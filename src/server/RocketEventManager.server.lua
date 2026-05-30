--======================================================================
-- RocketEventManager.server.lua  (Script)
--======================================================================
-- Orchestrates the global "Rocket Construction & Launch" spectacle event.
--
-- This is a PURE BACKGROUND SPECTACLE. It does NOT read or modify the
-- player's fart meter, flight, food, guts, island heights, earn, coins,
-- the falling-junk hazard, or the plane hazard. It only spawns its own
-- replicated parts and fires its own RemoteEvent for client presentation.
--
-- All timing is driven on the SERVER. Server-created parts replicate to
-- all clients automatically, so everyone sees the same build/launch/boom.
-- The RocketEventSync RemoteEvent is used ONLY for client-side
-- presentation (notification text, countdown number, camera shake, flash).
--======================================================================

--======================================================================
-- CONFIG  -- edit anything here. All values are tunable.
--======================================================================
local CONFIG = {
	EVENT_INTERVAL = 900,      -- seconds between events (15 min)
	BUILD_DURATION = 60,       -- construction phase length (split across 5 stages)
	COUNTDOWN = 10,            -- countdown seconds
	LIFTOFF_DURATION = 2.5,    -- slow vertical lift before it accelerates
	FLIGHT_DURATION = 12,      -- seconds to fly from island 1 across to island 14
	ROCKET_SITE = nil,         -- nil = auto: MIDDLE of island 1 (workspace "Stand1Pos"). Set Vector3 to override.
	FLIGHT_END = Vector3.new(380, 23749, -340) + Vector3.new(0, 120, 0), -- above island 14 (explosion point); editable
	MAX_DEBRIS = 18,           -- explosion debris cap (perf)
}

--======================================================================
-- Services + module requires.
--======================================================================
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Sibling ModuleScripts created by this event (synced via default.project.json).
local RocketNPCs = require(ServerScriptService:WaitForChild("RocketNPCs"))
local RocketLogic = require(ServerScriptService:WaitForChild("RocketLogic"))
local RocketEffects = require(ServerScriptService:WaitForChild("RocketEffects"))

-- The sync RemoteEvent (added to ReplicatedStorage via default.project.json).
local RocketEventSync = ReplicatedStorage:WaitForChild("RocketEventSync")
-- [LATE-JOIN] Record the last LIFECYCLE phase + payload into _G.BigEvents.rocket so LateJoinEventSync
-- can replay the EXACT current state to a late-joiner: the "start" banner + "Go to Island 1" button,
-- and (if still building) "constructionStart" with the SITE so the client's positional construction
-- sound loop starts. The FireAllClients inside is IDENTICAL to the direct call -- this ONLY also stashes
-- phase/payload (purely additive). Transient effects (shake/flash) keep firing directly. (The 3D rocket
-- build is ModelStreamingMode.Persistent, so it already replicates to late-joiners.)
local function rocketPhase(phase, payload)
	RocketEventSync:FireAllClients(phase, payload)
	local e = _G.BigEvents and _G.BigEvents.rocket
	if e then
		e.currentPhase, e.currentPayload = phase, payload
		if phase == "start" then e.startPayload = payload end
	end
end

--======================================================================
-- State.
--======================================================================
local eventRunning = false   -- guard so we never run two events at once

--------------------------------------------------------------------
-- Resolve the construction site (ground position on island 1).
-- When CONFIG.ROCKET_SITE is nil, wait for workspace attribute
-- "Stand1Pos" (published by PlayerStats after stand setup), polling up
-- to ~30s. Fall back to a sane default if it never appears.
--------------------------------------------------------------------
-- snapToGround: raycast straight down at (x,z) from fromY to find the island
-- TOP SURFACE Y. Ignores players + the Farmer (TutorialNPCs) so it lands on the
-- real ground. Returns nil if nothing is hit.
local function snapToGround(x, z, fromY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(exclude, plr.Character) end
	end
	local tut = workspace:FindFirstChild("TutorialNPCs")
	if tut then table.insert(exclude, tut) end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	local hit = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -6000, 0), params)
	return hit and hit.Position.Y or nil
end

-- Resolve the construction site = the CENTER (path crossroads / central hub) of
-- island 1, ON the ground. We take the HORIZONTAL CENTER of the Island_1_BeanFarm
-- model and raycast down to its top surface, so the rocket/NPCs/site sit dead-centre
-- on the island (not off near the bean stand). Set CONFIG.ROCKET_SITE to an explicit
-- Vector3 to override (e.g. paste the exact crossroads Position from Studio).
local function resolveSite()
	-- Explicit override: snap the given X/Z down to the ground.
	if typeof(CONFIG.ROCKET_SITE) == "Vector3" then
		local gy = snapToGround(CONFIG.ROCKET_SITE.X, CONFIG.ROCKET_SITE.Z, CONFIG.ROCKET_SITE.Y + 200)
		return Vector3.new(CONFIG.ROCKET_SITE.X, gy or CONFIG.ROCKET_SITE.Y, CONFIG.ROCKET_SITE.Z)
	end
	-- Auto: centre of the Island_1_BeanFarm model, snapped to its surface.
	local deadline = os.clock() + 30
	while os.clock() < deadline do
		local island = workspace:FindFirstChild("Island_1_BeanFarm")
		if island and island:IsA("Model") then
			local ok, cf, size = pcall(function() return island:GetBoundingBox() end)
			if ok and cf and size then
				local cx, cz = cf.Position.X, cf.Position.Z
				local gy = snapToGround(cx, cz, cf.Position.Y + size.Y / 2 + 30)
				if gy then
					return Vector3.new(cx, gy, cz)
				end
			end
		end
		task.wait(0.5)
	end
	-- Fallbacks: Stand1Pos, then a safe default.
	local stand = workspace:GetAttribute("Stand1Pos")
	if typeof(stand) == "Vector3" then
		warn("[RocketEvent] island centre not found; falling back to Stand1Pos.")
		return stand
	end
	warn("[RocketEvent] no island centre or Stand1Pos; using fallback (0,50,0).")
	return Vector3.new(0, 50, 0)
end

--------------------------------------------------------------------
-- Full event sequence. Returns when the whole thing is done + cleaned.
--------------------------------------------------------------------
local function runEvent()
	if eventRunning then
		return
	end
	eventRunning = true

	-- Wrap in pcall so a failure still cleans up + clears the guard.
	local ok, err = pcall(function()
		local site = resolveSite()
		-- [STREAMING DIAG] view in live via F9 -> Server tab. Confirms where the build is placed and
		-- whether instance streaming is on (the cause of far players not seeing the build).
		print(string.format("[RocketEvent] START site=(%.1f, %.1f, %.1f)  Workspace.StreamingEnabled=%s",
			site.X, site.Y, site.Z, tostring(workspace.StreamingEnabled)))

		-- ---- 1) START ----
		rocketPhase("start", "🚀 The Big Rocket Construction Event Starting! Everyone go to Island 1!")
		RocketEffects.playSiren(site)              -- optional alarm
		-- ORDER: build the ROCKET FIRST so it's guaranteed even if NPC spawning has trouble. spawn() is
		-- now resilient (per-worker pcall) so it can't abort the event, but building first is belt-and-
		-- suspenders: the rocket exists before any worker code runs.
		RocketLogic.beginBuild(site)               -- empty rocket model + PrimaryPart (guaranteed)
		RocketNPCs.spawn(site)                     -- 3 workers walk in (resilient: failures skip, never abort)
		RocketEffects.startBuildAmbience(site)     -- sparks/smoke/ambience
		rocketPhase("constructionStart", site) -- CLIENT-side positional build loop (mobile-reliable; each client plays its own — see RocketSounds.client.lua)
		RocketNPCs.build()                         -- hammer loop

		-- ---- 2) CONSTRUCTION ----
		-- 5 stages spread evenly across BUILD_DURATION so it visibly builds.
		local stageGap = CONFIG.BUILD_DURATION / 5
		for stage = 1, 5 do
			RocketLogic.addNextStage()             -- base -> body -> windows -> fins -> cone
			RocketNPCs.idle()                      -- personality between stages
			task.wait(stageGap)
		end

		-- [STREAMING DIAG] after the 5 build stages, confirm the build content exists + its part counts
		-- (view in live via F9 -> Server tab). With the Persistent streaming fix these should be visible
		-- to every client regardless of distance.
		do
			local function countParts(inst)
				if not inst then return -1 end
				local n = 0
				for _, d in ipairs(inst:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end
				return n
			end
			print(string.format("[RocketEvent] BUILD DONE  EventRocket parts=%d  RocketEventNPCs parts=%d  RocketSiteDressing parts=%d",
				countParts(workspace:FindFirstChild("EventRocket")),
				countParts(workspace:FindFirstChild("RocketEventNPCs")),
				countParts(workspace:FindFirstChild("RocketSiteDressing"))))
		end

		-- ---- 3) COUNTDOWN ----
		local primary = RocketLogic.getPrimaryPart()
		RocketEffects.startCountdownSmoke(primary) -- thickening smoke under rocket
		rocketPhase("constructionStop") -- stop the CLIENT-side build loop exactly at countdown
		RocketEffects.startCountdownSound()        -- start the SERVER-WIDE countdown sound for everyone
		for n = CONFIG.COUNTDOWN, 1, -1 do
			rocketPhase("countdown", n)     -- big "Launch in n..."
			RocketEventSync:FireAllClients("shake", site)      -- client camera shake near site
			RocketNPCs.idle()
			task.wait(1)
		end

		-- ---- 4) LAUNCH ----
		-- LAUNCH SOUND is now CLIENT-side: each client plays it locally on the "launch" sync below
		-- (mobile-reliable one-shot from SoundService — see RocketSounds.client.lua).
		RocketEffects.startLaunchTrail(primary)    -- fire + smoke trail (visual only)
		RocketNPCs.wave()                          -- workers wave; one falls backward
		rocketPhase("launch")   -- client may react (e.g. clear countdown)

		-- ---- 5) FLIGHT (no teleport) + 6) ENDING explosion on arrival ----
		RocketLogic.launch(CONFIG.FLIGHT_END, function()
			-- onArrive: cinematic explosion at FLIGHT_END.
			RocketEffects.explode(CONFIG.FLIGHT_END, CONFIG.MAX_DEBRIS)
			RocketEventSync:FireAllClients("flash")            -- brief client sky flash
			RocketEventSync:FireAllClients("end", "🚀 The rocket reached the stars!")
		end, CONFIG.LIFTOFF_DURATION, CONFIG.FLIGHT_DURATION)

		-- Small beat so the explosion visuals/sound finish before teardown.
		task.wait(3)
	end)

	if not ok then
		warn("[RocketEvent] event errored: " .. tostring(err))
	end

	-- ---- 7) RESET: destroy everything, no leftovers ----
	-- Safety: ensure the CLIENT-side construction loop stops even if the event aborted BEFORE the
	-- countdown's "constructionStop" fired (idempotent on the client if already stopped).
	RocketEventSync:FireAllClients("constructionStop")
	RocketNPCs.cleanup()
	RocketLogic.cleanup()
	RocketEffects.cleanup()
	eventRunning = false
end

--------------------------------------------------------------------
-- Public starter (used by the interval timer + test triggers).
--------------------------------------------------------------------
local function startEvent()
	if eventRunning then
		warn("[RocketEvent] start ignored: an event is already running.")
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
_G.BigEvents.rocket = { start = startEvent, isRunning = function() return eventRunning end }

-- (Pre-launch cleanup: the "/rocket" chat command + _G.startRocketEvent manual test trigger were removed.
-- The event still fires on its own via the BigEventScheduler using the registration above.)
