--======================================================================
-- EventSoundPreload.client.lua  (LocalScript)
--======================================================================
-- SURGICAL CACHE-PRIMING ONLY. At join, this preloads EXACTLY the event sounds listed below so they
-- play instantly the first time an event fires (no first-trigger load delay / missing audio).
--
-- It runs on the CLIENT because audio is loaded/decoded client-side for playback — priming the CLIENT
-- content cache is what makes the sound ready instantly when its (server- or client-created) Sound
-- replicates/plays. (A server-side PreloadAsync of sounds would not prime client audio.)
--
-- It does NOT create, parent, play, scope, trigger, or restructure any gameplay Sound. The temporary
-- Sound instances here are never played and are destroyed right after the cache is primed. The real
-- event sounds stay exactly where/how they already are.
--======================================================================

local ContentProvider = game:GetService("ContentProvider")

-- EXACT list (do NOT add others): rocket construction / countdown / launch, meteor impact / intro,
-- UFO alien, mutation, and the 4 background-music tracks.
local EVENT_SOUND_IDS = {
	"rbxassetid://133543192033291", -- rocket construction
	"rbxassetid://1841791990",      -- rocket countdown
	"rbxassetid://135490777114772", -- rocket launch
	"rbxassetid://114095353806681", -- meteor impact
	"rbxassetid://109362273688140", -- meteor intro
	"rbxassetid://82428123919520",  -- UFO alien
	"rbxassetid://97213152915968",  -- mutation
	"rbxassetid://140517328454242", -- music track 1
	"rbxassetid://139448720739903", -- music track 2
	"rbxassetid://139206228229841", -- music track 3
	"rbxassetid://138099443718294", -- music track 4
}

task.spawn(function()
	-- Build a throwaway Sound per id (SoundId set, NEVER played) purely for cache priming.
	local primers = {}
	for _, id in ipairs(EVENT_SOUND_IDS) do
		local s = Instance.new("Sound")
		s.SoundId = id
		primers[#primers + 1] = s
	end
	-- One PreloadAsync call, wrapped in pcall so a thrown error can't crash the loader. The per-asset
	-- callback warns on any single failure and the loader continues with the others.
	pcall(function()
		ContentProvider:PreloadAsync(primers, function(contentId, status)
			if status == Enum.AssetFetchStatus.Failure then
				warn("[Preload] failed: " .. tostring(contentId))
			end
		end)
	end)
	-- Done priming — discard the throwaway instances (the cache stays warm).
	for _, s in ipairs(primers) do s:Destroy() end
end)
