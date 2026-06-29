-- ============================================================================
-- REWARDS CLIENT — UI for the three RewardsService features:
--   1) CODES        : a "Codes" window (title + TextBox + Redeem + result label). Opened from the
--                     MORE+ menu (CoreClient adds the "Codes" entry, which calls _G.openCodesGui).
--   2) FRIEND BOOST : a small top indicator while the coin boost is active, an auto tip banner every
--                     2 min, and a /friends chat command that shows the tip on demand.
--   3) GROUP PERK   : a group window showing membership + perk. Non-members get a "Join Group" button
--                     (opens the page) and a "Copy Link" button, plus the "rejoin to claim" note.
--
-- All rewards are validated/granted by the server; this script is presentation only.
-- ============================================================================

local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local GuiService       = game:GetService("GuiService")
local player           = Players.LocalPlayer
local playerGui        = player:WaitForChild("PlayerGui")

local RedeemCode      = RS:WaitForChild("RedeemCode", 30)
local CoinBoostState  = RS:WaitForChild("CoinBoostState", 30)
local GroupInfo       = RS:WaitForChild("GroupInfo", 30)
local GetOwnedPets    = (function() local r = RS:WaitForChild("CrateRemotes", 30); return r and r:WaitForChild("GetOwnedPets", 30) end)() -- to tell if a new player still has no pets

-- group info is filled in by the GroupInfo event; sensible fallback so the buttons work even if it's late
local groupState = { isMember = false, groupId = 758781978, url = "https://www.roblox.com/communities/758781978/MLR-Studios" }

-- ---- tiny UI helpers -------------------------------------------------------
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 12) }, o) end
local function stroke(o, c, t) new("UIStroke", { Color = c or Color3.new(1,1,1), Thickness = t or 2 }, o) end

local PINK   = Color3.fromRGB(225, 70, 170)
local GREEN  = Color3.fromRGB(54, 170, 90)
local CREAM  = Color3.fromRGB(255, 247, 230)
local DARK   = Color3.fromRGB(70, 40, 65)

-- =========================== 1) CODES WINDOW ================================
local codesGui = new("ScreenGui", { Name = "CodesGui", ResetOnSpawn = false, DisplayOrder = 130, Enabled = false }, playerGui) -- starts fully CLOSED so its dim scrim never shows at spawn
local codesCatch = new("TextButton", { Size = UDim2.fromScale(1,1), BackgroundColor3 = Color3.new(0,0,0), BackgroundTransparency = 1, Text = "", Visible = false, ZIndex = 1, AutoButtonColor = false }, codesGui) -- click-to-close catcher only; fully transparent (no dark scrim)
local codesPanel = new("Frame", { Size = UDim2.fromOffset(360, 300), Position = UDim2.fromScale(0.5,0.5), AnchorPoint = Vector2.new(0.5,0.5), BackgroundColor3 = Color3.fromRGB(30, 90, 185), Visible = false, ZIndex = 2 }, codesGui)
corner(codesPanel, 16); stroke(codesPanel, CREAM, 3)
new("TextLabel", { Text = "ENTER CODE", Font = Enum.Font.FredokaOne, TextSize = 26, TextColor3 = CREAM, BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 50), Position = UDim2.fromOffset(20, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, codesPanel)
local codesX = new("TextButton", { Text = "X", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = CREAM, BackgroundColor3 = Color3.fromRGB(210, 60, 55), Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -40, 0, 16), ZIndex = 3 }, codesPanel)
corner(codesX, 8)
local codeBox = new("TextBox", { PlaceholderText = "type a code...", Text = "", Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = DARK, BackgroundColor3 = Color3.fromRGB(245, 245, 250), Size = UDim2.new(1, -40, 0, 52), Position = UDim2.fromOffset(20, 78), ClearTextOnFocus = false, ZIndex = 3 }, codesPanel)
corner(codeBox, 10); stroke(codeBox, Color3.fromRGB(20, 60, 130), 2)
local redeemBtn = new("TextButton", { Text = "REDEEM", Font = Enum.Font.FredokaOne, TextSize = 22, TextColor3 = Color3.new(1,1,1), BackgroundColor3 = GREEN, Size = UDim2.new(1, -40, 0, 52), Position = UDim2.fromOffset(20, 146), ZIndex = 3 }, codesPanel)
corner(redeemBtn, 10); stroke(redeemBtn, CREAM, 2)
local codeResult = new("TextLabel", { Text = "", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = CREAM, BackgroundTransparency = 1, TextWrapped = true, Size = UDim2.new(1, -40, 0, 60), Position = UDim2.fromOffset(20, 210), ZIndex = 3 }, codesPanel)

-- Route open/close through the shared main-menu manager (same one Shop / Pet Hub use) so opening Codes hides
-- the bottom HUD (BottomStackGui) and closes any other open menu, and closing it restores the HUD.
local function setCodesOpen(open)
	if open then
		if _G.MainMenuManager then _G.MainMenuManager.notifyOpened("Codes") end -- hides bottom HUD + closes other menus
		codesGui.Enabled = true; codesPanel.Visible = true; codesCatch.Visible = true
		codeResult.Text = ""
	else
		codesGui.Enabled = false; codesPanel.Visible = false; codesCatch.Visible = false
		if _G.MainMenuManager then _G.MainMenuManager.notifyClosed("Codes") end  -- restores bottom HUD (if no other menu open)
	end
end
-- register a full-hide fn so opening Shop/Pets over Codes closes Codes too (manager exists once CoreClient/Shop loads)
task.spawn(function()
	while not _G.MainMenuManager do task.wait(0.1) end
	_G.MainMenuManager.register("Codes", function() codesGui.Enabled = false; codesPanel.Visible = false; codesCatch.Visible = false end)
end)
codesCatch.MouseButton1Click:Connect(function() setCodesOpen(false) end)
codesX.MouseButton1Click:Connect(function() setCodesOpen(false) end)

local redeeming = false
local function doRedeem()
	if redeeming then return end
	local code = codeBox.Text
	if code:gsub("%s+", "") == "" then codeResult.TextColor3 = Color3.fromRGB(255, 220, 120); codeResult.Text = "Enter a code"; return end
	redeeming = true
	codeResult.TextColor3 = CREAM; codeResult.Text = "Checking..."
	task.spawn(function()
		local ok, res = pcall(function() return RedeemCode:InvokeServer(code) end)
		redeeming = false
		if ok and type(res) == "table" then
			codeResult.TextColor3 = res.ok and Color3.fromRGB(150, 255, 170) or Color3.fromRGB(255, 150, 150)
			codeResult.Text = res.msg or (res.ok and "Code redeemed!" or "Invalid code")
			if res.ok then codeBox.Text = "" end
		else
			codeResult.TextColor3 = Color3.fromRGB(255, 150, 150); codeResult.Text = "Something went wrong, try again"
		end
	end)
end
redeemBtn.MouseButton1Click:Connect(doRedeem)
codeBox.FocusLost:Connect(function(enter) if enter then doRedeem() end end)
_G.openCodesGui = function() setCodesOpen(true) end

-- =========================== 3) GROUP WINDOW ================================
local groupGui = new("ScreenGui", { Name = "GroupPerkGui", ResetOnSpawn = false, DisplayOrder = 130, Enabled = false }, playerGui) -- starts CLOSED; never enabled for group members (see setGroupOpen)
local groupCatch = new("TextButton", { Size = UDim2.fromScale(1,1), BackgroundColor3 = Color3.new(0,0,0), BackgroundTransparency = 0.5, Text = "", Visible = false, ZIndex = 1, AutoButtonColor = false }, groupGui)
local groupPanel = new("Frame", { Size = UDim2.fromOffset(380, 320), Position = UDim2.fromScale(0.5,0.5), AnchorPoint = Vector2.new(0.5,0.5), BackgroundColor3 = Color3.fromRGB(40, 40, 55), Visible = false, ZIndex = 2 }, groupGui)
corner(groupPanel, 16); stroke(groupPanel, CREAM, 3)
new("TextLabel", { Text = "MLR STUDIOS GROUP", Font = Enum.Font.FredokaOne, TextSize = 24, TextColor3 = CREAM, BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 44), Position = UDim2.fromOffset(20, 12), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, groupPanel)
local groupX = new("TextButton", { Text = "X", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = CREAM, BackgroundColor3 = Color3.fromRGB(210, 60, 55), Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -40, 0, 14), ZIndex = 3 }, groupPanel)
corner(groupX, 8)
local groupStatus = new("TextLabel", { Text = "", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = CREAM, BackgroundTransparency = 1, TextWrapped = true, Size = UDim2.new(1, -40, 0, 70), Position = UDim2.fromOffset(20, 60), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3 }, groupPanel)
local joinBtn = new("TextButton", { Text = "JOIN GROUP", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = Color3.new(1,1,1), BackgroundColor3 = GREEN, Size = UDim2.new(1, -40, 0, 46), Position = UDim2.fromOffset(20, 136), ZIndex = 3 }, groupPanel)
corner(joinBtn, 10); stroke(joinBtn, CREAM, 2)
local urlBox = new("TextBox", { Text = groupState.url, Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = DARK, BackgroundColor3 = Color3.fromRGB(245,245,250), TextWrapped = true, ClearTextOnFocus = false, TextEditable = true, Size = UDim2.new(1, -40, 0, 50), Position = UDim2.fromOffset(20, 192), ZIndex = 3 }, groupPanel)
corner(urlBox, 8)
local copyBtn = new("TextButton", { Text = "COPY LINK", Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = DARK, BackgroundColor3 = Color3.fromRGB(255, 210, 90), Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 250), ZIndex = 3 }, groupPanel)
corner(copyBtn, 10); stroke(copyBtn, Color3.fromRGB(180, 140, 40), 2)

local function refreshGroupPanel()
	if groupState.isMember then
		groupStatus.Text = "You're a member — +10% coins active! \xE2\x9C\x85"
		joinBtn.Visible = false; urlBox.Visible = false; copyBtn.Visible = false
		groupPanel.Size = UDim2.fromOffset(380, 150)
	else
		groupStatus.Text = "Join MLR Studios for a permanent +10% coin perk (stacks with the friend boost).\nJoin the group, then REJOIN the game to claim."
		joinBtn.Visible = true; urlBox.Visible = true; copyBtn.Visible = true; urlBox.Text = groupState.url
		groupPanel.Size = UDim2.fromOffset(380, 310)
	end
end
local function setGroupOpen(open)
	-- MEMBERS never see this window (or its dim scrim) at all -- the perk is already applied for them.
	if open and groupState.isMember then groupGui.Enabled = false; groupPanel.Visible = false; groupCatch.Visible = false; return end
	refreshGroupPanel()
	groupGui.Enabled = open                          -- whole ScreenGui off when closed -> no scrim renders
	groupPanel.Visible = open; groupCatch.Visible = open
end
groupCatch.MouseButton1Click:Connect(function() setGroupOpen(false) end)
groupX.MouseButton1Click:Connect(function() setGroupOpen(false) end)
joinBtn.MouseButton1Click:Connect(function()
	pcall(function() GuiService:OpenBrowserWindow(groupState.url) end) -- opens the group page in a browser (desktop)
end)
copyBtn.MouseButton1Click:Connect(function()
	-- Roblox has no player-clipboard API, so best-effort: try an exploit-free clipboard if present, then
	-- highlight the URL text so the player can copy it manually (Ctrl+C / long-press).
	pcall(function() if setclipboard then setclipboard(groupState.url) end end)
	urlBox:CaptureFocus()
	pcall(function() urlBox.CursorPosition = #urlBox.Text + 1; urlBox.SelectionStart = 1 end)
	copyBtn.Text = "LINK HIGHLIGHTED \xE2\x80\x94 COPY IT"
	task.delay(2.5, function() if copyBtn.Parent then copyBtn.Text = "COPY LINK" end end)
end)
_G.openGroupGui = function() setGroupOpen(true) end

-- NOTE: the old always-on "+X% Coins" top pill was REMOVED. The coin boost is no longer a persistent HUD
-- element stuck across the top of the screen. The friend/group perks are surfaced ONLY via the periodic,
-- lowest-priority reminder banners below. (If you want a passive "perk active" indicator, add a small icon to
-- the STATS/PERKS panel — never a banner pinned to the top.) CoinBoostState is left wired for that future use.

GroupInfo.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then return end
	groupState.isMember = info.isMember == true
	if info.url then groupState.url = info.url end
	if info.groupId then groupState.groupId = info.groupId end
	if groupState.isMember then
		groupGui.Enabled = false; groupPanel.Visible = false; groupCatch.Visible = false -- members: keep it fully closed
	elseif groupPanel.Visible then
		refreshGroupPanel()
	end
end)

-- ============== 2)+3) SHARED BANNER SCHEDULER (no overlap, event-gated) ======
-- One banner frame, one queue. The three recurring reminders (friend / daily / group) and /friends all
-- go through enqueueBanner(); only ONE shows at a time and none show while a big event is active/imminent
-- or while a full-screen UI moment (loading screen, crate reveal) is up.
local bannerGui = new("ScreenGui", { Name = "ReminderBannerGui", ResetOnSpawn = false, DisplayOrder = 140, IgnoreGuiInset = true }, playerGui)
local banner = new("Frame", { BackgroundColor3 = Color3.fromRGB(40, 120, 70), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -80), Size = UDim2.fromOffset(560, 54), ZIndex = 5 }, bannerGui)
corner(banner, 14); stroke(banner, CREAM, 2)
local bannerText = new("TextLabel", { Text = "", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = CREAM, BackgroundTransparency = 1, TextScaled = true, Size = UDim2.new(1, -24, 1, -12), Position = UDim2.fromOffset(12, 6), ZIndex = 6 }, banner)
new("UITextSizeConstraint", { MaxTextSize = 22 }, bannerText)
-- a transparent button over the whole banner so a tappable banner (e.g. the group one) can open something
local bannerBtn = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Visible = false, Active = false, ZIndex = 7 }, banner)
local currentOnClick = nil
bannerBtn.Activated:Connect(function() local f = currentOnClick; if f then f() end end)

-- ---- the reusable "is it safe to show a banner right now?" gate ----
local SoundService = game:GetService("SoundService")
local bigFlag
task.spawn(function()
	local grp = SoundService:WaitForChild("BackgroundMusic", 60)
	bigFlag = grp and grp:WaitForChild("BigEventActive", 60) -- replicated big-event-active BoolValue (MusicManager)
end)
local function eventUIShowing()
	-- treat an event as "active or about to start" if its banner/countdown UI is currently up
	for _, n in ipairs({ "RocketEventUI", "MeteorEventUI" }) do
		local g = playerGui:FindFirstChild(n)
		if g and g.Enabled then
			local b, c = g:FindFirstChild("Banner"), g:FindFirstChild("Countdown")
			if (b and b.Visible) or (c and c.Visible) then return true end
		end
	end
	return false
end
-- Reward/toast/reveal popups that TOGGLE their ScreenGui.Enabled when shown (created Enabled=false), so a
-- simple Enabled check is reliable (no false "always blocking"). The reminders defer to all of these.
local BLOCKER_TOGGLE_GUIS = { "GardenToast", "GardenRewardGui", "CoconutCrackGui", "FilmReelSpinGui", "ButterReelGui", "FishReelGui" }

-- THE GATE: reminders are the LOWEST priority -> only show when the screen is CLEAR of everything else.
local function isSafeToShowBanner()
	-- (one-at-a-time is enforced by pumpBanners' own bannerShowing check before it calls this)
	if bigFlag and bigFlag.Value then return false end           -- a big event is running
	if eventUIShowing() then return false end                    -- a big event is starting / its banner is up
	if playerGui:FindFirstChild("LoadingScreen") then return false end -- still loading
	for _, g in ipairs(playerGui:GetChildren()) do               -- the one-time Garden cinematic (cover/title/skip)
		if g:IsA("ScreenGui") and g.Name:sub(1, 11) == "GardenIntro" then return false end
	end
	local reveal = playerGui:FindFirstChild("MeteorCrateReveal")  -- daily-crate reveal open
	if reveal then
		local dim = reveal:FindFirstChild("Dim")
		if dim and dim.Visible and dim.BackgroundTransparency < 1 then return false end
	end
	-- a MENU is open: food/premium/stomach(+Skins)/pets/codes route through the shared manager; the group window doesn't
	if _G.MainMenuManager and _G.MainMenuManager.current ~= nil then return false end
	if (groupGui and groupGui.Enabled) or (codesGui and codesGui.Enabled) then return false end
	-- any toast / reward popup currently shown
	for _, n in ipairs(BLOCKER_TOGGLE_GUIS) do
		local g = playerGui:FindFirstChild(n)
		if g and g:IsA("ScreenGui") and g.Enabled then return false end
	end
	return true
end

-- ---- one-at-a-time queue ----
local bannerQueue, bannerShowing = {}, false
local function displayBanner(spec, onDone)
	bannerText.Text = spec.text
	currentOnClick = spec.onClick                              -- tappable banners (e.g. group) open something
	bannerBtn.Visible = spec.onClick ~= nil; bannerBtn.Active = spec.onClick ~= nil
	banner.Position = UDim2.new(0.5, 0, 0, -80)
	TweenService:Create(banner, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 50) }):Play()
	task.delay(4.5, function()
		TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 0, -80) }):Play()
		task.delay(0.45, function() currentOnClick = nil; bannerBtn.Visible = false; bannerBtn.Active = false; if onDone then onDone() end end)
	end)
end
local pumpBanners
pumpBanners = function()
	if bannerShowing or #bannerQueue == 0 then return end
	if not isSafeToShowBanner() then task.delay(5, pumpBanners); return end -- HOLD: anything higher-priority up -> retry soon
	local spec = table.remove(bannerQueue, 1)
	bannerShowing = true
	displayBanner(spec, function() bannerShowing = false; task.defer(pumpBanners) end)
end
local function enqueueBanner(text, key, onClick)
	for _, s in ipairs(bannerQueue) do if s.key == key then return end end -- never stack duplicates of the same reminder
	bannerQueue[#bannerQueue + 1] = { text = text, key = key, onClick = onClick }
	pumpBanners()
end
-- exposed so other systems (e.g. GutSkinClient skin-unlock banners) share this one no-overlap, event-gated queue
_G.enqueueReminderBanner = enqueueBanner

-- ---- reminder text + eligibility ----
local FRIEND_TEXT = "\xF0\x9F\x91\xAB Have a friend in the server? You BOTH earn +25% coins!"
local GROUP_TEXT  = "\xF0\x9F\x91\xA5 Join the MLR Studios group for +10% coins \xE2\x80\x94 tap to join!"
local DAILY_TEXT  = "\xF0\x9F\x8E\x81 Claim your FREE Daily Reward from the More menu!"

local petCache = false -- last-known "has at least one pet"
local function playerHasPet()
	if not GetOwnedPets then return petCache end
	local ok, list = pcall(function() return GetOwnedPets:InvokeServer() end)
	if ok and type(list) == "table" then petCache = (#list > 0) end
	return petCache
end
local function friendEligible() return true end                                 -- general tip, always
local function groupEligible()  return not groupState.isMember end              -- only nag non-members
local function dailyEligible()                                                  -- new player: no pets AND reward unclaimed
	local claimable = (_G.crateIsClaimable and _G.crateIsClaimable()) == true
	return claimable and not playerHasPet()
end

-- the group reminder banner opens the join window (with the Join + Copy-link buttons) when tapped
local function showGroupBanner() enqueueBanner(GROUP_TEXT, "group", function() if _G.openGroupGui then _G.openGroupGui() end end) end

-- Each reminder is its OWN paced loop. The single-banner queue + "screen clear" gate still guarantee they
-- never overlap each other OR any event/menu/popup -- a faster cadence just means it waits its turn.
-- FRIEND: a general nudge every 6 minutes.
task.spawn(function()
	task.wait(45)
	while true do
		if friendEligible() then enqueueBanner(FRIEND_TEXT, "friend") end
		task.wait(360)
	end
end)
-- DAILY: every 3 minutes, but ONLY while a daily reward is actually ready (and the player has no pet yet).
-- The task.wait(180) floor means it can never fire faster than once every 3 minutes.
task.spawn(function()
	task.wait(60)
	while true do
		if dailyEligible() then enqueueBanner(DAILY_TEXT, "daily") end -- dailyEligible() = crate claimable + no pet
		task.wait(180) -- 3 minutes
	end
end)

-- ---- group: its OWN banner every 10 minutes, ONLY until the player joins the MLR group ----
-- (no HUD button anymore; this tappable banner is the prompt. Stops once groupState.isMember is true.)
task.spawn(function()
	task.wait(60) -- settle-in delay
	while true do
		if groupEligible() then showGroupBanner() end -- groupEligible() = not a member -> gone once they join
		task.wait(600) -- 10 minutes
	end
end)

-- chat commands to show a reminder on demand: /friends (friend tip) and /group (group banner, for testing).
-- Both still route through the gate/queue. The /group banner is tappable -> opens the join window.
local function handleFriendsCmd() enqueueBanner(FRIEND_TEXT, "friend") end
local function handleGroupCmd() showGroupBanner() end
pcall(function()
	local TextChatService = game:GetService("TextChatService")
	local cmds = TextChatService:WaitForChild("TextChatCommands", 10) -- default container under TextChatService
	if cmds then
		local f = Instance.new("TextChatCommand"); f.Name = "FriendsCommand"; f.PrimaryAlias = "/friends"; f.Parent = cmds
		f.Triggered:Connect(handleFriendsCmd)
		local g = Instance.new("TextChatCommand"); g.Name = "GroupCommand"; g.PrimaryAlias = "/group"; g.Parent = cmds
		g.Triggered:Connect(handleGroupCmd)
	end
end)
pcall(function()
	player.Chatted:Connect(function(msg)
		local m = msg:lower():gsub("%s+", "")
		if m == "/friends" then handleFriendsCmd() elseif m == "/group" then handleGroupCmd() end
	end)
end)

print("[RewardsClient] ready (codes, group banner, shared banner scheduler, /friends, /group)")
