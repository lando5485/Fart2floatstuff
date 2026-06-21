--======================================================================
-- EasterEggManager.server.lua  (Script)  -- STANDALONE, MODULAR easter-egg system
--======================================================================
-- A niche, mythical easter egg: a wandering COW on Island 1 that occasionally gets abducted by a small
-- UFO; afterwards a new cow simply spawns back at its roaming spot. Purely COSMETIC -- it never touches
-- flight, pets, coins, gas, the black hole, shop, events, or any gameplay.
--
-- The cow is a polished low-poly creature built with the SAME rounded-cube UNION technique as the pets
-- (server UnionAsync of a fillet box -> ONE gap-free beveled solid, matte Plastic, smooth surfaces) -- so
-- it's a clean solid cow, NOT a pile of loose balls. It's bigger than a pet and clearly a COW (barrel
-- body, horns, udder, spots) so players don't mistake it for a collectible pet. It's a RIG: anchored
-- parts repositioned each frame so the 4 legs STEP (diagonal gait) with the FEET PLANTED on the ground
-- (the body only bobs/waddles subtly above the legs -- it never hovers).
--
-- MODULAR: each easter egg is one row in EGGS (a spot marker, a build fn + timing). The wander / graze /
-- moo / abduct loop is generic and reused. To add another: write buildX(cf)->rig and add a config row.
--======================================================================

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")

-- \xE2\x9A\xA0 PLACEHOLDER SOUNDS -- REPLACE WITH REAL ASSET IDS BEFORE LAUNCH. Left "" (silent, no broken-id spam).
local MOO_SOUND_ID  = "" -- \xE2\x9A\xA0 REPLACE WITH MOO SOUND
local UFO_SOUND_ID  = "" -- \xE2\x9A\xA0 REPLACE WITH UFO HUM SOUND
local BEAM_SOUND_ID = "" -- \xE2\x9A\xA0 REPLACE WITH ABDUCTION BEAM SOUND

-- motion tuning
local STEP        = 0.05          -- seconds per animation frame
local COW_SPEED   = 4             -- studs/sec (slow + deliberate -> the steps read)
local STRIDE      = 1.5           -- studs of travel per half leg-cycle (ties leg speed to ground speed)
local SWING_ANGLE = math.rad(26)  -- how far the legs swing fore/aft (planted feet, no body lift)
local BOB_HEIGHT  = 0.08          -- TINY body bob (upper body only) -- feet stay grounded, no float
local WADDLE_ROLL = math.rad(3.5) -- subtle side-to-side body lean per step

local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local SMOOTH = Enum.SurfaceType.Smooth

--======================================================================
-- LOW-LEVEL BUILD HELPER (pet art style: matte Plastic, ALL surfaces Smooth, massless, no collide).
--======================================================================
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part")
	p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
	p.Material = material or Enum.Material.Plastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	p.TopSurface = SMOOTH;  p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH;  p.BackSurface = SMOOTH
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end

-- FUSE overlapping source parts into ONE union (rounded solid). On CSG failure, keep the (overlapping)
-- source parts so the cow still appears as a rounded shape. Same approach as the pets' fuse().
local function fuse(model, src, name, color)
	local first = table.remove(src, 1)
	local ok, u = pcall(function() return first:UnionAsync(src) end)
	if ok and typeof(u) == "Instance" then
		first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
		u.Name = name; u.Anchored = true; u.CanCollide = false; u.CanQuery = false; u.CanTouch = false
		u.CastShadow = false; u.Massless = true; u.Material = Enum.Material.Plastic
		u.UsePartColor = true; u.Color = color
		pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
		pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
		pcall(function() u.SmoothingAngle = 60 end) -- soft satin shading across the fused solid
		u.Parent = model
		return u
	else
		table.insert(src, 1, first)
		for _, p in ipairs(src) do p.Name = name .. "Chunk" end -- unfused fallback (still a rounded cluster)
		return nil
	end
end

--======================================================================
-- THE COW. Body + neck + head = ONE rounded-cube UNION (gap-free white solid). Colored details (snout,
-- horns, ears, eyes, spots, udder, tail) + the animated legs are separate flush parts. Returns a RIG.
-- FRONT = -Z (head end) so facing via CFrame.lookAt points the head where it walks.
--======================================================================
local function buildCow(rootCF)
	local cow = Instance.new("Model"); cow.Name = "EasterCow"
	cow.Parent = Workspace -- parented before UnionAsync (CSG needs the parts in the world)
	local WHITE = Color3.fromRGB(248,248,248)
	local BLACK = Color3.fromRGB(34,34,40)
	local PINK  = Color3.fromRGB(255,176,190)
	local DARKP = Color3.fromRGB(248,150,166)
	local CREAM = Color3.fromRGB(232,222,198)
	local rig = { model = cow, poseCF = rootCF, phase = 0, amp = 0, statics = {}, legs = {} }

	-- build a part at a LOCAL offset from rootCF (matte Plastic)
	local function part(shape, sx,sy,sz, color, x,y,z, rot, material)
		return newPart(cow, "b", shape, Vector3.new(sx,sy,sz), color, rootCF * CFrame.new(x,y,z) * (rot or CFrame.new()), material)
	end
	-- record a (already-built) part as a STATIC that follows the upper body (bob/waddle)
	local function recStatic(p) rig.statics[#rig.statics + 1] = { part = p, off = rootCF:Inverse() * p.CFrame }; return p end
	-- build + record a detail part in one go
	local function detail(name, shape, sx,sy,sz, color, x,y,z, rot, material)
		local p = part(shape, sx,sy,sz, color, x,y,z, rot, material); p.Name = name; return recStatic(p)
	end
	-- append a rounded-cube (fillet box: 3 slabs + 8 corner spheres + 12 edge cylinders) to `src`. dims map
	-- X=D (width), Y=H (height), Z=W (length); +Z/-Z is front-back. (Same construction the pets use.)
	local function roundedCubeInto(src, cx,cy,cz, W,H,D,R, color)
		local iW,iH,iD = W-2*R, H-2*R, D-2*R
		local hW,hH,hD = iW/2, iH/2, iD/2
		local dd = 2*R
		local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = part(sh, sx,sy,sz, color, cx+x, cy+y, cz+z, rot) end
		a(BLK, D,iH,iW, 0,0,0); a(BLK, iD,H,iW, 0,0,0); a(BLK, iD,iH,W, 0,0,0)            -- flat faces
		for _, c in ipairs({{1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1}}) do
			a(BAL, dd,dd,dd, c[1]*hD, c[2]*hH, c[3]*hW)                                    -- 8 corner spheres
		end
		for _, e in ipairs({{1,1},{1,-1},{-1,1},{-1,-1}}) do                               -- 12 edge cylinders
			a(CYL, iD,dd,dd, 0, e[1]*hH, e[2]*hW)
			a(CYL, iH,dd,dd, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0,0,math.rad(90)))
			a(CYL, iW,dd,dd, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0,math.rad(90),0))
		end
	end

	-- ===== BODY + NECK + HEAD -> ONE rounded-cube union (clean gap-free solid) =====
	local src = {}
	roundedCubeInto(src, 0, 0, 0,        4.6, 2.6, 3.0, 0.75, WHITE) -- barrel body (Z len 4.6 x Y 2.6 x X 3.0)
	roundedCubeInto(src, 0, 0.7, -2.7,   1.9, 1.8, 2.0, 0.62, WHITE) -- head (forward + up)
	src[#src+1] = part(BLK, 1.6,1.7,1.5, WHITE, 0, 0.4, -1.85)       -- neck block bridging body<->head (no gap)
	local bodyU = fuse(cow, src, "CowBody", WHITE)
	if bodyU then
		cow.PrimaryPart = bodyU; recStatic(bodyU); rig.body = bodyU
	else
		for _, p in ipairs(src) do recStatic(p) end -- union failed: keep the overlapping rounded cluster
		rig.body = src[1]; cow.PrimaryPart = src[1]
	end

	-- ===== COLORED DETAILS (flush, matte) =====
	detail("Muzzle", BLK, 2.0,1.2,1.0, PINK, 0, 0.25, -3.75)                       -- snout (lighter)
	detail("Nostril", CYL, 0.18,0.22,0.22, DARKP, -0.4, 0.3, -4.22, CFrame.Angles(0,math.rad(90),0))
	detail("Nostril", CYL, 0.18,0.22,0.22, DARKP,  0.4, 0.3, -4.22, CFrame.Angles(0,math.rad(90),0))
	detail("EarL", BLK, 1.0,0.32,0.6, WHITE, -1.15, 1.05, -2.55, CFrame.Angles(0,0,math.rad(30)))
	detail("EarR", BLK, 1.0,0.32,0.6, WHITE,  1.15, 1.05, -2.55, CFrame.Angles(0,0,math.rad(-30)))
	detail("HornL", CYL, 0.6,0.28,0.28, CREAM, -0.55, 1.55, -2.5, CFrame.Angles(0,0,math.rad(70)))
	detail("HornR", CYL, 0.6,0.28,0.28, CREAM,  0.55, 1.55, -2.5, CFrame.Angles(0,0,math.rad(110)))
	-- flat disc eyes (+ white sparkle), like the pets -- discs face -Z (the front)
	for _, sgn in ipairs({1, -1}) do
		detail("Eye", CYL, 0.22, 0.66, 0.66, Color3.fromRGB(18,18,22), sgn*0.58, 0.95, -3.55, CFrame.Angles(0,math.rad(90),0))
		detail("Sparkle", CYL, 0.12, 0.24, 0.24, Color3.fromRGB(255,255,255), sgn*0.44, 1.1, -3.62, CFrame.Angles(0,math.rad(90),0))
	end
	-- black spots = FLAT rounded patches (thin discs) hugging the body surface (not bumps)
	detail("Spot", CYL, 0.3, 1.6, 1.3, BLACK, 0.2, 1.28, 0.4, CFrame.Angles(0,0,math.rad(90)))   -- top
	detail("Spot", CYL, 0.3, 1.4, 1.4, BLACK, 1.5, 0.35, 0.95)                                    -- right side (disc faces X)
	detail("Spot", CYL, 0.3, 1.2, 1.2, BLACK, -1.5, 0.5, -0.7)                                    -- left side
	detail("Spot", CYL, 0.3, 1.1, 1.0, BLACK, -0.25, 1.2, 1.65, CFrame.Angles(0,0,math.rad(90)))  -- rump top
	-- udder + teats
	detail("Udder", BLK, 1.25,0.75,1.15, PINK, 0, -1.05, 1.2)
	detail("Teat", CYL, 0.42,0.2,0.2, DARKP, -0.32, -1.5, 1.0, CFrame.Angles(0,0,math.rad(90)))
	detail("Teat", CYL, 0.42,0.2,0.2, DARKP,  0.32, -1.5, 1.0, CFrame.Angles(0,0,math.rad(90)))
	-- tail (thin cylinder down the rump + a dark tuft)
	detail("Tail", CYL, 1.5,0.26,0.26, WHITE, 0, 0.05, 2.55, CFrame.Angles(math.rad(35),0,0) * CFrame.Angles(0,0,math.rad(90)))
	detail("TailTuft", BLK, 0.5,0.55,0.5, BLACK, 0, -0.7, 2.95)

	-- ===== LEGS (separate, animated). 4 rounded cylinder legs + dark hoof caps; diagonal gait (FL+BR vs FR+BL).
	-- hip = local point at the top of the leg; legHalf/hoofY chosen so the FEET sit at root.Y - 2.6 (the ground).
	local function addLeg(lx, lz, group)
		local hip = Vector3.new(lx, -0.4, lz)
		local legHalf, hoofY = 0.85, 1.95
		local legCF  = rootCF * CFrame.new(hip) * CFrame.new(0,-legHalf,0) * CFrame.Angles(0,0,math.rad(90))
		local hoofCF = rootCF * CFrame.new(hip) * CFrame.new(0,-hoofY,0) * CFrame.Angles(0,0,math.rad(90))
		local stub = newPart(cow, "Leg",  CYL, Vector3.new(1.7,0.74,0.74), WHITE, legCF)
		local hoof = newPart(cow, "Hoof", CYL, Vector3.new(0.5,0.8,0.8), BLACK, hoofCF)
		rig.legs[#rig.legs + 1] = { stub = stub, hoof = hoof, hip = hip, legHalf = legHalf, hoofY = hoofY, phase = group }
	end
	addLeg(-0.95, -1.3, 0)        -- front-left
	addLeg( 0.95, -1.3, math.pi)  -- front-right
	addLeg(-0.95,  1.45, math.pi) -- back-left
	addLeg( 0.95,  1.45, 0)       -- back-right

	-- moo sound (placeholder) on the body
	local moo = Instance.new("Sound"); moo.Name = "MooSound"; moo.SoundId = MOO_SOUND_ID -- \xE2\x9A\xA0 REPLACE WITH MOO SOUND
	moo.Volume = 0.6; moo.RollOffMinDistance = 12; moo.RollOffMaxDistance = 130; moo.Parent = rig.body
	return rig
end

-- Position every cow part. The UPPER body (union + details) bobs/waddles a little; the LEGS swing about
-- hips on a NON-bobbing base, so the FEET stay planted on the ground (no floating).
local function applyPose(rig)
	if not rig.model.Parent then return end
	local amp = rig.amp
	local bob  = math.abs(math.sin(rig.phase)) * BOB_HEIGHT * amp
	local roll = math.sin(rig.phase) * WADDLE_ROLL * amp
	local grounded = rig.poseCF * CFrame.Angles(0, 0, roll)   -- waddle only (NO vertical) -> legs use this
	local upper    = grounded * CFrame.new(0, bob, 0)         -- upper body bobs slightly above the legs
	for _, e in ipairs(rig.statics) do e.part.CFrame = upper * e.off end
	for _, lg in ipairs(rig.legs) do
		local swing = math.sin(rig.phase + lg.phase) * SWING_ANGLE * amp
		local hipCF = grounded * CFrame.new(lg.hip) * CFrame.Angles(swing, 0, 0)
		lg.stub.CFrame = hipCF * CFrame.new(0, -lg.legHalf, 0) * CFrame.Angles(0,0,math.rad(90))
		lg.hoof.CFrame = hipCF * CFrame.new(0, -lg.hoofY, 0) * CFrame.Angles(0,0,math.rad(90))
	end
end

--======================================================================
-- THE SMALL UFO (rounded saucer). Moved with a simple PivotTo glide (it FLIES). Invisible upright Root.
--======================================================================
local function buildUFO(rootCF)
	local ufo = Instance.new("Model"); ufo.Name = "EasterUFO"
	local GRAY = Color3.fromRGB(150,156,168)
	local function rel(o) return rootCF * o end
	local root = newPart(ufo, "Root", BLK, Vector3.new(0.4,0.4,0.4), GRAY, rootCF)
	root.Transparency = 1; ufo.PrimaryPart = root
	newPart(ufo, "Disc", CYL, Vector3.new(0.7,7,7), GRAY, rel(CFrame.Angles(0,0,math.rad(90))))
	newPart(ufo, "Rim",  CYL, Vector3.new(0.45,7.6,7.6), Color3.fromRGB(95,100,112), rel(CFrame.new(0,-0.1,0) * CFrame.Angles(0,0,math.rad(90))))
	local dome = newPart(ufo, "Dome", BAL, Vector3.new(3.4,3.4,3.4), Color3.fromRGB(150,220,255), rel(CFrame.new(0,0.9,0)))
	dome.Transparency = 0.35
	for i = 0, 3 do
		local a = i * (math.pi / 2)
		newPart(ufo, "Light", BAL, Vector3.new(0.65,0.65,0.65), Color3.fromRGB(255,238,120),
			rel(CFrame.new(math.cos(a) * 2.7, -0.45, math.sin(a) * 2.7)), Enum.Material.Neon)
	end
	local hum = Instance.new("Sound"); hum.Name = "HumSound"; hum.SoundId = UFO_SOUND_ID -- \xE2\x9A\xA0 REPLACE WITH UFO HUM SOUND
	hum.Volume = 0.5; hum.Looped = true; hum.RollOffMinDistance = 15; hum.RollOffMaxDistance = 160; hum.Parent = root
	return ufo
end

local function buildBeam(topPos, botPos)
	local mid = (topPos + botPos) / 2
	local len = math.max((topPos - botPos).Magnitude, 1)
	local beam = newPart(Workspace, "EasterBeam", CYL, Vector3.new(len, 5, 5),
		Color3.fromRGB(150,230,255), CFrame.lookAt(mid, botPos) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.Neon)
	beam.Transparency = 0.6
	local s = Instance.new("Sound"); s.Name = "BeamSound"; s.SoundId = BEAM_SOUND_ID -- \xE2\x9A\xA0 REPLACE WITH BEAM SOUND
	s.Volume = 0.5; s.RollOffMinDistance = 15; s.RollOffMaxDistance = 160; s.Parent = beam
	return beam
end

--======================================================================
-- MOTION HELPERS
--======================================================================
local function groundFacing(pos, target)
	local flat = Vector3.new(target.X, pos.Y, target.Z)
	if (flat - pos).Magnitude < 0.05 then return CFrame.new(pos) end
	return CFrame.lookAt(pos, flat)
end
local function interruptibleWait(secs, stop)
	local t = 0
	while t < secs do
		if stop and stop() then return end
		task.wait(STEP * 2); t = t + STEP * 2
	end
end
-- simple PivotTo glide for FLYING things (UFO) -- no leg rig
local function glide(model, toCF, duration, stop)
	if not (model and model.Parent) then return end
	local fromCF = model:GetPivot()
	local t = 0
	while t < duration do
		if stop and stop() then return end
		if not model.Parent then return end
		t = math.min(duration, t + STEP)
		local a = t / duration
		pcall(function() model:PivotTo(fromCF:Lerp(toCF, (math.sin((a - 0.5) * math.pi) + 1) / 2)) end)
		task.wait(STEP)
	end
	if model.Parent then pcall(function() model:PivotTo(toCF) end) end
end
-- drive the COW rig from its current pose to toCF; if `moving`, legs step (gait tied to distance -> no
-- foot-slide) + the upper body bobs/waddles; if not, the legs straighten (amp -> 0). Feet stay planted.
local function driveCow(rig, toCF, duration, moving, stop)
	if not rig.model.Parent then return end
	local fromCF = rig.poseCF
	local t = 0
	while t < duration do
		if stop and stop() then return end
		if not rig.model.Parent then return end
		t = math.min(duration, t + STEP)
		local a = t / duration
		local newCF = fromCF:Lerp(toCF, (math.sin((a - 0.5) * math.pi) + 1) / 2)
		local dpos = (newCF.Position - rig.poseCF.Position).Magnitude
		if moving then rig.phase = rig.phase + (dpos / STRIDE) * math.pi end
		rig.amp = rig.amp + ((moving and 1 or 0) - rig.amp) * 0.25
		rig.poseCF = newCF
		applyPose(rig)
		task.wait(STEP)
	end
	if not (stop and stop()) and rig.model.Parent then
		rig.poseCF = toCF
		rig.amp = rig.amp + ((moving and 1 or 0) - rig.amp) * 0.25
		applyPose(rig)
	end
end
local function randomPoint(center, radius, baseY)
	local ang = math.random() * 2 * math.pi
	local r = radius * math.sqrt(math.random())
	return Vector3.new(center.X + math.cos(ang) * r, baseY, center.Z + math.sin(ang) * r)
end
local function walkTo(rig, baseY, target, stop)
	if not rig.model.Parent then return end
	local fromPos = rig.poseCF.Position
	local toPos = Vector3.new(target.X, baseY, target.Z)
	local dir = toPos - Vector3.new(fromPos.X, baseY, fromPos.Z)
	local toCF = (dir.Magnitude > 0.1) and CFrame.lookAt(toPos, toPos + dir) or rig.poseCF
	driveCow(rig, toCF, math.clamp(dir.Magnitude / COW_SPEED, 0.5, 8), true, stop)
end
local function graze(rig, baseY, stop)
	if not rig.model.Parent then return end
	local upright = rig.poseCF
	driveCow(rig, upright * CFrame.Angles(math.rad(14), 0, 0) * CFrame.new(0, -0.3, -0.2), 0.5, false, stop)
	interruptibleWait(math.random(2, 4), stop)
	if rig.model.Parent then driveCow(rig, upright, 0.45, false, stop) end
end
local function moo(rig, stop)
	if not rig.model.Parent then return end
	local s = rig.body and rig.body:FindFirstChild("MooSound"); if s then pcall(function() s.TimePosition = 0; s:Play() end) end
	print("[EasterEgg] moo")
	local home = rig.poseCF
	driveCow(rig, home * CFrame.new(0, 0.25, 0), 0.2, false, stop)
	if rig.model.Parent then driveCow(rig, home, 0.2, false, stop) end
end

--======================================================================
-- THE ABDUCTION (cow rig + UFO glide). UFO in -> hover -> cow panic-hop -> beam -> cow rises -> UFO away.
--======================================================================
local function abduct(cfg, rig, baseY)
	if not rig.model.Parent then return end
	local cowPos = rig.poseCF.Position
	local rot = rig.poseCF - cowPos
	local ufo = buildUFO(CFrame.new(cowPos.X, cowPos.Y + 55, cowPos.Z)); ufo.Parent = Workspace
	pcall(function() local h = ufo.PrimaryPart:FindFirstChild("HumSound"); if h then h:Play() end end)
	local hoverY = cowPos.Y + 13
	glide(ufo, CFrame.new(cowPos.X, hoverY, cowPos.Z), 1.6)
	driveCow(rig, CFrame.new(cowPos.X, cowPos.Y + 2.2, cowPos.Z) * rot, 0.22, false) -- panic hop
	if rig.model.Parent then driveCow(rig, CFrame.new(cowPos.X, cowPos.Y, cowPos.Z) * rot, 0.22, false) end
	local beam = buildBeam(Vector3.new(cowPos.X, hoverY - 1, cowPos.Z), Vector3.new(cowPos.X, cowPos.Y, cowPos.Z))
	pcall(function() local b = beam:FindFirstChild("BeamSound"); if b then b:Play() end end)
	driveCow(rig, CFrame.new(cowPos.X, hoverY - 2.5, cowPos.Z) * rot, 2.5, false) -- rise into the UFO
	pcall(function() beam:Destroy() end)
	task.spawn(function() driveCow(rig, CFrame.new(cowPos.X, cowPos.Y + 230, cowPos.Z) * rot, 1.3, false) end)
	glide(ufo, CFrame.new(cowPos.X, cowPos.Y + 250, cowPos.Z), 1.3)
	task.wait(0.1)
	pcall(function() rig.model:Destroy() end)
	pcall(function() ufo:Destroy() end)
end

--======================================================================
-- ISLAND / MARKER RESOLUTION (by name, like the pet quest markers).
--======================================================================
local function findIsland(prefix)
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.find(m.Name, prefix, 1, true) then return m end
	end
	return nil
end
local function resolveMarker(island, name)
	local p = island and island:FindFirstChild(name, true)
	if not p then p = Workspace:FindFirstChild(name) end
	if not p then p = Workspace:FindFirstChild(name, true) end
	return p
end

--======================================================================
-- OVERHEAD CHAT BUBBLE (server-built BillboardGui -- works for an NPC regardless of chat settings, unlike the
-- legacy Chat:Chat). One bubble per creature, adorned to its body so it tracks the walk/bob; say() shows a
-- line then auto-hides. The talk loop is config-driven (cfg.talkLines) so it ONLY affects eggs that opt in,
-- and it dies with the creature (loop guard on rig.model.Parent). Purely cosmetic -- no gameplay touched.
--======================================================================
local function attachTalkBubble(rig)
	local host = rig and rig.body
	if not (host and host.Parent) then return nil end
	local bb = Instance.new("BillboardGui")
	bb.Name = "TalkBubble"; bb.Adornee = host
	bb.Size = UDim2.fromOffset(230, 64)        -- PIXEL OFFSET units only (NO scale component) -> constant screen size at any distance
	bb.SizeOffset = Vector2.new(0, 0)
	bb.StudsOffset = Vector3.new(0, 3.3, 0)    -- local StudsOffset (NOT StudsOffsetWorldSpace) for the height above the head
	bb.LightInfluence = 0                      -- ignore world lighting -> constant look near/far
	bb.AlwaysOnTop = true; bb.MaxDistance = 20; bb.Enabled = false; bb.Parent = host; print("[BUBBLE RANGE] cow MaxDistance=20") -- only visible within 20 studs (Roblox auto-hides the BillboardGui beyond MaxDistance)
	print("[BUBBLE FIX] cow offset-locked"); print(string.format("[BUBBLE DIAG] TalkBubble SizeOffset=%s StudsOffsetWorldSpace=%s hasUIScale=%s", tostring(bb.SizeOffset), tostring(bb.StudsOffsetWorldSpace), (bb:FindFirstChildWhichIsA("UIScale", true) or bb:FindFirstChildWhichIsA("UISizeConstraint", true)) and "y" or "n"))
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(230, 64); frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BackgroundTransparency = 0.05; frame.BorderSizePixel = 0; frame.Parent = bb
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = frame
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(40, 40, 46); stroke.Thickness = 2; stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1; label.Size = UDim2.fromOffset(214, 54); label.Position = UDim2.new(0, 8, 0, 5)
	label.Font = Enum.Font.GothamBold; label.TextScaled = false; label.TextSize = 18; label.AutomaticSize = Enum.AutomaticSize.None; label.TextColor3 = Color3.fromRGB(34, 34, 40)
	label.TextWrapped = true; label.Text = ""; label.Parent = frame
	print(string.format("[BUBBLE TEXT] cow TextScaled=false->%s TextSize=%d sizeUsesScale=n", tostring(label.TextScaled), label.TextSize))
	return { gui = bb, label = label }
end

local function bubbleSay(bubble, message, holdSecs)
	if not (bubble and bubble.gui and bubble.gui.Parent) then return end
	bubble.label.Text = message
	bubble.gui.Enabled = true
	task.delay(holdSecs or 4.5, function()
		if bubble.gui and bubble.gui.Parent then bubble.gui.Enabled = false end
	end)
end

-- proximity gate: true if any player's character is within `range` studs of the creature's body. Mirrors the
-- Farmer's prompt range (FarmerNPC PROMPT_DISTANCE = 12, set via ProximityPrompt.MaxActivationDistance).
local COW_TALK_RANGE = 12
local function isPlayerNear(rig, range)
	local host = rig and rig.body
	if not (host and host.Parent) then return false end
	local origin = host.Position
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - origin).Magnitude <= range then return true end
	end
	return false
end

-- talk loop: while the creature exists, every talkMin..talkMax sec show a random line -- but ONLY when a player
-- is within COW_TALK_RANGE (same close range as the Farmer's prompt). No one near -> skip this tick. Stops on despawn.
local function runEggTalk(rig, cfg)
	if not (rig and rig.model and rig.model.Parent) then return end
	local lines = cfg.talkLines
	if not (lines and #lines > 0) then return end
	local bubble = attachTalkBubble(rig)
	if not bubble then return end
	print("[COW TALK] bubble wired"); print("[BUBBLE SPEAK] cow method=reuses spawn bubble")
	while rig.model.Parent do
		interruptibleWait(math.random(cfg.talkMin or 12, cfg.talkMax or 18), function() return not rig.model.Parent end)
		if not rig.model.Parent then break end
		if isPlayerNear(rig, COW_TALK_RANGE) then
			local line = lines[math.random(1, #lines)]
			bubbleSay(bubble, line, 4.5)
			print("[COW TALK] said (player near): " .. line)
		else
			print("[COW TALK] skipped (no one near)")
		end
	end
end

--======================================================================
-- PER-EGG CONTROLLER (one task per easter egg). Sequential -> ALWAYS exactly one creature at a time.
--======================================================================
local forceAbduct = {} -- [eggName] = true -> the /abductcow test command triggers the next abduction immediately

local function runEgg(cfg)
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end
	local island; for _ = 1, 30 do island = findIsland(cfg.island); if island then break end; task.wait(1) end
	local spotM = resolveMarker(island, cfg.spot)
	if not (spotM and spotM:IsA("BasePart")) then
		warn("[EasterEgg] " .. cfg.name .. ": marker '" .. cfg.spot .. "' not found -- easter egg disabled")
		return
	end
	pcall(function() spotM.Transparency = 1; spotM.CanCollide = false; spotM.CanQuery = false end)
	local spotPos = spotM.Position
	local baseY   = spotPos.Y + (cfg.groundOffset or 2.6)

	local firstSpawn = true
	while true do
		-- spawn the cow directly at its roaming spot (no barn walk-out)
		local spawnPos = Vector3.new(spotPos.X, baseY, spotPos.Z)
		local rig = cfg.build(groundFacing(spawnPos, spawnPos + Vector3.new(0, 0, -1)))
		local stop = function() return forceAbduct[cfg.name] == true or not rig.model.Parent end
		print("[EasterEgg] " .. (firstSpawn and "cow spawned at " or "new cow spawned at ") .. cfg.spot)
		firstSpawn = false
		forceAbduct[cfg.name] = false

		-- overhead chat bubble (cosmetic): its own task, tied to THIS rig -> dies when this cow despawns/abducts
		if cfg.talkLines then task.spawn(function() runEggTalk(rig, cfg) end) end

		local interval = math.random(cfg.abductMin, cfg.abductMax)
		print("[EasterEgg] next abduction in " .. interval .. "s")
		local deadline = os.clock() + interval
		local nextMoo  = os.clock() + math.random(cfg.mooMin, cfg.mooMax)

		-- WANDER (open area near CowSpot) / GRAZE / MOO until abduction time (or /abductcow forces it)
		while os.clock() < deadline and not forceAbduct[cfg.name] and rig.model.Parent do
			if os.clock() >= nextMoo then moo(rig, stop); nextMoo = os.clock() + math.random(cfg.mooMin, cfg.mooMax) end
			if math.random() < 0.3 then
				graze(rig, baseY, stop)
			else
				walkTo(rig, baseY, randomPoint(spotPos, cfg.wanderRadius, baseY), stop)
			end
		end
		forceAbduct[cfg.name] = false

		if rig.model.Parent then
			print("[EasterEgg] abduction starting")
			local ok, err = pcall(abduct, cfg, rig, baseY)
			if not ok then warn("[EasterEgg] abduction error: " .. tostring(err)); pcall(function() rig.model:Destroy() end) end
			print("[EasterEgg] cow abducted, UFO away")
		end

		task.wait(math.random(cfg.returnMin, cfg.returnMax))
	end
end

--======================================================================
-- CONFIG -- one row per easter egg. Add more rows (creature + marker + timing) to add more easter eggs.
--======================================================================
local EGGS = {
	{
		name         = "Cow",
		island       = "Island_1_BeanFarm",
		spot         = "CowSpot",            -- roam centre (the cow spawns + wanders here; no barn walk-out)
		build        = buildCow,
		groundOffset = 2.0,                  -- body-centre height above the marker so the FEET sit on the ground (lowered 0.6 so he isn't floating; decrease more if still hovering, increase if sinking)
		wanderRadius = 28,                   -- studs from CowSpot (clamped -> stays in the open, never off the island)
		abductMin    = 360, abductMax = 600, -- 6-10 minutes between abductions (randomized each time)
		returnMin    = 30,  returnMax  = 45, -- a new cow appears 30-45s after an abduction
		mooMin       = 15,  mooMax     = 40, -- moo every 15-40s
		talkMin      = 12,  talkMax    = 18, -- overhead chat bubble shows a random line every 12-18s
		talkLines    = {                     -- random cosmetic one-liners for the overhead bubble
			"Moo.",
			"Nice day for floating, huh?",
			"I've been abducted before, you know.",
			"Got any snacks?",
			"Mooove along, nothing to see here.",
			"The sky calls to me.",
			"Ever tried flying on a full stomach?",
			"Baa\xE2\x80\x94 wait, wrong animal.",
		},
	},
}

for _, cfg in ipairs(EGGS) do
	task.spawn(function()
		local ok, err = pcall(runEgg, cfg)
		if not ok then warn("[EasterEgg] " .. tostring(cfg.name) .. " controller error: " .. tostring(err)) end
	end)
end

--======================================================================
-- \xE2\x9A\xA0\xE2\x9A\xA0 TEST COMMAND /abductcow -- triggers the cow abduction IMMEDIATELY (test users only). \xE2\x9A\xA0\xE2\x9A\xA0
-- \xE2\x9A\xA0\xE2\x9A\xA0 REMOVE BEFORE LAUNCH. \xE2\x9A\xA0\xE2\x9A\xA0  Uses the same _G.isAllowedTestUser allow-list as the other test commands.
--======================================================================
local function hookAbductChat(plr)
	plr.Chatted:Connect(function(msg)
		if string.lower(msg) == "/abductcow" then
			if _G.isAllowedTestUser and _G.isAllowedTestUser(plr) then
				forceAbduct["Cow"] = true
				print("[EasterEgg] /abductcow triggered by " .. plr.Name .. " (TEST - REMOVE BEFORE LAUNCH)")
			end
		end
	end)
end
for _, p in ipairs(Players:GetPlayers()) do hookAbductChat(p) end
Players.PlayerAdded:Connect(hookAbductChat)

--======================================================================
-- CONDIMENT GEYSER EASTER EGG (Island 12 / Burger Bluff). Two nozzle markers -- KetchupSquirt (RED) +
-- MustardSquirt (YELLOW) -- periodically (~every 10 min, randomized) shoot a big geyser stream of colored
-- condiment blobs STRAIGHT UP for ~2s, which arc, fall back down, and fade -- BOTH firing simultaneously.
-- Purely COSMETIC: anchored, CanCollide=false, NO sound, and each squirt cleans up its own parts (no leak).
-- Reuses the same newPart helper + StandsReady/marker resolution the cow uses, so it's part of this system.
--======================================================================
local KETCHUP_COLOR = Color3.fromRGB(190, 30, 30)  -- ketchup red
local MUSTARD_COLOR = Color3.fromRGB(226, 196, 44) -- mustard yellow
local GEYSER_MIN, GEYSER_MAX = 480, 720            -- ~8-12 minutes between geysers (randomized -> unpredictable)
local SQUIRT_DURATION = 2.0                         -- seconds the nozzle actively spews
local BLOB_INTERVAL   = 0.06                        -- spawn cadence -> a thick stream
local BLOB_RISE_SPEED = 90                          -- studs/sec upward (tall, visible geyser)
local BLOB_GRAVITY    = 95                          -- studs/sec^2 downward -> rise, peak, fall
local BLOB_LIFE       = 2.4                         -- each blob's flight before fade/despawn
local BLOB_STEP       = 0.04                        -- sim frame

local geyserPos = {}        -- { ketchup = Vector3, mustard = Vector3 } -- captured AFTER StandsReady
local geyserReady = false

-- ONE geyser: a self-managed stream of colored condiment blobs (parabolic: up -> peak -> fall + fade). It
-- runs in its own coroutine and DESTROYS its own folder once the spew window is over and all blobs are gone.
local function fireGeyser(pos, col)
	task.spawn(function()
		pcall(function()
			local folder = Instance.new("Folder"); folder.Name = "CondimentGeyser"; folder.Parent = Workspace
			local blobs = {}
			local g = Vector3.new(0, -BLOB_GRAVITY, 0)
			local elapsed, spawnAccum = 0, 0
			while true do
				-- spawn new blobs only during the active spew window
				if elapsed < SQUIRT_DURATION then
					spawnAccum = spawnAccum + BLOB_STEP
					while spawnAccum >= BLOB_INTERVAL do
						spawnAccum = spawnAccum - BLOB_INTERVAL
						local s = 1.1 + math.random() * 1.1
						local b = newPart(folder, "Blob", BAL, Vector3.new(s,s,s), col, CFrame.new(pos), Enum.Material.SmoothPlastic)
						-- mostly straight up (slight spread) -> a tight geyser column
						local vel = Vector3.new((math.random()-0.5)*9, BLOB_RISE_SPEED + math.random()*22, (math.random()-0.5)*9)
						blobs[#blobs+1] = { part = b, vel = vel, t = 0 }
					end
				end
				-- advance every blob (gravity arc + fade near end)
				for i = #blobs, 1, -1 do
					local bl = blobs[i]
					bl.t = bl.t + BLOB_STEP
					bl.vel = bl.vel + g * BLOB_STEP
					if bl.part.Parent then
						bl.part.CFrame = bl.part.CFrame + bl.vel * BLOB_STEP
						if bl.t > BLOB_LIFE - 0.6 then bl.part.Transparency = math.clamp((bl.t - (BLOB_LIFE - 0.6)) / 0.6, 0, 1) end
					end
					if bl.t >= BLOB_LIFE or not bl.part.Parent then
						pcall(function() bl.part:Destroy() end)
						table.remove(blobs, i)
					end
				end
				if elapsed >= SQUIRT_DURATION and #blobs == 0 then break end -- done -> clean up
				elapsed = elapsed + BLOB_STEP
				task.wait(BLOB_STEP)
			end
			pcall(function() folder:Destroy() end)
		end)
	end)
end

-- fire BOTH nozzles at the exact same moment (red + yellow)
local function fireBothGeysers()
	if not geyserReady then return end
	print("[EasterEgg] ketchup+mustard geyser firing")
	fireGeyser(geyserPos.ketchup, KETCHUP_COLOR)
	fireGeyser(geyserPos.mustard, MUSTARD_COLOR)
end

-- controller: wait for islands positioned, resolve both nozzle markers on Island 12, then loop ~every 10 min
task.spawn(function()
	local ok, err = pcall(function()
		local waited = 0
		while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end
		local island; for _ = 1, 30 do island = findIsland("Island_12_BurgerBluff"); if island then break end; task.wait(1) end
		local kM = resolveMarker(island, "KetchupSquirt")
		local mM = resolveMarker(island, "MustardSquirt")
		if not (kM and kM:IsA("BasePart") and mM and mM:IsA("BasePart")) then
			warn("[EasterEgg] condiment geyser markers not found on Island 12 -- geyser disabled")
			return
		end
		pcall(function() kM.Transparency = 1; kM.CanCollide = false; kM.CanQuery = false end)
		pcall(function() mM.Transparency = 1; mM.CanCollide = false; mM.CanQuery = false end)
		geyserPos.ketchup = kM.Position
		geyserPos.mustard = mM.Position
		geyserReady = true
		print("[EasterEgg] condiment geysers ready (Burger Bluff)")
		while true do
			local nextIn = math.random(GEYSER_MIN, GEYSER_MAX)
			print("[EasterEgg] next condiment geyser in " .. nextIn .. "s")
			task.wait(nextIn)
			pcall(fireBothGeysers)
		end
	end)
	if not ok then warn("[EasterEgg] condiment geyser controller error: " .. tostring(err)) end
end)

--======================================================================
-- ⚠⚠ TEST COMMAND /squirt -- fires BOTH condiment geysers IMMEDIATELY (test users only). ⚠⚠
-- ⚠⚠ REMOVE BEFORE LAUNCH. ⚠⚠  Uses the same _G.isAllowedTestUser allow-list as /abductcow.
--======================================================================
local function hookSquirtChat(plr)
	plr.Chatted:Connect(function(msg)
		if string.lower(msg) == "/squirt" then
			if _G.isAllowedTestUser and _G.isAllowedTestUser(plr) then
				print("[EasterEgg] /squirt triggered by " .. plr.Name .. " (TEST - REMOVE BEFORE LAUNCH)")
				pcall(fireBothGeysers)
			end
		end
	end)
end
for _, p in ipairs(Players:GetPlayers()) do hookSquirtChat(p) end
Players.PlayerAdded:Connect(hookSquirtChat)

print("[EasterEgg] manager ready (" .. #EGGS .. " easter egg(s))")
