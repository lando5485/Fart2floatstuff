--======================================================================
-- PurchaseBanner_AllInOne.server.lua  (Server Script)
--======================================================================
-- The SERVER side of the purchase-announcement banner, copied VERBATIM from
-- PlayerStats.server.lua. When a player buys a developer PRODUCT or a GAMEPASS,
-- the server broadcasts to EVERY client via PurchaseAnnouncementEvent, and each
-- client shows the gold banner (PurchaseBanner_AllInOne.client.lua).
--
-- Wiring: call announceProductPurchase() from your ProcessReceipt, and
-- announceGamepassPurchase() wherever a gamepass purchase is confirmed/granted.
-- Both are also exposed as _G functions. Drop into ServerScriptService.
--======================================================================

local Players           = game:GetService("Players")
local RS                = game:GetService("ReplicatedStorage")
local MarketplaceService= game:GetService("MarketplaceService")

-- the broadcast remote (created if missing)
local PAE = RS:FindFirstChild("PurchaseAnnouncementEvent")
if not PAE then PAE = Instance.new("RemoteEvent"); PAE.Name = "PurchaseAnnouncementEvent"; PAE.Parent = RS end

-- ===== ID -> display name maps (set these to YOUR real product/gamepass IDs) =====
local PRODUCT_IDS = { TwoXOneHour=3600302990, MidAirRecharge=3600303163, SkipIsland=3600303265, BirdNuke=3600303082 }
local GAMEPASS_IDS = { TwoXForever=1862015450, GlitterTrail=1859714979, InfiniteGut=1860686821 }

local PAE_productNames = {
	[PRODUCT_IDS.TwoXOneHour]    = "2x Power 1 Hour",
	[PRODUCT_IDS.MidAirRecharge] = "Mid-Air Recharge",
	[PRODUCT_IDS.SkipIsland]     = "Skip Island",
	[PRODUCT_IDS.BirdNuke]       = "Bird Nuke",
}
local passNames = {
	[GAMEPASS_IDS.TwoXForever]  = "2x Fart Power Forever",
	[GAMEPASS_IDS.GlitterTrail] = "Glitter Fart Trail",
	[GAMEPASS_IDS.InfiniteGut]  = "Infinite Gut",
}

-- ===== broadcast helpers (VERBATIM behavior) =====
-- developer product purchased -> banner to everyone (isGamepass = false -> 🎉 icon)
local function announceProductPurchase(player, productId)
	pcall(function() PAE:FireAllClients(player.Name, PAE_productNames[productId] or "an item", false) end)
end
-- gamepass purchased -> banner to everyone (isGamepass = true -> ⭐ icon)
local function announceGamepassPurchase(player, passId)
	pcall(function() PAE:FireAllClients(player.Name, passNames[passId] or "a gamepass", true) end)
end
_G.announceProductPurchase  = announceProductPurchase
_G.announceGamepassPurchase = announceGamepassPurchase
-- generic escape hatch if you want to announce anything: _G.announcePurchase("Name","Item",true/false)
_G.announcePurchase = function(name, item, isGamepass) pcall(function() PAE:FireAllClients(name, item, isGamepass and true or false) end) end

-- ===== GAMEPASS purchase -> announce (this server event is safe to connect) =====
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, wasPurchased)
	if wasPurchased then announceGamepassPurchase(plr, passId) end
end)

-- ===== DEVELOPER PRODUCT purchase -> announce =====
-- In the real game this is called from PlayerStats' SINGLE MarketplaceService.ProcessReceipt:
--   local function processReceipt(info)
--       local player = Players:GetPlayerByUserId(info.PlayerId)
--       ... grant the item ...
--       if player then announceProductPurchase(player, info.ProductId) end   -- <-- this line shows the banner
--       return Enum.ProductPurchaseDecision.PurchaseGranted
--   end
-- Only ONE script may own ProcessReceipt, so DON'T set it here if you already have one --
-- just call _G.announceProductPurchase(player, info.ProductId) from inside your existing receipt.
-- If you have NO ProcessReceipt yet, uncomment this minimal one:
--[[
MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if player then announceProductPurchase(player, info.ProductId) end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
]]

print("[PurchaseBanner] server ready -- gamepass purchases auto-announce; call _G.announceProductPurchase from your ProcessReceipt")
