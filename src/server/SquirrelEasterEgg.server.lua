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
local NEAR_MIN, NEAR_MAX = 7, 16       -- pick NEARBY points (studs from current spot) -> it ambles, not long dashes
local IDLE_MIN, IDLE_MAX = 2, 6        -- varied idle pause (sec) between moves
local MOVE_TIMEOUT = 8                 -- give up on a target after this long (then re-pick)
local FALL_BELOW   = 25                -- studs below the floor -> treat as "fell", respawn
local TALK_MIN, TALK_MAX = 12, 18      -- random line every 12-18s
local TALK_RANGE   = 20                -- only speak when a player is within 20 studs (same gate as the bubble MaxDistance)

local PIG_LINES = {
	"Oink oink.",
	"Is it slop time yet?",
	"Mud bath later?",
	"Snort... smells like food.",
	"I'm not fat, I'm fluffy.",
	"Wheeee!",
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
	hrp.Anchored = false
	pcall(function() hrp:SetNetworkOwner(nil) end) -- server simulates it (no client jitter / handoff)

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

	-- [COLLISION] make the VISIBLE pig body SOLID so players bump into it instead of passing through. The HRP is an
	-- unanchored physics mover wrapped in ANCHORED cosmetic parts -- if those just became CanCollide, the HRP would shove
	-- against its own body and stick. So every pig part (HRP + cosmetic) joins NPC_COLLISION_GROUP (which doesn't
	-- self-collide), and the cosmetic parts get CanCollide=true. Result: players bump the body, the HRP slides through its
	-- own shell, and MoveTo/wander is unaffected. HumanoidRootPart handling is otherwise unchanged.
	pcall(function() hrp.CollisionGroup = NPC_COLLISION_GROUP end) -- keep HRP CanCollide as-is; just group it so the body can't push it
	local pigSolid = 0
	for _, e in ipairs(statics) do -- every cosmetic body part (PigBody union, snout, ears, eyes, tail, etc.)
		if e.part and e.part:IsA("BasePart") then pcall(function() e.part.CanCollide = true; e.part.CollisionGroup = NPC_COLLISION_GROUP end); pigSolid = pigSolid + 1 end
	end
	for _, lg in ipairs(legs) do -- the four animated legs + hooves
		for _, lp in ipairs({ lg.stub, lg.hoof }) do
			if lp and lp:IsA("BasePart") then pcall(function() lp.CanCollide = true; lp.CollisionGroup = NPC_COLLISION_GROUP end); pigSolid = pigSolid + 1 end
		end
	end
	print("[COLLISION] pig body parts set solid=" .. pigSolid .. " (CanCollide=true, NPCBody group so the HRP doesn't stick)")

	return { model = model, hrp = hrp, head = head, hum = hum, legs = legs }
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
	bb.AlwaysOnTop = true; bb.MaxDistance = 20; bb.Enabled = false; bb.Parent = host
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
	while rig.model.Parent and not stop() do
		interruptibleWait(math.random(TALK_MIN, TALK_MAX), function() return stop() or not rig.model.Parent end)
		if stop() or not rig.model.Parent then break end
		if isPlayerNear(rig, TALK_RANGE) then
			local line = PIG_LINES[math.random(1, #PIG_LINES)]
			bubbleSay(bubble, line, 4.5)
			print("[PIG] said (player near): " .. line)
		else
			print("[PIG] skipped (no one near)")
		end
	end
end

--======================================================================
-- WANDER (cow-paced amble): pick a NEARBY random point (so it ambles instead of darting), Humanoid:MoveTo it
-- (AutoRotate turns it smoothly toward the target -- no snap), then a VARIED idle pause with small lifelike
-- fidgets (a brief look-around turn or a tiny hop), mirroring how the cow idles. Targets are clamped inside the
-- bounds so it always stays in the field.
--======================================================================
-- a nearby point within [NEAR_MIN,NEAR_MAX] studs of `from`, clamped inside the bounds
local function nearbyPoint(field, from, near)
	local ang = math.random() * 2 * math.pi
	local d = NEAR_MIN + math.random() * ((near or NEAR_MAX) - NEAR_MIN)
	local x = math.clamp(from.X + math.cos(ang) * d, field.minX + EDGE_MARGIN, field.maxX - EDGE_MARGIN)
	local z = math.clamp(from.Z + math.sin(ang) * d, field.minZ + EDGE_MARGIN, field.maxZ - EDGE_MARGIN)
	return Vector3.new(x, field.groundY, z)
end

-- a varied idle pause with occasional lifelike fidgets (look-around turn / tiny hop)
local function idle(rig, field, stop)
	local pause = math.random(IDLE_MIN, IDLE_MAX)
	local elapsed = 0
	while elapsed < pause do
		if stop() or not rig.model.Parent then return end
		local r = math.random()
		if r < 0.22 then
			rig.hum.Jump = true -- tiny hop
		elseif r < 0.48 then
			-- brief look-around: a TINY step (~1.5-3 studs) toward a random nearby spot -> AutoRotate turns it to "look" that way
			local p = rig.hrp.Position
			local a, dd = math.random() * 2 * math.pi, 1.5 + math.random() * 1.5
			local lx = math.clamp(p.X + math.cos(a) * dd, field.minX + EDGE_MARGIN, field.maxX - EDGE_MARGIN)
			local lz = math.clamp(p.Z + math.sin(a) * dd, field.minZ + EDGE_MARGIN, field.maxZ - EDGE_MARGIN)
			rig.hum:MoveTo(Vector3.new(lx, field.groundY, lz))
		end
		local slice = math.min(pause - elapsed, 0.8 + math.random() * 0.8) -- 0.8-1.6s slices
		interruptibleWait(slice, function() return stop() or not rig.model.Parent end)
		elapsed = elapsed + slice
	end
end

local function wander(rig, field, stop)
	local hum, hrp = rig.hum, rig.hrp
	while rig.model.Parent and not stop() do
		local target = nearbyPoint(field, hrp.Position)
		hum:MoveTo(target) -- AutoRotate smoothly turns toward the target as it walks
		-- walk until close enough or timeout
		local t0 = os.clock()
		while rig.model.Parent and not stop() and (os.clock() - t0) < MOVE_TIMEOUT do
			local p = hrp.Position
			if (Vector3.new(p.X, 0, p.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude < 2 then break end
			task.wait(0.15)
		end
		idle(rig, field, stop) -- varied pause + lifelike fidget between moves
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
