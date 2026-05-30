-- ===== FART TO FLOAT — STARTUP LOADING SCREEN =====
-- Runs from ReplicatedFirst so it appears INSTANTLY on join, before the game loads. Hides Roblox's
-- default loading screen, preloads game assets with a REAL per-batch progress bar, then shows a
-- PLAY button once everything is loaded. Clicking PLAY fades the screen out into the game.

print("LOADING SCREEN SCRIPT RUNNING") -- confirm in F9 that this LocalScript actually executes

local ReplicatedFirst    = game:GetService("ReplicatedFirst")
local ContentProvider    = game:GetService("ContentProvider")
local Players            = game:GetService("Players")
local TweenService       = game:GetService("TweenService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

-- Hide the default Roblox loading screen ASAP (before we yield on anything).
pcall(function() ReplicatedFirst:RemoveDefaultLoadingScreen() end)

-- ===== BACKGROUND MUSIC =====
-- OLD single-track background-music system REMOVED. Background music is now handled by the new
-- server-side shuffle system (MusicManager.server.lua, with client-side ducking in
-- MusicDucking.client.lua). This script no longer creates or plays any music, so the two systems
-- never run in parallel.

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== UI CLICK SOUND =====
-- Same click SFX (id + volume + clone-and-play) as every other button in the game (CoreClient's
-- _G.playUIClick). This script runs from ReplicatedFirst before CoreClient exists, so we set up our
-- own identical instance here for the PLAY button + island cards.
local UI_CLICK_VOLUME = 0.5
local uiClickSound = Instance.new("Sound")
uiClickSound.Name = "UIClickSound"
uiClickSound.SoundId = "rbxassetid://101638558691673"
uiClickSound.Volume = UI_CLICK_VOLUME
uiClickSound.Parent = playerGui
local function playUIClick()
	local s = uiClickSound:Clone()
	s.Parent = playerGui
	s:Play()
	game:GetService("Debris"):AddItem(s, 3)
end

-- ===== GUI =====
local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000        -- above everything else
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- CanvasGroup root so the whole screen can fade out uniformly via GroupTransparency.
local root = Instance.new("CanvasGroup")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(135, 206, 250)
root.BackgroundTransparency = 1 -- fully transparent: only the bg image + UI show, never grey/blue
root.BorderSizePixel = 0
root.GroupTransparency = 0
root.ZIndex = 1                 -- above the background image (ZIndex 0)
root.Parent = gui

-- Full-screen background IMAGE (FART TO FLOAT logo + character + sky baked in). Parented DIRECTLY to
-- the ScreenGui (NOT inside the CanvasGroup) so no parent buffer can letterbox it — it fills the raw
-- screen. ScaleType = Crop scales up + crops overflow => edge-to-edge on any aspect, no grey bars.
local bg = Instance.new("ImageLabel")
bg.Name = "Background"
bg.AnchorPoint = Vector2.new(0.5, 0.5)
bg.Position = UDim2.fromScale(0.5, 0.5)
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundTransparency = 1            -- no grey behind the image
bg.Image = "rbxassetid://127983055545494"
bg.ScaleType = Enum.ScaleType.Crop
bg.ZIndex = 0                            -- behind root (ZIndex 1) and all UI
bg.Parent = gui                          -- direct ScreenGui child, behind the UI CanvasGroup

-- Soft drop-shadow helper: a blurred 9-slice rounded shadow placed BEHIND `target` (as a sibling in
-- `parent`), expanded by `spread` px and nudged down so it reads as a soft shadow. Returns the shadow.
local SHADOW_IMG = "rbxassetid://1316045217" -- standard soft rounded shadow (9-slice)
local function makeShadow(target, parent, spread)
	local sh = Instance.new("ImageLabel")
	sh.Name = target.Name .. "Shadow"
	sh.BackgroundTransparency = 1
	sh.Image = SHADOW_IMG
	sh.ImageColor3 = Color3.fromRGB(0, 0, 0)
	sh.ImageTransparency = 0.5
	sh.ScaleType = Enum.ScaleType.Slice
	sh.SliceCenter = Rect.new(10, 10, 118, 118)
	sh.AnchorPoint = target.AnchorPoint
	sh.Size = UDim2.new(target.Size.X.Scale, target.Size.X.Offset + spread * 2, target.Size.Y.Scale, target.Size.Y.Offset + spread * 2)
	sh.Position = UDim2.new(target.Position.X.Scale, target.Position.X.Offset, target.Position.Y.Scale, target.Position.Y.Offset + 6)
	sh.ZIndex = math.max((target.ZIndex or 1) - 1, 0)
	sh.Parent = parent
	return sh
end

-- ===== PROGRESS BAR =====
-- Wrapper that holds the white track + green fill + the % pill (one Visible toggle hides them all).
local barWrap = Instance.new("Frame")
barWrap.Name = "BarWrap"
barWrap.AnchorPoint = Vector2.new(0.5, 0.5)
barWrap.Position = UDim2.fromScale(0.5, 0.64) -- lower-center, over the open sky (below the logo)
barWrap.Size = UDim2.fromScale(0.58, 0.06) -- viewport-relative so it adapts to any screen (was fixed 40px tall)
barWrap.BackgroundTransparency = 1
barWrap.ZIndex = 5
barWrap.Parent = root

local barShadow = makeShadow(barWrap, root, 14) -- soft shadow behind the whole bar

-- Outer container: WHITE, fully rounded. UIPadding insets the fill so the white reads as a border.
local barBg = Instance.new("Frame")
barBg.Name = "BarBg"
barBg.AnchorPoint = Vector2.new(0.5, 0.5)
barBg.Position = UDim2.fromScale(0.5, 0.5)
barBg.Size = UDim2.fromScale(1, 1)
barBg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
barBg.BorderSizePixel = 0
barBg.ZIndex = 6
local barBgCorner = Instance.new("UICorner"); barBgCorner.CornerRadius = UDim.new(1, 0); barBgCorner.Parent = barBg
local barPad = Instance.new("UIPadding")
barPad.PaddingLeft = UDim.new(0, 5); barPad.PaddingRight = UDim.new(0, 5)
barPad.PaddingTop = UDim.new(0, 5); barPad.PaddingBottom = UDim.new(0, 5)
barPad.Parent = barBg
barBg.Parent = barWrap

-- Inner fill: BRIGHT GREEN, fully rounded, grows left -> right. Diagonal light->bright green gradient
-- gives the lighter-green "stripe" sheen (gradient fallback, since a tiling stripe image isn't assured).
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.AnchorPoint = Vector2.new(0, 0.5)
fill.Position = UDim2.new(0, 0, 0.5, 0)
fill.Size = UDim2.new(0, 0, 1, 0)  -- 0% -> grows to 100%
fill.BackgroundColor3 = Color3.fromRGB(70, 215, 85)
fill.BorderSizePixel = 0
fill.ZIndex = 7
local fillCorner = Instance.new("UICorner"); fillCorner.CornerRadius = UDim.new(1, 0); fillCorner.Parent = fill
local fillGrad = Instance.new("UIGradient")
fillGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,   Color3.fromRGB(150, 245, 120)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 90)),
	ColorSequenceKeypoint.new(1,   Color3.fromRGB(45, 195, 65)),
})
fillGrad.Rotation = 25 -- diagonal sheen
fillGrad.Parent = fill
fill.Parent = barBg

-- Dark rounded % pill straddling the RIGHT END of the bar.
local pctPill = Instance.new("Frame")
pctPill.Name = "PctPill"
pctPill.AnchorPoint = Vector2.new(0.5, 0.5)
pctPill.Position = UDim2.fromScale(1, 0.5)
pctPill.Size = UDim2.new(0.1, 0, 1.55, 0) -- relative to the bar (10% of bar width), a touch taller than it
pctPill.BackgroundColor3 = Color3.fromRGB(22, 34, 70)
pctPill.BorderSizePixel = 0
pctPill.ZIndex = 9
local pillCorner = Instance.new("UICorner"); pillCorner.CornerRadius = UDim.new(1, 0); pillCorner.Parent = pctPill
local pillStroke = Instance.new("UIStroke"); pillStroke.Color = Color3.fromRGB(255, 255, 255); pillStroke.Thickness = 2; pillStroke.Parent = pctPill
local pctPillLabel = Instance.new("TextLabel")
pctPillLabel.Name = "Label"
pctPillLabel.AnchorPoint = Vector2.new(0.5, 0.5)
pctPillLabel.Position = UDim2.fromScale(0.5, 0.5)
pctPillLabel.Size = UDim2.fromScale(0.82, 0.6)
pctPillLabel.BackgroundTransparency = 1
pctPillLabel.Font = Enum.Font.FredokaOne
pctPillLabel.Text = "0%"
pctPillLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
pctPillLabel.TextScaled = true
pctPillLabel.ZIndex = 10
pctPillLabel.Parent = pctPill
pctPill.Parent = barWrap

-- ===== "<n>% LOADED" text (with 💥 on each side) =====
local loadedLabel = Instance.new("TextLabel")
loadedLabel.Name = "Loaded"
loadedLabel.AnchorPoint = Vector2.new(0.5, 0.5)
loadedLabel.Position = UDim2.fromScale(0.5, 0.72)
loadedLabel.Size = UDim2.fromScale(0.6, 0.07)
loadedLabel.BackgroundTransparency = 1
loadedLabel.Font = Enum.Font.FredokaOne
loadedLabel.Text = "\xF0\x9F\x92\xA5 0% LOADED \xF0\x9F\x92\xA5"
loadedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
loadedLabel.TextScaled = true
loadedLabel.ZIndex = 5
local loadedStroke = Instance.new("UIStroke"); loadedStroke.Color = Color3.fromRGB(0,0,0); loadedStroke.Thickness = 3; loadedStroke.Parent = loadedLabel
loadedLabel.Parent = root

-- ===== Rotating tip (blue) =====
local tipLabel = Instance.new("TextLabel")
tipLabel.Name = "Tip"
tipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
tipLabel.Position = UDim2.fromScale(0.5, 0.8)
tipLabel.Size = UDim2.fromScale(0.8, 0.045)
tipLabel.BackgroundTransparency = 1
tipLabel.Font = Enum.Font.FredokaOne
tipLabel.Text = ""
tipLabel.TextColor3 = Color3.fromRGB(45, 120, 255) -- bold blue
tipLabel.TextScaled = true
tipLabel.ZIndex = 5
local tipStroke = Instance.new("UIStroke"); tipStroke.Color = Color3.fromRGB(255,255,255); tipStroke.Thickness = 2; tipStroke.Parent = tipLabel
tipLabel.Parent = root

-- ===== PLAY button (hidden/disabled until 100%) =====
local PLAY_W, PLAY_H = 0.23, 0.12 -- base size as VIEWPORT FRACTIONS (responsive); hover/press scale around this
local playShadow -- soft shadow (created after the button so it can copy its footprint)
local playBtn = Instance.new("TextButton")
playBtn.Name = "PlayButton"
playBtn.AnchorPoint = Vector2.new(0.5, 0.5)
playBtn.Position = UDim2.fromScale(0.5, 0.88)
playBtn.Size = UDim2.fromScale(PLAY_W, PLAY_H)
playBtn.BackgroundColor3 = Color3.fromRGB(55, 205, 70)
playBtn.Text = "" -- text lives in a child label so it can have its own black outline
playBtn.AutoButtonColor = false
playBtn.Visible = false   -- revealed at 100%
playBtn.Active = false    -- not clickable until ready
playBtn.ZIndex = 8
local playCorner = Instance.new("UICorner"); playCorner.CornerRadius = UDim.new(1, 0); playCorner.Parent = playBtn -- fully rounded
local playAspect = Instance.new("UIAspectRatioConstraint") -- keep the pill shape (width:height) on any aspect ratio
playAspect.AspectRatio = 3.4; playAspect.DominantAxis = Enum.DominantAxis.Width; playAspect.Parent = playBtn
local playStroke = Instance.new("UIStroke") -- thick WHITE border around the button
playStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
playStroke.Color = Color3.fromRGB(255, 255, 255)
playStroke.Thickness = 5
playStroke.Parent = playBtn
local playLabel = Instance.new("TextLabel")
playLabel.Name = "Label"
playLabel.AnchorPoint = Vector2.new(0.5, 0.5)
playLabel.Position = UDim2.fromScale(0.5, 0.5)
playLabel.Size = UDim2.fromScale(0.8, 0.62)
playLabel.BackgroundTransparency = 1
playLabel.Font = Enum.Font.FredokaOne
playLabel.Text = "PLAY!"
playLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
playLabel.TextScaled = true
playLabel.ZIndex = 9
local playLabelStroke = Instance.new("UIStroke"); playLabelStroke.Color = Color3.fromRGB(0,0,0); playLabelStroke.Thickness = 3; playLabelStroke.Parent = playLabel
playLabel.Parent = playBtn
playBtn.Parent = root
playShadow = makeShadow(playBtn, root, 16); playShadow.Visible = false

-- ===== ROTATING TIPS =====
local TIPS = {
	"Bigger stomach = fly higher!",
	"Land on islands to save progress!",
	"Just TAP to fart!",
	"Skip Island to leap ahead!",
}
task.spawn(function()
	local i = 0
	while gui.Parent do
		i = (i % #TIPS) + 1
		tipLabel.Text = TIPS[i]
		task.wait(2.5)
	end
end)

-- ===== PROGRESS HELPER =====
-- Set directly (no tween) — the driver below calls this every frame, so the fill is already smooth.
local function setProgress(p)
	p = math.clamp(p, 0, 1)
	fill.Size = UDim2.new(p, 0, 1, 0)
	local pct = math.floor(p * 100)
	pctPillLabel.Text = pct .. "%"
	loadedLabel.Text = "\xF0\x9F\x92\xA5 " .. pct .. "% LOADED \xF0\x9F\x92\xA5"
end

-- ===== ISLAND-SELECT MENU (shown after PLAY) =====
local ISLAND_NAMES = {
	"Bean Farm","Broccoli Bluff","Cabbage Cliffs","Turnip Tranquil","Coconut Cove","Bread Board",
	"Pasta Peak","Popcorn Pinnacle","Milk Marsh","Butter Swamp","Ice Cream Isle","Burger Bluff",
	"Burrito Barrens","Pizza Palms",
}
local SelectIslandEvent = ReplicatedStorage:WaitForChild("SelectIslandEvent", 10)

-- Menu BACKGROUND image (title "SELECT YOUR ISLAND" + character + sky + hint are baked in — we do
-- NOT recreate them). Direct ScreenGui child (NOT inside the CanvasGroup) so Crop fills the whole
-- screen with no grey bars. Hidden until PLAY.
local menuBg = Instance.new("ImageLabel")
menuBg.Name = "MenuBackground"
menuBg.AnchorPoint = Vector2.new(0.5, 0.5)
menuBg.Position = UDim2.fromScale(0.5, 0.5)
menuBg.Size = UDim2.fromScale(1, 1)
menuBg.BackgroundTransparency = 1
menuBg.Image = "rbxassetid://111075648402081"
menuBg.ScaleType = Enum.ScaleType.Crop
menuBg.Visible = false
menuBg.ZIndex = 0
menuBg.Parent = gui

-- Container for the 14 island cards, in the open CENTER/RIGHT area (clear of the baked-in title up
-- top and the character on the left). Inside `root` so the cards sit above the bg and fade out.
local cards = Instance.new("Frame")
cards.Name = "IslandCards"
cards.AnchorPoint = Vector2.new(0.5, 0.5)
cards.Position = UDim2.fromScale(0.62, 0.58)
cards.Size = UDim2.fromScale(0.7, 0.52)
cards.BackgroundTransparency = 1
cards.Visible = false
cards.ZIndex = 11
cards.Parent = root
local grid = Instance.new("UIGridLayout")
grid.FillDirectionMaxCells = 7                 -- exactly 7 per row -> two rows of 7
grid.CellSize = UDim2.fromScale(0.13, 0.46)
grid.CellPadding = UDim2.fromScale(0.008, 0.05)
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.VerticalAlignment = Enum.VerticalAlignment.Center
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = cards

local choiceMade = false
local function chooseIsland(n)
	if choiceMade then return end
	choiceMade = true
	if SelectIslandEvent then SelectIslandEvent:FireServer(n) end
	print("ISLAND MENU: selected island " .. n)
	-- Fade the whole screen out into the game; the server teleports + releases the hold meanwhile.
	TweenService:Create(root, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {GroupTransparency = 1}):Play()
	TweenService:Create(bg, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {ImageTransparency = 1}):Play()       -- loading bg (outside CanvasGroup)
	TweenService:Create(menuBg, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {ImageTransparency = 1}):Play()   -- menu bg (outside CanvasGroup)
	task.delay(0.5, function() gui:Destroy() end)
end

-- 14 island cards (created once; lock state + text/colour applied in showMenu). Each card = a
-- rounded TextButton with a big NUMBER (or gold lock) on top and the NAME (or "Island N") under it.
-- FredokaOne, white text + black outline.
local islandCards = {}
for n = 1, 14 do
	local card = Instance.new("TextButton")
	card.Name = "Island" .. n
	card.LayoutOrder = n
	card.Text = ""
	card.BorderSizePixel = 0
	card.AutoButtonColor = true
	card.ZIndex = 12
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = card
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(0, 0, 0); s.Thickness = 2.5; s.Parent = card

	local top = Instance.new("TextLabel")
	top.Name = "Top"
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.fromScale(0.5, 0.05)
	top.Size = UDim2.fromScale(0.9, 0.52)
	top.BackgroundTransparency = 1
	top.Font = Enum.Font.FredokaOne
	top.TextColor3 = Color3.fromRGB(255, 255, 255)
	top.TextScaled = true
	top.ZIndex = 13
	local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(0, 0, 0); ts.Thickness = 2; ts.Parent = top
	top.Parent = card

	local bottom = Instance.new("TextLabel")
	bottom.Name = "Bottom"
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.Position = UDim2.fromScale(0.5, 0.95)
	bottom.Size = UDim2.fromScale(0.94, 0.4)
	bottom.BackgroundTransparency = 1
	bottom.Font = Enum.Font.FredokaOne
	bottom.TextColor3 = Color3.fromRGB(255, 255, 255)
	bottom.TextScaled = true
	bottom.TextWrapped = true
	bottom.ZIndex = 13
	local bs = Instance.new("UIStroke"); bs.Color = Color3.fromRGB(0, 0, 0); bs.Thickness = 1.5; bs.Parent = bottom
	bottom.Parent = card

	card.Parent = cards
	card.Activated:Connect(function()
		if card.Active then playUIClick() end -- click SFX only for unlocked (clickable) cards, never locked ones
		chooseIsland(n)
	end)
	islandCards[n] = { card = card, top = top, bottom = bottom }
end

local function showMenu()
	-- Highest reached island comes from the server (set on data load), so locks reflect saved progress.
	local highest = player:GetAttribute("HighestIsland")
	local waited = 0
	while not highest and waited < 5 do task.wait(0.1); waited = waited + 0.1; highest = player:GetAttribute("HighestIsland") end
	highest = highest or 1
	for n = 1, 14 do
		local e = islandCards[n]
		if n <= highest then
			-- UNLOCKED: green, clickable, big number + island name.
			e.card.Active = true; e.card.AutoButtonColor = true
			e.card.BackgroundColor3 = Color3.fromRGB(45, 175, 75)
			e.top.Text = tostring(n); e.top.TextColor3 = Color3.fromRGB(255, 255, 255)
			e.bottom.Text = ISLAND_NAMES[n]
		else
			-- LOCKED: dark navy, gold lock + "Island N", not clickable.
			e.card.Active = false; e.card.AutoButtonColor = false
			e.card.BackgroundColor3 = Color3.fromRGB(18, 28, 66)
			e.top.Text = "\xF0\x9F\x94\x92"; e.top.TextColor3 = Color3.fromRGB(255, 205, 70) -- 🔒 gold
			e.bottom.Text = "Island " .. n
		end
	end
	-- Swap the loading visuals for the menu.
	bg.Visible = false
	barWrap.Visible = false; barShadow.Visible = false
	loadedLabel.Visible = false; tipLabel.Visible = false
	playBtn.Visible = false; playShadow.Visible = false
	menuBg.Visible = true
	cards.Visible = true
end

-- ===== READY / PLAY =====
local function scalePlay(mult, dur)
	TweenService:Create(playBtn, TweenInfo.new(dur or 0.12, Enum.EasingStyle.Quad),
		{Size = UDim2.fromScale(PLAY_W * mult, PLAY_H * mult)}):Play()
end

local function revealPlay()
	setProgress(1)
	playShadow.Visible = true
	playBtn.Visible = true
	playBtn.Active = true
	-- pop-in from small
	playBtn.Size = UDim2.fromScale(PLAY_W * 0.7, PLAY_H * 0.7)
	scalePlay(1, 0.4)
end

-- Small hover/press scale (hover fires on PC; press works on PC + mobile).
playBtn.MouseEnter:Connect(function() if playBtn.Active then scalePlay(1.06) end end)
playBtn.MouseLeave:Connect(function() if playBtn.Active then scalePlay(1) end end)
playBtn.MouseButton1Down:Connect(function() if playBtn.Active then scalePlay(0.95) end end)
playBtn.MouseButton1Up:Connect(function() if playBtn.Active then scalePlay(1.06) end end)

playBtn.Activated:Connect(function()
	playUIClick()
	playBtn.Active = false
	showMenu() -- PLAY now opens the island-select menu (picking one spawns + releases the player)
end)

-- ===== TIMING + PRELOAD =====
-- The bar always takes a MINIMUM of 8s to fill (smooth, steady). PLAY appears only once BOTH
-- (a) 8s have elapsed AND (b) the real asset preload + game.Loaded are done — whichever is later.
-- So fast devices get a clean 8s fill -> PLAY; slow devices hold just shy of 100% until really loaded.
local FILL_SECONDS = 8
local assetsReady = false

-- REAL preload runs underneath; it only flips `assetsReady` when finished (it no longer drives the bar).
task.spawn(function()
	if not game:IsLoaded() then game.Loaded:Wait() end
	-- Gather everything now that the place has replicated, then preload in batches (PreloadAsync
	-- ignores instances with no content, so this is safe).
	local assets = game:GetDescendants()
	local total = #assets
	local BATCH = 50
	local i = 0
	local loadStart = os.clock()
	while i < total do
		local batch = {}
		for _ = 1, BATCH do
			i = i + 1
			if i > total then break end
			batch[#batch + 1] = assets[i]
		end
		-- pcall so a broken/unapproved asset (e.g. bad sound id) can't error out the loader.
		pcall(function() ContentProvider:PreloadAsync(batch) end)
		-- 15s safety timeout: failing assets can stall PreloadAsync, so never block the player forever.
		if os.clock() - loadStart > 15 then
			print("LOADING: 15s safety timeout reached, proceeding")
			break
		end
	end
	print("LOADING: preloaded " .. total .. " assets, ready")
	assetsReady = true
end)

-- DRIVER: smooth time-based fill. The % counts up in sync. The bar is held just below 100% until the
-- real load is done, then snaps to 100% and PLAY is revealed.
task.spawn(function()
	local startT = os.clock()
	while true do
		local timeP = math.min((os.clock() - startT) / FILL_SECONDS, 1)
		setProgress(assetsReady and timeP or math.min(timeP, 0.95))
		if assetsReady and timeP >= 1 then break end
		task.wait()
	end
	setProgress(1)
	revealPlay()
end)
