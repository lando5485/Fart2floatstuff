# Burrito Barrens — Dig Quest & Animation Reference

How island 13's BurritoArmadillo "dig up the buried egg" quest works.
Source: `buildBurritoWorld` in `src/client/PetFollow.client.lua` (client = props + animation)
and `PetSystem.server.lua` (the anti-cheat claim gate).
Self-contained copy: `src/client/BurritoDig_AllInOne.client.lua`.

---

## Quest flow

| Step | What happens |
|---|---|
| 1. Grab shovel | A low-poly wooden **barrel** with 3 shovels sticking out. `Grab Shovel` prompt (E, **0.3s hold**). On grab, `st.hasShovel = true` and a shovel starts following your hand. |
| 2. Held shovel | A Heartbeat loop pins a matching shovel to your **RightHand**: the shaft aims `(look + (0,-0.5,0)).Unit` so the **blade points down-forward**, grip at the hand. |
| 3. Dig the trail | 6 stops, **one active at a time**: DigSpot1 → 2 → 3 → 4 → 5 → **BuriedEggSpot**. Each is a hidden low-poly dirt mound; only the active one is shown + has its `Dig` prompt enabled. |
| 4. Swing | Each E-tap = **one swing** (`HoldDuration 0`, prompt on its own persistent anchor so shrinking the mound never removes it → it re-arms every press). **6 swings** fully digs a mound. |
| 5a. Decoy | A fully-dug decoy **rises JUNK** out of the hole + lays **armadillo tracks** to the next mound, which then activates. |
| 5b. Real spot | `BuriedEggSpot` fully dug → the **armadillo egg rises** up out of the hole → Hatch prompt. |

---

## The dig-swing animation (`doSwing`, per E-tap)

Each swing does all of:
1. **Shrink** the mound a step: `mound:ScaleTo(math.max(0.06, 1 - swings/6))` — the part-based "dig".
2. **Dirt burst**: a ParticleEmitter (`smoke_main.dds`, brown ColorSequence, Speed 10–18, SpreadAngle 40,
   `Acceleration (0,-44,0)` so it falls back down, EmissionDirection Top) does `em:Emit(20)`.
3. **Dig sound**: `rbxassetid://9114065998` (Volume 0.55) — replayed from `TimePosition = 0` each swing. *(placeholder — swap freely)*
4. **Camera kick**: `Humanoid.CameraOffset = (rand·0.5, -0.35, 0)` then tweened back to zero over 0.18s — a little jolt for feel.

On the 6th swing the prompt disables, the mound hides, the dirt FX is cleaned up (`Debris:AddItem(fxAnchor, 1.2)`),
and the trail either advances (decoy) or reveals the egg (real spot).

---

## Decoy reveal — junk + tracks

- **`junkRise(pos, junkName)`** — a brown ball with a junk-emoji billboard starts at `pos + (0,-3,0)` and
  tweens up to `pos + (0,1.3,0)` (Back ease, 0.55s), holds 2.4s, then fades. Junk pool:
  boot 🥾 · cattle skull 💀 · rusty can 🥫 · cactus 🌵 · horseshoe 🧲 · coyote bone 🦴 · tumbleweed 🌾.
- **`spawnTracks(from, to)`** — a line of footprints (flat oval `Ball 0.95×0.12×1.35` + 3 toe dots) alternating
  left/right of the path, **raycast-grounded** to the floor, leading ~85% of the way (stops short of the next mound),
  fading in. One print roughly every ~7 studs (clamped 4–16). This is the cue the player follows.

---

## The egg rising (`spawnArmadilloEgg`)

- A sandy egg: one `Shell` ball with a `Sphere` SpecialMesh scaled `(3.0, 4.0, 3.0)` (color `224,194,148`,
  Reflectance 0.05) + 6 brown specks around it, in a `Visual` sub-model. A tan Highlight.
- It starts **down inside the hole** at `pos + (0,-3.4,0)` and **rises** to `pos + (0,1.7,0)`.
  Because Models can't be tweened directly, a `NumberValue` (0→1, Back ease, 1.15s) drives a
  `startCF:Lerp(baseCF, t)` `PivotTo` each change.
- The **Hatch prompt is disabled until it has fully risen** (`st.eggRising`), then it bobs gently
  (paused while rising or hatching). Hatch reuses the shared hatch flow (shake → crack → pet pops).

---

## Server gate (anti-cheat) — `PetSystem.server.lua`

- Digging the **real** spot fires `PetDigEvent:FireServer(petId)`.
- `PetDigEvent.OnServerEvent` sets `digEggReady[player] = true`.
- `PetClaimEvent` **rejects** the BurritoArmadillo claim unless `digEggReady[player]` is set — so the
  client can never fake unearthing the egg. Decoy digs are purely cosmetic and never call the server.
- `digEggReady` is **session-only** (you re-dig after a rejoin); the claim writes ownership + persistence.

In the standalone copy this remote is fired only if it exists, so it runs without the server; the hatch is a
short stand-in (the real shared `hatchEgg` lives in `PetFollow` / the egg file).

---

## Markers (server-provided in the real game)

`ShovelSpot`, `DigSpot1`–`DigSpot5`, `BuriedEggSpot`. The client never searches Workspace — it asks the server
for these coordinates (`PetGetMarkers`) and builds from them. The standalone copy instead lays a wandering
6-stop trail out in front of the player and raycast-grounds each mound.
