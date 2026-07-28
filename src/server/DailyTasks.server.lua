-- DailyTasks.server.lua  (Script)  -- the daily chore list, and the reason to log in tomorrow.
--
-- The game had already grown four separate once-per-day actions -- water the garden, feed the cow, feed the
-- pig, claim the daily reward -- and NOTHING told the player they existed. You had to walk into four different
-- prompts and discover them. This surfaces them as one checklist with a completion bonus.
--
-- SERVER-AUTHORITATIVE: the client only ever RECEIVES state. It cannot mark a task done, and it cannot claim
-- the bonus -- the bonus is granted here, automatically, the moment the fourth task lands. There is no "claim"
-- remote for a cheater to call.
--
-- HOW TASKS GET TICKED: each owning system calls _G.dailyTaskDone(player, id) at its OWN success point -- the
-- point where it has already validated everything. We deliberately do NOT re-implement "did they really water
-- it" here; the garden already knows, and two sources of truth would drift.

local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

-- ============================================================================
-- CONFIG
-- ============================================================================

-- Order here is the order they appear on the panel.
local TASKS = {
	{ id = "water",    label = "Water the Garden",   hint = "Get a can from the Gardener" },
	{ id = "feed_cow", label = "Feed the Cow",       hint = "Grab food from the cow's bin" },
	{ id = "feed_pig", label = "Feed the Pig",       hint = "Grab food from the pig's bin" },
	{ id = "invite",   label = "Invite a Friend",    hint = "Tap this to open the invite menu" },
}

-- ⚠ "invite" IS CLIENT-REPORTED, and that is not a mistake I can engineer away: Roblox's SocialService invite
-- prompt lives on the CLIENT, and the server is given no signal that an invite was actually sent. So the
-- client tells us, and a determined player could fire that remote without inviting anyone.
--
-- Accepted deliberately: the prize is the daily streak bonus (50-500 coins) once per day. The cost of faking
-- it is lower than the
-- cost of the machinery to stop it, and no other player is harmed. Every OTHER task is server-validated at its
-- own success point and cannot be spoofed. Do NOT copy this pattern for anything that pays real value.
local CLIENT_REPORTED = { invite = true }

-- ===== STREAK =====
-- Clearing all four tasks pays out, and CONSECUTIVE days pay more. Without this, day 50 pays exactly what day
-- 1 paid, so there is no reason to come back TOMORROW specifically -- only "eventually". A streak gives the
-- player something they can lose, which is the whole point.
--
-- Index = streak length, clamped to the end of the ladder. Day 7+ sits at the top rather than growing forever;
-- an unbounded ladder eventually pays absurd numbers to whoever has been around longest.
local STREAK_REWARDS = { 50, 75, 100, 150, 200, 300, 500 }
local function rewardFor(streak)
	return STREAK_REWARDS[math.clamp(streak, 1, #STREAK_REWARDS)]
end

-- Streak maths runs on an integer UTC DAY NUMBER, not the "YYYY-MM-DD" string used for the daily rollover.
-- "Was the last completion yesterday?" is `lastDay == today - 1` with integers, but string dates would need
-- real calendar arithmetic to get month and year boundaries right -- and that is exactly the kind of code that
-- quietly breaks on the 1st of March.
local function dayNumber() return math.floor(os.time() / 86400) end

-- The panel is HIDDEN on a player's first-ever join and appears from their second onward. A brand-new player
-- is already being walked through the garden cinematic, the farmer tutorial and their starter pet; a chore
-- list on top of that is noise at the exact moment they're most likely to bounce. By their second session
-- they know what a garden and a cow are, and the list reads as a goal instead of homework.
local SHOW_FROM_JOIN = 2

-- ⚠ STUDIO TEST OVERRIDE. In Studio the DataStore is dead (API access is off -- PlayerStats warns about this
-- every boot), so `joins` never persists and EVERY Studio session is join #1: the panel would be permanently
-- invisible and impossible to test. While this is true, Studio always shows it. The LIVE game is unaffected --
-- IsStudio() is false there, so real players still don't see it until their second join.
-- Set false to test the real first-join-hidden behaviour in Studio.
local STUDIO_ALWAYS_SHOW = true

-- ============================================================================

local store = DataStoreService:GetDataStore("DailyTasks_v1")

local DailyTasksEvent = ReplicatedStorage:FindFirstChild("DailyTasksEvent")
if not DailyTasksEvent then
	DailyTasksEvent = Instance.new("RemoteEvent")
	DailyTasksEvent.Name   = "DailyTasksEvent"
	DailyTasksEvent.Parent = ReplicatedStorage
end

local state = {} -- [player] = { day = "YYYY-MM-DD", done = { [id]=true }, bonus = bool }

local function utcDay() return os.date("!%Y-%m-%d") end
local function fresh()
	return { day = utcDay(), done = {}, bonus = false, joins = 0, streak = 0, lastDay = 0 }
end

-- A streak is only ALIVE if the last completed day was today or yesterday. Anything older means they missed a
-- day and it's back to zero. Evaluated lazily on read rather than by a scheduled job, so it stays correct for
-- a player who was offline for a week -- there is nobody around to run a job for them.
local function liveStreak(s)
	local last = tonumber(s.lastDay) or 0
	local today = dayNumber()
	if last == today or last == today - 1 then return tonumber(s.streak) or 0 end
	return 0 -- missed a day (or more) -> broken
end

-- New UTC day -> wipe the ticks and re-arm the bonus. Called on every read, so a player who stays online
-- through midnight rolls over correctly instead of being stuck on yesterday's list.
--
-- `joins` is deliberately NOT reset: it's a lifetime session count, not a daily one. Wiping it would hide the
-- panel again every single morning, which is the opposite of the point.
local function rollover(s)
	if s.day ~= utcDay() then
		s.day   = utcDay()
		s.done  = {}
		s.bonus = false
	end
	return s
end

local function stateOf(player)
	local s = state[player]
	if not s then s = fresh(); state[player] = s end
	return rollover(s)
end

local function save(player)
	local s = state[player]
	if not s then return end
	pcall(function()
		store:SetAsync(tostring(player.UserId), {
			day = s.day, done = s.done, bonus = s.bonus, joins = s.joins,
			streak = s.streak, lastDay = s.lastDay,
		})
	end)
end

local function load(player)
	local ok, v = pcall(function() return store:GetAsync(tostring(player.UserId)) end)
	local valid = ok and type(v) == "table" and v.day and type(v.done) == "table"
	-- On a store FAILURE we start them fresh rather than blocking: worst case someone re-earns a bonus they
	-- already had. Refusing to show the panel because a DataStore blipped would be the worse trade.
	local s = rollover(valid and v or fresh())
	s.joins = (tonumber(s.joins) or 0) + 1 -- count THIS session; lifetime, never reset by the daily rollover
	state[player] = s
	task.spawn(save, player) -- persist the bump now, so a crash can't lose it and re-hide the panel tomorrow
end

local function eligible(player)
	if STUDIO_ALWAYS_SHOW and RunService:IsStudio() then return true end -- ⚠ TEST ONLY; no effect on a live server
	return stateOf(player).joins >= SHOW_FROM_JOIN
end

-- What the client renders. Sends the task definitions too, so the panel never hardcodes a list that could
-- drift out of sync with this one.
local function push(player)
	local s = stateOf(player)
	local list = {}
	for _, t in ipairs(TASKS) do
		list[#list + 1] = { id = t.id, label = t.label, hint = t.hint, done = s.done[t.id] == true }
	end
	local streak = liveStreak(s)
	pcall(function()
		DailyTasksEvent:FireClient(player, {
			tasks      = list,
			bonus      = s.bonus,
			show       = eligible(player), -- false on a first-ever join -> the client keeps the panel hidden
			streak     = streak,
			-- What TODAY is worth. If they've already banked today the streak has been incremented, so show
			-- what they earned; otherwise show what finishing today would pay.
			bonusCoins = s.bonus and rewardFor(streak) or rewardFor(streak + 1),
			nextCoins  = rewardFor(streak + 1), -- what TOMORROW pays: the number they lose by not coming back
			maxStreak  = #STREAK_REWARDS,
		})
	end)
end

local function grantCoins(player, amt)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local tce   = ls:FindFirstChild("TotalCoinsEarned")
	if coins then coins.Value = coins.Value + amt end
	if tce   then tce.Value   = tce.Value + amt end
end

local function allDone(s)
	for _, t in ipairs(TASKS) do
		if not s.done[t.id] then return false end
	end
	return true
end

-- =====================  THE HOOK  =====================

-- Called by each owning system at its own validated success point. Safe to call repeatedly -- a task already
-- ticked today is a no-op, so a double-fire can't pay the bonus twice.
_G.dailyTaskDone = function(player, id)
	if not (player and player.Parent) then return end
	local s = stateOf(player)
	if s.done[id] then return end -- already ticked today

	-- Reject unknown ids loudly. A typo'd id in a caller would otherwise silently never tick, and the player
	-- would be stuck one task short of a bonus they can never earn -- with nothing in the log to say why.
	local known = false
	for _, t in ipairs(TASKS) do if t.id == id then known = true break end end
	if not known then
		warn("[DailyTasks] unknown task id '" .. tostring(id) .. "' -- ignored (check the caller)")
		return
	end

	s.done[id] = true
	print(string.format("[DailyTasks] %s completed '%s'", player.Name, id))

	-- CRATE TOKENS (cosmetic currency) ride along with every task. Guarded, so this file works unchanged with
	-- SkinCrateService absent. The AMOUNT lives in Shared/CrateTokens.REWARDS, not here -- retuning the cosmetic
	-- economy must never mean editing the quest system.
	if _G.crateTokensAward then pcall(_G.crateTokensAward, player, "dailyTask") end

	-- BONUS: paid automatically the instant the last task lands. No claim button -> nothing to exploit.
	if allDone(s) and not s.bonus then
		s.bonus = true

		-- Advance the streak. liveStreak() has already zeroed it if they missed a day, so this is just +1 --
		-- continuing a run and starting a fresh one are the same line.
		local newStreak = liveStreak(s) + 1
		s.streak  = newStreak
		s.lastDay = dayNumber()

		local payout = rewardFor(newStreak)
		grantCoins(player, payout)
		print(string.format("[DailyTasks] %s cleared ALL tasks -> day %d streak, +%d coins",
			player.Name, newStreak, payout))
		-- Clearing the list also pays the all-tasks token bonus AND the login-streak token reward -- this is the
		-- one place in the game that already knows the streak day, so it's where the streak payout belongs.
		if _G.crateTokensAward then
			pcall(_G.crateTokensAward, player, "dailyAllTasks")
			pcall(_G.crateTokensAward, player, "loginStreak", newStreak)
		end
	end

	push(player)
	task.spawn(save, player)
end

-- =====================  LIFECYCLE  =====================

Players.PlayerAdded:Connect(function(player)
	load(player)
	-- The panel asks for its state once it's built; the client may well be ready before this, so we also push
	-- on a short delay. Cheap, and it removes a race that would show an empty list on join.
	task.delay(2, function() if player.Parent then push(player) end end)
end)

-- The client fires this to (a) ask for state, or (b) report a CLIENT_REPORTED task -- currently only "invite",
-- which the server has no way to observe for itself (see the note by TASKS). Anything not on that allow-list
-- is refused, so this remote can never be used to tick a server-validated task like watering or feeding.
DailyTasksEvent.OnServerEvent:Connect(function(player, action)
	if action ~= nil then
		if CLIENT_REPORTED[action] then
			_G.dailyTaskDone(player, action)
		else
			warn(("[DailyTasks] %s tried to self-report '%s' -- refused (not client-reportable)")
				:format(player.Name, tostring(action)))
		end
		return
	end
	push(player) -- no action = "send me my state"
end)

Players.PlayerRemoving:Connect(function(player)
	save(player)
	state[player] = nil
end)

for _, p in ipairs(Players:GetPlayers()) do task.spawn(load, p) end

print(("[DailyTasks] ready -- %d tasks/day; streak ladder %d..%d coins over %d days"):format(
	#TASKS, STREAK_REWARDS[1], STREAK_REWARDS[#STREAK_REWARDS], #STREAK_REWARDS))
if STUDIO_ALWAYS_SHOW and RunService:IsStudio() then
	warn("[DailyTasks] \xE2\x9A\xA0 STUDIO OVERRIDE ON -- panel always shows here. Live players still wait until join #"
		.. SHOW_FROM_JOIN .. ". Set STUDIO_ALWAYS_SHOW = false to test the real gate.")
end
