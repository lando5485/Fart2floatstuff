--======================================================================
-- BackButtonKit.client.luau  (StarterPlayerScripts)  -- CandyRealm
--======================================================================
-- ONE shared "BACK" button, styled exactly as realm 1's (SkinCrateClient's crate-panel header):
--     70x30, corner 8, WHITE stroke 1.5, "BACK" in FredokaOne, TextScaled, max text size 14
-- placed directly to the LEFT of a panel's own close X.
--
-- ===== WHY A HELPER AND NOT FIVE HAND-PLACED BUTTONS =====
-- The panels that need one (Rebirth, Wormhole, Send a Gift, and the Rewards destinations) each park their
-- X differently -- AnchorPoint (1,0) vs (1,0.5) vs unset, sizes 36/40/44, insets -12/-18/-54. Hard-coding
-- five positions means five chances to be a few pixels out, and five things to re-fix if a header moves.
-- This DERIVES its position from the X it is given, so it lands correctly on all of them and stays correct
-- if one of those headers is ever re-laid-out.
--
-- ===== WHAT "BACK" MEANS HERE =====
-- Realm 1's rule, kept: BACK and CLOSE are DIFFERENT actions. BACK returns you to the menu you came from;
-- X shuts the panel. All four of these panels are opened from the MORE+ menu, so BACK closes the panel and
-- reopens MORE+ -- the same shape as realm 1's crate panel closing itself and firing PetInvToggle to
-- reopen the Pet Hub.
--
-- USAGE (from any client script, after its close button exists):
--     _G.addBackButton(closeBtn, function() ... end)   -- custom action
--     _G.addBackButton(closeBtn)                       -- defaults to "close panel, reopen MORE+"
--======================================================================

local BACK_W, BACK_H = 70, 30
local GAP = 8   -- px between the BACK button's right edge and the X's left edge

-- Close the panel this button lives in, then reopen the MORE+ menu it was opened from.
-- Finding the panel by walking up to the ScreenGui keeps the helper independent of how each script names
-- its frames; hiding the ScreenGui is what every one of these panels' own X ends up doing anyway.
local function defaultBack(btn)
	local node = btn
	while node and not node:IsA("ScreenGui") do node = node.Parent end
	if node then node.Enabled = false end
	-- MainMenuManager owns HUD visibility; not telling it leaves the HUD hidden after a BACK.
	if _G.MainMenuManager and _G.MainMenuManager.notifyClosed then
		pcall(_G.MainMenuManager.notifyClosed, node and node.Name or "")
	end
	-- toggle, not "open": MORE+ is closed at this point (opening any of these panels closed it), so a
	-- toggle reopens it. Exactly what realm 1's crate BACK does with PetInvToggle.
	if _G.toggleMorePopup then
		pcall(_G.toggleMorePopup)
	else
		local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local ev = pg and pg:FindFirstChild("OpenMorePopup")
		if ev and ev:IsA("BindableEvent") then ev:Fire() end
	end
end

_G.addBackButton = function(closeBtn, onBack)
	if typeof(closeBtn) ~= "Instance" or not closeBtn:IsA("GuiObject") then return nil end
	local parent = closeBtn.Parent
	if not parent then return nil end
	if parent:FindFirstChild("BackBtn") then return parent.BackBtn end -- idempotent

	local back = Instance.new("TextButton")
	back.Name = "BackBtn"
	back.Size = UDim2.fromOffset(BACK_W, BACK_H)
	back.BackgroundColor3 = Color3.fromRGB(70, 86, 140)
	back.Font = Enum.Font.FredokaOne
	back.TextScaled = true
	back.TextColor3 = Color3.new(1, 1, 1)
	back.Text = "\xE2\x9D\xAE BACK"
	back.AutoButtonColor = true
	back.ZIndex = closeBtn.ZIndex   -- same layer as the X, so neither can bury the other

	-- ---- position: right edge GAP px left of the X's left edge, vertically centred on it ----
	local cp, cs, ca = closeBtn.Position, closeBtn.Size, closeBtn.AnchorPoint
	-- The X's LEFT edge in its parent's offset space. AnchorPoint.X scales how much of its own width sits
	-- left of Position, so this one expression covers (1,y), (0,y) and anything between.
	local xLeftOffset = cp.X.Offset - (cs.X.Offset * ca.X)
	-- Anchor the BACK on its own right edge, so it grows leftward and never creeps under the X.
	back.AnchorPoint = Vector2.new(1, ca.Y)
	local yOffset = cp.Y.Offset
	if ca.Y == 0 then
		yOffset = cp.Y.Offset + (cs.Y.Offset - BACK_H) / 2   -- top-anchored: centre it on the X's height
	end
	back.Position = UDim2.new(cp.X.Scale, xLeftOffset - GAP, cp.Y.Scale, yOffset)
	back.Parent = parent

	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = back
	local s = Instance.new("UIStroke"); s.Color = Color3.new(1, 1, 1); s.Thickness = 1.5; s.Parent = back
	local t = Instance.new("UITextSizeConstraint"); t.MaxTextSize = 14; t.Parent = back

	back.MouseButton1Click:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		if onBack then pcall(onBack) else defaultBack(back) end
	end)
	return back
end

print("[BackButtonKit] ready -- _G.addBackButton(closeBtn[, onBack]) places realm 1's BACK left of any close X")
