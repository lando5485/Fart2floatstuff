-- ===== MOBILE TEXT FIT =====
-- Applies the Pet Hub's text-scaling treatment to EVERY HUD in the game, including the ones that only appear
-- later (treasure chest, crates, shops, popups, banners).
--
-- THE TREATMENT (copied exactly from PetHub_AllInOne's fitText):
--     TextScaled = true, plus a UITextSizeConstraint whose MaxTextSize is the label's AUTHORED TextSize.
--
-- Why that specific pair, and not just TextScaled: TextScaled alone will GROW text to fill its box, so a label
-- authored at 18px can balloon on a big screen and stop matching the rest of the HUD. Pinning the authored size
-- as the MAXIMUM means the label is pixel-identical to before at full size, and shrinks -- instead of spilling
-- out of its frame or getting clipped -- when the box is small. That is the whole problem on phones.
--
-- WHAT IS DELIBERATELY LEFT ALONE (each of these gets WORSE, not better, with TextScaled):
--   * AutomaticSize labels -- the label sizes to the text while the text sizes to the label; the two fight.
--   * Labels that are ALREADY TextScaled -- the author opted in; their real authored size is unknowable here
--     (TextSize is often just the 14 default on those), so pinning it as a max would SHRINK working text.
--   * TextBoxes -- scaling the text while someone is typing in it looks broken.
--   * Tiny/placeholder labels -- several HUDs park a 1x1 label offscreen as a marker.
--   * Anything tagged with the opt-out attribute below.

local Players    = game:GetService("Players")
local player     = Players.LocalPlayer
local playerGui  = player:WaitForChild("PlayerGui")

local SKIP_ATTR = "MTF_Skip"   -- set this attribute on a label to keep this pass off it
local MIN_BOX   = 8            -- px; below this the object is a marker/placeholder, not real text

local touched = 0

local function fit(o)
	if not (o:IsA("TextLabel") or o:IsA("TextButton")) then return end   -- TextBox excluded on purpose
	if o:GetAttribute(SKIP_ATTR) then return end
	if o.TextScaled then return end                                     -- author already opted in; leave it
	if o.AutomaticSize ~= Enum.AutomaticSize.None then return end       -- would fight TextScaled
	if o:FindFirstChildOfClass("UITextSizeConstraint") then return end  -- already fitted (e.g. the Pet Hub)

	local authored = o.TextSize
	if authored <= 0 then return end

	-- Guard against the placeholder labels. AbsoluteSize is 0 until the GUI has laid out, so only skip when we
	-- can actually see a real measurement -- otherwise we would skip every label created this frame.
	local box = o.AbsoluteSize
	if box.X > 0 and box.Y > 0 and (box.X < MIN_BOX or box.Y < MIN_BOX) then return end

	o.TextScaled = true
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = authored        -- never bigger than the design; free to shrink below it
	c.MinTextSize = 1
	c.Parent = o
	touched = touched + 1
end

for _, d in ipairs(playerGui:GetDescendants()) do
	pcall(fit, d)
end
local initial = touched

-- HUDs are built lazily all through the session (the chest, crate reveals, shop panels, event banners), so a
-- one-shot pass would only ever catch whatever existed at boot. defer so the creating script has finished
-- setting TextSize/AutomaticSize before we read them -- DescendantAdded fires on Instance.new, before the
-- properties are assigned.
playerGui.DescendantAdded:Connect(function(d)
	task.defer(function() pcall(fit, d) end)
end)

print(("[MobileTextFit] ready -- %d label(s) fitted at boot, watching for more. TextScaled + UITextSizeConstraint(max = authored size): identical on desktop, shrinks instead of spilling on phones. Set the %s attribute on a label to exempt it.")
	:format(initial, SKIP_ATTR))
