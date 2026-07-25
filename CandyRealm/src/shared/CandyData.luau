--!strict
--======================================================================
-- CandyData.luau  (ModuleScript -> ReplicatedStorage.Shared)
--======================================================================
-- Single source of truth for the FOOD STAND's food list. The BuyFood server
-- validates purchases against this, so client + server can never disagree about
-- price/power/island. Values match the game's food table (CLAUDE.md); the client
-- shop reads its display data from _G.foods (provided by the place) -- keep the
-- name/price/power/island here in sync with that list.
--======================================================================

local CandyData = {}

-- one food per island, ordered by island (index == island number)
CandyData.FOODS = {
	{ name = "Candy Canes", price = 10,  power = 8,   island = 1 },
	{ name = "Ice Cream", price = 250,   power = 25,  island = 2 },
	{ name = "Cookies",  price = 450,    power = 45,  island = 3 },
	{ name = "Turnips",  price = 2000,   power = 70,  island = 4 },
	{ name = "Taffy",    price = 3500,   power = 100, island = 5 },
	{ name = "Bread",    price = 7000,   power = 140, island = 6 },
	{ name = "Pasta",    price = 14000,  power = 185, island = 7 },
	{ name = "Popcorn",  price = 28000,  power = 240, island = 8 },
	{ name = "Milk",     price = 55000,  power = 300, island = 9 },
	{ name = "Butter",   price = 100000, power = 370, island = 10 },
	{ name = "IceCream", price = 180000, power = 450, island = 11 },
	{ name = "Burger",   price = 320000, power = 540, island = 12 },
	{ name = "Burrito",  price = 550000, power = 640, island = 13 },
	{ name = "Pizza",    price = 900000, power = 750, island = 14 },
}

-- name -> food, for O(1) server validation
CandyData.FOOD_BY_NAME = {}
for _, f in ipairs(CandyData.FOODS) do
	CandyData.FOOD_BY_NAME[f.name] = f
end

return CandyData
