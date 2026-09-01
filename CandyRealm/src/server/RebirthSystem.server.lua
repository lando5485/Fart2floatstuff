--======================================================================
-- RebirthSystem.server.lua  (Script -> ServerScriptService)
--======================================================================
-- REBIRTH: once you've FINISHED the run -- reached the last island AND completed the Space + Dino realms --
-- you can rebirth. Your island run resets (coins, gut, back to Bean Farm) and the realms are WIPED so you
-- re-beat them next loop, but you keep a PERMANENT, stacking boost:
--     * +25% coins earned    (via _G.rebirthMult, applied in PlayerStats' CoinEvent)
--     * +3%  flight speed     (client reads the Rebirths leaderstat -> _G.rebirthSpeedMult in CoreClient)
--     * better rare-pet luck  (via _G.rebirthLuck, applied in PetSystem's rare roll)
-- KEPT across rebirth: pets (incl. any rarer ones you earn later), gamepasses, rebirth count + multiplier,
-- and lifetime totals (Total Coins Earned / Total Fart Power).
--
-- SERVER-AUTHORITATIVE: the client only asks for state or asks to rebirth; every requirement is checked here.
-- STUDIO: realms count as complete so you can actually TEST the button/HUD (a fresh test account could never
-- complete Space/Dino otherwise). Live servers check the real per-realm saves.
--======================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")
local RunService        = game:GetService("RunService")

--------------------------------------------------------------------------------
-- config (tunables)
--------------------------------------------------------------------------------
local COIN_PER   = 0.25  -- +25% coins per rebirth
local SPEED_PER  = 0.03  -- +3% flight speed per rebirth (kept here for docs; CoreClient reads the leaderstat)
local LUCK_PER   = 0.15  -- rare-pet odds divided by (1 + 0.15 * rebirths)
-- must have reached the SUMMIT to rebirth. This is a SLOT (climb position), not an island
-- model number: the tower scrambles the two, so "HighestIsland >= 14" was both wrong and
-- unreachable. The summit is the last slot in IslandOrder.
-- The summit slot. Read from IslandOrder so adding or removing a rung cannot leave the
-- rebirth requirement pointing at the wrong island -- the space-economy port took the tower
-- from 11 slots to 12, and a hard-coded 11 would have made rebirth available one island
-- early, before the Bake-Off.
local REQ_SLOT = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	:WaitForChild("IslandOrder")).COUNT

-- realm-completion stores (the SAME keys/fields RealmPortals.server reads)
local SPACE_STORE, SPACE_PLANETS = "SpaceRealm_PlayerState_v1", 8
local DINO_STORE                 = "DinoRealm_PlayerState_v1"
local CANDY_STORE                = "CandyRealm_PlayerState_v1"
local KEY_PREFIX                 = "Player_"

-- MUST match the new-player defaults in FlightEconomy/StomachUpgrade ensureStats -- so they
-- are read from the same Constants/StomachTiers rather than written down a third time.
-- Under the food-realm port the starting tank is tier 1's maxPower, 120 (the Gumdrop Belly):
-- a rebirthed player can fly at once and re-earns every gut out of flight coins. The ledger
-- wipe below re-locks the island FOOD STANDS behind their quests, which is the redo.
local SharedRB      = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ConstantsRB   = require(SharedRB:WaitForChild("Constants"))
local StomachTiersRB = require(SharedRB:WaitForChild("StomachTiers"))
local DEFAULT_COINS   = ConstantsRB.STARTING_COINS
local DEFAULT_STOMACH = StomachTiersRB.getTier(ConstantsRB.STARTING_STOMACH_TIER).maxPower

--------------------------------------------------------------------------------
-- wiring
--------------------------------------------------------------------------------
local store      = DataStoreService:GetDataStore("Rebirth_v1")
local spaceStore = DataStoreService:GetDataStore(SPACE_STORE)
local dinoStore  = DataStoreService:GetDataStore(DINO_STORE)
local candyStore = DataStoreService:GetDataStore(CANDY_STORE)

_G.rebirthMult = _G.rebirthMult or {} -- [player] = coin multiplier (read by PlayerStats CoinEvent)
_G.rebirthLuck = _G.rebirthLuck or {} -- [player] = rare-pet odds DIVISOR (read by PetSystem rare roll)

local rebirths = {} -- [player] = n
local busy     = {} -- [player] = true while a rebirth is processing

local function keyFor(uid) return KEY_PREFIX .. tostring(uid) end

local function getOrCreate(cls, name)
	local o = ReplicatedStorage:FindFirstChild(name)
	if not o then o = Instance.new(cls); o.Name = name; o.Parent = ReplicatedStorage end
	return o
end
local remote = getOrCreate("RemoteEvent", "RebirthEvent") -- client<->server: "state" | "rebirth" -> "state"/"result"

--------------------------------------------------------------------------------
-- requirement checks (fail CLOSED; Studio auto-passes the realms so the flow is testable)
--------------------------------------------------------------------------------
local function readField(dstore, uid, check)
	if RunService:IsStudio() then return true end -- TEST: realms count as done in Studio
	local ok, data = pcall(function() return dstore:GetAsync(keyFor(uid)) end)
	if not ok or type(data) ~= "table" then return false end
	return check(data) == true
end
local function spaceDone(uid)
	return readField(spaceStore, uid, function(d)
		return type(d.highestPlanetReached) == "number" and math.floor(d.highestPlanetReached) >= SPACE_PLANETS
	end)
end
local function dinoDone(uid)
	return readField(dinoStore, uid, function(d) return d.dinoComplete == true end)
end
local function candyDone(uid)
	return readField(candyStore, uid, function(d) return d.candyComplete == true end)
end
local function islandsDone(player)
	return math.floor(player:GetAttribute("HighestSlot") or 1) >= REQ_SLOT
end

local function coinMult(n)  return 1 + COIN_PER  * n end
local function speedMult(n) return 1 + SPEED_PER * n end
local function luckMult(n)  return 1 + LUCK_PER  * n end

local function reqTable(player)
	return { islands = islandsDone(player), space = spaceDone(player.UserId), dino = dinoDone(player.UserId), candy = candyDone(player.UserId) }
end

--------------------------------------------------------------------------------
-- apply the stacking boosts (globals + the Rebirths leaderstat, which drives flight speed on the client)
--------------------------------------------------------------------------------
local function applyBoosts(player)
	local n = rebirths[player] or 0
	_G.rebirthMult[player] = coinMult(n)
	_G.rebirthLuck[player] = luckMult(n)
	local ls = player:FindFirstChild("leaderstats")
	local rb = ls and ls:FindFirstChild("Rebirths")
	if rb then rb.Value = n end
	player:SetAttribute("Rebirths", n) -- replicates to every client -> RebirthTag draws it above the head
end

local function pushState(player)
	local n = rebirths[player] or 0
	local reqs = reqTable(player)
	pcall(function()
		remote:FireClient(player, "state", {
			rebirths = n,
			coinMult = coinMult(n), speedMult = speedMult(n), luckMult = luckMult(n),
			nextCoin = coinMult(n + 1), nextSpeed = speedMult(n + 1), nextLuck = luckMult(n + 1),
			reqs = reqs, reqIsland = REQ_SLOT,
			canRebirth = reqs.islands and reqs.space and reqs.dino and reqs.candy,
			petMilestones = (function()
				local t = {}
				if type(_G.REBIRTH_PET_MILESTONES) == "table" then
					for i, ms in ipairs(_G.REBIRTH_PET_MILESTONES) do t[i] = { req = ms.req, name = ms.name, owned = n >= ms.req } end
				end
				return t
			end)(),
		})
	end)
end

--------------------------------------------------------------------------------
-- the rebirth itself: wipe realms, reset the island run, respawn on Bean Farm
--------------------------------------------------------------------------------
local function wipeRealms(uid)
	-- "redo every rebirth" -> clear the completion fields so Space/Dino must be re-beaten. Best-effort; if the
	-- realms are a separate universe these writes just don't reach them (harmless).
	pcall(function() spaceStore:UpdateAsync(keyFor(uid), function(d) d = d or {}; d.highestPlanetReached = 0; return d end) end)
	pcall(function() dinoStore:UpdateAsync(keyFor(uid), function(d) d = d or {}; d.dinoComplete = false; return d end) end)
	pcall(function() candyStore:UpdateAsync(keyFor(uid), function(d) d = d or {}; d.candyComplete = false; return d end) end)
end

local function resetRun(player)
	wipeRealms(player.UserId) -- redo-every-rebirth: clear Space/Dino completion

	-- WIPE THE CANDY TOWER TOO. Under the space economy the island-quest ledger is this
	-- realm's progression save (every gut is funded and gated by one quest in it), so a
	-- rebirth that left it standing would strand the player at tier 1 with nothing left to
	-- fund a gut -- and GutProgression would restore the whole tower on their next join
	-- anyway. See islandTaskResetForRebirth for the trade-off this accepts.
	if type(_G.islandTaskResetForRebirth) == "function" then
		pcall(_G.islandTaskResetForRebirth, player)
	else
		warn("[Rebirth] IslandTaskTokens has not published _G.islandTaskResetForRebirth -- the "
			.. "candy tower will NOT reset and this rebirth will be undone on the next join")
	end
	player:SetAttribute("UnlockedGutTier", 1)
	player:SetAttribute("UnlockedSlot", 1)   -- the island lock resets with the guts
	if type(_G.rebirthResetHome) == "function" then
		_G.rebirthResetHome(player) -- PlayerStats owns home base + teleport + coins/gut/meter reset
		return
	end
	-- fallback if PlayerStats' hook isn't up yet (won't fix home island, but resets the visible stats)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local function setStat(name, v) local s = ls:FindFirstChild(name); if s then s.Value = v end end
	setStat("Coins", DEFAULT_COINS); setStat("Island", 1); setStat("StomachMax", DEFAULT_STOMACH); setStat("CurrentPower", 0)
	player:SetAttribute("HighestIsland", 1)
	-- HighestSlot is the CLIMB position, and it is what food unlocks, gut unlocks and
	-- the wormhole all gate on. Resetting only HighestIsland left a rebirthed player
	-- holding slot 13 -- every food and every gut buyable from the bottom island.
	player:SetAttribute("HighestSlot", 1)
	pcall(function() player:LoadCharacter() end)
end

local function persist(player)
	if RunService:IsStudio() then return end
	pcall(function() store:SetAsync(keyFor(player.UserId), { rebirths = rebirths[player] or 0 }) end)
end

remote.OnServerEvent:Connect(function(player, action)
	if action == "state" then pushState(player); return end
	if action ~= "rebirth" then return end
	if busy[player] then return end
	busy[player] = true

	local reqs = reqTable(player)
	if not (reqs.islands and reqs.space and reqs.dino and reqs.candy) then
		pcall(function() remote:FireClient(player, "result", false, "You haven't finished everything yet!") end)
		pushState(player); busy[player] = false; return
	end

	rebirths[player] = (rebirths[player] or 0) + 1
	applyBoosts(player) -- coin/luck globals + Rebirths leaderstat (flight speed) BEFORE the reset
	-- grant any rebirth MILESTONE PET the player now qualifies for (PetSystem owns the grant + models + HUD)
	if type(_G.REBIRTH_PET_MILESTONES) == "table" and type(_G.grantRebirthPet) == "function" then
		for _, ms in ipairs(_G.REBIRTH_PET_MILESTONES) do
			if rebirths[player] >= ms.req then pcall(_G.grantRebirthPet, player, ms.id) end
		end
	end
	persist(player)
	resetRun(player)    -- wipe islands + realms, respawn on Bean Farm

	pcall(function() remote:FireClient(player, "result", true,
		"\xF0\x9F\x94\x84 REBIRTH #" .. rebirths[player] .. "! Everything's a little stronger now.") end)
	pcall(function() remote:FireAllClients("announce", player.Name, rebirths[player]) end) -- server-wide "X rebirthed!" banner
	print(("[Rebirth] %s -> rebirth #%d (coins x%.2f, speed x%.2f, luck x%.2f)")
		:format(player.Name, rebirths[player], coinMult(rebirths[player]), speedMult(rebirths[player]), luckMult(rebirths[player])))

	task.wait(0.6); pushState(player)
	busy[player] = false
end)

--------------------------------------------------------------------------------
-- join / leave
--------------------------------------------------------------------------------
local function load(player)
	local n = 0
	if not RunService:IsStudio() then
		local ok, saved = pcall(function() return store:GetAsync(keyFor(player.UserId)) end)
		if ok and type(saved) == "table" then n = tonumber(saved.rebirths) or 0 end
	end
	rebirths[player] = n
end

local function ensureStat(player)
	local ls = player:WaitForChild("leaderstats", 30); if not ls then return end
	local rb = ls:FindFirstChild("Rebirths")
	if not rb then rb = Instance.new("IntValue"); rb.Name = "Rebirths"; rb.Parent = ls end -- shows on the leaderboard too
	rb.Value = rebirths[player] or 0
end

local function onAdded(player)
	load(player)
	task.spawn(function()
		ensureStat(player)
		applyBoosts(player)
		task.wait(3) -- let the client build
		pushState(player)
		-- catch-up: grant any milestone pets already earned (after the wait so PetSystem's ownedPets is loaded)
		if type(_G.REBIRTH_PET_MILESTONES) == "table" and type(_G.grantRebirthPet) == "function" then
			for _, ms in ipairs(_G.REBIRTH_PET_MILESTONES) do
				if (rebirths[player] or 0) >= ms.req then pcall(_G.grantRebirthPet, player, ms.id) end
			end
		end
	end)
end
Players.PlayerAdded:Connect(onAdded)
for _, p in ipairs(Players:GetPlayers()) do onAdded(p) end

Players.PlayerRemoving:Connect(function(p)
	persist(p)
	rebirths[p] = nil
	if _G.rebirthMult then _G.rebirthMult[p] = nil end
	if _G.rebirthLuck then _G.rebirthLuck[p] = nil end
end)
game:BindToClose(function() for _, p in ipairs(Players:GetPlayers()) do persist(p) end end)

print("[Rebirth] system ready -- finish islands + Space + Dino -> rebirth for +coins/speed/luck (REBIRTH side button)")
