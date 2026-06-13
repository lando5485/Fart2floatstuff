# Fart to Float — Complete GUI Spec (for visual recreation)

> A faithful, value-exact reference of every on-screen GUI in **Fart to Float (FtF)**, written so you can paste it into another game's chat (e.g. **Space Realm**) and rebuild the look. All values are quoted from the FtF client source. Roblox Luau.

---

## HOW TO RECREATE IN ANOTHER GAME

**Transfers as-is (pure visual — copy the values, no logic needed):**
- Every panel/frame/button: `Size`, `Position`, `AnchorPoint`, `BackgroundColor3`, `BackgroundTransparency`, `UICorner`, `UIStroke`, `UIGradient`, fonts, `TextSize`, colors, `ZIndex`, `DisplayOrder`.
- Layouts: `UIGridLayout` / `UIListLayout` cell sizes, padding, sort order.
- Built-in Roblox assets (`rbxasset://...` textures/icons) and old public library asset IDs (the `1316045217` shadow, the `9xxxxxxx` SFX) generally work in any game.
- The minigame *mechanics* are self-contained (tap-to-fill, stop-the-marker, keep-in-zone) — rebuild the panel + the per-frame loop; nothing game-specific.

**Needs RE-WIRING to your game's systems (logic, not visuals):**
- Anything that fires a **RemoteEvent / RemoteFunction** (named like `BuyFoodEvent`, `BuyStomachEvent`, `PetClaimEvent`, `PetFishRollEvent`, `SelectIslandEvent`, `CoinEvent`, …). Point these at your own systems.
- **`_G.*` reads** (`_G.foods`, `_G.leaderstats`, `_G.peakHeight`, `_G.COIN_IMAGE`, `_G.GUT_IMAGE`, `_G.playUIClick`, `_G.BuyFoodEvent`, …). Replace with your own data/currency.
- **Marketplace IDs** (product/gamepass) — swap for yours.
- **Custom uploaded image assets** (coin `106760789458573`, gut `108585083746103`, bean `133231198126712`, loading bg `127983055545494`, menu bg `111075648402081`) are owned by the FtF creator; re-upload your own equivalents (IDs only work cross-game if the asset is public).
- Server-authoritative gating (pet catch roll/pity, stomach purchase validation) lives server-side — re-implement on your server.

**Conventions used below:** colors are `Color3.fromRGB(r,g,b)` unless noted (`Color3.new(1,1,1)` = white). Positions/sizes are `UDim2.new(xScale,xOffset,yScale,yOffset)`. "corner N" = `UICorner CornerRadius UDim.new(0,N)`. Default font in newer screens is **FredokaOne**; older HUD uses **GothamBold**. Many CoreClient elements are created with one color then **restyled** by late IIFEs — the **final** value is what renders and is what's listed.

---

# 1. LOADING SCREEN + ISLAND-SELECT MENU
*File: `LoadingScreen.client.lua` — runs from ReplicatedFirst, instant on join.*

**ScreenGui `LoadingScreen`** — `IgnoreGuiInset=true`, `ResetOnSpawn=false`, `DisplayOrder=1000`, `ZIndexBehavior=Sibling`. Default Roblox loading screen is removed.

**Lifecycle:** join → background + progress bar fill (min **10s**, holds at 95% until assets+`game.Loaded`, then 100%) → **PLAY** button pops in at true 100% → click PLAY → island-select menu → click an unlocked island → fade out 0.45s → destroy.

### Background `Background` (ImageLabel, direct ScreenGui child)
- Anchor `(0.5,0.5)`, Position `fromScale(0.5,0.5)`, Size `fromScale(1,1)`, `BackgroundTransparency=1`.
- **Image `rbxassetid://127983055545494`**, `ScaleType=Crop`, `ZIndex=0`. (Logo/character/sky baked in.)

### Root `Root` (CanvasGroup)
- Full-screen, `BackgroundColor3 (135,206,250)`, `BackgroundTransparency=1`, `GroupTransparency=0` (used for whole-screen fade), `ZIndex=1`.

### Drop-shadow helper `makeShadow(target,parent,spread)`
- ImageLabel, **Image `rbxassetid://1316045217`** (soft rounded 9-slice shadow), `ImageColor3 (0,0,0)`, `ImageTransparency=0.5`, `ScaleType=Slice`, `SliceCenter=Rect.new(10,10,118,118)`, position nudged +6px down, `ZIndex=target.ZIndex-1`. Used for the bar (spread 14) and PLAY button (spread 16).

### Progress bar
- **`BarWrap` (Frame):** Anchor `(0.5,0.5)`, Position `fromScale(0.5,0.64)`, Size `fromScale(0.58,0.06)`, transparent, `ZIndex=5`.
- **`BarBg` (Frame):** full of BarWrap, `BackgroundColor3 (255,255,255)`, corner `UDim.new(1,0)` (pill), `UIPadding` 5px all sides, `ZIndex=6`.
- **`Fill` (Frame):** Anchor `(0,0.5)`, Position `(0,0,0.5,0)`, Size grows `(p,0,1,0)`, `BackgroundColor3 (70,215,85)`, corner `(1,0)`, `ZIndex=7`. **UIGradient** keypoints `0→(150,245,120)`, `0.5→(80,220,90)`, `1→(45,195,65)`, Rotation `25`. (Size set directly each frame, no tween.)
- **`PctPill` (Frame):** Anchor `(0.5,0.5)`, Position `fromScale(1,0.5)`, Size `(0.1,0,1.55,0)`, `BackgroundColor3 (22,34,70)`, corner `(1,0)`, UIStroke white 2, `ZIndex=9`. Child label `FredokaOne`, `TextScaled`, white, text `"<pct>%"`.

### "% LOADED" `Loaded` (TextLabel)
- Anchor `(0.5,0.5)`, Position `fromScale(0.5,0.72)`, Size `fromScale(0.6,0.07)`, transparent, `FredokaOne`, `TextScaled`, white, UIStroke black 3, `ZIndex=5`. Text **`"💥 <pct>% LOADED 💥"`** (💥 = bytes `\xF0\x9F\x92\xA5`).

### Rotating tip `Tip` (TextLabel)
- Anchor `(0.5,0.5)`, Position `fromScale(0.5,0.8)`, Size `fromScale(0.8,0.045)`, `FredokaOne`, `TextScaled`, `TextColor3 (45,120,255)`, UIStroke white 2. Cycles every 2.5s through:
  1. `"Bigger stomach = fly higher!"`  2. `"Land on islands to save progress!"`  3. `"Just TAP to fart!"`  4. `"Skip Island to leap ahead!"`

### PLAY button `PlayButton` (TextButton)
- Anchor `(0.5,0.5)`, Position `fromScale(0.5,0.88)`, Size `fromScale(0.23,0.12)`, `BackgroundColor3 (55,205,70)`, `AutoButtonColor=false`, corner `(1,0)`, `UIAspectRatioConstraint` ratio `3.4`, UIStroke white thickness 5 (Border mode). Hidden until true 100%.
- Child label `Label`: `FredokaOne`, `TextScaled`, white, UIStroke black 3, text **`"PLAY!"`**.
- Reveal: pop-in from `0.7x→1.0x` over 0.4s Quad. Hover `1.06x`, press `0.95x`. **Click → `playUIClick()` + `showMenu()`** (does NOT teleport directly).

### Island-select menu (after PLAY)
- **`MenuBackground` (ImageLabel, direct ScreenGui child):** full-screen, **Image `rbxassetid://111075648402081`**, `ScaleType=Crop`, hidden until menu. (Title "SELECT YOUR ISLAND" baked into image.)
- **`IslandCards` (Frame):** Anchor `(0.5,0.5)`, Position `fromScale(0.62,0.58)`, Size `fromScale(0.7,0.52)`, transparent, `ZIndex=11`. **UIGridLayout:** `FillDirectionMaxCells=7` (two rows of 7), `CellSize fromScale(0.13,0.46)`, `CellPadding fromScale(0.008,0.05)`, centered.
- **Island cards `Island1`…`Island14` (TextButton ×14):** corner `(0,14)`, UIStroke black 2.5, `ZIndex=12`.
  - **Unlocked** (`n<=highest`): `BackgroundColor3 (45,175,75)`; `Top`=`tostring(n)` white; `Bottom`=island name white.
  - **Locked**: `BackgroundColor3 (18,28,66)`; `Top`=`"🔒"` gold `(255,205,70)`; `Bottom`=`"Island n"`.
  - `Top` label: Anchor `(0.5,0)`, Pos `fromScale(0.5,0.05)`, Size `fromScale(0.9,0.52)`, `FredokaOne`, `TextScaled`, UIStroke black 2. `Bottom`: Anchor `(0.5,1)`, Pos `fromScale(0.5,0.95)`, Size `fromScale(0.94,0.4)`, `FredokaOne`, `TextScaled`, wrapped, UIStroke black 1.5.
  - **Click (unlocked) → `playUIClick()` + `chooseIsland(n)` → `SelectIslandEvent:FireServer(n)`** → fade + destroy.
- **Island names:** Bean Farm, Broccoli Bluff, Cabbage Cliffs, Turnip Tranquil, Coconut Cove, Bread Board, Pasta Peak, Popcorn Pinnacle, Milk Marsh, Butter Swamp, Ice Cream Isle, Burger Bluff, Burrito Barrens, Pizza Palms.

**Sound:** `UIClickSound` `rbxassetid://101638558691673` vol `0.5` (clone-and-play on PLAY + unlocked cards).

---

# 2. MAIN HUD
*File: `CoreClient.client.lua`. Scale: `scale = isMobile and 0.7 or 1.0`. An adaptive `UIScale` (`min(vp.X/1280, vp.Y/720, 1)`) is added to clusters and `TextScaled=true` forced on labels. All HUD ScreenGuis are created hidden and revealed on `CharacterAdded` (after island pick).*

**Global asset constants:**
| Global | Value | Use |
|---|---|---|
| `_G.COIN_IMAGE` | `rbxassetid://106760789458573` | gold coin icon |
| `_G.GUT_IMAGE` | `rbxassetid://108585083746103` | gut/stomach icon (XL tier + stomach button) |
| `_G.CHECK_IMAGE` | `rbxasset://textures/ui/LuaApp/icons/ic-check.png` | checkmark (built-in) |

## 2.1 Coin pill (top-right) — ScreenGui `CoinGui` (`IgnoreGuiInset`)
- **`coinPill` (Frame):** Anchor `(1,0)`, Position `(1,-10,0,10)`, Size `(0,200,0,52)` (repositioned), `BackgroundColor3 (255,180,0)`, corner `20`, UIStroke `(180,100,0)` thickness 3, `ZIndex=4`.
- **`CoinIcon` (ImageLabel):** Size `(0,30*scale,0,30*scale)`, Pos `(0,8,0.5,0)`, Anchor `(0,0.5)`, Image `_G.COIN_IMAGE`, `ScaleType=Fit`, `ZIndex=6`.
- **`Amount` (TextLabel):** Size `(1,-95,1,0)`, Pos `(0,44,0,0)`, `GothamBold`, `TextSize 20*scale`, white, left-aligned. Format: `"<n>"`, `"<n.n>K"` (≥1000), `"<n.n>M"` (≥1e6).
- **`coinPlusBtn` (TextButton):** Size `(0,34*scale,0,34*scale)`, Pos `(1,-42,0.5,0)`, Anchor `(0,0.5)`, `BackgroundColor3 (50,180,50)`, text `"+"` GothamBold 24 white, corner 19, UIStroke `(0,130,0)` 2. **Click → toggles `PremiumShopGui.Enabled`.**

## 2.2 Right stats panel + impulse buttons — ScreenGui `RightPanelGui` (`IgnoreGuiInset`, `ZIndexBehavior=Sibling`)
- **`RightPanel` (Frame):** Size `(0,230,0,500)`, Position `(1,-5,0,85)`, Anchor `(1,0)`, `BackgroundColor3 (30,140,255)`, corner `20`, UIStroke `(20,60,160)` thickness 3, `ZIndex=3`.
- **Stats section** (transparent, top): `statsTitle` `"⭐ STATS"` GothamBold 20 gold `(255,220,0)` TextScaled; `islandLabel` `"🏝️ Island: <n>"` GothamBold 22 white; `heightLabel` `"🏆 Max Height: <n>"` GothamBold 22 white; a 2px white divider transparency 0.7.
- **Three impulse buttons** (each Frame Size `(1,-16,0,78)`, corner 14, UIStroke thickness 3, icon TextLabel 60px + title/sub/price labels, green `(100,255,100)` price text):
  - **`MidAirBtn`** Pos `(0,8,0,197)`, `BackgroundColor3 (20,180,255)`, UIStroke `(20,80,180)`. Icon `"⚡☁️"`, title `"MID-AIR"`, sub `"RECHARGE"`, price `"39 R$"`. **Click → freeze if airborne + `PromptProductPurchase(player, 3600303163)`.**
  - **`TwoXBtn`** Pos `(0,8,0,295)`, `BackgroundColor3 (180,80,255)`, UIStroke `(80,30,140)`. Icon `"⚡"`, title `"2X POWER"`, sub `"1 HOUR"`, price `"59 R$"`. Has hidden `twoXTimerLabel` (`"⚡ %dm %02ds"` when active). **Click → `PromptProductPurchase(player, 3600302990)`.**
  - **`BirdNukeBtn`** Pos `(0,8,0,393)`, `BackgroundColor3 (255,60,60)`, UIStroke `(160,20,20)`. Icon `"🐦💥"`, title `"BIRD NUKE"`, price `"79 R$"`. **Click → `PromptProductPurchase(player, 3600303082)`.**

## 2.3 Left side buttons — ScreenGui `SidebarGui`
Each is a Frame `Size (0,95,0,95)` (STOMACH stays `0,110,0,110` row layout), corner 16, UIStroke thickness 3, an emoji/icon TextLabel (Gotham, `30*scale`, black stroke 1), a `Label` (GothamBold, `12*scale`, white, black stroke 1), and a full-size transparent TextButton. Stacked left-edge, vertically centered.
| Frame | Color (final) | Icon | Label | Click |
|---|---|---|---|---|
| `shopSideFrame` | `(50,220,50)`, stroke `(30,120,30)` | `"🛒"` | `"SHOP"` | toggles `PremiumShopGui.Enabled` |
| `inviteSideFrame` | `(180,80,255)`, stroke `(80,30,140)` | `"👥"` | `"INVITE"` | `SocialService:PromptGameInvite` |
| `dailySideFrame` (PETS) | `(80,170,70)`, stroke `(40,110,40)` | `"🐾"` | `"PETS"` | fires BindableEvent **`PlayerGui.PetInvToggle`** |
| `stomachSideFrame` | `(220,80,180)` | *(image)* | `"STOMACH"` | toggles `StomachShopGui.Enabled` |
- `stomachSideFrame` uses an ImageLabel `GutIcon` (Image `_G.GUT_IMAGE`, `ScaleType=Fit`, Size `(0,46*scale,0,46*scale)`, Pos `(0.5,0,0,5)`, Anchor `(0.5,0)`) instead of an emoji.
- Each click first calls `playUIClick()`.

## 2.4 Bottom-center stack — ScreenGui `BottomStackGui` (`IgnoreGuiInset`, `DisplayOrder=5`)
`BottomStack` (Frame): Anchor `(0.5,1)`, Position `(0.5,0,1,-12)`, Size `(0,480,0,0)` `AutomaticSize=Y`, transparent. **UIListLayout** vertical, centered, bottom-aligned, Padding `8`. Three rows (LayoutOrder 1/2/3):

**(1) Gut pill `StomachHud` (Frame):** Size `(0,300,0,40)`, `BackgroundColor3 (220,80,180)`, corner 20, UIStroke `(140,20,100)` thickness 3, `ZIndex=10`. `GutIcon` (emoji TextLabel or XL image), `StomachHudLabel` = current gut name (FredokaOne, TextScaled, white, black stroke 2).

**(2) Gas meter `gasMeterPanel` (Frame):** Size `(0,480,0,85)`, `BackgroundColor3 (20,140,255)`, corner 16, UIStroke `(20,40,120)` thickness 3.
- `gasTitleLabel` `"GAS METER"` FredokaOne `17*scale`, `TextColor3 (255,255,100)`, black stroke 2.
- `gasBg` (Frame): Size `(1,-20,0,32*scale)`, Pos `(0,10,0,36*scale)`, `BackgroundColor3 (20,20,80)`, corner 12.
- `gasFill` (Frame, Name `Fill`): width `(fill,0,1,0)`, `BackgroundColor3 (60,210,90)`, corner 12, `ZIndex=2`. **UIGradient** `0→(255,30,30)`, `0.5→(255,230,0)`, `1→(0,255,80)`, Rotation 90, `Offset=Vector2.new(-(1-fill),0)` (the bar reveals the green→red gradient as it drains).
- `gasPowerText` (TextLabel): `"<cur>/<max>"`, FredokaOne `18*scale`, white, black stroke 2, `ZIndex=3`.

**(3) Fart button `fartBtnFrame` (Frame):** Size `(0,480,0,62)`, `BackgroundColor3 (50,220,50)`, corner 16, UIStroke `(30,130,30)` thickness 4. **UIGradient** `0→(50,220,50)`, `1→(30,190,30)`, Rotation 90.
- `fartCloudLabel` `"☁"` GothamBold `28*scale` white, left.
- `fartBtn` (TextButton, transparent): Size `(1,-70,1,0)`, Pos `(0,60,0,0)`, `GothamBold`, `22*scale`, white, black stroke 2, left-aligned. Text states: **`"HOLD TO FART!"`** / **`"FARTING! (TAP TO STOP)"`** / **`"TAP TO FART!"`** / disabled grey `"BUY FOOD FIRST!"`. **Activated → `toggleFart()`** (`startFlying`/`stopFlying`).

## 2.5 Settings gear + panel
*File: `SettingsMenu.client.lua`.* ScreenGui `SettingsGui`, `DisplayOrder=60`, `IgnoreGuiInset`.
- **`SettingsGearBtn` (TextButton):** Size `(0,46,0,46)`, `BackgroundColor3 (40,40,55)`, gear icon GothamBold, corner 10, black stroke; repositioned at runtime to sit 8px left of the coin pill.
- **`SettingsPanel` (Frame):** Size `(0,260,0,150)`, `BackgroundColor3 (30,30,45)`, corner 12, white stroke, hidden until gear click. Title `"Settings"` GothamBold 20 left; red **X** `(220,60,60)` top-right.
- **Toggle rows** (40px tall): label GothamBold 16 + a `(0,76,0,30)` ON/OFF TextButton — green `(50,190,70)` "ON" / grey `(120,120,130)` "OFF". Rows: **Music** (`y=46`) and **Sound Effects** (`y=96`). Both default ON; local-only (routes SFX through a `GameSFX_LocalSettings` SoundGroup; toggles `_G.musicEnabled`).

---

# 3. FOOD SHOP
*File: `ShopClient.client.lua`. ScreenGui `FoodShopGui`, `ResetOnSpawn=false`, `Enabled=false` start, `DisplayOrder=100`. Opens automatically by proximity to a food stand (within `12` studs horizontal, `120` vertical, grounded, not flying); closes on walk-away or X.*

- **Dark film (Frame):** full-screen, black, `BackgroundTransparency=1` (invisible), `Active=true` (blocks HUD clicks).
- **`foodPanel` (Frame):** Size `(0,700,0,520)`, Position `(0.5,0,0.5,-45)` (nudged up 45px to clear the gut pill), Anchor `(0.5,0.5)`, `BackgroundColor3 (30,120,220)`, corner `20`, UIStroke `(20,60,160)` thickness 3.
- **`foodHeader` (Frame):** Size `(1,0,0,55)`, `BackgroundColor3 (15,60,140)`, corner 20. Title `"🏝️ ISLAND <n> FOOD STAND"` FredokaOne TextScaled gold `(255,220,0)` black stroke 2. Close `X` `(255,60,60)` FredokaOne, Size `(0,40,0,40)` Pos `(1,-45,0,7)`.
- **Left preview `foodLeftPanel` (Frame):** Size `(0,160,1,-80)`, Pos `(0,10,0,60)`, `BackgroundColor3 (20,90,200)`, corner 14, UIStroke white 2. Holds: featured food emoji (`FoodEmoji` 80px, greyed `0.5` if locked) or image (`FoodEmojiImg` Fit), `foodName` FredokaOne white (locked → `"<name>  🔒 LOCKED"` grey), price row (coin icon `_G.COIN_IMAGE` 22px + `foodPrice` `"<price> coins"` gold), `foodPower` `"+<power> power"` light green `(100,255,100)`.
- **BUY buttons (reparented to `foodPanel`):**
  - **`foodBuyBtn`** Size `(0,130,0,48)`, Pos `(0,10,1,-58)`, `BackgroundColor3 (50,220,50)`, FredokaOne white, corner 12, UIStroke `(30,130,30)` 2. States: `"BUY FOOD"` (green) / grey `"LOCKED"` / `"Not Enough Coins"` / `"Stomach Full"` / `"Not Enough Room"`. **Click → `_G.BuyFoodEvent:FireServer(foodName)`** + floating `"+<power> power!"` green text.
  - **`foodBuyMaxBtn`** Size `(0,130,0,48)`, Pos `(0,148,1,-58)`, `BackgroundColor3 (255,160,20)`, FredokaOne white, corner 12, UIStroke `(180,80,0)` 2. States: `"MAX x<n>"` / grey `"FULL"`/`"NO ROOM"`/`"LOCKED"`. **Click → loops `_G.BuyFoodEvent:FireServer` per unit** + `"MAX! +<total> power!"` orange text.
- **Right panel `foodRight` (Frame):** Size `(1,-190,1,-70)`, Pos `(0,180,0,60)`, `BackgroundColor3 (15,60,140)`, corner 12. Header `"ALL FOODS"` FredokaOne gold TextScaled.
- **`foodScroll` (ScrollingFrame):** `ScrollBarThickness 6`, `AutomaticCanvasSize=Y`. **UIGridLayout `foodGrid`:** `CellSize (0,95,0,75)`, `CellPadding (0,6,0,6)`, `SortOrder=LayoutOrder` (cell `LayoutOrder=food.island`).
- **Food cell (Frame, one per 14 foods):** `BackgroundColor3 (20,90,200)`, corner 10, UIStroke white 1.5. Children: emoji frame `(0,36,0,36)` (emoji or Bean image), `NameLabel` FredokaOne white black-stroke 2, `PriceIcon` (coin) `(0,18,0,18)`, `PriceLabel` FredokaOne gold `(255,220,0)`, full-cover transparent `BuyOverlay` button (`ZIndex 5`) that **features** the food.
  - **Locked cell:** bg `(180,180,180)`, stroke `(140,140,140)`, emoji `"🔒"`, name `"???"`, no price.
  - **Buyable:** bg `(50,200,50)`, stroke `(30,150,30)`. **Maxed/can't afford:** bg `(180,50,50)`, stroke `(120,30,30)`.
  - **Featured highlight:** UIStroke gold `(255,215,0)` thickness 4.
- **Food emojis:** Beans🥜 Broccoli🥦 Cabbage🥬 Turnips🌿 Coconuts🥥 Bread🍞 Pasta🍝 Popcorn🍿 Milk🥛 Butter🧈 IceCream🍦 Burger🍔 Burrito🌯 Pizza🍕. **Bean image override:** `rbxassetid://133231198126712` (scale 0.8).
- **Sound:** eat `rbxassetid://103794849233173` vol 0.8 on buy.

---

# 4. STOMACH UPGRADE SHOP
*File: `CoreClient.client.lua`. ScreenGui `StomachShopGui`, `Enabled=false` start, `DisplayOrder=100`. Opens via STOMACH side button, or auto on `StomachFullEvent` ("not_enough_room"/"stomach_full"). Closes via X.*

- **Dark film `bg` (Frame):** full-screen black, `BackgroundTransparency=1` (invisible), `Active=true`, `ZIndex=0`.
- **`stomachPanel` (Frame):** Size `(0,680,0,500)`, Position `(0.5,0,0.5,0)`, Anchor `(0.5,0.5)`, `BackgroundColor3 (30,120,220)`, corner 20, UIStroke `(20,60,160)` thickness 3.
- **Header:** `GutIcon` (emoji or XL image `_G.GUT_IMAGE`, `(0,46,0,46)`, Pos `(0,12,0,9)`); title `"STOMACH SHOP"` FredokaOne TextScaled gold `(255,220,0)` black stroke 2; close `X` `(255,60,60)` `(0,40,0,40)` Pos `(1,-48,0,8)` corner 8 UIStroke `(160,20,20)` 2; `currentStomachLabel` `"Current: <name> (<max> max power)"` (bg `(20,80,180)`, FredokaOne white, corner 10, white stroke).
- **`scrollFrame` (ScrollingFrame):** Size `(1,-20,1,-110)`, Pos `(0,10,0,105)`, `ScrollBarThickness 6`, `AutomaticCanvasSize=Y`. **UIListLayout** Padding 8, **UIPadding** L/R 4.
- **Tier card (Frame, one per tier):** Size `(1,0,0,70)`, `BackgroundColor3 (20,90,200)`, corner 12, UIStroke white 2. Icon (XL → image, else emoji, `(0,52,0,52)` Pos `(0,12,0.5,0)`), name FredokaOne white black-stroke 2, power label `"<max> max power"` / `"∞ Unlimited power"` light blue `(180,220,255)`, buy button `(0,150,0,46)` Pos `(1,-158,0.5,0)` FredokaOne white corner 10 black-stroke 2.
  | Tier | maxPower | cost | currency | buy bg | buy text |
  |---|---|---|---|---|---|
  | Tiny Gut | 100 | 0 | free | `(100,100,100)` | `"✓ FREE"` |
  | Small Gut | 182 | 1600 | Coins | `(50,220,50)` | `"🪙 1600"` |
  | Medium Gut | 520 | 3000 | Coins | `(50,220,50)` | `"🪙 3000"` |
  | Large Gut | 1075 | 5200 | Coins | `(50,220,50)` | `"🪙 5200"` |
  | XL Gut | 2146 | 8000 | Coins | `(50,220,50)` | `"🪙 8000"` |
  | Iron Gut | 3218 | 11000 | Coins | `(50,220,50)` | `"🪙 11000"` |
  | Infinite Gut | 9999 | 499 | **Robux** | `(255,160,20)` | `"499 R$"` |
  - **Owned** → buy bg `(80,80,80)` text `"✓ OWNED"`. **Click:** Robux → `PromptGamePassPurchase(player, 1860686821)`; coin → if short, `playErrorSound()` + shake, then `BuyStomachEvent:FireServer(maxPower, cost)`.
- **Gut emojis (HUD/shop):** Tiny👶 Small🧒 Medium🧑 Large🧔 Iron🦛 Infinite🐋; XL = the gut image.

---

# 5. BANNERS, TOASTS & MISC HUD
*File: `CoreClient.client.lua`.*

- **Arrival banner `arrivalFrame`** (ScreenGui `ArrivalGui`): Size `(0,500,0,65)`, slides from `(0.5,0,0,-100)` to `(0.5,0,0,10)` (Back ease), bg = per-island color, corner 16, white stroke 3. Line1 `"🏝️ Welcome to"` + `islandLabel` `"<Island name>!"` GothamBold white black-stroke. Auto-hide 3s. Plays island sound `rbxassetid://117464325212045` vol 0.8.
- **Announcement banner `announceFrame`** (`AnnounceGui`): Size `(0,500,0,65)`, bg `(255,200,0)`, corner 20, stroke `(200,150,0)` 2. Text `"🏝️ <name> reached <island>!"` GothamBold `(80,40,0)`. ~3.3s.
- **Server-event banner `seBannerFrame`** (`ServerEventGui`): Size `(0,500,0,80)`, slides to `(0.5,0,0,136)`, bg per-event, corner 20, white stroke 3. Line1 `"⚠ SERVER EVENT!"`, `seBannerLine2` = message, both white black-stroke. 4s.
- **Purchase banner** (`PurchaseBanner`, `IgnoreGuiInset`): `banner` Size `(0,500,0,60)` slides to `(0.5,0,0,10)` Back ease, bg `(255,200,0)`, corner 12, stroke `(200,150,0)` 3, `ZIndex 20`. Icon `"⭐"`/`"🎉"`, label `"<player> bought <item>!"` GothamBold `(80,40,0)`. Spawns 30 confetti frames (8–14px, `Color3.fromHSV`, corner 2, fall+fade 2s) + sound `rbxassetid://112825313814792` vol 0.8.
- **Wind indicator `windIndicatorFrame`** (`WindGui`): Size `(0,150,0,36)`, Pos `(0.5,0,0.35,0)`, bg `(30,100,200)` transp 0.2, corner 18, white stroke 2. Label `"💨 Wind →"` GothamBold 14 white.
- **Flight stats `flightStatsFrame`** (`FlightStatsGui`, parented inside `gasMeterPanel`): Size `(0,130,0,140)`, Anchor `(1,0.5)` (left of gas meter), bg `(30,100,200)` transp 0.1, corner 12, white stroke 2. Rows `"📏 Height: <y>"`, `"💍 Rings: <n> (x<mult>)"`, `"⏱ Air: <s>s"` GothamBold 12 white. Visible only while flying.
- **Return-to-island `ReturnBtn`** (`ReturnIslandGui`, `IgnoreGuiInset`): Size `(0,180*scale,0,56*scale)`, Pos `(0,130,0.5,0)`, Anchor `(0,0.5)`, bg `(255,150,0)`, GothamBold white, corner 14, UIStroke `(180,90,0)` 3, `ZIndex 8`. Text `"⬆ Return to Island <n>"`. **Click → `ReturnToIslandEvent:FireServer()`.**
- **Stomach-full popup** (`showFloatingText`): transient label GothamBold 22, Size `(0,300,0,50)`, Pos `(0.5,-150,0.5,0)`, floats up + fades 1.5s. `"⚠ Not Enough Coins"` / `"⚠ Not Enough Room!"` / `"⚠ Stomach Full! Buy a bigger gut!"` all `(255,100,100)`; the room/full variants also open the stomach shop.
- **Floating text helper** (`showFloatingText`): generic toast, default gold `(255,220,0)`. Examples in flight: `"+💨 GAS BOOST!"` `(0,255,100)`, `"+<bonus> 🪙 x<mult>"` `(255,215,0)`.
- **Effect flash `effectFlashFrame`** (`FlashGui`, `ZIndexBehavior=Global`): full-screen white, transparency-driven, `ZIndex 10`.

---

# 6. PET HUB (inventory) + PET QUEST UI
*File: `PetFollow.client.lua`.*

## 6.1 Pet Quest UI — ScreenGui `PetQuestUI`, `ResetOnSpawn=false`, `DisplayOrder=30`
- **(1) Landing hint `Hint` (TextLabel):** Anchor `(0.5,0)`, Position `(0.5,0,0.07,0)`, Size `(0,500,0,34)`, transparent, `FredokaOne`, `TextSize 22`, `TextColor3 (225,232,255)`, UIStroke black 2. Text e.g. **`"🐾 Pet Quest Available! See more in Pet Inventory"`**. Fades in 0.6s, holds 3s, fades out 1s. Fired once per island landing.
- **(2a) Discovery popup `Popup` (Frame):** Anchor `(0.5,0.5)`, Position `(0.5,0,0.4,0)`, Size `(0,300,0,110)`, `BackgroundColor3 (38,72,38)`, `BackgroundTransparency 0.05`, corner 16, UIStroke `(120,220,120)` thickness 3, hidden by default. `popTitle` FredokaOne 26 `(180,255,180)` `"Pet Search Active!"`; `popSub` FredokaOne 22 white `"<found>/<total> <Label> Found"`. Pops in (Back ease), then flies to the tracker after 2s.
- **(2b) Corner tracker `Tracker` (Frame):** Anchor `(1,0)`, Position `(1,-14,0,14)`, Size `(0,190,0,40)`, `BackgroundColor3 (28,52,28)`, `BackgroundTransparency 0.12`, corner 10, UIStroke `(120,220,120)` thickness 2, hidden by default. `trkIcon` (per-pet emoji, Gotham 22) + `trkLabel` FredokaOne 18 white left-aligned (`"<Label>: <found>/<total>"`, or the pet's "all found" message in `(255,240,130)`).
- **(3) Egg pointer `Pointer` (TextLabel):** Anchor `(0.5,0.5)`, Size `(0,60,0,60)`, transparent, `GothamBold`, `TextSize 46`, `TextColor3 (150,255,140)`, UIStroke black 2, Text `"➤"` (arrow). Tracks the egg's world position on screen, rotates to point, clamps to screen edge.

## 6.2 Pet Hub inventory — ScreenGui `PetInventoryUI`, `ResetOnSpawn=false`, `DisplayOrder=100`
Opened by the **PETS** side button (BindableEvent `PetInvToggle`). No dark film (`dim` Frame is transparent + `Active`, blocks HUD clicks; clicking it closes).
- **`panel` (Frame):** Size `(0,680,0,500)`, Position `(0.5,0,0.5,0)`, Anchor `(0.5,0.5)`, `BackgroundColor3 (25,90,185)`, `ClipsDescendants`, corner 18, UIStroke white thickness 3.
- **`header` (Frame):** Size `(1,0,0,60)`, `BackgroundColor3 (15,60,140)`, corner 18. Title `"🐾 PET HUB"` GothamBold 26 gold `(255,215,0)` black-stroke 2, left; subtitle `"Your pets & quest progress"` Gotham 13 white; close `X` `(220,50,50)` `(0,40,0,40)` Pos `(1,-48,0,10)` corner 8 black-stroke 2.
- **Two sections** (`makeSection(x,w,title)`): Frame Size `(0,w,1,-74)` Pos `(0,x,0,68)`, `BackgroundColor3 (18,66,150)` transp 0.25, corner 12, UIStroke `(10,40,100)` 2; section title GothamBold 16 gold left; inner ScrollingFrame `ScrollBarThickness 6` `ScrollBarImageColor3 (255,215,0)`.
  - **PETS section** `makeSection(12, 388, "🐾 PETS")` — **UIGridLayout `CellSize (0,176,0,158)`, `CellPadding (0,8,0,8)`, left-aligned.**
  - **QUESTS section** `makeSection(412, 256, "🗺 QUESTS")` — **UIListLayout** Padding 8; empty-state label `"Land on islands to discover pet quests!"` Gotham 13 `(200,220,255)` wrapped.
- **Owned pet card `buildPetCard` (Frame `(176×158)`):** `BackgroundColor3 (20,70,160)`, corner 10, UIStroke gold `(255,215,0)` thickness 3 if equipped else `(10,40,100)` thickness 1. Children: icon (per-pet emoji, GothamBold 30, y6); name (GothamBold 15 white, y46); level `"Lv L / M • EQUIPPED"` (GothamBold 12 gold, y64); **EQUIP/UNEQUIP** button `(1,-12,0,26)` y86, green `(50,200,50)` "EQUIP" / grey `(120,120,120)` "UNEQUIP" (corner 8, black-stroke 1) → `PetEquipEvent:FireServer(petId|false)`; **upgrade** button `(0.6,-7,0,24)` y116 — `"MAX"` grey / `"UPGRADE!"` orange `(255,140,0)` (→ `PetUpgradeEvent`) / `"Lv<n> 🔒"` blue `(40,80,150)`; **R$** button `(0.4,-5,0,24)` y116 green `(50,200,50)` → `PetPendingUpgrade` + `PromptProductPurchase`.
- **Locked slot `buildLockedSlot` (Frame):** `BackgroundColor3 (14,46,104)`, corner 10, UIStroke `(10,30,80)` 1. Big `"?"` GothamBold 46 `(70,100,170)`; `"🔒 Locked"` Gotham 12 `(130,160,220)`.
- **Quest entry `buildQuestEntry` (Frame `(1,-4,0,92)`):** `BackgroundColor3 (20,70,160)`, corner 8, UIStroke `(10,40,100)` 1. Island name (GothamBold 14 white); status (GothamBold 11): `"Done ✔"` green `(120,255,120)` / `"In Progress  <n>/<t> <unit>"` amber `(255,205,90)` / `"Available"` blue `(180,220,255)`; short desc (Gotham 11 `(205,222,255)` wrapped).

---

# 7. PET MINIGAMES
*File: `PetFollow.client.lua`. Each is a modal ScreenGui with a dim film `(0,0,0)` transparency 0.5 `Active=true`, and a blue panel `(25,90,185)` corner 16 + white UIStroke 3, gold FredokaOne/GothamBold titles. All `DisplayOrder=90`, `Enabled=false` until opened.*

## 7.1 Coconut crack (tug-of-war tap-fill) — ScreenGui `CoconutCrackGui`
- **`panel`** Size `(0,300,0,310)`, centered. Title `"CRACK THE COCONUT!"` GothamBold 20 gold; hint Gotham 13 white.
- **`coco` (TextButton):** Size `(0,150,0,150)`, Pos `(0.5,0,0.5,8)`, Anchor `(0.5,0.5)`, bg `(112,72,42)`, Text `"🥥"` TextSize 90 GothamBold, corner `(1,0)` (circle). Tapping fills the bar.
- **`cnt` (TextLabel):** Size `(1,-20,0,26)`, Pos `(0,10,1,-58)`, GothamBold 18 white.
- **`barBg` (Frame):** Size `(1,-20,0,14)`, Pos `(0,10,1,-26)`, bg `(15,40,90)`, corner 6. **`bar` (Frame):** fills `(fill,0,1,0)`, bg `(80,220,80)` (turns amber `(235,170,55)` below 0.5), corner 6.
- **Mechanic:** bar starts at 0.28, **holds steady until the first tap**, then drains (per-coconut rate) while each tap adds fill; reach top = crack. Difficulty hidden from player.

## 7.2 Popcorn film-reel (stop-the-marker) — ScreenGui `FilmReelSpinGui`
- **`panel`** Size `(0,360,0,240)`. Title `"STOP THE REEL!"` GothamBold 22 gold; hint Gotham 13 white `"Tap STOP when the marker is in the green zone!"`.
- **`track` (Frame):** Size `(1,-40,0,34)`, Pos `(0.5,0,0,98)`, Anchor `(0.5,0)`, bg `(15,40,90)`, corner 8.
  - **`zone` (Frame):** green `(70,210,90)` target band, corner 6 (width = difficulty fraction, random X).
  - **`marker` (Frame):** Size `(0,8,1,8)`, yellow `(255,230,80)`, corner 3, black stroke 1, `ZIndex 2` — sweeps left↔right.
- **`stop` (TextButton):** Size `(0,180,0,48)`, Pos `(0.5,0,1,-18)`, Anchor `(0.5,1)`, red `(220,60,60)`, `"STOP"` GothamBold 24 white, corner 10, black stroke 2. **`close` (TextButton):** `(0,30,0,30)` Pos `(1,-38,0,8)`, `(120,40,40)`, `"X"`.
- **Mechanic:** tap STOP while the marker is inside the green zone. Per-reel: zone shrinks `0.34→0.20`, speed `0.55→1.10` sweeps/sec across reels 1–6. Miss = keep going.

## 7.3 Butter fishing — reel-in (keep-in-zone) — ScreenGui `ButterReelGui`
- **`panel`** Size `(0,360,0,300)`. Title `"REEL IT IN!"` GothamBold 22 gold; hint Gotham 13 white `"HOLD to reel up - keep the fish in the green zone!"`.
- **`track` (Frame, vertical):** Size `(0,70,0,196)`, Pos `(0,40,0,76)`, bg `(12,34,76)`, corner 10.
  - **`zone` (Frame):** Size `(1,-8,0.26,0)`, green `(70,210,90)` transp 0.25, corner 6 — moves vertically (you hold to raise it; gravity drops it).
  - **`fish` (TextLabel):** `"🐟"` GothamBold 30, `ZIndex 3` — drifts up/down.
- **`pbBg` (Frame):** Size `(0,34,0,196)`, Pos `(1,-58,0,76)`, bg `(15,40,90)`, corner 8. **`pb` (Frame):** fills bottom-up `(1,0,progress,0)`, `(255,205,60)` (→ green `(120,235,110)` above 0.5), corner 8. Label `"CATCH"` GothamBold 12 `(255,225,120)`.
- **Mechanic:** HOLD anywhere raises the zone; keep the fish inside it to fill the CATCH meter (`+0.42/s` in-zone, `−0.26/s` out). Full = caught, empty = escapes. Tuned easy.

## 7.4 Fishing HUD (cast / bite / catch) — ScreenGui `ButterFishingHUD`, `DisplayOrder=88`
- **`status` (TextLabel):** Anchor `(0.5,0)`, Pos `(0.5,0,0.12,0)`, Size `(0,440,0,40)`, bg `(25,90,185)` transp 0.12, GothamBold 20 white, corner 10, UIStroke gold `(255,215,0)` 2. Shows `"Waiting for a bite..."`, `"Something's biting! TAP!"`, `"It got away!"`, `"You caught: <junk>!"`, `"You reeled in... an EGG! 🥚"`.
- **Tap-to-hook overlay** (`waitForTap`): full-screen TextButton bg `(255,120,40)` transp 0.8; big label `"TAP TO HOOK!"` FredokaOne 60 `(255,240,120)` UIStroke 3.
- **Junk popup:** centered emoji TextLabel (Pos `(0.5,0,0.42,0)`) pops 60→120px (Back ease) then fades. Junk→emoji: old boot🥾, butter blob🧈, rubber duck🦆, soggy sock🧦, tin can🥫, swamp weed🌿, flip-flop🩴, message in a bottle🍾.
- **World prompts** (ProximityPrompts): `"Grab Fishing Rod"` (barrel), `"Fish"` (over lake), `"Hatch"` (caught egg). **Catch roll is server-side via `PetFishRollEvent` (RemoteFunction).**

## 7.5 Cave Key reveal — ScreenGui `CaveKeyReveal`, `DisplayOrder=95`
- **`f` (Frame):** grows from `(0,40,0,24)` to `(0,260,0,150)` at Pos `(0.5,0,0.4,0)` Anchor `(0.5,0.5)`, bg `(25,90,185)` transp 0.05, corner 16, UIStroke gold `(255,215,0)` 3. Key `"🗝️"` TextSize 56 + `"You got the Cave Key!"` GothamBold 20 gold. Holds 2s, floats up + fades.

---

# 8. POPCORN MOVIE — SurfaceGui cinematic (on a 3D screen)
*File: `PetFollow.client.lua`. A ~30s cinematic that plays on the real `PopcornScreen` part, then HOLDS its final frame permanently.*

- **SurfaceGui `<pet>Movie`:** `Face` = the screen's player-facing broad face (auto-picked), `CanvasSize Vector2(600, 600*aspect)`, `LightInfluence=0`, `Brightness=2`, `ZOffset=0.05`, `Adornee` = the real screen part, **`Parent = PlayerGui`** (so it survives streaming; a 2s watcher re-points the Adornee). `ResetOnSpawn=false`.
- **`bg` (Frame):** full, `BackgroundColor3 (6,7,16)`, `ClipsDescendants`. A white `flash` overlay (`ZIndex 50`) for the flicker-on.
- **Scenes (tweened 2D shapes/text):** flicker-on → studio card **`"POPCORN PICTURES"` / `"presents"`** (gold `(255,226,150)`) with a 🍿 → title **`"FLUFF FROM ABOVE"`** (FredokaOne, gold `(255,216,0)`, glow UIStroke) + subtitle `"the legend of the popcorn sheep"` → cosmic journey (twinkling star Frames, drifting planets, a glowing ring/portal, comet w/ gradient tail, purple nebula, asteroid, a tumbling 2D egg with a sparkle trail) → lands on a popcorn-mountain silhouette → **`"A NEW FRIEND HATCHES!"`** (FredokaOne, gold `(255,236,150)`, glow) + a peeking sheep + ✨ sparkles. **Held forever**; on the player hatching, the egg graphic cracks off and the caption becomes **`"A NEW FRIEND HATCHED!"`**.
- Palette: deep space navy bg, warm gold text, soft pastel planets/nebula. Egg = rounded oval `(248,236,170)` with speckles + highlight.
- **Hook:** the reveal is synced to the real `PetClaimEvent` (server ownership) — re-wire to your own "pet obtained" signal.

---

# 9. SPECIAL-EVENT OVERLAY UIs (concise)
*Full-screen server-driven overlays. Each event banner is a top TextLabel (`Size (0.6,0,0.08,0)`, GothamBold, TextScaled, corner 12, shown at `BackgroundTransparency 0.2`) sharing a vertical-slot allocator so concurrent banners stack. Sky changes via ColorCorrection + Atmosphere + fog, restored on `"reset"`.*

- **Meteor `MeteorEventUI`** (`DisplayOrder 51`, RemoteEvent `MeteorSync`): banner bg `(40,12,12)` text `(255,220,180)`; `"METEOR SHOWER INCOMING!"`, `"LEGENDARY METEOR DETECTED!"`; impact camera shake; reward popup `+N Coins!` GothamBlack gold `(255,230,120)`. Vignette tint orange `(255,170,130)`, fog `(120,50,35)`.
- **UFO `UFOEventUI`** (`DisplayOrder 52`, `UFOSync`): banner bg `(18,30,22)` text `(170,255,190)`; `"UFO DETECTED ABOVE THE ISLANDS!"`; green lens-flare ImageLabel (`rbxasset://textures/ui/LuaApp/graphic/gradient_circle.png`, color `(150,255,170)`); white-green `bigFlash`. Vignette green, ClockTime 0.2 (night).
- **Ice Age `IceAgeEventUI`** (`DisplayOrder 53`, `IceAgeSync`): banner bg `(28,44,60)` text `(210,235,255)`; `"ICE AGE APPROACHING!"`; aurora bands (green/blue/purple), blue `blueFlash`. Vignette desaturated cold `(220,235,250)`, ClockTime 9 overcast.
- **Mutation `MutationEventUI`** (`DisplayOrder 54`, `MutationSync`): banner bg `(30,55,25)` text `(190,255,170)`; `"MUTATION EVENT ACTIVE!"`, `"ULTIMATE MUTATION!"`; toxic tint heartbeat-pulses green `(170,255,150)` ↔ purple `(190,140,255)`; green `greenFlash` + heat-blur.
- **Rocket `RocketEventUI`** (`DisplayOrder 50`, `RocketEventSync`): banner bg `(20,20,30)` text `(255,240,200)`; big center countdown TextLabel (Pos `0.5,0.35`, GothamBlack, `(255,90,60)`), `"🚀 LIFTOFF!"`; green `"Go to Island 1"` button `(55,170,90)` Pos `(0.5,0.20)` Size `(0,210,0,50)` → `GoToIsland1Event`.
- **Rainbow Beams `RainbowBeamFlashGui`** (`RainbowBeamSync`): full-screen pink `(255,120,255)` flash (`ZIndex 30`, transparency 0.45→1 over 0.5s) + `"🌈 Beam hit! Flight rewound!"`.
- **EventClient banners** (weather/buff events via `_G.ServerEventNotify`): edge-glow strips (`EventGlowGui`, 4px L/R, `ZIndex 15`); countdown pill (`EventCountGui`, Pos `(0.5,0,0,80)`, Size `(0,280,0,44)`, `(180,60,220)`, FredokaOne); large banner (`EventBannerGui`, `(0,500,0,65)`, slides −100→10 Back ease, 5s); full-screen flash/storm overlays (`EventFlashGui`/`StormGui`, storm `darkOverlay (10,10,30)` transp 0.35 + BlurEffect 18). Events: ⛈ THUNDERSTORM, 🌪 WINDSTORM, POWER_SURGE (yellow flashes), COIN_RUSH/RING_FEVER, FART_STORM, 🐦💥 BIRD NUKE (orange flash `(255,80,0)` + shake).

---

# 10. SOUNDS (all asset IDs)
*Format: `rbxassetid://<id>`. Many `9xxxxxxx` and `1xxxxxxx`-era IDs are old public library assets (likely reusable); the longer modern IDs may be game-specific uploads.*

**UI / Core gameplay:**
| ID | Purpose | Vol |
|---|---|---|
| `101638558691673` | UI click (buttons, menu) | 0.5 |
| `87486053112716` | error / not enough coins | 0.6 |
| `103794849233173` | food eat (buy) | 0.8 |
| `115390827163601` | ring collect | 0.6 |
| `117464325212045` | island arrival fanfare | 0.8 |
| `112825313814792` | purchase confetti | 0.8 |
| `9116458024` | beam "WHAM" knockback / egg hatch crack | 1 / 0.6 |
| `137105349517966`, `136812322649032`, `119702591396866`, `123499328258921`, `92449881602559`, `109574021376037`, `129402830763074` | **fart sounds** (one picked at random) | 0.6 |

**Music (server-driven, 4-track loop):** `140517328454242`, `139448720739903`, `139206228229841`, `138099443718294`.

**Events / hazards:**
| ID | Purpose |
|---|---|
| `133543192033291` | rocket construction |
| `1841791990` | rocket countdown |
| `135490777114772` | rocket launch |
| `9120386436`, `9116544355` | rocket effect stages |
| `114095353806681` | meteor impact |
| `109362273688140` | meteor intro |
| `5801257793` | shared low boom (meteor / ice / rocket fireball) |
| `82428123919520` | UFO alien |
| `97213152915968` | mutation ambient |
| `9112854440` | low drone / alien / roar / creak (shared, many event UIs) |
| `9114402399` | electrical buzz / wind / bubble (shared) |
| `101642229651469` | windstorm |
| `97219963176654` | thunderstorm |
| `1369158752` | thunder clap |
| `3240498563` | bird screech |
| `121387867149574` | event sting (EventClient) |
| `89988274755984` | bird-nuke boom |

---

# 11. IMAGE / ICON ASSETS
| Asset | Purpose | Reusable? |
|---|---|---|
| `rbxassetid://106760789458573` | **gold coin icon** (`_G.COIN_IMAGE`) | custom upload — re-upload your own |
| `rbxassetid://108585083746103` | **gut/stomach icon** (`_G.GUT_IMAGE`) | custom upload |
| `rbxassetid://133231198126712` | **bean food icon** (only Beans has an image; rest are emoji) | custom upload |
| `rbxassetid://127983055545494` | loading-screen background (logo+character baked in) | custom upload |
| `rbxassetid://111075648402081` | island-select menu background | custom upload |
| `rbxassetid://1316045217` | soft rounded **drop-shadow** (9-slice, `SliceCenter Rect(10,10,118,118)`) | old public asset — reusable |
| `rbxasset://textures/ui/LuaApp/icons/ic-check.png` | checkmark (`_G.CHECK_IMAGE`) | **built-in, public** |
| `rbxasset://textures/ui/LuaApp/graphic/gradient_circle.png` | UFO lens flare / soft glow | **built-in, public** |
| `rbxasset://textures/particles/sparkles_main.dds` | sparkle particles (pets, effects) | **built-in, public** |
| `rbxasset://textures/particles/smoke_main.dds` | smoke particles | **built-in, public** |
| `rbxasset://textures/particles/fire_main.dds` | fire particles | **built-in, public** |

**Emoji "icons" (text, not assets — work anywhere):** foods (🥜🥦🥬🌿🥥🍞🍝🍿🥛🧈🍦🍔🌯🍕), pets (Broccoli Dino 🥦, Coconut Crab 🥥, Popcorn Sheep 🐑, Butter Duck 🦆), guts (👶🧒🧑🧔🦛🐋), UI (🪙🐾🛒👥💨🏝️🏆💍⏱⚡☁️🐦💥➤🔒✔✨🥚🐟🗝️).

---

# 12. GAME-LOGIC HOOKS (RemoteEvents/Functions to re-wire)
The GUIs only fire these — point them at your own systems.

- **Food/economy:** `BuyFoodEvent`, `CoinEvent`, `RegenEvent`, `_G.leaderstats` (Coins / CurrentPower / StomachMax / Island), `_G.foods`, `_G.peakHeight`.
- **Stomach:** `BuyStomachEvent(maxPower,cost)`, `StomachUpdateEvent`, `StomachFullEvent(reason)`.
- **Islands/flight:** `SelectIslandEvent(n)`, `SkipIslandEvent`, `IslandUnlockEvent`, `ReturnToIslandEvent`, `WelcomeEvent`, `LandingEvent`, `RequestPlayerState`, `AnnouncementEvent`, `ServerEventNotify`, `BirdNukeEvent`, `PurchaseAnnouncementEvent`.
- **Pets:** `PetStateEvent` (s→c), `PetInventoryEvent` (s→c), `PetCollectEvent`, `PetClaimEvent`, `PetEquipEvent`, `PetUpgradeEvent`, `PetProgressEvent`, `PetPendingUpgradeEvent`, `PetQuestDiscoveredEvent`, `PetGetMarkers` (RF), **`PetFishRollEvent` (RF — server rolls the catch + pity)**; BindableEvent `PetInvToggle` (PETS button → Pet Hub).
- **Marketplace IDs (swap for yours):** Mid-Air Recharge product `3600303163`; 2X Power product `3600302990`; Bird Nuke product `3600303082`; Infinite Gut gamepass `1860686821`.

---
*End of spec. Generated by scanning the FtF client source (read-only).*
