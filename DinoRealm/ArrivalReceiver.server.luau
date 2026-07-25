--======================================================================
-- ArrivalReceiver.server.luau  (Script)   [RECEIVING PLACE -- the DINO REALM]
--======================================================================
-- TEMPLATE -- put this Script in the DINO REALM place (ServerScriptService), NOT in the main game.
-- It is the other half of DinoRealmTeleport.server.lua.
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
--======================================================================
local Players = game:GetService("Players")

_G.playerOwnedPets   = _G.playerOwnedPets   or {}
_G.playerEquippedPet = _G.playerEquippedPet or {}
_G.incomingFtFData   = _G.incomingFtFData   or {}

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

	-- Not a portal arrival (joined the place directly, or the payload was lost) -> give them a normal start.
	if type(data) ~= "table" or data.fromFartToFloat ~= true then
		print("[DinoRealm] " .. player.Name .. " joined WITHOUT teleport data -> fresh start")
		return
	end

	_G.incomingFtFData[player]   = data
	_G.playerOwnedPets[player]   = (type(data.ownedPets) == "table") and data.ownedPets or {}
	_G.playerEquippedPet[player] = data.equippedPet

	print(("[DinoRealm] %s arrived from place %s with %d pet stack(s); equipped=%s")
		:format(player.Name, tostring(data.fromPlaceId), countStacks(_G.playerOwnedPets[player]),
		        tostring(data.equippedPet)))

	-- >>> YOUR ARRIVAL LOGIC GOES HERE <<<
	-- e.g. spawn them at the Dino Realm entrance, rebuild their equipped pet, play an arrival cinematic.
end

Players.PlayerAdded:Connect(intake)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(intake, p) end -- players already in (Studio / hot reload)

Players.PlayerRemoving:Connect(function(p)
	_G.incomingFtFData[p]   = nil
	_G.playerOwnedPets[p]   = nil
	_G.playerEquippedPet[p] = nil
end)

print("[DinoRealm] arrival receiver ready -- reading TeleportData from portal arrivals")
