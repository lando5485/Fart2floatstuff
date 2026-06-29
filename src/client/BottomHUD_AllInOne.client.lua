--======================================================================
-- BottomHUD_AllInOne.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of the BOTTOM-CENTER HUD STACK from CoreClient --
-- the three elements at the bottom of the screen, with their EXACT sizes,
-- colors, fonts, and placement copied verbatim:
--
--   LayoutOrder 1 (TOP):    STOMACH / GUT PILL  -- pink pill, gut emoji + name
--   LayoutOrder 2 (MIDDLE): GAS METER           -- blue box, gold title + green fuel bar + %
--   LayoutOrder 3 (BOTTOM): FART BUTTON         -- green "HOLD TO FART!" button
--
-- HOW THE PLACEMENT WORKS: all three live in ONE container ("BottomStack")
-- anchored bottom-center (AnchorPoint 0.5,1 at Position 0.5,1,-12). A vertical
-- UIListLayout (HorizontalAlignment Center, VerticalAlignment Bottom, Padding 8)
-- stacks them sharing the EXACT same center, so they never drift apart. The
-- container AutomaticSize=Y so it hugs the three. ScreenGui IgnoreGuiInset=true,
-- DisplayOrder 5 (above the world, below menus at 100).
--
-- This is COSMETIC/visual only (no flight wiring). Drop into StarterPlayer >
-- StarterPlayerScripts (or sync via Rojo) and the stack appears bottom-center.
--======================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- scale: phones use 0.7, PC 1.0 (same as CoreClient). Text sizes multiply by this.
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local scale    = isMobile and 0.7 or 1.0

-- ===== GUI HELPERS (verbatim from CoreClient) =====
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

-- ===== GUT ASSETS (verbatim) -- per-tier emoji on the pill; XL Gut uses an image instead =====
local GUT_EMOJI = {
	["Tiny Gut"]     = "\xF0\x9F\x91\xB6",             -- 👶 baby (tiny tummy)
	["Small Gut"]    = "\xF0\x9F\x90\xB9",             -- 🐹 hamster
	["Medium Gut"]   = "\xF0\x9F\x90\xB7",             -- 🐷 pig
	["Large Gut"]    = "\xF0\x9F\x90\x98",             -- 🐘 elephant
	["XL Gut"]       = "\xF0\x9F\xA6\x9B",             -- 🦛 hippo (XL shows GUT_IMAGE; this is the fallback)
	["Iron Gut"]     = "\xF0\x9F\x8F\x8B\xEF\xB8\x8F", -- 🏋️ weightlifter
	["Infinite Gut"] = "\xF0\x9F\x90\x8B",             -- 🐋 whale
}
local GUT_IMAGE = "rbxassetid://108585083746103" -- stomach/gut icon image (used by the XL Gut tier)
local stomachName = "Tiny Gut" -- the current gut tier (drives the pill icon + name)

-- ============================================================================
-- BOTTOM-CENTER STACK CONTAINER -- the three elements all parent into this.
-- ============================================================================
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

local gui = {} -- holds the built elements (mirrors CoreClient's _G.gui usage)

-- ============================================================================
-- (1) STOMACH / GUT PILL  (LayoutOrder 1 = TOP of the stack) -- VERBATIM
-- A pink pill (220,80,180) 300x40, gut EMOJI on the left + gut NAME centered.
-- ============================================================================
local stomachHud = Instance.new("Frame"); stomachHud.Name = "StomachHud"
stomachHud.Size = UDim2.new(0,300,0,40); stomachHud.LayoutOrder = 1; stomachHud.ZIndex = 10 -- top of the bottom-center stack (the pill), centered above the meter
stomachHud.BackgroundColor3 = Color3.fromRGB(220,80,180); stomachHud.BorderSizePixel = 0; stomachHud.Parent = bottomStack
mkCorner(stomachHud,20); mkStroke(stomachHud,Color3.fromRGB(140,20,100),3)
-- per-tier gut EMOJI on the LEFT of the pill
local stomachHudIcon = Instance.new("TextLabel"); stomachHudIcon.Name = "GutIcon"
stomachHudIcon.BackgroundTransparency = 1; stomachHudIcon.Text = (GUT_EMOJI[stomachName] or ""); stomachHudIcon.Font = Enum.Font.GothamBold; stomachHudIcon.TextScaled = true
stomachHudIcon.Size = UDim2.new(0,32,0,32); stomachHudIcon.Position = UDim2.new(0,6,0.5,0); stomachHudIcon.AnchorPoint = Vector2.new(0,0.5)
stomachHudIcon.ZIndex = 12; stomachHudIcon.Parent = stomachHud
-- XL Gut shows an IMAGE in the SAME icon slot (emoji blanked then); all other tiers use the emoji.
local stomachHudIconImg = Instance.new("ImageLabel"); stomachHudIconImg.Name = "GutIconImg"
stomachHudIconImg.BackgroundTransparency = 1; stomachHudIconImg.Image = GUT_IMAGE; stomachHudIconImg.ScaleType = Enum.ScaleType.Fit
stomachHudIconImg.Size = UDim2.new(0,32,0,32); stomachHudIconImg.Position = UDim2.new(0,6,0.5,0); stomachHudIconImg.AnchorPoint = Vector2.new(0,0.5)
stomachHudIconImg.ZIndex = 12; stomachHudIconImg.Visible = false; stomachHudIconImg.Parent = stomachHud
-- gut NAME text, to the right of the icon
local stomachHudLabel = Instance.new("TextLabel"); stomachHudLabel.Name = "StomachHudLabel"
stomachHudLabel.Size = UDim2.new(1,-44,1,0); stomachHudLabel.Position = UDim2.new(0,40,0,0); stomachHudLabel.BackgroundTransparency = 1; stomachHudLabel.ZIndex = 11
stomachHudLabel.Text = "Stomach"; stomachHudLabel.Font = Enum.Font.FredokaOne
stomachHudLabel.TextScaled = true; stomachHudLabel.TextColor3 = Color3.fromRGB(255,255,255); stomachHudLabel.TextXAlignment = Enum.TextXAlignment.Center; stomachHudLabel.Parent = stomachHud
mkStroke(stomachHudLabel,Color3.fromRGB(0,0,0),2)
-- updateStomachDisplay: set the pill to the current gut tier (emoji vs XL image)
local function updateStomachDisplay()
	stomachHudLabel.Text = stomachName
	if stomachName == "XL Gut" then
		stomachHudIcon.Text = ""; stomachHudIconImg.Visible = true
	else
		stomachHudIcon.Text = GUT_EMOJI[stomachName] or stomachHudIcon.Text; stomachHudIconImg.Visible = false
	end
end
updateStomachDisplay()

-- ============================================================================
-- (2) GAS METER  (LayoutOrder 2 = MIDDLE) -- VERBATIM
-- A blue box (45,120,220) 480x85, gold "GAS METER" title, a green fuel bar
-- (gasBg track holds the green Fill child) + a centered % readout.
-- ============================================================================
gui.gasMeterPanel = mkFrame(bottomStack,{Size=UDim2.new(0,480,0,85),LayoutOrder=2,BackgroundColor3=Color3.fromRGB(45,120,220)}) -- solid BLUE container
mkCorner(gui.gasMeterPanel,16); local gmStroke0 = mkStroke(gui.gasMeterPanel,Color3.fromRGB(20,65,165),4); gmStroke0.Enabled = false -- dark-navy outline stays DISABLED
do
	gui.gasTitleLabel = mkLabel(gui.gasMeterPanel,{Text="GAS METER",Font=Enum.Font.FredokaOne,TextSize=math.floor(17*scale),TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,0,0,math.floor(28*scale)),Position=UDim2.new(0,0,0,math.floor(6*scale)),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	mkStroke(gui.gasTitleLabel,Color3.fromRGB(0,0,0),2)
	gui.gasBg = mkFrame(gui.gasMeterPanel,{Size=UDim2.new(1,-20,1,-(math.floor(34*scale)+8)),Position=UDim2.new(0,10,0,math.floor(34*scale)),BackgroundColor3=Color3.fromRGB(18,28,66),BackgroundTransparency=1}) -- the bar TRACK (transparent so empty shows the blue container)
	mkCorner(gui.gasBg,17)
	gui.gasFill = mkFrame(gui.gasBg,{Name="Fill",Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.fromRGB(60,210,90),ZIndex=2})
	mkCorner(gui.gasFill,17)
	gui.gasGradient = Instance.new("UIGradient"); gui.gasGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(130,240,120)),ColorSequenceKeypoint.new(1,Color3.fromRGB(45,190,70))}); gui.gasGradient.Rotation = 90; gui.gasGradient.Parent = gui.gasFill
	gui.gasPowerText = mkLabel(gui.gasBg,{Size=UDim2.new(1,0,1,0),Text="100%",Font=Enum.Font.FredokaOne,TextSize=math.floor(18*scale),TextColor3=Color3.fromRGB(255,255,255),ZIndex=3,TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(gui.gasPowerText,Color3.fromRGB(0,0,0),2)
end

-- tightenGasMeter (VERBATIM): puts the bar right under the label (2px gap), fixed 40px bar height,
-- and shrinks the blue container to hug the content -> no empty blue strip.
local function tightenGasMeter()
	local panel, label, bg = gui.gasMeterPanel, gui.gasTitleLabel, gui.gasBg
	if not (panel and label and bg) then return end
	local pad = label.Position.Y.Offset
	local barTop = pad + label.Size.Y.Offset + 2
	local barH = 40
	bg.Position = UDim2.new(0, 10, 0, barTop)
	bg.Size = UDim2.new(1, -20, 0, barH)
	panel.Size = UDim2.new(0, 480, 0, barTop + barH + pad)
end
tightenGasMeter()

-- setGas(pct): drive the green fill + % (the flight loop does this live in-game). 0..100.
local function setGas(pct)
	pct = math.clamp(pct, 0, 100)
	gui.gasFill.Size = UDim2.new(pct/100, 0, 1, 0)
	gui.gasPowerText.Text = math.floor(pct) .. "%"
end
setGas(72) -- demo fill so the meter reads as a fuel bar (in-game this tracks gasMeter)

-- ============================================================================
-- (3) FART BUTTON  (LayoutOrder 3 = BOTTOM) -- VERBATIM
-- A green button (50,180,50) 480x62: a cloud emoji on the left + "HOLD TO FART!".
-- ============================================================================
gui.fartBtnFrame = mkFrame(bottomStack,{Size=UDim2.new(0,480,0,62),LayoutOrder=3,BackgroundColor3=Color3.fromRGB(50,180,50)})
mkCorner(gui.fartBtnFrame,14); mkStroke(gui.fartBtnFrame,Color3.fromRGB(0,120,0),4)
gui.fartBtnGradient = Instance.new("UIGradient"); gui.fartBtnGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(100,220,60)),ColorSequenceKeypoint.new(1,Color3.fromRGB(40,160,20))}); gui.fartBtnGradient.Rotation = 90; gui.fartBtnGradient.Parent = gui.fartBtnFrame
gui.fartCloudLabel = mkLabel(gui.fartBtnFrame,{Text="\xe2\x98\x81",Font=Enum.Font.GothamBold,TextSize=math.floor(28*scale),TextColor3=Color3.fromRGB(255,255,255),Size=UDim2.new(0,55,1,0),Position=UDim2.new(0,12,0,0),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1,ZIndex=3,RichText=false})
gui.fartBtn = mkButton(gui.fartBtnFrame,{Size=UDim2.new(1,-70,1,0),Position=UDim2.new(0,60,0,0),BackgroundTransparency=1,Text="HOLD TO FART!",Font=Enum.Font.GothamBold,TextSize=math.floor(22*scale),TextColor3=Color3.fromRGB(255,255,255),ZIndex=3,TextXAlignment=Enum.TextXAlignment.Left})
mkStroke(gui.fartBtn,Color3.fromRGB(0,80,0),2)

-- COSMETIC state toggle so you can see both looks (in-game the flight loop sets these):
--   idle  -> green "TAP TO FART!"     farting -> green "FARTING! (TAP TO STOP)"
--   no food -> grey "BUY FOOD FIRST!" (Active=false)
local farting = false
gui.fartBtn.Activated:Connect(function()
	farting = not farting
	if farting then
		gui.fartBtnFrame.BackgroundColor3 = Color3.fromRGB(80,210,80)
		gui.fartBtnGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(80,210,80)),ColorSequenceKeypoint.new(1,Color3.fromRGB(60,180,60))})
		gui.fartBtn.Text = "FARTING! (TAP TO STOP)"
	else
		gui.fartBtnFrame.BackgroundColor3 = Color3.fromRGB(80,210,80)
		gui.fartBtnGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(80,210,80)),ColorSequenceKeypoint.new(1,Color3.fromRGB(60,180,60))})
		gui.fartBtn.Text = "TAP TO FART!"
	end
end)

print("[BottomHUD] stomach pill + gas meter + fart button stacked bottom-center")
