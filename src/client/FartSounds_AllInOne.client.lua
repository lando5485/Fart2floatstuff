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

local function playFartSound()
	fartSound:Stop() -- cut any in-progress fart so rapid re-toggles don't stack
	local chosenId = FART_SOUND_IDS[math.random(1, #FART_SOUND_IDS)]
	fartSound.SoundId = chosenId
	print("FART SOUND playing id=" .. chosenId)
	fartSound:Play()
end
_G.playFartSound = playFartSound -- call this on fart-launch from your flight code

-- ===== TEST: a button + Space key to hear them =====
local gui = Instance.new("ScreenGui"); gui.Name = "FartSoundTest"; gui.ResetOnSpawn = false; gui.Parent = PlayerGui
local btn = Instance.new("TextButton"); btn.AnchorPoint = Vector2.new(0.5,1); btn.Position = UDim2.new(0.5,0,1,-90); btn.Size = UDim2.new(0,200,0,44)
btn.BackgroundColor3 = Color3.fromRGB(120,80,200); btn.Text = "\xe2\x98\x81 TEST FART SOUND"; btn.Font = Enum.Font.GothamBold; btn.TextSize = 16; btn.TextColor3 = Color3.new(1,1,1); btn.Parent = gui
Instance.new("UICorner", btn).CornerRadius = UDim.new(0,10)
btn.Activated:Connect(playFartSound)
UserInputService.InputBegan:Connect(function(io, gp) if gp then return end if io.KeyCode == Enum.KeyCode.Space then playFartSound() end end)

print("[FartSounds] loaded 7 fart sounds -> _G.playFartSound() (TEST button + Space)")
