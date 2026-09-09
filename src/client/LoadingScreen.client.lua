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
			-- Safe to add a gradient HERE (unlike at build time) precisely because the image is cleared on
			-- the line below: with no Image left there is nothing for the gradient to tint, so it renders
			-- as a plain sky fill. The guard keeps it to one gradient if this ever runs twice.
			img.Image = ""
			img.BackgroundTransparency = 0
			if not img:FindFirstChildOfClass("UIGradient") then
				img.BackgroundColor3 = Color3.fromRGB(135, 206, 250)
				local g = Instance.new("UIGradient")
				g.Color = ColorSequence.new(Color3.fromRGB(158, 214, 255), Color3.fromRGB(96, 165, 240))
				g.Rotation = 90
				g.Parent = img
			end
		else
			print(("[LOADINGSCREEN] %s image loaded OK (%s)"):format(label, tostring(img.Image)))
		end
	end)
end

-- ===== WHAT THIS SCREEN IS =====
-- THE ORIGINAL LOADING SCREEN IS BACK: the full-screen background PHOTO (the FART TO FLOAT logo, character
-- and sky baked into one image) with a SIMPLE LOADING BAR across the lower third, filling on real preload
-- progress, and PLAY appearing underneath it when the bar reaches 100%.
--
-- For a while this screen was replaced by the MLR STUDIOS splash -- the charcoal/gold composition built
-- from "intro image refrence.png" at the repo root. That splash has NOT been deleted; the whole STUDIO
-- INTRO section at the bottom of this file is intact and still works. It is simply switched OFF, because
-- what the game wants on boot is the picture and the bar.
--
-- The two switches below are the whole difference, and they are a matched pair:
--   SHOW_BG_PHOTO     true  -> the photo is the loading screen (and the bar has something to sit on)
--   SHOW_STUDIO_INTRO false -> the splash never builds, so nothing covers the photo while it loads
-- Set SHOW_STUDIO_INTRO back to true and SHOW_BG_PHOTO back to false to return to the splash exactly as
-- it was; nothing else needs touching in either direction.
--
-- The IN-GAME intro (GardenIntro's garden cinematic, started from chooseIsland below) is untouched by
-- either switch -- that is a separate cinematic and it plays as normal.
local SHOW_BG_PHOTO     = true   -- full-screen background photo (the original loading screen art)
local SHOW_STUDIO_INTRO = false  -- MLR STUDIOS splash. Off: the photo + bar own the wait, as they used to.

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
-- PAINTED FROM FRAME ONE, NOT WHEN THE PHOTO ARRIVES.
-- This used to be BackgroundTransparency = 1 with only the Image set. The ScreenGui is parented on line 116,
-- a few milliseconds into the join -- but an ImageLabel with a transparent background and an unfetched image
-- draws NOTHING, so for as long as the asset took to download the "instant" intro was an empty screen. The
-- boot log measured that gap: script running at 04.185, image resolved at 07.938 -- 3.7 seconds of blank.
--
-- The sky gradient below is the same one guardBackgroundImage falls back to when the asset genuinely fails.
-- Using it as the STARTING state means the screen is a finished-looking sky immediately and the photo simply
-- lands on top of it when it is ready. Nothing waits, and a slow download degrades into a plain sky instead
-- of into nothing at all -- which also makes the failure path identical to the loading path.
-- FLAT COLOUR ONLY -- DO NOT PUT A UIGradient ON THIS LABEL.
-- On an ImageLabel a UIGradient is applied to the Image as well as to the background, so a gradient here
-- does not sit *behind* the photo, it multiplies *over* it: once the asset loaded the whole loading screen
-- came out washed blue. BackgroundColor3 has no such effect -- it is painted strictly behind the image and
-- vanishes the moment the image covers it, which is exactly the placeholder behaviour wanted here.
bg.BackgroundTransparency = 0
bg.BackgroundColor3 = Color3.fromRGB(135, 206, 250)
bg.Image = SHOW_BG_PHOTO and "rbxassetid://127983055545494" or ""  -- photo removed for now (see SHOW_BG_PHOTO)
bg.ScaleType = Enum.ScaleType.Crop
bg.ZIndex = 0                            -- behind root (ZIndex 1) and all UI
-- VISIBLE FROM FRAME ONE when the splash is off. With the studio intro running this was false, because the
-- splash covered the screen anyway and the photo was only revealed at handover. With the splash off, false
-- would mean the player stares at an empty CanvasGroup for the entire load and the picture only appears at
-- the very end -- which is the opposite of a loading screen. So the picture IS the wait again.
bg.Visible = not SHOW_STUDIO_INTRO
bg.Parent = gui                          -- direct ScreenGui child, behind the UI CanvasGroup
if SHOW_BG_PHOTO then
	guardBackgroundImage(bg, "loading background")  -- blank -> sky-gradient fallback + logs the failing id/cause
else
	-- No photo: paint the sky ourselves. This is an ImageLabel with no Image, so a UIGradient here has
	-- nothing to multiply over and renders as a plain sky fill (the same fallback guardBackgroundImage uses).
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(168, 220, 255), Color3.fromRGB(88, 158, 240))
	g.Rotation = 90
	g.Parent = bg
end

-- Soft drop-shadow helper: a blurred 9-slice rounded shadow placed BEHIND `target` (as a sibling in
-- `parent`), expanded by `spread` px and nudged down so it reads as a soft shadow. Returns the shadow.
-- Fade the loading background out. `bg` is no longer a photo — with SHOW_BG_PHOTO off it is an ImageLabel
-- with NO image whose BackgroundColor3 + UIGradient paint the sky. Tweening only ImageTransparency (which
-- is all the old code did, because the photo was the whole picture) would therefore fade nothing and leave
-- a solid blue rectangle sitting over the game until gui:Destroy() popped it away. Both properties go.
local function fadeBg(target, dur)
	TweenService:Create(target, TweenInfo.new(dur, Enum.EasingStyle.Quad),
		{ImageTransparency = 1, BackgroundTransparency = 1}):Play()
end

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

-- ===== PLAY-SCREEN TITLE =====
-- The background PHOTO has "FART TO FLOAT" baked into it. With the photo gone the play screen would have
-- had no title at all, so it is drawn as text here — same FredokaOne + white-on-black-outline as the rest
-- of the game's UI. Hidden until the intro hands over (revealPlay).
--
-- WITH THE PHOTO BACK ON, THIS STAYS HIDDEN. The picture already says FART TO FLOAT in the game's own
-- lettering; drawing the words again on top of it gives you the title twice, once in each font. So the
-- text title is now the FALLBACK title — it appears only when there is no photo to carry it.
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "GameTitle"
titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
titleLabel.Position = UDim2.fromScale(0.5, 0.34)
titleLabel.Size = UDim2.fromScale(0.78, 0.17)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.FredokaOne
titleLabel.Text = "FART TO FLOAT"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextScaled = true
titleLabel.TextTransparency = 1  -- faded up by revealPlay
titleLabel.Visible = false
titleLabel.ZIndex = 5
local titleStroke = Instance.new("UIStroke")
titleStroke.Color = Color3.fromRGB(0, 0, 0); titleStroke.Thickness = 5; titleStroke.Transparency = 1
titleStroke.Parent = titleLabel
titleLabel.Parent = root

--======================================================================
-- THE SIMPLE LOADING BAR  (restored)
--======================================================================
-- A track, a fill, and "% LOADED" over it. That is deliberately all it is -- this is the original bar, not
-- a new one: no rotating tips, no spinner, no per-asset filename crawl. The player is looking at the
-- picture; the bar's only job is to say how much longer.
--
-- IT IS DRIVEN BY REAL PROGRESS, NOT A TIMER. `setLoadingPct` below is called from preload pass 1 as each
-- batch of 50 assets comes back (see TIMING + PRELOAD), so the fill tracks work actually completed. A bar
-- animated on a fixed duration is worse than no bar at all: it finishes early on a slow client and then
-- sits full while the player waits anyway, which teaches them the bar is lying.
--
-- It lives on `root` (the CanvasGroup) so the whole screen still fades out as one unit at handover, and it
-- is hidden the moment PLAY is revealed -- a full bar sitting under a PLAY button is just clutter.
local LOADBAR_Y = 0.80

local loadBarTrack = Instance.new("Frame")
loadBarTrack.Name = "LoadBar"
loadBarTrack.AnchorPoint = Vector2.new(0.5, 0.5)
loadBarTrack.Position = UDim2.fromScale(0.5, LOADBAR_Y)
loadBarTrack.Size = UDim2.fromScale(0.46, 0.032)
loadBarTrack.BackgroundColor3 = Color3.fromRGB(18, 26, 40)
loadBarTrack.BackgroundTransparency = 0.25
loadBarTrack.BorderSizePixel = 0
loadBarTrack.ZIndex = 6
loadBarTrack.Visible = not SHOW_STUDIO_INTRO   -- with the splash on, the splash IS the wait; no bar
loadBarTrack.Parent = root
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = loadBarTrack
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(255, 255, 255); s.Thickness = 3; s.Transparency = 0.15
	s.Parent = loadBarTrack
end

local loadBarFill = Instance.new("Frame")
loadBarFill.Name = "Fill"
loadBarFill.AnchorPoint = Vector2.new(0, 0.5)
loadBarFill.Position = UDim2.fromScale(0, 0.5)
loadBarFill.Size = UDim2.fromScale(0, 1)      -- grows to 1 on the X axis
loadBarFill.BackgroundColor3 = Color3.fromRGB(55, 205, 70) -- the PLAY button's green: the bar fills toward it
loadBarFill.BorderSizePixel = 0
loadBarFill.ZIndex = 7
loadBarFill.Parent = loadBarTrack
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = loadBarFill end

local loadPctLabel = Instance.new("TextLabel")
loadPctLabel.Name = "LoadPct"
loadPctLabel.AnchorPoint = Vector2.new(0.5, 1)
loadPctLabel.Position = UDim2.fromScale(0.5, LOADBAR_Y - 0.030)
loadPctLabel.Size = UDim2.fromScale(0.4, 0.045)
loadPctLabel.BackgroundTransparency = 1
loadPctLabel.Font = Enum.Font.FredokaOne
loadPctLabel.Text = "0% LOADED"
loadPctLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
loadPctLabel.TextScaled = true
loadPctLabel.ZIndex = 7
loadPctLabel.Visible = not SHOW_STUDIO_INTRO
loadPctLabel.Parent = root
do
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(0, 0, 0); s.Thickness = 4
	s.Parent = loadPctLabel
	local t = Instance.new("UITextSizeConstraint"); t.MaxTextSize = 34; t.Parent = loadPctLabel
end

-- MONOTONIC. Two preload passes and a watchdog can all report at once; a bar that ever goes BACKWARDS is
-- the one thing a loading bar must never do, so a lower figure than the one already shown is ignored.
local loadingPct = 0
local function setLoadingPct(pct)
	pct = math.clamp(tonumber(pct) or 0, 0, 100)
	if pct <= loadingPct then return end
	loadingPct = pct
	loadPctLabel.Text = string.format("%d%% LOADED", math.floor(pct))
	TweenService:Create(loadBarFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
		{ Size = UDim2.fromScale(pct / 100, 1) }):Play()
end

local function hideLoadBar()
	loadBarTrack.Visible = false
	loadPctLabel.Visible = false
end

-- ===== PLAY button (hidden/disabled until 100%) =====
local PLAY_W, PLAY_H = 0.23, 0.12 -- base size as VIEWPORT FRACTIONS (responsive); hover/press scale around this
local playShadow -- soft shadow (created after the button so it can copy its footprint)
local playBtn = Instance.new("TextButton")
playBtn.Name = "PlayButton"
playBtn.AnchorPoint = Vector2.new(0.5, 0.5)
playBtn.Position = UDim2.fromScale(0.5, 0.63) -- centred under the title; the tips/bar that used to sit here are gone
playBtn.Size = UDim2.fromScale(PLAY_W, PLAY_H)
playBtn.BackgroundColor3 = Color3.fromRGB(55, 205, 70)
playBtn.Text = "" -- text lives in a child label so it can have its own black outline
playBtn.AutoButtonColor = false
playBtn.Visible = false            -- revealed at TRUE 100% (see revealPlay)
playBtn.Active = false             -- not clickable until ready
playBtn.BackgroundTransparency = 1 -- BULLETPROOF HIDE: fully transparent too, so it can render NOTHING before reveal even if Visible leaked (e.g. via the parent CanvasGroup)
playBtn.ZIndex = 8
-- No tick on this one. UiHaptics adopts every GuiButton under PlayerGui, so PLAY! buzzed the phone
-- the instant the game was pressed into life -- a stray jolt on a screen that is meant to feel calm.
playBtn:SetAttribute("NoHaptic", true)
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

-- ROTATING TIPS + PROGRESS HELPER: REMOVED along with the bar they annotated.
--
-- The PLAY gate used to be "loadingPct == 100", i.e. a number the bar itself set. With no bar there is no
-- percentage to gate on, so the gate is now the two real conditions it was always standing in for:
-- the intro has finished playing, and the asset preload has finished. Both are set at the bottom of the
-- file; revealPlay() refuses to fire until both are true (or the hard failsafe trips).
local introDone = false

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
-- Same treatment as the loading background: painted immediately so it can never render as a hole while its
-- image is still fetching. This one is Visible = false at boot, but it is revealed the instant the player
-- reaches the island picker, and its asset resolved even later than the first one on the last boot.
-- Flat colour only, for the same reason as the loading background above: a UIGradient on an ImageLabel
-- tints the Image, not just the fill.
menuBg.BackgroundTransparency = 0
menuBg.BackgroundColor3 = Color3.fromRGB(135, 206, 250)
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
	-- Decide this on STATE (island 1, intro not yet seen), NOT on whether _G.startGardenIntro happens to be
	-- assigned at this instant. GardenIntro publishes that global near the END of its own script, so a fast
	-- click could arrive first -- and the old `type(...) == "function"` test then sent us down the fade path,
	-- which both flashed the world AND skipped the cinematic, since the server's fallback trigger only fires
	-- later. Committing on state and waiting a moment for the function is correct in both orders.
	local introStarting = (n == 1 and player:GetAttribute("SeenGardenIntro") ~= true)
	if introStarting then
		print("ISLAND MENU: first-time island 1 -> starting garden cinematic (black transition) immediately")
		task.spawn(function()
			local t = os.clock()
			while type(_G.startGardenIntro) ~= "function" and os.clock() - t < 2 do task.wait() end
			if type(_G.startGardenIntro) == "function" then
				_G.startGardenIntro()
			else
				warn("[LOADINGSCREEN] _G.startGardenIntro never appeared -- the cover wait below will time out and fade normally")
			end
		end)
	end

	if introStarting then
		-- STEP 1 -- OUR OWN BLACK, INSTANTLY, BEFORE ANYTHING ELSE.
		-- Everything below waits on the cinematic, and waiting means frames. So the very first thing that
		-- happens on the click is that WE paint the screen black ourselves, with no tween and no yield. From
		-- this instant the world is unreachable no matter what the intro does, how slow the server spawn is,
		-- or whether the intro script exists at all. Every other guard here is now just about deciding when it
		-- is safe to take this away again -- not about whether the player can see through.
		local blackout = Instance.new("Frame")
		blackout.Name = "HandoffBlack"
		blackout.Size = UDim2.fromScale(1, 1)
		blackout.Position = UDim2.fromScale(0, 0)
		blackout.BackgroundColor3 = Color3.new(0, 0, 0)
		blackout.BackgroundTransparency = 0
		blackout.BorderSizePixel = 0
		blackout.ZIndex = 100000          -- above root (1) and both backgrounds (0)
		blackout.Parent = gui

		-- HANDOFF, NOT A FADE.
		-- This used to fade the whole loading screen (background image included) to transparent over 0.45s and
		-- destroy it at 0.5s, on a timer, whether or not the cinematic had put its black up yet. The intro is a
		-- separate script that has to build its cover and wait on the character spawning -- the boot log showed
		-- the server not confirming the spawn until ~0.9s after PLAY -- so for a moment the screen was fading
		-- through to the live world. That is the split-second of "actually in game" before the intro.
		--
		-- GardenIntro's cover (GardenIntroCover, DisplayOrder 1500000, BackgroundTransparency 0) sits ABOVE this
		-- ScreenGui, so the correct move is to not fade at all: stay fully opaque, let the intro's black land on
		-- top of us, and only then destroy -- underneath something already opaque, where it cannot be seen.
		-- The result is opaque -> opaque with no frame of world in between.
		task.spawn(function()
			local t0 = os.clock()

			-- STEP 2 -- wait for the cover to be REAL, not merely to exist.
			-- GardenIntro parents the ScreenGui first and its black Frame on the NEXT line, so there is a window
			-- where GardenIntroCover exists and is completely empty. Removing our black during that window is
			-- exactly the flash we are trying to kill, so test for an actually-opaque full-screen child instead
			-- of just the container.
			local function coverIsPainted()
				local cover = playerGui:FindFirstChild("GardenIntroCover")
				if not (cover and cover.Enabled) then return false end
				for _, d in ipairs(cover:GetDescendants()) do
					if d:IsA("GuiObject") and d.Visible and d.BackgroundTransparency <= 0.02
						and d.AbsoluteSize.X >= workspace.CurrentCamera.ViewportSize.X * 0.9
						and d.AbsoluteSize.Y >= workspace.CurrentCamera.ViewportSize.Y * 0.9 then
						return true
					end
				end
				return false
			end

			local painted = false
			repeat
				painted = coverIsPainted()
				if painted then break end
				task.wait()
			until os.clock() - t0 > 3   -- bounded: if the intro never appears we must not strand the player here

			if painted then
				-- STEP 3 -- let it actually DRAW before we get out of the way.
				-- The cover existing and the cover having been rendered are different things; a Frame created
				-- this frame is not on screen until the next one. Yielding two render frames means the intro's
				-- black is provably on the display before ours disappears, which removes the last one-frame gap.
				local RunService = game:GetService("RunService")
				RunService.RenderStepped:Wait()
				RunService.RenderStepped:Wait()

				gui:Destroy()   -- covered from above by a cover we have SEEN painted; removal is invisible
				print(("[LOADINGSCREEN] handed off to the intro cover after %.2fs -- black-to-black, no world frame"):format(os.clock() - t0))
			else
				-- Intro never came up. Fall back to the original behaviour rather than sitting on a dead screen.
				-- The blackout MUST be faded too: it is opaque and above everything else here, so fading only
				-- root/bg/menuBg would leave the player staring at a black screen forever instead of the game.
				warn(("[LOADINGSCREEN] GardenIntroCover never appeared (%.1fs) -- fading out normally instead"):format(os.clock() - t0))
				TweenService:Create(blackout, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {BackgroundTransparency = 1}):Play()
				TweenService:Create(root,   TweenInfo.new(0.45, Enum.EasingStyle.Quad), {GroupTransparency = 1}):Play()
				fadeBg(bg, 0.45)
				fadeBg(menuBg, 0.45)
				task.delay(0.5, function() gui:Destroy() end)
			end
		end)
	else
		-- No cinematic (returning player): unchanged -- fade the screen out into the game.
		TweenService:Create(root, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {GroupTransparency = 1}):Play()
		fadeBg(bg, 0.45)       -- loading bg (outside CanvasGroup, so it never sees GroupTransparency)
		fadeBg(menuBg, 0.45)   -- menu bg (same)
		task.delay(0.5, function() gui:Destroy() end)
	end
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
	fadeBg(bg, 0.45)
	fadeBg(dinoBg, 0.45)
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
	titleLabel.Visible = false
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
	-- HARD GATE: the PLAY button may ONLY appear once the studio intro has actually finished. An accidental
	-- early call returns WITHOUT consuming the once-guard, so the real reveal can still happen later. (The
	-- failsafe at the bottom sets introDone itself before calling, so it can never be blocked by this.)
	if not introDone then return end
	if playRevealed then return end      -- already revealed once — never double-fire
	playRevealed = true
	print("[LOADINGSCREEN] revealPlay fired via " .. tostring(reason or "NORMAL path"))

	-- The play screen: picture, title, button. With the studio splash ON, the splash ran on black over the
	-- top of all of it and this was the moment the background first became visible. With it OFF the photo
	-- has been up the whole time (that is the point of the restored screen) and these two lines are simply
	-- a no-op re-assert -- kept, not deleted, so flipping SHOW_STUDIO_INTRO back on still works unchanged.
	bg.Visible = true
	bg.ImageTransparency = 0

	-- The loading is over: the bar has said everything it had to say and a full bar under a PLAY button is
	-- just clutter. Snap it to 100 first so it is never caught mid-fill on the frame it disappears.
	setLoadingPct(100)
	hideLoadBar()

	-- The photo carries "FART TO FLOAT" in the game's own lettering, so the drawn text title is only used
	-- when there is no photo to carry it. Showing both gives you the title twice, in two different fonts.
	titleLabel.Visible = not SHOW_BG_PHOTO

	-- Restore the transparencies that were forced to 1 at creation (the button was kept BOTH
	-- Visible=false AND fully transparent until now, so it could not render at all before this
	-- reveal). This is the moment — and the only moment — the button becomes visible.
	playBtn.BackgroundTransparency = 0
	playStroke.Transparency = 0
	playLabel.TextTransparency = 0
	playLabelStroke.Transparency = 0
	playShadow.ImageTransparency = 1  -- keep the drop-shadow hidden (it read as a grey box behind PLAY)
	playShadow.Visible = false
	playBtn.Visible = true
	playBtn.Active = true
	-- Title fades up; button pops in from small.
	TweenService:Create(titleLabel, TweenInfo.new(0.35), {TextTransparency = 0}):Play()
	TweenService:Create(titleStroke, TweenInfo.new(0.35), {Transparency = 0}):Play()
	playBtn.Size = UDim2.fromScale(PLAY_W * 0.7, PLAY_H * 0.7)
	scalePlay(1, 0.4)

	-- Idle breathe, so the button reads as the live thing on the screen.
	task.spawn(function()
		task.wait(0.45)
		while playBtn.Parent and playBtn.Active do
			TweenService:Create(playBtn, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{Size = UDim2.fromScale(PLAY_W * 1.04, PLAY_H * 1.04)}):Play()
			task.wait(0.85)
			if not (playBtn.Parent and playBtn.Active) then break end
			TweenService:Create(playBtn, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{Size = UDim2.fromScale(PLAY_W, PLAY_H)}):Play()
			task.wait(0.85)
		end
	end)
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
-- PLAY appears once BOTH (a) the studio splash has finished AND (b) the real asset preload + game.Loaded
-- are done — whichever is LATER. The splash builds in ~1.5s and holds its finished frame to a ~2.8s
-- minimum, so on a fast client that hold is all you see of the wait; on a slow one the same still frame
-- simply holds longer instead of showing a button that isn't backed by loaded assets.
local PRELOAD_TIMEOUT = 11   -- if the preload hasn't finished by now (e.g. it's stuck on an unapproved/bad asset), proceed ANYWAY
local MAX_REVEAL_TIME = 14   -- HARD FAILSAFE: PLAY is force-revealed no later than this, no matter what.
                             -- Must stay above the splash's worst case (MIN_SHOW ~2.8s + its 6s asset
                             -- hold): the failsafe DESTROYS the intro layer, so a value below that would
                             -- execute the splash mid-hold on every slow boot.
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

-- CREEP FLOOR. PreloadAsync can sit on a single stuck asset for seconds, during which the batch callback
-- never fires and the bar does not move -- and a frozen bar is read as a frozen game. So an independent
-- timer raises a FLOOR toward 90% over PRELOAD_TIMEOUT seconds. setLoadingPct is monotonic and takes the
-- higher of the two, so on a normal boot real progress outruns this and the floor is never seen; on a
-- stuck one the bar keeps inching instead of stopping dead. It cannot lie past 90 -- the last stretch is
-- still owned by work actually finishing.
task.spawn(function()
	while not assetsReady and (os.clock() - preloadStart) < PRELOAD_TIMEOUT do
		setLoadingPct(math.min(90, ((os.clock() - preloadStart) / PRELOAD_TIMEOUT) * 90))
		task.wait(0.1)
	end
	setLoadingPct(97) -- assets are in (or gave up): the bar is done, the PLAY gate takes it from here
end)

-- REAL preload (best-effort, underneath). The WHOLE thing is in a pcall so a thrown error can't kill it, and
-- each batch is in its own pcall so one bad asset can't stop the rest. Flips assetsReady when it finishes --
-- but only if the watchdog above hasn't already.
task.spawn(function()
	-- TWO PASSES, and only the FIRST one gates the PLAY button.
	--
	-- This used to be a single sweep of game:GetDescendants() -- every part of all fourteen islands, every pet
	-- model, the lot -- and PLAY waited for the whole thing. But the player lands on island 1 and cannot even
	-- see islands 2-14, so making them wait for those to fetch bought nothing; it was simply the largest part
	-- of the 6.1s the boot log recorded.
	--
	-- Pass 1 is what is actually on screen at PLAY time: the loading screen's own images, Lighting (the sky),
	-- ReplicatedStorage, and island 1. Once that is done the game is genuinely ready to be looked at, so
	-- assetsReady flips and the bar is free to finish.
	-- Pass 2 then sweeps everything else in the background, so nothing ends up LESS preloaded than before --
	-- it just no longer happens in front of a player staring at a full progress bar.
	-- `report` (optional) is called after every batch with the fraction of `list` completed, 0..1. Pass 1
	-- passes one so the restored loading bar fills on REAL work; pass 2 passes nothing, because it runs
	-- behind the player and must never move a bar that has already finished.
	local function preloadAll(list, report)
		local total = #list
		local BATCH = 50
		local i = 0
		while i < total do
			local batch = {}
			for _ = 1, BATCH do
				i = i + 1
				if i > total then break end
				batch[#batch + 1] = list[i]
			end
			pcall(function() ContentProvider:PreloadAsync(batch) end)
			if report then pcall(report, math.min(i, total) / math.max(1, total)) end
			if (os.clock() - preloadStart) > 30 then break end -- absolute cap on the batch loop
		end
	end

	local ok, err = pcall(function()
		-- A bar pinned at 0 while game.Loaded is still pending reads as a hung client, so the two waits
		-- before any asset is fetched get a small floor each. Everything above 15 is measured work.
		setLoadingPct(5)
		if not game:IsLoaded() then game.Loaded:Wait() end
		setLoadingPct(15)

		-- PASS 1 -- on-screen-at-PLAY-time only.
		local first = {}
		local function add(root)
			if not root then return end
			first[#first + 1] = root
			for _, d in ipairs(root:GetDescendants()) do first[#first + 1] = d end
		end
		add(gui)                                        -- our own backgrounds + card art
		add(game:GetService("Lighting"))                -- sky
		add(ReplicatedStorage)
		add(workspace:FindFirstChild("Island_1_BeanFarm"))
		-- 15 -> 97 across the real batches. It stops at 97, not 100: `assetsReady` is what actually opens
		-- the PLAY gate, and a bar that hits 100 a moment before the button appears is the classic "it's
		-- done, why is nothing happening" beat. The last three percent are spent by revealPlay itself.
		preloadAll(first, function(frac) setLoadingPct(15 + frac * 82) end)
		print(("[LOADINGSCREEN] preload pass 1 (screen + island 1, %d assets) done at %.1fs -- PLAY is no longer blocked")
			:format(#first, os.clock() - preloadStart))
	end)
	if not ok then print("[LOADINGSCREEN] preload pcall caught error: " .. tostring(err)) end
	if not assetsReady then
		assetsReady = true
		print(string.format("[LOADINGSCREEN] preload finished (or timed out after %.1fs)", os.clock() - preloadStart))
	end

	-- PASS 2 -- the rest of the game, behind the player. Nothing waits on this, and it passes NO progress
	-- reporter: the bar is finished by now and must not be dragged back into motion behind a PLAY button.
	task.spawn(function()
		pcall(function() preloadAll(game:GetDescendants()) end)
	end)
end)

--======================================================================
-- SPLASH OFF -> THE PHOTO AND THE BAR ARE THE WHOLE LOADING SCREEN
--======================================================================
-- `introDone` exists to stop PLAY appearing while the studio splash is still playing. With the splash
-- switched off there is no splash to wait for, so the gate is satisfied immediately and PLAY is left
-- depending on the one condition that actually matters: the assets being ready.
--
-- Everything below this block is skipped by the `if SHOW_STUDIO_INTRO` guard on the build coroutine -- the
-- splash's ~700 lines still compile and are still correct, they simply never run. That is why this is a
-- switch and not a deletion: flip SHOW_STUDIO_INTRO back to true and the splash returns intact.
if not SHOW_STUDIO_INTRO then
	introDone = true
	task.spawn(function()
		-- Wait for the assets, then hand straight over. No minimum hold: the player has been looking at the
		-- picture and a filling bar the whole time, so there is nothing left to give them a moment to read.
		local t0 = os.clock()
		while not assetsReady and (os.clock() - t0) < MAX_REVEAL_TIME do task.wait(0.05) end
		revealPlay("photo + loading bar (studio splash off)")
	end)
	print("[LOADINGSCREEN] ORIGINAL SCREEN RESTORED -- full-screen background photo (" ..
		"rbxassetid://127983055545494) + the simple % loading bar, driven by real preload progress. " ..
		"The MLR STUDIOS splash is switched OFF (SHOW_STUDIO_INTRO=false), not deleted.")
end

-- ====================================================================================================
-- ===== STUDIO INTRO =================================================================================
-- ====================================================================================================
-- The MLR STUDIOS splash, built to match the reference image checked in at the repo root as
-- "intro image refrence.png" — that file is the design spec for this block. Layout numbers in here are
-- MEASURED off it (positions as fractions of its 16:9 frame, colours sampled from it), so if a value
-- looks oddly specific, it is: it came from the picture.
--
--   crown-M emblem (centre y 0.235) -> "BROUGHT TO YOU BY", wide-tracked, gold rules either side
--   (y 0.37) -> the MLR STUDIOS wordmark as the dominant element (y 0.53, ~3/4 of the screen wide,
--   MLR gold and a step taller than the white STUDIOS) -> angular gold corner frame -> SKIP pill
--   bottom-right. Near-black ground, warm glow behind the title, diagonal gold streaks.
--
-- The build animation runs ~1.5s, then the finished frame HOLDS (skippable) until the preload is done
-- and hands over to the PLAY screen. No camera moves, no bounces — the reference is a still, so the
-- animation's whole job is to assemble that still and then respect it.
local RunService = game:GetService("RunService")

-- Palette — sampled from the reference, not guessed.
local GOLD      = Color3.fromRGB(255, 200, 46)    -- bright gold (title top, frame, accents)
local GOLD_DEEP = Color3.fromRGB(242, 158, 18)    -- the orange the gold gradients fall into
local WHITE_HI  = Color3.fromRGB(255, 255, 255)   -- STUDIOS top
local WHITE_LO  = Color3.fromRGB(199, 203, 217)   -- STUDIOS' cool grey lower half
local INK       = Color3.fromRGB(24, 25, 33)      -- the dark navy-black every outline uses
local GROUND    = Color3.fromRGB(14, 12, 9)       -- near-black base
local ALLOW_SKIP = true

-- Build timeline — absolute seconds from the intro's first frame.
local T_DECOR  = 0.00
local T_EMBLEM = 0.10
local T_SUB    = 0.40
local T_LINES  = 0.50
local T_TITLE  = 0.65
local T_SETTLE = 1.30
local MIN_SHOW = 2.80      -- the splash never flashes past faster than this, even on instant loads

-- ===== GROUND =====
local introLayer = Instance.new("Frame")
introLayer.Name = "StudioIntro"
introLayer.Size = UDim2.fromScale(1, 1)
introLayer.Position = UDim2.fromScale(0, 0)
introLayer.BackgroundColor3 = GROUND
introLayer.BorderSizePixel = 0
introLayer.ZIndex = 5000
do
	-- The reference's ambient warmth: a faint brown-gold lift toward the centre-low region where the
	-- title glow lives. Multiplies the base colour, so the handover fade needs no special handling.
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(235, 232, 226)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(228, 220, 200)),
	})
	g.Parent = introLayer
end
-- NOT PARENTED WHEN THE SPLASH IS OFF. This layer sits at ZIndex 5000 and covers the whole screen, so
-- parenting it unconditionally would hide the restored photo and bar behind a near-black rectangle for the
-- entire load. Left unparented it renders nothing and costs nothing, and every later `if introLayer.Parent`
-- guard (the handover and the failsafe both use one) already reads correctly as "nothing to tear down".
if SHOW_STUDIO_INTRO then
	introLayer.Parent = gui
end

-- Decorative Frames register with their RESTING transparency; one loop fades them all in at the start
-- and out at the handover.
local decor = {}
local function reg(obj, rest)
	obj.BackgroundTransparency = 1
	decor[#decor + 1] = { obj = obj, rest = rest }
	return obj
end

-- ===== BACKDROP: SLABS + STREAKS =====
-- The reference's ground is not flat black: dark charcoal slabs cut diagonally through it, and long
-- gold light-streaks rake across the lower-left and upper-right at ~35°. All of it stays out of the
-- centre band where the type lives.
do
	local function panel(x, y, w, h, rot, color, rest, z)
		local p = Instance.new("Frame")
		p.Name = "Backdrop"
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.fromScale(x, y)
		p.Size = UDim2.fromScale(w, h)
		p.Rotation = rot
		p.BackgroundColor3 = color
		p.BorderSizePixel = 0
		p.ZIndex = z or 5001
		p.Parent = introLayer
		return reg(p, rest)
	end
	local CHARCOAL2 = Color3.fromRGB(31, 28, 22)
	-- Big soft slabs, corner-weighted.
	panel(0.10, 0.88, 0.70, 0.38, -35, CHARCOAL2, 0.55)
	panel(0.92, 0.12, 0.60, 0.30, -35, CHARCOAL2, 0.62)
	-- The light streaks: long thin gold bars, faded along their length so the ends dissolve instead of
	-- stopping. Same 35° rake as the slabs — one diagonal grammar for the whole backdrop.
	local function streak(x, y, len, th, rest)
		local s = panel(x, y, len, th, -35, GOLD, rest, 5002)
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = s
	end
	streak(0.13, 0.80, 0.55, 0.012, 0.72)
	streak(0.07, 0.90, 0.40, 0.006, 0.68)
	streak(0.88, 0.22, 0.45, 0.010, 0.74)
	streak(0.94, 0.34, 0.30, 0.005, 0.70)
end

-- ===== ANGULAR GOLD FRAME =====
-- The reference border is corner-weighted esports framing, not a hairline box: chunky gold bars and a
-- 45°-rotated wedge at each corner (with a dark ink stroke separating gold from ground), thinning into
-- faint strips along the edges, with the centres of all four edges left open.
do
	local function bar(pos, size, rest, withInk)
		local b = Instance.new("Frame")
		b.Name = "FrameBar"
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = pos
		b.Size = size
		b.BackgroundColor3 = GOLD
		b.BorderSizePixel = 0
		b.ZIndex = 5058
		if withInk then
			local s = Instance.new("UIStroke")
			s.Color = INK; s.Thickness = 2
			s.Parent = b
		end
		b.Parent = introLayer
		return reg(b, rest)
	end
	-- One corner: a thick horizontal bar and a thick vertical bar meeting at the corner, plus the
	-- rotated wedge poking in at 45°. sx/sy = which corner (+1 = left/top edge, -1 = right/bottom).
	local function corner(cx, cy, sx, sy)
		bar(UDim2.new(cx, sx * 90,  cy, sy * 8),  UDim2.new(0.115, 0, 0, 13), 0.08, true)   -- along the top/bottom
		bar(UDim2.new(cx, sx * 6,   cy, sy * 80), UDim2.new(0, 11, 0.105, 0), 0.08, true)   -- along the side
		local wedge = bar(UDim2.new(cx, sx * 26, cy, sy * 26), UDim2.new(0, 34, 0, 34), 0.05, true)
		wedge.Rotation = 45
		-- The fading continuation strips that reach toward the open edge centres.
		bar(UDim2.new(cx, sx * 250, cy, sy * 6),  UDim2.new(0.14, 0, 0, 4), 0.55, false)
		bar(UDim2.new(cx, sx * 4,   cy, sy * 210), UDim2.new(0, 4, 0.10, 0), 0.55, false)
	end
	corner(0, 0,  1,  1)
	corner(1, 0, -1,  1)
	corner(0, 1,  1, -1)
	corner(1, 1, -1, -1)
end

-- ===== VIGNETTE =====
-- Kept extremely subtle: the reference's edges darken a little, nothing more.
do
	local function edge(anchor, pos, size, rot)
		local f = Instance.new("Frame")
		f.Name = "Vignette"
		f.AnchorPoint = anchor
		f.Position = pos
		f.Size = size
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.ZIndex = 5040
		local g = Instance.new("UIGradient")
		g.Rotation = rot
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		f.Parent = introLayer
		reg(f, 0.4)
	end
	edge(Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.18), 90)
	edge(Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.fromScale(1, 0.18), 270)
	edge(Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.14, 1), 0)
	edge(Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.14, 1), 180)
end

-- ===== PARTICLES =====
-- Sparse gold motes on a very slow parallax drift — the only thing that keeps moving after the build.
-- Starts FALSE when the splash is switched off, so the per-frame drift loop below exits on its first
-- check instead of animating motes inside an unparented layer nobody can see.
local introAlive = SHOW_STUDIO_INTRO
local dust = {}
do
	for i = 1, 24 do
		local f = Instance.new("Frame")
		f.Name = "Mote" .. i
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = GOLD
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.ZIndex = 5003
		do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = f end
		f.Parent = introLayer
		dust[i] = {
			f = f,
			x = math.random(), y = math.random(),
			z = 0.2 + math.random() * 0.8,
			vx = (math.random() - 0.5) * 0.008,
			vy = (math.random() - 0.5) * 0.005,
			tw = math.random() * math.pi * 2,
		}
	end
	task.spawn(function()
		local last = os.clock()
		local born = last
		while introAlive do
			local now = os.clock()
			local dt = math.min(now - last, 0.1)
			last = now
			local fadeIn = math.clamp((now - born) / 1.0, 0, 1)
			local vp = workspace.CurrentCamera.ViewportSize
			for _, d in ipairs(dust) do
				d.x = (d.x + d.vx * d.z * dt) % 1
				d.y = (d.y + d.vy * d.z * dt) % 1
				d.tw = d.tw + dt * 1.6
				local px = math.max(d.z * (vp.Y / 900) * 2.6, 1)
				d.f.Size = UDim2.fromOffset(px, px)
				d.f.Position = UDim2.fromScale(d.x, d.y)
				local vis = d.z * (0.36 + 0.14 * math.sin(d.tw)) * fadeIn
				d.f.BackgroundTransparency = math.clamp(1 - vis, 0.5, 1)
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

-- ===== TITLE GLOW =====
-- The warm illumination radiating from behind the wordmark in the reference — the soft-shadow 9-slice
-- tinted gold, falling off in both axes. Noticeably present, per the picture, but still an underlight.
local titleGlow = Instance.new("ImageLabel")
titleGlow.Name = "TitleGlow"
titleGlow.AnchorPoint = Vector2.new(0.5, 0.5)
titleGlow.Position = UDim2.fromScale(0.5, 0.5)
titleGlow.Size = UDim2.fromScale(1.05, 0.62)
titleGlow.BackgroundTransparency = 1
titleGlow.Image = SHADOW_IMG
titleGlow.ImageColor3 = Color3.fromRGB(200, 150, 40)
titleGlow.ImageTransparency = 1
titleGlow.ScaleType = Enum.ScaleType.Slice
titleGlow.SliceCenter = Rect.new(10, 10, 118, 118)
titleGlow.ZIndex = 5004
titleGlow.Parent = introLayer
local GLOW_REST = 0.82

-- ===== EMBLEM: THE CROWN-M =====
-- The reference mark is an angular M whose three peaks read as a crown, the centre one tallest. It is
-- rebuilt here as six thick gold segments — two per peak — each with a gold-to-orange vertical gradient
-- and an ink outline, the whole mark duplicated once in dark gold 4px lower for depth, with a soft halo
-- behind. A CanvasGroup so it enters and exits as one object.
--
-- NOTE: this is the best pure-UI approximation of a drawn logo. If pixel-exact matters later, export
-- the emblem from the reference as an image asset and swap it in — one ImageLabel replaces this block.
local emblem = Instance.new("CanvasGroup")
emblem.Name = "Emblem"
emblem.AnchorPoint = Vector2.new(0.5, 0.5)
emblem.Position = UDim2.fromScale(0.5, 0.235)   -- measured: emblem centre sits at y 0.235
emblem.Size = UDim2.fromScale(0.15, 0.16)
emblem.BackgroundTransparency = 1
emblem.GroupTransparency = 1
emblem.ZIndex = 5007
do
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1.5; ar.DominantAxis = Enum.DominantAxis.Height   -- the mark is half again wider than tall
	ar.Parent = emblem
end
emblem.Parent = introLayer
do
	local halo = Instance.new("ImageLabel")
	halo.Name = "Halo"
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Position = UDim2.fromScale(0.5, 0.5)
	halo.Size = UDim2.fromScale(2.0, 2.0)
	halo.BackgroundTransparency = 1
	halo.Image = SHADOW_IMG
	halo.ImageColor3 = Color3.fromRGB(255, 190, 60)
	halo.ImageTransparency = 0.82
	halo.ScaleType = Enum.ScaleType.Slice
	halo.SliceCenter = Rect.new(10, 10, 118, 118)
	halo.ZIndex = 5007
	halo.Parent = emblem

	-- Segment layout, hand-tuned in the 1.5:1 box: outer strokes lean out, inner strokes dive to the
	-- valleys, centre pair rises above the outer peaks. yOffsetPx separates the ink layer from the face.
	local SEGS = {
		-- x, y, w, h, rotation
		{0.095, 0.56, 0.15, 0.82,  -14},   -- left outer, up to the left peak
		{0.295, 0.62, 0.15, 0.68,   18},   -- left peak down into the left valley
		{0.435, 0.47, 0.15, 0.94,  -12},   -- valley up to the CROWN peak
		{0.565, 0.47, 0.15, 0.94,   12},   -- crown peak down to the right valley
		{0.705, 0.62, 0.15, 0.68,  -18},   -- right valley up to the right peak
		{0.905, 0.56, 0.15, 0.82,   14},   -- right outer
	}
	local function mLayer(bright, deep, yOffsetPx, withStroke, z)
		local layer = Instance.new("Frame")
		layer.Name = withStroke and "Face" or "Ink"
		layer.AnchorPoint = Vector2.new(0.5, 0.5)
		layer.Position = UDim2.new(0.5, 0, 0.5, yOffsetPx)
		layer.Size = UDim2.fromScale(1, 1)
		layer.BackgroundTransparency = 1
		layer.ZIndex = z
		layer.Parent = emblem
		for _, sdef in ipairs(SEGS) do
			local b = Instance.new("Frame")
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.Position = UDim2.fromScale(sdef[1], sdef[2])
			b.Size = UDim2.fromScale(sdef[3], sdef[4])
			b.Rotation = sdef[5]
			b.BackgroundColor3 = bright
			b.BorderSizePixel = 0
			b.ZIndex = z
			do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.18, 0); c.Parent = b end
			do
				local g = Instance.new("UIGradient")
				g.Rotation = 90
				g.Color = ColorSequence.new(bright, deep)
				g.Parent = b
			end
			if withStroke then
				local s = Instance.new("UIStroke")
				s.Color = INK; s.Thickness = 2.5; s.LineJoinMode = Enum.LineJoinMode.Round
				s.Parent = b
			end
			b.Parent = layer
		end
	end
	mLayer(Color3.fromRGB(120, 78, 12), Color3.fromRGB(80, 52, 8), 4, false, 5008)   -- ink depth
	mLayer(GOLD, GOLD_DEEP, 0, true, 5009)                                            -- gold face
end

-- ===== "BROUGHT TO YOU BY" =====
-- Wide-tracked like the reference. The tracking is done by literally spacing the string — with
-- TextScaled and a fixed box this renders evenly and needs no per-character layout to go wrong.
local subtitle = Instance.new("TextLabel")
subtitle.Name = "BroughtToYouBy"
subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
subtitle.Position = UDim2.fromScale(0.5, 0.37)   -- measured: the credit line sits at y 0.37
subtitle.Size = UDim2.fromScale(0.44, 0.034)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.GothamBold
subtitle.Text = "B R O U G H T   T O   Y O U   B Y"
subtitle.TextColor3 = WHITE_HI
subtitle.TextScaled = true
subtitle.TextTransparency = 1
subtitle.ZIndex = 5006
subtitle.Parent = introLayer

-- The gold rules: long and tapered, inner ends at x 0.27 / 0.73 (clear of the text), dissolving
-- outward toward x ~0.135 / 0.865 — all measured off the reference.
local function accentLine(anchorX, posX, fadeOutward)
	local ln = Instance.new("Frame")
	ln.Name = "AccentLine"
	ln.AnchorPoint = Vector2.new(anchorX, 0.5)
	ln.Position = UDim2.fromScale(posX, 0.37)
	ln.Size = UDim2.new(0, 0, 0, 3)
	ln.BackgroundColor3 = GOLD
	ln.BackgroundTransparency = 0.15
	ln.BorderSizePixel = 0
	ln.ZIndex = 5006
	local g = Instance.new("UIGradient")
	-- Solid at the text end, dissolved at the outer end.
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, fadeOutward and 1 or 0),
		NumberSequenceKeypoint.new(1, fadeOutward and 0 or 1),
	})
	g.Parent = ln
	ln.Parent = introLayer
	return ln
end
local lineL = accentLine(1, 0.27, true)    -- grows leftward; left end (gradient 0) dissolves
local lineR = accentLine(0, 0.73, false)   -- grows rightward; right end (gradient 1) dissolves

-- ===== THE WORDMARK =====
-- Two labels, not one: the reference sets MLR a step TALLER than STUDIOS, and no single text run can
-- size its spans independently. Each word carries its own gradient (gold->orange vs white->cool grey),
-- its own thick ink stroke, and its own two shadow layers — a hard extrusion just below (the chunky 3D
-- depth) and a softer, farther drop under that. MLR also carries the reference's slight playful cant.
local titleWrap = Instance.new("Frame")
titleWrap.Name = "TitleWrap"
titleWrap.AnchorPoint = Vector2.new(0.5, 0.5)
titleWrap.Position = UDim2.fromScale(0.5, 0.53)   -- measured: wordmark centre at y 0.53
titleWrap.Size = UDim2.fromScale(0.78, 0.235)     -- measured: ~3/4 of the screen wide, 0.235 tall
titleWrap.BackgroundTransparency = 1
titleWrap.ZIndex = 5010
titleWrap.Parent = introLayer
local titleScale = Instance.new("UIScale")
titleScale.Scale = 1.08
titleScale.Parent = titleWrap

-- Everything that fades in/out with the title registers here so the build and handover can treat the
-- whole wordmark as one thing.
local titleTexts = {}     -- TextLabels: fade via TextTransparency (with per-label resting values)
local titleStrokes = {}   -- UIStrokes: fade via Transparency

-- One word of the mark: main glyphs + extrusion + soft drop, stacked in its own container.
local function makeWord(name, text, xAnchor, xPos, yPos, wScale, hScale, rot, topColor, bottomColor)
	local box = Instance.new("Frame")
	box.Name = name
	box.AnchorPoint = Vector2.new(xAnchor, 0.5)
	box.Position = UDim2.fromScale(xPos, yPos)
	box.Size = UDim2.fromScale(wScale, hScale)
	box.BackgroundTransparency = 1
	box.Rotation = rot
	box.ZIndex = 5010
	box.Parent = titleWrap

	local function lbl(n, color, yOff, z, rest)
		local l = Instance.new("TextLabel")
		l.Name = n
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.new(0.5, 0, 0.5, yOff)
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.FredokaOne
		l.Text = text
		l.TextColor3 = color
		l.TextScaled = true
		l.TextTransparency = 1
		l.ZIndex = z
		l.Parent = box
		titleTexts[#titleTexts + 1] = { obj = l, rest = rest }
		return l
	end
	-- Soft drop farthest back, hard extrusion above it, glyphs on top. The extrusion is nearly opaque
	-- ink — it IS the "chunky 3D" edge; the drop is loose and translucent.
	lbl("Drop", Color3.new(0, 0, 0), 14, 5010, 0.75)
	lbl("Extrude", INK, 6, 5011, 0.05)
	local main = lbl("Main", topColor, 0, 5012, 0)
	do
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.0, topColor),
			ColorSequenceKeypoint.new(0.45, topColor),
			ColorSequenceKeypoint.new(1.0, bottomColor),
		})
		g.Parent = main
	end
	local st = Instance.new("UIStroke")
	st.Color = INK
	st.Thickness = 4
	st.LineJoinMode = Enum.LineJoinMode.Round
	st.Transparency = 1
	st.Parent = main
	titleStrokes[#titleStrokes + 1] = st
	return box
end

-- Measured split: MLR fills the left ~36% of the wrap at full height with a slight counter-clockwise
-- cant; STUDIOS fills the right ~60% at 82% height, dead level, both bottoms landing together.
makeWord("MLR",     "MLR",     0, 0.00, 0.48, 0.36, 1.00, -2.5, GOLD, GOLD_DEEP)
makeWord("Studios", "STUDIOS", 1, 1.00, 0.55, 0.60, 0.82, 0,    WHITE_HI, WHITE_LO)

-- ===== SOUND =====
local function tone(pitch, vol)
	pcall(function()
		local s = uiClickSound:Clone()
		s.Volume = vol or 0.3
		s.PlaybackSpeed = pitch or 0.6
		s.Parent = playerGui
		s:Play()
		game:GetService("Debris"):AddItem(s, 3)
	end)
end

-- ===== SKIP =====
local skipped = false
local skipBtn, skipStroke
if ALLOW_SKIP then
	-- Matched to the reference: solid near-black pill, gold border, white SKIP with a gold triangle,
	-- right edge at x 0.968, centre at y 0.857, and larger than a caption — it is a real control.
	skipBtn = Instance.new("TextButton")
	skipBtn.Name = "SkipIntro"
	skipBtn.AnchorPoint = Vector2.new(1, 0.5)
	skipBtn.Position = UDim2.fromScale(0.968, 0.857)
	skipBtn.Size = UDim2.new(0.115, 24, 0.062, 16)   -- scale + pixel floor: stays tappable on phones
	skipBtn.BackgroundColor3 = Color3.fromRGB(28, 26, 23)
	skipBtn.BackgroundTransparency = 1
	skipBtn.Font = Enum.Font.GothamBold
	skipBtn.RichText = true
	skipBtn.Text = 'SKIP <font color="#FFC82E">\xE2\x96\xB6</font>'
	skipBtn.TextColor3 = WHITE_HI
	skipBtn.TextScaled = true
	skipBtn.TextTransparency = 1
	skipBtn.AutoButtonColor = false
	skipBtn.Visible = false
	skipBtn.ZIndex = 5070
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = skipBtn end
	do
		local p = Instance.new("UIPadding")
		p.PaddingTop = UDim.new(0, 9); p.PaddingBottom = UDim.new(0, 9)
		p.PaddingLeft = UDim.new(0, 16); p.PaddingRight = UDim.new(0, 16)
		p.Parent = skipBtn
	end
	skipStroke = Instance.new("UIStroke")
	skipStroke.Color = GOLD
	skipStroke.Thickness = 2.5
	skipStroke.Transparency = 1
	skipStroke.Parent = skipBtn
	local skipScale = Instance.new("UIScale"); skipScale.Parent = skipBtn
	skipBtn.Parent = introLayer

	-- Hover: slightly bigger, slightly brighter, smoothly — the design itself does not change.
	skipBtn.MouseEnter:Connect(function()
		if skipped then return end
		TweenService:Create(skipScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {Scale = 1.05}):Play()
		TweenService:Create(skipBtn, TweenInfo.new(0.12), {BackgroundTransparency = 0}):Play()
		TweenService:Create(skipStroke, TweenInfo.new(0.12), {Transparency = 0}):Play()
	end)
	skipBtn.MouseLeave:Connect(function()
		if skipped then return end
		TweenService:Create(skipScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Scale = 1}):Play()
		TweenService:Create(skipBtn, TweenInfo.new(0.15), {BackgroundTransparency = 0.05}):Play()
		TweenService:Create(skipStroke, TweenInfo.new(0.15), {Transparency = 0.1}):Play()
	end)
	skipBtn.Activated:Connect(function()
		if skipped then return end
		skipped = true
		playUIClick()
	end)
end

-- ===== THE BUILD =====
-- Guarded, not deleted. With SHOW_STUDIO_INTRO off this coroutine returns on its first line: the splash
-- never assembles, never holds, and never hands over -- the photo-and-bar block further up owns the reveal
-- instead. Flip the switch back and this runs exactly as it did before, untouched.
task.spawn(function()
	if not SHOW_STUDIO_INTRO then return end
	local introStart = os.clock()
	local function waitUntil(offset)
		while not skipped do
			local remain = offset - (os.clock() - introStart)
			if remain <= 0 then return true end
			task.wait(math.min(remain, 0.05))
		end
		return false
	end

	local function build()
		-- 1) The ground dressing fades to its resting values.
		if not waitUntil(T_DECOR) then return end
		for _, d in ipairs(decor) do
			TweenService:Create(d.obj, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {BackgroundTransparency = d.rest}):Play()
		end
		TweenService:Create(titleGlow, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {ImageTransparency = GLOW_REST}):Play()

		-- 2) The crown settles in from slightly small — eased, never bounced.
		if not waitUntil(T_EMBLEM) then return end
		tone(0.5, 0.2)
		emblem.Size = UDim2.fromScale(0.128, 0.136)
		TweenService:Create(emblem, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{GroupTransparency = 0, Size = UDim2.fromScale(0.15, 0.16)}):Play()

		-- 3) The credit line.
		if not waitUntil(T_SUB) then return end
		TweenService:Create(subtitle, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {TextTransparency = 0}):Play()

		-- 4) The rules extend outward from beside it, to their measured length.
		if not waitUntil(T_LINES) then return end
		TweenService:Create(lineL, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{Size = UDim2.new(0.135, 0, 0, 3)}):Play()
		TweenService:Create(lineR, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{Size = UDim2.new(0.135, 0, 0, 3)}):Play()

		-- 5) The wordmark: fade + a shallow scale-down onto its mark, all layers together.
		if not waitUntil(T_TITLE) then return end
		tone(0.72, 0.28)
		TweenService:Create(titleScale, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Scale = 1}):Play()
		for _, t in ipairs(titleTexts) do
			TweenService:Create(t.obj, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {TextTransparency = t.rest}):Play()
		end
		for _, s in ipairs(titleStrokes) do
			TweenService:Create(s, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {Transparency = 0}):Play()
		end
		if ALLOW_SKIP and skipBtn then
			task.delay(0.25, function()
				if skipped then return end
				skipBtn.Visible = true
				TweenService:Create(skipBtn, TweenInfo.new(0.5), {TextTransparency = 0, BackgroundTransparency = 0.05}):Play()
				TweenService:Create(skipStroke, TweenInfo.new(0.5), {Transparency = 0.1}):Play()
			end)
		end

		-- 6) Settle: one soft bloom of the underlight, and the composition is finished.
		if not waitUntil(T_SETTLE) then return end
		tone(0.9, 0.16)
		titleGlow.ImageTransparency = GLOW_REST - 0.1
		TweenService:Create(titleGlow, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {ImageTransparency = GLOW_REST}):Play()

		-- HOLD the finished frame: minimum display first (skippable), then — if the preload is still
		-- running — up to six more bounded seconds of the same still.
		if not waitUntil(MIN_SHOW) then return end
		while not skipped and not assetsReady and (os.clock() - introStart) < MIN_SHOW + 6 do
			task.wait(0.05)
		end
	end

	build()

	-- ---------- HANDOVER ----------
	local fast = skipped
	introDone = true
	local waitStart = os.clock()
	while not assetsReady and (os.clock() - waitStart) < 6 do task.wait(0.05) end

	revealPlay(fast and "intro skipped" or "intro complete")
	introAlive = false
	local outDur = fast and 0.3 or 0.6
	local function fadeOut(obj, props)
		TweenService:Create(obj, TweenInfo.new(outDur, Enum.EasingStyle.Quad), props):Play()
	end
	fadeOut(introLayer, {BackgroundTransparency = 1})
	for _, d in ipairs(decor) do fadeOut(d.obj, {BackgroundTransparency = 1}) end
	for _, d in ipairs(dust) do fadeOut(d.f, {BackgroundTransparency = 1}) end
	fadeOut(titleGlow, {ImageTransparency = 1})
	fadeOut(emblem, {GroupTransparency = 1})
	fadeOut(subtitle, {TextTransparency = 1})
	fadeOut(lineL, {BackgroundTransparency = 1})
	fadeOut(lineR, {BackgroundTransparency = 1})
	for _, t in ipairs(titleTexts) do fadeOut(t.obj, {TextTransparency = 1}) end
	for _, s in ipairs(titleStrokes) do fadeOut(s, {Transparency = 1}) end
	if skipBtn then
		skipBtn.Active = false
		fadeOut(skipBtn, {TextTransparency = 1, BackgroundTransparency = 1})
		fadeOut(skipStroke, {Transparency = 1})
	end
	task.delay(outDur + 0.1, function()
		if introLayer.Parent then introLayer:Destroy() end
	end)
	print(("[LOADINGSCREEN] studio splash %s after %.2fs (assetsReady=%s)")
		:format(fast and "SKIPPED" or "finished", os.clock() - introStart, tostring(assetsReady)))
end)

-- HARD FAILSAFE: if anything above throws or wedges, the player still gets a PLAY button. It sets
-- introDone itself so revealPlay's gate cannot refuse it, and tears the intro layer down directly.
task.spawn(function()
	local t0 = os.clock()
	while not playRevealed and (os.clock() - t0) < MAX_REVEAL_TIME do task.wait(0.1) end
	if not playRevealed then
		warn(("[LOADINGSCREEN] intro did not hand over within %ds -- force-revealing PLAY"):format(MAX_REVEAL_TIME))
		introDone = true
		revealPlay("FAILSAFE timeout")
		introAlive = false
		if introLayer.Parent then introLayer:Destroy() end
	end
end)
