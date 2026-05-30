GAMESERVER_SOURCE = '''return
'''

PLAYERSTATS_SOURCE = '''local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local function getOrCreate(parent, className, name)
	local obj = parent:FindFirstChild(name)
	if not obj then
		obj = Instance.new(className)
		obj.Name = name
		obj.Parent = parent
	end
	return obj
end

local BuyFoodEvent  = getOrCreate(RS, "RemoteEvent", "BuyFoodEvent")
local RegenEvent    = getOrCreate(RS, "RemoteEvent", "RegenEvent")
local CoinEvent     = getOrCreate(RS, "RemoteEvent", "CoinEvent")
local SkipIslandEvent = getOrCreate(RS, "RemoteEvent", "SkipIslandEvent")

local foods = {
	{name="Beans",    price=10,     power=10,   island=1},
	{name="Broccoli", price=25,     power=15,   island=1},
	{name="Cabbage",  price=50,     power=23,   island=2},
	{name="Turnips",  price=100,    power=34,   island=2},
	{name="Coconuts", price=250,    power=51,   island=3},
	{name="Bread",    price=500,    power=76,   island=3},
	{name="Pasta",    price=1000,   power=114,  island=4},
	{name="Popcorn",  price=2500,   power=171,  island=4},
	{name="Milk",     price=5000,   power=256,  island=5},
	{name="Butter",   price=10000,  power=384,  island=5},
	{name="IceCream", price=25000,  power=577,  island=6},
	{name="Burger",   price=50000,  power=865,  island=6},
	{name="Burrito",  price=75000,  power=1297, island=6},
	{name="Pizza",    price=100000, power=1946, island=6},
}

local islandThresholds = {0, 200, 1000, 5000, 25000, 100000}

local GAMEPASS_2X      = 0
local PRODUCT_2X_1HOUR = 0
local PRODUCT_MIDAIR   = 0
local PRODUCT_SKIP     = 0

local playerGas = {}

local function getFoodByName(name)
	for _, f in ipairs(foods) do if f.name == name then return f end end
end

local function checkIslandUnlock(player)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local earned = ls:FindFirstChild("TotalCoinsEarned")
	local island = ls:FindFirstChild("Island")
	if not earned or not island then return end
	for i = #islandThresholds, 1, -1 do
		if earned.Value >= islandThresholds[i] then
			if island.Value < i then island.Value = i end
			break
		end
	end
end

local function owns2xPass(player)
	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GAMEPASS_2X)
	end)
	return ok and result
end

Players.PlayerAdded:Connect(function(player)
	local ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player

	local coins = Instance.new("IntValue"); coins.Name = "Coins"; coins.Value = 20; coins.Parent = ls
	local island = Instance.new("IntValue"); island.Name = "Island"; island.Value = 1; island.Parent = ls
	local tfp = Instance.new("IntValue"); tfp.Name = "TotalFartPower"; tfp.Value = 0; tfp.Parent = ls
	local tce = Instance.new("IntValue"); tce.Name = "TotalCoinsEarned"; tce.Value = 0; tce.Parent = ls

	playerGas[player] = 0

	task.spawn(function()
		task.wait(2)
		local standNum = 0
		for _, obj in ipairs(game.Workspace:GetDescendants()) do
			if obj:IsA("ProximityPrompt") and obj.ObjectText == "Stand" then
				standNum = standNum + 1
				if standNum <= 5 then
					obj:SetAttribute("IslandNumber", standNum)
					obj.Style = Enum.ProximityPromptStyle.Custom
					obj.Enabled = false
				end
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player) playerGas[player] = nil end)

BuyFoodEvent.OnServerEvent:Connect(function(player, foodName)
	local food = getFoodByName(foodName); if not food then return end
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local tfp   = ls:FindFirstChild("TotalFartPower")
	local tce   = ls:FindFirstChild("TotalCoinsEarned")
	if not coins or not tfp or not tce then return end
	if coins.Value < food.price then return end
	local gain = food.power
	if owns2xPass(player) then gain = gain * 2 end
	coins.Value = coins.Value - food.price
	tfp.Value   = tfp.Value + gain
	playerGas[player] = (playerGas[player] or 0) + gain
	tce.Value   = tce.Value + food.price
	checkIslandUnlock(player)
	pcall(function() RegenEvent:FireClient(player, gain) end)
end)

CoinEvent.OnServerEvent:Connect(function(player, amount)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local tce   = ls:FindFirstChild("TotalCoinsEarned")
	if not coins or not tce then return end
	local amt = math.floor(tonumber(amount) or 0)
	if amt <= 0 then return end
	coins.Value = coins.Value + amt
	tce.Value   = tce.Value + amt
	checkIslandUnlock(player)
end)

SkipIslandEvent.OnServerEvent:Connect(function(player)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local island = ls:FindFirstChild("Island"); if not island then return end
	if island.Value < 6 then island.Value = island.Value + 1 end
end)

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	if info.ProductId == PRODUCT_2X_1HOUR then
		player:SetAttribute("TwoXBoostEnd", os.time() + 3600)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif info.ProductId == PRODUCT_MIDAIR then
		local ls = player:FindFirstChild("leaderstats")
		local tfp = ls and ls:FindFirstChild("TotalFartPower")
		pcall(function() RegenEvent:FireClient(player, tfp and tfp.Value or 100) end)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif info.ProductId == PRODUCT_SKIP then
		pcall(function() SkipIslandEvent:FireClient(player) end)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end
'''
