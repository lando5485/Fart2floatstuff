--======================================================================
-- BeamEffects.lua  (ModuleScript)
--======================================================================
-- Shared VFX helpers for the "RAINBOW BEAMS" aerial hazard.
--
-- This module is PURE PRESENTATION. It builds the rainbow look that the
-- beam parts wear: the rainbow ColorSequence/gradient, the glow
-- (PointLight + Neon), and the compressed-light particle emitters that
-- give each beam its "streak of compressed light" feel. It also offers a
-- tiny ambient corridor shimmer helper.
--
-- It owns NO state and touches NO gameplay. BeamGeneration calls these to
-- decorate the parts it creates. Every emitter Rate is capped at
-- CONFIG.MAX_PARTICLE_RATE so the look stays cheap on mobile.
--======================================================================

local BeamEffects = {}

-- Wired by init() so we can honour the shared particle-rate cap.
local CONFIG = nil

--------------------------------------------------------------------
-- init(config): wire the shared CONFIG (owned by the manager).
--------------------------------------------------------------------
function BeamEffects.init(config)
	CONFIG = config
end

-- clampRate(): never let an emitter exceed the configured hard cap.
local function clampRate(rate)
	local cap = (CONFIG and CONFIG.MAX_PARTICLE_RATE) or 24
	return math.min(rate, cap)
end

--------------------------------------------------------------------
-- rainbowColorSequence(): a full-spectrum ColorSequence (red -> violet)
-- reused for the beam surface gradient, the trail, and the particles so
-- the whole beam reads as one rainbow streak.
--------------------------------------------------------------------
function BeamEffects.rainbowColorSequence()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 40, 40)),   -- red
		ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 150, 40)),  -- orange
		ColorSequenceKeypoint.new(0.34, Color3.fromRGB(255, 240, 40)),  -- yellow
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(60, 230, 90)),   -- green
		ColorSequenceKeypoint.new(0.67, Color3.fromRGB(60, 150, 255)),  -- blue
		ColorSequenceKeypoint.new(0.84, Color3.fromRGB(140, 80, 255)),  -- indigo
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(230, 80, 255)),  -- violet
	})
end

--------------------------------------------------------------------
-- hueColor(phase): a single VIVID, fully-saturated spectrum colour for a
-- phase in [0,1) -- 0=red, ~.1=orange, ~.17=yellow, ~.33=green, ~.6=blue,
-- ~.8=violet. Used to colour each beam a different rainbow hue so a burst of
-- beams spans the whole spectrum (red/orange/yellow/green/blue/purple).
--------------------------------------------------------------------
function BeamEffects.hueColor(phase)
	return Color3.fromHSV((phase or 0) % 1, 1, 1)
end

--------------------------------------------------------------------
-- applyBeamColor(part, phase): paint a beam part its own VIVID spectrum hue
-- (replaces the old flat Neon white that made beams read as plain white
-- lines). Each beam picks a different hue from `phase`, so across a flashing
-- burst the beams are red, orange, yellow, green, blue and violet. The full
-- rainbow Beam streak + rainbow sparks (below) layer on top, so every single
-- beam still reads as a multi-coloured rainbow streak, not one solid bar.
--------------------------------------------------------------------
function BeamEffects.applyBeamColor(part, phase)
	part.Material = Enum.Material.Neon
	part.Color = BeamEffects.hueColor(phase or 0)
end

--------------------------------------------------------------------
-- addRainbowBeam(part, length): attach a Roblox Beam running the length of
-- the streak so the actual RAINBOW gradient shows along the part. Two
-- Attachments are placed at the part's two ends (part's long axis is X).
-- Returns the Beam (so callers can fade it on retract).
--------------------------------------------------------------------
function BeamEffects.addRainbowBeam(part, length)
	local a0 = Instance.new("Attachment")
	a0.Name = "BeamEnd0"
	a0.Position = Vector3.new(-length / 2, 0, 0)
	a0.Parent = part

	local a1 = Instance.new("Attachment")
	a1.Name = "BeamEnd1"
	a1.Position = Vector3.new(length / 2, 0, 0)
	a1.Parent = part

	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = BeamEffects.rainbowColorSequence()
	beam.LightEmission = 1            -- full bloom: "compressed light"
	beam.LightInfluence = 0           -- ignore world lighting; always vivid
	beam.FaceCamera = true            -- always presents broadside to the viewer
	beam.Width0 = 3.2                 -- chunkier, more vivid rainbow streak (was 2.2)
	beam.Width1 = 3.2
	beam.Texture = ""                 -- solid gradient (no scrolling texture)
	beam.Transparency = NumberSequence.new(0)
	beam.Segments = 1
	beam.Parent = part
	return beam
end

--------------------------------------------------------------------
-- addGlow(part): a PointLight so each beam casts coloured light into the
-- corridor. Intensity is modest; one light per beam (capped by MAX_BEAMS).
-- Returns the light.
--------------------------------------------------------------------
function BeamEffects.addGlow(part, phase)
	local light = Instance.new("PointLight")
	light.Color = phase and BeamEffects.hueColor(phase) or Color3.fromRGB(255, 120, 255)  -- glow matches the beam's own hue
	light.Brightness = 3
	light.Range = 28
	light.Shadows = false
	light.Parent = part
	return light
end

--------------------------------------------------------------------
-- addLightStreakParticles(part, length): the "compressed light" feel --
-- small fast bright sparks running ALONG the beam. Rate is capped.
-- Returns the emitter so it can be disabled on retract.
--------------------------------------------------------------------
function BeamEffects.addLightStreakParticles(part, length)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = BeamEffects.rainbowColorSequence()
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rate = clampRate(26)
	emitter.Lifetime = NumberRange.new(0.15, 0.35)
	emitter.Speed = NumberRange.new(0, 2)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Emit across the whole length of the streak (X is the long axis).
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = part
	return emitter
end

--------------------------------------------------------------------
-- fadeOut(beam, light, emitter): on retract, kill the light + stop new
-- particles so nothing lingers after the part shrinks/destroys.
--------------------------------------------------------------------
function BeamEffects.fadeOut(beam, light, emitter)
	if emitter then emitter.Enabled = false end
	if light then light.Brightness = 0 end
	if beam then beam.Transparency = NumberSequence.new(1) end
end

return BeamEffects
