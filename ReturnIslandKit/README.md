# Return-to-Island Kit

The fall-catch safety button from Fart to Float, cut free of that game so any realm can drop it in.

> ⬆ Return to Island 7

Appears whenever the player is below the highest anchor they've reached. Tapping puts them back.
No auto-teleport — falling is part of the game, and this is the player choosing to give up on the fall.

## Install

| file | goes in |
|---|---|
| `ReturnIsland.server.luau` | `ServerScriptService` |
| `ReturnIsland.client.luau` | `StarterPlayerScripts` |

Then tag your anchors: pick one part per island/platform, and in Studio's Properties → Attributes add a
**number** attribute named `ReturnAnchor` set to that island's index (`1`, `2`, `3`…). That's the whole setup.

Prefer the attribute to a naming convention — a name match breaks the first time someone renames a model,
whereas an attribute is attached to the thing itself and survives renaming, moving and reparenting. If you'd
rather not tag anything, set `CONFIG.FALLBACK_FOLDER` and it'll look for `Island1`, `Island2`… inside it.

## Config worth knowing

| key | default | note |
|---|---|---|
| `CATCH_MARGIN` | `60` | studs below the anchor before the button appears. Too small and it flickers on every hop; too large and a falling player waits to be offered help |
| `PROGRESS_STAT` | `"Island"` | a leaderstats IntValue naming the furthest anchor reached. Set it if your realm has one — it's persistent, so it survives a rejoin. `nil` falls back to session-only tracking |
| `DROP_HEIGHT` | `6` | studs above the anchor's top face, so they land *on* it, not inside it |
| `X_INSET` (client) | `130` | px from the left edge — the one number to change if your rails differ |

## Placement

`Position (0, 130, 0.5, 0)`, `AnchorPoint (0, 0.5)` — left edge, vertically centred. That spot isn't
arbitrary; it's the only large area this game leaves empty:

- the **left rail** (shop / stomach / wormhole / more) runs down the left at `x < 130`, so 130 clears it
- the **right panel** (stats + impulse buttons) owns the right edge
- the **bottom centre** is the gas meter and the fart button
- the **top centre** is the announcement banner lane plus the quest and objective cards

A mid-height button never covers the middle of the screen because it sits well out to the side. Keep the
anchor at `(0, 0.5)` and change only `X_INSET`.

Authored at 180×56; a responsive pass scales it from there (on a phone at 0.42 it measures ~75×23).

## Three things that will bite you if you rewrite it

**The client sends nothing but "I tapped it."** No index, no position, no target. The server recomputes
where the player actually got to and moves them itself. A client that can name its own destination is a
client that can teleport to the top of the map — passing the island number would be the whole exploit.

**Anchors are re-scanned, not cached once.** With StreamingEnabled, or in a realm that builds its world from
a script, the parts don't all exist on frame one. A stale cache means the button silently does nothing for
whatever loaded late, which looks exactly like a broken button.

**The tap deliberately doesn't re-check the below-margin condition.** The button is only ever shown while
the player is below home, and re-testing on the server meant someone who tapped just as they crossed back
over the line got a silent no-op. A button that sometimes does nothing is worse than one that occasionally
repositions you three studs — and it can't skip progress either way, since the only destination it can
produce is somewhere the player already reached.

## Source

`src/client/CoreClient.client.lua:1947` (the button) and `src/server/PlayerStats.server.lua:1704` +
`:1814` (the remote handler and the per-frame prompt driver). The original reads islands out of that game's
`standData` table and its `maxIslandVisited`; both are `CONFIG` here.
