--!nonstrict
--======================================================================
-- DinoRealmTeleport.server.lua  (Script, ServerScriptService)
--======================================================================
-- THE SERVER HALF OF THE CANDY REALM'S DINO PORTAL.
--
-- DinoPortal.client.luau touches the portal and fires DinoRealmEnterEvent with NO arguments -- intent only.
-- Everything that matters happens here: the gate, the payload, the instance choice, the teleport. A client
-- that can name its own destination is a client that can teleport itself anywhere.
--
-- ===== THIS REPLACES THE BAKED-IN COPY =====
-- The original of this script only ever existed inside the place file, never in the source tree, which is why
-- the portal worked but could not be edited. Rojo only ADDS -- it does not remove what is already in the
-- place -- so once this syncs there will be TWO scripts listening to DinoRealmEnterEvent and one touch will
-- fire two teleports. DELETE the baked-in DinoRealmTeleport in Studio when you sync this.
--
-- The _G guard below catches the case where both are running only if the old one has it too, which it does
-- not. It is here for the second copy of THIS file, not as protection against the old one.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local RunService        = game:GetService("RunService")

if _G.__DinoRealmTeleport then
	warn("[DinoTeleport] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__DinoRealmTeleport = true

-- 0 means "not built yet" -> the portal answers "Coming soon!" instead of teleporting into nowhere.
local DINO_PLACE_ID = 110777788409412   -- FART TO FLOAT [DINO REALM]

local SEND_COOLDOWN = 6   -- seconds between attempts, per player; the portal is a touch trigger

local enterEvent = ReplicatedStorage:FindFirstChild("DinoRealmEnterEvent")
if not enterEvent then
	enterEvent = Instance.new("RemoteEvent")
	enterEvent.Name = "DinoRealmEnterEvent"
	enterEvent.Parent = ReplicatedStorage
end

--======================================================================
-- LAND THEM WITH THEIR FRIENDS
--======================================================================
-- A portal that drops you into a random empty server has technically worked and has actually failed: the
-- reason two kids walk through together is to still be together on the other side. Roblox will not do this on
-- its own -- TeleportAsync picks whatever instance it likes -- so the sending place has to look up where the
-- friends already are and name the instance explicitly.
--
-- BEST EFFORT, ALWAYS. Every part of this can fail for reasons that are nobody's fault: the friend list is a
-- web call, GetPlayerPlaceInstanceAsync respects the other player's join-privacy setting, and the server it
-- finds may fill in the seconds before the teleport lands. So it is wrapped end to end, capped, and every
-- failure path falls through to the ordinary teleport rather than blocking the trip.
local FRIEND_SCAN_CAP = 24    -- friends to check at most; a 200-friend list is not worth 200 web calls
local FRIEND_TIME_CAP = 1.5   -- seconds; past this the player is just standing at a portal waiting

local function friendInstanceIn(player, placeId)
	local deadline = os.clock() + FRIEND_TIME_CAP
	local found, checked = nil, 0

	local ok = pcall(function()
		local page = Players:GetFriendsAsync(player.UserId)
		while true do
			for _, f in ipairs(page:GetCurrentPage()) do
				if found or checked >= FRIEND_SCAN_CAP or os.clock() > deadline then return end
				checked = checked + 1
				-- Returns (success, errorMessage, placeId, instanceId). It is only allowed to answer for
				-- players whose privacy permits it, so a `false` here is a normal outcome, not an error.
				local callOk, success, _, pid, iid =
					pcall(TeleportService.GetPlayerPlaceInstanceAsync, TeleportService, f.Id)
				if callOk and success and pid == placeId and iid then
					found = iid
					return
				end
			end
			if page.IsFinished then break end
			page:AdvanceToNextPageAsync()
		end
	end)

	if not ok then return nil end
	return found
end

--======================================================================
-- THE TRIP
--======================================================================
local lastTry = {}
Players.PlayerRemoving:Connect(function(p) lastTry[p] = nil end)

enterEvent.OnServerEvent:Connect(function(player)
	if DINO_PLACE_ID == 0 then
		enterEvent:FireClient(player, "locked")
		return
	end

	-- The portal is a Touched trigger, so a player standing in it fires this many times a second. The client
	-- debounces too, but a client debounce is a courtesy and this one is the actual limit.
	local now = os.clock()
	if lastTry[player] and now - lastTry[player] < SEND_COOLDOWN then return end
	lastTry[player] = now

	-- NO UNLOCK GATE HERE, on purpose. Reaching the Candy realm already required climbing the food realm and
	-- walking through its portal -- the entry guard in RealmServer enforces that on every join. Re-checking a
	-- requirement that is upstream of standing in this room would only add a way to be wrongly refused.
	enterEvent:FireClient(player, "traveling")

	-- Looked up BEFORE the options are built and OUTSIDE the teleport pcall, so a slow or refused lookup can
	-- never turn into a failed teleport -- worst case it returns nil and they travel normally.
	local friendInstance = friendInstanceIn(player, DINO_PLACE_ID)

	local ok, err = pcall(function()
		-- TeleportData is the ONLY channel across a place boundary -- _G, workspace and leaderstats do NOT
		-- come with the player. Set SERVER-side, here, so it is trustworthy on the far side.
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData({
			fromFartToFloat = true,          -- the marker every receiver checks (a direct join has NO data)
			fromPlaceId     = game.PlaceId,
			fromRealm       = "candy",
			ownedPets   = (_G.playerOwnedPets   and _G.playerOwnedPets[player])   or {},
			equippedPet = (_G.playerEquippedPet and _G.playerEquippedPet[player]) or nil,
		})
		if friendInstance then options.ServerInstanceId = friendInstance end
		TeleportService:TeleportAsync(DINO_PLACE_ID, { player }, options)
	end)

	if ok then
		print(("[DinoTeleport] %s -> Dino Realm (%d)%s"):format(
			player.Name, DINO_PLACE_ID, friendInstance and " [friend's server]" or ""))
	else
		warn(("[DinoTeleport] teleport failed for %s: %s"):format(player.Name, tostring(err)))
		lastTry[player] = nil            -- a failed trip should not cost them the cooldown
		enterEvent:FireClient(player, "error")
	end
end)

-- Teleports can also fail AFTER TeleportAsync returns. Without this the client sits on "Traveling..." until
-- its own 5s failsafe clears it, with no idea anything went wrong.
TeleportService.TeleportInitFailed:Connect(function(player, _result, errMsg)
	if not player or not player.Parent then return end
	warn(("[DinoTeleport] async teleport failure for %s: %s"):format(player.Name, tostring(errMsg)))
	lastTry[player] = nil
	pcall(function() enterEvent:FireClient(player, "error") end)
end)

print(("[DinoTeleport] ready -- Dino portal %s"):format(
	DINO_PLACE_ID == 0 and "LOCKED (place id 0)" or ("-> " .. DINO_PLACE_ID)))
