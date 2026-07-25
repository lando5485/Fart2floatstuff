-- ============================================================================================================
-- FLIGHT FEEDBACK  (client)
--
-- "YOU PASSED ANOTHER PLAYER" -- a mid-flight callout, docked under the stats panel, fired when you climb above
-- someone who was above you at launch. It is the cheapest social pressure in the game and it lands at the exact
-- instant a new player is deciding whether this is worth another attempt.
--
-- WHY A NEW FILE: CoreClient is at Luau's 200-locals-per-scope ceiling. One more top-level local there and the
-- WHOLE script fails to compile, silently, taking every handler with it. New features go in new files.
--
-- Nothing here is authoritative -- it reads _G.isFlying / _G.peakHeight / leaderstats, all of which the server
-- already owns. It cannot grant anything, so it cannot be exploited for anything.
-- ============================================================================================================

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local PASS_MARGIN = 6     -- studs you must clear someone by before it counts as a pass (stops jitter re-firing)

-- ===== SESSION STATE =====
local flightNo    = 0
local inFlight    = false
local wasAbove    = {}    -- [player] = true if they were ABOVE us at launch (the only people we can "pass")
local passedThis  = {}    -- [player] = true once passed, so one player is only ever counted once per flight
local passCount   = 0

local function myY()
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position.Y or nil
end

-- ===== "YOU PASSED ANOTHER PLAYER" =====
-- Deliberately ANONYMOUS. Naming the person invites griefing and makes it feel personal in a way a silly fart game
-- does not need; "another player" carries the whole social punch with none of that.
--
-- DOCKED UNDER THE STATS PANEL (top-right), not floating on its own. Its position and WIDTH are read from the
-- stats panel's live AbsolutePosition/AbsoluteSize every time it shows -- NOT hard-coded. That matters because the
-- stats panel moves and shrinks: it has a UIScale, phones scale it to ~0.47, and CoreClient re-positions it on
-- every viewport change. A fixed offset would be correct on exactly one screen size and wrong everywhere else.
local passGui = Instance.new("ScreenGui")
passGui.Name = "PassToast"; passGui.ResetOnSpawn = false; passGui.DisplayOrder = 55
passGui.IgnoreGuiInset = true -- so offset (0,0) is the true screen corner, matching AbsolutePosition's origin
passGui:SetAttribute("NoTextSweep", true) -- CoreClient force-sets TextScaled on every label it can see; keep it off ours
passGui.Parent = PlayerGui

-- SAME SIZE as before (panel width x 34px) -- this is a styling pass only. What makes a toast read as a designed
-- element rather than a grey box is STRUCTURE, not size:
--   * a cyan ACCENT BAR down the left edge -- the cheapest thing that makes it look deliberate, and it catches the
--     eye in peripheral vision, which is where this will actually be seen (the player is watching the sky, not
--     the corner of the HUD);
--   * the rocket in its OWN slot instead of jammed into the sentence, so the words start on a clean left margin;
--   * a diagonal GRADIENT, so it has depth rather than reading as flat UI chrome;
--   * a soft SHADOW plate behind it, which is what actually lifts it off the sky.
local passToast = Instance.new("Frame")
passToast.Name = "Toast"
passToast.AnchorPoint = Vector2.new(1, 0) -- right-aligned, so it lines up with the stats panel's right edge
passToast.Size = UDim2.new(0, 230, 0, 34)
passToast.BackgroundColor3 = Color3.fromRGB(20, 46, 84)
passToast.BackgroundTransparency = 1
passToast.Visible = false
passToast.ZIndex = 2
passToast.ClipsDescendants = true -- keeps the accent bar's square corners inside the rounded frame
passToast.Parent = passGui
Instance.new("UICorner", passToast).CornerRadius = UDim.new(0, 9)

-- DEPTH: a dark plate offset behind and below. Cheap, and it stops the toast dissolving into a bright sky.
local passShadow = Instance.new("Frame")
passShadow.Name = "Shadow"
passShadow.AnchorPoint = Vector2.new(1, 0)
passShadow.BackgroundColor3 = Color3.fromRGB(0, 6, 16)
passShadow.BackgroundTransparency = 1
passShadow.BorderSizePixel = 0
passShadow.Visible = false
passShadow.ZIndex = 1
passShadow.Parent = passGui
Instance.new("UICorner", passShadow).CornerRadius = UDim.new(0, 11)

local passGrad = Instance.new("UIGradient")
passGrad.Color = ColorSequence.new(Color3.fromRGB(32, 74, 132), Color3.fromRGB(13, 30, 58))
passGrad.Rotation = 20
passGrad.Parent = passToast

local passStroke = Instance.new("UIStroke", passToast)
passStroke.Color = Color3.fromRGB(120, 220, 255); passStroke.Thickness = 1.5; passStroke.Transparency = 1

local passAccent = Instance.new("Frame")
passAccent.Name = "Accent"
passAccent.Size = UDim2.new(0, 4, 1, 0)
passAccent.BorderSizePixel = 0
passAccent.BackgroundColor3 = Color3.fromRGB(120, 220, 255)
passAccent.BackgroundTransparency = 1
passAccent.ZIndex = 3
passAccent.Parent = passToast

local passIcon = Instance.new("TextLabel")
passIcon.Name = "Icon"
passIcon.Size = UDim2.new(0, 22, 1, 0); passIcon.Position = UDim2.new(0, 11, 0, 0)
passIcon.BackgroundTransparency = 1; passIcon.Font = Enum.Font.GothamBold; passIcon.TextSize = 15
passIcon.Text = "\xF0\x9F\x9A\x80"; passIcon.TextTransparency = 1
passIcon.ZIndex = 3
passIcon.Parent = passToast

local passLbl = Instance.new("TextLabel")
passLbl.Name = "Label"
passLbl.Size = UDim2.new(1, -44, 1, 0); passLbl.Position = UDim2.new(0, 38, 0, 0)
passLbl.BackgroundTransparency = 1; passLbl.Font = Enum.Font.GothamBold; passLbl.TextSize = 13
passLbl.TextXAlignment = Enum.TextXAlignment.Left
passLbl.TextColor3 = Color3.fromRGB(196, 242, 255); passLbl.TextTransparency = 1
passLbl.Text = "Passed another player!"
passLbl.ZIndex = 3
passLbl.Parent = passToast
local passLblStroke = Instance.new("UIStroke", passLbl)
passLblStroke.Color = Color3.fromRGB(6, 18, 38); passLblStroke.Thickness = 1.5; passLblStroke.Transparency = 1

-- Find the stats panel and sit directly under it, with a CLEAR gap -- never touching it.
--
-- The gap has to allow for the strokes. AbsoluteSize does NOT include a UIStroke: the stats panel draws a 2px
-- stroke OUTSIDE its measured box, and this toast draws its own 2px stroke outside its box too. So the visible
-- separation is (GAP - panelStroke - toastStroke), and a naive 8px gap actually rendered as ~4px of daylight with
-- the two outlines nearly kissing. The strokes are subtracted explicitly so GAP means what it says.
local STATS_GAP    = 70  -- pixels of VISIBLE daylight between the panel's outline and this toast's outline.
                         -- Raise this number if it still reads as crowded -- it is the only knob for the spacing.
local PANEL_STROKE = 2
local TOAST_STROKE = 2

local function dockUnderStats()
	local rp = PlayerGui:FindFirstChild("RightPanelGui")
	local panel = rp and rp:FindFirstChild("RightPanel")
	if panel and panel.AbsoluteSize.Y > 1 then
		local ap, as = panel.AbsolutePosition, panel.AbsoluteSize
		local y = ap.Y + as.Y + PANEL_STROKE + STATS_GAP + TOAST_STROKE
		passToast.Size = UDim2.new(0, as.X, 0, 34)          -- match the panel's LIVE (scaled) width
		passToast.Position = UDim2.fromOffset(ap.X + as.X, y) -- right edges aligned, clear of the panel below it
	else
		passToast.Size = UDim2.new(0, 230, 0, 34)
		passToast.Position = UDim2.new(1, -8, 0, 600)
	end
	-- the shadow rides the toast: same box, nudged 3px down-right
	passShadow.Size = UDim2.new(0, passToast.AbsoluteSize.X + 6, 0, 40)
	passShadow.Position = UDim2.fromOffset(
		passToast.Position.X.Offset + 3, passToast.Position.Y.Offset + 3)
end

local passHideAt = 0
local function announcePass()
	passCount += 1

	-- Passing two people in one climb must not stack two toasts on top of each other -- the second REPLACES the
	-- first and re-arms the timer, and the text switches to a count so the information is not lost.
	passLbl.Text = (passCount > 1)
		and ("Passed %d players!"):format(passCount)
		or "Passed another player!"

	dockUnderStats()
	passToast.Visible = true
	passShadow.Visible = true
	passHideAt = os.clock() + 2.5

	-- SLIDE IN FROM THE RIGHT, not a plain fade. The motion is what your eye actually catches while you are looking
	-- up at the sky -- a thing that fades in at the edge of vision simply is not noticed, and an unnoticed
	-- notification may as well not exist.
	local IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local restX = passToast.Position.X.Offset
	passToast.Position = UDim2.fromOffset(restX + 26, passToast.Position.Y.Offset)
	TweenService:Create(passToast, IN, {
		Position = UDim2.fromOffset(restX, passToast.Position.Y.Offset),
		BackgroundTransparency = 0.06,
	}):Play()
	TweenService:Create(passStroke, IN, { Transparency = 0.15 }):Play()
	TweenService:Create(passAccent, IN, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(passShadow, IN, { BackgroundTransparency = 0.55 }):Play()
	TweenService:Create(passIcon, IN, { TextTransparency = 0 }):Play()
	TweenService:Create(passLbl, IN, { TextTransparency = 0 }):Play()
	TweenService:Create(passLblStroke, IN, { Transparency = 0 }):Play()

	print("[FlightFeedback] passed another player (" .. passCount .. " this flight)")
end

-- auto-hide, and keep it glued to the stats panel while it is up (the panel can move on a viewport change)
RunService.Heartbeat:Connect(function()
	if not passToast.Visible then return end
	dockUnderStats()
	if passHideAt > 0 and os.clock() >= passHideAt then
		passHideAt = 0
		local OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(passToast, OUT, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(passStroke, OUT, { Transparency = 1 }):Play()
		TweenService:Create(passAccent, OUT, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(passShadow, OUT, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(passIcon, OUT, { TextTransparency = 1 }):Play()
		TweenService:Create(passLbl, OUT, { TextTransparency = 1 }):Play()
		TweenService:Create(passLblStroke, OUT, { Transparency = 1 }):Play()
		task.delay(0.35, function()
			if passHideAt == 0 then -- a new pass may have re-armed it mid-fade
				passToast.Visible = false
				passShadow.Visible = false
			end
		end)
	end
end)

-- ===== FLIGHT LIFECYCLE =====
local function beginFlight()
	flightNo += 1
	inFlight = true
	wasAbove, passedThis, passCount = {}, {}, 0

	-- Snapshot who is ABOVE us right now. Only they can be "passed" -- otherwise standing up would count as
	-- overtaking everyone on the farm, and the callout would be meaningless noise.
	local y = myY()
	if y then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				local ch = p.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				if hrp and hrp.Position.Y > y + PASS_MARGIN then wasAbove[p] = true end
			end
		end
	end
end

local function endFlight()
	inFlight = false
	print(("[FlightFeedback] flight %d ended -- passed %d player(s)"):format(flightNo, passCount))
end

RunService.Heartbeat:Connect(function()
	local flying = _G.isFlying == true

	if flying and not inFlight then
		beginFlight()
	elseif inFlight and not flying then
		-- _G.isFlying goes false the moment the gas runs out -- but the player is still FALLING, and the peak is
		-- already locked in by then. Ending the run here (rather than waiting to touch the ground) means the card
		-- appears at the top of the arc, while they are watching, instead of after a long silent drop.
		endFlight()
	end

	if not inFlight then return end

	-- pass detection
	local y = myY()
	if not y then return end
	for p, _ in pairs(wasAbove) do
		if not passedThis[p] then
			local ch = p.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
			if hrp and y > hrp.Position.Y + PASS_MARGIN then
				passedThis[p] = true
				announcePass()
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	wasAbove[p] = nil; passedThis[p] = nil
end)

-- ===== TEST COMMANDS =====
--   /passed  -> fire the "you passed another player" callout
--
-- Listened for on BOTH TextChatService.MessageReceived and player.Chatted. Player.Chatted is only dependable on
-- the SERVER -- under TextChatService the client-side event frequently never fires, which is exactly why an
-- earlier /optin listener in a LocalScript silently did nothing. MessageReceived is the reliable client-side one;
-- Chatted stays connected as a harmless fallback for the legacy chat.
local function onCommand(msg)
	msg = tostring(msg or ""):lower()
	if msg:sub(1, 7) == "/passed" then
		print("[FlightFeedback][TEST] /passed -- firing the pass callout")
		announcePass()
	end
end

pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function()
	player.Chatted:Connect(onCommand)
end)

print("[FlightFeedback] ready -- 'passed another player' callout under the stats panel (/passed)")
