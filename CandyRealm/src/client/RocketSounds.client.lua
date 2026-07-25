--======================================================================
-- RocketSounds.client.lua  (LocalScript)
--======================================================================
-- MOBILE-RELIABLE playback for the two rocket-event sounds that failed when created/played on the
-- server (the launch one-shot and the positional construction loop). Same proven CLIENT-SIDE-PLAY
-- pattern as the meteor impact sound: the server just broadcasts a signal over RocketEventSync, and
-- each client creates + plays its OWN Sound locally from the already-preloaded asset (preloaded by
-- EventSoundPreload.client.lua). This avoids the server->client one-shot replication/timing problem
-- on mobile.
--
-- SCOPE: this ONLY handles the rocket LAUNCH and CONSTRUCTION sounds. It does not touch the meteor
-- sounds, UFO sound, mutation sound, background music, music ducking, the rocket countdown sound, the
-- rocket model/NPCs/scaffolding, or any other system.
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local Workspace         = game:GetService("Workspace")

-- Settings mirrored from the old server versions in RocketEffects.lua (audio already preloaded).
local LAUNCH_SOUND_ID        = "rbxassetid://135490777114772"
local LAUNCH_VOLUME          = 1

local CONSTRUCTION_SOUND_ID  = "rbxassetid://133543192033291"
local CONSTRUCTION_VOLUME    = 1
local CONSTRUCTION_FULLVOL   = 200   -- RollOffMinDistance (full volume across island 1)
local CONSTRUCTION_ROLLOFF   = 450   -- RollOffMaxDistance (faded out before island 2 -> stays LOCAL)

local sync = ReplicatedStorage:WaitForChild("RocketEventSync", 60)
if not sync then return end

--------------------------------------------------------------------
-- CONSTRUCTION (positional, looped, local to island 1): a local invisible anchor + positional Sound,
-- owned by THIS client (not replicated). Started on "constructionStart", stopped on "constructionStop"
-- (and as a safety on "end").
--------------------------------------------------------------------
local constructionAnchor = nil
local constructionSound = nil

local function stopConstruction()
	if constructionSound then pcall(function() constructionSound:Stop() end); constructionSound = nil end
	if constructionAnchor then pcall(function() constructionAnchor:Destroy() end); constructionAnchor = nil end
end

local function startConstruction(site)
	stopConstruction()  -- guard against a stale loop
	if typeof(site) ~= "Vector3" then return end
	local anchor = Instance.new("Part")
	anchor.Name = "RocketConstructionSoundAnchorLocal"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Anchored = true
	anchor.CFrame = CFrame.new(site + Vector3.new(0, 3, 0))
	anchor.Parent = Workspace  -- created by a LocalScript => local-only, never replicated
	constructionAnchor = anchor

	local snd = Instance.new("Sound")
	snd.Name = "ConstructionLoopLocal"
	snd.SoundId = CONSTRUCTION_SOUND_ID
	snd.Volume = CONSTRUCTION_VOLUME
	snd.Looped = true
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.RollOffMinDistance = CONSTRUCTION_FULLVOL
	snd.RollOffMaxDistance = CONSTRUCTION_ROLLOFF
	snd.Parent = anchor  -- BasePart parent => POSITIONAL / 3D (local to island 1)
	constructionSound = snd
	snd:Play()
end

--------------------------------------------------------------------
-- LAUNCH (server-wide, one-shot): each client plays its OWN 2D Sound from SoundService on "launch".
--------------------------------------------------------------------
local function playLaunch()
	local snd = Instance.new("Sound")
	snd.Name = "RocketLaunchLocal"
	snd.SoundId = LAUNCH_SOUND_ID
	snd.Volume = LAUNCH_VOLUME
	snd.Looped = false
	snd.Parent = SoundService  -- non-BasePart parent => 2D / global for this client (everyone hears it)
	snd:Play()
	snd.Ended:Connect(function() if snd then snd:Destroy() end end)
	task.delay(15, function() if snd and snd.Parent then snd:Destroy() end end)  -- safety cleanup
end

sync.OnClientEvent:Connect(function(phase, payload)
	if phase == "constructionStart" then
		startConstruction(payload)
	elseif phase == "constructionStop" then
		stopConstruction()
	elseif phase == "launch" then
		playLaunch()
	elseif phase == "end" then
		stopConstruction()  -- safety: stop the loop if the event ended/aborted
	end
end)
