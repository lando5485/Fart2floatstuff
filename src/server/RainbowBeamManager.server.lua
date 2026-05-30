--======================================================================
-- RainbowBeamManager.server.lua  (Script)
--======================================================================
-- Orchestrates the "RAINBOW BEAMS" aerial hazard.
--
-- Long, thin, glowing RAINBOW beams sweep ACROSS the vertical climb
-- corridor between certain islands. They EXTEND from a side of the gap,
-- HOLD on a steady readable beat, then RETRACT before the next cycle. A
-- flying player who drifts into a beam line gets their flight REWOUND --
-- but this script does NOT implement the rewind. It only DETECTS the hit
-- and tells the client to run the pre-built `_G.applyBeamHit()`.
--
-- DESIGN / SAFETY (mirrors the Meteor / UFO / Plane events' contract):
--   * SERVER-AUTHORITATIVE + SYNCED: this script (server) creates the beam
--     parts (they auto-replicate, so all clients see identical beams),
--     drives ALL timing, and decides ALL collisions. The RainbowBeamSync
--     RemoteEvent carries the per-client "hit" message + presentation cues.
--   * The ONLY gameplay effect is firing RainbowBeamSync:FireClient(player,
--     "hit"), which makes that client call `_G.applyBeamHit()` -- the
--     PRE-APPROVED snapshot/restore. This script NEVER reads or writes the
--     fart meter, flight, food, guts, island heights, coins, or earn rate.
--   * ACTIVE ONLY WHILE A PLAYER IS IN A BEAM BAND (like the propeller
--     planes): beams spawn/extend while at least one player is inside a beam
--     band's Y range, and everything is cleared the moment none are.
--   * Everything is capped (MAX_BEAMS, particle rates) + cleaned up on every
--     band-empty and on shutdown (no leaks).
--======================================================================

--======================================================================
-- ISLAND-Y REFERENCE (top-surface band Y values, from EventClient bands):
--   1=150  2=790  3=1680  4=2480  5=3580  6=4820  7=6460  8=8090
--   9=9879 10=12125 11=14247 12=17191 13=19938 14=23749
-- A "band" is the vertical GAP between two consecutive islands -- the same
-- corridor the propeller planes patrol (centred on X=0, Z=0).
--======================================================================

--======================================================================
-- CONFIG  -- EDIT ANYTHING HERE. Every value is tunable + commented.
--======================================================================
local CONFIG = {
	-- ---------------- STEADY BEAT (seconds) ----------------
	-- CLEAR 5s RESET CYCLE: beams fire, fully retract, then ~5s later the next cycle
	-- fires -- a clean, learnable rhythm. INVARIANT (must hold): BEAM_INTERVAL minus the
	-- timing wobble (BeamPattern.timingOffset, +/-0.2s) must stay >= the full beam
	-- lifecycle (BEAM_EXTEND_TIME + BEAM_DURATION + BEAM_RETRACT_TIME) so one cycle's
	-- beams are fully GONE before the next fires. Only ONE cycle of beams is ever live,
	-- so the per-cycle reserved safe lane is ALWAYS the live open route (never a wall).
	-- Lifecycle = 0.30 + 1.9 + 0.25 = 2.45s; min interval = 5 - 0.2 = 4.8s >= 2.45 (huge margin). ✓
	BEAM_INTERVAL    = 5,     -- seconds between beam cycles (clear, learnable 5s rhythm)
	BEAM_DURATION    = 1.9,   -- how long each beam HOLDS fully extended (well under the 5s interval -> full retract)
	BEAM_EXTEND_TIME = 0.30,  -- grow-out animation time (beam shoots across the corridor)
	BEAM_RETRACT_TIME = 0.25, -- shrink/fade animation time before the next cycle

	-- ---------------- PATTERN VARIATION ----------------
	BEAM_ANGLE_VARIANCE = 35, -- max +/- tilt (DEGREES). RAISED 18->35 for many more, more chaotic angles. At the
	                          -- corridor CENTRE a beam always sits at its slot HEIGHT (the tilt rotates ABOUT the
	                          -- centre point), so a wider tilt can NEVER move a beam into the reserved lane; it only
	                          -- grows a beam's vertical reach at centre to HIT_RADIUS/cos(tilt). SAFE_LANE_MIN below
	                          -- is sized so even a 35-deg neighbour beam can't close the reserved gap.
	BEAMS_PER_CYCLE  = 28,    -- BEAM COUNT per cycle. RAISED 7->28 -> a LOT more beams, densely filling the 8-9
	                          -- corridor from both sides. Beams ALTERNATE sides (left<->right) in BeamPattern so
	                          -- they cross from BOTH directions. ALWAYS capped to slotCount-1, so the ONE reserved
	                          -- safe lane can never be filled no matter how high this goes.
	SAFE_LANE_MIN    = 22,    -- min GUARANTEED open vertical gap (studs) with NO beam. SHRUNK 55->22: a tight,
	                          -- hard-to-spot opening the player must thread precisely. NEVER zero -> BeamPattern
	                          -- ALWAYS reserves one whole >=SAFE_LANE_MIN slot. Worst case (BOTH neighbour slots
	                          -- filled, each jittered toward the lane, at the steepest 35-deg tilt) still leaves a
	                          -- clear vertical window at the corridor centre: 1.6*slot - 2*(9/cos35) = ~13.7 > 0.

	-- ---------------- PERF CAPS ----------------
	MAX_BEAMS        = 32,    -- HARD cap on simultaneous beam parts. RAISED 10->32 so ALL BEAMS_PER_CYCLE (28)
	                          -- beams actually appear (the dense pattern). Clipping only ever REMOVES beams, never
	                          -- fills the reserved lane, so the cap can never wall the corridor.
	MAX_PARTICLE_RATE = 26,   -- HARD cap on every ParticleEmitter Rate (BeamEffects honours this)

	-- ---------------- COLLISION ----------------
	BEAM_HIT_RADIUS  = 9,     -- studs from a beam LINE that counts as a hit (point-to-segment)
	HIT_DEBOUNCE     = 2.0,   -- seconds a player is immune to further hits after one (1 crossing = 1 rewind)
	COLLISION_TICK   = 0.12,  -- seconds between server proximity checks while active

	-- ---------------- CORRIDOR (matches the plane hazard's lane) ----------------
	CORRIDOR_CENTER  = Vector3.new(0, 0, 0), -- X/Z centre of the climb corridor (Y is per-beam)
	CORRIDOR_WIDTH   = 300,   -- studs each beam spans across the corridor (wider than the plane loop so it truly crosses)

	-- ---------------- REAL BEAM BANDS (vertical gaps between islands) ----------------
	-- Beams live ONLY in the islands 8->9 gap now (island 8 Y=8202, island 9 Y=9732).
	BEAM_SPAWN_ZONES = {
		{ lo = 8202, hi = 9732 },   -- islands 8 -> 9 (the only beam zone)
	},

	-- ---------------- ZONE SELECT ----------------
	-- "real" => use BEAM_SPAWN_ZONES (the islands 8-9 gap). "1-2" => a short test
	-- band {150,790} for testing without climbing. The Pattern module guarantees a
	-- safe lane in either band.
	BEAM_TEST_ZONE = "real",  -- beams active in the islands 8-9 gap
}

--======================================================================
-- Services + module requires.
--======================================================================
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Sibling ModuleScripts created by this event (synced via default.project.json).
local BeamEffects    = require(ServerScriptService:WaitForChild("BeamEffects"))
local BeamPattern    = require(ServerScriptService:WaitForChild("BeamPattern"))
local BeamGeneration = require(ServerScriptService:WaitForChild("BeamGeneration"))
local BeamCollision  = require(ServerScriptService:WaitForChild("BeamCollision"))
local BeamKnockback  = require(ServerScriptService:WaitForChild("BeamKnockback"))

-- The sync RemoteEvent (added to ReplicatedStorage via default.project.json).
local RainbowBeamSync = ReplicatedStorage:WaitForChild("RainbowBeamSync")

-- Wire the modules together (CONFIG is owned here; pass it down).
BeamEffects.init(CONFIG)
BeamPattern.init(CONFIG)
BeamGeneration.init(CONFIG, BeamEffects)
BeamCollision.init(CONFIG)
BeamKnockback.init(CONFIG, RainbowBeamSync)

--======================================================================
-- BANDS: resolve the active beam bands from CONFIG (test vs real).
--======================================================================
local BEAM_BANDS
if CONFIG.BEAM_TEST_ZONE == "1-2" then
	BEAM_BANDS = { { lo = 150, hi = 790 } }   -- TEST: gap between islands 1 and 2
else
	BEAM_BANDS = CONFIG.BEAM_SPAWN_ZONES       -- REAL: the configured launch gaps
end

-- bandForY(y): the band a given Y sits inside, or nil if none.
local function bandForY(y)
	for _, b in ipairs(BEAM_BANDS) do
		if y >= b.lo and y <= b.hi then return b end
	end
	return nil
end

-- anyPlayerInBand(): the FIRST band that currently contains a player, else
-- nil. Mirrors the plane hazard: the hazard is live only while occupied.
local function anyPlayerInBand()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local b = bandForY(hrp.Position.Y)
			if b then return b end
		end
	end
	return nil
end

--======================================================================
-- State.
--======================================================================
local activeBand = nil       -- the band we are currently running beams in (nil = idle)
local forceCycleNow = false  -- set by the test trigger to fire a cycle immediately

-- clearAll(): retract/destroy every beam + reset debounce. Idempotent.
local function clearAll()
	BeamGeneration.cleanup()
	BeamKnockback.reset()
	activeBand = nil
end

--======================================================================
-- runCycle(band): plan + spawn this cycle's beams, then schedule their
-- retract after BEAM_DURATION. The collision loop (separate, faster) does
-- the hit detection independently so it stays responsive.
--======================================================================
local function runCycle(band)
	-- Ask the pattern brain which beams fire this cycle (guarantees a safe lane).
	local descriptors = BeamPattern.planCycle(band)
	for _, d in ipairs(descriptors) do
		local rec = BeamGeneration.spawnBeam(d)   -- nil if MAX_BEAMS reached (safely skipped)
		if rec then
			-- Schedule THIS beam's retract after it has held for BEAM_DURATION
			-- (the hold begins once it finishes extending).
			task.delay(CONFIG.BEAM_EXTEND_TIME + CONFIG.BEAM_DURATION, function()
				BeamGeneration.retractBeam(rec)
			end)
		end
	end
end

--======================================================================
-- COLLISION LOOP: a fast, independent loop that checks proximity every
-- COLLISION_TICK while a band is active and routes hits to BeamKnockback.
--======================================================================
task.spawn(function()
	while true do
		task.wait(CONFIG.COLLISION_TICK)
		if activeBand then
			local descriptors = BeamGeneration.getActiveDescriptors()
			if #descriptors > 0 then
				local hits = BeamCollision.getHitPlayers(descriptors, activeBand)
				if #hits > 0 then
					BeamKnockback.notifyHits(hits)   -- fires RainbowBeamSync "hit" (debounced)
				end
			end
		end
	end
end)

--======================================================================
-- MAIN LOOP: the steady BEAT. While a player occupies a beam band, run a
-- pattern cycle every BEAM_INTERVAL (+ a tiny per-cycle wobble). When no
-- player is in any band, clear everything and idle cheaply.
--======================================================================
task.spawn(function()
	while true do
		local band = anyPlayerInBand()

		if band then
			-- Entering / staying active in a band.
			activeBand = band
			runCycle(band)

			-- Wait the steady beat (+ small organic wobble) before the next
			-- cycle, but bail early if a forced test cycle is requested or the
			-- band empties (so cleanup is prompt).
			local waitFor = CONFIG.BEAM_INTERVAL + BeamPattern.timingOffset()
			local deadline = os.clock() + waitFor
			while os.clock() < deadline do
				task.wait(0.1)
				if forceCycleNow then forceCycleNow = false break end
				if not anyPlayerInBand() then break end
			end
		else
			-- No player in any band: ensure beams are cleared, then idle.
			if BeamGeneration.count() > 0 or activeBand then
				clearAll()
			end
			task.wait(0.3)
		end
	end
end)

-- Drop a leaving player's debounce entry (no leak).
Players.PlayerRemoving:Connect(function(player)
	BeamKnockback.clearPlayer(player)
end)

-- (Pre-launch cleanup: the "/beams" chat command + _G.startBeams manual test trigger were removed.
-- The beam hazard still runs on its own via the collision/cycle loop above — forceCycleNow simply stays
-- false now, so cycles fire on normal timing.)
