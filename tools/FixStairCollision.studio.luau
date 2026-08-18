--======================================================================
-- FixStairCollision.studio.luau  --  STUDIO COMMAND BAR ONLY (Rojo does not sync this)
--======================================================================
-- THE "SOMETHING KICKED ME OFF THE LADDER" BUG.
--
-- The climbs on islands 2, 3 and 5 are UnionOperations named "Stairs", and every one of them
-- has CollisionFidelity left at Default. For a thin, steep, diagonal union that setting builds
-- a crude collision hull that does NOT follow the visible steps -- it bulges out past them.
-- Walking up, you intermittently run into a lump of collision that is not where the geometry
-- looks like it is, and the character gets shoved sideways or off the edge. Whether you hit it
-- depends on your exact line up the stairs, which is why it happens some runs and not others.
--
-- The fix is CollisionFidelity = PreciseConvexDecomposition: the hull is then built to follow
-- the real shape, so the surface you can see is the surface you stand on.
--
-- ===== WHY THIS IS A STUDIO SCRIPT AND NOT A SERVER ONE =====
-- CollisionFidelity is LOCKED AT RUNTIME. A live server cannot change it -- assigning to it
-- from a Script silently does nothing. It has to be set at edit time and saved into the place,
-- which is exactly the same reason CandyRealm/studio/FixUnionCollision.lua is a Studio tool.
--
--   1. Open the place in Studio (EDIT mode, not a playtest).
--   2. View -> Command Bar.
--   3. Paste this whole file, press Enter.
--   4. Read the Output counts, walk-test a climb, then Ctrl+S / publish.
--
-- The whole run is ONE undo step (Ctrl+Z reverts all of it).
--
-- ===== SCOPE =====
-- Deliberately narrow: only CSG parts whose NAME looks like a climb, and only those. A blanket
-- pass over every union in the place would also convert decorative ones the player never walks
-- on, and Precise hulls are the expensive kind -- there is no reason to pay for that on scenery.
-- As of writing that is 18 parts (island 2: 2, island 3: 12, island 5: 4). If a climb somewhere
-- is named something else, add it to NAME_HINTS rather than widening the class filter.
--======================================================================

--=============================== CONFIG ===============================
local NAME_HINTS = { "stair", "ladder", "step", "ramp", "climb" }

-- Set false for a report-only run that changes nothing (do this first if you like).
local APPLY = true

-- Precise follows the visible shape; Hull is cheaper but still boxy on steep thin geometry,
-- which is the whole problem here. Leave this alone unless physics cost becomes a real issue.
local TARGET = Enum.CollisionFidelity.PreciseConvexDecomposition
--======================================================================

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local function looksLikeClimb(name)
	local n = string.lower(name)
	for _, h in ipairs(NAME_HINTS) do
		if string.find(n, h, 1, true) then return true end
	end
	return false
end

-- UnionOperation, NegateOperation and IntersectOperation all inherit PartOperation,
-- so one IsA check catches every CSG type.
local found, changed, already = {}, 0, 0
for _, inst in ipairs(workspace:GetDescendants()) do
	if inst:IsA("PartOperation") and looksLikeClimb(inst.Name) then
		table.insert(found, inst)
	end
end

table.sort(found, function(a, b) return a:GetFullName() < b:GetFullName() end)

print(("[StairFix] %d climb-like CSG parts found"):format(#found))

local recording
if APPLY then
	recording = ChangeHistoryService:TryBeginRecording("Fix stair collision fidelity")
end

for _, inst in ipairs(found) do
	local before = inst.CollisionFidelity
	if before == TARGET then
		already = already + 1
	elseif APPLY then
		local ok, err = pcall(function() inst.CollisionFidelity = TARGET end)
		if ok and inst.CollisionFidelity == TARGET then
			changed = changed + 1
			print(("  fixed   %s   (%s -> %s)"):format(inst:GetFullName(), before.Name, TARGET.Name))
		else
			-- Almost always means this was pasted into a PLAYTEST rather than edit mode.
			warn(("  FAILED  %s   -- %s"):format(inst:GetFullName(),
				tostring(err) .. " (CollisionFidelity is locked at runtime -- use EDIT mode)"))
		end
	else
		print(("  would fix %s   (%s)"):format(inst:GetFullName(), before.Name))
	end
end

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end

print(("[StairFix] done: %d changed, %d already correct, %d total%s")
	:format(changed, already, #found, APPLY and "" or "  (DRY RUN -- APPLY is false)"))
if changed > 0 then
	print("[StairFix] walk-test a climb on islands 2, 3 and 5, then SAVE AND PUBLISH -- "
		.. "this change only exists in the place file, so an unsaved Studio session loses it.")
end
