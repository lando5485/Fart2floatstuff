--======================================================================
-- FlightTuning.luau  (ModuleScript -> ReplicatedStorage.Shared)  -- CandyRealm
--======================================================================
-- THE FLIGHT MATH, ported from the Dino Realm's FlightTuning verbatim (same solved
-- numbers -- CandyRealm uses the same 13-slot tower, so the solve transfers exactly).
-- Kept in one place because PropelSystem_AllInOne.client (burns the tank) and the
-- purchase servers (fill it) must agree, and IslandOrder owns the gaps both are
-- tuned against.
--
-- THE MODEL:
--   gasMeter  = (CurrentPower / StomachMax) * 100      -- normalised 0..100
--   every frame:  gasMeter -= DRAIN_RATE * dt
--                 CurrentPower = (gasMeter/100) * StomachMax
--   riseSpeed = getFlightSpeed(CurrentPower)            -- BANDS, by CURRENT power
--   BodyVelocity.Y = riseSpeed
--
-- The band lookup reads the power that is DRAINING, so a flight starts in the top
-- band its gut can reach and steps DOWN through every band beneath it as the tank
-- empties. That taper is the mechanic.
--
-- WHY THE BANDS ARE SOLVED, NOT GUESSED
-- With a tapering speed the climb is the integral of the band speeds over the time
-- spent in each. Gas falls linearly, so for a gut of size M the flight spends
--       t_j = FLIGHT_SECONDS * (M_j - M_(j-1)) / M     seconds in band j
-- and the total climb is
--       climb(M_k) = (FLIGHT_SECONDS / M_k) * SUM_j[ v_j * (M_j - M_(j-1)) ]
-- Requiring climb(M_k) = gap_k * MARGIN for every tier gives a triangular system
-- with exactly one solution, which is the TIERS table below. Hand-editing one row
-- silently breaks every tier above it -- re-run the solve instead.
--======================================================================

local FlightTuning = {}

-- 45 s of thrust on a full tank, for EVERY gut. The meter is normalised, so tank SIZE
-- does not change how long you fly -- it changes how fast, and so how far. Sized from
-- the pacing brief: ~3 minutes to clear an island in 3-5 attempts, so one attempt is
-- 180/4 = 45. This is THE pacing dial -- everything below is solved from it.
FlightTuning.FLIGHT_SECONDS = 45

-- How far a full tank overshoots the gap it is tuned for: gas spent steering can
-- still cost you the landing.
FlightTuning.MARGIN = 1.08

-- Every tier gets the SAME tankSeconds -- constant leg length at every tier; distance
-- is bought with SPEED instead.
FlightTuning.TANK_SECONDS = FlightTuning.FLIGHT_SECONDS

function FlightTuning.tankSecondsFor(_stomachMax: number): number
	return FlightTuning.TANK_SECONDS
end

-- gas/sec on the normalised 0-100 meter (~2.222).
FlightTuning.DRAIN_RATE = 100 / FlightTuning.TANK_SECONDS

-- GUT TIER -> THE GAP IT OPENS. ONE TIER PER CROSSING: TEN gut sizes, TEN gaps, and row k
-- here is the crossing from slot k to slot k+1 in IslandOrder.SLOT_POS.
--
-- TEN, NOT TWELVE: this world has eleven islands (1,2,3,4,5,8,9,11,13,14,15 -- 6/7/10/12
-- are not built), so there are ten crossings to wall. The bands below are the Dino Realm's
-- solve TRUNCATED at tier 10, which is exact rather than approximate: the triangular system
-- solves bottom-up, so dropping the top rows leaves every remaining row's speed untouched.
--
-- THE maxPower COLUMN MUST EQUAL StomachTiers.LIST's, ROW FOR ROW. The band widths ARE
-- those numbers, so a tank size that exists in the shop and not here lands mid-band and
-- climbs the wrong distance, silently.
--
-- EVERY TANK CARRIES +10 over the solved 100/140/190/260/355/485/665/910/1250/1715 sizes --
-- capacity only; effective margin lands at ~1.072 instead of 1.080. Full-tank climb vs the
-- gap each tier must clear, and vs the gap ABOVE it (the check that keeps the shop mandatory):
--     Gumdrop     110 ->  3645  needs 3375, next 3780      Caramel     675 ->  7143  needs 6663, next 7463
--     Taffy       150 ->  4053  needs 3780, next 4234      Marshmallow 920 ->  8012  needs 7463, next 8359
--     Cookie      200 ->  4526  needs 4234, next 4742      Fudge      1260 ->  8985  needs 8359, next 9362
--     Jelly       270 ->  5066  needs 4742, next 5311      Licorice   1725 -> 10074  needs 9362 (summit)
--     Gummy       365 ->  5678  needs 5311, next 5949
--     Choco       495 ->  6368  needs 5949, next 6663
FlightTuning.TIERS = {
	{ maxPower = 110,  gap = 3375, speed = 81.0 },  -- Gumdrop Belly      slot 1 -> 2
	{ maxPower = 150,  gap = 3780, speed = 115.0 }, -- Taffy Tummy        slot 2 -> 3
	{ maxPower = 200,  gap = 4234, speed = 132.1 }, -- Cookie Gut         slot 3 -> 4
	{ maxPower = 270,  gap = 4742, speed = 146.9 }, -- Jelly Belly        slot 4 -> 5
	{ maxPower = 365,  gap = 5311, speed = 164.8 }, -- Gummy Gut          slot 5 -> 6
	{ maxPower = 495,  gap = 5949, speed = 184.6 }, -- Choco Stomach      slot 6 -> 7
	{ maxPower = 675,  gap = 6663, speed = 206.1 }, -- Caramel Core       slot 7 -> 8
	{ maxPower = 920,  gap = 7463, speed = 231.2 }, -- Marshmallow Middle slot 8 -> 9
	{ maxPower = 1260, gap = 8359, speed = 258.2 }, -- Fudge Furnace      slot 9 -> 10
	{ maxPower = 1725, gap = 9362, speed = 289.4 }, -- Licorice Loop      slot 10 -> 11 (top coin gut)
	-- Sugar Rush Gut (Robux). Deliberately ABOVE the solved ladder rather than the next step
	-- in it: it is a purchase, not a progression rung. `gap` is notional -- there is no
	-- crossing above the summit until islands 6/7/10/12 are built.
	{ maxPower = math.huge, gap = 10485, speed = 420.0 },
}

-- The band for the CURRENT (draining) power, so speed tapers through the flight.
function FlightTuning.getFlightSpeed(power: number): number
	local p = tonumber(power) or 0
	for _, tier in ipairs(FlightTuning.TIERS) do
		if p <= tier.maxPower then return tier.speed end
	end
	return FlightTuning.TIERS[#FlightTuning.TIERS].speed
end

-- The tier a TANK SIZE belongs to (not a draining power) -- used by the shop.
function FlightTuning.tierFor(stomachMax: number)
	local max = tonumber(stomachMax) or 0
	for _, tier in ipairs(FlightTuning.TIERS) do
		if max <= tier.maxPower then return tier end
	end
	return FlightTuning.TIERS[#FlightTuning.TIERS]
end

-- What a FULL tank of this size actually climbs, by the integral described above.
-- This is the check the BANDS were solved against; it is the only thing that will
-- tell you a hand-edited speed has broken a tier.
function FlightTuning.fullTankClimb(stomachMax: number): number
	local max = tonumber(stomachMax) or 0
	if max <= 0 then return 0 end
	local sum, prev = 0, 0
	for _, tier in ipairs(FlightTuning.TIERS) do
		local top = math.min(tier.maxPower, max)
		if top > prev then
			sum += tier.speed * (top - prev)
			prev = top
		end
		if top >= max then break end
	end
	return (FlightTuning.FLIGHT_SECONDS / max) * sum
end

-- POWER NEEDED TO CLIMB `distance` IN A TANK OF `stomachMax`. The inverse of
-- fullTankClimb: how full must the tank be to go this far. Same integral, solved
-- for p by walking the bands -- no search, no approximation.
function FlightTuning.powerForClimb(stomachMax: number, distance: number): number
	local max = tonumber(stomachMax) or 0
	local dist = tonumber(distance) or 0
	if max <= 0 or dist <= 0 then return 0 end
	local need = dist * max / FlightTuning.FLIGHT_SECONDS   -- the S(p) we must reach
	local sum, prev = 0, 0
	for _, tier in ipairs(FlightTuning.TIERS) do
		local top = math.min(tier.maxPower, max)
		if top > prev then
			local span = (top - prev) * tier.speed
			if sum + span >= need then
				return math.min(max, prev + (need - sum) / tier.speed)
			end
			sum, prev = sum + span, top
		end
		if top >= max then break end
	end
	return max   -- a full tank is not enough; the caller gets everything there is
end

-- COURTESY FILL: what CurrentPower a gut should hold the moment it is bought.
-- `gap` is the crossing actually in front of the player (you buy a gut at the END of
-- the previous tier, so the very next crossing is the SHORTER one you are standing at
-- the bottom of -- sizing the fill against the new tank's own gap over-fills it).
-- Called with no gap it falls back to whole-tank behaviour.
function FlightTuning.courtesyPower(stomachMax: number, gap: number?): number
	local max = tonumber(stomachMax) or 0
	if max <= 0 then return 0 end
	local g = tonumber(gap)
	if not g or g <= 0 then
		return math.floor(math.min(1, (1 / FlightTuning.MARGIN) * 1.10) * max + 0.5)
	end
	local need = FlightTuning.powerForClimb(max, g)
	return math.floor(math.min(max, need * 1.10) + 0.5)
end

-- The gap the player must cross FROM a given climb slot -- i.e. the one their next
-- flight has to clear. Pairs with courtesyPower; keep in step with IslandOrder.SLOT_POS.
function FlightTuning.gapFromSlot(slot: number): number?
	local s = math.floor(tonumber(slot) or 0)
	if s < 1 then return nil end
	local ok, IslandOrder = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("IslandOrder"))
	end)
	if not ok or not IslandOrder then return nil end
	local here, next_ = IslandOrder.SLOT_POS[s], IslandOrder.SLOT_POS[s + 1]
	if not (here and next_) then return nil end
	return next_.Y - here.Y
end

return FlightTuning
