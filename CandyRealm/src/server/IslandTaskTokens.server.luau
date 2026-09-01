--======================================================================
-- IslandTaskTokens.server.luau  (Script, ServerScriptService)  -- CandyRealm
--======================================================================
-- Pays CRATE TOKENS for finishing an island's quest, ONCE per quest, ever.
--
-- ===== WHY THIS IS A SERVER SCRIPT AND NOT A LINE IN EACH QUEST =====
-- All twelve Candy quests are CLIENT scripts (`*_AllInOne.client.lua`), and each one already pays its coin
-- reward by firing CoinEvent straight at the server. Adding a token grant inside twelve fragile, thousand-line
-- quest files would mean twelve edits, twelve chances to break a working quest, and twelve places to keep the
-- amounts in sync. Instead the client only ANNOUNCES "quest <id> finished" and this script decides -- once --
-- whether that is worth anything.
--
-- ===== THE SECURITY POSTURE, STATED PLAINLY =====
-- The claim arrives from the client, so a crafted call can claim a quest the player never played. Two things
-- make that acceptable rather than a hole:
--   * IT IS PAID ONCE, EVER, per quest per player, and the ledger is persisted. The entire exploit is worth
--     one full clear of CrateTokens.ISLAND_TASK -- the same total an honest player earns -- and then it is
--     worth nothing, forever. (The figure quoted here used to be 1,850, which was the pre-rescale ladder;
--     it is derived at the boot print below rather than written down twice.)
--   * The realm ALREADY trusts the client for the much larger prize: CoinEvent grants coins on the client's
--     word (FlightEconomy), and the quests pay their coin rewards through it. This adds no new class of
--     exposure; it adds a strictly BOUNDED one.
-- If quest completion ever moves server-side, delete the remote and call awardIslandTask() directly -- the
-- ledger, the cap and the celebration all keep working untouched.
--
-- ===== THE LEDGER IS ITS OWN DATASTORE =====
-- CandyRealm's PlayerState owns "CrateState_v1" (crate cosmetics) and the food game owns its own save. This
-- keeps a third, tiny store rather than wedging a field into either -- a schema change here can never corrupt
-- a save that matters, and a failed read degrades to "not claimed yet" rather than to a broken join.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")
local RunService        = game:GetService("RunService")

if _G.__IslandTaskTokensServer then
	warn("[IslandTask] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__IslandTaskTokensServer = true

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local CrateTokens  = require(Shared:WaitForChild("CrateTokens"))
local IslandConfig = require(Shared:WaitForChild("IslandConfig"))

local STORE_NAME = "CandyIslandTasks_v1"
local store = nil
do
	local ok, ds = pcall(function() return DataStoreService:GetDataStore(STORE_NAME) end)
	if ok then
		store = ds
	else
		warn("[IslandTask] DataStore unavailable (" .. tostring(ds)
			.. ") -- island task tokens will not persist this session")
	end
end

--======================================================================
-- REMOTES
--======================================================================
local function remote(name, class)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then r = Instance.new(class or "RemoteEvent"); r.Name = name; r.Parent = ReplicatedStorage end
	return r
end
local ClaimEvent  = remote("ClaimIslandTaskTokens")   -- c->s: (questId)
local RewardEvent = remote("IslandTaskRewardEvent")   -- s->c: (questId, questName, tokens)

--======================================================================
-- LEDGER
--======================================================================
-- [player] = { [questId] = true }  -- loaded on join, written through on every successful claim.
local claimed = {}
Players.PlayerRemoving:Connect(function(p) claimed[p] = nil end)

local function key(userId) return "u_" .. tostring(userId) end

local function load(player)
	local data
	if store then
		local ok, res = pcall(function() return store:GetAsync(key(player.UserId)) end)
		if ok and type(res) == "table" then
			data = res
		elseif not ok then
			-- Degrade to "nothing claimed". The write path uses UpdateAsync against the STORED value, so a
			-- failed read can never cause a double-pay: the update function sees the real ledger.
			warn("[IslandTask] ledger read failed for " .. player.Name .. ": " .. tostring(res))
		end
	end
	claimed[player] = data or {}
end

Players.PlayerAdded:Connect(load)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(load, p) end

--======================================================================
-- THE LEDGER IS THE QUEST SAVE (and, through it, the food-stand gate)
--======================================================================
-- CandyRealm persists NOTHING about the economy -- coins, CurrentPower and StomachMax are
-- all rebuilt by ensureStats on every join. This ledger IS persisted. Under the food-realm
-- port it no longer funds or restores guts (those are bought with flight coins); what it
-- still drives is GutProgression's UnlockedSlot attribute -- the FOOD STAND gate on every
-- island, the journal's ticks and the wormhole rows. These two accessors are that read path.
--
-- ready(player) is separate from claimed() on purpose: "no ledger yet" and "ledger says no"
-- are different answers, and a slow DataStore read must only ever LOCK a stand, never open one.
local function ledgerReady(player)
	return claimed[player] ~= nil
end
local function ledgerHas(player, questId)
	local mine = claimed[player]
	return (mine ~= nil) and (mine[tostring(questId or "")] == true)
end
_G.islandTaskLedgerReady = ledgerReady
_G.islandTaskClaimed     = ledgerHas

--[[
	WIPE THE LEDGER FOR A REBIRTH.

	Rebirth is "redo everything": it already clears Space / Dino / Candy realm completion so
	those realms must be re-beaten. Under the space economy this ledger is ALSO the candy
	tower's progression save, so leaving it intact would make a rebirth unplayable rather than
	just hard -- the rebirthed player is reset to tier 1 (maxPower 0, cannot fly, cannot earn),
	while every quest still reads as claimed, so nothing can ever fund a gut again. On their
	next join GutProgression would then restore the whole tower and quietly undo the rebirth.
	Neither outcome is a rebirth.

	THE COST, STATED PLAINLY: the tokens for those quests become re-earnable, once per
	rebirth. That is a real fountain, and it is accepted deliberately -- a rebirth costs
	re-beating three realms and the whole climb, so the loop is far more expensive than the
	750 tokens it returns. If that trade ever stops being worth it, the fix is to split this
	table in two (a permanent `paid` set for tokens, a resettable `done` set for progression)
	rather than to stop wiping, because not wiping is the broken case.
]]
local function resetForRebirth(player)
	claimed[player] = {}
	if store then
		local ok, err = pcall(function() store:SetAsync(key(player.UserId), {}) end)
		if not ok then
			warn("[IslandTask] rebirth ledger wipe FAILED for " .. player.Name .. ": " .. tostring(err)
				.. " -- their tower progression is still recorded, so the rebirth will not stick")
			return false
		end
	end
	if _G.refreshGutUnlock then pcall(_G.refreshGutUnlock, player) end
	print(("[IslandTask] %s rebirthed -- island quest ledger wiped, the whole tower is replayable")
		:format(player.Name))
	return true
end
_G.islandTaskResetForRebirth = resetForRebirth

--======================================================================
-- AWARD
--======================================================================
-- Returns the number of tokens actually granted (0 if already claimed / unknown quest / award refused).
local function awardIslandTask(player, questId)
	questId = tostring(questId or "")
	local amount = CrateTokens.islandTaskReward(questId)
	if amount <= 0 then return 0 end                      -- not a paying quest id

	local mine = claimed[player]
	if not mine then return 0 end                          -- ledger not loaded yet: refuse rather than guess
	if mine[questId] then return 0 end                      -- already paid, in memory

	-- THE STORED LEDGER IS THE AUTHORITY, not the in-memory copy. UpdateAsync reads the live value and we
	-- decide inside the transform, so two servers racing the same claim cannot both pay.
	local alreadyStored = false
	if store then
		local ok, err = pcall(function()
			store:UpdateAsync(key(player.UserId), function(old)
				local t = (type(old) == "table") and old or {}
				if t[questId] then alreadyStored = true; return nil end -- abort the write, keep the value
				t[questId] = true
				return t
			end)
		end)
		if not ok then
			-- IN STUDIO, DEGRADE TO MEMORY. Studio blocks DataStore writes unless "Enable Studio
			-- Access to API Services" is ticked, so every claim fails here -- and under the space
			-- economy that used to mean the GUT PAYOUT never ran either, leaving a tester grounded
			-- at tier 1 with maxPower 0 and no way to earn a tank. The whole realm was untestable
			-- in Studio for a reason that has nothing to do with the game.
			-- Memory-only is exactly what this file already does when `store` is nil (see the boot
			-- note about Studio); a rejected write is the same situation, so treat it the same.
			if RunService:IsStudio() then
				warn("[IslandTask] ledger write blocked in Studio for " .. player.Name .. " / " .. questId
					.. " -- granting anyway, MEMORY ONLY (it resets when you stop the playtest). "
					.. "Tick Game Settings > Security > Enable Studio Access to API Services to persist it.")
			else
				-- LIVE: do NOT pay what we could not record. A transient DataStore failure must never
				-- hand out a second payout on the next server.
				warn("[IslandTask] ledger write failed for " .. player.Name .. " / " .. questId .. ": " .. tostring(err))
				return 0
			end
		end
		if alreadyStored then
			mine[questId] = true                            -- resync memory and move on quietly
			return 0
		end
	end
	mine[questId] = true

	local granted = 0
	if _G.crateTokensAward then
		local ok, n = pcall(_G.crateTokensAward, player, "islandTask", questId)
		if ok then granted = tonumber(n) or 0 end
	else
		warn("[IslandTask] SkinCrateService has not published _G.crateTokensAward -- no tokens granted")
	end

	-- ===== THE FART-POWER TOP-UP =====
	-- Some quests advertise "coins AND fart power" on their reward card. The coins go through
	-- CoinEvent from the client like every other payout; the POWER is granted here instead,
	-- because this is the only place in the realm that already knows a quest was finished for
	-- the first time. Hanging it off the ledger rather than a new remote means it inherits the
	-- once-ever guarantee for free -- there is nothing extra to rate-limit or validate.
	--
	-- CLAMPED TO THE PLAYER'S TANK. CurrentPower above StomachMax is not a bigger reward, it is
	-- a broken flight: the HUD bar overflows and BuyFood's "stomach full" check starts refusing
	-- purchases the player can see they can afford.
	local power = CrateTokens.islandTaskPower and CrateTokens.islandTaskPower(questId) or 0
	if power > 0 then
		local ls = player:FindFirstChild("leaderstats")
		local cp = ls and ls:FindFirstChild("CurrentPower")
		local sm = ls and ls:FindFirstChild("StomachMax")
		if cp and sm then
			local before = cp.Value
			cp.Value = math.min(sm.Value, cp.Value + power)
			print(("[IslandTask] %s -> +%d fart power (%d -> %d, tank %d)")
				:format(player.Name, cp.Value - before, before, cp.Value, sm.Value))
		end
	end

	-- ===== NO GUT PAYOUT ANY MORE (food-realm port) =====
	-- Under the space port this is where a quest paid EXACTLY the next gut's cost and unlocked
	-- its purchase (the "two-purse" economy). Guts are now bought out of flight coins and gated
	-- by the island reached, so a quest is worth its own coin reward (paid by the quest client
	-- through CoinEvent) plus the tokens above -- nothing here touches Coins or StomachMax.
	--
	-- What a first-ever completion still does is advance the persisted quest ledger, which is
	-- what GutProgression publishes as UnlockedSlot -- the FOOD STAND gate, the journal ticks
	-- and the wormhole rows. Re-publish it now so the stand opens without a rejoin.
	if IslandConfig.BY_QUEST[questId] and _G.refreshGutUnlock then
		pcall(_G.refreshGutUnlock, player)
	end

	if granted > 0 and _G.badgeIslandQuest then pcall(_G.badgeIslandQuest, player, questId) end
	return granted
end
_G.awardIslandTask = awardIslandTask   -- so a future server-side quest can call it directly

--======================================================================
-- CLAIM
--======================================================================
local lastClaim = {}   -- [player] = os.clock(); a trivial throttle so a spinning client cannot hammer the store
Players.PlayerRemoving:Connect(function(p) lastClaim[p] = nil end)

ClaimEvent.OnServerEvent:Connect(function(player, questId)
	if type(questId) ~= "string" then return end
	local now = os.clock()
	if lastClaim[player] and (now - lastClaim[player]) < 0.5 then return end
	lastClaim[player] = now

	local granted = awardIslandTask(player, questId)
	if granted > 0 then
		local name = CrateTokens.ISLAND_TASK_NAME and CrateTokens.ISLAND_TASK_NAME[questId] or questId
		pcall(function() RewardEvent:FireClient(player, questId, name, granted) end)
		print(("[IslandTask] %s finished '%s' -> +%d crate tokens"):format(player.Name, questId, granted))
	end
end)

--======================================================================
local total = CrateTokens.islandTaskTotal()
local n = 0
for _ in pairs(CrateTokens.ISLAND_TASK) do n += 1 end
if RunService:IsStudio() and not store then
	print("[IslandTask] NOTE: no DataStore in Studio (Game Settings > Security > Enable Studio Access to API "
		.. "Services). Tokens still grant, but the once-ever ledger resets every run.")
end
-- The "= 5 Starter + 1 Premium" promise is about the CLIMB -- CrateTokens' ladder is solved so the twelve
-- quests on the tower total exactly 750. The three off-ladder islands (16/18/19) are extra on top and were
-- never part of that sum, so quoting the grand total here read as the promise being overshot by a third.
print(("[IslandTask] ready -- %d island quests, %d tokens in total; the 12 on the climb are the solved 750 "
	.. "(= 5 Starter + 1 Premium crate) and the rest is the off-ladder islands. Paid once each, ever.")
	:format(n, total))
