--!nonstrict
--======================================================================
-- BuyFood.server.luau  (Server Script)  -- CandyRealm
-- FOOD-REALM PORT: the first realm's food purchase rules.
--======================================================================
-- Authoritative backend for the FOOD STAND. The client fires
--   _G.BuyFoodEvent:FireServer(foodName)   (Shop_AllInOne, BUY / BUY MAX)
-- and EconomyBootstrap binds _G.BuyFoodEvent to the RemoteEvent this creates.
--
--   * ISLAND LOCK (the CEILING): a food unlocks once you have physically REACHED its
--     island -- the HighestSlot attribute, raised only by FlightEconomy's landing detection.
--     Below that ceiling anything is buyable anywhere: the price table is monotonic in
--     power-per-coin, so a cheaper lower food is never a trap, and stretch crossings are
--     DESIGNED to be filled by mixing a cheaper food in.
--   * COINS ARE CHECKED FIRST (the common blocker) -> "not_enough_coins".
--   * Then room: TRULY full -> "stomach_full", has room but this serving won't fit ->
--     "not_enough_room". A buy landing EXACTLY on the cap is allowed (`>` not `>=`).
--   * Coins are never deducted on a rejected buy.
-- Rejection reasons go to the client via StomachFullEvent.
--
-- The anti-strand (one free serving for a dry, broke player) lives in FlightEconomy, on the
-- tank-empty report, so it has already run by the time the player opens the shop.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local CandyData   = require(Shared:WaitForChild("CandyData"))
local IslandOrder = require(Shared:WaitForChild("IslandOrder"))

local function ev(name)
	local e = ReplicatedStorage:FindFirstChild(name)
	if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = ReplicatedStorage end
	return e
end
local BuyFoodEvent     = ev("BuyFoodEvent")
local StomachFullEvent = ev("StomachFullEvent")
local RegenEvent       = ev("RegenEvent")

BuyFoodEvent.OnServerEvent:Connect(function(player, foodName)
	if type(foodName) ~= "string" then return end
	local food = CandyData.FOOD_BY_NAME[foodName]
	if not food then return end

	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local cp    = ls:FindFirstChild("CurrentPower")
	local sm    = ls:FindFirstChild("StomachMax")
	if not (coins and cp and sm) then return end

	-- ISLAND LOCK: reached-slot gate (the client greying a cell is cosmetic; this is the rule).
	-- Checked BEFORE the coin check on purpose: a locked food must say "locked", not "not
	-- enough coins".
	local reached  = math.max(1, math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1))
	local foodSlot = IslandOrder.ISLAND_TO_SLOT[food.island] or food.island
	if foodSlot > reached then
		pcall(function() StomachFullEvent:FireClient(player, "food_locked", food.name, foodSlot) end)
		return
	end

	-- COINS FIRST
	if coins.Value < food.price then
		pcall(function() StomachFullEvent:FireClient(player, "not_enough_coins") end)
		return
	end

	-- ROOM: exact-cap landings allowed (`>` not `>=`)
	local newPower = cp.Value + food.power
	if newPower > sm.Value then
		local remaining = sm.Value - cp.Value
		pcall(function()
			StomachFullEvent:FireClient(player, remaining <= 0 and "stomach_full" or "not_enough_room")
		end)
		return
	end

	coins.Value = coins.Value - food.price
	cp.Value    = math.min(newPower, sm.Value)

	local tfp = ls:FindFirstChild("TotalFartPower"); if tfp then tfp.Value = tfp.Value + food.power end

	pcall(function() RegenEvent:FireClient(player, food.power, cp.Value, sm.Value) end)

	-- optional pet-XP hook (guarded -- no-ops if absent)
	if type(_G.petOnGas) == "function" then pcall(_G.petOnGas, player, food.power) end
end)

print("[BuyFood] server ready -- BuyFoodEvent(foodName): reached-slot ceiling, coins-first reasons, exact-cap fills")
