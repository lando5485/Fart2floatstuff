--!nonstrict
--======================================================================
-- StomachUpgrade.server.luau  (Server Script)  -- CandyRealm
--======================================================================
-- Backend for StomachShop_AllInOne.client.lua, reworked for the Dino-Realm-style
-- 12-tier gut ladder. Contract unchanged:
--   * client reads state from leaderstats.Coins / leaderstats.StomachMax
--   * client buys via  _G.BuyStomachEvent:FireServer(tierName)  -- a STRING name
--
-- WHAT CHANGED in the port:
--   * The tier table MOVED OUT to ReplicatedStorage.Shared.StomachTiers -- one
--     table, required by both sides, so panel and server can never drift.
--   * unlockSlot GATE: tier k opens the crossing from slot k to k+1, so it is
--     bought while STANDING on slot k. Without this a player could farm island 1
--     and buy the Jawbreaker Gut outright, skipping every wall the 12 tiers exist
--     to build. Checked HERE, not just drawn in the panel.
--   * STRICT UPGRADE ONLY -- a client cannot "buy" a cheaper tier and shrink its
--     own tank.
--   * COURTESY FILL: a new gut arrives holding enough power to cross the gap
--     actually in front of the player x 1.10 (FlightTuning.courtesyPower), never
--     more than the tank, and never less than the scaled-over old fill.
--
-- Coin income is FlightEconomy.server.luau (0.14 coins per stud climbed).
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local StomachTiers = require(Shared:WaitForChild("StomachTiers"))
local FlightTuning = require(Shared:WaitForChild("FlightTuning"))

local DEFAULT_MAX = StomachTiers.LIST[1].maxPower -- Gumdrop Belly (110)

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

-- Ensure the leaderstats scaffold this shop reads. Only fills in what's missing --
-- SAME defaults as FlightEconomy.ensureStats, so creation order is irrelevant.
local function ensureStats(player)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player end

	local coins = ls:FindFirstChild("Coins")
	if not coins then coins = Instance.new("IntValue"); coins.Name = "Coins"; coins.Value = 120; coins.Parent = ls end

	local sm = ls:FindFirstChild("StomachMax")
	if not sm then sm = Instance.new("IntValue"); sm.Name = "StomachMax"; sm.Value = DEFAULT_MAX; sm.Parent = ls end

	local cp = ls:FindFirstChild("CurrentPower")
	if not cp then cp = Instance.new("NumberValue"); cp.Name = "CurrentPower"; cp.Value = 0; cp.Parent = ls end

	return ls, coins, sm, cp
end

-- ============================================================================
-- THE ROBUX GUT -- Infinite Gut gamepass (Shared.Gamepasses.IDS.InfiniteGut)
-- ============================================================================
-- The Sugar Rush Gut row in the shop is a GAMEPASS, so it never comes through BuyStomachEvent (which drops
-- robux tiers on the floor, below). OWNING THE PASS IS THE PURCHASE: PassOwnership publishes HasInfiniteGut,
-- and this raises the tank off that attribute.
--
-- Driven by the attribute rather than by PromptGamePassPurchaseFinished on purpose -- one code path covers the
-- fresh purchase AND every future join, so the gut is permanent without anything having to persist it. It is
-- idempotent (a strict upgrade, exactly like a coin tier), so re-running it on a player who already has the
-- tank does nothing.
local Gamepasses = require(Shared:WaitForChild("Gamepasses"))
local ROBUX_TIER do
	for _, t in ipairs(StomachTiers.LIST) do
		if t.robux then ROBUX_TIER = t; break end
	end
end

local function applyGutPass(player)
	if not ROBUX_TIER then return end
	if not Gamepasses.owns(player, "InfiniteGut") then return end

	local _, _, sm, cp = ensureStats(player)
	if sm.Value >= ROBUX_TIER.maxPower then return end -- already at (or above) the pass tank

	local oldMax = sm.Value
	sm.Value = ROBUX_TIER.maxPower

	-- Same courtesy fill a coin tier gets: keep the fraction they were holding, floored at enough power to
	-- cross the gap actually in front of them. A 9999 tank arriving EMPTY would feel like a broken purchase.
	local reached  = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1)
	local gap      = FlightTuning.gapFromSlot(reached)
	local frac     = (oldMax > 0) and (cp.Value / oldMax) or 0
	local scaled   = math.floor(frac * ROBUX_TIER.maxPower)
	local courtesy = FlightTuning.courtesyPower(ROBUX_TIER.maxPower, gap)
	cp.Value = math.clamp(math.max(scaled, courtesy), cp.Value, ROBUX_TIER.maxPower)

	pcall(function() RegenEvent:FireClient(player, 0, cp.Value, sm.Value) end)
	pcall(function() StomachUpdateEvent:FireClient(player, ROBUX_TIER.maxPower, ROBUX_TIER.name) end)
	print(("[StomachUpgrade] %s owns the Infinite Gut pass -- granted %s (max %d, fill %d)")
		:format(player.Name, ROBUX_TIER.name, ROBUX_TIER.maxPower, cp.Value))
end

local function watchGutPass(player)
	ensureStats(player)
	local attr = Gamepasses.ATTR.InfiniteGut
	if not attr then return end
	-- PassOwnership resolves ownership asynchronously, so the attribute usually arrives AFTER this connects.
	-- Both the listener and the immediate call are needed: the listener catches the join round trip and any
	-- later purchase, the direct call catches a player whose attribute was already set (script reload in Studio).
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
	if tier.robux then return end -- Robux tiers are the Infinite Gut GAMEPASS; see applyGutPass above

	local _, coins, sm, cp = ensureStats(player)

	-- STRICT UPGRADE ONLY
	if tier.maxPower <= sm.Value then return end

	-- ANTI-SKIP: you must have REACHED the slot this gut belongs to.
	local reached = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1)
	if not StomachTiers.isUnlocked(tier, reached) then
		print(("[StomachUpgrade] %s cannot buy %s yet: on slot %d, needs slot %d")
			:format(player.Name, tier.name, reached, tier.unlockSlot or 1))
		pcall(function() StomachFullEvent:FireClient(player, "gut_locked") end)
		return
	end

	-- THE PRICE IS THE SERVER'S (from the shared table); the client only names the tier.
	if coins.Value < tier.cost then
		print(("[StomachUpgrade] %s cannot afford %s: %d < %d"):format(player.Name, tier.name, coins.Value, tier.cost))
		pcall(function() StomachFullEvent:FireClient(player, "not_enough_coins") end)
		return
	end

	coins.Value = coins.Value - tier.cost
	local oldMax = sm.Value
	sm.Value = tier.maxPower

	-- COURTESY FILL, measured against the gap the player is actually at (a gut is
	-- bought at the END of the previous tier, so the next crossing is the shorter
	-- one underneath its own). Never worse than the scaled-over old fill.
	local gap  = FlightTuning.gapFromSlot(reached)
	local frac = (oldMax > 0) and (cp.Value / oldMax) or 0
	local scaled   = math.floor(frac * tier.maxPower)
	local courtesy = FlightTuning.courtesyPower(tier.maxPower, gap)
	cp.Value = math.clamp(math.max(scaled, courtesy), cp.Value, tier.maxPower)

	pcall(function() RegenEvent:FireClient(player, 0, cp.Value, sm.Value) end)
	pcall(function() StomachUpdateEvent:FireClient(player, tier.maxPower, tier.name) end)
	print(("[StomachUpgrade] %s bought %s (max %d) for %d coins -- courtesy fill %d (next gap %s)")
		:format(player.Name, tier.name, tier.maxPower, tier.cost, cp.Value, gap and tostring(math.floor(gap)) or "?"))
end)

print(("[StomachUpgrade] server ready -- shared StomachTiers, unlockSlot gate, courtesy fill, Infinite Gut pass %s%s")
	:format(tostring(Gamepasses.IDS.InfiniteGut),
		Gamepasses.FORCE_UNOWNED and "  [FORCE_UNOWNED is ON -- the pass grants nothing until it is false]" or ""))
