-- ============================================================================================================
-- PASS OWNERSHIP (server) -- resolves who owns which gamepass, and publishes it as a player attribute.
-- ============================================================================================================
-- WHY THIS FILE EXISTS IN CANDY REALM
-- In the Food realm this job is done inside PlayerStats (its join-time UserOwnsGamePassAsync loop and its
-- PromptGamePassPurchaseFinished handler). Candy has no PlayerStats -- so before this file, NOTHING in this
-- realm ever asked Roblox who owned what, and no ownership attribute was ever set. Every pass read as un-owned
-- here no matter what the player had actually bought.
--
-- WHAT IT PUBLISHES
-- One boolean attribute per pass (Gamepasses.ATTR: HasVIP, HasLuckyPass, ...). Player attributes replicate to
-- every client automatically, so ownership needs no remotes, works for late joiners, is readable from both
-- sides, and costs one web call per pass per join and nothing thereafter. Everything else in the realm --
-- Gamepasses.owns(), the shop cards' OWNED state, the VIP tag, the crate luck -- reads those attributes and
-- never asks Roblox anything itself.
--
-- WHAT IT DOES NOT DO
-- It grants no perk. Each perk lives with its own system (VipService pays the stipend, RewardsService adds the
-- coin share, SkinCrateService reads luck at roll time). This file only answers "do they own it".
--
-- FAILURE BEHAVIOUR
-- A failed ownership check leaves the attribute UNSET rather than false. Writing false on a transient Roblox
-- error would strip a paying customer's pass for the session; leaving it unset means owns() returns false for
-- now and a rejoin fixes it. Never punish a player for a web hiccup.
-- ============================================================================================================

local Players            = game:GetService("Players")
local RS                 = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Gamepasses = require(RS:WaitForChild("Shared"):WaitForChild("Gamepasses"))

local function resolveFor(player)
	for key, id in pairs(Gamepasses.configured()) do -- configured() skips any pass still sitting at id 0
		task.spawn(function()
			local attr = Gamepasses.ATTR[key]
			if not attr then return end

			-- [TESTING] FORCE_UNOWNED makes every pass read un-owned so the buy flows can be tested on an
			-- account that owns them. Roblox reports the CREATOR of a pass as owning it, so without this the
			-- dev account can never see a shop card in its un-owned state. Set it false before publishing.
			if Gamepasses.FORCE_UNOWNED then
				player:SetAttribute(attr, false)
				return
			end

			-- Current id AND any superseded one granting the same perk (Gamepasses.LEGACY_IDS). The realms share
			-- one experience, so a pass bought in another realm is owned here too.
			local ok, owns = pcall(function()
				for _, passId in ipairs(Gamepasses.allIdsFor(key)) do
					if MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId) then return true end
				end
				return false
			end)
			if not ok then
				warn(("[PassOwnership] ownership check FAILED for %s / %s -- leaving unset (a rejoin retries)")
					:format(player.Name, key))
				return -- deliberately NOT false; see FAILURE BEHAVIOUR above
			end
			player:SetAttribute(attr, owns and true or false)
			if owns then print(("[PassOwnership] %s owns %s"):format(player.Name, Gamepasses.NAMES[key] or key)) end
		end)
	end
end

Players.PlayerAdded:Connect(resolveFor)
for _, p in ipairs(Players:GetPlayers()) do resolveFor(p) end -- Studio play-solo / live reload

-- A fresh purchase must take effect immediately -- the perk systems all watch these attributes, so setting one
-- here is the whole grant. No rejoin, no remote, no second code path that could disagree with the join check.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if not wasPurchased then return end
	local key = Gamepasses.keyForId(passId)   -- nil for a pass that is not ours, and for any id still at 0
	if not key then return end
	local attr = Gamepasses.ATTR[key]
	if not attr then return end
	if Gamepasses.FORCE_UNOWNED then
		warn(("[PassOwnership] %s bought %s but FORCE_UNOWNED is on -- not granting. Turn it off to go live.")
			:format(player.Name, Gamepasses.NAMES[key] or key))
		return
	end
	player:SetAttribute(attr, true)
	print(("[PassOwnership] %s PURCHASED %s -- granted immediately"):format(player.Name, Gamepasses.NAMES[key] or key))
end)

do
	local n = 0
	for _ in pairs(Gamepasses.configured()) do n = n + 1 end
	print(("[PassOwnership] ready -- %d configured pass(es)%s"):format(
		n, Gamepasses.FORCE_UNOWNED and "  [TESTING: FORCE_UNOWNED is ON, everything reads un-owned]" or ""))
end
