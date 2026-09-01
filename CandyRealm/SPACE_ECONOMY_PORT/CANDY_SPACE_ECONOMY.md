> # ⚠ SUPERSEDED — DO NOT TUNE FROM THIS FOLDER
>
> On 2026-09-01 the Candy Realm was re-ported onto the **FOOD REALM's** progression model (the first
> realm: wall/stretch gut pairs, coins per stud travelled, guts bought with coins and gated by island
> reached, no flight ceiling). Everything in this folder describes the Space Realm port that replaced
> the Dino solve and has itself now been replaced. The live spec is
> `CANDY_ISLAND_SPACING_AND_ECONOMY.md`; the authority is the code under `src/shared/` and
> `python tools/ladder.py`. Kept only as the record of what the tower used to be.

# Candy Realm — Space Realm Economy Port (12 islands)

A complete copy of the Space Realm's coins-earned / spacing / progression system, re-solved
for the Candy Realm's twelve-island tower.

**Slots 1–8 are the Space Realm's numbers verbatim.** Slots 9–12 continue every one of its
curves by the same rule. Nothing here is a candy invention — where a number is new, the rule
that produced it is stated.

Files in this folder are drop-in replacements for `CandyRealm/src/shared/…` and
`CandyRealm/src/server/…`:

| File | Replaces | What it owns |
|---|---|---|
| `IslandOrder.luau` | `src/shared/IslandOrder.luau` | slot order, positions, gaps, names |
| `StomachTiers.luau` | `src/shared/StomachTiers.luau` | the 12 guts, the ladder, the hard ceiling |
| `CandyData.luau` | `src/shared/CandyData.luau` | food price/power per slot |
| `IslandConfig.luau` | *(new — candy had no `PlanetConfig`)* | per-island quest → gut mapping |
| `FlightTuning.luau` | `src/shared/FlightTuning.luau` | the flight model (**different model, not a retune**) |
| `FlightPayout.luau` | `src/client/PropelSystem…` `COIN_PER_STUD` | the income model |
| `Economy.luau` | `src/server/BuyFood` + `StomachUpgrade` | the two purses |
| `Constants.luau` | merge into `src/shared/Constants.luau` | starting state, ceiling margins |

---

## 1. What actually changes

The old candy economy is the Dino Realm's solve. It is a *different design*, not a
differently-tuned one. Five things invert:

| | Old (dino/candy) | New (space) |
|---|---|---|
| **What gates progress** | tank **reach** — no gut climbs the gap above its own | a **hard ceiling** at your island + 400 studs |
| **What coins are paid for** | **studs climbed** (`COIN_PER_STUD = 0.14`) | **power burned** (`powerBurned × payoutPerPower`) |
| **Who pays for a gut** | flight surplus — one purse | the island's **quest**, paying exactly the gut's cost — two purses |
| **How gaps grow** | ×1.12 per crossing (must exceed ×1.08 or guts go optional) | flat **+200 second difference** |
| **How a bigger tank goes further** | it flies **faster** (45 s for every gut) | it flies **longer** (`tankSeconds` 28 → 98) |

The consequence that matters: **in the old model, "how many tries an island takes" was set by
how long you were willing to grind.** Guts came out of flight surplus, so a patient player
bought their way up. In the space model the wall is structural — the ceiling does not move
until the quest that funds the next gut is done, and no amount of coins moves it.

---

## 2. Island spacing — the 12-slot tower

### The rule

The Space Realm's gaps have a **constant second difference of +200**. That is the entire
spacing law, and extending to twelve islands meant only continuing it:

```
gaps      1400  2000  2800  3800  5000  6400  8000 | 9800 11800 14000 16400
1st diff      600   800  1000  1200  1400  1600 |1800  2000  2200  2400
2nd diff          200   200   200   200   200 | 200   200   200   200
                                     space ^^^^ | ^^^^ new
```

### The ladder

| Slot | Model | Name | Y | Gap above | Quest content |
|---|---|---|---|---|---|
| 1 | island1 | Candy Cane Court | 220 | 1,400 | tutorial, garden, gumball hunt |
| 2 | island9 | Gumdrop Grove | 1,620 | 2,000 | reactor cleanup |
| 3 | island3 | Cookie Crumble | 3,620 | 2,800 | cookie repair, chocolate monster |
| 4 | island13 | Gumtree Park | 6,420 | 3,800 | the Forgotten Park / ancient tree |
| 5 | island5 | Taffy Town | 10,220 | 5,000 | taffy storm |
| 6 | island8 | Crystal Candy Caves | 15,220 | 6,400 | crystal mine |
| 7 | island2 | Chocolate Chasm | 21,620 | 8,000 | ⚠️ **no quest built** |
| 8 | island12 | Sherbet Shelf | 29,620 | 9,800 | ⚠️ **island not built, no quest** |
| 9 | island11 | Licorice Tunnels | 39,420 | 11,800 | tunnel blast |
| 10 | island4 | Frostbell Peak | 51,220 | 14,000 | campfire freeze, summit bell |
| 11 | island14 | Marshmallow Camp | 65,220 | 16,400 | camp s'mores |
| 12 | island15 | Bakery Summit | 81,620 | — | the Great Bake-Off (finale) |

Slots 1–8 are the Space Realm's `PLANET_Y` exactly (Mercury 220 → Neptune 29,620).

X/Z keep the candy zig-zag: alternate sign, magnitude growing 20 studs per step. The summit
at 81,620 stays well under ~100k, where float precision starts to jitter parts.

**Two pins kept:** `island1` at slot 1 (spawn + tutorial live there), `island15` at slot 12
(the Bake-Off is the finale).

---

## 3. The guts — 12 tiers, one per island

### How capacity was derived

A full tank climbs `maxPower × 2.16` studs (`STUDS_PER_POWER`, measured on the space flight
model), and each tier exists to make **one** hop. The space rule is that every tank clears its
gap by the **same ~18% margin**:

```
maxPower = ceil10( gap × 1.18 / 2.16 )
```

That formula reproduces all seven Space Realm capacities **exactly** and generates the four
new ones. The uniform margin is the point — the pre-tuning space numbers cleared their gaps by
anywhere from 2.6% to 48%, which made tier 3 a trap (any gas spent steering left you short of
the island you had just bought the correct gut for) while tier 8's surplus bought nothing.

### The table

| Tier | Name | maxPower | cost | tankSec | Clears gap | Margin |
|---|---|---|---|---|---|---|
| 1 | Gumdrop Belly | **0** | 0 | 28 | — (grounded gate) | — |
| 2 | Taffy Tummy | 770 | 450 | 28 | 1,400 | +18.8% |
| 3 | Cookie Gut | 1,100 | 750 | 30 | 2,000 | +18.8% |
| 4 | Jelly Belly | 1,530 | 1,200 | 34 | 2,800 | +18.0% |
| 5 | Gummy Gut | 2,080 | 1,750 | 38 | 3,800 | +18.2% |
| 6 | Choco Stomach | 2,740 | 2,400 | 44 | 5,000 | +18.4% |
| 7 | Caramel Core | 3,500 | 3,100 | 50 | 6,400 | +18.1% |
| 8 | Marshmallow Middle | 4,380 | 3,950 | 58 | 8,000 | +18.3% |
| 9 | Fudge Furnace | **5,360** | **4,900** | **66** | 9,800 | +18.1% |
| 10 | Licorice Loop | **6,450** | **5,950** | **76** | 11,800 | +18.1% |
| 11 | Peppermint Pit | **7,650** | **7,150** | **86** | 14,000 | +18.0% |
| 12 | Nougat Nova | **8,960** | **8,450** | **98** | 16,400 | +18.0% |

Bold = new. Tiers 2–8 are the Space Realm's `SPACE_STOMACHS` verbatim.

- **`maxPower`** — the formula above.
- **`cost`** — continues `cost/maxPower`, which climbs 0.584 → 0.902 across the space tiers,
  by +0.01 per new rung (0.914 → 0.943). Step ratios stay smooth: 1.241, 1.214, 1.202, 1.182.
- **`tankSeconds`** — continues the +2-seconds-every-two-rungs cadence.

### Tier 1 has maxPower = 0 on purpose

It is a **grounded gate**. A fresh player cannot fly, and so cannot farm flight coins, until
the first island's quest grants tier 2. Remove it and flight money can buy a gut, which
collapses the two-purse design in section 5.

---

## 4. The wall is the ceiling, not the reach

This is the biggest single change, and the reason the gap-growth constraint disappears.

```lua
getMaxHeight(state) = ISLAND_LADDER[yourTier].y + 400
getCeilingLid(state) = ISLAND_LADDER[yourTier + 1].y - 250
```

Your ceiling is **your island + 400 studs**. The next island sits a full gap beyond it, so it
is unreachable no matter how much power you carry — gas bubbles, a 2× Power pass, a mid-air
refuel, none of it matters. `getCeilingLid` is the never-exceed clamp for events that *scale*
the ceiling, so a Sugar Rush ×1.5 can never quietly mean "skip a gut".

Every rung audited at boot — reaches its own island, never the next:

| Tier | Ceiling | Own island | Next island | Lid |
|---|---|---|---|---|
| 1 | 620 | 220 | 1,620 | 1,370 |
| 2 | 2,020 | 1,620 | 3,620 | 3,370 |
| 3 | 4,020 | 3,620 | 6,420 | 6,170 |
| 4 | 6,820 | 6,420 | 10,220 | 9,970 |
| 5 | 10,620 | 10,220 | 15,220 | 14,970 |
| 6 | 15,620 | 15,220 | 21,620 | 21,370 |
| 7 | 22,020 | 21,620 | 29,620 | 29,370 |
| 8 | 30,020 | 29,620 | 39,420 | 39,170 |
| 9 | 39,820 | 39,420 | 51,220 | 50,970 |
| 10 | 51,620 | 51,220 | 65,220 | 64,970 |
| 11 | 65,620 | 65,220 | 81,620 | 81,370 |
| 12 | 82,020 | 81,620 | — | ∞ |

### Reach is deliberately generous — don't "fix" it

`STUDS_PER_POWER = 2.16` is a **conservative floor** used only for the boot warning. The
actual band model delivers more:

| Tier | Band-model climb | Gap | Real margin |
|---|---|---|---|
| 2 | 2,369 | 1,400 | +69% |
| 5 | 4,536 | 3,800 | +19% |
| 8 | 10,930 | 8,000 | +37% |
| 12 | 23,054 | 16,400 | +41% |

This over-reach is inherited from the Space Realm and is harmless **because reach is not the
wall.** You can carry a tank that could physically climb three islands and still be stopped
dead at your own island + 400. The margin is what stops a player who bought exactly the right
gut from being stranded by a low takeoff or gas spent steering.

---

## 5. Coins earned — the income model

```
coins per flight = floor(powerBurned × payoutPerPower)
```

`powerBurned` is the **food power spent during the flight** — *not* how high you climbed.

### Why power, not altitude

The old candy model paid `COIN_PER_STUD = 0.14` per stud of altitude gained. That pays for
*flying well*: two players who buy the same food and burn the same tank get different money
because one steered straighter, and a player who bounces off the ceiling burning fuel gets
nothing. Paying per power burned makes income a function of what you **spent**, so a clean
flight and a clumsy one on the same tank pay the same. Skill decides whether you *arrive*, not
whether you can afford the next tank.

It also makes the hard ceiling safe. Under a per-stud model the ceiling would cap your income
too, so the last stretch of every island would pay nothing.

### The rate, by the island you're flying from

| Slot | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `payoutPerPower` | 1.9 | 2.3 | 2.9 | 3.7 | 4.8 | 6.1 | 7.8 | **9.9** | **12.6** | **16.0** | **20.3** | **20.3** |

Slots 1–7 are the Space Realm's rates verbatim; 8–11 continue its ~×1.27 per-rung growth.
Slot 12 is the summit — no flight onward is needed, so like Neptune it **mirrors** the rate
below rather than being zero, in case the player still flies there.

### The two purses

| Purse | Source | Spends on |
|---|---|---|
| **Quest money** | finishing an island's quest pays **exactly** the cost of the gut it unlocks | the gut — and the buy is quest-gated |
| **Flight money** | `powerBurned × payoutPerPower` | food, and only food |

`Economy.BuyGut` enforces all three: next-tier-only, **quest completed**, can-afford. A player
who farms flights all day still cannot buy the next gut.

`Economy.PayForNextGut` pays only when the player does **not** already own the tier. The summit
names the same capstone tier as the island below it (there is no tier 13), so without that check
finishing the Bake-Off would hand out another 8,450 coins for a gut already bought.

---

## 6. Food — price and power per slot

### Power is a fixed fraction of the tank it fills

You arrive on slot *k* with tier *k*, finish the quest, buy tier *k+1*, then buy food **here**
and fly. So **slot *k*'s food fills tier *k+1*'s tank.** The Space Realm ramps that fraction
11.0% → 17.9% across its seven crossings; this continues the same +1.1-points-per-rung slope
out to 22.3%.

### Price is solved from R, not picked

```
R = (power × payoutPerPower) / price     ← what a serving earns ÷ what it costs
```

**R is the only number that matters.** It must stay above 1 at every slot or a flight costs
more than it earns and the player spirals down. The Space Realm's R runs 1.47 → 1.35 → 1.75,
**plateauing at 1.749** for its top two islands. Slots 1–7 below are its exact prices; slots
8–12 are solved to hold that plateau:

```
price = power × payoutPerPower / 1.749
```

### The table

| Slot | Food | Host | power | price | % of tank | price/power | R |
|---|---|---|---|---|---|---|---|
| 1 | Candy Canes | island1 | 85 | 110 | 11.0% | 1.294 | 1.468 |
| 2 | Gumdrops | island9 | 135 | 230 | 12.3% | 1.704 | 1.350 |
| 3 | Cookies | island3 | 200 | 430 | 13.1% | 2.150 | 1.349 |
| 4 | Jelly Beans | island13 | 285 | 760 | 13.7% | 2.667 | 1.388 |
| 5 | Taffy | island5 | 415 | 1,300 | 15.1% | 3.133 | 1.532 |
| 6 | Gummy Bears | island8 | 570 | 2,150 | 16.3% | 3.772 | 1.617 |
| 7 | Chocolate Bars | island2 | 785 | 3,500 | 17.9% | 4.459 | 1.749 |
| 8 | **Sherbet Scoops** | island12 | **1,020** | **5,770** | 19.0% | 5.657 | 1.750 |
| 9 | Rock Candy | island11 | **1,300** | **9,365** | 20.2% | 7.204 | 1.749 |
| 10 | Marshmallows | island4 | **1,625** | **14,860** | 21.2% | 9.145 | 1.750 |
| 11 | Caramel Apples | island14 | **2,000** | **23,210** | 22.3% | 11.605 | 1.749 |
| 12 | Sundaes | island15 | **2,000** | **23,210** | — (summit) | 11.605 | 1.749 |

Because R > 1 everywhere, **prices cannot set the try count** — a solvent economy gives
one-pass islands by construction. The only thing that makes an island take several tries is
the wall in section 4.

### Servings to fill a tank

| Slot | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| servings | 9.1 | 8.2 | 7.7 | 7.3 | 6.6 | 6.1 | 5.6 | 5.3 | 5.0 | 4.7 | 4.5 |

Refuelling stays a multi-purchase ritual the whole way up; it just gets less repetitive.

### One drift worth knowing about

The cost of a full tank grows faster than the cost of a gut, because a fill compounds
(price × servings) while gut cost tracks capacity roughly linearly. Fill-cost ÷ gut-cost runs
2.4 at slot 1 → 5.3 at slot 7 → 13.7 at slot 11.

**This is the space curve's own behaviour continued, and it is harmless here** — the gut is
quest-funded, so gut affordability was never the wall. If you ever move guts back onto flight
surplus, this drift becomes a real problem and the cost curve needs re-solving.

---

## 7. The flight model (this is a replacement, not a retune)

```
gas       = RAW power, 0 .. maxPower          (NOT normalised)
drainRaw  = maxPower / tankSeconds            per second
each frame: gas -= drainRaw × dt
riseSpeed = riseSpeedFor(gas)                 bands, by CURRENT raw power
BodyVelocity.Y = riseSpeed
```

A full tank lasts exactly that tier's `tankSeconds`, and the band lookup reads the power that
is **draining** — a flight starts in the top band its gut can reach and steps down through
every band beneath it as the tank empties. That taper is the mechanic.

**One fixed band table, shared by every tier.** The thresholds are *not* tier capacities and
must not be re-derived from them:

| Power ≤ | 100 | 182 | 611 | 1,075 | 2,146 | 3,218 | ∞ |
|---|---|---|---|---|---|---|---|
| studs/sec | 40 | 62 | 84 | 126 | 144 | 226 | 280 |

Plus `INFINITE_RISE_SPEED = 350` (Sugar Rush), `HORIZONTAL_SPEED = 48`.

The old model's band speeds were a fragile simultaneous solve — hand-edit one row and every
tier above it silently broke. Here speed comes from one shared table and a bigger tank simply
burns longer, so a tier can be retuned on its own. The twelve-island extension needed **no new
bands**: the top band already covers every tank above 3,218, and the extra distance comes
entirely from `tankSeconds`.

---

## 8. Starting state

| | Value | Why |
|---|---|---|
| `STARTING_STOMACH_TIER` | 1 | maxPower 0 — the grounded gate |
| `STARTING_COINS` | 150 | enough for ~1 slot-1 food (110) to start the loop |
| `STARTING_POWER` | 0 | empty tank; you buy your first food |
| `CEILING_MARGIN` | 400 | headroom to fly around your island and land |
| `LID_CLEARANCE` | 250 | how far the next island stays out of reach under a buff |

`CEILING_MARGIN + LID_CLEARANCE = 650`, against a smallest gap of 1,400 — comfortable.

---

## 9. The loop, end to end

1. Land on slot *k* with gut tier *k*.
2. Finish slot *k*'s quest → **+cost(tier k+1) coins**, and the buy unlocks.
3. Buy gut *k+1* from the GUT panel — quest-gated, so flight coins can't skip it.
4. Buy food at stand *k* (R ≈ 1.35–1.75, so flying is always solvent), fly, earn
   `power × payoutPerPower` on landing.
5. The hard ceiling lifts to slot *k+1*. Go.

---

## 10. Blockers before this ships

1. **`island12` does not exist.** The world has eleven island models — 1, 2, 3, 4, 5, 8, 9,
   11, 13, 14, 15 (6, 7, 10, 12 were never built). A twelve-slot tower needs one more, and
   this port names **`island12` as the new slot 8**. Building 6, 7 or 10 instead is fine —
   change the one number in `SLOT_TO_ISLAND` **and** the matching `island` field in
   `CandyData.FOODS`, together.

2. **Two islands have no quest.** Slot 7 (Chocolate Chasm / island2) never had one, and slot 8
   is brand new. Both carry `TODO` placeholders in `IslandConfig.luau`. **Until they have real
   quests the ladder dead-ends at slot 7** — tier 8 never gets funded, so the ceiling never
   lifts past 21,620.

3. **Old call sites still speak the old model.** `PropelSystem_AllInOne.client.lua` pays
   `COIN_PER_STUD` and normalises the meter; `StomachUpgrade.server.luau` gates on
   `unlockSlot` rather than quest completion; `FlightEconomy.server.luau` has its own
   anti-strand logic that assumes reach is the wall. All three need rewiring to the new
   modules — the data tables alone won't change behaviour.

4. **`PlayerState` needs per-island quest state.** `Economy.BuyGut` looks for
   `PlayerState.get<IslandName>QuestState(player)` returning `"COMPLETED"`. That accessor
   pattern is the Space Realm's; candy's `PlayerState` will need the equivalent.

### If you ship 11 islands instead of 12

The solve is bottom-up, so truncating is exact rather than approximate: **delete the last row
of every table** (slot 12 / tier 12 / the `Sundaes` row / the trailing `20.3`) and move the
Bake-Off to slot 11. Every remaining number is unchanged. Do *not* delete a middle row — that
renumbers every rung above it.
