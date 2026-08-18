--======================================================================
-- DoneCommand.client.luau  (LocalScript)  -- CandyRealm
--======================================================================
-- TWO SMALL THINGS THAT BOTH NEEDED "WHICH ISLAND AM I ON", so they share one file.
--
--   1. /done   -- force-completes the quest(s) on the island you are STANDING ON. A testing command:
--                 it flips the quest's own `_G.<name>QuestComplete` flag, which is the same signal
--                 IslandTaskWatcher and QuestJournal already read, so the crate tokens pay and the
--                 journal ticks exactly as they would if you had played it.
--
--   2. _G.questLocked(questName, why)  -- the shared "you haven't taken this job yet" banner. A quest
--                 whose pieces are inert before you accept should SAY so when you touch one, instead of
--                 silently doing nothing and leaving you wondering if it is broken.
--
-- ===== /done DOES NOT REPLAY THE ENDING =====
-- It marks the quest complete for progression and tokens. It does not run the quest's finale (the
-- explosion, the tree waking, the bin sealing) -- those live inside each quest's own state machine and
-- reaching in from outside to drive them would be twelve different reach-ins, each able to break a
-- working quest. Where a quest publishes its own force-complete hook (`_G.<id>ForceComplete`) this calls
-- that instead, so a quest can opt into the full ending with one line on its side.
--
-- A HOOK THAT RETURNS true MEANS "HANDLED -- DO NOT FLAG IT COMPLETE". That is how a quest makes /done
-- a mid-run step instead of an ending: island 15's Bake-Off grants the whole shopping list so the mixing
-- bowl and oven HUDs can be tested, and returns true so nothing pays out for a bake that never happened.
-- The next /done on that island falls through to the normal completion.
--======================================================================

local Players         = game:GetService("Players")
local Workspace       = game:GetService("Workspace")
local TextChatService = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local function norm(s) return (tostring(s or ""):lower():gsub("[%s_%-]", "")) end

-- ============================================================================
-- WHICH ISLAND ARE YOU ON
-- ============================================================================
-- Bounding boxes, with VERTICAL DISTANCE DOMINATING -- the same rule NpcGuideArrow needed.
--
-- A horizontal-only footprint test is wrong for a tower: these islands sit above one another and overlap
-- in X/Z by design (the zig-zag is only +/-320 studs wide), so stood on island 9 you are also "inside"
-- island 1's footprint and a tie-break decides it. That bug had the guide arrows pointing at an NPC
-- 3,364 studs below. Height alone identifies the island here, so height is weighted far above the rest.
local boxes = {}

local function boxOf(m)
	local b = boxes[m]
	-- A box under ~50 studs across means the island had not streamed in when it was measured, so that one
	-- is re-measured rather than trusted.
	if b and b.h.X > 25 and b.h.Z > 25 then return b end
	local ok, cf, size = pcall(function() return m:GetBoundingBox() end)
	if not ok or not cf then return nil end
	b = { c = cf.Position, h = size * 0.5 }
	boxes[m] = b
	return b
end

local function islandUnder(pos)
	local best, bestScore, bestNum
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") then
			local n = tonumber(string.match(norm(m.Name), "^island(%d+)$"))
			if n then
				local b = boxOf(m)
				if b then
					local dx = math.max(0, math.abs(pos.X - b.c.X) - b.h.X)
					local dz = math.max(0, math.abs(pos.Z - b.c.Z) - b.h.Z)
					local dy = math.max(0, math.abs(pos.Y - b.c.Y) - b.h.Y)
					local score = dy * 1e6 + math.sqrt(dx * dx + dz * dz) * 1000 + (b.h.X + b.h.Z)
					if not bestScore or score < bestScore then best, bestScore, bestNum = m, score, n end
				end
			end
		end
	end
	return best, bestNum
end

-- ============================================================================
-- ISLAND -> QUEST(S)
-- ============================================================================
-- `flag` matches IslandTaskWatcher's QUESTS table and QuestJournal's ROWS, which is what makes the token
-- payout and the journal tick work without touching any quest file.
--
-- ⚠ THE ISLAND NUMBERS HERE ARE THE VERIFIED ONES, and two disagree with the comments in
-- IslandTaskWatcher: that file lists `summit` as island8 and `crystal` as island11. Read the quests and it
-- is the other way round -- SummitBellQuest is island4 and CrystalMineQuest is island8. Only the FLAG
-- names matter to the watcher, so those stale comments pay nothing and break nothing there; they would
-- have broken /done, which is keyed by island, so the corrected mapping lives here.
--
-- An island may host MORE THAN ONE quest (island4 has both the campfire and the summit bell). /done
-- finishes every quest on the island you are stood on.
local BY_ISLAND = {
	[1]  = { { id = "candy",     flag = "candyQuestComplete",     name = "Gumball Hunt" } },
	[2]  = { { id = "jelly",     flag = "jellyQuestComplete",     name = "Jelly Tower" } },
	[3]  = { { id = "cookie",    flag = "cookieQuestComplete",    name = "Cookie Repair" } },
	[4]  = { { id = "campfire",  flag = "campfireQuestComplete",  name = "Campfire Freeze" },
	         { id = "summit",    flag = "summitQuestComplete",    name = "Summit Bell" } },
	[5]  = { { id = "storm",     flag = "stormQuestComplete",     name = "Taffy Storm" } },
	[8]  = { { id = "crystal",   flag = "crystalQuestComplete",   name = "Crystal Mine" } },
	[9]  = { { id = "cleanup",   flag = "cleanupQuestComplete",   name = "Reactor Cleanup" } },
	[11] = { { id = "tunnel",    flag = "tunnelQuestComplete",    name = "Tunnel Blast" } },
	[13] = { { id = "park",      flag = "parkQuestComplete",      name = "Ancient Tree" } },
	[14] = { { id = "smores",    flag = "smoresQuestComplete",    name = "Camp S'mores" } },
	[15] = { { id = "bakery",    flag = "bakeryQuestComplete",    name = "The Great Bake-Off" } },
	[16] = { { id = "candymine", flag = "candyMineQuestComplete", name = "Candy Mine Explosion" } },
	[18] = { { id = "pancake",   flag = "pancakeQuestComplete",   name = "Wake the Pancake Monster" } },
	[19] = { { id = "tractor",   flag = "tractorQuestComplete",   name = "Broken Tractor" } },
}

-- ============================================================================
-- THE BANNER  (shared -- also used by the "not accepted yet" nudge below)
-- ============================================================================
local function banner(text, colour)
	local NC = _G.NotifyCenter
	if NC and NC.push then
		pcall(function()
			NC.push({
				text = text,
				color = colour or Color3.fromRGB(255, 122, 190),
				-- EVENT rung: above the standing objective (REWARD 40) so it is actually seen, below an
				-- island arrival or a purchase so it can never sit on top of those.
				priority = (NC.PRIORITY and NC.PRIORITY.EVENT) or 80,
				duration = 3.5,
			})
		end)
		return
	end
	if _G.showHudBanner then pcall(_G.showHudBanner, text, colour, 3.5) end
end

-- ============================================================================
-- 2) "YOU HAVEN'T TAKEN THIS JOB YET"
-- ============================================================================
-- Published for the quests to call. Touch a minigame piece before accepting and the quest calls this
-- instead of returning silently -- an inert prompt that does nothing is indistinguishable from a broken
-- one, and this realm has enough genuinely broken markers that players cannot tell the difference.
--
-- Rate-limited: the pieces are ProximityPrompts and a held key re-triggers, so without this a single lean
-- on the button would stack the same banner a dozen deep and starve the hero lane.
local lastLocked = 0
_G.questLocked = function(questName, why)
	if os.clock() - lastLocked < 2.5 then return end
	lastLocked = os.clock()
	banner(why or ("\xF0\x9F\x92\xAC Talk to the Candy NPC first to start " .. tostring(questName or "this quest") .. "!"),
		Color3.fromRGB(255, 190, 80))
end

-- ============================================================================
-- 1) /done
-- ============================================================================
local function runDone()
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then banner("/done -- no character yet."); return end

	local isle, num = islandUnder(hrp.Position)
	if not isle or not num then
		banner("/done -- you are not standing on any island.")
		warn("[Done] no island under the player -- nothing to complete")
		return
	end

	local list = BY_ISLAND[num]
	if not list then
		banner(("/done -- island%d has no quest."):format(num))
		warn(("[Done] island%d is not in BY_ISLAND -- add a row if it has a quest now"):format(num))
		return
	end

	local didAny, already, handledSelf = {}, {}, {}
	for _, q in ipairs(list) do
		if _G[q.flag] == true then
			already[#already + 1] = q.name
		else
			-- Prefer the quest's OWN finisher if it publishes one -- that runs the real ending. Falling back
			-- to the flag marks it done for tokens and the journal without faking the finale.
			--
			-- A HOOK MAY RETURN true TO MEAN "HANDLED -- DO NOT FLAG IT". That is for quests where /done
			-- is most useful mid-run: the Bake-Off grants its shopping list so the oven HUDs can be tried,
			-- and flagging the quest complete on the way past would pay the island token for a bake that
			-- never happened. Those quests fall through to the normal completion on the NEXT /done.
			local hook = _G[q.id .. "ForceComplete"]
			if type(hook) == "function" then
				local ok, handled = pcall(hook)
				print(("[Done] island%d '%s' -> called its own ForceComplete hook"):format(num, q.name))
				if ok and handled == true then
					handledSelf[#handledSelf + 1] = q.name
					print(("[Done] island%d '%s' handled it itself -- NOT flagged complete"):format(num, q.name))
					continue
				end
			end
			_G[q.flag] = true
			didAny[#didAny + 1] = q.name
			print(("[Done] island%d '%s' marked complete (_G.%s = true)"):format(num, q.name, q.flag))
		end
	end

	if #didAny > 0 then
		banner(("\xE2\x9C\x85 /done -- %s complete!"):format(table.concat(didAny, " + ")),
			Color3.fromRGB(110, 210, 120))
	elseif #handledSelf > 0 then
		-- the quest ran its own /done step and said so -- it puts up its own banner explaining
		-- what it did, so this one only confirms the command landed
		banner(("\xE2\x9C\x85 /done -- %s moved you on."):format(table.concat(handledSelf, " + ")),
			Color3.fromRGB(110, 210, 120))
	elseif #already > 0 then
		banner(("/done -- %s was already complete."):format(table.concat(already, " + ")))
	end
end

local function onCommand(msg)
	local m = tostring(msg or ""):lower():gsub("^%s+", "")
	if m:sub(1, 5) ~= "/done" then return end
	runDone()
end

-- Both chat routes: TextChatService is the modern one, player.Chatted the legacy one. Every other command
-- in this realm (/arrows, /island<N>, /npc) wires both, and so does this.
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)

-- Also exposed as a call, so a button or another script can trigger it without going through chat.
_G.islandDone = runDone

print("[Done] ready -- type /done to complete the quest on the island you are standing on."
	.. "  _G.questLocked(name) publishes the 'talk to the NPC first' banner.")
