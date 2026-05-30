--======================================================================
-- MusicManager.server.lua  (Script)
--======================================================================
-- DUCKING INFRASTRUCTURE ONLY. The actual background-music PLAYBACK + shuffle + crossfade now runs
-- CLIENT-SIDE (MusicClient.client.lua). The server could not reliably tell when a track ended —
-- Sound.TimeLength reads 0 (the server never decodes audio), Sound.Ended never fires, and os.clock()
-- timing over a yield is unreliable — so the old server loop got stuck on one song. Clients decode audio
-- properly, so playback + advance live there now. Each player hears their own shuffle (NOT synced across
-- players — fine for background music, and far more reliable).
--
-- WHAT THIS SERVER SCRIPT STILL OWNS (the unchanged contract for MusicDucking.client.lua + the
-- SettingsMenu music toggle): the "BackgroundMusic" SoundGroup with its NormalVolume/DuckedVolume
-- attributes, plus the replicated "BigEventActive" BoolValue. The client music routes its voices THROUGH
-- this group, and MusicDucking.client.lua tweens THIS group's Volume for event ducking AND the mute
-- toggle (via _G.musicEnabled) — so ducking and the settings toggle keep working with NO changes to the
-- client music. Big-event state is read READ-ONLY from _G.BigEvents; nothing is written to those events.
--
-- This script never reads or modifies the fart meter, flight, food, guts, islands, earn rate, coins,
-- hazards, event sounds, or any other system.
--======================================================================

-- ===== CONFIG (tunables) =====
local BACKGROUND_MUSIC_ENABLED = true
local MUSIC_NORMAL_VOLUME = 1     -- normal music level (the group Volume MusicDucking tweens toward)
local MUSIC_DUCKED_VOLUME = 0.28  -- MUCH lower (~28%): when ducked the music sits well under any event audio

local SoundService = game:GetService("SoundService")

if not BACKGROUND_MUSIC_ENABLED then
	print("[MusicManager] background music disabled (BACKGROUND_MUSIC_ENABLED = false)")
	return
end

--======================================================================
-- "BackgroundMusic" SoundGroup: the client music plays THROUGH it, and MusicDucking.client.lua tweens its
-- Volume (the duck target / mute). We set it ONCE here; the client owns it from then on. The client looks
-- it up by name, so MusicDucking + the SettingsMenu music toggle are unchanged.
--======================================================================
local musicGroup = Instance.new("SoundGroup")
musicGroup.Name = "BackgroundMusic"
musicGroup.Volume = MUSIC_NORMAL_VOLUME   -- starting level; the client (MusicDucking) owns it from here on
musicGroup:SetAttribute("NormalVolume", MUSIC_NORMAL_VOLUME)
musicGroup:SetAttribute("DuckedVolume", MUSIC_DUCKED_VOLUME)
musicGroup.Parent = SoundService

-- Replicated flag the client reads to know when ANY big event (Rocket/Meteor/UFO/Ice Age/Mutation) is
-- active, so it can duck. Parented to the group so late joiners get the current value automatically.
local bigFlag = Instance.new("BoolValue")
bigFlag.Name = "BigEventActive"
bigFlag.Value = false
bigFlag.Parent = musicGroup

--======================================================================
-- BIG-EVENT DUCK FLAG: poll the read-only _G.BigEvents registry (set by the five big-event managers) and
-- mirror "any big event running" onto the replicated BoolValue. We only READ isRunning(); we never
-- start/stop or otherwise touch those events.
--======================================================================
task.spawn(function()
	while true do
		local active = false
		local reg = _G.BigEvents
		if reg then
			for _, e in pairs(reg) do
				if e and e.isRunning and e.isRunning() then active = true break end
			end
		end
		if bigFlag.Value ~= active then bigFlag.Value = active end
		task.wait(0.3)
	end
end)

print("[MusicManager] ducking infrastructure ready (BackgroundMusic group + BigEventActive flag); playback runs client-side in MusicClient")
