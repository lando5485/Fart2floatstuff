--!nonstrict
-- DevCommands (ServerScriptService/DevCommands)
-- ============================================================================
-- [REMOVE BEFORE LAUNCH]  Developer-only chat commands. This whole script is a
-- dev convenience and MUST be deleted before shipping.
-- ============================================================================
--
-- /crate       -> fires ServerScriptService/DevForceCrate (payload = the chatting Player), which
--                 CrateService handles by running performClaim(player, nil, true): bypasses the 6h
--                 gate, grants pet levels exactly like a real claim, and pushes the result via
--                 CrateResult so the reveal animates without tapping the (hidden) crate button.
-- /resetcrate  -> [TEST USERS ONLY] resets the player's crate timer to ready immediately
--                 (lastCrateClaim = 0) so they can claim again right away. Pushes a fresh snapshot
--                 so the More-menu row / "!" dot flip to READY at once.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DevForceCrate = ServerScriptService:WaitForChild("DevForceCrate", 30)
-- PlayerState is the authority for lastCrateClaim; require returns the cached module instance
-- (same in-memory state CrateService uses), so setLastCrateClaim(player, 0) takes effect live.
local PlayerState = require(ServerScriptService:WaitForChild("PlayerState"))

-- [REMOVE BEFORE LAUNCH] Allowlist for test-only commands (/resetcrate). Add UserIds and/or names.
local TEST_USER_IDS = {
	-- [1418148401] = true,  -- example: fill in real test UserIds
}
local TEST_USER_NAMES = {
	["lando5485"] = true,
}
local function isTestUser(player)
	return TEST_USER_IDS[player.UserId] == true or TEST_USER_NAMES[player.Name] == true
end

-- ====================== TEST SKIN COMMANDS - REMOVE BEFORE LAUNCH ======================
-- /default /gold /lava /diamond /galaxy /rainbow : instantly GRANT + EQUIP that gut skin for testing,
-- bypassing the playtime requirement (uses the same _G.grantGutSkin the unlock system uses). Test users only.
local SKIN_CMDS = {
	["/default"] = "Default", ["/gold"] = "Gold", ["/lava"] = "Lava",
	["/diamond"] = "Diamond", ["/galaxy"] = "Galaxy", ["/rainbow"] = "Rainbow",
}
-- ==================== END TEST SKIN COMMANDS ====================

local function onChatted(player, message)
	local cmd = string.lower((string.gsub(message, "^%s*(.-)%s*$", "%1")))
	if cmd == "/crate" then
		if DevForceCrate then
			DevForceCrate:Fire(player)
		end
	elseif cmd == "/resetcrate" then
		-- TEST USERS ONLY: silently ignore for everyone else.
		if not isTestUser(player) then return end
		PlayerState.setLastCrateClaim(player, 0) -- 0 = never claimed -> ready now; pushes snapshot
		print("[DevCommands] /resetcrate: crate timer reset to READY for " .. player.Name)
	-- TEST SKIN COMMANDS - REMOVE BEFORE LAUNCH: /default /gold /lava /diamond /galaxy /rainbow
	elseif SKIN_CMDS[cmd] then
		if not isTestUser(player) then return end
		local skinId = SKIN_CMDS[cmd]
		if _G.grantGutSkin and _G.grantGutSkin(player, skinId, true) then -- grant + equip + apply to the current gut
			print("[DevCommands] " .. cmd .. " -> granted + equipped '" .. skinId .. "' for " .. player.Name)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(msg)
		onChatted(player, msg)
	end)
end)
-- Players already present when this script starts.
for _, p in ipairs(Players:GetPlayers()) do
	p.Chatted:Connect(function(msg)
		onChatted(p, msg)
	end)
end
