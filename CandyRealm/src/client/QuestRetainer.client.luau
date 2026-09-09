--======================================================================
-- QuestRetainer.client.luau  (StarterPlayerScripts)  -- CandyRealm
--======================================================================
-- MAKES SURE ALL 14 ISLAND TASKS ACTUALLY BUILD, AND FORCES THEIR WORLD TO RENDER.
--
-- ===== THE FAILURE THIS EXISTS FOR =====
-- Every quest is a client script that, at join, hunts Workspace for its hand-placed markers
-- (the bell, the campfire, the crystals, the axe) and then builds its props on top of them.
-- Each hunt is a `pollFor(fn, 20..120)` -- poll every half second, then GIVE UP.
--
-- With StreamingEnabled that deadline is a coin flip. A quest on island4 boots while you are
-- standing on island1, forty thousand studs below. If island4's parts have not replicated
-- inside the quest's 45 seconds, the poll expires, the quest warns "inactive" and RETURNS --
-- and it is dead for the rest of the session. Fly up there ten minutes later and the island
-- is bare: no bell, no props, no prompt, no quest. Nothing retries, because nothing is left
-- running to retry. That is the "some island tasks just aren't there" bug, and it is a race,
-- so it lands on a different island every session and looks random.
--
-- The realm's own boot log calls the same shot from the other side: StreamingMinRadius is
-- NotScriptable and still at the 64-stud default, so the guaranteed-resident radius is tiny
-- and everything outside it is at the mercy of timing.
--
-- ===== WHAT THIS DOES =====
--   1. FORCES THE RENDER. RequestStreamAroundAsync on every task island, at boot and again
--      before any re-run. That is the one client-side call that says "stream this region in
--      NOW", and it is what turns a quest's marker hunt from a race into a lookup.
--   2. WATCHES. Each quest sets `_G.questBuilt_<id> = true` at its ready print (one line per
--      quest, added at the same time as this file). No flag = that quest did not finish.
--   3. RE-RUNS what did not build. The quest's LocalScript is cloned back into PlayerScripts,
--      which re-runs it from the top with the island now resident.
--
-- ===== WHY THE RE-RUN CANNOT DUPLICATE ANYTHING =====
-- This is the whole safety argument, so it is written down rather than assumed. A quest is
-- re-run ONLY when `_G.questBuilt_<id>` is false -- i.e. it provably never reached the end of
-- its build. It bailed on a missing marker, before it made props. There is nothing on the
-- island to duplicate; that is exactly why we are re-running it. A quest that DID build sets
-- the flag and is never touched, no matter how long it took to get there.
--
-- Belt and braces on top of that: MAX_ATTEMPTS caps it, one quest is re-run at a time, and a
-- re-run that still does not set the flag is reported rather than retried forever.
--
-- ===== IT NEVER BLAMES THE WORLD FOR YOUR OWN MISSING MODEL =====
-- A task whose island model does not exist in Workspace at all (island2 / Jelly Tower, at the
-- time of writing) is reported as MISSING ISLAND and NOT re-run. Re-running a quest whose
-- island was never built just burns a slot and prints the same warning again. That one is a
-- Studio job -- name a model `island2` -- and the report says so in as many words.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")

local player      = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")

if _G.__QuestRetainer then
	warn("[Retainer] a SECOND retainer is running -- this one is bailing out.")
	return
end
_G.__QuestRetainer = true

-- ============================================================================
-- CONFIG
-- ============================================================================
local FIRST_CHECK   = 55    -- seconds after join before the first audit. Must be LONGER than the
                            -- longest pollFor in any quest (Summit's 120s bell hunt is the outlier;
                            -- see LONG_QUESTS) or we would re-run a quest that was still working.
local RECHECK_EVERY = 45    -- seconds between later audits
local MAX_ATTEMPTS  = 2     -- re-runs per quest per session
local SETTLE        = 12    -- seconds given to a re-run before it is judged

-- Quests with a pollFor longer than FIRST_CHECK get their own, later deadline. Summit polls the
-- whole Workspace for the bell for up to 120s; judging it at 55s would re-run a live quest.
local LONG_QUESTS = { summit = 150 }

-- id -> { flag published at the quest's ready print, the LocalScript's name, the island model }
-- The ids match IslandTaskWatcher's QUESTS table; the island column is the MODEL name in Workspace,
-- which is what RequestStreamAroundAsync needs a position for.
--
-- THE ISLAND COLUMN HERE HAS ALWAYS BEEN THE CORRECT ONE. IslandTaskWatcher's comments, QuestJournal's
-- rows and CrateTokens' ladder all used to read `summit` as island8 and `crystal` as island11, which is
-- backwards -- SummitBellQuest is ISLAND_NAME = "island4", CrystalMineQuest is "island8". This file got
-- it right, and getting it right is load-bearing here in a way it is not there: an id with the wrong
-- island force-streams the wrong region and then reports MISSING ISLAND for one that exists. The other
-- three are corrected now, so all four agree.
--
-- island4 appears TWICE on purpose -- Frostbell Peak hosts both the campfire and the summit bell.
local QUESTS = {
	{ id = "candy",    script = "CandyGumballQuest_AllInOne",       island = "island1"  },
	{ id = "cleanup",  script = "RadioactiveCleanupQuest_AllInOne", island = "island9"  },
	{ id = "cookie",   script = "CookieRepairQuest_AllInOne",       island = "island3"  },
	{ id = "park",     script = "AncientTreeQuest_AllInOne",        island = "island13" },
	{ id = "storm",    script = "TaffyStormQuest_AllInOne",         island = "island5"  },
	{ id = "crystal",  script = "CrystalMineQuest_AllInOne",        island = "island8"  },
	-- jelly (island2) REMOVED: the island was never built and the quest script is retired --
	-- keeping the row here only bought a MISSING ISLAND warning every boot
	{ id = "tunnel",   script = "TunnelBlastQuest_AllInOne",        island = "island11" },
	{ id = "summit",   script = "SummitBellQuest_AllInOne",         island = "island4"  },
	{ id = "campfire", script = "CampfireFreezeQuest_AllInOne",     island = "island4"  },
	{ id = "smores",   script = "CampSmoresQuest_AllInOne",         island = "island14" },
	{ id = "bakery",   script = "BakeryQuest_AllInOne",             island = "island15" },
	{ id = "pancake",  script = "PancakeMonsterQuest_AllInOne",     island = "island18" },
	{ id = "tractor",  script = "BrokenTractorQuest_AllInOne",      island = "island19" },
	{ id = "candymine", script = "CandyMineExplosionQuest_AllInOne", island = "island16" },
}

-- ============================================================================
-- FORCE THE RENDER
-- ============================================================================
-- An island Model with StreamingEnabled replicates as an EMPTY MODEL at distance -- it exists,
-- GetPivot() returns the origin, and every marker inside it reads as missing. So the position
-- comes from IslandOrder (the shared solved ladder, which the client can read without the parts)
-- and falls back to the model's own pivot only for the off-ladder islands.
local islandPos = {}
do
	local ok, IslandOrder = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared", 20):WaitForChild("IslandOrder", 20))
	end)
	if ok and type(IslandOrder) == "table" and IslandOrder.SLOT_TO_ISLAND and IslandOrder.SLOT_POS then
		for slot, num in ipairs(IslandOrder.SLOT_TO_ISLAND) do
			local p = IslandOrder.SLOT_POS[slot]
			if p then islandPos["island" .. num] = (typeof(p) == "Vector3") and p or Vector3.new(p[1], p[2], p[3]) end
		end
	else
		warn("[Retainer] IslandOrder unreadable -- falling back to each model's own pivot for streaming")
	end
end

-- Where to ask the engine to stream. IslandOrder first (correct even when the model is a hollow
-- shell), then the model's pivot, then nothing -- an island with neither is simply skipped.
local function islandTarget(name)
	local p = islandPos[name]
	if p then return p end
	local m = Workspace:FindFirstChild(name)
	if m then
		local piv = m:GetPivot().Position
		if piv.Magnitude > 1 then return piv end   -- (0,0,0) means "hollow model", not a real spot
	end
	return nil
end

-- THE ACTUAL FORCE. RequestStreamAroundAsync is the only client-side call that pulls a region in
-- on demand; it is a yield, so each one is spawned rather than run in series (fourteen serial
-- 3-second timeouts would take most of a minute).
local function forceStream(name)
	local pos = islandTarget(name)
	if not pos then return false end
	task.spawn(function()
		pcall(function() player:RequestStreamAroundAsync(pos, 4) end)
	end)
	return true
end

local function forceStreamAll()
	local n = 0
	local done = {}
	for _, q in ipairs(QUESTS) do
		if not done[q.island] then
			done[q.island] = true
			if forceStream(q.island) then n += 1 end
		end
	end
	return n
end

-- ============================================================================
-- AUDIT + RE-RUN
-- ============================================================================
local attempts, reported = {}, {}
local startedAt = os.clock()

local function built(q) return _G["questBuilt_" .. q.id] == true end
local function islandExists(q) return Workspace:FindFirstChild(q.island) ~= nil end
local function due(q) return (os.clock() - startedAt) >= (LONG_QUESTS[q.id] or FIRST_CHECK) end

-- Re-run by cloning the LocalScript back into PlayerScripts. A LocalScript runs when it is
-- parented somewhere that runs client code, so a clone restarts the quest from line 1 -- with
-- the island now resident, its marker hunt is a lookup instead of a race.
local function rerun(q)
	local src = playerScripts:FindFirstChild(q.script)
	if not src or not src:IsA("LuaSourceContainer") then
		warn(("[Retainer] '%s' did not build and its script '%s' is not in PlayerScripts -- cannot re-run")
			:format(q.id, q.script))
		return false
	end
	attempts[q.id] = (attempts[q.id] or 0) + 1
	forceStream(q.island)
	task.wait(1.5)   -- let the stream request land before the clone starts hunting

	local clone = src:Clone()
	clone.Name = q.script .. "_Retry" .. attempts[q.id]
	clone.Disabled = false
	clone.Parent = playerScripts
	warn(("[Retainer] '%s' never built (attempt %d/%d) -- island %s force-streamed, quest re-run as '%s'")
		:format(q.id, attempts[q.id], MAX_ATTEMPTS, q.island, clone.Name))
	return true
end

local function audit()
	local okCount, pending, missingIsland, failed = 0, {}, {}, {}

	for _, q in ipairs(QUESTS) do
		if built(q) then
			okCount += 1
		elseif not due(q) then
			pending[#pending + 1] = q.id            -- still inside its own poll window; leave it alone
		elseif not islandExists(q) then
			missingIsland[#missingIsland + 1] = ("%s (%s)"):format(q.id, q.island)
		elseif (attempts[q.id] or 0) < MAX_ATTEMPTS then
			if rerun(q) then task.wait(SETTLE) end
		else
			failed[#failed + 1] = ("%s (%s)"):format(q.id, q.island)
		end
	end

	-- ---- the report. Printed on the first audit and whenever the picture changes, not every
	-- pass -- a line every 45 seconds that always says the same thing gets tuned out.
	local key = table.concat({ okCount, #pending, #missingIsland, #failed }, "|")
	if reported[key] then return okCount end
	reported[key] = true

	print(("[Retainer] %d/%d island tasks built%s"):format(okCount, #QUESTS,
		(#pending > 0) and (" -- still building: " .. table.concat(pending, ", ")) or ""))
	if #missingIsland > 0 then
		warn(("[Retainer] NO ISLAND MODEL for: %s. These tasks CANNOT run and are not being re-run "
			.. "-- the model does not exist in Workspace. Fix in Studio: name the island's Model "
			.. "'island<N>' exactly (this is the same thing IslandLayout warns about as an empty tower slot).")
			:format(table.concat(missingIsland, ", ")))
	end
	if #failed > 0 then
		warn(("[Retainer] STILL NOT BUILT after %d re-run(s): %s. The island streamed in and the quest "
			.. "ran again and still could not find its markers -- so this is a missing/renamed marker "
			.. "in Studio, not a streaming race. Check that quest's own warn line for which name it wanted.")
			:format(MAX_ATTEMPTS, table.concat(failed, ", ")))
	end
	return okCount
end

-- ============================================================================
-- GO
-- ============================================================================
-- Stream first and keep streaming: the boot pass is what gives the quests' own polls a fighting
-- chance, so most sessions never need a single re-run. Re-running is the fallback, not the plan.
task.spawn(function()
	local n = forceStreamAll()
	print(("[Retainer] ready -- force-streamed %d task island(s); auditing %d island task(s) at %ds, "
		.. "then every %ds. Unbuilt quests are re-run (max %d), built ones are never touched.")
		:format(n, #QUESTS, FIRST_CHECK, RECHECK_EVERY, MAX_ATTEMPTS))

	-- a second sweep while the player is still on the spawn island: RequestStreamAroundAsync is a
	-- request, not a guarantee, and the engine drops some of them under a join-time load spike
	task.wait(12)
	forceStreamAll()

	while true do
		task.wait(RECHECK_EVERY)
		if audit() >= #QUESTS then
			print("[Retainer] all island tasks are built -- retainer going quiet.")
			return
		end
	end
end)

-- Re-force the island you are actually standing on, every time you land somewhere new. This is
-- the "forces the render" half doing its day job: whatever the boot sweep missed, arriving fixes.
task.spawn(function()
	local last
	while true do
		task.wait(3)
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local nearest, bestD
			for _, q in ipairs(QUESTS) do
				local p = islandTarget(q.island)
				if p then
					local d = (p - hrp.Position).Magnitude
					if not bestD or d < bestD then nearest, bestD = q.island, d end
				end
			end
			if nearest and bestD and bestD < 900 and nearest ~= last then
				last = nearest
				forceStream(nearest)
			end
		end
	end
end)
