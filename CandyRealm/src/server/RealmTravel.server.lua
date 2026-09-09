--!nonstrict
--======================================================================
-- RealmTravel.server.lua  (Script, ServerScriptService)  -- CandyRealm
--======================================================================
-- THE SERVER HALF OF THE WORMHOLE'S "OTHER REALMS" ROWS.
--
-- WormholeClient's Fast Travel menu lists the three realms that come before this one -- Food, Space
-- and Dino -- under the island list, and firing this remote is the only way it can move you. The
-- client sends a KEY ("food" / "space" / "dino"), never a place id: a client that can name its own
-- destination is a client that can teleport itself into any experience on the platform, so the id
-- table lives here and the key is looked up against it.
--
-- ===== WHY THIS IS NOT A FOURTH COPY OF DinoRealmTeleport =====
-- That file owns the PORTAL on island 1 -- a Touched trigger with its own cooldown, its own client
-- states ("traveling" / "locked" / "error") and its own remote that DinoPortal.client.luau already
-- listens to. Rewiring it to take a destination argument would change a working portal's protocol
-- for the benefit of a menu. This is the MENU's door: same friend-instance trick, same TeleportData
-- payload, its own remote. Both can run without knowing about each other.
--
-- ===== THE PAYLOAD IS THE CONTRACT =====
-- TeleportData is the ONLY channel across a place boundary -- _G, workspace and leaderstats do not
-- travel with the player. It is set SERVER-side, here, so the receiving place can trust it, and it
-- carries the same fields DinoRealmTeleport sends so the far side needs no new handling:
-- `fromFartToFloat` (the marker every receiver checks -- a direct join has NO data), `fromPlaceId`,
-- `fromRealm`, and the player's pets.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")

if _G.__RealmTravelServer then
	warn("[RealmTravel] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__RealmTravelServer = true

--======================================================================
-- THE DESTINATIONS
--======================================================================
-- Ids cross-checked against every place in the family that already holds them, so there is one set
-- of numbers and not four: the Dino realm's own WormholeService lists all three
-- (farttofloatdinosaurealm/src/server/WormholeService.server.luau:31-33), the food realm's
-- BlackHoleTeleport holds Space, and this realm's RealmServer holds Food.
--
-- 0 means "not built / not authorised yet" -> the row answers "Coming soon" instead of teleporting
-- into nowhere. Nothing here is 0 today; the branch stays because it is how a realm gets retired.
local REALMS = {
	food  = { id = 120919484545190, name = "Food Realm" },
	space = { id = 125063266868039, name = "Space Realm" },
	dino  = { id = 110777788409412, name = "Dinosaur Realm" },
}

local SEND_COOLDOWN = 6   -- seconds between attempts, per player

local travelEvent = ReplicatedStorage:FindFirstChild("RealmTravelEvent")
if not travelEvent then
	travelEvent = Instance.new("RemoteEvent")
	travelEvent.Name = "RealmTravelEvent"
	travelEvent.Parent = ReplicatedStorage
end

--======================================================================
-- LAND THEM WITH THEIR FRIENDS
--======================================================================
-- Lifted from DinoRealmTeleport, and for its reason: a portal that drops you into a random empty
-- server has technically worked and has actually failed -- the reason two kids travel together is
-- to still be together on the other side. Roblox will not do this on its own, so the SENDING place
-- has to look up where the friends already are and name the instance explicitly.
--
-- BEST EFFORT, ALWAYS. The friend list is a web call, GetPlayerPlaceInstanceAsync respects the other
-- player's join-privacy setting, and the server it finds may fill in the seconds before the teleport
-- lands. Wrapped end to end, capped in both count and time, and every failure path falls through to
-- the ordinary teleport rather than blocking the trip.
local FRIEND_SCAN_CAP = 24
local FRIEND_TIME_CAP = 1.5

local function friendInstanceIn(player, placeId)
	local deadline = os.clock() + FRIEND_TIME_CAP
	local ok, pages = pcall(function() return Players:GetFriendsAsync(player.UserId) end)
	if not ok or not pages then return nil end

	local checked = 0
	while checked < FRIEND_SCAN_CAP and os.clock() < deadline do
		local gotPage, items = pcall(function() return pages:GetCurrentPage() end)
		if not gotPage or not items then return nil end
		for _, f in ipairs(items) do
			if checked >= FRIEND_SCAN_CAP or os.clock() >= deadline then return nil end
			checked += 1
			-- Returns (success, errorMessage, placeId, instanceId), and only answers for a friend who
			-- is actually in-experience with join privacy open. Any other shape means "no".
			local callOk, success, _err, pid, iid =
				pcall(TeleportService.GetPlayerPlaceInstanceAsync, TeleportService, f.Id)
			if callOk and success and pid == placeId and iid then
				return iid
			end
		end
		if pages.IsFinished then return nil end
		local advanced = pcall(function() pages:AdvanceToNextPageAsync() end)
		if not advanced then return nil end
	end
	return nil
end

--======================================================================
-- THE TRIP
--======================================================================
local lastTry = {}
Players.PlayerRemoving:Connect(function(p) lastTry[p] = nil end)

travelEvent.OnServerEvent:Connect(function(player, key)
	-- THE KEY IS VALIDATED, NOT TRUSTED. A non-string, or a string that is not one of the three, is
	-- dropped without an answer -- there is no path from here to an arbitrary place id.
	if type(key) ~= "string" then return end
	local dest = REALMS[key]
	if not dest then
		warn(("[RealmTravel] %s asked for unknown realm '%s' -- refused"):format(player.Name, tostring(key)))
		return
	end

	if dest.id == 0 then
		travelEvent:FireClient(player, "locked", key)
		return
	end

	local now = os.clock()
	if lastTry[player] and now - lastTry[player] < SEND_COOLDOWN then return end
	lastTry[player] = now

	travelEvent:FireClient(player, "traveling", key)

	-- Looked up BEFORE the options are built and OUTSIDE the teleport pcall, so a slow or refused
	-- lookup can never turn into a failed teleport -- worst case it returns nil and they travel alone.
	local friendInstance = friendInstanceIn(player, dest.id)

	local ok, err = pcall(function()
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData({
			fromFartToFloat = true,
			fromPlaceId     = game.PlaceId,
			fromRealm       = "candy",
			ownedPets   = (_G.playerOwnedPets   and _G.playerOwnedPets[player])   or {},
			equippedPet = (_G.playerEquippedPet and _G.playerEquippedPet[player]) or nil,
		})
		if friendInstance then options.ServerInstanceId = friendInstance end
		TeleportService:TeleportAsync(dest.id, { player }, options)
	end)

	if ok then
		print(("[RealmTravel] %s -> %s (%d)%s"):format(
			player.Name, dest.name, dest.id, friendInstance and " [friend's server]" or ""))
	else
		warn(("[RealmTravel] teleport failed for %s -> %s: %s"):format(player.Name, dest.name, tostring(err)))
		lastTry[player] = nil            -- a failed trip should not cost them the cooldown
		travelEvent:FireClient(player, "error", key)
	end
end)

-- Teleports can also fail AFTER TeleportAsync returns. Without this the client sits on "Traveling..."
-- with no idea anything went wrong.
TeleportService.TeleportInitFailed:Connect(function(player, _result, errMsg)
	if not player or not player.Parent then return end
	warn(("[RealmTravel] async teleport failure for %s: %s"):format(player.Name, tostring(errMsg)))
	lastTry[player] = nil
	pcall(function() travelEvent:FireClient(player, "error") end)
end)

do
	local names = {}
	for k, v in pairs(REALMS) do
		names[#names + 1] = ("%s=%s"):format(k, v.id == 0 and "LOCKED" or tostring(v.id))
	end
	table.sort(names)
	print("[RealmTravel] ready -- wormhole realm rows travel via RealmTravelEvent (" .. table.concat(names, ", ") .. ")")
end
