--!nonstrict
--======================================================================
-- StomachUpgrade.server.luau  (Server Script)  -- CandyRealm
--======================================================================
-- CandyRealm is a SEPARATE place (same universe), so it runs its OWN server
-- scripts -- the food realm's PlayerStats.server.lua does NOT run here. That
-- realm's RealmServer is a stub that never builds leaderstats, so the Stomach
-- shop had no backend: no BuyStomachEvent, no StomachMax, no Coins.
--
-- Backend for the EXISTING StomachShop_AllInOne.client.lua, matching its exact
-- contract:
--   * client reads state from leaderstats.Coins / leaderstats.StomachMax
--   * client buys via  _G.BuyStomachEvent:FireServer(tierName)  -- a STRING name
--     (the EconomyBootstrap.client.luau binds _G.BuyStomachEvent to the RemoteEvent
--      this script creates, since CandyRealm has no CoreClient to do CoreClient:1741)
--
-- Provides a SELF-SUFFICIENT stomach backend:
--   * Ensures leaderstats + Coins / StomachMax / CurrentPower exist per player
--     (created ONLY if absent -- if a future save/receiver builds leaderstats
--     first, this reuses it and never clobbers real values).
--   * Handles BuyStomachEvent(tierName): validates against the SAME tiers the
--     client shows, checks Coins, deducts, raises StomachMax, clamps CurrentPower.
--
-- ⚠ COINS SOURCE: this realm (in this folder) has no coin income -- coins are
-- expected to arrive via TeleportData from the food realm (RealmServer's receiver,
-- currently a stub). The shop is fully functional; players just need Coins to come
-- from somewhere. Nothing here mints free coins.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===== TIERS -- keyed by NAME; values MUST match StomachShop_AllInOne.client.lua's TIERS =====
local TIERS = {
	{ name="Tiny Gut",     max=40,    cost=0,      robux=false },
	{ name="Small Gut",    max=96,    cost=200,    robux=false },
	{ name="Medium Gut",   max=282,   cost=1500,   robux=false },
	{ name="Large Gut",    max=603,   cost=8000,   robux=false },
	{ name="XL Gut",       max=1425,  cost=40000,  robux=false },
	{ name="Iron Gut",     max=2639,  cost=200000, robux=false },
	{ name="Infinite Gut", max=99999, cost=499,    robux=true  },
}
local TIER_BY_NAME = {}
for _, t in ipairs(TIERS) do TIER_BY_NAME[t.name] = t end
local DEFAULT_MAX = TIERS[1].max -- Tiny Gut

-- ===== getOrCreate helpers (never clobber existing instances/values) =====
local BuyStomachEvent = ReplicatedStorage:FindFirstChild("BuyStomachEvent")
if not BuyStomachEvent then
	BuyStomachEvent = Instance.new("RemoteEvent"); BuyStomachEvent.Name = "BuyStomachEvent"; BuyStomachEvent.Parent = ReplicatedStorage
end

-- Ensure the leaderstats scaffold this shop reads. Only fills in what's missing,
-- so any real save/receiver system that runs first keeps ownership of the values.
local function ensureStats(player)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player end

	local coins = ls:FindFirstChild("Coins")
	if not coins then coins = Instance.new("IntValue"); coins.Name = "Coins"; coins.Value = 0; coins.Parent = ls end

	local sm = ls:FindFirstChild("StomachMax")
	if not sm then sm = Instance.new("IntValue"); sm.Name = "StomachMax"; sm.Value = DEFAULT_MAX; sm.Parent = ls end

	local cp = ls:FindFirstChild("CurrentPower")
	if not cp then cp = Instance.new("NumberValue"); cp.Name = "CurrentPower"; cp.Value = 0; cp.Parent = ls end

	return ls, coins, sm, cp
end

Players.PlayerAdded:Connect(ensureStats)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(ensureStats, p) end -- Studio Play Solo / live reload

-- ===== PURCHASE HANDLER -- client sends the tier NAME (string) =====
BuyStomachEvent.OnServerEvent:Connect(function(player, tierName)
	if type(tierName) ~= "string" then return end
	local tier = TIER_BY_NAME[tierName]
	if not tier then return end
	if tier.robux then return end -- Robux tiers are not bought through this event (no DevProduct wired)

	local _, coins, sm, cp = ensureStats(player)
	if tier.max <= sm.Value then return end   -- already at/above this tier
	if coins.Value < tier.cost then return end -- can't afford

	coins.Value = coins.Value - tier.cost
	sm.Value    = tier.max
	cp.Value    = math.min(cp.Value, tier.max) -- carry current power, clamp to new tank

	print(("[StomachUpgrade] %s bought %s (max %d) for %d coins"):format(player.Name, tier.name, tier.max, tier.cost))
end)

print("[StomachUpgrade] server ready -- leaderstats scaffold + BuyStomachEvent(tierName) handler")
