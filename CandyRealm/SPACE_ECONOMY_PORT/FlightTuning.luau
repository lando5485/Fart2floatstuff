--!strict
--======================================================================
-- FlightTuning.luau  (ReplicatedStorage.Shared.FlightTuning)  -- CandyRealm
-- SPACE-REALM PORT: replaces the dino/candy band-solve with the space flight model.
--======================================================================
-- ===== READ THIS BEFORE TOUCHING ANYTHING =====
-- This file is NOT a retune of the old FlightTuning. It is a DIFFERENT MODEL, and the two
-- cannot be mixed. If you keep the old one, the ported gaps and gut sizes are meaningless.
--
--   OLD (dino/candy)                        NEW (space)
--   ----------------------------------      ----------------------------------
--   FLIGHT_SECONDS = 45 for EVERY gut       tankSeconds is PER TIER (28 -> 98)
--   distance bought with SPEED              distance bought with TANK DURATION
--   band speeds SOLVED per tier             ONE fixed band table, shared by all tiers
--   wall = no tank reaches the next gap     wall = HARD CEILING (island Y + 400)
--   gaps must grow >8% or guts go optional  gaps grow by a flat +200 second difference
--
-- The old model normalised the meter, so tank SIZE changed how FAST you flew, not how long.
-- That made the band speeds a fragile simultaneous solve -- hand-edit one row and every tier
-- above it silently breaks. The space model does the opposite: speed comes from ONE fixed
-- table everybody shares, and a bigger tank simply burns LONGER. Nothing is coupled, so a
-- tier can be retuned on its own.
--
-- ===== THE MODEL =====
--   gas          = RAW power, 0 .. StomachMax  (NOT normalised)
--   drainRaw     = StomachMax / tankSeconds    -- per second
--   every frame:   gas -= drainRaw * dt
--   riseSpeed    = riseSpeedFor(gas)           -- BANDS, by CURRENT raw power
--   BodyVelocity.Y = riseSpeed
--
-- So a full tank lasts exactly that tier's tankSeconds, and the band lookup reads the power
-- that is DRAINING -- a flight starts in the top band its gut can reach and steps DOWN
-- through every band beneath it as the tank empties. That taper is the mechanic.
--
-- ===== WHY REACH IS GENEROUS AND THAT IS FINE =====
-- StomachTiers sizes each tank as ceil10(gap * 1.18 / 2.16) -- a +18% margin against a
-- STUDS_PER_POWER heuristic of 2.16. The bands below actually deliver MORE than that (19% to
-- 41% depending on the rung; see the audit print at the bottom). That mismatch is inherited
-- from the Space Realm and is DELIBERATE -- do not "fix" it by shrinking tanks:
--   * The heuristic is a conservative floor used for the boot warning, not a promise.
--   * Over-reach cannot break progression, because reach is NOT the wall. getMaxHeight() is.
--     You can carry a tank that could physically climb three islands and still be stopped
--     dead at your own island + 400 studs.
--   * A generous margin is what stops a player who bought exactly the right gut from being
--     stranded by gas spent steering, a low takeoff, or a moment's hesitation.
--======================================================================

local FlightTuning = {}

-- Fixed climb speed for the Sugar Rush gut (infinite power -- no drain, so no taper).
FlightTuning.INFINITE_RISE_SPEED = 350

-- Sideways steering speed while flying (flat, all tiers).
FlightTuning.HORIZONTAL_SPEED = 48

-- BodyVelocity maxforce: weak on X/Z so steering feels like drift, strong on Y.
FlightTuning.BODYVEL_MAXFORCE = Vector3.new(50000, 1e6, 50000)

-- How often (s) the client reports gas to the server.
FlightTuning.GAS_SYNC_INTERVAL = 0.2

-- Conservative studs-per-power used ONLY by the boot reach warning in StomachTiers.
-- The bands below beat it; see "WHY REACH IS GENEROUS" above.
FlightTuning.STUDS_PER_POWER = 2.16

-- ===== THE BANDS =====
-- Rise speed (studs/sec) by CURRENT raw power remaining. ONE table for every tier -- the
-- thresholds are NOT tier capacities and must not be re-derived from them. Ported verbatim
-- from the Space Realm; the twelve-island extension needed no new bands, because the top
-- band already covers every tank above 3,218 and the extra distance comes from tankSeconds.
FlightTuning.BANDS = {
	{ upTo = 100,          speed = 40 },
	{ upTo = 182,          speed = 62 },
	{ upTo = 611,          speed = 84 },
	{ upTo = 1075,         speed = 126 },
	{ upTo = 2146,         speed = 144 },
	{ upTo = 3218,         speed = 226 },
	{ upTo = math.huge,    speed = 280 },
}

--[[ Rise speed for the power remaining right now. ]]
function FlightTuning.riseSpeedFor(power: number): number
	local p = tonumber(power) or 0
	for _, band in ipairs(FlightTuning.BANDS) do
		if p <= band.upTo then
			return band.speed
		end
	end
	return FlightTuning.BANDS[#FlightTuning.BANDS].speed
end

--[[ Raw power burned per second for a tier: a full tank lasts exactly tankSeconds. ]]
function FlightTuning.drainRateFor(maxPower: number, tankSeconds: number): number
	local m, t = tonumber(maxPower) or 0, tonumber(tankSeconds) or 1
	if t <= 0 then
		return 0
	end
	return m / t
end

--[[
	What a FULL tank of `maxPower` actually climbs, given its `tankSeconds`.

	Gas falls linearly, so a tank of size M spends
	    t_j = tankSeconds * (bandWidth_j / M)   seconds in band j
	and the total climb is
	    (tankSeconds / M) * SUM_j[ speed_j * bandWidth_j ]
	This is the ONLY thing that will tell you a hand-edited band or tankSeconds has broken a
	tier. StomachTiers' boot audit calls it.
]]
function FlightTuning.fullTankClimb(maxPower: number, tankSeconds: number): number
	local max = tonumber(maxPower) or 0
	local ts = tonumber(tankSeconds) or 0
	if max <= 0 or ts <= 0 then
		return 0
	end
	local sum, prev = 0, 0
	for _, band in ipairs(FlightTuning.BANDS) do
		local top = math.min(band.upTo, max)
		if top > prev then
			sum += band.speed * (top - prev)
			prev = top
		end
		if top >= max then
			break
		end
	end
	return (ts / max) * sum
end

--[[
	POWER NEEDED to climb `distance` in a tank of `maxPower`/`tankSeconds` -- the inverse of
	fullTankClimb, solved by walking the bands. No search, no approximation. Used by the
	courtesy fill so a freshly bought gut holds enough to actually make the hop in front of it.
]]
function FlightTuning.powerForClimb(maxPower: number, tankSeconds: number, distance: number): number
	local max = tonumber(maxPower) or 0
	local ts = tonumber(tankSeconds) or 0
	local dist = tonumber(distance) or 0
	if max <= 0 or ts <= 0 or dist <= 0 then
		return 0
	end
	local need = dist * max / ts -- the band-area we must accumulate
	local sum, prev = 0, 0
	for _, band in ipairs(FlightTuning.BANDS) do
		local top = math.min(band.upTo, max)
		if top > prev then
			local span = (top - prev) * band.speed
			if sum + span >= need then
				return math.min(max, prev + (need - sum) / band.speed)
			end
			sum, prev = sum + span, top
		end
		if top >= max then
			break
		end
	end
	return max -- a full tank is not enough; the caller gets everything there is
end

--[[
	COURTESY FILL: what power a gut should hold the moment it is bought.
	`gap` is the crossing actually in front of the player. Called with no gap it falls back to
	a near-full tank.
]]
function FlightTuning.courtesyPower(maxPower: number, tankSeconds: number, gap: number?): number
	local max = tonumber(maxPower) or 0
	if max <= 0 then
		return 0
	end
	local g = tonumber(gap)
	if not g or g <= 0 then
		return math.floor(max * 0.9 + 0.5)
	end
	local need = FlightTuning.powerForClimb(max, tankSeconds, g)
	return math.floor(math.min(max, need * 1.10) + 0.5)
end

-- Boot audit: print what every tier actually climbs vs the gap it has to clear.
if game:GetService("RunService"):IsServer() then
	local ok, StomachTiers = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("StomachTiers"))
	end)
	local ok2, IslandOrder = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("IslandOrder"))
	end)
	if ok and ok2 and StomachTiers and IslandOrder then
		print("[FlightTuning] band-model reach per tier (the real number; STUDS_PER_POWER is only a floor)")
		for i = 2, StomachTiers.MAX_TIER do
			local tier = StomachTiers.CANDY_GUTS[i]
			local gap = IslandOrder.GAPS[i - 1] or 0
			local reach = FlightTuning.fullTankClimb(tier.maxPower, tier.tankSeconds)
			local margin = (gap > 0) and ((reach / gap - 1) * 100) or 0
			print(("[FlightTuning] %s: climbs %.0f vs gap %d (+%.0f%%)")
				:format(tier.name, reach, gap, margin))
			if gap > 0 and reach < gap then
				warn(("[FlightTuning] %s CANNOT clear its own gap (%.0f < %d) -- the rung is unplayable")
					:format(tier.name, reach, gap))
			end
		end
	end
end

return FlightTuning
