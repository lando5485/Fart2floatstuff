# Pet Upgrade System — Full Reference

How pets gain levels through **flight**, how **Robux** buys levels, and exactly how a pet's look
changes as it climbs from Common → Uncommon → Rare → Epic → Legendary (and the rare-only
Exotic / Mythical tiers above them).

Everything in this system is **cosmetic**. No pet level, tier, accessory or effect touches flight
speed, gas, stomach, or coin earn rate. Pets are a prestige/vanity track that *feeds off* flight
but never *feeds back into* it.

---

## 1. Where the code actually lives

| File | Role | Synced by Rojo? |
|---|---|---|
| `src/server/PetSystem.server.lua` | **The live system.** Owns levels, XP, tiers, Robux receipts, rares, persistence. | ✅ yes (`default.project.json:17`) |
| `src/client/PetFollow.client.lua` | **The live visuals.** Applies size/aura/trail/sparkles/orbs/accessories per level; owns the inventory GUI + Robux prompt. | ✅ yes (`default.project.json:283`) |
| `src/server/PetUpgrades_AllInOne.server.lua` | Standalone demo/reference copy of the same logic. | ❌ **not synced — dead file** |
| `src/client/PetHub_AllInOne.client.lua` | Standalone demo/reference copy of the GUI. | ❌ **not synced — dead file** |
| `src/client/PetMoveUpgrades_AllInOne.client.lua` | Standalone demo/reference copy. | ❌ **not synced — dead file** |

> **Important:** the `*_AllInOne` files duplicate the XP constants, the tier bands and the Robux
> product IDs. They are **not** in `default.project.json`, so they never run in-game. If you tune a
> number, tune it in `PetSystem.server.lua` / `PetFollow.client.lua` — editing an `_AllInOne` file
> changes nothing. (They're a landmine: they *look* authoritative and they'd overwrite the same
> `_G.petOn*` hooks if anyone ever added them to the Rojo tree.)

### 1a. There are two leveling systems in the file — only one is live

The `PETS` catalog at the top of `PetSystem.server.lua` still carries an **old 3-level
achievement system**:

```lua
maxLevel = 3,
tiers = {
    [2] = { height = 1200, time = 90 },
    [3] = { height = 6000, time = 300 },
}
```

…backed by `nextTier()`, `canUpgrade()` and the `PetUpgradeEvent` remote. This was the original
"reach 1200 studs OR carry the pet 90 seconds → level 2" design. **It is superseded.** The live
system is the 25-level XP curve below. The old `tiers`/`maxLevel` data still gets read by
`canUpgrade()` (which only drives a diagnostic `print` and an inventory resend), but it no longer
gates any actual level-up. The `height` and `time` counters are still tracked and still persist —
they're just cosmetic stats on the card now.

**Cleanup candidate:** `maxLevel = 3` and the `tiers` tables can be deleted along with
`nextTier`/`canUpgrade`/`PetUpgradeEvent` once you're sure nothing else reads them.

---

## 2. The core model

Every owned pet is one row of saved data:

```lua
{ level = 1, xp = 0, height = 0, time = 0, count = 1, rare = false }
```

- **`level`** — 1 to 25. This is the *only* number that drives tier and appearance.
- **`xp`** — progress toward the *next* level. Resets to the remainder on level-up.
- **`level` is capped at `PET_MAX_LEVEL = 25`.** At 25, XP stops accruing and is forced to 0.
- **`rare`** — a hatch flag. Rares come **pre-maxed** and display as level 25 regardless of stored level.

Pets are stored under a **storage key**, not just a species id:

- `"ButterDuck"` → the normal variant
- `"ButterDuck#R"` → the rare variant

A player can own **both** at once; they are two separate stacks, each with its own level, each
independently equippable and tradeable.

---

## 3. Earning levels through flight (the main path)

### 3a. Only the EQUIPPED pet earns XP

`awardXP()` reads `_G.playerEquippedPet[player]` and awards to that pet only. Unequipped pets are
frozen at whatever level they were. **If you want to level a second pet, you must equip it.** This
is the single most important rule in the system and it's easy to miss.

### 3b. The four XP sources

All rates live at the top of the leveling block in `PetSystem.server.lua`:

| Source | Constant | Rate | Fires when |
|---|---|---|---|
| **Distance flown** | `XP_PER_FLIGHT_TICK` | **6 XP per tick** | every 0.5 s **during flight** → **12 XP/sec** |
| **Coins earned** | `XP_PER_COIN` | **0.15 XP per coin** | same 0.5 s flight tick, proportional to coins banked |
| **Gas / food** | `XP_PER_GAS` | **0.5 XP per power** | every time you eat food (power gained) |
| **New island** | `XP_PER_ISLAND` | **600 XP flat** | first time you reach each island |

Hook sites (all in `PlayerStats.server.lua`, plus one in `Shop_AllInOne.server.lua`):

```
PlayerStats:956   _G.petOnGas(player, powerGain)      -- eating food
PlayerStats:977   _G.petOnCoins(player, amt)          -- coin tick
PlayerStats:978   _G.petOnFlightTick(player)          -- distance tick
PlayerStats:989   _G.petOnIsland(player)              -- new island unlocked
```

### 3c. What that means in practice — flight XP scales *hard* with altitude

The distance component is flat (12 XP/sec), but the **coin** component rides the game's coin
formula, which is quadratic in height:

```
coins per 0.5s tick = height * 0.008 + (height / 500)^2
XP from coins       = coins * 0.15
```

So the XP you earn per second of flight, by altitude:

| Altitude (Y) | Coins / tick | XP/sec from coins | + distance | **Total XP/sec** |
|---|---|---|---|---|
| 500 | 5 | 1.5 | 12 | **~13.5** |
| 1,000 | 12 | 3.6 | 12 | **~15.6** |
| 4,000 (Coconut Cove) | 96 | 28.8 | 12 | **~40.8** |
| 11,500 (Popcorn Pinnacle) | 621 | 186 | 12 | **~198** |
| 24,000 (Ice Cream Isle) | 2,496 | 749 | 12 | **~761** |
| 45,000 (Pizza Palms) | 8,460 | 2,538 | 12 | **~2,550** |

**Design consequence:** low-altitude players grind pet levels slowly (a few XP/sec); late-game
players at 45k studs earn a full early level *every second of flight*. The pet track is therefore
back-loaded — it's essentially free once you're deep in the game, and the meaningful grind window
is roughly islands 1–8.

### 3d. The XP curve

```lua
PET_XP_BASE, PET_XP_EXP = 80, 1.6
xpNeeded(L) = math.floor(80 * L^1.6)      -- XP to go from level L to L+1
```

A rising curve — level 1→2 is trivial, 24→25 is a real grind.

| Lvl | XP to next | Cumulative from Lv1 | | Lvl | XP to next | Cumulative from Lv1 |
|---|---|---|---|---|---|---|
| 1 | 80 | 80 | | 13 | 4,846 | 26,695 |
| 2 | 242 | 322 | | 14 | 5,456 | 32,151 |
| 3 | 463 | 785 | | 15 | 6,093 | 38,244 |
| 4 | 735 | 1,520 | | 16 | 6,755 | 44,999 |
| 5 | 1,050 | 2,570 | | 17 | 7,444 | 52,443 |
| 6 | 1,406 | 3,976 | | 18 | 8,156 | 60,599 |
| 7 | 1,799 | 5,775 | | 19 | 8,893 | 69,492 |
| 8 | 2,228 | 8,003 | | 20 | 9,654 | 79,146 |
| 9 | 2,690 | 10,693 | | 21 | 10,438 | 89,584 |
| 10 | 3,184 | 13,877 | | 22 | 11,245 | 100,829 |
| 11 | 3,709 | 17,586 | | 23 | 12,074 | 112,903 |
| 12 | 4,263 | 21,849 | | 24 | 12,924 | **125,827** |

**Total XP to take one pet from Level 1 → Level 25: 125,827 XP.**

Sanity check against flight: at Pizza Palms altitude (~2,550 XP/sec) that's **under a minute** of
flight. At Broccoli Bluff altitude (~15 XP/sec) it's **~2.3 hours**. Eating a Pizza (750 power)
gives 375 XP; each new island gives 600 XP.

### 3e. Level-up mechanics

`awardXP()` adds XP, then loops:

```lua
while d.level < PET_MAX_LEVEL do
    local need = xpNeeded(d.level)
    if d.xp < need then break end
    d.xp = d.xp - need          -- carry the remainder
    levelUp(player, petId, ...)  -- can chain multiple levels in one tick
end
```

- **Remainder carries** — overflow XP rolls into the next level.
- **Multi-level-ups in a single tick are supported** (common at high altitude).
- Every `levelUp()` calls `sendState()` (follower re-applies its visual), `sendInventory()` (card
  updates), and `broadcastEquip()` (other players see the new look).
- Inventory resends are throttled to once per 2.5 s except on level-up, which forces an immediate sync.

---

## 4. The rarity tiers — how a pet "adapts" as it climbs

`petTier(level, isRare, petId)` in `PetFollow.client.lua`. Tier is derived purely from level —
there is no separate stored rarity for normal pets.

| Tier | Levels | Badge colour | Notes |
|---|---|---|---|
| **Common** | 1–5 | grey `(175,180,190)` | starting tier |
| **Uncommon** | 6–10 | green `(90,210,90)` | |
| **Rare** | 11–15 | blue `(70,140,255)` | |
| **Epic** | 16–20 | purple `(180,90,235)` | |
| **Legendary** | 21–25 | orange `(255,170,40)` | top tier reachable by leveling |
| **Exotic** | *rare hatch* | cyan `(40,235,225)` | **outranks Legendary**; glows |
| **Mythical** | *rare Butter Duck only* | magenta `(255,70,230)` | **top of everything**; glows |

Exotic/Mythical are **not levels** — they're the rare-variant flag. A rare pet ignores its stored
level and always renders at the full level-25 look, and its badge shows the tier name *without* a
"Lv N" suffix (normal pets show e.g. `Epic  Lv 17`).

Inventory sort rank: `Mythical 7 > Exotic 6 > Legendary 5 > Epic 4 > Rare 3 > Uncommon 2 > Common 1`.

---

## 5. What actually changes on the pet, level by level

`applyLevelVisual(pet, level, petId, isRare, lite)` in `PetFollow.client.lua`. It **never modifies
the base pet's own parts** — body evolution was removed. Upgrades are **size + accessories +
effects** layered on top, and the whole layer is torn down and rebuilt (`clearEvo`) on every
equip/level-up so it's idempotent.

### 5a. Size — the guaranteed change every single level

```lua
frac      = (level - 1) / 24          -- 0 at Lv1, 1 at Lv25
A.sizeMul = 0.6 + 0.4 * frac
```

**60% scale at Level 1 → 100% scale at Level 25**, +1.667% per level. This is the one thing that
changes on *every* level-up, so no level ever feels dead.

### 5b. The effect ladder

| Level | Unlocks | Detail |
|---|---|---|
| **2** | **Aura** | Themed `Highlight` glow + `PointLight` + soft particles. Brightens every level after (`ramp(2)`). |
| **5** | **Trail** | Themed `Trail` off the body. Lengthens + brightens every level (lifetime `0.5 → 1.6`). |
| **8** | **Sparkles** | Particle emitter. Density ramps `14 → 104` rate as level climbs. |
| **11** | **Orb ×1** | Glowing neon orb orbiting the pet. |
| **14** | **Orb ×2** | Second orbiting orb. |
| **15** | **Energy ring** | 8 glowing beads spinning on a tilted circle. |
| **18** | **Pulse** | Expanding/fading ring burst. |
| **19** | **Orb ×3** | Third orbiting orb. |
| **24** | **Burst** | Periodic ambient particle burst. |
| **25** | **GOLD + shimmer** | All accessories re-tinted `PRESTIGE_GOLD`; shimmer flag on; full FX stack. |

Effects that "ramp" recompute their intensity from the current level, so e.g. an Epic-tier pet's
aura is visibly brighter than a Rare-tier pet's even though both simply "have an aura."

### 5c. Accessories — 7 per pet, at levels 3 / 7 / 10 / 13 / 17 / 20 / 23

They **accumulate** (a level-23 pet is wearing all seven), and at **level 25 they all turn gold**.

| Pet | Lv 3 | Lv 7 | Lv 10 | Lv 13 | Lv 17 | Lv 20 | Lv 23 |
|---|---|---|---|---|---|---|---|
| **Broccoli Bunny** | bowtie | glasses | crown | backpack | flower | halo ring | staff |
| **Coconut Crab** | bowtie | glasses | pirate hat | backpack | sword | gem cluster | anchor |
| **Popcorn Sheep** | bell | glasses | top hat | scarf | flower | cloud cluster | crook |
| **Butter Duck** | bowtie | glasses | top hat | scarf | monocle | sparkle cluster | cane |
| **Burrito Armadillo** | bowtie | glasses | safari hat | backpack | gem studs | lantern | pickaxe |
| **Sunflower Bee** *(seasonal)* | bowtie | glasses | crown | backpack | flower | halo ring | staff |
| **Maple Fox** *(seasonal)* | bowtie | glasses | crown | backpack | flower | halo ring | staff |
| **Frost Penguin** *(seasonal)* | bowtie | glasses | top hat | scarf | monocle | sparkle cluster | cane |
| **Blossom Bunny** *(seasonal)* | bowtie | glasses | crown | backpack | flower | halo ring | staff |

Accessories are welded into the pet's animation list with `role="body"`, so they track the pet's
bob/sway and the size tier every frame — they can never float off.

### 5d. Full progression, tier by tier

- **Common (1–5)** — 60→77% size. Aura from 2. Bowtie at 3. Trail at 5. *Small, plain, a bit sparkly.*
- **Uncommon (6–10)** — 77→90% size. Glasses at 7. Sparkles at 8. Hat/crown at 10. *Clearly dressed up and glowing.*
- **Rare (11–15)** — 90→100%… (still ramping). First orb at 11. Backpack/scarf at 13. Second orb at 14. Energy ring at 15. *Now it has orbiting objects — the "this player has invested" read.*
- **Epic (16–20)** — Accessory #5 at 17. Pulse at 18. Third orb at 19. Accessory #6 at 20. *Full orbital + pulse + 6 accessories.*
- **Legendary (21–25)** — Accessory #7 at 23. Burst at 24. **Level 25: gold trim on everything + shimmer + max size.** *The flex.*
- **Exotic / Mythical (rare hatch)** — renders as a level-25 pet, then a **rare body sheen** is painted on top (see §7).

### 5e. Known inconsistency — the milestone hint text is wrong

`tierVisual()` and `nextMilestoneHint()` on the server advertise milestones at **3 / 8 / 13 / 18 / 23**
("Lvl 8: accessory #2 (glasses)"), and `isMilestone()` agrees. But the actual accessory schedule in
`PET_THEME` is **3 / 7 / 10 / 13 / 17 / 20 / 23**. So the card's "next milestone" hint tells players
glasses arrive at 8 when they actually arrive at 7, and it never mentions the level-10, -17 or -20
accessories at all.

**Fix:** make `nextMilestoneHint`/`isMilestone` read the real `{3,7,10,13,17,20,23}` schedule.

---

## 6. Buying levels with Robux — the tier-skip products

### 6a. The four products

Each product jumps the pet to the **first level of the next tier**, and sets `xp = 0`.

| Product ID | Price | From tier (src levels) | Jumps to | Levels gained |
|---|---|---|---|---|
| `123456701` ⚠ | **49 R$** | Common (1–5) | **Level 6** (Uncommon) | 1–5 |
| `123456702` ⚠ | **99 R$** | Uncommon (6–10) | **Level 11** (Rare) | 1–5 |
| `123456703` ⚠ | **299 R$** | Rare (11–15) | **Level 16** (Epic) | 1–5 |
| `123456704` ⚠ | **599 R$** | Epic (16–20) | **Level 21** (Legendary) | 1–5 |

There is **no product for Legendary (21–25)** — `nextTierTarget()` returns `nil` at the top tier, and
the client hides the skip button. **You cannot buy your way to level 25**; the last 4 levels must be
flown. (That's a deliberate-looking gate, and a good one — the gold/shimmer max look stays earned.)

### 6b. ⚠ ALL FOUR PRODUCT IDs ARE PLACEHOLDERS

`123456701`–`123456704` are fake. Until real Developer Product IDs are created and pasted into
**both** places, real purchases will not grant anything (the prompt errors harmlessly):

- `src/server/PetSystem.server.lua` → `PET_SKIP_PRODUCTS` (the authoritative table)
- `src/client/PetFollow.client.lua` → `PET_SKIP_PRODUCTS` (the prompt + price label)

There is also a legacy `PET_UPGRADE_PRODUCT_ID = 123456789` still declared — dead, superseded by the
tier-skip products. Safe to delete.

### 6c. The purchase flow

```
1. Client (PetFollow) picks the skip step matching the pet's CURRENT level:
      level <=5 -> product 1,  <=10 -> product 2,  <=15 -> product 3,  <=20 -> product 4,  else none
2. Client fires PetPendingUpgradeEvent(petId)   -- "this is the pet I'm about to skip"
      -> server stores pendingRobuxPet[userId] = petId
3. Client calls MarketplaceService:PromptProductPurchase(player, productId)
4. Player pays.
5. PlayerStats owns the SINGLE MarketplaceService.ProcessReceipt (PlayerStats:1556),
   which delegates to _G.petsHandleReceipt(player, productId)  (PlayerStats:1597)
6. Server validates + applies the jump.
```

### 6d. The anti-cheat — a cheap product can never skip a high tier

This is the important part. `_G.petsHandleReceipt` re-checks the pet's level **against the product's
own source band** at receipt time:

```lua
if d.level >= prod.srcMin and d.level <= prod.srcMax then
    d.level = prod.target; d.xp = 0     -- only applies inside this product's source tier
    ...
    return true
end
warn("... not applicable ...")           -- pet leveled past the band before the receipt landed
return true                              -- consume the receipt WITHOUT a wrong jump
```

So buying the **49 R$** Common→Uncommon product while sitting at level 18 does **not** jump you to
level 6 (a downgrade) or to Legendary (a steal) — it's rejected, and the receipt is *consumed
anyway* (`return true`) so Roblox doesn't retry it forever.

> **⚠ Player-facing risk:** that rejection path takes the player's Robux and grants nothing. It's the
> right call for receipt hygiene (never re-deliver), but it can fire legitimately — a player at level
> 5 who buys the 49 R$ skip and then levels to 6 from a coin tick *while the purchase dialog is open*
> loses the purchase. Worth either (a) refunding by granting the *correct* tier skip for their new
> level, or (b) freezing XP for that pet while a purchase is pending.

### 6e. Value-per-Robux is uneven

Each product costs the same regardless of where you are in the band. Buying the 49 R$ skip at
**level 1** gains you **5 levels**; buying it at **level 5** gains you **1 level** — same price.
Players who understand this will always buy immediately after entering a tier. Consider either
per-level pricing or advertising it as "jump to the next tier" (which the label already does).

### 6f. Test path (⚠ remove before launch)

`PetPendingUpgradeEvent` short-circuits for test accounts:

```lua
if _G.isAllowedTestUser and _G.isAllowedTestUser(player) then
    tierSkip(player, petId, "test")   -- instant tier jump, NO purchase
    return
end
```

`tierSkip()` computes the target **server-side** from the pet's current level, so even the test path
can never skip more than one tier.

---

## 7. Rare hatch variants (Exotic / Mythical)

- **Odds:** `1 / 99` for every pet — **except Butter Duck at `1 / 500`** (ultra-rare).
- **Roll timing:** on hatch, and **first-completion-only**. `_G.playerEverCompletedQuests` permanently
  records that a player has completed a pet's quest; a *re-run* of the quest (after trading the pet
  away) grants a **guaranteed normal** pet. **Rares can never be farmed by repeating the quest.**
- **A rare comes pre-maxed:** stored as `{ level = 25, xp = 0, rare = true }`, and
  `applyLevelVisual` hard-forces `level = 25` whenever `isRare`.
- **Rare look** (`RARE_LOOK`, applied *on top of* the maxed visuals — eyes, accessories and level FX
  are left intact):

| Pet | Rare name | Tier | Body | Material | Refl | Extra |
|---|---|---|---|---|---|---|
| Broccoli Bunny | **Emerald Bunny** | Exotic | emerald green | Glass | 0.25 | green crystal sparkles |
| Coconut Crab | **Golden Crab** | Exotic | solid gold | Metal | 0.35 | gold sparkles |
| Popcorn Sheep | **Cloud Sheep** | Exotic | white-blue | Plastic | 0.10 | cloud puffs + soft light |
| Burrito Armadillo | **Crystal Armadillo** | Exotic | amethyst | Glass | 0.25 | crystal-shard sparkles |
| **Butter Duck** | **Cosmic Duck** | **Mythical** | deep-space navy | Plastic | 0.10 | swirling stars + rainbow cosmic aura + light |

A rare is a **separate storage slot** (`petId#R`), so you can own the normal *and* the rare of the
same species side by side and equip either.

---

## 8. Other ways levels are granted

| Path | Function | Notes |
|---|---|---|
| **Mystery Meteor Crate** | `_G.petGrantLevels(player, petId, n)` | Player picks an owned pet; grants N levels. Funnels through `levelUp()` per step, so every step re-syncs follower + GUI + broadcast. Clamps at 25. Returns `oldLevel, newLevel, levelsAdded` (`levelsAdded == 0` if already maxed). Called from `CrateService.server.luau:160`. |
| `_G.petListOwnedForCrate` | — | Feeds the crate's pet picker: `{petId, displayName, level, maxed, xp, xpNeed, xpPct}`. |
| **Test: grant all rares** | `_G.petsGrantRare(player)` | ⚠ `/rarepets` — grants every pet as its rare variant, pre-maxed. `PlayerStats:1720`. Remove before launch. |
| **Test: skip** | `tierSkip(..., "test")` | ⚠ see §6f. |

---

## 9. Persistence

- **`_G.playerOwnedPets[player]`** — `[storageKey] = {level, xp, height, time, count, rare}`.
  Persisted by `PlayerStats` under `saved.ownedPets`.
- **`_G.playerEquippedPet[player]`** — the equipped **storage key** (persisted).
- **`_G.playerDiscoveredQuests[player]`** — which pet quests the player has found (persisted).
- **`_G.playerEverCompletedQuests[player]`** — permanent; gates the first-time-only rare roll (persisted).
- **Piece progress is session-only** — deliberately not saved.

**Legacy-save safety:** `getPetData()` normalizes anything it finds. Old saves that stored a bare
`true` become `{level=1, xp=0, ...}`; missing fields default; levels above 25 are clamped down to 25.
There's also a one-time **migration** that re-keys a legacy rare stored under its plain species key
into the `petId#R` slot (and fixes the equipped key to match).

---

## 10. Summary — the player's journey

1. Complete an island quest (find pieces / crack coconuts / film reels / fishing / digging) → **hatch a pet at Level 1, Common, 60% size.**
   - 1-in-99 (1-in-500 for Butter Duck) it hatches **rare** — instantly maxed, Exotic/Mythical, full gold look + unique sheen. First completion only.
2. **Equip it** — only the equipped pet earns XP.
3. **Fly.** 12 XP/sec just for being airborne, plus 0.15 XP per coin (which explodes with altitude), plus 375 XP for a Pizza, plus 600 XP per new island.
4. It **grows 1.667% every level** and picks up an aura (2), trail (5), sparkles (8), bowtie (3), glasses (7), hat (10)…
5. **Level 6 → Uncommon. 11 → Rare** (orbs start orbiting). **16 → Epic** (pulse). **21 → Legendary.**
6. Impatient? **Buy the next tier for 49 / 99 / 299 / 599 R$.** You can skip up to Legendary — but the final stretch to **Level 25 (gold + shimmer + max size)** can only be flown.
7. Total cost of a max pet by flight: **125,827 XP**.

---

## 11. Pre-launch checklist

- [ ] **Replace the 4 placeholder Robux product IDs** in `PetSystem.server.lua` **and** `PetFollow.client.lua`.
- [ ] **Remove the test tier-skip path** (`_G.isAllowedTestUser` short-circuit in `PetPendingUpgrade`).
- [ ] **Remove `/rarepets`** (`_G.petsGrantRare`).
- [ ] **Fix the milestone hint text** — it advertises 3/8/13/18/23 but accessories land at 3/7/10/13/17/20/23 (§5e).
- [ ] **Handle the pending-purchase race** — a level-up mid-dialog eats the player's Robux (§6d).
- [ ] Delete the dead `PET_UPGRADE_PRODUCT_ID = 123456789`.
- [ ] Delete or Rojo-wire the three `*_AllInOne` pet files — right now they're misleading dead copies (§1).
- [ ] Decide the fate of the legacy 3-level `tiers`/`maxLevel` achievement data (§1a).
