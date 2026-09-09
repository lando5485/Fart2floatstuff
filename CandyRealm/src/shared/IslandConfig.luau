--!nonstrict
--======================================================================
-- IslandConfig.luau  (ModuleScript -> ReplicatedStorage.Shared)  -- CandyRealm
-- The per-island data table: which quest lives on which rung, and which food.
--======================================================================
-- DATA ONLY -- the actual quest logic (how you earn the item) is the per-island
-- *_AllInOne.client.lua code that already exists.
--
-- Thirteen islands, slot 1 -> slot 13, in climb order. For each we define:
--   name       : display name (matches IslandOrder.NAMES)
--   slot       : 1..13, the climb position (this IS the progression index)
--   island     : the Workspace model number that hosts it
--   questId    : the CrateTokens.ISLAND_TASK id -- the SAME id the quest client claims
--                through ClaimIslandTaskTokens. Finishing it pays crate tokens (once ever,
--                off IslandTaskTokens' ledger) and opens the island's FOOD STAND
--                (Shop_AllInOne's stand gate reads UnlockedSlot, which GutProgression
--                derives from the ledger).
--   questName  : what the quest is called in the journal / on the reward card
--   food       : { name, cost, power } -- mirrors CandyData.FOODS[slot]
--
-- ===== FOOD-REALM PORT: QUESTS NO LONGER FUND OR GATE GUTS =====
-- Under the space port every entry carried `gutUnlock = { unlocksTier = k+1 }`: finishing
-- the quest paid exactly that gut's cost and StomachUpgrade refused the buy until the quest
-- was done. That field is GONE. Guts are bought out of flight coins and gated only by the
-- slot you have reached (StomachTiers.unlockSlot). The quest's own coin reward (paid by the
-- quest client through CoinEvent) and its crate tokens are what it is worth now.
--
-- ===== THE LOOP THIS TABLE ENCODES =====
--   1. Land on slot k. Its stand is locked until you finish slot k's quest.
--   2. Finish the quest -> its coin reward + crate tokens; the stand opens.
--   3. Buy food, fly the crossing. Fall 2% short on the wall crossings -- that IS the
--      "buy a gut" message -- and buy the next gut from the GUT panel with flight coins.
--
-- ===== EVERY RUNG HAS A REAL, SHIPPED QUEST =====
-- Every quest-bearing island in the realm is ON the tower: 1, 3, 4, 5, 8, 9, 11, 13, 14,
-- 15, 16, 18, 19 -- thirteen models, thirteen quests, thirteen rungs. island2 was never built.
--======================================================================

local IslandConfig = {}

-- Ordered slot 1 -> slot 13. Array index == climb slot.
IslandConfig.ISLANDS = {
	{
		name = "Candy Cane Court", slot = 1, island = 1,
		-- questId stays "candy": IslandTaskWatcher, CrateTokens.ISLAND_TASK and the save ledger
		-- all key off it, so renaming the id would orphan every existing player's rung. Island 1
		-- is the Gumball Hunt again (CandyGumballQuest_AllInOne); the Bridge Toll that briefly
		-- replaced it is disabled at the top of CandyTrollBridge_AllInOne.
		questId = "candy", questName = "Gumball Hunt",
		food = { name = "Candy Canes", cost = 1280, power = 32 },
	},
	{
		name = "Cocoa Reactor", slot = 2, island = 9,
		questId = "cleanup", questName = "Reactor Cleanup",
		food = { name = "Gumdrops", cost = 1480, power = 40 },
	},
	{
		name = "Cookie Crumble", slot = 3, island = 3,
		questId = "cookie", questName = "Cookie Repair",
		food = { name = "Cookies", cost = 1480, power = 40 },
	},
	{
		name = "Gumtree Park", slot = 4, island = 13,
		questId = "park", questName = "Ancient Tree",
		food = { name = "Jelly Beans", cost = 1520, power = 45 },
	},
	{
		name = "Taffy Town", slot = 5, island = 5,
		questId = "storm", questName = "Taffy Storm",
		food = { name = "Taffy", cost = 1520, power = 45 },
	},
	{
		name = "Crystal Candy Caves", slot = 6, island = 8,
		questId = "crystal", questName = "Crystal Mine",
		food = { name = "Gummy Bears", cost = 1720, power = 55 },
	},
	{
		name = "Pancake Arena", slot = 7, island = 18,
		questId = "pancake", questName = "Wake the Pancake Monster",
		food = { name = "Chocolate Bars", cost = 1720, power = 55 },
	},
	{
		name = "Bakery Summit", slot = 8, island = 15,
		questId = "bakery", questName = "The Great Bake-Off",
		food = { name = "Sundaes", cost = 1840, power = 65 },
	},
	{
		name = "Licorice Tunnels", slot = 9, island = 11,
		questId = "tunnel", questName = "Tunnel Blast",
		food = { name = "Rock Candy", cost = 1840, power = 65 },
	},
	{
		-- TWO quests live here. `campfire` is the one the stand gate and the ledger key off;
		-- `summit` (Summit Bell) is extra crate tokens on the same island and gates nothing.
		name = "Frostbell Peak", slot = 10, island = 4,
		questId = "campfire", questName = "Campfire Freeze",
		food = { name = "Marshmallows", cost = 2200, power = 85 },
	},
	{
		name = "Marshmallow Camp", slot = 11, island = 14,
		questId = "smores", questName = "Camp S'mores",
		food = { name = "Caramel Apples", cost = 2200, power = 85 },
	},
	{
		name = "Sugarbeet Farm", slot = 12, island = 19,
		questId = "tractor", questName = "Broken Tractor",
		food = { name = "Candy Floss", cost = 3080, power = 130 },
	},
	{
		-- POP ROCK QUARRY IS THE ENDING ISLAND: the tower tops out at the mine explosion.
		name = "Pop Rock Quarry", slot = 13, island = 16,
		questId = "candymine", questName = "Candy Mine Explosion",
		food = { name = "Sherbet Scoops", cost = 3080, power = 130 },
	},
}

-- questId -> island, so a claim can go straight to the rung it belongs to.
IslandConfig.BY_QUEST = {}
for _, island in ipairs(IslandConfig.ISLANDS) do
	if island.questId then
		IslandConfig.BY_QUEST[island.questId] = island
	end
end

--[[ Island by climb slot (1..13), or nil. ]]
function IslandConfig.getBySlot(slot: number)
	return IslandConfig.ISLANDS[math.floor(tonumber(slot) or 0)]
end

--[[ Island by Workspace model number, or nil. ]]
function IslandConfig.getByModel(islandNum: number)
	for _, island in ipairs(IslandConfig.ISLANDS) do
		if island.island == islandNum then
			return island
		end
	end
	return nil
end

--[[ Island by display name, or nil. ]]
function IslandConfig.getByName(name: string)
	for _, island in ipairs(IslandConfig.ISLANDS) do
		if island.name == name then
			return island
		end
	end
	return nil
end

-- BOOT AUDIT (server only): the three tables that have to agree -- IslandConfig, IslandOrder
-- and CandyData -- are checked against each other here, because a mismatch puts a stand on
-- one island and its quest on another and nothing else would ever say so.
if game:GetService("RunService"):IsServer() then
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local okOrder, IslandOrder = pcall(function() return require(Shared:WaitForChild("IslandOrder")) end)
	local okData, CandyData = pcall(function() return require(Shared:WaitForChild("CandyData")) end)
	local okTok, CrateTokens = pcall(function() return require(Shared:WaitForChild("CrateTokens")) end)

	for _, island in ipairs(IslandConfig.ISLANDS) do
		if okOrder and IslandOrder.SLOT_TO_ISLAND[island.slot] ~= island.island then
			warn(("[IslandConfig] slot %d hosts island%d here but island%s in IslandOrder -- "
				.. "the stand and the quest are on different islands")
				:format(island.slot, island.island, tostring(IslandOrder.SLOT_TO_ISLAND[island.slot])))
		end
		local food = okData and CandyData.FOODS[island.slot]
		if food and (food.island ~= island.island or food.name ~= island.food.name
			or food.price ~= island.food.cost or food.power ~= island.food.power) then
			warn(("[IslandConfig] slot %d food drift: CandyData says %s/%d/%d on island%d, "
				.. "IslandConfig says %s/%d/%d on island%d")
				:format(island.slot, food.name, food.price, food.power, food.island,
					island.food.name, island.food.cost, island.food.power, island.island))
		end
		if okTok and island.questId and not CrateTokens.ISLAND_TASK[island.questId] then
			warn(("[IslandConfig] slot %d names questId '%s', which is not in "
				.. "CrateTokens.ISLAND_TASK -- its completion will never be ledgered, so its "
				.. "stand can never open for a returning player"):format(island.slot, island.questId))
		end
	end
	print(("[IslandConfig] %d islands wired -- every rung has a shipped quest")
		:format(#IslandConfig.ISLANDS))
end

return IslandConfig
