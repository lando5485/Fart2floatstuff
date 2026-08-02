--!nonstrict
--======================================================================
-- RealmTransfer  (ReplicatedStorage/Shared/RealmTransfer)  -- SERVER-USE MODULE
--======================================================================
-- ONE definition of "what a player carries between realms", shared by every sender in THIS place
-- (RealmPortals.server.lua and DinoRealmTeleport.server.lua). Before this module they each had their own
-- copy of the payload literal, which is exactly how the two doors into the Dino Realm end up sending
-- different shapes and the receiver starts guessing.
--
-- The matching receivers:
--   * this place:  RealmReturnReceiver.server.lua   (catches players coming HOME)
--   * Dino Realm:  ArrivalReceiver.server.luau + ReturnSender.server.luau
--   * Space Realm: PetReceiver.server.luau
-- Those live in OTHER places and cannot require this module -- a place boundary is a hard wall. They carry
-- their own copy of the field list; if you add a field here, add it there too.
--
-- ⚠ SERVER ONLY. It reads the _G player tables PlayerStats owns, which do not exist on a client.
--======================================================================
local HttpService = game:GetService("HttpService")

local RealmTransfer = {}

RealmTransfer.VERSION = 1

--======================================================================
-- SIZE. Roblox caps TeleportData, and going over does not truncate -- TeleportAsync THROWS, which means the
-- portal stops working entirely for exactly the players who have played the most. A completionist's skin
-- inventory is combinatorial (every pet x 20 skins x 9 traits is its own key), so this is a real ceiling,
-- not a theoretical one.
--
-- So we measure the encoded payload and, if it is too big, shed the least valuable things first. Pets are
-- NEVER dropped -- they are the whole point of the trip.
--======================================================================
local BUDGET_BYTES = 28000 -- comfortably under the cap, with room for Roblox's own envelope

local function encodedSize(t)
	local ok, json = pcall(function() return HttpService:JSONEncode(t) end)
	if not ok then return math.huge end -- unencodable -> treat as oversized so the shedding below runs
	return #json
end

-- Shed in priority order, cheapest loss first. Each step is announced, because a player silently losing
-- their collection book on every portal trip is the kind of bug that takes weeks to notice.
local function fit(payload, playerName)
	if encodedSize(payload) <= BUDGET_BYTES then return payload end

	-- 1) Duplicate COUNTS in the skin inventory. Owning 12 copies vs 1 copy only matters for the crate's
	--    duplicate display; which skins you OWN is what actually renders a pet. Collapse counts to 1.
	if type(payload.petSkins) == "table" then
		local flat = {}
		for k, v in pairs(payload.petSkins) do
			if (tonumber(v) or 0) > 0 then flat[k] = 1 end
		end
		payload.petSkins = flat
		warn(("[RealmTransfer] %s payload oversized -- collapsed skin duplicate counts"):format(playerName))
		if encodedSize(payload) <= BUDGET_BYTES then return payload end
	end

	-- 2) The collection book + milestone flags. Both are re-derivable at home from the inventory the player
	--    already has saved there, so dropping them costs nothing permanent.
	payload.collection    = nil
	payload.petMilestones = nil
	warn(("[RealmTransfer] %s payload still oversized -- dropped collection + milestones"):format(playerName))
	if encodedSize(payload) <= BUDGET_BYTES then return payload end

	-- 3) The skin inventory itself. Their pets now travel undressed (base look in the other realm), but they
	--    travel. The home save still has every skin -- nothing is lost permanently, only for this visit.
	payload.petSkins      = nil
	payload.equippedSkins = nil
	warn(("[RealmTransfer] %s payload STILL oversized -- dropped the skin inventory; pets will render " ..
		"with their base look in the other realm"):format(playerName))
	return payload
end

--======================================================================
-- THE PAYLOAD
--======================================================================
-- What travels, and just as importantly what does NOT:
--
--   * Pets + the cosmetics that dress them. A pet without its skin/trait renders as the plain base pet in
--     the other realm, so the bundle moves together.
--   * homePlaceId -- how the far side knows where "back" is. The Dino place does not know this place's id,
--     and hardcoding the same magic number in two projects is how return trips break the first time one is
--     republished. We stamp it; ArrivalReceiver stashes it; ReturnSender teleports to it.
--   * NOT coins/island/stomach/fartMeter. Those are ABSOLUTES and this place's DataStore is their authority.
--     A returning snapshot assigning them would wipe whatever the player earned in the meantime -- see the
--     header of RealmReturnReceiver.server.lua for the full reasoning.
--
-- `extra` is merged in last, so a caller can add its own keys (RealmPortals passes `realm`).
function RealmTransfer.build(player, realmKey, extra)
	local function g(tbl, default)
		local t = _G[tbl]
		local v = t and t[player]
		if v == nil then return default end
		return v
	end

	local payload = {
		fromFartToFloat = true,          -- the marker EVERY receiver in the project checks -- do not rename
		payloadVersion  = RealmTransfer.VERSION,
		fromPlaceId     = game.PlaceId,  -- which realm they came FROM
		homePlaceId     = game.PlaceId,  -- where the return trip goes (this IS home)
		toRealm         = realmKey,      -- where they were headed, for the far side's logs
		userId          = player.UserId, -- the far side refuses a payload stamped for somebody else
		sentAt          = os.time(),

		ownedPets       = g("playerOwnedPets", {}),
		equippedPet     = g("playerEquippedPet", nil),
		petSkins        = g("playerPetSkins", {}),
		equippedSkins   = g("playerEquippedSkins", {}),
		collection      = g("playerCollection", {}),
		petMilestones   = g("playerPetMilestones", {}),
		title           = g("playerTitle", nil),
		crateTokens     = math.floor(tonumber(g("playerCrateTokens", 0)) or 0),
		ownedGutSkins   = g("playerOwnedGutSkins", { Default = true }),
		equippedGutSkin = g("playerEquippedGutSkin", "Default"),
	}

	if type(extra) == "table" then
		for k, v in pairs(extra) do payload[k] = v end
	end

	return fit(payload, player.Name)
end

return RealmTransfer
