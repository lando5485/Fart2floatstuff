--======================================================================
-- IslandOrder.luau  (ModuleScript -> ReplicatedStorage/Shared)
--======================================================================
-- WHERE EVERY ISLAND SITS. The single copy: PlayerStats positions the Workspace models
-- from SLOT_POS at boot and CoreClient reads the same table for gaps and coin payouts.
--
-- Y values are copied from the F2F UNIVERSAL PROGRESSION GUIDE (the Dinosaur Realm's
-- shipped tower) -- slots 1-13 exactly. Island 14 is the one addition: the guide's tower
-- is 13 islands, ours is 14, so the top gut (Iron, climb 7110) covers two crossings like
-- every other gut does -- c12 is its wall (6200, widened for the summit grind) and c13 is
-- its stretch at 7110 / 1.031 = 6896.2.
--
-- X/Z alternate sign and grow slowly. That is a READABILITY device, not a mechanic:
-- nothing in the flight model reads X or Z. It makes the tower visibly spiral and stops
-- islands occluding each other when you look straight up. Keep some lateral offset.
--
-- Food Realm islands are numbered in climb order, so slot == island number and
-- SLOT_TO_ISLAND is the identity. KEEP THE TABLE anyway -- it is what lets the order be
-- changed later without touching every call site.
--
-- Gaps (slot -> slot+1), for reference -- wall / stretch pairs per gut:
--   c1   630.0  Tiny     (tutorial, 1.355x headroom)
--   c2  1068.0  Small    wall   (25.1% past Tiny's reach -- the tutorial exit)
--   c3  1242.0  Small    stretch
--   c4  1305.0  Medium   wall   (= 1279.5 * 1.020)
--   c5  1792.5  Medium   stretch(= 1848.0 / 1.031)
--   c6  1885.5  Large    wall
--   c7  2482.5  Large    stretch
--   c8  2610.0  XL       wall
--   c9  3448.5  XL       stretch
--   c10 3625.5  XXL      wall
--   c11 4827.0  XXL      stretch
--   c12 6200.0  Iron     wall   (24.6% past XXL's reach -- the summit grind)
--   c13 6896.2  Iron     stretch
--======================================================================

local IslandOrder = {}

-- Must match FlightTuning.SPACING_SCALE. Its job is to divide COIN_PER_STUD_BASE at the
-- point of use so respacing the tower does not change what a flight pays.
IslandOrder.SPACING_SCALE = 0.6825

IslandOrder.SLOT_POS = {
	{ x = 0,    y = 150,     z = 0    },  -- 1  Bean Farm
	{ x = 120,  y = 780,     z = 60   },  -- 2  Broccoli Bluff
	{ x = -160, y = 1848,    z = 100  },  -- 3  Cabbage Cliffs
	{ x = 180,  y = 3090,    z = -120 },  -- 4  Turnip Tranquil
	{ x = -200, y = 4395,    z = 160  },  -- 5  Coconut Cove
	{ x = 220,  y = 6187.5,  z = -180 },  -- 6  Bread Board
	{ x = -240, y = 8073,    z = 200  },  -- 7  Pasta Peak
	{ x = 260,  y = 10555.5, z = -220 },  -- 8  Popcorn Pinnacle
	{ x = -280, y = 13165.5, z = 240  },  -- 9  Milk Marsh
	{ x = 300,  y = 16614,   z = -260 },  -- 10 Butter Swamp
	{ x = -320, y = 20239.5, z = 280  },  -- 11 Ice Cream Isle
	{ x = 340,  y = 25066.5, z = -300 },  -- 12 Burger Bluff
	{ x = -360, y = 31266.5, z = 320  },  -- 13 Burrito Barrens
	{ x = 380,  y = 38162.7, z = -340 },  -- 14 Pizza Palms  (31266.5 + 6896.2)
}

IslandOrder.SLOT_TO_ISLAND = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 }
IslandOrder.ISLAND_TO_SLOT = {}
for slot, island in ipairs(IslandOrder.SLOT_TO_ISLAND) do
	IslandOrder.ISLAND_TO_SLOT[island] = slot
end

IslandOrder.NAMES = {
	"Bean Farm","Broccoli Bluff","Cabbage Cliffs","Turnip Tranquil",
	"Coconut Cove","Bread Board","Pasta Peak","Popcorn Pinnacle",
	"Milk Marsh","Butter Swamp","Ice Cream Isle","Burger Bluff",
	"Burrito Barrens","Pizza Palms",
}

-- Gap from slot s to s+1, or nil at the summit.
function IslandOrder.gap(slot: number): number?
	local a, b = IslandOrder.SLOT_POS[slot], IslandOrder.SLOT_POS[slot + 1]
	if not (a and b) then return nil end
	return b.y - a.y
end

return IslandOrder
