--======================================================================
-- NpcGuideArrow.client.lua   (LocalScript, per-player)   -- PORTABLE REALM KIT
--======================================================================
-- LAND ON AN ISLAND, GET POINTED AT ITS NPC.
--
-- Every island has a quest giver and no way of knowing where they are; you land, and you are
-- stood on a large island with a person somewhere on it. This lays the chevron trail from
-- wherever you touch down to that island's NPC, then puts itself away.
--
-- IT DOES NOT DRAW ANYTHING. GuideTrail owns the chevrons, works on every island, hides itself
-- mid-flight and comes back when you land -- all the awkward parts are solved in there. This
-- script only decides WHERE it should point, through the low-priority slot _G.guideTrailNpc, so
-- an urgent target (a hatchable egg) still beats an NPC every time.
--
-- IT ONLY NAGS ONCE. Reaching an island's NPC latches that island off for the session. A trail
-- that lights up every time you walk back past someone you have already met is nagging, not
-- guidance.
--
-- ===== PORTING TO ANOTHER REALM =====
-- ISLAND_PREFIX and NPC_HINT are the whole port. Both are matched against a NORMALISED name
-- (lowercased, spaces/underscores/hyphens stripped), so "island1", "Island_1", "Island 1" and
-- "Island_1_BeanFarm" all match the prefix "island" -- which is the exact class of naming
-- mismatch that has silently broken three separate scripts in this codebase. Normalise, always.
--======================================================================

local Players         = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Workspace       = game:GetService("Workspace")
local RunService      = game:GetService("RunService")
local player          = Players.LocalPlayer

-- ===== CONFIG =====
local ISLAND_PREFIX = "island"   -- normalised prefix of your top-level island models
local NPC_HINT      = "npc"      -- any model whose name contains this, e.g. "Candy Npc"
local ARRIVE_DIST   = 16         -- close enough to count as met
local GUIDE_RANGE   = 850        -- islands are big; this only stops cross-map pointing
local RESCAN        = 1.5        -- seconds between full searches

-- names in a real place carry stray spaces, underscores and casing ('gas vents ', 'Candy Npc')
local function norm(s)
	return (tostring(s):lower():gsub("[%s_%-]", ""))
end

local reached  = {}     -- island name -> true once you have met its NPC this session
local boxes    = {}     -- island -> { c = centre, h = half-extents }; islands do not move
local island, npcPart   -- what we are currently pointing at
local nextScan = 0

-- THE ISLAND YOU ARE STANDING ON.
--
-- The first version compared horizontal distance to each island's PIVOT, and a model's pivot is
-- wherever it happens to sit -- for these islands, nowhere near the island itself. Stood on
-- island 8 it picked island 14, handed the trail a target hundreds of studs away, and the
-- renderer's own range cap then threw every chevron out. Nothing drew and nothing said why.
--
-- Bounding boxes instead: you are on the island whose footprint you are inside. Boxes are cached
-- because GetBoundingBox walks every part, but a box under ~50 studs across means the island had
-- not streamed in when it was measured, so that one is measured again rather than trusted.
local function boxOf(m)
	local b = boxes[m]
	if b and b.h.X > 25 and b.h.Z > 25 then return b end
	local ok, cf, size = pcall(function() return m:GetBoundingBox() end)
	if not ok or not cf then return nil end
	b = { c = cf.Position, h = size * 0.5 }
	boxes[m] = b
	return b
end

local function islandUnder(pos)
	local best, bestScore
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and norm(m.Name):sub(1, #ISLAND_PREFIX) == ISLAND_PREFIX then
			local b = boxOf(m)
			if b then
				-- how far OUTSIDE the footprint you are: zero while you are over it, at any height.
				-- Ties break toward the SMALLER island, so a big one cannot swallow a small one
				-- that sits inside its box.
				local dx = math.max(0, math.abs(pos.X - b.c.X) - b.h.X)
				local dz = math.max(0, math.abs(pos.Z - b.c.Z) - b.h.Z)
				local score = math.sqrt(dx * dx + dz * dz) * 1000 + (b.h.X + b.h.Z)
				if not bestScore or score < bestScore then best, bestScore = m, score end
			end
		end
	end
	return best
end

-- The NPC INSIDE that island, never a Workspace-wide search. Two neighbouring islands can be only
-- a few hundred studs apart, and a nearest-in-range sweep happily wires one island's quest giver
-- to the other -- which is exactly the bug two CandyRealm quests already hit.
local function npcIn(scope, from)
	local best, bestD
	for _, d in ipairs(scope:GetDescendants()) do
		if d:IsA("Model") and string.find(norm(d.Name), NPC_HINT, 1, true) then
			local part = d:FindFirstChild("Head") or d.PrimaryPart
				or d:FindFirstChildWhichIsA("BasePart", true)
			if part then
				local dist = (part.Position - from).Magnitude
				if not bestD or dist < bestD then best, bestD = part, dist end
			end
		end
	end
	return best
end

-- The trail lives in another script. If that one is missing or is an older copy without the NPC
-- slot, this script does everything right and nothing appears -- so say so, once, loudly, rather
-- than sitting there silently pointing at nobody.
task.delay(5, function()
	if not _G.guideTrailNpc then
		warn("[NpcGuide] no _G.guideTrailNpc -- arrows CANNOT draw. Make sure GuideTrail.client.luau is synced.")
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
	print(("  met      : %s"):format(island and tostring(reached[island.Name] == true) or "n/a"))
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

	-- Mid-flight the trail hides itself anyway, so skip the searching too -- but do NOT clear the
	-- target on the flag alone. If _G.isFlying lingers true after landing, clearing here means the
	-- trail never comes back, which is exactly the failure that is impossible to see from the
	-- outside. Keep the target; the trail decides whether to draw it.
	if _G.isFlying then return end

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
		if _G.guideTrailNpc then _G.guideTrailNpc(nil) end
		return
	end

	local d = (npcPart.Position - hrp.Position).Magnitude
	if d <= ARRIVE_DIST then
		reached[island.Name] = true
		if _G.guideTrailNpc then _G.guideTrailNpc(nil) end
		print(("[NpcGuide] reached %s's NPC -- no more arrows for it"):format(island.Name))
		return
	end
	if d > GUIDE_RANGE then
		if _G.guideTrailNpc then _G.guideTrailNpc(nil) end
		return
	end

	if _G.guideTrailNpc then _G.guideTrailNpc(npcPart.Position) end
end)

print("[NpcGuide] ready -- arrows to each island's NPC on landing")
