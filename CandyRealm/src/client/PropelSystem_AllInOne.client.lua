--======================================================================
-- PropelSystem_AllInOne.client.lua  (LocalScript)  -- CandyRealm
-- FOOD-REALM PORT: the first realm's flight loop and coin accounting, on candy's plumbing.
--======================================================================
-- The FART PROPEL / FLIGHT ENGINE (no HUD of its own). It drives the REAL bottom HUD card
-- built by BottomMeterPanel.client.luau: the gas bar (_G.HUD.gasFill / _G.HUD.gasPct) and
-- the "HOLD TO FART!" button (which routes taps through _G.toggleFart). Space also farts
-- (desktop) -- bound HERE and only here.
--
-- ===== THIS IS THE FOOD REALM'S MODEL (CoreClient's flight loop), NOT THE SPACE ONE =====
--   * SPEED IS A FRACTION OF YOUR OWN TANK. FlightTuning.getFlightSpeed(power, stomachMax)
--     reads an 8-band taper across the tank, scaled so a full tank climbs exactly the tier's
--     climb (853.5 on the Gumdrop Belly ... 7110 on the Caramel Core). A bigger gut flies
--     FASTER, not longer: every tank empties in tankSecondsFor(stomachMax) seconds.
--   * THE WALL IS REACH, NOT A CEILING. There is no altitude cap. The islands are spaced so
--     that no tank clears the crossing above its own gut's pair (wall = previous climb x1.020),
--     so you get 97%+ of the way and fall -- that IS the "buy a gut" message. The upward coast
--     after thrust ends is damped (COAST_DAMPING) so it cannot leak a gate.
--   * COINS ARE PAID PER STUD TRAVELLED, by THIS client, through CoinEvent (the server bounds
--     it). A landing pays the climb x 3.52. A failed flight pays the climb x3: the 2x descent
--     bonus. PREPAY: at launch, climbFor(stomachMax, power) predicts the peak; if it is under
--     gap x 0.90 the flight is already a failure and every climbed stud pays 3x on the spot.
--     Otherwise the climb pays 1x and the 2x is paid per stud FALLEN below the peak, settled
--     at touchdown -- a landing on the next island falls ~0 and pays nothing extra.
--   * FUEL IS NEVER WIPED ON TOUCHDOWN. Leftover carries into the next launch. Only respawn
--     zeroes the tank (the server does that). No arrival bleed (ARRIVAL_BLEED_RADIUS = 0).
--   * THE TANK IS RAW POWER (0 .. stomachMax), drained at stomachMax / tankSeconds per second
--     -- the same drain as the food realm's 100/tankSeconds %/s meter, in fuel units, so the
--     server's CurrentPower sync (BurnFuelEvent, downward only) needs no conversion.
--
-- Behavior: tap fart -> a BodyVelocity drives you straight UP while gas DRAINS. Run dry ->
-- thrust stops, you fall under gravity. Tap again BEFORE empty -> cancels but KEEPS the
-- remaining fart. Respawn resets to 0.
--======================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local FlightTuning = require(Shared:WaitForChild("FlightTuning"))
local StomachTiers = require(Shared:WaitForChild("StomachTiers"))
local IslandOrder  = require(Shared:WaitForChild("IslandOrder"))

local COIN_PER_STUD    = FlightTuning.COIN_PER_STUD     -- 3.52
local DESCENT_PAY_MULT = FlightTuning.DESCENT_PAY_MULT  -- 2.0

-- ============================================================================
-- STATE
-- ============================================================================
local stomachMax   = 120   -- mirrored from leaderstats.StomachMax
local gas          = 0     -- RAW power in the tank, 0 .. stomachMax
local isFlying     = false
local bodyVel      = nil
local syncTimer    = 0
local coinTimer    = 0

-- per-flight coin accounting (the food realm's flightPrepaid / flightLastY / flightDescentOwed)
local flightPrepaid     = false   -- this flight's descent is being paid during the climb
local flightLastY       = 0       -- Y at the previous coin tick (per-stud accounting)
local flightGap         = 0       -- the crossing in front of the player at launch (studs)
local flightDescentOwed = 0       -- studs of descent still unpaid on a non-prepaid flight
local launchY           = 0       -- altitude we launched from (the descent is owed down to here)

-- remotes (created server-side by FlightEconomy; guarded so we never block forever)
local BurnFuelEvent = ReplicatedStorage:WaitForChild("BurnFuelEvent", 20)
local CoinEvent     = ReplicatedStorage:WaitForChild("CoinEvent", 20)

local function infiniteGut()
	return stomachMax >= StomachTiers.SUGAR_RUSH.maxPower
end

-- ============================================================================
-- LEADERSTATS SYNC -- the server owns the tank; this engine mirrors it.
-- While FLYING the local drain is authoritative (reported back via BurnFuelEvent);
-- while grounded, server values win (BuyFood fills, respawn zero, quest top-ups).
-- ============================================================================
local updateMeter -- forward-declared
local function syncFromStats()
	local ls = player:FindFirstChild("leaderstats")
	local cp = ls and ls:FindFirstChild("CurrentPower")
	local sm = ls and ls:FindFirstChild("StomachMax")
	if sm then stomachMax = math.max(0, sm.Value) end
	if cp and not isFlying then
		gas = math.clamp(cp.Value, 0, math.max(0, stomachMax))
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

-- Report the tank so the server's CurrentPower follows the burn (downward only). No coins
-- ride on this -- coins go through CoinEvent per stud, below.
local function reportBurn()
	if BurnFuelEvent then
		pcall(function() BurnFuelEvent:FireServer(gas) end)
	end
end

-- Pay coins. serverEventCoinMult is 2 during a double-coins event. The server floors,
-- accumulates and bounds it.
local function payCoins(amount)
	if amount <= 0 or not CoinEvent then return end
	local pay = amount * (_G.serverEventCoinMult or 1)
	pcall(function() CoinEvent:FireServer(pay) end)
end

-- ============================================================================
-- HUD DRIVE -- the bar is a percentage of the CURRENT tank. All guarded: no-ops until
-- BottomMeterPanel has published _G.HUD.
-- ============================================================================
updateMeter = function()
	local hud = _G.HUD
	if not hud then return end
	local f = (stomachMax > 0) and math.clamp(gas / stomachMax, 0, 1) or 0
	_G.gasFill01 = f   -- BellyPuff reads this for the charge puff
	if hud.gasFill then hud.gasFill.Size = UDim2.new(f, 0, 1, 0) end
	if hud.gasPct  then hud.gasPct.Text  = math.floor(f * 100 + 0.5) .. "%" end
end
local function updateFartLabel()
	local hud = _G.HUD
	if hud and hud.fartLabel then
		hud.fartLabel.Text = isFlying and "FARTING! (TAP TO STOP)" or "HOLD TO FART!"
	end
end

local function nudge(text)
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(_G.NotifyCenter.push, { text = text, color = Color3.fromRGB(255, 123, 172) })
	end
end

-- The slot whose island is nearest to a position (3D). On the ground at launch this is the
-- island we are standing on, so SLOT_POS[slot + 1] is the crossing in front of us.
local function nearestSlot(pos)
	local best, bestD = 1, math.huge
	for slot, p in ipairs(IslandOrder.SLOT_POS) do
		local d = (pos - p).Magnitude
		if d < bestD then bestD, best = d, slot end
	end
	return best
end

-- ============================================================================
-- START / STOP FLIGHT (stopFlying KEEPS the tank -- only respawn zeroes it)
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
		-- THE BALLISTIC COAST. Thrust is gone but the upward velocity is not: undamped it carries
		-- on for v^2/2g, which at Caramel-Core speed is enough to push a tier over the next wall
		-- and make a gut optional. Damp it to COAST_DAMPING (0.4): the coast distance becomes
		-- 16% of undamped, 1-22 studs across the seven tiers -- small enough that no gate leaks.
		local v = hrp.AssemblyLinearVelocity
		if v.Y > 0 then
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, v.Y * FlightTuning.COAST_DAMPING, v.Z)
		end
		-- Arm the descent payout: everything between here and the launch altitude is owed at 2x
		-- if we fall (non-prepaid flights only -- a prepaid flight was paid its 3x on the way up).
		if not flightPrepaid then
			flightLastY = hrp.Position.Y
			flightDescentOwed = math.max(0, hrp.Position.Y - launchY)
		end
	end
	reportBurn()   -- final tank sync for this thrust
	updateFartLabel()
	-- NOTE: gas is NOT touched here -> the leftover fart is preserved.
end

local function startFlying()
	if isFlying then return end
	if stomachMax <= 0 then return end
	if gas <= 0 then return end            -- no fuel -> can't launch
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	isFlying = true; _G.isFlying = true
	syncTimer = 0; coinTimer = 0
	_G.peakHeight = hrp.Position.Y
	_G.flewSinceGrounded = true

	-- PREPAY: predict the peak from the tank and compare it to the crossing in front of us
	-- (the island above the one we are launching from).
	launchY = hrp.Position.Y
	flightLastY = launchY
	flightDescentOwed = 0
	local here = nearestSlot(hrp.Position)
	flightGap = IslandOrder.gapFromSlot(here) or math.huge
	local predicted = FlightTuning.climbFor(stomachMax, gas)
	flightPrepaid = predicted < flightGap * FlightTuning.PREPAY_SAFETY
	-- an Infinite Gut is never "prepaid": it can always reach, so it pays the climb only
	if infiniteGut() then flightPrepaid = false end

	updateFartLabel()
end

-- ============================================================================
-- TOGGLE: tap once -> fly up (hands-free); tap again -> cancel (KEEP leftover gas);
-- running dry auto-stops. Exposed as _G.toggleFart for the HUD button.
-- ============================================================================
local function toggleFart()
	if isFlying then
		stopFlying()
	else
		startFlying()
	end
end
_G.toggleFart = toggleFart
UserInputService.InputBegan:Connect(function(io, gp)
	if gp then return end
	if io.KeyCode == Enum.KeyCode.Space then toggleFart() end
end)

-- ============================================================================
-- THE FLIGHT LOOP
--   drain  = stomachMax / tankSecondsFor(stomachMax)  (raw power/s; the bar always empties
--            in one flight: 22.75s on the first two guts, stretching to 36.4s on the Core)
--   speed  = getFlightSpeed(gas, stomachMax)          (8-band taper across YOUR tank)
--   coins  = studs climbed x 3.52 every COIN_TICK (x3 when prepaid); 2x per stud fallen
--            below the peak on a non-prepaid flight, settled at touchdown
-- ============================================================================
RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	if not char then if isFlying then stopFlying() end return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChild("Humanoid")
	if not hrp or not hum then if isFlying then stopFlying() end return end
	if hrp.Anchored then hrp.Anchored = false end

	if isFlying and gas > 0 and stomachMax > 0 then
		if infiniteGut() then
			-- Infinite gut: the meter is re-topped every frame, so there is no drain and no taper.
			gas = stomachMax
		else
			gas = math.max(0, gas - FlightTuning.rawDrainFor(stomachMax) * (_G.serverEventGasDrainMult or 1) * dt)
		end

		local speed = FlightTuning.getFlightSpeed(gas, stomachMax)
			* (_G.serverEventSpeedMult or 1) * (_G.rebirthSpeedMult or 1)

		-- Horizontal steering from MoveDirection (camera-relative; PC, mobile and gamepad alike),
		-- plus the event winds EventClient publishes: the windstorm shove and the storm buffet.
		local move = hum.MoveDirection
		local wpx, wpz = 0, 0
		if _G.windstormActive and _G.windstormDir then
			wpx = _G.windstormDir.X * 150
			wpz = _G.windstormDir.Z * 150
		end
		local tw = _G.thunderWindVec
		if tw then wpx = wpx + tw.X; wpz = wpz + tw.Z end

		if not bodyVel or not bodyVel.Parent then
			bodyVel = Instance.new("BodyVelocity"); bodyVel.Name = "FartVelocity"; bodyVel.Parent = hrp
		end
		bodyVel.MaxForce = FlightTuning.BODYVEL_MAXFORCE
		bodyVel.Velocity = Vector3.new(
			move.X * FlightTuning.HORIZONTAL_SPEED + wpx,
			speed,
			move.Z * FlightTuning.HORIZONTAL_SPEED + wpz)
		updateMeter()
		if hrp.Position.Y > (_G.peakHeight or 0) then _G.peakHeight = hrp.Position.Y end

		-- COINS: per STUD climbed, every COIN_TICK. 1x the climb, or 3x when the flight was prepaid
		-- at launch (the tank could not reach PREPAY_SAFETY of the gap, so the fall is certain).
		coinTimer += dt
		if coinTimer >= FlightTuning.COIN_TICK then
			coinTimer = 0
			local climbed = hrp.Position.Y - flightLastY
			flightLastY = hrp.Position.Y
			if climbed > 0 then
				payCoins(climbed * COIN_PER_STUD * (flightPrepaid and (1 + DESCENT_PAY_MULT) or 1))
			end
		end

		-- ---- tank sync every GAS_SYNC_INTERVAL ----
		syncTimer += dt
		if syncTimer >= FlightTuning.GAS_SYNC_INTERVAL then
			syncTimer = 0
			reportBurn()
		end

		-- gas just emptied this frame -> stop thrusting, fall under gravity
		if gas <= 0 then
			gas = 0
			updateMeter()
			stopFlying()
		end
	else
		if isFlying then stopFlying() end
		if bodyVel then bodyVel:Destroy(); bodyVel = nil end

		-- THE DESCENT PAYOUT (non-prepaid flights). Every stud fallen below the peak pays
		-- DESCENT_PAY_MULT x COIN_PER_STUD, down to the altitude we launched from. A flight that
		-- LANDS on the next island stops falling at once and owes ~nothing; a flight that drops
		-- all the way back pays exactly 2x its climb -- the 3x-for-a-failure total, streamed.
		if not flightPrepaid and flightDescentOwed > 0 then
			coinTimer += dt
			if coinTimer >= FlightTuning.COIN_TICK then
				coinTimer = 0
				local fell = flightLastY - hrp.Position.Y
				if fell > 0 then
					flightLastY = hrp.Position.Y
					local studs = math.min(fell, flightDescentOwed)
					flightDescentOwed -= studs
					payCoins(studs * COIN_PER_STUD * DESCENT_PAY_MULT)
				end
			end
		end
	end
end)

-- ============================================================================
-- TOUCHDOWN SETTLES THE DESCENT. Pay whatever fell since the last tick, then close the
-- book: once you are standing, nothing more is owed -- otherwise landing on a new island
-- and hopping off it would collect the 2x fall bonus on top of the 1x landing.
-- Fuel is KEPT: only respawn zeroes the tank.
-- ============================================================================
local function watchLanding(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	local lastMaterial = Enum.Material.Air
	hum:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
		if hum.FloorMaterial ~= Enum.Material.Air and lastMaterial == Enum.Material.Air and not isFlying then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp and not flightPrepaid and flightDescentOwed > 0 then
				local studs = math.min(flightDescentOwed, math.max(0, flightLastY - hrp.Position.Y))
				payCoins(studs * COIN_PER_STUD * DESCENT_PAY_MULT)
			end
			flightDescentOwed = 0
			_G.flewSinceGrounded = false
			_G.hasLanded = true
			reportBurn()
		end
		lastMaterial = hum.FloorMaterial
	end)
end

-- ============================================================================
-- HAZARD HIT HANDLERS -- EventClient calls these; every call site is guarded.
-- They are all writes to the flight state, so they live here.
-- ============================================================================
local function reportHazardLoss(lost)
	if lost <= 0 then return end
	local e = ReplicatedStorage:FindFirstChild("HazardDrainEvent")
	if e then pcall(function() e:FireServer(lost) end) end
end

-- FALLING CANDY -> your rise ENDS. The tank is untouched: you keep every drop you have not
-- burned and can launch again the moment you land. What it costs you is the climb.
_G.applyJunkHit = function(pushDown)
	if not isFlying then return false end
	stopFlying()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and pushDown and pushDown > 0 then
		local v = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(v.X, -math.abs(pushDown), v.Z)
	end
	nudge("\u{1F36C} Knocked out of the air!")
	return true
end

-- PLANE BULLETS -> the rise ends AND you are dropped.
_G.applyBeamHit = function()
	if not isFlying then return false end
	stopFlying()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local v = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(v.X * 0.4, -60, v.Z * 0.4)
	end
	nudge("\u{1F6E9} Hit! You are going down!")
	return true
end

-- GINGERBREAD GLIDERS -> 20% of the CURRENT tank, gone (with a cooldown so a flock of three
-- is survivable). Reported down the no-pay path.
local GINGER_BITE      = 0.20
local GINGER_COOLDOWN  = 1.6
local lastBite = -math.huge
_G.applyBirdHalve = function()
	if not isFlying then return false end
	if os.clock() - lastBite < GINGER_COOLDOWN then return false end
	lastBite = os.clock()
	local lost = gas * GINGER_BITE
	if lost <= 0 then return false end
	gas = math.max(0, gas - lost)
	reportHazardLoss(lost)
	updateMeter()
	if gas <= 0 then stopFlying() end
	return true
end

-- ============================================================================
-- RESPAWN RESET: the server zeroes CurrentPower on CharacterAdded; mirror it locally
-- so the bar doesn't lie while the replication lands.
-- ============================================================================
player.CharacterAdded:Connect(function(char)
	isFlying = false; _G.isFlying = false
	if bodyVel then pcall(function() bodyVel:Destroy() end); bodyVel = nil end
	gas = 0
	flightDescentOwed = 0; flightPrepaid = false
	updateMeter(); updateFartLabel()
	watchLanding(char)
end)
if player.Character then watchLanding(player.Character) end

updateMeter(); updateFartLabel()

-- SETTLE PASS: LocalScripts start in arbitrary order, so redraw once the HUDs have built.
task.delay(1, function() syncFromStats(); updateMeter(); updateFartLabel() end)

print(("[Propel] flight engine ready -- FOOD MODEL: 8-band taper across your own tank, %.2f coins/stud "
	.. "(x3 on a failure, prepaid under %.0f%% of the gap), coast damped to %.1f, fuel kept on touchdown, no ceiling")
	:format(COIN_PER_STUD, FlightTuning.PREPAY_SAFETY * 100, FlightTuning.COAST_DAMPING))
