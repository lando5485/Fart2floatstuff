--======================================================================
-- FoodRealmHud.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- ONE unified bottom HUD -- stomach readout + shop call-to-action in a single panel, in the
-- colours of the world it sits in: sunbaked stone, wells of dark earth cut into it, chunky
-- golden-yellow trim, and an amber CTA. This is a dinosaur realm, so nothing in here is blue --
-- the navy the panel used to share with the Stats panel is what made it read as a stock
-- simulator HUD dropped on top of the game rather than as part of it.
--
-- Warm from front to back: stone shell, gold rim, amber -> burnt orange -> warm red button,
-- brown shadows throughout. No emoji anywhere on the button -- see the caption scrub below.
--
--    . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .    <- halo, 484 x 158
--   +================================================================+   <- gold rim, 4px
--   |  (( ))   Tiny Gut                                              |   <- recessed well, layered ring
--   |  ((ic))  [############ 0/100 ##############]                   |   <- inset bar, 382 x 36
--   |  [  (cart)   BUY FOOD FIRST!                              ]    |   <- 446 x 52, amber->orange->red
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
-- THE SHELL -- sunbaked stone, not navy. The panel used to borrow the blue of the Stats panel
-- and the currency bar, which is exactly what made this HUD read as a generic simulator: a cold
-- slab under a warm world. It is now the sandstone of the paths, lit from above, and the wells
-- cut into it are the wet earth underneath.
local STONE_TOP  = Color3.fromRGB(192, 134, 80)   -- #C08650  lit from above
local STONE_MID  = Color3.fromRGB(160, 102, 56)   -- #A06638
local STONE_BOT  = Color3.fromRGB(126, 72, 36)    -- #7E4824
local WELL       = Color3.fromRGB(58, 31, 15)     -- recessed: icon holder, bar track
local WELL_TOP   = Color3.fromRGB(82, 46, 24)
local WELL_DEEP  = Color3.fromRGB(42, 21, 9)      -- the darkest point of an inset, right at its top lip
local GOLD       = Color3.fromRGB(244, 180, 0)    -- #F4B400
local GOLD_LT    = Color3.fromRGB(255, 222, 108)
local GOLD_DEEP  = Color3.fromRGB(186, 128, 0)
local FILL_HI    = Color3.fromRGB(255, 240, 170)
local FILL_YEL   = Color3.fromRGB(255, 216, 74)   -- #FFD84A
local FILL_ORG   = Color3.fromRGB(245, 166, 35)   -- #F5A623
local BLACK      = Color3.fromRGB(0, 0, 0)
local WHITE      = Color3.fromRGB(255, 255, 255)

-- THE CTA'S OWN WARM SET -- golden amber down through burnt orange into a warm red foot, the
-- same ramp as the dirt paths outside. Nothing in here is a blue-grey: even the shadows are
-- brown, because a black shadow under an orange button reads as soot rather than as depth.
local AMBER      = Color3.fromRGB(255, 178, 52)   -- #FFB234  golden amber, the lit top
local ORANGE_BRN = Color3.fromRGB(230, 112, 30)   -- #E6701E  burnt orange, the body
local RED_WARM   = Color3.fromRGB(186, 58, 30)    -- #BA3A1E  warm red, the shaded foot
local AMBER_DIM  = Color3.fromRGB(236, 164, 60)   -- the same ramp, a shade deeper, for "no food yet"
local ORANGE_DIM = Color3.fromRGB(206, 102, 34)
local RED_DIM    = Color3.fromRGB(162, 54, 28)
local ORANGE_LIT = Color3.fromRGB(255, 158, 74)   -- the soft inner stroke: light bouncing round the rim
local RIM_HI     = Color3.fromRGB(255, 234, 158)  -- warm gold trim, lit from above
local RIM_MID    = Color3.fromRGB(250, 194, 68)
local RIM_LO     = Color3.fromRGB(158, 92, 20)
local CREAM      = Color3.fromRGB(255, 246, 222)  -- the gloss across the top
local CREAM_GOLD = Color3.fromRGB(255, 228, 164)  -- the cart's body
local BROWN_INK  = Color3.fromRGB(74, 34, 14)     -- outlines: the cart, the caption
local BROWN_SHD  = Color3.fromRGB(58, 24, 10)     -- shadows: under the button, inside its rim

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

-- A GOLD RIM WITH DEPTH. Two strokes rather than one: a dark base ring sitting a pixel out,
-- and the lit gradient ring on top of it. That reads as a rounded metal trim catching light
-- from above instead of a flat outline -- the same look the Stats panel and Shop buttons use.
-- hi/mid/lo are optional: the CTA passes a warmer gold so its trim sits with amber rather than
-- with navy. Omitted, it is the panel's existing yellow-gold, unchanged.
local function goldRim(o, thickness, hi, mid, lo)
	hi, mid, lo = hi or GOLD_LT, mid or GOLD, lo or GOLD_DEEP
	local shade = deco(o, "Frame", "RimShade")
	shade.BackgroundTransparency = 1
	shade.Position = UDim2.fromOffset(-1, 0)
	shade.Size = UDim2.new(1, 2, 1, 2)
	shade.ZIndex = 0
	local sc = o:FindFirstChildOfClass("UICorner")
	corner(shade, sc and sc.CornerRadius.Scale == 1 and "pill" or ((sc and sc.CornerRadius.Offset or 8) + 1))
	stroke(shade, lo, thickness, 0.25)

	local s = stroke(o, WHITE, thickness, 0)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local g = s:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	g.Color = three(hi, mid, lo); g.Rotation = 90; g.Parent = s
	return s
end

-- SOFT INNER SHADOW. Roblox has no inset stroke, so this is an empty frame inset by N pixels
-- carrying a black rounded stroke. Called more than once at different insets and opacities,
-- the rings stack into a soft gradient inward from the edge rather than one hard line.
-- col is optional: black inside the navy panel, warm brown (or a lit orange) inside the CTA.
local function innerRing(parent, name, inset, radius, thickness, trans, col)
	local s = deco(parent, "Frame", name)
	s.BackgroundTransparency = 1
	s.Position = UDim2.fromOffset(inset, inset)
	s.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	s.ZIndex = 0
	corner(s, radius)
	stroke(s, col or BLACK, thickness, trans)
	return s
end

-- Ambient highlight -- depth without gloss. Scale-sized so it can never collapse into a stub.
local function topLight(parent, radius, strength, zi, col)
	local hi = deco(parent, "Frame", "TopLight")
	hi.BackgroundColor3 = col or WHITE
	hi.BorderSizePixel = 0
	hi.Position = UDim2.fromScale(0, 0)
	hi.Size = UDim2.new(1, 0, 0.46, 0)
	hi.ZIndex = zi or 1
	corner(hi, radius)
	local g = hi:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, strength), NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = hi
	return hi
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

	-- THE HALO -- 484 x 158, i.e. GLOW_OUT proud of the card on every side, built as two rings
	-- rather than one so it falls off softly instead of ending in a hard line. Both are CHILDREN
	-- of the card (a child always draws in front of its parent), so only the part of each stroke
	-- lying outside the card's own edge is ever visible -- the fill never washes over the card.
	for i, ring in ipairs({ { 4, 3, 0.62 }, { GLOW_OUT, 3, 0.84 } }) do
		local out, thick, trans = ring[1], ring[2], ring[3]
		local halo = deco(panel, "Frame", "OuterGlow" .. i)
		halo.BackgroundTransparency = 1
		halo.Position = UDim2.fromOffset(-out, -out)
		halo.Size = UDim2.new(1, out * 2, 1, out * 2)
		halo.ZIndex = 0
		corner(halo, R_OUTER + out)
		stroke(halo, AMBER, thick, trans)
	end

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
		drop(fill, "FillGloss", "LeadingEdge")
		fill.BackgroundColor3 = WHITE          -- white so the gradient reads true
		fill.ZIndex = 3
		corner(fill, "pill")
		grad(fill, three(FILL_HI, FILL_YEL, FILL_ORG), 90)
		fill.Visible = fill.Size.X.Scale > 0.005

		local gloss = deco(fill, "Frame", "FillLight")
		gloss.BackgroundColor3 = WHITE
		gloss.BorderSizePixel = 0
		gloss.Position = UDim2.fromScale(0, 0.08)
		gloss.Size = UDim2.new(1, 0, 0.34, 0)
		gloss.ZIndex = 4
		corner(gloss, "pill")
		local gg = gloss:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
		gg.Rotation = 90
		gg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1),
		})
		gg.Parent = gloss
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
-- The caption still fills the button and centres by geometry; the only asymmetry is the left
-- inset, which is the cart's slot -- so the words centre in the space the cart LEAVES instead
-- of running underneath it. Top/bottom stay small and equal.
-- Re-fitted to the measured 446 x 52 box: on a 52px-tall button the cart drops to 30 (11px clear
-- top and bottom) and the paddings come in with it.
local CAP_SIDE, CAP_TB = 22, 7                  -- the right/vertical padding
local CART_X, CART_S   = 14, 30                 -- the cart's left offset and box
local CAP_LEFT         = CART_X + CART_S + 12   -- 56: past the cart, with a breath after it
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

local function fossilGrain(frame)
	for i, f in ipairs(FLECKS) do
		local d = deco(frame, "Frame", "Fleck" .. i)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromScale(f[1], f[2])
		d.Size = UDim2.fromOffset(f[3], f[3])
		d.BackgroundColor3 = f[4] and BROWN_SHD or CREAM
		d.BackgroundTransparency = f[4] and 0.88 or 0.85
		d.BorderSizePixel = 0
		d.ZIndex = 2
		corner(d, "pill")
	end
	for i, v in ipairs(VEINS) do
		local d = deco(frame, "Frame", "Vein" .. i)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromScale(v[1], v[2])
		d.Size = UDim2.fromOffset(v[3], 2)
		d.Rotation = v[4]
		d.BackgroundColor3 = CREAM
		d.BackgroundTransparency = 0.94
		d.BorderSizePixel = 0
		d.ZIndex = 2
		corner(d, "pill")
	end
end

--======================================================================
-- THE CART -- drawn, not typed.
--======================================================================
-- A 🛒 emoji cannot be recoloured: the font renders it in its own colours and TextColor3 is
-- ignored, so it would stay the one cold blue-grey object on a warm button. Five rounded frames
-- give the same read at this size AND take the palette -- cream-gold body, dark brown edge.
local function buildCart(frame)
	local cart = deco(frame, "Frame", "CartIcon")
	cart.BackgroundTransparency = 1
	cart.AnchorPoint = Vector2.new(0, 0.5)
	cart.Position = UDim2.new(0, CART_X, 0.5, -1)
	cart.Size = UDim2.fromOffset(CART_S, CART_S)
	cart.ZIndex = 7

	-- Drawn to a 30px box (CART_S), the size that leaves 11px clear above and below inside the
	-- measured 52px button. Thinner outline on the wheels: 2px round a 7px circle is nearly all
	-- outline.
	local function piece(name, x, y, w, h, r, rot, edge)
		local p = deco(cart, "Frame", name)
		p.BackgroundColor3 = CREAM_GOLD
		p.BorderSizePixel = 0
		p.Position = UDim2.fromOffset(x, y)
		p.Size = UDim2.fromOffset(w, h)
		p.Rotation = rot or 0
		p.ZIndex = 7
		corner(p, r)
		local s = stroke(p, BROWN_INK, edge or 2, 0)
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		return p
	end

	piece("Handle",     1,  6, 11,  4, 2, -30)  -- the push bar, angled up out of the basket
	piece("BasketRim",  6,  8, 23,  4, 2)       -- the lip
	local body = piece("BasketBody", 8, 11, 19, 11, 3)
	piece("Wheel1",    11, 22,  7,  7, "pill", 0, 1.5)
	piece("Wheel2",    20, 22,  7,  7, "pill", 0, 1.5)

	for i = 1, 2 do                             -- two ribs, so the basket reads as a basket
		local rib = deco(body, "Frame", "Rib" .. i)
		rib.BackgroundColor3 = BROWN_INK
		rib.BackgroundTransparency = 0.55
		rib.BorderSizePixel = 0
		rib.Position = UDim2.fromOffset(4 + (i - 1) * 6, 3)
		rib.Size = UDim2.fromOffset(2, 5)
		rib.ZIndex = 8
		corner(rib, 1)
	end
	return cart
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
		-- WHITE, because the gold lives in the gradient CHILD of this stroke and a coloured stroke
		-- would tint it. CoreClient's green/grey goes here; white is the neutral that lets the gold through.
		s.Color = WHITE
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
	topLight(frame, R_INNER - 2, 0.82, 3, CREAM)   -- faint ambient lift; the gloss below does the shine

	-- THE GLOSS -- a single cream band across the top, inset a few px from the sides so it reads
	-- as light lying ON a curved face rather than as a paler stripe painted edge to edge.
	local gloss = deco(frame, "Frame", "Gloss")
	gloss.BackgroundColor3 = CREAM
	gloss.BorderSizePixel = 0
	gloss.Position = UDim2.fromOffset(7, 4)
	gloss.Size = UDim2.new(1, -14, 0.36, 0)
	gloss.ZIndex = 4
	corner(gloss, R_INNER - 5)
	do
		local gg = gloss:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
		gg.Rotation = 90
		gg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, live and 0.52 or 0.66),
			NumberSequenceKeypoint.new(0.55, 0.86),
			NumberSequenceKeypoint.new(1, 1),
		})
		gg.Parent = gloss
	end

	local shade = deco(frame, "Frame", "BottomShade")   -- the lower half of the bevel
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.BackgroundColor3 = BROWN_SHD                  -- brown, not black: shadow, not soot
	shade.BorderSizePixel = 0
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.new(1, 0, 0.34, 0)
	shade.ZIndex = 4
	corner(shade, R_INNER - 2)
	do
		local sg = shade:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
		sg.Rotation = 90
		sg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.78),
		})
		sg.Parent = shade
	end

	buildCart(frame)

	-- the plate the button sits on: warm brown, so the shadow belongs to this button in this
	-- world and not to a blue one borrowed from somewhere else
	local base = deco(panel, "Frame", "CtaBase")
	base.Position = UDim2.fromOffset(PAD, BTN_Y + 6)
	base.Size = UDim2.new(1, -(PAD * 2), 0, BTN_H)
	base.BackgroundColor3 = BROWN_SHD
	base.BackgroundTransparency = 0.5
	base.BorderSizePixel = 0
	base.ZIndex = 2
	corner(base, R_INNER)

	-- THE CAPTION -- bold white on a dark brown outline, sat in the space right of the cart.
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
