# Fart to Float - Game Documentation

> **All numbers below were re-verified against the source on 2026-08-14.** The previous version of this
> file was a full balance pass out of date — every table (islands, foods, guts, speeds, coin formula) had
> different numbers from the code. If you are about to trust a figure here, it is cheaper to re-grep it
> than to assume; the authority is always the source, and the file/line is given for each table.

## Game Concept
Players buy food -> fills stomach and gas meter -> hold fart button to fly up -> earn coins based on
height -> buy more food -> reach higher islands. 14 islands total.

New player defaults (`PlayerStats.server.lua`, `DEFAULT_COINS/STOMACH/ISLAND`): **25 coins, Tiny Gut
(100 maxPower), island 1.**

---

## ⚠ CURRENT TESTING STATE — READ BEFORE PUBLISHING

`PlayerStats.server.lua` — `DISABLE_SAVE_FOR_TESTING = true`.

Every join starts as a brand-new player and **nothing is written to the DataStore**. This is deliberate
(fast iteration on the opening minutes) but it is the single most destructive thing that can ship: live,
every player loses all progress the moment they leave, unrecoverably. **Set it to `false` before publishing.**

`FRESH_PLAYER_TEST`, `SPAWN_AT_PIZZA_PALMS_TEST` and `FRESH_PLAYER_USERID` in the same file are **dead
code** — declared, never read. Their comments claim to protect one account's save data. They do not, and
never did. Flipping them changes nothing.

---

## Island Heights
Exact positions (`ISLAND_POSITIONS`, `PlayerStats.server.lua`).
Note these are the island **model** positions; the physical Stand a player lands on sits ~90 studs higher
on island 1 and a few studs off on the rest (see the `STAND DATA ISLAND n` boot log for live values).

| # | Island | X | Y | Z |
|---|--------|------|-------|------|
| 1 | Bean Farm | 0 | 150 | 0 |
| 2 | Broccoli Bluff | 120 | 790 | 60 |
| 3 | Cabbage Cliffs | -160 | 1680 | 100 |
| 4 | Turnip Tranquil | 180 | 2480 | -120 |
| 5 | Coconut Cove | -200 | 3580 | 160 |
| 6 | Bread Board | 220 | 4820 | -180 |
| 7 | Pasta Peak | -240 | 6460 | 200 |
| 8 | Popcorn Pinnacle | 260 | 8202 | -220 |
| 9 | Milk Marsh | -280 | 9732 | 240 |
| 10 | Butter Swamp | 300 | 11978 | -260 |
| 11 | Ice Cream Isle | -320 | 14194 | 280 |
| 12 | Burger Bluff | 340 | 17138 | -300 |
| 13 | Burrito Barrens | -360 | 20206 | 320 |
| 14 | Pizza Palms | 380 | 24017 | -340 |

Islands 3, 5 and 7 are rotated about Y for looks only (`ISLAND_ROTATIONS`); heights are untouched.

**Known world issue:** island 2's model is misspelled `Island_2_BrocolliBluff` in Workspace. PlayerStats
falls back and warns every boot. Renaming it to `Island_2_BroccoliBluff` removes a permanent workaround.

## Food Data
All 14 foods (`foods` table — **identical in `CoreClient.client.lua` and `PlayerStats.server.lua`**;
if you change one, change both).

| Name | Price | Power | Island | Power/coin |
|------|-------|-------|--------|-----------|
| Beans | 5 | 8 | 1 | 1.60 |
| Broccoli | 24 | 25 | 2 | 1.04 |
| Cabbage | 85 | 45 | 3 | 0.53 |
| Turnips | 94 | 70 | 4 | 0.74 |
| Coconuts | 142 | 100 | 5 | 0.70 |
| Bread | 138 | 140 | 6 | 1.01 |
| Pasta | 202 | 185 | 7 | 0.92 |
| Popcorn | 600 | 240 | 8 | 0.40 |
| Milk | 500 | 300 | 9 | 0.60 |
| Butter | 400 | 370 | 10 | 0.93 |
| IceCream | 560 | 450 | 11 | 0.80 |
| Burger | 405 | 540 | 12 | 1.33 |
| Burrito | 700 | 640 | 13 | 0.91 |
| Pizza | 518 | 750 | 14 | 1.45 |

**Prices are not monotonic and value swings wildly** — see Known Issues.
The comment above the table claims `price = round(power * (0.8 + (island-1)/13 * 2.2))`. That formula does
**not** produce these numbers (it gives Pizza 2250, not 518). The table is hand-tuned; the comment is stale.

## Stomach Tiers
`stomachTiers`, `PlayerStats.server.lua`. The client keeps a mirror in `CoreClient.client.lua` — the server
owns the real check, so if they drift the button lies but the purchase is still refused correctly.

| Name | maxPower | Cost | Currency | Island gate |
|------|----------|------|----------|-------------|
| Tiny Gut | 100 | 0 | Coins (default) | 1 |
| Small Gut | 182 | 1600 | Coins | 2 |
| Medium Gut | 520 | 3000 | Coins | 4 |
| Large Gut | 1075 | 5200 | Coins | 7 |
| XL Gut | 2146 | 8000 | Coins | 11 |
| Iron Gut | 3218 | 11000 | Coins | 14 |
| Infinite Gut | 9999 | 499 | Robux (`robux=true`) | 1 |

The island gate is a **second** lock on top of cost: banked coins alone cannot buy a gut for a stretch of
the game the player has not reached.

## Flight System
- **Drain rate:** `DRAIN_RATE = 3.5` gas/sec (`CoreClient`). A full 100 tank ≈ 28s of thrust.
- **maxGasMeter:** 100. Horizontal speed: `FLIGHT_HORIZONTAL_SPEED = 48`.
- **gasMeter ↔ currentPower:** during flight `currentPower = (gasMeter / maxGasMeter) * stomachMax`.
  gasMeter is the 0-100 normalised fuel bar. At 0 the thrust stops and the player falls.
- **`getFlightSpeed()` by current power:**

  | power ≤ | speed |
  |---------|-------|
  | 100 | 40 |
  | 182 | 62 |
  | 611 | 84 |
  | 1075 | 126 |
  | 2146 | 144 |
  | 3218 | 226 |
  | else | 280 |

  ⚠ The third band is `611`, but Medium Gut's maxPower is `520` — the speed table and the gut table do not
  line up there. Harmless today (nothing sits between 520 and 611) but it will bite on the next retune.

  Multiplied by `_G.serverEventSpeedMult`, `_G.rebirthSpeedMult`, ×1.35 while Shady Sal's rocket gas is
  active (`SalSpeedBoostUntil`, server-clock expiry), and ×2 for a 2x boost.
- **Infinite Gut owners never drain** — the meter is re-topped every frame.
- **Gas bubbles** grant a % of the tank scaled by gut tier (3 → 6). Bubbles respawn after 45s; rings 30s.

## Coin System
Sent from the client every 0.5s during flight via `CoinEvent:FireServer(...)`.

```lua
tickCoins = height * 0.0044 * (_G.serverEventCoinMult or 1)   -- height = hrp.Position.Y
dynCap    = math.max(FLIGHT_COIN_CAP, peakHeight * CAP_PER_HEIGHT)   -- 80, 0.2
pay       = math.min(tickCoins, dynCap - flightCoinsEarned)
CoinEvent:FireServer(pay * 0.70)                              -- 70% payout scalar
```

The old `(height / 500) ^ 2` term is **gone**. Height coins are capped per flight; ring bonuses are not.

**Ring bonus:** `math.floor(15 * ringMultiplier * serverEventRingMult)` where
`ringMultiplier = 1 + ringStreak * 0.2`. `ringStreak` resets to 0 on landing.
Event ceilings: `serverEventCoinMult` peaks at **2**, `serverEventRingMult` at **10** — so one ring on a
long streak during a ring event legitimately pays ~1,650, at any altitude.

**Server side** (`CoinEvent.OnServerEvent`, PlayerStats) applies, in order: friend/group bonus
(`_G.coinBonusMult`), rebirth (`_G.rebirthMult`), Sal's 2x (`SalCoinBoostUntil`); then accumulates
fractions in `playerCoinAccum` and adds `math.floor` to `Coins` + `TotalCoinsEarned`.

**Validation:** the handler rejects NaN/inf/≤0, caps a single grant (`COIN_MAX_SINGLE`), rate-limits calls
and enforces a per-window budget that scales with the player's real altitude. This is a **bound, not
authority** — the client still decides the figure. The real fix is computing flight coins server-side.

## Power System Rules
- **currentPower resets on:** island unlock (`UnlockIslandEvent`), stomach upgrade (`BuyStomachEvent`),
  and respawn/landing (`stopFlying`).
- **Stomach full check uses `>` not `>=`:** `if newPower > stomachMax.Value then` reject — a purchase
  landing exactly on stomachMax is allowed.
- **Coins are NOT deducted if the stomach is full:** the check fires `StomachFullEvent` and returns
  *before* `coins.Value` is reduced.

## Known Issues
- **Food prices are not monotonic.** Popcorn (island 8) costs 600 while Milk 500, Butter 400, Burger 405
  and Pizza 518 are all cheaper *and* stronger. Popcorn is 0.40 power/coin, Pizza is 1.45 — a 3.6x spread
  with the worst deal in the middle of the game. Later foods being cheaper than earlier ones inverts the
  progression.
- Flight speed / coin earn rate still being tuned.
- Targets: island 1→2 ≈ 2 min, each later island ≈ 3 min base, events +1-3 min each, total 65-70 min.
- The speed table's 611 band vs Medium Gut's 520 (above).

## Repo layout
Three separate Roblox places, three separate repos:
- **This repo** — the main Food Realm (14 islands).
- `CandyRealm/` — subfolder here, its own `default.project.json`.
- `../farttofloatdinosaurealm/` and `../SpaceRealmStuff/` — separate checkouts.

Key files: `src/client/CoreClient.client.lua` (flight, HUD, food table), `src/server/PlayerStats.server.lua`
(save/load, islands, guts, coins), `src/client/PetFollow.client.lua` (pets **and** the real fishing quest),
`src/client/NotifyCenter.client.luau` (all banners — use `push`/`pin`, don't build a new ScreenGui).

## Rojo Setup
- Run `rojo serve`, connect the plugin in Studio, Ctrl+S in Studio for world changes.
- **Rojo only ADDS — it never overwrites.** A stale copy of a script baked into the place file runs
  *alongside* the synced one. The boot log's `[BootCheck]` and `[SECURITY] NOT-IN-MANIFEST` sections list
  them; there are currently ~27 duplicated scripts. If an edit "does nothing", check the log's line number
  against the file before assuming the code is wrong.
