local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local function getOrCreate(parent, className, name)
	local obj = parent:FindFirstChild(name)
	if not obj then obj = Instance.new(className); obj.Name = name; obj.Parent = parent end
	return obj
end

local BuyFoodEvent      = getOrCreate(RS, "RemoteEvent", "BuyFoodEvent")
local RegenEvent        = getOrCreate(RS, "RemoteEvent", "RegenEvent")
local CoinEvent         = getOrCreate(RS, "RemoteEvent", "CoinEvent")
local SkipIslandEvent   = getOrCreate(RS, "RemoteEvent", "SkipIslandEvent")
local UnlockIslandEvent = getOrCreate(RS, "RemoteEvent", "UnlockIslandEvent")
local AnnouncementEvent = getOrCreate(RS, "RemoteEvent", "AnnouncementEvent")
local ServerEventNotify = getOrCreate(RS, "RemoteEvent", "ServerEventNotify")

local ISLAND_DISPLAY_NAMES = {
	"Bean Farm","Broccoli Bluff","Cabbage Cliffs","Turnip Tranquil",
	"Coconut Cove","Bread Board","Pasta Peak","Popcorn Pinnacle",
	"Milk Marsh","Butter Swamp","Ice Cream Isle","Burger Bluff",
	"Burrito Barrens","Pizza Palms"
}

local foods = {
	{name="Beans",    price=10,     power=3,   island=1},
	{name="Broccoli", price=25,     power=5,   island=2},
	{name="Cabbage",  price=50,     power=8,   island=3},
	{name="Turnips",  price=100,    power=12,  island=4},
	{name="Coconuts", price=250,    power=18,  island=5},
	{name="Bread",    price=500,    power=26,  island=6},
	{name="Pasta",    price=1000,   power=37,  island=7},
	{name="Popcorn",  price=2500,   power=52,  island=8},
	{name="Milk",     price=5000,   power=72,  island=9},
	{name="Butter",   price=10000,  power=98,  island=10},
	{name="IceCream", price=25000,  power=132, island=11},
	{name="Burger",   price=50000,  power=175, island=12},
	{name="Burrito",  price=75000,  power=225, island=13},
	{name="Pizza",    price=100000, power=280, island=14},
}

local ISLAND_NAMES = {
	"Island_1_BeanFarm","Island_2_BroccoliBluff","Island_3_CabbageCliffs",
	"Island_4_TurnipTranquil","Island_5_CoconutCove","Island_6_BreadBoard",
	"Island_7_PastaPeak","Island_8_PopcornPinnacle","Island_9_MilkMarsh",
	"Island_10_ButterSwamp","Island_11_IceCreamIsle","Island_12_BurgerBluff",
	"Island_13_BurritoBarrens","Island_14_PizzaPalms"
}

local ISLAND_POSITIONS = {
	{x=0,    y=50,    z=0},   {x=120,  y=600,   z=60},   {x=-160, y=1400,  z=100},
	{x=180,  y=2500,  z=-120}, {x=-200, y=4000,  z=160},  {x=220,  y=6000,  z=-180},
	{x=-240, y=8500,  z=200},  {x=260,  y=11500, z=-220}, {x=-280, y=15000, z=240},
	{x=300,  y=19000, z=-260}, {x=-320, y=24000, z=280},  {x=340,  y=30000, z=-300},
	{x=-360, y=37000, z=320},  {x=380,  y=45000, z=-340},
}

local GAMEPASS_2X      = 0
local PRODUCT_2X_1HOUR = 0
local PRODUCT_MIDAIR   = 0
local PRODUCT_SKIP     = 0

local playerCoinAccum = {}

local function getFoodByName(name)
	for _, f in ipairs(foods) do if f.name == name then return f end end
end

local function owns2xPass(player)
	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GAMEPASS_2X)
	end)
	return ok and result
end

task.spawn(function()
	task.wait(2)
	for i, iname in ipairs(ISLAND_NAMES) do
		local model = workspace:FindFirstChild(iname)
		local pos = ISLAND_POSITIONS[i]
		if model then
			pcall(function()
				if model:IsA("Model") then
					if model.PrimaryPart then
						model:SetPrimaryPartCFrame(CFrame.new(pos.x, pos.y, pos.z))
					else
						model:MoveTo(Vector3.new(pos.x, pos.y, pos.z))
					end
				end
			end)
			print("Positioned "..iname.." at Y="..pos.y)
			for _, obj in ipairs(model:GetDescendants()) do
				if obj:IsA("ProximityPrompt") and obj.ObjectText == "Stand" then
					obj:SetAttribute("IslandNumber", i)
					obj.Style = Enum.ProximityPromptStyle.Custom
					obj.Enabled = false
				end
			end
		else
			print("WARNING: "..iname.." not found in workspace")
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	local ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player
	local coins  = Instance.new("IntValue"); coins.Name  = "Coins";          coins.Value  = 50; coins.Parent  = ls
	local island = Instance.new("IntValue"); island.Name = "Island";         island.Value = 1;  island.Parent = ls
	local tfp    = Instance.new("IntValue"); tfp.Name    = "TotalFartPower"; tfp.Value    = 0;  tfp.Parent    = ls
	local tce    = Instance.new("IntValue"); tce.Name    = "TotalCoinsEarned"; tce.Value  = 0;  tce.Parent    = ls
	playerCoinAccum[player] = 0
end)

Players.PlayerRemoving:Connect(function(player)
	playerCoinAccum[player] = nil
end)

BuyFoodEvent.OnServerEvent:Connect(function(player, foodName)
	local food = getFoodByName(foodName); if not food then return end
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins  = ls:FindFirstChild("Coins")
	local tfp    = ls:FindFirstChild("TotalFartPower")
	local tce    = ls:FindFirstChild("TotalCoinsEarned")
	local island = ls:FindFirstChild("Island")
	if not coins or not tfp or not tce then return end
	if island and food.island > island.Value then return end
	if coins.Value < food.price then return end
	local gain = food.power
	if owns2xPass(player) then gain = gain * 2 end
	coins.Value = coins.Value - food.price
	tfp.Value   = tfp.Value + gain
	tce.Value   = tce.Value + food.price
	pcall(function() RegenEvent:FireClient(player, gain) end)
end)

CoinEvent.OnServerEvent:Connect(function(player, amount)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local tce   = ls:FindFirstChild("TotalCoinsEarned")
	if not coins or not tce then return end
	local amt = tonumber(amount) or 0; if amt <= 0 then return end
	playerCoinAccum[player] = (playerCoinAccum[player] or 0) + amt
	local toAdd = math.floor(playerCoinAccum[player])
	if toAdd > 0 then
		playerCoinAccum[player] = playerCoinAccum[player] - toAdd
		coins.Value = coins.Value + toAdd
		tce.Value   = tce.Value + toAdd
	end
end)

UnlockIslandEvent.OnServerEvent:Connect(function(player, islandNum)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local island = ls:FindFirstChild("Island"); if not island then return end
	local n = tonumber(islandNum) or 0
	if n > island.Value and n <= 14 then
		island.Value = n
		print("ISLAND "..n.." UNLOCKED by "..player.Name)
		local iname = ISLAND_DISPLAY_NAMES[n] or ("Island "..n)
		pcall(function() AnnouncementEvent:FireAllClients(player.Name, n, iname) end)
	end
end)

SkipIslandEvent.OnServerEvent:Connect(function(player)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local island = ls:FindFirstChild("Island"); if not island then return end
	if island.Value < 14 then island.Value = island.Value + 1 end
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
		local ls = player:FindFirstChild("leaderstats")
		local island = ls and ls:FindFirstChild("Island")
		if island and island.Value < 14 then island.Value = island.Value + 1 end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- ===== SERVER-WIDE EVENT LOOP =====
local eventPool = {
	{name="FART_STORM",  dispName="\xF0\x9F\x92\xA8 FART STORM",  weight=30, dur=60, msg="\xF0\x9F\x92\xA8 FART STORM! Everyone flies faster for 60 seconds!",      r=100,g=200,b=255},
	{name="COIN_RUSH",   dispName="\xF0\x9F\xAA\x99 COIN RUSH",   weight=25, dur=45, msg="\xF0\x9F\xAA\x99 COIN RUSH! Triple coins for 45 seconds!",                  r=255,g=200,b=0},
	{name="LOW_GRAVITY", dispName="\xF0\x9F\x8C\x99 LOW GRAVITY", weight=20, dur=60, msg="\xF0\x9F\x8C\x99 LOW GRAVITY! Float like a cloud for 60 seconds!",          r=150,g=100,b=255},
	{name="POWER_SURGE", dispName="\xE2\x9A\xA1 POWER SURGE",     weight=15, dur=30, msg="\xE2\x9A\xA1 POWER SURGE! Fly higher than ever for 30 seconds!",            r=255,g=255,b=0},
	{name="RING_FEVER",  dispName="\xF0\x9F\x8E\xAF RING FEVER",  weight=10, dur=60, msg="\xF0\x9F\x8E\xAF RING FEVER! Massive ring bonuses for 60 seconds!",         r=255,g=100,b=200},
}

local function pickEvent()
	local roll = math.random(100)
	local cum = 0
	for _, ev in ipairs(eventPool) do
		cum = cum + ev.weight
		if roll <= cum then return ev end
	end
	return eventPool[1]
end

task.spawn(function()
	task.wait(math.random(180, 300))
	while true do
		local ev = pickEvent()
		pcall(function()
			ServerEventNotify:FireAllClients(ev.name, ev.dispName, ev.dur, ev.msg, Color3.fromRGB(ev.r, ev.g, ev.b))
		end)
		task.wait(ev.dur)
		pcall(function()
			ServerEventNotify:FireAllClients("END", "", 0, "", Color3.new(1,1,1))
		end)
		task.wait(math.random(180, 300))
	end
end)

-- Thunderstorm: every 480 seconds, lasts 10 seconds
task.spawn(function()
	task.wait(480)
	while true do
		pcall(function()
			ServerEventNotify:FireAllClients("THUNDERSTORM", "\xe2\x9b\x88 THUNDERSTORM", 10, "\xe2\x9b\x88\xef\xb8\x8f THUNDERSTORM! Hard to see!", Color3.fromRGB(50,50,80))
		end)
		task.wait(490)
	end
end)

-- Windstorm: every 480 seconds, offset 240s from thunderstorm
task.spawn(function()
	task.wait(240)
	while true do
		pcall(function()
			ServerEventNotify:FireAllClients("WINDSTORM", "\xF0\x9F\x92\xA8 WIND STORM", 10, "\xF0\x9F\x92\xA8 WIND STORM! Fighting the wind!", Color3.fromRGB(100,150,200))
		end)
		task.wait(490)
	end
end)

print("CHUNK 3 DONE")
