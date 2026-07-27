--[[
	WormholeClient.client.luau  (StarterPlayerScripts.WormholeClient)

	The Wormhole travel menu for THIS realm (the island tower). The menu HUD is ported from the Space Realm's
	wormhole; the warp CINEMATIC + SOUND come from the shared WarpEffect module (WarpEffect.luau). The DATA is
	rewired to this place: destinations are the 14 ISLANDS, the gate is the "HighestIsland" player attribute, and
	the teleport is our own server-authoritative WormholeWarp RemoteFunction (validates reached-island + grounded,
	then places you on that island's stand).

	Opens from the WORMHOLE side button (CoreClient): _G.toggleWormhole() or the "OpenWormhole" BindableEvent.
	Travel only: it never unlocks an island or grants progression -- it just moves you to one you've reached.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- WARP CINEMATIC + SOUND -- the shared module (the new file). play(onPeak) does the ~1.9s tunnel; playSound() whooshes.
local WarpEffect = require(script.Parent:WaitForChild("WarpEffect"))

-- ===== destinations (this realm's 14 islands) =====
local ISLANDS = {
	"Bean Farm", "Broccoli Bluff", "Cabbage Cliffs", "Turnip Tranquil", "Coconut Cove", "Bread Board",
	"Pasta Peak", "Popcorn Pinnacle", "Milk Marsh", "Butter Swamp", "Ice Cream Isle", "Burger Bluff",
	"Burrito Barrens", "Pizza Palms",
}
-- a colour per island (row icon disc + stroke), warm-to-cool up the tower
local ISLAND_COLORS = {
	Color3.fromRGB(180, 210, 90), Color3.fromRGB(110, 200, 90), Color3.fromRGB(120, 200, 120), Color3.fromRGB(200, 150, 90),
	Color3.fromRGB(150, 110, 80), Color3.fromRGB(220, 190, 120), Color3.fromRGB(230, 200, 140), Color3.fromRGB(250, 230, 150),
	Color3.fromRGB(235, 240, 250), Color3.fromRGB(250, 220, 120), Color3.fromRGB(180, 220, 240), Color3.fromRGB(210, 120, 90),
	Color3.fromRGB(200, 140, 90), Color3.fromRGB(230, 120, 110),
}

-- ===== Palette (Space-Realm wormhole look) =====
local PANEL      = Color3.fromRGB(18, 24, 52)
local PANEL_DEEP = Color3.fromRGB(10, 14, 32)
local ACCENT     = Color3.fromRGB(150, 90, 230)
local TITLE_BAR  = Color3.fromRGB(28, 22, 60)
local WHITE      = Color3.fromRGB(235, 242, 255)
local LOCK_GREY  = Color3.fromRGB(46, 50, 66)
local MUTED      = Color3.fromRGB(150, 160, 195)

-- ===== gate + position state =====
-- Highest island the player has UNLOCKED (reached). Clamped to a minimum of 1 so Bean Farm (island 1) is ALWAYS
-- unlocked/warpable, even before the HighestIsland attribute has replicated. Islands above this stay locked.
local function highestIsland() return math.max(1, math.floor(tonumber(player:GetAttribute("HighestIsland")) or 1)) end
local islandY = {} -- island Y-heights (for the "Here" marker), from StandsReadyEvent
task.spawn(function()
	local sre = ReplicatedStorage:FindFirstChild("StandsReadyEvent") or ReplicatedStorage:WaitForChild("StandsReadyEvent", 30)
	if sre then
		sre.OnClientEvent:Connect(function(data)
			for num, pos in pairs(data) do islandY[tonumber(num)] = pos.y end
		end)
	end
end)
local function currentIsland()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not next(islandY) then return nil end
	local best, bestD = nil, math.huge
	for num, y in pairs(islandY) do
		local d = math.abs(hrp.Position.Y - y)
		if d < bestD then bestD, best = d, num end
	end
	return (bestD < 200) and best or nil
end
local function isGrounded()
	if _G.isFlying then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
end

-- our server-authoritative warp remote (created by WormholeService)
local WormholeWarp = ReplicatedStorage:WaitForChild("WormholeWarp", 30)

-- ===== MENU GUI =====
local gui = Instance.new("ScreenGui")
gui.Name = "WormholeMenu"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 160; gui.Enabled = false
gui.Parent = PlayerGui

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"; backdrop.Size = UDim2.new(1, 0, 1, 0); backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.45; backdrop.AutoButtonColor = false; backdrop.Text = ""; backdrop.Active = true; backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.new(0.5, 0, 0.5, 0); panel.Size = UDim2.new(0.9, 0, 0, 470)
panel.BackgroundColor3 = PANEL; panel.BorderSizePixel = 0; panel.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 20); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = ACCENT; s.Thickness = 2; s.Transparency = 0.2; s.Parent = panel
	local sc = Instance.new("UISizeConstraint"); sc.MaxSize = Vector2.new(460, 470); sc.Parent = panel
end
local panelScale = Instance.new("UIScale"); panelScale.Scale = 0.7; panelScale.Parent = panel -- pop-in

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 56); titleBar.BackgroundColor3 = TITLE_BAR; titleBar.BorderSizePixel = 0; titleBar.Parent = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 20); c.Parent = titleBar
	local mask = Instance.new("Frame")
	mask.AnchorPoint = Vector2.new(0, 1); mask.Position = UDim2.new(0, 0, 1, 0); mask.Size = UDim2.new(1, 0, 0, 20)
	mask.BackgroundColor3 = TITLE_BAR; mask.BorderSizePixel = 0; mask.Parent = titleBar
end
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1; title.AnchorPoint = Vector2.new(0, 0.5); title.Position = UDim2.new(0, 16, 0.5, 0); title.Size = UDim2.new(1, -70, 1, -14)
title.Font = Enum.Font.FredokaOne; title.Text = "\u{1F300} WORMHOLE"; title.TextColor3 = WHITE; title.TextScaled = true; title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar
do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 26; cns.Parent = title
	local st = Instance.new("UIStroke"); st.Color = Color3.new(0, 0, 0); st.Thickness = 1.5; st.Transparency = 0.4; st.Parent = title end
local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5); closeBtn.Position = UDim2.new(1, -12, 0.5, 0); closeBtn.Size = UDim2.new(0, 36, 0, 36)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 70); closeBtn.Font = Enum.Font.FredokaOne; closeBtn.Text = "X"; closeBtn.TextColor3 = WHITE; closeBtn.TextScaled = true
closeBtn.Parent = titleBar
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = closeBtn end

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1; subtitle.AnchorPoint = Vector2.new(0.5, 0); subtitle.Position = UDim2.new(0.5, 0, 0, 62); subtitle.Size = UDim2.new(1, -32, 0, 22)
subtitle.Font = Enum.Font.GothamMedium; subtitle.Text = "Warp to an island you've already reached"; subtitle.TextColor3 = MUTED; subtitle.TextScaled = true
subtitle.Parent = panel
do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 16; cns.Parent = subtitle end

local scroll = Instance.new("ScrollingFrame")
scroll.AnchorPoint = Vector2.new(0.5, 0); scroll.Position = UDim2.new(0.5, 0, 0, 92); scroll.Size = UDim2.new(1, -24, 1, -104)
scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 6; scroll.ScrollBarImageColor3 = ACCENT
scroll.CanvasSize = UDim2.new(0, 0, 0, 0); scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; scroll.Parent = panel
do local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 8); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = scroll end

local warping = false
local closeMenu -- fwd
local warpTo    -- fwd

-- Build one row per island; returns a refresher.
local rowRefreshers = {}
for i, name in ipairs(ISLANDS) do
	local col = ISLAND_COLORS[i] or ACCENT
	local row = Instance.new("TextButton")
	row.Name = "Island" .. i; row.LayoutOrder = i; row.Size = UDim2.new(1, -6, 0, 50); row.AutoButtonColor = true; row.Text = ""
	row.BackgroundColor3 = PANEL_DEEP; row.Parent = scroll
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = row end
	local rowStroke = Instance.new("UIStroke"); rowStroke.Color = ACCENT; rowStroke.Thickness = 1.5; rowStroke.Transparency = 0.4; rowStroke.Parent = row

	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icon"; iconHolder.AnchorPoint = Vector2.new(0, 0.5); iconHolder.Position = UDim2.new(0, 11, 0.5, 0); iconHolder.Size = UDim2.new(0, 30, 0, 30)
	iconHolder.BackgroundTransparency = 1; iconHolder.Parent = row
	local disc = Instance.new("TextLabel")
	disc.AnchorPoint = Vector2.new(0.5, 0.5); disc.Position = UDim2.new(0.5, 0, 0.5, 0); disc.Size = UDim2.new(1, 0, 1, 0)
	disc.BackgroundColor3 = col; disc.Font = Enum.Font.FredokaOne; disc.Text = tostring(i); disc.TextColor3 = Color3.new(1, 1, 1); disc.TextScaled = true; disc.Parent = iconHolder
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = disc
		local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(10, 12, 24); s.Thickness = 1; s.Transparency = 0.2; s.Parent = disc
		local p = Instance.new("UIPadding"); p.PaddingTop = UDim.new(0, 4); p.PaddingBottom = UDim.new(0, 4); p.Parent = disc end
	local lockOverlay = Instance.new("Frame")
	lockOverlay.Name = "LockDim"; lockOverlay.AnchorPoint = Vector2.new(0.5, 0.5); lockOverlay.Position = UDim2.new(0.5, 0, 0.5, 0); lockOverlay.Size = UDim2.new(1, 0, 1, 0)
	lockOverlay.BackgroundColor3 = Color3.fromRGB(54, 58, 74); lockOverlay.BackgroundTransparency = 0.12; lockOverlay.BorderSizePixel = 0; lockOverlay.ZIndex = 6; lockOverlay.Visible = false; lockOverlay.Parent = iconHolder
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = lockOverlay end

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1; nameLbl.AnchorPoint = Vector2.new(0, 0.5); nameLbl.Position = UDim2.new(0, 50, 0.5, 0); nameLbl.Size = UDim2.new(0.5, 0, 1, -12)
	nameLbl.Font = Enum.Font.FredokaOne; nameLbl.Text = name; nameLbl.TextColor3 = WHITE; nameLbl.TextScaled = true; nameLbl.TextXAlignment = Enum.TextXAlignment.Left; nameLbl.Parent = row
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 22; cns.Parent = nameLbl end

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Name = "Status"; statusLbl.BackgroundTransparency = 1; statusLbl.AnchorPoint = Vector2.new(1, 0.5); statusLbl.Position = UDim2.new(1, -14, 0.5, 0); statusLbl.Size = UDim2.new(0.5, -10, 1, -14)
	statusLbl.Font = Enum.Font.GothamBold; statusLbl.Text = ""; statusLbl.TextColor3 = MUTED; statusLbl.TextScaled = true; statusLbl.TextXAlignment = Enum.TextXAlignment.Right; statusLbl.Parent = row
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 15; cns.Parent = statusLbl end

	row.Activated:Connect(function()
		if warping then return end
		if i > highestIsland() then return end
		if currentIsland() == i then return end
		if warpTo then warpTo(i, name) end
	end)

	rowRefreshers[i] = function()
		local reached = i <= highestIsland()
		local here = currentIsland() == i
		if reached then
			row.BackgroundColor3 = PANEL_DEEP; rowStroke.Color = col; rowStroke.Transparency = 0.25; lockOverlay.Visible = false; nameLbl.TextColor3 = WHITE
			statusLbl.Text = here and "Here" or "Warp \u{27A4}"
			statusLbl.TextColor3 = here and MUTED or col
			row.Active = true; row.AutoButtonColor = not here
		else
			row.BackgroundColor3 = LOCK_GREY; rowStroke.Color = Color3.fromRGB(70, 74, 92); rowStroke.Transparency = 0.5; lockOverlay.Visible = true; nameLbl.TextColor3 = MUTED
			statusLbl.Text = "\u{1F512} Reach it first"; statusLbl.TextColor3 = MUTED
			row.Active = false; row.AutoButtonColor = false
		end
	end
end

--======================================================================
-- OPEN / CLOSE / WARP
--======================================================================
local isOpen = false
local function refreshMenu() for _, fn in pairs(rowRefreshers) do fn() end end
local function openMenu()
	if warping or isOpen then return end
	isOpen = true
	refreshMenu()
	gui.Enabled = true
	panelScale.Scale = 0.7
	pcall(function() TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play() end)
	if _G.MainMenuManager and _G.MainMenuManager.notifyOpened then _G.MainMenuManager.notifyOpened("Wormhole") end
end
closeMenu = function()
	if not isOpen then return end
	isOpen = false
	gui.Enabled = false
	if _G.MainMenuManager and _G.MainMenuManager.notifyClosed then _G.MainMenuManager.notifyClosed("Wormhole") end
end
if _G.MainMenuManager and _G.MainMenuManager.register then _G.MainMenuManager.register("Wormhole", function() gui.Enabled = false; isOpen = false end) end
_G.toggleWormhole = function() if isOpen then closeMenu() else openMenu() end end

-- "land first" toast (own ScreenGui so it shows over the closed menu)
local landToastGui = Instance.new("ScreenGui"); landToastGui.Name = "WormholeLandFirst"; landToastGui.ResetOnSpawn = false; landToastGui.IgnoreGuiInset = true; landToastGui.DisplayOrder = 9500; landToastGui.Enabled = false; landToastGui.Parent = PlayerGui
local landToast = Instance.new("TextLabel"); landToast.AnchorPoint = Vector2.new(0.5, 0); landToast.Position = UDim2.new(0.5, 0, 0, 90); landToast.Size = UDim2.new(0, 470, 0, 52)
landToast.BackgroundColor3 = Color3.fromRGB(14, 20, 44); landToast.BackgroundTransparency = 0.05; landToast.Font = Enum.Font.FredokaOne; landToast.Text = "\u{1FA90}  Land on an island to use the wormhole!"; landToast.TextColor3 = Color3.fromRGB(210, 226, 255); landToast.TextScaled = true; landToast.Parent = landToastGui
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = landToast
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(90, 150, 255); s.Thickness = 2; s.Parent = landToast
	local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 22; cns.Parent = landToast end
local landTok = 0
local function showLandFirst() landTok += 1; local mine = landTok; landToastGui.Enabled = true; task.delay(2.6, function() if landTok == mine then landToastGui.Enabled = false end end) end

warpTo = function(islandNum, islandName)
	if warping then return end
	if islandNum > highestIsland() then return end     -- locked; guard
	if not isGrounded() then closeMenu(); showLandFirst(); return end
	warping = true
	closeMenu()
	WarpEffect.playSound() -- warp whoosh (the new file's sound), fired as the warp begins
	WarpEffect.play(function()
		pcall(function() WormholeWarp:InvokeServer(islandNum) end) -- server re-validates reached-island + grounded, then places you
	end)
	warping = false
end

closeBtn.Activated:Connect(closeMenu)
-- NOTE: there is deliberately NO click-outside-to-close handler (matching the Pet Hub). The backdrop spans
-- the whole screen, so a click anywhere off the panel used to slam it shut, which made menus feel like they
-- closed at random. This panel now closes ONLY on an explicit action: its X button, its own toggle, or
-- MainMenuManager closing it because another menu opened.
-- OpenWormhole BindableEvent (fired by the WORMHOLE side button in CoreClient)
do
	local sig = ReplicatedStorage:FindFirstChild("OpenWormhole")
	if not sig then sig = Instance.new("BindableEvent"); sig.Name = "OpenWormhole"; sig.Parent = ReplicatedStorage end
	sig.Event:Connect(openMenu)
end
player:GetAttributeChangedSignal("HighestIsland"):Connect(function() if isOpen then refreshMenu() end end)

print("[Wormhole][client] online -- island travel menu + shared WarpEffect cinematic (opens from the WORMHOLE side button)")
