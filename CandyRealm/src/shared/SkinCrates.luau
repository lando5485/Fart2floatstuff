--!nonstrict
-- SkinCrates (ReplicatedStorage/Shared/SkinCrates)
-- ============================================================================================================
-- SINGLE SOURCE OF TRUTH for the CS:GO-style pet-skin crates: what's inside each crate, what it costs, the
-- rarity odds, and the Robux token packs.
--
-- BOTH sides require this module. The SERVER calls roll() to decide the reward; the CLIENT reads the same
-- CONTENTS to build the scrolling reel and the same RARITY_ODDS to print the odds panel. Because the numbers
-- the player is shown and the numbers the server rolls on come from ONE table, they can never disagree --
-- the honest-odds contract this file is the single source of truth for.
--
--   * Roblox POLICY: a paid random-chance item must publish TRUTHFUL odds. Do NOT add a secret re-roll, a pity
--     timer, or any visual rigging. The reel must land on the reward the server actually rolled.
--
-- HOW THE ROLL WORKS (exactly as specified):
--   1. Roll the RARITY from RARITY_ODDS (Common 79.92% ... Gold 0.08%).
--   2. Pick UNIFORMLY at random from that rarity's entries in the crate.
--   3. Roll the TRAIT separately -- see PetTraits.roll(). Independent of rarity.
--
-- A rarity band with NO entries in a crate is skipped and its weight redistributed to the bands that do have
-- entries (see roll()), so a half-filled crate is still openable while you're building it out.
-- ============================================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetSkins = require(Shared:WaitForChild("PetSkins"))

local SkinCrates = {}

-- ---- RARITY ODDS --------------------------------------------------------------------------------------------
-- The REAL drop chances, in percent. These MUST sum to 100 (asserted at the bottom of this file).
-- This is the BASELINE, used by the Starter crate and by any crate that doesn't set its own `odds`. The higher
-- tiers DO override it (that's what makes them worth more tokens) -- but an override is asserted to sum to 100
-- too, and the odds panel always prints the same table the roll reads, so no crate can be quietly stingier
-- than what it advertises.
SkinCrates.RARITY_ODDS = {
	Common    = 79.92,
	Uncommon  = 16.00,
	Rare      =  3.20,
	Epic      =  0.64,
	Legendary =  0.16,
	Gold      =  0.08,
}
-- Roll order, lowest to highest. Also the display order in the odds panel.
SkinCrates.RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Gold" }

SkinCrates.ODDS_NOTE = "These are the real drop chances."

-- A crate MAY override RARITY_ODDS with its own `odds` table -- that's how the Premium/Elite/Mythic tiers below
-- get "better odds" than Starter. Everything downstream (roll, liveRarities, effectiveOdds, and the percentages
-- the UI prints) reads through this ONE accessor, so a crate's published odds and its rolled odds are guaranteed
-- to be the same table. A crate with no `odds` field uses the shared default.
function SkinCrates.oddsFor(crate)
	return (crate and crate.odds) or SkinCrates.RARITY_ODDS
end

-- The GOLD tier is the "knife pull" -- it gets its own sound, its own reel flash, and a server-wide announcement.
-- Everything below it reveals normally.
SkinCrates.GOLD_TIER = "Gold"

-- ---- THE CRATES ---------------------------------------------------------------------------------------------
-- Each entry is { pet = <petId>, skin = <skinId> }. petId must exist in PetSystem's PETS catalogue; skinId must
-- exist in PetSkins.Skins. Both are validated at require-time by the assert block at the bottom, so a typo fails
-- loudly on load instead of producing an unobtainable reward.
--
-- IMPORTANT: a player can receive a skin for a pet they have NOT unlocked. That is deliberate -- it stops anyone
-- deliberately staying locked to farm better odds. The skin sits in the inventory reading
-- "Unlock <Pet> to equip", and becomes wearable the moment they unlock that pet. See SkinCrateService.
-- The species the Pet Crate stocks. ONE shared list referenced by all six bands rather than six copies, so a
-- pet can never be accidentally obtainable at Rare but not at Epic. See the Pet Crate below for what is
-- deliberately left out and why.
local PET_CRATE_SPECIES = {
	{ pet = "BeanBuddy"        }, { pet = "BroccoliPet"  }, { pet = "CoconutCrab"      },
	{ pet = "PopcornSheep"     }, { pet = "ButterDuck"   }, { pet = "BurritoArmadillo" },
	{ pet = "SunflowerBee"     }, { pet = "MapleFox"     }, { pet = "FrostPenguin"     },
	{ pet = "BlossomBunny"     },
}

SkinCrates.CRATES = {
	-- ===== THE PET CRATE -- the ONLY source of pets above Common ==============================================
	-- kind = "pets": entries are { pet = <petId> }, no skin and no levels. The band the roll lands on IS the
	-- rarity of the pet you get, which is why every band stocks the same ten species -- you are not rolling
	-- WHICH pet is rare, you are rolling HOW rare YOUR pet is. Every species can be had at every band.
	--
	-- Rarity is a PERMANENT axis (see PetRarity): a pet's rarity never changes, while its AGE (Baby..Elder)
	-- grows with flight time and playtime. The crate sells rarity; it never sells a head start on growth.
	--
	-- DUPLICATES ARE THE POINT, not a consolation: pulling a species you already own at a band you already own
	-- stacks it, and those duplicates are what fusion consumes to climb the ladder.
	--
	-- NOT STOCKED, on purpose: PizzaDragon is the secret collection reward and selling it in a crate would
	-- erase the only thing completing the collection is for.
	{
		id = "Pets", displayName = "Pet Crate",
		blurb = "A pet at a rolled rarity. Duplicates stack -- fuse them to climb the ladder.",
		price = 160, color = Color3.fromRGB(255, 150, 60), icon = "\xF0\x9F\xA5\x9A", -- egg
		kind = "pets", -- entries are { pet = petId }, NOT { pet, skin }
		odds = { Common = 60.00, Uncommon = 25.00, Rare = 10.00, Epic = 4.00, Legendary = 0.90, Gold = 0.10 },
		contents = {
			Common    = PET_CRATE_SPECIES,
			Uncommon  = PET_CRATE_SPECIES,
			Rare      = PET_CRATE_SPECIES,
			Epic      = PET_CRATE_SPECIES,
			Legendary = PET_CRATE_SPECIES,
			Gold      = PET_CRATE_SPECIES,
		},
	},

	-- THE PET LEVEL CRATE. Replaces the Robux Pet Wheel, which is gone: this is where pet levels come from
	-- now. It runs on the EXACT same machinery as the skin crates -- roll a rarity band, pick uniformly
	-- inside it, animate the reel to the index the server actually rolled -- so the honest-odds contract and
	-- every anti-rigging guarantee carry over unchanged. The only difference is what an entry HOLDS:
	-- `levels = N` instead of `pet`/`skin`. kind = "levels" is what tells the roll, the validator, the
	-- server grant and the reel which shape to expect.
	--
	-- ODDS + AMOUNTS are carried over from the old wheel so the value of a level did not silently change:
	-- the wheel paid an average of 1.70 levels per spin, this pays 1.78 per open.
	--   0.52*1 + 0.30*2 + 0.13*3 + 0.04*5 + 0.009*7 + 0.001*10 = 1.783
	--
	-- PRICE is the one number to tune. At the token pack rate (0.4 R$/token) 150 tokens is about R$60, where
	-- a wheel spin was R$15. It is deliberately dearer than the wheel and deliberately CHEAPER than the
	-- Starter crate, so it reads as the entry-level utility crate rather than a cosmetic pull. For exact
	-- parity with the old wheel price, set this to 40.
	{
		id = "PetLevels", displayName = "Pet Level Crate",
		blurb = "Nothing but pet levels. Every single pull levels up a pet.",
		price = 75, color = Color3.fromRGB(120, 200, 120), icon = "\xE2\xAD\x90", -- star
		kind = "levels", -- entries are { levels = N }, NOT { pet, skin }
		odds = { Common = 52.00, Uncommon = 30.00, Rare = 13.00, Epic = 4.00, Legendary = 0.90, Gold = 0.10 },
		contents = {
			Common    = { { levels = 1  } },
			Uncommon  = { { levels = 2  } },
			Rare      = { { levels = 3  } },
			Epic      = { { levels = 5  } },
			Legendary = { { levels = 7  } },
			Gold      = { { levels = 10 } },
		},
	},
	{
		id = "Starter", displayName = "Starter Crate",
		blurb = "Cheap and cheerful. Mostly Common, but every tier is in here.",
		price = 100, color = Color3.fromRGB(64, 120, 245), icon = "\xF0\x9F\x93\xA6", -- box
		-- no `odds` field -> the shared baseline. This is the crate players learn the odds from.
		contents = {
			Common = {
				{ pet = "BeanBuddy", skin = "Stone" }, { pet = "BlossomBunny", skin = "Sand" },
				{ pet = "BroccoliPet", skin = "Moss" }, { pet = "ButterDuck", skin = "Mud" },
				{ pet = "SunflowerBee", skin = "Chocolate" }, { pet = "MapleFox", skin = "Honey" },
			},
			Uncommon = {
				{ pet = "FrostPenguin", skin = "Ice" }, { pet = "BeanBuddy", skin = "Emerald" },
				{ pet = "ButterDuck", skin = "Coral" }, { pet = "BroccoliPet", skin = "Gilded" },
				{ pet = "BlossomBunny", skin = "Crystal" },
			},
			Rare = {
				{ pet = "MapleFox", skin = "Neon" }, { pet = "SunflowerBee", skin = "Toxic" },
				{ pet = "BurritoArmadillo", skin = "Magma" }, { pet = "PizzaDragon", skin = "Gilded" },
			},
			Epic = {
				{ pet = "PizzaDragon", skin = "Galaxy" }, { pet = "ButterDuck", skin = "Rainbow" },
				{ pet = "MapleFox", skin = "Cyber" },
			},
			Legendary = { { pet = "PizzaDragon", skin = "Shadow" }, { pet = "PopcornSheep", skin = "Celestial" } },
			Gold      = { { pet = "PizzaDragon", skin = "Cosmic" } },
		},
	},

	{
		id = "Premium", displayName = "Premium Crate",
		blurb = "Better odds across the board. Half the Commons of a Starter.",
		price = 250, color = Color3.fromRGB(72, 200, 120), icon = "\xF0\x9F\x8E\x81", -- gift
		-- BETTER ODDS: Common roughly halved, everything above it lifted. Still sums to 100 (asserted below).
		odds = { Common = 58.00, Uncommon = 30.00, Rare = 9.00, Epic = 2.20, Legendary = 0.60, Gold = 0.20 },
		contents = {
			Common = {
				{ pet = "CoconutCrab", skin = "Stone" }, { pet = "PopcornSheep", skin = "Sand" },
				{ pet = "BurritoArmadillo", skin = "Mud" }, { pet = "FrostPenguin", skin = "Chocolate" },
			},
			Uncommon = {
				{ pet = "CoconutCrab", skin = "Coral" }, { pet = "PopcornSheep", skin = "Ice" },
				{ pet = "MapleFox", skin = "Crystal" }, { pet = "SunflowerBee", skin = "Gilded" },
				{ pet = "BurritoArmadillo", skin = "Emerald" },
			},
			Rare = {
				{ pet = "FrostPenguin", skin = "Neon" }, { pet = "ButterDuck", skin = "Toxic" },
				{ pet = "BroccoliPet", skin = "Magma" }, { pet = "BeanBuddy", skin = "Neon" },
			},
			Epic = {
				{ pet = "BurritoArmadillo", skin = "Galaxy" }, { pet = "BeanBuddy", skin = "Cyber" },
				{ pet = "PopcornSheep", skin = "Rainbow" },
			},
			Legendary = { { pet = "CoconutCrab", skin = "Shadow" }, { pet = "BlossomBunny", skin = "Celestial" } },
			Gold      = { { pet = "CoconutCrab", skin = "Cosmic" } },
		},
	},

	{
		id = "Elite", displayName = "Elite Crate",
		blurb = "Expensive. Rare or better more often than not.",
		price = 600, color = Color3.fromRGB(248, 150, 56), icon = "\xF0\x9F\x92\x8E", -- gem
		-- HIGH CHANCE OF RARE+: Rare/Epic/Legendary/Gold together are 55% of this crate.
		odds = { Common = 20.00, Uncommon = 25.00, Rare = 34.00, Epic = 15.00, Legendary = 5.00, Gold = 1.00 },
		contents = {
			Common   = { { pet = "PizzaDragon", skin = "Stone" }, { pet = "CoconutCrab", skin = "Moss" } },
			Uncommon = {
				{ pet = "PizzaDragon", skin = "Crystal" }, { pet = "FrostPenguin", skin = "Emerald" },
				{ pet = "BurritoArmadillo", skin = "Gilded" },
			},
			Rare = {
				{ pet = "PizzaDragon", skin = "Neon" }, { pet = "CoconutCrab", skin = "Toxic" },
				{ pet = "PopcornSheep", skin = "Magma" }, { pet = "BlossomBunny", skin = "Neon" },
			},
			Epic = {
				{ pet = "CoconutCrab", skin = "Galaxy" }, { pet = "FrostPenguin", skin = "Cyber" },
				{ pet = "SunflowerBee", skin = "Rainbow" }, { pet = "MapleFox", skin = "Galaxy" },
			},
			Legendary = {
				{ pet = "ButterDuck", skin = "Shadow" }, { pet = "MapleFox", skin = "Celestial" },
				{ pet = "BeanBuddy", skin = "Shadow" },
			},
			Gold = { { pet = "ButterDuck", skin = "Cosmic" }, { pet = "MapleFox", skin = "Cosmic" } },
		},
	},

	{
		id = "Mythic", displayName = "Mythic Crate",
		blurb = "Limited collection. Events, Season Pass and Robux bundles only.",
		price = 1200, color = Color3.fromRGB(240, 96, 180), icon = "\xE2\x9C\xA8", -- sparkles
		-- The event crate: no Commons at all, and the best Gold rate in the game.
		odds = { Common = 0.00, Uncommon = 18.00, Rare = 40.00, Epic = 28.00, Legendary = 11.00, Gold = 3.00 },
		limited = true, -- flagged for the UI: not bought with tokens in the normal shop
		contents = {
			Uncommon = { { pet = "PizzaDragon", skin = "Ice" }, { pet = "BeanBuddy", skin = "Crystal" } },
			Rare = {
				{ pet = "PizzaDragon", skin = "Toxic" }, { pet = "BlossomBunny", skin = "Magma" },
				{ pet = "SunflowerBee", skin = "Neon" },
			},
			Epic = {
				{ pet = "PizzaDragon", skin = "Cyber" }, { pet = "BlossomBunny", skin = "Galaxy" },
				{ pet = "FrostPenguin", skin = "Rainbow" }, { pet = "CoconutCrab", skin = "Cyber" },
			},
			Legendary = {
				{ pet = "SunflowerBee", skin = "Shadow" }, { pet = "BurritoArmadillo", skin = "Celestial" },
				{ pet = "FrostPenguin", skin = "Shadow" },
			},
			Gold = {
				{ pet = "BlossomBunny", skin = "Cosmic" }, { pet = "SunflowerBee", skin = "Cosmic" },
				{ pet = "BroccoliPet", skin = "Cosmic" },
			},
		},
	},

}

-- ---- ROBUX TOKEN PACKS (Developer Products) -----------------------------------------------------------------
-- These are LIVE Developer Product ids and TEST_MODE below is off: the buy button opens a real Roblox
-- purchase and tokens are credited only by ProcessReceipt. Use /givetokens to test without spending.
-- The rate the SMALLEST pack sells at, and the baseline every "Save X%" tag is measured against. It is the
-- entry pack's own rate on purpose: the discount a player is shown is then the real answer to "what do I gain
-- by buying bigger", not a saving against a single-token price nobody can actually buy.
SkinCrates.SINGLE_TOKEN_ROBUX = 0.25

-- ---- THE LADDER ----
-- Buying power climbs the whole way up, and the top pack is worth exactly DOUBLE the entry pack per Robux:
--
--   Handful    100 tok /  25 R$  = 0.250  base
--   Pocket     300 tok /  59 R$  = 0.197  +27%
--   Standard   700 tok / 129 R$  = 0.184  +36%
--   Big      1,500 tok / 239 R$  = 0.159  +57%
--   Huge     4,400 tok / 549 R$  = 0.125  +100%
--
-- The extra value is paid in TOKENS, not by cutting the price. "549 gets me three Mythics" is a thing a
-- player can picture; "549 is 8% off" is not. The prices are round, familiar numbers and they stay put.
--
-- Every pack divides EVENLY into crates at the prices above -- nothing is stranded. The usual trick is to
-- mismatch them so there is always an unusable remainder nagging at the next purchase, and it is skipped on
-- purpose: leftover-balance churn is what generates refund requests and one-star reviews.
--
-- SAME PRODUCT IDS AS THE FOOD REALM, and that is correct rather than a copy-paste slip: developer products
-- are scoped to the UNIVERSE, not the place, and all three realms live in one universe. One product, bought
-- anywhere, credited by whichever place the player was standing in.
SkinCrates.TOKEN_PACKS = {
	{ id = "tok100",  productId = 3699250369, tokens =  100, robux =  25,                    label = "100 Tokens"   },
	{ id = "tok300",  productId = 3699255106, tokens =  300, robux =  59, tag = "Popular",    label = "300 Tokens"   },
	{ id = "tok700",  productId = 3699261145, tokens =  700, robux = 129,                    label = "700 Tokens"   },
	{ id = "tok1500", productId = 3699268487, tokens = 1500, robux = 239,                    label = "1,500 Tokens" },
	{ id = "tok4400", productId = 3699282826, tokens = 4400, robux = 549, tag = "Best Value", label = "4,400 Tokens" },
}

-- ---- TEST MODE (no Robux) -----------------------------------------------------------------------------------
-- While TEST_MODE is true the token packs do NOT open a Roblox purchase prompt (there is no real product yet).
-- The client fires "buy" and the SERVER credits tokens through the SAME addTokens() the real ProcessReceipt path
-- calls, so every downstream step (balance, save, crate open, roll, grant, reveal) behaves exactly as it will on
-- launch. The only difference is where the credit comes from.
--
-- TEST_MODE and the ids above are ONE decision, never two. TEST_MODE credits tokens on the client's say-so
-- with no receipt -- harmless while the products did not exist, and a free-token faucet the moment they do.
-- So it went off in the same edit that pasted the real ids in.
SkinCrates.TEST_MODE = false

-- ---- TRADE UPS ---------------------------------------------------------------------------------------------
-- CS:GO's trade-up contract: hand in TRADE_UP.COST skins of one rarity, get 1 random skin of the next rarity up.
-- The pet is random, the skin is random, and the trait rolls fresh -- so a trade-up is its own little pull.
--
-- This is the sink that gives duplicates a purpose. Without it a second Stone Bean Buddy is worth nothing and
-- the inventory just accumulates; with it every duplicate is 1/10th of a step up the ladder.
SkinCrates.TRADE_UP = {
	COST = 10, -- how many same-rarity skins one contract consumes
	-- What each rarity trades UP into. Gold is deliberately absent: it's the top, so it has nothing to become.
	NEXT = {
		Common    = "Uncommon",
		Uncommon  = "Rare",
		Rare      = "Epic",
		Epic      = "Legendary",
		Legendary = "Gold",
	},
}

-- The rarity a given tier trades up into, or nil if it's the top of the ladder.
function SkinCrates.tradeUpTarget(tier)
	return SkinCrates.TRADE_UP.NEXT[tier]
end

-- Every (pet, skin) pair that can come OUT of a trade-up at `tier`, gathered from every crate so the result pool
-- isn't limited to one crate's collection. Deduped -- the same pair often appears in more than one crate.
function SkinCrates.tradeUpPool(tier)
	local seen, out = {}, {}
	for _, crate in ipairs(SkinCrates.CRATES) do
		-- A level crate stocks no skins, so it can neither feed nor receive a trade-up contract.
		-- isSkinCrate, not "not isLevelCrate": the Pet Crate stocks no skins either, so feeding it to a
		-- trade-up contract would offer a pet as skin collateral and pay out nothing.
		for _, e in ipairs(SkinCrates.isSkinCrate(crate) and crate.contents[tier] or {}) do
			local k = e.pet .. "|" .. e.skin
			if not seen[k] then seen[k] = true; out[#out + 1] = { pet = e.pet, skin = e.skin } end
		end
	end
	return out
end

-- ---- LOOKUPS ------------------------------------------------------------------------------------------------
SkinCrates.ById = {}
for _, c in ipairs(SkinCrates.CRATES) do SkinCrates.ById[c.id] = c end

-- Does this crate pay out pet LEVELS instead of skins? Everything that has to branch on payout shape asks
-- here rather than testing `kind` directly, so adding a third kind later is one edit, not a search.
function SkinCrates.isLevelCrate(crateOrId)
	local c = type(crateOrId) == "table" and crateOrId or SkinCrates.getCrate(crateOrId)
	return c ~= nil and c.kind == "levels"
end

-- Does this crate pay out PETS (at the rolled rarity) instead of skins? Same shape of question as
-- isLevelCrate, and every branch that asks "what does this crate actually give me" must ask both.
function SkinCrates.isPetCrate(crateOrId)
	local c = type(crateOrId) == "table" and crateOrId or SkinCrates.getCrate(crateOrId)
	return c ~= nil and c.kind == "pets"
end

-- A crate that pays out anything other than a skin. The skin-only machinery -- trade-up contracts, the
-- Collection Book, the Gold skin announcement -- must skip these, because there is no skin to operate on.
function SkinCrates.isSkinCrate(crateOrId)
	return not (SkinCrates.isLevelCrate(crateOrId) or SkinCrates.isPetCrate(crateOrId))
end

function SkinCrates.getCrate(id)
	return (type(id) == "string" and SkinCrates.ById[id]) or nil
end
function SkinCrates.packById(id)
	for _, p in ipairs(SkinCrates.TOKEN_PACKS) do if p.id == id then return p end end
	return nil
end
function SkinCrates.packByProductId(productId)
	for _, p in ipairs(SkinCrates.TOKEN_PACKS) do if p.productId == productId then return p end end
	return nil
end

-- Every entry in a crate, flattened to { pet, skin, rarity } in RARITY_ORDER. Used by the client to build the
-- reel and the crate's contents list, and by the require-time validator below.
function SkinCrates.flatContents(crateId)
	local crate = SkinCrates.getCrate(crateId)
	local out = {}
	if not crate then return out end
	for _, rarity in ipairs(SkinCrates.RARITY_ORDER) do
		for _, e in ipairs(crate.contents[rarity] or {}) do
			out[#out + 1] = { pet = e.pet, skin = e.skin, levels = e.levels, rarity = rarity }
		end
	end
	return out
end

-- Which rarity bands this crate actually has entries for, and their total weight. A crate mid-build (some bands
-- empty) stays openable: the empty bands' weight is redistributed proportionally across the filled ones.
-- ---- LUCK ---------------------------------------------------------------------------------------------------
-- `luck` (optional, default 1) multiplies the weight of every band ABOVE the commonest LIVE one. Because the
-- roll and the odds panel both renormalise on the returned `total`, the commonest band's share shrinks by
-- exactly what the rarer bands gain -- so luck never has to be subtracted anywhere by hand, and the published
-- odds and the rolled odds still come from this one function.
--
-- Luck 1 (or nil) returns the weights BIT FOR BIT unchanged, so every existing caller is unaffected.
-- Callers get their number from Shared.Gamepasses.luckFor (rebirth luck x the Lucky Pass, clamped).
function SkinCrates.liveRarities(crateId, luck)
	local crate = SkinCrates.getCrate(crateId)
	local live, total = {}, 0
	if not crate then return live, 0 end
	local odds = SkinCrates.oddsFor(crate)
	local boost = (type(luck) == "number" and luck > 1) and luck or 1
	for _, rarity in ipairs(SkinCrates.RARITY_ORDER) do
		local pool = crate.contents[rarity]
		if pool and #pool > 0 then
			local w = odds[rarity] or 0
			if boost > 1 and #live > 0 then w = w * boost end -- #live > 0 -> not the commonest live band
			live[#live + 1] = { rarity = rarity, weight = w, count = #pool }
			total = total + w
		end
	end
	return live, total
end

-- The EFFECTIVE percent chance of each rarity in THIS crate (after empty-band redistribution). This is what the
-- odds panel must print -- not the raw RARITY_ODDS -- or the published odds would be wrong for a partial crate.
-- Pass the player's `luck` to print the odds they will ACTUALLY roll at -- a Lucky Pass owner reading the base
-- odds panel is being told the wrong number about the thing they paid for.
function SkinCrates.effectiveOdds(crateId, luck)
	local live, total = SkinCrates.liveRarities(crateId, luck)
	local out = {}
	if total <= 0 then return out end
	for _, l in ipairs(live) do
		out[l.rarity] = (l.weight / total) * 100
	end
	return out
end

function SkinCrates.totalRarityWeight()
	local t = 0
	for _, r in ipairs(SkinCrates.RARITY_ORDER) do t = t + (SkinCrates.RARITY_ODDS[r] or 0) end
	return t
end

-- ---- THE ROLL -----------------------------------------------------------------------------------------------
-- SERVER-ONLY in practice (the client never calls this). `rng` is a Roblox Random so the SERVER owns the
-- randomness. Rarity first, then a uniform pick inside that rarity -- exactly the specified order.
--
-- Returns: rarity, entry, entryIndex
--   entryIndex is the position in flatContents(crateId), so the client can scroll its reel to the exact item
--   the server picked -- the animation can never show a different reward than the one granted.
-- Returns nil if the crate id is unknown or completely empty.
function SkinCrates.roll(rng, crateId, luck)
	local crate = SkinCrates.getCrate(crateId)
	if not crate then return nil end
	local live, total = SkinCrates.liveRarities(crateId, luck) -- `luck` nil/1 -> identical weights to before
	if total <= 0 then return nil end

	-- 1) RARITY
	local pick = rng:NextNumber(0, total)
	local acc, chosen = 0, live[#live].rarity
	for _, l in ipairs(live) do
		acc = acc + l.weight
		if pick < acc then chosen = l.rarity; break end
	end

	-- 2) UNIFORM pick inside that rarity
	local pool = crate.contents[chosen]
	local entry = pool[rng:NextInteger(1, #pool)]

	-- 3) the entry's index in the flattened list, for the client's reel
	local idx = 0
	local isLevels = SkinCrates.isLevelCrate(crate)
	for i, e in ipairs(SkinCrates.flatContents(crateId)) do
		-- Match on whichever payload this crate uses. A level crate has no pet/skin, so comparing those would
		-- compare nil to nil, match the FIRST entry of the band every time, and land the reel on the wrong cell.
		local same = false
		if e.rarity == chosen then
			if isLevels then same = (e.levels == entry.levels)
			else same = (e.pet == entry.pet and e.skin == entry.skin) end
		end
		if same then idx = i; break end
	end

	return chosen, entry, idx
end

-- ---- REQUIRE-TIME VALIDATION --------------------------------------------------------------------------------
-- Fails loudly on load rather than shipping a crate with an unobtainable or mis-typed reward.
do
	local total = SkinCrates.totalRarityWeight()
	assert(math.abs(total - 100) < 1e-6,
		string.format("[SkinCrates] RARITY_ODDS must sum to 100, got %s", tostring(total)))

	for _, crate in ipairs(SkinCrates.CRATES) do
		assert(type(crate.id) == "string" and crate.id ~= "", "[SkinCrates] every crate needs an id")
		assert(type(crate.price) == "number" and crate.price > 0,
			string.format("[SkinCrates] crate '%s' needs a positive token price", tostring(crate.id)))
		local count = 0
		for rarity, pool in pairs(crate.contents) do
			assert(SkinCrates.RARITY_ODDS[rarity] ~= nil,
				string.format("[SkinCrates] crate '%s' has unknown rarity band '%s'", crate.id, tostring(rarity)))
			for _, e in ipairs(pool) do
				if SkinCrates.isLevelCrate(crate) then
					-- a level entry must actually pay something, or an open would charge tokens for nothing
					assert(type(e.levels) == "number" and e.levels > 0 and e.levels % 1 == 0,
						string.format("[SkinCrates] crate '%s' / %s: level entries need a positive whole `levels`",
							crate.id, rarity))
				elseif SkinCrates.isPetCrate(crate) then
					-- a pet entry is a species and NOTHING else: the band it sits in supplies the rarity, so there
					-- is no skin to validate. Checked separately because PetSkins.exists(nil) is false and would
					-- have hard-failed this crate at require time, taking every other crate down with it.
					assert(type(e.pet) == "string" and e.pet ~= "",
						string.format("[SkinCrates] crate '%s' / %s has a pet entry with no pet", crate.id, rarity))
					assert(e.skin == nil,
						string.format("[SkinCrates] crate '%s' / %s: pet entries must not carry a skin (got '%s')",
							crate.id, rarity, tostring(e.skin)))
				else
					assert(type(e.pet) == "string" and e.pet ~= "",
						string.format("[SkinCrates] crate '%s' / %s has an entry with no pet", crate.id, rarity))
					assert(PetSkins.exists(e.skin),
						string.format("[SkinCrates] crate '%s' / %s: skin '%s' is not in PetSkins.Skins",
							crate.id, rarity, tostring(e.skin)))
				end
				count = count + 1
			end
		end
		assert(count > 0, string.format("[SkinCrates] crate '%s' is empty", crate.id))

		-- A crate that overrides the odds must ALSO sum to 100, and may only name rarities we know about.
		-- Without this a typo'd override ("Rate = 34") would silently vanish 34% of the weight and quietly
		-- change every published percentage in that crate.
		if crate.odds then
			local ot = 0
			for rarity, w in pairs(crate.odds) do
				assert(SkinCrates.RARITY_ODDS[rarity] ~= nil,
					string.format("[SkinCrates] crate '%s' odds has unknown rarity '%s'", crate.id, tostring(rarity)))
				assert(type(w) == "number" and w >= 0,
					string.format("[SkinCrates] crate '%s' odds for '%s' must be a number >= 0", crate.id, rarity))
				ot = ot + w
			end
			assert(math.abs(ot - 100) < 1e-6,
				string.format("[SkinCrates] crate '%s' odds must sum to 100, got %s", crate.id, tostring(ot)))
		end
	end

	-- TRADE UPS: every rung of the ladder must actually be reachable. If a tier trades up into a rarity that no
	-- crate stocks, a contract would consume 10 skins and return nothing -- so refuse to load instead.
	for from, to in pairs(SkinCrates.TRADE_UP.NEXT) do
		assert(SkinCrates.RARITY_ODDS[from] ~= nil and SkinCrates.RARITY_ODDS[to] ~= nil,
			string.format("[SkinCrates] TRADE_UP.NEXT names an unknown rarity: %s -> %s", tostring(from), tostring(to)))
		assert(#SkinCrates.tradeUpPool(to) > 0,
			string.format("[SkinCrates] TRADE_UP %s -> %s: no crate stocks any '%s' skin, so the contract "
				.. "could never pay out", from, to, to))
	end
end

return SkinCrates
