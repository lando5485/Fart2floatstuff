--!nonstrict
--======================================================================
-- GutProgression.server.luau  (Server Script)  -- CandyRealm
-- PUBLISHES THE QUEST LEDGER AS THE `UnlockedSlot` ATTRIBUTE.
--======================================================================
-- ===== WHAT THIS SCRIPT DOES NOW (food-realm port) =====
-- Under the space port this script RESTORED A GUT from the quest ledger on join, because
-- every gut was funded by exactly one quest and coins/tank were never saved. That is gone:
-- guts are bought with flight coins and gated by the island reached (StomachUpgrade), so
-- there is no gut to derive from the ledger and this file grants nothing.
--
-- What remains is the one number the CONTENT systems still need from the persisted quest
-- ledger (IslandTaskTokens' "CandyIslandTasks_v1", paid once ever):
--
--     UnlockedSlot = 1 + (how many island quests are done, CONTIGUOUSLY from slot 1)
--
-- Read by:
--   * Shop_AllInOne   -- the FOOD STAND gate: slot k's stand opens when UnlockedSlot > k
--                        (or the session flag says the quest was finished just now).
--   * PetHub_AllInOne -- the quest list's done/undone ticks.
--   * WormholeClient  -- which fast-travel rows are open.
--
-- It is NOT read by the economy any more. BuyFood, StomachUpgrade and FlightEconomy all gate
-- on HighestSlot (the island you have physically stood on) -- the food realm's ceiling lock.
--
-- CONTIGUOUS IS DELIBERATE: a player who finished slot 5's quest without slot 4's has
-- UnlockedSlot 4, not 6, and has to go back for the one they skipped.
--
-- The gut panel used to read a second attribute, UnlockedGutTier, from here. It now derives
-- its locks from HighestSlot + StomachTiers.unlockSlot directly; the attribute is still
-- published (as that derived value) so nothing reading it sees nil.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if _G.__CandyGutProgression then
	warn("[GutProgression] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__CandyGutProgression = true

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local StomachTiers = require(Shared:WaitForChild("StomachTiers"))
local IslandConfig = require(Shared:WaitForChild("IslandConfig"))

-- How long to wait for the DataStore read behind the ledger before giving up. A slow read
-- must NOT be read as "you have finished nothing" for longer than necessary, so we wait;
-- but the attribute defaults to 1 meanwhile, which only ever LOCKS stands, never opens them.
local LEDGER_WAIT = 30

--[[
	1 + the contiguous run of finished quests from slot 1. Returns 1 when nothing is done.
]]
local function questSlot(player): number
	local claimed = _G.islandTaskClaimed
	if type(claimed) ~= "function" then
		return 1
	end
	local unlocked = 1
	for slot = 1, #IslandConfig.ISLANDS do
		local island = IslandConfig.ISLANDS[slot]
		if not (island.questId and claimed(player, island.questId)) then
			break
		end
		unlocked = slot + 1
	end
	return math.clamp(unlocked, 1, #IslandConfig.ISLANDS + 1)
end

--[[
	PUBLISH THE GATE so the client panels can draw it. Attributes replicate to every client
	automatically, so there is no request/response and no staleness. Display/convenience
	only where the server is concerned: nothing economic keys off it any more.
]]
local function refreshGutUnlock(player)
	local unlocked = questSlot(player)
	player:SetAttribute("UnlockedSlot", unlocked)
	-- Kept for readers that still expect it: the highest gut whose island gate is passed.
	local reached = math.max(1, math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1))
	player:SetAttribute("UnlockedGutTier", StomachTiers.unlockedTierFor(reached))
	return unlocked
end
_G.refreshGutUnlock = refreshGutUnlock

local function onJoin(player)
	-- publish a safe default immediately, then the real value once the ledger has loaded
	player:SetAttribute("UnlockedSlot", 1)
	player:SetAttribute("UnlockedGutTier", 1)
	player:GetAttributeChangedSignal("HighestSlot"):Connect(function() refreshGutUnlock(player) end)

	local deadline = os.clock() + LEDGER_WAIT
	while os.clock() < deadline do
		if type(_G.islandTaskLedgerReady) == "function" and _G.islandTaskLedgerReady(player) then
			break
		end
		task.wait(0.25)
		if not player.Parent then return end
	end
	if not (type(_G.islandTaskLedgerReady) == "function" and _G.islandTaskLedgerReady(player)) then
		warn(("[GutProgression] ledger never loaded for %s -- UnlockedSlot stays at 1 (stands past "
			.. "the first island stay locked until it does)"):format(player.Name))
		return
	end
	local unlocked = refreshGutUnlock(player)
	print(("[GutProgression] %s: quest ledger says UnlockedSlot %d"):format(player.Name, unlocked))
end

Players.PlayerAdded:Connect(function(p) task.spawn(onJoin, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onJoin, p) end

print("[GutProgression] ready -- publishes UnlockedSlot from the quest ledger (stand/journal/wormhole "
	.. "gate); guts are bought with coins and are NOT derived from quests any more")
