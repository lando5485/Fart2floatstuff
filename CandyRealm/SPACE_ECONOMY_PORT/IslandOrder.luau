--!strict
--======================================================================
-- IslandOrder.luau  (ReplicatedStorage.Shared.IslandOrder)  -- CandyRealm
-- SPACE-REALM PORT: 12 islands, spaced by the Space Realm's own rule.
--======================================================================
-- WHAT CHANGED vs the old candy tower. The old solve was the Dino Realm's:
-- ELEVEN islands, gaps growing 12% per crossing (3375 -> 9362), and the wall was
-- TANK REACH (no gut climbs the gap above its own). The Space Realm does none of
-- that. Its gaps grow by a CONSTANT SECOND DIFFERENCE of +200, and its wall is a
-- HARD CEILING (your island + 400 studs), not reach. This file is the space rule,
-- run out to twelve islands.
--
-- ===== THE SPACING RULE (this is the whole thing) =====
-- Gaps:      1400, 2000, 2800, 3800, 5000, 6400, 8000, 9800, 11800, 14000, 16400
-- 1st diff:      600,  800, 1000, 1200, 1400, 1600, 1800,  2000,  2200,  2400
-- 2nd diff:         200,  200,  200,  200,  200,  200,   200,   200,   200
--
-- The second difference is a FLAT +200 -- that is the Space Realm's spacing law,
-- and the only thing that had to be extended to add four more islands. The first
-- eight Ys below are the Space Realm's PLANET_Y verbatim (Mercury 220 -> Neptune
-- 29620); slots 9-12 continue the same arithmetic.
--
-- Summit is 81,620 -- still well under ~100k, where float precision starts to
-- jitter parts, so the taller tower costs nothing in stability.
--
-- ===== TWO PINS KEPT FROM THE OLD TOWER =====
--   * island1 AT SLOT 1  -- SpawnOnIsland1.server.luau spawns players there and the
--     tutorial / community garden / gumball quest are built on it.
--   * island15 AT SLOT 12 -- the Great Bake-Off is the finale, so it stays at the summit.
--
-- ===== THE TWELFTH ISLAND IS NOT BUILT YET =====
-- The world has ELEVEN island models: 1, 2, 3, 4, 5, 8, 9, 11, 13, 14, 15 (6, 7, 10
-- and 12 were never built). A twelve-slot tower needs one more, and this file names
-- **island12** as the new SLOT 8. Until that model exists in Workspace, IslandLayout
-- will warn on slot 8 and the tower runs as eleven with a hole. Building any of
-- 6 / 7 / 10 instead is fine -- change the one number in SLOT_TO_ISLAND and the
-- matching `island` field in CandyData.FOODS, together.
--
-- ===== THE SLOT/MODEL SPLIT IS STILL THE CONTRACT =====
-- CandyData.FOODS is ordered by SLOT and each row's price/power is solved for the gap
-- and tank size AT THAT SLOT, but each row's `island` field names the model that HOSTS
-- the stand. Move an island here without moving that field and the stand travels with
-- the model, putting a slot-11 food (power 2000) on slot 3. Change both, or neither.
--======================================================================

local IslandOrder = {}

-- slot (1..12, bottom -> summit) -> island MODEL number ("island<N>" in Workspace).
-- A fixed scramble, NOT a runtime shuffle: positions have to be stable across server
-- restarts and identical on every client, or the shop gates and the wormhole disagree.
-- island12 at slot 8 is the NEW rung (see "THE TWELFTH ISLAND" above).
IslandOrder.SLOT_TO_ISLAND = { 1, 9, 3, 13, 5, 8, 2, 12, 11, 4, 14, 15 }

-- slot -> world position. THE ladder: IslandLayout.server.luau moves each island here at
-- startup. Lives in the shared module because the CLIENT needs it too and cannot get it
-- from Workspace: with StreamingEnabled a distant island's MODEL replicates but its PARTS
-- do not, and GetPivot() on a partless model returns the origin.
--
-- Y = the Space Realm ladder, extended. X and Z keep the candy zig-zag: alternate sign,
-- magnitude growing 20 studs per step.
--
--   gaps:  slot  1-2   1400     slot  5-6   5000     slot  9-10  11800
--          slot  2-3   2000     slot  6-7   6400     slot 10-11  14000
--          slot  3-4   2800     slot  7-8   8000     slot 11-12  16400
--          slot  4-5   3800     slot  8-9   9800
--
-- CHANGE THESE AND YOU MUST RE-SOLVE StomachTiers: every tank capacity is
-- ceil10(gap * 1.18 / 2.16), and every ceiling is the Y directly above.
IslandOrder.SLOT_POS = {
	Vector3.new(   0,   220,    0),  -- slot  1
	Vector3.new( 120,  1620,   60),  -- slot  2
	Vector3.new(-160,  3620,  100),  -- slot  3
	Vector3.new( 180,  6420, -120),  -- slot  4
	Vector3.new(-200, 10220,  160),  -- slot  5
	Vector3.new( 220, 15220, -180),  -- slot  6
	Vector3.new(-240, 21620,  200),  -- slot  7
	Vector3.new( 260, 29620, -220),  -- slot  8
	Vector3.new(-280, 39420,  240),  -- slot  9
	Vector3.new( 300, 51220, -260),  -- slot 10
	Vector3.new(-320, 65220,  280),  -- slot 11
	Vector3.new( 340, 81620, -300),  -- slot 12 (summit)
}

-- The crossing ABOVE each slot, in studs. Derived from SLOT_POS, but written out because
-- StomachTiers audits its capacities against it at boot and a derived-vs-declared mismatch
-- is exactly the drift that audit exists to catch.
IslandOrder.GAPS = { 1400, 2000, 2800, 3800, 5000, 6400, 8000, 9800, 11800, 14000, 16400 }

-- SLOT -> display name (indexed by SLOT, not model number), so the wormhole and HUD list
-- them in climb order. Purely cosmetic -- nothing keys off these.
IslandOrder.NAMES = {
	"Candy Cane Court",    -- slot  1 = island1   (the start: tutorial, garden, gumball hunt)
	"Gumdrop Grove",       -- slot  2 = island9   (reactor cleanup)
	"Cookie Crumble",      -- slot  3 = island3   (cookie repair, chocolate monster)
	"Gumtree Park",        -- slot  4 = island13  (the Forgotten Park / ancient tree)
	"Taffy Town",          -- slot  5 = island5   (taffy storm)
	"Crystal Candy Caves", -- slot  6 = island8   (crystal mine)
	"Chocolate Chasm",     -- slot  7 = island2   (NO QUEST YET -- see IslandConfig)
	"Sherbet Shelf",       -- slot  8 = island12  (NEW ISLAND -- not built, NO QUEST YET)
	"Licorice Tunnels",    -- slot  9 = island11  (tunnel blast)
	"Frostbell Peak",      -- slot 10 = island4   (campfire freeze, summit bell)
	"Marshmallow Camp",    -- slot 11 = island14  (camp smores)
	"Bakery Summit",       -- slot 12 = island15  (the Great Bake-Off finale)
}

-- derived inverse: island MODEL number -> slot (climb position).
IslandOrder.ISLAND_TO_SLOT = {}
for slot, islandNum in ipairs(IslandOrder.SLOT_TO_ISLAND) do
	IslandOrder.ISLAND_TO_SLOT[islandNum] = slot
end

-- model number -> display name, for anything holding an island number rather than a slot.
IslandOrder.NAME_BY_ISLAND = {}
for slot, islandNum in ipairs(IslandOrder.SLOT_TO_ISLAND) do
	IslandOrder.NAME_BY_ISLAND[islandNum] = IslandOrder.NAMES[slot]
end

IslandOrder.COUNT = #IslandOrder.SLOT_TO_ISLAND                        -- 12 islands
IslandOrder.TOP_ISLAND = IslandOrder.SLOT_TO_ISLAND[IslandOrder.COUNT] -- island15 -- the summit MODEL

-- The gap a player standing on `slot` must cross next, or nil at the summit.
function IslandOrder.gapFromSlot(slot: number): number?
	local s = math.floor(tonumber(slot) or 0)
	local here, next_ = IslandOrder.SLOT_POS[s], IslandOrder.SLOT_POS[s + 1]
	if not (here and next_) then
		return nil
	end
	return next_.Y - here.Y
end

-- BOOT AUDIT: the declared GAPS must match what SLOT_POS actually spaces. Server only.
if game:GetService("RunService"):IsServer() then
	for i = 1, IslandOrder.COUNT - 1 do
		local actual = IslandOrder.SLOT_POS[i + 1].Y - IslandOrder.SLOT_POS[i].Y
		if actual ~= IslandOrder.GAPS[i] then
			warn(("[IslandOrder] GAP DRIFT slot %d->%d: SLOT_POS says %d, GAPS says %d")
				:format(i, i + 1, actual, IslandOrder.GAPS[i]))
		end
	end
	print(("[IslandOrder] %d islands, summit Y=%d (space-realm spacing: 2nd difference +200)")
		:format(IslandOrder.COUNT, IslandOrder.SLOT_POS[IslandOrder.COUNT].Y))
end

return IslandOrder
