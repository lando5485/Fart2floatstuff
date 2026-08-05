# Currency Capsule Kit

The top-right coins + tokens HUD from Fart to Float, cut free of that game so it can be dropped
into any realm.

```
[ gear ] <-8px-> (( 🎟 1,234 )( $ 5,678 ))
```

## What it is

Three nested capsules, not one box with two rectangles cut out of it: a dark navy outer capsule,
and inside it on a 6px inset, two fully rounded pills — navy tokens, gold coins. **The frame
showing through the 6px gap between them is the divider**, so it follows the same curve as
everything else and there is no square corner anywhere in the component.

Both pills are self-sizing: each is only as wide as its own icon + digits + `+`, then both are
squared off to the wider of the two. So there is never a slab of dead gold after the coin count,
and the two halves always look like a matched pair.

There is **no drop shadow behind it**. Roblox has no real blur, so a "soft" shadow is just a
bigger flat rectangle, and on a bright HUD it reads as a grey slab rather than as depth. All the
depth comes from inside: gradients, inner shadows, rim highlights, and a small contact shadow
under each icon.

## Install

1. Drop `CurrencyCapsule.client.luau` into `StarterPlayerScripts` (Rojo: anywhere your realm
   already syncs client scripts).
2. Open the `CONFIG` block at the top — that is the whole of what you need to change.
3. Play. It builds its own `ScreenGui` and owns everything in it.

## Wiring the numbers

Sources are tried in order, first one that answers wins:

| # | source | when to use it |
|---|--------|----------------|
| 1 | `_G.CurrencyCapsule.setCoins(n)` / `.setTokens(n)` | your balance lives in a script or arrives on a RemoteEvent |
| 2 | `leaderstats.<COIN_STAT>` / `<TOKEN_STAT>` | the normal case — **no code needed**, just set the names |
| 3 | `_G[COIN_GLOBAL]` / `_G[TOKEN_GLOBAL]` | a global another script already maintains |
| 4 | `MIRROR_COIN_LABEL` | last resort: copy digits out of an existing on-screen label |

```lua
-- from a RemoteEvent, say:
CoinUpdate.OnClientEvent:Connect(function(n) _G.CurrencyCapsule.setCoins(n) end)
```

## Config worth knowing

| key | default | note |
|-----|---------|------|
| `SHOW_TOKENS` | `true` | `false` = coins only; the capsule closes up around the single pill |
| `TOKEN_ICON` | `🎟` | emoji render in **their own colours** — `TextColor3` is ignored. Want a recoloured icon? Swap the `TextLabel` for an `ImageLabel` |
| `ON_COIN_PLUS` / `ON_TOKEN_PLUS` | opens `_G.openCoinShop` / `_G.openTokenShop` | set to `nil` and no `+` is drawn on that pill — better than a button that does nothing |
| `ON_TOKEN_TAP` | same as token `+` | tapping the whole navy pill |
| `GEAR_GUI` / `GEAR_BTN` | `SettingsGui` / `SettingsGearBtn` | adopts an existing gear into the row. Set either to `nil` if your realm has none |
| `RIGHT_MARGIN` / `TOP` | `10` / `10` | px from the screen corner |

Colours are the block under `-- LOOK`. Height is driven by `CAP_H` alone; everything else derives
from it, so changing that one number rescales the component.

## Two things that will bite you if you rewrite them

**Don't measure positions across ScreenGuis.** HUD guis do not share a coordinate space — in one
frame, different guis report an 800×600 space and the real viewport. Anything that measures pixels
in one gui and writes them into another computes correctly and lands wrong, and the diagnostics
(printed early in a join, before the viewport settles) agree with the maths instead of with the
screen. That is why the gear and the capsule are reparented into one row and a `UIListLayout` does
the spacing.

**A `UIListLayout` ignores a child's `Position` but not its `AnchorPoint`.** If another script
re-stamps an anchor of `(1, 0)` on the gear when a menu closes, it slides a full width sideways
inside the row. The loop re-asserts `AnchorPoint` every frame, not just on adoption.

## Source

Ported from `src/client/TokenHud.client.luau`. The original reads coins out of `CoreClient`'s
`CoinGui.Frame.Amount`, adopts CoreClient's own `+` button, and pulls tokens from
`_G.crateTokenBalance`; all three are `CONFIG` here.
