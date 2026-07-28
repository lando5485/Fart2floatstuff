# StatsPanelKit — the right-side STATS panel, copied exactly

Drop-in copy of Fart to Float's **⭐ STATS panel** (`RightPanelGui`), pulled verbatim out of
`src/client/CoreClient.client.lua`. These are the **final** in-game values — i.e. after both
restyle passes run, not the initial build values the game overwrites at load.

## Install

1. Put `StatsPanelKit_AllInOne.client.lua` in **StarterPlayer → StarterPlayerScripts** as a
   **LocalScript** (or via Rojo: `"StatsPanel": { "$path": "StatsPanelKit/StatsPanelKit_AllInOne.client.lua" }`).
2. Swap the three **product ids** in `CONFIG.productIds`.
3. Point `CONFIG.progress` at whatever drives progress in that realm.

No server script, no remotes, no `_G.foods` needed. It shows `Island: 1` / `Max Height: 0`
until real data exists, then fills in.

## Layout (exact values)

```
RightPanelGui  (ScreenGui, IgnoreGuiInset = true, ScreenInsets = DeviceSafeInsets,
                ZIndexBehavior = Sibling, ResetOnSpawn = false)
└─ RightPanel   230 × 500   Position (1,-5,0,85)   AnchorPoint (1,0)   ZIndex 3
   bg 30,140,255 · UICorner 20 · UIStroke 20,60,160 w3
   ├─ statsSection      (1,-16,0,175) at (0,8,0,8)   transparent
   │  ├─ "⭐ STATS"       (1,-8,0,32)  at (0,8,0,0)    GothamBold 20  gold 255,220,0  left
   │  ├─ "🏝️ Island: 1"   (1,0,0,36)   at (0,0,0,36)   GothamBold 22  white          left
   │  ├─ "🏆 Max Height:0"(1,0,0,36)   at (0,0,0,76)   GothamBold 22  white          left
   │  ├─ "🚀 TO SPACE REALM" (1,0,0,22) at (0,0,0,116) GothamBold 16  190,210,255    left
   │  └─ bar bg          (1,-2,0,22)  at (0,0,0,142)  10,14,36 · corner 9 · stroke 8,10,28 w1
   │     ├─ fill         (frac,0,1,0)  90,200,120 → 170,110,255 at 100% · corner 9 · ZIndex 4
   │     └─ "Island 7/14 - 50%"  GothamBold 13  white · black stroke 1 · ZIndex 5
   ├─ divider           (1,-16,0,2)  at (0,8,0,187)   white @ 0.7 transparency
   ├─ MidAirBtn         (1,-16,0,78) at (0,8,0,197)   20,180,255 · corner 14 · stroke 20,80,180 w3
   ├─ TwoXBtn           (1,-16,0,78) at (0,8,0,295)   180,80,255 · corner 14 · stroke 80,30,140 w3
   └─ BirdNukeBtn       (1,-16,0,78) at (0,8,0,393)   255,60,60  · corner 14 · stroke 160,20,20 w3
```

Every impulse button has the same internals:

| Part | Size | Position | Style |
|---|---|---|---|
| emoji icon | `0,60,0,60` | `(0,8,0.5,0)`, anchor `(0,0.5)` | Gotham, TextSize 36, ZIndex 5 |
| TITLE | `1,-76,0,28` | `(0,76,0,8)` | GothamBold 20, white, left |
| SUB | `1,-76,0,22` | `(0,76,0,38)` | Gotham 16, `220,220,220`, left |
| PRICE | `1,-76,0,22` | `(0,76,0,62)` | GothamBold 16, green `100,255,100`, left |

- Mid-Air: `⚡☁️` / `MID-AIR` / `RECHARGE` / `39 R$`
- 2x Power: `⚡` / `2X POWER` / `1 HOUR` / `59 R$` — the SUB slot also holds the live timer
- Bird Nuke: `🐦💥` / `BIRD NUKE` / *(no sub row)* / `79 R$`

### Two quirks copied as-is

1. **The button gaps are 20 px, not 8.** The buttons were authored 90 tall at y `197 / 295 / 393`
   (8 px apart), then the final restyle pass shrank them to **78** without re-deriving the
   positions. The look everyone knows has the wider gaps, so it's kept. Want them tight?
   Change the ys to `197 / 283 / 369`.
2. **The panel is 500 tall but the content ends at 471.** Leftover from the removed 3rd stat row.
   `showImpulseButtons = false` shrinks it to 195 (stats only, no divider or buttons).

## Data sources

| Row | Reads |
|---|---|
| Island | `_G.leaderstats.Island` → falls back to `player.leaderstats.Island` |
| Max Height | `max(_G.peakHeight, session best)` — never ticks backwards mid-flight |
| Progress bar | `player:GetAttribute("HighestIsland")` (server-authoritative) → falls back to the `Island` leaderstat |
| 2x timer | `_G.playerGamepasses.twoXHourExpiry`, set by the server's `ProcessReceipt` → `GamepassEvent` |

There was a third stat row, **"Farts"** (`TotalFartPower`), at y=116 — removed so Max Height is
the bottom stat. The leaderstat itself is untouched and still drives flight/power.

## Mid-air-recharge freeze (the non-obvious part)

Tapping **MID-AIR RECHARGE** while airborne holds you in place for the whole Robux prompt so
you don't keep falling through it:

1. Zero velocity, `HumanoidRootPart.Anchored = true`, and set the `Frozen` player attribute
   (Fart to Float's flight loop reads `Frozen` and skips flight while it's set).
2. **Purchased** → meter refills to max and you **keep hovering** with a full tank. It does
   *not* auto-resume; your next fart press does.
3. **Cancelled** → hold releases immediately, you resume falling from rest, no refill.
4. A 60 s safety timeout releases the hold if no result ever arrives — but it deliberately does
   *not* fire once a purchase succeeded, because that hover is intentional.

It never stomps an existing `Frozen` hold (e.g. the server's join freeze), and clicking on the
ground does nothing special. In a realm whose flight code doesn't read `Frozen`, the anchoring
alone still stops the fall, so this works standalone. Set
`CONFIG.midAirFreezeWhileBuying = false` to skip it entirely.

Globals it exposes for the rest of the HUD: `_G.rechargeAwaitingFart`, `_G.endRechargePause`,
`_G.rechargeMarkPurchased`. It calls `_G.rechargeFartMeter()` if your realm defines it — that's
the function that actually writes the meter to max.

## Mobile

`RightPanelGui` is one of the three screen-hogging clusters, so it gets an **extra 0.78** on top
of the global scale, phones only:

- Scale formula: iPhone SE/8 landscape reference (1100×590), `clamp(min(vp.X/1100, vp.Y/590), 0.55, deviceMax)`
  where `deviceMax` = **0.60** phone-class (short axis < 800) or **2.5** tablet/iPad. Desktop is exactly 1.
- Anchor `(1,0)` means the `UIScale` shrinks it *into* the top-right corner — it can't drift off-screen.
- Phone-class moves it to `(1,-8,0,coinBottom+8)`, tucked under the coin pill, where
  `coinBottom = 10 + round(52 × scale × 0.78)`. That Y is **derived** from the pill's live scaled
  height on purpose: the pill and the panel shrink by different amounts, so any fixed number
  either opens a gap or overlaps them the moment a multiplier changes.
- If your realm's coin pill isn't 52 px tall at y10, edit `COIN_HEIGHT` / `COIN_Y` near the bottom
  of the file, or call `_G.repositionStatsPanel()` after you build yours.

## Config flags

| Flag | Default | What it does |
|---|---|---|
| `productIds` | FtF ids | **must be replaced per experience** |
| `prices` | `39/59/79 R$` | the price label text (cosmetic only — Roblox shows the real price) |
| `showImpulseButtons` | `true` | `false` = STATS only; panel shrinks to 230×195 |
| `midAirFreezeWhileBuying` | `true` | the mid-flight hold described above |
| `progress` | space-realm bar | `title`, `total`, `attribute`, `leaderstat`, `unit`, `fillColor`, `doneColor` |
| `rows` | 🏝️ / 🏆 prefixes | stat row icons + labels |

## ⚠️ Product ids won't carry over

`3600303163` (Mid-Air), `3600302990` (2x 1-Hour), `3600303082` (Bird Nuke) belong to the **Fart to
Float** experience. In another realm they won't prompt and won't grant. Make new dev products in
that game's Monetization page, paste the ids in, and add a `ProcessReceipt` branch per id on the
server — this panel only *prompts*.
