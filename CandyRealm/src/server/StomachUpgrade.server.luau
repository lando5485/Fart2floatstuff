--!nonstrict
--======================================================================
-- StomachUpgrade.server.luau  (Server Script)  -- CandyRealm
-- FOOD-REALM PORT: guts are bought with coins and gated by the island you have reached.
--======================================================================
-- Backend for StomachShop_AllInOne.client.lua. Contract unchanged:
--   * client reads state from leaderstats.Coins / leaderstats.StomachMax
--   * client buys via  _G.BuyStomachEvent:FireServer(tierName)  -- a STRING name
--
-- ===== THE THREE CONDITIONS, ALL ENFORCED HERE (the panel only draws the lock) =====
--   (1) MUST BE AN UPGRADE -- strictly bigger than the tank already owned. A re-buy of the
--       current gut, or a SMALLER one, is refused: the server would otherwise take the coins
--       and shrink StomachMax.
--   (2) THE ISLAND GATE -- the player must have physically REACHED tier.unlockSlot (the
--       HighestSlot attribute, raised only by FlightEconomy's landing detection). Tier k
--       unlocks on the island below its wall, so you fly the wall first, fall 2% short, and
--       THEN the shop sells you the gut. Enforced here because the client's shop is only a
--       display: it can be a stale baked-in copy, or simply lied to.
--   (3) THEY CAN AFFORD IT -- at the SERVER's price, from the shared table. The client only
--       names a tier.
-- Nothing is charged on a rejected buy.
--
-- QUESTS DO NOT GATE THIS ANY MORE. The space port refused every buy until the island's quest
-- was ledgered (and paid the gut's cost as the quest reward). The food model has one purse:
-- flight coins buy food AND guts, and the wall spacing -- not a quest -- is what makes each
-- gut mandatory. Quests keep their own coin rewards and gate their island's FOOD STAND.
--
-- A NEW GUT ARRIVES EMPTY (FlightTuning.COURTESY_FRACTION = 0). Whatever was already in the
-- tank is KEPT (clamped to the new capacity) but nothing is added. It used to come full, and
-- that handed out a free crossing with every purchase.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local StomachTiers = require(Shared:WaitForChild("StomachTiers"))
local IslandOrder  = require(Shared:WaitForChild("IslandOrder"))
local Constants    = require(Shared:WaitForChild("Constants"))

-- Tier 1's tank (120, the Gumdrop Belly). A fresh player can fly at once.
local DEFAULT_MAX = StomachTiers.getTier(Constants.STARTING_STOMACH_TIER).maxPower

-- ===== remotes =====
local function ev(name)
	local e = ReplicatedStorage:FindFirstChild(name)
	if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = ReplicatedStorage end
	return e
end
local BuyStomachEvent    = ev("BuyStomachEvent")
local StomachFullEvent   = ev("StomachFullEvent")   -- s->c: rejection reasons
local StomachUpdateEvent = ev("StomachUpdateEvent") -- s->c: (newMax, tierName)
local RegenEvent         = ev("RegenEvent")         -- s->c: (powerAdded, currentPower, stomachMax)

-- Ensure the leaderstats scaffold this shop reads. Only fills in what is missing --
-- SAME Constants as FlightEconomy.ensureStats, so creation order is irrelevant.
local function ensureStats(player)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player end

	local coins = ls:FindFirstChild("Coins")
	if not coins then
		coins = Instance.new("IntValue"); coins.Name = "Coins"
		coins.Value = Constants.STARTING_COINS; coins.Parent = ls
	end

	local sm = ls:FindFirstChild("StomachMax")
	if not sm then
		sm = Instance.new("IntValue"); sm.Name = "StomachMax"
		sm.Value = DEFAULT_MAX; sm.Parent = ls
	end

	local cp = ls:FindFirstChild("CurrentPower")
	if not cp then
		cp = Instance.new("NumberValue"); cp.Name = "CurrentPower"
		cp.Value = Constants.STARTING_POWER; cp.Parent = ls
	end

	return ls, coins, sm, cp
end

-- KEEP THE FUEL, GRANT NONE. Both purchase paths call this. A bigger tank never destroys
-- what you were carrying, and never adds to it either.
local function keepFuel(cp, tier)
	cp.Value = math.clamp(cp.Value, 0, tier.maxPower)
	return cp.Value
end

-- ============================================================================
-- THE ROBUX GUT -- Infinite Gut gamepass (Shared.Gamepasses.IDS.InfiniteGut)
-- ============================================================================
-- The Sugar Rush Gut row in the shop is a GAMEPASS, so it never comes through
-- BuyStomachEvent (which drops robux tiers on the floor, below). OWNING THE PASS IS THE
-- PURCHASE: PassOwnership publishes HasInfiniteGut, and this raises the tank off that
-- attribute. Idempotent (a strict upgrade, exactly like a coin tier). Not island-gated: it
-- is a purchase, not a progression step.
local Gamepasses = require(Shared:WaitForChild("Gamepasses"))
local ROBUX_TIER = StomachTiers.SUGAR_RUSH

local function applyGutPass(player)
	if not Gamepasses.owns(player, "InfiniteGut") then return end

	local _, _, sm, cp = ensureStats(player)
	if sm.Value >= ROBUX_TIER.maxPower then return end -- already at (or above) the pass tank

	sm.Value = ROBUX_TIER.maxPower
	keepFuel(cp, ROBUX_TIER)

	pcall(function() RegenEvent:FireClient(player, 0, cp.Value, sm.Value) end)
	pcall(function() StomachUpdateEvent:FireClient(player, ROBUX_TIER.maxPower, ROBUX_TIER.name) end)
	print(("[StomachUpgrade] %s owns the Infinite Gut pass -- granted %s (max %d, fill %d)")
		:format(player.Name, ROBUX_TIER.name, ROBUX_TIER.maxPower, cp.Value))
end

local function watchGutPass(player)
	ensureStats(player)
	local attr = Gamepasses.ATTR.InfiniteGut
	if not attr then return end
	player:GetAttributeChangedSignal(attr):Connect(function() applyGutPass(player) end)
	applyGutPass(player)
end

Players.PlayerAdded:Connect(ensureStats)
Players.PlayerAdded:Connect(watchGutPass)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(ensureStats, p); task.spawn(watchGutPass, p) end

-- ===== PURCHASE HANDLER -- client sends the tier NAME (string) =====
BuyStomachEvent.OnServerEvent:Connect(function(player, tierName)
	if type(tierName) ~= "string" then return end
	local tier = StomachTiers.BY_NAME[tierName]
	if not tier then return end
	if tier.robux then return end -- Robux tiers are the Infinite Gut GAMEPASS; see applyGutPass
	if tier.cost <= 0 then return end -- the starting gut is not for sale

	local _, coins, sm, cp = ensureStats(player)

	-- (1) MUST BE AN UPGRADE.
	if tier.maxPower <= sm.Value then
		pcall(function() StomachFullEvent:FireClient(player, "already_owned") end)
		return
	end

	-- (2) THE ISLAND GATE. HighestSlot is written only by server code (FlightEconomy's
	--     landing detection), never by client input.
	local reached = math.max(1, math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1))
	if not StomachTiers.isUnlocked(tier, reached) then
		print(("[StomachUpgrade] %s cannot buy %s yet: needs slot %d, reached %d")
			:format(player.Name, tier.name, tier.unlockSlot or 1, reached))
		pcall(function()
			StomachFullEvent:FireClient(player, "gut_locked", tier.name, tier.unlockSlot,
				IslandOrder.NAMES[tier.unlockSlot or 1])
		end)
		return
	end

	-- (3) THE PRICE IS THE SERVER'S (from the shared table); the client only names the tier.
	if coins.Value < tier.cost then
		print(("[StomachUpgrade] %s cannot afford %s: %d < %d")
			:format(player.Name, tier.name, coins.Value, tier.cost))
		pcall(function() StomachFullEvent:FireClient(player, "not_enough_coins") end)
		return
	end

	coins.Value = coins.Value - tier.cost
	sm.Value = tier.maxPower
	keepFuel(cp, tier)

	pcall(function() RegenEvent:FireClient(player, 0, cp.Value, sm.Value) end)
	pcall(function() StomachUpdateEvent:FireClient(player, tier.maxPower, tier.name) end)
	print(("[StomachUpgrade] %s bought %s (max %d) for %d coins at slot %d -- tank arrives with %d "
		.. "(what they were already carrying; a gut grants no fuel)")
		:format(player.Name, tier.name, tier.maxPower, tier.cost, reached, cp.Value))
end)

print(("[StomachUpgrade] server ready -- %d coin tiers gated by island reached (start tank %d), Infinite Gut pass %s%s")
	:format(StomachTiers.MAX_TIER, DEFAULT_MAX, tostring(Gamepasses.IDS.InfiniteGut),
		Gamepasses.FORCE_UNOWNED and "  [FORCE_UNOWNED is ON -- the pass grants nothing until it is false]" or ""))
