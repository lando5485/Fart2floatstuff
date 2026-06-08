--======================================================================
-- RainbowBeamManager.server.lua  (Script)
--======================================================================
-- Orchestrates the "RAINBOW BEAMS" aerial hazard.
--
-- Long, thin, glowing RAINBOW beams fill the vertical climb corridor between
-- certain islands as PERSISTENT SPINNING BLADES: each is a flat, horizontal
-- rainbow line that spins continuously about its own hub (like a helicopter
-- blade) at its own speed/direction -- they do NOT flicker on/off. A flying
-- player who drifts into a beam line gets their flight REWOUND -- but this
-- script does NOT implement the rewind. It only DETECTS the hit and tells the
-- client to run the pre-built `_G.applyBeamHit()`.
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
--     planes): the spinning blades spawn once a player is inside a beam band's
--     Y range and spin until they leave; everything is cleared the moment none are.
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
	-- ---------------- PERSISTENT SPINNING BLADES ----------------
	-- The beams are NOT flickering on/off. When a player enters the band we spawn a
	-- fixed set of beams spaced through the climb height, and they SPIN CONTINUOUSLY
	-- about their own hubs until the band empties. Each blade's own spin speed +
	-- direction (below) makes its line sweep past every spot periodically, so a
	-- timed gap to pass through always recurs -- safety is inherent to the spin.
	BEAM_COUNT       = 14,    -- how many persistent spinning blades fill the corridor (kept ~same density as before)
	SPIN_SPEED_MIN   = 0.25,  -- slowest blade spin (rad/s, ~14 deg/s) -- "some spin slow"
	SPIN_SPEED_MAX   = 1.5,   -- fastest blade spin (rad/s, ~86 deg/s) -- "some spin fast"; sign is randomised per beam (CW/CCW)
	HUB_OFFSET_MIN   = 25,    -- min horizontal nudge of a blade's hub OFF the central climb axis (studs)
	HUB_OFFSET_MAX   = 65,    -- max hub nudge. Off-centre hubs mean the central climb line gets periodic clear openings,
	                          -- not a permanently-blocked pivot -> a timed pass straight up the middle always recurs.

	-- ---------------- PERF CAPS ----------------
	MAX_BEAMS        = 36,    -- HARD cap on simultaneous beam parts (>= BEAM_COUNT). Clipping only ever REMOVES beams.
	MAX_PARTICLE_RATE = 26,   -- HARD cap on every ParticleEmitter Rate (BeamEffects honours this)

	-- ---------------- COLLISION ----------------
	BEAM_HIT_RADIUS  = 9,     -- studs from a beam LINE that counts as a hit (point-to-segment)
	HIT_DEBOUNCE     = 2.0,   -- seconds a player is immune to further hits after one (1 crossing = 1 rewind)
	COLLISION_TICK   = 0.10,  -- seconds between server proximity checks (faster, so quick flashes still register)

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
	-- band {150,790} for testing without climbing. Spinning blades fill either band.
	BEAM_TEST_ZONE = "real",  -- beams active in the islands 8-9 gap
}

--======================================================================
-- Services + module requires.
--======================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
local activeBand = nil       -- the band whose spinning blades are currently live (nil = idle)

-- clearAll(): destroy every beam + reset debounce. Idempotent.
local function clearAll()
	BeamGeneration.cleanup()
	BeamKnockback.reset()
	activeBand = nil
end

--======================================================================
-- spawnLayout(band): lay out the PERSISTENT spinning blades for this band ONCE
-- (called when a player first enters the band). The pattern brain decides each
-- blade's height, hub, spin speed/direction and colour; we just spawn them.
-- After this they spin forever (driven by the SPIN LOOP) until the band empties.
--======================================================================
local function spawnLayout(band)
	local descriptors = BeamPattern.planLayout(band)
	for _, d in ipairs(descriptors) do
		BeamGeneration.spawnBeam(d)   -- persistent; nil (skipped) only if MAX_BEAMS reached
	end
end

--======================================================================
-- SPIN LOOP: every frame, while a band is active, advance every blade's
-- rotation by its own speed/direction (BeamGeneration.update recomputes each
-- beam's CFrame + collision endpoints). This is what makes the blades spin
-- continuously instead of flickering on/off.
--======================================================================
RunService.Heartbeat:Connect(function(dt)
	if activeBand then
		BeamGeneration.update(dt)
	end
end)

--======================================================================
-- COLLISION LOOP: a fast, independent loop that checks proximity every
-- COLLISION_TICK while a band is active and routes hits to BeamKnockback.
-- (Reads the live, just-rotated endpoints, so hits match what the player sees.)
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
-- MAIN LOOP: while a player occupies the beam band, the spinning blades are
-- spawned ONCE (on entry) and left to spin. When the band empties, everything
-- is cleared and we idle cheaply. No on/off cycle -- the blades are persistent.
--======================================================================
task.spawn(function()
	while true do
		local band = anyPlayerInBand()

		if band then
			if activeBand ~= band then
				-- First entry into this band: build the persistent spinning layout once.
				clearAll()             -- fresh start (also resets the hit debounce)
				activeBand = band
				spawnLayout(band)
			end
			task.wait(0.2)
		else
			-- No player in the band: clear the blades, then idle.
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

-- (The beam hazard runs on its own: the main loop spawns the persistent spinning
-- blades while a player is in the 8-9 band, the Heartbeat spin loop rotates them,
-- and the collision loop routes touches to the launch-snapshot rewind.)
