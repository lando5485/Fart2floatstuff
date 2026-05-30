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
local sg = Instance.new("ScreenGui")
-- IgnoreGuiInset matches the coin counter's CoinGui (also IgnoreGuiInset=true) so the gear's Y lines up
-- exactly with the coins (same coordinate origin at the very top of the screen).
sg.Name = "SettingsGui"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true; sg.DisplayOrder = 60; sg.Parent = PlayerGui

-- Gear button — sits in the TOP-RIGHT area, immediately to the LEFT of the coin counter. Its exact
-- size/position are set relative to the coin pill (see placeNextToCoins at the bottom) so it tucks in
-- beside the coins on every screen size. The values here are a sensible top-right FALLBACK used only if
-- the coin pill can't be found.
local gearBtn = Instance.new("TextButton")
gearBtn.Name = "SettingsGearBtn"
gearBtn.AnchorPoint = Vector2.new(1, 0)
gearBtn.Size = UDim2.new(0, 46, 0, 46)
gearBtn.Position = UDim2.new(1, -198, 0, 10)
gearBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
gearBtn.Text = "\xE2\x9A\x99\xEF\xB8\x8F"  -- gear icon
gearBtn.TextScaled = true
gearBtn.Font = Enum.Font.GothamBold
gearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
gearBtn.ZIndex = 20
gearBtn.Parent = sg
do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,10); c.Parent=gearBtn end
do local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(0,0,0); s.Thickness=2; s.Parent=gearBtn end
do local p=Instance.new("UIPadding"); p.PaddingTop=UDim.new(0,6); p.PaddingBottom=UDim.new(0,6); p.PaddingLeft=UDim.new(0,6); p.PaddingRight=UDim.new(0,6); p.Parent=gearBtn end

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
end

makeToggleRow(46,  "Music",         function() return musicOn end, function(v) musicOn = v; applyMusic() end)
makeToggleRow(96,  "Sound Effects", function() return sfxOn   end, function(v) sfxOn   = v; applySFX()   end)

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
	local GAP = 8
	local function place()
		local cSize = coinPill.AbsoluteSize       -- coins' rendered size, in real screen pixels
		if cSize.X <= 0 or cSize.Y <= 0 then return end -- not rendered yet; listeners re-run once it is
		local cLeft = coinPill.AbsolutePosition.X -- coins' rendered LEFT edge, in real screen pixels
		local gearW = cSize.Y                     -- square, matching the coins' rendered height (one row)
		local coinPosY    = coinPill.Position.Y   -- coins' vertical position PROPERTY (scale + offset)
		local coinAnchorY = coinPill.AnchorPoint.Y
		-- Gear: X = just left of the coins' real left edge (absolute px); Y = the coins' EXACT vertical
		-- anchor + position, so it lands on the coins' row and never above the top-bar inset.
		gearBtn.AnchorPoint = Vector2.new(0, coinAnchorY)
		gearBtn.Size = UDim2.fromOffset(gearW, cSize.Y)
		gearBtn.Position = UDim2.new(0, cLeft - GAP - gearW, coinPosY.Scale, coinPosY.Offset)
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
