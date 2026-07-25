--!nonstrict
-- PetWheelConfig (ReplicatedStorage/Shared/PetWheelConfig)
-- ============================================================================================================
-- SINGLE SOURCE OF TRUTH for the Robux "Pet Wheel" spin system. BOTH the server (PetWheel.server.lua, which
-- rolls) and the client (PetWheel.client.lua, which draws the wheel + the Odds panel) require THIS module.
-- Because the odds shown to players and the odds the server rolls on come from the SAME table, they can never
-- drift apart -- which is exactly what Roblox requires for a paid random-chance ("loot") item.
--
--   * Roblox POLICY: paid random items must publish TRUTHFUL odds. The server rolls on SEGMENTS[i].weight and
--     the Odds panel prints SEGMENTS[i].weight as the "%". Do NOT add any secret re-roll, pity, or visual
--     rigging -- the wheel must animate to the segment the server actually rolled.
-- ============================================================================================================

local Config = {}

-- Pet level cap. Mirrors PetSystem.PET_MAX_LEVEL (=25). Level rewards clamp to this server-side.
Config.PET_MAX_LEVEL = 25

-- ---- COIN REWARD AMOUNTS (tunable) -------------------------------------------------------------------------
-- The two "Coins" wedges are the consolation prizes. Tune these to taste for your economy; changing them here
-- changes what the server grants (the Odds panel only lists the % chance, not the amount, so no drift risk).
Config.COINS_SMALL = 750
Config.COINS_BIG   = 7500

-- ---- WHEEL SEGMENTS ----------------------------------------------------------------------------------------
-- weight = the REAL drop chance in percent. These MUST sum to 100 (asserted below). The Odds panel shows each
-- weight verbatim. kind drives what the server grants: "levels" (amount = pet levels), "coins" (amount = coins),
-- "mythical" (grants a random mythical pet -- see MYTHICAL_PETS). Order here = clockwise order on the wheel.
Config.SEGMENTS = {
	{ id = "lvl2",   label = "+2 Pet Levels",      weight = 45,   kind = "levels",   amount = 2,                     color = Color3.fromRGB(120, 200, 120) },
	{ id = "coinsS", label = "Coins (small)",      weight = 25,   kind = "coins",    amount = Config.COINS_SMALL,    color = Color3.fromRGB(245, 205,  70) },
	{ id = "lvl3",   label = "+3 Pet Levels",      weight = 18,   kind = "levels",   amount = 3,                     color = Color3.fromRGB( 90, 175, 235) },
	{ id = "coinsB", label = "Coins (big)",        weight = 7,    kind = "coins",    amount = Config.COINS_BIG,      color = Color3.fromRGB(240, 170,  60) },
	{ id = "lvl5",   label = "+5 Pet Levels",      weight = 4,    kind = "levels",   amount = 5,                     color = Color3.fromRGB(170, 120, 240) },
	{ id = "lvl7",   label = "+7 Pet Levels",      weight = 0.9,  kind = "levels",   amount = 7,                     color = Color3.fromRGB(255, 120, 180) },
	{ id = "mythic", label = "MYTHICAL PET",       weight = 0.1,  kind = "mythical",                                 color = Color3.fromRGB(255, 210,  80) },
}

-- One-line disclosure printed on the Odds panel so the honest-odds statement is visible to players + moderation.
Config.ODDS_NOTE = "These are the real drop chances."

-- ---- MYTHICAL JACKPOT --------------------------------------------------------------------------------------
-- The 0.1% jackpot grants a RANDOM pet species from this list as its rare/"Mythical" variant. Today the game's
-- only Mythical is the Cosmic Duck (the ButterDuck rare). To add more mythicals later, just append their species
-- id here -- the server picks uniformly at random from this list, so new entries are auto-included, no code change.
Config.MYTHICAL_PETS = { "ButterDuck" }

-- ---- ROBUX PURCHASE OPTIONS (Developer Products) -----------------------------------------------------------
-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- !!!  PLACEHOLDER DEVELOPER PRODUCT IDS -- REPLACE BEFORE LAUNCH.                                          !!!
-- !!!  Create three Developer Products in the Roblox Creator Dashboard (Store > Developer Products) at the  !!!
-- !!!  R$ prices below, then paste their real assetIds over these placeholders. Until you do, the buy       !!!
-- !!!  buttons will not complete a real purchase (use the /givespins dev command to test the wheel).        !!!
-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Config.SINGLE_SPIN_ROBUX = 15 -- baseline price of one spin, used to compute the pack savings shown to players
Config.PRODUCTS = {
	{ id = "spin1",  productId = 111111111, spins = 1,  robux = 15,               label = "1 Spin"   },
	{ id = "spin5",  productId = 222222222, spins = 5,  robux = 49, tag = "Popular",    label = "5 Spins"  },
	{ id = "spin10", productId = 333333333, spins = 10, robux = 89, tag = "Best Value", label = "10 Spins" },
}

-- ---- HELPERS -----------------------------------------------------------------------------------------------
-- Total of all weights (should be 100). Computed from the table so it can never disagree with SEGMENTS.
function Config.totalWeight()
	local t = 0
	for _, seg in ipairs(Config.SEGMENTS) do t = t + seg.weight end
	return t
end

-- Robux saved vs buying that many single spins (for the "Save X R$" label on the 5 / 10 packs).
function Config.savingsFor(product)
	return (product.spins * Config.SINGLE_SPIN_ROBUX) - product.robux
end

-- Find a product by its Roblox Developer Product id (used by the server's ProcessReceipt handler).
function Config.productByProductId(productId)
	for _, p in ipairs(Config.PRODUCTS) do
		if p.productId == productId then return p end
	end
	return nil
end

-- THE ROLL. Server-only in practice (client never calls this). `rng` is a Roblox Random object so the SERVER
-- owns the randomness. Returns (segment, index) where index is the position in SEGMENTS -- the client rotates
-- the wheel to that exact index, so the animation always lands on the segment the server truly rolled.
function Config.roll(rng)
	local total = Config.totalWeight()
	local pick = rng:NextNumber(0, total) -- uniform in [0, total)
	local cumulative = 0
	for i, seg in ipairs(Config.SEGMENTS) do
		cumulative = cumulative + seg.weight
		if pick < cumulative then
			return seg, i
		end
	end
	-- Floating-point safety net: if pick == total exactly, award the last segment.
	return Config.SEGMENTS[#Config.SEGMENTS], #Config.SEGMENTS
end

-- Sanity assert at require-time: weights MUST sum to 100 (Roblox honest-odds requirement). If someone edits a
-- weight and breaks the sum, this errors loudly on load instead of silently shipping wrong published odds.
do
	local total = Config.totalWeight()
	-- tolerate tiny float error from the 0.9 / 0.1 entries
	assert(math.abs(total - 100) < 1e-6, string.format("[PetWheelConfig] SEGMENT weights must sum to 100, got %s", tostring(total)))
end

return Config
