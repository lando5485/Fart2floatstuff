--======================================================================
-- TokenHud.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- A small always-on CRATE TOKEN counter under the coin counter.
--
-- Coins have a HUD pill; tokens had NOTHING on screen -- the only way to learn your
-- balance was to open the crate panel or the Pet Hub header. Tokens are checked less
-- often than coins, so this is deliberately SMALLER than the coin pill (~2/3 size),
-- but it is always there.
--
-- STYLE: the same dark-blue chip + gold text as the Pet Hub's header token chip
-- (HubTokens), so "this is the token colour" stays one consistent statement.
--
-- POSITION: glued under the coin pill by reading its on-screen box every second
-- (the same cadence every badge poll in this game uses). Computed, not hardcoded,
-- because the coin pill moves with viewport size / mobile scale -- and if CoinGui is
-- ever missing, the pill falls back to a fixed top-right slot instead of vanishing.
--
-- TAP: opens the Skin Crates panel -- the place tokens are spent.
--======================================================================

local Players   = game:GetService("Players")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local PILL_W, PILL_H = 104, 30

local gui = Instance.new("ScreenGui")
gui.Name = "TokenHudGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6                      -- with the HUD, under every menu (menus sit at 100)
gui:SetAttribute("NoTextSweep", true)     -- precise 16px type; CoreClient's TextScaled sweep must skip it
gui.Parent = PlayerGui

local pill = Instance.new("TextButton")
pill.Name = "TokenPill"
pill.Size = UDim2.fromOffset(PILL_W, PILL_H)
pill.Position = UDim2.new(1, -12 - PILL_W, 0, 8)    -- fallback slot; re-glued left of the coin pill below
pill.BackgroundColor3 = Color3.fromRGB(12, 44, 104) -- HubTokens chip blue
pill.AutoButtonColor = false
pill.Text = ""
pill.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 15); c.Parent = pill
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255, 215, 0); s.Thickness = 1.5; s.Parent = pill
end

local lbl = Instance.new("TextLabel")
lbl.BackgroundTransparency = 1
lbl.Size = UDim2.new(1, -12, 1, 0)
lbl.Position = UDim2.new(0, 6, 0, 0)
lbl.Font = Enum.Font.GothamBold
lbl.TextSize = 16
lbl.TextColor3 = Color3.fromRGB(255, 215, 0)
lbl.Text = "\xF0\x9F\x8E\x9F 0"
lbl.Parent = pill

-- tap -> the crate panel (where tokens get spent). Debounced like every toggle button.
local last = 0
pill.MouseButton1Click:Connect(function()
	local now = os.clock()
	if now - last < 0.35 then return end
	last = now
	if _G.playUIClick then pcall(_G.playUIClick) end
	if _G.toggleSkinCrates then _G.toggleSkinCrates() end
end)

-- Track the balance AND stay glued under the coin pill. One loop, 1s, matching the
-- badge-poll pattern the rest of the UI uses. _G.crateTokenBalance is pushed by
-- SkinCrateClient every time the server sends a new state, so this is never stale by
-- more than a second.
task.spawn(function()
	while true do
		local n = math.floor(tonumber(_G.crateTokenBalance) or 0)
		lbl.Text = "\xF0\x9F\x8E\x9F " .. ((n > 9999) and "9999+" or tostring(n))

		local coinFrame
		local cg = PlayerGui:FindFirstChild("CoinGui")
		if cg and cg:IsA("ScreenGui") and cg.Enabled then
			local f = cg:FindFirstChild("Frame")
			if f and f:IsA("GuiObject") and f.Visible then coinFrame = f end
		end
		if coinFrame then
			-- To the LEFT of the coin pill, vertically centred on it. NOT below: the STATS panel
			-- (RightPanelGui) starts directly under the coin counter, so a pill glued underneath
			-- sat on top of the stats header -- the token/coin/stats overlap on the right side.
			-- Left of the coins is the one direction on that edge with nothing in it.
			-- AbsolutePosition is in the same space for both guis (neither ignores the inset).
			local ap, as = coinFrame.AbsolutePosition, coinFrame.AbsoluteSize
			pill.Position = UDim2.fromOffset(ap.X - PILL_W - 8, ap.Y + math.floor((as.Y - PILL_H) / 2))
		end
		task.wait(1)
	end
end)

print("[TokenHud] ready -- crate-token pill under the coin counter (tap = open Skin Crates)")
