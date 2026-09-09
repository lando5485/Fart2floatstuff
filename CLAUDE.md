# Fart to Float - Game Documentation

> **Progression was rebuilt on 2026-08-22 from `F2F UNIVERSAL SPACING GUIDE.md` (the Dinosaur Realm's
> shipped tower), values copied exactly.** The authority for every number below is the source:
> `src/shared/FlightTuning.luau`, `src/shared/IslandOrder.luau` and the two tables in `PlayerStats`.
> `python tools/ladder.py` parses those files and replays the whole climb -- **run it after any tuning
> change; a realm is not done until it passes.** If this file and the harness disagree, the harness is right.

## Game Concept
Players buy food -> fills stomach -> hold fart button to fly up -> earn coins **per stud travelled** ->
buy more food -> reach higher islands. 14 islands, 13 crossings, 7 coin guts.

New player defaults (`PlayerStats.server.lua`, `DEFAULT_COINS/STOMACH/ISLAND`): **2,000 coins, Tiny Gut
(120 maxPower), island 1.** 2,000 against a 1,280 first meal is a 3-rung tutorial ladder off the bank.

---

## ⚠ CURRENT TESTING STATE — READ BEFORE PUBLISHING

`PlayerStats.server.lua` — `DISABLE_SAVE_FOR_TESTING = true`.

Every join starts as a brand-new player and **nothing is written to the DataStore**. This is deliberate
(fast iteration on the opening minutes) but it is the single most destructive thing that can ship: live,
every player loses all progress the moment they leave, unrecoverably. **Set it to `false` before publishing.**

It is mirrored to `_G.FRESH_PLAYER_TESTING` for the rest of the server. **Any feature with its own
DataStore must read that flag**, or it restores something a "brand-new" test player never earned and the
gate it guards looks broken. `SecretTreeDoor`'s Gnome Home key did exactly that until 2026-09-06.

`FRESH_PLAYER_TEST`, `SPAWN_AT_PIZZA_PALMS_TEST` and `FRESH_PLAYER_USERID` in the same file are **dead
code** — declared, never read. Their comments claim to protect one account's save data. They do not, and
never did. Flipping them changes nothing.

---

## The structure: one gut = one WALL + one STRETCH
Every coin gut covers exactly two crossings. The **wall** gap is the previous gut's full-tank climb
× 1.020 — you get 97%+ of the way on a full tank and cannot land; that 2% *is* the "buy a gut" message,
delivered by the flight, not a popup. The **stretch** gap is the new gut's climb ÷ 1.031 (97% of the tank).
Tier 1 covers only c1 (tutorial, 1.355× headroom). Tier 7 covers c12 (widened to 6200 for the summit
grind) and c13. **Do not move an island without re-running the harness** — the gates are
`climb[k] ≥ own gaps` and `climb[k] + coast < next tier's gaps`, and both are asserted.

## Island Heights
`IslandOrder.SLOT_POS` (**one copy**; PlayerStats positions the Workspace models from it at boot and
CoreClient reads the same table). Slot == island number; keep the identity `SLOT_TO_ISLAND` table.

| # | Island | X | Y | Z | Gap up | Gut (tier) |
|---|--------|------|-------|------|-------|------|
| 1 | Bean Farm | 0 | 150 | 0 | 630.0 | Tiny |
| 2 | Broccoli Bluff | 120 | 780 | 60 | 1068.0 | Small (wall) |
| 3 | Cabbage Cliffs | -160 | 1848 | 100 | 1242.0 | Small (stretch) |
| 4 | Turnip Tranquil | 180 | 3090 | -120 | 1305.0 | Medium (wall) |
| 5 | Coconut Cove | -200 | 4395 | 160 | 1792.5 | Medium (stretch) |
| 6 | Bread Board | 220 | 6187.5 | -180 | 1885.5 | Large (wall) |
| 7 | Pasta Peak | -240 | 8073 | 200 | 2482.5 | Large (stretch) |
| 8 | Popcorn Pinnacle | 260 | 10555.5 | -220 | 2610.0 | XL (wall) |
| 9 | Milk Marsh | -280 | 13165.5 | 240 | 3448.5 | XL (stretch) |
| 10 | Butter Swamp | 300 | 16614 | -260 | 3625.5 | XXL (wall) |
| 11 | Ice Cream Isle | -320 | 20239.5 | 280 | 4827.0 | XXL (stretch) |
| 12 | Burger Bluff | 340 | 25066.5 | -300 | 6200.0 | Iron (wall, summit grind) |
| 13 | Burrito Barrens | -360 | 31266.5 | 320 | 6896.2 | Iron (stretch) |
| 14 | Pizza Palms | 380 | 38162.7 | -340 | — | — |

Slots 1–13 are the guide's exact positions; island 14 is the one addition (the guide's tower is 13
islands), placed by the guide's own stretch rule `7110 ÷ 1.031`. Islands 3, 5 and 7 are rotated about
Y for looks only (`ISLAND_ROTATIONS`). Anything that hard-codes a height (skies, events) needs re-checking
against this table — the old summit was Y 24,017, the new one is 38,163.

**Known world issue:** island 2's model is misspelled `Island_2_BrocolliBluff` in Workspace. PlayerStats
falls back and warns every boot. Renaming it to `Island_2_BroccoliBluff` removes a permanent workaround.

## Food Data
`foods` — **identical in `CoreClient.client.lua` and `PlayerStats.server.lua`**; change both.

| Name | Price | Power | Island | Power/coin |
|------|-------|-------|--------|-----------|
| Beans | 1280 | 32 | 1 | 0.0250 |
| Broccoli | 1480 | 40 | 2 | 0.0270 |
| Cabbage | 1480 | 40 | 3 | 0.0270 |
| Turnips | 1520 | 45 | 4 | 0.0296 |
| Coconuts | 1520 | 45 | 5 | 0.0296 |
| Bread | 1720 | 55 | 6 | 0.0320 |
| Pasta | 1720 | 55 | 7 | 0.0320 |
| Popcorn | 1840 | 65 | 8 | 0.0353 |
| Milk | 1840 | 65 | 9 | 0.0353 |
| Butter | 2200 | 85 | 10 | 0.0386 |
| IceCream | 2200 | 85 | 11 | 0.0386 |
| Burger | 3080 | 130 | 12 | 0.0422 |
| Burrito | 3080 | 130 | 13 | 0.0422 |
| Pizza | 3080 | 130 | 14 | 0.0422 |

**Rules the harness asserts:** power/price never decreases up the tower (1.69× spread, ≥1.5 required);
power never decreases; every crossing can afford its own food on flight 1; no meal past the tutorial
exceeds 20% of its crossing. A food unlocks when its island has been reached (ceiling lock); below
that, anything is buyable anywhere — with monotonic value that is never a trap.

Stretch crossings need ~97% of the tank, which whole servings of one food cannot always make (6 Broccoli
= 240 of a 270 tank). Mixing in a cheaper food (5 Broccoli + 2 Beans = 264) does it — that is by design.

## Stomach Tiers
`stomachTiers`, `PlayerStats.server.lua`; `maxPower` **must** equal `FlightTuning.BASE_TIERS` row for row
(asserted). Mirrors: `tierDefs` + `dbgTiers` + `stomachNames` in CoreClient, `TIERS` in BellySystem/BellyPuff.

| Name | maxPower | Climb (full tank) | Cost | Island gate |
|------|----------|-------|------|-------------|
| Tiny Gut | 120 | 853.5 | 0 | 1 |
| Small Gut | 270 | 1279.5 | 1,000 | 2 |
| Medium Gut | 470 | 1848.0 | 2,000 | 4 |
| Large Gut | 620 | 2559.0 | 4,000 | 6 |
| XL Gut | 1080 | 3555.0 | 5,000 | 8 |
| XXL Gut | 1710 | 4977.0 | 6,000 | 10 |
| Iron Gut | 2600 | 7110.0 | 11,500 | 12 |
| Infinite Gut | 9999 | 7110.0 (top tier) | 499 Robux | 1 |

Each gut costs less than the crossing before its wall pays out, so saving is short. The island gate is a
second lock on top of cost. **A purchased gut arrives EMPTY** (`COURTESY_FRACTION = 0`) — it used to come
full, which handed out a free crossing with every purchase. Whatever was in the tank is kept.

## Flight System (`src/shared/FlightTuning.luau`)
- **`climbFor(tank, power)` / `powerForClimb(tank, dist)`** are the whole model: an 8-band speed taper
  (`SPEED_SHAPE`, mean exactly 1.0) across the tank, so a full tank climbs exactly `tier.climb` studs.
  **No time term in either** — that is what makes every gate scale-free.
- **Wall-clock:** `FLIGHT_SECONDS = 22.75`, stretched per tier by `TIER_TIME` (1.00, 1.00, 1.35, 1.50,
  1.55, 1.60, 1.60). Mean speeds 37.5 → 56.2 → 60.2 → 75.0 → 100.8 → 136.7 → 195.3 studs/s — must rise
  with every gut. `speed = climb ÷ time`, so retiming moves no gate; it is the only free pacing lever.
- **Drain:** `100 / tankSecondsFor(stomachMax)` %/s — the bar always empties in one flight.
- `getFlightSpeed(power, stomachMax)` is multiplied by `_G.serverEventSpeedMult`, `_G.rebirthSpeedMult`,
  ×1.35 for Shady Sal's rocket gas, ×2 for a 2x boost, ×0.7 carrying the watering can. (These lift the
  climb without lifting drain — events are bounded so they can save an attempt, never skip a crossing.)
- **Coast:** thrust ends → upward velocity damped to `COAST_DAMPING = 0.4` (16% of the undamped coast),
  1–22 studs across the tiers. Gates are verified **with** the coast.
- **Fuel is never wiped on touchdown** — leftover carries. The arrival bleed is off (`ARRIVAL_BLEED_RADIUS
  = 0`); the wall spacing makes it redundant.
- **Infinite Gut owners never drain** — the meter is re-topped every frame.
- **Gas bubbles** grant `max(2, tank * 0.0075)` -- +2 on a Tiny Gut, +3.5 on a Medium, +19.5 on an Iron,
  so the raw power climbs with you instead of decaying to nothing. **0.75% is the top of the range, not a
  preference:** a gap holds two bubbles and a wall crossing leaves only a ~2% margin, so the pair must fit
  inside it. At 0.75% the Medium/Large/XL walls keep 6.9/8.4/10.4 studs spare; 0.8% cuts that to ~5 and
  **0.9% goes negative** -- a full tank plus two bubbles clears a wall and the tower loses a rung. The
  fraction has to stay flat across tiers because the margin it fits inside is itself a flat ~1.9% of the
  climb. Baseline progression still works with zero bubbles. Bubbles also pay coins -- see **Pickup
  bonus** above.

## Coin System
`COIN_PER_STUD = COIN_PER_STUD_BASE / SPACING_SCALE = 2.4024 / 0.6825 = 3.52`. Coins are billed for
**distance travelled**, not height.

| Outcome | Pays |
|---|---|
| Crossing lands | `gap × 3.52` (climb only) |
| Flight fails | `climb × 3.52 × (1 + DESCENT_PAY_MULT)` = **3× the climb** |

That asymmetry is the single lever that sets flight counts — never fold the 2× into the base rate.
`R = eff × 3.52 × 3 × climb / tank` is "how much further the next flight goes"; min R is 1.187 (≥1.15
asserted), which is what keeps the last miss in the 80s instead of grinding through the 90s.

**Prepay** (`CoreClient`): at launch `climbFor(stomachMax, currentPower)` predicts the peak; if it is
under `gap × PREPAY_SAFETY (0.90)` the flight is already a failure and every climbed stud pays 3× on the
spot. Otherwise the climb pays 1× per `COIN_TICK` (0.23s) and the 2× is paid per stud **fallen** below
the peak, settled at touchdown — a landing on the next island falls ~0 studs and pays nothing extra.

**Pickup bonus:** both bubbles pay a **set amount, no streak multiplier**, and it **grows with altitude**
(`_G.pickupCoins(kind, atY)` in CoreClient): a fixed share of the meal sold at whatever island the player
is currently level with -- **15%** for a coin bubble (190 at Bean Farm -> 460 at Pizza Palms), **half
that** for a gas bubble (100 -> 230). It reads the player's Y against `ISLAND_POS` (+25 tolerance, because
a landing surface can sit just below its own configured Y), **not** the `Island` leaderstat, which only
goes up and would pay summit rates to someone on island 1. Two of each per gap, so sweeping a gap is ~45%
of one meal at every height. `serverEventRingMult` still applies and peaks at 10, so one bubble at the
summit can pay ~4,600 -- under the 8,000 single-grant cap.

**Server side** (`CoinEvent.OnServerEvent`): friend/group bonus, rebirth, Sal's 2× in that order; then
`math.floor` via `playerCoinAccum`. **Validation** rejects NaN/inf/≤0, caps a single grant at 8,000
(an Iron Gut falling at terminal speed during COIN_RUSH is ~5.4k per tick), rate-limits calls and
budgets each 5s window at "one full failed flight on this player's gut during COIN_RUSH" + a 5,000 ring
allowance — computed from the server's own StomachMax. Still a **bound, not authority**.

**Anti-strand** (`BuyFoodEvent`): land dry and unable to afford any unlocked food → the shop grants
exactly enough for one serving of the island's own food, once per landing. The free meal peaks at 34% of a
crossing; it must never hand one over (an earlier design priced it on `powerShortfall()` and did).

## Reference ladder (`python tools/ladder.py`)
Whole-serving reference player, no events, no bubbles:
`[3, 7, 4, 7, 8, 6, 4, 13, 7, 14, 9, 12, 6]` = 100 flights. The guide's own curve for the same values is
`[3, 7, 4, 8, 7, 8, 4, 10, 6, 13, 9, 16]`; c1–c3 replay identically. Two texture checks fail under
whole servings (a coin-limited 99.6% final-try miss on c13; repeated steps at wall crossings where coins
are low right after the gut) — the values were copied as-is and not retuned around them.

## Power System Rules
- **Stomach full check uses `>` not `>=`:** a purchase landing exactly on stomachMax is allowed.
- **Coins are NOT deducted if the stomach is full:** `StomachFullEvent` fires and the handler returns
  before `coins.Value` is reduced.
- currentPower resets on respawn; it is **kept** (clamped) on a gut purchase and on landing.

## Known Issues
- **No island has a PrimaryPart**, so PlayerStats places all 14 with `MoveTo`, which puts the model's
  **bounding-box centre** on `SLOT_POS`. One part left far outside the island stretches that box and the
  landmass lands somewhere else entirely while the boot log still prints the right Y. Cabbage Cliffs did
  this on 2026-08-30: `Positioned Island_3_CabbageCliffs at Y=1848` with its ground at Y=243, 1605 studs
  low. PlayerStats now measures the island by the **median part** (`coreCentre`), corrects the placement
  and warns with the stray part's full name; `tools/IslandAudit.studio.luau` finds them in Studio. The
  correction is a safety net -- delete the stray in Studio, don't leave the island relying on it.
- Anything that hard-coded the old heights (sky bands in `EventClient`, island 14 at 24,017) is stale.
- Events and the 2x gamepass multiply speed without multiplying drain, so they extend the climb; events are
  bounded (×1.3 for 7s) but the 2x pass is a ×2 climb for its whole duration and can leak a gate.

## Pet abilities (`src/shared/PetAbilities.luau`)
Pets stopped being cosmetic-only on 2026-09-06. **`PetAbilities.DEFS` is the only place a pet bonus is
defined**; `PetAbilityService.server.luau` resolves it against who is equipped and publishes each lever as a
`PetAbil_<lever>` **player attribute** (server-written, client-read) plus `_G.petAbility(player, lever)` for
server code. Adding a pet's ability is a row in DEFS and nothing else. Pets 7-14 are live; **1-6 are absent on
purpose** -- a species with no row contributes nothing.

**⚠ THE RULE: no ability may touch flight speed, climb height, gas drain, coast, or gas-bubble power.** Those
lift the climb without lifting drain and eat the `climb[k] + coast < next tier's gaps` margin, which is only
~1.9% of a climb. With up to 5 equip slots, duplicate stacking (100/60/38/27.5/20%) and enchants all
multiplying, one speed lever would collapse the ladder, not just leak a rung. Every lever is therefore outside
the flight maths: coins, prices, reach, luck, tokens, XP, defence. Deltas are **summed then finalised once** --
never compounded, or five "+8%" pets would quietly become +47%.

Wired at: `PlayerStats` CoinEvent (coinAll, after the budget check so it can't buy anti-cheat headroom),
`SkinCrateService` luckFor (crateLuck), `AFKTokenFarm` (afkRate, on credited tokens only -- never the
`paidUpTo` clock), `PetSystem.awardXP` (petXp), `CoreClient` descent pay (coinFall) and ring pickup
(bubbleGolden). Tricks + Pollen Sweep's extra **coin** rings live in `PetTricks.client.luau`.
`tools/ladder.py` reads only the `foods`/`stomachTiers` tables, so none of this moves the harness.

## Repo layout
Three separate Roblox places, three separate repos:
- **This repo** — the main Food Realm (14 islands).
- `CandyRealm/` — subfolder here, its own `default.project.json`. **Runs this same food progression model
  since 2026-09-01** (slots 1–13 of the tower, the 7 guts, food rows 1–13, coins per stud) on its own
  shared modules; `CandyRealm/tools/ladder.py` is its harness and `CandyRealm/CANDY_ISLAND_SPACING_AND_ECONOMY.md`
  the spec. Guts there are bought with coins and gated by island reached. **Quests gate NOTHING since
  2026-09-03** -- `STANDS_ALWAYS_OPEN` at the top of `src/client/Shop_AllInOne.client.lua` opens every
  food stand on arrival, so a kid can climb the whole tower without doing a single quest; quests are
  optional and pay coins + crate tokens. The `UnlockedSlot` quest gate is kept working behind that flag.
- `../farttofloatdinosaurealm/` and `../SpaceRealmStuff/` — separate checkouts.

**⚠ `CoreClient` sits at 199/200 locals and CandyRealm's `PetFollow` + `AncientTreeQuest` at 200/200.**
Roblox refuses a 201st live local in a function and a script's main chunk IS one -- the script then
silently never runs (no error except one line in the client log). `python tools/registers.py .` measures
it; note that locals inside a top-level `do`/`if`/`for` block count too, so indentation tells you nothing.
In a file that is full, write `_G.name = function() ... end` instead of `local function name()` -- it
costs zero registers.

Key files: `src/shared/FlightTuning.luau` (flight math + coin constants), `src/shared/IslandOrder.luau`
(island positions), `src/client/CoreClient.client.lua` (flight loop, HUD, food table), `src/server/PlayerStats.server.lua`
(save/load, islands, guts, coins), `tools/ladder.py` (the progression harness), `src/client/PetFollow.client.lua` (pets **and** the real fishing quest),
`src/client/NotifyCenter.client.luau` (all banners — use `push`/`pin`, don't build a new ScreenGui),
`src/client/GutGrowCinematic.client.luau` (the gut-purchase shot — **identical file in all four realms**).

## The gut purchase moment (`GutGrowCinematic.client.luau`)
Stomach max going **up** is the only trigger — never the buy button, so a purchase the server refuses can't
play it. It always plays a buy sound; if the player is **landed** it also hides the open shop panel, swings
the camera around to the belly and plays the stretch sound while the belly grows. `BellyPuff` owns the local
belly size and reads `_G.gutGrowHoldUntil` / `_G.gutGrowSlowUntil` to freeze then slow that growth; realms
with no BellyPuff (space, dino) let the cinematic write the size itself. It is the same file in the food,
candy, dino and space repos — configure nothing per realm, copy it verbatim.

## Rojo Setup
- Run `rojo serve`, connect the plugin in Studio, Ctrl+S in Studio for world changes.
- **Rojo only ADDS — it never overwrites.** A stale copy of a script baked into the place file runs
  *alongside* the synced one. The boot log's `[BootCheck]` and `[SECURITY] NOT-IN-MANIFEST` sections list
  them; there are currently ~27 duplicated scripts. If an edit "does nothing", check the log's line number
  against the file before assuming the code is wrong.
