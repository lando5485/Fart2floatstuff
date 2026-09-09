--======================================================================
-- GroupMembership.luau  (ModuleScript -> ReplicatedStorage/Shared)
--======================================================================
-- ONE answer to "is this player in the MLR Studios group RIGHT NOW", shared by every server
-- script that gates something on it: RewardsService (+10% coins) and SocialRewards (+5 pet
-- levels, one-time). Same reasoning as Gamepasses.luau -- the group id was hand-copied into
-- three files and the "you must rejoin" bug had to be fixed in each of them separately.
--
-- WHY NOT Player:IsInGroup()
--   IsInGroup is answered from a cache the engine fills the FIRST time it is asked for that
--   player in that server, and never refreshes for the rest of their session. So a player who
--   presses JOIN GROUP in-game, joins on the group page, and comes straight back still reads as
--   a non-member -- which is why every group panel in this place used to end with "then REJOIN
--   the game to claim". That is the bug. GroupService:GetGroupsAsync() is a fresh web request
--   every call, so it sees a membership that is ten seconds old.
--
-- WHAT THIS DOES NOT DO
--   It cannot join the group. Roblox has no API for that -- no experience can add a player to a
--   group, and anything claiming otherwise is a scam. The button opens the group page in the
--   in-experience browser overlay; this module is what makes the perk land the moment they are
--   back, with no rejoin. That is the whole of what the platform allows.
--
-- COST
--   GetGroupsAsync is a WEB REQUEST. Never call it in a loop or per-frame. isMember() rate-limits
--   to one call per player per COOLDOWN seconds and remembers a positive for the session, so the
--   client is free to poll it while the group panel is open.
--
-- WHO MAY CALL WHAT
--   GROUP_ID / GROUP_URL  -- read them anywhere. That is the point: three files used to hand-copy the id.
--   isMember()            -- SERVER ONLY. The client must never be the authority on this or the coin perk
--                            is something you can grant yourself; client code asks the server instead,
--                            through RewardsService's CheckGroupNow remote.
--======================================================================

local GroupService = game:GetService("GroupService")

local GroupMembership = {}

GroupMembership.GROUP_ID  = 758781978
GroupMembership.GROUP_URL = "https://www.roblox.com/communities/758781978/MLR-Studios"

local COOLDOWN = 4 -- seconds between web calls for the same player

local known = {} -- [userId] = true once we have seen them in the group (cleared by forget())
local last  = {} -- [userId] = os.clock() of that player's last web call

-- Returns (isMember: boolean, status: string).
--   status "member"       -- confirmed in the group (isMember true)
--   status "not-a-member" -- confirmed NOT in the group
--   status "cooldown"     -- asked too soon after the last call; NOTHING was looked up
--   status "failed"       -- the web call errored (Roblox down, no network in Studio, ...)
-- Only "member" is a confirmed yes and only "not-a-member" is a confirmed no. Callers must never
-- turn "cooldown" or "failed" into "they left the group" -- treat those as "ask again later", or a
-- blip in the group API silently switches off a perk the player has already earned.
function GroupMembership.isMember(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false, "failed" end
	local uid = player.UserId
	if known[uid] then return true, "member" end

	local now = os.clock()
	if last[uid] and (now - last[uid]) < COOLDOWN then return false, "cooldown" end
	last[uid] = now

	local ok, groups = pcall(function() return GroupService:GetGroupsAsync(uid) end)
	if not ok or type(groups) ~= "table" then return false, "failed" end
	for _, g in ipairs(groups) do
		if g.Id == GroupMembership.GROUP_ID then
			known[uid] = true
			return true, "member"
		end
	end
	return false, "not-a-member"
end

-- Drop a player's cached answer on leave so the tables cannot grow for the life of the server.
function GroupMembership.forget(player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		known[player.UserId] = nil
		last[player.UserId]  = nil
	end
end

return GroupMembership
