--======================================================================
-- DailyStreak.server.lua   (ServerScriptService)
--======================================================================
-- RECOVERED, NOT REWRITTEN. This script existed only baked into the place file -- no repo source, absent
-- from default.project.json, flagged NOT-IN-MANIFEST by SecurityWatchdog every boot. It is reproduced here
-- VERBATIM so that deleting the baked-in copy in Studio is safe: the claim rules, the ladder and the grant
-- are exactly what has been running, byte for byte. The client restyle changed no server behaviour.
--
-- If you edit anything below, remember the client (DailyStreak.client.luau) reads these exact state field
-- names: canClaim, streak, day, ladder, ladderLen, claimedToday, todayReward, nextReward.
--======================================================================

-- DailyStreak.server.lua  (Script)  -- the 🔥 Daily Streak: log in, claim, keep the run alive.
--
-- ONE login-based streak claim, once per UTC day. This is the merged "Daily Login / Daily Streak" the Rewards
-- menu shows: showing up on consecutive days walks a 7-day token ladder ({5,8,10,12,15,20,30}); after day 7 the
-- ladder LOOPS (day 8 = day 1 again) while the underlying streak keeps counting, so a long run keeps paying the
-- day-7 peak without an unbounded ladder.
--
-- SERVER-AUTHORITATIVE: the client sends only "claim". The server decides whether a claim is allowed today,
-- advances/resets the streak, and pays TOKENS through the shared faucet (_G.crateTokensAward). A client that
-- fakes a claim gets nothing -- a second claim the same day is rejected here.

local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local CrateTokens = require(Shared:WaitForChild("CrateTokens"))

local LADDER_LEN = #CrateTokens.LOGIN_STREAK -- 7

local store = DataStoreService:GetDataStore("DailyStreak_v1")

-- client -> server: fire "claim".  server -> client: fire "state", <stateTable> | "result", ok, amount, msg
local remote = ReplicatedStorage:FindFirstChild("DailyStreakEvent")
if not remote then
	remote = Instance.new("RemoteEvent"); remote.Name = "DailyStreakEvent"; remote.Parent = ReplicatedStorage
end

-- Integer UTC day number: "was the last claim yesterday?" is `last == today - 1`, with none of the calendar
-- arithmetic a YYYY-MM-DD string would need to get month/year boundaries right. Matches DailyTasks' day maths.
local function dayNumber() return math.floor(os.time() / 86400) end

local data = {} -- [player] = { streak = n, lastDay = dayNumber }

-- The crate day 7 spins. The rarest one in SkinCrates (1,200 tokens, the top of the price list) -- if a rarer
-- crate is ever added, this is the single line that moves the reward to it.
local DAY7_CRATE = "Mythic"

-- The 1-7 ladder position for a given streak length (loops after 7).
local function ladderDay(streak)
	local s = math.max(1, math.floor(streak or 1))
	return ((s - 1) % LADDER_LEN) + 1
end

-- Resolve the live streak for TODAY without mutating: a claim today keeps it; a claim yesterday keeps it (ready
-- to advance); anything older is a broken run (next claim starts a fresh day 1).
local function resolve(d)
	local today = dayNumber()
	local last  = tonumber(d.lastDay) or 0
	local streak = tonumber(d.streak) or 0
	if last == today then
		return streak, false            -- already claimed today
	elseif last == today - 1 then
		return streak, true             -- run alive, claim advances it to streak+1
	else
		return 0, true                  -- missed a day (or first ever) -> next claim is day 1
	end
end

local function buildState(player)
	local d = data[player] or { streak = 0, lastDay = 0 }
	local curStreak, canClaim = resolve(d)
	-- If they can still claim today, the NEXT streak day is curStreak+1; if already claimed, it's the current one.
	local shownStreak = canClaim and (curStreak + 1) or curStreak
	local shownDay    = ladderDay(shownStreak)
	return {
		streak      = shownStreak,                                  -- the streak number to show big
		day         = shownDay,                                     -- 1-7 position on the ladder
		ladderLen   = LADDER_LEN,
		ladder      = CrateTokens.LOGIN_STREAK,                     -- the whole {5,8,...,30} ladder for the row of day cards
		canClaim    = canClaim,                                     -- is the claim button live right now?
		claimedToday= not canClaim,                                 -- show the claimed/checkmark state
		todayReward = CrateTokens.loginStreakReward(shownDay),      -- tokens the claim button pays right now
		nextReward  = CrateTokens.loginStreakReward(ladderDay(shownStreak + 1)), -- what tomorrow pays (the FOMO number)
	}
end

local function pushState(player)
	pcall(function() remote:FireClient(player, "state", buildState(player)) end)
end

local function load(player)
	local ok, v = pcall(function() return store:GetAsync(tostring(player.UserId)) end)
	if ok and type(v) == "table" then
		data[player] = { streak = tonumber(v.streak) or 0, lastDay = tonumber(v.lastDay) or 0 }
	else
		-- store blip -> start fresh rather than block the claim (worst case they re-earn a small day-1 reward).
		data[player] = { streak = 0, lastDay = 0 }
	end
end

local function save(player)
	local d = data[player]; if not d then return end
	pcall(function() store:SetAsync(tostring(player.UserId), { streak = d.streak, lastDay = d.lastDay }) end)
end

remote.OnServerEvent:Connect(function(player, action)
	if action ~= "claim" then return end
	local d = data[player]; if not d then return end

	local curStreak, canClaim = resolve(d)
	if not canClaim then
		pcall(function() remote:FireClient(player, "result", false, 0, "Come back tomorrow to keep your streak!") end)
		return
	end

	-- Advance (or restart) the streak, then grant the ladder reward for the new day.
	local newStreak = curStreak + 1
	local day       = ladderDay(newStreak)
	-- ===== DAY 7 IS A CRATE, NOT A NUMBER =====
	-- The last rung pays one free spin of the MYTHIC CRATE -- the rarest thing in the game and, at 1,200
	-- tokens, worth roughly six of the 200-token payout it replaces. That is the point: the week should end on
	-- a prize you watch arrive, not the same counter ticking up a seventh time. The card has always shown a
	-- rainbow "?" and read MYSTERY / SPECIAL REWARD; until now that mystery resolved into more tokens.
	--
	-- The spin is server-rolled and banked before the reveal is pushed, so what the reel lands on IS what was
	-- awarded -- the client is being shown a result, never asked for one.
	local granted, isCrate = 0, false
	if day >= LADDER_LEN then
		if not _G.skinCrateFreeSpin then
			-- SkinCrateService still loading. Same rule as the token faucet below: do NOT consume the day.
			pcall(function() remote:FireClient(player, "result", false, 0, "One moment -- try again!") end)
			return
		end
		local res = _G.skinCrateFreeSpin(player, DAY7_CRATE)
		if not (type(res) == "table" and res.ok) then
			pcall(function() remote:FireClient(player, "result", false, 0, "Couldn't open your crate -- try again!") end)
			return
		end
		granted, isCrate = 1, true
	else
		-- The faucet reads the amount from CrateTokens.loginStreakReward(day), so the number can never disagree
		-- with what the UI showed. Granting is the ONLY authoritative token write.
		granted = (_G.crateTokensAward and _G.crateTokensAward(player, "loginStreak", day)) or 0
		if granted <= 0 then
			-- faucet not ready (SkinCrateService still loading) -> don't consume the day; let them retry.
			pcall(function() remote:FireClient(player, "result", false, 0, "One moment -- try again!") end)
			return
		end
	end

	d.streak  = newStreak
	d.lastDay = dayNumber()
	task.spawn(save, player)

	if isCrate then
		print(("[DailyStreak] %s claimed day %d (streak %d) -> FREE %s SPIN"):format(
			player.Name, day, newStreak, DAY7_CRATE))
		pcall(function() remote:FireClient(player, "result", true, 0, "Day 7!  Free Mythic Crate spin!") end)
	else
		print(("[DailyStreak] %s claimed day %d (streak %d) -> +%d Tokens"):format(player.Name, day, newStreak, granted))
		pcall(function() remote:FireClient(player, "result", true, granted, ("Day %d streak!  +%d Tickets"):format(day, granted)) end)
	end
	pushState(player)
end)

-- Let other systems (RewardsHub badge) ask "is a claim waiting?" without a remote round-trip.
_G.dailyStreakPending = function(player)
	local d = data[player]; if not d then return false end
	local _, canClaim = resolve(d)
	return canClaim == true
end

local function onAdded(player)
	load(player)
	task.spawn(function()
		task.wait(3) -- let the client build its UI + let SkinCrateService register the token faucet
		pushState(player)
	end)
end

Players.PlayerAdded:Connect(onAdded)
for _, p in ipairs(Players:GetPlayers()) do onAdded(p) end
Players.PlayerRemoving:Connect(function(p) save(p); data[p] = nil end)

print("[DailyStreak] ready -- one login-streak claim per day, tokens on the {5,8,10,12,15,20,30} ladder")
