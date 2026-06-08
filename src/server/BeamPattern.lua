--======================================================================
-- BeamPattern.lua  (ModuleScript)
--======================================================================
-- Pattern / Timing brain for the "RAINBOW BEAMS" hazard.
--
-- PURE LOGIC -- this module creates NO parts and touches NO gameplay. When a
-- player ENTERS the beam band the manager asks it "lay out the spinning beams
-- for THIS band", and it returns ONE descriptor per persistent SPINNING beam:
--     { height = <Y>, offsetX, offsetZ,           -- the beam's hub (spin pivot)
--       spinSpeed = <signed rad/s>, angle = <start rad>, colorPhase = <0..1> }
--
-- DESIGN (from the spec):
--   * PERSISTENT SPINNING BLADES: the beams do NOT flicker on/off. Each is a
--     flat, horizontal rainbow line that spins continuously about its OWN hub
--     in the horizontal plane (like a helicopter blade), and stays visible the
--     whole time. The manager rotates them every frame; this module only
--     decides each blade's height, hub, spin speed/direction and colour.
--   * CHAOTIC PER-BEAM SPIN: every beam picks its OWN random spin SPEED and
--     DIRECTION (sign) + a random start angle, so no two beams spin alike.
--   * SPACED THROUGH THE CLIMB: one beam per evenly-spaced height SLOT (with a
--     little jitter) so the player threads past blade after blade on the way up.
--   * SAFETY IS INHERENT: because each blade spins, its line sweeps away from
--     any given spot periodically -> a timed gap to pass through always recurs.
--     The hub is nudged OFF the central climb axis (offset) so the centre line
--     itself gets periodic clear openings, not a permanently-blocked pivot.
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

--------------------------------------------------------------------
-- planLayout(band): given a band { lo = <Y>, hi = <Y> }, return ONE descriptor
-- per PERSISTENT SPINNING beam. The beams are spaced through the corridor's
-- height (one per evenly-spaced slot + jitter). Each gets its OWN random spin
-- speed + direction, a random start angle, a hub nudged off the central climb
-- axis, and a vivid rainbow hue. The manager spawns them once and spins them
-- forever (while the band is occupied) -- no on/off flicker.
--------------------------------------------------------------------
function BeamPattern.planLayout(band)
	local lo, hi = band.lo, band.hi
	local count   = (CONFIG and CONFIG.BEAM_COUNT) or 14
	local spinMin = (CONFIG and CONFIG.SPIN_SPEED_MIN) or 0.4
	local spinMax = (CONFIG and CONFIG.SPIN_SPEED_MAX) or 2.4
	local offMin  = (CONFIG and CONFIG.HUB_OFFSET_MIN) or 25
	local offMax  = (CONFIG and CONFIG.HUB_OFFSET_MAX) or 65

	-- Keep beams off the very floor/ceiling of the band so a player entering
	-- or leaving the band is never instantly clipped.
	local margin = 40
	local usableLo = lo + margin
	local usableHi = hi - margin
	local usable = usableHi - usableLo
	if usable <= 0 or count < 1 then
		return {}
	end

	local slotHeight = usable / count
	local descriptors = {}
	for n = 1, count do
		-- One beam per slot, centred with a little vertical jitter so the spacing
		-- isn't perfectly regular.
		local slotCenter = usableLo + (n - 0.5) * slotHeight
		local jitter = (math.random() - 0.5) * (slotHeight * 0.4)
		local height = slotCenter + jitter

		-- HUB OFFSET: nudge the spin pivot a random horizontal distance/direction
		-- OFF the central climb axis. The hub (always within HIT_RADIUS of the
		-- line) is the only permanently-blocked spot, so keeping it off-centre
		-- means the central climb line gets periodic clear openings as the blade
		-- sweeps past -- a timed pass through the middle always recurs.
		local offAng = math.random() * math.pi * 2
		local offMag = offMin + math.random() * (offMax - offMin)
		local offsetX = math.cos(offAng) * offMag
		local offsetZ = math.sin(offAng) * offMag

		-- OWN random spin SPEED + DIRECTION (sign) -> no two blades spin alike.
		local dir = (math.random() < 0.5) and -1 or 1
		local spinSpeed = dir * (spinMin + math.random() * (spinMax - spinMin))

		-- Random start angle so the blades aren't phase-aligned when they appear.
		local angle = math.random() * math.pi * 2

		-- Vivid per-beam rainbow hue (0..1) -> across the stack, red..violet.
		local colorPhase = math.random()

		table.insert(descriptors, {
			height = height,
			offsetX = offsetX, offsetZ = offsetZ,
			spinSpeed = spinSpeed, angle = angle,
			colorPhase = colorPhase,
		})
	end

	return descriptors
end

return BeamPattern
