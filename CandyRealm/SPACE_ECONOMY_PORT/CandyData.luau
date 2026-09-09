--!strict
--======================================================================
-- CandyData.luau  (ReplicatedStorage.Shared.CandyData)  -- CandyRealm
-- SPACE-REALM PORT: 12 foods, one per island, priced by the space curve.
--======================================================================
-- Single source of truth for the FOOD STAND's list. BuyFood validates purchases against
-- this and the shop UI reads it, so client and server can never disagree about
-- price/power/island.
--
-- ORDERED BY CLIMB SLOT (1..12) -- the order the player meets them, NOT by island model
-- number. The tower scrambles the two, so keying this by model number would scatter power
-- along the actual route.
--
-- ===== HOW THE NUMBERS WERE DERIVED (all three columns) =====
--
-- POWER (gas) is a FIXED FRACTION OF THE TANK IT FILLS. You arrive on slot k with tier k,
-- finish the quest, buy tier k+1, then buy food HERE and fly. So slot k's food fills tier
-- k+1's tank. The Space Realm ramps that fraction 11.0% -> 17.9% across its seven crossings;
-- this continues the same +1.1-points-per-rung slope out to 22.3%:
--
--     slot  1: 11.0% of  770 =   85        slot  7: 17.9% of 4380 =  785
--     slot  2: 12.3% of 1100 =  135        slot  8: 19.0% of 5360 = 1020
--     slot  3: 13.1% of 1530 =  200        slot  9: 20.2% of 6450 = 1300
--     slot  4: 13.7% of 2080 =  285        slot 10: 21.2% of 7650 = 1625
--     slot  5: 15.1% of 2740 =  415        slot 11: 22.3% of 8960 = 2000
--     slot  6: 16.3% of 3500 =  570        slot 12: summit -- mirrors slot 11
--
-- In servings-to-fill that is 9.1 at the bottom easing to 4.5 at the top: refuelling stays a
-- multi-purchase ritual the whole way up, it just gets less repetitive.
--
-- PRICE IS SOLVED FROM R, NOT PICKED. R is the only number that matters:
--
--     R = (coins one serving earns when burned) / (what that serving costs)
--       = (power * payoutPerPower) / price
--
-- R must stay ABOVE 1 at every row or a flight costs more than it earns and the player
-- spirals down. The Space Realm's R runs 1.47 -> 1.35 -> 1.75, PLATEAUING at 1.749 for its
-- top two islands. Slots 1-7 below are its exact prices; slots 8-12 are solved to HOLD that
-- plateau, price = power * payoutPerPower / 1.749, exactly as Neptune mirrors Uranus.
--
--     price = power * payoutPerPower / 1.749
--
-- R > 1 means PRICES CANNOT SET THE TRY COUNT -- a solvent economy gives one-pass islands by
-- construction. The thing that makes an island take several tries is the WALL: the hard
-- flight ceiling in StomachTiers, which no amount of coins can buy past.
--
-- payoutPerPower lives in FlightPayout.luau. CHANGE ONE, RE-SOLVE BOTH.
--
-- ===== THE ROW ORDER IS THE CONTRACT; `island` JUST NAMES THE HOST =====
-- Row k is the food for SLOT k and its price/power are solved for slot k; `island` only says
-- which model the stand physically sits on. Whenever IslandOrder moves an island, the
-- affected rows' island fields move with it.
--======================================================================

local CandyData = {}

--                                                              slot  host      gut tier this fills
CandyData.FOODS = {
	{ name = "Candy Canes",    price = 110,   power = 85,   island = 1 },  --  1  island1   Taffy Tummy (770)
	{ name = "Gumdrops",       price = 230,   power = 135,  island = 9 },  --  2  island9   Cookie Gut (1100)
	{ name = "Cookies",        price = 430,   power = 200,  island = 3 },  --  3  island3   Jelly Belly (1530)
	{ name = "Jelly Beans",    price = 760,   power = 285,  island = 13 }, --  4  island13  Gummy Gut (2080)
	{ name = "Taffy",          price = 1300,  power = 415,  island = 5 },  --  5  island5   Choco Stomach (2740)
	{ name = "Gummy Bears",    price = 2150,  power = 570,  island = 8 },  --  6  island8   Caramel Core (3500)
	{ name = "Chocolate Bars", price = 3500,  power = 785,  island = 2 },  --  7  island2   Marshmallow Middle (4380)
	{ name = "Sherbet Scoops", price = 5770,  power = 1020, island = 12 }, --  8  island12  Fudge Furnace (5360)   NEW ISLAND
	{ name = "Rock Candy",     price = 9365,  power = 1300, island = 11 }, --  9  island11  Licorice Loop (6450)
	{ name = "Marshmallows",   price = 14860, power = 1625, island = 4 },  -- 10  island4   Peppermint Pit (7650)
	{ name = "Caramel Apples", price = 23210, power = 2000, island = 14 }, -- 11  island14  Nougat Nova (8960)
	-- The summit has no crossing above it, so like Neptune it MIRRORS the row below rather
	-- than being trivially cheap -- its value stays consistent with the curve.
	{ name = "Sundaes",        price = 23210, power = 2000, island = 15 }, -- 12  island15  (summit)
}

-- name -> food, for O(1) server validation.
CandyData.FOOD_BY_NAME = {}
for _, f in ipairs(CandyData.FOODS) do
	CandyData.FOOD_BY_NAME[f.name] = f
end

-- slot -> food, since the row index IS the climb slot.
function CandyData.foodForSlot(slot: number)
	return CandyData.FOODS[math.floor(tonumber(slot) or 0)]
end

return CandyData
