--======================================================================
-- MusicClient.client.lua  (LocalScript)
--======================================================================
-- CLIENT-SIDE background music: every track, in a shuffled order, with a 2.5s crossfade between them,
-- forever. Each player runs this locally and hears their OWN shuffle (players are NOT synced to the same
-- song at the same instant — fine, and far more reliable, for background music).
--
-- WHY CLIENT-SIDE: the server can't tell when a song ends (Sound.TimeLength reads 0, Sound.Ended never
-- fires, os.clock() timing is unreliable), so the old server loop got stuck. Clients DECODE audio.
--
-- ===== WHY "NOT ALL THE TRACKS EVER PLAY" HAPPENED, AND THE TWO FIXES =====
-- 1. THE ROTATION WAS A LOTTERY. It picked at random with a single "not the same as last time" rule.
--    Nothing made a given track come up at all, so a player could easily sit through a whole session
--    hearing two of the four. It is a SHUFFLED BAG now: every track is dealt once, in a random order,
--    before any of them repeats. All of them run, and they still don't arrive in the same order twice.
-- 2. A DEAD ID SAT IN THE ROTATION AND PLAYED SILENCE. The old preload pass threw its results away —
--    it printed "preload pass complete" and nothing else — so an id that does not resolve for this
--    experience (not an audio asset, or uploaded on another account and not approved here) looked exactly
--    like one that does. It stayed in the rotation, got picked, played nothing, and the playlist then sat
--    waiting for an Ended that a sound with no audio never fires. Ids are now VERIFIED at boot with the
--    per-asset callback, every one is named in the log with its status, and a dud is dropped from the
--    rotation instead of being handed a silent slot.
--
-- KEY ROBUSTNESS: we WAIT FOR EACH SOUND TO LOAD (Sound.IsLoaded / Sound.Loaded) before reading
-- TimeLength — reading TimeLength before load returns 0 and breaks the "wait until near the end" math.
-- The advance is driven primarily off Sound.Ended (reliable on the client), with a TimePosition
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

-- ===== CONFIG =====
local MUSIC_TRACKS = {
	"rbxassetid://140517328454242",
	"rbxassetid://139448720739903",
	"rbxassetid://139206228229841",
	"rbxassetid://138099443718294",
}
local BACKGROUND_MUSIC_ENABLED = true
local CROSSFADE_TIME = 2.5   -- seconds to blend one song into the next
local VOICE_GAIN     = 1     -- a voice at full crossfade gain (the group Volume applies duck/mute on top)
local LOAD_GRACE     = 15    -- seconds to wait for a track to decode before treating it as a dud
local VERIFY_GRACE   = 15    -- seconds to wait for the boot verification before starting anyway
local DEAD_AIR_MAX   = 10    -- seconds a zero-length track is allowed to hold the playlist (was 600 = 10 min of silence)

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

--======================================================================
-- WHICH IDS ACTUALLY WORK  (fix 2)
--======================================================================
-- Preload with the PER-ASSET CALLBACK, name every id and its status in the log, and keep only the ones that
-- came back usable. The rotation is built from `playable`, never from MUSIC_TRACKS directly, so a dud can
-- never be handed a slot. The warning prints the failing id — that is the line you need to replace.
local playable = {}
local verified = false

task.spawn(function()
	local primers, indexOf, status = {}, {}, {}
	for i, id in ipairs(MUSIC_TRACKS) do
		local s = Instance.new("Sound"); s.SoundId = id
		primers[i] = s
		indexOf[id] = i
		status[i] = "no callback"
	end
	pcall(function()
		ContentProvider:PreloadAsync(primers, function(contentId, fetchStatus)
			local i = indexOf[contentId]
			if i then status[i] = tostring(fetchStatus) end
		end)
	end)

	local good = tostring(Enum.AssetFetchStatus.Success)
	local bad = {}
	for i, s in ipairs(primers) do
		local id = MUSIC_TRACKS[i]
		-- PreloadAsync blocks until every asset has resolved, so IsLoaded is trustworthy by here. Either
		-- signal counts as usable: the callback is the explicit answer, IsLoaded the observable one.
		local ok = s.IsLoaded or status[i] == good
		print(("[MUSIC CLIENT] track %d  %s -> %s%s"):format(i, id, status[i], ok and "" or "   << WILL NOT PLAY"))
		if ok then playable[#playable + 1] = id else bad[#bad + 1] = id end
		s:Destroy()
	end

	if #bad > 0 then
		warn(("[MUSIC CLIENT] %d of %d music id(s) DID NOT LOAD and are dropped from the rotation: %s -- replace "
			.. "them in MUSIC_TRACKS. An id fails when it is not an audio asset, or was uploaded on another "
			.. "account and is not approved for this experience.")
			:format(#bad, #MUSIC_TRACKS, table.concat(bad, ", ")))
	end
	verified = true
	print(("[MUSIC CLIENT] verification done -- %d of %d track(s) playable"):format(#playable, #MUSIC_TRACKS))
end)

--======================================================================
-- THE ROTATION: A SHUFFLED BAG, NOT A COIN FLIP  (fix 1)
--======================================================================
local bag, lastId = {}, nil

local function refillBag()
	bag = table.clone(playable)
	for i = #bag, 2, -1 do -- Fisher-Yates
		local j = math.random(1, i)
		bag[i], bag[j] = bag[j], bag[i]
	end
	-- Don't let a fresh bag open with the track that just finished -- the one seam a bag cannot smooth itself.
	if #bag > 1 and bag[1] == lastId then bag[1], bag[#bag] = bag[#bag], bag[1] end
end

local function nextTrackId()
	if #bag == 0 then refillBag() end
	local id = table.remove(bag, 1)
	lastId = id
	return id
end

-- Pull an id out of the rotation for good (it verified at boot but will not load now).
local function dropFromRotation(id)
	for i = #playable, 1, -1 do if playable[i] == id then table.remove(playable, i) end end
	for i = #bag, 1, -1 do if bag[i] == id then table.remove(bag, i) end end
end

--======================================================================
-- VOICES
--======================================================================
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

-- Load the next track onto a voice (WAIT for IsLoaded so TimeLength is valid), then Play + fade its gain in.
-- Returns the id it started, or nil if nothing in the rotation would load.
local function startTrackOn(voice, vnum)
	for _ = 1, math.max(1, #playable) do
		local id = nextTrackId()
		if not id then break end
		voice.TimePosition = 0
		voice.SoundId = id
		print(string.format("[MUSIC CLIENT] voice %d: PICKED %s | Looped=%s IsLoaded=%s -> waiting for LOAD",
			vnum, id, tostring(voice.Looped), tostring(voice.IsLoaded)))

		-- WAIT FOR LOAD: TimeLength is only valid once the asset is loaded. Listen to Loaded + poll IsLoaded,
		-- bounded so a bad/slow asset can't hang us.
		local loadedConn = voice.Loaded:Once(function()
			print(string.format("[MUSIC CLIENT] voice %d: Sound.Loaded FIRED (TimeLength=%.2f)", vnum, voice.TimeLength))
		end)
		local t0 = os.clock()
		while not voice.IsLoaded and (os.clock() - t0) < LOAD_GRACE do task.wait(0.1) end
		loadedConn:Disconnect()

		if voice.IsLoaded then
			print(string.format("[MUSIC CLIENT] voice %d: LOAD DONE — after %.1fs, TimeLength=%.2f, Looped=%s",
				vnum, os.clock() - t0, voice.TimeLength, tostring(voice.Looped)))
			voice.Volume = 0
			voice:Play()
			print(string.format("[MUSIC CLIENT] voice %d: PLAYING %s (IsPlaying=%s)", vnum, id, tostring(voice.IsPlaying)))
			TweenService:Create(voice, TweenInfo.new(CROSSFADE_TIME, Enum.EasingStyle.Linear), { Volume = VOICE_GAIN }):Play()
			return id
		end

		-- Verified at boot but will not load now. Drop it and take the next one immediately, rather than
		-- playing a silent voice and waiting out its whole slot -- that is the silence this fix exists for.
		warn(string.format("[MUSIC CLIENT] voice %d: %s did not load in %ds -- dropping it and taking the next track",
			vnum, id, LOAD_GRACE))
		dropFromRotation(id)
	end
	warn("[MUSIC CLIENT] nothing in the rotation would load -- no track started")
	return nil
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
		-- ===== THIS WAIT USED TO BE UNBOUNDED, AND THAT COULD STRAND THE WHOLE PLAYLIST =====
		-- The exit conditions are "Ended fired" or "TimePosition reached the fade point". If the voice ever
		-- STOPS advancing without firing Ended -- stopped by something else, an asset that unloads, a stream
		-- that dies -- TimePosition freezes below fadeStart, Ended never comes, and this spins here for the
		-- rest of the session. The pcall around the caller cannot save it: a hang is not an error, so nothing
		-- logs and nothing retries. The symptom is exactly "the music played for a while then never moved on".
		--
		-- Two guards, both of which fall through to the crossfade -- advancing is always better than silence:
		--   * A WALL-CLOCK CAP of the track's own length + 15s. Generous enough that normal playback, a duck or
		--     a slow frame can never trip it; short enough that a dead track costs one song, not the session.
		--   * A STALL CHECK: IsPlaying going false while we wait means it is not coming back. Given a 3s grace
		--     period, because IsPlaying can still read false for the first frames after :Play().
		local t0, lastBeat, stalledFor = os.clock(), 0, 0
		while not ended and voice.TimePosition < fadeStart do
			task.wait(0.1)
			local elapsed = os.clock() - t0
			if elapsed > len + 15 then
				warn(string.format("[MUSIC CLIENT] voice %d: TIMED OUT after %.0fs (TimePosition stuck at %.1f of "
					.. "%.1f) -- advancing to the next track rather than stranding the playlist",
					vnum, elapsed, voice.TimePosition, len))
				break
			end
			if elapsed > 3 and not voice.IsPlaying then
				stalledFor = stalledFor + 0.1
				if stalledFor >= 1.5 then
					warn(string.format("[MUSIC CLIENT] voice %d: STOPPED PLAYING without firing Ended (TimePosition "
						.. "%.1f of %.1f) -- advancing", vnum, voice.TimePosition, len))
					break
				end
			else
				stalledFor = 0
			end
			-- Once-a-minute heartbeat: if this ever hangs again the log says whether the clock was still moving,
			-- which is the difference between "stalled" and "the exit condition is wrong".
			if elapsed - lastBeat >= 60 then
				lastBeat = elapsed
				print(string.format("[MUSIC CLIENT] voice %d: still playing, %.0fs / %.0fs", vnum, voice.TimePosition, len))
			end
		end
	else
		-- A loaded track with no length has no audio to give. This used to wait TEN MINUTES on an Ended that
		-- such a sound never fires -- one dud id bought itself ten minutes of silence, which is most of what
		-- "the music stops" looked like. Give it DEAD_AIR_MAX and move on.
		warn(string.format("[MUSIC CLIENT] voice %d: TimeLength=0 after load (%s has no playable audio) -- "
			.. "giving it %ds, then advancing", vnum, voice.SoundId, DEAD_AIR_MAX))
		dropFromRotation(voice.SoundId)
		local t0 = os.clock()
		while not ended and (os.clock() - t0) < DEAD_AIR_MAX do task.wait(0.25) end
	end
	conn:Disconnect()
	print(string.format("[MUSIC CLIENT] voice %d: near-end reached (ended=%s, TimePosition=%.1f) -> CROSSFADE", vnum, tostring(ended), voice.TimePosition))
end

--======================================================================
-- THE PLAYLIST
--======================================================================
task.spawn(function()
	-- Start from the VERIFIED list. If verification is somehow still running, take the full list rather than
	-- standing in silence -- the per-track load guard above still catches a dud, just one song later.
	local t0 = os.clock()
	while not verified and (os.clock() - t0) < VERIFY_GRACE do task.wait(0.2) end
	if not verified then
		warn(("[MUSIC CLIENT] id verification did not finish in %ds -- starting with the full track list"):format(VERIFY_GRACE))
		playable = table.clone(MUSIC_TRACKS)
	elseif #playable == 0 then
		warn("[MUSIC CLIENT] NO music id loads for this experience -- there is nothing to play. Replace the ids "
			.. "in MUSIC_TRACKS (see the per-track lines above for which failed).")
		return
	end

	local cur = 1
	local playing = false -- is a voice actually sounding? drives prime-vs-crossfade, so a failed start can
	                      -- never leave the loop waiting on the end of a track that never began

	while true do
		local ok, err = pcall(function()
			if not playing then
				if startTrackOn(voices[cur], cur) then playing = true else task.wait(2) end
				return
			end

			local curVoice = voices[cur]
			waitForNearEnd(curVoice, cur)

			-- CROSSFADE: start the next track on the OTHER voice (it fades IN inside startTrackOn), then fade
			-- the current one OUT over the same window.
			local nxt = 3 - cur
			local nid = startTrackOn(voices[nxt], nxt)
			if not nid then
				-- Nothing to cross into. Stop the old voice rather than fading into silence, and come back
				-- around to the prime branch above once the rotation has something to give again.
				curVoice:Stop(); curVoice.Volume = 0
				playing = false
				task.wait(2)
				return
			end
			print(string.format("[MUSIC CLIENT] CROSSFADING voice %d -> voice %d (now playing %s)", cur, nxt, nid))
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
		if #playable == 0 then
			warn("[MUSIC CLIENT] every track has been dropped -- background music is off for this session.")
			return
		end
	end
end)
