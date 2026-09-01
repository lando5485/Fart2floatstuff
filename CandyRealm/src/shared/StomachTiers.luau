--!nonstrict
--======================================================================
-- StomachTiers.luau  (ModuleScript -> ReplicatedStorage.Shared)  -- CandyRealm
-- FOOD-REALM PORT: the first realm's seven coin guts + the Robux gut, prices copied exactly.
--======================================================================
-- Kept in ONE place because the SHOP UI (StomachShop_AllInOne.client) and the PURCHASE
-- HANDLER (StomachUpgrade.server) both read it -- two copies is how the dino realm's
-- panel showed 1600 while its server charged 112 and every gut silently became unbuyable.
--
-- ===== WHAT A TIER IS =====
-- "Gut tier" == how much power the player can hold (maxPower), which gates how far a full
-- tank flies (FlightTuning.BASE_TIERS -- maxPower MUST match row for row; asserted below).
-- SEVEN coin tiers. You START with tier 1 (the food realm's Tiny Gut, 120): a new player
-- can fly from the first second, and the 630-stud tutorial crossing is 1.355x inside its
-- reach. Tiers 2..7 are BOUGHT WITH COINS from the GUT panel.
--
-- ===== ONE GUT = ONE WALL + ONE STRETCH =====
-- Every gut past the first covers exactly two crossings. The WALL gap above the previous
-- gut's island is that gut's full-tank climb x 1.020 -- you get 97%+ of the way on a full
-- tank and cannot land; that 2% is the "buy a gut" message, delivered by the flight. The
-- STRETCH gap is the new gut's climb / 1.031 (97% of the tank). Guts are therefore
-- MANDATORY by reach -- there is no flight ceiling any more, the spacing IS the wall.
--
-- ===== THE TWO LOCKS ON A GUT =====
--   cost        -- the coin price. Each gut costs less than the crossing before its wall
--                  pays out, so saving for it is short.
--   unlockSlot  -- the climb slot you must have REACHED (stood on) before you may buy it.
--                  Tier k unlocks on the island BELOW its wall: you arrive on slot 2k-2
--                  with the old gut, fly the wall, fall 2% short, and the shop sells you
--                  the tank that makes it. StomachUpgrade enforces this against HighestSlot.
--
-- A PURCHASED GUT ARRIVES EMPTY (FlightTuning.COURTESY_FRACTION = 0). Whatever was in the
-- tank is kept (clamped). It used to come full, which handed out a free crossing with every
-- purchase.
--
-- QUESTS NO LONGER FUND OR GATE GUTS. Under the space port each island's quest paid exactly
-- the next gut's cost and the buy was refused until the quest was done. Under the food
-- model the quests are content: they pay their own coin rewards (through CoinEvent, like
-- everything else) plus crate tokens, and they still gate the FOOD STAND on their island
-- (Shop_AllInOne's stand gate), but the gut you need is bought out of flight coins.
--======================================================================

local StomachTiers = {}

-- ============================================================================
-- THE SEVEN GUTS  (food realm: Tiny / Small / Medium / Large / XL / XXL / Iron)
-- ============================================================================
--   maxPower   = tank capacity. == FlightTuning.BASE_TIERS[i].maxPower (asserted at boot).
--   cost       = coin price (0 for the starting tier).
--   unlockSlot = the slot you must have reached to buy it (== the food realm's `island`).
--   robux      = false for every row here; the Robux gut is SUGAR_RUSH below.
--   questId    = nil -- kept as a field so older readers (the shop panel) find nothing rather
--                than erroring. No quest funds a gut any more.
StomachTiers.CANDY_GUTS = {
	{ name = "Gumdrop Belly", maxPower = 120,  cost = 0,     unlockSlot = 1,  questId = nil, emoji = "\u{1F36C}", robux = false }, -- Tiny   (start; c1)
	{ name = "Taffy Tummy",   maxPower = 270,  cost = 1000,  unlockSlot = 2,  questId = nil, emoji = "\u{1F36D}", robux = false }, -- Small  (c2 wall, c3 stretch)
	{ name = "Cookie Gut",    maxPower = 470,  cost = 2000,  unlockSlot = 4,  questId = nil, emoji = "\u{1F36A}", robux = false }, -- Medium (c4, c5)
	{ name = "Jelly Belly",   maxPower = 620,  cost = 4000,  unlockSlot = 6,  questId = nil, emoji = "\u{1F36E}", robux = false }, -- Large  (c6, c7)
	{ name = "Gummy Gut",     maxPower = 1080, cost = 5000,  unlockSlot = 8,  questId = nil, emoji = "\u{1F43B}", robux = false }, -- XL     (c8, c9)
	{ name = "Choco Stomach", maxPower = 1710, cost = 6000,  unlockSlot = 10, questId = nil, emoji = "\u{1F36B}", robux = false }, -- XXL    (c10, c11)
	{ name = "Caramel Core",  maxPower = 2600, cost = 11500, unlockSlot = 12, questId = nil, emoji = "\u{1F36F}", robux = false }, -- Iron   (c12 -- the summit wall)
}

-- The SUGAR RUSH tier -- candy's Infinite Gut (the food realm's "Infinite Gut", 9999, 499 R$).
-- NOT part of the normal chain: it is the Robux gamepass, granted by StomachUpgrade off the
-- HasInfiniteGut attribute. Owners never drain -- the meter is re-topped every frame.
StomachTiers.SUGAR_RUSH = {
	name = "Sugar Rush Gut", maxPower = 9999, cost = 499,
	unlockSlot = 1, questId = nil, emoji = "\u{26A1}", robux = true,
}

-- Number of normal (non-Robux) tiers -- the length of the coin ladder.
StomachTiers.MAX_TIER = #StomachTiers.CANDY_GUTS

-- LIST is what the SHOP PANEL iterates, so it carries the Robux row on the end. Anything
-- walking the PROGRESSION ladder must use CANDY_GUTS / MAX_TIER instead, or it will treat
-- Sugar Rush as tier 8.
StomachTiers.LIST = {}
for i, tier in ipairs(StomachTiers.CANDY_GUTS) do
	StomachTiers.LIST[i] = tier
end
StomachTiers.LIST[#StomachTiers.LIST + 1] = StomachTiers.SUGAR_RUSH

StomachTiers.BY_NAME = {}
StomachTiers.NAME_BY_MAX = {}
for _, tier in ipairs(StomachTiers.LIST) do
	StomachTiers.BY_NAME[tier.name] = tier
	StomachTiers.NAME_BY_MAX[tier.maxPower] = tier.name
end

-- tier NAME -> its index on the ladder (nil for Sugar Rush, which is not on it).
StomachTiers.INDEX_BY_NAME = {}
for i, tier in ipairs(StomachTiers.CANDY_GUTS) do
	StomachTiers.INDEX_BY_NAME[tier.name] = i
end

--[[ The Tier definition for a ladder index, clamped to range. ]]
function StomachTiers.getTier(index: number)
	local i = math.clamp(math.floor(tonumber(index) or 1), 1, StomachTiers.MAX_TIER)
	return StomachTiers.CANDY_GUTS[i]
end

--[[ Look a tier up by tank size -- the server reads the PRICE off its own table, so a
     client-sent cost can never change what it pays. ]]
function StomachTiers.byMaxPower(maxPower: number)
	local target = tonumber(maxPower)
	if not target then
		return nil
	end
	for _, tier in ipairs(StomachTiers.LIST) do
		if tier.maxPower == target then
			return tier
		end
	end
	return nil
end

--[[ The ladder INDEX a stored StomachMax corresponds to. The tank size is what the
     leaderstats actually persist, so this is how the server recovers "which rung am I
     on" without a second saved field. Sugar Rush resolves to the top rung. ]]
function StomachTiers.tierIndexForMax(maxPower: number): number
	local target = tonumber(maxPower) or 0
	if target >= StomachTiers.SUGAR_RUSH.maxPower then
		return StomachTiers.MAX_TIER
	end
	local best = 1
	for i, tier in ipairs(StomachTiers.CANDY_GUTS) do
		if target >= tier.maxPower then
			best = i
		end
	end
	return best
end

--[[ Has this player climbed far enough to be allowed to buy this tier? This IS the gate
     (plus the price): the server checks the same thing against HighestSlot in
     StomachUpgrade. Robux tiers are exempt on purpose. ]]
function StomachTiers.isUnlocked(tier, highestSlot: number?): boolean
	if not tier then
		return false
	end
	if tier.robux then
		return true
	end
	return (math.floor(tonumber(highestSlot) or 1)) >= (tier.unlockSlot or 1)
end

--[[ The highest ladder index whose island gate a player at `highestSlot` has passed. The
     shop panel draws its locks off this; the server re-derives it on every buy. ]]
function StomachTiers.unlockedTierFor(highestSlot: number?): number
	local reached = math.floor(tonumber(highestSlot) or 1)
	local best = 1
	for i, tier in ipairs(StomachTiers.CANDY_GUTS) do
		if reached >= (tier.unlockSlot or 1) then
			best = i
		end
	end
	return best
end

-- ============================================================================
-- BOOT AUDITS (server only -- no client spam)
-- ============================================================================
if game:GetService("RunService"):IsServer() then
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local okFT, FlightTuning = pcall(function() return require(Shared:WaitForChild("FlightTuning")) end)
	local okIO, IslandOrder  = pcall(function() return require(Shared:WaitForChild("IslandOrder")) end)

	-- TANKS MUST MATCH FlightTuning.BASE_TIERS ROW FOR ROW. FlightTuning maps a tank size to a
	-- climb by `max <= tier.maxPower`, so a StomachTiers row that FlightTuning does not know
	-- about silently flies on the next tier up's climb.
	if okFT and FlightTuning and FlightTuning.BASE_TIERS then
		if #FlightTuning.BASE_TIERS ~= StomachTiers.MAX_TIER then
			warn(("[Gut] %d coin tiers here but %d rows in FlightTuning.BASE_TIERS -- they must match")
				:format(StomachTiers.MAX_TIER, #FlightTuning.BASE_TIERS))
		end
		for i, tier in ipairs(StomachTiers.CANDY_GUTS) do
			local ft = FlightTuning.BASE_TIERS[i]
			if not ft or ft.maxPower ~= tier.maxPower then
				warn(("[Gut] TANK DRIFT tier %d: StomachTiers says %d, FlightTuning says %s")
					:format(i, tier.maxPower, ft and tostring(ft.maxPower) or "missing"))
			end
		end
	end

	-- PRICES: strictly increasing past the free start, and every gut cheaper than the crossing
	-- before its wall pays out (gap x COIN_PER_STUD), so saving for it is never a grind.
	for i = 2, StomachTiers.MAX_TIER do
		local tier, prev = StomachTiers.CANDY_GUTS[i], StomachTiers.CANDY_GUTS[i - 1]
		if tier.cost <= prev.cost and i > 2 then
			warn(("[Gut] %s (%d) is not dearer than %s (%d)"):format(tier.name, tier.cost, prev.name, prev.cost))
		end
		if tier.maxPower <= prev.maxPower then
			warn(("[Gut] %s tank (%d) is not bigger than %s (%d)"):format(tier.name, tier.maxPower, prev.name, prev.maxPower))
		end
		if okFT and okIO and FlightTuning and IslandOrder and IslandOrder.GAPS then
			-- the crossing before tier i's wall is c(2i-3): the previous gut's stretch
			local before = IslandOrder.GAPS[2 * i - 3]
			if before then
				local pays = before * FlightTuning.COIN_PER_STUD
				if tier.cost >= pays then
					warn(("[Gut] %s costs %d but the crossing before its wall pays only %.0f")
						:format(tier.name, tier.cost, pays))
				end
			end
		end
	end

	for i, tier in ipairs(StomachTiers.CANDY_GUTS) do
		local climb = (okFT and FlightTuning and FlightTuning.fullTankClimb(tier.maxPower)) or 0
		print(("[Gut] %-14s max=%-4d cost=%-5d unlock@slot %-2d climb=%.1f")
			:format(tier.name, tier.maxPower, tier.cost, tier.unlockSlot, climb))
	end
end

return StomachTiers
