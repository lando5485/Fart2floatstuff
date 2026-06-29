# Pet Movement, Upgrades & Trail — Reference

How the pet follows you, how the level upgrades work, and how the trail is built.
Source: `src/client/PetFollow.client.lua`. Self-contained copy: `src/client/PetMoveUpgrades_AllInOne.client.lua`.

Demo controls (in the standalone copy): `]` / `[` level ±1 · `R` toggle rare · `P` swap pet.

---

## 1. How it moves with you (the FOLLOW loop)

Runs every frame in `RunService.RenderStepped`.

| Thing | Value / formula | Why |
|---|---|---|
| Target spot | `hrp.CFrame * CFrame.new(FOLLOW_OFFSET)` | a fixed spot relative to you |
| `FOLLOW_OFFSET` | `Vector3.new(3.5, 1.5, 5)` | 3.5 right, 1.5 up, 5 **behind** (+Z) |
| Position ease | `alpha = 1 - exp(-FOLLOW_K * dt)` | frame-rate-independent spring glide |
| `FOLLOW_K` | `6` | lower = softer/flowier (no micro-bounce) |
| Facing ease | `fAlpha = 1 - exp(-FACE_K * dt)` | a **slower** spring than position |
| `FACE_K` | `4` | pet **swings around** to turn, doesn't snap |
| `MAX_TRAIL` | `45` | clamp so a fast fart-ascent never strands it |
| Bob | `sin(bobT * 1.4) * 0.10` | gentle vertical float |

Steps each frame:
1. `petSmoothPos = petSmoothPos:Lerp(targetPos, alpha)` — eased glide toward the offset spot.
2. Clamp: if `(petSmoothPos - targetPos).Magnitude > MAX_TRAIL`, pull it back onto the 45-stud sphere.
3. `petSmoothFwd = petSmoothFwd:Lerp(playerHeading, fAlpha)` — eased facing (slower → graceful swing turns).
4. `pet:PivotTo(CFrame.lookAt(renderPos, renderPos + face) * CFrame.Angles(0, rad(90), 0))`.
   The `+90°` yaw is because the model is built with **+X = front**.
5. `animatePet(pet, dt)` layers per-part motion on top of the root placement.

**Per-part animator (`animatePet`)** — reads the live root CFrame, writes local offsets:
- Whole body: soft breathing bob + sway + forward lean when moving.
- `head`: bob + idle nod + side glance (pivoted at the neck base).
- `tail`: side-to-side sway.
- `leg`: diagonal gait (front-left + back-right in phase).
- `ear`: floppy wiggle. `wing`: flap. `claw`: scuttle.
- `eye`: blink squash every ~2–5 s.
- Everything scales by `sizeMul` (level size) × `popMul` (level-up bounce).

---

## 2. How the upgrades work (`applyLevelVisual`)

Server-authoritative level → cosmetic look. Idempotent: `clearEvo` strips the added
parts/effects and re-applies, so equip + live level-ups stay clean. **The base pet is
never modified** — upgrades are only size, effects, and welded accessory parts.

`frac = (level - 1) / 24` (0 at Lv1 → 1 at Lv25). `ramp(startL)` = 0 at `startL` → 1 at Lv25.

| Level | What appears | Detail |
|---|---|---|
| **every** | **Size** | `sizeMul = 0.6 + 0.4 * frac` → 60% @1, 100% @25 (+1.667%/level) |
| **2** | **Aura** | themed `Highlight` glow + `PointLight` (bright `2.5+4t`, range `8+8t`) + soft particles `8+34t` |
| **3 / 7 / 10 / 13 / 17 / 20 / 23** | **Accessories** | per-pet schedule, accumulating (see below) |
| **5** | **Trail** | see section 3 |
| **8** | **Sparkles** | `PetSparkle` emitter, rate `14 + 90t` |
| **11 / 14 / 19** | **Floating orbs** | 1 / 2 / 3 neon orbs, orbit radius 2.0 |
| **15** | **Energy ring** | 8 neon beads on a tilted (22°) spinning circle, radius 2.2 |
| **18** | **Pulse** | neon cylinder that expands + fades on a 1.3 s loop |
| **24** | **Burst** | `PetBurst` emitter fires 18 particles every 1.3 s |
| **25 (MAX)** | **Gold + shimmer** | accessories get gold trim; rainbow shimmer hue-cycles aura/trail/orbs/ring |

On a **live level-up**: `popClock = 0.4` (scale-pop bounce) + a one-shot 20-particle burst.
The orbs/ring/pulse/burst/shimmer are stored in `petFX[pet]` and animated by the FX `Heartbeat` loop.

**Per-pet accessory schedule** (`PET_THEME[petId].accs`):

| Lv | Coconut Crab | Popcorn Sheep | Butter Duck |
|----|--------------|---------------|-------------|
| 3  | bowtie | bell | bowtie |
| 7  | glasses | glasses | glasses |
| 10 | piratehat | tophat | tophat |
| 13 | backpack | scarf | scarf |
| 17 | sword | flower | monocle |
| 20 | gemcluster | cloudcluster | sparklecluster |
| 23 | anchor | crook | cane |

(Broccoli Bunny / Burrito Armadillo reuse the same machinery: bowtie/glasses/crown/backpack/flower/haloring/staff and bowtie/glasses/safari/backpack/gemstuds/lantern/pickaxe.)

**Rare variants** (`applyRareLook`): forced to the full Lv-25 look, then a unique body
sheen (color + material + reflectance) + a rare sparkle aura on top. E.g.:
- Golden Crab — solid metal gold + gold sparkles
- Cloud Sheep — white-blue plastic sheen + cloud puffs + soft light
- Cosmic Duck (Mythical) — deep-space body + swirling stars + rainbow cosmic aura

---

## 3. The trail behind the pet (Lv5+)

Built inside `applyLevelVisual` when `level >= 5`:

```lua
local t = ramp(5) -- 0 at Lv5 -> 1 at Lv25
local a0 = Instance.new("Attachment"); a0.Name="PTrailA0"; a0.Position = Vector3.new(0, 1.0, 0); a0.Parent = root
local a1 = Instance.new("Attachment"); a1.Name="PTrailA1"; a1.Position = Vector3.new(0,-1.0, 0); a1.Parent = root
local tr = Instance.new("Trail"); tr.Name="PetTrail"; tr.Attachment0 = a0; tr.Attachment1 = a1
tr.Color = ColorSequence.new(theme.color); tr.LightEmission = 0.6
tr.Lifetime = 0.5 + 1.1*t  -- LENGTHENS: 0.5s @Lv5 -> 1.6s @Lv25
tr.Transparency = NumberSequence.new({          -- BRIGHTENS with level
    NumberSequenceKeypoint.new(0, math.clamp(0.35 - 0.3*t, 0, 1)), -- head: 0.35 -> 0.05
    NumberSequenceKeypoint.new(1, 1),                              -- tail fades out
})
tr.Parent = root
```

- The two attachments sit 1 stud **above** and 1 stud **below** the root — the gap between
  them is the trail's **width**. As the pet moves, Roblox streaks a ribbon between them.
- It **lengthens** (Lifetime `0.5 → 1.6 s`) and **brightens** (head transparency `0.35 → 0.05`)
  as the level climbs from 5 to 25, themed to the pet's color.
- At MAX, the shimmer loop hue-cycles the trail color (`(hue+0.5)%1`).
- `clearEvo` removes `PetTrail`, `PTrailA0`, `PTrailA1` on every re-apply so it never doubles up.
