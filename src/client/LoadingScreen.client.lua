-- ===== FART TO FLOAT — STARTUP LOADING SCREEN =====
-- Runs from ReplicatedFirst so it appears INSTANTLY on join, before the game loads. Hides Roblox's
-- default loading screen, preloads game assets with a REAL per-batch progress bar, then shows a
-- PLAY button once everything is loaded. Clicking PLAY fades the screen out into the game.

print("[LOADINGSCREEN] GATED-BUILD v2 running - this is the synced Rojo copy") -- [DIAG] if this does NOT appear in F9, the synced src is not the script that's running
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

-- \xE2\x9A\xA0 TEST: these accounts get ALL 14 islands unlocked + selectable on the island-select page (the
-- server's SelectIslandEvent handler has a matching bypass so they can actually spawn anywhere). Matched by
-- USERNAME (case-insensitive); mirrors the server's ALLOWED_TEST_USERS list. REMOVE BEFORE LAUNCH.
local TEST_ACCOUNTS = { ["lando5485"] = true, ["broskie310111"] = true, ["itsmaddmax1"] = true, ["itsmaddmax2"] = true }

-- ⚠ TEST-UNLOCK TOGGLE -- default OFF, so a test account sees the REAL new-player island picker (2-14 locked 🔒).
--
-- Turning it ON does not actually let you go anywhere: the SERVER re-validates every pick against your saved
-- HighestIsland and clamps it. Your own log shows exactly that --
--     ISLAND MENU: selected island 2
--     ISLAND SELECT: Broskie310111 requested LOCKED island 2 (max 1), clamping
-- -- so the override was only ever lying to the CLIENT: the cards showed unlocked, you clicked island 2, and the
-- server quietly put you back on island 1. That mismatch is worse than no override at all.
--
-- Flip to true only to eyeball the later cards' artwork; it must be false (or the whole block deleted) at launch.
local TEST_UNLOCK_ALL_ISLANDS = false
local IS_TEST_ACCOUNT = TEST_UNLOCK_ALL_ISLANDS and (TEST_ACCOUNTS[string.lower(player.Name)] == true)

-- [DIAG] After a brief wait (let StarterGui replicate into PlayerGui + other scripts spawn), list
-- EVERY instance named "LoadingScreen" anywhere it could live. More than one = a stale/duplicate copy
-- is running alongside the Rojo one, which would explain a PLAY button that ignores this script's gate.
task.spawn(function()
	task.wait(2)
	local found = {}
	local function scan(container)
		if not container then return end
		for _, inst in ipairs(container:GetDescendants()) do
			if inst.Name == "LoadingScreen" then table.insert(found, inst:GetFullName() .. " (" .. inst.ClassName .. ")") end
		end
	end
	pcall(function() scan(game:GetService("ReplicatedFirst")) end)
	pcall(function() scan(game:GetService("StarterGui")) end)
	pcall(function() scan(game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")) end)
	pcall(function() scan(playerGui) end)
	print("[LOADINGSCREEN] instances found: " .. (#found > 0 and table.concat(found, "  |  ") or "NONE"))
end)

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

-- ===== IMAGE FALLBACK =====
-- A full-screen background ImageLabel that renders BLANK is almost always a bad asset: a DECAL id used where
-- an IMAGE id is needed, or an asset that's private / still moderating / owned by a different account than the
-- game. We can't repair the asset from code, but we can stop it looking broken: preload it and, if it FAILS,
-- swap in a clean sky-gradient so the screen still looks finished -- and log the exact id + the likely cause.
local function guardBackgroundImage(img, label)
	task.spawn(function()
		local status
		pcall(function()
			ContentProvider:PreloadAsync({ img }, function(_, st) status = st end)
		end)
		if status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then
			warn(("[LOADINGSCREEN] %s image FAILED to load (%s) -- using a sky-gradient fallback. "):format(label, tostring(img.Image))
				.. "Fix: use an IMAGE asset id (not a Decal id), and make sure the asset is APPROVED and owned by the "
				.. "same account/group that owns this game.")
			img.Image = ""
			img.BackgroundTransparency = 0
			img.BackgroundColor3 = Color3.fromRGB(135, 206, 250)
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(Color3.fromRGB(158, 214, 255), Color3.fromRGB(96, 165, 240))
			g.Rotation = 90
			g.Parent = img
		else
			print(("[LOADINGSCREEN] %s image loaded OK (%s)"):format(label, tostring(img.Image)))
		end
	end)
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

-- Master container for BOTH select screens (island + planet) — every island/planet button, title,
-- subtitle, and navigation arrow lives under this. It stays HIDDEN during loading, so the loading screen
-- shows ONLY the loading UI. A hidden parent hides ALL its descendants regardless of their own Visible
-- state, so no select UI can leak onto the loading screen. Revealed only when PLAY is clicked at 100%.
local selectLayer = Instance.new("Frame")
selectLayer.Name = "SelectLayer"
selectLayer.AnchorPoint = Vector2.new(0.5, 0.5)
selectLayer.Position = UDim2.fromScale(0.5, 0.5)
selectLayer.Size = UDim2.fromScale(1, 1)
selectLayer.BackgroundTransparency = 1
selectLayer.Visible = false     -- HARD GATE: nothing under here renders until PLAY sets this true
selectLayer.ZIndex = 2
selectLayer.Parent = root

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
guardBackgroundImage(bg, "loading background")  -- blank -> sky-gradient fallback + logs the failing id/cause

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

-- (Drop-shadow removed: its soft lower edge bled down BEHIND the "% LOADED" text and read as a shaded box.
-- Kept as an invisible instance so the `barShadow.Visible = false` calls in the menu code stay valid.)
local barShadow = makeShadow(barWrap, root, 14)
barShadow.Visible = false

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
pctPill.Visible = false -- REMOVED: the circular "%" pill at the bar's end is hidden ("100% LOADED" text below the bar still shows)

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
playBtn.Position = UDim2.fromScale(0.5, 0.90) -- nudged down slightly so it isn't touching the tip text above it
playBtn.Size = UDim2.fromScale(PLAY_W, PLAY_H)
playBtn.BackgroundColor3 = Color3.fromRGB(55, 205, 70)
playBtn.Text = "" -- text lives in a child label so it can have its own black outline
playBtn.AutoButtonColor = false
playBtn.Visible = false            -- revealed at TRUE 100% (see revealPlay)
playBtn.Active = false             -- not clickable until ready
playBtn.BackgroundTransparency = 1 -- BULLETPROOF HIDE: fully transparent too, so it can render NOTHING before reveal even if Visible leaked (e.g. via the parent CanvasGroup)
playBtn.ZIndex = 8
local playCorner = Instance.new("UICorner"); playCorner.CornerRadius = UDim.new(1, 0); playCorner.Parent = playBtn -- fully rounded
local playAspect = Instance.new("UIAspectRatioConstraint") -- keep the pill shape (width:height) on any aspect ratio
playAspect.AspectRatio = 3.4; playAspect.DominantAxis = Enum.DominantAxis.Width; playAspect.Parent = playBtn
local playStroke = Instance.new("UIStroke") -- thick WHITE border around the button
playStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
playStroke.Color = Color3.fromRGB(255, 255, 255)
playStroke.Thickness = 5
playStroke.Transparency = 1 -- hidden until reveal (restored in revealPlay)
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
playLabel.TextTransparency = 1 -- hidden until reveal (restored in revealPlay)
local playLabelStroke = Instance.new("UIStroke"); playLabelStroke.Color = Color3.fromRGB(0,0,0); playLabelStroke.Thickness = 3; playLabelStroke.Transparency = 1; playLabelStroke.Parent = playLabel
playLabel.Parent = playBtn
playBtn.Parent = root
playShadow = makeShadow(playBtn, root, 16); playShadow.Visible = false; playShadow.ImageTransparency = 1 -- hidden + fully transparent until reveal

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
local loadingPct = 0   -- latest whole-number percent; the PLAY button may ONLY appear once this hits 100
local function setProgress(p)
	p = math.clamp(p, 0, 1)
	fill.Size = UDim2.new(p, 0, 1, 0)
	local pct = math.floor(p * 100)
	loadingPct = pct
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

-- Island-select BACKGROUND image. Direct ScreenGui child (NOT inside the CanvasGroup) so Crop fills the
-- whole screen with no grey bars. Hidden until PLAY. The title + subtitle are drawn as TEXT below (this
-- image has no baked-in title), so they can be shown ONLY on this screen.
local menuBg = Instance.new("ImageLabel")
menuBg.Name = "MenuBackground"
menuBg.AnchorPoint = Vector2.new(0.5, 0.5)
menuBg.Position = UDim2.fromScale(0.5, 0.5)
menuBg.Size = UDim2.fromScale(1, 1)
menuBg.BackgroundTransparency = 1
menuBg.Image = "rbxassetid://97445593789129"
menuBg.ScaleType = Enum.ScaleType.Crop
menuBg.Visible = false
menuBg.ZIndex = 0
menuBg.Parent = gui
guardBackgroundImage(menuBg, "island-select background")  -- blank -> sky-gradient fallback + logs the failing id/cause

-- Island-screen TITLE + SUBTITLE (FredokaOne, white + black outline). Inside `root` so they fade out with
-- the rest. Shown only on the island menu (hidden on the planet screen), so the two never overlap.
local islandTitle = Instance.new("TextLabel")
islandTitle.Name = "IslandTitle"
islandTitle.AnchorPoint = Vector2.new(0.5, 0.5)
islandTitle.Position = UDim2.fromScale(0.5, 0.12)
islandTitle.Size = UDim2.fromScale(0.7, 0.11)
islandTitle.BackgroundTransparency = 1
islandTitle.Font = Enum.Font.FredokaOne
islandTitle.Text = "SELECT YOUR ISLAND"
islandTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
islandTitle.TextScaled = true
islandTitle.Visible = false
islandTitle.ZIndex = 15
local itStroke = Instance.new("UIStroke"); itStroke.Color = Color3.fromRGB(0, 0, 0); itStroke.Thickness = 3; itStroke.Parent = islandTitle
islandTitle.Parent = selectLayer

local islandSubtitle = Instance.new("TextLabel")
islandSubtitle.Name = "IslandSubtitle"
islandSubtitle.AnchorPoint = Vector2.new(0.5, 0.5)
islandSubtitle.Position = UDim2.fromScale(0.5, 0.9)
islandSubtitle.Size = UDim2.fromScale(0.7, 0.06)
islandSubtitle.BackgroundTransparency = 1
islandSubtitle.Font = Enum.Font.FredokaOne
islandSubtitle.Text = "Tap an unlocked island to drop in!"
islandSubtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
islandSubtitle.TextScaled = true
islandSubtitle.Visible = false
islandSubtitle.ZIndex = 15
local isStroke = Instance.new("UIStroke"); isStroke.Color = Color3.fromRGB(0, 0, 0); isStroke.Thickness = 2; isStroke.Parent = islandSubtitle
islandSubtitle.Parent = selectLayer

-- Container for the 14 island cards, in the open CENTER/RIGHT area (clear of the baked-in title up
-- top and the character on the left). Inside `root` so the cards sit above the bg and fade out.
local cards = Instance.new("Frame")
cards.Name = "IslandCards"
cards.AnchorPoint = Vector2.new(0.5, 0.5)
cards.Position = UDim2.fromScale(0.57, 0.58) -- shifted left so buttons 7 & 14 clear the right NEXT arrow (was 0.62)
cards.Size = UDim2.fromScale(0.7, 0.52)
cards.BackgroundTransparency = 1
cards.Visible = false
cards.ZIndex = 11
cards.Parent = selectLayer
local grid = Instance.new("UIGridLayout")
-- 8 per row, NOT 7. There are now FIFTEEN cards: the 14 islands + the BLACK HOLE tease (LayoutOrder 15),
-- so the rows are [1..8] and [9..14 + black hole]. That drops the black hole at the very end of the
-- sequence -- right after Pizza Palms -- which is exactly where you want the question "...and what's
-- after the last island?" to land. Cell width shrinks 0.13 -> 0.115 so 8 still fit (8*0.115 + 7*0.008 < 1).
grid.FillDirectionMaxCells = 8
grid.CellSize = UDim2.fromScale(0.115, 0.46)
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
	-- FIRST-TIME ISLAND 1: start the garden cinematic ON CLICK so its black overlay appears immediately,
	-- covering the menu close + camera move. The server also fires its own trigger; GardenIntro's `playing`
	-- guard prevents a double. (Returning players have SeenGardenIntro=true, so this never fires for them.)
	if n == 1 and player:GetAttribute("SeenGardenIntro") ~= true and type(_G.startGardenIntro) == "function" then
		print("ISLAND MENU: first-time island 1 -> starting garden cinematic (black transition) immediately")
		task.spawn(_G.startGardenIntro)
	end
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

-- ===== CARD 15: THE BLACK HOLE (a hook, not a destination) ==========================================
-- Deliberately NOT selectable -- it never calls chooseIsland. The other 13 locked islands are dead grey
-- boxes with a padlock, which say "you can't" and nothing else. This one is ALIVE: it swirls, it pulses,
-- and when you tap it, it REACTS -- it lurches toward you and refuses. A lock tells a player they are
-- shut out; a thing that answers back tells them there is something in there. That's the difference
-- between a locked door and a mystery, and it costs one card in a menu every player already looks at.
--
-- Keep it non-functional on purpose. The moment it teleports somewhere it stops being a question.
do
	local bh = Instance.new("TextButton")
	bh.Name = "BlackHole"
	bh.LayoutOrder = 15 -- last cell -> sits immediately after Island 14 (Pizza Palms)
	bh.Text = ""
	bh.BorderSizePixel = 0
	bh.AutoButtonColor = false -- we do our own reaction; the stock grey-out would read as "disabled"
	bh.Active = true           -- it MUST be clickable. A dead button is ignored; a live one gets poked.
	bh.BackgroundColor3 = Color3.fromRGB(14, 6, 28)
	bh.ZIndex = 12
	local bhCorner = Instance.new("UICorner"); bhCorner.CornerRadius = UDim.new(0, 14); bhCorner.Parent = bh
	local bhStroke = Instance.new("UIStroke"); bhStroke.Color = Color3.fromRGB(150, 70, 255); bhStroke.Thickness = 2.5; bhStroke.Parent = bh

	-- Slow-rotating gradient = the accretion disc. Cheap, but it makes the card the only thing MOVING
	-- on a screen of 14 static boxes, so the eye goes straight to it.
	local bhGrad = Instance.new("UIGradient")
	bhGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(90, 30, 170)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 4, 20)),
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(60, 15, 130)),
	})
	bhGrad.Parent = bh

	local bhTop = Instance.new("TextLabel")
	bhTop.Name = "Top"
	bhTop.AnchorPoint = Vector2.new(0.5, 0)
	bhTop.Position = UDim2.fromScale(0.5, 0.05)
	bhTop.Size = UDim2.fromScale(0.9, 0.52)
	bhTop.BackgroundTransparency = 1
	bhTop.Font = Enum.Font.FredokaOne
	bhTop.Text = "\xF0\x9F\x8C\x80" -- swirl
	bhTop.TextColor3 = Color3.fromRGB(235, 215, 255)
	bhTop.TextScaled = true
	bhTop.ZIndex = 13
	local bhTs = Instance.new("UIStroke"); bhTs.Color = Color3.fromRGB(0, 0, 0); bhTs.Thickness = 2; bhTs.Parent = bhTop
	bhTop.Parent = bh

	local bhBottom = Instance.new("TextLabel")
	bhBottom.Name = "Bottom"
	bhBottom.AnchorPoint = Vector2.new(0.5, 1)
	bhBottom.Position = UDim2.fromScale(0.5, 0.95)
	bhBottom.Size = UDim2.fromScale(0.94, 0.4)
	bhBottom.BackgroundTransparency = 1
	bhBottom.Font = Enum.Font.FredokaOne
	bhBottom.Text = "???"
	bhBottom.TextColor3 = Color3.fromRGB(215, 185, 255)
	bhBottom.TextScaled = true
	bhBottom.TextWrapped = true
	bhBottom.ZIndex = 13
	local bhBs = Instance.new("UIStroke"); bhBs.Color = Color3.fromRGB(0, 0, 0); bhBs.Thickness = 1.5; bhBs.Parent = bhBottom
	bhBottom.Parent = bh

	bh.Parent = cards

	-- Idle: spin the disc + breathe the stroke, forever.
	task.spawn(function()
		while bh.Parent do
			bhGrad.Rotation = (bhGrad.Rotation + 1) % 360
			task.wait(0.03)
		end
	end)
	task.spawn(function()
		while bh.Parent do
			TweenService:Create(bhStroke, TweenInfo.new(1.1, Enum.EasingStyle.Sine), { Thickness = 5 }):Play()
			task.wait(1.1)
			if not bh.Parent then break end
			TweenService:Create(bhStroke, TweenInfo.new(1.1, Enum.EasingStyle.Sine), { Thickness = 2.5 }):Play()
			task.wait(1.1)
		end
	end)

	-- The refusal. Tapping it does NOT pick an island -- it pulls, shudders, and pushes you back out,
	-- and the subtitle answers you. Rotating lines so a kid who taps it five times gets five answers
	-- and keeps tapping. Guarded so spam-clicking can't stack the tween or strand the subtitle.
	local TEASES = {
		"It's not open yet\xE2\x80\xA6",
		"You're not high enough. Not even close.",
		"Something in there is PULLING.",
		"Reach the top first. Then we'll talk.",
		"\xF0\x9F\x8C\x80 Not yet, little bean.",
	}
	local teaseIdx, reacting = 0, false
	bh.Activated:Connect(function()
		if reacting then return end
		reacting = true
		playUIClick()

		teaseIdx = (teaseIdx % #TEASES) + 1
		local prevText, prevColor = islandSubtitle.Text, islandSubtitle.TextColor3
		islandSubtitle.Text = TEASES[teaseIdx]
		islandSubtitle.TextColor3 = Color3.fromRGB(200, 150, 255)

		-- suck IN, then snap back out -> it feels like the card grabbed at you and let go
		local grow = TweenService:Create(bh, TweenInfo.new(0.09, Enum.EasingStyle.Quad), { Rotation = -4 })
		grow:Play(); grow.Completed:Wait()
		local snap = TweenService:Create(bh, TweenInfo.new(0.35, Enum.EasingStyle.Elastic), { Rotation = 0 })
		snap:Play()

		task.delay(2.2, function()
			if islandSubtitle.Text == TEASES[teaseIdx] then -- don't clobber a newer tease
				islandSubtitle.Text = prevText
				islandSubtitle.TextColor3 = prevColor
			end
			reacting = false
		end)
	end)
end

-- ===== SPACE BACKGROUND SLIDE =====
-- A plain full-screen space background, reachable from the island menu via a right arrow (left arrow
-- goes back). No selectable buttons live on it — just the background, kept for later use.
local spaceBg = Instance.new("ImageLabel")
spaceBg.Name = "SpaceBackground"
spaceBg.AnchorPoint = Vector2.new(0.5, 0.5)
spaceBg.Position = UDim2.fromScale(0.5, 0.5)
spaceBg.Size = UDim2.fromScale(1, 1)
spaceBg.BackgroundTransparency = 1
spaceBg.Image = "rbxassetid://121396936672779"
spaceBg.ScaleType = Enum.ScaleType.Crop
spaceBg.Visible = false
spaceBg.ZIndex = 0
spaceBg.Parent = gui

-- Green circular arrow button (white chevron, black outline) — matches the loading-screen styling.
local function makeArrow(name, pointsLeft)
	local btn = Instance.new("ImageButton")
	btn.Name = name
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Size = UDim2.fromScale(0.075, 0.075)
	btn.BackgroundColor3 = Color3.fromRGB(55, 205, 70)
	btn.AutoButtonColor = true
	btn.Image = ""
	btn.ZIndex = 30
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = btn
	local ar = Instance.new("UIAspectRatioConstraint"); ar.AspectRatio = 1; ar.Parent = btn
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(0, 0, 0); st.Thickness = 4; st.Parent = btn
	local function bar(yoff, rot)
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromScale(0.5, yoff)
		b.Size = UDim2.fromScale(0.62, 0.16)
		b.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		b.BorderSizePixel = 0
		b.Rotation = pointsLeft and -rot or rot
		b.ZIndex = 31
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(1, 0); bc.Parent = b
		local bs = Instance.new("UIStroke"); bs.Color = Color3.fromRGB(0, 0, 0); bs.Thickness = 2; bs.Parent = b
		b.Parent = btn
		return b
	end
	bar(0.34, 42)  -- top half of the chevron
	bar(0.66, -42) -- bottom half
	btn.Parent = selectLayer -- under the master gate, so arrows stay hidden during loading too
	return btn
end

-- Right arrow on the island menu -> show the space background; left arrow on the space slide -> back.
local spaceNextArrow = makeArrow("SpaceNext", false)
spaceNextArrow.Position = UDim2.fromScale(0.955, 0.5)
spaceNextArrow.Visible = false
local spaceBackArrow = makeArrow("SpaceBack", true)
spaceBackArrow.Position = UDim2.fromScale(0.07, 0.5)
spaceBackArrow.Visible = false

-- ===== "SELECT A PLANET" screen (lives on the space slide) =====
-- Mirrors the island-select layout: centered title, 8 green buttons (2 rows of 4, number + name), and a
-- bottom subtitle. Unlocked planets are clickable; locked ones show 🔒. New players: only Mercury (1).
local PLANET_NAMES = { "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune" }
-- Space Realm planet-select remotes (created by PlanetSelectService on the FtF server). GetUnlocks reads the
-- SHARED universe DataStore (highestPlanetReached); Teleport warps the player into the Space Realm PLACE.
local PlanetGetUnlocks = ReplicatedStorage:WaitForChild("PlanetSelect_GetUnlocks", 15)
local PlanetTeleport   = ReplicatedStorage:WaitForChild("PlanetSelect_Teleport", 15)
local planetUnlocked   = {}    -- name -> bool, refreshed from the server each time the planet screen opens
local planetTeleporting = false -- guard so one tap = one teleport request

-- Title "SELECT A PLANET" centered at top (FredokaOne, white + black outline). Inside `root` so it fades
-- out with everything else. Only shown on the space slide, so it never overlaps the island title.
local planetTitle = Instance.new("TextLabel")
planetTitle.Name = "PlanetTitle"
planetTitle.AnchorPoint = Vector2.new(0.5, 0.5)
planetTitle.Position = UDim2.fromScale(0.5, 0.12)
planetTitle.Size = UDim2.fromScale(0.7, 0.11)
planetTitle.BackgroundTransparency = 1
planetTitle.Font = Enum.Font.FredokaOne
planetTitle.Text = "SELECT A PLANET"
planetTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
planetTitle.TextScaled = true
planetTitle.Visible = false
planetTitle.ZIndex = 15
local ptStroke = Instance.new("UIStroke"); ptStroke.Color = Color3.fromRGB(0, 0, 0); ptStroke.Thickness = 3; ptStroke.Parent = planetTitle
planetTitle.Parent = selectLayer

-- Bottom subtitle.
local planetSubtitle = Instance.new("TextLabel")
planetSubtitle.Name = "PlanetSubtitle"
planetSubtitle.AnchorPoint = Vector2.new(0.5, 0.5)
planetSubtitle.Position = UDim2.fromScale(0.5, 0.52)      -- centred: this is now the only thing on the slide
planetSubtitle.Size = UDim2.fromScale(0.82, 0.16)
planetSubtitle.BackgroundTransparency = 1
planetSubtitle.Font = Enum.Font.FredokaOne
planetSubtitle.Text = "\xF0\x9F\x9A\x80 Spawn into Bean Farm\nto reach the Space Realm!"
planetSubtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
planetSubtitle.TextScaled = true
planetSubtitle.Visible = false
planetSubtitle.ZIndex = 15
local psStroke = Instance.new("UIStroke"); psStroke.Color = Color3.fromRGB(0, 0, 0); psStroke.Thickness = 2; psStroke.Parent = planetSubtitle
planetSubtitle.Parent = selectLayer

-- 8 planet buttons in a 4x2 grid, same green rounded style as the island cards.
local planetCardsFrame = Instance.new("Frame")
planetCardsFrame.Name = "PlanetCards"
planetCardsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
planetCardsFrame.Position = UDim2.fromScale(0.5, 0.56)
planetCardsFrame.Size = UDim2.fromScale(0.7, 0.52) -- EXACT same frame size as the island cards
planetCardsFrame.BackgroundTransparency = 1
planetCardsFrame.Visible = false
planetCardsFrame.ZIndex = 11
planetCardsFrame.Parent = selectLayer
local pGrid = Instance.new("UIGridLayout")
pGrid.FillDirectionMaxCells = 4 -- 4 per row -> two rows of 4
pGrid.CellSize = UDim2.fromScale(0.13, 0.46) -- EXACT same button size as the island cards (same frame + cell scale)
pGrid.CellPadding = UDim2.fromScale(0.008, 0.05)
pGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
pGrid.VerticalAlignment = Enum.VerticalAlignment.Center
pGrid.SortOrder = Enum.SortOrder.LayoutOrder
pGrid.Parent = planetCardsFrame

-- Pick an unlocked planet -> ask the server to TELEPORT us into the Space Realm place. The server re-checks
-- the unlock against the shared DataStore, then teleports with the planet name in TeleportData; the Roblox
-- teleport loading screen takes over from here (no local fade/spawn). Locked planets are ignored.
local function choosePlanet(n)
	local name = PLANET_NAMES[n]
	if planetTeleporting or planetUnlocked[name] ~= true then return end -- locked/invalid, or already warping
	planetTeleporting = true
	planetSubtitle.Text = "Traveling to " .. name .. "..."
	print("PLANET MENU: teleport request for " .. name)
	if PlanetTeleport then PlanetTeleport:FireServer(name) end
	-- If we're still here after a moment (locked re-check failed server-side, or the place id is unset),
	-- let the player try again instead of being stuck on "Traveling...".
	task.delay(5, function()
		if gui.Parent then
			planetTeleporting = false
			planetSubtitle.Text = "Tap an unlocked planet to drop in!"
		end
	end)
end

-- Build the 8 planet buttons (styled identically to the island cards). Lock state is set in showSpace.
local planetCards = {}
for n = 1, 8 do
	local card = Instance.new("TextButton")
	card.Name = "Planet" .. n
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

	card.Parent = planetCardsFrame
	card.Activated:Connect(function()
		if card.Active then playUIClick() end -- click SFX only for unlocked (clickable) cards
		choosePlanet(n)
	end)
	planetCards[n] = { card = card, top = top, bottom = bottom }
end

-- ===== "SELECT A DINOSAUR ISLAND" screen (third slide, after the planet screen) =====
-- Same layout as the island-select screen: 14 buttons (2 rows of 7), EXACT same size/placement/style.
-- Unlocked islands are clickable; locked show 🔒. New players: only 1 unlocked. Server validates before spawn.
local DinoSelectEvent = ReplicatedStorage:WaitForChild("DinoSelectEvent", 15)
local dinoPending = nil -- dino island awaiting server approval (guards the round-trip)

-- Dinosaur background (full-screen Crop; direct ScreenGui child like the other backgrounds). Hidden until reached.
local dinoBg = Instance.new("ImageLabel")
dinoBg.Name = "DinoBackground"
dinoBg.AnchorPoint = Vector2.new(0.5, 0.5)
dinoBg.Position = UDim2.fromScale(0.5, 0.5)
dinoBg.Size = UDim2.fromScale(1, 1)
dinoBg.BackgroundTransparency = 1
dinoBg.Image = "rbxassetid://132153667223852"
dinoBg.ScaleType = Enum.ScaleType.Crop
dinoBg.Visible = false
dinoBg.ZIndex = 0
dinoBg.Parent = gui

-- Title + subtitle (under the master gate; hidden until shown, so they never overlap the other screens').
local dinoTitle = Instance.new("TextLabel")
dinoTitle.Name = "DinoTitle"
dinoTitle.AnchorPoint = Vector2.new(0.5, 0.5)
dinoTitle.Position = UDim2.fromScale(0.5, 0.12)
dinoTitle.Size = UDim2.fromScale(0.85, 0.11)
dinoTitle.BackgroundTransparency = 1
dinoTitle.Font = Enum.Font.FredokaOne
dinoTitle.Text = "SELECT A DINOSAUR ISLAND"
dinoTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
dinoTitle.TextScaled = true
dinoTitle.Visible = false
dinoTitle.ZIndex = 15
local dtStroke = Instance.new("UIStroke"); dtStroke.Color = Color3.fromRGB(0, 0, 0); dtStroke.Thickness = 3; dtStroke.Parent = dinoTitle
dinoTitle.Parent = selectLayer

local dinoSubtitle = Instance.new("TextLabel")
dinoSubtitle.Name = "DinoSubtitle"
dinoSubtitle.AnchorPoint = Vector2.new(0.5, 0.5)
dinoSubtitle.Position = UDim2.fromScale(0.5, 0.52)       -- centred: the cards are gone
dinoSubtitle.Size = UDim2.fromScale(0.82, 0.16)
dinoSubtitle.BackgroundTransparency = 1
dinoSubtitle.Font = Enum.Font.FredokaOne
dinoSubtitle.Text = "\xF0\x9F\xA6\x96 Spawn into Bean Farm\nto reach the Dino Realm!"
dinoSubtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
dinoSubtitle.TextScaled = true
dinoSubtitle.Visible = false
dinoSubtitle.ZIndex = 15
local dsStroke = Instance.new("UIStroke"); dsStroke.Color = Color3.fromRGB(0, 0, 0); dsStroke.Thickness = 2; dsStroke.Parent = dinoSubtitle
dinoSubtitle.Parent = selectLayer

-- 14 dino buttons — EXACT same frame + grid config as the island cards (2 rows of 7, same cell size/padding).
local dinoCardsFrame = Instance.new("Frame")
dinoCardsFrame.Name = "DinoCards"
dinoCardsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
dinoCardsFrame.Position = UDim2.fromScale(0.62, 0.58) -- EXACT same placement as the island cards
dinoCardsFrame.Size = UDim2.fromScale(0.7, 0.52)
dinoCardsFrame.BackgroundTransparency = 1
dinoCardsFrame.Visible = false
dinoCardsFrame.ZIndex = 11
dinoCardsFrame.Parent = selectLayer
local dGrid = Instance.new("UIGridLayout")
dGrid.FillDirectionMaxCells = 7 -- 7 per row -> two rows of 7
dGrid.CellSize = UDim2.fromScale(0.13, 0.46)
dGrid.CellPadding = UDim2.fromScale(0.008, 0.05)
dGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
dGrid.VerticalAlignment = Enum.VerticalAlignment.Center
dGrid.SortOrder = Enum.SortOrder.LayoutOrder
dGrid.Parent = dinoCardsFrame

-- Fade the whole screen out into the game (server spawns the placeholder island meanwhile).
local function fadeDinoToGame()
	TweenService:Create(root, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {GroupTransparency = 1}):Play()
	TweenService:Create(bg, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {ImageTransparency = 1}):Play()
	TweenService:Create(dinoBg, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {ImageTransparency = 1}):Play()
	task.delay(0.5, function() gui:Destroy() end)
end
-- Pick an unlocked dino island -> server RE-VALIDATES -> spawn + fade. Shares the island one-choice guard.
local function chooseDino(n)
	if choiceMade or dinoPending then return end
	dinoPending = n
	print("DINO MENU: requesting dino island " .. n)
	if DinoSelectEvent then
		DinoSelectEvent:FireServer(n)
	else
		choiceMade = true; fadeDinoToGame() -- no remote (shouldn't happen): proceed locally
	end
end
-- Server reply: spawn + fade ONLY on approval (never trust the client).
if DinoSelectEvent then
	DinoSelectEvent.OnClientEvent:Connect(function(dinoNum, approved)
		if approved and dinoNum == dinoPending then
			choiceMade = true; dinoPending = nil
			print("DINO MENU: server APPROVED dino island " .. tostring(dinoNum) .. " -> entering game")
			fadeDinoToGame()
		else
			dinoPending = nil -- rejected: allow another pick
			print("DINO MENU: server REJECTED dino island " .. tostring(dinoNum) .. " (locked)")
		end
	end)
end

-- Build the 14 dino buttons (styled identically to the island cards).
local dinoCards = {}
for n = 1, 14 do
	local card = Instance.new("TextButton")
	card.Name = "Dino" .. n
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

	card.Parent = dinoCardsFrame
	card.Activated:Connect(function()
		if card.Active then playUIClick() end -- click SFX only for unlocked (clickable) cards
		chooseDino(n)
	end)
	dinoCards[n] = { card = card, top = top, bottom = bottom }
end

-- Planet screen RIGHT arrow -> dino screen; dino screen LEFT arrow -> planet screen. (Dino is the LAST
-- screen, so it shows NO functional right arrow — the baked-in right arrow is reserved for a future screen.)
local planetNextArrow = makeArrow("PlanetNext", false)
planetNextArrow.Position = UDim2.fromScale(0.955, 0.5)
planetNextArrow.Visible = false
local dinoBackArrow = makeArrow("DinoBack", true)
dinoBackArrow.Position = UDim2.fromScale(0.07, 0.5)
dinoBackArrow.Visible = false

-- ============================================================================================================
-- REALM 4 -- the screen AFTER the dinosaur realm. 14 cards, ALL LOCKED.
--
-- Built HERE, above showMenu/showSpace/showDino, on purpose: each of those functions hides every OTHER screen's
-- elements, so they have to be able to see these locals. Lua closes over locals that already exist at the moment
-- the function is DEFINED -- put this block below them and the hides would silently reference nil.
--
-- EVERY card is locked and unclickable, because there is no unlock system for this realm yet. The lock is driven
-- off a server attribute ("UnlockedRealm4") that nothing sets, so it reads 0 and all 14 stay shut. When you build
-- the progression, set that attribute server-side and the cards light up with no change needed here -- exactly how
-- UnlockedDinos already drives the dino screen.
--
-- DELIBERATELY NO CLIENT TELEPORT. The place ID is recorded below, but nothing here calls TeleportService: a
-- client-side teleport is a client-side decision, and a player could just fire it and walk into a realm they have
-- not unlocked. When this realm opens up, it goes through a server remote that re-validates -- like the planet
-- screen's PlanetSelect_Teleport does.
-- ============================================================================================================
-- The realm-4 asset ID is the screen's BACKGROUND IMAGE, not a place. The destination place ID is still unknown, so
-- it stays 0 -- and nothing reads it yet anyway (see the no-client-teleport note above). Do not paste an image ID
-- in here by mistake: a teleport to an image ID does not fail loudly, it just dumps the player nowhere.
local REALM4_PLACE_ID = 0                   -- <-- SET ME to the real destination place when the realm exists
local REALM4_TITLE    = "SELECT A REALM"    -- <-- RENAME ME once the realm has a name
local REALM4_COUNT    = 14

-- Backdrop: same ImageLabel setup as the dino screen (full-bleed, Crop so it fills any aspect ratio without
-- squashing), so all four select screens behave identically on every device.
local realm4Bg = Instance.new("ImageLabel")
realm4Bg.Name = "Realm4Background"
realm4Bg.AnchorPoint = Vector2.new(0.5, 0.5)
realm4Bg.Position = UDim2.fromScale(0.5, 0.5)
realm4Bg.Size = UDim2.fromScale(1, 1)
realm4Bg.BackgroundTransparency = 1
realm4Bg.Image = "rbxassetid://104365496493966"
realm4Bg.ScaleType = Enum.ScaleType.Crop
realm4Bg.Visible = false
realm4Bg.ZIndex = 0
realm4Bg.Parent = gui

local realm4Title = Instance.new("TextLabel")
realm4Title.Name = "Realm4Title"
realm4Title.AnchorPoint = Vector2.new(0.5, 0.5)
realm4Title.Position = UDim2.fromScale(0.5, 0.12)
realm4Title.Size = UDim2.fromScale(0.85, 0.11)
realm4Title.BackgroundTransparency = 1
realm4Title.Font = Enum.Font.FredokaOne
realm4Title.Text = REALM4_TITLE
realm4Title.TextColor3 = Color3.fromRGB(255, 255, 255)
realm4Title.TextScaled = true
realm4Title.Visible = false
realm4Title.ZIndex = 15
do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(0,0,0); s.Thickness = 3; s.Parent = realm4Title end
realm4Title.Parent = selectLayer

local realm4Subtitle = Instance.new("TextLabel")
realm4Subtitle.Name = "Realm4Subtitle"
realm4Subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
realm4Subtitle.Position = UDim2.fromScale(0.5, 0.52)     -- centred: the cards are gone
realm4Subtitle.Size = UDim2.fromScale(0.82, 0.16)
realm4Subtitle.BackgroundTransparency = 1
realm4Subtitle.Font = Enum.Font.FredokaOne
realm4Subtitle.Text = "\xF0\x9F\x8D\xAD Spawn into Bean Farm\nto reach the Candy Realm!"
realm4Subtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
realm4Subtitle.TextScaled = true
realm4Subtitle.Visible = false
realm4Subtitle.ZIndex = 15
do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(0,0,0); s.Thickness = 2; s.Parent = realm4Subtitle end
realm4Subtitle.Parent = selectLayer

-- 14 cards -- the SAME frame + grid config as the island / dino cards (2 rows of 7), so the four screens line up.
local realm4CardsFrame = Instance.new("Frame")
realm4CardsFrame.Name = "Realm4Cards"
realm4CardsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
realm4CardsFrame.Position = UDim2.fromScale(0.62, 0.58)
realm4CardsFrame.Size = UDim2.fromScale(0.7, 0.52)
realm4CardsFrame.BackgroundTransparency = 1
realm4CardsFrame.Visible = false
realm4CardsFrame.ZIndex = 11
realm4CardsFrame.Parent = selectLayer
do
	local grid = Instance.new("UIGridLayout")
	grid.FillDirectionMaxCells = 7
	grid.CellSize = UDim2.fromScale(0.13, 0.46)
	grid.CellPadding = UDim2.fromScale(0.008, 0.05)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.VerticalAlignment = Enum.VerticalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = realm4CardsFrame
end

local realm4Cards = {}
for n = 1, REALM4_COUNT do
	local card = Instance.new("TextButton")
	card.Name = "Realm4_" .. n
	card.LayoutOrder = n
	card.Text = ""
	card.BorderSizePixel = 0
	card.Active = false          -- locked from birth; showRealm4 re-asserts it every time the screen opens
	card.AutoButtonColor = false
	card.ZIndex = 12
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = card end
	do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(0,0,0); s.Thickness = 2.5; s.Parent = card end

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
	do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(0,0,0); s.Thickness = 2; s.Parent = top end
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
	do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(0,0,0); s.Thickness = 1.5; s.Parent = bottom end
	bottom.Parent = card

	card.Parent = realm4CardsFrame
	-- No chooser is wired up at all. A locked card has Active=false so it cannot be clicked anyway, but wiring a
	-- teleport that "checks a lock" client-side would just be a lock a cheater can skip. When the realm opens,
	-- this gets a server remote that re-validates, like the other screens.
	realm4Cards[n] = { card = card, top = top, bottom = bottom }
end

-- Dino screen RIGHT arrow -> realm 4 (this is the "future screen" the dino comment was holding the arrow for).
local dinoNextArrow = makeArrow("DinoNext", false)
dinoNextArrow.Position = UDim2.fromScale(0.955, 0.5)
dinoNextArrow.Visible = false
local realm4BackArrow = makeArrow("Realm4Back", true)
realm4BackArrow.Position = UDim2.fromScale(0.07, 0.5)
realm4BackArrow.Visible = false

local function showMenu()
	-- Highest reached island comes from the server (set on data load), so locks reflect saved progress.
	local highest = player:GetAttribute("HighestIsland")
	local waited = 0
	while not highest and waited < 5 do task.wait(0.1); waited = waited + 0.1; highest = player:GetAttribute("HighestIsland") end
	highest = highest or 1
	-- \xE2\x9A\xA0 TEST: test accounts get ALL 14 islands unlocked/selectable; normal players keep their
	-- reached-only locks. REMOVE BEFORE LAUNCH.
	if IS_TEST_ACCOUNT then highest = 14 end
	for n = 1, 14 do
		local e = islandCards[n]
		if n <= highest then
			-- UNLOCKED: green, clickable, big number + island name. Bean Farm (island 1) is GOLDEN -- it's the
			-- hub everyone spawns into and reaches the realm portals from, so it stands out from the rest.
			e.card.Active = true; e.card.AutoButtonColor = true
			e.card.BackgroundColor3 = (n == 1) and Color3.fromRGB(226, 178, 52) or Color3.fromRGB(45, 175, 75)
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
	-- Hide the planet + dino slides (in case we came BACK from one), show the island menu + its right arrow.
	spaceBg.Visible = false; spaceBackArrow.Visible = false; planetNextArrow.Visible = false
	planetTitle.Visible = false; planetSubtitle.Visible = false; planetCardsFrame.Visible = false
	dinoBg.Visible = false; dinoBackArrow.Visible = false; dinoNextArrow.Visible = false
	dinoTitle.Visible = false; dinoSubtitle.Visible = false; dinoCardsFrame.Visible = false
	realm4Bg.Visible = false; realm4BackArrow.Visible = false
	realm4Title.Visible = false; realm4Subtitle.Visible = false; realm4CardsFrame.Visible = false
	menuBg.Visible = true
	cards.Visible = true
	islandTitle.Visible = true; islandSubtitle.Visible = true -- island screen's OWN title/subtitle
	spaceNextArrow.Visible = true
end

-- Paint one planet card as UNLOCKED (green, clickable) or LOCKED (navy + 🔒, not clickable).
local function paintPlanetCard(n, isUnlocked)
	local e = planetCards[n]
	local name = PLANET_NAMES[n]
	if isUnlocked then
		e.card.Active = true; e.card.AutoButtonColor = true
		e.card.BackgroundColor3 = Color3.fromRGB(45, 175, 75)
		e.top.Text = tostring(n); e.top.TextColor3 = Color3.fromRGB(255, 255, 255)
		e.bottom.Text = name
	else
		e.card.Active = false; e.card.AutoButtonColor = false
		e.card.BackgroundColor3 = Color3.fromRGB(18, 28, 66)
		e.top.Text = "\xF0\x9F\x94\x92"; e.top.TextColor3 = Color3.fromRGB(255, 205, 70) -- 🔒 gold
		e.bottom.Text = name
	end
end

-- Show the "SELECT A PLANET" screen on the space slide (hides the island menu + its title). Left arrow
-- returns to the island menu; the space background's baked-in right arrow stays visible.
local function showSpace()
	planetTeleporting = false
	planetSubtitle.Text = "Tap an unlocked planet to drop in!"
	-- Start with EVERYTHING locked (so no card is clickable before the server answers), then swap in the
	-- real unlocks asynchronously so the screen appears instantly instead of blocking on the DataStore read.
	planetUnlocked = {}
	for n = 1, 8 do paintPlanetCard(n, false) end
	task.spawn(function()
		local snapUnlocked = {}
		if PlanetGetUnlocks then
			local ok, snap = pcall(function() return PlanetGetUnlocks:InvokeServer() end)
			if ok and type(snap) == "table" and type(snap.unlocked) == "table" then
				snapUnlocked = snap.unlocked
			end
		end
		planetUnlocked = snapUnlocked -- unlocks come from the SHARED Space Realm DataStore (highestPlanetReached)
		if planetCardsFrame.Visible then -- still on the planet screen
			for n = 1, 8 do paintPlanetCard(n, snapUnlocked[PLANET_NAMES[n]] == true) end
		end
	end)
	-- Hide the island menu + its title/subtitle AND the dino slide, so ONLY the planet screen shows (no overlap).
	menuBg.Visible = false
	cards.Visible = false
	islandTitle.Visible = false; islandSubtitle.Visible = false
	spaceNextArrow.Visible = false
	dinoBg.Visible = false; dinoBackArrow.Visible = false; dinoNextArrow.Visible = false
	dinoTitle.Visible = false; dinoSubtitle.Visible = false; dinoCardsFrame.Visible = false
	realm4Bg.Visible = false; realm4BackArrow.Visible = false
	realm4Title.Visible = false; realm4Subtitle.Visible = false; realm4CardsFrame.Visible = false
	spaceBg.Visible = true
	spaceBackArrow.Visible = true       -- LEFT: back to island
	planetNextArrow.Visible = true      -- RIGHT: forward to the dino screen
	planetTitle.Visible = true
	planetSubtitle.Visible = true
	planetCardsFrame.Visible = false -- realms are entered via the in-world portal now, not tapped here
end

-- Show the "SELECT A DINOSAUR ISLAND" screen (hides the planet screen). Left arrow -> planet screen. This
-- is the LAST screen, so there is no functional right arrow (the baked-in one is reserved for a future screen).
local function showDino()
	-- 0, not 1: if the attribute has not replicated yet, paint everything LOCKED rather than flashing a free
	-- unlocked card that the server would then refuse anyway.
	local unlocked = tonumber(player:GetAttribute("UnlockedDinos")) or 0
	if IS_TEST_ACCOUNT then unlocked = 14 end -- \xE2\x9A\xA0 TEST: all dino islands unlocked. REMOVE BEFORE LAUNCH.
	for n = 1, 14 do
		local e = dinoCards[n]
		if n <= unlocked then
			-- UNLOCKED: green, clickable, big number + label.
			e.card.Active = true; e.card.AutoButtonColor = true
			e.card.BackgroundColor3 = Color3.fromRGB(45, 175, 75)
			e.top.Text = tostring(n); e.top.TextColor3 = Color3.fromRGB(255, 255, 255)
			e.bottom.Text = "Island " .. n
		else
			-- LOCKED: dark navy, gold 🔒 + label, not clickable.
			e.card.Active = false; e.card.AutoButtonColor = false
			e.card.BackgroundColor3 = Color3.fromRGB(18, 28, 66)
			e.top.Text = "\xF0\x9F\x94\x92"; e.top.TextColor3 = Color3.fromRGB(255, 205, 70) -- 🔒 gold
			e.bottom.Text = "Island " .. n
		end
	end
	-- Hide EVERY other screen, show the dino screen. The island hides look redundant -- dino used to be reachable
	-- only from the planet screen, which had already hidden them -- but realm 4 now also routes back into here, so
	-- relying on "whoever sent me here already cleaned up" is a bug waiting for the next screen to be added.
	menuBg.Visible = false; cards.Visible = false
	islandTitle.Visible = false; islandSubtitle.Visible = false; spaceNextArrow.Visible = false
	spaceBg.Visible = false
	planetTitle.Visible = false; planetSubtitle.Visible = false; planetCardsFrame.Visible = false
	spaceBackArrow.Visible = false; planetNextArrow.Visible = false
	realm4Bg.Visible = false; realm4BackArrow.Visible = false
	realm4Title.Visible = false; realm4Subtitle.Visible = false; realm4CardsFrame.Visible = false
	dinoBg.Visible = true
	dinoTitle.Visible = true; dinoSubtitle.Visible = true; dinoCardsFrame.Visible = false -- portal, not tap
	dinoBackArrow.Visible = true         -- LEFT: back to the planet screen
	dinoNextArrow.Visible = true         -- RIGHT: on to realm 4
end

-- Show realm 4. Every card is repainted LOCKED on each open, from the server's UnlockedRealm4 attribute -- which
-- nothing sets yet, so it reads 0 and all 14 stay shut. Painting from the attribute (rather than hard-coding the
-- lock) means the day you add the unlock, this screen already works.
local function showRealm4()
	local unlocked = tonumber(player:GetAttribute("UnlockedRealm4")) or 0
	for n = 1, REALM4_COUNT do
		local e = realm4Cards[n]
		if n <= unlocked then
			e.card.Active = true; e.card.AutoButtonColor = true
			e.card.BackgroundColor3 = Color3.fromRGB(45, 175, 75)
			e.top.Text = tostring(n); e.top.TextColor3 = Color3.fromRGB(255, 255, 255)
			e.bottom.Text = "Island " .. n
		else
			-- LOCKED: dark navy, gold 🔒, not clickable -- identical treatment to the island / dino / planet cards.
			e.card.Active = false; e.card.AutoButtonColor = false
			e.card.BackgroundColor3 = Color3.fromRGB(18, 28, 66)
			e.top.Text = "\xF0\x9F\x94\x92"; e.top.TextColor3 = Color3.fromRGB(255, 205, 70)
			e.bottom.Text = "Island " .. n
		end
	end
	-- Hide every other screen, show this one.
	menuBg.Visible = false; cards.Visible = false
	islandTitle.Visible = false; islandSubtitle.Visible = false; spaceNextArrow.Visible = false
	spaceBg.Visible = false; spaceBackArrow.Visible = false; planetNextArrow.Visible = false
	planetTitle.Visible = false; planetSubtitle.Visible = false; planetCardsFrame.Visible = false
	dinoBg.Visible = false; dinoBackArrow.Visible = false; dinoNextArrow.Visible = false
	dinoTitle.Visible = false; dinoSubtitle.Visible = false; dinoCardsFrame.Visible = false
	realm4Bg.Visible = true
	realm4Title.Visible = true; realm4Subtitle.Visible = true; realm4CardsFrame.Visible = false -- portal, not tap
	realm4BackArrow.Visible = true       -- LEFT: back to dino. No RIGHT arrow -- this is the last screen now.
end

spaceNextArrow.Activated:Connect(function() playUIClick(); showSpace() end)
spaceBackArrow.Activated:Connect(function() playUIClick(); showMenu() end)
planetNextArrow.Activated:Connect(function() playUIClick(); showDino() end)
dinoBackArrow.Activated:Connect(function() playUIClick(); showSpace() end)
dinoNextArrow.Activated:Connect(function() playUIClick(); showRealm4() end)
realm4BackArrow.Activated:Connect(function() playUIClick(); showDino() end)

-- ===== READY / PLAY =====
local function scalePlay(mult, dur)
	TweenService:Create(playBtn, TweenInfo.new(dur or 0.12, Enum.EasingStyle.Quad),
		{Size = UDim2.fromScale(PLAY_W * mult, PLAY_H * mult)}):Play()
end

local playRevealed = false               -- once-guard: the reveal may fire only ONCE (but IS guaranteed to fire)
local function revealPlay(reason)
	-- HARD GATE: the PLAY button may ONLY appear at 100% LOADED. The driver/failsafe both call setProgress(1)
	-- right before this, so loadingPct is 100 on every legit call; an accidental early call (loadingPct < 100)
	-- returns WITHOUT consuming the once-guard, so the real reveal can still happen later.
	if loadingPct < 100 then return end
	if playRevealed then return end      -- already revealed once — never double-fire
	playRevealed = true
	print("[LOADINGSCREEN] revealPlay fired via " .. tostring(reason or "NORMAL path") .. " (loadingPct=" .. tostring(loadingPct) .. ")")
	setProgress(1)                       -- affirm 100% (redundant on the legit path, harmless)
	-- Restore the transparencies that were forced to 1 at creation (the button was kept BOTH
	-- Visible=false AND fully transparent until now, so it could not render at all before this
	-- real-100% reveal). This is the moment — and the only moment — the button becomes visible.
	playBtn.BackgroundTransparency = 0
	playStroke.Transparency = 0
	playLabel.TextTransparency = 0
	playLabelStroke.Transparency = 0
	playShadow.ImageTransparency = 1  -- keep the drop-shadow hidden (it read as a grey box behind PLAY)
	playShadow.Visible = false
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

-- PLAY press -> open the island-select menu (picking one spawns + releases the player). Guard so the multiple
-- bound input paths (Activated + MouseButton1Click + TouchTap all fire on one click) only run it ONCE.
local function onPlayPressed()
	if not playBtn.Active then return end -- not ready yet, or already consumed this press
	playBtn.Active = false
	playUIClick()
	-- ISLAND-SELECT MENU REMOVED: PLAY drops you STRAIGHT into the game. chooseIsland() spawns you + releases
	-- the hold, and (for first-timers on island 1) still kicks off the garden intro cinematic. We spawn you on
	-- your HOME island (highest reached) so returning players resume where they left off; brand-new players
	-- are island 1 -> intro plays.
	local home = player:GetAttribute("HighestIsland")
	if type(home) ~= "number" or home < 1 then home = 1 end
	print("[LOADINGSCREEN] PLAY pressed -> straight into the game on island " .. home .. " (island menu removed)")
	chooseIsland(home)
end
playBtn.Activated:Connect(onPlayPressed)
playBtn.MouseButton1Click:Connect(onPlayPressed) -- redundant safety in case Activated is swallowed on a device
playBtn.TouchTap:Connect(onPlayPressed)

-- ===== TIMING + PRELOAD =====
-- 10-SECOND MINIMUM fill. PLAY appears only once BOTH (a) 10s have elapsed AND (b) the real asset
-- preload + game.Loaded are done — whichever is LATER. So if assets finish in 3s the bar still takes
-- the full 10s; if assets take 14s it waits the full 14s. The bar HOLDS at 95% until assets are ready
-- (it never sits at a visual 100% while still waiting), then snaps to 100% and reveals PLAY.
local FILL_SECONDS    = 10   -- the normal MINIMUM fill time
local PRELOAD_TIMEOUT = 11   -- if the preload hasn't finished by now (e.g. it's stuck on an unapproved/bad asset), proceed ANYWAY
local MAX_REVEAL_TIME = 13   -- HARD FAILSAFE: PLAY is force-revealed no later than this, no matter what (must be within 12-15s)
local assetsReady = false
local preloadStart = os.clock()

-- WATCHDOG: GUARANTEES `assetsReady` flips even if PreloadAsync HANGS. PreloadAsync yields (waits) on a
-- stuck/unapproved asset id (e.g. the "not approved" / "type does not match" sound ids), and a pcall can't
-- interrupt a yield -- so the real preload coroutine below could block forever and never set assetsReady.
-- This independent timer flips it after PRELOAD_TIMEOUT regardless, so the loader never waits on a stuck asset.
task.spawn(function()
	while not assetsReady and (os.clock() - preloadStart) < PRELOAD_TIMEOUT do task.wait(0.1) end
	if not assetsReady then
		assetsReady = true
		print(string.format("[LOADINGSCREEN] preload finished (or timed out after %.1fs)", os.clock() - preloadStart))
	end
end)

-- REAL preload (best-effort, underneath). The WHOLE thing is in a pcall so a thrown error can't kill it, and
-- each batch is in its own pcall so one bad asset can't stop the rest. Flips assetsReady when it finishes --
-- but only if the watchdog above hasn't already.
task.spawn(function()
	local ok, err = pcall(function()
		if not game:IsLoaded() then game.Loaded:Wait() end
		local assets = game:GetDescendants()
		local total = #assets
		local BATCH = 50
		local i = 0
		while i < total do
			local batch = {}
			for _ = 1, BATCH do
				i = i + 1
				if i > total then break end
				batch[#batch + 1] = assets[i]
			end
			pcall(function() ContentProvider:PreloadAsync(batch) end)
			if (os.clock() - preloadStart) > 30 then break end -- absolute cap on the batch loop
		end
	end)
	if not ok then print("[LOADINGSCREEN] preload pcall caught error: " .. tostring(err)) end
	if not assetsReady then
		assetsReady = true
		print(string.format("[LOADINGSCREEN] preload finished (or timed out after %.1fs)", os.clock() - preloadStart))
	end
end)

-- DRIVER: smooth time-based fill to the 10s MINIMUM, held just below 100% (capped at 0.95) until assets are
-- ready, then snaps to 100% and reveals PLAY. TWO exit conditions, whichever comes FIRST:
--   NORMAL   -> 10s elapsed AND assetsReady (the intended path),
--   FAILSAFE -> the hard MAX_REVEAL_TIME cap (so PLAY ALWAYS appears, even if everything above stalls).
task.spawn(function()
	local startT = os.clock()
	while true do
		local elapsed = os.clock() - startT
		local timeP = math.min(elapsed / FILL_SECONDS, 1)
		setProgress(assetsReady and timeP or math.min(timeP, 0.95)) -- hold at 95% until assets are ready
		if assetsReady and timeP >= 1 then
			setProgress(1); revealPlay("NORMAL path"); break
		end
		if elapsed >= MAX_REVEAL_TIME then
			setProgress(1); revealPlay("FAILSAFE timeout"); break    -- never leave the player without a PLAY button
		end
		task.wait()
	end
end)
