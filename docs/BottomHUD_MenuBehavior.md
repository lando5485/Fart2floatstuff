# Bottom HUD vs. Menus — How the Fart Meter & Bottom Buttons Behave When UI Pops Up

This documents how the bottom-center HUD stack (gut pill / gas "fart" meter / fart button)
interacts with menus, popups, and overlays: who hides it, who restores it, and why it can
never get stuck hidden.

---

## 1. What the bottom stack IS

One ScreenGui: **`BottomStackGui`** (built in `CoreClient.client.lua:1317`).
Inside it, one frame **`BottomStack`** anchored bottom-center (`AnchorPoint 0.5,1`,
`Position 0.5,1,-12`), with a vertical `UIListLayout` (Padding 8, bottom-aligned) holding
exactly three elements:

| LayoutOrder | Element | Look |
|---|---|---|
| 1 (top) | **Stomach / gut pill** | pink pill 300x40, per-tier gut emoji + gut name |
| 2 (middle) | **Gas meter** ("fart meter") | blue box 480px wide, gold "GAS METER" title, green fill bar + % |
| 3 (bottom) | **Fart button** | green 480x62 "HOLD TO FART!" / "BUY FOOD FIRST!" |

Because all three live in ONE ScreenGui, **`BottomStackGui.Enabled` is the single on/off
switch for the whole bottom HUD.** Nothing hides the pieces individually.

- `BottomStackGui` is `DisplayOrder 5`, `IgnoreGuiInset = true`.
- `_G.gui.bottomStack` is shared so other scripts (menu locker, Pet Hub) can read the
  stack's real top edge for their own layout.
- `BottomHUD_AllInOne.client.lua` and `JustButtons_AllInOne.client.lua` are **cosmetic
  standalone copies** of this stack for Studio drops — they are not the live wiring.
- `GasMeterGui`, `FartButtonGui`, `StomachGui` are **legacy leftover ScreenGuis** (the real
  meter is inside BottomStackGui). They still appear in hide-lists so stale copies can't
  pop back on screen.

## 2. The DisplayOrder ladder

| Layer | DisplayOrder |
|---|---|
| Bottom HUD (`BottomStackGui`) | 5 |
| Main menus (shop, pet hub, etc.) | 100 |
| Bottom HUD **pinned over the food stand** | 105 |
| Crate / Daily-Rewards reveal overlay | 120 |

So by default any open menu draws over the HUD, and the crate reveal draws over everything.

## 3. Who decides: two layers

### Layer A — `_G.MainMenuManager` (the mutual-exclusivity manager)

A tiny shared table on `_G`, created by a **guarded factory** — an identical
`if not _G.MainMenuManager then ... end` block exists in `CoreClient.client.lua:394`,
`ShopClient.client.lua:1141`, `Shop_AllInOne`, `PetFollow`, `PetHub_AllInOne`, and
`GardenerChat`; whichever script loads first creates it, everyone else reuses it.

API:
- `mgr.register(name, hideFn)` — every menu registers a "fully close me" function.
- `mgr.notifyOpened(name)` — called right **before** showing a menu. It (1) calls the
  hider of whatever other menu was open (so only ONE main menu is ever up — direct
  click-to-switch, no X needed), then (2) calls `mgr.setHud(false)`.
- `mgr.notifyClosed(name)` — clears `current`; when the **last** menu closes it calls
  `mgr.setHud(true)`.
- `mgr.setHud(visible)` — literally just `BottomStackGui.Enabled = visible`.

**Registered menus** include: FoodShop, Premium, Stomach, Pet Hub, Seasonal Pets, Rebirth,
Wormhole, Rewards hub, Gardener chat, and "More" (RailGuard registers a raw hider for the
MORE+ panel at `RailGuard.client.luau:219` so it can't stack under another menu).

So the baseline behavior is: **open any main menu → the fart meter, gut pill and fart
button vanish; close it (or switch to another and close that) → they come back.**

### Layer B — the BOTTOM-HUD AUTHORITY (the enforcer)

`CoreClient.client.lua:3623-3696`. History: ~a dozen scripts used to flip
`BottomStackGui.Enabled` by their own bookkeeping, and stale duplicate LocalScripts baked
into the place file run OLD copies of that logic — whoever wrote last won, and players got
stuck with no gas meter and no buy button.

The fix: **one loop, in the one script with no duplicate, re-asserts the correct state
4x/second.** A stale script can still write `Enabled = false`; it gets corrected a
quarter-second later.

Every 0.25s it computes:

```lua
menuOpen = MainMenuManager.current ~= nil and current ~= "FoodShop"
want     = not (menuOpen or anyHold() or roasting())
if g.Enabled ~= want then g.Enabled = want end
```

The HUD is off **only** while something real wants it off:

1. **A main menu is open** (`MainMenuManager.current`), *except the food stand* — see §4.
2. **A named hold is claimed** via `_G.hudHold(tag, true)` — see below.
3. **You are genuinely roasting** — holding the "Marshmallow Stick" tool AND within 45
   studs of a workspace `Campfire` model. Both, not either (holding alone meant walking
   off with the stick left the HUD gone forever).

Anything else and the bottom buttons come back, whoever turned them off.

The loop stands down in two cases: before `hudRevealed` (LoadingScreen pre-spawn hides all
game GUIs and restores their intended state on reveal) and while a `GardenIntro*`
ScreenGui exists (the garden cinematic owns the whole screen and restores the HUD itself).

### `_G.hudHold(tag, on)` — named reasons to keep the HUD hidden

`_G.hudHolds` is a set of tags; `anyHold()` is true if any tag is claimed. Current users:

- **`"MeteorCrate"`** — `CrateClient.client.luau:496`: the daily-rewards / crate reveal
  claims a hold for the whole reveal (picker modal + reward popup), otherwise the
  authority would re-enable the bottom buttons straight over the modal 0.25s in.
- **`"Campfire"`** — `Campfire.client.luau:151`: deliberately does **not** touch
  `Enabled` itself (stale duplicates of that file exist); it only declares the reason.
  The authority runs the same stick-AND-near-fire test itself, so the restore happens
  even if the whole script is shadowed by a stale copy.

**Rule: a script that wants the HUD hidden should claim a hold (or join MainMenuManager),
never write `BottomStackGui.Enabled` directly — the authority will overwrite a bare write
within 0.25s.**

## 4. The exceptions, one by one

### Food stand (FoodShop) — the HUD STAYS UP, and gets pinned on top

You need the gut pill, gas meter and BUY FOOD button to actually use the stand, so:

- The authority loop explicitly excludes `"FoodShop"` from `menuOpen`.
- `standHudPin(on)` in `ShopClient.client.lua:1172` re-enables `BottomStackGui` and raises
  its DisplayOrder **5 → 105** (above the shop's 100, below the crate reveal's 120),
  because re-enabling alone would leave it drawn underneath the shop.
- The previous DisplayOrder is stashed in an **attribute** (`HudOrderBeforePin`), not a
  local, so the unpin is still correct if the stand closes by a path the function never
  saw (respawn, teleport, another menu stealing focus). The FoodShop hider registered
  with MainMenuManager also calls `standHudPin(false)`, so closing by ANY route unpins.

### Crate / Daily-Rewards reveal — hides HUD, remembers exact prior state

`CrateClient.client.luau:484-517`: hides `BottomStackGui` **plus** the legacy
`GasMeterGui` / `FartButtonGui` / `StomachGui`, recording each GUI's prior `Enabled` and
restoring exactly that on close. The left sidebar (SidebarGui) deliberately stays visible.
Also claims the `MeteorCrate` hud-hold (see above) for BottomStackGui, since only that one
is arbitrated by the authority.

### Gardener chat — behaves like a main menu

`GardenerChat.client.lua:234-267`: registers as `"Gardener"` and drives
`notifyOpened`/`notifyClosed` off the panel's `Visible` property changing — so the HUD
always restores no matter HOW the chat closes (X, "Bye!", another menu opening, or the
walk-away safety closing it when the prompt hides).

### Campfire roasting — hold-declared, authority-enforced

Covered above: the HUD hides only while holding the stick AND near a fire (≤45 studs).

## 5. Guards that must NEVER touch the bottom HUD

Two janitor scripts sweep PlayerGui for stray/stale UI, and both carry explicit skip-lists
containing the bottom HUD:

- **`RailGuard.client.luau:40`** — `NEVER_TOUCH` includes `BottomStackGui`, `GasMeterGui`,
  `FartButtonGui`, `StomachGui` (plus Sidebar/Coin/RightPanel/Settings). RailGuard hides
  "rail-shaped" square buttons anywhere else; without the skip-list it would eat HUD tiles.
- **`MenuBackdropGuard.client.lua:52`** — `HUD_GUIS` skip-list. This is load-bearing, not
  tidiness: the fart button's click area is a full-size **invisible TextButton**, and when
  the viewport briefly reads wrong (join, rotate, app-resume) it measures as "full-screen
  input-sinking backdrop" and would get hidden — killing the fart button, which on a phone
  IS the game.

If you add a new sweeping/guard script, copy these skip-lists.

## 6. Mobile scaling & text

- `_G.MOBILE_SHRINK` (`CoreClient.client.lua:1705`): on phones `BottomStackGui` gets an
  extra **0.72** multiplier on top of the base 0.60 scale (≈0.43 of authored size).
- `applyScaling` / `_G.applyHudScaling` puts a `UIScale` on each top-level element
  (scaling around its own anchor, so the bottom-anchored stack stays glued to the bottom
  edge) and force-sets `TextScaled = true` on every label — opt out per-element with the
  `NoTextSweep` attribute.

## 7. Fart button text states (for completeness)

The flight loop drives the button's look; the states are:

- **Idle, has food:** green, "TAP TO FART!" / "HOLD TO FART!"
- **Farting:** brighter green, "FARTING! (TAP TO STOP)"
- **No food / power 0:** grey, "BUY FOOD FIRST!", `Active = false`

The gas meter fill = `gasMeter / 100` (green bar + centered %), where
`gasMeter = (currentPower / stomachMax) * 100` and drains at 4/sec in flight.

## 8. Cheat sheet — adding a new menu or overlay

1. **Full main menu** (should close others, hide bottom HUD):
   `_G.MainMenuManager.register("MyMenu", fullHideFn)`, call `notifyOpened("MyMenu")`
   right before showing, `notifyClosed("MyMenu")` on every close path.
2. **Overlay that just needs the bottom HUD out of the way** (modal, cutscene):
   `_G.hudHold("MyTag", true)` on open, `_G.hudHold("MyTag", false)` on close. Tie the
   release to a property/state that can't be skipped (like GardenerChat's `Visible` hook).
3. **Never** write `BottomStackGui.Enabled` directly as your mechanism — the authority
   re-asserts 4x/sec and will undo you (that's the point).
4. Menus close on their **X button only**, never on a backdrop tap (standing rule).
5. If your menu must coexist with the HUD (like the food stand), re-enable + raise
   DisplayOrder above your menu, stash the old order in an attribute, and restore it in
   your registered hider.
