# Purchase Perks — How They Work

How the four buyable perks work: 2x Power Forever (gamepass), 2x Power 1 Hour,
Mid-Air Recharge, and Skip Island (products). Source: `PlayerStats.server.lua`
(grants/effects) + `CoreClient.client.lua` (client reactions).

IDs (set these to your own):
- Gamepass `TwoXForever = 1862015450`
- Products `TwoXOneHour = 3600302990`, `MidAirRecharge = 3600303163`, `SkipIsland = 3600303265`

---

## 1) 2x Power FOREVER (gamepass) & 2) 2x Power 1 HOUR (product)

Both grant the SAME "2x power" effect — one is permanent, one lasts an hour. The
effect is applied on the SERVER when you **buy food**, not in the flight loop.

**Grant (server):**
- Forever pass → `player:SetAttribute("HasTwoXForever", true)` (on purchase via
  `PromptGamePassPurchaseFinished`, and re-applied on join via `UserOwnsGamePassAsync`).
- 1-Hour product → `player:SetAttribute("TwoXHourExpiry", os.time() + 3600)` (1 hour),
  and fires `GamepassEvent {twoXHourExpiry=...}` so the client shows a countdown.

**Effect (server, in `BuyFoodEvent`):**
```lua
local has2x = player:GetAttribute("HasTwoXForever")
           or (player:GetAttribute("TwoXHourExpiry") and player:GetAttribute("TwoXHourExpiry") > os.time())
-- POWER_PASS_MULT = 1.4
local powerGain    = has2x and math.floor(food.power * POWER_PASS_MULT) or food.power
local effectiveMax = has2x and math.floor(stomachMax.Value * POWER_PASS_MULT) or stomachMax.Value
-- food adds 1.4x its power to the tank AND the tank can hold 1.4x stomachMax -> you fly HIGHER + LONGER
```
So with the pass: each food gives **1.4× power**, and your effective fuel tank
grows to **1.4× StomachMax**. The DISPLAY meter still shows the normal 0–100%
(the extra fuel reads as flying higher, not a bigger bar).

Notes:
- It's labeled "2x" but the live multiplier is **`POWER_PASS_MULT = 1.4`** (tune freely).
- The 1-hour version expires when `TwoXHourExpiry` passes; the client ticks a
  `⚡ Xm YYs` timer from `_G.playerGamepasses.twoXHourExpiry`.
- (There IS a dead `twoXBoostActive -> speed*2` branch in the flight loop, but it's
  never enabled — the real effect is the 1.4× food multiplier above.)
- In the current balance test, `FORCE_NO_2X` / `DISABLE_PERKS_FOR_BALANCE` force
  `has2x = false`. Set those off to enable the perk.

---

## 3) MID-AIR RECHARGE (product) — refill the meter to 100% mid-flight

**Effect (server, `triggerMidAirRecharge`, called from `ProcessReceipt`):**
```lua
local function triggerMidAirRecharge(player, isTest)
    player:SetAttribute("MidAirRechargeCount", (player:GetAttribute("MidAirRechargeCount") or 0) + 1)
    local ls = player:FindFirstChild("leaderstats")
    local cp, sm = ls and ls:FindFirstChild("CurrentPower"), ls and ls:FindFirstChild("StomachMax")
    if cp and sm then cp.Value = sm.Value end          -- server meter -> 100% (gut max); sticks past the landing sync
    GamepassEvent:FireClient(player, {midAirRecharge = ..., rechargeNow = true})
end
```

**Client reaction (`GamepassEvent` handler + the recharge pause):**
- On `rechargeNow`, the client refills its displayed meter to MAX and, if you're
  mid-flight, **pauses you hovering with a full meter** (`Frozen`/anchored), waiting.
- `_G.rechargeAwaitingFart = true` → your NEXT fart press unpauses you
  (`_G.endRechargePause()`) and resumes flight on the full meter.

So: buy it while flying → instantly back to 100% gas → tap fart → keep climbing.

---

## 4) SKIP ISLAND (product) — jump to the next island

**Effect (server, `triggerSkipIsland`, called from `ProcessReceipt` on purchase):**
```lua
local function triggerSkipIsland(player)
    local current = highestIslandReached[player] or 1
    if current >= 14 then return end                    -- already at the top
    local target = current + 1
    highestIslandReached[player] = target
    player:SetAttribute("HighestIsland", target)
    local island = player.leaderstats:FindFirstChild("Island")
    if island and island.Value < target then island.Value = target end -- unlock the food shop / UI
    teleportToHome(player.Character, standData[target])  -- teleport onto the next island's home stand
end
```
- Instant on purchase (no second button): teleports you to the **next island above
  your current highest** (e.g., 6 → 7), repeatable up to island 14, and moves your
  home base + `Island` stat so respawn/return/unlocks all follow.

---

## The receipt flow that ties products together (`ProcessReceipt`)

```lua
MarketplaceService.ProcessReceipt = function(info)
    local player = Players:GetPlayerByUserId(info.PlayerId)
    if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
    if info.ProductId == PRODUCT_IDS.TwoXOneHour then
        player:SetAttribute("TwoXHourExpiry", os.time() + 3600)
        GamepassEvent:FireClient(player, {twoXHourExpiry = os.time() + 3600})
    elseif info.ProductId == PRODUCT_IDS.MidAirRecharge then
        triggerMidAirRecharge(player)
    elseif info.ProductId == PRODUCT_IDS.SkipIsland then
        triggerSkipIsland(player)
    end
    fireProductAnnouncement(player, info.ProductId)      -- the buy banner (see PURCHASE_BANNER.md)
    return Enum.ProductPurchaseDecision.PurchaseGranted
end
```
Gamepasses (2x Forever, etc.) are granted in `PromptGamePassPurchaseFinished`,
not here. The buy banner for everyone is covered in `PURCHASE_BANNER.md`.
```
