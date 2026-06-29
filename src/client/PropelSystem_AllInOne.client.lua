--======================================================================
-- PropelSystem_AllInOne.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of the FART PROPEL / FLIGHT system from CoreClient.
-- Press the fart button -> a BodyVelocity drives you straight UP while the gas
-- meter DRAINS. Run dry (meter hits 0) -> thrust stops, you fall under gravity.
-- Press again BEFORE empty -> it cancels but KEEPS your remaining fart, so the
-- next press resumes from whatever's left. Only landing/respawn resets it to 0.
-- (Exactly the toggle behavior you described.)
--
-- THE NUMBERS (verbatim from CoreClient):
--   maxGasMeter = 100, DRAIN_RATE = 3.5 gas/sec (a full tank ~= 28s of flight)
--   gasMeter <-> currentPower:  gasMeter = (currentPower/stomachMax)*100
--                               currentPower = (gasMeter/100)*stomachMax
--   rise speed = getFlightSpeed(currentPower) (scales by gut tier)
--   horizontal steer speed = FLIGHT_HORIZONTAL_SPEED = 48
--   Y velocity = BodyVelocity (MaxForce Y = 1e6); nothing else moves you up.
--
-- It builds a small gas bar + a fart button + a "EAT (refill)" button so you
-- have fuel to test (in the real game food fills the tank). Drop into
-- StarterPlayer > StarterPlayerScripts.
--======================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- STATE + CONSTANTS (verbatim)
-- ============================================================================
local stomachMax  = 100   -- the gut's max raw power (Tiny Gut). Bigger gut = faster + higher.
local maxGasMeter = 100   -- the 0..100 normalized fuel bar
local DRAIN_RATE  = 3.5   -- gas drained per second of flight (full tank ~= 28s)
local FLIGHT_HORIZONTAL_SPEED = 48
local gasMeter      = 0   -- 0..100 normalized fuel (THE meter)
local currentPower  = 0   -- raw power = (gasMeter/100)*stomachMax
local isFlying      = false
local hasBoughtFood = false -- must have fuel loaded before you can launch
local bodyVel       = nil

-- rise speed by current (gas-scaled) power -- scales per gut tier (verbatim thresholds)
local function getFlightSpeed(power)
	if power <= 100 then return 40
	elseif power <= 182 then return 62
	elseif power <= 611 then return 84
	elseif power <= 1075 then return 126
	elseif power <= 2146 then return 144
	elseif power <= 3218 then return 226
	else return 280 end
end

-- ============================================================================
-- MINIMAL HUD: gas meter bar + fart button + refill button
-- ============================================================================
local gui = Instance.new("ScreenGui"); gui.Name = "PropelHUD"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.Parent = PlayerGui
local stack = Instance.new("Frame"); stack.AnchorPoint = Vector2.new(0.5,1); stack.Position = UDim2.new(0.5,0,1,-12); stack.Size = UDim2.new(0,480,0,0)
stack.AutomaticSize = Enum.AutomaticSize.Y; stack.BackgroundTransparency = 1; stack.Parent = gui
do local l = Instance.new("UIListLayout"); l.FillDirection=Enum.FillDirection.Vertical; l.HorizontalAlignment=Enum.HorizontalAlignment.Center; l.VerticalAlignment=Enum.VerticalAlignment.Bottom; l.Padding=UDim.new(0,8); l.Parent=stack end

-- gas meter
local meterPanel = Instance.new("Frame"); meterPanel.Size=UDim2.new(0,480,0,70); meterPanel.LayoutOrder=1; meterPanel.BackgroundColor3=Color3.fromRGB(45,120,220); meterPanel.Parent=stack
Instance.new("UICorner", meterPanel).CornerRadius = UDim.new(0,16)
local title = Instance.new("TextLabel"); title.BackgroundTransparency=1; title.Text="GAS METER"; title.Font=Enum.Font.FredokaOne; title.TextSize=17; title.TextColor3=Color3.fromRGB(255,215,0); title.Size=UDim2.new(1,0,0,24); title.Position=UDim2.new(0,0,0,6); title.Parent=meterPanel
local barBg = Instance.new("Frame"); barBg.Size=UDim2.new(1,-20,0,28); barBg.Position=UDim2.new(0,10,0,34); barBg.BackgroundColor3=Color3.fromRGB(18,28,66); barBg.BackgroundTransparency=1; barBg.Parent=meterPanel
Instance.new("UICorner", barBg).CornerRadius = UDim.new(0,14)
local fill = Instance.new("Frame"); fill.Name="Fill"; fill.Size=UDim2.new(0,0,1,0); fill.BackgroundColor3=Color3.fromRGB(60,210,90); fill.Parent=barBg; Instance.new("UICorner", fill).CornerRadius=UDim.new(0,14)
local powerText = Instance.new("TextLabel"); powerText.Size=UDim2.new(1,0,1,0); powerText.BackgroundTransparency=1; powerText.Text="0/"..stomachMax; powerText.Font=Enum.Font.FredokaOne; powerText.TextSize=18; powerText.TextColor3=Color3.new(1,1,1); powerText.ZIndex=3; powerText.Parent=barBg

-- fart button
local fartBtnFrame = Instance.new("Frame"); fartBtnFrame.Size=UDim2.new(0,480,0,62); fartBtnFrame.LayoutOrder=2; fartBtnFrame.BackgroundColor3=Color3.fromRGB(50,180,50); fartBtnFrame.Parent=stack
Instance.new("UICorner", fartBtnFrame).CornerRadius = UDim.new(0,14)
local fartBtn = Instance.new("TextButton"); fartBtn.Size=UDim2.new(1,0,1,0); fartBtn.BackgroundTransparency=1; fartBtn.Text="\xe2\x98\x81  TAP TO FART!"; fartBtn.Font=Enum.Font.GothamBold; fartBtn.TextSize=22; fartBtn.TextColor3=Color3.new(1,1,1); fartBtn.Parent=fartBtnFrame

-- refill ("eat") button -- stands in for buying food (fills the tank)
local eatBtn = Instance.new("TextButton"); eatBtn.Size=UDim2.new(0,480,0,40); eatBtn.LayoutOrder=3; eatBtn.BackgroundColor3=Color3.fromRGB(255,160,40); eatBtn.Text="\xF0\x9F\x8D\xBD\xEF\xB8\x8F EAT (refill tank)"; eatBtn.Font=Enum.Font.GothamBold; eatBtn.TextSize=16; eatBtn.TextColor3=Color3.new(1,1,1); eatBtn.Parent=stack
Instance.new("UICorner", eatBtn).CornerRadius = UDim.new(0,10)

-- updateMeter: bar fill + readout from currentPower/stomachMax (verbatim shape)
local function updateMeter()
	local f = stomachMax > 0 and math.clamp(currentPower / stomachMax, 0, 1) or 0
	fill.Size = UDim2.new(f, 0, 1, 0)
	powerText.Text = math.floor(math.min(currentPower, stomachMax)) .. "/" .. stomachMax
end

-- EAT -> load the tank (in-game this is BuyFood: currentPower up to stomachMax)
eatBtn.MouseButton1Click:Connect(function()
	currentPower = stomachMax           -- full tank (raw power)
	gasMeter = maxGasMeter              -- 100% fuel
	hasBoughtFood = true
	updateMeter()
end)

-- ============================================================================
-- START / STOP FLIGHT (stopFlying KEEPS the meter -- only land/respawn zeroes it)
-- ============================================================================
local function stopFlying()
	if not isFlying then return end
	isFlying = false
	if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then local old = hrp:FindFirstChild("FartVelocity"); if old then old:Destroy() end; hrp.Anchored = false end
	end
	-- NOTE: currentPower / gasMeter are NOT touched here -> the leftover fart is preserved.
end

local function startFlying()
	if isFlying then return end
	if currentPower <= 0 then return end   -- no fuel -> can't launch
	if not hasBoughtFood then return end   -- must have eaten/loaded the tank
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	isFlying = true
end

-- ============================================================================
-- TOGGLE: press once -> fly up (hands-free); press again -> cancel (KEEP leftover
-- gas); running dry auto-stops. (verbatim toggleFart behavior)
-- ============================================================================
local function toggleFart()
	if isFlying then
		stopFlying()                                  -- cancel ascent; remaining gas/power is preserved
	elseif hasBoughtFood and currentPower > 0 then
		startFlying()                                 -- begin/resume ascent, draining the remaining gas
	end
end
fartBtn.Activated:Connect(toggleFart)
-- also allow Space to fart (desktop), like a typical bind
UserInputService.InputBegan:Connect(function(io, gp)
	if gp then return end
	if io.KeyCode == Enum.KeyCode.Space then toggleFart() end
end)

-- ============================================================================
-- THE FLIGHT LOOP (verbatim core): thrust up while flying + gas left; drain;
-- scale power by remaining gas; stop at 0; fall under gravity otherwise.
-- ============================================================================
RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	if not char then if isFlying then stopFlying() end return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChild("Humanoid")
	if not hrp or not hum then if isFlying then stopFlying() end return end
	if hrp.Anchored then hrp.Anchored = false end

	if isFlying and gasMeter > 0 then
		-- button held + gas left -> thrust straight up
		gasMeter = math.max(0, gasMeter - DRAIN_RATE * dt)        -- DRAIN the meter
		local scaledPower = (gasMeter / maxGasMeter) * stomachMax -- power scaled by REMAINING gas
		currentPower = scaledPower
		local speed = getFlightSpeed(scaledPower)
		local move = hum.MoveDirection                            -- camera-relative steer (PC/mobile/gamepad)

		if not bodyVel or not bodyVel.Parent then
			bodyVel = Instance.new("BodyVelocity"); bodyVel.Name = "FartVelocity"; bodyVel.Parent = hrp
		end
		bodyVel.MaxForce = Vector3.new(50000, 1e6, 50000)
		bodyVel.Velocity = Vector3.new(move.X * FLIGHT_HORIZONTAL_SPEED, speed, move.Z * FLIGHT_HORIZONTAL_SPEED)
		updateMeter()

		-- gas just emptied this frame -> stop thrusting, fall under gravity
		if gasMeter <= 0 then
			currentPower = 0
			updateMeter()
			stopFlying()
		end
	else
		-- not thrusting -> no upward BodyVelocity; gravity does the falling
		if isFlying then stopFlying() end
		if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	end
end)

-- ============================================================================
-- LAND / RESPAWN RESET: the ONLY place the meter zeroes (verbatim behavior).
-- On respawn, currentPower + gasMeter reset to 0 and you must eat again.
-- ============================================================================
player.CharacterAdded:Connect(function()
	isFlying = false; if bodyVel then pcall(function() bodyVel:Destroy() end); bodyVel = nil end
	currentPower = 0; gasMeter = 0; hasBoughtFood = false
	updateMeter()
end)

updateMeter()
print("[Propel] ready -- EAT to fill, then TAP TO FART (Space also works). Release keeps your leftover fart.")
