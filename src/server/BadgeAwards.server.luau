--======================================================================
-- BadgeAwards.server.luau  (Script, ServerScriptService)
--======================================================================
-- Roblox BADGES for the milestones that matter. Badges are the cheapest high-value reward in the platform:
-- they are free to award, they are PERMANENT, and -- the part that actually matters -- they show on the kid's
-- Roblox PROFILE, outside your game, where their friends see them. A badge is the only reward in this game
-- that does marketing for you.
--
-- ============================================================================================
--  !!!  YOU MUST CREATE THE BADGES FIRST -- THEY CANNOT BE MADE FROM CODE.                 !!!
--  !!!                                                                                      !!!
--  !!!  Creator Dashboard -> your experience -> Engagement -> Badges -> Create Badge.        !!!
--  !!!  Each one costs 100 Robux to create (one-off, not per award). Paste each badge's ID   !!!
--  !!!  into BADGES below. An entry left at 0 is simply skipped -- the game runs fine with   !!!
--  !!!  none of them configured, so you can add them one at a time.                          !!!
-- ============================================================================================
--
-- ===== AWARDING DOES NOT WORK IN STUDIO =====
-- BadgeService needs a published place, so every attempt here fails in a Studio playtest. That is expected
-- and this script says so once rather than spamming the output -- otherwise the first thing you would do is
-- go hunting for a bug that is not there.
--
-- ===== IT NEVER RE-AWARDS =====
-- UserHasBadgeAsync is checked once per badge per session and the result cached, because it is a web call and
-- polling it every few seconds for every player in the server would be a rate-limit incident waiting to
-- happen. Roblox itself also ignores a duplicate award, so the check is about traffic, not correctness.
--======================================================================

local Players      = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")

-- s->c: (badgeLabel). The client turns this into a hero banner -- see Achievements.client.lua. Created
-- here rather than assumed, so load order with anything else touching ReplicatedStorage cannot leave it
-- missing and silently lose the announcement again.
local BadgeBanner = game:GetService("ReplicatedStorage"):FindFirstChild("BadgeEarnedEvent")
if not BadgeBanner then
	BadgeBanner = Instance.new("RemoteEvent")
	BadgeBanner.Name = "BadgeEarnedEvent"
	BadgeBanner.Parent = game:GetService("ReplicatedStorage")
end

if _G.__BadgeAwardsServer then
	warn("[Badges] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__BadgeAwardsServer = true

--======================================================================
-- THE BADGES
--======================================================================
-- id   : paste from the Creator Dashboard. 0 = not created yet -> silently skipped.
-- test : returns true when the player has earned it. Runs on the server, every few seconds, per player --
--        so it must be cheap and must never yield.
-- THE OTHER REALMS' BADGES LIVE IN THE OTHER REALMS.
--
-- These three exist and are paid for, but they cannot be awarded from here -- a player standing on Bean Farm
-- has not joined the Space realm, and handing them the badge for it on the way to the portal would make it a
-- badge for clicking a door. Each belongs in its own place's BadgeAwards, awarded on join there:
--
--   Joining Space Realm  3361125680446145   -> Space place  (125063266868039)
--   Joining Dino Realm   1706106194994975   -> Dino place   (110777788409412)
--   Joining Candy Realm  1428418202453474   -> Candy place  (CandyRealm/src)
--
-- They are recorded here so the ids are not lost, NOT because this script uses them.
local BADGES = {
	{
		-- Awarded the moment a player is in the game at all. Deliberately the first thing that happens to
		-- them: a badge inside the first ten seconds teaches a new player that this game gives things out,
		-- and it lands on their profile where their friends see it.
		key = "justjoined", id = 830343673404751, label = "Just Joined",
		test = function() return true end,
	},
	{
		-- The FOOD realm specifically -- and gated on SeenGardenIntro rather than on joining, so it means
		-- "actually arrived on Bean Farm" instead of "loaded the menu". Otherwise it is the same badge as
		-- Just Joined awarded twice, which teaches nothing.
		key = "firstrealm", id = 3111475138104703, label = "Joined the Food Realm",
		test = function(p) return p:GetAttribute("SeenGardenIntro") == true end,
	},
	{
		key = "island3", id = 0, label = "Cabbage Climber",
		test = function(p) return (tonumber(p:GetAttribute("HighestIsland")) or 1) >= 3 end,
	},
	{
		key = "island7", id = 0, label = "Halfway Up",
		test = function(p) return (tonumber(p:GetAttribute("HighestIsland")) or 1) >= 7 end,
	},
	{
		key = "island11", id = 0, label = "Ice Cream Isle",
		test = function(p) return (tonumber(p:GetAttribute("HighestIsland")) or 1) >= 11 end,
	},
	{
		key = "island14", id = 0, label = "Top of the World",
		test = function(p) return (tonumber(p:GetAttribute("HighestIsland")) or 1) >= 14 end,
	},
	{
		-- Any rare variant in the inventory. PetSystem stores a rare in its OWN slot with the "#R" suffix
		-- (variantKey), which is what makes "do they own a rare at all" a key scan rather than a data read.
		key = "rare", id = 0, label = "One in a Thousand",
		test = function(p)
			local owned = _G.playerOwnedPets and _G.playerOwnedPets[p]
			if not owned then return false end
			for key in pairs(owned) do
				if tostring(key):sub(-2) == "#R" then return true end
			end
			return false
		end,
	},
	{
		-- All five island pet quests. Reads the SAME persisted table the token reward is gated on, so the badge
		-- and the tokens can never disagree about what has been completed.
		key = "allquests", id = 0, label = "Quest Master",
		test = function(p)
			local done = _G.playerEverCompletedQuests and _G.playerEverCompletedQuests[p]
			if not done then return false end
			for _, petId in ipairs({ "BroccoliPet", "CoconutCrab", "PopcornSheep", "ButterDuck", "BurritoArmadillo" }) do
				if not done[petId] then return false end
			end
			return true
		end,
	},
	{
		key = "collector", id = 0, label = "Master Collector",
		test = function(p) return (tonumber(p:GetAttribute("CollectionPct")) or 0) >= 100 end,
	},
	{
		key = "rebirth", id = 0, label = "Born Again",
		test = function(p) return (tonumber(p:GetAttribute("Rebirths")) or 0) >= 1 end,
	},
}

--======================================================================
-- AWARD
--======================================================================
local earned   = {}   -- [player] = { [key] = true }  -- already has it, or we just gave it
local warnedNoStudio = false

local function award(player, badge)
	if badge.id == 0 then return end

	local bucket = earned[player]
	if not bucket then bucket = {}; earned[player] = bucket end
	if bucket[badge.key] then return end

	-- One web call per badge per session, then never again for this player.
	local ok, has = pcall(function() return BadgeService:UserHasBadgeAsync(player.UserId, badge.id) end)
	if ok and has then bucket[badge.key] = true; return end

	local gaveOk, err = pcall(function() return BadgeService:AwardBadge(player.UserId, badge.id) end)
	if gaveOk then
		bucket[badge.key] = true
		print(string.format("[Badges] awarded '%s' to %s", badge.label, player.Name))
		-- A badge that lands silently is a badge nobody notices. Roblox shows its own toast, but that toast is
		-- easy to miss mid-flight, so say it in the game's own voice too.
		-- THIS USED TO READ _G.NotifyCenter DIRECTLY AND WAS DEAD CODE. NotifyCenter is a LocalScript, so
		-- _G.NotifyCenter only ever exists in the CLIENT's global table; on the server that check was always
		-- nil, so no badge -- including Master Collector, the 100%-collection reward -- has ever bannered.
		-- The award itself always worked, which is why this never looked broken.
		pcall(function() BadgeBanner:FireClient(player, badge.label) end)
	else
		-- Expected in Studio. Say it once, clearly, then stop -- this is not a bug and should not look like one.
		if not warnedNoStudio then
			warnedNoStudio = true
			warn("[Badges] AwardBadge failed -- this is EXPECTED in Studio (BadgeService needs a published place). "
				.. "On a live server it means the badge id does not belong to this experience. Error: " .. tostring(err))
		end
	end
end

--======================================================================
-- WATCH
--======================================================================
Players.PlayerRemoving:Connect(function(p) earned[p] = nil end)

local configured = 0
for _, b in ipairs(BADGES) do if b.id ~= 0 then configured = configured + 1 end end

task.spawn(function()
	while true do
		task.wait(5)
		if configured > 0 then
			for _, player in ipairs(Players:GetPlayers()) do
				for _, badge in ipairs(BADGES) do
					local ok, hit = pcall(badge.test, player)
					if ok and hit then award(player, badge) end
				end
			end
		end
	end
end)

if configured == 0 then
	print(("[Badges] ready -- %d badges defined but NONE have ids yet. Create them on the Creator Dashboard "
		.. "(Engagement > Badges), paste each id into BADGES in this file, and they start awarding."):format(#BADGES))
else
	print(("[Badges] ready -- %d/%d badges configured and awarding"):format(configured, #BADGES))
end
