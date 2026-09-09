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
local CheckGroupNow   = RS:WaitForChild("CheckGroupNow", 30) -- ask the server to RE-READ group membership (no rejoin)
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
-- NOTE: the catcher deliberately does NOT close the window any more -- it only swallows clicks that land off
-- the panel. A tap-outside-to-close on a window with a TEXT BOX in it is especially bad: tapping past the box
-- to dismiss the on-screen keyboard would throw away a half-typed code. The X is the way out.
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
local groupCatch = new("TextButton", { Size = UDim2.fromScale(1,1), BackgroundTransparency = 1, Text = "", Visible = false, ZIndex = 1, AutoButtonColor = false }, groupGui) -- click-catcher only; no dark scrim
local groupPanel = new("Frame", { Size = UDim2.fromOffset(700, 520), Position = UDim2.fromScale(0.5,0.5), AnchorPoint = Vector2.new(0.5,0.5), BackgroundColor3 = Color3.fromRGB(40, 40, 55), Visible = false, ZIndex = 2 }, groupGui)
corner(groupPanel, 16); stroke(groupPanel, CREAM, 3)
-- MOBILE FIT: same rule as the minigame cards -- a fixed 700x520 panel must scale itself down on phones or
-- it hangs off both edges of a 360-tall screen. 92% of the viewport, never above 1.
do
	local gscale = Instance.new("UIScale"); gscale.Parent = groupPanel
	local function gfit()
		local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
		gscale.Scale = math.clamp(math.min(vp.X * 0.92 / 700, vp.Y * 0.92 / 520), 0.4, 1)
	end
	gfit()
	pcall(function() workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(gfit) end)
end
new("TextLabel", { Text = "MLR STUDIOS GROUP", Font = Enum.Font.FredokaOne, TextSize = 24, TextColor3 = CREAM, BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 44), Position = UDim2.fromOffset(20, 12), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, groupPanel)
local groupX = new("TextButton", { Text = "X", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = CREAM, BackgroundColor3 = Color3.fromRGB(210, 60, 55), Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -40, 0, 14), ZIndex = 3 }, groupPanel)
corner(groupX, 8)
local groupStatus = new("TextLabel", { Text = "", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = CREAM, BackgroundTransparency = 1, TextWrapped = true, Size = UDim2.new(1, -80, 0, 110), Position = UDim2.fromOffset(40, 120), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3 }, groupPanel)
local joinBtn = new("TextButton", { Text = "JOIN GROUP", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = Color3.new(1,1,1), BackgroundColor3 = GREEN, Size = UDim2.new(1, -80, 0, 56), Position = UDim2.fromOffset(40, 250), ZIndex = 3 }, groupPanel)
corner(joinBtn, 10); stroke(joinBtn, CREAM, 2)
local urlBox = new("TextBox", { Text = groupState.url, Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = DARK, BackgroundColor3 = Color3.fromRGB(245,245,250), TextWrapped = true, ClearTextOnFocus = false, TextEditable = true, Size = UDim2.new(1, -80, 0, 56), Position = UDim2.fromOffset(40, 326), ZIndex = 3 }, groupPanel)
corner(urlBox, 8)
local copyBtn = new("TextButton", { Text = "COPY LINK", Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = DARK, BackgroundColor3 = Color3.fromRGB(255, 210, 90), Size = UDim2.new(1, -80, 0, 52), Position = UDim2.fromOffset(40, 400), ZIndex = 3 }, groupPanel)
corner(copyBtn, 10); stroke(copyBtn, Color3.fromRGB(180, 140, 40), 2)

local function refreshGroupPanel()
	if groupState.isMember then
		groupStatus.Text = "You're a member — +10% coins active! \xE2\x9C\x85"
		joinBtn.Visible = false; urlBox.Visible = false; copyBtn.Visible = false
		groupPanel.Size = UDim2.fromOffset(700, 520)
	else
		groupStatus.Text = "Join MLR Studios for a permanent +10% coin perk (stacks with the friend boost).\nJoin the group, then REJOIN the game to claim."
		joinBtn.Visible = true; urlBox.Visible = true; copyBtn.Visible = true; urlBox.Text = groupState.url
		groupPanel.Size = UDim2.fromOffset(700, 520)
	end
end
local function setGroupOpen(open)
	-- MEMBERS never see this window (or its dim scrim) at all -- the perk is already applied for them.
	if open and groupState.isMember then groupGui.Enabled = false; groupPanel.Visible = false; groupCatch.Visible = false; return end
	refreshGroupPanel()
	if open and not groupState.isMember then joinBtn.Text = "JOIN GROUP" end -- fresh open = fresh prompt
	groupGui.Enabled = open                          -- whole ScreenGui off when closed -> no scrim renders
	groupPanel.Visible = open; groupCatch.Visible = open
end
groupCatch.MouseButton1Click:Connect(function() setGroupOpen(false) end)
groupX.MouseButton1Click:Connect(function() setGroupOpen(false) end)
-- ===== JOIN GROUP, WITHOUT LEAVING THE GAME =====
-- Roblox has NO API that can join a group for a player -- no experience can do it, and this button never
-- could. What it can do is open the group page in the IN-EXPERIENCE browser overlay (so the player never
-- alt-tabs or closes the game), and then notice on its own that they joined.
--
-- Noticing is the part that used to be broken. The server checked membership once, on join, through
-- Player:IsInGroup(), which caches for the whole session -- so someone who joined the group thirty seconds
-- ago still read as a non-member and the panel told them to REJOIN THE GAME. The server now re-reads it
-- live (RewardsService.CheckGroupNow -> Shared.GroupMembership, which uses GroupService:GetGroupsAsync and
-- is not cached), so all this has to do is ask a few times while the panel is open.
--
-- The poll is bounded and slow on purpose: every ask is a web request on the server. POLL_EVERY is above the
-- module's own 4s rate limit, and the whole thing stops on success, when the panel closes, or after
-- POLL_FOR seconds -- after which the button is still there to press manually.
local POLL_EVERY, POLL_FOR = 5, 120
local pollToken = 0 -- bumped to cancel the previous poll; a stale loop sees the change and exits

local function askServerAmIIn()
	local res
	local ok = pcall(function() res = CheckGroupNow:InvokeServer() end)
	return ok and type(res) == "table" and res.isMember == true
end

-- Confirmed: flip the panel over to the member state and say so, once.
local function onConfirmedMember()
	groupState.isMember = true
	joinBtn.Text = "JOIN GROUP"
	refreshGroupPanel()
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(function()
			_G.NotifyCenter.push({
				top = "GROUP JOINED", text = "+10% COINS FOR JOINING!",
				color = Color3.fromRGB(90, 200, 110), priority = _G.NotifyCenter.PRIORITY.REWARD, duration = 4,
			})
		end)
	end
end

local function startPolling()
	pollToken = pollToken + 1
	local mine = pollToken
    task.spawn(function()
		local waited = 0
		while waited < POLL_FOR do
			task.wait(POLL_EVERY)
			waited = waited + POLL_EVERY
			if pollToken ~= mine then return end            -- superseded by a newer press
			if groupState.isMember then return end          -- the server told us via GroupInfo already
			if not groupPanel.Visible then return end       -- panel closed: stop spending web calls
			if askServerAmIIn() then
				if pollToken == mine then onConfirmedMember() end
				return
			end
		end
		-- Window lapsed without a yes. Leave the button in its "check" state so a slow joiner can still
		-- confirm by hand -- never claim they failed, they may simply have taken their time.
		if pollToken == mine and not groupState.isMember and groupPanel.Visible then
			joinBtn.Text = "I JOINED â CHECK AGAIN"
		end
	end)
end

joinBtn.MouseButton1Click:Connect(function()
	-- Second and later presses are a manual "check me now" -- the page is already open behind the panel.
	if joinBtn.Text ~= "JOIN GROUP" then
		joinBtn.Text = "CHECKINGâ¦"
		task.spawn(function()
			local yes = askServerAmIIn()
			if yes then onConfirmedMember()
			else joinBtn.Text = "I JOINED â CHECK AGAIN" end
		end)
		return
	end
	pcall(function() GuiService:OpenBrowserWindow(groupState.url) end) -- in-experience overlay, not a real browser tab
	joinBtn.Text = "CHECKINGâ¦"
	startPolling()
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

-- GroupInfo comes from a WaitForChild WITH A TIMEOUT, so it is nil-able by design and every use of it has to
-- say so. It WAS nil in practice: RewardsService (its only creator) yielded forever on Shared.GroupMembership,
-- which was missing from the Rojo project, so the remote was never created and this line took the whole script
-- down with "attempt to index nil with 'OnClientEvent'" -- killing every reward banner below it, not just the
-- group one.
--
-- That mapping is fixed, so it should arrive now. The guard stays regardless: a client that loses a race
-- against a slow server should quietly do without the group perk, never lose the rest of its rewards UI.
if not GroupInfo then
	warn("[Rewards] GroupInfo remote never arrived -- group perks are off this session. RewardsService creates "
		.. "it; if that script is stuck, check ReplicatedStorage.Shared.GroupMembership exists.")
end
if GroupInfo then GroupInfo.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then return end
	groupState.isMember = info.isMember == true
	if info.url then groupState.url = info.url end
	if info.groupId then groupState.groupId = info.groupId end
	if groupState.isMember then
		groupGui.Enabled = false; groupPanel.Visible = false; groupCatch.Visible = false -- members: keep it fully closed
	elseif groupPanel.Visible then
		refreshGroupPanel()
	end
end) end

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
	-- ===== THE ONBOARDING DIRECTIONS OWN THE SCREEN UNTIL THEY ARE DONE =====
	-- While the tutorial arrows are guiding a brand-new player ("go to the Gardener", then "go to the food
	-- stand"), a Daily Rewards nag popping over the top is the worst possible timing: it lands on the exact
	-- player who has no idea what any of it means yet, and it competes with the one instruction they are
	-- supposed to be following.
	--
	-- GardenGuideTrail publishes the live step here: "gardener" / "stand" while directions are running, and
	-- nil the moment BOTH legs are done (or the player flies, which also graduates them). Non-nil = the
	-- directions are still on screen, so every reminder banner waits. They are not lost -- pumpBanners
	-- re-checks this gate on its own timer and shows them once the player is through.
	if _G.gardenGuideStep ~= nil then return false end
	local reveal = playerGui:FindFirstChild("MeteorCrateReveal")  -- daily-crate reveal open
	if reveal then
		-- The Dim is a click-catcher with NO tint now, so "reveal open" is signalled by Visible alone --
		-- its transparency is permanently 1 and can no longer carry that information.
		local dim = reveal:FindFirstChild("Dim")
		if dim and dim.Visible then return false end
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
-- Rendered by NotifyCenter's HERO lane, not by this file's own banner frame. That frame rested at
-- UDim2.new(0.5,0,0,50) and is 54px tall, so it occupied y 50..104 -- straight through the ObjectiveHUD
-- card (y 85..163). And these reminders (daily-reward nag, friend tip) target new players, who are
-- exactly the ones with the objective card on screen: a guaranteed, repeating collision.
-- Priority REWARD means a real island unlock or purchase preempts the nag instead of stacking on it.
-- onDone is what advances pumpBanners, so it must fire on every path -- NotifyCenter guarantees that.
local function displayBanner(spec, onDone)
	local NC = _G.NotifyCenter
	if not NC then if onDone then onDone() end return end
	NC.push({
		text     = spec.text,
		color    = Color3.fromRGB(40, 120, 70),
		priority = NC.PRIORITY.REWARD,
		duration = spec.duration or 4.5, -- per-banner: a one-line tip reads in 4.5s, a "where to find it" tip does not
		onClick  = spec.onClick, -- tappable banners (e.g. group) open something
		onDone   = onDone,
	})
end
local pumpBanners
pumpBanners = function()
	if bannerShowing or #bannerQueue == 0 then return end
	if not isSafeToShowBanner() then task.delay(5, pumpBanners); return end -- HOLD: anything higher-priority up -> retry soon
	local spec = table.remove(bannerQueue, 1)
	bannerShowing = true
	displayBanner(spec, function() bannerShowing = false; task.defer(pumpBanners) end)
end
local function enqueueBanner(text, key, onClick, duration)
	for _, s in ipairs(bannerQueue) do if s.key == key then return end end -- never stack duplicates of the same reminder
	bannerQueue[#bannerQueue + 1] = { text = text, key = key, onClick = onClick, duration = duration }
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
-- DAILY REMINDER: REMOVED. It fired every 3 minutes telling the player to "claim your FREE Daily Reward
-- from the More menu", and it was the most repetitive thing on screen -- a nag pointing at a button that is
-- already sitting in the HUD with its own ready-dot. The reward itself is untouched: it is still claimable
-- from More+ > Rewards, the ready-dot still marks it, and _G.crateIsClaimable is still what the rest of the
-- game asks. Only the recurring banner is gone.
--
-- DAILY_TEXT / dailyEligible / playerHasPet are deliberately KEPT above rather than deleted: they are the
-- whole "is a daily reward waiting for a new player" test, and re-adding a prompt later (a one-shot on
-- first join, say) should not mean rewriting it from scratch.

-- ---- group: its OWN banner every 10 minutes, ONLY until the player joins the MLR group ----
-- (no HUD button anymore; this tappable banner is the prompt. Stops once groupState.isMember is true.)
task.spawn(function()
	task.wait(60) -- settle-in delay
	while true do
		if groupEligible() then showGroupBanner() end -- groupEligible() = not a member -> gone once they join
		task.wait(600) -- 10 minutes
	end
end)

-- ---- WORMHOLE: the one reminder that never retires ----
-- Every OTHER prompt here has an off switch -- the group one stops when they join, the daily one stopped
-- because it was nagging about a button that already has a ready-dot. This one runs for the whole session
-- on purpose: the wormhole is a menu entry with no world presence at all, it moved out of the button rail
-- into MORE+, and a player who never opens MORE+ will finish the game without ever learning it exists.
--
-- FAST AT FIRST, THEN BACKS OFF. Every 3 minutes for the first half hour, every 10 after that. The early
-- pace is aimed at the exact window where knowing about fast-travel changes how the game feels -- the
-- stretch where you are re-climbing islands you already own -- and the late pace is a footnote for anyone
-- still playing two hours in. It never stops entirely because there is nothing to detect: no flag says
-- "this player understands the wormhole", so backing off is the honest version of giving up on them.
--
-- It shares the same queue and screen-clear gate as everything else here, so a faster cadence only ever
-- means it waits its turn behind a real unlock, an event, or an open menu.
local WORMHOLE_TEXT       = "\xF0\x9F\x8C\x80 WORMHOLE is in the MORE+ menu -- warp straight to any island you've unlocked!"
local WORMHOLE_EARLY_GAP  = 180  -- 3 minutes...
local WORMHOLE_LATE_GAP   = 600  -- ...then 10
local WORMHOLE_EARLY_FOR  = 1800 -- for the first 30 minutes of the session

-- Tapping it opens the wormhole menu, so the reminder is also the shortcut -- being told where a thing is
-- and being taken there are very different amounts of work for the player.
local function showWormholeBanner()
	-- 8 SECONDS, not the usual 4.5. This banner is doing more work than the others: it names a thing, says
	-- where the thing lives, and says what it does. Read that at a glance while flying and 4.5s is a blur --
	-- and it is the one banner you can act on, so it has to still be there when you reach for it.
	enqueueBanner(WORMHOLE_TEXT, "wormhole", function()
		if _G.toggleWormhole then _G.toggleWormhole() end
	end, 8)
end

task.spawn(function()
	local elapsed = 90
	task.wait(elapsed) -- let them land and fly once before the first tip
	while true do
		showWormholeBanner()
		local gap = (elapsed < WORMHOLE_EARLY_FOR) and WORMHOLE_EARLY_GAP or WORMHOLE_LATE_GAP
		task.wait(gap)
		elapsed += gap
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

print("[RewardsClient] ready (codes, group banner, wormhole reminder 3min-then-10min, shared banner scheduler, /friends, /group)")
