--!nonstrict
--======================================================================
-- BuyFood.server.luau  (Server Script)  -- CandyRealm
--======================================================================
-- Authoritative backend for the FOOD STAND. The client fires
--   _G.BuyFoodEvent:FireServer(foodName)   (Shop_AllInOne, BUY / BUY MAX)
-- and EconomyBootstrap binds _G.BuyFoodEvent to the RemoteEvent this creates.
--
-- Nothing in CandyRealm handled food buys (the food realm's PlayerStats server
-- doesn't run here), so this is the missing authority -- mirrors StomachUpgrade:
--   * validates the food against CandyData (shared, same list the client shows)
--   * checks Coins first, then gut room, then deducts coins + adds power
--   * leaderstats (Coins/CurrentPower/StomachMax) are created by StomachUpgrade;
--     this reuses them and never clobbers.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CandyData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CandyData"))

local BuyFoodEvent = ReplicatedStorage:FindFirstChild("BuyFoodEvent")
if not BuyFoodEvent then
	BuyFoodEvent = Instance.new("RemoteEvent"); BuyFoodEvent.Name = "BuyFoodEvent"; BuyFoodEvent.Parent = ReplicatedStorage
end

BuyFoodEvent.OnServerEvent:Connect(function(player, foodName)
	if type(foodName) ~= "string" then return end
	local food = CandyData.FOOD_BY_NAME[foodName]
	if not food then return end

	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local cp    = ls:FindFirstChild("CurrentPower")
	local sm    = ls:FindFirstChild("StomachMax")
	if not (coins and cp and sm) then return end

	-- island-unlock gate (only if an Island value exists; the client also gates this)
	local island = ls:FindFirstChild("Island")
	if island and food.island > island.Value then return end

	if coins.Value < food.price then return end            -- can't afford
	if cp.Value + food.power > sm.Value then return end     -- no room in the gut

	coins.Value = coins.Value - food.price
	cp.Value    = math.min(cp.Value + food.power, sm.Value)

	local tfp = ls:FindFirstChild("TotalFartPower"); if tfp then tfp.Value = tfp.Value + food.power end

	-- optional pet-XP hook (guarded -- absent in this realm, so it just no-ops)
	if type(_G.petOnGas) == "function" then pcall(_G.petOnGas, player, food.power) end
end)

print("[BuyFood] server ready -- BuyFoodEvent(foodName) handler (validates CandyData)")
