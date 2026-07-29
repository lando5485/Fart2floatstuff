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
-- ===== THIS FILE ALSO OWNS THE TOP-RIGHT ROW LAYOUT =====
-- Three scripts used to guess at the same corner independently: the stale CoreClient parks the
-- coin pill at the right edge, SettingsMenu parks the gear at a HAND-TUNED x offset (-198), and
-- this pill glued itself "left of the coins" -- which IS the gear's spot. Nobody measured anybody
-- else, so the pill sat on the gear and the pill's red sale badge drew underneath it.
-- Now ONE pass lays the row out as a chain, right to left, with a fixed gap:
--
--     [ token pill ] <-GAP-> [ gear ] <-GAP-> [ coin pill ]   (coin stays where CoreClient puts it)
--
-- Each element is placed by its RIGHT edge from the measured ABSOLUTE left edge of the element
-- before it, so nothing can touch regardless of viewport, mobile scale, or the per-element
-- UIScale the HUD pass adds (offsets position the ANCHOR, which UIScale does not move).
-- It also clamps the coin pill's red discount/sale badge (baked-in, no synced source) back inside
-- the pill's bounds -- straddling the pill's TOP edge, never poking sideways into a neighbour.
--
-- TAP: opens the Skin Crates panel -- the place tokens are spent.
--======================================================================

local Players   = game:GetService("Players")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local PILL_W, PILL_H = 104, 30
local GAP = 10 -- the fixed breathing room between every element in the top-right row

local gui = Instance.new("ScreenGui")
gui.Name = "TokenHudGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6                      -- with the HUD, under every menu (menus sit at 100)
-- SAME coordinate space as CoinGui and SettingsGui (both IgnoreGuiInset=true). Without this the
-- pill computed its Y from CoinGui's full-screen coords but rendered in inset coords -- ~40px low,
-- into the stats panel.
gui.IgnoreGuiInset = true
gui:SetAttribute("NoTextSweep", true)     -- precise 16px type; CoreClient's TextScaled sweep must skip it
gui.Parent = PlayerGui

local pill = Instance.new("TextButton")
pill.Name = "TokenPill"
pill.Size = UDim2.fromOffset(PILL_W, PILL_H)
-- Anchored by its RIGHT-CENTRE: the layout pass positions right edges, and the per-element UIScale
-- the HUD pass adds scales the box AROUND the anchor -- so the right edge holds exactly where placed
-- at every scale, and the chain's gaps never compress.
pill.AnchorPoint = Vector2.new(1, 0.5)
pill.Position = UDim2.new(1, -12, 0, 33)            -- fallback slot; re-laid from the coin pill below
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

-- ===== THE LAYOUT PASS =====
-- Balance + the whole top-right row, twice a second (cheap: a handful of property reads).
--
-- The chain is measured, not authored: each element's right edge = the previous element's
-- MEASURED absolute left edge minus GAP. Absolute coords are comparable across all three guis
-- because all three are IgnoreGuiInset = true.
local badgeClamped = {} -- [GuiObject] = true, so each rescued badge is logged once

local function clampCoinBadges(coinFrame)
	-- The red discount/sale badge on the coin pill is baked into the place (no synced source), and
	-- it hangs off the pill's edge -- which put it underneath whatever neighbours the pill. Any
	-- small red thing in CoinGui that pokes OUTSIDE the pill sideways gets snapped to straddle the
	-- pill's top-right corner: fully inside horizontally, above it vertically, drawn on top.
	local pl = coinFrame.AbsolutePosition.X
	local pr = pl + coinFrame.AbsoluteSize.X
	for _, d in ipairs(coinFrame.Parent:GetDescendants()) do
		if (d:IsA("Frame") or d:IsA("TextLabel") or d:IsA("ImageLabel") or d:IsA("TextButton"))
			and d.Visible and d.BackgroundTransparency < 0.5
			and d.AbsoluteSize.X > 0 and d.AbsoluteSize.X <= 90 and d.AbsoluteSize.Y <= 60
		then
			local c = d.BackgroundColor3
			if c.R > 0.7 and c.G < 0.45 and c.B < 0.45 then -- red, badge-sized
				local dl = d.AbsolutePosition.X
				local dr = dl + d.AbsoluteSize.X
				if dl < pl - 2 or dr > pr + 2 then -- pokes sideways out of the pill into a neighbour
					d.AnchorPoint = Vector2.new(1, 0.5)
					d.Position = UDim2.new(1, -6, 0, 0) -- straddles the parent's top edge, inside its right end
					d.ZIndex = 12                       -- above the pill, never behind a neighbour
					if not badgeClamped[d] then
						badgeClamped[d] = true
						warn("[TokenHud] clamped a badge that hung outside the coin pill: " .. d:GetFullName())
					end
				end
			end
		end
	end
end

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
			local ap, as = coinFrame.AbsolutePosition, coinFrame.AbsoluteSize
			local midY = ap.Y + math.floor(as.Y / 2)
			local nextRight = ap.X - GAP -- where the next element's right edge goes

			-- (1) GEAR: right edge a fixed GAP left of the pill, vertically centred on the coin
			-- row. Its authored -198 was tuned for one viewport and is exactly what the pill and
			-- badge were colliding with; measured placement replaces it.
			local sgui = PlayerGui:FindFirstChild("SettingsGui")
			local gear = sgui and sgui:FindFirstChild("SettingsGearBtn")
			if gear and gear:IsA("GuiObject") and gear.Visible then
				gear.AnchorPoint = Vector2.new(1, 0.5)
				gear.Position = UDim2.fromOffset(nextRight, midY)
				-- derive the next slot from the gear's SIZE, not a same-frame AbsolutePosition
				-- read (which may not have recomputed yet): left edge = right edge - width.
				nextRight = nextRight - gear.AbsoluteSize.X - GAP
			end

			-- (2) TOKEN PILL: right edge a fixed GAP left of whatever came before (gear if
			-- present, else the coin pill).
			pill.Position = UDim2.fromOffset(nextRight, midY)

			-- (3) the red badge stays inside the pill it belongs to
			pcall(clampCoinBadges, coinFrame)
		end
		task.wait(0.5)
	end
end)

print("[TokenHud] ready -- token pill + top-right row layout (pill | gear | coins, fixed gaps; tap = Skin Crates)")
