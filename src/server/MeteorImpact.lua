--======================================================================
-- MeteorImpact.lua  (ModuleScript)
--======================================================================
-- Handles what happens when a meteor lands, for the "MeteorStorm" event.
--
-- On impact (all SERVER-created + replicated parts so everyone sees it):
--   * a big neon explosion fireball
--   * debris particles + scattered debris rocks (CanCollide=false)
--   * an expanding + fading shockwave ring
--   * lingering fire / smoke
--   * a SCORCHED IMPACT ZONE on the ground (NOT a deep crater): a
--     blackened/cracked disc, glowing Neon "lava" cracks, smoke + embers,
--     and small fire particles. The whole zone FADES then is destroyed.
--   * fires MeteorSync "impact" so each client shakes its own camera +
--     plays its own boom (per-client camera effect).
--   * runs the SERVER-AUTHORITATIVE knockback proximity check and tells
--     ONLY the nearby clients to nudge their OWN HumanoidRootPart.
--   * asks MeteorReward to (maybe) drop coins/loot.
--
-- Bigger meteor (higher `bigness`) => bigger scorch, more debris, stronger
-- cracks, bigger explosion.
--
-- GAMEPLAY SAFETY:
--   * EVERY scorch/debris/explosion part is CanCollide=false so it can
--     never block, trap or stand on a player.
--   * The ONLY gameplay effects are: (a) knockback = a pure physics nudge
--     applied client-side to the player's own HRP (never touches gas /
--     fart power / flight / coins), and (b) coin/loot rewards via
--     MeteorReward. Both are CONFIG-gated and can be zeroed.
--======================================================================

local MeteorImpact = {}

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")  -- for the impact-sound RemoteEvent

-- Wired by init().
local CONFIG = nil
local MeteorSync = nil
local MeteorReward = nil

-- Folder holding all scorch/explosion parts so cleanup is one Destroy().
local impactFolder = nil

-- MOBILE-RELIABLE meteor-impact sound. The sound is NO LONGER played on the server (server-side audio
-- isn't always reliable on mobile, and the old Sound lived on a folder that gets destroyed). Instead we
-- fire the "MeteorImpactSound" RemoteEvent to ALL clients on every impact; each client plays its own
-- copy from SoundService (see MeteorImpactSound.client.lua), keeping the don't-restart rule locally.
local IMPACT_SOUND_EVENT_NAME = "MeteorImpactSound"  -- the RemoteEvent the clients listen on

--------------------------------------------------------------------
-- init(config, syncEvent, rewardModule): wire shared dependencies.
--------------------------------------------------------------------
function MeteorImpact.init(config, syncEvent, rewardModule)
	CONFIG = config
	MeteorSync = syncEvent
	MeteorReward = rewardModule
end

--------------------------------------------------------------------
-- ensureFolder(): fresh folder for impact instances.
--------------------------------------------------------------------
local function ensureFolder()
	if not impactFolder or not impactFolder.Parent then
		impactFolder = Instance.new("Folder")
		impactFolder.Name = "MeteorStormImpacts"
		impactFolder.Parent = workspace
	end
	return impactFolder
end

--------------------------------------------------------------------
-- makeEmitter(parent, props): capped emitter helper (same cap as spawn).
--------------------------------------------------------------------
local function makeEmitter(parent, props)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = props.Texture or "rbxasset://textures/particles/smoke_main.dds"
	pe.Rate = math.min(props.Rate or 10, CONFIG.MAX_PARTICLE_RATE)
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
	return pe
end

--------------------------------------------------------------------
-- buildScorchZone(pos, radius, bigness, vdefLight): the lingering scorch.
-- A flat blackened disc + glowing Neon cracks + scattered debris rocks +
-- smoke/embers/small fire. Everything CanCollide=false. The whole folder
-- of scorch parts FADES (tween transparency to 1) then is destroyed.
--------------------------------------------------------------------
local function buildScorchZone(pos, radius, bigness, lightColor)
	local folder = ensureFolder()

	-- Group this single impact's scorch parts so we can fade + destroy them
	-- together without affecting other concurrent impacts.
	local zone = Instance.new("Model")
	zone.Name = "ScorchZone"
	zone.Parent = folder

	local scorchRadius = radius * (2.5 + bigness * 3) -- bigger meteor = wider scorch
	local fadeParts = {} -- parts we will tween to transparent

	-- ---- Blackened ground disc (thin, flat, sits ON the surface). ----
	local disc = Instance.new("Part")
	disc.Name = "ScorchDisc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Ground
	disc.Color = Color3.fromRGB(25, 20, 18)
	disc.Size = Vector3.new(0.4, scorchRadius * 2, scorchRadius * 2)
	disc.Anchored = true
	disc.CanCollide = false   -- never blocks players
	disc.CanQuery = false
	disc.CanTouch = false
	-- Lay the cylinder flat (length axis vertical -> rotate 90 about Z) just
	-- above the ground so it reads as a charred patch.
	disc.CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.Transparency = 0.05
	disc.Parent = zone
	table.insert(fadeParts, disc)

	-- ---- Glowing Neon "lava" cracks radiating from the center. Count scales
	--      with bigness (stronger cracks on bigger meteors), capped. ----
	local crackCount = math.clamp(math.floor(4 + bigness * 6), 4, CONFIG.MAX_CRACKS)
	for i = 1, crackCount do
		local ang = math.rad((360 / crackCount) * i + math.random(-15, 15))
		local len = scorchRadius * (0.4 + math.random() * 0.6)
		local crack = Instance.new("Part")
		crack.Name = "LavaCrack_" .. i
		crack.Material = Enum.Material.Neon
		crack.Color = lightColor or Color3.fromRGB(255, 110, 30)
		crack.Size = Vector3.new(len, 0.25, math.random(4, 8) / 10)
		crack.Anchored = true
		crack.CanCollide = false
		crack.CanQuery = false
		crack.CanTouch = false
		-- Lay along the ground, radiating outward from center.
		crack.CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0))
			* CFrame.Angles(0, ang, 0)
			* CFrame.new(len / 2, 0, 0)
		crack.Transparency = 0.1
		crack.Parent = zone
		table.insert(fadeParts, crack)
	end

	-- ---- Scattered debris rocks around the rim (CanCollide=false). ----
	local debrisCount = math.clamp(math.floor(3 + bigness * 8), 3, CONFIG.MAX_DEBRIS_ROCKS)
	for i = 1, debrisCount do
		local ang = math.random() * math.pi * 2
		local dist = scorchRadius * (0.5 + math.random() * 0.7)
		local sz = math.random(6, 16) / 10 * (1 + bigness)
		local chunk = Instance.new("Part")
		chunk.Name = "DebrisRock_" .. i
		chunk.Material = Enum.Material.Slate
		chunk.Color = Color3.fromRGB(45, 40, 38)
		chunk.Size = Vector3.new(sz, sz * 0.8, sz)
		chunk.Anchored = true
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CFrame = CFrame.new(pos + Vector3.new(math.cos(ang) * dist, sz * 0.4, math.sin(ang) * dist))
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.Transparency = 0
		chunk.Parent = zone
		table.insert(fadeParts, chunk)
	end

	-- ---- Lingering smoke + embers + small fire from the center. ----
	local emberAnchor = Instance.new("Part")
	emberAnchor.Name = "ScorchEmberAnchor"
	emberAnchor.Size = Vector3.new(1, 1, 1)
	emberAnchor.Transparency = 1
	emberAnchor.Anchored = true
	emberAnchor.CanCollide = false
	emberAnchor.CanQuery = false
	emberAnchor.CanTouch = false
	emberAnchor.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
	emberAnchor.Parent = zone

	local lingerSmoke = makeEmitter(emberAnchor, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = math.floor(4 + bigness * 8),
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(2, 5),
		Size = NumberSequence.new(scorchRadius * 0.6),
		Color = ColorSequence.new(Color3.fromRGB(50, 45, 42)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Acceleration = Vector3.new(0, 5, 0),
	})
	local lingerFire = makeEmitter(emberAnchor, {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Rate = math.floor(3 + bigness * 6),
		Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(1, 3),
		Size = NumberSequence.new(radius * 0.8),
		Color = ColorSequence.new(Color3.fromRGB(255, 150, 50), Color3.fromRGB(200, 40, 0)),
		LightEmission = 1,
		Transparency = NumberSequence.new(0.2),
	})
	local lingerEmbers = makeEmitter(emberAnchor, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = math.floor(3 + bigness * 5),
		Lifetime = NumberRange.new(0.6, 1.4),
		Speed = NumberRange.new(3, 7),
		SpreadAngle = Vector2.new(40, 40),
		Size = NumberSequence.new(0.4),
		Color = ColorSequence.new(lightColor or Color3.fromRGB(255, 140, 40)),
		LightEmission = 1,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Acceleration = Vector3.new(0, 6, 0),
	})

	-- ---- Fade the whole zone over SCORCH_LIFETIME, then destroy it. ----
	local life = CONFIG.SCORCH_LIFETIME
	-- Stop emitting partway so smoke has time to clear before destroy.
	task.delay(life * 0.6, function()
		if lingerSmoke then lingerSmoke.Enabled = false end
		if lingerFire then lingerFire.Enabled = false end
		if lingerEmbers then lingerEmbers.Enabled = false end
	end)
	-- Begin the visual fade after a hold, so the scorch lingers first.
	task.delay(life * 0.5, function()
		for _, p in ipairs(fadeParts) do
			if p and p.Parent then
				TweenService:Create(p, TweenInfo.new(life * 0.5, Enum.EasingStyle.Linear),
					{ Transparency = 1 }):Play()
			end
		end
	end)
	-- Final destroy (also covered by cleanup() if the event ends sooner).
	Debris:AddItem(zone, life + 1)
end

--------------------------------------------------------------------
-- buildExplosion(pos, radius, bigness, lightColor, legendary): the burst.
-- Fireball + shockwave ring + debris particles + loud boom. All parts
-- CanCollide=false. Sizes scale with bigness; legendary is much larger.
--------------------------------------------------------------------
local function buildExplosion(pos, radius, bigness, lightColor, legendary)
	local folder = ensureFolder()
	local scale = legendary and CONFIG.LEGENDARY_EXPLOSION_SCALE or (1 + bigness * 1.5)

	-- ---- Fireball core ----
	local fireball = Instance.new("Part")
	fireball.Name = "MeteorFireball"
	fireball.Shape = Enum.PartType.Ball
	fireball.Material = Enum.Material.Neon
	fireball.Color = legendary and Color3.fromRGB(255, 215, 80) or Color3.fromRGB(255, 150, 40)
	fireball.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	fireball.Anchored = true
	fireball.CanCollide = false
	fireball.CanQuery = false
	fireball.CanTouch = false
	fireball.CFrame = CFrame.new(pos + Vector3.new(0, radius, 0))
	fireball.Parent = folder
	TweenService:Create(fireball,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(radius * 14 * scale, radius * 14 * scale, radius * 14 * scale),
		  Transparency = 1 }):Play()

	local fbEmitter = makeEmitter(fireball, {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Rate = CONFIG.MAX_PARTICLE_RATE,
		Lifetime = NumberRange.new(0.4, 1.0),
		Speed = NumberRange.new(15, 35),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(radius * 4),
		Color = ColorSequence.new(
			legendary and Color3.fromRGB(255, 240, 140) or Color3.fromRGB(255, 220, 120),
			Color3.fromRGB(255, 60, 0)),
		LightEmission = 1,
		Transparency = NumberSequence.new(0.1),
	})
	task.delay(0.35, function()
		if fbEmitter then fbEmitter.Enabled = false end
	end)

	-- Bright flash light for the burst.
	local flash = Instance.new("PointLight")
	flash.Color = lightColor or Color3.fromRGB(255, 150, 60)
	flash.Brightness = legendary and 10 or 5
	flash.Range = math.clamp(radius * 12 * scale, 30, 120)
	flash.Parent = fireball

	-- ---- Expanding shockwave ring (thin neon disc). ----
	local ring = Instance.new("Part")
	ring.Name = "MeteorShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 245, 210)
	ring.Size = Vector3.new(0.5, radius * 4, radius * 4)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	ring.Parent = folder
	TweenService:Create(ring,
		TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.5, radius * 30 * scale, radius * 30 * scale), Transparency = 1 }):Play()

	-- ---- Debris particle burst (smoke + sparks fan). ----
	local burstAnchor = Instance.new("Part")
	burstAnchor.Name = "MeteorBurstAnchor"
	burstAnchor.Size = Vector3.new(1, 1, 1)
	burstAnchor.Transparency = 1
	burstAnchor.Anchored = true
	burstAnchor.CanCollide = false
	burstAnchor.CanQuery = false
	burstAnchor.CanTouch = false
	burstAnchor.CFrame = CFrame.new(pos + Vector3.new(0, radius, 0))
	burstAnchor.Parent = folder
	local burstSmoke = makeEmitter(burstAnchor, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = CONFIG.MAX_PARTICLE_RATE,
		Lifetime = NumberRange.new(1.5, 3),
		Speed = NumberRange.new(10, 25),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(radius * 5 * scale),
		Color = ColorSequence.new(Color3.fromRGB(60, 55, 50)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	task.delay(0.5, function()
		if burstSmoke then burstSmoke.Enabled = false end
	end)

	-- ---- Loud boom (positional). ----
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxassetid://5801257793"
	snd.Volume = 1   -- unified volume: matches the meteor intro sound
	snd.RollOffMaxDistance = 6000
	snd.Parent = fireball
	snd:Play()

	-- Tidy the static explosion parts after visuals finish (also in cleanup()).
	Debris:AddItem(fireball, 2)
	Debris:AddItem(ring, 2)
	Debris:AddItem(burstAnchor, 4)
end

--------------------------------------------------------------------
-- applyKnockback(pos, radius, legendary): SERVER-AUTHORITATIVE proximity
-- check. The SERVER decides who is close enough, then tells ONLY those
-- clients to nudge their OWN HumanoidRootPart (clients own their character
-- physics, so server-applied velocity wouldn't stick reliably).
--
-- The fired payload is { dir = unit Vector3 (horizontal away + slight up),
-- force = studs/sec impulse }. The client handler ONLY touches the HRP's
-- velocity — it never reads or writes gas / fart power / flight / coins.
--------------------------------------------------------------------
local function applyKnockback(pos, radius, legendary)
	if CONFIG.METEOR_KNOCKBACK_FORCE <= 0 or CONFIG.METEOR_HIT_RADIUS <= 0 then
		return -- knockback disabled via CONFIG
	end
	local hitRadius = CONFIG.METEOR_HIT_RADIUS + radius -- a touch wider for bigger rocks
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local delta = hrp.Position - pos
			local dist = delta.Magnitude
			if dist <= hitRadius then
				-- Direction = mostly horizontal away from impact, with a small
				-- upward component so the player gets a believable little "pop".
				local horiz = Vector3.new(delta.X, 0, delta.Z)
				if horiz.Magnitude < 0.1 then horiz = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) end
				horiz = horiz.Unit
				local dir = (horiz + Vector3.new(0, 0.6, 0)).Unit
				-- Closer = stronger (linear falloff), capped at the configured force.
				local falloff = math.clamp(1 - dist / hitRadius, 0.2, 1)
				local force = CONFIG.METEOR_KNOCKBACK_FORCE * falloff
				if legendary then force = force * 1.4 end -- legendary hits a bit harder (still modest)
				-- Tell THIS client to apply the nudge to its own HRP.
				MeteorSync:FireClient(plr, "knockback", { dir = dir, force = force })
			end
		end
	end
end

--------------------------------------------------------------------
-- playImpactSound(): SERVER-WIDE impact sound, now MOBILE-RELIABLE. We fire the impact-sound
-- RemoteEvent to ALL clients on EVERY impact (same "every impact, server-wide" trigger as before);
-- each client plays its own preloaded copy from SoundService and applies the don't-restart-if-already-
-- playing rule locally. No server-side Sound is created/played anymore.
--------------------------------------------------------------------
local function playImpactSound()
	local ev = ReplicatedStorage:FindFirstChild(IMPACT_SOUND_EVENT_NAME)
	if ev then ev:FireAllClients() end
end

--======================================================================
-- onImpact(info): the public entry the spawn module calls on landing.
--   info = { position, radius, bigness, variant, legendary, lightColor }
--======================================================================
function MeteorImpact.onImpact(info)
	local pos = info.position
	local radius = info.radius or 3
	local bigness = info.bigness or 0.5
	local legendary = info.legendary == true

	-- Visuals (replicated server parts -> everyone sees them).
	buildExplosion(pos, radius, bigness, info.lightColor, legendary)
	buildScorchZone(pos, radius, bigness, info.lightColor)

	-- SERVER-WIDE impact sound (skipped if one is already playing).
	playImpactSound()

	-- Tell every client to shake its OWN camera + play its boom. Bigger
	-- meteor / legendary = stronger shake. (Camera shake is per-client.)
	local shakeIntensity = (legendary and CONFIG.LEGENDARY_SHAKE or CONFIG.IMPACT_SHAKE)
		* (0.6 + bigness * 0.8)
	MeteorSync:FireAllClients("impact", {
		position = pos,
		intensity = shakeIntensity,
		legendary = legendary,
	})

	-- Gameplay touch-point #1: knockback (pure HRP physics, server-decided).
	applyKnockback(pos, radius, legendary)

	-- Gameplay touch-point #2: rewards (coins/loot), CONFIG-gated + modest.
	if MeteorReward then
		MeteorReward.maybeDrop(pos, radius, legendary)
	end
end

--======================================================================
-- cleanup(): destroy all impact/scorch instances. No leaks.
--======================================================================
function MeteorImpact.cleanup()
	if impactFolder and impactFolder.Parent then
		impactFolder:Destroy()
	end
	impactFolder = nil
	-- (No server-side impact Sound to reset anymore — the impact sound now plays per-client.)
end

return MeteorImpact
