# Pet Skin Crate System (CS:GO style) — Skins + Traits + Overall Tier

Collectible pet-cosmetic economy: crates bought with a **cosmetic-only** currency, a server-rolled reward, a
scrolling reel reveal, stacking duplicates, and trading — built **on top of** the existing pet, trade, quest
and save systems rather than beside them.

**Every pet-cosmetic pull is `1 Skin + 1 Trait`**, rolled independently:

* **Skin** = the pet's main visual identity **and its display name**: *Cosmic Duck*, *Golden Crab*. Recolour +
  material + effects + small deco geometry (Crystal shards, Robot antenna).
* **Trait** = what the pet is **wearing**: a character theme built from accessories (King, Mafia, Wizard,
  Astronaut, Sunglasses…). Never part of the name — the UI says `Trait: King`, never "Cosmic King Duck".
* **Overall Tier** = ONE label (Common…Legendary) computed from hidden values:
  `PetSkins.TIER_VALUE[skin tier] + PetTraits.TIER_VALUE[trait tier] = score → PetTier.THRESHOLDS → tier`.
  Only this single tier ever shows above a pet ("Baby Legendary · Age 3"); the skin/trait rarities are spelled
  out in the pet detail card and inventory rows.

## Files

| File | What it is |
|---|---|
| `src/shared/PetSkins.luau` | The **17 approved skins** (4 Common / 4 Uncommon / 4 Rare / 3 Epic / 2 Legendary), hidden tier values, legacy-id map, the inventory **key format** |
| `src/shared/PetTraits.luau` | The **21 approved traits** + rarity odds + `roll()` + accessory part specs + `PET_OFFSETS` (per-pet placement tuning) |
| `src/shared/PetTier.luau` | Hidden values → Pet Score → **Overall Tier** (thresholds live here) |
| `src/shared/SkinCrates.luau` | Crates, contents by rarity, prices, rarity odds, `roll()`, Robux token packs |
| `src/shared/CrateTokens.luau` | The cosmetic currency: earn amounts per source, login streak, caps |
| `src/shared/TraitShop.luau` | **Trait prices by tier** for the Pet Hut's Customize counter — the one table the server charges from and the client prints |
| `src/client/PetBarn.client.lua` | The Pet Hut panel: the **NAP** tab (drop a pet off) and the **CUSTOMIZE** tab (the trait wardrobe) |
| `src/server/SkinCrateService.server.lua` | Authority: tokens, inventory, the roll, equip, receipts, trade hooks, **legacy migration on join** |
| `src/client/PetSkinLook.client.lua` | Renders a skin + trait onto a pet model (attach-point accessory builder lives here) |
| `src/client/SkinCrateClient.client.lua` | Crate shop, the CS:GO reel, the skin inventory, token packs |
| `src/client/TestPetPreview.client.lua` | **`/testpet`** — the dev-only skin & trait inspector [REMOVE BEFORE LAUNCH] |

**Reachable from:** MORE+ → **Skin Crates**. Also `_G.toggleSkinCrates()`, `/crates`.

## The approved lists — do not add, rename, or remove without sign-off

* **Skins** — Common: Classic, Pastel, Muddy, Arctic · Uncommon: Candy, Jungle, Desert, Ocean · Rare: Lava,
  Toxic, Crystal, Robot · Epic: Golden, Shadow, Ancient · Legendary: Cosmic, Rainbow. **No Galaxy** — Cosmic
  is the space skin.
* **Traits** — Common: Sunglasses, Bowtie, Bandana, Backpack, Beanie · Uncommon: Cowboy, Chef, Party,
  Explorer, Top Hat · Rare: Astronaut, Pirate, Viking, Detective, Ninja · Epic: Mafia, Superhero ·
  Legendary: Wizard, King, Celestial, Titan. **No Samurai.**
  *(Wizard and King moved Epic → Legendary on 2026-09-02: they are the two players ask for by name. The
  Legendary band's 2% is now shared four ways, so each is rarer than it was; Epic's 7% is shared by two.)*

Skins never use the **Gold** band — Gold stays the *pet* rarity jackpot (Pet Crate / Pet Level Crate) and the
knife-pull announcement tier. `SkinCrates` asserts at require time that a skin entry's band matches the
skin's own tier.

## How a pull works

1. **Skin rarity** from the crate's odds (base: Common 79.92 / Uncommon 16.00 / Rare 3.20 / Epic 0.64 /
   Legendary 0.24). Asserted to sum to 100.
2. **A uniform pick** from that rarity's entries in that crate (contents are generated `pets × skins`, so
   every stocked pet can roll every skin of every band — the Collection Book has no dead pages).
3. **The trait**, rolled separately from `PetTraits.TIER_ODDS` — Common 50 / Uncommon 27 / Rare 14 / Epic 7 /
   Legendary 2 — then a uniform pick inside the tier. Also asserted to sum to 100. **There is no "None"
   outcome any more**: every pull grants a trait. `""` (no trait) survives only as a legacy value.

Traits are fully independent of the skin roll, so *Legendary Skin + Common Trait* and *Common Skin +
Legendary Trait* are both live outcomes — that mix is exactly what the Overall Tier score exists to grade.

Crate stocking: **Starter** carries five species, **Premium** the other five, **Elite** is the Pizza Dragon's
wardrobe, and the limited **Mythic** carries everyone with no Commons. Between them every (pet, skin) pair is
obtainable.

**The Trait Crate** (`id = "Traits"`, 200 tokens — above the Pet Crate, below Premium) inverts the roll: the
reel band IS the trait's rarity (Common 55 / Uncommon 25 / Rare 13 / Epic 5.5 / Legendary 1.5) and a uniform
pick inside the band chooses which trait. Because inventory entries are `pet|skin|trait`, the trait arrives
riding a **random species + a skin rolled at the shared baseline odds** (`SkinCrates.rollRideAlong`) — a
perfectly ordinary entry that equips, trades, stacks and saves. Contents are generated from
`PetTraits.ByTier`, so a new trait stocks itself; `kind = "trait"` follows the same contract as the level
and pet crates, and `isSkinCrate()` excludes it from trade-up pools and the Collection Book sweep.

## How a trait fits every pet

Traits are authored ONCE against named attach points — `Head / Face / Neck / Back / Body` — that
`PetSkinLook` derives from each pet's **main body mass**: thin protrusions (Bean Buddy's head vine,
antennae, horns, ears, tails, beaks — filtered by name and by horizontal footprint) never anchor an
accessory, so a hat seats on the top surface of the biggest mass (a duck's head, a bean's body, a crab's
shell, sunk a hair so the brim hugs) and glasses sit on that part's face at eye level. When something is
worn ON the head, any twig poking above the head top (the vine, bunny ears, horns) is hidden — locally and
snapshot-restored, so it reappears the instant the hat comes off; face/neck/back gear never hides anything.
Accessory parts are anchored and ride the pet as a rigid assembly on one RenderStepped pass.
A pet whose anatomy needs a nudge gets an entry in **`PetTraits.PET_OFFSETS`** (position / rotation / scale
per attach point). **Never fork a trait per pet** — tune the offsets. The rule that keeps this working: a
trait must never hide the pet or its skin; the player must always be able to read *what pet, what skin, what
trait* at a glance.

## `/testpet` — the inspection command  [REMOVE BEFORE LAUNCH]

Dev-only (same allowlist as DevCommands). Opens a 700×520 panel with a pet selector and two pages:

* **SKINS** — all 17 skins on the selected pet, no trait (walk the pets to cover *all skins × each pet*).
* **TRAITS** — all 21 traits on the **Classic** skin of the selected pet (*all traits × one common skin*).
* **COMBO** — pick ONE skin + ONE trait from two chip lists and see the pair on a single big preview with
  its Overall Tier, plus TRY. One combination at a time — this is how pairs are inspected without ever
  generating the forbidden all-combos grid.

Deliberately **never** the full skins × traits × pets cross product. Previews build lazily one per frame from
one cached base model per pet; switching pet or page destroys the previous page's models. Nothing is granted,
saved, or sent to the server. Use it to check clipping / floating / scale, then fix in `PET_OFFSETS`.

Every card also has a **TRY** button: it paints that exact combo onto your live follower pet in the world
(full effects — particles, glow, accessories riding the pet) via `_G.petSkinTryOn`, so you can walk around
wearing it. The override lives inside the renderer, so repaints (level-ups, state pushes) keep it until
**CLEAR TRY-ON** in the panel header (or a rejoin) restores the real equip. Client-side preview only —
other players still see the real equip, and the overhead badge shows the try-on's true Overall Tier.

## Server authority

The client sends only `OpenCrate:InvokeServer(crateId)`. The server checks the balance, **spends then grants
synchronously**, and returns the result **plus the reel index** to stop on. A tampered client can change what
the animation looks like and nothing else. Both odds tables live in `Shared` and are required by both sides —
Roblox's honest-odds requirement for paid random items. **Do not add a pity timer, a secret re-roll, or
visual rigging.**

## The inventory key

`petId | skinId | traitId` — e.g. `PizzaDragon|Cosmic|King`, or `PizzaDragon|Cosmic|` for a legacy no-trait
entry. Duplicates stack as a count on the key; a **different trait is a different key**. A flat string,
matching how `_G.playerOwnedPets` already keys pets; it survives the DataStore round-trip and passes through
the **existing** trade remote as one string (`SKIN:<key>`).

**No permanent variant models exist anywhere.** A pet is stored as `pet + skin + trait` and the visuals are
applied dynamically at render time — that is what keeps thousands of combinations free.

## The trait wardrobe — buying a trait at the Pet Hut

Added 2026-09-02. A trait used to exist **only** inside an inventory key, so wearing King meant owning the
exact `Pet|Skin|King` entry a crate happened to mint. The Pet Hut's **CUSTOMIZE** tab sells traits directly:

* **A second, parallel store.** `_G.playerOwnedTraits[player] = { King = true }`, persisted as
  `saved.ownedTraits`. Set membership — no counts, because a second King does nothing the first doesn't.
  The skin inventory, its keys, the Collection Book and trading are **completely untouched**.
* **Prices by tier** (`TraitShop.PRICES`): Common 250 / Uncommon 600 / Rare 1,400 / Epic 3,000 /
  Legendary 7,500 tickets. Priced by tier, never per id, so a new trait is priced automatically — and
  moving Wizard and King up to Legendary repriced them from 3,000 to 7,500 with no edit to this table.
  The whole 21-trait catalogue is 47,250 tickets.
* **It does not replace the Trait Crate.** That stays the 200-ticket gamble. Chasing one *specific* Common
  through the crate averages ~1,800 tickets, so the shop is the guaranteed route and the crate is the
  cheap one. Both are wanted; neither should be strictly better.
* **Crate pulls stock the wardrobe too.** `addSkinEntry` grants the trait — it is the single funnel every
  trait-bearing grant passes through (crate, ride-along, trade-up, dev grant), so no future path can forget.
  Existing saves are back-filled from the skin inventory on join (`skinCrateApplyOnJoin`).
* **Wearing one** goes through `SetPetTrait` (RemoteEvent) → `setPetTrait`, which writes only the `trait`
  half of the equipped pair and checks the **wardrobe** instead of an inventory key. Buying goes through
  `BuyTrait` (RemoteFunction) so the client knows whether it went through before it repaints.
* **A bought trait survives a skin change.** `equipSkin` carries a wardrobe-owned trait across when the new
  entry names no trait of its own, and clearing a skin no longer clears the trait. An entry that *does* name
  a trait still wins — the player picked that exact combination.
* **The tab is built phone-first.** One tier at a time behind a big left/right pager (at most five rows of
  38px with 17px type), not all 21 traits in a grid — a 21-card grid becomes 36px cards and 6px text once the
  panel's UIScale bottoms out on a handset. The bed rail and the footer tip are hidden here (both are NAP
  questions), which drops the tab to 442px and lets it render at ~0.84 on a phone instead of ~0.55.
  The panel's UIScale is now measured against **the panel's own current size**, not a fixed 1280×720, so
  every short state — including the NAP tab — is allowed to render bigger.
* **`skin = nil, trait = King` is a legitimate equip** — it is what you get the moment you buy your first
  one. Both `applyPetSkinLook` and the client's `applyState` mirror used to gate the trait behind a non-nil
  skin and silently dropped it; both now treat the two layers as independent.

## Legacy saves — nothing is wiped

The first-generation ids (skins *Stone…Galaxy*, traits *Sparkly…Crowned*) map to their closest modern
identity via `PetSkins.LEGACY` / `PetTraits.LEGACY`. `SkinCrateService` rewrites the inventory and equips
**once, on join** (old keys merge, counts add; an unrecognisable key is kept verbatim). The renderer and the
equip path also normalise defensively. Old pets without a trait keep `""` and render skin-only.

## Skins for locked pets / Trading / Currencies

Unchanged from the original design: skins for locked pets are received and held ("Unlock <Pet> to equip"),
trading rides the existing PetSystem session via `SKIN:` keys, and Crate Tokens remain structurally separate
from Food Coins. Trade-ups: 10 of one tier → 1 random of the next; the ladder now tops out at **Legendary**.

## Adding content

* **A skin** → one row in `PetSkins.Skins` (approved list only!) + its tier's list in
  `SkinCrates.SKINS_BY_TIER`. Every pet wears it immediately.
* **A trait** → one row in `PetTraits.TRAITS` with accessory part specs; check it on every pet with
  `/testpet`, tune `PET_OFFSETS`. Tier odds are per-band so no re-balancing needed.
* **A pet** → it already has the whole skin + trait collection. Add it to a crate's species list.
* **Retuning value** → `PetSkins.TIER_VALUE`, `PetTraits.TIER_VALUE`, `PetTier.THRESHOLDS`,
  `PetTraits.TIER_ODDS`, `SkinCrates` odds. All config, no code.

## Before launch

1. `SkinCrates.TOKEN_PACKS` product ids are live and `TEST_MODE = false` — unchanged.
2. Upload a Gold fanfare (`GOLD_SOUND` in SkinCrateClient) — Gold now only comes from the Pet / Level crates.
3. **Remove the dev commands** (`/givetokens`, `/opencrate`, `/goldtest`, `/unlockall`, **`/testpet`**).
4. Rebalance earn rates (unchanged guess: ~2–3 free crates a week).

## Testing

```
/givetokens 5000     credit tokens, no Robux
/opencrate Starter   force-open (price comped, no DataStore write)
/goldtest            open until a Gold pull lands (Pet Level Crate default)
/unlockall           grant every skin on every pet + one of each trait
/testpet             the skin & trait inspector (see above)
```

## Notes / known gaps

* **CandyRealm carries the previous generation** of `PetSkins`/`PetTraits`/`SkinCrates`. Its crate stack was
  not migrated in this pass; skins crossing realms are normalised by the Food Realm's `LEGACY` maps on join.
  Port the new shared modules + `PetSkinLook` + crate contents there as one change when CandyRealm's crates
  are next touched — replacing only its `PetSkins` would fail its `SkinCrates` require-time asserts.
* **Accessory placement is heuristic until inspected.** The attach points come from bounding boxes; run
  `/testpet` across every pet and tune `PetTraits.PET_OFFSETS` before calling the visuals done.
* **Token daily caps are session-scoped** (unchanged).
* **Verified by compile + inspection, not by running.** `tools/check.sh .` passes (205 files) and
  `tools/registers.py` is clear, but the new visuals have not yet been eyeballed in Studio.
