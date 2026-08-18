--!nonstrict
--[[
	RealmServer.server.luau  —  the new realm's main server script (starter).

	This runs in the NEW realm's place (a separate Roblox place). It does two realm-specific jobs:
	  1) RECEIVER: reads the state the food realm packed into TeleportData when the player warped in,
	     so their pets / coins / progress arrive with them (the "pushers/receivers" pattern).
	  2) Your realm gameplay goes below the marked line.

	ROUTED BY: NewRealm/default.project.json -> ServerScriptService.RealmServer
	SERVE IT:  rojo serve NewRealm/default.project.json   (then connect the Rojo plugin in that place)
]]

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

-- ===========================================================================
-- 0) ENTRY GUARD — you get here through the portal or you do not get here.
-- ===========================================================================
-- This place is a LATER realm. Arriving in it should mean you climbed the food realm, unlocked Candy, and
-- walked through the door -- but a Roblox place is a public URL, so without a guard anyone can paste the
-- link and skip every one of those steps. That is not just a shortcut past the unlock: a direct joiner has
-- no TeleportData, so they arrive with no pets, no coins and no progress, in a realm built assuming they
-- brought all three.
--
-- The test is the marker the food realm packs into TeleportData. Real portal arrivals have it; a pasted
-- link cannot fake it, because TeleportData can only be set by the sending SERVER.
--
-- FAIL-OPEN, DELIBERATELY. If FOOD_PLACE_ID is left at 0 the guard warns and lets them in. Bouncing players
-- at an id that has not been filled in would strand them in a teleport to nowhere, and a realm nobody can
-- enter is a worse bug than a realm anyone can.
local FOOD_PLACE_ID = 120919484545190   -- the FART TO FLOAT food-islands place. 0 = guard disabled.

-- THE TEST IS "DID A SERVER SEND YOU", not "did the food realm send you".
--
-- TeleportData can only be set by the sending SERVER, so its mere presence proves the player was already
-- inside this universe when they travelled -- which is the whole property worth checking, and the one a
-- pasted link cannot fake.
--
-- It used to require `fromFartToFloat` specifically. That is right only while this realm is reachable from
-- exactly one place, and it is not: there is a Dino portal here, so a player coming BACK from Dino is a
-- legitimate arrival whose payload was written by a different sender with different keys. The strict version
-- would have bounced them to the food realm for walking backwards through a door they had already earned.
local function arrivedThroughPortal(player)
	local jd = player:GetJoinData()
	return type(jd and jd.TeleportData) == "table"
end

local function guard(player)
	-- Studio has no teleport data by definition. Before FOOD_PLACE_ID was filled in this did not matter --
	-- the guard was disabled and fell through the warn below -- but with a real id in place, a guard that ran
	-- in Studio would teleport you out of the place you are trying to test.
	if game:GetService("RunService"):IsStudio() then return true end
	if arrivedThroughPortal(player) then return true end
	if FOOD_PLACE_ID == 0 then
		warn(("[CandyRealm] %s joined DIRECTLY and the guard is off (FOOD_PLACE_ID = 0) -- letting them in. "
			.. "Set FOOD_PLACE_ID to bounce direct joins back to the food realm."):format(player.Name))
		return true
	end
	print(("[CandyRealm] %s joined directly -- sending them to the food realm to start properly")
		:format(player.Name))
	-- Not a kick. They did not cheat, they clicked a link -- so they get put where the game begins.
	local ok = pcall(function() TeleportService:Teleport(FOOD_PLACE_ID, player) end)
	if not ok then
		warn("[CandyRealm] bounce teleport FAILED -- leaving them here rather than stranding them")
	end
	return false
end

-- ===========================================================================
-- 1) RECEIVER — catch the state carried across from the food realm.
-- The sender did: options:SetTeleportData({ ... }); TeleportService:TeleportAsync(...).
-- Here we read it back on join. Everything is best-effort/pcall'd so a missing field never errors.
-- ===========================================================================
local function onPlayerAdded(player)
	if not guard(player) then return end   -- direct join: they are on their way to the food realm

	local joinData = player:GetJoinData()
	local data = joinData and joinData.TeleportData

	if type(data) ~= "table" then
		-- Only reachable with the guard disabled (or in Studio, where there is no teleport data at all).
		print(("[CandyRealm] %s joined with NO teleport data (fresh)"):format(player.Name))
		return
	end

	print(("[NewRealm] %s arrived from placeId %s")
		:format(player.Name, tostring(data.fromPlaceId)))

	-- ---- read the carried fields here ----
	-- Match the exact keys the food realm packs in RealmPortals (SetTeleportData). Examples:
	--   local coins   = tonumber(data.coins) or 0
	--   local pets    = data.pets            -- table of the player's owned pets
	--   local rebirths= tonumber(data.rebirths) or 0
	-- Then apply them to this realm's leaderstats / save / pet system.
	-- pcall each apply so one bad field can't block the rest.
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p) -- catch anyone already in (Studio Play Solo, live reload)
end

-- ===========================================================================
-- 2) YOUR REALM GAMEPLAY  ↓↓↓  build the new realm below this line
-- ===========================================================================

print("[NewRealm] server ready")
