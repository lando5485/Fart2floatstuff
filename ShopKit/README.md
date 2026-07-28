# ShopKit — the SHOP button + SHOP panel, copied exactly

Drop-in copy of Fart to Float's **SHOP button** and the **"🛒 SHOP" panel** it opens
(`PremiumShopGui`), pulled verbatim out of `src/client/ShopClient.client.lua` and
`src/client/CoreClient.client.lua`.

## Install

1. Put `ShopKit_AllInOne.client.lua` in **StarterPlayer → StarterPlayerScripts** as a
   **LocalScript** (or via Rojo: `"ShopKit": { "$path": "ShopKit/ShopKit_AllInOne.client.lua" }`
   under `StarterPlayerScripts`).
2. Open the `CONFIG` block at the top and swap the **gamepass / product ids** (see below).
3. That's it. It builds its own ScreenGuis, its own click sound, and its own mobile
   scaling. No server script, no remotes, no `_G.foods` needed — every hook into the rest
   of the game is guarded.

## ⚠️ The ids MUST be replaced per experience

Gamepasses and developer products belong to **one Roblox experience**. Fart to Float's ids
will not prompt, will never report ownership, and will never grant in another realm.
Create new ones (Creator Dashboard → that game → Monetization) and paste them into
`CONFIG.gamepassIds` / `CONFIG.productIds`.

### Gamepasses (permanent)

| Card | Name | Fart to Float id | Price shown | Effect in FtF |
|---|---|---|---|---|
| 1 | 2x Power Forever | `1862015450` | `249 R$` | `POWER_PASS_MULT = 1.4` — food gives `power × 1.4`, tank `× 1.4`. Server attribute `HasTwoXForever` |
| 2 | Glitter Trail | `1859714979` | `49 R$` | cosmetic: fart cloud → pink neon sparkle, half size. Attribute `HasGlitterTrail` |
| — | Infinite Gut | `1860686821` | *(sold from the GUT menu, not this panel)* | `StomachMax = 9999` + meter never drains |

### Developer products (one-time)

| Card | Name | Fart to Float id | Price shown | Effect in FtF |
|---|---|---|---|---|
| 3 | 2x Power 1 Hour | `3600302990` | `59 R$` | attribute `TwoXHourExpiry = os.time()+3600` |
| 4 | Mid-Air Recharge | `3600303163` | `39 R$` | `triggerMidAirRecharge` — gas → 100% |
| 5 | Skip Island | `3600303265` | `69 R$` | `triggerSkipIsland` — advance one island |
| 6 | Bird Nuke | `3600303082` | `79 R$` | `triggerBirdNuke` — 30 birds server-wide |

Grants live in `PlayerStats.server.lua`:
`MarketplaceService.ProcessReceipt` (products) and
`MarketplaceService.PromptGamePassPurchaseFinished` (passes) → `GamepassEvent:FireClient`.
The kit only **prompts**; the server still has to grant.

### Coin packs

`CONFIG.coinPacks` — six packs, all shipped with `productId = 0`, which makes the button
show a "needs ids" banner instead of prompting. Set real ids and add a `ProcessReceipt`
branch per id to grant the coins.

## What the SHOP button looks like (exact values)

The *final* in-game look — i.e. after CoreClient's restyle + `repositionGUIs` passes, not
the initial `mkSideBtn` values the game overwrites at load:

- Frame **95 × 95**, `AnchorPoint (0,0)`, `Position (0, 12, 0, 96)` — rail slot 1 of the
  desktop grid `96 / 203 / 310 / 417` (107 px pitch).
- `BackgroundColor3 = Color3.fromRGB(50,220,50)` (bright green), `UICorner 16`,
  `UIStroke Color(30,120,30) Thickness 3`.
- Icon: `TextLabel` `🛒`, `Gotham`, `TextSize 30`, `Size (1,0,0,56)` at `(0,0)`,
  `RichText = true`, black `UIStroke` thickness 1.
- Label: `TextLabel` `"SHOP"`, `GothamBold`, `TextSize 12`, white, `Size (1,0,0,28)` at
  `(0,0,0,57)`, centered, black `UIStroke` thickness 1.
- A full-size transparent `TextButton` on top does the clicking.
- Phone-class (viewport short axis < 800) raises the rail to `y = 66` to clear the joystick.
  Tablet/iPad keeps `y = 96` and scales **up**; desktop is exactly 1.0.
- `ScreenInsets = DeviceSafeInsets` (notch only — `CoreUISafeInsets` pushes the rail too low).

Click → `_G.playUIClick()` then toggle `PremiumShopGui.Enabled` through
`_G.MainMenuManager` (opening one main menu closes the others and hides `BottomStackGui`).

## What the SHOP panel looks like (exact values)

- `ScreenGui PremiumShopGui`: `ResetOnSpawn=false`, `Enabled=false`, `DisplayOrder=100`
  (above the HUD, which is ≤5), `ScreenInsets = CoreUISafeInsets`.
- Full-screen catcher frame, `BackgroundTransparency=1`, **`Active = false`** — clicks
  outside the panel fall *through* to the HUD menu buttons so you can switch menus in one
  click. The panel itself is `Active = true`.
- `premPanel`: **770 × 572**, `Position (0.5,0,0.5,-45)`, `AnchorPoint (0.5,0.5)`,
  transparent (it's just the container); a soft slice-image drop shadow (`1316045217`,
  `ImageTransparency 0.9`, 786×586) sits behind it.
- `premCard` (fills the panel, `UICorner 26`): blue `25,90,185` with a vertical gradient
  `42,122,214 → 96,60,178`, **black `UIStroke` thickness 4**.
- Header 65 px tall, transparent (so the card's rounded top corners show), with a white
  shine strip that sweeps across every 4 s.
  - Title `"🛒 SHOP"`, `FredokaOne`, gold `255,206,92`, left at `(0,16,0,4)`, black stroke 2,
    plus a gold slice-glow and 3 twinkling `✦`.
  - Subtitle `"Power up your adventure!"`, `Gotham`, `215,228,255`.
  - Close `X`: 40×40 at `(1,-48,0,12)`, red `232,96,90`, `UICorner 8`, beveled.
- `"💰 BUY COINS"` banner: full width −16, 60 px tall at `y74`, blue-violet gradient with a
  gold stroke, low-poly coin pile, `⭐ Best Way to Progress!` gold badge, green
  `OPEN SHOP ➜` button, shimmer sweep, hover pop. Opens the **COIN SHOP**, which *replaces*
  the main page (everything else hides, the coin window scales in) — never two stacked windows.
- Scroll: `Position (0,3,0,162)`, `Size (1,-8,1,-238)`, gold 5 px rounded scrollbar,
  vertical `UIListLayout` padding 18, canvas driven from `AbsoluteContentSize.Y + 18`.
- Two gold section headers with a 2 px gold underline: `"⭐ GAMEPASSES"`, `"🎯 ONE-TIME ITEMS"`.
- 3 cards per row, `31%` wide each, 190 px (gamepasses) / 220 px (products) tall, `UICorner 18`,
  each with its **own** gradient — blue, purple, pink, green, cyan, orange (desaturated 14%
  toward grey so the text reads), a glowing light border, and a static top sheen.
- Card stack (a `_Content` `UIListLayout`, padding 8): icon → title → subtitle → desc →
  **gold price capsule** (`🪙 249 R$`, 128×24, pill corner, glossy) → **green pill BUY button**
  (80% wide, 36 px, corner 18, hover 1.05 / click 0.92 bounce).
- Card 1 carries a `BEST VALUE ⭐` gold badge overlay — **built `Visible = false`** in the live
  game; flip it on if you want it showing.
- Footer: full-width purple gradient banner, `⭐ Thanks for supporting <realmName>!`
  (`FredokaOne`, max text size 16) + a bean mascot with sparkles.
- 10 twinkling `✦` in the background; the whole panel slides up from the bottom
  (`Back / Out`, 0.34 s) each time it's enabled.
- **No backdrop-click close.** The `X` button is the only way to shut it.
- Everything text is `FredokaOne`, white, `TextScaled`, black `UIStroke` 2.

## ✓ OWNED state

Cards 1 & 2 only (the permanent passes). Once owned the button becomes a non-clickable
`✓ OWNED` on grey `70,70,70`; otherwise it's the orange `BUY GAMEPASS` (`255,160,20`).
Clicking while owned is also guarded before prompting.

Ownership is read from `_G.playerGamepasses.twoXForever` / `.glitterTrail` when the game
provides it. This copy **also** asks `MarketplaceService:UserOwnsGamePassAsync` directly and
listens to `PromptGamePassPurchaseFinished`, so OWNED works in a realm with no server wiring
at all. The dev products are repeatable and deliberately never show OWNED.

## Sounds / assets used

| Thing | Asset |
|---|---|
| UI click (open/close/buttons) | `rbxassetid://101638558691673`, Volume 0.5 |
| Drop shadow + title glow | `rbxassetid://1316045217` (9-slice, `SliceCenter 10,10,118,118`) |
| Footer / banner mascot | `rbxassetid://133231198126712` (the bean icon — always renders; `🫘` does not) |
| Rounded scrollbar | `rbxasset://textures/ui/Scroll/scroll-*.png` |

There is **no** dedicated gamepass-purchase sound — confirmation is Roblox's own prompt plus
the server's `PurchaseAnnouncementEvent` banner (⭐ icon for gamepasses).

## Config flags

| Flag | Default | What it does |
|---|---|---|
| `realmName` | `"Fart to Float"` | footer text |
| `buildShopButton` | `true` | `false` = don't build the rail button; call `_G.toggleShopKit()` from your own sidebar instead |
| `shopButtonY` | `96` | rail slot (grid `96 / 203 / 310 / 417`). Phone auto-raises 96 → 66 |
| `showCoinBanner` | `true` | `false` = no BUY COINS banner / COIN SHOP; the scroll re-tops itself to `y70` so there's no gap |
| `items` | six entries | icons / titles / subtitles / price labels / button colours |
| `coinPacks` | six packs | names, amounts, bonus %, prices, product ids, colours, ribbons |

## Known quirk (copied as-is)

The price capsule prefixes `🪙`, and the coin-pack amounts use `🪙` too. Elsewhere in the
codebase that glyph is noted as not rendering in Roblox's font — the live shop uses it
anyway, so it's kept here for an exact match. If it shows as an empty box, delete the
`\xF0\x9F\xAA\x99` prefixes (there are 3) or swap in an `ImageLabel` using the coin image
`rbxassetid://106760789458573`.
