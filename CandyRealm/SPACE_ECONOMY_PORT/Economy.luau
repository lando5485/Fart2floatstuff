--!strict
--[[
	Economy.luau  (ServerScriptService.Economy)  -- CandyRealm
	SPACE-REALM PORT: the dual-purse economy, verbatim.

	===== THE TWO PURSES =====
	This is the whole design, and it is the thing the old candy economy did not have:

	  QUEST MONEY buys GUTS.   Finishing an island's quest pays out EXACTLY the cost of the
	                           gut it unlocks. The buy is then quest-gated, so a player who
	                           farms flights all day still cannot buy the next gut.
	  FLIGHT MONEY buys FOOD.  coins = powerBurned * payoutPerPower. Food is the only thing
	                           it is for.

	Keeping them separate is what makes each minigame mandatory. In the old candy model there
	was ONE purse: guts were bought out of flight surplus, so "how many tries an island takes"
	was a function of how long you were willing to grind. Here the wall is structural -- the
	hard flight ceiling in StomachTiers does not move until the quest that funds the next gut
	is done, and no amount of coins moves it.

	Four public entry points:

	  GrantQuestReward(player, itemName, itemAmount, coinAmount)
	      Adds coins, adds items, then re-checks gut unlocks.

	  AddCoins(player, amount)
	      Coins only, no item, no gut re-check -- used by the flight payout.

	  BuyFood(player, foodName, foodCost, powerAmount)
	      Deducts coins and refills power (rejects an overfill WITHOUT charging).

	  BuyGut(player, targetTier)
	      Server-authoritative gut upgrade. Enforces next-tier-only, quest-completed, and
	      can-afford. Nothing is charged on a rejected buy.

	All of them mutate PlayerState, mark it dirty, and push to the HUD. They contain NO
	per-island values -- those are supplied by the caller from IslandConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StomachTiers = require(Shared:WaitForChild("StomachTiers"))
local IslandConfig = require(Shared:WaitForChild("IslandConfig"))
local PlayerState = require(ServerScriptService:WaitForChild("PlayerState"))
local GutProgression = require(ServerScriptService:WaitForChild("GutProgression"))

local Economy = {}

-- Which island's quest funds + gates each gut tier (lowest slot per unlocksTier -> the
-- standard path: slot 1 -> tier 2, ... slot 11 -> the capstone tier 12). Built once at load.
local unlockIslandForTier = {}
for _, island in ipairs(IslandConfig.ISLANDS) do
	local u = island.gutUnlock
	if u and u.unlocksTier and not unlockIslandForTier[u.unlocksTier] then
		unlockIslandForTier[u.unlocksTier] = island
	end
end

export type BuyResult = {
	ok: boolean,
	reason: string?, -- populated when ok == false ("insufficient_coins", etc.)
}

--[[
	GrantQuestReward(player, itemName, itemAmount, coinAmount) -> ()

	Award the fixed reward for completing an island quest. After updating the inventory we
	re-evaluate the gut unlock chain so reaching a threshold immediately grants the tier.
]]
function Economy.GrantQuestReward(player: Player, itemName: string, itemAmount: number, coinAmount: number)
	local state = PlayerState.get(player)
	if not state then
		return
	end

	local grantedCoins = math.max(0, coinAmount)
	state.coins += grantedCoins
	if grantedCoins > 0 then
		print(("[Economy] +%d coins granted to %s (total now: %d)"):format(grantedCoins, player.Name, state.coins))
	end

	if itemName and itemAmount and itemAmount > 0 then
		state.inventory[itemName] = (state.inventory[itemName] or 0) + itemAmount
	end

	PlayerState.markDirty(player)

	-- Re-check unlocks (this pushes to the client if the tier changes); always push once more
	-- so coin/inventory deltas show even when the tier is static.
	GutProgression.evaluate(player)
	PlayerState.pushToClient(player)
end

--[[
	AddCoins(player, amount) -> ()

	Grant coins only -- used by the flight payout. Fires StateChanged via pushToClient so the
	HUD coin counter updates live, exactly like quest rewards do.
]]
function Economy.AddCoins(player: Player, amount: number)
	local state = PlayerState.get(player)
	if not state then
		return
	end
	local granted = math.max(0, math.floor(amount))
	if granted <= 0 then
		return
	end
	state.coins += granted
	PlayerState.markDirty(player)
	PlayerState.pushToClient(player)
	print(("[Economy] +%d coins granted to %s (total now: %d)"):format(granted, player.Name, state.coins))
end

--[[
	BuyFood(player, foodName, foodCost, powerAmount) -> BuyResult

	Spend `foodCost` coins to gain `powerAmount` power, clamped to the player's current gut
	maxPower (Sugar Rush => effectively uncapped).

	REJECTS AN OVERFILL WITHOUT CHARGING. Food ADDS power on top of what is carried over; it
	never resets the fill. A buy that would push past the cap is refused and costs nothing --
	no wasted purchase, which is the single most common way a food economy feels unfair.
]]
function Economy.BuyFood(player: Player, foodName: string, foodCost: number, powerAmount: number): BuyResult
	local state = PlayerState.get(player)
	if not state then
		return { ok = false, reason = "no_profile" }
	end

	if state.coins < foodCost then
		return { ok = false, reason = "insufficient_coins" }
	end

	local cap = StomachTiers.getMaxPower(state)
	if state.gas + powerAmount > cap then
		return { ok = false, reason = "stomach_full" }
	end

	state.coins -= foodCost
	state.gas = state.gas + powerAmount -- guaranteed <= cap by the check above

	PlayerState.markDirty(player)
	PlayerState.pushToClient(player)
	-- DAILY TASK "food": only reached once the coins have been taken and the power is in the
	-- tank, so a rejected buy (broke / full) can never tick it.
	if _G.dailyTaskDone then
		pcall(_G.dailyTaskDone, player, "food")
	end
	return { ok = true }
end

--[[
	BuyGut(player, targetTier) -> BuyResult

	Spend coins to upgrade to the NEXT gut. Server-authoritative -- the client only sends a
	target tier index. Enforced:
	  (1) it is exactly the next sequential tier (current + 1) and exists (<= MAX_TIER);
	  (2) the island QUEST that funds/gates that tier is COMPLETED -- so a player must
	      actually play the minigame that pays for it, and flight coins cannot skip it;
	  (3) the player can afford the tier's coin `cost`.
	Nothing is charged on a rejected buy. Sugar Rush owners already sit at top capacity.
]]
function Economy.BuyGut(player: Player, targetTier: number): BuyResult
	local state = PlayerState.get(player)
	if not state then
		return { ok = false, reason = "no_profile" }
	end
	if state.sugarRush or state.unlimitedGut then
		return { ok = false, reason = "already_maxed" }
	end
	if type(targetTier) ~= "number" or targetTier ~= targetTier then -- NaN guard
		return { ok = false, reason = "bad_request" }
	end
	targetTier = math.floor(targetTier)

	if targetTier ~= state.stomachTier + 1 then
		return { ok = false, reason = "not_next_tier" }
	end
	if targetTier > StomachTiers.MAX_TIER then
		return { ok = false, reason = "max_tier" }
	end

	-- QUEST GATE: the funding island's quest must be done (this is what paid you the coins).
	local island = unlockIslandForTier[targetTier]
	if island then
		local getQuestState = PlayerState["get" .. island.name:gsub("%s+", "") .. "QuestState"]
		local questState = (type(getQuestState) == "function") and getQuestState(player) or nil
		if questState ~= "COMPLETED" then
			return { ok = false, reason = "quest_incomplete" }
		end
	end

	local tier = StomachTiers.getTier(targetTier)
	if state.coins < tier.cost then
		return { ok = false, reason = "insufficient_coins" }
	end

	state.coins -= tier.cost
	state.stomachTier = targetTier

	PlayerState.markDirty(player)
	PlayerState.pushToClient(player)
	print(("[Economy] %s bought %s for %d coins -> tier %d (max %d)")
		:format(player.Name, tier.name, tier.cost, targetTier, tier.maxPower))
	return { ok = true }
end

--[[
	PayForNextGut(player, island) -> ()

	Call this on the NOT_COMPLETED -> COMPLETED edge of an island's quest. It pays out exactly
	the cost of the gut that island unlocks, so the player can go BUY it from the GUT panel.

	ONLY IF THEY DO NOT ALREADY OWN IT. The summit names the same capstone tier as the island
	below it (there is no tier 13), so without this check finishing the Bake-Off would hand out
	another 8,450 coins for a gut already bought -- free money for an upgrade that does not
	exist. The payout is here to make the NEXT tank affordable, so it only pays when there is a
	next tank to buy.
]]
function Economy.PayForNextGut(player: Player, island)
	local state = PlayerState.get(player)
	if not (state and island and island.gutUnlock and island.gutUnlock.unlocksTier) then
		return
	end
	local tier = StomachTiers.getTier(island.gutUnlock.unlocksTier)
	local ownedTier = tonumber(state.stomachTier) or 1
	if tier and tier.cost > 0 and ownedTier < island.gutUnlock.unlocksTier then
		state.coins += tier.cost
		PlayerState.markDirty(player)
		PlayerState.pushToClient(player)
		print(("[QuestReward] %s completed %s -- paid %d coins for %s (buy it in the GUT panel)")
			:format(player.Name, island.name, tier.cost, tier.name))
	end
end

print("[Economy] two-purse model online: quest money buys guts (quest-gated), flight money buys food")

return Economy
