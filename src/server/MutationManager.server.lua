--======================================================================
-- MutationManager.server.lua  (Script)
--======================================================================
-- Orchestrates the global "MutationEvent" spectacle.
--
-- Radioactive chaos sweeps the map: the sky turns neon green/purple, toxic
-- clouds spread, alarms wail, then a creeping warning phase fills the gaps
-- between islands with green fog + electrical surges + panicking NPCs, then
-- a MAIN phase where players, NPCs, and the environment mutate randomly +
-- RADIOACTIVE STORMS strike islands (nearby players get a STRONGER mutation).
-- Finally radiation fades, every mutation wears off, the world restores, and
-- the EVENT_INTERVAL timer restarts.
--
-- DESIGN / SAFETY (mirrors the Rocket / Meteor / UFO / IceAge events):
--   * GREENFIELD ADD-ON. This event NEVER reads or modifies the fart meter,
--     fart power, flight code, food prices, gut stats, island heights, the
--     normal coin earn rate, coins, the falling junk hazard, the planes, or
--     any other event. The ONLY _G access in the whole event is the CLIENT
--     READING `_G.isFlying` to gate the guarded player mutations.
--   * All sequencing/timing runs on the SERVER. Server-created world parts
--     replicate so the whole server sees the same mutation. The MutationSync
--     RemoteEvent carries client presentation (sky/banners/SFX/particles) AND
--     the per-client PLAYER-MUTATION messages (since characters are client-
--     owned, the affected client applies + gates + reverts its own mutations).
--   * ★ PLAYER MUTATIONS split COSMETIC vs GUARDED ★ — the client enforces the
--     contract: cosmetic = appearance/sound only (anytime, may stack);
--     guarded = grounded-only behind `_G.isFlying`/grounded gate, suspended
--     the instant the player flies/leaves ground, height-capped by
--     GUARDED_MAX_BOOST_HEIGHT so they can NEVER reach a higher/locked island
--     or skip progression, temporary, never touch power/flight, fully revert.
--   * Everything is CAPPED + fully cleaned up on reset (no leaks, no player
--     or NPC left mutated).
--======================================================================

--======================================================================
-- CONFIG  -- EDIT ANYTHING HERE. Every value is tunable + commented. The
-- guarded magnitudes are deliberately GENTLE + height-capped; zero one to
-- disable that mutation without breaking the spectacle.
--======================================================================
local CONFIG = {
	-- ---------------- TIMINGS (seconds) ----------------
	EVENT_INTERVAL    = 1500, -- seconds between auto-runs of the Mutation Event (25 min)
	WARNING_DURATION  = 20,   -- WARNING phase: fog rises, surges flash, NPCs panic
	MAIN_DURATION     = 80,   -- MAIN phase: full chaos (player/NPC/world mutations + storms)
	ENDING_DURATION   = 12,   -- ENDING phase: radiation weakens, everything reverts

	-- ---------------- AMBIENT SOUND (server-wide, looped, full event) ----------------
	-- Plays SERVER-WIDE the moment the event begins, LOOPED for the whole event,
	-- then hard-stops at the ENDING/cleanup phase. The ~5s clip loops to fill it.
	AMBIENT_SOUND_ID     = "rbxassetid://97213152915968",
	AMBIENT_SOUND_VOLUME = 1,  -- same as the meteor intro sound (matches every event sound)

	PLAYER_MUTATION_INTERVAL = 6, -- seconds between server "roll a player mutation" pulses (MAIN)
	NPC_MUTATION_INTERVAL    = 5, -- seconds between server NPC-mutation pulses (MAIN)
	STORM_INTERVAL_MIN = 7,   -- min seconds between radioactive storms (MAIN)
	STORM_INTERVAL_MAX = 14,  -- max seconds between radioactive storms (MAIN)
	SURGE_INTERVAL_MIN = 5,   -- min seconds between electrical surge flashes
	SURGE_INTERVAL_MAX = 11,  -- max seconds between electrical surge flashes

	-- ---------------- PLAYER MUTATION GROUPS ----------------
	-- Probability that a given player roll picks from the GUARDED group (else
	-- cosmetic). Cosmetic is the majority for safety + chaos-without-grief.
	GUARDED_PICK_CHANCE = 0.35,

	-- COSMETIC group (SAFE: appearance/sound only, may apply ANYTIME, may
	-- STACK, never affect flight). Each: id, weight (relative pick odds),
	-- duration (seconds), and an optional magnitude the client interprets.
	COSMETIC_MUTATIONS = {
		{ id = "giant_arms",     weight = 3, duration = 12, magnitude = 2.5 }, -- arm scale
		{ id = "tiny_legs",      weight = 3, duration = 12, magnitude = 0.4 }, -- leg scale
		{ id = "massive_head",   weight = 3, duration = 12, magnitude = 3.0 }, -- head scale
		{ id = "tiny_body",      weight = 2, duration = 12, magnitude = 0.5 }, -- torso scale
		{ id = "glowing_skin",   weight = 3, duration = 14 },                  -- neon green recolor
		{ id = "giant_hands",    weight = 2, duration = 12, magnitude = 2.5 }, -- hand scale
		{ id = "giant_feet",     weight = 2, duration = 12, magnitude = 2.5 }, -- foot scale (+ small shake)
		{ id = "balloon_body",   weight = 2, duration = 12, magnitude = 1.8 }, -- inflated body scale
		{ id = "squeaky_voice",  weight = 2, duration = 10 },                  -- squeaky SFX
		{ id = "spin",           weight = 2, duration = 8 },                   -- cosmetic visual spin only
		{ id = "radioactive_trail", weight = 3, duration = 14 },               -- green trail
		{ id = "goofy_anim",     weight = 2, duration = 10 },                  -- goofy animation
	},

	-- GUARDED group (movement/fart-altering). Client applies ONLY while
	-- grounded + not flying, suspends instantly on flight/airborne, height-
	-- capped by GUARDED_MAX_BOOST_HEIGHT, temporary, fully reverted. Each:
	-- id, weight, duration, magnitude (units depend on the mutation; all
	-- gentle + capped). These only touch Humanoid props / short HRP physics.
	GUARDED_MUTATIONS = {
		{ id = "super_jump",   weight = 3, duration = 10, magnitude = 90 },  -- JumpPower (capped by height)
		{ id = "extra_speed",  weight = 3, duration = 10, magnitude = 28 },  -- +WalkSpeed added
		{ id = "fart_cloud",   weight = 3, duration = 10 },                  -- COSMETIC particle only (no force)
		{ id = "super_fart_boost", weight = 2, duration = 10, magnitude = 55 }, -- one capped upward hop
		{ id = "floating",     weight = 2, duration = 8,  magnitude = 6 },   -- HipHeight float (studs, small)
		{ id = "bouncing",     weight = 2, duration = 10, magnitude = 45 },  -- gentle repeated capped hops
		{ id = "reverse_controls", weight = 2, duration = 8 },               -- client input remap (no force)
	},

	-- ---------------- ★ GUARDED SAFETY ★ ----------------
	-- The HARD cap (studs above the player's grounded start) that ANY guarded
	-- vertical boost (super jump / bounce / float / super-fart hop / ultimate)
	-- may carry the player. Islands are HUNDREDS of studs apart vertically
	-- (e.g. 50 -> 600), so this is WELL below the gap: it's a spectacle hop,
	-- never a climb, and can NEVER reach a higher/locked island or bank height
	-- to skip progression. The client enforces this every frame.
	GUARDED_MAX_BOOST_HEIGHT = 40,

	-- ---------------- ULTIMATE MUTATION (rare) ----------------
	ULTIMATE_CHANCE      = 0.01, -- chance a player roll becomes the Ultimate
	ULTIMATE_DURATION    = 12,   -- seconds the Ultimate lasts
	ULTIMATE_GIANT_SCALE = 3,    -- how gigantic the player becomes (cosmetic scale)
	-- Ultimate's boosted fart/jump is STILL GUARDED: grounded-only, capped by
	-- GUARDED_MAX_BOOST_HEIGHT, temporary, fully reverted (handled client-side).

	-- ---------------- RADIOACTIVE STORMS ----------------
	STORM_RADIUS        = 60,   -- studs from a strike a player gets the STRONGER mutation
	STORM_STRONG_CHANCE = 1.0,  -- chance a struck-nearby player gets the strong variant
	STORM_DURATION_MULT = 1.4,  -- storm-boosted ("strong") mutations last this much longer

	-- ---------------- NPC CHAOS ----------------
	NPC_MUTATIONS = { -- weighted id list for NPC mutations (server-side)
		{ id = "grow",   weight = 3, duration = 9 },
		{ id = "shrink", weight = 3, duration = 9 },
		{ id = "speed",  weight = 3, duration = 9 },
		{ id = "bounce", weight = 2, duration = 9 },
		{ id = "glow",   weight = 3, duration = 10 },
		{ id = "scream", weight = 2, duration = 6 },
	},
	NPC_GROW_FACTOR     = 2.0,  -- grow mutation scale factor
	NPC_SHRINK_FACTOR   = 0.5,  -- shrink mutation scale factor
	NPC_SPEED_FACTOR    = 3.0,  -- speed mutation WalkSpeed multiplier
	NPC_BOUNCE_MAX_JUMP = 90,   -- cap on bounce JumpPower (NPCs only; not players)
	NPC_COMBINE_DURATION = 7,   -- seconds a "combined giant mutant" pair lasts
	NPC_COMBINE_CHANCE  = 0.15, -- chance per NPC pulse to instead do a combine

	-- ---------------- CAPS (PERFORMANCE is the #1 risk) ----------------
	MAX_PARTICLE_RATE   = 26,   -- HARD cap on EVERY ParticleEmitter Rate (server + client)
	MAX_WORLD_MUTATIONS = 220,  -- HARD cap on simultaneous world-mutation parts
	MAX_MUTATED_NPCS    = 8,    -- HARD cap on simultaneously mutated NPCs
	MAX_HEAVY_PLAYER_FX = 6,    -- HARD cap on simultaneous players with heavy effects (client mirrors)

	-- ---------------- TARGETING ----------------
	-- Fallback island top-surface positions (X,Y,Z) if a model can't be found
	-- or a raycast fails. Sourced from the game's ISLAND_POSITIONS.
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

-- Sibling ModuleScripts (synced via default.project.json).
local MutationEffects = require(ServerScriptService:WaitForChild("MutationEffects"))
local NPCMutationSystem = require(ServerScriptService:WaitForChild("NPCMutationSystem"))
local Generator = require(ServerScriptService:WaitForChild("RandomMutationGenerator"))

-- The sync RemoteEvent (added to ReplicatedStorage via default.project.json).
local MutationSync = ReplicatedStorage:WaitForChild("MutationSync")
-- [LATE-JOIN] Record the last LIFECYCLE phase + payload into _G.BigEvents.mutation so LateJoinEventSync
-- can replay the EXACT current visuals (sky + maxBoostHeight from the start payload) to a late-joiner.
-- The FireAllClients inside is IDENTICAL to the direct call -- this ONLY also stashes phase/payload
-- (purely additive). Transient effects (mutate/surge/storm) keep calling MutationSync:FireAllClients.
local function mutationPhase(phase, payload)
	MutationSync:FireAllClients(phase, payload)
	local e = _G.BigEvents and _G.BigEvents.mutation
	if e then
		e.currentPhase, e.currentPayload = phase, payload
		if phase == "start" then e.startPayload = payload end
	end
end

-- Wire the modules together (CONFIG is owned here; pass it down).
Generator.init(CONFIG)
MutationEffects.init(CONFIG, MutationSync)
NPCMutationSystem.init(CONFIG, Generator)

--======================================================================
-- State.
--======================================================================
local eventRunning = false -- guard so we never run two Mutation Events at once

--======================================================================
-- AMBIENT SOUND (server-wide, looped, whole event).
-- Parented to a Folder in Workspace (a non-BasePart), so it plays globally /
-- 2D for EVERY client regardless of position -- server-wide. Created on the
-- server => replicates to all. Looped; explicitly stopped at the ENDING phase.
--======================================================================
local ambientSoundHolder = nil

local function startAmbientSound()
	if ambientSoundHolder and ambientSoundHolder.Parent then ambientSoundHolder:Destroy() end
	local holder = Instance.new("Folder")
	holder.Name = "MutationAmbientSound"
	holder.Parent = workspace      -- Folder (non-BasePart) => global / server-wide
	ambientSoundHolder = holder

	local snd = Instance.new("Sound")
	snd.Name = "MutationAmbient"
	snd.SoundId = CONFIG.AMBIENT_SOUND_ID
	snd.Volume = CONFIG.AMBIENT_SOUND_VOLUME
	snd.Looped = true              -- loop the ~5s clip for the whole event
	snd.Parent = holder
	snd:Play()
end

-- stopAmbientSound(): hard-stop + remove the looped sound. Idempotent (safe to
-- call at ENDING and again in the reset/error path).
local function stopAmbientSound()
	if ambientSoundHolder and ambientSoundHolder.Parent then ambientSoundHolder:Destroy() end
	ambientSoundHolder = nil
end

--======================================================================
-- TARGETING: resolve island top-surface positions (same approach as the
-- other events). Scan Workspace for "Island_<n>_..." models, take the center,
-- raycast DOWN to the top surface; fall back to CONFIG.FALLBACK_TARGETS.
--======================================================================
local function snapToGround(x, z, fromY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(exclude, plr.Character) end
	end
	local tut = workspace:FindFirstChild("TutorialNPCs")
	if tut then table.insert(exclude, tut) end
	-- Exclude our own event folders so we never raycast onto our own props.
	for _, name in ipairs({ "MutationWorldVFX", "MutationStorms" }) do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(exclude, f) end
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	local hit = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -8000, 0), params)
	return hit and hit.Position.Y or nil
end

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
							size = size,
							model = child,
						})
						found = true
					end
					break
				end
			end
		end
		if not found and CONFIG.FALLBACK_TARGETS[i] then
			local fb = CONFIG.FALLBACK_TARGETS[i]
			local gy = snapToGround(fb.X, fb.Z, fb.Y + 200)
			table.insert(targets, {
				index = i,
				position = Vector3.new(fb.X, gy or fb.Y, fb.Z),
				size = Vector3.new(140, 40, 140),
				model = nil,
			})
		end
	end
	if #targets == 0 then
		for i, fb in ipairs(CONFIG.FALLBACK_TARGETS) do
			table.insert(targets, { index = i, position = fb, size = Vector3.new(140, 40, 140) })
		end
	end
	return targets
end

--======================================================================
-- PLAYER MUTATION DRIVING.
-- Characters are client-owned, so the SERVER only DECIDES which mutation +
-- when (+ storm proximity for "strong") and messages the affected client.
-- The CLIENT (MutationUI) applies, gates the guarded ones, and reverts.
--======================================================================

-- mutateOnePlayer(player, strong): roll + send one player a mutation message.
local function mutateOnePlayer(player, strong)
	local pick = Generator.rollPlayerMutation(strong)
	if not pick then return end
	MutationSync:FireClient(player, "mutate", {
		id = pick.id,
		group = pick.group,                 -- "cosmetic" | "guarded" | "ultimate"
		duration = pick.duration,
		magnitude = pick.magnitude,
		strong = pick.strong,
		maxBoostHeight = CONFIG.GUARDED_MAX_BOOST_HEIGHT, -- client enforces this cap
	})
end

-- pulsePlayerMutations(): each MAIN pulse, roll a random mutation for a random
-- subset of players (so it feels chaotic, not synchronized).
local function pulsePlayerMutations()
	local players = Players:GetPlayers()
	for _, plr in ipairs(players) do
		-- ~60% chance each player gets a fresh roll this pulse.
		if math.random() < 0.6 then
			mutateOnePlayer(plr, false)
		end
	end
end

-- runStorm(targets): trigger a radioactive storm; any player within
-- STORM_RADIUS of the strike gets a STRONGER mutation (still fully guarded
-- on the client). Uses the strike position returned by MutationEffects.
local function runStorm(targets)
	local strikePos = MutationEffects.radioactiveStorm(targets)
	if not strikePos then return end
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - strikePos).Magnitude <= CONFIG.STORM_RADIUS then
			local strong = Generator.rollStormStrength()
			mutateOnePlayer(plr, strong)
		end
	end
end

--======================================================================
-- Full event sequence. Returns when the whole thing is done + cleaned.
--======================================================================
local function runEvent()
	if eventRunning then return end
	eventRunning = true

	local ok, err = pcall(function()
		local targets = getIslandTargets()

		-- ---- 1) START ----
		-- Sky -> neon green/purple, toxic clouds spread, bubbling + alarm.
		mutationPhase("start", {
			text = "\u{2623}\u{FE0F} MUTATION EVENT ACTIVE!",
			maxBoostHeight = CONFIG.GUARDED_MAX_BOOST_HEIGHT,
		})
		startAmbientSound()  -- server-wide looped sound for the whole event

		-- ---- 2) WARNING (~WARNING_DURATION) ----
		-- Green fog rises between islands, electrical surges flash, NPCs panic.
		mutationPhase("warning")
		MutationEffects.startFog(targets)
		-- A few surges during the warning build-up.
		task.spawn(function()
			local deadline = os.clock() + CONFIG.WARNING_DURATION
			while os.clock() < deadline and eventRunning do
				MutationEffects.electricalSurge(targets)
				task.wait(math.random(CONFIG.SURGE_INTERVAL_MIN, CONFIG.SURGE_INTERVAL_MAX))
			end
		end)
		task.wait(CONFIG.WARNING_DURATION)

		-- ---- 3) MAIN: full radioactive chaos ----
		mutationPhase("main")
		MutationEffects.startWorldMutations(targets) -- world mutates (VISUAL ONLY)
		NPCMutationSystem.start()                    -- begin NPC chaos + auto-revert tick

		local mainDeadline = os.clock() + CONFIG.MAIN_DURATION
		local nextPlayer = os.clock()
		local nextNPC = os.clock()
		local nextStorm = os.clock() + math.random(CONFIG.STORM_INTERVAL_MIN, CONFIG.STORM_INTERVAL_MAX)
		local nextSurge = os.clock() + math.random(CONFIG.SURGE_INTERVAL_MIN, CONFIG.SURGE_INTERVAL_MAX)

		while os.clock() < mainDeadline and eventRunning do
			local now = os.clock()
			if now >= nextPlayer then
				pulsePlayerMutations()
				nextPlayer = now + CONFIG.PLAYER_MUTATION_INTERVAL
			end
			if now >= nextNPC then
				if math.random() < CONFIG.NPC_COMBINE_CHANCE then
					NPCMutationSystem.combineTwo()
				else
					NPCMutationSystem.mutateSome()
				end
				nextNPC = now + CONFIG.NPC_MUTATION_INTERVAL
			end
			if now >= nextStorm then
				runStorm(targets)
				nextStorm = now + math.random(CONFIG.STORM_INTERVAL_MIN, CONFIG.STORM_INTERVAL_MAX)
			end
			if now >= nextSurge then
				MutationEffects.electricalSurge(targets)
				nextSurge = now + math.random(CONFIG.SURGE_INTERVAL_MIN, CONFIG.SURGE_INTERVAL_MAX)
			end
			task.wait(0.25)
		end

		NPCMutationSystem.stop()

		-- ---- 4) ENDING (ENDING_DURATION): radiation weakens, all revert ----
		mutationPhase("ending", {
			text = "\u{2623}\u{FE0F} Mutation Levels Returning to Safe Range\u{2026}",
		})
		stopAmbientSound()          -- event is ending -> hard-stop the looped sound
		MutationEffects.startMelt() -- fade world mutations
		task.wait(CONFIG.ENDING_DURATION)
	end)

	if not ok then
		warn("[Mutation] event errored: " .. tostring(err))
	end

	-- ---- RESET: restore everyone + destroy everything, no leftovers ----
	-- Client reverts ALL player mutations (cosmetic + guarded), restores the
	-- sky from its snapshot, removes particles + UI.
	stopAmbientSound()          -- safety: stop the sound even if the event errored early
	MutationSync:FireAllClients("reset")
	NPCMutationSystem.cleanup() -- restore every NPC (none left mutated)
	MutationEffects.cleanup()   -- destroy all world/storm parts
	eventRunning = false
end

--------------------------------------------------------------------
-- Public starter (used by the interval timer + test triggers).
--------------------------------------------------------------------
local function startEvent()
	if eventRunning then
		warn("[Mutation] start ignored: a Mutation Event is already running.")
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
_G.BigEvents.mutation = { start = startEvent, isRunning = function() return eventRunning end }

-- (Pre-launch cleanup: the "/mutation" chat command + _G.startMutation manual test trigger were removed.
-- The event still fires on its own via the BigEventScheduler using the registration above.)
