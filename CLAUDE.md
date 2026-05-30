# Fart to Float - Game Documentation

## Game Concept
Players buy food -> fills stomach and gas meter
-> hold fart button to fly up -> earn coins
based on height -> buy more food -> reach
higher islands. 14 islands total.

## Island Heights
Exact Y positions (from `ISLAND_POSITIONS` / `ISLAND_POS`):

| # | Island | X | Y | Z |
|---|--------|----|------|------|
| 1 | Bean Farm | 0 | 50 | 0 |
| 2 | Broccoli Bluff | 120 | 600 | 60 |
| 3 | Cabbage Cliffs | -160 | 1400 | 100 |
| 4 | Turnip Tranquil | 180 | 2500 | -120 |
| 5 | Coconut Cove | -200 | 4000 | 160 |
| 6 | Bread Board | 220 | 6000 | -180 |
| 7 | Pasta Peak | -240 | 8500 | 200 |
| 8 | Popcorn Pinnacle | 260 | 11500 | -220 |
| 9 | Milk Marsh | -280 | 15000 | 240 |
| 10 | Butter Swamp | 300 | 19000 | -260 |
| 11 | Ice Cream Isle | -320 | 24000 | 280 |
| 12 | Burger Bluff | 340 | 30000 | -300 |
| 13 | Burrito Barrens | -360 | 37000 | 320 |
| 14 | Pizza Palms | 380 | 45000 | -340 |

## Food Data
All 14 foods (from `foods` table, identical in client and server):

| Name | Price | Power | Island |
|------|-------|-------|--------|
| Beans | 10 | 8 | 1 |
| Broccoli | 250 | 25 | 2 |
| Cabbage | 450 | 45 | 3 |
| Turnips | 2000 | 70 | 4 |
| Coconuts | 3500 | 100 | 5 |
| Bread | 7000 | 140 | 6 |
| Pasta | 14000 | 185 | 7 |
| Popcorn | 28000 | 240 | 8 |
| Milk | 55000 | 300 | 9 |
| Butter | 100000 | 370 | 10 |
| IceCream | 180000 | 450 | 11 |
| Burger | 320000 | 540 | 12 |
| Burrito | 550000 | 640 | 13 |
| Pizza | 900000 | 750 | 14 |

## Stomach Tiers
All tiers (from `stomachTiers`):

| Name | maxPower | Cost | Currency |
|------|----------|------|----------|
| Tiny Gut | 40 | 0 | Coins (default) |
| Small Gut | 96 | 200 | Coins |
| Medium Gut | 282 | 1500 | Coins |
| Large Gut | 603 | 8000 | Coins |
| XL Gut | 1425 | 40000 | Coins |
| Iron Gut | 2639 | 200000 | Coins |
| Infinite Gut | 99999 | 499 | Robux (`robux=true`) |

## Flight System
- **Drain rate:** `gasMeter = math.max(0, gasMeter - 4 * dt)` -> **4 gas per second**
- **maxGasMeter:** 100
- **How gasMeter and currentPower relate:**
  During flight, `currentPower = (gasMeter / maxGasMeter) * stomachMax`.
  gasMeter is the 0-100 normalized fuel bar; currentPower is the raw power scaled to the player's stomachMax. When gasMeter hits 0, currentPower hits 0 and flight stops.
- **getFlightSpeed() values (by current power):**
  - power <= 40 -> 28
  - power <= 96 -> 35
  - power <= 282 -> 45
  - power <= 603 -> 58
  - power <= 1425 -> 75
  - power <= 2639 -> 95
  - else (> 2639) -> 120

  Speed is then multiplied by `_G.serverEventSpeedMult` (event bonus) and doubled if a 2x boost is active. Applied as the Y velocity of a BodyVelocity (`bodyVel.Velocity = Vector3.new(move.X*27, speed, move.Z*27)`).
- **How height is calculated:**
  `getMaxHeight() = 50 + (currentPower * 14)`. Live height is read directly from `hrp.Position.Y`; `_G.peakHeight` tracks the max Y reached during a flight.

## Coin System
Coins are sent to the server every 0.5s during flight via `CoinEvent:FireServer(coins)`.

Exact earn formula (per 0.5s tick, where `height = math.max(1, hrp.Position.Y)`):

```
coins = height * 0.008 + (height / 500) ^ 2
```

The server (`CoinEvent.OnServerEvent`) accumulates fractional amounts in `playerCoinAccum` and adds `math.floor` of the total to `Coins` and `TotalCoinsEarned` once it reaches a whole number.

Ring bonus (separate): `bonus = math.floor(15 * ringMultiplier * serverEventRingMult)`, where `ringMultiplier = 1 + ringStreak * 0.2`.

## Power System Rules
- **currentPower only resets when:**
  1. Island unlocked (`UnlockIslandEvent` -> `cp.Value = 0`)
  2. Stomach upgraded (`BuyStomachEvent` -> `cp.Value = 0`)
  3. CharacterAdded/respawn (`stopFlying`/land sets `currentPower = 0`)
- `gasMeter = (currentPower / stomachMax) * 100`
- **Stomach full check uses `>` not `>=`:** in `BuyFoodEvent`, `if newPower > stomachMax.Value then` reject. So a purchase that lands exactly on stomachMax is allowed.
- **Coins NOT deducted if stomach full:** the full check fires `StomachFullEvent` and `return`s BEFORE `coins.Value` is reduced. Player keeps their coins.

## Known Issues
- Flight speed needs balancing
- Coin earn rate needs balancing
- Target: Island 1->2 = 2 minutes
- Target: Each other island = 3 min base
- Events will add 1-3 min per island
- Total target playtime: 65-70 minutes

## File Structure
- src/client/CoreClient.client.lua
- src/client/ShopClient.client.lua
- src/client/EventClient.client.lua
- src/client/WorldClient.client.lua
- src/server/PlayerStats.server.lua
- default.project.json (Rojo config)

## Rojo Setup
- Run: rojo serve
- Connect Rojo plugin in Studio
- Scripts sync automatically
- Must Ctrl+S in Studio for world changes
