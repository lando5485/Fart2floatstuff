--======================================================================
-- CoinPulse.client.lua  (LocalScript)
--======================================================================
-- The coin counter pops and flashes green when it goes up.
--
-- Coins are the reward for every single thing in this game and the number currently just... changes. A value
-- that silently ticks over reads as a readout; a value that reacts reads as a payout. This is the cheapest
-- feel-good left in the HUD and it costs one tween.
--
-- ===== RISING ONLY =====
-- No reaction when it falls. Spending happens constantly -- every food purchase, every stomach tier -- and a
-- red flash on each one would turn the most-looked-at number on screen into a nag.
--
-- ===== WHY IT DOES NOT JUST ADD A UISCALE AND SET IT BACK TO 1 =====
-- ResponsiveUI puts its own UIScale on managed HUD elements on phones, and its header is explicit that a
-- hand-authored UIScale must not be stacked or fought. So this: reads whatever scale is already there,
-- pulses UP from it, and returns to THAT value rather than to 1. On a phone showing 0.72 it pulses
-- 0.72 -> 0.85 -> 0.72. And if the element is one ResponsiveUI has already claimed, the scale pulse is
-- skipped entirely and only the colour flash plays -- a slightly quieter effect beats a broken layout.
--======================================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

if _G.__CoinPulseClient then
	warn("[CoinPulse] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__CoinPulseClient = true

--======================================================================
-- TUNING
--======================================================================
-- HOW BIG THE POP CAN SAFELY BE. TokenHud's coin pill is a FIXED-width frame and the number sits in a
-- ValueBox anchored to its LEFT edge, so a UIScale grows the digits rightward into the gap before the "+"
-- button -- 14px of slack by TokenHud's own reckoning. At 0.13 even a seven-figure balance (~110px of text)
-- grows about 13px and stays inside it.
--
-- The pill itself does NOT resize under the pop, which is the thing that would actually look broken:
-- TokenHud's fit() sizes the pill from coinValue.TextBounds.X, and TextBounds is the intrinsic text
-- measurement -- an ancestor UIScale does not change it. So the digits pop and the capsule holds still.
local POP        = 0.13                            -- how far above its resting scale the number jumps
local UP_TIME    = 0.09
local DOWN_TIME  = 0.20
local FLASH      = Color3.fromRGB(126, 255, 150)   -- the green it flashes to
local RESPONSIVE_TAG = "ResponsiveScaleApplied"    -- ResponsiveUI's own marker; see the header

--======================================================================
-- FIND THE COIN NUMBER
--======================================================================
-- Resolved by SEARCH rather than by a hard path, because the coin readout has been rebuilt more than once and
-- a literal path would break silently the next time it moves.
--
-- ===== IT MUST BE THE *VISIBLE* ONE =====
-- There are TWO coin labels in CoinGui at once. CoreClient builds the original at CoinGui.Frame.Amount;
-- TokenHud later builds its capsule at CoinGui > TopRightRow > CurrencyCapsule > CoinPill > ValueBox > Value
-- and then HIDES the original outright (TokenHud sets coinFrame.Visible = false). Both still exist, so a
-- search that just takes the first match it finds has even odds of animating a label nobody can see -- which
-- is exactly what happened: the log read "armed on CoinGui.Frame.Amount" 550ms BEFORE TokenHud had built the
-- capsule, so the preferred path did not exist yet and the fallback won.
--
-- So: check effective visibility, not merely existence. A label is only a candidate if it and every ancestor
-- up to the ScreenGui are visible and it occupies real pixels.
local function shown(inst)
	local node = inst
	while node and node ~= PlayerGui do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("ScreenGui") and not node.Enabled then return false end
		node = node.Parent
	end
	return inst.AbsoluteSize.X > 1 and inst.AbsoluteSize.Y > 1
end

local function findCoinLabel()
	local gui = PlayerGui:FindFirstChild("CoinGui")
	if not gui then return nil end
	local fallback
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") and (d.Name == "Value" or d.Name == "Amount") then
			-- the token pill sits in the same capsule and is also called Value; it is not the coins
			local isToken = d:FindFirstAncestor("TokenPill") ~= nil
			if not isToken then
				if shown(d) then return d end
				fallback = fallback or d -- remember it in case NOTHING is visible yet (HUD still building)
			end
		end
	end
	return fallback
end

--======================================================================
-- THE PULSE
--======================================================================
local busy = false
local function pulse(label)
	if busy or not label or not label.Parent then return end
	busy = true

	-- colour flash: always safe, never touches layout
	local baseColour = label.TextColor3
	label.TextColor3 = FLASH
	TweenService:Create(label, TweenInfo.new(DOWN_TIME + UP_TIME, Enum.EasingStyle.Quad), { TextColor3 = baseColour }):Play()

	-- scale pop: only if nobody else owns the scaling of this box
	local box = label.Parent
	local claimed = box:GetAttribute(RESPONSIVE_TAG) ~= nil or label:GetAttribute(RESPONSIVE_TAG) ~= nil
	local us = box:FindFirstChildOfClass("UIScale")
	if not claimed then
		if not us then
			us = Instance.new("UIScale"); us.Name = "PulseScale"; us.Parent = box
		end
		local rest = us.Scale -- whatever it is RIGHT NOW, which is what we must come back to
		local up = TweenService:Create(us, TweenInfo.new(UP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = rest + POP })
		up.Completed:Connect(function()
			TweenService:Create(us, TweenInfo.new(DOWN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Scale = rest }):Play()
		end)
		up:Play()
	end

	task.delay(UP_TIME + DOWN_TIME, function() busy = false end)
end

--======================================================================
-- WATCH
--======================================================================
task.spawn(function()
	local ls
	for _ = 1, 60 do
		ls = _G.leaderstats or player:FindFirstChild("leaderstats")
		if ls and ls:FindFirstChild("Coins") then break end
		task.wait(0.5)
	end
	local coins = ls and ls:FindFirstChild("Coins")
	if not coins then warn("[CoinPulse] leaderstats.Coins never arrived -- inactive"); return end

	-- Wait for a VISIBLE label, not merely any label. TokenHud builds its capsule and hides CoreClient's
	-- original a beat after this script starts, so resolving on the first thing that exists picks the loser.
	local label
	for _ = 1, 60 do
		label = findCoinLabel()
		if label and shown(label) then break end
		task.wait(0.5)
	end
	if not label then warn("[CoinPulse] no coin label found under CoinGui -- inactive"); return end

	local last = coins.Value
	coins:GetPropertyChangedSignal("Value"):Connect(function()
		local now = coins.Value
		if now > last then
			-- Re-resolve if the label was destroyed OR hidden since we bound to it. Hidden matters as much as
			-- destroyed here: TokenHud swapping which pill is on screen leaves the old one parented but
			-- invisible, and pulsing that is a no-op the player never sees.
			if not (label.Parent and shown(label)) then
				label = findCoinLabel() or label
			end
			pulse(label)
		end
		last = now
	end)
	print("[CoinPulse] armed on " .. label:GetFullName())
end)
