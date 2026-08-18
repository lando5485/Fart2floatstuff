--======================================================================
-- StomachTiers.luau  (ModuleScript -> ReplicatedStorage.Shared)  -- CandyRealm
--======================================================================
-- THE GUT TIERS, in one place, because the SHOP UI (StomachShop_AllInOne.client)
-- and the PURCHASE HANDLER (StomachUpgrade.server) both need them -- two copies is
-- how the dino realm's panel showed 1600 while its server charged 112 and every
-- gut silently became unbuyable.
--
-- ONE GUT PER CROSSING -- 10 coin tiers for the 10 crossings of this eleven-island
-- tower, plus a Robux one. A gut is the wall that forces saving; with fewer guts than
-- crossings some islands are free by construction (the dino playtest with 6 guts over
-- 12 crossings ran 3, 1, 3, 1, 6, 1 attempts -- alternating perfectly).
--
-- TEN, NOT TWELVE: islands 6, 7, 10 and 12 are not built, so the tower is
-- 1,2,3,4,5,8,9,11,13,14,15 -- eleven islands, ten crossings. When those get built,
-- add tiers 11 and 12 back (2360/3450 and 3230/3850) and re-solve.
--
-- PRICES ARE 4.25 FLIGHTS OF SURPLUS AT THE TIER BELOW -- the sole "3-5 tries per
-- island" dial. Surplus = what one flight nets after buying its fuel; a gut costing
-- 4.25x that takes ~4 flights to save for, and at 45 s per flight each island lands
-- at ~3.0 minutes. Prices span only ~2.5x (1250 -> 3050) because a flight's surplus
-- only roughly doubles up the tower.
--
-- unlockSlot IS THE ANTI-SKIP RULE: tier k opens the crossing from slot k to k+1, so
-- it is bought while STANDING on slot k. Without the check a player could farm
-- island 1 and buy the Licorice Loop outright, skipping every wall. The server
-- enforces it; the shop panel just draws the lock. Sugar Rush is Robux and
-- deliberately NOT slot-gated -- it is a purchase, not a progression step.
--
-- maxPower MUST MATCH FlightTuning.TIERS ROW FOR ROW -- the band widths ARE these
-- numbers. Nothing keys off the name except display.
--======================================================================

local StomachTiers = {}

StomachTiers.LIST = {
	{ name = "Gumdrop Belly",      maxPower = 110,  cost = 0,    robux = false, unlockSlot = 1,  emoji = "\u{1F36C}" }, -- crossing 1 -> 2
	{ name = "Taffy Tummy",        maxPower = 150,  cost = 1250, robux = false, unlockSlot = 2,  emoji = "\u{1F36D}" }, -- crossing 2 -> 3
	{ name = "Cookie Gut",         maxPower = 200,  cost = 1400, robux = false, unlockSlot = 3,  emoji = "\u{1F36A}" }, -- crossing 3 -> 4
	{ name = "Jelly Belly",        maxPower = 270,  cost = 1550, robux = false, unlockSlot = 4,  emoji = "\u{1F36E}" }, -- crossing 4 -> 5
	{ name = "Gummy Gut",          maxPower = 365,  cost = 1750, robux = false, unlockSlot = 5,  emoji = "\u{1F43B}" }, -- crossing 5 -> 6
	{ name = "Choco Stomach",      maxPower = 495,  cost = 1950, robux = false, unlockSlot = 6,  emoji = "\u{1F36B}" }, -- crossing 6 -> 7
	{ name = "Caramel Core",       maxPower = 675,  cost = 2200, robux = false, unlockSlot = 7,  emoji = "\u{1F36F}" }, -- crossing 7 -> 8
	{ name = "Marshmallow Middle", maxPower = 920,  cost = 2450, robux = false, unlockSlot = 8,  emoji = "\u{2601}\u{FE0F}" }, -- crossing 8 -> 9
	{ name = "Fudge Furnace",      maxPower = 1260, cost = 2750, robux = false, unlockSlot = 9,  emoji = "\u{1F525}" }, -- crossing 9 -> 10
	{ name = "Licorice Loop",      maxPower = 1725, cost = 3050, robux = false, unlockSlot = 10, emoji = "\u{1F300}" }, -- crossing 10 -> 11 (top coin gut)
	{ name = "Sugar Rush Gut",     maxPower = 9999, cost = 499,  robux = true,  unlockSlot = 1,  emoji = "\u{26A1}" },
}

-- Look a tier up by the tank size the client asked for -- the server reads the PRICE
-- off its own table, so a client-sent cost cannot change what it pays.
function StomachTiers.byMaxPower(maxPower: number)
	local target = tonumber(maxPower)
	if not target then return nil end
	for _, tier in ipairs(StomachTiers.LIST) do
		if tier.maxPower == target then return tier end
	end
	return nil
end

-- name -> tier, for the name-keyed BuyStomachEvent protocol the CandyRealm shop uses.
StomachTiers.BY_NAME = {}
for _, tier in ipairs(StomachTiers.LIST) do
	StomachTiers.BY_NAME[tier.name] = tier
end

-- Has this player reached far enough up the tower to buy this gut? Gating on REACH
-- (not on owning the previous tier) means the ladder cannot be skipped but can still
-- be back-filled. Robux tiers are exempt on purpose.
function StomachTiers.isUnlocked(tier, highestSlot: number?): boolean
	if not tier then return false end
	if tier.robux then return true end
	return (math.floor(tonumber(highestSlot) or 1)) >= (tier.unlockSlot or 1)
end

-- maxPower -> display name, for anything that only has the number (HUD, save data).
StomachTiers.NAME_BY_MAX = {}
for _, tier in ipairs(StomachTiers.LIST) do
	StomachTiers.NAME_BY_MAX[tier.maxPower] = tier.name
end

return StomachTiers
