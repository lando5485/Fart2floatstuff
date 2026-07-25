--======================================================================
-- MeteorImpactSound.client.lua  (LocalScript)
--======================================================================
-- MOBILE-RELIABLE playback for the meteor IMPACT sound ONLY (rbxassetid://114095353806681).
--
-- The server fires the "MeteorImpactSound" RemoteEvent to ALL clients on every meteor impact; each
-- client plays its OWN local copy of the sound from SoundService. This avoids server-side audio, which
-- doesn't always reach mobile reliably, and keeps the sound parented to a persistent, replicating
-- location (SoundService) instead of a part/folder that gets destroyed.
--
-- This script is fully self-contained: it touches no other sound, event, or system.
--======================================================================

local SoundService     = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider  = game:GetService("ContentProvider")

local IMPACT_SOUND_ID     = "rbxassetid://114095353806681"
local IMPACT_SOUND_VOLUME = 1   -- unchanged: matches the meteor intro sound's volume

-- ONE reusable local Sound, parented to SoundService (2D / persistent / reliably present on mobile).
local impactSound = Instance.new("Sound")
impactSound.Name = "MeteorImpactLocal"
impactSound.SoundId = IMPACT_SOUND_ID
impactSound.Volume = IMPACT_SOUND_VOLUME
impactSound.Looped = false
impactSound.Parent = SoundService

-- PRELOAD on join so it's ready to play INSTANTLY (mobile devices load assets slower than PC).
task.spawn(function()
	pcall(function() ContentProvider:PreloadAsync({ impactSound }) end)
end)

-- Play locally on each server impact, keeping the don't-restart-if-already-playing rule (checked
-- LOCALLY here): if it's already playing, this impact is skipped — no restart / machine-gunning.
local ev = ReplicatedStorage:WaitForChild("MeteorImpactSound", 30)
if ev then
	ev.OnClientEvent:Connect(function()
		if impactSound.IsPlaying then return end
		impactSound.TimePosition = 0
		impactSound:Play()
	end)
end
