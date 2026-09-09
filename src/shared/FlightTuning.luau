--======================================================================
-- FlightTuning.luau  (ModuleScript -> ReplicatedStorage/Shared)
--======================================================================
-- THE FLIGHT MATH, in one place, copied from the F2F UNIVERSAL PROGRESSION GUIDE
-- (the Dinosaur Realm's shipped values). CoreClient burns the tank with it and
-- PlayerStats fills / gates with it. Two copies of "how far does a tank go" is how
-- a shop starts selling a gut that does not reach.
--
-- THE MODEL
--   A tank of size M filled to power p flies for  tankSecondsFor(M) * p/M  seconds.
--   Speed tapers across the tank (SPEED_SHAPE, 8 bands, mean exactly 1.0), so a full
--   tank climbs exactly  tier.climb  studs -- no integration needed.
--   climbFor / powerForClimb contain NO time term. That is deliberate: every gate in
--   the game is scale-free, and retiming a tier (TIER_TIME) moves nothing structural.
--
-- THE STRUCTURE  (one gut = one WALL crossing + one STRETCH crossing)
--   wall gap    = previous tier's climb * 1.020   (you get 97%+ of the way on a full
--                 tank and still cannot land -- that 2% IS the "buy a gut" message)
--   stretch gap = own tier's climb / 1.031        (97% of the new tank)
--   IslandOrder.SLOT_POS is solved from these; do not move an island without
--   re-checking  climb[k] >= own gaps  and  climb[k] + coast < next tier's gaps.
--======================================================================

local FlightTuning = {}

-- ===== WALL-CLOCK =====
-- 22.75 s of thrust on a full tank at tier 1 and 2; later tiers are stretched by
-- TIER_TIME. speed = climb / time, so this is the ONLY pacing dial: it changes how
-- long a flight takes without moving a single gate.
FlightTuning.FLIGHT_SECONDS = 22.75
FlightTuning.TANK_SECONDS   = FlightTuning.FLIGHT_SECONDS

-- ===== COINS =====
-- Coins are paid per STUD TRAVELLED, not per height. COIN_PER_STUD_BASE / SPACING_SCALE
-- is the live rate (3.52). A landing pays gap * rate (climb only). A failed flight pays
-- climb * rate * (1 + DESCENT_PAY_MULT) = 3x the climb -- that asymmetry is the single
-- lever that sets flight counts. Never fold the descent into the base rate.
FlightTuning.COIN_PER_STUD_BASE = 2.4024
FlightTuning.SPACING_SCALE      = 0.6825   -- must match IslandOrder.SPACING_SCALE
FlightTuning.COIN_PER_STUD      = FlightTuning.COIN_PER_STUD_BASE / FlightTuning.SPACING_SCALE
FlightTuning.DESCENT_PAY_MULT   = 2.0
FlightTuning.MARGIN             = 1.08     -- referenced by powerShortfall only (NOT WIRED)
FlightTuning.COIN_TICK          = 0.23     -- seconds between coin payouts during flight

-- The 2x fall bonus is PREPAID during the climb when the tank obviously cannot make it:
-- if climbFor(tank, power) < gap * PREPAY_SAFETY the flight is already a failure and every
-- climbed stud pays 3x on the spot. One-sided on purpose -- a prepaid flight cannot surprise
-- us by landing, which is the only case that would overpay.
FlightTuning.PREPAY_SAFETY = 0.90

-- Thrust ends -> leftover upward velocity is damped to 40%, so the free ballistic coast is
-- 0.4^2 = 16% of undamped. Without it the coast can push a tier over the next wall and make a
-- gut optional. Gates are verified against climb + coast.
FlightTuning.COAST_DAMPING = 0.4

-- A freshly bought gut arrives EMPTY. (Was 1.10 -> 0.30 -> 0.15 -> 0: at 1.10 every gut
-- purchase handed out a free crossing.) Never auto-fill a purchased tank.
FlightTuning.COURTESY_FRACTION  = 0
FlightTuning.COURTESY_FULL_TANK = false

-- ===== SPEED TAPER =====
-- Eight bands across the tank. Index 1 is the EMPTY end, index 8 is full: a full tank flies
-- 5.8% above the tier mean, a nearly-dry one 5.6% below. Mean is EXACTLY 1.0 -- that is what
-- lets fullTankClimb() return tier.climb directly. Keep the taper mild (~12% spread).
local SPEED_SHAPE = { 0.944, 0.960, 0.975, 0.991, 1.007, 1.024, 1.041, 1.058 }
local NBANDS = #SPEED_SHAPE
local CUM = { 0 }
for i, v in ipairs(SPEED_SHAPE) do CUM[i + 1] = CUM[i] + v / NBANDS end
FlightTuning.SPEED_SHAPE = SPEED_SHAPE

-- ===== TIERS =====
-- maxPower MUST equal StomachTiers' (PlayerStats.stomachTiers) row for row. climb = what a
-- full tank travels. Tier climb growth stays in 1.35-1.50x.
FlightTuning.BASE_TIERS = {
	{ maxPower = 120,  climb = 853.5  },  -- Tiny Gut     (tutorial: c1)
	{ maxPower = 270,  climb = 1279.5 },  -- Small Gut    (c2 wall, c3 stretch)
	{ maxPower = 470,  climb = 1848.0 },  -- Medium Gut   (c4, c5)
	{ maxPower = 620,  climb = 2559.0 },  -- Large Gut    (c6, c7)
	{ maxPower = 1080, climb = 3555.0 },  -- XL Gut       (c8, c9)
	{ maxPower = 1710, climb = 4977.0 },  -- XXL Gut      (c10, c11)
	{ maxPower = 2600, climb = 7110.0 },  -- Iron Gut     (c12, c13)
}
FlightTuning.TIERS = FlightTuning.BASE_TIERS

-- Per-tier flight-duration factor. speed = climb / (FLIGHT_SECONDS * factor), so this buys
-- wall-clock WITHOUT moving climb. Capped from below by "speed must rise with every gut":
-- the Small Gut flies 56.2 studs/s, so Medium's factor can never exceed 1.44.
local TIER_TIME = {
	{ 120 , 1.00 },
	{ 270 , 1.00 },
	{ 470 , 1.35 },
	{ 620 , 1.50 },
	{ 1080, 1.55 },
	{ 1710, 1.60 },
	{ 2600, 1.60 },
}

-- The tier a TANK SIZE belongs to. Anything above the table (Infinite Gut) gets the top row.
function FlightTuning.tierFor(stomachMax: number)
	local max = tonumber(stomachMax) or 0
	for _, tier in ipairs(FlightTuning.TIERS) do
		if max <= tier.maxPower then return tier end
	end
	return FlightTuning.TIERS[#FlightTuning.TIERS]
end

function FlightTuning.timeScaleFor(stomachMax: number): number
	local max = tonumber(stomachMax) or 0
	for _, row in ipairs(TIER_TIME) do
		if max <= row[1] then return row[2] end
	end
	return TIER_TIME[#TIER_TIME][2]
end

function FlightTuning.tankSecondsFor(stomachMax: number): number
	return FlightTuning.TANK_SECONDS * FlightTuning.timeScaleFor(stomachMax)
end

-- %/sec the normalised 0-100 meter drains for this gut. The bar always empties in one flight.
function FlightTuning.drainRateFor(stomachMax: number): number
	return 100 / FlightTuning.tankSecondsFor(stomachMax)
end

-- Rise speed for the CURRENT (draining) power. `stomachMax` is not optional in spirit: the
-- band is a fraction of YOUR OWN tank, so the same 100 fuel is "nearly empty" on an Iron Gut
-- and "most of a tank" on a Tiny Gut. A caller that omits it silently gets tier 1 behaviour.
function FlightTuning.getFlightSpeed(power: number, stomachMax: number?): number
	local max = tonumber(stomachMax) or FlightTuning.TIERS[1].maxPower
	if max <= 0 then return 0 end
	local tier = FlightTuning.tierFor(max)
	local avg  = tier.climb / FlightTuning.tankSecondsFor(max)   -- the tier's mean speed
	local x    = math.clamp((tonumber(power) or 0) / max, 0, 1)
	local band = math.min(NBANDS, math.floor(x * NBANDS) + 1)
	return avg * SPEED_SHAPE[band]
end

-- Distance a partially-filled tank travels. NO time term -- keep it that way.
function FlightTuning.climbFor(stomachMax: number, power: number): number
	local max = tonumber(stomachMax) or 0
	if max <= 0 then return 0 end
	local x = math.clamp((tonumber(power) or 0) / max, 0, 1)
	local j = math.min(NBANDS - 1, math.floor(x * NBANDS))
	return FlightTuning.tierFor(max).climb * (CUM[j + 1] + (x - j / NBANDS) * SPEED_SHAPE[j + 1])
end

-- Exact inverse: how full the tank must be to travel `distance`.
function FlightTuning.powerForClimb(stomachMax: number, distance: number): number
	local max  = tonumber(stomachMax) or 0
	local dist = tonumber(distance) or 0
	if max <= 0 or dist <= 0 then return 0 end
	local y = dist / FlightTuning.tierFor(max).climb
	if y >= 1 then return max end
	for j = 1, NBANDS do
		if CUM[j + 1] >= y then
			return max * ((j - 1) / NBANDS + (y - CUM[j]) / SPEED_SHAPE[j])
		end
	end
	return max
end

-- What a FULL tank climbs. A straight lookup because the shape averages 1.
function FlightTuning.fullTankClimb(stomachMax: number): number
	local max = tonumber(stomachMax) or 0
	if max <= 0 then return 0 end
	return FlightTuning.tierFor(max).climb
end

-- The gap the player must cross FROM a given island -- the one their next flight has to clear.
function FlightTuning.gapFromSlot(slot: number): number?
	local s = math.floor(tonumber(slot) or 0)
	if s < 1 then return nil end
	local ok, IslandOrder = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("IslandOrder"))
	end)
	if not ok or not IslandOrder then return nil end
	local here, next_ = IslandOrder.SLOT_POS[s], IslandOrder.SLOT_POS[s + 1]
	if not (here and next_) then return nil end
	return next_.y - here.y
end

-- What a purchased gut holds the moment it is bought. COURTESY_FRACTION = 0 -> nothing.
function FlightTuning.courtesyPower(stomachMax: number, gap: number?): number
	local max = tonumber(stomachMax) or 0
	if max <= 0 then return 0 end
	if FlightTuning.COURTESY_FULL_TANK then return max end
	local g = tonumber(gap)
	if not g or g <= 0 then return 0 end
	return math.floor(math.min(max, FlightTuning.powerForClimb(max, g) * FlightTuning.COURTESY_FRACTION) + 0.5)
end

-- NOT WIRED. "How much more do I need" is the honest HUD question, but never pay its answer
-- out as coins: an anti-strand priced on it handed over a whole crossing on the first dry landing.
function FlightTuning.powerShortfall(stomachMax: number, currentPower: number): number
	local max = tonumber(stomachMax) or 0
	if max <= 0 then return 0 end
	local need = (1 / FlightTuning.MARGIN) * max
	return math.max(0, need - (tonumber(currentPower) or 0))
end

return FlightTuning
