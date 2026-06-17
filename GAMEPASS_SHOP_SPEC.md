# Fart to Float — Gamepass Shop Spec (for recreating in Space Realm)

Scanned read-only from `src/client/ShopClient.client.lua`, `src/client/CoreClient.client.lua`, and `src/server/PlayerStats.server.lua`. Nothing was changed.

> **TL;DR on IDs:** every gamepass ID and developer-product ID below belongs to the **Fart to Float** experience. They will **NOT** work in Space Realm. You must create your own gamepasses + dev products in the Space Realm experience and swap every ID. See section 3.

---

## 1) THE GAMEPASSES & PRODUCTS

There are **3 gamepasses** and **4 developer products** (one-time purchases). The shop UI (the "🛒 SHOP" panel) shows 2 gamepasses + the 2×-1-hour product + the 4 one-time items. The **Infinite Gut** gamepass is sold from the **stomach/gut upgrade menu** (CoreClient), not the shop panel.

### Gamepasses (permanent)

| Name (in shop) | Gamepass Asset ID | Price shown | What it grants | Where applied |
|---|---|---|---|---|
| **2x Power Forever** | `1862015450` | `249 R$` | Permanent 2× fart power: each food gives `power × 1.4`, and the effective tank grows `× 1.4` (`POWER_PASS_MULT = 1.4`) → flies higher/longer. | Server sets attribute `HasTwoXForever=true`; `BuyFoodEvent` reads `has2x` → `powerGain = floor(food.power * 1.4)`, `effectiveMax = floor(stomachMax * 1.4)` (`PlayerStats.server.lua` ~line 841–848). Client mirrors via `_G.playerGamepasses.twoXForever` + `POWER_PASS_MULT` in `CoreClient`. |
| **Glitter Trail** | `1859714979` | `49 R$` | Permanent cosmetic: the fart-cloud trail becomes a small **pink neon** sparkle cloud. | Server sets `HasGlitterTrail=true` + sends `{glitterTrail=true}`; client `spawnCloud()` uses `gp.glitterTrail` → `Color (255,220,255)`, `Material=Neon`, half-size cloud (`CoreClient.client.lua` ~line 1496). |
| **Infinite Gut** (a.k.a. Unlimited Gut) | `1860686821` | *(no shop price; it is the only Robux tier in the Gut upgrade menu)* | Sets `StomachMax = 9999` (top tier) and **locks the fart meter full / never drains**. | `applyInfiniteGut(player)` in `PlayerStats.server.lua` (~line 114): sets `HasInfiniteGut=true`, `StomachMax=9999`, fills `CurrentPower`, fires `StomachUpdateEvent` + `RegenEvent`. Prompted from `CoreClient.client.lua` ~line 1032: `PromptGamePassPurchase(player, 1860686821)` for the `tier.robux` gut tier. |

### Developer products (one-time / consumable)

| Name (in shop) | Product Asset ID | Price shown | What it grants | Where applied |
|---|---|---|---|---|
| **2x Power 1 Hour** | `3600302990` | `59 R$` | 2× fart power for 1 hour (same `×1.4` effect as the forever pass, time-limited). | `ProcessReceipt` sets attribute `TwoXHourExpiry = os.time()+3600` + sends `{twoXHourExpiry=...}`. `has2x` also true while `TwoXHourExpiry > now`. |
| **Mid-Air Recharge** | `3600303163` | `39 R$` | Instantly refills the gas meter to 100% mid-flight. | `ProcessReceipt` → `triggerMidAirRecharge(player)` (bumps `MidAirRechargeCount`, sets server `CurrentPower` to gut max, sends `{rechargeNow=true}`; client `rechargeFartMeter`). Same id is `RECHARGE_PRODUCT` in `CoreClient`. |
| **Skip Island** | `3600303265` | `69 R$` | Instantly teleports/advances the player to the next island. | `ProcessReceipt` → `triggerSkipIsland(player)` (immediate skip on purchase; also bumps `SkipIslandCount`). |
| **Bird Nuke** | `3600303082` | `79 R$` | Offensive: spawns ~30 aggressive birds on the whole server; every other player dies & respawns home + a banner. | `ProcessReceipt` → `triggerBirdNuke(player)` → `BirdNukeEvent:FireAllClients`. Also a duplicate buy button in `CoreClient` (~line 570). |
| *(Pet Upgrade — stub)* | `PET_UPGRADE_PRODUCT_ID = 0` | — | Cosmetic "skip the grind" pet level. **Currently `0` = disabled stub** (prompt never opens). | `PetSystem.server.lua` `_G.petsHandleReceipt`; set a real id in BOTH `PetSystem.server.lua` and `PetFollow.client.lua` to enable. |

### Exact MarketplaceService calls used

- **Gamepass purchase prompt:** `MarketplaceService:PromptGamePassPurchase(player, <gamepassId>)`
- **Gamepass ownership (on join, live):** `MarketplaceService:UserOwnsGamePassAsync(player.UserId, <gamepassId>)` — gamepass ownership is **read live each join, never saved** (`PlayerStats.server.lua` ~line 737–762).
- **Gamepass live grant:** `MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased) ... end)` (~line 1387) — sets the attribute/flag and fires `GamepassEvent` to the client.
- **Product purchase prompt:** `MarketplaceService:PromptProductPurchase(player, <productId>)`
- **Product grant:** `MarketplaceService.ProcessReceipt = function(info) ... end` (~line 1345) — switches on `info.ProductId`, applies the effect, returns `Enum.ProductPurchaseDecision.PurchaseGranted` (or `NotProcessedYet`).
- **State replication:** server → client `GamepassEvent:FireClient(player, data)` (a `RemoteEvent` in `ReplicatedStorage`). Client stores it in `_G.playerGamepasses = {twoXForever, glitterTrail, midAirRecharge, skipIsland, twoXHourExpiry}`.

> Note: there are two test/balance kill-switches on the server that force perks off — `DISABLE_2X` (Studio only) and `DISABLE_PERKS_FOR_BALANCE` (master no-perks). Set both to `false` in Space Realm so purchases actually take effect.

---

## 2) THE SHOP GUI (the "🛒 SHOP" panel = `PremiumShopGui`)

All built in code in `ShopClient.client.lua`. Helpers: `mkCorner`, `mkStroke`, `mkLabel`, `mkFrame`, `mkButton`.

### Root + Panel
- **ScreenGui** `PremiumShopGui`: `ResetOnSpawn=false`, `Enabled=false`, `DisplayOrder=100`, parented to `PlayerGui`.
- Full-screen invisible catcher frame: `Size=(1,0,1,0)`, `BackgroundColor3=(0,0,0)`, `BackgroundTransparency=1`, `Active=false` (clicks outside the panel fall through to HUD menu buttons).
- **Panel `premPanel`:** `Size=UDim2.new(0.9,0,0.85,0)`, `Position=UDim2.new(0.5,0,0.5,0)`, `AnchorPoint=Vector2.new(0.5,0.5)`, `BackgroundColor3=Color3.fromRGB(25,90,185)`, `ClipsDescendants=true`, `Active=true`. Corner radius `20`, UIStroke `Color (255,255,255)` thickness `3`.

### Header
- **`premHeader` frame:** `Size=(1,0,0,65)`, `BackgroundColor3=Color3.fromRGB(15,60,140)`.
- **Title:** text `"🛒 SHOP"`, `Font=GothamBold`, `TextSize=30`, `TextColor3=Color3.fromRGB(255,215,0)` (gold), `Size=(1,-60,0,40)`, `Position=(0,14,0,5)`, left-aligned, black UIStroke thickness 2.
- **Subtitle:** text `"Power up your farts!"`, `Font=Gotham`, `TextSize=14`, `TextColor3=(255,255,255)`, `Position=(0,14,0,45)`.
- **Close button `premClose`:** `Size=(0,40,0,40)`, `Position=UDim2.new(1,-48,0,12)`, `BackgroundColor3=Color3.fromRGB(220,50,50)`, text `"✕"`, `Font=GothamBold`, `TextSize=20`, white, corner radius 8. On click: `playUIClick()` + `PremiumShopGui.Enabled=false`.

### Scroll + layout
- **`premScroll` ScrollingFrame:** `Position=(0,0,0,65)`, `Size=(1,0,1,-92)` (between header and footer), `BackgroundTransparency=1`, `BorderSizePixel=0`, `ScrollBarThickness=6`, `ScrollBarImageColor3=(255,215,0)`, `ScrollingDirection=Y`. `CanvasSize` is driven explicitly from the layout's `AbsoluteContentSize.Y + 18` (equivalent to `AutomaticCanvasSize=Y`).
- **Scroll layout:** vertical `UIListLayout`, `HorizontalAlignment=Center`, `Padding=10`, `SortOrder=LayoutOrder`; `UIPadding` top 8 / bottom 10.
- **Section header** (`sectionHeader`): a `(1,-16,0,28)` frame with a gold title (`GothamBold`, `TextSize=16`, `(255,215,0)`, left) + a 2px gold underline at the bottom. Two sections: `"⭐ GAMEPASSES"` (order 1) and `"🎯 ONE-TIME ITEMS"` (order 3).
- **Section row** (`mkSectionRow`): full-width `(1,-16,0,190)` frame with a horizontal `UIListLayout`, `HorizontalAlignment=Center`, `VerticalAlignment=Top`, `Padding=18`. Holds 3 cards each.

### Card (`mkShopCard`) — uniform card
- **Card size:** `CARD_W=208` × `CARD_H=190`. `BackgroundColor3=Color3.fromRGB(20,70,160)`, corner radius `16`, UIStroke white thickness `2`.
- **Content holder:** full-size frame, vertical `UIListLayout` (`HorizontalAlignment=Center`, `VerticalAlignment=Top`, `Padding=3`); `UIPadding` top 18 / bottom 6 / left 8 / right 8. Items stack top→bottom by `LayoutOrder`:
  - **Icon** (order 1): TextLabel, `Font=Gotham`, `TextSize=40`, white, `Size=(1,0,0,42)`, centered.
  - **Title** (order 2): `GothamBold`, `TextSize=16`, white, centered.
  - **Subtitle** (order 3): `GothamBold`, `TextSize=12`, colored, centered.
  - **Price** (order 4): `GothamBold`, `TextSize=15`, `(255,215,0)` gold, centered.
  - **Desc** (order 5, optional): `Gotham`, `TextSize=11`, `(180,210,255)`, wrapped, centered.
  - **BUY button** (order 10, always last → never overlaps): `Size=(1,0,0,32)`, `BackgroundColor3=<per-card>`, `Font=GothamBold`, `TextSize=13`, white, corner radius 8.

### The 6 cards (exact content)
| # | Icon | Title / Subtitle | Price | Buy button color (RGB) | Button text | Extra |
|---|---|---|---|---|---|---|
| 1 | ⚡ | `2x Power` / `FOREVER` (sub green 100,220,100) | `249 R$` | `255,180,0` + stroke `200,130,0` | `BUY GAMEPASS` | `"BEST VALUE ⭐"` badge overlay (BG `255,180,0`, text `80,40,0`, corner 6) |
| 2 | ✨ | `Glitter Trail` / `PERMANENT` | `49 R$` | `220,80,180` | `BUY GAMEPASS` | — |
| 3 | ⏰ | `2x Power` / `1 HOUR` (sub `255,200,100`) | `59 R$` | `50,150,255` | `BUY NOW` | live "Active: Xm Ys" timer label (order 6) |
| 4 | 🔋 | `Mid-Air` / `RECHARGE` | `39 R$` | `50,200,50` | `BUY NOW` | desc `"Refills gas to 100%!"` |
| 5 | 🏝️ | `Skip Island` / `ONE USE` (sub `255,200,100`) | `69 R$` | `255,140,0` | `BUY NOW` | desc `"Jump to next island!"` |
| 6 | 💥 | `Bird Nuke` / `CHAOS MODE` (sub `255,100,100`) | `79 R$` | `220,50,50` | `BUY NOW` | desc `"Unleash 30 birds on everyone!"` |

### Footer + "OWNED" state
- **Footer label:** `"Purchases support the game! Thank you! 🙏"`, `Gotham`, `TextSize=12`, `(150,180,255)`, near the panel bottom, centered.
- **OWNED state:** for the two **forever gamepasses only** (cards 1 & 2), once `_G.playerGamepasses.twoXForever` / `.glitterTrail` is true, the buy button becomes a non-clickable **`✓ OWNED`** (green); otherwise it stays the orange/pink `BUY GAMEPASS`. Refreshed from the `GamepassEvent` client handler (`ShopClient` ~line 1009–1042). Clicking a buy button while already-owned does nothing (guard checks `_G.playerGamepasses` before prompting).

### Sounds
- **UI click:** `rbxassetid://101638558691673`, Volume `0.5` (`CoreClient` `uiClickSound` / `_G.playUIClick`). Played on shop open/close + button clicks.
- **Food "eat"/buy sound (food stand only):** `rbxassetid://103794849233173`, Volume `0.8`.
- **Coin price icon image:** `rbxassetid://106760789458573` (used by food prices, not the gamepass cards).
- There is **no dedicated gamepass-purchase sound** — purchase confirmation is the Roblox system prompt plus a server `PurchaseAnnouncementEvent` banner (`⭐` icon for gamepasses).

> The separate **food stand** (`FoodShopGui`) is coin-purchased food, not gamepasses — documented here only to note it exists; it is not part of the Robux shop.

---

## 3) MAKING IT WORK IN SPACE REALM — READ THIS

**Gamepasses and developer products are tied to a specific Roblox experience.** A gamepass/product created under *Fart to Float* is owned by that experience; `PromptGamePassPurchase`, `UserOwnsGamePassAsync`, `PromptProductPurchase`, and `ProcessReceipt` only work for IDs that belong to the **running experience**. So you **cannot** reuse these IDs in Space Realm — they will fail to prompt / never report ownership / never grant.

**To make the shop work "off rip" in Space Realm:**
1. In the **Space Realm** experience (Creator Dashboard → that game → Monetization), create **new gamepasses** and **new developer products** matching this list (same names/prices is fine).
2. Copy each new ID and **replace** the corresponding Fart-to-Float ID in the code.
3. Make sure the balance/test kill-switches are off (`DISABLE_2X=false`, `DISABLE_PERKS_FOR_BALANCE=false`) so purchases apply.

### Exact IDs to replace with Space Realm's own IDs

**Gamepasses** (defined in `ShopClient.client.lua` line 11 and `PlayerStats.server.lua` line 104 — keep them in sync):
- `TwoXForever  = 1862015450`
- `GlitterTrail = 1859714979`
- `InfiniteGut  = 1860686821` (also referenced in `CoreClient.client.lua` ~line 1032)

**Developer products** (`ShopClient.client.lua` line 12 and `PlayerStats.server.lua` line 141 — keep in sync; also `CoreClient` lines 451/550/570):
- `TwoXOneHour    = 3600302990`
- `MidAirRecharge = 3600303163`
- `SkipIsland     = 3600303265`
- `BirdNuke       = 3600303082`

**Stub (optional):** `PET_UPGRADE_PRODUCT_ID = 0` in `PetSystem.server.lua` + `PetFollow.client.lua` — leave 0 to keep disabled, or set a real product id in both.

> Search the codebase for each numeric ID above and replace every occurrence. The IDs appear in `ShopClient.client.lua`, `PlayerStats.server.lua`, and `CoreClient.client.lua`.
