--!nonstrict
-- TraitShop (ReplicatedStorage/Shared/TraitShop)
-- ============================================================================================================
-- SINGLE SOURCE OF TRUTH for buying a TRAIT OUTRIGHT with Crate Tickets, at the Pet Hut's Customize counter.
--
-- ===== WHAT THIS IS, AND WHY IT IS NOT THE TRAIT CRATE =====
-- A trait has always arrived ATTACHED to an inventory entry: crates grant "pet|skin|trait" as one item, and
-- PetTraits.roll() decides which trait that is. That is a LOTTERY -- 200 tickets for a random one.
--
-- This is the SHOP: you pick the trait you want, you pay a fixed price, you own it forever, and you can put it
-- on ANY pet you own. The two coexist on purpose and they are priced so neither kills the other:
--
--   * The Trait Crate stays the cheap gamble. 200 tickets, any trait, 1.5% Legendary.
--   * The shop is the GUARANTEED route, and it costs multiples of a pull. Chasing one SPECIFIC Common through
--     the crate averages ~1,800 tickets; the shop sells it for 250. Targeting should beat chasing -- that is
--     what makes the shop worth having -- while a single 200-ticket pull stays the cheapest way to see a
--     trait at all.
--
-- ===== A PURCHASED TRAIT IS A WARDROBE ITEM, NOT AN INVENTORY ENTRY =====
-- Crate-pulled traits live inside a skin entry's key. Purchased traits live in a SEPARATE per-player set --
-- _G.playerOwnedTraits, persisted as saved.ownedTraits -- and equipping one writes only the `trait` half of
-- the equipped pair, leaving whatever skin is on the pet alone. That is the whole reason this is additive:
-- nothing about the crate economy, the inventory keys, the Collection Book or trading changes shape.
--
-- Pulling a trait from a crate ALSO stocks the wardrobe (SkinCrateService does that on grant), so a trait you
-- won is a trait you can wear on every pet -- not just on the one body it happened to land on.
--
-- BOTH sides require this module: the server charges `priceOf`, the client prints `priceOf`. One table, so the
-- price on the button can never differ from the price that is actually taken -- the same honest-numbers
-- contract SkinCrates.luau follows for the odds.
-- ============================================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetTraits = require(Shared:WaitForChild("PetTraits"))

local TraitShop = {}

-- ---- THE PRICES ---------------------------------------------------------------------------------------------
-- By TIER, never per trait: a trait's tier already decides its rarity everywhere else in the game (the crate
-- band it sits in, its hidden score in PetTier), so pricing per id would be a second, driftable opinion about
-- how rare a King is. Add a trait to PetTraits and it is priced automatically.
--
-- The ladder is steep on purpose -- roughly 2.4x a rung -- so the Legendary band reads as a genuine goal
-- rather than an afternoon's saving. Every price is a round number of tickets. Wizard and King sit in that
-- band (they were Epic until 2026-09-02), so the two most-wanted traits are also the two most expensive --
-- which is the point, and it took no edit here: price follows tier.
TraitShop.PRICES = {
	Common    =   250,
	Uncommon  =   600,
	Rare      =  1400,
	Epic      =  3000,
	Legendary =  7500,
}

-- Display order for the shop grid: cheapest first, so the wall a new player sees opens with something they can
-- actually afford. Mirrors PetTraits.TIER_ORDER; asserted below to stay in step with it.
TraitShop.TIER_ORDER = PetTraits.TIER_ORDER

TraitShop.PRICE_NOTE = "Tickets are cosmetic-only -- traits never affect flight, coins or progression."

-- ---- LOOKUPS ------------------------------------------------------------------------------------------------
-- The ticket price of a trait, or nil if it is not a purchasable trait. "" (no trait) is not purchasable: it is
-- the CLEAR action, and clearing is free.
function TraitShop.priceOf(traitId)
	local tier = PetTraits.tierOf(traitId)
	if not tier then return nil end
	return TraitShop.PRICES[tier]
end

-- Is this a real, buyable trait id? Rejects nil, "", garbage, and anything not in PetTraits.TRAITS. Legacy ids
-- are NOT accepted -- the shop sells current traits, and normalising a legacy id here would let a stale client
-- buy "Crowned" and be charged for King without being told.
function TraitShop.isBuyable(traitId)
	if type(traitId) ~= "string" or traitId == "" then return false end
	if PetTraits.ById[traitId] == nil then return false end
	return TraitShop.priceOf(traitId) ~= nil
end

-- Every trait the shop stocks, grouped by tier in TIER_ORDER, each row carrying what a shop card needs to draw
-- itself: id, name, tier, price and the trait's UI accent colour. The client builds its grid straight from
-- this, so a new trait appears in the shop with no client edit.
function TraitShop.catalogue()
	local out = {}
	for _, tier in ipairs(TraitShop.TIER_ORDER) do
		for _, t in ipairs(PetTraits.ByTier[tier] or {}) do
			out[#out + 1] = {
				id = t.id, displayName = t.displayName, tier = tier,
				price = TraitShop.PRICES[tier], color = t.color,
			}
		end
	end
	return out
end

-- What it would cost to own every trait in the game. Printed on the shop's footer as the long-term goal, and
-- used by the tests to notice a price change that quietly doubles the total.
function TraitShop.totalCatalogueCost()
	local sum = 0
	for _, row in ipairs(TraitShop.catalogue()) do sum = sum + row.price end
	return sum
end

-- ---- REQUIRE-TIME VALIDATION --------------------------------------------------------------------------------
-- Fails loudly on load rather than shipping a shop with an unpriced (and therefore unbuyable, or worse FREE)
-- trait in it.
do
	for _, tier in ipairs(PetTraits.TIER_ORDER) do
		local p = TraitShop.PRICES[tier]
		assert(type(p) == "number" and p > 0 and p % 1 == 0,
			string.format("[TraitShop] tier '%s' needs a positive whole ticket price, got %s", tier, tostring(p)))
	end
	-- Every trait that exists must be priced. A trait added to PetTraits with a new tier name would otherwise
	-- show up in the shop costing nil.
	for _, t in ipairs(PetTraits.TRAITS) do
		assert(TraitShop.priceOf(t.id) ~= nil,
			string.format("[TraitShop] trait '%s' (tier %s) has no price", t.id, tostring(t.tier)))
	end
	-- The ladder must never go DOWN: a rarer trait costing less than a commoner one would make the tier badge
	-- on the card a lie.
	local prev = 0
	for _, tier in ipairs(TraitShop.TIER_ORDER) do
		local p = TraitShop.PRICES[tier]
		assert(p > prev, string.format("[TraitShop] prices must rise with tier -- %s (%d) is not above the tier below (%d)",
			tier, p, prev))
		prev = p
	end
end

return TraitShop
