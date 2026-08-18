--======================================================================
-- RivalCallout.client.lua  (LocalScript)
--======================================================================
-- "YOU BEAT SAM'S BEST!" -- fires the moment your flight passes another player's best height this session.
--
-- FlightFeedback already tells you when you physically overtake someone mid-air. This is the other half, and
-- the stickier one: it fires against a person's RECORD rather than their current position, so it lands even
-- when that person is standing on the ground, in a menu, or on the other side of the map. A kid who is alone
-- in the sky still gets told they beat someone.
--
-- ===== FRIENDS FIRST, AND THAT IS THE WHOLE POINT =====
-- "You beat a player's best" is a stat. "You beat SAM'S best" is a thing you say out loud to Sam. So friends
-- outrank strangers even when a stranger's record was passed first in the same flight, and a friend's callout
-- says so on the banner. IsFriendsWith is cached per session -- it is a web call and calling it mid-flight,
-- per player, per frame, would be a rate-limit incident.
--
-- ===== IT IS HONEST ABOUT WHAT "BEST" MEANS =====
-- BestHeight is a SESSION best, sampled server-side by SocialStats (which does not trust the client, for the
-- same reason LeaderboardService refuses to run a height board at all). So the banner says "this round" --
-- claiming an all-time record this cannot see would be a lie the player eventually catches.
--
-- ===== ONE CALLOUT PER PERSON PER FLIGHT =====
-- Without that, hovering on the exact stud of someone's record machine-guns the banner. Passing the same
-- rival again after landing is a fresh achievement and re-arms.
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

if _G.__RivalCalloutClient then
	warn("[RivalCallout] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__RivalCalloutClient = true

--======================================================================
-- TUNING
--======================================================================
local MIN_RECORD   = 260    -- ignore records barely above spawn (island 1 sits at ~245): beating those is noise
local GROUND_Y     = 250    -- below this you are on Bean Farm, not flying -- used to reset the per-flight set
local CHECK_EVERY  = 0.35
local MARGIN       = 5      -- must clear the record by this much, so hovering on the boundary cannot re-fire

--======================================================================
-- FRIEND LOOKUP (cached)
--======================================================================
local friendCache = {}   -- [userId] = true/false
local function isFriend(userId)
	local cached = friendCache[userId]
	if cached ~= nil then return cached end
	friendCache[userId] = false                     -- assume not, so a slow call cannot stall the loop
	task.spawn(function()
		local ok, res = pcall(function() return player:IsFriendsWith(userId) end)
		friendCache[userId] = (ok and res) and true or false
	end)
	return friendCache[userId]
end

--======================================================================
-- THE BANNER
--======================================================================
local function shout(name, height, friend)
	local text = friend
		and string.format("\xF0\x9F\x94\xA5  YOU BEAT %s'S BEST!  %s studs", string.upper(name), tostring(height))
		or  string.format("\xE2\x9A\xA1  PASSED %s'S BEST THIS ROUND  \xE2\x80\xA2  %s studs", string.upper(name), tostring(height))

	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(_G.NotifyCenter.push, {
			text = text,
			color = friend and Color3.fromRGB(255, 206, 92) or Color3.fromRGB(120, 186, 255),
			-- SOCIAL, not REWARD. This fires mid-flight and must never sit on top of an island-landing banner
			-- or a crate reveal -- those are the things the player actually stopped to look at.
			priority = (_G.NotifyCenter.PRIORITY and _G.NotifyCenter.PRIORITY.SOCIAL) or 10,
		})
	end
	if _G.Sfx then pcall(_G.Sfx.play, friend and "levelup" or "pop") end
	print(string.format("[RivalCallout] passed %s's best (%d studs)%s", name, height, friend and " [friend]" or ""))
end

--======================================================================
-- WATCH
--======================================================================
task.spawn(function()
	local calledThisFlight = {}   -- [userId] = true, cleared on landing
	local airborne = false

	while true do
		task.wait(CHECK_EVERY)

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local y = hrp.Position.Y

			-- A flight ENDS when you come back down near the ground. Resetting there (rather than on a
			-- velocity check) means a hover at altitude does not count as landing and silently re-arm everything.
			if y < GROUND_Y then
				if airborne then calledThisFlight = {}; airborne = false end
			else
				airborne = true

				-- Collect everyone whose record we just cleared, THEN pick one -- so a friend still wins even
				-- if a stranger's record happened to be lower and would have been hit first.
				local bestFriend, bestOther
				for _, other in ipairs(Players:GetPlayers()) do
					if other ~= player and not calledThisFlight[other.UserId] then
						local rec = tonumber(other:GetAttribute("BestHeight")) or 0
						if rec >= MIN_RECORD and y > rec + MARGIN then
							local entry = { p = other, rec = rec }
							if isFriend(other.UserId) then
								-- among friends, the HIGHEST record beaten is the better brag
								if not bestFriend or rec > bestFriend.rec then bestFriend = entry end
							else
								if not bestOther or rec > bestOther.rec then bestOther = entry end
							end
						end
					end
				end

				local pick = bestFriend or bestOther
				if pick then
					calledThisFlight[pick.p.UserId] = true
					shout(pick.p.DisplayName or pick.p.Name, pick.rec, bestFriend ~= nil)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p) friendCache[p.UserId] = nil end)

print("[RivalCallout] ready -- callouts when you pass another player's best height (friends called out by name)")
