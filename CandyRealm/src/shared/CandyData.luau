--!strict
--======================================================================
-- CandyData.luau  (ModuleScript -> ReplicatedStorage.Shared)  -- CandyRealm
--======================================================================
-- Single source of truth for the FOOD STAND's food list. The BuyFood server validates
-- purchases against this and EconomyBootstrap publishes it as _G.foods for the shop UI,
-- so client + server can never disagree about price/power/island.
--
-- ORDERED BY CLIMB SLOT (1..11), which is the order the player meets them -- NOT by island
-- model number. The tower scrambles the two (IslandOrder.SLOT_TO_ISLAND is
-- {1,9,3,13,5,8,2,11,4,14,15}), so keying this by model number would scatter power along the
-- actual route, and several foods would unlock on slots where the player's tank is too small
-- to hold even one serving -- an outright rejected buy. Model numbers are also NOT contiguous
-- (6, 7, 10, 12 were never built), so a model-keyed list would have holes in it.
--
-- THE ROW ORDER IS THE CONTRACT; THE `island` FIELD JUST NAMES THE HOST. Row k is the food
-- for SLOT k and its price/power are solved for slot k; `island` only says which model the
-- stand physically sits on. Whenever IslandOrder moves an island, the affected rows' island
-- fields move with it.
--
-- PRICES ARE DERIVED, NOT PICKED. Each row is solved for a flat
--       R = (coins a full flight earns) / (coins a full refill costs) = 1.91
--       price = gap * MARGIN * COIN_PER_STUD / (R * (tierMaxPower / power))
-- against the gap and the tank size AT THAT SLOT (tierMaxPower = the ORIGINAL solved sizes
-- 100/140/190/260/355/485/665/910/1250/1715, not the +10 the shop sells). The summit row has
-- no gap above it, so it is priced against the LAST crossing and the top tier.
--
-- Rules that matter:
--   * R must stay ABOVE 1 at every row or a flight costs more than it earns and the player
--     spirals down. That, not the price, is the number to protect.
--   * R > 1 means prices CANNOT set the try count -- a solvent economy gives one-pass islands
--     by construction. The only thing that makes an island take several tries is a WALL: a
--     gut you can't yet afford (StomachTiers' 10 tiers).
--   * COIN_PER_STUD (0.14, in PropelSystem_AllInOne.client) is the other half of R. Change
--     one, re-solve both.
--======================================================================

local CandyData = {}

--                                                 slot  host island   gut tier at that slot
CandyData.FOODS = {
	{ name = "Candy Canes",    price = 21,  power = 8,   island = 1 },  --  1  island1   Gumdrop
	{ name = "Gumdrops",       price = 53,  power = 25,  island = 9 },  --  2  island9   Taffy
	{ name = "Cookies",        price = 79,  power = 45,  island = 3 },  --  3  island3   Cookie
	{ name = "Jelly Beans",    price = 101, power = 70,  island = 13 }, --  4  island13  Jelly
	{ name = "Taffy",          price = 118, power = 100, island = 5 },  --  5  island5   Gummy
	{ name = "Gummy Bears",    price = 136, power = 140, island = 8 },  --  6  island8   Choco
	{ name = "Chocolate Bars", price = 147, power = 185, island = 2 },  --  7  island2   Caramel
	{ name = "Rock Candy",     price = 156, power = 240, island = 11 }, --  8  island11  Marshmallow
	{ name = "Marshmallows",   price = 159, power = 300, island = 4 },  --  9  island4   Fudge
	{ name = "Caramel Apples", price = 160, power = 370, island = 14 }, -- 10  island14  Licorice
	{ name = "Sundaes",        price = 194, power = 450, island = 15 }, -- 11  island15  Licorice (summit)
}

-- name -> food, for O(1) server validation
CandyData.FOOD_BY_NAME = {}
for _, f in ipairs(CandyData.FOODS) do
	CandyData.FOOD_BY_NAME[f.name] = f
end

return CandyData
