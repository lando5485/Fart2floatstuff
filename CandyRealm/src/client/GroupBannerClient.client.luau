--[[
	GroupBannerClient.client.luau  (StarterPlayerScripts.GroupBannerClient)

	A one-per-session "JOIN THE GROUP" popup, ported from the Space Realm banner and re-skinned to the house
	palette. Shown ONCE, after 1 MINUTE OF PLAYTIME.

	UI ONLY: the JOIN button opens the MLR Studios group page (group 758781978); closing or tapping Join
	dismisses it for the session. NO reward is granted -- see the TODO in the Join handler.

	WHY A TIMER INSTEAD OF "AFTER THE INTRO": the Space version waited for the intro cinematic to end, which
	meant it landed the instant a brand-new player got control -- the single worst moment to interrupt, before
	they have done anything or have any reason to care about a group. A minute in they have flown, earned
	coins, and the ask makes sense. Space and Candy now use this same one-minute rule.

	The minute is PLAYTIME, not wall clock: the counter is paused while an intro/arrival cinematic is on
	screen, because sitting through a cutscene is not playing. So the banner cannot appear mid-cinematic, and
	a 25-second intro does not eat nearly half the delay.

	Self-contained by design: it builds its own ScreenGui and requires NOTHING. The three realms nest their
	shared modules differently (Space maps src/shared to the ReplicatedStorage root; this realm and Candy put
	it under a "Shared" folder), so a single require path would break in at least one of them. Phone detection
	is done inline off UserInputService rather than through PhoneHUD for the same reason.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local GROUP_ID = 758781978
local GROUP_URL = "https://www.roblox.com/groups/758781978" -- MLR Studios

-- One minute of playtime before the ask. Tune here; Space and Candy carry the same value.
local PLAYTIME_SECONDS = 60

-- Any ScreenGui in PlayerGui with one of these names means a cinematic is on screen: the playtime counter
-- pauses and the banner will not open. Every realm's cover GUI is listed so this file stays identical
-- between Fart to Float and Candy Realm (a name that does not exist here simply never matches).
local CINEMATIC_GUIS = {
	"GardenIntroCover",       -- Fart to Float: GardenIntro's full-screen cover
	"GardenIntroSkip",        -- Fart to Float: the skip button, up for the whole intro
	"CandyArrivalCinematic",  -- Candy Realm: ArrivalCinematic
	"IntroCinematic",         -- Space Realm (harmless here)
}

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== House palette (see CrateClient's `local C` -- bright, never dark) =====
local BG_DIM      = Color3.fromRGB(6, 26, 80)     -- navy scrim, NOT black
local PANEL       = Color3.fromRGB(26, 79, 214)   -- #1a4fd6 panel top
local PANEL_DK    = Color3.fromRGB(14, 59, 176)   -- #0e3bb0 panel bottom
local TITLE_BAR   = Color3.fromRGB(18, 56, 150)
local WHITE       = Color3.fromRGB(255, 255, 255)
local MUTED       = Color3.fromRGB(214, 232, 252)
local GOLD        = Color3.fromRGB(255, 210, 74)  -- #ffd24a
local LIME        = Color3.fromRGB(126, 217, 87)  -- #7ed957
local LIME_DK     = Color3.fromRGB(74, 150, 32)
local RED         = Color3.fromRGB(214, 64, 72)

-- Phones get the whole popup shrunk so it fits with margin. Same test ResponsiveUI uses: touch and no keyboard
-- (an iPad with a keyboard is treated as desktop, which is the behaviour the rest of the HUD already has).
local isPhone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local REST_SCALE = isPhone and 0.7 or 1
local POP_SCALE = 0.6 * REST_SCALE

local shown = false

local function cinematicUp()
	for _, name in ipairs(CINEMATIC_GUIS) do
		local g = PlayerGui:FindFirstChild(name)
		if g and g:IsA("ScreenGui") then
			return true
		end
	end
	return false
end

local function showBanner()
	if shown then
		return
	end
	shown = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "GroupBanner"
	gui.ResetOnSpawn = false -- survive respawns; shown once per session
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200 -- above the HUD; it's a modal popup
	gui.Parent = PlayerGui

	-- Navy scrim. Active = true so it swallows clicks aimed at the HUD behind, but it is deliberately NOT a
	-- button and has NO dismiss handler: in this game a menu closes on its X and nothing else, so a stray tap
	-- on the background must never shut the popup.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = BG_DIM
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Active = true
	backdrop.ZIndex = 1
	backdrop.Parent = gui
	TweenService:Create(backdrop, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()

	-- Soft navy drop shadow behind the panel.
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 0, 0.5, 8)
	shadow.Size = UDim2.new(0.9, 14, 0, 308)
	shadow.BackgroundColor3 = Color3.fromRGB(6, 26, 80)
	shadow.BackgroundTransparency = 0.45
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 2
	shadow.Parent = gui
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 24); c.Parent = shadow end
	do local sc = Instance.new("UISizeConstraint"); sc.MaxSize = Vector2.new(474, 314); sc.Parent = shadow end
	local shadowScale = Instance.new("UIScale"); shadowScale.Scale = POP_SCALE; shadowScale.Parent = shadow

	-- Main panel: blue gradient body, thick WHITE border.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0.9, 0, 0, 300)
	panel.BackgroundColor3 = PANEL
	panel.BorderSizePixel = 0
	panel.ZIndex = 3
	panel.Parent = gui
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 20); c.Parent = panel end
	do
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(PANEL, PANEL_DK)
		g.Rotation = 90
		g.Parent = panel
	end
	do local s = Instance.new("UIStroke"); s.Color = WHITE; s.Thickness = 4; s.Parent = panel end
	do local sc = Instance.new("UISizeConstraint"); sc.MaxSize = Vector2.new(460, 300); sc.Parent = panel end
	local panelScale = Instance.new("UIScale"); panelScale.Scale = POP_SCALE; panelScale.Parent = panel

	-- Title bar (rounded top corners match the panel; a mask squares off the bottom edge).
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 58)
	titleBar.BackgroundColor3 = TITLE_BAR
	titleBar.BorderSizePixel = 0
	titleBar.ZIndex = 4
	titleBar.Parent = panel
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 20); c.Parent = titleBar end
	local titleMask = Instance.new("Frame")
	titleMask.Name = "TitleMask"
	titleMask.AnchorPoint = Vector2.new(0, 1)
	titleMask.Position = UDim2.new(0, 0, 1, 0)
	titleMask.Size = UDim2.new(1, 0, 0, 20)
	titleMask.BackgroundColor3 = TITLE_BAR
	titleMask.BorderSizePixel = 0
	titleMask.ZIndex = 4
	titleMask.Parent = titleBar

	local headline = Instance.new("TextLabel")
	headline.Name = "Headline"
	headline.BackgroundTransparency = 1
	headline.AnchorPoint = Vector2.new(0, 0.5)
	headline.Position = UDim2.new(0, 18, 0.5, 0)
	headline.Size = UDim2.new(1, -70, 1, -14)
	headline.Font = Enum.Font.FredokaOne
	headline.Text = "JOIN THE GROUP!"
	headline.TextColor3 = GOLD
	headline.TextScaled = true
	headline.TextXAlignment = Enum.TextXAlignment.Left
	headline.ZIndex = 5
	headline.Parent = titleBar
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 28; cns.Parent = headline end
	do local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(6, 26, 80); st.Thickness = 2; st.Parent = headline end

	-- X / close button (top-right of the title bar). The ONLY way to dismiss besides tapping Join.
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.Size = UDim2.new(0, 38, 0, 38)
	closeBtn.BackgroundColor3 = RED
	closeBtn.AutoButtonColor = true
	closeBtn.Font = Enum.Font.FredokaOne
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(20, 20, 20)
	closeBtn.TextScaled = true
	closeBtn.ZIndex = 6
	closeBtn.Parent = titleBar
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = closeBtn end
	do local s = Instance.new("UIStroke"); s.Color = WHITE; s.Thickness = 3; s.Parent = closeBtn end
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 22; cns.Parent = closeBtn end

	-- Body text.
	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.new(0.5, 0, 0, 138)
	body.Size = UDim2.new(1, -44, 0, 96)
	body.Font = Enum.Font.GothamMedium
	body.Text = "Join MLR Studios for exclusive rewards coming soon!"
	body.TextColor3 = MUTED
	body.TextWrapped = true
	body.TextSize = 20
	body.ZIndex = 4
	body.Parent = panel

	-- JOIN GROUP button (big, near the bottom).
	local joinBtn = Instance.new("TextButton")
	joinBtn.Name = "JoinGroup"
	joinBtn.AnchorPoint = Vector2.new(0.5, 1)
	joinBtn.Position = UDim2.new(0.5, 0, 1, -22)
	joinBtn.Size = UDim2.new(1, -44, 0, 54)
	joinBtn.BackgroundColor3 = LIME
	joinBtn.AutoButtonColor = true
	joinBtn.Font = Enum.Font.FredokaOne
	joinBtn.Text = "JOIN GROUP"
	joinBtn.TextColor3 = Color3.fromRGB(12, 44, 8)
	joinBtn.TextScaled = true
	joinBtn.ZIndex = 4
	joinBtn.Parent = panel
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = joinBtn end
	do local s = Instance.new("UIStroke"); s.Color = LIME_DK; s.Thickness = 3; s.Parent = joinBtn end
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 26; cns.Parent = joinBtn end

	-- Scale-in pop (panel + shadow together).
	pcall(function()
		TweenService:Create(panelScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = REST_SCALE }):Play()
		TweenService:Create(shadowScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = REST_SCALE }):Play()
	end)

	print(("[GroupBanner] shown (group %d) after %ds of playtime"):format(GROUP_ID, PLAYTIME_SECONDS))

	-- ===== Dismiss (once) =====
	local dismissed = false
	local function dismiss()
		if dismissed then
			return
		end
		dismissed = true
		print("[GroupBanner] closed/join tapped")
		pcall(function()
			TweenService:Create(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = POP_SCALE }):Play()
			TweenService:Create(shadowScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = POP_SCALE }):Play()
			TweenService:Create(panel, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(backdrop, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		end)
		task.delay(0.3, function()
			if gui then
				gui:Destroy()
			end
		end)
	end

	closeBtn.Activated:Connect(dismiss)

	joinBtn.Activated:Connect(function()
		-- Open the MLR Studios group page (758781978). There's no sanctioned in-game "join group" prompt, so
		-- open the group page in the in-experience browser; the player joins from there.
		pcall(function()
			GuiService:OpenBrowserWindow(GROUP_URL)
		end)

		-- TODO(reward): grant a "joined the group" reward HERE once it's designed.
		--   1) Verify membership AUTHORITATIVELY on the server -- the client `player:IsInGroup(GROUP_ID)` is
		--      spoofable, so a server RemoteFunction should call player:IsInGroup(758781978) and gate the grant.
		--   2) Award it via that server path, once-per-player (persisted), then flip this banner to a
		--      "reward claimed" state. NO reward is granted yet -- this banner is UI only for now.

		dismiss()
	end)
end

-- Run once: bank a minute of actual playtime, then open (never over a cinematic).
task.spawn(function()
	if not player.Character then
		player.CharacterAdded:Wait()
	end

	local elapsed = 0
	while elapsed < PLAYTIME_SECONDS do
		local dt = task.wait(0.5)
		if not cinematicUp() then
			elapsed += dt
		end
	end

	-- A cinematic could have started on the very tick the minute completed (an event, a realm arrival);
	-- hold until the screen is the player's again.
	while cinematicUp() do
		task.wait(0.25)
	end
	task.wait(0.6) -- a beat of air so it doesn't pop on the same frame as whatever just closed

	showBanner()
end)
