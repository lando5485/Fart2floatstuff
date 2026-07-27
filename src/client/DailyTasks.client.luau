-- DailyTasks.client.luau  (LocalScript)  -- the daily chore checklist panel.
--
-- DISPLAY ONLY. Every tick and the bonus itself are decided on the server (DailyTasks.server.lua); this script
-- cannot mark anything done. It receives a state blob and draws it.
--
-- The task LIST comes from the server too, rather than being hardcoded here -- if the two lists drifted, the
-- panel would cheerfully show a checklist the server doesn't agree with.
--
-- OPENS ONLY FROM More+ > Daily Tasks. It is a full menu like the Shop, not a HUD widget: same 700x520 frame,
-- same centre position, same DisplayOrder 100, and registered with MainMenuManager so opening it closes the
-- Shop/Stomach menus (and they close it) instead of two panels stacking on top of each other.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local SocialService     = game:GetService("SocialService")
local Players           = game:GetService("Players")

local player = Players.LocalPlayer
local gui    = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("DailyTasksEvent", 30)
if not remote then
	warn("[DailyTasks] DailyTasksEvent never appeared -- panel not built")
	return
end

-- ===== palette =====
local BG        = Color3.fromRGB(20, 24, 38)
local CARD      = Color3.fromRGB(32, 38, 58)
local CARD_DONE = Color3.fromRGB(26, 52, 42)
local GREEN     = Color3.fromRGB(110, 226, 140)
local GOLD      = Color3.fromRGB(255, 205, 70)
local GOLD_DK   = Color3.fromRGB(196, 148, 34)
local TXT       = Color3.fromRGB(236, 240, 248)
local TXT_DIM   = Color3.fromRGB(132, 143, 166)

-- Icons live client-side, keyed by the server's task id. The server owns WHAT the tasks are; presentation is
-- ours. An unknown id still renders -- it just gets the neutral fallback rather than crashing the panel.
local ICONS = {
	water    = "\u{1F4A7}",
	feed_cow = "\u{1F404}",
	feed_pig = "\u{1F437}",
	invite   = "\u{1F465}",
}

-- ============================ shell ============================

local screen = Instance.new("ScreenGui")
screen.Name           = "DailyTasksGui"
screen.ResetOnSpawn   = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.DisplayOrder   = 100   -- same as the Shop / Stomach menus: definitively above the HUD
screen.Enabled        = false -- CLOSED until opened from More+
screen.Parent         = gui

-- Tap-outside-to-close, same affordance the More+ menu uses. FULLY TRANSPARENT: it still catches the click,
-- it just doesn't grey the world out behind the panel.
local catcher = Instance.new("TextButton")
catcher.Size                   = UDim2.fromScale(1, 1)
catcher.BackgroundTransparency = 1
catcher.Text                   = ""
catcher.AutoButtonColor        = false
catcher.ZIndex                 = 1
catcher.Parent                 = screen

local panel = Instance.new("Frame")
panel.Name             = "Panel"
panel.AnchorPoint      = Vector2.new(0.5, 0.5)
panel.Position         = UDim2.new(0.5, 0, 0.5, -45) -- matches the Shop exactly
panel.Size             = UDim2.new(0, 700, 0, 520)   -- matches the Shop exactly
panel.BackgroundColor3 = BG
panel.BorderSizePixel  = 0
panel.ZIndex           = 2
panel.Parent           = screen
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)

local pstroke = Instance.new("UIStroke", panel)
pstroke.Color       = GOLD
pstroke.Thickness   = 3
pstroke.Transparency = 0.45

-- Depth: a soft vertical gradient over the flat fill so the panel isn't a dead rectangle.
local pgrad = Instance.new("UIGradient", panel)
pgrad.Rotation = 90
pgrad.Color    = ColorSequence.new(Color3.fromRGB(30, 36, 56), Color3.fromRGB(16, 19, 30))

-- ===== header =====
local head = Instance.new("Frame")
head.Size             = UDim2.new(1, 0, 0, 78)
head.BackgroundColor3 = Color3.fromRGB(44, 52, 80)
head.BorderSizePixel  = 0
head.ZIndex           = 3
head.Parent           = panel
Instance.new("UICorner", head).CornerRadius = UDim.new(0, 16)
local hgrad = Instance.new("UIGradient", head)
hgrad.Rotation = 0
hgrad.Color    = ColorSequence.new(Color3.fromRGB(58, 48, 96), Color3.fromRGB(36, 54, 84))
-- Square the header's bottom corners so it butts flush against the body instead of floating.
local hfill = Instance.new("Frame")
hfill.Size             = UDim2.new(1, 0, 0, 18)
hfill.Position         = UDim2.new(0, 0, 1, -18)
hfill.BackgroundColor3 = Color3.fromRGB(41, 51, 82)
hfill.BorderSizePixel  = 0
hfill.ZIndex           = 3
hfill.Parent           = head

local title = Instance.new("TextLabel")
title.Position               = UDim2.new(0, 24, 0, 12)
title.Size                   = UDim2.new(1, -110, 0, 32)
title.BackgroundTransparency = 1
title.Font                   = Enum.Font.GothamBlack
title.Text                   = "DAILY TASKS"
title.TextColor3             = GOLD
title.TextSize               = 28
title.TextXAlignment         = Enum.TextXAlignment.Left
title.ZIndex                 = 4
title.Parent                 = head

local sub = Instance.new("TextLabel")
sub.Position               = UDim2.new(0, 24, 0, 44)
sub.Size                   = UDim2.new(1, -110, 0, 20)
sub.BackgroundTransparency = 1
sub.Font                   = Enum.Font.GothamMedium
sub.Text                   = "Resets every 24 hours"
sub.TextColor3             = TXT_DIM
sub.TextSize               = 14
sub.TextXAlignment         = Enum.TextXAlignment.Left
sub.ZIndex                 = 4
sub.Parent                 = head

-- STREAK BADGE. Sits in the header next to the close button: it's the number the player is protecting, so it
-- belongs where they can't miss it.
local streakBadge = Instance.new("Frame")
streakBadge.AnchorPoint      = Vector2.new(1, 0.5)
streakBadge.Position         = UDim2.new(1, -70, 0.5, 0)
streakBadge.Size             = UDim2.fromOffset(112, 40)
streakBadge.BackgroundColor3 = Color3.fromRGB(58, 40, 26)
streakBadge.BorderSizePixel  = 0
streakBadge.ZIndex           = 5
streakBadge.Parent           = head
Instance.new("UICorner", streakBadge).CornerRadius = UDim.new(0, 10)
local sbStroke = Instance.new("UIStroke", streakBadge)
sbStroke.Color = Color3.fromRGB(120, 82, 40); sbStroke.Thickness = 2

local streakTxt = Instance.new("TextLabel")
streakTxt.Size                   = UDim2.fromScale(1, 1)
streakTxt.BackgroundTransparency = 1
streakTxt.Font                   = Enum.Font.GothamBlack
streakTxt.Text                   = "\u{1F525} 0"
streakTxt.TextColor3             = Color3.fromRGB(255, 168, 76)
streakTxt.TextSize               = 18
streakTxt.ZIndex                 = 6
streakTxt.Parent                 = streakBadge

local close = Instance.new("TextButton")
close.AnchorPoint      = Vector2.new(1, 0.5)
close.Position         = UDim2.new(1, -18, 0.5, 0)
close.Size             = UDim2.fromOffset(40, 40)
close.BackgroundColor3 = Color3.fromRGB(212, 68, 84)
close.Font             = Enum.Font.FredokaOne
close.Text             = "X"                       -- plain white X, matching the other menus' close buttons
close.TextColor3       = Color3.new(1, 1, 1)
close.TextSize         = 22
close.ZIndex           = 5
close.Parent           = head
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)

-- ===== progress bar =====
local barBG = Instance.new("Frame")
barBG.Position         = UDim2.new(0, 24, 0, 92)
barBG.Size             = UDim2.new(1, -48, 0, 14)
barBG.BackgroundColor3 = Color3.fromRGB(16, 19, 30)
barBG.BorderSizePixel  = 0
barBG.ZIndex           = 3
barBG.Parent           = panel
Instance.new("UICorner", barBG).CornerRadius = UDim.new(1, 0)

local barFill = Instance.new("Frame")
barFill.Size             = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = GREEN
barFill.BorderSizePixel  = 0
barFill.ZIndex           = 4
barFill.Parent           = barBG
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)
local fgrad = Instance.new("UIGradient", barFill)
fgrad.Color = ColorSequence.new(Color3.fromRGB(96, 210, 128), Color3.fromRGB(150, 240, 170))

local barTxt = Instance.new("TextLabel")
barTxt.AnchorPoint            = Vector2.new(1, 0)
barTxt.Position               = UDim2.new(1, -24, 0, 108)
barTxt.Size                   = UDim2.new(0, 200, 0, 20)
barTxt.BackgroundTransparency = 1
barTxt.Font                   = Enum.Font.GothamBold
barTxt.Text                   = ""
barTxt.TextColor3             = TXT_DIM
barTxt.TextSize               = 14
barTxt.TextXAlignment         = Enum.TextXAlignment.Right
barTxt.ZIndex                 = 4
barTxt.Parent                 = panel

-- ===== task list =====
local body = Instance.new("Frame")
body.Position               = UDim2.new(0, 24, 0, 136)
body.Size                   = UDim2.new(1, -48, 1, -216)
body.BackgroundTransparency = 1
body.ZIndex                 = 3
body.Parent                 = panel

local layout = Instance.new("UIListLayout")
layout.Padding   = UDim.new(0, 10)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent    = body

-- ===== bonus strip =====
-- Narrower than full width now: the DAILY REWARD button (the crate) shares this bottom row with it. The two
-- daily things -- the checklist bonus and the daily crate -- were separate More+ entries, which meant a player
-- had to know that "Daily Rewards" and "Daily Tasks" were different menus. They are one row now.
local BONUS_GAP, REWARD_W = 12, 196
local bonus = Instance.new("Frame")
bonus.AnchorPoint      = Vector2.new(0, 1)
bonus.Position         = UDim2.new(0, 24, 1, -20)
bonus.Size             = UDim2.new(1, -48 - REWARD_W - BONUS_GAP, 0, 54)
bonus.BackgroundColor3 = CARD
bonus.BorderSizePixel  = 0
bonus.ZIndex           = 3
bonus.Parent           = panel
Instance.new("UICorner", bonus).CornerRadius = UDim.new(0, 12)
local bstroke = Instance.new("UIStroke", bonus)
bstroke.Color = Color3.fromRGB(60, 70, 100); bstroke.Thickness = 2

local bonusTxt = Instance.new("TextLabel")
bonusTxt.Size                   = UDim2.fromScale(1, 1)
bonusTxt.BackgroundTransparency = 1
bonusTxt.Font                   = Enum.Font.GothamBold
bonusTxt.Text                   = ""
bonusTxt.TextColor3             = TXT_DIM
bonusTxt.TextSize               = 18
bonusTxt.ZIndex                 = 4
bonusTxt.Parent                 = bonus

-- ===== DAILY REWARD (the Mystery Meteor Crate) =====
-- CrateClient owns the crate; it listens on the OpenMeteorCrate BindableEvent, which is exactly what the old
-- "Daily Rewards" More+ entry fired. Firing it from here is the same call -- the entry point moved, the crate
-- did not change. Gold, because it is the one thing in this panel that hands you something immediately.
local rewardBtn = Instance.new("TextButton")
rewardBtn.AnchorPoint      = Vector2.new(1, 1)
rewardBtn.Position         = UDim2.new(1, -24, 1, -20)
rewardBtn.Size             = UDim2.fromOffset(REWARD_W, 54)
rewardBtn.BackgroundColor3 = GOLD
rewardBtn.Font             = Enum.Font.GothamBlack
rewardBtn.Text             = "\u{1F381}  DAILY REWARD"
rewardBtn.TextColor3       = Color3.fromRGB(64, 40, 4)
rewardBtn.TextSize         = 18
rewardBtn.AutoButtonColor  = true
rewardBtn.ZIndex           = 3
rewardBtn.Parent           = panel
Instance.new("UICorner", rewardBtn).CornerRadius = UDim.new(0, 12)
do
	local rs = Instance.new("UIStroke", rewardBtn); rs.Color = GOLD_DK; rs.Thickness = 2
	local rg = Instance.new("UIGradient", rewardBtn); rg.Rotation = 90
	rg.Color = ColorSequence.new(Color3.fromRGB(255, 226, 128), GOLD_DK)
end

-- "!" dot, the same cue the More+ row used to carry, driven by the same _G.crateIsClaimable() CrateClient
-- exposes. It lives ON the button now, so the panel itself tells you whether there is anything to claim.
local rewardDot = Instance.new("Frame")
rewardDot.AnchorPoint      = Vector2.new(1, 0)
rewardDot.Position         = UDim2.new(1, 4, 0, -6)
rewardDot.Size             = UDim2.fromOffset(20, 20)
rewardDot.BackgroundColor3 = Color3.fromRGB(225, 50, 50)
rewardDot.Visible          = false
rewardDot.ZIndex           = 6
rewardDot.Parent           = rewardBtn
Instance.new("UICorner", rewardDot).CornerRadius = UDim.new(1, 0)
do
	local bang = Instance.new("TextLabel")
	bang.BackgroundTransparency = 1; bang.Size = UDim2.fromScale(1, 1)
	bang.Font = Enum.Font.GothamBlack; bang.Text = "!"; bang.TextSize = 14
	bang.TextColor3 = Color3.new(1, 1, 1); bang.ZIndex = 7; bang.Parent = rewardDot
end

-- ============================ open / close ============================

local latest -- last state blob from the server
local MENU_NAME = "DailyTasks"

local function setOpen(open)
	if open and (not latest or latest.show ~= true) then return end -- not eligible -> nothing to open
	if open then
		-- Direct switch: closes any other main menu first, so we can't stack on top of the Shop.
		if _G.MainMenuManager then _G.MainMenuManager.notifyOpened(MENU_NAME) end
		screen.Enabled = true
		-- Pop in. Starting slightly small and settling reads as a panel arriving, not blinking into existence.
		panel.Size = UDim2.new(0, 660, 0, 490)
		TweenService:Create(panel, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 700, 0, 520),
		}):Play()
	else
		screen.Enabled = false
		if _G.MainMenuManager then _G.MainMenuManager.notifyClosed(MENU_NAME) end
	end
end

-- THE DAILY REWARD BUTTON.
--
-- CrateClient's attemptOpen() starts with `if not isClaimable() then return end` -- a SILENT return. So on
-- cooldown, closing this panel and firing the event would look exactly like a broken button: the panel vanishes
-- and nothing happens. So we ask the same question CrateClient asks (its own _G.crateIsClaimable) BEFORE
-- committing: not ready -> stay open and say so on the button itself; ready -> close and fire.
--
-- If _G.crateIsClaimable doesn't exist yet (CrateClient still loading) we fire anyway rather than refusing --
-- CrateClient connects its listener before any blocking wait, and warns for itself if it's not ready.
local rewardBusy = false
rewardBtn.MouseButton1Click:Connect(function()
	if rewardBusy then return end
	local claimable = (_G.crateIsClaimable == nil) or (_G.crateIsClaimable() == true)
	if not claimable then
		-- say it ON the button (this panel has no toast lane of its own), then put it back
		rewardBusy = true
		local was = rewardBtn.Text
		rewardBtn.Text = "\u{23F3}  COME BACK TOMORROW"
		rewardBtn.TextSize = 15
		task.delay(2, function()
			if rewardBtn.Parent then rewardBtn.Text = was; rewardBtn.TextSize = 18 end
			rewardBusy = false
		end)
		return
	end
	-- The crate takes over the screen when it opens, so close this panel first rather than letting the reveal
	-- land on top of it. Firing the event is all CrateClient needs: it creates the BindableEvent and connects
	-- its listener up front (before any blocking WaitForChild), which is the same instance the old More+ row
	-- fired -- so this is the identical entry point, just moved into the panel.
	setOpen(false)
	local ev = ReplicatedStorage:FindFirstChild("OpenMeteorCrate")
	if not ev then
		ev = Instance.new("BindableEvent"); ev.Name = "OpenMeteorCrate"; ev.Parent = ReplicatedStorage
	end
	ev:Fire()
end)

-- keep the "!" dot in step with the crate's cooldown while the panel is open
task.spawn(function()
	while true do
		if screen.Enabled then
			rewardDot.Visible = (_G.crateIsClaimable and _G.crateIsClaimable()) == true
		end
		task.wait(1)
	end
end)

close.MouseButton1Click:Connect(function() setOpen(false) end)
-- NOTE: there is deliberately NO click-outside-to-close handler (matching the Pet Hub). The backdrop spans
-- the whole screen, so a click anywhere off the panel used to slam it shut, which made menus feel like they
-- closed at random. This panel now closes ONLY on an explicit action: its X button, its own toggle, or
-- MainMenuManager closing it because another menu opened.

-- Let the manager slam us shut when another menu opens over us.
--
-- MainMenuManager is created by CoreClient, and LocalScript start order is NOT guaranteed -- if we ran first,
-- a plain `if _G.MainMenuManager then register end` would silently no-op and this panel would then be the one
-- menu the Shop couldn't close, so the two would stack. Wait for it instead.
task.spawn(function()
	for _ = 1, 100 do
		if _G.MainMenuManager then
			_G.MainMenuManager.register(MENU_NAME, function() screen.Enabled = false end)
			return
		end
		task.wait(0.1)
	end
	warn("[DailyTasks] MainMenuManager never appeared -- this panel won't be auto-closed by other menus")
end)

-- ============================ rendering ============================

-- THE INVITE PROMPT. Roblox only exposes this on the client, and gives the server no signal that an invite was
-- actually sent -- so the client has to report it. We report on GameInvitePromptClosed rather than the moment
-- we open it, so at minimum the player did see the invite screen.
local invitePending = false
local function promptInvite()
	if invitePending then return end
	invitePending = true
	local ok = pcall(function()
		-- Not every platform/account can send invites. If it can't, don't open a prompt that will fail.
		if not SocialService:CanSendGameInviteAsync(player) then error("cannot invite") end
		SocialService:PromptGameInvite(player)
	end)
	if not ok then
		invitePending = false
		warn("[DailyTasks] invite prompt unavailable on this client")
	end
end

SocialService.GameInvitePromptClosed:Connect(function(_plr, recipientIds)
	invitePending = false
	-- Tick it whether or not anyone was actually picked: Roblox does not reliably report recipients on every
	-- platform, so requiring a non-empty list would silently break the task for some players.
	if recipientIds ~= nil then
		remote:FireServer("invite")
	end
end)

local function makeCard(i, t)
	-- The invite task is the one you DO from this panel, so its card is a button.
	local card = Instance.new(t.id == "invite" and not t.done and "TextButton" or "Frame")
	card.LayoutOrder      = i
	card.Size             = UDim2.new(1, 0, 0, 66)
	card.BackgroundColor3 = t.done and CARD_DONE or CARD
	card.BorderSizePixel  = 0
	card.ZIndex           = 3
	card.Parent           = body
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	if card:IsA("TextButton") then
		card.Text            = ""
		card.AutoButtonColor = true
		card.MouseButton1Click:Connect(promptInvite)
	end
	local cs = Instance.new("UIStroke", card)
	cs.Color     = t.done and GREEN or Color3.fromRGB(56, 66, 96)
	cs.Thickness = 2
	cs.Transparency = t.done and 0.4 or 0.6

	-- Icon tile
	local tile = Instance.new("TextLabel")
	tile.Position         = UDim2.new(0, 12, 0.5, -21)
	tile.Size             = UDim2.fromOffset(42, 42)
	tile.BackgroundColor3 = t.done and Color3.fromRGB(34, 70, 56) or Color3.fromRGB(44, 52, 78)
	tile.Font             = Enum.Font.GothamBold
	tile.Text             = ICONS[t.id] or "\u{2B50}"
	tile.TextSize         = 24
	tile.BorderSizePixel  = 0
	tile.ZIndex           = 4
	tile.Parent           = card
	Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 10)

	local lbl = Instance.new("TextLabel")
	lbl.Position               = UDim2.new(0, 66, 0, 12)
	lbl.Size                   = UDim2.new(1, -130, 0, 22)
	lbl.BackgroundTransparency = 1
	lbl.Font                   = Enum.Font.GothamBold
	lbl.Text                   = t.label
	lbl.TextColor3             = t.done and TXT_DIM or TXT
	lbl.TextSize               = 18
	lbl.TextXAlignment         = Enum.TextXAlignment.Left
	lbl.TextTruncate           = Enum.TextTruncate.AtEnd
	lbl.ZIndex                 = 4
	lbl.Parent                 = card

	-- The hint is what makes this a GUIDE and not just a scoreboard: it tells you where to go. Once the task
	-- is done the hint is pointless, so it's replaced.
	local hint = Instance.new("TextLabel")
	hint.Position               = UDim2.new(0, 66, 0, 34)
	hint.Size                   = UDim2.new(1, -130, 0, 18)
	hint.BackgroundTransparency = 1
	hint.Font                   = Enum.Font.Gotham
	hint.Text                   = t.done and "Complete" or t.hint
	hint.TextColor3             = t.done and GREEN or TXT_DIM
	hint.TextSize               = 14
	hint.TextXAlignment         = Enum.TextXAlignment.Left
	hint.TextTruncate           = Enum.TextTruncate.AtEnd
	hint.ZIndex                 = 4
	hint.Parent                 = card

	-- Checkbox
	local box = Instance.new("TextLabel")
	box.AnchorPoint      = Vector2.new(1, 0.5)
	box.Position         = UDim2.new(1, -14, 0.5, 0)
	box.Size             = UDim2.fromOffset(32, 32)
	box.BackgroundColor3 = t.done and GREEN or Color3.fromRGB(48, 56, 82)
	box.Font             = Enum.Font.GothamBlack
	box.Text             = t.done and "\u{2713}" or ""
	box.TextColor3       = Color3.fromRGB(14, 30, 20)
	box.TextSize         = 20
	box.BorderSizePixel  = 0
	box.ZIndex           = 4
	box.Parent           = card
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)
end

local function render(data)
	latest = data
	if data.show ~= true then
		screen.Enabled = false -- ineligible (first-ever join) -> the panel simply does not exist for them
		return
	end

	for _, c in ipairs(body:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end

	local done = 0
	for i, t in ipairs(data.tasks) do
		makeCard(i, t)
		if t.done then done = done + 1 end
	end
	local total = #data.tasks

	barTxt.Text = ("%d of %d complete"):format(done, total)
	TweenService:Create(barFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
		Size = UDim2.new(total > 0 and (done / total) or 0, 0, 1, 0),
	}):Play()

	-- STREAK
	local streak = data.streak or 0
	streakTxt.Text = ("\u{1F525} %d"):format(streak)
	if streak > 0 then
		streakBadge.BackgroundColor3 = Color3.fromRGB(74, 46, 24)
		sbStroke.Color               = Color3.fromRGB(232, 138, 54)
		streakTxt.TextColor3         = Color3.fromRGB(255, 186, 96)
	else
		-- Cold badge at zero: nothing to lose yet, so don't pretend there's a fire.
		streakBadge.BackgroundColor3 = Color3.fromRGB(40, 44, 62)
		sbStroke.Color               = Color3.fromRGB(64, 72, 98)
		streakTxt.TextColor3         = TXT_DIM
	end

	if data.bonus then
		bonus.BackgroundColor3 = Color3.fromRGB(34, 68, 48)
		bstroke.Color          = GREEN
		local atCap = (data.maxStreak and streak >= data.maxStreak)
		bonusTxt.Text = atCap
			and ("\u{2713}  Day %d  \u{2014}  +%d coins  (max streak!)"):format(streak, data.bonusCoins)
			-- Tell them what TOMORROW is worth. That's the whole hook: the number they lose by not coming back.
			or ("\u{2713}  Day %d done  \u{2014}  +%d coins  \u{2022}  Tomorrow: +%d"):format(
				streak, data.bonusCoins, data.nextCoins or data.bonusCoins)
		bonusTxt.TextColor3 = GREEN
	elseif done >= total and total > 0 then
		-- Near-invisible in practice: the server pays the bonus the same instant the last task lands.
		bonus.BackgroundColor3 = Color3.fromRGB(66, 56, 26)
		bstroke.Color          = GOLD
		bonusTxt.Text          = ("Bonus ready:  +%d coins"):format(data.bonusCoins)
		bonusTxt.TextColor3    = GOLD
	else
		bonus.BackgroundColor3 = CARD
		bstroke.Color          = GOLD_DK
		bonusTxt.Text          = (streak > 0)
			and ("Finish all %d  \u{2192}  +%d coins  \u{2022}  keep your %d-day streak!"):format(total, data.bonusCoins, streak)
			or  ("Finish all %d tasks  \u{2192}  +%d coins"):format(total, data.bonusCoins)
		bonusTxt.TextColor3 = GOLD
	end
end

-- ============================ the More+ menu talks to us through these ============================

_G.toggleDailyTasks = function()
	setOpen(not screen.Enabled)
end

-- TRUE when this panel can actually open. setOpen() refuses while the server says the player isn't eligible
-- for tasks yet (a brand-new join), and since the daily CRATE now lives inside this panel, the More+ entry has
-- to know that -- otherwise a new player's only route to their crate would silently do nothing.
_G.dailyTasksAvailable = function()
	return (latest ~= nil) and (latest.show == true)
end

-- STALE-DUPLICATE DEFENSE (same pattern SeasonPass uses, and for the same reason). An old baked-in copy of this
-- script is running alongside the Rojo one -- the Output prints "[DailyTasks] panel ready" TWICE from two
-- different line numbers, and both build a ScreenGui called "DailyTasksGui". Whichever loads LAST wins
-- _G.toggleDailyTasks, so More+ can open the stale panel instead -- and the stale panel has no DAILY REWARD
-- button in it, which is exactly "the daily reward button isn't there / doesn't work".
--
-- Destroy any OTHER DailyTasksGui and RE-CLAIM both globals for THIS panel, now and whenever a duplicate turns
-- up later. Targets DailyTasksGui ONLY. (Deleting the stale LocalScript in Studio is the real fix.)
local function claimDailyTasks()
	for _, g in ipairs(gui:GetChildren()) do
		if g ~= screen and g:IsA("ScreenGui") and g.Name == "DailyTasksGui" then
			g:Destroy()
			warn("[DailyTasks] destroyed a STALE duplicate DailyTasksGui -- delete the old LocalScript in Studio")
		end
	end
	_G.toggleDailyTasks    = function() setOpen(not screen.Enabled) end
	_G.dailyTasksAvailable = function() return (latest ~= nil) and (latest.show == true) end
end
task.defer(claimDailyTasks)
gui.ChildAdded:Connect(function(c)
	if c ~= screen and c:IsA("ScreenGui") and c.Name == "DailyTasksGui" then task.defer(claimDailyTasks) end
end)
-- ChildAdded only covers a duplicate that appears AFTER us. A duplicate that loaded first is already parented,
-- so it never fires -- and it can still overwrite _G.toggleDailyTasks a moment after our task.defer ran, since
-- LocalScript start order isn't guaranteed. Re-claim a few times across the first seconds so the last word is
-- always ours; it stops on its own.
task.spawn(function()
	for _ = 1, 5 do          -- 2s apart, so ~10s of cover, then it stops
		task.wait(2)
		pcall(claimDailyTasks)
	end
end)

-- Drives the "!" dot + wiggle on the More+ button. TRUE while any task is still outstanding today.
_G.dailyTasksPending = function()
	if not latest or latest.show ~= true then return false end -- ineligible players get no nagging
	for _, t in ipairs(latest.tasks or {}) do
		if not t.done then return true end
	end
	return false
end

remote.OnClientEvent:Connect(render)
remote:FireServer() -- ask for the current state (we render it hidden, ready for the first open)

print("[DailyTasks] panel ready -- opens from More+ > Daily Tasks (700x520, same frame as the Shop)")
