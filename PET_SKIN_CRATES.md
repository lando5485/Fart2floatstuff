# Pet Skin Crate System (CS:GO style)

Collectible pet-skin economy: crates bought with a **cosmetic-only** currency, a server-rolled reward, a
scrolling reel reveal, independent traits, stacking duplicates, and trading — built **on top of** the existing
pet, trade, quest and save systems rather than beside them.

## Files

| File | What it is |
|---|---|
| `src/shared/PetSkins.luau` | 20 skin themes, the 6 rarity tiers, and the inventory **key format** |
| `src/shared/PetTraits.luau` | 9 traits (incl. None) + odds + `roll()` + render presets |
| `src/shared/SkinCrates.luau` | Crates, contents by rarity, prices, rarity odds, `roll()`, Robux token packs |
| `src/shared/CrateTokens.luau` | The cosmetic currency: earn amounts per source, login streak, caps |
| `src/server/SkinCrateService.server.lua` | Authority: tokens, inventory, the roll, equip, receipts, trade hooks |
| `src/client/PetSkinLook.client.lua` | Renders a skin + trait onto a pet model |
| `src/client/SkinCrateClient.client.lua` | Crate shop, the CS:GO reel, the skin inventory, token packs |

**Reachable from:** MORE+ → **Skin Crates**. Also `_G.toggleSkinCrates()`.

## Edits to existing files (all additive, all guarded)

| File | Change |
|---|---|
| `PlayerStats.server.lua` | 3 new save keys (`crateTokens`, `petSkins`, `equippedSkins`), the `CrateTokens` leaderstat, the receipt hook, the join handshake |
| `PetSystem.server.lua` | Trade session now routes `SKIN:` keys to the skin service (6 small branches). Pet logic untouched |
| `PetFollow.client.lua` | Two guarded one-liners calling `_G.applyPetSkinLook` at the end of `applyLevelVisual` |
| `CoreClient.client.lua` | One MORE+ menu row |
| `DailyTasks.server.lua` | Awards tokens per task, per full clear, and for the login streak |
| `DevCommands.server.luau` | `/givetokens`, `/opencrate`, `/goldtest` |

Every hook is `if _G.x then` — with the crate system removed, all of these behave exactly as before.

## How a roll works

1. **Rarity** from `SkinCrates.RARITY_ODDS` — Common 79.92 / Uncommon 16.00 / Rare 3.20 / Epic 0.64 /
   Legendary 0.16 / **Gold 0.08**. Asserted to sum to 100 at require-time.
2. **A uniform pick** from that rarity's entries in that crate.
3. **The trait**, rolled separately from `PetTraits.TRAITS` — None 85 / Sparkly 6 / Smoky 3.5 / Flaming 2 /
   Frozen 1.5 / Charged 1 / Glowing 0.7 / Cosmic Aura 0.2 / **Crowned 0.1**. Also asserted to sum to 100.

Traits are fully independent of rarity: a Stone Bean Buddy has the same 0.1% shot at Crowned as a Cosmic Pizza
Dragon. That's what makes a low-tier pull with a top trait worth keeping.

**A rarity band with no entries** in a crate is skipped and its weight redistributed across the filled bands, so
a half-built crate is still openable. `SkinCrates.effectiveOdds()` returns the post-redistribution numbers, and
that's what the odds panel prints — printing the raw table would publish wrong odds for a partial crate.

## Server authority

The client sends only `OpenCrate:InvokeServer(crateId)`. The server checks the balance, **spends then grants
synchronously** (no yield between, so a second request can't ride the same balance), and returns the result
**plus the reel index** to stop on. A tampered client can change what the animation looks like and nothing else —
the item is decided and saved before the reel moves.

Both odds tables live in `Shared` and are required by both sides, so the numbers shown to players and the numbers
rolled on are the same values. That's Roblox's honest-odds requirement for paid random items, and the same
contract `PetWheelConfig.luau` already follows. **Do not add a pity timer, a secret re-roll, or visual rigging.**

## The inventory key

`petId | skinId | traitId` — e.g. `PizzaDragon|Galaxy|Crowned`, or `PizzaDragon|Galaxy|` for no trait.

Duplicates stack as a count on the key; a **different trait is a different key**, so these are two entries:

```
PizzaDragon|Galaxy|          x4
PizzaDragon|Galaxy|Crowned   x1
```

A flat string, matching how `_G.playerOwnedPets` already keys pets (`ButterDuck#R`). It survives a DataStore
round-trip as a plain table key, and it passes through the **existing** trade remote as one string — which is
why skins needed no new trade protocol.

## Skins for locked pets

You **can** receive a skin for a pet you haven't unlocked — deliberately, so nobody stays locked to farm better
odds. The skin sits in the inventory reading **"Unlock \<Pet\> to equip"** and is refused by `equipSkin` until
the species is owned.

Nothing migrates when the pet unlocks: the same ownership check simply starts passing. A 2-second watcher
compares the player's pet-ownership *signature* and re-pushes state when it changes, so this works for **every**
unlock path — quest claim, seasonal harvest, starter grant, collection milestone, trade — including ones added
later. One string compare per player per 2s.

## Trading

Rides the existing `PetSystem` trade session (request → offer → confirm → atomic execute, with ownership
re-validated at execution). A skin offer is the same `PetTradeOfferEvent` carrying `SKIN:<key>`; PetSystem routes
those to four hooks on the skin service. Duplicates are tradable — a stack is just a count. Trading a skin for a
pet you haven't unlocked is allowed, and it becomes wearable the moment you unlock it. Giving away the last copy
of a skin you were wearing clears the equip.

## Two currencies, kept apart

| Currency | Leaderstat | Earns | Spends on |
|---|---|---|---|
| Food Coins | `Coins` | playing | food, gut upgrades, progression |
| **Crate Tokens** | `CrateTokens` | quests, realms, quest lines, login streaks, events, codes, Robux | skin crates and future cosmetics |

Enforced structurally: `SkinCrateService` is the only script that spends tokens and it never reads `Coins`. A
crate cannot be bought with coins by construction, not by a check that could be forgotten.

### Awarding tokens

One entry point, so every grant shares the same cap, clamp, log and save:

```lua
_G.crateTokensAward(player, "dailyTask")             -- amount comes from CrateTokens.REWARDS
_G.crateTokensAward(player, "loginStreak", 5)        -- day 5 of the streak
_G.crateTokensAward(player, "promoCode", nil, 500)   -- explicit override
```

Callers pass a **source name**, never an amount, so retuning the cosmetic economy is a one-line edit in
`CrateTokens.REWARDS` and never a hunt through call sites.

**Already wired:** `dailyTask`, `dailyAllTasks`, `loginStreak` (all in `DailyTasks.server.lua`).

**Not yet wired** — one guarded line each, wherever that system decides it succeeded:

| Source | Suggested home |
|---|---|
| `weeklyTask`, `weeklyAllTasks` | whatever runs weeklies (no weekly system exists yet) |
| `realmComplete` | `RealmPortals.server.lua` / the realm's own completion check |
| `questLine`, `petQuest` | `PetSystem.server.lua` at the quest-claim grant |
| `seasonPassFree`, `seasonPassPaid` | `SeasonPass.server.lua` at tier claim |
| `eventReward` | `BigEventScheduler.server.lua` / the event's reward path |
| `promoCode` | the codes handler inside the Season Pass panel |

## Adding content

* **A skin theme** → one row in `PetSkins.Skins`. Every pet can wear it immediately; no per-pet art.
* **A pet** → it already has the whole skin collection. Add its entries to whichever crates should drop them.
* **A crate** → copy a block in `SkinCrates.CRATES`. Nothing outside that table changes.
* **A trait** → one row in `PetTraits.TRAITS`, then adjust the others so the chances still sum to 100 (the
  require-time assert will tell you loudly if they don't). Traits must stay **effect-only** — no wings, no body
  changes — so they keep working on every pet including future ones.

## Before launch

1. **Create 4 Developer Products** for the token packs and paste the real ids over the placeholders
   (`900000001`–`900000004`) in `SkinCrates.TOKEN_PACKS`, then set **`SkinCrates.TEST_MODE = false`**. While
   TEST_MODE is true the packs credit tokens with no Robux charge (the server refuses the buy verb once it's
   false, so a shipped build can't be farmed by an old client).
2. **Upload a Gold fanfare** and set `GOLD_SOUND` in `SkinCrateClient.client.lua`. Until then a Gold pull plays
   the existing reveal sound pitched down and layered — clearly different, but not the payoff it deserves.
3. **Remove the dev commands** (`/givetokens`, `/opencrate`, `/goldtest`) with the rest of `DevCommands`.
4. **Rebalance the earn rates.** At the defaults a full daily sweep is ~95 tokens and a Starter Crate is 250, so
   roughly 2–3 free crates a week. That's a guess, not a tuned number.

## Testing

```
/givetokens 5000     credit tokens, no Robux
/opencrate Starter   force-open (price comped, no DataStore write)
/goldtest            open until a Gold pull lands (0.08% -> expect ~1250 opens)
```

`/opencrate` and `/goldtest` go through the **same** `openCrate` the real button uses — there is no test-only
roll path that could behave differently from production. They skip only the DataStore write, so `/goldtest`'s
thousands of opens can't throttle real saving.

## Notes / known gaps

* **Reel cells are coloured tiles**, not 3D pet previews. The pet models are built procedurally client-side and
  rendering 56 `ViewportFrame`s during a 5-second animation would cost far more than it's worth; the tile shows
  the skin's actual colour, its name, the pet and the rarity band, which reads better at speed anyway. The
  *equipped* pet is fully 3D, and inventory/trade icons get the skin via the `lite` path.
* **Token daily caps are session-scoped.** They exist to stop a bug in a caller becoming an infinite faucet, not
  to limit a legitimate player, so a rejoin resets them. A designed daily limit belongs in the quest system that
  awards it.
* **Verified by inspection, not by running.** Every file was block-balance checked and every cross-file `_G`
  reference confirmed to resolve, but none of it has been run in Studio yet.
