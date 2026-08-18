--[[
	IslandOrder.luau  (ReplicatedStorage.Shared.IslandOrder)  -- CandyRealm

	SINGLE SOURCE OF TRUTH for the Candy island TOWER ORDER + display names + positions.
	Ported from the Dino Realm's solved economy, re-solved for ELEVEN islands / TEN crossings.

	TOWER ORDER: slot 1 = the FIRST island (bottom) ... slot 11 = the SUMMIT. The player climbs
	slots in order, so a slot number IS the climb/progression position.

	THE MODEL NUMBERS ARE NOT CONTIGUOUS. This world has ELEVEN island models --
	1, 2, 3, 4, 5, 8, 9, 11, 13, 14, 15 -- with 6, 7, 10 and 12 never built. (See the boot-scan
	note in ReturnIsland.server.luau; island13 hosts the Forgotten Park, island14 Camp S'mores,
	island15 the Bake-Off.) Anything that loops `for i = 1, 11` over Workspace will miss the top
	three islands and warn about three that do not exist -- iterate SLOT_TO_ISLAND instead.

	SLOT ORDER IS SCRAMBLED against model number, the same way the Dino Realm's is, so the tower
	doesn't read as "1, 2, 3, ..." going up and players can't guess what's next from the name.

	TWO PINS, both deliberate:
	  * island1 AT SLOT 1 -- SpawnOnIsland1.server.luau spawns players there and the tutorial /
	    community garden / gumball quest are built on it.
	  * island15 AT SLOT 11 -- the Bake-Off is the finale, so it sits at the summit.

	THE SLOT/MODEL SPLIT IS THE WHOLE CONTRACT. CandyData.FOODS is ordered by SLOT and its
	prices/power are solved for the gap and tank size AT THAT SLOT, but each row's `island`
	field names the model that HOSTS the stand. Move an island here without moving that field
	and the stand travels with the model -- putting a slot-8 food (power 240) on slot 3 and a
	slot-3 food (power 45) on slot 8. Change both, together, or neither.
]]

local IslandOrder = {}

-- slot (1..11, bottom -> summit) -> island MODEL number ("island<N>" in Workspace).
-- A fixed scramble, NOT a runtime shuffle: positions have to be stable across server
-- restarts and identical on every client, or the shop gates and the wormhole disagree.
IslandOrder.SLOT_TO_ISLAND = { 1, 9, 3, 13, 5, 8, 2, 11, 4, 14, 15 }

-- slot -> world position. THE ladder: IslandLayout.server.luau moves each island here at
-- startup. Lives in the shared module because the CLIENT needs it too and cannot get it
-- from Workspace: with StreamingEnabled a distant island's MODEL replicates but its PARTS
-- do not, and GetPivot() on a partless model returns the origin.
--
-- THE SOLVE (same shape as the Dino Realm's, re-run for ten crossings):
--   * Y gaps grow 12% per crossing (3375 -> 9362), one gap per gut tier, TEN of each.
--   * 12% is LOAD-BEARING: a full tank climbs its own gap x MARGIN (1.08), so a gut is
--     locked out of the NEXT gap only if gaps grow by MORE than 8%. 12% clears that at
--     every step; ~8% growth silently makes guts unnecessary rather than unbuyable.
--   * Each gap is what a full tank climbs / 1.08 -- a clean run only just makes it, and
--     NO GUT REACHES THE GAP ABOVE ITS OWN, which is what makes the gut shop mandatory:
--       3645 < 3780   5066 < 5311   7143 < 7463
--       4053 < 4234   5678 < 5949   8012 < 8359
--       4526 < 4742   6368 < 6663   8985 < 9362
--     (the top coin gut, 1725, climbs 10074 and clears the last crossing with room)
--   * X and Z zig-zag: alternate sign, magnitude grows 20 studs per step.
--
--   gaps:  slot 1-2   3375     slot 5-6   5311     slot  9-10   8359
--          slot 2-3   3780     slot 6-7   5949     slot 10-11   9362
--          slot 3-4   4234     slot 7-8   6663
--          slot 4-5   4742     slot 8-9   7463
--
-- Summit is 59,388 -- well clear of ~100k+ where float precision jitters parts, with room
-- to extend upward if more islands get built.
--
-- CHANGE THESE AND YOU MUST RE-SOLVE FlightTuning.TIERS. The band speeds are the solution
-- to these exact gaps and nothing will warn you if they drift apart.
IslandOrder.SLOT_POS = {
	Vector3.new(   0,   150,    0),
	Vector3.new( 120,  3525,   60),
	Vector3.new(-160,  7305,  100),
	Vector3.new( 180, 11539, -120),
	Vector3.new(-200, 16281,  160),
	Vector3.new( 220, 21592, -180),
	Vector3.new(-240, 27541,  200),
	Vector3.new( 260, 34204, -220),
	Vector3.new(-280, 41667,  240),
	Vector3.new( 300, 50026, -260),
	Vector3.new(-320, 59388,  280),
}

-- SLOT -> display name (indexed by SLOT, not model number), so the wormhole and HUD list
-- them in climb order. Purely cosmetic -- nothing keys off these.
IslandOrder.NAMES = {
	"Candy Cane Court",    -- slot 1  = island1   (the start: tutorial, garden, gumball hunt)
	"Gumdrop Grove",       -- slot 2  = island9   (reactor cleanup)
	"Cookie Crumble",      -- slot 3  = island3   (cookie repair, chocolate monster)
	"Gumtree Park",        -- slot 4  = island13  (the Forgotten Park / ancient tree)
	"Taffy Town",          -- slot 5  = island5   (taffy storm)
	"Crystal Candy Caves", -- slot 6  = island8   (crystal mine)
	"Chocolate Chasm",     -- slot 7  = island2
	"Licorice Tunnels",    -- slot 8  = island11  (tunnel blast)
	"Frostbell Peak",      -- slot 9  = island4   (campfire freeze, summit bell)
	"Marshmallow Camp",    -- slot 10 = island14  (camp s'mores)
	"Bakery Summit",       -- slot 11 = island15  (the Bake-Off finale)
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

IslandOrder.COUNT = #IslandOrder.SLOT_TO_ISLAND                        -- 11 islands
IslandOrder.TOP_ISLAND = IslandOrder.SLOT_TO_ISLAND[IslandOrder.COUNT] -- island6 -- the summit MODEL

return IslandOrder
