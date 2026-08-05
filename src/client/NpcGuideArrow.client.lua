--======================================================================
-- NpcGuideArrow.client.lua   (LocalScript, per-player)   -- from NpcMovementKit
--======================================================================
-- LAND ON AN ISLAND, GET POINTED AT ITS NPC.
--
-- Every island has a quest giver and no way of knowing where they are; you land, and you are stood
-- on a large island with a person somewhere on it. This lays the chevron trail from wherever you
-- touch down to that island's NPC, then puts itself away.
--
-- IT DOES NOT DRAW ANYTHING. GardenGuideTrail owns the chevrons -- it already survives across
-- islands, hides itself mid-flight and comes back when you land, and all the awkward parts are
-- solved in there. This script only decides WHERE it should point, through the low-priority slot
-- _G.guideTrailNpc, so an urgent target (a hatchable egg) still beats an NPC every time.
--
-- ===== WHEN THE ARROWS GO AWAY (three ways) =====
--   1. YOU REACH THEM      -- within ARRIVE_DIST. You found who you were looking for.
--   2. THIRTY SECONDS      -- SHOW_SECONDS of standing on the island. Guidance is for the moment
--                             you arrive; a trail still burning minutes later is scenery, and
--                             scenery that points at something is nagging.
--   3. YOU FLY AWAY        -- the target is dropped the moment you take off. Leaving BEFORE the
--                             30s is up does not spend your chance: land again and the visit
--                             timer restarts, so you are guided on arrival every time.
--
-- 1 and 2 latch that island off for the session. 3 does not.
--
-- ===== FINDING THE NPC =====
-- Inside the island model ONLY, never a Workspace-wide sweep: islands here sit a few hundred studs
-- apart and a nearest-in-range search happily wires one island's quest giver to its neighbour.
-- Matched on the QuestNpc attribute (set by IslandNPCs.server.lua) or a name containing
-- "quest"/"npc", and re-tried every scan because island CONTENTS stream in after the model does --
-- a single look at landing time finds nothing on most islands.
--======================================================================

local Players         = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Workspace       = game:GetService("Workspace")
local RunService      = game:GetService("RunService")
local player          = Players.LocalPlayer

-- ===== CONFIG =====
local ISLAND_PREFIX = "island"   -- normalised prefix of the top-level island models
local NPC_ATTR      = "QuestNpc" -- set by IslandNPCs.server.lua on every wired quest giver
local NAME_HINTS    = { "quest", "npc" }
local ARRIVE_DIST   = 16         -- close enough to count as met
local GUIDE_RANGE   = 850        -- islands are big; this only stops cross-map pointing
local SHOW_SECONDS  = 45         -- how long the arrows stay up per visit before they retire
local RESCAN        = 1.5        -- seconds between full searches
local Y_SLACK       = 120        -- studs of vertical tolerance when deciding which island you are on

-- names in a real place carry stray spaces, underscores and casing ('Island_2_BrocolliBluff')
local function norm(s)
	return (tostring(s):lower():gsub("[%s_%-]", ""))
end

local reached  = {}     -- island name -> true once met OR timed out this session (no more arrows)
local visitAt  = {}     -- island name -> os.clock() this visit began; nil while flying
local boxes    = {}     -- island -> { c = centre, h = half-extents }; islands do not move
local island, npcPart   -- what we are currently pointing at
local nextScan = 0

-- THE ISLAND YOU ARE STANDING ON.
--
-- Comparing distance to each island's PIVOT does not work -- a model's pivot is wherever it
-- happens to sit, for these islands nowhere near the island itself. Bounding boxes instead: you
-- are on the island whose footprint you are inside. Boxes are cached because GetBoundingBox walks
-- every part, but a box under ~50 studs across means the island had not streamed in when it was
-- measured, so that one is measured again rather than trusted.
-- THE ISLANDS MOVE. PlayerStats repositions all 14 at runtime (~6s in, "Positioned Island_2_BroccoliBluff
-- at Y=790"), so a box measured before that is a footprint at coordinates the island no longer occupies.
-- The old cache only re-measured when the box was too SMALL, never when it had MOVED -- so it answered with
-- stale geography forever. That is why the guide reported "now on Island_2" while the player was stood on
-- island 1, and then never noticed them arriving anywhere else: the island never appeared to change, so it
-- never re-scanned, so no arrows.
--
-- Re-measure whenever the pivot has shifted. Cheap, since the pivot read is O(1) and islands settle early.
local function boxOf(m)
	local ok, piv = pcall(function() return m:GetPivot().Position end)
	if not ok then return nil end
	local b = boxes[m]
	if b and b.h.X > 25 and b.h.Z > 25 and (b.piv - piv).Magnitude < 1 then return b end
	local ok2, cf, size = pcall(function() return m:GetBoundingBox() end)
	if not ok2 or not cf then return nil end
	b = { c = cf.Position, h = size * 0.5, piv = piv }
	boxes[m] = b
	return b
end

local function islandUnder(pos)
	local best, bestScore
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and norm(m.Name):sub(1, #ISLAND_PREFIX) == ISLAND_PREFIX then
			local b = boxOf(m)
			if b then
				-- HOW FAR OUTSIDE THE BOX YOU ARE, IN ALL THREE AXES. Zero means you are inside it.
				--
				-- Y IS NOT OPTIONAL HERE. This tested X/Z only -- "are you over this footprint" -- which is
				-- right for a realm laid out on a plane and useless for this one: these islands are STACKED
				-- at Y=150, 790, 1680, 2480 ... with X/Z footprints that overlap heavily. Flat, the test
				-- matched several islands at once and kept returning whichever won the size tie-break, so
				-- warping from island 1 to island 2 registered as no change at all -- no re-scan, no NPC
				-- lookup, no arrows, and not one line in the log to say why.
				--
				-- The slack covers standing on a tall prop or jumping. Islands here sit 640+ studs apart
				-- vertically, so this separates them with a wide margin to spare.
				local dx = math.max(0, math.abs(pos.X - b.c.X) - b.h.X)
				local dy = math.max(0, math.abs(pos.Y - b.c.Y) - b.h.Y - Y_SLACK)
				local dz = math.max(0, math.abs(pos.Z - b.c.Z) - b.h.Z)
				-- Ties (inside more than one box) break toward the SMALLER island, so a big one cannot
				-- swallow a small one sitting inside its bounds.
				local score = math.sqrt(dx * dx + dy * dy + dz * dz) * 1000 + (b.h.X + b.h.Z)
				if not bestScore or score < bestScore then best, bestScore = m, score end
			end
		end
	end
	return best
end

local function looksLikeNpc(m)
	if m:GetAttribute(NPC_ATTR) then return true end
	local n = norm(m.Name)
	for _, hint in ipairs(NAME_HINTS) do
		if string.find(n, hint, 1, true) then return true end
	end
	return false
end

local function npcIn(scope, from)
	local best, bestD
	for _, d in ipairs(scope:GetDescendants()) do
		if d:IsA("Model") and looksLikeNpc(d) then
			local part = d:FindFirstChild("HumanoidRootPart") or d:FindFirstChild("Head") or d.PrimaryPart
				or d:FindFirstChildWhichIsA("BasePart", true)
			if part and part:IsA("BasePart") then
				local dist = (part.Position - from).Magnitude
				if not bestD or dist < bestD then best, bestD = part, dist end
			end
		end
	end
	return best
end

-- ONE SET OF RULES, TWO RENDERERS.
--
-- The ▼ over the NPC's head (NpcWaypointArrow) must appear and vanish on exactly the same terms as the ground
-- chevrons -- gone when you fly off, gone after SHOW_SECONDS, gone once you have met them. Rather than give
-- that script its own island detection and its own timer to drift out of step with this one, this publishes
-- the ONE npc currently being guided to. Nil means "show nothing", and every retirement path below already
-- routes through clearTrail().
local function setGuided(part)
	local model = nil
	if part then
		-- Nearest ancestor Model IS the NPC (the guide points at its HumanoidRootPart/Head, whose parent is
		-- the rig). Do not climb further: one more step lands on the ISLAND model, and the arrow would then
		-- hover over the island's bounding-box top -- hundreds of studs up in empty sky.
		model = part:FindFirstAncestorOfClass("Model")
		-- ...unless the rig nests its parts a level deeper, in which case take the tagged one above it.
		if model and not model:GetAttribute("QuestNpc") then
			local up = model:FindFirstAncestorOfClass("Model")
			if up and up:GetAttribute("QuestNpc") then model = up end
		end
	end
	_G.questArrowNpc = model
end

local function clearTrail()
	if _G.guideTrailNpc then _G.guideTrailNpc(nil) end
	setGuided(nil)
end

-- The trail lives in another script. If that one is missing or is an older copy without the NPC
-- slot, this script does everything right and nothing appears -- so say so, once, loudly, rather
-- than sitting there silently pointing at nobody.
task.delay(5, function()
	if not _G.guideTrailNpc then
		warn("[NpcGuide] no _G.guideTrailNpc -- arrows CANNOT draw. GardenGuideTrail.client.luau needs the NPC slot.")
	end
end)

-- /arrows -- print exactly what the guide can see, so a silent trail can be diagnosed in one line
-- instead of guessed at
local function onCommand(msg)
	if tostring(msg or ""):lower():sub(1, 7) ~= "/arrows" then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	print("[NpcGuide] ---- state ----")
	print(("  island   : %s"):format(island and island.Name or "NONE"))
	print(("  npc      : %s"):format(npcPart and npcPart:GetFullName() or "NONE"))
	if hrp and npcPart then
		print(("  distance : %d studs (guide range %d)")
			:format((npcPart.Position - hrp.Position).Magnitude, GUIDE_RANGE))
	end
	if island and visitAt[island.Name] then
		print(("  visit    : %.0fs of %ds"):format(os.clock() - visitAt[island.Name], SHOW_SECONDS))
	end
	print(("  retired  : %s"):format(island and tostring(reached[island.Name] == true) or "n/a"))
	print(("  flying   : %s"):format(tostring(_G.isFlying == true)))
	print(("  trail api: %s"):format(_G.guideTrailNpc and "present" or "MISSING"))
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)

RunService.Heartbeat:Connect(function()
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- FLYING AWAY DROPS THE TARGET. The trail hides itself mid-flight regardless, but the point
	-- of clearing here is that taking off ends this VISIT: the timer is thrown away, so landing
	-- again (here or anywhere) starts a fresh 30 seconds instead of resuming a spent one.
	-- Crucially it does NOT latch the island off -- leaving early must not cost you your guidance.
	if _G.isFlying then
		if island then visitAt[island.Name] = nil end
		clearTrail()
		return
	end

	local now = os.clock()
	if now >= nextScan then
		nextScan = now + RESCAN
		local isl = islandUnder(hrp.Position)
		if isl ~= island then
			island, npcPart = isl, nil
			if isl then print(("[NpcGuide] now on %s"):format(isl.Name)) end
		end
		-- re-find if it streamed out, or if we never found one -- island models arrive before their
		-- contents do, so a single look at landing time finds nothing on most islands
		if island and not reached[island.Name] and not (npcPart and npcPart.Parent) then
			npcPart = npcIn(island, hrp.Position)
			if npcPart then
				print(("[NpcGuide] %s -> guiding to %s (%d studs)")
					:format(island.Name, npcPart:GetFullName(),
						(npcPart.Position - hrp.Position).Magnitude))
			end
		end
	end

	if not (island and npcPart and npcPart.Parent) or reached[island.Name] then
		clearTrail()
		return
	end

	-- start (or resume) this visit's clock the first grounded frame on the island
	if not visitAt[island.Name] then visitAt[island.Name] = now end

	-- 30 SECONDS AND IT RETIRES. Latched, so it does not light up again every time you cross back
	-- over this island later in the run.
	if now - visitAt[island.Name] >= SHOW_SECONDS then
		reached[island.Name] = true
		clearTrail()
		print(("[NpcGuide] %ds up on %s -- arrows retired for this island"):format(SHOW_SECONDS, island.Name))
		return
	end

	local d = (npcPart.Position - hrp.Position).Magnitude
	if d <= ARRIVE_DIST then
		reached[island.Name] = true
		clearTrail()
		print(("[NpcGuide] reached %s's NPC -- no more arrows for it"):format(island.Name))
		return
	end
	if d > GUIDE_RANGE then
		clearTrail()
		return
	end

	if _G.guideTrailNpc then _G.guideTrailNpc(npcPart.Position) end
	setGuided(npcPart) -- and light the ▼ over that same NPC's head
end)

print(("[NpcGuide] ready -- arrows to each island's NPC on landing, gone after %ds or on takeoff"):format(SHOW_SECONDS))
