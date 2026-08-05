--======================================================================
-- ArrivalReceiver.server.luau  (Script)   [RECEIVING PLACE -- the DINO REALM]
--======================================================================
-- Put this Script in the DINO REALM place (ServerScriptService), NOT in the main game.
-- It is one of a PAIR OF PAIRS:
--
--     islands  --[DinoRealmTeleport / RealmPortals]-->  THIS SCRIPT      (arriving)
--     islands  <--[RealmReturnReceiver]--[ReturnSender.server.luau]--    (going home)
--
-- The sending place attached a payload with TeleportOptions:SetTeleportData{...}. Over here we read it
-- back with player:GetJoinData().TeleportData. This is the ONLY way state crosses a place boundary --
-- _G, workspace and leaderstats do NOT come with the player.
--
-- IMPORTANT: GetJoinData() can be empty for a moment on join, and it is ONLY populated for players who
-- actually arrived via TeleportAsync. Somebody who opens the Dino Realm place directly from the Roblox
-- site gets NO TeleportData -- that is why we check the `fromFartToFloat` marker before trusting it.
--
-- SECURITY NOTE: TeleportData is set SERVER-side in the sending place, so it is trustworthy for things
-- like "which pets do they own". Never set TeleportData from a client.
--
-- ⚠ THE PART THAT MAKES THE RETURN TRIP POSSIBLE: we stash `homePlaceId` in _G.playerHomePlaceId. The Dino
-- place does not know the islands' placeId on its own, and ReturnSender reads exactly that global to send
-- them back. Break this and every player is stranded here.
--======================================================================
local Players = game:GetService("Players")

_G.playerOwnedPets       = _G.playerOwnedPets       or {}
_G.playerEquippedPet     = _G.playerEquippedPet     or {}
_G.playerPetSkins        = _G.playerPetSkins        or {} -- ["Pet|Skin|Trait"] = duplicate count
_G.playerEquippedSkins   = _G.playerEquippedSkins   or {} -- [petKey] = skin key the pet is wearing
_G.playerCollection      = _G.playerCollection      or {}
_G.playerPetMilestones   = _G.playerPetMilestones   or {}
_G.playerTitle           = _G.playerTitle           or {}
_G.playerCrateTokens     = _G.playerCrateTokens     or {}
_G.playerOwnedGutSkins   = _G.playerOwnedGutSkins   or {}
_G.playerEquippedGutSkin = _G.playerEquippedGutSkin or {}
_G.playerGamepasses      = _G.playerGamepasses      or {} -- [player] = { TwoXForever=bool, GlitterTrail=bool, InfiniteGut=bool }

_G.incomingFtFData   = _G.incomingFtFData   or {} -- the raw payload, kept for custom arrival code
_G.playerHomePlaceId = _G.playerHomePlaceId or {} -- [player] = placeId to send them BACK to

-- What the player has EARNED in this realm, which is the only thing the return trip pays out at home.
-- Deltas, never absolutes: the islands' DataStore owns their real balance, so we can only ever say
-- "add this much", never "set it to this". Your Dino gameplay adds to these:
--
--     _G.dinoAddEarnedCoins(player, 250)
--     _G.dinoAddEarnedTokens(player, 1)
--
_G.playerEarnedHere = _G.playerEarnedHere or {} -- [player] = { coins = n, crateTokens = n }

local function earnings(player)
	_G.playerEarnedHere[player] = _G.playerEarnedHere[player] or { coins = 0, crateTokens = 0 }
	return _G.playerEarnedHere[player]
end

_G.dinoAddEarnedCoins = function(player, n)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then return end
	local e = earnings(player); e.coins = e.coins + n
end

_G.dinoAddEarnedTokens = function(player, n)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then return end
	local e = earnings(player); e.crateTokens = e.crateTokens + n
end

local function countStacks(t)
	local n = 0
	if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
	return n
end

local function intake(player)
	local data
	pcall(function()
		local jd = player:GetJoinData()
		data = jd and jd.TeleportData
	end)

	earnings(player) -- always exists, so gameplay code can add to it whether or not they arrived via a portal

	-- ===== GAMEPASSES: bought once in ANY realm, honoured in all of them ==========================
	-- ABOVE the "no teleport data" return ON PURPOSE. Everything below this block is portal-arrival state
	-- that genuinely only exists in a payload -- but a gamepass is not: it is a Roblox-side fact about the
	-- USER, so somebody who opens this place straight from the website owns it just as much as somebody who
	-- walked through the portal. Resolving it after the early return would have quietly taken a paid pass
	-- away from every direct joiner.
	--
	-- TWO STEPS, in this order, and both matter:
	--   1. TRUST THE PAYLOAD, instantly. The islands already resolved every pass when the player joined
	--      there, so the flags arrive pre-computed and a 2x pass works on the arrival frame instead of a
	--      second later. They are stamped as ATTRIBUTES under the islands' own names (HasTwoXForever /
	--      HasGlitterTrail / HasInfiniteGut), so a client script copied over from there reads them
	--      unmodified. TeleportData is server-set, so a client cannot forge these.
	--   2. THEN VERIFY, in a spawn so a slow web call never holds up the arrival. The flags are a snapshot
	--      of the moment they left: a pass bought on the website mid-session, an older sender that predates
	--      this field, or a direct joiner with no payload at all would each be wrong. UserOwnsGamePassAsync
	--      is the real authority and works from any place, so it gets the last word -- but only ever to ADD.
	--      A failed web call must never strip a pass off somebody who paid for it.
	local passes = (type(data) == "table" and type(data.gamepasses) == "table") and data.gamepasses or {}
	_G.playerGamepasses[player] = passes
	for name, owned in pairs(passes) do
		player:SetAttribute("Has" .. name, owned == true)
	end
	-- The ids normally come down the wire, which is what keeps this file from owning a second copy of the
	-- islands' list that then drifts. They can be absent three ways: a direct joiner (no payload at all), an
	-- older sender, or the sending place's RealmTransfer module failing to load and dropping to its
	-- documented "pets-only" emergency payload. None of those should cost a player a pass they bought, so
	-- there is a fallback list -- used ONLY when the wire did not carry one.
	local passIds = (type(data) == "table" and type(data.gamepassIds) == "table" and next(data.gamepassIds) ~= nil)
		and data.gamepassIds
		or { TwoXForever = 1862015450, GlitterTrail = 1859714979, InfiniteGut = 1860686821 }
	task.spawn(function()
		local MarketplaceService = game:GetService("MarketplaceService")
		for name, id in pairs(passIds) do
			if tonumber(id) and tonumber(id) ~= 0 then
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, tonumber(id))
				end)
				if ok and owns and passes[name] ~= true and player.Parent then
					passes[name] = true
					player:SetAttribute("Has" .. name, true)
					print(("[DinoRealm] %s owns %s (confirmed live)"):format(player.Name, name))
				end
			end
		end
	end)

	-- Not a portal arrival (joined the place directly, or the payload was lost) -> give them a normal start.
	-- They get NO home placeId, so ReturnSender falls back to its own constant -- see the note over there.
	if type(data) ~= "table" or data.fromFartToFloat ~= true then
		print("[DinoRealm] " .. player.Name .. " joined WITHOUT teleport data -> fresh start")
		return
	end

	_G.incomingFtFData[player]   = data
	_G.playerOwnedPets[player]   = (type(data.ownedPets) == "table") and data.ownedPets or {}
	_G.playerEquippedPet[player] = data.equippedPet

	-- The cosmetic bundle. Without these a carried pet renders as the plain base pet over here -- the skin
	-- and trait are what make it look like the pet the player actually walked in with.
	_G.playerPetSkins[player]        = (type(data.petSkins) == "table") and data.petSkins or {}
	_G.playerEquippedSkins[player]   = (type(data.equippedSkins) == "table") and data.equippedSkins or {}
	_G.playerCollection[player]      = (type(data.collection) == "table") and data.collection or {}
	_G.playerPetMilestones[player]   = (type(data.petMilestones) == "table") and data.petMilestones or {}
	_G.playerTitle[player]           = data.title
	_G.playerCrateTokens[player]     = math.floor(tonumber(data.crateTokens) or 0)
	_G.playerOwnedGutSkins[player]   = (type(data.ownedGutSkins) == "table") and data.ownedGutSkins or { Default = true }
	_G.playerEquippedGutSkin[player] = data.equippedGutSkin or "Default"

	-- THE WAY HOME. Prefer the explicit homePlaceId; fall back to fromPlaceId, which older payloads (and the
	-- Space/Candy senders) still set. Either way, the return trip lands them in the place they came from.
	_G.playerHomePlaceId[player] = tonumber(data.homePlaceId) or tonumber(data.fromPlaceId)

	print(("[DinoRealm] %s arrived from place %s with %d pet stack(s), %d skin(s), %d token(s); equipped=%s; home=%s")
		:format(player.Name, tostring(data.fromPlaceId), countStacks(_G.playerOwnedPets[player]),
		        countStacks(_G.playerPetSkins[player]), _G.playerCrateTokens[player],
		        tostring(data.equippedPet), tostring(_G.playerHomePlaceId[player])))

	-- >>> YOUR ARRIVAL LOGIC GOES HERE <<<
	-- e.g. spawn them at the Dino Realm entrance, rebuild their equipped pet, play an arrival cinematic.
	-- The pet data is already staged in the same globals the islands' PetSystem uses, so if you copy
	-- PetSystem/PetFollow into this place, calling _G.petsApplyOnJoin(player) here renders them as-is.
end

Players.PlayerAdded:Connect(intake)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(intake, p) end -- players already in (Studio / hot reload)

Players.PlayerRemoving:Connect(function(p)
	_G.incomingFtFData[p]       = nil
	_G.playerOwnedPets[p]       = nil
	_G.playerEquippedPet[p]     = nil
	_G.playerPetSkins[p]        = nil
	_G.playerEquippedSkins[p]   = nil
	_G.playerCollection[p]      = nil
	_G.playerPetMilestones[p]   = nil
	_G.playerTitle[p]           = nil
	_G.playerCrateTokens[p]     = nil
	_G.playerOwnedGutSkins[p]   = nil
	_G.playerEquippedGutSkin[p] = nil
	_G.playerGamepasses[p]      = nil
	_G.playerHomePlaceId[p]     = nil
	_G.playerEarnedHere[p]      = nil
end)

print("[DinoRealm] arrival receiver ready -- reading TeleportData from portal arrivals")
