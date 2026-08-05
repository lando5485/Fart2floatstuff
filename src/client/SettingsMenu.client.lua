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
local SETTINGS_BUILD = 2   -- 2 = adds the owner-only Glitter Trail toggle
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
		if inst:IsA("ScreenGui") and inst.Name == "SettingsGui" and not inst:GetAttribute("BuiltByLiveScript") then
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

-- Panel (hidden until the gear is clicked); opens just below the gear, right-aligned to the coins (its
-- exact position is set relative to the coin pill in placeNextToCoins). Fallback values here.
local panel = Instance.new("Frame")
panel.Name = "SettingsPanel"
panel.Size = UDim2.new(0, 260, 0, 150)
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -10, 0, 64)
panel.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
panel.BorderSizePixel = 0
panel.Visible = false
panel.ZIndex = 20
panel.Parent = sg
do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,12); c.Parent=panel end
do local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(255,255,255); s.Thickness=2; s.Parent=panel end

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -54, 0, 34); title.Position = UDim2.new(0, 12, 0, 6); title.BackgroundTransparency = 1
title.Text = "Settings"; title.Font = Enum.Font.GothamBold; title.TextSize = 20; title.TextColor3 = Color3.fromRGB(255,255,255)
title.TextXAlignment = Enum.TextXAlignment.Left; title.ZIndex = 21; title.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30); closeBtn.Position = UDim2.new(1, -38, 0, 8); closeBtn.AnchorPoint = Vector2.new(0, 0)
closeBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60); closeBtn.Text = "X"; closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextScaled = true; closeBtn.TextColor3 = Color3.fromRGB(255,255,255); closeBtn.ZIndex = 21; closeBtn.Parent = panel
do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=closeBtn end

-- Build one labeled ON/OFF toggle row. getOn() reads current state; setOn(v) applies it.
-- Returns the row so a caller can show/hide it (the Glitter row is owner-only).
local function makeToggleRow(yOff, labelText, getOn, setOn)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -24, 0, 40); row.Position = UDim2.new(0, 12, 0, yOff); row.BackgroundTransparency = 1
	row.ZIndex = 21; row.Parent = panel
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -90, 1, 0); lbl.Position = UDim2.new(0, 0, 0, 0); lbl.BackgroundTransparency = 1
	lbl.Text = labelText; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 16; lbl.TextColor3 = Color3.fromRGB(235,235,245)
	lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 21; lbl.Parent = row
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 76, 0, 30); btn.Position = UDim2.new(1, -76, 0.5, 0); btn.AnchorPoint = Vector2.new(0, 0.5)
	btn.Font = Enum.Font.GothamBold; btn.TextSize = 15; btn.TextColor3 = Color3.fromRGB(255,255,255); btn.ZIndex = 21; btn.Parent = row
	do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=btn end
	local function refresh()
		local on = getOn()
		btn.Text = on and "ON" or "OFF"
		btn.BackgroundColor3 = on and Color3.fromRGB(50, 190, 70) or Color3.fromRGB(120, 120, 130)
	end
	btn.MouseButton1Click:Connect(function()
		setOn(not getOn())
		refresh()
	end)
	refresh()
	return row, refresh
end

makeToggleRow(46,  "Music",         function() return musicOn end, function(v) musicOn = v; applyMusic() end)
makeToggleRow(96,  "Sound Effects", function() return sfxOn   end, function(v) sfxOn   = v; applySFX()   end)

-- ===== GLITTER FART TRAIL (owners only) =====
-- The gamepass used to force its look on anyone who owned it, with no way back to the default trail --
-- and the game's creator owns every pass automatically, so they could never see their own default trail.
-- The pass now UNLOCKS this switch instead of equipping itself: default OFF, and the row only exists for
-- owners so it never advertises itself to players who cannot use it. CoreClient reads _G.glitterTrailOn.
do
	local glitterRow, refreshGlitter = makeToggleRow(146, "Glitter Trail",
		function() return _G.glitterTrailOn == true end,
		function(v) _G.glitterTrailOn = v and true or false end)
	glitterRow.Visible = false
	-- The gamepass flag arrives from the server a moment after join (GamepassEvent), and can change mid-
	-- session on a live purchase -- so poll rather than read once. Cheap: one table lookup a second.
	task.spawn(function()
		while true do
			local gp = _G.playerGamepasses
			local owns = (gp ~= nil) and gp.glitterTrail == true
			if glitterRow.Visible ~= owns then
				glitterRow.Visible = owns
				-- the panel is 150 tall for two rows; owners get a third, so it grows to fit
				panel.Size = UDim2.new(0, 260, 0, owns and 200 or 150)
				if owns then refreshGlitter() end
			end
			task.wait(1)
		end
	end)
end

-- Open/close.
gearBtn.MouseButton1Click:Connect(function()
	if _G.playUIClick then pcall(_G.playUIClick) end
	panel.Visible = not panel.Visible
end)
closeBtn.MouseButton1Click:Connect(function()
	if _G.playUIClick then pcall(_G.playUIClick) end
	panel.Visible = false
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
		-- Panel: opens just below the coin/gear row, right edge aligned with the coins' right edge.
		panel.AnchorPoint = Vector2.new(0, coinAnchorY)
		panel.Position = UDim2.new(0, (cLeft + cSize.X) - panel.Size.X.Offset, coinPosY.Scale, coinPosY.Offset + cSize.Y + 6)
	end
	place()
	-- Re-run whenever the coins move/resize: device/orientation/resize, a HUD refresh that repositions or
	-- resizes the pill (e.g. line ~961 in CoreClient), or simply the first frame it renders.
	coinPill:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
	coinPill:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	coinPill:GetPropertyChangedSignal("Position"):Connect(place)
	coinPill:GetPropertyChangedSignal("AnchorPoint"):Connect(place)
end)
