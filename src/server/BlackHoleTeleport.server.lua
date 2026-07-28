--======================================================================
-- BlackHoleTeleport.server.lua  (Script)
--======================================================================
-- SERVER-AUTHORITATIVE teleport from the black-hole orb (the visual landmark high above Pizza Palms /
-- Island 14) to the SPACE REALM place inside this same Fart to Float experience.
--
-- The orb VISUAL is built CLIENT-side (WorldClient.buildBlackHole). That client detects the touch and
-- fires BlackHoleEnterEvent; the SERVER (here) validates + calls TeleportService:TeleportAsync. The
-- client is NEVER trusted to teleport itself -- this is the correct/secure pattern.
--
-- ⚠⚠ TESTER LOCK ⚠⚠  SPACE_REALM_TESTERS_ONLY = true gates the teleport to the test users below.
--   To OPEN Space Realm to EVERYONE later, flip SPACE_REALM_TESTERS_ONLY = false (one line) and re-sync.
--   ★ REMOVE / OPEN THIS GATE BEFORE PUBLIC LAUNCH. ★
--
-- Touches nothing else: no flight, pets, shop, events, coins, gas, hazards. Only this teleport.
--======================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")

local SPACE_REALM_PLACE_ID = 125063266868039 -- Space Realm place (within the FtF experience, Universe 10236070926)

-- ⚠ TESTER LOCK -- flip to false to open Space Realm to everyone; REMOVE/OPEN BEFORE PUBLIC LAUNCH. ⚠
local SPACE_REALM_TESTERS_ONLY = true
local TESTER_IDS   = { [1086836724] = true, [1418148401] = true }  -- lando5485, Broskie310111
-- Keys are LOWER-CASE and the lookup lower-cases too. The previous version compared plr.Name directly
-- against mixed-case keys, so anyone whose account capitalisation differed by a single letter was refused
-- with no message -- which is exactly how a tester ends up locked out of Space Realm for no visible reason.
local TESTER_NAMES = { ["lando5485"] = true, ["broskie310111"] = true, ["itsmaddmax1"] = true, ["itsmaddmax2"] = true }
local function isTester(plr)
	-- Prefer the SHARED allow-list in PlayerStats when it has loaded, so there is one place to add a tester;
	-- the local table stays as a fallback for load-order (this script may run before PlayerStats).
	if type(_G.isAllowedTestUser) == "function" then
		local ok, res = pcall(_G.isAllowedTestUser, plr)
		if ok and res then return true end
	end
	return TESTER_IDS[plr.UserId] == true or TESTER_NAMES[string.lower(plr.Name)] == true
end
local function allowed(plr) return (not SPACE_REALM_TESTERS_ONLY) or isTester(plr) end

-- RemoteEvent the client (orb touch) fires its INTENT on. getOrCreate so a missing project.json entry can't
-- break it; the client WaitForChild's this same name.
local enterEvent = ReplicatedStorage:FindFirstChild("BlackHoleEnterEvent")
if not enterEvent then
	enterEvent = Instance.new("RemoteEvent"); enterEvent.Name = "BlackHoleEnterEvent"; enterEvent.Parent = ReplicatedStorage
end

local teleporting = {} -- [player] = true  (server-side debounce: never double-teleport)

-- The SERVER is the single authoritative gate (the client never decides). The client only fires its INTENT
-- on touch; the server checks the tester lock, tells the client what to show, then does the teleport itself.
enterEvent.OnServerEvent:Connect(function(player)
	if not player or teleporting[player] then return end -- per-player debounce: never double-teleport
	local ok2 = allowed(player)
	print("[BlackHole] " .. player.Name .. " touched orb - testerAllowed=" .. (ok2 and "y" or "n"))
	if not ok2 then
		pcall(function() enterEvent:FireClient(player, "locked") end) -- enforce the lock -> client shows "Coming soon!"
		return
	end
	teleporting[player] = true
	pcall(function() enterEvent:FireClient(player, "traveling") end) -- client shows "Traveling to Space Realm..."
	task.wait(1.2) -- brief intentional pause so it feels deliberate, THEN teleport
	if not player.Parent then teleporting[player] = nil; return end -- player left during the pause
	print("[BlackHole] teleporting " .. player.Name .. " to SpaceRealm (placeId " .. SPACE_REALM_PLACE_ID .. ")")
	local ok, err = pcall(function()
		-- Carry the player's COLLECTED PETS into the Space Realm. TeleportData is set server-side here and
			-- read on the other side via player:GetJoinData().TeleportData -> the Space Realm rebuilds them.
			local options = Instance.new("TeleportOptions")
			options:SetTeleportData({
				fromFartToFloat = true,
				ownedPets   = (_G.playerOwnedPets   and _G.playerOwnedPets[player])   or {},  -- { [petKey] = {level,height,time,rare,xp} }
				equippedPet = (_G.playerEquippedPet and _G.playerEquippedPet[player]) or nil, -- the pet that should follow them in Space Realm
			})
			TeleportService:TeleportAsync(SPACE_REALM_PLACE_ID, { player }, options) -- server-side teleport (secure) + pet payload
	end)
	print(string.format("[BlackHole] teleport %s -> SpaceRealm (placeId %d) result: %s",
		player.Name, SPACE_REALM_PLACE_ID, ok and "ok" or ("err: " .. tostring(err))))
	print("[BlackHole] teleport result: " .. (ok and "success" or ("error: " .. tostring(err))))
	if not ok then
		teleporting[player] = nil -- teleport failed -> allow a retry
		pcall(function() enterEvent:FireClient(player, "error") end) -- client shows "Couldn't travel right now, try again"
	end
end)

Players.PlayerRemoving:Connect(function(p) teleporting[p] = nil end)

print("[BlackHole] teleport handler ready (Space Realm placeId " .. SPACE_REALM_PLACE_ID ..
	", testersOnly=" .. tostring(SPACE_REALM_TESTERS_ONLY) .. ")")
