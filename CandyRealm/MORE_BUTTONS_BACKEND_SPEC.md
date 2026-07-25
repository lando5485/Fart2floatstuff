# CandyRealm — MORE+ / rail backend requirements

Handoff spec for building the missing **server + ReplicatedStorage backends** that the
existing CandyRealm **client** scripts already expect. The clients are done and correct;
they just hang or early-return because these instances don't exist in this place.

## Why everything but "Pets" is dead

CandyRealm is a **separate place** (own DataModel). Its `default.project.json` declares
`ReplicatedStorage.Shared` as an **empty Folder**, and it ships **no server services** for
these features (only `RealmServer` (stub), `AnchorIslands`, `StomachUpgrade`). So every
client that `WaitForChild`s / `require`s a shared module or remote either:
- **infinite-hangs** (no timeout) — e.g. `CrateClient` on `Shared.Constants`, or
- **early-returns** (`if not remote then return`) — e.g. Rebirth/SeasonPass/DailyTasks.

`Pets` works only because `PetHub` creates its `PetInvToggle` BindableEvent with no
external dependency.

Build each backend to the contracts below. **Match the instance names exactly** —
the client `WaitForChild`s them by name.

---

## 0. SHARED (blocks Daily Crate; likely reused by other state-driven features)

⚠ **Rojo first:** `ReplicatedStorage.Shared` is declared as an empty Folder with **no `$path`**
in `default.project.json`, so a `src/shared` folder does NOT sync today. Map it first — change the
`Shared` node to `"Shared": { "$className": "Folder", "$path": "src/shared" }`, then create
`src/shared/Constants.luau`, `src/shared/Remotes.luau`, etc.

Put these ModuleScripts under `ReplicatedStorage.Shared`:

- **`Constants`** (ModuleScript) — must expose `Constants.CRATE` with at least:
  - `CRATE.COOLDOWN_SECONDS` (number) — daily-crate cooldown
  - `CRATE.RARITY_COLORS` (table: rarityName → Color3)
  - `CRATE.PET_MAX_LEVEL` (number, e.g. 25)
  - *Consumed at* `CrateClient.client.luau:27,79,270,1064,677`
- **`Remotes`** (ModuleScript) — a state-snapshot helper. Must expose:
  - `Remotes.getStateChanged()` → a **RemoteEvent** the client connects `.OnClientEvent(snapshot)`
  - `Remotes.getRequestState()` → a **RemoteEvent** the client `:FireServer()` to request a snapshot
  - *Consumed at* `CrateClient.client.luau:25,88,94` (and other state-driven scripts follow this pattern)

---

## 1. Daily Crate — `CrateClient.client.luau`

**Create:**
- `ReplicatedStorage.Shared.Constants` + `.Remotes` (section 0). *Without these the script
  infinite-hangs at line 24 and never even creates its `OpenMeteorCrate` listener.*
- `ReplicatedStorage.CrateRemotes` (Folder) containing:
  - `ClaimCrate` (**RemoteFunction**) — `:InvokeServer(petId)` → result table
    (fields used: `result.nextClaimAt`, plus reveal fields). *CrateClient:56,671,677*
  - `CrateResult` (**RemoteEvent**) — server→client `:FireClient(result)`; client reveals it.
    *CrateClient:57,1497*
  - `GetOwnedPets` (**RemoteFunction**) — `:InvokeServer()` → list of owned pets. *CrateClient:58,64*
  - `PreviewRoll` (**RemoteFunction**) — `:InvokeServer()` → `{rarity, levelAmount}` decided by
    the SERVER (client never decides). *CrateClient:59,1485*
- `ReplicatedStorage.OpenMeteorCrate` (BindableEvent) — the MORE row fires this to open the
  crate. CrateClient *creates+connects it itself* once it gets past the Shared requires.

**Server must:** own crate cooldown, roll rarity/level (PreviewRoll), grant on `ClaimCrate(petId)`
(apply +N levels to that owned pet), push `CrateResult`, and drive the state snapshot via
`Remotes.getStateChanged`. Client exposes `_G.crateIsClaimable()` once loaded.

---

## 2. Daily Tasks — `DailyTasks.client.luau`

**Create:** `ReplicatedStorage.DailyTasksEvent` (**RemoteEvent**). *Client early-returns without it (line 20-21).*

**Contract:**
- Client → server: `remote:FireServer()` (request current state, line 463), `remote:FireServer("invite")` (line 302).
- Server → client: `remote:FireClient(payload)` → `render(payload)` (line 462). Payload = the task
  list + per-task progress/claim state (read the `render` fn for exact fields).

**Server must:** track daily tasks + progress per player, send state, handle the invite verb (and
any claim verb `render` expects). Client exposes `_G.toggleDailyTasks`, `_G.dailyTasksPending`.

---

## 3. Rebirth — `RebirthClient.client.luau`

**Create:** `ReplicatedStorage.RebirthEvent` (**RemoteEvent**). *Client early-returns without it (line 15-16).* Header names the intended authority: `RebirthSystem.server.lua`.

**Contract:**
- Client → server: `remote:FireServer("state")` (on open, line 288), `remote:FireServer("rebirth")` (confirm, line 304).
- Server → client: `remote:FireClient(kind, a, b)` → handler at line 522. State the client draws
  (from its default table, line 22): `reqs = { islands, space, dino, candy }`, `reqIsland = 14`,
  `canRebirth`, rebirth count, multipliers, `petMilestones`.

**Server must:** validate rebirth requirements, apply the rebirth (reset progress, bump `Rebirths`
leaderstat + multipliers), and push state. Client exposes `_G.toggleRebirth`.

---

## 4. Season Pass — `SeasonPass.client.luau`

**Create:** `ReplicatedStorage.SeasonPassEvent` (**RemoteEvent**). *Client early-returns without it (line 15-16).*

**Contract:**
- Client → server: `remote:FireServer("buy")` (premium, line 142), `remote:FireServer("claim", tierIndex, lane)` (line 213).
- Server → client: `remote:FireClient(kind, a, b, c, d)` → handler at line 339 (pass tiers/XP/lane state).

**Server must:** own the pass (tiers, XP/progress, free + premium lanes), handle buy + claim(tier, lane).
Client exposes `_G.toggleSeasonPass`.
⚠ **Note:** SeasonPass.client.luau:317-324 warns a **stale duplicate LocalScript** can steal
`_G.toggleSeasonPass`. If MORE opens a dead SeasonPass panel even after the backend exists, delete
the stale baked-in script in the place.

---

## 5. Codes — `RewardsClient.client.lua`

**Create (all timeout-guarded, so `_G.openCodesGui` is defined ~late but the GUI opens):**
- `ReplicatedStorage.RedeemCode` (**RemoteFunction**) — `:InvokeServer(code)` → result. *Line 20,85*
- `ReplicatedStorage.CoinBoostState` (**RemoteEvent**) — line 21 (wired for future boost display).
- `ReplicatedStorage.GroupInfo` (**RemoteEvent**) — `:FireClient(info)` group-membership → line 22,155.
- Also uses `CrateRemotes.GetOwnedPets` (shared with section 1).

**Server must:** validate + grant on `RedeemCode(code)`, publish `GroupInfo` (membership check).
Client exposes `_G.openCodesGui`, `_G.openGroupGui`.

---

## Not MORE rows, but same missing-backend class (fix if you want those features)

- **Stomach "Skins" tab** — `GutSkinClient` needs `Shared.GutSkins` (ModuleScript) + remotes
  `EquipGutSkin`/`GetGutSkins` (RemoteFunctions), `GutSkinState`/`GutSkinUnlocked` (RemoteEvents).
  The Stomach *menu* already opens; the Skins tab only appears once these exist.
- **Realm events** — `MeteorUI` waits on `ReplicatedStorage.MeteorSync`; `RocketUI` waits on
  `RocketEventSync`. Absent → those event UIs hang (harmless but they never fire).
- **Coins** — no coin income in this place; `StomachUpgrade` scaffolds `leaderstats.Coins=0`.
  Real coins expected via TeleportData from the food realm (`RealmServer`'s receiver is a stub),
  or a flight/coin backend. The Stomach shop is fully wired; it just needs Coins to arrive.

## Rojo note
`src/server` is folder-mapped to `ServerScriptService`, so new server services drop in and sync.
BUT `ReplicatedStorage.Shared` has NO `$path` (empty Folder) — you must add
`"$path": "src/shared"` to the `Shared` node before any `src/shared` module will sync (see section 0).
