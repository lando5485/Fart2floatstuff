--======================================================================
-- MusicDucking.client.lua  (LocalScript)
--======================================================================
-- Ducks the server-wide background music (MusicManager.server.lua) whenever a dramatic event is active,
-- then smoothly raises it back when the last event ends. The music Sound itself is server-owned (in
-- SoundService) so all players hear the same track; the server sets its Volume only once and never
-- again, so this script freely tweens the LOCAL Volume for ducking without the server overriding it.
--
-- Detection touches NO event systems:
--   * BIG events (Rocket / Meteor / UFO / Ice Age / Mutation): read the replicated "BigEventActive"
--     BoolValue the server mirrors from _G.BigEvents.
--   * MEDIUM dramatic events (Wind Storm / Thunderstorm / Fart Storm): listen to the existing
--     ServerEventNotify remote (the same one EventClient already uses) — start = the event name,
--     end = "END".
-- We stay ducked while EITHER source is active, so overlapping events stay ducked until the LAST ends.
--======================================================================

local SoundService     = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")

local FADE_TIME = 0.6  -- seconds for the quick duck/un-duck fade (~0.5-1s)

-- Medium events that should duck the music (the loud/dramatic ones). Other medium events (coin rush,
-- gravity, power surge, ring fever) have no dramatic audio, so they don't duck.
local DUCK_MEDIUM_EVENTS = {
	WINDSTORM    = true,
	THUNDERSTORM = true,
	FART_STORM   = true,
}

-- The server-owned music Sound. If music is disabled server-side it never appears; just bail.
local music = SoundService:WaitForChild("BackgroundMusic", 30)
if not music then return end

local NORMAL_VOLUME = music:GetAttribute("NormalVolume") or music.Volume
local DUCKED_VOLUME = music:GetAttribute("DuckedVolume") or (NORMAL_VOLUME * 0.28)
local bigFlag       = music:WaitForChild("BigEventActive", 15)  -- replicated big-event-active flag

local mediumActive = false   -- a duckable medium event is currently active
local currentTween = nil

local function bigActive()
	return bigFlag ~= nil and bigFlag.Value == true
end

-- Smoothly fade the LOCAL music volume to ducked (event active) or normal (all clear). The client MUSIC
-- toggle (Settings menu) gates this: when _G.musicEnabled == false the volume is forced to 0 regardless
-- of duck state. Forcing it HERE — the one place that owns the BackgroundMusic SoundGroup volume — means
-- the mute can never fight the crossfade or the ducking. Default (nil / true) = play normally.
local function applyDuck()
	local target
	if _G.musicEnabled == false then
		target = 0
	else
		target = (bigActive() or mediumActive) and DUCKED_VOLUME or NORMAL_VOLUME
	end
	if currentTween then currentTween:Cancel() end
	currentTween = TweenService:Create(
		music,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Volume = target }
	)
	currentTween:Play()
end
-- Let the Settings menu re-apply the music volume right after it flips _G.musicEnabled (mute/unmute now).
_G.refreshMusicVolume = applyDuck

-- BIG events: re-evaluate whenever the replicated flag flips (covers late joiners too, since the
-- BoolValue carries its current value).
if bigFlag then
	bigFlag:GetPropertyChangedSignal("Value"):Connect(applyDuck)
end

-- MEDIUM events: the existing server->client notify. Only one medium event runs at a time, so a single
-- boolean tracks it; "END" clears whatever was active.
local ServerEventNotify = ReplicatedStorage:WaitForChild("ServerEventNotify", 30)
if ServerEventNotify then
	ServerEventNotify.OnClientEvent:Connect(function(eventName)
		if eventName == "END" then
			if mediumActive then mediumActive = false; applyDuck() end
		elseif DUCK_MEDIUM_EVENTS[eventName] then
			mediumActive = true; applyDuck()
		end
		-- non-duckable medium events: leave the music level unchanged.
	end)
end

-- Set the initial level (duck immediately if a big event is already running on join).
applyDuck()
