--======================================================================
-- ObjectiveHUD.client.luau   (StarterPlayerScripts)
--======================================================================
-- NEW-PLAYER ONBOARDING: one always-visible objective card that teaches the
-- core loop by DOING it -- buy food -> tap fart -> grab a ring -> reach island 2.
-- Before this, the only explanation of the loop lived behind the Farmer's optional
-- ProximityPrompt (FarmerTutorial), which a player could walk straight past.
--
-- The step is DERIVED from live game state every tick -- there is no stored step
-- counter, so it is self-healing (a player who dies, rejoins, or buys food out of
-- order always sees the right instruction) and needs no persistence.
--
-- It retires itself for good the moment Island >= 2: reaching Broccoli Bluff IS
-- the graduation, so anyone past island 1 never sees the card again.
--
-- THE RING STEP IS LOAD-BEARING, not flavour. A fresh player has 25 coins -> 5 Beans
-- -> 40 power -> a ~600-stud flight that pays back ~27 coins. Island 2 is at Y=790.
-- So the opening loop is almost exactly BREAK-EVEN and cannot reach island 2 on
-- height coins alone -- rings (+18 and up) are the only escape, and nothing else in
-- the game mentions they exist. The FULL-TANK coin goal below makes the target legible.
--======================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== DUPLICATE GUARD =====
-- A STALE COPY OF THIS SCRIPT IS BAKED INTO THE PLACE. MenuBackdropGuard names it in both of its warnings --
-- "18 DUPLICATE LocalScript(s): ... ObjectiveHUD ..." and "8 DUPLICATE ScreenGui name(s): ... ObjectiveHUD".
-- Two copies run, each builds its own card, and both sit at the same anchored position: the old one lands on
-- top of the new one, so the card you read is whichever loaded last -- and it was showing the OLD wording
-- while the arrows followed the new route. Exactly the failure the trail/card sync was meant to end.
--
-- Rojo cannot fix this by editing the file, because the stale copy is not this file -- it is a separate
-- Instance in the place that Rojo never touches. So the live copy evicts it at runtime, the same way
-- Campfire and DailyTasks already do.
--
-- THIS RUNS BEFORE THE GRADUATION EARLY-RETURN BELOW, deliberately. If the player is already past island 2
-- this script bails out and never builds a card -- but the stale copy might not, and an un-evicted stale card
-- would then hang on screen for a graduated player with nothing left to remove it.
if _G.__ObjectiveHUD then return end
_G.__ObjectiveHUD = true

local STAMP = "BuiltByLiveScript"
local function nukeStaleObjectiveHUD()
	local removed = 0
	for _, inst in ipairs(player:GetDescendants()) do
		if inst:IsA("ScreenGui") and inst.Name == "ObjectiveHUD" and not inst:GetAttribute(STAMP) then
			pcall(function() inst:Destroy() end); removed += 1
		elseif inst ~= script and inst:IsA("LocalScript") and inst.Name == script.Name then
			-- the running copies live under the player (PlayerScripts / PlayerGui), not in StarterPlayer
			pcall(function() inst.Disabled = true; inst:Destroy() end); removed += 1
		end
	end
	if removed > 0 then
		warn("[Objective] cleared " .. removed .. " STALE duplicate objective card(s)/script(s) -- the old one " ..
			"was drawn on top of this one. Delete them in Studio for good.")
	end
end
nukeStaleObjectiveHUD()
-- Load order is not ours to choose: a stale copy that starts AFTER us is only reachable once it has built
-- itself, so sweep again a few times over the first few seconds.
task.delay(1, nukeStaleObjectiveHUD); task.delay(4, nukeStaleObjectiveHUD); task.delay(9, nukeStaleObjectiveHUD)

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local scale    = isMobile and 0.7 or 1.0

-- Beans = the island-1 food. Mirrors CoreClient's `foods[1]` and PlayerStats' server table
-- (the food list is already duplicated client/server in this codebase -- keep all three in step).
local BEAN_PRICE, BEAN_POWER = 5, 8

local GOAL_ISLAND      = 2
local GOAL_ISLAND_NAME = "Broccoli Bluff"

-- ===== state =====
local ls          = player:WaitForChild("leaderstats", 30)
if not ls then return end
local coinsVal    = ls:WaitForChild("Coins", 10)
local islandVal   = ls:WaitForChild("Island", 10)
local powerVal    = ls:WaitForChild("CurrentPower", 10)
local stomachVal  = ls:WaitForChild("StomachMax", 10)
if not (coinsVal and islandVal and powerVal and stomachVal) then return end

-- Already past island 1 -> this player has graduated; never build the card at all.
if islandVal.Value >= GOAL_ISLAND then return end

local grabbedARing = false -- sticky across flights: once they've learned rings, stop nagging about them
local retired      = false

-- ===== card =====
local gui = Instance.new("ScreenGui")
gui.Name          = "ObjectiveHUD"
gui.ResetOnSpawn  = false
gui.IgnoreGuiInset = true
gui.DisplayOrder  = 55 -- above the HUD, below the Farmer dialog (60) and shop popups
-- Stamped BEFORE parenting: the delayed sweeps above destroy any unstamped ObjectiveHUD they find, and a
-- gui that is parented first and stamped a line later can be caught in that gap by its own cleanup.
gui:SetAttribute(STAMP, true)
gui.Parent        = playerGui

-- ===== THE PET COMES FIRST, THEN THE DIRECTIONS =====
-- A brand-new player is given a free Bean Buddy on their very first join, and PetFollow plays a welcome
-- card for it. That card and this one both want the same first ten seconds of a new player's attention,
-- and two cards at once is how somebody reads neither -- so this one waits its turn.
--
-- The handshake is _G.starterWelcome, set by PetFollow: "pending" the instant the grant lands, "showing"
-- while the card is up, "done" once it has faded. Claiming "pending" at the GRANT rather than at the card
-- matters, because that card deliberately waits out the loading screen and the whole Garden Intro before
-- appearing -- without the early claim this card would win the race every single time.
--
-- RETURNING PLAYERS ARE NOT DELAYED AT ALL. SeenGardenIntro is a saved attribute, so anyone who has played
-- before has it true and skips this entirely; only a first-join can be waiting on a welcome card. The 45s
-- ceiling is a safety net for a welcome that never resolves (an intro that never reports back, a player who
-- sits on the PLAY button) -- the directions are the more important of the two cards, so if anything goes
-- wrong they show anyway rather than being suppressed.
gui.Enabled = false
task.spawn(function()
	local waited = 0
	if player:GetAttribute("SeenGardenIntro") ~= true then
		-- brand-new: give the grant a moment to announce itself, then wait out the card
		while _G.starterWelcome == nil and waited < 8 do task.wait(0.25); waited = waited + 0.25 end
		while (_G.starterWelcome == "pending" or _G.starterWelcome == "showing") and waited < 45 do
			task.wait(0.25); waited = waited + 0.25
		end
	end
	gui.Enabled = true
	print(("[Objective] directions shown (%s, waited %.1fs)"):format(
		_G.starterWelcome == "done" and "after the starter-pet welcome"
			or (_G.starterWelcome == nil and "no starter pet -- returning player" or "welcome timed out"), waited))
end)

-- y=85: the arrival/announcement banners settle at y=10 and are 65px tall, so this clears them.
local card = Instance.new("Frame")
card.Name          = "Card"
card.AnchorPoint   = Vector2.new(0.5, 0)
card.Position      = UDim2.new(0.5, 0, 0, math.floor(85 * scale))
card.Size          = UDim2.new(0, math.floor(470 * scale), 0, math.floor(78 * scale))
card.BackgroundColor3 = Color3.fromRGB(35, 40, 70)
card.BackgroundTransparency = 0.08
card.BorderSizePixel = 0
card.Parent        = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = card
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(48, 55, 95), Color3.fromRGB(28, 32, 58))
	g.Rotation = 90; g.Parent = card
end

local stroke = Instance.new("UIStroke")
stroke.Color     = Color3.fromRGB(255, 200, 0)
stroke.Thickness = 3
stroke.Parent    = card

local titleLbl = Instance.new("TextLabel")
titleLbl.AnchorPoint = Vector2.new(0.5, 0)
titleLbl.Position    = UDim2.new(0.5, 0, 0, math.floor(7 * scale))
titleLbl.Size        = UDim2.new(1, -20, 0, math.floor(30 * scale))
titleLbl.BackgroundTransparency = 1
titleLbl.Font        = Enum.Font.FredokaOne
titleLbl.TextColor3  = Color3.fromRGB(255, 215, 0)
titleLbl.TextScaled  = true
titleLbl.Text        = ""
titleLbl.Parent      = card

local subLbl = Instance.new("TextLabel")
subLbl.AnchorPoint = Vector2.new(0.5, 0)
subLbl.Position    = UDim2.new(0.5, 0, 0, math.floor(38 * scale))
subLbl.Size        = UDim2.new(1, -24, 0, math.floor(20 * scale))
subLbl.BackgroundTransparency = 1
subLbl.Font        = Enum.Font.GothamBold
subLbl.TextColor3  = Color3.fromRGB(205, 215, 245)
subLbl.TextScaled  = true
subLbl.Text        = ""
subLbl.Parent      = card

-- Coin goal bar: only shown on the BUY step, where "how much more do I need?" is the live question.
local barBg = Instance.new("Frame")
barBg.Name         = "GoalBar"
barBg.AnchorPoint  = Vector2.new(0.5, 1)
barBg.Position     = UDim2.new(0.5, 0, 1, math.floor(-8 * scale))
barBg.Size         = UDim2.new(1, -24, 0, math.floor(9 * scale))
barBg.BackgroundColor3 = Color3.fromRGB(18, 22, 44)
barBg.BorderSizePixel  = 0
barBg.Visible      = false
barBg.Parent       = card
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = barBg end

local barFill = Instance.new("Frame")
barFill.Size            = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
barFill.BorderSizePixel = 0
barFill.Parent          = barBg
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = barFill end

-- ===== attention pulse (runs until retired) =====
task.spawn(function()
	while not retired and gui.Parent do
		TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine), {Thickness = 5}):Play()
		task.wait(0.6)
		if retired then break end
		TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine), {Thickness = 3}):Play()
		task.wait(0.6)
	end
end)

-- ===== the step machine: pure derivation from live state =====
-- Returns title, subtitle, and (coins, cost) when a goal bar should show.
local function describeStep()
	local flying = _G.isFlying == true
	local power  = powerVal.Value

	if flying then
		if (_G.ringsCollectedFlight or 0) > 0 then grabbedARing = true end
		if not grabbedARing then
			return "\xF0\x9F\x92\x8D FLY THROUGH A RING!",
			       "Rings pay BONUS coins \xE2\x80\x94 steer into them on the way up"
		end
		return "\xF0\x9F\x9A\x80 CLIMB TO " .. string.upper(GOAL_ISLAND_NAME) .. "!",
		       "Land on it to unlock it forever"
	end

	-- ===== WALK THE PLAYER DOWN THE SAME ROUTE THE ARROWS DRAW =====
	-- GardenGuideTrail lays green chevrons to the Gardener first, then re-routes to the food stand. This card
	-- used to open on "BUY BEANS AT THE FOOD STAND" regardless -- so the very first thing a new player was
	-- told pointed somewhere the arrows on the floor were not going. Now the arrows lead and the words follow.
	--
	-- Read, never recomputed: the trail owns the route and is the half the player can SEE, so it is the half
	-- that gets to be right. Working the route out a second time here is how the two drift apart again.
	--
	-- nil means there are no tutorial arrows -- not started, both legs walked, or they have already flown --
	-- and the card falls through to its own advice below, which is correct with nothing on the ground to follow.
	local guideStep = _G.gardenGuideStep
	if guideStep == "gardener" then
		-- No coin goal bar on this leg: nothing here costs money, and a progress bar under "go and say hello"
		-- reads as though the player is being asked to save up first.
		return "\xF0\x9F\x8C\xBB FOLLOW THE ARROWS TO THE GARDENER",
		       "The green arrows on the ground show you the way \xE2\x80\x94 go and say hello"
	end
	if guideStep == "stand" and power <= 0 then
		-- Same destination as the fallback step below, but phrased so it agrees with the arrows that just
		-- re-routed. The coin goal bar comes back here, because now the question IS "can I afford a tank?".
		local need  = math.max(0, stomachVal.Value - power)
		local beans = math.ceil(need / BEAN_POWER)
		return "\xF0\x9F\x9B\x92 FOLLOW THE ARROWS TO THE FOOD STAND",
		       "Buy BEANS to fill your gas meter \xE2\x80\x94 " .. BEAN_PRICE .. " coins each",
		       coinsVal.Value, beans * BEAN_PRICE
	end

	if power > 0 then
		local pct = math.floor((power / math.max(1, stomachVal.Value)) * 100 + 0.5)
		return "\xF0\x9F\x92\xA8 TAP THE GREEN FART BUTTON!",
		       "Your gas meter is " .. pct .. "% full \xE2\x80\x94 one tap and you're flying"
	end

	-- Grounded and empty -> buy. Show exactly what a FULL tank costs, so the grind has a visible target.
	local need  = math.max(0, stomachVal.Value - power)
	local beans = math.ceil(need / BEAN_POWER)
	local cost  = beans * BEAN_PRICE
	return "\xF0\x9F\x9B\x92 BUY BEANS AT THE FOOD STAND",
	       "Beans fill your GAS METER \xE2\x80\x94 " .. BEAN_PRICE .. " coins each",
	       coinsVal.Value, cost
end

local function refresh()
	if retired then return end
	local title, sub, coins, cost = describeStep()
	titleLbl.Text = title
	subLbl.Text   = sub

	if cost and cost > 0 then
		barBg.Visible = true
		local pct = math.clamp(coins / cost, 0, 1)
		TweenService:Create(barFill, TweenInfo.new(0.25), {Size = UDim2.new(pct, 0, 1, 0)}):Play()
		-- Once they can afford a full tank, say so plainly -- that's the moment they can actually reach island 2.
		if coins >= cost then
			subLbl.Text = "You can afford a FULL TANK! Hit BUY MAX \xE2\x9C\x85"
			barFill.BackgroundColor3 = Color3.fromRGB(80, 220, 100)
		else
			subLbl.Text = sub .. "  \xE2\x80\xA2  " .. coins .. " / " .. cost .. " for a FULL tank"
			barFill.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
		end
	else
		barBg.Visible = false
	end
end

-- ===== graduation: reaching island 2 retires the card for good =====
local function retire()
	if retired then return end
	retired = true

	titleLbl.Text = "\xF0\x9F\x8E\x89 " .. string.upper(GOAL_ISLAND_NAME) .. " UNLOCKED!"
	subLbl.Text   = "Now buy the food HERE to climb even higher \xE2\x80\x94 good luck!"
	barBg.Visible = false
	card.BackgroundColor3 = Color3.fromRGB(30, 90, 45)
	stroke.Color  = Color3.fromRGB(90, 230, 110)
	stroke.Thickness = 4

	task.delay(5, function()
		if not gui.Parent then return end
		TweenService:Create(card, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.5), {Transparency = 1}):Play()
		TweenService:Create(titleLbl, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
		TweenService:Create(subLbl, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
		task.wait(0.6)
		gui:Destroy()
	end)
end

islandVal.Changed:Connect(function(v)
	if v >= GOAL_ISLAND then retire() end
end)

-- Re-derive on the signals that change the step, plus a slow tick to catch _G.isFlying
-- (a plain global, so there's nothing to listen to).
coinsVal.Changed:Connect(refresh)
powerVal.Changed:Connect(refresh)
stomachVal.Changed:Connect(refresh)

refresh()
task.spawn(function()
	while not retired and gui.Parent do
		refresh()
		task.wait(0.2)
	end
end)
