-- ============================================================================
-- ONE-TIME COMMUNITY GARDEN CINEMATIC INTRO
-- ============================================================================
-- Plays the FIRST time a brand-new player selects Island 1 from the island-select
-- menu. The SERVER decides whether to play it (gated on the saved "SeenGardenIntro"
-- flag) and fires GardenIntroEvent; this script runs the cutscene and, when it
-- finishes, fires GardenIntroDoneEvent back so the server sets+saves the flag.
-- Once seen, it never plays again. (lando5485 is force-reset server-side each join
-- so it replays for testing.) NOT skippable.
--
-- Flow: lock controls + hide HUD -> cinematic camera smoothly pans between the
-- Gardener, the cow (EasterCow) and the pig (WanderingPig), each auto-advancing its
-- chat-bubble lines on a timer (the cow and pig also MOO/OINK on their noise lines -- see ANIMAL NOISES) -> ISLAND FLYOVER (Island 1 from above, then a side
-- view up the island stack 2..14, ending bottom-up on the black hole) -> return the
-- camera to the player, restore everything. Any NPC/island that can't be found is
-- skipped gracefully; existing garden/NPC behaviour is left intact afterwards.
-- SKIPPABLE: a SKIP button fades in a few seconds in (SKIP_AFTER) and cancels the
-- cinematic immediately when pressed (restores camera/controls/HUD and notifies the server).
-- ============================================================================

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local StarterGui       = game:GetService("StarterGui")
local Workspace        = game:GetService("Workspace")
local SoundService     = game:GetService("SoundService")
local Debris           = game:GetService("Debris")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GardenIntroEvent     = ReplicatedStorage:WaitForChild("GardenIntroEvent", 30)
local GardenIntroDoneEvent = ReplicatedStorage:WaitForChild("GardenIntroDoneEvent", 30)

-- ---- DIALOGUE -------------------------------------------------------------
-- INTRO ONLY: short, fast-reading lines. Farmer/Cow/Pig all have the SAME number of slides (4) -- keep them
-- short (a few words each) and equal in count. The bean-stand FARMER speaks FIRST, then the garden NPCs.
local FARMER_LINES = {
	"Welcome to Fart to Float!",
	"Grab some beans!",
	"Explore the islands!",
	"Visit our farm friends!",
}
local GARDENER_LINES = {
	"Hi! Welcome to the garden! \xF0\x9F\x8C\xB1",
	"This is where everything grows.",
	"Do tasks to earn rewards!",
	"Come see me when you're ready!",
	"Meet my friends for some tips...",
}
local COW_LINES = {
	"Moo! Welcome!",
	"Got any hay?",
	"Moo moo!",
	"See ya 'round!",
}
local PIG_LINES = {
	"Oink! Welcome!",
	"Got any snacks?",
	"Oink oink!",
	"Come back soon!",
}

-- ---- ANIMAL NOISES --------------------------------------------------------
-- The cow MOOS and the pig OINKS during their own segments. The bubbles are silent text, and two farm animals
-- visibly mouthing "Moo!" / "Oink!" at the camera without a sound was the one beat of the cinematic that read
-- as unfinished -- the lines are already written as noises, so the audio just has to exist.
--
-- A cry fires on any line that STARTS with the animal's own word, which today is lines 1 and 3 of each set
-- above ("Moo! Welcome!" / "Moo moo!", "Oink! Welcome!" / "Oink oink!"). Deliberately derived from the text
-- rather than a second list of indices: reword the lines and the noises follow, with nothing to keep in sync.
-- Two per animal across an 8s window is enough to register as a farm and short of a barnyard.
--
-- WHERE THE ASSET COMES FROM, in order:
--   1. `reuse` -- a Sound the animal is ALREADY carrying. EasterEggManager builds the cow with a "MooSound"
--      on its body for the ambient 15-40s moo, so setting that script's MOO_SOUND_ID lights up the ambient
--      moo AND this one from a single place. Skipped if the sound is absent or its SoundId is still blank.
--   2. `id` -- a fallback asset for animals with no sound of their own (the pig has none: SquirrelEasterEgg
--      builds WanderingPig without one).
-- BOTH blank => that animal simply stays quiet and the rest of the cinematic is untouched. Same convention as
-- EasterEggManager's MOO_SOUND_ID and Monsoon's ROAR_SOUND_ID: no asset is a silent no-op, never an error.
-- `plays` is HOW MANY TIMES the animal cries during its own segment, spread evenly across that
-- segment's window. It replaced a rule that fired on any bubble line starting with the animal's own
-- word: that read nicely but the count was a side effect of how the lines happened to be worded (two
-- each, today), so "the cow should moo once" was not something the config could actually say.
local COW_CRY = { reuse = "MooSound", id = "rbxassetid://124453455193367", plays = 1, volume = 0.85, pitch = 1.00 }
local PIG_CRY = {                     id = "rbxassetid://855134280",       plays = 3, volume = 0.85, pitch = 1.00 }

-- TOTAL on-screen window (s) per NPC — ALL of that NPC's lines play within this window, divided evenly
-- across them (auto-advancing). The camera holds on the NPC for the whole window before panning on.
local FARMER_WINDOW   = 8   -- ~2s per line (4 lines) so each is readable
local GARDENER_WINDOW = 9
local COW_WINDOW      = 8
local PIG_WINDOW      = 8
local PAN_TIME        = 0.9  -- camera tween between subjects (snappier)
local SKIP_AFTER      = 12   -- seconds before the SKIP button becomes active

-- ---- NPC FINDERS (robust; return nil if absent) ---------------------------
local function findGardener()
	local build = Workspace:FindFirstChild("CommunityGardenBuild", true)
	if build then
		local props = build:FindFirstChild("GardenProps")
		local g = props and props:FindFirstChild("Gardener")
		if g and g:IsA("Model") then return g end
		for _, d in ipairs(build:GetDescendants()) do
			if d:IsA("Model") and d:GetAttribute("GardenerNPC") then return d end
		end
	end
	local byName = Workspace:FindFirstChild("Gardener", true)
	if byName and byName:IsA("Model") then return byName end
	return nil
end
-- the bean-stand Farmer (cloned into Workspace.TutorialNPCs as "Farmer"; NOT the scarecrow "Farmer2").
local function findFarmer()
	local folder = Workspace:FindFirstChild("TutorialNPCs")
	local f = folder and folder:FindFirstChild("Farmer")
	if f and f:IsA("Model") then return f end
	local byName = Workspace:FindFirstChild("Farmer", true)
	if byName and byName:IsA("Model") then return byName end
	return nil
end
local function findCow() return Workspace:FindFirstChild("EasterCow", true) end
local function findPig() return Workspace:FindFirstChild("WanderingPig", true) end

-- ---- ISLAND + BLACK-HOLE FINDERS (for the flyover) ------------------------
local ISLAND_NAMES = {
	"Bean Farm","Broccoli Bluff","Cabbage Cliffs","Turnip Tranquil","Coconut Cove","Bread Board",
	"Pasta Peak","Popcorn Pinnacle","Milk Marsh","Butter Swamp","Ice Cream Isle","Burger Bluff",
	"Burrito Barrens","Pizza Palms",
}
-- islands are top-level Workspace models named "Island_<n>_..." (same lookup WorldClient uses); fall
-- back to the exact display name. Returns nil if the island isn't in the world yet (segment is skipped).
local function findIslandModel(n)
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") and obj.Name:match("^Island_" .. n .. "_") then return obj end
	end
	local exact = Workspace:FindFirstChild(ISLAND_NAMES[n])
	if exact and exact:IsA("Model") then return exact end
	return nil
end
local function findBlackHole() return Workspace:FindFirstChild("BlackHole", true) end

-- center + a size clamped against stray far-flung parts (keeps framing distances sane).
local function modelCenterSize(model)
	local cf, size = model:GetBoundingBox()
	local sx = math.min(size.X, 500); local sy = math.min(size.Y, 500); local sz = math.min(size.Z, 500)
	return cf.Position, Vector3.new(sx, sy, sz)
end

-- ISLAND 1 from ABOVE, looking down (slight horizontal offset so it isn't a degenerate straight-down).
local function islandTopCFrame(model)
	local center, size = modelCenterSize(model)
	local span = math.max(size.X, size.Z)
	local height = span * 1.4 + 130
	local camPos = center + Vector3.new(0, height, span * 0.25 + 30)
	return CFrame.lookAt(camPos, center)
end

-- SIDE VIEW of an island, from a consistent world direction so travelling up the stack reads smoothly.
local function islandSideCFrame(model)
	local center, size = modelCenterSize(model)
	local span = math.max(size.X, size.Z)
	local dist = span * 1.3 + 100
	local dir = Vector3.new(1, 0, 0.4).Unit
	local camPos = center + dir * dist + Vector3.new(0, size.Y * 0.2, 0)
	return CFrame.lookAt(camPos, center)
end

-- BOTTOM-UP view of the black hole (camera below, looking up; slight offset avoids a degenerate up).
local function blackHoleCFrame(model)
	local center, size = modelCenterSize(model)
	local span = math.max(size.X, size.Y, size.Z)
	local dist = span * 0.9 + 200
	local camPos = center - Vector3.new(0, dist, 0) + Vector3.new(0, 0, dist * 0.25)
	return CFrame.lookAt(camPos, center)
end

-- poll for a model up to `timeout` seconds (NPCs build asynchronously after the stands).
local function waitForModel(finder, timeout)
	local m = finder()
	local t = 0
	while not m and t < timeout do
		task.wait(0.25); t = t + 0.25; m = finder()
	end
	return m
end

local function subjectHead(model)
	return model:FindFirstChild("Head") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

-- camera CFrame that frames `model` from the front (uses its facing), aimed at its head.
local function frameCFrame(model, dist)
	local pivot = model:GetPivot()
	local look = pivot.LookVector
	if look.Magnitude < 0.1 then look = Vector3.new(0, 0, 1) end
	local head = model:FindFirstChild("Head")
	local targetPos = head and head.Position or (pivot.Position + Vector3.new(0, 2, 0))
	local camPos = targetPos + look * dist + Vector3.new(0, 1.6, 0)
	return CFrame.lookAt(camPos, targetPos)
end

-- ---- CHAT BUBBLE (mirrors the gardener's existing speech-bubble look) ------
local function makeBubble(model)
	local head = subjectHead(model)
	if not head then return nil, nil end
	local bb = Instance.new("BillboardGui")
	bb.Name = "IntroBubble"
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(300, 96)
	bb.StudsOffset = Vector3.new(0, 3.4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 1000
	bb.LightInfluence = 0

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Parent = bb
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = panel
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(40, 40, 46); stroke.Thickness = 2; stroke.Parent = panel

	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.92, 0.9)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(34, 34, 40)
	-- BIGGER TEXT, SAME BUBBLE: scale the text up to fill the (unchanged) bubble, wrapping so long lines still
	-- fit. The size constraint caps short lines so they stay tidy while still being notably bigger than before.
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = ""
	label.Parent = panel
	local sizeCap = Instance.new("UITextSizeConstraint")
	sizeCap.MaxTextSize = 30 -- was a flat 18; lines now scale up toward this within the same bubble
	sizeCap.MinTextSize = 14
	sizeCap.Parent = label

	bb.Parent = head
	return bb, label
end

-- ---- CAMERA TWEEN ---------------------------------------------------------
local function tweenCam(camera, cf, dur)
	local tw = TweenService:Create(camera, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {CFrame = cf})
	tw:Play()
	return tw
end

-- ===========================================================================
local playing = false
local function playIntro()
	if playing then return end
	playing = true
	print("[GARDEN INTRO] cinematic START")

	-- BLACK TRANSITION: drop a FULLY BLACK full-screen overlay the MOMENT the cinematic starts (right when
	-- Island 1 is clicked). It covers the menu closing + the camera repositioning, holds ~1s, then fades out to
	-- reveal the FARMER already framed (he speaks first). Top-most ScreenGui; forward-declared so cleanup() removes it on error/skip.
	local blackStart = os.clock()
	local coverGui = Instance.new("ScreenGui")
	coverGui.Name = "GardenIntroCover"
	coverGui.IgnoreGuiInset = true
	coverGui.ResetOnSpawn = false
	coverGui.DisplayOrder = 1500000 -- above the letterbox + title card (skip button at 2000000 sits above, fades in at SKIP_AFTER)
	coverGui.Parent = playerGui
	local coverBlack = Instance.new("Frame")
	coverBlack.Size = UDim2.fromScale(1, 1)
	coverBlack.Position = UDim2.fromScale(0, 0)
	coverBlack.BackgroundColor3 = Color3.new(0, 0, 0)
	coverBlack.BackgroundTransparency = 0 -- fully black immediately
	coverBlack.BorderSizePixel = 0
	coverBlack.ZIndex = 10
	coverBlack.Parent = coverGui

	-- ===================== FLASH PROBE (diagnostic; set FLASH_PROBE=false to silence) =====================
	-- The boot log can tell us WHEN things happen but not WHAT THE RENDERER ACTUALLY DREW, which is the one
	-- thing that matters for "a split second of the island right after PLAY". So sample it per frame: is an
	-- opaque, full-screen GuiObject actually present this frame, and where is the camera pointing?
	--
	-- An UNCOVERED frame is a frame the player could have seen the world through. If the report says 0 of them,
	-- the leak is NOT a missing cover and the camera columns say whether we were still framed on the spawn.
	local FLASH_PROBE = true
	local probeStop   -- forward-declared; doSegment calls this when the farmer scene actually takes over
	if FLASH_PROBE then
		local cam        = workspace.CurrentCamera
		local t0         = os.clock()
		local frames, uncovered = 0, 0
		local samples    = {}          -- up to 8 uncovered frames, recorded for the report
		local firstBad, lastBad        -- seconds since PLAY

		-- Cheap depth-limited sweep: a full-screen blackout is always a direct child or grandchild of a
		-- ScreenGui, never buried deeper, so this stays affordable at 60fps (a full GetDescendants() of
		-- PlayerGui every frame would itself cause the stutter we are trying to measure).
		local function screenIsCovered()
			local vp = cam.ViewportSize
			for _, sg in ipairs(playerGui:GetChildren()) do
				if sg:IsA("ScreenGui") and sg.Enabled then
					for _, a in ipairs(sg:GetChildren()) do
						if a:IsA("GuiObject") and a.Visible then
							if a.BackgroundTransparency <= 0.02
								and a.AbsoluteSize.X >= vp.X * 0.9 and a.AbsoluteSize.Y >= vp.Y * 0.9 then
								return true, sg.Name .. "." .. a.Name
							end
							for _, b in ipairs(a:GetChildren()) do
								if b:IsA("GuiObject") and b.Visible and b.BackgroundTransparency <= 0.02
									and b.AbsoluteSize.X >= vp.X * 0.9 and b.AbsoluteSize.Y >= vp.Y * 0.9 then
									return true, sg.Name .. "." .. a.Name .. "." .. b.Name
								end
							end
						end
					end
				end
			end
			return false, nil
		end

		local conn
		conn = RunService.RenderStepped:Connect(function()
			frames = frames + 1
			local t = os.clock() - t0
			local covered = screenIsCovered()
			if not covered then
				uncovered = uncovered + 1
				firstBad = firstBad or t
				lastBad = t
				if #samples < 8 then
					local p = cam.CFrame.Position
					samples[#samples + 1] = ("      t=%.3fs  camType=%s  camPos=(%d, %d, %d)")
						:format(t, tostring(cam.CameraType):gsub("Enum.CameraType.", ""), p.X, p.Y, p.Z)
				end
			end
		end)

		probeStop = function(reason)
			if not conn then return end
			conn:Disconnect(); conn = nil
			local total = os.clock() - t0
			print("========== [GARDEN INTRO] FLASH PROBE ==========")
			print(("  window: PLAY -> %s   (%.2fs, %d frames)"):format(reason, total, frames))
			if uncovered == 0 then
				print("  UNCOVERED FRAMES: 0 -- an opaque full-screen cover was present EVERY frame.")
				print("  => the flash is NOT the world showing through a gap. Look at what the fade reveals instead")
				print("     (camera framing, or a HUD element drawn over the cinematic).")
			else
				print(("  UNCOVERED FRAMES: %d of %d  (%.0f%%)  first=%.3fs  last=%.3fs  ~%.0fms of visible world")
					:format(uncovered, frames, uncovered / math.max(1, frames) * 100,
						firstBad or 0, lastBad or 0, ((lastBad or 0) - (firstBad or 0)) * 1000))
				print("  the camera during those frames (Custom = default player camera = you saw the spawn):")
				for _, s in ipairs(samples) do print(s) end
			end
			print("===============================================")
		end
	end
	-- =================== END FLASH PROBE ===================

	-- wait for the character (blocks BEHIND the black; selecting island 1 spawns it server-side)
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp  = char:WaitForChild("HumanoidRootPart", 10)
	local hum  = char:FindFirstChildWhichIsA("Humanoid")
	local camera = Workspace.CurrentCamera

	-- ---- snapshot state we will restore ----
	local prevCamType    = camera.CameraType
	local prevCamSubject = camera.CameraSubject
	local startCF        = camera.CFrame
	local wasAnchored    = hrp and hrp.Anchored
	local guiGuards      = {}  -- { {gui=, wasEnabled=, conn=}, ... } every non-own ScreenGui, force-hidden for the cinematic
	local guardedSet     = {}  -- [gui] = true (dedupe)
	local flyoverIslands = nil -- island models hidden during the flyover (so only the current island shows); restored at the end
	local controls
	local coreState      = {}
	local coreTypes = {
		Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health,
		Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Chat, Enum.CoreGuiType.EmotesMenu,
	}

	-- ---- SKIP support (cooperative cancel) ----
	local skipped = false  -- flips true when the SKIP button is pressed; the helpers below bail the sequence
	local skipGui          -- the SKIP button's own ScreenGui (forward-declared; torn down in cleanup)
	local activeTween      -- the in-flight camera tween, so a skip can cancel it immediately
	-- interruptible wait: returns true if SKIP fired during the wait (callers bail the sequence on true).
	local function sleep(dur)
		local elapsed = 0
		while elapsed < dur and not skipped do
			elapsed += task.wait()
		end
		return skipped
	end
	-- interruptible camera pan: tween to cf over dur; returns true if SKIP fired (tween cancelled).
	local function panTo(cf, dur)
		if skipped then return true end
		local tw = TweenService:Create(camera, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {CFrame = cf})
		activeTween = tw
		local done = false
		tw.Completed:Connect(function() done = true end)
		tw:Play()
		while not done and not skipped do task.wait() end
		if skipped then pcall(function() tw:Cancel() end) end
		activeTween = nil
		return skipped
	end

	-- ---- LOCK CONTROLS + HIDE ALL HUD (no letterbox bars) ----
	-- Hide EVERY HUD/icon ScreenGui (coins, settings gear, left sidebar buttons, right stats panel, gas meter,
	-- fart button — all of it) for a completely clean cinematic view. We disable the existing ones AND watch for
	-- any added during the intro (HUD scripts build/rebuild async, and ResetOnSpawn re-adds them when the
	-- character spawns mid-intro), skipping only our OWN overlays (named "GardenIntro*"). All restored at the end.
	local worldRestored = false
	local hudConn
	local function isOwnGui(g) return g.Name:sub(1, 11) == "GardenIntro" end
	-- Guard a ScreenGui: force it OFF now and KEEP it off for the whole cinematic. If its own script (or a
	-- banner / reminder / toast / respawn) re-enables it mid-intro, the Enabled watcher slaps it back off and
	-- remembers it "wanted" to be on, so it's restored correctly at the end. Catches everything, even GUIs that
	-- start disabled and turn on later, or re-enable themselves on a timer.
	local function hideGui(g)
		if not (g:IsA("ScreenGui")) or isOwnGui(g) or guardedSet[g] then return end
		guardedSet[g] = true
		local rec = { gui = g, wasEnabled = g.Enabled }
		g.Enabled = false
		rec.conn = g:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not worldRestored and g.Enabled then rec.wasEnabled = true; g.Enabled = false end -- it wanted on -> restore on later
		end)
		guiGuards[#guiGuards + 1] = rec
	end
	for _, g in ipairs(playerGui:GetChildren()) do hideGui(g) end
	hudConn = playerGui.ChildAdded:Connect(function(g)
		if g:IsA("ScreenGui") then task.defer(function() if not worldRestored then hideGui(g) end end) end -- catch HUD/banners spawned mid-intro
	end)
	for _, t in ipairs(coreTypes) do
		pcall(function() coreState[t] = StarterGui:GetCoreGuiEnabled(t); StarterGui:SetCoreGuiEnabled(t, false) end)
	end
	pcall(function()
		local pm = player:WaitForChild("PlayerScripts", 5) and player.PlayerScripts:WaitForChild("PlayerModule", 5)
		if pm then controls = require(pm):GetControls(); controls:Disable() end
	end)
	if hrp then hrp.Anchored = true end

	-- ---- HIDE ALL PLAYER CHARACTERS (local + everyone else) for a clean cinematic ----
	-- Set every character part/decal/texture (body, accessories, tools, face) transparent, remembering the
	-- original value so it's restored exactly. We also watch for parts that stream/equip in mid-intro and for
	-- characters that (re)spawn during it (incl. the LOCAL one, which spawns right as the intro begins).
	local hiddenParts = {}   -- { {inst=, t=originalTransparency}, ... }
	local playerConns = {}   -- connections to disconnect on restore
	local function hidePart(d)
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			hiddenParts[#hiddenParts + 1] = { inst = d, t = d.Transparency }
			d.Transparency = 1
		end
	end
	local function hideCharacter(c)
		for _, d in ipairs(c:GetDescendants()) do hidePart(d) end
		playerConns[#playerConns + 1] = c.DescendantAdded:Connect(function(d)
			if not worldRestored then hidePart(d) end -- accessories/tools that load or equip mid-intro
		end)
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then hideCharacter(pl.Character) end
		playerConns[#playerConns + 1] = pl.CharacterAdded:Connect(function(c)
			if not worldRestored then hideCharacter(c) end
		end)
	end
	playerConns[#playerConns + 1] = Players.PlayerAdded:Connect(function(pl)
		playerConns[#playerConns + 1] = pl.CharacterAdded:Connect(function(c)
			if not worldRestored then hideCharacter(c) end
		end)
	end)
	local function restorePlayers()
		for _, c in ipairs(playerConns) do pcall(function() c:Disconnect() end) end
		playerConns = {}
		for _, e in ipairs(hiddenParts) do
			if e.inst and e.inst.Parent then pcall(function() e.inst.Transparency = e.t end) end
		end
		hiddenParts = {}
	end

	-- The closing title-card overlay (its own ScreenGui so it survives the world-restore behind it).
	-- Forward-declared here so cleanup() can tear it down too if the cinematic errors out.
	local titleGui

	-- restoreWorld(): hand control + the normal view + ALL HUD back to the player. Called behind the black title
	-- card during the normal flow, and by cleanup() as the always-runs safety net. Does NOT touch titleGui.
	local function restoreWorld()
		if worldRestored then return end
		worldRestored = true
		-- MUSIC BACK UP. MusicDucking owns the BackgroundMusic group's volume, so we hand it straight back
		-- to that script rather than writing a number ourselves -- it knows whether an event duck or the
		-- settings-menu mute is currently in force, and we do not.
		pcall(function()
			if _G.refreshMusicVolume then _G.refreshMusicVolume() end
		end)
		if hudConn then hudConn:Disconnect(); hudConn = nil end -- stop hiding newly-added HUD
		restorePlayers() -- make every player character fully visible again
		-- un-hide every island we hid during the flyover (LocalTransparencyModifier is client-only -> just zero it)
		if flyoverIslands then
			for _, m in ipairs(flyoverIslands) do
				if m and m.Parent then for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 end end end
			end
			flyoverIslands = nil
		end
		-- FACE THE GARDEN: turn the player's CHARACTER toward the Community Garden and seed the camera BEHIND
		-- them looking at it, so the instant control returns both the view and the body face the garden.
		local gard = findGardener()
		if gard and hrp and hrp.Parent then
			local gp = gard:GetPivot().Position
			local look = Vector3.new(gp.X, hrp.Position.Y, gp.Z)
			if (look - hrp.Position).Magnitude > 0.5 then
				hrp.CFrame = CFrame.lookAt(hrp.Position, look) -- character faces the garden (anchored CFrame sticks)
				local back = hrp.Position - look; back = Vector3.new(back.X, 0, back.Z)
				back = (back.Magnitude > 0.1) and back.Unit or Vector3.new(0, 0, 1)
				-- seed the (still-Scriptable) camera over-the-shoulder looking at the garden, just before Custom
				camera.CFrame = CFrame.lookAt(hrp.Position + back * 12 + Vector3.new(0, 3, 0), hrp.Position + Vector3.new(0, 2, 0))
			end
		end
		-- Force the normal player-controlled camera. We must NOT restore prevCamType here: the loading screen leaves
		-- the camera Scriptable, so prevCamType (captured at intro start) is often Scriptable -- restoring it left the
		-- camera locked so the mouse/camera wouldn't rotate until the player clicked something. Custom = free look.
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = hum or prevCamSubject
		if controls then pcall(function() controls:Enable() end) end
		if hrp and wasAnchored ~= nil then hrp.Anchored = wasAnchored end
		-- HARD control restore: the intro disabled the controls AND used a Modal skip button, which can leave the
		-- game GUI-focused / the mouse unlocked -- so movement + camera don't respond until the player clicks
		-- something. Clear the modal focus and release the mouse so the player can move and turn the INSTANT the
		-- intro ends, without having to click a button first.
		pcall(function()
			local UIS = game:GetService("UserInputService")
			UIS.ModalEnabled = false                                   -- drop any lingering modal-input capture
			UIS.MouseBehavior = Enum.MouseBehavior.Default             -- re-release the mouse to the camera
			game:GetService("GuiService").SelectedObject = nil         -- clear gamepad/GUI selection focus
			-- END THE MODAL SKIP BUTTON NOW: while a Modal GuiButton is VISIBLE, Roblox force-UNLOCKS the mouse,
			-- which kills mouse-look camera ROTATION until that button is gone. On skip the button only fades out
			-- (staying visible + Modal for a beat) before cleanup destroys it -- so clear Modal + hide it right here
			-- so the player can turn the camera the INSTANT the intro ends, without having to click a GUI first.
			if skipGui then
				for _, d in ipairs(skipGui:GetDescendants()) do
					if d:IsA("GuiButton") then d.Modal = false; d.Visible = false end
				end
			end
		end)
		-- restore every guarded ScreenGui to the state it WANTED (HUD/banners -> on; shops/popups left off)
		for _, rec in ipairs(guiGuards) do
			if rec.conn then pcall(function() rec.conn:Disconnect() end) end
			if rec.gui and rec.gui.Parent then rec.gui.Enabled = rec.wasEnabled end
		end
		for _, t in ipairs(coreTypes) do
			if coreState[t] ~= nil then pcall(function() StarterGui:SetCoreGuiEnabled(t, coreState[t]) end) end
		end
	end

	-- ---- cleanup (always runs; restores EVERYTHING so the player is never stuck — even on error) ----
	local cleaned = false
	local function cleanup()
		if cleaned then return end
		cleaned = true
		-- Safety stop for the probe: if the farmer is never found, or the player SKIPs before the first segment,
		-- doSegment never runs and the RenderStepped sampler would otherwise stay connected for the session.
		if probeStop then probeStop("cleanup (skipped / no segment reached)"); probeStop = nil end
		restoreWorld()
		if titleGui then titleGui:Destroy(); titleGui = nil end -- never leave the player stuck on a black screen
		if coverGui then coverGui:Destroy(); coverGui = nil end -- opening black transition overlay
		if skipGui then skipGui:Destroy(); skipGui = nil end
		-- BULLETPROOF: sweep away ANY leftover GardenIntro overlay (cover / title black fill, skip) regardless of
		-- which code path ended the cinematic, so a skip can never leave a black fill/dim stuck over the screen.
		for _, g in ipairs(playerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g.Name:sub(1, 11) == "GardenIntro" then pcall(function() g:Destroy() end) end
		end
	end

	-- ---- SKIP BUTTON (jungle/cartoon): hidden at first, fades in after SKIP_AFTER seconds, stays until the
	-- cinematic ends. Its own ScreenGui ABOVE the letterbox AND the title card so it's always visible + clickable. ----
	skipGui = Instance.new("ScreenGui")
	skipGui.Name = "GardenIntroSkip"
	skipGui.IgnoreGuiInset = true
	skipGui.ResetOnSpawn = false
	skipGui.DisplayOrder = 2000000 -- above letterbox (100000) and title card (1000000)
	skipGui.Parent = playerGui
	local skipBtn = Instance.new("TextButton")
	skipBtn.Name = "SkipButton"
	skipBtn.AnchorPoint = Vector2.new(1, 1)
	skipBtn.Position = UDim2.fromScale(0.975, 0.94) -- bottom-right corner (original placement)
	skipBtn.Size = UDim2.fromOffset(138, 48)
	skipBtn.AutoButtonColor = true
	-- Modal=true is what actually makes the tap register here: it frees the cursor / captures input even while
	-- player controls are disabled during the cinematic (without it the bottom-right tap was being swallowed).
	skipBtn.Modal = true
	skipBtn.Active = true
	skipBtn.Selectable = true
	skipBtn.BackgroundColor3 = Color3.fromRGB(54, 116, 50)  -- bright ready green (skip is live immediately)
	skipBtn.Font = Enum.Font.FredokaOne                     -- game's bold rounded font
	skipBtn.Text = "SKIP  \xE2\x9E\x9C"                     -- "SKIP ➜" -- clickable from the very first frame (no countdown)
	skipBtn.TextColor3 = Color3.fromRGB(255, 247, 230)      -- cream
	skipBtn.TextScaled = true
	skipBtn.BackgroundTransparency = 0.05                   -- fully visible (skip is active right away)
	skipBtn.TextTransparency = 0
	skipBtn.ZIndex = 2
	skipBtn.Parent = skipGui
	print("[GARDEN INTRO] SKIP button shown (active immediately)")
	local skCorner = Instance.new("UICorner"); skCorner.CornerRadius = UDim.new(0, 12); skCorner.Parent = skipBtn
	local skBorder = Instance.new("UIStroke"); skBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	skBorder.Color = Color3.fromRGB(255, 247, 230); skBorder.Thickness = 2.5; skBorder.Transparency = 0.35; skBorder.Parent = skipBtn
	local skPad = Instance.new("UIPadding")
	skPad.PaddingTop = UDim.new(0, 8); skPad.PaddingBottom = UDim.new(0, 8)
	skPad.PaddingLeft = UDim.new(0, 14); skPad.PaddingRight = UDim.new(0, 14); skPad.Parent = skipBtn
	local skipReady = true -- skip is available IMMEDIATELY (no countdown gate)
	local function doSkip()
		print("[GARDEN INTRO] SKIP button CLICKED (skipReady=" .. tostring(skipReady) .. ", skipped=" .. tostring(skipped) .. ")")
		if not skipReady then return end -- still counting down ("SKIP in N") -> not clickable yet
		if not skipped then skipped = true; print("[GARDEN INTRO] SKIP handler FIRING -> ending cinematic early") end
		-- drop the Modal + hide the button the instant it's tapped, so the mouse re-locks and the camera can be
		-- rotated right away (restoreWorld also does this, but this is the earliest possible point).
		pcall(function() skipBtn.Modal = false; skipBtn.Visible = false end)
	end
	-- bind several input paths so a tap/click always registers (Activated covers mouse+touch; the extras are
	-- redundant safety in case one path is swallowed on a given device)
	skipBtn.Activated:Connect(doSkip)
	skipBtn.MouseButton1Click:Connect(doSkip)
	skipBtn.TouchTap:Connect(doSkip)
	-- SKIP is available IMMEDIATELY -- the button is styled ready above and skipReady starts true, so a player can
	-- bail out of the intro the instant they join (no countdown). skBorder brightened up front to match.
	pcall(function() skBorder.Transparency = 0 end)

	-- ---- one subject segment: pan in, auto-advance ALL the NPC's lines across `window` seconds total ----
	-- `window` (seconds) is divided EVENLY across this NPC's lines, so the whole set fills the 8-10s window
	-- and the camera holds on them for it. Returns true if SKIP fired so the caller bails the rest.
	-- Play an animal's own noise ON the animal, so it arrives from over there instead of out of the player's
	-- head -- the camera is 9-11 studs off the subject during a segment, which is well inside the rolloff.
	-- Routed through SFXGroup where the realm has one, so the Settings "Sound Effects" toggle mutes it like
	-- every other cue. Debris-cleaned. No asset, no part to hang it on, or a dead model => silent no-op.
	local function playCry(model, cry)
		if not cry or not model or not model.Parent then return end

		-- 1. the animal's own sound, if it has one with an asset actually set. Rewound first: the ambient moo
		--    loop may be mid-play, and :Play() on an already-playing Sound is otherwise a no-op.
		if cry.reuse then
			local own = model:FindFirstChild(cry.reuse, true)
			if own and own:IsA("Sound") and own.SoundId ~= "" then
				pcall(function() own.TimePosition = 0; own:Play() end)
				return
			end
		end

		-- 2. fallback asset, hung on the animal for the one shot.
		if cry.id == "" then return end
		local host = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if not host then return end
		local s = Instance.new("Sound")
		s.Name = "IntroCry"
		s.SoundId = cry.id
		s.Volume = cry.volume or 0.85
		s.PlaybackSpeed = cry.pitch or 1
		s.RollOffMinDistance = 12
		s.RollOffMaxDistance = 160
		local grp = SoundService:FindFirstChild("SFXGroup")
		if grp and grp:IsA("SoundGroup") then s.SoundGroup = grp end
		s.Parent = host
		s:Play()
		Debris:AddItem(s, 6)
	end

	local function frameAndSpeak(model, lines, window, dist, noPan, cry)
		-- temporarily silence any existing rotating speech bubble so it can't fight ours
		local hidExisting = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BillboardGui") and d.Name == "SpeechBubble" and d.Enabled then
				d.Enabled = false; hidExisting[#hidExisting + 1] = d
			end
		end
		local function restoreBubbles() for _, d in ipairs(hidExisting) do if d and d.Parent then d.Enabled = true end end end

		-- noPan: camera is already framed (the black-transition reveal snapped to it) -> just hold + speak.
		if not noPan then
			if panTo(frameCFrame(model, dist), PAN_TIME) then restoreBubbles(); return true end
		end

		-- keep the (possibly wandering) subject centred while it speaks
		--
		-- HANDHELD SWAY ONLY -- the framing DISTANCE is fixed, and must stay fixed.
		--
		-- A slow push-in was tried here and removed. It looked correct on paper and wrong on screen, for a
		-- reason worth writing down so nobody re-adds it: frameCFrame() recomputes the shot from the NPC's
		-- CURRENT position every frame, and that position arrives by REPLICATION, not per-frame. With a
		-- constant distance the lerp converges and the camera sits still, so the stepping is invisible. Feed
		-- it a distance that is also shrinking and every replication update lands as a small forward nudge:
		-- the camera visibly INCHES toward whoever is speaking instead of gliding. Any dolly move here has to
		-- come from a separately smoothed subject position, not from varying `dist` against a live target.
		--
		-- The sway survives because it is pure ROTATION applied to the final CFrame -- it adds no positional
		-- motion at all, so it cannot inch. A few thousandths of a radian on two axes at deliberately
		-- mismatched speeds, so the drift never visibly repeats: the difference between a camera someone is
		-- holding and a CFrame. Keep it tiny; crank these and it reads as a wobble.
		local SWAY_YAW  = 0.006  -- radians
		local SWAY_PIT  = 0.004
		-- Declared HERE, above the closure that reads it. It is also the cries' cancel flag further down,
		-- and a `local` placed after this connection would be a DIFFERENT variable -- the closure would
		-- read a nil global, return every frame, and the camera would stop following the animal entirely.
		local following = true
		local conn = RunService.RenderStepped:Connect(function()
			if not following or not model.Parent then return end
			local t = os.clock()
			local sway = CFrame.Angles(math.sin(t * 0.73) * SWAY_PIT, math.sin(t * 0.51) * SWAY_YAW, 0)
			camera.CFrame = camera.CFrame:Lerp(frameCFrame(model, dist) * sway, 0.06)
		end)

		-- THE CRIES, on their own timer for the length of the segment. Separate from the line loop below
		-- because the two are counted differently now: the lines divide the window between them, while the
		-- cries are a fixed number spread across the whole of it. The first fires immediately, so the animal
		-- makes its noise as the camera settles on it rather than after a silent beat.
		-- `following` doubles as the cancel flag -- it is already cleared when the segment ends (or is
		-- skipped), so a cry can never land over the next NPC.
		if cry and (cry.plays or 0) > 0 then
			task.spawn(function()
				local gap = window / cry.plays
				for i = 1, cry.plays do
					if not following or not model.Parent then return end
					playCry(model, cry)
					if i < cry.plays then task.wait(gap) end
				end
			end)
		end

		-- split the window evenly across the lines (each line = clear + show, summing to ~per)
		local n = #lines
		local per = (n > 0) and (window / n) or window
		local bb, label = makeBubble(model)
		for _, line in ipairs(lines) do
			if label then label.Text = "" end -- clear previous line
			if sleep(0.1) then break end
			if label then label.Text = line end
			if sleep(math.max(0.3, per - 0.1)) then break end
		end

		following = false
		conn:Disconnect()
		if bb then bb:Destroy() end
		restoreBubbles()
		return skipped
	end

	-- Returns true if SKIP fired (so the sequence bails). Skip-aware model wait so a missing NPC can't stall a skip.
	local function doSegment(finder, lines, window, dist, label, noPan, cry)
		local model = finder()
		local t = 0
		while not model and t < 5 and not skipped do task.wait(0.25); t = t + 0.25; model = finder() end
		if skipped then return true end
		if not model then
			print("[GARDEN INTRO] " .. label .. " not found -> skipping segment")
			return false
		end
		print("[GARDEN INTRO] segment: " .. label)
		-- The probe's window closes here: from this point doSegment owns the camera, so anything after is the
		-- cinematic proper, not the handoff we are measuring. Only the FIRST segment ends it.
		if probeStop then probeStop("segment:" .. label); probeStop = nil end

		-- The NPC WAVES as the camera settles on him. Without this he stands stone-still through the one scene that
		-- is entirely about him -- his proximity wave cannot fire, because the player's character is still back at
		-- spawn while the camera is over here.
		--
		-- Deliberately fired a beat AFTER the pan starts, not on the same frame: a wave that begins before the camera
		-- has arrived is half over by the time you can see him.
		local WAVERS = { GARDENER = "Gardener", FARMER = "Farmer" }
		local who = WAVERS[label]
		if who then
			task.delay(0.8, function()
				local ev = ReplicatedStorage:FindFirstChild("GardenerWaveRequest")
				if ev then
					ev:FireServer(who)
					print("[GARDEN INTRO] asked the " .. who .. " to wave")
				end
			end)
		end

		return frameAndSpeak(model, lines, window, dist, noPan, cry)
	end

	-- ---- RUN THE CINEMATIC (guarded so cleanup ALWAYS happens; SKIP bails any step early) ----
	-- DUCK THE MUSIC UNDER THE CINEMATIC. The NPCs "speak" in silent text bubbles, so the soundtrack is the
	-- only thing competing with them -- pulling it down for the shot is the difference between lines you
	-- read and lines you notice. Tweened, not snapped, so the drop is not itself an event.
	-- restoreWorld() hands control back to MusicDucking; this only borrows the group for the shot.
	pcall(function()
		local grp = SoundService:FindFirstChild("BackgroundMusic")
		if grp and grp:IsA("SoundGroup") then
			local normal = grp:GetAttribute("NormalVolume") or grp.Volume
			TweenService:Create(grp, TweenInfo.new(0.6), { Volume = normal * 0.35 }):Play()
		end
	end)

	local ok, err = pcall(function()
		camera.CameraType = Enum.CameraType.Scriptable
		-- BEHIND THE BLACK: frame the FARMER (the first speaker) so the reveal shows him already in place (no pan/jump).
		local farm = findFarmer()
		local gt = 0
		while not farm and gt < 3 and not skipped do task.wait(0.2); gt = gt + 0.2; farm = findFarmer() end
		if skipped then return end
		local revealModel = farm or findGardener() -- fall back to the gardener if the farmer isn't around
		camera.CFrame = revealModel and frameCFrame(revealModel, 9) or startCF
		-- Reveal ASAP: hold black only the tiny beat it takes to frame the farmer (min ~0.1s since the click, to cover
		-- the menu close + camera move), then a QUICK ~0.25s fade -- so the intro appears almost immediately after PLAY
		-- instead of the old 0.5s-hold + 0.5s-fade (~1s) pause.
		if sleep(math.max(0, 0.1 - (os.clock() - blackStart))) then return end

		-- HOLD THE FRAMING ACROSS THE FADE.
		-- CameraType was set to Scriptable further up, and the CFrame above frames the farmer -- but BOTH of those
		-- happen before the server has finished spawning the character. Selecting the island respawns it, and a
		-- fresh character makes the engine reset CameraType to Custom and repoint CameraSubject at the new
		-- Humanoid. The camera therefore snaps back onto the player somewhere in this gap, and the fade below then
		-- reveals ordinary gameplay instead of the farmer for a beat -- the boot log measured 0.29s of it, from
		-- "fading up" to "segment: FARMER" (which is where doSegment's own lerp finally retakes the camera).
		--
		-- Re-assert immediately, then keep re-asserting every rendered frame until the segment takes over, so it
		-- does not matter WHEN the respawn lands inside this window.
		local function holdFrame()
			camera.CameraType = Enum.CameraType.Scriptable
			if revealModel then camera.CFrame = frameCFrame(revealModel, 9) end
		end
		-- Same reasoning for the HUD. CoreClient hides every game ScreenGui at build time and re-enables them all
		-- on CharacterAdded ("HUD REVEALED"), which lands INSIDE the cinematic -- the boot log has it at .936
		-- with this fade at .069, 0.13s later. The Enabled watcher in hideGui does catch that and slap them back
		-- off, but only on the frame the property changes, and only for GUIs that were guarded at intro start.
		-- Re-sweep here so what the fade uncovers is guaranteed to be the farmer and nothing else.
		for _, g in ipairs(playerGui:GetChildren()) do
			hideGui(g)                                              -- guards anything that appeared since the start
			if guardedSet[g] and g.Enabled then g.Enabled = false end -- and force off anything re-enabled since
		end

		holdFrame()
		local holdConn = RunService.RenderStepped:Connect(holdFrame)

		-- DRAW THE FARMER FRAMING BEHIND THE BLACK BEFORE LIFTING IT.
		-- holdFrame() only ASSIGNS the CFrame; the engine does not composite it until the next render. Starting
		-- the tween on this same frame therefore lets the first fade frames come out of the renderer still using
		-- the OLD camera -- which, this early, is the default player camera looking at the spawn: plain world.
		-- That is the "quick glimpse of the game right after PLAY, before the farmer" being reported. Give the
		-- new camera two real rendered frames under the still-opaque black, so the very first non-black pixel
		-- the player ever sees is already the farmer.
		RunService.RenderStepped:Wait()
		RunService.RenderStepped:Wait()

		print("[GARDEN INTRO] black hold done -> fading up to reveal the farmer")
		TweenService:Create(coverBlack, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {BackgroundTransparency = 1}):Play()
		local bailed = sleep(0.25)
		holdConn:Disconnect()   -- doSegment drives the camera from here; releasing avoids fighting its lerp
		if bailed then return end
		if coverGui then coverGui:Destroy(); coverGui = nil end

		-- FARMER FIRST: already framed by the reveal -> straight into his welcome lines (no pan). Then the garden
		-- NPCs in their existing order; the gardener now PANS in (camera was on the farmer).
		if doSegment(findFarmer,   FARMER_LINES,   FARMER_WINDOW,   9, "FARMER", true) then return end
		if doSegment(findGardener, GARDENER_LINES, GARDENER_WINDOW, 9, "GARDENER") then return end
		if doSegment(findCow,      COW_LINES,      COW_WINDOW,      11, "COW",  false, COW_CRY) then return end
		if doSegment(findPig,      PIG_LINES,      PIG_WINDOW,      10, "PIG",  false, PIG_CRY) then return end

		-- ---- ISLAND FLYOVER: Island 1 top-down -> side view up a FEW islands -> black hole bottom-up ----
		-- Only a handful of islands are shown (not all 14): the point is a quick "look how high this goes"
		-- tease, and visiting every island turned it into a ~31s wordless camera trip. The big height jumps
		-- between these three sell the scale better than the full stack did. Edit FLYOVER_ISLANDS to retune.
		local FLYOVER_ISLANDS = {5, 9, 14} -- Coconut Cove -> Milk Marsh -> Pizza Palms (the summit)
		local FLY_TRAVEL = 1.0  -- smooth eased travel between viewpoints
		local FLY_HOLD   = 0.5  -- DWELL: hold at each island / the black hole

		-- ONLY-CURRENT-ISLAND: cache every island's parts, hide them all, and show just the one in frame each
		-- segment (so e.g. island 2 isn't visible while island 1 is shown). Client-only via LocalTransparencyModifier;
		-- restoreWorld() zeroes it back at the end (also on skip), and flyoverIslands lets it find them.
		local islandModels, islandParts = {}, {}
		for n = 1, 14 do
			local m = findIslandModel(n); islandModels[n] = m
			local t = {}
			if m then for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then t[#t + 1] = d end end end
			islandParts[n] = t
		end
		flyoverIslands = islandModels -- restoreWorld() un-hides every island regardless of how the cinematic ends
		local function setIslandLT(n, lt) for _, p in ipairs(islandParts[n] or {}) do p.LocalTransparencyModifier = lt end end
		for n = 1, 14 do setIslandLT(n, 1) end -- hide ALL islands up front
		local shownIsland = nil
		local function showOnlyIsland(only) -- only=nil -> keep everything hidden (just the black hole shows)
			if shownIsland and shownIsland ~= only then setIslandLT(shownIsland, 1) end -- hide the previous
			if only then setIslandLT(only, 0) end                                       -- show the current
			shownIsland = only
		end

		local isl1 = islandModels[1]
		if isl1 then
			print("[GARDEN INTRO] flyover: ISLAND 1 (top-down)")
			showOnlyIsland(1)
			if panTo(islandTopCFrame(isl1), FLY_TRAVEL) then return end
			if sleep(FLY_HOLD) then return end
		else
			print("[GARDEN INTRO] flyover: ISLAND 1 not found -> skipping")
		end

		for _, n in ipairs(FLYOVER_ISLANDS) do
			if skipped then return end
			local m = islandModels[n]
			if m then
				print("[GARDEN INTRO] flyover: ISLAND " .. n .. " (side view)")
				showOnlyIsland(n)
				if panTo(islandSideCFrame(m), FLY_TRAVEL) then return end
				if sleep(FLY_HOLD) then return end
			else
				print("[GARDEN INTRO] flyover: ISLAND " .. n .. " not found -> skipping")
			end
		end

		local bh = findBlackHole()
		if bh then
			print("[GARDEN INTRO] flyover: BLACK HOLE (bottom-up)")
			showOnlyIsland(nil) -- hide all islands -> only the black hole in frame
			if panTo(blackHoleCFrame(bh), FLY_TRAVEL + 0.5) then return end
			if sleep(FLY_HOLD) then return end
		else
			print("[GARDEN INTRO] flyover: BLACK HOLE not found -> skipping")
		end
		showOnlyIsland(nil) -- leave the islands hidden behind the closing title card; restoreWorld() un-hides them

		-- ---- CLOSING TITLE CARD: fade to black -> title + credit -> hold -> fade out to gameplay ----
		print("[GARDEN INTRO] segment: TITLE CARD (fade to black)")
		-- Its OWN full-screen ScreenGui at a higher DisplayOrder than the letterbox, so the black overlay
		-- covers the ENTIRE screen (nothing shows behind it) and survives restoreWorld() behind it.
		titleGui = Instance.new("ScreenGui")
		titleGui.Name = "GardenIntroTitle"
		titleGui.IgnoreGuiInset = true
		titleGui.ResetOnSpawn = false
		titleGui.DisplayOrder = 1000000
		titleGui.Parent = playerGui

		-- ---- the card itself: black backdrop, the game's name, the studio credit ----
		-- Same two labels and the same timing this always had. Only the COLOURS changed, to the ones the rest of
		-- the realm is built from: the gold the crate reveal, the shop headers and the growth dial all use, over a
		-- navy-black rather than a flat #000 -- flat black is the one colour nothing else in this game uses, which
		-- is exactly what made a white-on-black card feel like it belonged to some other game.
		local GOLD  = Color3.fromRGB(255, 210, 74)  -- #ffd24a, the house gold
		local NAVY   = Color3.fromRGB(6, 26, 80)     -- the house shadow colour; never black
		local CREAM = Color3.fromRGB(238, 244, 255)

		local black = Instance.new("Frame")
		black.Name = "Black"
		black.Size = UDim2.fromScale(1, 1)
		black.Position = UDim2.fromScale(0, 0)
		black.BackgroundColor3 = Color3.fromRGB(6, 10, 26) -- near-black, faintly navy
		black.BackgroundTransparency = 1 -- fades 1 -> 0 (fully opaque)
		black.BorderSizePixel = 0
		black.ZIndex = 1
		black.Parent = titleGui

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.AnchorPoint = Vector2.new(0.5, 0.5)
		title.Position = UDim2.fromScale(0.5, 0.45)
		title.Size = UDim2.fromScale(0.86, 0.15)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne -- game's bold rounded font
		title.Text = "Welcome To Fart To Float"
		title.TextColor3 = GOLD
		title.TextScaled = true
		title.TextTransparency = 1 -- fades in just after the screen goes black
		title.ZIndex = 2
		title.Parent = titleGui
		-- A navy outline, the same one every panel and label in the game wears. It is what stops gold text from
		-- washing out, and it is most of why this reads as the game's own lettering.
		--
		-- KEPT IN A VARIABLE, and it starts invisible. A UIStroke has its OWN Transparency that
		-- TextTransparency does not touch, so a stroke left at 0 while the label fades leaves the hollow
		-- outline of the name hanging on screen after the letters themselves have gone. Every fade below
		-- drives this alongside the label.
		local titleStroke = Instance.new("UIStroke")
		titleStroke.Thickness = 3
		titleStroke.Color = NAVY
		titleStroke.Transparency = 1
		titleStroke.Parent = title

		-- A hairline of house gold between the name and the credit. One thin rule is the whole reason a
		-- two-line card reads as SET rather than as two sentences that happen to be near each other -- it
		-- groups them and gives the credit something to hang from. Static, centred, no animation of its own.
		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.AnchorPoint = Vector2.new(0.5, 0.5)
		rule.Position = UDim2.fromScale(0.5, 0.525)
		rule.Size = UDim2.fromScale(0.20, 0.004)
		rule.BackgroundColor3 = GOLD
		rule.BackgroundTransparency = 1
		rule.BorderSizePixel = 0
		rule.ZIndex = 2
		rule.Parent = titleGui
		do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = rule end

		local credit = Instance.new("TextLabel")
		credit.Name = "Credit"
		credit.AnchorPoint = Vector2.new(0.5, 0)
		credit.Position = UDim2.fromScale(0.5, 0.555) -- under the rule, with the same small gap as before
		credit.Size = UDim2.fromScale(0.5, 0.045)
		credit.BackgroundTransparency = 1
		credit.Font = Enum.Font.FredokaOne
		credit.Text = "By: M.L.R. Studios"
		credit.TextColor3 = CREAM
		credit.TextScaled = true
		credit.TextTransparency = 1
		credit.ZIndex = 2
		credit.Parent = titleGui

		-- ===== FADES, WITH THE STROKE DRIVEN ALONGSIDE THE TEXT =====
		-- One helper for both directions, so the card can never go out by a different route than it came
		-- in. `a` is 0 (visible) or 1 (gone); the stroke and the rule ride the same tween as the labels --
		-- which is the whole point of it existing, because a stroke left behind is exactly how the outline
		-- of the name ended up hanging over live gameplay.
		local function fadeCard(a, dur)
			local info = TweenInfo.new(dur)
			TweenService:Create(title,       info, {TextTransparency = a}):Play()
			TweenService:Create(titleStroke, info, {Transparency = a}):Play()
			TweenService:Create(credit,      info, {TextTransparency = a}):Play()
			TweenService:Create(rule,        info, {BackgroundTransparency = (a >= 1) and 1 or 0.25}):Play()
		end

		-- 1) fade the whole screen down (~1s)
		TweenService:Create(black, TweenInfo.new(1, Enum.EasingStyle.Quad), {BackgroundTransparency = 0}):Play()
		if sleep(1) then return end

		-- 2) the card fades in over the black (~0.6s)
		print('[GARDEN INTRO] segment: TITLE CARD ("Welcome To Fart To Float" / By: M.L.R. Studios)')
		fadeCard(0, 0.6)

		-- 3) hold (~3s)
		if sleep(3) then return end

		-- 4) behind the still-opaque black, hand the world back (default camera on the player, controls +
		-- HUD restored, letterbox gone) so that when the black lifts, NORMAL GAMEPLAY is revealed.
		print("[GARDEN INTRO] segment: RETURN TO PLAYER (behind title card)")
		restoreWorld()

		-- 5) card out first (0.6s), then the screen up (1.2s, Sine). The black lifting is what brings the
		-- whole picture back -- world and HUD together -- so it is left slower than the text.
		print("[GARDEN INTRO] segment: TITLE CARD (fade out -> gameplay)")
		fadeCard(1, 0.6)
		TweenService:Create(black, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{BackgroundTransparency = 1}):Play()
		if sleep(1.25) then return end
		if titleGui then titleGui:Destroy(); titleGui = nil end
	end)

	-- ---- SKIP teardown: if the player hit SKIP, fade out any letterbox/overlay cleanly, then restore. ----
	if skipped and not cleaned then
		print("[GARDEN INTRO] SKIP -> ending early, fading overlays out")
		if activeTween then pcall(function() activeTween:Cancel() end) end
		if skipGui then pcall(function() TweenService:Create(skipBtn, TweenInfo.new(0.2), {BackgroundTransparency = 1, TextTransparency = 1}):Play() end) end
		if titleGui then
			-- Title card is up: restore the world BEHIND the opaque black, then fade the card out -> gameplay.
			--
			-- GetDESCENDANTS, and UIStroke is in the list. This used to walk GetChildren() and tween only
			-- TextTransparency / BackgroundTransparency -- but a UIStroke is a child OF the label, not of
			-- the ScreenGui, and it carries its own Transparency that TextTransparency does not touch. So
			-- the black went, the credit went, the gold fill of the name went, and the navy outline of
			-- "Welcome To Fart To Float" stayed fully opaque -- a hollow shell of the title hanging over
			-- live gameplay for the rest of the fade. Everything now goes out on the same 0.5s.
			restoreWorld()
			for _, d in ipairs(titleGui:GetDescendants()) do
				pcall(function()
					if d:IsA("TextLabel") then TweenService:Create(d, TweenInfo.new(0.5), {TextTransparency = 1}):Play() end
					if d:IsA("Frame")     then TweenService:Create(d, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play() end
					if d:IsA("UIStroke")  then TweenService:Create(d, TweenInfo.new(0.5), {Transparency = 1}):Play() end
				end)
			end
			task.wait(0.55)
		else
			-- no title card up: brief beat, then restore (camera returns to the player, HUD comes back)
			task.wait(0.2)
		end
	end

	cleanup()
	if not ok then warn("[GARDEN INTRO] error during cinematic: " .. tostring(err)) end

	-- tell the server we finished so it sets + saves SeenGardenIntro (won't play again — skipped counts as seen)
	pcall(function() GardenIntroDoneEvent:FireServer() end)
	print("[GARDEN INTRO] finished -> notified server to set SeenGardenIntro flag; normal gameplay resumes")

	-- GUIDE: kick off the green chevron trail -> Gardener, then the food stand (runs after finish OR skip).
	if type(_G.startGardenGuide) == "function" then _G.startGardenGuide() end
end

-- ON-CLICK START: LoadingScreen calls this the instant Island 1 is clicked, so the black overlay appears
-- right on the click. The server's GardenIntroEvent below is the authoritative fallback; the `playing`
-- guard makes whichever fires first win and the other a no-op.
_G.startGardenIntro = playIntro

if GardenIntroEvent then
	GardenIntroEvent.OnClientEvent:Connect(playIntro)
else
	warn("[GARDEN INTRO] GardenIntroEvent missing -> cinematic disabled")
end
