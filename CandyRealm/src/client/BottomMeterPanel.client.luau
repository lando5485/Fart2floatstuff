--======================================================================
-- BottomMeterPanel.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- THE BOTTOM HUD PANEL -- icon + name + meter + one action button, as ONE card.
--
-- CANDYREALM COPY of the portable kit, ported from Fart to Float: Dinosaur Realm. The card,
-- the meter and the button are the component; nothing in this file knows what the number
-- means or moves the player. Re-themed CANDY (see LOOK) -- the jungle olive it shipped in
-- read as a different game's HUD next to the candy rail and the navy/gold currency capsule.
--
-- ===== WHAT IT REPLACED =====
-- This IS CandyRealm's bottom HUD now. It took over from the three stacked slabs that
-- JustButtons_AllInOne used to build -- a pink "Stomach" pill, a blue GAS METER panel and a
-- green HOLD TO FART button, ~200px of screen in three separate rounded rectangles. Same
-- information, one 144px card.
--
-- ===== THE TWO CONTRACTS IT HAD TO KEEP =====
-- 1. THE GUI IS STILL CALLED "BottomStackGui". Five scripts reach for that exact name to
--    hide the HUD -- Campfire (roasting), CrateClient, GardenerChat, PetFollow and
--    JustButtons' own MainMenuManager.setHud (any main menu opening). Renaming it would have
--    silently broken all five, so GUI_NAME keeps it. Nothing else needed to change.
-- 2. PROPELSYSTEM DRIVES THE NUMBERS, NOT LEADERSTATS. The flight engine
--    (PropelSystem_AllInOne) keeps gasMeter / currentPower in LOCALS and never writes them
--    to leaderstats -- its stomachMax is a hardcoded 100. So the kit's default
--    CUR_STAT/MAX_STAT wiring would have shown numbers with no relation to the real meter.
--    Instead the stats are nil (the value loop below goes inert) and the card publishes its
--    own parts on _G.HUD, which is the handle PropelSystem has always written to:
--        _G.HUD.gasFill   <- the fill frame   (it sets .Size to the fuel fraction)
--        _G.HUD.gasPct    <- the value label  (it sets .Text to "62%")
--        _G.HUD.fartLabel <- the button label (idle / FARTING text)
--    So the engine needed NO changes at all: it writes the same three handles it always did.
--
--     +--------------------------------------------------+
--     |  ( icon )   Title Text                           |   <- 470 x 144 card
--     |             (=====meter=========  1234/5000  )   |
--     |  [            TAP TO FART!                   ]   |   <- 446 x 52 button
--     +--------------------------------------------------+
--
-- ===== HOW THE GEOMETRY IS DERIVED =====
-- Every number below was solved backwards from a live measurement of the reference HUD, so
-- they are NOT free values -- they agree with each other and with PAD = 12:
--     the track ends at 76 + 382 = 458 = 470 - 12          -> right pad 12
--     the button spans 12 .. 458                           -> both pads 12
--     12 + 16 + 6 + 36 + 10 + 52 + 12 = 144                -> the card's height
-- Change one and re-derive the rest. Nudging a single constant on its own is what makes a
-- card whose contents no longer line up with its own edges.
--
-- ===== POSITIONING =====
-- The card hangs off the BOTTOM CENTRE of the screen: anchor (0.5, 1), and BOTTOM_GAP is
-- literally the pixel gap between the card's bottom edge and the viewport's. The two other
-- gaps are consequences of it, not separate settings:
--     glow bottom   = BOTTOM_GAP - GLOW_OUT
--     button bottom = BOTTOM_GAP + PAD
-- OFFSET, NOT SCALE, deliberately: a scale would match on one screen height and nowhere
-- else. The panel is authored at full size on every device -- if your realm has a
-- responsive scaler, let it hang ONE UIScale on the row (see RESPONSIVE_SHRINK).
--
-- ===== WIRING IT UP =====
-- Everything you change is in CONFIG. Values are tried in order:
--     1. whatever was last passed to _G.BottomMeterPanel.setValue()
--     2. leaderstats.<CUR_STAT> / leaderstats.<MAX_STAT>
--     3. _G[<CUR_GLOBAL>] / _G[<MAX_GLOBAL>]
-- so a realm with leaderstats needs no code at all, and one that keeps the value in a
-- script just calls the setter. Set SHOW_BUTTON = false for a display-only meter.
--======================================================================

local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local player             = Players.LocalPlayer
local PlayerGui          = player:WaitForChild("PlayerGui")

--======================================================================
-- CONFIG -- the whole of what a new realm has to think about
--======================================================================
local CONFIG = {
	-- ---- what it says --------------------------------------------------------------
	-- "GAS METER" is the title the blue panel carried before, kept so nothing about the HUD
	-- reads as renamed. The badge takes the fart cloud the old green button used.
	TITLE      = "GAS METER",
	ICON       = "\xF0\x9F\x92\xA8",  -- emoji in the badge. Emoji render in their OWN colours
	                                  -- (TextColor3 is ignored), so for a recoloured icon use
	                                  -- an ImageLabel instead of this string.
	-- Tier swap is driven from apply(), and apply() only runs off the value loop -- which is
	-- inert here (see below). Empty until something actually feeds this card a max.
	TIERS = {},

	-- ---- where the numbers come from -------------------------------------------------
	-- ALL NIL ON PURPOSE. PropelSystem_AllInOne owns the meter and writes it straight into
	-- the handles published on _G.HUD at the bottom of this file. Pointing these at
	-- leaderstats.CurrentPower / StomachMax would show a SECOND, unrelated number: the flight
	-- engine keeps its fuel in locals and never writes those stats. With every source nil,
	-- readStat returns nil, the loop's `if cur or max` never fires, and the engine is the
	-- single writer -- which is the only way the bar and the digits can't disagree.
	CUR_STAT   = nil,
	MAX_STAT   = nil,
	CUR_GLOBAL = nil,
	MAX_GLOBAL = nil,
	VALUE_FORMAT = function(cur, max) return string.format("%d/%d", math.floor(cur), math.floor(max)) end,

	-- ---- the button --------------------------------------------------------------------
	SHOW_BUTTON  = true,
	-- These two strings are not free text: PropelSystem writes them into the label itself on
	-- every state change. They must match what updateFartLabel() sets VERBATIM, or the button
	-- flickers between two wordings for the same state.
	BUTTON_TEXT  = "HOLD TO FART!",                 -- idle
	BUTTON_ACTIVE_TEXT = "FARTING! (TAP TO STOP)",  -- while flying
	-- FALSE, and it matters: PropelSystem already binds Space to toggleFart (its InputBegan
	-- handler). A second bind here would fire the toggle TWICE per press -- on, then straight
	-- back off -- so Space would look like it did nothing at all.
	BIND_SPACE   = false,
	-- Looked up at press time, never captured: load order between LocalScripts is arbitrary,
	-- so _G.toggleFart may not exist yet when this file runs.
	ON_PRESS     = function() if type(_G.toggleFart) == "function" then pcall(_G.toggleFart) end end,
	CLICK_SOUND  = "playUIClick",               -- _G function name to call on press, or nil

	-- ---- where it sits -----------------------------------------------------------------
	-- The name FIVE other scripts use to hide this HUD. See the header -- do not rename it.
	GUI_NAME          = "BottomStackGui",
	BOTTOM_GAP        = 12,   -- px from the card's bottom edge to the bottom of the screen
	DISPLAY_ORDER     = 5,    -- same layer the old bottom stack sat on
	RESPONSIVE_SHRINK = 0.72, -- read by a responsive scaler off the row, if your realm has one
}

--======================================================================
-- LOOK -- colours here, not in the build. CANDY, not the jungle olive this shipped in: the
-- card is bubblegum, every outline is a thick WHITE candy-wrapper border, and the recesses
-- are deep raspberry rather than near-black. Swap the block and the card re-themes without
-- touching a line of the build.
--
-- House palette rules this follows (CrateClient's `local C`, the Daily Rewards reveal):
-- bright and kid-friendly, never dark or casino; thick white borders; lime 126,217,87 for
-- good news; gold 255,210,74 for treasure; navy 6,26,80 for shadow -- never black.
--======================================================================
-- THE CARD BODY IS THE STATS PINK, verbatim: CANDY.bodyTop / bodyBot from
-- StatsPanelKit_AllInOne, the same pink the MORE+ rail button and ShopKit's PANEL2 wear. It is
-- also the CONTRAST-MEASURED one -- the stats panel records a first draft of (238,116,186) at
-- 2.7:1 against white text where this reads ~4.7:1 -- which matters here too, because the title
-- and the meter's digits are read straight off this surface.
local PANEL_LIT  = Color3.fromRGB(196,  66, 148) -- top of the card
local PANEL_DEEP = Color3.fromRGB(158,  48, 140) -- the same pink shaded, bottom of the card
-- RECESSES STAY DARKER ON PURPOSE. The track and the badge are holes in the card, not panels
-- on it -- if they share the card's own colour the meter becomes a bright bar in a bright
-- trough and the fill stops reading. Deepened to PLUM when the card body went from bubblegum
-- to the deeper stats pink: at the old raspberry (140,32,100) the trough had nearly caught up
-- with the card and stopped reading as a hole. This is the stats panel's own ink family, so it
-- is still candy, and still nowhere near the no-dark-panels line.
local RECESS     = Color3.fromRGB(104,  20,  84) -- track + badge interiors
local RECESS_DIM = Color3.fromRGB( 82,  12,  66) -- top of each recess, so contents sit down in it
local EDGE       = Color3.fromRGB(255, 255, 255) -- candy wrapper: EVERY outline on the panel
local FILL_LIT   = Color3.fromRGB(170, 240, 120) -- top of the meter fill: the house lime, and
local FILL_DEEP  = Color3.fromRGB( 96, 200,  74) -- close to the green the old gas bar used, so
                                                 -- a full tank still reads as "full" at a glance
-- IDLE BUTTON -- candy-corn gold. The one thing on the card that is NOT pink, and deliberately:
-- it is the only control here, so it has to separate from the card by hue and not just by being
-- a slightly different shade of it. Gold on the stats pink is also the house's own treasure
-- pairing (CrateClient's gold 255,210,74 over its panels).
local BTN_LIT    = Color3.fromRGB(255, 206,  74) -- top of the idle button
local BTN_DEEP   = Color3.fromRGB(240, 148,  34) -- bottom of it
-- ACTIVE lights the button to the METER'S OWN GREEN. Gold -> green is a far louder state
-- change than a lighter gold, and it ties the button to the bar it is draining.
local BTN_ON_LIT = Color3.fromRGB(196, 250, 146)
local BTN_ON_MID = Color3.fromRGB(150, 232, 108)
local BTN_ON_DEEP= Color3.fromRGB(104, 208,  76)
local BTN_INSET  = Color3.fromRGB(186, 100,  16) -- the button's inner shade ring
local INK        = Color3.fromRGB(  6,  26,  80) -- text outline + shadow: house NAVY, never black
local WHITE      = Color3.fromRGB(255, 255, 255) -- gloss highlights ONLY, never text
local CREAM      = Color3.fromRGB(255, 252, 245) -- all text on the panel

--======================================================================
-- GEOMETRY -- measured, and interlocking. See the header before editing.
--======================================================================
local PANEL_W     = 470
local PAD         = 12
local TITLE_H     = 16
local TITLE_GAP   = 6
local BAR_H       = 36
local ICON_D      = 52                        -- badge diameter
local BAR_Y       = TITLE_H + TITLE_GAP       -- 22, from the card's padding box
local TOP_H       = BAR_Y + BAR_H             -- 58
local SECTION_GAP = 10
local CTA_H       = 52
local PANEL_H     = PAD + TOP_H + SECTION_GAP + CTA_H + PAD  -- 144
local PANEL_R     = 22
local GLOW_OUT    = 7                         -- 470+14 = 484, 144+14 = 158
local EDGE_W      = 2                         -- ONE border weight for the whole panel
local INK_W       = 1.5                       -- ONE text-outline weight

local ICON_X  = PAD
local BAR_X   = 76                            -- measured
local BAR_W   = (PANEL_W - PAD) - BAR_X       -- 382, measured
local BAR_TOP = PAD + BAR_Y                   -- 34, measured
local CTA_Y   = PAD + TOP_H + SECTION_GAP     -- 80, measured
local CTA_W   = PANEL_W - PAD * 2             -- 446, measured

--======================================================================
-- HELPERS
--======================================================================
local function mkCorner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p; return c end
local function mkStroke(p, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = p; return s end
local function mkLabel(p, props) local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; for k, v in pairs(props) do l[k] = v end; l.Parent = p; return l end
local function mkFrame(p, props) local f = Instance.new("Frame"); for k, v in pairs(props) do f[k] = v end; f.Parent = p; return f end
local function mkButton(p, props) local b = Instance.new("TextButton"); for k, v in pairs(props) do b[k] = v end; b.Parent = p; return b end
local function click()
	local name = CONFIG.CLICK_SOUND
	if name and type(_G[name]) == "function" then pcall(_G[name]) end
end

-- A soft ambient shadow under the card. Roblox cannot blur, so the falloff is faked with
-- three progressively larger and fainter rounded rects behind the thing casting it. Kept
-- LIGHT (0.76+) so the card sits ON the screen rather than hovering well above it.
local function ambientShadow(parent, radius)
	for i = 3, 1, -1 do
		local grow = i * 3
		local sh = mkFrame(parent, {
			Name = "Shadow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, i * 2),
			Size = UDim2.new(1, grow, 1, grow),
			BackgroundColor3 = INK,
			BackgroundTransparency = 0.76 + i * 0.07,
			BorderSizePixel = 0,
			ZIndex = 1,
		})
		mkCorner(sh, radius + math.floor(grow / 2))
	end
end

-- Text with a thick dark outline plus an offset dark copy behind it for the drop shadow.
-- Returns the front label; the shadow tracks it via a Changed hook so the two can never say
-- different things.
--
-- `maxText` is applied to BOTH copies, and it has to be: these are TextScaled, so a shadow
-- without the same cap grows to fill its box while the front label stops at the cap -- and
-- the "shadow" ends up visibly bigger than the text it is meant to sit behind.
local function boldText(parent, props, maxText)
	local shadow = mkLabel(parent, {
		Text = props.Text, Font = props.Font, TextScaled = props.TextScaled,
		TextColor3 = INK, TextTransparency = 0.55,
		Size = props.Size, Position = props.Position + UDim2.fromOffset(0, 2),
		AnchorPoint = props.AnchorPoint, TextXAlignment = props.TextXAlignment,
		TextYAlignment = props.TextYAlignment,
		ZIndex = (props.ZIndex or 1) - 1,
	})
	local front = mkLabel(parent, props)
	mkStroke(front, INK, INK_W)
	if maxText then
		for _, lbl in ipairs({ front, shadow }) do
			local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = maxText; c.Parent = lbl
		end
	end
	front:GetPropertyChangedSignal("Text"):Connect(function() shadow.Text = front.Text end)
	return front
end

--======================================================================
-- THE SCREEN GUI + ROW
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = CONFIG.GUI_NAME or "BottomMeterGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = CONFIG.DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = PlayerGui

-- Anchor (0.5, 1) and a single child, so BOTTOM_GAP IS the gap from the screen's bottom edge.
local row = Instance.new("Frame")
row.Name = "BottomStack"
row.AnchorPoint = Vector2.new(0.5, 1)
row.Position = UDim2.new(0.5, 0, 1, -CONFIG.BOTTOM_GAP)
row.Size = UDim2.new(0, PANEL_W, 0, 0)
row.AutomaticSize = Enum.AutomaticSize.Y
row.BackgroundTransparency = 1
row.Parent = gui
if CONFIG.RESPONSIVE_SHRINK then row:SetAttribute("ResponsiveExtraShrink", CONFIG.RESPONSIVE_SHRINK) end
do
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Vertical
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	sl.Padding = UDim.new(0, 8)
	sl.Parent = row
end

--======================================================================
-- THE CARD
--======================================================================
local wrap = mkFrame(row, { Name = "MeterPanel", Size = UDim2.fromOffset(PANEL_W, PANEL_H),
	BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 10 })
ambientShadow(wrap, PANEL_R)

-- The halo, GLOW_OUT past the card on every side. A sibling BEHIND the card (ZIndex 2 vs 3)
-- rather than a UIStroke, because a stroke cannot be soft and this has to read as light
-- spilling out from under the panel.
local glow = mkFrame(wrap, {
	Name = "MeterGlow", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, GLOW_OUT * 2, 1, GLOW_OUT * 2),
	BackgroundColor3 = EDGE, BackgroundTransparency = 0.68, BorderSizePixel = 0, ZIndex = 2,
})
mkCorner(glow, PANEL_R + GLOW_OUT)

local card = mkFrame(wrap, { Name = "Card", Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = PANEL_LIT, BorderSizePixel = 0, ZIndex = 3 })
mkCorner(card, PANEL_R)
mkStroke(card, EDGE, EDGE_W)
do -- very subtle vertical gradient, lighter at the top
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new(PANEL_LIT, PANEL_DEEP); g.Parent = card
end
do -- inner liner: 1px at 0.6 transparency is a hint of depth, not a second border
	local liner = mkFrame(card, { Name = "InnerLine", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -5, 1, -5),
		BackgroundTransparency = 1, ZIndex = 4 })
	mkCorner(liner, PANEL_R - 3)
	local s = mkStroke(liner, PANEL_DEEP, 1); s.Transparency = 0.6
end

-- ---- TITLE, aligned to where the TRACK begins so the two share one left edge ----------
local titleLbl = boldText(card, {
	Name = "Title", Text = CONFIG.TITLE, Font = Enum.Font.FredokaOne, TextScaled = true,
	TextColor3 = CREAM, Size = UDim2.fromOffset(BAR_W, TITLE_H),
	Position = UDim2.fromOffset(BAR_X, PAD),
	AnchorPoint = Vector2.new(0, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7,
}, 16)

-- ---- THE TRACK -----------------------------------------------------------------------
local track = mkFrame(card, { Name = "Track", Size = UDim2.fromOffset(BAR_W, BAR_H),
	Position = UDim2.fromOffset(BAR_X, BAR_TOP), BackgroundColor3 = RECESS,
	ZIndex = 5, BorderSizePixel = 0 })
mkCorner(track, math.floor(BAR_H / 2))   -- fully rounded ends
mkStroke(track, EDGE, EDGE_W)
do -- darkest at the TOP, so the fill reads as sitting down inside the trough
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new(RECESS_DIM, RECESS); g.Parent = track
end

local fill = mkFrame(track, { Name = "Fill", Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = FILL_LIT, ZIndex = 6, BorderSizePixel = 0 })
mkCorner(fill, math.floor(BAR_H / 2))    -- rounded, so the leading end stays a cap at every width
do
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new(FILL_LIT, FILL_DEEP); g.Parent = fill
end
do -- soft highlight across the top of the FILL. A child of the fill, so it grows with it and
	-- never floats over empty track.
	local sheen = mkFrame(fill, { Name = "Sheen", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(1, -14, 0, 6),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.66, BorderSizePixel = 0, ZIndex = 7 })
	mkCorner(sheen, 3)
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = sheen
end
local valueLbl = boldText(track, {
	Name = "ValueText", Size = UDim2.new(1, 0, 1, 0), Position = UDim2.fromOffset(0, 0),
	AnchorPoint = Vector2.new(0, 0), Text = "0/0", Font = Enum.Font.FredokaOne, TextScaled = true,
	TextColor3 = CREAM, ZIndex = 10, TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
}, 20)

-- ---- THE BADGE, built AFTER the track so it draws over it ------------------------------
-- Its vertical centre is the TRACK's centre, not the row's -- that is what visually attaches
-- it to the meter instead of leaving it floating beside the row. At ICON_D 52 it clears the
-- button below by 2px; grow it past 56 and it starts hanging over the CTA.
local badge = mkFrame(card, { Name = "IconWell", AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromOffset(ICON_X, BAR_TOP + math.floor(BAR_H / 2)),
	Size = UDim2.fromOffset(ICON_D, ICON_D), BackgroundColor3 = RECESS,
	BorderSizePixel = 0, ZIndex = 8 })
mkCorner(badge, 999)
mkStroke(badge, EDGE, EDGE_W)
do -- darker at the TOP, the opposite of the card: that inversion is what sinks it in
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new(RECESS_DIM, RECESS); g.Parent = badge
end
-- Sized off the circle and centred on BOTH axes. Emoji have uneven glyph boxes, so a
-- full-bleed square plus centre/centre alignment is what actually lands one in the middle --
-- an eyeballed offset only ever centres the one emoji you tuned it against.
local iconLbl = mkLabel(badge, { Name = "Icon", Text = CONFIG.ICON, Font = Enum.Font.GothamBold,
	TextScaled = true, Size = UDim2.fromScale(0.66, 0.66), Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5), TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 9 })

--======================================================================
-- THE BUTTON
--======================================================================
local btnFill, btnGrad, btnLabel, hit
if CONFIG.SHOW_BUTTON then
	local slot = mkFrame(card, {
		Name = "CTASlot",
		Size = UDim2.fromOffset(CTA_W, CTA_H),
		Position = UDim2.fromOffset(PAD, CTA_Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
	})
	local R = math.floor(CTA_H / 2)

	btnFill = mkFrame(slot, { Name = "Fill", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BTN_LIT, BorderSizePixel = 0, ZIndex = 5 })
	mkCorner(btnFill, R)
	btnGrad = Instance.new("UIGradient")
	btnGrad.Rotation = 90
	btnGrad.Color = ColorSequence.new(BTN_LIT, BTN_DEEP)
	btnGrad.Parent = btnFill

	do -- outline, inset ring and gloss, all on the SLOT rather than the fill, so recolouring
		-- the fill on state change never disturbs the decoration
		local shell = mkFrame(slot, { Name = "Shell", Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1, ZIndex = 9 })
		mkCorner(shell, R)
		mkStroke(shell, EDGE, EDGE_W)
		local ins = mkFrame(slot, { Name = "InsetShade", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -3, 1, -3),
			BackgroundTransparency = 1, ZIndex = 9 })
		mkCorner(ins, math.max(2, R - 2))
		local s = mkStroke(ins, BTN_INSET, 1); s.Transparency = 0.6
		local sheen = mkFrame(slot, { Name = "Sheen", AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(1, -34, 0, 5),
			BackgroundColor3 = WHITE, BackgroundTransparency = 0.86, BorderSizePixel = 0, ZIndex = 6 })
		mkCorner(sheen, 3)
		local sg = Instance.new("UIGradient")
		sg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
		})
		sg.Parent = sheen
	end

	-- One transparent hit target over everything, so a tap anywhere in the slot counts. The
	-- text is a SEPARATE label at ZIndex 11 -- above the gloss (6) and the shell (9) -- because
	-- a TextButton's own text sits under both and comes out washed.
	hit = mkButton(slot, { Name = "Button", Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 10 })
	btnLabel = boldText(slot, {
		Name = "ButtonText", Text = CONFIG.BUTTON_TEXT, Font = Enum.Font.FredokaOne, TextScaled = true,
		TextColor3 = CREAM, Size = UDim2.new(1, -32, 0, 28), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 11,
	}, 24)

	local function press()
		click()
		if CONFIG.ON_PRESS then pcall(CONFIG.ON_PRESS) end
	end
	hit.Activated:Connect(press)
	if CONFIG.BIND_SPACE then
		UserInputService.InputBegan:Connect(function(io, gp)
			if gp then return end
			if io.KeyCode == Enum.KeyCode.Space then press() end
		end)
	end
end

--======================================================================
-- VALUES + PUBLIC API
--======================================================================
local override = {}

local function readStat(statName, globalName, key)
	if override[key] then return override[key] end
	if statName then
		local ls = player:FindFirstChild("leaderstats")
		local v = ls and ls:FindFirstChild(statName)
		if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then return v.Value end
	end
	if globalName then
		local n = tonumber(_G[globalName])
		if n then return n end
	end
	return nil
end

local lastMax = nil
local function apply(cur, max)
	cur, max = math.max(cur or 0, 0), math.max(max or 0, 0)
	local pct = max > 0 and math.clamp(cur / max, 0, 1) or 0
	fill.Size = UDim2.new(pct, 0, 1, 0)
	valueLbl.Text = CONFIG.VALUE_FORMAT(cur, max)
	-- tier swap, if this realm uses one
	if max ~= lastMax then
		lastMax = max
		local tier = CONFIG.TIERS and CONFIG.TIERS[max]
		if tier then
			if tier.title then titleLbl.Text = tier.title end
			if tier.icon  then iconLbl.Text  = tier.icon  end
		end
	end
end

_G.BottomMeterPanel = {
	setValue  = function(cur, max) override.cur = tonumber(cur); override.max = tonumber(max) end,
	setTitle  = function(s) titleLbl.Text = tostring(s) end,
	setIcon   = function(s) iconLbl.Text = tostring(s) end,
	-- Your game owns the on/off state; call this when it flips. The button lights up to the
	-- meter's own green, which is a much louder change than a lighter shade of the idle colour.
	setActive = function(on)
		if not btnFill then return end
		if on then
			btnFill.BackgroundColor3 = BTN_ON_MID
			btnGrad.Color = ColorSequence.new(BTN_ON_LIT, BTN_ON_DEEP)
			btnLabel.Text = CONFIG.BUTTON_ACTIVE_TEXT
		else
			btnFill.BackgroundColor3 = BTN_LIT
			btnGrad.Color = ColorSequence.new(BTN_LIT, BTN_DEEP)
			btnLabel.Text = CONFIG.BUTTON_TEXT
		end
	end,
	config = CONFIG, gui = gui, row = row, card = card, button = hit,
}

--======================================================================
-- THE FLIGHT-ENGINE HANDLES -- what makes this card the realm's real HUD
--======================================================================
-- PropelSystem_AllInOne has always written these three, and it still does, unchanged. The old
-- bottom stack published a bar Frame, a "62%" TextLabel and the button's text label; this card
-- publishes its own equivalents, so the engine never learns anything moved.
--
-- valueLbl and btnLabel come from boldText(), which keeps a shadow copy in step via a Changed
-- hook -- so the engine writing .Text directly still gets the shadowed text for free.
_G.HUD = _G.HUD or {}
_G.HUD.gasFill = fill        -- engine sets .Size = UDim2.new(fuelFraction, 0, 1, 0)
_G.HUD.gasPct  = valueLbl    -- engine sets .Text = "62%"
if btnLabel then _G.HUD.fartLabel = btnLabel end -- engine sets idle / FARTING text

apply(0, 0)
valueLbl.Text = "0%"   -- the engine's units, not the kit's "0/0", for the frame before it writes

task.spawn(function()
	local wasFlying = nil
	while true do
		-- The VALUE sources are all nil in this realm, so this is a no-op and the engine stays
		-- the single writer of the bar and the digits. Left in place: the moment a realm sets
		-- CUR_STAT or CUR_GLOBAL, it starts working again with no other change.
		local cur = readStat(CONFIG.CUR_STAT, CONFIG.CUR_GLOBAL, "cur")
		local max = readStat(CONFIG.MAX_STAT, CONFIG.MAX_GLOBAL, "max")
		if cur or max then apply(cur or 0, max or lastMax or 0) end

		-- BUTTON COLOUR. PropelSystem drives the button's TEXT itself but knows nothing about
		-- this card's gold->green active state, so mirror it off _G.isFlying -- the flag the
		-- engine already sets in startFlying / stopFlying / CharacterAdded. Edge-triggered, so
		-- it is two property writes on a state change and nothing at all in between.
		local flying = _G.isFlying == true
		if flying ~= wasFlying then
			wasFlying = flying
			_G.BottomMeterPanel.setActive(flying)
		end
		task.wait(0.1)
	end
end)

print(("[MeterPanel] CandyRealm bottom HUD ready as '%s' -- card=%dx%d glow=%dx%d track=%dx%d slot=%dx%d "
	.. "| bottomGap card=%d glow=%d slot=%d | driven by PropelSystem via _G.HUD")
	:format(gui.Name, PANEL_W, PANEL_H, PANEL_W + GLOW_OUT * 2, PANEL_H + GLOW_OUT * 2,
		BAR_W, BAR_H, CTA_W, CTA_H,
		CONFIG.BOTTOM_GAP, CONFIG.BOTTOM_GAP - GLOW_OUT, CONFIG.BOTTOM_GAP + PAD))
