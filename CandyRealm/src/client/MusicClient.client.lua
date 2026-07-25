--======================================================================
-- MusicClient.client.lua  (LocalScript)
--======================================================================
-- CLIENT-SIDE background music: shuffle (no repeat in a row) + 2.5s crossfade through all 4 tracks,
-- forever. Each player runs this locally and hears their OWN shuffle (players are NOT synced to the same
-- song at the same instant — fine, and far more reliable, for background music).
--
-- WHY CLIENT-SIDE: the server can't tell when a song ends (Sound.TimeLength reads 0, Sound.Ended never
-- fires, os.clock() timing is unreliable), so the old server loop got stuck. Clients DECODE audio.
--
-- KEY ROBUSTNESS (this version): we WAIT FOR EACH SOUND TO LOAD (Sound.IsLoaded / Sound.Loaded) before
-- reading TimeLength — reading TimeLength before load returns 0 and breaks the "wait until near the end"
-- math. The advance is driven primarily off Sound.Ended (reliable on the client), with a TimePosition
-- >= (TimeLength - crossfade) trigger to start the crossfade slightly early so tracks overlap. Loud
-- [MUSIC CLIENT] diagnostics at every step (TEMP — see F9).
--
-- VOLUME MODEL (preserves ducking + settings toggle, NO changes to those scripts): plays through the
-- server-created "BackgroundMusic" SoundGroup that MusicDucking.client.lua owns. MusicDucking tweens that
-- GROUP's Volume for event ducking AND the settings-menu mute (via _G.musicEnabled). This script only sets
-- the voices' OWN Volume (crossfade gain 0..1); audible = voiceGain x groupVolume, so crossfade + duck/mute
-- compose cleanly. We never touch the group Volume. Routing into that group also keeps the voices OFF the
-- SettingsMenu SFX toggle group.
--======================================================================

local SoundService    = game:GetService("SoundService")
local TweenService    = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

-- ===== CONFIG (NEW track IDs) =====
local MUSIC_TRACKS = {
	"rbxassetid://140517328454242",
	"rbxassetid://139448720739903",
	"rbxassetid://139206228229841",
	"rbxassetid://138099443718294",
}
local BACKGROUND_MUSIC_ENABLED = true
local CROSSFADE_TIME = 2.5   -- seconds to blend one song into the next
local VOICE_GAIN     = 1     -- a voice at full crossfade gain (the group Volume applies duck/mute on top)

if not BACKGROUND_MUSIC_ENABLED then
	print("[MUSIC CLIENT] background music disabled (BACKGROUND_MUSIC_ENABLED = false)")
	return
end

print("[MUSIC CLIENT] started, " .. #MUSIC_TRACKS .. " tracks")

-- The DUCK/MUTE group is created by the server (MusicManager) and owned by MusicDucking.client.lua. Route
-- our voices through it so ducking + the settings toggle apply automatically. If it never appears (music
-- disabled server-side), bail rather than play ungrouped audio.
local musicGroup = SoundService:WaitForChild("BackgroundMusic", 30)
if not musicGroup then
	warn("[MUSIC CLIENT] BackgroundMusic SoundGroup NOT FOUND — music disabled server-side? No client music.")
	return
end
print("[MUSIC CLIENT] found BackgroundMusic SoundGroup (Volume=" .. tostring(musicGroup.Volume) .. ")")

-- Prime the track cache so the incoming song is decoded before we crossfade into it.
task.spawn(function()
	local primers = {}
	for _, id in ipairs(MUSIC_TRACKS) do
		local s = Instance.new("Sound"); s.SoundId = id; primers[#primers + 1] = s
	end
	pcall(function() ContentProvider:PreloadAsync(primers) end)
	for _, s in ipairs(primers) do s:Destroy() end
	print("[MUSIC CLIENT] preload pass complete")
end)

-- Two voices to CROSSFADE between. Looped=false so each track ENDS (firing Sound.Ended on the client) and
-- the SYSTEM advances. SoundGroup = the BackgroundMusic group (duck/mute applies; also keeps them off the
-- SFX toggle group). Set the group BEFORE parenting so SettingsMenu's router never grabs them.
local function makeVoice(n)
	local s = Instance.new("Sound")
	s.Name = "ClientMusicVoice" .. n
	s.Looped = false
	s.Volume = 0
	s.SoundGroup = musicGroup
	s.Parent = SoundService
	print(string.format("[MUSIC CLIENT] voice %d created: Looped=%s (MUST be false)", n, tostring(s.Looped)))
	return s
end
local voices = { makeVoice(1), makeVoice(2) }

-- pickNext(): shuffle, never repeat the just-played track in a row. Returns the index.
local last = nil
local function pickNextIdx()
	local idx
	if #MUSIC_TRACKS <= 1 then
		idx = 1
	else
		repeat idx = math.random(1, #MUSIC_TRACKS) until idx ~= last
	end
	last = idx
	return idx
end

-- Load a track onto a voice (WAIT for IsLoaded so TimeLength is valid), then Play + fade its gain in.
-- Returns the chosen track index.
local function startTrackOn(voice, vnum)
	local idx = pickNextIdx()
	local id = MUSIC_TRACKS[idx]
	voice.TimePosition = 0
	voice.SoundId = id
	print(string.format("[MUSIC CLIENT] voice %d: PICKED track #%d id=%s | Looped=%s IsLoaded=%s -> waiting for LOAD",
		vnum, idx, id, tostring(voice.Looped), tostring(voice.IsLoaded)))
	-- WAIT FOR LOAD: TimeLength is only valid once the asset is loaded. Listen to Loaded + poll IsLoaded,
	-- bounded so a bad/slow asset can't hang us.
	local loadedConn = voice.Loaded:Once(function()
		print(string.format("[MUSIC CLIENT] voice %d: track #%d Sound.Loaded FIRED (TimeLength=%.2f)", vnum, idx, voice.TimeLength))
	end)
	local t0 = os.clock()
	while not voice.IsLoaded and (os.clock() - t0) < 15 do task.wait(0.1) end
	loadedConn:Disconnect()
	print(string.format("[MUSIC CLIENT] voice %d: track #%d LOAD DONE — IsLoaded=%s after %.1fs, TimeLength=%.2f, Looped=%s",
		vnum, idx, tostring(voice.IsLoaded), os.clock() - t0, voice.TimeLength, tostring(voice.Looped)))
	voice.Volume = 0
	voice:Play()
	print(string.format("[MUSIC CLIENT] voice %d: PLAYING track #%d (IsPlaying=%s)", vnum, idx, tostring(voice.IsPlaying)))
	TweenService:Create(voice, TweenInfo.new(CROSSFADE_TIME, Enum.EasingStyle.Linear), { Volume = VOICE_GAIN }):Play()
	return idx
end

-- Wait until the (loaded, playing) track is near its end, then return. Driven by Sound.Ended (definitive,
-- works on the client) + a TimePosition >= fadeStart trigger to start the crossfade slightly early.
local function waitForNearEnd(voice, vnum)
	local ended = false
	local conn = voice.Ended:Once(function()
		ended = true
		print(string.format("[MUSIC CLIENT] voice %d: Sound.Ended FIRED (track finished)", vnum))
	end)
	local len = voice.TimeLength
	if len > 0 then
		local fadeStart = math.max(0, len - CROSSFADE_TIME)
		print(string.format("[MUSIC CLIENT] voice %d: holding until TimePosition >= %.1fs (len=%.1f) or Ended", vnum, fadeStart, len))
		while not ended and voice.TimePosition < fadeStart do task.wait(0.1) end
	else
		-- Should not happen now (we waited for load), but never trust a 0 length: wait on Ended only, bounded.
		print(string.format("[MUSIC CLIENT] voice %d: WARNING TimeLength=0 after load -> waiting on Ended only", vnum))
		local t0 = os.clock()
		while not ended and (os.clock() - t0) < 600 do task.wait(0.25) end
	end
	conn:Disconnect()
	print(string.format("[MUSIC CLIENT] voice %d: near-end reached (ended=%s, TimePosition=%.1f) -> CROSSFADE", vnum, tostring(ended), voice.TimePosition))
end

task.spawn(function()
	local cur = 1
	startTrackOn(voices[cur], cur)   -- first track

	while true do
		local ok, err = pcall(function()
			local curVoice = voices[cur]
			waitForNearEnd(curVoice, cur)

			-- CROSSFADE: start the next track on the OTHER voice (it fades IN inside startTrackOn), then fade
			-- the current one OUT over the same window.
			local nxt = 3 - cur
			local nidx = startTrackOn(voices[nxt], nxt)
			print(string.format("[MUSIC CLIENT] CROSSFADING voice %d -> voice %d (now playing track #%d)", cur, nxt, nidx))
			TweenService:Create(curVoice, TweenInfo.new(CROSSFADE_TIME, Enum.EasingStyle.Linear), { Volume = 0 }):Play()
			task.wait(CROSSFADE_TIME)

			-- Old song faded out -> stop + reset its gain so it's ready to be the next incoming voice.
			curVoice:Stop()
			curVoice.Volume = 0
			cur = nxt
		end)
		if not ok then
			-- A single bad cycle must never end the loop (that's what would strand one track). Log + continue.
			warn("[MUSIC CLIENT] LOOP ERROR (continuing to next track): " .. tostring(err))
			task.wait(1)
		end
	end
end)
