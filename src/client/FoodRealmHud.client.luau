--======================================================================
-- FoodRealmHud.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- ONE unified bottom HUD -- stomach readout + shop call-to-action in a single panel, restyled
-- FLAT ROYAL BLUE to match the right-side menu / stats / currency panels. (An earlier pass
-- painted it sunbaked-stone brown with heavy bevels; it read as muddy and over-shaded next to
-- the rest of the UI, so the palette went back to the game's blue -- see PALETTE below.)
--
-- Flat blue shell, gold rim, green gas fill, amber CTA with a gentle two-shade ramp, navy
-- shadows throughout. No emoji anywhere on the button -- see the caption scrub below.
--
--    . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .    <- halo, 484 x 158
--   +================================================================+   <- dark-blue outline, 3px
--   |  (( ))   Tiny Gut                                              |   <- recessed well, gut icon
--   |  ((ic))  [############ 0/100 ##############]                   |   <- inset bar, 382 x 36
--   |  [            BUY FOOD FIRST!                             ]    |   <- 446 x 52, amber -> orange
--   +================================================================+
--                CARD 470 x 144  -- measured, see LAYOUT
--
-- ===== IT RESTYLES. IT DOES NOT REBUILD. =====
-- Every element already exists and is already wired. CoreClient builds them, holds them on
-- _G.gui, drives the fill from CurrentPower, and swaps the button's text/Active across its
-- three states. This file writes only colours, corners, gradients, strokes, geometry and
-- decoration -- no Text on any label that code owns, no rebound clicks, nothing functional
-- destroyed:
--
--   _G.gui.gasMeterPanel   the unified shell    _G.gui.gasFill        the fill CoreClient drives
--   _G.gui.gasBg           the bar track        _G.gui.gasPowerText   the 0/100 readout
--   _G.gui.fartBtnFrame    the CTA button       _G.gui.fartBtn        its caption + click
--   _G.gui.gasTitleLabel   the old caption      _G.gui.fartCloudLabel the old glyph
--   bottomStack.StomachHud the old name row (its GutIcon becomes the holder art)
--
-- ===== THE ONE STRUCTURAL CHANGE =====
-- One unified container cannot be two sibling rows, so fartBtnFrame (and the gut icon) are
-- REPARENTED into the panel. Safe here specifically because nothing addresses them by path:
-- CoreClient reaches the button via _G.gui.fartBtnFrame (2494-2507, 3554-3567) and the icon
-- via a local upvalue. Re-asserted on the tick, so a rival pass that moves it back is undone.
--======================================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player       = Players.LocalPlayer
local PlayerGui    = player:WaitForChild("PlayerGui")

--======================================================================
-- PALETTE -- the game's existing UI colours, verbatim
--======================================================================
-- THE SHELL -- FLAT ROYAL BLUE, matched to the right-side menu / stats panels (the 30,100,200
-- family that TokenHud and the flight-stats card already wear). The sunbaked-stone brown read
-- as muddy next to them, and its steep top->bottom ramps gave the panel a heavy 3D bevel the
-- rest of the UI doesn't have. The constant NAMES survive from the stone pass (every gradient
-- below references them); only the values changed. The three shell stops now sit a few percent
-- apart, so the "gradient" renders as a single clean blue with the faintest vertical light --
-- flat, per the art direction, without touching any of the geometry that uses them.
-- ===== THE RIGHT-SIDE PANEL'S REAL COLOUR IS (30, 140, 255) =====
-- An earlier pass matched Color3.fromRGB(30, 90, 200) -- which is what CoreClient BUILDS the right panel
-- as, and is NOT what it ends up. Two later restyle passes repaint it, and the last one (CoreClient's
-- final HUD pass) sets Color3.fromRGB(30, 140, 255): a much lighter, brighter blue. Matching the build
-- colour is exactly why this HUD still looked dark next to the menu it was supposed to match.
local PANEL_BLUE = Color3.fromRGB(30, 140, 255)   -- the LIGHT blue actually on screen at the right edge

-- ===== A WHISPER OF GRADIENT -- ENOUGH TO BREATHE, NOT ENOUGH TO LOOK MOULDED =====
-- Fully flat fills fixed the plastic 3D look but went too far the other way: flat shapes stacked on flat
-- shapes read as paper cut-outs. `lift` returns a colour a few percent up or down from a base, which is
-- all a subtle top-to-bottom ramp needs -- around 8%, versus the 30-40% swings the original build used.
-- One knob: raise AMT if the panels still feel dead, lower it if any moulding creeps back in.
local LIFT_AMT = 0.08
local function lift(c, dir) -- dir +1 = slightly lighter (top), -1 = slightly darker (bottom)
	local k = 1 + LIFT_AMT * dir
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

local STONE_TOP  = lift(PANEL_BLUE,  1)
local STONE_MID  = PANEL_BLUE
local STONE_BOT  = lift(PANEL_BLUE, -1)
-- OUTLINE-ONLY. This deeper blue used to be the FILL of the icon holder and the gas-bar track, which is
-- what made the HUD read as a dark panel with a bright frame -- the exact inverse of the right-side menu.
-- It is now only ever a stroke, and the wells are a flat LIGHTER blue than the panel, so an inset reads
-- as a lit slot rather than a hole punched in the HUD.
local OUTLINE    = Color3.fromRGB(16, 92, 178)    -- the subtle darker outline, used ONLY as a stroke
local WELL       = Color3.fromRGB(96, 178, 255)   -- recessed: icon holder, bar track
local WELL_TOP   = lift(WELL,  1)                 -- the same faint lift as the shell, so an inset has
local WELL_DEEP  = lift(WELL, -1)                 -- some life in it without turning back into a pit
local GOLD       = Color3.fromRGB(244, 180, 0)    -- #F4B400  gold trim stays: it is the game's accent on blue
local GOLD_LT    = Color3.fromRGB(255, 222, 108)
local GOLD_DEEP  = Color3.fromRGB(186, 128, 0)
-- GAS FILL: green, with the same faint lift as everything else so the bar looks lit rather than printed.
local FILL_BASE  = Color3.fromRGB(76, 206, 88)
local FILL_HI    = lift(FILL_BASE,  1)
local FILL_YEL   = FILL_BASE
local FILL_ORG   = lift(FILL_BASE, -1)
local BLACK      = Color3.fromRGB(0, 0, 0)
local WHITE      = Color3.fromRGB(255, 255, 255)

-- ===== THE CTA IS GREEN, AND FLAT =====
-- "TAP TO FART!" is the fart button, and the fart button has always been green everywhere else in this
-- game (CoreClient builds it as Color3.fromRGB(50,180,50); the sidebar SHOP tile is the same family).
-- This file was painting it amber -> burnt orange -> warm red, which is both the wrong colour for the
-- action and a three-stop ramp -- the single most 3D-looking thing on the HUD.
-- The names below are kept because the skin code references them in several places; only the values
-- changed, and every ramp is now one flat green (identical stops = nothing for UIGradient to blend).
local GREEN_MAIN = Color3.fromRGB(50, 190, 60)    -- the fart-button green
local GREEN_DIM  = Color3.fromRGB(44, 150, 52)    -- the same green, dimmed, for "no food yet"
local AMBER      = lift(GREEN_MAIN,  1)           -- top: a touch lighter
local ORANGE_BRN = GREEN_MAIN                     -- body
local RED_WARM   = lift(GREEN_MAIN, -1)           -- foot: a touch darker. ~8% end to end, no bevel.
local AMBER_DIM  = lift(GREEN_DIM,  1)
local ORANGE_DIM = GREEN_DIM
local RED_DIM    = lift(GREEN_DIM, -1)
local ORANGE_LIT = Color3.fromRGB(120, 226, 128)  -- the soft inner stroke, now a light green
local RIM_HI     = Color3.fromRGB(22, 110, 32)    -- the CTA's outline: ONE dark green, flat
local RIM_MID    = Color3.fromRGB(22, 110, 32)
local RIM_LO     = Color3.fromRGB(22, 110, 32)
local CREAM      = Color3.fromRGB(255, 246, 222)  -- the gloss across the top
local CREAM_GOLD = Color3.fromRGB(255, 228, 164)  -- (was the drawn cart's body; the cart is removed)
local BROWN_INK  = Color3.fromRGB(18, 34, 80)     -- outlines: the cart, the caption (navy ink now)
local BROWN_SHD  = Color3.fromRGB(12, 26, 66)     -- shadows: under the button, inside its rim (navy)

--======================================================================
-- LAYOUT -- MEASURED, not invented. Every number below is read off the lower GUI as it renders
-- at 1:1 (viewport 2239x1044, scale 1.000 on every element):
--
--   CARD   470 x 144        <- PANEL_W / PANEL_H
--   GLOW   484 x 158        <- 7px proud of the card on every side
--   TRACK  382 x 36         <- the gas bar
--   SLOT   446 x 52         <- the CTA's box...
--   BTN    446 x 52         <- ...and the button filling it exactly
--
-- The three widths are one equation, not three guesses, and PAD falls out of it:
--   button 446 = 470 - 2*PAD                  ->  PAD    = 12
--   track  382 = 470 - COL_X - PAD            ->  COL_X  = 76
--   COL_X   76 = PAD + HOLDER + PAD           ->  HOLDER = 52
--
-- Vertical rhythm:  9 | title 17 | 2 | bar 36 | 12 | button 52 | 16
-- Label-to-bar is the tighter gap so the two group as one unit; 12 separates the sections, and
-- the 16 at the foot is deliberate -- the button's shadow plate sits 6px below it and still
-- needs to land inside the card.
--======================================================================
local PANEL_W, PANEL_H = 470, 144               -- was 480 x 178
local GLOW_OUT         = 7                      -- 470+14 x 144+14 = the measured 484 x 158
local PAD              = 12                     -- was 18
local HOLDER           = 52                     -- was 62
local ICON             = 32                     -- was 38, held to the same ratio of HOLDER
local COL_X            = PAD + HOLDER + PAD     -- 76: title and bar share this left edge
local TITLE_Y, TITLE_H = 9, 17                  -- was 18 / 20
local HOLDER_Y         = TITLE_Y + 3            -- centres the well on the title+bar block
local BAR_Y, BAR_H     = 28, 36                 -- was 48 / 42
local BTN_Y, BTN_H     = 76, 52                 -- was 104 / 56

-- ONE RADIUS SYSTEM -- stepped down with the card
local R_OUTER, R_INNER = 22, 16                 -- was 26 / 18
-- ONE BORDER SYSTEM
local RIM_OUTER, RIM_INNER = 4, 3               -- was 5 / 3

--======================================================================
-- HELPERS -- each REUSES an existing child where one exists, so the re-assert loop can run
-- forever without stacking a second corner/stroke/gradient onto the same element.
--======================================================================
local function corner(o, r)
	local c = o:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	c.CornerRadius = (r == "pill") and UDim.new(1, 0) or UDim.new(0, r)
	c.Parent = o; return c
end
local function stroke(o, col, t, trans)
	local s = o:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	s.Color = col; s.Thickness = t; s.Transparency = trans or 0
	s.LineJoinMode = Enum.LineJoinMode.Round; s.Enabled = true; s.Parent = o; return s
end
local function grad(o, seq, rot)
	local g = o:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	g.Color = seq; g.Rotation = rot or 90; g.Parent = o; return g
end
local function three(a, b, c)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.5, b), ColorSequenceKeypoint.new(1, c),
	})
end
local function deco(parent, class, name)
	local d = parent:FindFirstChild(name)
	if d and d.ClassName ~= class then d:Destroy(); d = nil end
	if not d then d = Instance.new(class); d.Name = name; d.Parent = parent end
	return d
end
local function drop(parent, ...)
	for _, n in ipairs({ ... }) do
		local d = parent:FindFirstChild(n)
		if d then d:Destroy() end
	end
end

-- ===== ONE SUBTLE OUTLINE. NO GOLD, NO METAL TRIM. =====
-- This was goldRim(): a two-ring lit gold bevel (a dark base ring plus a gradient ring on top). It
-- fought every other panel in the game -- the right-side menu, the stats panel and the currency capsule
-- all carry a single thin outline and no metalwork -- and the gold band around a blue HUD was the loudest
-- thing on screen. It is now exactly what those panels use: ONE flat stroke in the darker blue.
--
-- The NAME is kept (every call site below calls goldRim) and so is the hi/mid/lo signature, which is now
-- ignored -- the CTA passed a warmer gold through it, and letting that keep arriving harmlessly is a far
-- smaller change than rewriting nine call sites to a new name. The RimShade frame from the old two-ring
-- build is actively cleared, or a stale one left by an earlier run would keep drawing the outer gold ring.
local function goldRim(o, thickness, _hi, _mid, _lo)
	local stale = o:FindFirstChild("RimShade")
	if stale then stale:Destroy() end
	local s = stroke(o, OUTLINE, math.max(1, (thickness or 3) - 1), 0)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local g = s:FindFirstChildOfClass("UIGradient") -- kill the old lit-gold gradient if one survives
	if g then g:Destroy() end
	return s
end

-- ===== INNER SHADOW RINGS DISABLED (flat UI) =====
-- These stacked 2-3 dark rounded strokes just inside each panel's edge, at increasing inset and
-- transparency, so the edge faded inward like a moulded recess. Together with topLight() above that is
-- what made the HUD look embossed. Same approach as topLight: the helper stays, deletes any ring an
-- earlier run left behind, and returns nil -- so no call site needs touching and nothing is drawn.
local function innerRing(parent, name, _inset, _radius, _thickness, _trans, _col)
	local stale = parent:FindFirstChild(name)
	if stale then stale:Destroy() end
	return nil
end
local function innerRingUNUSED(parent, name, inset, radius, thickness, trans, col)
	local s = deco(parent, "Frame", name)
	s.BackgroundTransparency = 1
	s.Position = UDim2.fromOffset(inset, inset)
	s.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	s.ZIndex = 0
	corner(s, radius)
	stroke(s, col or BLACK, thickness, trans)
	return s
end

-- ===== TOP LIGHT DISABLED (flat UI) =====
-- This laid a white-to-clear gradient across the top 46% of a panel to fake a lit, curved surface. It is
-- the single biggest contributor to the "3D look" and nothing else in this game's UI has one. The helper
-- stays and every call site still calls it -- it now just DELETES any highlight left by an earlier run
-- and returns nil, so the panels render as flat fills with no rewiring of the ten-odd call sites.
local function topLight(parent, _radius, _strength, _zi, _col)
	local stale = parent:FindFirstChild("TopLight")
	if stale then stale:Destroy() end
	return nil
end

-- The game's type: bold white, thick black outline.
local function inkWhite(o, thickness, col)
	o.TextColor3 = WHITE
	stroke(o, col or BLACK, thickness or 4, 0)
end
local function textCap(o, maxSize)
	local c = o:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize; c.Parent = o; return c
end

--======================================================================
-- THE GUT HOLDER -- a recessed navy well with a layered gold ring, matching the game's round
-- icons. GutIcon/GutIconImg are MOVED here rather than redrawn, so gut skins keep rendering;
-- CoreClient addresses them through local upvalues, so they work wherever they sit.
--======================================================================
local function buildHolder(panel)
	-- the drop shadow the well sits in
	local pit = deco(panel, "Frame", "HolderPit")
	pit.Position = UDim2.fromOffset(PAD - 2, HOLDER_Y - 1)
	pit.Size = UDim2.fromOffset(HOLDER + 4, HOLDER + 5)
	pit.BackgroundColor3 = BROWN_SHD
	pit.BackgroundTransparency = 0.6
	pit.BorderSizePixel = 0
	pit.ZIndex = 2
	corner(pit, "pill")

	local holder = deco(panel, "Frame", "GutHolder")
	holder.Position = UDim2.fromOffset(PAD, HOLDER_Y)      -- centred on the title+bar block
	holder.Size = UDim2.fromOffset(HOLDER, HOLDER)
	holder.BackgroundColor3 = WELL
	holder.BorderSizePixel = 0
	holder.ZIndex = 3
	corner(holder, "pill")
	grad(holder, ColorSequence.new(WELL_TOP, WELL), 90)
	goldRim(holder, RIM_INNER)
	innerRing(holder, "InnerRing1", 1, HOLDER, 3, 0.25, BROWN_SHD)    -- the recess, layered
	innerRing(holder, "InnerRing2", 4, HOLDER, 4, 0.7, BROWN_SHD)

	local stack = _G.gui and _G.gui.bottomStack
	local oldRow = stack and stack:FindFirstChild("StomachHud")
	for _, n in ipairs({ "GutIcon", "GutIconImg" }) do
		local ic = holder:FindFirstChild(n) or (oldRow and oldRow:FindFirstChild(n))
		if ic then
			if ic.Parent ~= holder then ic.Parent = holder end
			ic.AnchorPoint = Vector2.new(0.5, 0.5)
			ic.Position = UDim2.new(0.5, 0, 0.5, 0)
			ic.Size = UDim2.fromOffset(ICON, ICON)
			ic.ZIndex = 5
			-- Visible stays CoreClient's: it hides GutIconImg on every tier except XL Gut.
		end
	end
	return holder
end

--======================================================================
-- TOP SECTION -- shell, holder, title, bar
--======================================================================
local function skinTop()
	local g = _G.gui
	local panel = g and g.gasMeterPanel
	if not (panel and panel.Parent) then return end

	drop(panel, "BeanBadge", "GutBadge", "Socket", "Gloss", "InnerShadow", "InnerLine",
		"Crumb1", "Crumb2", "Crumb3")
	for i = 1, 18 do drop(panel, "Star" .. i) end

	-- THE SHELL -- stone gradient, chunky gold trim, layered inner shadow
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.BackgroundColor3 = STONE_MID
	panel.ClipsDescendants = false
	corner(panel, R_OUTER)
	grad(panel, three(STONE_TOP, STONE_MID, STONE_BOT), 90)
	goldRim(panel, RIM_OUTER)
	innerRing(panel, "InnerRing1", 1, R_OUTER - 1, 3, 0.28, BROWN_SHD)
	innerRing(panel, "InnerRing2", 5, R_OUTER - 4, 5, 0.74, BROWN_SHD)

	-- HALO REMOVED. Two soft rings sat GLOW_OUT proud of the card on every side to make it glow against
	-- the world. Nothing else in this UI glows, and an amber halo round a blue panel was part of what made
	-- the HUD look like a lit 3D object. Destroyed rather than skipped, since this runs on a repeating
	-- tick and a ring built by an earlier version would otherwise persist for the session.
	for i = 1, 2 do drop(panel, "OuterGlow" .. i) end

	buildHolder(panel)

	-- THE TITLE -- the gut name, sharing the bar's left edge exactly. The words come from ONE
	-- place: updateStomachDisplay writes StomachHudLabel and nothing else; this MIRRORS it
	-- through a property signal. Nothing here writes Text.
	local stack = g.bottomStack
	local oldRow = stack and stack:FindFirstChild("StomachHud")
	local srcLabel = oldRow and oldRow:FindFirstChild("StomachHudLabel")
	if srcLabel then
		local title = deco(panel, "TextLabel", "GutName")
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextYAlignment = Enum.TextYAlignment.Center
		title.Position = UDim2.fromOffset(COL_X, TITLE_Y)
		title.Size = UDim2.new(1, -(COL_X + PAD), 0, TITLE_H)
		title.ZIndex = 3
		title.Text = srcLabel.Text
		inkWhite(title, 4, BROWN_INK)
		textCap(title, 22)
		if not title:GetAttribute("Mirrored") then
			title:SetAttribute("Mirrored", true)
			srcLabel:GetPropertyChangedSignal("Text"):Connect(function() title.Text = srcLabel.Text end)
		end
		oldRow.Visible = false   -- the old row: hidden, never destroyed
	end

	-- The old "GAS METER" caption has no place in this design and CoreClient owns its Text,
	-- so it is faded rather than rewritten or destroyed.
	local oldTitle = g.gasTitleLabel
	if oldTitle and oldTitle.Parent then
		oldTitle.TextTransparency = 1
		local ts = oldTitle:FindFirstChildOfClass("UIStroke")
		if ts then ts.Enabled = false end
	end

	-- THE TRACK -- embedded: a dark well with its own gold trim and two inner rings, so it
	-- reads as cut into the panel rather than sat on it.
	local bg = g.gasBg
	if bg and bg.Parent then
		bg.BackgroundColor3 = WELL
		bg.BackgroundTransparency = 0
		bg.Position = UDim2.fromOffset(COL_X, BAR_Y)
		bg.Size = UDim2.new(1, -(COL_X + PAD), 0, BAR_H)
		bg.ZIndex = 2
		bg.ClipsDescendants = true       -- keeps the fill's rounded ends inside the well
		corner(bg, "pill")
		grad(bg, ColorSequence.new(WELL_DEEP, WELL_TOP), 90)  -- inset: dark at top
		goldRim(bg, RIM_INNER)
		innerRing(bg, "InnerRing1", 1, BAR_H, 3, 0.3, BROWN_SHD)
	end

	-- THE FILL -- CoreClient drives the WIDTH; this owns the finish.
	--
	-- Both the fill and its gloss are SCALE-sized, never inset by fixed pixels. That is what
	-- the square at the start of the bar was: a highlight inset by a fixed few px collapsed
	-- into a stub at small widths. The fill is also hidden below half a percent so no corner
	-- nub is painted at zero.
	local fill = g.gasFill
	if fill and fill.Parent then
		-- FLAT GREEN, NO GLOSS. The bar was a three-stop gradient with a white gloss strip lying over its
		-- top third -- a glass-tube look. It is now one solid green, and the gloss frame is actively
		-- destroyed (this runs on a repeating tick, so a leftover from an earlier build must be removed
		-- rather than merely not re-created).
		drop(fill, "FillGloss", "LeadingEdge", "FillLight")
		fill.BackgroundColor3 = FILL_YEL
		fill.ZIndex = 3
		corner(fill, "pill")
		grad(fill, three(FILL_HI, FILL_YEL, FILL_ORG), 90) -- the faint ~8% lift, not the old glass ramp
		fill.Visible = fill.Size.X.Scale > 0.005
	end

	-- THE READOUT -- centred in the bar, larger, on a thicker black outline.
	local val = g.gasPowerText
	if val and val.Parent then
		val.Font = Enum.Font.FredokaOne
		val.TextXAlignment = Enum.TextXAlignment.Center
		val.TextYAlignment = Enum.TextYAlignment.Center
		val.ZIndex = 6
		inkWhite(val, 4, BROWN_INK)
		textCap(val, 26)
	end
end

--======================================================================
-- BOTTOM SECTION -- the CTA, built into the panel
--======================================================================
-- CART REMOVED. A hand-drawn shopping trolley (five rounded frames + two ribs) used to sit at the left
-- of this button. At 30px it did not read as a trolley -- it read as a cluster of random shapes -- and
-- nothing else in the HUD carries a drawn icon. The caption now centres in the WHOLE button, so the left
-- inset that reserved the cart's slot is gone too and CAP_LEFT matches CAP_SIDE.
-- (The GUT icon in the holder on the left of the panel is a DIFFERENT thing and is untouched.)
local CAP_SIDE, CAP_TB = 22, 7                  -- the right/vertical padding
local CAP_LEFT         = CAP_SIDE               -- symmetric now: no icon to leave room for
local pressWired = false

-- EMOJI OUT OF THE CAPTION. In UTF-8 every byte of a plain ASCII letter is < 128 and every byte
-- of an emoji is >= 128, so dropping the high bytes takes the puff of wind, the cloud and every
-- other pictograph out while leaving "TAP TO FART!" untouched. Then the double space it leaves
-- behind is closed up. All three captions are pure ASCII, so nothing legitimate can be caught.
local function plain(s)
	local t = tostring(s or "")
	t = t:gsub("[\128-\255]", "")
	t = t:gsub("%s+", " ")
	return t:match("^%s*(.-)%s*$") or t
end

local function fitCaption(o)
	o.Position = UDim2.new(0, 0, 0, 0)
	o.Size = UDim2.new(1, 0, 1, 0)
	o.TextScaled = true
	o.TextXAlignment = Enum.TextXAlignment.Center
	o.TextYAlignment = Enum.TextYAlignment.Center
	local p = o:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, CAP_TB); p.PaddingBottom = UDim.new(0, CAP_TB)
	p.PaddingLeft = UDim.new(0, CAP_LEFT); p.PaddingRight = UDim.new(0, CAP_SIDE)
	p.Parent = o
	textCap(o, 34)   -- up from 29, so the text fills the button
end

--======================================================================
-- FOSSIL ROCK -- texture with a light touch.
--======================================================================
-- Polished stone is not a pattern, it is IRREGULARITY: a scatter of mineral flecks and a couple
-- of pale veins running through the body. Both are painted at 0.85-0.94 transparency, so from a
-- normal viewing distance they only stop the gradient reading as flat plastic -- you notice them
-- when you look for them and not before.
--
-- The positions are a FIXED table rather than random, because this whole file re-asserts itself
-- four times a second: random flecks would crawl around the button every quarter second. Fixed
-- table + deco() by name = the same speck lands on the same pixel forever.
local FLECKS = {   -- {x scale, y scale, px, dark?}
	{ 0.05, 0.31, 3, false }, { 0.10, 0.71, 2, true  }, { 0.17, 0.24, 2, false },
	{ 0.24, 0.62, 3, true  }, { 0.31, 0.36, 2, false }, { 0.38, 0.77, 2, false },
	{ 0.45, 0.27, 3, true  }, { 0.52, 0.59, 2, false }, { 0.59, 0.39, 2, true  },
	{ 0.66, 0.73, 3, false }, { 0.72, 0.30, 2, false }, { 0.79, 0.65, 2, true  },
	{ 0.86, 0.42, 3, false }, { 0.93, 0.70, 2, false }, { 0.97, 0.33, 2, true  },
}
local VEINS = {    -- {x scale, y scale, px long, degrees}
	{ 0.14, 0.38, 118, -5 }, { 0.58, 0.64, 92, 4 }, { 0.36, 0.21, 64, -3 },
}

-- FOSSIL GRAIN REMOVED. Fifteen specks and three hairline veins were scattered across the button to
-- break up its gradient and read as weathered stone. With the gradient gone and the button now a flat
-- green, the speckling is just dirt on a clean surface -- and it belonged to the sunbaked-stone palette
-- this HUD no longer uses. Destroys any speck a previous build left behind (this runs on a tick).
local function fossilGrain(frame)
	for i = 1, #FLECKS do drop(frame, "Fleck" .. i) end
	for i = 1, #VEINS  do drop(frame, "Vein"  .. i) end
end

--======================================================================
-- THE CART -- drawn, not typed.
-- REMOVE the drawn shopping-cart icon (and any leftovers from earlier passes that built it).
-- It was five rounded frames plus two ribs meant to read as a trolley; at 30px on the button it just
-- looked like a handful of random shapes, and no other element in this HUD has a drawn icon.
-- This is a DESTRUCTOR, not a builder: the CTA is re-skinned on a repeating tick, so it also has to
-- clear a cart left behind by a previous run (or by a stale duplicate script) rather than only skip
-- drawing a new one. The gut icon lives in the panel's holder, not here, and is not touched.
local function removeCart(frame)
	local cart = frame:FindFirstChild("CartIcon")
	if cart then cart:Destroy() end
end

--======================================================================
-- THE COLOUR, HELD AGAINST CoreClient
--======================================================================
-- CoreClient repaints this button on every state change and it still thinks the button is green:
-- grey + grey gradient with no food, then 80,210,80 + a green gradient the instant you tap, and
-- a green stroke on both. The re-assert loop below runs 4x/sec, which is FAR too slow for that --
-- you tap, the button goes green, and a quarter second later it turns amber again. That flash is
-- what you were seeing on "FARTING!".
--
-- So the colour is pulled out into its own function and driven by CoreClient's own writes: the
-- moment it touches the fill, the gradient, the stroke or Active, this paints back over it in the
-- SAME frame. The 0.25s loop stays as a backstop for anything that repaints without a signal.
--
-- Note the gradient: it is _G.gui.fartBtnGradient, the exact instance CoreClient keeps a handle
-- to, so setting the frame's fill alone would leave a green gradient painted on top of amber.
local ctaWired, painting = false, false

local function paintCTA(frame, btn)
	if painting then return end          -- our own writes re-enter through the same signals
	painting = true
	local live = not (btn and btn.Active == false)
	frame.BackgroundColor3 = live and AMBER or AMBER_DIM
	local g = frame:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = live and three(AMBER, ORANGE_BRN, RED_WARM) or three(AMBER_DIM, ORANGE_DIM, RED_DIM)
		g.Rotation = 90
	end
	local s = frame:FindFirstChildOfClass("UIStroke")
	if s then
		-- The stroke is now a FLAT dark-blue outline (the lit-gold gradient child it used to carry is
		-- gone), so it must be the outline colour itself -- forcing WHITE here, as this did while the
		-- gradient existed, would leave a bright white ring round the button and undo the restyle.
		s.Color = OUTLINE
		s.Thickness = RIM_INNER
	end
	painting = false
end

local function skinCTA()
	local g = _G.gui
	local panel = g and g.gasMeterPanel
	local frame = g and g.fartBtnFrame
	if not (panel and panel.Parent and frame) then return end
	local btn = g.fartBtn
	local live = not (btn and btn.Active == false)

	-- Leftovers from older passes. The cart is NOT in this list any more -- it is built below,
	-- in the palette, rather than deleted.
	drop(frame, "CartDivider",
		"BurgerIcon", "CupIcon", "StateTint", "InnerShadow", "InnerLine")
	for i = 1, 16 do drop(frame, "Star" .. i) end

	-- INTO THE PANEL. The reparent that makes the two pieces one component, re-asserted so a
	-- rival pass that moves it back is undone rather than fought per-frame.
	if frame.Parent ~= panel then frame.Parent = panel end
	frame.Position = UDim2.fromOffset(PAD, BTN_Y)
	frame.Size = UDim2.new(1, -(PAD * 2), 0, BTN_H)
	frame.ZIndex = 3

	-- SUNBAKED STONE, NOT BLUE PLASTIC. Golden amber at the lit top, burnt orange through the
	-- body, warm red where it turns away from the light -- the ramp the dirt paths already use.
	-- "No food yet" is the SAME ramp a shade deeper rather than a grey-out: this is the button
	-- that sends you to the shop, so the state that means "go buy something" has to stay the
	-- loudest thing on the HUD. The caption and its transparency still carry the state.
	corner(frame, R_INNER)
	paintCTA(frame, btn)

	-- WARM GOLD TRIM, then a soft orange stroke just inside it. Two rings a pixel apart is what
	-- turns a flat outline into a rounded metal edge with light running along it; the orange one
	-- is the inner lighting, the colour of the button's own body bouncing back off the rim.
	goldRim(frame, RIM_INNER, RIM_HI, RIM_MID, RIM_LO)
	innerRing(frame, "InnerRing1", 1, R_INNER - 1, 2, 0.42, ORANGE_LIT)
	innerRing(frame, "InnerRing2", 3, R_INNER - 2, 3, 0.72, BROWN_SHD)

	-- One-time hookup, AFTER goldRim, so the stroke it listens on is guaranteed to exist. From
	-- here the button is amber within the same frame as CoreClient's write, not on the next tick,
	-- so there is no green at all -- not even for one frame.
	if not ctaWired and btn then
		ctaWired = true
		local function hold() paintCTA(frame, btn) end
		frame:GetPropertyChangedSignal("BackgroundColor3"):Connect(hold)
		btn:GetPropertyChangedSignal("Active"):Connect(hold)
		local fg = frame:FindFirstChildOfClass("UIGradient")
		if fg then fg:GetPropertyChangedSignal("Color"):Connect(hold) end
		local fs = frame:FindFirstChildOfClass("UIStroke")
		if fs then fs:GetPropertyChangedSignal("Color"):Connect(hold) end
	end

	fossilGrain(frame)
	topLight(frame, R_INNER - 2, 0.82, 3, CREAM)   -- now a no-op destructor (see topLight)

	-- ===== THE BUTTON IS A FLAT GREEN SLAB =====
	-- It used to carry FOUR separate depth layers on top of its gradient: a cream GLOSS band across the
	-- top, a BottomShade bevel across the bottom, a top light, and a CtaBase shadow plate offset 6px
	-- below it. Stacked, that is a moulded plastic button -- the exact "3D look" being removed. All four
	-- are destroyed (not merely skipped): this function runs on a repeating tick, so anything an earlier
	-- build created has to be actively cleared or it stays for the session.
	drop(frame, "Gloss", "BottomShade", "TopLight")
	drop(panel, "CtaBase")

	removeCart(frame)

	-- THE CAPTION -- bold white on a dark outline, centred in the whole button now the cart is gone.
	-- CoreClient owns the words and Active across its three states; this owns the ink and the box.
	if btn and btn.Parent then
		btn.Font = Enum.Font.FredokaOne
		btn.TextTransparency = live and 0 or 0.15
		btn.ZIndex = 6
		fitCaption(btn)
		inkWhite(btn, 4, BROWN_INK)   -- white on dark brown: max contrast, still in the palette

		-- Scrubbed ON the change rather than on the 0.25s tick, so an emoji CoreClient writes is
		-- gone in the same frame instead of flashing up for a quarter second. Re-entry is safe:
		-- the second pass computes the same string, and assigning a Text its existing value does
		-- not fire the signal again.
		local function scrub()
			local clean = plain(btn.Text)
			if clean ~= btn.Text then btn.Text = clean end
		end
		if not btn:GetAttribute("Scrubbed") then
			btn:SetAttribute("Scrubbed", true)
			btn:GetPropertyChangedSignal("Text"):Connect(scrub)
		end
		scrub()
	end

	-- A SOFT SHADOW UNDER THE TEXT -- a dark copy 2px down at low opacity, sitting behind the
	-- caption. It MIRRORS the caption's text through a property signal, so CoreClient still
	-- writes exactly one Text and the two can never drift apart across its three states.
	if btn and btn.Parent then
		local ts = deco(frame, "TextLabel", "CaptionShadow")
		ts.BackgroundTransparency = 1
		ts.Font = Enum.Font.FredokaOne
		ts.TextColor3 = BROWN_SHD
		ts.TextTransparency = 0.58
		ts.ZIndex = 5
		ts.Text = plain(btn.Text)
		fitCaption(ts)
		ts.Position = UDim2.new(0, 0, 0, 2)
		if not ts:GetAttribute("Mirrored") then
			ts:SetAttribute("Mirrored", true)
			btn:GetPropertyChangedSignal("Text"):Connect(function() ts.Text = plain(btn.Text) end)
		end
	end

	-- NO GLYPHS ON THIS BUTTON. Two separate sources put one there:
	--
	--   1. fartCloudLabel, a "\u{2601}" sat at the button's left edge, which CoreClient turns
	--      Visible on the two ACTIVE states -- so it appeared exactly when you tapped and the
	--      button said FARTING!. Blanked, faded AND its stroke switched off: emptying the string
	--      is the part that actually guarantees it, since transparency leaves a UIStroke still
	--      drawing an outline round invisible text, and Visible is CoreClient's to toggle.
	--   2. the caption itself: older builds write "\u{1F4A8} BUY FOOD FIRST!" with the puff of
	--      wind baked into the string, and the copy of CoreClient actually running in the place
	--      may well be one of those. Nothing here can stop it writing that, so the text is
	--      scrubbed the instant it lands -- see the caption block above.
	local cloud = g.fartCloudLabel
	if cloud and cloud.Parent then
		cloud.Text = ""            -- the one Text this file writes, and it is safe: CoreClient sets
		                           -- this label's Text ONCE, when it builds it, and never again --
		                           -- it only ever toggles Visible afterwards. Blanking beats fading
		                           -- because there is then nothing left to render at all.
		cloud.TextTransparency = 1
		cloud.TextStrokeTransparency = 1
		local cs = cloud:FindFirstChildOfClass("UIStroke")
		if cs then cs.Enabled = false end
	end

	-- ...and the catch-all, by CONTENT rather than by name, because a stale baked copy of
	-- CoreClient can put its own glyph label in here under a name this file has never heard of.
	-- Every label in the button gets any non-ASCII stripped; the captions are pure ASCII, so the
	-- words are never touched.
	for _, d in ipairs(frame:GetChildren()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			local clean = plain(d.Text)
			if clean ~= d.Text then d.Text = clean end
		end
	end

	-- PRESS FEEL -- a small dip that settles the button into its own shadow. Cosmetic only:
	-- the input is still the button's existing Activated handler.
	if not pressWired and btn and btn.Parent then
		pressWired = true
		local sc = frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		sc.Parent = frame
		local rest = sc.Scale
		btn.MouseButton1Down:Connect(function()
			TweenService:Create(sc, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Scale = rest * 0.97 }):Play()
		end)
		local function release()
			TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = rest }):Play()
		end
		btn.MouseButton1Up:Connect(release)
		btn.MouseLeave:Connect(release)
	end
end

--======================================================================
-- THE STACK -- with the button now inside the panel, the panel is the only visible row.
--======================================================================
local function skinStack()
	local stack = _G.gui and _G.gui.bottomStack
	local lay = stack and stack:FindFirstChildOfClass("UIListLayout")
	if not lay then return end
	lay.Padding = UDim.new(0, 0)
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
end

--======================================================================
-- RUN
--======================================================================
local function skin()
	local ok, err = pcall(skinStack)
	if not ok then warn("[FoodHUD] stack failed: " .. tostring(err)) end
	ok, err = pcall(skinTop)
	if not ok then warn("[FoodHUD] top failed: " .. tostring(err)) end
	ok, err = pcall(skinCTA)
	if not ok then warn("[FoodHUD] cta failed: " .. tostring(err)) end
end

task.spawn(function()
	for _ = 1, 240 do
		if _G.gui and _G.gui.gasMeterPanel and _G.gui.fartBtnFrame then break end
		task.wait(0.25)
	end
	skin()
	print(("[FoodHUD] warm pass -- card %dx%d (+halo %dx%d), pad %d, radius %d/%d, gold rim %dpx. "
		.. "NO NAVY: sandstone shell, dark-earth wells, %dpx inset bar with yellow->orange fill + gloss. CTA is "
		.. "amber->burnt orange->warm red, warm gold trim over a soft orange inner stroke, cream "
		.. "gloss, %d fossil flecks + %d veins, brown shadows, drawn cream-gold cart. Amber in "
		.. "EVERY state -- CoreClient's green/grey repaints are caught on the signal, so there is "
		.. "no flash on FARTING. No emoji: cloud blanked, every label in the button scrubbed of "
		.. "non-ASCII on write. Restyle + one reparent; every value, state and handler is still "
		.. "CoreClient's."):format(
		PANEL_W, PANEL_H, PANEL_W + GLOW_OUT * 2, PANEL_H + GLOW_OUT * 2,
		PAD, R_OUTER, R_INNER, RIM_OUTER, BAR_H, #FLECKS, #VEINS))

	-- Re-assert slowly. CoreClient re-stamps the button's colour on every state change and
	-- re-asserts the bottom stack 4x/sec; 0.25s sits on top of that without a frame cost.
	while true do
		task.wait(0.25)
		skin()
	end
end)
