--======================================================================
-- Gifting.client.lua  (LocalScript)
--======================================================================
-- The GIFT panel: pick someone in the server, pick an amount, send them Crate Tokens. And -- the half that
-- actually matters -- the moment where you RECEIVE one.
--
-- Receiving an unprompted present from another kid is the single warmest thing that can happen in a game like
-- this, so it gets a real moment rather than a line of chat: a gold banner with the sender's name on it, a
-- reward sound, and the token count going up while they watch.
--
-- ===== IT OPENS FROM MORE+ =====
-- The Gift card lives in RailGuard's MORE+ grid, which is where the other "sometimes" doors already are
-- (Rebirth, Rewards, Wormhole) -- and it is what finally makes that grid a real 2x2 instead of three cards
-- and a hole. Not the rail: RailGuard locks the rail to four buttons and actively retires anything else.
--
-- RailGuard calls _G.openGiftPanel, which OPENS rather than toggles: a card in that menu always means "show
-- me this", and a toggle would read as a dead button whenever the panel happened to be enabled already.
-- MORE+ is the only entrance: no hidden gestures elsewhere in the HUD.
--
-- ===== THE PANEL FOLLOWS THE HOUSE RULES =====
-- Fixed 700x520, bright blue/white/gold, and the X button is the ONLY way to close it -- no backdrop-click
-- dismissal, because a stray tap closing a panel mid-decision is the thing this codebase has repeatedly and
-- deliberately designed out.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

if _G.__GiftingClient then
	warn("[Gifting] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__GiftingClient = true

--======================================================================
-- LOOK  (the house palette)
--======================================================================
local BLUE   = Color3.fromRGB(30, 140, 255)
local BLUE_D = Color3.fromRGB(18, 92, 190)
local GOLD   = Color3.fromRGB(255, 206, 92)
local GOLD_D = Color3.fromRGB(226, 158, 30)
local GREEN  = Color3.fromRGB(72, 190, 96)
local RED    = Color3.fromRGB(210, 70, 70)
local CREAM  = Color3.fromRGB(255, 250, 236)
local LIME   = Color3.fromRGB(126, 224, 110)
local INK    = Color3.fromRGB(16, 44, 96)

-- These MUST match Gifting.server's MIN_GIFT / MAX_GIFT. They are duplicated here rather than fetched
-- because the client only uses them to be POLITE -- to grey out an impossible amount before the player
-- presses send. The server re-checks every one of them and is the only authority; if these drift, the worst
-- case is a friendly message that turns out to be wrong, not a gift that shouldn't have happened.
local MIN_GIFT = 10
local MAX_GIFT = 500
local AMOUNTS  = { 10, 25, 50, 100, 250, 500 }   -- quick picks, all inside MIN_GIFT..MAX_GIFT

local function corner(g, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = g end
local function stroke(g, col, th)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th or 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = g; return s
end
local function text(parent, str, size, colour)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextSize = size
	t.TextColor3 = colour or CREAM
	t.Text = str
	t.Parent = parent
	local st = Instance.new("UIStroke"); st.Color = INK; st.Thickness = 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; st.Parent = t
	return t
end
local function sfx(cue) if _G.Sfx then pcall(_G.Sfx.play, cue) end end

--======================================================================
-- REMOTES
--======================================================================
local GiftSend     = ReplicatedStorage:WaitForChild("GiftTokensEvent", 30)
local GiftResult   = ReplicatedStorage:WaitForChild("GiftResultEvent", 30)
local GiftReceived = ReplicatedStorage:WaitForChild("GiftReceivedEvent", 30)
if not (GiftSend and GiftResult and GiftReceived) then
	warn("[Gifting] gift remotes never arrived -- panel inactive")
	return
end

--======================================================================
-- PANEL
--======================================================================
local gui, panel, listFrame, statusLbl, customBox
-- Forward-declared because build() closes over it but is written above its definition. Without this it
-- compiles to a GLOBAL read inside build() and comes back nil the first time the panel is closed.
local setHudHidden
local tabBtns = {}
local mode = "server"        -- "server" = people here now, "friends" = your friends list
local friendCache = nil      -- filled once per session by loadFriends()
local friendsLoading = false
local chosenUser, chosenName, chosenAmount = nil, nil, AMOUNTS[2]
local amountBtns = {}

local function setStatus(msg, colour)
	if statusLbl then statusLbl.Text = msg or ""; statusLbl.TextColor3 = colour or CREAM end
end

local function refreshAmountButtons()
	local matchedPreset = false
	for amt, btn in pairs(amountBtns) do
		local on = (amt == chosenAmount)
		if on then matchedPreset = true end
		btn.BackgroundColor3 = on and GOLD or BLUE_D
		local lbl = btn:FindFirstChildWhichIsA("TextLabel")
		if lbl then lbl.TextColor3 = on and INK or CREAM end
	end
	-- The custom box lights up only when the chosen amount is NOT one of the presets, so exactly one control
	-- ever looks selected and the player can always tell where the number they are about to send came from.
	if customBox then
		local custom = (not matchedPreset) and customBox.Text ~= ""
		customBox.BackgroundColor3 = custom and GOLD or BLUE_D
		customBox.TextColor3 = custom and INK or CREAM
	end
end

--======================================================================
-- FRIENDS
--======================================================================
-- GetFriendsAsync works for OFFLINE friends, which is the entire point -- the server-only list can never
-- show the person a kid actually wants to send something to, because that person is usually not here.
--
-- It is a paged web call, so it is fetched ONCE per session and cached: re-requesting it every time the
-- panel opens would be both slow and a good way to get rate-limited.
local function loadFriends(onDone)
	if friendCache then onDone(friendCache); return end
	if friendsLoading then return end
	friendsLoading = true
	task.spawn(function()
		local out = {}
		local ok, err = pcall(function()
			local pages = Players:GetFriendsAsync(player.UserId)
			for _ = 1, 10 do   -- 10 pages is far more friends than any panel needs to list
				for _, f in ipairs(pages:GetCurrentPage()) do
					out[#out + 1] = {
						id   = f.Id,
						name = f.DisplayName or f.Username,
						user = f.Username,
					}
				end
				if pages.IsFinished then break end
				pages:AdvanceToNextPageAsync()
			end
		end)
		friendsLoading = false
		if not ok then
			warn("[Gifting] could not load friends: " .. tostring(err))
			friendCache = {}
		else
			table.sort(out, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
			friendCache = out
		end
		onDone(friendCache)
	end)
end

local function refreshTabs()
	for id, btn in pairs(tabBtns) do
		local on = (id == mode)
		btn.BackgroundColor3 = on and GOLD or BLUE_D
		local lbl = btn:FindFirstChildWhichIsA("TextLabel")
		if lbl then lbl.TextColor3 = on and INK or CREAM end
	end
end

local function rebuildPlayerList()
	if not listFrame then return end
	-- CLEAR EVERYTHING WE DREW, NOT JUST THE ROWS.
	-- This used to destroy only TextButtons, which quietly leaked the "nobody else is here" note: that note is
	-- a TextLabel, so it survived every rebuild and a fresh one was added on top. rebuildPlayerList runs on
	-- open, on PlayerAdded AND on PlayerRemoving, so opening the panel twice in an empty server stacked two
	-- copies at the same position and it read as doubled text.
	--
	-- GuiObject is the right net: it catches the rows and the note, and UICorner/UIListLayout are UIComponents
	-- rather than GuiObjects, so the frame's own styling is never destroyed.
	for _, c in ipairs(listFrame:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end

	-- Both tabs render the same row shape, so the list is built from a plain {id, name, here} array and the
	-- only difference between the two modes is where that array came from.
	local others = {}
	if mode == "server" then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				others[#others + 1] = { id = p.UserId, name = p.DisplayName or p.Name, here = true }
			end
		end
	else
		for _, f in ipairs(friendCache or {}) do
			-- A friend who IS in this server is shown as online, so the row reads honestly either way and a
			-- kid is never told a gift will "arrive later" when it is about to arrive instantly.
			others[#others + 1] = {
				id = f.id, name = f.name,
				here = Players:GetPlayerByUserId(f.id) ~= nil,
			}
		end
	end

	if #others == 0 then
		-- An empty list with no explanation reads as a broken panel. Say why it is empty.
		-- Belt and braces after the leak above: never add a second note even if a rebuild races.
		if not listFrame:FindFirstChild("EmptyNote") then
			local msg
			if mode == "friends" then
				msg = friendCache and "No friends found -- add some on Roblox first!" or "Loading your friends..."
			else
				msg = "Nobody else is in this server right now!"
			end
			local none = text(listFrame, msg, 18, CREAM)
			none.Name = "EmptyNote"
			-- positioned, not left at (0,0): a stray duplicate would then be visibly offset rather than
			-- silently overprinting the original and looking like bold text
			none.Size = UDim2.new(1, -12, 0, 40)
			none.Position = UDim2.new(0, 6, 0, 8)
		end
		listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
		return
	end

	for i, p in ipairs(others) do
		local picked = (chosenUser == p.id)
		local row = Instance.new("TextButton")
		row.Name = "P_" .. p.id
		row.Size = UDim2.new(1, -12, 0, 46)
		row.Position = UDim2.new(0, 6, 0, (i - 1) * 52)
		row.BackgroundColor3 = picked and GOLD or BLUE_D
		row.AutoButtonColor = false
		row.Text = ""
		row.Parent = listFrame
		corner(row, 12); stroke(row, picked and GOLD_D or BLUE, 2)

		local nameLbl = text(row, p.name, 20, picked and INK or CREAM)
		nameLbl.Size = UDim2.new(1, -120, 1, 0)
		nameLbl.Position = UDim2.new(0, 14, 0, 0)
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left

		-- Say plainly whether this lands now or later. "Offline" on its own reads like a refusal; the point
		-- is that sending still works, so the row says WHEN it arrives instead of whether it can.
		local badge = text(row, p.here and "HERE NOW" or "GETS IT LATER", 13,
			picked and INK or (p.here and LIME or Color3.fromRGB(180, 210, 245)))
		badge.Size = UDim2.new(0, 110, 1, 0)
		badge.Position = UDim2.new(1, -118, 0, 0)
		badge.TextXAlignment = Enum.TextXAlignment.Right

		row.MouseButton1Click:Connect(function()
			chosenUser, chosenName = p.id, p.name
			sfx("click")
			setStatus(p.here and ("Gifting to " .. p.name)
				or ("Gifting to " .. p.name .. " -- they'll get it next time they play"), CREAM)
			rebuildPlayerList()
		end)
	end
	listFrame.CanvasSize = UDim2.new(0, 0, 0, #others * 52 + 8)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "GiftGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.Enabled = false
	gui.Parent = PlayerGui

	-- BELT AND BRACES. MenuBackButton and MainMenuManager can both close this panel without going through
	-- toggle(), and a panel that closes while the bottom HUD is still held off leaves the player with no fart
	-- button and no way to get it back. Watching Enabled catches every route, including ones added later.
	--
	-- This MUST live in here, not at the top level: `gui` is a forward-declared local that stays nil until
	-- this function runs, so at file scope it indexes nil and takes the whole script down before the panel
	-- is ever built -- which is exactly what happened, and why the MORE+ card found no GiftGui at all.
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not gui.Enabled then setHudHidden(false) end
	end)

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(700, 520)   -- the house panel size, same as the Shop and Pet Hub
	panel.BackgroundColor3 = BLUE
	panel.BorderSizePixel = 0
	panel.Parent = gui
	corner(panel, 22); stroke(panel, CREAM, 4)

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 66)
	header.BackgroundColor3 = BLUE_D
	header.BorderSizePixel = 0
	header.Parent = panel
	corner(header, 22)

	local title = text(header, "\xF0\x9F\x8E\x81  SEND A GIFT", 30, GOLD)
	title.Size = UDim2.new(1, -80, 1, 0)
	title.Position = UDim2.new(0, 20, 0, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left

	-- X ONLY. This codebase has repeatedly designed out backdrop-click dismissal; there is no backdrop here.
	--
	-- THE "X" IS THE BUTTON'S OWN Text, NOT A CHILD LABEL. MenuBackButton finds a panel's close button by
	-- reading TextButton.Text and matching it against "X"/"x"/the two multiplication glyphs, then mirrors the
	-- BACK button off its size, anchor, corner radius and baseline. With the X parked in a child label the
	-- button's own Text is "", findCloseX returns nil, and BACK silently falls back to the old top-left
	-- placement on top of the title.
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(44, 44)
	close.Position = UDim2.new(1, -54, 0, 11)
	close.BackgroundColor3 = RED
	close.AutoButtonColor = false
	close.Font = Enum.Font.FredokaOne
	close.TextSize = 24
	close.TextColor3 = CREAM
	close.Text = "X"
	close.Parent = header
	corner(close, 12); stroke(close, Color3.fromRGB(150, 40, 40), 2)
	local xStroke = Instance.new("UIStroke")
	xStroke.Color = INK; xStroke.Thickness = 2
	xStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	xStroke.Parent = close

	local hint = text(panel, "Pick someone, pick an amount, send them Crate Tickets.", 16, CREAM)
	hint.Size = UDim2.new(1, -40, 0, 22)
	hint.Position = UDim2.new(0, 20, 0, 72)
	hint.TextXAlignment = Enum.TextXAlignment.Left

	-- TWO TABS. The server list can only ever show who happens to be here; the friends list is how a kid
	-- reaches the person they actually meant, whether or not that person is online.
	local TABS = { { id = "server", label = "IN THIS SERVER" }, { id = "friends", label = "MY FRIENDS" } }
	for i, t in ipairs(TABS) do
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. t.id
		b.Size = UDim2.fromOffset(180, 34)
		b.Position = UDim2.new(0, 20 + (i - 1) * 190, 0, 98)
		b.BackgroundColor3 = BLUE_D
		b.AutoButtonColor = false
		b.Text = ""
		b.Parent = panel
		corner(b, 10); stroke(b, BLUE, 2)
		local l = text(b, t.label, 15, CREAM); l.Size = UDim2.fromScale(1, 1)
		tabBtns[t.id] = b
		b.MouseButton1Click:Connect(function()
			if mode == t.id then return end
			mode = t.id
			chosenUser, chosenName = nil, nil
			sfx("click"); refreshTabs()
			if mode == "friends" then
				rebuildPlayerList()                      -- shows "Loading your friends..." straight away
				loadFriends(function() if gui.Enabled then rebuildPlayerList() end end)
			else
				rebuildPlayerList()
			end
		end)
	end
	refreshTabs()

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "PlayerList"
	listFrame.Size = UDim2.new(1, -40, 0, 188)
	listFrame.Position = UDim2.new(0, 20, 0, 138)
	listFrame.BackgroundColor3 = Color3.fromRGB(22, 108, 205)
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 6
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.Parent = panel
	corner(listFrame, 14)

	local amtTitle = text(panel, "HOW MANY?", 20, GOLD)
	amtTitle.Size = UDim2.new(1, -40, 0, 24)
	amtTitle.Position = UDim2.new(0, 20, 0, 330)
	amtTitle.TextXAlignment = Enum.TextXAlignment.Left

	-- QUICK PICKS. Six buttons at 100 wide with an 8px gap span exactly 20..680 inside a 700 panel.
	for i, amt in ipairs(AMOUNTS) do
		local b = Instance.new("TextButton")
		b.Name = "Amt_" .. amt
		b.Size = UDim2.fromOffset(100, 44)
		b.Position = UDim2.new(0, 20 + (i - 1) * 108, 0, 356)
		b.BackgroundColor3 = BLUE_D
		b.AutoButtonColor = false
		b.Text = ""
		b.Parent = panel
		corner(b, 12); stroke(b, BLUE, 2)
		local l = text(b, tostring(amt), 22, CREAM); l.Size = UDim2.fromScale(1, 1)
		amountBtns[amt] = b
		b.MouseButton1Click:Connect(function()
			chosenAmount = amt
			if customBox then customBox.Text = "" end   -- a preset wins: clear the typed one
			sfx("click"); refreshAmountButtons()
		end)
	end

	-- CUSTOM AMOUNT. The quick picks cover the common cases; this is for the kid who wants to send exactly
	-- 137 because that is how many they have.
	local orLbl = text(panel, "OR TYPE ONE:", 15, CREAM)
	orLbl.Size = UDim2.fromOffset(112, 36)
	orLbl.Position = UDim2.new(0, 20, 0, 406)
	orLbl.TextXAlignment = Enum.TextXAlignment.Left

	customBox = Instance.new("TextBox")
	customBox.Name = "CustomAmount"
	customBox.Size = UDim2.fromOffset(150, 36)
	customBox.Position = UDim2.new(0, 136, 0, 406)
	customBox.BackgroundColor3 = BLUE_D
	customBox.Font = Enum.Font.FredokaOne
	customBox.TextSize = 20
	customBox.TextColor3 = CREAM
	customBox.PlaceholderText = MIN_GIFT .. "-" .. MAX_GIFT
	customBox.PlaceholderColor3 = Color3.fromRGB(150, 185, 230)
	customBox.Text = ""
	customBox.ClearTextOnFocus = false   -- kids edit a number, they do not retype it from scratch
	customBox.Parent = panel
	corner(customBox, 10); stroke(customBox, BLUE, 2)

	local rangeLbl = text(panel, ("%d-%d tickets"):format(MIN_GIFT, MAX_GIFT), 14, Color3.fromRGB(170, 205, 245))
	rangeLbl.Size = UDim2.fromOffset(180, 36)
	rangeLbl.Position = UDim2.new(0, 296, 0, 406)
	rangeLbl.TextXAlignment = Enum.TextXAlignment.Left

	-- DIGITS ONLY, AS THEY TYPE. A TextBox will happily accept "-50" or "1e9" or a paragraph, and every one
	-- of those reaches FireServer as something the server then has to reject. Stripping non-digits at the
	-- keystroke means the box can only ever hold a number, and the 4-character cap keeps it inside the range
	-- without an alarming red error for typing a fifth digit.
	local guard = false
	customBox:GetPropertyChangedSignal("Text"):Connect(function()
		if guard then return end
		local clean = customBox.Text:gsub("%D", ""):sub(1, 4)
		if clean ~= customBox.Text then
			guard = true; customBox.Text = clean; guard = false
		end
	end)

	-- COMMIT ON FOCUS LOST. Clamping live would fight the typist: type "5" on the way to "50" and it would
	-- snap to 10 under their finger. So the box holds whatever they type and is clamped once they are done.
	customBox.FocusLost:Connect(function()
		local n = tonumber(customBox.Text)
		if not n or n <= 0 then
			customBox.Text = ""                       -- empty / rubbish: fall back to the selected preset
			refreshAmountButtons()
			return
		end
		local clamped = math.clamp(math.floor(n), MIN_GIFT, MAX_GIFT)
		chosenAmount = clamped
		-- Write the clamped value back so what they SEE is what will send. Silently sending a different
		-- number than the one on screen is the single most confusing thing a form can do.
		guard = true; customBox.Text = tostring(clamped); guard = false
		if clamped ~= math.floor(n) then
			setStatus(("Gifts are %d-%d tickets, so that became %d."):format(MIN_GIFT, MAX_GIFT, clamped), GOLD)
			sfx("deny")
		else
			sfx("click")
		end
		refreshAmountButtons()
	end)

	refreshAmountButtons()

	local send = Instance.new("TextButton")
	send.Name = "Send"
	send.Size = UDim2.new(1, -40, 0, 50)
	send.Position = UDim2.new(0, 20, 0, 450)
	send.BackgroundColor3 = GREEN
	send.AutoButtonColor = false
	send.Text = ""
	send.Parent = panel
	corner(send, 14); stroke(send, Color3.fromRGB(40, 130, 60), 3)
	local sendLbl = text(send, "SEND GIFT", 26, CREAM); sendLbl.Size = UDim2.fromScale(1, 1)

	statusLbl = text(panel, "", 16, CREAM)
	statusLbl.Size = UDim2.new(1, -40, 0, 20)
	statusLbl.Position = UDim2.new(0, 20, 0, 500)

	send.MouseButton1Click:Connect(function()
		if not chosenUser then sfx("deny"); setStatus("Pick someone first!", GOLD); return end
		-- ===== ONLY REFUSE WHEN WE POSITIVELY KNOW IT IS TOO LOW =====
		-- This check exists to give a fast, kind answer; the server re-checks and is the sole authority.
		--
		-- It used to read `tonumber(_G.crateTokenBalance) or 0`, which treats "I do not know yet" as "you
		-- have nothing" -- and that global is only populated once SkinCrateClient receives its first
		-- SkinStateEvent. Open the gift panel before that lands and every send was refused locally with
		-- "You only have 0 tickets", so the request never reached the server at all. A nil balance now falls
		-- through and lets the server decide, which is the safe direction to be wrong in: the worst case is
		-- one round trip that comes back "you don't have that many".
		local bal = tonumber(_G.crateTokenBalance)
		if bal and bal < chosenAmount then
			sfx("deny")
			setStatus(("You only have %d tickets."):format(bal), GOLD)
			return
		end
		sfx("confirm")
		setStatus("Sending...", CREAM)
		GiftSend:FireServer(chosenUser, chosenAmount)
	end)

	close.MouseButton1Click:Connect(function()
		sfx("click")
		gui.Enabled = false
	end)

	Players.PlayerAdded:Connect(function() if gui.Enabled then rebuildPlayerList() end end)
	Players.PlayerRemoving:Connect(function(p)
		if chosenUser == p.UserId then chosenUser, chosenName = nil, nil end
		if gui.Enabled then task.defer(rebuildPlayerList) end
	end)
end

--======================================================================
-- HIDE THE BOTTOM HUD WHILE OPEN
--======================================================================
-- Same treatment every other full panel gets (CrateClient does exactly this): the fart button, gas meter,
-- stomach bar and bottom buttons all sit over the middle of the screen and would otherwise draw straight
-- through a 700x520 panel. The LEFT-side rail is deliberately NOT hidden -- it is outside the panel and the
-- other menus leave it up.
--
-- _G.hudHold IS THE PART THAT ACTUALLY WORKS. CoreClient runs a bottom-stack authority that re-asserts
-- BottomStackGui four times a second to beat stale duplicate scripts, so simply setting Enabled = false gets
-- silently undone a quarter-second later. The hold tells that authority this is a legitimate reason to stay
-- off. The other three GUIs are not arbitrated there and are restored from the snapshot below.
local HUD_GUIS = { "BottomStackGui", "GasMeterGui", "FartButtonGui", "StomachGui" }
local hudPrev = nil

function setHudHidden(hidden)   -- assigns the forward-declared local above; do NOT re-add `local` here
	if _G.hudHold then pcall(_G.hudHold, "GiftPanel", hidden) end
	if hidden then
		if hudPrev then return end          -- already hidden; never re-capture over a snapshot
		hudPrev = {}
		for _, name in ipairs(HUD_GUIS) do
			local g = PlayerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") then
				hudPrev[name] = g.Enabled     -- remember the PRIOR state, not "true"
				g.Enabled = false
			end
		end
	else
		if not hudPrev then return end
		for _, name in ipairs(HUD_GUIS) do
			local g = PlayerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") and hudPrev[name] ~= nil then
				g.Enabled = hudPrev[name]     -- restore EXACTLY what it was, so a HUD that was already
			end                               -- hidden for another reason does not get switched back on
		end
		hudPrev = nil
	end
end

--======================================================================
-- OPEN / CLOSE
--======================================================================
local function toggle()
	if not gui then return end
	local opening = not gui.Enabled
	if opening then
		-- Play nicely with the rest of the HUD: everything else closes when a menu opens.
		if _G.MainMenuManager and _G.MainMenuManager.closeAll then pcall(_G.MainMenuManager.closeAll) end
		chosenUser, chosenName = nil, nil
		mode = "server"
		refreshTabs()
		chosenAmount = AMOUNTS[2]
		if customBox then customBox.Text = "" end
		setStatus("", CREAM)
		refreshAmountButtons()
		rebuildPlayerList()
		sfx("whoosh")
	else
		sfx("click")
	end
	gui.Enabled = opening
	setHudHidden(opening)
end
_G.toggleGiftPanel = toggle

-- OPEN, never close. This is what the MORE+ card calls -- see the header for why a card must not toggle.
_G.openGiftPanel = function()
	if not gui then return end
	if gui.Enabled then return end
	toggle()
end

--======================================================================
-- RESULTS
--======================================================================
GiftResult.OnClientEvent:Connect(function(ok, msg)
	if ok then
		sfx("purchase")
		-- NO BANNER FOR THE SENDER. The gift panel is open and they are looking straight at it, so the green
		-- status line under the SEND button already tells them it worked -- a gold banner at the top of the
		-- screen said the same thing a second time, in a place they were not looking, over the top of the
		-- panel they were still using. The RECEIVER still gets a banner (below), because that is the half
		-- that arrives unannounced and has no panel to read.
		setStatus(msg or "Sent!", Color3.fromRGB(150, 255, 170))
	else
		sfx("deny")
		setStatus(msg or "Couldn't send that.", GOLD)
	end
end)

-- THE MOMENT THAT MATTERS. Getting a present is the reason this feature exists, so it lands as a hero banner
-- with the sender's name on it -- not as a status line in a panel the recipient does not have open.
GiftReceived.OnClientEvent:Connect(function(fromName, amount, wasOffline)
-- Somebody gave you something. Unprompted good news deserves to be felt, not just seen.
if _G.hapticPulse then pcall(_G.hapticPulse, "milestone") end
	sfx("reward")
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(_G.NotifyCenter.push, {
			text = wasOffline
				and ("\xF0\x9F\x8E\x81  %s LEFT YOU %s TICKETS WHILE YOU WERE AWAY!"):format(
					string.upper(tostring(fromName)), tostring(amount))
				or  ("\xF0\x9F\x8E\x81  %s GAVE YOU %s TICKETS!"):format(
					string.upper(tostring(fromName)), tostring(amount)),
			color = GOLD,
			-- REWARD, not SOCIAL: somebody just handed this kid something, and it must not be silently
			-- dropped behind a "player passed you" callout.
			priority = (_G.NotifyCenter.PRIORITY and _G.NotifyCenter.PRIORITY.REWARD) or 40,
		})
	end
	print(("[Gifting] received %s tokens from %s"):format(tostring(amount), tostring(fromName)))
end)

--======================================================================
-- WIRE THE OPENER
--======================================================================
-- MORE+ is the ONLY entrance. There was a right-click-the-token-pill shortcut here as well; it is gone.
-- A hidden gesture on an element that already does something else on left-click is a discoverability
-- problem, not a feature -- nobody finds it, and the people who hit it by accident do not know what opened.
build()

print("[Gifting] ready -- opens from the MORE+ menu (Send a Gift)")
