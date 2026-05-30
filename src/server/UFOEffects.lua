--======================================================================
-- UFOEffects.lua  (ModuleScript)
--======================================================================
-- Server-side, replicated VFX for the global "UFO" event: the gigantic
-- mothership itself + all its presentation.
--
-- Everything here creates real Workspace instances on the SERVER so every
-- client sees the identical UFO (server-authoritative). It owns:
--   * the ENORMOUS slowly-rotating saucer (glowing underside lights, a
--     hovering bob, a humming engine sound, floating debris orbiting it),
--     visible from every island.
--   * the descent from the clouds and the ENDING energy-charge + flash +
--     rapid ascent + vanish.
--   * WARNING-phase flicker lights / electrical buzz / scout ships.
--   * green glowing fog parts / electricity / a downward "presence" beam.
--   * rare-variant tints (golden / broken-sparking / hostile-red) and the
--     swarm of tiny fast UFOs.
--
-- PERFORMANCE / SAFETY:
--   * Every emitter Rate is capped at CONFIG.MAX_PARTICLE_RATE.
--   * Orbiting debris capped at MAX_DEBRIS_ORBIT, scouts at MAX_SCOUTS.
--   * Every part is Anchored + CanCollide=false (it lives high in the sky,
--     never where players stand, and can never block/trap a player).
--   * Every instance + connection is tracked and destroyed/disconnected in
--     cleanup() -- no leaks.
--   * This module never touches gameplay state of any kind.
--======================================================================

local UFOEffects = {}

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Wired by init().
local CONFIG = nil
local UFOSync = nil

-- Folders / handles (all reset in cleanup()).
local effectsFolder = nil    -- everything we spawn lives in here
local warnFolder = nil       -- WARNING-only flicker lights / scouts
local ufoModel = nil         -- the saucer Model
local ufoPrimary = nil       -- the saucer hull Part (we move/spin this)
local hoverConn = nil        -- Heartbeat: bob + spin + orbit
local warnConn = nil         -- Heartbeat: flicker / scout motion
local hoverBasePos = nil     -- the resting CFrame position the bob oscillates around
local orbitParts = {}        -- debris orbiting the saucer { part, radius, angle, speed, y }
local hovering = false       -- gate for the hover loop
local lightPulse = {}        -- underside rim lights to pulse in sequence { Part, ... }
local pulseConn = nil        -- Heartbeat: chase/pulse the underside rim lights

--------------------------------------------------------------------
-- init(config, syncEvent): wire shared dependencies.
--------------------------------------------------------------------
function UFOEffects.init(config, syncEvent)
	CONFIG = config
	UFOSync = syncEvent
end

--------------------------------------------------------------------
-- ensureFolder(): fresh folder for all UFO VFX instances.
--------------------------------------------------------------------
local function ensureFolder()
	if not effectsFolder or not effectsFolder.Parent then
		effectsFolder = Instance.new("Folder")
		effectsFolder.Name = "UFOEvent"
		effectsFolder.Parent = workspace
	end
	return effectsFolder
end

--------------------------------------------------------------------
-- makeEmitter(parent, props): capped ParticleEmitter helper.
--------------------------------------------------------------------
local function makeEmitter(parent, props)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = props.Texture or "rbxasset://textures/particles/smoke_main.dds"
	pe.Rate = math.min(props.Rate or 8, CONFIG.MAX_PARTICLE_RATE) -- HARD cap
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

-- Variant -> primary glow colour for the saucer / beams / fog.
local function variantColor(variant)
	if variant == "golden" then return Color3.fromRGB(255, 215, 70) end
	if variant == "hostile" then return Color3.fromRGB(255, 50, 50) end
	if variant == "broken" then return Color3.fromRGB(150, 255, 160) end
	return Color3.fromRGB(120, 255, 150) -- default eerie alien green
end

--======================================================================
-- spawnUFO(hoverPos, variant): build the gigantic saucer at the CLOUD
-- height directly above hoverPos. Stored anchored; descend() lowers it.
--======================================================================
function UFOEffects.spawnUFO(hoverPos, variant)
	local folder = ensureFolder()
	local glow = variantColor(variant)
	local D = CONFIG.UFO_DIAMETER

	-- Resting hover position (where it settles after descent).
	hoverBasePos = hoverPos
	-- Start way up in the clouds; descend() tweens to hoverBasePos.
	local startPos = hoverPos + Vector3.new(0, CONFIG.UFO_CLOUD_HEIGHT, 0)

	ufoModel = Instance.new("Model")
	ufoModel.Name = "Mothership"
	ufoModel.Parent = folder

	-- Variant-driven hull colour: a dark, cold chrome/gunmetal so the craft
	-- reads as menacing. Hostile gets an oxidised red-black, golden a warm
	-- brass tone; everything else is a cold dark grey.
	local hullColor
	if variant == "hostile" then
		hullColor = Color3.fromRGB(58, 22, 22)
	elseif variant == "golden" then
		hullColor = Color3.fromRGB(120, 95, 35)
	else
		hullColor = Color3.fromRGB(52, 56, 64)
	end
	-- A darker tone derived from the hull for seam/panel/trim detail.
	local trimColor = Color3.new(hullColor.R * 0.45, hullColor.G * 0.45, hullColor.B * 0.45)

	-- Local helper: spawn an anchored, weld-to-hull, non-colliding detail part.
	-- All parts are built in WORLD space relative to startPos; PivotTo later
	-- moves the whole anchored model rigidly, and the WeldConstraint is a
	-- belt-and-suspenders lock so the craft stays a single unit.
	local hull -- forward-declared so weldToHull can reference it
	local function weldToHull(part)
		local w = Instance.new("WeldConstraint")
		w.Part0 = hull
		w.Part1 = part
		w.Parent = part
		part.Parent = ufoModel
	end

	-- ====================================================================
	-- 1) MAIN HULL — wide flattened saucer disc. This is the PrimaryPart we
	--    move; every other part welds to it. Metallic / chrome gunmetal.
	-- ====================================================================
	hull = Instance.new("Part")
	hull.Name = "Hull"
	hull.Shape = Enum.PartType.Cylinder
	hull.Material = Enum.Material.Metal
	hull.Color = hullColor
	hull.Reflectance = 0.25                    -- chrome-ish sheen
	hull.Size = Vector3.new(D * 0.16, D, D)    -- length axis = thickness; flat disc
	hull.Anchored = true
	hull.CanCollide = false
	hull.CanQuery = false
	hull.CanTouch = false
	-- Lay the cylinder flat (its length axis vertical -> rotate 90 about Z).
	-- NOTE: this exact orientation (Angles(0,0,rad(90))) is the model pivot
	-- baseline that descend()/startHover()/chargeAndDepart() re-apply.
	hull.CFrame = CFrame.new(startPos) * CFrame.Angles(0, 0, math.rad(90))
	hull.Parent = ufoModel
	ufoPrimary = hull
	ufoModel.PrimaryPart = hull

	-- ---- Lower hull taper: a second, narrower disc beneath the main body to
	--      give the saucer a tapered "two stacked discs" silhouette. ----
	local lowerHull = Instance.new("Part")
	lowerHull.Name = "LowerHull"
	lowerHull.Shape = Enum.PartType.Cylinder
	lowerHull.Material = Enum.Material.DiamondPlate
	lowerHull.Color = trimColor
	lowerHull.Size = Vector3.new(D * 0.10, D * 0.62, D * 0.62)
	lowerHull.Anchored = true
	lowerHull.CanCollide = false
	lowerHull.CanQuery = false
	lowerHull.CanTouch = false
	lowerHull.CFrame = CFrame.new(startPos - Vector3.new(0, D * 0.10, 0)) * CFrame.Angles(0, 0, math.rad(90))
	weldToHull(lowerHull)

	-- ====================================================================
	-- 2) PANEL / SEAM detail — two thin darker rings around the hull edge
	--    plus a darker trim band, for a paneled, riveted look.
	-- ====================================================================
	for ringIdx = 1, 2 do
		local seam = Instance.new("Part")
		seam.Name = "SeamRing_" .. ringIdx
		seam.Shape = Enum.PartType.Cylinder
		seam.Material = Enum.Material.DiamondPlate
		seam.Color = trimColor
		-- Slightly proud of the hull so the darker band reads as a panel seam.
		local r = (ringIdx == 1) and 0.74 or 0.5
		seam.Size = Vector3.new(D * 0.175, D * r, D * r)
		seam.Anchored = true
		seam.CanCollide = false
		seam.CanQuery = false
		seam.CanTouch = false
		seam.CFrame = CFrame.new(startPos) * CFrame.Angles(0, 0, math.rad(90))
		weldToHull(seam)
	end

	-- ---- Rivet / grille trim ring: a dark metal band that wraps the rim. ----
	local rim = Instance.new("Part")
	rim.Name = "RimTrim"
	rim.Shape = Enum.PartType.Cylinder
	rim.Material = Enum.Material.Metal
	rim.Color = trimColor
	rim.Reflectance = 0.1
	rim.Size = Vector3.new(D * 0.20, D * 0.985, D * 0.985)
	rim.Anchored = true
	rim.CanCollide = false
	rim.CanQuery = false
	rim.CanTouch = false
	rim.CFrame = CFrame.new(startPos) * CFrame.Angles(0, 0, math.rad(90))
	weldToHull(rim)

	-- ====================================================================
	-- 3) CENTRAL DOME — translucent glowing cockpit on top (Glass + emissive
	--    tint). Variant-tinted via `glow`.
	-- ====================================================================
	local dome = Instance.new("Part")
	dome.Name = "Dome"
	dome.Shape = Enum.PartType.Ball
	dome.Material = Enum.Material.Glass
	dome.Color = glow
	dome.Transparency = 0.35
	dome.Reflectance = 0.15
	dome.Size = Vector3.new(D * 0.45, D * 0.45, D * 0.45)
	dome.Anchored = true
	dome.CanCollide = false
	dome.CanQuery = false
	dome.CanTouch = false
	dome.CFrame = CFrame.new(startPos + Vector3.new(0, D * 0.10, 0))
	weldToHull(dome)

	-- A small neon core inside the dome so the cockpit glows from within.
	local domeCore = Instance.new("Part")
	domeCore.Name = "DomeCore"
	domeCore.Shape = Enum.PartType.Ball
	domeCore.Material = Enum.Material.Neon
	domeCore.Color = glow
	domeCore.Transparency = 0.2
	domeCore.Size = Vector3.new(D * 0.22, D * 0.22, D * 0.22)
	domeCore.Anchored = true
	domeCore.CanCollide = false
	domeCore.CanQuery = false
	domeCore.CanTouch = false
	domeCore.CFrame = CFrame.new(startPos + Vector3.new(0, D * 0.10, 0))
	weldToHull(domeCore)

	-- ====================================================================
	-- 4) UNDERSIDE RING — the structural glowing ring around the lower rim.
	-- ====================================================================
	local underRing = Instance.new("Part")
	underRing.Name = "UndersideRing"
	underRing.Shape = Enum.PartType.Cylinder
	underRing.Material = Enum.Material.Neon
	underRing.Color = glow
	underRing.Size = Vector3.new(D * 0.05, D * 0.9, D * 0.9)
	underRing.Anchored = true
	underRing.CanCollide = false
	underRing.CanQuery = false
	underRing.CanTouch = false
	underRing.CFrame = CFrame.new(startPos - Vector3.new(0, D * 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	weldToHull(underRing)

	-- A big underside glow light (visible from the islands below).
	-- NOTE: chargeAndDepart() looks this up by name on the hull -- keep it here.
	local underLight = Instance.new("PointLight")
	underLight.Name = "UnderLight"
	underLight.Color = glow
	underLight.Brightness = 6
	underLight.Range = 60
	underLight.Parent = hull

	-- ====================================================================
	-- 5) UNDERSIDE RIM LIGHTS — a ring of bright neon spheres that PULSE in
	--    SEQUENCE (chase effect, driven by ONE Heartbeat; see below). They
	--    sit just below the rim so they read from the islands below.
	-- ====================================================================
	lightPulse = {}
	local lobes = 10
	for i = 1, lobes do
		local ang = math.rad((360 / lobes) * i)
		local lobe = Instance.new("Part")
		lobe.Name = "RimLight_" .. i
		lobe.Shape = Enum.PartType.Ball
		lobe.Material = Enum.Material.Neon
		lobe.Color = glow
		lobe.Size = Vector3.new(D * 0.06, D * 0.06, D * 0.06)
		lobe.Anchored = true
		lobe.CanCollide = false
		lobe.CanQuery = false
		lobe.CanTouch = false
		lobe.CFrame = CFrame.new(startPos - Vector3.new(0, D * 0.06, 0))
			* CFrame.Angles(0, ang, 0)
			* CFrame.new(D * 0.45, 0, 0)
		weldToHull(lobe)
		table.insert(lightPulse, lobe) -- tracked for the pulse loop
	end

	-- ====================================================================
	-- 6) THRUST / EXHAUST VENTS — a few darker recessed vents around the
	--    underside rim with a faint warm neon glow (engine exhaust).
	-- ====================================================================
	local vents = 4
	for i = 1, vents do
		local ang = math.rad((360 / vents) * i + 18) -- offset from the rim lights
		local vent = Instance.new("Part")
		vent.Name = "ThrustVent_" .. i
		vent.Shape = Enum.PartType.Cylinder
		vent.Material = Enum.Material.Neon
		-- Hostile vents glow red; otherwise a faint menacing orange ember.
		vent.Color = (variant == "hostile") and Color3.fromRGB(180, 40, 30) or Color3.fromRGB(120, 55, 20)
		vent.Size = Vector3.new(D * 0.04, D * 0.12, D * 0.12)
		vent.Anchored = true
		vent.CanCollide = false
		vent.CanQuery = false
		vent.CanTouch = false
		vent.CFrame = CFrame.new(startPos - Vector3.new(0, D * 0.09, 0))
			* CFrame.Angles(0, ang, 0)
			* CFrame.new(D * 0.30, 0, 0)
			* CFrame.Angles(0, 0, math.rad(90)) -- point the cylinder downward
		weldToHull(vent)
	end

	-- ====================================================================
	-- 7) ANTENNAE / SENSOR SPIRES — thin spires on top of the dome with tiny
	--    neon tips, for a menacing alien-tech silhouette.
	-- ====================================================================
	local spireDefs = {
		{ x = 0,          z = 0,          h = 0.40 }, -- central tall spire
		{ x = D * 0.10,   z = D * 0.06,   h = 0.26 },
		{ x = -D * 0.09,  z = -D * 0.07,  h = 0.24 },
	}
	for i, def in ipairs(spireDefs) do
		-- Thin metal spire.
		local spire = Instance.new("Part")
		spire.Name = "Spire_" .. i
		spire.Shape = Enum.PartType.Cylinder
		spire.Material = Enum.Material.Metal
		spire.Color = trimColor
		spire.Size = Vector3.new(D * def.h, D * 0.012, D * 0.012)
		spire.Anchored = true
		spire.CanCollide = false
		spire.CanQuery = false
		spire.CanTouch = false
		-- Stand the cylinder upright (length axis -> world Y) above the dome.
		spire.CFrame = CFrame.new(startPos + Vector3.new(def.x, D * 0.22 + D * def.h * 0.5, def.z))
			* CFrame.Angles(0, 0, math.rad(90))
		weldToHull(spire)

		-- Tiny glowing neon tip on top of the spire.
		local tip = Instance.new("Part")
		tip.Name = "SpireTip_" .. i
		tip.Shape = Enum.PartType.Ball
		tip.Material = Enum.Material.Neon
		tip.Color = glow
		tip.Size = Vector3.new(D * 0.03, D * 0.03, D * 0.03)
		tip.Anchored = true
		tip.CanCollide = false
		tip.CanQuery = false
		tip.CanTouch = false
		tip.CFrame = CFrame.new(startPos + Vector3.new(def.x, D * 0.22 + D * def.h, def.z))
		weldToHull(tip)
	end

	-- ====================================================================
	-- 8) EQUATORIAL ACCENT STRIP — a thin glowing band around the widest part
	--    of the hull, for a cold tech accent line.
	-- ====================================================================
	local accent = Instance.new("Part")
	accent.Name = "AccentStrip"
	accent.Shape = Enum.PartType.Cylinder
	accent.Material = Enum.Material.Neon
	accent.Color = glow
	accent.Transparency = 0.15
	accent.Size = Vector3.new(D * 0.07, D * 1.0, D * 1.0)
	accent.Anchored = true
	accent.CanCollide = false
	accent.CanQuery = false
	accent.CanTouch = false
	accent.CFrame = CFrame.new(startPos) * CFrame.Angles(0, 0, math.rad(90))
	weldToHull(accent)

	-- ---- Humming engine sound (positional, looping). ----
	local hum = Instance.new("Sound")
	hum.Name = "EngineHum"
	hum.SoundId = "rbxassetid://9112854440" -- low drone (looping)
	hum.Looped = true
	hum.Volume = 1   -- unified volume: matches the meteor intro sound
	hum.RollOffMaxDistance = 8000
	hum.Parent = hull
	hum:Play()

	-- ---- Green glowing fog/electricity around the hull (capped emitters). ----
	makeEmitter(hull, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 10,
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(1, 4),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(D * 0.4),
		Color = ColorSequence.new(glow),
		LightEmission = 0.5,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	makeEmitter(underRing, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = (variant == "broken") and CONFIG.MAX_PARTICLE_RATE or 12, -- broken sparks harder
		Lifetime = NumberRange.new(0.4, 1.0),
		Speed = NumberRange.new(4, 12),
		SpreadAngle = Vector2.new(120, 120),
		Size = NumberSequence.new(2),
		Color = ColorSequence.new((variant == "broken") and Color3.fromRGB(255, 240, 150) or glow),
		LightEmission = 1,
		Transparency = NumberSequence.new(0.1),
	})

	-- ---- Floating debris that will orbit the saucer once hovering. ----
	orbitParts = {}
	for i = 1, CONFIG.MAX_DEBRIS_ORBIT do
		local chunk = Instance.new("Part")
		chunk.Name = "OrbitDebris_" .. i
		chunk.Material = Enum.Material.Slate
		chunk.Color = Color3.fromRGB(60, 60, 70)
		local s = math.random(20, 45) / 10
		chunk.Size = Vector3.new(s, s * 0.7, s)
		chunk.Anchored = true
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.Parent = ufoModel
		table.insert(orbitParts, {
			part = chunk,
			radius = D * (0.6 + math.random() * 0.3),
			angle = math.random() * math.pi * 2,
			speed = (math.random() < 0.5 and 1 or -1) * (0.2 + math.random() * 0.4),
			y = (math.random() - 0.5) * D * 0.2,
		})
	end

	-- ---- SWARM variant: a flock of tiny fast UFOs around the mothership. ----
	if variant == "swarm" then
		for i = 1, CONFIG.MAX_SCOUTS do
			local mini = Instance.new("Part")
			mini.Name = "SwarmUFO_" .. i
			mini.Shape = Enum.PartType.Cylinder
			mini.Material = Enum.Material.Neon
			mini.Color = glow
			mini.Size = Vector3.new(3, 18, 18)
			mini.Anchored = true
			mini.CanCollide = false
			mini.CanQuery = false
			mini.CanTouch = false
			mini.Parent = ufoModel
			-- Reuse the orbit list with a tight radius + fast speed.
			table.insert(orbitParts, {
				part = mini,
				radius = D * (0.7 + math.random() * 0.5),
				angle = math.random() * math.pi * 2,
				speed = (math.random() < 0.5 and 1 or -1) * (1.5 + math.random()),
				y = (math.random() - 0.5) * D * 0.4,
				flat = true, -- keep saucer flat
			})
		end
	end

	-- ====================================================================
	-- UNDERSIDE-LIGHT PULSE: ONE tracked Heartbeat drives a "chase" around the
	-- rim. Each light's brightness/transparency follows a cosine wave whose
	-- phase is offset by its index, so the bright spot sweeps around the ring.
	-- A single connection updates every light each frame (no per-light conns),
	-- and cleanup() disconnects it. We start it fresh here.
	-- ====================================================================
	if pulseConn then pulseConn:Disconnect() pulseConn = nil end
	local pulseT0 = os.clock()
	local n = #lightPulse
	pulseConn = RunService.Heartbeat:Connect(function()
		if n == 0 then return end
		local t = os.clock() - pulseT0
		for i, lobe in ipairs(lightPulse) do
			if lobe and lobe.Parent then
				-- Phase offset around the ring -> a single bright spot chases
				-- around the rim at ~1 rev/sec.
				local phase = (t * math.pi * 2) - (i / n) * math.pi * 2
				-- 0..1 wave; sharpen so most lights stay dim and one peaks.
				local wave = (math.cos(phase) * 0.5 + 0.5) ^ 3
				lobe.Transparency = 0.75 - wave * 0.75 -- 0.75 (dim) -> 0 (bright)
			end
		end
	end)
end

--======================================================================
-- descend(duration): glide the whole saucer from the clouds down to its
-- resting hover position over `duration` seconds.
--======================================================================
function UFOEffects.descend(duration)
	if not ufoModel or not hoverBasePos then return end
	-- The saucer is built from independently-anchored parts, so we glide the
	-- WHOLE model with PivotTo each frame (NOT a single-part tween, which would
	-- leave the anchored dome/ring/lobes behind). Sine ease-out for a smooth
	-- settle. This runs on its own short Heartbeat that self-disconnects.
	local startCF = ufoModel:GetPivot()
	local goalPos = hoverBasePos
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not ufoModel or not ufoModel.Parent then
			if conn then conn:Disconnect() end
			return
		end
		local a = math.clamp((os.clock() - t0) / math.max(0.01, duration), 0, 1)
		-- Sine ease-out.
		local eased = math.sin(a * math.pi / 2)
		local pos = startCF.Position:Lerp(goalPos, eased)
		ufoModel:PivotTo(CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)))
		if a >= 1 then
			if conn then conn:Disconnect() conn = nil end
		end
	end)
end

--======================================================================
-- getUFOPosition(): the current world position of the saucer hull (used by
-- the beam module to aim beams downward from the UFO).
--======================================================================
function UFOEffects.getUFOPosition()
	if ufoPrimary and ufoPrimary.Parent then
		return ufoPrimary.Position
	end
	return hoverBasePos or Vector3.new(0, 1000, 0)
end

--======================================================================
-- startHover(): begin the bob + spin + orbiting-debris Heartbeat loop.
--======================================================================
function UFOEffects.startHover()
	if hovering or not ufoPrimary then return end
	hovering = true
	local t0 = os.clock()
	hoverConn = RunService.Heartbeat:Connect(function()
		if not ufoPrimary or not ufoPrimary.Parent then return end
		local t = os.clock() - t0
		-- Bob up/down + slow spin about the vertical axis.
		local bob = math.sin(t * CONFIG.UFO_BOB_SPEED * math.pi * 2) * CONFIG.UFO_BOB_AMPLITUDE
		local spin = math.rad(CONFIG.UFO_SPIN_SPEED) * t
		local base = hoverBasePos + Vector3.new(0, bob, 0)
		-- Saucer stays flat (rotate 90 about Z), spinning about world Y.
		ufoModel:PivotTo(CFrame.new(base) * CFrame.Angles(0, spin, 0) * CFrame.Angles(0, 0, math.rad(90)))

		-- Orbit the debris / swarm minis around the current saucer position.
		for _, o in ipairs(orbitParts) do
			if o.part and o.part.Parent then
				o.angle = o.angle + o.speed * 0.016
				local px = base.X + math.cos(o.angle) * o.radius
				local pz = base.Z + math.sin(o.angle) * o.radius
				local py = base.Y + o.y
				if o.flat then
					o.part.CFrame = CFrame.new(px, py, pz) * CFrame.Angles(0, 0, math.rad(90))
				else
					o.part.CFrame = CFrame.new(px, py, pz) * CFrame.Angles(o.angle, o.angle * 0.5, 0)
				end
			end
		end
	end)
end

--======================================================================
-- chargeAndDepart(duration): the ENDING. A bright energy glow builds under
-- the saucer, a massive flash fires (client handles per-player flash), then
-- the saucer rapidly accelerates straight up and vanishes.
--======================================================================
function UFOEffects.chargeAndDepart(duration)
	if not ufoPrimary then return end
	local underLight = ufoPrimary:FindFirstChild("UnderLight")

	-- Phase A: charge -- swell the underside glow + spawn a building energy ball.
	local charge = Instance.new("Part")
	charge.Name = "ChargeBall"
	charge.Shape = Enum.PartType.Ball
	charge.Material = Enum.Material.Neon
	charge.Color = Color3.fromRGB(220, 255, 230)
	charge.Size = Vector3.new(10, 10, 10)
	charge.Anchored = true
	charge.CanCollide = false
	charge.CanQuery = false
	charge.CanTouch = false
	charge.CFrame = CFrame.new(ufoPrimary.Position - Vector3.new(0, CONFIG.UFO_DIAMETER * 0.1, 0))
	charge.Parent = ensureFolder()
	TweenService:Create(charge,
		TweenInfo.new(duration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = Vector3.new(CONFIG.UFO_DIAMETER * 0.6, CONFIG.UFO_DIAMETER * 0.6, CONFIG.UFO_DIAMETER * 0.6) }):Play()
	if underLight then
		TweenService:Create(underLight, TweenInfo.new(duration * 0.6), { Brightness = 14, Range = 120 }):Play()
	end

	task.spawn(function()
		task.wait(duration * 0.6)

		-- Phase B: massive flash (clients flash their own screens) + pop charge.
		UFOSync:FireAllClients("flash")
		if charge and charge.Parent then
			TweenService:Create(charge,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(2, 2, 2), Transparency = 1 }):Play()
		end

		-- Phase C: rapid ascent + vanish. Stop the hover loop and shoot up.
		if hoverConn then hoverConn:Disconnect() hoverConn = nil end
		hovering = false
		local startCF = ufoModel and ufoModel:GetPivot()
		if startCF then
			local riseTime = math.max(0.5, duration * 0.4)
			local t0 = os.clock()
			local ascConn
			ascConn = RunService.Heartbeat:Connect(function()
				if not ufoModel or not ufoModel.Parent then
					if ascConn then ascConn:Disconnect() end
					return
				end
				local el = os.clock() - t0
				if el >= riseTime then
					if ascConn then ascConn:Disconnect() ascConn = nil end
					return
				end
				-- Accelerating ease: distance grows with el^2.
				local dist = CONFIG.UFO_ASCENT_SPEED * (el * el) / riseTime
				ufoModel:PivotTo(startCF + Vector3.new(0, dist, 0))
			end)
		end
	end)
end

--======================================================================
-- WARNING-phase visuals: flickering strange lights high in the sky +
-- electrical buzz + scout ships zooming past. Lives in its own folder so
-- stopWarning() can clear them before the mothership arrives.
--======================================================================
function UFOEffects.startWarning(hoverPos, targets, variant)
	if not warnFolder or not warnFolder.Parent then
		warnFolder = Instance.new("Folder")
		warnFolder.Name = "UFOEventWarn"
		warnFolder.Parent = ensureFolder()
	end
	local glow = variantColor(variant)

	-- A few flickering light orbs high above the band.
	local flickers = {}
	for i = 1, CONFIG.MAX_SCOUTS do
		local orb = Instance.new("Part")
		orb.Name = "Flicker_" .. i
		orb.Shape = Enum.PartType.Ball
		orb.Material = Enum.Material.Neon
		orb.Color = glow
		orb.Size = Vector3.new(8, 8, 8)
		orb.Transparency = 0.3
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanQuery = false
		orb.CanTouch = false
		orb.CFrame = CFrame.new(hoverPos + Vector3.new(
			(math.random() - 0.5) * 1200, math.random(200, 1200), (math.random() - 0.5) * 1200))
		local light = Instance.new("PointLight")
		light.Color = glow
		light.Brightness = 4
		light.Range = 40
		light.Parent = orb
		orb.Parent = warnFolder
		table.insert(flickers, orb)
	end

	-- Scout ships that drift/zoom across the sky.
	local scouts = {}
	for i = 1, CONFIG.MAX_SCOUTS do
		local scout = Instance.new("Part")
		scout.Name = "Scout_" .. i
		scout.Shape = Enum.PartType.Cylinder
		scout.Material = Enum.Material.Neon
		scout.Color = glow
		scout.Size = Vector3.new(4, 22, 22)
		scout.Anchored = true
		scout.CanCollide = false
		scout.CanQuery = false
		scout.CanTouch = false
		scout.Parent = warnFolder
		table.insert(scouts, {
			part = scout,
			origin = hoverPos + Vector3.new(0, math.random(300, 1400), 0),
			angle = math.random() * math.pi * 2,
			radius = math.random(600, 1500),
			speed = (math.random() < 0.5 and 1 or -1) * (0.6 + math.random()),
		})
	end

	-- Electrical buzz (positional) high in the sky.
	local buzz = Instance.new("Sound")
	buzz.Name = "Buzz"
	buzz.SoundId = "rbxassetid://9114402399"
	buzz.Looped = true
	buzz.Volume = 1   -- unified volume: matches the meteor intro sound
	buzz.RollOffMaxDistance = 6000
	local buzzAnchor = Instance.new("Part")
	buzzAnchor.Name = "BuzzAnchor"
	buzzAnchor.Size = Vector3.new(1, 1, 1)
	buzzAnchor.Transparency = 1
	buzzAnchor.Anchored = true
	buzzAnchor.CanCollide = false
	buzzAnchor.CanQuery = false
	buzzAnchor.CanTouch = false
	buzzAnchor.CFrame = CFrame.new(hoverPos)
	buzz.Parent = buzzAnchor
	buzzAnchor.Parent = warnFolder
	buzz:Play()

	-- Drive flicker + scout motion.
	local t0 = os.clock()
	warnConn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		for _, orb in ipairs(flickers) do
			if orb and orb.Parent then
				-- Flicker the transparency + light randomly.
				orb.Transparency = (math.random() < 0.2) and 0.9 or 0.25
				local l = orb:FindFirstChildOfClass("PointLight")
				if l then l.Enabled = math.random() > 0.15 end
			end
		end
		for _, s in ipairs(scouts) do
			if s.part and s.part.Parent then
				s.angle = s.angle + s.speed * 0.016
				local px = s.origin.X + math.cos(s.angle) * s.radius
				local pz = s.origin.Z + math.sin(s.angle) * s.radius
				-- Face the direction of travel, kept flat.
				s.part.CFrame = CFrame.new(px, s.origin.Y + math.sin(t + s.angle) * 60, pz)
					* CFrame.Angles(0, -s.angle, 0) * CFrame.Angles(0, 0, math.rad(90))
			end
		end
	end)
end

--------------------------------------------------------------------
-- stopWarning(): disconnect + destroy the WARNING-only visuals.
--------------------------------------------------------------------
function UFOEffects.stopWarning()
	if warnConn then warnConn:Disconnect() warnConn = nil end
	if warnFolder and warnFolder.Parent then warnFolder:Destroy() end
	warnFolder = nil
end

--======================================================================
-- cleanup(): disconnect every connection + destroy every instance. No leaks.
--======================================================================
function UFOEffects.cleanup()
	if hoverConn then hoverConn:Disconnect() hoverConn = nil end
	if warnConn then warnConn:Disconnect() warnConn = nil end
	if pulseConn then pulseConn:Disconnect() pulseConn = nil end
	hovering = false
	orbitParts = {}
	lightPulse = {}
	ufoModel = nil
	ufoPrimary = nil
	hoverBasePos = nil
	warnFolder = nil
	if effectsFolder and effectsFolder.Parent then
		effectsFolder:Destroy()
	end
	effectsFolder = nil
end

return UFOEffects
