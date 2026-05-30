--======================================================================
-- BeamCollision.lua  (ModuleScript)
--======================================================================
-- SERVER-AUTHORITATIVE proximity check for the "RAINBOW BEAMS" hazard.
--
-- Given the active beam descriptors (each a line segment p0 -> p1 from
-- BeamGeneration) and the live players, this returns the list of players
-- whose HumanoidRootPart is within CONFIG.BEAM_HIT_RADIUS studs of ANY
-- beam line. The math runs entirely on the server -- no client trust.
--
-- GATING (so a beam never grabs someone safely standing on an island):
--   * The player must be AIRBORNE (mid-flight). We treat "airborne" as the
--     Humanoid's FloorMaterial == Air. As a robust fallback we also require
--     them to be inside the active corridor band's Y range and not sitting
--     on the ground -- but FloorMaterial is the primary check.
--
-- This module decides WHO is hit; it does NOT notify anyone or move anyone.
-- The manager passes the hits to BeamKnockback, which fires the per-client
-- "hit" message. Pure read-only logic; touches no gameplay state.
--======================================================================

local BeamCollision = {}

local Players = game:GetService("Players")

-- Wired by init() (CONFIG owned by the manager).
local CONFIG = nil

--------------------------------------------------------------------
-- init(config): wire the shared CONFIG.
--------------------------------------------------------------------
function BeamCollision.init(config)
	CONFIG = config
end

--------------------------------------------------------------------
-- pointToSegmentDistance(p, a, b): shortest distance from point p to the
-- finite line segment a->b. Standard projection-clamped-to-[0,1] formula.
--------------------------------------------------------------------
local function pointToSegmentDistance(p, a, b)
	local ab = b - a
	local abLenSq = ab:Dot(ab)
	if abLenSq < 1e-6 then
		-- Degenerate segment (a == b): just the point distance.
		return (p - a).Magnitude
	end
	-- Projection parameter t of p onto the line, clamped to the segment.
	local t = (p - a):Dot(ab) / abLenSq
	t = math.clamp(t, 0, 1)
	local closest = a + ab * t
	return (p - closest).Magnitude
end

--------------------------------------------------------------------
-- isAirborne(character): true if the player is genuinely mid-flight and not
-- standing on an island. Primary signal: Humanoid.FloorMaterial == Air.
--------------------------------------------------------------------
local function isAirborne(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	-- FloorMaterial is Air when there is no ground directly beneath them.
	return humanoid.FloorMaterial == Enum.Material.Air
end

--------------------------------------------------------------------
-- getHitPlayers(beamDescriptors, band): return the list of players touching
-- a beam. `band` is the active { lo, hi } Y range, used as a belt-and-braces
-- bound (a hit only counts if the player is within the band's Y window).
--
-- Returns: array of { player = <Player>, hrp = <BasePart> }.
--------------------------------------------------------------------
function BeamCollision.getHitPlayers(beamDescriptors, band)
	local hits = {}
	if not beamDescriptors or #beamDescriptors == 0 then return hits end

	local radius = CONFIG.BEAM_HIT_RADIUS or 9

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if char and hrp then
			local pos = hrp.Position
			-- Band Y gate: only players inside the active band can be hit.
			local inBand = (not band) or (pos.Y >= band.lo and pos.Y <= band.hi)
			if inBand and isAirborne(char) then
				-- Test against every active beam line; nearest within radius = hit.
				for _, d in ipairs(beamDescriptors) do
					local dist = pointToSegmentDistance(pos, d.p0, d.p1)
					if dist <= radius then
						table.insert(hits, { player = player, hrp = hrp })
						break  -- one hit per player per tick is enough
					end
				end
			end
		end
	end

	return hits
end

return BeamCollision
