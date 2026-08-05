# Pickup Time System — Candy Realm

How long a collectible takes to earn in Candy Realm, and how that length is *enforced*
rather than tuned. All numbers below are read from `CandyRealm/src/client/*_AllInOne.client.lua`.

## The rule

No collectible is ever handed over on a single prompt trigger. Every pickup takes a
minimum of 15 seconds, via a modal minigame themed to that island's environment.

Rationale: the island quests are the pacing backbone of a 65–70 min playtime target, and a
free E-tap collapses an island's quest into a few seconds of walking.

Two supporting rules:

- Every quest gets a DISTINCT mechanic. See the inventory below for what Candy Realm has
  already spent — don't repeat those.
- The payoff stays instant. The cookie cinematic, the campfire ignite, the bake DING, the
  gumball crank — don't pad those. Lengthen the work, never the reward.

## Mechanics already spent in Candy Realm

Don't reuse a verb from this list for a new quest.

| Quest | Island | Verb |
|---|---|---|
| CandyGumball | 1 | walk-over orb collect + finale crank |
| CookieRepair | 3 | tap-E chunk collect |
| JellyTower | 4 | bounce platforming to a flag |
| CampfireFreeze | 4 | carry-and-place against a countdown meter |
| SummitBell | 4 | climb + repair broken stairs through a blizzard cycle |
| TaffyStorm | 5 | cap an anchor / reel a kite / catch falling candy in a basket |
| CrystalMine | 8 | click-swing pickaxe, N hits per crystal |
| TunnelBlast | 11 | carry crates to a blast X, mine ore, deposit at a cart |
| AncientTree | 13 | hold-the-wrench pipe seal; hold-to-crank gate with slip-back |
| CampSmores | 14 | axe swings per tree, mill logs, pick regrowing mushrooms |
| Bakery | 15 | tap-to-stir; oven heat sweet-zone hold |
| CandyDelivery | — | hold-E tree shake; 3-step conveyor |
| RadioactiveCleanup | — | crane slew / hoist / grab / release |
| ChocolateMonster | — | tap-E shove |

## How to actually enforce the floor

Tuning a mechanic "to feel like 15s" does NOT work — players mash, and anything bar-based
gets beaten in 3 seconds. Pick the pattern that matches the mechanic's input style.

### 1. Rising ceiling — any bar-fill mechanic (the best one)

A ceiling value rises from the bar's start position to 1.0 over exactly N seconds; clamp
the bar to it every frame and on every input. The player can never finish early no matter
how fast they input; going slower than the ceiling still costs them extra time. Exact,
invisible, un-gameable.

```lua
local ceiling  = startFill
local ceilRate = (1 - startFill) / SECONDS
-- each frame:  ceiling = math.min(1, ceiling + ceilRate*dt);  fill = math.min(fill, ceiling)
-- on input:    fill = math.min(fill + gain, ceiling)
```

Nothing in Candy Realm uses this yet. It is the right fix for the Bakery stir bar and for
any new bar-shaped minigame.

### 2. Forced cadence — tap-per-action mechanics

Disable the prompt/button for a cooldown after each action, so N actions × cooldown IS the
floor and extra presses do nothing. Re-enable behind the same guard the activation code
uses, or a finished or abandoned object will re-arm itself.

Candy Realm already does this with `HoldDuration` rather than a cooldown, which works the
same way — the hold *is* the cadence:

- `AncientTreeQuest` — `PIPE_HOLD = 0.3` × `PIPE_TURNS = 4` per pipe × `PIPE_COUNT = 4`
  pipes, plus the walk between them. The file budgets this at ~20s.
- `CandyDeliveryQuest` — `SHAKE_TIME = 1.1` hold-E per tree shake.

### 3. Requirement escalation — discrete hit-count mechanics

If the player completes the requirement before the floor, don't finish — bump the
requirement by one and say why ("Still cracked — one more swing!"). Keeps player agency
instead of freezing the UI.

### 4. Natural rate limit

If the mechanic already self-paces, you only need to tune the gain rate. Verify by
hand-computing the optimal loop, and also the degenerate loop (holding through every
failure) — both must exceed the floor.

Candy Realm's three working examples:

- `AncientTreeQuest` gate crank — `CRANK_SPEED = 330`°/s while held vs `CRANK_DECAY = 150`°/s
  slip-back when you let go, `CRANK_TURNS = 3` (1080°), with `SEIZE_POINTS = {0.38, 0.76}`
  forcing two re-grips. Held perfectly that's ~3.3s per gate, so the floor here comes from
  three gates plus the walk, not from one crank.
- `BakeryQuest` oven — `HEAT_DECAY` bleeds heat away, `HEAT_STOKE = 24` throws it back, and
  the bake bar only fills fast while the needle sits in the orange zone. Mashing STOKE
  overshoots the zone and costs you time.
- `RadioactiveCleanupQuest` crane — slew and hoist travel time paces the whole loop.

## Where Candy Realm currently breaks the floor

Audited against the source. These are the gaps, worst first:

| Quest | Problem | Fix |
|---|---|---|
| `CandyGumballQuest` | 8 orbs collected by proximity (`COLLECT_DISTANCE = 12`) — walk over, done. No floor at all. | Needs a mechanic, not just a longer walk |
| `CookieRepairQuest` | 6 chunks on a `HoldDuration = 0` "Take" prompt — instant. | Same |
| `BakeryQuest` stir | `STIRS_NEEDED = 8` on a `HoldDuration = 0` prompt — a masher clears it in ~2s. | Pattern 1 (rising ceiling) or 2 |
| `CrystalMineQuest` | `HITS_PER_CRYSTAL = 6`, dropping to `UPGRADED_HITS = 4` after `UPGRADE_AFTER = 3`. Click-limited, so a fast clicker sets the pace. | Pattern 2 — a swing cooldown |
| `CampSmoresQuest` | `SWINGS_PER_TREE = 6`, same click-limited shape. | Pattern 2 |

Note the Crystal Mine upgrade *deliberately* shortens the back half ("so the back half of
the job speeds up instead of dragging"). That's a legitimate deviation from a flat floor —
but it should shorten a floor that exists, not substitute for one.

## Design constraints

- **Mobile first.** Whatever tap rate is needed to make progress must stay under
  ~2.7/sec. Length comes from more reps, never from faster input.
- **Forgiving, not punishing.** No hard fail. Failure costs progress (~10%) plus a short
  lockout. Bailing out closes the panel with no reward. `CampfireFreezeQuest` is the one
  quest with a real fail state, and it is deliberately generous — `FREEZE_CALM_TIME = 190`.
- **X button closes it — a backdrop tap NEVER does.** (House rule across this game.)
- **Reset the world prop on abort,** or a half-cranked gate stays half-cranked.
- **The real world object reacts behind the panel** (the dim film is 0.5 transparency, so
  it's visible). It should move a believable distance.
- **UI:** house palette — panel `Color3.fromRGB(25,90,185)`, white `UIStroke` 3, gold title
  `(255,215,0)`, 0.5 black film, `DisplayOrder = 90`. Prompt opens it with
  `HoldDuration ≈ 0.4`.
- **Props:** anchor every part AND `WeldConstraint` them to a root, or they read as loose
  debris. Island 15 markers stream in late — keep the scanner polling, and raycast-ground
  hand-placed markers once the player is near.

## Budgeting the time

Multiply the floor by the item count and sanity-check the island total. Current Candy Realm
counts, from source:

| Quest | Island | Items | At a 15s floor |
|---|---|---|---|
| CandyGumball | 1 | 8 gumballs (`TOTAL`) | 120s |
| CookieRepair | 3 | 6 chunks (`TOTAL`) | 90s |
| CampfireFreeze | 4 | 16 materials (5 log + 8 stone + 3 kindling) | not a per-item floor — timed quest |
| CrystalMine | 8 | crystals in world × 6 hits | — |
| TunnelBlast | 11 | 3 crates + 10 ore nodes | — |
| AncientTree | 13 | 4 pipes + 3 gates | ~20s pipes, ~15s gates (already met) |
| CampSmores | 14 | 4 trees + 6 mushrooms | 150s |
| Bakery | 15 | 8 stirs + 1 bake | — |

Watch the item count. 8 gumballs × 15s is two minutes of one verb on the *first* island,
which is well past tedious for a tutorial quest — cut the count before you add the floor.
**3–5 collectibles per quest is the comfortable range.** `CampfireFreeze`'s 16 pieces only
work because the verb is "walk it over and it snaps in", not a minigame each.
