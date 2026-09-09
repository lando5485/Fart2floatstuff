--!nonstrict
-- CrateTokens (ReplicatedStorage/Shared/CrateTokens)
-- ============================================================================================================
-- SINGLE SOURCE OF TRUTH for the COSMETIC currency: Crate Tokens.
--
-- TWO CURRENCIES, kept strictly apart:
--   * Food Coins   (leaderstats.Coins)       -- earned by playing. Buys food, gut upgrades, progression.
--                                               MUST NEVER buy a skin crate.
--   * Crate Tokens (leaderstats.CrateTokens) -- earned from quests/realms/streaks/events/codes, or bought with
--                                               Robux. Spends ONLY on cosmetics.
--
-- The separation is enforced in ONE place -- SkinCrateService, which is the only script that spends tokens and
-- never reads Coins. Nothing in the crate path can touch the coin economy, and nothing in the food/gut path can
-- touch tokens, so a balance change on one side can't leak into the other.
--
-- This module holds the AMOUNTS only. The SERVER is the sole authority on granting them (SkinCrateService's
-- _G.crateTokensAward), so a client that fakes a "daily complete" gets nothing.
-- ============================================================================================================

local CrateTokens = {}

CrateTokens.CURRENCY_NAME = "Crate Tokens"
CrateTokens.LEADERSTAT    = "CrateTokens" -- the IntValue name in leaderstats (PlayerStats creates it)
CrateTokens.ICON          = "\xF0\x9F\x8E\x9F"  -- 🎟

-- Hard ceiling, so a bugged grant loop can never mint an absurd balance into a save.
CrateTokens.MAX_BALANCE = 1000000

-- ---- EARN AMOUNTS -------------------------------------------------------------------------------------------
-- Every source the spec calls for. Tune freely -- these are the only numbers that decide how fast a
-- non-spending player earns crates. At Starter Crate = 250 tokens, the defaults below mean roughly:
--   a full daily sweep (3 tasks + the daily bonus)      ~=  95 tokens/day
--   a weekly clear                                       = 150 tokens
--   so ~2-3 free Starter crates a week without paying.
CrateTokens.REWARDS = {
	dailyTask      = 25,   -- one daily task completed
	dailyAllTasks  = 20,   -- bonus for clearing the whole daily list
	weeklyTask     = 60,   -- one weekly task completed
	weeklyAllTasks = 150,  -- bonus for clearing the weekly list
	realmComplete  = 400,  -- finishing a realm (Candy / Dino / Space / the main island run)
	questLine      = 200,  -- finishing a whole quest line (e.g. every pet quest on a realm)
	petQuest       = 75,   -- a single pet quest completed
	seasonPassFree = 50,   -- a free-lane Season Pass tier
	seasonPassPaid = 120,  -- a premium-lane Season Pass tier
	eventReward    = 100,  -- a live event objective
	promoCode      = 250,  -- default for a code that grants tokens (a code may override with its own amount)
}

-- ---- LOGIN STREAK -------------------------------------------------------------------------------------------
-- Day N of a consecutive-login streak. Beyond the table the last value repeats, so a long streak keeps paying
-- without needing an entry per day.
CrateTokens.LOGIN_STREAK = { 20, 30, 40, 60, 80, 110, 200 }

function CrateTokens.loginStreakReward(day)
	local d = math.max(1, math.floor(tonumber(day) or 1))
	return CrateTokens.LOGIN_STREAK[math.min(d, #CrateTokens.LOGIN_STREAK)]
end

-- ---- ANTI-FARM CAPS -----------------------------------------------------------------------------------------
-- Optional per-source daily ceilings. A source NOT listed here is uncapped (one-off grants like realmComplete
-- and questLine don't need a cap -- they can only fire once). Sources that a player could conceivably repeat are
-- capped so a bug in a caller can't become an infinite token faucet.
CrateTokens.DAILY_CAPS = {
	dailyTask   = 100,  -- 4 tasks' worth, even if the task system somehow re-fires
	weeklyTask  = 300,
	eventReward = 400,
	petQuest    = 300,
}

-- ---- ISLAND TASK LADDER -------------------------------------------------------------------------------------
-- ONE-TIME token reward for finishing an island's quest, keyed by the quest's OWN id (the same short name its
-- _G.<id>QuestComplete flag uses, which is what IslandTaskTokens pays against).
--
-- ORDERED BY CLIMB SLOT, NOT BY ISLAND NUMBER. IslandOrder.SLOT_TO_ISLAND is a deliberate scramble
-- ({1,9,3,13,5,8,2,11,4,14,15}), so "island 9" is the SECOND island you reach and "island 2" is the seventh.
-- Paying by island number would hand a climber the big rewards in a random order; these amounts rise with the
-- slot you actually reach them at, so the ladder feels like a ladder.
--
-- THE TOTAL IS THE POINT: 750, which is exactly 5 spins on the 100 Starter crate plus 1 on the 250 Premium.
-- Clear every island quest and you have earned a real crate session -- the identical promise the Food and
-- Space realms make, so a player moving between realms meets the same deal.
--
-- Slot 9 (island4) hosts TWO quests -- Campfire Freeze and Summit Bell, both on Frostbell Peak -- so it
-- splits its 85 into 45 + 40 rather than paying double. Every other slot has exactly one quest.
--
-- (!) THE SLOTS BELOW ARE THE VERIFIED ONES. Until now this table read `summit` as slot 6 (island8) and
-- `crystal` as slot 8 (island11) -- the same swap DoneCommand.client.luau documents and works around. Read
-- the quests themselves and SummitBellQuest is ISLAND_NAME = "island4" (slot 9) while CrystalMineQuest is
-- ISLAND_NAME = "island8" (slot 6). Because this table is keyed by quest id and not by island, the swap never
-- misrouted a payout -- it MISPRICED four of them. Crystal, the sixth island you reach, paid 40 (half of a
-- twin slot it is not on); Tunnel, alone on slot 8, paid 40 instead of the full 80; and island4 collected
-- 85 + 65 = 150 for its two quests, nearly twice what its rung is worth. Corrected below, and the ladder
-- still totals exactly 750.
--
-- ===== RESCALED WITH THE CRATE PRICES =====
-- This ladder totalled 1,850 while Starter cost 250 and Premium 600. Those are now 100 and 250, so the same
-- tokens bought roughly two and a half times as much and "clear the realm, earn a crate session" had quietly
-- become "clear the realm, earn eighteen Starters". The promise is the point, not the numeral, so the target
-- moves with the prices: 1,850 -> 750 (x0.405), every rung scaled onto a clean multiple of 5, still strictly
-- ascending by CLIMB SLOT, and the twin-quest slot still splitting evenly.
--
-- Keep this in step with the Food realm's ladder (src/shared/CrateTokens.luau) -- both encode the same deal,
-- and a player crossing realms should not find one of them paying on the old scale.
CrateTokens.ISLAND_TASK = {
	candy    =  35,  -- slot 1  (island1)  Gumball Hunt
	cleanup  =  45,  -- slot 2  (island9)  Reactor Cleanup
	cookie   =  50,  -- slot 3  (island3)  Cookie Repair
	park     =  55,  -- slot 4  (island13) Ancient Tree
	storm    =  60,  -- slot 5  (island5)  Taffy Storm
	crystal  =  65,  -- slot 6  (island8)  Crystal Mine
	-- OFF THE LADDER NOW: the Jelly Tower was removed from island2, so this id is never
	-- claimed any more. Kept (rather than deleted) so a save that already recorded it stays
	-- readable, and so the quest can be dropped back in without re-solving anything.
	jelly    =  75,  -- island2 (no slot) Jelly Tower -- REMOVED FROM THE WORLD
	tunnel   =  80,  -- slot 8  (island11) Tunnel Blast
	campfire =  45,  -- slot 9  (island4)  Campfire Freeze  \_ one slot, two quests, 85 split
	summit   =  40,  -- slot 9  (island4)  Summit Bell      /
	smores   =  90,  -- slot 10 (island14) Camp S'mores
	bakery   = 100,  -- slot 8 (island15) The Great Bake-Off -- moved down when the quarry took the summit; swapped amounts with candymine so the climb's solved total is unchanged
	-- OFF THE LADDER, so it is not part of the slot solve above and does not disturb it: island18
	-- is reached by command/wormhole, not by a crossing. Priced above the summit because it is the
	-- longest quest in the realm (five fetches, a boss chase, then eight more fetches under fire).
	pancake  = 120,  -- island18 (no slot) Wake the Pancake Monster
	tractor  = 115,  -- island19 (no slot) Broken Tractor
	-- island16 is off the ladder too (EXTRA_PERSIST in IslandStreaming, reached by /island16 or the
	-- wormhole). It was the one quest in the realm with a completion flag and no reward: DoneCommand
	-- already listed it, but this table did not, so awardIslandTask returned 0 and finishing it paid
	-- nothing at all. Priced BELOW pancake and tractor because it is much the shorter job -- five
	-- fetches and a blast, no boss and no second act.
	candymine = 110, -- slot 13 (island16) Candy Mine Explosion -- THE ENDING ISLAND's finale reward
}

-- What the celebration card calls each quest. Kept beside the amounts rather than passed up from the client,
-- so the banner can never be made to say something the server did not choose. Matches the Quest Journal's
-- wording exactly -- a kid who reads "Taffy Storm" on the card should find "Taffy Storm" in the journal.
CrateTokens.ISLAND_TASK_NAME = {
	candy    = "Gumball Hunt",
	cleanup  = "Reactor Cleanup",
	cookie   = "Cookie Repair",
	park     = "Ancient Tree",
	storm    = "Taffy Storm",
	summit   = "Summit Bell",
	jelly    = "Jelly Tower",
	tunnel   = "Tunnel Blast",
	crystal  = "Crystal Mine",
	campfire = "Campfire Freeze",
	smores   = "Camp S'mores",
	bakery   = "The Great Bake-Off",
	pancake  = "Wake the Pancake Monster",
	tractor  = "Broken Tractor",
	candymine = "Candy Mine Explosion",
}

-- A FART-POWER TOP-UP on top of the tokens, for the quests that promise one. Paid through the
-- SAME once-ever ledger as the tokens (IslandTaskTokens), so finishing the fight again -- or
-- replaying it on a fresh server -- pays nothing, and there is no new remote to abuse. Quests
-- absent from this table simply grant no power, which is every quest that shipped before it.
CrateTokens.ISLAND_TASK_POWER = {
	pancake = 400,   -- island18: a free tank most of the way up, as the quest's card advertises
	tractor = 320,   -- island19: a day's work is worth a decent top-up
}

function CrateTokens.islandTaskPower(questId)
	return CrateTokens.ISLAND_TASK_POWER[tostring(questId)] or 0
end

function CrateTokens.islandTaskReward(questId)
	return CrateTokens.ISLAND_TASK[tostring(questId)] or 0
end

function CrateTokens.islandTaskTotal()
	local t = 0
	for _, v in pairs(CrateTokens.ISLAND_TASK) do t += v end
	return t
end

function CrateTokens.amountFor(source, ...)
	if source == "loginStreak" then return CrateTokens.loginStreakReward(...) end
	if source == "islandTask" then return CrateTokens.islandTaskReward(...) end
	return CrateTokens.REWARDS[source] or 0
end

function CrateTokens.dailyCap(source)
	return CrateTokens.DAILY_CAPS[source] -- nil = uncapped
end

-- "1,800" -- thousands separators for the HUD balance
function CrateTokens.format(n)
	local s = tostring(math.max(0, math.floor(tonumber(n) or 0)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

return CrateTokens
