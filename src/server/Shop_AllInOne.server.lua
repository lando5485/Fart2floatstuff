--======================================================================
-- Shop_AllInOne.server.lua  (Server Script)
--======================================================================
-- The SERVER half of the shop, copied VERBATIM from PlayerStats.server.lua:
-- the food-buy + stomach-upgrade handlers, the foods + stomachTiers data, and
-- the exact validation rules. This is what the shop CLIENT (Shop_AllInOne.client
-- / ShopClient) talks to via the remotes.
--
-- It's self-contained: it creates the remotes, sets up the leaderstats stats the
-- handlers read (Coins / CurrentPower / StomachMax / TotalFartPower /
-- TotalCoinsEarned), and copies the BuyFood + BuyStomach logic 1:1. Drop into
-- ServerScriptService. (Robux products -- 2x pass, Bird Nuke, etc. -- go through
-- MarketplaceService.ProcessReceipt in the real game; that lives elsewhere and is
-- noted at the bottom, not duplicated here.)
--
-- KEY RULES (verbatim):
--   * COINS are checked FIRST (the common blocker) -> "not_enough_coins".
--   * Then stomach capacity: TRULY full -> "stomach_full", else has room but the
--     food won't fit -> "not_enough_room". Stomach-full uses `>` (a buy landing
--     EXACTLY on the max is allowed), and coins are NOT deducted when full.
--   * Stomach upgrade validates the (maxPower, cost) pair against a real,
--     non-Robux tier and carries the current power over (only the max grows).
--======================================================================

local Players            = game:GetService("Players")
local RS                 = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")

-- ===== remotes (created if missing) =====
local function ev(name) local e = RS:FindFirstChild(name); if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = RS end; return e end
local BuyFoodEvent      = ev("BuyFoodEvent")       -- c->s: (foodName)
local BuyStomachEvent   = ev("BuyStomachEvent")    -- c->s: (newMax, cost)
local StomachFullEvent  = ev("StomachFullEvent")   -- s->c: (reason) "not_enough_coins"/"stomach_full"/"not_enough_room"
local StomachUpdateEvent= ev("StomachUpdateEvent") -- s->c: (newMax, tierName)
local RegenEvent        = ev("RegenEvent")         -- s->c: (powerAdded, currentPower, stomachMax)
local CoinEvent         = ev("CoinEvent")          -- c->s: (amount) -- coins earned during flight

-- ============================================================================
-- DATA (VERBATIM from PlayerStats.server.lua) -- the client mirrors this exactly.
-- ============================================================================
local foods = {
	{name="Beans",    price=1280, power=32,  island=1},
	{name="Broccoli", price=1480, power=40,  island=2},
	{name="Cabbage",  price=1480, power=40,  island=3},
	{name="Turnips",  price=1520, power=45,  island=4},
	{name="Coconuts", price=1520, power=45,  island=5},
	{name="Bread",    price=1720, power=55,  island=6},
	{name="Pasta",    price=1720, power=55,  island=7},
	{name="Popcorn",  price=1840, power=65,  island=8},
	{name="Milk",     price=1840, power=65,  island=9},
	{name="Butter",   price=2200, power=85,  island=10},
	{name="IceCream", price=2200, power=85,  island=11},
	{name="Burger",   price=3080, power=130, island=12},
	{name="Burrito",  price=3080, power=130, island=13},
	{name="Pizza",    price=3080, power=130, island=14},
}
-- getMaxHeight(maxPower) = 50 + maxPower*14. Iron is the top of the free path; Infinite is a Robux-only premium gut.
-- `island` = the island that must have been REACHED before this gut can be bought. Keep these in
-- step with the same table in PlayerStats.server.lua, which is the live one -- a gut unlocks on the
-- island where the previous gut runs out. Infinite Gut stays at 1: it is the Robux tier.
local stomachTiers = {
	{name="Tiny Gut",     maxPower=120,  cost=0,      robux=false, island=1},
	{name="Small Gut",    maxPower=270,  cost=1000,   robux=false, island=2},
	{name="Medium Gut",   maxPower=470,  cost=2000,   robux=false, island=4},
	{name="Large Gut",    maxPower=620,  cost=4000,   robux=false, island=6},
	{name="XL Gut",       maxPower=1080, cost=5000,   robux=false, island=8},
	{name="XXL Gut",      maxPower=1710, cost=6000,   robux=false, island=10},
	{name="Iron Gut",     maxPower=2600, cost=11500,  robux=false, island=12},
	{name="Infinite Gut", maxPower=9999, cost=499,    robux=true,  island=1},
}
-- expose for the client (the real game sets these in CoreClient; harmless if already set)
_G.foods = _G.foods or foods
_G.stomachTiers = _G.stomachTiers or stomachTiers

-- ===== config flags the handlers read (VERBATIM values) =====
local POWER_PASS_MULT = 1.4   -- the 2x-power pass multiplier (food power + tank both scale by this when owned)
local DISABLE_2X = true       -- [TESTING] no 2x boost in Studio
local DISABLE_PERKS_FOR_BALANCE = false -- [BALANCE] force normal 1x power everywhere
local FORCE_NO_2X = true      -- [NOSAVE TEST] 2x forced un-owned for everyone. REMOVE BEFORE LAUNCH.
local TEST_FULL_DATA = false  -- [TEST] free switch to any tier (ignore cost+coins) to sample every tier's reach

-- balance-logging tables the handlers touch (kept so the copy is 1:1)
local coinsSpentOnFood, coinsSpentOnGuts = {}, {}
local gutPurchases, highestIslandReached, sessionStartTime, flightsOfSaving, sessionFlights = {}, {}, {}, {}, {}
local playerCoinAccum = {}

-- ============================================================================
-- LEADERSTATS setup (the handlers read these stats; the real game builds them
-- in PlayerStats). Created here so the shop runs standalone.
-- ============================================================================
local function setupStats(player)
	if player:FindFirstChild("leaderstats") then return end
	local ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player
	local function num(name, v) local n = Instance.new("IntValue"); n.Name = name; n.Value = v; n.Parent = ls; return n end
	num("Coins", 100)            -- starting coins (so you can buy)
	num("CurrentPower", 0)       -- current fart fuel in the tank
	num("StomachMax", 100)       -- tank size = Tiny Gut
	num("TotalFartPower", 0)     -- cosmetic lifetime counter
	num("TotalCoinsEarned", 0)
	num("Island", 1)
end
Players.PlayerAdded:Connect(setupStats)
for _, p in ipairs(Players:GetPlayers()) do setupStats(p) end

-- ============================================================================
-- BUY FOOD (VERBATIM)
-- ============================================================================
BuyFoodEvent.OnServerEvent:Connect(function(player, foodName)
	print("SERVER RECEIVED BUY:", player.Name, foodName)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then return end
	local coins        = stats:FindFirstChild("Coins")
	local totalPower   = stats:FindFirstChild("TotalFartPower")
	local totalEarned  = stats:FindFirstChild("TotalCoinsEarned")
	local currentPower = stats:FindFirstChild("CurrentPower")
	local stomachMax   = stats:FindFirstChild("StomachMax")
	if not coins or not totalPower then return end
	local food = nil
	for _, f in ipairs(foods) do
		if f.name == foodName then food = f; break end
	end
	if not food then
		print("FOOD NOT FOUND:", foodName)
		return
	end
	-- FAILURE CHECK 1 (COINS FIRST -- the common blocker): not enough coins -> "not_enough_coins".
	if coins.Value < food.price then
		print("NOT ENOUGH COINS:", player.Name, coins.Value, "<", food.price)
		pcall(function() StomachFullEvent:FireClient(player, "not_enough_coins") end) -- specific reason for the client
		return
	end
	if not currentPower or not stomachMax then return end
	-- 2x Fart Power pass (forever) OR an active 1-hour product both grant the real power boost.
	local has2x = player:GetAttribute("HasTwoXForever") or
		(player:GetAttribute("TwoXHourExpiry") and player:GetAttribute("TwoXHourExpiry") > os.time())
	if DISABLE_2X and RunService:IsStudio() then has2x = false end -- [TESTING] no 2x boost in Studio
	if DISABLE_PERKS_FOR_BALANCE then has2x = false end -- [BALANCE] force normal 1x power
	if FORCE_NO_2X then has2x = false end -- [NOSAVE TEST] 2x forced un-owned. REMOVE BEFORE LAUNCH.
	-- With the pass, food adds POWER_PASS_MULT x its power to ACTUAL flight fuel, and the
	-- effective tank grows to stomachMax * POWER_PASS_MULT (so the player flies higher).
	local powerGain   = has2x and math.floor(food.power * POWER_PASS_MULT) or food.power
	local effectiveMax = has2x and math.floor(stomachMax.Value * POWER_PASS_MULT) or stomachMax.Value
	local newPower = currentPower.Value + powerGain
	-- FAILURE CHECK 2 (only reached when coins are sufficient): does it fit the REMAINING stomach space?
	-- Distinguish TRULY FULL (no room at all -> "stomach_full") from HAS-ROOM-but-too-big ("not_enough_room").
	if newPower > effectiveMax then
		local remaining = effectiveMax - currentPower.Value
		if remaining <= 0 then
			print("STOMACH FULL:", player.Name, currentPower.Value, "/", effectiveMax, "(no room at all)")
			pcall(function() StomachFullEvent:FireClient(player, "stomach_full") end)    -- truly full
		else
			print("NOT ENOUGH ROOM:", player.Name, "+"..powerGain, ">", remaining, "remaining")
			pcall(function() StomachFullEvent:FireClient(player, "not_enough_room") end) -- has room, this food won't fit
		end
		return
	end
	coins.Value = coins.Value - food.price
	coinsSpentOnFood[player] = (coinsSpentOnFood[player] or 0) + food.price -- [BALANCE LOGGING] track food spend
	currentPower.Value = newPower
	-- Cosmetic TotalFartPower counter: unchanged -- still doubles with the pass as before.
	local bonusPower = has2x and food.power or 0
	totalPower.Value = totalPower.Value + food.power + bonusPower
	if totalEarned then totalEarned.Value = totalEarned.Value + food.price end
	pcall(function() RegenEvent:FireClient(player, food.power, currentPower.Value, stomachMax.Value) end)
	print("BOUGHT:", player.Name, foodName, "+", food.power, "power, total:", currentPower.Value)
	-- PET XP (cosmetic-only): eating food = "collecting gas" -> XP for the equipped pet.
	if _G.petOnGas then _G.petOnGas(player, powerGain) end
end)

-- ============================================================================
-- BUY STOMACH (coin tiers) (VERBATIM)
-- ============================================================================
BuyStomachEvent.OnServerEvent:Connect(function(player, newMax, cost)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local stomachMaxStat = ls:FindFirstChild("StomachMax")
	if not coins or not stomachMaxStat then return end
	local newMaxN = tonumber(newMax) or 0
	local costN   = tonumber(cost)   or 0
	-- [TEST] TEST_FULL_DATA: free switch to ANY real tier (ignore cost + coins) so every tier's reach can be sampled.
	if TEST_FULL_DATA then
		if newMaxN <= 0 then return end
		local ok = false
		for _, tier in ipairs(stomachTiers) do if tier.maxPower == newMaxN then ok = true; break end end
		if not ok then return end
		stomachMaxStat.Value = newMaxN
		local cp = ls:FindFirstChild("CurrentPower"); local carried = 0
		if cp then cp.Value = math.min(cp.Value, newMaxN); carried = cp.Value end
		pcall(function() RegenEvent:FireClient(player, 0, carried, newMaxN) end)
		local nameStr = "Gut"
		for _, t in ipairs(stomachTiers) do if t.maxPower == newMaxN then nameStr = t.name; break end end
		pcall(function() StomachUpdateEvent:FireClient(player, newMaxN, nameStr) end)
		print("TEST_FULL_DATA: "..player.Name.." switched to "..nameStr.." (maxPower "..newMaxN..") for FREE")
		return
	end
	if costN <= 0 or newMaxN <= 0 then return end
	local valid = false
	local wantTier = nil
	for _, tier in ipairs(stomachTiers) do
		if tier.maxPower == newMaxN and tier.cost == costN and not tier.robux then
			valid = true; wantTier = tier; break
		end
	end
	if not valid or coins.Value < costN then return end
	-- ISLAND LOCK (mirrors PlayerStats). Read from the HighestIsland ATTRIBUTE rather than a local
	-- table, because the landing detection that owns that number lives in PlayerStats and this file
	-- cannot see its locals. PlayerStats sets the attribute on load and on every new island reached.
	if wantTier.island and (player:GetAttribute("HighestIsland") or 1) < wantTier.island then
		print(("STOMACH LOCKED: %s tried to buy %s (needs island %d)")
			:format(player.Name, wantTier.name, wantTier.island))
		return
	end
	coins.Value = coins.Value - costN
	coinsSpentOnGuts[player] = (coinsSpentOnGuts[player] or 0) + costN -- [BALANCE LOGGING] track gut spend
	stomachMaxStat.Value = newMaxN
	-- CARRY OVER the power already in the tank (don't reset). Only the tank's MAX grows; the current fill stays.
	local cp = ls:FindFirstChild("CurrentPower")
	local carried = 0
	if cp then cp.Value = math.min(cp.Value, newMaxN); carried = cp.Value end
	pcall(function() RegenEvent:FireClient(player, 0, carried, newMaxN) end)
	local tierNameStr = "Gut"
	for _, t in ipairs(stomachTiers) do
		if t.maxPower == newMaxN then tierNameStr = t.name; break end
	end
	pcall(function() StomachUpdateEvent:FireClient(player, newMaxN, tierNameStr) end)
	print("BOUGHT GUT:", player.Name, tierNameStr, "maxPower "..newMaxN.." for "..costN.." coins")
end)

-- ============================================================================
-- ROBUX products (2x pass, 2x-1hr, Mid-Air Recharge, Skip Island, Bird Nuke):
-- in the real game these go through MarketplaceService.ProcessReceipt + the
-- gamepass-owned check (UserOwnsGamePassAsync) in PlayerStats. They're NOT
-- duplicated here because only ONE script may own ProcessReceipt. The shop
-- CLIENT already prompts them (MPS:PromptGamePassPurchase / PromptProductPurchase
-- with GAMEPASS_IDS / PRODUCT_IDS); wire those product IDs into your existing
-- ProcessReceipt to grant the effects.
-- ============================================================================
print("[Shop] server buy handlers loaded (food + stomach). Robux products go through your ProcessReceipt.")
