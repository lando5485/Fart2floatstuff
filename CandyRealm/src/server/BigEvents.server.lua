-- ============================================================================================================
-- BIG EVENTS (server) -- the realm-wide SET PIECES for Candy Realm.
-- ============================================================================================================
-- ⚠ WHY THIS FILE EXISTS: THREE FINISHED EVENT UIs WERE SITTING IN THIS REALM WITH NOTHING TO DRIVE THEM.
--
-- Every boot logged the same three lines, and they are the whole reason this file was written:
--
--     [MeteorUI]      MeteorSync never appeared      -- no meteor event in this realm, UI not built
--     [RainbowBeamUI] RainbowBeamSync never appeared -- no rainbow beam event in this realm, UI not built
--     [RocketUI]      RocketEventSync never appeared -- no rocket event in this realm, UI not built
--
-- That is MeteorUI (~430 lines: sky takeover, banners, camera shake, knockback, reward popup, ember field),
-- RocketUI (~330: countdown, launch shake, teleport button, flash) and RainbowBeamUI -- all complete, all
-- ported from the Food realm, and all waiting on a RemoteEvent that nothing in this realm ever created. Same
-- break ServerEvents.server.lua was written to fix for the MINI events, one level up.
--
-- THUNDERSTORM and WINDSTORM are the other half. EventClient implements both in full (storm fog, blur, wind
-- streaks, lightning, the countdown pill) and ServerEvents deliberately keeps them OUT of its 4-minute pool,
-- because they take over the sky and Food schedules them separately. "Separately" is this file -- which did
-- not exist, so they had never fired here either.
--
-- ===== THE PROTOCOLS ARE THE CLIENTS', NOT MINE =====
-- Every phase string and payload shape below is read off the client that consumes it. These are not names I
-- chose; a typo in one silently does nothing, because the client's branch simply stops matching:
--
--   MeteorSync      (phase, payload)  start / warning / distant / main / legendaryIncoming / impact /
--                                     knockback / reward / legendaryClaimed / ending / reset
--                                     impact payload = { position = Vector3, intensity = n, legendary = bool }
--   RocketEventSync (phase, payload)  start / countdown(n) / shake(Vector3) / launch / flash / end
--   RainbowBeamSync (action)          "hit"
--   ServerEventNotify (name, dispName, dur, msg, colour)  -- THUNDERSTORM / WINDSTORM, as EventClient expects
--
-- ===== IT NEVER OVERLAPS A MINI EVENT =====
-- ServerEvents sets workspace.ActiveServerEvent for the length of each mini event, exactly so other server
-- scripts can see one is running. This reads it and waits: two banners and two countdown pills on screen at
-- once is worse than either event on its own, and a thunderstorm starting mid-COIN RUSH steals the payoff of
-- the rush. It sets the same attribute while a big event runs, so the courtesy goes both ways.
-- ============================================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")

-- ===== CONFIG =====
local DISABLE_BIG_EVENTS = false   -- flip true to silence every set piece without deleting anything
local FIRST_WAIT         = 420     -- seconds before the first big event of a server's life
local BETWEEN            = 600     -- seconds of quiet between big events
local SETTLE             = 15      -- seconds to wait out a mini event that is already running

-- Create the remotes HERE, before anything waits on them. All three UIs use a bounded WaitForChild (30s, 30s,
-- 60s) and bail permanently on timeout -- so a remote created late is a remote that never gets used for the
-- rest of that client's session. This is the first thing the file does for that reason.
local function remote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local MeteorSync      = remote("MeteorSync")
local RocketEventSync = remote("RocketEventSync")
local RainbowBeamSync = remote("RainbowBeamSync")
local BlizzardSync    = remote("BlizzardSync")
local ServerEventNotify = remote("ServerEventNotify")   -- ServerEvents makes this too; whoever is first wins

-- Coins are written straight to leaderstats. NOT through CoinEvent: that is the client->server path the
-- flight economy uses, so the server cannot fire it at itself -- and an event paying out is exactly the case
-- that should never be routed through a remote a client could also send.
local function award(plr, amount)
	if not plr then return end
	local stats = plr:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	if coins then coins.Value = coins.Value + amount end
end

--=============================================================================================================
-- THE SET PIECES
--=============================================================================================================

-- ===== METEOR SHOWER =====
-- Paced as a build, not a burst: sky first, warning, distant rumbles you feel before you see anything, then
-- the shower itself, then one LEGENDARY meteor as the finish. The client owns every visual -- this is only
-- the timing and who gets paid.
local function runMeteorShower()
	MeteorSync:FireAllClients("start", "\u{2604} METEOR SHOWER INCOMING!")
	task.wait(4)
	MeteorSync:FireAllClients("warning", "Take cover! Candy meteors approaching...")

	-- distant rumbles: three of them, growing, so the shower announces itself through the floor
	for i = 1, 3 do
		task.wait(1.6)
		MeteorSync:FireAllClients("distant", { intensity = 0.15 + i * 0.08 })
	end

	MeteorSync:FireAllClients("main", "\u{2604} METEOR SHOWER!")

	-- the shower proper. Impacts land near random players so the shake is always somebody's problem, and
	-- the one they land near gets the knockback and the coins.
	for _ = 1, 10 do
		task.wait(1.4 + math.random() * 1.2)
		local list = Players:GetPlayers()
		if #list > 0 then
			local victim = list[math.random(1, #list)]
			local char = victim.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local at = hrp.Position + Vector3.new(math.random(-70, 70), 0, math.random(-70, 70))
				MeteorSync:FireAllClients("impact", { position = at, intensity = 0.55, legendary = false })
				-- knockback goes to that ONE client: it moves their own HRP, so broadcasting it would
				-- shove everybody in the server for a rock that landed nowhere near them
				MeteorSync:FireClient(victim, "knockback", { position = at, force = 55 })
				local coins = math.random(40, 90)
				award(victim, coins)
				MeteorSync:FireClient(victim, "reward", { coins = coins })
			end
		end
	end

	-- ---- the legendary: announced, held, then one big hit worth ten of the others ----
	MeteorSync:FireAllClients("legendaryIncoming", "\u{1F31F} LEGENDARY CANDY METEOR DETECTED!")
	task.wait(5)
	local list = Players:GetPlayers()
	if #list > 0 then
		local lucky = list[math.random(1, #list)]
		local char = lucky.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local at = hrp and hrp.Position or Vector3.new(0, 200, 0)
		MeteorSync:FireAllClients("impact", { position = at, intensity = 1, legendary = true })
		local coins = math.random(600, 1200)
		award(lucky, coins)
		MeteorSync:FireAllClients("legendaryClaimed", { player = lucky.DisplayName, coins = coins })
	end

	task.wait(3)
	MeteorSync:FireAllClients("ending", "\u{2604} Meteor Shower Ending\u{2026}")
	task.wait(4)
	MeteorSync:FireAllClients("reset")   -- MUST be sent: this is what restores the sky the client took over
end

-- ===== ROCKET LAUNCH =====
-- The only event that asks players to GO somewhere. RocketUI puts a "Go to Island 1" button on screen at
-- "start", so the gap before the countdown is travel time -- shorten it and half the server watches the
-- launch from four islands away.
local function runRocketLaunch()
	RocketEventSync:FireAllClients("start",
		"\u{1F680} CANDY ROCKET LAUNCH! Everyone to Candy Cane Court!")
	task.wait(25)   -- travel time; the teleport button is up for all of it

	local site = Vector3.new(0, 150, 0)   -- island1, the spawn island (IslandOrder slot 1)
	for n = 10, 1, -1 do
		RocketEventSync:FireAllClients("countdown", n)
		if n <= 3 then RocketEventSync:FireAllClients("shake", site) end
		task.wait(1)
	end

	RocketEventSync:FireAllClients("launch")
	RocketEventSync:FireAllClients("flash")

	-- everyone present when it goes up gets paid, whether or not they made it to the pad: the reward is for
	-- being in the server for the event, and gating it on position would punish the player who was mid-climb
	for _, plr in ipairs(Players:GetPlayers()) do
		award(plr, math.random(250, 400))
	end

	task.wait(6)
	RocketEventSync:FireAllClients("end")
end

-- ===== RAINBOW BEAM =====
-- The short one, and the only one that is a per-player moment rather than a server-wide spectacle: the beam
-- catches ONE player and RainbowBeamUI runs its rewind on them. Everyone else gets the announcement.
local function runRainbowBeam()
	local list = Players:GetPlayers()
	if #list == 0 then return end
	local caught = list[math.random(1, #list)]
	ServerEventNotify:FireAllClients("RAINBOW_BEAM", "\u{1F308} RAINBOW BEAM", 8,
		("\u{1F308} The rainbow beam caught %s!"):format(caught.DisplayName),
		Color3.fromRGB(255, 120, 220))
	RainbowBeamSync:FireClient(caught, "hit")
	award(caught, math.random(150, 300))
	task.wait(8)
	ServerEventNotify:FireAllClients("END", "", 0, "", Color3.new(1, 1, 1))
end

-- ===== POWDERED SUGAR BLIZZARD =====
-- The only set piece with a MECHANIC rather than just a spectacle: while it blows, being outside
-- costs you speed, and getting under a roof gives it back. Everything you see is Blizzard.client;
-- the server owns the one thing a client must not, which is deciding who is under cover.
--
-- THE SHELTER TEST IS SourRain'S, NOT A NEW ONE. One ray straight up, 30 studs, ignoring every
-- character. That distance is load-bearing and the reasoning is written out in SourRain.server:
-- longer and the island above reads as a roof, so the top of the tower is permanently "indoors"
-- and the event does nothing to anybody. Two different answers to "are you sheltered" is how you
-- get a player slowed under a roof because the client disagreed with the server.
local SHELTER_UP = 30
local blizzardRay = RaycastParams.new()
blizzardRay.FilterType = Enum.RaycastFilterType.Exclude

local function isSheltered(char)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return true end                  -- no body to slow down
	local hit = Workspace:Raycast(hrp.Position + Vector3.new(0, 2, 0),
		Vector3.new(0, SHELTER_UP, 0), blizzardRay)
	return hit ~= nil
end

local function runBlizzard()
	local DUR = 75
	ServerEventNotify:FireAllClients("BLIZZARD", "\u{2744} SUGAR BLIZZARD", DUR,
		"\u{2744} A powdered sugar blizzard is rolling in -- find cover!", Color3.fromRGB(210, 226, 250))
	BlizzardSync:FireAllClients("start")

	local told = {}          -- [player] = the last state we sent them
	local endAt = os.clock() + DUR
	while os.clock() < endAt do
		-- rebuilt every pass: characters respawn mid-storm, and a stale filter means a player's own
		-- torso starts counting as the roof over their head
		local ex = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then ex[#ex + 1] = p.Character end
		end
		blizzardRay.FilterDescendantsInstances = ex

		for _, plr in ipairs(Players:GetPlayers()) do
			local safe = isSheltered(plr.Character)
			-- sent only when it CHANGES: this loop runs four times a second and the client only
			-- needs to know the moment you step under something
			if told[plr] ~= safe then
				told[plr] = safe
				BlizzardSync:FireClient(plr, "shelter", safe)
			end
		end
		task.wait(0.25)
	end

	BlizzardSync:FireAllClients("stop")
	ServerEventNotify:FireAllClients("END", "", 0, "", Color3.new(1, 1, 1))
end

-- ===== THUNDERSTORM / WINDSTORM =====
-- These two need no server logic at all -- EventClient implements them end to end and only ever needed
-- somebody to say "go". The name string is what selects the branch there; the display name is free text.
local function runWeather(kind)
	if kind == "THUNDERSTORM" then
		ServerEventNotify:FireAllClients("THUNDERSTORM", "\u{26C8} SOUR STORM", 30,
			"\u{26C8} A sour storm rolls in -- hold on tight!", Color3.fromRGB(50, 50, 80))
		task.wait(32)
	else
		ServerEventNotify:FireAllClients("WINDSTORM", "\u{1F32A} SUGAR GALE", 25,
			"\u{1F32A} A sugar gale is tearing through the realm!", Color3.fromRGB(0, 200, 220))
		task.wait(27)
	end
	ServerEventNotify:FireAllClients("END", "", 0, "", Color3.new(1, 1, 1))
end

--=============================================================================================================
-- THE ROTATION
--=============================================================================================================
-- Weighted, and the weights are the pacing: the two weather events are the cheap ones and should come round
-- most often, the rocket is the rarest because it asks everyone to stop what they are doing and travel.
local POOL = {
	{ w = 30, name = "SOUR STORM",     run = function() runWeather("THUNDERSTORM") end },
	{ w = 25, name = "SUGAR GALE",     run = function() runWeather("WINDSTORM") end },
	{ w = 20, name = "METEOR SHOWER",  run = runMeteorShower },
	{ w = 20, name = "SUGAR BLIZZARD", run = runBlizzard },
	{ w = 15, name = "RAINBOW BEAM",   run = runRainbowBeam },
	{ w = 10, name = "ROCKET LAUNCH",  run = runRocketLaunch },
}

local function pick()
	local total = 0
	for _, e in ipairs(POOL) do total += e.w end
	local roll, acc = math.random() * total, 0
	for _, e in ipairs(POOL) do
		acc += e.w
		if roll <= acc then return e end
	end
	return POOL[#POOL]
end

if DISABLE_BIG_EVENTS then
	print("[BigEvents] DISABLED -- remotes created so the three UIs still build, but nothing will fire.")
	return
end

task.spawn(function()
	task.wait(FIRST_WAIT)
	local fired = 0
	while true do
		-- never on top of a mini event: two banners and two countdown pills at once is worse than either
		while Workspace:GetAttribute("ActiveServerEvent") do task.wait(SETTLE) end
		-- and never to an empty server -- an event nobody saw still burns its slot in the rotation
		if #Players:GetPlayers() > 0 then
			local e = pick()
			fired += 1
			Workspace:SetAttribute("ActiveServerEvent", e.name)
			print(("[BigEvents] %s fired -- %d big event(s) this session"):format(e.name, fired))
			local ok, err = pcall(e.run)
			if not ok then warn(("[BigEvents] %s errored: %s"):format(e.name, tostring(err))) end
			Workspace:SetAttribute("ActiveServerEvent", nil)
			print(("[BigEvents] %s ended"):format(e.name))
		end
		task.wait(BETWEEN)
	end
end)

print(("[BigEvents] ready -- %d set piece(s): sour storm, sugar gale, sugar blizzard, meteor shower, "
	.. "rainbow beam, rocket launch. First in %ds, then every %ds. MeteorSync / RocketEventSync / "
	.. "RainbowBeamSync / BlizzardSync created here, which is what finally builds those UIs.")
	:format(#POOL, FIRST_WAIT, BETWEEN))
