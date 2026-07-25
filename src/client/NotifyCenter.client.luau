--======================================================================
-- NotifyCenter.client.luau   (StarterPlayerScripts)
--======================================================================
-- ONE OWNER FOR EVERY TRANSIENT BANNER. Before this, five separate ScreenGuis
-- (ArrivalGui, AnnounceGui, HudNoticeGui, PurchaseBanner, EventBannerGui) all
-- rested at the SAME spot -- UDim2.new(0.5,0,0,10), 500x65 -- with nothing
-- coordinating them. Land on a new island while another player announces theirs
-- and the two banners drew straight through each other.
--
-- Two ideas fix it:
--   1) LANES. Notifications are placed by KIND, not all dumped top-centre.
--      HERO   = your own big moments (top-centre, the prime slot)
--      SOCIAL = other players' news (top-left, small, never blocks you)
--   2) PRIORITY. The HERO lane shows exactly ONE banner at a time. A more
--      important one PREEMPTS a less important one; equal-or-lower ones QUEUE.
--      So "ISLAND UNLOCKED!" is never buried under "Daily Reward Ready".
--
-- The screen's vertical budget for the top-centre column is fixed and shared:
--     y  10..75   HERO banner            (this file)
--     y  85..163  ObjectiveHUD card      (ObjectiveHUD.client.luau)
--     y 175..     Event stack            (MeteorUI / RocketUI, slot-based)
-- Anything new that wants top-centre space must go through a lane here, or it
-- WILL land on top of one of the three above.
--
-- Callers use _G.NotifyCenter.push{...}. CoreClient's showArrival /
-- showHudBanner / showServerEventBanner / queueAnnouncement / purchase banner
-- all delegate here, so every existing call site keeps working unchanged.
--======================================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== PRIORITIES (higher wins the HERO slot) =====
-- Exported so callers name the moment instead of hard-coding a number.
local PRIORITY = {
	ISLAND   = 100, -- "BROCCOLI BLUFF!" -- you physically landed on a new island. The biggest moment in the game.
	PURCHASE = 90,  -- a real Robux/gamepass purchase went through -- must never be swallowed.
	EVENT    = 80,  -- a server event started (2x coins, low gravity, ...).
	REWARD   = 40,  -- "Daily Reward Ready" / "Stomach Upgrade Available" -- a nudge, not news.
	SOCIAL   = 10,  -- another player reached an island. Routed to its own lane; never competes.
}

local HERO_SHOWN  = UDim2.new(0.5, 0, 0, 10)
local HERO_HIDDEN = UDim2.new(0.5, 0, 0, -100)

-- ===== HERO lane: top-centre, one at a time =====
local heroGui = Instance.new("ScreenGui")
heroGui.Name = "NotifyHero"
heroGui.ResetOnSpawn = false
heroGui.IgnoreGuiInset = true
heroGui.DisplayOrder = 95 -- above the HUD, below shops (100) and the crate reveal
heroGui.Parent = playerGui

local hero = Instance.new("Frame")
hero.Name = "Hero"
hero.AnchorPoint = Vector2.new(0.5, 0)
hero.Position = HERO_HIDDEN
hero.Size = UDim2.new(0, 500, 0, 65)
hero.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
hero.BorderSizePixel = 0
hero.Visible = false
hero.Parent = heroGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = hero
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(0, 0, 0); s.Thickness = 2; s.Parent = hero
end

local heroTop = Instance.new("TextLabel")
heroTop.AnchorPoint = Vector2.new(0.5, 0)
heroTop.Position = UDim2.new(0.5, 0, 0, 6)
heroTop.Size = UDim2.new(1, -12, 0, 22)
heroTop.BackgroundTransparency = 1
heroTop.Font = Enum.Font.GothamBold
heroTop.TextColor3 = Color3.new(1, 1, 1)
heroTop.TextScaled = true
heroTop.Text = ""
heroTop.Parent = hero
do local s = Instance.new("UIStroke"); s.Color = Color3.new(0, 0, 0); s.Thickness = 2; s.Parent = heroTop end

-- Some banners are tappable (RewardsClient's group/friend nags open a panel). One transparent button
-- covers the whole card; presentHero rebinds it per banner and clears it when nothing is showing.
local heroBtn = Instance.new("TextButton")
heroBtn.Size = UDim2.fromScale(1, 1)
heroBtn.BackgroundTransparency = 1
heroBtn.Text = ""
heroBtn.AutoButtonColor = false
heroBtn.Visible = false
heroBtn.Active = false
heroBtn.ZIndex = 5
heroBtn.Parent = hero

local heroOnClick = nil
heroBtn.Activated:Connect(function()
	local f = heroOnClick
	if f then pcall(f) end
end)

local heroMain = Instance.new("TextLabel")
heroMain.AnchorPoint = Vector2.new(0.5, 0)
heroMain.Position = UDim2.new(0.5, 0, 0, 29)
heroMain.Size = UDim2.new(1, -12, 0, 32)
heroMain.BackgroundTransparency = 1
heroMain.Font = Enum.Font.FredokaOne
heroMain.TextColor3 = Color3.new(1, 1, 1)
heroMain.TextScaled = true
heroMain.Text = ""
heroMain.Parent = hero
do local s = Instance.new("UIStroke"); s.Color = Color3.new(0, 0, 0); s.Thickness = 2; s.Parent = heroMain end

-- ===== SOCIAL lane: top-left, small, stacks, never competes with HERO =====
local socialGui = Instance.new("ScreenGui")
socialGui.Name = "NotifySocial"
socialGui.ResetOnSpawn = false
socialGui.IgnoreGuiInset = true
socialGui.DisplayOrder = 94
socialGui.Parent = playerGui

local SOCIAL_MAX  = 3   -- most pills on screen at once; the oldest is evicted past this
local SOCIAL_H    = 34
local SOCIAL_GAP  = 6
local socialPills = {}  -- newest last

local function layoutSocial()
	for i, pill in ipairs(socialPills) do
		local y = 10 + (i - 1) * (SOCIAL_H + SOCIAL_GAP)
		TweenService:Create(pill, TweenInfo.new(0.2), { Position = UDim2.new(0, 10, 0, y) }):Play()
	end
end

local function popSocial(pill)
	for i, p in ipairs(socialPills) do
		if p == pill then table.remove(socialPills, i); break end
	end
	TweenService:Create(pill, TweenInfo.new(0.25), { Position = UDim2.new(0, -320, 0, pill.Position.Y.Offset) }):Play()
	task.delay(0.3, function() if pill.Parent then pill:Destroy() end end)
	layoutSocial()
end

local function showSocial(text, color)
	local pill = Instance.new("TextLabel")
	pill.AnchorPoint = Vector2.new(0, 0)
	pill.Position = UDim2.new(0, -320, 0, 10)
	pill.Size = UDim2.new(0, 300, 0, SOCIAL_H)
	pill.BackgroundColor3 = color or Color3.fromRGB(45, 55, 90)
	pill.BackgroundTransparency = 0.15
	pill.BorderSizePixel = 0
	pill.Font = Enum.Font.GothamBold
	pill.TextColor3 = Color3.fromRGB(235, 240, 255)
	pill.TextSize = 14
	pill.TextScaled = true
	pill.Text = "  " .. text
	pill.TextXAlignment = Enum.TextXAlignment.Left
	pill.Parent = socialGui
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = pill
		local s = Instance.new("UIStroke"); s.Color = Color3.new(0, 0, 0); s.Thickness = 1.5; s.Parent = pill
		local t = Instance.new("UITextSizeConstraint"); t.MaxTextSize = 15; t.Parent = pill
	end

	socialPills[#socialPills + 1] = pill
	if #socialPills > SOCIAL_MAX then popSocial(socialPills[1]) end
	layoutSocial()
	task.delay(4.5, function() if pill.Parent then popSocial(pill) end end)
end

-- ===== HERO scheduler: one at a time, priority-ordered, preemptable =====
local queue    = {}    -- pending specs, highest priority first (stable within a priority)
local showing  = nil   -- the spec currently on screen
local token    = 0     -- invalidates the in-flight hide timer when a banner is replaced
local lastText, lastAt = nil, 0

local function hideHero(after)
	TweenService:Create(hero, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Position = HERO_HIDDEN }):Play()
	task.delay(0.32, function()
		hero.Visible = false
		if after then after() end
	end)
end

local drain -- forward declaration (mutually recursive with presentHero)

local function presentHero(spec)
	showing = spec
	token = token + 1
	local mine = token

	heroTop.Text  = spec.top or ""
	heroTop.Visible = (spec.top ~= nil and spec.top ~= "")
	heroMain.Text = spec.text or ""
	-- With no top line, the main label uses the whole card instead of sitting low.
	heroMain.Position = heroTop.Visible and UDim2.new(0.5, 0, 0, 29) or UDim2.new(0.5, 0, 0, 10)
	heroMain.Size     = heroTop.Visible and UDim2.new(1, -12, 0, 32) or UDim2.new(1, -12, 0, 45)
	hero.BackgroundColor3 = spec.color or Color3.fromRGB(100, 200, 100)

	heroOnClick = spec.onClick
	heroBtn.Visible = spec.onClick ~= nil
	heroBtn.Active  = spec.onClick ~= nil

	hero.Position = HERO_HIDDEN
	hero.Visible = true
	TweenService:Create(hero, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = HERO_SHOWN }):Play()

	if spec.sound then pcall(spec.sound) end

	task.delay(spec.duration or 3.5, function()
		if token ~= mine then return end -- preempted or replaced -> that path owns the hide
		hideHero(function()
			if token ~= mine then return end
			showing = nil
			heroOnClick = nil
			heroBtn.Visible = false
			heroBtn.Active = false
			if spec.onDone then pcall(spec.onDone) end -- let the caller's own queue advance
			drain()
		end)
	end)
end

function drain()
	if showing or #queue == 0 then return end
	presentHero(table.remove(queue, 1))
end

-- Insert by priority: strictly-greater priorities go ahead, equals keep arrival order (FIFO).
local function enqueue(spec)
	local i = #queue + 1
	for k = 1, #queue do
		if spec.priority > queue[k].priority then i = k; break end
	end
	table.insert(queue, i, spec)
end

--- push a notification.
--- spec = { text, top?, color?, priority?, duration?, lane? ("hero"|"social"), sound? (fn) }
local function push(spec)
	if type(spec) ~= "table" or not spec.text then return end
	spec.priority = spec.priority or PRIORITY.REWARD

	if spec.lane == "social" or spec.priority <= PRIORITY.SOCIAL then
		showSocial(spec.text, spec.color)
		return
	end

	-- Drop an exact repeat within 2s (the reward reminder re-fires on a loop). onDone MUST still fire:
	-- callers like RewardsClient hold a `bannerShowing` flag that only clears on onDone, so silently
	-- swallowing the spec would wedge their queue permanently.
	local now = os.clock()
	if spec.text == lastText and (now - lastAt) < 2 then
		if spec.onDone then task.defer(function() pcall(spec.onDone) end) end
		return
	end
	lastText, lastAt = spec.text, now

	if not showing then
		presentHero(spec)
		return
	end

	if spec.priority > showing.priority then
		-- PREEMPT: the current banner is less important. Put it back at the head of the
		-- queue (it still deserves its moment) and swap the new one in immediately.
		token = token + 1 -- orphan the outgoing banner's hide timer
		local demoted = showing
		showing = nil
		enqueue(demoted)
		hideHero(function() if not showing then drain() end end)
		-- the preempting spec must lead the queue
		table.insert(queue, 1, spec)
		return
	end

	enqueue(spec) -- equal or lower -> wait your turn
end

_G.NotifyCenter = {
	push     = push,
	PRIORITY = PRIORITY,
	isBusy   = function() return showing ~= nil end,
}

print("[NotifyCenter] ready -- HERO lane (top-centre, priority queue) + SOCIAL lane (top-left)")
