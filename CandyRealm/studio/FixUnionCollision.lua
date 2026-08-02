--======================================================================
-- FixUnionCollision.lua  -- STUDIO COMMAND BAR ONLY (not synced by Rojo)
--======================================================================
-- Fixes invisible collision walls caused by CSG parts (unions/negates/
-- intersects) whose collision hull is a chunky box bigger than the
-- visible shape. CollisionFidelity is LOCKED at runtime, so this must
-- run in Studio:
--
--   1. Open the place in Studio (edit mode, not playtest).
--   2. View -> Command Bar.
--   3. Paste this whole file and press Enter.
--   4. Check the Output counts, walk-test, then Ctrl+S to save.
--
-- The whole run is one undo step (Ctrl+Z reverts everything).
--======================================================================

--=============================== CONFIG ===============================
-- Union/negate/intersect NAMES to leave completely untouched (not case
-- sensitive). Add names here if a specific union should keep its
-- current collision setup.
local EXCLUDE_NAMES = {
	-- "KillBrick",
	-- "SecretDoor",
}

-- Second pass toggle:
--   * CSG parts anywhere under a Folder named "Decor" get Hull instead
--     of Precise (cheaper physics for stuff you never walk on).
--   * CSG parts tagged "NoCollide" (CollectionService tag) get
--     CanCollide = false entirely.
local RUN_SECOND_PASS = false
--======================================================================

local CollectionService = game:GetService("CollectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local excluded = {}
for _, name in ipairs(EXCLUDE_NAMES) do
	excluded[string.lower(name)] = true
end

-- UnionOperation, NegateOperation and IntersectOperation all inherit
-- from PartOperation, so one IsA check catches all three.
local function isCSG(inst)
	return inst:IsA("PartOperation")
end

local function underDecorFolder(inst)
	local node = inst.Parent
	while node and node ~= workspace do
		if node:IsA("Folder") and node.Name == "Decor" then return true end
		node = node.Parent
	end
	return false
end

ChangeHistoryService:SetWaypoint("Before FixUnionCollision")

-- PASS 1: precise collision for every non-excluded CSG part.
local changed, skipped = 0, 0
for _, d in ipairs(workspace:GetDescendants()) do
	if isCSG(d) then
		if excluded[string.lower(d.Name)] then
			skipped += 1
		elseif d.CollisionFidelity ~= Enum.CollisionFidelity.PreciseConvexDecomposition then
			d.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
			changed += 1
		end
	end
end
print(("[FixUnionCollision] pass 1: %d union(s) set to PreciseConvexDecomposition, %d excluded by name"):format(changed, skipped))

-- PASS 2 (optional): Decor folders get cheap hulls, "NoCollide" tags
-- lose collision entirely. Runs after pass 1 so it wins for those parts.
if RUN_SECOND_PASS then
	local hulled, uncollided = 0, 0
	for _, d in ipairs(workspace:GetDescendants()) do
		if isCSG(d) and not excluded[string.lower(d.Name)] then
			if underDecorFolder(d) and d.CollisionFidelity ~= Enum.CollisionFidelity.Hull then
				d.CollisionFidelity = Enum.CollisionFidelity.Hull
				hulled += 1
			end
			if CollectionService:HasTag(d, "NoCollide") and d.CanCollide then
				d.CanCollide = false
				uncollided += 1
			end
		end
	end
	print(("[FixUnionCollision] pass 2: %d Decor union(s) set to Hull, %d NoCollide-tagged union(s) had CanCollide turned off"):format(hulled, uncollided))
end

ChangeHistoryService:SetWaypoint("After FixUnionCollision")
print("[FixUnionCollision] done -- walk-test, then Ctrl+S to save (Ctrl+Z undoes everything)")
