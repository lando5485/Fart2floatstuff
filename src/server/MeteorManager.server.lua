--======================================================================
-- MeteorManager.server.lua  (Script)
--======================================================================
-- Orchestrates the global "MeteorStorm" spectacle event.
--
-- A meteor shower sweeps the sky: warning streaks, then large meteors
-- rain down onto RANDOM islands with long cinematic trails, exploding +
-- leaving fading scorch zones. Rare variants (toxic / ice / rainbow /
-- alien) and a very-rare LEGENDARY golden meteor add flavour.
--
-- DESIGN / SAFETY (mirrors the Rocket event's contract):
--   * This event is a SPECTACLE + two small, CONFIG-gated gameplay touch-
--     points ONLY: (a) meteor KNOCKBACK (a pure physics nudge to a nearby
--     player's HumanoidRootPart) and (b) coin/loot REWARDS (added to the
--     Coins leaderstat). It NEVER reads or modifies the fart meter, flight,
--     food prices, gut stats, island heights, the normal coin earn rate,
--     the falling-junk hazard, or the plane hazard.
--   * All timing runs on the SERVER. Server-created meteor/explosion/scorch
--     parts replicate to all clients automatically, so everyone sees the
--     same storm. The MeteorSync RemoteEvent is used for client-side
--     presentation (banners, sky changes, camera shake) and to deliver the
--     server-decided knockback vector to the specific hit clients.
--   * Everything is capped (MAX_METEORS, particle rates) and fully cleaned
--     up on reset (no leaks).
--======================================================================

--======================================================================
-- CONFIG  -- EDIT ANYTHING HERE. Every value is tunable; the gameplay
-- values are deliberately MODEST and can be zeroed to disable a feature.
--======================================================================
local CONFIG = {
	-- ---------------- TIMINGS ----------------
	EVENT_INTERVAL = 1200,        -- seconds between auto-runs of the storm (20 min)
	WARNING_DURATION = 15,        -- WARNING phase length (sirens + harmless streaks)
	MAIN_DURATION = 45,           -- MAIN phase length (the real meteor barrage)
	ENDING_DURATION = 8,          -- ENDING phase length (frequency tapers, sky restores)

	-- ---------------- INTRO SOUND (server-wide, looped, first 10s only) ----------------
	-- Plays SERVER-WIDE the moment the storm begins, LOOPED, then stops after
	-- INTRO_DURATION. Separate from the impact + storm sounds. The clip is ~6s,
	-- so looping covers the full window (plays through ~twice in 10s).
	INTRO_SOUND_ID = "rbxassetid://109362273688140",
	INTRO_DURATION = 20,          -- seconds to play the looped intro before stopping (~6s clip loops a few times)
	INTRO_VOLUME = 1,             -- reasonable volume
	METEOR_INTERVAL_MIN = 1.2,    -- min seconds between meteor spawns in MAIN
	METEOR_INTERVAL_MAX = 3.0,    -- max seconds between meteor spawns in MAIN
	METEOR_FALL_TIME_MIN = 2.2,   -- min seconds a meteor takes to fall to impact
	METEOR_FALL_TIME_MAX = 3.6,   -- max seconds a meteor takes to fall to impact
	WARNING_STREAK_FALL = 1.6,    -- fall time for harmless warning-phase streaks
	WARNING_STREAK_INTERVAL = 2.0,-- seconds between harmless warning streaks

	-- ---------------- SPAWN / SIZE ----------------
	MAX_METEORS = 6,              -- HARD cap on simultaneous falling meteors (perf)
	METEOR_SPAWN_HEIGHT = 900,    -- base studs above the target the meteor starts at
	SMALL_SIZE_MIN = 2, SMALL_SIZE_MAX = 4,    -- small meteor radius range (studs)
	MEDIUM_SIZE_MIN = 4, MEDIUM_SIZE_MAX = 7,  -- medium meteor radius range
	LARGE_SIZE_MIN = 7, LARGE_SIZE_MAX = 11,   -- large meteor radius range
	LEGENDARY_SIZE = 16,          -- legendary meteor radius (huge + golden)
	GLOW_THRESHOLD = 0.55,        -- bigness >= this adds a glowing PointLight to the meteor

	-- ---------------- VARIANT CHANCES (per non-legendary meteor) ----------------
	TOXIC_CHANCE = 0.10,          -- green toxic
	ICE_CHANCE = 0.10,            -- blue/white ice
	RAINBOW_CHANCE = 0.06,        -- rainbow / confetti
	ALIEN_CHANCE = 0.04,          -- purple alien
	LEGENDARY_CHANCE = 0.01,      -- VERY small: huge golden legendary meteor (per spawn)

	-- ---------------- GAMEPLAY (gentle defaults, all tunable/zeroable) ----------------
	-- KNOCKBACK: a pure physics nudge to a nearby player's HRP. MODEST -- a
	-- noticeable push, NOT a launch. Applied client-side to the player's own
	-- HumanoidRootPart; never touches gas/fart-power/flight/coins. Set to 0
	-- to disable knockback entirely.
	METEOR_KNOCKBACK_FORCE = 45,  -- studs/sec impulse at point-blank (scales down with distance)
	-- HIT RADIUS: only players genuinely CLOSE to an impact get nudged (not
	-- the whole island). Set to 0 to disable.
	METEOR_HIT_RADIUS = 18,       -- studs from impact center (+ the meteor's radius)

	-- REWARDS: added to the Coins leaderstat. Kept small so meteor coins do
	-- NOT dwarf normal earning or skip the food/gut grind.
	METEOR_REWARD_CHANCE = 0.35,  -- only SOME meteors drop a collectible coin
	METEOR_COIN_REWARD = 25,      -- normal drop amount (modest!)
	REWARD_LIFETIME = 20,         -- seconds an uncollected coin drop lingers

	-- Rare bonus rolls inside a drop (chances are out of 1.0 of a drop):
	BOOST_DROP_CHANCE = 0.08,     -- "boost" style bigger bundle
	BOOST_REWARD = 150,           -- boost bundle coins
	RARE_BEAN_CHANCE = 0.04,      -- "rare bean" style bundle
	RARE_BEAN_REWARD = 300,       -- rare-bean bundle coins
	-- LEGENDARY: a bigger coin reward + a brief, purely-cosmetic server-wide
	-- notification (NO permanent flight/earn balance change).
	LEGENDARY_REWARD = 1000,      -- legendary coin bundle (still well below a single gut/food tier)

	-- ---------------- IMPACT PRESENTATION ----------------
	IMPACT_SHAKE = 0.7,           -- base camera-shake intensity on a normal impact
	LEGENDARY_SHAKE = 1.4,        -- camera-shake intensity for a legendary impact
	LEGENDARY_EXPLOSION_SCALE = 2.5, -- legendary explosion multiplier (visible from all islands)
	SCORCH_LIFETIME = 14,         -- seconds a scorch zone lingers before fading away

	-- ---------------- PARTICLE / DEBRIS CAPS (perf) ----------------
	MAX_PARTICLE_RATE = 30,       -- HARD cap on every ParticleEmitter Rate
	MAX_CRACKS = 12,              -- max glowing lava cracks per scorch zone
	MAX_DEBRIS_ROCKS = 14,        -- max scattered debris rocks per scorch zone

	-- ---------------- TARGETING ----------------
	-- Fallback island center positions (X,Y,Z) if a model can't be found /
	-- raycast fails. Sourced from the game's ISLAND_POSITIONS (top surfaces
	-- are found by raycast at runtime; these are safe defaults).
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
local MeteorSpawn = require(ServerScriptService:WaitForChild("MeteorSpawn"))
local MeteorImpact = require(ServerScriptService:WaitForChild("MeteorImpact"))
local MeteorReward = require(ServerScriptService:WaitForChild("MeteorReward"))

-- The sync RemoteEvent (added to ReplicatedStorage via default.project.json).
local MeteorSync = ReplicatedStorage:WaitForChild("MeteorSync")
-- [LATE-JOIN] Record the last LIFECYCLE phase + payload into _G.BigEvents.meteor so LateJoinEventSync
-- can replay the EXACT current visuals to a late-joiner. The FireAllClients inside is IDENTICAL to the
-- direct call -- this ONLY also stashes phase/payload (purely additive). Transient effects
-- (distant/impact/legendary) keep calling MeteorSync:FireAllClients directly (they aren't "the phase").
local function meteorPhase(phase, payload)
	MeteorSync:FireAllClients(phase, payload)
	local e = _G.BigEvents and _G.BigEvents.meteor
	if e then
		e.currentPhase, e.currentPayload = phase, payload
		if phase == "start" then e.startPayload = payload end
	end
end

-- Wire the modules together (CONFIG is owned here; pass it down).
MeteorReward.init(CONFIG, MeteorSync)
MeteorImpact.init(CONFIG, MeteorSync, MeteorReward)
MeteorSpawn.init(CONFIG, MeteorImpact)

--======================================================================
-- State.
--======================================================================
local eventRunning = false   -- guard so we never run two storms at once

--======================================================================
-- INTRO SOUND (server-wide, looped, first INTRO_DURATION seconds only).
-- The Sound is parented to a Folder in Workspace (a non-BasePart), so it plays
-- globally / 2D for EVERY client regardless of position -- server-wide. Created
-- on the server => replicates to all. A generation token lets the auto-stop /
-- reset cancel cleanly without affecting a later run.
--======================================================================
local introSoundGen = 0      -- bumped to invalidate a pending auto-stop
local introHolder = nil      -- Folder hosting the global intro sound

-- stopIntroSound(): stop + remove the intro sound. Idempotent (safe to call at
-- the auto-stop AND again in the reset/error path).
local function stopIntroSound()
	introSoundGen = introSoundGen + 1   -- invalidate any pending auto-stop
	if introHolder and introHolder.Parent then introHolder:Destroy() end
	introHolder = nil
end

-- startIntroSound(): play the looped intro now; auto-stop after INTRO_DURATION
-- so it never keeps looping past the opening window.
local function startIntroSound()
	introSoundGen = introSoundGen + 1
	local myGen = introSoundGen

	local holder = Instance.new("Folder")
	holder.Name = "MeteorStormIntroSound"
	holder.Parent = workspace      -- Folder (non-BasePart) => global / server-wide
	introHolder = holder

	local snd = Instance.new("Sound")
	snd.Name = "IntroSound"
	snd.SoundId = CONFIG.INTRO_SOUND_ID
	snd.Volume = CONFIG.INTRO_VOLUME
	snd.Looped = true              -- loop the ~6s clip through the intro window
	snd.Parent = holder
	snd:Play()

	-- Hard-stop after INTRO_DURATION (no looping past the intro window).
	task.delay(CONFIG.INTRO_DURATION, function()
		if myGen == introSoundGen then
			stopIntroSound()
		end
	end)
end

--======================================================================
-- TARGETING: find a random island impact point.
-- Scan Workspace for the island models (named "Island_<n>_..."), take a
-- model's horizontal center, and RAYCAST DOWN to its top surface so the
-- impact lands on island GROUND. Fall back to CONFIG.FALLBACK_TARGETS.
--======================================================================

-- snapToGround: raycast straight down at (x,z) to find the top surface Y.
-- Excludes players + the Farmer so meteors land on the real ground.
local function snapToGround(x, z, fromY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(exclude, plr.Character) end
	end
	local tut = workspace:FindFirstChild("TutorialNPCs")
	if tut then table.insert(exclude, tut) end
	-- Exclude our own event folders so we never raycast onto a prior scorch.
	for _, name in ipairs({ "MeteorStormMeteors", "MeteorStormImpacts", "MeteorStormRewards" }) do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(exclude, f) end
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	local hit = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -8000, 0), params)
	return hit and hit.Position.Y or nil
end

-- Gather all island models present in the Workspace.
local function getIslandModels()
	local islands = {}
	for i = 1, 14 do
		-- Match "Island_<i>_..." by prefix; names are e.g. Island_1_BeanFarm.
		for _, child in ipairs(workspace:GetChildren()) do
			if child:IsA("Model") then
				local prefix = "Island_" .. i .. "_"
				if child.Name:sub(1, #prefix) == prefix then
					table.insert(islands, { index = i, model = child })
					break
				end
			end
		end
	end
	return islands
end

-- Pick a random island impact point (top surface) or a safe fallback.
local function pickTarget()
	local islands = getIslandModels()
	if #islands > 0 then
		local pick = islands[math.random(1, #islands)]
		local ok, cf, size = pcall(function() return pick.model:GetBoundingBox() end)
		if ok and cf and size then
			-- Random point within the central area of the island (not just dead
			-- center) so impacts vary across the island surface.
			local jitterX = (math.random() - 0.5) * size.X * 0.5
			local jitterZ = (math.random() - 0.5) * size.Z * 0.5
			local cx = cf.Position.X + jitterX
			local cz = cf.Position.Z + jitterZ
			local gy = snapToGround(cx, cz, cf.Position.Y + size.Y / 2 + 50)
			if gy then
				return Vector3.new(cx, gy, cz)
			end
			-- Raycast missed: use the model center Y as a fallback.
			return Vector3.new(cx, cf.Position.Y, cz)
		end
	end
	-- Full fallback: a configured island center, snapped to ground if possible.
	local fb = CONFIG.FALLBACK_TARGETS[math.random(1, #CONFIG.FALLBACK_TARGETS)]
	local gy = snapToGround(fb.X, fb.Z, fb.Y + 200)
	return Vector3.new(fb.X, gy or fb.Y, fb.Z)
end

--======================================================================
-- Full event sequence. Returns when the whole thing is done + cleaned.
--======================================================================
local function runEvent()
	if eventRunning then return end
	eventRunning = true

	-- Wrap in pcall so a failure still cleans up + clears the guard.
	local ok, err = pcall(function()
		-- ---- 1) START ----
		-- Sky to dark red/orange, embers, distant streaks, rumble + banner.
		meteorPhase("start", "\u{2604} METEOR SHOWER INCOMING!")
		startIntroSound()  -- server-wide looped intro for the first INTRO_DURATION seconds

		-- ---- 2) WARNING (~WARNING_DURATION) ----
		-- Sirens, harmless small streaks, occasional slight shake / distant booms.
		meteorPhase("warning", "Take cover! Meteors approaching...")
		local warnDeadline = os.clock() + CONFIG.WARNING_DURATION
		while os.clock() < warnDeadline do
			-- Harmless streak that fades in the sky (no impact).
			MeteorSpawn.spawnMeteor(pickTarget(), { harmless = true })
			-- Occasional slight island shake + a distant boom cue for the clients.
			if math.random() < 0.4 then
				MeteorSync:FireAllClients("distant", { intensity = 0.25 })
			end
			task.wait(CONFIG.WARNING_STREAK_INTERVAL)
		end

		-- ---- 3) MAIN (MAIN_DURATION): the real barrage ----
		meteorPhase("main", "\u{2604} METEOR SHOWER!")
		local mainDeadline = os.clock() + CONFIG.MAIN_DURATION
		while os.clock() < mainDeadline do
			-- Decide if THIS meteor is legendary (very small chance).
			local legendary = math.random() < CONFIG.LEGENDARY_CHANCE
			if legendary then
				-- Announce the legendary loudly before it lands.
				MeteorSync:FireAllClients("legendaryIncoming", "\u{1F31F} LEGENDARY METEOR DETECTED!")
			end
			-- Respect the simultaneous cap (spawnMeteor returns false if full).
			MeteorSpawn.spawnMeteor(pickTarget(), { legendary = legendary })

			task.wait(CONFIG.METEOR_INTERVAL_MIN
				+ math.random() * (CONFIG.METEOR_INTERVAL_MAX - CONFIG.METEOR_INTERVAL_MIN))
		end

		-- ---- 6) ENDING (ENDING_DURATION): frequency tapers, sky restores ----
		meteorPhase("ending", "\u{2604} Meteor Shower Ending\u{2026}")
		local endDeadline = os.clock() + CONFIG.ENDING_DURATION
		while os.clock() < endDeadline do
			-- A few last, sparse meteors.
			if math.random() < 0.4 then
				MeteorSpawn.spawnMeteor(pickTarget(), {})
			end
			task.wait(1.5)
		end

		-- Let the final impacts/scorch breathe before teardown.
		task.wait(2)
	end)

	if not ok then
		warn("[MeteorStorm] event errored: " .. tostring(err))
	end

	-- ---- 7) RESET: tell clients to restore sky + destroy everything ----
	stopIntroSound()                   -- safety: stop the intro if the event errored within its first 10s
	MeteorSync:FireAllClients("reset") -- clients restore Lighting/sky fully
	MeteorSpawn.cleanup()
	MeteorImpact.cleanup()
	MeteorReward.cleanup()
	eventRunning = false
end

--------------------------------------------------------------------
-- Public starter (used by the interval timer + test triggers).
--------------------------------------------------------------------
local function startEvent()
	if eventRunning then
		warn("[MeteorStorm] start ignored: a storm is already running.")
		return
	end
	task.spawn(runEvent)
end

--======================================================================
-- BIG-EVENT SCHEDULER REGISTRATION.
-- This event's own interval timer is DISABLED -- the single BigEventScheduler
-- (BigEventScheduler.server.lua) now decides when each big event runs (one at a
-- time, every 7 min, never the same twice in a row). We just register our start
-- function + a running-state query for it to use.
--======================================================================
_G.BigEvents = _G.BigEvents or {}
_G.BigEvents.meteor = { start = startEvent, isRunning = function() return eventRunning end }

-- (Pre-launch cleanup: the "/meteor" chat command + _G.startMeteorStorm manual test trigger were removed.
-- The event still fires on its own via the BigEventScheduler using the registration above.)
