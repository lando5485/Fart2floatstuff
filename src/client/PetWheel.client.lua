--!nonstrict
-- PetWheel (StarterPlayer/StarterPlayerScripts/PetWheel)
-- ============================================================================================================
-- CLIENT for the Robux "Pet Wheel". This script ONLY draws the panel, prompts the Robux purchases, and animates
-- the wheel to the result the SERVER sends. It never decides an outcome, never rolls, and never grants anything
-- (PetWheel.server.lua is the authority). It is a self-contained script (per the "new client logic in its own
-- script" rule) -- it touches no other client module's state.
--
-- HONEST ODDS: the Odds panel lists every segment and its % straight from the SHARED PetWheelConfig.SEGMENTS
-- table -- the exact same table the server rolls on -- so the shown odds can never differ from the real odds.
--
-- ENTRY POINT: exposes _G.togglePetWheel(); the Pet menu (PetHub_AllInOne) calls it to open the panel.
--
-- BUYING SPINS: while PetWheelConfig.TEST_MODE is true there are no real Developer Products yet, so a buy card
-- fires "buy" and the SERVER credits the pack (same addSpins() the real receipt uses). The client never edits
-- its own spin count either way -- it only ever displays the number the server pushes back -- so the test path
-- and the shipping path exercise exactly the same code from the grant onward. Set TEST_MODE = false once the
-- real product ids are pasted in and the identical click opens the Roblox purchase prompt instead.
--
-- VISUAL LAYER (premium simulator styling) -- purely cosmetic, no gameplay meaning:
--   * everything is drawn from Frames/gradients/emoji. NO external image assets, so nothing can fail to load.
--   * "radial gradient" / glow = stacked concentric circles (Roblox UIGradient has no radial mode).
--   * all idle motion (twinkling stars, floating sparkles, mythic pulse) is driven by ONE Heartbeat loop that
--     early-outs while the panel is closed, so a closed wheel costs nothing.
-- ============================================================================================================

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local SoundService       = game:GetService("SoundService")   -- reward-reveal payoff sound (routed to SFXGroup)
local Debris             = game:GetService("Debris")         -- burst/confetti cleanup

local player  = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local Config  = require(Shared:WaitForChild("PetWheelConfig"))
local remote  = ReplicatedStorage:WaitForChild("PetWheelEvent")

-- Canonical "give me my owned pets" fetch, the SAME RemoteFunction the existing crate pet-picker uses. Returns
-- a list of { petId, displayName, level, maxed, xpPct }. Fetched lazily so we don't hard-depend on load order.
local function fetchOwnedPets()
	local crateRemotes = ReplicatedStorage:FindFirstChild("CrateRemotes")
	local rf = crateRemotes and crateRemotes:FindFirstChild("GetOwnedPets")
	if not rf then return {} end
	local ok, list = pcall(function() return rf:InvokeServer() end)
	if ok and type(list) == "table" then return list end
	return {}
end

-- ============================================================================================================
-- THEME -- one place for every colour so the whole panel stays consistent.
-- ============================================================================================================
-- The palette is deliberately the SAME one the Daily Rewards crate reveal / Pet Hub / shops already use --
-- bright cartoon blue (#1a4fd6 family), white borders, lime and gold accents. The wheel used to be near-black
-- purple, which read as a casino next to the rest of the game; matching the house colours makes it read as the
-- same friendly game, and it means the reward reveal below can share these exact values.
local T = {
	panelTop    = Color3.fromRGB( 46, 111, 232),   -- bright blue panel gradient TOP
	panelBot    = Color3.fromRGB( 20,  66, 190),   -- #1442be-ish bottom, same ramp as the crate panel
	cardTop     = Color3.fromRGB( 78, 145, 248),   -- cards sit LIGHTER than the panel so they lift off it
	cardBot     = Color3.fromRGB( 44, 104, 224),
	goldLight   = Color3.fromRGB(255, 244, 186),
	gold        = Color3.fromRGB(255, 210,  74),   -- #ffd24a, the house gold
	goldDeep    = Color3.fromRGB(228, 162,  32),
	goldShadow  = Color3.fromRGB(178, 118,  16),
	-- Lime, not the old muted sage: this is the game's "good news" colour (#7ed957) and it belongs on the SPIN
	-- button, which is the one thing in the panel we want a kid to press.
	greenLight  = Color3.fromRGB(182, 244, 130),
	green       = Color3.fromRGB(126, 217,  87),
	greenDeep   = Color3.fromRGB( 74, 168,  42),
	redLight    = Color3.fromRGB(255, 132, 138),
	red         = Color3.fromRGB(232,  72,  84),
	textBright  = Color3.fromRGB(255, 255, 255),
	textSoft    = Color3.fromRGB(206, 232, 255),   -- light blue, readable on the bright panel
	textDark    = Color3.fromRGB( 18,  46, 100),   -- navy, for text sitting ON gold/white
	glow        = Color3.fromRGB(140, 200, 255),
	outline     = Color3.fromRGB(255, 255, 255),   -- every panel/card border is white now (the cartoon look)
	shadow      = Color3.fromRGB(  6,  26,  80),   -- navy shadow, never black -- black on blue looks like grime
}

-- Consistent corner radii + outline weights for the WHOLE panel. Use these instead of ad-hoc numbers so nothing
-- drifts: panels/overlays share one radius, cards/buttons share another, small chips share a third.
local R_PANEL, R_CARD, R_SMALL = 24, 16, 12
-- Exactly TWO outline weights exist in this UI: panels/overlays, and everything else. Nothing uses anything in
-- between, which is most of what makes the borders read as deliberate rather than incidental.
local LINE_PANEL, LINE_CARD    = 3, 2

-- One type scale for the whole panel. Every TextSize in this file comes from here -- no ad-hoc sizes -- so the
-- hierarchy stays legible: title > value > card heading > body > label > caption.
-- F_TITLE trimmed 38 -> 36 (~5%): shortens "PET WHEEL" by ~10px, which is real clearance, without reading smaller.
local F_TITLE, F_VALUE, F_CARD, F_BODY, F_LABEL, F_MICRO = 36, 24, 19, 16, 13, 12

-- THE GRID.
--   PANEL_PAD -- distance from the panel edge to any content, identical on the left and the right.
--   GUTTER    -- distance from a card/button edge to its own contents, identical in every card.
-- Every x position in this file is derived from one of these two, so the columns line up by construction.
local PANEL_PAD = 32
local GUTTER    = 16

-- Fixed badge pill. Sized for the longest tag ("BEST VALUE") so every badge is the same shape.
local BADGE_W, BADGE_H = 84, 18

-- ---- tiny UI helpers ----------------------------------------------------------------------------------------
local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(inst, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = inst; return c end
local function round(inst)     local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0);     c.Parent = inst; return c end
-- Border outline. NOTE: ApplyStrokeMode MUST be Border here -- on a TextButton the default (Contextual) would
-- outline the *text* instead of the button edge.
local function stroke(inst, col, th, trans)
	local s = Instance.new("UIStroke")
	s.Color = col; s.Thickness = th or 2; s.Transparency = trans or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end
-- Outline around the glyphs themselves (Contextual on a text object = text outline).
local function textStroke(inst, col, th, trans)
	local s = Instance.new("UIStroke")
	s.Color = col; s.Thickness = th or 2; s.Transparency = trans or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = inst
	return s
end

-- vertical (top -> bottom) two-stop gradient; returns the UIGradient so callers can recolour it later
local function grad(inst, top, bottom, rotation)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = inst
	return g
end
local function setGrad(g, top, bottom)
	g.Color = ColorSequence.new(top, bottom)
end

-- Soft drop shadow: a slightly larger, blurred-looking dark twin sitting behind `inst`. Roblox has no blur, so
-- we stack two low-alpha rounded frames -- close enough at simulator-UI scale and costs no image asset.
local function shadowFor(inst, spread, radius, drop)
	spread, radius, drop = spread or 6, radius or 14, drop or 4
	local parent = inst.Parent
	local a = inst.AnchorPoint
	local made = {}
	for i = 2, 1, -1 do
		local s = spread * i
		-- expand symmetrically regardless of AnchorPoint: shifting by s*(2*anchor - 1) keeps the twin concentric
		local sh = mk("Frame", {
			Name = "Shadow", BackgroundColor3 = T.shadow, BackgroundTransparency = 0.72 + 0.1 * (i - 1),
			AnchorPoint = a, ZIndex = math.max(1, inst.ZIndex - 1), Visible = inst.Visible,
			Size = UDim2.new(inst.Size.X.Scale, inst.Size.X.Offset + s * 2, inst.Size.Y.Scale, inst.Size.Y.Offset + s * 2),
			Position = UDim2.new(
				inst.Position.X.Scale, inst.Position.X.Offset + s * (2 * a.X - 1),
				inst.Position.Y.Scale, inst.Position.Y.Offset + s * (2 * a.Y - 1) + drop),
		}, parent)
		corner(sh, radius + s)
		made[#made + 1] = sh
	end
	-- the shadow is a SIBLING, so it has to follow the owner's visibility or a hidden overlay leaves a dark blob
	inst:GetPropertyChangedSignal("Visible"):Connect(function()
		for _, sh in ipairs(made) do sh.Visible = inst.Visible end
	end)
end

-- Fake radial gradient / glow: concentric circles whose alpha ramps outward. Centred in `parent`.
local function radialGlow(parent, diameter, color, layers, innerTrans, outerTrans, zi)
	layers = layers or 9
	local holder = mk("Frame", {
		Name = "Glow", BackgroundTransparency = 1, Size = UDim2.fromOffset(diameter, diameter),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = zi or 1,
	}, parent)
	for i = layers, 1, -1 do
		local f = i / layers
		-- scale-sized (not offset) so animating the holder's Size actually grows the whole glow
		local ring = mk("Frame", {
			BackgroundColor3 = color, Size = UDim2.fromScale(f, f),
			Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = zi or 1,
			BackgroundTransparency = outerTrans + (innerTrans - outerTrans) * (1 - f),
		}, holder)
		round(ring)
	end
	return holder
end

-- ONE surface treatment shared by every card-like thing (purchase cards, the spins panel, the odds button), so
-- border weight, corner radius, shadow depth and the inner bevel are identical everywhere by construction.
local function cardSkin(frame, shadowSpread)
	corner(frame, R_CARD)
	grad(frame, T.cardTop, T.cardBot)
	stroke(frame, T.outline, LINE_CARD, 0.55)
	shadowFor(frame, shadowSpread or 3, R_CARD, 3)
	-- inner bevel: a hairline light edge along the top, a soft dark one along the bottom
	mk("Frame", {
		Name = "InnerTop", BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.9,
		Size = UDim2.new(1, -28, 0, 1), Position = UDim2.new(0.5, 0, 0, 1), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 8,
	}, frame)
	mk("Frame", {
		Name = "InnerBottom", BackgroundColor3 = T.shadow, BackgroundTransparency = 0.8,
		Size = UDim2.new(1, -28, 0, 2), Position = UDim2.new(0.5, 0, 1, -2), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 8,
	}, frame)
	return frame
end

-- Soft inner shadow for a circular element: concentric rings hugging the inside of the edge, each thinner and
-- fainter than the last. Used on the wheel disc so its rim recedes instead of needing another glow on top.
local function innerShadowCircle(parent, rings, zi)
	for i = 1, (rings or 3) do
		local inset = (i - 1) * 5
		local ring = mk("Frame", {
			Name = "InnerShade", BackgroundTransparency = 1,
			Size = UDim2.new(1, -inset * 2, 1, -inset * 2), Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = zi or 1,
		}, parent)
		round(ring)
		stroke(ring, Color3.fromRGB(16, 56, 148), 6, 0.66 + (i - 1) * 0.13)
	end
end

-- The Robux "R$" chip, drawn (not an asset) so it always renders. Returns the chip frame.
local function robuxChip(parent, size, zi)
	local chip = mk("Frame", {
		Name = "Robux", BackgroundColor3 = T.green, Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = zi or 1,
	}, parent)
	round(chip); grad(chip, T.greenLight, T.greenDeep)
	stroke(chip, Color3.fromRGB(18, 84, 44), LINE_CARD)
	mk("TextLabel", {
		Text = "R$", Font = Enum.Font.GothamBlack, TextSize = math.floor(size * 0.52),
		TextColor3 = Color3.fromRGB(240, 255, 244), BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = (zi or 1) + 1,
	}, chip)
	return chip
end

-- ---- one shared idle-animation loop -------------------------------------------------------------------------
local anims = {}
local function animate(fn) table.insert(anims, fn) end

-- ---- state --------------------------------------------------------------------------------------------------
local spinsOwned = 0
local pendingLevels = 0
local spinning = false

-- PURCHASE STATE. `buying` gates the buy cards while a purchase is in flight so a double-click can't send two
-- requests; the server also cools purchases down, this is purely so the UI can't lie about what it sent.
-- `purchase` is forward-declared here because the buy cards are built (and capture it) further up the file than
-- it can be defined -- it needs showToast/refreshSpinButton, which live near the bottom.
local buying = false
local buyVeils = {}       -- [product.id] = the "..." veil drawn over that card while its purchase is in flight
local purchase            -- purchase(product) -- assigned once the toast/refresh helpers exist

-- ============================================================================================================
-- BUILD THE UI
-- ============================================================================================================
-- PANEL_H grew 620 -> 652 purely to give the header room: CONTENT_TOP moved down 28px so the pointer clears the
-- title, and the bottom margin is unchanged. Nothing inside either column was resized.
local PANEL_W, PANEL_H = 840, 652
-- The y at which both columns start -- the wheel and the right-hand stack share it, so their tops line up.
local CONTENT_TOP = 120

local gui = mk("ScreenGui", {
	Name = "PetWheelGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 100, Enabled = false,
}, playerGui)

local dim = mk("TextButton", {
	Name = "Dim", Text = "", AutoButtonColor = false, BackgroundColor3 = T.shadow,
	BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 1,
}, gui)

-- Active = true here is load-bearing, not cosmetic. A Frame does not sink input in Roblox, so without it a click
-- anywhere on the panel that isn't a button falls straight through to the full-screen `dim` underneath. Marking
-- the panel Active makes it swallow those clicks, so the only thing that can close this UI is the close button.
local panel = mk("Frame", {
	Name = "Panel", BackgroundColor3 = T.panelBot, ClipsDescendants = true, Active = true,
	Size = UDim2.fromOffset(PANEL_W, PANEL_H), Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	ZIndex = 2,
}, gui)
corner(panel, R_PANEL)
grad(panel, T.panelTop, T.panelBot)
stroke(panel, T.outline, LINE_PANEL)
local panelScale = mk("UIScale", {}, panel)

-- very soft outer halo so the panel lifts off the dimmed world (kept faint -- the wheel is the focus)
radialGlow(gui, PANEL_W + 200, T.glow, 6, 0.95, 1, 1).Position = UDim2.fromScale(0.5, 0.5)

-- ---- background --------------------------------------------------------------------------------------------
-- Deliberately almost nothing: the panel's own vertical gradient, plus ONE soft radial glow behind the wheel
-- (created with the wheel further down). No star field, no floating motes, no vignette -- they were competing
-- with the content for attention and none of them carried information.

-- ============================================================================================================
-- HEADER -- paw icon + gold-outlined title + close button
-- ============================================================================================================
-- HEADER GEOMETRY, and why the title used to clip the pointer:
--   The pointer sticks 38px ABOVE the wheel holder, so with the wheel at y=92 its cap started at y=54 -- and a
--   38px title vertically centred in a band at y=18..74 put its glyphs at roughly y=33..60. They overlapped by a
--   few pixels around x=218, which is exactly where the pointer sits. Moving the title right cannot fix that
--   (the pointer is in the middle of the wheel column, so right is INTO it) -- the fix has to be vertical.
--
--   Header band:      24 .. 70   (top padding 18 -> 24)
--   Title line box:   29 .. 65   (36px text centred in a 46px band)
--   Pointer cap top:  82         (CONTENT_TOP 120 - 38)
--   => ~17px clear against the text's full line box, ~22px against the visible capitals.
--
--   That clearance is bought by CONTENT_TOP moving 92 -> 120, which is why the panel grew 620 -> 652. The wheel,
--   the columns and the right-hand rhythm are all unchanged -- the extra height is entirely header breathing room.
local HEADER_Y, HEADER_H = 24, 46
local header = mk("Frame", {
	Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, -PANEL_PAD * 2, 0, HEADER_H),
	Position = UDim2.fromOffset(PANEL_PAD, HEADER_Y), ZIndex = 12,
}, panel)

-- Paw badge sits 6px in from the header's left rail, so the title clears the window border by more than the
-- wheel does while the header block still reads as aligned to the wheel column.
local PAW_X, PAW_D, PAW_GAP = 6, 46, 20      -- 6 + 46 + 20 -> the title starts at x = 72 within the header
local TITLE_X = PAW_X + PAW_D + PAW_GAP
local pawBadge = mk("Frame", {
	BackgroundColor3 = T.gold, Size = UDim2.fromOffset(PAW_D, PAW_D),
	Position = UDim2.new(0, PAW_X, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 12,
}, header)
round(pawBadge); grad(pawBadge, T.goldLight, T.goldDeep); stroke(pawBadge, T.goldShadow, LINE_CARD)
mk("TextLabel", {
	Text = "\xF0\x9F\x90\xBE", Font = Enum.Font.GothamBlack, TextSize = F_VALUE, TextColor3 = T.textDark,
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 13,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, pawBadge)

-- Title shadow (offset dark twin) then the gold-outlined title on top. Both are 36px -- a 5% trim off the old 38
-- that shortens the word by ~10px without reading as smaller. Both are Y-centred in the header band, and so is
-- the paw badge and the close button, so all three share one baseline by construction.
-- The box is a fixed 420 wide (not 1,-150) so it can never run underneath the close button.
mk("TextLabel", {
	Text = "PET WHEEL", Font = Enum.Font.GothamBlack, TextSize = F_TITLE, TextColor3 = Color3.fromRGB(12, 40, 112),
	TextTransparency = 0.5, BackgroundTransparency = 1, Size = UDim2.new(0, 420, 1, 0),
	Position = UDim2.fromOffset(TITLE_X + 2, 3), TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 12,
}, header)
local title = mk("TextLabel", {
	Text = "PET WHEEL", Font = Enum.Font.GothamBlack, TextSize = F_TITLE, TextColor3 = Color3.fromRGB(255, 252, 236),
	BackgroundTransparency = 1, Size = UDim2.new(0, 420, 1, 0), Position = UDim2.fromOffset(TITLE_X, 0),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 13,
}, header)
textStroke(title, T.gold, 2)

local closeBtn = mk("TextButton", {
	-- plain ASCII "X", not a "\xE2\x9C\x95" glyph: the multiply sign is a font-fallback risk, an X never is
	Name = "Close", Text = "X", Font = Enum.Font.GothamBlack, TextSize = F_VALUE - 3,
	TextColor3 = Color3.fromRGB(18, 8, 10),   -- black X, per request
	AutoButtonColor = false, BackgroundColor3 = T.red, Size = UDim2.fromOffset(44, 44),
	Position = UDim2.new(1, -22, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 13,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, header)
corner(closeBtn, R_SMALL); grad(closeBtn, T.redLight, T.red)   -- rounded square, matching the panel's radii
stroke(closeBtn, Color3.fromRGB(255, 255, 255), LINE_PANEL)   -- white ring, same weight as the panel borders
shadowFor(closeBtn, 3, R_SMALL, 3)   -- radius follows the button's corner now that it's a rounded square
mk("Frame", {  -- soft top gloss (wider + softer than before so it reads as a highlight, not a white dot)
	BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.82,
	Size = UDim2.fromOffset(28, 12), Position = UDim2.new(0.5, 0, 0, 5), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 14,
}, closeBtn).Name = "Gloss"
corner(closeBtn:FindFirstChild("Gloss"), 5)

-- ============================================================================================================
-- THE WHEEL -- a decorative bolted outer rim (static) + a spinning disc of rounded reward segments.
-- A fixed gold arrow at the top marks the result. Angle 0 = top (under the pointer), clockwise.
-- ============================================================================================================
local WHEEL_D = 372                                   -- was 300 -- +24% so the wheel is the focal point
local wheelHolder = mk("Frame", {
	Name = "WheelHolder", BackgroundTransparency = 1, Size = UDim2.fromOffset(WHEEL_D, WHEEL_D),
	Position = UDim2.fromOffset(PANEL_PAD, CONTENT_TOP), ZIndex = 4,
}, panel)

-- THE only lighting on the wheel: one soft radial highlight behind it. Nothing else glows.
radialGlow(wheelHolder, WHEEL_D + 170, T.glow, 9, 0.91, 1, 3)

-- ---- outer gold ring (does NOT rotate) ------------------------------------------------------------------------
local RIM_D = WHEEL_D + 42
local RIM_R, DISC_R = RIM_D / 2, WHEEL_D / 2          -- 207 and 186: the band lives between these two radii
local rim = mk("Frame", {
	Name = "Rim", BackgroundColor3 = T.gold, Size = UDim2.fromOffset(RIM_D, RIM_D),
	Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4,
}, wheelHolder)
round(rim); stroke(rim, T.goldShadow, LINE_CARD)
do   -- smooth four-stop metal: highlight, body, a gentle shaded belly, warm again at the base. No hard steps.
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(253, 234, 178)),
		ColorSequenceKeypoint.new(0.38, Color3.fromRGB(244, 206, 124)),
		ColorSequenceKeypoint.new(0.72, Color3.fromRGB(216, 168,  76)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(234, 190, 104)),
	})
	g.Parent = rim
end
-- Inner bevel on the ring: a bright hairline just inside the outer edge and a darker one just outside the disc.
-- Two 1px rings give the band its thickness without a drop shadow.
do
	local lip = mk("Frame", {
		Name = "RimLipOuter", BackgroundTransparency = 1, Size = UDim2.fromOffset(RIM_D - 6, RIM_D - 6),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5,
	}, rim)
	round(lip); stroke(lip, Color3.fromRGB(255, 246, 210), 1, 0.45)
	local seat = mk("Frame", {
		Name = "RimLipInner", BackgroundTransparency = 1, Size = UDim2.fromOffset(WHEEL_D + 8, WHEEL_D + 8),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5,
	}, rim)
	round(seat); stroke(seat, Color3.fromRGB(150, 96, 16), 1, 0.4)
end
-- BOLTS: 12 at exactly 30 degrees apart, seated on the band's true centre line ((207 + 186) / 2 = 196.5), so
-- they ring the wheel perfectly evenly. 5px and faint -- present as hardware, never competing with the rewards.
local BOLT_R = (RIM_R + DISC_R) / 2
for i = 0, 11 do
	local a = math.rad(i * 30)
	local bolt = mk("Frame", {
		Name = "Bolt", BackgroundColor3 = T.goldShadow, BackgroundTransparency = 0.55,
		Size = UDim2.fromOffset(5, 5), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, BOLT_R * math.sin(a), 0.5, -BOLT_R * math.cos(a)), ZIndex = 6,
	}, rim)
	round(bolt)
end

-- ---- the spinning disc ---------------------------------------------------------------------------------------
local disc = mk("Frame", {
	Name = "Disc", BackgroundColor3 = Color3.fromRGB(52, 118, 230), Size = UDim2.fromScale(1, 1), ZIndex = 6,
	Rotation = 0,
}, wheelHolder)
round(disc); grad(disc, Color3.fromRGB(74, 144, 250), Color3.fromRGB(34, 92, 206))
stroke(disc, T.outline, LINE_CARD, 0.4)   -- the gold band around it is the ring now, so this is just a soft seam
-- Soft inner shadow hugging the rim. This is what gives the disc depth now -- no extra glow layered on top.
innerShadowCircle(disc, 3, 7)

-- ---- reward icons: one glyph per reward kind (levels = pet XP star, coins = money bag, mythical = crown) -----
local function iconFor(seg)
	if seg.kind == "mythical" then return "\xF0\x9F\x91\x91" end            -- crown
	if seg.kind == "coins"    then return "\xF0\x9F\x92\xB0" end            -- money bag
	return "\xE2\xAD\x90"                                                    -- star (pet XP)
end
-- "high value" = the rare wedges that get sparkles; derived from the shared weights, never hard-coded.
local function isHighValue(seg) return seg.weight <= 5 end

local N = #Config.SEGMENTS
local STEP = 360 / N

-- (The starburst spokes behind the centre are gone. With the wedges spaced apart they were doing no work, and
--  a ring of faint lines radiating out of the hub was the last bit of noise inside the disc.)

-- WEDGE GEOMETRY -- one calculation, applied identically to all seven, which is what makes the wheel symmetrical:
--   r      = 0.392 * 372 = 145.8 from the centre, the same for every wedge
--   chord  = 2 * r * sin(180/7) = 126.5 between neighbouring centres
--   W = 112 -> a ~14px gap between adjacent wedges (was ~8), so none of them touch
--   outer corner lands at sqrt((145.8 + 27)^2 + 56^2) = 181.8, inside the disc's 186 radius with room to spare
local W_PILL, H_PILL, R_FRAC = 112, 54, 0.392

-- one rounded segment per reward, arranged around the ring at its angle
local mythicGlow
local pills = {}                                      -- { f = pill, ang = its angle } -- used by orientLabels()
for i, seg in ipairs(Config.SEGMENTS) do
	local ang  = (i - 1) * STEP                       -- degrees clockwise from top
	local rad  = math.rad(ang)
	local rFrac = R_FRAC                              -- distance from centre as a fraction of the disc
	local px = 0.5 + rFrac * math.sin(rad)
	local py = 0.5 - rFrac * math.cos(rad)
	local base = seg.color or Color3.fromRGB(200, 200, 200)
	local high = isHighValue(seg)

	-- The only light left inside the disc: a faint puddle behind the two rare wedges (the mythic one breathes).
	-- It stays because it carries information -- it marks which rewards are rare -- unlike the glows that went.
	if high then
		local g = radialGlow(disc, 132, base, 6, 0.92, 1, 8)
		g.Position = UDim2.fromScale(px, py)
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		if seg.kind == "mythical" then mythicGlow = g end
	end

	-- Every wedge is built from the SAME W_PILL / H_PILL / R_CARD / stroke -- no per-reward exceptions anywhere,
	-- which is the whole reason the ring reads as symmetrical.
	local pill = mk("Frame", {
		Name = seg.id, BackgroundColor3 = base, Size = UDim2.fromOffset(W_PILL, H_PILL),
		Position = UDim2.fromScale(px, py), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = ang, ZIndex = 9,
	}, disc)
	corner(pill, R_CARD)   -- identical radius on all seven, and the same one the cards on the right use
	-- Softened toward a warm off-white before the gradient is applied: takes the edge off the saturation while
	-- the wedge still sits well clear of the near-black disc behind it.
	local soft = base:Lerp(Color3.fromRGB(246, 244, 250), 0.1)
	grad(pill, soft:Lerp(Color3.new(1, 1, 1), 0.14), soft:Lerp(Color3.new(0, 0, 0), 0.15))
	stroke(pill, T.outline, high and 2.5 or 2, high and 0 or 0.2)
	pills[#pills + 1] = { f = pill, ang = ang }

	-- soft top gloss, inset so it never touches the rounded corners
	local gloss = mk("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.88,
		Size = UDim2.new(1, -18, 0, 14), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 10,
	}, pill)
	corner(gloss, 7)

	-- CONTENT GRID (identical on all seven): 9px padding | 26px icon well | 6px gap | 62px label | 9px padding.
	-- The well is a fixed 26px circle and the glyph inside it is a fixed size, so no reward's icon can render
	-- visually larger than another's. Both the well and the label centre on the pill's midline in BOTH axes.
	local iconWell = mk("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.72,
		Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0, 9, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 10,
	}, pill)
	round(iconWell)
	mk("TextLabel", {
		Text = iconFor(seg), Font = Enum.Font.GothamBlack, TextSize = F_MICRO + 3, TextColor3 = T.textDark,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 11,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, iconWell)

	mk("TextLabel", {
		-- one TextSize and one alignment for EVERY wedge, no per-reward special cases
		Text = seg.label, Font = Enum.Font.GothamBlack, TextSize = F_MICRO,
		TextColor3 = T.textDark, BackgroundTransparency = 1, TextWrapped = true,
		Size = UDim2.new(1, -50, 1, -14), Position = UDim2.fromOffset(41, 7), ZIndex = 11,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, pill)
end

-- ---- KEEP EVERY REWARD THE RIGHT WAY UP -----------------------------------------------------------------------
-- A wedge is laid out radially (Rotation = its angle), which is what a wheel should look like -- but it means the
-- wedges on the far side of the disc would render UPSIDE DOWN. Because a child's rotation composes with its
-- parent's, a wedge's true on-screen angle is disc.Rotation + its own; when that lands in the lower semicircle we
-- add 180 so the label flips back up. The wedge occupies exactly the same space either way, so the ring's
-- geometry and spacing are untouched -- only the reading direction changes.
--
-- Called at build and again when a spin SETTLES, never per frame: mid-spin the wedges are a blur, and flipping
-- them while they turn would just look like a stutter.
local function orientLabels()
	local discAng = disc.Rotation % 360
	for _, p in ipairs(pills) do
		local onScreen = (discAng + p.ang) % 360     -- where this wedge actually sits, not where it was authored
		p.f.Rotation = (onScreen > 90 and onScreen < 270) and (p.ang + 180) or p.ang
	end
end
orientLabels()

-- gentle pulsing glow on the Mythical wedge (slower + shallower than before)
if mythicGlow then
	animate(function(t)
		local k = 0.5 + 0.5 * math.sin(t * 1.5)
		mythicGlow.Size = UDim2.fromOffset(132 + k * 16, 132 + k * 16)
	end)
end

-- ---- metallic gold centre button (also spins -- same action as the SPIN button) --------------------------------
local hub = mk("TextButton", {
	Name = "Hub", Text = "", AutoButtonColor = false, BackgroundColor3 = T.gold, Size = UDim2.fromOffset(96, 96),
	Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 14,
}, wheelHolder)   -- parented to the HOLDER (not the disc) so it stays upright while the disc spins
round(hub)
stroke(hub, T.goldShadow, LINE_CARD)
do   -- smooth four-stop metal, matching the ring's sweep so hub and rim read as the same material
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 244, 196)),
		ColorSequenceKeypoint.new(0.40, Color3.fromRGB(248, 212, 124)),
		ColorSequenceKeypoint.new(0.74, Color3.fromRGB(212, 158,  56)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(228, 180,  84)),
	})
	g.Parent = hub
end
-- BEVEL, not a drop shadow: a thin bright arc inside the top edge and a softer dark one inside the bottom. Both
-- are 1px and low-contrast -- enough to read as raised metal, far short of a heavy ring around the button.
local hubBevelLight = mk("Frame", {
	Name = "BevelLight", BackgroundTransparency = 1, Size = UDim2.fromOffset(88, 88), Position = UDim2.new(0.5, 0, 0.5, -1),
	AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 15,
}, hub)
round(hubBevelLight); stroke(hubBevelLight, Color3.fromRGB(255, 250, 226), 1, 0.5)
local hubBevelDark = mk("Frame", {
	Name = "BevelDark", BackgroundTransparency = 1, Size = UDim2.fromOffset(88, 88), Position = UDim2.new(0.5, 0, 0.5, 2),
	AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 15,
}, hub)
round(hubBevelDark); stroke(hubBevelDark, Color3.fromRGB(140, 88, 12), 1, 0.62)
-- Paw + label are ONE centred stack inside the 96px hub: 18px paw + 2px gap + 24px label = 44 tall, so the stack
-- starts at (96 - 44) / 2 = 26. Each row is full-width and centre-aligned on both axes, so the two are centred on
-- the hub's exact midline rather than eyeballed.
mk("TextLabel", {
	Text = "\xF0\x9F\x90\xBE", Font = Enum.Font.GothamBlack, TextSize = F_BODY, TextColor3 = Color3.fromRGB(96, 56, 10),
	BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 26), ZIndex = 16,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, hub)
local hubLabel = mk("TextLabel", {
	Text = "SPIN", Font = Enum.Font.GothamBlack, TextSize = F_VALUE - 4, TextColor3 = Color3.fromRGB(66, 36, 6),
	BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 46), ZIndex = 16,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, hub)

-- ---- gold pointer: one clean arrow (rounded cap + diamond tip) with a single soft shine ------------------------
-- Outlined in deep brown rather than gold: the outer ring is now a gold band, so a gold-on-gold edge would vanish.
local PTR_EDGE = Color3.fromRGB(78, 46, 8)
local PTR_TOP, PTR_BOT = Color3.fromRGB(255, 240, 186), Color3.fromRGB(226, 172,  62)
-- Same shape as before (rounded cap + diamond tip), and both parts sit on x = 0.5 of the wheel holder with a
-- centred anchor, so the arrow is exactly on the wheel's vertical axis by construction rather than by nudging.
--
-- SHADOW UNDERNEATH: a soft dark twin of each part, offset 3px down and drawn below them, so the pointer reads
-- as sitting ON the wheel instead of being painted onto it. Deliberately drawn as its own pair rather than via
-- shadowFor, because these two parts overlap and a per-part shadow would show a seam between them.
local function ptrShadow(size, y, rot, rad)
	local s = mk("Frame", {
		Name = "PtrShadow", BackgroundColor3 = T.shadow, BackgroundTransparency = 0.6,
		Size = size, Position = UDim2.new(0.5, 0, 0, y + 3), AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = rot, ZIndex = 16,
	}, wheelHolder)
	corner(s, rad)
end
ptrShadow(UDim2.fromOffset(24, 24), -8, 45, 7)
ptrShadow(UDim2.fromOffset(38, 26), -25, 0, R_SMALL)

local ptrDiamond = mk("Frame", {
	Name = "PointerTip", BackgroundColor3 = T.gold, Size = UDim2.fromOffset(24, 24),
	Position = UDim2.new(0.5, 0, 0, -8), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45, ZIndex = 17,
}, wheelHolder)
corner(ptrDiamond, 7)   -- rounder corners = smoother silhouette where the tip meets the wheel
stroke(ptrDiamond, PTR_EDGE, 1.5)
do   -- the tip's sweep runs along its own 45-degree axis so it matches the cap above it
	local g = Instance.new("UIGradient")
	g.Rotation = 45
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, PTR_TOP),
		ColorSequenceKeypoint.new(0.40, Color3.fromRGB(248, 212, 124)),
		ColorSequenceKeypoint.new(1.00, PTR_BOT),
	})
	g.Parent = ptrDiamond
end
local ptrCap = mk("Frame", {
	Name = "PointerCap", BackgroundColor3 = T.gold, Size = UDim2.fromOffset(38, 26),
	Position = UDim2.new(0.5, 0, 0, -25), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 18,
}, wheelHolder)
corner(ptrCap, R_SMALL); stroke(ptrCap, PTR_EDGE, 1.5)
do   -- four-stop metal, the same recipe as the ring and the hub
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, PTR_TOP),
		ColorSequenceKeypoint.new(0.40, Color3.fromRGB(248, 212, 124)),
		ColorSequenceKeypoint.new(0.74, Color3.fromRGB(212, 158,  56)),
		ColorSequenceKeypoint.new(1.00, PTR_BOT),
	})
	g.Parent = ptrCap
end
mk("Frame", {   -- subtle shine, faded out downward rather than a hard white pill
	BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.72,
	Size = UDim2.fromOffset(24, 9), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 19,
}, ptrCap).Name = "Gloss"
do
	local gl = ptrCap:FindFirstChild("Gloss")
	round(gl)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = gl
end

-- (the floating sparkles around the wheel were removed -- decoration with nothing to say)

-- ============================================================================================================
-- RIGHT COLUMN -- spins card, main action button, pending banner, buy-spins cards
-- ============================================================================================================
-- Right column: x runs to exactly PANEL_PAD from the right edge, matching the wheel column's left margin.
-- VERTICAL RHYTHM inside the 504px column (every gap is deliberate, and it ends flush at 504):
--     0  spins panel      62 tall
--    80  SPIN button      66 tall      (gap 18)
--   160  pending banner   44 tall      (gap 14)
--   220  section heading  20 tall      (gap 16)
--   244  hairline divider  1 tall
--   254  purchase cards   74 tall each, 88 pitch -> 254 / 342 / 430, last ends at 504
local RIGHT_W = PANEL_W - 440 - PANEL_PAD
local right = mk("Frame", {
	Name = "Right", BackgroundTransparency = 1, Size = UDim2.fromOffset(RIGHT_W, 504), Position = UDim2.fromOffset(440, CONTENT_TOP), ZIndex = 6,
}, panel)

-- ---- "Spins" information card ----------------------------------------------------------------------------------
local spinsCard = mk("Frame", {
	Name = "SpinsCard", BackgroundColor3 = T.cardBot, Size = UDim2.new(1, 0, 0, 62), Position = UDim2.fromOffset(0, 0), ZIndex = 7,
}, right)
cardSkin(spinsCard)

-- GUTTER(16) + 36px icon + 12px gap -> text column at 64, the same column the buy cards use.
-- Label (14) + value (28) = 42, centred as a pair in the 62px card -> the stack starts at (62 - 42) / 2 = 10.
local ticketWell = mk("Frame", {
	BackgroundColor3 = T.gold, Size = UDim2.fromOffset(36, 36), Position = UDim2.new(0, GUTTER, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5), ZIndex = 8,
}, spinsCard)
round(ticketWell); grad(ticketWell, T.goldLight, T.goldDeep); stroke(ticketWell, T.goldShadow, LINE_CARD)
mk("TextLabel", {
	Text = "\xF0\x9F\x8E\x9F", Font = Enum.Font.GothamBlack, TextSize = F_BODY, TextColor3 = T.textDark,
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 9,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, ticketWell)

mk("TextLabel", {
	Text = "SPINS", Font = Enum.Font.GothamMedium, TextSize = F_MICRO, TextColor3 = T.textSoft,
	BackgroundTransparency = 1, Size = UDim2.new(0, 140, 0, 14), Position = UDim2.fromOffset(64, 10),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 9,
}, spinsCard)
local spinsValue = mk("TextLabel", {
	Name = "SpinsValue", Text = "0", Font = Enum.Font.GothamBlack, TextSize = F_VALUE, TextColor3 = T.goldLight,
	BackgroundTransparency = 1, Size = UDim2.new(0, 200, 0, 28), Position = UDim2.fromOffset(64, 24),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 9,
}, spinsCard)

-- ---- main action button (SPIN / BUY SPINS / SPINNING...) ---------------------------------------------------------
local spinBtn = mk("TextButton", {
	Name = "SpinBtn", Text = "", AutoButtonColor = false, BackgroundColor3 = T.green,
	Size = UDim2.new(1, 0, 0, 66), Position = UDim2.fromOffset(0, 80), ZIndex = 7,
}, right)
corner(spinBtn, R_CARD)
local spinGrad = grad(spinBtn, T.greenLight, T.greenDeep)
-- thin outline; the depth comes from the shadow below, not from a heavy border
local spinStroke = stroke(spinBtn, Color3.fromRGB(30, 84, 54), LINE_CARD)
shadowFor(spinBtn, 3, R_CARD, 3)   -- the gloss + gradient carry the depth now
-- (the green halo behind this button is gone -- it was pulling the eye away from the wheel, which is the
--  thing the player is actually here to use)
do  -- glossy highlight across the top: a soft band that fades out downward rather than a flat white bar
	local gl = mk("Frame", {
		Name = "Gloss", BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.8,
		Size = UDim2.new(1, -18, 0, 24), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 8,
	}, spinBtn)
	corner(gl, 10)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = gl
end
-- hover = a small brightness lift, nothing else
do
	local hv = mk("Frame", { Name = "Hover", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8 }, spinBtn)
	corner(hv, R_CARD)
	spinBtn.MouseEnter:Connect(function() TweenService:Create(hv, TweenInfo.new(0.14), { BackgroundTransparency = 0.9 }):Play() end)
	spinBtn.MouseLeave:Connect(function() TweenService:Create(hv, TweenInfo.new(0.14), { BackgroundTransparency = 1 }):Play() end)
end
local spinIcon = mk("TextLabel", {
	-- GUTTER(16) + 32px icon + 8px gap -> label at 56, on the same left rail as every card in this column
	Name = "Icon", Text = "\xE2\x9C\xA8", Font = Enum.Font.GothamBlack, TextSize = F_VALUE, TextColor3 = T.textBright,
	BackgroundTransparency = 1, Size = UDim2.fromOffset(32, 32), Position = UDim2.new(0, GUTTER, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5), ZIndex = 9,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, spinBtn)
local spinText = mk("TextLabel", {
	-- the one deliberate step above F_VALUE in the whole panel: this is the primary call to action
	Name = "Label", Text = "SPIN", Font = Enum.Font.GothamBlack, TextSize = F_VALUE + 2, TextColor3 = T.textBright,
	BackgroundTransparency = 1, Size = UDim2.new(1, -72, 1, 0), Position = UDim2.fromOffset(56, 0),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 9,
}, spinBtn)
textStroke(spinText, Color3.fromRGB(46, 116, 30), 1.5)

-- ---- pending-levels banner (shown when the player has unassigned pet levels waiting) -------------------------------
local pendingBtn = mk("TextButton", {
	Name = "PendingBtn", Text = "", AutoButtonColor = false, BackgroundColor3 = T.gold,
	Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 160), Visible = false, ZIndex = 7,
}, right)
corner(pendingBtn, R_CARD); grad(pendingBtn, T.goldLight, T.goldDeep); stroke(pendingBtn, T.goldShadow, LINE_CARD)
shadowFor(pendingBtn, 3, R_CARD, 3)
local pendingText = mk("TextLabel", {
	Text = "", Font = Enum.Font.GothamBlack, TextSize = F_BODY, TextColor3 = T.textDark, BackgroundTransparency = 1,
	Size = UDim2.new(1, -GUTTER * 2, 1, 0), Position = UDim2.fromOffset(GUTTER, 0),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
	TextWrapped = true, ZIndex = 8,
}, pendingBtn)

-- ---- "Buy Spins" section header -------------------------------------------------------------------------------
mk("TextLabel", {
	Text = "BUY SPINS", Font = Enum.Font.GothamBold, TextSize = F_LABEL, TextColor3 = T.textSoft,
	BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 220),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 7,
}, right)
-- TEST-MODE tell. Sits on the section heading's own row, right-aligned, in the same quiet weight the sub-lines
-- use -- present so nobody mistakes a free test credit for a real Robux sale, gone the moment TEST_MODE is off.
if Config.TEST_MODE then
	mk("TextLabel", {
		Text = "TEST \xE2\x80\x94 FREE", Font = Enum.Font.GothamBold, TextSize = F_MICRO - 1,
		TextColor3 = T.greenLight, TextTransparency = 0.2, BackgroundTransparency = 1,
		Size = UDim2.new(0, 140, 0, 20), Position = UDim2.new(1, -140, 0, 220),
		TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 7,
	}, right)
end
mk("Frame", {   -- hairline divider -- 1px and faint, so it separates without drawing the eye
	BackgroundColor3 = T.gold, BackgroundTransparency = 0.9, Size = UDim2.new(1, 0, 0, 1),
	Position = UDim2.fromOffset(0, 244), ZIndex = 7,
}, right)

-- ---- one rounded card per Robux product -----------------------------------------------------------------------
local function makeBuyButton(product, yOff)
	local card = mk("TextButton", {
		Name = "Buy_" .. product.id, Text = "", AutoButtonColor = false, BackgroundColor3 = T.cardBot,
		Size = UDim2.new(1, 0, 0, 74), Position = UDim2.fromOffset(0, yOff), ZIndex = 7,
	}, right)
	cardSkin(card)   -- identical border weight, radius, shadow and bevel on every card-like surface

	-- hover = brightness lift only
	local hover = mk("Frame", {
		Name = "Hover", BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 8,
	}, card)
	corner(hover, R_CARD)
	local function fade(to) TweenService:Create(hover, TweenInfo.new(0.14), { BackgroundTransparency = to }):Play() end
	card.MouseEnter:Connect(function() fade(0.9) end)
	card.MouseLeave:Connect(function() fade(1) end)
	card.MouseButton1Down:Connect(function() fade(0.84) end)
	card.MouseButton1Up:Connect(function() fade(0.9) end)

	-- ALIGNMENT GRID (identical on every card, so the three cards read as one column):
	--   GUTTER(16) left          -> icon well (42px)
	--   70  text column          -> pack name + sub-line, both left-aligned on the same x
	--   -GUTTER right            -> price number, right-aligned on exactly the same x on every card
	--   -80 R$ chip centre       -> fixed, so the chips line up regardless of price width
	local well = mk("Frame", {
		BackgroundColor3 = T.gold, Size = UDim2.fromOffset(42, 42), Position = UDim2.new(0, GUTTER, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5), ZIndex = 9,
	}, card)
	round(well); grad(well, T.goldLight, T.goldDeep); stroke(well, T.goldShadow, LINE_CARD)
	mk("TextLabel", {
		Text = "\xF0\x9F\x8E\x9F", Font = Enum.Font.GothamBlack, TextSize = F_VALUE - 4, TextColor3 = T.textDark,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, well)

	-- middle: pack name + sub-line, centred as a pair (20 + 2 + 16 = 38 against a 74px card -> top at 18)
	mk("TextLabel", {
		Text = product.label, Font = Enum.Font.GothamBlack, TextSize = F_CARD, TextColor3 = T.textBright,
		BackgroundTransparency = 1, Size = UDim2.new(0, 140, 0, 20), Position = UDim2.fromOffset(70, 18),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 10,
	}, card)
	local saved = Config.savingsFor(product)
	mk("TextLabel", {
		-- sub-line: lighter weight, smaller, and dimmer than the pack name so it reads as secondary
		Text = saved > 0 and string.format("Save R$ %d", saved) or "Single spin",
		Font = Enum.Font.GothamMedium, TextSize = F_MICRO - 1,
		TextColor3 = saved > 0 and T.greenLight or T.textSoft, TextTransparency = 0.28,
		BackgroundTransparency = 1, Size = UDim2.new(0, 140, 0, 16), Position = UDim2.fromOffset(70, 40),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 10,
	}, card)

	-- right: price. Fixed right edge + fixed chip x => every card's price sits on the same two verticals,
	-- and both the number and the chip are centred on the card's vertical midline.
	local priceLbl = mk("TextLabel", {
		Text = tostring(product.robux), Font = Enum.Font.GothamBlack, TextSize = F_VALUE,
		TextColor3 = Color3.fromRGB(206, 250, 218), BackgroundTransparency = 1,
		Size = UDim2.new(0, 58, 1, 0), Position = UDim2.new(1, -(GUTTER + 58), 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 10,
	}, card)
	textStroke(priceLbl, Color3.fromRGB(28, 82, 44), 1)
	robuxChip(card, 23, 10).Position = UDim2.new(1, -80, 0.5, 0)

	-- Badge pill in the TOP-RIGHT corner. FIXED width/height (no AutomaticSize) so POPULAR and BEST VALUE are
	-- the same pill on every card, pinned to the same GUTTER rail as the price below them.
	if product.tag then
		local badge = mk("Frame", {
			Name = "Badge", BackgroundColor3 = T.gold, Size = UDim2.fromOffset(BADGE_W, BADGE_H),
			Position = UDim2.new(1, -GUTTER, 0, -(BADGE_H / 2)), AnchorPoint = Vector2.new(1, 0), ZIndex = 12,
		}, card)
		round(badge)
		-- softer, lower-contrast gold than the icon wells so the badge reads as a label, not a button
		grad(badge, Color3.fromRGB(250, 220, 156), Color3.fromRGB(226, 182,  96))
		shadowFor(badge, 2, BADGE_H / 2, 2)   -- just enough to lift it off the card edge
		mk("TextLabel", {
			Text = string.upper(product.tag), Font = Enum.Font.GothamBlack, TextSize = 10,
			TextColor3 = Color3.fromRGB(78, 48, 10), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 13,
			TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
		}, badge)
	end

	-- BUSY VEIL: covers the card between the click and the server's answer, so the card visibly acknowledges the
	-- press instead of looking dead for a round trip. Hidden again by setBuying(false) on "purchased"/"toast",
	-- or by the safety timeout in purchase() if the server never answers.
	local veil = mk("Frame", {
		Name = "Busy", BackgroundColor3 = Color3.fromRGB(16, 56, 148), BackgroundTransparency = 0.3,
		Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 14,
	}, card)
	corner(veil, R_CARD)
	mk("TextLabel", {
		Text = "...", Font = Enum.Font.GothamBlack, TextSize = F_VALUE, TextColor3 = T.goldLight,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 15,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, veil)
	buyVeils[product.id] = veil

	card.Activated:Connect(function() purchase(product) end)
	return card
end

local y = 254
for _, product in ipairs(Config.PRODUCTS) do
	makeBuyButton(product, y)
	y = y + 88           -- 74px card + 14px gap; three of them land flush on the column's 504px bottom
end

-- ============================================================================================================
-- RESULT BANNER (under the wheel) + ODDS BUTTON
-- ============================================================================================================
-- The status line used to be a full card with its own border, gradient and shadow, which made a throwaway
-- message like "Buy spins to play!" shout as loudly as the wheel. It is now just a small centred line of text
-- sitting directly under the wheel -- no chrome at all. `resultCard` is kept purely as the show/hide holder so
-- showToast() is unchanged.
local resultCard = mk("Frame", {
	-- y clears the gold ring, which sticks 21px past the 372px wheel (ring bottom = 120 + 372 + 21 = 513)
	Name = "ResultCard", BackgroundTransparency = 1, Size = UDim2.fromOffset(WHEEL_D, 30),
	Position = UDim2.fromOffset(PANEL_PAD, 524), Visible = false, ZIndex = 6,
}, panel)

local resultLabel = mk("TextLabel", {
	Name = "ResultLabel", Text = "", Font = Enum.Font.GothamBold, TextSize = F_LABEL, TextColor3 = T.textSoft,
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), TextWrapped = true, ZIndex = 7,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, resultCard)

local oddsBtn = mk("TextButton", {
	Name = "OddsBtn", Text = "", AutoButtonColor = false, BackgroundColor3 = T.cardBot,
	-- 580 + 44 = 624, leaving the same 28px bottom margin the right column ends on (120 + 504 = 624)
	Size = UDim2.fromOffset(150, 44), Position = UDim2.fromOffset(PANEL_PAD, 580), ZIndex = 6,
}, panel)
cardSkin(oddsBtn)   -- same surface as the purchase cards, so the two columns feel like one system
mk("TextLabel", {
	Text = "?", Font = Enum.Font.GothamBlack, TextSize = F_CARD, TextColor3 = T.gold, BackgroundTransparency = 1,
	Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0, GUTTER, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 7,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, oddsBtn)
mk("TextLabel", {
	Text = "ODDS", Font = Enum.Font.GothamBlack, TextSize = F_BODY, TextColor3 = T.textBright, BackgroundTransparency = 1,
	Size = UDim2.new(1, -52, 1, 0), Position = UDim2.fromOffset(46, 0), ZIndex = 7,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
}, oddsBtn)
do
	local hv = mk("Frame", { Name = "Hover", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6 }, oddsBtn)
	corner(hv, R_CARD)
	oddsBtn.MouseEnter:Connect(function() TweenService:Create(hv, TweenInfo.new(0.14), { BackgroundTransparency = 0.9 }):Play() end)
	oddsBtn.MouseLeave:Connect(function() TweenService:Create(hv, TweenInfo.new(0.14), { BackgroundTransparency = 1 }):Play() end)
end

-- ============================================================================================================
-- ODDS PANEL -- lists every segment + its exact % straight from PetWheelConfig.SEGMENTS (same table the server
-- rolls on), plus the real-odds disclosure note.
-- ============================================================================================================
local oddsOverlay = mk("Frame", {
	Name = "OddsOverlay", BackgroundColor3 = T.panelBot, Size = UDim2.fromOffset(400, 480), Active = true,
	Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 20,
}, panel)
corner(oddsOverlay, R_PANEL); grad(oddsOverlay, T.panelTop, T.panelBot); stroke(oddsOverlay, T.outline, LINE_PANEL)
shadowFor(oddsOverlay, 8, R_PANEL, 6)

mk("TextLabel", {
	Text = "DROP CHANCES", Font = Enum.Font.GothamBlack, TextSize = F_VALUE, TextColor3 = T.goldLight,
	BackgroundTransparency = 1, Size = UDim2.new(1, -80, 0, 44), Position = UDim2.fromOffset(20, 12),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 21,
}, oddsOverlay)

local oddsClose = mk("TextButton", {
	Text = "X", Font = Enum.Font.GothamBlack, TextSize = F_BODY, TextColor3 = T.textBright,
	AutoButtonColor = false, BackgroundColor3 = T.red, Size = UDim2.fromOffset(36, 36),
	Position = UDim2.new(1, -18, 0, 34), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 22,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, oddsOverlay)
corner(oddsClose, R_SMALL); grad(oddsClose, T.redLight, T.red); stroke(oddsClose, Color3.new(1, 1, 1), LINE_PANEL)

local oddsList = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -36, 1, -122), Position = UDim2.fromOffset(18, 60), ZIndex = 21 }, oddsOverlay)
mk("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, oddsList)
for i, seg in ipairs(Config.SEGMENTS) do
	local row = mk("Frame", { BackgroundColor3 = T.cardBot, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = i, ZIndex = 21 }, oddsList)
	corner(row, R_SMALL); grad(row, T.cardTop, T.cardBot); stroke(row, seg.color or T.textSoft, LINE_CARD, 0.55)
	local swatch = mk("Frame", {
		BackgroundColor3 = seg.color or Color3.fromRGB(200, 200, 200), Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 22,
	}, row)
	round(swatch); stroke(swatch, T.outline, LINE_CARD, 0.25)
	mk("TextLabel", {
		Text = iconFor(seg), Font = Enum.Font.GothamBlack, TextSize = F_LABEL, TextColor3 = T.textDark,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 23,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, swatch)
	mk("TextLabel", {
		Text = seg.label, Font = Enum.Font.GothamBold, TextSize = F_LABEL + 1, TextColor3 = T.textBright,
		BackgroundTransparency = 1, Size = UDim2.new(0.62, 0, 1, 0), Position = UDim2.fromOffset(46, 0),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 22,
	}, row)
	-- print the weight exactly as configured (e.g. 45, 0.9, 0.1) with a trailing % -- no rounding, no drift
	mk("TextLabel", {
		Text = string.format("%s%%", tostring(seg.weight)), Font = Enum.Font.GothamBlack, TextSize = F_BODY,
		TextColor3 = T.greenLight, BackgroundTransparency = 1,
		Size = UDim2.new(0.34, -GUTTER, 1, 0), Position = UDim2.new(0.66, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 22,
	}, row)
end

mk("TextLabel", {
	Text = Config.ODDS_NOTE, Font = Enum.Font.GothamMedium, TextSize = F_LABEL, TextColor3 = T.goldLight,
	BackgroundTransparency = 1, Size = UDim2.new(1, -36, 0, 44), Position = UDim2.new(0, 18, 1, -52),
	TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21,
}, oddsOverlay)

-- ============================================================================================================
-- PET PICKER -- reuses the canonical GetOwnedPets fetch. Lists the player's OWNED pets; maxed pets are greyed
-- and not selectable (they can't take levels). Picking one fires "assign" to the server, which grants the held
-- pet-levels (clamped to 25) onto that pet. If the player owns ZERO pets, shows the "unlock a pet" message.
-- ============================================================================================================
local pickerOverlay = mk("Frame", {
	Name = "PickerOverlay", BackgroundColor3 = T.panelBot, Size = UDim2.fromOffset(440, 500), Active = true,
	Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 30,
}, panel)
corner(pickerOverlay, R_PANEL); grad(pickerOverlay, T.panelTop, T.panelBot); stroke(pickerOverlay, T.outline, LINE_PANEL)
shadowFor(pickerOverlay, 8, R_PANEL, 6)

local pickerTitle = mk("TextLabel", {
	Text = "Choose a Pet to Level Up", Font = Enum.Font.GothamBlack, TextSize = F_CARD, TextColor3 = T.goldLight,
	BackgroundTransparency = 1, Size = UDim2.new(1, -80, 0, 44), Position = UDim2.fromOffset(20, 12),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 31,
}, pickerOverlay)

local pickerClose = mk("TextButton", {
	Text = "X", Font = Enum.Font.GothamBlack, TextSize = F_BODY, TextColor3 = T.textBright,
	AutoButtonColor = false, BackgroundColor3 = T.red, Size = UDim2.fromOffset(36, 36),
	Position = UDim2.new(1, -18, 0, 34), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 32,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
}, pickerOverlay)
corner(pickerClose, R_SMALL); grad(pickerClose, T.redLight, T.red); stroke(pickerClose, Color3.new(1, 1, 1), LINE_PANEL)

local pickerMsg = mk("TextLabel", {
	Text = "", Font = Enum.Font.GothamBold, TextSize = F_BODY, TextColor3 = Color3.fromRGB(255, 226, 180),
	BackgroundTransparency = 1, Size = UDim2.new(1, -36, 0, 70), Position = UDim2.fromOffset(18, 66),
	TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 31,
}, pickerOverlay)

local pickerScroll = mk("ScrollingFrame", {
	BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -36, 1, -80), Position = UDim2.fromOffset(18, 64),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6,
	ScrollBarImageColor3 = T.gold, ZIndex = 31,
}, pickerOverlay)
mk("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, pickerScroll)

local function clearPicker()
	for _, ch in ipairs(pickerScroll:GetChildren()) do
		if ch:IsA("GuiButton") or ch:IsA("Frame") then ch:Destroy() end
	end
end

local function closePicker() pickerOverlay.Visible = false end

local function openPicker()
	clearPicker()
	pickerMsg.Visible = false
	pickerScroll.Visible = true
	pickerTitle.Text = string.format("Choose a Pet (+%d levels)", pendingLevels)
	local owned = fetchOwnedPets()
	if #owned == 0 then
		-- ZERO pets: hold the reward (it's already banked in `pending` server-side) and tell the player.
		pickerScroll.Visible = false
		pickerMsg.Visible = true
		pickerMsg.Text = "Unlock a pet to receive these levels.\nYour +" .. pendingLevels .. " levels are saved and waiting."
		pickerOverlay.Visible = true
		return
	end
	for i, p in ipairs(owned) do
		local maxed = p.maxed == true
		local row = mk("TextButton", {
			Text = "", AutoButtonColor = not maxed, BackgroundColor3 = maxed and Color3.fromRGB(56, 92, 158) or T.cardBot,
			Size = UDim2.new(1, -8, 0, 50), LayoutOrder = i, ZIndex = 32,
		}, pickerScroll)
		corner(row, R_SMALL)
		grad(row, maxed and Color3.fromRGB(74, 116, 186) or T.cardTop, maxed and Color3.fromRGB(48, 82, 146) or T.cardBot)
		stroke(row, T.outline, LINE_CARD, maxed and 0.7 or 0.35)
		local well = mk("Frame", {
			BackgroundColor3 = maxed and Color3.fromRGB(146, 178, 220) or T.gold, Size = UDim2.fromOffset(32, 32),
			Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 33,
		}, row)
		round(well); stroke(well, T.goldShadow, LINE_CARD, maxed and 0.6 or 0)
		mk("TextLabel", {
			Text = "\xF0\x9F\x90\xBE", Font = Enum.Font.GothamBlack, TextSize = F_BODY, TextColor3 = T.textDark,
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 34,
			TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
		}, well)
		mk("TextLabel", {
			Text = (p.displayName or p.petId or "Pet"), Font = Enum.Font.GothamBold, TextSize = F_BODY,
			TextColor3 = maxed and Color3.fromRGB(196, 218, 246) or T.textBright,
			BackgroundTransparency = 1, Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.fromOffset(56, 0),
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 33,
		}, row)
		mk("TextLabel", {
			Text = maxed and "MAX" or ("Lv " .. tostring(p.level or 1)),
			Font = Enum.Font.GothamBlack, TextSize = F_BODY,
			TextColor3 = maxed and T.goldLight or T.greenLight,
			BackgroundTransparency = 1, Size = UDim2.new(0.3, -GUTTER, 1, 0), Position = UDim2.new(0.7, 0, 0, 0),
			TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 33,
		}, row)
		if not maxed then
			row.Activated:Connect(function()
				remote:FireServer("assign", p.petId)   -- server grants + clamps; we get "assigned" + "state" back
				closePicker()
			end)
		end
	end
	pickerOverlay.Visible = true
end

-- ============================================================================================================
-- RESULT ANIMATION + TOASTS
-- ============================================================================================================
-- `isWin` lifts the line to gold; everything else (prompts, rejections) stays quiet grey so it can't compete
-- with the wheel for attention.
local function showToast(msg, isWin)
	msg = msg or ""
	resultLabel.Text = msg
	resultLabel.TextColor3 = isWin and T.goldLight or T.textSoft
	resultCard.Visible = (msg ~= "")
end

-- Spin the disc so segment `idx` (1-based, matching PetWheelConfig.SEGMENTS) lands under the top pointer.
-- Segment i sits at angle (i-1)*STEP clockwise from top; to bring it to the top we rotate to a multiple of 360
-- minus that angle, plus several full turns for the spin feel. Honest: idx is exactly what the server rolled.
local function animateTo(idx, onDone)
	local target = (5 * 360) - ((idx - 1) * STEP)   -- 5 full spins then land on the segment
	-- normalise current rotation so repeated spins keep accelerating from wherever it stopped
	disc.Rotation = disc.Rotation % 360
	local tween = TweenService:Create(disc, TweenInfo.new(4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Rotation = target })
	tween:Play()
	tween.Completed:Connect(function()
		disc.Rotation = disc.Rotation % 360
		orientLabels()   -- the disc came to rest somewhere new: re-settle every label the right way up
		if onDone then onDone() end
	end)
end

local function describeReward(reward)
	if reward.kind == "levels" then
		return string.format("\xE2\xAD\x90 You won +%d Pet Levels! Pick a pet...", reward.amount or 0)
	elseif reward.kind == "coins" then
		return string.format("\xF0\x9F\x92\xB0 You won %d Coins!", reward.amount or 0)
	elseif reward.kind == "mythical" then
		return string.format("\xF0\x9F\x91\x91 JACKPOT! Mythical pet: %s!", reward.name or reward.petId or "Mythical")
	end
	return "You won a prize!"
end

-- ============================================================================================================
-- THE REWARD REVEAL -- the payoff. A happy "YOU WON!" card that pops OVER the HUD (and over the wheel panel)
-- when the disc stops, then gets dismissed by one big friendly button.
--
-- It is deliberately the SAME card the Daily Rewards crate reveal uses -- 320x420, bright blue with a thick
-- white cartoon border, triple navy drop shadow, flash + rings + shards burst, confetti, and the same payoff
-- sound -- because a kid who has opened a crate already knows what this means. Copied rather than shared: the
-- crate owns its build inside CrateClient's own reveal flow, and this script stays self-contained.
--
-- SIZE MATCHES THE HUD: the card carries the identical adaptive UIScale the shops/Pet Hub/crate get from
-- _G.applyHudScaling -- min(vp.X/1280, vp.Y/720, 1) -- so it is exactly as big, relative to the screen, as
-- every other panel in the game, on a phone or a monitor.
--
-- Wrapped in a do-block: it needs a dozen helpers of its own and none of them belong at module scope.
local showReveal   -- showReveal(reward, onClosed)
do
	local REVEAL_SOUND = "rbxassetid://4612378364"   -- the crate's payoff sound, so the two feel like one game
	local function playRevealSound()
		task.spawn(function()
			local s = Instance.new("Sound")
			s.Name = "PetWheelRevealSound"
			s.SoundId = REVEAL_SOUND
			s.Volume = 0.6
			-- route through SFXGroup so the Settings "Sound Effects" toggle mutes it like every other SFX
			local sfx = SoundService:FindFirstChild("SFXGroup")
			if sfx and sfx:IsA("SoundGroup") then s.SoundGroup = sfx end
			s.Parent = SoundService
			pcall(function() s:Play() end)
			Debris:AddItem(s, 5)
		end)
	end

	-- DisplayOrder 120 -- above the HUD *and* above the wheel panel (100), so the reveal is never half-covered
	-- by the thing that produced it.
	local revealGui = mk("ScreenGui", {
		Name = "PetWheelReveal", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 120, Enabled = false,
	}, playerGui)
	local revealDim = mk("Frame", {
		Name = "Dim", BackgroundColor3 = T.shadow, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1,
	}, revealGui)
	-- Everything except the dim lives under this holder, which carries the HUD-matching scale.
	local stage = mk("Frame", { Name = "Stage", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, revealGui)
	local stageScale = mk("UIScale", { Scale = 1 }, stage)
	local function applyHudScale()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		stageScale.Scale = math.min(vp.X / 1280, vp.Y / 720, 1)   -- the exact _G.applyHudScaling factor
	end
	applyHudScale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyHudScale)
	end
	-- A UIScale scales about the TOP-LEFT of its frame, so a full-screen stage would drift off-centre as it
	-- shrinks. Anchoring the stage's contents to the screen centre via this holder keeps the card centred at
	-- every scale.
	local centre = mk("Frame", {
		Name = "Centre", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 2,
	}, stage)
	do   -- keep the holder pinned to the true screen centre even as the stage scales around its top-left
		local function recentre()
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
			local s = math.max(0.001, stageScale.Scale)
			centre.Position = UDim2.fromOffset((vp.X / 2) / s, (vp.Y / 2) / s)
		end
		recentre()
		stageScale:GetPropertyChangedSignal("Scale"):Connect(recentre)
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(recentre)
		end
	end

	-- ---- per-reward presentation -----------------------------------------------------------------------------
	-- One table decides everything that differs between the three reward kinds, so the card itself has no
	-- per-reward branching in its layout.
	local function present(reward)
		local kind = reward.kind
		if kind == "coins" then
			return {
				header = "COINS!", headerColor = T.gold,
				emoji = "\xF0\x9F\x92\xB0", tile = Color3.fromRGB(255, 200, 60),
				name = string.format("%d Coins", reward.amount or 0),
				sub = "Added to your balance",
				accent = T.gold, big = false,
			}
		elseif kind == "mythical" then
			return {
				header = "MYTHICAL!", headerColor = T.gold,
				emoji = "\xF0\x9F\x91\x91", tile = Color3.fromRGB(255, 214, 96),
				name = tostring(reward.name or reward.petId or "Mythical Pet"),
				sub = "The 0.1% jackpot \xE2\x80\x94 it's yours!",
				accent = T.gold, big = true,   -- the jackpot gets the bigger burst
			}
		end
		local n = reward.amount or 0
		return {
			header = "YOU WON!", headerColor = T.greenLight,
			emoji = "\xE2\xAD\x90", tile = Color3.fromRGB(126, 217, 87),
			name = string.format("+%d Pet %s", n, n == 1 and "Level" or "Levels"),
			sub = "Choose which pet levels up",
			accent = T.green, big = (n >= 5),
		}
	end

	-- ---- the burst: white flash, expanding rings, flying shards, falling confetti -----------------------------
	local function playBurst(big, accent)
		local flash = mk("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.15,
			Size = UDim2.fromScale(1, 1), ZIndex = 5,
		}, stage)
		TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
		Debris:AddItem(flash, 0.6)

		for i = 1, (big and 3 or 2) do
			local ring = mk("Frame", {
				BackgroundTransparency = 1, Size = UDim2.fromOffset(40, 40),
				Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 6,
			}, centre)
			round(ring)
			local rs = stroke(ring, big and T.gold or accent, 5)
			local sz = (big and 520 or 360) + i * 60
			TweenService:Create(ring, TweenInfo.new(0.5 + i * 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(sz, sz) }):Play()
			TweenService:Create(rs, TweenInfo.new(0.5 + i * 0.08), { Transparency = 1 }):Play()
			Debris:AddItem(ring, 1.2)
		end

		local shards = big and 18 or 10
		for i = 1, shards do
			local shard = mk("Frame", {
				BackgroundColor3 = big and T.gold or accent, Size = UDim2.fromOffset(10, 10),
				Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 6,
			}, centre)
			round(shard)
			local ang  = (i / shards) * math.pi * 2
			local dist = (big and 320 or 220) + (i % 3) * 30
			TweenService:Create(shard, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, math.cos(ang) * dist, 0.5, math.sin(ang) * dist),
				BackgroundTransparency = 1, Size = UDim2.fromOffset(2, 2),
			}):Play()
			Debris:AddItem(shard, 0.8)
		end

		-- CONFETTI: little coloured rectangles raining past the card. Purely joy; nothing reads them for meaning.
		local CONFETTI = { T.gold, T.green, Color3.fromRGB(94, 198, 255), Color3.fromRGB(255, 132, 190), T.outline }
		for i = 1, (big and 46 or 28) do
			local w = math.random(6, 12)
			local piece = mk("Frame", {
				BackgroundColor3 = CONFETTI[(i - 1) % #CONFETTI + 1], BorderSizePixel = 0,
				Size = UDim2.fromOffset(w, math.random(10, 18)), Rotation = math.random(0, 360),
				Position = UDim2.new(math.random(6, 94) / 100, 0, 0, -40), ZIndex = 7,
			}, stage)
			corner(piece, 3)
			local fall = 1.3 + math.random() * 1.1
			TweenService:Create(piece, TweenInfo.new(fall, Enum.EasingStyle.Linear), {
				Position = UDim2.new(piece.Position.X.Scale + (math.random(-12, 12) / 100), 0, 1.15, 0),
				Rotation = piece.Rotation + math.random(-320, 320),
			}):Play()
			TweenService:Create(piece, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
			Debris:AddItem(piece, fall + 0.2)
		end
	end

	-- ---- the card --------------------------------------------------------------------------------------------
	local CARD_W, CARD_H = 320, 420

	-- Big friendly button, the same glossy cartoon shape the crate reveal uses.
	local function bigButton(parent, text, fill, edge, order, width)
		local b = mk("TextButton", {
			Text = text, Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = T.textBright,
			AutoButtonColor = true, BackgroundColor3 = fill, Size = UDim2.fromOffset(width or 130, 44),
			LayoutOrder = order, ZIndex = 12,
		}, parent)
		corner(b, R_SMALL)
		grad(b, Color3.fromRGB(255, 255, 255), Color3.fromRGB(204, 204, 204))
		stroke(b, edge, 2)
		return b
	end

	local closeCurrent   -- set while a reveal is on screen

	showReveal = function(reward, onClosed)
		reward = reward or {}
		local p = present(reward)

		-- tear down anything still on screen (a respawn or a very fast second spin) so a reveal can never be
		-- blocked by leftover state
		if closeCurrent then closeCurrent(true) end
		for _, ch in ipairs(stage:GetChildren()) do
			if ch ~= centre and not ch:IsA("UIScale") then ch:Destroy() end
		end
		for _, ch in ipairs(centre:GetChildren()) do ch:Destroy() end

		revealGui.Enabled = true
		revealDim.BackgroundTransparency = 1
		TweenService:Create(revealDim, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()
		playBurst(p.big, p.accent)
		playRevealSound()

		-- triple navy drop shadow, drawn BEHIND the card as siblings (the card has a UIListLayout, so children
		-- would get laid out in its content column instead of sitting behind it)
		for i, sp in ipairs({ 70, 48, 28 }) do
			local sh = mk("Frame", {
				BackgroundColor3 = T.shadow, BackgroundTransparency = ({ 0.86, 0.74, 0.58 })[i], BorderSizePixel = 0,
				Size = UDim2.fromOffset(CARD_W + sp, CARD_H + sp), Position = UDim2.fromOffset(0, 6),
				AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 9,
			}, centre)
			corner(sh, 30)
		end

		local card = mk("Frame", {
			Name = "Card", BackgroundColor3 = T.panelTop, Size = UDim2.fromOffset(0, 0),
			Position = UDim2.fromOffset(0, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 10,
		}, centre)
		corner(card, R_PANEL)
		grad(card, T.panelTop, T.panelBot)
		stroke(card, T.outline, 4)      -- the thick white cartoon border, same weight as the crate card
		mk("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top, Padding = UDim.new(0, 10),
		}, card)
		mk("UIPadding", {
			PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18),
			PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18),
		}, card)

		local header = mk("TextLabel", {
			Text = p.header, Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = p.headerColor,
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1, ZIndex = 11,
		}, card)
		textStroke(header, T.shadow, 1.5, 0.5)

		-- reward tile: one big emoji on a coloured rounded square, ringed with sparkle dots
		local holder = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(140, 140), LayoutOrder = 2, ZIndex = 11 }, card)
		local tile = mk("Frame", {
			BackgroundColor3 = p.tile, Size = UDim2.fromOffset(132, 132), Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 11,
		}, holder)
		corner(tile, 22); stroke(tile, T.outline, 3)
		grad(tile, p.tile:Lerp(Color3.new(1, 1, 1), 0.35), p.tile:Lerp(Color3.new(0, 0, 0), 0.18))
		mk("TextLabel", {
			Text = p.emoji, Font = Enum.Font.GothamBlack, TextSize = 74, TextColor3 = T.textDark,
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 12,
			TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
		}, tile)
		for _, sp in ipairs({ {0.10, 0.14, 6}, {0.90, 0.20, 5}, {0.14, 0.88, 5}, {0.88, 0.84, 6} }) do
			local dot = mk("Frame", {
				BackgroundColor3 = T.outline, BackgroundTransparency = 0.05, BorderSizePixel = 0,
				Size = UDim2.fromOffset(sp[3] * 2, sp[3] * 2), Position = UDim2.fromScale(sp[1], sp[2]),
				AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 13,
			}, holder)
			round(dot)
			TweenService:Create(dot, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.55 }):Play()
		end
		-- the tile bounces in a beat after the card, which is what sells the "reveal"
		tile.Size = UDim2.fromOffset(0, 0)
		task.delay(0.16, function()
			if tile.Parent then
				TweenService:Create(tile, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(132, 132) }):Play()
			end
		end)

		local nameLbl = mk("TextLabel", {
			Text = p.name, Font = Enum.Font.GothamBlack, TextSize = 26, TextColor3 = T.textBright,
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 3, ZIndex = 11,
		}, card)
		textStroke(nameLbl, T.shadow, 2, 0.35)
		mk("TextLabel", {
			Text = p.sub, Font = Enum.Font.GothamSemibold, TextSize = 16, TextColor3 = T.textSoft,
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, LayoutOrder = 4, ZIndex = 11,
		}, card)

		local btnRow = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 5, ZIndex = 11 }, card)
		mk("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10),
		}, btnRow)

		-- CLOSE. `skipCallback` is used by the teardown-on-restart path so an interrupted reveal doesn't fire
		-- the caller's follow-up (e.g. opening the pet picker) a second time.
		local closed = false
		local function close(skipCallback)
			if closed then return end
			closed = true
			closeCurrent = nil
			TweenService:Create(revealDim, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Size = UDim2.fromOffset(0, 0) }):Play()
			task.delay(0.24, function()
				for _, ch in ipairs(centre:GetChildren()) do ch:Destroy() end
				revealGui.Enabled = false
			end)
			if not skipCallback and onClosed then task.spawn(onClosed) end
		end
		closeCurrent = close

		-- Level wins go straight into the pet-picker, so their button says what happens next rather than "OK".
		local isLevels = (reward.kind == "levels")
		local go = bigButton(btnRow, isLevels and "CHOOSE PET" or "AWESOME!", isLevels and Color3.fromRGB(46, 156, 255) or T.green,
			isLevels and Color3.fromRGB(22, 104, 210) or T.greenDeep, 1, isLevels and 150 or 190)
		go.Activated:Connect(function() close() end)

		-- pop the card in
		TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(CARD_W, CARD_H) }):Play()
	end
end

-- Quick scale pop on the spins counter, played when the number goes UP so a purchase visibly lands even if the
-- player's eyes are on the buy card rather than the counter.
local spinsValueScale = mk("UIScale", {}, spinsValue)
local function popSpins()
	spinsValueScale.Scale = 1.45
	TweenService:Create(spinsValueScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- ---- server -> client ---------------------------------------------------------------------------------------
local function refreshSpinButton()
	spinsValue.Text = tostring(spinsOwned)
	if spinning then
		spinText.Text = "SPINNING..."
		spinIcon.Text = "\xE2\x9C\xA6"
		setGrad(spinGrad, Color3.fromRGB(158, 196, 240), Color3.fromRGB(96, 138, 200))
		spinStroke.Color = Color3.fromRGB(52, 96, 164)
		hubLabel.Text = "..."
	elseif spinsOwned > 0 then
		spinText.Text = "SPIN"
		spinIcon.Text = "\xE2\x9C\xA8"
		setGrad(spinGrad, T.greenLight, T.greenDeep)
		spinStroke.Color = Color3.fromRGB(30, 84, 54)
		hubLabel.Text = "SPIN"
	else
		spinText.Text = "BUY SPINS"
		spinIcon.Text = "\xF0\x9F\x9B\x92"     -- shopping cart
		setGrad(spinGrad, T.goldLight, T.goldDeep)
		spinStroke.Color = T.goldShadow
		hubLabel.Text = "SPIN"
	end
	if pendingLevels > 0 then
		pendingBtn.Visible = true
		pendingText.Text = string.format("\xE2\xAD\x90  Assign +%d pet levels  \xE2\x86\x92", pendingLevels)
	else
		pendingBtn.Visible = false
	end
end

-- ---- buying spins -------------------------------------------------------------------------------------------
-- One in-flight purchase at a time. `setBuying(true, id)` veils the card that was clicked and locks the rest;
-- setBuying(false) clears every veil, whatever the outcome was, so the panel can never strand itself.
local function setBuying(on, productId)
	buying = on
	for id, veil in pairs(buyVeils) do
		veil.Visible = on and (id == productId)
	end
end

-- THE BUY BUTTON. In TEST_MODE this sends "buy" and the SERVER credits the spins (see PetWheel.server) -- the
-- client deliberately does not touch spinsOwned here, so what gets tested is the real path: click -> server
-- grant -> "state"/"purchased" push -> counter and SPIN button update from the server's number.
-- With real product ids in place (TEST_MODE = false) the exact same click opens the Roblox purchase prompt and
-- the credit arrives through ProcessReceipt instead. Nothing else in this file changes between the two.
purchase = function(product)
	if not product or buying then return end
	setBuying(true, product.id)
	if Config.TEST_MODE then
		remote:FireServer("buy", product.id)
	else
		local ok = pcall(function() MarketplaceService:PromptProductPurchase(player, product.productId) end)
		if not ok then
			setBuying(false)
			showToast("Purchase unavailable right now.")
			return
		end
	end
	-- safety net: if no answer ever arrives (dropped remote, closed prompt), unlock the cards rather than leaving
	-- the player staring at a veiled panel
	task.delay(6, function() if buying then setBuying(false) end end)
end

remote.OnClientEvent:Connect(function(verb, data)
	if verb == "state" then
		local before = spinsOwned
		spinsOwned = data.spins or 0
		pendingLevels = data.pending or 0
		refreshSpinButton()
		if spinsOwned > before then popSpins() end
		if buying then setBuying(false) end
	elseif verb == "purchased" then
		-- the pack landed. "state" (fired by the same server grant) already moved the counter; this verb exists
		-- to say WHICH pack, and to clear the veil the moment the purchase resolves.
		setBuying(false)
		local n = data.spins or 0
		showToast(string.format("\xF0\x9F\x8E\x9F +%d %s added \xE2\x80\x94 hit SPIN!", n, n == 1 and "spin" or "spins"), true)
	elseif verb == "result" then
		spinsOwned = data.spins or spinsOwned
		pendingLevels = data.pending or pendingLevels
		refreshSpinButton()
		local reward = data.reward or {}
		showToast("")
		animateTo(data.segIndex or 1, function()
			spinning = false
			refreshSpinButton()
			showToast(describeReward(reward), true)
			-- THE PAYOFF: the reveal card pops over the HUD. A level win routes into the pet-picker when the
			-- player dismisses it (the picker is the next step, so it waits for them rather than racing the
			-- card off the screen); coins and the mythical are already granted, so the card is the whole event.
			task.wait(0.25)
			showReveal(reward, reward.kind == "levels" and openPicker or nil)
		end)
	elseif verb == "assigned" then
		pendingLevels = data.pending or 0
		refreshSpinButton()
		if (data.added or 0) > 0 then
			showToast(string.format("\xE2\xAD\x90 +%d levels added!", data.added), true)
			-- leftover levels (pet hit the 25 cap) -> let them pick another pet
			if pendingLevels > 0 then task.wait(0.5); openPicker() end
		else
			showToast("That pet is already max level.")
		end
	elseif verb == "toast" then
		-- a server toast is only sent on a rejection (out of spins / not your pet / purchase refused); make sure a
		-- refused action can't leave the panel stuck on "SPINNING..." or veiled (neither got its normal reply).
		if spinning then spinning = false; refreshSpinButton() end
		if buying then setBuying(false) end
		showToast(tostring(data))
	end
end)

-- ---- client -> server / buttons -----------------------------------------------------------------------------
local function doSpin()
	if spinning then return end
	if spinsOwned < 1 then
		-- With no credits the button reads "BUY SPINS", so it has to actually buy: send the player straight at
		-- the single-spin pack (the cheapest one) rather than telling them to go and find a card. The outcome
		-- toast comes from the purchase itself, so nothing is announced up front.
		purchase(Config.PRODUCTS[1])
		return
	end
	spinning = true
	refreshSpinButton()
	remote:FireServer("spin")
end

spinBtn.Activated:Connect(doSpin)
hub.Activated:Connect(doSpin)

-- press feedback on the main button + hub
do
	local function press(btn, downScale)
		local base = btn.Size
		btn.MouseButton1Down:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.08), { Size = UDim2.new(base.X.Scale, base.X.Offset - downScale, base.Y.Scale, base.Y.Offset - downScale) }):Play()
		end)
		local function up() TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = base }):Play() end
		btn.MouseButton1Up:Connect(up)
		btn.MouseLeave:Connect(up)
	end
	press(spinBtn, 6)
	press(hub, 6)
	press(closeBtn, 4)
	press(oddsBtn, 4)
end

pendingBtn.Activated:Connect(function() openPicker() end)
oddsBtn.Activated:Connect(function() oddsOverlay.Visible = true end)
oddsClose.Activated:Connect(function() oddsOverlay.Visible = false end)
pickerClose.Activated:Connect(closePicker)

-- ---- keep the panel on screen on small displays ---------------------------------------------------------------
local function fitPanel()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local s = math.min(1, (vp.X - 40) / PANEL_W, (vp.Y - 40) / PANEL_H)
	panelScale.Scale = math.max(0.5, s)
end
fitPanel()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel)
		fitPanel()
	end
end)

-- ---- one idle-animation driver (early-outs while closed, so a closed wheel is free) -----------------------------
RunService.Heartbeat:Connect(function()
	if not gui.Enabled then return end
	local t = os.clock()
	for _, fn in ipairs(anims) do fn(t) end
end)

-- ---- open / close -------------------------------------------------------------------------------------------
local function setOpen(open)
	gui.Enabled = open
	if open then
		remote:FireServer("requestState") -- get fresh credits/pending on open
		showToast("")
		-- pop-in
		panel.Position = UDim2.new(0.5, 0, 0.5, 18)
		TweenService:Create(panel, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0.5, 0) }):Play()
	else
		oddsOverlay.Visible = false
		pickerOverlay.Visible = false
	end
end

-- The close button is the ONLY thing that closes this UI. `dim` still exists to darken the world and to swallow
-- clicks that land outside the panel, but it deliberately has no Activated handler -- clicking the backdrop used
-- to close everything, which made mis-clicks lose the panel mid-session.
closeBtn.Activated:Connect(function() setOpen(false) end)

-- ENTRY POINT for the Pet menu (PetHub_AllInOne calls this).
_G.togglePetWheel = function() setOpen(not gui.Enabled) end

refreshSpinButton()
remote:FireServer("requestState") -- prime state at load so the button label is correct before first open
print("[PetWheel] client ready")
