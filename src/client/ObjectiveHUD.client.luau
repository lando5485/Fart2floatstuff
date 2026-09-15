--======================================================================
-- ObjectiveHUD.client.luau   (StarterPlayerScripts)
--======================================================================
-- NEW-PLAYER ONBOARDING: one small, polished CENTRE-SCREEN tutorial card that teaches only the essential
-- gameplay loop, one step at a time:
--     Buy Beans  ->  (buying fills the gas meter)  ->  Press the FART button  ->  Fly up & reach the next island
--
-- THERE IS NO GARDENER / FARMER STEP. The tutorial never tells the player to see the Gardener or talk to the
-- Farmer -- that is not part of the required beginner loop. This file derives its step purely from live game
-- state (grounded/flying + current power), so it never references the garden guide route.
--
-- ===== IT IS ITS OWN CARD. IT DOES NOT USE THE SHARED BANNER. =====
-- The three notification systems are SEPARATE by design:
--     top of screen   = world/event alerts + countdowns (NotifyCenter + EventClient) -- untouched
--     UI buttons       = progression reminders (the sidebar Stomach badge/callout in CoreClient)
--     centre of screen = THIS: the beginner tutorial, one instruction at a time
-- So this file builds its OWN small ScreenGui ("TutorialPrompt") and never touches NotifyCenter. The card is
-- a friendly dark rounded panel -- deliberately NOT the coloured, top-centre event-banner look.
--
-- The step is DERIVED from live state every tick (no stored counter), so it is self-healing and needs no
-- persistence. Exactly ONE instruction is on screen at a time; when the player completes an action the line
-- fades out and the next one pops in. It retires for good the moment Island >= 2 (reaching Broccoli Bluff is
-- the graduation), so anyone past island 1 never sees it again.
--======================================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== DUPLICATE GUARD + DEMOLITION OF ANY OLD STANDALONE CARD =====
-- A stale copy of this script (and the old "ObjectiveHUD" ScreenGui it built) can be baked into the place.
-- We build a DIFFERENTLY NAMED GUI ("TutorialPrompt"), so we can safely destroy every leftover "ObjectiveHUD"
-- ScreenGui and disable duplicate copies of this script without touching our own card.
if _G.__ObjectiveHUD then return end
_G.__ObjectiveHUD = true

local function nukeStaleCards()
	local removed = 0
	for _, inst in ipairs(player:GetDescendants()) do
		if inst:IsA("ScreenGui") and inst.Name == "ObjectiveHUD" then
			pcall(function() inst:Destroy() end); removed += 1
		elseif inst ~= script and inst:IsA("LocalScript") and inst.Name == script.Name then
			pcall(function() inst.Disabled = true; inst:Destroy() end); removed += 1
		end
	end
	if removed > 0 then
		print(("[Tutorial] removed %d stale ObjectiveHUD card/script copy(ies) -- the tutorial is a compact " ..
			"centre-screen card now, separate from the top banner."):format(removed))
	end
end
nukeStaleCards()
task.delay(1, nukeStaleCards); task.delay(4, nukeStaleCards); task.delay(9, nukeStaleCards)

local GOAL_ISLAND      = 2
local GOAL_ISLAND_NAME = "Broccoli Bluff"

-- ===== state =====
local ls = player:WaitForChild("leaderstats", 30)
if not ls then return end
local coinsVal   = ls:WaitForChild("Coins", 10)
local islandVal  = ls:WaitForChild("Island", 10)
local powerVal   = ls:WaitForChild("CurrentPower", 10)
local stomachVal = ls:WaitForChild("StomachMax", 10)
if not (coinsVal and islandVal and powerVal and stomachVal) then return end

-- Already past island 1 -> this player has graduated; never show anything at all.
if islandVal.Value >= GOAL_ISLAND then return end

local retired  = false
local liveStep = nil   -- the step key currently shown, so a CHANGE (=step complete) can be detected

--======================================================================
-- THE COMPACT CARD (centre-screen, one line, its own ScreenGui)
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "TutorialPrompt"
gui.ResetOnSpawn = false
gui.DisplayOrder = 55
gui.IgnoreGuiInset = true                    -- so raw-pixel offsets line up with the bar's AbsolutePosition
gui.Parent = PlayerGui

local pill = Instance.new("Frame")
pill.Name = "Prompt"
pill.AnchorPoint = Vector2.new(0.5, 1)       -- bottom-centre: its BOTTOM edge sits just above the Stomach/Gas bar
pill.Position = UDim2.new(0.5, 0, 0.82, 0)   -- fallback until it's anchored to the bottom bar (see positionCard)
pill.AutomaticSize = Enum.AutomaticSize.XY   -- hug the text (grows upward from the bottom edge)
pill.Size = UDim2.new(0, 0, 0, 0)
pill.BackgroundColor3 = Color3.fromRGB(32, 40, 60)  -- friendly dark card, NOT the coloured event-banner look
pill.BackgroundTransparency = 0.05
pill.BorderSizePixel = 0
pill.Visible = false
pill.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = pill
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255, 255, 255); s.Thickness = 2.5; s.Parent = pill
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromRGB(44, 54, 80), Color3.fromRGB(24, 30, 48)); g.Parent = pill
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 22); p.PaddingRight = UDim.new(0, 22)
	p.PaddingTop  = UDim.new(0, 10); p.PaddingBottom = UDim.new(0, 10); p.Parent = pill
end
-- A UIScale we pop from 0.82 -> 1 whenever a new instruction appears, so each step arrives with a little bump.
local pop = Instance.new("UIScale"); pop.Scale = 1; pop.Parent = pill

local label = Instance.new("TextLabel")
label.Name = "Text"
label.AutomaticSize = Enum.AutomaticSize.X
label.Size = UDim2.new(0, 0, 0, 26)
label.BackgroundTransparency = 1
-- Rounded, modern, friendly font (Nunito Bold) instead of the chunky FredokaOne -- bold and readable but softer.
label.FontFace = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
label.TextSize = 22
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.Text = ""
label.Parent = pill
-- Subtle dark outline for readability -- lighter than before (1.5px, softened) so it reads clean, not chunky.
do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(20, 24, 38); s.Thickness = 1.5; s.Transparency = 0.1; s.Parent = label end

-- ===== SIT JUST ABOVE THE BOTTOM STOMACH / GAS BAR =====
-- Anchor the card to the bottom HUD (BottomStackGui > BottomStack: the stomach pill + gas meter + fart button
-- stack) rather than a hard-coded Y, so it sits a small gap above the bar and never overlaps it on any screen
-- size. gui.IgnoreGuiInset is true, so raw-pixel offsets from the bar's AbsolutePosition line up exactly.
local GAP_ABOVE_BAR = 12
local bottomBar = nil
local function positionCard()
	if not (bottomBar and bottomBar.Parent) then return end
	local bp, bs = bottomBar.AbsolutePosition, bottomBar.AbsoluteSize
	if bs.X <= 0 or bs.Y <= 0 then return end
	-- pill AnchorPoint is (0.5,1): bottom edge GAP px above the bar's top edge, centred on the bar.
	pill.Position = UDim2.fromOffset(math.floor(bp.X + bs.X / 2), math.floor(bp.Y - GAP_ABOVE_BAR))
end
task.spawn(function()
	local bsg = PlayerGui:WaitForChild("BottomStackGui", 30)
	if not bsg then return end
	bottomBar = bsg:WaitForChild("BottomStack", 30)
	if not bottomBar then return end
	bottomBar:GetPropertyChangedSignal("AbsolutePosition"):Connect(positionCard)
	bottomBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(positionCard)
	positionCard()
end)

-- Smoothly present a line: pop the card + fade the text in.
local function showStep(text)
	label.Text = text
	positionCard()          -- re-anchor above the bar (it may have moved / resized since last shown)
	pill.Visible = true
	pop.Scale = 0.82
	label.TextTransparency = 1
	TweenService:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
end

--======================================================================
-- THE PET COMES FIRST, THEN THE DIRECTIONS
--======================================================================
-- A brand-new player is given a free Bean Buddy on first join and PetFollow plays a welcome card for it.
-- That card and these directions both want the first few seconds of attention, so the tutorial waits its
-- turn via the _G.starterWelcome handshake ("pending"/"showing"/"done"). Returning players (SeenGardenIntro
-- saved true) skip the wait entirely. A 45s ceiling is a safety net for a welcome that never resolves.
local ready = false
task.spawn(function()
	local waited = 0
	if player:GetAttribute("SeenGardenIntro") ~= true then
		while _G.starterWelcome == nil and waited < 8 do task.wait(0.25); waited += 0.25 end
		while (_G.starterWelcome == "pending" or _G.starterWelcome == "showing") and waited < 45 do
			task.wait(0.25); waited += 0.25
		end
	end
	ready = true
end)

-- ===== the step machine: pure derivation from live state (NO gardener/farmer, ever) =====
-- Returns a STEP KEY plus the compact one-line instruction. The key is what makes "the step completed" a
-- thing this file can detect: when it changes, the previous instruction has been satisfied.
local function describeStep()
	local flying = _G.isFlying == true
	local power  = powerVal.Value

	if flying then
		return "climb", "Fly up and reach the next island!"
	end
	if power > 0 then
		-- Beans bought -> the tank has gas now -> teach the fly input.
		return "fart", "Press the FART button to fly!"
	end
	-- Grounded and empty -> buy Beans (buying is what fills the gas meter).
	return "buy", "Buy Beans at the Bean Stand!"
end

--======================================================================
-- REFRESH: show the current instruction; when the step changes, fade the old line out then pop the next in.
--======================================================================
local function refresh()
	if retired or not ready then return end
	local key, text = describeStep()
	if key == liveStep then return end
	liveStep = key
	if not pill.Visible then
		showStep(text)                          -- first appearance: straight in
	else
		-- The player completed the previous action: smoothly remove it, then show the next step.
		TweenService:Create(label, TweenInfo.new(0.12), { TextTransparency = 1 }):Play()
		task.delay(0.13, function()
			if not retired and liveStep == key then showStep(text) end
		end)
	end
end

--======================================================================
-- THE ONE FINAL MESSAGE -- shown once, after the beginner loop is complete (island 2 reached).
--======================================================================
-- A celebratory sign-off on the SAME card (same dark rounded pill + Nunito font, so it reads as the tutorial
-- finishing), just brighter: gold stroke + a bigger title. It is a DISCOVERY/REMINDER only -- it points at the
-- Global Garden and Hall of Fame but is NOT a tutorial objective: no ground arrows, nothing to complete,
-- nothing gated on it. It shows ~6s, fades out, and the card is destroyed -- after that the player has no
-- beginner prompts at all.
--
-- SHOWN ONCE PER ACCOUNT: this whole script early-returns when Island >= 2 (line ~69), and Island only ever
-- goes up and is saved server-side, so a returning graduate never rebuilds this card -- the saved island
-- progression IS the "already completed the intro" flag. No separate DataStore/attribute is needed; it is the
-- exact same gate that already stops the tutorial itself from reappearing.
local function showFinalMessage()
	-- The bottom tutorial pill is done; hide it. The final message is its OWN small card, centred on the
	-- SCREEN (AnchorPoint 0.5,0.5 at fromScale 0.5,0.5) -- NOT anchored to the bottom bar -- so it stays dead
	-- centre on every resolution and is deliberately compact (2 lines, tight padding, ~28% of the width).
	pill.Visible = false

	local vw = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X) or 1280
	local w  = math.clamp(math.floor(vw * 0.28), 250, 470)   -- ~25-30% wide, clamped so it scales on mobile

	local card = Instance.new("Frame")
	card.Name = "ReadyCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)                 -- true centre of the screen
	card.Size = UDim2.fromOffset(w, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y                 -- height hugs the two lines -> compact
	card.BackgroundColor3 = Color3.fromRGB(32, 40, 60)        -- same friendly dark card as the tutorial
	card.BackgroundTransparency = 0.05
	card.BorderSizePixel = 0
	card.Parent = gui
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = card
		local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255, 210, 70); s.Thickness = 3; s.Parent = card -- gold = celebratory
		local g = Instance.new("UIGradient"); g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(44, 54, 80), Color3.fromRGB(24, 30, 48)); g.Parent = card
		local p = Instance.new("UIPadding")                  -- tight padding
		p.PaddingLeft = UDim.new(0, 12); p.PaddingRight = UDim.new(0, 12)
		p.PaddingTop  = UDim.new(0, 9);  p.PaddingBottom = UDim.new(0, 9); p.Parent = card
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 3)
		list.Parent = card
	end
	local strokeRef = card:FindFirstChildOfClass("UIStroke")

	-- 3 short lines. The title is a touch larger/bolder; the two place names get a slight colour pop via
	-- RichText so they stand out without turning this into a shouty banner. TextScaled + a MaxTextSize cap
	-- keeps each line readable but never oversized, and shrinks it to fit on a narrow phone card.
	local function line(text, maxSize, order, color, rich)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, 0, maxSize + 6)
		t.LayoutOrder = order
		t.RichText = rich == true
		t.FontFace = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
		t.Text = text
		t.TextScaled = true
		t.TextColor3 = color
		t.TextXAlignment = Enum.TextXAlignment.Center
		t.Parent = card
		local cons = Instance.new("UITextSizeConstraint"); cons.MaxTextSize = maxSize; cons.Parent = t
		local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(20, 24, 38); st.Thickness = 1.5; st.Transparency = 0.1; st.Parent = t
		return t
	end
	local title = line("🎉 YOU'RE READY TO FLOAT!", 22, 1, Color3.fromRGB(255, 210, 70))
	local body  = line("Don't forget to check out the", 14, 2, Color3.fromRGB(226, 232, 245))
	local links = line(
		'🌱 <font color="rgb(126,217,87)"><b>Global Garden</b></font> & 🏆 <font color="rgb(255,210,70)"><b>Hall of Fame</b></font>!',
		15, 3, Color3.fromRGB(255, 255, 255), true)
	local lines = { title, body, links }

	-- pop in
	local pop2 = Instance.new("UIScale"); pop2.Scale = 0.82; pop2.Parent = card
	for _, t in ipairs(lines) do t.TextTransparency = 1 end
	TweenService:Create(pop2, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	for _, t in ipairs(lines) do TweenService:Create(t, TweenInfo.new(0.25), { TextTransparency = 0 }):Play() end

	-- hold ~5.5s, then smoothly fade the card away and destroy it -- no more prompts after this
	task.delay(5.5, function()
		local ti = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(card, ti, { BackgroundTransparency = 1 }):Play()
		if strokeRef then TweenService:Create(strokeRef, ti, { Transparency = 1 }):Play() end
		for _, t in ipairs(lines) do TweenService:Create(t, ti, { TextTransparency = 1 }):Play() end
		task.delay(0.6, function() pcall(function() gui:Destroy() end) end)
	end)
end

--======================================================================
-- GRADUATION: reaching island 2 completes the beginner loop -> show the ONE final message, then retire.
--======================================================================
local function retire()
	if retired then return end
	retired = true
	liveStep = "graduated"
	showFinalMessage()
	print("[Tutorial] graduated -- final 'ready to float' message shown; tutorial retired for good")
end

islandVal.Changed:Connect(function(v)
	if v >= GOAL_ISLAND then retire() end
end)

-- Re-derive on the signals that change the step, plus a slow tick to catch _G.isFlying (a plain global).
coinsVal.Changed:Connect(refresh)
powerVal.Changed:Connect(refresh)
stomachVal.Changed:Connect(refresh)

task.spawn(function()
	while not retired do
		refresh()
		task.wait(0.2)
	end
end)

print("[Tutorial] compact centre-screen card active (own GUI; no gardener step; not the shared top banner).")
