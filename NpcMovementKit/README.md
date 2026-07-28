# NPC Movement Kit — drop into any realm

Everything that makes CandyRealm's NPCs and world feel alive, pulled out of the realm it grew in
and given a CONFIG block at the top of each file. Copy the five files into
`<Realm>/src/client/`, change the handful of names listed below, sync with Rojo.

| File | What it does |
|---|---|
| `NpcLife.client.lua` | Static quest givers turn to face you, breathe, greet once, and hop about when nobody's near |
| `NpcFacing.client.lua` | The same "turn to face you" for rigs that already play a looping idle animation |
| `GuideTrail.client.luau` | The chevron trail renderer. Two priority slots, no opinion about where you should go |
| `NpcGuideArrow.client.lua` | Land on an island → chevrons to that island's NPC → latches off once you've met them |
| `AmbientWildlife.client.luau` | Butterflies + bees over a landmark, birds circling an island. Client-only, zero replication |

## What to change per realm

Only these lines. Everything else is realm-agnostic.

```lua
-- NpcLife.client.lua
local NPC_HINT   = "npc"      -- substring your quest-giver models share

-- NpcFacing.client.lua
local TARGETS = {
    names      = { Gardener = true },   -- animated rigs by model name
    attributes = { "GardenerNPC" },     -- ...or by attribute
}

-- NpcGuideArrow.client.lua
local ISLAND_PREFIX = "island"   -- normalised prefix of your top-level island models
local NPC_HINT      = "npc"

-- AmbientWildlife.client.luau
local GROUND_ANCHOR = { "communitygardenbuild", "garden" }
local SKY_ANCHOR    = { "island1" }
```

## The two rules that make it work

**1. NpcLife and NpcFacing must never grab the same rig.**

They solve the same problem two incompatible ways. `NpcLife` anchors the root and drives the whole
pose with `PivotTo` every frame — that's the only way to move an unanchored Humanoid rig, because
otherwise the Humanoid and the physics solver both write to the root *after* you do and your pose
is gone before it's drawn. `NpcFacing` touches yaw on the root only and leaves the Animator to
drive the limbs.

Point `NpcLife` at an animated rig and the two fight: judder, or a frozen animation. Set the
`NoNpcLife` attribute on any rig you're handing to `NpcFacing`, or keep its name outside
`NPC_HINT`.

**2. Normalise names. Never pattern-match raw ones.**

Every lookup here goes through `norm()` — lowercase, strip spaces/underscores/hyphens — so
`island1`, `Island_1`, `Island 1` and `Island_1_BeanFarm` all match the prefix `island`.

This is not fussiness. `Name:match("^Island_1_")` in CandyRealm's original `AmbientWildlife` never
matched, because the islands are actually named `island1`. The birds' anchor stayed `nil`, they
were never given a CFrame, and four bird models sat visible at world origin for the whole session.
Nothing errored, nothing logged. Three separate scripts in that codebase have the same mismatch.
The version here fixes it and adds a `warn()` naming the anchor that failed.

## Scope NPC searches to the island, never the whole Workspace

`NpcGuideArrow` searches for the quest giver *inside* the island model you're standing on. Two
neighbouring islands can be a few hundred studs apart, and a nearest-in-range Workspace sweep will
happily wire one island's NPC to the other — a bug two CandyRealm quests already hit and had to
work around individually.

The island you're on is decided by **bounding box**, not pivot distance. A model's pivot sits
wherever it happens to sit; judging by pivot distance is how CandyRealm's arrows ended up pointing
at island 14 while you stood on island 8, which then blew the trail's own range cap so nothing
drew at all.

## Diagnostics

Both NPC scripts ship a chat command, because a script that loaded fine and moves nothing is
impossible to diagnose from the outside:

- `/npc` — every NPC adopted, its root, its distance, its current yaw
- `/arrows` — the island you're on, the NPC found, distance vs range, and whether the trail API exists

`NpcGuideArrow` also warns 5 seconds after load if `_G.guideTrailNpc` is missing, which is the
failure you'd otherwise stare at for an hour.

## Trail API

`GuideTrail` draws; it decides nothing. Anyone can point it:

```lua
_G.guideTrailTo(pos)    -- HIGH priority: hatchable egg, urgent objective
_G.guideTrailClear()    -- drop the high-priority target
_G.guideTrailNpc(pos)   -- LOW priority: the island quest giver (NpcGuideArrow owns this)
```

Call it every frame while you want it; stop calling and it puts itself away. Two slots rather than
one is deliberate — with a single slot whichever script wrote most recently wins, so the trail
flickers between an egg and an NPC instead of choosing. An egg beats an NPC every time, and that
comparison is made in one place.

Two things this renderer deliberately does **not** do, both of which the CandyRealm original
learned the hard way:

- It never destroys its pool. The original did, at the end of the tutorial — correct for a one-shot
  tutorial, fatal for anything later, since by the time you reach island 8's egg the trail no longer
  exists.
- Flying only **hides** it. The original killed itself permanently on the first flight; every egg
  after the first is reached by flying. And it checks you're actually airborne rather than trusting
  `_G.isFlying` alone — if that flag lingers true after a landing, a flag-only check means the trail
  never returns and nothing anywhere says why.
