--======================================================================
-- BigEventScheduler.server.lua  (Script)
--======================================================================
-- ONE scheduler for the FIVE big server-wide events: Rocket, Meteor Storm,
-- UFO, Ice Age, Mutation. Each big-event manager registers itself into
--     _G.BigEvents[key] = { start = <fn>, isRunning = <fn returning bool> }
-- and DISABLES its own interval timer, so big-event timing is decided ONLY
-- here -- which fixes the old "events running on top of each other" bug.
--
-- RULES (from the spec):
--   * Only ONE big event runs at a time.
--   * Every SCHEDULE_INTERVAL (7 minutes) the scheduler randomly picks +
--     starts ONE of the five.
--   * NEVER the same event twice in a row (the next pick differs from the last).
--   * If a previous event is somehow STILL active when the timer fires, WAIT for
--     it to end cleanly before starting the next -> no overlap, ever.
--   * The medium/small events (wind, birds, ring fever, ...) are NOT touched --
--     they run independently on PlayerStats' own loop. This governs ONLY the five.
--   * (Pre-launch cleanup: the per-event /rocket /meteor /ufo /iceage /mutation chat commands +
--     _G.start* manual test triggers were removed from the managers. Big events now fire ONLY here.)
--======================================================================

local SCHEDULE_INTERVAL = 420   -- seconds between big-event picks (7 minutes)
local FIRST_DELAY       = 420   -- wait before the FIRST scheduled big event (fresh server isn't slammed)
local REGISTER_GRACE    = 10    -- let the five managers register into _G.BigEvents on startup
local ORDER = { "rocket", "meteor", "ufo", "iceage", "mutation" } -- the five big events

local lastKey = nil   -- the event started last time -> never picked again the very next time

-- True if ANY registered big event is currently running (so we never overlap).
local function anyRunning()
	local reg = _G.BigEvents
	if not reg then return false end
	for _, e in pairs(reg) do
		if e and e.isRunning and e.isRunning() then return true end
	end
	return false
end

-- Pick a registered big-event key that is NOT the one we ran last time.
local function pickNext()
	local reg = _G.BigEvents or {}
	local choices = {}
	for _, key in ipairs(ORDER) do
		if reg[key] and reg[key].start and key ~= lastKey then
			choices[#choices + 1] = key
		end
	end
	-- Edge case (e.g. only one event registered): if excluding lastKey leaves
	-- nothing, allow any registered event so the scheduler never stalls.
	if #choices == 0 then
		for _, key in ipairs(ORDER) do
			if reg[key] and reg[key].start then choices[#choices + 1] = key end
		end
	end
	if #choices == 0 then return nil end
	return choices[math.random(1, #choices)]
end

task.spawn(function()
	task.wait(REGISTER_GRACE)  -- managers register on startup
	task.wait(FIRST_DELAY)     -- first big event ~7 min in
	while true do
		-- NO OVERLAP: if a previous big event (scheduled OR a manual test) is still
		-- active, wait for it to end cleanly before starting the next.
		while anyRunning() do task.wait(1) end

		local key = pickNext()
		if key then
			lastKey = key
			print("[BigEventScheduler] starting big event: " .. key)
			local ok, err = pcall(_G.BigEvents[key].start)
			if not ok then
				warn("[BigEventScheduler] start error for " .. key .. ": " .. tostring(err))
			end
		else
			print("[BigEventScheduler] no big events registered yet -- retrying next cycle")
		end

		task.wait(SCHEDULE_INTERVAL)
	end
end)

print("[BigEventScheduler] active: one big event every " .. SCHEDULE_INTERVAL ..
	"s, only one at a time, never the same twice in a row.")
