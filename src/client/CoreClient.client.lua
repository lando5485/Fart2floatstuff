print("CORECLIENT LOADING")
task.wait(0.1)
print("CORECLIENT RUNNING")
local Players = game.Players
local player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local scale = isMobile and 0.7 or 1.0
local PlayerGui = player.PlayerGui
-- The character is NOT awaited here. With CharacterAutoLoads=false the player is HELD (no character)
-- through the loading screen + island menu, so blocking on CharacterAdded would stall the entire HUD
-- build until after the player is already in the world (causing the oversized flash / snap). Instead
-- we build + scale the whole HUD right now (under the loading screen) and reveal it on CharacterAdded
-- — which only fires once the player clicks PLAY and picks an island. hrp/humanoid are fetched live
-- where the flight code needs them, so these top-level locals being nil at start is fine.
local character = player.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
local hrp = character and character:FindFirstChildOfClass("HumanoidRootPart")

-- ===== BUILD HUD HIDDEN, REVEAL ON SPAWN =====
-- Every game ScreenGui (this script's + ShopClient/WorldClient/EventClient's, which all build after
-- _G.CoreClientReady below) is hidden the moment it's created and only revealed once the player
-- spawns into the world. So the UI is fully built + scaled BEFORE it's ever visible — no flash, no
-- snapping into place. We record each GUI's intended Enabled state and restore exactly that on reveal,
-- so menus that start disabled stay disabled. NOTE: hiding a ScreenGui (Enabled=false) does NOT stop
-- the scripts that build/drive it — instances + loops keep running, they're just not drawn until reveal.
local hudRevealed = false
local hudWantEnabled = {} -- [ScreenGui] = the Enabled state it was created with
local function hideGameGui(child)
	if child:IsA("ScreenGui") and child.Name ~= "LoadingScreen" and hudWantEnabled[child] == nil then
		hudWantEnabled[child] = child.Enabled
		child.Enabled = false
	end
end
for _, child in ipairs(PlayerGui:GetChildren()) do hideGameGui(child) end -- anything already created
local autoHideConn = PlayerGui.ChildAdded:Connect(hideGameGui)              -- everything created until reveal
local function revealHud()
	if hudRevealed then return end
	hudRevealed = true
	if autoHideConn then autoHideConn:Disconnect(); autoHideConn = nil end
	for sg, wantEnabled in pairs(hudWantEnabled) do
		if sg.Parent then sg.Enabled = wantEnabled end
	end
	print("HUD REVEALED: game UI shown after spawn")
end
player.CharacterAdded:Connect(revealHud)
if player.Character then revealHud() end -- safety: if a character somehow already exists

-- ===== UI CLICK SOUND =====
-- One click sound shared by ALL main-menu buttons (open + close). Clone-and-play so rapid
-- presses don't cut each other off. Parented to PlayerGui => 2D, audible only to this player.
-- This is UI-only; it is NOT wired to any gameplay event (flying/food/rings).
local UI_CLICK_VOLUME = 0.5 -- single adjustable volume for every menu click
local uiClickSound = Instance.new("Sound")
uiClickSound.Name = "UIClickSound"
uiClickSound.SoundId = "rbxassetid://101638558691673"
uiClickSound.Volume = UI_CLICK_VOLUME
uiClickSound.Parent = PlayerGui
local function playUIClick()
	local s = uiClickSound:Clone()
	s.Parent = PlayerGui
	s:Play()
	game:GetService("Debris"):AddItem(s, 3)
end
_G.playUIClick = playUIClick

-- ===== INSUFFICIENT-FUNDS ERROR SOUND =====
-- Played ONLY when a coin-priced stomach buy is attempted without enough coins.
-- Clone-and-play (audible to local player); single adjustable volume.
local ERROR_SOUND_VOLUME = 0.6
local errorSound = Instance.new("Sound")
errorSound.Name = "InsufficientFundsSound"
errorSound.SoundId = "rbxassetid://87486053112716"
errorSound.Volume = ERROR_SOUND_VOLUME
errorSound.Parent = PlayerGui
local function playErrorSound()
	local s = errorSound:Clone()
	s.Parent = PlayerGui
	s:Play()
	game:GetService("Debris"):AddItem(s, 3)
end

-- Quick left-right wobble for "can't afford" feedback on a button (~0.3s, small px shake, then
-- returns to its original Position). Guarded so rapid taps don't stack or leave it off-center.
local SHAKE_OFFSET = 8 -- px each side
local function shakeButton(btn)
	if not btn or btn:GetAttribute("Shaking") then return end
	btn:SetAttribute("Shaking", true)
	local orig = btn.Position
	local ti = TweenInfo.new(0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	task.spawn(function()
		for _ = 1, 3 do
			local a = TweenService:Create(btn, ti, {Position = orig + UDim2.fromOffset(-SHAKE_OFFSET, 0)}); a:Play(); a.Completed:Wait()
			local b = TweenService:Create(btn, ti, {Position = orig + UDim2.fromOffset(SHAKE_OFFSET, 0)}); b:Play(); b.Completed:Wait()
		end
		local c = TweenService:Create(btn, ti, {Position = orig}); c:Play(); c.Completed:Wait()
		btn.Position = orig
		btn:SetAttribute("Shaking", false)
	end)
end

-- ===== FART SOUNDS =====
-- Played ONLY when the player starts a fart/ascent (toggle-on). One reusable Sound: each start
-- stops any in-progress fart and plays a fresh random pick, so rapid toggles never overlap.
-- Parented to SoundService => 2D, audible to the local player. FART_VOLUME is the single adjustable volume.
local FART_VOLUME = 0.6
local FART_SOUND_IDS = {
	"rbxassetid://137105349517966",
	"rbxassetid://136812322649032",
	"rbxassetid://119702591396866",
	"rbxassetid://123499328258921",
	"rbxassetid://92449881602559",
	"rbxassetid://109574021376037",
	"rbxassetid://129402830763074",
}
local fartSound = Instance.new("Sound")
fartSound.Name = "FartSound"
fartSound.Volume = FART_VOLUME
fartSound.Parent = game:GetService("SoundService") -- SoundService => reliable 2D global playback (local player)
local function playFartSound()
	fartSound:Stop() -- cut any in-progress fart so rapid re-toggles don't stack
	local chosenId = FART_SOUND_IDS[math.random(1, #FART_SOUND_IDS)]
	fartSound.SoundId = chosenId
	print("FART SOUND playing id="..chosenId)
	fartSound:Play()
end

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
	{x=0,y=150,z=0},{x=120,y=790,z=60},{x=-160,y=1680,z=100},
	{x=180,y=2480,z=-120},{x=-200,y=3580,z=160},{x=220,y=4820,z=-180},
	{x=-240,y=6460,z=200},{x=260,y=8202,z=-220},{x=-280,y=9732,z=240},
	{x=300,y=11978,z=-260},{x=-320,y=14194,z=280},{x=340,y=17138,z=-300},
	{x=-360,y=20206,z=320},{x=380,y=24017,z=-340},
}
-- price = round(power * (0.8 + (island - 1) / 13 * 2.2))  -- cheap early islands, expensive late
local foods = {
	{name="Beans",    price=5,    power=8,   island=1},
	{name="Broccoli", price=24,   power=25,  island=2},
	{name="Cabbage",  price=85,   power=45,  island=3},
	{name="Turnips",  price=94,   power=70,  island=4},
	{name="Coconuts", price=142,  power=100, island=5},
	{name="Bread",    price=138,  power=140, island=6},
	{name="Pasta",    price=202,  power=185, island=7},
	{name="Popcorn",  price=600,  power=240, island=8},
	{name="Milk",     price=500,  power=300, island=9},
	{name="Butter",   price=400,  power=370, island=10},
	{name="IceCream", price=560,  power=450, island=11},
	{name="Burger",   price=405,  power=540, island=12},
	{name="Burrito",  price=700,  power=640, island=13},
	{name="Pizza",    price=518,  power=750, island=14},
}
local RING_COLORS = {Color3.fromRGB(255,215,0),Color3.fromRGB(0,200,255),Color3.fromRGB(255,100,200)}

_G.ISLAND_NAMES=ISLAND_NAMES; _G.ISLAND_DISPLAY_NAMES=ISLAND_DISPLAY_NAMES
_G.ISLAND_COLORS=islandColors; _G.ISLAND_POS=ISLAND_POS
_G.foods=foods; _G.RING_COLORS=RING_COLORS

-- ===== SHARED FLIGHT STATE =====
_G.isFlying=false; _G.cosmeticGas=0; _G.hasLanded=true; _G.hasBoughtFood=false; _G.hasRainbowTrail=false
_G.peakHeight=0; _G.ringsCollectedFlight=0
-- ===== SHARED EVENT STATE (set by EventClient) =====
_G.serverEventActive=false; _G.serverEventEndTime=0; _G.serverEventDisplayName=""
_G.serverEventSpeedMult=1; _G.serverEventCoinMult=1; _G.serverEventGasDrainMult=1
_G.serverEventHeightMult=1; _G.serverEventRingMult=1
_G.thunderstormActive=false; _G.windstormActive=false
_G.windstormDir=Vector3.new(1,0,0); _G.stormWindTimer=0; _G.activeBirds={}
-- ===== WORLD TABLES (populated by WorldClient) =====
_G.activeRings={}; _G.activeGasPockets={}; _G.landingPads={}
-- ===== GAMEPASS STATE =====
local playerGamepasses = {twoXForever=false, glitterTrail=false, midAirRecharge=0, skipIsland=0, twoXHourExpiry=0}
_G.playerGamepasses = playerGamepasses
_G.gui = {}

-- ===== LOCAL STATE =====
local flightStartY = 50
local flightStartTime = 0
local ringStreak = 0
local ringMultiplier = 1
local twoXBoostActive = false
local twoXBoostEndTime = 0
local arrivedIslands = {}
local arrivalHideToken = nil
local sessionMaxHeight = 0
local announceQueue = {}
local announceRunning = false
local bodyGyro = nil
local glideVel = nil
local isFlying = false
local hasBoughtFood = false
local currentPower = 0
local stomachMax = 100
local gasMeter = 0
local maxGasMeter = 100
-- 2x Fart Power pass/product: when active the effective tank is POWER_PASS_MULT x larger, so the
-- internal gas meter may fill up to maxGasMeter * POWER_PASS_MULT (longer flight => higher). The
-- DISPLAYED meter is still clamped to the normal 0..maxGasMeter / 0..stomachMax range (see
-- updateMeter). Must match POWER_PASS_MULT in PlayerStats.server.lua.
local POWER_PASS_MULT = 1.4
-- True when this player owns 2x-forever or has an unexpired 2x-hour product (mirrors the server's
-- has2x). Reads the gamepass state the server replicates into _G.playerGamepasses.
local function powerPassActive()
	local gp = _G.playerGamepasses
	return (gp and (gp.twoXForever or (gp.twoXHourExpiry and gp.twoXHourExpiry > os.time()))) and true or false
end
-- Effective fuel ceiling for flight physics (NOT for display).
local function effGasMax()
	return powerPassActive() and (maxGasMeter * POWER_PASS_MULT) or maxGasMeter
end
local DRAIN_RATE = 3.5 -- gas drained per second of flight (full tank ~= 28s)
-- Sideways steering speed (studs/s) WHILE FLYING only. Was a hardcoded 27; raised for more
-- responsive drifting to line up with islands. Affects horizontal X/Z only — NOT vertical rise,
-- gas drain, or on-ground WalkSpeed. Tune freely.
local FLIGHT_HORIZONTAL_SPEED = 48 -- ~1.8x the old 27
-- Per-flight cap on HEIGHT coin earnings (in-flight ring bonus is separate and NOT capped). The cap
-- now SCALES with how high you fly: this flight's height coins are capped at peakHeight*CAP_PER_HEIGHT
-- (never below FLIGHT_COIN_CAP). So a deep flight pays out much more than a shallow one, and earnings
-- clearly exceed food cost as the player climbs (earn ~= maxPower*14*CAP_PER_HEIGHT vs food cost/power).
local FLIGHT_COIN_CAP = 80     -- floor: minimum per-flight height-coin cap (covers low/short flights)
local CAP_PER_HEIGHT  = 0.2    -- per-flight cap = max(FLIGHT_COIN_CAP, peakHeight * this)
local flightCoinsEarned = 0 -- height coins actually sent this flight (capped at FLIGHT_COIN_CAP)
-- FLIGHT DEBUG balance tracking (per flight): food bought since last flight, and the
-- coins/tank snapshot taken at launch. dbgPrepPower/Cost accumulate in the RegenEvent handler.
local dbgPrepPower = 0
local dbgPrepCost = 0
local dbgCoinsBefore = 0
local dbgTankPower = 0
local dbgFlightRaw = 0 -- height coins this flight BEFORE the cap (uncapped total)
local stomachName = "Tiny Gut"
local stomachEmoji = "\xF0\x9F\x91\xB6"
local updateStomachDisplay = nil

-- ===== GUI HELPERS =====
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

-- ===== GUI CREATION =====
local sg
local SocialService = game:GetService("SocialService")

-- ===== TOP RIGHT: COIN DISPLAY =====
sg=Instance.new("ScreenGui"); sg.Name="CoinGui"; sg.ResetOnSpawn=false; sg.IgnoreGuiInset=true; sg.Parent=PlayerGui
local coinGui=sg
local coinPill=mkFrame(sg,{Position=UDim2.new(1,-10,0,10),Size=UDim2.new(0,180*scale,0,46*scale),BackgroundColor3=Color3.fromRGB(220,160,0),AnchorPoint=Vector2.new(1,0),ClipsDescendants=false,ZIndex=4})
mkCorner(coinPill,25); mkStroke(coinPill,Color3.fromRGB(180,120,0),3)
local coinGrad=Instance.new("UIGradient")
coinGrad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,190,20)),ColorSequenceKeypoint.new(1,Color3.fromRGB(200,140,0))})
coinGrad.Rotation=90; coinGrad.Parent=coinPill
-- Shared coin / checkmark IMAGE assets. Emoji glyphs (🪙 / ✅) do NOT render in Roblox
-- text labels, so we use real images instead. Defined on _G so BOTH the coin counter
-- here and the daily-rewards icons below reference the EXACT SAME asset (consistency),
-- and so we add no new main-chunk locals (Luau 200-local-per-function limit). To change
-- the icon everywhere, edit just these two strings.
_G.COIN_IMAGE  = "rbxassetid://106760789458573"                       -- gold coin icon (verified uploaded asset)
_G.GUT_IMAGE   = "rbxassetid://108585083746103"                       -- stomach/gut icon IMAGE (used by the STOMACH shop-OPEN side button AND the XL Gut tier icon)
-- PER-TIER GUT EMOJIS (single source of truth, keyed by gut name). Each gut's name label, HUD pill,
-- and shop-list card shows ITS OWN emoji from here — EXCEPT XL Gut, which shows an ImageLabel
-- (_G.GUT_IMAGE) instead of an emoji, so its entry below is kept only as an UNUSED fallback. The
-- STOMACH shop-OPEN button also keeps _G.GUT_IMAGE and is intentionally NOT in this map.
_G.GUT_EMOJI = {
	["Tiny Gut"]     = "\xF0\x9F\x91\xB6", -- 👶 baby
	["Small Gut"]    = "\xF0\x9F\xA7\x92", -- 🧒 child
	["Medium Gut"]   = "\xF0\x9F\xA7\x91", -- 🧑 person
	["Large Gut"]    = "\xF0\x9F\xA7\x94", -- 🧔 bearded adult
	["XL Gut"]       = "\xF0\x9F\xA4\xB0", -- 🤰 pregnant person (fallback for 🫃)
	["Iron Gut"]     = "\xF0\x9F\xA6\x9B", -- 🦛 hippo
	["Infinite Gut"] = "\xF0\x9F\x90\x8B", -- 🐋 whale
}
_G.CHECK_IMAGE = "rbxasset://textures/ui/LuaApp/icons/ic-check.png"   -- claimed checkmark (built-in)
-- Coin counter icon: a real coin IMAGE to the LEFT of the number (replaces the old "G" text).
local coinIcon=Instance.new("ImageLabel")
coinIcon.Name="CoinIcon"
coinIcon.Size=UDim2.new(0,math.floor(30*scale),0,math.floor(30*scale))
coinIcon.Position=UDim2.new(0,8,0.5,0)
coinIcon.AnchorPoint=Vector2.new(0,0.5)
coinIcon.BackgroundTransparency=1
coinIcon.Image=_G.COIN_IMAGE
coinIcon.ScaleType=Enum.ScaleType.Fit
coinIcon.ZIndex=6
coinIcon.Parent=coinPill
local coinAmountLabel=Instance.new("TextLabel")
coinAmountLabel.Name="Amount"
coinAmountLabel.Size=UDim2.new(1,-95,1,0)
coinAmountLabel.Position=UDim2.new(0,44,0,0)

coinAmountLabel.BackgroundTransparency=1
coinAmountLabel.Text="50"
coinAmountLabel.Font=Enum.Font.GothamBold
coinAmountLabel.TextSize=math.floor(20*scale)
coinAmountLabel.TextColor3=Color3.fromRGB(255,255,255)
coinAmountLabel.RichText=false
coinAmountLabel.TextScaled=false
coinAmountLabel.TextXAlignment=Enum.TextXAlignment.Left
coinAmountLabel.ZIndex=5
coinAmountLabel.Parent=coinPill
local coinPlusBtn=mkButton(coinPill,{Size=UDim2.new(0,34*scale,0,34*scale),Position=UDim2.new(1,-42,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.fromRGB(50,180,50),Text="+",Font=Enum.Font.GothamBold,TextSize=24,TextColor3=Color3.fromRGB(255,255,255)})
mkCorner(coinPlusBtn,19); mkStroke(coinPlusBtn,Color3.fromRGB(0,130,0),2)
coinPlusBtn.MouseButton1Click:Connect(function()
	local psg=PlayerGui:FindFirstChild("PremiumShopGui")
	if psg then psg.Enabled=not psg.Enabled end
end)
-- coinAmount alias removed (unused)

print("COIN PILL:", coinPill and coinPill.Parent and coinPill.Parent.Name or "NO PARENT")
print("COIN ICON:", coinIcon and tostring(coinIcon.AbsoluteSize) or "NIL")
print("COIN AMOUNT:", coinAmountLabel and coinAmountLabel.Text or "NIL")
print("COIN PILL VISIBLE:", coinPill and tostring(coinPill.Visible) or "NIL")
print("COIN GUI ENABLED:", coinGui and tostring(coinGui.Enabled) or "NIL")

-- ===== RIGHT PANEL (UNIFIED: STATS + IMPULSE BUTTONS) =====
local rightPanel = Instance.new("Frame")
do
	local rightGui = Instance.new("ScreenGui")
	rightGui.Name = "RightPanelGui"; rightGui.ResetOnSpawn = false
	rightGui.IgnoreGuiInset = true; rightGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	rightGui.Parent = PlayerGui
	rightPanel.Name = "RightPanel"
	rightPanel.Size = UDim2.new(0,230,0,500); rightPanel.Position = UDim2.new(1,-5,0,85)
	rightPanel.AnchorPoint = Vector2.new(1,0); rightPanel.BackgroundColor3 = Color3.fromRGB(30,90,200)
	rightPanel.ZIndex = 3; rightPanel.Parent = rightGui
end
mkCorner(rightPanel,16); mkStroke(rightPanel,Color3.fromRGB(255,255,255),2)

-- stats section (y=8, height=175)
local statsSection = Instance.new("Frame")
statsSection.Size = UDim2.new(1,-16,0,175); statsSection.Position = UDim2.new(0,8,0,8)
statsSection.BackgroundTransparency = 1; statsSection.Parent = rightPanel

local statsTitle = Instance.new("TextLabel")
statsTitle.Size = UDim2.new(1,-8,0,32); statsTitle.Position = UDim2.new(0,8,0,0)
statsTitle.BackgroundTransparency = 1; statsTitle.Text = "\xe2\xad\x90 STATS"
statsTitle.Font = Enum.Font.GothamBold; statsTitle.TextSize = 20; statsTitle.TextColor3 = Color3.fromRGB(255,200,0)
statsTitle.TextScaled = true; statsTitle.RichText = false
statsTitle.TextXAlignment = Enum.TextXAlignment.Left; statsTitle.Parent = statsSection

local islandLabel = Instance.new("TextLabel")
islandLabel.Size = UDim2.new(1,0,0,36); islandLabel.Position = UDim2.new(0,0,0,36)
islandLabel.BackgroundTransparency = 1; islandLabel.Text = "\xF0\x9F\x8F\x9d\xef\xb8\x8f Island: 1"
islandLabel.Font = Enum.Font.GothamBold; islandLabel.TextSize = 22; islandLabel.TextColor3 = Color3.fromRGB(255,255,255)
islandLabel.TextScaled = true; islandLabel.RichText = false
islandLabel.TextXAlignment = Enum.TextXAlignment.Left; islandLabel.Parent = statsSection

local heightLabel = Instance.new("TextLabel")
heightLabel.Size = UDim2.new(1,0,0,36); heightLabel.Position = UDim2.new(0,0,0,76)
heightLabel.BackgroundTransparency = 1; heightLabel.Text = "\xF0\x9F\x8f\x86 Max Height: 0"
heightLabel.Font = Enum.Font.GothamBold; heightLabel.TextSize = 22; heightLabel.TextColor3 = Color3.fromRGB(255,255,255)
heightLabel.TextScaled = true; heightLabel.RichText = false
heightLabel.TextXAlignment = Enum.TextXAlignment.Left; heightLabel.Parent = statsSection

local fartsLabel = Instance.new("TextLabel")
fartsLabel.Size = UDim2.new(1,0,0,36); fartsLabel.Position = UDim2.new(0,0,0,116)
fartsLabel.BackgroundTransparency = 1; fartsLabel.Text = "\xF0\x9F\x92\xa8 Farts: 0"
fartsLabel.Font = Enum.Font.GothamBold; fartsLabel.TextSize = 22; fartsLabel.TextColor3 = Color3.fromRGB(255,255,255)
fartsLabel.TextScaled = true; fartsLabel.RichText = false
fartsLabel.TextXAlignment = Enum.TextXAlignment.Left; fartsLabel.Parent = statsSection

-- lbIsland/lbMaxHeight/lbEarned/statsPanel aliases removed; use originals directly

-- divider (y=187: 8+175+4)
do
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1,-16,0,2); divider.Position = UDim2.new(0,8,0,187)
	divider.BackgroundColor3 = Color3.fromRGB(255,255,255); divider.BackgroundTransparency = 0.7; divider.Parent = rightPanel
end

-- MID AIR RECHARGE button (y=197: 187+2+8)
local midAir = Instance.new("TextButton")
midAir.Name = "MidAirBtn"; midAir.Size = UDim2.new(1,-16,0,90); midAir.Position = UDim2.new(0,8,0,197)
midAir.BackgroundColor3 = Color3.fromRGB(50,120,220); midAir.Text = ""; midAir.ZIndex = 4; midAir.Parent = rightPanel
mkCorner(midAir,12); mkStroke(midAir,Color3.fromRGB(255,255,255),1.5)
local midAirIcon = Instance.new("TextLabel")
midAirIcon.Size = UDim2.new(0,60,0,60); midAirIcon.Position = UDim2.new(0,8,0.5,0); midAirIcon.AnchorPoint = Vector2.new(0,0.5); midAirIcon.BackgroundTransparency = 1
midAirIcon.Text = "\xe2\x9a\xa1\xe2\x98\x81\xef\xb8\x8f"; midAirIcon.TextSize = 36; midAirIcon.Font = Enum.Font.Gotham
midAirIcon.RichText = false; midAirIcon.TextXAlignment = Enum.TextXAlignment.Center; midAirIcon.TextYAlignment = Enum.TextYAlignment.Center; midAirIcon.ZIndex = 5; midAirIcon.Parent = midAir
local midAirTitle = Instance.new("TextLabel")
midAirTitle.Size = UDim2.new(1,-76,0,28); midAirTitle.Position = UDim2.new(0,76,0,8); midAirTitle.BackgroundTransparency = 1
midAirTitle.Text = "MID-AIR"; midAirTitle.Font = Enum.Font.GothamBold; midAirTitle.TextSize = 20; midAirTitle.TextColor3 = Color3.fromRGB(255,255,255)
midAirTitle.TextScaled = true; midAirTitle.RichText = false; midAirTitle.TextXAlignment = Enum.TextXAlignment.Left; midAirTitle.TextYAlignment = Enum.TextYAlignment.Center; midAirTitle.ZIndex = 5; midAirTitle.Parent = midAir
local midAirSub = Instance.new("TextLabel")
midAirSub.Size = UDim2.new(1,-76,0,22); midAirSub.Position = UDim2.new(0,76,0,38); midAirSub.BackgroundTransparency = 1
midAirSub.Text = "RECHARGE"; midAirSub.Font = Enum.Font.Gotham; midAirSub.TextSize = 16; midAirSub.TextColor3 = Color3.fromRGB(220,220,220)
midAirSub.TextScaled = true; midAirSub.RichText = false; midAirSub.TextXAlignment = Enum.TextXAlignment.Left; midAirSub.TextYAlignment = Enum.TextYAlignment.Center; midAirSub.ZIndex = 5; midAirSub.Parent = midAir
local midAirPrice = Instance.new("TextLabel")
midAirPrice.Size = UDim2.new(1,-76,0,22); midAirPrice.Position = UDim2.new(0,76,0,62); midAirPrice.BackgroundTransparency = 1
midAirPrice.Text = "39 R$"; midAirPrice.Font = Enum.Font.GothamBold; midAirPrice.TextSize = 16; midAirPrice.TextColor3 = Color3.fromRGB(100,255,100)
midAirPrice.TextScaled = true; midAirPrice.RichText = false; midAirPrice.TextXAlignment = Enum.TextXAlignment.Left; midAirPrice.TextYAlignment = Enum.TextYAlignment.Center; midAirPrice.ZIndex = 5; midAirPrice.Parent = midAir
-- ===== MID-AIR RECHARGE — pause while purchasing (mid-flight only) =====
-- Tapping the Mid-Air Recharge BUY button while AIRBORNE holds the player in place for the whole
-- Robux prompt so they don't keep falling during it. We reuse the flight loop's OWN "Frozen" hold
-- path (it anchors the root + skips flight while that attribute is set), so this touches NEITHER the
-- flight code NOR the fart meter. On ANY prompt result (purchased OR cancelled) we release the hold
-- and zero velocity -> they resume from rest where they were paused. A successful purchase grants the
-- recharge charge through the normal server flow (its effect is left exactly as-is). Clicking on the
-- ground does nothing special. (Helpers are kept in a do-block so they add no main-chunk locals.)
do
	local rechargePauseActive = false
	local rechargePauseToken = 0
	local RECHARGE_PRODUCT = 3600303163
	-- _G.rechargeAwaitingFart: TRUE only while the player is paused AFTER a successful purchase, waiting
	-- for their fart press to unpause + fly. The fart handler reads it; we keep it on _G so toggleFart
	-- (outside this block) can see it.
	_G.rechargeAwaitingFart = false
	-- Lift the pause: clear Frozen, un-anchor, zero velocity. Used by CANCEL (resume falling) and by the
	-- fart-button resume after a purchase. Also clears the await flag so nothing lingers.
	local function rechargeUnfreeze()
		if not rechargePauseActive then return end
		rechargePauseActive = false
		rechargePauseToken = rechargePauseToken + 1            -- invalidate any pending safety timeout
		_G.rechargeAwaitingFart = false
		if player:GetAttribute("Frozen") then player:SetAttribute("Frozen", false) end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.Anchored = false
			hrp.AssemblyLinearVelocity = Vector3.zero          -- resume from rest at the paused spot
		end
	end
	_G.endRechargePause = rechargeUnfreeze
	-- STEP 1: clicking the button while AIRBORNE freezes the player in place, then opens the prompt.
	local function rechargeFreezeAndPrompt()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local airborne = hrp and hum and hum.FloorMaterial == Enum.Material.Air
		_G.rechargeAwaitingFart = false                        -- new attempt; not purchased yet
		-- Only pause MID-FLIGHT, and never stomp an existing (server join-) "Frozen" hold.
		if airborne and not rechargePauseActive and not player:GetAttribute("Frozen") then
			rechargePauseActive = true
			rechargePauseToken = rechargePauseToken + 1
			local myToken = rechargePauseToken
			hrp.AssemblyLinearVelocity = Vector3.zero          -- zero momentum -> hover exactly where clicked
			hrp.Anchored = true                                -- instant freeze; flight loop keeps it held while Frozen
			player:SetAttribute("Frozen", true)                -- flight loop anchors + skips flight while this is set
			-- Safety net: if NO purchase result ever arrives, auto-release after 60s so they can't get
			-- stuck. It does NOT fire once a purchase succeeded (awaiting fart) — that hover is intentional.
			task.delay(60, function()
				if rechargePauseActive and rechargePauseToken == myToken and not _G.rechargeAwaitingFart then
					rechargeUnfreeze()
				end
			end)
		end
		pcall(function() MarketplaceService:PromptProductPurchase(player, RECHARGE_PRODUCT) end)
	end
	-- STEP 2: on a SUCCESSFUL purchase -> refill the meter to MAX and KEEP the player frozen (hovering
	-- with a full tank). We do NOT auto-resume; the next fart press (step 4) resumes them.
	_G.rechargeMarkPurchased = function()
		-- Only act while still paused from this purchase. Both the client purchase callback AND the
		-- server's rechargeNow can call this; the guard makes it idempotent and prevents a late second
		-- signal from re-topping the meter AFTER the player already farted/resumed.
		if not rechargePauseActive then return end
		if _G.rechargeFartMeter then _G.rechargeFartMeter() end   -- actually WRITE the meter to its MAX + refresh UI
		_G.rechargeAwaitingFart = true                            -- stay frozen; the fart press (step 4) unpauses + flies
	end
	midAir.MouseButton1Click:Connect(function() playUIClick(); rechargeFreezeAndPrompt() end)
	-- Purchase result callback: isPurchased distinguishes SUCCESS vs CANCEL.
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, productId, isPurchased)
		if productId ~= RECHARGE_PRODUCT then return end
		if isPurchased then
			_G.rechargeMarkPurchased()     -- STEP 2: refill + keep paused, await fart
		else
			rechargeUnfreeze()             -- STEP 3: cancel/close -> immediately resume falling (no refill)
		end
	end)
end
-- midAirFrame alias removed

-- 2X POWER button (y=295: 197+90+8)
local twoX = Instance.new("TextButton")
twoX.Name = "TwoXBtn"; twoX.Size = UDim2.new(1,-16,0,90); twoX.Position = UDim2.new(0,8,0,295)
twoX.BackgroundColor3 = Color3.fromRGB(130,50,200); twoX.Text = ""; twoX.ZIndex = 4; twoX.Parent = rightPanel
mkCorner(twoX,12); mkStroke(twoX,Color3.fromRGB(255,255,255),1.5)
local twoXIcon = Instance.new("TextLabel")
twoXIcon.Size = UDim2.new(0,60,0,60); twoXIcon.Position = UDim2.new(0,8,0.5,0); twoXIcon.AnchorPoint = Vector2.new(0,0.5); twoXIcon.BackgroundTransparency = 1
twoXIcon.Text = "\xe2\x9a\xa1"; twoXIcon.TextSize = 36; twoXIcon.Font = Enum.Font.Gotham
twoXIcon.RichText = false; twoXIcon.TextXAlignment = Enum.TextXAlignment.Center; twoXIcon.TextYAlignment = Enum.TextYAlignment.Center; twoXIcon.ZIndex = 5; twoXIcon.Parent = twoX
local twoXTitle = Instance.new("TextLabel")
twoXTitle.Size = UDim2.new(1,-76,0,28); twoXTitle.Position = UDim2.new(0,76,0,8); twoXTitle.BackgroundTransparency = 1
twoXTitle.Text = "2X POWER"; twoXTitle.Font = Enum.Font.GothamBold; twoXTitle.TextSize = 20; twoXTitle.TextColor3 = Color3.fromRGB(255,255,255)
twoXTitle.TextScaled = true; twoXTitle.RichText = false; twoXTitle.TextXAlignment = Enum.TextXAlignment.Left; twoXTitle.TextYAlignment = Enum.TextYAlignment.Center; twoXTitle.ZIndex = 5; twoXTitle.Parent = twoX
local twoXSub = Instance.new("TextLabel")
twoXSub.Size = UDim2.new(1,-76,0,22); twoXSub.Position = UDim2.new(0,76,0,38); twoXSub.BackgroundTransparency = 1
twoXSub.Text = "1 HOUR"; twoXSub.Font = Enum.Font.Gotham; twoXSub.TextSize = 16; twoXSub.TextColor3 = Color3.fromRGB(220,220,220)
twoXSub.TextScaled = true; twoXSub.RichText = false; twoXSub.TextXAlignment = Enum.TextXAlignment.Left; twoXSub.TextYAlignment = Enum.TextYAlignment.Center; twoXSub.ZIndex = 5; twoXSub.Parent = twoX
-- twoXSubLabel alias removed; use twoXSub directly
local twoXPrice = Instance.new("TextLabel")
twoXPrice.Size = UDim2.new(1,-76,0,22); twoXPrice.Position = UDim2.new(0,76,0,62); twoXPrice.BackgroundTransparency = 1
twoXPrice.Text = "59 R$"; twoXPrice.Font = Enum.Font.GothamBold; twoXPrice.TextSize = 16; twoXPrice.TextColor3 = Color3.fromRGB(100,255,100)
twoXPrice.TextScaled = true; twoXPrice.RichText = false; twoXPrice.TextXAlignment = Enum.TextXAlignment.Left; twoXPrice.TextYAlignment = Enum.TextYAlignment.Center; twoXPrice.ZIndex = 5; twoXPrice.Parent = twoX
local twoXTimerLabel = Instance.new("Frame")
twoXTimerLabel.Size = UDim2.new(1,-76,0,22); twoXTimerLabel.Position = UDim2.new(0,76,0,38)
twoXTimerLabel.BackgroundTransparency = 1; twoXTimerLabel.Visible = false; twoXTimerLabel.ZIndex = 5; twoXTimerLabel.Parent = twoX
local twoXTimerText = Instance.new("TextLabel")
twoXTimerText.Size = UDim2.new(1,0,1,0); twoXTimerText.BackgroundTransparency = 1
twoXTimerText.Text = "\xe2\x9a\xa1 60m 00s"; twoXTimerText.Font = Enum.Font.GothamBold
twoXTimerText.TextColor3 = Color3.fromRGB(100,255,100); twoXTimerText.TextScaled = true
twoXTimerText.ZIndex = 6; twoXTimerText.Parent = twoXTimerLabel
twoX.MouseButton1Click:Connect(function() playUIClick(); pcall(function() MarketplaceService:PromptProductPurchase(player,3600302990) end) end)
-- twoXFrame alias removed

-- BIRD NUKE button (y=393: 295+90+8)
local birdNuke = Instance.new("TextButton")
birdNuke.Name = "BirdNukeBtn"; birdNuke.Size = UDim2.new(1,-16,0,90); birdNuke.Position = UDim2.new(0,8,0,393)
birdNuke.BackgroundColor3 = Color3.fromRGB(200,50,50); birdNuke.Text = ""; birdNuke.ZIndex = 4; birdNuke.Parent = rightPanel
mkCorner(birdNuke,12); mkStroke(birdNuke,Color3.fromRGB(255,255,255),1.5)
local birdIcon = Instance.new("TextLabel")
birdIcon.Size = UDim2.new(0,60,0,60); birdIcon.Position = UDim2.new(0,8,0.5,0); birdIcon.AnchorPoint = Vector2.new(0,0.5); birdIcon.BackgroundTransparency = 1
birdIcon.Text = "\xF0\x9F\x90\xa6\xF0\x9F\x92\xa5"; birdIcon.TextSize = 36; birdIcon.Font = Enum.Font.Gotham
birdIcon.RichText = false; birdIcon.TextXAlignment = Enum.TextXAlignment.Center; birdIcon.TextYAlignment = Enum.TextYAlignment.Center; birdIcon.ZIndex = 5; birdIcon.Parent = birdNuke
local birdTitle = Instance.new("TextLabel")
birdTitle.Size = UDim2.new(1,-76,0,28); birdTitle.Position = UDim2.new(0,76,0,8); birdTitle.BackgroundTransparency = 1
birdTitle.Text = "BIRD NUKE"; birdTitle.Font = Enum.Font.GothamBold; birdTitle.TextSize = 20; birdTitle.TextColor3 = Color3.fromRGB(255,255,255)
birdTitle.TextScaled = true; birdTitle.RichText = false; birdTitle.TextXAlignment = Enum.TextXAlignment.Left; birdTitle.TextYAlignment = Enum.TextYAlignment.Center; birdTitle.ZIndex = 5; birdTitle.Parent = birdNuke
local birdPrice = Instance.new("TextLabel")
birdPrice.Size = UDim2.new(1,-76,0,22); birdPrice.Position = UDim2.new(0,76,0,62); birdPrice.BackgroundTransparency = 1
birdPrice.Text = "79 R$"; birdPrice.Font = Enum.Font.GothamBold; birdPrice.TextSize = 16; birdPrice.TextColor3 = Color3.fromRGB(100,255,100)
birdPrice.TextScaled = true; birdPrice.RichText = false; birdPrice.TextXAlignment = Enum.TextXAlignment.Left; birdPrice.TextYAlignment = Enum.TextYAlignment.Center; birdPrice.ZIndex = 5; birdPrice.Parent = birdNuke
birdNuke.MouseButton1Click:Connect(function() playUIClick(); pcall(function() MarketplaceService:PromptProductPurchase(player,3600303082) end) end)
-- birdNukeFrame alias removed

-- ===== LEFT SIDE BUTTONS =====
sg=Instance.new("ScreenGui"); sg.Name="SidebarGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local function mkSideBtn(yOff,bgCol,iconTxt,labelTxt)
	local btn=mkFrame(sg,{Size=UDim2.new(0,75*scale,0,75*scale),Position=UDim2.new(0,10,0.5,yOff),BackgroundColor3=bgCol})
	mkCorner(btn,14); mkStroke(btn,Color3.new(1,1,1),2)
	local iconL=mkLabel(btn,{Text=iconTxt,Font=Enum.Font.Gotham,TextSize=math.floor(30*scale),Size=UDim2.new(1,0,0,56),Position=UDim2.new(0,0,0,0),RichText=true,BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(iconL,Color3.new(0,0,0),1)
	local textL=mkLabel(btn,{Name="Label",Text=labelTxt,Font=Enum.Font.GothamBold,TextSize=math.floor(12*scale),TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,28),Position=UDim2.new(0,0,0,57),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	mkStroke(textL,Color3.new(0,0,0),1)
	local clickBtn=mkButton(btn,{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""})
	return btn,clickBtn
end
local shopSideFrame,shopSideClick=mkSideBtn(-90*scale,Color3.fromRGB(50,180,50),"\xF0\x9F\x9b\x92","SHOP")
local inviteSideFrame,inviteSideClick=mkSideBtn(0,Color3.fromRGB(100,80,200),"\xF0\x9F\x91\xa5","INVITE")
local dailySideFrame,dailySideClick=mkSideBtn(90*scale,Color3.fromRGB(255,160,0),"\xF0\x9F\x8e\x81","DAILY")
local dailyBadge=mkLabel(dailySideFrame,{Text="1",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=Color3.new(1,1,1),Size=UDim2.new(0,20,0,20),Position=UDim2.new(1,-18,0,-2),BackgroundColor3=Color3.fromRGB(255,50,50),ZIndex=3,Visible=false})
mkCorner(dailyBadge,10)
local stomachSideFrame,stomachSideClick=mkSideBtn(180*scale,Color3.fromRGB(220,80,180),"","STOMACH") -- gut icon is now an IMAGE (added below), not an emoji
-- Gut icon IMAGE in the STOMACH side button (replaces the gut emoji). Non-interactive, so the button's click still works.
local stomachSideIcon=Instance.new("ImageLabel"); stomachSideIcon.Name="GutIcon"
stomachSideIcon.BackgroundTransparency=1; stomachSideIcon.Image=_G.GUT_IMAGE; stomachSideIcon.ScaleType=Enum.ScaleType.Fit
stomachSideIcon.Size=UDim2.new(0,math.floor(46*scale),0,math.floor(46*scale)); stomachSideIcon.Position=UDim2.new(0.5,0,0,5); stomachSideIcon.AnchorPoint=Vector2.new(0.5,0)
stomachSideIcon.ZIndex=2; stomachSideIcon.Parent=stomachSideFrame
shopSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	local g=PlayerGui:FindFirstChild("PremiumShopGui"); if g then g.Enabled=not g.Enabled end
end)
inviteSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	pcall(function() SocialService:PromptGameInvite(game.Players.LocalPlayer) end)
end)
dailySideClick.MouseButton1Click:Connect(function()
	playUIClick()
	local g=PlayerGui:FindFirstChild("DailyRewardsGui"); if g then g.Enabled=not g.Enabled end
end)
stomachSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	local g=PlayerGui:FindFirstChild("StomachShopGui"); if g then g.Enabled=not g.Enabled end
end)

-- ===== BOTTOM-CENTER STACK: Tiny Gut pill + GAS METER + fart button =====
-- ONE vertically-stacked, horizontally-CENTERED group anchored bottom-center. A UIListLayout keeps
-- all three sharing the EXACT same center and tightly stacked (pill on top, meter, then fart button).
-- They all live in this single container, so they can never drift apart horizontally; the per-cluster
-- UIScale (applyScaling) scales the whole group together so the layout + gaps hold on phone AND PC.
local bottomStackGui = Instance.new("ScreenGui")
bottomStackGui.Name = "BottomStackGui"; bottomStackGui.ResetOnSpawn = false
bottomStackGui.IgnoreGuiInset = true; bottomStackGui.DisplayOrder = 5; bottomStackGui.Parent = PlayerGui
local bottomStack = Instance.new("Frame")
bottomStack.Name = "BottomStack"; bottomStack.AnchorPoint = Vector2.new(0.5, 1)
bottomStack.Position = UDim2.new(0.5, 0, 1, -12); bottomStack.Size = UDim2.new(0, 480, 0, 0)
bottomStack.AutomaticSize = Enum.AutomaticSize.Y; bottomStack.BackgroundTransparency = 1; bottomStack.Parent = bottomStackGui
do
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Vertical; sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Center; sl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	sl.Padding = UDim.new(0, 8); sl.Parent = bottomStack
end

-- GAS METER box (LayoutOrder 2 = middle). Moderate FIXED width; UIScale handles screen scaling, so
-- it stays a moderate proportional width and never stretches full-width on wide screens.
sg=Instance.new("ScreenGui"); sg.Name="GasMeterGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
_G.gui.gasMeterPanel=mkFrame(bottomStack,{Size=UDim2.new(0,480,0,85),LayoutOrder=2,BackgroundColor3=Color3.fromRGB(45,120,220)})
mkCorner(_G.gui.gasMeterPanel,16); mkStroke(_G.gui.gasMeterPanel,Color3.fromRGB(20,65,165),4)
do
	_G.gui.gasTitleLabel=mkLabel(_G.gui.gasMeterPanel,{Text="GAS METER",Font=Enum.Font.FredokaOne,TextSize=math.floor(17*scale),TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,0,0,math.floor(28*scale)),Position=UDim2.new(0,0,0,math.floor(6*scale)),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	mkStroke(_G.gui.gasTitleLabel,Color3.fromRGB(0,0,0),2)
	_G.gui.gasBg=mkFrame(_G.gui.gasMeterPanel,{Size=UDim2.new(1,-20,0,math.floor(32*scale)),Position=UDim2.new(0,10,0,math.floor(36*scale)),BackgroundColor3=Color3.fromRGB(18,28,66)})
	mkCorner(_G.gui.gasBg,17)
	_G.gui.gasFill=mkFrame(_G.gui.gasBg,{Name="Fill",Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.fromRGB(60,210,90),ZIndex=2})
	mkCorner(_G.gui.gasFill,17)
	_G.gui.gasGradient=Instance.new("UIGradient"); _G.gui.gasGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(130,240,120)),ColorSequenceKeypoint.new(1,Color3.fromRGB(45,190,70))}); _G.gui.gasGradient.Rotation=90; _G.gui.gasGradient.Parent=_G.gui.gasFill
	_G.gui.gasPowerText=mkLabel(_G.gui.gasBg,{Size=UDim2.new(1,0,1,0),Text="100%",Font=Enum.Font.FredokaOne,TextSize=math.floor(18*scale),TextColor3=Color3.fromRGB(255,255,255),ZIndex=3,TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(_G.gui.gasPowerText,Color3.fromRGB(0,0,0),2)
end
_G.flyingLabel=mkLabel(sg,{Text="",Font=Enum.Font.Gotham,TextSize=1,Size=UDim2.new(0,1,0,1),Position=UDim2.new(0,-200,0,0),BackgroundTransparency=1})

-- ===== FART BUTTON (LayoutOrder 3 = bottom of the stack) =====
sg=Instance.new("ScreenGui"); sg.Name="FartButtonGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
_G.gui.fartBtnFrame=mkFrame(bottomStack,{Size=UDim2.new(0,480,0,62),LayoutOrder=3,BackgroundColor3=Color3.fromRGB(50,180,50)})
mkCorner(_G.gui.fartBtnFrame,14); mkStroke(_G.gui.fartBtnFrame,Color3.fromRGB(0,120,0),4)
_G.gui.fartBtnGradient=Instance.new("UIGradient"); _G.gui.fartBtnGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(100,220,60)),ColorSequenceKeypoint.new(1,Color3.fromRGB(40,160,20))}); _G.gui.fartBtnGradient.Rotation=90; _G.gui.fartBtnGradient.Parent=_G.gui.fartBtnFrame
_G.gui.fartCloudLabel=mkLabel(_G.gui.fartBtnFrame,{Text="\xe2\x98\x81",Font=Enum.Font.GothamBold,TextSize=math.floor(28*scale),TextColor3=Color3.fromRGB(255,255,255),Size=UDim2.new(0,55,1,0),Position=UDim2.new(0,12,0,0),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1,ZIndex=3,RichText=false})
_G.gui.fartBtn=mkButton(_G.gui.fartBtnFrame,{Size=UDim2.new(1,-70,1,0),Position=UDim2.new(0,60,0,0),BackgroundTransparency=1,Text="HOLD TO FART!",Font=Enum.Font.GothamBold,TextSize=math.floor(22*scale),TextColor3=Color3.fromRGB(255,255,255),ZIndex=3,TextXAlignment=Enum.TextXAlignment.Left})
mkStroke(_G.gui.fartBtn,Color3.fromRGB(0,80,0),2)

-- ===== TOP CENTER: ARRIVAL BANNER =====
sg=Instance.new("ScreenGui"); sg.Name="ArrivalGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
_G.gui.arrivalFrame=mkFrame(sg,{Size=UDim2.new(0,500,0,65),Position=UDim2.new(0.5,0,0,-100),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(100,200,100),Visible=false})
mkCorner(_G.gui.arrivalFrame,16); mkStroke(_G.gui.arrivalFrame,Color3.new(1,1,1),3)
do
	local arrivalLine1=mkLabel(_G.gui.arrivalFrame,{Text="\xF0\x9F\x8F\x9d\xef\xb8\x8f Welcome to",Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,26),Position=UDim2.new(0,5,0,6),TextXAlignment=Enum.TextXAlignment.Center,RichText=true,TextScaled=true})
	mkStroke(arrivalLine1,Color3.new(0,0,0),1)
end
_G.gui.islandLabel=mkLabel(_G.gui.arrivalFrame,{Text="Bean Farm!",Font=Enum.Font.GothamBold,TextSize=26,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,34),Position=UDim2.new(0,5,0,33),TextXAlignment=Enum.TextXAlignment.Center,TextScaled=true})
mkStroke(_G.gui.islandLabel,Color3.new(0,0,0),2)

-- ===== ANNOUNCEMENT BANNER =====
sg=Instance.new("ScreenGui"); sg.Name="AnnounceGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
_G.gui.announceFrame=mkFrame(sg,{Size=UDim2.new(0,500,0,65),Position=UDim2.new(0.5,0,0,-100),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(255,200,0),Visible=false})
mkCorner(_G.gui.announceFrame,20); mkStroke(_G.gui.announceFrame,Color3.fromRGB(200,150,0),2)
_G.gui.announceBanner=mkLabel(_G.gui.announceFrame,{Text="",Font=Enum.Font.GothamBold,TextSize=15,TextColor3=Color3.fromRGB(80,40,0),Size=UDim2.new(1,-20,1,0),Position=UDim2.new(0,10,0,0),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})

-- ===== SERVER EVENT BANNER =====
sg=Instance.new("ScreenGui"); sg.Name="ServerEventGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
_G.gui.seBannerFrame=mkFrame(sg,{Size=UDim2.new(0,500,0,80),Position=UDim2.new(0.5,0,0,-130),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(30,100,200),Visible=false})
mkCorner(_G.gui.seBannerFrame,20); mkStroke(_G.gui.seBannerFrame,Color3.new(1,1,1),3)
do
	local seBannerLine1=mkLabel(_G.gui.seBannerFrame,{Text="\xe2\x9a\xa0 SERVER EVENT!",Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,30),Position=UDim2.new(0,5,0,5),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	mkStroke(seBannerLine1,Color3.new(0,0,0),1.5)
end
_G.gui.seBannerLine2=mkLabel(_G.gui.seBannerFrame,{Text="",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,36),Position=UDim2.new(0,5,0,38),TextXAlignment=Enum.TextXAlignment.Center,TextWrapped=true,BackgroundTransparency=1})
mkStroke(_G.gui.seBannerLine2,Color3.new(0,0,0),1.5)


-- ===== WIND/TURB INDICATOR =====
sg=Instance.new("ScreenGui"); sg.Name="WindGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
_G.gui.windIndicatorFrame=mkFrame(sg,{Size=UDim2.new(0,150,0,36),Position=UDim2.new(0.5,0,0.35,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(30,100,200),BackgroundTransparency=0.2,Visible=false})
mkCorner(_G.gui.windIndicatorFrame,18); mkStroke(_G.gui.windIndicatorFrame,Color3.new(1,1,1),2)
_G.gui.windIndicatorLabel=mkLabel(_G.gui.windIndicatorFrame,{Text="\xF0\x9F\x92\xa8 Wind \xe2\x86\x92",Font=Enum.Font.GothamBold,TextSize=14,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,1,0),Position=UDim2.new(0,5,0,0),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})

-- ===== FLIGHT STATS =====
sg=Instance.new("ScreenGui"); sg.Name="FlightStatsGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
-- Parented INSIDE the gas meter panel and anchored to its LEFT edge, so it always sits immediately
-- left of the gas meter and scales WITH it (applyScaling scales the whole bottom cluster). This keeps
-- it in the right relative spot on BOTH PC and mobile and clear of the left-side STOMACH button column,
-- instead of a fixed screen offset that drifted onto the buttons when the meter scaled down on phones.
_G.gui.flightStatsFrame=mkFrame(_G.gui.gasMeterPanel,{Size=UDim2.new(0,130,0,140),Position=UDim2.new(0,-12,0.5,0),AnchorPoint=Vector2.new(1,0.5),BackgroundColor3=Color3.fromRGB(30,100,200),BackgroundTransparency=0.1,Visible=false})
mkCorner(_G.gui.flightStatsFrame,12); mkStroke(_G.gui.flightStatsFrame,Color3.new(1,1,1),2)
_G.gui.fsHeight=mkLabel(_G.gui.flightStatsFrame,{Text="\xF0\x9F\x93\x8f Height: 0",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,38),Position=UDim2.new(0,6,0,6),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
mkStroke(_G.gui.fsHeight,Color3.new(0,0,0),1)
_G.gui.fsRings=mkLabel(_G.gui.flightStatsFrame,{Text="\xF0\x9F\x92\x8d Rings: 0",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,38),Position=UDim2.new(0,6,0,48),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
mkStroke(_G.gui.fsRings,Color3.new(0,0,0),1)
_G.gui.fsAir=mkLabel(_G.gui.flightStatsFrame,{Text="\xe2\x8f\xb1 Air: 0s",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,38),Position=UDim2.new(0,6,0,90),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
mkStroke(_G.gui.fsAir,Color3.new(0,0,0),1)

-- ===== EFFECT FLASH =====
sg=Instance.new("ScreenGui"); sg.Name="FlashGui"; sg.ResetOnSpawn=false; sg.ZIndexBehavior=Enum.ZIndexBehavior.Global; sg.Parent=PlayerGui
_G.effectFlashFrame=mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ZIndex=10})

-- ===== DAILY REWARDS GUI =====
sg=Instance.new("ScreenGui"); sg.Name="DailyRewardsGui"; sg.ResetOnSpawn=false; sg.Enabled=false; sg.DisplayOrder=100; sg.Parent=PlayerGui -- DisplayOrder 100 = definitively above the HUD (<=5) so the popup covers it
local DailyRewardsGui=sg
mkFrame(DailyRewardsGui,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0.5})
local dailyPanel=mkFrame(DailyRewardsGui,{Size=UDim2.new(0.9,0,0.85,0),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(25,90,185),ClipsDescendants=true})
mkCorner(dailyPanel,20); mkStroke(dailyPanel,Color3.new(1,1,1),3)

-- Header
local dailyHeader=mkFrame(dailyPanel,{Size=UDim2.new(1,0,0,65),Position=UDim2.new(0,0,0,0),BackgroundColor3=Color3.fromRGB(15,60,140)})
mkCorner(dailyHeader,20)
local dailyTitleL=Instance.new("TextLabel"); dailyTitleL.Text="\xF0\x9F\x8E\x81 DAILY REWARDS"
dailyTitleL.Font=Enum.Font.GothamBold; dailyTitleL.TextSize=26; dailyTitleL.RichText=false
dailyTitleL.TextColor3=Color3.fromRGB(255,200,0); dailyTitleL.BackgroundTransparency=1
dailyTitleL.Size=UDim2.new(1,-60,0,36); dailyTitleL.Position=UDim2.new(0,10,0,6)
dailyTitleL.TextXAlignment=Enum.TextXAlignment.Center; dailyTitleL.Parent=dailyHeader
mkStroke(dailyTitleL,Color3.new(0,0,0),2)
local dailySubL=mkLabel(dailyHeader,{Text="Login daily for coins!",Font=Enum.Font.Gotham,TextSize=13,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-60,0,18),Position=UDim2.new(0,10,0,43),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
local dailyCloseBtn=mkButton(dailyHeader,{Size=UDim2.new(0,36,0,36),Position=UDim2.new(1,-46,0,12),BackgroundColor3=Color3.fromRGB(220,50,50),Text="X",Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(255,255,255)})
mkCorner(dailyCloseBtn,8)
local dcs=Instance.new("UIStroke"); dcs.Color=Color3.fromRGB(0,0,0); dcs.Thickness=2; dcs.Parent=dailyCloseBtn
dailyCloseBtn.MouseButton1Click:Connect(function() playUIClick(); DailyRewardsGui.Enabled=false end)

-- Streak display
local streakBar=mkFrame(dailyPanel,{Size=UDim2.new(1,-20,0,50),Position=UDim2.new(0,10,0,72),BackgroundColor3=Color3.fromRGB(15,60,140)})
mkCorner(streakBar,12)
local dailyStreakLabel=Instance.new("TextLabel"); dailyStreakLabel.Text="\xF0\x9F\x94\xa5 Day 0 Streak!"
dailyStreakLabel.Font=Enum.Font.GothamBold; dailyStreakLabel.TextSize=20; dailyStreakLabel.RichText=false
dailyStreakLabel.TextColor3=Color3.fromRGB(255,140,0); dailyStreakLabel.BackgroundTransparency=1
dailyStreakLabel.Size=UDim2.new(1,-10,0,26); dailyStreakLabel.Position=UDim2.new(0,5,0,4)
dailyStreakLabel.TextXAlignment=Enum.TextXAlignment.Center; dailyStreakLabel.Parent=streakBar
local dailyNextLabel=mkLabel(streakBar,{Text="Next reward: 5 Coins",Font=Enum.Font.Gotham,TextSize=13,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,16),Position=UDim2.new(0,5,0,31),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})

-- Reward grid (7 boxes for current week cycle)
local dailyGridFrame=mkFrame(dailyPanel,{Size=UDim2.new(1,-20,0,108),Position=UDim2.new(0,10,0,130),BackgroundTransparency=1})
local dailyGridLayout=Instance.new("UIGridLayout")
dailyGridLayout.CellSize=UDim2.new(0,72,0,90); dailyGridLayout.CellPadding=UDim2.new(0,8,0,8)
dailyGridLayout.HorizontalAlignment=Enum.HorizontalAlignment.Center
dailyGridLayout.VerticalAlignment=Enum.VerticalAlignment.Center
dailyGridLayout.Parent=dailyGridFrame
-- COINS ONLY now (matches the server DAILY_REWARDS 7-day ladder). No trails/items.
local GUI_CYCLE_REWARDS={
	{emoji="\xF0\x9F\xAA\x99",label="5 Coins"},
	{emoji="\xF0\x9F\xAA\x99",label="15 Coins"},
	{emoji="\xF0\x9F\xAA\x99",label="30 Coins"},
	{emoji="\xF0\x9F\xAA\x99",label="60 Coins"},
	{emoji="\xF0\x9F\xAA\x99",label="100 Coins"},
	{emoji="\xF0\x9F\xAA\x99",label="175 Coins"},
	{emoji="\xF0\x9F\xAA\x99",label="300 Coins"},
}
local dailyBoxes={}
for i=1,7 do
	local box=mkFrame(dailyGridFrame,{BackgroundColor3=Color3.fromRGB(20,60,120)})
	mkCorner(box,10); mkStroke(box,Color3.fromRGB(50,100,200),2)
	mkLabel(box,{Text="Day "..i,Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,16),Position=UDim2.new(0,0,0,3),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	local rd=GUI_CYCLE_REWARDS[i]
	-- Per-day reward icon: a real COIN IMAGE before claiming, swapped to the CHECKMARK
	-- IMAGE once claimed (handled in updateRewardGrid). Named "_icon" so the refresh can
	-- find + toggle it. Uses the SAME shared assets as the coin counter for consistency.
	local emojiL=Instance.new("ImageLabel"); emojiL.Name="_icon"; emojiL.Image=_G.COIN_IMAGE
	emojiL.BackgroundTransparency=1; emojiL.ScaleType=Enum.ScaleType.Fit
	emojiL.Size=UDim2.new(0,34,0,34); emojiL.Position=UDim2.new(0.5,-17,0,18)
	emojiL.Parent=box
	mkLabel(box,{Text=rd.label,Font=Enum.Font.Gotham,TextSize=10,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-4,0,14),Position=UDim2.new(0,2,1,-16),TextXAlignment=Enum.TextXAlignment.Center,TextWrapped=true,BackgroundTransparency=1})
	dailyBoxes[i]=box
end

-- Milestone section
local msTitle=Instance.new("TextLabel"); msTitle.Text="\xF0\x9F\x8F\x86 MILESTONE REWARDS"
msTitle.Font=Enum.Font.GothamBold; msTitle.TextSize=14; msTitle.RichText=false
msTitle.TextColor3=Color3.fromRGB(255,200,0); msTitle.BackgroundTransparency=1
msTitle.Size=UDim2.new(1,-20,0,20); msTitle.Position=UDim2.new(0,10,0,252)
msTitle.TextXAlignment=Enum.TextXAlignment.Left; msTitle.Parent=dailyPanel
local milestoneFrame=mkFrame(dailyPanel,{Size=UDim2.new(1,-20,0,80),Position=UDim2.new(0,10,0,276),BackgroundTransparency=1})
local msLayout=Instance.new("UIGridLayout"); msLayout.CellSize=UDim2.new(0,120,0,70); msLayout.CellPadding=UDim2.new(0,8,0,0)
msLayout.HorizontalAlignment=Enum.HorizontalAlignment.Center; msLayout.Parent=milestoneFrame
-- Milestone TRAIL rewards REMOVED (daily rewards are coins-only; the colored trail
-- is shop-only now). Empty list + the title/frame are hidden just below.
local MILESTONES={}
msTitle.Visible=false
milestoneFrame.Visible=false
local milestoneBoxes={}
for _,ms in ipairs(MILESTONES) do
	local mb=mkFrame(milestoneFrame,{BackgroundColor3=Color3.fromRGB(15,60,140)}); mkCorner(mb,10); mkStroke(mb,Color3.fromRGB(255,200,0),2)
	mkLabel(mb,{Text="Day "..ms.day,Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,16),Position=UDim2.new(0,0,0,3),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	local msEmoji=Instance.new("TextLabel"); msEmoji.Text=ms.emoji; msEmoji.RichText=false
	msEmoji.Font=Enum.Font.Gotham; msEmoji.TextSize=24; msEmoji.BackgroundTransparency=1
	msEmoji.Size=UDim2.new(1,0,0,28); msEmoji.Position=UDim2.new(0,0,0,18)
	msEmoji.TextXAlignment=Enum.TextXAlignment.Center; msEmoji.Parent=mb
	mkLabel(mb,{Text=ms.name,Font=Enum.Font.Gotham,TextSize=10,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,0,1,-15),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	milestoneBoxes[ms.day]=mb
end

-- Claim button
local dailyClaimBtn=mkButton(dailyPanel,{Size=UDim2.new(0,320,0,55),Position=UDim2.new(0.5,0,1,-70),AnchorPoint=Vector2.new(0.5,1),BackgroundColor3=Color3.fromRGB(50,200,50),Font=Enum.Font.GothamBold,TextSize=1,TextColor3=Color3.new(1,1,1),Visible=false})
mkCorner(dailyClaimBtn,12); mkStroke(dailyClaimBtn,Color3.fromRGB(0,150,0),3)
dailyClaimBtn.Text = ""
local claimBtnL=Instance.new("TextLabel"); claimBtnL.Text="\xF0\x9F\x8E\x81  Claim Reward!"; claimBtnL.RichText=false
claimBtnL.Font=Enum.Font.GothamBold; claimBtnL.TextSize=20; claimBtnL.TextColor3=Color3.new(1,1,1)
claimBtnL.BackgroundTransparency=1; claimBtnL.Size=UDim2.new(1,0,1,0); claimBtnL.TextXAlignment=Enum.TextXAlignment.Center
claimBtnL.Parent=dailyClaimBtn; mkStroke(claimBtnL,Color3.new(0,0,0),2)
local dailyClaimScale=Instance.new("UIScale"); dailyClaimScale.Scale=1; dailyClaimScale.Parent=dailyClaimBtn
local dailyUnavailLabel=mkButton(dailyPanel,{Size=UDim2.new(0,320,0,55),Position=UDim2.new(0.5,0,1,-70),AnchorPoint=Vector2.new(0.5,1),BackgroundColor3=Color3.fromRGB(80,80,80),Text="\xe2\x9c\x85 Come back tomorrow!",Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.fromRGB(180,180,180),Visible=true,Active=false})
mkCorner(dailyUnavailLabel,12)
task.spawn(function()
	while true do
		task.wait(0.4)
		if dailyClaimBtn.Visible then
			TweenService:Create(dailyClaimScale,TweenInfo.new(0.8,Enum.EasingStyle.Sine),{Scale=1.03}):Play()
			task.wait(0.8)
			TweenService:Create(dailyClaimScale,TweenInfo.new(0.8,Enum.EasingStyle.Sine),{Scale=1.0}):Play()
			task.wait(0.8)
		end
	end
end)

for _,v in ipairs(dailyPanel:GetDescendants()) do
	if v:IsA("TextLabel") or v:IsA("TextButton") then v.TextScaled=true end
end

-- ===== DAILY REWARDS LAYOUT =====
;(function()
	-- Main panel: fixed size, centered
	dailyPanel.Size = UDim2.new(0,700,0,560)
	dailyPanel.Position = UDim2.new(0.5,0,0.5,0)
	dailyPanel.AnchorPoint = Vector2.new(0.5,0.5)

	-- Streak banner
	streakBar.Size = UDim2.new(1,-20,0,65)
	streakBar.Position = UDim2.new(0,10,0,80)

	-- Day cards: 7 × (88×110) with 6px padding
	dailyGridFrame.Size = UDim2.new(1,-20,0,118)
	dailyGridFrame.Position = UDim2.new(0,10,0,152)
	dailyGridLayout.CellSize = UDim2.new(0,88,0,110)
	dailyGridLayout.CellPadding = UDim2.new(0,6,0,6)

	-- Milestone section title
	msTitle.Position = UDim2.new(0,10,0,278)

	-- Milestone cards: 4 × (145×110) with 8px padding
	milestoneFrame.Size = UDim2.new(1,-20,0,118)
	milestoneFrame.Position = UDim2.new(0,10,0,306)
	msLayout.CellSize = UDim2.new(0,145,0,110)
	msLayout.CellPadding = UDim2.new(0,8,0,0)

	-- Come back tomorrow / claim button: full-width at bottom, 10px margin
	dailyClaimBtn.Size = UDim2.new(1,-20,0,55)
	dailyClaimBtn.Position = UDim2.new(0.5,0,1,-10)
	dailyClaimBtn.AnchorPoint = Vector2.new(0.5,1)
	-- Ensure TextScaled on all content
	for _, v in ipairs(dailyPanel:GetDescendants()) do
		if v:IsA("TextLabel") or v:IsA("TextButton") then v.TextScaled = true end
	end
end)()

dailyUnavailLabel:Destroy()

-- Destroy any stray green Frame (not a button) that may sit behind the claim button
for _, v in ipairs(dailyPanel:GetDescendants()) do
	if v:IsA("Frame") then
		local r,g,b = v.BackgroundColor3.R*255, v.BackgroundColor3.G*255, v.BackgroundColor3.B*255
		if g > 180 and r < 150 and b < 150 then
			v:Destroy()
		end
	end
end

-- Pulse claim button ONLY when it is visible (prevents green bleed behind come-back button)
dailyClaimBtn.BackgroundColor3 = Color3.fromRGB(50,210,50)
task.spawn(function()
	while true do
		task.wait(0.3)
		if dailyClaimBtn.Visible then
			TweenService:Create(dailyClaimBtn,
				TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{BackgroundColor3 = Color3.fromRGB(100,255,100)}):Play()
			task.wait(0.7)
			TweenService:Create(dailyClaimBtn,
				TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{BackgroundColor3 = Color3.fromRGB(50,210,50)}):Play()
			task.wait(0.7)
		end
	end
end)

if isMobile then
	task.defer(function()
		for _,gui in ipairs({"AnnounceGui","ServerEventGui","SeCountGui","WindGui","FlightStatsGui"}) do
			local g=PlayerGui:FindFirstChild(gui)
			if g then
				for _,v in ipairs(g:GetDescendants()) do
					if (v:IsA("TextLabel") or v:IsA("TextButton")) and not v.TextScaled then
						v.TextSize=math.max(10,math.floor(v.TextSize*scale))
					end
				end
			end
		end
	end)
end
print("GUIS BUILT")

-- ===== ADAPTIVE SCALING =====
local StarterGui = game:GetService("StarterGui")
pcall(function() StarterGui:SetCore("TopbarEnabled", true) end)

local function getScale()
	local vp = workspace.CurrentCamera.ViewportSize
	return math.min(vp.X/1280, vp.Y/720, 1)
end

local function applyScaling()
	local s = getScale()
	for _, gui in ipairs(PlayerGui:GetChildren()) do
		-- LoadingScreen scales itself (separate ReplicatedFirst script); leave it alone.
		if gui:IsA("ScreenGui") and gui.Name ~= "LoadingScreen" then
			-- Scale each top-level cluster around ITS OWN anchor so it stays pinned to its screen
			-- edge/corner. (A ScreenGui-level UIScale scales from the top-left origin, so right/bottom-
			-- anchored clusters would drift off their edge as the scale shrinks.) Full-screen backgrounds
			-- / dimmers (Size ~ 1,1 scale) are skipped so they keep covering the whole screen.
			for _, child in ipairs(gui:GetChildren()) do
				if child:IsA("GuiObject") and not (child.Size.X.Scale >= 1 and child.Size.Y.Scale >= 1) then
					local us = child:FindFirstChildWhichIsA("UIScale")
					if not us then us = Instance.new("UIScale"); us.Parent = child end
					us.Scale = s
				end
			end
			for _, v in ipairs(gui:GetDescendants()) do
				if v:IsA("TextLabel") or v:IsA("TextButton") then v.TextScaled = true end
			end
		end
	end
end

-- ===== HIDE HUD WHILE A SHOP / MENU POPUP IS OPEN =====
-- Popups sit on much higher DisplayOrder ScreenGuis, but to GUARANTEE the HUD never bleeds through on
-- top of an open shop (Tiny Gut pill / gas meter / fart button / sidebar / coins / stats), we also
-- DISABLE the HUD ScreenGuis whenever any popup is open, and re-enable them once every popup is closed.
-- refreshHud is a GLOBAL (not a chunk local) and its tables live INSIDE it, and the watcher's vars
-- live inside a do-block — so this whole feature adds ZERO module-level locals. CoreClient's main
-- chunk is right at Luau's 200-local-per-function limit; going over it makes the WHOLE script fail
-- to compile (which blanks the UI), so we must not add chunk-level locals here.
_G.refreshHud = function()
	if not hudRevealed then return end -- stay hidden until the player has actually spawned in
	local POPUP_NAMES = {"FoodShopGui","StomachShopGui","PremiumShopGui","DailyRewardsGui"}
	local HUD_NAMES = {"BottomStackGui","SidebarGui","CoinGui","RightPanelGui","StomachGui"}
	local open = false
	for _, name in ipairs(POPUP_NAMES) do
		local g = PlayerGui:FindFirstChild(name)
		if g and g.Enabled then open = true; break end
	end
	for _, name in ipairs(HUD_NAMES) do
		local g = PlayerGui:FindFirstChild(name)
		if g then g.Enabled = not open end -- hide HUD ScreenGuis while a popup is open
	end
end
do
	local POPUPS = {"FoodShopGui","StomachShopGui","PremiumShopGui","DailyRewardsGui"}
	local function watch(g)
		g:GetPropertyChangedSignal("Enabled"):Connect(_G.refreshHud)
		_G.refreshHud()
	end
	for _, name in ipairs(POPUPS) do
		local g = PlayerGui:FindFirstChild(name); if g then watch(g) end
	end
	-- FoodShopGui / PremiumShopGui are created later by ShopClient, so catch them as they appear.
	PlayerGui.ChildAdded:Connect(function(child)
		if child:IsA("ScreenGui") then
			for _, name in ipairs(POPUPS) do
				if child.Name == name then watch(child); break end
			end
		end
	end)
end

local function repositionGUIs()
	-- coin display
	coinGui.Enabled = true; coinPill.Visible = true
	coinPill.Size = UDim2.new(0,200,0,52); coinPill.Position = UDim2.new(1,-10,0,10); coinPill.AnchorPoint = Vector2.new(1,0)
	-- right panel (unified stats + impulse buttons)
	rightPanel.Size = UDim2.new(0,230,0,500); rightPanel.Position = UDim2.new(1,-5,0,85); rightPanel.AnchorPoint = Vector2.new(1,0)
	-- left buttons, square and high up
	shopSideFrame.Size = UDim2.new(0,110,0,110); shopSideFrame.Position = UDim2.new(0,10,0.08,0); shopSideFrame.AnchorPoint = Vector2.new(0,0)
	inviteSideFrame.Size = UDim2.new(0,110,0,110); inviteSideFrame.Position = UDim2.new(0,10,0.30,0); inviteSideFrame.AnchorPoint = Vector2.new(0,0)
	dailySideFrame.Size = UDim2.new(0,110,0,110); dailySideFrame.Position = UDim2.new(0,10,0.52,0); dailySideFrame.AnchorPoint = Vector2.new(0,0)
	stomachSideFrame.Size = UDim2.new(0,110,0,110); stomachSideFrame.Position = UDim2.new(0,10,0.74,0); stomachSideFrame.AnchorPoint = Vector2.new(0,0)
	-- all text visible and scaled
	for _, v in ipairs(PlayerGui:GetDescendants()) do
		if v:IsA("TextLabel") or v:IsA("TextButton") then v.TextScaled = true; v.Visible = true end
	end
	-- Tiny Gut pill + gas meter + fart button are ONE centered group (BottomStack + UIListLayout);
	-- their size/position/centering is owned by that layout + the per-cluster UIScale below — nothing to set here.
	applyScaling()
	if _G.refreshHud then _G.refreshHud() end -- re-apply popup-based HUD hiding (this fn force-enables coinGui above)
end

workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(repositionGUIs)
repositionGUIs()
player.CharacterAdded:Connect(function()
	task.wait(0.1)
	repositionGUIs()
end)
task.delay(3, repositionGUIs)

-- ===== TRAIL SELECTOR =====
sg=Instance.new("ScreenGui"); sg.Name="TrailSelectorGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local trailPanel=mkFrame(sg,{Size=UDim2.new(0,90,0,10),Position=UDim2.new(0,10,0.7,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.fromRGB(25,90,185),Visible=false})
mkCorner(trailPanel,12); mkStroke(trailPanel,Color3.new(1,1,1),2)
local trailTitleL=mkLabel(trailPanel,{Text="\xF0\x9F\x92\xa8 TRAIL",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=Color3.fromRGB(255,200,0),Size=UDim2.new(1,0,0,20),Position=UDim2.new(0,0,0,6),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
local trailBtnContainer=mkFrame(trailPanel,{Size=UDim2.new(1,0,0,0),Position=UDim2.new(0,0,0,30),BackgroundTransparency=1})
local trailBtnLayout=Instance.new("UIListLayout"); trailBtnLayout.FillDirection=Enum.FillDirection.Vertical
trailBtnLayout.HorizontalAlignment=Enum.HorizontalAlignment.Center; trailBtnLayout.Padding=UDim.new(0,6); trailBtnLayout.Parent=trailBtnContainer
_G.customTrailColor=nil; _G.useCustomTrail=false; _G.selectedTrail="default"; _G.unlockedTrails={}
local selectedTrailBtn=nil
local function highlightTrailBtn(btn)
	if selectedTrailBtn then
		local st=selectedTrailBtn:FindFirstChildWhichIsA("UIStroke"); if st then st.Color=Color3.new(1,1,1); st.Thickness=2 end
		local lbl=selectedTrailBtn:FindFirstChildOfClass("TextLabel"); if lbl then lbl.Text="" end
	end
	selectedTrailBtn=btn
	if btn then
		local st=btn:FindFirstChildWhichIsA("UIStroke"); if st then st.Color=Color3.fromRGB(255,200,0); st.Thickness=4 end
		local lbl=btn:FindFirstChildOfClass("TextLabel"); if lbl then lbl.Text="\xe2\x9c\x93" end
	end
end
local function mkTrailBtn(parent,bgCol,emoji,onClick)
	local btn=mkButton(parent,{Size=UDim2.new(0,60,0,60),BackgroundColor3=bgCol,Text="",BackgroundTransparency=0})
	mkCorner(btn,30); mkStroke(btn,Color3.new(1,1,1),2)
	local lbl=Instance.new("TextLabel"); lbl.Text=""; lbl.RichText=false
	lbl.Font=Enum.Font.GothamBold; lbl.TextSize=emoji and 24 or 20; lbl.BackgroundTransparency=1
	lbl.TextColor3=Color3.new(1,1,1); lbl.Size=UDim2.new(1,0,1,0); lbl.TextXAlignment=Enum.TextXAlignment.Center
	if emoji then lbl.Text=emoji end; lbl.Parent=btn
	btn.MouseButton1Click:Connect(onClick)
	return btn
end
local defaultTrailBtn=mkTrailBtn(trailBtnContainer,Color3.fromRGB(0,200,50),nil,function()
	_G.useCustomTrail=false; _G.selectedTrail="default"; highlightTrailBtn(defaultTrailBtn)
end)
highlightTrailBtn(defaultTrailBtn)
local trailBtnRefs={}
local rainbowTrailBtn=nil
-- TRAIL-PICKER REMOVED: the daily-reward colored-trail picker UI is disabled and never
-- shows. updateTrailSelector() is now a no-op that just keeps the picker panel hidden, so
-- nothing (daily rewards / login / claim) can ever pop it up. The colored fart trail is
-- now ONLY the GlitterTrail gamepass, which is applied AUTOMATICALLY to the fart cloud
-- (see the `gp.glitterTrail` branch in the cloud spawner) -- it does NOT use this picker,
-- so removing the picker does not affect the purchasable gamepass.
local function updateTrailSelector()
	if trailPanel then trailPanel.Visible = false end
end
_G.updateTrailSelector=updateTrailSelector

-- ===== REMOTE EVENTS =====
local RS = game:GetService("ReplicatedStorage")
local BuyFoodEvent=RS:FindFirstChild("BuyFoodEvent") or RS:WaitForChild("BuyFoodEvent",10)
local RegenEvent=RS:FindFirstChild("RegenEvent") or RS:WaitForChild("RegenEvent",10)
local CoinEvent=RS:FindFirstChild("CoinEvent") or RS:WaitForChild("CoinEvent",10)
local SkipIslandEvent=RS:FindFirstChild("SkipIslandEvent") or RS:WaitForChild("SkipIslandEvent",10)
local UnlockIslandEvent=RS:FindFirstChild("IslandUnlockEvent") or RS:WaitForChild("IslandUnlockEvent",10)
local AnnouncementEvent=RS:FindFirstChild("AnnouncementEvent") or RS:WaitForChild("AnnouncementEvent",10)
local ServerEventNotify=RS:FindFirstChild("ServerEventNotify") or RS:WaitForChild("ServerEventNotify",10)
local GamepassEvent=RS:FindFirstChild("GamepassEvent") or RS:WaitForChild("GamepassEvent",10)
local LandingEvent=RS:FindFirstChild("LandingEvent") or RS:WaitForChild("LandingEvent",10)
local leaderstats=player:FindFirstChild("leaderstats") or player:WaitForChild("leaderstats",10)
_G.leaderstats=leaderstats; _G.CoinEvent=CoinEvent; _G.BuyFoodEvent=BuyFoodEvent
_G.SkipIslandEvent=SkipIslandEvent; _G.UnlockIslandEvent=UnlockIslandEvent
_G.ServerEventNotify=ServerEventNotify; _G.LandingEvent=LandingEvent

-- ===== RETURN TO ISLAND BUTTON =====
-- Shown by the SERVER (via the ReturnPromptIsland attribute) only when the player has
-- fallen below their highest-reached island and isn't flying up. Tapping asks the server
-- to teleport them to that island's real Stand part — server-authoritative, no client TP.
local ReturnToIslandEvent = RS:FindFirstChild("ReturnToIslandEvent") or RS:WaitForChild("ReturnToIslandEvent",10)
do
	local rtSg = Instance.new("ScreenGui"); rtSg.Name="ReturnIslandGui"; rtSg.ResetOnSpawn=false; rtSg.IgnoreGuiInset=true; rtSg.Parent=PlayerGui
	-- Off to the side: left edge, vertically centered, clear of the left sidebar, the
	-- bottom fart/gas controls, and the right stats panel. Never covers the middle.
	local rtBtn = mkButton(rtSg,{
		Name="ReturnBtn",
		Size=UDim2.new(0,180*scale,0,56*scale),
		Position=UDim2.new(0,130,0.5,0),
		AnchorPoint=Vector2.new(0,0.5),
		BackgroundColor3=Color3.fromRGB(255,150,0),
		Text="Return to Island 1",
		Font=Enum.Font.GothamBold,
		TextSize=math.floor(17*scale),
		TextColor3=Color3.fromRGB(255,255,255),
		BorderSizePixel=0,
		Visible=false,
		ZIndex=8,
	})
	mkCorner(rtBtn,14); mkStroke(rtBtn,Color3.fromRGB(180,90,0),3)
	local function refreshReturnBtn()
		local n = player:GetAttribute("ReturnPromptIsland") or 0
		if n > 0 then
			rtBtn.Text = "\xE2\xAC\x86 Return to Island "..n
			rtBtn.Visible = true
		else
			rtBtn.Visible = false
		end
	end
	player:GetAttributeChangedSignal("ReturnPromptIsland"):Connect(refreshReturnBtn)
	refreshReturnBtn()
	rtBtn.MouseButton1Click:Connect(function()
		if ReturnToIslandEvent then pcall(function() ReturnToIslandEvent:FireServer() end) end
	end)
end

-- ===== STOMACH HUD + SHOP =====
task.spawn(function()
	-- HUD
	local stomachGui=Instance.new("ScreenGui"); stomachGui.Name="StomachGui"; stomachGui.ResetOnSpawn=false; stomachGui.DisplayOrder=5; stomachGui.Parent=PlayerGui
	local stomachHud=Instance.new("Frame"); stomachHud.Name="StomachHud"
	stomachHud.Size=UDim2.new(0,300,0,40); stomachHud.LayoutOrder=1; stomachHud.ZIndex=10 -- top of the bottom-center stack (the pill), centered above the meter
	stomachHud.BackgroundColor3=Color3.fromRGB(220,80,180); stomachHud.BorderSizePixel=0; stomachHud.Parent=bottomStack
	mkCorner(stomachHud,20); mkStroke(stomachHud,Color3.fromRGB(140,20,100),3)
	-- Per-tier gut EMOJI on the LEFT of the pill (shows the CURRENT gut's own emoji).
	local stomachHudIcon=Instance.new("TextLabel"); stomachHudIcon.Name="GutIcon"
	stomachHudIcon.BackgroundTransparency=1; stomachHudIcon.Text=(_G.GUT_EMOJI[stomachName] or ""); stomachHudIcon.Font=Enum.Font.GothamBold; stomachHudIcon.TextScaled=true
	stomachHudIcon.Size=UDim2.new(0,32,0,32); stomachHudIcon.Position=UDim2.new(0,6,0.5,0); stomachHudIcon.AnchorPoint=Vector2.new(0,0.5)
	stomachHudIcon.ZIndex=12; stomachHudIcon.Parent=stomachHud
	-- XL Gut shows an IMAGE instead of an emoji: an ImageLabel overlaid in the SAME icon slot, shown
	-- only while the current gut is XL Gut (the emoji TextLabel is blanked then). All other tiers use the emoji.
	local stomachHudIconImg=Instance.new("ImageLabel"); stomachHudIconImg.Name="GutIconImg"
	stomachHudIconImg.BackgroundTransparency=1; stomachHudIconImg.Image=_G.GUT_IMAGE; stomachHudIconImg.ScaleType=Enum.ScaleType.Fit
	stomachHudIconImg.Size=UDim2.new(0,32,0,32); stomachHudIconImg.Position=UDim2.new(0,6,0.5,0); stomachHudIconImg.AnchorPoint=Vector2.new(0,0.5)
	stomachHudIconImg.ZIndex=12; stomachHudIconImg.Visible=false; stomachHudIconImg.Parent=stomachHud
	-- Gut NAME text, to the right of the icon (name only; the icon is the image above).
	local stomachHudLabel=Instance.new("TextLabel"); stomachHudLabel.Name="StomachHudLabel"
	stomachHudLabel.Size=UDim2.new(1,-44,1,0); stomachHudLabel.Position=UDim2.new(0,40,0,0); stomachHudLabel.BackgroundTransparency=1; stomachHudLabel.ZIndex=11
	stomachHudLabel.Text="Stomach"; stomachHudLabel.Font=Enum.Font.FredokaOne
	stomachHudLabel.TextScaled=true; stomachHudLabel.TextColor3=Color3.fromRGB(255,255,255); stomachHudLabel.TextXAlignment=Enum.TextXAlignment.Center; stomachHudLabel.Parent=stomachHud
	mkStroke(stomachHudLabel,Color3.fromRGB(0,0,0),2)

	updateStomachDisplay = function()
		stomachHudLabel.Text = stomachName   -- gut NAME (the per-tier icon is to its left)
		if stomachName == "XL Gut" then
			stomachHudIcon.Text = ""              -- XL Gut: blank the emoji, show the image overlay instead
			stomachHudIconImg.Visible = true
		else
			stomachHudIcon.Text = _G.GUT_EMOJI[stomachName] or stomachHudIcon.Text  -- the other six: their own emoji
			stomachHudIconImg.Visible = false
		end
	end
	updateStomachDisplay()

	-- Shop GUI
	local stomachShopGui=Instance.new("ScreenGui"); stomachShopGui.Name="StomachShopGui"; stomachShopGui.ResetOnSpawn=false; stomachShopGui.Enabled=false; stomachShopGui.DisplayOrder=100; stomachShopGui.Parent=PlayerGui -- DisplayOrder 100 = definitively above the HUD (<=5) so the shop covers it
	local currentStomachLabel; local scrollFrame; local ttlIcon; local ttlIconImg
	do
		local stomachPanel=Instance.new("Frame"); stomachPanel.Size=UDim2.new(0,680,0,500)
		stomachPanel.Position=UDim2.new(0.5,0,0.5,0); stomachPanel.AnchorPoint=Vector2.new(0.5,0.5)
		stomachPanel.BackgroundColor3=Color3.fromRGB(30,120,220); stomachPanel.BorderSizePixel=0; stomachPanel.Parent=stomachShopGui
		mkCorner(stomachPanel,20); mkStroke(stomachPanel,Color3.fromRGB(20,60,160),3)
		do
			local bg=Instance.new("Frame"); bg.Size=UDim2.new(1,0,1,0); bg.BackgroundColor3=Color3.new(0,0,0)
			bg.BackgroundTransparency=0.5; bg.BorderSizePixel=0; bg.ZIndex=0; bg.Parent=stomachShopGui
			-- Per-tier gut EMOJI to the LEFT of the shop title (shows the CURRENT gut's own emoji).
			ttlIcon=Instance.new("TextLabel"); ttlIcon.Name="GutIcon"; ttlIcon.BackgroundTransparency=1
			ttlIcon.Text=(_G.GUT_EMOJI[stomachName] or ""); ttlIcon.Font=Enum.Font.GothamBold; ttlIcon.TextScaled=true
			ttlIcon.Size=UDim2.new(0,46,0,46); ttlIcon.Position=UDim2.new(0,12,0,9); ttlIcon.Parent=stomachPanel
			-- XL Gut shows an IMAGE here instead of the emoji: ImageLabel overlaid in the SAME slot,
			-- shown only while the current gut is XL Gut (toggled with the emoji in the handler below).
			ttlIconImg=Instance.new("ImageLabel"); ttlIconImg.Name="GutIconImg"; ttlIconImg.BackgroundTransparency=1
			ttlIconImg.Image=_G.GUT_IMAGE; ttlIconImg.ScaleType=Enum.ScaleType.Fit
			ttlIconImg.Size=UDim2.new(0,46,0,46); ttlIconImg.Position=UDim2.new(0,12,0,9); ttlIconImg.Parent=stomachPanel
			if stomachName == "XL Gut" then ttlIcon.Text=""; ttlIconImg.Visible=true else ttlIconImg.Visible=false end
			local ttl=mkLabel(stomachPanel,{Size=UDim2.new(1,-116,0,55),Position=UDim2.new(0,64,0,5),Text="STOMACH SHOP",Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(255,220,0),TextXAlignment=Enum.TextXAlignment.Left})
			mkStroke(ttl,Color3.fromRGB(0,0,0),2)
		end
		do
			local sc=mkButton(stomachPanel,{Size=UDim2.new(0,40,0,40),Position=UDim2.new(1,-48,0,8),BackgroundColor3=Color3.fromRGB(255,60,60),Text="X",Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0})
			mkCorner(sc,8); mkStroke(sc,Color3.fromRGB(160,20,20),2)
			sc.MouseButton1Click:Connect(function() playUIClick(); stomachShopGui.Enabled=false end)
		end
		currentStomachLabel=mkLabel(stomachPanel,{Size=UDim2.new(1,-20,0,35),Position=UDim2.new(0,10,0,62),BackgroundColor3=Color3.fromRGB(20,80,180),BackgroundTransparency=0,Text="Current: Tiny Gut (100 max power)",Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0})
		mkCorner(currentStomachLabel,10); mkStroke(currentStomachLabel,Color3.fromRGB(255,255,255),2)
		scrollFrame=Instance.new("ScrollingFrame"); scrollFrame.Size=UDim2.new(1,-20,1,-110)
		scrollFrame.Position=UDim2.new(0,10,0,105); scrollFrame.BackgroundTransparency=1
		scrollFrame.ScrollBarThickness=6; scrollFrame.CanvasSize=UDim2.new(0,0,0,0)
		scrollFrame.AutomaticCanvasSize=Enum.AutomaticSize.Y; scrollFrame.BorderSizePixel=0; scrollFrame.Parent=stomachPanel
		do
			local ll=Instance.new("UIListLayout"); ll.Padding=UDim.new(0,8); ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Parent=scrollFrame
			local lp=Instance.new("UIPadding"); lp.PaddingLeft=UDim.new(0,4); lp.PaddingRight=UDim.new(0,4); lp.Parent=scrollFrame
		end
	end

	local tierDefs={
		{name="Tiny Gut",     maxPower=100,  cost=0,      robux=false, emoji="\xF0\x9F\x91\xB6"},
		{name="Small Gut",    maxPower=182,  cost=1600,   robux=false, emoji="\xF0\x9F\xA7\x92"},
		{name="Medium Gut",   maxPower=520,  cost=3000,   robux=false, emoji="\xF0\x9F\x90\xB7"},
		{name="Large Gut",    maxPower=1075, cost=5200,   robux=false, emoji="\xF0\x9F\x90\x98"},
		{name="XL Gut",       maxPower=2146, cost=8000,   robux=false, emoji="\xF0\x9F\x92\xAA"},
		{name="Iron Gut",     maxPower=3218, cost=11000,  robux=false, emoji="\xF0\x9F\x8F\x8B\xEF\xB8\x8F"},
		{name="Infinite Gut", maxPower=9999, cost=499,    robux=true,  emoji="\xe2\x99\xbe\xef\xb8\x8f"},
	}
	local BuyStomachEvent=RS:WaitForChild("BuyStomachEvent",30)
	local StomachUpdateEvent=RS:WaitForChild("StomachUpdateEvent",30)

	for i,tier in ipairs(tierDefs) do
		do
			local card=Instance.new("Frame"); card.Size=UDim2.new(1,0,0,70); card.BorderSizePixel=0
				-- VISUAL list position ONLY (tier data/icon/price unchanged): Infinite Gut pinned at the TOP,
				-- then the others keep their existing ascending order (Tiny->Iron) just below it.
				card.LayoutOrder = (tier.name == "Infinite Gut") and 1 or (i + 1)
			card.BackgroundColor3=Color3.fromRGB(20,90,200); card.Parent=scrollFrame
			mkCorner(card,12); mkStroke(card,Color3.fromRGB(255,255,255),2)
			do
				-- Per-tier gut icon on each shop tier card. XL Gut shows an IMAGE (ScaleType=Fit) in the
				-- icon slot; the other six show their OWN emoji as text. Same slot size/position either way.
				if tier.name == "XL Gut" then
					local ic=Instance.new("ImageLabel"); ic.Name="GutIcon"; ic.BackgroundTransparency=1
					ic.Image=_G.GUT_IMAGE; ic.ScaleType=Enum.ScaleType.Fit
					ic.Size=UDim2.new(0,52,0,52); ic.Position=UDim2.new(0,12,0.5,0); ic.AnchorPoint=Vector2.new(0,0.5)
					ic.Parent=card
				else
					local ic=Instance.new("TextLabel"); ic.Name="GutIcon"; ic.BackgroundTransparency=1
					ic.Text=(_G.GUT_EMOJI[tier.name] or ""); ic.Font=Enum.Font.GothamBold; ic.TextScaled=true
					ic.Size=UDim2.new(0,52,0,52); ic.Position=UDim2.new(0,12,0.5,0); ic.AnchorPoint=Vector2.new(0,0.5)
					ic.Parent=card
				end
			end
			do
				local nl=mkLabel(card,{Size=UDim2.new(0,220,0,32),Position=UDim2.new(0,72,0,8),Text=tier.name,Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(255,255,255),TextXAlignment=Enum.TextXAlignment.Left})
				mkStroke(nl,Color3.fromRGB(0,0,0),2)
			end
			mkLabel(card,{Size=UDim2.new(0,220,0,24),Position=UDim2.new(0,72,0,38),TextXAlignment=Enum.TextXAlignment.Left,Text=(tier.maxPower>=9999 and "\xe2\x88\x9e Unlimited power" or tostring(tier.maxPower).." max power"),Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(180,220,255)})
			local buyBtn=Instance.new("TextButton"); buyBtn.Size=UDim2.new(0,150,0,46)
			buyBtn.Position=UDim2.new(1,-158,0.5,0); buyBtn.AnchorPoint=Vector2.new(0,0.5); buyBtn.BorderSizePixel=0
			if tier.cost==0 then buyBtn.BackgroundColor3=Color3.fromRGB(100,100,100); buyBtn.Text="\xe2\x9c\x93 FREE"
			elseif tier.robux then buyBtn.BackgroundColor3=Color3.fromRGB(255,160,20); buyBtn.Text=tostring(tier.cost).." R$"
			else buyBtn.BackgroundColor3=Color3.fromRGB(50,220,50); buyBtn.Text="\xF0\x9F\xAA\x99 "..tostring(tier.cost) end
			buyBtn.Font=Enum.Font.FredokaOne; buyBtn.TextScaled=true; buyBtn.TextColor3=Color3.fromRGB(255,255,255); buyBtn.Parent=card
			mkCorner(buyBtn,10); mkStroke(buyBtn,Color3.fromRGB(0,0,0),2)
			buyBtn.MouseButton1Click:Connect(function()
				if tier.cost==0 then return end
				if tier.robux then pcall(function() game:GetService("MarketplaceService"):PromptGamePassPurchase(player,1860686821) end) -- Infinite/Unlimited Gut gamepass (the only robux tier); was 0 (invalid -> prompt never opened)
				elseif BuyStomachEvent then
						-- Coin-priced tier: on a can't-afford tap (and only if NOT already owned), give
						-- feedback — error sound + a quick shake of THIS button. Purchase logic is unchanged:
						-- we still fire, and the server stays the authority that accepts/rejects.
						local coinsVal, ownedMax = 0, 0
						pcall(function()
							local ls=player:FindFirstChild("leaderstats")
							if ls then
								local c=ls:FindFirstChild("Coins"); if c then coinsVal=c.Value end
								local sm=ls:FindFirstChild("StomachMax"); if sm then ownedMax=sm.Value end
							end
						end)
						-- Owned tiers (maxPower <= current) get no feedback; free/Robux are handled above.
						if tier.maxPower>ownedMax and coinsVal<tier.cost then
							playErrorSound()
							shakeButton(buyBtn)
						end
						pcall(function() BuyStomachEvent:FireServer(tier.maxPower, tier.cost) end)
					end
			end)
			task.spawn(function()
				while true do
					task.wait(1)
					pcall(function()
						local ls=player:FindFirstChild("leaderstats"); if not ls then return end
						local sm=ls:FindFirstChild("StomachMax"); if not sm then return end
						if tier.maxPower<=sm.Value then buyBtn.BackgroundColor3=Color3.fromRGB(80,80,80); buyBtn.Text="\xe2\x9c\x93 OWNED" end
					end)
				end
			end)
		end
	end

	local stomachNames = {
		[100]  = {"\xF0\x9F\x91\xB6", "Tiny Gut"},
		[182]  = {"\xF0\x9F\xAB\x83", "Small Gut"},
		[520]  = {"\xF0\x9F\x90\xB7", "Medium Gut"},
		[1075] = {"\xF0\x9F\x90\x98", "Large Gut"},
		[2146] = {"\xF0\x9F\x92\xAA", "XL Gut"},
		[3218] = {"\xF0\x9F\x8F\x8B\xEF\xB8\x8F", "Iron Gut"},
		[9999] = {"\xe2\x99\xbe\xef\xb8\x8f", "Infinite Gut"},
	}
	if StomachUpdateEvent then
		StomachUpdateEvent.OnClientEvent:Connect(function(newMax)
			pcall(function()
				local oldMax = stomachMax; stomachMax = tonumber(newMax) or stomachMax
				currentPower = math.min(currentPower, stomachMax) -- carry power over into the bigger tank (clamp to new max), don't reset
				local info = stomachNames[stomachMax]
				if info then stomachEmoji = info[1]; stomachName = info[2] end
				local maxStr = stomachMax >= 9999 and "\xe2\x88\x9e" or tostring(stomachMax)
				currentStomachLabel.Text = "Current: " .. stomachName .. " (" .. maxStr .. " max power)"
				if updateStomachDisplay then updateStomachDisplay() end
				-- keep the shop-title icon in sync: XL Gut -> image, the other six -> their emoji
				if ttlIcon then
					if stomachName == "XL Gut" then
						ttlIcon.Text = ""
						if ttlIconImg then ttlIconImg.Visible = true end
					else
						ttlIcon.Text = _G.GUT_EMOJI[stomachName] or ttlIcon.Text
						if ttlIconImg then ttlIconImg.Visible = false end
					end
				end
				-- BALANCE LOG: only a real upgrade (maxPower went up). Cost looked up from tierDefs.
				if stomachMax > oldMax then
					local costStr = "?"
					for _, t in ipairs(tierDefs) do
						if t.maxPower == stomachMax then costStr = t.robux and (t.cost.." R$") or (t.cost.." coins"); break end
					end
					print(string.format("STOMACH BOUGHT: %s for %s, new maxPower %d", stomachName, costStr, stomachMax))
				end
			end)
		end)
	end
	stomachSideClick.MouseButton1Click:Connect(function()
		pcall(function()
			local ls=player:FindFirstChild("leaderstats"); if not ls then return end
			local sm=ls:FindFirstChild("StomachMax"); if not sm then return end
			local tierName2="Custom"
			for _,t in ipairs(tierDefs) do if t.maxPower==sm.Value then tierName2=t.name; break end end
			local maxStr=sm.Value>=9999 and "\xe2\x88\x9e" or tostring(sm.Value)
			currentStomachLabel.Text="Current: "..tierName2.." ("..maxStr.." max power)"
		end)
	end)
end)

-- ===== CORE FUNCTIONS =====
local function updateMeter()
	-- Display stays in the NORMAL range even when the 2x pass overfills the real tank: the bar is
	-- clamped to 100% and the readout to stomachMax, so the extra fuel shows as flying higher, not
	-- as a bigger meter. (fill uses currentPower/stomachMax clamped; text uses min(..,stomachMax).)
	local fill = stomachMax > 0 and math.clamp(currentPower / stomachMax, 0, 1) or 0
	_G.gui.gasFill.Size=UDim2.new(fill,0,1,0)
	_G.gui.gasGradient.Offset=Vector2.new(-(1-fill),0)
	_G.gui.gasPowerText.Text=math.floor(math.min(currentPower, stomachMax)).."/"..stomachMax
	_G.cosmeticGas=currentPower
end
_G.updateMeter=updateMeter

-- Bird hit: drain real fart fuel as a percentage of the gut's max power (NEVER coins), so it
-- is proportionally fair at every gut tier. We reduce currentPower and resync gasMeter so the
-- flight loop keeps the reduced value, then refresh the meter immediately. If it hits 0 the
-- flight ends naturally via the existing flight loop.
local BIRD_DRAIN_PCT = 0.20 -- single tunable constant: fraction of stomachMax removed per hit
local function applyBirdDrain()
	if stomachMax <= 0 then return end
	local drain = math.ceil(stomachMax * BIRD_DRAIN_PCT)
	currentPower = math.max(0, currentPower - drain)
	gasMeter = (currentPower / stomachMax) * maxGasMeter
	updateMeter()
end
_G.applyBirdDrain = applyBirdDrain

-- Space-junk hit (called from EventClient): END THE CURRENT RISE exactly like running out of power —
-- _G.stopFlying() clears isFlying + the upward BodyVelocity so the player falls under gravity. It does
-- NOT touch currentPower/gasMeter, so the meter is FULLY PRESERVED (the out-of-power path zeroes power
-- separately before calling stopFlying; we deliberately skip that). No drain. Farting is NOT disabled —
-- the player can press fart again to climb on the next attempt. Optional small downward knock (pushDown,
-- studs/sec): with the upward BodyVelocity now gone, setting Y-velocity sticks; gravity continues. 0 = rely
-- on the natural fall only.
_G.applyJunkHit = function(pushDown)
	local meter = gasMeter
	if _G.stopFlying then _G.stopFlying() end   -- normal end-of-rise fall; power preserved
	if pushDown and pushDown > 0 then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, -pushDown, v.Z)
		end
	end
	print(string.format("JUNK HIT: rise ended (fall state), meter PRESERVED at %.1f (no drain)", meter))
end

-- Rainbow-beam hit (called from the beam system's client listener): UNDO the whole flight.
-- 1) restore the fart meter to the EXACT amount the player LAUNCHED with this flight (from
--    _G.beamLaunchSnapshot.power -- NOT the drained amount at the moment of hit), and
-- 2) knock them back through the air to the island they LAUNCHED from, releasing control there.
-- This is the ONE allowed write to the meter (the explicit "restore" exception). It NEVER touches
-- food/gut/earn/coins; the server's CurrentPower stays at the launch value all flight (it only syncs
-- on landing, decrease-only), so on landing the restored value reports clean -> a true full rewind.
-- GUARDRAIL: the knock-back island must be AT or BELOW the player's current Y. If the launch-island
-- snapshot is somehow higher than the player, fall back to the closest island below (never go up).
_G.beamBlasting = false
_G.applyBeamHit = function()
	if _G.beamBlasting then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if _G.stopFlying then _G.stopFlying() end  -- end the rise first (no drain; we set power next)

	local islands = _G.ISLAND_POS or {}
	local curY = hrp.Position.Y
	local snap = _G.beamLaunchSnapshot
	-- ---- choose the knock-back island (never higher than current Y) ----
	local destIdx = nil
	if snap and snap.islandIndex and islands[snap.islandIndex] and islands[snap.islandIndex].y <= curY + 5 then
		destIdx = snap.islandIndex                 -- launch island, only if at/below us
	else
		local bestY = -math.huge                    -- else closest island BELOW current Y
		for i, p in ipairs(islands) do
			if p.y <= curY + 5 and p.y > bestY then bestY = p.y; destIdx = i end
		end
	end

	-- ---- restore the meter to the LAUNCH amount (full rewind) ----
	if snap and snap.power then
		currentPower = math.max(0, math.min(snap.power, stomachMax))
		gasMeter = math.min(effGasMax(), (stomachMax > 0) and (currentPower / stomachMax) * maxGasMeter or 0)
		if _G.updateMeter then _G.updateMeter() end
		print(string.format("BEAM HIT: flight rewound -> meter RESTORED to launch power %.1f", currentPower))
	else
		print("BEAM HIT: no launch snapshot -> meter left as-is")
	end

	if not destIdx then
		-- Nothing at/below us: never go up -- just drop in place (meter already restored).
		if _G.applyJunkHit then _G.applyJunkHit(20) end
		return
	end

	local dp = islands[destIdx]
	-- ★ FIND THE REAL TOP SURFACE (fixes clipping UNDER the island) ★
	-- ISLAND_POS[i].y is the island's CONFIG position, NOT the walkable top, so using it
	-- dragged the knock-back DOWN past the surface and left players under the island.
	-- Raycast straight DOWN at the island's centre (from above the player, who is above
	-- the island) to get the actual top-surface Y; the knock-back lands ON that.
	local surfaceY = dp.y
	do
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { char }      -- ignore ourselves; first hit = the island top
		rp.IgnoreWater = true
		local fromY = math.max(curY, dp.y) + 80
		local hit = workspace:Raycast(Vector3.new(dp.x, fromY, dp.z), Vector3.new(0, -8000, 0), rp)
		if hit then surfaceY = hit.Position.Y end
	end
	local FLOOR_Y = surfaceY + 3                       -- the floor the knock-back may never pass below
	local destAbove = Vector3.new(dp.x, FLOOR_Y, dp.z) -- land just ABOVE the real top; unanchor settles them on it
	print(string.format("BEAM HIT: blasting back to island %d (surfaceY=%.1f, configY=%.0f, curY=%.0f)", destIdx, surfaceY, dp.y, curY))

	_G.beamBlasting = true
	local TweenService = game:GetService("TweenService")
	local RunService   = game:GetService("RunService")

	-- "WHAM" hit sound (2D). PLACEHOLDER id -- swap freely.
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxassetid://9116458024"
	snd.Volume = 1
	snd.Parent = game:GetService("SoundService")
	snd:Play()
	game:GetService("Debris"):AddItem(snd, 4)

	-- Wind-streak blast effect trailing the player during the knock-back (client-local).
	local streaks = Instance.new("Part")
	streaks.Name = "BeamBlastStreaks"; streaks.Anchored = true; streaks.CanCollide = false
	streaks.CanQuery = false; streaks.CanTouch = false; streaks.Transparency = 1
	streaks.Size = Vector3.new(1, 1, 1); streaks.CFrame = hrp.CFrame; streaks.Parent = workspace
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Rate = 40; pe.Lifetime = NumberRange.new(0.2, 0.45); pe.Speed = NumberRange.new(10, 18)
	pe.SpreadAngle = Vector2.new(12, 12); pe.Size = NumberSequence.new(2.5)
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 240, 255))
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	pe.LightEmission = 0.6
	pe.Parent = streaks

	-- Dramatic blast-back: a quick arc up-and-back, then a swoop down to the island. Anchored CFrame
	-- tween (visible knock-back, NOT an instant teleport); unanchor on arrival so they settle + regain control.
	hrp.Anchored = true
	hrp.AssemblyLinearVelocity = Vector3.zero
	local startPos = hrp.Position
	local midPos = startPos:Lerp(destAbove, 0.45) + Vector3.new(0, 18, 0) -- arc apex (knocked up + outward)
	local t1 = TweenService:Create(hrp, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(midPos) })
	local t2 = TweenService:Create(hrp, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = CFrame.new(destAbove) })

	local conn
	conn = RunService.RenderStepped:Connect(function()
		if hrp.Parent then streaks.CFrame = CFrame.new(hrp.Position) end
	end)

	local function finish()
		if conn then conn:Disconnect() end
		if streaks then pe.Enabled = false; game:GetService("Debris"):AddItem(streaks, 1) end
		if _G.stopFlying then _G.stopFlying() end  -- clear any stray flight state started mid-blast (no drain)
		if hrp and hrp.Parent then
			-- The anchored tween already ended ON the surface (FLOOR_Y); guarantee we are
			-- never below it, then release so they settle on the collidable island top.
			if hrp.Position.Y < FLOOR_Y then
				hrp.CFrame = CFrame.new(hrp.Position.X, FLOOR_Y, hrp.Position.Z)
			end
			hrp.Anchored = false
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
		-- Brief watchdog: for ~0.6s after release, if anything (a non-collidable top, a
		-- bad settle) pushes them below the island surface, snap them back up to FLOOR_Y.
		-- This is the "island top acts as a solid floor" clamp the knock-back must respect.
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 0.6 do
				if hrp and hrp.Parent and hrp.Position.Y < FLOOR_Y - 1 then
					hrp.CFrame = CFrame.new(hrp.Position.X, FLOOR_Y, hrp.Position.Z)
					hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
				end
				task.wait()
			end
		end)
		_G.beamBlasting = false
	end

	t1.Completed:Connect(function() t2:Play() end)
	t2.Completed:Connect(finish)
	t1:Play()
end

local function updateFartBtn()
	local st=_G.gui.fartBtnFrame:FindFirstChildWhichIsA("UIStroke")
	if not hasBoughtFood or currentPower<=0 then
		if st then st.Color=Color3.fromRGB(80,80,80); st.Thickness=4 end
		_G.gui.fartBtnFrame.BackgroundColor3=Color3.fromRGB(140,140,140)
		_G.gui.fartBtnGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(140,140,140)),ColorSequenceKeypoint.new(1,Color3.fromRGB(110,110,110))})
		_G.gui.fartCloudLabel.Visible=false; _G.gui.fartBtn.Text="BUY FOOD FIRST!"; _G.gui.fartBtn.Active=false
	elseif isFlying then
		if st then st.Color=Color3.fromRGB(30,130,30); st.Thickness=4 end
		_G.gui.fartBtnFrame.BackgroundColor3=Color3.fromRGB(80,210,80)
		_G.gui.fartBtnGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(80,210,80)),ColorSequenceKeypoint.new(1,Color3.fromRGB(60,180,60))})
		_G.gui.fartCloudLabel.Visible=true; _G.gui.fartBtn.Text="FARTING! (TAP TO STOP)"; _G.gui.fartBtn.Active=true
	else
		if st then st.Color=Color3.fromRGB(30,130,30); st.Thickness=4 end
		_G.gui.fartBtnFrame.BackgroundColor3=Color3.fromRGB(80,210,80)
		_G.gui.fartBtnGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(80,210,80)),ColorSequenceKeypoint.new(1,Color3.fromRGB(60,180,60))})
		_G.gui.fartCloudLabel.Visible=true; _G.gui.fartBtn.Text="TAP TO FART!"; _G.gui.fartBtn.Active=true
	end
	_G.hasBoughtFood=hasBoughtFood
end
_G.updateFartBtn=updateFartBtn

-- ===== MID-AIR RECHARGE EFFECT =====
-- FULLY refill the real fart fuel to MAX and refresh the UI. The flight loop + meter read the LOCAL
-- currentPower / gasMeter — NOT _G.cosmeticGas (which updateMeter() overwrites from currentPower). The
-- old recharge code only set _G.cosmeticGas, so it never actually refuelled. This sets the real vars
-- (same pattern applyBirdDrain uses), so the tank is genuinely full and the bar updates immediately.
function _G.rechargeFartMeter()
	if stomachMax and stomachMax > 0 then currentPower = stomachMax end  -- full tank (raw power)
	gasMeter = maxGasMeter                       -- 100% normalized fuel the flight loop actually reads
	hasBoughtFood = true                         -- so they can immediately fart from the restored meter
	updateMeter()                                -- bar + readout (+ _G.cosmeticGas) re-derive from currentPower -> shows 100%
	updateFartBtn()
	-- NOTE: this only WRITES the meter to max + updates the UI. It deliberately does NOT unpause —
	-- after a purchase the player stays frozen (hovering, full meter) until their fart press resumes them.
end

local function updateCoins()
	pcall(function()
		if leaderstats then
			local c=leaderstats:FindFirstChild("Coins")
			if c then
				local coins=c.Value
				local formatted
				if coins>=1000000 then
					formatted=string.format("%.1fM",coins/1000000)
				elseif coins>=1000 then
					formatted=string.format("%.1fK",coins/1000)
				else
					formatted=tostring(coins)
				end
				coinAmountLabel.Text=formatted
			end
		end
	end)
end
_G.updateCoins=updateCoins


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

-- StomachFull notification (FIX 7)
task.spawn(function()
	local StomachFullEvent=RS:WaitForChild("StomachFullEvent",30)
	if StomachFullEvent then
		StomachFullEvent.OnClientEvent:Connect(function()
			showFloatingText("\xe2\x9a\xa0 STOMACH FULL! Buy a bigger gut!", Color3.fromRGB(255,100,100))
			local g = PlayerGui:FindFirstChild("StomachShopGui")
			if g then g.Enabled = true end
		end)
	end
end)

-- Ring collect SFX. Fresh Sound per hit + Debris cleanup so rapid consecutive ring hits
-- each play cleanly without silencing one another. Volume is adjustable here.
local RING_SOUND_VOLUME = 0.6
local function playRingSound()
	local sound=Instance.new("Sound"); sound.SoundId="rbxassetid://115390827163601"
	sound.Volume=RING_SOUND_VOLUME; sound.Parent=workspace; sound:Play()
	game:GetService("Debris"):AddItem(sound,3)
end

local function playIslandSound()
	local sound=Instance.new("Sound"); sound.SoundId="rbxassetid://117464325212045"
	sound.Volume=0.8; sound.Parent=workspace; sound:Play()
	game:GetService("Debris"):AddItem(sound,4)
end

local function showArrival(islandNum)
	if arrivedIslands[islandNum] then return end
	arrivedIslands[islandNum]=true
	_G.gui.arrivalFrame.BackgroundColor3=islandColors[islandNum] or Color3.fromRGB(100,200,100)
	_G.gui.islandLabel.Text=(ISLAND_DISPLAY_NAMES[islandNum] or ("Island "..islandNum)).."!"
	_G.gui.arrivalFrame.Position=UDim2.new(0.5,0,0,-100); _G.gui.arrivalFrame.Visible=true
	playIslandSound()
	TweenService:Create(_G.gui.arrivalFrame,TweenInfo.new(0.4,Enum.EasingStyle.Back),{Position=UDim2.new(0.5,0,0,10)}):Play()
	local token={}; arrivalHideToken=token
	task.delay(3,function()
		if arrivalHideToken~=token then return end
		TweenService:Create(_G.gui.arrivalFrame,TweenInfo.new(0.3),{Position=UDim2.new(0.5,0,0,-100)}):Play()
		task.delay(0.35,function() if arrivalHideToken==token then _G.gui.arrivalFrame.Visible=false end end)
	end)
end
_G.showArrival=showArrival

local function showServerEventBanner(msg, col)
	_G.gui.seBannerFrame.BackgroundColor3=col; _G.gui.seBannerLine2.Text=msg
	_G.gui.seBannerFrame.Position=UDim2.new(0.5,0,0,-130); _G.gui.seBannerFrame.Visible=true
	TweenService:Create(_G.gui.seBannerFrame,TweenInfo.new(0.4,Enum.EasingStyle.Back),{Position=UDim2.new(0.5,0,0,136)}):Play()
	task.delay(4,function()
		TweenService:Create(_G.gui.seBannerFrame,TweenInfo.new(0.3),{Position=UDim2.new(0.5,0,0,-130)}):Play()
		task.delay(0.35,function() _G.gui.seBannerFrame.Visible=false end)
	end)
end
_G.showServerEventBanner=showServerEventBanner

local function queueAnnouncement(msg)
	table.insert(announceQueue,msg)
	if not announceRunning then
		announceRunning=true
		task.spawn(function()
			while #announceQueue>0 do
				local m=table.remove(announceQueue,1)
				_G.gui.announceBanner.Text=m; _G.gui.announceFrame.Position=UDim2.new(0.5,0,0,-100); _G.gui.announceFrame.Visible=true
				TweenService:Create(_G.gui.announceFrame,TweenInfo.new(0.3,Enum.EasingStyle.Back),{Position=UDim2.new(0.5,0,0,10)}):Play()
				task.wait(3.3)
				TweenService:Create(_G.gui.announceFrame,TweenInfo.new(0.3),{Position=UDim2.new(0.5,0,0,-100)}):Play()
				task.wait(0.4); _G.gui.announceFrame.Visible=false
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
local rainbowHue=0
local function spawnCloud()
	local ch=player.Character; local h=ch and ch:FindFirstChild("HumanoidRootPart"); if not h then return end
	local cloud=Instance.new("Part"); cloud.Shape=Enum.PartType.Ball
	local sz=math.random(10,25)/10
	cloud.Size=Vector3.new(sz,sz,sz)
	local gp=_G.playerGamepasses
	if _G.useCustomTrail and _G.customTrailColor then
		cloud.Color=_G.customTrailColor
	elseif _G.selectedTrail=="rainbow" and _G.hasRainbowTrail then
		local hue=(tick()*0.5)%1
		cloud.Color=Color3.fromHSV(hue,1,1)
	elseif gp and gp.glitterTrail then
		cloud.Color=Color3.fromRGB(255,220,255)
		cloud.Material=Enum.Material.Neon
		cloud.Size=Vector3.new(sz*0.5,sz*0.5,sz*0.5)
	else
		local greens={Color3.fromRGB(0,200,50),Color3.fromRGB(50,220,80),Color3.fromRGB(100,255,100)}
		cloud.Color=greens[math.random(1,#greens)]
	end
	cloud.Material=Enum.Material.Neon; cloud.Transparency=0.3
	cloud.CanCollide=false; cloud.Anchored=true; cloud.CastShadow=false
	cloud.Position=h.Position+Vector3.new(math.random(-15,15)/10,math.random(-10,5)/10,math.random(-15,15)/10)
	cloud.Parent=workspace
	local tw=TweenService:Create(cloud,TweenInfo.new(1.5,Enum.EasingStyle.Linear),{Transparency=1.0,Size=Vector3.new(0.1,0.1,0.1)})
	tw:Play(); tw.Completed:Connect(function() cloud:Destroy() end)
end

-- ===== LANDING DETECTION =====
local function onLand(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	local lastMaterial = Enum.Material.Air
	hum:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
		if hum.FloorMaterial ~= Enum.Material.Air and lastMaterial == Enum.Material.Air then
			if not isFlying then
				local hrpNow = char:FindFirstChild("HumanoidRootPart")
				if hrpNow then
					for _,pad in ipairs(_G.landingPads) do
						if pad and pad.Parent then
							local dp = hrpNow.Position - pad.Position
							if math.abs(dp.X)<6 and math.abs(dp.Z)<6 then
								-- PERFECT-LANDING REWARD REMOVED: no popup/effect fires here anymore. (Loop is also dead: _G.landingPads is never populated now.)
								break
							end
						end
					end
				end
				_G.hasLanded=true; ringStreak=0; ringMultiplier=1
				-- Keep whatever gas was NOT burned in flight (currentPower already reflects the
				-- remaining tank). Do NOT force it to 0 — only respawn/death resets to 0.
				-- Sync the actual remaining power to the server (decrease-only clamp prevents inflation).
				-- [BALANCE LOGGING] pass whether a bird hit the player this flight as a 2nd arg (remainingPower stays first).
				-- [LOGGING ACCURACY] Count this as a real flight ATTEMPT only if the player actually fart-launched
				-- since being grounded AND was airborne > 3s. This filters spawn falls, post-teleport settles,
				-- walk-offs, and aborted near-zero launches. realAttempt gates ONLY the server attempt/save-gate
				-- counters; the power-sync (remainingPower) always runs.
				local airtime = (flightStartTime > 0) and (tick() - flightStartTime) or 0
				local realAttempt = (_G.flewSinceGrounded == true) and airtime > 3
				_G.flewSinceGrounded = false
				pcall(function() if LandingEvent then LandingEvent:FireServer(currentPower, _G.birdHitThisFlight and true or false, realAttempt) end end)
				task.wait(0.2)
				updateFartBtn()
				if updateStomachDisplay then updateStomachDisplay() end
			end
		end
		lastMaterial = hum.FloorMaterial
	end)
end

-- ===== FLIGHT =====
local bodyVel = nil
local cloudTimer = 0
local coinTimer = 0

-- ===== ISLAND UNLOCK BY PEAK HEIGHT =====
-- getMaxHeight is the gut's height ceiling. It is used ONLY to gate which islands a gut can
-- unlock — it never moves, stops, clamps, or snaps the player. The player's vertical motion
-- is ALWAYS just their fart BodyVelocity plus gravity.
local function getMaxHeight()
	return 50 + (stomachMax * 14)
end

local highestUnlockedByHeight = 1
-- Unlock island N once the player's peak flight height reaches ISLAND_Y[N] (and the gut's
-- ceiling is high enough to reach it). Driven purely by how high they actually fly.
local function checkPeakUnlock(peakY)
	for n = highestUnlockedByHeight + 1, 14 do
		local iy = ISLAND_POS[n] and ISLAND_POS[n].y
		if iy and peakY >= iy and iy <= getMaxHeight() then
			highestUnlockedByHeight = n
			_G.unlockedIslands = _G.unlockedIslands or {}
			for i = 1, n do _G.unlockedIslands[i] = true end
			if UnlockIslandEvent then pcall(function() UnlockIslandEvent:FireServer(n) end) end
			-- NOTE: no welcome here. The "You reached [Island]!" welcome fires ONLY from the
			-- server's physical-landing detection (via WelcomeEvent), never from peak height.
		else
			break
		end
	end
end

local function stopFlying()
	if not isFlying then return end
	isFlying = false
	_G.isFlying = false
	if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local old = hrp:FindFirstChild("FartVelocity")
			if old then old:Destroy() end
			hrp.Anchored = false -- never leave the player anchored
		end
	end
	_G.gui.flightStatsFrame.Visible = false; _G.gui.windIndicatorFrame.Visible = false
	-- FLIGHT DEBUG: ONE complete, labeled balance line per flight. Captured now, but printed ~0.5s
	-- later so the server has finalized this flight's coins + island progression (landing detection,
	-- last ring/coin ticks). All values below are snapshots so a quick re-flight can't clobber them.
	-- (All locals here are function-scoped + _G, so no module-level locals are added.)
	local fCoinsBefore = dbgCoinsBefore
	local fGut, fGutMax = stomachName, stomachMax
	local fPowerBought, fTankSize, fTankCost = dbgPrepPower, dbgTankPower, dbgPrepCost
	local fPeak = math.floor(_G.peakHeight or 0)
	local fRaw, fCapped = math.floor(dbgFlightRaw), math.floor(flightCoinsEarned)
	local fRingBonus = math.floor(_G.ringBonusFlight or 0)
	local fIslandBefore = _G.dbgIslandBefore or 1
	local fHas2x = powerPassActive()
	-- [BALANCE LOGGING] timing snapshots (function-scoped + _G only; no module-level locals added).
	local fAirtime = (flightStartTime > 0) and (tick() - flightStartTime) or 0
	local fGroundTime = _G.dbgGroundTime or 0          -- ground/shop time BEFORE this flight (prev land -> this launch)
	local fSinceLastLaunch = _G.dbgSinceLastLaunch or 0 -- real seconds since the PREVIOUS flight's launch
	_G.dbgLastLandTime = tick()                         -- mark this landing so the NEXT flight can compute ground time
	-- [BALANCE LOGGING] % of the gut's tank that was actually filled this flight.
	local fTankFillPct = (fGutMax > 0) and math.floor(fTankSize / fGutMax * 100) or 0
	-- [BALANCE LOGGING] event snapshot (read the _G server-event mirrors).
	local fEvtActive = _G.serverEventActive and true or false
	local fEvtName = _G.serverEventDisplayName or ""
	local fEvtSpeed, fEvtCoin = _G.serverEventSpeedMult or 1, _G.serverEventCoinMult or 1
	local fEvtGas, fEvtHeight, fEvtRing = _G.serverEventGasDrainMult or 1, _G.serverEventHeightMult or 1, _G.serverEventRingMult or 1
	-- [BALANCE LOGGING] bird flags this flight (set by EventClient).
	local fBirdSpawned = _G.birdSpawnedThisFlight and true or false
	local fBirdHit = _G.birdHitThisFlight and true or false
	-- [BALANCE LOGGING] affordability of the NEXT gut. Tier list mirrors the shop's tierDefs (function-scoped copy).
	local dbgTiers = {
		{name="Tiny Gut",maxPower=100,cost=0,robux=false}, {name="Small Gut",maxPower=182,cost=1600,robux=false},
		{name="Medium Gut",maxPower=520,cost=3000,robux=false}, {name="Large Gut",maxPower=1075,cost=5200,robux=false},
		{name="XL Gut",maxPower=2146,cost=8000,robux=false}, {name="Iron Gut",maxPower=3218,cost=11000,robux=false},
		{name="Infinite Gut",maxPower=9999,cost=499,robux=true},
	}
	task.delay(0.5, function()
		local coinsAfter = (leaderstats and leaderstats:FindFirstChild("Coins") and leaderstats.Coins.Value) or fCoinsBefore
		local curIsland = (leaderstats and leaderstats:FindFirstChild("Island") and leaderstats.Island.Value) or fIslandBefore
		local highestReached = player:GetAttribute("HighestIsland") or curIsland
		local flightEarned = coinsAfter - fCoinsBefore
		local newIsland = (highestReached > fIslandBefore) and ("YES -> island "..highestReached) or ("no (fell back/same, on island "..curIsland..")")
		-- [BALANCE LOGGING] how far the peak was from the NEXT island (uses ISLAND_POS Y) + was the tank full.
		local nextIsland = math.min(highestReached + 1, 14)
		local nextStandY = (ISLAND_POS[nextIsland] and ISLAND_POS[nextIsland].y) or 0
		local distToNext = nextStandY - fPeak
		local pctOfNeeded = (nextStandY > 0) and math.floor(fPeak / nextStandY * 100) or 0
		local fullTank = fTankSize >= (fGutMax - 2)
		-- [BALANCE LOGGING] event field string.
		local evtStr
		if fEvtActive then
			evtStr = string.format("%s (speed x%.2f, coin x%.2f, gasDrain x%.2f, height x%.2f, ring x%.2f)",
				(fEvtName ~= "" and fEvtName or "?"), fEvtSpeed, fEvtCoin, fEvtGas, fEvtHeight, fEvtRing)
		else
			evtStr = "none"
		end
		-- [BALANCE LOGGING] next-gut affordability: first tier with maxPower > current gut max.
		local affordStr = "max gut owned"
		for _, t in ipairs(dbgTiers) do
			if t.maxPower > fGutMax then
				if t.robux then
					affordStr = string.format("next %s is Robux (%d R$)", t.name, t.cost)
				elseif coinsAfter >= t.cost then
					affordStr = string.format("couldAfford %s (cost %d, have %d)", t.name, t.cost, coinsAfter)
				else
					affordStr = string.format("saving: need %d more for %s (cost %d, have %d)", t.cost - coinsAfter, t.name, t.cost, coinsAfter)
				end
				break
			end
		end
		print(string.format(
			"FLIGHT DEBUG | t=%s | sinceLastLaunch=%.1fs | groundTime=%.1fs | airtime=%.1fs | coinsBefore=%d | gut=%s (maxPower=%d) | powerBought=%d (tankSize=%d, foodCost=%d coins) | tankFill=%d%% | peak=%d | currentIsland=%d | highestIslandReached=%d | newIslandThisFlight=%s | flightEarnedRaw=%d | flightEarnedCapped=%d | ringBonus=%d | flightEarned=%d | coinsAfter=%d | net(earned-foodCost)=%d | has2x=%s | event=%s | birdSpawned=%s | birdHit=%s | distToNextIsland=%d (nextIsland=%d at Y=%d) | pctOfNeeded=%d%% | fullTank=%s | afford=%s",
			os.date("%H:%M:%S"), fSinceLastLaunch, fGroundTime, fAirtime, fCoinsBefore, fGut, fGutMax, fPowerBought, fTankSize, fTankCost, fTankFillPct, fPeak, curIsland, highestReached, newIsland, fRaw, fCapped, fRingBonus, flightEarned, coinsAfter, flightEarned - fTankCost, tostring(fHas2x), evtStr, tostring(fBirdSpawned), tostring(fBirdHit), distToNext, nextIsland, nextStandY, pctOfNeeded, tostring(fullTank), affordStr))
	end)
	dbgPrepPower = 0; dbgPrepCost = 0
	if _G.checkMilestones then _G.checkMilestones() end
	_G.peakHeight = 0; _G.ringsCollectedFlight = 0
	updateFartBtn()
end
_G.stopFlying = stopFlying

local function startFlying()
	if isFlying then return end
	if currentPower <= 0 then return end
	if not hasBoughtFood then return end
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	isFlying = true
	_G.isFlying = true
	_G.flewSinceGrounded = true -- [LOGGING ACCURACY] a genuine fart-launch happened; only these count as attempts
	playFartSound() -- random fart SFX on every ascent start (after the guards above pass)
	flightStartTime = tick()
	_G.peakHeight = hrp.Position.Y; _G.ringsCollectedFlight = 0
	-- FLIGHT DEBUG: snapshot coins + tank at launch (after this flight's food was bought).
	dbgCoinsBefore = (leaderstats and leaderstats:FindFirstChild("Coins") and leaderstats.Coins.Value) or 0
	dbgTankPower = math.floor(currentPower)
	-- RAINBOW-BEAM launch snapshot: the island we're launching FROM + the meter we took off with.
	-- A beam hit "rewinds" the whole flight: restore THIS power and knock back to THIS island.
	-- (We're on the ground at launch, so the nearest ISLAND_POS to the HRP is the launch island.)
	do
		local snapIdx = 1
		if _G.ISLAND_POS then
			local bd = math.huge
			for i, p in ipairs(_G.ISLAND_POS) do
				local d = (hrp.Position - Vector3.new(p.x, p.y, p.z)).Magnitude
				if d < bd then bd = d; snapIdx = i end
			end
		end
		_G.beamLaunchSnapshot = { power = currentPower, islandIndex = snapIdx }
	end
	-- Reset the per-flight height-coin counters (cap + debug) for the new flight.
	flightCoinsEarned = 0
	dbgFlightRaw = 0
	_G.ringBonusFlight = 0 -- ring-bonus coins earned this flight (for FLIGHT DEBUG); _G avoids adding a chunk local
	_G.dbgIslandBefore = player:GetAttribute("HighestIsland") or 1 -- to detect LANDING on a new island this flight
	-- [BALANCE LOGGING] per-flight timing + bird flags (all _G; no module-level locals added to CoreClient).
	-- gap = seconds spent on ground/shop since the PREVIOUS landing; sinceLastLaunch = seconds since previous launch.
	_G.dbgGroundTime = _G.dbgLastLandTime and (tick() - _G.dbgLastLandTime) or 0
	_G.dbgSinceLastLaunch = _G.dbgLastLaunchTime and (tick() - _G.dbgLastLaunchTime) or 0
	_G.dbgLastLaunchTime = tick()
	_G.birdSpawnedThisFlight = false -- reset; EventClient sets true if a bird spawns this flight
	_G.birdHitThisFlight = false     -- reset; EventClient sets true if a bird hits the player this flight

	-- This flight's gas tank = how full the stomach is from food, as 0-100 (or up to
	-- 0-(100*POWER_PASS_MULT) internally when the 2x pass is active, for a longer/higher flight).
	gasMeter = math.min(effGasMax(), (stomachMax > 0) and (currentPower / stomachMax) * maxGasMeter or 0)

	hrp.Anchored = false
	if glideVel then glideVel:Destroy(); glideVel = nil end
	local old = hrp:FindFirstChild("FartVelocity")
	if old then old:Destroy() end
	if bodyVel then bodyVel:Destroy() end
	bodyVel = Instance.new("BodyVelocity")
	bodyVel.Name = "FartVelocity"
	bodyVel.MaxForce = Vector3.new(50000, 1e6, 50000)
	bodyVel.Velocity = Vector3.new(0, 0, 0)
	bodyVel.Parent = hrp

	updateMeter(); updateFartBtn()
end

player.CharacterAdded:Connect(function(char)
	isFlying = false; _G.isFlying = false
	if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	currentPower = 0; gasMeter = 0; hasBoughtFood = false; _G.hasLanded = true
	-- ===== RESTORE METER on RESPAWN (two distinct rules, decided in Humanoid.Died below) =====
	-- Every death sets _G.respawnMeterPending + _G.respawnMeterSnapshot, so restore that snapshot
	-- instead of the default reset-to-0:
	--  • BIRD NUKE death -> snapshot is THIS flight's LAUNCH amount (_G.beamLaunchSnapshot.power).
	--  • R-reset / fall  -> snapshot is the ENDED amount (the meter at the moment of death).
	-- The snapshot is clamped to the current gut max here. The grounded-landing sync that fires right
	-- after the respawn reconciles the server CurrentPower decrease-only — correct in BOTH cases because
	-- the kept amount is <= the server's launch/last value (launch == the server value for a nuke; the
	-- ended amount <= it for R/fall), so client and server agree and it sticks through save/sync. Hazard
	-- hits (junk/planes/beams), the Return-to-Island button and food buys never set the flag, so they're
	-- unaffected.
	if _G.respawnMeterPending and _G.respawnMeterSnapshot then
		currentPower = math.clamp(_G.respawnMeterSnapshot, 0, stomachMax)
		gasMeter = (stomachMax > 0) and (currentPower / stomachMax) * maxGasMeter or 0
		if currentPower > 0 then hasBoughtFood = true end -- keep the fart button usable with the kept fuel
	end
	_G.respawnMeterPending = false
	_G.birdNukeDeathPending = false -- consumed: clear so the NEXT R/fall death uses the ended-amount rule
	-- Keep islands already unlocked so we don't re-fire unlocks the server already has.
	highestUnlockedByHeight = 1
	pcall(function()
		local ls = player:FindFirstChild("leaderstats")
		local isl = ls and ls:FindFirstChild("Island")
		if isl and isl.Value > highestUnlockedByHeight then highestUnlockedByHeight = isl.Value end
	end)
	updateMeter(); updateFartBtn()
	onLand(char)
	-- Snapshot the meter the INSTANT this character dies so the NEXT respawn can restore
	-- it. Humanoid.Died fires for BOTH cases we care about: falling out of the world AND a
	-- force-reset (pressing R). It does NOT fire for hazard hits, the Return button, etc.
	task.spawn(function()
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
		if hum then
			hum.Died:Connect(function()
				-- TWO DISTINCT DEATH RULES (kept separate so neither overwrites the other):
				--  • BIRD NUKE death (_G.birdNukeDeathPending, set by the BirdNukeEvent handler): restore to
				--    THIS flight's LAUNCH amount (_G.beamLaunchSnapshot.power — the same launch-snapshot rule
				--    junk/planes/beams use) if they were in an ACTIVE flight; if grounded (no current flight
				--    to rewind to), fall back to the ended amount.
				--  • GENERIC respawn (R-key force-reset / fall off map): keep the ENDED amount — EXACTLY the
				--    meter at the moment of death (NOT launch, NOT zero).
				-- CharacterAdded consumes _G.respawnMeterSnapshot and clears _G.birdNukeDeathPending.
				if _G.birdNukeDeathPending then
					if _G.flewSinceGrounded and _G.beamLaunchSnapshot then
						_G.respawnMeterSnapshot = _G.beamLaunchSnapshot.power
					else
						_G.respawnMeterSnapshot = currentPower
					end
				else
					_G.respawnMeterSnapshot = currentPower
				end
				_G.respawnMeterPending = true
			end)
		end
	end)
end)
if character then onLand(character) end -- no character yet on join (CharacterAutoLoads=false); runs via CharacterAdded on spawn

-- Y rise-speed by current (gas-scaled) power. Tuned so each stomach's full-tank CLIMB lands just past
-- ~2 islands (the next island sits at ~93-94% of the climb -> ~3-4 attempts), evening out the
-- per-island difficulty: Tiny->2,3,4 (gate 5), Small->5,6 (gate 7), Medium->7,8 (gate 9),
-- Large->9,10 (gate 11), XL->11,12 (gate 13), Iron->13,14. Thresholds align with the stomach maxPowers.
local function getFlightSpeed(power)
	if power <= 100 then return 40 -- Tiny band: bumped 33->40 (real data: speed 33 only climbed ~830 from launch, short of island 3). 40 -> ~1006 climb: reaches 3 & 4 with effort, gates at 5.
	elseif power <= 182 then return 62
	elseif power <= 611 then return 84   -- was 68 (too close to Small's 62 -> Medium barely out-climbed Small). 84 -> Medium clears islands 7,8.
	elseif power <= 1075 then return 126 -- was 108 -> Large clears 9,10
	elseif power <= 2146 then return 144 -- was 129 -> XL clears 11,12
	elseif power <= 3218 then return 226 -- was 196 -> Iron clears 13,14
	else return 280 end                  -- was 250 (Infinite gut)
end

-- ===== FLIGHT LOOP — simple land-on-islands flight =====
-- Hold the fart button -> BodyVelocity drives the player straight up while gas drains.
-- Release or run dry -> the BodyVelocity is destroyed and they fall under real gravity and
-- land on whatever island they land on. Nothing ever moves the player vertically except this
-- BodyVelocity + gravity. There is no checkpoint, no floor, no platform, no anchoring.
RunService.Heartbeat:Connect(function(dt)
	if twoXBoostActive and os.time() > twoXBoostEndTime then twoXBoostActive = false end

	local char = player.Character
	if not char then if isFlying then stopFlying() end return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChild("Humanoid")
	if not hrp or not hum then if isFlying then stopFlying() end return end

	-- JOIN HOLD: while the server has the player "Frozen" (held until they pick an island), keep them
	-- anchored and skip flight — otherwise the loop below would immediately un-anchor them.
	if player:GetAttribute("Frozen") then
		if not hrp.Anchored then hrp.Anchored = true end
		if isFlying then stopFlying() end
		return
	end

	-- The player is never anchored (outside the join hold above).
	if hrp.Anchored then hrp.Anchored = false end

	-- INFINITE GUT (gamepass 1860686821): the fart meter is LOCKED at full and NEVER drains. The server sets
	-- the HasInfiniteGut attribute for OWNERS in applyInfiniteGut — on JOIN (UserOwnsGamePassAsync) and on
	-- purchase — and player attributes replicate to the client, so we read it here. For owners we keep the
	-- tank topped off (currentPower = StomachMax, gasMeter = full) and farting always enabled -> unlimited
	-- continuous flight, and the meter is full again immediately after any flight / landing / hazard. We
	-- re-apply ONLY when something dropped it (a flight frame, a landing reset, a hazard) to avoid per-frame
	-- churn. NON-OWNERS never enter this block, so they drain exactly as before.
	local infiniteGut = (player:GetAttribute("HasInfiniteGut") == true)
	if infiniteGut and (currentPower < stomachMax or gasMeter < maxGasMeter or not hasBoughtFood) then
		gasMeter = maxGasMeter
		currentPower = stomachMax
		hasBoughtFood = true   -- a permanently full tank is always "loaded", so launching is always allowed
		updateMeter()          -- bar -> 100% (fill derives from currentPower/stomachMax)
		updateFartBtn()        -- keep the fart button usable (e.g. right after a respawn cleared the flags)
	end

	if isFlying and gasMeter > 0 then
		-- Button held + gas left -> thrust straight up.
		if not infiniteGut then
			gasMeter = math.max(0, gasMeter - DRAIN_RATE * dt) -- normal drain; SKIPPED for Infinite Gut owners (never drains)
		end
		local scaledPower = (gasMeter / maxGasMeter) * stomachMax -- power scaled by remaining gas
		currentPower = scaledPower
		local speed = getFlightSpeed(scaledPower) * (_G.serverEventSpeedMult or 1)
		if twoXBoostActive then speed = speed * 2 end

		-- Horizontal steering while flying. Source the direction from the Humanoid's MoveDirection so
		-- it works for PC (WASD/arrows), mobile (joystick), AND gamepad — it's already camera-relative.
		-- (0,0,0 when there's no input.) Only X/Z below are steered; the Y component is the rise speed.
		local move = hum.MoveDirection

		if not bodyVel or not bodyVel.Parent then
			bodyVel = Instance.new("BodyVelocity")
			bodyVel.Name = "FartVelocity"
			bodyVel.Parent = hrp
		end
		bodyVel.MaxForce = Vector3.new(50000, 1e6, 50000)
		-- WIND STORM shove: while a windstorm is active, add a STRONG horizontal push along _G.windstormDir
		-- (set + re-aimed by EventClient). 150 studs/s is ~3x the 48 steering speed, so players really get
		-- knocked off course and struggle to steer. Zero when no windstorm, so normal flight is unchanged.
		local wpx, wpz = 0, 0
		if _G.windstormActive and _G.windstormDir then
			wpx = _G.windstormDir.X * 150
			wpz = _G.windstormDir.Z * 150
		end
		bodyVel.Velocity = Vector3.new(move.X * FLIGHT_HORIZONTAL_SPEED + wpx, speed, move.Z * FLIGHT_HORIZONTAL_SPEED + wpz)

		updateMeter()
		if hrp.Position.Y > _G.peakHeight then _G.peakHeight = hrp.Position.Y end
		checkPeakUnlock(hrp.Position.Y) -- unlock islands by how high we actually fly

		_G.gui.flightStatsFrame.Visible = true
		_G.gui.fsHeight.Text = "\xF0\x9F\x93\x8F Height: " .. math.floor(hrp.Position.Y)
		_G.gui.fsRings.Text = "\xF0\x9F\x92\x8D Rings: " .. _G.ringsCollectedFlight .. " (x" .. string.format("%.1f", ringMultiplier) .. ")"
		_G.gui.fsAir.Text = "\xe2\x8f\xb1 Air: " .. math.floor(tick() - flightStartTime) .. "s"

		-- COINS: every 0.5s add height * 0.0044 * serverEventCoinMult (default 1, becomes 2 during
		-- COIN_RUSH so "Double Coins" actually doubles). Server floors/accumulates. No (height/500)^2.
		coinTimer = coinTimer + dt
		if coinTimer >= 0.5 then
			coinTimer = 0
			local height = math.max(1, hrp.Position.Y)
			local tickCoins = height * 0.0044 * (_G.serverEventCoinMult or 1)
			dbgFlightRaw = dbgFlightRaw + tickCoins
			-- Cap height earnings per flight at max(FLIGHT_COIN_CAP, peakHeight*CAP_PER_HEIGHT), so flying
			-- higher raises the ceiling and pays out much more. peakHeight only rises, so the cap never
			-- shrinks mid-descent. Only pay the remaining headroom this tick. Rings are separate + uncapped.
			local dynCap = math.max(FLIGHT_COIN_CAP, (_G.peakHeight or height) * CAP_PER_HEIGHT)
			local pay = math.min(tickCoins, dynCap - flightCoinsEarned)
			if pay > 0 then
				flightCoinsEarned = flightCoinsEarned + pay
				pcall(function() CoinEvent:FireServer(pay * 0.70) end) -- [BALANCE] pay out 70% of the capped flight coins (after cap; ring bonus + food cost unaffected)
			end
		end

		-- ring collection
		for i = #_G.activeRings, 1, -1 do
			local r = _G.activeRings[i]
			if r.part and r.part.Parent then
				if (hrp.Position - r.part.Position).Magnitude < 16 then
					local rpos, rcol, ridx, rdir = r.pos, r.color, r.idx, r.dir
					r.part:Destroy(); table.remove(_G.activeRings, i)
					playRingSound() -- one clean play per ring hit
					ringStreak = ringStreak + 1; ringMultiplier = 1 + ringStreak * 0.2
					local bonus = math.floor(15 * ringMultiplier * _G.serverEventRingMult)
					_G.ringsCollectedFlight = _G.ringsCollectedFlight + 1
					_G.ringBonusFlight = (_G.ringBonusFlight or 0) + bonus -- track ring-bonus coins for FLIGHT DEBUG
					if CoinEvent then pcall(function() CoinEvent:FireServer(bonus) end) end
					showFloatingText("+" .. bonus .. " \xF0\x9F\xAA\x99 x" .. string.format("%.1f", ringMultiplier), Color3.fromRGB(255, 215, 0))
					task.delay(30, function() if _G.spawnRing then _G.spawnRing(rpos, rcol, ridx, rdir) end end)
				end
			else table.remove(_G.activeRings, i) end
		end

		-- FART BUBBLES (gas pockets): PURE VISUAL. Touching one POPS it (expand+fade +
		-- particle burst + pop sound via _G.popGasPocket) but gives ZERO gas/power and ZERO
		-- coins -- only the visual pop happens. It re-spawns after a delay so the cosmetic
		-- stays available. (No boost, no "GAS BOOST!" text, no flash -- the mechanical effect
		-- is gone; only the pop remains.)
		for i = #_G.activeGasPockets, 1, -1 do
			local p = _G.activeGasPockets[i]
			if p and p.Parent then
				if (hrp.Position - p.Position).Magnitude < 20 then
					local ppos = p.Position
					table.remove(_G.activeGasPockets, i)
					if _G.popGasPocket then _G.popGasPocket(p) end   -- VISUAL pop only
					task.delay(45, function() if _G.spawnGasPocket then _G.spawnGasPocket(ppos) end end)
				end
			else table.remove(_G.activeGasPockets, i) end
		end

		-- cosmetic fart-trail particle (NOT a platform: non-collidable, fades out in ~1.5s)
		cloudTimer = cloudTimer + dt
		if cloudTimer >= 0.1 then cloudTimer = 0; pcall(spawnCloud) end

		-- Gas just emptied this frame: stop thrusting so the player falls under gravity.
		if gasMeter <= 0 then
			currentPower = 0
			updateMeter()
			stopFlying()
		end
	else
		-- Not thrusting -> guarantee no upward BodyVelocity; fall under gravity.
		if isFlying then stopFlying() end
		if bodyVel then bodyVel:Destroy(); bodyVel = nil end

		-- Horizontal-only WASD air control while falling with no fuel. MaxForce.Y = 0, so
		-- this never adds or holds vertical velocity — gravity always does the falling.
		if hum.FloorMaterial == Enum.Material.Air and currentPower <= 0 then
			if not glideVel or not glideVel.Parent then
				glideVel = Instance.new("BodyVelocity"); glideVel.Name = "GlideVelocity"
				glideVel.Velocity = Vector3.new(0, 0, 0)
				glideVel.Parent = hrp
			end
			glideVel.MaxForce = Vector3.new(10000, 0, 10000)
			local camCF = workspace.CurrentCamera.CFrame
			local fwd = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z); if fwd.Magnitude > 0 then fwd = fwd.Unit end
			local rgt = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z); if rgt.Magnitude > 0 then rgt = rgt.Unit end
			local md = Vector3.new(0, 0, 0)
			if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then md = md + fwd end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then md = md - fwd end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then md = md - rgt end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then md = md + rgt end
			if md.Magnitude > 0 then md = md.Unit end
			glideVel.Velocity = Vector3.new(md.X * 27, 0, md.Z * 27)
		else
			if glideVel then glideVel:Destroy(); glideVel = nil end
		end
	end
end)

-- ===== INPUT (TOGGLE: press once to fart up hands-free, press again to cancel) =====
-- Press once -> start flying (gas drains, player rises; no need to keep holding — they can move the
-- camera/character freely). Press again -> cancel: stop the drain and fall under gravity. Canceling
-- KEEPS the leftover gas/power (stopFlying never zeroes the meter — only respawn/death resets it),
-- so a later press resumes flying from the remaining gas. Running dry still auto-stops as before.
local function toggleFart()
	-- STEP 4: if the player is paused AFTER a successful Mid-Air Recharge purchase (hovering with a full
	-- meter), this fart press unpauses them and resumes normal flight on the refilled meter. Only applies
	-- in that exact state -- otherwise the fart button behaves exactly as normal.
	if _G.rechargeAwaitingFart then
		_G.rechargeAwaitingFart = false
		if _G.endRechargePause then _G.endRechargePause() end   -- lift the freeze (clear Frozen, un-anchor, zero velocity)
		if hasBoughtFood and currentPower > 0 then startFlying() end  -- fly up on the full meter; drains normally from here
		return
	end
	if isFlying then
		stopFlying()                                  -- cancel ascent; remaining gas/power is preserved
	elseif hasBoughtFood and currentPower > 0 then
		startFlying()                                 -- begin/resume ascent, draining the remaining gas
	end
end
-- Activated fires on mouse click, touch tap, and gamepad -> works on PC and mobile.
_G.gui.fartBtn.Activated:Connect(toggleFart)

-- ===== REMOTE HANDLERS =====
pcall(function()
	if RegenEvent then
		RegenEvent.OnClientEvent:Connect(function(power, total, max)
			hasBoughtFood = true
			currentPower = tonumber(total) or currentPower + (tonumber(power) or 0)
			stomachMax = tonumber(max) or stomachMax
			gasMeter = stomachMax > 0 and (currentPower / stomachMax) * maxGasMeter or 0
			-- FLIGHT DEBUG: a food buy fires RegenEvent with power>0 (resets/landing send 0).
			-- Powers are unique per food, so map power->price to tally the tank bought this flight.
			local p = tonumber(power) or 0
			if p > 0 then
				for _, fd in ipairs(foods) do
					if fd.power == p then dbgPrepPower = dbgPrepPower + p; dbgPrepCost = dbgPrepCost + fd.price; break end
				end
			end
			updateMeter()
			updateFartBtn()
		end)
	end
end)
-- Personal "You reached [Island]!" welcome — fired by the server ONLY on confirmed physical
-- landing (WelcomeEvent), to this player only.
local WelcomeEvent = RS:FindFirstChild("WelcomeEvent") or RS:WaitForChild("WelcomeEvent",10)
if WelcomeEvent then
	WelcomeEvent.OnClientEvent:Connect(function(islandNum)
		if _G.showArrival then pcall(function() _G.showArrival(islandNum) end) end
	end)
end
if AnnouncementEvent then
	AnnouncementEvent.OnClientEvent:Connect(function(pName,islandNum,islandName)
		queueAnnouncement("\xF0\x9F\x8F\x9D\xEF\xB8\x8F "..tostring(pName).." reached "..tostring(islandName).."!")
	end)
end
if GamepassEvent then
	GamepassEvent.OnClientEvent:Connect(function(data)
		if not data then return end
		local gp=_G.playerGamepasses
		if data.twoXForever ~= nil then gp.twoXForever = data.twoXForever end
		if data.glitterTrail ~= nil then gp.glitterTrail = data.glitterTrail end
		if data.twoXHourExpiry then gp.twoXHourExpiry = data.twoXHourExpiry end
		if data.midAirRecharge ~= nil then gp.midAirRecharge = data.midAirRecharge end
		if data.skipIsland ~= nil then gp.skipIsland = data.skipIsland end
		-- FRESH Mid-Air Recharge purchase (server-authoritative grant): refill the meter to MAX and keep
		-- the player paused/awaiting-fart (same handler the client purchase callback uses; idempotent if
		-- both fire). We consume the just-granted charge so a purchase = exactly one refill (no banked dup).
		if data.rechargeNow then
			if gp.midAirRecharge and gp.midAirRecharge > 0 then gp.midAirRecharge = gp.midAirRecharge - 1 end
			if _G.rechargeMarkPurchased then _G.rechargeMarkPurchased()
			elseif _G.rechargeFartMeter then _G.rechargeFartMeter() end
			-- [TEST ONLY] rechargeTest is set ONLY by the server /recharge test hook (never a real
			-- purchase), so it forces a direct display refill to 100% even when NOT mid-flight-paused --
			-- letting the refill be confirmed in Studio. Idempotent (just sets the meter to max).
			if data.rechargeTest and _G.rechargeFartMeter then _G.rechargeFartMeter() end
		end
		if _G.updateHotbar then _G.updateHotbar() end
	end)
end

-- ===== STATS LOOP =====
task.spawn(function()
	while true do
		task.wait(0.5)
		pcall(function()
			if leaderstats then
				local isl=leaderstats:FindFirstChild("Island"); local tfp=leaderstats:FindFirstChild("TotalFartPower"); local tce=leaderstats:FindFirstChild("TotalCoinsEarned")
				if isl then islandLabel.Text="\xF0\x9F\x8F\x9d\xef\xb8\x8f Island: "..isl.Value end
				local sh=math.floor(math.max(_G.peakHeight or 0,sessionMaxHeight))
				if sh>sessionMaxHeight then sessionMaxHeight=sh end
				heightLabel.Text="\xF0\x9F\x8f\x86 Max Height: "..sh
				if tfp then fartsLabel.Text="\xF0\x9F\x92\xa8 Farts: "..tostring(leaderstats.TotalFartPower.Value) end
			end
		end)
		updateCoins()
	end
end)
task.spawn(function()
	while true do
		task.wait(1)
		local gp=_G.playerGamepasses
		local expiry = gp and gp.twoXHourExpiry or 0
		if expiry > os.time() then
			local rem = expiry - os.time()
			local mins = math.floor(rem/60); local secs = rem%60
			twoXTimerText.Text=string.format("\xe2\x9a\xa1 %dm %02ds",mins,secs)
			twoXTimerLabel.Visible=true
			if twoXSub then twoXSub.Visible=false end
		else
			twoXTimerLabel.Visible=false
			if twoXSub then twoXSub.Visible=true end
		end
	end
end)

-- ===== DAILY REWARD CLIENT HANDLER =====
task.spawn(function()
	local DailyRewardEvent2=RS:WaitForChild("DailyRewardEvent",30)
	local ClaimRewardEvent=RS:WaitForChild("ClaimRewardEvent",30)
	if not DailyRewardEvent2 then print("DAILY REWARDS SYSTEM READY"); return end
	if ClaimRewardEvent then
		dailyClaimBtn.MouseButton1Click:Connect(function()
			-- Send the claim FIRST so nothing below can block it. (BUG FIX: dailyUnavailLabel is
			-- :Destroy()ed during setup, and setting .Visible on the destroyed label threw HERE, before
			-- FireServer ran -> the server never received the claim, so no coins and no confetti/sound.)
			pcall(function() ClaimRewardEvent:FireServer() end)
			dailyClaimBtn.Visible=false; dailyBadge.Visible=false
			if dailyUnavailLabel and dailyUnavailLabel.Parent then dailyUnavailLabel.Visible=true end
		end)
	end
	local function updateRewardGrid(streak,available)
		local cyclePos=streak%7
		for i=1,7 do
			local box=dailyBoxes[i]; if not box then continue end
			local st=box:FindFirstChildWhichIsA("UIStroke")
			local scl=box:FindFirstChildOfClass("UIScale")
			local icon=box:FindFirstChild("_icon")  -- per-day reward icon: coin (unclaimed) vs checkmark (claimed)
			if available and i==cyclePos+1 then
				box.BackgroundColor3=Color3.fromRGB(255,180,0)
				if icon then icon.Image=_G.COIN_IMAGE end  -- AVAILABLE / not yet claimed -> coin image
				if st then st.Color=Color3.fromRGB(255,200,0); st.Thickness=3 end
				if not scl then scl=Instance.new("UIScale"); scl.Parent=box end
				task.spawn(function()
					while box and box.Parent and available do
						TweenService:Create(scl,TweenInfo.new(0.6,Enum.EasingStyle.Sine),{Scale=1.05}):Play()
						task.wait(0.6)
						TweenService:Create(scl,TweenInfo.new(0.6,Enum.EasingStyle.Sine),{Scale=1.0}):Play()
						task.wait(0.6)
					end
				end)
			elseif i<=cyclePos then
				box.BackgroundColor3=Color3.fromRGB(50,150,50)
				if st then st.Color=Color3.fromRGB(0,120,0); st.Thickness=2 end
				if scl then scl:Destroy() end
				-- CLAIMED: swap the coin image to the CHECKMARK image (replaces the old overlaid _check label).
				if icon then icon.Image=_G.CHECK_IMAGE end
				local oldCk=box:FindFirstChild("_check"); if oldCk then oldCk:Destroy() end  -- remove any legacy overlay
			else
				box.BackgroundColor3=Color3.fromRGB(20,60,120); box.BackgroundTransparency=0.2
				if st then st.Color=Color3.fromRGB(50,100,200); st.Thickness=2 end
				if scl then scl:Destroy() end
				if icon then icon.Image=_G.COIN_IMAGE end  -- FUTURE day (incl. after a cycle reset) -> back to coin image
			end
		end
	end
	local function updateMilestones(streak)
		for day,mb in pairs(milestoneBoxes) do
			if streak>=day then
				mb.BackgroundColor3=Color3.fromRGB(50,150,50)
				local st=mb:FindFirstChildWhichIsA("UIStroke"); if st then st.Color=Color3.fromRGB(255,200,0); st.Thickness=3 end
				local ckL=mb:FindFirstChild("_check")
				if not ckL then
					ckL=Instance.new("TextLabel"); ckL.Name="_check"; ckL.Text="\xe2\x9c\x93"; ckL.RichText=false
					ckL.Font=Enum.Font.GothamBold; ckL.TextSize=14; ckL.TextColor3=Color3.fromRGB(100,255,100); ckL.BackgroundTransparency=1
					ckL.Size=UDim2.new(0,16,0,16); ckL.Position=UDim2.new(1,-18,0,2)
					ckL.TextXAlignment=Enum.TextXAlignment.Center; ckL.Parent=mb
				end
			end
		end
	end
	DailyRewardEvent2.OnClientEvent:Connect(function(data)
		pcall(function()
			local streak=data.streak or 0
			dailyStreakLabel.Text="\xF0\x9F\x94\xa5 Day "..streak.." Streak!"
			local nextDay=streak+1
			local nextNames={"5 Coins","25 Coins","75 Coins","150 Coins","300 Coins","500 Coins","1000 Coins"}
			local nextName=nextNames[((nextDay-1)%7)+1]
			dailyNextLabel.Text="Next reward: "..(nextName or ("Day "..nextDay))
			dailyBadge.Visible=data.available==true
			dailyClaimBtn.Visible=data.available==true
			-- Guarded: dailyUnavailLabel is :Destroy()ed at setup; touching it here would throw and (since
			-- this whole handler is pcall'd) silently skip the confetti + sound block below.
			if dailyUnavailLabel and dailyUnavailLabel.Parent then dailyUnavailLabel.Visible=data.available~=true end
			updateRewardGrid(streak,data.available)
			updateMilestones(streak)
			_G.unlockedTrails=data.unlockedTrails or {}
			_G.hasRainbowTrail=data.hasRainbow or false
			updateTrailSelector()
			if data.justClaimed then
				local reward=data.justClaimed
				-- Sound
				local claimSound=Instance.new("Sound"); claimSound.SoundId="rbxassetid://112825313814792"
				claimSound.Volume=0.8; claimSound.Parent=workspace; claimSound:Play()
				game:GetService("Debris"):AddItem(claimSound,5)
				-- 2D GUI confetti
				local dailyConfettiGui=Instance.new("ScreenGui"); dailyConfettiGui.Name="DailyConfetti"
				dailyConfettiGui.ResetOnSpawn=false; dailyConfettiGui.Parent=PlayerGui
				task.spawn(function()
					for i=1,40 do
						task.wait(0.04)
						local confetti=Instance.new("Frame")
						confetti.Size=UDim2.new(0,math.random(10,16),0,math.random(10,16))
						confetti.Position=UDim2.new(math.random(10,90)/100,0,0,math.random(-20,0))
						confetti.BackgroundColor3=Color3.fromHSV(math.random(0,100)/100,1,1)
						confetti.BorderSizePixel=0; confetti.ZIndex=25; confetti.Rotation=math.random(0,360)
						confetti.Parent=dailyConfettiGui
						local uic=Instance.new("UICorner"); uic.CornerRadius=UDim.new(0,3); uic.Parent=confetti
						TweenService:Create(confetti,TweenInfo.new(2.5),{
							Position=UDim2.new(confetti.Position.X.Scale,0,1,60),
							Rotation=math.random(360),
							BackgroundTransparency=1
						}):Play()
						game:GetService("Debris"):AddItem(confetti,2.6)
					end
					task.wait(3)
					dailyConfettiGui:Destroy()
				end)
				showFloatingText("\xF0\x9F\x8E\x81 "..(reward.name or "Reward").." UNLOCKED!",Color3.fromRGB(255,215,0))
				if reward.type=="trail" then task.delay(0.5,function() updateTrailSelector() end) end
				local char2=player.Character; local hrp2=char2 and char2:FindFirstChild("HumanoidRootPart")
				if hrp2 then
					local Debris=game:GetService("Debris")
					for j=1,25 do
						task.delay(j*0.08,function()
							pcall(function()
								local c=Instance.new("Part"); c.Size=Vector3.new(0.5,0.5,0.5)
								c.Color=Color3.fromHSV(math.random(),0.9,1); c.Material=Enum.Material.Neon
								c.CanCollide=false; c.CastShadow=false; c.Anchored=false
								c.Position=hrp2.Position+Vector3.new(math.random(-12,12),15,math.random(-12,12)); c.Parent=workspace
								local bv=Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(1e6,1e6,1e6)
								bv.Velocity=Vector3.new(math.random(-6,6),-6,math.random(-6,6)); bv.Parent=c
								Debris:AddItem(c,2.5)
							end)
						end)
					end
				end
			end
		end)
	end)
	print("DAILY REWARDS SYSTEM READY")
end)

-- ===== BIRD NUKE (offensive): DIE + RESPAWN AT LAUNCH AMOUNT when someone ELSE nukes =====
-- When another player nukes, the victim's character is KILLED here (Humanoid.Health = 0) and goes
-- through the normal Roblox respawn; the server reloads it at its home island. The Humanoid.Died
-- handler (in CharacterAdded) sees the _G.birdNukeDeathPending flag set below and restores the meter
-- to THIS flight's LAUNCH amount on respawn (vs the ended amount for a plain R/fall death). The buyer
-- is spared. Wrapped in a do-block to keep this local out of the main chunk's register budget.
do
	local BirdNukeEvent = RS:FindFirstChild("BirdNukeEvent") or RS:WaitForChild("BirdNukeEvent", 10)
	if BirdNukeEvent then
		BirdNukeEvent.OnClientEvent:Connect(function(buyerName)
			if buyerName == player.Name then return end -- the buyer is spared
			-- BIRD NUKE = DEATH + RESPAWN AT LAUNCH AMOUNT. Flag this as a bird-nuke death so the
			-- Humanoid.Died handler snapshots THIS flight's LAUNCH-amount meter (_G.beamLaunchSnapshot.power,
			-- the same launch-snapshot rule junk/planes/beams use) instead of the ended amount, then KILL
			-- the character so it goes through the normal Roblox respawn (the server reloads the victim at
			-- their home island). On respawn, CharacterAdded restores currentPower to that launch amount and
			-- the landing sync makes the server CurrentPower agree, so it sticks through save/sync.
			_G.birdNukeDeathPending = true
			if isFlying then stopFlying() end -- end the flight cleanly (drop the BodyVelocity) before the kill
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = 0 -- actually kill the character -> Humanoid.Died -> normal respawn at home
			end
		end)
	end
end

-- ===== PURCHASE ANNOUNCEMENT BANNER =====
-- Purchase banner: display fn + event handler, wrapped in a do-block so these locals stay out of
-- the main chunk's register budget (same reason as the IIFE further below).
do
-- Builds and shows the gold purchase banner (slide-in, confetti, sound, auto-dismiss). Called by
-- the PurchaseAnnouncementEvent handler on a real purchase.
local function showPurchaseBanner(playerName, itemName, isGamepass)
		local bannerGui = Instance.new("ScreenGui")
		bannerGui.Name = "PurchaseBanner"
		bannerGui.ResetOnSpawn = false
		bannerGui.IgnoreGuiInset = true
		bannerGui.Parent = PlayerGui

		local banner = Instance.new("Frame")
		banner.Size = UDim2.new(0,500,0,60)
		banner.Position = UDim2.new(0.5,0,0,-70)
		banner.AnchorPoint = Vector2.new(0.5,0)
		banner.BackgroundColor3 = Color3.fromRGB(255,200,0)
		banner.ZIndex = 20
		banner.Parent = bannerGui
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,12); bc.Parent = banner
		local bs = Instance.new("UIStroke"); bs.Color = Color3.fromRGB(200,150,0); bs.Thickness = 3; bs.Parent = banner

		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(0,50,1,0)
		icon.Position = UDim2.new(0,8,0,0)
		icon.BackgroundTransparency = 1
		icon.Text = isGamepass and "\xe2\xad\x90" or "\xf0\x9f\x8e\x89"
		icon.TextSize = 28
		icon.Font = Enum.Font.Gotham
		icon.RichText = false
		icon.ZIndex = 21
		icon.Parent = banner

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1,-60,1,0)
		label.Position = UDim2.new(0,55,0,0)
		label.BackgroundTransparency = 1
		label.Text = playerName .. " bought " .. itemName .. "!"
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextColor3 = Color3.fromRGB(80,40,0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextScaled = false
		label.ZIndex = 21
		label.Parent = banner

		TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Position = UDim2.new(0.5,0,0,10)}):Play()

		local function playConfettiSound()
				local sound = Instance.new("Sound")
				sound.SoundId = "rbxassetid://112825313814792"
				sound.Volume = 0.8
				sound.Parent = workspace
				sound:Play()
				game:GetService("Debris"):AddItem(sound, 5)
			end

			task.spawn(function()
				playConfettiSound()
				for i = 1, 30 do
					task.wait(0.05)
					local confetti = Instance.new("Frame")
				confetti.Size = UDim2.new(0, math.random(8,14), 0, math.random(8,14))
				confetti.Position = UDim2.new(math.random(20,80)/100, 0, 0, math.random(-10,0))
				confetti.BackgroundColor3 = Color3.fromHSV(math.random(0,100)/100, 1, 1)
				confetti.BorderSizePixel = 0
				confetti.ZIndex = 22
				confetti.Rotation = math.random(0,360)
				confetti.Parent = bannerGui
				local uic = Instance.new("UICorner"); uic.CornerRadius = UDim.new(0,2); uic.Parent = confetti
				TweenService:Create(confetti, TweenInfo.new(2), {
					Position = UDim2.new(confetti.Position.X.Scale, 0, 1, 50),
					Rotation = math.random(360),
					BackgroundTransparency = 1
				}):Play()
				game:GetService("Debris"):AddItem(confetti, 2.1)
			end
		end)

		task.delay(4, function()
			TweenService:Create(banner, TweenInfo.new(0.3),
				{Position = UDim2.new(0.5,0,0,-70)}):Play()
			task.wait(0.4)
			bannerGui:Destroy()
		end)
end

local PAE = RS:WaitForChild("PurchaseAnnouncementEvent", 10)
if PAE then
	PAE.OnClientEvent:Connect(function(playerName, itemName, isGamepass)
		showPurchaseBanner(playerName, itemName, isGamepass)
	end)
end
end

-- ===== BRIGHT FLAT STYLE =====
-- IIFE keeps locals out of the outer function's 200-register budget
;(function()
	-- Fredoka + white + black stroke on every text element
	for _, v in ipairs(PlayerGui:GetDescendants()) do
		if v:IsA("TextLabel") or v:IsA("TextButton") then
			v.Font = Enum.Font.FredokaOne
			v.TextColor3 = Color3.fromRGB(255,255,255)
			v.TextScaled = true
			local ts = v:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
			ts.Color = Color3.fromRGB(0,0,0); ts.Thickness = 2; ts.Parent = v
		end
	end

	-- COIN PILL  (variable: coinPill, line 106)
	local cg = coinPill:FindFirstChildOfClass("UIGradient"); if cg then cg:Destroy() end
	coinPill.BackgroundColor3 = Color3.fromRGB(255,180,0)
	local cpC = coinPill:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	cpC.CornerRadius = UDim.new(0,20); cpC.Parent = coinPill
	local cpS = coinPill:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	cpS.Color = Color3.fromRGB(180,100,0); cpS.Thickness = 3; cpS.Parent = coinPill

	-- SHOP BUTTON  (variable: shopSideFrame, line 301)
	shopSideFrame.BackgroundColor3 = Color3.fromRGB(80,200,80)
	local shC = shopSideFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	shC.CornerRadius = UDim.new(0,16); shC.Parent = shopSideFrame
	local shS = shopSideFrame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	shS.Color = Color3.fromRGB(30,120,30); shS.Thickness = 3; shS.Parent = shopSideFrame

	-- INVITE BUTTON  (variable: inviteSideFrame, line 302)
	inviteSideFrame.BackgroundColor3 = Color3.fromRGB(160,80,220)
	local inC = inviteSideFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	inC.CornerRadius = UDim.new(0,16); inC.Parent = inviteSideFrame
	local inS = inviteSideFrame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	inS.Color = Color3.fromRGB(80,30,140); inS.Thickness = 3; inS.Parent = inviteSideFrame

	-- DAILY BUTTON  (variable: dailySideFrame, line 303)
	dailySideFrame.BackgroundColor3 = Color3.fromRGB(255,150,30)
	local daC = dailySideFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	daC.CornerRadius = UDim.new(0,16); daC.Parent = dailySideFrame
	local daS = dailySideFrame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	daS.Color = Color3.fromRGB(180,80,0); daS.Thickness = 3; daS.Parent = dailySideFrame

	-- RIGHT PANEL  (variable: rightPanel, line 160)
	rightPanel.BackgroundColor3 = Color3.fromRGB(40,120,220)
	local rpC = rightPanel:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	rpC.CornerRadius = UDim.new(0,20); rpC.Parent = rightPanel
	local rpS = rightPanel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	rpS.Color = Color3.fromRGB(20,60,160); rpS.Thickness = 3; rpS.Parent = rightPanel
	statsTitle.TextColor3 = Color3.fromRGB(255,220,0)

	-- MID AIR BUTTON  (variable: midAir, line 210)
	midAir.BackgroundColor3 = Color3.fromRGB(50,160,255)
	local maC = midAir:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	maC.CornerRadius = UDim.new(0,14); maC.Parent = midAir
	local maS = midAir:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	maS.Color = Color3.fromRGB(20,80,180); maS.Thickness = 3; maS.Parent = midAir
	midAirPrice.TextColor3 = Color3.fromRGB(100,255,100)

	-- 2X BUTTON  (variable: twoX, line 235)
	twoX.BackgroundColor3 = Color3.fromRGB(160,80,220)
	local txC = twoX:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	txC.CornerRadius = UDim.new(0,14); txC.Parent = twoX
	local txS = twoX:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	txS.Color = Color3.fromRGB(80,30,140); txS.Thickness = 3; txS.Parent = twoX
	twoXPrice.TextColor3 = Color3.fromRGB(100,255,100)
	twoXTimerText.TextColor3 = Color3.fromRGB(100,255,100)

	-- BIRD NUKE BUTTON  (variable: birdNuke, line 269)
	birdNuke.BackgroundColor3 = Color3.fromRGB(255,70,70)
	local bnC = birdNuke:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	bnC.CornerRadius = UDim.new(0,14); bnC.Parent = birdNuke
	local bnS = birdNuke:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	bnS.Color = Color3.fromRGB(160,20,20); bnS.Thickness = 3; bnS.Parent = birdNuke
	birdPrice.TextColor3 = Color3.fromRGB(100,255,100)

	-- GAS METER CONTAINER
	_G.gui.gasMeterPanel.BackgroundColor3 = Color3.fromRGB(30,80,180)
	local gmC = _G.gui.gasMeterPanel:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	gmC.CornerRadius = UDim.new(0,16); gmC.Parent = _G.gui.gasMeterPanel
	local gmS = _G.gui.gasMeterPanel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	gmS.Color = Color3.fromRGB(20,40,120); gmS.Thickness = 3; gmS.Parent = _G.gui.gasMeterPanel
	if _G.gui.gasTitleLabel then _G.gui.gasTitleLabel.TextColor3 = Color3.fromRGB(255,255,100) end

	-- GAS BAR BACKGROUND
	_G.gui.gasBg.BackgroundColor3 = Color3.fromRGB(20,20,60)
	local gbC = _G.gui.gasBg:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	gbC.CornerRadius = UDim.new(0,12); gbC.Parent = _G.gui.gasBg

	-- GAS BAR FILL gradient
	local gfC = _G.gui.gasFill:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	gfC.CornerRadius = UDim.new(0,12); gfC.Parent = _G.gui.gasFill
	local gg = _G.gui.gasFill:FindFirstChildOfClass("UIGradient")
	if gg then gg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(255,50,50)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255,220,0)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(50,255,50)),
	}) end

	-- FART BUTTON FRAME
	_G.gui.fartBtnFrame.BackgroundColor3 = Color3.fromRGB(80,210,80)
	local fbC = _G.gui.fartBtnFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	fbC.CornerRadius = UDim.new(0,16); fbC.Parent = _G.gui.fartBtnFrame
	local fbS = _G.gui.fartBtnFrame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	fbS.Color = Color3.fromRGB(30,130,30); fbS.Thickness = 4; fbS.Parent = _G.gui.fartBtnFrame
	_G.gui.fartBtnGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80,210,80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60,180,60)),
	})
end)()

;(function()
	-- BRIGHTER COLORS + RESIZE
	_G.gui.fartBtnFrame.BackgroundColor3 = Color3.fromRGB(50,220,50)
	_G.gui.fartBtnGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(50,220,50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30,190,30)),
	})
	_G.gui.gasMeterPanel.BackgroundColor3 = Color3.fromRGB(20,140,255)
	_G.gui.gasBg.BackgroundColor3 = Color3.fromRGB(20,20,80)
	local gg2 = _G.gui.gasFill:FindFirstChildOfClass("UIGradient")
	if gg2 then gg2.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(255,30,30)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255,230,0)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(0,255,80)),
	}) end
	shopSideFrame.BackgroundColor3 = Color3.fromRGB(50,220,50)
	inviteSideFrame.BackgroundColor3 = Color3.fromRGB(180,80,255)
	dailySideFrame.BackgroundColor3 = Color3.fromRGB(255,160,20)
	shopSideFrame.Size = UDim2.new(0,95,0,95)
	inviteSideFrame.Size = UDim2.new(0,95,0,95)
	dailySideFrame.Size = UDim2.new(0,95,0,95)
	rightPanel.BackgroundColor3 = Color3.fromRGB(30,140,255)
	midAir.BackgroundColor3 = Color3.fromRGB(20,180,255)
	twoX.BackgroundColor3 = Color3.fromRGB(180,80,255)
	birdNuke.BackgroundColor3 = Color3.fromRGB(255,60,60)
	midAir.Size = UDim2.new(1,-16,0,78)
	twoX.Size = UDim2.new(1,-16,0,78)
	birdNuke.Size = UDim2.new(1,-16,0,78)
end)()

updateFartBtn(); updateMeter(); updateCoins()
_G.CoreClientReady=true
print("CORECLIENT READY")

-- ON-JOIN STATE RESTORE HANDSHAKE: the full HUD is now built and every RemoteEvent handler is connected
-- (the gut label via StomachUpdateEvent, forever passes via GamepassEvent). Ask the server to (re)send
-- our saved state now. Because this fires AFTER the GUI/handlers exist, slow-loading mobile/console
-- clients reliably receive + apply the gut label + forever gamepasses without opening any menu. Works
-- identically on every platform (no desktop-only event/input involved).
task.spawn(function()
	local req = RS:WaitForChild("RequestPlayerState", 30)
	if req then req:FireServer() end
end)
print("DONE")
print("FIXED")
