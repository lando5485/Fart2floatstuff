--======================================================================
-- BeamKnockback.lua  (ModuleScript)
--======================================================================
-- The SERVER side of the "knock-back" for the RAINBOW BEAMS hazard.
--
-- ★ IMPORTANT ★ This module does NOT move the player, touch the fart meter,
-- coins, flight, food, guts, or anything else. The ENTIRE hit response --
-- restoring the launch meter + blasting the player back to the launch
-- island -- is the pre-built client function `_G.applyBeamHit()`.
--
-- All this module does is: take the players the collision module flagged as
-- hit and, with a PER-PLAYER DEBOUNCE, fire `RainbowBeamSync:FireClient(
-- player, "hit")` to each. The client's RainbowBeamUI handler then calls
-- `_G.applyBeamHit()` (itself guarded by `_G.beamBlasting`).
--
-- The debounce (CONFIG.HIT_DEBOUNCE, ~2s) means one crossing = one rewind:
-- we won't spam a player with hits every tick while they're inside a beam.
--======================================================================

local BeamKnockback = {}

-- Wired by init().
local CONFIG = nil
local RainbowBeamSync = nil

-- Per-player debounce: [player] = os.clock() time the debounce expires.
local nextHitAllowed = {}

--------------------------------------------------------------------
-- init(config, syncEvent): wire CONFIG + the RemoteEvent (owned by manager).
--------------------------------------------------------------------
function BeamKnockback.init(config, syncEvent)
	CONFIG = config
	RainbowBeamSync = syncEvent
end

--------------------------------------------------------------------
-- notifyHits(hits): for each hit { player = ... }, if its debounce has
-- expired, fire the per-client "hit" message and re-arm the debounce.
-- Returns how many players were actually notified this call (for logging).
--------------------------------------------------------------------
function BeamKnockback.notifyHits(hits)
	if not hits or #hits == 0 then return 0 end

	local now = os.clock()
	local debounce = CONFIG.HIT_DEBOUNCE or 2.0
	local notified = 0

	for _, hit in ipairs(hits) do
		local player = hit.player
		local allowedAt = nextHitAllowed[player]
		if not allowedAt or now >= allowedAt then
			-- Re-arm the debounce BEFORE firing so duplicate hits this tick
			-- (shouldn't happen -- collision dedupes per player -- but safe).
			nextHitAllowed[player] = now + debounce
			-- Tell THIS client to run the pre-approved rewind. The client
			-- guards with _G.beamBlasting, so an in-progress rewind is skipped.
			RainbowBeamSync:FireClient(player, "hit")
			notified = notified + 1
		end
	end

	return notified
end

--------------------------------------------------------------------
-- clearPlayer(player): drop a leaving player's debounce entry (no leak).
--------------------------------------------------------------------
function BeamKnockback.clearPlayer(player)
	nextHitAllowed[player] = nil
end

--------------------------------------------------------------------
-- reset(): wipe all debounce state (e.g. when the band empties).
--------------------------------------------------------------------
function BeamKnockback.reset()
	nextHitAllowed = {}
end

return BeamKnockback
