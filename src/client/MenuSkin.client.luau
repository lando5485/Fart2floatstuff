--======================================================================
-- MenuSkin.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- ONE LOOK FOR EVERY MENU.
--
-- Every panel in this game was built by whoever needed it, copying roughly from the last one, and the
-- copies drifted. Measured across src/client on the day this file was written:
--
--   close X       5 sizes (26/30/34/40/44), 7 different reds, 2 fonts, TextSize 16-22 AND TextScaled,
--                 4 different corner anchors
--   corner radius 8, 10, 12, 14, 16, 18, 20 and 30, all live at once
--   panel fill    6 (hub blue, MORE pink, locker cream, stomach brown, daily navy, gut-skin near-black)
--   scrollbars    mostly 6px gold, but not everywhere
--
-- A player closes a menu more often than they do almost anything else in this UI, and it looks like a
-- different button every time. That -- not the layouts -- is what makes the menus read as several games
-- stapled together.
--
-- ===== IT ADOPTS, IT DOES NOT REBUILD =====
-- The panels are owned by about twenty different scripts. This one watches for a panel appearing and
-- normalises its chrome IN PLACE. Nothing is rebuilt, no owner script is edited, and deleting this file
-- puts everything back exactly as it was.
--
-- That is the pattern this codebase already proved twice:
--     HousePanel.client.luau (CandyRealm)  adopts any task HUD -> house size + house spot
--     MenuBackButton.client.luau           injects BACK into five panels owned by five other scripts
--
-- It also sidesteps the two things that make editing the owners dangerous:
--   * CoreClient sits at 199 of Luau's 200 locals. One more top-level local there and the whole HUD
--     silently stops running -- no error, one line in the client log.
--   * Rojo only ADDS. A stale copy of CoreClient baked into the place file shadows any edit to its
--     source. Mutating what is already on screen works whichever copy drew it.
--
-- ===== WHAT IT DELIBERATELY DOES NOT TOUCH =====
--   * Layout. No panel is moved, resized or re-flowed. Header BAND heights are left alone -- children
--     are positioned against them by hand in most panels, so changing one silently drops labels behind
--     the divider. Header height is a per-panel job, not a sweep.
--   * Text content, remotes, state, open/close flags. MenuBackButton's scars are the reference here:
--     each panel toggles ONE of ScreenGui.Enabled / panel.Visible, and touching both strands it forever.
--     This file reads Visible and never writes it.
--   * Anything carrying the NoMenuSkin attribute.
--
-- Everything it adds or marks is named / attributed MS_*, so a second pass finds its own work and can
-- never double up.
--======================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local player     = Players.LocalPlayer
local PlayerGui  = player:WaitForChild("PlayerGui")

--======================================================================
-- THE KIT
--======================================================================
-- THIS TABLE IS THE WHOLE DESIGN DECISION. Everything below reads from it and nothing hardcodes a
-- number, so retuning the menus is editing these values and nothing else.
--
-- The values are the Pet Hub's, because the Pet Hub is already the informal reference: the Shop, MORE+,
-- Daily Tasks, the Locker, Rebirth, Gifting and Skin Crates all copy its 700x520 box at (0.5,0,0.5,-45).
-- Writing it down is the only new part.
local SKIN = {
	-- ===== PANEL FILL =====
	-- The blue family is unified on ONE blue. The Pet Hub was 25,90,185 and the panels beside it were each
	-- something near but not equal to it, so side by side they read as three different blues rather than as
	-- one game. This is the house blue -- the value CrateClient and SettingsMenu already share.
	--
	-- ONLY BLUE PANELS ARE REPAINTED (see blueish below). MORE+ stays pink, the Locker stays cream, the
	-- Garden keeps its yellow header: the hue is how a player knows which menu they are in, and flattening
	-- that would cost more than the consistency is worth.
	panelFill  = Color3.fromRGB( 26,  79, 214),
	headerFill = Color3.fromRGB( 14,  59, 176),

	-- corner radius, by what the frame IS. Three values, not eight: the card itself, the cards inside
	-- it, and the buttons. Applied by size class (see radiusFor) because that is the only signal a
	-- sweep has -- a frame does not say what it thinks it is.
	cardRadius   = 24,   -- the 700x520 panel
	innerRadius  = 16,   -- sections, rows, list cells
	buttonRadius = 12,   -- buttons and pills

	-- the card's chunky white rim. This IS the identity -- it does not get thinner.
	cardStroke      = Color3.fromRGB(255, 255, 255),
	cardStrokeWidth = 3,

	-- THE CLOSE BUTTON, settled. 40x40 is the middle of the five sizes in use and the one the Pet Hub,
	-- MORE+, the Shop and the Stomach shop already share, so it is also the smallest actual change.
	closeSize    = 40,
	closeRadius  = 8,
	closeFill    = Color3.fromRGB(220, 50, 50),
	closeFont    = Enum.Font.FredokaOne,
	closeTextSize= 20,
	closeStroke  = Color3.fromRGB(0, 0, 0),
	closeStrokeW = 2,
	closeInsetX  = 48,   -- from the RIGHT edge of whatever it sits in
	closeInsetY  = 10,   -- from the TOP edge

	-- scrollbars. 6px was already near-universal; the colour moves gold -> white so the bar stops reading
	-- as something you can claim. A scrollbar is chrome, and gold in this game means "act on me".
	scrollThickness = 6,
	scrollColor     = Color3.fromRGB(255, 255, 255),

	-- panel titles: the display face, in WHITE. Gold was doing two jobs -- "this is the title" and "this is
	-- selectable / claimable" -- and the second is the one that has to stay loud. With the tab bar sitting
	-- directly under the header ALSO gold, the two competed; a white title leaves the selected tab as the
	-- only gold thing in the top third of the panel. Body copy is left alone -- Gotham under a Fredoka
	-- title is the intended pairing, not drift.
	titleFont  = Enum.Font.FredokaOne,
	titleColor = Color3.fromRGB(255, 255, 255),
	titleMin   = 20,   -- a TextLabel at or above this size, in a header, counts as the title

	-- ===== THE PRIMARY ACTION, AND WHY IT IS NOT SWEPT =====
	-- Orange, so the one thing you came to a screen to press is not the same colour as the tab you are
	-- already standing on. It is applied AT THE SOURCE (VIEW QUEST on a locked pet card, the TRADE UP chip)
	-- rather than by a pass in this file, and that is deliberate: a selected tab and a gold CTA are the
	-- SAME fill today, so a sweep repainting "gold buttons" would repaint every selected tab along with
	-- them and destroy the one thing the tab colour exists to say. Recorded here so the decision lives with
	-- the rest of the kit -- grep "MS PRIMARY" for the sites.
	primaryFill = Color3.fromRGB(255, 150,  40),
	primaryInk  = Color3.fromRGB( 58,  30,   0),
}

-- THE HOUSE PALETTE. Not invented here -- this is `local C` from CrateClient.client.luau:630, which
-- SettingsMenu already copied verbatim when it was converted off its dark grey. Third copy, same table.
local HOUSE = {
	-- panel/header deliberately absent: those are SKIN.panelFill / SKIN.headerFill, so the dark-panel
	-- recolour and the blue-family repaint can never drift onto two different blues.
	row    = Color3.fromRGB( 47, 111, 224),
	navy   = Color3.fromRGB( 12,  34,  86),
	line   = Color3.fromRGB(120, 170, 250),
	muted  = Color3.fromRGB(214, 232, 252),
	gold   = Color3.fromRGB(255, 210,  74),
}

-- ===== THE DARK PANELS =====
-- Four menus are dark-mode windows sitting inside a bright blue-and-gold kids' game. Three of them are
-- here; Settings was already converted (SETTINGS_BUILD 4) and is the proof this lands cleanly.
--
--   WormholeMenu    18,24,52   inherited straight from the Space Realm port, never re-skinned
--   DailyTasksGui   20,24,38
--   StomachShopGui  12,10,32   NOT authored dark -- CoreClient builds it brown and GutSkinClient
--                              re-colours it at runtime to match the Space Realm skins window. So it
--                              has to be re-applied on every open, not once at boot.
--
-- Recolouring a dark panel leaves its text on a much lighter ground, so liftText below rescues any
-- label that would end up too dark to read. Nothing is recoloured that is not on this list.
local RECOLOR = {
	WormholeMenu   = true,
	DailyTasksGui  = true,
	StomachShopGui = true,
}

--======================================================================
-- HELPERS
--======================================================================
local function corner(o, r)
	local c = o:FindFirstChildOfClass("UICorner")
	if not c then c = Instance.new("UICorner"); c.Parent = o end
	c.CornerRadius = UDim.new(0, r)
	return c
end

local function stroke(o, col, t)
	local s = o:FindFirstChildOfClass("UIStroke")
	if not s then s = Instance.new("UIStroke"); s.Parent = o end
	s.Color = col; s.Thickness = t
	return s
end

-- Perceived brightness, 0..1. Used only to decide whether a colour is "dark" -- the weights are the
-- usual luma coefficients, and the exact curve does not matter for a threshold test.
local function luma(c)
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

-- IS THIS A BLUE PANEL? Blue-DOMINANT, by a clear margin, so the test cannot drift onto a colour that
-- merely leans cool. MORE+ pink (225,70,170) fails on R >= B; the Locker cream, the Stomach brown and the
-- Garden yellow all fail the same way. The Pet Hub's 25,90,185 passes comfortably.
--
-- The margin is 30 rather than 1 on purpose: a near-grey with one more unit of blue in it is not a blue
-- panel, and repainting one would be exactly the kind of silent over-reach a sweep must never make.
local function blueish(c)
	local r, g, b = c.R * 255, c.G * 255, c.B * 255
	return b > r + 30 and b > g + 30
end

-- WHAT RADIUS DOES THIS FRAME WANT. A sweep cannot ask, so it measures. The 700x520 card and anything
-- near it is a card; a control shorter than 56px is a button; everything between is an inner section.
local function radiusFor(o)
	local sz = o.AbsoluteSize
	if sz.X >= 400 and sz.Y >= 200 then return SKIN.cardRadius end
	if sz.Y <= 56 then return SKIN.buttonRadius end
	return SKIN.innerRadius
end

-- THE PANEL FRAME, by shape -- the same test MenuBackButton uses, deliberately.
-- STRICTLY a Frame: "any big GuiObject" matched RebirthGui's 720x546 drop-shadow ImageLabel, which is
-- not the panel and is kept hidden forever.
local function bigFrame(gui)
	for _, ch in ipairs(gui:GetChildren()) do
		if ch.ClassName == "Frame" and ch.Size.X.Offset >= 400 and ch.Size.Y.Offset >= 200 then return ch end
	end
	for _, ch in ipairs(gui:GetChildren()) do
		if ch.ClassName == "Frame" and ch.Size.X.Scale >= 0.5 then return ch end
	end
	return nil
end

-- The header band: a full-width frame, 44-90 tall, pinned to the top of the panel. Tolerance on the Y
-- position is 20 rather than 4 because Rebirth insets its band by 14.
local function headerOf(panel)
	for _, ch in ipairs(panel:GetChildren()) do
		if ch.ClassName == "Frame" and ch.Size.X.Scale >= 1
			and ch.Size.Y.Offset >= 44 and ch.Size.Y.Offset <= 90
			and ch.Position.Y.Offset <= 20 then
			return ch
		end
	end
	return nil
end

local function skipped(o)
	local n = o
	while n and n ~= PlayerGui do
		if n:GetAttribute("NoMenuSkin") then return true end
		n = n.Parent
	end
	return false
end

--======================================================================
-- THE PASSES
--======================================================================

-- 1. THE CLOSE X.
-- Style is applied always. POSITION is only touched when the button sits in something full-width --
-- a header band or the panel itself -- because that is the only case where "48 in from the right edge"
-- means the same thing it means everywhere else. A close button parked inside a narrow sub-frame is
-- left where its author put it; moving it would be guessing.
local function skinClose(panel)
	local best
	for _, ch in ipairs(panel:GetDescendants()) do
		if ch:IsA("TextButton") then
			local t = ch.Text
			if (t == "X" or t == "x" or t == "\xE2\x9C\x95" or t == "\xE2\x9C\x96")
				and ch.AbsoluteSize.X > 0 and ch.AbsoluteSize.X <= 60
				and (not best or ch.AbsolutePosition.Y < best.AbsolutePosition.Y)
			then
				best = ch
			end
		end
	end
	if not best then return end

	best.Size            = UDim2.fromOffset(SKIN.closeSize, SKIN.closeSize)
	best.BackgroundColor3= SKIN.closeFill
	best.Font            = SKIN.closeFont
	best.TextColor3      = Color3.new(1, 1, 1)
	-- TextScaled and an explicit TextSize fight; three panels set both. The explicit size wins here so
	-- the glyph is the same weight at the same 40px on every menu.
	best.TextScaled      = false
	best.TextSize        = SKIN.closeTextSize
	corner(best, SKIN.closeRadius)
	stroke(best, SKIN.closeStroke, SKIN.closeStrokeW)

	local host = best.Parent
	if host and host:IsA("GuiObject") and host.Size.X.Scale >= 1 then
		best.AnchorPoint = Vector2.new(0, 0)
		best.Position    = UDim2.new(1, -SKIN.closeInsetX, 0, SKIN.closeInsetY)
	end
end

-- 2. RADII + THE CARD RIM.
-- Only frames that ALREADY have a UICorner are touched. A square-cornered frame is square on purpose
-- (dividers, gradient caps, the squared-off band under MORE+'s header that stops its 20px corner
-- cutting into the panel edge) and adding a radius there is how a sweep breaks a design.
local function skinShapes(panel)
	corner(panel, SKIN.cardRadius)
	stroke(panel, SKIN.cardStroke, SKIN.cardStrokeWidth)

	for _, d in ipairs(panel:GetDescendants()) do
		if d:IsA("GuiObject") and d:FindFirstChildOfClass("UICorner") then
			corner(d, radiusFor(d))
		end
		if d:IsA("ScrollingFrame") then
			d.ScrollBarThickness    = SKIN.scrollThickness
			d.ScrollBarImageColor3  = SKIN.scrollColor
		end
	end
end

-- 3. THE BLUE FAMILY, ON ONE BLUE.
-- Fill and header only. Inner cards and sections are left exactly as their author set them: they are
-- tinted RELATIVE to their own panel (a section is the panel darkened, a row is the section lightened),
-- and a sweep that flattened them onto one value would erase the depth the panels are built out of.
--
-- The header band is repainted with the fill, never on its own -- a house-blue panel under an old darker
-- header reads as a mismatch, which is the exact problem this pass exists to remove.
local function skinBlue(panel)
	if not blueish(panel.BackgroundColor3) then return end
	panel.BackgroundColor3 = SKIN.panelFill
	local hdr = headerOf(panel)
	if hdr and blueish(hdr.BackgroundColor3) then hdr.BackgroundColor3 = SKIN.headerFill end
end

-- 4. THE TITLE.
-- The largest TextLabel in the header band, at or above titleMin. Everything smaller in there is the
-- subtitle and keeps its body face -- Fredoka over Gotham is the intended pairing.
local function skinTitle(panel)
	local hdr = headerOf(panel)
	if not hdr then return end
	local best
	for _, ch in ipairs(hdr:GetDescendants()) do
		if ch:IsA("TextLabel") and not ch.TextScaled and ch.TextSize >= SKIN.titleMin then
			if not best or ch.TextSize > best.TextSize then best = ch end
		end
	end
	if best then
		best.Font       = SKIN.titleFont
		best.TextColor3 = SKIN.titleColor
	end
end

-- 5. THE DARK PANELS.
-- Fill and wells go to the house blue; then every label that was authored for a near-black ground gets
-- lifted, or the panel comes out unreadable. The threshold is deliberately generous -- on the house
-- blue (luma ~0.33) anything below 0.55 is muddy, not just anything below 0.5.
local function liftText(root)
	for _, d in ipairs(root:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and luma(d.TextColor3) < 0.55 then
			d.TextColor3 = HOUSE.muted
		end
	end
end

local function recolor(panel)
	if luma(panel.BackgroundColor3) < 0.30 then
		panel.BackgroundColor3 = SKIN.panelFill
	end
	for _, d in ipairs(panel:GetDescendants()) do
		if d:IsA("Frame") and d.BackgroundTransparency < 1 then
			local l = luma(d.BackgroundColor3)
			-- A recessed well (a progress track, a list background) stays dark so it still reads as
			-- recessed -- it just becomes house navy instead of black. Mid-dark frames are rows.
			if l < 0.10 then
				d.BackgroundColor3 = HOUSE.navy
			elseif l < 0.30 then
				d.BackgroundColor3 = HOUSE.row
			end
		end
	end
	liftText(panel)
end

--======================================================================
-- ADOPT
--======================================================================
local function skin(gui)
	if not gui:IsA("ScreenGui") or skipped(gui) then return end
	local panel = bigFrame(gui)
	if not panel then return end

	-- ===== A MENU CARD, OR AN EFFECT OVERLAY WEARING A CARD'S SHAPE? =====
	-- THIS GATE IS THE FIX FOR THE "TWO WHITE LINES AT THE TOP OF THE SCREEN".
	--
	-- bigFrame's scale fallback exists for scale-sized menu panels (the Shop is 0.9 x 0.85) -- but a
	-- full-screen fade/flash sheet is Size (1,0,1,0), which passes the same >= 0.5 test. The first cut of
	-- this file therefore adopted every effect overlay in the game (FlashGui, EventFlashGui, StormGui,
	-- RainbowBeamFlashGui, WindGui, SecretCaveFade, WarpEffect, RebirthFX) and gave each one the 3px WHITE
	-- CARD RIM. On a transparent sheet the rim is the only thing that draws -- and a stroked sheet in an
	-- IgnoreGuiInset gui puts its top edge at y=0 while an inset one puts it just under the ~58px topbar,
	-- which is exactly the pair of hairlines that were haunting the top of the screen.
	--
	-- Two tests, either one disqualifies, and every real menu card in the game passes both:
	--   * it must NOT cover (nearly) the whole viewport -- no menu card does, the Shop included;
	--   * its fill must actually be VISIBLE -- every menu card here is opaque, and a fade sheet is
	--     see-through by definition (its whole job is to be invisible until an effect tweens it in).
	do
		local cam = Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		if panel.AbsoluteSize.X >= vp.X * 0.95 and panel.AbsoluteSize.Y >= vp.Y * 0.95 then return end
		if panel.BackgroundTransparency >= 0.9 then return end
	end

	local ok, err = pcall(function()
		skinShapes(panel)
		skinClose(panel)
		skinBlue(panel)
		skinTitle(panel)
		if RECOLOR[gui.Name] then recolor(panel) end
	end)
	if not ok then
		warn("[MenuSkin] " .. gui.Name .. ": " .. tostring(err))
		return
	end
	gui:SetAttribute("MS_Skinned", true)
end

-- WHEN. A panel is skinned when it OPENS, not once at boot, and that is not an optimisation:
--   * most of these panels build their contents lazily on first open, so a boot-time pass would find
--     an empty frame;
--   * StomachShopGui is re-coloured at runtime by GutSkinClient, so a one-shot pass loses to it.
-- Re-skinning on every open costs one descendant walk on a frame the player is already waiting on.
local function watch(gui)
	if not gui:IsA("ScreenGui") then return end
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then task.defer(skin, gui) end
	end)
	-- The Visible-driven half of the set (Pet Hub, Rebirth, Free Rewards) never flips Enabled, so
	-- watching that alone would skip them entirely. Watch the panel frame too -- READ ONLY.
	task.defer(function()
		local panel = bigFrame(gui)
		if not panel then return end
		panel:GetPropertyChangedSignal("Visible"):Connect(function()
			if panel.Visible then task.defer(skin, gui) end
		end)
		if gui.Enabled and panel.Visible then skin(gui) end
	end)
end

--======================================================================
-- THE LEGACY COIN PILL, HIDDEN BEHIND THE STOMACH SHOP
--======================================================================
-- The yellow "2000" pill that sits over the Stomach Shop is NOT part of that panel. It is CoinGui.Frame --
-- the original top-right coin readout CoreClient builds for the whole HUD (CoreClient.client.lua:467) --
-- and it simply stays on screen while the shop is open, floating over its top-right corner.
--
-- So it cannot be deleted "from the shop": there is nothing to delete there. It is hidden for exactly as
-- long as the shop is up, and restored to whatever it was before, which is the behaviour that was actually
-- wanted and costs the rest of the HUD nothing.
--
-- WORTH KNOWING: TokenHud draws a SECOND, newer coin readout beside it (the navy capsule holding a token
-- pill and a coin pill), so this old pill is showing a number that is already on screen twice. If it should
-- go everywhere rather than just here, that is one line -- say so and it goes.
do
	local prevVisible = nil
	local function coinPill()
		local cg = PlayerGui:FindFirstChild("CoinGui")
		return cg and cg:FindFirstChild("Frame")
	end
	local function apply()
		local shop = PlayerGui:FindFirstChild("StomachShopGui")
		local open = shop ~= nil and shop:IsA("ScreenGui") and shop.Enabled
		local pill = coinPill()
		if not pill then return end
		if open then
			-- Captured on the way IN, so a pill already hidden by something else is not "restored" visible.
			if prevVisible == nil then prevVisible = pill.Visible end
			pill.Visible = false
		elseif prevVisible ~= nil then
			pill.Visible = prevVisible
			prevVisible = nil
		end
	end
	local function hook(sg)
		if sg:IsA("ScreenGui") and sg.Name == "StomachShopGui" then
			sg:GetPropertyChangedSignal("Enabled"):Connect(function() task.defer(apply) end)
			task.defer(apply)
		end
	end
	for _, g in ipairs(PlayerGui:GetChildren()) do hook(g) end
	PlayerGui.ChildAdded:Connect(hook)
end

for _, g in ipairs(PlayerGui:GetChildren()) do watch(g) end
PlayerGui.ChildAdded:Connect(watch)

-- A few late sweeps. Panels that are built well after boot (and any that were already open when this
-- script started) are picked up without needing a special case for each one.
for _, d in ipairs({ 1, 4, 10 }) do
	task.delay(d, function()
		for _, g in ipairs(PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") and not g:GetAttribute("MS_Skinned") then
				local panel = bigFrame(g)
				if panel and panel.Visible then skin(g) end
			end
		end
	end)
end

print("[MenuSkin] ready -- close X, radii, rim, scrollbars, titles; recolour for "
	.. "WormholeMenu / DailyTasksGui / StomachShopGui")
