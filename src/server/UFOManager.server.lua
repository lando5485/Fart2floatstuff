--======================================================================
-- UFOManager.server.lua  (Script)
--======================================================================
-- Orchestrates the global "UFO" spectacle event.
--
-- A gigantic alien mothership descends from the clouds, hovers + slowly
-- rotates over the islands, casts massive downward tractor beams that
-- abduct NPCs/props/items, (optionally) lifts GROUNDED players for a short
-- ride, occasionally pulls a rider into an enclosed inside-UFO scene, then
-- charges up and rockets away into space. Rare variants (golden / broken /
-- swarm / hostile) add flavour.
--
-- DESIGN / SAFETY (mirrors the Rocket + Meteor events' contract):
--   * This is a SPECTACLE + a pure-physics player RIDE. It NEVER reads or
--     modifies the fart meter, flight code, food prices, gut stats, island
--     heights, the normal coin earn rate, the falling junk, or the planes.
--     The ONLY _G access anywhere in this event is READING `_G.isFlying`
--     on the client to gate the ride. The ONLY leaderstat touch is an
--     OPTIONAL, modest, zeroable golden-UFO coin reward (see UFOAbduction).
--   * All sequencing/timing runs on the SERVER. Server-created UFO/beam/
--     abductee parts replicate to every client automatically, so the whole
--     server sees the same UFO. The UFOSync RemoteEvent carries client-side
--     presentation (sky, banners, camera, ambient sound) AND the per-client
--     ride messages ("you are in a beam", "go inside", "return").
--   * ★ POSITION SAFETY ★ The event moves players vertically, so it is
--     built to NEVER let a player skip islands or bypass unlock-gating:
--       - The beam may ONLY engage a player who is GROUNDED on/near an
--         island and NOT flying. The grounded/flying check + the actual
--         ride physics happen on the AFFECTED CLIENT (clients own their
--         character physics); the server only decides which islands are
--         targeted + proximity and messages those clients.
--       - The client CAPTURES the player's exact HRP CFrame the instant it
--         engages and ALWAYS sets them back to that captured spot after the
--         ride AND after any inside-UFO scene. Nobody is ever deposited on a
--         higher/locked island.
--       - If the player starts flying / jumps / boosts mid-ride, the client
--         releases them immediately with NO teleport.
--   * Everything is capped (MAX_BEAMS, MAX_ABDUCTEES, particle rates) and
--     fully cleaned up on reset (no leaks).
--======================================================================

--======================================================================
-- CONFIG  -- EDIT ANYTHING HERE. Every value is tunable; gameplay-adjacent
-- values are deliberately MODEST and can be zeroed to disable a feature.
--======================================================================
local CONFIG = {
	-- ---------------- TIMINGS (seconds) ----------------
	EVENT_INTERVAL   = 1500,  -- seconds between auto-runs of the UFO event (25 min)
	WARNING_DURATION = 20,    -- WARNING phase: flickering lights, buzzing, scout ships
	DESCENT_DURATION = 8,     -- how long the mothership takes to descend from the clouds
	MAIN_DURATION    = 18,    -- MAIN phase: UFO hovers + rotates before abducting
	ABDUCTION_DURATION = 30,  -- ABDUCTION phase: tractor beams target islands
	ENDING_DURATION  = 9,     -- ENDING phase: energy charge + flash + rapid ascent

	-- ---------------- ALIEN AMBIENT SOUND (server-wide, repeating) ----------------
	-- Plays SERVER-WIDE once at event start, then again every ALIEN_SOUND_INTERVAL
	-- seconds for the whole event; stops when the ENDING phase begins.
	ALIEN_SOUND_ID = "rbxassetid://82428123919520",
	ALIEN_SOUND_INTERVAL = 10,  -- seconds between repeats (easy to change)
	ALIEN_SOUND_VOLUME = 1,     -- unified volume: matches the meteor intro sound

	-- ---------------- UFO SIZE / POSITION ----------------
	UFO_DIAMETER     = 420,   -- mothership saucer diameter (studs) -- ENORMOUS, seen from all islands
	UFO_HOVER_HEIGHT = 900,   -- studs the UFO hovers ABOVE the targeted islands' band
	UFO_CLOUD_HEIGHT = 4000,  -- studs above the band the UFO starts at (descends from clouds)
	UFO_BOB_AMPLITUDE = 14,   -- vertical hover-bob amplitude (studs)
	UFO_BOB_SPEED    = 0.5,   -- hover-bob cycles per second
	UFO_SPIN_SPEED   = 8,     -- saucer rotation (degrees / second)
	UFO_ASCENT_SPEED = 1400,  -- studs/sec the UFO accelerates upward on ENDING

	-- ---------------- BEAM / RIDE ----------------
	MAX_BEAMS        = 4,     -- HARD cap on simultaneous tractor beams (perf)
	BEAM_RADIUS      = 38,    -- studs: horizontal radius a player/object must be within to be caught
	BEAM_PULL_STRENGTH = 22,  -- studs/sec the ride floats a caught player up the beam
	BEAM_SPIN_RATE   = 45,    -- degrees/sec a ridden player gently spins
	ABDUCT_LIFT_HEIGHT = 220, -- studs above their START a rider/object is lifted (then held)
	BEAM_RETARGET_INTERVAL = 4.5, -- how often beams pick new island targets during ABDUCTION
	ESCAPE_SENSITIVITY = 1.0, -- multiplier on how easily flying/jumping/boosting breaks the ride

	-- ---------------- INSIDE-UFO SCENE ----------------
	INSIDE_UFO_CHANCE = 0.18, -- per ridden PLAYER: chance they're pulled into the enclosed scene
	INSIDE_UFO_DURATION = 8,  -- seconds a player spends in the enclosed inside-UFO chamber

	-- ---------------- ABDUCTEES (NPCs / props / items) ----------------
	MAX_ABDUCTEES    = 10,    -- HARD cap on simultaneous server-moved abducted objects
	ABDUCTEE_SPIN_RATE = 60,  -- degrees/sec abducted props spin as they rise
	ABDUCTEE_LIFT_TIME = 3.5, -- seconds an object takes to rise to the hold point

	-- ---------------- VARIANT CHANCES (rolled once at event start) ----------------
	GOLDEN_UFO_CHANCE  = 0.05, -- golden UFO: bigger spectacle + (optional) modest coin reward
	BROKEN_UFO_CHANCE  = 0.08, -- broken UFO: sparking / malfunctioning visuals
	SWARM_CHANCE       = 0.07, -- swarm: a flock of tiny fast UFOs instead of one mothership feel
	HOSTILE_UFO_CHANCE = 0.06, -- hostile (red) UFO: stronger pull (still a ride, still returns)
	HOSTILE_PULL_MULT  = 1.8,  -- multiplier applied to BEAM_PULL_STRENGTH when HOSTILE

	-- ---------------- GOLDEN-UFO REWARD (optional / modest / ZEROABLE) ----------------
	-- The ONLY leaderstat touch in this whole event. A flat coin bundle added
	-- to the Coins leaderstat for each player who is RIDDEN during a GOLDEN
	-- event. Kept small so it can't dwarf normal earning or skip the grind.
	-- SET TO 0 TO DISABLE ENTIRELY.
	GOLDEN_COIN_REWARD = 250,

	-- ---------------- PARTICLE / EMITTER CAPS (perf) ----------------
	MAX_PARTICLE_RATE = 28,   -- HARD cap on every ParticleEmitter Rate
	MAX_DEBRIS_ORBIT  = 10,   -- max chunks of debris orbiting the UFO
	MAX_SCOUTS        = 4,    -- max scout ships during WARNING / swarm minis

	-- ---------------- TARGETING ----------------
	-- Fallback island top-surface positions (X,Y,Z) if a model can't be found
	-- or a raycast fails. Sourced from the game's ISLAND_POSITIONS (top
	-- surfaces are found by raycast at runtime; these are safe defaults).
	FALLBACK_TARGETS = {
		Vector3.new(0, 50, 0), Vector3.new(120, 600, 60), Vector3.new(-160, 1400, 100),
		Vector3.new(180, 2500, -120), Vector3.new(-200, 4000, 160), Vector3.new(220, 6000, -180),
		Vector3.new(-240, 8500, 200), Vector3.new(260, 11500, -220), Vector3.new(-280, 15000, 240),
		Vector3.new(300, 19000, -260), Vector3.new(-320, 24000, 280), Vector3.new(340, 30000, -300),
		Vector3.new(-360, 37000, 320), Vector3.new(380, 45000, -340),
	},
}

--======================================================================
-- Services + module requires.
--======================================================================
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Sibling ModuleScripts created by this event (synced via default.project.json).
local UFOEffects   = require(ServerScriptService:WaitForChild("UFOEffects"))
local UFOBeam      = require(ServerScriptService:WaitForChild("UFOBeam"))
local UFOAbduction = require(ServerScriptService:WaitForChild("UFOAbduction"))

-- The sync RemoteEvent (added to ReplicatedStorage via default.project.json).
local UFOSync = ReplicatedStorage:WaitForChild("UFOSync")
-- [LATE-JOIN] Record the last LIFECYCLE phase + payload into _G.BigEvents.ufo so LateJoinEventSync can
-- replay the EXACT current visuals (sky variant, etc.) to a late-joiner. The FireAllClients inside is
-- IDENTICAL to the direct call -- this ONLY also stashes phase/payload (purely additive). Transient
-- effects (islandFlash/gibberish/engage/flash) keep calling UFOSync:FireAllClients directly.
local function ufoPhase(phase, payload)
	UFOSync:FireAllClients(phase, payload)
	local e = _G.BigEvents and _G.BigEvents.ufo
	if e then
		e.currentPhase, e.currentPayload = phase, payload
		if phase == "start" then e.startPayload = payload end
	end
end

-- Wire the modules together (CONFIG is owned here; pass it down).
UFOEffects.init(CONFIG, UFOSync)
UFOAbduction.init(CONFIG, UFOSync)
UFOBeam.init(CONFIG, UFOSync, UFOAbduction)

--======================================================================
-- State.
--======================================================================
local eventRunning = false   -- guard so we never run two UFO events at once

--======================================================================
-- ALIEN AMBIENT SOUND (server-wide, repeating every ALIEN_SOUND_INTERVAL).
-- The Sound is parented to a Folder in Workspace (a non-BasePart), so it plays
-- globally / 2D for EVERY client regardless of position -- server-wide. Created
-- on the server => replicates to all. A generation token lets stop... cancel
-- the running loop cleanly (and survive overlapping events).
--======================================================================
local alienSoundGen = 0          -- bumped to invalidate the running loop
local alienSoundHolder = nil     -- Folder hosting the global sound
local alienSound = nil           -- the reused Sound instance

-- startAlienSoundLoop(): play once now, then every ALIEN_SOUND_INTERVAL until stopped.
local function startAlienSoundLoop()
	alienSoundGen = alienSoundGen + 1
	local myGen = alienSoundGen

	local holder = Instance.new("Folder")
	holder.Name = "UFOEventAlienSound"
	holder.Parent = workspace      -- Folder (non-BasePart) => global / server-wide
	alienSoundHolder = holder

	local snd = Instance.new("Sound")
	snd.Name = "AlienSound"
	snd.SoundId = CONFIG.ALIEN_SOUND_ID
	snd.Volume = CONFIG.ALIEN_SOUND_VOLUME
	snd.Looped = false
	snd.Parent = holder
	alienSound = snd

	task.spawn(function()
		-- Trigger once at event start, then again every interval while active.
		while alienSoundGen == myGen and holder.Parent do
			if snd and snd.Parent then
				snd.TimePosition = 0
				snd:Play()
			end
			task.wait(CONFIG.ALIEN_SOUND_INTERVAL)
		end
	end)
end

-- stopAlienSoundLoop(): cancel the loop + stop/destroy the sound. Idempotent,
-- so it's safe to call at ENDING and again in the reset/error path.
local function stopAlienSoundLoop()
	alienSoundGen = alienSoundGen + 1   -- the running loop's next check fails -> it exits
	if alienSound and alienSound.Parent then alienSound:Stop() end
	if alienSoundHolder and alienSoundHolder.Parent then alienSoundHolder:Destroy() end
	alienSound = nil
	alienSoundHolder = nil
end

--======================================================================
-- TARGETING: resolve island top-surface positions.
-- Scan Workspace for the island models (named "Island_<n>_..."), take a
-- model's horizontal center, and RAYCAST DOWN to its top surface so beams
-- and the UFO band line up with island GROUND. Fall back to FALLBACK_TARGETS.
--======================================================================

-- snapToGround: raycast straight down at (x,z) to find the top surface Y.
-- Excludes players + the Farmer + our own event folders so we never raycast
-- onto a beam, a rider, or a prior abductee.
local function snapToGround(x, z, fromY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(exclude, plr.Character) end
	end
	local tut = workspace:FindFirstChild("TutorialNPCs")
	if tut then table.insert(exclude, tut) end
	for _, name in ipairs({ "UFOEvent", "UFOEventBeams", "UFOEventAbductees", "UFOEventInside" }) do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(exclude, f) end
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	local hit = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -8000, 0), params)
	return hit and hit.Position.Y or nil
end

-- getIslandTargets: gather one top-surface point per island present in the
-- Workspace. Returns a list of { index = n, position = Vector3 }.
local function getIslandTargets()
	local targets = {}
	for i = 1, 14 do
		local found = false
		for _, child in ipairs(workspace:GetChildren()) do
			if child:IsA("Model") then
				local prefix = "Island_" .. i .. "_"
				if child.Name:sub(1, #prefix) == prefix then
					local ok, cf, size = pcall(function() return child:GetBoundingBox() end)
					if ok and cf and size then
						local cx, cz = cf.Position.X, cf.Position.Z
						local gy = snapToGround(cx, cz, cf.Position.Y + size.Y / 2 + 50)
						table.insert(targets, {
							index = i,
							position = Vector3.new(cx, gy or cf.Position.Y, cz),
						})
						found = true
					end
					break
				end
			end
		end
		-- If the model was missing, use the configured fallback for this island.
		if not found and CONFIG.FALLBACK_TARGETS[i] then
			local fb = CONFIG.FALLBACK_TARGETS[i]
			local gy = snapToGround(fb.X, fb.Z, fb.Y + 200)
			table.insert(targets, { index = i, position = Vector3.new(fb.X, gy or fb.Y, fb.Z) })
		end
	end
	-- Absolute fallback so the event always has somewhere to be.
	if #targets == 0 then
		for i, fb in ipairs(CONFIG.FALLBACK_TARGETS) do
			table.insert(targets, { index = i, position = fb })
		end
	end
	return targets
end

-- pickVariant: roll exactly one rare variant (or "normal") at event start.
-- Order matters so chances don't stack; returns a variant string.
local function pickVariant()
	local r = math.random()
	if r < CONFIG.GOLDEN_UFO_CHANCE then return "golden" end
	r = r - CONFIG.GOLDEN_UFO_CHANCE
	if r < CONFIG.BROKEN_UFO_CHANCE then return "broken" end
	r = r - CONFIG.BROKEN_UFO_CHANCE
	if r < CONFIG.SWARM_CHANCE then return "swarm" end
	r = r - CONFIG.SWARM_CHANCE
	if r < CONFIG.HOSTILE_UFO_CHANCE then return "hostile" end
	return "normal"
end

--======================================================================
-- Full event sequence. Returns when the whole thing is done + cleaned.
--======================================================================
local function runEvent()
	if eventRunning then return end
	eventRunning = true

	-- Roll the variant once for the whole event.
	local variant = pickVariant()

	-- Wrap in pcall so a failure still cleans up + clears the guard.
	local ok, err = pcall(function()
		local targets = getIslandTargets()

		-- The UFO hovers over the vertical MIDDLE of the island band so it is
		-- visible from islands both above and below it.
		local minY, maxY = math.huge, -math.huge
		for _, t in ipairs(targets) do
			minY = math.min(minY, t.position.Y)
			maxY = math.max(maxY, t.position.Y)
		end
		local bandMidY = (minY + maxY) / 2
		local hoverPos = Vector3.new(0, bandMidY + CONFIG.UFO_HOVER_HEIGHT, 0)

		-- ---- 1) START ----
		-- Sky darkens green/purple, clouds speed up, eerie ambient.
		ufoPhase("start", { text = "\u{1F6F8} UFO DETECTED ABOVE THE ISLANDS!", variant = variant })
		startAlienSoundLoop()  -- server-wide alien sound: now + every ALIEN_SOUND_INTERVAL until ENDING

		-- ---- 2) WARNING (~WARNING_DURATION) ----
		-- Flickering strange lights, electrical buzzing, random islands flash
		-- green, distant alien noises, occasional small scout ships zoom past.
		ufoPhase("warning", { variant = variant })
		UFOEffects.startWarning(hoverPos, targets, variant)
		local warnDeadline = os.clock() + CONFIG.WARNING_DURATION
		while os.clock() < warnDeadline do
			-- Flash a random island green for the clients.
			local t = targets[math.random(1, #targets)]
			UFOSync:FireAllClients("islandFlash", { position = t.position })
			-- Occasional alien gibberish over the sky.
			if math.random() < 0.5 then
				UFOSync:FireAllClients("gibberish")
			end
			task.wait(2)
		end
		UFOEffects.stopWarning()

		-- ---- 3) MAIN: the mothership descends + hovers ----
		ufoPhase("main", { variant = variant })
		UFOEffects.spawnUFO(hoverPos, variant)        -- build the giant saucer in the clouds
		UFOEffects.descend(CONFIG.DESCENT_DURATION)   -- glide down from UFO_CLOUD_HEIGHT
		task.wait(CONFIG.DESCENT_DURATION)
		UFOEffects.startHover()                        -- bob + spin + hum + orbiting debris
		task.wait(CONFIG.MAIN_DURATION)

		-- ---- 4) ABDUCTION: tractor beams target islands ----
		ufoPhase("abduction", { variant = variant })
		local abductDeadline = os.clock() + CONFIG.ABDUCTION_DURATION
		local retargetAt = 0
		while os.clock() < abductDeadline do
			if os.clock() >= retargetAt then
				-- Pick up to MAX_BEAMS random island targets and aim beams there.
				local chosen = {}
				local pool = {}
				for _, t in ipairs(targets) do table.insert(pool, t) end
				for _ = 1, math.min(CONFIG.MAX_BEAMS, #pool) do
					local idx = math.random(1, #pool)
					table.insert(chosen, pool[idx])
					table.remove(pool, idx)
				end
				-- Beam module spawns/repoints the beams + handles object pickup +
				-- per-client player engage messages (server-authoritative).
				UFOBeam.setTargets(chosen, UFOEffects.getUFOPosition(), variant)
				retargetAt = os.clock() + CONFIG.BEAM_RETARGET_INTERVAL
			end
			-- Beam module runs proximity detection every tick.
			UFOBeam.update()
			task.wait(0.2)
		end
		UFOBeam.stopAll()       -- release beams + return any object still rising

		-- ---- 6) ENDING: energy charge + flash + rapid ascent + vanish ----
		stopAlienSoundLoop()  -- event is ending -> no more alien sound plays
		ufoPhase("ending", { text = "\u{1F6F8} UFO EVENT ENDING\u{2026}", variant = variant })
		UFOEffects.chargeAndDepart(CONFIG.ENDING_DURATION)  -- glow builds -> flash -> rocket up
		task.wait(CONFIG.ENDING_DURATION)
	end)

	if not ok then
		warn("[UFOEvent] event errored: " .. tostring(err))
	end

	-- ---- 7) RESET: restore everyone + destroy everything, no leftovers ----
	stopAlienSoundLoop()               -- safety: also stop the sound if the event errored early
	UFOSync:FireAllClients("reset")    -- clients restore Lighting + force-return any rider
	UFOBeam.cleanup()                  -- release beams + return all abducted players
	UFOAbduction.cleanup()             -- return all abducted objects + destroy inside scene
	UFOEffects.cleanup()               -- destroy the saucer + all VFX
	eventRunning = false
end

--------------------------------------------------------------------
-- Public starter (used by the interval timer + test triggers).
--------------------------------------------------------------------
local function startEvent()
	if eventRunning then
		warn("[UFOEvent] start ignored: an event is already running.")
		return
	end
	task.spawn(runEvent)
end

--======================================================================
-- Main interval timer loop.
--======================================================================
-- BIG-EVENT SCHEDULER: this event's own interval timer is DISABLED. The single
-- BigEventScheduler now drives all five big events (one at a time, every 7 min,
-- never the same twice in a row). We just register start + running-state.
_G.BigEvents = _G.BigEvents or {}
_G.BigEvents.ufo = { start = startEvent, isRunning = function() return eventRunning end }

-- (Pre-launch cleanup: the "/ufo" chat command + _G.startUFOEvent manual test trigger were removed.
-- The event still fires on its own via the BigEventScheduler using the registration above.)
