--======================================================================
-- IslandLayout.server.luau  (Server Script)  -- CandyRealm  -- RUNS FIRST
--======================================================================
-- Spaces the candy islands into the vertical "tower" layout, ported from the Dino
-- Realm's IslandLayout. Each island MODEL is moved to its slot position (rotation
-- preserved, children -- stands, NPCs, quest props -- come along). Then it sets
-- _G.islandsPositioned, which island-dependent scripts can wait on so their NPCs /
-- spawns land at the NEW positions.
--
-- THE MODEL NUMBERS ARE NOT CONTIGUOUS: this world has eleven islands numbered
-- 1,2,3,4,5,8,9,11,13,14,15 (6, 7, 10 and 12 were never built), and the climb order
-- scrambles them further. IslandOrder owns both facts; this script only applies them.
--
-- IT REPORTS WHAT IT ACTUALLY FOUND, and that is the point of the audit below. Getting
-- the model list wrong is silent by nature: a tower entry with no model leaves a slot
-- with nothing to land on (an unwinnable crossing), and an island model that is not in
-- the tower stays wherever Studio left it -- still visible, still walkable, but off the
-- ladder with its quests stranded. Neither throws. So both are printed loudly.
--
-- The Y values, the food prices in CandyData, the gut costs in StomachTiers, and
-- FLIGHT_SECONDS + the band speeds in FlightTuning are ONE INTERLOCKED SET -- retune
-- together or not at all. Edit positions in IslandOrder; this script only applies them.
--
--======================================================================
-- THE MOVE IS RIGID, AND STAYS RIGID
--======================================================================
-- "Correct in Studio, props floating on Play" is what a NON-rigid move looks like:
-- the island's ground arrives at its tower slot and something built on it does not
-- follow, so the prop hangs at the old offset. Four rules keep that from happening,
-- and each is verified rather than assumed:
--
--   1  ONE CALL. The whole model moves with a single PivotTo. Never a loop over
--      parts assigning Position/Y -- that is a rigid move only if every part is
--      reached, and the one it misses is the bug.
--   2  A REAL PRIMARYPART. Set to the base terrain slab when the builder left it
--      empty, so the model has a defined anchor rather than a bounding-box centre
--      that shifts as props are added.
--   3  ANCHOR EVERYTHING FOR THE DURATION OF THE MOVE, then restore each part's
--      real Anchored value. This is the opposite of the obvious guess, and the
--      obvious guess is wrong: anchoring does NOT leave a part behind -- anchored
--      parts follow a PivotTo exactly, each one its own assembly, each CFrame
--      write independent and final. It is UNANCHORED parts that get left behind.
--      A loose part welded into an assembly is moved by the assembly, not by the
--      write; if anything in that assembly is anchored (very common -- a free
--      model welded to island scenery) the write is reverted the instant it
--      lands, and the part stays at its old CFrame while the island leaves.
--      Measured, not theorised: un-anchoring first left 92 parts behind across
--      islands 1/4/11/13, each by exactly its island's full translation, and
--      island4's list was an NPC rig ("Left Leg", "Right Arm") -- precisely the
--      parts AnchorIslands deliberately does not anchor.
--      No yield happens inside the anchor/pivot/restore block, so physics never
--      gets a step at which a temporarily-anchored rig could misbehave.
--   4  PROVE IT, THEN FIX WHAT FAILED. Every part's CFrame is recorded in the
--      island pivot's OBJECT space before the move and re-checked after; a rigid
--      move changes none of them. Anything that did change is force-written back
--      to pivot * savedOffset while it is still anchored, and re-checked again.
--      The summary prints drifted / repaired / still wrong, and "still wrong"
--      is the only number that matters -- it must be 0.
--
-- WHAT NO PIVOT CAN FIX: a BasePart parented to Workspace instead of into the
-- island model. It is not a child, so it does not move, and it is left 59,000
-- studs below the island it belongs to. Those cannot be fixed from here -- they
-- have to be reparented in Studio -- so they are found and named in the audit.
--
-- PRIMARYPART CHANGES WHAT GetPivot() RETURNS -- careful. With no PrimaryPart the
-- pivot is the model's WorldPivot (bounding-box centre by default); once one is
-- set, it is the PrimaryPart's own CFrame. The tower's Y values were authored
-- against the FORMER, so "PivotTo(CFrame.new(pos))" after setting a PrimaryPart
-- would silently drop every island by roughly half its height. This file therefore
-- measures the required TRANSLATION before touching PrimaryPart and then applies
-- that translation -- a translation is a translation whatever the pivot is, so the
-- placement is bit-identical to the version that had no PrimaryPart.
--======================================================================
local Workspace = game:GetService("Workspace")

local IslandOrder = require(game:GetService("ReplicatedStorage")
	:WaitForChild("Shared"):WaitForChild("IslandOrder"))
local SLOT_POS       = IslandOrder.SLOT_POS
local SLOT_TO_ISLAND = IslandOrder.SLOT_TO_ISLAND

local TOP_SLOT = IslandOrder.COUNT

local DRIFT_EPSILON = 0.01   -- studs; float noise in a CFrame round-trip, not movement
local LOOSE_MARGIN  = 12     -- studs of slop around an island's box when hunting loose parts
local LOOSE_LIST_MAX = 40    -- names printed per island before the list is truncated

--======================================================================
-- PRIMARYPART  (rule 2)
--======================================================================
-- The base terrain slab: by name if the builder named it like one, otherwise the
-- biggest flat footprint in the model. Deliberately NOT "the biggest part by
-- volume" -- a tall decorative tower can beat the floor on volume and would make
-- a nonsense anchor.
local GROUND_NAMES = { "base", "ground", "floor", "terrain", "slab", "platform", "chickenzone" }

local function normName(s: string): string
	return (string.lower(s):gsub("[%s_%-]", ""))
end

local function looksLikeGroundName(name: string): boolean
	local n = normName(name)
	for _, pat in ipairs(GROUND_NAMES) do
		if string.find(n, pat, 1, true) then return true end
	end
	return false
end

local function pickBasePart(isl: Model): BasePart?
	local best, bestArea, bestNamed = nil, -1, false
	for _, d in ipairs(isl:GetDescendants()) do
		if d:IsA("BasePart") then
			local area = d.Size.X * d.Size.Z
			local named = looksLikeGroundName(d.Name)
			-- A name match outranks any amount of area; among equals, area wins.
			if (named and not bestNamed) or (named == bestNamed and area > bestArea) then
				best, bestArea, bestNamed = d, area, named
			end
		end
	end
	return best
end

--======================================================================
-- THE STATIC TEST -- IDENTICAL TO AnchorIslands
--======================================================================
-- Copied deliberately rather than shared through a module, because these two
-- scripts must not be able to disagree about what "static" means and neither
-- owns a module the other could require without a load-order problem. If you
-- change one, change the other: AnchorIslands.isStatic is the twin of this.
--
-- A part is static only if nothing else is driving it: not the driven side of
-- a weld, not inside a Tool or Accessory, not inside a model with a Humanoid.
-- Anchoring any of those breaks the thing that animates it.
local function buildWeldedSet(): { [BasePart]: boolean }
	local welded = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") then
			if d.Part1 then welded[d.Part1] = true end
		end
	end
	return welded
end

local function isStatic(part: BasePart, welded: { [BasePart]: boolean }): boolean
	if welded[part] then return false end
	if part:FindFirstAncestorWhichIsA("Tool") then return false end
	if part:FindFirstAncestorWhichIsA("Accessory") then return false end

	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildWhichIsA("Humanoid") then return false end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return true
end

-- Built once, before any island moves. Rebuilding it per island would be
-- O(islands x Workspace) and would stall startup.
local weldedSet = buildWeldedSet()

--======================================================================
-- RIGIDITY PROOF  (rule 4)
--======================================================================
-- Each part's CFrame expressed in the pivot's object space. A rigid move carries
-- the pivot and the parts together, so every one of these is unchanged afterwards.
local function snapshotOffsets(isl: Model)
	local pivot = isl:GetPivot()
	local snap = {}
	for _, d in ipairs(isl:GetDescendants()) do
		if d:IsA("BasePart") then
			snap[d] = pivot:ToObjectSpace(d.CFrame)
		end
	end
	return snap
end

local function countDrift(isl: Model, snap): (number, { string })
	local pivot = isl:GetPivot()
	local drifted, names = 0, {}
	for part, was in pairs(snap) do
		if part.Parent then   -- something deleted mid-move is not drift
			local now = pivot:ToObjectSpace(part.CFrame)
			if (now.Position - was.Position).Magnitude > DRIFT_EPSILON then
				drifted += 1
				if #names < 20 then
					names[#names + 1] = ("%s (%.2f studs)")
						:format(part.Name, (now.Position - was.Position).Magnitude)
				end
			end
		end
	end
	return drifted, names
end

--======================================================================
-- LOOSE PARTS: BELONG TO THE ISLAND, NOT PARENTED TO IT
--======================================================================
-- Run BEFORE the move, while the island is still at its Studio position -- that is
-- the only moment a loose part is still sitting where it looks like it belongs.
-- Direct Workspace children only: anything deeper is inside some other model and
-- is that model's problem.
local function findLooseParts(isl: Model): { string }
	local cf, size = isl:GetBoundingBox()
	local half = size * 0.5 + Vector3.new(LOOSE_MARGIN, LOOSE_MARGIN, LOOSE_MARGIN)
	local found = {}

	for _, d in ipairs(Workspace:GetChildren()) do
		if d:IsA("BasePart") and d ~= Workspace.Terrain then
			local o = cf:PointToObjectSpace(d.Position)
			if math.abs(o.X) <= half.X and math.abs(o.Y) <= half.Y and math.abs(o.Z) <= half.Z then
				found[#found + 1] = ("%s  (%s at %d, %d, %d)")
					:format(d.Name, d.ClassName, d.Position.X, d.Position.Y, d.Position.Z)
			end
		end
	end
	return found
end

--======================================================================
-- THE MOVE  (rules 1 + 3)
--======================================================================
local function rigidMove(isl: Model, targetPos: Vector3, verbose: boolean): (boolean, string?, number)
	-- (a) Required translation, measured against the pivot semantics the tower's Y
	--     values were authored against -- i.e. BEFORE PrimaryPart is touched.
	local authoredPivot = isl:GetPivot()
	local delta = targetPos - authoredPivot.Position

	-- (b) PrimaryPart, if the builder left it empty.
	if not isl.PrimaryPart then
		local base = pickBasePart(isl)
		if base then
			isl.PrimaryPart = base
			if verbose then
				print(("[IslandLayout] %s PrimaryPart was unset -> %s (%.0f x %.0f footprint)")
					:format(isl.Name, base.Name, base.Size.X, base.Size.Z))
			end
		else
			return false, "no BasePart in the model -- cannot set a PrimaryPart", 0
		end
	end

	local before = isl:GetPivot()
	if verbose then
		print(("[IslandLayout] %s pivot BEFORE: (%.1f, %.1f, %.1f)  [PrimaryPart = %s]")
			:format(isl.Name, before.Position.X, before.Position.Y, before.Position.Z,
				isl.PrimaryPart and isl.PrimaryPart.Name or "none"))
	end

	local snap = snapshotOffsets(isl)

	-- (c) Anchor everything -> pivot -> repair -> restore the real anchor state.
	--     No yield anywhere in here, so no physics step lands in the middle.
	local wasAnchored = {}
	for _, d in ipairs(isl:GetDescendants()) do
		if d:IsA("BasePart") then
			wasAnchored[d] = d.Anchored
			d.Anchored = true
		end
	end

	local ok, err = pcall(function()
		isl:PivotTo(before + delta)   -- ONE call, whole model, rotation untouched
	end)

	local after = isl:GetPivot()
	local drifted, names = 0, {}
	local repaired, stillWrong = 0, 0

	if ok then
		drifted, names = countDrift(isl, snap)

		-- REPAIR. Anything the pivot failed to carry is written back explicitly,
		-- while it is still anchored so the write cannot be reverted by an
		-- assembly. This is not papering over the failure -- the offsets come
		-- from the pre-move snapshot, so the result is the rigid transform the
		-- PivotTo was supposed to produce.
		if drifted > 0 then
			for part, was in pairs(snap) do
				if part.Parent then
					local target = after * was
					if (part.CFrame.Position - target.Position).Magnitude > DRIFT_EPSILON then
						part.CFrame = target
						repaired += 1
					end
				end
			end
			stillWrong = countDrift(isl, snap)
		end
	end

	-- ANCHOR THE STATIC PARTS *NOW*, IN THIS FRAME. Same rule for every island.
	--
	-- Restoring the raw Anchored state here is what caused the "perfect at the
	-- intro, then everything shifts" bug. IslandLayout finished at 35.398 and
	-- AnchorIslands' pass1 did not run until 35.948 -- half a second in which a
	-- few hundred just-teleported loose parts are simulated, settle, and shove
	-- each other 2-10 studs. Measured: 413 objects moved within 5s, and the
	-- Bakery slab's floor drifted 59430 -> 59435.
	--
	-- The parts AnchorIslands would anchor anyway are anchored right here
	-- instead, in the same frame as the pivot, so physics never gets a step at
	-- them. This is not special treatment for island15 -- it is the identical
	-- static test AnchorIslands uses (see isStatic there), applied to all eleven
	-- islands, just half a second earlier. Anything that test skips -- welded rig
	-- parts, NPC limbs, Tool contents -- gets its real state back exactly as
	-- before, so nothing that is meant to move stops moving.
	local anchoredEarly = 0
	for part, anchored in pairs(wasAnchored) do
		if part.Parent then
			if anchored then
				part.Anchored = true
			elseif isStatic(part, weldedSet) then
				part.Anchored = true       -- AnchorIslands' job, done in time to matter
				anchoredEarly += 1
			else
				part.Anchored = false      -- rig / NPC / tool: must stay loose
			end
		end
	end
	if verbose and anchoredEarly > 0 then
		print(("[IslandLayout] %s -- %d static part(s) anchored in the move frame (no physics gap)")
			:format(isl.Name, anchoredEarly))
	end

	if not ok then
		return false, ("PivotTo failed: %s"):format(tostring(err)), 0
	end

	if verbose then
		print(("[IslandLayout] %s pivot AFTER:  (%.1f, %.1f, %.1f)")
			:format(isl.Name, after.Position.X, after.Position.Y, after.Position.Z))
		print(("[IslandLayout] %s parts whose offset from the pivot changed: %d (expected 0)")
			:format(isl.Name, stillWrong))
	end
	if drifted > 0 then
		warn(("[IslandLayout] %s -- PivotTo left %d part(s) behind, %d repaired, %d STILL WRONG. First few: %s")
			:format(isl.Name, drifted, repaired, stillWrong, table.concat(names, ", ")))
	end

	return true, nil, stillWrong
end

--======================================================================
-- PLACE THE TOWER
--======================================================================
local placed, missing = {}, {}
local looseByIsland = {}
local totalDrift = 0

for slot = 1, TOP_SLOT do
	local islandNum = SLOT_TO_ISLAND[slot]
	local pos = SLOT_POS[slot]
	local isl = Workspace:FindFirstChild("island" .. islandNum)

	if isl and isl:IsA("Model") and pos then
		-- Island 15 (the Bakery Summit) is the one this was debugged on, so it gets
		-- the full before/after/drift trace. The others report only on failure.
		local verbose = (islandNum == 15)

		local loose = findLooseParts(isl)   -- BEFORE the move, while it is still in place
		if #loose > 0 then looseByIsland[isl.Name] = loose end

		local ok, err, drifted = rigidMove(isl, pos, verbose)
		totalDrift += drifted

		if ok then
			placed[islandNum] = true
			print(("[IslandLayout] slot %2d -> island%-2d  %-20s @ (%d, %d, %d)")
				:format(slot, islandNum, IslandOrder.NAMES[slot] or "?", pos.X, pos.Y, pos.Z))
		else
			missing[#missing + 1] = ("island%d (slot %d) -- %s"):format(islandNum, slot, err or "?")
		end
	else
		missing[#missing + 1] = ("island%d (slot %d) -- no such model in Workspace"):format(islandNum, slot)
	end
end

-- Only NOW is it true. Anything that reads island positions (AnchorIslands, NPC
-- spawners, quest props) waits on this rather than on start order.
_G.islandsPositioned = true
Workspace:SetAttribute("IslandsPositioned", true)   -- same latch, readable from the client

-- ---- AUDIT ---------------------------------------------------------------
-- Any island model in Workspace that the tower does NOT reference. These keep their
-- Studio position while everything else moves, so their quests end up orphaned at an
-- altitude no crossing reaches.
local orphans = {}
for _, d in ipairs(Workspace:GetChildren()) do
	if d:IsA("Model") then
		local n = tonumber(string.match(string.lower(d.Name), "^island[ _]?(%d+)$"))
		if n and not placed[n] then
			orphans[#orphans + 1] = d.Name
		end
	end
end

print(("[IslandLayout] %d/%d islands placed into the tower. Parts left non-rigid AFTER repair: %d (must be 0)")
	:format(TOP_SLOT - #missing, TOP_SLOT, totalDrift))

if #missing > 0 then
	warn("[IslandLayout] ===== TOWER SLOTS WITH NO ISLAND =====")
	for _, m in ipairs(missing) do warn("  ! " .. m) end
	warn("  These slots have NOTHING TO LAND ON -- the crossing into them is unwinnable.")
	warn("  Fix IslandOrder.SLOT_TO_ISLAND to match the models that actually exist.")
end

if #orphans > 0 then
	warn("[IslandLayout] ===== ISLAND MODELS NOT IN THE TOWER =====")
	warn("  " .. table.concat(orphans, ", "))
	warn("  These were left at their Studio positions. Anything built on them (quests,")
	warn("  stands, NPCs) is off the ladder. Add them to IslandOrder.SLOT_TO_ISLAND and")
	warn("  re-solve the economy, or delete them.")
end

if next(looseByIsland) then
	warn("[IslandLayout] ===== LOOSE PARTS -- IN WORKSPACE, NOT IN THE ISLAND MODEL =====")
	warn("  These sat inside an island's bounding box in Studio but are parented to")
	warn("  Workspace, so the PivotTo did NOT move them. They are still at their Studio")
	warn("  coordinates, tens of thousands of studs below the island they belong to.")
	warn("  FIX: in Studio, drag each into its island model, then re-run.")
	for islName, list in pairs(looseByIsland) do
		warn(("  -- %s: %d loose part(s)"):format(islName, #list))
		for i, entry in ipairs(list) do
			if i > LOOSE_LIST_MAX then
				warn(("     ...and %d more"):format(#list - LOOSE_LIST_MAX))
				break
			end
			warn("     " .. entry)
		end
	end
end
