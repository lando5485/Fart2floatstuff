--======================================================================
-- RocketNPCs.lua  (ModuleScript)
--======================================================================
-- Construction-worker NPCs for the Rocket event. Pure background actors:
--   * spawn(site)  -> 3 REAL R15 Humanoid workers walk in from staggered
--                     offsets to the site (Humanoid:MoveTo pathing + walk anim)
--   * build()      -> hammer animation loop at the site (RightShoulder Motor6D)
--   * idle()       -> personality: pause / look around (Neck) / wipe forehead
--   * wave()       -> wave on launch; ONE worker comically falls backward
--   * cleanup()    -> destroy all NPCs + site dressing, no leaks
--
-- REBUILD NOTE (visual/character only): each worker is now a genuine Roblox
-- R15 character built with Players:CreateHumanoidModelFromDescription(...).
-- That gives us a real Humanoid, correct R15 proportions and the standard R15
-- Motor6D joints we animate by hand:
--    * "RightShoulder" Motor6D (parented in RightUpperArm) -> hammer swing/wave
--    * "Neck" Motor6D (parented in Head)                   -> look-around
-- We dress them with welded hat / hi-vis vest / hammer parts and recolour the
-- R15 body parts (hands = gloves, feet = boots, legs = pants) via the
-- HumanoidDescription. The rocket / event / flight / explosion / balance code
-- is untouched — this module only changes how the workers look & animate.
--
-- COLLISION TRADEOFF (commented at the plant step too): while a worker is
-- walking IN, its legs collide with the ground so it walks normally. The
-- moment it arrives we "plant" it: anchor the HumanoidRootPart and turn OFF
-- collision on every part, so a planted worker can never block, trap or knock
-- a player standing on island 1.
--======================================================================

local RocketNPCs = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ---------------------------------------------------------------------
-- DEFAULT R15 ANIMATION ASSET IDS
-- These are the well-known Roblox default R15 "Animate" loop ids. If a swap is
-- ever needed it is a one-line change here. (Walk + Idle are all we need for an
-- NPC that walks in then stands; everything else is hand-animated Motor6Ds.)
--   * R15 default walk : rbxassetid://913402848   (uncertain exact id — swap here)
--   * R15 default idle : rbxassetid://507766388   (uncertain exact id — swap here)
-- NOTE: both ids above are the standard default R15 ids; if your place uses a
-- different default Animate set, change ONLY these two constants.
-- ---------------------------------------------------------------------
local WALK_ANIM_ID = "rbxassetid://913402848"
local IDLE_ANIM_ID = "rbxassetid://507766388"

-- Module state.
local npcFolder = nil
local dressingFolder = nil  -- construction set-dressing (STAYS on island 1)
local workers = {}          -- list of worker rig tables (see makeWorker)
local sitePos = nil
local actionLoops = {}      -- heartbeat connections we must stop on cleanup

-- ---------------------------------------------------------------------
-- WORKER_STANDOFF (studs): how far OUT from the site centre each worker
-- stands while building. The rocket's widest part (the fins) reaches roughly
-- ~21 studs from centre at the current rocket scale, so this MUST stay clearly
-- beyond that. At 25 studs the planted body sits ~4 studs clear of the fins,
-- and the swing is mostly VERTICAL (the arm raises then strikes), so the
-- hammer's horizontal reach toward the rocket is tiny — NO worker body or arm
-- touches the rocket during walk-in, building, or launch (small clear gap kept).
-- BUMP THIS if the rocket is ever scaled larger (keep it > fin radius + arm
-- reach + margin).
-- Brought CLOSER (was 25, then 23) so the workers read as clearly "at the rocket" working on it. We
-- can stand them well INSIDE the ~21-stud fin envelope now because the bearings below place each
-- worker in a GAP BETWEEN the fins (the 4 fins sit on the cardinal bearings 0/90/180/270; gaps are at
-- 45/135/225/315). In a gap, the only geometry ahead of a worker (toward centre) is the narrow body
-- (radius ~5*scale), and the nearest fin blades sit ~10+ studs off to the sides — so at 16 the body
-- and the mostly-VERTICAL hammer swing keep a clear gap from BOTH the body and the fins. (If you ever
-- want them even closer, this single value can go lower; in the gaps it stays clear down to ~10.)
local WORKER_STANDOFF = 16

-- Three bearings (degrees) around the rocket, placed in the GAPS BETWEEN the 4 fins (fins sit on the
-- cardinal bearings 0/90/180/270, so the gaps are at 45/135/225/315). Standing in the gaps lets the
-- workers come in close (WORKER_STANDOFF) without the fins ever being in front of them. Each worker
-- plants on the ring at its bearing and FACES the rocket centre.
local WORKER_BEARINGS = { 45, 135, 225 }

-- Helper: a flat (ground-level) offset on the standoff ring at `bearingDeg`.
local function ringOffset(bearingDeg, radius)
	local a = math.rad(bearingDeg)
	return Vector3.new(math.sin(a) * radius, 0, math.cos(a) * radius)
end

-- The 3 staggered entry offsets (relative to the site, on the ground). These
-- start FURTHER out than the standoff ring (on the same bearings) so the
-- workers walk inward toward the ring but never toward the rocket centre.
local SPAWN_OFFSETS = {
	ringOffset(WORKER_BEARINGS[1], WORKER_STANDOFF + 16),
	ringOffset(WORKER_BEARINGS[2], WORKER_STANDOFF + 20),
	ringOffset(WORKER_BEARINGS[3], WORKER_STANDOFF + 18),
}

-- Where each worker stands while building: ON the standoff ring (a safe radius
-- clearly beyond the rocket's widest part). Walk-in targets these — NOT the
-- rocket centre — so a worker can never walk into the rocket body/fins.
local WORK_OFFSETS = {
	ringOffset(WORKER_BEARINGS[1], WORKER_STANDOFF),
	ringOffset(WORKER_BEARINGS[2], WORKER_STANDOFF),
	ringOffset(WORKER_BEARINGS[3], WORKER_STANDOFF),
}

-- Per-worker appearance variation so the 3 aren't identical:
--   skin     -> HumanoidDescription HeadColor / torso / arms (base body tone),
--               using believable HUMAN SKIN TONES varied across the three.
--   shirt    -> torso/arm body colour (uniform work-shirt tone under the vest)
--   pants    -> recolours the upper+lower legs (work trousers)
--   gloves   -> recolours the hands (work gloves)
--   boots    -> recolours the feet + lower legs (sturdy boots)
--   vest     -> welded hi-vis vest base colour
--   hat      -> welded hard-hat colour (hi-vis)
--   idleSpd  -> idle-anim playback speed (slight per-worker variation)
--   stance   -> a small resting neck-yaw offset (degrees) so the 3 stand
--               slightly differently while planted (not all dead-ahead)
--   shoulderRest -> a small resting shoulder-pitch offset (degrees) so arms
--               hang a touch differently per worker
--   gestureDelay -> seconds added before this worker's idle gestures, so the
--               three don't all look around / wipe on the same beat
local WORKER_LOOKS = {
	{ -- worker 1: orange-vest guy, light skin tone
		skin   = Color3.fromRGB(255, 224, 196),  -- light human skin
		shirt  = Color3.fromRGB(70, 95, 150),    -- blue work shirt
		pants  = Color3.fromRGB(58, 60, 72),      -- charcoal work trousers
		gloves = Color3.fromRGB(45, 42, 40),      -- dark work gloves
		boots  = Color3.fromRGB(35, 30, 28),      -- brown-black boots
		vest   = Color3.fromRGB(255, 120, 0),     -- bright safety orange
		hat    = Color3.fromRGB(255, 215, 0),     -- hi-vis yellow hat
		idleSpd      = 0.92,
		stance       = -8,
		shoulderRest = 4,
		gestureDelay = 0.0,
	},
	{ -- worker 2: yellow-vest guy, medium-tan skin tone
		skin   = Color3.fromRGB(222, 172, 138),  -- medium human skin
		shirt  = Color3.fromRGB(150, 70, 65),    -- maroon work shirt
		pants  = Color3.fromRGB(72, 66, 54),      -- khaki/olive trousers
		gloves = Color3.fromRGB(60, 48, 36),      -- tan leather gloves
		boots  = Color3.fromRGB(42, 34, 28),      -- tan-brown boots
		vest   = Color3.fromRGB(235, 235, 30),    -- hi-vis yellow
		hat    = Color3.fromRGB(245, 245, 248),   -- white hat (foreman)
		idleSpd      = 1.0,
		stance       = 0,
		shoulderRest = 0,
		gestureDelay = 0.4,
	},
	{ -- worker 3: green-vest guy, deep brown skin tone
		skin   = Color3.fromRGB(140, 96, 66),    -- deep human skin
		shirt  = Color3.fromRGB(55, 75, 110),    -- steel-blue work shirt
		pants  = Color3.fromRGB(48, 52, 58),      -- slate trousers
		gloves = Color3.fromRGB(34, 38, 44),      -- dark grey gloves
		boots  = Color3.fromRGB(26, 28, 32),      -- black boots
		vest   = Color3.fromRGB(60, 230, 90),     -- hi-vis green
		hat    = Color3.fromRGB(220, 45, 45),     -- red hat
		idleSpd      = 1.08,
		stance       = 9,
		shoulderRest = -4,
		gestureDelay = 0.8,
	},
}

-- Reflective-stripe colour shared by all vests: a bright silvery white with a
-- slight glow read. Used for the 2 horizontal hi-vis bands + shoulder straps.
local REFLECTIVE = Color3.fromRGB(238, 240, 245)

--------------------------------------------------------------------
-- Helper: weld a CanCollide=false, Massless detail part rigidly onto a
-- carrier part (so it can never fall off during walk/build/wave and never
-- blocks a player). The part is positioned at carrier.CFrame * offset, then
-- locked there with a WeldConstraint.
--
-- `opts` (optional) tunes the look of a single welded piece:
--   opts.shape        -> Enum.PartType (Ball/Cylinder/Block) for domes & rings
--   opts.reflectance  -> 0..1, used for the reflective hi-vis stripe read
--   opts.transparency -> pass-through for any rare see-through detail
-- Every welded part is CanCollide=false + Massless + firmly WeldConstraint-ed
-- and parented into the worker model, so it never falls off and cleanup() frees
-- it with the model.
--------------------------------------------------------------------
local function weldDetail(parentModel, carrier, name, size, color, mat, offset, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false   -- CRITICAL: dressing never blocks a player
	p.Massless = true      -- never drags the rig physics around
	p.CanTouch = false
	p.CanQuery = false
	if opts.shape then p.Shape = opts.shape end
	if opts.reflectance then p.Reflectance = opts.reflectance end
	if opts.transparency then p.Transparency = opts.transparency end
	p.CFrame = carrier.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = carrier
	w.Part1 = p
	w.Parent = p
	p.Parent = parentModel
	return p
end

--------------------------------------------------------------------
-- Helper: build a construction-worker HumanoidDescription for `look`.
--
-- CLOTHING NOTE: we do NOT set Shirt/Pants/GraphicTshirt asset ids here. We have
-- no construction-uniform texture asset ids we are confident are valid Roblox
-- defaults, and a wrong id renders as a grey/error template. So the uniform is
-- achieved with BODY COLOURS (work-shirt tone on torso/arms, trouser tone on the
-- legs) PLUS the welded hi-vis vest / belt / hat / boot-cuff parts below.
-- LATER UPGRADE: if you obtain a real construction Shirt + Pants (or layered
-- clothing) asset id you trust, set desc.Shirt / desc.Pants here — that is the
-- only change needed to drop a real texture uniform onto every worker.
--------------------------------------------------------------------
local function makeDescription(look)
	local desc = Instance.new("HumanoidDescription")

	-- Body colours map onto the R15 body parts. Skin tone goes on the head; the
	-- arms/torso wear the work-shirt tone (the vest covers most of the torso);
	-- the legs wear the trouser tone (boots/gloves are recoloured afterwards).
	desc.HeadColor       = look.skin
	desc.TorsoColor      = look.shirt
	desc.LeftArmColor    = look.shirt   -- sleeves (forearms become gloves below)
	desc.RightArmColor   = look.shirt
	desc.LeftLegColor    = look.pants   -- work trousers
	desc.RightLegColor   = look.pants

	-- No bundle/face/accessory asset ids (we have none we trust). The construction
	-- look is body colours + welded parts; see CLOTHING NOTE above.
	return desc
end

--------------------------------------------------------------------
-- Helper: recolour individual R15 body parts AFTER the rig is created so we
-- can give distinct gloves (hands) and boots (feet) on top of the base body
-- colours. R15 hand parts are "LeftHand"/"RightHand", feet are
-- "LeftFoot"/"RightFoot". Lower legs read as the lower trouser/boot shaft.
--------------------------------------------------------------------
local function recolorExtremities(model, look)
	local function setColor(partName, color, mat)
		local part = model:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Color = color
			if mat then part.Material = mat end
		end
	end
	-- Gloves = coloured hands (matte fabric/leather read).
	setColor("LeftHand", look.gloves, Enum.Material.Fabric)
	setColor("RightHand", look.gloves, Enum.Material.Fabric)
	-- Boots = coloured feet + lower legs (the boot shaft), chunky leather read.
	setColor("LeftFoot", look.boots, Enum.Material.Leather)
	setColor("RightFoot", look.boots, Enum.Material.Leather)
	setColor("LeftLowerLeg", look.boots, Enum.Material.Leather)
	setColor("RightLowerLeg", look.boots, Enum.Material.Leather)
end

--------------------------------------------------------------------
-- Helper: load + play a default R15 animation track on a Humanoid's Animator.
-- Returns the AnimationTrack (or nil) so callers can stop it later.
--------------------------------------------------------------------
local function playAnim(humanoid, animId, speed)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		-- A real Humanoid auto-creates an Animator, but make sure.
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Looped = true
		track:Play()
		-- Slight per-worker speed variation so the 3 idles aren't lock-step.
		if speed then track:AdjustSpeed(speed) end
		return track
	end
	return nil
end

--------------------------------------------------------------------
-- Helper: build ONE real R15 construction worker.
--
-- HOW IT'S BUILT:
--   1. CreateHumanoidModelFromDescription -> a genuine R15 character with a
--      Humanoid, correct proportions and the standard R15 Motor6D joints.
--   2. Recolour extremities (gloves = hands, boots = feet/lower legs).
--   3. Weld on a hard HAT (dome + brim) to the Head, a hi-vis VEST (front +
--      back panel) to the UpperTorso, and a HAMMER (handle + head) into the
--      RIGHT HAND.
--   4. Cache the RightShoulder Motor6D (in RightUpperArm) and the Neck Motor6D
--      (in Head) plus their rest C0s — those are the only joints we animate.
--
-- The model is positioned (PivotTo) at the spawn offset so it walks in from
-- there. While walking the legs collide with the ground (normal walk); we
-- plant it (anchor root + CanCollide off) on arrival in spawn().
--------------------------------------------------------------------
local function makeWorker(index, spawnPos)
	local look = WORKER_LOOKS[index] or WORKER_LOOKS[1]

	-- 1) REAL R15 rig from a HumanoidDescription (server-callable).
	-- RESILIENCE: CreateHumanoidModelFromDescription is web-backed and can FAIL / time out on LIVE
	-- servers (it works in Studio because it's locally cached). Wrap it so a failure logs a warn and
	-- returns nil — it must NOT error up through spawn() and abort the whole event. The rocket still
	-- builds without this worker.
	local desc = makeDescription(look)
	local okRig, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not okRig or not model then
		warn("[RocketNPCs] worker rig failed: " .. tostring(model))
		return nil
	end
	model.Name = "RocketWorker_" .. index
	-- STREAMING FIX: each R15 worker rig (a Model) is itself Persistent, so it replicates to EVERY
	-- client regardless of distance (explicit per-rig safety alongside the parent container's Persistent).
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = npcFolder

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	local upperTorso = model:FindFirstChild("UpperTorso")
	local lowerTorso = model:FindFirstChild("LowerTorso")  -- waist (tool belt)
	local rightHand = model:FindFirstChild("RightHand")
	local leftHand = model:FindFirstChild("LeftHand")
	local rightUpperArm = model:FindFirstChild("RightUpperArm")
	local leftLowerLeg = model:FindFirstChild("LeftLowerLeg")    -- boot cuff
	local rightLowerLeg = model:FindFirstChild("RightLowerLeg")  -- boot cuff

	-- 2) Distinct gloves/boots on top of the description's body colours.
	recolorExtremities(model, look)

	-- Place the rig at its spawn position (feet roughly on the ground). The
	-- HumanoidRootPart sits ~3 studs above the feet on a default R15 rig.
	model:PivotTo(CFrame.new(spawnPos + Vector3.new(0, 3, 0)))

	-- 3a) HARD HAT: a real hard-hat shape welded to the HEAD so it turns with the
	-- head when the Neck Motor6D animates. Built from welded pieces:
	--   * DOME  : a half-sphere (flattened ball) shell that fits OVER the top of
	--             the head and RESTS on the crown (not floating above it). A
	--             default R15 Head is ~1.2 studs tall/wide; the dome is ~1.5 wide
	--             and only ~0.8 tall, so it caps the crown like a real shell.
	--   * RIDGE : a thin centre ridge running front-to-back along the crown.
	--   * BRIM  : a thin FLAT disc encircling the bottom edge of the dome (a real
	--             hard-hat brim), laid flat so it reads as the peak all round.
	--   * PEAK  : a slightly forward extension of the brim so the front peak reads.
	-- The head's local origin is its centre; +Y ~0.6 reaches the crown. We sit the
	-- dome with its base around the crown so it rests ON the head.
	-- Classic hi-vis hat colour (the per-worker `look.hat`), lightly glossy.
	weldDetail(model, head, "HardHatDome",
		Vector3.new(1.5, 0.82, 1.5), look.hat, Enum.Material.SmoothPlastic,
		CFrame.new(0, 0.62, 0), { shape = Enum.PartType.Ball })
	-- Centre ridge: a thin raised strip along the top of the dome (front->back).
	weldDetail(model, head, "HardHatRidge",
		Vector3.new(0.16, 0.24, 1.42), look.hat, Enum.Material.SmoothPlastic,
		CFrame.new(0, 0.82, 0))
	-- Thin FLAT brim disc circling the bottom edge of the dome (the all-round
	-- hard-hat brim). A flat cylinder, rotated 90deg about X so its round face
	-- points up, sitting at the dome's base just above the brow.
	weldDetail(model, head, "HardHatBrim",
		Vector3.new(0.14, 1.95, 1.95), look.hat, Enum.Material.SmoothPlastic,
		-- FLAT horizontal brim: rotate about Z so the cylinder's AXIS points UP (round faces up/down).
		-- The OLD rotation was about X, which left the axis pointing left/right -> a VERTICAL disc that
		-- cut a ring straight through the head. Now it lies flat at the dome's bottom edge (the brow).
		CFrame.new(0, 0.32, 0) * CFrame.Angles(0, 0, math.rad(90)),
		{ shape = Enum.PartType.Cylinder })
	-- Front PEAK: a small flat slab pushed forward of the brim so the classic
	-- hard-hat front peak reads clearly.
	weldDetail(model, head, "HardHatPeak",
		Vector3.new(1.2, 0.14, 0.5), look.hat, Enum.Material.SmoothPlastic,
		CFrame.new(0, 0.32, -0.95))

	-- 3b) HI-VIS VEST: a wrap of welded panels on the UpperTorso forming a proper
	-- vest, slightly glossy so the reflective bands pop:
	--   * FRONT + BACK + two SIDE panels  -> the bright hi-vis body of the vest
	--   * 2 horizontal REFLECTIVE BANDS (upper + lower) wrapping front/back
	--   * 2 REFLECTIVE SHOULDER STRAPS over the shoulders
	-- Vest base is faintly glossy (low reflectance) so the silver bands read.
	local vestOpts = { reflectance = 0.04 }
	weldDetail(model, upperTorso, "VestFront",
		Vector3.new(2.15, 1.75, 0.28), look.vest, Enum.Material.SmoothPlastic,
		CFrame.new(0, 0, -0.56), vestOpts)
	weldDetail(model, upperTorso, "VestBack",
		Vector3.new(2.15, 1.75, 0.28), look.vest, Enum.Material.SmoothPlastic,
		CFrame.new(0, 0, 0.56), vestOpts)
	weldDetail(model, upperTorso, "VestSideL",
		Vector3.new(0.28, 1.75, 1.1), look.vest, Enum.Material.SmoothPlastic,
		CFrame.new(-1.0, 0, 0), vestOpts)
	weldDetail(model, upperTorso, "VestSideR",
		Vector3.new(0.28, 1.75, 1.1), look.vest, Enum.Material.SmoothPlastic,
		CFrame.new(1.0, 0, 0), vestOpts)
	-- 2 horizontal REFLECTIVE BANDS (silver/white, glossy) wrapping the vest:
	-- one upper (chest) and one lower (belly), on both the front and the back.
	local bandOpts = { reflectance = 0.35 }
	for _, by in ipairs({ 0.42, -0.42 }) do  -- upper then lower band height
		weldDetail(model, upperTorso, "VestBandFront",
			Vector3.new(2.18, 0.3, 0.32), REFLECTIVE, Enum.Material.SmoothPlastic,
			CFrame.new(0, by, -0.57), bandOpts)
		weldDetail(model, upperTorso, "VestBandBack",
			Vector3.new(2.18, 0.3, 0.32), REFLECTIVE, Enum.Material.SmoothPlastic,
			CFrame.new(0, by, 0.57), bandOpts)
	end
	-- 2 REFLECTIVE SHOULDER STRAPS (front-to-back over each shoulder).
	weldDetail(model, upperTorso, "VestStrapL",
		Vector3.new(0.3, 0.32, 1.2), REFLECTIVE, Enum.Material.SmoothPlastic,
		CFrame.new(-0.62, 0.78, 0), bandOpts)
	weldDetail(model, upperTorso, "VestStrapR",
		Vector3.new(0.3, 0.32, 1.2), REFLECTIVE, Enum.Material.SmoothPlastic,
		CFrame.new(0.62, 0.78, 0), bandOpts)

	-- 3c) TOOL BELT: a thin dark belt wrapping the LowerTorso (waist) with a
	-- buckle and 1-2 small pouches/tools hanging off it. Welded to the waist so
	-- it rides with the body. (Guarded in case LowerTorso is ever missing.)
	if lowerTorso then
		weldDetail(model, lowerTorso, "ToolBelt",
			Vector3.new(2.2, 0.34, 1.25), Color3.fromRGB(48, 34, 26), Enum.Material.Leather,
			CFrame.new(0, 0.15, 0))
		-- Brass buckle at the front centre.
		weldDetail(model, lowerTorso, "BeltBuckle",
			Vector3.new(0.38, 0.32, 0.14), Color3.fromRGB(196, 158, 70), Enum.Material.Metal,
			CFrame.new(0, 0.15, -0.62), { reflectance = 0.15 })
		-- A small tool POUCH on the right hip.
		weldDetail(model, lowerTorso, "BeltPouchR",
			Vector3.new(0.5, 0.55, 0.4), Color3.fromRGB(58, 42, 32), Enum.Material.Leather,
			CFrame.new(0.62, -0.05, -0.5))
		-- A wrench-ish loop tool on the left hip (a short grey bar).
		weldDetail(model, lowerTorso, "BeltToolL",
			Vector3.new(0.18, 0.7, 0.18), Color3.fromRGB(120, 124, 132), Enum.Material.Metal,
			CFrame.new(-0.62, -0.1, -0.45), { reflectance = 0.1 })
	end

	-- 3d) GLOVE CUFFS: a thin cuff ring at each wrist so the work gloves (the
	-- recoloured hands) read as gloves rather than bare hands. Welded to hands.
	if leftHand then
		weldDetail(model, leftHand, "GloveCuffL",
			Vector3.new(0.85, 0.28, 0.85), look.gloves, Enum.Material.Fabric,
			CFrame.new(0, 0.45, 0))
	end
	if rightHand then
		weldDetail(model, rightHand, "GloveCuffR",
			Vector3.new(0.85, 0.28, 0.85), look.gloves, Enum.Material.Fabric,
			CFrame.new(0, 0.45, 0))
	end

	-- 3e) BOOT CUFFS: a thin chunky cuff ring near the top of each boot shaft
	-- (the recoloured lower legs) so the boots read as sturdy work boots.
	if leftLowerLeg then
		weldDetail(model, leftLowerLeg, "BootCuffL",
			Vector3.new(0.95, 0.3, 0.95), look.boots, Enum.Material.Leather,
			CFrame.new(0, 0.45, 0))
	end
	if rightLowerLeg then
		weldDetail(model, rightLowerLeg, "BootCuffR",
			Vector3.new(0.95, 0.3, 0.95), look.boots, Enum.Material.Leather,
			CFrame.new(0, 0.45, 0))
	end

	-- 3f) HAMMER: wooden handle + dark metal head, welded into the RIGHT HAND so
	-- it follows the arm when the RightShoulder Motor6D swings. The hammer head
	-- points forward (-Z) so a raise->strike pitch drives it down/forward.
	weldDetail(model, rightHand, "HammerHandle",
		Vector3.new(0.25, 1.7, 0.25), Color3.fromRGB(140, 95, 55), Enum.Material.Wood,
		CFrame.new(0, -0.6, -0.2))
	weldDetail(model, rightHand, "HammerHead",
		Vector3.new(0.5, 0.5, 1.05), Color3.fromRGB(70, 72, 80), Enum.Material.Metal,
		CFrame.new(0, -1.35, -0.2), { reflectance = 0.08 })

	-- 4) Cache the two Motor6Ds we hand-animate, plus their REST C0s so the
	-- animation code can lerp from a known neutral pose.
	--   * RightShoulder lives in RightUpperArm on an R15 rig (Part0=UpperTorso).
	--   * Neck lives in Head (Part0=UpperTorso).
	local shoulderMotor = rightUpperArm and rightUpperArm:FindFirstChild("RightShoulder")
	local neckMotor = head and head:FindFirstChild("Neck")

	-- Bake a SMALL per-worker resting stance offset into the cached rest C0s, so
	-- the three workers don't all stand dead-identical (one looks slightly off to
	-- one side, arms hang a touch differently). All animation (hammer/idle/wave)
	-- lerps from these rest C0s, so the variation persists naturally and is also
	-- restored after every gesture.
	local stanceYaw = math.rad(look.stance or 0)        -- neck resting yaw
	local shoulderHang = math.rad(look.shoulderRest or 0) -- arm resting pitch

	local shoulderRestC0 = shoulderMotor and (shoulderMotor.C0 * CFrame.Angles(shoulderHang, 0, 0)) or CFrame.new()
	local neckRestC0 = neckMotor and (neckMotor.C0 * CFrame.Angles(0, stanceYaw, 0)) or CFrame.new()

	-- Apply the resting offsets immediately so the planted pose shows them.
	if shoulderMotor then shoulderMotor.C0 = shoulderRestC0 end
	if neckMotor then neckMotor.C0 = neckRestC0 end

	-- Return the rig table. Keys match what build/idle/wave/cleanup rely on:
	--   model, humanoid, root, head, the two Motor6Ds + rest C0s, anim tracks,
	--   and the alive/fallen/paused flags.
	return {
		model = model,
		humanoid = humanoid,
		root = root,
		head = head,
		shoulderMotor = shoulderMotor,
		shoulderRestC0 = shoulderRestC0,
		neckMotor = neckMotor,
		neckRestC0 = neckRestC0,
		walkTrack = nil,
		idleTrack = nil,
		planted = false,
		alive = true,
		fallen = false,
		paused = false,
		-- Per-worker presence variation (read by plantWorker/idle).
		idleSpd = look.idleSpd or 1.0,        -- idle anim playback speed
		gestureDelay = look.gestureDelay or 0, -- stagger idle gestures
	}
end

--------------------------------------------------------------------
-- Helper: PLANT a worker on arrival.
--
-- COLLISION TRADEOFF: while walking in we WANT the legs to collide with the
-- ground (so the Humanoid walks normally). Once arrived, we flip the worker to
-- a static planted actor: anchor the HumanoidRootPart (so physics/players can
-- never shove it) and turn CanCollide OFF on every part (so a planted worker
-- can't block, trap or knock a player on island 1). We then stop the walk
-- animation and start the idle animation.
--------------------------------------------------------------------
local function plantWorker(worker)
	if worker.planted or not worker.alive then return end
	worker.planted = true

	local model = worker.model
	if not model or not model.Parent then return end

	-- Anchor the root so nothing can push the planted worker around, and ORIENT
	-- it to FACE the rocket (site centre) so the worker hammers toward the rocket.
	-- We keep the root's current (standoff-ring) position and only rotate it to
	-- look at the site — the body stays ~WORKER_STANDOFF studs out, never moving
	-- toward the rocket.
	if worker.root then
		if sitePos then
			local rootPos = worker.root.Position
			-- Look at the site centre on the flat plane (keep our own Y level).
			local lookTarget = Vector3.new(sitePos.X, rootPos.Y, sitePos.Z)
			if (lookTarget - rootPos).Magnitude > 0.01 then
				worker.root.CFrame = CFrame.lookAt(rootPos, lookTarget)
			end
		end
		worker.root.Anchored = true
	end
	-- Non-colliding everywhere (welded dressing was already CanCollide=false).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end

	-- Swap walk -> idle animation.
	if worker.walkTrack then
		worker.walkTrack:Stop()
		worker.walkTrack = nil
	end
	if worker.humanoid and not worker.idleTrack then
		-- Natural default idle, at this worker's slightly-varied playback speed so
		-- the three breathing/idle loops aren't lock-step identical.
		worker.idleTrack = playAnim(worker.humanoid, IDLE_ANIM_ID, worker.idleSpd)
	end
end

--------------------------------------------------------------------
-- Helper: walk a worker IN to a target ground position using the real
-- Humanoid pathing (Humanoid:MoveTo) so we get genuine R15 walking + the walk
-- animation. We listen on Humanoid.MoveToFinished to plant on arrival, and as
-- a safety net also poll distance on Heartbeat (MoveToFinished can fire false
-- if the path is interrupted). Both routes converge on plantWorker().
--------------------------------------------------------------------
local function walkIn(worker, targetPos)
	local humanoid = worker.humanoid
	local root = worker.root
	if not humanoid or not root then
		-- No humanoid (shouldn't happen) — just plant where it stands.
		plantWorker(worker)
		return
	end

	-- Start the walk animation while moving.
	worker.walkTrack = playAnim(humanoid, WALK_ANIM_ID)

	-- Kick off the real walk.
	humanoid:MoveTo(targetPos)

	-- Plant when the Humanoid reports arrival.
	local moveConn
	moveConn = humanoid.MoveToFinished:Connect(function(reached)
		if moveConn then moveConn:Disconnect() end
		plantWorker(worker)
	end)
	table.insert(actionLoops, moveConn)

	-- Safety-net distance check: if MoveTo stalls or MoveToFinished misfires,
	-- plant once we're close enough. Also re-issues MoveTo so the worker keeps
	-- heading to the spot (MoveTo times out after ~8s otherwise).
	local t0 = os.clock()
	local distConn
	distConn = RunService.Heartbeat:Connect(function()
		if not worker.alive or worker.planted or not root.Parent then
			distConn:Disconnect()
			return
		end
		local flat = (root.Position - (targetPos + Vector3.new(0, root.Position.Y - targetPos.Y, 0)))
		flat = Vector3.new(flat.X, 0, flat.Z)
		if flat.Magnitude <= 3 then
			distConn:Disconnect()
			plantWorker(worker)
		elseif os.clock() - t0 > 4 then
			-- Re-issue MoveTo periodically so the Humanoid doesn't give up.
			t0 = os.clock()
			humanoid:MoveTo(targetPos)
		end
	end)
	table.insert(actionLoops, distConn)
end

--------------------------------------------------------------------
-- Helper: build the construction-site SET DRESSING around the pad.
--
-- CRITICAL: this dressing must STAY ON ISLAND 1. It is parented into its OWN
-- Folder ("RocketSiteDressing") in workspace — NEVER into the rocket model
-- (that model lifts off and explodes). cleanup() destroys this folder.
--
-- Everything here is Anchored (it just sits on the ground), CanCollide=false
-- and Massless so it can never block, trap or knock a player. We place items
-- as a loose ring around the pad, well clear of where the workers stand.
--------------------------------------------------------------------
local function buildSiteDressing(site)
	-- STREAMING FIX: a MODEL (not a Folder) so it can be marked Persistent (ModelStreamingMode is a
	-- Model-only property). Persistent => its plain dressing parts replicate to EVERY client regardless
	-- of streaming distance (plain parts under a Folder would otherwise stream by position). Set BEFORE
	-- adding children so every dressing part is included. (Used/destroyed exactly like the old folder.)
	dressingFolder = Instance.new("Model")
	dressingFolder.Name = "RocketSiteDressing"
	dressingFolder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	dressingFolder.Parent = workspace

	-- Local helper: an anchored, non-colliding dressing part placed by a CFrame
	-- offset relative to the site (which sits roughly at ground level). The
	-- offset is applied in world space so Y is always "up off the ground".
	local function dress(name, size, color, mat, offsetCF)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Anchored = true        -- sits on the ground; never driven/jointed
		p.CanCollide = false      -- CRITICAL: never blocks a player
		p.Massless = true
		p.CanTouch = false
		p.CanQuery = false
		-- Translate the site by the offset's position, then apply its rotation.
		p.CFrame = CFrame.new(site + offsetCF.Position) * (offsetCF - offsetCF.Position)
		p.Parent = dressingFolder
		return p
	end

	-- Shared scaffold colours/material.
	local TUBE   = Color3.fromRGB(150, 152, 160)  -- metal-grey scaffold tube
	local PLANK  = Color3.fromRGB(168, 124, 72)   -- wooden walkway plank
	local TUBE_M = Enum.Material.Metal
	local WOOD_M = Enum.Material.Wood

	-- ======================================================================
	-- SCAFFOLDING TOWER (launch gantry) — stands well to one SIDE of the
	-- rocket so it never clips the rocket body/fins. The rocket's fins reach
	-- ~21 studs from centre, so we keep the scaffold's NEAR face JUST past that:
	-- its footprint is centred at SCAFF_X (-28) and is ~10 studs wide, so the
	-- closest post sits ~23 studs from centre — a small ~2-stud gap from the fins,
	-- framing the rocket like a gantry standing right beside it (never clipping it).
	-- The tower is a sturdy multi-tier tube frame: 4 corner posts, horizontal
	-- rails on 3 tiers, diagonal X cross-braces between posts, wooden plank
	-- walkways on 2 levels, base plates/feet, a top guard rail, and a side ladder.
	-- ======================================================================
	local SCAFF_X = -28          -- scaffold footprint centre, offset out to the side (brought closer)
	local SCAFF_Z = 0
	local HW = 5                 -- half-width of the square footprint (10x10 base)
	local TIER_H = 6             -- height of each tier
	local TIERS  = 3             -- number of tiers (multi-level)
	local POST_H = TIER_H * TIERS  -- total post height (18)
	local TUBE_T = 0.4           -- tube thickness

	-- Corner XZ positions (relative to scaffold centre).
	local corners = { {-HW, -HW}, {HW, -HW}, {-HW, HW}, {HW, HW} }

	-- --- 4 vertical corner posts (full height) ---
	for _, c in ipairs(corners) do
		dress("ScaffoldPost", Vector3.new(TUBE_T, POST_H, TUBE_T), TUBE, TUBE_M,
			CFrame.new(SCAFF_X + c[1], POST_H / 2, SCAFF_Z + c[2]))
		-- Base plate / foot where each post meets the ground.
		dress("ScaffoldFoot", Vector3.new(1.3, 0.3, 1.3), Color3.fromRGB(110, 112, 120), TUBE_M,
			CFrame.new(SCAFF_X + c[1], 0.15, SCAFF_Z + c[2]))
	end

	-- --- Horizontal rails on each tier (a ring tying the 4 posts) ---
	for tier = 1, TIERS do
		local y = tier * TIER_H
		-- Rails along X (front + back edges).
		dress("ScaffoldRail", Vector3.new(HW * 2, TUBE_T, TUBE_T), TUBE, TUBE_M,
			CFrame.new(SCAFF_X, y, SCAFF_Z - HW))
		dress("ScaffoldRail", Vector3.new(HW * 2, TUBE_T, TUBE_T), TUBE, TUBE_M,
			CFrame.new(SCAFF_X, y, SCAFF_Z + HW))
		-- Rails along Z (left + right edges).
		dress("ScaffoldRail", Vector3.new(TUBE_T, TUBE_T, HW * 2), TUBE, TUBE_M,
			CFrame.new(SCAFF_X - HW, y, SCAFF_Z))
		dress("ScaffoldRail", Vector3.new(TUBE_T, TUBE_T, HW * 2), TUBE, TUBE_M,
			CFrame.new(SCAFF_X + HW, y, SCAFF_Z))
	end

	-- --- Diagonal X cross-braces between posts (classic crossed supports) ---
	-- A brace spans one tier's height across the face width; length = hypotenuse.
	local braceLen = math.sqrt((HW * 2) ^ 2 + TIER_H ^ 2)
	local braceTilt = math.atan2(TIER_H, HW * 2)  -- tilt of the brace from horizontal
	-- Build crossed braces on the two visible side faces (the two Z-edges), one
	-- X-cross per tier — the classic crossed supports running up the tower.
	for tier = 1, TIERS do
		local yMid = (tier - 0.5) * TIER_H
		for _, sz in ipairs({ -HW, HW }) do
			-- Two diagonals crossing each other (mirror the tilt) across X.
			dress("ScaffoldBrace", Vector3.new(braceLen, TUBE_T * 0.7, TUBE_T * 0.7), TUBE, TUBE_M,
				CFrame.new(SCAFF_X, yMid, SCAFF_Z + sz) * CFrame.Angles(0, 0, braceTilt))
			dress("ScaffoldBrace", Vector3.new(braceLen, TUBE_T * 0.7, TUBE_T * 0.7), TUBE, TUBE_M,
				CFrame.new(SCAFF_X, yMid, SCAFF_Z + sz) * CFrame.Angles(0, 0, -braceTilt))
		end
	end

	-- --- Wooden plank WALKWAYS on 2 levels (several planks side-by-side) ---
	-- Lay 4 planks across each walkway level so it reads as a real deck, not one
	-- board. Levels at tier 1 (lower deck) and tier 3 (top deck).
	for _, lvl in ipairs({ 1, TIERS }) do
		local y = lvl * TIER_H + TUBE_T / 2 + 0.15
		local nPlanks = 3
		local plankW = (HW * 2) / nPlanks
		for p = 0, nPlanks - 1 do
			local px = SCAFF_X - HW + plankW * (p + 0.5)
			dress("ScaffoldPlank", Vector3.new(plankW - 0.1, 0.3, HW * 2 - 0.4), PLANK, WOOD_M,
				CFrame.new(px, y, SCAFF_Z))
		end
	end

	-- --- Top GUARD RAIL along the top walkway (a waist-high rail above deck) ---
	local guardY = POST_H + 1.6
	dress("ScaffoldGuard", Vector3.new(HW * 2, TUBE_T, TUBE_T), TUBE, TUBE_M,
		CFrame.new(SCAFF_X, guardY, SCAFF_Z - HW))
	dress("ScaffoldGuard", Vector3.new(HW * 2, TUBE_T, TUBE_T), TUBE, TUBE_M,
		CFrame.new(SCAFF_X, guardY, SCAFF_Z + HW))
	dress("ScaffoldGuard", Vector3.new(TUBE_T, TUBE_T, HW * 2), TUBE, TUBE_M,
		CFrame.new(SCAFF_X - HW, guardY, SCAFF_Z))
	-- Short guard posts extending the corner posts up to the guard rail (3 sides).
	for _, c in ipairs({ {-HW, -HW}, {HW, -HW}, {-HW, HW} }) do
		dress("ScaffoldGuardPost", Vector3.new(TUBE_T, guardY - POST_H, TUBE_T), TUBE, TUBE_M,
			CFrame.new(SCAFF_X + c[1], (POST_H + guardY) / 2, SCAFF_Z + c[2]))
	end

	-- --- Simple LADDER up one side (two rails + rungs), on the outer (-X) face ---
	local ladderX = SCAFF_X - HW - 0.5
	for _, rz in ipairs({ -0.6, 0.6 }) do
		dress("LadderRail", Vector3.new(0.2, POST_H, 0.2), Color3.fromRGB(130, 132, 140), TUBE_M,
			CFrame.new(ladderX, POST_H / 2, SCAFF_Z + rz))
	end
	for rung = 1, 5 do
		dress("LadderRung", Vector3.new(0.2, 0.18, 1.4), Color3.fromRGB(130, 132, 140), TUBE_M,
			CFrame.new(ladderX, rung * (POST_H / 6), SCAFF_Z))
	end

	-- ======================================================================
	-- WORK-SITE DRESSING scattered around the site (clear of the workers'
	-- standoff ring and the scaffold). Toolboxes, crates, cones, a barrel.
	-- ======================================================================

	-- ---- CRATES: a couple of scattered wooden crates ----
	dress("Crate", Vector3.new(3, 3, 3), Color3.fromRGB(150, 110, 65),
		Enum.Material.WoodPlanks, CFrame.new(17, 1.5, -14) * CFrame.Angles(0, math.rad(15), 0))
	dress("Crate", Vector3.new(2.6, 2.6, 2.6), Color3.fromRGB(135, 98, 58),
		Enum.Material.WoodPlanks, CFrame.new(18, 1.3, -16) * CFrame.Angles(0, math.rad(-20), 0))

	-- ---- BARREL: an upright cylinder drum with a darker rim ----
	local barrel = dress("Barrel", Vector3.new(3.2, 2.6, 2.6), Color3.fromRGB(60, 130, 175),
		Enum.Material.Metal, CFrame.new(-16, 1.3, 16) * CFrame.Angles(0, 0, math.rad(90)))
	barrel.Shape = Enum.PartType.Cylinder
	local barrelRim = dress("BarrelRim", Vector3.new(0.4, 2.7, 2.7), Color3.fromRGB(40, 95, 130),
		Enum.Material.Metal, CFrame.new(-17.5, 1.3, 16) * CFrame.Angles(0, 0, math.rad(90)))
	barrelRim.Shape = Enum.PartType.Cylinder

	-- ---- SAFETY CONES: a few orange cones marking the site edge ----
	-- A cone = a flat base plate + a tapered cylinder body + a white stripe.
	for _, pos in ipairs({ Vector3.new(12, 0, 16), Vector3.new(-12, 0, 16) }) do
		dress("ConeBase", Vector3.new(1.4, 0.25, 1.4), Color3.fromRGB(255, 95, 0),
			Enum.Material.SmoothPlastic, CFrame.new(pos.X, 0.12, pos.Z))
		-- Cylinder stood upright (rotate 90° on Z) reads as a cone body.
		local coneBody = dress("Cone", Vector3.new(1.6, 1, 1), Color3.fromRGB(255, 110, 0),
			Enum.Material.SmoothPlastic, CFrame.new(pos.X, 1.0, pos.Z) * CFrame.Angles(0, 0, math.rad(90)))
		coneBody.Shape = Enum.PartType.Cylinder
		local coneStripe = dress("ConeStripe", Vector3.new(1.05, 1.04, 1.04), Color3.fromRGB(245, 245, 245),
			Enum.Material.SmoothPlastic, CFrame.new(pos.X, 1.2, pos.Z) * CFrame.Angles(0, 0, math.rad(90)))
		coneStripe.Shape = Enum.PartType.Cylinder
	end

	-- ---- TOOLBOXES: two small boxes with dark lids, near the crates ----
	for _, t in ipairs({ {14, -18, -9, Color3.fromRGB(190, 45, 45)}, {17, -15, 17, Color3.fromRGB(45, 95, 190)} }) do
		dress("Toolbox", Vector3.new(2.4, 1.1, 1.3), t[4],
			Enum.Material.Metal, CFrame.new(t[1], 0.55, t[2]) * CFrame.Angles(0, math.rad(t[3]), 0))
		dress("ToolboxLid", Vector3.new(2.45, 0.3, 1.35), Color3.fromRGB(60, 60, 65),
			Enum.Material.Metal, CFrame.new(t[1], 1.2, t[2]) * CFrame.Angles(0, math.rad(t[3]), 0))
	end
end

--======================================================================
-- spawn(site): create 3 REAL R15 workers and walk them in from staggered
-- offsets to the site using Humanoid:MoveTo (real pathing + walk anim).
--======================================================================
function RocketNPCs.spawn(site)
	sitePos = site
	workers = {}
	actionLoops = {}

	-- STREAMING FIX: a MODEL (not a Folder) so it can be marked Persistent — ModelStreamingMode is a
	-- Model-only property. Persistent => this container + its descendants (the worker rigs) replicate to
	-- EVERY client regardless of streaming distance. Set BEFORE adding children so they're all included.
	-- (Still used/destroyed exactly like the old folder — only the class + streaming mode changed.)
	npcFolder = Instance.new("Model")
	npcFolder.Name = "RocketEventNPCs"
	npcFolder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	npcFolder.Parent = workspace

	-- Build the static set dressing (in its OWN folder — stays on island 1).
	buildSiteDressing(site)

	for i = 1, 3 do
		local spawnPos = site + (SPAWN_OFFSETS[i] or Vector3.new(0, 0, 0))
		-- RESILIENCE: a single worker failing must NOT break the loop or abort the event. pcall each
		-- makeWorker; on failure (or a nil rig from the inner pcall), log + skip and continue with the
		-- rest. The event proceeds with however many workers DID spawn (0, 1, 2 or all 3).
		local okW, worker = pcall(makeWorker, i, spawnPos)
		if not okW then
			warn("[RocketNPCs] worker " .. i .. " spawn failed: " .. tostring(worker))
		elseif worker then
			table.insert(workers, worker)  -- only real rigs go in the list (consumers use ipairs)
			-- Walk to their work position with the real Humanoid (legs collide with
			-- the ground while walking; planted non-colliding on arrival).
			local workPos = site + (WORK_OFFSETS[i] or Vector3.new(0, 0, 0))
			walkIn(worker, workPos)
		end
	end
end

--======================================================================
-- build(): hammer animation loop.
--
-- THE SWING: we animate ONLY the right-shoulder Motor6D's C0. On an R15 rig the
-- "RightShoulder" Motor6D lives in RightUpperArm (Part0 = UpperTorso, Part1 =
-- RightUpperArm). Rotating its C0 about the joint's local X axis pitches the
-- whole arm forward/back about the shoulder. The HumanoidRootPart is anchored
-- (planted) and we never touch the torso, legs, head or left arm — so the body
-- stays PERFECTLY PLANTED and only the right arm + the welded hammer move.
--
-- The cycle is a raise->strike toward the rocket:
--   * raised pose pitches the arm back/up,
--   * strike pose swings it forward/down (the hit).
-- We lerp C0 between those poses on a sine so it reads as repeated hammering.
-- A per-worker phase desyncs the three hammers. We wait until the worker is
-- planted so we don't fight the walk animation.
--======================================================================
function RocketNPCs.build()
	for _, worker in ipairs(workers) do
		if worker.alive and worker.shoulderMotor then
			local motor = worker.shoulderMotor
			local restC0 = worker.shoulderRestC0
			local phase = math.random() * math.pi * 2 -- desync the hammers
			-- Pure rotations applied ON TOP of the rest C0 (which already places
			-- the shoulder joint). Negative X pitches back/up, positive X swings
			-- forward/down toward the rocket.
			local raisedAngle = math.rad(-70) -- back/up (ready)
			local strikeAngle = math.rad(25)  -- forward/down (the hit)
			local conn
			conn = RunService.Heartbeat:Connect(function()
				-- Stop if the worker is gone, has fallen, or is paused (idle()).
				-- Also wait until planted so the swing doesn't fight the walk-in.
				if not worker.alive or worker.fallen or worker.paused
					or not worker.planted or not motor.Parent then
					if not worker.alive or worker.fallen or not motor.Parent then
						if conn then conn:Disconnect() end
					end
					return
				end
				-- 0..1 sine drives the blend between raised and strike each cycle.
				local s = (math.sin(os.clock() * 6 + phase) + 1) * 0.5
				-- EASE the blend so the swing accelerates into the strike and eases
				-- out of the raise (smootherstep) instead of a linear/robotic lerp.
				local e = s * s * s * (s * (s * 6 - 15) + 10)
				local pitch = raisedAngle + (strikeAngle - raisedAngle) * e
				-- Apply ONLY to this joint's C0 — rotate about local X (pitch).
				motor.C0 = restC0 * CFrame.Angles(pitch, 0, 0)
			end)
			table.insert(actionLoops, conn)
		end
	end
end

--======================================================================
-- idle(): personality — SUBTLE and SEPARATE from the hammer swing.
-- One of three short one-shots per worker:
--   * look around : rotate ONLY the Neck Motor6D's C0 (head yaws L/R/centre)
--   * wipe forehead : briefly raise the right arm to the brow, then back
--   * pause : hold the hammer swing for a beat (build() checks worker.paused)
-- None of these moves the body/root. Call periodically during construction.
--======================================================================
function RocketNPCs.idle()
	for _, worker in ipairs(workers) do
		if worker.alive and not worker.fallen and math.random() < 0.5 then
			task.spawn(function()
				-- Stagger gestures per worker so the 3 don't look around / wipe on
				-- the exact same beat (plus a tiny random jitter for life).
				task.wait((worker.gestureDelay or 0) + math.random() * 0.25)
				if not worker.alive or worker.fallen then return end
				local roll = math.random(1, 3)
				if roll == 1 and worker.neckMotor then
					-- LOOK AROUND: rotate ONLY the Neck Motor6D's C0 (yaw the head
					-- left, right, then back to centre). Body + hammer keep going.
					local motor = worker.neckMotor
					local rest = worker.neckRestC0
					for _, ang in ipairs({ -0.5, 0.5, 0 }) do
						if not worker.alive or not motor.Parent then break end
						motor.C0 = rest * CFrame.Angles(0, ang, 0)
						task.wait(0.35)
					end
				elseif roll == 2 and worker.shoulderMotor then
					-- WIPE FOREHEAD: pause the hammer loop, lift the right arm up to
					-- the brow (a big back/up pitch + slight inward roll), hold,
					-- then release back to the swing. Only the RightShoulder C0.
					worker.paused = true
					local motor = worker.shoulderMotor
					local rest = worker.shoulderRestC0
					motor.C0 = rest * CFrame.Angles(math.rad(-120), 0, math.rad(20))
					task.wait(0.5)
					-- Settle back near rest before handing control back to build().
					if worker.alive and motor.Parent then
						motor.C0 = rest
					end
					worker.paused = false
				else
					-- PAUSE: briefly stop the arm swing (build() checks worker.paused).
					-- The arm just holds its current pose for a beat.
					worker.paused = true
					task.wait(0.6)
					worker.paused = false
				end
			end)
		end
	end
end

--======================================================================
-- wave(): on launch, everyone waves; ONE worker falls backward (comedy).
--======================================================================
function RocketNPCs.wave()
	for i, worker in ipairs(workers) do
		if not worker.alive then continue end

		-- fallen=true stops the hammer loop so the wave/topple is clean.
		worker.fallen = true

		if i == 1 then
			-- COMEDY: this worker topples straight backward like a felled tree.
			-- We RAGDOLL it: unanchor the root so physics takes over, kill the
			-- Humanoid's standing state, stop animations, then tip the whole rig
			-- backward with a rotating PivotTo (so it reads as a stiff topple even
			-- without a fall animation). It keeps CanCollide=false so it can't
			-- land on / block a player.
			local model = worker.model
			local humanoid = worker.humanoid
			if worker.walkTrack then worker.walkTrack:Stop() end
			if worker.idleTrack then worker.idleTrack:Stop() end
			if worker.root then
				worker.root.Anchored = true -- we drive the topple ourselves
			end
			if humanoid then
				-- Let the Humanoid go limp so it doesn't try to re-stand.
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
				humanoid.PlatformStand = true
			end
			local startCF = model:GetPivot()
			local t0 = os.clock()
			local conn
			conn = RunService.Heartbeat:Connect(function()
				if not model.Parent then conn:Disconnect(); return end
				local a = math.clamp((os.clock() - t0) / 0.8, 0, 1)
				-- Rotate backward up to ~85° about the feet and sink slightly.
				local fallCF = startCF
					* CFrame.new(0, -a * 1.5, 0)
					* CFrame.Angles(math.rad(-85 * a), 0, 0)
				model:PivotTo(fallCF)
				if a >= 1 then conn:Disconnect() end
			end)
			table.insert(actionLoops, conn)
		elseif worker.shoulderMotor then
			-- WAVE: raise the right arm overhead and swing it side to side — by
			-- animating ONLY the RightShoulder Motor6D's C0. Body stays planted.
			if worker.idleTrack then worker.idleTrack:Stop() end
			local motor = worker.shoulderMotor
			local restC0 = worker.shoulderRestC0
			local conn
			conn = RunService.Heartbeat:Connect(function()
				if not motor.Parent or not worker.alive then conn:Disconnect(); return end
				-- Pitch the arm fully up overhead and add a small side-to-side
				-- roll (Z) so it reads as a friendly wave.
				local wave = math.sin(os.clock() * 8) * 0.5
				motor.C0 = restC0 * CFrame.Angles(math.rad(-155), 0, wave)
			end)
			table.insert(actionLoops, conn)
		end
	end
end

--======================================================================
-- cleanup(): stop loops + destroy all NPC instances + site dressing. No leaks.
--======================================================================
function RocketNPCs.cleanup()
	-- Disconnect every connection we made (MoveToFinished + Heartbeat loops).
	for _, conn in ipairs(actionLoops) do
		if conn and conn.Connected then conn:Disconnect() end
	end
	actionLoops = {}

	for _, worker in ipairs(workers) do
		worker.alive = false
		-- Stop any animation tracks so their Animator references release.
		if worker.walkTrack then pcall(function() worker.walkTrack:Stop() end) end
		if worker.idleTrack then pcall(function() worker.idleTrack:Stop() end) end
		if worker.model and worker.model.Parent then
			worker.model:Destroy()
		end
	end
	workers = {}

	if npcFolder and npcFolder.Parent then
		npcFolder:Destroy()
	end
	npcFolder = nil

	-- Destroy the construction set-dressing folder too (it lives on island 1
	-- in its own container, NOT in the rocket model, so we free it here).
	if dressingFolder and dressingFolder.Parent then
		dressingFolder:Destroy()
	end
	dressingFolder = nil

	sitePos = nil
end

return RocketNPCs
