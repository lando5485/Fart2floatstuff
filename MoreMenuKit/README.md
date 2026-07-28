# MoreMenuKit — everything behind the MORE+ button, copied exactly

Drop-in copy of Fart to Float's pink **MORE+** button and everything it opens, pulled verbatim
out of the `MORE+ POPUP MENU + SEASONAL LOCKER` block in `src/client/CoreClient.client.lua`.

## Install

1. Put `MoreMenuKit_AllInOne.client.lua` in **StarterPlayer → StarterPlayerScripts** as a
   **LocalScript** (or via Rojo: `"MoreMenu": { "$path": "MoreMenuKit/MoreMenuKit_AllInOne.client.lua" }`).
2. Edit `CONFIG.entries` to match what that realm actually has.
3. Done. Rows whose target doesn't exist in the realm hide themselves.

## What's in the box

| # | Piece | Where it lives |
|---|---|---|
| 1 | The **MORE rail button** — 95×95 pink, rail slot 4 | `MoreMenuKitSidebarGui` |
| 2 | The **MORE+ popup** — 196×206 pink window, scrolling list of 7 rows | `MoreMenuGui` |
| 3 | The **"!" ready dot + wiggle** — two independent dot groups, one shared ±8° wiggle | on the rows + the button |
| 4 | The **Seasonal Pets locker** — 700×520 wood-and-garden panel with 4 expandable season cards and spinning 3D pet previews | `LockerGui` |

**What's deliberately NOT in here:** six of the seven rows open panels owned by *other* scripts —
Rebirth, Daily Tasks, Pet Inventory, Pet Wheel, Free Rewards, Season Pass. This kit is the
**menu**, not every destination. Each action is a guarded `_G.*` call, so it lights up the moment
that realm has the panel. The **Seasonal Pets locker** *is* included, because CoreClient builds it
inside this same block and nothing else can open it.

## The MORE rail button (exact values)

- Frame **95 × 95**, `AnchorPoint (0,0)`, `Position (0,12,0,417)` — rail slot 4 of the desktop grid
  `96 / 203 / 310 / 417` (107 px pitch).
- `BackgroundColor3 = Color3.fromRGB(225,70,170)` (pink), **`UICorner 14`**, **`UIStroke` white w2**.
- Icon: `TextLabel` `"+"`, `Gotham`, `TextSize 30`, `Size (1,0,0,56)` at `(0,0)`, `RichText = true`,
  black stroke 1.
- Label: `"MORE"`, `GothamBold 12`, white, `Size (1,0,0,28)` at `(0,0,0,57)`, centered, black stroke 1.
- Full-size transparent `TextButton` on top.

> **The asymmetry is real.** The rail restyle pass touches SHOP / WORMHOLE / Stomach but **never
> MORE**, so MORE keeps the original **corner 14 + white stroke w2** while its three neighbours got
> **corner 16 + coloured strokes w3**. It only ever gets its size/position set to the 95 grid. Copied
> as-is — if you "fix" it, the button stops matching the game.

## The MORE+ popup (exact values)

```
MoreMenuGui  (ScreenGui, DisplayOrder 8, ScreenInsets = CoreUISafeInsets, ResetOnSpawn = false)
├─ catcher   (1,0,1,0) transparent TextButton, ZIndex 1 — tap-outside-to-close
└─ panel     196 × 206   bg 225,70,170   UICorner 14   UIStroke white w2   ZIndex 2
   UIPadding 8 on all four sides
   ├─ hdr        (1,0,0,28) at (0,0)      transparent
   │  ├─ "MORE"  (1,-32,1,0) at (0,4,0,0)  FredokaOne 18, white, left, ZIndex 3
   │  └─ X btn   26×26 at (1,-26,0.5,0) anchor (0,0.5)  red 210,60,55, corner 8, GothamBold 16
   └─ EntryList  ScrollingFrame (1,0,1,-36) at (0,0,0,36)
      transparent (the panel's pink shows through), AutomaticCanvasSize = Y,
      ScrollBarThickness 6, gold 255,215,0, ClipsDescendants, UIListLayout padding 8
      └─ 7 rows: (1,0,0,46)  bg 248,240,250  corner 10
         ├─ icon   30×30 (image) or 30-wide TextLabel Gotham 22, at x8, ZIndex 3
         └─ label  (1,-50,1,0) at (0,46,0,0)  GothamBold 18, plum 70,40,65, left, ZIndex 3
```

**Position:** the panel is placed from the button's **live** `AbsolutePosition` / `AbsoluteSize`
every time it opens — `fromOffset(ap.X + asz.X + 10, ap.Y)`, i.e. 10 px to the **right** of the
MORE button, top-aligned with it. No hardcoded coordinates, so it lands right at any rail scale or
device.

**Why the window is fixed at 206 tall:** that's ~3 entries. There are 7, so they overflow and the
inner `ScrollingFrame` scrolls, instead of the panel growing off the bottom of the screen. The rows
are parented **directly** into the ScrollingFrame (no intermediate Frame) — that's what lets
`UIListLayout` + `AutomaticCanvasSize` measure them. The panel itself deliberately has **no**
UIListLayout (it mirrors the locker's manual layout); adding one breaks the canvas measurement.

Clicking a row: play click → **close the popup** → run the action.

### The 7 rows

| Row | Icon | Opens | Dots |
|---|---|---|---|
| Rebirth | 🔄 | `_G.toggleRebirth()` | — |
| Daily | 🎁 | `_G.toggleDailyTasks()`, or fires the `OpenMeteorCrate` BindableEvent if the player isn't eligible yet | **both** |
| Pets | 🐾 | fires the `PetInvToggle` BindableEvent in PlayerGui | — |
| Pet Wheel | 🎡 | `_G.togglePetWheel()` | — |
| Seasonal Pets | 🐾 | the locker in this file | — |
| Free Rewards | 🎁 | `_G.toggleSocialRewards()` | — |
| Season Pass | ⭐ | `_G.toggleSeasonPass()` | — |

Two consolidations are baked into that list, worth keeping if you rebuild it:
- **"Daily Rewards" + "Daily Tasks" merged into one "Daily" row.** Two rows for one habit meant a
  player had to already know they were different menus. The tasks panel now carries the crate as a
  DAILY REWARD button, so both dots ride on this single row. If the player is too new to have a task
  list the panel would refuse to open, so the row fires the crate directly instead — the reward is
  never unreachable.
- **"Codes" moved into the Season Pass panel** (bottom-left CODES button) and the **MLR Group** row
  was removed in favour of a periodic banner. Both were whole menu rows for rare actions.

### The "!" dot (18×18)

`Frame` 18×18, `AnchorPoint (1,0)` at `(1,-2,0,-2)`, red `225,50,50`, `UICorner (1,0)` (full circle),
`ZIndex 8`, with a `GothamBlack 13` white `"!"` at `ZIndex 9`. Starts hidden.

**Two independent groups, on purpose:** `crateReadyDots` (driven by `_G.crateIsClaimable()`) and
`taskPendingDots` (driven by `_G.dailyTasksPending()`). Claiming the crate must not clear the tasks
dot and vice versa. A 1 s poll toggles both groups and drives a **shared** wiggle — the whole MORE
button oscillating `-8° → +8°` on a 0.32 s reversing Sine tween, the same wiggle the gut button uses.
The dot goes on **both** the Daily row and the MORE button itself.

## The Seasonal Pets locker (exact values)

```
LockerGui  (ScreenGui, DisplayOrder 100, Enabled = false, CoreUISafeInsets)
└─ lockPanel  700 × 520 at (0.5,0,0.5,-45) anchor (0.5,0.5)   ← identical geometry to the SHOP panel
   cream 245,238,214 · UICorner 18 · UIStroke brown 120,78,40 w4 · ClipsDescendants
   ├─ header   (1,0,0,50)  dark wood 74,48,30
   │  🌻 26×26 at x16 centered · "Seasonal Pets" FredokaOne 22 white at x50 · X 34×34 red 210,60,55 corner 9
   ├─ subtitle (1,-28,0,42) at (0,14,0,60)  green 58,116,52 corner 12
   │  🌿 both ends + centered wrapped GothamBold 13 white
   ├─ scroll   (1,-24,1,-146) at (0,12,0,110)  brown scrollbar w5, AutomaticCanvasSize Y,
   │           UIListLayout padding 10 centered  → the 4 season cards
   └─ footer   (1,0,0,28) at bottom  green 70,130,60 · GothamBold 13 white centered
```

**Season cards** — `AutomaticSize = Y`, corner 14, stroke = the season accent w2, own UIListLayout:

- **Collapsed header row** (66 tall, the *whole row* is the expand button, `AutoButtonColor = false`):
  a 52×52 `ViewportFrame` at x8 (corner 10), the season emoji at x70, `SEASON` in the accent colour
  at x94, the pet name FredokaOne 18 at x70/y30, a status **pill** (84×26, corner 13) at
  `(1,-118,0.5,0)`, and a chevron `v`/`^` at `(1,-28)`.
- **Expanded content** (hidden unless this is the open card): a `(1,0,0,150)` `ViewportFrame` preview,
  `SEASON REWARD` caption, the pet name at 24, a **progress bar** (22 tall, corner 11, bg
  `225,215,190`, fill green `90,200,80`) with `"0 / 2000 Flowers"` centered on it, the season blurb,
  then a 40-tall **EQUIP** button (green `70,150,55`, corner 12).

**Accordion:** clicking a header sets `expanded` to that season, or `nil` if it was already open —
exactly one card open at a time. Opening the locker defaults to the first season's card.

**Pill / bar states:**

| State | Pill | Bar |
|---|---|---|
| Not owned, not the current season | `LOCKED` brown `150,120,90` | 0 % — only the active season's garden counts |
| Not owned, current season | `LOCKED` | live `GardenProgress / GardenGoal` |
| Owned | `OWNED` blue `90,160,210` | full, `Earned ✓` |
| Owned + equipped | `EQUIPPED` green `70,150,55` | full — button reads `EQUIPPED ✓` on `120,160,110` |

**The 3D previews:** `fillViewport` clones a template out of ReplicatedStorage, anchors every part,
pivots the root to the origin, and frames a `FieldOfView 50` camera from
`Vector3.new(0.8, 0.5, 0.55).Unit * (maxExtent * 1.45 + 1)` — a 3/4 front view slightly above (pets
face **+X**). It's a **lazy fill**: templates replicate a moment after join, so it retries on every
refresh until one lands. Every viewport model registers into one shared spin list and gets
`PivotTo` rotated about its bounding-box centre at `dt * 0.6` on `RenderStepped` — but **only while
the locker is open**, so it costs nothing the rest of the time. Same speed and axis as the pet
inventory icons.

**Wiring:** equips via the same `PetEquipEvent` the pet inventory uses (`FireServer(false)` toggles
off). Ownership from `PetStateEvent`. Live progress from the Workspace `GardenProgress` /
`GardenGoal` / `GardenSeason` attributes the server mirrors. Opening fires
`PetRequestStateEvent` to refresh ownership. All guarded — with none of it present the cards just
render LOCKED at 0 % with empty previews.

## ⚠️ The popup closes on a tap outside

That contradicts your house rule for menus (X button only). It's what the live code does, and the
justification is that this is a small pop-out rather than a panel — but it's the one behaviour here
most likely to be wrong for you. `CONFIG.closeOnTapOutside = false` makes it X-only; the catcher is
then never shown. The **locker** already follows the rule (X only, no backdrop).

## Config flags

| Flag | Default | What it does |
|---|---|---|
| `buildMoreButton` | `true` | `false` = don't build the rail button; call `_G.toggleMorePopup()` from your own sidebar |
| `moreButtonY` | `417` | rail slot (grid `96 / 203 / 310 / 417`); mobile re-derives the slot from this |
| `closeOnTapOutside` | `true` | see the warning above |
| `hideMissingEntries` | `true` | hides rows whose `needs` hook doesn't exist; re-checked once a second for 10 s while other scripts load. `false` = show them and banner on click |
| `showSeasonalLocker` | `true` | `false` drops the whole locker panel and hides its row |
| `entries` | 7 rows | `{ label, emoji or image, action, needs, readyDot, tasksDot, color }` |
| `locker` | garden copy | title, icons, subtitle, footer, goal noun, default goal |
| `seasons` | 4 seasons | pet ids, template names, card + accent colours, blurbs |

Globals it exposes: `_G.toggleMorePopup()`, `_G.openSeasonalLocker()`.

## Mobile

The rail button re-derives its Y from the live scale, because the four rail buttons are separate
fixed-offset frames — a `UIScale` sizes each one but leaves the **gaps** fixed, which spreads them
out when scaled down (phone) and **overlaps** them when scaled up (iPad):

- **Phone-class** (viewport short axis < 800): pitch `101 × s`, rail top **y66** to clear the joystick
- **Tablet/iPad**: pitch `107 × s`, authored top **y96**, scales *up* to 2.5
- **Desktop**: the exact authored grid, untouched, scale 1

The **popup is deliberately not scaled** — it's positioned from the button's live `AbsolutePosition`
each open, so it follows the scaled rail on its own.
