# Fart to Float — Complete Sound Asset List

Read-only scan of `src/` (client + server). Every `rbxassetid://` used as a **Sound** is listed below.
The stale `scripts_dump/` folder contains no sound IDs — all live sounds live in `src/`.

**⚠️ Known-broken IDs** (flagged as not loading): `101642229651469`, `1369158752`, `3240498563`,
`9116544355`, `9116458024`, `9114402399`. These are marked **BROKEN** wherever they appear.
Note: `9116458024` and `9114402399` are reused across several scripts — replacing them fixes multiple spots at once.

---

## 🎵 Music

| Asset ID | Purpose | Script | Status |
|---|---|---|---|
| `140517328454242` | Background music track 1 | `MusicClient.client.lua`, preloaded in `EventSoundPreload.client.lua` | ✅ Works |
| `139448720739903` | Background music track 2 | `MusicClient.client.lua`, `EventSoundPreload.client.lua` | ✅ Works |
| `139206228229841` | Background music track 3 | `MusicClient.client.lua`, `EventSoundPreload.client.lua` | ✅ Works |
| `138099443718294` | Background music track 4 | `MusicClient.client.lua`, `EventSoundPreload.client.lua` | ✅ Works |

---

## 💨 Fart / Flight

7-item random pool — one is picked each time the player starts a fart/ascent (`FART_SOUND_IDS`, vol 0.6).

| Asset ID | Purpose | Script | Status |
|---|---|---|---|
| `137105349517966` | Fart/ascent sound (random pool #1) | `CoreClient.client.lua` | ✅ Works |
| `136812322649032` | Fart/ascent sound (random pool #2) | `CoreClient.client.lua` | ✅ Works |
| `119702591396866` | Fart/ascent sound (random pool #3) | `CoreClient.client.lua` | ✅ Works |
| `123499328258921` | Fart/ascent sound (random pool #4) | `CoreClient.client.lua` | ✅ Works |
| `92449881602559`  | Fart/ascent sound (random pool #5) | `CoreClient.client.lua` | ✅ Works |
| `109574021376037` | Fart/ascent sound (random pool #6) | `CoreClient.client.lua` | ✅ Works |
| `129402830763074` | Fart/ascent sound (random pool #7) | `CoreClient.client.lua` | ✅ Works |

---

## 🖱️ UI / Buttons

| Asset ID | Purpose | Script | Status |
|---|---|---|---|
| `101638558691673` | UI click sound (menu/button clicks, PLAY, island cards), vol 0.5 | `CoreClient.client.lua`, `LoadingScreen.client.lua` | ✅ Works |
| `87486053112716`  | "Insufficient funds" error sound (can't-afford stomach buy), vol 0.6 | `CoreClient.client.lua` | ✅ Works |

---

## 🛒 Shop / Purchases / Rewards

| Asset ID | Purpose | Script | Status |
|---|---|---|---|
| `103794849233173` | Eat / buy-food sound, vol 0.8 | `ShopClient.client.lua` | ✅ Works |
| `112825313814792` | Purchase banner + confetti sound (item bought), vol 0.8 | `CoreClient.client.lua` | ✅ Works |
| `115390827163601` | Ring collect SFX, vol 0.6 | `CoreClient.client.lua` | ✅ Works |
| `117464325212045` | Island arrival / "Welcome to island" sound, vol 0.8 | `CoreClient.client.lua` | ✅ Works |
| `9116458024`      | Beam blast "WHAM" hit sound, vol 1 | `CoreClient.client.lua` | ❌ **BROKEN** |

---

## 🐾 Pets / Quests

| Asset ID | Purpose | Script | Status |
|---|---|---|---|
| `9116458024` | Pet effect/pop sound, vol 0.6 | `PetFollow.client.lua` | ❌ **BROKEN** |

---

## ⛈️ Events / Storm / Hazards

### Thunderstorm & wind (EventClient)
| Asset ID | Purpose | Script | Status |
|---|---|---|---|
| `101642229651469` | Windstorm ambient loop | `EventClient.client.lua` | ❌ **BROKEN** |
| `97219963176654`  | Thunderstorm ambient loop | `EventClient.client.lua` | ✅ Works |
| `1369158752`      | Thunder clap, vol 0.8 | `EventClient.client.lua` | ❌ **BROKEN** |
| `3240498563`      | Bird screech, vol 1 | `EventClient.client.lua` | ❌ **BROKEN** |
| `121387867149574` | Bird / plane hazard sound, vol 0.8 | `EventClient.client.lua` | ✅ Works |
| `89988274755984`  | Nuke boom sound | `EventClient.client.lua` | ✅ Works |

### Ice Age event
| Asset ID | Purpose | Script | Status |
|---|---|---|---|
| `9114402399` | Low wind / howl loop | `IceAgeUI.client.lua` | ❌ **BROKEN** |
| `9112854440` | Distant cracking / creak loop | `IceAgeUI.client.lua` | ✅ Works |

### Mutation event
| Asset ID | Purpose | Script | Status |
|---|---|---|---|
| `97213152915968` | Mutation ambient loop | `MutationManager.server.lua` (preloaded in `EventSoundPreload`) | ✅ Works |
| `9112854440`     | Mutation alarm / roar | `MutationUI.client.lua`, `NPCMutationSystem.lua` | ✅ Works |
| `9114402399`     | Mutation bubble sound | `MutationUI.client.lua` | ❌ **BROKEN** |

### UFO event
| Asset ID | Purpose | Script | Status |
|---|---|---|---|
| `82428123919520` | UFO alien sound | `UFOManager.server.lua` (preloaded in `EventSoundPreload`) | ✅ Works |
| `9112854440`     | Eerie alien drone / hum loop | `UFOUI.client.lua`, `UFOEffects.lua` | ✅ Works |
| `9114402399`     | Electrical buzz | `UFOUI.client.lua`, `UFOEffects.lua` | ❌ **BROKEN** |

### Meteor event
| Asset ID | Purpose | Script | Status |
|---|---|---|---|
| `114095353806681` | Meteor impact (mobile-reliable path) | `MeteorImpactSound.client.lua` (preloaded in `EventSoundPreload`) | ✅ Works |
| `109362273688140` | Meteor intro | `MeteorManager.server.lua` (preloaded in `EventSoundPreload`) | ✅ Works |
| `5801257793`      | Shared low boom (meteor/ice/rocket, pitch-tuned) | `IceMeteor.lua`, `MeteorImpact.lua`, `RocketEffects.lua` | ✅ Works |

### Rocket event
| Asset ID | Purpose | Script | Status |
|---|---|---|---|
| `133543192033291` | Rocket construction | `RocketSounds.client.lua`, `RocketEffects.lua` (preloaded in `EventSoundPreload`) | ✅ Works |
| `1841791990`      | Rocket countdown | `RocketEffects.lua` (preloaded in `EventSoundPreload`) | ✅ Works |
| `135490777114772` | Rocket launch | `RocketSounds.client.lua`, `RocketEffects.lua` (preloaded in `EventSoundPreload`) | ✅ Works |
| `9120386436`      | Rocket effect sound | `RocketEffects.lua` | ✅ Works |
| `9112854440`      | Rocket effect sound | `RocketEffects.lua` | ✅ Works |
| `9116458024`      | Rocket effect sound | `RocketEffects.lua` | ❌ **BROKEN** |
| `9116544355`      | Rocket effect sound | `RocketEffects.lua` | ❌ **BROKEN** |

---

## 🔧 Misc / Ambient

| Asset ID | Purpose | Script | Status |
|---|---|---|---|
| `9114402399` | World ambient wind (collectible/pad effect), vol 0.5 | `WorldClient.client.lua` | ❌ **BROKEN** |

---

## Quick "broken" summary

| Broken ID | Used for | Scripts affected |
|---|---|---|
| `101642229651469` | Windstorm ambient loop | EventClient |
| `1369158752` | Thunder clap | EventClient |
| `3240498563` | Bird screech | EventClient |
| `9116544355` | Rocket effect | RocketEffects |
| `9116458024` | Beam "WHAM" hit, pet pop, rocket effect | CoreClient, PetFollow, RocketEffects |
| `9114402399` | Wind/howl, bubble, buzz, world wind | IceAgeUI, MutationUI, UFOUI, UFOEffects, WorldClient |

> Note: `9120386436`, `9112854440`, and `5801257793` are old-library-style IDs in the same era as the
> broken ones but were **not** on your broken list — verify them in-game before relying on them.
