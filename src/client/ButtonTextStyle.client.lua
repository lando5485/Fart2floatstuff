--======================================================================
-- BUTTON LABEL LEGIBILITY  (LocalScript, per-player)
--======================================================================
-- ONE TREATMENT FOR EVERY BUTTON LABEL IN THE GAME.
--
-- The problem this fixes, exactly as it looked on "HOLD TO PULL": near-white text sitting on a bright green
-- fill, wearing a thick BLACK stroke. Three separate mistakes stacking up --
--
--   * white-on-bright-green is barely any contrast to begin with,
--   * a black stroke against a green fill is a colour that appears nowhere else in the button, so it reads as
--     dirt rather than as an edge, and
--   * at 3-4px that stroke grows inward far enough to close up the counters (the holes in a, e, o) and
--     thicken the stems, so the letterforms themselves stop being readable.
--
-- The fix is applied HERE, in one place, rather than at each of the ~30 files that build buttons. Those files
-- would drift apart within a week, and half of them are shadowed by stale baked-in copies that cannot be
-- edited from Rojo at all -- but they all end up as GuiObjects under PlayerGui, so styling them from the
-- outside catches every one, including the copies.
--
-- ===== THE RULES =====
--   TEXT     soft cream, not pure white -- takes the glare off and lets the stroke define the edge
--   STROKE   thickness 2, coloured a DARK SHADE OF THE BUTTON'S OWN FILL. A dark green edge on a green
--            button reads as shadow; a black one reads as grime.
--   FILL     darkened, so light text has somewhere to sit
--   GRADIENT flipped/darkened when its light end is behind the text
--   SHADOWS  duplicate offset labels deleted -- the stroke does that job now, and two labels 1px apart is
--            what makes text look smeared when the UI scales
--
-- ===== WHY IT RE-APPLIES =====
-- Several scripts here restyle GUIs after the fact (CoreClient's dark-element sweep, RailGuard's rebuilds,
-- the crate and shop builders). A one-shot pass at startup would be undone by whichever of them ran last, so
-- this re-sweeps on a slow timer and on DescendantAdded.
--
-- ===== WHY THE ORIGINAL FILL IS REMEMBERED =====
-- Darkening is not idempotent: run it twice and the button is black. So the FIRST time a button is seen its
-- untouched fill is stored on it, and every later pass recomputes from that stored value rather than from
-- whatever is on screen now. Re-running this a thousand times leaves the button exactly as it was after the
-- first pass.
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local player     = Players.LocalPlayer
local playerGui  = player:WaitForChild("PlayerGui")

-- ===== PALETTE / TUNING =====
local CREAM        = Color3.fromRGB(255, 244, 224) -- label colour: warm off-white, never pure #FFF
local STROKE_THICK = 2                             -- was 3-4 and eating the letterforms
local STROKE_MIX   = 0.34                          -- stroke = fill darkened to 34% -- a shade OF the button
local FILL_MIX     = 0.78                          -- fill darkened to 78% of its original brightness
local MIN_TEXT     = 8                             -- ignore decorative micro-text
local RESWEEP      = 3                             -- seconds between full re-sweeps

local ORIG_ATTR    = "BTS_OrigFill"  -- remembers the untouched fill so darkening stays idempotent
local DONE_ATTR    = "BTS_Styled"    -- marks labels we have already de-duplicated

-- Multiply toward black. Straight multiplication (not a Lerp to black) keeps the hue and just drops the
-- value, which is what makes the result read as "the same colour, in shadow".
local function darken(c, f)
	return Color3.new(c.R * f, c.G * f, c.B * f)
end

local function luminance(c)
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

-- The fill a button STARTED with, remembered on first sight. Everything else is derived from this, so the
-- treatment can be re-applied forever without the button creeping darker each time.
local function originalFill(btn)
	local stored = btn:GetAttribute(ORIG_ATTR)
	if typeof(stored) == "Color3" then return stored end
	btn:SetAttribute(ORIG_ATTR, btn.BackgroundColor3)
	return btn.BackgroundColor3
end

-- A FAKE DROP SHADOW is a second label saying the same thing, nudged a pixel or two behind the real one.
-- It was a reasonable trick at a fixed resolution; with the HUD's UIScale it slides out of alignment and the
-- text looks doubled. The stroke replaces it.
local function killShadowTwins(holder, keep)
	if keep.Text == "" then return end
	for _, sib in ipairs(holder:GetChildren()) do
		if sib ~= keep and sib:IsA("TextLabel") and sib.Text == keep.Text then
			-- same words, sat behind, and dark: that is a shadow, not a second piece of information
			local behind = sib.ZIndex <= keep.ZIndex
			local dark   = luminance(sib.TextColor3) < 0.4
			if behind and dark then sib:Destroy() end
		end
	end
end

-- A gradient whose LIGHT end sits under the text is the other half of the legibility problem: the label is
-- readable at one end of the button and gone at the other. Rotating is risky (it is someone's deliberate
-- sheen), so instead the gradient is compressed toward its dark end -- the sheen survives, the contrast
-- under the text does not disappear.
local function tameGradient(btn)
	local grad = btn:FindFirstChildOfClass("UIGradient")
	if not grad then return end
	local seq = grad.Color.Keypoints
	local lightest, idx = -1, nil
	for i, kp in ipairs(seq) do
		local l = luminance(kp.Value)
		if l > lightest then lightest, idx = l, i end
	end
	if not idx or lightest < 0.62 then return end -- nothing bright enough to wash the text out
	local rebuilt = {}
	for i, kp in ipairs(seq) do
		local v = kp.Value
		if i == idx then v = darken(v, 0.74) end -- pull the bright end down toward the rest
		rebuilt[#rebuilt + 1] = ColorSequenceKeypoint.new(kp.Time, v)
	end
	local ok = pcall(function() grad.Color = ColorSequence.new(rebuilt) end)
	if not ok then grad.Color = ColorSequence.new(darken(seq[1].Value, 0.8)) end
end

-- Style ONE label against the fill of the button it belongs to.
local function styleLabel(label, fill)
	label.TextColor3 = CREAM

	local stroke = label:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = label
	end
	stroke.Thickness    = STROKE_THICK
	stroke.Color        = darken(fill, STROKE_MIX)
	stroke.Transparency = 0
	-- Contextual joins round the corners where strokes meet, which is what stops a heavy stroke from
	-- spiking out of the tight angles in A, W and M.
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
end

-- Should this button be touched at all? Text-free buttons are icons and rails -- restyling those would flatten
-- deliberate art for no legibility gain.
local function textOf(btn)
	if btn:IsA("TextButton") and btn.Text ~= "" then return btn end
	for _, d in ipairs(btn:GetChildren()) do
		if d:IsA("TextLabel") and d.Text ~= "" and d.TextSize >= MIN_TEXT then return d end
	end
	return nil
end

local SKIP_ATTR = "BTS_Skip" -- opt-out: "this button drives its own fill, keep out"

local function styleButton(btn)
	if not (btn:IsA("TextButton") or btn:IsA("ImageButton")) then return end
	-- SOME BUTTONS USE THEIR FILL TO MEAN SOMETHING. The campfire's Roast/Stop/Eat go grey when the action is
	-- illegal, and that greying IS the feature -- it is how a button that cannot work is made to look like it
	-- cannot work. This sweep re-asserting a remembered "original" colour every 3 seconds would repaint them
	-- live again a moment after they greyed, so a dead button would look pressable. Worse than ugly text.
	if btn:GetAttribute(SKIP_ATTR) then return end
	if btn.BackgroundTransparency > 0.5 then return end -- see-through button: no fill to contrast against
	local label = textOf(btn)
	if not label then return end

	local fill = originalFill(btn)
	btn.BackgroundColor3 = darken(fill, FILL_MIX)
	tameGradient(btn)

	-- the button's own text (TextButton) and any caption labels inside it get the identical treatment
	if btn:IsA("TextButton") and btn.Text ~= "" then styleLabel(btn, fill) end
	for _, d in ipairs(btn:GetChildren()) do
		if d:IsA("TextLabel") and d.Text ~= "" and d.TextSize >= MIN_TEXT then
			styleLabel(d, fill)
			if not d:GetAttribute(DONE_ATTR) then
				d:SetAttribute(DONE_ATTR, true)
				killShadowTwins(btn, d)
			end
		end
	end
end

local function sweep()
	for _, d in ipairs(playerGui:GetDescendants()) do
		pcall(styleButton, d)
	end
end

-- New GUIs appear constantly (crate reveals, shop panels, minigame cards). Style them as they arrive rather
-- than waiting up to RESWEEP seconds for the timer.
playerGui.DescendantAdded:Connect(function(d)
	task.defer(function() pcall(styleButton, d) end)
end)

task.spawn(function()
	while true do
		pcall(sweep)
		task.wait(RESWEEP)
	end
end)

print("[BtnText] label legibility pass active -- cream text, 2px tinted stroke, darkened fills, no twin shadows")
