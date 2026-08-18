--======================================================================
-- IslandTaskWatcher.client.luau  (LocalScript)  -- CandyRealm
--======================================================================
-- Notices when an island quest finishes, and tells the server so it can pay the crate tokens.
--
-- ===== WHY A WATCHER INSTEAD OF TWELVE EDITS =====
-- Every Candy quest already publishes a boolean when it completes -- `_G.candyQuestComplete`,
-- `_G.bakeryQuestComplete` and so on. That is not a convention I invented for this: QuestJournal has read
-- exactly these flags since it was written, which is the proof they are reliable and that the quests keep
-- them accurate.
--
-- So the token feature needs NO change to any of the twelve `*_AllInOne.client.lua` quest files. Those are
-- thousand-line scripts with their own state machines; editing all twelve to add one line each would be
-- twelve chances to break a working quest for a feature that can be bolted on from outside instead. If a
-- thirteenth quest is added later, it appears here as one row -- and until someone adds that row, nothing
-- breaks, it simply pays nothing.
--
-- ===== EDGE-TRIGGERED, AND THE SERVER STILL DECIDES =====
-- A flag going false -> true fires ONE claim. `seen` stops the poll re-firing on a flag that simply stays
-- true. The server pays once per quest ever regardless, so the worst a bug here can do is send a claim that
-- is politely ignored.
--
-- ===== IT DOES NOT FIRE FOR ALREADY-DONE QUESTS ON JOIN =====
-- The first pass PRIMES `seen` from whatever is already true (a quest completed in a previous session that
-- restored its flag) without claiming, so rejoining does not spray claims for work finished days ago. Those
-- were paid the first time; the server would refuse them anyway, but silence beats a refused round trip.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if _G.__IslandTaskWatcherClient then
	warn("[IslandTask] a SECOND watcher is running -- this one is bailing out.")
	return
end
_G.__IslandTaskWatcherClient = true

-- questId -> the global the quest sets when it finishes. The ids match CrateTokens.ISLAND_TASK exactly; the
-- globals match QuestJournal's ROWS exactly. Both halves have to agree or a quest silently pays nothing, so
-- they are written next to each other here rather than derived.
local QUESTS = {
	{ id = "candy",    flag = "candyQuestComplete"    }, -- island1  Gumball Hunt
	{ id = "cleanup",  flag = "cleanupQuestComplete"  }, -- island9  Reactor Cleanup
	{ id = "cookie",   flag = "cookieQuestComplete"   }, -- island3  Cookie Repair
	{ id = "park",     flag = "parkQuestComplete"     }, -- island13 Ancient Tree
	{ id = "storm",    flag = "stormQuestComplete"    }, -- island5  Taffy Storm
	{ id = "summit",   flag = "summitQuestComplete"   }, -- island8  Summit Bell
	{ id = "jelly",    flag = "jellyQuestComplete"    }, -- island2  Jelly Tower
	{ id = "tunnel",   flag = "tunnelQuestComplete"   }, -- island11 Tunnel Blast
	{ id = "crystal",  flag = "crystalQuestComplete"  }, -- island11 Crystal Mine
	{ id = "campfire", flag = "campfireQuestComplete" }, -- island4  Campfire Freeze
	{ id = "smores",   flag = "smoresQuestComplete"   }, -- island14 Camp S'mores
	{ id = "bakery",   flag = "bakeryQuestComplete"   }, -- island15 The Great Bake-Off
	{ id = "pancake",  flag = "pancakeQuestComplete"  }, -- island18 Wake the Pancake Monster (off-ladder)
	{ id = "tractor",  flag = "tractorQuestComplete"  }, -- island19 Broken Tractor (off-ladder)
}

local ClaimEvent = ReplicatedStorage:WaitForChild("ClaimIslandTaskTokens", 60)
if not ClaimEvent then
	warn("[IslandTask] ClaimIslandTaskTokens never arrived -- island quest tokens inactive")
	return
end

local seen = {}   -- [questId] = true once we have observed its flag true

-- PRIME. Anything already true at startup was finished before this session, so record it WITHOUT claiming.
for _, q in ipairs(QUESTS) do
	if _G[q.flag] == true then seen[q.id] = true end
end

task.spawn(function()
	while true do
		task.wait(1)   -- one second is imperceptible against a quest you just finished, and costs nothing
		for _, q in ipairs(QUESTS) do
			if not seen[q.id] and _G[q.flag] == true then
				seen[q.id] = true
				pcall(function() ClaimEvent:FireServer(q.id) end)
				print(("[IslandTask] '%s' completed -> claiming crate tokens"):format(q.id))
			end
		end
	end
end)

print(("[IslandTask] watcher ready -- %d island quests watched via their _G.<name>QuestComplete flags "
	.. "(no quest script was modified)"):format(#QUESTS))
