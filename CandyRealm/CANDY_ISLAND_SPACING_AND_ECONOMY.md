# Candy Realm — Island Spacing & Economy (FOOD-REALM MODEL)

> **Ported on 2026-09-01 from the first realm (Food Realm / Bean Farm → Pizza Palms), values copied
> exactly.** The authority for every number here is the code: `src/shared/FlightTuning.luau`,
> `src/shared/IslandOrder.luau`, `src/shared/StomachTiers.luau`, `src/shared/CandyData.luau`,
> `src/shared/Constants.luau`. `python tools/ladder.py` (run from `CandyRealm/`) parses those files and
> replays the whole climb — **run it after any tuning change; the realm is not done until it passes.**
> If this file and the harness disagree, the harness is right.
>
> **History.** Candy has had three economies: the Dino Realm's solve (eleven islands, gaps ×1.12,
> `COIN_PER_STUD = 0.14`), then the Space Realm port (`SPACE_ECONOMY_PORT/`, twelve-then-thirteen
> islands, +200 second difference, hard flight ceiling, quest-funded guts), and now this one. The two
> older docs are kept as records only; nothing in them describes the live game.

## The model in one paragraph

Players buy candy → fills the gut → tap fart to fly straight up → earn coins **per stud travelled** →
buy more candy → reach higher islands. 13 islands, 12 crossings, 7 coin guts. A new player starts with
**2,000 coins, the Gumdrop Belly (120 maxPower), slot 1** — 2,000 against a 1,280 first meal is a
3-rung tutorial ladder off the bank. There is **no flight ceiling**: the wall is the tank's *reach*.

## One gut = one WALL + one STRETCH

Every gut past the first covers exactly two crossings. The **wall** gap is the previous gut's full-tank
climb × 1.020 — you get 97%+ of the way on a full tank and cannot land; that 2% *is* the "buy a gut"
message, delivered by the flight. The **stretch** gap is the new gut's climb ÷ 1.031 (97% of the tank).
Tier 1 covers only c1 (tutorial, 1.355× headroom). Tier 7 covers c12 (6200, the summit grind). The
harness asserts `climb[k] ≥ own gaps` and `climb[k] + coast < next tier's gaps` for every tier.

## Island positions (`IslandOrder.SLOT_POS` — the food realm's slots 1–13, verbatim)

| Slot | Model | Name | X | Y | Z | Gap up | Gut |
|---|---|---|---|---|---|---|---|
| 1 | island1 | Candy Cane Court | 0 | 150 | 0 | 630.0 | Gumdrop Belly |
| 2 | island9 | Cocoa Reactor | 120 | 780 | 60 | 1068.0 | Taffy Tummy (wall) |
| 3 | island3 | Cookie Crumble | -160 | 1848 | 100 | 1242.0 | Taffy Tummy (stretch) |
| 4 | island13 | Gumtree Park | 180 | 3090 | -120 | 1305.0 | Cookie Gut (wall) |
| 5 | island5 | Taffy Town | -200 | 4395 | 160 | 1792.5 | Cookie Gut (stretch) |
| 6 | island8 | Crystal Candy Caves | 220 | 6187.5 | -180 | 1885.5 | Jelly Belly (wall) |
| 7 | island18 | Pancake Arena | -240 | 8073 | 200 | 2482.5 | Jelly Belly (stretch) |
| 8 | island15 | Bakery Summit | 260 | 10555.5 | -220 | 2610.0 | Gummy Gut (wall) |
| 9 | island11 | Licorice Tunnels | -280 | 13165.5 | 240 | 3448.5 | Gummy Gut (stretch) |
| 10 | island4 | Frostbell Peak | 300 | 16614 | -260 | 3625.5 | Choco Stomach (wall) |
| 11 | island14 | Marshmallow Camp | -320 | 20239.5 | 280 | 4827.0 | Choco Stomach (stretch) |
| 12 | island19 | Sugarbeet Farm | 340 | 25066.5 | -300 | 6200.0 | Caramel Core (wall) |
| 13 | island16 | Pop Rock Quarry | -360 | 31266.5 | 320 | — | — |

`IslandLayout.server` moves the models here at boot. The slot→model scramble is unchanged from before;
`CandyData.FOODS[k].island` and `IslandConfig.ISLANDS[k].island` carry the same pairing and must move
with any change here. The summit dropped from Y 100,620 to 31,266.5.

## Foods (`CandyData.FOODS` — the food realm's rows 1–13)

| Slot | Name | Price | Power | Power/coin |
|---|---|---|---|---|
| 1 | Candy Canes | 1280 | 32 | 0.0250 |
| 2 | Gumdrops | 1480 | 40 | 0.0270 |
| 3 | Cookies | 1480 | 40 | 0.0270 |
| 4 | Jelly Beans | 1520 | 45 | 0.0296 |
| 5 | Taffy | 1520 | 45 | 0.0296 |
| 6 | Gummy Bears | 1720 | 55 | 0.0320 |
| 7 | Chocolate Bars | 1720 | 55 | 0.0320 |
| 8 | Sundaes | 1840 | 65 | 0.0353 |
| 9 | Rock Candy | 1840 | 65 | 0.0353 |
| 10 | Marshmallows | 2200 | 85 | 0.0386 |
| 11 | Caramel Apples | 2200 | 85 | 0.0386 |
| 12 | Candy Floss | 3080 | 130 | 0.0422 |
| 13 | Sherbet Scoops | 3080 | 130 | 0.0422 |

A food unlocks when its island has been **reached** (`HighestSlot`, a ceiling lock enforced in
`BuyFood.server`); below that anything is buyable anywhere. Value never decreases up the tower (1.69×
spread), so a cheaper lower food is never a trap, and stretch crossings are designed to be filled by
mixing one in (5 Gumdrops + 2 Candy Canes = 264 of a 270 tank).

**The stand on each island is still locked behind that island's quest** (`Shop_AllInOne`'s stand gate,
reading `UnlockedSlot` from the quest ledger). That is candy content, not economy: it makes the quests
mandatory without touching the flight numbers.

## Guts (`StomachTiers.CANDY_GUTS`; `maxPower` must equal `FlightTuning.BASE_TIERS` row for row — asserted)

| Name | maxPower | Full-tank climb | Cost | Unlocks at slot | Food-realm name |
|---|---|---|---|---|---|
| Gumdrop Belly | 120 | 853.5 | 0 | 1 | Tiny Gut |
| Taffy Tummy | 270 | 1279.5 | 1,000 | 2 | Small Gut |
| Cookie Gut | 470 | 1848.0 | 2,000 | 4 | Medium Gut |
| Jelly Belly | 620 | 2559.0 | 4,000 | 6 | Large Gut |
| Gummy Gut | 1080 | 3555.0 | 5,000 | 8 | XL Gut |
| Choco Stomach | 1710 | 4977.0 | 6,000 | 10 | XXL Gut |
| Caramel Core | 2600 | 7110.0 | 11,500 | 12 | Iron Gut |
| Sugar Rush Gut | 9999 | 7110.0 (top tier, never drains) | 499 R$ | — | Infinite Gut |

Guts are **bought with coins** in the GUT panel (`StomachUpgrade.server`): must be a strict upgrade, the
player must have physically reached `unlockSlot`, and the server's price applies. Each gut costs less
than the crossing before its wall pays out. **A purchased gut arrives EMPTY** (`COURTESY_FRACTION = 0`);
whatever was in the tank is kept. **Quests no longer fund or gate guts** — they pay their own coin
reward through `CoinEvent` (750–3,000, all under the 8,000 single-grant cap) plus crate tokens.

## Flight (`FlightTuning.luau`, run by `PropelSystem_AllInOne.client.lua`)

- `climbFor(tank, power)` / `powerForClimb(tank, dist)`: an 8-band speed taper (`SPEED_SHAPE`, mean 1.0)
  across the tank, so a full tank climbs exactly `tier.climb`. No time term — every gate is scale-free.
- Wall-clock: `FLIGHT_SECONDS = 22.75`, stretched per tier by `TIER_TIME` (1.00, 1.00, 1.35, 1.50, 1.55,
  1.60, 1.60). Mean speeds 37.5 → 56.2 → 60.2 → 75.0 → 100.8 → 136.7 → 195.3 studs/s, rising every gut.
- Drain: `stomachMax / tankSecondsFor(stomachMax)` raw power per second — the bar always empties in one
  flight. The tank is raw power (0..StomachMax) so the server sync (`BurnFuelEvent`, downward only) needs
  no conversion. Sugar Rush owners never drain.
- Coast: thrust ends → upward velocity damped to `COAST_DAMPING = 0.4` (1–22 studs across the tiers).
- Fuel is never wiped on touchdown; only respawn zeroes the tank (server-side). No arrival bleed.
- Speed multipliers honoured: `_G.serverEventSpeedMult`, `_G.rebirthSpeedMult`; drain: `_G.serverEventGasDrainMult`;
  winds: `_G.windstormDir` / `_G.thunderWindVec`.

## Coins

`COIN_PER_STUD = 2.4024 / 0.6825 = 3.52`. A landing pays `gap × 3.52`; a failed flight pays
`climb × 3.52 × 3`. **Prepay:** at launch `climbFor(stomachMax, power)` predicts the peak; under
`gap × 0.90` the flight is already a failure and every climbed stud pays 3× on the spot. Otherwise the
climb pays 1× per `COIN_TICK` (0.23 s) and the 2× is paid per stud *fallen* below the peak, settled at
touchdown. The client fires `CoinEvent`; `FlightEconomy.server` **bounds** it (NaN/inf/≤0 rejected,
8,000 per grant, 60 calls per 5 s, budget = 5,000 flat + one failed flight on the server's own StomachMax
at 2× events), then applies friend/group and rebirth multipliers and floors through an accumulator.

**Anti-strand** (`FlightEconomy.ensureCanRefuel`): tank hits zero and the player cannot afford *any*
unlocked food → grant exactly one serving of the reached island's food, once per dry spell. Peaks at 34%
of a crossing.

## Reference ladder (`python tools/ladder.py`)

Whole-serving reference player, no events: `[3, 7, 4, 7, 8, 6, 4, 13, 7, 14, 9, 12]` = **94 flights** —
identical to the food realm's first twelve crossings. `R` runs 1.878 → 1.187 (min ≥ 1.15 asserted). One
texture check fails exactly as it does in the food realm: repeated flat steps at wall crossings where coins
are low right after a gut purchase (9 here). The values were copied as-is and not retuned around it.

## What is NOT saved

Coins, CurrentPower and StomachMax are rebuilt by `ensureStats` on every join — Candy has no economy
DataStore (the food realm's `PlayerData_v1` save is not in this place). Only the quest ledger
(`CandyIslandTasks_v1`) persists, and it now drives the stand gate / journal / wormhole rows, not the tank.
A returning player restarts the climb with 2,000 coins and the Gumdrop Belly. That matches the food
realm's current `DISABLE_SAVE_FOR_TESTING = true` state; a real save is a separate piece of work.

## Files

| File | Owns |
|---|---|
| `src/shared/IslandOrder.luau` | slot order, positions, `GAPS`, names |
| `src/shared/FlightTuning.luau` | flight math, coin constants, tiers' climbs, boot gate audit |
| `src/shared/StomachTiers.luau` | the 7 guts + Sugar Rush, island gates, boot audits |
| `src/shared/CandyData.luau` | the 13 foods |
| `src/shared/IslandConfig.luau` | slot → quest / host model / food (content wiring) |
| `src/shared/Constants.luau` | starting coins / tier / power / island |
| `src/client/PropelSystem_AllInOne.client.lua` | flight loop, prepay, coin ticks, descent settle |
| `src/server/FlightEconomy.server.luau` | leaderstats, CoinEvent bound, tank sync, anti-strand, progress |
| `src/server/StomachUpgrade.server.luau` | gut purchase (upgrade + island gate + price) |
| `src/server/BuyFood.server.luau` | food purchase (ceiling lock, coins first, exact-cap fill) |
| `src/server/GutProgression.server.luau` | publishes `UnlockedSlot` from the quest ledger |
| `tools/ladder.py` | the progression harness |
