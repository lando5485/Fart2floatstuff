--======================================================================
-- RocketEffects.lua  (ModuleScript)
--======================================================================
-- Server-side, replicated VFX for the Rocket Construction & Launch event.
--
-- Everything in here creates real Workspace instances on the SERVER so
-- that every client sees the identical effect (server-authoritative).
-- ParticleEmitters, smoke, fire, the explosion fireball, shockwave ring,
-- smoke cloud and falling debris all live here.
--
-- PERFORMANCE NOTES:
--   * Every emitter Rate is capped low.
--   * Debris count is capped by the caller (MAX_DEBRIS from CONFIG).
--   * Every instance we create is tracked and Destroy()'d in cleanup().
--   * Nothing is anchored in a player's way; effect parts are
--     CanCollide=false, Massless and Anchored only for the explosion
--     (which is far above island 14, not where players stand).
--======================================================================

local RocketEffects = {}

local Debris = game:GetService("Debris")

-- Folder that holds every effect instance we spawn so cleanup is trivial.
local effectsFolder = nil

-- Live handles we may need to stop early (build ambience emitters etc).
local activeEmitters = {}   -- list of ParticleEmitter we toggle off later
local activeSounds = {}     -- list of Sound instances to clean up

--------------------------------------------------------------------
-- Phase sound config (tunable). The CONSTRUCTION loop is POSITIONAL (only
-- heard near the rocket on island 1); the COUNTDOWN sound is SERVER-WIDE
-- (heard by everyone). Edit these freely.
--------------------------------------------------------------------
local CONSTRUCTION_SOUND_ID  = "rbxassetid://133543192033291"
local CONSTRUCTION_VOLUME    = 1     -- unified volume: matches the meteor intro sound
local CONSTRUCTION_FULLVOL   = 200   -- studs: stays at FULL volume out to here (covers all of island 1)
local CONSTRUCTION_ROLLOFF   = 450   -- studs: faded to silence by here -- well short of island 2 (~614 away), so stays LOCAL
local COUNTDOWN_SOUND_ID     = "rbxassetid://1841791990"
local COUNTDOWN_VOLUME       = 1     -- unified volume: matches the meteor intro sound
local LAUNCH_SOUND_ID        = "rbxassetid://135490777114772"
local LAUNCH_VOLUME          = 1     -- unified volume: matches the meteor intro sound

-- Handles for the looping construction sound so we can stop it at countdown.
local constructionSoundAnchor = nil  -- the BasePart hosting the positional loop
local constructionSound = nil        -- the looping Sound itself

--------------------------------------------------------------------
-- Internal helper: make sure we have a fresh effects folder.
--------------------------------------------------------------------
local function ensureFolder()
	if not effectsFolder or not effectsFolder.Parent then
		-- STREAMING FIX: a MODEL (not a Folder) so we can mark it Persistent — ModelStreamingMode is a
		-- Model-only property. Persistent => this container + its descendants (the construction-sound
		-- anchor and any other effect parts) replicate to EVERY client regardless of streaming distance,
		-- so the positional sound has a host on every player. Set BEFORE parenting so all children inherit.
		effectsFolder = Instance.new("Model")
		effectsFolder.Name = "RocketEventEffects"
		effectsFolder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		effectsFolder.Parent = workspace
	end
	return effectsFolder
end

--------------------------------------------------------------------
-- Internal helper: build a ParticleEmitter with sane, capped values.
--------------------------------------------------------------------
local function makeEmitter(parent, props)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = props.Texture or "rbxasset://textures/particles/smoke_main.dds"
	pe.Rate = math.min(props.Rate or 10, props.RateCap or 30) -- HARD cap on rate
	pe.Lifetime = props.Lifetime or NumberRange.new(0.6, 1.2)
	pe.Speed = props.Speed or NumberRange.new(2, 5)
	pe.SpreadAngle = props.SpreadAngle or Vector2.new(20, 20)
	pe.Rotation = props.Rotation or NumberRange.new(0, 360)
	pe.Size = props.Size or NumberSequence.new(2)
	pe.Transparency = props.Transparency or NumberSequence.new(0.2)
	pe.Color = props.Color or ColorSequence.new(Color3.new(1, 1, 1))
	pe.LightEmission = props.LightEmission or 0
	pe.Acceleration = props.Acceleration or Vector3.new(0, 0, 0)
	pe.Enabled = props.Enabled ~= false
	pe.Parent = parent
	table.insert(activeEmitters, pe)
	return pe
end

--------------------------------------------------------------------
-- Internal helper: play a sound from a position (or globally).
--------------------------------------------------------------------
local function playSound(soundId, volume, parentPart)
	local snd = Instance.new("Sound")
	snd.SoundId = soundId
	snd.Volume = volume or 1
	snd.RollOffMaxDistance = 4000 -- audible across the big map
	snd.Parent = parentPart or ensureFolder()
	snd:Play()
	table.insert(activeSounds, snd)
	-- Auto-clean once it finishes (but cleanup() also handles it).
	snd.Ended:Connect(function()
		snd:Destroy()
	end)
	return snd
end

--======================================================================
-- BUILD PHASE: sparks + smoke puffs + ambience attached to the site.
-- `site` is a Vector3 (ground position of the rocket).
--======================================================================
function RocketEffects.startBuildAmbience(site)
	local folder = ensureFolder()

	-- An invisible anchor part at the construction site to host emitters.
	local anchor = Instance.new("Part")
	anchor.Name = "BuildAmbienceAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false      -- never blocks a player
	anchor.Anchored = true         -- stays at the site, but it's tiny+intangible
	anchor.CFrame = CFrame.new(site + Vector3.new(0, 3, 0))
	anchor.Parent = folder

	-- Welding sparks (bright, short-lived).
	makeEmitter(anchor, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = 18, RateCap = 30,
		Lifetime = NumberRange.new(0.2, 0.5),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(60, 60),
		Size = NumberSequence.new(0.4),
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 120)),
		LightEmission = 1,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	-- Light construction smoke puffs.
	makeEmitter(anchor, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 6, RateCap = 12,
		Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(1, 3),
		Size = NumberSequence.new(3),
		Color = ColorSequence.new(Color3.fromRGB(180, 180, 180)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Acceleration = Vector3.new(0, 4, 0),
	})

	-- Construction ambience hum.
	playSound("rbxassetid://9120386436", 1, anchor)
end

--======================================================================
-- COUNTDOWN PHASE: thickening smoke under the rocket.
-- `primaryPart` = the rocket's PrimaryPart so smoke tracks the rocket.
--======================================================================
function RocketEffects.startCountdownSmoke(primaryPart)
	if not primaryPart then return end

	-- Attachment-style emitter at the base of the rocket.
	makeEmitter(primaryPart, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 22, RateCap = 30, -- thick but capped
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(3, 7),
		SpreadAngle = Vector2.new(45, 45),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 4),
			NumberSequenceKeypoint.new(1, 10),
		}),
		Color = ColorSequence.new(Color3.fromRGB(210, 210, 210)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Acceleration = Vector3.new(0, -2, 0), -- pools downward at the pad
	})

	-- Low rumble.
	playSound("rbxassetid://9116458024", 1, primaryPart)
end

--======================================================================
-- LAUNCH PHASE: fire particles + thick smoke trail under the rocket.
--======================================================================
function RocketEffects.startLaunchTrail(primaryPart)
	if not primaryPart then return end

	-- Engine fire.
	makeEmitter(primaryPart, {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Rate = 28, RateCap = 30,
		Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(15, 15),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 6),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 120)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 0)),
		}),
		LightEmission = 1,
		Transparency = NumberSequence.new(0.1),
		Acceleration = Vector3.new(0, -10, 0),
	})

	-- Thick smoke trail.
	makeEmitter(primaryPart, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 26, RateCap = 30,
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(30, 30),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 5),
			NumberSequenceKeypoint.new(1, 16),
		}),
		Color = ColorSequence.new(Color3.fromRGB(150, 150, 150)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Acceleration = Vector3.new(0, -6, 0),
	})

	-- Launch roar (attached so it travels with the rocket).
	playSound("rbxassetid://9112854440", 1, primaryPart)
end

--======================================================================
-- ENDING: cinematic explosion at `endPos` (Vector3).
--   * huge fireball
--   * expanding + fading shockwave ring
--   * smoke cloud
--   * up to maxDebris falling+fading debris pieces
--   * loud explosion sound
-- All explosion parts are CanCollide=false and high in the sky.
--======================================================================
function RocketEffects.explode(endPos, maxDebris)
	local folder = ensureFolder()
	maxDebris = math.min(maxDebris or 18, 30) -- hard safety cap

	-- ---- Fireball core ----
	local fireball = Instance.new("Part")
	fireball.Name = "RocketFireball"
	fireball.Shape = Enum.PartType.Ball
	fireball.Material = Enum.Material.Neon
	fireball.Color = Color3.fromRGB(255, 150, 40)
	fireball.Size = Vector3.new(10, 10, 10)
	fireball.Anchored = true
	fireball.CanCollide = false
	fireball.CFrame = CFrame.new(endPos)
	fireball.Parent = folder

	-- Expand then fade the fireball.
	local TweenService = game:GetService("TweenService")
	local grow = TweenService:Create(fireball,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(70, 70, 70), Transparency = 1 })
	grow:Play()

	-- Fire emitter on the fireball.
	makeEmitter(fireball, {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Rate = 30, RateCap = 30,
		Lifetime = NumberRange.new(0.5, 1.2),
		Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(12),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 150)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 0)),
		}),
		LightEmission = 1,
		Transparency = NumberSequence.new(0.1),
	})
	-- Burst once then disable so it doesn't keep emitting forever.
	task.delay(0.4, function()
		for _, pe in ipairs(activeEmitters) do
			if pe and pe.Parent == fireball then pe.Enabled = false end
		end
	end)

	-- ---- Expanding shockwave ring ----
	local ring = Instance.new("Part")
	ring.Name = "RocketShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 255, 220)
	ring.Size = Vector3.new(1, 8, 8) -- thin disc (Cylinder length on X)
	ring.Anchored = true
	ring.CanCollide = false
	-- Rotate so the flat disc faces up (cylinder axis vertical-ish, kept horizontal ring).
	ring.CFrame = CFrame.new(endPos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	ring.Parent = folder
	local ringTween = TweenService:Create(ring,
		TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(1, 160, 160), Transparency = 1 })
	ringTween:Play()

	-- ---- Smoke cloud ----
	local smokeAnchor = Instance.new("Part")
	smokeAnchor.Name = "RocketSmokeCloud"
	smokeAnchor.Size = Vector3.new(1, 1, 1)
	smokeAnchor.Transparency = 1
	smokeAnchor.Anchored = true
	smokeAnchor.CanCollide = false
	smokeAnchor.CFrame = CFrame.new(endPos)
	smokeAnchor.Parent = folder
	local smokeEmitter = makeEmitter(smokeAnchor, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 30, RateCap = 30,
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(8, 18),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 14),
			NumberSequenceKeypoint.new(1, 40),
		}),
		Color = ColorSequence.new(Color3.fromRGB(70, 70, 70)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	task.delay(0.6, function()
		if smokeEmitter then smokeEmitter.Enabled = false end
	end)

	-- ---- Falling + fading debris (capped) ----
	for i = 1, maxDebris do
		local chunk = Instance.new("Part")
		chunk.Name = "RocketDebris_" .. i
		chunk.Size = Vector3.new(
			math.random(15, 35) / 10,
			math.random(15, 35) / 10,
			math.random(15, 35) / 10)
		chunk.Material = Enum.Material.Metal
		chunk.Color = Color3.fromRGB(120, 120, 130)
		chunk.CanCollide = false   -- never lands on / blocks a player
		chunk.Anchored = false     -- physics so it arcs out and falls
		chunk.CFrame = CFrame.new(endPos) * CFrame.Angles(
			math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.Parent = folder
		-- Launch it outward in a random direction.
		local dir = Vector3.new(
			math.random(-100, 100),
			math.random(20, 100),
			math.random(-100, 100)).Unit
		chunk.AssemblyLinearVelocity = dir * math.random(60, 120)
		-- Fade it out, then Debris auto-destroys it (also covered by cleanup).
		TweenService:Create(chunk,
			TweenInfo.new(2.5, Enum.EasingStyle.Linear),
			{ Transparency = 1 }):Play()
		Debris:AddItem(chunk, 3)
	end

	-- ---- Loud explosion sound ----
	playSound("rbxassetid://5801257793", 1, fireball)

	-- Tidy the static explosion parts after the visuals finish.
	Debris:AddItem(fireball, 2)
	Debris:AddItem(ring, 2)
	Debris:AddItem(smokeAnchor, 5)
end

--======================================================================
-- Optional global siren/alarm at the very start of the event.
--======================================================================
function RocketEffects.playSiren(site)
	local folder = ensureFolder()
	local anchor = Instance.new("Part")
	anchor.Name = "RocketSirenAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.CFrame = CFrame.new(site or Vector3.new(0, 50, 0))
	anchor.Parent = folder
	playSound("rbxassetid://9116544355", 1, anchor)
	Debris:AddItem(anchor, 6)
end

--======================================================================
-- CONSTRUCTION LOOP (POSITIONAL / LOCAL): start a looping construction sound
-- parented to a tiny invisible part AT the build site. Because the Sound's
-- parent is a BasePart it is 3D/positional, so its volume falls off with
-- distance (full volume across island 1 out to CONSTRUCTION_FULLVOL, faded by
-- CONSTRUCTION_ROLLOFF -- short of island 2, so it stays LOCAL). Loops until
-- stopConstructionSound() is called. `site` = the Vector3 ground position.
--======================================================================
function RocketEffects.startConstructionSound(site)
	-- Guard against a stale loop if called twice.
	RocketEffects.stopConstructionSound()

	local folder = ensureFolder()
	local anchor = Instance.new("Part")
	anchor.Name = "ConstructionSoundAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false      -- never blocks a player
	anchor.Anchored = true
	anchor.CFrame = CFrame.new((site or Vector3.new(0, 50, 0)) + Vector3.new(0, 3, 0))
	anchor.Parent = folder
	constructionSoundAnchor = anchor

	local snd = Instance.new("Sound")
	snd.Name = "ConstructionLoop"
	snd.SoundId = CONSTRUCTION_SOUND_ID
	snd.Volume = CONSTRUCTION_VOLUME
	snd.Looped = true                                  -- keep looping the ~34s clip
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.RollOffMinDistance = CONSTRUCTION_FULLVOL      -- full volume across island 1
	snd.RollOffMaxDistance = CONSTRUCTION_ROLLOFF      -- faded out beyond the island => POSITIONAL / local
	snd.Parent = anchor                                -- BasePart parent => POSITIONAL
	snd:Play()
	print(string.format("[RocketSound] construction start asset=%s pos=(%.0f,%.0f,%.0f) playing=%s",
		CONSTRUCTION_SOUND_ID, anchor.Position.X, anchor.Position.Y, anchor.Position.Z,
		tostring(snd.IsPlaying)))
	table.insert(activeSounds, snd)
	constructionSound = snd
	return snd
end

--======================================================================
-- stopConstructionSound(): stop + remove the looping construction sound.
-- Called exactly when the 10s countdown begins. Destroying the host anchor
-- also stops/destroys its child Sound.
--======================================================================
function RocketEffects.stopConstructionSound()
	if constructionSound and constructionSound.Parent then
		constructionSound:Stop()
	end
	if constructionSoundAnchor and constructionSoundAnchor.Parent then
		constructionSoundAnchor:Destroy()
	end
	constructionSound = nil
	constructionSoundAnchor = nil
end

--======================================================================
-- COUNTDOWN SOUND (SERVER-WIDE): parented to the effects FOLDER (not a
-- BasePart), so it plays globally / 2D for every client. Created on the
-- server => replicates to everyone. Played once.
--======================================================================
function RocketEffects.startCountdownSound()
	local folder = ensureFolder()
	local snd = Instance.new("Sound")
	snd.Name = "CountdownGlobal"
	snd.SoundId = COUNTDOWN_SOUND_ID
	snd.Volume = COUNTDOWN_VOLUME
	snd.Looped = false
	snd.Parent = folder            -- Folder (non-BasePart) parent => global/server-wide
	snd:Play()
	table.insert(activeSounds, snd)
	snd.Ended:Connect(function()
		if snd and snd.Parent then snd:Destroy() end
	end)
	return snd
end

--======================================================================
-- LAUNCH SOUND (SERVER-WIDE): parented to the effects FOLDER so it plays
-- globally for every client the moment the rocket lifts off. Played once.
--======================================================================
function RocketEffects.startLaunchSound()
	local folder = ensureFolder()
	local snd = Instance.new("Sound")
	snd.Name = "LaunchGlobal"
	snd.SoundId = LAUNCH_SOUND_ID
	snd.Volume = LAUNCH_VOLUME
	snd.Looped = false
	snd.Parent = folder            -- Folder (non-BasePart) parent => global/server-wide
	snd:Play()
	table.insert(activeSounds, snd)
	snd.Ended:Connect(function()
		if snd and snd.Parent then snd:Destroy() end
	end)
	return snd
end

--======================================================================
-- CLEANUP: destroy every instance this module created. No leaks.
--======================================================================
function RocketEffects.cleanup()
	-- Stop & drop tracked emitters.
	for _, pe in ipairs(activeEmitters) do
		if pe and pe.Parent then
			pe.Enabled = false
		end
	end
	activeEmitters = {}

	-- Stop & destroy tracked sounds.
	for _, snd in ipairs(activeSounds) do
		if snd and snd.Parent then
			snd:Stop()
			snd:Destroy()
		end
	end
	activeSounds = {}

	-- Destroy the whole effects folder (parts, emitters, sounds, debris).
	if effectsFolder and effectsFolder.Parent then
		effectsFolder:Destroy()
	end
	effectsFolder = nil

	-- Drop the construction-loop handles (the folder destroy removed them).
	constructionSound = nil
	constructionSoundAnchor = nil
end

return RocketEffects
