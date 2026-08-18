--======================================================================
-- SkinPersistence.server.luau  (ServerScriptService.SkinPersistence)  -- CandyRealm
--======================================================================
-- THE MISSING HALF OF THE SKIN ECONOMY. SkinCrateService was ported from realm 1 complete with its save
-- calls (`_G.savePlayerData(player, "crate_open")` after every grant) and its load handshake
-- (`_G.skinCrateApplyOnJoin`) -- but in realm 1 both ends live in PlayerStats.server.lua, which was never
-- ported. So in Candy every save call was a pcall into nil and nothing ever called the apply: tokens,
-- crate pulls, equipped skins and the Collection Book all lived exactly one session. Spend real tokens on
-- a spin, rejoin, own nothing.
--
-- This file is that missing half, scoped to what SkinCrateService actually owns. Same four fields, same
-- shapes, same names as realm 1's PlayerStats writes (saved.crateTokens / petSkins / equippedSkins /
-- collection), so a future migration in either direction is a straight copy:
--
--   crateTokens    number                                   _G.playerCrateTokens[player]
--   petSkins       ["Pet|Skin|Trait"] = duplicate count     _G.playerPetSkins[player]
--   equippedSkins  { [petId] = { skin=, trait= } }          _G.playerEquippedSkins[player]
--   collection     { completedPets, titles, auras,
--                    activeTitle, activeAura, full }        _G.playerCollection[player]
--
-- ===== ORDER OF EVENTS ON JOIN =====
-- Load (with retries) -> MERGE the pre-load session state in -> write the globals -> ensure the
-- leaderstat exists -> call _G.skinCrateApplyOnJoin, which mirrors the balance and pushes state.
--
-- The MERGE matters: other systems (island-task token awards, a fast first crate) can credit the player in
-- the seconds before the DataStore answers. Overwriting the globals with the loaded blob would silently
-- eat those. Tokens add; skin counts add; equips/collection prefer the loaded copy only where the session
-- has none.
--
-- ===== WHY UpdateAsync AND A THROTTLE =====
-- SkinCrateService fires savePlayerData on every grant, equip and trade -- a crate-opening spree would be
-- a SetAsync per click, straight into the 6s-per-key write limit. Saves are therefore throttled per
-- player (a trailing save catches the last state), and the write is UpdateAsync so a half-loaded session
-- can never clobber a richer save with an emptier one -- the merge-down rule inside refuses to shrink.
--
-- In Studio without API access every call fails; that is logged once and the realm runs session-only,
-- exactly as it did before this file existed.
--======================================================================

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService       = game:GetService("RunService")

local STORE_NAME    = "CandySkinState_v1"
local SAVE_INTERVAL = 8    -- seconds between writes per player; Roblox's own per-key limit is 6
local MAX_ENTRIES   = 600  -- inventory-key cap on load; far above any legitimate collection

local store
do
	local ok, s = pcall(function() return DataStoreService:GetDataStore(STORE_NAME) end)
	if ok then store = s else warn("[SkinPersist] DataStore unavailable -- skin state will not persist this session") end
end

-- The globals SkinCrateService owns (created there; the `or {}` covers whichever script loads first).
_G.playerCrateTokens   = _G.playerCrateTokens   or {}
_G.playerPetSkins      = _G.playerPetSkins      or {}
_G.playerEquippedSkins = _G.playerEquippedSkins or {}
_G.playerCollection    = _G.playerCollection    or {}

--======================================================================
-- SANITISE (loads come from a DataStore; treat every field as suspect)
--======================================================================
local function num(v, lo, hi)
	return math.clamp(math.floor(tonumber(v) or 0), lo, hi)
end

local function cleanSkins(t)
	local out, n = {}, 0
	if type(t) ~= "table" then return out end
	for key, count in pairs(t) do
		if n >= MAX_ENTRIES then break end
		if type(key) == "string" and #key <= 120 then
			local c = num(count, 0, 9999)
			if c > 0 then out[key] = c; n += 1 end
		end
	end
	return out
end

local function cleanEquips(t)
	local out = {}
	if type(t) ~= "table" then return out end
	for petId, e in pairs(t) do
		if type(petId) == "string" and type(e) == "table" and type(e.skin) == "string" then
			out[petId] = { skin = e.skin, trait = (type(e.trait) == "string") and e.trait or nil }
		end
	end
	return out
end

local function cleanStrSet(t)
	local out = {}
	if type(t) ~= "table" then return out end
	for k, v in pairs(t) do
		if type(k) == "string" and v then out[k] = true end
	end
	return out
end

local function cleanCollection(t)
	if type(t) ~= "table" then t = {} end
	return {
		completedPets = cleanStrSet(t.completedPets),
		titles        = cleanStrSet(t.titles),
		auras         = cleanStrSet(t.auras),
		activeTitle   = (type(t.activeTitle) == "string") and t.activeTitle or "",
		activeAura    = (type(t.activeAura) == "string") and t.activeAura or "",
		full          = t.full == true,
	}
end

--======================================================================
-- SNAPSHOT (the in-memory truth, in the exact saved shape)
--======================================================================
local function snapshot(player)
	local eq = {}
	for petId, e in pairs(_G.playerEquippedSkins[player] or {}) do
		if type(e) == "table" and type(e.skin) == "string" then
			eq[petId] = { skin = e.skin, trait = (type(e.trait) == "string") and e.trait or nil }
		end
	end
	local c = _G.playerCollection[player] or {}
	return {
		v             = 1,
		crateTokens   = num(_G.playerCrateTokens[player], 0, 1e9),
		petSkins      = cleanSkins(_G.playerPetSkins[player]),
		equippedSkins = eq,
		collection    = cleanCollection(c),
	}
end

--======================================================================
-- SAVE (throttled per player, trailing write, UpdateAsync)
--======================================================================
local loaded    = {} -- [userId] = true once the join load finished (saves before that are refused -- see below)
local lastSave  = {} -- [userId] = os.clock() of the last write
local savePend  = {} -- [userId] = true while a trailing save is scheduled
local leftAt    = {} -- [userId] = snapshot taken at PlayerRemoving (the player object dies with the leave)

local function writeNow(userId, snap, reason)
	if not store then return false end
	local ok, err = pcall(function()
		store:UpdateAsync("u_" .. userId, function()
			-- The snapshot IS the truth: it was taken from the live session, which itself started from this
			-- key. Nothing else writes this store, so there is no sibling state to merge with here.
			return snap
		end)
	end)
	if ok then
		lastSave[userId] = os.clock()
	else
		warn(("[SkinPersist] save failed for %d (%s): %s"):format(userId, tostring(reason), tostring(err)))
	end
	return ok
end

-- REASONS THAT MUST NOT WAIT. The throttle exists for crate-opening sprees; these are different in kind:
--   * "trade"           -- items just moved BETWEEN two players. Realm 1 saves both sides immediately for
--                          exactly this reason: the gap between the swap and the next save is the one
--                          window where a server crash hands one side both halves of the deal.
--   * "tokens_purchase" / "coinpack" -- real Robux went through ProcessReceipt. The receipt is already
--                          answered PurchaseGranted, so a crash before the save silently eats a purchase.
-- These write straight through; if the immediate write fails (throttled by Roblox, transient error), they
-- fall back onto the normal trailing save rather than being lost.
local URGENT = { trade = true, tokens_purchase = true, coinpack = true }

_G.savePlayerData = function(player, reason)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local userId = player.UserId
	-- NEVER SAVE BEFORE THE LOAD LANDED. A crate opened in the pre-load window would snapshot a session
	-- that does not yet contain the loaded inventory -- and write that emptiness over the real save. The
	-- merge on load folds that early grant in; this refusal keeps the store safe until it has.
	if not loaded[userId] then return end

	local now = os.clock()
	if URGENT[tostring(reason)] then
		-- Unthrottled: snapshot and write this instant. Two players trading are two different keys, so the
		-- pair of urgent writes a trade fires cannot contend with each other.
		if writeNow(userId, snapshot(player), reason) then return end
		-- immediate write refused/failed -> fall through so the trailing save still lands it
	end
	if now - (lastSave[userId] or 0) >= SAVE_INTERVAL then
		writeNow(userId, snapshot(player), reason)
	elseif not savePend[userId] then
		-- trailing save: the LAST state inside a burst wins, one write for the whole spree
		savePend[userId] = true
		task.delay(SAVE_INTERVAL, function()
			savePend[userId] = nil
			if player.Parent then
				writeNow(userId, snapshot(player), tostring(reason) .. "+trailing")
			end
		end)
	end
end

--======================================================================
-- LOAD (with merge -- see the header)
--======================================================================
local function loadFor(player)
	local userId = player.UserId
	local saved
	if store then
		for attempt = 1, 3 do
			local ok, data = pcall(function() return store:GetAsync("u_" .. userId) end)
			if ok then saved = data; break end
			if attempt == 1 then
				warn(("[SkinPersist] load failed for %s (retrying): %s"):format(player.Name, tostring(data)))
			end
			task.wait(attempt * 2)
			if not player.Parent then return end
		end
	end
	if not player.Parent then return end
	saved = (type(saved) == "table") and saved or {}

	-- MERGE the pre-load session in (tokens earned / skins pulled while the DataStore was answering).
	local preTokens = num(_G.playerCrateTokens[player], 0, 1e9)
	local preSkins  = _G.playerPetSkins[player] or {}

	local skins = cleanSkins(saved.petSkins)
	for key, count in pairs(cleanSkins(preSkins)) do
		skins[key] = (skins[key] or 0) + count
	end

	_G.playerCrateTokens[player]   = num(saved.crateTokens, 0, 1e9) + preTokens
	_G.playerPetSkins[player]      = skins
	-- equips/collection: a seconds-old session has none of either, so loaded wins outright; the defensive
	-- fallback only matters if apply somehow ran twice.
	_G.playerEquippedSkins[player] = next(_G.playerEquippedSkins[player] or {}) and _G.playerEquippedSkins[player]
		or cleanEquips(saved.equippedSkins)
	_G.playerCollection[player]    = cleanCollection(saved.collection)

	-- THE LEADERSTAT. Realm 1's PlayerStats creates leaderstats.CrateTokens; nothing in Candy did, which is
	-- the same bug Space had -- the balance existed but nothing on screen could show it going up or down.
	do
		local ls = player:FindFirstChild("leaderstats")
		if not ls then ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player end
		if not ls:FindFirstChild("CrateTokens") then
			local st = Instance.new("IntValue"); st.Name = "CrateTokens"
			st.Value = _G.playerCrateTokens[player]; st.Parent = ls
		end
	end

	loaded[userId] = true

	-- Hand off to SkinCrateService exactly the way realm 1's PlayerStats does. Polled because script boot
	-- order is not guaranteed; if the service truly never comes up the state is still loaded and saves work.
	task.spawn(function()
		local deadline = os.clock() + 15
		while os.clock() < deadline do
			if _G.skinCrateApplyOnJoin then
				pcall(_G.skinCrateApplyOnJoin, player)
				return
			end
			task.wait(0.25)
		end
		warn("[SkinPersist] skinCrateApplyOnJoin never appeared -- state loaded but not pushed to the client")
	end)

	print(("[SkinPersist] loaded %s: %d tokens, %d skin entr%s%s"):format(
		player.Name, _G.playerCrateTokens[player],
		(function() local n = 0; for _ in pairs(skins) do n += 1 end; return n end)(),
		(function() local n = 0; for _ in pairs(skins) do n += 1 end; return n == 1 and "y" or "ies" end)(),
		(preTokens > 0) and (" (+%d pre-load tokens merged)"):format(preTokens) or ""))
end

Players.PlayerAdded:Connect(function(p) task.spawn(loadFor, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(loadFor, p) end -- Studio Play Solo / live reload

--======================================================================
-- LEAVE + SHUTDOWN
--======================================================================
Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	if loaded[userId] then
		-- Snapshot NOW (the globals are keyed by the player object and are about to be cleaned up by their
		-- owners), write unthrottled -- the leave is the one save that must not be deferred.
		leftAt[userId] = snapshot(player)
		task.spawn(function()
			writeNow(userId, leftAt[userId], "leave")
			leftAt[userId] = nil
		end)
	end
	loaded[userId] = nil
	savePend[userId] = nil
end)

game:BindToClose(function()
	if RunService:IsStudio() and not store then return end
	-- Synchronous on purpose: BindToClose is the last chance, and returning early abandons the writes.
	for _, player in ipairs(Players:GetPlayers()) do
		if loaded[player.UserId] then
			pcall(writeNow, player.UserId, snapshot(player), "shutdown")
		end
	end
end)

print(("[SkinPersist] ready -- tokens/skins/equips/collection persist to %s (save >= every %ds per player)")
	:format(STORE_NAME, SAVE_INTERVAL))
