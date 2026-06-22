--======================================================================
-- GardenBird.server.lua  (Script)  -- SELF-CONTAINED cosmetic songbird companion for the Gardener.
--======================================================================
-- A tiny robin-style bird that starts perched on one of the Gardener's shoulders, then loops forever: it arcs
-- out to a random perch on a Global Garden object (pillar tops, arch sign, lamp posts, fence posts, planters,
-- RewardChest, gnomes, sunflower, the sign), lands + idles a few seconds (little hops / look-around), and
-- sometimes RETURNS to the shoulder to rest before flying off again. Smoothly interpolated (per-frame CFrame
-- lerp along a curved/arc path with gentle bobbing, faces its direction of travel, wings flap while flying).
--
-- COSMETIC + ISOLATED: every part is Anchored, CanCollide=false (never blocks the player), smooth surfaces,
-- and CFrame-driven (no physics). It only READS the gardener's HumanoidRootPart + the garden's parts to find
-- perch points -- it never modifies the gardener, his bubble, or any garden geometry. Parented to Workspace so
-- a garden stage-rebuild can't destroy it; it re-validates perch parts before each flight.
--======================================================================

local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local BAL, BLK = Enum.PartType.Ball, Enum.PartType.Block
local SMOOTH   = Enum.SurfaceType.Smooth

-- ===== TUNABLES =====
local FLY_SPEED   = 13                 -- studs/sec along the arc (duration = dist/FLY_SPEED, clamped)
local FLY_MIN, FLY_MAX = 1.4, 4.2      -- clamp flight duration (sec)
local FLAP_FREQ   = 16                 -- base wing-beat rate (modulated by takeoff/climb EFFORT in flyTo)
local WING_FOLD   = math.rad(-6)       -- wings tucked along the sides at rest (folded look)
local WING_SPREAD = math.rad(14)       -- wings held out (glide pose) during flight
local WING_BEAT   = math.rad(46)       -- flap-beat amplitude, scaled by effort (fast on takeoff/climb, glides between)
local REST_H      = 0.5                 -- bird body sits this high above a perch's top surface
local PERCH_MIN, PERCH_MAX = 2.6, 5.6  -- idle time at a GARDEN perch (sec)
local SHOULDER_REST = 10                -- [TWEAK] seconds resting on the shoulder before flying off again
local RETURN_CHANCE = 0.40             -- chance to fly back to the shoulder (instead of another object)
-- [TWEAK] OPPOSITE shoulder: -X mirrors the old +0.85 to the gardener's LEFT side of the torso
local SHOULDER_OFFSET = CFrame.new(-0.85, 1.7, -0.1)
local SHOULDER_SIDE   = (SHOULDER_OFFSET.X < 0) and "left" or "right"

local rng = Random.new()

--======================================================================
-- LOCATE the gardener + the garden build (poll; both are built asynchronously after StandsReady).
--======================================================================
local function findGarden()
	local build = Workspace:FindFirstChild("CommunityGardenBuild", true)
	if not build then return nil end
	local props = build:FindFirstChild("GardenProps")
	local gard = props and props:FindFirstChild("Gardener")
	if not gard then
		for _, d in ipairs(build:GetDescendants()) do
			if d:IsA("Model") and d:GetAttribute("GardenerNPC") then gard = d; break end
		end
	end
	if not gard then return nil end
	local hrp = gard:FindFirstChild("HumanoidRootPart") or gard.PrimaryPart or gard:FindFirstChildWhichIsA("BasePart")
	if not hrp then return nil end
	return build, gard, hrp
end

local build, gardener, hrp
for _ = 1, 360 do -- up to ~180s for the garden + gardener to finish building
	build, gardener, hrp = findGarden()
	if build and hrp then break end
	task.wait(0.5)
end
if not (build and hrp) then
	warn("[BIRD COMPANION] gardener / garden build not found -- bird not spawned")
	return
end

-- garden centre (for perched birds to face inward); pcall'd in case the bounding box can't be taken
local gardenCenter = Vector3.new(0, 0, 0)
pcall(function() local bb = build:GetBoundingBox(); gardenCenter = bb.Position end)

--======================================================================
-- GATHER perch points from garden objects: the TOP of each matching part/model + a little rest height.
-- (Dedup near-duplicates so clustered parts -- e.g. a pillar's stacked capitals -- give ONE perch.)
--======================================================================
local function topOfPart(p)
	local sz, cf = p.Size, p.CFrame
	local halfH = 0.5 * (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z)
	return Vector3.new(p.Position.X, p.Position.Y + halfH + REST_H, p.Position.Z)
end

local function gatherPerches()
	local list = {}
	local function tryAdd(pos, name, ref)
		for _, e in ipairs(list) do if (e.pos - pos).Magnitude < 3 then return end end -- dedup
		list[#list + 1] = { pos = pos, name = name, ref = ref }
	end
	for _, d in ipairs(build:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = d.Name
			if n == "PillarCapital" or n == "FencePostCap" or n == "ArchSignBoard" or n == "LampPostHi"
				or n == "LanternRoof" or string.find(n, "Planter") then
				tryAdd(topOfPart(d), n, d)
			end
		elseif d:IsA("Model") then
			local n = d.Name
			if n == "GardenGnome" or n == "RewardChest" or n == "SunflowerCenterpiece" then
				local ok, cf, size = pcall(function() return d:GetBoundingBox() end)
				if ok then tryAdd(Vector3.new(cf.Position.X, cf.Position.Y + size.Y * 0.5 + REST_H, cf.Position.Z), n, d) end
			end
		end
	end
	local sign = Workspace:FindFirstChild("CommunityGardenSign") -- the main board lives in Workspace, not the build
	if sign and sign:IsA("BasePart") then tryAdd(topOfPart(sign), "CommunityGardenSign", sign) end
	return list
end

local perches = gatherPerches()

local rig -- forward-declared so shoulderCF()'s fallback can read the bird's last pose

--======================================================================
-- BUILD the bird: a tiny low-poly robin. Anchored cosmetic parts, smooth, CanCollide=false. Driven entirely by
-- per-frame CFrame off ONE root frame (the same rigid technique the cow/pig NPCs use) -> the parts stay locked
-- together like a welded model, but motion is teleport-free and physics-free. `statics` follow the root; `wings`
-- additionally pivot for the flap.
--======================================================================
local BACK   = Color3.fromRGB(116, 104, 92) -- grey-brown back / head / wings / tail
local BREAST = Color3.fromRGB(214, 92, 50)  -- warm orange-red robin breast
local BEAK_C = Color3.fromRGB(40, 34, 28)   -- dark beak
local EYE_C  = Color3.fromRGB(14, 12, 11)   -- black eye dot

local function newBirdPart(parent, name, shape, size, color, isWedge)
	local p = isWedge and Instance.new("WedgePart") or Instance.new("Part")
	if not isWedge then p.Shape = shape end
	p.Name = name; p.Size = size; p.Color = color; p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
	p.Parent = parent
	return p
end

-- A more believable little songbird: fuller rounded body with a pale belly + orange breast, a distinct small head
-- (with a short pointed beak) on its own animated frame so it can turn, a wider fanned tail on a hinge so it can
-- flick, thin folded wing-blades along the sides that pivot at the shoulder, and small legs + feet for the perch.
-- FRONT = -Z. Built at the origin; `applyBird` poses it each frame off one root CFrame (rigid, physics-free).
local function buildBird()
	local model = Instance.new("Model"); model.Name = "GardenBird"; model.Parent = Workspace
	local rig = { model = model, body = {}, headParts = {}, wings = {}, cf = CFrame.new() }
	local BACK   = Color3.fromRGB(120, 104, 86)  -- warm brown-grey back / head / wings / tail
	local BREAST = Color3.fromRGB(208, 84, 46)   -- warm orange-red breast
	local BELLY  = Color3.fromRGB(228, 216, 196) -- pale cream belly (slightly lighter)
	local BEAK_C = Color3.fromRGB(54, 44, 34)    -- short dark beak
	local LEG_C  = Color3.fromRGB(150, 110, 80)  -- legs / feet
	local EYE_C  = Color3.fromRGB(16, 14, 12)    -- eye dot
	local function add(list, name, shape, size, color, off, isWedge)
		list[#list + 1] = { part = newBirdPart(model, name, shape, size, color, isWedge), off = off }
	end

	-- BODY: rounder + fuller -> main ball, a lower PALE belly, the warm BREAST up front, a rounded rump
	add(rig.body, "Body",   BAL, Vector3.new(1.12, 1.04, 1.42), BACK,   CFrame.new(0,  0.00,  0.05))
	add(rig.body, "Belly",  BAL, Vector3.new(1.02, 0.80, 1.20), BELLY,  CFrame.new(0, -0.30,  0.04))
	add(rig.body, "Breast", BAL, Vector3.new(0.98, 0.92, 0.80), BREAST, CFrame.new(0, -0.05, -0.52))
	add(rig.body, "Rump",   BAL, Vector3.new(0.80, 0.76, 0.72), BACK,   CFrame.new(0,  0.10,  0.64))
	-- LEGS + small forward FEET (perch look)
	for _, sx in ipairs({ -0.24, 0.24 }) do
		add(rig.body, "Leg",  BLK, Vector3.new(0.12, 0.34, 0.12), LEG_C, CFrame.new(sx, -0.66, 0.04))
		add(rig.body, "Foot", BLK, Vector3.new(0.24, 0.08, 0.34), LEG_C, CFrame.new(sx, -0.84, -0.04))
	end

	-- HEAD on its OWN frame (so it can turn): distinct head + slight crown + short pointed beak + two eyes
	rig.headBase = CFrame.new(0, 0.52, -0.66)
	add(rig.headParts, "Head",  BAL, Vector3.new(0.86, 0.82, 0.82), BACK,   CFrame.new(0,  0.00,  0.00))
	add(rig.headParts, "Crown", BAL, Vector3.new(0.66, 0.42, 0.62), BACK,   CFrame.new(0,  0.22,  0.06))
	add(rig.headParts, "Beak",  nil, Vector3.new(0.26, 0.20, 0.42), BEAK_C, CFrame.new(0, -0.04, -0.48) * CFrame.Angles(0, math.rad(180), 0), true) -- short pointed beak
	add(rig.headParts, "Eye",   BAL, Vector3.new(0.16, 0.16, 0.16), EYE_C,  CFrame.new(-0.28, 0.06, -0.30))
	add(rig.headParts, "Eye",   BAL, Vector3.new(0.16, 0.16, 0.16), EYE_C,  CFrame.new( 0.28, 0.06, -0.30))

	-- TAIL: a wider, flatter FAN on a hinge at the rump (animated pitch -> flick / fan)
	rig.tailBase = CFrame.new(0, 0.16, 0.92)
	rig.tail = { part = newBirdPart(model, "Tail", BLK, Vector3.new(0.92, 0.10, 0.98), BACK), off = CFrame.new(0, 0.02, 0.42) * CFrame.Angles(math.rad(16), 0, 0) }

	-- WINGS: thin flat blades that lie folded along the flanks; each pivots at the shoulder, flapping about the
	-- body's forward (Z) axis (symmetric: side = +1 left / -1 right).
	for _, side in ipairs({ 1, -1 }) do
		rig.wings[#rig.wings + 1] = {
			part   = newBirdPart(model, side == 1 and "WingL" or "WingR", BLK, Vector3.new(0.12, 0.30, 1.05), BACK),
			side   = side,
			pivot  = CFrame.new(side * 0.34, 0.20, -0.18), -- shoulder hinge (out / up / forward)
			armOff = CFrame.new(side * 0.16, -0.16, 0.30), -- blade lies down + back along the flank (folded)
		}
	end
	return rig
end

-- pose the whole bird off one root CFrame. anim = { wing, lean, tail, headYaw, headPitch } (all optional, eased by callers)
local function applyBird(rig, cf, anim)
	anim = anim or {}
	local bcf = cf * CFrame.Angles(0, 0, anim.lean or 0)                 -- bank/lean into turns
	for _, e in ipairs(rig.body) do e.part.CFrame = bcf * e.off end
	local hf = bcf * rig.headBase * CFrame.Angles(anim.headPitch or 0, anim.headYaw or 0, 0) -- head turns on its own frame
	for _, e in ipairs(rig.headParts) do e.part.CFrame = hf * e.off end
	rig.tail.part.CFrame = bcf * rig.tailBase * CFrame.Angles(anim.tail or 0, 0, 0) * rig.tail.off
	local wing = anim.wing or WING_FOLD
	for _, w in ipairs(rig.wings) do
		w.part.CFrame = bcf * w.pivot * CFrame.Angles(0, 0, w.side * wing) * w.armOff
	end
	rig.cf = cf
end

--======================================================================
-- TARGET CFRAMES + the smooth flight / perch motion.
--======================================================================
local function shoulderCF()
	if not (hrp and hrp.Parent) then return rig and rig.cf or CFrame.new() end
	local c = hrp.CFrame * SHOULDER_OFFSET
	local look = hrp.CFrame.LookVector; look = Vector3.new(look.X, 0, look.Z) -- level (gardener's facing)
	if look.Magnitude < 0.01 then look = Vector3.new(0, 0, -1) end
	return CFrame.lookAt(c.Position, c.Position + look.Unit)
end

local function perchCFrame(p)
	local toC = Vector3.new(gardenCenter.X - p.pos.X, 0, gardenCenter.Z - p.pos.Z) -- face inward toward the garden
	if toC.Magnitude < 1 then toC = Vector3.new(0, 0, -1) end
	return CFrame.lookAt(p.pos, p.pos + toC.Unit)
end

local function randomPerch()
	for i = #perches, 1, -1 do -- drop any perch whose part got rebuilt away (e.g. the sunflower on a stage change)
		local r = perches[i].ref
		if not (r and r:IsDescendantOf(Workspace)) then table.remove(perches, i) end
	end
	if #perches == 0 then perches = gatherPerches() end
	if #perches == 0 then return nil, nil end
	local p = perches[rng:NextInteger(1, #perches)]
	return perchCFrame(p), p.name
end

local function bez(a, c, b, t) local u = 1 - t; return a * (u * u) + c * (2 * u * t) + b * (t * t) end

local function flyTo(rig, fromCF, toCF)
	local startP, goalP = fromCF.Position, toCF.Position
	local dist = (goalP - startP).Magnitude
	local dur  = math.clamp(dist / FLY_SPEED, FLY_MIN, FLY_MAX)
	-- curved/arc control point: lift up + bow out to one side so the path circles toward the target (not a straight line)
	local mid  = (startP + goalP) * 0.5
	local flat = Vector3.new(goalP.X - startP.X, 0, goalP.Z - startP.Z)
	local perp = (flat.Magnitude > 0.1) and Vector3.new(-flat.Z, 0, flat.X).Unit or Vector3.new(1, 0, 0)
	local ctrl = mid + Vector3.new(0, math.clamp(dist * 0.30, 3, 9), 0) + perp * ((rng:NextNumber() < 0.5 and 1 or -1) * math.clamp(dist * 0.32, 2, 8))
	local t, flapPhase, lean = 0, 0, 0
	local prevPos = startP
	local prevHd  = (flat.Magnitude > 0.1) and flat.Unit or Vector3.new(0, 0, -1)
	while t < 1 do
		local dt = RunService.Heartbeat:Wait()
		if not rig.model.Parent then return end
		t = math.min(1, t + dt / dur)
		local s = t * t * (3 - 2 * t)                                       -- smoothstep ease in/out
		local pos   = bez(startP, ctrl, goalP, s)
		local ahead = bez(startP, ctrl, goalP, math.min(1, s + 0.04))
		pos = pos + Vector3.new(0, math.sin(t * math.pi * 3) * 0.22, 0)     -- soft up/down bob along the arc
		local dir = ahead - pos
		-- EFFORT: strong flap on takeoff (early t) + while climbing; eases toward a GLIDE when descending/cruising
		local climb   = (pos.Y - prevPos.Y) / math.max(dt, 1 / 120)
		local takeoff = math.max(0, 1 - t * 3)                             -- big for the first ~1/3 of the flight
		local effort  = math.clamp(0.22 + takeoff * 1.1 + math.max(0, climb) * 0.5, 0.12, 1.5)
		-- BANK into the turn (eased): roll proportional to how fast the heading is rotating
		local hd = Vector3.new(dir.X, 0, dir.Z)
		if hd.Magnitude > 0.01 then
			hd = hd.Unit
			local targetLean = math.clamp(prevHd:Cross(hd).Y * 9, -math.rad(30), math.rad(30))
			lean = lean + (targetLean - lean) * math.min(dt * 6, 1)
			prevHd = hd
		end
		flapPhase = flapPhase + dt * FLAP_FREQ * (0.6 + effort)            -- beats FASTER on takeoff/climb
		local wing = WING_SPREAD + math.sin(flapPhase) * WING_BEAT * effort -- glide (effort low) -> wings held near spread
		local cf = (dir.Magnitude > 0.01) and CFrame.lookAt(pos, pos + dir) or (CFrame.new(pos) * toCF.Rotation) -- always face travel
		applyBird(rig, cf, { wing = wing, lean = lean, tail = math.rad(6) * effort })
		prevPos = pos
	end
	-- LAND: a little hop + settle -- dip then rise, fold the wings in, untilt, eased to rest
	local st = 0
	while st < 0.42 do
		local dt = RunService.Heartbeat:Wait()
		if not rig.model.Parent then return end
		st = st + dt
		local u = math.min(1, st / 0.42)
		local bob  = math.sin(u * math.pi) * -0.16                         -- small settle dip
		local wing = WING_SPREAD + (WING_FOLD - WING_SPREAD) * u           -- fold wings in as it lands
		applyBird(rig, toCF * CFrame.new(0, bob, 0), { wing = wing, lean = (1 - u) * lean, tail = math.rad(10) * (1 - u) })
	end
	applyBird(rig, toCF, { wing = WING_FOLD })
end

local function perchIdle(rig, cf, dur)
	local t = 0
	-- idle-action scheduler: occasional small behaviors (head turn / hop / tail flick / wing shuffle), each an eased
	-- pulse; all channels are smoothed toward their targets so nothing snaps. Plus a constant gentle breathing bob.
	local act, actT, actDur, actSign, nextAct = nil, 0, 0, 1, rng:NextNumber(0.8, 2.0)
	local headYaw, tail, wing, hopY = 0, 0, WING_FOLD, 0
	while t < dur do
		local dt = RunService.Heartbeat:Wait()
		if not rig.model.Parent then return end
		t = t + dt
		nextAct = nextAct - dt
		if not act and nextAct <= 0 then
			act = ({ "look", "hop", "tailflick", "shuffle" })[rng:NextInteger(1, 4)]
			actT, actDur = 0, (act == "hop" and 0.45) or (act == "shuffle" and 0.5) or 0.9
			actSign = (rng:NextNumber() < 0.5) and 1 or -1
			nextAct = rng:NextNumber(1.4, 3.2)
		end
		local tHeadYaw, tTail, tWing, tHop = 0, 0, WING_FOLD, 0
		if act then
			actT = actT + dt
			local u = math.clamp(actT / actDur, 0, 1)
			local pulse = math.sin(u * math.pi)                            -- 0 -> 1 -> 0 ease
			if act == "look" then tHeadYaw = actSign * math.rad(42) * pulse
			elseif act == "hop" then tHop = pulse * 0.5; tWing = WING_FOLD + math.rad(16) * pulse
			elseif act == "tailflick" then tTail = math.rad(28) * pulse
			else tWing = WING_FOLD + math.rad(22) * pulse end              -- "shuffle": a little wing ruffle
			if u >= 1 then act = nil end
		end
		local k = math.min(dt * 8, 1)                                       -- ease channels toward their targets
		headYaw = headYaw + (tHeadYaw - headYaw) * k
		tail    = tail + (tTail - tail) * k
		wing    = wing + (tWing - wing) * k
		hopY    = hopY + (tHop - hopY) * k
		local breathe = math.sin(t * 2.1) * 0.03                           -- gentle breathing
		applyBird(rig, cf * CFrame.new(0, breathe + hopY, 0), { headYaw = headYaw, tail = tail, wing = wing })
	end
	applyBird(rig, cf, { wing = WING_FOLD })
end

--======================================================================
-- SPAWN on the (now OPPOSITE) shoulder + run the loop forever.
--======================================================================
rig = buildBird()
local curCF = shoulderCF()
applyBird(rig, curCF, { wing = WING_FOLD })
print("[BIRD COMPANION] spawned on gardener's " .. SHOULDER_SIDE .. " shoulder, perch points=" .. #perches .. ".")
print("[BIRD COMPANION] shoulder=" .. SHOULDER_SIDE .. ", shoulder rest=10s, realism pass applied.")

task.spawn(function()
	local atShoulder = true
	while rig.model.Parent do
		-- rest where we are: 10s on the shoulder, a shorter idle on a garden perch
		perchIdle(rig, curCF, atShoulder and SHOULDER_REST or rng:NextNumber(PERCH_MIN, PERCH_MAX))
		if not rig.model.Parent then break end

		local targetCF, name
		if not atShoulder and rng:NextNumber() < RETURN_CHANCE then
			targetCF, name = shoulderCF(), "shoulder"               -- sometimes head back to rest on the shoulder
		else
			targetCF, name = randomPerch()                         -- otherwise pick a garden object (may be nil if none)
		end
		if not targetCF then
			if atShoulder then continue end                        -- no perches available -> just keep resting on the shoulder
			targetCF, name = shoulderCF(), "shoulder"
		end

		if name == "shoulder" then
			print("[BIRD COMPANION] returning to shoulder.")
			targetCF = shoulderCF() -- refresh the shoulder pose at launch time (in case the gardener ever moved)
		else
			print("[BIRD COMPANION] flying to " .. tostring(name))
		end
		flyTo(rig, rig.cf, targetCF) -- start from the bird's ACTUAL current pose
		curCF = targetCF
		atShoulder = (name == "shoulder")
	end
end)
