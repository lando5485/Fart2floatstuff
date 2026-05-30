--======================================================================
-- RocketLogic.lua  (ModuleScript)
--======================================================================
-- Builds the rocket gradually (one welded Model with a PrimaryPart) and
-- handles the launch movement: slow vertical lift, then accelerate +
-- tilt toward island 14, fly across the sky, and signal on arrival.
--
-- The rocket is ONE Model, welded together, moved with TweenService /
-- model:PivotTo along a smooth path. NEVER teleported.
--
-- SAFETY: every part is CanCollide=false and Massless so the rocket can
-- never block, trap or knock a player on island 1. The model is moved by
-- tweening its PrimaryPart's CFrame and pivoting (no physics on players).
--======================================================================

local RocketLogic = {}

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

--======================================================================
-- ROCKET_SIZE: ONE-NUMBER UNIFORM SCALE for the whole rocket.
-- Every part Size and every weld-offset TRANSLATION below is multiplied
-- by this value at creation time (via the local `S`), so each stage part
-- still pops into its correct FINAL flush position as it builds (we never
-- scale the finished model, which would cause a pop). Change this single
-- number to grow/shrink the entire rocket uniformly.
--======================================================================
local ROCKET_SIZE = 1.6

-- Module state.
local rocketModel = nil   -- the Model instance
local primaryPart = nil   -- PrimaryPart we tween/pivot
local sitePos = nil       -- ground Vector3 where it was built
local stageIndex = 0      -- how many stages added so far
local stageParts = {}     -- parts grouped by stage for ordered reveal

-- The 5 build stages, in order.
local STAGE_ORDER = { "base", "body", "windows", "fins", "cone" }

--======================================================================
-- GEOMETRY REFERENCE (UNSCALED, in body-local studs; multiply by S):
--   The PrimaryPart (RocketCore) is the origin. Body-local y = 0 is the
--   vertical CENTER of the main body tube.
--     * Main body: diameter 10, height 40  -> spans y -20 .. +20.
--     * Shoulder dome: caps the body top at y +20, reaching up to ~ +25.
--     * Nose cone: stacked shrinking cylinders from y +25 up to the tip.
--     * Engine nozzle bell: hangs below the body bottom, y -20 .. ~ -27.
--     * Flame: glows downward from the nozzle mouth (y ~ -27 and below).
--     * Fins: hug the lower body and sweep down to tips BELOW the nozzle.
--   The LOWEST geometry is the fin tips at body-local y ~ -30. beginBuild
--   lifts the core so that point rests on the ground (see beginBuild).
--======================================================================
-- Shared color/material palette (toy-rocket cartoon look).
local C_WHITE  = Color3.fromRGB(245, 245, 248)   -- body + shoulder (pure white)
local C_RED    = Color3.fromRGB(205, 45, 45)     -- cone, band, fins, frames
local C_GLASS  = Color3.fromRGB(20, 35, 80)      -- dark blue glossy window glass
local C_NOZZLE = Color3.fromRGB(120, 95, 60)     -- tan / dark metallic nozzle
local C_RIVET  = Color3.fromRGB(70, 72, 80)      -- dark grey rivet dots
local C_FLAME  = Color3.fromRGB(255, 170, 60)    -- glowing yellow-orange flame

--------------------------------------------------------------------
-- Helper: create a CanCollide=false, Massless part welded to primary.
--------------------------------------------------------------------
local function makePart(name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color or Color3.fromRGB(220, 220, 220)
	p.Material = material or Enum.Material.Metal
	p.Anchored = false       -- welded to primary instead of anchored
	p.CanCollide = false     -- CRITICAL: never collides with players
	p.Massless = true        -- no physics influence
	p.CanTouch = false
	p.CanQuery = false
	return p
end

--------------------------------------------------------------------
-- Helper: weld a part to the PrimaryPart and parent it into the model.
-- `offset` is a CFrame offset relative to the primary part.
--------------------------------------------------------------------
local function weldToPrimary(part, offset)
	part.CFrame = primaryPart.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = primaryPart
	weld.Part1 = part
	weld.Parent = part
	part.Parent = rocketModel
end

--======================================================================
-- beginBuild(site): create the empty model + PrimaryPart at the ground.
-- The PrimaryPart is the invisible structural anchor at the rocket base.
-- Stages are added later via addNextStage().
--======================================================================
function RocketLogic.beginBuild(site)
	sitePos = site
	stageIndex = 0
	stageParts = {}

	rocketModel = Instance.new("Model")
	rocketModel.Name = "EventRocket"
	-- STREAMING FIX (Workspace.StreamingEnabled is ON): mark the rocket build Persistent so it + ALL its
	-- descendants replicate to EVERY client regardless of distance (players far from island 1 otherwise
	-- never receive it). Set BEFORE any parts are added so every stage part is in the persistent set.
	rocketModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	-- PrimaryPart: invisible anchor at the rocket's vertical centre-base.
	primaryPart = Instance.new("Part")
	primaryPart.Name = "RocketCore"
	primaryPart.Size = Vector3.new(2, 2, 2)
	primaryPart.Transparency = 1
	primaryPart.Anchored = true        -- we drive it via tween/pivot
	primaryPart.CanCollide = false
	primaryPart.Massless = true
	primaryPart.CanTouch = false
	primaryPart.CanQuery = false
	-- Lift the core so the LOWEST geometry (fin tips, body-local y ~ -30)
	-- rests on the ground at the site, AT ANY ROCKET_SIZE. The fin tips sit
	-- at -30 * S below the core, so place the core that high above site.Y.
	primaryPart.CFrame = CFrame.new(site + Vector3.new(0, 30 * ROCKET_SIZE, 0))
	primaryPart.Parent = rocketModel

	rocketModel.PrimaryPart = primaryPart
	rocketModel.Parent = workspace

	return rocketModel
end

--------------------------------------------------------------------
-- Helper: a small dark-grey RIVET DOT (tiny sphere) welded to primary.
-- `size` and `offset` are passed already-scaled by the caller. Returns
-- the part so the builder can add it to its returned parts array.
--------------------------------------------------------------------
local function makeRivet(name, sizeStud, offset)
	local r = makePart(name, Vector3.new(sizeStud, sizeStud, sizeStud), C_RIVET, Enum.Material.Metal)
	r.Shape = Enum.PartType.Ball
	weldToPrimary(r, offset)
	return r
end

--------------------------------------------------------------------
-- Per-stage builders. Each returns the parts it created (parented+welded).
-- Geometry is built bottom->top within the rocket but in STAGE_ORDER for
-- the reveal: base(engine) -> body -> windows -> fins -> cone.
-- EVERY Size and EVERY weld-offset TRANSLATION is multiplied by S
-- (= ROCKET_SIZE) so the rocket scales uniformly from one number while
-- each part still lands in its correct FINAL flush spot as it pops in.
--------------------------------------------------------------------
local STAGE_BUILDERS = {
	-- ============================================================
	-- 1) BASE STAGE = ENGINE.
	--    A short flared nozzle/bell at the very bottom center (tan/dark
	--    metallic) with a glowing yellow-orange flame pointing DOWN
	--    (Neon glow cone + capped ParticleEmitter). Tucked at bottom
	--    center where the fins will surround it. Flush to the body bottom.
	--    Body bottom is body-local y = -20; nozzle top meets it flush.
	-- ============================================================
	base = function()
		local S = ROCKET_SIZE
		local parts = {}

		-- NOZZLE BELL: stacked shrinking-then-flaring cylinders forming a
		-- classic flared bell. Top ring is full body-ish width and meets the
		-- body bottom (y -20) flush; it narrows to a throat then flares out.
		-- Each ring is 2 studs tall; tops are placed so rings touch flush.
		-- ring profile (radius, center-y): widest at the flared mouth bottom.
		local bell = {
			{ d = 8.0, y = -21 },   -- top of bell, tucks just under body bottom (-20)
			{ d = 6.4, y = -23 },   -- narrowing throat
			{ d = 7.2, y = -25 },   -- starting to flare back out
			{ d = 9.0, y = -27 },   -- wide flared mouth (lowest engine ring)
		}
		for i, seg in ipairs(bell) do
			local n = makePart("RocketNozzle_" .. i, Vector3.new(2 * S, seg.d * S, seg.d * S),
				C_NOZZLE, Enum.Material.Metal)
			n.Shape = Enum.PartType.Cylinder -- length axis is X -> rotate upright
			weldToPrimary(n, CFrame.new(0, seg.y * S, 0) * CFrame.Angles(0, 0, math.rad(90)))
			table.insert(parts, n)
		end

		-- FLAME GLOW CONE: a downward-pointing Neon glow built as a couple of
		-- shrinking cylinders hanging out of the nozzle mouth (y < -27).
		local flameSegs = {
			{ d = 6.5, y = -29 },
			{ d = 4.2, y = -31 },
			{ d = 2.0, y = -33 }, -- tapering flame tip
		}
		local flameTop -- remember a flame part to host the ParticleEmitter
		for i, seg in ipairs(flameSegs) do
			local f = makePart("RocketFlame_" .. i, Vector3.new(2 * S, seg.d * S, seg.d * S),
				C_FLAME, Enum.Material.Neon)
			f.Shape = Enum.PartType.Cylinder
			f.Transparency = 0.15
			weldToPrimary(f, CFrame.new(0, seg.y * S, 0) * CFrame.Angles(0, 0, math.rad(90)))
			table.insert(parts, f)
			if i == 1 then flameTop = f end
		end

		-- ParticleEmitter for exhaust, on a welded flame part (cleaned with
		-- the model). Rate is CAPPED low per spec. Emits downward (-Y) since
		-- the part normal we bias acceleration along world down.
		if flameTop then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "RocketExhaust"
			emitter.Color = ColorSequence.new(
				Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 40))
			emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
			emitter.Rate = 24                       -- capped (<= 25)
			emitter.Lifetime = NumberRange.new(0.3, 0.6)
			emitter.Speed = NumberRange.new(6, 12)
			emitter.SpreadAngle = Vector2.new(12, 12)
			emitter.Acceleration = Vector3.new(0, -20, 0) -- shoot downward
			emitter.LightEmission = 0.8
			emitter.Size = NumberSequence.new(2.5 * S, 0.2)
			emitter.Parent = flameTop
		end

		return parts
	end,

	-- ============================================================
	-- 2) BODY STAGE = MAIN BODY + SHOULDER + RIVET SEAMS + RED BAND.
	--    Main body: ONE tall WHITE cylinder (diameter 10, height 40, ~4x
	--    taller than wide), spanning body-local y -20..+20. Upper shoulder
	--    domes inward toward the nose. Rivet seam rings + a raised RED band.
	-- ============================================================
	body = function()
		local S = ROCKET_SIZE
		local parts = {}

		-- MAIN BODY: one tall solid WHITE tube. Center y = 0, height 40.
		local body = makePart("RocketBody", Vector3.new(40 * S, 10 * S, 10 * S),
			C_WHITE, Enum.Material.SmoothPlastic)
		body.Shape = Enum.PartType.Cylinder -- X is length axis -> rotate upright
		weldToPrimary(body, CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)))
		table.insert(parts, body)

		-- UPPER SHOULDER: a half-sphere (ball) of the SAME 10-stud top diameter
		-- centered at the body top (y +20) so it rounds the wide-body->nose
		-- transition smoothly. WHITE. (Ball reads as a rounded dome on the top.)
		local shoulder = makePart("RocketShoulder", Vector3.new(10 * S, 10 * S, 10 * S),
			C_WHITE, Enum.Material.SmoothPlastic)
		shoulder.Shape = Enum.PartType.Ball
		weldToPrimary(shoulder, CFrame.new(0, 20 * S, 0)) -- bottom half overlaps body top flush
		table.insert(parts, shoulder)

		-- RIVET SEAM RINGS: 3 rings of evenly-spaced dark-grey dots wrapping
		-- the body. Rings at y = -10 (lower), +12 (under the band, lower
		-- border) and +16 (upper border of the band, just under the nose).
		-- Dots sit on the 10-stud body surface (radius 5), flush.
		local seamHeights = { -10, 12, 16 }
		local DOTS = 10 -- modest count per ring
		for ringIdx, hy in ipairs(seamHeights) do
			for d = 0, DOTS - 1 do
				local a = math.rad(d * (360 / DOTS))
				-- Place each dot on the body surface (radius 5) at this height.
				local off = CFrame.Angles(0, a, 0) * CFrame.new(5 * S, hy * S, 0)
				table.insert(parts,
					makeRivet("RocketSeamRivet_" .. ringIdx .. "_" .. d, 0.45 * S, off))
			end
		end

		-- RED ACCENT BAND: a raised RED ring wrapping the upper body, flush to
		-- the surface (slightly larger diameter than the body so it reads as a
		-- raised stripe, not floating). Sits between the two upper rivet rings
		-- (y 12 & 16) -> center y = 14, height ~3.
		local band = makePart("RocketRedBand", Vector3.new(3 * S, 10.5 * S, 10.5 * S),
			C_RED, Enum.Material.SmoothPlastic)
		band.Shape = Enum.PartType.Cylinder
		weldToPrimary(band, CFrame.new(0, 14 * S, 0) * CFrame.Angles(0, 0, math.rad(90)))
		table.insert(parts, band)

		return parts
	end,

	-- ============================================================
	-- 3) WINDOWS STAGE = THREE round PORTHOLES stacked vertically, centered
	--    down the FRONT (+Z) face, evenly spaced. Each = outer RED frame ring
	--    + a circle of dark-grey rivet dots around the frame + a recessed
	--    DARK-BLUE glossy glass center. Sit ON the surface (flush), not floating.
	--    Body surface front is z = +5; portholes centered at y = -6, 0, +6.
	-- ============================================================
	windows = function()
		local S = ROCKET_SIZE
		local parts = {}
		local centersY = { -6, 0, 6 }
		for i, cy in ipairs(centersY) do
			-- RED FRAME RING: a flat disc on the front face. Disc faces +Z, so
			-- rotate the cylinder's X length-axis to point along Z.
			local frame = makePart("RocketWindowFrame_" .. i, Vector3.new(0.6 * S, 3.6 * S, 3.6 * S),
				C_RED, Enum.Material.SmoothPlastic)
			frame.Shape = Enum.PartType.Cylinder
			-- Disc center pushed to the surface (z 5), slightly proud (5.0) so
			-- it hugs the curved hull without floating.
			weldToPrimary(frame, CFrame.new(0, cy * S, 5.0 * S) * CFrame.Angles(0, math.rad(90), 0))
			table.insert(parts, frame)

			-- DARK-BLUE glossy GLASS center, recessed slightly INTO the frame
			-- (z 4.9 < frame 5.0) so it reads as inset glass, not floating.
			local glass = makePart("RocketWindowGlass_" .. i, Vector3.new(0.7 * S, 2.5 * S, 2.5 * S),
				C_GLASS, Enum.Material.SmoothPlastic)
			glass.Shape = Enum.PartType.Cylinder
			glass.Reflectance = 0.25 -- glossy
			weldToPrimary(glass, CFrame.new(0, cy * S, 4.9 * S) * CFrame.Angles(0, math.rad(90), 0))
			table.insert(parts, glass)

			-- Ring of small dark-grey RIVET DOTS around the frame (8 per window).
			local DOTS = 8
			for d = 0, DOTS - 1 do
				local a = math.rad(d * (360 / DOTS))
				-- Offset around the porthole in the body's vertical/horizontal
				-- plane (radius ~2.05), sitting on the surface (z ~5.05).
				local ringR = 2.05
				local off = CFrame.new(
					math.sin(a) * ringR * S,
					(cy + math.cos(a) * ringR) * S,
					5.05 * S)
				table.insert(parts,
					makeRivet("RocketWindowRivet_" .. i .. "_" .. d, 0.4 * S, off))
			end
		end
		return parts
	end,

	-- ============================================================
	-- 4) FINS STAGE = 4 large swept RED fins evenly spaced around the lower
	--    body. Each is wide where it meets the body and tapers outward+down
	--    to a point that extends BELOW the engine nozzle (landing-leg style).
	--    Flush against the body, no gap. Built from a stacked stair of
	--    shrinking wedge-ish blocks to read as a smooth swept curve.
	-- ============================================================
	fins = function()
		local S = ROCKET_SIZE
		local parts = {}
		for i = 0, 3 do
			local angle = math.rad(i * 90)

			-- Each fin = a few stacked blocks. As we go DOWN, the block sits
			-- further OUT from the body and its tip drops lower, forming a swept
			-- landing-leg profile. Top block hugs the body (inner edge at radius
			-- ~5, flush with the 10-stud hull). Lowest block tip reaches y ~ -30
			-- (below the nozzle mouth at -27).
			-- {radial center, y center, thickness, height, depth(out)}
			-- Each fin is rooted DEEP inside the body (inner edge well inside the hull radius) so it
			-- physically overlaps the body with NO gap, then sweeps out + down. Consecutive segments
			-- overlap each other so the fin reads as ONE continuous blade growing out of the rocket.
			local segs = {
				{ r = 3.5,  y = -10, h = 22, depth = 5.0 },  -- main blade: inner edge ~radius 1 (deep in hull), tall, hugs the lower body
				{ r = 8.0,  y = -23, h = 12, depth = 5.0 },  -- swept blade out+down, overlaps the main blade (no gap)
				{ r = 11.0, y = -29, h = 5,  depth = 4.0 },  -- pointed foot, extends below the nozzle, overlaps the swept blade
			}
			for s, seg in ipairs(segs) do
				local fin = makePart("RocketFin_" .. i .. "_" .. s,
					Vector3.new(seg.depth * S, seg.h * S, 0.8 * S),
					C_RED, Enum.Material.SmoothPlastic)
				-- Rotate so the fin's flat blade lies radially (depth points out
				-- along local X after the yaw), then push out to radius r.
				local off = CFrame.Angles(0, angle, 0)
					* CFrame.new(seg.r * S, seg.y * S, 0)
				weldToPrimary(fin, off)
				table.insert(parts, fin)
			end
		end
		return parts
	end,

	-- ============================================================
	-- 5) CONE STAGE = NOSE CONE on top: a smooth cone tapering to a SHARP
	--    point, RED, sitting FLUSH on the body's upper shoulder dome. Roblox
	--    has no cone primitive, so it is built as a flush stack of shrinking
	--    same-axis cylinders ending in a tiny tip. A rivet ring marks the
	--    cone's base seam. Base diameter matches the body top width (10).
	--    Shoulder dome tops out ~ y +25; cone starts there and rises to a tip.
	-- ============================================================
	cone = function()
		local S = ROCKET_SIZE
		local parts = {}

		-- Stacked shrinking cylinders. Each is 2.5 studs tall; tops touch flush.
		-- Diameters step 10 -> ~0.6 to read as a smooth sharp cone.
		-- center-y placed so consecutive segments are flush (2.5 apart).
		local segs = {
			{ d = 10.0, y = 25.25 }, -- base, matches body/shoulder top diameter (10) flush
			{ d = 8.4,  y = 27.75 },
			{ d = 6.8,  y = 30.25 },
			{ d = 5.2,  y = 32.75 },
			{ d = 3.6,  y = 35.25 },
			{ d = 2.0,  y = 37.75 },
			{ d = 0.7,  y = 40.25 }, -- sharp tip
		}
		for i, seg in ipairs(segs) do
			local c = makePart("RocketCone_" .. i, Vector3.new(2.5 * S, seg.d * S, seg.d * S),
				C_RED, Enum.Material.SmoothPlastic)
			c.Shape = Enum.PartType.Cylinder
			weldToPrimary(c, CFrame.new(0, seg.y * S, 0) * CFrame.Angles(0, 0, math.rad(90)))
			table.insert(parts, c)
		end

		-- RIVET RING around the cone base seam (y ~24, on the 10-stud diameter,
		-- radius 5), tying the cone visually to the shoulder. 10 dots.
		local DOTS = 10
		for d = 0, DOTS - 1 do
			local a = math.rad(d * (360 / DOTS))
			local off = CFrame.Angles(0, a, 0) * CFrame.new(5 * S, 24 * S, 0)
			table.insert(parts,
				makeRivet("RocketConeRivet_" .. d, 0.45 * S, off))
		end

		return parts
	end,
}

--======================================================================
-- addNextStage(): reveal the next build stage in STAGE_ORDER.
-- Returns true if a stage was added, false if already complete.
--======================================================================
function RocketLogic.addNextStage()
	if stageIndex >= #STAGE_ORDER then
		return false
	end
	stageIndex = stageIndex + 1
	local key = STAGE_ORDER[stageIndex]
	local builder = STAGE_BUILDERS[key]
	if builder then
		local created = builder()
		stageParts[key] = created
		-- Small pop-in scale tween for visual flair (size only; welded).
		for _, p in ipairs(created) do
			local target = p.Size
			p.Size = Vector3.new(target.X * 0.2, target.Y * 0.2, target.Z * 0.2)
			TweenService:Create(p, TweenInfo.new(0.4, Enum.EasingStyle.Back,
				Enum.EasingDirection.Out), { Size = target }):Play()
		end
	end
	return true
end

--======================================================================
-- getPrimaryPart(): expose the PrimaryPart so RocketEffects can attach
-- the launch trail / countdown smoke to the rocket itself.
--======================================================================
function RocketLogic.getPrimaryPart()
	return primaryPart
end

--======================================================================
-- launch(endPos, onArrive):
--   Phase A: slow vertical lift (liftoffDuration).
--   Phase B: accelerate + tilt toward endPos and fly across the sky
--            (flightDuration). Calls onArrive() when it reaches endPos.
-- Movement is done by tweening the PrimaryPart's CFrame and calling
-- model:PivotTo each frame. NO teleporting.
--======================================================================
function RocketLogic.launch(endPos, onArrive, liftoffDuration, flightDuration)
	if not rocketModel or not primaryPart then
		if onArrive then onArrive() end
		return
	end
	liftoffDuration = liftoffDuration or 2.5
	flightDuration = flightDuration or 12

	local startCFrame = primaryPart.CFrame
	local startPos = startCFrame.Position

	-- Horizontal direction toward island 14 (used ONLY for the forward lean — never vertical).
	local toEnd = endPos - startPos
	local horizDir = Vector3.new(toEnd.X, 0, toEnd.Z)
	if horizDir.Magnitude < 0.001 then horizDir = Vector3.new(0, 0, 1) end
	horizDir = horizDir.Unit

	-- ORIENTATION FIX: build a CFrame at `pos` whose LOCAL +Y (the rocket's NOSE) points along
	-- `upDir`. Uses CFrame.fromMatrix(right, up) so there is NO CFrame.lookAt degeneracy/flip when
	-- the direction is near-vertical. (The old `lookAt(up-ish) * CFrame.Angles(90)` is what inverted
	-- the rocket — looking straight up is a degenerate lookAt.) The rocket is modelled nose-up (+Y),
	-- so making local +Y = upDir keeps the nose leading, never upside down.
	local function noseUpCFrame(pos, upDir)
		upDir = upDir.Unit
		local right = upDir:Cross(horizDir)
		if right.Magnitude < 1e-3 then
			right = upDir:Cross(Vector3.new(1, 0, 0))
			if right.Magnitude < 1e-3 then right = upDir:Cross(Vector3.new(0, 0, 1)) end
		end
		right = right.Unit
		return CFrame.fromMatrix(pos, right, upDir) -- +Y column = upDir = nose direction
	end

	-- Cap the forward lean so the nose never tilts more than this from vertical (never inverts).
	local MAX_TILT = math.rad(55)

	-- ---- Phase A: slow vertical lift, NOSE STRAIGHT UP ----
	local liftPos = startPos + Vector3.new(0, 60, 0) -- gentle rise
	do
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local alpha = math.clamp((os.clock() - t0) / liftoffDuration, 0, 1)
			local eased = alpha * alpha -- EaseIn so it starts slow
			local pos = startPos:Lerp(liftPos, eased)
			rocketModel:PivotTo(noseUpCFrame(pos, Vector3.new(0, 1, 0))) -- nose +Y, perfectly upright
			if alpha >= 1 then conn:Disconnect() end
		end)
		repeat task.wait() until not conn.Connected
	end

	-- ---- Phase B: accelerate across the sky with a GENTLE capped forward lean (nose stays up) ----
	local flightStart = liftPos
	do
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local alpha = math.clamp((os.clock() - t0) / flightDuration, 0, 1)
			local eased = alpha * alpha * (3 - 2 * alpha) -- accelerate then settle
			local pos = flightStart:Lerp(endPos, eased)
			-- Nose direction = straight up, leaned toward the horizontal travel dir, CAPPED at MAX_TILT.
			-- cos*up + sin*horiz stays between vertical (tilt 0) and MAX_TILT — never past it, never down.
			local tilt = MAX_TILT * eased
			local upDir = (Vector3.new(0, 1, 0) * math.cos(tilt)) + (horizDir * math.sin(tilt))
			rocketModel:PivotTo(noseUpCFrame(pos, upDir))
			if alpha >= 1 then conn:Disconnect() end
		end)
		repeat task.wait() until not conn.Connected
	end

	if onArrive then
		onArrive()
	end
end

--======================================================================
-- cleanup(): destroy the rocket model entirely. No leaks.
--======================================================================
function RocketLogic.cleanup()
	if rocketModel and rocketModel.Parent then
		rocketModel:Destroy()
	end
	rocketModel = nil
	primaryPart = nil
	sitePos = nil
	stageIndex = 0
	stageParts = {}
end

return RocketLogic
