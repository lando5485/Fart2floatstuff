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
gui.Parent        = playerGui

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
