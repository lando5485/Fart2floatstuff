# Fart Sounds Reference

Every sound the game plays when you fart, and how it plays them.
Source: `src/client/CoreClient.client.lua` (lines 117–141).
Self-contained copy: `src/client/FartSounds_AllInOne.client.lua`.

## The 7 fart sound IDs

One is picked at RANDOM each time you start a fart/ascent (toggle-on):

| # | Asset ID |
|---|----------|
| 1 | rbxassetid://137105349517966 |
| 2 | rbxassetid://136812322649032 |
| 3 | rbxassetid://119702591396866 |
| 4 | rbxassetid://123499328258921 |
| 5 | rbxassetid://92449881602559  |
| 6 | rbxassetid://109574021376037 |
| 7 | rbxassetid://129402830763074 |

## How it plays

- **Volume:** `FART_VOLUME = 0.6` (the single adjustable knob).
- **One reusable `Sound`** named `FartSound`, parented to **`SoundService`** →
  2D playback, audible to the local player.
- Played **only on fart-launch** (toggle-on / `startFlying`). Each launch:
  1. `fartSound:Stop()` — cut any in-progress fart so rapid re-toggles don't stack.
  2. pick a random ID from the list.
  3. set `fartSound.SoundId` and `fartSound:Play()`.

## Copy-paste (Lua)

```lua
local FART_VOLUME = 0.6
local FART_SOUND_IDS = {
	"rbxassetid://137105349517966",
	"rbxassetid://136812322649032",
	"rbxassetid://119702591396866",
	"rbxassetid://123499328258921",
	"rbxassetid://92449881602559",
	"rbxassetid://109574021376037",
	"rbxassetid://129402830763074",
}
local fartSound = Instance.new("Sound")
fartSound.Name = "FartSound"
fartSound.Volume = FART_VOLUME
fartSound.Parent = game:GetService("SoundService")

local function playFartSound()
	fartSound:Stop() -- cut any in-progress fart so rapid re-toggles don't stack
	fartSound.SoundId = FART_SOUND_IDS[math.random(1, #FART_SOUND_IDS)]
	fartSound:Play()
end
```

## Related one-off sounds (not fart, but nearby in the game)

| Sound | ID | When |
|---|---|---|
| UI click | rbxassetid://101638558691673 | button taps |
| Error | rbxassetid://87486053112716 | invalid action |
| Ring collect | rbxassetid://115390827163601 | flying through a ring |
| Gas-pocket pop | rbxassetid://117464325212045 | popping a gas bubble |
