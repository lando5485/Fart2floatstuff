--======================================================================
-- ReturnIsland.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- The "Return to <N>" button. Pairs with ReturnIsland.server.luau -- that script decides WHEN it shows and
-- does the actual teleport; this one only draws it and reports the tap.
--
-- ===== IT SENDS NOTHING BUT "I TAPPED IT" =====
-- No index, no position, no target. The server recomputes where the player has actually got to and moves
-- them itself, so a hacked client spamming this remote achieves nothing except being put back somewhere it
-- had already earned. Do not "optimise" this by passing the island number -- that is the whole exploit.
--
-- ===== PLACEMENT: LEFT EDGE, VERTICALLY CENTRED =====
-- Position (0, 130, 0.5, 0) with AnchorPoint (0, 0.5). That specific spot is not arbitrary -- it is the one
-- part of the screen this game leaves empty:
--   * the LEFT RAIL (shop / stomach / wormhole / more) runs down the left at x < 130, so 130 clears it;
--   * the RIGHT panel (stats + impulse buttons) owns the right edge;
--   * the BOTTOM CENTRE is the gas meter and the fart button;
--   * the TOP CENTRE is the announcement banner lane and the quest/objective cards.
-- Vertically centred is the only large area left, and a mid-height button never covers the middle of the
-- screen because it sits well out to the side.
--
-- If your realm's rails differ, the ONE number to change is X_INSET below. Keep the anchor at (0, 0.5).
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player            = Players.LocalPlayer
local PlayerGui         = player:WaitForChild("PlayerGui")

--======================================================================
-- LOOK / PLACEMENT -- the authored values from the original, unchanged
--======================================================================
-- 130 is correct for THIS realm as authored: JustButtons' rail is 95px wide at x=12, so it ends
-- at 107 and this clears it by 23. Checked, not assumed.
local X_INSET   = 130                            -- px from the left edge; clears the left rail
local W, H      = 180, 56                        -- authored size (a responsive pass scales it from here)
-- CANDY, but deliberately the ONE warm hue on this HUD. The kit shipped it orange on the
-- reasoning that a safety action should not look like a purchase, and that still holds here --
-- the pinks are panels, the gold is the fart button, the lime is the meter. A tangerine sweet is
-- the only thing left that reads as "this is different". White candy-wrapper stroke and navy ink
-- to match the currency capsule and the bottom card; only the hue is its own.
local FILL      = Color3.fromRGB(255, 150,  60)  -- tangerine
local FILL_DEEP = Color3.fromRGB(235, 105,  20)
local EDGE      = Color3.fromRGB(255, 255, 255)  -- the house's thick white candy-wrapper border
local INK       = Color3.fromRGB(  6,  26,  80)  -- house navy for the caption's outline, never black
local TEXT_SIZE = 17
local CORNER    = 14
local STROKE    = 3
local Z         = 8

local ReturnToIslandEvent = ReplicatedStorage:FindFirstChild("ReturnToIslandEvent")
	or ReplicatedStorage:WaitForChild("ReturnToIslandEvent", 30)

local gui = Instance.new("ScreenGui")
gui.Name = "ReturnIslandGui"
gui.ResetOnSpawn = false      -- it must survive the respawn that a long fall usually ends in
gui.IgnoreGuiInset = true     -- so the y=0.5 centring is against the real screen, not the topbar-inset one
gui.DisplayOrder = 8
gui.Parent = PlayerGui

local btn = Instance.new("TextButton")
btn.Name = "ReturnBtn"
btn.AnchorPoint = Vector2.new(0, 0.5)
btn.Position = UDim2.new(0, X_INSET, 0.5, 0)
btn.Size = UDim2.new(0, W, 0, H)
btn.BackgroundColor3 = FILL
btn.BorderSizePixel = 0
btn.Text = ""                 -- the caption is a CHILD label; see below
btn.AutoButtonColor = false
btn.Visible = false           -- the server's attribute is what reveals it; never show it unprompted
btn.ZIndex = Z
btn.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, CORNER); c.Parent = btn
	local s = Instance.new("UIStroke"); s.Color = EDGE; s.Thickness = STROKE; s.Parent = btn
	local g = Instance.new("UIGradient"); g.Rotation = 90   -- lit the same way as the bottom card
	g.Color = ColorSequence.new(FILL, FILL_DEEP); g.Parent = btn
end

-- THE CAPTION IS A SEPARATE LABEL, and it has to be: an instance honours only ONE UIStroke, so
-- the button cannot carry both the white candy-wrapper border AND a navy outline on its own text
-- -- one of the two would silently not apply. The border stays on the button, the text outline
-- goes here. White on tangerine is only ~2.5:1 on its own; the dark outline is what makes the
-- caption legible against a mid-tone fill, so it is doing real work, not decoration.
local caption = Instance.new("TextLabel")
caption.Name = "Caption"
caption.BackgroundTransparency = 1
caption.Size = UDim2.new(1, -12, 1, 0)
caption.Position = UDim2.fromScale(0.5, 0.5)
caption.AnchorPoint = Vector2.new(0.5, 0.5)
caption.Font = Enum.Font.FredokaOne   -- the font the rest of this realm's HUD is set in
caption.TextColor3 = Color3.fromRGB(255, 255, 255)
caption.TextScaled = true
caption.Text = "Return"
caption.ZIndex = Z + 1
caption.Parent = btn
do
	local ts = Instance.new("UIStroke"); ts.Color = INK; ts.Thickness = 2
	ts.LineJoinMode = Enum.LineJoinMode.Round; ts.Parent = caption
	-- TextScaled with a ceiling, not a fixed TextSize. Most HUD scaling passes blanket-force
	-- TextScaled = true on every label they own, which IGNORES TextSize and inflates the caption to fill
	-- the button. A UITextSizeConstraint is the only thing that holds it at the authored size.
	local t = Instance.new("UITextSizeConstraint"); t.MaxTextSize = TEXT_SIZE; t.Parent = caption
end

--======================================================================
-- VISIBILITY -- driven entirely by the server's attribute
--======================================================================
-- ReturnPromptIsland = the anchor index to offer, or 0 for "hide". The client never decides this: only the
-- server knows how far the player actually got, and only the server can see whether the anchor exists.
local function refresh()
	local n = tonumber(player:GetAttribute("ReturnPromptIsland")) or 0
	if n > 0 then
		caption.Text = "\xE2\xAC\x86 Return to Island " .. n   -- U+2B06 up arrow
		btn.Visible = true
	else
		btn.Visible = false
	end
end

player:GetAttributeChangedSignal("ReturnPromptIsland"):Connect(refresh)
refresh()

if ReturnToIslandEvent then
	btn.MouseButton1Click:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		-- hide on tap: the teleport takes a moment to land, and a button still sitting there invites a
		-- second tap that does nothing. The server clears the attribute too, which is what makes it stick.
		btn.Visible = false
		pcall(function() ReturnToIslandEvent:FireServer() end)
	end)
else
	warn("[Return] ReturnToIslandEvent missing -- is ReturnIsland.server.luau in ServerScriptService?")
end

print("[Return] button ready -- left edge, vertically centred. The SERVER decides when it shows "
	.. "(ReturnIsland.server.luau sets the ReturnPromptIsland attribute); this script only draws it.")
