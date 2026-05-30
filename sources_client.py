GAMECLIENT_SOURCE = '''-- Fart to Float v3 - Game Client (FartButton)
-- NOTE: Move this LocalScript to StarterPlayer/StarterPlayerScripts to run

local Players = game.Players
local player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SocialService = game:GetService("SocialService")
local MarketplaceService = game:GetService("MarketplaceService")
local PlayerGui = player.PlayerGui

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid", 10)
local hrp = character:WaitForChild("HumanoidRootPart", 10)

local gasMeter = 0
local maxGas = 0
local isFlying = false
local twoXBoostActive = false
local twoXBoostEndTime = 0
local midAirRechargeCount = 0
local skipIslandCount = 0
local ownsGlitterTrail = false
local ownsCustomColor = false
local customTrailColor = Color3.fromRGB(0, 200, 50)
local currentShopPage = 1
local shopOpen = false
local nearIslandNumber = 1

local foodEmojis = {
	Beans="\\xF0\\x9F\\xAB\\x98", Broccoli="\\xF0\\x9F\\xA5\\xA6", Cabbage="\\xF0\\x9F\\xA5\\xAC",
	Turnips="\\xF0\\x9F\\x8C\\xBF", Coconuts="\\xF0\\x9F\\xA5\\xA5", Bread="\\xF0\\x9F\\x8D\\x9E",
	Pasta="\\xF0\\x9F\\x8D\\x9D", Popcorn="\\xF0\\x9F\\x8D\\xBF", Milk="\\xF0\\x9F\\xA5\\x9B",
	Butter="\\xF0\\x9F\\xA7\\x88", IceCream="\\xF0\\x9F\\x8D\\xA6", Burger="\\xF0\\x9F\\x8D\\x94",
	Burrito="\\xF0\\x9F\\x8C\\xAF", Pizza="\\xF0\\x9F\\x8D\\x95"
}

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

local function getFoodsForIsland(n)
	local r = {}
	for _, f in ipairs(foods) do if f.island == n then table.insert(r, f) end end
	return r
end

-- UI helpers
local function mkCorner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p, col, t) local s = Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p, props)
	local l = Instance.new("TextLabel"); l.BackgroundTransparency=1
	for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l
end
local function mkFrame(p, props)
	local f = Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f
end
local function mkButton(p, props)
	local b = Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b
end

-- ===== GUI 1: GAS METER =====
local GasMeterGui = Instance.new("ScreenGui"); GasMeterGui.Name="GasMeterGui"; GasMeterGui.ResetOnSpawn=false; GasMeterGui.Parent=PlayerGui
local gmFrame = mkFrame(GasMeterGui, {Size=UDim2.new(0.55,0,0,70), Position=UDim2.new(0.225,0,0.88,0), BackgroundTransparency=1})
local gmLabel = mkLabel(gmFrame, {Text="\\xF0\\x9F\\x92\\xA8 GAS METER", Font=Enum.Font.GothamBold, TextSize=18, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0,25), Position=UDim2.new(0,0,0,0), RichText=true})
mkStroke(gmLabel, Color3.new(0,0,0), 2)
local gasBg = mkFrame(gmFrame, {Size=UDim2.new(1,0,0,35), Position=UDim2.new(0,0,1,-35), BackgroundColor3=Color3.fromRGB(60,60,60)})
mkCorner(gasBg, 20); mkStroke(gasBg, Color3.fromRGB(0,200,50), 3)
local gasFill = mkFrame(gasBg, {Name="Fill", Size=UDim2.new(0,0,1,0), BackgroundColor3=Color3.fromRGB(0,200,50), ZIndex=2})
mkCorner(gasFill, 20)
local fillGrad = Instance.new("UIGradient"); fillGrad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(0,220,60)), ColorSequenceKeypoint.new(1,Color3.fromRGB(255,220,0))}); fillGrad.Parent=gasFill
local gasPowerText = mkLabel(gasBg, {Size=UDim2.new(1,0,1,0), Text="0 / 0", Font=Enum.Font.GothamBold, TextSize=14, TextColor3=Color3.new(1,1,1), ZIndex=3})
mkStroke(gasPowerText, Color3.new(0,0,0), 1.5)

-- ===== GUI 2: FART BUTTON =====
local FartButtonGui = Instance.new("ScreenGui"); FartButtonGui.Name="FartButtonGui"; FartButtonGui.ResetOnSpawn=false; FartButtonGui.Parent=PlayerGui
local fartBtnFrame = mkFrame(FartButtonGui, {Position=UDim2.new(0.5,0,0.78,0), Size=UDim2.new(0,220,0,55), BackgroundColor3=Color3.fromRGB(50,200,50), AnchorPoint=Vector2.new(0.5,0.5)})
mkCorner(fartBtnFrame, 12); mkStroke(fartBtnFrame, Color3.fromRGB(0,150,0), 3)
local fartBtn = mkButton(fartBtnFrame, {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="\\xF0\\x9F\\x92\\xA8 CLICK TO FART!", Font=Enum.Font.GothamBold, TextSize=22, TextColor3=Color3.new(1,1,1), RichText=true})
mkStroke(fartBtn, Color3.new(0,0,0), 2)

-- ===== GUI 3: COIN DISPLAY =====
local CoinGui = Instance.new("ScreenGui"); CoinGui.Name="CoinGui"; CoinGui.ResetOnSpawn=false; CoinGui.Parent=PlayerGui
local coinPill = mkFrame(CoinGui, {Position=UDim2.new(1,-10,0,10), Size=UDim2.new(0,200,0,50), BackgroundColor3=Color3.fromRGB(255,200,0), AnchorPoint=Vector2.new(1,0)})
mkCorner(coinPill, 25); mkStroke(coinPill, Color3.fromRGB(200,140,0), 3)
mkLabel(coinPill, {Text="\\xF0\\x9F\\xAA\\x99", Size=UDim2.new(0,45,1,0), Position=UDim2.new(0,5,0,0), TextSize=28, RichText=true})
local coinAmount = mkLabel(coinPill, {Name="Amount", Text="0", Font=Enum.Font.GothamBold, TextSize=24, TextColor3=Color3.fromRGB(100,50,0), Size=UDim2.new(1,-55,1,0), Position=UDim2.new(0,50,0,0), TextXAlignment=Enum.TextXAlignment.Left})
mkStroke(coinAmount, Color3.new(1,1,1), 1.5)
local cpsLabel = mkLabel(CoinGui, {Name="CPS", Text="", Font=Enum.Font.Gotham, TextSize=13, TextColor3=Color3.fromRGB(50,150,0), Position=UDim2.new(1,-10,0,65), Size=UDim2.new(0,200,0,20), AnchorPoint=Vector2.new(1,0), TextXAlignment=Enum.TextXAlignment.Right, Visible=false})

-- ===== GUI 4: LEADERBOARD =====
local LeaderboardGui = Instance.new("ScreenGui"); LeaderboardGui.Name="LeaderboardGui"; LeaderboardGui.ResetOnSpawn=false; LeaderboardGui.Parent=PlayerGui
local lbPanel = mkFrame(LeaderboardGui, {Position=UDim2.new(1,-10,0,70), Size=UDim2.new(0,200,0,110), BackgroundColor3=Color3.fromRGB(255,255,255), AnchorPoint=Vector2.new(1,0)})
mkCorner(lbPanel, 12); mkStroke(lbPanel, Color3.fromRGB(200,200,200), 2)
mkLabel(lbPanel, {Text="\\xF0\\x9F\\x93\\x8A STATS", Font=Enum.Font.GothamBold, TextSize=16, TextColor3=Color3.fromRGB(50,50,50), Size=UDim2.new(1,-10,0,25), Position=UDim2.new(0,5,0,5), RichText=true, TextXAlignment=Enum.TextXAlignment.Left})
local lbIsland = mkLabel(lbPanel, {Text="\\xF0\\x9F\\x8F\\x9D\\xEF\\xB8\\x8F Island: 1", Font=Enum.Font.Gotham, TextSize=14, TextColor3=Color3.fromRGB(80,80,80), Size=UDim2.new(1,-10,0,22), Position=UDim2.new(0,5,0,30), RichText=true, TextXAlignment=Enum.TextXAlignment.Left})
local lbPower  = mkLabel(lbPanel, {Text="\\xE2\\x9A\\xA1 Power: 0",  Font=Enum.Font.Gotham, TextSize=14, TextColor3=Color3.fromRGB(80,80,80), Size=UDim2.new(1,-10,0,22), Position=UDim2.new(0,5,0,54), RichText=true, TextXAlignment=Enum.TextXAlignment.Left})
local lbEarned = mkLabel(lbPanel, {Text="\\xF0\\x9F\\xAA\\x99 Earned: 0", Font=Enum.Font.Gotham, TextSize=14, TextColor3=Color3.fromRGB(80,80,80), Size=UDim2.new(1,-10,0,22), Position=UDim2.new(0,5,0,78), RichText=true, TextXAlignment=Enum.TextXAlignment.Left})

-- ===== GUI 5: SIDEBAR =====
local SidebarGui = Instance.new("ScreenGui"); SidebarGui.Name="SidebarGui"; SidebarGui.ResetOnSpawn=false; SidebarGui.Parent=PlayerGui
local shopBtn = mkButton(SidebarGui, {Size=UDim2.new(0,70,0,70), Position=UDim2.new(0,10,0.4,0), BackgroundColor3=Color3.fromRGB(255,140,0), Text=""})
mkCorner(shopBtn,14); mkStroke(shopBtn, Color3.fromRGB(200,100,0), 3)
mkLabel(shopBtn, {Text="\\xF0\\x9F\\x9B\\x92", TextSize=32, Size=UDim2.new(1,0,0.65,0), RichText=true})
mkLabel(shopBtn, {Text="Shop", Font=Enum.Font.GothamBold, TextSize=13, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0.35,0), Position=UDim2.new(0,0,0.65,0)})
local inviteBtn = mkButton(SidebarGui, {Size=UDim2.new(0,70,0,70), Position=UDim2.new(0,10,0.4,85), BackgroundColor3=Color3.fromRGB(140,80,220), Text=""})
mkCorner(inviteBtn,14); mkStroke(inviteBtn, Color3.fromRGB(100,50,180), 3)
mkLabel(inviteBtn, {Text="\\xF0\\x9F\\x91\\xA5", TextSize=32, Size=UDim2.new(1,0,0.65,0), RichText=true})
mkLabel(inviteBtn, {Text="Invite", Font=Enum.Font.GothamBold, TextSize=13, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0.35,0), Position=UDim2.new(0,0,0.65,0)})

-- ===== GUI 6: FOOD STAND SHOP =====
local FoodShopGui = Instance.new("ScreenGui"); FoodShopGui.Name="FoodShopGui"; FoodShopGui.ResetOnSpawn=false; FoodShopGui.Enabled=false; FoodShopGui.Parent=PlayerGui
mkFrame(FoodShopGui, {Size=UDim2.new(1,0,1,0), BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=0.4})
local foodPanel = mkFrame(FoodShopGui, {Size=UDim2.new(0,680,0,480), Position=UDim2.new(0.5,0,0.5,0), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=Color3.fromRGB(240,248,255)})
mkCorner(foodPanel,16); mkStroke(foodPanel, Color3.fromRGB(100,180,255), 4)
local foodHeader = mkFrame(foodPanel, {Size=UDim2.new(1,0,0,55), BackgroundColor3=Color3.fromRGB(80,160,255)})
mkCorner(foodHeader,16)
local foodTitle = mkLabel(foodHeader, {Text="\\xF0\\x9F\\x8F\\x9D\\xEF\\xB8\\x8F ISLAND 1 FOOD STAND", Font=Enum.Font.GothamBold, TextSize=24, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,-60,1,0), RichText=true})
mkStroke(foodTitle, Color3.new(0,0,0), 2)
local foodCloseBtn = mkButton(foodHeader, {Size=UDim2.new(0,40,0,40), Position=UDim2.new(1,-45,0,7), BackgroundColor3=Color3.fromRGB(255,60,60), Text="X", Font=Enum.Font.GothamBold, TextSize=20, TextColor3=Color3.new(1,1,1)})
mkCorner(foodCloseBtn,8)

local foodLeftPanel = mkFrame(foodPanel, {Size=UDim2.new(0,280,1,-65), Position=UDim2.new(0,10,0,65), BackgroundColor3=Color3.new(1,1,1)})
mkCorner(foodLeftPanel,12)
local foodEmoji  = mkLabel(foodLeftPanel, {Text="\\xF0\\x9F\\xAB\\x98", TextSize=64, Size=UDim2.new(0,100,0,100), Position=UDim2.new(0.5,-50,0,10), RichText=true})
local foodName   = mkLabel(foodLeftPanel, {Text="Beans", Font=Enum.Font.GothamBold, TextSize=22, TextColor3=Color3.fromRGB(30,30,30), Size=UDim2.new(1,-10,0,30), Position=UDim2.new(0,5,0,115), TextXAlignment=Enum.TextXAlignment.Center})
local foodPrice  = mkLabel(foodLeftPanel, {Text="\\xF0\\x9F\\xAA\\x99 10 coins", Font=Enum.Font.GothamBold, TextSize=18, TextColor3=Color3.fromRGB(200,140,0), Size=UDim2.new(1,-10,0,25), Position=UDim2.new(0,5,0,148), RichText=true, TextXAlignment=Enum.TextXAlignment.Center})
local foodPower  = mkLabel(foodLeftPanel, {Text="+10 power", Font=Enum.Font.GothamBold, TextSize=16, TextColor3=Color3.fromRGB(0,160,60), Size=UDim2.new(1,-10,0,22), Position=UDim2.new(0,5,0,176), TextXAlignment=Enum.TextXAlignment.Center})
local foodPage   = mkLabel(foodLeftPanel, {Text="1/2", Font=Enum.Font.Gotham, TextSize=14, TextColor3=Color3.fromRGB(120,120,120), Size=UDim2.new(1,0,0,20), Position=UDim2.new(0,0,0,200), TextXAlignment=Enum.TextXAlignment.Center, Visible=false})
local foodPrev   = mkButton(foodLeftPanel, {Size=UDim2.new(0,40,0,40), Position=UDim2.new(0,15,0,225), BackgroundColor3=Color3.fromRGB(200,200,200), Text="<", Font=Enum.Font.GothamBold, TextSize=18})
mkCorner(foodPrev,8)
local foodNext   = mkButton(foodLeftPanel, {Size=UDim2.new(0,40,0,40), Position=UDim2.new(1,-55,0,225), BackgroundColor3=Color3.fromRGB(200,200,200), Text=">", Font=Enum.Font.GothamBold, TextSize=18})
mkCorner(foodNext,8)
local foodBuyBtn = mkButton(foodLeftPanel, {Size=UDim2.new(0.85,0,0,50), Position=UDim2.new(0.075,0,1,-60), BackgroundColor3=Color3.fromRGB(50,200,50), Text="BUY FOOD", Font=Enum.Font.GothamBold, TextSize=20, TextColor3=Color3.new(1,1,1)})
mkCorner(foodBuyBtn,12)
local foodLocked = mkLabel(foodLeftPanel, {Text="LOCKED", Font=Enum.Font.GothamBold, TextSize=32, TextColor3=Color3.fromRGB(200,0,0), Size=UDim2.new(1,0,0,50), Position=UDim2.new(0,0,0,120), Visible=false})
local foodUnlock = mkLabel(foodLeftPanel, {Text="Unlock at 0 coins earned", Font=Enum.Font.Gotham, TextSize=14, TextColor3=Color3.fromRGB(120,120,120), Size=UDim2.new(1,0,0,20), Position=UDim2.new(0,0,0,175), Visible=false})

local foodRight = mkFrame(foodPanel, {Size=UDim2.new(1,-300,1,-65), Position=UDim2.new(0,300,0,65), BackgroundColor3=Color3.fromRGB(248,248,248)})
mkCorner(foodRight,12)
mkLabel(foodRight, {Text="ALL FOODS", Font=Enum.Font.GothamBold, TextSize=18, TextColor3=Color3.fromRGB(50,50,50), Size=UDim2.new(1,-10,0,25), Position=UDim2.new(0,5,0,5)})
local foodScroll = Instance.new("ScrollingFrame"); foodScroll.Size=UDim2.new(1,-10,1,-35); foodScroll.Position=UDim2.new(0,5,0,30); foodScroll.BackgroundTransparency=1; foodScroll.ScrollBarThickness=6; foodScroll.CanvasSize=UDim2.new(0,0,0,0); foodScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; foodScroll.Parent=foodRight
local foodGrid = Instance.new("UIGridLayout"); foodGrid.CellSize=UDim2.new(0,155,0,70); foodGrid.CellPaddingSize=UDim2.new(0,6,0,6); foodGrid.Parent=foodScroll

local foodCells = {}
for _, f in ipairs(foods) do
	local cell = mkFrame(foodScroll, {Name=f.name, BackgroundColor3=Color3.fromRGB(200,240,200)}); mkCorner(cell,8); mkStroke(cell, Color3.fromRGB(150,200,150), 2)
	mkLabel(cell, {Text=foodEmojis[f.name] or "?", TextSize=28, Size=UDim2.new(0,40,1,0), Position=UDim2.new(0,2,0,0), RichText=true})
	mkLabel(cell, {Text=f.name, Font=Enum.Font.GothamBold, TextSize=13, TextColor3=Color3.fromRGB(30,30,30), Size=UDim2.new(1,-46,0,30), Position=UDim2.new(0,44,0,5), TextXAlignment=Enum.TextXAlignment.Left})
	mkLabel(cell, {Text="\\xF0\\x9F\\xAA\\x99 "..f.price, Font=Enum.Font.Gotham, TextSize=12, TextColor3=Color3.fromRGB(120,80,0), Size=UDim2.new(1,-46,0,20), Position=UDim2.new(0,44,0,38), TextXAlignment=Enum.TextXAlignment.Left, RichText=true})
	foodCells[f.name] = cell
end

-- ===== GUI 7: PREMIUM SHOP =====
local PremiumShopGui = Instance.new("ScreenGui"); PremiumShopGui.Name="PremiumShopGui"; PremiumShopGui.ResetOnSpawn=false; PremiumShopGui.Enabled=false; PremiumShopGui.Parent=PlayerGui
mkFrame(PremiumShopGui, {Size=UDim2.new(1,0,1,0), BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=0.5})
local premPanel = mkFrame(PremiumShopGui, {Size=UDim2.new(0,700,0,560), Position=UDim2.new(0.5,0,0.5,0), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=Color3.fromRGB(255,248,200)})
mkCorner(premPanel,16); mkStroke(premPanel, Color3.fromRGB(255,200,0), 4)
local premHeader = mkFrame(premPanel, {Size=UDim2.new(1,0,0,60), BackgroundColor3=Color3.fromRGB(255,200,0)}); mkCorner(premHeader,16)
local premTitle = mkLabel(premHeader, {Text="PREMIUM SHOP", Font=Enum.Font.GothamBold, TextSize=28, TextColor3=Color3.fromRGB(100,50,0), Size=UDim2.new(1,-60,1,0)})
mkStroke(premTitle, Color3.new(1,1,1), 2)
local premClose = mkButton(premHeader, {Size=UDim2.new(0,40,0,40), Position=UDim2.new(1,-45,0,10), BackgroundColor3=Color3.fromRGB(255,60,60), Text="X", Font=Enum.Font.GothamBold, TextSize=20, TextColor3=Color3.new(1,1,1)}); mkCorner(premClose,8)

mkLabel(premPanel, {Text="GAMEPASSES - Permanent perks", Font=Enum.Font.GothamBold, TextSize=16, TextColor3=Color3.fromRGB(80,80,80), Size=UDim2.new(1,-20,0,24), Position=UDim2.new(0,10,0,68), TextXAlignment=Enum.TextXAlignment.Left, BackgroundTransparency=1})

local function mkCard(parent, xPos, yPos, icon, title, desc, price, btnCol, btnTxt, onClick)
	local card = mkFrame(parent, {Size=UDim2.new(0,200,0,180), Position=UDim2.new(0,xPos,0,yPos), BackgroundColor3=Color3.new(1,1,1)}); mkCorner(card,12); mkStroke(card, Color3.fromRGB(220,220,220), 2)
	mkLabel(card, {Text=icon, TextSize=36, Size=UDim2.new(1,0,0,50), Position=UDim2.new(0,0,0,5), RichText=true})
	mkLabel(card, {Text=title, Font=Enum.Font.GothamBold, TextSize=13, TextColor3=Color3.fromRGB(30,30,30), Size=UDim2.new(1,-10,0,35), Position=UDim2.new(0,5,0,55), TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Center, BackgroundTransparency=1})
	mkLabel(card, {Text=desc, Font=Enum.Font.Gotham, TextSize=12, TextColor3=Color3.fromRGB(120,120,120), Size=UDim2.new(1,-10,0,30), Position=UDim2.new(0,5,0,90), TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Center, BackgroundTransparency=1})
	mkLabel(card, {Text=price, Font=Enum.Font.GothamBold, TextSize=14, TextColor3=Color3.fromRGB(0,150,0), Size=UDim2.new(1,-10,0,18), Position=UDim2.new(0,5,0,122), TextXAlignment=Enum.TextXAlignment.Center, BackgroundTransparency=1})
	local btn = mkButton(card, {Size=UDim2.new(0.85,0,0,28), Position=UDim2.new(0.075,0,1,-35), BackgroundColor3=btnCol, Text=btnTxt, Font=Enum.Font.GothamBold, TextSize=13, TextColor3=Color3.new(1,1,1)}); mkCorner(btn,8); btn.MouseButton1Click:Connect(onClick)
end

mkCard(premPanel,10,95,"PWR","2x Fart Power - FOREVER","Double your fart power on every purchase!","249 R$",Color3.fromRGB(255,180,0),"BUY GAMEPASS",function() pcall(function() MarketplaceService:PromptGamePassPurchase(player,0) end) end)
mkCard(premPanel,220,95,"GLTR","Glitter Fart Trail","Leave a sparkling glitter trail!","49 R$",Color3.fromRGB(220,80,180),"BUY GAMEPASS",function() pcall(function() MarketplaceService:PromptGamePassPurchase(player,0) end) end)
mkCard(premPanel,430,95,"CLR","Custom Color Trail","Choose your own fart trail colour!","89 R$",Color3.fromRGB(140,80,220),"BUY GAMEPASS",function() pcall(function() MarketplaceService:PromptGamePassPurchase(player,0) end) end)

mkLabel(premPanel, {Text="ONE-TIME ITEMS - Spend and enjoy", Font=Enum.Font.GothamBold, TextSize=16, TextColor3=Color3.fromRGB(80,80,80), Size=UDim2.new(1,-20,0,24), Position=UDim2.new(0,10,0,288), TextXAlignment=Enum.TextXAlignment.Left, BackgroundTransparency=1})
mkCard(premPanel,10,315,"2XHR","2x Fart Power - 1 Hour","Double fart power for 60 minutes!","59 R$",Color3.fromRGB(50,120,255),"BUY",function() pcall(function() MarketplaceService:PromptProductPurchase(player,0) end) end)
mkCard(premPanel,220,315,"RCHG","Mid-Air Recharge","Instantly refill your gas meter!","39 R$",Color3.fromRGB(50,200,50),"BUY",function() pcall(function() MarketplaceService:PromptProductPurchase(player,0) end) end)
mkCard(premPanel,430,315,"SKIP","Skip Island","Instantly unlock the next island!","69 R$",Color3.fromRGB(255,140,0),"BUY",function() pcall(function() MarketplaceService:PromptProductPurchase(player,0) end) end)

-- ===== GUI 8: HOTBAR =====
local HotbarGui = Instance.new("ScreenGui"); HotbarGui.Name="HotbarGui"; HotbarGui.ResetOnSpawn=false; HotbarGui.Parent=PlayerGui
local hotbarFrame = mkFrame(HotbarGui, {Position=UDim2.new(1,-10,1,-80), Size=UDim2.new(0,140,0,60), AnchorPoint=Vector2.new(1,1), BackgroundTransparency=1, Visible=false})
local hbLayout = Instance.new("UIListLayout"); hbLayout.FillDirection=Enum.FillDirection.Horizontal; hbLayout.Padding=UDim.new(0,5); hbLayout.Parent=hotbarFrame
local rechargeSlot = mkButton(hotbarFrame, {Size=UDim2.new(0,60,0,60), BackgroundColor3=Color3.fromRGB(50,50,50), BackgroundTransparency=0.3, Text="RCHRG", TextSize=11, Font=Enum.Font.GothamBold, TextColor3=Color3.new(1,1,1)})
mkCorner(rechargeSlot,10); mkStroke(rechargeSlot, Color3.fromRGB(100,100,100), 2)
local rechargeBadge = mkLabel(rechargeSlot, {Text="0", Font=Enum.Font.GothamBold, TextSize=12, TextColor3=Color3.new(1,1,1), Size=UDim2.new(0,20,0,20), Position=UDim2.new(1,-20,1,-20), BackgroundColor3=Color3.fromRGB(255,60,60)}); mkCorner(rechargeBadge,10)
local skipSlot = mkButton(hotbarFrame, {Size=UDim2.new(0,60,0,60), BackgroundColor3=Color3.fromRGB(50,50,50), BackgroundTransparency=0.3, Text="SKIP", TextSize=13, Font=Enum.Font.GothamBold, TextColor3=Color3.new(1,1,1)})
mkCorner(skipSlot,10); mkStroke(skipSlot, Color3.fromRGB(100,100,100), 2)
local skipBadge = mkLabel(skipSlot, {Text="0", Font=Enum.Font.GothamBold, TextSize=12, TextColor3=Color3.new(1,1,1), Size=UDim2.new(0,20,0,20), Position=UDim2.new(1,-20,1,-20), BackgroundColor3=Color3.fromRGB(255,60,60)}); mkCorner(skipBadge,10)

-- ===== ALL GUIs BUILT — CONNECT EVENTS =====
local RS = game:GetService("ReplicatedStorage")
local BuyFoodEvent, RegenEvent, CoinEvent, SkipIslandEvent
pcall(function()
	BuyFoodEvent   = RS:WaitForChild("BuyFoodEvent", 10)
	RegenEvent     = RS:WaitForChild("RegenEvent", 10)
	CoinEvent      = RS:WaitForChild("CoinEvent", 10)
	SkipIslandEvent= RS:WaitForChild("SkipIslandEvent", 10)
end)

local leaderstats
pcall(function() leaderstats = player:WaitForChild("leaderstats", 10) end)

local function updateMeter()
	local fill = maxGas > 0 and math.clamp(gasMeter/maxGas, 0, 1) or 0
	gasFill.Size = UDim2.new(fill, 0, 1, 0)
	gasPowerText.Text = math.floor(gasMeter).." / "..math.floor(maxGas)
end

local function updateFartBtn()
	if gasMeter <= 0 then
		fartBtnFrame.BackgroundColor3 = Color3.fromRGB(120,120,120)
		local st = fartBtnFrame:FindFirstChildWhichIsA("UIStroke"); if st then st.Color = Color3.fromRGB(80,80,80) end
		fartBtn.Text = "\\xF0\\x9F\\x92\\xA8 NO GAS! BUY FOOD"
	else
		fartBtnFrame.BackgroundColor3 = Color3.fromRGB(50,200,50)
		local st = fartBtnFrame:FindFirstChildWhichIsA("UIStroke"); if st then st.Color = Color3.fromRGB(0,150,0) end
		fartBtn.Text = "\\xF0\\x9F\\x92\\xA8 CLICK TO FART!"
	end
end

local function updateCoins()
	pcall(function()
		if leaderstats then
			local c = leaderstats:FindFirstChild("Coins"); if c then coinAmount.Text = tostring(c.Value) end
		end
	end)
end

local function updateHotbar()
	hotbarFrame.Visible = midAirRechargeCount > 0 or skipIslandCount > 0
	rechargeBadge.Text = tostring(midAirRechargeCount)
	skipBadge.Text = tostring(skipIslandCount)
end

local function getFlightSpeed(p)
	if p < 100 then return 30
	elseif p < 500 then return 30+(p-100)/400*20
	elseif p < 1000 then return 50+(p-500)/500*20
	elseif p < 5000 then return 70+(p-1000)/4000*40
	elseif p < 10000 then return 110+(p-5000)/5000*50
	elseif p < 50000 then return 160+(p-10000)/40000*70
	elseif p < 100000 then return 230+(p-50000)/50000*70
	else return 300 end
end

local function getHeightCap(p)
	if p < 100 then return 150
	elseif p < 500 then return 300
	elseif p < 1000 then return 600
	elseif p < 5000 then return 1200
	elseif p < 10000 then return 2500
	elseif p < 50000 then return 6000
	elseif p < 100000 then return 12000
	else return 25000 end
end

local gColors = {Color3.fromRGB(0,200,50), Color3.fromRGB(50,220,80), Color3.fromRGB(100,255,100), Color3.fromRGB(80,180,40)}
local glColors= {Color3.fromRGB(255,215,0), Color3.fromRGB(255,100,200), Color3.fromRGB(0,200,255)}

local function spawnCloud()
	if not hrp then return end
	local cloud = Instance.new("Part"); cloud.Shape=Enum.PartType.Ball
	cloud.Size = Vector3.new(math.random(10,25)/10, math.random(10,25)/10, math.random(10,25)/10)
	if ownsCustomColor then cloud.Color = customTrailColor
	elseif ownsGlitterTrail then
		local all={}; for _,c in ipairs(gColors) do table.insert(all,c) end; for _,c in ipairs(glColors) do table.insert(all,c) end
		cloud.Color = all[math.random(1,#all)]
	else cloud.Color = gColors[math.random(1,#gColors)] end
	cloud.Material=Enum.Material.Neon; cloud.Transparency=0.3; cloud.CanCollide=false; cloud.Anchored=true; cloud.CastShadow=false
	cloud.Position = hrp.Position + Vector3.new(math.random(-15,15)/10, math.random(-10,5)/10, math.random(-15,15)/10)
	cloud.Parent = workspace
	local tw = TweenService:Create(cloud, TweenInfo.new(1.5,Enum.EasingStyle.Linear), {Transparency=1.0, Size=Vector3.new(0.1,0.1,0.1)})
	tw:Play(); tw.Completed:Connect(function() cloud:Destroy() end)
end

local bv = nil
local cloudTimer = 0
local coinTimer = 0

local function startFlying()
	if gasMeter <= 0 or not hrp then return end
	isFlying = true
	if bv then bv:Destroy() end
	bv = Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(0,math.huge,0); bv.Velocity=Vector3.new(0,0,0); bv.Parent=hrp
end

local function stopFlying()
	isFlying = false
	if bv then bv:Destroy(); bv=nil end
	cpsLabel.Visible = false
	updateFartBtn()
end

RunService.Heartbeat:Connect(function(dt)
	if twoXBoostActive and os.time() > twoXBoostEndTime then twoXBoostActive = false end
	if not isFlying then return end
	if gasMeter <= 0 then stopFlying(); return end
	if not hrp or not bv then return end
	local power = 0
	pcall(function() if leaderstats then local t=leaderstats:FindFirstChild("TotalFartPower"); if t then power=t.Value end end end)
	local spd = getFlightSpeed(power); if twoXBoostActive then spd=spd*2 end
	local cap = getHeightCap(power)
	bv.Velocity = hrp.Position.Y < cap and Vector3.new(0,spd,0) or Vector3.new(0,0,0)
	gasMeter = math.max(0, gasMeter - 8*dt)
	updateMeter()
	coinTimer=coinTimer+dt
	if coinTimer >= 0.1 then
		coinTimer=0
		local h = math.max(0, hrp.Position.Y-5)
		local cpt = math.floor(h/10)*0.1
		if cpt > 0 then
			pcall(function() if CoinEvent then CoinEvent:FireServer(cpt) end end)
			cpsLabel.Text = "+"..math.floor(cpt*10).."/sec"; cpsLabel.Visible=true
		end
	end
	cloudTimer=cloudTimer+dt
	if cloudTimer >= 0.1 then cloudTimer=0; pcall(spawnCloud) end
end)

fartBtn.MouseButton1Down:Connect(function() if gasMeter > 0 then startFlying() end end)
fartBtn.MouseButton1Up:Connect(stopFlying)

shopBtn.MouseButton1Click:Connect(function() PremiumShopGui.Enabled = not PremiumShopGui.Enabled end)
inviteBtn.MouseButton1Click:Connect(function() pcall(function() SocialService:PromptInviteAsync(player) end) end)
premClose.MouseButton1Click:Connect(function() PremiumShopGui.Enabled=false end)
foodCloseBtn.MouseButton1Click:Connect(function() FoodShopGui.Enabled=false; shopOpen=false end)

local function updateFoodShop(islandNum)
	nearIslandNumber = islandNum
	foodTitle.Text = "ISLAND "..islandNum.." FOOD STAND"
	local pIsland = 1
	pcall(function() if leaderstats then local i=leaderstats:FindFirstChild("Island"); if i then pIsland=i.Value end end end)
	local locked = islandNum > pIsland
	foodLocked.Visible=locked; foodUnlock.Visible=locked
	foodEmoji.Visible=not locked; foodName.Visible=not locked; foodPrice.Visible=not locked
	foodPower.Visible=not locked; foodBuyBtn.Visible=not locked; foodPrev.Visible=not locked; foodNext.Visible=not locked
	if locked then foodUnlock.Text="Unlock at "..(islandThresholds[islandNum] or 0).." coins earned"; return end
	local ifoods = getFoodsForIsland(islandNum)
	if #ifoods==0 then return end
	if currentShopPage > #ifoods then currentShopPage=1 end
	local f = ifoods[currentShopPage]
	foodEmoji.Text = foodEmojis[f.name] or "?"
	foodName.Text  = f.name
	foodPrice.Text = "\\xF0\\x9F\\xAA\\x99 "..f.price.." coins"
	foodPower.Text = "+"..f.power.." power"
	foodPage.Visible = #ifoods > 1; foodPage.Text = currentShopPage.."/"..#ifoods
	local coins = 0
	pcall(function() if leaderstats then local c=leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end end end)
	if coins >= f.price then
		foodBuyBtn.BackgroundColor3=Color3.fromRGB(50,200,50); foodBuyBtn.Text="BUY FOOD"; foodBuyBtn.TextSize=20
	else
		foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text="NOT ENOUGH COINS"; foodBuyBtn.TextSize=16
	end
	for _, fd in ipairs(foods) do
		local cell = foodCells[fd.name]
		if cell then
			local st = cell:FindFirstChildWhichIsA("UIStroke")
			if coins >= fd.price then cell.BackgroundColor3=Color3.fromRGB(200,240,200); if st then st.Color=Color3.fromRGB(150,200,150) end
			else cell.BackgroundColor3=Color3.fromRGB(210,210,210); if st then st.Color=Color3.fromRGB(160,160,160) end end
		end
	end
end

foodPrev.MouseButton1Click:Connect(function()
	local ifoods=getFoodsForIsland(nearIslandNumber); currentShopPage=currentShopPage-1; if currentShopPage<1 then currentShopPage=#ifoods end; updateFoodShop(nearIslandNumber)
end)
foodNext.MouseButton1Click:Connect(function()
	local ifoods=getFoodsForIsland(nearIslandNumber); currentShopPage=currentShopPage+1; if currentShopPage>#ifoods then currentShopPage=1 end; updateFoodShop(nearIslandNumber)
end)
foodBuyBtn.MouseButton1Click:Connect(function()
	local ifoods=getFoodsForIsland(nearIslandNumber); if #ifoods==0 then return end
	if currentShopPage>#ifoods then currentShopPage=1 end
	local f=ifoods[currentShopPage]
	local coins=0; pcall(function() if leaderstats then local c=leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end end end)
	if coins < f.price then return end
	pcall(function() if BuyFoodEvent then BuyFoodEvent:FireServer(f.name) end end)
	local fl=Instance.new("TextLabel"); fl.Text="+"..f.power.." power!"; fl.Font=Enum.Font.GothamBold; fl.TextSize=20; fl.TextColor3=Color3.fromRGB(0,200,50); fl.BackgroundTransparency=1; fl.Size=UDim2.new(0,200,0,40); fl.Position=UDim2.new(0.3,0,0.6,0); fl.ZIndex=10; fl.Parent=FoodShopGui
	TweenService:Create(fl, TweenInfo.new(1.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out), {Position=UDim2.new(0.3,0,0.4,0), TextTransparency=1}):Play()
	task.delay(1.5, function() fl:Destroy() end)
end)

rechargeSlot.MouseButton1Click:Connect(function()
	if midAirRechargeCount > 0 then
		midAirRechargeCount = midAirRechargeCount-1
		pcall(function() if leaderstats then local t=leaderstats:FindFirstChild("TotalFartPower"); if t then gasMeter=t.Value; maxGas=t.Value end end end)
		updateMeter(); updateFartBtn(); updateHotbar()
		pcall(function() if RegenEvent then RegenEvent:FireServer() end end)
	end
end)
skipSlot.MouseButton1Click:Connect(function()
	if skipIslandCount > 0 then
		skipIslandCount = skipIslandCount-1
		pcall(function() if SkipIslandEvent then SkipIslandEvent:FireServer() end end)
		updateHotbar()
	end
end)

pcall(function()
	if RegenEvent then
		RegenEvent.OnClientEvent:Connect(function(power)
			local g = tonumber(power) or 0
			gasMeter = gasMeter + g
			if twoXBoostActive then gasMeter = gasMeter + g end
			if leaderstats then local t=leaderstats:FindFirstChild("TotalFartPower"); if t and t.Value > maxGas then maxGas=t.Value end end
			if maxGas > 0 and gasMeter > maxGas then gasMeter = maxGas end
			updateMeter(); updateFartBtn()
		end)
	end
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		pcall(function()
			if leaderstats then
				local isl=leaderstats:FindFirstChild("Island"); local tfp=leaderstats:FindFirstChild("TotalFartPower"); local tce=leaderstats:FindFirstChild("TotalCoinsEarned")
				if isl then lbIsland.Text="Island: "..isl.Value end
				if tfp then lbPower.Text="Power: "..tfp.Value; if tfp.Value > maxGas then maxGas=tfp.Value; updateMeter() end end
				if tce then lbEarned.Text="Earned: "..tce.Value end
			end
		end)
		updateCoins()
	end
end)

pcall(function()
	if leaderstats then
		local c=leaderstats:FindFirstChild("Coins"); if c then c.Changed:Connect(function() updateCoins(); if shopOpen then updateFoodShop(nearIslandNumber) end end) end
		local t=leaderstats:FindFirstChild("TotalFartPower"); if t then t.Changed:Connect(function(v) if v>maxGas then maxGas=v end; updateMeter() end) end
	end
end)

-- ===== PROXIMITY DETECTION (own task.spawn) =====
task.spawn(function()
	local DIST = 20
	while true do
		task.wait(0.1)
		pcall(function()
			local char = player.Character; if not char then return end
			local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
			local nearStand=false; local nearIsland=1
			for _, obj in ipairs(workspace:GetDescendants()) do
				if obj:IsA("ProximityPrompt") and obj.ObjectText=="Stand" then
					local part = obj.Parent
					if part and part:IsA("BasePart") then
						if (root.Position - part.Position).Magnitude < DIST then
							nearStand=true; nearIsland=obj:GetAttribute("IslandNumber") or 1; break
						end
					end
				end
			end
			if nearStand and not shopOpen then
				currentShopPage=1; updateFoodShop(nearIsland)
				FoodShopGui.Enabled=true; shopOpen=true
			elseif not nearStand and shopOpen then
				FoodShopGui.Enabled=false; shopOpen=false
			end
		end)
	end
end)

updateFartBtn(); updateMeter(); updateCoins()
'''
