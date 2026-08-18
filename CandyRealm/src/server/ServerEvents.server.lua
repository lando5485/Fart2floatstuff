-- ============================================================================================================
-- SERVER EVENTS (server) -- the realm-wide "mini events" driver for Candy Realm.
-- ============================================================================================================
-- ⚠ WHY THIS FILE HAD TO BE WRITTEN: CANDY'S EVENTS WERE COMPLETELY DEAD.
--
-- Candy already had the ENTIRE presentation half -- EventClient.client.lua is ~2,000 lines of banners, glow
-- pulses, wind streaks, screen shake, storm fog, meteor visuals and a countdown pill, all finished and all
-- unreachable. Three separate breaks, any one of which was enough on its own:
--
--   1. NOTHING ON THE SERVER EVER FIRED AN EVENT. In the Food realm the pool + loop live inside
--      PlayerStats.server.lua, which Candy does not have. No equivalent was ever written here, so no event
--      was ever broadcast in this realm.
--   2. THE REMOTE DID NOT EXIST. Food declares ServerEventNotify in its default.project.json; Candy's project
--      file folder-syncs src/ and declares no remotes, so ReplicatedStorage.ServerEventNotify was never
--      created. MusicDucking.client sat on a 30s WaitForChild for it and always timed out.
--   3. THE CLIENT HANDLER NEVER EVEN CONNECTED. EventClient reads `_G.ServerEventNotify`, which Food's
--      CoreClient publishes -- Candy has no CoreClient, so that global was always nil and the whole
--      `if ServerEventNotify then ... end` block was skipped at load.
--
-- This file fixes 1 and 2. Break 3 is fixed in EventClient itself, which now resolves the remote directly
-- instead of depending on a global from a script this realm does not have.
--
-- ===== THE PROTOCOL (unchanged from the Food realm, deliberately) =====
-- Candy's EventClient is a copy of Food's, so it already understands Food's exact wire format and event names.
-- Inventing a Candy-specific protocol would have meant rewriting 2,000 lines of working client code for no
-- gain, so this speaks the format that client already parses:
--
--     ServerEventNotify:FireAllClients(name, displayName, durationSeconds, message, color)
--     ServerEventNotify:FireAllClients("END", "", 0, "", white)   -- when it is over
--
-- The names below are the ones EventClient branches on (EventClient ~1361). Changing a `name` string here
-- silently turns that event into a generic banner with no mechanics, because the client's branch stops
-- matching -- the display name is the only part safe to reword.
--
-- workspace:SetAttribute("ActiveServerEvent", name) is also set, mirroring Food, so SERVER scripts can react
-- without a remote of their own (Food's campfire douses itself during a thunderstorm this way).
-- ============================================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create the remote HERE, before anything waits on it. MusicDucking.client does a WaitForChild with a 30s
-- timeout, and the client can start before this script runs -- so it must exist as early as possible, and it
-- must be created rather than assumed.
local function getOrCreate(parent, className, name)
	local inst = parent:FindFirstChild(name)
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = parent
	end
	return inst
end
local ServerEventNotify = getOrCreate(ReplicatedStorage, "RemoteEvent", "ServerEventNotify")

-- ===== CONFIG =====
local DISABLE_EVENTS   = false  -- flip true to silence every event without deleting anything
local FIRST_EVENT_WAIT = 240    -- seconds before the first event of a server's life
local BETWEEN_EVENTS   = 240    -- seconds of quiet between events
local END_GRACE        = 2      -- seconds after an event's duration before "END" is broadcast (matches Food)

-- ===== THE POOL =====
-- `name` MUST stay in the set EventClient handles; `dispName`/`msg` are the player-facing text and are the only
-- fields safe to reword for the candy theme. Durations and colours match Food's so the pacing players already
-- know carries across realms.
--
-- THUNDERSTORM / WINDSTORM are deliberately NOT in this pool. EventClient treats those two as "big events"
-- with their own early-return branches (they take over the sky, delete the Atmosphere and swap in fog), and
-- Food schedules them from a separate BigEventScheduler rather than the ordinary rotation. Adding them here
-- would fire a full storm on the 4-minute mini-event timer, which is not what either client expects.
local eventPool = {
	{ name = "FART_STORM",  dispName = "\xF0\x9F\x92\xA8 SUGAR RUSH",   weight = 15, dur = 7,
	  msg = "\xF0\x9F\x92\xA8 SUGAR RUSH! Everyone flies faster for 7 seconds!",   r = 100, g = 200, b = 255 },
	{ name = "COIN_RUSH",   dispName = "\xF0\x9F\x92\xB0 COIN RUSH",    weight = 15, dur = 7,
	  msg = "\xF0\x9F\x92\xB0 COIN RUSH! Double coins for 7 seconds!",             r = 255, g = 200, b = 0 },
	-- DISPLAY-NAME-ONLY rename, exactly as in Food: the internal key stays LOW_GRAVITY because that is the
	-- branch EventClient matches on and where the speed / gas-drain multipliers live.
	{ name = "LOW_GRAVITY", dispName = "\xF0\x9F\x8C\x99 HIGH GRAVITY", weight = 15, dur = 10,
	  msg = "\xF0\x9F\x8C\x99 HIGH GRAVITY! Float like a marshmallow for 10 seconds!", r = 150, g = 100, b = 255 },
	{ name = "POWER_SURGE", dispName = "\xE2\x9A\xA1 POWER SURGE",      weight = 15, dur = 20,
	  msg = "\xE2\x9A\xA1 POWER SURGE! Fly higher than ever for 20 seconds!",     r = 255, g = 255, b = 0 },
	{ name = "RING_FEVER",  dispName = "\xF0\x9F\x8E\xAF RING FEVER",   weight = 15, dur = 30,
	  msg = "\xF0\x9F\x8E\xAF RING FEVER! Massive ring bonuses for 30 seconds!",  r = 255, g = 100, b = 200 },
}

-- Weighted pick. Food's own picker ignores its `weight` column and picks uniformly; this one actually uses it,
-- so tuning a weight here does something. With every weight equal the behaviour is identical to Food's.
local function pickRandomEvent()
	local total = 0
	for _, e in ipairs(eventPool) do total = total + (e.weight or 1) end
	if total <= 0 then return eventPool[1] end
	local roll = math.random() * total
	local acc = 0
	for _, e in ipairs(eventPool) do
		acc = acc + (e.weight or 1)
		if roll <= acc then return e end
	end
	return eventPool[#eventPool]
end

local firedCount = 0
local activeEvent = nil -- guards against two events overlapping (the loop and a dev command racing)

local function fireEvent(ev)
	if not ev or activeEvent then return false end
	activeEvent = ev.name
	firedCount = firedCount + 1

	pcall(function()
		ServerEventNotify:FireAllClients(ev.name, ev.dispName, ev.dur, ev.msg, Color3.fromRGB(ev.r, ev.g, ev.b))
	end)
	workspace:SetAttribute("ActiveServerEvent", ev.name)
	print(("[Events] %s fired (%ds) -- %d event(s) this session"):format(ev.name, ev.dur, firedCount))

	task.delay(ev.dur + END_GRACE, function()
		pcall(function() ServerEventNotify:FireAllClients("END", "", 0, "", Color3.new(1, 1, 1)) end)
		workspace:SetAttribute("ActiveServerEvent", "")
		activeEvent = nil
		print(("[Events] %s ended"):format(ev.name))
	end)
	return true
end

-- Exposed so a dev command or a quest reward can fire one on demand through the SAME path the loop uses --
-- one code path means a hand-fired event can never behave differently from a scheduled one.
_G.fireCandyEvent = function(name)
	for _, e in ipairs(eventPool) do
		if e.name == name then return fireEvent(e) end
	end
	warn(("[Events] no event named %q -- valid: FART_STORM, COIN_RUSH, LOW_GRAVITY, POWER_SURGE, RING_FEVER")
		:format(tostring(name)))
	return false
end

task.spawn(function()
	if DISABLE_EVENTS then
		print("[Events] DISABLED (DISABLE_EVENTS = true) -- no events will fire")
		return
	end
	task.wait(FIRST_EVENT_WAIT)
	while true do
		local ev = pickRandomEvent()
		if fireEvent(ev) then
			task.wait(ev.dur + END_GRACE)
		end
		task.wait(BETWEEN_EVENTS)
	end
end)

workspace:SetAttribute("ActiveServerEvent", "") -- publish the idle state immediately, so a reader never sees nil

print(("[Events] Candy Realm mini events ONLINE -- %d event(s) in the pool, first in %ds, then every %ds.")
	:format(#eventPool, FIRST_EVENT_WAIT, BETWEEN_EVENTS))
print("[Events] ServerEventNotify created. This realm has never fired an event before: the remote did not"
	.. " exist, nothing broadcast, and EventClient's handler never connected. All three are fixed now.")
