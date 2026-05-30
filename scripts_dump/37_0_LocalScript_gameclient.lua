print("GAMECLIENT STARTED")

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

-- ===== STATE =====
local cosmeticGas = 100
local hasBoughtFood = false
local isFlying = false
local twoXBoostActive = false
local twoXBoostEndTime = 0
local midAirRechargeCount = 0
local skipIslandCount = 0
local ownsGlitterTrail = false
local ownsCustomColor = false
local customTrailColor = Color3.fromRGB(0, 200, 50)
local shopOpen = false
local playerClosedShop = false
local nearIslandNumber = 1
local flightStartY = 50
local flightStartTime = 0
local peakHeight = 0
local ringsCollectedFlight = 0
local arrivedIslands = {}
local currentKnownIsland = 0
local arrivalHideToken = nil
local ringStreak = 0
local ringMultiplier = 1
local activeRings = {}
local landingPads = {}
local activeGasPockets = {}
local serverEventActive = false
local serverEventEndTime = 0
local serverEventDisplayName = ""
local serverEventSpeedMult = 1
local serverEventCoinMult = 1
local serverEventGasDrainMult = 1
local serverEventHeightMult = 1
local serverEventRingMult = 1
local turbTimer = 0
local activeBirds = {}
local birdSpawnTimer = 0
local birdSpawnInterval = math.random(20, 40)
local thunderstormActive = false
local windstormActive = false
local windstormDir = Vector3.new(1, 0, 0)
local stormWindTimer = 0
local hasLanded = true

-- ===== DATA =====
local ISLAND_NAMES = {
	"Island_1_BeanFarm","Island_2_BroccoliBluff","Island_3_CabbageCliffs",
	"Island_4_TurnipTranquil","Island_5_CoconutCove","Island_6_BreadBoard",
	"Island_7_PastaPeak","Island_8_PopcornPinnacle","Island_9_MilkMarsh",
	"Island_10_ButterSwamp","Island_11_IceCreamIsle","Island_12_BurgerBluff",
	"Island_13_BurritoBarrens","Island_14_PizzaPalms"
}

local ISLAND_DISPLAY_NAMES = {
	"Bean Farm","Broccoli Bluff","Cabbage Cliffs","Turnip Tranquil",
	"Coconut Cove","Bread Board","Pasta Peak","Popcorn Pinnacle",
	"Milk Marsh","Butter Swamp","Ice Cream Isle","Burger Bluff",
	"Burrito Barrens","Pizza Palms"
}

local islandColors = {
	Color3.fromRGB(100,200,100), Color3.fromRGB(100,180,100),
	Color3.fromRGB(150,200,80),  Color3.fromRGB(180,220,80),
	Color3.fromRGB(255,180,50),  Color3.fromRGB(220,160,80),
	Color3.fromRGB(200,120,60),  Color3.fromRGB(255,140,0),
	Color3.fromRGB(100,180,255), Color3.fromRGB(150,200,255),
	Color3.fromRGB(255,150,200), Color3.fromRGB(200,80,80),
	Color3.fromRGB(180,100,60),  Color3.fromRGB(255,80,80),
}

local ISLAND_COLORS = islandColors

local ISLAND_POS = {
	{x=0,    y=50,    z=0},   {x=120,  y=600,   z=60},   {x=-160, y=1400,  z=100},
	{x=180,  y=2500,  z=-120}, {x=-200, y=4000,  z=160},  {x=220,  y=6000,  z=-180},
	{x=-240, y=8500,  z=200},  {x=260,  y=11500, z=-220}, {x=-280, y=15000, z=240},
	{x=300,  y=19000, z=-260}, {x=-320, y=24000, z=280},  {x=340,  y=30000, z=-300},
	{x=-360, y=37000, z=320},  {x=380,  y=45000, z=-340},
}

local islandEmojis = {
	"\xF0\x9F\xAB\x98","\xF0\x9F\xA5\xA6","\xF0\x9F\xA5\xAC","\xF0\x9F\x8C\xBF",
	"\xF0\x9F\xA5\xA5","\xF0\x9F\x8D\x9E","\xF0\x9F\x8D\x9D","\xF0\x9F\x8D\xBF",
	"\xF0\x9F\xA5\x9B","\xF0\x9F\xA7\x88","\xF0\x9F\x8D\xA6","\xF0\x9F\x8D\x94",
	"\xF0\x9F\x8C\xAF","\xF0\x9F\x8D\x95"
}

local foodEmojis = {
	Beans="\xF0\x9F\xAB\x98", Broccoli="\xF0\x9F\xA5\xA6", Cabbage="\xF0\x9F\xA5\xAC",
	Turnips="\xF0\x9F\x8C\xBF", Coconuts="\xF0\x9F\xA5\xA5", Bread="\xF0\x9F\x8D\x9E",
	Pasta="\xF0\x9F\x8D\x9D", Popcorn="\xF0\x9F\x8D\xBF", Milk="\xF0\x9F\xA5\x9B",
	Butter="\xF0\x9F\xA7\x88", IceCream="\xF0\x9F\x8D\xA6", Burger="\xF0\x9F\x8D\x94",
	Burrito="\xF0\x9F\x8C\xAF", Pizza="\xF0\x9F\x8D\x95"
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

local RING_COLORS = {Color3.fromRGB(255,215,0), Color3.fromRGB(0,200,255), Color3.fromRGB(255,100,200)}

local windZoneData = {}
local turbZoneData = {}
for i = 1, 13 do
	local y1, y2 = ISLAND_POS[i].y, ISLAND_POS[i+1].y
	local gap = y2 - y1
	windZoneData[i] = {yMin=y1+gap*0.15, yMax=y1+gap*0.65}
	turbZoneData[i] = {yMin=y1+gap*0.70, yMax=y1+gap*0.95}
end

-- ===== GUI HELPERS =====
local function mkCorner(p, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p, col, t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p, props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p, props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p, props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

-- ===== GUI 1: GAS METER =====
local GasMeterGui = Instance.new("ScreenGui"); GasMeterGui.Name="GasMeterGui"; GasMeterGui.ResetOnSpawn=false; GasMeterGui.Parent=PlayerGui
local gmFrame = mkFrame(GasMeterGui, {Size=UDim2.new(0,400,0,50), Position=UDim2.new(0.5,0,1,-73), AnchorPoint=Vector2.new(0.5,1), BackgroundTransparency=1})
local gmLabel = mkLabel(gmFrame, {Text="\xF0\x9F\x92\xA8 GAS METER", Font=Enum.Font.Gotham, TextSize=13, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0,20), Position=UDim2.new(0,0,0,0), RichText=true})
mkStroke(gmLabel, Color3.new(0,0,0), 2)
local gasBg = mkFrame(gmFrame, {Size=UDim2.new(1,0,0,30), Position=UDim2.new(0,0,0,20), BackgroundColor3=Color3.fromRGB(60,60,60)})
mkCorner(gasBg, 20)
local gasMeterStroke = mkStroke(gasBg, Color3.fromRGB(0,200,50), 3)
local gasFill = mkFrame(gasBg, {Name="Fill", Size=UDim2.new(1,0,1,0), BackgroundColor3=Color3.fromRGB(0,200,50), ZIndex=2})
mkCorner(gasFill, 20)
local gasPowerText = mkLabel(gasBg, {Size=UDim2.new(1,0,1,0), Text="GAS: 100%", Font=Enum.Font.GothamBold, TextSize=14, TextColor3=Color3.new(1,1,1), ZIndex=3})
mkStroke(gasPowerText, Color3.new(0,0,0), 1.5)
local flyingLabel = mkLabel(GasMeterGui, {Text="", Font=Enum.Font.Gotham, TextSize=11, TextColor3=Color3.fromRGB(160,160,160), Size=UDim2.new(0,400,0,16), Position=UDim2.new(0.5,0,1,-122), AnchorPoint=Vector2.new(0.5,1), TextXAlignment=Enum.TextXAlignment.Center})

-- ===== GUI 2: FART BUTTON =====
local FartButtonGui = Instance.new("ScreenGui"); FartButtonGui.Name="FartButtonGui"; FartButtonGui.ResetOnSpawn=false; FartButtonGui.Parent=PlayerGui
local fartBtnFrame = mkFrame(FartButtonGui, {Position=UDim2.new(0.5,0,1,-15), Size=UDim2.new(0,240,0,50), BackgroundColor3=Color3.fromRGB(120,120,120), AnchorPoint=Vector2.new(0.5,1)})
mkCorner(fartBtnFrame, 12); mkStroke(fartBtnFrame, Color3.fromRGB(80,80,80), 3)
local fartBtn = mkButton(fartBtnFrame, {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="\xF0\x9F\x92\xA8 BUY FOOD FIRST!", Font=Enum.Font.Gotham, TextSize=17, TextColor3=Color3.new(1,1,1), RichText=true})
mkStroke(fartBtn, Color3.new(0,0,0), 2)

-- ===== GUI 3: COIN DISPLAY =====
local CoinGui = Instance.new("ScreenGui"); CoinGui.Name="CoinGui"; CoinGui.ResetOnSpawn=false; CoinGui.Parent=PlayerGui
local coinPill = mkFrame(CoinGui, {Position=UDim2.new(1,-10,0,10), Size=UDim2.new(0,210,0,44), BackgroundColor3=Color3.fromRGB(255,200,0), AnchorPoint=Vector2.new(1,0)})
mkCorner(coinPill, 25); mkStroke(coinPill, Color3.fromRGB(200,140,0), 3)
mkLabel(coinPill, {Text="\xF0\x9F\xAA\x99", Font=Enum.Font.Gotham, Size=UDim2.new(0,40,0,40), Position=UDim2.new(0,5,0,5), TextSize=28, RichText=true, BackgroundTransparency=1})
local coinAmount = mkLabel(coinPill, {Name="Amount", Text="0", Font=Enum.Font.GothamBold, TextSize=24, TextColor3=Color3.fromRGB(100,50,0), Size=UDim2.new(1,-55,1,0), Position=UDim2.new(0,50,0,0), TextXAlignment=Enum.TextXAlignment.Left})
mkStroke(coinAmount, Color3.new(1,1,1), 1.5)
local cpsLabel = mkLabel(CoinGui, {Name="CPS", Text="", Font=Enum.Font.Gotham, TextSize=13, TextColor3=Color3.fromRGB(50,150,0), Position=UDim2.new(1,-10,0,65), Size=UDim2.new(0,210,0,20), AnchorPoint=Vector2.new(1,0), TextXAlignment=Enum.TextXAlignment.Right, Visible=false})

-- ===== GUI 4: STATS PANEL =====
local StatsGui = Instance.new("ScreenGui"); StatsGui.Name="StatsGui"; StatsGui.ResetOnSpawn=false; StatsGui.Parent=PlayerGui
local statsPanel = mkFrame(StatsGui, {Position=UDim2.new(1,-10,0,62), Size=UDim2.new(0,210,0,90), BackgroundColor3=Color3.fromRGB(255,255,255), AnchorPoint=Vector2.new(1,0)})
mkCorner(statsPanel, 12); mkStroke(statsPanel, Color3.fromRGB(200,200,200), 2)
mkLabel(statsPanel, {Text="\xF0\x9F\x93\x8A STATS", Font=Enum.Font.Gotham, TextSize=16, TextColor3=Color3.fromRGB(50,50,50), Size=UDim2.new(1,-10,0,25), Position=UDim2.new(0,5,0,5), RichText=true, TextXAlignment=Enum.TextXAlignment.Left})
local lbIsland    = mkLabel(statsPanel, {Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F Island: 1", Font=Enum.Font.Gotham, TextSize=14, TextColor3=Color3.fromRGB(80,80,80), Size=UDim2.new(1,-10,0,20), Position=UDim2.new(0,5,0,30), RichText=true, TextXAlignment=Enum.TextXAlignment.Left})
local lbMaxHeight = mkLabel(statsPanel, {Text="\xF0\x9F\x9A\x80 Max H: 50", Font=Enum.Font.Gotham, TextSize=14, TextColor3=Color3.fromRGB(80,80,80), Size=UDim2.new(1,-10,0,20), Position=UDim2.new(0,5,0,50), RichText=true, TextXAlignment=Enum.TextXAlignment.Left})
local lbEarned    = mkLabel(statsPanel, {Text="\xF0\x9F\xAA\x99 Earned: 0", Font=Enum.Font.Gotham, TextSize=14, TextColor3=Color3.fromRGB(80,80,80), Size=UDim2.new(1,-10,0,20), Position=UDim2.new(0,5,0,70), RichText=true, TextXAlignment=Enum.TextXAlignment.Left})

-- ===== GUI 5: ARRIVAL BANNER (FIX 1) =====
local ArrivalGui = Instance.new("ScreenGui"); ArrivalGui.Name="ArrivalGui"; ArrivalGui.ResetOnSpawn=false; ArrivalGui.Parent=PlayerGui
local arrivalFrame = mkFrame(ArrivalGui, {Size=UDim2.new(0,420,0,70), Position=UDim2.new(0.5,0,0,10), AnchorPoint=Vector2.new(0.5,0), BackgroundColor3=Color3.fromRGB(100,200,100), Visible=false})
mkCorner(arrivalFrame, 16); mkStroke(arrivalFrame, Color3.new(1,1,1), 3)
local arrivalLine1 = mkLabel(arrivalFrame, {Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F Welcome to", Font=Enum.Font.Gotham, TextSize=16, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,-10,0,26), Position=UDim2.new(0,5,0,6), TextXAlignment=Enum.TextXAlignment.Center, RichText=true})
mkStroke(arrivalLine1, Color3.new(0,0,0), 1)
local islandLabel = mkLabel(arrivalFrame, {Text="Bean Farm!", Font=Enum.Font.GothamBold, TextSize=26, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,-10,0,34), Position=UDim2.new(0,5,0,33), TextXAlignment=Enum.TextXAlignment.Center})
mkStroke(islandLabel, Color3.new(0,0,0), 2)

-- ===== GUI 6: ANNOUNCEMENT BANNER =====
local AnnounceGui = Instance.new("ScreenGui"); AnnounceGui.Name="AnnounceGui"; AnnounceGui.ResetOnSpawn=false; AnnounceGui.Parent=PlayerGui
local announceFrame = mkFrame(AnnounceGui, {Size=UDim2.new(0,420,0,40), Position=UDim2.new(0.5,0,0,-44), AnchorPoint=Vector2.new(0.5,0), BackgroundColor3=Color3.fromRGB(255,200,0)})
mkCorner(announceFrame, 20); mkStroke(announceFrame, Color3.fromRGB(200,150,0), 2)
local announceBanner = mkLabel(announceFrame, {Text="", Font=Enum.Font.GothamBold, TextSize=15, TextColor3=Color3.fromRGB(80,40,0), Size=UDim2.new(1,-20,1,0), Position=UDim2.new(0,10,0,0), TextXAlignment=Enum.TextXAlignment.Center})

-- ===== GUI 7: SERVER EVENT BANNER =====
local ServerEventGui = Instance.new("ScreenGui"); ServerEventGui.Name="ServerEventGui"; ServerEventGui.ResetOnSpawn=false; ServerEventGui.Parent=PlayerGui
local seBannerFrame = mkFrame(ServerEventGui, {Size=UDim2.new(0,500,0,80), Position=UDim2.new(0.5,0,0,-90), AnchorPoint=Vector2.new(0.5,0), BackgroundColor3=Color3.fromRGB(100,200,255)})
mkCorner(seBannerFrame, 20); mkStroke(seBannerFrame, Color3.new(1,1,1), 3)
local seBannerLine1 = mkLabel(seBannerFrame, {Text="\xE2\x9A\xA0 SERVER EVENT!", Font=Enum.Font.GothamBold, TextSize=16, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,-10,0,30), Position=UDim2.new(0,5,0,5), TextXAlignment=Enum.TextXAlignment.Center})
mkStroke(seBannerLine1, Color3.new(0,0,0), 1.5)
local seBannerLine2 = mkLabel(seBannerFrame, {Text="", Font=Enum.Font.GothamBold, TextSize=18, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,-10,0,36), Position=UDim2.new(0,5,0,38), TextXAlignment=Enum.TextXAlignment.Center, TextWrapped=true})
mkStroke(seBannerLine2, Color3.new(0,0,0), 1.5)

-- ===== GUI 8: SERVER EVENT COUNTDOWN =====
local seCountGui = Instance.new("ScreenGui"); seCountGui.Name="SeCountGui"; seCountGui.ResetOnSpawn=false; seCountGui.Parent=PlayerGui
local seCountFrame = mkFrame(seCountGui, {Size=UDim2.new(0,200,0,32), Position=UDim2.new(0.5,0,0,224), AnchorPoint=Vector2.new(0.5,0), BackgroundColor3=Color3.fromRGB(50,50,50), Visible=false})
mkCorner(seCountFrame, 16); mkStroke(seCountFrame, Color3.fromRGB(200,200,200), 2)
local seCountLabel = mkLabel(seCountFrame, {Text="", Font=Enum.Font.GothamBold, TextSize=13, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,-10,1,0), Position=UDim2.new(0,5,0,0), TextXAlignment=Enum.TextXAlignment.Center})

-- ===== GUI 9: WIND / TURB INDICATOR =====
local WindGui = Instance.new("ScreenGui"); WindGui.Name="WindGui"; WindGui.ResetOnSpawn=false; WindGui.Parent=PlayerGui
local windIndicatorFrame = mkFrame(WindGui, {Size=UDim2.new(0,140,0,36), Position=UDim2.new(0.5,0,0.35,0), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=Color3.fromRGB(100,150,255), BackgroundTransparency=0.3, Visible=false})
mkCorner(windIndicatorFrame, 18)
local windIndicatorLabel = mkLabel(windIndicatorFrame, {Text="\xF0\x9F\x92\xA8 Wind \xe2\x86\x92", Font=Enum.Font.Gotham, TextSize=14, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,-10,1,0), Position=UDim2.new(0,5,0,0), TextXAlignment=Enum.TextXAlignment.Center})

-- ===== GUI 10: FLIGHT STATS =====
local FlightStatsGui = Instance.new("ScreenGui"); FlightStatsGui.Name="FlightStatsGui"; FlightStatsGui.ResetOnSpawn=false; FlightStatsGui.Parent=PlayerGui
local flightStatsFrame = mkFrame(FlightStatsGui, {Size=UDim2.new(0,160,0,100), Position=UDim2.new(0,90,1,-180), AnchorPoint=Vector2.new(0,1), BackgroundColor3=Color3.new(1,1,1), BackgroundTransparency=0.15, Visible=false})
mkCorner(flightStatsFrame, 10)
local fsHeight = mkLabel(flightStatsFrame, {Text="\xF0\x9F\x93\x8F Height: 0", Font=Enum.Font.Gotham, TextSize=13, TextColor3=Color3.fromRGB(30,30,30), Size=UDim2.new(1,-10,0,28), Position=UDim2.new(0,5,0,5), TextXAlignment=Enum.TextXAlignment.Left})
local fsRings  = mkLabel(flightStatsFrame, {Text="\xF0\x9F\x92\x8D Rings: 0 (x1.0)", Font=Enum.Font.Gotham, TextSize=13, TextColor3=Color3.fromRGB(30,30,30), Size=UDim2.new(1,-10,0,28), Position=UDim2.new(0,5,0,36), TextXAlignment=Enum.TextXAlignment.Left})
local fsAir    = mkLabel(flightStatsFrame, {Text="\xE2\x8F\xB1 Air: 0s", Font=Enum.Font.Gotham, TextSize=13, TextColor3=Color3.fromRGB(30,30,30), Size=UDim2.new(1,-10,0,28), Position=UDim2.new(0,5,0,67), TextXAlignment=Enum.TextXAlignment.Left})

-- ===== GUI 11: EFFECT FLASH =====
local FlashGui = Instance.new("ScreenGui"); FlashGui.Name="FlashGui"; FlashGui.ResetOnSpawn=false; FlashGui.ZIndexBehavior=Enum.ZIndexBehavior.Global; FlashGui.Parent=PlayerGui
local effectFlashFrame = mkFrame(FlashGui, {Size=UDim2.new(1,0,1,0), BackgroundColor3=Color3.new(1,1,1), BackgroundTransparency=1, ZIndex=10})

-- ===== GUI 12: SIDEBAR =====
local SidebarGui = Instance.new("ScreenGui"); SidebarGui.Name="SidebarGui"; SidebarGui.ResetOnSpawn=false; SidebarGui.Parent=PlayerGui
local shopBtn = mkButton(SidebarGui, {Size=UDim2.new(0,70,0,70), Position=UDim2.new(0,10,0.5,-90), AnchorPoint=Vector2.new(0,0.5), BackgroundColor3=Color3.fromRGB(255,140,0), Text=""})
mkCorner(shopBtn,14); mkStroke(shopBtn, Color3.fromRGB(200,100,0), 3)
mkLabel(shopBtn, {Text="\xF0\x9F\x9B\x92", Font=Enum.Font.Gotham, TextSize=32, Size=UDim2.new(1,0,0.65,0), RichText=true})
mkLabel(shopBtn, {Text="Shop", Font=Enum.Font.GothamBold, TextSize=13, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0.35,0), Position=UDim2.new(0,0,0.65,0)})
local inviteBtn = mkButton(SidebarGui, {Size=UDim2.new(0,70,0,70), Position=UDim2.new(0,10,0.5,0), AnchorPoint=Vector2.new(0,0.5), BackgroundColor3=Color3.fromRGB(140,80,220), Text=""})
mkCorner(inviteBtn,14); mkStroke(inviteBtn, Color3.fromRGB(100,50,180), 3)
mkLabel(inviteBtn, {Text="\xF0\x9F\x91\xA5", Font=Enum.Font.Gotham, TextSize=32, Size=UDim2.new(1,0,0.65,0), RichText=true})
mkLabel(inviteBtn, {Text="Invite", Font=Enum.Font.GothamBold, TextSize=13, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0.35,0), Position=UDim2.new(0,0,0.65,0)})

-- ===== GUI 13: FOOD STAND SHOP =====
local FoodShopGui = Instance.new("ScreenGui"); FoodShopGui.Name="FoodShopGui"; FoodShopGui.ResetOnSpawn=false; FoodShopGui.Enabled=false; FoodShopGui.Parent=PlayerGui
mkFrame(FoodShopGui, {Size=UDim2.new(1,0,1,0), BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=0.4})
local foodPanel = mkFrame(FoodShopGui, {Size=UDim2.new(0,680,0,480), Position=UDim2.new(0.5,0,0.5,0), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=Color3.fromRGB(240,248,255)})
mkCorner(foodPanel,16); mkStroke(foodPanel, Color3.fromRGB(100,180,255), 4)
local foodHeader = mkFrame(foodPanel, {Size=UDim2.new(1,0,0,55), BackgroundColor3=Color3.fromRGB(80,160,255)})
mkCorner(foodHeader,16)
local foodTitle = mkLabel(foodHeader, {Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F ISLAND 1 FOOD STAND", Font=Enum.Font.Gotham, TextSize=24, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,-60,1,0), RichText=true})
mkStroke(foodTitle, Color3.new(0,0,0), 2)
local foodCloseBtn = mkButton(foodHeader, {Size=UDim2.new(0,40,0,40), Position=UDim2.new(1,-45,0,7), BackgroundColor3=Color3.fromRGB(255,60,60), Text="X", Font=Enum.Font.GothamBold, TextSize=20, TextColor3=Color3.new(1,1,1)})
mkCorner(foodCloseBtn,8)
local foodLeftPanel = mkFrame(foodPanel, {Size=UDim2.new(0,280,1,-65), Position=UDim2.new(0,10,0,65), BackgroundColor3=Color3.new(1,1,1)})
mkCorner(foodLeftPanel,12)
local foodEmoji  = mkLabel(foodLeftPanel, {Text="\xF0\x9F\xAB\x98", Font=Enum.Font.Gotham, TextSize=80, Size=UDim2.new(0,120,0,120), Position=UDim2.new(0.5,-60,0,10), RichText=true})
local foodName   = mkLabel(foodLeftPanel, {Text="Beans", Font=Enum.Font.GothamBold, TextSize=26, TextColor3=Color3.fromRGB(30,30,30), Size=UDim2.new(1,-10,0,35), Position=UDim2.new(0,5,0,135), TextXAlignment=Enum.TextXAlignment.Center})
local foodPrice  = mkLabel(foodLeftPanel, {Text="\xF0\x9F\xAA\x99 10 coins", Font=Enum.Font.Gotham, TextSize=20, TextColor3=Color3.fromRGB(200,140,0), Size=UDim2.new(1,-10,0,28), Position=UDim2.new(0,5,0,174), RichText=true, TextXAlignment=Enum.TextXAlignment.Center})
local foodPower  = mkLabel(foodLeftPanel, {Text="+3 power", Font=Enum.Font.GothamBold, TextSize=18, TextColor3=Color3.fromRGB(0,160,60), Size=UDim2.new(1,-10,0,26), Position=UDim2.new(0,5,0,206), TextXAlignment=Enum.TextXAlignment.Center})
local foodBuyBtn = mkButton(foodLeftPanel, {Size=UDim2.new(0.85,0,0,55), Position=UDim2.new(0.075,0,1,-65), BackgroundColor3=Color3.fromRGB(50,200,50), Text="BUY FOOD", Font=Enum.Font.GothamBold, TextSize=22, TextColor3=Color3.new(1,1,1)})
mkCorner(foodBuyBtn,12)
local foodLockedFrame = mkFrame(foodLeftPanel, {Size=UDim2.new(1,0,1,0), BackgroundColor3=Color3.fromRGB(240,240,240), Visible=false})
mkCorner(foodLockedFrame, 12)
mkLabel(foodLockedFrame, {Text="\xF0\x9F\x94\x92", Font=Enum.Font.Gotham, TextSize=64, Size=UDim2.new(0,100,0,100), Position=UDim2.new(0.5,-50,0,40), RichText=true})
mkLabel(foodLockedFrame, {Text="Fly here to unlock!", Font=Enum.Font.GothamBold, TextSize=20, TextColor3=Color3.fromRGB(200,0,0), Size=UDim2.new(1,-20,0,60), Position=UDim2.new(0,10,0,155), TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Center})
local foodRight = mkFrame(foodPanel, {Size=UDim2.new(1,-300,1,-65), Position=UDim2.new(0,300,0,65), BackgroundColor3=Color3.fromRGB(248,248,248)})
mkCorner(foodRight,12)
mkLabel(foodRight, {Text="ALL FOODS", Font=Enum.Font.GothamBold, TextSize=18, TextColor3=Color3.fromRGB(50,50,50), Size=UDim2.new(1,-10,0,25), Position=UDim2.new(0,5,0,5)})
local foodScroll = Instance.new("ScrollingFrame"); foodScroll.Size=UDim2.new(1,-10,1,-35); foodScroll.Position=UDim2.new(0,5,0,30); foodScroll.BackgroundTransparency=1; foodScroll.ScrollBarThickness=6; foodScroll.CanvasSize=UDim2.new(0,0,0,0); foodScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; foodScroll.Parent=foodRight
local foodGrid = Instance.new("UIGridLayout"); foodGrid.CellSize=UDim2.new(0,155,0,70); foodGrid.CellPadding=UDim2.new(0,6,0,6); foodGrid.Parent=foodScroll
local foodCells = {}
for _, f in ipairs(foods) do
	local cell = mkFrame(foodScroll, {Name=f.name, BackgroundColor3=Color3.fromRGB(200,240,200)}); mkCorner(cell,8); mkStroke(cell, Color3.fromRGB(150,200,150), 2)
	mkLabel(cell, {Text=foodEmojis[f.name] or "?", Font=Enum.Font.Gotham, TextSize=28, Size=UDim2.new(0,40,1,0), Position=UDim2.new(0,2,0,0), RichText=true})
	mkLabel(cell, {Text=f.name, Font=Enum.Font.GothamBold, TextSize=13, TextColor3=Color3.fromRGB(30,30,30), Size=UDim2.new(1,-46,0,30), Position=UDim2.new(0,44,0,5), TextXAlignment=Enum.TextXAlignment.Left})
	mkLabel(cell, {Text="\xF0\x9F\xAA\x99 "..f.price, Font=Enum.Font.Gotham, TextSize=12, TextColor3=Color3.fromRGB(120,80,0), Size=UDim2.new(1,-46,0,20), Position=UDim2.new(0,44,0,38), TextXAlignment=Enum.TextXAlignment.Left, RichText=true})
	foodCells[f.name] = cell
end

-- ===== GUI 14: PREMIUM SHOP =====
local PremiumShopGui = Instance.new("ScreenGui"); PremiumShopGui.Name="PremiumShopGui"; PremiumShopGui.ResetOnSpawn=false; PremiumShopGui.Enabled=false; PremiumShopGui.Parent=PlayerGui
mkFrame(PremiumShopGui, {Size=UDim2.new(1,0,1,0), BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=0.5})
local premPanel = mkFrame(PremiumShopGui, {Size=UDim2.new(0,700,0,600), Position=UDim2.new(0.5,0,0.5,0), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=Color3.fromRGB(255,248,200)})
mkCorner(premPanel,16); mkStroke(premPanel, Color3.fromRGB(255,200,0), 4)
local premHeader = mkFrame(premPanel, {Size=UDim2.new(1,0,0,60), BackgroundColor3=Color3.fromRGB(255,200,0)}); mkCorner(premHeader,16)
local premTitle = mkLabel(premHeader, {Text="SHOP", Font=Enum.Font.GothamBold, TextSize=28, TextColor3=Color3.fromRGB(100,50,0), Size=UDim2.new(1,-60,1,0)})
mkStroke(premTitle, Color3.new(1,1,1), 2)
local premClose = mkButton(premHeader, {Size=UDim2.new(0,40,0,40), Position=UDim2.new(1,-45,0,10), BackgroundColor3=Color3.fromRGB(255,60,60), Text="X", Font=Enum.Font.GothamBold, TextSize=20, TextColor3=Color3.new(1,1,1)}); mkCorner(premClose,8)
mkLabel(premPanel, {Text="GAMEPASSES", Font=Enum.Font.GothamBold, TextSize=16, TextColor3=Color3.fromRGB(80,80,80), Size=UDim2.new(1,-20,0,24), Position=UDim2.new(0,10,0,68), TextXAlignment=Enum.TextXAlignment.Left, BackgroundTransparency=1})
local function mkCard(parent, xPos, yPos, icon, title, desc, price, btnCol, btnTxt, onClick)
	local card = mkFrame(parent, {Size=UDim2.new(0,200,0,200), Position=UDim2.new(0,xPos,0,yPos), BackgroundColor3=Color3.new(1,1,1)}); mkCorner(card,12); mkStroke(card, Color3.fromRGB(220,220,220), 2)
	mkLabel(card, {Text=icon, Font=Enum.Font.Gotham, TextSize=36, Size=UDim2.new(1,0,0,50), Position=UDim2.new(0,0,0,5), RichText=true})
	mkLabel(card, {Text=title, Font=Enum.Font.GothamBold, TextSize=13, TextColor3=Color3.fromRGB(30,30,30), Size=UDim2.new(1,-10,0,35), Position=UDim2.new(0,5,0,55), TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Center, BackgroundTransparency=1})
	mkLabel(card, {Text=desc, Font=Enum.Font.Gotham, TextSize=12, TextColor3=Color3.fromRGB(120,120,120), Size=UDim2.new(1,-10,0,40), Position=UDim2.new(0,5,0,90), TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Center, BackgroundTransparency=1})
	mkLabel(card, {Text=price, Font=Enum.Font.GothamBold, TextSize=14, TextColor3=Color3.fromRGB(0,150,0), Size=UDim2.new(1,-10,0,18), Position=UDim2.new(0,5,0,132), TextXAlignment=Enum.TextXAlignment.Center, BackgroundTransparency=1})
	local btn = mkButton(card, {Size=UDim2.new(0.85,0,0,28), Position=UDim2.new(0.075,0,1,-35), BackgroundColor3=btnCol, Text=btnTxt, Font=Enum.Font.GothamBold, TextSize=13, TextColor3=Color3.new(1,1,1)}); mkCorner(btn,8); btn.MouseButton1Click:Connect(onClick)
end
mkCard(premPanel,25,98,"PWR","2x Power FOREVER","Double fart power!","249 R$",Color3.fromRGB(255,180,0),"BUY",function() pcall(function() MarketplaceService:PromptGamePassPurchase(player,0) end) end)
mkCard(premPanel,250,98,"GLTR","Glitter Trail","Sparkling trail!","49 R$",Color3.fromRGB(220,80,180),"BUY",function() pcall(function() MarketplaceService:PromptGamePassPurchase(player,0) end) end)
mkCard(premPanel,475,98,"CLR","Custom Color","Your own colour!","89 R$",Color3.fromRGB(140,80,220),"BUY",function() pcall(function() MarketplaceService:PromptGamePassPurchase(player,0) end) end)
mkLabel(premPanel, {Text="ONE-TIME ITEMS", Font=Enum.Font.GothamBold, TextSize=16, TextColor3=Color3.fromRGB(80,80,80), Size=UDim2.new(1,-20,0,24), Position=UDim2.new(0,10,0,308), TextXAlignment=Enum.TextXAlignment.Left, BackgroundTransparency=1})
mkCard(premPanel,25,335,"2XHR","2x Power 1 Hour","Double power 60 min!","59 R$",Color3.fromRGB(50,120,255),"BUY",function() pcall(function() MarketplaceService:PromptProductPurchase(player,0) end) end)
mkCard(premPanel,250,335,"RCHG","Mid-Air Recharge","Refill gas instantly!","39 R$",Color3.fromRGB(50,200,50),"BUY",function() pcall(function() MarketplaceService:PromptProductPurchase(player,0) end) end)
mkCard(premPanel,475,335,"SKIP","Skip Island","Unlock next island!","69 R$",Color3.fromRGB(255,140,0),"BUY",function() pcall(function() MarketplaceService:PromptProductPurchase(player,0) end) end)

-- ===== GUI 15: HOTBAR =====
local HotbarGui = Instance.new("ScreenGui"); HotbarGui.Name="HotbarGui"; HotbarGui.ResetOnSpawn=false; HotbarGui.Parent=PlayerGui
local hotbarFrame = mkFrame(HotbarGui, {Position=UDim2.new(1,-10,1,-80), Size=UDim2.new(0,140,0,60), AnchorPoint=Vector2.new(1,1), BackgroundTransparency=1, Visible=false})
local hbLayout = Instance.new("UIListLayout"); hbLayout.FillDirection=Enum.FillDirection.Horizontal; hbLayout.Padding=UDim.new(0,5); hbLayout.Parent=hotbarFrame
local rechargeSlot = mkButton(hotbarFrame, {Size=UDim2.new(0,60,0,60), BackgroundColor3=Color3.fromRGB(50,50,50), BackgroundTransparency=0.3, Text="RCHRG", TextSize=11, Font=Enum.Font.GothamBold, TextColor3=Color3.new(1,1,1)})
mkCorner(rechargeSlot,10); mkStroke(rechargeSlot, Color3.fromRGB(100,100,100), 2)
local rechargeBadge = mkLabel(rechargeSlot, {Text="0", Font=Enum.Font.GothamBold, TextSize=12, TextColor3=Color3.new(1,1,1), Size=UDim2.new(0,20,0,20), Position=UDim2.new(1,-20,1,-20), BackgroundColor3=Color3.fromRGB(255,60,60)}); mkCorner(rechargeBadge,10)
local skipSlot = mkButton(hotbarFrame, {Size=UDim2.new(0,60,0,60), BackgroundColor3=Color3.fromRGB(50,50,50), BackgroundTransparency=0.3, Text="SKIP", TextSize=13, Font=Enum.Font.GothamBold, TextColor3=Color3.new(1,1,1)})
mkCorner(skipSlot,10); mkStroke(skipSlot, Color3.fromRGB(100,100,100), 2)
local skipBadge = mkLabel(skipSlot, {Text="0", Font=Enum.Font.GothamBold, TextSize=12, TextColor3=Color3.new(1,1,1), Size=UDim2.new(0,20,0,20), Position=UDim2.new(1,-20,1,-20), BackgroundColor3=Color3.fromRGB(255,60,60)}); mkCorner(skipBadge,10)

-- ===== GUI 16: NAVIGATION ARROW =====
local NavGui = Instance.new("ScreenGui"); NavGui.Name="NavGui"; NavGui.ResetOnSpawn=false; NavGui.Parent=PlayerGui
local navFrame = mkFrame(NavGui, {Size=UDim2.new(0,44,0,44), Position=UDim2.new(0.5,0,0.5,0), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=Color3.fromRGB(255,200,0), BackgroundTransparency=0.2, Visible=false})
mkCorner(navFrame, 22); mkStroke(navFrame, Color3.fromRGB(200,140,0), 2)
local navArrow = mkLabel(navFrame, {Text="\xe2\x86\x91", Font=Enum.Font.GothamBold, TextSize=26, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,1,0), TextXAlignment=Enum.TextXAlignment.Center})
mkStroke(navArrow, Color3.new(0,0,0), 1.5)
local navName = mkLabel(NavGui, {Text="", Font=Enum.Font.Gotham, TextSize=11, TextColor3=Color3.new(1,1,1), Size=UDim2.new(0,120,0,16), AnchorPoint=Vector2.new(0.5,0), TextXAlignment=Enum.TextXAlignment.Center, Visible=false})
mkStroke(navName, Color3.new(0,0,0), 1)

-- ===== GUI 17: STORM OVERLAY =====
local StormGui = Instance.new("ScreenGui"); StormGui.Name="StormGui"; StormGui.ResetOnSpawn=false; StormGui.ZIndexBehavior=Enum.ZIndexBehavior.Global; StormGui.Parent=PlayerGui
local stormOverlay = mkFrame(StormGui, {Size=UDim2.new(1,0,1,0), BackgroundColor3=Color3.fromRGB(20,20,40), BackgroundTransparency=1, ZIndex=5})
local lightningFlash = mkFrame(StormGui, {Size=UDim2.new(1,0,1,0), BackgroundColor3=Color3.new(1,1,1), BackgroundTransparency=1, ZIndex=6})

-- ===== GUI 18: WIND STORM ARROW =====
local WindStormGui = Instance.new("ScreenGui"); WindStormGui.Name="WindStormGui"; WindStormGui.ResetOnSpawn=false; WindStormGui.Parent=PlayerGui
local windStormFrame = mkFrame(WindStormGui, {Size=UDim2.new(0,200,0,50), Position=UDim2.new(0.5,0,0.5,-25), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=Color3.fromRGB(100,150,200), BackgroundTransparency=1, Visible=false})
mkCorner(windStormFrame, 12); mkStroke(windStormFrame, Color3.fromRGB(80,120,180), 2)
local windStormLabel = mkLabel(windStormFrame, {Text="\xF0\x9F\x92\xA8 WIND STORM!", Font=Enum.Font.GothamBold, TextSize=18, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,-10,1,0), Position=UDim2.new(0,5,0,0), TextXAlignment=Enum.TextXAlignment.Center})
mkStroke(windStormLabel, Color3.new(0,0,0), 1.5)

print("GUIS BUILT")

-- ===== WORLD OBJECT SPAWNING =====
local function makeBillboard(parent, text, textColor, textSize)
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,120,0,30); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=false; bb.Parent=parent
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=textSize or 13; lbl.TextColor3=textColor or Color3.new(1,1,1); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	return bb, lbl
end

local ringDataStore = {}

local function spawnRing(pos, color, dataIndex, dirVec)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(1, 25, 25)
	-- Orient so cylinder axis (X) faces travel direction
	local dir = (dirVec and dirVec.Magnitude > 0) and dirVec.Unit or Vector3.new(0,1,0)
	local worldUp = math.abs(dir.Y) < 0.9 and Vector3.new(0,1,0) or Vector3.new(1,0,0)
	local yAxis = worldUp - dir * dir:Dot(worldUp)
	yAxis = yAxis.Magnitude > 0.001 and yAxis.Unit or Vector3.new(0,0,1)
	local zAxis = dir:Cross(yAxis).Unit
	ring.CFrame = CFrame.fromMatrix(pos, dir, yAxis, zAxis)
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.CanCollide = false
	ring.Anchored = true
	ring.Transparency = 0.3
	ring.CastShadow = false
	ring.Parent = workspace
	makeBillboard(ring, "\xF0\x9F\xAA\x99 +BONUS", Color3.new(1,1,1), 14)
	local entry = {part=ring, pos=pos, color=color, idx=dataIndex, dir=dirVec}
	table.insert(activeRings, entry)
	if dataIndex then ringDataStore[dataIndex] = entry end
end

local function spawnLandingPad(i)
	local padPos = nil
	local iname = ISLAND_NAMES[i]
	local model = workspace:FindFirstChild(iname)
	if model then
		for _, obj in ipairs(model:GetDescendants()) do
			if obj:IsA("ProximityPrompt") and obj.ObjectText == "Stand" then
				local part = obj.Parent
				if part and not part:IsA("BasePart") then
					part = part:FindFirstChildWhichIsA("BasePart") or (part.Parent and part.Parent:IsA("BasePart") and part.Parent)
				end
				if part and part:IsA("BasePart") then
					padPos = part.Position + part.CFrame.LookVector * 5 + Vector3.new(0, -part.Size.Y/2 + 0.25, 0)
				end
				break
			end
		end
		if not padPos then
			local bbCF, bbSize
			local ok = pcall(function() bbCF, bbSize = model:GetBoundingBox() end)
			if ok and bbCF and bbSize then
				padPos = bbCF.Position + Vector3.new(0, -bbSize.Y/2 + 0.5, 0)
			end
		end
	end
	if not padPos then
		local pos = ISLAND_POS[i]
		padPos = Vector3.new(pos.x, pos.y + 1, pos.z)
	end
	local pad = Instance.new("Part")
	pad.Size = Vector3.new(8, 0.5, 8)
	pad.Color = Color3.fromRGB(255,200,0)
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.3
	pad.Anchored = true
	pad.CanCollide = true
	pad.CastShadow = false
	pad.Position = padPos
	pad.Parent = workspace
	makeBillboard(pad, "\xF0\x9F\x8E\xAF Land Here!", Color3.fromRGB(255,220,0), 13)
	table.insert(landingPads, pad)
end

local function startGasPocketPulse(part)
	local function doPulse()
		if not part.Parent then return end
		local t1 = TweenService:Create(part, TweenInfo.new(1, Enum.EasingStyle.Sine), {Size=Vector3.new(17,17,17)})
		t1:Play()
		t1.Completed:Connect(function()
			if not part.Parent then return end
			local t2 = TweenService:Create(part, TweenInfo.new(1, Enum.EasingStyle.Sine), {Size=Vector3.new(13,13,13)})
			t2:Play()
			t2.Completed:Connect(function() doPulse() end)
		end)
	end
	doPulse()
end

local function spawnGasPocket(pos)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(15,15,15)
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(0,255,100)
	p.Transparency = 0.6
	p.CanCollide = false
	p.Anchored = true
	p.CastShadow = false
	p.Position = pos
	p.Parent = workspace
	table.insert(activeGasPockets, p)
	startGasPocketPulse(p)
end

-- ===== BIRD ATTACK =====
local function createBird()
	if #activeBirds >= 3 then return end
	local char = player.Character
	local hrpTarget = char and char:FindFirstChild("HumanoidRootPart"); if not hrpTarget then return end
	local angle = math.random() * math.pi * 2
	local spawnPos = hrpTarget.Position + Vector3.new(math.cos(angle)*50, 0, math.sin(angle)*50)
	local birdModel = Instance.new("Model"); birdModel.Name="Bird"; birdModel.Parent=workspace
	local body = Instance.new("Part"); body.Name="Body"; body.Size=Vector3.new(2,0.5,1)
	body.Color=Color3.fromRGB(50,50,50); body.Material=Enum.Material.SmoothPlastic
	body.CanCollide=false; body.Anchored=false; body.Position=spawnPos; body.Parent=birdModel
	birdModel.PrimaryPart=body
	local birdVel = Instance.new("BodyVelocity"); birdVel.MaxForce=Vector3.new(1e6,1e6,1e6); birdVel.Velocity=Vector3.new(0,0,0); birdVel.Parent=body
	local function makeWing(name, ox)
		local w = Instance.new("Part"); w.Name=name; w.Size=Vector3.new(1.5,0.1,0.5)
		w.Color=Color3.fromRGB(50,50,50); w.Material=Enum.Material.SmoothPlastic; w.CanCollide=false; w.Parent=birdModel
		local weld = Instance.new("Weld"); weld.Part0=body; weld.Part1=w; weld.C0=CFrame.new(ox,0,0); weld.Parent=body
		return weld
	end
	local weld1 = makeWing("Wing1", -1.5)
	local weld2 = makeWing("Wing2", 1.5)
	local entry = {model=birdModel, body=body}
	table.insert(activeBirds, entry)
	task.spawn(function()
		local flapUp = true
		while birdModel.Parent do
			local a = flapUp and 0.5 or -0.3
			pcall(function() weld1.C0=CFrame.new(-1.5,0,0)*CFrame.Angles(0,0,a) end)
			pcall(function() weld2.C0=CFrame.new(1.5,0,0)*CFrame.Angles(0,0,-a) end)
			flapUp = not flapUp; task.wait(0.3)
		end
	end)
	task.spawn(function()
		while birdModel.Parent do
			local c = player.Character; local hrpNow = c and c:FindFirstChild("HumanoidRootPart")
			if not hrpNow then birdModel:Destroy(); break end
			local diff = hrpNow.Position - body.Position
			if diff.Magnitude < 4 then
				birdModel:Destroy()
				cosmeticGas = math.max(0, cosmeticGas * 0.75); updateMeter()
				showFloatingText("\xF0\x9F\x90\xA6 BIRD ATTACK! -25% gas!", Color3.fromRGB(255,80,0))
				effectFlashFrame.BackgroundColor3=Color3.fromRGB(255,80,0); effectFlashFrame.BackgroundTransparency=0.6
				TweenService:Create(effectFlashFrame,TweenInfo.new(0.2),{BackgroundTransparency=0.97}):Play()
				pcall(function()
					local px = math.random(1,2)==1 and math.random(-20,-8) or math.random(8,20)
					local pz = math.random(1,2)==1 and math.random(-20,-8) or math.random(8,20)
					local pushBV = Instance.new("BodyVelocity"); pushBV.MaxForce=Vector3.new(1e6,0,1e6)
					pushBV.Velocity=Vector3.new(px,0,pz); pushBV.Parent=hrpNow
					task.delay(0.3,function() pcall(function() pushBV:Destroy() end) end)
				end)
				break
			elseif diff.Magnitude > 150 then
				birdModel:Destroy(); break
			else
				pcall(function() birdVel.Velocity=diff.Unit*40 end)
			end
			task.wait(0.05)
		end
		for i = #activeBirds, 1, -1 do
			if activeBirds[i].model==birdModel then table.remove(activeBirds,i); break end
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(1)
		if isFlying then
			birdSpawnTimer = birdSpawnTimer + 1
			if birdSpawnTimer >= birdSpawnInterval then
				birdSpawnTimer = 0; birdSpawnInterval = math.random(20,40)
				createBird()
			end
		else
			birdSpawnTimer = 0
		end
	end
end)

-- ===== RAIN / WIND-LINE HELPERS =====
local function spawnRainDrop()
	local char = player.Character; local hrpNow = char and char:FindFirstChild("HumanoidRootPart"); if not hrpNow then return end
	local drop = Instance.new("Part"); drop.Size=Vector3.new(0.05,1,0.05); drop.Color=Color3.new(1,1,1)
	drop.Material=Enum.Material.Neon; drop.Transparency=0.5; drop.CanCollide=false; drop.CastShadow=false; drop.Anchored=false
	drop.Position=hrpNow.Position+Vector3.new(math.random(-30,30),math.random(5,20),math.random(-30,30)); drop.Parent=workspace
	local bv=Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(0,1e6,0); bv.Velocity=Vector3.new(0,-80,0); bv.Parent=drop
	task.delay(2,function() pcall(function() if drop.Parent then drop:Destroy() end end) end)
end

local function spawnWindLine()
	local char = player.Character; local hrpNow = char and char:FindFirstChild("HumanoidRootPart"); if not hrpNow then return end
	local line = Instance.new("Part"); line.Size=Vector3.new(0.05,0.05,3); line.Color=Color3.new(1,1,1)
	line.Material=Enum.Material.Neon; line.Transparency=0.5; line.CanCollide=false; line.CastShadow=false; line.Anchored=false
	line.Position=hrpNow.Position+Vector3.new(math.random(-20,20),math.random(-5,5),math.random(-20,20)); line.Parent=workspace
	local bv=Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(1e6,1e6,1e6); bv.Velocity=windstormDir*40; bv.Parent=line
	task.delay(1,function() pcall(function() if line.Parent then line:Destroy() end end) end)
end

local function startThunderstorm()
	stormOverlay.BackgroundTransparency=1
	TweenService:Create(stormOverlay,TweenInfo.new(0.5),{BackgroundTransparency=0.6}):Play()
	local endT = tick()+10
	task.spawn(function()
		while tick()<endT and thunderstormActive do
			for i=1,3 do pcall(spawnRainDrop) end
			if math.random()<0.4 then
				lightningFlash.BackgroundTransparency=0; task.wait(0.05)
				if not thunderstormActive then break end
				lightningFlash.BackgroundTransparency=1
			end
			TweenService:Create(stormOverlay,TweenInfo.new(0.2),{BackgroundTransparency=0.5+math.random()*0.2}):Play()
			task.wait(0.5+math.random()*1.5)
		end
		thunderstormActive=false
		lightningFlash.BackgroundTransparency=1
		TweenService:Create(stormOverlay,TweenInfo.new(0.5),{BackgroundTransparency=1}):Play()
	end)
end

local function startWindstorm()
	local rx = math.random(1,2)==1 and math.random(-10,-3) or math.random(3,10)
	local rz = math.random(1,2)==1 and math.random(-10,-3) or math.random(3,10)
	windstormDir = Vector3.new(rx,0,rz).Unit
	local dirArrow
	if math.abs(windstormDir.X) >= math.abs(windstormDir.Z) then
		dirArrow = windstormDir.X>0 and "\xe2\x86\x92" or "\xe2\x86\x90"
	else
		dirArrow = windstormDir.Z>0 and "\xe2\x86\x93" or "\xe2\x86\x91"
	end
	windStormLabel.Text = "\xF0\x9F\x92\xA8 "..dirArrow.." WIND STORM!"
	windStormFrame.BackgroundTransparency=1; windStormFrame.Visible=true
	TweenService:Create(windStormFrame,TweenInfo.new(0.5),{BackgroundTransparency=0.2}):Play()
	local endT = tick()+10
	task.spawn(function()
		while tick()<endT and windstormActive do
			for i=1,3 do pcall(spawnWindLine) end
			task.wait(0.3)
		end
		windstormActive=false
		TweenService:Create(windStormFrame,TweenInfo.new(0.5),{BackgroundTransparency=1}):Play()
		task.delay(0.5,function() windStormFrame.Visible=false end)
	end)
end

task.spawn(function()
	task.wait(3)
	local rng = Random.new()
	-- Rings: 3 between each island pair, placed along travel direction
	local ridx = 0
	for i = 1, 13 do
		local v1 = Vector3.new(ISLAND_POS[i].x, ISLAND_POS[i].y, ISLAND_POS[i].z)
		local v2 = Vector3.new(ISLAND_POS[i+1].x, ISLAND_POS[i+1].y, ISLAND_POS[i+1].z)
		local dir = (v2 - v1).Unit
		local dist = (v2 - v1).Magnitude
		for j = 1, 3 do
			local pos = v1 + dir * (dist * (j / 4))
			ridx = ridx + 1
			spawnRing(pos, RING_COLORS[((j-1)%3)+1], ridx, dir)
		end
	end
	-- Landing pads
	for i = 1, 14 do spawnLandingPad(i) end
	-- Gas pockets: 2 per island pair
	for i = 1, 13 do
		local p1, p2 = ISLAND_POS[i], ISLAND_POS[i+1]
		for _ = 1, 2 do
			local t = 0.25 + rng:NextNumber() * 0.5
			local pos = Vector3.new(
				p1.x + (p2.x - p1.x) * t + rng:NextNumber() * 40 - 20,
				p1.y + (p2.y - p1.y) * t,
				p1.z + (p2.z - p1.z) * t + rng:NextNumber() * 40 - 20
			)
			spawnGasPocket(pos)
		end
	end
	print("WORLD OBJECTS SPAWNED")
end)

-- ===== REMOTE EVENTS =====
local RS = game:GetService("ReplicatedStorage")
local BuyFoodEvent      = RS:FindFirstChild("BuyFoodEvent")      or RS:WaitForChild("BuyFoodEvent",      10)
local RegenEvent        = RS:FindFirstChild("RegenEvent")        or RS:WaitForChild("RegenEvent",        10)
local CoinEvent         = RS:FindFirstChild("CoinEvent")         or RS:WaitForChild("CoinEvent",         10)
local SkipIslandEvent   = RS:FindFirstChild("SkipIslandEvent")   or RS:WaitForChild("SkipIslandEvent",   10)
local UnlockIslandEvent = RS:FindFirstChild("UnlockIslandEvent") or RS:WaitForChild("UnlockIslandEvent", 10)
local AnnouncementEvent = RS:FindFirstChild("AnnouncementEvent") or RS:WaitForChild("AnnouncementEvent", 10)
local ServerEventNotify = RS:FindFirstChild("ServerEventNotify") or RS:WaitForChild("ServerEventNotify", 10)

local leaderstats = player:FindFirstChild("leaderstats") or player:WaitForChild("leaderstats", 10)
if not leaderstats then print("ERROR: leaderstats missing") end

-- ===== CORE UPDATE FUNCTIONS =====
local function updateMeter()
	local fill = math.clamp(cosmeticGas / 100, 0, 1)
	gasFill.Size = UDim2.new(fill, 0, 1, 0)
	local col
	if fill >= 0.75 then col = Color3.fromRGB(0,200,50)
	elseif fill >= 0.40 then col = Color3.fromRGB(255,200,0)
	elseif fill >= 0.10 then col = Color3.fromRGB(255,140,0)
	else col = Color3.fromRGB(220,50,50) end
	gasFill.BackgroundColor3 = col
	gasMeterStroke.Color = col
	gasPowerText.Text = "GAS: "..math.floor(cosmeticGas).."%"
end

local function updateFartBtn()
	if not hasBoughtFood then
		fartBtnFrame.BackgroundColor3 = Color3.fromRGB(120,120,120)
		local st = fartBtnFrame:FindFirstChildWhichIsA("UIStroke"); if st then st.Color = Color3.fromRGB(80,80,80) end
		fartBtn.Text = "\xF0\x9F\x92\xA8 BUY FOOD FIRST!"
		fartBtn.Active = false
	elseif isFlying or not hasLanded then
		fartBtnFrame.BackgroundColor3 = Color3.fromRGB(120,120,120)
		local st = fartBtnFrame:FindFirstChildWhichIsA("UIStroke"); if st then st.Color = Color3.fromRGB(80,80,80) end
		fartBtn.Text = "FLYING..."
		fartBtn.Active = false
	else
		fartBtnFrame.BackgroundColor3 = Color3.fromRGB(50,200,50)
		local st = fartBtnFrame:FindFirstChildWhichIsA("UIStroke"); if st then st.Color = Color3.fromRGB(0,150,0) end
		fartBtn.Text = "\xF0\x9F\x92\xA8 HOLD TO FART!"
		fartBtn.Active = true
	end
end

local function updateCoins()
	pcall(function()
		if leaderstats then local c = leaderstats:FindFirstChild("Coins"); if c then coinAmount.Text = tostring(c.Value) end end
	end)
end

local function updateHotbar()
	hotbarFrame.Visible = midAirRechargeCount > 0 or skipIslandCount > 0
	rechargeBadge.Text = tostring(midAirRechargeCount)
	skipBadge.Text = tostring(skipIslandCount)
end

local function getFlightSpeed(power)
	if power < 50 then return 18
	elseif power < 150 then return 25
	elseif power < 300 then return 35
	elseif power < 600 then return 48
	elseif power < 1000 then return 63
	elseif power < 1800 then return 80
	elseif power < 3000 then return 100
	elseif power < 5000 then return 123
	elseif power < 8000 then return 148
	elseif power < 12000 then return 175
	elseif power < 17000 then return 205
	elseif power < 24000 then return 238
	elseif power < 33000 then return 273
	else return 310 end
end

local function getMaxHeight(totalPower)
	return (flightStartY + totalPower * 1.6) * serverEventHeightMult
end

local gColors = {Color3.fromRGB(0,200,50), Color3.fromRGB(50,220,80), Color3.fromRGB(100,255,100), Color3.fromRGB(80,180,40)}
local function spawnCloud()
	local char = player.Character; local hrpNow = char and char:FindFirstChild("HumanoidRootPart"); if not hrpNow then return end
	local cloud = Instance.new("Part"); cloud.Shape=Enum.PartType.Ball
	cloud.Size=Vector3.new(math.random(10,25)/10,math.random(10,25)/10,math.random(10,25)/10)
	cloud.Color=gColors[math.random(1,#gColors)]; cloud.Material=Enum.Material.Neon; cloud.Transparency=0.3; cloud.CanCollide=false; cloud.Anchored=true; cloud.CastShadow=false
	cloud.Position=hrpNow.Position+Vector3.new(math.random(-15,15)/10,math.random(-10,5)/10,math.random(-15,15)/10)
	cloud.Parent=workspace
	local tw=TweenService:Create(cloud,TweenInfo.new(1.5,Enum.EasingStyle.Linear),{Transparency=1.0,Size=Vector3.new(0.1,0.1,0.1)})
	tw:Play(); tw.Completed:Connect(function() cloud:Destroy() end)
end

-- ===== UI UTILITY FUNCTIONS =====
local function showFloatingText(text, col)
	local sg = Instance.new("ScreenGui"); sg.ResetOnSpawn=false; sg.Parent=PlayerGui
	local lbl = Instance.new("TextLabel"); lbl.Text=text; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=22
	lbl.TextColor3=col or Color3.fromRGB(255,220,0); lbl.BackgroundTransparency=1
	lbl.Size=UDim2.new(0,300,0,50); lbl.Position=UDim2.new(0.5,-150,0.5,0); lbl.ZIndex=10; lbl.Parent=sg
	Instance.new("UIStroke").Parent=lbl
	TweenService:Create(lbl,TweenInfo.new(1.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(0.5,-150,0.35,0),TextTransparency=1}):Play()
	task.delay(1.5, function() sg:Destroy() end)
end

local function showMilestonePills(milestones)
	for i, m in ipairs(milestones) do
		task.delay((i-1)*0.35, function()
			local sg = Instance.new("ScreenGui"); sg.ResetOnSpawn=false; sg.Parent=PlayerGui
			local pill = mkFrame(sg, {Size=UDim2.new(0,280,0,42), Position=UDim2.new(0.5,-140,0.45,(i-1)*52), BackgroundColor3=Color3.fromRGB(40,190,40)})
			mkCorner(pill,21); mkStroke(pill,Color3.fromRGB(0,140,0),2)
			mkLabel(pill, {Text=m, Font=Enum.Font.GothamBold, TextSize=16, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,-10,1,0), Position=UDim2.new(0,5,0,0), TextXAlignment=Enum.TextXAlignment.Center})
			pill.BackgroundTransparency=1; pill.Position=UDim2.new(0.5,-140,0.42,(i-1)*52)
			TweenService:Create(pill,TweenInfo.new(0.3,Enum.EasingStyle.Back),{BackgroundTransparency=0,Position=UDim2.new(0.5,-140,0.45,(i-1)*52)}):Play()
			task.delay(2.5, function()
				TweenService:Create(pill,TweenInfo.new(0.4),{BackgroundTransparency=1}):Play()
				task.delay(0.4, function() sg:Destroy() end)
			end)
		end)
	end
end

local function showPerfectLanding(pad)
	if CoinEvent then pcall(function() CoinEvent:FireServer(25) end) end
	showFloatingText("\xF0\x9F\x8E\xAF Perfect Landing! +25 \xF0\x9F\xAA\x99", Color3.fromRGB(255,220,0))
	local orig = pad.Color
	TweenService:Create(pad,TweenInfo.new(0.1),{Color=Color3.new(1,1,1)}):Play()
	task.delay(0.25, function() pcall(function() TweenService:Create(pad,TweenInfo.new(0.25),{Color=orig}):Play() end) end)
end

local function showArrival(islandNum)
	if arrivedIslands[islandNum] then return end
	arrivedIslands[islandNum] = true
	arrivalFrame.BackgroundColor3 = islandColors[islandNum] or Color3.fromRGB(100,200,100)
	islandLabel.Text = (ISLAND_DISPLAY_NAMES[islandNum] or ("Island "..islandNum)).."!"
	arrivalFrame.Position = UDim2.new(0.5,0,0,-80)
	arrivalFrame.Visible = true
	TweenService:Create(arrivalFrame,TweenInfo.new(0.4,Enum.EasingStyle.Back),{Position=UDim2.new(0.5,0,0,10)}):Play()
	local token = {}
	arrivalHideToken = token
	task.delay(3, function()
		if arrivalHideToken ~= token then return end
		TweenService:Create(arrivalFrame,TweenInfo.new(0.3),{Position=UDim2.new(0.5,0,0,-80)}):Play()
		task.delay(0.35, function()
			if arrivalHideToken == token then arrivalFrame.Visible = false end
		end)
	end)
end

local function showServerEventBanner(msg, col)
	seBannerFrame.BackgroundColor3 = col
	seBannerLine2.Text = msg
	seBannerFrame.Position = UDim2.new(0.5,0,0,-90)
	TweenService:Create(seBannerFrame,TweenInfo.new(0.4,Enum.EasingStyle.Back),{Position=UDim2.new(0.5,0,0,136)}):Play()
	task.delay(4, function()
		TweenService:Create(seBannerFrame,TweenInfo.new(0.3),{Position=UDim2.new(0.5,0,0,-90)}):Play()
	end)
end

local announceQueue = {}
local announceRunning = false
local function queueAnnouncement(msg)
	table.insert(announceQueue, msg)
	if not announceRunning then
		announceRunning = true
		task.spawn(function()
			while #announceQueue > 0 do
				local m = table.remove(announceQueue, 1)
				announceBanner.Text = m
				announceFrame.Position = UDim2.new(0.5,0,0,-44)
				TweenService:Create(announceFrame,TweenInfo.new(0.3,Enum.EasingStyle.Back),{Position=UDim2.new(0.5,0,0,88)}):Play()
				task.wait(3.3)
				TweenService:Create(announceFrame,TweenInfo.new(0.3),{Position=UDim2.new(0.5,0,0,-44)}):Play()
				task.wait(0.4)
			end
			announceRunning = false
		end)
	end
end

local function getWindArrow(wx, wz)
	if math.abs(wx) >= math.abs(wz) then
		return wx > 0 and "\xe2\x86\x92" or "\xe2\x86\x90"
	else
		return wz > 0 and "\xe2\x86\x93" or "\xe2\x86\x91"
	end
end

local function checkMilestones()
	local peak = peakHeight
	local rings = ringsCollectedFlight
	local heightBonus, heightMsg = 0, nil
	if peak > 5000 then heightBonus, heightMsg = 500, "+500 \xF0\x9F\xAA\x99 LEGENDARY!"
	elseif peak > 2000 then heightBonus, heightMsg = 100, "+100 \xF0\x9F\xAA\x99 Amazing flight!"
	elseif peak > 500 then heightBonus, heightMsg = 20, "+20 \xF0\x9F\xAA\x99 Nice flight!" end
	local ringBonus, ringMsg = 0, nil
	if rings >= 6 then ringBonus, ringMsg = 200, "+200 \xF0\x9F\xAA\x99 Ring KING!"
	elseif rings >= 3 then ringBonus, ringMsg = 50, "+50 \xF0\x9F\xAA\x99 Ring Master!" end
	local total = heightBonus + ringBonus
	if total > 0 and CoinEvent then pcall(function() CoinEvent:FireServer(total) end) end
	local pills = {}
	if heightMsg then table.insert(pills, heightMsg) end
	if ringMsg then table.insert(pills, ringMsg) end
	if #pills > 0 then showMilestonePills(pills) end
end

-- ===== LANDING DETECTION =====
local function setupLandingDetection(char)
	local hum = char:FindFirstChildWhichIsA("Humanoid"); if not hum then return end
	hum:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
		if hum.FloorMaterial ~= Enum.Material.Air then
			cosmeticGas = 100; updateMeter()
			hasLanded = true
			ringStreak = 0; ringMultiplier = 1
			updateFartBtn()
			local hrpNow = char:FindFirstChild("HumanoidRootPart")
			if hrpNow then
				for _, pad in ipairs(landingPads) do
					if pad and pad.Parent then
						local dp = hrpNow.Position - pad.Position
						if math.abs(dp.X) < 6 and math.abs(dp.Z) < 6 then
							showPerfectLanding(pad); break
						end
					end
				end
			end
		end
	end)
end

-- ===== FLIGHT =====
local bodyVel = nil
local cloudTimer = 0
local coinTimer = 0

player.CharacterAdded:Connect(function(char)
	isFlying = false; bodyVel = nil; cosmeticGas = 100; hasLanded = true; updateMeter(); setupLandingDetection(char)
end)
setupLandingDetection(character)

local function startFlying()
	if not hasBoughtFood then return end
	if not hasLanded then return end
	if isFlying then return end
	local char = player.Character
	local hrpNow = char and char:FindFirstChild("HumanoidRootPart")
	if not hrpNow then return end
	hasLanded = false
	isFlying = true
	flightStartY = hrpNow.Position.Y
	flightStartTime = tick()
	peakHeight = hrpNow.Position.Y
	ringsCollectedFlight = 0
	flightStatsFrame.Visible = true
	if bodyVel then bodyVel:Destroy() end
	bodyVel = Instance.new("BodyVelocity")
	bodyVel.Name = "FartVelocity"
	bodyVel.MaxForce = Vector3.new(0, 1e6, 0)
	bodyVel.Velocity = Vector3.new(0, 50, 0)
	bodyVel.Parent = hrpNow
	updateFartBtn()
end

local function stopFlying()
	isFlying = false
	if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	cpsLabel.Visible = false
	flightStatsFrame.Visible = false
	windIndicatorFrame.Visible = false
	checkMilestones()
	peakHeight = 0; ringsCollectedFlight = 0
	updateFartBtn()
end

-- ===== HEARTBEAT =====
RunService.Heartbeat:Connect(function(dt)
	if twoXBoostActive and os.time() > twoXBoostEndTime then twoXBoostActive = false end
	if not isFlying then return end
	local char = player.Character
	local hrpNow = char and char:FindFirstChild("HumanoidRootPart")
	if not hrpNow then isFlying = false; return end
	if not bodyVel or not bodyVel.Parent then
		bodyVel = Instance.new("BodyVelocity"); bodyVel.Name="FartVelocity"
		bodyVel.MaxForce=Vector3.new(0,1e6,0); bodyVel.Velocity=Vector3.new(0,50,0); bodyVel.Parent=hrpNow
	end
	local power = 0
	pcall(function() if leaderstats then local t=leaderstats:FindFirstChild("TotalFartPower"); if t then power=t.Value end end end)
	local spd = getFlightSpeed(power) * serverEventSpeedMult
	if twoXBoostActive then spd = spd * 2 end
	local cap = getMaxHeight(power)
	if hrpNow.Position.Y >= cap then stopFlying(); return end

	-- Wind/turb zone check (Y-range)
	local posY = hrpNow.Position.Y
	local inWind, inTurb = false, false
	for _, wz in ipairs(windZoneData) do if posY >= wz.yMin and posY < wz.yMax then inWind=true; break end end
	if not inWind then
		for _, tz in ipairs(turbZoneData) do if posY >= tz.yMin and posY < tz.yMax then inTurb=true; break end end
	end

	if inTurb then
		turbTimer = turbTimer + dt
		windIndicatorFrame.BackgroundColor3 = Color3.fromRGB(255,200,50)
		windIndicatorLabel.Text = "\xE2\x9A\xA1 Turbulence!"
		windIndicatorFrame.Visible = true
		if turbTimer >= 0.5 then
			turbTimer = 0
			bodyVel.Velocity = Vector3.new(math.random(-15,15), spd*math.random(70,100)/100, math.random(-15,15))
			effectFlashFrame.BackgroundColor3 = Color3.new(1,1,1)
			effectFlashFrame.BackgroundTransparency = 0.7
			TweenService:Create(effectFlashFrame,TweenInfo.new(0.1),{BackgroundTransparency=0.97}):Play()
		else
			bodyVel.Velocity = Vector3.new(0, spd, 0)
		end
	elseif inWind then
		turbTimer = 0
		local wx = math.sin(tick()*0.5)*8
		local wz = math.cos(tick()*0.3)*8
		bodyVel.Velocity = Vector3.new(wx, spd, wz)
		windIndicatorFrame.BackgroundColor3 = Color3.fromRGB(100,150,255)
		windIndicatorFrame.BackgroundTransparency = 0.3
		windIndicatorLabel.Text = "\xF0\x9F\x92\xA8 Wind "..getWindArrow(wx, wz)
		windIndicatorFrame.Visible = true
	else
		turbTimer = 0
		bodyVel.Velocity = Vector3.new(0, spd, 0)
		windIndicatorFrame.Visible = false
	end

	-- Storm wind override
	if thunderstormActive then
		stormWindTimer = stormWindTimer + dt
		if stormWindTimer >= 0.5 then
			stormWindTimer = 0
			bodyVel.Velocity = Vector3.new(math.random(-25,25), spd, math.random(-25,25))
		end
	elseif windstormActive then
		stormWindTimer = stormWindTimer + dt
		if stormWindTimer >= 0.2 then
			stormWindTimer = 0
			bodyVel.Velocity = Vector3.new(windstormDir.X*35, spd, windstormDir.Z*35)
		end
	else
		stormWindTimer = 0
	end

	-- Gas drain: 3% per second
	cosmeticGas = math.max(0, cosmeticGas - dt * 3 * (serverEventGasDrainMult < 1 and 1/serverEventGasDrainMult or 1))
	updateMeter()
	if cosmeticGas <= 0 then stopFlying(); return end

	-- Peak height tracking
	if hrpNow.Position.Y > peakHeight then peakHeight = hrpNow.Position.Y end

	-- Flight stats update
	fsHeight.Text = "\xF0\x9F\x93\x8F Height: "..math.floor(hrpNow.Position.Y)
	fsRings.Text  = "\xF0\x9F\x92\x8D Rings: "..ringsCollectedFlight.." (x"..string.format("%.1f",ringMultiplier)..")"
	fsAir.Text    = "\xE2\x8F\xB1 Air: "..math.floor(tick()-flightStartTime).."s"

	-- Coins
	coinTimer = coinTimer + dt
	if coinTimer >= 0.2 then
		coinTimer = 0
		local height = math.max(0, hrpNow.Position.Y - 5)
		local coinsPerTick = math.floor(height / 10) * 0.15 * serverEventCoinMult
		if coinsPerTick > 0 then
			pcall(function() CoinEvent:FireServer(coinsPerTick) end)
		end
	end

	-- Ring collection
	for i = #activeRings, 1, -1 do
		local r = activeRings[i]
		if r.part and r.part.Parent then
			if (hrpNow.Position - r.part.Position).Magnitude < 12 then
				local rpos, rcol, ridx, rdir = r.pos, r.color, r.idx, r.dir
				r.part:Destroy()
				table.remove(activeRings, i)
				ringStreak = ringStreak + 1
				ringMultiplier = 1 + ringStreak * 0.2
				local bonus = math.floor(15 * ringMultiplier * serverEventRingMult)
				ringsCollectedFlight = ringsCollectedFlight + 1
				if CoinEvent then pcall(function() CoinEvent:FireServer(bonus) end) end
				showFloatingText("+"..bonus.." \xF0\x9F\xAA\x99 x"..string.format("%.1f",ringMultiplier), Color3.fromRGB(255,215,0))
				task.delay(30, function() spawnRing(rpos, rcol, ridx, rdir) end)
			end
		else
			table.remove(activeRings, i)
		end
	end

	-- Gas pocket collection
	for i = #activeGasPockets, 1, -1 do
		local p = activeGasPockets[i]
		if p and p.Parent then
			if (hrpNow.Position - p.Position).Magnitude < 9 then
				local ppos = p.Position
				p:Destroy(); table.remove(activeGasPockets, i)
				cosmeticGas = math.min(100, cosmeticGas + 20); updateMeter()
				showFloatingText("+GAS BOOST!", Color3.fromRGB(0,255,100))
				effectFlashFrame.BackgroundColor3 = Color3.fromRGB(0,255,100)
				effectFlashFrame.BackgroundTransparency = 0.7
				TweenService:Create(effectFlashFrame,TweenInfo.new(0.15),{BackgroundTransparency=0.97}):Play()
				task.delay(45, function() spawnGasPocket(ppos) end)
			end
		else
			table.remove(activeGasPockets, i)
		end
	end

	cloudTimer = cloudTimer + dt
	if cloudTimer >= 0.1 then cloudTimer = 0; pcall(spawnCloud) end
end)

-- ===== INPUT =====
local UserInputService = game:GetService("UserInputService")
local isFartButtonHeld = false

fartBtn.MouseButton1Down:Connect(function()
	isFartButtonHeld = true
	if hasBoughtFood then startFlying() end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isFartButtonHeld = false; stopFlying()
	end
end)
UserInputService.TouchEnded:Connect(function()
	isFartButtonHeld = false; stopFlying()
end)

shopBtn.MouseButton1Click:Connect(function() PremiumShopGui.Enabled = not PremiumShopGui.Enabled end)
inviteBtn.MouseButton1Click:Connect(function() pcall(function() SocialService:PromptGameInvite(player) end) end)
premClose.MouseButton1Click:Connect(function() PremiumShopGui.Enabled = false end)
foodCloseBtn.MouseButton1Click:Connect(function() FoodShopGui.Enabled=false; shopOpen=false; playerClosedShop=true end)

-- ===== FOOD SHOP =====
local function updateFoodShop(islandNum)
	nearIslandNumber = islandNum
	foodTitle.Text = "\xF0\x9F\x8F\x9D\xEF\xB8\x8F ISLAND "..islandNum.." FOOD STAND"
	local pIsland = 1
	pcall(function() if leaderstats then local i=leaderstats:FindFirstChild("Island"); if i then pIsland=i.Value end end end)
	local locked = islandNum > pIsland
	foodLockedFrame.Visible=locked; foodEmoji.Visible=not locked; foodName.Visible=not locked
	foodPrice.Visible=not locked; foodPower.Visible=not locked; foodBuyBtn.Visible=not locked
	if locked then return end
	local f = foods[islandNum]; if not f then return end
	foodEmoji.Text=foodEmojis[f.name] or "?"; foodName.Text=f.name
	foodPrice.Text="\xF0\x9F\xAA\x99 "..f.price.." coins"; foodPower.Text="+"..f.power.." power"
	local coins=0
	pcall(function() if leaderstats then local c=leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end end end)
	if coins>=f.price then foodBuyBtn.BackgroundColor3=Color3.fromRGB(50,200,50); foodBuyBtn.Text="BUY FOOD"; foodBuyBtn.TextSize=22
	else foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text="NOT ENOUGH COINS"; foodBuyBtn.TextSize=16 end
	for _, fd in ipairs(foods) do
		local cell=foodCells[fd.name]; if cell then
			local st=cell:FindFirstChildWhichIsA("UIStroke")
			if fd.island<=pIsland then cell.BackgroundColor3=Color3.fromRGB(200,240,200); if st then st.Color=Color3.fromRGB(150,200,150) end
			else cell.BackgroundColor3=Color3.fromRGB(210,210,210); if st then st.Color=Color3.fromRGB(160,160,160) end end
		end
	end
end

foodBuyBtn.MouseButton1Click:Connect(function()
	local f=foods[nearIslandNumber]; if not f then return end
	local coins=0
	pcall(function() if leaderstats then local c=leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end end end)
	if coins<f.price then return end
	pcall(function() if BuyFoodEvent then BuyFoodEvent:FireServer(f.name) end end)
	local fl=Instance.new("TextLabel"); fl.Text="+"..f.power.." power!"; fl.Font=Enum.Font.GothamBold; fl.TextSize=20; fl.TextColor3=Color3.fromRGB(0,200,50); fl.BackgroundTransparency=1; fl.Size=UDim2.new(0,200,0,40); fl.Position=UDim2.new(0.3,0,0.6,0); fl.ZIndex=10; fl.Parent=FoodShopGui
	TweenService:Create(fl,TweenInfo.new(1.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(0.3,0,0.4,0),TextTransparency=1}):Play()
	task.delay(1.5, function() fl:Destroy() end)
end)

rechargeSlot.MouseButton1Click:Connect(function()
	if midAirRechargeCount>0 then
		midAirRechargeCount=midAirRechargeCount-1; cosmeticGas=100; updateMeter(); updateFartBtn(); updateHotbar()
	end
end)
skipSlot.MouseButton1Click:Connect(function()
	if skipIslandCount>0 then
		skipIslandCount=skipIslandCount-1
		pcall(function() if SkipIslandEvent then SkipIslandEvent:FireServer() end end)
		updateHotbar()
	end
end)

-- ===== REMOTE EVENT HANDLERS =====
pcall(function()
	if RegenEvent then
		RegenEvent.OnClientEvent:Connect(function(power)
			hasBoughtFood = true; updateFartBtn()
		end)
	end
end)

if AnnouncementEvent then
	AnnouncementEvent.OnClientEvent:Connect(function(pName, islandNum, islandName)
		local msg = "\xF0\x9F\x8F\x9D\xEF\xB8\x8F "..tostring(pName).." reached "..tostring(islandName).."!"
		queueAnnouncement(msg)
	end)
end

if ServerEventNotify then
	ServerEventNotify.OnClientEvent:Connect(function(eventName, dispName, duration, msg, color)
		if eventName=="THUNDERSTORM" then
			thunderstormActive=true; pcall(startThunderstorm); return
		elseif eventName=="WINDSTORM" then
			windstormActive=true; pcall(startWindstorm); return
		end
		serverEventSpeedMult=1; serverEventCoinMult=1; serverEventGasDrainMult=1; serverEventHeightMult=1; serverEventRingMult=1
		if eventName == "END" then
			serverEventActive=false; seCountFrame.Visible=false; serverEventDisplayName=""
		else
			serverEventActive=true
			serverEventEndTime = os.time() + (tonumber(duration) or 0)
			serverEventDisplayName = tostring(dispName)
			if eventName=="FART_STORM"  then serverEventSpeedMult=2
			elseif eventName=="COIN_RUSH"   then serverEventCoinMult=3
			elseif eventName=="LOW_GRAVITY" then serverEventSpeedMult=0.5; serverEventGasDrainMult=0.3
			elseif eventName=="POWER_SURGE" then serverEventHeightMult=1.8
			elseif eventName=="RING_FEVER"  then serverEventRingMult=5 end
			seCountFrame.Visible=true
			showServerEventBanner(tostring(msg), color or Color3.new(1,1,1))
		end
	end)
end

-- ===== STATS LOOP =====
task.spawn(function()
	while true do
		task.wait(0.5)
		pcall(function()
			if leaderstats then
				local isl=leaderstats:FindFirstChild("Island"); local tfp=leaderstats:FindFirstChild("TotalFartPower"); local tce=leaderstats:FindFirstChild("TotalCoinsEarned")
				if isl then lbIsland.Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F Island: "..isl.Value end
				if tfp then lbMaxHeight.Text="\xF0\x9F\x9A\x80 Gain: +"..math.floor(tfp.Value*1.6).." studs" end
				if tce then lbEarned.Text="\xF0\x9F\xAA\x99 Earned: "..tce.Value end
			end
		end)
		updateCoins()
	end
end)

-- Server event countdown loop
task.spawn(function()
	while true do
		task.wait(1)
		if serverEventActive and serverEventEndTime > 0 then
			local remaining = math.max(0, serverEventEndTime - os.time())
			seCountLabel.Text = serverEventDisplayName..": "..remaining.."s"
			seCountFrame.Visible = remaining > 0
			if remaining <= 0 then serverEventActive=false end
		end
	end
end)

pcall(function()
	if leaderstats then
		local c=leaderstats:FindFirstChild("Coins")
		if c then c.Changed:Connect(function() updateCoins(); if shopOpen then updateFoodShop(nearIslandNumber) end end) end
	end
end)

print("EVENTS CONNECTED")

-- ===== GHOST TRAIL LOOP =====
local playerBillboards = {}
task.spawn(function()
	while true do
		task.wait(1)
		local flyingCount = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				local char2 = p.Character
				if char2 then local hrp2=char2:FindFirstChild("HumanoidRootPart"); if hrp2 and hrp2:FindFirstChild("FartVelocity") then flyingCount=flyingCount+1 end end
			end
		end
		if isFlying then flyingCount=flyingCount+1 end
		flyingLabel.Text = flyingCount>0 and (flyingCount.." player"..(flyingCount==1 and "" or "s").." flying now") or ""
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				pcall(function()
					local char2=p.Character; if not char2 then playerBillboards[p]=nil; return end
					local head2=char2:FindFirstChild("Head"); if not head2 then return end
					local bb=playerBillboards[p]
					if not bb or not bb.Parent then
						bb=Instance.new("BillboardGui"); bb.Name="GhostTrailBB"; bb.Size=UDim2.new(0,120,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=false; bb.Parent=head2; playerBillboards[p]=bb
						local dot=Instance.new("Frame"); dot.Name="Dot"; dot.Size=UDim2.new(0,10,0,10); dot.Position=UDim2.new(0,2,0.5,-5); dot.BorderSizePixel=0; dot.ZIndex=2; dot.Parent=bb; local dc=Instance.new("UICorner"); dc.CornerRadius=UDim.new(1,0); dc.Parent=dot
						local lbl=Instance.new("TextLabel"); lbl.Name="Info"; lbl.Size=UDim2.new(1,-14,1,0); lbl.Position=UDim2.new(0,14,0,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=13; lbl.TextColor3=Color3.new(1,1,1); lbl.TextWrapped=true; lbl.LineHeight=1.1; lbl.Parent=bb
						local st=Instance.new("UIStroke"); st.Color=Color3.new(0,0,0); st.Thickness=1.5; st.Parent=lbl
					end
					local pIsland=1
					pcall(function() local pls2=p:FindFirstChild("leaderstats"); if pls2 then local i2=pls2:FindFirstChild("Island"); if i2 then pIsland=i2.Value end end end)
					local ic=ISLAND_COLORS[pIsland] or Color3.fromRGB(100,200,100)
					local iname2=ISLAND_DISPLAY_NAMES[pIsland] or ("Island "..pIsland)
					local dot2=bb:FindFirstChild("Dot"); if dot2 then dot2.BackgroundColor3=ic end
					local lbl2=bb:FindFirstChild("Info"); if lbl2 then lbl2.Text=p.Name.."\n"..iname2 end
				end)
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(p) playerBillboards[p]=nil end)

-- ===== PROXIMITY + ISLAND UNLOCK LOOP (FIX 1) =====
task.spawn(function()
	print("PROXIMITY LOOP STARTED")
	local STAND_DIST = 20
	local ISLAND_DIST = 40
	local islandCenters = {}
	for i, pos in ipairs(ISLAND_POS) do islandCenters[i] = Vector3.new(pos.x, pos.y, pos.z) end
	while true do
		task.wait(0.2)
		local _ok, _err = pcall(function()
			local char = player.Character; if not char then return end
			local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
			local rpos = root.Position
			-- Try to get actual model centers
			for i, iname in ipairs(ISLAND_NAMES) do
				local model = workspace:FindFirstChild(iname)
				if model then
					local ok2, cf = pcall(function() return model:GetBoundingBox() end)
					if ok2 and cf then islandCenters[i] = cf.Position end
				end
				local center = islandCenters[i]
				if center and (rpos - center).Magnitude < ISLAND_DIST then
					local num = i
					if num > currentKnownIsland then
						showArrival(num)
						pcall(function() if UnlockIslandEvent then UnlockIslandEvent:FireServer(num) end end)
						currentKnownIsland = num
					end
				end
			end
			-- Food stand proximity
			local nearStand, nearIsland = false, 1
			for _, obj in ipairs(workspace:GetDescendants()) do
				if obj:IsA("ProximityPrompt") and obj.ObjectText == "Stand" then
					local part = obj.Parent
					if part and not part:IsA("BasePart") then
						part = part:FindFirstChildWhichIsA("BasePart") or (part.Parent and part.Parent:IsA("BasePart") and part.Parent or nil)
					end
					if part and (rpos - part.Position).Magnitude < STAND_DIST then
						nearStand=true; nearIsland=obj:GetAttribute("IslandNumber") or 1; break
					end
				end
			end
			if nearStand and not shopOpen and not playerClosedShop then
				updateFoodShop(nearIsland); FoodShopGui.Enabled=true; shopOpen=true
			elseif not nearStand then
				if shopOpen then FoodShopGui.Enabled=false; shopOpen=false end
				playerClosedShop=false
			end
		end)
		if not _ok then print("PROX ERR: "..tostring(_err)) end
	end
end)

-- ===== NAVIGATION ARROW LOOP =====
task.spawn(function()
	local Camera = workspace.CurrentCamera
	while true do
		task.wait(0.1)
		pcall(function()
			local ls = leaderstats
			if not ls then navFrame.Visible=false; navName.Visible=false; return end
			local islVal = ls:FindFirstChild("Island")
			if not islVal then navFrame.Visible=false; navName.Visible=false; return end
			local nextIsland = islVal.Value + 1
			if nextIsland > 14 then navFrame.Visible=false; navName.Visible=false; return end
			local tp = ISLAND_POS[nextIsland]
			local target3D = Vector3.new(tp.x, tp.y, tp.z)
			local vp = Camera.ViewportSize
			local cx, cy = vp.X/2, vp.Y/2
			local screenPos, onScreen = Camera:WorldToScreenPoint(target3D)
			local dx, dy = screenPos.X - cx, screenPos.Y - cy
			local margin = 60
			local maxX = cx - margin
			local maxY = cy - margin
			local ex, ey
			if onScreen and screenPos.Z > 0 and math.abs(dx) < maxX and math.abs(dy) < maxY then
				ex = screenPos.X; ey = screenPos.Y
			else
				if math.abs(dx) * maxY >= math.abs(dy) * maxX then
					local sign = dx >= 0 and 1 or -1
					ex = cx + sign * maxX
					ey = cy + dy * (maxX / math.max(math.abs(dx), 0.001))
				else
					local sign = dy >= 0 and 1 or -1
					ey = cy + sign * maxY
					ex = cx + dx * (maxY / math.max(math.abs(dy), 0.001))
				end
			end
			navFrame.Position = UDim2.new(0, ex, 0, ey)
			navName.Position = UDim2.new(0, ex, 0, ey + 26)
			navArrow.Rotation = math.deg(math.atan2(dy, dx)) + 90
			navFrame.Visible = true
			navName.Text = ISLAND_DISPLAY_NAMES[nextIsland] or ("Island "..nextIsland)
			navName.Visible = true
		end)
	end
end)

updateFartBtn(); updateMeter(); updateCoins()
print("CHUNK 3 DONE")
