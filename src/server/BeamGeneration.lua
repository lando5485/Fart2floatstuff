--======================================================================
-- BeamGeneration.lua  (ModuleScript)
--======================================================================
-- Creates / animates / destroys the actual rainbow BEAM PARTS for the
-- "RAINBOW BEAMS" hazard. SERVER-AUTHORITATIVE: the parts are made on the
-- server, so they replicate to every client automatically (everyone sees
-- the same beams).
--
-- A beam is a long, thin, glowing Neon part that spans HORIZONTALLY ACROSS
-- the climb corridor (from one side of the gap to the other) at a given
-- HEIGHT and ANGLE. It animates in three phases:
--     EXTEND  -- grows out from one side across the corridor (quick tween)
--     HOLD    -- stays fully extended for BEAM_DURATION
--     RETRACT -- shrinks/fades back before the next cycle
--
-- It hands the active beams' geometry (the two endpoints + center) to the
-- collision module each tick via getActiveDescriptors(). It enforces the
-- MAX_BEAMS hard cap and cleans up every part, attachment, light, emitter
-- and tween (no leaks).
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
-- spawnBeam(descriptor): build ONE beam part for the given
-- { height, angle, side } descriptor. Returns a beam record (or nil if the
-- MAX_BEAMS cap is hit). The record exposes the geometry the collision
-- module needs (p0, p1 endpoints + center).
--
-- GEOMETRY: the beam spans the full CORRIDOR_WIDTH across the corridor,
-- centred on CORRIDOR_CENTER (X/Z), at the descriptor's HEIGHT. "side"
-- decides which end it grows out FROM during EXTEND. "angle" tilts it a
-- little off flat-across (rotation about the corridor's forward axis).
--------------------------------------------------------------------
function BeamGeneration.spawnBeam(descriptor)
	-- Respect the hard simultaneous cap (perf / mobile).
	if #activeBeams >= (CONFIG.MAX_BEAMS or 6) then
		return nil
	end

	local center = CONFIG.CORRIDOR_CENTER or Vector3.new(0, 0, 0)
	local width = CONFIG.CORRIDOR_WIDTH or 300
	local height = descriptor.height
	local angle = descriptor.angle or 0

	-- The beam crosses along the corridor's X axis by default. We tilt it by
	-- "angle" about the Z axis (so it slopes up/down across the gap).
	local centerPos = Vector3.new(center.X, height, center.Z)
	local orientation = CFrame.Angles(0, 0, angle)
	local fullCF = CFrame.new(centerPos) * orientation

	-- Compute the two endpoints (used by collision). Long axis is local X.
	local half = width / 2
	local p0 = (fullCF * CFrame.new(-half, 0, 0)).Position
	local p1 = (fullCF * CFrame.new(half, 0, 0)).Position

	-- Build the part. It starts THIN (length ~0) at the growth side and
	-- tweens out to the full width during EXTEND.
	local part = Instance.new("Part")
	part.Name = "RainbowBeam"
	part.Anchored = true
	part.CanCollide = false          -- purely cosmetic; collision is server math
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = Vector3.new(0.5, 1.6, 1.6)   -- starts tiny (length on X)
	BeamEffects.applyRainbowGradient(part)

	-- Decorate: rainbow Beam gradient along the length + glow + light streak.
	local rainbowBeam = BeamEffects.addRainbowBeam(part, width)
	local light = BeamEffects.addGlow(part)
	local emitter = BeamEffects.addLightStreakParticles(part, width)

	-- Position the part so its growth STARTS at the chosen side. We anchor
	-- the part center where it will END (fullCF center) but begin collapsed
	-- toward the side, then tween Size + CFrame to the centered full beam.
	local growSign = (descriptor.side == "left") and -1 or 1
	local startCenter = fullCF * CFrame.new(growSign * half, 0, 0)  -- collapsed at the side
	part.CFrame = startCenter
	part.Parent = ensureFolder()

	-- The beam record. activeFull flags whether it currently spans the gap
	-- (collision only counts a beam while it is at/near full extension).
	local record = {
		part = part,
		beam = rainbowBeam,
		light = light,
		emitter = emitter,
		p0 = p0,
		p1 = p1,
		center = centerPos,
		activeFull = false,
		tweens = {},
	}
	table.insert(activeBeams, record)

	-- ---- EXTEND: grow from the side across to full width + recentre ----
	local extendTime = CONFIG.BEAM_EXTEND_TIME or 0.35
	local tIn = TweenService:Create(part,
		TweenInfo.new(extendTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(width, 1.6, 1.6), CFrame = fullCF })
	table.insert(record.tweens, tIn)
	tIn.Completed:Connect(function()
		-- Once fully extended, it becomes a live collision line.
		record.activeFull = true
	end)
	tIn:Play()

	return record
end

--------------------------------------------------------------------
-- retractBeam(record): shrink + fade a single beam back to its growth side,
-- then destroy it and remove it from the active list. Idempotent-safe.
--------------------------------------------------------------------
function BeamGeneration.retractBeam(record)
	if not record or record.retracting then return end
	record.retracting = true
	record.activeFull = false          -- stops counting for collisions immediately

	BeamEffects.fadeOut(record.beam, record.light, record.emitter)

	local part = record.part
	local retractTime = CONFIG.BEAM_RETRACT_TIME or 0.3

	local function destroyNow()
		for i = #activeBeams, 1, -1 do
			if activeBeams[i] == record then table.remove(activeBeams, i) end
		end
		if part and part.Parent then part:Destroy() end
	end

	if part and part.Parent then
		local tOut = TweenService:Create(part,
			TweenInfo.new(retractTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = Vector3.new(0.5, 1.6, 1.6), Transparency = 1 })
		table.insert(record.tweens, tOut)
		tOut.Completed:Connect(destroyNow)
		tOut:Play()
		-- Backup destroy in case the tween is interrupted (no leak).
		Debris:AddItem(part, retractTime + 1)
	else
		destroyNow()
	end
end

--------------------------------------------------------------------
-- getActiveDescriptors(): the geometry of beams currently spanning the gap
-- (only those past their EXTEND, i.e. activeFull). Returned for collision.
-- Each entry: { p0 = Vector3, p1 = Vector3 }.
--------------------------------------------------------------------
function BeamGeneration.getActiveDescriptors()
	local out = {}
	for _, rec in ipairs(activeBeams) do
		if rec.activeFull and not rec.retracting then
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
