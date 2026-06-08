--======================================================================
-- BeamGeneration.lua  (ModuleScript)
--======================================================================
-- Creates / animates / destroys the actual rainbow BEAM PARTS for the
-- "RAINBOW BEAMS" hazard. SERVER-AUTHORITATIVE: the parts are made on the
-- server, so they replicate to every client automatically (everyone sees
-- the same beams).
--
-- A beam is a long, thin, glowing Neon part that lies FLAT/HORIZONTAL across
-- the climb corridor at a given HEIGHT, pivoting about its own HUB. It is
-- PERSISTENT (no on/off flicker): once spawned it stays and SPINS continuously
-- in the horizontal plane (like a helicopter blade) until cleanup. update(dt)
-- advances every beam's angle by its own spin speed/direction and rewrites its
-- CFrame + endpoints; the line sweeping past any spot is what creates the
-- timed openings a player threads through.
--
-- It hands the live beams' geometry (the two endpoints) to the collision
-- module each tick via getActiveDescriptors(). It enforces the MAX_BEAMS hard
-- cap and cleans up every part, attachment, light, emitter (no leaks).
--
-- Touches NO gameplay -- it only makes/destroys cosmetic, CanCollide=false
-- parts and reports their lines. All decoration comes from BeamEffects.
--======================================================================

local BeamGeneration = {}

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Wired by init().
local CONFIG = nil
local BeamEffects = nil

-- State.
local beamFolder = nil   -- Workspace folder holding all live beam parts
local activeBeams = {}    -- list of live beam records (see below)

--------------------------------------------------------------------
-- init(config, effects): wire shared dependencies (CONFIG owned by manager).
--------------------------------------------------------------------
function BeamGeneration.init(config, effects)
	CONFIG = config
	BeamEffects = effects
end

--------------------------------------------------------------------
-- ensureFolder(): make sure we have a fresh Workspace folder to parent
-- beam parts into (so cleanup is a single Destroy).
--------------------------------------------------------------------
local function ensureFolder()
	if not beamFolder or not beamFolder.Parent then
		beamFolder = Instance.new("Folder")
		beamFolder.Name = "RainbowBeamParts"
		beamFolder.Parent = workspace
	end
	return beamFolder
end

--------------------------------------------------------------------
-- spawnBeam(descriptor): build ONE PERSISTENT SPINNING beam for the given
-- { height, offsetX, offsetZ, spinSpeed, angle, colorPhase } descriptor.
-- Returns a beam record (or nil if the MAX_BEAMS cap is hit). The record
-- exposes the geometry the collision module needs (p0, p1 endpoints) and the
-- spin state update(dt) advances.
--
-- GEOMETRY: the beam is a flat line of length CORRIDOR_WIDTH lying in the
-- horizontal plane at the descriptor's HEIGHT, pivoting about its HUB
-- (CORRIDOR_CENTER + the descriptor's X/Z offset). It appears at full length
-- immediately and then spins (rotation about the vertical Y axis) -- no
-- extend/flicker. "spinSpeed" is signed (its sign = spin direction).
--------------------------------------------------------------------
function BeamGeneration.spawnBeam(descriptor)
	-- Respect the hard simultaneous cap (perf / mobile).
	if #activeBeams >= (CONFIG.MAX_BEAMS or 6) then
		return nil
	end

	local center = CONFIG.CORRIDOR_CENTER or Vector3.new(0, 0, 0)
	local width = CONFIG.CORRIDOR_WIDTH or 300
	local height = descriptor.height
	local half = width / 2

	-- The hub (spin pivot): corridor centre nudged by the descriptor's offset,
	-- at this beam's height.
	local hub = Vector3.new(center.X + (descriptor.offsetX or 0), height, center.Z + (descriptor.offsetZ or 0))

	-- Initial flat orientation: rotate about Y by the start angle so the line
	-- lies in the horizontal plane (long axis = local X).
	local angle = descriptor.angle or 0
	local cf = CFrame.new(hub) * CFrame.Angles(0, angle, 0)

	-- Build the part at FULL length immediately (persistent -- no extend tween).
	local part = Instance.new("Part")
	part.Name = "RainbowBeam"
	part.Anchored = true
	part.CanCollide = false          -- purely cosmetic; collision is server math
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = Vector3.new(width, 1.6, 1.6)   -- full length on local X
	BeamEffects.applyBeamColor(part, descriptor.colorPhase)   -- vivid per-beam spectrum hue (not white)

	-- Decorate: rainbow Beam gradient along the length + glow + light streak.
	local rainbowBeam = BeamEffects.addRainbowBeam(part, width)
	local light = BeamEffects.addGlow(part, descriptor.colorPhase)   -- glow tinted to this beam's hue
	local emitter = BeamEffects.addLightStreakParticles(part, width)

	part.CFrame = cf
	part.Parent = ensureFolder()

	-- The beam record: geometry (p0/p1) + spin state for update(dt).
	local record = {
		part = part,
		beam = rainbowBeam,
		light = light,
		emitter = emitter,
		hub = hub,
		half = half,
		angle = angle,
		spinSpeed = descriptor.spinSpeed or 1,   -- signed rad/s (sign = direction)
		p0 = (cf * CFrame.new(-half, 0, 0)).Position,
		p1 = (cf * CFrame.new(half, 0, 0)).Position,
		tweens = {},
	}
	table.insert(activeBeams, record)

	return record
end

--------------------------------------------------------------------
-- update(dt): advance EVERY live beam's spin by its own speed/direction and
-- rewrite its CFrame + endpoints. Called every frame by the manager while a
-- player occupies the band. This is what makes the blades spin continuously
-- and keeps the collision line in sync with what the player sees.
--------------------------------------------------------------------
local TWO_PI = math.pi * 2
function BeamGeneration.update(dt)
	for _, rec in ipairs(activeBeams) do
		if rec.part and rec.part.Parent and not rec.retracting then
			-- Advance the spin (wrap to keep the angle bounded over long sessions).
			rec.angle = (rec.angle + rec.spinSpeed * dt) % TWO_PI
			local cf = CFrame.new(rec.hub) * CFrame.Angles(0, rec.angle, 0)
			rec.part.CFrame = cf
			rec.p0 = (cf * CFrame.new(-rec.half, 0, 0)).Position
			rec.p1 = (cf * CFrame.new(rec.half, 0, 0)).Position
		end
	end
end

--------------------------------------------------------------------
-- getActiveDescriptors(): the geometry of every live spinning beam, for
-- collision. Each entry: { p0 = Vector3, p1 = Vector3 } -- the current (this
-- frame's) endpoints, kept fresh by update(dt).
--------------------------------------------------------------------
function BeamGeneration.getActiveDescriptors()
	local out = {}
	for _, rec in ipairs(activeBeams) do
		if rec.part and rec.part.Parent and not rec.retracting then
			table.insert(out, { p0 = rec.p0, p1 = rec.p1 })
		end
	end
	return out
end

--------------------------------------------------------------------
-- count(): number of live beam records (used to respect MAX_BEAMS upstream).
--------------------------------------------------------------------
function BeamGeneration.count()
	return #activeBeams
end

--------------------------------------------------------------------
-- cleanup(): destroy EVERY beam part + the folder, cancel pending tweens,
-- clear state. Called on band-empty and on shutdown -- guarantees no leaks.
--------------------------------------------------------------------
function BeamGeneration.cleanup()
	for _, rec in ipairs(activeBeams) do
		for _, tw in ipairs(rec.tweens) do
			pcall(function() tw:Cancel() end)
		end
		if rec.part and rec.part.Parent then
			pcall(function() rec.part:Destroy() end)
		end
	end
	activeBeams = {}
	if beamFolder and beamFolder.Parent then
		pcall(function() beamFolder:Destroy() end)
	end
	beamFolder = nil
end

return BeamGeneration
