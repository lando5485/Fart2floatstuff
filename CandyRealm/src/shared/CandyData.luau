--!strict
--======================================================================
-- CandyData.luau  (ModuleScript -> ReplicatedStorage.Shared)  -- CandyRealm
-- FOOD-REALM PORT: 13 foods, one per slot, the first realm's price/power rows copied exactly.
--======================================================================
-- Single source of truth for the FOOD STAND's list. BuyFood.server validates purchases
-- against this and EconomyBootstrap publishes it as _G.foods for the shop UI, so client
-- and server can never disagree about price/power/island.
--
-- ORDERED BY CLIMB SLOT (1..13) -- the order the player meets them, NOT by island model
-- number. The tower scrambles the two, so keying this by model number would scatter power
-- along the actual route; model numbers are also not contiguous, so it would have holes.
--
-- ===== THE NUMBERS ARE THE FOOD REALM'S `foods` TABLE, ROWS 1-13 =====
-- Beans -> Burrito, renamed for candy. Nothing here is a candy invention. The rules the
-- ladder harness (tools/ladder.py) asserts about them:
--   * power/price never DECREASES up the tower (0.0250 -> 0.0422, a 1.69x spread; >= 1.5
--     required) -- so a later food is always at least as good a buy, never a trap;
--   * power never decreases;
--   * every crossing can afford its own food on flight 1;
--   * no meal past the tutorial exceeds 20% of what its crossing pays.
--
-- A FOOD UNLOCKS WHEN ITS ISLAND HAS BEEN REACHED (a ceiling lock on HighestSlot, enforced
-- by BuyFood). Below that ceiling anything is buyable anywhere -- with monotonic value that
-- is never a trap. Stretch crossings need ~97% of the tank, which whole servings of one food
-- cannot always make (6 Gumdrops = 240 of a 270 tank). Mixing in a cheaper food (5 Gumdrops
-- + 2 Candy Canes = 264) does it -- that is by design.
--
-- WHY THE PRICES LOOK BIG NEXT TO THE OLD 110-COIN CANDY CANE: coins are paid per STUD
-- TRAVELLED at 3.52/stud, x3 on a failed flight. The 630-stud tutorial crossing pays
-- 2,217 on a landing and ~2,700 on each near-miss, so a 1,280 meal is about half a flight.
-- New players start with 2,000 coins -- a 3-rung tutorial ladder off the bank.
--
-- ===== THE ROW ORDER IS THE CONTRACT; `island` JUST NAMES THE HOST =====
-- Row k is the food for SLOT k; `island` only says which model the stand physically sits
-- on. Whenever IslandOrder moves an island, the affected rows' island fields move with it.
--======================================================================

local CandyData = {}

--                                                              slot  host      food-realm row
CandyData.FOODS = {
	{ name = "Candy Canes",    price = 1280, power = 32,  island = 1 },  --  1  island1   Beans
	{ name = "Gumdrops",       price = 1480, power = 40,  island = 9 },  --  2  island9   Broccoli
	{ name = "Cookies",        price = 1480, power = 40,  island = 3 },  --  3  island3   Cabbage
	{ name = "Jelly Beans",    price = 1520, power = 45,  island = 13 }, --  4  island13  Turnips
	{ name = "Taffy",          price = 1520, power = 45,  island = 5 },  --  5  island5   Coconuts
	{ name = "Gummy Bears",    price = 1720, power = 55,  island = 8 },  --  6  island8   Bread
	{ name = "Chocolate Bars", price = 1720, power = 55,  island = 18 }, --  7  island18  Pasta
	{ name = "Sundaes",        price = 1840, power = 65,  island = 15 }, --  8  island15  Popcorn
	{ name = "Rock Candy",     price = 1840, power = 65,  island = 11 }, --  9  island11  Milk
	{ name = "Marshmallows",   price = 2200, power = 85,  island = 4 },  -- 10  island4   Butter
	{ name = "Caramel Apples", price = 2200, power = 85,  island = 14 }, -- 11  island14  IceCream
	{ name = "Candy Floss",    price = 3080, power = 130, island = 19 }, -- 12  island19  Burger
	{ name = "Sherbet Scoops", price = 3080, power = 130, island = 16 }, -- 13  island16  Burrito (summit)
}

-- name -> food, for O(1) server validation.
CandyData.FOOD_BY_NAME = {}
for _, f in ipairs(CandyData.FOODS) do
	CandyData.FOOD_BY_NAME[f.name] = f
end

--[[ slot -> food, since the row index IS the climb slot. ]]
function CandyData.foodForSlot(slot: number)
	return CandyData.FOODS[math.floor(tonumber(slot) or 0)]
end

-- BOOT AUDIT (server only): the monotonic-value rule, so a hand edit that makes a later food
-- a worse buy than an earlier one is caught at boot rather than by a player.
if game:GetService("RunService"):IsServer() then
	local prevEff, prevPower = 0, 0
	for slot, f in ipairs(CandyData.FOODS) do
		local eff = f.power / f.price
		if eff + 1e-9 < prevEff then
			warn(("[CandyData] slot %d %s is WORSE value (%.4f/coin) than the food below it (%.4f) -- a trap")
				:format(slot, f.name, eff, prevEff))
		end
		if f.power < prevPower then
			warn(("[CandyData] slot %d %s has less power (%d) than the food below it (%d)")
				:format(slot, f.name, f.power, prevPower))
		end
		prevEff, prevPower = eff, f.power
	end
	print(("[CandyData] %d foods, value %.4f -> %.4f power/coin (food-realm rows 1-13)")
		:format(#CandyData.FOODS, CandyData.FOODS[1].power / CandyData.FOODS[1].price, prevEff))
end

return CandyData
