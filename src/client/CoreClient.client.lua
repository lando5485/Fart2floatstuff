-- ############################################################################
-- ## LUAU REGISTER BUDGET -- READ BEFORE ADDING A TOP-LEVEL `local`         ##
-- ############################################################################
-- A Luau function may hold at most 200 live local registers, and this script's
-- MAIN CHUNK is one such function. It currently sits at ~189. If you push it
-- over 200, the whole file fails to COMPILE with:
--     "Out of local registers when trying to allocate X: exceeded limit 200"
-- and NONE of this script runs -- no HUD, no gas meter, no fart button, no coin
-- counter -- while every other script keeps working. It looks like "the game
-- didn't load", not like a script error. (This already happened once.)
--
-- To add more code here, put it in an IIFE:  ;(function() ... end)()
-- A `do ... end` block is NOT enough on its own: it is not a function scope, so
-- its locals still allocate from THIS chunk's 200 -- they are merely freed at
-- `end`. That is fine for short-lived setup constants (see the sound blocks
-- below) but useless for anything that must stay live.
-- ############################################################################
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
	-- The LoadingScreen has a black 50%-transparent shadow image (BarWrapShadow) that, if it lingers after
	-- spawn, reads as a dark film over the screen (incl. the gas meter). Make sure it's fully gone.
	local lp = game.Players.LocalPlayer
	local ls = lp.PlayerGui:FindFirstChild("LoadingScreen")
	if ls then
		print("[LSCHECK] LoadingScreen STILL PRESENT after spawn, Enabled="..tostring(ls.Enabled))
		ls.Enabled = false
		ls:Destroy()
		print("[LSCHECK] LoadingScreen destroyed")
	else
		print("[LSCHECK] LoadingScreen already gone")
	end
end
player.CharacterAdded:Connect(revealHud)
if player.Character then revealHud() end -- safety: if a character somehow already exists

-- ===== UI CLICK SOUND =====
-- One click sound shared by ALL main-menu buttons (open + close). Clone-and-play so rapid
-- presses don't cut each other off. Parented to PlayerGui => 2D, audible only to this player.
-- This is UI-only; it is NOT wired to any gameplay event (flying/food/rings).
-- REGISTER BUDGET: the setup locals sit in a do-block so Luau FREES their registers at `end`.
-- Only playUIClick stays in the main chunk. See the 200-local ceiling note at the top of the file.
local playUIClick
do
	local UI_CLICK_VOLUME = 0.5 -- single adjustable volume for every menu click
	local uiClickSound = Instance.new("Sound")
	uiClickSound.Name = "UIClickSound"
	uiClickSound.SoundId = "rbxassetid://101638558691673"
	uiClickSound.Volume = UI_CLICK_VOLUME
	uiClickSound.Parent = PlayerGui
	function playUIClick()
		local s = uiClickSound:Clone()
		s.Parent = PlayerGui
		s:Play()
		game:GetService("Debris"):AddItem(s, 3)
	end
end
_G.playUIClick = playUIClick

-- ===== INSUFFICIENT-FUNDS ERROR SOUND =====
-- Played ONLY when a coin-priced stomach buy is attempted without enough coins.
-- Clone-and-play (audible to local player); single adjustable volume.
local playErrorSound
do -- REGISTER BUDGET: setup locals scoped so their registers are freed (see the note at the top).
	local ERROR_SOUND_VOLUME = 0.6
	local errorSound = Instance.new("Sound")
	errorSound.Name = "InsufficientFundsSound"
	errorSound.SoundId = "rbxassetid://87486053112716"
	errorSound.Volume = ERROR_SOUND_VOLUME
	errorSound.Parent = PlayerGui
	function playErrorSound()
		local s = errorSound:Clone()
		s.Parent = PlayerGui
		s:Play()
		game:GetService("Debris"):AddItem(s, 3)
	end
end

-- Quick left-right wobble for "can't afford" feedback on a button (~0.3s, small px shake, then
-- returns to its original Position). Guarded so rapid taps don't stack or leave it off-center.
local shakeButton
do -- REGISTER BUDGET: SHAKE_OFFSET scoped so its register is freed (see the note at the top).
	local SHAKE_OFFSET = 8 -- px each side
	function shakeButton(btn)
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
end

-- ===== FART SOUNDS =====
-- Played ONLY when the player starts a fart/ascent (toggle-on). One reusable Sound: each start
-- stops any in-progress fart and plays a fresh random pick, so rapid toggles never overlap.
-- Parented to SoundService => 2D, audible to the local player. FART_VOLUME is the single adjustable volume.
local playFartSound
do -- REGISTER BUDGET: setup locals scoped so their registers are freed (see the note at the top).
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
	function playFartSound()
		fartSound:Stop() -- cut any in-progress fart so rapid re-toggles don't stack
		local chosenId = FART_SOUND_IDS[math.random(1, #FART_SOUND_IDS)]
		fartSound.SoundId = chosenId
		print("FART SOUND playing id="..chosenId)
		fartSound:Play()
	end
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
-- REBIRTH flight-speed bonus: +3% per rebirth, read live off the Rebirths leaderstat (set by RebirthSystem).
_G.rebirthSpeedMult=1
task.spawn(function()
	local REBIRTH_SPEED_PER = 0.03
	local plr = game:GetService("Players").LocalPlayer
	local ls  = plr:WaitForChild("leaderstats", 30); if not ls then return end
	local rb  = ls:WaitForChild("Rebirths", 30);     if not rb then return end
	local function apply() _G.rebirthSpeedMult = 1 + REBIRTH_SPEED_PER * math.max(0, rb.Value) end
	apply(); rb.Changed:Connect(apply)
end)
_G.windstormDir=Vector3.new(1,0,0); _G.stormWindTimer=0; _G.activeBirds={}
_G.thunderWindVec=Vector3.new(0,0,0) -- LIGHT varying thunderstorm wind (set by EventClient); zero = no push
-- ===== WORLD TABLES (populated by WorldClient) =====
_G.activeRings={}; _G.activeGasPockets={}; _G.landingPads={}
-- ===== GAMEPASS STATE =====
local playerGamepasses = {twoXForever=false, glitterTrail=false, midAirRecharge=0, skipIsland=0, twoXHourExpiry=0}
_G.playerGamepasses = playerGamepasses
_G.gui = {}

-- ===== LOCAL STATE =====
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
-- Climb-speed multiplier while carrying the Gardener's watering can. A full can is heavy: you CAN still fly
-- with it, you just fly worse -- which is the joke. 0.7 = a noticeable drag without stranding anyone.
local CAN_WEIGHT_MULT = 0.7
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

-- Disable default Roblox CoreGui elements (health bar / backpack hotbar / player list) that draw behind our
-- custom HUD -- the dark strip over the gas meter is one of these core elements, not a PlayerGui object.
do
	local StarterGui = game:GetService("StarterGui")
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false) end)
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)
	print("[COREGUI] health + backpack + playerlist core elements disabled")
end

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
-- Theme: a growing APPETITE -> strength -> endless. Each gut is its own creature/icon (not the old baby->child->
-- man aging line). Tiny stays a baby + Infinite stays a whale; Iron is a weightlifter (a gut of iron).
_G.GUT_EMOJI = {
	["Tiny Gut"]     = "\xF0\x9F\x91\xB6",             -- 👶 baby (tiny tummy)
	["Small Gut"]    = "\xF0\x9F\x90\xB9",             -- 🐹 hamster (stuffs its cheeks)
	["Medium Gut"]   = "\xF0\x9F\x90\xB7",             -- 🐷 pig (greedy eater)
	["Large Gut"]    = "\xF0\x9F\x90\x98",             -- 🐘 elephant (big belly)
	["XL Gut"]       = "\xF0\x9F\xA6\x9B",             -- 🦛 hippo (huge belly) -- XL shows GUT_IMAGE; this is the fallback
	["Iron Gut"]     = "\xF0\x9F\x8F\x8B\xEF\xB8\x8F", -- 🏋️ weightlifter (a gut of iron)
	["Infinite Gut"] = "\xF0\x9F\x90\x8B",             -- 🐋 whale (endless appetite)
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
-- ===== MAIN-MENU MUTUAL EXCLUSIVITY: a tiny shared manager (ONE instance across all client scripts, via _G)
-- so only ONE main menu (food shop / food stand / pet hub / stomach shop / premium shop) is open at a time.
-- Opening any registered menu first CLOSES whichever other one is open (direct click-to-switch, no X needed).
-- The factory is guarded so whichever client script loads first creates it and the rest reuse it. =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end          -- each menu provides a full-hide fn
	function mgr.setHud(visible)                                                -- hide/show the WHOLE bottom HUD (gut pill + gas meter + fart button all live in BottomStackGui)
		local lp = game:GetService("Players").LocalPlayer
		local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
		local g = pg and pg:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)                                             -- call right BEFORE showing a menu
		if mgr.current and mgr.current ~= name then
			local h = mgr.hiders[mgr.current]; if h then pcall(h) end           -- fully close the other open menu
		end
		mgr.current = name
		mgr.setHud(false)                                                       -- a main menu is now open -> hide the bottom HUD (Shop/Pet Hub/Seasonal Pets all route through here)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end                       -- call when a menu hides
		if mgr.current == nil then mgr.setHud(true) end                         -- last menu closed -> restore the bottom HUD
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end  -- a DIFFERENT menu is open?
	_G.MainMenuManager = mgr
end
-- toggle an Enabled-driven menu through the manager (open => first close any other; close => clear current)
local function toggleMainMenu(name, guiName)
	local g = PlayerGui:FindFirstChild(guiName); if not g then return end
	print("[MenuMgr] button "..name.." clicked while "..tostring(_G.MainMenuManager.current).." open") -- diagnostic: confirms the click is received even with another menu open
	if g.Enabled then
		g.Enabled = false; _G.MainMenuManager.notifyClosed(name)
	else
		_G.MainMenuManager.notifyOpened(name) -- direct switch: closes any other open main menu first
		g.Enabled = true
	end
end
-- register full-hide fns for the two menus CoreClient drives (used when ANOTHER menu opens over them)
_G.MainMenuManager.register("Premium", function() local g=PlayerGui:FindFirstChild("PremiumShopGui"); if g then g.Enabled=false end end)
_G.MainMenuManager.register("Stomach", function() local g=PlayerGui:FindFirstChild("StomachShopGui"); if g then g.Enabled=false end end)

coinPlusBtn.MouseButton1Click:Connect(function()
	toggleMainMenu("Premium", "PremiumShopGui")
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

-- Farts stat REMOVED from the stats display (was the last row at y=116; "Max Height" above is now
-- the bottom stat, so the remaining rows stay contiguous with no gap). The TotalFartPower leaderstat
-- it read is untouched — it's still tracked server-side and used by flight/power.

-- ===== SPACE REALM PROGRESS (bottom of the STATS section) =====
-- A bar + percentage showing how close the player is to the FINAL island / the Space Realm (the black hole above
-- Pizza Palms = island 14). Driven by the server's authoritative "HighestIsland" player attribute (set on landing /
-- island-skip / load), so it climbs live as new islands are reached -- the "99% to space" progress big games show.
local SPACE_TOTAL_ISLANDS = 14
local spaceRealmTitle = Instance.new("TextLabel")
spaceRealmTitle.Size = UDim2.new(1,0,0,22); spaceRealmTitle.Position = UDim2.new(0,0,0,116)
spaceRealmTitle.BackgroundTransparency = 1; spaceRealmTitle.Text = "\xF0\x9F\x9A\x80 TO SPACE REALM"
spaceRealmTitle.Font = Enum.Font.GothamBold; spaceRealmTitle.TextSize = 16; spaceRealmTitle.TextColor3 = Color3.fromRGB(190,210,255)
spaceRealmTitle.TextScaled = true; spaceRealmTitle.RichText = false
spaceRealmTitle.TextXAlignment = Enum.TextXAlignment.Left; spaceRealmTitle.Parent = statsSection
local spaceBarBG = Instance.new("Frame")
spaceBarBG.Size = UDim2.new(1,-2,0,22); spaceBarBG.Position = UDim2.new(0,0,0,142)
spaceBarBG.BackgroundColor3 = Color3.fromRGB(10,14,36); spaceBarBG.BorderSizePixel = 0; spaceBarBG.ZIndex = 4; spaceBarBG.Parent = statsSection
mkCorner(spaceBarBG, 9); mkStroke(spaceBarBG, Color3.fromRGB(8,10,28), 1)
local spaceFill = Instance.new("Frame")
spaceFill.Size = UDim2.new(0,0,1,0); spaceFill.BackgroundColor3 = Color3.fromRGB(90,200,120); spaceFill.BorderSizePixel = 0; spaceFill.ZIndex = 4; spaceFill.Parent = spaceBarBG
mkCorner(spaceFill, 9)
local spacePctLabel = Instance.new("TextLabel")
spacePctLabel.Size = UDim2.new(1,-8,1,0); spacePctLabel.Position = UDim2.new(0,4,0,0); spacePctLabel.BackgroundTransparency = 1
spacePctLabel.Font = Enum.Font.GothamBold; spacePctLabel.TextSize = 13; spacePctLabel.TextColor3 = Color3.new(1,1,1)
spacePctLabel.TextScaled = true; spacePctLabel.RichText = false; spacePctLabel.ZIndex = 5; spacePctLabel.Parent = spaceBarBG
mkStroke(spacePctLabel, Color3.new(0,0,0), 1)
local function updateSpaceRealmProgress()
	local hi = math.clamp(math.floor(tonumber(player:GetAttribute("HighestIsland")) or 1), 1, SPACE_TOTAL_ISLANDS)
	local frac = hi / SPACE_TOTAL_ISLANDS
	spaceFill.Size = UDim2.new(frac, 0, 1, 0)
	-- green up the islands, then space-purple once the top (island 14 -> the realm gate) is reached
	spaceFill.BackgroundColor3 = (hi >= SPACE_TOTAL_ISLANDS) and Color3.fromRGB(170,110,255) or Color3.fromRGB(90,200,120)
	spacePctLabel.Text = "Island " .. hi .. "/" .. SPACE_TOTAL_ISLANDS .. "  -  " .. math.floor(frac * 100 + 0.5) .. "%"
end
updateSpaceRealmProgress()
player:GetAttributeChangedSignal("HighestIsland"):Connect(updateSpaceRealmProgress) -- climbs live as new islands are reached

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
local setMoreOpen, openLocker  -- MORE+ popup toggler + Locker opener (assigned after the sidebar, below)
local moreOpenState = false    -- is the MORE+ popup currently open?
local shopSideFrame,shopSideClick=mkSideBtn(-90*scale,Color3.fromRGB(50,180,50),"\xF0\x9F\x9b\x92","SHOP")
-- PETS button (was WORMHOLE -> was REBIRTH -> was INVITE). Var names kept (inviteSideFrame/inviteSideClick) so the
-- HUD layout + restyle passes still target this slot. Wormhole moved into the MORE+ menu -- fast travel is a
-- sometimes action; the pet hub is an every-minute one, so Pets holds the always-visible slot.
local inviteSideFrame,inviteSideClick=mkSideBtn(0,Color3.fromRGB(80,170,70),"\xF0\x9F\x90\xBE","PETS")
-- SWAP: the STOMACH button now lives here on the main screen, in the PETS button's OLD slot (same anchor/position/
-- size/styling). It keeps its OWN icon (GUT_IMAGE), label ("Stomach"), and click action (opens the stomach shop).
-- Var names dailySideFrame/dailySideClick are kept so the existing HUD layout + restyle code still target this slot.
local dailySideFrame,dailySideClick=mkSideBtn(90*scale,Color3.fromRGB(80,170,70),"","Stomach")
do -- the stomach's own icon is an IMAGE (GUT_IMAGE), so overlay it in the side button's icon area
	local gutIcon=Instance.new("ImageLabel")
	gutIcon.Name="Icon"; gutIcon.BackgroundTransparency=1; gutIcon.Image=_G.GUT_IMAGE; gutIcon.ScaleType=Enum.ScaleType.Fit
	gutIcon.Size=UDim2.new(0,math.floor(40*scale),0,math.floor(40*scale)); gutIcon.Position=UDim2.new(0.5,0,0,6); gutIcon.AnchorPoint=Vector2.new(0.5,0)
	gutIcon.ZIndex=3; gutIcon.Parent=dailySideFrame
end
-- MORE+ side button (REPLACES the old STOMACH button -- Stomach now lives inside the MORE+ popup). Var names are
-- kept (stomachSideFrame/stomachSideClick) so the existing HUD layout reposition + stomach-label refresh still apply.
local stomachSideFrame,stomachSideClick=mkSideBtn(180*scale,Color3.fromRGB(225,70,170),"+","MORE")
shopSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	toggleMainMenu("Premium", "PremiumShopGui")
end)
inviteSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	-- _G.togglePetHub (PetFollow's own toggle) first: a baked-in PetHub_AllInOne kit creates a SECOND
	-- BindableEvent named PetInvToggle, and FindFirstChild can return the impostor. Event = fallback only.
	if _G.togglePetHub then
		pcall(_G.togglePetHub)
	else
		local ev = PlayerGui:FindFirstChild("PetInvToggle")
		if ev then ev:Fire() end
	end
end)
dailySideClick.MouseButton1Click:Connect(function()
	playUIClick()
	toggleMainMenu("Stomach", "StomachShopGui") -- SWAP: this main-screen slot now opens the stomach shop (same call the old More+ Stomach entry used)
end)
stomachSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	setMoreOpen(not moreOpenState) -- MORE+ toggles its popup (Stomach lives inside it now)
end)

-- ===== HUD NOTICE BANNER =====
-- MATCHED to the game's other banners (Arrival/Announce): same 500x65 top-center frame that slides
-- from y=-100 down to y=10. Text-only (no emoji glyphs, which don't render in published games). Used
-- for "Stomach Upgrade Available" + "Daily Reward Ready". The periodic scheduler below flashes it
-- every 20s for 4s while a reward is available AND nothing else is on screen.
local NOTICE_SHOWN  = UDim2.new(0.5, 0, 0, 10)   -- where the Arrival/Announce banners rest
local NOTICE_HIDDEN = UDim2.new(0.5, 0, 0, -100)
local noticeGui = Instance.new("ScreenGui")
noticeGui.Name = "HudNoticeGui"; noticeGui.ResetOnSpawn = false; noticeGui.IgnoreGuiInset = true
noticeGui.DisplayOrder = 90; noticeGui.Parent = PlayerGui
local noticeFrame = mkFrame(noticeGui, {
	Size = UDim2.new(0, 500, 0, 65), AnchorPoint = Vector2.new(0.5, 0), Position = NOTICE_HIDDEN,
	BackgroundColor3 = Color3.fromRGB(40, 160, 90), Visible = false,
})
mkCorner(noticeFrame, 16); mkStroke(noticeFrame, Color3.new(1, 1, 1), 3)
local noticeLabel = mkLabel(noticeFrame, {
	Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 12, 0, 0),
	Text = "", Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
})
mkStroke(noticeLabel, Color3.new(0, 0, 0), 2)
local noticeSeq = 0
-- Suppress the banner while ANYTHING else is happening: a server event, an open shop/menu, the crate
-- reveal, or another banner already on screen -- so it never collides with on-screen activity.
-- Is it a bad moment to nag the player? NotifyCenter now owns banner-vs-banner arbitration, so this
-- only has to answer the question it is actually good at: "is the player busy with something else?"
-- Storm/windstorm/nuke are checked explicitly -- they set their OWN flags, not _G.serverEventActive,
-- so the old gate happily fired a "Daily Reward Ready!" nag in the middle of a thunderstorm.
local function bannerBusy()
	if _G.serverEventActive or _G.thunderstormActive or _G.windstormActive then return true end
	if _G.MainMenuManager and _G.MainMenuManager.current then return true end
	if _G.NotifyCenter and _G.NotifyCenter.isBusy() then return true end
	local rev = PlayerGui:FindFirstChild("MeteorCrateReveal")
	if rev and rev.Enabled then return true end
	return false
end
-- A nudge, not news: lowest hero priority, so a real island unlock or purchase preempts it instantly.
local function showHudBanner(text, color, holdSeconds)
	local NC = _G.NotifyCenter
	if not NC then return end
	NC.push({
		text     = text,
		color    = color or Color3.fromRGB(40, 160, 90),
		priority = NC.PRIORITY.REWARD,
		duration = holdSeconds or 4,
	})
end
_G.showHudBanner = showHudBanner
-- Periodic reminder: every 20s, if a reward is available and nothing else is on screen, flash the
-- banner for 4s. Crate takes priority over the gut upgrade. Stops on its own once claimed/bought (the
-- _G flags flip false). [crate = _G.crateIsClaimable() from CrateClient; gut = _G.gutUpgradeAffordable]
task.spawn(function()
	while true do
		task.wait(20)
		if not bannerBusy() then
			if _G.crateIsClaimable and _G.crateIsClaimable() then
				showHudBanner("Daily Reward Ready!  Tap MORE+", Color3.fromRGB(255, 196, 60), 4)
			elseif _G.gutUpgradeAffordable then
				showHudBanner("Stomach Upgrade Available!", Color3.fromRGB(60, 180, 90), 4)
			end
		end
	end
end)

-- ===== MORE+ POPUP MENU + SEASONAL LOCKER ==============================================================
-- The pink MORE+ side button opens a small rounded popup near the sidebar listing extra menus. It's DATA-DRIVEN:
-- add a row to MORE_ENTRIES to add more later. "Stomach" opens the EXISTING stomach shop (same call the old
-- STOMACH button used); "Locker" opens the seasonal cosmetics Locker (built just below).
do
	-- ===== SEASONAL LOCKER: expandable season cards + a big ViewportFrame pet preview, wired to the REAL seasonal pets
	-- (equips via the SAME PetEquipEvent the pet inventory uses). Ownership is read from PetStateEvent; live garden
	-- progress from the Workspace GardenProgress/GardenGoal/GardenSeason attributes the server mirrors. =====
	local RSx = game:GetService("ReplicatedStorage")
	local PetEquipEvent = RSx:FindFirstChild("PetEquipEvent")
	local PetStateEvent = RSx:FindFirstChild("PetStateEvent")
	local PetReqState   = RSx:FindFirstChild("PetRequestStateEvent")
	local SEASONS = {
		{ season="Summer", petId="SunflowerBee", petName="Sunflower Bee", tmpl="SunflowerBeeTemplate", icon="\xF0\x9F\x8C\xBB", card=Color3.fromRGB(250,243,205), accent=Color3.fromRGB(232,180,50), desc="A cheerful honeybee wrapped in sunflower petals -- the Summer harvest reward." },
		{ season="Autumn", petId="MapleFox",     petName="Maple Fox",     tmpl="MapleFoxTemplate",     icon="\xF0\x9F\x8D\x81", card=Color3.fromRGB(246,206,170), accent=Color3.fromRGB(214,118,46), desc="A cozy little fox in warm autumn colors -- the Autumn harvest reward." },
		{ season="Winter", petId="FrostPenguin", petName="Frost Penguin", tmpl="FrostPenguinTemplate", icon="\xE2\x9D\x84",     card=Color3.fromRGB(208,226,246), accent=Color3.fromRGB(86,148,206),  desc="A frosty penguin topped with little ice crystals -- the Winter harvest reward." },
		{ season="Spring", petId="BlossomBunny", petName="Blossom Bunny", tmpl="BlossomBunnyTemplate", icon="\xF0\x9F\x8C\xB8", card=Color3.fromRGB(248,216,228), accent=Color3.fromRGB(228,128,168), desc="A gentle bunny wearing a fresh flower crown -- the Spring harvest reward." },
	}
	local seasonalOwned, seasonalEquipped = {}, nil
	local expanded = nil
	local cardRefreshers = {}
	local refreshLocker -- forward
	local WHT = Color3.new(1,1,1)
	local lockerSpins = {} -- { {model, center}, ... } -- slow-spun while the locker is open (SAME as the pet inventory icons)
	local function gProgress() return tonumber(workspace:GetAttribute("GardenProgress")) or 0 end
	local function gGoal()     return tonumber(workspace:GetAttribute("GardenGoal")) or 2000 end
	local function gSeason()   return tostring(workspace:GetAttribute("GardenSeason") or "Summer") end
	-- render a pet template inside a ViewportFrame (lazy-fill: templates replicate a moment after join). Built EXACTLY
	-- like the pet-inventory icons (root at origin, camera framed to the bounding box) so it can spin the same way.
	local function fillViewport(vp, tmplName)
		if vp:FindFirstChildWhichIsA("Model") then return end
		local tmpl = RSx:FindFirstChild(tmplName); if not tmpl then return end
		local m = tmpl:Clone()
		for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end end
		pcall(function()
			m:PivotTo(CFrame.new()) -- root at origin (same as the inventory icons)
			m.Parent = vp
			local cam = Instance.new("Camera"); cam.FieldOfView = 50; cam.Parent = vp; vp.CurrentCamera = cam
			local cf, size = m:GetBoundingBox()
			local maxe = math.max(size.X, size.Y, size.Z, 1)
			local center = cf.Position
			local dir = Vector3.new(0.8, 0.5, 0.55).Unit -- 3/4 front view (pets face +X), slightly above
			cam.CFrame = CFrame.lookAt(center + dir * (maxe * 1.45 + 1), center)
			vp.Ambient = Color3.fromRGB(185,185,195); vp.LightColor = Color3.fromRGB(255,255,255); vp.LightDirection = Vector3.new(-0.4,-1,-0.5)
			lockerSpins[#lockerSpins+1] = { model = m, center = center } -- register for the shared spin loop
		end)
	end

	-- --- panel ---
	local lockerGui = Instance.new("ScreenGui"); lockerGui.Name = "LockerGui"; lockerGui.ResetOnSpawn = false
	lockerGui.DisplayOrder = 100; lockerGui.Enabled = false; lockerGui.Parent = PlayerGui -- EXACT same ScreenGui settings as the SHOP (PremiumShopGui): DisplayOrder 100, no IgnoreGuiInset
	-- EXACT same Size + Position + AnchorPoint as the SHOP menu's FINAL layout (PremiumShopGui's premPanel, after its
	-- layout pass): 700 x 520 fixed, centered, nudged up 45px. No UIScale/UISizeConstraint/UIAspectRatioConstraint on the Shop.
	local lockPanel = mkFrame(lockerGui, { Size = UDim2.new(0, 700, 0, 520), Position = UDim2.new(0.5, 0, 0.5, -45), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(245, 238, 214), ClipsDescendants = true })
	mkCorner(lockPanel, 18); mkStroke(lockPanel, Color3.fromRGB(120, 78, 40), 4)
	local function lockerFit() end -- no-op: the panel now uses the SHOP's static scale-based geometry (kept as a stub so existing call sites still work)
	-- header (dark wood)
	local lockHead = mkFrame(lockPanel, { Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Color3.fromRGB(74, 48, 30), BorderSizePixel = 0 })
	mkLabel(lockHead, { Text = "\xF0\x9F\x8C\xBB", Font = Enum.Font.FredokaOne, TextSize = 20, Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(0, 16, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center })
	mkLabel(lockHead, { Text = "Seasonal Pets", Font = Enum.Font.FredokaOne, TextSize = 22, TextColor3 = WHT, Size = UDim2.new(1, -100, 1, 0), Position = UDim2.new(0, 50, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center })
	local lockX = mkButton(lockHead, { Size = UDim2.new(0, 34, 0, 34), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = Color3.fromRGB(210, 60, 55), Text = "X", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = WHT })
	mkCorner(lockX, 9)
	-- subtitle banner (dark-green pill with leaf accents)
	local sub = mkFrame(lockPanel, { Size = UDim2.new(1, -28, 0, 42), Position = UDim2.new(0, 14, 0, 60), BackgroundColor3 = Color3.fromRGB(58, 116, 52) })
	mkCorner(sub, 12)
	mkLabel(sub, { Text = "\xF0\x9F\x8C\xBF", Font = Enum.Font.FredokaOne, TextSize = 16, Size = UDim2.new(0, 24, 1, 0), Position = UDim2.new(0, 8, 0, 0), TextXAlignment = Enum.TextXAlignment.Center })
	mkLabel(sub, { Text = "Grow the Community Garden each season to unlock exclusive pets!", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = WHT, TextWrapped = true, Size = UDim2.new(1, -64, 1, 0), Position = UDim2.new(0, 32, 0, 0), TextXAlignment = Enum.TextXAlignment.Center })
	mkLabel(sub, { Text = "\xF0\x9F\x8C\xBF", Font = Enum.Font.FredokaOne, TextSize = 16, Size = UDim2.new(0, 24, 1, 0), Position = UDim2.new(1, -32, 0, 0), TextXAlignment = Enum.TextXAlignment.Center })
	-- footer (small green strip)
	local footer = mkFrame(lockPanel, { Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 1, -28), BackgroundColor3 = Color3.fromRGB(70, 130, 60), BorderSizePixel = 0 })
	mkLabel(footer, { Text = "New seasons, new rewards. Keep growing!", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = WHT, Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
	-- scrolling list of season cards (between subtitle + footer)
	local scroll = Instance.new("ScrollingFrame"); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
	scroll.Position = UDim2.new(0, 12, 0, 110); scroll.Size = UDim2.new(1, -24, 1, -146); scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 78, 40); scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; scroll.Parent = lockPanel
	local slay = Instance.new("UIListLayout", scroll); slay.Padding = UDim.new(0, 10); slay.SortOrder = Enum.SortOrder.LayoutOrder; slay.HorizontalAlignment = Enum.HorizontalAlignment.Center

	for i, s in ipairs(SEASONS) do
		local card = mkFrame(scroll, { Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = s.card, LayoutOrder = i, ClipsDescendants = true })
		mkCorner(card, 14); mkStroke(card, s.accent, 2)
		local clay = Instance.new("UIListLayout", card); clay.SortOrder = Enum.SortOrder.LayoutOrder
		-- collapsed header row (the whole row is the expand button)
		local hrow = mkButton(card, { Size = UDim2.new(1, 0, 0, 66), BackgroundTransparency = 1, Text = "", LayoutOrder = 1, AutoButtonColor = false })
		local mini = Instance.new("ViewportFrame"); mini.BackgroundColor3 = WHT; mini.BackgroundTransparency = 0.15
		mini.Size = UDim2.new(0, 52, 0, 52); mini.Position = UDim2.new(0, 8, 0.5, 0); mini.AnchorPoint = Vector2.new(0, 0.5); mini.Parent = hrow; mkCorner(mini, 10)
		mkLabel(hrow, { Text = s.icon, Font = Enum.Font.FredokaOne, TextSize = 18, Size = UDim2.new(0, 22, 0, 18), Position = UDim2.new(0, 70, 0, 10), BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left })
		mkLabel(hrow, { Text = s.season:upper(), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = s.accent, Size = UDim2.new(0, 150, 0, 18), Position = UDim2.new(0, 94, 0, 10), TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1 })
		mkLabel(hrow, { Text = s.petName, Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = Color3.fromRGB(60, 45, 30), Size = UDim2.new(0, 220, 0, 24), Position = UDim2.new(0, 70, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1 })
		local pill = mkLabel(hrow, { Text = "LOCKED", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHT, Size = UDim2.new(0, 84, 0, 26), Position = UDim2.new(1, -118, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.fromRGB(150, 120, 90), TextXAlignment = Enum.TextXAlignment.Center }); mkCorner(pill, 13)
		local chev = mkLabel(hrow, { Text = "v", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = s.accent, Size = UDim2.new(0, 24, 1, 0), Position = UDim2.new(1, -28, 0, 0), TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 1 })
		-- expanded content (hidden until this row is the open one)
		local exp = mkFrame(card, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2, Visible = false })
		local ep = Instance.new("UIPadding", exp); ep.PaddingLeft = UDim.new(0, 12); ep.PaddingRight = UDim.new(0, 12); ep.PaddingBottom = UDim.new(0, 12)
		local el = Instance.new("UIListLayout", exp); el.Padding = UDim.new(0, 8); el.SortOrder = Enum.SortOrder.LayoutOrder; el.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local big = Instance.new("ViewportFrame"); big.BackgroundColor3 = WHT; big.BackgroundTransparency = 0.05; big.Size = UDim2.new(1, 0, 0, 150); big.LayoutOrder = 1; big.Parent = exp; mkCorner(big, 12); mkStroke(big, s.accent, 2)
		mkLabel(exp, { Text = s.season:upper() .. " REWARD", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = s.accent, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 1 })
		mkLabel(exp, { Text = s.petName, Font = Enum.Font.FredokaOne, TextSize = 24, TextColor3 = Color3.fromRGB(60, 45, 30), Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 1 })
		local barBG = mkFrame(exp, { Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = Color3.fromRGB(225, 215, 190), LayoutOrder = 4 }); mkCorner(barBG, 11)
		local barFill = mkFrame(barBG, { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(90, 200, 80) }); mkCorner(barFill, 11)
		local barTxt = mkLabel(barBG, { Text = "0 / 2000 Flowers", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.fromRGB(60, 50, 40), Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3, BackgroundTransparency = 1 })
		mkLabel(exp, { Text = s.desc, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Color3.fromRGB(80, 65, 45), TextWrapped = true, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 5, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 1 })
		local equipBtn = mkButton(exp, { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.fromRGB(70, 150, 55), Text = "EQUIP", Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = WHT, LayoutOrder = 6 }); mkCorner(equipBtn, 12)

		hrow.MouseButton1Click:Connect(function() playUIClick(); expanded = (expanded == s.season) and nil or s.season; refreshLocker() end)
		equipBtn.MouseButton1Click:Connect(function()
			playUIClick()
			if not seasonalOwned[s.petId] or not PetEquipEvent then return end
			if seasonalEquipped == s.petId then pcall(function() PetEquipEvent:FireServer(false) end) -- toggle off (same as inventory)
			else pcall(function() PetEquipEvent:FireServer(s.petId) end) end
		end)

		cardRefreshers[i] = function()
			fillViewport(mini, s.tmpl); fillViewport(big, s.tmpl)
			local owns = seasonalOwned[s.petId] == true
			local isExp = (expanded == s.season)
			chev.Text = isExp and "^" or "v"; exp.Visible = isExp
			if owns then
				if seasonalEquipped == s.petId then pill.Text = "EQUIPPED"; pill.BackgroundColor3 = Color3.fromRGB(70, 150, 55)
				else pill.Text = "OWNED"; pill.BackgroundColor3 = Color3.fromRGB(90, 160, 210) end
			else pill.Text = "LOCKED"; pill.BackgroundColor3 = Color3.fromRGB(150, 120, 90) end
			local cur, p, g = gSeason(), gProgress(), gGoal()
			local frac, label
			if owns then frac, label = 1, "Earned \xE2\x9C\x93"
			elseif s.season == cur then frac, label = math.clamp(p / g, 0, 1), string.format("%d / %d Flowers", p, g)
			else frac, label = 0, "0 / " .. g .. " Flowers" end
			barFill.Size = UDim2.new(frac, 0, 1, 0); barTxt.Text = label
			equipBtn.Visible = owns
			equipBtn.Text = (seasonalEquipped == s.petId) and "EQUIPPED \xE2\x9C\x93" or "EQUIP"
			equipBtn.BackgroundColor3 = (seasonalEquipped == s.petId) and Color3.fromRGB(120, 160, 110) or Color3.fromRGB(70, 150, 55)
		end
	end

	refreshLocker = function() for _, fn in ipairs(cardRefreshers) do pcall(fn) end end

	-- live ownership from the pet system (same source the inventory uses) + live garden progress from Workspace attrs
	if PetStateEvent then
		PetStateEvent.OnClientEvent:Connect(function(state)
			if type(state) ~= "table" then return end
			for _, s in ipairs(SEASONS) do
				local info = state[s.petId]
				if info then
					seasonalOwned[s.petId] = info.owns == true
					if info.equipped then seasonalEquipped = s.petId elseif seasonalEquipped == s.petId then seasonalEquipped = nil end
				end
			end
			if lockerGui.Enabled then refreshLocker() end
		end)
	end
	workspace:GetAttributeChangedSignal("GardenProgress"):Connect(function() if lockerGui.Enabled then refreshLocker() end end)
	workspace:GetAttributeChangedSignal("GardenSeason"):Connect(function() if lockerGui.Enabled then refreshLocker() end end)

	-- SLOW AUTO-ROTATE for every locker pet ViewportFrame (mini thumbnails + big preview) -- EXACT same approach as the
	-- pet inventory icons (Y-axis PivotTo about the bounding-box centre at dt*0.6, only while the menu is open).
	do
		local angle = 0
		game:GetService("RunService").RenderStepped:Connect(function(dt)
			if not lockerGui.Enabled or #lockerSpins == 0 then return end
			angle = (angle + dt * 0.6) % (2 * math.pi) -- slow + smooth (same speed/axis as the backpack pets)
			for i = #lockerSpins, 1, -1 do
				local ic = lockerSpins[i]
				if ic.model and ic.model.Parent then
					ic.model:PivotTo(CFrame.new(ic.center) * CFrame.Angles(0, angle, 0) * CFrame.new(-ic.center))
				else
					table.remove(lockerSpins, i)
				end
			end
		end)
	end

	_G.MainMenuManager.register("Locker", function() lockerGui.Enabled = false end) -- closed when another menu opens
	lockX.MouseButton1Click:Connect(function() playUIClick(); lockerGui.Enabled = false; _G.MainMenuManager.notifyClosed("Locker") end)
	openLocker = function()
		if PetReqState then pcall(function() PetReqState:FireServer() end) end -- refresh ownership from the server
		expanded = expanded or "Summer"   -- default: Summer card open (matches the reference)
		refreshLocker()
		toggleMainMenu("Locker", "LockerGui")
		lockerFit() -- no-op stub (panel uses the SHOP's static geometry)
		if _G.applyHudScaling then _G.applyHudScaling() end -- re-apply the SHOP's identical UIScale so this panel matches the Shop size exactly
		task.defer(function() print("[UIFix] Locker AbsoluteSize=" .. tostring(lockPanel.AbsoluteSize) .. " AbsolutePosition=" .. tostring(lockPanel.AbsolutePosition)) end) -- resolved on-screen size, to compare vs the SHOP
	end
	-- EXPOSED for the garden treasure box (SeasonalPetsChest.client.luau), which is now the only
	-- way in since Seasonal Pets left the MORE+ menu. It must be THIS function and not a bare
	-- LockerGui.Enabled = true: this one re-requests ownership from the server first, so a player
	-- who just earned a seasonal pet sees it instead of an out-of-date grid.
	-- Assignment to the existing _G table -- deliberately NOT a new local, since this file sits at
	-- ~187 of Luau's 200-local ceiling and one more would stop the whole script compiling.
	_G.openLocker = openLocker

	-- --- the MORE+ popup itself ---
	local moreGui = Instance.new("ScreenGui"); moreGui.Name = "MoreMenuGui"; moreGui.ResetOnSpawn = false
	-- DisplayOrder 9, not 8. The stale menu below also used 8, and at equal DisplayOrder the winner is
	-- whichever happened to be created last -- so the old design could render OVER the new one for the
	-- moment before the sweep reaches it. 9 makes this one win outright, sweep or no sweep.
	moreGui.DisplayOrder = 9; moreGui.Parent = PlayerGui
	-- ============================================================================================
	-- ONE MORE MENU, AND IT IS THIS ONE.
	-- ============================================================================================
	-- HUD_AllInOne.client.lua builds its OWN ScreenGui, also called "MoreMenuGui", also DisplayOrder 8,
	-- containing the OLD 196x206 pop-out: its own catcher, panel, header and button rows. It is not in
	-- default.project.json -- no *_AllInOne file is -- so it cannot be reaching the game through Rojo, and
	-- the only way it runs is as a copy baked into the place file. That is what is showing through behind
	-- the new cards: not leftovers inside this menu (this ScreenGui is built from scratch every run and
	-- contains nothing but the dashboard), but a whole second menu sitting underneath it.
	--
	-- Deleting the source file cannot fix that, because a baked-in instance is not the source file. So the
	-- live script evicts it instead:
	--   * NOW, for a copy that was built before this line ran;
	--   * ON ChildAdded, for one built after it (load order between two LocalScripts is not defined);
	--   * and on a few delayed passes, because a StarterGui copy is re-cloned into PlayerGui on respawn.
	-- The watcher stays connected for the session, so a rebuild at any point is caught too.
	--
	-- TARGETED BY NAME, and it never touches this ScreenGui. Sweeping PlayerGui broadly is what produced
	-- the black bar over the HUD -- other menus legitimately keep hidden frames parked, and a blanket
	-- "destroy anything invisible" pass eats them.
	do
		local function evictStaleMoreMenus()
			for _, g in ipairs(PlayerGui:GetChildren()) do
				if g ~= moreGui and g:IsA("ScreenGui") and g.Name == "MoreMenuGui" then
					print("[MOREMENU] evicted a stale duplicate MoreMenuGui (old pop-out design)")
					g:Destroy()
				end
			end
		end
		evictStaleMoreMenus()
		PlayerGui.ChildAdded:Connect(function(c)
			if c ~= moreGui and c:IsA("ScreenGui") and c.Name == "MoreMenuGui" then
				-- deferred: let the other script finish parenting before it is taken away, so it cannot
				-- error mid-build and leave half a menu behind
				task.defer(function()
					if c and c.Parent and c ~= moreGui then
						print("[MOREMENU] evicted a stale duplicate MoreMenuGui (added after ours)")
						c:Destroy()
					end
				end)
			end
		end)
		for _, d in ipairs({ 0.5, 2, 5, 10 }) do task.delay(d, evictStaleMoreMenus) end
	end
	local catcher = mkButton(moreGui, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 1, Visible = false }) -- tap-outside-to-close
	-- FULL-SIZE PANEL: 700x520 at (0.5,0,0.5,-45) -- the exact geometry the Shop, Pet Hub, Daily Tasks, Locker and
	-- Skin Crates all use, so every menu in the game opens to the same box in the same place. It used to be a
	-- 196x206 pop-out beside the MORE button, which showed ~3 of its 8 rows and buried the rest below the fold.
	local panel = mkFrame(moreGui, { Size = UDim2.new(0, 700, 0, 520), Position = UDim2.new(0.5, 0, 0.5, -45),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(225, 70, 170), Visible = false, ZIndex = 2, Active = true })
	mkCorner(panel, 20); mkStroke(panel, Color3.fromRGB(140, 20, 100), 3)
	-- 60px header bar in the darker pink, matching the other panels' header band.
	-- THE TEXT SWEEPS MUST NOT TOUCH THIS MENU. _G.applyHudScaling force-sets TextScaled = true AND Visible = true
	-- on every TextLabel/TextButton under PlayerGui, which is exactly what blew the Pet Hub's type up on top of
	-- itself. A dashboard is all precise type sizes -- a 21px title beside a 13px description -- so every one of
	-- them would be rescaled to fill its frame and the hierarchy would collapse. The NoTextSweep attribute is the
	-- sweep's own documented opt-out (see _G.hudTextSweepSkip); the mobile UIScale pass still applies as normal.
	moreGui:SetAttribute("NoTextSweep", true)
	-- 72px header band: title, subtitle, close. Squared off at the bottom because the 20px corner is only wanted
	-- where it meets the panel's own top corners -- without this the band's lower corners cut in and the pink
	-- shows through either side of the divider.
	local hdr = mkFrame(panel, { Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = Color3.fromRGB(170, 40, 125), ZIndex = 2 })
	mkCorner(hdr, 20)
	mkFrame(hdr, { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -22), BackgroundColor3 = Color3.fromRGB(170, 40, 125), BorderSizePixel = 0, ZIndex = 2 })
	-- The title used to carry a double-encoded U+2795 (the UTF-8 of the UTF-8), which rendered as garbage.
	-- Dropped rather than re-encoded -- the header reads better without a glyph in front of it.
	mkLabel(hdr, { Text = "MORE", Font = Enum.Font.FredokaOne, TextSize = 34, TextColor3 = Color3.fromRGB(255, 220, 0), Size = UDim2.new(0, 300, 0, 38), Position = UDim2.new(0, 20, 0, 8), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	mkLabel(hdr, { Text = "Everything else lives here", Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.fromRGB(255, 205, 238), Size = UDim2.new(0, 300, 0, 16), Position = UDim2.new(0, 22, 0, 46), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	local moreX = mkButton(hdr, { Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(1, -52, 0, 16), BackgroundColor3 = Color3.fromRGB(210, 60, 55), Text = "X", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
	mkCorner(moreX, 10); mkStroke(moreX, Color3.new(0, 0, 0), 2)
	-- Hairline divider separating the header from the cards.
	mkFrame(panel, { Size = UDim2.new(1, -40, 0, 2), Position = UDim2.new(0, 20, 0, 74), BackgroundColor3 = Color3.fromRGB(255, 190, 232), BackgroundTransparency = 0.62, BorderSizePixel = 0, ZIndex = 3 })

	-- Entry-list scroll: a real ScrollingFrame whose canvas Roblox auto-measures from the UIListLayout's children.
	-- The entry buttons are parented DIRECTLY into this ScrollingFrame (no intermediate Frame), so the layout +
	-- AutomaticCanvasSize can measure them and the list scrolls once the content is taller than the window.
	local entryScroll = Instance.new("ScrollingFrame")
	entryScroll.Name = "EntryList"
	entryScroll.BackgroundTransparency = 1 -- seamless: the panel's pink shows through, so the menu looks identical
	entryScroll.BorderSizePixel = 0
	entryScroll.Position = UDim2.new(0, 16, 0, 82) -- below the 72px header band + its divider
	entryScroll.Size = UDim2.new(1, -32, 1, -96)  -- 668 x 424, the exact area the cards below are sized to fill
	entryScroll.ScrollingEnabled = true
	entryScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	entryScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	entryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y          -- Roblox measures the canvas from the children
	entryScroll.ScrollBarThickness = 6                              -- match PetInventoryUI scroll
	entryScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 215, 0)  -- gold, same as PetInventoryUI
	entryScroll.ClipsDescendants = true
	entryScroll.ZIndex = 2
	entryScroll.Parent = panel
	-- DASHBOARD GEOMETRY. Positioned by hand rather than by a UIGridLayout, because the Season Pass card spans
	-- BOTH columns and a grid layout cannot make one cell double-width.
	--
	-- It is built to fill the 668x424 content box EXACTLY, so there is no dead space and no scrollbar:
	--   columns  327 + 14 gutter + 327 = 668
	--   rows     3 x 100 + 2 x 14 gutter = 328, then a 14 gutter, then the 82 full-width card = 424
	-- Cards are anchored from their CENTRE so the hover scale grows evenly on all four sides instead of
	-- shoving the card down and to the right. One table rather than eight locals: this file sits at 187 of
	-- Luau's 200-locals ceiling and every scope here is one bad edit from silently failing to compile.
	local MORE_UI = { CARD_W = 327, CARD_H = 100, GAP = 14, FULL_W = 668, FULL_H = 82, FULL_Y = 342 }

	-- CRATE (Daily Rewards) ready "!" dot infrastructure. The crate snapshot lives in CrateClient,
	-- which exposes _G.crateIsClaimable; we poll it to toggle a red dot on the ready row + MORE button.
	local crateReadyDots = {}
	local taskPendingDots = {} -- DAILY TASKS: its own dot group, so a done checklist can't clear the crate's dot
	-- `list` is which group the dot belongs to. Originally this only ever made crate dots; the daily-tasks row
	-- needs the same dot but toggled by a DIFFERENT condition, so the group is now a parameter rather than the
	-- function silently appending to one hardcoded table.
	local function mkCrateDot(parent, list)
		local dot = Instance.new("Frame")
		dot.Name = "CrateReadyDot"
		dot.Size = UDim2.fromOffset(18, 18)
		dot.AnchorPoint = Vector2.new(1, 0)
		dot.Position = UDim2.new(1, -2, 0, -2)
		dot.BackgroundColor3 = Color3.fromRGB(225, 50, 50)
		dot.ZIndex = 8
		dot.Visible = false
		dot.Parent = parent
		local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot
		local bang = Instance.new("TextLabel")
		bang.BackgroundTransparency = 1; bang.Size = UDim2.fromScale(1, 1)
		bang.Font = Enum.Font.GothamBlack; bang.Text = "!"; bang.TextSize = 13
		bang.TextColor3 = Color3.new(1, 1, 1); bang.ZIndex = 9; bang.Parent = dot
		local group = list or crateReadyDots
		group[#group + 1] = dot
		return dot
	end

	local MORE_ENTRIES = { -- ADD MORE HERE later (each: label + an image OR emoji icon + an action)
		{ label = "Rebirth", desc = "Reset your progress for permanent multipliers.", tint = Color3.fromRGB(90, 200, 255), order = 1,
		emoji = "\xF0\x9F\x94\x84", action = function() if _G.toggleRebirth then _G.toggleRebirth() end end }, -- MOVED here from the side button (the WORMHOLE button took its slot)
		-- ONE "Rewards" entry. Daily and Free were two rows for the same idea -- things you claim for free --
		-- and a player had to already know which menu held which. RewardsHub.client.luau is the single door;
		-- DAILY and FREE are sections inside it. Both dots ride on this row, so a "!" means "something is
		-- claimable" without having to say which side it is on.
		{ label = "Rewards", desc = "Daily login rewards and free playtime rewards.", tint = Color3.fromRGB(255, 175, 45), order = 2,
		emoji = "\xF0\x9F\x8E\x81", readyDot = true, tasksDot = true, action = function()
			if _G.toggleRewardsHub then
				_G.toggleRewardsHub()
			-- RewardsHub not loaded -> fall back to the daily panel directly. Not eligible yet (a brand-new
			-- player has no task list) -> the panel would refuse to open, so fire the crate instead. The
			-- daily reward is never unreachable either way.
			elseif _G.dailyTasksAvailable and _G.dailyTasksAvailable() then
				if _G.toggleDailyTasks then _G.toggleDailyTasks() end
			else
				local ev = RSx:FindFirstChild("OpenMeteorCrate")
				if not ev then ev = Instance.new("BindableEvent"); ev.Name = "OpenMeteorCrate"; ev.Parent = RSx end
				ev:Fire()
			end
		end },
		-- WORMHOLE moved here FROM the rail: the PETS button took its always-visible slot (players open the
		-- pet hub constantly; fast travel is a sometimes action). Same door, same panel -- only the entrance moved.
		{ label = "Wormhole", desc = "Fast travel to any island you've unlocked.", tint = Color3.fromRGB(140, 86, 226), order = 3,
		emoji = "\xF0\x9F\x8C\x80", action = function()
			if _G.toggleWormhole then _G.toggleWormhole()
			else
				local sig = ReplicatedStorage:FindFirstChild("OpenWormhole")
				if not sig then sig = Instance.new("BindableEvent"); sig.Name = "OpenWormhole"; sig.Parent = ReplicatedStorage end
				sig:Fire()
			end
		end },
		-- (PETS is a RAIL button now, not a menu row -- inviteSideFrame above, firing PetInvToggle.)
		-- (SEASONAL PETS removed from this menu. It is a limited-time GARDEN reward, and a menu row made it
		--  read as a settings entry -- so it moved to a treasure box beside the Global Garden. The panel it
		--  opens is unchanged (LockerGui, below); only the door moved. See SeasonalPetsChest.client.luau,
		--  which calls _G.openLocker -- exposed just after openLocker is defined.)
		-- (SEASON PASS removed from this menu entirely.)
		-- (SKIN CRATES removed from this menu: crates are the CRATES page of the pet hub now -- pets and
		--  crates are one combined interface behind the PETS rail button. SkinCrateClient still owns the
		--  panel; the hub's tab bar is the way in.)
		-- (FREE REWARDS merged INTO the "Rewards" row above -- it is the FREE section of RewardsHub now.
		--  SocialRewards.client still owns that panel; only the way in changed.)
		-- (the "Codes" entry lives in the Season Pass panel -- bottom-left CODES button.)
		-- (the "MLR Group" entry was removed from the HUD; non-members are now nudged by a periodic banner that
		--  opens the group window when tapped -- see RewardsClient)
	}
	-- Draw in the requested reading order, not the order the table happens to be written in. `order` overrides;
	-- anything without one keeps its table position, so adding an entry still Just Works.
	table.sort(MORE_ENTRIES, function(a, b) return (a.order or 99) < (b.order or 99) end)
	for i, e in ipairs(MORE_ENTRIES) do
		-- WHERE THIS CARD GOES. The full-width Season Pass sits on its own band under the 3x2 grid.
		local w = e.full and MORE_UI.FULL_W or MORE_UI.CARD_W
		local h = e.full and MORE_UI.FULL_H or MORE_UI.CARD_H
		local cx = e.full and (MORE_UI.FULL_W / 2)
			or (((i - 1) % 2) * (MORE_UI.CARD_W + MORE_UI.GAP) + MORE_UI.CARD_W / 2)
		local cy = (e.full and MORE_UI.FULL_Y
			or (math.floor((i - 1) / 2) * (MORE_UI.CARD_H + MORE_UI.GAP))) + h / 2
		-- NO SHADOW FRAME. There used to be one here: a sibling the same size as the card, offset 5px down,
		-- meant to read as a soft drop shadow. It had no UICorner, so its four SQUARE corners stuck out past
		-- the card's 16px rounded ones and rendered as little dark rectangular tabs behind every tile --
		-- reading as stray accents rather than as depth. The card's own dark stroke already separates it from
		-- the panel, so the shadow is gone rather than rounded; add mkCorner(shadow, 16) if depth is wanted
		-- back, but it MUST be rounded to the same radius as the card or the tabs come straight back.
		local row = mkButton(entryScroll, { Size = UDim2.new(0, w, 0, h), Position = UDim2.new(0, cx, 0, cy),
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(186, 44, 138),
			Text = "", AutoButtonColor = false, ClipsDescendants = true, ZIndex = 3, LayoutOrder = i })
		mkCorner(row, 16); mkStroke(row, Color3.fromRGB(140, 20, 100), 2)
		-- GLOSS: a fixed sheen over the top half. Always on -- this is what makes the tile read as a panel.
		do
			local gl = mkFrame(row, { Size = UDim2.new(1, 0, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 4 })
			mkCorner(gl, 16)
			local gg = Instance.new("UIGradient"); gg.Rotation = 90
			gg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.84), NumberSequenceKeypoint.new(1, 1) })
			gg.Parent = gl
		end
		-- SHINE: a narrow bright band that sweeps across on hover. Parked off the left edge until then.
		local shineG = Instance.new("UIGradient")
		do
			local sh = mkFrame(row, { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 5 })
			-- Rounded to the card's own radius. ClipsDescendants on the card clips to its RECTANGULAR bounds,
			-- not to its UICorner, so without this the shine's square corners flash white over the card's
			-- rounded ones every time the sweep runs -- the same square-corner artefact the shadow had.
			mkCorner(sh, 16)
			shineG.Rotation = 18
			shineG.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1),
				NumberSequenceKeypoint.new(0.5, 0.74), NumberSequenceKeypoint.new(0.58, 1),
				NumberSequenceKeypoint.new(1, 1) })
			shineG.Offset = Vector2.new(-1, 0); shineG.Parent = sh
		end
		-- ICON in its own coloured rounded square -- the one spot of per-feature colour on an otherwise
		-- uniform pink tile, which is what lets the eye find a row without reading any of the labels.
		do
			local sq = mkFrame(row, { Size = UDim2.new(0, 62, 0, 62), Position = UDim2.new(0, 16, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = e.tint or Color3.fromRGB(255, 175, 45), ZIndex = 6 })
			mkCorner(sq, 14); mkStroke(sq, Color3.fromRGB(140, 20, 100), 2)
			if e.image then
				local im = Instance.new("ImageLabel"); im.BackgroundTransparency = 1; im.Image = e.image; im.ScaleType = Enum.ScaleType.Fit
				im.Size = UDim2.new(1, -12, 1, -12); im.Position = UDim2.new(0, 6, 0, 6); im.ZIndex = 7; im.Parent = sq
			else
				mkLabel(sq, { Text = e.emoji or "", Font = Enum.Font.Gotham, TextSize = 32, Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
			end
		end
		-- TITLE + DESCRIPTION, both left-aligned to the same x so every card reads down one column.
		mkLabel(row, { Text = e.label, Font = Enum.Font.GothamBold, TextSize = 21, TextColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(0, w - 126, 0, 24), Position = UDim2.new(0, 92, 0, e.full and 14 or 18),
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6 })
		mkLabel(row, { Text = e.desc or "", Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.fromRGB(255, 205, 238),
			Size = UDim2.new(0, w - 126, 0, e.full and 24 or 36), Position = UDim2.new(0, 92, 0, e.full and 42 or 44),
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 6 })
		-- ARROW: this opens another menu rather than doing something on the spot.
		mkLabel(row, { Text = "\xE2\x9D\xAF", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = Color3.fromRGB(255, 190, 232),
			Size = UDim2.new(0, 24, 1, 0), Position = UDim2.new(0, w - 34, 0, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
		-- BADGES, inside the card's own bounds (it clips) and side by side rather than stacked -- the crate dot
		-- and the tasks dot are independent, and stacking them hid whichever drew second.
		if e.readyDot then mkCrateDot(row, crateReadyDots).Position = UDim2.new(1, -10, 0, 10) end
		if e.tasksDot then mkCrateDot(row, taskPendingDots).Position = UDim2.new(1, -32, 0, 10) end
		-- HOVER: lift the tile 3% and sweep the shine across it. UIScale (not a Size tween) so the card grows
		-- from its centre and every child scales with it -- icon square, type and arrow stay in proportion.
		do
			local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = row
			local qi = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			row.MouseEnter:Connect(function()
				TweenService:Create(sc, qi, { Scale = 1.03 }):Play()
				shineG.Offset = Vector2.new(-1, 0)
				TweenService:Create(shineG, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Offset = Vector2.new(1, 0) }):Play()
			end)
			row.MouseLeave:Connect(function() TweenService:Create(sc, qi, { Scale = 1 }):Play() end)
		end
		row.MouseButton1Click:Connect(function() playUIClick(); setMoreOpen(false); pcall(e.action) end)
	end
		mkCrateDot(stomachSideFrame, crateReadyDots) -- "!" dot on the MORE button itself
		-- Wiggle the WHOLE MORE+ button whenever the daily-rewards crate is claimable OR the daily tasks are
		-- unfinished (same ±8° rotation oscillation as the gut button). Driven by the poll below.
		local moreWiggling, moreWiggleTween = false, nil
		local function stopMoreWiggle()
			if not moreWiggling then return end
			moreWiggling = false
			if moreWiggleTween then pcall(function() moreWiggleTween:Cancel() end); moreWiggleTween = nil end
			stomachSideFrame.Rotation = 0
		end
		local function startMoreWiggle()
			if moreWiggling then return end
			moreWiggling = true
			stomachSideFrame.Rotation = -8
			local info = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
			moreWiggleTween = TweenService:Create(stomachSideFrame, info, { Rotation = 8 })
			moreWiggleTween:Play()
		end
		task.spawn(function() -- poll every 1s; toggles the row dots + MORE-button dot + wiggle
			while true do
				local ready   = (_G.crateIsClaimable and _G.crateIsClaimable()) == true
				local pending = (_G.dailyTasksPending and _G.dailyTasksPending()) == true
				-- Two INDEPENDENT dot groups: claiming the crate must not clear the daily-tasks dot, and
				-- finishing your tasks must not clear the crate's. They just happen to share one wiggle.
				for _, d in ipairs(crateReadyDots)   do d.Visible = ready   end
				for _, d in ipairs(taskPendingDots)  do d.Visible = pending end
				if ready or pending then startMoreWiggle() else stopMoreWiggle() end
				task.wait(1)
			end
		end)
	task.spawn(function() -- print AFTER the layout has measured (frameY vs contentY); scrolls when contentY > frameY
		task.wait(0.3)
		print(string.format("[MOREMENU] scroll: frameY=%d contentY=%d canvasY=%d entries=%d (scrolls if contentY>frameY)",
			math.floor(entryScroll.AbsoluteSize.Y), math.floor(entryScroll.AbsoluteCanvasSize.Y), math.floor(entryScroll.AbsoluteCanvasSize.Y), #MORE_ENTRIES))
	end)

	setMoreOpen = function(open)
		moreOpenState = open and true or false
		if moreOpenState then
			-- No repositioning any more: the panel is a centred 700x520 window like every other menu, so it opens
			-- in the same place regardless of where the rail button ended up on this device.
			panel.Visible = true; catcher.Visible = true
		else
			panel.Visible = false; catcher.Visible = false
		end
	end
	catcher.MouseButton1Click:Connect(function() setMoreOpen(false) end)
	moreX.MouseButton1Click:Connect(function() playUIClick(); setMoreOpen(false) end)
end
print("[MOREMENU SWAP] stomach -> main screen (pets old slot), pets -> more menu (stomach old slot).")

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
_G.gui.bottomStack = bottomStack -- shared so BOTH menu scripts (locker here + Pet Hub in PetFollow) can read its real top edge
task.spawn(function() -- log the bottom HUD's real top edge once it has laid out (so we can verify the menu fits above it)
	for _ = 1, 30 do
		task.wait(0.2)
		if bottomStack.AbsoluteSize.Y > 0 then print("[UIFix] bottomHUD topY=" .. tostring(math.floor(bottomStack.AbsolutePosition.Y))); break end
	end
end)
do
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Vertical; sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Center; sl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	sl.Padding = UDim.new(0, 8); sl.Parent = bottomStack
end

-- GAS METER box (LayoutOrder 2 = middle). Moderate FIXED width; UIScale handles screen scaling, so
-- it stays a moderate proportional width and never stretches full-width on wide screens.
sg=Instance.new("ScreenGui"); sg.Name="GasMeterGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
_G.gui.gasMeterPanel=mkFrame(bottomStack,{Size=UDim2.new(0,480,0,85),LayoutOrder=2,BackgroundColor3=Color3.fromRGB(45,120,220)}) -- solid BLUE container (restored). The green Fill's track (gasBg) now spans the full inner height, so no blue band shows above the green.
mkCorner(_G.gui.gasMeterPanel,16); local gmStroke0=mkStroke(_G.gui.gasMeterPanel,Color3.fromRGB(20,65,165),4); gmStroke0.Enabled=false -- dark-navy outline stays DISABLED (that was the earlier dark line)
task.delay(10, function() if _G.gui.gasMeterPanel then print("[HUDdone] gas container bgtrans now = "..tostring(_G.gui.gasMeterPanel.BackgroundTransparency)) end end) -- confirm the blue is back (expect 0) -- DARK NAVY container outline DISABLED (this stroke was the dark line across the gas meter). Kept (not destroyed) so the restyle reuses it instead of creating a new enabled one; restyle sets only its Color/Thickness, never Enabled.
do
	_G.gui.gasTitleLabel=mkLabel(_G.gui.gasMeterPanel,{Text="GAS METER",Font=Enum.Font.FredokaOne,TextSize=math.floor(17*scale),TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,0,0,math.floor(28*scale)),Position=UDim2.new(0,0,0,math.floor(6*scale)),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	mkStroke(_G.gui.gasTitleLabel,Color3.fromRGB(0,0,0),2)
	_G.gui.gasBg=mkFrame(_G.gui.gasMeterPanel,{Size=UDim2.new(1,-20,1,-(math.floor(34*scale)+8)),Position=UDim2.new(0,10,0,math.floor(34*scale)),BackgroundColor3=Color3.fromRGB(18,28,66),BackgroundTransparency=1}) -- track now FILLS the inner height: from just under the GAS METER label (y=34) down to ~8px above the bottom. The green Fill (child, height 1,0) fills this whole area -> no blue gap above/below it. Track bg stays transparent so the empty part of the bar shows the blue container.
	mkCorner(_G.gui.gasBg,17)
	_G.gui.gasFill=mkFrame(_G.gui.gasBg,{Name="Fill",Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.fromRGB(60,210,90),ZIndex=2})
	mkCorner(_G.gui.gasFill,17)
	_G.gui.gasGradient=Instance.new("UIGradient"); _G.gui.gasGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(130,240,120)),ColorSequenceKeypoint.new(1,Color3.fromRGB(45,190,70))}); _G.gui.gasGradient.Rotation=90; _G.gui.gasGradient.Parent=_G.gui.gasFill
	_G.gui.gasPowerText=mkLabel(_G.gui.gasBg,{Size=UDim2.new(1,0,1,0),Text="100%",Font=Enum.Font.FredokaOne,TextSize=math.floor(18*scale),TextColor3=Color3.fromRGB(255,255,255),ZIndex=3,TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(_G.gui.gasPowerText,Color3.fromRGB(0,0,0),2)
end

-- ===== GAS METER: tighten the layout so there's NO empty blue strip between the label and the green bar =====
-- KEEP THE BLUE (transparency stays 0). Computed from the label's real offset so it's exact regardless of scaling:
--  1) put the bar track (gasBg -> holds the green Fill child) right under the "GAS METER" label (2px gap),
--  2) give it a fixed bar height,
--  3) shrink the blue container's HEIGHT so it hugs: top pad + label + green bar + equal bottom pad -- nothing empty.
-- Only Position/Size change; the green Fill, label, and number stay visible and in order. Re-run after restyles settle.
local function tightenGasMeter()
	local panel, label, bg = _G.gui.gasMeterPanel, _G.gui.gasTitleLabel, _G.gui.gasBg
	if not (panel and label and bg) then return end
	local pad = label.Position.Y.Offset                 -- top padding above the label (reused as the bottom pad)
	local barTop = pad + label.Size.Y.Offset + 2        -- bar starts 2px under the label -> no gap
	local barH = 40
	bg.Position = UDim2.new(0, 10, 0, barTop)
	bg.Size = UDim2.new(1, -20, 0, barH)                -- green Fill (child, height 1,0) fills this whole bar
	panel.Size = UDim2.new(0, 480, 0, barTop + barH + pad) -- container hugs the content -> no empty blue strip
	print("[HUDdone3] container AbsoluteSize="..tostring(panel.AbsoluteSize).." greenBar AbsolutePosition="..tostring(bg.AbsolutePosition))
end
tightenGasMeter()
task.delay(2, tightenGasMeter); task.delay(6, tightenGasMeter); task.delay(11, tightenGasMeter) -- re-assert after restyles/scaling

-- ===== GAS METER: flatten the green Fill's gradient to solid bright green (its dark stop was the dark strip) =====
-- The Fill's UIGradient fades to a near-black stop, which reads as the dark band. Replace it with a flat bright
-- green (no dark fade). Runtime + delayed so it OVERRIDES the restyle passes that set a red/dark gradient at load.
local function flattenGasGradient()
	local fill = _G.gui and _G.gui.gasFill
	if not fill then return end
	local g = fill:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(Color3.fromRGB(60,210,90)) -- solid bright green, no dark fade
		g.Transparency = NumberSequence.new(0)
		print("[FLATGRAD] gas fill gradient flattened to solid green")
	end
end
flattenGasGradient()
task.delay(2, flattenGasGradient); task.delay(6, flattenGasGradient); task.delay(11, flattenGasGradient) -- override the load-time restyle gradient
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

-- ===== GAS METER: kill the dark band in the REAL gas meter -- the separate "GasMeterGui" ScreenGui =====
-- The visible gas meter is its OWN ScreenGui "GasMeterGui" (a pre-placed leftover, NOT the BottomStack one the
-- source builds) -- which is why every earlier source-side fix missed it. Its "GAS METER" TextLabel has a dark
-- background box + a black UIStroke that render as the dark band. We sweep EVERY "GasMeterGui" in PlayerGui
-- (there can be two with the same name) and: remove label background boxes, hide dark Frame backgrounds, and
-- DISABLE near-black UIStrokes. Only backgrounds/strokes change -> the green fill bar + text stay visible.
local function fixGasMeterGui()
	local pg = game.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	for _, gmg in ipairs(pg:GetChildren()) do
		if gmg:IsA("ScreenGui") and gmg.Name == "GasMeterGui" then
			local hits = 0
			for _, el in ipairs(gmg:GetDescendants()) do
				if el:IsA("TextLabel") or el:IsA("TextButton") then
					if el.BackgroundTransparency < 1 then el.BackgroundTransparency = 1; hits = hits + 1 end -- remove the label's background box (text stays)
				elseif el:IsA("Frame") or el:IsA("ImageLabel") then
					local c = el.BackgroundColor3
					if (c.R < 0.30 and c.G < 0.30 and c.B < 0.55) and el.BackgroundTransparency < 1 then
						el.BackgroundTransparency = 1; hits = hits + 1 -- dark track/box -> hidden (bright green Fill is kept)
					end
				elseif el:IsA("UIStroke") then
					local c = el.Color
					if (c.R < 0.30 and c.G < 0.30 and c.B < 0.60) and el.Enabled then
						el.Enabled = false; hits = hits + 1 -- the black outline (the dark band) -> off
					end
				end
			end
			print("[HUDfix] GasMeterGui cleaned -> "..hits.." dark element(s) hidden")
		end
	end
end
fixGasMeterGui()
task.delay(3, fixGasMeterGui); task.delay(7, fixGasMeterGui); task.delay(12, fixGasMeterGui) -- catch late StarterGui copy / restyle
PlayerGui.ChildAdded:Connect(function(ch) if ch.Name == "GasMeterGui" then task.wait(0.1); fixGasMeterGui() end end) -- re-fix if it's re-added
game.Players.LocalPlayer.CharacterAdded:Connect(function() task.wait(0.5); fixGasMeterGui(); task.delay(3, fixGasMeterGui) end) -- and after respawn

-- ===== GAS METER: remove ONLY the dark teal band the "GAS METER" text sits on (BottomStackGui) =====
-- Surgical: find the "GAS METER" TextLabel in BottomStackGui, clear its own background, and clear its PARENT
-- frame's background ONLY if that parent is a dark teal/green (NOT the blue container, NOT the green Fill).
-- Touches nothing else -- blue container, green Fill, pink gut pill, and all text/number are left exactly as-is.
local function killGasMeterBand()
	local pg = game.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local bsg = pg and pg:FindFirstChild("BottomStackGui")
	if not bsg then return end
	for _, el in ipairs(bsg:GetDescendants()) do
		if el:IsA("TextLabel") and string.find(string.upper(el.Text), "GAS METER", 1, true) then
			el.BackgroundTransparency = 1 -- (2) the label's own background, in case it has a fill
			local label = el
			local p = label.Parent
			if p and p:IsA("GuiObject") then
				local c = p.BackgroundColor3
				local isBlue  = (math.abs(c.R-0.078) < 0.06 and math.abs(c.G-0.549) < 0.10 and math.abs(c.B-1.0) < 0.06)
				local isGreen = (math.abs(c.R-0.235) < 0.10 and math.abs(c.G-0.823) < 0.10 and math.abs(c.B-0.353) < 0.10)
				local isDarkTeal = (c.R < 0.30 and c.G > 0.20 and c.G < 0.60 and c.B < 0.30)
				if isDarkTeal and not isBlue and not isGreen then
					p.BackgroundTransparency = 1 -- (3) the dark teal strip behind the label
				end
				print("[BAND] label parent="..p.Name.." parentColor="..tostring(p.BackgroundColor3).." parentTransNow="..tostring(p.BackgroundTransparency))
			end
		end
	end
end
killGasMeterBand()
task.delay(3, killGasMeterBand); task.delay(8, killGasMeterBand); task.delay(12, killGasMeterBand) -- re-run after restyles/scaling settle

-- NOTE: the old "kill the black bar over the gut/gas meter" sweep was REMOVED. The console dumps proved there
-- is NO foreign black element over the bottom HUD (the gas panel is blue, the gut pill is pink, the fart button
-- is grey). Worse, that sweep's "bar-shaped image" rule matched the full-screen LOADING SCREEN BACKGROUND image
-- (1968 wide) and hid it -- which is exactly why the loading picture went blank. If a real black bar ever shows
-- up, grab a screenshot + F9 output and target it by name instead of a broad heuristic sweep.

-- ===== [DARK] DIAGNOSTIC: scan the ENTIRE PlayerGui for dark-colored elements (print only, no fixes) =====
-- Runs after the HUD + restyles + scaling have settled. Lists every dark, non-transparent GuiObject and every
-- dark enabled UIStroke with full path + color + transparency + on-screen pos/size, so the gas-meter dark band
-- can be identified by its absPos (~465,470 area).
task.delay(8, function()
	for _, gui in ipairs(game.Players.LocalPlayer.PlayerGui:GetChildren()) do
		if gui:IsA("ScreenGui") then
			for _, el in ipairs(gui:GetDescendants()) do
				if el:IsA("GuiObject") then
					local c = el.BackgroundColor3
					if (c.R < 0.25 and c.G < 0.25 and c.B < 0.5) and el.BackgroundTransparency < 1 then
						print("[DARK] "..el:GetFullName().." "..el.ClassName.." color="..tostring(c).." trans="..tostring(el.BackgroundTransparency).." absPos="..tostring(el.AbsolutePosition).." absSize="..tostring(el.AbsoluteSize).." vis="..tostring(el.Visible))
					end
				elseif el:IsA("UIStroke") then
					local c = el.Color
					if (c.R < 0.25 and c.G < 0.25 and c.B < 0.6) and el.Enabled and el.Transparency < 1 then
						print("[DARK-STROKE] "..el:GetFullName().." color="..tostring(c).." thickness="..tostring(el.Thickness).." trans="..tostring(el.Transparency))
					end
				end
			end
		end
	end
end)

-- ===== [GMG] DIAGNOSTIC: dump GasMeterGui's FULL contents with NO color filter (print only) =====
-- So we can see the teal/green band's REAL color and whether it's a UIGradient on the green fill or a label/
-- frame background. Iterates EVERY ScreenGui named "GasMeterGui" (there can be two). Runs after HUD loads.
task.delay(8, function()
	for _, gmg in ipairs(game.Players.LocalPlayer.PlayerGui:GetChildren()) do
		if gmg:IsA("ScreenGui") and gmg.Name == "GasMeterGui" then
			print("[GMG] === ScreenGui GasMeterGui (Enabled="..tostring(gmg.Enabled)..", DisplayOrder="..tostring(gmg.DisplayOrder)..") ===")
			for _, el in ipairs(gmg:GetDescendants()) do
				if el:IsA("GuiObject") then
					print("[GMG] "..el.Name.." "..el.ClassName.." bgcolor="..tostring(el.BackgroundColor3).." bgtrans="..tostring(el.BackgroundTransparency).." absPos="..tostring(el.AbsolutePosition).." absSize="..tostring(el.AbsoluteSize).." vis="..tostring(el.Visible).." zindex="..tostring(el.ZIndex))
					local grad = el:FindFirstChildOfClass("UIGradient")
					if grad then print("   [GMG-grad] on "..el.Name.." rotation="..tostring(grad.Rotation).." colorseq="..tostring(grad.Color)) end
					local st = el:FindFirstChildOfClass("UIStroke")
					if st then print("   [GMG-stroke] on "..el.Name.." color="..tostring(st.Color).." enabled="..tostring(st.Enabled).." trans="..tostring(st.Transparency).." thickness="..tostring(st.Thickness)) end
				end
			end
		end
	end
end)

-- ===== [BSG] DIAGNOSTIC: dump BottomStackGui's FULL contents with NO color filter (print only) =====
-- The REAL on-screen gas meter is inside BottomStackGui.BottomStack (GasMeterGui is a disabled off-screen
-- decoy). Dump every element's real color so the teal/dark-green band Frame (~absPos Y 470, between the gut
-- pill and the green fill, bgtrans=0) can be identified. No fixes.
task.delay(8, function()
	local bsg = game.Players.LocalPlayer.PlayerGui:FindFirstChild("BottomStackGui")
	if not bsg then print("[BSG] BottomStackGui not found"); return end
	for _, el in ipairs(bsg:GetDescendants()) do
		if el:IsA("GuiObject") then
			print("[BSG] "..el.Name.." "..el.ClassName.." bgcolor="..tostring(el.BackgroundColor3).." bgtrans="..tostring(el.BackgroundTransparency).." absPos="..tostring(el.AbsolutePosition).." absSize="..tostring(el.AbsoluteSize).." zindex="..tostring(el.ZIndex).." vis="..tostring(el.Visible))
			local g = el:FindFirstChildOfClass("UIGradient"); if g then print("   [BSG-grad] on "..el.Name.." rotation="..tostring(g.Rotation).." "..tostring(g.Color)) end
			local st = el:FindFirstChildOfClass("UIStroke"); if st then print("   [BSG-stroke] on "..el.Name.." color="..tostring(st.Color).." enabled="..tostring(st.Enabled).." trans="..tostring(st.Transparency)) end
		end
	end
end)

-- ===== [FILM] DIAGNOSTIC: scan the WHOLE PlayerGui for any element overlapping the gas meter (a translucent film) =====
-- Looking for a dark element (color sum < ~1.0) with BackgroundTransparency between 0 and 1 and a high ZIndex
-- covering the ~454-wide meter strip -- i.e. a translucent black overlay sitting ON TOP of the gas meter. Print only.
task.delay(8, function()
	local meterYtop, meterYbot = 386, 464   -- gas meter strip vertical range (abs Y)
	local meterXl, meterXr = 172, 627        -- gas meter horizontal range (abs X)
	for _, el in ipairs(game.Players.LocalPlayer.PlayerGui:GetDescendants()) do
		if el:IsA("GuiObject") and el.Visible and el.BackgroundTransparency < 1 then
			local p, s = el.AbsolutePosition, el.AbsoluteSize
			if p.X < meterXr and (p.X+s.X) > meterXl and p.Y < meterYbot and (p.Y+s.Y) > meterYtop then
				local c = el.BackgroundColor3
				print("[FILM] "..el:GetFullName().." "..el.ClassName.." color="..tostring(c).." bright="..tostring(c.R+c.G+c.B).." bgtrans="..tostring(el.BackgroundTransparency).." zindex="..tostring(el.ZIndex).." size="..tostring(s).." absPos="..tostring(p))
			end
		end
	end
end)

-- ===== [OVL] DIAGNOSTIC: scan EVERYTHING over the GAS METER strip (incl. Image color/transparency) =====
-- A black overlay can be an ImageLabel/ImageButton (dark ImageColor3 / low ImageTransparency) rather than a
-- background -- the earlier scans only checked BackgroundTransparency, so they missed it. This lists EVERY
-- visible GuiObject overlapping the strip with its bg + image props + zindex. Print only.
task.delay(8, function()
	local x1,x2,y1,y2 = 172,627,386,470   -- the GAS METER strip region (abs)
	for _, el in ipairs(game.Players.LocalPlayer.PlayerGui:GetDescendants()) do
		if el:IsA("GuiObject") and el.Visible then
			local p,s = el.AbsolutePosition, el.AbsoluteSize
			if p.X < x2 and (p.X+s.X) > x1 and p.Y < y2 and (p.Y+s.Y) > y1 then
				local info = el.ClassName.." "..el:GetFullName()
				info = info.." bgcolor="..tostring(el.BackgroundColor3).." bgtrans="..tostring(el.BackgroundTransparency).." zindex="..tostring(el.ZIndex).." size="..tostring(s)
				if el:IsA("ImageLabel") or el:IsA("ImageButton") then
					info = info.." IMAGE id="..tostring(el.Image).." imgcolor="..tostring(el.ImageColor3).." imgtrans="..tostring(el.ImageTransparency)
				end
				print("[OVL] "..info)
			end
		end
	end
end)

-- ===== EFFECT FLASH =====
sg=Instance.new("ScreenGui"); sg.Name="FlashGui"; sg.ResetOnSpawn=false; sg.ZIndexBehavior=Enum.ZIndexBehavior.Global; sg.Parent=PlayerGui
_G.effectFlashFrame=mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ZIndex=10})


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

-- Global HUD scale. DESKTOP + TABLET keep the original 1280x720 (cap 1) behavior — untouched. Only PHONES
-- switch to the iPhone SE/8 LANDSCAPE reference (1100x590, matches Space Realm's ResponsiveUI) so the whole
-- HUD fits every phone instead of rendering at full authored size — that full-size render is why the buttons
-- land in the wrong place on high-res phones "on join". Also guards the boot 1x1 viewport (camera reports 1x1
-- for a frame or two at join → without the guard the scale collapses to ~0 and the HUD lands wrong until a resize).
local function getScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	if vp.X <= 1 or vp.Y <= 1 then
		return isMobile and 0.60 or 1 -- boot: viewport not valid yet; safe default until a recompute fixes it
	end
	if isMobile then
		-- EXACT Space Realm ResponsiveUI formula: iPhone SE/8 landscape reference (1100x590), clamped by
		-- device CLASS (viewport short-axis). PHONE-class (< 800) caps at 0.60 (clears the joystick, unchanged
		-- — the phone scaling that's already dialed in). TABLET/iPad (>= 800) caps at 2.5, so it scales UP from
		-- the reference (e.g. ~1.07 computed is kept) instead of being pinned at 1 — the iPad behavior copied
		-- from the handoff file.
		local deviceMax = (math.min(vp.X, vp.Y) >= 800) and 2.5 or 0.60
		return math.clamp(math.min(vp.X / 1100, vp.Y / 590), 0.55, deviceMax)
	end
	return math.min(vp.X / 1280, vp.Y / 720, 1) -- DESKTOP: unchanged (authored layout, capped at 1)
end

-- ===== PHONE: PER-CLUSTER EXTRA SHRINK =====
-- getScale() already shrinks the whole HUD to 0.60 on a phone, but three clusters were still eating the screen --
-- and they are the three that sit ON TOP of where you actually look. So they get an EXTRA multiplier on top of the
-- global scale, applied ONLY on mobile (desktop multiplies by nothing and is bit-for-bit unchanged).
--
-- Why a multiplier rather than smaller authored sizes: the authored sizes are shared with desktop, and every one of
-- these clusters is a stack of fixed-offset children (the bottom group is a UIListLayout of pill + meter + button).
-- Editing the numbers would need every child re-tuned and would drift from the desktop layout. One UIScale on the
-- cluster root shrinks the frames, the gaps, the paddings and the (TextScaled) text together, as one piece.
--
-- These are safe to shrink this hard because all three are anchored to a screen EDGE -- bottom-centre for the
-- bottom group, top-right for the coin pill and the stats panel -- and a UIScale scales about the element's own
-- AnchorPoint. So they shrink INTO their corner and stay pinned there; they cannot drift off-screen.
-- Deliberately on _G and NOT a `local`. CoreClient is very close to Luau's hard 200-locals-per-scope ceiling, and
-- going one over makes the ENTIRE script fail to compile -- silently, taking every handler in it with it. (That is
-- exactly how the Pet Hub's buttons died once.) A table on _G costs no register, so new tunables go here.
-- ===== TEXT-SWEEP OPT-OUT =====
-- Two passes below (applyScaling + repositionGUIs) blanket-force TextScaled=true -- and one of them Visible=true --
-- on EVERY TextLabel/TextButton under EVERY ScreenGui. That is fine for the panels that were authored to be
-- auto-fitted, and RUINOUS for any panel authored with explicit TextSizes: TextScaled ignores TextSize and blows
-- each label up to fill its whole frame, so a carefully sized 12pt caption becomes 40pt and lands on top of its
-- neighbours. That is the Pet Hub "REWARDS text goes huge and overlaps" bug -- the overlay is built with correct
-- TextSizes, and then a later sweep (a viewport change, a respawn, or another menu calling _G.applyHudScaling)
-- reaches in and overwrites them.
--
-- So the sweeps are now OPT-OUT. Set the NoTextSweep attribute on a ScreenGui (or any single element) and neither
-- pass will touch its text. On _G, not a local: CoreClient is at the edge of Luau's 200-locals ceiling.
_G.hudTextSweepSkip = function(v)
	local n = v
	while n and n ~= PlayerGui do
		if n:GetAttribute("NoTextSweep") then return true end
		n = n.Parent
	end
	return false
end

_G.MOBILE_SHRINK = {
	BottomStackGui = 0.72, -- gut pill + gas meter + BUY FOOD FIRST -> 0.60 * 0.72 = 0.43 of authored size
	CoinGui        = 0.78, -- coin counter, top-right
	RightPanelGui  = 0.78, -- STATS panel + impulse buttons, top-right
}

local function applyScaling()
	local s = getScale()
	for _, gui in ipairs(PlayerGui:GetChildren()) do
		-- LoadingScreen scales itself (separate ReplicatedFirst script); leave it alone.
		if gui:IsA("ScreenGui") and gui.Name ~= "LoadingScreen" then
			-- phone-only extra shrink for the three screen-hogging clusters; 1.0 (no change) for everything else
			local extra = (isMobile and _G.MOBILE_SHRINK[gui.Name]) or 1
			local s = s * extra
			-- (Safe-area / topbar insets are handled per-GUI by applyTopSafe below, using CoreUISafeInsets —
			-- see the TOP SAFE-AREA block — so nothing is set here; this pass is scaling only.)
			-- Scale each top-level cluster around ITS OWN anchor so it stays pinned to its screen
			-- edge/corner. (A ScreenGui-level UIScale scales from the top-left origin, so right/bottom-
			-- anchored clusters would drift off their edge as the scale shrinks.) A full-screen cover
			-- (Size ~ 1,1 scale — a dimmer / input catcher) is NOT scaled (it must keep covering the
			-- screen); instead we RECURSE into it so a menu PANEL nested underneath (e.g. the food/premium
			-- shop, whose panel lives inside a full-screen Frame) still gets scaled on phones. Once we hit a
			-- non-full-screen element we scale it and stop (its UIScale carries all its descendants).
			local function scaleNode(child)
				if not child:IsA("GuiObject") then return end
				if child.Size.X.Scale >= 1 and child.Size.Y.Scale >= 1 then
					for _, gc in ipairs(child:GetChildren()) do scaleNode(gc) end -- recurse into the cover
				else
					local us = child:FindFirstChildWhichIsA("UIScale")
					if not us then us = Instance.new("UIScale"); us.Parent = child end
					us.Scale = s
				end
			end
			for _, child in ipairs(gui:GetChildren()) do scaleNode(child) end
			for _, v in ipairs(gui:GetDescendants()) do
				if (v:IsA("TextLabel") or v:IsA("TextButton")) and not _G.hudTextSweepSkip(v) then
					v.TextScaled = true
				end
			end
		end
	end
end
-- Expose the SHOP's exact scaling pass so the Pet Hub + Seasonal Pets menus (built in other scripts, sometimes
-- AFTER this ran) can re-apply the identical UIScale on open -> their AbsoluteSize then matches the Shop's.
_G.applyHudScaling = applyScaling

-- ===== HUD STAYS VISIBLE WHILE A SHOP / MENU POPUP IS OPEN =====
-- The HUD is intentionally LEFT VISIBLE while a popup (food shop / stomach shop / premium shop /
-- daily rewards) is open. Each shop's own full-screen invisible overlay (Active=true) catches input,
-- so the HUD can't be clicked through while shopping — but it remains on screen. The previous code
-- here disabled BottomStackGui / SidebarGui / CoinGui / RightPanelGui / StomachGui on popup-open and
-- re-enabled them on close; that hide/re-enable behavior has been removed.
-- _G.refreshHud is left undefined; its one remaining caller (repositionGUIs) guards with `if _G.refreshHud`.

local function repositionGUIs()
	-- coin display
	coinGui.Enabled = true; coinPill.Visible = true
	coinPill.Size = UDim2.new(0,200,0,52); coinPill.Position = UDim2.new(1,-10,0,10); coinPill.AnchorPoint = Vector2.new(1,0)
	-- right panel (unified stats + impulse buttons)
	-- right panel (stats + impulse buttons). Anchor (1,0) top-right, so its UIScale shrinks it toward that
	-- corner. Desktop/tablet keep the authored spot; on phone-class it tucks up under the coin pill.
	--
	-- That Y is now DERIVED from the coin pill's live rendered height rather than hard-coded (it used to be a
	-- flat y48, "a first-pass estimate"). The coin pill and the stats panel now shrink by DIFFERENT amounts, so
	-- any fixed number is wrong the moment either multiplier is touched -- the gap would silently open up or the
	-- two would overlap. Measuring it keeps them locked together whatever the scales become.
	do
		local vpR = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
		local phoneClassR = isMobile and math.min(vpR.X, vpR.Y) < 800
		rightPanel.Size = UDim2.new(0,230,0,500); rightPanel.AnchorPoint = Vector2.new(1,0)
		if phoneClassR then
			local coinScale = getScale() * (_G.MOBILE_SHRINK.CoinGui or 1)
			local coinBottom = 10 + math.floor(52 * coinScale + 0.5) -- pill's authored y-offset + its scaled height
			rightPanel.Position = UDim2.new(1, -8, 0, coinBottom + 8)
		else
			rightPanel.Position = UDim2.new(1, -5, 0, 85)
		end
	end
	-- LEFT RAIL: 4 stacked 95x95 buttons (SHOP / STOMACH / WORMHOLE / MORE). These are 4 SEPARATE fixed-offset
	-- frames (NOT one UIListLayout), so applyScaling's per-frame UIScale sizes each button but leaves the GAPS
	-- fixed — which spreads them out when scaled DOWN (phone) and OVERLAPS them when scaled UP (iPad, now that
	-- tablets can exceed 1). So on ALL mobile we recompute the stack pitch from the live scale:
	--   PHONE-class: tight padding 6 (pitch 101*s) + rail raised 30px to y66 (clears the joystick).
	--   TABLET/iPad: default padding 12 (pitch 107*s), authored top y96 — the reference's tablet treatment.
	-- DESKTOP keeps the exact authored grid (y96/203/310/417, 107px pitch) — unchanged. (At scale 1 the tablet
	-- formula equals the authored grid, so they stay continuous.)
	do
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		local phoneClass = isMobile and math.min(vp.X, vp.Y) < 800
		local frames = { shopSideFrame, inviteSideFrame, dailySideFrame, stomachSideFrame }
		if isMobile then
			local s = getScale()
			local pitch = math.floor((phoneClass and 101 or 107) * s + 0.5) -- (button + padding) * live scale
			local topY = phoneClass and 66 or 96 -- phone raises 30px to clear the joystick; tablet keeps y96
			for i, f in ipairs(frames) do
				f.Size = UDim2.new(0,95,0,95); f.AnchorPoint = Vector2.new(0,0)
				f.Position = UDim2.new(0, 12, 0, topY + pitch * (i - 1))
			end
		else
			local ys = { 96, 203, 310, 417 } -- DESKTOP: authored grid (107px pitch), unchanged
			for i, f in ipairs(frames) do
				f.Size = UDim2.new(0,95,0,95); f.AnchorPoint = Vector2.new(0,0)
				f.Position = UDim2.new(0, 12, 0, ys[i])
			end
		end
	end
	-- All text visible and scaled -- EXCEPT anything under a NoTextSweep element (see the opt-out above).
	-- The Visible=true here is the nastier half of this pass: it force-SHOWS every label, including ones a menu
	-- deliberately hid (a collapsed tab, a locked row, an empty state). Combined with TextScaled that is exactly
	-- how the Pet Hub ended up with giant overlapping text on top of each other.
	--
	-- ===== IT MUST NOT FORCE-SHOW OVERLAYS =====
	-- A menu's sub-sheets -- Rebirth's PETS overlay, the Season Pass "how it works" card, every "are you sure"
	-- confirm -- are TextButtons authored Visible = false and sized fromScale(1, 1) so they cover their panel.
	-- This loop switched all of them on, and a 700x520 rectangle at 20-25% opacity then hung over the middle of
	-- the screen dimming everything, with nothing on screen to dismiss it. The tell was that the identical sheet
	-- built as a Frame in the same panel stayed hidden -- the sweep only reaches text classes.
	--
	-- Filling the parent is the structural line between the two: a caption is never sized (1,1) scale over its
	-- container, and a backdrop/dim/overlay always is. Those keep whatever Visible their owner set.
	--
	-- Skipping the force can only ever leave something hidden that its owner had already hidden -- it never hides
	-- anything -- so this cannot break a label that was showing correctly.
	for _, v in ipairs(PlayerGui:GetDescendants()) do
		if (v:IsA("TextLabel") or v:IsA("TextButton")) and not _G.hudTextSweepSkip(v) then
			v.TextScaled = true
			if not (v.Size.X.Scale >= 1 and v.Size.Y.Scale >= 1) then v.Visible = true end
		end
	end
	-- Tiny Gut pill + gas meter + fart button are ONE centered group (BottomStack + UIListLayout);
	-- their size/position/centering is owned by that layout + the per-cluster UIScale below — nothing to set here.
	applyScaling()
	if _G.refreshHud then _G.refreshHud() end -- no-op now (popup-based HUD hiding removed); guarded so it's safe if undefined
end

workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(repositionGUIs)
repositionGUIs()
player.CharacterAdded:Connect(function()
	task.wait(0.1)
	repositionGUIs()
end)
task.delay(3, repositionGUIs)

-- ===== TOP SAFE-AREA: keep these panels clear of the device notch (and, where needed, the Roblox topbar) =====
-- ScreenInsets maps a ScreenGui's coordinate space into a safe rect and Roblox auto-recomputes it on
-- rotation / safe-area changes. TWO modes, because the choice depends on how the GUI was already inset:
--   "device" = DeviceSafeInsets  → notch / home-bar ONLY. Used for GUIs that were IgnoreGuiInset=true
--              (full-screen coords): on desktop this is a NO-OP (no notch), so they stay put — this is what
--              fixes the "coin + stats got pushed down" regression. On phones it still clears the notch.
--   "core"   = CoreUISafeInsets  → topbar + notch. Used for GUIs that already respected the topbar
--              (IgnoreGuiInset=false): adding this doesn't move them on desktop, it just adds notch clearance.
-- NOTE: we do NOT flip IgnoreGuiInset anymore (that was forcing the topbar inset on the coin/stats).
local TOP_SAFE_GUIS = {
	CoinGui = "device",        -- coin pill (was IgnoreGuiInset=true → notch only, no desktop shift)
	RightPanelGui = "device",  -- STATS panel + impulse buttons (was IgnoreGuiInset=true → notch only)
	SidebarGui = "device",     -- left rail: notch only. CoreUISafeInsets added the topbar inset and pushed the rail too low — this puts it back up.
	StomachShopGui = "core",   -- STOMACH SHOP
	FoodShopGui = "core",      -- SHOP
	PremiumShopGui = "core",   -- SHOP (premium tab)
	MoreMenuGui = "core",      -- MORE+ menu (its buttons are children, so they shift with it)
	GardenerChatGui = "core",  -- Global Community Gardener interact panel
}
local function applyTopSafe(sg)
	local mode = sg:IsA("ScreenGui") and TOP_SAFE_GUIS[sg.Name]
	if not mode then return end
	pcall(function()
		sg.ScreenInsets = (mode == "core") and Enum.ScreenInsets.CoreUISafeInsets or Enum.ScreenInsets.DeviceSafeInsets
	end)
end
for _, sg in ipairs(PlayerGui:GetChildren()) do applyTopSafe(sg) end
-- Catch any of these built later (shops/gardener panel are built after this runs). Defer so the builder
-- finishes its own IgnoreGuiInset/setup first, then we assert the safe-area inset last.
PlayerGui.ChildAdded:Connect(function(sg) task.defer(applyTopSafe, sg) end)

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
		local stomachPanel=Instance.new("Frame"); stomachPanel.Name="Panel"; stomachPanel.Size=UDim2.new(0,700,0,520) -- matches the FOOD SHOP panel size (700x520) -- Name="Panel" so GutSkinClient can inject the Skins tab
		stomachPanel.Position=UDim2.new(0.5,0,0.5,-45); stomachPanel.AnchorPoint=Vector2.new(0.5,0.5) -- nudged UP 45px to match the food shop's on-screen position
		stomachPanel.BackgroundColor3=Color3.fromRGB(78,46,34); stomachPanel.BorderSizePixel=0; stomachPanel.Active=true; stomachPanel.Parent=stomachShopGui -- WARM THEME (brown panel); Active=true so panel clicks don't leak to the HUD behind it
		mkCorner(stomachPanel,24); mkStroke(stomachPanel,Color3.fromRGB(198,100,40),2) -- rounder + thinner inner outline
		do local g=Instance.new("UIGradient"); g.Rotation=90; g.Color=ColorSequence.new(Color3.fromRGB(98,60,44),Color3.fromRGB(64,36,26)); g.Parent=stomachPanel end -- subtle warm brown gradient
		-- (drop shadow behind the panel REMOVED -- the stomach shop no longer casts the soft shadow behind its UI)
		do
			local bg=Instance.new("Frame"); bg.Size=UDim2.new(1,0,1,0); bg.BackgroundColor3=Color3.new(0,0,0)
			bg.BackgroundTransparency=1; bg.Active=false; bg.BorderSizePixel=0; bg.ZIndex=0; bg.Parent=stomachShopGui -- invisible + Active=FALSE so clicks OUTSIDE the panel fall through to the HUD MENU BUTTONS (direct click-to-switch)
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
			local sc=mkButton(stomachPanel,{Size=UDim2.new(0,40,0,40),Position=UDim2.new(1,-48,0,8),BackgroundColor3=Color3.fromRGB(230,96,82),Text="X",Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0})
			mkCorner(sc,8); mkStroke(sc,Color3.fromRGB(150,50,40),2)
			sc.MouseButton1Click:Connect(function() playUIClick(); stomachShopGui.Enabled=false; _G.MainMenuManager.notifyClosed("Stomach") end)
		end
		currentStomachLabel=mkLabel(stomachPanel,{Size=UDim2.new(1,-20,0,35),Position=UDim2.new(0,10,0,62),BackgroundColor3=Color3.fromRGB(56,32,24),BackgroundTransparency=0,Text="Current: Tiny Gut (100 max power)",Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(247,234,214),BorderSizePixel=0})
		currentStomachLabel.Name="CurrentLabel" -- GutSkinClient repositions this when it injects the Skins tab
		mkCorner(currentStomachLabel,10); mkStroke(currentStomachLabel,Color3.fromRGB(255,208,96),2)
		scrollFrame=Instance.new("ScrollingFrame"); scrollFrame.Name="TierList"; scrollFrame.Size=UDim2.new(1,-20,1,-110) -- Name="TierList" so the Skins tab can show/hide it
		scrollFrame.Position=UDim2.new(0,10,0,105); scrollFrame.BackgroundTransparency=1
		scrollFrame.ScrollBarThickness=6; scrollFrame.CanvasSize=UDim2.new(0,0,0,0)
		scrollFrame.AutomaticCanvasSize=Enum.AutomaticSize.Y; scrollFrame.BorderSizePixel=0; scrollFrame.Parent=stomachPanel
		do
			local ll=Instance.new("UIListLayout"); ll.Padding=UDim.new(0,12); ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Parent=scrollFrame
			local lp=Instance.new("UIPadding"); lp.PaddingLeft=UDim.new(0,10); lp.PaddingRight=UDim.new(0,10); lp.PaddingTop=UDim.new(0,4); lp.PaddingBottom=UDim.new(0,8); lp.Parent=scrollFrame
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

	-- ===== GUT-UPGRADE-AFFORDABLE WIGGLE =====
	-- Wiggle the bottom-HUD gut icon whenever the player can AFFORD the next (un-owned) coin gut tier:
	-- a continuous subtle rotation oscillation (-8deg <-> +8deg). Starts when coins >= next gut cost and
	-- that tier isn't already owned; stops when they can't afford it. Re-checked on coin changes + on
	-- gut purchase (StomachMax change). Purely visual; touches no gameplay.
	-- the WHOLE LEFT "Stomach" side button wiggles (rotating the button rotates its icon + label + bg)
	local gutSideIcon = dailySideFrame
	local gutWiggling = false
	local gutWiggleTween = nil
	local function stopGutWiggle()
		if not gutWiggling then return end
		gutWiggling = false
		if gutWiggleTween then pcall(function() gutWiggleTween:Cancel() end); gutWiggleTween = nil end
		if gutSideIcon then gutSideIcon.Rotation = 0 end
	end
	local function startGutWiggle()
		if not gutSideIcon then warn("[wiggle] Stomach side button not found — cannot wiggle"); return end
		if gutWiggling then return end
		print("[wiggle] startGutWiggle -> wiggling " .. gutSideIcon:GetFullName())
		gutWiggling = true
		gutSideIcon.Rotation = -8
		local info = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true) -- loop + reverse
		gutWiggleTween = TweenService:Create(gutSideIcon, info, { Rotation = 8 })
		gutWiggleTween:Play()
	end
	-- the next UN-OWNED coin gut tier = lowest maxPower above the current StomachMax (Robux/free excluded)
	local function nextCoinGutTier(curMax)
		local best = nil
		for _, t in ipairs(tierDefs) do
			if (not t.robux) and t.cost > 0 and t.maxPower > curMax then
				if (not best) or t.maxPower < best.maxPower then best = t end
			end
		end
		return best
	end
	local function checkGutAfford()
		local ls = player:FindFirstChild("leaderstats")
		if not ls then stopGutWiggle(); _G.gutUpgradeAffordable = false; return end
		local sm = ls:FindFirstChild("StomachMax"); local c = ls:FindFirstChild("Coins")
		if not (sm and c) then stopGutWiggle(); _G.gutUpgradeAffordable = false; return end
		local nextTier = nextCoinGutTier(sm.Value)                       -- nil once every coin tier is owned
		local affordable = (nextTier ~= nil) and (c.Value >= nextTier.cost)
		if affordable then startGutWiggle() else stopGutWiggle() end
		_G.gutUpgradeAffordable = affordable  -- read by the periodic banner scheduler
	end
	_G.forceGutWiggle = startGutWiggle  -- exposed for the /wiggle dev command (force the wiggle on)
	_G.checkGutAfford = checkGutAfford  -- exposed so other handlers can re-check
	-- Re-check on coin changes AND on gut purchase (StomachMax change), plus one pass once stats exist.
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats", 30); if not ls then return end
		local coins = ls:WaitForChild("Coins", 30)
		local smv = ls:WaitForChild("StomachMax", 30)
		if coins then coins:GetPropertyChangedSignal("Value"):Connect(checkGutAfford) end
		if smv then smv:GetPropertyChangedSignal("Value"):Connect(checkGutAfford) end
		checkGutAfford()
	end)

	for i,tier in ipairs(tierDefs) do
		do
			local card=Instance.new("Frame"); card.Size=UDim2.new(1,0,0,70); card.BorderSizePixel=0
				-- VISUAL list position ONLY (tier data/icon/price unchanged): Infinite Gut pinned at the TOP,
				-- then the others keep their existing ascending order (Tiny->Iron) just below it.
				card.LayoutOrder = (tier.name == "Infinite Gut") and 1 or (i + 1)
			card.BackgroundColor3=Color3.fromRGB(20,90,200); card.Parent=scrollFrame
			mkCorner(card,14); mkStroke(card,Color3.fromRGB(120,170,235),1.5) -- cleaner, thinner border
				do local cg=Instance.new("UIGradient"); cg.Rotation=90; cg.Color=ColorSequence.new(Color3.fromRGB(38,112,224),Color3.fromRGB(16,74,168)); cg.Parent=card end -- soft vertical gradient
				do local hlz=Instance.new("Frame"); hlz.BackgroundColor3=Color3.new(1,1,1); hlz.BackgroundTransparency=0.82; hlz.BorderSizePixel=0; hlz.Position=UDim2.new(0,8,0,4); hlz.Size=UDim2.new(1,-16,0,10); hlz.ZIndex=(card.ZIndex or 1); hlz.Parent=card; local hc=Instance.new("UICorner",hlz); hc.CornerRadius=UDim.new(0,6); local hg=Instance.new("UIGradient",hlz); hg.Rotation=90; hg.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.4),NumberSequenceKeypoint.new(1,1)}) end -- subtle top highlight
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
				checkGutAfford() -- gut just changed (purchase) -> re-evaluate the affordability wiggle
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

-- [REMOVE BEFORE LAUNCH] /wiggle DEV COMMAND: force the gut-icon affordability wiggle on, for testing.
-- NOTE: with the modern TextChatService, Player.Chatted does NOT fire on the CLIENT — so we hook
-- TextChatService.SendingMessage (fires client-side when the local player sends a message). We keep
-- Player.Chatted too for the legacy chat system. Either path routes to the same handler.
local function onDevChat(text)
	local cmd = string.lower((string.gsub(text or "", "^%s*(.-)%s*$", "%1")))
	if cmd == "/wiggle" then
		print("[wiggle] /wiggle received (forceGutWiggle ready=" .. tostring(_G.forceGutWiggle ~= nil) .. ", showHudBanner ready=" .. tostring(_G.showHudBanner ~= nil) .. ")")
		if _G.forceGutWiggle then _G.forceGutWiggle() end -- wiggle the gut button
		if _G.showHudBanner then _G.showHudBanner("Stomach Upgrade Available!", Color3.fromRGB(60, 180, 90), 4) end -- + its banner (for testing)
	elseif cmd == "/banner" then -- [REMOVE BEFORE LAUNCH] force-show the crate notice banner for testing
		print("[banner] /banner received (showHudBanner ready=" .. tostring(_G.showHudBanner ~= nil) .. ")")
		if _G.showHudBanner then _G.showHudBanner("Daily Reward Ready!  Tap MORE+", Color3.fromRGB(255, 196, 60), 4) end
	end
end
pcall(function()
	game:GetService("TextChatService").SendingMessage:Connect(function(m) onDevChat(m.Text) end)
end)
pcall(function() player.Chatted:Connect(onDevChat) end)

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
	_G.gasFill01=fill -- 0..1 gas charge, read by the belly puff (BellyPuff.client)
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

-- Bird hit (NEW behavior for the aggressive event birds): NO kill, NO knockdown -- just DRAIN 20% of the
-- player's CURRENT gas (floored), with a 1s cooldown so multiple birds can't drain you to nothing in
-- one pass. Returns true if it applied, false if it was on cooldown (so the caller can skip feedback).
local BIRD_HALVE_COOLDOWN = 1 -- seconds of invulnerability between bird hits
local BIRD_GAS_DRAIN_PCT = 0.2 -- fraction of CURRENT gas removed per bird hit (was 0.5 / halve); 50% -> 20%
_G.lastBirdHalveTime = -math.huge
_G.applyBirdHalve = function()
	local now = os.clock()
	if now - (_G.lastBirdHalveTime or -math.huge) < BIRD_HALVE_COOLDOWN then
		print("[BIRD] hit ignored (within "..BIRD_HALVE_COOLDOWN.."s cooldown)")
		return false
	end
	_G.lastBirdHalveTime = now
	local before = gasMeter
	gasMeter = math.floor(gasMeter * (1 - BIRD_GAS_DRAIN_PCT))                     -- remove 20% of CURRENT gas, floored (was /2 = 50%)
	currentPower = (stomachMax > 0) and (gasMeter / maxGasMeter) * stomachMax or 0 -- keep power in sync with the reduced gas
	if _G.updateMeter then _G.updateMeter() end
	print(string.format("[BIRD] hit -> gas drained 20%%: before=%.1f after=%.1f (no kill, no knockdown)", before, gasMeter))
	return true
end
print("[BIRD] attack drain changed 50% -> 20% of fart power.")

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

-- Rainbow-beam hit (called from the beam system's client listener): knock the player down.
-- 1) GAS IS LEFT AS-IS -- the meter keeps whatever value it has at the instant of the hit (it is NO
--    LONGER restored to the launch/pre-takeoff amount), and
-- 2) knock them back through the air to the island they LAUNCHED from, releasing control there.
-- It NEVER touches food/gut/earn/coins. (The knockdown physics below are unchanged; only the old
-- gas-restore step was removed.)
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

	-- ---- GAS: LEAVE IT AS-IS (changed) ----
	-- A rainbow hit no longer RESTORES the meter to the launch (pre-takeoff) amount. The gas meter is
	-- left at whatever value it has at the instant of the hit -- only the knockdown below runs. stopFlying
	-- above does NOT touch the meter, so removing the restore leaves the current drained value intact.
	print(string.format("BEAM HIT: knockdown only -> gas LEFT AS-IS at %.1f", gasMeter))

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


-- Ring bonuses, gas boosts, bird hits, "Not Enough Coins" -- all of it lands here, and the ring one
-- fires on EVERY ring collected. Each call used to build its own ScreenGui at the identical pixel
-- (0.5, 0.5) with no queue and no token, so grabbing three rings in two seconds drew three labels
-- straight through each other. Now: ONE ScreenGui, and concurrent floats claim distinct vertical
-- SLOTS so they read as a stack. Past 3 in flight we drop rather than pile on -- unreadable either way.
-- The band was also moved off 0.35, which is exactly where the rocket-launch countdown sits.
-- (`slots` is an upvalue: the do-block frees its REGISTER but the closure keeps the value -- see the
-- register-budget note at the top of the file.)
local showFloatingText
do
	local FLOAT_SLOTS = 3
	local slots = {}
	local floatGui = Instance.new("ScreenGui")
	floatGui.Name = "FloatingTextGui"
	floatGui.ResetOnSpawn = false
	floatGui.IgnoreGuiInset = true
	floatGui.DisplayOrder = 92
	floatGui.Parent = PlayerGui

	function showFloatingText(text, col)
		local slot
		for i = 1, FLOAT_SLOTS do if not slots[i] then slot = i; break end end
		if not slot then return end
		slots[slot] = true

		local startY = 0.60 - (slot - 1) * 0.05 -- 0.60 / 0.55 / 0.50, drifting up 0.10 -> band 0.40..0.60
		local lbl = Instance.new("TextLabel")
		lbl.Text = text; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 22
		lbl.TextColor3 = col or Color3.fromRGB(255,220,0); lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(0,300,0,50); lbl.Position = UDim2.new(0.5,-150,startY,0)
		lbl.ZIndex = 10; lbl.Parent = floatGui
		Instance.new("UIStroke").Parent = lbl
		TweenService:Create(lbl, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5,-150,startY - 0.10,0), TextTransparency = 1 }):Play()
		task.delay(1.5, function() lbl:Destroy(); slots[slot] = nil end)
	end
end
_G.showFloatingText=showFloatingText

-- StomachFull notification (FIX 7)
task.spawn(function()
	local StomachFullEvent=RS:WaitForChild("StomachFullEvent",30)
	if StomachFullEvent then
		local GATE_PET_NAMES = { BroccoliPet="Broccoli Bunny", CoconutCrab="Coconut Crab", PopcornSheep="Popcorn Sheep", ButterDuck="Butter Duck", BurritoArmadillo="Burrito Armadillo" }
		StomachFullEvent.OnClientEvent:Connect(function(reason, foodName, needPet)
			if reason == "not_enough_coins" then
				-- Coin shortfall: show the correct message; do NOT open the stomach shop.
				showFloatingText("\xe2\x9a\xa0 Not Enough Coins", Color3.fromRGB(255,100,100))
			elseif reason == "pet_quest_locked" then
				-- Food stand locked: this island's pet quest isn't done yet. Styled HERO notice (matches the game),
				-- with a plain floating-text fallback. Never opens a shop.
				local petName = GATE_PET_NAMES[needPet] or "pet"
				local msg = "Finish the " .. petName .. " quest to unlock this food stand!"
				if _G.NotifyCenter and _G.NotifyCenter.push then
					_G.NotifyCenter.push({ top = "\xF0\x9F\x94\x92 Food Stand Locked", text = msg, color = Color3.fromRGB(255,190,60), priority = _G.NotifyCenter.PRIORITY and _G.NotifyCenter.PRIORITY.PURCHASE or nil, duration = 3.5 })
				else
					showFloatingText("\xF0\x9F\x94\x92 " .. msg, Color3.fromRGB(255,190,60))
				end
			elseif reason == "food_locked" then
				-- ISLAND LOCK: this food belongs to an island the player has not climbed to yet. The third arg
				-- is the ISLAND NUMBER for this reason (the same slot carries a pet id for pet_quest_locked).
				-- Needs its own branch rather than falling through: the generic branch below pops the GUT shop
				-- open, which is the wrong advice entirely -- a bigger stomach does not unlock this food.
				local isl = tonumber(needPet) or 0
				local msg = isl > 0
					and ("Reach Island " .. isl .. " to unlock " .. tostring(foodName) .. "!")
					or  "You have not reached this food's island yet!"
				if _G.NotifyCenter and _G.NotifyCenter.push then
					_G.NotifyCenter.push({ top = "\xF0\x9F\x94\x92 Food Locked", text = msg, color = Color3.fromRGB(255,190,60), priority = _G.NotifyCenter.PRIORITY and _G.NotifyCenter.PRIORITY.PURCHASE or nil, duration = 3.5 })
				else
					showFloatingText("\xF0\x9F\x94\x92 " .. msg, Color3.fromRGB(255,190,60))
				end
			elseif reason == "not_enough_room" then
				-- HAS room but this food is too big to fit -> distinct message; nudge to a bigger gut.
				showFloatingText("\xe2\x9a\xa0 Not Enough Room!", Color3.fromRGB(255,100,100))
				local g = PlayerGui:FindFirstChild("StomachShopGui")
				if g then _G.MainMenuManager.notifyOpened("Stomach"); g.Enabled = true end
			else
				-- "stomach_full" (or nil, for backward compatibility): full gut -> nudge to a bigger gut.
				showFloatingText("\xe2\x9a\xa0 Stomach Full! Buy a bigger gut!", Color3.fromRGB(255,100,100))
				local g = PlayerGui:FindFirstChild("StomachShopGui")
				if g then _G.MainMenuManager.notifyOpened("Stomach"); g.Enabled = true end
			end
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

-- Landing a NEW island is the biggest moment in the game, so it goes to NotifyCenter's HERO lane at
-- the top priority: it PREEMPTS anything lesser already on screen (a reward nag, a purchase) rather
-- than being drawn underneath it. (The old arrivalFrame sat at UDim2.new(0.5,0,0,10) -- the same pixel
-- as announceFrame/noticeFrame/PurchaseBanner, with nothing arbitrating between them.)
local function showArrival(islandNum)
	if arrivedIslands[islandNum] then return end
	arrivedIslands[islandNum]=true
	local NC = _G.NotifyCenter
	if not NC then return end
	NC.push({
		top      = "\xF0\x9F\x8F\x9d\xef\xb8\x8f You reached",
		text     = (ISLAND_DISPLAY_NAMES[islandNum] or ("Island "..islandNum)).."!",
		color    = islandColors[islandNum] or Color3.fromRGB(100,200,100),
		priority = NC.PRIORITY.ISLAND,
		duration = 3.5,
		sound    = playIslandSound,
	})
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

-- "<player> reached <island>!" is OTHER people's news. It used to take the prime top-centre slot for
-- 3.3s a time -- in a busy server, back to back -- burying the player's own arrival banner, which sat
-- at the identical pixel. It now goes to NotifyCenter's SOCIAL lane (small pills, top-left, up to 3
-- stacked), where it can fire as often as it likes without ever competing with the player's own moments.
local function queueAnnouncement(msg)
	local NC = _G.NotifyCenter
	if not NC then return end
	NC.push({ text = msg, lane = "social", priority = NC.PRIORITY.SOCIAL })
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

	-- FART BUBBLES (gas pockets): runs EVERY frame, OUTSIDE the isFlying block, so a bubble pops
	-- whether the player is RISING or FALLING through it. Touching one (within 20 studs) POPS it
	-- (expand+fade + particle burst + pop sound via _G.popGasPocket) AND grants a +15 gas boost.
	-- It re-spawns after 45s so the pickup stays available.
	for i = #_G.activeGasPockets, 1, -1 do
		local p = _G.activeGasPockets[i]
		if p and p.Parent then
			if (hrp.Position - p.Position).Magnitude < 20 then
				local ppos = p.Position
				table.remove(_G.activeGasPockets, i)
				if _G.popGasPocket then _G.popGasPocket(p) end   -- VISUAL pop
				-- GAS BUBBLE BOOST. The meter is 0-100 and currentPower = (gasMeter / maxGasMeter) * stomachMax,
				-- so at the base Tiny Gut (100 max power) 1 meter point IS 1 fart power -- this grants exactly
				-- +2 fart power there, and stays 2% of the tank on bigger guts so a bubble does not become
				-- worthless the moment you upgrade. For a flat +2 power at EVERY tier instead, this would have to
				-- be (2 / stomachMax) * 100 -- which pays 0.06 of a meter point on an Iron Gut, i.e. nothing.
				-- Fires whether the player is RISING or FALLING (this loop runs OUTSIDE the isFlying block).
				local BUBBLE_GAS_BOOST = 2
				local gasBefore = gasMeter
				gasMeter = math.min(maxGasMeter, gasMeter + BUBBLE_GAS_BOOST)
				updateMeter()
				print(string.format("[BUBBLE] popped - gas before=%.1f, +%d, gas after=%.1f", gasBefore, BUBBLE_GAS_BOOST, gasMeter))
				showFloatingText("+\xF0\x9F\x92\xA8 GAS BOOST!", Color3.fromRGB(0, 255, 100))
				task.delay(45, function() if _G.spawnGasPocket then _G.spawnGasPocket(ppos) end end)
			end
		else table.remove(_G.activeGasPockets, i) end
	end

	-- RINGS: runs EVERY frame, OUTSIDE the isFlying block, so a ring collects whether the player is
	-- RISING or FALLING through it. The reward (coin bonus + streak multiplier) fires either direction,
	-- same as the bubble's gas boost. Re-spawns after 30s so the pickup stays available.
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

	if isFlying and gasMeter > 0 then
		-- Button held + gas left -> thrust straight up.
		if not infiniteGut then
			gasMeter = math.max(0, gasMeter - DRAIN_RATE * dt) -- normal drain; SKIPPED for Infinite Gut owners (never drains)
		end
		local scaledPower = (gasMeter / maxGasMeter) * stomachMax -- power scaled by remaining gas
		currentPower = scaledPower
		local speed = getFlightSpeed(scaledPower) * (_G.serverEventSpeedMult or 1) * (_G.rebirthSpeedMult or 1) -- rebirth: a little faster each time
		if twoXBoostActive then speed = speed * 2 end
		-- WATERING CAN WEIGHT. A full can is heavy -- carrying it drags your climb down. The server sets this
		-- attribute when the Gardener hands one over and clears it the moment the can is used or lost, so this
		-- can't get stuck on. Applied AFTER the 2x boost so the penalty scales with your real climb speed.
		if player:GetAttribute("CarryingWateringCan") then speed = speed * CAN_WEIGHT_MULT end

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
		-- LIGHT thunderstorm wind: a soft varying buffet set by EventClient (_G.thunderWindVec); zero outside the
		-- storm, so normal flight is unchanged. Much gentler than the windstorm shove above.
		local tw = _G.thunderWindVec
		if tw then wpx = wpx + tw.X; wpz = wpz + tw.Z end
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

		-- (ring collection moved OUTSIDE this block — see the RINGS loop above; rings now collect
		-- whether rising or falling, same as the gas-pocket bubbles.)

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
				-- Farts stat row removed from the stats display (TotalFartPower itself is untouched)
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
-- The banner itself now goes through NotifyCenter's HERO lane (priority PURCHASE) instead of
-- building its own ScreenGui at UDim2.new(0.5,0,0,10) -- which is the exact spot the arrival,
-- announce and reward banners also used, so a purchase could land on top of "ISLAND UNLOCKED!".
-- The confetti + sound stay: they're a full-screen celebration layered OVER whatever the hero
-- lane is showing, so they cost no screen real estate and can't collide with anything.
-- Still an IIFE, not a do-block -- see the register-budget note at the top of the file.
;(function()
local function celebrate()
	local fx = Instance.new("ScreenGui")
	fx.Name = "PurchaseConfetti"
	fx.ResetOnSpawn = false
	fx.IgnoreGuiInset = true
	fx.DisplayOrder = 96 -- just above the hero banner it celebrates
	fx.Parent = PlayerGui

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://112825313814792"
	sound.Volume = 0.8
	sound.Parent = workspace
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 5)

	task.spawn(function()
		for _ = 1, 30 do
			task.wait(0.05)
			local confetti = Instance.new("Frame")
			confetti.Size = UDim2.new(0, math.random(8,14), 0, math.random(8,14))
			confetti.Position = UDim2.new(math.random(20,80)/100, 0, 0, math.random(-10,0))
			confetti.BackgroundColor3 = Color3.fromHSV(math.random(0,100)/100, 1, 1)
			confetti.BorderSizePixel = 0
			confetti.Rotation = math.random(0,360)
			confetti.Parent = fx
			local uic = Instance.new("UICorner"); uic.CornerRadius = UDim.new(0,2); uic.Parent = confetti
			TweenService:Create(confetti, TweenInfo.new(2), {
				Position = UDim2.new(confetti.Position.X.Scale, 0, 1, 50),
				Rotation = math.random(360),
				BackgroundTransparency = 1
			}):Play()
			game:GetService("Debris"):AddItem(confetti, 2.1)
		end
		task.wait(2.2)
		fx:Destroy()
	end)
end

local PAE = RS:WaitForChild("PurchaseAnnouncementEvent", 10)
if PAE then
	PAE.OnClientEvent:Connect(function(playerName, itemName, isGamepass)
		local NC = _G.NotifyCenter
		if not NC then return end
		NC.push({
			top      = isGamepass and "â­ GAMEPASS" or "ð PURCHASE",
			text     = tostring(playerName) .. " bought " .. tostring(itemName) .. "!",
			color    = Color3.fromRGB(255, 200, 0),
			priority = NC.PRIORITY.PURCHASE,
			duration = 4,
			sound    = celebrate,
		})
	end)
end
end)()

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

	-- PETS BUTTON  (variable kept as inviteSideFrame; was WORMHOLE, which moved into MORE+)
	inviteSideFrame.BackgroundColor3 = Color3.fromRGB(80,170,70) -- pets green, matching the paw button
	local inC = inviteSideFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	inC.CornerRadius = UDim.new(0,16); inC.Parent = inviteSideFrame
	local inS = inviteSideFrame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	inS.Color = Color3.fromRGB(40,110,40); inS.Thickness = 3; inS.Parent = inviteSideFrame

	-- PETS BUTTON  (variable kept as dailySideFrame; repurposed paw button)
	dailySideFrame.BackgroundColor3 = Color3.fromRGB(80,170,70)
	local daC = dailySideFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	daC.CornerRadius = UDim.new(0,16); daC.Parent = dailySideFrame
	local daS = dailySideFrame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	daS.Color = Color3.fromRGB(40,110,40); daS.Thickness = 3; daS.Parent = dailySideFrame

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
	inviteSideFrame.BackgroundColor3 = Color3.fromRGB(80,170,70) -- PETS button (Wormhole moved into MORE+)
	dailySideFrame.BackgroundColor3 = Color3.fromRGB(80,170,70)
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

-- ===== PET WHEEL REMOVAL SWEEP =====
-- The wheel's source files are deleted, but Rojo only adds -- the LocalScript and the PetWheelGui already
-- saved into this place keep running and keep showing a spin panel that no longer belongs to anything. Kill
-- the GUI, kill the script, and clear the _G hook so any stale caller that still reaches for it does nothing
-- rather than opening a half-dead panel.
do
	_G.togglePetWheel = nil
	local function sweepWheel()
		for _, inst in ipairs(player:GetDescendants()) do
			local n = inst.Name
			if n == "PetWheelGui" or n == "PetWheelReveal" or (n == "PetWheel" and inst:IsA("LocalScript")) then
				pcall(function()
					if inst:IsA("BaseScript") then inst.Disabled = true end
					inst:Destroy()
				end)
			end
		end
	end
	sweepWheel()
	task.delay(2, sweepWheel); task.delay(8, sweepWheel)
	-- and catch a wheel GUI rebuilt later by a stale script that survived the pass above
	player.ChildAdded:Connect(function(c)
		if c.Name == "PlayerGui" then task.delay(1, sweepWheel) end
	end)
end

-- ===== BOTTOM-HUD AUTHORITY: ONE script decides whether BottomStackGui is on =====
-- BottomStackGui holds the gut pill, the gas meter and the BUY FOOD FIRST / TAP TO FART button, and roughly a
-- dozen scripts used to switch it off and switch it back on again by their own bookkeeping. That works right up
-- until two of them disagree, or until one of them never gets to run its restore -- and then the player is left
-- with no gut pill, no gas meter and no buy button, with nothing on screen that can bring them back.
--
-- That is exactly what the marshmallow stick hit. Campfire.client hid the HUD on pick-up and restored it on
-- drop, but STALE DUPLICATE copies of that script are baked into the place (MenuBackdropGuard lists Campfire
-- among 20 duplicated LocalScripts). The duplicates run their own older hide/restore, so the fixed copy's
-- restore was being overwritten by a copy that cannot be edited from here. Patching Campfire again could not
-- win that race.
--
-- So the decision moves HERE instead, into the one script with no duplicate, and it is RE-ASSERTED on a timer
-- rather than written once on an edge. A stale script can still write Enabled=false; it just gets corrected a
-- quarter-second later. Whoever writes last no longer decides -- this does.
--
-- The HUD is off only while something real wants it off:
--   * a main menu is open (MainMenuManager.current), EXCEPT the food stand, which deliberately keeps the HUD
--     up because you need the gut pill + BUY FOOD button to actually use the stand (see standHudPin);
--   * a script has claimed a hold via _G.hudHold(tag, true) -- currently the meteor crate reveal;
--   * you are genuinely roasting: holding the stick AND standing at a fire. Both, not either. Holding alone
--     meant walking away with the stick still equipped left the HUD gone with no way to get it back.
-- Anything else and the bottom buttons come back, whoever turned them off and for whatever reason.
do
	_G.hudHolds = _G.hudHolds or {}
	function _G.hudHold(tag, on)          -- claim/release a named reason to keep the bottom HUD hidden
		if not tag then return end
		_G.hudHolds[tag] = on and true or nil
	end

	local function anyHold()
		for _ in pairs(_G.hudHolds) do return true end
		return false
	end

	-- The garden cinematic hides every ScreenGui and re-hides anything that turns itself back on, so asserting
	-- against it would just be churn. It restores the HUD itself when it ends; stand down while it's on screen.
	local function introRunning()
		for _, g in ipairs(PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g.Name:sub(1, 11) == "GardenIntro" then return true end
		end
		return false
	end

	local function roasting()
		local char = player.Character
		if not (char and char:FindFirstChild("Marshmallow Stick")) then return false end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then return false end
		for _, m in ipairs(workspace:GetChildren()) do   -- the server parents every built fire to Workspace as 'Campfire'
			if m.Name == "Campfire" and m:IsA("Model") then
				local pivot = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
				if pivot and (pivot.Position - root.Position).Magnitude <= 45 then return true end
			end
		end
		return false
	end

	task.spawn(function()
		while true do
			task.wait(0.25)
			pcall(function()
				if not hudRevealed or introRunning() then return end -- pre-spawn + cinematic own the screen
				local g = PlayerGui:FindFirstChild("BottomStackGui")
				if not (g and g:IsA("ScreenGui")) then return end
				local mm = _G.MainMenuManager
				local menuOpen = mm ~= nil and mm.current ~= nil and mm.current ~= "FoodShop"
				local want = not (menuOpen or anyHold() or roasting())
				if g.Enabled ~= want then g.Enabled = want end
			end)
		end
	end)
	print("[HUD] bottom-stack authority armed -- re-asserts BottomStackGui 4x/sec (beats stale duplicate scripts)")
end

print("DONE")
print("FIXED")
