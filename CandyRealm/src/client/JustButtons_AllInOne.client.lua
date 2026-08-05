--======================================================================
-- JustButtons_AllInOne.client.lua  (LocalScript)
--======================================================================
-- The FINAL in-game look of the buttons + the REAL wiring behind them.
-- Geometry/colors are the values AFTER CoreClient's restyle + repositionGUIs
-- passes (the 95x95 rail, brighter fart button, etc). The click wiring is the
-- verbatim CoreClient behavior, grafted on so the rail actually opens menus.
--
--   LEFT RAIL (SidebarGui): 4 buttons, 95x95, top-left x=12, y 96/203/310/417
--       SHOP (candy cane) -> PremiumShopGui       (Shop_AllInOne)
--       PETS (grape)      -> _G.togglePetHub()    (PetHub_AllInOne)
--       Stomach (mint)    -> StomachShopGui
--       MORE (bubblegum)  -> MORE+ popup
--
--   PETS took the WORMHOLE slot (same swap the main game made): players open the
--   pet hub constantly, fast travel is a sometimes action -- so the Wormhole card
--   moved into the MORE+ menu (MorePopup_AllInOne) and Pets holds the rail.
--
--   CANDY PASS: the rail reads as four WRAPPED SWEETS. It is PAINT ONLY -- every size,
--   position, corner radius and stroke width is the same number it was before, so the
--   mobile rail repitch and all the click wiring below are untouched. Only colour,
--   gradient and two icon glyphs changed.
--   BOTTOM STACK (BottomStackGui): no longer built here -- BottomMeterPanel.client.luau
--       owns it, as one candy card instead of three slabs. It keeps the same ScreenGui
--       name, so mgr.setHud below still finds it. Only _G.HUD is still created here.
--
-- All wiring is GUARDED: it no-ops cleanly if a target menu/event isn't in this
-- realm yet, and starts working the moment it is. Values below are the DESKTOP
-- (scale 1.0) final grid; on mobile the game recomputes the rail pitch live.
--======================================================================

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local scale = 1.0 -- desktop grid (matches the authored y96/203/310/417 rail)

-- ===== helpers (verbatim from CoreClient) =====
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end
local GUT_IMAGE = "rbxassetid://108585083746103" -- stomach/gut icon image
_G.GUT_IMAGE = _G.GUT_IMAGE or GUT_IMAGE

-- ===== UI CLICK SOUND (self-contained, shared via _G) =====
-- NOTE: the standard UI-click asset (rbxassetid://101638558691673) is NOT accessible
-- to this experience ("User is not authorized to access Asset"), so it spammed the
-- console on every click. Left blank => silent, no error. Drop in an OWNED audio id here.
local UI_CLICK_SOUND_ID = "" -- e.g. "rbxassetid://<your owned click sound>"
local uiClickSound = Instance.new("Sound")
uiClickSound.Name = "UIClickSound_Sidebar"; uiClickSound.SoundId = UI_CLICK_SOUND_ID; uiClickSound.Volume = 0.5; uiClickSound.Parent = PlayerGui
local function playUIClick()
	if uiClickSound.SoundId == "" then return end -- no valid asset -> stay silent (no load error)
	local s = uiClickSound:Clone(); s.Parent = PlayerGui; s:Play(); game:GetService("Debris"):AddItem(s, 3)
end
_G.playUIClick = _G.playUIClick or playUIClick

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY (shared; reuse whoever defined it first) =====
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
-- LEFT RAIL -- 4 buttons, FINAL look: 95x95, top-left x=12, fixed Y grid.
--   frames order (from repositionGUIs): SHOP, PETS, Stomach, MORE
--   Y grid (desktop): 96, 203, 310, 417   (107px pitch)
--======================================================================
local sidebarGui = Instance.new("ScreenGui")
sidebarGui.Name = "SidebarGui"; sidebarGui.ResetOnSpawn = false; sidebarGui.Parent = PlayerGui

-- ===== CANDY PAINT HELPERS =====
-- The button's BackgroundColor3 is left WHITE and all colour comes from the UIGradient.
-- UIGradient MULTIPLIES with the background, so a tinted background would quietly mute
-- every colour underneath it -- white is the only value that renders the stops as authored.
local function candyGradient(frame, top, bottom, rotation)
	local g = Instance.new("UIGradient")
	g.Name = "CandyPaint"
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = frame
	return g
end

-- CANDY-CANE STRIPES. Hard stops are the whole trick: two keypoints a hair apart give a
-- BAND, where two keypoints far apart give a fade. Diagonal, because vertical stripes on a
-- square read as a barcode. ColorSequence demands strictly-increasing offsets that start at
-- exactly 0 and end at exactly 1, which is what the clamping on the first/last band is for.
local function candyStripes(grad, a, b, bands, rotation)
	local keys, n = {}, bands or 6
	for i = 0, n - 1 do
		local col = (i % 2 == 0) and a or b
		local s, e = i / n, (i + 1) / n
		keys[#keys + 1] = ColorSequenceKeypoint.new(i == 0 and 0 or s + 0.0005, col)
		keys[#keys + 1] = ColorSequenceKeypoint.new(i == n - 1 and 1 or e - 0.0005, col)
	end
	grad.Color = ColorSequence.new(keys)
	grad.Rotation = rotation or 45
end

-- makes a 95x95 rail button with the FINAL corner/stroke geometry from the restyle pass,
-- now painted as a wrapped sweet. Returns the frame, a transparent full-size TextButton
-- overlay for click wiring, and the gradient (so a caller can restripe it).
local function mkRailBtn(y, colTop, colBot, corner, strokeCol, strokeW, iconTxt, labelTxt)
	local btn = mkFrame(sidebarGui,{
		Size=UDim2.new(0,95,0,95), AnchorPoint=Vector2.new(0,0),
		Position=UDim2.new(0,12,0,y), BackgroundColor3=Color3.new(1,1,1),
	})
	mkCorner(btn, corner); mkStroke(btn, strokeCol, strokeW)
	local grad = candyGradient(btn, colTop, colBot, 90)
	-- GLOSS: a soft white band across the top. This one detail is what turns a flat coloured
	-- square into something that looks WRAPPED and pickable-up. It is a plain Frame, and Frames
	-- never consume input, so the click overlay above it is completely unaffected.
	local gloss = mkFrame(btn,{Name="Gloss",Size=UDim2.new(1,-12,0,26),Position=UDim2.new(0,6,0,5),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=0.72,BorderSizePixel=0,ZIndex=2})
	mkCorner(gloss, math.max(corner - 5, 6))
	-- icon + label sit ABOVE the gloss (ZIndex 3 vs 2), or the shine washes the glyph out
	local iconL=mkLabel(btn,{Text=iconTxt,Font=Enum.Font.Gotham,TextSize=math.floor(30*scale),Size=UDim2.new(1,0,0,56),Position=UDim2.new(0,0,0,0),RichText=true,TextXAlignment=Enum.TextXAlignment.Center,ZIndex=3})
	mkStroke(iconL,Color3.new(0,0,0),1)
	local textL=mkLabel(btn,{Name="Label",Text=labelTxt,Font=Enum.Font.GothamBold,TextSize=math.floor(12*scale),TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,28),Position=UDim2.new(0,0,0,57),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=3})
	mkStroke(textL,Color3.new(0,0,0),1)
	local clickBtn=mkButton(btn,{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="",ZIndex=5})
	return btn, clickBtn, grad
end

-- 1) SHOP -- CANDY CANE. The only striped button on the rail: one striped face among four
--    solid ones reads as a highlight, where four striped faces read as noise. Corner 16 (kept).
local shopSide, shopClick, shopGrad = mkRailBtn(96, Color3.new(1,1,1), Color3.new(1,1,1), 16, Color3.fromRGB(205,45,70), 3, "\xF0\x9F\x8D\xAC", "SHOP")
candyStripes(shopGrad, Color3.fromRGB(255,255,255), Color3.fromRGB(255,80,95), 6, 45)
-- 2) PETS -- GRAPE. Same grape-lolly wrapper the slot always had (keeps the rail's candy
--    palette: cane / grape / mint / bubblegum), now with the paw glyph and the PET HUB behind
--    it. WORMHOLE gave up this slot and lives in the MORE+ menu (MorePopup_AllInOne).
local petsSide, petsClick = mkRailBtn(203, Color3.fromRGB(200,140,255), Color3.fromRGB(140,70,225), 16, Color3.fromRGB(95,40,165), 3, "\xF0\x9F\x90\xBE", "PETS")
-- 3) Stomach -- MINT. Corner 16, stroke w3 (kept); icon is still the GUT_IMAGE.
local stomachSide, stomachClick = mkRailBtn(310, Color3.fromRGB(155,240,205), Color3.fromRGB(70,205,155), 16, Color3.fromRGB(35,140,110), 3, "", "Stomach")
do
	local gutIcon=Instance.new("ImageLabel")
	gutIcon.Name="Icon"; gutIcon.BackgroundTransparency=1; gutIcon.Image=GUT_IMAGE; gutIcon.ScaleType=Enum.ScaleType.Fit
	gutIcon.Size=UDim2.new(0,math.floor(40*scale),0,math.floor(40*scale)); gutIcon.Position=UDim2.new(0.5,0,0,6); gutIcon.AnchorPoint=Vector2.new(0.5,0)
	gutIcon.ZIndex=3; gutIcon.Parent=stomachSide
end
-- 4) MORE -- STATS PINK. Was a lighter bubblegum (255,150,215 -> 240,80,175); now the exact
--    CANDY.bodyTop/bodyBot the stats panel is built from (StatsPanelKit_AllInOne, `local CANDY`),
--    so the button and the panel it sits beside are one pink rather than two that nearly match.
--    That pink is also the CONTRAST-MEASURED one: the stats panel notes a first draft of
--    (238,116,186) measured 2.7:1 against white text, where this reads ~4.7:1. Keeps its
--    ORIGINAL corner 14 + WHITE stroke w2 (the old restyle pass never touched MORE, deliberately).
local moreSide, moreClick = mkRailBtn(417, Color3.fromRGB(196,66,148), Color3.fromRGB(158,48,140), 14, Color3.new(1,1,1), 2, "+", "MORE")

--======================================================================
-- WIRING (all guarded) -- verbatim CoreClient behavior
--======================================================================
shopClick.MouseButton1Click:Connect(function()
	_G.playUIClick(); toggleMainMenu("Premium","PremiumShopGui")
end)
petsClick.MouseButton1Click:Connect(function()
	_G.playUIClick()
	-- _G.togglePetHub FIRST (the hub's own unambiguous door): a baked-in copy of the pet kit
	-- can leave a SECOND BindableEvent named PetInvToggle behind, and FindFirstChild can return
	-- the impostor. The found-event is fallback only, for load-order races.
	if _G.togglePetHub then
		pcall(_G.togglePetHub)
	else
		local ev = PlayerGui:FindFirstChild("PetInvToggle")
		if ev and ev:IsA("BindableEvent") then ev:Fire() end
	end
end)
stomachClick.MouseButton1Click:Connect(function()
	_G.playUIClick(); toggleMainMenu("Stomach","StomachShopGui")
end)
moreClick.MouseButton1Click:Connect(function()
	_G.playUIClick()
	-- MORE+ popup: fire the shared toggler if present, else the OpenMorePopup signal
	if _G.toggleMorePopup then
		_G.toggleMorePopup()
	else
		local sig = PlayerGui:FindFirstChild("OpenMorePopup")
		if sig and sig:IsA("BindableEvent") then sig:Fire() end
	end
end)

-- ===== Stomach button wiggle when a gut upgrade is affordable =====
do
	local wiggling, tween = false, nil
	local function stopWiggle()
		if not wiggling then return end
		wiggling = false
		if tween then pcall(function() tween:Cancel() end); tween = nil end
		stomachSide.Rotation = 0
	end
	local function startWiggle()
		if wiggling then return end
		wiggling = true; stomachSide.Rotation = -8
		local info = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		tween = TweenService:Create(stomachSide, info, { Rotation = 8 }); tween:Play()
	end
	task.spawn(function()
		while true do
			if _G.gutUpgradeAffordable == true then startWiggle() else stopWiggle() end
			task.wait(1)
		end
	end)
end

-- ===== MORE button "!" dot + wiggle when the daily crate/tasks need attention =====
do
	local dot = Instance.new("Frame")
	dot.Name = "MoreReadyDot"; dot.Size = UDim2.fromOffset(18,18); dot.AnchorPoint = Vector2.new(1,0)
	dot.Position = UDim2.new(1,-2,0,-2); dot.BackgroundColor3 = Color3.fromRGB(225,50,50); dot.ZIndex = 8; dot.Visible = false; dot.Parent = moreSide
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1,0); dc.Parent = dot
	local bang = Instance.new("TextLabel"); bang.BackgroundTransparency=1; bang.Size=UDim2.fromScale(1,1)
	bang.Font=Enum.Font.GothamBlack; bang.Text="!"; bang.TextSize=13; bang.TextColor3=Color3.new(1,1,1); bang.ZIndex=9; bang.Parent=dot
	local wiggling, tween = false, nil
	local function stopWiggle() if not wiggling then return end wiggling=false; if tween then pcall(function() tween:Cancel() end); tween=nil end moreSide.Rotation=0 end
	local function startWiggle() if wiggling then return end wiggling=true; moreSide.Rotation=-8
		local info=TweenInfo.new(0.32,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true); tween=TweenService:Create(moreSide,info,{Rotation=8}); tween:Play() end
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

--======================================================================
-- BOTTOM STACK -- MOVED OUT. BottomMeterPanel.client.luau owns it now.
--======================================================================
-- This file used to build "BottomStackGui" as THREE stacked slabs bottom-centre: a pink
-- "Stomach" pill, a blue GAS METER panel and a green HOLD TO FART button, about 200px of
-- screen. BottomMeterPanel.client.luau replaces all three with ONE 144px candy card --
-- badge, title, meter and button in a single rounded panel -- and keeps both contracts
-- this code had:
--   * its ScreenGui is still named "BottomStackGui", so MainMenuManager.setHud below and
--     the four other scripts that hide the HUD by that name need no change at all;
--   * it publishes _G.HUD.gasFill / .gasPct / .fartLabel off its own parts, so the flight
--     engine (PropelSystem_AllInOne) writes exactly the handles it always wrote.
-- Only the _G.HUD table itself stays here, created empty for load order -- either file may
-- run first, and both fill it non-destructively.
_G.HUD = _G.HUD or {} -- shared handles the flight engine drives (gas bar + fart label)

print("[JustButtons] CANDY rail WIRED: candy-cane SHOP / grape PETS / mint Stomach / bubblegum MORE (bottom stack -> BottomMeterPanel)")
