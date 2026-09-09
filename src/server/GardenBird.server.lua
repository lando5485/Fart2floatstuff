--======================================================================
-- GardenBird.server.lua  (Script)  -- SELF-CONTAINED cosmetic songbird companion for the Gardener.
--======================================================================
-- A tiny robin-style bird that starts perched on one of the Gardener's shoulders, then loops forever: it arcs
-- out to a random perch on a Global Garden object (pillar tops, arch sign, lamp posts, fence posts, planters,
-- RewardChest, gnomes, sunflower, the sign), lands + idles a few seconds (little hops / look-around), and
-- sometimes RETURNS to the shoulder to rest before flying off again. Smoothly interpolated (per-frame CFrame
-- lerp along a curved/arc path with gentle bobbing, faces its direction of travel, wings flap while flying).
--
-- COSMETIC + ISOLATED: every part is Anchored and SOLID (CanCollide -- you can land on one), but CanQuery=false
-- so the birds' own raycasts ignore them, smooth surfaces,
-- and CFrame-driven (no physics). It only READS the gardener's HumanoidRootPart + the garden's parts to find
-- perch points -- it never modifies the gardener, his bubble, or any garden geometry. Parented to Workspace so
-- a garden stage-rebuild can't destroy it; it re-validates perch parts before each flight.
--======================================================================

local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players    = game:GetService("Players") -- island birds filter characters out of their landing raycast

local BAL, BLK = Enum.PartType.Ball, Enum.PartType.Block
local SMOOTH   = Enum.SurfaceType.Smooth

-- ===== TUNABLES =====
local FLY_SPEED   = 13                 -- studs/sec along the arc (duration = dist/FLY_SPEED, clamped)
-- FLY_MAX raised 4.2 -> 9.0 for the ISLAND birds. It only bites on legs longer than FLY_SPEED*4.2 = ~55 studs,
-- and the garden is ~42 across, so no perch-to-perch flight in the garden ever reached the old cap -- the garden
-- bird is unaffected. The island legs ARE that long, and at the old cap they were flown at ~40 studs/sec, which
-- looks like a thrown rock rather than a bird.
local FLY_MIN, FLY_MAX = 1.4, 9.0      -- clamp flight duration (sec)
-- WING FLAP (made clearly VISIBLE): each wing is a wide blade hinged at the shoulder ROOT; the flap swings it WIDE
-- up/down about the body's forward axis so the wingtip travels a big arc. Folded down at rest; in flight it beats
-- around just-above-horizontal with a large amplitude + faster/stronger beats on takeoff/climb, easing to a relaxed
-- cadence (with brief glides) while cruising.
local WING_FOLD    = math.rad(-50)     -- at rest: wings hang folded down along the flanks
local FLAP_CENTER  = math.rad(8)       -- flight beat centred just above horizontal
local FLAP_AMP_MIN = math.rad(40)      -- relaxed cruise beat amplitude (one-sided)
local FLAP_AMP_MAX = math.rad(62)      -- takeoff/climb amplitude -> tip swings from well ABOVE the body to BELOW horizontal
local FLAP_HZ_MIN  = 3.2               -- cruise beats per second
local FLAP_HZ_MAX  = 6.5               -- takeoff/climb beats per second
local PERCH_MIN, PERCH_MAX = 2.6, 5.6  -- idle time at a GARDEN perch (sec)
local SHOULDER_REST = 10                -- [TWEAK] seconds resting on the shoulder before flying off again
local RETURN_CHANCE = 0.40             -- chance to fly back to the shoulder (instead of another object)
-- [TWEAK] OPPOSITE shoulder: -X mirrors the old +0.85 to the gardener's LEFT side of the torso
local SHOULDER_OFFSET = CFrame.new(-0.85, 1.7, -0.1)
local SHOULDER_SIDE   = (SHOULDER_OFFSET.X < 0) and "left" or "right"
-- [PERCH FIX] distance from the bird's body ORIGIN down to its lowest point (feet bottom) -- the SAME body-above-feet
-- offset the shoulder pose uses. A perch landing origin = object_top + FOOT_DROP puts the feet ON the surface and the
-- body above it (no sinking). Recomputed from the actual model after buildBird; this default matches the current rig.
local FOOT_DROP = 0.88

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
-- GATHER perch points from garden objects: the exact TOP FACE of each matching part/model (position.Y + half its
-- height). The bird's foot-drop is added at landing (perchCFrame) so its feet rest ON the surface, body above.
-- (Dedup near-duplicates so clustered parts -- e.g. a pillar's stacked capitals -- give ONE perch.)
--======================================================================
local function topOfPart(p)
	local sz, cf = p.Size, p.CFrame
	local halfH = 0.5 * (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z)
	return Vector3.new(p.Position.X, p.Position.Y + halfH, p.Position.Z) -- [PERCH FIX] the TOP face (foot-drop added at landing)
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
				if ok then tryAdd(Vector3.new(cf.Position.X, cf.Position.Y + size.Y * 0.5, cf.Position.Z), n, d) end -- [PERCH FIX] top face (foot-drop added at landing)
			end
		end
	end
	-- The "Community Garden" plank board was retired, so this usually finds nothing now -- kept because it
	-- costs one lookup and a bird perched on that board was a nice shot if it ever comes back.
	local sign = Workspace:FindFirstChild("CommunityGardenSign")
	if sign and sign:IsA("BasePart") then tryAdd(topOfPart(sign), "CommunityGardenSign", sign) end
	return list
end

local perches = gatherPerches()

local rig -- forward-declared so shoulderCF()'s fallback can read the bird's last pose

--======================================================================
-- BUILD the bird: a tiny low-poly robin. Anchored cosmetic parts, smooth, solid but unqueryable. Driven entirely by
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
	-- SOLID (CanCollide), but still NOT QUERYABLE (CanQuery=false). Those two are independent and both
	-- matter here: collision is what lets a bird land on you / be bumped into, while CanQuery=false keeps
	-- birds out of every raycast this script fires -- the landing ray that finds a perch and the flight-path
	-- clearance test. Make them queryable and a bird would try to perch on another bird, and would climb to
	-- dodge one crossing its path.
	p.Anchored = true; p.CanCollide = true; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
	p.Parent = parent
	return p
end

-- Fuse a group of rounded source parts into ONE smooth solid via UnionAsync (Studio API access is on). Colours +
-- materials of each source are PRESERVED (UsePartColor = false) so a single union can carry the two-tone robin
-- coats. The union inherits the BASE part's CFrame, so building the base at the rig's local origin keeps `off`
-- identity. Returns the configured UnionOperation, or nil if the union call fails (caller then keeps loose parts).
local function fuseParts(name, base, others)
	local ok, union = pcall(function() return base:UnionAsync(others) end)
	if not ok or not union then return nil end
	union.Name = name
	union.UsePartColor = false                       -- keep each source part's own colour -> blended two-tone coat
	union.Material = Enum.Material.SmoothPlastic      -- smooth, no studs/notches
	union.Anchored = true; union.CanCollide = true; union.CanQuery = false; union.CanTouch = false
	union.CastShadow = false; union.Massless = true
	pcall(function() union.CollisionFidelity = Enum.CollisionFidelity.Box end)
	pcall(function() union.RenderFidelity   = Enum.RenderFidelity.Precise end) -- crisp curved silhouette
	union.Parent = base.Parent
	base:Destroy()
	for _, p in ipairs(others) do p:Destroy() end
	return union
end

-- A believable little songbird built from SMOOTH CURVED forms. The plump body (back/breast/belly/rump) is fused
-- with UnionAsync into ONE soft teardrop solid; the rounded head (head + crown + nape-blend + cone beak + eyes) is
-- a SECOND union on its own animated frame so it can still turn while overlapping the body with no hard neck seam.
-- Curved folded wing-blades hinge at the shoulder, a smooth fanned tail hinges at the rump, thin legs + feet perch.
-- FRONT = -Z. Built at the origin; `applyBird` poses it each frame off one root CFrame (rigid, physics-free). If a
-- union fails the same source parts are kept loose (still smooth + correct) so the bird always works -- `unionOK`
-- records which path was taken.
-- `palette` (optional) recolours the bird -- see BIRD_PALETTES below. Omit it and you get the original robin,
-- so the garden bird is untouched. Every field falls back sensibly, so a palette only has to name what differs.
local function buildBird(palette)
	palette = palette or {}
	local model = Instance.new("Model"); model.Name = "GardenBird"
	-- StreamingEnabled is ON in this place. A runtime model out over the island is far enough from spawn to
	-- be streamed OUT for a player standing in the garden -- it exists on the server and is simply invisible
	-- on the client, with nothing in the log to say so. Persistent means "always replicate", the same thing
	-- IslandStreaming does for the islands and BlimpService for the blimp.
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
	model.Parent = Workspace
	local rig = { model = model, body = {}, headParts = {}, wings = {}, cf = CFrame.new(), unionOK = true }
	local BACK   = palette.back   or Color3.fromRGB(120, 104, 86)  -- back / saddle / rump
	local BREAST = palette.breast or Color3.fromRGB(208, 84, 46)   -- warm orange-red breast
	local BELLY  = palette.belly  or Color3.fromRGB(228, 216, 196) -- pale cream belly (slightly lighter)
	local BEAK_C = palette.beak   or Color3.fromRGB(54, 44, 34)    -- short dark beak
	local LEG_C  = palette.legs   or Color3.fromRGB(150, 110, 80)  -- legs / feet
	local EYE_C  = Color3.fromRGB(16, 14, 12)                      -- eye dot (every bird has a black eye)
	-- ===== LOOK PASS: three details that do most of the work on a bird this small =====
	--  * WINGS + TAIL a shade DARKER than the back. On the old bird every feathered surface was the one brown, so
	--    the folded wing vanished into the flank and the tail read as a flat paddle stuck on the back. A darker
	--    wing/tail is what makes the silhouette legible from across the island.
	--  * A CROWN cap, so the head has a marking instead of being a plain ball of back-colour.
	--  * A pale EYE RING behind each eye -- the bird gets a face. It's a slightly larger pale ball fused just
	--    behind the (smaller, protruding) dark eye, so the ring shows around it.
	local function darker(c, f) return c:Lerp(Color3.fromRGB(0, 0, 0), f or 0.28) end
	local WING_C  = palette.wing  or darker(BACK)
	local TAIL_C  = palette.tail  or WING_C
	local CROWN_C = palette.crown or darker(BACK, 0.14)
	local RING_C  = palette.ring  or Color3.fromRGB(236, 230, 216)
	-- Two more derived tones for this pass. Both fall out of colours a palette ALREADY names, so all seven
	-- birds pick them up without a single palette edit.
	--  * COVERT_C -- the shoulder patch where a real wing meets the body. The wing is darker than the back, so
	--    the join was a hard colour step; the coverts are the band that steps between them on a real bird.
	--  * THROAT_C -- pale throat under the beak. Every one of these species has one, and on a model this small
	--    it is what stops the head reading as a ball glued to a body.
	local COVERT_C = palette.covert or BACK:Lerp(WING_C, 0.45)
	local THROAT_C = palette.throat or BELLY:Lerp(BREAST, 0.22)

	-- Build a group of rounded source parts (positioned around the rig origin), then fuse them into ONE smooth
	-- solid appended to `targetList`. On union failure the loose parts are kept (each already smooth) so the rig
	-- still poses correctly. Each spec = { name, shape, size, color, off, isWedge }; spec[1] is the union base.
	local function buildFused(unionName, specs, targetList)
		local parts = {}
		for _, s in ipairs(specs) do
			local p = newBirdPart(model, s[1], s[2], s[3], s[4], s[6])
			p.CFrame = s[5]                              -- place each source at its build offset for the fuse
			parts[#parts + 1] = p
		end
		local others = {}
		for i = 2, #parts do others[#others + 1] = parts[i] end
		local union = fuseParts(unionName, parts[1], others)
		if union then
			targetList[#targetList + 1] = { part = union, off = specs[1][5] } -- union inherits the base's CFrame
			return true
		end
		for i, p in ipairs(parts) do targetList[#targetList + 1] = { part = p, off = specs[i][5] } end -- fallback: loose
		return false
	end

	-- BODY: overlapping balls -> ONE smooth teardrop. Brown back/saddle, orange breast up front, pale belly under,
	-- a small rump that tapers toward the tail. Fused so the seams flow together into a single plump form.
	local bodyOK = buildFused("BodyMesh", {
		{ "BodyCore", BAL, Vector3.new(1.18, 1.10, 1.46), BACK,   CFrame.new(0,  0.00,  0.00), false }, -- base (union origin)
		{ "Saddle",   BAL, Vector3.new(0.94, 0.76, 1.04), BACK,   CFrame.new(0,  0.22,  0.16), false }, -- brown back / top
		{ "Breast",   BAL, Vector3.new(1.00, 0.96, 0.84), BREAST, CFrame.new(0, -0.06, -0.54), false }, -- warm orange front
		{ "Belly",    BAL, Vector3.new(1.02, 0.78, 1.14), BELLY,  CFrame.new(0, -0.34,  0.00), false }, -- pale underside
		{ "Rump",     BAL, Vector3.new(0.72, 0.66, 0.76), BACK,   CFrame.new(0,  0.14,  0.66), false }, -- taper to the tail
	}, rig.body)

	-- LEGS + small forward FEET (perch look) -- slim separate parts, in their OWN list (rig.legs) rather than
	-- rig.body, because they have to move independently of it: a bird in flight TUCKS its legs up under the
	-- tail. Dangling legs are the single biggest tell that a flying model is a prop -- real birds pull them in
	-- the moment they leave the perch and only drop them again to land. applyBird poses these off `legTuck`.
	-- TOES. The foot was a single 0.22 x 0.07 x 0.32 block -- a paddle. A perching bird is defined by its feet
	-- gripping the branch, and three forward toes with one back (anisodactyl, which every songbird here is)
	-- is a shape you read instantly even at a few studs. Fused per foot so each stays the ONE part applyBird
	-- poses; the overall footprint is the same 0.24 x 0.34 the block occupied, so nothing sinks or floats.
	local function buildFoot(name)
		local list = {}
		local ok = buildFused(name, {
			{ "FootPad",  BLK, Vector3.new(0.11, 0.06, 0.11), LEG_C, CFrame.new(0, 0, 0), false }, -- base = ankle, union origin
			{ "ToeMid",   BLK, Vector3.new(0.05, 0.05, 0.22), LEG_C, CFrame.new(0, -0.005, -0.13), false },
			{ "ToeL",     BLK, Vector3.new(0.05, 0.05, 0.20), LEG_C, CFrame.new(-0.06, -0.005, -0.11) * CFrame.Angles(0, math.rad(-22), 0), false },
			{ "ToeR",     BLK, Vector3.new(0.05, 0.05, 0.20), LEG_C, CFrame.new( 0.06, -0.005, -0.11) * CFrame.Angles(0, math.rad( 22), 0), false },
			{ "ToeBack",  BLK, Vector3.new(0.05, 0.05, 0.14), LEG_C, CFrame.new(0, -0.005,  0.09), false }, -- the hind toe that closes the grip
		}, list)
		if ok then return list[1].part end
		for _, e in ipairs(list) do e.part:Destroy() end
		return newBirdPart(model, name, BLK, Vector3.new(0.22, 0.07, 0.32), LEG_C)
	end

	rig.legs = {}
	for _, sx in ipairs({ -0.22, 0.22 }) do
		rig.legs[#rig.legs + 1] = { part = newBirdPart(model, "Leg",  BLK, Vector3.new(0.10, 0.34, 0.10), LEG_C), off = CFrame.new(sx, -0.66, 0.04) }
		rig.legs[#rig.legs + 1] = { part = buildFoot("Foot"), off = CFrame.new(sx, -0.83, -0.05) }
	end

	-- HEAD on its OWN frame (so it can still turn): head + crown + a NAPE ball that blends down/back into the body
	-- (hiding the neck seam) + a small smooth cone-style beak + two rounded eyes -- all fused into one smooth dome.
	rig.headBase = CFrame.new(0, 0.50, -0.62)
	local headOK = buildFused("HeadMesh", {
		{ "HeadBall", BAL, Vector3.new(0.86, 0.82, 0.86), BACK,    CFrame.new(0,  0.00,  0.00), false }, -- base (head pivot)
		{ "Crown",    BAL, Vector3.new(0.60, 0.46, 0.60), CROWN_C, CFrame.new(0,  0.22,  0.06), false }, -- cap marking
		{ "Nape",     BAL, Vector3.new(0.74, 0.66, 0.80), BACK,    CFrame.new(0, -0.18,  0.30), false }, -- blend into body (no neck seam)
		{ "Throat",   BAL, Vector3.new(0.46, 0.34, 0.38), THROAT_C, CFrame.new(0, -0.26, -0.24), false }, -- pale bib under the beak, blends into the breast
		-- TWO MANDIBLES, not one cone. A single wedge gave a rigid dart of a beak with a flat underside; a real
		-- bill is an upper half that overhangs a shorter, shallower lower half, and the seam between them is
		-- most of what reads as a beak at all. The upper is pitched down ~5 degrees (bills are not level with
		-- the skull) and the lower tucked up under it, so the profile closes to a point instead of a blunt end.
		{ "BeakUpper", nil, Vector3.new(0.24, 0.17, 0.46), BEAK_C,  CFrame.new(0, -0.02, -0.51) * CFrame.Angles(math.rad(-5), math.rad(180), 0), true },
		{ "BeakLower", nil, Vector3.new(0.20, 0.10, 0.34), darker(BEAK_C, 0.22), CFrame.new(0, -0.14, -0.45) * CFrame.Angles(math.rad(7), math.rad(180), 0), true },
		-- eye ring FIRST (larger, set slightly back), then the dark eye in front of it so the pale ring shows around it
		{ "EyeRing",  BAL, Vector3.new(0.24, 0.24, 0.24), RING_C,  CFrame.new(-0.27, 0.07, -0.26), false },
		{ "EyeRing",  BAL, Vector3.new(0.24, 0.24, 0.24), RING_C,  CFrame.new( 0.27, 0.07, -0.26), false },
		{ "Eye",      BAL, Vector3.new(0.17, 0.17, 0.17), EYE_C,   CFrame.new(-0.27, 0.08, -0.32), false },
		{ "Eye",      BAL, Vector3.new(0.17, 0.17, 0.17), EYE_C,   CFrame.new( 0.27, 0.08, -0.32), false },
	}, rig.headParts)

	rig.unionOK = bodyOK and headOK

	-- TAIL: a FANNED set of feathers, fused into one smooth solid on a hinge at the rump.
	--
	-- This was a single 1.00 x 0.08 x 1.06 slab -- a flat rectangular paddle stuck on the back, and the least
	-- bird-like thing on the model. A real tail is a FAN of separate feathers that splay outward and get
	-- shorter toward the edges, and that splay is most of what reads as "bird" in silhouette from a distance.
	--
	-- Five feathers: a long centre pair and two shorter outer ones angled out ~14 and ~27 degrees, all fused
	-- into ONE part so `rig.tail` stays a single part and applyBird's posing is untouched. Built narrow at
	-- the rump and spreading toward the tip, so it tapers the right way round.
	rig.tailBase = CFrame.new(0, 0.16, 0.92)
	do
		local featherSpecs = {}
		-- { sideways offset, yaw outward (deg), length, width }
		for _, f in ipairs({
			{  0.00,   0, 1.10, 0.30 },  -- centre feather: longest -- this is the union base
			{ -0.17, -14, 0.98, 0.26 },
			{  0.17,  14, 0.98, 0.26 },
			{ -0.31, -27, 0.80, 0.22 },  -- outermost: shortest, splayed widest
			{  0.31,  27, 0.80, 0.22 },
		}) do
			local dx, yaw, len, wid = f[1], f[2], f[3], f[4]
			featherSpecs[#featherSpecs + 1] = {
				"TailFeather", BLK, Vector3.new(wid, 0.07, len), TAIL_C,
				-- pushed back by half its own length so every feather starts at the SAME rump line and only
				-- differs in how far it reaches -- otherwise the short ones float away from the body
				CFrame.new(dx, 0, len * 0.5 - 0.55) * CFrame.Angles(0, math.rad(yaw), 0),
				false,
			}
		end
		local tailList = {}
		local fanOK = buildFused("TailMesh", featherSpecs, tailList)
		if not fanOK then
			-- UNION FAILED -> FALL BACK TO THE OLD SINGLE SLAB, not to one lone feather.
			-- rig.tail is ONE part that applyBird poses from a single hinge; it cannot drive five loose
			-- feathers. Keeping only the centre one would leave the bird with a thin spike instead of a tail,
			-- which is worse than the paddle this replaced. So on failure the loose sources are cleared and
			-- the original wide slab is rebuilt -- the fan is an upgrade when it works and costs nothing when
			-- it doesn't.
			for _, e in ipairs(tailList) do e.part:Destroy() end
			tailList = { { part = newBirdPart(model, "Tail", BLK, Vector3.new(1.00, 0.08, 1.06), TAIL_C) } }
		end
		rig.tail = { part = tailList[1].part, off = CFrame.new(0, 0.02, 0.42) * CFrame.Angles(math.rad(16), 0, 0) }
	end

	-- WINGS: smooth folded blades that sit flush along the flanks, each hinged at the shoulder ROOT (pivot). The flap
	-- rotates the whole blade up/down about the body's forward (Z) axis, so the far WINGTIP travels a big vertical arc
	-- (mirrored L/R: side +1 left / -1 right). Built lying out horizontally; the flap angle is driven each frame.
	-- TWO SEGMENTS PER WING (arm + hand), not one blade. A single rigid blade rotating about the shoulder is
	-- the other big tell -- real wings bend at the wrist, and the outer half (the primaries) LAGS behind the
	-- inner half through the beat, so the tip traces a shallow figure-of-eight instead of a rigid see-saw.
	-- applyBird drives the outer segment off its own angle (`wingOuter`), which flyTo feeds a phase-delayed
	-- copy of the main flap. The hand is also narrower and swept slightly back, so the wing tapers to a point.
	-- POINTED WINGTIPS. The hand was a 0.64 x 0.07 x 0.40 rectangle, so despite the comment above about the
	-- wing "tapering to a point" it actually ended in a blunt square edge -- the one place the silhouette
	-- still read as two slabs rather than a wing. The hand is now fused from three pieces: the main blade, a
	-- half-width mid piece, and a small tip, each shorter and set further out, so the outer half steps down
	-- to an actual point. Fused into ONE part, because applyBird poses `outer` as a single part off the wrist.
	-- TAPERED ARM. The arm was one 0.68 x 0.09 x 0.54 rectangle -- the last straight edge left in the
	-- silhouette, and the reason the wing still read as a plank with a point stuck on the end. A real wing is
	-- DEEPEST where it meets the body (the secondaries) and narrows toward the wrist, so this is fused from
	-- three sections that step down in chord, plus a lighter covert patch riding on top at the shoulder.
	--
	-- The span is unchanged at 0.68 and the union origin sits exactly where the old block's centre was, so
	-- `innerOff` / `wrist` / the whole of applyBird need no adjustment -- this is a shape swap, not a rig change.
	local function buildArm(name, side)
		local list = {}
		local ok = buildFused(name, {
			{ "ArmMid",   BLK, Vector3.new(0.30, 0.09, 0.54), WING_C,   CFrame.new(0, 0, 0.00), false },              -- base = union origin
			{ "ArmRoot",  BLK, Vector3.new(0.26, 0.10, 0.60), WING_C,   CFrame.new(side * -0.21, 0, 0.02), false },   -- deepest, against the body
			{ "ArmWrist", BLK, Vector3.new(0.26, 0.08, 0.46), WING_C,   CFrame.new(side *  0.21, 0, 0.04), false },   -- narrowing into the wrist
			{ "Coverts",  BLK, Vector3.new(0.30, 0.06, 0.32), COVERT_C, CFrame.new(side * -0.14, 0.045, -0.10), false }, -- lighter shoulder band on top
		}, list)
		if ok then return list[1].part end
		-- Same rule as the tail and the hand: `inner` must be ONE part for applyBird to pose, so a failed
		-- union rebuilds the original single blade rather than leaving four loose sections behind.
		for _, e in ipairs(list) do e.part:Destroy() end
		return newBirdPart(model, name, BLK, Vector3.new(0.68, 0.09, 0.54), WING_C)
	end

	local function buildHand(name, side)
		local list = {}
		local ok = buildFused(name, {
			{ "HandBlade", BLK, Vector3.new(0.34, 0.07, 0.40), WING_C, CFrame.new(side * -0.15, 0, 0.00), false }, -- base (union origin = the hand's own frame)
			{ "HandMid",   BLK, Vector3.new(0.22, 0.06, 0.30), WING_C, CFrame.new(side *  0.13, 0, 0.03), false },
			{ "HandTip",   BLK, Vector3.new(0.14, 0.05, 0.20), WING_C, CFrame.new(side *  0.29, 0, 0.06), false }, -- the point
		}, list)
		if ok then return list[1].part end
		-- Same reasoning as the tail: `outer` must be ONE part, so a failed union falls back to the original
		-- single blade rather than leaving three loose pieces the poser cannot drive.
		for _, e in ipairs(list) do e.part:Destroy() end
		return newBirdPart(model, name, BLK, Vector3.new(0.64, 0.07, 0.40), WING_C)
	end

	for _, side in ipairs({ 1, -1 }) do
		local tag = (side == 1) and "L" or "R"
		rig.wings[#rig.wings + 1] = {
			inner    = buildArm("WingArm" .. tag, side),
			outer    = buildHand("WingHand" .. tag, side),
			side     = side,
			pivot    = CFrame.new(side * 0.30, 0.16, -0.05), -- shoulder hinge = the WING ROOT (rotation pivot)
			innerOff = CFrame.new(side * 0.34, 0, 0.02),     -- arm centre, half its span out from the shoulder
			wrist    = CFrame.new(side * 0.68, 0, 0.02),     -- elbow/wrist joint: where the hand hinges
			outerOff = CFrame.new(side * 0.32, 0, 0.09),     -- hand centre, swept a touch back for the taper
		}
	end
	return rig
end

-- pose the whole bird off one root CFrame.
-- anim = { wing, wingOuter, lean, tail, headYaw, headPitch, legTuck } (all optional, eased by callers)
local function applyBird(rig, cf, anim)
	anim = anim or {}
	local lean = anim.lean or 0
	local bcf = cf * CFrame.Angles(0, 0, lean)                           -- bank/lean into turns
	for _, e in ipairs(rig.body) do e.part.CFrame = bcf * e.off end
	-- HEAD HELD LEVEL. A banking bird counter-rolls its head to keep its eyes on the horizon -- it's the
	-- thing that makes a turning bird look like an animal steering rather than a model being rotated. Undoing
	-- most (not all) of the body's roll on the head frame is that, in one term.
	local hf = bcf * rig.headBase * CFrame.Angles(anim.headPitch or 0, anim.headYaw or 0, -lean * 0.55)
	for _, e in ipairs(rig.headParts) do e.part.CFrame = hf * e.off end
	rig.tail.part.CFrame = bcf * rig.tailBase * CFrame.Angles(anim.tail or 0, 0, 0) * rig.tail.off
	-- LEGS: 0 = down (perched), 1 = tucked up under the tail (flight).
	local tuck = anim.legTuck or 0
	if rig.legs then
		for _, e in ipairs(rig.legs) do
			e.part.CFrame = bcf * e.off
				* CFrame.new(0, 0.30 * tuck, 0.26 * tuck)                -- draw up and back toward the tail
				* CFrame.Angles(math.rad(-72) * tuck, 0, 0)              -- and fold them flat against the belly
		end
	end
	-- WINGS: arm rotates at the shoulder, hand rotates again at the wrist (its own, lagging angle).
	local wing  = anim.wing or WING_FOLD
	local outer = anim.wingOuter or wing
	for _, w in ipairs(rig.wings) do
		local shoulder = bcf * w.pivot * CFrame.Angles(0, 0, w.side * wing)
		w.inner.CFrame = shoulder * w.innerOff
		w.outer.CFrame = shoulder * w.wrist * CFrame.Angles(0, 0, w.side * outer) * w.outerOff
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
	-- [PERCH FIX] sit the body FOOT_DROP above the object's top face -> feet rest ON the surface, body above (matches shoulder)
	local landPos = Vector3.new(p.pos.X, p.pos.Y + FOOT_DROP, p.pos.Z)
	local toC = Vector3.new(gardenCenter.X - landPos.X, 0, gardenCenter.Z - landPos.Z) -- face inward toward the garden
	if toC.Magnitude < 1 then toC = Vector3.new(0, 0, -1) end
	return CFrame.lookAt(landPos, landPos + toC.Unit)
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

-- ===== DON'T FLY THROUGH THINGS =====================================================================
-- The flight path is an arc through open air, and nothing was ever checking what was ON that arc -- so a
-- leg that happened to cross a house, a tree or the hillside went straight through it. This walks the arc
-- and raycasts between consecutive samples; the caller then RAISES the arc and re-tests until it's clear.
--
-- Bird parts are CanQuery=false, so a bird can never block another bird. Player characters are filtered out
-- (a player standing on the path shouldn't reroute a bird -- the 5-stud flush below handles people). The
-- last sample stops SHORT of the goal: a landing leg ENDS on a surface, and testing right into it would
-- report every single landing as blocked.
local function pathBlocked(a, ctrl, b, stopShort)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then ignore[#ignore + 1] = p.Character end
	end
	params.FilterDescendantsInstances = ignore
	local SAMPLES = 9
	local last = a
	for i = 1, SAMPLES do
		local t = (i / SAMPLES) * (stopShort and 0.86 or 1)
		local pt = bez(a, ctrl, b, t)
		local seg = pt - last
		if seg.Magnitude > 0.05 and Workspace:Raycast(last, seg, params) then
			return true
		end
		last = pt
	end
	return false
end

-- `noLand` (added for the island birds): skip the landing settle at the end. A bird that is heading straight
-- into its next leg must not dip, fold its wings and stop -- that's a perch arrival, and mid-air it reads as a
-- stall. With noLand the flight simply ends on the waypoint at full wing and the next flyTo picks up from there.
local function flyTo(rig, fromCF, toCF, noLand)
	local startP, goalP = fromCF.Position, toCF.Position
	local dist = (goalP - startP).Magnitude
	local dur  = math.clamp(dist / FLY_SPEED, FLY_MIN, FLY_MAX)
	-- curved/arc control point: lift up + bow out to one side so the path circles toward the target (not a straight line)
	local mid  = (startP + goalP) * 0.5
	local flat = Vector3.new(goalP.X - startP.X, 0, goalP.Z - startP.Z)
	local perp = (flat.Magnitude > 0.1) and Vector3.new(-flat.Z, 0, flat.X).Unit or Vector3.new(1, 0, 0)
	local ctrl = mid + Vector3.new(0, math.clamp(dist * 0.30, 3, 9), 0) + perp * ((rng:NextNumber() < 0.5 and 1 or -1) * math.clamp(dist * 0.32, 2, 8))
	-- CLEAR THE PATH. If the arc runs through something, lift it and try again -- a bird that meets an
	-- obstacle climbs over it, which is both what a real bird does and the cheapest fix here (the alternative,
	-- steering sideways mid-flight, needs a whole avoidance loop). Four lifts of 9 studs clears anything on
	-- these islands; if it still won't clear we fly the raised arc anyway rather than freezing in place.
	for _ = 1, 4 do
		if not pathBlocked(startP, ctrl, goalP, not noLand) then break end
		ctrl = ctrl + Vector3.new(0, 9, 0)
	end
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
		-- EFFORT 0 (relaxed cruise / glide) .. 1 (hard takeoff/climb): strong early in the flight + while climbing
		local climb   = (pos.Y - prevPos.Y) / math.max(dt, 1 / 120)
		local takeoff = math.max(0, 1 - t * 2.5)                            -- strong through the first ~40% of the flight
		local effort  = math.clamp(takeoff + math.clamp(climb / 5, 0, 1), 0, 1)
		-- BANK into the turn (eased): roll proportional to how fast the heading is rotating
		local hd = Vector3.new(dir.X, 0, dir.Z)
		if hd.Magnitude > 0.01 then
			hd = hd.Unit
			local targetLean = math.clamp(prevHd:Cross(hd).Y * 9, -math.rad(30), math.rad(30))
			lean = lean + (targetLean - lean) * math.min(dt * 6, 1)
			prevHd = hd
		end
		-- WIDE flap: amplitude AND beat rate both grow with effort; cruise = relaxed wide beat with brief glides
		local amp   = FLAP_AMP_MIN + (FLAP_AMP_MAX - FLAP_AMP_MIN) * effort
		local hz    = FLAP_HZ_MIN + (FLAP_HZ_MAX - FLAP_HZ_MIN) * effort
		local glide = (effort < 0.2) and (0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * math.pi * 2.2))) or 1 -- brief relaxed glides while cruising
		flapPhase = flapPhase + dt * hz * (2 * math.pi)                     -- hz = beats/sec; FASTER on takeoff/climb
		local wing = FLAP_CENTER + math.sin(flapPhase) * amp * glide        -- wings swing WIDE up/down about the shoulder root
		-- The HAND (outer wing) runs a beat behind the arm -- that lag is what makes a wingbeat look like
		-- a flexing wing instead of a rigid see-saw, and it deepens with effort exactly as a real one does.
		local outerWing = FLAP_CENTER + math.sin(flapPhase - 0.85) * amp * glide * (0.75 + 0.45 * effort)
		-- LEGS UP. Tucked within the first quarter of the flight (a real bird pulls them in right after the
		-- push-off) and, on a landing leg, dropped again during the flare below.
		local legTuck = math.min(1, t * 4)
		local cf = (dir.Magnitude > 0.01) and CFrame.lookAt(pos, pos + dir) or (CFrame.new(pos) * toCF.Rotation) -- always face travel
		-- The head LEADS the turn: a bird looks where it is going before its body gets there. Plus a little
		-- pitch up while climbing hard.
		applyBird(rig, cf, {
			wing = wing, wingOuter = outerWing, lean = lean,
			tail = math.rad(6) * effort,
			headYaw = -lean * 0.45,
			headPitch = math.rad(-7) * effort,
			legTuck = legTuck,
		})
		prevPos = pos
	end
	if noLand then return end -- mid-air waypoint: no dip, no wing-fold, straight on to the next leg
	-- LAND: a proper FLARE, then settle. A bird doesn't just stop and fold -- it throws its wings up and
	-- forward to brake, fans the tail down as an airbrake, swings its legs out ahead to take the impact, and
	-- only then settles and folds. Two phases: flare (wings sweeping UP past the beat, legs coming down,
	-- tail fanned), then settle (dip, wings folding to rest, tail relaxing).
	local FLARE, SETTLE = 0.30, 0.34
	local FLARE_WING = FLAP_CENTER + math.rad(58)                          -- wings held high + cupped to brake
	local st = 0
	while st < FLARE do
		local dt = RunService.Heartbeat:Wait()
		if not rig.model.Parent then return end
		st = st + dt
		local u = math.min(1, st / FLARE)
		local wing = FLAP_CENTER + (FLARE_WING - FLAP_CENTER) * u
		applyBird(rig, toCF * CFrame.new(0, 0.10 * (1 - u), 0), {          -- drops the last few inches onto the perch
			wing = wing,
			wingOuter = wing + math.rad(16) * u,                           -- hand cups further than the arm
			lean = (1 - u) * lean,
			tail = math.rad(34) * u,                                       -- tail fanned DOWN as an airbrake
			headPitch = math.rad(6) * u,                                   -- head comes up as it flares
			legTuck = 1 - u,                                               -- legs swing forward for the landing
		})
	end
	st = 0
	while st < SETTLE do
		local dt = RunService.Heartbeat:Wait()
		if not rig.model.Parent then return end
		st = st + dt
		local u = math.min(1, st / SETTLE)
		local bob  = math.sin(u * math.pi) * -0.16                         -- small settle dip as the legs take the weight
		local wing = FLARE_WING + (WING_FOLD - FLARE_WING) * u             -- fold the wings down onto the flanks
		applyBird(rig, toCF * CFrame.new(0, bob, 0), {
			wing = wing, wingOuter = wing,
			tail = math.rad(34) * (1 - u),
			headPitch = math.rad(6) * (1 - u),
		})
	end
	applyBird(rig, toCF, { wing = WING_FOLD })
end

-- `flushDist` (island birds only): if a player comes within this many studs, stop idling immediately and
-- return "flushed" so the caller can launch. Wild birds do not sit still while something walks up to them --
-- they break off and go. The GARDEN bird passes no flushDist: it lives on the gardener's shoulder and in his
-- garden, where players are meant to walk right up, and a bird that bolts from its own owner is worse than
-- one that never reacts. Checked once every few frames, not every frame -- it's a distance test per player,
-- and a 0.15s reaction is still faster than anyone can close 5 studs.
local function perchIdle(rig, cf, dur, flushDist)
	local t = 0
	-- idle-action scheduler: occasional small behaviors (head turn / hop / tail flick / wing shuffle), each an eased
	-- pulse; all channels are smoothed toward their targets so nothing snaps. Plus a constant gentle breathing bob.
	local act, actT, actDur, actSign, nextAct = nil, 0, 0, 1, rng:NextNumber(0.8, 2.0)
	local headYaw, tail, wing, hopY = 0, 0, WING_FOLD, 0
	local flushCheck = 0
	while t < dur do
		local dt = RunService.Heartbeat:Wait()
		if not rig.model.Parent then return end
		t = t + dt
		if flushDist then
			flushCheck = flushCheck - dt
			if flushCheck <= 0 then
				flushCheck = 0.15
				local here = rig.cf.Position
				for _, p in ipairs(Players:GetPlayers()) do
					local ch = p.Character
					local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
					if hrp and (hrp.Position - here).Magnitude <= flushDist then
						return "flushed", hrp.Position
					end
				end
			end
		end
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
do -- [PERCH FIX] measure the model's real foot-drop (origin -> lowest point) so perch landings match the shoulder's body-above-feet pose
	local lowest = 0
	for _, list in ipairs({ rig.body, rig.legs }) do -- legs live in their own list now, and they ARE the lowest point
		for _, e in ipairs(list) do lowest = math.min(lowest, e.off.Position.Y - e.part.Size.Y * 0.5) end
	end
	if lowest < 0 then FOOT_DROP = -lowest end
end
local curCF = shoulderCF()
applyBird(rig, curCF, { wing = WING_FOLD })
do -- report the rebuilt smooth model
	local partCount = 0
	for _, d in ipairs(rig.model:GetDescendants()) do if d:IsA("BasePart") then partCount += 1 end end
	print(string.format("[BIRD COMPANION] model rebuilt smooth (union ok=%s), parts=%d.", rig.unionOK and "y" or "n", partCount))
end
print("[BIRD COMPANION] spawned on gardener's " .. SHOULDER_SIDE .. " shoulder, perch points=" .. #perches .. ".")
print("[BIRD COMPANION] shoulder=" .. SHOULDER_SIDE .. ", shoulder rest=10s, realism pass applied.")
print(string.format("[BIRD COMPANION] wing flap amplitude=%ddeg, beats/sec flying=%.1f, visible flap=yes.", math.floor(math.deg(FLAP_AMP_MAX) + 0.5), FLAP_HZ_MIN))

task.spawn(function()
	local atShoulder, perchFixLogged = true, false
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
		if name ~= "shoulder" and not perchFixLogged then
			perchFixLogged = true
			print("[BIRD COMPANION] perch offset fixed -> sits on top of " .. tostring(name) .. ", feet-on-surface.")
		end
		curCF = targetCF
		atShoulder = (name == "shoulder")
	end
end)

--======================================================================
-- ISLAND BIRDS: SIX more of the same robin, living out on the island instead of in the garden.
--======================================================================
-- Same bird, different job. They're built by the SAME buildBird() and posed by the SAME applyBird()/flyTo()/
-- perchIdle(), so they are the garden bird in every visible respect -- same smooth union body, same wide flap,
-- same banking into turns, same little hop-and-settle when they land. Copying the ~200 lines of model + flight
-- code into a second script would have meant two rigs to keep in sync forever.
--
-- WHAT'S DIFFERENT, and why:
--   * NO SHOULDER, NO NAMED PERCH LIST. The garden bird works off hand-gathered garden objects (pillar caps,
--     lamp posts, planters). Out on the island there is no such list -- houses, rocks, fences, trees, hillside,
--     all differently named -- so a landing spot is found by RAYCASTING DOWN and using whatever is there.
--   * A SECTOR EACH. Six birds sharing one orbit is six birds in a queue through the same airspace, which
--     from the ground reads as one bird you keep seeing again. Each owns a sixth of the island and stays in
--     it, so wherever you are there is a bird nearby and it isn't the same bird as the last one.
--   * A FLOOR ON HOW MANY ARE UP. At least three are airborne at any moment -- see MIN_AIRBORNE.
--   * FLY, THEN SOMETIMES SIT. Air legs use flyTo(..., noLand) so the wings never fold mid-flight; a landing
--     leg uses the normal flyTo and then perchIdle, giving the full dip-settle-fold and the idle hops.
--
-- COST: server-side like the garden bird (CFrame per frame, replicated), which is right for something every
-- player should see in the same place. Seven small models is cheap; the twenty client-side critters in
-- AmbientWildlife are the ones that would have been expensive here.
do
	local ISLAND_BIRDS = 6
	local R_MIN, R_MAX  = 55, 155   -- studs from the island centre
	local H_MIN, H_MAX  = 20, 47    -- studs above the island's SURFACE (ceiling cut 25%: 62 -> 47)
	local STEP_MIN, STEP_MAX = 0.30, 0.60 -- radians of arc per leg (kept inside the bird's own sector)
	-- EACH BIRD OWNS A SLICE OF THE ISLAND. Six birds on one shared orbit is six birds in a queue: they pass
	-- through the same airspace and, from the ground, read as one bird you keep seeing again. So the island is
	-- split into ISLAND_BIRDS equal sectors (60 degrees each at six) and every bird patrols only its own,
	-- wandering inside it rather than lapping the whole island. Change the count and the sectors re-divide
	-- themselves -- there is no per-bird placement to keep in step with it.
	local SECTOR_HALF = (math.pi / ISLAND_BIRDS) * 0.82 -- most of its wedge, with a gap so two never overlap
	local LAND_CHANCE = 0.42        -- after each air leg, the odds it comes down to perch instead of flying on
	-- Short stops only: 2.5s is the CEILING, so nothing ever sits there long enough to read as furniture --
	-- these are birds passing through, not statues. A player inside FLUSH_DIST cuts it shorter still.
	local PERCH_STAY_MIN, PERCH_STAY_MAX = 1.2, 2.5 -- seconds sat on whatever it landed on
	local FLUSH_DIST  = 25          -- studs: get this close to a perched bird and it takes off
	-- ALWAYS SOMETHING IN THE AIR. Each bird decides for itself whether to land, and left alone those rolls
	-- eventually line up and the whole flock is on the ground (or all diving for it) at the same moment --
	-- the sky goes empty and the island reads as dead, which is the exact thing these birds exist to fix.
	-- A shared count of how many are down or on their way down caps it: at least MIN_AIRBORNE are always up.
	-- The count is claimed BEFORE the descent, not on touchdown, so three birds can't all commit to landing
	-- in the same instant and then argue about it.
	local MIN_AIRBORNE = 3
	local MAX_GROUNDED = math.max(0, ISLAND_BIRDS - MIN_AIRBORNE)
	local grounded = 0              -- birds currently descending, landing, perched, or taking off again

	-- SEVEN DIFFERENT BIRDS. The garden one keeps the original robin colours (it builds with no palette at all);
	-- these six are a BLUEBIRD, GOLDFINCH, CARDINAL, PARAKEET, ORIOLE and VIOLET STARLING -- blue, yellow, red,
	-- green, orange, violet. Deliberately six different HUES rather than six shades of one: at flying distance a
	-- bird is a moving dot and only the hue survives. Each is still a real species' scheme so they read as birds and not as painted blobs -- dark
	-- cap, darker wings, pale belly, with the bright colour on the back and breast.
	local BIRD_PALETTES = {
		{ -- 1: BLUEBIRD -- deep blue above, rust breast, white belly
			name   = "Bluebird",
			back   = Color3.fromRGB( 58, 102, 196),
			crown  = Color3.fromRGB( 42,  78, 168),
			wing   = Color3.fromRGB( 34,  62, 140),
			tail   = Color3.fromRGB( 34,  62, 140),
			breast = Color3.fromRGB(206, 116,  62),
			belly  = Color3.fromRGB(240, 238, 230),
			beak   = Color3.fromRGB( 40,  40,  46),
			legs   = Color3.fromRGB( 72,  68,  70),
		},
		{ -- 2: GOLDFINCH -- bright yellow, black cap and wings
			name   = "Goldfinch",
			back   = Color3.fromRGB(226, 194,  60),
			crown  = Color3.fromRGB( 34,  32,  30),
			wing   = Color3.fromRGB( 44,  42,  40),
			tail   = Color3.fromRGB( 44,  42,  40),
			breast = Color3.fromRGB(248, 216,  74),
			belly  = Color3.fromRGB(250, 242, 206),
			beak   = Color3.fromRGB(232, 172, 110),
			legs   = Color3.fromRGB(198, 152,  92),
		},
		{ -- 3: CARDINAL -- crimson all over, black mask, orange beak
			name   = "Cardinal",
			back   = Color3.fromRGB(202,  46,  42),
			crown  = Color3.fromRGB(160,  28,  28),
			wing   = Color3.fromRGB(146,  30,  28),
			tail   = Color3.fromRGB(146,  30,  28),
			breast = Color3.fromRGB(232,  66,  54),
			belly  = Color3.fromRGB(244, 170, 150),
			beak   = Color3.fromRGB(240, 148,  52),
			legs   = Color3.fromRGB(150,  96,  70),
			ring   = Color3.fromRGB( 40,  30,  30), -- black mask instead of a pale ring
		},
		{ -- 4: PARAKEET -- leaf green with a teal cap
			name   = "Parakeet",
			back   = Color3.fromRGB( 74, 176,  76),
			crown  = Color3.fromRGB( 46, 152, 138),
			wing   = Color3.fromRGB( 40, 128,  60),
			tail   = Color3.fromRGB( 40, 128,  60),
			breast = Color3.fromRGB(140, 210,  86),
			belly  = Color3.fromRGB(228, 240, 198),
			beak   = Color3.fromRGB(236, 198,  96),
			legs   = Color3.fromRGB(178, 150,  86),
		},
		{ -- 5: ORIOLE -- vivid orange body, black hood and wings
			name   = "Oriole",
			back   = Color3.fromRGB(240, 138,  30),
			crown  = Color3.fromRGB( 30,  28,  28),
			wing   = Color3.fromRGB( 38,  36,  36),
			tail   = Color3.fromRGB( 38,  36,  36),
			breast = Color3.fromRGB(250, 168,  52),
			belly  = Color3.fromRGB(252, 214, 150),
			beak   = Color3.fromRGB( 92,  92, 100),
			legs   = Color3.fromRGB( 96,  92,  96),
		},
		{ -- 6: VIOLET STARLING -- deep iridescent purple, lilac underside
			name   = "VioletStarling",
			back   = Color3.fromRGB(124,  76, 200),
			crown  = Color3.fromRGB( 94,  52, 168),
			wing   = Color3.fromRGB( 78,  44, 146),
			tail   = Color3.fromRGB( 78,  44, 146),
			breast = Color3.fromRGB(158, 108, 226),
			belly  = Color3.fromRGB(226, 210, 246),
			beak   = Color3.fromRGB( 44,  40,  52),
			legs   = Color3.fromRGB( 80,  70,  88),
			ring   = Color3.fromRGB(250, 226, 120), -- pale gold eye ring, the starling's one bright marking
		},
	}

	-- The island the garden sits on (Bean Farm). NAME MATCHING IS NORMALISED, not the "^Island_1_" pattern a
	-- few scripts in this repo use: the models in this place are actually named `island1` .. `island14`
	-- (lowercase, no suffix), so an "Island_1_" match finds NOTHING and every bird would silently fall back to
	-- the garden centre. Lowercasing + stripping separators catches both spellings, and the digit guard stops
	-- "island1" from matching island10..14. (Same finder GardenerWave/IslandNPCs use.)
	local function normName(s) return (tostring(s):lower():gsub("[%s_%-%.]", "")) end
	local function findIslandCentre()
		for _, m in ipairs(Workspace:GetChildren()) do
			if m:IsA("Model") then
				local nm = normName(m.Name)
				if nm:sub(1, 7) == "island1" and not tonumber(nm:sub(8, 8)) then
					local ok, cf = pcall(function() return m:GetPivot() end)
					if ok then
						-- X/Z FROM THE ISLAND, Y FROM THE GARDEN. The island MODEL's pivot sits ~90 studs
						-- BELOW the surface you walk on (the log reads "centre = 0, 150, 0" while the spawn
						-- stand is at Y=245 and the garden floor at Y=241) -- it's the pivot of the whole
						-- island solid, rock and all. Circling at "height 38" above THAT put both birds
						-- underneath the island, which is exactly why they were nowhere to be seen. The
						-- garden is built ON the surface, so its centre is the real ground height.
						local groundY = (gardenCenter.Y ~= 0) and gardenCenter.Y or cf.Position.Y
						return Vector3.new(cf.Position.X, groundY, cf.Position.Z)
					end
				end
			end
		end
		return nil
	end

	task.spawn(function()
		local centre
		for _ = 1, 60 do -- islands stream/build in; give it 30s before settling for the garden centre
			centre = findIslandCentre()
			if centre then break end
			task.wait(0.5)
		end
		centre = centre or gardenCenter
		print(("[ISLAND BIRDS] centre = %.0f, %.0f, %.0f -- spawning %d"):format(centre.X, centre.Y, centre.Z, ISLAND_BIRDS))

		for i = 1, ISLAND_BIRDS do
			task.spawn(function()
				local pal = BIRD_PALETTES[i] or BIRD_PALETTES[1]
				local bird = buildBird(pal)
				-- NOT "IslandBird_*": these sit at the top of Workspace next to Island_1_BeanFarm etc, and
				-- NpcGuideArrow picks the island you're on by matching top-level models named "island..." --
				-- so a bird called IslandBird_Goldfinch WAS an island as far as the tutorial arrows were
				-- concerned. That matcher now demands a digit after "island", but the name is fixed here too:
				-- a model should not be one character away from impersonating the thing it's flying over.
				bird.model.Name = "SkyBird_" .. pal.name
				-- This bird's own patch of sky: its sector of the island, its own radius + height band, its
				-- own drift direction. Nothing here is shared with the other three.
				local home   = ((i - 1) / ISLAND_BIRDS) * math.pi * 2  -- centre of its sector
				local dir    = (i % 2 == 0) and 1 or -1
				local radius = rng:NextNumber(R_MIN, R_MAX)
				local height = rng:NextNumber(H_MIN, H_MAX)
				local offset = rng:NextNumber(-SECTOR_HALF, SECTOR_HALF) -- where it is within its sector

				-- Wander to a new angle INSIDE the sector: step, then bounce off the sector edge rather than
				-- clamping to it (a clamped bird sits on the boundary and looks stuck).
				local function nextAngle()
					offset = offset + dir * rng:NextNumber(STEP_MIN, STEP_MAX)
					if offset > SECTOR_HALF or offset < -SECTOR_HALF then
						dir = -dir
						offset = math.clamp(offset, -SECTOR_HALF, SECTOR_HALF)
					end
					return home + offset
				end

				local function airWaypoint()
					-- Drift the radius/height a little each leg rather than re-rolling them: the bird wanders,
					-- it doesn't teleport between two different orbits.
					radius = math.clamp(radius + rng:NextNumber(-16, 16), R_MIN, R_MAX)
					height = math.clamp(height + rng:NextNumber(-8, 8), H_MIN, H_MAX)
					local angle = nextAngle()
					local pos = centre + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
					local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * dir
					return CFrame.lookAt(pos, pos + tangent)
				end

				-- A PERCH ANYWHERE ON THE ISLAND, found by RAYCASTING DOWN from a point in the bird's sector.
				-- The garden bird works off a hand-gathered list of named garden objects (pillar caps, lamp
				-- posts, planters); out on the island there is no such list -- it's houses, rocks, fences,
				-- trees and hillside, all differently named. A downward ray lands the bird on whatever is
				-- actually there, at its real top surface, and needs no maintenance when the island changes.
				-- Bird parts are CanQuery=false already, so the ray can't hit another bird; players are
				-- filtered so it never perches on somebody's head.
				local function perchTarget()
					local angle = nextAngle()
					local r = rng:NextNumber(R_MIN, R_MAX)
					local x, z = centre.X + math.cos(angle) * r, centre.Z + math.sin(angle) * r
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					local ignore = {}
					for _, p in ipairs(Players:GetPlayers()) do
						if p.Character then ignore[#ignore + 1] = p.Character end
					end
					params.FilterDescendantsInstances = ignore
					local from = Vector3.new(x, centre.Y + 160, z)
					local hit = Workspace:Raycast(from, Vector3.new(0, -400, 0), params)
					if not hit then return nil end
					-- Nothing to stand on down there (it fired off the edge into open sky/void).
					if hit.Position.Y < centre.Y - 40 then return nil end
					local landPos = hit.Position + Vector3.new(0, FOOT_DROP, 0)
					local toC = Vector3.new(centre.X - landPos.X, 0, centre.Z - landPos.Z) -- face back inland
					if toC.Magnitude < 1 then toC = Vector3.new(0, 0, -1) end
					return CFrame.lookAt(landPos, landPos + toC.Unit)
				end

				-- Start already in the air on its own circuit (no takeoff from nowhere).
				local cf = airWaypoint()
				applyBird(bird, cf, { wing = FLAP_CENTER })
				print(("[ISLAND BIRDS] %s airborne -- sector %d deg, radius %.0f, height %.0f"):format(
					pal.name, math.floor(math.deg(home) + 0.5), radius, height))

				-- SPOOKED: break off and climb AWAY from whoever walked up. Not just "resume the patrol" --
				-- a startled bird puts distance and height between itself and the thing that startled it, so
				-- the escape waypoint is picked on the far side of the bird from the player and higher than
				-- it was sitting. It re-joins its normal sector wander from wherever it ends up.
				local function escapeFrom(threat)
					local here = bird.cf.Position
					local away = here - threat
					away = Vector3.new(away.X, 0, away.Z)
					if away.Magnitude < 0.5 then away = Vector3.new(1, 0, 0) end
					away = away.Unit
					height = math.clamp(height + 14, H_MIN, H_MAX)
					local pos = here + away * rng:NextNumber(28, 46) + Vector3.new(0, 16, 0)
					pos = Vector3.new(pos.X, math.max(pos.Y, centre.Y + H_MIN), pos.Z)
					return CFrame.lookAt(pos, pos + away)
				end

				local perchLogged = false
				while bird.model.Parent do
					-- Come down and sit on whatever is below -- but only if the flock can spare one. Otherwise
					-- stay up and fly the next leg.
					local mayLand = (rng:NextNumber() < LAND_CHANCE) and (grounded < MAX_GROUNDED)
					local landCF  = mayLand and perchTarget() or nil
					if landCF then
						grounded = grounded + 1                 -- claimed for the whole descent + perch + takeoff
						flyTo(bird, bird.cf, landCF)            -- WITH the landing flare: it's actually landing
						local why, threat
						if bird.model.Parent then
							if not perchLogged then
								perchLogged = true
								print(("[ISLAND BIRDS] %s perched at %.0f, %.0f, %.0f (raycast landing works)"):format(
									pal.name, landCF.X, landCF.Y, landCF.Z))
							end
							why, threat = perchIdle(bird, landCF, rng:NextNumber(PERCH_STAY_MIN, PERCH_STAY_MAX), FLUSH_DIST)
						end
						grounded = grounded - 1                 -- released here, on EVERY path, so a bird that
						                                        -- dies mid-perch can't leave the flock stuck up
						if not bird.model.Parent then break end
						if why == "flushed" and threat then
							print(("[ISLAND BIRDS] %s flushed -- player within %d studs, taking off"):format(pal.name, FLUSH_DIST))
							flyTo(bird, bird.cf, escapeFrom(threat), true) -- straight up and away, no landing
						end
					else
						flyTo(bird, bird.cf, airWaypoint(), true) -- true = noLand: straight into the next leg
					end
				end
			end)
		end
	end)
end
