--======================================================================
-- LeftSidebar_AllInOne.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of the 4 LEFT-SIDE HUD BUTTONS from CoreClient,
-- with EXACT sizes/positions/colors/icons/wiring copied verbatim:
--
--   1 (top)    SHOP      green  🛒  -> opens the Premium Shop (PremiumShopGui)
--   2          WORMHOLE  purple 🌀  -> opens the wormhole travel menu
--   3          Stomach   green  (gut image) -> opens the Stomach Shop (StomachShopGui)
--   4 (bottom) MORE      pink   +   -> toggles the MORE+ popup
--
-- All 4 are built by mkSideBtn(yOff, color, icon, label): a 75x75*scale frame
-- pinned far-left (x=10) and vertically centered (Position 0,10, 0.5,yOff).
-- Wiring is GUARDED so it no-ops cleanly if the target menus/events aren't in
-- this world yet, and starts working the moment they are. Drop into
-- StarterPlayer > StarterPlayerScripts (or sync via Rojo).
--======================================================================

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SocialService    = game:GetService("SocialService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local scale    = isMobile and 0.7 or 1.0

-- ===== GUI HELPERS (verbatim from CoreClient) =====
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

_G.GUT_IMAGE = _G.GUT_IMAGE or "rbxassetid://108585083746103" -- stomach/gut icon

-- ===== UI CLICK SOUND (self-contained, shared via _G) =====
local function makeClick()
	local s = Instance.new("Sound")
	s.Name = "UIClickSound_LeftSidebar"; s.SoundId = "rbxassetid://101638558691673"; s.Volume = 0.5; s.Parent = PlayerGui
	return s
end
local uiClickSound = makeClick()
local function playUIClick()
	local s = uiClickSound:Clone(); s.Parent = PlayerGui; s:Play(); game:GetService("Debris"):AddItem(s, 3)
end
_G.playUIClick = _G.playUIClick or playUIClick

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY (shared; reuse CoreClient's if present) =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible)
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local g = pg and pg:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then
			local h = mgr.hiders[mgr.current]; if h then pcall(h) end
		end
		mgr.current = name; mgr.setHud(false)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
_G.MainMenuManager.register("Premium", function() local g=PlayerGui:FindFirstChild("PremiumShopGui"); if g then g.Enabled=false end end)
_G.MainMenuManager.register("Stomach", function() local g=PlayerGui:FindFirstChild("StomachShopGui"); if g then g.Enabled=false end end)
local function toggleMainMenu(name, guiName)
	local g = PlayerGui:FindFirstChild(guiName); if not g then return end
	if g.Enabled then
		g.Enabled = false; _G.MainMenuManager.notifyClosed(name)
	else
		_G.MainMenuManager.notifyOpened(name); g.Enabled = true
	end
end

--======================================================================
-- THE SIDEBAR: 4 buttons built by mkSideBtn (verbatim geometry)
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

-- 1) SHOP  (green, top)
local shopSideFrame,shopSideClick=mkSideBtn(-90*scale,Color3.fromRGB(50,180,50),"\xF0\x9F\x9b\x92","SHOP")
-- 2) WORMHOLE (purple)
local inviteSideFrame,inviteSideClick=mkSideBtn(0,Color3.fromRGB(140,86,226),"\xF0\x9F\x8C\x80","WORMHOLE")
-- 3) Stomach (green, gut IMAGE icon overlaid)
local dailySideFrame,dailySideClick=mkSideBtn(90*scale,Color3.fromRGB(80,170,70),"","Stomach")
do
	local gutIcon=Instance.new("ImageLabel")
	gutIcon.Name="Icon"; gutIcon.BackgroundTransparency=1; gutIcon.Image=_G.GUT_IMAGE; gutIcon.ScaleType=Enum.ScaleType.Fit
	gutIcon.Size=UDim2.new(0,math.floor(40*scale),0,math.floor(40*scale)); gutIcon.Position=UDim2.new(0.5,0,0,6); gutIcon.AnchorPoint=Vector2.new(0.5,0)
	gutIcon.ZIndex=3; gutIcon.Parent=dailySideFrame
end
-- 4) MORE (pink, bottom)
local stomachSideFrame,stomachSideClick=mkSideBtn(180*scale,Color3.fromRGB(225,70,170),"+","MORE")

--======================================================================
-- WIRING (all guarded)
--======================================================================
shopSideClick.MouseButton1Click:Connect(function()
	playUIClick(); toggleMainMenu("Premium","PremiumShopGui")
end)
inviteSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	if _G.toggleWormhole then
		_G.toggleWormhole()
	else
		local sig = ReplicatedStorage:FindFirstChild("OpenWormhole")
		if not sig then sig = Instance.new("BindableEvent"); sig.Name="OpenWormhole"; sig.Parent=ReplicatedStorage end
		sig:Fire()
	end
end)
dailySideClick.MouseButton1Click:Connect(function()
	playUIClick(); toggleMainMenu("Stomach","StomachShopGui")
end)
stomachSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	-- MORE+ popup: fire the shared toggler if present, else the OpenMorePopup signal
	if _G.toggleMorePopup then
		_G.toggleMorePopup()
	else
		local sig = PlayerGui:FindFirstChild("OpenMorePopup")
		if sig and sig:IsA("BindableEvent") then sig:Fire() end
	end
end)

-- ===== Stomach button wiggle when a gut upgrade is affordable (verbatim behavior) =====
do
	local wiggling, tween = false, nil
	local function stopWiggle()
		if not wiggling then return end
		wiggling = false
		if tween then pcall(function() tween:Cancel() end); tween = nil end
		dailySideFrame.Rotation = 0
	end
	local function startWiggle()
		if wiggling then return end
		wiggling = true; dailySideFrame.Rotation = -8
		local info = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		tween = TweenService:Create(dailySideFrame, info, { Rotation = 8 }); tween:Play()
	end
	task.spawn(function()
		while true do
			local ok = (_G.gutUpgradeAffordable == true)
			if ok then startWiggle() else stopWiggle() end
			task.wait(1)
		end
	end)
end

-- ===== MORE button "!" dot + wiggle when the daily crate/tasks need attention =====
do
	local dot = Instance.new("Frame")
	dot.Name = "MoreReadyDot"; dot.Size = UDim2.fromOffset(18,18); dot.AnchorPoint = Vector2.new(1,0)
	dot.Position = UDim2.new(1,-2,0,-2); dot.BackgroundColor3 = Color3.fromRGB(225,50,50); dot.ZIndex = 8; dot.Visible = false; dot.Parent = stomachSideFrame
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1,0); dc.Parent = dot
	local bang = Instance.new("TextLabel"); bang.BackgroundTransparency=1; bang.Size=UDim2.fromScale(1,1)
	bang.Font=Enum.Font.GothamBlack; bang.Text="!"; bang.TextSize=13; bang.TextColor3=Color3.new(1,1,1); bang.ZIndex=9; bang.Parent=dot
	local wiggling, tween = false, nil
	local function stopWiggle() if not wiggling then return end wiggling=false; if tween then pcall(function() tween:Cancel() end); tween=nil end stomachSideFrame.Rotation=0 end
	local function startWiggle() if wiggling then return end wiggling=true; stomachSideFrame.Rotation=-8
		local info=TweenInfo.new(0.32,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true); tween=TweenService:Create(stomachSideFrame,info,{Rotation=8}); tween:Play() end
	task.spawn(function()
		while true do
			local ready   = (_G.crateIsClaimable and _G.crateIsClaimable()) == true
			local pending = (_G.dailyTasksPending and _G.dailyTasksPending()) == true
			dot.Visible = ready or pending
			if ready or pending then startWiggle() else stopWiggle() end
			task.wait(1)
		end
	end)
end

print("[LeftSidebar] 4 side buttons built: SHOP / WORMHOLE / Stomach / MORE")
