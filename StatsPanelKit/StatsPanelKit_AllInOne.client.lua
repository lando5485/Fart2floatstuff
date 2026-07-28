--======================================================================
-- StatsPanelKit_AllInOne.client.lua  (LocalScript -- StarterPlayer > StarterPlayerScripts)
--======================================================================
-- EXACT COPY of Fart to Float's RIGHT-SIDE STATS PANEL (RightPanelGui):
--   ⭐ STATS  header
--   🏝️ Island: N
--   🏆 Max Height: N
--   🚀 TO SPACE REALM  progress bar + "Island 7/14 - 50%"
--   ─── divider ───
--   ⚡☁️ MID-AIR  / RECHARGE   39 R$   (freezes you mid-flight while the prompt is up)
--   ⚡   2X POWER / 1 HOUR     59 R$   (live "⚡ 42m 07s" timer replaces the subtitle)
--   🐦💥 BIRD NUKE             79 R$
--
-- Extracted verbatim from src/client/CoreClient.client.lua -- the FINAL in-game
-- look, i.e. the values AFTER both restyle passes run (not the initial build
-- values, which the game overwrites at load).
--
-- SELF-CONTAINED: no CoreClient, no remotes, no _G.foods. Every hook into the
-- rest of the game is guarded, so it works dropped into an empty place and
-- starts showing real numbers the moment those globals/leaderstats exist.
--
-- ┌─ WHAT TO CHANGE PER REALM ────────────────────────────────────────┐
-- │ 1. CONFIG.productIds -- dev products belong to ONE experience.     │
-- │    Fart to Float's ids WILL NOT prompt in another realm.           │
-- │ 2. CONFIG.progress -- the "TO SPACE REALM" bar: label, total, and  │
-- │    which player attribute / leaderstat drives it.                  │
-- │ 3. CONFIG.rows -- icons + labels of the stat rows.                 │
-- │ 4. CONFIG.showImpulseButtons = false for a stats-ONLY panel        │
-- │    (the panel auto-shrinks to just the stats section).             │
-- └────────────────────────────────────────────────────────────────────┘
--======================================================================

local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local MarketplaceService  = game:GetService("MarketplaceService")
local Debris             = game:GetService("Debris")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

--======================================================================
-- CONFIG
--======================================================================
local CONFIG = {
	-- ===== REPLACE THESE PER EXPERIENCE =====
	productIds = {
		MidAirRecharge = 3600303163, -- 39 R$
		TwoXOneHour    = 3600302990, -- 59 R$
		BirdNuke       = 3600303082, -- 79 R$
	},
	prices = { midAir = "39 R$", twoX = "59 R$", birdNuke = "79 R$" },

	showImpulseButtons = true, -- false = STATS only (panel shrinks to 195 tall, no divider/buttons)
	midAirFreezeWhileBuying = true, -- hold the player in place for the whole Robux prompt if airborne

	-- The progress bar at the bottom of the stats section.
	progress = {
		title      = "\xF0\x9F\x9A\x80 TO SPACE REALM", -- 🚀 TO SPACE REALM
		total      = 14,                                -- island count (Pizza Palms = 14)
		attribute  = "HighestIsland",                   -- player attribute the server sets (authoritative)
		leaderstat = "Island",                          -- fallback if the attribute isn't set
		unit       = "Island",                          -- "Island 7/14 - 50%"
		fillColor  = Color3.fromRGB(90,200,120),        -- green while climbing
		doneColor  = Color3.fromRGB(170,110,255),       -- space-purple once the top is reached
	},

	rows = {
		island = "\xF0\x9F\x8F\x9d\xef\xb8\x8f Island: ",  -- 🏝️ Island:
		height = "\xF0\x9F\x8f\x86 Max Height: ",          -- 🏆 Max Height:
	},

	uiClickSound = "rbxassetid://101638558691673", -- volume 0.5
}
local PRODUCT_IDS = CONFIG.productIds
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

--======================================================================
-- GUI HELPERS (verbatim from CoreClient)
--======================================================================
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end

-- ===== UI CLICK SOUND (self-contained, shared via _G) =====
local uiClickSound = Instance.new("Sound")
uiClickSound.Name="UIClickSound_StatsPanel"; uiClickSound.SoundId=CONFIG.uiClickSound; uiClickSound.Volume=0.5; uiClickSound.Parent=PlayerGui
local function playUIClick()
	local s=uiClickSound:Clone(); s.Parent=PlayerGui; s:Play(); Debris:AddItem(s,3)
end
_G.playUIClick = _G.playUIClick or playUIClick

--======================================================================
-- RIGHT PANEL (UNIFIED: STATS + IMPULSE BUTTONS)
-- 230 x 500, anchored TOP-RIGHT at (1,-5,0,85). ScreenGui is IgnoreGuiInset
-- so it lives in full-screen coords, then DeviceSafeInsets adds notch-only
-- clearance (CoreUISafeInsets would push it down under the topbar).
--======================================================================
local rightPanel = Instance.new("Frame")
local rightGui
do
	rightGui = Instance.new("ScreenGui")
	rightGui.Name = "RightPanelGui"; rightGui.ResetOnSpawn = false
	rightGui.IgnoreGuiInset = true; rightGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	rightGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- notch only, no desktop shift
	rightGui.Parent = PlayerGui
	rightPanel.Name = "RightPanel"
	rightPanel.Size = UDim2.new(0,230,0,CONFIG.showImpulseButtons and 500 or 195)
	rightPanel.Position = UDim2.new(1,-5,0,85)
	rightPanel.AnchorPoint = Vector2.new(1,0)
	rightPanel.BackgroundColor3 = Color3.fromRGB(30,140,255) -- FINAL restyled blue
	rightPanel.ZIndex = 3; rightPanel.Parent = rightGui
end
mkCorner(rightPanel,20); mkStroke(rightPanel,Color3.fromRGB(20,60,160),3) -- FINAL: corner 20, dark-blue stroke 3

-- stats section (y=8, height=175)
local statsSection = Instance.new("Frame")
statsSection.Size = UDim2.new(1,-16,0,175); statsSection.Position = UDim2.new(0,8,0,8)
statsSection.BackgroundTransparency = 1; statsSection.Parent = rightPanel

local statsTitle = Instance.new("TextLabel")
statsTitle.Size = UDim2.new(1,-8,0,32); statsTitle.Position = UDim2.new(0,8,0,0)
statsTitle.BackgroundTransparency = 1; statsTitle.Text = "\xe2\xad\x90 STATS"
statsTitle.Font = Enum.Font.GothamBold; statsTitle.TextSize = 20
statsTitle.TextColor3 = Color3.fromRGB(255,220,0) -- FINAL gold (built 255,200,0, restyled to 255,220,0)
statsTitle.TextScaled = true; statsTitle.RichText = false
statsTitle.TextXAlignment = Enum.TextXAlignment.Left; statsTitle.Parent = statsSection

local islandLabel = Instance.new("TextLabel")
islandLabel.Size = UDim2.new(1,0,0,36); islandLabel.Position = UDim2.new(0,0,0,36)
islandLabel.BackgroundTransparency = 1; islandLabel.Text = CONFIG.rows.island .. "1"
islandLabel.Font = Enum.Font.GothamBold; islandLabel.TextSize = 22; islandLabel.TextColor3 = Color3.fromRGB(255,255,255)
islandLabel.TextScaled = true; islandLabel.RichText = false
islandLabel.TextXAlignment = Enum.TextXAlignment.Left; islandLabel.Parent = statsSection

local heightLabel = Instance.new("TextLabel")
heightLabel.Size = UDim2.new(1,0,0,36); heightLabel.Position = UDim2.new(0,0,0,76)
heightLabel.BackgroundTransparency = 1; heightLabel.Text = CONFIG.rows.height .. "0"
heightLabel.Font = Enum.Font.GothamBold; heightLabel.TextSize = 22; heightLabel.TextColor3 = Color3.fromRGB(255,255,255)
heightLabel.TextScaled = true; heightLabel.RichText = false
heightLabel.TextXAlignment = Enum.TextXAlignment.Left; heightLabel.Parent = statsSection

-- NOTE: there used to be a "Farts" stat row here (the 3rd row, y=116). It was REMOVED so "Max Height"
-- is the bottom stat and the rows stay contiguous with no gap. The TotalFartPower leaderstat it read is
-- untouched -- still tracked server-side and still driving flight/power.

-- ===== PROGRESS BAR (bottom of the STATS section) =====
-- "How close am I to the end?" -- the 99%-to-space bar big games show. Driven by the server's
-- authoritative player attribute so it climbs live as new islands are reached, with the leaderstat as
-- a fallback for realms that don't set the attribute.
local P = CONFIG.progress
local spaceRealmTitle = Instance.new("TextLabel")
spaceRealmTitle.Size = UDim2.new(1,0,0,22); spaceRealmTitle.Position = UDim2.new(0,0,0,116)
spaceRealmTitle.BackgroundTransparency = 1; spaceRealmTitle.Text = P.title
spaceRealmTitle.Font = Enum.Font.GothamBold; spaceRealmTitle.TextSize = 16; spaceRealmTitle.TextColor3 = Color3.fromRGB(190,210,255)
spaceRealmTitle.TextScaled = true; spaceRealmTitle.RichText = false
spaceRealmTitle.TextXAlignment = Enum.TextXAlignment.Left; spaceRealmTitle.Parent = statsSection

local spaceBarBG = Instance.new("Frame")
spaceBarBG.Size = UDim2.new(1,-2,0,22); spaceBarBG.Position = UDim2.new(0,0,0,142)
spaceBarBG.BackgroundColor3 = Color3.fromRGB(10,14,36); spaceBarBG.BorderSizePixel = 0; spaceBarBG.ZIndex = 4; spaceBarBG.Parent = statsSection
mkCorner(spaceBarBG, 9); mkStroke(spaceBarBG, Color3.fromRGB(8,10,28), 1)

local spaceFill = Instance.new("Frame")
spaceFill.Size = UDim2.new(0,0,1,0); spaceFill.BackgroundColor3 = P.fillColor; spaceFill.BorderSizePixel = 0; spaceFill.ZIndex = 4; spaceFill.Parent = spaceBarBG
mkCorner(spaceFill, 9)

local spacePctLabel = Instance.new("TextLabel")
spacePctLabel.Size = UDim2.new(1,-8,1,0); spacePctLabel.Position = UDim2.new(0,4,0,0); spacePctLabel.BackgroundTransparency = 1
spacePctLabel.Font = Enum.Font.GothamBold; spacePctLabel.TextSize = 13; spacePctLabel.TextColor3 = Color3.new(1,1,1)
spacePctLabel.TextScaled = true; spacePctLabel.RichText = false; spacePctLabel.ZIndex = 5; spacePctLabel.Parent = spaceBarBG
mkStroke(spacePctLabel, Color3.new(0,0,0), 1)

local function currentProgressValue()
	local v = tonumber(player:GetAttribute(P.attribute))
	if not v and P.leaderstat then
		local ls = player:FindFirstChild("leaderstats") or _G.leaderstats
		local st = ls and ls:FindFirstChild(P.leaderstat)
		if st then v = tonumber(st.Value) end
	end
	return v or 1
end
local function updateSpaceRealmProgress()
	local hi = math.clamp(math.floor(currentProgressValue()), 1, P.total)
	local frac = hi / P.total
	spaceFill.Size = UDim2.new(frac, 0, 1, 0)
	spaceFill.BackgroundColor3 = (hi >= P.total) and P.doneColor or P.fillColor
	spacePctLabel.Text = P.unit .. " " .. hi .. "/" .. P.total .. "  -  " .. math.floor(frac * 100 + 0.5) .. "%"
end
updateSpaceRealmProgress()
player:GetAttributeChangedSignal(P.attribute):Connect(updateSpaceRealmProgress) -- climbs live

--======================================================================
-- IMPULSE BUTTONS  (divider y=187, then 3 buttons at y 197 / 295 / 393)
-- Each button: full width -16, 78 tall (FINAL; built 90 then resized), corner
-- 14, 3px stroke; a 60x60 emoji icon pinned left at x=8 centered vertically,
-- then TITLE (y8) / SUB (y38) / PRICE (y62) stacked at x=76.
-- The button POSITIONS were never re-derived after the 90->78 resize, so the
-- gaps between them are 20px, not 8 -- copied as-is.
--======================================================================
local midAir, twoX, birdNuke
local twoXSub, twoXTimerLabel, twoXTimerText

if CONFIG.showImpulseButtons then
	do -- divider (y=187: 8+175+4)
		local divider = Instance.new("Frame")
		divider.Size = UDim2.new(1,-16,0,2); divider.Position = UDim2.new(0,8,0,187)
		divider.BackgroundColor3 = Color3.fromRGB(255,255,255); divider.BackgroundTransparency = 0.7; divider.Parent = rightPanel
	end

	-- shared builder for the 3 identical-shape impulse buttons
	local function mkImpulseBtn(name, y, bgCol, strokeCol, iconTxt, titleTxt, subTxt, priceTxt)
		local btn = Instance.new("TextButton")
		btn.Name = name; btn.Size = UDim2.new(1,-16,0,78); btn.Position = UDim2.new(0,8,0,y)
		btn.BackgroundColor3 = bgCol; btn.Text = ""; btn.ZIndex = 4; btn.Parent = rightPanel
		mkCorner(btn,14); mkStroke(btn,strokeCol,3)

		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(0,60,0,60); icon.Position = UDim2.new(0,8,0.5,0); icon.AnchorPoint = Vector2.new(0,0.5); icon.BackgroundTransparency = 1
		icon.Text = iconTxt; icon.TextSize = 36; icon.Font = Enum.Font.Gotham
		icon.RichText = false; icon.TextXAlignment = Enum.TextXAlignment.Center; icon.TextYAlignment = Enum.TextYAlignment.Center
		icon.ZIndex = 5; icon.Parent = btn

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1,-76,0,28); title.Position = UDim2.new(0,76,0,8); title.BackgroundTransparency = 1
		title.Text = titleTxt; title.Font = Enum.Font.GothamBold; title.TextSize = 20; title.TextColor3 = Color3.fromRGB(255,255,255)
		title.TextScaled = true; title.RichText = false; title.TextXAlignment = Enum.TextXAlignment.Left; title.TextYAlignment = Enum.TextYAlignment.Center
		title.ZIndex = 5; title.Parent = btn

		local sub
		if subTxt then
			sub = Instance.new("TextLabel")
			sub.Size = UDim2.new(1,-76,0,22); sub.Position = UDim2.new(0,76,0,38); sub.BackgroundTransparency = 1
			sub.Text = subTxt; sub.Font = Enum.Font.Gotham; sub.TextSize = 16; sub.TextColor3 = Color3.fromRGB(220,220,220)
			sub.TextScaled = true; sub.RichText = false; sub.TextXAlignment = Enum.TextXAlignment.Left; sub.TextYAlignment = Enum.TextYAlignment.Center
			sub.ZIndex = 5; sub.Parent = btn
		end

		local price = Instance.new("TextLabel")
		price.Size = UDim2.new(1,-76,0,22); price.Position = UDim2.new(0,76,0,62); price.BackgroundTransparency = 1
		price.Text = priceTxt; price.Font = Enum.Font.GothamBold; price.TextSize = 16; price.TextColor3 = Color3.fromRGB(100,255,100)
		price.TextScaled = true; price.RichText = false; price.TextXAlignment = Enum.TextXAlignment.Left; price.TextYAlignment = Enum.TextYAlignment.Center
		price.ZIndex = 5; price.Parent = btn

		return btn, sub
	end

	-- MID AIR RECHARGE (y=197) -- FINAL cyan-blue 20,180,255 / stroke 20,80,180
	midAir = mkImpulseBtn("MidAirBtn", 197, Color3.fromRGB(20,180,255), Color3.fromRGB(20,80,180),
		"\xe2\x9a\xa1\xe2\x98\x81\xef\xb8\x8f", "MID-AIR", "RECHARGE", CONFIG.prices.midAir)

	-- 2X POWER (y=295) -- FINAL purple 180,80,255 / stroke 80,30,140
	twoX, twoXSub = mkImpulseBtn("TwoXBtn", 295, Color3.fromRGB(180,80,255), Color3.fromRGB(80,30,140),
		"\xe2\x9a\xa1", "2X POWER", "1 HOUR", CONFIG.prices.twoX)

	-- BIRD NUKE (y=393) -- FINAL red 255,60,60 / stroke 160,20,20. NOTE: no subtitle row on this one.
	birdNuke = mkImpulseBtn("BirdNukeBtn", 393, Color3.fromRGB(255,60,60), Color3.fromRGB(160,20,20),
		"\xF0\x9F\x90\xa6\xF0\x9F\x92\xa5", "BIRD NUKE", nil, CONFIG.prices.birdNuke)

	-- 2x timer: a Frame in the SUBTITLE slot holding a green countdown label. While the boost is live the
	-- timer shows and the "1 HOUR" subtitle hides; when it lapses they swap back.
	twoXTimerLabel = Instance.new("Frame")
	twoXTimerLabel.Size = UDim2.new(1,-76,0,22); twoXTimerLabel.Position = UDim2.new(0,76,0,38)
	twoXTimerLabel.BackgroundTransparency = 1; twoXTimerLabel.Visible = false; twoXTimerLabel.ZIndex = 5; twoXTimerLabel.Parent = twoX
	twoXTimerText = Instance.new("TextLabel")
	twoXTimerText.Size = UDim2.new(1,0,1,0); twoXTimerText.BackgroundTransparency = 1
	twoXTimerText.Text = "\xe2\x9a\xa1 60m 00s"; twoXTimerText.Font = Enum.Font.GothamBold
	twoXTimerText.TextColor3 = Color3.fromRGB(100,255,100); twoXTimerText.TextScaled = true
	twoXTimerText.ZIndex = 6; twoXTimerText.Parent = twoXTimerLabel

	twoX.MouseButton1Click:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		pcall(function() MarketplaceService:PromptProductPurchase(player, PRODUCT_IDS.TwoXOneHour) end)
	end)
	birdNuke.MouseButton1Click:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		pcall(function() MarketplaceService:PromptProductPurchase(player, PRODUCT_IDS.BirdNuke) end)
	end)
end

--======================================================================
-- MID-AIR RECHARGE -- pause while purchasing (mid-flight only)
-- Tapping BUY while AIRBORNE holds the player in place for the whole Robux
-- prompt so they don't keep falling during it. Anchors the root AND sets the
-- "Frozen" player attribute (Fart to Float's flight loop reads that and skips
-- flight while it's set). On ANY result -- purchased OR cancelled -- the hold
-- releases and velocity zeroes, so they resume from rest where they paused.
--   purchased -> meter refills, player KEEPS hovering until their next fart press
--   cancelled -> immediately resumes falling, no refill
-- A 60s safety timeout releases the hold if no result ever arrives.
-- Clicking on the ground does nothing special.
--======================================================================
if midAir then
	local rechargePauseActive = false
	local rechargePauseToken = 0
	local RECHARGE_PRODUCT = PRODUCT_IDS.MidAirRecharge

	-- TRUE only while paused AFTER a successful purchase, waiting for the fart press to unpause + fly.
	_G.rechargeAwaitingFart = false

	local function rechargeUnfreeze()
		if not rechargePauseActive then return end
		rechargePauseActive = false
		rechargePauseToken = rechargePauseToken + 1 -- invalidate any pending safety timeout
		_G.rechargeAwaitingFart = false
		if player:GetAttribute("Frozen") then player:SetAttribute("Frozen", false) end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.Anchored = false
			hrp.AssemblyLinearVelocity = Vector3.zero -- resume from rest at the paused spot
		end
	end
	_G.endRechargePause = rechargeUnfreeze

	local function rechargeFreezeAndPrompt()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local airborne = hrp and hum and hum.FloorMaterial == Enum.Material.Air
		_G.rechargeAwaitingFart = false -- new attempt; not purchased yet
		-- Only pause MID-FLIGHT, and never stomp an existing (server join-) "Frozen" hold.
		if CONFIG.midAirFreezeWhileBuying and airborne and not rechargePauseActive and not player:GetAttribute("Frozen") then
			rechargePauseActive = true
			rechargePauseToken = rechargePauseToken + 1
			local myToken = rechargePauseToken
			hrp.AssemblyLinearVelocity = Vector3.zero -- zero momentum -> hover exactly where clicked
			hrp.Anchored = true                       -- instant freeze
			player:SetAttribute("Frozen", true)       -- flight loop anchors + skips flight while set
			-- Safety net: auto-release after 60s if NO purchase result ever arrives. Does NOT fire once a
			-- purchase succeeded (awaiting fart) -- that hover is intentional.
			task.delay(60, function()
				if rechargePauseActive and rechargePauseToken == myToken and not _G.rechargeAwaitingFart then
					rechargeUnfreeze()
				end
			end)
		end
		pcall(function() MarketplaceService:PromptProductPurchase(player, RECHARGE_PRODUCT) end)
	end

	-- On SUCCESS: refill the meter to MAX and KEEP the player frozen (hovering with a full tank). We do
	-- NOT auto-resume; their next fart press does. Idempotent, so a late second signal (client callback
	-- AND the server's rechargeNow) can't re-top the meter after they already resumed.
	_G.rechargeMarkPurchased = function()
		if not rechargePauseActive then return end
		if _G.rechargeFartMeter then _G.rechargeFartMeter() end -- WRITE the meter to MAX + refresh UI
		_G.rechargeAwaitingFart = true
	end

	midAir.MouseButton1Click:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		rechargeFreezeAndPrompt()
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, productId, isPurchased)
		if productId ~= RECHARGE_PRODUCT then return end
		if isPurchased then
			_G.rechargeMarkPurchased() -- refill + keep paused, await fart
		else
			rechargeUnfreeze()         -- cancel/close -> resume falling, no refill
		end
	end)
end

--======================================================================
-- STATS LOOP  (0.5s) -- Island + Max Height, plus the progress bar
-- Reads _G.leaderstats when the game provides it, else player.leaderstats.
-- Max Height = max(_G.peakHeight, best seen this session), so it never
-- ticks backwards mid-flight.
--======================================================================
local sessionMaxHeight = 0
task.spawn(function()
	while true do
		task.wait(0.5)
		pcall(function()
			local leaderstats = _G.leaderstats or player:FindFirstChild("leaderstats")
			if leaderstats then
				local isl = leaderstats:FindFirstChild("Island")
				if isl then islandLabel.Text = CONFIG.rows.island .. isl.Value end
			end
			local sh = math.floor(math.max(_G.peakHeight or 0, sessionMaxHeight))
			if sh > sessionMaxHeight then sessionMaxHeight = sh end
			heightLabel.Text = CONFIG.rows.height .. sh
			updateSpaceRealmProgress() -- also refresh here so leaderstat-only realms still climb
		end)
	end
end)

-- 2x-1-hour countdown (1s). Reads _G.playerGamepasses.twoXHourExpiry, which the server sets from
-- ProcessReceipt -> GamepassEvent. Timer visible = subtitle hidden, and vice versa.
if twoXTimerLabel then
	task.spawn(function()
		while true do
			task.wait(1)
			local gp = _G.playerGamepasses
			local expiry = gp and gp.twoXHourExpiry or 0
			if expiry > os.time() then
				local rem = expiry - os.time()
				twoXTimerText.Text = string.format("\xe2\x9a\xa1 %dm %02ds", math.floor(rem/60), rem % 60)
				twoXTimerLabel.Visible = true
				if twoXSub then twoXSub.Visible = false end
			else
				twoXTimerLabel.Visible = false
				if twoXSub then twoXSub.Visible = true end
			end
		end
	end)
end

--======================================================================
-- MOBILE SCALING + POSITION  (the game's exact pass, scoped to this panel)
-- Phone caps at 0.60 and gets an EXTRA 0.78 (RightPanelGui is one of the three
-- screen-hogging clusters), tablet/iPad scales up to 2.5, desktop is exactly 1.
-- Anchor (1,0) means the UIScale shrinks it INTO the top-right corner, so it
-- can never drift off-screen.
-- On phone-class the panel tucks up under the coin pill, and that Y is DERIVED
-- from the pill's live scaled height -- a fixed number goes wrong the moment
-- either multiplier changes (gap opens up or the two overlap).
--======================================================================
local MOBILE_SHRINK = 0.78   -- RightPanelGui's extra phone shrink
local COIN_SHRINK   = 0.78   -- CoinGui's extra phone shrink
local COIN_HEIGHT   = 52     -- authored coin-pill height
local COIN_Y        = 10     -- authored coin-pill y-offset

local function getScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	if vp.X <= 1 or vp.Y <= 1 then return isMobile and 0.60 or 1 end -- boot: viewport not valid yet
	if isMobile then
		-- iPhone SE/8 landscape reference (1100x590), clamped by device CLASS (viewport short axis).
		local deviceMax = (math.min(vp.X, vp.Y) >= 800) and 2.5 or 0.60
		return math.clamp(math.min(vp.X / 1100, vp.Y / 590), 0.55, deviceMax)
	end
	return 1
end

local function repositionStatsPanel()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
	local phoneClass = isMobile and math.min(vp.X, vp.Y) < 800

	rightPanel.Size = UDim2.new(0,230,0,CONFIG.showImpulseButtons and 500 or 195)
	rightPanel.AnchorPoint = Vector2.new(1,0)
	if phoneClass then
		local coinScale = getScale() * COIN_SHRINK
		local coinBottom = COIN_Y + math.floor(COIN_HEIGHT * coinScale + 0.5) -- pill's y + its scaled height
		rightPanel.Position = UDim2.new(1, -8, 0, coinBottom + 8)
	else
		rightPanel.Position = UDim2.new(1, -5, 0, 85)
	end

	local us = rightPanel:FindFirstChildWhichIsA("UIScale")
	if not us then us = Instance.new("UIScale"); us.Parent = rightPanel end
	us.Scale = getScale() * (isMobile and MOBILE_SHRINK or 1)

	for _, v in ipairs(rightGui:GetDescendants()) do
		if v:IsA("TextLabel") or v:IsA("TextButton") then v.TextScaled = true end
	end
end
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(repositionStatsPanel)
end
repositionStatsPanel()
player.CharacterAdded:Connect(function() task.wait(0.1); repositionStatsPanel() end)
task.delay(3, repositionStatsPanel)

-- Exposed so a realm's own HUD code can nudge it (e.g. after building a coin pill of a different size)
_G.repositionStatsPanel = repositionStatsPanel

print("[StatsPanelKit] STATS panel built (230x" .. (CONFIG.showImpulseButtons and 500 or 195) .. ", top-right)")
