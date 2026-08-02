--======================================================================
-- ReturnSender.server.luau  (Script)   [SENDING PLACE -- the DINO REALM]
--======================================================================
-- Put this Script in the DINO REALM place (ServerScriptService), beside ArrivalReceiver.
-- It is the SENDER half of the trip home, and the exact mirror of the islands' DinoRealmTeleport:
--
--     islands  --[DinoRealmTeleport / RealmPortals]-->  ArrivalReceiver   (arriving)
--     islands  <--[RealmReturnReceiver]--[THIS SCRIPT]--                  (going home)
--
-- THE PATTERN (do not deviate -- this is the secure shape, same as every other portal in the project):
--   1. CLIENT touches the return portal -> fires DinoReturnEvent:FireServer() with NO ARGUMENTS.
--      The client never says where to go, and never teleports itself.
--   2. SERVER (here) validates: has a home to go to + per-player debounce.
--   3. SERVER replies with a STATUS STRING ("traveling"/"nohome"/"error") for the client to render.
--   4. SERVER calls TeleportAsync with the payload. The islands read it back in RealmReturnReceiver.
--
--======================================================================
-- WHERE "HOME" COMES FROM
--======================================================================
-- This place does NOT hardcode the islands' placeId, and it shouldn't: two projects with the same magic
-- number in them drift apart the first time one is republished. Instead, the islands stamp `homePlaceId`
-- into the payload they send, ArrivalReceiver stashes it in _G.playerHomePlaceId, and we read it here.
-- The player goes back to the exact place they came from.
--
-- FALLBACK: somebody who opened the Dino Realm directly from the Roblox site never went through a portal,
-- so they have no stashed home. For them we use HOME_PLACE_ID below. It is 0 = unset out of the box, which
-- makes the portal answer "nohome" instead of teleporting somebody into the void -- fill it in with the
-- islands' placeId when you want direct-joiners to be able to travel to the islands too.
--
-- WHAT TRAVELS: the same cosmetic bundle that came in, plus `earned` -- the coins/tokens they picked up in
-- THIS realm. Deltas only. The islands' DataStore is the authority on their real balance, so we can say
-- "add 250" but never "your balance is 250" (that would wipe whatever they earned at home in the meantime).
--======================================================================
local Players         = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local DataStoreService = game:GetService("DataStoreService")

-- Only used for players who joined this place DIRECTLY (no portal, so no stashed home). 0 = unset.
local HOME_PLACE_ID = 0

-- Set by the ArrivalReceiver in this same place. Guarded in case script order ever flips.
_G.playerHomePlaceId = _G.playerHomePlaceId or {}
_G.playerEarnedHere  = _G.playerEarnedHere  or {}

-- getOrCreate, so a missing project entry can't break the remote. The client WaitForChild's this name.
local returnEvent = ReplicatedStorage:FindFirstChild("DinoReturnEvent")
if not returnEvent then
	returnEvent = Instance.new("RemoteEvent")
	returnEvent.Name = "DinoReturnEvent"
	returnEvent.Parent = ReplicatedStorage
end

local teleporting = {} -- [player] = true -- server-side debounce: never double-teleport

--======================================================================
-- "BEAT THE DINO REALM"  -- the flag that unlocks the CANDY REALM back home
--======================================================================
-- The islands' RealmPortals gates Candy behind DinoRealm_PlayerState_v1 -> dinoComplete == true, read from
-- the UNIVERSE-SCOPED DataStore (the only state shared between places -- TeleportData only moves when a
-- player does, and the portal has to know before they travel). Nothing has ever written that field, which
-- is why Candy has stayed locked. When your Dino gameplay decides the realm is beaten, call:
--
--     _G.dinoMarkComplete(player)
--
-- It is write-once and safe to call repeatedly. The store name + key prefix MUST match RealmPortals'.
local DINO_STORE = "DinoRealm_PlayerState_v1"
local KEY_PREFIX = "Player_"
local dinoStore = nil
do
	local ok, ds = pcall(function() return DataStoreService:GetDataStore(DINO_STORE) end)
	if ok then dinoStore = ds
	else warn("[DinoReturn] DataStore unavailable (" .. tostring(ds) .. ") -- completion can't be recorded this session") end
end

local markedComplete = {} -- [player] = true -- don't re-write the same flag every call

_G.dinoMarkComplete = function(player)
	if not player or markedComplete[player] then return end
	markedComplete[player] = true
	if not dinoStore then return end
	task.spawn(function()
		-- UpdateAsync, not SetAsync: this store may hold other Dino progress later, and a blind Set would
		-- stomp it. Merging into whatever is there keeps this script a good neighbour to its own future.
		local ok, err = pcall(function()
			dinoStore:UpdateAsync(KEY_PREFIX .. tostring(player.UserId), function(old)
				local d = (type(old) == "table") and old or {}
				d.dinoComplete = true
				d.completedAt  = os.time()
				return d
			end)
		end)
		print(("[DinoReturn] %s dinoComplete write: %s"):format(player.Name, ok and "ok" or ("err: " .. tostring(err))))
	end)
end

--======================================================================
-- SIZE GUARD  (a self-contained mirror of the islands' ReplicatedStorage/Shared/RealmTransfer -- this place
-- can't require that module, a place boundary is a hard wall, so the logic is copied. Keep them in step.)
--======================================================================
-- Roblox caps TeleportData, and going over does not truncate -- TeleportAsync THROWS, so the return portal
-- would break for exactly the players who have played the most. A completionist's skin inventory is
-- combinatorial (every pet x every skin x every trait is its own key), so measure and shed if needed.
-- Pets and the `earned` deltas are NEVER dropped -- they are the whole point of the trip home.
local HttpService = game:GetService("HttpService")
local BUDGET_BYTES = 28000

local function encodedSize(t)
	local ok, json = pcall(function() return HttpService:JSONEncode(t) end)
	if not ok then return math.huge end
	return #json
end

local function fit(payload, playerName)
	if encodedSize(payload) <= BUDGET_BYTES then return payload end

	if type(payload.petSkins) == "table" then -- duplicate counts matter least; which skins you OWN matters
		local flat = {}
		for k, v in pairs(payload.petSkins) do
			if (tonumber(v) or 0) > 0 then flat[k] = 1 end
		end
		payload.petSkins = flat
		warn(("[DinoReturn] %s payload oversized -- collapsed skin duplicate counts"):format(playerName))
		if encodedSize(payload) <= BUDGET_BYTES then return payload end
	end

	payload.collection    = nil -- re-derivable at home from the inventory already saved there
	payload.petMilestones = nil
	warn(("[DinoReturn] %s payload still oversized -- dropped collection + milestones"):format(playerName))
	if encodedSize(payload) <= BUDGET_BYTES then return payload end

	payload.petSkins      = nil -- last resort: the home save still has every skin, nothing is lost for good
	payload.equippedSkins = nil
	warn(("[DinoReturn] %s payload STILL oversized -- dropped the skin inventory"):format(playerName))
	return payload
end

--======================================================================
-- the payload
--======================================================================
local function buildReturnPayload(player)
	local function g(tbl, default)
		local t = _G[tbl]
		local v = t and t[player]
		if v == nil then return default end
		return v
	end

	local earned = _G.playerEarnedHere[player] or {}

	return fit({
		fromFartToFloat = true,          -- the marker every receiver in the project checks
		returningHome   = true,          -- ⚠ what tells RealmReturnReceiver this is a trip HOME, not an arrival
		payloadVersion  = 1,
		fromPlaceId     = game.PlaceId,
		fromRealm       = "dino",
		userId          = player.UserId, -- the far side refuses a payload stamped for somebody else
		sentAt          = os.time(),

		-- The cosmetic bundle, carried back so anything unlocked/levelled/equipped here survives the trip.
		-- The islands MERGE these (union + max), so re-sending state they already have is harmless.
		ownedPets       = g("playerOwnedPets", {}),
		equippedPet     = g("playerEquippedPet", nil),
		petSkins        = g("playerPetSkins", {}),
		equippedSkins   = g("playerEquippedSkins", {}),
		collection      = g("playerCollection", {}),
		petMilestones   = g("playerPetMilestones", {}),
		title           = g("playerTitle", nil),
		ownedGutSkins   = g("playerOwnedGutSkins", { Default = true }),
		equippedGutSkin = g("playerEquippedGutSkin", "Default"),

		-- CURRENCY: deltas ONLY. Note we do NOT send crateTokens as an absolute here -- the islands would
		-- have to guess which part of it was new. `earned` is unambiguous: this is what they picked up in
		-- the Dino Realm, add it.
		earned = {
			coins       = math.max(0, math.floor(tonumber(earned.coins) or 0)),
			crateTokens = math.max(0, math.floor(tonumber(earned.crateTokens) or 0)),
		},
	}, player.Name)
end

--======================================================================
-- the teleport
--======================================================================
local function homePlaceFor(player)
	local stashed = tonumber(_G.playerHomePlaceId[player])
	if stashed and stashed > 0 then return stashed end
	if HOME_PLACE_ID > 0 then return HOME_PLACE_ID end
	return nil
end

returnEvent.OnServerEvent:Connect(function(player)
	if not player or teleporting[player] then return end

	local placeId = homePlaceFor(player)
	if not placeId then
		-- They never came through a portal and no fallback is configured. Say so plainly rather than
		-- teleporting them somewhere arbitrary.
		print("[DinoReturn] " .. player.Name .. " has no home place (direct join + HOME_PLACE_ID unset)")
		pcall(function() returnEvent:FireClient(player, "nohome") end)
		return
	end

	teleporting[player] = true
	pcall(function() returnEvent:FireClient(player, "traveling") end)
	task.wait(1.2) -- brief deliberate pause so the transition reads as intentional, THEN teleport
	if not player.Parent then teleporting[player] = nil; return end -- they left during the pause

	local ok, err = pcall(function()
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData(buildReturnPayload(player))
		TeleportService:TeleportAsync(placeId, { player }, options)
	end)

	print(("[DinoReturn] teleport %s -> home (placeId %d): %s")
		:format(player.Name, placeId, ok and "ok" or ("err: " .. tostring(err))))

	if not ok then
		teleporting[player] = nil -- failed -> let them retry
		pcall(function() returnEvent:FireClient(player, "error") end)
	end
end)

Players.PlayerRemoving:Connect(function(p)
	teleporting[p]     = nil
	markedComplete[p]  = nil
end)

print("[DinoReturn] return sender ready (fallback home placeId " .. HOME_PLACE_ID ..
	" -- 0 means portal arrivals only)")
