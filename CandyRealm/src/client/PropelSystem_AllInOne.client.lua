--======================================================================
-- PropelSystem_AllInOne.client.lua  (LocalScript)
--======================================================================
-- The FART PROPEL / FLIGHT ENGINE (no HUD of its own). It drives the REAL
-- bottom-stack HUD built by JustButtons_AllInOne: the gas bar (_G.HUD.gasFill /
-- _G.HUD.gasPct) and the "HOLD TO FART!" button (which routes taps through
-- _G.toggleFart). Space also farts (desktop).
--
-- Behavior (verbatim from CoreClient): tap fart -> a BodyVelocity drives you
-- straight UP while the gas meter DRAINS. Run dry (meter hits 0) -> thrust stops,
-- you fall under gravity. Tap again BEFORE empty -> cancels but KEEPS the
-- remaining fart, so the next tap resumes. Landing/respawn resets it to 0.
--
-- THE NUMBERS (verbatim):
--   maxGasMeter = 100, DRAIN_RATE = 3.5 gas/sec (a full tank ~= 28s of flight)
--   gasMeter <-> currentPower:  currentPower = (gasMeter/100)*stomachMax
--   rise speed = getFlightSpeed(currentPower) (scales by gut tier)
--   Y velocity = BodyVelocity (MaxForce Y = 1e6); nothing else moves you up.
--
-- ⚠ TEST FUEL: the old on-screen "EAT (refill tank)" button was removed. Until
-- real food-buying fills the tank, this auto-tops the tank on spawn and whenever
-- you're on the ground (see AUTO-FUEL below) so you can keep test-flying. Delete
-- that block once BuyFood drives currentPower/gasMeter for real.
--======================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
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
-- HUD DRIVE -- update the REAL JustButtons bottom-stack gas bar + fart label.
-- All guarded: no-ops until JustButtons has published _G.HUD.
-- ============================================================================
local function updateMeter()
	local hud = _G.HUD
	if not hud then return end
	local f = math.clamp(gasMeter / maxGasMeter, 0, 1)
	if hud.gasFill then hud.gasFill.Size = UDim2.new(f, 0, 1, 0) end
	if hud.gasPct  then hud.gasPct.Text  = math.floor(gasMeter + 0.5) .. "%" end
end
local function updateFartLabel()
	local hud = _G.HUD
	if hud and hud.fartLabel then
		hud.fartLabel.Text = isFlying and "FARTING! (TAP TO STOP)" or "HOLD TO FART!"
	end
end

-- ============================================================================
-- START / STOP FLIGHT (stopFlying KEEPS the meter -- only land/respawn zeroes it)
-- ============================================================================
local function stopFlying()
	if not isFlying then return end
	isFlying = false; _G.isFlying = false
	if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then local old = hrp:FindFirstChild("FartVelocity"); if old then old:Destroy() end; hrp.Anchored = false end
	end
	updateFartLabel()
	-- NOTE: currentPower / gasMeter are NOT touched here -> the leftover fart is preserved.
end

local function startFlying()
	if isFlying then return end
	if currentPower <= 0 then return end   -- no fuel -> can't launch
	if not hasBoughtFood then return end   -- must have eaten/loaded the tank
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	isFlying = true; _G.isFlying = true
	updateFartLabel()
end

-- ============================================================================
-- TOGGLE: tap once -> fly up (hands-free); tap again -> cancel (KEEP leftover
-- gas); running dry auto-stops. (verbatim toggleFart behavior)
-- Exposed as _G.toggleFart so the real HOLD TO FART button (JustButtons) uses it.
-- ============================================================================
local function toggleFart()
	if isFlying then
		stopFlying()                                  -- cancel ascent; remaining gas/power is preserved
	elseif hasBoughtFood and currentPower > 0 then
		startFlying()                                 -- begin/resume ascent, draining the remaining gas
	end
end
_G.toggleFart = toggleFart
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

	-- ===== AUTO-FUEL (TEST) -- stands in for the removed EAT button: top the tank
	-- whenever you're grounded and not flying, so you always have fuel to launch.
	if not isFlying and hum.FloorMaterial ~= Enum.Material.Air then
		if gasMeter < maxGasMeter then
			gasMeter = maxGasMeter; currentPower = stomachMax; hasBoughtFood = true
			updateMeter()
		end
	end

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
-- On respawn, currentPower + gasMeter reset to 0 (AUTO-FUEL tops it once grounded).
-- ============================================================================
player.CharacterAdded:Connect(function()
	isFlying = false; _G.isFlying = false; if bodyVel then pcall(function() bodyVel:Destroy() end); bodyVel = nil end
	currentPower = 0; gasMeter = 0; hasBoughtFood = false
	updateMeter(); updateFartLabel()
end)

updateMeter(); updateFartLabel()
print("[Propel] flight engine ready -- drives the real HUD; HOLD TO FART button + Space fart. (auto-fuel on ground)")
