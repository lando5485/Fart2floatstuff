--!nonstrict
-- Constants (ReplicatedStorage/Shared/Constants)
-- Shared tuning values for the Mystery Meteor Crate system plus the economy's starting state.
-- Required by both the server authority (CrateService / PlayerState / FlightEconomy /
-- StomachUpgrade) and the client (CrateClient / HudSidebarStats). Server is the ONLY
-- authority for eligibility/roll/grant; these numbers must match on both sides.

local Constants = {}

-- ===== MYSTERY METEOR CRATE =====
-- REWARD: pet levels (not cosmetics). Rarity decides how many levels are added to the player's
-- chosen owned pet, hard-capped at PET_MAX_LEVEL. If every owned pet is maxed -> FALLBACK_COINS.
Constants.CRATE = {
	-- 8 hours between free claims (8 * 60 * 60).
	COOLDOWN_SECONDS = 28800,
	-- Coins granted when every owned pet is already at the level cap (nothing left to level).
	FALLBACK_COINS = 500,
	-- Pet level cap (mirrors PetSystem.PET_MAX_LEVEL; grants clamp here).
	PET_MAX_LEVEL = 25,
	-- Rarity roll weights. Sum = 100, but consumers compute the total defensively so any
	-- future re-weighting still works without touching the roll code.
	RARITY_WEIGHTS = {
		Uncommon = 55,
		Rare = 28,
		Epic = 13,
		Mythical = 4,
	},
	-- Deterministic rarity order (used when iterating weights for a stable cumulative roll).
	RARITY_ORDER = { "Uncommon", "Rare", "Epic", "Mythical" },
	-- Levels granted per rarity (clamped to PET_MAX_LEVEL on apply).
	RARITY_LEVELS = {
		Uncommon = 1,
		Rare = 2,
		Epic = 4,
		Mythical = 6,
	},
	-- Reveal-card header / accent color per rarity.
	RARITY_COLORS = {
		Uncommon  = Color3.fromRGB(150, 160, 172),
		Rare      = Color3.fromRGB(70, 140, 255),
		Epic      = Color3.fromRGB(175, 90, 240),
		Mythical  = Color3.fromRGB(255, 200, 60),
	},
}

-- ===== ECONOMY: STARTING STATE (food-realm port) =====
-- FlightEconomy.ensureStats and StomachUpgrade.ensureStats both read these, so the two
-- cannot drift apart. They are the food realm's DEFAULT_COINS / DEFAULT_STOMACH / DEFAULT_ISLAND.
--
-- Tier 1 is the Gumdrop Belly (120), the food realm's Tiny Gut: a new player CAN fly from the
-- first second. The 630-stud tutorial crossing is 1.355x inside a full tank's reach, and the
-- gut above it is the first thing flight coins buy. (The space port started at maxPower 0 as a
-- "grounded gate" so quests had to fund the first gut; that gate is gone with the two-purse model.)
Constants.STARTING_STOMACH_TIER = 1 -- index into StomachTiers.CANDY_GUTS

-- 2,000 against a 1,280 first meal is a 3-rung tutorial ladder off the bank.
Constants.STARTING_COINS = 2000

-- Empty tank. You buy your first food with the starting coins.
Constants.STARTING_POWER = 0

-- Slot 1. (leaderstats.Island is the CLIMB SLOT in this realm, not the model number.)
Constants.STARTING_ISLAND = 1

if game:GetService("RunService"):IsServer() then
	print(("[Constants] start: tier=%d coins=%d power=%d island=%d (food-realm defaults)")
		:format(Constants.STARTING_STOMACH_TIER, Constants.STARTING_COINS, Constants.STARTING_POWER,
			Constants.STARTING_ISLAND))
end

return Constants
