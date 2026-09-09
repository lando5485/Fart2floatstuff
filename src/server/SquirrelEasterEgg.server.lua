--======================================================================
-- SquirrelEasterEgg.server.lua  (Script)  -- STANDALONE, self-contained NPC easter egg  [now a PIG]
--======================================================================
-- A walking PIG NPC that wanders inside an invisible rectangular field defined by 3 parts named "Boundary"
-- in Workspace. Mirrors the COW easter egg (EasterEggManager): same overhead chat-bubble style + the
-- proximity-gated random one-liners, the same "spawn -> wander -> respawn on death/fall" controller.
--
-- It's a REAL Humanoid rig: a HumanoidRootPart + Humanoid so it walks itself via Humanoid:MoveTo and
-- auto-faces its direction of travel. Cosmetic body parts are welded (massless) to the root; the body+head
-- is fused into ONE smooth union (PetSystem pattern) so there are no ball seams. Purely COSMETIC -- never
-- touches flight, pets, coins, gas, shop, the black hole, events, the cow, the Farmer, the Gardener, or any
-- other NPC / gameplay.
--======================================================================

local Workspace  = game:GetService("Workspace")
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local SMOOTH = Enum.SurfaceType.Smooth

-- [COLLISION] a collision group for the pig so its now-SOLID body parts can't shove the UNANCHORED HumanoidRootPart
-- (the group does NOT collide with itself, so the HRP slides freely through its own shell -> MoveTo/wander unaffected),
-- while still blocking players + the world (the Default group). Registered once here; each pig's parts join it on build.
local NPC_COLLISION_GROUP = "NPCBody"
pcall(function() PhysicsService:RegisterCollisionGroup(NPC_COLLISION_GROUP) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable(NPC_COLLISION_GROUP, NPC_COLLISION_GROUP, false) end)

-- ===== TUNABLES ===== (calm, cow-paced amble)
local WALK_SPEED   = 4                 -- studs/sec -- matches the cow (COW_SPEED=4): slow + deliberate, never darts
local EDGE_MARGIN  = 1.5               -- keep targets this far inside the bounds
local NEAR_MIN, NEAR_MAX = 10, 26      -- amble distance per leg (studs) -> longer legs so it actually roams the whole field
local IDLE_MIN, IDLE_MAX = 1, 4        -- short idle pause (sec) between moves -- kept under CAMP_LIMIT so it's always roaming
local MOVE_TIMEOUT = 12                -- give up on a target after this long (then re-pick); longer legs need more time
-- Anti-camp: the pig must never linger in one spot. If it hasn't displaced CAMP_RADIUS studs within CAMP_LIMIT
-- seconds (whether idling OR stuck mid-move), we bail out of whatever it's doing and force a fresh move.
local CAMP_LIMIT  = 6                  -- hard cap (sec) on standing in the same spot -> always moving around
local CAMP_RADIUS = 4                  -- counts as "moved" once it's this many studs from the remembered spot
-- Obstacle avoidance (so the pig never walks its body into garden props/fences/walls -- it steers/turns away).
local AVOID_LOOKAHEAD = 5              -- studs of clear space it keeps ahead; something nearer -> stop + turn away
-- (The old AVOID_HALFWIDTH / AVOID_RAYHEIGHT rays are gone: the path is now swept with the pig's whole body
-- silhouette -- see bodySweepHit below -- so width and height come from the model, not from two numbers.)
local AVOID_TRIES     = 18            -- random directions tested for a fully-clear path before it gives up + waits
local NOSE_BUFFER     = 3             -- require the path clear this far PAST the target too, so the snout never pokes into an object
local FALL_BELOW   = 25                -- studs below the floor -> treat as "fell", respawn
local TALK_MIN, TALK_MAX = 12, 18      -- random line every 12-18s
local TALK_RANGE   = 20                -- only speak the AMBIENT one-liners when a player is within 20 studs
                                       -- (the bubble itself is readable from 100 -- see the note by the bubble)
-- ===== THE OINK =====
-- The pig had NO sound at all -- only text bubbles -- so it has been a silent animal since it was
-- written. This mirrors the cow exactly: same Sound placement (on the body, 3D/positional), same
-- rolloff, same "every N seconds plus on demand" cadence, so the two farm animals behave alike.
-- â  PUT A REAL rbxassetid HERE. Empty means the pig hops but makes no noise.
local OINK_SOUND_ID = "rbxassetid://855134280"
local OINK_MIN, OINK_MAX = 15, 40      -- same cadence as the cow's moo (mooMin/mooMax in EasterEggManager)
-- ONE-SHOT LOAD CHECK, at file scope rather than per rig (the pig respawns, and a repeated check would
-- just spam the log). Several ids in this place fail with "Asset type does not match requested type" or
-- "not approved for the requester", and that failure is SILENT at the point of use -- without this line
-- a bad id looks exactly like the oink system being broken.
task.spawn(function()
	if OINK_SOUND_ID == "" then return end
	local probe = Instance.new("Sound"); probe.SoundId = OINK_SOUND_ID; probe.Parent = workspace
	local ok, err = pcall(function() game:GetService("ContentProvider"):PreloadAsync({probe}) end)
	if ok and probe.IsLoaded then
		print(("[PIG] oink %s loaded OK (length %.2fs) -- the id is good"):format(OINK_SOUND_ID, probe.TimeLength))
	else
		warn("[PIG] oink "..OINK_SOUND_ID.." did NOT load -- the pig will be silent. "..tostring(err))
	end
	probe:Destroy()
end)

-- short cosmetic one-liners cycled in the pig's overhead bubble (easy to edit; keep them brief)
local PIG_LINES = {
	"Oink! Welcome to the farm!",
	"Got any snacks?",
	"Oink oink!",
}

--======================================================================
-- BOUNDARY FIELD: find the 3 parts named "Boundary", treat their positions as corners, compute the X/Z
-- bounding box (the roam region) + the average Y (floor). Then hide the field (invisible markers).
--======================================================================
local function findBoundaryParts()
	local found = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Boundary" then found[#found + 1] = d end
	end
	return found
end

local function computeField(parts)
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	local sumY, n = 0, 0
	for _, b in ipairs(parts) do
		local p = b.Position
		minX = math.min(minX, p.X); maxX = math.max(maxX, p.X)
		minZ = math.min(minZ, p.Z); maxZ = math.max(maxZ, p.Z)
		sumY = sumY + p.Y; n = n + 1
	end
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ, groundY = sumY / math.max(n, 1) }
end

--======================================================================
-- THE PIG RIG. HumanoidRootPart (collidable, invisible) rests on the floor; cosmetic parts are welded
-- (massless) around it. FRONT = -Z so Humanoid AutoRotate points the head where it walks. Returns a rig.
--======================================================================
local function buildPig(rootCF)
	local model = Instance.new("Model"); model.Name = "WanderingPig"
	model.Parent = Workspace

	-- ===== PALETTE =====
	local PINK_BODY  = Color3.fromRGB(238, 160, 165) -- body / legs / tail (reference pink)
	local PINK_SNOUT = Color3.fromRGB(224, 134, 148) -- snout (slightly darker)
	local PINK_EAR   = Color3.fromRGB(230, 146, 158) -- ears (slightly darker)
	local NOSTRIL    = Color3.fromRGB(60, 42, 48)    -- nostril dots
	local EYE        = Color3.fromRGB(20, 18, 22)    -- eye dots
	local HOOF       = Color3.fromRGB(90, 55, 45)    -- dark-brown hooves

	-- HumanoidRootPart: physics/collision body (rests its bottom on the ground), invisible. Anchored DURING the
	-- build so nothing drifts while UnionAsync yields; unanchored (with everything welded to it) at the very end.
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"; hrp.Size = Vector3.new(1.5, 1.0, 1.7) -- footprint under the barrel; Y=1.0 so the controller's groundY+0.5 spawn rests the BOTTOM on the floor
	hrp.Transparency = 1; hrp.Anchored = true; hrp.CanCollide = true; hrp.CanQuery = false
	hrp.TopSurface = SMOOTH; hrp.BottomSurface = SMOOTH
	hrp.CFrame = rootCF
	hrp.Parent = model
	model.PrimaryPart = hrp

	local function V(x, y, z) return Vector3.new(x, y, z) end
	local function R(x, y, z, rot) return rootCF * CFrame.new(x, y, z) * (rot or CFrame.new()) end -- body-local placement

	-- a raw smooth source/detail part: ANCHORED (no drift during CSG), matte SmoothPlastic, no collide/shadow.
	local function raw(name, shape, size, color, cframe)
		local p = Instance.new("Part")
		p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.CastShadow = false; p.Massless = true
		p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
		p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
		p.CFrame = cframe; p.Parent = model
		return p
	end

	-- FUSE heavily-overlapping source parts into ONE smooth union (the PetSystem pattern: UnionAsync ->
	-- UsePartColor + SmoothPlastic + Precise + Box + SmoothingAngle 60). On CSG failure (e.g. Studio API access
	-- off) keep the (overlapping) source parts renamed so the pig still spawns. Returns ok (true/false), err.
	local function fuseGroup(src, name, color)
		local first = table.remove(src, 1)
		local ok, u = pcall(function() return first:UnionAsync(src) end)
		if ok and typeof(u) == "Instance" then
			first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
			u.Name = name; u.UsePartColor = true; u.Color = color; u.Material = Enum.Material.SmoothPlastic
			u.Anchored = true; u.CanCollide = false; u.CanQuery = false; u.CanTouch = false
			u.CastShadow = false; u.Massless = true
			u.TopSurface = SMOOTH; u.BottomSurface = SMOOTH; u.LeftSurface = SMOOTH
			u.RightSurface = SMOOTH; u.FrontSurface = SMOOTH; u.BackSurface = SMOOTH
			pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
			pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
			pcall(function() u.SmoothingAngle = 60 end) -- soft satin shading across the fused solid
			u.Parent = model
			return true, nil
		else
			table.insert(src, 1, first)
			for _, p in ipairs(src) do p.Name = name .. "Chunk" end -- unfused fallback -> still spawns (lumpier)
			local err = (not ok) and tostring(u) or ("UnionAsync returned " .. typeof(u)) -- the actual CSG error (or nil-result)
			return false, err
		end
	end

	-- a TRIANGULAR ear (WedgePart) with the same cosmetic flags as raw()
	local function rawWedge(name, size, color, cframe)
		local p = Instance.new("WedgePart")
		p.Name = name; p.Size = size; p.Color = color; p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.CastShadow = false; p.Massless = true
		p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
		p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
		p.CFrame = cframe; p.Parent = model
		return p
	end

	-- ===== ONE CLEAN BARREL UNION (body + head only -- the legs are SEPARATE animated parts, built below). THREE
	-- big, heavily-overlapping torso spheres with their centres close together fuse into ONE smooth oval barrel with
	-- NO segment bumps/rings near the hips/rear. Slim + horizontal (wider + longer than tall), like a real pig. Plus
	-- a neck bridge + a distinct head. SmoothingAngle 60 (in fuseGroup) softens the joins. FRONT = -Z; floor = -0.5.
	local bodySrc = {}
	local function B(size, cframe) bodySrc[#bodySrc + 1] = raw("BodySrc", BAL, size, PINK_BODY, cframe) end
	B(V(1.97, 1.71, 2.25), R(0, 0.95, -0.1))  -- torso FRONT (slightly bigger + lowered 0.03)
	B(V(2.03, 1.75, 2.15), R(0, 0.95, 0.5))   -- torso MID (slightly bigger + lowered; fills the waist, no pinch/bump)
	B(V(1.95, 1.70, 2.05), R(0, 0.95, 1.05))  -- torso REAR (slightly bigger + lowered) -> ONE clean barrel
	-- NECK: TWO big overlapping segments bridging torso -> head with NO gap; head pushed DEEPER into the body too
	B(V(1.62, 1.56, 1.5),  R(0, 0.95, -1.15)) -- neck 1 (deep overlap into the torso front)
	B(V(1.52, 1.5, 1.4),   R(0, 0.92, -1.7))  -- neck 2 (overlaps neck 1 AND the head -> continuous)
	B(V(1.5, 1.5, 1.5),    R(0, 0.9, -1.9))   -- HEAD (pushed deeper/back into the body, distinct, lower)
	-- ROUNDED UNDERBELLY (replaces the old per-leg haunch nubs that read as separate lumps): ONE wide, low, CONTINUOUS
	-- belly sphere fused into the torso, so the whole underside is a smooth rounded curve that dips down over the hips.
	-- The four legs overlap UP into THIS (their tops buried) -> each leg/thigh sinks straight into the curved underbelly
	-- with NO separate connector/haunch piece and no lump. Slightly wider + lower now so it DRAPES a bit further down
	-- over the leg tops, hiding the leg-to-body join. Still within the torso width (no side bulge); subtle, not bloated.
	B(V(1.92, 1.32, 2.82), R(0, 0.5, 0.35))
	local bodyOk, bodyErr = fuseGroup(bodySrc, "PigBody", PINK_BODY)

	-- ===== SEPARATE crisp parts (hooves are part of the animated leg rig, built further below) =====
	-- SNOUT: a short flat cylinder LOW on the head front (round face forward = -Z), darker pink, + 2 nostrils
	raw("Snout", CYL, V(0.5, 1.05, 1.05), PINK_SNOUT, R(0, 0.65, -2.6, CFrame.Angles(0, math.rad(90), 0)))
	raw("Nostril", BAL, V(0.17, 0.19, 0.12), NOSTRIL, R(-0.2, 0.65, -2.87))
	raw("Nostril", BAL, V(0.17, 0.19, 0.12), NOSTRIL, R( 0.2, 0.65, -2.87))
	-- EYES: two SMALL black dots on the head front, ABOVE the snout
	raw("Eye", BAL, V(0.22, 0.26, 0.18), EYE, R(-0.42, 1.2, -2.4))
	raw("Eye", BAL, V(0.22, 0.26, 0.18), EYE, R( 0.42, 1.2, -2.4))
	-- EARS: two small UPRIGHT TRIANGULAR ears on TOP of the head (apex up + slightly forward, splayed outward)
	rawWedge("Ear", V(0.16, 0.74, 0.56), PINK_EAR, R(-0.52, 1.55, -1.85, CFrame.Angles(math.rad(8), 0, math.rad(22))))
	rawWedge("Ear", V(0.16, 0.74, 0.56), PINK_EAR, R( 0.52, 1.55, -1.85, CFrame.Angles(math.rad(8), 0, math.rad(-22))))
	-- TAIL REMOVED: the little 4-sphere curl read as stray spheres poking up on the top/back -> removed entirely so
	-- nothing pokes out of the top of the back (only legs + their tiny blends remain, at the BOTTOM corners).

	-- invisible HEAD anchor the bubble attaches to (the head shape itself is fused into the body union)
	local head = raw("HeadAnchor", BAL, V(0.2, 0.2, 0.2), PINK_BODY, R(0, 0.9, -1.9)); head.Transparency = 1

	-- ===== COW-EXACT RIG (copied verbatim from EasterEggManager.applyPose). INSPECTION RESULT: the cow's legs use
	-- NO Motor6D / Weld / Bone / Humanoid joint -- each leg is just an ANCHORED Part (newPart sets Anchored=true) and
	-- applyPose sets stub.CFrame / hoof.CFrame EVERY FRAME. They never detach because the WHOLE cow (body via
	-- rig.statics AND legs via rig.legs) is positioned from the SAME base (rig.poseCF) in ONE pass, so body + legs
	-- can't desync. We replicate that IDENTICALLY: every cosmetic part stays ANCHORED (NO welds), and one applyPose
	-- pass per frame CFrames the body+details (statics) AND the legs off ONE base. The only change: the base is the
	-- pig's HumanoidRootPart.CFrame (the invisible physics mover, so MoveTo/wander still works) in place of poseCF.

	-- LEGS (cow's addLeg): anchored stub + hoof per leg; hip pivot buried deep in the belly; hoof bottom = floor.
	local legs = {}
	local function addLeg(lx, lz, phase)
		local hip = Vector3.new(lx, 1.1, lz)   -- hip pivot raised DEEP into the belly (top buried ~0.7 past the underside)
		local legHalf, hoofY = 0.75, 1.45      -- leg lengthened UPWARD (1.5 long): top at the hip (buried), bottom -0.4
		local stub = raw("Leg",  CYL, V(1.5, 0.5, 0.5),   PINK_BODY, rootCF * CFrame.new(hip) * CFrame.new(0, -legHalf, 0) * CFrame.Angles(0, 0, math.rad(90))) -- slimmed (dia 0.5)
		local hoof = raw("Hoof", CYL, V(0.3, 0.56, 0.56), HOOF,      rootCF * CFrame.new(hip) * CFrame.new(0, -hoofY, 0)   * CFrame.Angles(0, 0, math.rad(90))) -- matches the slim leg
		legs[#legs + 1] = { stub = stub, hoof = hoof, hip = hip, legHalf = legHalf, hoofY = hoofY, phase = phase }
	end
	addLeg(-0.62, -0.45, 0)        -- front-left
	addLeg( 0.62, -0.45, math.pi)  -- front-right
	addLeg(-0.62, 1.0,  math.pi)   -- back-left
	addLeg( 0.62, 1.0,  0)         -- back-right

	-- STATICS (cow's rig.statics): every OTHER cosmetic part (body union + snout/nostrils/eyes/ears/tail/head anchor)
	-- captured as { part, off = root^-1 * partCFrame }. They stay ANCHORED -- driven off the same base as the legs.
	local legPart = {}
	for _, lg in ipairs(legs) do legPart[lg.stub] = true; legPart[lg.hoof] = true end
	local statics = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= hrp and not legPart[d] then
			statics[#statics + 1] = { part = d, off = rootCF:Inverse() * d.CFrame }
		end
	end

	-- HUMANOID = the invisible physics MOVER only (walks via MoveTo/AutoRotate; FRONT=-Z). HipHeight 0 + collidable
	-- root resting on the floor (spawned groundY+0.5) -> stands on all fours, hooves on the floor. ONLY the HRP is
	-- unanchored; every visible part stays anchored and is CFrame'd off it by the rig (exactly as the cow does).
	local HIP_HEIGHT = 0
	local hum = Instance.new("Humanoid")
	hum.WalkSpeed = WALK_SPEED; hum.AutoRotate = true; hum.HipHeight = HIP_HEIGHT
	hum.UseJumpPower = true; hum.JumpPower = 14
	hum.NameDisplayDistance = 0; hum.HealthDisplayDistance = 0
	pcall(function() hum.BreakJointsOnDeath = false end)
	hum.Parent = model
	-- CFRAME-DRIVEN (cow-exact): the HRP stays ANCHORED; the wander loop sets its CFrame directly each step (see driveTo).
	-- The Humanoid is kept only as an inert holder (no MoveTo/physics) -- movement is 100% CFrame, exactly like the cow, so
	-- the solid collidable body below can never fight a walker and the pig can't wedge/stop.
	hrp.Anchored = true

	-- applyPose COPIED FROM THE COW: ONE base per frame; the upper body bobs/waddles, the legs swing about the hip on
	-- the NON-bobbing base (feet planted). phase advanced by DISTANCE moved; amp lerps in/out. Same SWING_ANGLE(26),
	-- STRIDE(1.5), BOB_HEIGHT(0.08), WADDLE_ROLL(3.5deg) as the cow. Heartbeat-driven; dies with the model.
	local SWING_ANGLE, STRIDE, BOB_HEIGHT, WADDLE_ROLL = math.rad(26), 1.5, 0.08, math.rad(3.5)
	local phase, amp, lastPos = 0, 0, hrp.Position
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent then conn:Disconnect(); return end
		local pos = hrp.Position
		local dpos = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(lastPos.X, 0, lastPos.Z)).Magnitude
		lastPos = pos
		local moving = dpos > 0.008
		phase = phase + (dpos / STRIDE) * math.pi
		amp = amp + ((moving and 1 or 0) - amp) * math.min(dt * 6, 1)
		local bob  = math.abs(math.sin(phase)) * BOB_HEIGHT * amp
		local roll = math.sin(phase) * WADDLE_ROLL * amp
		local grounded = hrp.CFrame * CFrame.Angles(0, 0, roll) -- legs use this (no vertical bob -> feet planted)
		local upper    = grounded * CFrame.new(0, bob, 0)       -- body/details bob slightly above the legs
		for _, e in ipairs(statics) do e.part.CFrame = upper * e.off end
		for _, lg in ipairs(legs) do
			local swing = math.sin(phase + lg.phase) * SWING_ANGLE * amp
			local hipCF = grounded * CFrame.new(lg.hip) * CFrame.Angles(swing, 0, 0)
			lg.stub.CFrame = hipCF * CFrame.new(0, -lg.legHalf, 0) * CFrame.Angles(0, 0, math.rad(90))
			lg.hoof.CFrame = hipCF * CFrame.new(0, -lg.hoofY, 0) * CFrame.Angles(0, 0, math.rad(90))
		end
	end)

	-- GROUNDING CHECK: lowest world-space point across all parts (oriented AABB half-height) vs the hrp bottom (floor)
	local floorY = hrp.Position.Y - hrp.Size.Y * 0.5
	local lowest = math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, sz = d.CFrame, d.Size
			local hy = 0.5 * (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z)
			lowest = math.min(lowest, d.Position.Y - hy)
		end
	end
	local feetTouch = math.abs(lowest - floorY) < 0.2
	print(string.format("[PIG] belly enlarged slightly overhang=ok feetTouchFloor=%s", feetTouch and "y" or "n"))
	if not bodyOk then print("[PIG] body UnionAsync error: " .. tostring(bodyErr)) end

	-- [COLLISION] make the VISIBLE pig body SOLID so players bump into it instead of walking through (cow-exact). Now that
	-- the pig is ANCHORED + CFrame-driven (no Humanoid physics), making its parts collidable CANNOT break movement -- driveTo
	-- re-sets every part's CFrame each step regardless of any collision resolution, exactly as the cow's note explains. Every
	-- pig part joins NPC_COLLISION_GROUP (doesn't self-collide) so the parts never shove each other; players/world still bump them.
	pcall(function() hrp.CollisionGroup = NPC_COLLISION_GROUP end)
	local pigSolid = 0
	for _, e in ipairs(statics) do -- every cosmetic body part (PigBody union, snout, ears, eyes, head anchor, etc.)
		if e.part and e.part:IsA("BasePart") then pcall(function() e.part.CanCollide = true; e.part.CollisionGroup = NPC_COLLISION_GROUP end); pigSolid = pigSolid + 1 end
	end
	for _, lg in ipairs(legs) do -- the four animated legs + hooves
		for _, lp in ipairs({ lg.stub, lg.hoof }) do
			if lp and lp:IsA("BasePart") then pcall(function() lp.CanCollide = true; lp.CollisionGroup = NPC_COLLISION_GROUP end); pigSolid = pigSolid + 1 end
		end
	end
	print("[COLLISION] pig body parts set solid=" .. pigSolid .. " (CanCollide=true; anchored + CFrame-driven, movement unaffected)")

	-- OINK SOUND on the body, not the HumanoidRootPart: the HRP is invisible and sits at the pig's
	-- centre, but the body union is what a player is standing next to. Cow-exact rolloff so the two
	-- animals carry the same distance across the garden.
	local oink = Instance.new("Sound"); oink.Name = "OinkSound"; oink.SoundId = OINK_SOUND_ID
	oink.Volume = 0.6; oink.RollOffMinDistance = 12; oink.RollOffMaxDistance = 130
	oink.Parent = head or hrp
	if OINK_SOUND_ID == "" then
		warn("[PIG] OINK_SOUND_ID is empty -- the pig hops but is SILENT. Set it at the top of "
			.. "SquirrelEasterEgg.server.lua to a real rbxassetid.")
	end

	return { model = model, hrp = hrp, head = head, hum = hum, legs = legs, oink = oink }
end

--======================================================================
-- OVERHEAD CHAT BUBBLE -- COPIES the cow's TalkBubble style EXACTLY (bg / UICorner / UIStroke / Font /
-- TextColor3 / TextSize 18 / padding, TextScaled=false, pixel-offset size, MaxDistance=20). Adorned to the
-- head so it tracks the walk; say() shows a line then auto-hides. Named "PigTalkBubble".
--======================================================================
local function attachTalkBubble(rig)
	local host = rig and rig.head
	if not (host and host.Parent) then return nil end
	local bb = Instance.new("BillboardGui")
	bb.Name = "PigTalkBubble"; bb.Adornee = host
	bb.Size = UDim2.fromOffset(230, 64)        -- PIXEL OFFSET units only (NO scale) -> constant screen size near/far
	bb.SizeOffset = Vector2.new(0, 0)
	bb.StudsOffset = Vector3.new(0, 2.2, 0)    -- above the head
	bb.LightInfluence = 0
	-- 100, not 20: MaxDistance is the range the bubble can be SEEN from. See the matching note on the cow's
	-- bubble in EasterEggManager -- at 20 the fireside stories were unreadable from anywhere but on top of
	-- the animals, which defeats walking over to watch them.
	bb.AlwaysOnTop = true; bb.MaxDistance = 100; bb.Enabled = false; bb.Parent = host
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(230, 64); frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BackgroundTransparency = 0.05; frame.BorderSizePixel = 0; frame.Parent = bb
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = frame
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(40, 40, 46); stroke.Thickness = 2; stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1; label.Size = UDim2.fromOffset(214, 54); label.Position = UDim2.new(0, 8, 0, 5)
	label.Font = Enum.Font.GothamBold; label.TextScaled = false; label.TextSize = 18; label.AutomaticSize = Enum.AutomaticSize.None
	label.TextColor3 = Color3.fromRGB(34, 34, 40); label.TextWrapped = true; label.Text = ""; label.Parent = frame
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

-- proximity gate: true if any player's character is within `range` studs of the pig's head.
local function isPlayerNear(rig, range)
	local host = rig and rig.head
	if not (host and host.Parent) then return false end
	local origin = host.Position
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - origin).Magnitude <= range then return true end
	end
	return false
end

local function interruptibleWait(secs, stop)
	local t = 0
	while t < secs do
		if stop and stop() then return end
		task.wait(0.2); t = t + 0.2
	end
end

-- talk loop: every TALK_MIN..TALK_MAX sec show a random line -- but ONLY when a player is within 20 studs.
local function runTalk(rig, stop)
	local bubble = attachTalkBubble(rig)
	if not bubble then return end
	-- register for the GardenFeeding mini-feature (find the pig's body + make it speak, reusing THIS bubble)
	_G.gardenAnimals = _G.gardenAnimals or {}
	-- `hold` is optional and defaults to the 7s an ambient one-liner wants. The fireside stories pass a
	-- shorter one: they land a line every LINE_SECONDS and the bubble must clear before this animal speaks
	-- again, or the hide fires over the next line and blanks it mid-sentence.
	_G.gardenAnimals.pig = { body = bubble.gui.Adornee, say = function(m, hold) bubbleSay(bubble, m, hold or 7) end }

	-- ===== OINK: on a timer AND on demand =====
	-- Rewound before every play, same as the warning alarm and the cow's moo: a Sound told to play while
	-- already playing resumes instead of restarting, which turns two oinks into one smeared one.
	local function oinkNow()
		if not rig.model.Parent then return false end
		local s = rig.oink
		if s then pcall(function() s.TimePosition = 0; s:Play() end) end
		print("[PIG] oink")
		return true
	end
	-- The ambient cadence. A SEPARATE loop from the talk loop above on purpose: the bubble lines are
	-- proximity-gated (they are text nobody can read from across the garden), but a sound carries, so
	-- gating the oink on proximity too would leave the farm silent exactly when you are walking toward it.
	task.spawn(function()
		while rig.model.Parent and not stop() do
			interruptibleWait(math.random(OINK_MIN, OINK_MAX), function() return stop() or not rig.model.Parent end)
			if stop() or not rig.model.Parent then break end
			oinkNow()
		end
	end)
	local i = 1 -- CYCLE the short lines in order (loop), starting on line 1
	while rig.model.Parent and not stop() do
		interruptibleWait(math.random(TALK_MIN, TALK_MAX), function() return stop() or not rig.model.Parent end)
		if stop() or not rig.model.Parent then break end
		-- SILENT AT NIGHT. The idle one-liners share the ONE speech bubble the fireside stories are told
		-- through, so an ambient "Got any snacks?" landing mid-story overwrites a line and the exchange stops making
		-- sense. Campfire.server owns BeanFarmNight; the chatter comes back on its own at sunrise.
		if Workspace:GetAttribute("BeanFarmNight") == true then
			print("[PIG] quiet -- night, the fireside story owns the bubble")
		elseif isPlayerNear(rig, TALK_RANGE) then
			local line = PIG_LINES[i]
			i = (i % #PIG_LINES) + 1
			bubbleSay(bubble, line, 7) -- readable pace
			print("[PIG] said (player near): " .. line)
		else
			print("[PIG] skipped (no one near)")
		end
	end
	if _G.gardenAnimals then _G.gardenAnimals.pig = nil end -- pig despawned -> deregister for feeding
end

--======================================================================
-- WANDER (cow-paced amble): pick a NEARBY random point (so it ambles instead of darting), Humanoid:MoveTo it
-- (AutoRotate turns it smoothly toward the target -- no snap), then a VARIED idle pause with small lifelike
-- fidgets (a brief look-around turn or a tiny hop), mirroring how the cow idles. Targets are clamped inside the
-- bounds so it always stays in the field.
--======================================================================
-- a point a random [minD,maxD] studs from `from`, clamped inside the bounds (defaults to the normal leg range)
local function nearbyPoint(field, from, minD, maxD)
	local lo, hi = minD or NEAR_MIN, maxD or NEAR_MAX
	local ang = math.random() * 2 * math.pi
	local d = lo + math.random() * (hi - lo)
	local x = math.clamp(from.X + math.cos(ang) * d, field.minX + EDGE_MARGIN, field.maxX - EDGE_MARGIN)
	local z = math.clamp(from.Z + math.sin(ang) * d, field.minZ + EDGE_MARGIN, field.maxZ - EDGE_MARGIN)
	return Vector3.new(x, field.groundY, z)
end

-- ===== OBSTACLE AVOIDANCE ===== (horizontal raycasts so the pig steers around the objects in its field).
-- The pig's own parts + the boundary markers are all CanQuery=false, so rays only hit REAL obstacles.
-- RaycastParams that also ignore the pig model + every player character (never treat those as walls).
local function avoidParams(rig)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local list = { rig.model }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then table.insert(list, pl.Character) end
	end
	params.FilterDescendantsInstances = list
	return params
end

-- ===== BODY SWEEP, NOT HAIRLINE RAYS =====
-- Three rays at one fixed height were the previous test, and one fixed height is why the animals still
-- walked through things: the cow's ray sat 3.2 studs up -- above the 2.4-stud food box, above the fence
-- rails, above every planter -- so none of those ever registered, and the pig's missed anything under
-- 1.4 studs or over its shoulder line. This sweeps a slab the size of the animal's own silhouette (its
-- bounding box, minus ankle height so grass tufts are stepped over rather than steered around) along
-- the intended path. Anything the body would pass through, at any height from shin to back, is a hit.
-- Invisible non-collidable bricks (hidden markers) are skipped, so a helper part never becomes an
-- invisible wall. `params` supplies the exclusion list (the animal itself, players).
local function bodySweepHit(model, fromPos, dir, dist, params)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.05 or dist <= 0 then return nil end
	flat = flat.Unit
	local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
	if not ok or not size then return nil end
	local LIFT = 0.5 -- shin height: things this low are walked over, not around
	local slab = Vector3.new(math.max(1, size.X), math.max(0.5, size.Y - LIFT), 0.5)
	local centre = Vector3.new(fromPos.X, cf.Position.Y + LIFT * 0.5, fromPos.Z)
	local start = CFrame.lookAt(centre, centre + flat)
	local ghosts = {}
	for _ = 1, 6 do
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.IgnoreWater = true
		local list = table.clone(params.FilterDescendantsInstances)
		for _, g in ipairs(ghosts) do list[#list + 1] = g end
		p.FilterDescendantsInstances = list
		local hit = workspace:Blockcast(start, slab, flat * dist, p)
		if not hit then return nil end
		local inst = hit.Instance
		if inst and inst:IsA("BasePart") and inst.Transparency >= 0.95 and not inst.CanCollide then
			ghosts[#ghosts + 1] = inst -- a hidden marker: look past it
		else
			return hit
		end
	end
	return nil
end

-- true if the pig's whole body can travel from `fromPos` to `toPos` without passing through anything.
local function pathClear(rig, fromPos, toPos, params)
	local dir = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
	if dir.Magnitude < 0.05 then return true end
	return bodySweepHit(rig.model, fromPos, dir, dir.Magnitude, params) == nil
end

-- true if something solid is within AVOID_LOOKAHEAD studs straight ahead (pig front = HRP LookVector).
local function forwardBlocked(rig, params)
	local fwd = rig.hrp.CFrame.LookVector
	return bodySweepHit(rig.model, rig.hrp.Position, fwd, AVOID_LOOKAHEAD, params) ~= nil
end

-- pick a target whose ENTIRE straight path is clear of obstacles (plus a nose buffer past the endpoint so the snout
-- never ends up inside something). Two passes: normal legs first, then short steps -> it can still slip down a gap when
-- mostly boxed in. nil only when no clear direction exists at all (caller just waits + retries -- it never clips through).
local function pickClearTarget(rig, field, fromPos, params)
	for _, span in ipairs({ { NEAR_MIN, NEAR_MAX }, { 3, 9 } }) do
		for _ = 1, AVOID_TRIES do
			local cand = nearbyPoint(field, fromPos, span[1], span[2])
			local dir = Vector3.new(cand.X - fromPos.X, 0, cand.Z - fromPos.Z)
			-- check the whole way to the target AND NOSE_BUFFER studs beyond it -> the pig stops short, body fully clear
			local checkTo = (dir.Magnitude > 0.05) and (cand + dir.Unit * NOSE_BUFFER) or cand
			if pathClear(rig, fromPos, checkTo, params) then return cand end
		end
	end
	return nil
end

-- ===== CFRAME DRIVER (cow-exact) ===== The pig is ANCHORED + CFrame-driven, EXACTLY like the cow's driveCow/walkTo:
-- we lerp the HumanoidRootPart.CFrame ourselves each step, and the Heartbeat applyPose (built in buildPig) reads that
-- CFrame to swing the legs + bob from the per-frame displacement. No Humanoid physics -> the solid collidable shell can
-- never fight a walker, so the pig is both bump-solid AND can never wedge/stop.
local STEP = 1 / 30
-- glide the rig's root from its current CFrame to toCF over `duration` secs (ease-in/out, same curve the cow uses).
-- The params argument is optional. When given, the drive CHECKS AHEAD EVERY STEP and stops early if
-- something has moved into the way -- see the note below on why picking a clear path once is not enough.
local function driveTo(rig, toCF, duration, stop, params)
	local hrp = rig.hrp
	local fromCF = hrp.CFrame
	local t = 0
	local look = 0
	while t < duration do
		if stop() or not rig.model.Parent then return end
		-- ===== CHECK AHEAD WHILE WALKING, NOT ONLY WHEN CHOOSING =====
		-- pickClearTarget tests the path at the MOMENT the leg starts and never again, so anything that
		-- appears after that gets walked straight through: the food box (placed a moment after the pig
		-- spawns), a player-dropped prop, the cow, a garden rebuild. forwardBlocked existed for exactly
		-- this and was never called. Four times a second is plenty for an animal at 4 studs/sec and it
		-- costs three short rays.
		look = look + STEP
		if params and look >= 0.25 then
			look = 0
			if forwardBlocked(rig, params) then return end   -- stop here; wander() picks a fresh heading
		end
		t = math.min(duration, t + STEP)
		local a = t / duration
		hrp.CFrame = fromCF:Lerp(toCF, (math.sin((a - 0.5) * math.pi) + 1) / 2) -- eased -> smooth accel + settle
		task.wait(STEP)
	end
	if rig.model.Parent and not stop() then hrp.CFrame = toCF end
end

-- ===== NIGHT: GO TO THE FIRE =====
-- Campfire.server publishes BeanFarmNight and StoryFirePos (the fire nearest the island-1 food stand). While it
-- is night the pig stops wandering and walks to the point INSIDE its field nearest that fire, then stands facing
-- the flames -- that is where the stories are told (Campfire drives the bubbles; this only gets him there). The
-- field fence is never crossed: the story fire sits right at the field's corner, so "the nearest point inside"
-- is within a few studs of it.
local GATHER_BACK = 8 -- studs back from the flame centre, clear of the ring of stools around it

local function nightGatherPoint(field, firePos)
	local cx, cz = (field.minX + field.maxX) * 0.5, (field.minZ + field.maxZ) * 0.5
	local dir = Vector3.new(cx - firePos.X, 0, cz - firePos.Z)
	if dir.Magnitude < 0.05 then dir = Vector3.new(1, 0, 0) end
	local p = firePos + dir.Unit * GATHER_BACK
	return Vector3.new(
		math.clamp(p.X, field.minX + EDGE_MARGIN, field.maxX - EDGE_MARGIN), field.groundY,
		math.clamp(p.Z, field.minZ + EDGE_MARGIN, field.maxZ - EDGE_MARGIN))
end

-- One clear leg toward `goal` (flat vector from the pig): straight at it if the body sweep says the way is
-- clear, else the nearest clear heading either side. nil = every direction blocked this instant.
local function legToward(rig, field, flat, params)
	local here = rig.hrp.Position
	local len = math.clamp(flat.Magnitude, 3, NEAR_MAX)
	for _, deg in ipairs({ 0, 35, -35, 70, -70, 105, -105 }) do
		local dir = (CFrame.Angles(0, math.rad(deg), 0) * flat.Unit)
		local cand = Vector3.new(
			math.clamp(here.X + dir.X * len, field.minX + EDGE_MARGIN, field.maxX - EDGE_MARGIN), field.groundY,
			math.clamp(here.Z + dir.Z * len, field.minZ + EDGE_MARGIN, field.maxZ - EDGE_MARGIN))
		local d = Vector3.new(cand.X - here.X, 0, cand.Z - here.Z)
		if d.Magnitude > 1 and pathClear(rig, here, cand + d.Unit * math.min(NOSE_BUFFER, 1.5), params) then
			return cand
		end
	end
	return nil
end

-- WANDER: pick a clear nearby point, FACE it (front = -Z), glide there, brief pause, then immediately pick a NEW
-- direction. Each leg is short (capped ~5s) so the pig changes heading + position roughly every few seconds (always
-- under ~6s), and it's always either walking or in a <1s settle -- never parked. Mirrors the cow's walk/graze loop.
local function wander(rig, field, stop)
	local baseY = rig.hrp.Position.Y -- the (constant) root-centre height; targets stay on this plane so feet stay grounded
	while rig.model.Parent and not stop() do
		local params = avoidParams(rig) -- ignores the pig + players; refreshed per leg
		local stopFn = function() return stop() or not rig.model.Parent end

		-- NIGHT: head for the fire and stay there (see nightGatherPoint above).
		local firePos = Workspace:GetAttribute("StoryFirePos")
		if Workspace:GetAttribute("BeanFarmNight") == true and typeof(firePos) == "Vector3" then
			local goal = nightGatherPoint(field, firePos)
			local here = rig.hrp.Position
			local flat = Vector3.new(goal.X - here.X, 0, goal.Z - here.Z)
			local blockedTwice = (rig.nightBlocked or 0) >= 2 and flat.Magnitude <= 8
			if flat.Magnitude <= 2.5 or blockedTwice then
				-- settled: face the flames and listen. A stool in the way of the exact spot is close enough.
				local face = Vector3.new(firePos.X - here.X, 0, firePos.Z - here.Z)
				if face.Magnitude > 0.1 then
					local at = Vector3.new(here.X, baseY, here.Z)
					local want = CFrame.lookAt(at, at + face)
					if (rig.hrp.CFrame.LookVector - want.LookVector).Magnitude > 0.2 then driveTo(rig, want, 0.8, stop) end
				end
				interruptibleWait(1, stopFn)
			else
				local leg = legToward(rig, field, flat, params)
				if leg then
					rig.nightBlocked = 0
					local toPos = Vector3.new(leg.X, baseY, leg.Z)
					local dir = toPos - Vector3.new(here.X, baseY, here.Z)
					driveTo(rig, CFrame.lookAt(toPos, toPos + dir), math.clamp(dir.Magnitude / WALK_SPEED, 0.8, 6), stop, params)
				else
					rig.nightBlocked = (rig.nightBlocked or 0) + 1
					interruptibleWait(0.6, stopFn)
				end
			end
			continue
		end
		rig.nightBlocked = 0
		-- ONLY ever head to a point whose whole path is clear -> the pig gets close to props but never walks inside one.
		local target = pickClearTarget(rig, field, rig.hrp.Position, params)
		if not target then
			-- fully boxed in this instant: don't clip through anything -- wait a beat and re-scan for a clear opening
			interruptibleWait(0.4 + math.random() * 0.4, function() return stop() or not rig.model.Parent end)
		else
			local fromPos = rig.hrp.Position
			local toPos = Vector3.new(target.X, baseY, target.Z)
			local dir = toPos - Vector3.new(fromPos.X, baseY, fromPos.Z)
			if dir.Magnitude > 0.1 then
				local toCF = CFrame.lookAt(toPos, toPos + dir) -- front (-Z) faces the travel direction, like the cow
				-- params passed so the leg aborts if something moves into the path mid-walk
				driveTo(rig, toCF, math.clamp(dir.Magnitude / WALK_SPEED, 0.8, 5), stop, params) -- leg time tied to distance, capped
			end
			interruptibleWait(0.3 + math.random() * 0.6, function() return stop() or not rig.model.Parent end) -- brief settle, then a new heading
		end
	end
end

--======================================================================
-- CONTROLLER: resolve the field, then spawn -> wander -> respawn (on death OR fall), forever. One pig
-- at a time (sequential), mirroring the cow controller.
--======================================================================
task.spawn(function()
	local ok, err = pcall(function()
		-- wait for the world to be positioned (same signal the cow waits on), then locate the Boundary parts
		local waited = 0
		while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end
		local parts
		for _ = 1, 30 do
			parts = findBoundaryParts()
			if #parts >= 3 then break end
			task.wait(1)
		end
		if not parts or #parts < 2 then
			warn("[PIG] need >=2 parts named 'Boundary' in Workspace to form a field -- found " .. tostring(parts and #parts or 0) .. " -- disabled")
			return
		end
		if #parts < 3 then warn("[PIG] expected 3 'Boundary' parts, found " .. #parts .. " -- using bounding box of what was found") end

		local field = computeField(parts)
		-- make the field invisible (the markers are just corners -> hide + non-interactive)
		for _, b in ipairs(parts) do
			pcall(function() b.Transparency = 1; b.CanCollide = false; b.CanQuery = false end)
		end

		local cx = (field.minX + field.maxX) * 0.5
		local cz = (field.minZ + field.maxZ) * 0.5

		while true do
			-- spawn at the field centre, on the ground (hrp half-height above the floor -> bottom rests on it), random yaw
			local spawnCF = CFrame.new(cx, field.groundY + 0.5, cz) * CFrame.Angles(0, math.random() * 2 * math.pi, 0)
			local rig = buildPig(spawnCF)
			local dead = false
			local stop = function() return dead or not rig.model.Parent end

			rig.hum.Died:Connect(function() dead = true end)
			-- fall/stuck watcher: dropped well below the floor -> respawn
			task.spawn(function()
				while rig.model.Parent and not dead do
					if rig.hrp.Position.Y < field.groundY - FALL_BELOW then dead = true break end
					task.wait(0.5)
				end
			end)

			-- overhead chat bubble (cosmetic), tied to THIS rig
			task.spawn(function() runTalk(rig, stop) end)

			print(string.format("[PIG] spawned, field bounds %.1f..%.1f / %.1f..%.1f, bubble wired",
				field.minX, field.maxX, field.minZ, field.maxZ))

			wander(rig, field, stop)

			pcall(function() rig.model:Destroy() end)
			task.wait(math.random(2, 4)) -- brief beat, then a new pig wanders back in
		end
	end)
	if not ok then warn("[PIG] controller error: " .. tostring(err)) end
end)
