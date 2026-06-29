--======================================================================
-- HUDClone.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of every always-on-screen HUD component from the main
-- game, ready to drop into a NEW world. Build order + exact sizes/positions/
-- colors/text are copied verbatim from CoreClient/SettingsMenu so it looks
-- identical. Components included:
--
--   1. CoinGui      -- top-right coin pill (icon + amount + "+" button)
--   2. SettingsGui  -- gear button (tucks left of the coins) + Music/SFX panel
--   3. RightPanelGui-- STATS panel on the RIGHT (Island/Max Height/Space Realm
--                      progress) + MID-AIR / 2X POWER / BIRD NUKE buttons
--   4. SidebarGui   -- LEFT-side buttons: SHOP / INVITE / Stomach / MORE
--
-- "Working" wiring is preserved but GUARDED: anything that needs the rest of
-- the game (shop menus, server remotes, leaderstats, player attributes) is
-- wrapped so it silently no-ops if those don't exist yet in the new world, and
-- starts working automatically the moment they're added. Drop this one script
-- into StarterPlayer > StarterPlayerScripts (or sync via Rojo) and it runs.
--======================================================================

local Players            = game:GetService("Players")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService      = game:GetService("SocialService")
local SoundService       = game:GetService("SoundService")
local Workspace          = game:GetService("Workspace")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local scale    = isMobile and 0.7 or 1.0

-- ===== GUI HELPERS (copied from CoreClient) =====
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

-- ===== SHARED IMAGE ASSETS (from CoreClient) =====
_G.COIN_IMAGE = _G.COIN_IMAGE or "rbxassetid://106760789458573" -- gold coin icon
_G.GUT_IMAGE  = _G.GUT_IMAGE  or "rbxassetid://108585083746103" -- stomach/gut icon

-- ===== UI CLICK SOUND (self-contained) =====
local uiClickSound = Instance.new("Sound")
uiClickSound.Name = "UIClickSound_HUDClone"
uiClickSound.SoundId = "rbxassetid://101638558691673"
uiClickSound.Volume = 0.5
uiClickSound.Parent = PlayerGui
local function playUIClick()
	local s = uiClickSound:Clone()
	s.Parent = PlayerGui
	s:Play()
	game:GetService("Debris"):AddItem(s, 3)
end
_G.playUIClick = _G.playUIClick or playUIClick

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY (ported verbatim from CoreClient) =====
-- A tiny shared manager (ONE instance across all client scripts, via _G) so only ONE main menu
-- (premium shop / stomach shop) is open at a time. Opening any registered menu first CLOSES whichever
-- other is open. Guarded so whichever client script loads first creates it and the rest reuse it.
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end          -- each menu provides a full-hide fn
	function mgr.setHud(visible)                                                -- hide/show the WHOLE bottom HUD if this world has one
		local lp = game:GetService("Players").LocalPlayer
		local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
		local g = pg and pg:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end                                       -- no-op if this world has no bottom HUD yet
	end
	function mgr.notifyOpened(name)                                             -- call right BEFORE showing a menu
		if mgr.current and mgr.current ~= name then
			local h = mgr.hiders[mgr.current]; if h then pcall(h) end           -- fully close the other open menu
		end
		mgr.current = name
		mgr.setHud(false)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
-- toggle an Enabled-driven menu through the manager (open => first close any other; close => clear current)
local function toggleMainMenu(name, guiName)
	local g = PlayerGui:FindFirstChild(guiName); if not g then return end       -- menu not present in this world yet
	if g.Enabled then
		g.Enabled = false; _G.MainMenuManager.notifyClosed(name)
	else
		_G.MainMenuManager.notifyOpened(name)                                   -- direct switch: closes any other open main menu first
		g.Enabled = true
	end
end
_G.MainMenuManager.register("Premium", function() local g=PlayerGui:FindFirstChild("PremiumShopGui"); if g then g.Enabled=false end end)
_G.MainMenuManager.register("Stomach", function() local g=PlayerGui:FindFirstChild("StomachShopGui"); if g then g.Enabled=false end end)

-- forward-declared so the MORE+ side button (built below) can toggle the popup that's built later in this script
local setMoreOpen
local moreOpenState = false

--======================================================================
-- 1) TOP-RIGHT: COIN DISPLAY  (CoinGui)
--======================================================================
local coinGui = Instance.new("ScreenGui")
coinGui.Name = "CoinGui"; coinGui.ResetOnSpawn = false; coinGui.IgnoreGuiInset = true; coinGui.Parent = PlayerGui

local coinPill = mkFrame(coinGui,{Position=UDim2.new(1,-10,0,10),Size=UDim2.new(0,180*scale,0,46*scale),BackgroundColor3=Color3.fromRGB(220,160,0),AnchorPoint=Vector2.new(1,0),ClipsDescendants=false,ZIndex=4})
mkCorner(coinPill,25); mkStroke(coinPill,Color3.fromRGB(180,120,0),3)
local coinGrad=Instance.new("UIGradient")
coinGrad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,190,20)),ColorSequenceKeypoint.new(1,Color3.fromRGB(200,140,0))})
coinGrad.Rotation=90; coinGrad.Parent=coinPill

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
	playUIClick()
	toggleMainMenu("Premium", "PremiumShopGui")
end)

-- Live coin number: mirror leaderstats.Coins if it exists (so it "just works" when
-- a coin leaderstat is present in the new world). No-ops gracefully otherwise.
task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 30)
	local coins = ls and ls:FindFirstChild("Coins")
	if not coins then return end
	local function refresh() coinAmountLabel.Text = tostring(coins.Value) end
	refresh()
	coins:GetPropertyChangedSignal("Value"):Connect(refresh)
end)

--======================================================================
-- 2) SETTINGS: gear button (tucks left of coins) + Music/SFX panel  (SettingsGui)
--    Fully self-contained -- works standalone with no other game systems.
--======================================================================
local musicOn = true
local sfxOn   = true
_G.musicEnabled = true

-- SFX routing group: every NON-music sound plays through this so one toggle mutes all SFX.
local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = "GameSFX_HUDClone"
sfxGroup.Volume = 1
sfxGroup.Parent = SoundService
local function routeSound(snd)
	if typeof(snd) ~= "Instance" or not snd:IsA("Sound") then return end
	if snd.SoundGroup == nil then pcall(function() snd.SoundGroup = sfxGroup end) end
end
for _, d in ipairs(Workspace:GetDescendants())    do routeSound(d) end
for _, d in ipairs(SoundService:GetDescendants()) do routeSound(d) end
Workspace.DescendantAdded:Connect(routeSound)
SoundService.DescendantAdded:Connect(routeSound)
local function applySFX()   sfxGroup.Volume = sfxOn and 1 or 0 end
local function applyMusic() _G.musicEnabled = musicOn; if _G.refreshMusicVolume then pcall(_G.refreshMusicVolume) end end

local settingsGui = Instance.new("ScreenGui")
settingsGui.Name = "SettingsGui"; settingsGui.ResetOnSpawn = false; settingsGui.IgnoreGuiInset = true; settingsGui.DisplayOrder = 60; settingsGui.Parent = PlayerGui

local gearBtn = Instance.new("TextButton")
gearBtn.Name = "SettingsGearBtn"
gearBtn.AnchorPoint = Vector2.new(1, 0)
gearBtn.Size = UDim2.new(0, 46, 0, 46)
gearBtn.Position = UDim2.new(1, -198, 0, 10)
gearBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
gearBtn.Text = "\xE2\x9A\x99\xEF\xB8\x8F"  -- gear icon
gearBtn.TextScaled = true
gearBtn.Font = Enum.Font.GothamBold
gearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
gearBtn.ZIndex = 20
gearBtn.Parent = settingsGui
do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,10); c.Parent=gearBtn end
do local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(0,0,0); s.Thickness=2; s.Parent=gearBtn end
do local p=Instance.new("UIPadding"); p.PaddingTop=UDim.new(0,6); p.PaddingBottom=UDim.new(0,6); p.PaddingLeft=UDim.new(0,6); p.PaddingRight=UDim.new(0,6); p.Parent=gearBtn end

local settingsPanel = Instance.new("Frame")
settingsPanel.Name = "SettingsPanel"
settingsPanel.Size = UDim2.new(0, 260, 0, 150)
settingsPanel.AnchorPoint = Vector2.new(1, 0)
settingsPanel.Position = UDim2.new(1, -10, 0, 64)
settingsPanel.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
settingsPanel.BorderSizePixel = 0
settingsPanel.Visible = false
settingsPanel.ZIndex = 20
settingsPanel.Parent = settingsGui
do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,12); c.Parent=settingsPanel end
do local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(255,255,255); s.Thickness=2; s.Parent=settingsPanel end

local sTitle = Instance.new("TextLabel")
sTitle.Size = UDim2.new(1, -54, 0, 34); sTitle.Position = UDim2.new(0, 12, 0, 6); sTitle.BackgroundTransparency = 1
sTitle.Text = "Settings"; sTitle.Font = Enum.Font.GothamBold; sTitle.TextSize = 20; sTitle.TextColor3 = Color3.fromRGB(255,255,255)
sTitle.TextXAlignment = Enum.TextXAlignment.Left; sTitle.ZIndex = 21; sTitle.Parent = settingsPanel

local sCloseBtn = Instance.new("TextButton")
sCloseBtn.Size = UDim2.new(0, 30, 0, 30); sCloseBtn.Position = UDim2.new(1, -38, 0, 8); sCloseBtn.AnchorPoint = Vector2.new(0, 0)
sCloseBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60); sCloseBtn.Text = "X"; sCloseBtn.Font = Enum.Font.GothamBold
sCloseBtn.TextScaled = true; sCloseBtn.TextColor3 = Color3.fromRGB(255,255,255); sCloseBtn.ZIndex = 21; sCloseBtn.Parent = settingsPanel
do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=sCloseBtn end

local function makeToggleRow(yOff, labelText, getOn, setOn)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -24, 0, 40); row.Position = UDim2.new(0, 12, 0, yOff); row.BackgroundTransparency = 1
	row.ZIndex = 21; row.Parent = settingsPanel
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -90, 1, 0); lbl.Position = UDim2.new(0, 0, 0, 0); lbl.BackgroundTransparency = 1
	lbl.Text = labelText; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 16; lbl.TextColor3 = Color3.fromRGB(235,235,245)
	lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 21; lbl.Parent = row
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 76, 0, 30); btn.Position = UDim2.new(1, -76, 0.5, 0); btn.AnchorPoint = Vector2.new(0, 0.5)
	btn.Font = Enum.Font.GothamBold; btn.TextSize = 15; btn.TextColor3 = Color3.fromRGB(255,255,255); btn.ZIndex = 21; btn.Parent = row
	do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=btn end
	local function refresh()
		local on = getOn()
		btn.Text = on and "ON" or "OFF"
		btn.BackgroundColor3 = on and Color3.fromRGB(50, 190, 70) or Color3.fromRGB(120, 120, 130)
	end
	btn.MouseButton1Click:Connect(function() setOn(not getOn()); refresh() end)
	refresh()
end
makeToggleRow(46,  "Music",         function() return musicOn end, function(v) musicOn = v; applyMusic() end)
makeToggleRow(96,  "Sound Effects", function() return sfxOn   end, function(v) sfxOn   = v; applySFX()   end)

gearBtn.MouseButton1Click:Connect(function() playUIClick(); settingsPanel.Visible = not settingsPanel.Visible end)
sCloseBtn.MouseButton1Click:Connect(function() playUIClick(); settingsPanel.Visible = false end)
applySFX(); applyMusic()

-- Tuck the gear immediately to the LEFT of the coin pill, same row, on every device.
task.spawn(function()
	local GAP = 8
	local function place()
		local cSize = coinPill.AbsoluteSize
		if cSize.X <= 0 or cSize.Y <= 0 then return end
		local cLeft = coinPill.AbsolutePosition.X
		local gearW = cSize.Y
		local coinPosY    = coinPill.Position.Y
		local coinAnchorY = coinPill.AnchorPoint.Y
		gearBtn.AnchorPoint = Vector2.new(0, coinAnchorY)
		gearBtn.Size = UDim2.fromOffset(gearW, cSize.Y)
		gearBtn.Position = UDim2.new(0, cLeft - GAP - gearW, coinPosY.Scale, coinPosY.Offset)
		settingsPanel.AnchorPoint = Vector2.new(0, coinAnchorY)
		settingsPanel.Position = UDim2.new(0, (cLeft + cSize.X) - settingsPanel.Size.X.Offset, coinPosY.Scale, coinPosY.Offset + cSize.Y + 6)
	end
	place()
	coinPill:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
	coinPill:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	coinPill:GetPropertyChangedSignal("Position"):Connect(place)
	coinPill:GetPropertyChangedSignal("AnchorPoint"):Connect(place)
end)

--======================================================================
-- 3) RIGHT PANEL: STATS + IMPULSE BUTTONS  (RightPanelGui)
--======================================================================
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

-- Space Realm progress bar
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
	spaceFill.BackgroundColor3 = (hi >= SPACE_TOTAL_ISLANDS) and Color3.fromRGB(170,110,255) or Color3.fromRGB(90,200,120)
	spacePctLabel.Text = "Island " .. hi .. "/" .. SPACE_TOTAL_ISLANDS .. "  -  " .. math.floor(frac * 100 + 0.5) .. "%"
end
updateSpaceRealmProgress()
player:GetAttributeChangedSignal("HighestIsland"):Connect(updateSpaceRealmProgress)

-- divider (y=187)
do
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1,-16,0,2); divider.Position = UDim2.new(0,8,0,187)
	divider.BackgroundColor3 = Color3.fromRGB(255,255,255); divider.BackgroundTransparency = 0.7; divider.Parent = rightPanel
end

-- MID-AIR RECHARGE button (y=197)
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
midAir.MouseButton1Click:Connect(function() playUIClick(); pcall(function() MarketplaceService:PromptProductPurchase(player,3600303163) end) end)

-- 2X POWER button (y=295)
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
local twoXPrice = Instance.new("TextLabel")
twoXPrice.Size = UDim2.new(1,-76,0,22); twoXPrice.Position = UDim2.new(0,76,0,62); twoXPrice.BackgroundTransparency = 1
twoXPrice.Text = "59 R$"; twoXPrice.Font = Enum.Font.GothamBold; twoXPrice.TextSize = 16; twoXPrice.TextColor3 = Color3.fromRGB(100,255,100)
twoXPrice.TextScaled = true; twoXPrice.RichText = false; twoXPrice.TextXAlignment = Enum.TextXAlignment.Left; twoXPrice.TextYAlignment = Enum.TextYAlignment.Center; twoXPrice.ZIndex = 5; twoXPrice.Parent = twoX
twoX.MouseButton1Click:Connect(function() playUIClick(); pcall(function() MarketplaceService:PromptProductPurchase(player,3600302990) end) end)

-- BIRD NUKE button (y=393)
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

--======================================================================
-- 4) LEFT-SIDE BUTTONS  (SidebarGui): SHOP / INVITE / Stomach / MORE
--======================================================================
local sidebarGui = Instance.new("ScreenGui")
sidebarGui.Name = "SidebarGui"; sidebarGui.ResetOnSpawn = false; sidebarGui.Parent = PlayerGui

local function mkSideBtn(yOff,bgCol,iconTxt,labelTxt)
	local btn=mkFrame(sidebarGui,{Size=UDim2.new(0,75*scale,0,75*scale),Position=UDim2.new(0,10,0.5,yOff),BackgroundColor3=bgCol})
	mkCorner(btn,14); mkStroke(btn,Color3.new(1,1,1),2)
	local iconL=mkLabel(btn,{Text=iconTxt,Font=Enum.Font.Gotham,TextSize=math.floor(30*scale),Size=UDim2.new(1,0,0,56),Position=UDim2.new(0,0,0,0),RichText=true,BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(iconL,Color3.new(0,0,0),1)
	local textL=mkLabel(btn,{Name="Label",Text=labelTxt,Font=Enum.Font.GothamBold,TextSize=math.floor(12*scale),TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,28),Position=UDim2.new(0,0,0,57),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	mkStroke(textL,Color3.new(0,0,0),1)
	local clickBtn=mkButton(btn,{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""})
	return btn,clickBtn
end

local shopSideFrame,shopSideClick     = mkSideBtn(-90*scale,Color3.fromRGB(50,180,50),"\xF0\x9F\x9b\x92","SHOP")
local inviteSideFrame,inviteSideClick = mkSideBtn(0,Color3.fromRGB(100,80,200),"\xF0\x9F\x91\xa5","INVITE")
local dailySideFrame,dailySideClick   = mkSideBtn(90*scale,Color3.fromRGB(80,170,70),"","Stomach")
do -- stomach icon is an IMAGE (GUT_IMAGE) overlaid in the side button's icon area
	local gutIcon=Instance.new("ImageLabel")
	gutIcon.Name="Icon"; gutIcon.BackgroundTransparency=1; gutIcon.Image=_G.GUT_IMAGE; gutIcon.ScaleType=Enum.ScaleType.Fit
	gutIcon.Size=UDim2.new(0,math.floor(40*scale),0,math.floor(40*scale)); gutIcon.Position=UDim2.new(0.5,0,0,6); gutIcon.AnchorPoint=Vector2.new(0.5,0)
	gutIcon.ZIndex=3; gutIcon.Parent=dailySideFrame
end
local stomachSideFrame,stomachSideClick = mkSideBtn(180*scale,Color3.fromRGB(225,70,170),"+","MORE")

shopSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	toggleMainMenu("Premium", "PremiumShopGui")
end)
inviteSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	pcall(function() SocialService:PromptGameInvite(game.Players.LocalPlayer) end)
end)
dailySideClick.MouseButton1Click:Connect(function()
	playUIClick()
	toggleMainMenu("Stomach", "StomachShopGui")
end)
stomachSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	-- MORE+ popup is built below in this same script; toggle it open/closed.
	if setMoreOpen then setMoreOpen(not moreOpenState) end
end)

--======================================================================
-- 5) REAL MENUS: Premium Shop + Stomach Shop + MORE+ popup
--    These make the coin "+" / SHOP / Stomach / MORE+ buttons open real, WORKING
--    menus instead of no-ops. Every size/position/color/wiring is copied verbatim
--    from ShopClient (Premium Shop) and CoreClient (Stomach Shop + MORE menu).
--    Server-dependent actions (stomach purchase fires BuyStomachEvent; the MORE+
--    sub-items fire crate/pet/locker events) are GUARDED so they no-op cleanly in a
--    world that doesn't have those systems yet, and start working the moment it does.
--======================================================================
local RS  = game:GetService("ReplicatedStorage")
local RSx = RS
local MPS = MarketplaceService
local GAMEPASS_IDS = {TwoXForever=1862015450, GlitterTrail=1859714979}
local PRODUCT_IDS  = {TwoXOneHour=3600302990, MidAirRecharge=3600303163, SkipIsland=3600303265, BirdNuke=3600303082}

-- per-tier gut emoji (used by the stomach shop icons/labels); guarded so it's shared if already set
_G.GUT_EMOJI = _G.GUT_EMOJI or {
	["Tiny Gut"]="\xF0\x9F\x91\xB6", ["Small Gut"]="\xF0\x9F\x90\xB9", ["Medium Gut"]="\xF0\x9F\x90\xB7",
	["Large Gut"]="\xF0\x9F\x90\x98", ["XL Gut"]="\xF0\x9F\xA6\x9B", ["Iron Gut"]="\xF0\x9F\x8F\x8B\xEF\xB8\x8F",
	["Infinite Gut"]="\xF0\x9F\x90\x8B",
}

-- insufficient-funds error sound + "can't afford" button shake (from CoreClient)
local errorSound = Instance.new("Sound")
errorSound.Name="InsufficientFundsSound_HUDClone"; errorSound.SoundId="rbxassetid://87486053112716"; errorSound.Volume=0.6; errorSound.Parent=PlayerGui
local function playErrorSound() local s=errorSound:Clone(); s.Parent=PlayerGui; s:Play(); game:GetService("Debris"):AddItem(s,3) end
local SHAKE_OFFSET = 8
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

--======================================================================
-- 5a) PREMIUM SHOP  (opened by the coin "+" button and the SHOP side button)
--     Verbatim from ShopClient. Fully self-contained: every card just fires a
--     MarketplaceService gamepass/product prompt (works standalone).
--======================================================================
do
	local sg=Instance.new("ScreenGui"); sg.Name="PremiumShopGui"; sg.ResetOnSpawn=false; sg.Enabled=false; sg.DisplayOrder=100; sg.Parent=PlayerGui
	local PremiumShopGui=sg
	mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,Active=false})
	local premPanel=mkFrame(sg,{Size=UDim2.new(0.9,0,0.85,0),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(25,90,185),ClipsDescendants=true,Active=true})
	mkCorner(premPanel,20); mkStroke(premPanel,Color3.new(1,1,1),3)

	local premHeader=mkFrame(premPanel,{Size=UDim2.new(1,0,0,65),BackgroundColor3=Color3.fromRGB(15,60,140)})
	local premTitleLbl=mkLabel(premHeader,{Text="\xF0\x9F\x9B\x92 SHOP",Font=Enum.Font.GothamBold,TextSize=30,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,-60,0,40),Position=UDim2.new(0,14,0,5),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
	mkStroke(premTitleLbl,Color3.new(0,0,0),2)
	mkLabel(premHeader,{Text="Power up your farts!",Font=Enum.Font.Gotham,TextSize=14,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-60,0,18),Position=UDim2.new(0,14,0,45),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
	local premClose=mkButton(premHeader,{Size=UDim2.new(0,40,0,40),Position=UDim2.new(1,-48,0,12),BackgroundColor3=Color3.fromRGB(220,50,50),Text="\xe2\x9c\x95",Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.new(1,1,1)})
	mkCorner(premClose,8)

	local premScroll=Instance.new("ScrollingFrame")
	premScroll.Name="PremiumScroll"; premScroll.BackgroundTransparency=1; premScroll.BorderSizePixel=0
	premScroll.Position=UDim2.new(0,0,0,65); premScroll.Size=UDim2.new(1,0,1,-92)
	premScroll.ScrollBarThickness=6; premScroll.ScrollBarImageColor3=Color3.fromRGB(255,215,0)
	premScroll.CanvasSize=UDim2.new(0,0,0,0); premScroll.ScrollingDirection=Enum.ScrollingDirection.Y
	premScroll.AutomaticCanvasSize=Enum.AutomaticSize.None; premScroll.Parent=premPanel
	do
		local sll=Instance.new("UIListLayout"); sll.FillDirection=Enum.FillDirection.Vertical
		sll.HorizontalAlignment=Enum.HorizontalAlignment.Center; sll.Padding=UDim.new(0,10); sll.SortOrder=Enum.SortOrder.LayoutOrder; sll.Parent=premScroll
		local slp=Instance.new("UIPadding"); slp.PaddingTop=UDim.new(0,8); slp.PaddingBottom=UDim.new(0,10); slp.Parent=premScroll
		local function syncCanvas() premScroll.CanvasSize=UDim2.new(0,0,0, sll.AbsoluteContentSize.Y + 18) end
		sll:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas); task.defer(syncCanvas)
	end
	local CARD_W, CARD_H = 208, 190
	local function sectionHeader(text,order)
		local h=mkFrame(premScroll,{Size=UDim2.new(1,-16,0,28),BackgroundTransparency=1,LayoutOrder=order})
		mkLabel(h,{Text=text,Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,-8,0,22),Position=UDim2.new(0,4,0,0),TextXAlignment=Enum.TextXAlignment.Left})
		mkFrame(h,{Size=UDim2.new(1,-8,0,2),Position=UDim2.new(0,4,0,25),BackgroundColor3=Color3.fromRGB(255,215,0)})
		return h
	end
	local function mkSectionRow(order)
		local row=mkFrame(premScroll,{Size=UDim2.new(1,-16,0,CARD_H),BackgroundTransparency=1,LayoutOrder=order})
		local ll=Instance.new("UIListLayout"); ll.FillDirection=Enum.FillDirection.Horizontal
		ll.HorizontalAlignment=Enum.HorizontalAlignment.Center; ll.VerticalAlignment=Enum.VerticalAlignment.Top
		ll.Padding=UDim.new(0,18); ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Parent=row
		return row
	end
	local function mkShopCard(parent,order)
		local c=mkFrame(parent,{Size=UDim2.new(0,CARD_W,0,CARD_H),LayoutOrder=order,BackgroundColor3=Color3.fromRGB(20,70,160)})
		mkCorner(c,16); mkStroke(c,Color3.new(1,1,1),2)
		local holder=mkFrame(c,{Name="Content",Size=UDim2.new(1,0,1,0),BackgroundTransparency=1})
		local hl=Instance.new("UIListLayout"); hl.FillDirection=Enum.FillDirection.Vertical
		hl.HorizontalAlignment=Enum.HorizontalAlignment.Center; hl.VerticalAlignment=Enum.VerticalAlignment.Top
		hl.Padding=UDim.new(0,3); hl.SortOrder=Enum.SortOrder.LayoutOrder; hl.Parent=holder
		local hp=Instance.new("UIPadding"); hp.PaddingTop=UDim.new(0,18); hp.PaddingBottom=UDim.new(0,6); hp.PaddingLeft=UDim.new(0,8); hp.PaddingRight=UDim.new(0,8); hp.Parent=holder
		return c
	end
	local function cH(card) return card:FindFirstChild("Content") or card end
	local function cardIcon(card,txt)
		mkLabel(cH(card),{Text=txt,Font=Enum.Font.Gotham,TextSize=40,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,42),LayoutOrder=1,RichText=false,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center})
	end
	local function cardTitles(card,main,sub,subCol)
		mkLabel(cH(card),{Text=main,Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,19),LayoutOrder=2,TextXAlignment=Enum.TextXAlignment.Center})
		mkLabel(cH(card),{Text=sub,Font=Enum.Font.GothamBold,TextSize=12,TextColor3=subCol,Size=UDim2.new(1,0,0,15),LayoutOrder=3,TextXAlignment=Enum.TextXAlignment.Center})
	end
	local function cardPrice(card,price)
		mkLabel(cH(card),{Text=price,Font=Enum.Font.GothamBold,TextSize=15,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,0,0,17),LayoutOrder=4,TextXAlignment=Enum.TextXAlignment.Center})
	end
	local function cardDesc(card,desc)
		mkLabel(cH(card),{Text=desc,Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.fromRGB(180,210,255),Size=UDim2.new(1,0,0,20),LayoutOrder=5,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Top})
	end
	local function cardBuyBtn(card,col,txt,onClick)
		local btn=mkButton(cH(card),{Size=UDim2.new(1,0,0,32),LayoutOrder=10,BackgroundColor3=col,Text=txt,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.new(1,1,1)})
		mkCorner(btn,8); btn.MouseButton1Click:Connect(onClick); return btn
	end
	sectionHeader("\xe2\xad\x90 GAMEPASSES",1)
	local gamepassRow=mkSectionRow(2)

	local card1=mkShopCard(gamepassRow,1)
	local gpBadge=mkLabel(card1,{Text="BEST VALUE \xe2\xad\x90",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=Color3.fromRGB(80,40,0),Size=UDim2.new(1,-16,0,16),Position=UDim2.new(0.5,0,0,3),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(255,180,0),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=3})
	mkCorner(gpBadge,6)
	cardIcon(card1,"\xe2\x9a\xa1"); cardTitles(card1,"2x Power","FOREVER",Color3.fromRGB(100,220,100)); cardPrice(card1,"249 R$")
	local btn1=cardBuyBtn(card1,Color3.fromRGB(255,180,0),"BUY GAMEPASS",function()
		if _G.playerGamepasses and _G.playerGamepasses.twoXForever then return end
		pcall(function() MPS:PromptGamePassPurchase(player,GAMEPASS_IDS.TwoXForever) end)
	end)
	mkStroke(btn1,Color3.fromRGB(200,130,0),2)

	local card2=mkShopCard(gamepassRow,2)
	cardIcon(card2,"\xe2\x9c\xa8"); cardTitles(card2,"Glitter Trail","PERMANENT",Color3.fromRGB(100,220,100)); cardPrice(card2,"49 R$")
	cardBuyBtn(card2,Color3.fromRGB(220,80,180),"BUY GAMEPASS",function()
		if _G.playerGamepasses and _G.playerGamepasses.glitterTrail then return end
		pcall(function() MPS:PromptGamePassPurchase(player,GAMEPASS_IDS.GlitterTrail) end)
	end)

	local card3=mkShopCard(gamepassRow,3)
	cardIcon(card3,"\xe2\x8f\xb0"); cardTitles(card3,"2x Power","1 HOUR",Color3.fromRGB(255,200,100)); cardPrice(card3,"59 R$")
	local twoXShopTimer=mkLabel(cH(card3),{Text="",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=Color3.fromRGB(100,220,100),Size=UDim2.new(1,-8,0,14),LayoutOrder=6,TextXAlignment=Enum.TextXAlignment.Center,Visible=false})
	cardBuyBtn(card3,Color3.fromRGB(50,150,255),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.TwoXOneHour) end) end)

	sectionHeader("\xF0\x9F\x8E\xAF ONE-TIME ITEMS",3)
	local productRow=mkSectionRow(4)

	local card4=mkShopCard(productRow,1)
	cardIcon(card4,"\xF0\x9F\x94\x8B"); cardTitles(card4,"Mid-Air","RECHARGE",Color3.fromRGB(100,220,100)); cardPrice(card4,"39 R$"); cardDesc(card4,"Refills gas to 100%!")
	cardBuyBtn(card4,Color3.fromRGB(50,200,50),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.MidAirRecharge) end) end)

	local card5=mkShopCard(productRow,2)
	cardIcon(card5,"\xF0\x9F\x8F\x9D\xEF\xB8\x8F"); cardTitles(card5,"Skip Island","ONE USE",Color3.fromRGB(255,200,100)); cardPrice(card5,"69 R$"); cardDesc(card5,"Jump to next island!")
	cardBuyBtn(card5,Color3.fromRGB(255,140,0),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.SkipIsland) end) end)

	local card6=mkShopCard(productRow,3)
	cardIcon(card6,"\xF0\x9F\x92\xA5"); cardTitles(card6,"Bird Nuke","CHAOS MODE",Color3.fromRGB(255,100,100)); cardPrice(card6,"79 R$"); cardDesc(card6,"Unleash 30 birds on everyone!")
	cardBuyBtn(card6,Color3.fromRGB(220,50,50),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.BirdNuke) end) end)

	mkLabel(premPanel,{Text="Purchases support the game! Thank you! \xF0\x9F\x99\x8F",Font=Enum.Font.Gotham,TextSize=12,TextColor3=Color3.fromRGB(150,180,255),Size=UDim2.new(1,-20,0,18),Position=UDim2.new(0,10,1,-22),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})

	task.spawn(function()
		while true do
			task.wait(1)
			local gp=_G.playerGamepasses
			if gp and gp.twoXHourExpiry and gp.twoXHourExpiry>os.time() then
				local rem=gp.twoXHourExpiry-os.time()
				twoXShopTimer.Text="\xe2\x9a\xa1 Active: "..math.floor(rem/60).."m "..rem%60 .."s"
				twoXShopTimer.Visible=true
			else
				twoXShopTimer.Visible=false
			end
		end
	end)

	premClose.MouseButton1Click:Connect(function() playUIClick(); PremiumShopGui.Enabled=false; _G.MainMenuManager.notifyClosed("Premium") end)
end

--======================================================================
-- 5b) STOMACH SHOP  (opened by the "Stomach" side button)
--     Verbatim from CoreClient (the Shop GUI part). The 7 gut tiers fire
--     BuyStomachEvent to the server; the current-tier label + "OWNED" badges
--     read leaderstats. All server reads are guarded, so the GUI builds + opens
--     even with no server, and the buys start working once leaderstats exist.
--======================================================================
-- local gut state (CoreClient keeps these script-level; default to Tiny Gut)
local stomachName  = "Tiny Gut"
local stomachMax   = 100
local currentPower = 0
local stomachEmoji = _G.GUT_EMOJI["Tiny Gut"]
local updateStomachDisplay -- nil here (this clone has no bottom gut pill); stomach-shop handler guards on it
task.spawn(function()
	local stomachShopGui=Instance.new("ScreenGui"); stomachShopGui.Name="StomachShopGui"; stomachShopGui.ResetOnSpawn=false; stomachShopGui.Enabled=false; stomachShopGui.DisplayOrder=100; stomachShopGui.Parent=PlayerGui
	local currentStomachLabel; local scrollFrame; local ttlIcon; local ttlIconImg
	do
		local stomachPanel=Instance.new("Frame"); stomachPanel.Size=UDim2.new(0,700,0,520)
		stomachPanel.Position=UDim2.new(0.5,0,0.5,-45); stomachPanel.AnchorPoint=Vector2.new(0.5,0.5)
		stomachPanel.BackgroundColor3=Color3.fromRGB(30,120,220); stomachPanel.BorderSizePixel=0; stomachPanel.Active=true; stomachPanel.Parent=stomachShopGui
		mkCorner(stomachPanel,20); mkStroke(stomachPanel,Color3.fromRGB(20,60,160),3)
		do
			local bg=Instance.new("Frame"); bg.Size=UDim2.new(1,0,1,0); bg.BackgroundColor3=Color3.new(0,0,0)
			bg.BackgroundTransparency=1; bg.Active=false; bg.BorderSizePixel=0; bg.ZIndex=0; bg.Parent=stomachShopGui
			ttlIcon=Instance.new("TextLabel"); ttlIcon.Name="GutIcon"; ttlIcon.BackgroundTransparency=1
			ttlIcon.Text=(_G.GUT_EMOJI[stomachName] or ""); ttlIcon.Font=Enum.Font.GothamBold; ttlIcon.TextScaled=true
			ttlIcon.Size=UDim2.new(0,46,0,46); ttlIcon.Position=UDim2.new(0,12,0,9); ttlIcon.Parent=stomachPanel
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
			sc.MouseButton1Click:Connect(function() playUIClick(); stomachShopGui.Enabled=false; _G.MainMenuManager.notifyClosed("Stomach") end)
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

	-- gut-upgrade-affordable wiggle on the LEFT "Stomach" side button (dailySideFrame)
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
		if not gutSideIcon then return end
		if gutWiggling then return end
		gutWiggling = true
		gutSideIcon.Rotation = -8
		local info = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		gutWiggleTween = TweenService:Create(gutSideIcon, info, { Rotation = 8 })
		gutWiggleTween:Play()
	end
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
		local nextTier = nextCoinGutTier(sm.Value)
		local affordable = (nextTier ~= nil) and (c.Value >= nextTier.cost)
		if affordable then startGutWiggle() else stopGutWiggle() end
		_G.gutUpgradeAffordable = affordable
	end
	_G.forceGutWiggle = startGutWiggle
	_G.checkGutAfford = checkGutAfford
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
			card.LayoutOrder = (tier.name == "Infinite Gut") and 1 or (i + 1)
			card.BackgroundColor3=Color3.fromRGB(20,90,200); card.Parent=scrollFrame
			mkCorner(card,12); mkStroke(card,Color3.fromRGB(255,255,255),2)
			do
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
				if tier.robux then pcall(function() game:GetService("MarketplaceService"):PromptGamePassPurchase(player,1860686821) end)
				elseif BuyStomachEvent then
					local coinsVal, ownedMax = 0, 0
					pcall(function()
						local ls=player:FindFirstChild("leaderstats")
						if ls then
							local c=ls:FindFirstChild("Coins"); if c then coinsVal=c.Value end
							local sm=ls:FindFirstChild("StomachMax"); if sm then ownedMax=sm.Value end
						end
					end)
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
				currentPower = math.min(currentPower, stomachMax)
				local info = stomachNames[stomachMax]
				if info then stomachEmoji = info[1]; stomachName = info[2] end
				local maxStr = stomachMax >= 9999 and "\xe2\x88\x9e" or tostring(stomachMax)
				currentStomachLabel.Text = "Current: " .. stomachName .. " (" .. maxStr .. " max power)"
				if updateStomachDisplay then updateStomachDisplay() end
				checkGutAfford()
				if ttlIcon then
					if stomachName == "XL Gut" then
						ttlIcon.Text = ""
						if ttlIconImg then ttlIconImg.Visible = true end
					else
						ttlIcon.Text = _G.GUT_EMOJI[stomachName] or ttlIcon.Text
						if ttlIconImg then ttlIconImg.Visible = false end
					end
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

--======================================================================
-- 5c) MORE+ POPUP  (opened by the MORE+ side button)
--     Verbatim from CoreClient. The three entries fire the SAME events the real
--     game uses: Daily Rewards -> OpenMeteorCrate (CrateClient), Pets -> PetInvToggle
--     (PetFollow), Seasonal Pets -> openLocker. Those sub-systems must exist in the
--     world for the entries to DO something; otherwise each entry fires harmlessly.
--======================================================================
do
	local moreGui = Instance.new("ScreenGui"); moreGui.Name = "MoreMenuGui"; moreGui.ResetOnSpawn = false
	moreGui.DisplayOrder = 8; moreGui.Parent = PlayerGui
	local catcher = mkButton(moreGui, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 1, Visible = false })
	local panel = mkFrame(moreGui, { Size = UDim2.new(0, 196, 0, 206), BackgroundColor3 = Color3.fromRGB(225, 70, 170), Visible = false, ZIndex = 2 })
	mkCorner(panel, 14); mkStroke(panel, Color3.new(1, 1, 1), 2)
	local pad = Instance.new("UIPadding", panel); pad.PaddingTop = UDim.new(0, 8); pad.PaddingBottom = UDim.new(0, 8); pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)
	local hdr = mkFrame(panel, { Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1, ZIndex = 2 })
	mkLabel(hdr, { Text = "MORE", Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -32, 1, 0), Position = UDim2.new(0, 4, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	local moreX = mkButton(hdr, { Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -26, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.fromRGB(210, 60, 55), Text = "X", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
	mkCorner(moreX, 8)

	local entryScroll = Instance.new("ScrollingFrame")
	entryScroll.Name = "EntryList"
	entryScroll.BackgroundTransparency = 1
	entryScroll.BorderSizePixel = 0
	entryScroll.Position = UDim2.new(0, 0, 0, 36)
	entryScroll.Size = UDim2.new(1, 0, 1, -36)
	entryScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	entryScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	entryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	entryScroll.ScrollBarThickness = 6
	entryScroll.ClipsDescendants = true
	entryScroll.ZIndex = 2
	entryScroll.Parent = panel
	local entryListLayout = Instance.new("UIListLayout", entryScroll); entryListLayout.SortOrder = Enum.SortOrder.LayoutOrder; entryListLayout.Padding = UDim.new(0, 8)

	local crateReadyDots = {}
	local function mkCrateDot(parent)
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
		crateReadyDots[#crateReadyDots + 1] = dot
		return dot
	end

	local MORE_ENTRIES = {
		{ label = "Daily Rewards", emoji = "\xF0\x9F\x8E\x81", readyDot = true, action = function()
			local ev = RSx:FindFirstChild("OpenMeteorCrate")
			if not ev then ev = Instance.new("BindableEvent"); ev.Name = "OpenMeteorCrate"; ev.Parent = RSx end
			ev:Fire()
		end },
		{ label = "Pets", emoji = "\xF0\x9F\x90\xBE", action = function() local ev = PlayerGui:FindFirstChild("PetInvToggle"); if ev then ev:Fire() end end },
		{ label = "Seasonal Pets",  emoji = "\xF0\x9F\x90\xBE", action = function() if openLocker then openLocker() end end },
	}
	for i, e in ipairs(MORE_ENTRIES) do
		local row = mkButton(entryScroll, { Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = e.color or Color3.fromRGB(248, 240, 250), Text = "", ZIndex = 2, LayoutOrder = i })
		mkCorner(row, 10)
		if e.readyDot then mkCrateDot(row) end
		if e.image then
			local im = Instance.new("ImageLabel"); im.BackgroundTransparency = 1; im.Image = e.image; im.ScaleType = Enum.ScaleType.Fit
			im.Size = UDim2.new(0, 30, 0, 30); im.Position = UDim2.new(0, 8, 0.5, 0); im.AnchorPoint = Vector2.new(0, 0.5); im.ZIndex = 3; im.Parent = row
		else
			mkLabel(row, { Text = e.emoji or "", Font = Enum.Font.Gotham, TextSize = 22, Size = UDim2.new(0, 30, 1, 0), Position = UDim2.new(0, 8, 0, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		end
		mkLabel(row, { Text = e.label, Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.fromRGB(70, 40, 65), Size = UDim2.new(1, -50, 1, 0), Position = UDim2.new(0, 46, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
		row.MouseButton1Click:Connect(function() playUIClick(); setMoreOpen(false); pcall(e.action) end)
	end
	mkCrateDot(stomachSideFrame) -- "!" dot on the MORE+ button itself
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
	task.spawn(function()
		while true do
			local ready = (_G.crateIsClaimable and _G.crateIsClaimable()) == true
			for _, d in ipairs(crateReadyDots) do d.Visible = ready end
			if ready then startMoreWiggle() else stopMoreWiggle() end
			task.wait(1)
		end
	end)

	setMoreOpen = function(open)
		moreOpenState = open and true or false
		if moreOpenState then
			local ap, asz = stomachSideFrame.AbsolutePosition, stomachSideFrame.AbsoluteSize
			panel.Position = UDim2.fromOffset(ap.X + asz.X + 10, ap.Y) -- appears just to the RIGHT of the MORE+ button
			panel.Visible = true; catcher.Visible = true
		else
			panel.Visible = false; catcher.Visible = false
		end
	end
	catcher.MouseButton1Click:Connect(function() setMoreOpen(false) end)
	moreX.MouseButton1Click:Connect(function() playUIClick(); setMoreOpen(false) end)
end

print("[HUDClone] all on-screen HUD components built: Coins, Settings, Right Stats Panel, Left Sidebar, Premium Shop, Stomach Shop, MORE+ menu")
