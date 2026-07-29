--======================================================================
-- RewardsHub.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- ONE "Rewards" row in MORE+ instead of two.
--
-- "Daily Rewards" and "Free Rewards" were two menu rows for the same idea -- things you
-- claim for free -- and a player had to already know which menu held which. This is the
-- single door: a small hub with two tabs, DAILY and FREE, that opens whichever panel the
-- player picks.
--
-- ===== IT ROUTES, IT DOES NOT RE-IMPLEMENT =====
-- The two panels stay where they are: DailyTasks.client.luau owns the daily/streak panel
-- and its claim remote, SocialRewards.client.luau owns the like/favourite/group panel and
-- its one-time grants. This hub only decides which one opens.
--
-- That is deliberate. Both panels talk to the server about state the server owns (what is
-- claimable, what has already been claimed). A second copy of either would be a second
-- thing that can disagree with the server, and the disagreement always shows up as a
-- reward a player believes they earned and did not get. Same reason the Pet Hub hands
-- CRATES and TOKENS to the crate panel instead of rebuilding them.
--
-- If you later want them genuinely embedded rather than routed, the move is to have each
-- panel expose a "render into this frame" entry point -- not to copy their internals.
--======================================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RSx          = game:GetService("ReplicatedStorage")
local player       = Players.LocalPlayer
local PlayerGui    = player:WaitForChild("PlayerGui")

--======================================================================
-- LOOK -- the same 700x520 box, palette and fonts every other menu uses, so this reads
-- as part of the set rather than as a bolted-on extra.
--======================================================================
local PANEL_W, PANEL_H = 700, 520
local PANEL_FILL   = Color3.fromRGB(225, 70, 170)
local PANEL_STROKE = Color3.fromRGB(140, 20, 100)
local HEADER_FILL  = Color3.fromRGB(170, 40, 125)
local CARD_FILL    = Color3.fromRGB(186, 44, 138)
local DESC_COLOR   = Color3.fromRGB(255, 205, 238)
local GOLD         = Color3.fromRGB(255, 220, 0)

local TABS = {
	{ id = "daily", label = "\xF0\x9F\x8E\x81 DAILY",
	  title = "Daily Rewards", desc = "Claim your login reward and finish today's tasks.",
	  tint = Color3.fromRGB(255, 175, 45),
	  open = function()
		-- Eligible -> the panel (the crate button lives in it). A brand-new player has no
		-- task list yet, so the panel would refuse to open -- fire the crate directly
		-- instead. The daily reward is never unreachable either way.
		if _G.dailyTasksAvailable and _G.dailyTasksAvailable() then
			if _G.toggleDailyTasks then _G.toggleDailyTasks() end
		else
			local ev = RSx:FindFirstChild("OpenMeteorCrate")
			if not ev then ev = Instance.new("BindableEvent"); ev.Name = "OpenMeteorCrate"; ev.Parent = RSx end
			ev:Fire()
		end
	  end },
	{ id = "free", label = "\xF0\x9F\x92\x9D FREE",
	  title = "Free Rewards", desc = "Rewards just for playing -- like, favourite and join the group.",
	  tint = Color3.fromRGB(255, 105, 140),
	  open = function() if _G.toggleSocialRewards then _G.toggleSocialRewards() end end },
}

local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function stroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = o; return s end
local function label(parent, props)
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent; return l
end

--======================================================================
-- BUILD
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "RewardsHubGui"; gui.ResetOnSpawn = false; gui.Enabled = false
gui.DisplayOrder = 100                              -- above the HUD, same as the Shop
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
-- The dashboard is precise type -- a 21px title beside a 13px description. CoreClient's
-- reposition pass force-sets TextScaled on every label under PlayerGui, which would
-- rescale each one to fill its frame and collapse the hierarchy. This is that pass's
-- documented opt-out.
gui:SetAttribute("NoTextSweep", true)
gui.Parent = PlayerGui

-- Full-screen catcher, Active=false so a click OUTSIDE falls through to the HUD rail
-- (click-to-switch). It is NOT a close button: this closes on the X only, because a
-- stray screen tap must never shut a panel.
local catcher = Instance.new("Frame")
catcher.Size = UDim2.new(1, 0, 1, 0); catcher.BackgroundTransparency = 1
catcher.Active = false; catcher.Parent = gui

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
panel.Position = UDim2.new(0.5, 0, 0.5, -45)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = PANEL_FILL
panel.Active = true
panel.Parent = gui
corner(panel, 20); stroke(panel, PANEL_STROKE, 3)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 72); header.BackgroundColor3 = HEADER_FILL
header.Parent = panel
corner(header, 20)
-- Square off the band's bottom: the 20px corner is only wanted where it meets the
-- panel's own top corners, or the pink shows through either side of the divider.
local patch = Instance.new("Frame")
patch.Size = UDim2.new(1, 0, 0, 22); patch.Position = UDim2.new(0, 0, 1, -22)
patch.BackgroundColor3 = HEADER_FILL; patch.BorderSizePixel = 0; patch.Parent = header

label(header, { Text = "REWARDS", Font = Enum.Font.FredokaOne, TextSize = 34, TextColor3 = GOLD,
	Size = UDim2.new(0, 300, 0, 38), Position = UDim2.new(0, 20, 0, 8),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
label(header, { Text = "Everything you can claim for free", Font = Enum.Font.Gotham, TextSize = 13,
	TextColor3 = DESC_COLOR, Size = UDim2.new(0, 400, 0, 16), Position = UDim2.new(0, 22, 0, 46),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -52, 0, 16)
closeBtn.BackgroundColor3 = Color3.fromRGB(210, 60, 55); closeBtn.Text = "X"
closeBtn.Font = Enum.Font.FredokaOne; closeBtn.TextSize = 20
closeBtn.TextColor3 = Color3.new(1, 1, 1); closeBtn.ZIndex = 3; closeBtn.Parent = header
corner(closeBtn, 10); stroke(closeBtn, Color3.new(0, 0, 0), 2)

--======================================================================
-- THE TWO SECTIONS -- one card each, side by side, with its own "!" badge.
--======================================================================
local CARD_W, CARD_H, GAP = 327, 300, 14
local badges = { daily = {}, free = {} }

for i, t in ipairs(TABS) do
	local card = Instance.new("TextButton")
	card.Name = "Section_" .. t.id
	card.Size = UDim2.new(0, CARD_W, 0, CARD_H)
	card.Position = UDim2.new(0, 16 + (i - 1) * (CARD_W + GAP), 0, 96)
	card.BackgroundColor3 = CARD_FILL; card.Text = ""
	card.AutoButtonColor = false; card.ClipsDescendants = true
	card.ZIndex = 3; card.Parent = panel
	corner(card, 16); stroke(card, PANEL_STROKE, 2)

	-- gloss over the top half: what makes the tile read as a panel, not a flat rectangle
	local gl = Instance.new("Frame")
	gl.Size = UDim2.new(1, 0, 0.5, 0); gl.BackgroundColor3 = Color3.new(1, 1, 1)
	gl.BorderSizePixel = 0; gl.ZIndex = 4; gl.Parent = card
	corner(gl, 16)
	local gg = Instance.new("UIGradient"); gg.Rotation = 90
	gg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(1, 1) })
	gg.Parent = gl

	local sq = Instance.new("Frame")
	sq.Size = UDim2.new(0, 96, 0, 96); sq.Position = UDim2.new(0.5, 0, 0, 26)
	sq.AnchorPoint = Vector2.new(0.5, 0); sq.BackgroundColor3 = t.tint; sq.ZIndex = 6; sq.Parent = card
	corner(sq, 20); stroke(sq, PANEL_STROKE, 2)
	label(sq, { Text = t.label:sub(1, 4), Font = Enum.Font.Gotham, TextSize = 46,
		Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })

	label(card, { Text = t.title, Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, -24, 0, 26), Position = UDim2.new(0, 12, 0, 136),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	label(card, { Text = t.desc, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = DESC_COLOR,
		Size = UDim2.new(1, -32, 0, 56), Position = UDim2.new(0, 16, 0, 166),
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true, ZIndex = 6 })

	local go = Instance.new("TextButton")
	go.Size = UDim2.new(1, -40, 0, 44); go.Position = UDim2.new(0, 20, 1, -60)
	go.BackgroundColor3 = t.tint; go.Text = "OPEN"
	go.Font = Enum.Font.GothamBold; go.TextSize = 18; go.TextColor3 = Color3.fromRGB(70, 30, 60)
	go.ZIndex = 6; go.Parent = card
	corner(go, 12); stroke(go, PANEL_STROKE, 2)

	-- red "!" badge, top-right of the card
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(26, 26); dot.AnchorPoint = Vector2.new(1, 0)
	dot.Position = UDim2.new(1, -10, 0, 10); dot.BackgroundColor3 = Color3.fromRGB(225, 50, 50)
	dot.ZIndex = 8; dot.Visible = false; dot.Parent = card
	corner(dot, 999)
	label(dot, { Text = "!", Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1), ZIndex = 9 })
	badges[t.id][#badges[t.id] + 1] = dot

	local function activate()
		if _G.playUIClick then pcall(_G.playUIClick) end
		gui.Enabled = false
		pcall(t.open)
	end
	card.MouseButton1Click:Connect(activate)
	go.MouseButton1Click:Connect(activate)

	-- hover lift, from the card's centre so every child scales with it
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = card
	local qi = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	card.MouseEnter:Connect(function() TweenService:Create(sc, qi, { Scale = 1.03 }):Play() end)
	card.MouseLeave:Connect(function() TweenService:Create(sc, qi, { Scale = 1 }):Play() end)
end

--======================================================================
-- OPEN / CLOSE
--======================================================================
local function setOpen(open)
	gui.Enabled = open and true or false
	-- This hub is Enabled-driven, so nothing here ever hides `panel`. Re-asserting it on
	-- open costs nothing and means an outside script that hid the frame (a stale duplicate,
	-- a backdrop sweep) cannot leave this opening to an empty screen.
	if open then panel.Visible = true end
	if open and _G.MainMenuManager and _G.MainMenuManager.notifyOpened then
		pcall(_G.MainMenuManager.notifyOpened, "Rewards")
	elseif (not open) and _G.MainMenuManager and _G.MainMenuManager.notifyClosed then
		pcall(_G.MainMenuManager.notifyClosed, "Rewards")
	end
end

closeBtn.MouseButton1Click:Connect(function()
	if _G.playUIClick then pcall(_G.playUIClick) end
	setOpen(false)
end)

-- Registered so opening any OTHER main menu closes this one, like every other panel.
if _G.MainMenuManager and _G.MainMenuManager.register then
	pcall(_G.MainMenuManager.register, "Rewards", function() gui.Enabled = false end)
end

_G.toggleRewardsHub = function() setOpen(not gui.Enabled) end
-- The MORE+ card wants OPEN, never toggle: "show me this" must not close it because some
-- other script left Enabled true.
_G.openRewardsHub   = function() setOpen(true) end

-- TRUE when EITHER side has something waiting -- this is what the MORE+ row's badge reads.
_G.rewardsPending = function()
	local ready   = (_G.crateIsClaimable  and _G.crateIsClaimable())  == true
	local pending = (_G.dailyTasksPending and _G.dailyTasksPending()) == true
	return ready or pending
end

-- Two INDEPENDENT badge groups on one poll: claiming the crate must not clear the
-- free-rewards badge, and vice versa.
task.spawn(function()
	while true do
		local dailyOn = ((_G.crateIsClaimable and _G.crateIsClaimable()) == true)
			or ((_G.dailyTasksPending and _G.dailyTasksPending()) == true)
		local freeOn  = (_G.socialRewardsPending and _G.socialRewardsPending()) == true
		for _, d in ipairs(badges.daily) do if d.Parent then d.Visible = dailyOn end end
		for _, d in ipairs(badges.free)  do if d.Parent then d.Visible = freeOn  end end
		task.wait(1)
	end
end)

print("[RewardsHub] ready -- one Rewards door, DAILY + FREE inside (_G.toggleRewardsHub)")
