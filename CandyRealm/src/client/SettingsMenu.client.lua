--======================================================================
-- SettingsMenu.client.lua  (LocalScript)  --  CANDY REALM
--======================================================================
-- The gear button in the top-right HUD row, and the panel it opens: MUSIC and SOUND EFFECTS
-- on/off switches, a GRAPHICS selector, and a credits block. Per-player, in-memory
-- for the session (no DataStore).
--
-- It ONLY GATES audio OUTPUT — it never changes sound assets, the per-sound Volume values, the music
-- crossfade, or the ducking logic:
--   * MUSIC: gated via _G.musicEnabled, which MusicDucking respects. MusicDucking owns the
--     BackgroundMusic SoundGroup's volume, so forcing 0 there can't fight the crossfade/ducking.
--   * SOUND EFFECTS: every NON-music Sound is routed into a client-only "GameSFX" SoundGroup; the toggle
--     sets that group's Volume to 0 (off) or 1 (on). Group volume is multiplicative, so ON (1) leaves
--     every sound at its real volume and OFF (0) mutes them. Music voices (already in the BackgroundMusic
--     group) are skipped, so the two toggles are fully independent.
--
-- All of this is local to THIS player — one player muting never affects anyone else.
--
-- ===== THE FOOD REALM'S SETTINGS UI, PORTED AND RE-THEMED CANDY =====
-- The LAYOUT is a straight copy of src/client/SettingsMenu.client.lua in the main place: a centred
-- 360x470 card with a gloss sheen and a soft halo, a glossy gold "SETTINGS" header, a red X, and the rows
-- in a ScrollingFrame so they always fit and scroll on phones -- toggle rows 56 tall, track 72x32 with a
-- 26px knob, selector value pill 134x34, credits block 110. Every measurement is that file's.
-- What CandyRealm had before was the old 260x150 dark box pinned under the coin row.
--
-- The COLOURS are NOT that file's. Raspberry panel, grape rows, candy-wrapper white outlines -- see the
-- palette block below for where each one comes from.
--
-- FOUR DIFFERENCES FROM THE FOOD REALM FILE. The first is the re-theme; the rest are forced by what
-- exists in THIS place:
--   * CANDY, NOT BLUE. The food realm's blue/white/lime/gold card would sit on this realm's raspberry
--     HUD looking like another game's menu.
--   * NO GEAR PLACEMENT CODE. CurrencyCapsule.client.luau owns the top-right row here — it reparents
--     this exact button (SettingsGui/SettingsGearBtn, the names it looks for) into its row and re-asserts
--     the layout every frame. The old placeNextToCoins() waited 20s for a "CoinGui" that this place never
--     builds, so it did nothing anyway; writing a Position here would only fight the capsule.
--   * NO GLITTER TRAIL ROW. That switch drives _G.glitterTrailOn, which only CoreClient reads — and
--     CoreClient is a food-realm script. A switch that toggles nothing is worse than no switch, so the
--     row is gone until this realm grows a trail that reads the flag.
--   * The panel is CENTRED in its own ScreenGui instead of hanging off the currency row, so it no longer
--     needs to track anything.
--======================================================================

-- ONE GEAR ONLY. Rojo only ADDS scripts; a copy of this file baked into the place keeps running
-- alongside the synced one, and then there are two gears, two panels and two SFX groups, with the
-- second one to load silently winning every toggle. The claim below is VERSIONED: bump SETTINGS_BUILD
-- when behaviour changes and the newest copy always takes over. The old flag is still set, because
-- baked-in copies test it -- that is what makes THEM stand down when we win the race.
local SETTINGS_BUILD = 1   -- 1 = the food realm's panel LAYOUT in this realm's candy palette
if (_G.__SettingsMenuClientBuild or 0) >= SETTINGS_BUILD then return end
_G.__SettingsMenuClientBuild = SETTINGS_BUILD
_G.__SettingsMenuClient = true

local Players      = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Workspace    = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== STATE (per-player, in-memory for the session) =====
local musicOn = true
local sfxOn   = true
_G.musicEnabled = true  -- MusicDucking reads this (nil/true = play, false = mute)

--======================================================================
-- SOUND-EFFECTS routing: a client-only SoundGroup that all NON-music sounds play through, so one toggle
-- mutes every SFX without touching any individual sound's Volume.
--======================================================================
local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name   = "GameSFX_LocalSettings"
sfxGroup.Volume = 1   -- 1 = no change (identity); 0 = muted
sfxGroup.Parent = SoundService

-- Route a sound into the SFX group ONLY if it has no group yet. Sounds already in a group (the music
-- voices use the BackgroundMusic group) are left alone, so music stays on the music toggle.
local function routeSound(snd)
	if typeof(snd) ~= "Instance" or not snd:IsA("Sound") then return end
	if snd.SoundGroup == nil then
		pcall(function() snd.SoundGroup = sfxGroup end)
	end
end

-- Catch existing sounds + every future one. Sounds live under Workspace (positional/server sounds +
-- camera-anchored ambients, all descendants of Workspace) and SoundService (2D one-shots). The handler
-- is a cheap IsA check per descendant.
for _, d in ipairs(Workspace:GetDescendants())    do routeSound(d) end
for _, d in ipairs(SoundService:GetDescendants()) do routeSound(d) end
Workspace.DescendantAdded:Connect(routeSound)
SoundService.DescendantAdded:Connect(routeSound)

local function applySFX()
	sfxGroup.Volume = sfxOn and 1 or 0
end

local function applyMusic()
	_G.musicEnabled = musicOn
	if _G.refreshMusicVolume then pcall(_G.refreshMusicVolume) end -- MusicDucking re-applies its volume now
end

--======================================================================
-- CLEAR ANY STALE SETTINGS UI FIRST.
--======================================================================
-- If a baked-in copy of this script won the load race it has already built its own gear and panel.
-- CurrencyCapsule adopts "the" gear by name into its currency row, so a stale gear can end up in the row
-- (still opening the OLD dark panel) while ours sits unused in PlayerGui. Ours is stamped
-- BuiltByLiveScript so this can tell them apart, and the sweep is BY EXACT NAME -- our own widgets only,
-- never a blanket pass over PlayerGui. Repeated shortly after, because a stale copy that loads AFTER us
-- is only reachable once it has built itself.
local STALE_NAMES = {
	SettingsGui = true, SettingsPanelGui = true,   -- whole ScreenGuis
	SettingsGearBtn = true, SettingsPanel = true,  -- and the pieces, in case the capsule already took the gear
}
local function nukeStaleSettingsUi()
	local removed = 0
	for _, inst in ipairs(PlayerGui:GetDescendants()) do
		if STALE_NAMES[inst.Name] and (inst:IsA("ScreenGui") or inst:IsA("GuiObject"))
			and not inst:GetAttribute("BuiltByLiveScript") then
			pcall(function() inst:Destroy() end); removed = removed + 1
		end
	end
	if removed > 0 then
		warn("[Settings] cleared " .. removed .. " STALE settings widget(s) baked into the place. "
			.. "Delete the duplicate SettingsMenu LocalScripts in Studio for good.")
	end
end
nukeStaleSettingsUi()

--======================================================================
-- CANDY PALETTE -- the LAYOUT is the food realm's, the COLOURS are this realm's.
--======================================================================
-- The food realm's blue/white/lime/gold card would read as another game's UI sitting on top of a candy
-- HUD, so every colour here is lifted from what CandyRealm already ships:
--   * RASPBERRY panel -- the exact gradient ShopKit_AllInOne re-themes its shop card to
--     (196,66,148 -> 158,48,140), which is the same raspberry family as CurrencyCapsule's outer frame.
--     That makes the settings card, the shop and the currency row read as one HUD.
--   * GRAPE rows -- the capsule's token pill and the PETS rail button wear this. Grape on raspberry is
--     how this realm separates a control from its container: hue, not brightness, so nothing goes dark.
--   * Candy-wrapper WHITE outlines everywhere (the capsule's rule), gold 255,206,92 for the title,
--     candy green 86,205,120 for ON, and navy 6,26,80 for every text outline and shadow -- never black.
local C = {
	panel   = Color3.fromRGB(196,  66, 148),  -- raspberry, panel gradient TOP
	panelDk = Color3.fromRGB(158,  48, 140),  -- deeper raspberry, panel gradient BOTTOM
	row     = Color3.fromRGB(158,  88, 240),  -- GRAPE row body (the capsule's token pill)
	rowDeep = Color3.fromRGB(118,  48, 204),  -- deep grape -- the selector's value pill
	rowEdge = Color3.fromRGB( 90,  36, 160),  -- darker grape edge (the switch knob's rim)
	well    = Color3.fromRGB(140,  32, 100),  -- recessed raspberry -- the credits block
	line    = Color3.fromRGB(255, 190, 235),  -- candy-pink inner line
	muted   = Color3.fromRGB(255, 224, 244),  -- pale pink body text
	gold    = Color3.fromRGB(255, 206,  92),  -- treasure/title gold
	green   = Color3.fromRGB( 86, 205, 120),  -- candy green -> the ON switch
	shadow  = Color3.fromRGB(  6,  26,  80),  -- NAVY shadow, never black
	red     = Color3.fromRGB(232,  96,  90),  -- close button
	glow    = Color3.fromRGB(255, 150, 210),  -- the card's soft pink halo
}
local WHITE    = Color3.new(1, 1, 1)
local ON_GREEN = C.green
local OFF_DIM  = Color3.fromRGB(150, 96, 142) -- muted raspberry, still clearly part of the candy card

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p; return c
end
local function stroke(p, col, t)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = p; return s
end
-- Text outline in NAVY, not black -- the house rule for every panel in this game.
local function textStroke(lbl)
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(6, 26, 80); s.Thickness = 2; s.Parent = lbl; return s
end
local function maxText(obj, px)
	local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = px; c.Parent = obj
end
-- White sheen over the top 52%, fading down. ZIndex 0 = above the fill, below content.
local function addGloss(frame, cornerRadius)
	local hi = Instance.new("Frame")
	hi.Name = "Gloss"; hi.BackgroundColor3 = WHITE; hi.BorderSizePixel = 0
	hi.Position = UDim2.fromScale(0, 0); hi.Size = UDim2.new(1, 0, 0.52, 0); hi.ZIndex = 0
	corner(hi, cornerRadius or 12)
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = hi; hi.Parent = frame
	return hi
end
-- PANEL FILL: the raspberry top->bottom gradient this realm's shop card uses.
local function addPanelGradient(frame)
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.panel),
		ColorSequenceKeypoint.new(1, C.panelDk),
	})
	g.Parent = frame
	return g
end
-- CANDY-WRAPPER BORDER: a THICK WHITE outline. This is the single most recognisable part of the look --
-- every panel and pill in this realm is a candy-coloured card with a fat white rim.
local function addWhiteBorder(frame, thickness)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 4
	s.Color = WHITE
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = frame
	return s
end
-- Title sheen: gold -> deeper gold, the treasure look the crate + shop headers use.
local function addTextGloss(textObj)
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 240, 170)),
		ColorSequenceKeypoint.new(0.5, C.gold),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(208, 150,  24)),
	})
	g.Parent = textObj
	return g
end
-- A soft pink outer glow + a drop shadow, both SIBLINGS behind the panel, so the card reads as floating.
-- Needs the host ScreenGui on ZIndexBehavior.Sibling (set below) for the negative Z.
local function addPanelDepth(p, opts)
	opts = opts or {}
	local cr = (opts.corner or 16) + 4
	local a, pos, size, baseZ = p.AnchorPoint, p.Position, p.Size, p.ZIndex
	local parent = p.Parent
	local function layer(name, spread, dropY, color, transparency, z)
		local f = Instance.new("Frame")
		f.Name = name; f.AnchorPoint = a
		f.Position = UDim2.new(
			pos.X.Scale, pos.X.Offset + spread * (2 * a.X - 1),
			pos.Y.Scale, pos.Y.Offset + spread * (2 * a.Y - 1) + dropY)
		f.Size = UDim2.new(size.X.Scale, size.X.Offset + spread * 2, size.Y.Scale, size.Y.Offset + spread * 2)
		f.BackgroundColor3 = color; f.BackgroundTransparency = transparency
		f.BorderSizePixel = 0; f.ZIndex = z
		corner(f, cr); f.Parent = parent
		return f
	end
	-- NAVY shadow, never black (house rule), and the halo is candy pink so it reads as a soft sugary rim
	-- around the card rather than a grey drop shadow.
	local shadow = layer(p.Name .. "Shadow", opts.shadowSpread or 5, opts.shadowDrop or 5, C.shadow, 0.4, baseZ - 2)
	local glow   = layer(p.Name .. "Glow",   opts.glowSpread   or 7, 0, opts.glowColor or C.glow, 0.7, baseZ - 1)
	return glow, shadow
end

--======================================================================
-- THE GEAR BUTTON
--======================================================================
-- The NAMES matter: CurrencyCapsule.client.luau looks for a ScreenGui called "SettingsGui" holding a
-- button called "SettingsGearBtn" and pulls it into the top-right currency row. Rename either and the
-- gear silently falls back to the corner position below.
local sg = Instance.new("ScreenGui")
sg.Name = "SettingsGui"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true; sg.DisplayOrder = 60; sg.Parent = PlayerGui
sg:SetAttribute("BuiltByLiveScript", true)   -- the stamp nukeStaleSettingsUi() recognises as "ours"
task.delay(2, nukeStaleSettingsUi); task.delay(6, nukeStaleSettingsUi)
print(("[Settings] build %d ACTIVE (this is the Rojo copy)"):format(SETTINGS_BUILD))

-- RASPBERRY fill, corner 12, white glyph, a gloss sheen over the top half and a candy-wrapper white rim.
-- The food realm's version of this button is dark navy with a cyan neon edge; here it sits shoulder to
-- shoulder with the raspberry currency capsule, so it wears the capsule's colours instead -- same frame
-- raspberry, same white outline. The Position here is a FALLBACK only: the capsule reparents this button
-- into its row and zeroes the Position on the way in.
local gearBtn = Instance.new("TextButton")
gearBtn.Name = "SettingsGearBtn"
gearBtn.AnchorPoint = Vector2.new(1, 0)
gearBtn.Size = UDim2.new(0, 46, 0, 46)
gearBtn.Position = UDim2.new(1, -198, 0, 10)
gearBtn.BackgroundColor3 = Color3.fromRGB(176, 52, 128)  -- CurrencyCapsule's FRAME_TOP raspberry
gearBtn.Text = "\xE2\x9A\x99"                          -- U+2699 with NO variation selector, so it renders as
gearBtn.TextScaled = true                               -- a TINTED glyph instead of the fixed-colour emoji
gearBtn.Font = Enum.Font.GothamBold
gearBtn.TextColor3 = WHITE
gearBtn.TextStrokeColor3 = C.shadow                     -- navy glyph outline, never black
gearBtn.TextStrokeTransparency = 0.35
gearBtn.AutoButtonColor = true
gearBtn.ZIndex = 20
gearBtn.Parent = sg
gearBtn:SetAttribute("BuiltByLiveScript", true)   -- stamped too: the capsule may move it out of sg
corner(gearBtn, 12)
-- GLOSS: white sheen over the top 52%. Not Active, so it never eats the click meant for the button.
do
	local hi = Instance.new("Frame"); hi.Name = "Gloss"; hi.BackgroundColor3 = WHITE
	hi.BorderSizePixel = 0; hi.Position = UDim2.fromScale(0, 0); hi.Size = UDim2.new(1, 0, 0.52, 0)
	hi.ZIndex = gearBtn.ZIndex
	corner(hi, 12)
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = hi; hi.Parent = gearBtn
end
-- CANDY-WRAPPER RIM: the capsule's thick white outline, round-joined so the corners stay soft.
--
-- NO UIGradient ON THE BUTTON ITSELF, however much the capsule's shaded raspberry frame invites it: a
-- UIGradient tints a GuiObject's TEXT as well as its background, so a raspberry gradient here would
-- repaint the white gear glyph raspberry and it would vanish into its own button. The flat fill above
-- plus the Gloss child is the shading; only the stroke may carry a gradient (it is a separate object),
-- which is exactly how the food realm's neon edge gets away with it.
do
	local s = Instance.new("UIStroke"); s.Thickness = 3; s.Color = WHITE
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = gearBtn
end
do
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, 5); p.PaddingBottom = UDim.new(0, 5)
	p.PaddingLeft = UDim.new(0, 5); p.PaddingRight = UDim.new(0, 5)
	p.Parent = gearBtn
end

--======================================================================
-- THE PANEL -- centred card, 360x470.
--======================================================================
-- Its own ScreenGui: DisplayOrder 200 so the card always overlays the HUD and the shops (this realm's
-- layers: HUD <= 5, currency capsule 20, SettingsGui 60, shops 100). Enabled=false is the closed state --
-- nothing of it renders or takes input while shut.
local panelGui = Instance.new("ScreenGui")
panelGui.Name = "SettingsPanelGui"
panelGui.ResetOnSpawn = false
panelGui.IgnoreGuiInset = true
panelGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
panelGui.DisplayOrder = 200
panelGui.Enabled = false
panelGui.Parent = PlayerGui
panelGui:SetAttribute("BuiltByLiveScript", true)   -- same stamp, so nukeStaleSettingsUi never eats ours

-- Full-screen dim. It SINKS taps (so nothing behind the card can be clicked through) but does NOT close --
-- the X is the only way out. A stray tap must never shut a menu in this game.
local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.45
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.ZIndex = 1
backdrop.Parent = panelGui

local panel = Instance.new("Frame")
panel.Name = "SettingsPanel"
panel.Active = true -- sink clicks so tapping the card's chrome doesn't fall through to the backdrop
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
-- 700x520: the house panel size (Pet Hub, Shop, Daily Tasks, Season Pass, Gifting, Rebirth, the crate
-- panel -- every main menu in this realm). Settings was the one holdout at 360x470, and a menu half the
-- size of its siblings reads as an afterthought. The rows are all width-relative (1,-20) so they
-- stretch; only this line changes.
panel.Size = UDim2.new(0, 700, 0, 520)
panel.BackgroundColor3 = C.panel
panel.ZIndex = 2
panel.Parent = backdrop
panel:SetAttribute("BuiltByLiveScript", true)
corner(panel, 20)
addPanelDepth(panel, { corner = 20, glowSpread = 9, shadowSpread = 6, shadowDrop = 6 })
addPanelGradient(panel)
addGloss(panel, 20)
addWhiteBorder(panel, 4)

-- Title: gear glyph + "SETTINGS", glossy gold.
local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
-- U+2699 with NO variation selector, same as the gear button: a MONO glyph, which the gold title
-- gradient below tints along with the letters. A colour emoji (a lollipop, say) would be multiplied by
-- that gradient instead of matching it, and come out a muddy gold-on-red smear.
title.Text = "\xE2\x9A\x99 SETTINGS"
title.Font = Enum.Font.FredokaOne
title.TextColor3 = C.gold
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.Size = UDim2.new(1, -70, 0, 32)
title.Position = UDim2.new(0, 18, 0, 14)
title.ZIndex = 3
title.Parent = panel
textStroke(title)
addTextGloss(title)
maxText(title, 28)

-- Close: a RED button with a plain WHITE "X" on it, top-right. The letter X, not the U+2715
-- multiplication glyph -- that one renders thin and washed out (and boxes out in fonts that lack it).
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -12, 0, 12)
closeBtn.Size = UDim2.new(0, 38, 0, 38)
closeBtn.BackgroundColor3 = C.red
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.FredokaOne
closeBtn.TextScaled = true
closeBtn.TextColor3 = WHITE
closeBtn.ZIndex = 3
closeBtn.Parent = panel
corner(closeBtn, 10)
stroke(closeBtn, WHITE, 2)             -- white rim, matching the panel's white border
maxText(closeBtn, 22)

-- Rows live in a ScrollingFrame (AutomaticCanvasSize Y) so they always fit + scroll on small screens.
local rows = Instance.new("ScrollingFrame")
rows.Name = "Rows"
rows.BackgroundTransparency = 1
rows.BorderSizePixel = 0
rows.Position = UDim2.new(0, 16, 0, 64)
rows.Size = UDim2.new(1, -32, 1, -80)
rows.CanvasSize = UDim2.new(0, 0, 0, 0)
rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
rows.ScrollBarThickness = 4
rows.ScrollBarImageColor3 = C.line
rows.ZIndex = 3
rows.Parent = panel
do
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = rows
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 2); pad.PaddingBottom = UDim.new(0, 6); pad.Parent = rows
end

-- A labeled ON/OFF switch row: a pill track on a grape row (candy green = on, muted raspberry = off) with
-- a sliding white knob and an ON/OFF caption on the opposite side from the knob. The track IS the button.
local function makeToggleRow(order, labelText, getState, onChanged)
	local row = Instance.new("Frame")
	row.Name = labelText .. "Row"
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 56)
	row.BackgroundColor3 = C.row
	row.BackgroundTransparency = 0
	row.ZIndex = 3
	row.Parent = rows
	corner(row, 12)
	stroke(row, WHITE, 2)                 -- candy-wrapper white, the way every pill in this realm is edged

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Text = labelText
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextColor3 = WHITE
	lbl.TextScaled = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Size = UDim2.new(1, -110, 0, 26)
	lbl.Position = UDim2.new(0, 14, 0.5, 0)
	lbl.AnchorPoint = Vector2.new(0, 0.5)
	lbl.ZIndex = 4
	lbl.Parent = row
	textStroke(lbl)
	maxText(lbl, 22)

	local track = Instance.new("TextButton")
	track.Name = "Switch"
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -14, 0.5, 0)
	track.Size = UDim2.new(0, 72, 0, 32)
	track.AutoButtonColor = false
	track.Text = ""
	track.BackgroundColor3 = OFF_DIM
	track.ZIndex = 4
	track.Parent = row
	corner(track, 16)
	stroke(track, C.shadow, 1.5)          -- navy rim, never black

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.FredokaOne
	caption.TextColor3 = WHITE
	caption.TextScaled = true
	caption.Size = UDim2.new(0, 34, 0, 16)
	caption.ZIndex = 5
	caption.Parent = track

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.new(0, 26, 0, 26)
	knob.BackgroundColor3 = WHITE
	knob.ZIndex = 6
	knob.Parent = track
	corner(knob, 13)
	stroke(knob, C.rowEdge, 1)

	local function paint(animated)
		local on = getState()
		local knobPos = on and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 16, 0.5, 0)
		local capPos  = on and UDim2.new(0, 6, 0.5, 0)   or UDim2.new(1, -40, 0.5, 0)
		caption.Text = on and "ON" or "OFF"
		caption.Position = capPos
		caption.AnchorPoint = Vector2.new(0, 0.5)
		if animated then
			local ti = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(track, ti, { BackgroundColor3 = on and ON_GREEN or OFF_DIM }):Play()
			TweenService:Create(knob, ti, { Position = knobPos }):Play()
		else
			track.BackgroundColor3 = on and ON_GREEN or OFF_DIM
			knob.Position = knobPos
		end
	end

	track.Activated:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		onChanged(not getState())
		paint(true)
	end)
	paint(false)
	return row, paint
end

-- A labeled CYCLING selector: label left, a "< Option >" pill right that steps to the next option on tap.
local function makeSelectorRow(order, labelText, optionLabels, getIndex, onPick)
	local row = Instance.new("Frame")
	row.Name = labelText .. "Row"
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 56)
	row.BackgroundColor3 = C.row
	row.BackgroundTransparency = 0
	row.ZIndex = 3
	row.Parent = rows
	corner(row, 12)
	stroke(row, WHITE, 2)

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Text = labelText
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextColor3 = WHITE
	lbl.TextScaled = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Size = UDim2.new(1, -160, 0, 24)
	lbl.Position = UDim2.new(0, 14, 0.5, 0)
	lbl.AnchorPoint = Vector2.new(0, 0.5)
	lbl.ZIndex = 4
	lbl.Parent = row
	textStroke(lbl)
	maxText(lbl, 20)

	local valueBtn = Instance.new("TextButton")
	valueBtn.Name = "Value"
	valueBtn.AnchorPoint = Vector2.new(1, 0.5)
	valueBtn.Position = UDim2.new(1, -14, 0.5, 0)
	valueBtn.Size = UDim2.new(0, 134, 0, 34)
	valueBtn.AutoButtonColor = true
	valueBtn.BackgroundColor3 = C.rowDeep   -- deep grape, so the pill sits DOWN in its grape row
	valueBtn.Font = Enum.Font.FredokaOne
	valueBtn.TextColor3 = WHITE
	valueBtn.TextScaled = true
	valueBtn.Text = ""
	valueBtn.ZIndex = 4
	valueBtn.Parent = row
	corner(valueBtn, 10)
	stroke(valueBtn, WHITE, 2)            -- white rim, like every other button in this game
	maxText(valueBtn, 17)

	local function refresh()
		valueBtn.Text = "\xE2\x97\x80 " .. optionLabels[getIndex()] .. " \xE2\x96\xB6"
	end
	valueBtn.Activated:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		onPick((getIndex() % #optionLabels) + 1)   -- cycle forward (wraps)
		refresh()
	end)
	refresh()
	return row, refresh
end

makeToggleRow(1, "Music", function() return musicOn end, function(v)
	musicOn = v
	applyMusic()
end)
makeToggleRow(2, "Sound Effects", function() return sfxOn end, function(v)
	sfxOn = v
	applySFX()
end)

-- GRAPHICS -- Quality / Performance. "auto" resolves to Performance on phones (PhoneHUD.isPhone(), the
-- same detector ResponsiveUI uses; this realm may not ship the module, hence the pcall). The choice is
-- published as the LocalPlayer attribute "PerformanceMode" and _G.performanceMode.
-- NOTE: nothing in THIS place reads it yet, so today the row remembers the choice and nothing thins out;
-- point any FX/LOD script at the attribute and it starts working with no change here.
local perfPref = "auto"   -- "auto" | "quality" | "performance"
-- Resolved ONCE, without yielding: this runs while the panel is being built, and a WaitForChild here
-- would stall the whole build if PhoneHUD were missing. If it can't be read we just say "not a phone".
local isPhoneDevice = false
do
	local ok, phone = pcall(function()
		local mod = game:GetService("ReplicatedStorage"):FindFirstChild("PhoneHUD")
		return mod and require(mod).isPhone() or false
	end)
	isPhoneDevice = ok and phone == true
end
local function performanceOn()
	if perfPref == "performance" then return true end
	if perfPref == "quality" then return false end
	return isPhoneDevice   -- "auto"
end
local function applyPerformance()
	local on = performanceOn()
	player:SetAttribute("PerformanceMode", on)
	_G.performanceMode = on
end
makeSelectorRow(3, "Graphics", { "Quality", "Performance" },
	function() return performanceOn() and 2 or 1 end,
	function(i)
		perfPref = (i == 2) and "performance" or "quality"
		applyPerformance()
	end)

-- COLORBLIND MODE -- REMOVED at the owner's request (same call as the other realms). This place never had a
-- consumer for the attribute anyway, so the whole block goes: the row, the dead storage, and the boot publish.
-- Row LayoutOrder 4 is simply skipped -- UIListLayout doesn't mind gaps.

-- CREDITS / VERSION (read-only). Bump VERSION when you release.
local CREDITS_GAME    = "Fart to Float: Candy Realm"
local CREDITS_DEVS    = "Made by lando5485, Broskie310111 & itsmaddmax2"
local CREDITS_VERSION = "v1.0.0"
local CREDITS_THANKS  = "Thank you for playing! \xF0\x9F\x8D\xAC"   -- a candy, not the food realm's blue heart
local credits = Instance.new("TextLabel")
credits.Name = "Credits"
credits.LayoutOrder = 6
credits.Size = UDim2.new(1, 0, 0, 110)
credits.BackgroundColor3 = C.well        -- recessed raspberry, the capsule's shaded-frame colour
credits.BackgroundTransparency = 0
credits.Font = Enum.Font.FredokaOne
credits.TextColor3 = C.muted
credits.TextSize = 15
credits.TextWrapped = true
credits.RichText = true
credits.TextXAlignment = Enum.TextXAlignment.Center
credits.TextYAlignment = Enum.TextYAlignment.Center
credits.Text = ("<b>%s</b>\n%s\n%s\n%s"):format(CREDITS_GAME, CREDITS_DEVS, CREDITS_VERSION, CREDITS_THANKS)
credits.ZIndex = 3
credits.Parent = rows
corner(credits, 12)
stroke(credits, WHITE, 2)
do local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10); pad.Parent = credits end
maxText(credits, 16)

-- Publish the Graphics attribute immediately, so anything that starts reading it has a
-- value from the first frame rather than nil.
applyPerformance()

-- Open/close. The X is the only way out -- the backdrop deliberately does nothing (see above).
gearBtn.MouseButton1Click:Connect(function()
	if _G.playUIClick then pcall(_G.playUIClick) end
	panelGui.Enabled = not panelGui.Enabled
end)
closeBtn.Activated:Connect(function()
	if _G.playUIClick then pcall(_G.playUIClick) end
	panelGui.Enabled = false
end)

-- Anything else in this realm that wants to open settings can call this instead of hunting for the gear.
_G.toggleSettings = function()
	panelGui.Enabled = not panelGui.Enabled
end

-- Apply the initial state (both ON by default -> no audible change; ensures the group/flag are set).
applySFX()
applyMusic()
