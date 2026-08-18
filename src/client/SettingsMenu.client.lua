--======================================================================
-- SettingsMenu.client.lua  (LocalScript)
--======================================================================
-- A small CLIENT-SIDE settings menu: a gear button in the TOP-LEFT corner that opens a panel with
-- MUSIC and SOUND EFFECTS on/off toggles. Per-player, in-memory for the session (no DataStore).
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
--======================================================================

-- ONE GEAR ONLY. This file was never listed in default.project.json, so for its whole life it could only
-- have been running as a copy baked into the place. Registering it with Rojo (done in the same pass) means
-- a synced copy and any baked-in copy can now both be alive at once -- two gears, two panels, two SFX
-- groups, and the second one to load silently wins every toggle.
--
-- ===== NEWEST BUILD WINS, NOT FIRST LOADER =====
-- This was a plain first-loader-wins claim, which has a nasty failure mode: when a STALE baked-in copy
-- wins the race, the freshly-synced Rojo script returns here and never runs, so changes made in this
-- file have no effect at all and the game silently keeps the old behaviour. (That is exactly what
-- happened with the campfire client -- same pattern, same symptom.) The claim is now VERSIONED: bump
-- SETTINGS_BUILD when behaviour changes and the newest copy always takes over. The old flag is still
-- set, because baked-in copies test it -- that is what makes THEM stand down when we win the race.
local SETTINGS_BUILD = 4   -- 4 = Space Realm's panel LAYOUT in this game's house palette (blue/white/lime/gold)
if (_G.__SettingsMenuClientBuild or 0) >= SETTINGS_BUILD then return end
_G.__SettingsMenuClientBuild = SETTINGS_BUILD
_G.__SettingsMenuClient = true

local Players      = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Workspace    = game:GetService("Workspace")

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
-- UI: gear button (top-left) + settings panel.
--======================================================================
-- CLEAR ANY STALE SettingsGui FIRST. If a baked-in copy of this script won the load race it has already
-- built its own gear and panel; ours would then be the SECOND, and TokenHud (which adopts "the" gear
-- into the currency row) can just as easily pick theirs -- leaving the player using an old panel with no
-- Glitter Trail row on it. Ours is stamped BuiltByLiveScript so this can tell them apart; repeated
-- shortly after, because a stale copy that loads AFTER us is only reachable once it has built itself.
local function nukeStaleSettingsUi()
	local removed = 0
	for _, inst in ipairs(PlayerGui:GetChildren()) do
		if inst:IsA("ScreenGui") and (inst.Name == "SettingsGui" or inst.Name == "SettingsPanelGui")
			and not inst:GetAttribute("BuiltByLiveScript") then
			pcall(function() inst:Destroy() end); removed = removed + 1
		end
	end
	if removed > 0 then
		warn("[Settings] cleared " .. removed .. " STALE SettingsGui copy/copies baked into the place. "
			.. "Delete the duplicate SettingsMenu LocalScripts in Studio for good.")
	end
end
nukeStaleSettingsUi()

local sg = Instance.new("ScreenGui")
-- IgnoreGuiInset matches the coin counter's CoinGui (also IgnoreGuiInset=true) so the gear's Y lines up
-- exactly with the coins (same coordinate origin at the very top of the screen).
sg.Name = "SettingsGui"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true; sg.DisplayOrder = 60; sg.Parent = PlayerGui
sg:SetAttribute("BuiltByLiveScript", true)   -- the stamp nukeStaleSettingsUi() recognises as "ours"
task.delay(2, nukeStaleSettingsUi); task.delay(6, nukeStaleSettingsUi)
print(("[Settings] build %d ACTIVE (this is the Rojo copy)"):format(SETTINGS_BUILD))

-- Gear button — sits in the TOP-RIGHT area, immediately to the LEFT of the coin counter. Its exact
-- size/position are set relative to the coin pill (see placeNextToCoins at the bottom) so it tucks in
-- beside the coins on every screen size. The values here are a sensible top-right FALLBACK used only if
-- the coin pill can't be found.
-- SPACE REALM GEAR. Same button as SpaceRealm_SettingsButton/01_button_gear -- dark navy fill, corner 12,
-- white-blue glyph, a gloss sheen over the top half and a cyan->blue neon border. The exact values are
-- lifted from SpaceTheme.luau (StarfieldFill 12,16,42 / TextPrimary 230,238,255 / NeonCyan 64,224,255),
-- rebuilt inline rather than by pulling SpaceTheme in: this button is the only thing here that would use
-- it, and the module drags along starfields, planet tints and panel-depth helpers this game has no use for.
--
-- TWO DIFFERENCES FROM THE SNIPPET, both deliberate:
--   * the snippet adds addNeonEdge (a UIStroke) AND a second black UIStroke for glyph crispness. A
--     GuiObject only honours ONE UIStroke, so the second was doing nothing. The neon edge is the border,
--     and the glyph gets its outline from the button's own TextStroke, which does not collide.
--   * no fixed 44x44 / top-right position: size and position come from the coin pill below, so the gear
--     matches the coins' row height on every device.
local gearBtn = Instance.new("TextButton")
gearBtn.Name = "SettingsGearBtn"
gearBtn.AnchorPoint = Vector2.new(1, 0)
gearBtn.Size = UDim2.new(0, 46, 0, 46)
-- NOTE: this x offset is only the FIRST-FRAME position. TokenHud.client.luau owns the top-right
-- row layout ([token pill] gap [gear] gap [coin pill]) and re-places this button from the coin
-- pill's MEASURED left edge twice a second -- the hand-tuned -198 here was right for one viewport
-- and overlapped the coin pill (and its sale badge) on others, which is why the layouter exists.
gearBtn.Position = UDim2.new(1, -198, 0, 10)
gearBtn.BackgroundColor3 = Color3.fromRGB(12, 16, 42)   -- SpaceTheme.StarfieldFill
gearBtn.Text = "\xE2\x9A\x99"                          -- U+2699 with NO variation selector, so it renders as
gearBtn.TextScaled = true                               -- a TINTED glyph instead of the fixed-colour emoji
gearBtn.Font = Enum.Font.GothamBold
gearBtn.TextColor3 = Color3.fromRGB(230, 238, 255)      -- SpaceTheme.TextPrimary
gearBtn.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)      -- crisp glyph (the snippet's dead 2nd UIStroke, done properly)
gearBtn.TextStrokeTransparency = 0.35
gearBtn.AutoButtonColor = true
gearBtn.ZIndex = 20
gearBtn.Parent = sg
do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,12); c.Parent=gearBtn end
-- GLOSS: white sheen over the top 52%, fading out downward (SpaceTheme.addGloss). Not Active, so it never
-- eats the click meant for the button underneath it.
do
	local hi=Instance.new("Frame"); hi.Name="Gloss"; hi.BackgroundColor3=Color3.fromRGB(255,255,255)
	hi.BorderSizePixel=0; hi.Position=UDim2.fromScale(0,0); hi.Size=UDim2.new(1,0,0.52,0); hi.ZIndex=gearBtn.ZIndex
	local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,12); c.Parent=hi
	local g=Instance.new("UIGradient"); g.Rotation=90
	g.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.8), NumberSequenceKeypoint.new(1,1)})
	g.Parent=hi; hi.Parent=gearBtn
end
-- NEON EDGE: cyan -> blue gradient border (SpaceTheme.addNeonEdge).
do
	local s=Instance.new("UIStroke"); s.Thickness=2; s.Color=Color3.fromRGB(255,255,255)
	s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
	local g=Instance.new("UIGradient"); g.Rotation=90
	g.Color=ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(120,235,255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(64,224,255)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(56,120,255)),
	})
	g.Parent=s; s.Parent=gearBtn
end
do local p=Instance.new("UIPadding"); p.PaddingTop=UDim.new(0,5); p.PaddingBottom=UDim.new(0,5); p.PaddingLeft=UDim.new(0,5); p.PaddingRight=UDim.new(0,5); p.Parent=gearBtn end

--======================================================================
-- THE PANEL -- SPACE REALM'S LAYOUT, THIS REALM'S COLOURS.
--======================================================================
-- The structure is copied from Space Realm (SettingsClient.client.luau / cross-place/SETTINGS_HANDOFF.md):
-- a centred card with a gloss sheen, a gold "(gear) SETTINGS" header, a red close button, and the rows in a
-- ScrollingFrame so they always fit and scroll on phones. Every measurement is Space Realm's authored value:
--   panel 360x470, corner 20, depth glow 9 / shadow 6 / drop 6
--   title 32 tall at (18,14), max text 28 -- close 38x38 at (-12,12), corner 10, max 22
--   rows inset 16, top 64, 12px gaps -- toggle rows 56 tall, track 72x32 corner 16, knob 26x26
--   selector value pill 134x34 corner 10, "< Option >" -- credits block 110 tall, text 15
--
-- The COLOURS are this game's, not Space Realm's -- see the palette below.
--
-- The SpaceTheme helpers it needed (addPanelDepth / addGloss / addTextGloss) are inlined below rather than
-- required: that module lives in Space Realm and drags along planet tints and starfields this game has no
-- use for. The gear above already inlines its two helpers the same way.
--
-- THREE DELIBERATE DIFFERENCES FROM THE SPACE REALM FILE:
--   * THIS REALM'S COLOURS, not Space Realm's. The layout above is copied exactly; the palette is Fart to
--     Float's house one -- bright blue panel, thick white border, lime/gold accents. Space Realm's near-black
--     navy + starfield + cyan neon belong to that game and read dark and casino-ish next to this game's Shop
--     and Pet Hub, so they're gone: no starfield, no neon edge, no 10,14,34 rows.
--   * the backdrop does NOT close the panel (X only) -- a stray tap must never shut a menu in this game.
--   * no GetSettings/SaveSetting remotes here, so choices are per-session (Space Realm persists via
--     PlayerState).
--
-- HOUSE PALETTE -- the same colours the Daily Rewards crate reveal defines in CrateClient.client.luau
-- (`local C`), so this panel sits next to the Shop / Pet Hub / crate without looking like another game's UI.
local C = {
	panel   = Color3.fromRGB( 26,  79, 214),  -- #1a4fd6 panel gradient TOP
	panelDk = Color3.fromRGB( 14,  59, 176),  -- #0e3bb0 panel gradient BOTTOM
	row     = Color3.fromRGB( 47, 111, 224),  -- #2f6fe0 row body
	rowEdge = Color3.fromRGB( 18,  56, 150),  -- darker row edge
	navy    = Color3.fromRGB( 12,  34,  86),  -- recessed wells (the OFF switch track)
	line    = Color3.fromRGB(120, 170, 250),  -- light-blue inner line
	muted   = Color3.fromRGB(214, 232, 252),
	gold    = Color3.fromRGB(255, 210,  74),  -- #ffd24a treasure/title
	lime    = Color3.fromRGB(126, 217,  87),  -- #7ed957 good news -> the ON switch
	shadow  = Color3.fromRGB(  6,  26,  80),  -- NAVY shadow, never black
	red     = Color3.fromRGB(224,  72,  72),  -- close button
}
local WHITE   = Color3.new(1, 1, 1)
local ON_LIME = C.lime
local OFF_DIM = Color3.fromRGB(90, 116, 168) -- muted blue-gray, still clearly part of the blue panel

local TweenService = game:GetService("TweenService")

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
-- SpaceTheme.addGloss: white sheen over the top 52%, fading down. ZIndex 0 = above the fill, below content.
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
-- HOUSE PANEL FILL: the blue top->bottom gradient every panel in this game uses (replaces Space Realm's
-- flat near-black navy + starfield). Same call site as addStarfield was, so the layout is untouched.
local function addPanelGradient(frame)
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.panel),
		ColorSequenceKeypoint.new(1, C.panelDk),
	})
	g.Parent = frame
	return g
end
-- HOUSE BORDER: a THICK WHITE outline (replaces Space Realm's cyan neon gradient edge). This is the single
-- most recognisable part of the look -- every panel in this game is a blue card with a fat white rim.
local function addWhiteBorder(frame, thickness)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 4
	s.Color = WHITE
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = frame
	return s
end
-- Title sheen: gold -> deeper gold, the treasure look the crate + shop headers use (was white -> pale blue).
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
-- SpaceTheme.addPanelDepth: a soft blue outer glow + a drop shadow, both SIBLINGS behind the panel, so the
-- card reads as floating. Needs the host ScreenGui on ZIndexBehavior.Sibling (set below) for the negative Z.
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
	-- NAVY shadow, never black (house rule), and the halo is the light-blue inner line colour so it reads as
	-- a soft rim on a blue card instead of Space Realm's glow.
	local shadow = layer(p.Name .. "Shadow", opts.shadowSpread or 5, opts.shadowDrop or 5, C.shadow, 0.4, baseZ - 2)
	local glow   = layer(p.Name .. "Glow",   opts.glowSpread   or 7, 0, opts.glowColor or C.line, 0.7, baseZ - 1)
	return glow, shadow
end

-- Its own ScreenGui (Space Realm does the same): DisplayOrder 200 so the card always overlays the HUD and
-- the shop, and Enabled=false is the closed state -- nothing of it renders or takes input while shut.
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
-- the X is the only way out. MenuBackdropGuard leaves this alone: the card behind it is a real panel, and
-- while the menu is shut the whole ScreenGui is disabled.
local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundTransparency = 1 -- click-catcher only; panels draw with no dim over the world
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.ZIndex = 1
backdrop.Parent = panelGui

local panel = Instance.new("Frame")
panel.Name = "SettingsPanel"
panel.Active = true -- sink clicks so tapping the card's chrome doesn't fall through to the backdrop
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 360, 0, 470)
panel.BackgroundColor3 = C.panel
panel.ZIndex = 2
panel.Parent = backdrop
corner(panel, 20)
addPanelDepth(panel, { corner = 20, glowSpread = 9, shadowSpread = 6, shadowDrop = 6 })
addPanelGradient(panel)   -- house blue gradient (was the starfield)
addGloss(panel, 20)
addWhiteBorder(panel, 4)  -- thick white rim (was the cyan neon edge)

-- Title: gear glyph + "SETTINGS", glossy gold.
local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
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

-- Close: a RED button with a plain WHITE "X" on it, top-right.
-- The letter X, not the U+2715 multiplication glyph Space Realm used -- that glyph renders as a thin,
-- washed-out mark (and falls back to a box in fonts that don't carry it). A capital X in FredokaOne is
-- the fat, unmistakable white X every other close button in this game shows.
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -12, 0, 12)
closeBtn.Size = UDim2.new(0, 38, 0, 38)
closeBtn.BackgroundColor3 = C.red
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.FredokaOne
closeBtn.TextScaled = true
closeBtn.TextColor3 = WHITE            -- white X
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

-- A labeled ON/OFF switch row: glossy pill track (green=on, gray=off) with a sliding white knob and an
-- ON/OFF caption on the opposite side from the knob. The whole track is the button.
-- Returns (row, repaint) -- the row so a caller can hide it (Glitter Trail is owner-only).
local function makeToggleRow(order, labelText, getState, onChanged)
	local row = Instance.new("Frame")
	row.Name = labelText .. "Row"
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 56)
	row.BackgroundColor3 = C.row          -- house row blue (was Space Realm's near-black 10,14,34)
	row.BackgroundTransparency = 0
	row.ZIndex = 3
	row.Parent = rows
	corner(row, 12)
	stroke(row, C.line, 1.5)              -- light-blue inner line, the house row edge

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
			TweenService:Create(track, ti, { BackgroundColor3 = on and ON_LIME or OFF_DIM }):Play()
			TweenService:Create(knob, ti, { Position = knobPos }):Play()
		else
			track.BackgroundColor3 = on and ON_LIME or OFF_DIM
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
	row.BackgroundColor3 = C.row          -- house row blue (was Space Realm's near-black 10,14,34)
	row.BackgroundTransparency = 0
	row.ZIndex = 3
	row.Parent = rows
	corner(row, 12)
	stroke(row, C.line, 1.5)              -- light-blue inner line, the house row edge

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
	valueBtn.BackgroundColor3 = C.panelDk
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

-- GRAPHICS -- Quality / Performance, same row Space Realm ships. "auto" resolves to Performance on phones
-- (PhoneHUD.isPhone(), the same detector ResponsiveUI uses). The choice is published as the LocalPlayer
-- attribute "PerformanceMode" and _G.performanceMode -- Space Realm's CosmeticLOD + SkyFX read that live.
-- NOTE: nothing in THIS game reads it yet, so today the row remembers the choice and nothing thins out;
-- point any FX/LOD script at the attribute and it starts working with no change here.
local perfPref = "auto"   -- "auto" | "quality" | "performance"
-- Resolved ONCE, without yielding: this runs while the panel is being built, and a WaitForChild here would
-- stall the whole build if PhoneHUD were ever missing. If it can't be read we just say "not a phone".
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

-- REMOVED: Colorblind mode and the Glitter Trail toggle.
--
-- Colorblind stored a "ColorblindMode" attribute that NOTHING in this game ever read -- it was carried over
-- from Space Realm, whose ColorblindClient recolors its cues off that attribute. A control that visibly does
-- nothing is worse than no control: it reads as broken to the players who most need it to work.
--
-- Glitter Trail was a gamepass switch that only appeared for owners; the pass now simply applies its trail.
-- CoreClient still reads _G.glitterTrailOn, which is left unset here -- so it falls to the same default any
-- non-owner has always had, and nothing has to change there.

-- CREDITS / VERSION (read-only) -- Space Realm pulls these from its Version module; this game has none, so
-- the same four lines live here. Bump VERSION when you release.
local CREDITS_GAME    = "Fart to Float"
local CREDITS_DEVS    = "Made by lando5485, Broskie310111 & itsmaddmax2"
local CREDITS_VERSION = "v1.0.0"
local CREDITS_THANKS  = "Thank you for playing! \xF0\x9F\x92\x99"
local credits = Instance.new("TextLabel")
credits.Name = "Credits"
credits.LayoutOrder = 6
credits.Size = UDim2.new(1, 0, 0, 110)
credits.BackgroundColor3 = C.panelDk
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
stroke(credits, C.line, 1.5)
do local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10); pad.Parent = credits end
maxText(credits, 16)

-- Publish the Graphics attribute immediately, so anything that starts reading it has a value from the first
-- frame rather than nil. (applyColorblind used to be called here too; it went with the Colorblind row.)
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

-- Apply the initial state (both ON by default -> no audible change; ensures the group/flag are set).
applySFX()
applyMusic()

--======================================================================
-- Position the gear immediately to the LEFT of the coin counter, IDENTICALLY on PC and mobile, on the
-- SAME ROW as the coins. Two axes, two strategies:
--   * VERTICAL: copy the coin pill's exact AnchorPoint.Y + Position.Y (scale & offset). Both this gear's
--     ScreenGui and the CoinGui are IgnoreGuiInset=true (same Y origin at the top of the safe area), so
--     copying the coin's vertical PROPERTY guarantees the gear is at the coins' exact height on every
--     device — and respects the mobile top-bar inset, because the coins do. We use the property (a stable
--     value, set the instant the pill is created) rather than AbsolutePosition.Y, which can be a transient
--     0 during an early layout pass and would otherwise shove the gear up under the top bar.
--   * HORIZONTAL: sit just left of the coins' real rendered left edge (AbsolutePosition.X / AbsoluteSize),
--     so the gap is correct whatever the device width / UI scale.
-- Re-applied whenever the coins move/resize. We never modify the coin pill — only read it.
--======================================================================
task.spawn(function()
	local coinGui = PlayerGui:WaitForChild("CoinGui", 20)
	if not coinGui then return end -- keep the top-right fallback position
	local coinPill
	local deadline = os.clock() + 20
	repeat
		coinPill = coinGui:FindFirstChildOfClass("Frame") -- the coin pill is the only direct Frame child
		if not coinPill then task.wait(0.1) end
	until coinPill or os.clock() > deadline
	if not coinPill then return end -- keep the top-right fallback position
	-- A COUPLE OF PIXELS between the gear and the coins -- close enough to read as one cluster rather than
	-- two unrelated widgets, without the rounded corners touching.
	local GAP = 4
	local function place()
		local cSize = coinPill.AbsoluteSize       -- coins' rendered size, in real screen pixels
		if cSize.X <= 0 or cSize.Y <= 0 then return end -- not rendered yet; listeners re-run once it is
		local cLeft = coinPill.AbsolutePosition.X -- coins' rendered LEFT edge, in real screen pixels
		local gearW = cSize.Y                     -- square, matching the coins' rendered height (one row)
		local coinPosY    = coinPill.Position.Y   -- coins' vertical position PROPERTY (scale + offset)
		local coinAnchorY = coinPill.AnchorPoint.Y
		-- GEAR PLACEMENT REMOVED -- TokenHud.client.luau owns the whole top-right row now
		-- ([ticket pill] gap [gear] gap [coins], right-aligned to the STATS panel). This block used to
		-- place the gear too, driven off the coin pill's AbsolutePosition. The moment TokenHud started
		-- positioning the coin pill, that listener fired and stamped the gear back to ITS coordinates --
		-- the row snapped into place and jumped back a moment later, every time. Two writers on one
		-- element is the bug; the fix is one owner. `gearW` is still computed above because the panel
		-- width below reads the same measurements.
		gearBtn.Size = UDim2.fromOffset(gearW, cSize.Y)   -- size only: the row layouter measures this
		-- PANEL PLACEMENT IS GONE TOO: the Space Realm card is CENTRED on the screen (AnchorPoint 0.5,0.5
		-- at 0.5,0.5) instead of hanging off the coin pill, so it no longer has anything to track. Only the
		-- gear's size still comes from the coins.
	end
	place()
	-- Re-run whenever the coins move/resize: device/orientation/resize, a HUD refresh that repositions or
	-- resizes the pill (e.g. line ~961 in CoreClient), or simply the first frame it renders.
	coinPill:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
	coinPill:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	coinPill:GetPropertyChangedSignal("Position"):Connect(place)
	coinPill:GetPropertyChangedSignal("AnchorPoint"):Connect(place)
end)
