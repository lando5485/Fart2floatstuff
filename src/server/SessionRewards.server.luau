--======================================================================
-- SessionRewards.server.luau   (ServerScriptService)
--======================================================================
-- The TIMED tab of the Rewards hub: six playtime milestones on THIS session -- 5, 10, 20, 30, 45 and 60
-- minutes. Stay in the server, cross a milestone, claim it.
--
-- SERVER-AUTHORITATIVE, like every other faucet in this game. The client draws a countdown and a CLAIM
-- button, but it never decides anything: it asks, and this file checks the clock it kept itself.
--
-- ===== SESSION, NOT LIFETIME -- AND WHY THAT NEEDS NO DATASTORE =====
-- The track resets when you leave. That is the whole design: it rewards sitting down to play today, not a
-- total accumulated over months, so there is nothing worth persisting and no save to corrupt. Leaving at 55
-- minutes and rejoining starts you at zero, which is the honest reading of "session".
--
-- ===== "ACTIVELY PLAYING" MEANS CONNECTED =====
-- Time accrues while the player is in the server, full stop. No idle detection, deliberately:
--   * this game already ships an AFK earner (AFKTokenFarm) and an idle-kick suppressor (AntiIdle), so
--     earning while parked is an accepted part of its design rather than something to police here;
--   * every "are they really playing" test worth having needs the CLIENT to report input, which a client can
--     trivially fake -- so it would add a spoofable dependency and buy nothing.
-- The real cap is that a session is a session: the ladder tops out at an hour and then stops paying.
--
-- ===== THE PAYOUT TABLE IS THE ONLY THING TO EDIT =====
-- BASE below is the whole feature -- one pass of it. `kind` picks the faucet, and the client renders `label`/`icon`
-- straight from what the server sends -- so a card can never advertise a reward this file does not actually
-- pay. Add a rung, change an amount, reorder: the UI follows without a client edit.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:FindFirstChild("SessionRewardEvent")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "SessionRewardEvent"
	remote.Parent = ReplicatedStorage
end

--======================================================================
-- THE LADDER
--======================================================================
-- `kind` is the faucet, and only two are wired: "coins" (the leaderstat every other reward writes) and
-- "tokens" (_G.crateTokensAward, the shared crate-token faucet).
--
-- THE DESIGN BRIEF ASKED FOR food / gas-boost / crate rungs. Those are NOT here, and that is on purpose
-- rather than an omission: granting food means writing CurrentPower, which is the one number the whole
-- progression ladder is tuned around (see CLAUDE.md -- a free meal that clears a gap silently deletes a
-- rung), a gas boost has no per-player server hook yet, and handing out a crate OPEN needs SkinCrateService
-- to expose one. Each is a real piece of work with a real way to break the economy.
--
-- So every rung pays something this file can actually deliver, and the card shows exactly that. The 45 and
-- 60 minute rungs pay enough tokens to BUY the crate the brief wanted, which is the same destination through
-- the front door. When those faucets exist, change `kind` here and the cards update themselves.
-- ALL SIX RUNGS PAY TOKENS. They used to be a mix -- three coin rungs and three token ones -- which made the
-- track read as two different rewards interleaved, and the coin halves had stopped meaning anything: 250 coins
-- at the five-minute mark is a rounding error next to a 1,280-coin first meal, let alone the six figures a
-- player is carrying by the time an hour of session time has passed. Tokens do not inflate that way, because
-- the only thing that spends them is crates.
--
-- THE LADDER IS PRICED OFF THE CRATES, because crates are the only thing tokens buy. The cheapest is 75
-- (Starter), then 100 (Pet Level), 160, 200, 250, and the big two at 600 and 1200.
--
-- 10, 30, 60, 120, 250, 500 -- each rung roughly doubles the last, so the track accelerates instead of
-- paying a flat drip, and the two long rungs are the ones actually worth sitting for. The cumulative totals
-- are where it was tuned:
--     5 min   10      10 min   40      20 min  100
--     30 min 220      45 min  470      60 min  970
-- A first crate lands at 20 minutes (100 = Pet Level Crate; 75 was passed just before), a 200 crate by the
-- half hour, and a full hour pays 970 -- a 600 plus a 250, or just short of the 1200 top crate.
--
-- For scale: the daily login streak pays {5,8,10,12,15,20,30}, i.e. 100 tokens for a WEEK. This pays that
-- much in twenty minutes. That gap is intentional -- the streak rewards showing up, this rewards staying --
-- but it does mean session time is now the main token faucet in the game, ahead of both the streak and the
-- island tasks, so it is the first number to revisit if crates start feeling cheap.
--
-- ⚠ UNCAPPED. `sessionReward` is not in CrateTokens.DAILY_CAP_FLAT or DAILY_CAP_UNITS, so dailyCapFor()
-- returns nil and none of these grants are limited. It is self-limiting WITHIN a session (each rung pays
-- once, and progress resets to zero on leave, so a rejoin has to replay the whole hour) -- but nothing stops
-- an idle player banking 970 an hour, and this place already ships an AFK token farm. Add a `sessionReward`
-- entry to DAILY_CAP_FLAT to put a ceiling on it.
--
-- `kind = "coins"` is still wired in grant() below. Nothing uses it now; it is left there so a coin rung is a
-- one-line change to this table rather than a code change.
-- One glyph for all six rungs. Deliberately the literal ticket rather than a require of Shared.CrateTokens:
-- adding a WaitForChild to a server boot path is exactly how a service ends up yielding forever if a shared
-- module is ever left out of the Rojo project, and this file needs the one character and nothing else. It
-- must stay equal to CrateTokens.ICON -- the client falls back to that same constant for a rung with no icon.
-- (The 60-minute rung used to be a gift box and the coin rungs money bags: six cards, three icons, one
-- currency. Now all six match.)
local TOKEN_ICON = "\xF0\x9F\x8E\x9F"

local BASE = {
	{ sec =  5 * 60, kind = "tokens", amount =  10, icon = TOKEN_ICON, label = "10 Tickets"  },
	{ sec = 10 * 60, kind = "tokens", amount =  30, icon = TOKEN_ICON, label = "30 Tickets"  },
	{ sec = 20 * 60, kind = "tokens", amount =  60, icon = TOKEN_ICON, label = "60 Tickets"  },
	{ sec = 30 * 60, kind = "tokens", amount = 120, icon = TOKEN_ICON, label = "120 Tickets" },
	{ sec = 45 * 60, kind = "tokens", amount = 250, icon = TOKEN_ICON, label = "250 Tickets" },
	{ sec = 60 * 60, kind = "tokens", amount = 500, icon = TOKEN_ICON, label = "500 Tickets" },
}

--======================================================================
-- PASSES: the track does not end at an hour, it starts again bigger
--======================================================================
-- BASE above is ONE PASS. When all six of its rungs are claimed the track rolls over: the same six rungs come
-- back an hour further out and paying PASS_GROWTH times more. So an hour is a lap, not a finish line, and a
-- four-hour session keeps earning instead of going flat at 60 minutes.
--
--   pass 0    5/10/20/30/45/60 min      10,  30,  60, 120, 250,  500
--   pass 1   65/70/80/90/105/120 min    15,  45,  90, 180, 375,  750
--   pass 2  125/130/140/150/165/180     25,  70, 135, 270, 565, 1125
--
-- THE PASS ADVANCES ON THE SIXTH CLAIM, NOT ON THE CLOCK. Rolling over purely on elapsed time would step past
-- a rung a player had not collected yet -- open the panel at 61 minutes and the 60-rung would already be gone.
-- Tying it to the claim means nothing is ever skipped: a player who ignores the tab for three hours finds pass
-- 0 waiting, claims it, and pass 1's rungs are already due, so they collect the backlog a press at a time.
--
-- Rung times stay ABSOLUTE session seconds (pass 1's first rung really is at 65 minutes), so the client's
-- countdown keeps subtracting from the same clock and needed no new arithmetic to understand a pass.
local PASS_SEC    = 60 * 60   -- one lap; equal to the last rung's offset, so passes butt up without a gap
local PASS_GROWTH = 1.5       -- each lap pays half again as much as the one before

-- Rounded to the nearest 5 so a lap never advertises "562 Tickets". Growth compounds, so this is where a
-- runaway would show first: pass 5 (six hours in) pays 3,795 on its last rung. That is a lot of tokens, but it
-- costs six hours of real session time to reach and every rung before it had to be claimed by hand.
local function passAmount(baseAmount, pass)
	local v = baseAmount * (PASS_GROWTH ^ pass)
	return math.max(1, math.floor(v / 5 + 0.5) * 5)
end

-- The six rungs as they stand for a given pass. The ONLY place a pass's numbers are worked out, so the
-- snapshot the client draws and the amount the claim pays cannot disagree.
local function rungsFor(pass)
	local out = {}
	for i, m in ipairs(BASE) do
		local amount = passAmount(m.amount, pass)
		out[i] = {
			sec    = pass * PASS_SEC + m.sec,
			kind   = m.kind,
			amount = amount,
			icon   = m.icon,
			label  = amount .. " Tickets",
		}
	end
	return out
end

--======================================================================
-- STATE
--======================================================================
-- joinedAt is os.clock() at join. Elapsed is derived on every read rather than ticked by a loop: a counter
-- incremented on a heartbeat drifts, can double-count if the loop is ever restarted, and has to be defended
-- against the player leaving mid-tick. Subtracting two clock reads cannot do any of those things.
local joinedAt = {}   -- [player] = os.clock() at join
local claimed  = {}   -- [player] = { [index] = true }  -- for the CURRENT pass only; cleared on rollover
local passNo   = {}   -- [player] = which lap they are on (0-based)

local function elapsed(player)
	local t0 = joinedAt[player]
	if not t0 then return 0 end
	return math.max(0, math.floor(os.clock() - t0))
end

local function snapshot(player)
	local c    = claimed[player] or {}
	local pass = passNo[player] or 0
	-- The client is sent the LADDER ITSELF, not just progress against it. One source of truth: a card cannot
	-- advertise an amount this file will not pay, because the card is drawn from what rungsFor() returns.
	local rungs = {}
	for i, m in ipairs(rungsFor(pass)) do
		rungs[i] = { sec = m.sec, icon = m.icon, label = m.label, claimed = c[i] == true }
	end
	-- passStart lets the client's progress bar measure THIS lap rather than the whole session -- without it the
	-- bar sits pinned near full from pass 1 onwards, because `now` keeps growing and the last rung moves with it.
	return {
		sessionSec = elapsed(player), rungs = rungs, total = #BASE,
		pass = pass, passStart = pass * PASS_SEC,
	}
end

local function push(player)
	if not player or not player.Parent then return end
	pcall(function() remote:FireClient(player, "state", snapshot(player)) end)
end

--======================================================================
-- GRANTING
--======================================================================
local function grant(player, m)
	if m.kind == "coins" then
		local ls = player:FindFirstChild("leaderstats")
		local coins = ls and ls:FindFirstChild("Coins")
		if not coins then return 0 end
		coins.Value = coins.Value + m.amount
		return m.amount
	elseif m.kind == "tokens" then
		-- The shared faucet, with an explicit override amount -- the same call DailyStreak's claim uses, so
		-- session rewards land in the same ledger and the same on-screen balance as every other token grant.
		if not _G.crateTokensAward then return 0 end
		local ok, got = pcall(_G.crateTokensAward, player, "sessionReward", nil, m.amount)
		return (ok and tonumber(got)) or 0
	end
	return 0
end

--======================================================================
-- CLAIM
--======================================================================
remote.OnServerEvent:Connect(function(player, action, index)
	if action ~= "claim" then return end
	index = tonumber(index)
	if not index then return end

	local pass = passNo[player] or 0
	local m = rungsFor(pass)[index]
	if not m then return end

	local c = claimed[player]
	if not c then c = {}; claimed[player] = c end

	if c[index] then
		pcall(function() remote:FireClient(player, "result", false, 0, "Already claimed.") end)
		return
	end
	-- THE CLOCK THIS FILE KEPT, never a number the client sent. The client draws a countdown from its own
	-- copy of sessionSec, which is fine for a countdown and worthless as a permission.
	if elapsed(player) < m.sec then
		pcall(function() remote:FireClient(player, "result", false, 0, "Not unlocked yet -- keep playing!") end)
		push(player)
		return
	end

	-- Marked BEFORE the grant. If a grant ever throws, the worst case is a reward that did not pay; marking
	-- after would make the worst case a rung that can be claimed twice.
	c[index] = true
	local got = grant(player, m)
	if got <= 0 then
		c[index] = nil -- nothing was actually paid: let them try again rather than eating the rung
		pcall(function() remote:FireClient(player, "result", false, 0, "Couldn't pay that out -- try again.") end)
		push(player)
		return
	end

	print(("[SessionRewards] %s claimed pass %d rung %d (%d min) -> %s"):format(
		player.Name, pass, index, math.floor(m.sec / 60), m.label))
	pcall(function() remote:FireClient(player, "result", true, got, "Claimed  " .. m.label .. "!") end)

	-- ROLLOVER. Once every rung on this lap is collected the next lap opens: same six cards, an hour further
	-- out, paying more. Checked after the grant so a failed payout cannot advance the pass.
	local all = true
	for i = 1, #BASE do if not c[i] then all = false; break end end
	if all then
		passNo[player] = pass + 1
		claimed[player] = {}
		print(("[SessionRewards] %s finished pass %d -- pass %d now open (rungs %d..%d min)"):format(
			player.Name, pass, pass + 1,
			math.floor(((pass + 1) * PASS_SEC + BASE[1].sec) / 60),
			math.floor(((pass + 1) * PASS_SEC + BASE[#BASE].sec) / 60)))
		pcall(function()
			remote:FireClient(player, "result", true, 0,
				"Pass " .. (pass + 1) .. " unlocked -- bigger rewards!")
		end)
	end
	push(player)
end)

--======================================================================
-- LIFECYCLE
--======================================================================
local function onJoin(player)
	joinedAt[player] = os.clock()
	claimed[player]  = {}
	passNo[player]   = 0
	-- A few pushes over the first seconds rather than one: the client script may not have built its panel (or
	-- even run) when the first would land, and a rewards tab that opens empty until the next 20s tick reads
	-- as broken.
	task.spawn(function()
		for _, d in ipairs({ 1, 3, 8 }) do
			task.wait(d)
			if player.Parent then push(player) end
		end
	end)
end

Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

Players.PlayerRemoving:Connect(function(player)
	joinedAt[player] = nil
	claimed[player]  = nil
end)

-- ONE TIMER FOR THE WHOLE SERVER. 20s is chosen against what it drives: the client runs its own countdown
-- between pushes, so this only has to correct drift and announce a rung becoming claimable -- and a rung the
-- player can see counting down does not need to arrive within a frame of unlocking.
task.spawn(function()
	while true do
		task.wait(20)
		for _, p in ipairs(Players:GetPlayers()) do push(p) end
	end
end)

print(("[SessionRewards] ready -- %d rungs per pass (5..60 min), endless passes at x%.2f each, "
	.. "session-scoped, server-timed"):format(#BASE, PASS_GROWTH))
