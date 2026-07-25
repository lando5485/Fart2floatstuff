--======================================================================
-- PlanetSelectService.server.lua  (Script -> ServerScriptService)
--======================================================================
-- FtF (starting place) half of the planet-select menu. Two jobs:
--   1. Tell the client which planets are unlocked, by reading the SHARED, universe-scoped Space Realm
--      DataStore (highestPlanetReached). DataStore reads MUST be server-side.
--   2. Teleport the player into the Space Realm PLACE with the picked planet name in TeleportData, under
--      the SAME key Space Realm reads ("SelectedPlanetFromFtF"). Teleporting server-side (not from the
--      client) is the secure choice and RE-VALIDATES the unlock.
--
-- Pairs with the loading-screen planet menu (LoadingScreen.client.lua) and Space Realm's receiver
-- (PlanetSelectSpawn), which reads TeleportData["SelectedPlanetFromFtF"] and drops the player on that island.
--
-- ⚠ NOTE: Space Realm is currently TESTER-LOCKED for the black-hole entry (see BlackHoleTeleport.server.lua,
--   SPACE_REALM_TESTERS_ONLY). This planet menu follows the handoff spec and gates ONLY on the unlock
--   (highestPlanetReached; new players get Mercury). Add a tester gate here too if Space Realm must stay
--   closed to the public via this path.
--======================================================================
local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")

-- Space Realm place inside this SAME experience (matches BlackHoleTeleport.server.lua's id).
local SPACE_REALM_PLACE_ID = 125063266868039

-- These strings MUST match Space Realm's Constants (the single source of truth over there).
local DATASTORE_NAME      = "SpaceRealm_PlayerState_v1" -- Constants.DATASTORE_NAME
local KEY_PREFIX          = "Player_"                    -- Constants.DATASTORE_KEY_PREFIX
local SELECTED_PLANET_KEY = "SelectedPlanetFromFtF"      -- Constants.TELEPORT_KEYS.SelectedPlanet

-- Island order 1..8 (index == order), exactly like Space Realm's PlanetConfig.PLANETS.
local PLANETS = { "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune" }
local ORDER_OF = {}
for order, name in ipairs(PLANETS) do
	ORDER_OF[name] = order
end

local store = DataStoreService:GetDataStore(DATASTORE_NAME)

-- Read the player's furthest-reached planet (0..8). ZERO means "has never set foot in Space Realm", and that is
-- the correct default for a brand-new player: the ONLY thing unlocked anywhere in the game at the start is Island 1
-- of the first realm. Mercury is not a gift, it is something you reach.
--
-- This used to floor at 1, which silently handed every new account a free unlocked Mercury -- so the planet screen
-- showed one green card to someone who had never been to space. The clamp floor is now 0 so "never been" can
-- actually be represented; anyone who HAS reached a planet still clamps into 1..8 exactly as before.
--
-- A read FAILURE also resolves to 0. Failing closed matters here: if the DataStore blips, the safe answer is
-- "you have unlocked nothing", never "here, have a planet".
local function getHighestReached(userId)
	local data
	local ok, err = pcall(function()
		data = store:GetAsync(KEY_PREFIX .. tostring(userId))
	end)
	if not ok then
		warn(("[PlanetSelect] DataStore read failed for %d: %s -- failing CLOSED (nothing unlocked)")
			:format(userId, tostring(err)))
		return 0
	end
	if type(data) == "table" and type(data.highestPlanetReached) == "number" then
		return math.clamp(math.floor(data.highestPlanetReached), 0, #PLANETS)
	end
	return 0
end

-- Remotes: getOrCreate so this works whether they are pre-declared in default.project.json or created here.
-- The client (LoadingScreen) WaitForChild's these same names.
local function getOrCreate(className, name)
	local obj = ReplicatedStorage:FindFirstChild(name)
	if not obj then
		obj = Instance.new(className)
		obj.Name = name
		obj.Parent = ReplicatedStorage
	end
	return obj
end
local getUnlocks      = getOrCreate("RemoteFunction", "PlanetSelect_GetUnlocks")
local requestTeleport = getOrCreate("RemoteEvent",    "PlanetSelect_Teleport")

-- Client asks (each time the planet menu opens) which planets are unlocked. Returns highest + a name->bool map.
getUnlocks.OnServerInvoke = function(player)
	local highest = getHighestReached(player.UserId)
	local unlocked = {}
	for order, name in ipairs(PLANETS) do
		unlocked[name] = order <= highest
	end
	return { highest = highest, unlocked = unlocked }
end

local teleporting = {} -- [player] = true  (per-player debounce; never double-teleport)

-- Client asks to warp to a planet. The server RE-VALIDATES the unlock (never trust the client), then
-- teleports with the pick in TeleportData. A locked/invalid pick is silently ignored.
requestTeleport.OnServerEvent:Connect(function(player, planetName)
	if teleporting[player] then return end
	if type(planetName) ~= "string" or not ORDER_OF[planetName] then
		return
	end
	if ORDER_OF[planetName] > getHighestReached(player.UserId) then
		print(("[PlanetSelect] %s picked LOCKED %s -> ignored"):format(player.Name, tostring(planetName)))
		return
	end
	if SPACE_REALM_PLACE_ID == 0 then
		warn("[PlanetSelect] SPACE_REALM_PLACE_ID is not set — cannot teleport")
		return
	end

	teleporting[player] = true
	local opts = Instance.new("TeleportOptions")
	opts:SetTeleportData({
		[SELECTED_PLANET_KEY] = planetName,
		fromFartToFloat = true,
		-- Carry the player's COLLECTED PETS across, the same payload the black-hole teleport sends, so the
		-- Space Realm side can rebuild them (read via player:GetJoinData().TeleportData over there).
		ownedPets   = (_G.playerOwnedPets   and _G.playerOwnedPets[player])   or {},
		equippedPet = (_G.playerEquippedPet and _G.playerEquippedPet[player]) or nil,
	})
	print(("[PlanetSelect] teleporting %s -> Space Realm on %s (place %d)"):format(player.Name, planetName, SPACE_REALM_PLACE_ID))
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(SPACE_REALM_PLACE_ID, { player }, opts)
	end)
	if not ok then
		teleporting[player] = nil -- teleport failed -> allow a retry
		warn(("[PlanetSelect] teleport failed for %s: %s"):format(player.Name, tostring(err)))
	end
end)

Players.PlayerRemoving:Connect(function(p)
	teleporting[p] = nil
end)

print(("[PlanetSelect] service online (Space Realm place id %d)"):format(SPACE_REALM_PLACE_ID))
