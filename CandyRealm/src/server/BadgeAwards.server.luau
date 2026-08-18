--======================================================================
-- BadgeAwards.server.luau  (Script, ServerScriptService)  -- CandyRealm
--======================================================================
-- Roblox BADGES: the profile-visible, permanent kind. They are the cheapest long-term retention hook on the
-- platform -- they show on the player's profile forever, other kids see them, and "I don't have that one yet"
-- is a reason to come back that costs nothing to run.
--
-- ===== EVERY id IS 0 UNTIL YOU CREATE THEM =====
-- Badges must be created by hand on the Creator Dashboard (your experience > Engagement > Badges; each one
-- costs 100 Robux to publish). Paste each real id over its 0 below and that badge starts awarding -- a badge
-- with id 0 is silently skipped, so this script is safe to ship half-filled.
--
-- ===== HOW AWARDING WORKS =====
--   * event-driven where a clean funnel exists: IslandTaskTokens calls _G.badgeIslandQuest on every FIRST
--     completion of an island quest, Gifting calls _G.badgeGiftSent on every successful gift.
--   * polled (every 20s) for the numbers that have no event: the BestHeight and SpeciesOwned attributes that
--     SocialStats publishes.
-- AwardBadge is idempotent on Roblox's side (a second award is a no-op), and `given` keeps this session from
-- even asking twice.
--======================================================================

local BadgeService = game:GetService("BadgeService")
local Players      = game:GetService("Players")

if _G.__BadgeAwardsServer then
	warn("[Badges] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__BadgeAwardsServer = true

--======================================================================
-- THE BADGES
--======================================================================
-- Keep the names short: they render on tiny profile tiles.
local BADGES = {
-- ===== THE JOIN BADGE, FIRST IN THE LIST =====
-- Awarded for arriving, which is not a milestone and is not meant to be one. It is the badge that puts a
-- badge on the profile at all -- an empty badge shelf is a shelf nobody is collecting, and a kid with one
-- already on it has a set to finish. It is also the only reliable marker of who has actually been in this
-- realm, since it lands before any progress is made.
	{ key = "joined", id = 1428418202453474, name = "Candy Traveller", why = "visit this realm" },
	{ key = "firstQuest", id = 0, name = "Sweet Start",     why = "finish your first island quest" },
	{ key = "sixQuests",  id = 0, name = "Candy Climber",   why = "finish 6 island quests" },
	{ key = "allQuests",  id = 0, name = "Sugar Legend",    why = "finish all 12 island quests" },
	{ key = "height2k",   id = 0, name = "Above the Icing", why = "reach 2,000 studs in one session" },
	{ key = "height8k",   id = 0, name = "Summit Sweet",    why = "reach 8,000 studs in one session" },
	{ key = "species5",   id = 0, name = "Pet Wrangler",    why = "own 5 pet species" },
	{ key = "species10",  id = 0, name = "Full Crew",       why = "own all 10 base species" },
	{ key = "firstGift",  id = 0, name = "Candy Santa",     why = "send another player a token gift" },
}

local byKey = {}
for _, b in ipairs(BADGES) do byKey[b.key] = b end

-- [player] = { [key] = true } -- awarded (or at least attempted) this session
local given = {}
Players.PlayerRemoving:Connect(function(p) given[p] = nil end)

-- [player] = island quests first-completed this session. IslandTaskTokens only calls in on the FIRST ever
-- completion of each quest (it is the same once-ever ledger that pays the tokens), so this counter cannot be
-- inflated by replaying a quest -- but it also only counts what happened THIS session. A player who finished
-- six quests last week and one today counts 1, and earns the 6-quest badge on their next fresh run. That is
-- the honest trade for not adding a second persisted counter; the badge is not lost, only deferred.
local questCount = {}
Players.PlayerRemoving:Connect(function(p) questCount[p] = nil end)

local function award(player, key)
	local b = byKey[key]
	if not b then return end
	if b.id == 0 then return end -- not created on the dashboard yet: silently skip
	local g = given[player]
	if not g then g = {}; given[player] = g end
	if g[key] then return end
	g[key] = true
	task.spawn(function()
		local ok, err = pcall(function() BadgeService:AwardBadge(player.UserId, b.id) end)
		if ok then
			print(("[Badges] awarded '%s' to %s"):format(b.name, player.Name))
		else
			-- Un-mark so a transient failure (throttle, network) retries on the next trigger.
			g[key] = nil
			warn(("[Badges] award '%s' to %s failed: %s"):format(b.name, player.Name, tostring(err)))
		end
	end)
end

--======================================================================
-- EVENT-DRIVEN TRIGGERS
--======================================================================
-- Called by IslandTaskTokens on the first-ever completion of each island quest.
_G.badgeIslandQuest = function(player, questId)
	questCount[player] = (questCount[player] or 0) + 1
	local n = questCount[player]
	award(player, "firstQuest")
	if n >= 6 then award(player, "sixQuests") end
	if n >= 12 then award(player, "allQuests") end
end

-- Called by Gifting.server on every successful send (online or queued offline).
_G.badgeGiftSent = function(player)
	award(player, "firstGift")
end

--======================================================================
-- POLLED TRIGGERS (attributes SocialStats publishes)
--======================================================================
task.spawn(function()
	while true do
		task.wait(20)
		for _, p in ipairs(Players:GetPlayers()) do
			local h = tonumber(p:GetAttribute("BestHeight")) or 0
			if h >= 2000 then award(p, "height2k") end
			if h >= 8000 then award(p, "height8k") end
			local sp = tonumber(p:GetAttribute("SpeciesOwned")) or 0
			if sp >= 5 then award(p, "species5") end
			if sp >= 10 then award(p, "species10") end
		end
	end
end)


--======================================================================
-- ARRIVAL
--======================================================================
-- Awarded on join, deferred a few seconds. Not for pacing -- AwardBadge does not care -- but because a badge
-- award competes with the whole join burst (data load, character spawn, world streaming) for the same web
-- budget, and this is the one request in the file that can wait without anybody noticing.
--
-- No "already has it" check: AwardBadge is idempotent on Roblox's side and `given` stops this session asking
-- twice, so a returning player costs one no-op call and never a second badge.
local function onJoin(player)
	task.delay(5, function()
		if player.Parent then award(player, "joined") end
	end)
end
Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end   -- this script may load after the first joins

--======================================================================
local missing = 0
for _, b in ipairs(BADGES) do if b.id == 0 then missing += 1 end end
if missing > 0 then
	print(("[Badges] ready -- %d badges defined but %d have no ids yet. Create them on the Creator Dashboard "
		.. "(Engagement > Badges), paste each id into BADGES in this file, and they start awarding.")
		:format(#BADGES, missing))
else
	print(("[Badges] ready -- %d badges live"):format(#BADGES))
end
