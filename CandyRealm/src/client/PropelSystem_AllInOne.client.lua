--======================================================================
-- PropelSystem_AllInOne.client.lua  (LocalScript)
--======================================================================
-- The FART PROPEL / FLIGHT ENGINE (no HUD of its own). It drives the REAL
-- bottom HUD card built by BottomMeterPanel.client.luau: the gas bar (_G.HUD.gasFill /
-- _G.HUD.gasPct) and the "HOLD TO FART!" button (which routes taps through
-- _G.toggleFart). Space also farts (desktop) -- bound HERE and only here.
--
-- REWORKED FOR THE DINO-REALM-STYLE ECONOMY (see CANDY_ISLAND_SPACING_AND_ECONOMY.md):
--   * FUEL IS SERVER-OWNED: leaderstats.CurrentPower / StomachMax (filled by
--     BuyFood, drained here). The AUTO-FUEL test block is GONE -- you eat, you fly.
--   * Drain + band speeds come from ReplicatedStorage.Shared.FlightTuning: a full
--     tank is 45 s of thrust for EVERY gut (DRAIN_RATE = 100/45), and rise speed
--     is the band for the CURRENT (draining) power, so speed tapers through the
--     flight. The bands are SOLVED against the island gaps -- do not hand-edit.
--   * COINS: 0.14 per stud CLIMBED, paid every 0.5s of thrust via CoinEvent.
--     Billed on the DELTA from launch altitude, so you're paid for climb you
--     actually bought. The fall pays 0. One final flush on flight end.
--   * BURN REPORTING: the server only ever RAISES CurrentPower (BuyFood), so this
--     engine reports the remaining fuel via BurnFuelEvent -- the server adopts it
--     ONLY DOWNWARD, and a report of 0 triggers the anti-strand top-up.
--
-- Behavior: tap fart -> a BodyVelocity drives you straight UP while the gas meter
-- DRAINS. Run dry (meter hits 0) -> thrust stops, you fall under gravity. Tap
-- again BEFORE empty -> cancels but KEEPS the remaining fart. Respawn resets to 0.
--======================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local FlightTuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FlightTuning"))

-- ============================================================================
-- STATE + CONSTANTS
-- ============================================================================
local maxGasMeter = 100                       -- the 0..100 normalized fuel bar
local DRAIN_RATE  = FlightTuning.DRAIN_RATE   -- ~2.222 gas/sec -> full tank = 45 s of thrust
local FLIGHT_HORIZONTAL_SPEED = 48

local COIN_TICK     = 0.5    -- seconds of thrust between payouts
local COIN_PER_STUD = 0.14   -- [BALANCE] coins per stud climbed -- the other half of R = 1.91
                             -- (CandyData prices are solved against this; change one, re-solve both)

local stomachMax   = 110  -- mirrored from leaderstats.StomachMax
local gasMeter     = 0    -- 0..100 normalized fuel (THE meter)
local currentPower = 0    -- raw power = (gasMeter/100)*stomachMax
local isFlying     = false
local bodyVel      = nil

local coinTimer, lastCoinY, flightCoinsEarned = 0, 0, 0

-- remotes (created server-side by FlightEconomy; guarded so we never block forever)
local CoinEvent     = ReplicatedStorage:WaitForChild("CoinEvent", 20)
local BurnFuelEvent = ReplicatedStorage:WaitForChild("BurnFuelEvent", 20)

-- ============================================================================
-- LEADERSTATS SYNC -- the server owns the tank; this engine mirrors it.
-- While FLYING the local drain is authoritative (reported back via BurnFuelEvent);
-- while grounded, server values win (BuyFood fills, courtesy fills, respawn zero).
-- ============================================================================
local updateMeter -- forward-declared
local function syncFromStats()
	local ls = player:FindFirstChild("leaderstats")
	local cp = ls and ls:FindFirstChild("CurrentPower")
	local sm = ls and ls:FindFirstChild("StomachMax")
	if sm then stomachMax = math.max(1, sm.Value) end
	if cp and not isFlying then
		currentPower = math.max(0, cp.Value)
		gasMeter = math.clamp((currentPower / stomachMax) * 100, 0, maxGasMeter)
		if updateMeter then updateMeter() end
	end
end
task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 30); if not ls then return end
	local cp = ls:WaitForChild("CurrentPower", 10)
	local sm = ls:WaitForChild("StomachMax", 10)
	if cp then cp.Changed:Connect(syncFromStats) end
	if sm then sm.Changed:Connect(syncFromStats) end
	syncFromStats()
end)

local function reportBurn()
	if BurnFuelEvent then
		pcall(function() BurnFuelEvent:FireServer(currentPower) end)
	end
end

-- ============================================================================
-- HUD DRIVE -- update the bottom card's gas bar + fart label.
-- All guarded: no-ops until BottomMeterPanel has published _G.HUD.
-- ============================================================================
updateMeter = function()
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
-- COIN PAYOUT -- studs climbed since the last tick, flushed every COIN_TICK of
-- thrust and once more on flight end.
-- ============================================================================
local function flushClimbCoins(hrp)
	if not (hrp and CoinEvent) then return end
	local gained = hrp.Position.Y - lastCoinY
	lastCoinY = hrp.Position.Y
	if gained > 0 then
		local pay = gained * COIN_PER_STUD * (_G.serverEventCoinMult or 1)
		flightCoinsEarned = flightCoinsEarned + pay
		pcall(function() CoinEvent:FireServer(pay) end)
	end
end

-- ============================================================================
-- START / STOP FLIGHT (stopFlying KEEPS the meter -- only respawn zeroes it)
-- ============================================================================
local function stopFlying()
	if not isFlying then return end
	isFlying = false; _G.isFlying = false
	if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local old = hrp:FindFirstChild("FartVelocity"); if old then old:Destroy() end
		hrp.Anchored = false
		flushClimbCoins(hrp)   -- final flush of any remaining climb delta
	end
	reportBurn()               -- server adopts the drained tank (0 -> anti-strand)
	updateFartLabel()
	-- NOTE: currentPower / gasMeter are NOT touched here -> the leftover fart is preserved.
end

local function startFlying()
	if isFlying then return end
	if currentPower <= 0 then return end   -- no fuel -> can't launch
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	isFlying = true; _G.isFlying = true
	coinTimer = 0
	lastCoinY = hrp.Position.Y             -- climb is billed from the launch altitude
	flightCoinsEarned = 0
	updateFartLabel()
end

-- ============================================================================
-- TOGGLE: tap once -> fly up (hands-free); tap again -> cancel (KEEP leftover
-- gas); running dry auto-stops. Exposed as _G.toggleFart for the HUD button.
-- ============================================================================
local function toggleFart()
	if isFlying then
		stopFlying()
	elseif currentPower > 0 then
		startFlying()
	end
end
_G.toggleFart = toggleFart
UserInputService.InputBegan:Connect(function(io, gp)
	if gp then return end
	if io.KeyCode == Enum.KeyCode.Space then toggleFart() end
end)

-- ============================================================================
-- THE FLIGHT LOOP: thrust up while flying + gas left; drain; band speed from the
-- DRAINING power (the taper is the mechanic); pay climb coins every COIN_TICK.
-- ============================================================================
RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	if not char then if isFlying then stopFlying() end return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChild("Humanoid")
	if not hrp or not hum then if isFlying then stopFlying() end return end
	if hrp.Anchored then hrp.Anchored = false end

	if isFlying and gasMeter > 0 then
		gasMeter = math.max(0, gasMeter - DRAIN_RATE * dt)        -- DRAIN the meter
		currentPower = (gasMeter / maxGasMeter) * stomachMax      -- power scaled by REMAINING gas
		local speed = FlightTuning.getFlightSpeed(currentPower)
			* (_G.serverEventSpeedMult or 1)
		local move = hum.MoveDirection

		if not bodyVel or not bodyVel.Parent then
			bodyVel = Instance.new("BodyVelocity"); bodyVel.Name = "FartVelocity"; bodyVel.Parent = hrp
		end
		bodyVel.MaxForce = Vector3.new(50000, 1e6, 50000)
		bodyVel.Velocity = Vector3.new(move.X * FLIGHT_HORIZONTAL_SPEED, speed, move.Z * FLIGHT_HORIZONTAL_SPEED)
		updateMeter()

		-- ---- climb coins, every COIN_TICK seconds of thrust ----
		coinTimer = coinTimer + dt
		if coinTimer >= COIN_TICK then
			coinTimer = 0
			flushClimbCoins(hrp)
			reportBurn()   -- keep the server's tank roughly current mid-flight
		end

		-- gas just emptied this frame -> stop thrusting, fall under gravity
		if gasMeter <= 0 then
			currentPower = 0
			updateMeter()
			stopFlying()
		end
	else
		if isFlying then stopFlying() end
		if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	end
end)

-- ============================================================================
-- RESPAWN RESET: the server zeroes CurrentPower on CharacterAdded; mirror it
-- locally so the bar doesn't lie while the replication lands.
-- ============================================================================
player.CharacterAdded:Connect(function()
	isFlying = false; _G.isFlying = false
	if bodyVel then pcall(function() bodyVel:Destroy() end); bodyVel = nil end
	currentPower = 0; gasMeter = 0
	updateMeter(); updateFartLabel()
end)

updateMeter(); updateFartLabel()

-- SETTLE PASS: LocalScripts start in arbitrary order, so redraw once the HUDs
-- have built (two property writes, not a loop).
task.delay(1, function() syncFromStats(); updateMeter(); updateFartLabel() end)

print("[Propel] flight engine ready -- FlightTuning bands (45s tank), climb coins 0.14/stud, server-owned fuel")
