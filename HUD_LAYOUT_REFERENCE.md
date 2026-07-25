# Fart to Float — HUD Layout Reference (for cross-realm parity)

> Exact authored sizes/positions/colours of the main-screen HUD, pulled from
> `src/client/CoreClient.client.lua`. Rebuild these in the Space/Dino/Candy realms so the
> HUD looks identical everywhere. All values are at the **desktop scale of 1.0**.
> Verified: 2026-07-16.

**Global scale:** `local scale = isMobile and 0.7 or 1.0`. Any value written `N*scale` below is
shown at scale 1.0 (desktop). Device fitting for phone/tablet/iPad is handled separately by
`ResponsiveUI.client.luau` (one global UIScale) — do NOT bake phone shrink into these; keep the
authored sizes and let ResponsiveUI scale them.

---

## 1. Left side buttons — `SidebarGui` (4 buttons)

Built by `mkSideBtn(yOff, bgColor, iconTxt, labelTxt)`. Every button is identical in size/shape;
only colour, icon, label, and vertical offset differ.

**Per-button frame:**
- Size: `UDim2.new(0, 75, 0, 75)` — **75 × 75 px**
- Position: `UDim2.new(0, 10, 0.5, yOff)` — **X = 10 px from left edge**, Y = screen middle + `yOff`
- Corner radius **14**, white `UIStroke` thickness **2**
- Icon label: `TextSize 30`, Gotham, Size `(1,0,0,56)` Pos `(0,0,0,0)`, centered, black stroke 1
- Text label ("Label"): `TextSize 12`, GothamBold white, Size `(1,0,0,28)` Pos `(0,0,0,57)`, centered, black stroke 1
- Invisible click button fills the frame `(1,0,1,0)`, transparent

**The 4 buttons (top → bottom), stacked 90 px apart, centred on the screen's vertical middle:**

| Order | `yOff` | Colour (RGB)      | Icon         | Label     | Opens                              |
|-------|--------|-------------------|--------------|-----------|------------------------------------|
| 1     | **-90** | 50, 180, 50 (green) | 🛒          | SHOP      | `toggleMainMenu("Premium","PremiumShopGui")` |
| 2     | **0**   | 170, 90, 240 (purple)| 🔄          | REBIRTH   | `_G.toggleRebirth()`               |
| 3     | **90**  | 80, 170, 70 (green) | GUT_IMAGE*   | Stomach   | `toggleMainMenu("Stomach","StomachShopGui")` |
| 4     | **180** | 225, 70, 170 (pink) | +            | MORE      | More+ popup (`setMoreOpen`)        |

\* Button 3's icon is an **ImageLabel** (`_G.GUT_IMAGE`), Size `(0,40,0,40)`, Pos `(0.5,0,0,6)`,
AnchorPoint `(0.5,0)`, ZIndex 3 — overlaid in the icon area instead of an emoji.

So the 4 buttons sit at screen-Y offsets **-90, 0, +90, +180** from centre, all at **X = 10**.

---

## 2. Stats panel — `RightPanelGui > RightPanel`

Top-right blue panel. `IgnoreGuiInset = true`, ZIndexBehavior Sibling.

- **RightPanel:** Size `UDim2.new(0, 230, 0, 500)` (**230 × 500**), Position `UDim2.new(1, -5, 0, 85)`,
  AnchorPoint `(1, 0)` → top-right, 5 px in from the right edge, 85 px down. BgColor **30, 90, 200**,
  corner **16**, white stroke **2**.
- **statsSection** (holds the labels): Size `(1,-16,0,175)`, Pos `(0,8,0,8)`, transparent.
  - `⭐ STATS` title: Size `(1,-8,0,32)` Pos `(0,8,0,0)`, GothamBold **TextScaled**, gold **255,200,0**, left-aligned.
  - `🏝️ Island: N`: Size `(1,0,0,36)` Pos `(0,0,0,36)`, white, TextScaled, left-aligned.
  - `🏆 Max Height: N`: Size `(1,0,0,36)` Pos `(0,0,0,76)`, white, TextScaled.
  - `🚀 TO SPACE REALM`: Size `(1,0,0,22)` Pos `(0,0,0,116)`, colour **190,210,255**.
  - Progress bar bg: Size `(1,-2,0,22)` Pos `(0,0,0,142)`.
- Below the stats section the same panel also holds the flight **impulse buttons**
  (`MidAirBtn`, `TwoXBtn`, `BirdNukeBtn`) — stacked down the panel.

**Extra per-GUI scale used in `applyScaling`:** `RightPanelGui = 0.78`.

---

## 3. Bottom HUD — `BottomStackGui > BottomStack`

DisplayOrder **5**, `IgnoreGuiInset = true`. One centred vertical stack:
- **BottomStack:** AnchorPoint `(0.5, 1)`, Position `UDim2.new(0.5, 0, 1, -12)` (bottom-centre, 12 px up),
  Size `(0, 480, 0, 0)` with `AutomaticSize = Y`.
- **UIListLayout:** Vertical, HorizontalAlignment Center, VerticalAlignment Bottom, `Padding = 8`.

Three items by `LayoutOrder` (top → bottom of the cluster):

### 3a. Stomach pill — `StomachHud` (LayoutOrder 1)
- Size `UDim2.new(0, 300, 0, 40)` (**300 × 40**), ZIndex 10, BgColor **220, 80, 180** (pink),
  corner **20**, stroke **140, 20, 100** thickness **3**.
- `GutIcon` (emoji TextLabel): Size `(0,32,0,32)`, Pos `(0,6,0.5,0)`, AnchorPoint `(0,0.5)`, TextScaled, ZIndex 12.
- `GutIconImg` (ImageLabel, XL Gut only): same 32×32 slot, hidden otherwise.
- `StomachHudLabel`: Size `(1,-44,1,0)`, Pos `(0,40,0,0)`, FredokaOne **TextScaled** white, centred,
  black stroke 2. Text = current gut name.

### 3b. Gas meter — `gasMeterPanel` (LayoutOrder 2)
- Size `UDim2.new(0, 480, 0, 85)` → **tightened** at runtime to `(0, 480, 0, barTop+40+pad)`.
  BgColor **45, 120, 220** (blue), corner **16**. (Dark navy outline stroke exists but is DISABLED.)
- `GAS METER` title: FredokaOne `TextSize 17`, gold **255,215,0**, Size `(1,0,0,28)` Pos `(0,0,0,6)`, centred, black stroke 2.
- Bar track `gasBg`: Pos `(0,10,0,34)` → tightened to bar height **40** (`Size (1,-20,0,40)`), corner **17**, transparent track.
- Fill `gasFill`: green **60, 210, 90**, fills `(1,0,1,0)`, corner 17, ZIndex 2 (gradient flattened to solid green).
- `100%` power text: FredokaOne `TextSize 18`, white, centred, black stroke 2, ZIndex 3.

### 3c. "HOLD TO FART!" button — `fartBtnFrame` (LayoutOrder 3)
- Size `UDim2.new(0, 480, 0, 62)` (**480 × 62**), BgColor **50, 180, 50** (green), corner **14**,
  stroke **0, 120, 0** thickness **4**, green gradient (100,220,60 → 40,160,20, rotation 90).
- Cloud icon ☁: `TextSize 28`, Size `(0,55,1,0)` Pos `(0,12,0,0)`, left, ZIndex 3.
- Button text `HOLD TO FART!`: GothamBold `TextSize 22` white, Size `(1,-70,1,0)` Pos `(0,60,0,0)`, left-aligned, stroke 0,80,0 thickness 2, ZIndex 3.

### 3d. Flight stats (shown only while flying) — `flightStatsFrame`
- Parented INSIDE `gasMeterPanel`, Size `(0,130,0,140)`, Pos `(0,-12,0.5,0)`, AnchorPoint `(1,0.5)`
  → sits just to the LEFT of the gas meter and scales with it. BgColor 30,100,200 @ 0.1 transparency, corner 12, white stroke 2.
- Rows `📏 Height`, `💍 Rings`, `⏱ Air` — each Size `(1,-10,0,38)`, stacked at Y 6 / 48 / 90, GothamBold TextSize 12.

**Extra per-GUI scale used in `applyScaling`:** `BottomStackGui = 0.72`.

---

## 4. How menus open (panels + behaviour)

- **Standard menu panel size = 700 × 520, centred.** Used by Pet Hub (`PetInventoryUI`),
  Daily Tasks, Season Pass, Rebirth, Social/Free Rewards, Stomach Shop. The main **Shop is larger,
  ~770 × 572**. Each menu is its OWN ScreenGui: a dark full-screen dim backdrop + a centred panel
  (corner ~26, thick outline), and its content scrolls inside.
- **Mutually exclusive:** opening any full menu closes the others (`toggleMainMenu` / the `_G.toggle*`
  functions), so only one is ever open.
- **HUD hides while a menu is open:** `mgr.setHud(false)` disables `BottomStackGui`, `SidebarGui`,
  `CoinGui`, `RightPanelGui`, `StomachGui` on popup-open, and re-enables them on close — so the
  bottom cluster + side rail + stats + coin don't show behind a panel.
- **Coin pill** (`CoinGui`) sits top-right near the settings gear (separate ScreenGui); the gear is
  the Roblox top-right area. (Not sized here — it's a small pill; keep it top-right for parity.)

---

## 4b. Coin pill — `CoinGui`

- ScreenGui `IgnoreGuiInset = true`.
- `coinPill`: Size `UDim2.new(0, 180, 0, 46)` (**180 × 46**), Position `UDim2.new(1, -10, 0, 10)`,
  AnchorPoint `(1, 0)` → top-right, 10 px in from right, 10 px down. BgColor **220, 160, 0** (gold),
  corner **25**, stroke **180, 120, 0** thickness **3**, gold gradient (255,190,20 → 200,140,0, rot 90).
- Inside: a coin **ImageLabel** (`_G.COIN_IMAGE`) on the left + the amount TextLabel.
- Extra per-GUI scale in `applyScaling`: `CoinGui = 0.78`.

## 4c. Flight impulse buttons (inside the Stats panel, below the stats)

All three are children of `RightPanel`, full width, **90 px tall**, 8 px in from the left, stacked
98 px apart. A 2 px divider sits above them at Y 187.

| Button        | Size            | Position          | Colour (RGB)   |
|---------------|-----------------|-------------------|----------------|
| Divider       | `(1,-16,0,2)`   | `(0,8,0,187)`     | white @0.7     |
| `MidAirBtn`   | `(1,-16,0,90)`  | `(0,8,0,197)`     | 50, 120, 220   |
| `TwoXBtn`     | `(1,-16,0,90)`  | `(0,8,0,295)`     | (its own)      |
| `BirdNukeBtn` | `(1,-16,0,90)`  | `(0,8,0,393)`     | (its own)      |

Each button: corner **12**, white stroke **1.5**; a **60 × 60** icon on the left at `(0,8,0.5,0)`
anchor `(0,0.5)`; a title `TextSize 20` TextScaled at `(0,76,0,8)` size `(1,-76,0,28)`; a subtitle
below at `(0,76,0,38)`.

## 4d. MORE+ popup — `MoreMenuGui`

- ScreenGui DisplayOrder **8**. A full-screen transparent `catcher` button closes it on tap-outside.
- `panel`: Size `UDim2.new(0, 196, 0, 206)` (**196 × 206**, ~3 entries tall), BgColor **225, 70, 170**
  (pink), corner **14**, white stroke **2**, 8 px UIPadding all sides.
- Header: 28 px tall, `MORE` FredokaOne `TextSize 18` white left-aligned; close `X` button **26 × 26**
  at top-right `(1,-26,0.5,0)` anchor `(0,0.5)`, red **210, 60, 55**, corner 8.
- `EntryList` ScrollingFrame: Position `(0,0,0,36)`, Size `(1,0,1,-36)`, transparent, ScrollBarThickness
  **6** gold **255,215,0**, `AutomaticCanvasSize = Y`, UIListLayout padding **8**. The 5 entries overflow
  → it scrolls.

## 4e. Top-centre banners + wind indicator

All bottom values off-screen until shown (Position Y negative / hidden), AnchorPoint `(0.5, 0)`.

| Element (ScreenGui)        | Size          | BgColor (RGB)   | Corner | Stroke            |
|----------------------------|---------------|-----------------|--------|-------------------|
| Arrival `arrivalFrame`     | **500 × 65**  | 100, 200, 100   | 16     | white, 3          |
| Announce `announceFrame`   | **500 × 65**  | 255, 200, 0     | 20     | 200,150,0, 2      |
| Server Event `seBannerFrame` | **500 × 80** | 30, 100, 200   | 20     | white, 3          |
| Wind `windIndicatorFrame`  | **150 × 36**  | 30,100,200 @0.2 | 18     | white, 2          |

Arrival/Announce/ServerEvent hidden at `Position (0.5,0,0,-100..-130)`; Wind at `(0.5,0,0.35,0)`
anchor `(0.5,0.5)` (mid-screen). Text lines are TextScaled/centered inside each.

---

## 5. Quick rebuild checklist for another realm

1. `SidebarGui` — 4 buttons, 75×75, X=10, Y-offsets -90/0/90/180, colours + icons per §1.
2. `RightPanelGui > RightPanel` — 230×500, anchored top-right `(1,-5,0,85)`, blue, stats rows per §2.
3. `BottomStackGui > BottomStack` — bottom-centre, width 480, UIListLayout padding 8, three items:
   stomach pill 300×40 (LO1), gas meter 480×~85 (LO2), fart button 480×62 (LO3).
4. Menus open centred at **700×520** (shop 770×572), one at a time, HUD hidden while open.
5. Add `ResponsiveUI.client.luau` (from `DinoRealm_ResponsiveGUI.zip`) so it all fits phone/PC/iPad.

> Note: the icons here use the SAME `_G.GUT_IMAGE` / `_G.GUT_EMOJI` tables — if the other realm
> doesn't define those globals, substitute its own gut art or plain emoji so the pill/button icons render.
