# Candy Realm — Banner + Mini Events port

Ported from Space Realm on 2026-08-14. Two systems, one document.

---

# 1. The announcements banner

## Where it lives

| File | What it is |
|---|---|
| `src/client/NotifyCenter.luau` | **ModuleScript.** The banner itself — 649 lines, ported from Space Realm. |
| `src/client/CandyTheme.luau` | ModuleScript. Palette + panel helpers. A recoloured copy of Space's `SpaceTheme`. |
| `src/client/NotifyCenter.client.luau` | 40-line bootstrap. Requires the module and publishes `_G.NotifyCenter`. |

It is a **module, not a client script**, deliberately. The old version published `_G.NotifyCenter` and then had to
fight a load-order race to keep it. A `require` has no such race: the first caller builds the GUI, everyone else
gets the same table.

## Size

The card is **500 × 65** desktop, corner radius **12**.

Every internal position is expressed in **scale**, not pixels, so the same card also fits the phone banner spot
(`PhoneHUD.BANNER_SIZE` = 300 × 80) with no second layout:

| Line | Scale | At 500×65 |
|---|---|---|
| Top (kicker) | y `0.08`, h `0.34` | y 5.2, h 22.1 |
| Main (headline) | y `0.44`, h `0.50` | y 28.6, h 32.5 |
| Main **only**, no kicker | y `0.12`, h `0.76` | y 7.8, h 49.4 |

A card with the optional third `sub` line grows to **92** (desktop) / **96** (phone) and the three lines reflow.
Without a `sub`, the geometry above is untouched.

## Placement

The hero card sits at the **shared banner spot owned by `PhoneHUD`** (`PhoneHUD.bannerOn()` / `bannerOff()`),
re-read at show time so it always uses the live ResponsiveUI scale.

**Desktop spot = `UDim2.new(0.5, 0, 0, 10)`** — the exact position the Food realm uses
(`NotifyCenter.client` `HERO_SHOWN`), sliding in from `0, -100`.

⚠ This was `180` when the module first landed, which was **Space Realm's** number: its comment justified the
offset as clearing "the slim Planet title + the RaceBoard leaderboard", neither of which exists in Candy. The
visible symptom was the banner sitting a third of the way down the screen while the eleven quest objective
banners still occupied y=12, where this realm's banner has always been. `PhoneHUD` is the only source of that
spot and `NotifyCenter` is its only consumer, so moving it moved the banner and nothing else.

The **SOCIAL** lane is top-left: x `12`, first pill at y `10`, pills **300 × 34** with a **6px** gap, capped at
**2** so the stack always ends above the left rail (which starts at y `96`).

## Motion

| | |
|---|---|
| Slide in | 0.4s, `Back` / `Out` |
| Slide out | 0.3s, `Quad` |
| Default hold | 3.5s (`spec.duration` overrides) |

## How it works

Two ideas do all the work.

**1. Lanes.** Notifications are placed by *kind*, not all dumped in one spot.

- `HERO` — your own big moments. The prime slot.
- `SOCIAL` — other players' news. Small top-left pills that never block you.

**2. Priority.** The HERO lane shows **exactly one card at a time**. A more important banner **preempts** a less
important one, and the demoted card goes **back on the queue** — it is never eaten. Equal-or-lower priority
banners queue behind.

```
PLANET / ISLAND  100   you arrived somewhere new — the biggest moment in the game
PURCHASE          90   a real Robux purchase went through — must never be swallowed
EVENT             80   a server event started (2x coins, high gravity, …)
REWARD            40   "Daily Reward Ready" — a nudge, not news
SOCIAL            10   another player's news — routed to its own lane, never competes
```

So "SUGAR RUSH!" can never be buried under "Daily Reward Ready".

## The eleven quest objective banners are gone

Before: eleven quest scripts each built their **own** ScreenGui at `(0.5, 0, 0, 12)` — inside the hero band —
none of them aware of each other or of NotifyCenter. `CandyQuestObjective` ("Go talk to the Candy NPC!"),
`CookieQuestObjective`, `ParkObjective`, `BakeryObjective`, `SmoresObjective`, `CleanupObjective`,
`SummitObjective`, `StormObjective`, `JellyQuestObjective`, `CrystalQuestObjective`, `DeliveryQuestObjective`.
They were 520–560px wide against the hero's 500, so their ends stuck out past the card on both sides.

Now `ObjectiveBannerBridge.client.luau` hides all eleven **for good** (`ScreenGui.Enabled = false` — the quests
keep driving their frames' `Visible` underneath, untouched) and re-pushes whatever they currently say through
the one realm banner at **`PRIORITY.REWARD`**:

```
ISLAND   100  landing on a new island       -> preempts the objective instantly
PURCHASE  90  a real Robux purchase         -> preempts
EVENT     80  COIN RUSH / HIGH GRAVITY ...  -> preempts
REWARD    40  the quest objective           <- here
```

The demoted card is re-queued, not dropped, so the objective returns the moment the bigger banner finishes.

**It deliberately does not use `pin()`.** A pin owns the hero slot outright — `if pinned or heroBlocked() then
enqueue(spec)` — so a standing objective would starve island arrivals and purchases for the whole length of a
quest. Re-pushing at REWARD gives the same always-on feel while staying rankable. The 1s tick sits under
NotifyCenter's 2s exact-repeat drop, so the card refreshes before expiring and reads as continuous.

Matched by the `"Objective"` name suffix, so a twelfth quest banner is caught for free. `ObjectiveHUD` (a stub
here) and `FreezeHUD` are deliberately not matched — both sit below the band, and FreezeHUD's ScreenGui also
holds a progress bar.

## API

```lua
local Notify = _G.NotifyCenter          -- or require(script.Parent.NotifyCenter)

Notify.push({
    top      = "🍭 WELCOME TO",         -- optional kicker line
    text     = "GUMDROP GROVE",         -- the headline (required)
    sub      = "Watch the taffy.",      -- optional third line; grows the card to 92
    color    = Color3.fromRGB(...),     -- per-banner accent (border glow + gradient)
    priority = Notify.PRIORITY.ISLAND,
    duration = 4,
    lane     = "social",                -- optional: force the small top-left lane
    sound    = function() ... end,      -- optional, fired on show
    onDone   = function() ... end,      -- optional, fired when it leaves
})

Notify.pin("watering", { text = "Fill the can at the water tank" })  -- standing instruction
Notify.unpin("watering")

Notify.isBusy()    -- is the hero slot occupied
Notify.isPinned()  -- is a pin holding it
Notify.pillSpot()  -- where a countdown pill should sit, under the card
```

## Compatibility

`_G.NotifyCenter` is still published, so all **~75 existing call sites across 24 scripts** keep working with no
edits. The module table is a strict superset of the old one:

| | Old script | Module |
|---|---|---|
| `push`, `PRIORITY`, `isBusy` | yes | yes |
| `pin`, `unpin`, `hold`, `release`, `pillSpot`, `isPinned` | **no** | yes |

## Theme

Space's navy starfield became a candy palette in `CandyTheme.luau`:

| Field | Value | |
|---|---|---|
| `Panel` | `58, 26, 54` | deep raspberry |
| `PanelStroke` | `255, 138, 196` | candy-pink edge |
| `TextPrimary` | `255, 248, 242` | warm cream |
| `TextMuted` | `226, 178, 206` | soft sugar pink |
| `NeonCyan` | `255, 122, 190` | **default accent.** Name inherited from the Space original so the banner module is a byte-identical port apart from the module name — read it as "the accent". |
| `StarfieldFill` | `44, 18, 42` | cocoa-plum, the fill the sprinkles sit on |

---

# 2. Mini events

## What was wrong

Candy already had the **entire presentation half** — `EventClient.client.lua` is ~2,000 lines of banners, glow
pulses, wind streaks, screen shake, storm fog, meteor visuals and a countdown pill. All finished. All
unreachable. **Three independent breaks, any one of which was enough on its own:**

1. **Nothing ever fired an event.** In the Food realm the pool + loop live inside `PlayerStats.server.lua`, which
   Candy does not have. No equivalent was ever written here.
2. **The remote did not exist.** Food declares `ServerEventNotify` in its `default.project.json`; Candy's project
   file folder-syncs `src/` and declares no remotes. `MusicDucking.client` sat on a 30s `WaitForChild` for it and
   always timed out.
3. **The client handler never connected.** `EventClient` read `_G.ServerEventNotify`, which Food's `CoreClient`
   publishes — Candy has no CoreClient, so that global was always `nil` and the whole `if ServerEventNotify then`
   block was skipped at load.

## The fix

| File | Change |
|---|---|
| `src/server/ServerEvents.server.lua` | **New.** Creates the remote, owns the pool, runs the loop. |
| `src/client/EventClient.client.lua` | Resolves the remote itself (global first, then ReplicatedStorage) instead of depending on a script this realm does not have. |

## The pool

| Internal name | Shown as | Duration |
|---|---|---|
| `FART_STORM` | 💨 SUGAR RUSH | 7s |
| `COIN_RUSH` | 💰 COIN RUSH — double coins | 7s |
| `LOW_GRAVITY` | 🌙 HIGH GRAVITY | 10s |
| `POWER_SURGE` | ⚡ POWER SURGE | 20s |
| `RING_FEVER` | 🎯 RING FEVER | 30s |

⚠ **The internal `name` is not cosmetic.** `EventClient` branches on those exact strings; changing one turns the
event into a generic banner with no mechanics, because the branch stops matching. `dispName` and `msg` are the
only fields safe to reword.

`LOW_GRAVITY` displaying as "HIGH GRAVITY" is inherited from Food and intentional — the key stays because that is
where the speed and gas-drain multipliers hang.

`THUNDERSTORM` / `WINDSTORM` are deliberately **not** in this pool. `EventClient` treats those as big events with
their own early-return branches (they take over the sky, delete the Atmosphere, swap in fog), and Food schedules
them separately. Putting them on the 4-minute mini-event timer is not what the client expects.

## Timing

First event at **240s**, then one every **240s**. `END` is broadcast `duration + 2s` after the start.

## Wire format

Unchanged from Food, because Candy's `EventClient` is a copy of Food's and already parses it:

```lua
ServerEventNotify:FireAllClients(name, displayName, durationSeconds, message, color)
ServerEventNotify:FireAllClients("END", "", 0, "", white)
```

`workspace:SetAttribute("ActiveServerEvent", name)` is also set, so **server** scripts can react without a remote
of their own. It is `""` when idle, never `nil`.

## Tuning

At the top of `ServerEvents.server.lua`:

```lua
DISABLE_EVENTS   = false   -- silence everything without deleting anything
FIRST_EVENT_WAIT = 240
BETWEEN_EVENTS   = 240
END_GRACE        = 2
```

Each pool entry has a `weight`. Food's own picker ignores its weight column and picks uniformly; this one
actually uses it, so tuning a weight here does something. With all weights equal the behaviour matches Food.

## Firing one on demand

```lua
_G.fireCandyEvent("COIN_RUSH")
```

Goes through the same path as the scheduler, so a hand-fired event can never behave differently from a scheduled
one. Returns `false` if an event is already running or the name is unknown.
