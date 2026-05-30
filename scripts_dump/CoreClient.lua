print("CORECLIENT LOADING")
task.wait(0.1)
print("CORECLIENT RUNNING")
local Players = game.Players
local player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local PlayerGui = player.PlayerGui
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid",10)
local hrp = character:WaitForChild("HumanoidRootPart",10)

-- ===== SHARED DATA =====
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
	"Milk Marsh","Butter Swamp","Ice Cream Isle","Burger Bluff","Burrito Barrens","Pizza Palms"
}
local islandColors = {
	Color3.fromRGB(100,200,100),Color3.fromRGB(100,180,100),Color3.fromRGB(150,200,80),Color3.fromRGB(180,220,80),
	Color3.fromRGB(255,180,50),Color3.fromRGB(220,160,80),Color3.fromRGB(200,120,60),Color3.fromRGB(255,140,0),
	Color3.fromRGB(100,180,255),Color3.fromRGB(150,200,255),Color3.fromRGB(255,150,200),Color3.fromRGB(200,80,80),
	Color3.fromRGB(180,100,60),Color3.fromRGB(255,80,80),
}
local ISLAND_POS = {
	{x=0,y=50,z=0},{x=120,y=600,z=60},{x=-160,y=1400,z=100},
	{x=180,y=2500,z=-120},{x=-200,y=4000,z=160},{x=220,y=6000,z=-180},
	{x=-240,y=8500,z=200},{x=260,y=11500,z=-220},{x=-280,y=15000,z=240},
	{x=300,y=19000,z=-260},{x=-320,y=24000,z=280},{x=340,y=30000,z=-300},
	{x=-360,y=37000,z=320},{x=380,y=45000,z=-340},
}
local foods = {
	{name="Beans",price=10,power=3,island=1},{name="Broccoli",price=25,power=5,island=2},
	{name="Cabbage",price=50,power=8,island=3},{name="Turnips",price=100,power=12,island=4},
	{name="Coconuts",price=250,power=18,island=5},{name="Bread",price=500,power=26,island=6},
	{name="Pasta",price=1000,power=37,island=7},{name="Popcorn",price=2500,power=52,island=8},
	{name="Milk",price=5000,power=72,island=9},{name="Butter",price=10000,power=98,island=10},
	{name="IceCream",price=25000,power=132,island=11},{name="Burger",price=50000,power=175,island=12},
	{name="Burrito",price=75000,power=225,island=13},{name="Pizza",price=100000,power=280,island=14},
}
local RING_COLORS = {Color3.fromRGB(255,215,0),Color3.fromRGB(0,200,255),Color3.fromRGB(255,100,200)}

_G.ISLAND_NAMES=ISLAND_NAMES; _G.ISLAND_DISPLAY_NAMES=ISLAND_DISPLAY_NAMES
_G.ISLAND_COLORS=islandColors; _G.ISLAND_POS=ISLAND_POS
_G.foods=foods; _G.RING_COLORS=RING_COLORS

-- ===== SHARED FLIGHT STATE =====
_G.isFlying=false; _G.cosmeticGas=100; _G.hasLanded=true; _G.hasBoughtFood=false
_G.peakHeight=0; _G.ringsCollectedFlight=0
-- ===== SHARED EVENT STATE (set by EventClient) =====
_G.serverEventActive=false; _G.serverEventEndTime=0; _G.serverEventDisplayName=""
_G.serverEventSpeedMult=1; _G.serverEventCoinMult=1; _G.serverEventGasDrainMult=1
_G.serverEventHeightMult=1; _G.serverEventRingMult=1
_G.thunderstormActive=false; _G.windstormActive=false
_G.windstormDir=Vector3.new(1,0,0); _G.stormWindTimer=0; _G.activeBirds={}
-- ===== WORLD TABLES (populated by WorldClient) =====
_G.activeRings={}; _G.activeGasPockets={}; _G.landingPads={}

-- ===== LOCAL STATE =====
local flightStartY = 50
local flightStartTime = 0
local ringStreak = 0
local ringMultiplier = 1
local twoXBoostActive = false
local twoXBoostEndTime = 0
local turbTimer = 0
local arrivedIslands = {}
local arrivalHideToken = nil
local announceQueue = {}
local announceRunning = false

local windZoneData = {}
local turbZoneData = {}
for i = 1, 13 do
	local y1,y2 = ISLAND_POS[i].y, ISLAND_POS[i+1].y; local gap=y2-y1
	windZoneData[i]={yMin=y1+gap*0.15,yMax=y1+gap*0.65}
	turbZoneData[i]={yMin=y1+gap*0.70,yMax=y1+gap*0.95}
end

-- ===== GUI HELPERS =====
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

-- ===== GUI CREATION =====
local sg  -- reused ScreenGui variable

-- GUI 1: Gas Meter
sg=Instance.new("ScreenGui"); sg.Name="GasMeterGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local gmFrame=mkFrame(sg,{Size=UDim2.new(0,400,0,50),Position=UDim2.new(0.5,0,1,-73),AnchorPoint=Vector2.new(0.5,1),BackgroundTransparency=1})
local gmLabel=mkLabel(gmFrame,{Text="\xF0\x9F\x92\xA8 GAS METER",Font=Enum.Font.Gotham,TextSize=13,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,20),Position=UDim2.new(0,0,0,0),RichText=true})
mkStroke(gmLabel,Color3.new(0,0,0),2)
local gasBg=mkFrame(gmFrame,{Size=UDim2.new(1,0,0,30),Position=UDim2.new(0,0,0,20),BackgroundColor3=Color3.fromRGB(60,60,60)})
mkCorner(gasBg,20)
local gasMeterStroke=mkStroke(gasBg,Color3.fromRGB(0,200,50),3)
local gasFill=mkFrame(gasBg,{Name="Fill",Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.fromRGB(0,200,50),ZIndex=2})
mkCorner(gasFill,20)
local gasPowerText=mkLabel(gasBg,{Size=UDim2.new(1,0,1,0),Text="GAS: 100%",Font=Enum.Font.GothamBold,TextSize=14,TextColor3=Color3.new(1,1,1),ZIndex=3})
mkStroke(gasPowerText,Color3.new(0,0,0),1.5)
local flyingLabel=mkLabel(sg,{Text="",Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.fromRGB(160,160,160),Size=UDim2.new(0,400,0,16),Position=UDim2.new(0.5,0,1,-122),AnchorPoint=Vector2.new(0.5,1),TextXAlignment=Enum.TextXAlignment.Center})
_G.flyingLabel=flyingLabel

-- GUI 2: Fart Button
sg=Instance.new("ScreenGui"); sg.Name="FartButtonGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local fartBtnFrame=mkFrame(sg,{Position=UDim2.new(0.5,0,1,-15),Size=UDim2.new(0,240,0,50),BackgroundColor3=Color3.fromRGB(120,120,120),AnchorPoint=Vector2.new(0.5,1)})
mkCorner(fartBtnFrame,12); mkStroke(fartBtnFrame,Color3.fromRGB(80,80,80),3)
local fartBtn=mkButton(fartBtnFrame,{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="\xF0\x9F\x92\xA8 BUY FOOD FIRST!",Font=Enum.Font.Gotham,TextSize=17,TextColor3=Color3.new(1,1,1),RichText=true})
mkStroke(fartBtn,Color3.new(0,0,0),2)

-- GUI 3: Coins
sg=Instance.new("ScreenGui"); sg.Name="CoinGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local coinPill=mkFrame(sg,{Position=UDim2.new(1,-10,0,10),Size=UDim2.new(0,210,0,44),BackgroundColor3=Color3.fromRGB(255,200,0),AnchorPoint=Vector2.new(1,0)})
mkCorner(coinPill,25); mkStroke(coinPill,Color3.fromRGB(200,140,0),3)
mkLabel(coinPill,{Text="\xF0\x9F\xAA\x99",Font=Enum.Font.Gotham,Size=UDim2.new(0,40,0,40),Position=UDim2.new(0,5,0,5),TextSize=28,RichText=true,BackgroundTransparency=1})
local coinAmount=mkLabel(coinPill,{Name="Amount",Text="0",Font=Enum.Font.GothamBold,TextSize=24,TextColor3=Color3.fromRGB(100,50,0),Size=UDim2.new(1,-55,1,0),Position=UDim2.new(0,50,0,0),TextXAlignment=Enum.TextXAlignment.Left})
mkStroke(coinAmount,Color3.new(1,1,1),1.5)

-- GUI 4: Stats
sg=Instance.new("ScreenGui"); sg.Name="StatsGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local statsPanel=mkFrame(sg,{Position=UDim2.new(1,-10,0,62),Size=UDim2.new(0,210,0,90),BackgroundColor3=Color3.fromRGB(255,255,255),AnchorPoint=Vector2.new(1,0)})
mkCorner(statsPanel,12); mkStroke(statsPanel,Color3.fromRGB(200,200,200),2)
mkLabel(statsPanel,{Text="\xF0\x9F\x93\x8A STATS",Font=Enum.Font.Gotham,TextSize=16,TextColor3=Color3.fromRGB(50,50,50),Size=UDim2.new(1,-10,0,25),Position=UDim2.new(0,5,0,5),RichText=true,TextXAlignment=Enum.TextXAlignment.Left})
local lbIsland=mkLabel(statsPanel,{Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F Island: 1",Font=Enum.Font.Gotham,TextSize=14,TextColor3=Color3.fromRGB(80,80,80),Size=UDim2.new(1,-10,0,20),Position=UDim2.new(0,5,0,30),RichText=true,TextXAlignment=Enum.TextXAlignment.Left})
local lbMaxHeight=mkLabel(statsPanel,{Text="\xF0\x9F\x9A\x80 Gain: 0",Font=Enum.Font.Gotham,TextSize=14,TextColor3=Color3.fromRGB(80,80,80),Size=UDim2.new(1,-10,0,20),Position=UDim2.new(0,5,0,50),RichText=true,TextXAlignment=Enum.TextXAlignment.Left})
local lbEarned=mkLabel(statsPanel,{Text="\xF0\x9F\xAA\x99 Earned: 0",Font=Enum.Font.Gotham,TextSize=14,TextColor3=Color3.fromRGB(80,80,80),Size=UDim2.new(1,-10,0,20),Position=UDim2.new(0,5,0,70),RichText=true,TextXAlignment=Enum.TextXAlignment.Left})

-- GUI 5: Arrival
sg=Instance.new("ScreenGui"); sg.Name="ArrivalGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local arrivalFrame=mkFrame(sg,{Size=UDim2.new(0,420,0,70),Position=UDim2.new(0.5,0,0,10),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(100,200,100),Visible=false})
mkCorner(arrivalFrame,16); mkStroke(arrivalFrame,Color3.new(1,1,1),3)
local arrivalLine1=mkLabel(arrivalFrame,{Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F Welcome to",Font=Enum.Font.Gotham,TextSize=16,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,26),Position=UDim2.new(0,5,0,6),TextXAlignment=Enum.TextXAlignment.Center,RichText=true})
mkStroke(arrivalLine1,Color3.new(0,0,0),1)
local islandLabel=mkLabel(arrivalFrame,{Text="Bean Farm!",Font=Enum.Font.GothamBold,TextSize=26,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,34),Position=UDim2.new(0,5,0,33),TextXAlignment=Enum.TextXAlignment.Center})
mkStroke(islandLabel,Color3.new(0,0,0),2)

-- GUI 6: Announcement
sg=Instance.new("ScreenGui"); sg.Name="AnnounceGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local announceFrame=mkFrame(sg,{Size=UDim2.new(0,420,0,40),Position=UDim2.new(0.5,0,0,-44),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(255,200,0)})
mkCorner(announceFrame,20); mkStroke(announceFrame,Color3.fromRGB(200,150,0),2)
local announceBanner=mkLabel(announceFrame,{Text="",Font=Enum.Font.GothamBold,TextSize=15,TextColor3=Color3.fromRGB(80,40,0),Size=UDim2.new(1,-20,1,0),Position=UDim2.new(0,10,0,0),TextXAlignment=Enum.TextXAlignment.Center})

-- GUI 7: Server Event Banner
sg=Instance.new("ScreenGui"); sg.Name="ServerEventGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local seBannerFrame=mkFrame(sg,{Size=UDim2.new(0,500,0,80),Position=UDim2.new(0.5,0,0,-90),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(100,200,255)})
mkCorner(seBannerFrame,20); mkStroke(seBannerFrame,Color3.new(1,1,1),3)
local seBannerLine1=mkLabel(seBannerFrame,{Text="\xe2\x9a\xa0 SERVER EVENT!",Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,30),Position=UDim2.new(0,5,0,5),TextXAlignment=Enum.TextXAlignment.Center})
mkStroke(seBannerLine1,Color3.new(0,0,0),1.5)
local seBannerLine2=mkLabel(seBannerFrame,{Text="",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,36),Position=UDim2.new(0,5,0,38),TextXAlignment=Enum.TextXAlignment.Center,TextWrapped=true})
mkStroke(seBannerLine2,Color3.new(0,0,0),1.5)

-- GUI 8: SE Countdown
sg=Instance.new("ScreenGui"); sg.Name="SeCountGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local seCountFrame=mkFrame(sg,{Size=UDim2.new(0,200,0,32),Position=UDim2.new(0.5,0,0,224),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(50,50,50),Visible=false})
mkCorner(seCountFrame,16); mkStroke(seCountFrame,Color3.fromRGB(200,200,200),2)
local seCountLabel=mkLabel(seCountFrame,{Text="",Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,1,0),Position=UDim2.new(0,5,0,0),TextXAlignment=Enum.TextXAlignment.Center})
_G.seCountFrame=seCountFrame; _G.seCountLabel=seCountLabel

-- GUI 9: Wind/Turb Indicator
sg=Instance.new("ScreenGui"); sg.Name="WindGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local windIndicatorFrame=mkFrame(sg,{Size=UDim2.new(0,140,0,36),Position=UDim2.new(0.5,0,0.35,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(100,150,255),BackgroundTransparency=0.3,Visible=false})
mkCorner(windIndicatorFrame,18)
local windIndicatorLabel=mkLabel(windIndicatorFrame,{Text="\xF0\x9F\x92\xA8 Wind \xe2\x86\x92",Font=Enum.Font.Gotham,TextSize=14,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,1,0),Position=UDim2.new(0,5,0,0),TextXAlignment=Enum.TextXAlignment.Center})

-- GUI 10: Flight Stats
sg=Instance.new("ScreenGui"); sg.Name="FlightStatsGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local flightStatsFrame=mkFrame(sg,{Size=UDim2.new(0,160,0,100),Position=UDim2.new(0,90,1,-180),AnchorPoint=Vector2.new(0,1),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=0.15,Visible=false})
mkCorner(flightStatsFrame,10)
local fsHeight=mkLabel(flightStatsFrame,{Text="\xF0\x9F\x93\x8F Height: 0",Font=Enum.Font.Gotham,TextSize=13,TextColor3=Color3.fromRGB(30,30,30),Size=UDim2.new(1,-10,0,28),Position=UDim2.new(0,5,0,5),TextXAlignment=Enum.TextXAlignment.Left})
local fsRings=mkLabel(flightStatsFrame,{Text="\xF0\x9F\x92\x8D Rings: 0",Font=Enum.Font.Gotham,TextSize=13,TextColor3=Color3.fromRGB(30,30,30),Size=UDim2.new(1,-10,0,28),Position=UDim2.new(0,5,0,36),TextXAlignment=Enum.TextXAlignment.Left})
local fsAir=mkLabel(flightStatsFrame,{Text="\xe2\x8f\xb1 Air: 0s",Font=Enum.Font.Gotham,TextSize=13,TextColor3=Color3.fromRGB(30,30,30),Size=UDim2.new(1,-10,0,28),Position=UDim2.new(0,5,0,67),TextXAlignment=Enum.TextXAlignment.Left})

-- GUI 11: Effect Flash
sg=Instance.new("ScreenGui"); sg.Name="FlashGui"; sg.ResetOnSpawn=false; sg.ZIndexBehavior=Enum.ZIndexBehavior.Global; sg.Parent=PlayerGui
local effectFlashFrame=mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ZIndex=10})
_G.effectFlashFrame=effectFlashFrame

print("GUIS BUILT")

-- ===== REMOTE EVENTS =====
local RS = game:GetService("ReplicatedStorage")
local BuyFoodEvent=RS:FindFirstChild("BuyFoodEvent") or RS:WaitForChild("BuyFoodEvent",10)
local RegenEvent=RS:FindFirstChild("RegenEvent") or RS:WaitForChild("RegenEvent",10)
local CoinEvent=RS:FindFirstChild("CoinEvent") or RS:WaitForChild("CoinEvent",10)
local SkipIslandEvent=RS:FindFirstChild("SkipIslandEvent") or RS:WaitForChild("SkipIslandEvent",10)
local UnlockIslandEvent=RS:FindFirstChild("UnlockIslandEvent") or RS:WaitForChild("UnlockIslandEvent",10)
local AnnouncementEvent=RS:FindFirstChild("AnnouncementEvent") or RS:WaitForChild("AnnouncementEvent",10)
local ServerEventNotify=RS:FindFirstChild("ServerEventNotify") or RS:WaitForChild("ServerEventNotify",10)
local leaderstats=player:FindFirstChild("leaderstats") or player:WaitForChild("leaderstats",10)
_G.leaderstats=leaderstats; _G.CoinEvent=CoinEvent; _G.BuyFoodEvent=BuyFoodEvent
_G.SkipIslandEvent=SkipIslandEvent; _G.UnlockIslandEvent=UnlockIslandEvent
_G.ServerEventNotify=ServerEventNotify

-- ===== CORE FUNCTIONS =====
local function updateMeter()
	local fill=math.clamp(_G.cosmeticGas/100,0,1)
	gasFill.Size=UDim2.new(fill,0,1,0)
	local col
	if fill>=0.75 then col=Color3.fromRGB(0,200,50)
	elseif fill>=0.40 then col=Color3.fromRGB(255,200,0)
	elseif fill>=0.10 then col=Color3.fromRGB(255,140,0)
	else col=Color3.fromRGB(220,50,50) end
	gasFill.BackgroundColor3=col; gasMeterStroke.Color=col
	gasPowerText.Text="GAS: "..math.floor(_G.cosmeticGas).."%"
end
_G.updateMeter=updateMeter

local function updateFartBtn()
	if not _G.hasBoughtFood then
		fartBtnFrame.BackgroundColor3=Color3.fromRGB(120,120,120)
		local st=fartBtnFrame:FindFirstChildWhichIsA("UIStroke"); if st then st.Color=Color3.fromRGB(80,80,80) end
		fartBtn.Text="\xF0\x9F\x92\xA8 BUY FOOD FIRST!"; fartBtn.Active=false
	elseif _G.isFlying or not _G.hasLanded then
		fartBtnFrame.BackgroundColor3=Color3.fromRGB(120,120,120)
		local st=fartBtnFrame:FindFirstChildWhichIsA("UIStroke"); if st then st.Color=Color3.fromRGB(80,80,80) end
		fartBtn.Text="FLYING..."; fartBtn.Active=false
	else
		fartBtnFrame.BackgroundColor3=Color3.fromRGB(50,200,50)
		local st=fartBtnFrame:FindFirstChildWhichIsA("UIStroke"); if st then st.Color=Color3.fromRGB(0,150,0) end
		fartBtn.Text="\xF0\x9F\x92\xA8 HOLD TO FART!"; fartBtn.Active=true
	end
end
_G.updateFartBtn=updateFartBtn

local function updateCoins()
	pcall(function()
		if leaderstats then local c=leaderstats:FindFirstChild("Coins"); if c then coinAmount.Text=tostring(c.Value) end end
	end)
end
_G.updateCoins=updateCoins

local function getFlightSpeed(power)
	if power<50 then return 18 elseif power<150 then return 25 elseif power<300 then return 35
	elseif power<600 then return 48 elseif power<1000 then return 63 elseif power<1800 then return 80
	elseif power<3000 then return 100 elseif power<5000 then return 123 elseif power<8000 then return 148
	elseif power<12000 then return 175 elseif power<17000 then return 205 elseif power<24000 then return 238
	elseif power<33000 then return 273 else return 310 end
end

local function getMaxHeight(totalPower)
	return (flightStartY + totalPower * 1.6) * _G.serverEventHeightMult
end

local function showFloatingText(text, col)
	local sg2=Instance.new("ScreenGui"); sg2.ResetOnSpawn=false; sg2.Parent=PlayerGui
	local lbl=Instance.new("TextLabel"); lbl.Text=text; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=22
	lbl.TextColor3=col or Color3.fromRGB(255,220,0); lbl.BackgroundTransparency=1
	lbl.Size=UDim2.new(0,300,0,50); lbl.Position=UDim2.new(0.5,-150,0.5,0); lbl.ZIndex=10; lbl.Parent=sg2
	Instance.new("UIStroke").Parent=lbl
	TweenService:Create(lbl,TweenInfo.new(1.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(0.5,-150,0.35,0),TextTransparency=1}):Play()
	task.delay(1.5,function() sg2:Destroy() end)
end
_G.showFloatingText=showFloatingText

local function showArrival(islandNum)
	if arrivedIslands[islandNum] then return end
	arrivedIslands[islandNum]=true
	arrivalFrame.BackgroundColor3=islandColors[islandNum] or Color3.fromRGB(100,200,100)
	islandLabel.Text=(ISLAND_DISPLAY_NAMES[islandNum] or ("Island "..islandNum)).."!"
	arrivalFrame.Position=UDim2.new(0.5,0,0,-80); arrivalFrame.Visible=true
	TweenService:Create(arrivalFrame,TweenInfo.new(0.4,Enum.EasingStyle.Back),{Position=UDim2.new(0.5,0,0,10)}):Play()
	local token={}; arrivalHideToken=token
	task.delay(3,function()
		if arrivalHideToken~=token then return end
		TweenService:Create(arrivalFrame,TweenInfo.new(0.3),{Position=UDim2.new(0.5,0,0,-80)}):Play()
		task.delay(0.35,function() if arrivalHideToken==token then arrivalFrame.Visible=false end end)
	end)
end
_G.showArrival=showArrival

local function showServerEventBanner(msg, col)
	seBannerFrame.BackgroundColor3=col; seBannerLine2.Text=msg
	seBannerFrame.Position=UDim2.new(0.5,0,0,-90)
	TweenService:Create(seBannerFrame,TweenInfo.new(0.4,Enum.EasingStyle.Back),{Position=UDim2.new(0.5,0,0,136)}):Play()
	task.delay(4,function() TweenService:Create(seBannerFrame,TweenInfo.new(0.3),{Position=UDim2.new(0.5,0,0,-90)}):Play() end)
end
_G.showServerEventBanner=showServerEventBanner

local function queueAnnouncement(msg)
	table.insert(announceQueue,msg)
	if not announceRunning then
		announceRunning=true
		task.spawn(function()
			while #announceQueue>0 do
				local m=table.remove(announceQueue,1)
				announceBanner.Text=m; announceFrame.Position=UDim2.new(0.5,0,0,-44)
				TweenService:Create(announceFrame,TweenInfo.new(0.3,Enum.EasingStyle.Back),{Position=UDim2.new(0.5,0,0,88)}):Play()
				task.wait(3.3)
				TweenService:Create(announceFrame,TweenInfo.new(0.3),{Position=UDim2.new(0.5,0,0,-44)}):Play()
				task.wait(0.4)
			end
			announceRunning=false
		end)
	end
end

local function getWindArrow(wx,wz)
	if math.abs(wx)>=math.abs(wz) then return wx>0 and "\xe2\x86\x92" or "\xe2\x86\x90"
	else return wz>0 and "\xe2\x86\x93" or "\xe2\x86\x91" end
end

local gColors={Color3.fromRGB(0,200,50),Color3.fromRGB(50,220,80),Color3.fromRGB(100,255,100),Color3.fromRGB(80,180,40)}
local function spawnCloud()
	local ch=player.Character; local h=ch and ch:FindFirstChild("HumanoidRootPart"); if not h then return end
	local cloud=Instance.new("Part"); cloud.Shape=Enum.PartType.Ball
	cloud.Size=Vector3.new(math.random(10,25)/10,math.random(10,25)/10,math.random(10,25)/10)
	cloud.Color=gColors[math.random(1,#gColors)]; cloud.Material=Enum.Material.Neon; cloud.Transparency=0.3
	cloud.CanCollide=false; cloud.Anchored=true; cloud.CastShadow=false
	cloud.Position=h.Position+Vector3.new(math.random(-15,15)/10,math.random(-10,5)/10,math.random(-15,15)/10)
	cloud.Parent=workspace
	local tw=TweenService:Create(cloud,TweenInfo.new(1.5,Enum.EasingStyle.Linear),{Transparency=1.0,Size=Vector3.new(0.1,0.1,0.1)})
	tw:Play(); tw.Completed:Connect(function() cloud:Destroy() end)
end

-- ===== LANDING DETECTION =====
local function setupLandingDetection(char)
	local hum=char:FindFirstChildWhichIsA("Humanoid"); if not hum then return end
	hum:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
		if hum.FloorMaterial~=Enum.Material.Air then
			_G.cosmeticGas=100; updateMeter()
			_G.hasLanded=true; ringStreak=0; ringMultiplier=1
			updateFartBtn()
			local hrpNow=char:FindFirstChild("HumanoidRootPart")
			if hrpNow then
				for _,pad in ipairs(_G.landingPads) do
					if pad and pad.Parent then
						local dp=hrpNow.Position-pad.Position
						if math.abs(dp.X)<6 and math.abs(dp.Z)<6 then
							if _G.showPerfectLanding then _G.showPerfectLanding(pad) end; break
						end
					end
				end
			end
		end
	end)
end

-- ===== FLIGHT =====
local bodyVel=nil
local cloudTimer=0
local coinTimer=0

local function stopFlying()
	_G.isFlying=false
	if bodyVel then bodyVel:Destroy(); bodyVel=nil end
	flightStatsFrame.Visible=false; windIndicatorFrame.Visible=false
	if _G.checkMilestones then _G.checkMilestones() end
	_G.peakHeight=0; _G.ringsCollectedFlight=0
	updateFartBtn()
end
_G.stopFlying=stopFlying

local function startFlying()
	if not _G.hasBoughtFood then return end
	if not _G.hasLanded then return end
	if _G.isFlying then return end
	local char=player.Character
	local hrpNow=char and char:FindFirstChild("HumanoidRootPart"); if not hrpNow then return end
	_G.hasLanded=false; _G.isFlying=true
	flightStartY=hrpNow.Position.Y; flightStartTime=tick()
	_G.peakHeight=hrpNow.Position.Y; _G.ringsCollectedFlight=0
	flightStatsFrame.Visible=true
	if bodyVel then bodyVel:Destroy() end
	bodyVel=Instance.new("BodyVelocity"); bodyVel.Name="FartVelocity"
	bodyVel.MaxForce=Vector3.new(0,1e6,0); bodyVel.Velocity=Vector3.new(0,50,0); bodyVel.Parent=hrpNow
	updateFartBtn()
end

player.CharacterAdded:Connect(function(char)
	_G.isFlying=false; bodyVel=nil; _G.cosmeticGas=100; _G.hasLanded=true
	updateMeter(); setupLandingDetection(char)
end)
setupLandingDetection(character)

-- ===== HEARTBEAT =====
RunService.Heartbeat:Connect(function(dt)
	if twoXBoostActive and os.time()>twoXBoostEndTime then twoXBoostActive=false end
	if not _G.isFlying then return end
	local char=player.Character
	local hrpNow=char and char:FindFirstChild("HumanoidRootPart")
	if not hrpNow then _G.isFlying=false; return end
	if not bodyVel or not bodyVel.Parent then
		bodyVel=Instance.new("BodyVelocity"); bodyVel.Name="FartVelocity"
		bodyVel.MaxForce=Vector3.new(0,1e6,0); bodyVel.Velocity=Vector3.new(0,50,0); bodyVel.Parent=hrpNow
	end
	local power=0
	pcall(function() if leaderstats then local t=leaderstats:FindFirstChild("TotalFartPower"); if t then power=t.Value end end end)
	local spd=getFlightSpeed(power)*_G.serverEventSpeedMult
	if twoXBoostActive then spd=spd*2 end
	local cap=getMaxHeight(power)
	if hrpNow.Position.Y>=cap then stopFlying(); return end

	local posY=hrpNow.Position.Y
	local inWind,inTurb=false,false
	for _,wz in ipairs(windZoneData) do if posY>=wz.yMin and posY<wz.yMax then inWind=true; break end end
	if not inWind then for _,tz in ipairs(turbZoneData) do if posY>=tz.yMin and posY<tz.yMax then inTurb=true; break end end end

	if inTurb then
		turbTimer=turbTimer+dt; windIndicatorFrame.BackgroundColor3=Color3.fromRGB(255,200,50)
		windIndicatorLabel.Text="\xe2\x9a\xa1 Turbulence!"; windIndicatorFrame.Visible=true
		if turbTimer>=0.5 then
			turbTimer=0
			bodyVel.Velocity=Vector3.new(math.random(-15,15),spd*math.random(70,100)/100,math.random(-15,15))
			effectFlashFrame.BackgroundColor3=Color3.new(1,1,1); effectFlashFrame.BackgroundTransparency=0.7
			TweenService:Create(effectFlashFrame,TweenInfo.new(0.1),{BackgroundTransparency=0.97}):Play()
		else bodyVel.Velocity=Vector3.new(0,spd,0) end
	elseif inWind then
		turbTimer=0
		local wx=math.sin(tick()*0.5)*8; local wz=math.cos(tick()*0.3)*8
		bodyVel.Velocity=Vector3.new(wx,spd,wz)
		windIndicatorFrame.BackgroundColor3=Color3.fromRGB(100,150,255); windIndicatorFrame.BackgroundTransparency=0.3
		windIndicatorLabel.Text="\xF0\x9F\x92\xA8 Wind "..getWindArrow(wx,wz); windIndicatorFrame.Visible=true
	else
		turbTimer=0; bodyVel.Velocity=Vector3.new(0,spd,0); windIndicatorFrame.Visible=false
	end

	-- Storm wind override
	if _G.thunderstormActive then
		_G.stormWindTimer=_G.stormWindTimer+dt
		if _G.stormWindTimer>=0.5 then _G.stormWindTimer=0; bodyVel.Velocity=Vector3.new(math.random(-25,25),spd,math.random(-25,25)) end
	elseif _G.windstormActive then
		_G.stormWindTimer=_G.stormWindTimer+dt
		if _G.stormWindTimer>=0.2 then _G.stormWindTimer=0; bodyVel.Velocity=Vector3.new(_G.windstormDir.X*35,spd,_G.windstormDir.Z*35) end
	else _G.stormWindTimer=0 end

	-- Gas drain
	_G.cosmeticGas=math.max(0,_G.cosmeticGas-dt*3*(_G.serverEventGasDrainMult<1 and 1/_G.serverEventGasDrainMult or 1))
	updateMeter()
	if _G.cosmeticGas<=0 then stopFlying(); return end

	if hrpNow.Position.Y>_G.peakHeight then _G.peakHeight=hrpNow.Position.Y end

	fsHeight.Text="\xF0\x9F\x93\x8F Height: "..math.floor(hrpNow.Position.Y)
	fsRings.Text="\xF0\x9F\x92\x8D Rings: ".._G.ringsCollectedFlight.." (x"..string.format("%.1f",ringMultiplier)..")"
	fsAir.Text="\xe2\x8f\xb1 Air: "..math.floor(tick()-flightStartTime).."s"

	coinTimer=coinTimer+dt
	if coinTimer>=0.2 then
		coinTimer=0
		local height=math.max(0,hrpNow.Position.Y-5)
		local coins=math.floor(height/10)*0.15*_G.serverEventCoinMult
		if coins>0 then pcall(function() CoinEvent:FireServer(coins) end) end
	end

	-- Ring collection
	for i=#_G.activeRings,1,-1 do
		local r=_G.activeRings[i]
		if r.part and r.part.Parent then
			if (hrpNow.Position-r.part.Position).Magnitude<12 then
				local rpos,rcol,ridx,rdir=r.pos,r.color,r.idx,r.dir
				r.part:Destroy(); table.remove(_G.activeRings,i)
				ringStreak=ringStreak+1; ringMultiplier=1+ringStreak*0.2
				local bonus=math.floor(15*ringMultiplier*_G.serverEventRingMult)
				_G.ringsCollectedFlight=_G.ringsCollectedFlight+1
				if CoinEvent then pcall(function() CoinEvent:FireServer(bonus) end) end
				showFloatingText("+"..bonus.." \xF0\x9F\xAA\x99 x"..string.format("%.1f",ringMultiplier),Color3.fromRGB(255,215,0))
				task.delay(30,function() if _G.spawnRing then _G.spawnRing(rpos,rcol,ridx,rdir) end end)
			end
		else table.remove(_G.activeRings,i) end
	end

	-- Gas pocket collection
	for i=#_G.activeGasPockets,1,-1 do
		local p=_G.activeGasPockets[i]
		if p and p.Parent then
			if (hrpNow.Position-p.Position).Magnitude<9 then
				local ppos=p.Position; p:Destroy(); table.remove(_G.activeGasPockets,i)
				_G.cosmeticGas=math.min(100,_G.cosmeticGas+20); updateMeter()
				showFloatingText("+GAS BOOST!",Color3.fromRGB(0,255,100))
				effectFlashFrame.BackgroundColor3=Color3.fromRGB(0,255,100); effectFlashFrame.BackgroundTransparency=0.7
				TweenService:Create(effectFlashFrame,TweenInfo.new(0.15),{BackgroundTransparency=0.97}):Play()
				task.delay(45,function() if _G.spawnGasPocket then _G.spawnGasPocket(ppos) end end)
			end
		else table.remove(_G.activeGasPockets,i) end
	end

	cloudTimer=cloudTimer+dt
	if cloudTimer>=0.1 then cloudTimer=0; pcall(spawnCloud) end
end)

-- ===== INPUT =====
local UserInputService=game:GetService("UserInputService")
local isFartButtonHeld=false
fartBtn.MouseButton1Down:Connect(function() isFartButtonHeld=true; if _G.hasBoughtFood then startFlying() end end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1 then isFartButtonHeld=false; stopFlying() end
end)
UserInputService.TouchEnded:Connect(function() isFartButtonHeld=false; stopFlying() end)

-- ===== REMOTE HANDLERS =====
pcall(function()
	if RegenEvent then
		RegenEvent.OnClientEvent:Connect(function() _G.hasBoughtFood=true; updateFartBtn() end)
	end
end)
if AnnouncementEvent then
	AnnouncementEvent.OnClientEvent:Connect(function(pName,islandNum,islandName)
		queueAnnouncement("\xF0\x9F\x8F\x9D\xEF\xB8\x8F "..tostring(pName).." reached "..tostring(islandName).."!")
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
task.spawn(function()
	while true do
		task.wait(1)
		if _G.serverEventActive and _G.serverEventEndTime>0 then
			local rem=math.max(0,_G.serverEventEndTime-os.time())
			seCountLabel.Text=_G.serverEventDisplayName..": "..rem.."s"
			seCountFrame.Visible=rem>0
			if rem<=0 then _G.serverEventActive=false end
		end
	end
end)

updateFartBtn(); updateMeter(); updateCoins()
_G.CoreClientReady=true
print("CORECLIENT READY")
