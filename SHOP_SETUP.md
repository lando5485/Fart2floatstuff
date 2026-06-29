# Shop System — Setup & Wiring

An exact copy of the Fart-to-Float shop, split into a client UI file and a server
buy-logic file, ready to drop into another game.

## Files

| File | Put it in | What it is |
|---|---|---|
| `src/client/Shop_AllInOne.client.lua` | `StarterPlayer > StarterPlayerScripts` | Verbatim 1055-line copy of the shop UI: food shop (per-island, buy / buy-max, live affordability + lock states) + premium/gamepass shop (gamepasses + one-time Robux products, owned-state). |
| `src/server/Shop_AllInOne.server.lua` | `ServerScriptService` | Verbatim food + stomach buy handlers, the `foods` + `stomachTiers` data, the remotes, and a leaderstats setup so it runs standalone. |

## `_G` hooks the client needs

The client is an exact copy, so it reads the same globals CoreClient provided in the
original game. Provide these in the new game:

| `_G` value | What it is | Required? |
|---|---|---|
| `_G.CoreClientReady` | set `true` when your client is ready (shop waits on it at line 2) | **yes** |
| `_G.foods` | the foods table — the **server file sets this**; mirror it on the client too | **yes** |
| `_G.stomachTiers` | stomach tiers — server file sets it | for stomach UI |
| `_G.leaderstats` | the player's `leaderstats` folder (Coins / CurrentPower / StomachMax) — server file creates it | **yes** |
| `_G.BuyFoodEvent` | the `BuyFoodEvent` RemoteEvent — client does `_G.BuyFoodEvent:FireServer(name)` | **yes** |
| `_G.unlockedIslands` | `{[n]=true}` map of unlocked islands (gates locked foods) | **yes** |
| `_G.playerGamepasses` | `{twoXForever=, glitterTrail=, twoXHourExpiry=}` for gamepass owned-state | for premium shop |
| `_G.MainMenuManager` | the open/close manager (the PetHub file also creates this, or stub it) | **yes** |
| `_G.updateCoins` / `_G.updateHotbar` / `_G.isFlying` / `_G.playUIClick` | optional — all guarded with `if _G.x then`, safe to omit | no |

Minimal client glue to add (e.g. at the top of your own CoreClient-equivalent):

```lua
_G.BuyFoodEvent   = game.ReplicatedStorage:WaitForChild("BuyFoodEvent")
_G.foods          = _G.foods          -- set by the server file; or define the same table client-side
_G.leaderstats    = player:WaitForChild("leaderstats")
_G.unlockedIslands = { [1] = true }   -- mark islands true as the player unlocks them
_G.playerGamepasses = { twoXForever = false, glitterTrail = false }
-- a tiny MainMenuManager stub if you don't have one:
_G.MainMenuManager = _G.MainMenuManager or {
    current = nil, hiders = {},
    register = function() end, setHud = function() end,
    notifyOpened = function(self, n) self.current = n end,
    notifyClosed = function(self, n) if self.current == n then self.current = nil end end,
    isOtherOpen  = function(self, n) return self.current ~= nil and self.current ~= n end,
}
_G.CoreClientReady = true             -- LAST: unblocks the shop's `repeat wait until` at line 2
```

## Opening the shop

The original opens it from food-stand proximity / HUD buttons. To open it directly:

```lua
local pg = player:WaitForChild("PlayerGui")
pg.PremiumShopGui.Enabled = true   -- the gamepass / Robux shop
pg.FoodShopGui.Enabled    = true   -- the food shop
```

## The buy flow (server rules, verbatim)

**Food** (`BuyFoodEvent`):
1. **Coins checked FIRST** (the common blocker) → fires `StomachFullEvent("not_enough_coins")`.
2. Then stomach capacity. Uses `>` so a buy landing **exactly** on the max is allowed.
   - no room at all → `StomachFullEvent("stomach_full")`
   - has room but this food won't fit → `StomachFullEvent("not_enough_room")`
3. Coins are **NOT deducted** when the buy is rejected.
4. On success: deduct coins, add power, fire `RegenEvent(powerAdded, currentPower, stomachMax)`.

**Stomach** (`BuyStomachEvent(newMax, cost)`):
- Validates the `(maxPower, cost)` pair against a real, **non-Robux** tier.
- Carries current power over (only the tank's MAX grows), fires `RegenEvent` + `StomachUpdateEvent(newMax, tierName)`.

## Data (verbatim)

Foods: Beans(5/8) Broccoli(24/25) Cabbage(85/45) Turnips(94/70) Coconuts(142/100)
Bread(138/140) Pasta(202/185) Popcorn(600/240) Milk(500/300) Butter(400/370)
IceCream(560/450) Burger(405/540) Burrito(700/640) Pizza(518/750) — `{price/power}`, island = list order.

Stomach tiers: Tiny(100/0) Small(182/1600) Medium(520/3000) Large(1075/5200)
XL(2146/8000) Iron(3218/11000) Infinite(9999/**499 Robux**) — `{maxPower/cost}`.

Gamepass / product IDs (top of the client file): `GAMEPASS_IDS = {TwoXForever=1862015450,
GlitterTrail=1859714979}`, `PRODUCT_IDS = {TwoXOneHour=3600302990, MidAirRecharge=3600303163,
SkipIsland=3600303265, BirdNuke=3600303082}`.

## Caveats

1. **`BuyFoodEvent` source:** the client fires `_G.BuyFoodEvent`; the server creates the
   remote under `ReplicatedStorage`. Point `_G.BuyFoodEvent` at `ReplicatedStorage.BuyFoodEvent`.
2. **Robux products** (2x pass, Bird Nuke, etc.): the client *prompts* them, but granting
   runs through `MarketplaceService.ProcessReceipt` — NOT duplicated here, because only one
   script may own `ProcessReceipt`. Wire the product IDs into your existing receipt handler.
3. **Stomach-upgrade menu UI** lives in CoreClient in the original (separate from this shop).
   This bundle ships the stomach *server* logic + the *food/premium* UI; the stomach buy
   *menu* front-end is not included here.
