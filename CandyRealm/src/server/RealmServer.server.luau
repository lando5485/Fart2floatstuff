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

local Players = game:GetService("Players")

-- ===========================================================================
-- 1) RECEIVER — catch the state carried across from the food realm.
-- The sender did: options:SetTeleportData({ ... }); TeleportService:TeleportAsync(...).
-- Here we read it back on join. Everything is best-effort/pcall'd so a missing field never errors.
-- ===========================================================================
local function onPlayerAdded(player)
	local joinData = player:GetJoinData()
	local data = joinData and joinData.TeleportData

	if type(data) ~= "table" then
		-- No carried state (e.g. joined directly, or Studio). Start them at defaults.
		print(("[NewRealm] %s joined with NO teleport data (fresh)"):format(player.Name))
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
