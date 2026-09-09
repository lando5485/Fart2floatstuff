--!strict
-- ==============================================================================================================
-- PET ABILITIES -- the single source of truth for what every pet DOES.
--
-- Pets were cosmetic-only until 2026-09-06. This table is the whole design: one row per species, naming the
-- LEVER it pushes on, how hard it pushes at level 1 and at level 25, and which trick it fires. Nothing else in
-- the game hard-codes a pet bonus -- PetAbilityService reads this, resolves it against who is equipped, and
-- publishes the result as player attributes. Adding a pet's ability is a row here and nothing else.
--
-- ===== THE ONE RULE THAT CANNOT BE BROKEN =====
-- NO ABILITY MAY TOUCH FLIGHT SPEED, CLIMB HEIGHT, GAS DRAIN, COAST, OR GAS-BUBBLE POWER.
-- The tower's spacing is asserted by tools/ladder.py as `climb[k] >= own gaps` and
-- `climb[k] + coast < next tier's gaps`. Anything that lifts the climb without lifting drain eats into that
-- second margin, which is only ~1.9% of a climb. CLAUDE.md already flags the 2x gamepass as a leak for exactly
-- this reason. With up to 5 equipped pets, duplicate stacking AND enchants all multiplying together, a single
-- speed lever here would not leak one crossing -- it would collapse the ladder. Every lever below is therefore
-- OUTSIDE the flight maths: coins, prices, reach, luck, tokens, XP, defence.
--
-- ===== STACKING (the Pet Simulator 99 rule) =====
-- Duplicates of the same species stack, but each further copy is worth less: 100% / 60% / 38% / 27.5% / 20%.
-- That curve is deliberately steep. It makes a BROAD collection strictly better than a deep one, which is what
-- keeps trading interesting -- five different pets beat five of the same, so people trade instead of hoarding.
-- ==============================================================================================================

local PetAbilities = {}

-- Matches PET_MAX_LEVEL in PetSystem. If that moves, this moves with it (the scale below is normalised on it).
PetAbilities.MAX_LEVEL = 25

-- The diminishing-returns curve for duplicate copies of the SAME species. Index = which copy this is.
-- Past the 5th copy every extra one is worth the tail value, so hoarding asymptotes instead of running away.
PetAbilities.STACK_FALLOFF = { 1.0, 0.60, 0.38, 0.275, 0.20 }
PetAbilities.STACK_TAIL    = 0.12

-- ===== THE LEVER NAMES =====
-- These strings are the contract with the rest of the game. A system that wants a pet bonus asks for one of
-- these by name and gets a number back; it never asks "is a Pizza Dragon equipped".
--   coinAll      x mult on EVERY coin grant (server, inside the CoinEvent chain)
--   coinFall     x mult on coins paid for a FAILED flight's descent (client, at the descent-pay maths)
--   bubbleValue  x mult on what one coin bubble pays
--   bubbleGolden chance 0..1 that a coin bubble pays TRIPLE
--   bubbleExtra  whole extra COIN bubbles per gap (never gas -- see the rule above)
--   crateLuck    x mult on rare-pull weight, folded into Gamepasses.luckFor
--   afkRate      x mult on the AFK token farm + offline earnings
--   petXp        x mult on XP awarded to the equipped pet
--   magnetReach  x mult on the coin-magnet radius
--   foodPrice    x mult on food price (BELOW 1 = cheaper)
--   birdBlock    chance 0..1 to block the bird attack's 20% power drain
--   walkSpeed    x mult on ground walk speed
PetAbilities.LEVERS = {
	coinAll = 1, coinFall = 1, bubbleValue = 1, bubbleGolden = 0, bubbleExtra = 0,
	crateLuck = 1, afkRate = 1, petXp = 1, magnetReach = 1, foodPrice = 1,
	birdBlock = 0, walkSpeed = 1,
}

-- Levers whose neutral value is 0 and which ADD rather than multiply. Everything else starts at 1 and
-- multiplies. Kept as a set so the resolver never has to special-case a lever by name.
PetAbilities.ADDITIVE = { bubbleGolden = true, bubbleExtra = true, birdBlock = true }

-- ==============================================================================================================
-- THE PETS.
--   lever  -- which entry in LEVERS this pushes on
--   lv1    -- the bonus at level 1   (as a delta: 0.08 = +8%, or an absolute for additive levers)
--   lv25   -- the bonus at level 25
--   trick  -- the id PetTricks fires on the button. nil = no trick yet.
-- Pets 1-6 are deliberately ABSENT: their abilities are still being designed, and a species with no row here
-- simply contributes nothing rather than erroring. That is the extension point.
-- ==============================================================================================================
PetAbilities.DEFS = {
	-- 7. PIZZA DRAGON -- the collection trophy (all 10 other pets). The broadest lever in the game, because
	-- it is the reward for finishing the set and should feel like it on every single coin you earn.
	PizzaDragon = {
		displayName = "Dragon's Hoard", lever = "coinAll", lv1 = 0.08, lv25 = 0.40, trick = "firebreath",
		blurb = "Coins from everything",
	},
	-- 8. SUNFLOWER BEE -- Summer garden. COIN bubbles only. Gas bubbles are capped at two per gap because
	-- CLAUDE.md's own margin maths shows a third would clear a wall the gut was never meant to clear.
	SunflowerBee = {
		displayName = "Pollen Sweep", lever = "bubbleExtra", lv1 = 1, lv25 = 2, trick = "bloomtrail",
		blurb = "Extra coin bubbles per gap", integer = true,
	},
	-- 9. MAPLE FOX -- Autumn garden. Rides the crate luck hook that rebirths and the pass already use, so it
	-- obeys the same audited odds path and creates no second lottery.
	MapleFox = {
		displayName = "Lucky Streak", lever = "crateLuck", lv1 = 0.04, lv25 = 0.20, trick = "leafstorm",
		blurb = "Rare-pull weight in crates",
	},
	-- 10. FROST PENGUIN -- Winter garden. Pays while you are NOT playing, which is the one bonus that makes
	-- somebody come back tomorrow to collect it.
	FrostPenguin = {
		displayName = "Cold Storage", lever = "afkRate", lv1 = 0.12, lv25 = 0.60, trick = "bellyslide",
		blurb = "AFK farm + offline earnings",
	},
	-- 11. BLOSSOM BUNNY -- Spring garden. Feeds the pet system itself: the pet that makes every OTHER pet
	-- level faster. Deliberately the one ability with no coin value at all.
	BlossomBunny = {
		displayName = "Bloom", lever = "petXp", lv1 = 0.08, lv25 = 0.40, trick = "petalburst",
		blurb = "XP gain for all your pets",
	},
	-- 12. MOLTEN BEAN -- rebirth 3. A CHANCE rather than a flat rate, so the payoff is a moment you notice
	-- (the bubble goes molten and pays triple) instead of a number you never see.
	MoltenBean = {
		displayName = "Molten Coin", lever = "bubbleGolden", lv1 = 0.08, lv25 = 0.40, trick = "meltdown",
		blurb = "Chance a coin bubble pays 3x",
	},
	-- 13. VOID DRAGON -- rebirth 6. Pays you for FAILING, which is the half of the loop nothing else rewards.
	-- A missed crossing already pays 3x the climb; this softens the worst run of the tower (the summit grind).
	VoidDragon = {
		displayName = "Void Tithe", lever = "coinFall", lv1 = 0.10, lv25 = 0.50, trick = "rift",
		blurb = "Failed flights pay more",
	},
	-- 14. PRISM FOX -- rebirth 10, the apex. Runs every OTHER passive you own at reduced strength. Costs no new
	-- lever of its own: it is a combiner over levers already proven safe, which is exactly why it can be this
	-- strong without being a balance risk.
	PrismFox = {
		displayName = "Prism Split", lever = "_prism", lv1 = 0.08, lv25 = 0.40, trick = "refract",
		blurb = "Every other passive you own, at reduced strength",
	},
}

-- ==============================================================================================================
-- SCALING. Linear from lv1 at level 1 to lv25 at MAX_LEVEL. Linear on purpose: a player has to be able to look
-- at the number on the pet card, look at their level, and see why. An exponential curve reads as a lie at the
-- bottom and a cliff at the top.
-- ==============================================================================================================
function PetAbilities.valueAt(petId: string, level: number?): number
	local def = PetAbilities.DEFS[petId]
	if not def then return 0 end
	local lv = math.clamp(tonumber(level) or 1, 1, PetAbilities.MAX_LEVEL)
	local t  = (PetAbilities.MAX_LEVEL > 1) and ((lv - 1) / (PetAbilities.MAX_LEVEL - 1)) or 1
	local v  = def.lv1 + (def.lv25 - def.lv1) * t
	if def.integer then return math.floor(v + 1e-6) end
	return v
end

-- What one COPY is worth once the duplicate curve is applied. `copyIndex` is 1 for the first copy owned.
function PetAbilities.falloff(copyIndex: number): number
	local i = math.max(1, math.floor(copyIndex))
	return PetAbilities.STACK_FALLOFF[i] or PetAbilities.STACK_TAIL
end

-- Neutral starting value for a lever, so callers never have to remember which ones are additive.
function PetAbilities.neutral(lever: string): number
	return PetAbilities.ADDITIVE[lever] and 0 or 1
end

-- Fold one pet's contribution into a running total for its lever. Multiplicative levers accumulate as
-- (1 + sum of deltas) rather than a product of (1 + delta): a product compounds, and compounding is how a
-- "+8% each" ability quietly turns into +60% once five of them are equipped.
function PetAbilities.accumulate(running: number, lever: string, delta: number): number
	return running + delta
end

-- Turn an accumulated delta into the number a system actually multiplies by.
function PetAbilities.finalise(lever: string, accumulated: number): number
	if PetAbilities.ADDITIVE[lever] then
		if lever == "bubbleExtra" then return math.floor(accumulated + 1e-6) end
		return math.clamp(accumulated, 0, 1)     -- chances never exceed certainty
	end
	if lever == "foodPrice" then return math.clamp(1 - accumulated, 0.5, 1) end -- a discount, floored at half price
	return 1 + math.max(0, accumulated)
end

-- The attribute name a lever is published under, so server and client agree without a remote.
function PetAbilities.attrName(lever: string): string
	return "PetAbil_" .. lever
end

return PetAbilities
