--======================================================================
-- JustButtons_AllInOne.client.lua  (LocalScript)
--======================================================================
-- COSMETIC-ONLY copy of just the BUTTONS, using the ACTUAL FINAL in-game
-- look -- i.e. the values AFTER CoreClient's restyle + repositionGUIs passes
-- run (NOT the initial mkSideBtn values, which the game overwrites at load).
-- No menus, no clicks, no sounds inside -- just what you see on screen.
--
--   LEFT RAIL (SidebarGui): 4 buttons, 95x95, top-left x=12, y 96/203/310/417
--       SHOP (green) / WORMHOLE (purple) / Stomach (green) / MORE (pink)
--   BOTTOM STACK (BottomStackGui): Stomach pill / Gas meter / Fart button
--
-- Values below are the DESKTOP (scale 1.0) final grid. On mobile the game
-- recomputes the rail pitch from a live UIScale; this copy uses the desktop grid.
--======================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local scale = 1.0 -- desktop grid (matches the authored y96/203/310/417 rail)

-- ===== helpers (verbatim from CoreClient) =====
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local GUT_IMAGE = "rbxassetid://108585083746103" -- stomach/gut icon image

--======================================================================
-- LEFT RAIL -- 4 buttons, FINAL look: 95x95, top-left x=12, fixed Y grid.
--   frames order (from repositionGUIs): SHOP, WORMHOLE, Stomach, MORE
--   Y grid (desktop): 96, 203, 310, 417   (107px pitch)
--======================================================================
local sidebarGui = Instance.new("ScreenGui")
sidebarGui.Name = "SidebarGui"; sidebarGui.ResetOnSpawn = false; sidebarGui.Parent = PlayerGui

-- makes a 95x95 rail button with the FINAL bg/corner/stroke from the restyle pass
local function mkRailBtn(y, bgCol, corner, strokeCol, strokeW, iconTxt, labelTxt)
	local btn = mkFrame(sidebarGui,{
		Size=UDim2.new(0,95,0,95), AnchorPoint=Vector2.new(0,0),
		Position=UDim2.new(0,12,0,y), BackgroundColor3=bgCol,
	})
	mkCorner(btn, corner); mkStroke(btn, strokeCol, strokeW)
	local iconL=mkLabel(btn,{Text=iconTxt,Font=Enum.Font.Gotham,TextSize=math.floor(30*scale),Size=UDim2.new(1,0,0,56),Position=UDim2.new(0,0,0,0),RichText=true,TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(iconL,Color3.new(0,0,0),1)
	local textL=mkLabel(btn,{Name="Label",Text=labelTxt,Font=Enum.Font.GothamBold,TextSize=math.floor(12*scale),TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,28),Position=UDim2.new(0,0,0,57),TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(textL,Color3.new(0,0,0),1)
	return btn
end

-- 1) SHOP     -- bright green 50,220,50, corner 16, stroke 30,120,30 w3
mkRailBtn(96,  Color3.fromRGB(50,220,50),  16, Color3.fromRGB(30,120,30), 3, "\xF0\x9F\x9b\x92", "SHOP")
-- 2) WORMHOLE -- purple 140,86,226, corner 16, stroke 90,40,160 w3
mkRailBtn(203, Color3.fromRGB(140,86,226), 16, Color3.fromRGB(90,40,160), 3, "\xF0\x9F\x8C\x80", "WORMHOLE")
-- 3) Stomach  -- green 80,170,70, corner 16, stroke 40,110,40 w3; icon is the GUT_IMAGE
local stomachSide = mkRailBtn(310, Color3.fromRGB(80,170,70), 16, Color3.fromRGB(40,110,40), 3, "", "Stomach")
do
	local gutIcon=Instance.new("ImageLabel")
	gutIcon.Name="Icon"; gutIcon.BackgroundTransparency=1; gutIcon.Image=GUT_IMAGE; gutIcon.ScaleType=Enum.ScaleType.Fit
	gutIcon.Size=UDim2.new(0,math.floor(40*scale),0,math.floor(40*scale)); gutIcon.Position=UDim2.new(0.5,0,0,6); gutIcon.AnchorPoint=Vector2.new(0.5,0)
	gutIcon.ZIndex=3; gutIcon.Parent=stomachSide
end
-- 4) MORE     -- pink 225,70,170; NOTE: the restyle never touches MORE, so it keeps
--    the ORIGINAL corner 14 + WHITE stroke w2 (only its size/pos are set to the 95 grid)
mkRailBtn(417, Color3.fromRGB(225,70,170), 14, Color3.new(1,1,1), 2, "+", "MORE")

--======================================================================
-- BOTTOM STACK -- pill / gas meter / fart button, bottom-center.
-- Positions owned by a UIListLayout; colors are the FINAL restyled values.
--======================================================================
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

-- (1) STOMACH / GUT PILL -- 300x40 pink (never restyled), corner 20, stroke 140,20,100 w3
local stomachHud = mkFrame(bottomStack,{Name="StomachHud",Size=UDim2.new(0,300,0,40),LayoutOrder=1,BackgroundColor3=Color3.fromRGB(220,80,180),BorderSizePixel=0,ZIndex=10})
mkCorner(stomachHud,20); mkStroke(stomachHud,Color3.fromRGB(140,20,100),3)
do
	local ic=Instance.new("TextLabel"); ic.Name="GutIcon"; ic.BackgroundTransparency=1; ic.Text="\xF0\x9F\x91\xB6"; ic.Font=Enum.Font.GothamBold; ic.TextScaled=true
	ic.Size=UDim2.new(0,32,0,32); ic.Position=UDim2.new(0,6,0.5,0); ic.AnchorPoint=Vector2.new(0,0.5); ic.ZIndex=12; ic.Parent=stomachHud
	local lb=mkLabel(stomachHud,{Name="StomachHudLabel",Size=UDim2.new(1,-44,1,0),Position=UDim2.new(0,40,0,0),ZIndex=11,Text="Stomach",Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(255,255,255),TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(lb,Color3.fromRGB(0,0,0),2)
end

-- (2) GAS METER -- 480 wide, FINAL: container 20,140,255 corner 16 stroke 20,40,120 w3,
--     title 255,255,100, bar bg 20,20,80 corner 12, fill green corner 12
local gasPanel = mkFrame(bottomStack,{Size=UDim2.new(0,480,0,85),LayoutOrder=2,BackgroundColor3=Color3.fromRGB(20,140,255)})
mkCorner(gasPanel,16); mkStroke(gasPanel,Color3.fromRGB(20,40,120),3)
do
	local title=mkLabel(gasPanel,{Text="GAS METER",Font=Enum.Font.FredokaOne,TextSize=math.floor(17*scale),TextColor3=Color3.fromRGB(255,255,100),Size=UDim2.new(1,0,0,math.floor(28*scale)),Position=UDim2.new(0,0,0,math.floor(6*scale)),TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(title,Color3.fromRGB(0,0,0),2)
	local barTop = math.floor(6*scale) + math.floor(28*scale) + 2
	local bg=mkFrame(gasPanel,{Name="gasBg",Size=UDim2.new(1,-20,0,40),Position=UDim2.new(0,10,0,barTop),BackgroundColor3=Color3.fromRGB(20,20,80)})
	mkCorner(bg,12)
	local fill=mkFrame(bg,{Name="Fill",Size=UDim2.new(0.72,0,1,0),BackgroundColor3=Color3.fromRGB(60,210,90),ZIndex=2}) -- 72% demo fill, flat green (flattenGasGradient final look)
	mkCorner(fill,12)
	local pct=mkLabel(bg,{Size=UDim2.new(1,0,1,0),Text="72%",Font=Enum.Font.FredokaOne,TextSize=math.floor(18*scale),TextColor3=Color3.fromRGB(255,255,255),ZIndex=3,TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(pct,Color3.fromRGB(0,0,0),2)
	gasPanel.Size = UDim2.new(0,480,0, barTop + 40 + math.floor(6*scale)) -- tighten to hug content
end

-- (3) FART BUTTON -- 480x62, FINAL: bright green 50,220,50, corner 16, stroke 30,130,30 w4,
--     gradient 50,220,50 -> 30,190,30
local fartFrame = mkFrame(bottomStack,{Size=UDim2.new(0,480,0,62),LayoutOrder=3,BackgroundColor3=Color3.fromRGB(50,220,50)})
mkCorner(fartFrame,16); mkStroke(fartFrame,Color3.fromRGB(30,130,30),4)
do
	local grad=Instance.new("UIGradient"); grad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(50,220,50)),ColorSequenceKeypoint.new(1,Color3.fromRGB(30,190,30))}); grad.Rotation=90; grad.Parent=fartFrame
	mkLabel(fartFrame,{Text="\xe2\x98\x81",Font=Enum.Font.GothamBold,TextSize=math.floor(28*scale),TextColor3=Color3.fromRGB(255,255,255),Size=UDim2.new(0,55,1,0),Position=UDim2.new(0,12,0,0),TextXAlignment=Enum.TextXAlignment.Left,ZIndex=3,RichText=false})
	local txt=mkLabel(fartFrame,{Size=UDim2.new(1,-70,1,0),Position=UDim2.new(0,60,0,0),Text="HOLD TO FART!",Font=Enum.Font.GothamBold,TextSize=math.floor(22*scale),TextColor3=Color3.fromRGB(255,255,255),ZIndex=3,TextXAlignment=Enum.TextXAlignment.Left})
	mkStroke(txt,Color3.fromRGB(0,80,0),2)
end

print("[JustButtons] FINAL-look buttons built: SHOP/WORMHOLE/Stomach/MORE (95x95 rail) + pill/gas/fart")
