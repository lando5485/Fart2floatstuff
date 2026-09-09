--!strict
--======================================================================
-- IslandConfig.luau  (ReplicatedStorage.Shared.IslandConfig)  -- CandyRealm
-- SPACE-REALM PORT: the candy answer to PlanetConfig.luau.
--======================================================================
-- The master data table every island plugs into. DATA ONLY -- the actual quest logic
-- (how you earn the item) is the per-island client/server code that already exists.
--
-- Twelve islands, slot 1 -> slot 12, in climb order. For each we define:
--   name       : display name / state key
--   slot       : 1..12, the climb position (this IS the progression index)
--   island     : the Workspace model number that hosts it
--   standName  : the food-stand instance ("CandyStand_1" .. "CandyStand_12")
--   food       : { name, cost (coins), power (fuel refilled on purchase) }
--   questItem  : the SPECIFIC item this island's quest awards
--   questText  : human-readable description
--   questGoal  : how many questItem the quest needs (Task GUI target)
--   gutUnlock  : { item, count, unlocksTier } -- collecting `count` of `item` unlocks
--                gut tier `unlocksTier` AND pays out exactly that tier's cost.
--
-- Stand order matches slot order by design: CandyStand_1 == slot 1, ... CandyStand_12 == slot 12.
--
-- ===== THE LOOP THIS TABLE ENCODES =====
--   1. Land on slot k with gut tier k.
--   2. Finish slot k's quest -> +cost(tier k+1) coins, and the buy is unlocked.
--   3. Buy gut k+1 from the GUT panel (quest-gated -- flight coins alone cannot skip it).
--   4. Buy food at stand k, fly, earn power * payoutPerPower on landing.
--   5. The hard ceiling lifts to slot k+1. Go.
--
-- The quest pays for the gut EXACTLY; flight coins pay for the food. Those are two separate
-- purses on purpose, so grinding flights can never buy your way past a minigame.
--
-- ===== TWO ISLANDS STILL NEED A QUEST =====
-- Slot 7 (Chocolate Chasm / island2) never had one in the old tower, and slot 8 (Sherbet
-- Shelf / island12) is the brand-new island. Both are marked TODO below. Until they have a
-- real quest, their gutUnlock will never fire, and the ladder DEAD-ENDS at slot 7 -- the
-- ceiling cannot lift without the tier those quests fund. Ship a placeholder collect-N quest
-- if nothing else.
--======================================================================

local IslandConfig = {}

export type Food = {
	name: string,
	cost: number,
	power: number,
}

export type GutUnlock = {
	item: string,
	count: number,
	unlocksTier: number,
}

export type Island = {
	name: string,
	slot: number,
	island: number,
	standName: string,
	food: Food,
	questItem: string,
	questText: string,
	questGoal: number,
	gutUnlock: GutUnlock?,
}

-- Ordered slot 1 -> slot 12. Array index == climb slot.
IslandConfig.ISLANDS = {
	{
		name = "Candy Cane Court",
		slot = 1,
		island = 1,
		standName = "CandyStand_1",
		food = { name = "Candy Canes", cost = 110, power = 85 },
		questItem = "Gumball",
		questText = "Find the 3 lost gumballs in the community garden.",
		questGoal = 3,
		gutUnlock = { item = "Gumball", count = 3, unlocksTier = 2 },
	},
	{
		name = "Gumdrop Grove",
		slot = 2,
		island = 9,
		standName = "CandyStand_2",
		food = { name = "Gumdrops", cost = 230, power = 135 },
		questItem = "Coolant Rod",
		questText = "Clear the sugar reactor: pull all 4 coolant rods.",
		questGoal = 4,
		gutUnlock = { item = "Coolant Rod", count = 4, unlocksTier = 3 },
	},
	{
		name = "Cookie Crumble",
		slot = 3,
		island = 3,
		standName = "CandyStand_3",
		food = { name = "Cookies", cost = 430, power = 200 },
		questItem = "Cookie Piece",
		questText = "Repair the 6 cracked cookies before the chocolate monster returns.",
		questGoal = 6,
		gutUnlock = { item = "Cookie Piece", count = 6, unlocksTier = 4 },
	},
	{
		name = "Gumtree Park",
		slot = 4,
		island = 13,
		standName = "CandyStand_4",
		food = { name = "Jelly Beans", cost = 760, power = 285 },
		questItem = "Sap Vial",
		questText = "Tap 5 vials of sap from the ancient gumtree.",
		questGoal = 5,
		gutUnlock = { item = "Sap Vial", count = 5, unlocksTier = 5 },
	},
	{
		name = "Taffy Town",
		slot = 5,
		island = 5,
		standName = "CandyStand_5",
		food = { name = "Taffy", cost = 1300, power = 415 },
		questItem = "Taffy Reed",
		questText = "Gather 5 taffy reeds before the storm buries them.",
		questGoal = 5,
		gutUnlock = { item = "Taffy Reed", count = 5, unlocksTier = 6 },
	},
	{
		name = "Crystal Candy Caves",
		slot = 6,
		island = 8,
		standName = "CandyStand_6",
		food = { name = "Gummy Bears", cost = 2150, power = 570 },
		questItem = "Sugar Crystal",
		questText = "Mine 5 sugar crystals with your pickaxe.",
		questGoal = 5,
		gutUnlock = { item = "Sugar Crystal", count = 5, unlocksTier = 7 },
	},
	{
		name = "Chocolate Chasm",
		slot = 7,
		island = 2,
		standName = "CandyStand_7",
		-- TODO: THIS ISLAND HAS NO QUEST BUILT. The values below are a placeholder shape so the
		-- table is complete; wire a real minigame or the ladder dead-ends here (tier 8 never
		-- gets funded, so the ceiling never lifts past 21,620).
		food = { name = "Chocolate Bars", cost = 3500, power = 785 },
		questItem = "Cocoa Bean",
		questText = "TODO -- no quest built. Placeholder: collect 5 cocoa beans.",
		questGoal = 5,
		gutUnlock = { item = "Cocoa Bean", count = 5, unlocksTier = 8 },
	},
	{
		name = "Sherbet Shelf",
		slot = 8,
		island = 12,
		standName = "CandyStand_8",
		-- TODO: NEW ISLAND -- the island12 model does not exist in Workspace yet, and it has no
		-- quest. Both are required before slot 8 is playable.
		food = { name = "Sherbet Scoops", cost = 5770, power = 1020 },
		questItem = "Sherbet Shard",
		questText = "TODO -- island not built. Placeholder: chip 5 sherbet shards.",
		questGoal = 5,
		gutUnlock = { item = "Sherbet Shard", count = 5, unlocksTier = 9 },
	},
	{
		name = "Licorice Tunnels",
		slot = 9,
		island = 11,
		standName = "CandyStand_9",
		food = { name = "Rock Candy", cost = 9365, power = 1300 },
		questItem = "Blast Charge",
		questText = "Set 4 blast charges and open the collapsed tunnel.",
		questGoal = 4,
		gutUnlock = { item = "Blast Charge", count = 4, unlocksTier = 10 },
	},
	{
		name = "Frostbell Peak",
		slot = 10,
		island = 4,
		standName = "CandyStand_10",
		food = { name = "Marshmallows", cost = 14860, power = 1625 },
		questItem = "Ember",
		questText = "Relight the 4 frozen campfires and ring the summit bell.",
		questGoal = 4,
		gutUnlock = { item = "Ember", count = 4, unlocksTier = 11 },
	},
	{
		name = "Marshmallow Camp",
		slot = 11,
		island = 14,
		standName = "CandyStand_11",
		food = { name = "Caramel Apples", cost = 23210, power = 2000 },
		questItem = "Perfect Smore",
		questText = "Toast 5 perfect smores over the camp fire.",
		questGoal = 5,
		-- Slot 11 funds the CAPSTONE tier 12 -- the tank that clears the final 16,400 to the summit.
		gutUnlock = { item = "Perfect Smore", count = 5, unlocksTier = 12 },
	},
	{
		name = "Bakery Summit",
		slot = 12,
		island = 15,
		standName = "CandyStand_12",
		-- The summit: no flight onward is needed. Food mirrors slot 11 so its value stays on the
		-- curve rather than being trivially cheap (exactly what Neptune does in the Space Realm).
		food = { name = "Sundaes", cost = 23210, power = 2000 },
		questItem = "Blue Ribbon",
		questText = "Win the Great Bake-Off: 5 rounds, 5 ribbons.",
		questGoal = 5,
		-- Final island -> names the capstone tier 12 as well. There is no tier 13, and the
		-- task-completion grant only pays when the player does NOT already own the tier, so
		-- finishing the Bake-Off cannot hand out a second 8,450 for a gut already bought.
		gutUnlock = { item = "Blue Ribbon", count = 5, unlocksTier = 12 },
	},
} :: { Island }

-- Lookup helpers -------------------------------------------------------------

--[[ Island by display name, or nil. ]]
function IslandConfig.getByName(name: string): Island?
	for _, island in IslandConfig.ISLANDS do
		if island.name == name then
			return island
		end
	end
	return nil
end

--[[ Island by climb slot (1..12), or nil. ]]
function IslandConfig.getBySlot(slot: number): Island?
	return IslandConfig.ISLANDS[slot]
end

--[[ Island by Workspace model number, or nil. ]]
function IslandConfig.getByModel(islandNum: number): Island?
	for _, island in IslandConfig.ISLANDS do
		if island.island == islandNum then
			return island
		end
	end
	return nil
end

--[[ Island that owns a given food-stand instance name, or nil. ]]
function IslandConfig.getByStandName(standName: string): Island?
	for _, island in IslandConfig.ISLANDS do
		if island.standName == standName then
			return island
		end
	end
	return nil
end

-- One-time confirmation of the per-island tier unlock mapping (server only -- no client spam).
if game:GetService("RunService"):IsServer() then
	for _, island in ipairs(IslandConfig.ISLANDS) do
		local n = island.gutUnlock and island.gutUnlock.unlocksTier or nil
		print(("[IslandConfig] slot %d %s unlocksTier=%s"):format(island.slot, island.name, n and tostring(n) or "none"))
	end
end

return IslandConfig
