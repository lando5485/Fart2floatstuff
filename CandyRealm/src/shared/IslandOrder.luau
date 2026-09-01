--!strict
--======================================================================
-- IslandOrder.luau  (ModuleScript -> ReplicatedStorage.Shared)  -- CandyRealm
-- FOOD-REALM PORT: 13 islands on the first realm's tower, positions copied exactly.
--======================================================================
-- WHERE EVERY ISLAND SITS. The single copy: IslandLayout.server moves the Workspace models
-- here at boot and every client reads the same table for gaps and coin payouts.
--
-- ===== THE SPACING IS THE FOOD REALM'S, VERBATIM =====
-- Y values are the first realm's IslandOrder.SLOT_POS, slots 1-13 -- which are themselves the
-- F2F UNIVERSAL PROGRESSION GUIDE's shipped tower (the Dinosaur Realm's). The food realm adds
-- a 14th island; candy has thirteen models, so the tower stops at the guide's own summit.
--
-- ===== THE STRUCTURE: one gut = one WALL crossing + one STRETCH crossing =====
--   wall gap    = previous gut's full-tank climb x 1.020  (97%+ of the way on a full tank
--                 and you still cannot land -- that 2% IS the "buy a gut" message)
--   stretch gap = own gut's climb / 1.031                 (97% of the new tank)
-- FlightTuning.BASE_TIERS holds the climbs; do NOT move an island without re-running
-- tools/ladder.py -- the gates `climb[k] >= own gaps` and `climb[k] + coast < next tier's
-- gaps` are both asserted there.
--
-- Gaps (slot -> slot+1), wall / stretch pairs per gut:
--   c1   630.0  Gumdrop Belly (tutorial, 1.355x headroom)
--   c2  1068.0  Taffy Tummy   wall   (25.1% past the starting tank -- the tutorial exit)
--   c3  1242.0  Taffy Tummy   stretch
--   c4  1305.0  Cookie Gut    wall   (= 1279.5 * 1.020)
--   c5  1792.5  Cookie Gut    stretch(= 1848.0 / 1.031)
--   c6  1885.5  Jelly Belly   wall
--   c7  2482.5  Jelly Belly   stretch
--   c8  2610.0  Gummy Gut     wall
--   c9  3448.5  Gummy Gut     stretch
--   c10 3625.5  Choco Stomach wall
--   c11 4827.0  Choco Stomach stretch
--   c12 6200.0  Caramel Core  wall   (24.6% past the XXL reach -- the summit grind)
--
-- X/Z alternate sign and grow slowly. That is a READABILITY device, not a mechanic: nothing
-- in the flight model reads X or Z. It makes the tower visibly spiral and stops islands
-- occluding each other when you look straight up.
--
-- ===== THE PINS =====
--   * island1 AT SLOT 1  -- SpawnOnIsland1.server spawns players there and the tutorial /
--     community garden / troll bridge are built on it.
--   * island16 AT THE SUMMIT (slot 13) -- POP ROCK QUARRY is the ending island by request.
--
-- ===== THE SLOT/MODEL SPLIT IS THE WHOLE CONTRACT =====
-- CandyData.FOODS is ordered by SLOT and each row's price/power is the food realm's row for
-- that slot, but each row's `island` field names the model that HOSTS the stand. Move an
-- island here without moving that field and the stand travels with the model, putting a
-- slot-12 food on slot 3. Change both, or neither. IslandConfig.ISLANDS carries the same
-- pairing and must move with them.
--======================================================================

local IslandOrder = {}

-- Must match FlightTuning.SPACING_SCALE. Its job is to divide COIN_PER_STUD_BASE at the
-- point of use so respacing the tower does not change what a flight pays.
IslandOrder.SPACING_SCALE = 0.6825

-- ============================================================================
-- THE ONE TABLE TO CHECK AGAINST YOUR ACTUAL WORKSPACE
-- ============================================================================
-- slot (1..13, bottom -> summit) -> island MODEL number ("island<N>" in Workspace).
-- A fixed scramble, NOT a runtime shuffle: positions have to be stable across server
-- restarts and identical on every client, or the shop gates and the wormhole disagree.
--
-- THE TOWER IS EVERY QUEST-BEARING ISLAND, AND THERE ARE EXACTLY THIRTEEN:
-- 1, 3, 4, 5, 8, 9, 11, 13, 14, 15, 16, 18, 19. island2 was never built.
IslandOrder.SLOT_TO_ISLAND = { 1, 9, 3, 13, 5, 8, 18, 15, 11, 4, 14, 19, 16 }

-- slot -> world position. THE ladder: IslandLayout.server.luau moves each island here at
-- startup. Lives in the shared module because the CLIENT needs it too and cannot get it
-- from Workspace: with StreamingEnabled a distant island's MODEL replicates but its PARTS
-- do not, and GetPivot() on a partless model returns the origin.
--
-- Y = the food realm's SLOT_POS, slots 1-13, exactly. X/Z are the food realm's too.
IslandOrder.SLOT_POS = {
	Vector3.new(   0,   150,      0),  -- slot  1
	Vector3.new( 120,   780,     60),  -- slot  2
	Vector3.new(-160,  1848,    100),  -- slot  3
	Vector3.new( 180,  3090,   -120),  -- slot  4
	Vector3.new(-200,  4395,    160),  -- slot  5
	Vector3.new( 220,  6187.5, -180),  -- slot  6
	Vector3.new(-240,  8073,    200),  -- slot  7
	Vector3.new( 260, 10555.5, -220),  -- slot  8
	Vector3.new(-280, 13165.5,  240),  -- slot  9
	Vector3.new( 300, 16614,   -260),  -- slot 10
	Vector3.new(-320, 20239.5,  280),  -- slot 11
	Vector3.new( 340, 25066.5, -300),  -- slot 12
	Vector3.new(-360, 31266.5,  320),  -- slot 13 (summit)
}

-- The crossing ABOVE each slot, in studs. Derived from SLOT_POS, but written out because
-- StomachTiers audits its climbs against it at boot and a derived-vs-declared mismatch is
-- exactly the drift that audit exists to catch.
IslandOrder.GAPS = { 630, 1068, 1242, 1305, 1792.5, 1885.5, 2482.5, 2610, 3448.5, 3625.5, 4827, 6200 }

-- SLOT -> display name (indexed by SLOT, not model number), so the wormhole and HUD list
-- them in climb order. Purely cosmetic -- nothing keys off these.
IslandOrder.NAMES = {
	"Candy Cane Court",    -- slot  1 = island1   (the start: tutorial, garden, troll bridge)
	"Cocoa Reactor",       -- slot  2 = island9   (reactor cleanup)
	"Cookie Crumble",      -- slot  3 = island3   (cookie repair, chocolate monster)
	"Gumtree Park",        -- slot  4 = island13  (the Forgotten Park / ancient tree)
	"Taffy Town",          -- slot  5 = island5   (taffy storm)
	"Crystal Candy Caves", -- slot  6 = island8   (crystal mine)
	"Pancake Arena",       -- slot  7 = island18  (wake the pancake monster)
	"Bakery Summit",       -- slot  8 = island15  (the Great Bake-Off)
	"Licorice Tunnels",    -- slot  9 = island11  (tunnel blast)
	"Frostbell Peak",      -- slot 10 = island4   (campfire freeze, summit bell)
	"Marshmallow Camp",    -- slot 11 = island14  (camp smores)
	"Sugarbeet Farm",      -- slot 12 = island19  (broken tractor)
	"Pop Rock Quarry",     -- slot 13 = island16  (candy mine explosion -- THE ENDING ISLAND)
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

IslandOrder.COUNT = #IslandOrder.SLOT_TO_ISLAND                        -- 13 islands
IslandOrder.TOP_ISLAND = IslandOrder.SLOT_TO_ISLAND[IslandOrder.COUNT] -- island16 -- the summit MODEL

--[[ The gap a player standing on `slot` must cross next, or nil at the summit. ]]
function IslandOrder.gapFromSlot(slot: number): number?
	local s = math.floor(tonumber(slot) or 0)
	local here, next_ = IslandOrder.SLOT_POS[s], IslandOrder.SLOT_POS[s + 1]
	if not (here and next_) then
		return nil
	end
	return next_.Y - here.Y
end

-- Food-realm spelling of the same lookup (CoreClient calls it `gap`).
IslandOrder.gap = IslandOrder.gapFromSlot

-- BOOT AUDIT: the declared GAPS must match what SLOT_POS actually spaces. Server only.
if game:GetService("RunService"):IsServer() then
	for i = 1, IslandOrder.COUNT - 1 do
		local actual = IslandOrder.SLOT_POS[i + 1].Y - IslandOrder.SLOT_POS[i].Y
		if math.abs(actual - IslandOrder.GAPS[i]) > 0.01 then
			warn(("[IslandOrder] GAP DRIFT slot %d->%d: SLOT_POS says %.1f, GAPS says %.1f")
				:format(i, i + 1, actual, IslandOrder.GAPS[i]))
		end
	end
	print(("[IslandOrder] %d islands, summit Y=%.1f (food-realm spacing: wall x1.020 / stretch /1.031)")
		:format(IslandOrder.COUNT, IslandOrder.SLOT_POS[IslandOrder.COUNT].Y))
end

return IslandOrder
