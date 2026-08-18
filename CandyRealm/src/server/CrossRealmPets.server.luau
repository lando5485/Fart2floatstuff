--======================================================================
-- CrossRealmPets.server.luau  (ServerScriptService.CrossRealmPets)  -- CandyRealm
--======================================================================
-- Hands the client the pets the player's TELEPORT CARRIED IN, so the hub can show the FOOD realm and
-- DINO realm collections read-only alongside Candy's own.
--
-- ===== WHY THIS EXISTS =====
-- RealmServer.server.luau reads the teleport payload for the entry guard, but its "read the carried
-- fields here" section is still a stub -- `data.pets` appears only in a comment. So nothing in this place
-- has ever looked at the pets the Food Realm packs, and the hub had no way to know what you own
-- elsewhere. This is the smallest thing that closes that: read, sanitise, publish. It writes nothing and
-- grants nothing.
--
-- ===== WHAT THE FOOD REALM ACTUALLY SENDS =====
-- RealmPortals.server.lua's buildTransferPayload packs `ownedPets` (from _G.playerOwnedPets) and
-- `equippedPet`. When the richer RealmTransfer module is present it may pack more under other keys, so
-- several spellings are accepted below rather than betting on one.
--
-- Keys inside the pet table are petId, or petId.."#R" for a rare variant -- both can be owned at once and
-- the hub gives each its own card, exactly as the Dino Realm's FOOD tab does.
--
-- ===== READ-ONLY, AND THAT IS THE POINT =====
-- These pets cannot be equipped, levelled or traded HERE -- their catalogs do not exist in this place.
-- The hub shows them so the collection reads as ONE collection across the realms, and every locked card
-- points the player back to the realm that actually owns that pet. Nothing here can create a pet, so a
-- forged payload buys an exploiter a picture of a pet on a read-only page and nothing else. That is why
-- this is allowed to trust TeleportData at all.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENT_NAME = "CrossRealmPetsEvent" -- s->c: (table) { food = {...}, dino = {...} }
local FUNC_NAME  = "CrossRealmPetsFunc"  -- c->s RF: () -> the same table, for a client that loaded late

local function ensure(className: string, name: string)
	local e = ReplicatedStorage:FindFirstChild(name)
	if not e then
		e = Instance.new(className)
		e.Name = name
		e.Parent = ReplicatedStorage
	end
	return e
end

local PetsEvent = ensure("RemoteEvent", EVENT_NAME)
local PetsFunc  = ensure("RemoteFunction", FUNC_NAME)

local carried = {} -- [player] = { food = {...}, dino = {...} }

-- SANITISE, ALWAYS. This came off a teleport payload, so treat every field as hostile: cap the number of
-- entries, keep only string keys, and copy out only the three numeric fields the hub renders. A malformed
-- or malicious table then cannot reach the UI as anything but a short list of small numbers.
local MAX_ENTRIES = 64

local function cleanPetTable(src)
	local out = {}
	if type(src) ~= "table" then return out end
	local n = 0
	for key, v in pairs(src) do
		if n >= MAX_ENTRIES then break end
		if type(key) == "string" and #key <= 64 and type(v) == "table" then
			n += 1
			out[key] = {
				level = math.clamp(math.floor(tonumber(v.level) or 1), 1, 25),
				xp    = math.max(0, math.floor(tonumber(v.xp) or 0)),
				count = math.clamp(math.floor(tonumber(v.count) or 1), 1, 9999),
			}
		end
	end
	return out
end

-- The Food Realm's own key is `ownedPets`; the others are what the richer RealmTransfer module and the
-- Dino payload have used. First non-empty wins, so adding a realm later is one more string here.
local FOOD_KEYS = { "ownedPets", "pets", "foodPets" }
local DINO_KEYS = { "dinoPets", "dinosaurPets", "arrivedDinoPets" }

local function firstTable(data, keys)
	for _, k in ipairs(keys) do
		local t = data[k]
		if type(t) == "table" and next(t) ~= nil then return t end
	end
	return nil
end

local function readCarried(player)
	local ok, jd = pcall(function() return player:GetJoinData() end)
	local data = ok and jd and jd.TeleportData
	if type(data) ~= "table" then
		return { food = {}, dino = {} }
	end
	return {
		food = cleanPetTable(firstTable(data, FOOD_KEYS)),
		dino = cleanPetTable(firstTable(data, DINO_KEYS)),
	}
end

local function countOf(t)
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

-- ===== THE SPECIES SET FOR SKIN EQUIPPING =====
-- SkinCrateService gates "can this player WEAR this skin" on owning the pet species -- via
-- _G.playerOwnedPets, which nothing in Candy fills. Left alone, every skin a crate rolls here would say
-- "Unlock <Pet> to equip" forever, making the whole crate catalog cosmetically dead in this realm.
--
-- So the pets the teleport carried in are published as a SEPARATE ownership set, and SkinCrateService
-- consults it alongside the empty one. Deliberately NOT merged into _G.playerOwnedPets itself: that global
-- also feeds the live trade window, and carried pets are not persisted by this realm -- letting them into
-- trade would let a pet be given away here and still exist at home. A dedicated read-only set gives skins
-- their unlock and gives trade nothing.
_G.crossRealmCarriedPets = _G.crossRealmCarriedPets or {} -- [player] = { [petKey] = true }

local function onPlayer(player)
	local got = readCarried(player)
	carried[player] = got

	local keys = {}
	for k in pairs(got.food) do keys[k] = true end
	for k in pairs(got.dino) do keys[k] = true end -- harmless: no skin names a dino species, today
	_G.crossRealmCarriedPets[player] = keys
	print(("[CrossRealmPets] %s carried in %d food pet(s), %d dino pet(s)")
		:format(player.Name, countOf(got.food), countOf(got.dino)))

	-- PUSH, and keep pushing for a bit. The client half lives in StarterPlayerScripts and may not have
	-- connected its listener yet when this runs -- a single fire into the void would leave the hub
	-- permanently empty for a player who genuinely does own pets. The RemoteFunction below covers the
	-- same gap from the other side; between them a late client always gets its data.
	task.spawn(function()
		for _ = 1, 5 do
			if not player.Parent then return end
			pcall(function() PetsEvent:FireClient(player, got) end)
			task.wait(1)
		end
	end)
end

PetsFunc.OnServerInvoke = function(player)
	return carried[player] or { food = {}, dino = {} }
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, p) end -- Studio Play Solo / live reload

Players.PlayerRemoving:Connect(function(player)
	carried[player] = nil
	_G.crossRealmCarriedPets[player] = nil
end)

print("[CrossRealmPets] ready -- publishing the Food/Dino pets carried in by teleport (read-only)")
