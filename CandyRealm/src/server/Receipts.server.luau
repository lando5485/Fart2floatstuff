--!nonstrict
--======================================================================
-- Receipts.server.luau  (Script, ServerScriptService)
--======================================================================
-- THE ONE ProcessReceipt FOR THE CANDY REALM.
--
-- Roblox allows exactly one MarketplaceService.ProcessReceipt per server. This place did not have one. Every
-- other realm does: the Food realm's lives in PlayerStats, Space's lives in BoostProducts, and both fan out
-- to the individual systems through _G handlers. Candy's SkinCrateService was written for that arrangement --
-- it exposes _G.skinCrateHandleReceipt and says in its own comment that "PlayerStats owns ProcessReceipt" --
-- but no such script was ever ported here, so the handler had nothing calling it.
--
-- ===== WHAT THAT MEANT =====
-- Nothing, while every product id in this place was a placeholder and SkinCrates.TEST_MODE was true: no real
-- purchase could be prompted, so no receipt could arrive. The moment the real ids went in, it would have
-- become the worst bug a game can ship -- Robux taken, receipt handed to a server with no handler, nothing
-- granted. So this file went in with the ids, not after them.
--
-- ===== IF YOU ADD PRODUCTS =====
-- Add a branch to handleProduct below, or expose a _G handler and call it from the fan-out. Do NOT assign
-- MarketplaceService.ProcessReceipt anywhere else -- the second assignment silently replaces the first, and
-- whichever loses stops delivering.
--======================================================================

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")

if _G.__CandyReceipts then
	warn("[Receipts] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__CandyReceipts = true

--======================================================================
-- COIN PACKS
--======================================================================
-- The amounts live HERE, on the server, never in the shop card the client draws. A client can rewrite its own
-- label; it cannot rewrite this table, and a coin amount read from the client is an amount the client chooses.
--
-- Same ids as the Food and Space realms, which is correct rather than a copy-paste slip: developer products
-- are scoped to the UNIVERSE, not the place. One product, buyable in any realm, delivered by whichever realm
-- the player was standing in when they bought it.
local COIN_PACKS = {
	[3699050724] = 1000,      -- Small     49 R$
	[3699055852] = 5500,      -- Medium    99 R$
	[3699059563] = 12000,     -- Large     199 R$
	[3699065394] = 30000,     -- Giant     399 R$
	[3699081248] = 70000,     -- Mega      799 R$
	[3699076690] = 180000,    -- Ultimate  1499 R$
}

-- Purchased coins go to Coins and deliberately NOT to TotalCoinsEarned -- which is why this writes the
-- leaderstat directly instead of calling PlayerState.addCoins, which bumps both. TotalCoinsEarned is the
-- record of what a player FLEW for and it is what the leaderboard reads; letting Robux write to it would put
-- paying players at the top of a board that is supposed to measure climbing.
local function grantCoins(player, amount)
	local ls = player:FindFirstChild("leaderstats")
	local c  = ls and ls:FindFirstChild("Coins")
	if not c then return false end
	c.Value = c.Value + amount
	pcall(function()
		local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
		if PlayerState.pushSnapshot then PlayerState.pushSnapshot(player) end
	end)
	return true
end

--======================================================================
-- FAN-OUT
--======================================================================
-- Returns true only when the product was recognised AND granted. Anything else must return false, so the
-- receipt goes unconsumed and Roblox hands it back rather than the player paying for nothing.
local function handleProduct(player, productId)
	local packCoins = COIN_PACKS[productId]
	if packCoins then
		if not grantCoins(player, packCoins) then
			-- No leaderstats yet means the join load has not finished. Reported as not-granted so Roblox
			-- retries shortly, which is exactly what stops coins being lost by buying during a slow join.
			warn(("[Receipts] coin pack %d arrived before %s finished loading -- asking Roblox to retry")
				:format(productId, player.Name))
			return false
		end
		if _G.savePlayerData then pcall(_G.savePlayerData, player, "coinpack") end
		print(("[Receipts] %s bought %d coins (product %d)"):format(player.Name, packCoins, productId))
		return true
	end

	-- CRATE TOKEN packs. SkinCrateService owns a disjoint set of ids (SkinCrates.TOKEN_PACKS) and credits the
	-- tokens itself; it only ever returns true for ids it recognises.
	if _G.skinCrateHandleReceipt then
		local ok, granted = pcall(_G.skinCrateHandleReceipt, player, productId)
		if ok and granted then
			print(("[Receipts] product %d handled by SkinCrateService (token pack)"):format(productId))
			return true
		end
	end

	-- Anything a future system registers. Kept as a loop so adding one is a one-line change here rather than
	-- another copy of the same six lines.
	for _, name in ipairs({ "petsHandleReceipt", "gardenHandleDonationReceipt",
		"sourRainHandleReceipt" }) do
		local fn = _G[name]
		if type(fn) == "function" then
			local ok, granted = pcall(fn, player, productId)
			if ok and granted then
				print(("[Receipts] product %d handled by %s"):format(productId, name))
				return true
			end
		end
	end

	return false
end

--======================================================================
-- THE ONE ProcessReceipt
--======================================================================
-- Roblox may deliver the same PurchaseId more than once (a retry after a transient error). Granting twice off
-- one payment is the mirror image of granting zero times, so a handled purchase is remembered for the life of
-- the server and re-reported as granted rather than re-delivered.
local processed = {}
Players.PlayerRemoving:Connect(function(p)
	local prefix = tostring(p.UserId) .. ":"
	for k in pairs(processed) do
		if k:sub(1, #prefix) == prefix then processed[k] = nil end
	end
end)

MarketplaceService.ProcessReceipt = function(info)
	local key = tostring(info.PlayerId) .. ":" .. tostring(info.PurchaseId)
	if processed[key] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		-- Buyer left before the grant. Retry when they are back.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(handleProduct, player, info.ProductId)
	if not ok then
		warn(("[Receipts] error handling product %d for %s: %s")
			:format(info.ProductId, player.Name, tostring(granted)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not granted then
		-- NOT granted, on purpose, even though it means Roblox will keep offering this receipt.
		--
		-- The alternative -- report success on an id nobody handles, to stop the retries -- turns a bug that
		-- can still be fixed into money the player will never see. While the receipt stays unconsumed, adding
		-- the missing branch is enough to deliver it retroactively. It is the noisier failure and the only
		-- recoverable one.
		warn(("[Receipts] UNHANDLED product %d bought by %s -- receipt left unconsumed. Add a branch for it.")
			:format(info.ProductId, player.Name))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	processed[key] = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

print("[Receipts] ready -- Candy realm ProcessReceipt owner (coin packs + token packs)")
