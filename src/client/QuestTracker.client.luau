--!nonstrict
-- =================================================================================================
-- QUEST TRACKER -- the ACTIVE QUEST: one at a time, a green island to aim at, an arrow pointing at
-- it, and a banner that speaks up as you close in rather than sitting on screen forever.
-- =================================================================================================
-- WHY THIS IS ITS OWN FILE AND NOT PART OF PetFollow.
--   1. PetFollow sits at 195 of Luau's 200 locals per scope (see CLAUDE.md). A tracker needs state,
--      a pulse, an arrow loop and a banner scheduler; every one of those as a module local there
--      would push the file over the ceiling, at which point the WHOLE script silently never runs.
--   2. Tracking is not a pets-panel concern. The pulse is on the world, the arrow is on the flight
--      screen, and both have to keep working while the Pet Hub is shut.
--
-- WHAT THIS FILE DOES *NOT* OWN, deliberately:
--   * QUEST PROGRESS. The server counts pieces (PetSystem.foundCount) and persists it through
--     PlayerStats, and it always has. Progress is already independent of tracking -- get Broccoli to
--     2/3, track something else, come back, and it is still 2/3, because nothing here ever wrote it.
--   * QUEST COMPLETION / UNLOCKING THE PET. Also already server-side and already saved.
--   * THE GROUND TRAIL. GardenGuideTrail owns the chevrons and exposes _G.guideTrailTo(pos).
--   * BANNERS. NotifyCenter owns the top-centre lane and enforces one at a time. Every message here
--     goes through it, which is why a proximity ping can never land on top of an island arrival.
--
-- =================================================================================================
-- THE THREE SIGNALS, and why it is three and not one big HUD.
-- =================================================================================================
-- A permanent card telling you the same thing every frame stops being read within about a minute --
-- it becomes furniture, and it costs screen space on the one screen (flight) that has none spare.
-- So the information is split by how often it actually changes:
--
--   PULSE (constant, in the world) -- the destination itself glows green and breathes. No screen
--       space at all, readable from any distance, and it answers "which one is it" instantly.
--   ARROW (constant, tiny) -- a rotating pointer + distance. This is the only thing that must be
--       true every frame, because it changes every frame. It is deliberately ~64px and wordless.
--   BANNER (occasional) -- the detail: pet, objective, progress, island. Fires when you start
--       tracking, at distance milestones on the way in, and on arrival. Speaks when there is news.
--
-- TRACKING IS SESSION-LOCAL. Which quest you are pointed at is a display preference, not progress,
-- so it is not written to the DataStore -- rejoining starts you untracked with progress intact.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local Shared      = ReplicatedStorage:WaitForChild("Shared", 30)
local IslandOrder = Shared and Shared:FindFirstChild("IslandOrder") and require(Shared.IslandOrder) or nil

-- The same payload the Pet Hub's cards are built from. One source of truth for progress: if the panel
-- says 2/3 then so does the banner, because both read this.
local PetInventoryEvent = ReplicatedStorage:WaitForChild("PetInventoryEvent", 30)

--======================================================================
-- STATE
--======================================================================
local active     = nil    -- petId being tracked, or nil
local activeRow  = nil    -- newest quest payload row for it
local latestQ    = {}     -- [petId] = quest row, from the newest payload
local target     = nil    -- Vector3 island centre we are aiming at
local onIsland   = false  -- have we arrived (latched, so arrival announces once)

local GREEN = Color3.fromRGB( 90, 220, 120)
local INK   = Color3.fromRGB(  8,  28,  70)

--======================================================================
-- 1) THE ISLAND PULSE
--======================================================================
-- ONE Highlight, on the island's Model. Highlight is the right tool rather than recolouring parts:
-- it is non-destructive (it never touches a single BasePart's Color, so nothing has to be put back),
-- it follows the model if anything moves, and it costs one instance instead of hundreds of writes
-- across an island with 150+ parts.
--
-- FillTransparency stays high. A solid green island reads as broken, not as a marker -- the goal is a
-- tint that says "this one" while you can still see the place you are flying to.
-- Sweep FIRST, build second. The Highlight lives in Workspace, so it survives a script reload on its own --
-- and a sweep placed after the constructor would destroy the very instance this line is about to create.
for _, old in ipairs(Workspace:GetChildren()) do
	if old:IsA("Highlight") and old.Name == "QuestIslandPulse" then old:Destroy() end
	if old:IsA("BasePart") and old.Name == "QuestIslandShell" then old:Destroy() end
end

local pulse = Instance.new("Highlight")
pulse.Name = "QuestIslandPulse"
pulse.FillColor = GREEN
pulse.OutlineColor = Color3.fromRGB(180, 255, 200)
pulse.FillTransparency = 0.86
pulse.OutlineTransparency = 0.25
-- Occluded, NOT AlwaysOnTop: an always-on-top island would punch through everything in front of it,
-- including your own pet and the island you are standing on.
pulse.DepthMode = Enum.HighlightDepthMode.Occluded
pulse.Enabled = false
pulse.Parent = Workspace

-- Islands are named Island_<n>_<Name> in this place (Island_2_BrocolliBluff, typo and all -- see
-- CLAUDE.md). Matched on the NUMBER, so a renamed or misspelled island still resolves.
local function findIslandModel(n)
	if not n then return nil end
	local want = "^Island_" .. tostring(n) .. "_"
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.match(m.Name, want) then return m end
	end
	return nil
end

-- BREATHING, on a loop that checks it still owns the pulse each cycle. Tweens outlive whatever
-- started them, so a stale loop from a previous quest would fight the current one over the same
-- property -- the generation check is what stops two breaths at different rates.
local pulseGen = 0
-- ===== WHY A HIGHLIGHT ALONE DOES NOT WORK HERE =====
-- Roblox stops rendering a Highlight once its adornee is far enough from the camera -- the engine culls them
-- for performance and gives no warning when it does. That is fatal for THIS use: the whole point is to mark an
-- island you are not at yet, and in this game "not at yet" means 630 studs at the very least and up to 38,000
-- (island 1 to island 14). So the Highlight was almost always culled at exactly the distance it mattered, and
-- only ever appeared once you had basically arrived -- which reads as "the pulse does not work".
--
-- THE SHELL is what actually does the marking: a real Part, Neon green, sized to the island's own bounding box
-- and pulsing its Transparency. A Part is drawn at any distance, so the island genuinely glows from the bottom
-- of the tower. The Highlight is KEPT for close range, where it traces the island's actual silhouette and
-- looks far better than a box does.
--
-- The shell is client-local (never replicated), CanCollide and CanQuery false, so it cannot be stood on, shot
-- through, raycast against, or picked up by the ground checks the flight and build code do.
local shell = nil
local function destroyShell()
	if shell then shell:Destroy(); shell = nil end
end

local function startPulse(islandNum)
	local model = findIslandModel(islandNum)
	pulseGen = pulseGen + 1
	local myGen = pulseGen
	destroyShell()
	if not model then
		pulse.Enabled = false
		warn("[QuestTracker] no Workspace model matching 'Island_" .. tostring(islandNum)
			.. "_' -- the island cannot be highlighted. Check the model's name.")
		return
	end

	pulse.Adornee = model
	pulse.Enabled = true

	-- Sized from the island itself, so a small island gets a small glow and a sprawling one gets a big one.
	local okBox, boxCF, boxSize = pcall(function() return model:GetBoundingBox() end)
	if okBox and boxCF and boxSize then
		local s = Instance.new("Part")
		s.Name = "QuestIslandShell"
		s.Shape = Enum.PartType.Ball
		-- A ball on the LARGEST dimension: it has to contain the island from every angle, and a box read as a
		-- crate around the island rather than as a glow.
		local d = math.max(boxSize.X, boxSize.Y, boxSize.Z) * 1.15
		s.Size = Vector3.new(d, d, d)
		s.CFrame = boxCF
		s.Anchored = true
		s.CanCollide = false
		s.CanQuery = false
		s.CanTouch = false
		s.CastShadow = false
		s.Material = Enum.Material.Neon
		s.Color = GREEN
		s.Transparency = 0.88
		s.Parent = Workspace
		shell = s
	end

	task.spawn(function()
		while pulseGen == myGen do
			local up = { FillTransparency = 0.72, OutlineTransparency = 0.05 }
			TweenService:Create(pulse, TweenInfo.new(0.85, Enum.EasingStyle.Sine), up):Play()
			if shell then
				TweenService:Create(shell, TweenInfo.new(0.85, Enum.EasingStyle.Sine),
					{ Transparency = 0.80 }):Play()
			end
			task.wait(0.85)
			if pulseGen ~= myGen then break end
			TweenService:Create(pulse, TweenInfo.new(0.85, Enum.EasingStyle.Sine),
				{ FillTransparency = 0.92, OutlineTransparency = 0.4 }):Play()
			if shell then
				TweenService:Create(shell, TweenInfo.new(0.85, Enum.EasingStyle.Sine),
					{ Transparency = 0.93 }):Play()
			end
			task.wait(0.85)
		end
	end)
	print(("[QuestTracker] pulsing '%s' (island %s)"):format(model.Name, tostring(islandNum)))
end

local function stopPulse()
	pulseGen = pulseGen + 1   -- invalidates any running breath loop
	pulse.Enabled = false
	pulse.Adornee = nil
	destroyShell()
end

--======================================================================
-- 2) THE ARROW
--======================================================================
-- EXACTLY ONE OF THESE, EVER. Rojo only ADDS -- a stale copy of this script baked into the place file runs
-- alongside the synced one (there are ~21 such duplicates here; see CLAUDE.md), and two copies would mean two
-- arrow chips, two Highlights and two Heartbeat loops fighting over the same quest. Any earlier
-- QuestTrackerHud is destroyed before this one is built, so the newest copy wins and the older one is left
-- driving an instance that no longer exists.
for _, old in ipairs(PlayerGui:GetChildren()) do
	if old:IsA("ScreenGui") and old.Name == "QuestTrackerHud" then old:Destroy() end
end
local gui = Instance.new("ScreenGui")
gui.Name = "QuestTrackerHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 90          -- under menus (100+), over the world HUD
gui.Enabled = false
gui.Parent = PlayerGui

-- LEFT EDGE, mid-height: the one column that is reliably empty in flight. Top-centre is the banner
-- lane, top-right the currency capsule and gear, bottom-centre the gas meter and fart button, and the
-- right side is the button rail.
local chip = Instance.new("TextButton")
chip.Name = "QuestArrow"
chip.AnchorPoint = Vector2.new(0, 0.5)
chip.Position = UDim2.new(0, 14, 0.44, 0)
-- 64x92, not 64x78. RailGuard's stray-launcher sweep treats anything within 20% of square on the left edge
-- as a rail button, and 64x78 was inside that by 1.6px. It is exempted by name now too (see NEVER_TOUCH), but
-- a shape that is unambiguously a tall chip means the next heuristic to come along does not catch it either.
chip.Size = UDim2.fromOffset(64, 64)
chip.BackgroundColor3 = Color3.fromRGB(16, 60, 140)
chip.BackgroundTransparency = 0.12
chip.AutoButtonColor = false
chip.Text = ""
chip.BorderSizePixel = 0
chip.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = chip
	local s = Instance.new("UIStroke"); s.Color = GREEN; s.Thickness = 2.5; s.Parent = chip
end

-- The pointer. A rotated glyph, not an image: it has to spin smoothly through 360 degrees and an
-- ImageLabel would need an asset that cannot be inlined.
local arrow = Instance.new("TextLabel")
arrow.BackgroundTransparency = 1
-- Centred now that the label below it is gone, so the chip is just the pointer.
arrow.Size = UDim2.fromOffset(44, 44)
arrow.Position = UDim2.new(0.5, 0, 0.5, 0)
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.Font = Enum.Font.FredokaOne
arrow.Text = "\xE2\x9E\xA4"          -- heavy arrow, drawn pointing RIGHT, so 0 deg = east
arrow.TextSize = 34
arrow.TextColor3 = GREEN
arrow.Parent = chip
do
	local s = Instance.new("UIStroke"); s.Color = INK; s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; s.Parent = arrow
end

-- NO DISTANCE READOUT. There used to be a "1.2k" counter under the arrow, ticking down every frame as
-- you climbed. It turned a wordless pointer into a number to stare at, and a number that only ever says
-- "not yet" is a worse companion on a long climb than no number at all. The arrow says WHICH WAY, the
-- green island says WHICH ONE, and neither needs a running total to do its job.

-- SCREEN-SPACE, NOT YAW. A compass that only reads left/right is useless in this game: the islands
-- are a tower, and island 13 is 31,000 studs STRAIGHT UP from island 1. Projecting the target into
-- viewport space and pointing at it there means the arrow points up when the answer is "up".
local function aimArrow()
	local cam = Workspace.CurrentCamera
	if not (cam and target) then return end
	local sp = cam:WorldToViewportPoint(target)
	local centre = cam.ViewportSize / 2
	local v = Vector2.new(sp.X, sp.Y) - centre
	-- sp.Z < 0 means the target is BEHIND the camera, where the projection mirrors: without the flip
	-- the arrow points confidently in exactly the wrong direction whenever you turn away from it.
	if sp.Z < 0 then v = -v end
	if v.Magnitude < 1 then v = Vector2.new(0, -1) end   -- dead centre: pick "up" over a jitter spin
	-- atan2(y, x) with the glyph drawn pointing east (0 deg = +X), which is exactly this basis.
	arrow.Rotation = math.deg(math.atan2(v.Y, v.X))
end

--======================================================================
-- 3) THE BANNER
--======================================================================
-- Through NotifyCenter, never a ScreenGui of its own: it owns the top-centre lane and enforces one
-- banner at a time. A second banner built here is precisely how two end up overlapping.
-- THE SECOND CARD IN THE LANE, AND WHY IT APPEARED.
--
-- PetQuestUI.Tracker (PetFollow) is a PERSISTENT quest banner in this same top-centre strip, shown while a
-- quest minigame is live. It already knows to get out of the way -- its gate yields whenever
-- NotifyCenter.isBusy() is true -- but that gate is driven by a 0.15s POLL, and PetFollow's own comment on it
-- says the quiet part out loud: "that gap is long enough to see both cards on screen".
--
-- So pushing a banner and walking away means up to 150ms with the tracker still parked in the lane and our
-- banner drawn over it: two stacked quest cards. PetFollow already solved this for its own discovery popup by
-- publishing _G.__petTrackerApply and calling it the instant the popup takes the lane. This does the same --
-- same lane, same problem, same fix, rather than a second mechanism that has to be kept in step with it.
--
-- Deferred, not immediate: push() sets its "showing" state during the call, so re-checking on the next resume
-- reads the state AFTER the banner exists rather than the instant before.
local function yieldLane()
	if _G.__petTrackerApply then
		task.defer(function() pcall(_G.__petTrackerApply) end)
	end
end

local function say(text, sub, colour, dur)
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(_G.NotifyCenter.push, {
			text = text, sub = sub, color = colour or Color3.fromRGB(60, 170, 110),
			priority = 60, duration = dur or 3.2,
		})
		yieldLane()
	elseif _G.showHudBanner then
		pcall(_G.showHudBanner, text .. (sub and ("  --  " .. sub) or ""), colour, dur or 3.2)
	end
end

-- The quest line, rebuilt each time so it always carries CURRENT progress.
local function questSub()
	local r = activeRow
	if not r then return nil end
	local total = math.max(1, tonumber(r.total) or 1)
	local found = math.clamp(tonumber(r.found) or 0, 0, total)
	return tostring(r.desc or "") .. "   " .. found .. " / " .. total
end

-- NO PROGRESS BANNERS. There were four of these -- fired at 75/50/25/10% of the way in, each reading
-- "Halfway there!  4.1k to go". Same reasoning as the readout above: they were a countdown of how far you
-- still were, interrupting the climb four times to say you had not arrived yet. What is left speaks only
-- when something actually happens: you start tracking, you land, you finish.

local function checkProximity(hrp)
	if not (target and activeRow) then return end
	local d = (hrp.Position - target).Magnitude

	-- ARRIVAL. Latched, so standing on the island does not re-announce every second.
	if d <= 420 then
		if not onIsland then
			onIsland = true
			say("\xF0\x9F\x93\x8D " .. tostring(activeRow.islandName or "Arrived"), questSub(),
				Color3.fromRGB(70, 190, 110), 4.5)
			-- The long-haul TRAIL is done: the island's own NPC arrow (NpcGuideArrow) points at the actual
			-- objective better than a marker on the island centre, so hand that over rather than compete.
			--
			-- THE PULSE STAYS ON. It marks WHICH QUEST YOU ARE ON, not how far you have left to fly, so it
			-- has to hold from the bottom of the tower right through standing on the island -- including the
			-- case of sitting on island 1 with island 2 tracked. It is only ever switched off by untracking
			-- or by finishing the quest.
			wpTarget = nil
			if _G.guideTrailClear then pcall(_G.guideTrailClear) end
		end
		return
	end

	-- LEFT AGAIN (fell off, or launched for the next crossing): the ground trail comes back. The pulse was
	-- never switched off, so there is nothing to restart -- and restarting it here is what made it visibly
	-- blink every time the distance crossed the arrival radius.
	if onIsland then
		onIsland = false
		wpTarget = target
	end

end

--======================================================================
-- WAYPOINT (the ground trail)
--======================================================================
-- RE-ASSERTED EVERY FRAME, not set once. guideTrailTo is documented as "meant to be called every
-- frame by whoever owns the target: it is cheap, and it is self-correcting -- stop calling it and the
-- trail puts itself away". The self-correcting half is a feature here: when this file stops driving
-- it, the trail retires itself with no teardown to get wrong.
local wpTarget = nil

--======================================================================
-- COMPLETION
--======================================================================
local completeSound = Instance.new("Sound")
completeSound.Name = "QuestCompleteSound"
completeSound.SoundId = "rbxassetid://4612378364"
completeSound.Volume = 0.8
completeSound.PlaybackSpeed = 1.05
completeSound.Parent = SoundService

--======================================================================
-- PUBLIC API -- what the Pet Hub's quest cards call
--======================================================================
local function teardown()
	active, activeRow, target = nil, nil, nil
	onIsland = false
	wpTarget = nil
	stopPulse()
	gui.Enabled = false
	if _G.guideTrailClear then pcall(_G.guideTrailClear) end
	-- Hand the lane back at once rather than leaving PetQuestUI.Tracker hidden for up to another poll.
	yieldLane()
end

_G.questTrackGet = function() return active end

_G.questTrackClear = function(silent)
	if not active then return end
	teardown()
	if not silent and _G.questCardsRefresh then pcall(_G.questCardsRefresh) end
end

-- ISLAND CENTRES come from the shared IslandOrder table -- the SAME table PlayerStats positions the
-- island models from. A second copy of these numbers is how an arrow ends up pointing at where an
-- island used to be.
local function islandPos(n)
	if not (IslandOrder and IslandOrder.SLOT_POS and n) then return nil end
	local p = IslandOrder.SLOT_POS[n]
	if not p then return nil end
	if typeof(p) == "Vector3" then return p end
	-- LOWERCASE x/y/z. IslandOrder stores rows as { x = 120, y = 780, z = 60 } -- reading p.X/p.Y/p.Z
	-- (capitalised, as on a Vector3) silently gives nil for all three, and the fallback chain then produced
	-- Vector3.new(0, 0, 0). Everything downstream believed the island was at the world ORIGIN: the arrow
	-- pointed there, the distances were nonsense, and -- because island 1 spawns barely 270 studs from the
	-- origin, inside the 420-stud arrival radius -- checkProximity declared "arrived" on the very first frame
	-- and switched the pulse straight back off. That is the whole bug.
	--
	-- The capitalised and array forms are kept as fallbacks so this still works if the table is ever changed
	-- to Vector3s or to {x, y, z} positional rows.
	local x = p.x or p.X or p[1] or 0
	local y = p.y or p.Y or p[2] or 0
	local z = p.z or p.Z or p[3] or 0
	return Vector3.new(x, y, z)
end

-- `row` is the quest entry straight off the inventory payload, so the banner cannot describe the
-- quest differently from the card that started it.
_G.questTrackSet = function(petId, row)
	if type(petId) ~= "string" then return false end
	row = row or latestQ[petId]
	if not row then return false end
	if row.status == "done" then return false end   -- nothing to walk toward

	-- ONE AT A TIME: a new pick silently replaces the old, and the card refresh at the end flips the
	-- previous row's button back to TRACK QUEST.
	teardown()
	active, activeRow = petId, row
	onIsland = false

	local n = tonumber(row.island)
	target = islandPos(n)
	-- Logged because the previous round of this was un-diagnosable from a play session: if the pulse or the
	-- arrow is missing, this line says immediately whether the island number and its position resolved at all.
	print(("[QuestTracker] track %s -> island %s, pos %s"):format(
		tostring(petId), tostring(n), target and tostring(target) or "NIL (no SLOT_POS entry)"))

	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if target and hrp then
		wpTarget = target
		gui.Enabled = true
		startPulse(n)
		say("\xF0\x9F\x8E\xAF Now tracking: " .. string.upper(tostring(row.displayName or petId)),
			questSub(), Color3.fromRGB(70, 190, 110), 4)
	else
		-- No mapped position (a realm this table does not cover, or the character is still loading).
		-- Say so rather than showing an arrow that points at the origin.
		say("\xF0\x9F\x8E\xAF Now tracking: " .. string.upper(tostring(row.displayName or petId)),
			tostring(row.islandName or ""), Color3.fromRGB(70, 190, 110), 4)
	end

	if _G.questCardsRefresh then pcall(_G.questCardsRefresh) end
	return true
end

_G.questRowFor = function(petId) return latestQ[petId] end

--======================================================================
-- WIRING
--======================================================================
-- Tap the arrow -> back to the quest list. A persistent pointer should also be the shortest route
-- back to the thing it points at.
chip.MouseButton1Click:Connect(function()
	if _G.playUIClick then pcall(_G.playUIClick) end
	if _G.togglePetHub then pcall(_G.togglePetHub) end
	task.defer(function()
		if _G.PetHub and _G.PetHub.showPage then pcall(_G.PetHub.showPage, "quests") end
	end)
end)

-- THE PAYLOAD IS THE ONLY SOURCE OF PROGRESS. It arrives whenever the server changes anything about
-- this player's pets, which includes every piece picked up -- so a banner fired a moment later
-- carries current numbers without polling and without a second counter that could drift.
if PetInventoryEvent then
	PetInventoryEvent.OnClientEvent:Connect(function(payload)
		local qs = (type(payload) == "table" and payload.quests) or nil
		if type(qs) ~= "table" then return end
		latestQ = qs
		if not active then return end

		local row = qs[active]
		if not row then _G.questTrackClear() return end

		local wasDone = activeRow and activeRow.status == "done"
		activeRow = row

		if row.status == "done" and not wasDone then
			pcall(function() completeSound:Play() end)
			say("\xE2\x9C\xA8 QUEST COMPLETE!", "Unlocked " .. tostring(row.displayName or "a pet") .. "!",
				Color3.fromRGB(70, 190, 110), 4.5)
			if _G.hapticPulse then pcall(_G.hapticPulse, "success") end
			-- Captured, not re-read. `active` can change during the hold (the player switches quest from the
			-- panel), and clearing on a bare "is anything tracked" would drop the quest they just picked.
			local finished = active
			task.delay(2.5, function()
				if active == finished then _G.questTrackClear() end
			end)
		end
	end)
end

-- ONE loop drives the arrow, the trail and the proximity checks. They all need the same root part and
-- the same position read, so doing them together means one lookup per frame instead of three.
RunService.Heartbeat:Connect(function()
	if not active then return end
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if wpTarget and _G.guideTrailTo then pcall(_G.guideTrailTo, wpTarget) end
	if target then
		aimArrow()
		checkProximity(hrp)
	end
end)

print("[QuestTracker] ready -- one active quest: the island pulses green, a rotating arrow + distance "
	.. "points at it, and a banner fires when you START tracking, when you LAND and when you FINISH "
	.. "(the four 75/50/25/10% progress banners are gone). "
	.. "Progress and unlocks stay server-side.")
