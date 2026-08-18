# Bubble Kit

Both floating pickups that hang in the air between islands in Fart to Float, cut free of that game so any
realm can drop them in. Same look, same pulse, same erratic drift, same pops, same streak.

| | GAS | COIN |
|---|---|---|
| looks like | green 20-stud ball, **pulsing** | gold / cyan / pink 24-stud ball, steady |
| label | 💨 GAS! | 🪙 +BONUS |
| pays | refuel (a % of your tank) | coins, on a **streak multiplier** |
| collect radius | 20 studs | 16 studs |
| respawns | 45s | 30s |
| pops with | expand + green sparkle burst | destroyed instantly, sound only |

The pulse is the point of difference in the air: at a distance you tell them apart because the green one
breathes and the coloured one doesn't.

> The coin bubble is called a **"ring"** all through the original source (`spawnRing`, `activeRings`,
> `ringStreak`). It used to be a flat ring/cylinder, became a sphere, and the name never got updated.
> It is a ball. Don't go looking for a torus.

## Install

| file | goes in |
|---|---|
| `Bubbles.client.luau` | `StarterPlayerScripts` |

Then tag your islands: pick one part per island — the top surface players land on — and in Studio's
Properties → Attributes add a **number** attribute named `BubbleAnchor` set to that island's index
(`1`, `2`, `3`…). Bubbles spawn in the gaps *between* consecutive anchors, so you need at least two.

Prefer the attribute to a naming convention — the original matched `^Island_(%d+)_` and that breaks the
first time someone renames a model. An attribute is attached to the thing itself and survives renaming,
moving and reparenting. If you'd rather not tag anything, set `SHARED.FALLBACK_FOLDER` and it'll look for
`Island1`, `Island2`… inside it.

Last step — **edit `GAS.onPop` and `COIN.onPop`**. Out of the box bubbles pop and pay nothing. Wired
examples are in both; delete the ones you don't want. Set `ENABLED = false` on a type to ship only one.

## What a bubble does

Nothing is server-authoritative here, on purpose. Bubbles are anchored, non-collidable, moved by code only,
and each player collects their own — so two players never race for the same bubble and nobody watches one
vanish from under them. The only thing worth server auth is the reward, which is exactly what `onPop`
hands off to your RemoteEvent.

### The gas reward, and the one trap when porting it

The original grants **+2 on a 0–100 gas meter** — which is **2% of the tank**, not a flat +2. That's
deliberate, and the source comment spells out why:

> at the base Tiny Gut (100 max power) 1 meter point IS 1 fart power — this grants exactly +2 fart power
> there, and stays 2% of the tank on bigger guts so a bubble does not become worthless the moment you
> upgrade. For a flat +2 power at EVERY tier instead, this would have to be `(2 / stomachMax) * 100` —
> which pays 0.06 of a meter point on an Iron Gut, i.e. nothing.

Keep that shape. Pay a **percentage** of whatever the resource is, never a flat amount, or the pickup dies
the moment your realm's numbers grow.

### The coin streak — the reason coin bubbles are interesting

```
multiplier = 1 + streak * 0.2
bonus      = floor(15 * multiplier * eventMultiplier)
```

Every coin bubble collected **without landing** raises the streak. Landing resets it to zero.

So a chain in a single flight pays far more than the same number of bubbles across several flights:
five in one climb pays 18+21+24+27+30 = 120, while five across five climbs pays 18 each = 90. That gap is
what makes players plan a route up through the bubbles instead of grabbing whichever is nearest.

Landing is detected off the Humanoid's floor material, or the host realm's `_G.hasLanded` if it sets one.

⚠️ Example (A) in `COIN.onPop` fires the coin remote with a **client-computed** amount, same as the
original. That's fine for a coin pickup in a climber that feels single-player. If your realm has trading or
a leaderboard, use example (B): send the streak and let the server compute the payout.

## How they move

Both types share **one** drift function — that's why they move identically, and it's preserved here rather
than duplicated. This is the part that makes them feel alive, and the part most likely to get watered down
in a port.

Each bubble wanders inside a box around its spawn point: **±180 studs horizontally, ±280 vertically**, at
**12 studs/sec**. It re-aims every **0.35–1.3 seconds**, and the turn is *sharp* — the new random heading is
weighted 4:1 over the current one (`vel * 0.25 + randDir()`), so it darts rather than curves. Hitting a wall
of the box bounces it inward.

Those numbers are all tuned-up from earlier, gentler values (speed was 5, the box was ±45/±70, re-aims were
every 2–4.5s). The current feel is *a real chase, but still catchable by a determined flyer*. If you slow it
back down it stops being interesting; if you speed it up it stops being catchable.

Vertical drift is additionally clamped to the bubble's own island gap — `[lower island + 120, upper island − 200]`
— so a wide vertical band can't let a bubble wander into the next island's airspace. If a gap is shorter than
±280, the gap wins vertically and the full ±180 horizontal still applies.

It moves **per frame** (`task.wait()`), not on a timer. That matters: collection reads the part's *current*
position every frame, so a chunky update would let a fast player pass through a bubble between steps.

## Where they go

Two of each per gap, on opposite sides (`ang` and `ang + π`), pushed off the straight-up climb line:

| | height up the gap | studs off the centerline |
|---|---|---|
| GAS | 35% and 65% | 60–110 |
| COIN | 33% and 67% | **85–145** |

Coin bubbles sit noticeably further out — they're worth more, so they cost more of a detour.

All of that is one idea: grabbing a bubble should be a **choice**. If they sat on the centerline you'd
collect them by accident on a normal ascent, and putting both on the same side would make sweeping up both
nearly free. Players have to deviate.

The gap itself is inset — 120 studs above the lower island, 200 below the upper — so bubbles never spawn
inside an island's airspace or tucked under its underside.

Coin colours cycle gold → cyan → pink across all bubbles, and a respawned one keeps its original colour.

## Collection

Checked every frame, deliberately **outside** any is-flying condition. A bubble pops whether the player is
rising **or falling** through it — a falling player who steers into one gets it, which matters because
falling is when you most want the gas back.

Radii are 20 (gas) and 16 (coin). Gas is the more generous target despite the smaller ball; coin asks for
more precision because it's worth more.

After popping, a bubble **respawns at its original spawn point** — not wherever it had drifted to — so the
pickups stay in place over a long session instead of slowly clumping.

## Config worth knowing

`SHARED` — applies to both types:

| key | default | note |
|---|---|---|
| `DRIFT_SPEED` | `12` | the single biggest feel knob. 5 is a float, 12 is a chase, past ~18 it's uncatchable |
| `DRIFT_HR` / `DRIFT_VR` | `180` / `280` | wander box half-extents. Vertical is re-clamped to the island gap regardless |
| `REAIM_MIN` / `REAIM_MAX` | `0.35` / `1.3` | seconds between heading changes. Raise both and it glides instead of darting |
| `TURN_INERTIA` | `0.25` | how much of the old heading survives a re-aim. Raise toward 1 for smooth curves |
| `GAP_BOTTOM_PAD` / `GAP_TOP_PAD` | `120` / `200` | airspace kept clear at each end of a gap |
| `DEBUG` | `true` | one print per pop. Turn off for release |

Per type:

| key | GAS | COIN | note |
|---|---|---|---|
| `ENABLED` | `true` | `true` | set one to `false` to ship only the other |
| `COLLECT_RADIUS` | `20` | `16` | smaller feels unfair against a moving target |
| `RESPAWN` | `45` | `30` | gas is worth more, so it's rarer |
| `SPREAD_MIN`/`MAX` | `60`/`110` | `85`/`145` | studs off the climb line. Drop toward 0 and bubbles become free |
| `T_POSITIONS` | `{0.35, 0.65}` | `{1/3, 2/3}` | add entries for more per gap; they auto-space around the circle |
| `PULSE` | `true` | `false` | the at-a-distance tell between the two |
| `POP_STYLE` | `burst` | `instant` | set coin to `burst` if you want it to match gas |
| `SOUND_ID` | `9114402399` | `115390827163601` | the gas one is a placeholder in the original too |
| `BASE_BONUS` / `STREAK_STEP` | — | `15` / `0.2` | the streak formula above |

## Notes

- **Don't install this in Fart to Float or CandyRealm.** Both already run both systems inside their own
  `WorldClient`/`CoreClient`, and you'd get two overlapping sets of bubbles.
- Works with **StreamingEnabled**. Boot polls for anchors for up to 30s rather than reading workspace once,
  because far islands stream in late. If it can't find 2+ anchors it warns and spawns nothing instead of
  failing silently.
- **Floating text** reuses the host realm's `_G.showFloatingText` if there is one, so it matches your
  existing popups. Otherwise it creates its own faithful 3-slot copy.
- `_G.serverEventRingMult` is read for the coin bonus if your realm sets it (that's the "double coins" event
  multiplier). Absent, it's just 1.

## Source

| what | original location |
|---|---|
| drift / movement (shared) | `src/client/WorldClient.client.lua:26` — `startBubbleDrift` |
| gas pulse | `src/client/WorldClient.client.lua:113` — `startGasPocketPulse` |
| gas look / spawn | `src/client/WorldClient.client.lua:126` — `spawnGasPocket` |
| gas pop | `src/client/WorldClient.client.lua:139` — `popGasPocket` |
| coin look / spawn | `src/client/WorldClient.client.lua:74` — `spawnRing` |
| coin placement | `src/client/WorldClient.client.lua:366` |
| gas placement | `src/client/WorldClient.client.lua:383` |
| gas collection + boost | `src/client/CoreClient.client.lua:3089` |
| coin collection + streak | `src/client/CoreClient.client.lua:3116` |
| streak reset on landing | `src/client/CoreClient.client.lua:2749` |
