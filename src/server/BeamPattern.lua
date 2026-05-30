--======================================================================
-- BeamPattern.lua  (ModuleScript)
--======================================================================
-- Pattern / Timing brain for the "RAINBOW BEAMS" hazard.
--
-- PURE LOGIC -- this module creates NO parts and touches NO gameplay. Each
-- cycle the manager asks it "which beams fire this cycle, in THIS band?" and
-- it returns a small list of beam descriptors:
--     { height = <Y>, angle = <radians>, side = "left"|"right" }
--
-- DESIGN GOALS (from the spec):
--   * STEADY, READABLE BEAT: the manager runs a fixed BEAM_INTERVAL /
--     BEAM_DURATION, so beams pulse on a learnable rhythm.
--   * PER-CYCLE VARIATION: small random tilt (BEAM_ANGLE_VARIANCE) and a
--     small timing offset so a single memorised route never works forever.
--   * ★ ALWAYS A SAFE LANE ★ The corridor band is split into candidate
--     height SLOTS; we deliberately RESERVE one whole slot (>= SAFE_LANE_MIN
--     studs tall) as a guaranteed open vertical gap with NO beam, and only
--     place beams in the OTHER slots. So a clean vertical crossing always
--     exists -- the hazard is dodgeable by design, never an unbroken wall.
--======================================================================

local BeamPattern = {}

-- Wired by init() (CONFIG is owned by the manager).
local CONFIG = nil

--------------------------------------------------------------------
-- init(config): wire the shared CONFIG.
--------------------------------------------------------------------
function BeamPattern.init(config)
	CONFIG = config
end

-- A tiny per-cycle phase counter so the chosen safe-lane slot and the angle
-- jitter drift over time (the route keeps changing). Wraps harmlessly.
local cycle = 0

--------------------------------------------------------------------
-- planCycle(band): given a band { lo = <Y>, hi = <Y> }, return the list of
-- beam descriptors to fire THIS cycle. Guarantees one reserved open lane.
--
-- HOW THE SAFE LANE IS GUARANTEED:
--   1) The band's usable height (minus a margin top & bottom) is divided
--      into N evenly spaced SLOTS, where N is chosen so each slot is at
--      least SAFE_LANE_MIN studs tall.
--   2) We pick ONE slot index to RESERVE as the open lane and never place a
--      beam there. The reserved slot rotates each cycle so the safe lane
--      moves around (no static memorised path), but there is ALWAYS exactly
--      one untouched, >= SAFE_LANE_MIN-tall vertical gap.
--   3) From the REMAINING slots we place up to BEAMS_PER_CYCLE beams (capped
--      so we can never fill every slot). Each beam gets a random side and a
--      small angle tilt within +/- BEAM_ANGLE_VARIANCE.
--------------------------------------------------------------------
function BeamPattern.planCycle(band)
	cycle = cycle + 1

	local lo, hi = band.lo, band.hi
	local safeLane = (CONFIG and CONFIG.SAFE_LANE_MIN) or 90
	local perCycle = (CONFIG and CONFIG.BEAMS_PER_CYCLE) or 2
	local angleVar = math.rad((CONFIG and CONFIG.BEAM_ANGLE_VARIANCE) or 18)

	-- Keep beams off the very floor/ceiling of the band so a player entering
	-- or leaving the band is never instantly clipped.
	local margin = 40
	local usableLo = lo + margin
	local usableHi = hi - margin
	local usable = usableHi - usableLo
	if usable <= safeLane then
		-- Band too short to safely fit any beam AND a guaranteed lane: fire none.
		return {}
	end

	-- Number of slots: each must be >= SAFE_LANE_MIN tall, and we need at
	-- least 2 (one reserved lane + one usable). More slots = more beam options.
	local slotCount = math.max(2, math.floor(usable / safeLane))
	local slotHeight = usable / slotCount

	-- Reserve ONE slot as the always-open lane; rotate it each cycle.
	local reservedSlot = (cycle % slotCount) + 1

	-- Build the list of slots we ARE allowed to place a beam in.
	local placeable = {}
	for s = 1, slotCount do
		if s ~= reservedSlot then
			table.insert(placeable, s)
		end
	end

	-- Shuffle the placeable slots (Fisher-Yates) so beam heights vary.
	for i = #placeable, 2, -1 do
		local j = math.random(1, i)
		placeable[i], placeable[j] = placeable[j], placeable[i]
	end

	-- HARD SAFETY: never place a beam in more than (slotCount - 1) slots, so
	-- the reserved lane is always preserved. perCycle is the soft cap.
	local toPlace = math.min(perCycle, #placeable, slotCount - 1)

	local descriptors = {}
	for n = 1, toPlace do
		local slot = placeable[n]
		-- Centre of the slot, with a small per-beam vertical jitter inside it
		-- so beams don't always sit dead-centre (still inside their slot, so
		-- the reserved lane stays clear).
		local slotCenter = usableLo + (slot - 0.5) * slotHeight
		local jitter = (math.random() - 0.5) * (slotHeight * 0.4)
		local height = slotCenter + jitter

		-- FLAT / HORIZONTAL: beams fire LEVEL (parallel to the ground), never tilted vertically. All the
		-- per-cycle variety stays in the HORIZONTAL plane — which slots fire, the in-slot height jitter, and
		-- the firing side — but the vertical tilt is removed, so every beam is a flat side-to-side sweep.
		-- (angle = 0 also means cos(angle) = 1, so a beam's vertical reach is exactly BEAM_HIT_RADIUS, which
		-- only WIDENS the guaranteed safe gap vs the old tilted beams — the reserved-lane guarantee still holds.)
		local angle = 0

		-- BOTH SIDES: alternate the firing side across the beams in this cycle
		-- (left shoots right, right shoots left), with a per-cycle flip so the
		-- starting side isn't fixed. With >=2 beams, both directions always
		-- appear -- never all from one side.
		local side = (((n + cycle) % 2) == 0) and "left" or "right"

		table.insert(descriptors, { height = height, angle = angle, side = side })
	end

	return descriptors
end

--------------------------------------------------------------------
-- timingOffset(): a small random extra wait (seconds) added to the steady
-- BEAM_INTERVAL so the beat has a touch of organic variation (no perfectly
-- metronomic, trivially-memorised cadence). Small + bounded.
--------------------------------------------------------------------
function BeamPattern.timingOffset()
	-- +/- 0.2s wobble (was 0.35): kept small so BEAM_INTERVAL - wobble (2.8 - 0.2 = 2.6s)
	-- stays >= the beam lifecycle (2.45s) -> cycles never overlap into a wall, while the
	-- beat still isn't perfectly metronomic.
	return (math.random() * 2 - 1) * 0.2
end

return BeamPattern
