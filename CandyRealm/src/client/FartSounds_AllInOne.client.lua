--======================================================================
-- FartSounds_AllInOne.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of EVERY fart sound the game plays + the exact play
-- logic, lifted VERBATIM from CoreClient. The game plays ONE random fart sound
-- each time you start a fart/ascent (toggle-on): it stops any in-progress fart
-- and plays a fresh random pick, so rapid toggles never overlap. Parented to
-- SoundService => 2D, audible to the local player.
--
-- Exposes `_G.playFartSound()` so your flight/propel code can call it on launch
-- (in the real game startFlying() calls playFartSound()). Also includes a small
-- on-screen TEST button + the Space key so you can hear them. Drop into
-- StarterPlayer > StarterPlayerScripts.
--======================================================================

local Players          = game:GetService("Players")
local SoundService     = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== FART SOUNDS (verbatim) =====
local FART_VOLUME = 0.6                 -- the single adjustable fart volume
local FART_SOUND_IDS = {               -- all 7 fart sounds (one random pick per ascent)
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
fartSound.Parent = SoundService -- SoundService => reliable 2D global playback (local player)

-- FART SOUNDS DISABLED FOR NOW. Kept as a no-op (and the _G binding intact) so every caller
-- across the game goes silent without erroring. To re-enable, restore the body below and the
-- Space-key handler.
local FART_SOUNDS_ENABLED = false

local function playFartSound()
	if not FART_SOUNDS_ENABLED then return end -- farts turned off for now
	fartSound:Stop() -- cut any in-progress fart so rapid re-toggles don't stack
	local chosenId = FART_SOUND_IDS[math.random(1, #FART_SOUND_IDS)]
	fartSound.SoundId = chosenId
	print("FART SOUND playing id=" .. chosenId)
	fartSound:Play()
end
_G.playFartSound = playFartSound -- call this on fart-launch from your flight code

-- ===== Space key to hear them (disabled while farts are off) =====
if FART_SOUNDS_ENABLED then
	UserInputService.InputBegan:Connect(function(io, gp) if gp then return end if io.KeyCode == Enum.KeyCode.Space then playFartSound() end end)
end

print("[FartSounds] fart sounds DISABLED for now (_G.playFartSound is a no-op)")
