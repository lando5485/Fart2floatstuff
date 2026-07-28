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
	[1418148401] = true,  -- Broskie310111
}
local TEST_USER_NAMES = {
	["lando5485"] = true,
	["itsmaddmax1"] = true,
	["itsmaddmax2"] = true,
	["broskie310111"] = true,
}
local function isTestUser(player)
	-- names compared lower-cased so capitalisation of the account can't cause a miss
	return TEST_USER_IDS[player.UserId] == true or TEST_USER_NAMES[string.lower(player.Name)] == true
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
	-- (/givespins and /forcemythical went with the Pet Wheel. Pet levels come from the Pet Level Crate now,
	--  so /givetokens + /opencrate PetLevels tests that path end to end.)
	-- SKIN CRATE TEST COMMANDS - REMOVE BEFORE LAUNCH -----------------------------------------------------
	-- /givetokens <n>  : credit n Crate Tokens (default 1000) with no Robux purchase.
	-- /opencrate <id>  : force-open a crate (default the first), comping its token price, so the roll + reveal
	--                    can be tested repeatedly. Goes through the SAME openCrate the real button uses -- there
	--                    is no test-only roll path that could behave differently from production.
	-- /goldtest        : keep opening until a GOLD pull lands, to check the jackpot sound / flash / announcement.
	--                    Capped at 5000 opens so a bad streak can't spin forever (0.08% -> expect ~1250).
	elseif string.match(cmd, "^/givetokens") then
		if not isTestUser(player) then return end
		local n = tonumber(string.match(cmd, "^/givetokens%s+(%-?%d+)")) or 1000
		local ev = ServerScriptService:FindFirstChild("DevGiveTokens")
		if ev then ev:Fire(player, n); print("[DevCommands] /givetokens " .. tostring(n) .. " for " .. player.Name) end
	elseif string.match(cmd, "^/opencrate") then
		if not isTestUser(player) then return end
		local id = string.match(message, "^/opencrate%s+(%S+)") -- raw message, not lower-cased: crate ids are case-sensitive
		local ev = ServerScriptService:FindFirstChild("DevOpenCrate")
		if ev then ev:Fire(player, id); print("[DevCommands] /opencrate " .. tostring(id or "(default)") .. " for " .. player.Name) end
	-- /infinitegut : grant the Infinite Gut tier (StomachMax 9999 + a meter that never drains), the same thing the
	--                1860686821 gamepass gives. Forces past FORCE_BASE_STOMACH, the balance-test switch that
	--                otherwise pins every gut to base and makes even a real purchase a no-op.
	elseif cmd == "/infinitegut" or cmd == "/infgut" then
		if not isTestUser(player) then return end
		if _G.devGrantInfiniteGut then
			_G.devGrantInfiniteGut(player)
			print("[DevCommands] /infinitegut for " .. player.Name)
		end
	-- /unlockall : grant every skin on every pet + one of each trait. ~230 inventory entries, so the panel takes
	--              a beat to build the first time you open INVENTORY after running it.
	elseif cmd == "/unlockall" or cmd == "/unlockallskins" then
		if not isTestUser(player) then return end
		local ev = ServerScriptService:FindFirstChild("DevUnlockAllSkins")
		if ev then ev:Fire(player); print("[DevCommands] /unlockall for " .. player.Name) end
	elseif cmd == "/goldtest" then
		if not isTestUser(player) then return end
		local ev = ServerScriptService:FindFirstChild("DevOpenCrate")
		if not ev then return end
		print("[DevCommands] /goldtest: opening until a Gold pull (max 5000) for " .. player.Name)
		task.spawn(function()
			for i = 1, 5000 do
				ev:Fire(player, nil, true) -- quiet: don't print 5000 lines
				if _G.skinLastPullWasGold and _G.skinLastPullWasGold(player) then
					print("[DevCommands] /goldtest: GOLD after " .. i .. " opens"); return
				end
				if i % 100 == 0 then task.wait() end -- yield periodically so the server stays responsive
			end
			print("[DevCommands] /goldtest: no Gold in 5000 opens")
		end)
	-- END SKIN CRATE TEST COMMANDS ------------------------------------------------------------------------
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

-- The modern chat (TextChatService) does NOT fire Player.Chatted, so EVERY command above is dead on a place
-- using it -- which is why /givetokens silently did nothing. Register real slash commands as well, exactly the
-- way RealmPortals.server.lua already does for /unlock. Harmless on the legacy chat (these simply never trigger
-- there, and the Player.Chatted path above covers that case).
--
-- One TextChatCommand per alias pair; Triggered hands us the full typed text, so it routes straight into the
-- SAME onChatted used by the legacy path -- no second implementation to drift.
do
	local ok, err = pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local function register(name, primary, secondary)
			local cmd = Instance.new("TextChatCommand")
			cmd.Name = name
			cmd.PrimaryAlias = primary
			if secondary then cmd.SecondaryAlias = secondary end
			cmd.Parent = TextChatService
			cmd.Triggered:Connect(function(source, unfilteredText)
				local plr = source and Players:GetPlayerByUserId(source.UserId)
				if plr then onChatted(plr, unfilteredText) end
			end)
		end
		register("DevCrateCommand",      "/crate",      "/resetcrate")
		register("DevGiveTokensCommand", "/givetokens", "/opencrate")
		register("DevGoldTestCommand",   "/goldtest",   "/unlockall")
		register("DevInfiniteGutCommand", "/infinitegut", "/infgut")
	end)
	if ok then print("[DevCommands] slash commands registered with TextChatService (/crate /resetcrate /givetokens /opencrate /goldtest /unlockall /infinitegut)")
	else warn("[DevCommands] TextChatService command registration failed: " .. tostring(err)) end
end
