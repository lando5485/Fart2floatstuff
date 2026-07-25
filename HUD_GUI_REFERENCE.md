# Fart to Float — Complete HUD / GUI Reference

Every button, size, position, open behavior, and sound in the on-screen HUD.
Source of truth: `src/client/CoreClient.client.lua` (live game) plus the two
verbatim self-contained clones `HUD_AllInOne.client.lua` and
`BottomHUD_AllInOne.client.lua`.

---

## Global setup (applies to everything)
- **Scale factor:** `scale = isMobile and 0.7 or 1.0` (phones shrink to 70%). Many sizes/text sizes are multiplied by `scale`.
- **UI click sound:** `rbxassetid://101638558691673`, Volume `0.5` — cloned & played on almost every button via `playUIClick()`.
- **Error / can't-afford sound:** `rbxassetid://87486053112716`, Volume `0.6` → `playErrorSound()`, paired with an 8px horizontal **button shake** (3 shakes, 0.04s each).
- **Shared images:** Coin `rbxassetid://106760789458573` · Gut/stomach `rbxassetid://108585083746103`.
- **Mutual exclusivity (`MainMenuManager`):** only ONE main menu (Premium Shop **or** Stomach Shop) can be open. Opening one auto-closes the other AND hides the whole bottom HUD (`BottomStackGui`) until it closes.

---

## 1) LEFT SIDEBAR — `SidebarGui` (ScreenGui, ResetOnSpawn=false)

Every button is built by `mkSideBtn(yOff, bgColor, iconTxt, label)`:
- **Frame:** `75×75 * scale`, Position `UDim2.new(0, 10, 0.5, yOff)` → pinned to far-left, **vertically centered** on screen (x=10px). Corner radius **14**, white stroke **2**.
- **Icon label:** top area, `TextSize 30*scale`, 56px tall, black stroke 1.
- **Text label** ("Label"): below icon at y=57, `GothamBold 12*scale`, white, black stroke 1.
- **Click:** a full-size transparent `TextButton` overlay covers the frame.

| Order | yOff | Label | Color (RGB) | Icon | Click action |
|---|---|---|---|---|---|
| 1 | `-90*scale` | **SHOP** | `50,180,50` green | 🛒 | `playUIClick()` → toggle **Premium Shop** (`PremiumShopGui`) |
| 2 | `0` | **WORMHOLE** | `140,86,226` purple | 🌀 | `_G.toggleWormhole()` (fallback: fire `OpenWormhole` BindableEvent). *Was INVITE/REBIRTH — var still named `inviteSide`.* |
| 3 | `90*scale` | **Stomach** | `80,170,70` green | GUT_IMAGE (40×40 image at top-center, y=6) | toggle **Stomach Shop** (`StomachShopGui`) |
| 4 | `180*scale` | **MORE** | `225,70,170` pink | `+` | toggle the **MORE+ popup** |

**Attention animations:**
- **Stomach button** wiggles `±8°` (0.32s Sine loop) whenever the next coin gut tier is **affordable** (`checkGutAfford`).
- **MORE button** shows a red **"!" dot** (18×18, top-right) and wiggles `±8°` whenever the daily crate is claimable **or** daily tasks are unfinished (polled every 1s).

---

## 2) MORE+ POPUP — `MoreMenuGui` (DisplayOrder 8)

- **Panel:** `196×206`, pink `225,70,170`, corner 14, white stroke 2. Appears **directly to the right** of the MORE button: `Position = (moreBtn.X + moreBtn.Width + 10, moreBtn.Y)`.
- **Header:** "MORE" FredokaOne 18 white + red **X** close (26×26, `210,60,55`).
- **Full-screen invisible "catcher"** behind it — click anywhere off the panel to close.
- **Rows:** scrolling list, each `full-width × 46`, cream `248,240,250`, corner 10. Emoji icon (30px, left) + label `GothamBold 18`, dark text `70,40,65`. Clicking a row: `playUIClick()` → close popup → run action.

Live entries (in order):

| Emoji | Label | Action |
|---|---|---|
| 🔄 | **Rebirth** | `_G.toggleRebirth()` |
| 🎁 | **Daily Rewards** (red dot when ready) | fires `OpenMeteorCrate` → opens Mystery Meteor Crate |
| 📋 | **Daily Tasks** (dot when pending) | `_G.toggleDailyTasks()` |
| 🐾 | **Pets** | fires `PetInvToggle` → pet inventory |
| 🐾 | **Seasonal Pets** | `openLocker()` |
| 🎫 | **Codes** | `_G.openCodesGui()` |
| 🎁 | **Free Rewards** | `_G.toggleSocialRewards()` |
| ⭐ | **Season Pass** | `_G.toggleSeasonPass()` |

---

## 3) RIGHT STATS PANEL — `RightPanelGui`

- **Panel** "RightPanel": `230×500`, Position `(1,-5, 0,85)`, Anchor `(1,0)` → top-right, just under the coin pill. Blue `30,90,200`, corner 16, white stroke 2, ZIndex 3.

**Stats section** (transparent, y=8, height 175, x-padding 8):

| Element | y | Text / style |
|---|---|---|
| Title | 0 | "⭐ STATS" gold `255,200,0`, TextScaled |
| Island | 36 | "🏝️ Island: 1" white 22 |
| Max Height | 76 | "🏆 Max Height: 0" white 22 |
| Space Realm title | 116 | "🚀 TO SPACE REALM" `190,210,255` |
| Progress bar | 142 (h=22) | bg `10,14,36`; fill `90,200,120` green, turns purple `170,110,255` at island 14; label "Island x/14 - y%". Driven by `HighestIsland` attribute over 14 islands. |

**Divider** at y=187 (white, 70% transparent).

**Three impulse/purchase buttons** (each full-width `-16`, x=8, height **90**, corner 12, white stroke 1.5, icon 60px on left, `playUIClick()` → `PromptProductPurchase`):

| Button | y | Color | Icon | Text | Product ID |
|---|---|---|---|---|---|
| **MID-AIR / RECHARGE** | 197 | `50,120,220` blue | ⚡☁️ | "39 R$" (green) | `3600303163` |
| **2X POWER / 1 HOUR** | 295 | `130,50,200` purple | ⚡ | "59 R$" | `3600302990` |
| **BIRD NUKE** | 393 | `200,50,50` red | 🐦💥 | "79 R$" | `3600303082` |

---

## 4) TOP-RIGHT COINS — `CoinGui` (IgnoreGuiInset=true)

- **Coin pill:** `180×46 * scale`, Position `(1,-10, 0,10)`, Anchor `(1,0)`. Gold `220,160,0`, corner 25, stroke `180,120,0` w3, vertical gold gradient.
- **Coin icon:** 30×30*scale image at x=8 (COIN_IMAGE).
- **Amount label:** `GothamBold 20*scale` white, left-aligned — live-mirrors `leaderstats.Coins`.
- **Green "+" button:** `34×34*scale`, `50,180,50`, corner 19 → `playUIClick()` + opens **Premium Shop** (same as SHOP button).

## Settings gear — `SettingsGui` (DisplayOrder 60)
- **Gear button:** `46×46`, dark `40,40,55`, corner 10, ⚙️ icon. Auto-tucks to the **immediate left of the coin pill** (recomputed whenever the pill moves/resizes).
- **Settings panel:** `260×150`, `30,30,45`, corner 12, white stroke; hidden until gear tapped.
  - **Title** "Settings" + red **X** close (30×30, `220,60,60`).
  - **Two toggle rows** (`makeToggleRow`): **Music** (y=46) and **Sound Effects** (y=96). Each has a 76×30 button: **ON** = green `50,190,70`, **OFF** = grey `120,120,130`.
  - SFX toggle mutes a shared `SoundGroup` (all non-music sounds route through it → one switch kills all SFX). Music toggle sets `_G.musicEnabled` and refreshes music volume.

---

## 5) BOTTOM-CENTER STACK — `BottomStackGui` (IgnoreGuiInset, DisplayOrder 5)

Container "BottomStack": 480 wide, Anchor `(0.5,1)` at `(0.5,0, 1,-12)`, `AutomaticSize=Y`, vertical `UIListLayout` (center-aligned, bottom, padding 8). Three elements share one center so they never drift:

**(1) Stomach / Gut pill** — LayoutOrder 1 (top)
- `300×40`, pink `220,80,180`, corner 20, stroke `140,20,100` w3.
- Gut **emoji** icon 32×32 on left (XL Gut swaps to GUT_IMAGE). Gut **name** text `FredokaOne` white, centered. Updated by `StomachUpdateEvent`.

**(2) Gas meter** — LayoutOrder 2 (middle)
- `480×85` (auto-tightened to hug content), blue `45,120,220`, corner 16.
- Gold **"GAS METER"** title `FredokaOne 17*scale`, black stroke.
- **Green fuel bar:** track transparent (empty shows blue), Fill `60,210,90` with a green gradient; centered white **"%"** readout. `setGas(pct)` sizes the fill 0–100.

**(3) Fart button** — LayoutOrder 3 (bottom)
- `480×62`, green `50,180,50`, corner 14, stroke `0,120,0` w4, green gradient.
- ☁ cloud emoji (left) + **"HOLD TO FART!"** `GothamBold 22*scale`.
- **States:** idle → green "TAP TO FART!" · flying → "FARTING! (TAP TO STOP)" · no food → grey "BUY FOOD FIRST!" (`Active=false`).

---

## 6) PREMIUM SHOP — `PremiumShopGui` (DisplayOrder 100, Enabled=false)

- Full-screen dim + centered panel `0.9×0.85`, blue `25,90,185`, corner 20, white stroke 3, clips.
- **Header** (65px, `15,60,140`): "🛒 SHOP" gold 30 + "Power up your farts!" subtitle + red **X** close (40×40).
- **Scrolling cards** `208×190` each (`20,70,160`, corner 16), laid out in section rows:

**⭐ GAMEPASSES:**
| Card | Sub | Price | Prompt |
|---|---|---|---|
| 2x Power ("BEST VALUE ⭐") | FOREVER | 249 R$ | Gamepass `1862015450` |
| Glitter Trail | PERMANENT | 49 R$ | Gamepass `1859714979` |
| 2x Power | 1 HOUR | 59 R$ | Product `3600302990` (shows active timer) |

**🎯 ONE-TIME ITEMS:**
| Card | Desc | Price | Prompt |
|---|---|---|---|
| Mid-Air Recharge | "Refills gas to 100%!" | 39 R$ | Product `3600303163` |
| Skip Island | "Jump to next island!" | 69 R$ | Product `3600303265` |
| Bird Nuke | "Unleash 30 birds on everyone!" | 79 R$ | Product `3600303082` |

Close → `Enabled=false` + notify MainMenuManager.

---

## 7) STOMACH SHOP — `StomachShopGui` (DisplayOrder 100)

- **Panel** `700×520`, blue `30,120,220`, corner 20, stroke `20,60,160` w3, centered (y offset −45).
- **Header:** gut icon (46×46, emoji or GUT_IMAGE for XL) + "STOMACH SHOP" `FredokaOne` gold + red **X** close (40×40).
- **"Current:" label** `Current: <tier> (<max> max power)`, blue pill, updates live.
- **Scroll list** of tier cards `full-width × 70` (`20,90,200`, corner 12): 52px icon + name `FredokaOne` + "<max> max power" + **buy button** `150×46`.

Buy button styling: **FREE** = grey `100,100,100` "✓ FREE" · **coins** = green `50,220,50` "🪙 <cost>" · **robux** = orange `255,160,20` "<cost> R$". Owned tiers → grey "✓ OWNED".

| Tier | maxPower | Cost | Currency |
|---|---|---|---|
| Tiny Gut 👶 | 100 | 0 | FREE |
| Small Gut 🧒 | 182 | 1,600 | Coins |
| Medium Gut 🐷 | 520 | 3,000 | Coins |
| Large Gut 🐘 | 1,075 | 5,200 | Coins |
| XL Gut 💪 (image icon) | 2,146 | 8,000 | Coins |
| Iron Gut 🏋️ | 3,218 | 11,000 | Coins |
| Infinite Gut ♾️ (pinned to top) | 9,999 | 499 R$ | Gamepass `1860686821` |

Buy fires `BuyStomachEvent:FireServer(maxPower, cost)`. If you can't afford → **error sound + button shake**.

> ⚠️ Note: these stomach numbers are the values **actually in the GUI code** and differ from the older table in `CLAUDE.md` (e.g. Small Gut is 182/1600 here vs 96/200 in the doc). The GUI is the live source of truth.

---

## Sound summary

| Sound | Asset ID | Volume | When |
|---|---|---|---|
| UI click | `rbxassetid://101638558691673` | 0.5 | Nearly every button press (`playUIClick`) |
| Error / can't afford | `rbxassetid://87486053112716` | 0.6 | Failed purchase (`playErrorSound`) + button shake |

## Product / Gamepass IDs

| Item | Type | ID |
|---|---|---|
| 2x Power (Forever) | Gamepass | 1862015450 |
| Glitter Trail | Gamepass | 1859714979 |
| Infinite Gut | Gamepass | 1860686821 |
| 2x Power (1 Hour) | Product | 3600302990 |
| Mid-Air Recharge | Product | 3600303163 |
| Skip Island | Product | 3600303265 |
| Bird Nuke | Product | 3600303082 |
