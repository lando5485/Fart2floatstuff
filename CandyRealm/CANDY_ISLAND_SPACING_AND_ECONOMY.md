# Candy Realm — Island Spacing & Full Economy

Ported from the Dino Realm's solved economy (`DINO_ISLAND_SPACING_AND_ECONOMY.md`) and
**re-solved for eleven islands / ten crossings**. Same model, same five constants, fewer rungs.

Source of truth, all under `CandyRealm/`:
- `src/shared/IslandOrder.luau` — slot order, positions, display names
- `src/shared/FlightTuning.luau` — flight seconds, drain, band speeds, margins
- `src/shared/StomachTiers.luau` — gut tiers (prices, sizes, unlock slots)
- `src/shared/CandyData.luau` — food prices/power per climb slot
- `src/client/PropelSystem_AllInOne.client.lua` — flight loop + coins-per-stud
- `src/server/FlightEconomy.server.luau` — starting coins, coin accumulation, anti-strand, progress
- `src/server/IslandLayout.server.luau` — moves the islands into the tower at startup
- `src/server/StomachUpgrade.server.luau` / `src/server/BuyFood.server.luau` — purchases

NOTE: the root `CLAUDE.md` describes the FIRST realm (Bean Farm → Pizza Palms, 14 islands,
coins on absolute height). This document is the CANDY REALM's own system, different in
almost every number.

---

## 1. Island spacing — the 11-slot tower

Eleven islands, one vertical zig-zag tower. **Slot** = climb position (1 = bottom,
11 = summit).

**The model numbers are not contiguous.** The world has eleven island models —
**1, 2, 3, 4, 5, 8, 9, 11, 13, 14, 15** — with 6, 7, 10 and 12 never built. Anything that
loops `for i = 1, 11` over Workspace misses the top three islands and warns about three
that don't exist; iterate `SLOT_TO_ISLAND` instead.

**Slot order is SCRAMBLED against model number** (`IslandOrder.SLOT_TO_ISLAND =
{1, 9, 3, 13, 5, 8, 2, 11, 4, 14, 15}`), so the tower doesn't read as "1, 2, 3…" going up.
Two pins are deliberate: `island1` at slot 1 (spawn + tutorial live there) and `island15`
at slot 11 (the Bake-Off is the finale).

| Slot | Model | Name | Quest content | X | Y | Z | Gap to next |
|------|-------|------|---------------|----|------|------|-------------|
| 1 | island1 | Candy Cane Court | tutorial, garden, gumball hunt | 0 | 150 | 0 | 3,375 |
| 2 | island9 | Gumdrop Grove | reactor cleanup | 120 | 3,525 | 60 | 3,780 |
| 3 | island3 | Cookie Crumble | cookie repair, chocolate monster | -160 | 7,305 | 100 | 4,234 |
| 4 | island13 | Gumtree Park | the Forgotten Park / ancient tree | 180 | 11,539 | -120 | 4,742 |
| 5 | island5 | Taffy Town | taffy storm | -200 | 16,281 | 160 | 5,311 |
| 6 | island8 | Crystal Candy Caves | crystal mine | 220 | 21,592 | -180 | 5,949 |
| 7 | island2 | Chocolate Chasm | — | -240 | 27,541 | 200 | 6,663 |
| 8 | island11 | Licorice Tunnels | tunnel blast | 260 | 34,204 | -220 | 7,463 |
| 9 | island4 | Frostbell Peak | campfire freeze, summit bell | -280 | 41,667 | 240 | 8,359 |
| 10 | island14 | Marshmallow Camp | camp s'mores | 300 | 50,026 | -260 | 9,362 |
| 11 | island15 | Bakery Summit | the Great Bake-Off (finale) | -320 | 59,388 | 280 | — (summit) |

### The spacing rules (why these numbers)

- **X and Z zig-zag**: alternate sign every slot, magnitude grows 20 studs per step.
- **Y gaps grow 12% per crossing**: 3,375 → 9,362, ten gaps for ten crossings.
  **12% is load-bearing**: a full tank climbs its own gap × MARGIN (1.08), so a gut is
  locked out of the NEXT gap only if gaps grow by MORE than 8%.
- **One gap per gut tier, 1:1.** Ten gut tiers, ten gaps. A gut is the wall that forces
  saving; with fewer guts than crossings, some islands are free by construction.
- **No gut reaches the gap above its own** — verified, every row:

  | tank | climbs | own gap | next gap |
  |------|--------|---------|----------|
  | 110 | 3,645 | 3,375 | 3,780 |
  | 150 | 4,053 | 3,780 | 4,234 |
  | 200 | 4,526 | 4,234 | 4,742 |
  | 270 | 5,066 | 4,742 | 5,311 |
  | 365 | 5,678 | 5,311 | 5,949 |
  | 495 | 6,368 | 5,949 | 6,663 |
  | 675 | 7,143 | 6,663 | 7,463 |
  | 920 | 8,012 | 7,463 | 8,359 |
  | 1,260 | 8,985 | 8,359 | 9,362 |
  | 1,725 | 10,074 | 9,362 | — (summit) |

- Summit at 59,388 keeps well clear of ~100k+ where float precision jitters parts, with
  headroom to extend if more islands get built.

At startup `IslandLayout.server.luau` `PivotTo()`s each island model to its slot position
(rotation preserved, children come along), then sets `_G.islandsPositioned`.

### The slot/model split is the whole contract

`CandyData.FOODS` is ordered by **slot** and each row's prices/power are solved for the gap
and tank size at that slot — but each row's `island` field names the model that **hosts**
the stand. Move an island in `SLOT_TO_ISLAND` without moving that field and the stand
travels with the model, putting a slot-8 food (power 240) on slot 3. Change both, or neither.

Same rule for code: **compare SLOTS, never model numbers.** `island7` is slot 2, so
`islandNum > best` logic silently stalls progression. Fixed in `FlightEconomy` (progress),
`Shop_AllInOne` (unlock gate, BUY MAX, featured food) and `RebirthSystem` (summit gate).

---

## 2. Starting state (new player)

From `FlightEconomy.server.luau` / `StomachUpgrade.server.luau` (same defaults in both, so
creation order doesn't matter):

```lua
Coins        = 120   -- starting coins
CurrentPower = 0     -- current fart fuel in the tank
StomachMax   = 110   -- tank size (Gumdrop Belly tier)
Island       = 1     -- the CLIMB SLOT, not a model number
```

---

## 3. Coins earned while flying

**0.14 coins per stud CLIMBED**, paid every 0.5s of thrust, billed on the DELTA from launch
altitude. Paid only WHILE THRUSTING — the fall pays 0. One final flush on flight end.
`_G.serverEventCoinMult` scales it (1 normally).

The client sends fractional amounts; `FlightEconomy` accumulates and only moves whole coins
into stats (otherwise sub-1.0 payouts floor to 0).

**Earning intuition:** a full-tank flight climbs `gap × 1.08`, earning `gap × 1.08 × 0.14` —
slot 1→2 ≈ **510 coins**, slot 10→11 ≈ **1,416 coins**.

---

## 4. Flight model

```lua
FLIGHT_SECONDS = 45              -- a full tank = 45 s of thrust, for EVERY gut
MARGIN         = 1.08
DRAIN_RATE     = 100 / 45        -- ≈ 2.222 gas/sec on the 0–100 meter
gasMeter     -= DRAIN_RATE * dt
currentPower  = (gasMeter / 100) * stomachMax
riseSpeed     = getFlightSpeed(currentPower)   -- band lookup on the DRAINING power
```

The band is read from the DRAINING power, so a flight starts in the top band its gut reaches
and steps DOWN through every band beneath it — the speed taper is the mechanic.

### Band speeds — solved, not guessed

| Tier | Gut | maxPower | Gap it opens | Rise speed |
|------|-----|----------|--------------|------------|
| 1 | Gumdrop Belly | 110 | 3,375 (1→2) | 81.0 |
| 2 | Taffy Tummy | 150 | 3,780 (2→3) | 115.0 |
| 3 | Cookie Gut | 200 | 4,234 (3→4) | 132.1 |
| 4 | Jelly Belly | 270 | 4,742 (4→5) | 146.9 |
| 5 | Gummy Gut | 365 | 5,311 (5→6) | 164.8 |
| 6 | Choco Stomach | 495 | 5,949 (6→7) | 184.6 |
| 7 | Caramel Core | 675 | 6,663 (7→8) | 206.1 |
| 8 | Marshmallow Middle | 920 | 7,463 (8→9) | 231.2 |
| 9 | Fudge Furnace | 1,260 | 8,359 (9→10) | 258.2 |
| 10 | Licorice Loop | 1,725 | 9,362 (10→11) | 289.4 |
| — | Sugar Rush Gut (Robux) | ∞ | notional | 420.0 |

The speeds are the unique solution to "every full tank climbs its own gap × 1.08" given the
taper integral: a gut of size M spends `45 × (M_j − M_j-1) / M` seconds in band j, total
climb = `(45 / M) × Σ v_j × (M_j − M_j-1)`. This is the Dino solve **truncated at tier 10**,
which is exact rather than approximate — the system is triangular and solves bottom-up, so
dropping the top rows leaves every remaining speed untouched. **Hand-editing one row
silently breaks every tier above it** — re-solve instead.

Tanks carry +10 over the solved 100/140/190/260/355/485/665/910/1250/1715 sizes — capacity
only; effective margin lands at ~1.072 instead of 1.080 and every crossing still clears.

---

## 5. Gut tiers

**Ten coin tiers, one per crossing**, plus a Robux one. `unlockSlot` = the climb slot you
must have REACHED before it can be bought (server-enforced anti-skip).

| # | Name | maxPower | Cost | unlockSlot |
|---|------|----------|------|------------|
| 1 | Gumdrop Belly | 110 | 0 (default) | 1 |
| 2 | Taffy Tummy | 150 | 1,250 | 2 |
| 3 | Cookie Gut | 200 | 1,400 | 3 |
| 4 | Jelly Belly | 270 | 1,550 | 4 |
| 5 | Gummy Gut | 365 | 1,750 | 5 |
| 6 | Choco Stomach | 495 | 1,950 | 6 |
| 7 | Caramel Core | 675 | 2,200 | 7 |
| 8 | Marshmallow Middle | 920 | 2,450 | 8 |
| 9 | Fudge Furnace | 1,260 | 2,750 | 9 |
| 10 | Licorice Loop | 1,725 | 3,050 | 10 |
| — | Sugar Rush Gut | 9,999 | **499 Robux** | not gated |

**Prices are 4.25 flights of surplus at the tier below** — the sole "3–5 tries per island"
dial. A gut costing 4.25× a flight's surplus takes ~4 flights to save for; at 45 s per
flight each island lands at ~3.0 minutes.

The client fires `BuyStomachEvent:FireServer(tierName)` (a string); the server reads the
PRICE off its own shared table, validates `unlockSlot` against `HighestSlot`, enforces
strict-upgrade-only, deducts coins, and gives the new gut a **courtesy fill**: enough power
to cross the gap actually in front of the player × 1.10, never more than the tank.

---

## 6. Food

Ordered by **climb slot**. One stand per island.

| Slot | Food | Price | Power | Host model | R |
|------|------|-------|-------|-----------|---|
| 1 | Candy Canes | 21 | 8 | island1 | 1.94 |
| 2 | Gumdrops | 53 | 25 | island9 | 1.93 |
| 3 | Cookies | 79 | 45 | island3 | 1.92 |
| 4 | Jelly Beans | 101 | 70 | island13 | 1.91 |
| 5 | Taffy | 118 | 100 | island5 | 1.92 |
| 6 | Gummy Bears | 136 | 140 | island8 | 1.91 |
| 7 | Chocolate Bars | 147 | 185 | island2 | 1.91 |
| 8 | Rock Candy | 156 | 240 | island11 | 1.91 |
| 9 | Marshmallows | 159 | 300 | island4 | 1.91 |
| 10 | Caramel Apples | 160 | 370 | island14 | 1.91 |
| 11 | Sundaes | 194 | 450 | island15 | 1.92 |

**Prices are DERIVED, not picked:**

```
R = (coins a full flight earns) / (coins a full refill costs) = 1.91
price = gap × MARGIN × COIN_PER_STUD / (R × (tierMaxPower / power))
```

The summit row has no gap above it, so it is priced against the last crossing and the top tier.

- **R must stay above 1 at every row** or a flight costs more than it earns and the player
  spirals down. That, not the price, is the number to protect.
- **R > 1 means prices CANNOT set the try count** — a solvent economy gives one-pass islands
  by construction. The only thing that makes an island take several tries is a WALL: a gut
  you can't yet afford.
- `COIN_PER_STUD` (0.14) is the other half of R. Change one, re-solve both.

Buy rules (`BuyFood.server.luau`): reached-slot gate → `"food_locked"`; coins checked FIRST
→ `"not_enough_coins"`; then room (landing EXACTLY on the cap allowed) → `"stomach_full"` /
`"not_enough_room"`. Coins never deducted on a rejected buy.

---

## 7. Anti-strand top-up

When a flight ends with the tank at ZERO (`BurnFuelEvent` reports 0), the server grants the
coin SHORTFALL for a **quarter tank** of the food on the slot the player reached:

- A quarter tank, never the whole crossing — funding the crossing caps every island at 2 attempts.
- Grants COINS, never fuel — the player still walks to the stand and buys.
- A quarter tank always compounds back to full because R > 1 at every row.

---

## 8. Progress tracking

`FlightEconomy.server.luau` runs a 0.5s tracker that, when a player **stands on** a new
island, sets `HighestSlot` (the climb position — **what every gate reads**),
`HighestIsland` (the model number) and `leaderstats.Island` (the slot).

The check is **grounded + full 3D distance** (700-stud radius, or inside the bounding box).
An XZ-only check is a known dino-realm bug: the tower is ~59k studs of Y across ±320 of X/Z,
so ignoring Y makes "nearest island" arbitrary and `HighestSlot` runs away within a minute
of the first launch — unlocking every high-tier food and collapsing multi-attempt crossings
into one pass. Players with `IntroPlaying` are skipped so cinematics don't bank progress.

---

## 9. Verification

`tools/verify_economy.py` (run: `python tools/verify_economy.py`) re-runs every invariant:
slot map is a permutation, gaps grow 12%,
`TIERS` gaps match `SLOT_POS`, each gut clears its own gap and falls short of the next, and
R stays in [1.90, 1.95] at every food row. All pass as of this writing. **Re-run it after
any retune** — nothing errors when these drift apart.

---

## Change discipline

`IslandOrder.SLOT_POS` (gaps), `FlightTuning.TIERS` (band speeds), `CandyData.FOODS`
(prices/power) and `StomachTiers.LIST` (gut costs) are **one interlocked set**, all solved
from `FLIGHT_SECONDS = 45`, `MARGIN = 1.08`, `COIN_PER_STUD = 0.14`, `R = 1.91`, and 12% gap
growth. Retune together or not at all — nothing errors when they drift apart; islands just
silently become free or unwinnable.

### Adding islands later

The tower is sized for eleven. To extend: add the model, append its number to
`SLOT_TO_ISLAND`, append the next position (`Y += lastGap × 1.12`, X/Z zig-zag +20), append
a gut tier and a food row, and re-solve the band speeds. The Dino Realm's tiers 11 and 12
(2360/3450 and 3230/3850, speeds 324.4 and 363.4, gaps 10485 and 11743) are the next two
rungs if you go to thirteen islands.
