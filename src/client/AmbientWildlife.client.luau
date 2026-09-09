-- ============================================================================================================
-- AMBIENT WILDLIFE  (client)
--
-- Butterflies and bees over the Community Garden, and birds circling Bean Farm. The garden is beautiful and
-- completely dead -- nothing in it moves except the gardener and his one songbird. A still scene reads as a
-- diorama; a scene with things drifting through it reads as a place.
--
-- ===== WHY CLIENT-SIDE =====
-- GardenBird runs on the server, which is right for it: it is ONE bird, it perches on a specific NPC, and every
-- player should see it in the same spot. This is the opposite case. Twenty small critters on the server would
-- replicate twenty CFrames per frame to every player, forever, and nobody would be able to tell whether your
-- butterfly and mine were in the same place -- because nobody is watching a butterfly that closely. So each client
-- grows its own. Zero replication, zero server cost.
--
-- Nothing here collides, is queryable, casts shadows, or can be touched. It is scenery that happens to move.
-- ============================================================================================================

local Players      = game:GetService("Players")
local Workspace    = game:GetService("Workspace")
local RunService   = game:GetService("RunService")
local SoundService = game:GetService("SoundService") -- birdsong reads the music's live loudness to balance against it

-- ROUGHLY DOUBLED (was 10 / 7 / 4). The garden is the one place a player stands still in, so it is the
-- one place the density actually gets looked at, and a handful of bugs over a 42-stud circle reads as a
-- few strays rather than as a garden full of life. Everything here is culled past DRAW_DIST and frozen
-- while you are elsewhere, so the cost of more of them is only paid while you are stood among them.
local BUTTERFLIES = 20
local BEES        = 16
local BIRDS       = 7
-- Bugs scattered over the REST of the island, outside the garden. Kept deliberately thin -- the point is that
-- the island is alive, not that it has an insect problem -- and each one owns its own small patch, so you meet
-- a few at a time as you walk rather than all of them at once.
-- ROUGHLY DOUBLED (was 13 / 15 / 12). These are spread over a 190-stud radius, so the old numbers put one
-- bug every ~85 studs of open ground -- far enough apart that you could cross Bean Farm and meet nothing.
-- Each still owns its own patch and wakes independently, so this is more encounters as you walk, not a
-- bigger swarm in any one place.
local ISLAND_BUTTERFLIES = 26
local ISLAND_BEES        = 30
local ISLAND_FLIES       = 24
local ISLAND_BUG_R       = 190  -- studs from the island centre they are scattered within

local GARDEN_R    = 42   -- studs: how far from the garden centre they wander
local FLY_LOW     = 3    -- height band above the garden floor they stay within
local FLY_HIGH    = 11
local BIRD_R      = 150  -- radius the birds circle the island at
local BIRD_H      = 60   -- how high above the island they circle
local DRAW_DIST   = 260  -- beyond this from the player, freeze everything. A butterfly you cannot see does not
                         -- need to be animated, and this is what keeps 21 critters free rather than merely cheap.

-- ===== BUGS GET OUT OF YOUR WAY =====
-- Walking straight through a bee is the moment the garden stops being a place and becomes scenery. So
-- every bug carries a DODGE OFFSET: get close and it slides away from you, and it eases back to its
-- drift once you have passed. Added on top of the orbit rather than replacing it, so a bug that is
-- avoiding you is still doing its own wander -- it is being pushed, not teleported to a safe spot.
--
-- EASED, NOT SNAPPED. The offset lerps toward its target every frame, which is the whole difference
-- between a bug flitting out of reach and one that jumps. It is also why the push can be generous:
-- nothing moves fast enough to look like it teleported.
--
-- The radius is deliberately bigger than arm's reach. A bee that waits until you are touching it has
-- already failed -- real ones leave before you arrive, and the near miss is the bit that reads.
local SHY_RADIUS = 7.0   -- studs: start sliding away inside this
local SHY_PUSH   = 6.0   -- studs: how far it is shoved at closest approach
local SHY_RISE   = 0.45  -- of the push, added upward -- bugs break UP and away, never sideways only
local SHY_EASE   = 0.14  -- per frame toward the target offset; lower = lazier drift back

local player = Players.LocalPlayer
local rng = Random.new()

local folder = Instance.new("Folder")
folder.Name = "AmbientWildlife"
folder.Parent = Workspace

local function part(parent, name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p:SetAttribute("BaseT", 0) -- what the cull restores to; callers that want a see-through part re-stamp it
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A butterfly: two wings hinged either side of a body. The WINGS are what sell it -- a butterfly that glides with
-- fixed wings reads as a leaf, so the flap is the whole illusion and it has to be big and irregular.
local function buildButterfly(col1, col2, s)
	s = s or 1
	local m = Instance.new("Model"); m.Name = "Butterfly"; m.Parent = folder
	local body = part(m, "Body", Vector3.new(0.12, 0.12, 0.42) * s, Color3.fromRGB(40, 32, 28))
	m.PrimaryPart = body
	local wingL = part(m, "WingL", Vector3.new(0.06, 0.5, 0.62) * s, col1)
	local wingR = part(m, "WingR", Vector3.new(0.06, 0.5, 0.62) * s, col2)
	wingL.Transparency = 0.1; wingR.Transparency = 0.1
	wingL:SetAttribute("BaseT", 0.1); wingR:SetAttribute("BaseT", 0.1)
	return { model = m, body = body, wingL = wingL, wingR = wingR }
end

local function buildBee(s)
	s = s or 1
	local m = Instance.new("Model"); m.Name = "Bee"; m.Parent = folder
	local body = part(m, "Body", Vector3.new(0.22, 0.22, 0.34) * s, Color3.fromRGB(240, 200, 40))
	m.PrimaryPart = body
	part(m, "Stripe", Vector3.new(0.24, 0.24, 0.10) * s, Color3.fromRGB(30, 26, 20)).CFrame = body.CFrame
	local wingL = part(m, "WingL", Vector3.new(0.03, 0.16, 0.30) * s, Color3.fromRGB(230, 245, 255))
	local wingR = part(m, "WingR", Vector3.new(0.03, 0.16, 0.30) * s, Color3.fromRGB(230, 245, 255))
	wingL.Transparency = 0.55; wingR.Transparency = 0.55
	wingL:SetAttribute("BaseT", 0.55); wingR:SetAttribute("BaseT", 0.55)
	return { model = m, body = body, wingL = wingL, wingR = wingR, stripe = m.Stripe }
end

-- A gnat/fly: the small dark bugs that hang in the air over grass in the late afternoon. No colour, no detail --
-- at any distance this is a speck, and a speck that jitters is a bug while a speck that glides is a dust mote.
local function buildFly(s)
	s = s or 1
	local m = Instance.new("Model"); m.Name = "Fly"; m.Parent = folder
	local body = part(m, "Body", Vector3.new(0.13, 0.12, 0.20) * s, Color3.fromRGB(34, 30, 28))
	m.PrimaryPart = body
	local wingL = part(m, "WingL", Vector3.new(0.02, 0.10, 0.18) * s, Color3.fromRGB(225, 235, 245))
	local wingR = part(m, "WingR", Vector3.new(0.02, 0.10, 0.18) * s, Color3.fromRGB(225, 235, 245))
	wingL.Transparency = 0.7; wingR.Transparency = 0.7
	wingL:SetAttribute("BaseT", 0.7); wingR:SetAttribute("BaseT", 0.7)
	return { model = m, body = body, wingL = wingL, wingR = wingR }
end

-- ============================================================================================================
-- A distant soaring bird. It is circling 150 studs out and 60-odd up, so nothing here is about detail -- at that
-- range the whole animal is a few pixels and only the SILHOUETTE and the MOTION survive. Everything below serves
-- one of those two, and nothing else is worth a part.
--
-- SILHOUETTE
--   * The body is a SPHERE MESH ON A BLOCK, not a Ball part. A Ball part always renders as a sphere of the
--     SMALLEST size axis, so the old (0.5, 0.4, 1.3) body drew as a 0.4 marble and the length -- the entire
--     point of the number -- was thrown away. A Sphere SpecialMesh scales on all three axes, so the body is the
--     stretched teardrop it was always meant to be.
--   * The wings run SPANWISE, long on X. They used to be 2.2 studs long on Z, along the flight direction: that
--     is an enormous chord on a 1.8 span, which is the plan view of a manta ray, not a bird.
--   * Each wing is TWO segments with a hinge at the WRIST, and the outer one is narrower and darker the way
--     primaries are. A real wing bends there, and that bend is most of what separates a bird from a flapping
--     ironing board.
--   * Head in front, tail behind: the outline is a cross with a wedge behind it and a bump in front, and that
--     front-to-back asymmetry is the only thing telling you which way it is going.
--
-- Colour is deliberately drab and varies by VALUE rather than hue -- against bright sky a bird is a dark shape,
-- and four birds in four different greys read as four birds where four identical ones read as one on a loop.
local BIRD_PALETTES = {
	{ body = Color3.fromRGB( 52,  48,  58), head = Color3.fromRGB( 44,  40,  50), tail = Color3.fromRGB( 58,  54,  66), wing = Color3.fromRGB( 64,  60,  72), tip = Color3.fromRGB( 36,  33,  42) },
	{ body = Color3.fromRGB( 88,  76,  62), head = Color3.fromRGB( 74,  64,  52), tail = Color3.fromRGB( 98,  86,  70), wing = Color3.fromRGB(106,  92,  76), tip = Color3.fromRGB( 58,  50,  42) }, -- brown hawk
	{ body = Color3.fromRGB(198, 200, 206), head = Color3.fromRGB(214, 216, 220), tail = Color3.fromRGB(180, 184, 192), wing = Color3.fromRGB(188, 192, 200), tip = Color3.fromRGB( 58,  58,  64) }, -- gull: pale, black tips
	{ body = Color3.fromRGB( 38,  36,  42), head = Color3.fromRGB( 34,  32,  38), tail = Color3.fromRGB( 44,  42,  48), wing = Color3.fromRGB( 48,  46,  54), tip = Color3.fromRGB( 28,  26,  32) },
}

local function ellipsoid(p)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere -- scales on all three axes, unlike PartType.Ball
	mesh.Parent = p
	return p
end

local function buildBird(pal, scale)
	local s = scale
	local m = Instance.new("Model"); m.Name = "SkyBird"; m.Parent = folder
	local body = ellipsoid(part(m, "Body", Vector3.new(0.46, 0.40, 1.30) * s, pal.body))
	m.PrimaryPart = body
	local head = ellipsoid(part(m, "Head", Vector3.new(0.30, 0.28, 0.42) * s, pal.head))
	-- Tail: wider than the body and thin, so it reads as a fan from below -- the angle these are almost always
	-- seen from.
	-- A BEAK. The file above says the front-to-back asymmetry is the only thing telling you which way the
	-- bird is going, and an ellipsoid head has none -- it is the same shape from either end. A wedge two
	-- tenths of a stud long fixes that, and at range it is the difference between a bird and a dart.
	local beak = part(m, "Beak", Vector3.new(0.09, 0.08, 0.22) * s, pal.tip)
	-- WINGS AND TAIL ARE ELLIPSOIDS, not slabs. A rectangular wing has four hard corners, and corners are
	-- what the eye uses to decide something is a plank -- a real wing tapers to nothing at the tip. Same
	-- part count, same numbers, just a rounded outline.
	local tail  = ellipsoid(part(m, "Tail",  Vector3.new(0.82, 0.08, 1.10) * s, pal.tail))
	local wingL = ellipsoid(part(m, "WingL", Vector3.new(1.38, 0.09, 0.82) * s, pal.wing))
	local wingR = ellipsoid(part(m, "WingR", Vector3.new(1.38, 0.09, 0.82) * s, pal.wing))
	local tipL  = ellipsoid(part(m, "TipL",  Vector3.new(1.25, 0.08, 0.56) * s, pal.tip))
	local tipR  = ellipsoid(part(m, "TipR",  Vector3.new(1.25, 0.08, 0.56) * s, pal.tip))
	return { model = m, body = body, head = head, beak = beak, tail = tail,
	         wingL = wingL, wingR = wingR, tipL = tipL, tipR = tipR, scale = s }
end

-- ===== FIND THE GARDEN + THE ISLAND (both build asynchronously, long after this script starts) =====
local gardenPos, islandPos, islandModel
-- Where the scattered bugs actually live: real props on the island, collected once the model resolves.
-- propsReady flips true when the sweep has run, so a bug that got no prop knows to fall back rather than
-- waiting forever for a list that is already finished.
local propAnchors, propsReady = {}, false
task.spawn(function()
	for _ = 1, 240 do
		if not gardenPos then
			local build = Workspace:FindFirstChild("CommunityGardenBuild", true)
			if build then
				local ok, cf = pcall(function() return build:GetPivot() end)
				if ok then gardenPos = cf.Position end
			end
		end
		if not islandPos then
			-- NAME MATCHING IS NORMALISED. This used to demand "^Island_1_", and the models in this place are
			-- actually named `island1` .. `island14` -- so it matched NOTHING, islandPos stayed nil forever,
			-- and every bird sat frozen at the origin with its centre never resolving. (GardenBird hit the
			-- identical trap and fixed it the same way; GardenerWave and IslandNPCs use this finder too.)
			-- Lowercasing and stripping separators catches both spellings, and the digit guard stops "island1"
			-- from also matching island10..14.
			for _, m in ipairs(Workspace:GetChildren()) do
				if m:IsA("Model") then
					local nm = (m.Name:lower():gsub("[%s_%-%.]", ""))
					if nm:sub(1, 7) == "island1" and not tonumber(nm:sub(8, 8)) then
						local ok, cf = pcall(function() return m:GetPivot() end)
						if ok then islandPos = cf.Position; islandModel = m end
						break
					end
				end
			end
		end
		if gardenPos and islandPos then break end
		task.wait(0.5)
	end
	-- ===== FIND THE PROPS THE BUGS WILL LIVE ON =====
	-- The first version scattered them evenly across a 190-stud disc. That is one bug every ~85 studs of
	-- empty field at a body size of a fifth of a stud: they existed, they animated, and there was no angle
	-- from which a player could ever see one. Bugs belong ON THINGS -- so this collects the island's actual
	-- props (fences, crates, planters, huts, rocks, signs) and parks a bug over each. Everything you walk
	-- past now has something drifting around it, which is exactly where the player is already looking.
	--
	-- THE SIZE FILTER IS THE WHOLE TRICK. Too small and it hooks bolts and pebbles; too big and it hooks the
	-- island floor itself and hangs a butterfly 40 studs over the sea. Between 1.6 and 45 studs is "a thing
	-- you would walk up to", and the height window keeps it to ground level rather than the blimp.
	if islandModel and gardenPos then
		local baseY = gardenPos.Y
		for _, p in ipairs(islandModel:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 0.5 then
				local sz = p.Size
				if sz.X < 45 and sz.Z < 45 and math.max(sz.X, sz.Y, sz.Z) > 1.6 then
					local dx, dz = p.Position.X - islandPos.X, p.Position.Z - islandPos.Z
					if dx * dx + dz * dz < ISLAND_BUG_R * ISLAND_BUG_R
						and p.Position.Y > baseY - 6 and p.Position.Y < baseY + 45 then
						propAnchors[#propAnchors + 1] = p.Position + Vector3.new(0, sz.Y * 0.5 + 1.2, 0)
					end
				end
			end
		end
		-- Shuffle, or every bug ends up on whichever corner of the island happened to be built first.
		for i = #propAnchors, 2, -1 do
			local j = rng:NextInteger(1, i)
			propAnchors[i], propAnchors[j] = propAnchors[j], propAnchors[i]
		end
	end
	propsReady = true
	print(("[Wildlife] garden=%s island=%s -- %d prop(s) for the bugs to hang around")
		:format(tostring(gardenPos ~= nil), tostring(islandPos ~= nil), #propAnchors))
end)


-- ============================================================================================================
-- TWO PROPS THAT EXPLAIN THINGS THAT WERE ALREADY HAPPENING
--
-- CLIENT-SIDE, like everything else in this file, and for the same reason: neither can be touched, collided
-- with, or interacted with, so there is nothing for the server to be authoritative about. A hive that only
-- your client knows about is fine right up until somebody wants to click it -- if that day comes, these move
-- to CommunityGarden and the bee anchoring below reads the server's copy instead. Nothing else changes.
-- ============================================================================================================

-- Drop a point onto the ground under it. The garden floor is not flat everywhere and the island streams, so
-- guessing a Y is how a prop ends up buried or hovering. Returns nil if there is nothing under it at all.
local function groundAt(x, z, fromY)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { folder }   -- never land a prop on another prop we just built
	local hit = Workspace:Raycast(Vector3.new(x, fromY + 25, z), Vector3.new(0, -80, 0), rp)
	return hit and hit.Position.Y or nil
end

-- ===== THE BEEHIVE =====
-- There are bees over this garden and nothing they came from. A hive is one prop that answers that, and it
-- costs nothing else: the bees below simply orbit it instead of orbiting a coordinate, which is also a better
-- flight pattern -- an insect circles a THING.
--
-- Built as the classic stacked-box hive because the silhouette has to survive being seen from 40 studs away
-- across a garden: three tapering boxes and a lid is legible at that range where a detailed skep is a blob.
local hivePos
task.spawn(function()
	while not gardenPos do task.wait(0.5) end
	-- Off the path, on the garden's edge, where a real one would be: close enough to belong to the garden,
	-- far enough not to be something you walk into on the way to the water spot.
	local hx = gardenPos.X + 26
	local hz = gardenPos.Z - 22
	local gy = groundAt(hx, hz, gardenPos.Y) or gardenPos.Y
	local m = Instance.new("Model"); m.Name = "Beehive"; m.Parent = folder

	-- A short stand, so the hive is not sitting in the wet grass -- which is both what beekeepers do and
	-- what stops the bottom box reading as half-buried on uneven ground.
	local legY = gy + 0.35
	for _, dx in ipairs({ -0.55, 0.55 }) do
		for _, dz in ipairs({ -0.45, 0.45 }) do
			part(m, "Leg", Vector3.new(0.18, 0.7, 0.18), Color3.fromRGB(96, 74, 48), Enum.Material.Wood)
				.CFrame = CFrame.new(hx + dx, legY, hz + dz)
		end
	end

	-- Three supers, each a touch narrower than the one below: the taper is what says "stack of boxes" rather
	-- than "crate". Alternating tone so the joints between them are visible at distance.
	local y = gy + 0.7
	for i, w in ipairs({ 1.55, 1.42, 1.30 }) do
		local box = part(m, "Super", Vector3.new(w, 0.62, w * 0.82),
			(i % 2 == 1) and Color3.fromRGB(226, 214, 186) or Color3.fromRGB(206, 192, 162),
			Enum.Material.WoodPlanks)
		box.CFrame = CFrame.new(hx, y + 0.31, hz)
		y = y + 0.62
	end
	-- Lid: overhangs on every side, which is the one detail that reads as a roof rather than a fourth box.
	part(m, "Lid", Vector3.new(1.7, 0.16, 1.42), Color3.fromRGB(122, 96, 62), Enum.Material.Wood)
		.CFrame = CFrame.new(hx, y + 0.08, hz)
	-- The entrance slot, dark, at the front of the bottom super. Tiny, but it is where the bees go.
	part(m, "Entrance", Vector3.new(0.9, 0.09, 0.06), Color3.fromRGB(38, 30, 22))
		.CFrame = CFrame.new(hx, gy + 0.82, hz + 0.64)

	m.PrimaryPart = m:FindFirstChild("Lid")
	hivePos = Vector3.new(hx, gy + 1.1, hz)   -- bees orbit the body of the stack, not the lid
	print(("[Wildlife] beehive built at (%.0f, %.0f, %.0f) -- the garden bees now have somewhere to be from")
		:format(hx, gy, hz))
end)

-- ===== THE WEATHERVANE =====
-- The game already HAS wind: a windstorm sets _G.windstormDir and a thunderstorm sets _G.thunderWindVec, and
-- both push the player around mid-flight. Nothing on the ground has ever shown it. A vane that genuinely
-- points where the wind is going -- and spins when it is strong -- turns the weather from something happening
-- to your character into something happening to the island.
--
-- It reads the same globals the flight code does, so it cannot disagree with the wind you are actually
-- fighting. With no storm running it drifts on a slow idle breeze instead of freezing, because a vane locked
-- dead still is the one thing that looks broken.
task.spawn(function()
	while not gardenPos do task.wait(0.5) end
	local vx = gardenPos.X - 30
	local vz = gardenPos.Z + 18
	local gy = groundAt(vx, vz, gardenPos.Y) or gardenPos.Y
	local m = Instance.new("Model"); m.Name = "Weathervane"; m.Parent = folder

	part(m, "Post", Vector3.new(0.22, 6.0, 0.22), Color3.fromRGB(88, 68, 44), Enum.Material.Wood)
		.CFrame = CFrame.new(vx, gy + 3.0, vz)
	-- The fixed N/S/E/W cross. It does NOT turn -- that is the whole point of it: the arrow moves against
	-- something that does not, or there is no way to read which way it is pointing.
	for _, ax in ipairs({ Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) }) do
		part(m, "Cross", Vector3.new(0.09, 0.09, 0.09) + ax * 1.5, Color3.fromRGB(64, 60, 56), Enum.Material.Metal)
			.CFrame = CFrame.new(vx, gy + 5.4, vz)
	end

	-- The arrow: a head, a tail fin and a shaft, all posed as one unit every frame. The fin has to be BIGGER
	-- than the head -- that is what makes a vane point into the wind rather than look like a double-ended
	-- stick, and it is the only cue for direction at any distance.
	local shaft = part(m, "Shaft", Vector3.new(0.07, 0.07, 1.9), Color3.fromRGB(52, 48, 44), Enum.Material.Metal)
	local head  = part(m, "Head",  Vector3.new(0.22, 0.22, 0.42), Color3.fromRGB(184, 148, 60), Enum.Material.Metal)
	local fin   = part(m, "Fin",   Vector3.new(0.05, 0.62, 0.72), Color3.fromRGB(184, 148, 60), Enum.Material.Metal)
	m.PrimaryPart = shaft

	local pivot = Vector3.new(vx, gy + 5.85, vz)
	local heading = 0        -- radians, eased toward the wind so the vane swings rather than snaps
	local spin = 0           -- extra rotation while the wind is strong: a vane in a gale whips round
	RunService.Heartbeat:Connect(function(dt)
		if not shaft.Parent then return end
		-- CULLED WITH EVERYTHING ELSE. A vane nobody is near does not need to be turned.
		local ch = player.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp and (pivot - hrp.Position).Magnitude > DRAW_DIST then return end

		-- THE SAME WIND THE FLIGHT CODE USES. Thunderstorm wind is a full vector; the windstorm publishes a
		-- unit direction. Either can be absent, and absent means calm, not zero-length maths.
		local w = _G.thunderWindVec
		if typeof(w) ~= "Vector3" or w.Magnitude < 0.05 then
			local d = _G.windstormDir
			w = (typeof(d) == "Vector3" and d.Magnitude > 0.05) and (d * 40) or nil
		end

		local target, strength
		if w then
			target = math.atan2(w.X, w.Z)
			strength = math.clamp(w.Magnitude / 90, 0, 1)   -- 90 is STORM_WIND_FORCE, the game's own hard gust
		else
			-- Calm: a slow wandering breeze. Two mismatched sines so the drift never visibly repeats.
			target = math.sin(os.clock() * 0.07) * 2.4 + math.sin(os.clock() * 0.031) * 1.1
			strength = 0
		end

		-- Shortest way round, or the vane takes the long way for any swing past 180 degrees and spins
		-- backwards through three quarters of a circle to get somewhere it was next to.
		local diff = (target - heading + math.pi) % (math.pi * 2) - math.pi
		heading = heading + diff * math.clamp(dt * (1.5 + strength * 6), 0, 1)
		-- Above about half strength it stops pointing and starts whipping, which is what a real one does.
		spin = spin + dt * math.max(0, strength - 0.5) * 26

		local cf = CFrame.new(pivot) * CFrame.Angles(0, heading + spin, 0)
		shaft.CFrame = cf
		head.CFrame  = cf * CFrame.new(0, 0, -1.05)
		fin.CFrame   = cf * CFrame.new(0, 0.16, 0.95)
	end)
	print(("[Wildlife] weathervane built at (%.0f, %.0f, %.0f) -- reads the live storm wind")
		:format(vx, gy, vz))
end)

-- ============================================================================================================
-- ISLAND BIRDSONG: a looping ambience heard ANYWHERE on Bean Farm, fading out only once you leave it.
-- ============================================================================================================
-- It started life as a garden-only sound (full inside the garden, silent 240 studs out). It now covers the
-- whole island at one steady level, because that is what birds on an island actually sound like -- you don't
-- walk out of the birdsong when you leave the flowerbeds, and the six birds circling overhead are everywhere.
--
-- STILL POSITIONAL, not a proximity check. The Sound lives on an invisible part parked over the island's
-- centre, so Roblox itself does the distance falloff every frame on the audio thread: flat at MIN_DIST (a
-- radius big enough to swallow the island whole), then fading to nothing by MAX_DIST as you fly away or
-- climb. No Heartbeat work, no "am I close enough" polling, and no hard cut at a boundary line -- which is
-- what a scripted enter/leave check always ends up sounding like.
--
-- CENTRED ON THE ISLAND, NOT THE GARDEN: the garden sits off to one side, so a falloff centred there is
-- lopsided -- quieter on the far side of the island than the near. X/Z come from the island, but Y comes
-- from the GARDEN, because the island model's pivot is ~90 studs below the surface you stand on (the same
-- trap the island birds fell into) and a sound buried under the island is 90 studs of distance away for free.
--
-- CLIENT-SIDE for the same reason the critters are: it's ambience, every player hears their own, and a server
-- Sound would have to fight StreamingEnabled to exist for a player who is nowhere near the island yet.
--
-- It deliberately has NO SoundGroup: SettingsMenu's SFX toggle adopts every ungrouped Sound under Workspace,
-- so this obeys the Sound Effects switch like everything else.
do
	local BIRD_SOUND = "rbxassetid://5026653246"   -- (was 9119383479)
	local MIN_DIST   = 280  -- flat, full volume within this -- comfortably the whole island
	local MAX_DIST   = 700  -- gone by here: leaving the island or flying up out of it fades it away
	local VOLUME     = 0.585 -- the level it holds anywhere on the island (0.45 x 1.3)

	task.spawn(function()
		while not gardenPos do task.wait(0.5) end -- the garden builds long after this script starts

		-- Island X/Z + garden Y (see the note above). islandPos may still be nil if the model never resolved;
		-- the garden is on the island either way, so it's a safe fallback.
		local function emitterPos()
			local ground = gardenPos + Vector3.new(0, 6, 0)
			if islandPos then return Vector3.new(islandPos.X, ground.Y, islandPos.Z) end
			return ground
		end

		local emitter, song
		local function build()
			if folder.Parent == nil then folder.Parent = Workspace end -- our whole folder can go with a sweep too
			emitter = part(folder, "IslandBirdsong", Vector3.new(1, 1, 1), Color3.new(1, 1, 1))
			emitter.Transparency = 1
			emitter.Position = emitterPos()
			song = Instance.new("Sound")
			song.Name = "IslandBirdsongLoop"
			song.SoundId = BIRD_SOUND
			song.Looped = true            -- on repeat, forever
			song.Volume = VOLUME
			song.RollOffMode = Enum.RollOffMode.InverseTapered -- smooth swell rather than a linear ramp
			song.RollOffMinDistance = MIN_DIST
			song.RollOffMaxDistance = MAX_DIST
			song.Parent = emitter
			song:Play()
		end
		build()
		print(("[Wildlife] island birdsong looping at vol %.2f (flat within %d studs, silent past %d)")
			:format(VOLUME, MIN_DIST, MAX_DIST))

	-- ===== BIRDS GO QUIET IN BAD WEATHER =========================================================
	-- A thunderstorm rolls in, or the sky turns red and meteors start hitting the island, and the birds
	-- carried right on chirping underneath it. It undercut the two loudest moments in the game -- the storm
	-- is supposed to feel like the island is in trouble, and cheerful birdsong says it plainly is not.
	-- Real birds shut up before a storm, so this is what a player already expects to hear.
	--
	-- It rides the SAME eased volume the music-balancing loop below drives (target 0 instead of a level),
	-- so the birds fade out over about a second rather than being cut off mid-chirp, and fade back in the
	-- same way when the weather clears. The Sound keeps playing throughout at volume 0 -- pausing and
	-- resuming a looped positional sound restarts it from an arbitrary point and pops.
	--
	-- TWO SOURCES, because the two events are announced on different channels:
	--   * METEOR SHOWER -- the MeteorSync remote, silent from its first phase until "reset" (the full
	--     sky/cleanup restore at the very end). LateJoinEventSync replays these to a late joiner, so
	--     someone who walks in mid-shower gets the quiet too.
	--   * THUNDERSTORM -- ServerEventNotify, the medium-event channel, cleared by "END". This is the same
	--     pair MusicDucking listens to; SILENCING_EVENTS is a table so adding WINDSTORM or FART_STORM here
	--     later is one word, not a rewrite.
	-- Both are tracked separately and the birds stay quiet while EITHER is up, so an overlapping storm and
	-- shower cannot end each other's silence early.
	local SILENCING_EVENTS = { THUNDERSTORM = true }
	local meteorQuiet, stormQuiet = false, false
	local function silenced() return meteorQuiet or stormQuiet end

	task.spawn(function()
		local RS = game:GetService("ReplicatedStorage")
		local sync = RS:WaitForChild("MeteorSync", 60)
		if sync then
			sync.OnClientEvent:Connect(function(phase)
				if phase == "reset" then
					if meteorQuiet then print("[Wildlife] meteor shower over -- birdsong fading back in") end
					meteorQuiet = false
				elseif not meteorQuiet then
					meteorQuiet = true
					print("[Wildlife] meteor shower ('" .. tostring(phase) .. "') -- birdsong silenced")
					-- SAFETY: if the storm errors out before "reset" ever fires, the island would be left
					-- permanently birdless with nothing to undo it. A shower is a couple of minutes; five
					-- is comfortably past any legitimate one.
					task.delay(300, function() meteorQuiet = false end)
				end
			end)
		end
		local notify = RS:WaitForChild("ServerEventNotify", 60)
		if notify then
			notify.OnClientEvent:Connect(function(eventName)
				if eventName == "END" then
					if stormQuiet then print("[Wildlife] storm over -- birdsong fading back in") end
					stormQuiet = false
				elseif SILENCING_EVENTS[eventName] then
					stormQuiet = true
					print("[Wildlife] " .. tostring(eventName) .. " -- birdsong silenced")
					task.delay(300, function() stormQuiet = false end)
				end
			end)
		end
	end)

		-- ===== RIDE THE MUSIC =====================================================================
		-- The four background tracks are not mastered to the same level -- some are noticeably louder than
		-- others -- so ONE fixed birdsong volume is either buried under the loud tracks or sitting on top of
		-- the quiet ones. This measures how loud the music ACTUALLY is right now and moves the birdsong with
		-- it, so it keeps the same relationship to the music whichever track is playing.
		--
		-- It reads Sound.PlaybackLoudness, not Sound.Volume. Every track plays at the same configured Volume
		-- (MusicClient sets each voice to gain 1 and never varies it) -- the difference is in the ASSETS
		-- themselves, which only a real-time loudness read can see. Loudness is per-frame jittery, so it's
		-- smoothed with a running average and the volume is eased toward the target rather than snapped, or
		-- the birdsong would pump on every drum hit.
		--
		-- MUSIC OFF is not "music at zero" -- when the player mutes music (or an event ducks it), the birds
		-- go back to their normal standalone volume rather than dropping to the quiet-track floor.
		task.spawn(function()
			local REF_LOUD = 120     -- a "normal" music loudness; at this the birds sit at exactly VOLUME
			local MIN_VOL, MAX_VOL = VOLUME * 0.62, VOLUME * 1.55
			local smoothLoud, applied = 0, VOLUME
			while true do
				task.wait(0.25)
				if song and song.Parent then
					-- Loudest currently-playing music voice. They live in the BackgroundMusic group, which is
					-- also what MusicDucking mutes -- so a muted group reads as silence and we fall back.
					local loud, groupVol = 0, 1
					for _, s in ipairs(SoundService:GetDescendants()) do
						if s:IsA("Sound") and s.IsPlaying and s.SoundGroup and s.SoundGroup.Name == "BackgroundMusic" then
							loud = math.max(loud, s.PlaybackLoudness)
							groupVol = s.SoundGroup.Volume
						end
					end
					smoothLoud = smoothLoud + (loud - smoothLoud) * 0.35
					local target
					if silenced() then
						target = 0                                       -- storm/meteor: the birds shut up
					elseif smoothLoud < 5 or groupVol <= 0.01 or _G.musicEnabled == false then
						target = VOLUME                                  -- no music to balance against
					else
						-- ^0.6 rather than a straight ratio: loudness differences between tracks should nudge
						-- the birds, not track them 1:1 (that would make a loud track shout the birds over it).
						target = math.clamp(VOLUME * (smoothLoud / REF_LOUD) ^ 0.6, MIN_VOL, MAX_VOL)
					end
					applied = applied + (target - applied) * 0.25         -- ease, never snap
					-- ...except the last hair of a fade-out. The ease is asymptotic, so a silenced bird would
					-- sit at a few thousandths of a volume forever; below audible, snap it to a true zero.
					if target == 0 and applied < 0.01 then applied = 0 end
					song.Volume = applied
				end
			end
		end)

		-- KEEP IT ALIVE. A garden stage-rebuild, a world reset or anything else sweeping Workspace can take our
		-- emitter with it, and a one-shot :Play() that got stopped leaves the garden silent for the rest of the
		-- session with nothing in the log to say so. Re-park it on the garden centre (the pivot settles as the
		-- build finishes), rebuild it if it's gone, and restart the loop if something stopped it.
		while true do
			task.wait(3)
			if not (emitter and emitter.Parent) then
				warn("[Wildlife] garden birdsong emitter was removed -- rebuilding it")
				build()
			else
				if gardenPos then emitter.Position = gardenPos + Vector3.new(0, 6, 0) end
				if song and not song.IsPlaying then song:Play() end
			end
		end
	end)
end

-- ===== SPAWN =====
-- Each critter gets its OWN random speed, radius, height and phase. Give them shared values and they move as a
-- flock of clones, which is instantly readable as fake -- the irregularity IS the realism.
local WING_COLORS = {
	{ Color3.fromRGB(255, 170, 60),  Color3.fromRGB(255, 140, 40)  }, -- monarch
	{ Color3.fromRGB(120, 190, 255), Color3.fromRGB(90, 160, 240)  }, -- blue
	{ Color3.fromRGB(255, 245, 250), Color3.fromRGB(240, 225, 240) }, -- white
	{ Color3.fromRGB(255, 210, 90),  Color3.fromRGB(250, 180, 70)  }, -- yellow
}

local critters = {}
for i = 1, BUTTERFLIES do
	local c = WING_COLORS[((i - 1) % #WING_COLORS) + 1]
	local b = buildButterfly(c[1], c[2])
	b.kind    = "butterfly"
	b.radius  = rng:NextNumber(8, GARDEN_R)
	b.speed   = rng:NextNumber(0.16, 0.34)        -- lazy
	b.height  = rng:NextNumber(FLY_LOW, FLY_HIGH)
	b.bobAmp  = rng:NextNumber(0.8, 2.2)          -- butterflies do not fly straight; they bob a lot
	b.bobFreq = rng:NextNumber(1.4, 2.6)
	b.flap    = rng:NextNumber(7, 11)
	b.phase   = rng:NextNumber(0, math.pi * 2)
	critters[#critters + 1] = b
end
for i = 1, BEES do
	local b = buildBee()
	b.kind    = "bee"
	-- HALF THE HIVE WORKS THE HIVE. These ones orbit the hive prop instead of the garden centre, tight and
	-- low, so there is always traffic around the box -- which is what makes it read as a live hive rather
	-- than a crate somebody left out. The flag is checked in the pose loop, because the hive is built a few
	-- seconds after this runs and a bee assigned to a nil position would sit at the origin until it existed.
	b.atHive  = (i % 2 == 0)
	b.radius  = b.atHive and rng:NextNumber(1.6, 5) or rng:NextNumber(5, 22) -- bees stay tighter to the flowers
	b.speed   = rng:NextNumber(0.5, 0.9)          -- and are much busier
	b.height  = b.atHive and rng:NextNumber(0.2, 1.6) or rng:NextNumber(2, 6)
	b.bobAmp  = rng:NextNumber(0.3, 0.8)
	b.bobFreq = rng:NextNumber(3, 5)
	b.flap    = rng:NextNumber(28, 40)            -- a blur, as it should be
	b.phase   = rng:NextNumber(0, math.pi * 2)
	critters[#critters + 1] = b
end
for i = 1, BIRDS do
	local pal = BIRD_PALETTES[((i - 1) % #BIRD_PALETTES) + 1]
	local b = buildBird(pal, rng:NextNumber(0.85, 1.35))  -- no two the same size: distance ambiguity for free
	b.kind       = "bird"
	b.dir        = (rng:NextNumber() < 0.5) and 1 or -1   -- half of them circle the other way round
	b.radius     = rng:NextNumber(BIRD_R * 0.6, BIRD_R)
	b.speed      = rng:NextNumber(0.10, 0.18)             -- slow, wide, unhurried circles
	b.height     = rng:NextNumber(BIRD_H * 0.7, BIRD_H * 1.4)
	b.bobAmp     = rng:NextNumber(4, 9)                   -- the long thermal swell it rides up and down
	b.bobFreq    = rng:NextNumber(0.05, 0.11)
	b.phase      = rng:NextNumber(0, math.pi * 2)
	b.driftA     = rng:NextNumber(14, 34)                 -- how far the circle ITSELF wanders
	b.driftF     = rng:NextNumber(0.012, 0.030)
	b.cycleLen   = rng:NextNumber(7, 16)                  -- one burst-of-flaps-then-glide
	b.flapFrac   = rng:NextNumber(0.16, 0.34)             -- ...of which only this fraction is flapping
	b.cyclePhase = rng:NextNumber(0, 20)
	b.pumpAmp    = rng:NextNumber(2.5, 6)                 -- height won on the burst, given back on the glide
	b.flapHz     = rng:NextNumber(2.1, 3.2)
	b.flapAmp    = math.rad(rng:NextNumber(34, 50))
	b.dihedral   = math.rad(rng:NextNumber(4, 9))         -- held in a shallow V while gliding
	b.sweep      = math.rad(rng:NextNumber(12, 22))       -- and angled back, not square out
	b.bank       = math.rad(rng:NextNumber(17, 29))
	b.swoopLen   = rng:NextNumber(26, 52)                 -- one peel-off-and-dive per this many seconds
	b.swoopFrac  = rng:NextNumber(0.12, 0.20)             -- ...of which this is the dive itself
	b.swoopPhase = rng:NextNumber(0, 50)                  -- never two of them stooping together
	b.swoopDepth = rng:NextNumber(18, 44)                 -- studs it drops and climbs back out of
	critters[#critters + 1] = b
end

-- ===== BUGS OVER THE REST OF THE ISLAND =====================================================================
-- The garden had the only insects on Bean Farm, so the moment you walked out of it the island went sterile.
-- These are the same bees and butterflies plus a few gnats, scattered THINLY over the whole island -- a few in
-- view at a time, not a swarm.
--
-- EACH ONE OWNS A PATCH; it does not orbit the island. A bug circling the island centre at 140 studs would fly
-- a lap through every house on it, and would be a bug on a racetrack. So each gets an anchor somewhere on the
-- island and wanders a few studs around THAT -- which is also what a bug does, and it makes the cull per-bug.
--
-- AND THEY ARE BUILT BIG. A garden butterfly is right under your nose, so a 0.5-stud wing is plenty; out on
-- the island the nearest one is twenty or thirty studs away and that same wing is a sub-pixel speck. These are
-- built at ISLAND_BUG_SCALE, which is the entire difference between "there are no bugs" and "there are bugs".
local ISLAND_BUG_SCALE = 2.8
local islandBugN = 0
local function scatter(b, lowH, highH)
	islandBugN += 1
	b.propIdx   = islandBugN     -- which prop on the island this one gets, once the sweep has found them
	local ang = rng:NextNumber(0, math.pi * 2)
	local rad = math.sqrt(rng:NextNumber(0.05, 1)) * ISLAND_BUG_R -- sqrt: even coverage, not a bullseye
	b.anchorOff = Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad) -- only used if it gets no prop
	b.height    = rng:NextNumber(lowH, highH)
	b.phase     = rng:NextNumber(0, math.pi * 2)
	critters[#critters + 1] = b
end
for i = 1, ISLAND_BUTTERFLIES do
	local c = WING_COLORS[((i - 1) % #WING_COLORS) + 1]
	local b = buildButterfly(c[1], c[2], ISLAND_BUG_SCALE)
	b.kind   = "butterfly"
	b.scale  = ISLAND_BUG_SCALE
	b.radius = rng:NextNumber(4, 9)               -- a butterfly wanders further from its prop than a bee
	b.speed  = rng:NextNumber(0.16, 0.34)
	b.bobAmp = rng:NextNumber(0.8, 2.2)
	b.bobFreq = rng:NextNumber(1.4, 2.6)
	b.flap   = rng:NextNumber(7, 11)
	scatter(b, 1.5, 4)
end
for _ = 1, ISLAND_BEES do
	local b = buildBee(ISLAND_BUG_SCALE)
	b.kind   = "bee"
	b.scale  = ISLAND_BUG_SCALE
	b.radius = rng:NextNumber(2.5, 6)
	b.speed  = rng:NextNumber(0.5, 0.9)
	b.bobAmp = rng:NextNumber(0.3, 0.8)
	b.bobFreq = rng:NextNumber(3, 5)
	b.flap   = rng:NextNumber(28, 40)
	scatter(b, 1.2, 3.5)
end
for _ = 1, ISLAND_FLIES do
	local b = buildFly(ISLAND_BUG_SCALE * 0.8)    -- a gnat stays the smallest thing out there, just not invisible
	b.kind   = "fly"
	b.scale  = ISLAND_BUG_SCALE * 0.8
	b.radius = rng:NextNumber(1.2, 3)             -- a gnat holds one spot and jitters in it
	b.speed  = rng:NextNumber(1.1, 2.0)
	b.bobAmp = rng:NextNumber(0.5, 1.3)
	b.bobFreq = rng:NextNumber(5, 8)
	b.flap   = rng:NextNumber(34, 48)
	scatter(b, 1.5, 4.5)
end
print(("[Wildlife] garden %db+%dbee | island %db+%dbee+%dgnat | %d birds")
	:format(BUTTERFLIES, BEES, ISLAND_BUTTERFLIES, ISLAND_BEES, ISLAND_FLIES, BIRDS))

-- ===== BIRD FLIGHT PATH ===================================================================================
-- ONE analytic function of time, which is what buys everything else: sample it a moment AHEAD and the
-- difference is the velocity, and velocity is what pitch and bank are built out of. The old bird was a circle,
-- plus a facing that happened to point along it, plus a sine on the wings -- three animations that never
-- agreed with each other. This is one path, and every part of the pose is derived from it.
-- THE SWOOP. Four birds all riding the same lazy circle forever is a mobile hanging over a cot: the motion is
-- pleasant and completely without event. Every 25-50 seconds one of them peels off, drops thirty-odd studs on
-- a tightening turn and climbs back out. It is the one moment in the whole loop where a bird looks like it
-- WANTED something, and because the path is analytic the nose-down, the bank into it and the climb out all
-- fall out of the same maths -- there is no separate dive animation to keep in sync.
--
-- Returns 0 for most of the cycle and a smooth out-and-back hump during the dive, zero-slope at both ends so
-- entry and recovery have no kink in them.
local function birdSwoop(c, tt)
	local u = ((tt + c.swoopPhase) % c.swoopLen) / c.swoopLen
	if u >= c.swoopFrac then return 0 end
	local k = math.sin((u / c.swoopFrac) * math.pi)
	return k * k
end

local function birdPos(c, centre, tt)
	local a = tt * c.speed * c.dir + c.phase
	local sw = birdSwoop(c, tt)
	-- the circle TIGHTENS as it dives: speed traded for turn, which is what makes the stoop read as deliberate
	local r = c.radius * (1 + 0.18 * math.sin(a * 1.7 + c.phase)) * (1 - 0.26 * sw)
	-- THERMAL DRIFT: the circle ITSELF wanders. A bird holding one fixed centre for ten minutes is a carousel
	-- horse; a real soaring bird slides with the air and keeps re-finding the lift.
	local dx = math.sin(tt * c.driftF + c.phase) * c.driftA
	local dz = math.cos(tt * c.driftF * 0.83 + c.phase * 1.7) * c.driftA
	-- FLAP-GLIDE: it climbs on the burst of flaps and sinks back through the glide. This is what ties the
	-- height change to the WINGS instead of leaving it as a second, unrelated sine that disagrees with them.
	local u = ((tt + c.cyclePhase) % c.cycleLen) / c.cycleLen
	local climb = (u < c.flapFrac) and (u / c.flapFrac) or (1 - (u - c.flapFrac) / (1 - c.flapFrac))
	climb = climb * climb * (3 - 2 * climb) -- smoothstep: no kink at the top or the bottom of the sawtooth
	return centre + Vector3.new(
		math.cos(a) * r + dx,
		c.height + math.sin(tt * c.bobFreq + c.phase) * c.bobAmp + climb * c.pumpAmp - sw * c.swoopDepth,
		math.sin(a) * r + dz
	)
end

-- How hard it is flapping right now: ZERO for most of the cycle -- wings simply held, and it sails -- then a
-- burst that eases in and out. Also returns how far through the burst we are, so the beat can start strong and
-- tire through it. Constant flapping is what every fake bird does and no soaring bird does.
local function birdFlap(c, tt)
	local u = ((tt + c.cyclePhase) % c.cycleLen) / c.cycleLen
	if u >= c.flapFrac then return 0, 0 end
	local k = u / c.flapFrac
	return math.clamp(math.min(k * 5, (1 - k) * 3), 0, 1), k
end

local function poseBird(c, centre, t)
	local s   = c.scale
	local pos = birdPos(c, centre, t)
	local vel = birdPos(c, centre, t + 0.12) - pos
	local fwd = (vel.Magnitude > 1e-4) and vel.Unit or Vector3.new(0, 0, 1)

	-- BANK -- the single most convincing item on this list. A bird does not turn flat: it rolls into the circle
	-- and the turn falls out of the lean. Anything tracking a curve dead level reads as a model on a wire,
	-- which is exactly what this was. The lean goes toward the centre (which sits to its RIGHT when it circles
	-- anticlockwise) and breathes a couple of degrees so it is never a locked pose. PITCH comes free: lookAt is
	-- fed the real velocity, so it noses up on the climb and drops its head on the glide without being told to.
	-- It leans HARDER through the swoop -- a tighter turn is a steeper bank, and that is the read that turns a
	-- drop in altitude into a dive rather than a bird sinking.
	local sw   = birdSwoop(c, t)
	local roll = -c.dir * (c.bank * (1 + 0.55 * sw) + math.rad(4) * math.sin(t * 0.37 + c.phase))
	local cf   = CFrame.lookAt(pos, pos + fwd) * CFrame.Angles(0, 0, roll)
	c.body.CFrame = cf

	local w, k = birdFlap(c, t)
	-- WINGS TUCK ON THE STOOP. A diving bird does not flap; it folds. Killing the beat and sweeping the wings
	-- back turns the same descent from "flapping downwards" into a shape that is falling on purpose.
	w = w * (1 - sw)
	local ph   = t * c.flapHz * math.pi * 2 + c.phase
	-- The downstroke is the fast, powerful half and the recovery is slower. A plain sine gives both the same
	-- time, which reads as a metronome; warping the phase buys the asymmetry for one extra sin().
	local beat = math.sin(ph - 0.5 * math.sin(ph))
	local amp  = c.flapAmp * (1 - 0.30 * k)
	local ang  = c.dihedral + w * amp * beat
	-- The WRIST TRAILS THE SHOULDER: lag the outer half a beat behind and let it flex further, so the wing
	-- rolls through the stroke instead of swinging like one rigid plank.
	local lph    = ph - 1.0
	local tipRel = math.rad(4) + w * amp * 0.5 * math.sin(lph - 0.5 * math.sin(lph))
	-- and it pulls its wings BACK as it drives down, spreading them again on the recovery
	local sweep  = c.sweep + math.rad(7) * w * math.max(0, -beat) + math.rad(26) * sw
	local ang2   = ang - math.rad(9) * sw   -- and the shallow V flattens as the wings come back

	local hingeL = cf * CFrame.new(-0.20 * s, 0.09 * s, 0.02 * s) * CFrame.Angles(0,  sweep, -ang2)
	local hingeR = cf * CFrame.new( 0.20 * s, 0.09 * s, 0.02 * s) * CFrame.Angles(0, -sweep,  ang2)
	c.wingL.CFrame = hingeL * CFrame.new(-0.52 * s, 0, 0)
	c.wingR.CFrame = hingeR * CFrame.new( 0.52 * s, 0, 0)
	c.tipL.CFrame  = hingeL * CFrame.new(-1.05 * s, 0, 0) * CFrame.Angles(0,  math.rad(11), -tipRel) * CFrame.new(-0.47 * s, 0, 0.07 * s)
	c.tipR.CFrame  = hingeR * CFrame.new( 1.05 * s, 0, 0) * CFrame.Angles(0, -math.rad(11),  tipRel) * CFrame.new( 0.47 * s, 0, 0.07 * s)

	-- TAIL: behind and a touch high, twisted back against the roll -- a banking bird steers with it, and it
	-- never lies as far over in the turn as the wings do.
	c.tail.CFrame = cf * CFrame.new(0, 0.03 * s, 0.84 * s) * CFrame.Angles(math.rad(3), 0, -roll * 0.35)

	-- HEAD STABILISATION. Real behaviour, and free: a bird keeps its head LEVEL and locked on the ground it is
	-- watching while the body rolls and pitches underneath it. Almost nothing bothers with this, and it is
	-- instantly legible -- the head sitting flat while the body leans is what sells the lean as deliberate.
	local hp   = (cf * CFrame.new(0, 0.05 * s, -0.76 * s)).Position
	local flat = Vector3.new(fwd.X, 0, fwd.Z)
	flat = (flat.Magnitude > 1e-4) and flat.Unit or Vector3.new(0, 0, 1)
	c.head.CFrame = CFrame.lookAt(hp, hp + flat)
		* CFrame.Angles(0, math.rad(11) * math.sin(t * 0.23 + c.phase * 2.1), 0) -- glancing about as it goes
	-- The beak rides the HEAD, not the body, so it swings with every glance -- which is the whole point of
	-- having posed the head separately in the first place.
	if c.beak then c.beak.CFrame = c.head.CFrame * CFrame.new(0, -0.02 * s, -0.28 * s) end
end

-- A scattered bug finds its own ground ONCE, the first time it is near enough to be worth animating (the
-- island streams in, so asking at spawn time would raycast into empty air). If the ray finds nothing -- a bug
-- out over a gap in the island -- it keeps the garden height, which is a perfectly good answer.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.FilterDescendantsInstances = { folder }
local function groundAnchor(c)
	local hit = Workspace:Raycast(c.anchor + Vector3.new(0, 90, 0), Vector3.new(0, -320, 0), groundParams)
	if hit then c.anchor = Vector3.new(c.anchor.X, hit.Position.Y, c.anchor.Z) end
	c.grounded = true
end

-- ===== FLY =====
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	local me = hrp and hrp.Position

	for _, c in ipairs(critters) do
		-- Where this critter lives: the island for the birds, its OWN patch of the island for the scattered
		-- bugs, the garden centre for the garden's own.
		local centre
		if c.kind == "bird" then
			centre = islandPos
		elseif c.anchorOff then
			if not c.anchor and gardenPos then
				-- A REAL PROP FIRST. Bugs drift around the things on the island, not around empty coordinates
				-- in a field -- that is both what a bug does and the only way a player ever gets near one.
				local p = propAnchors[c.propIdx]
				if p then
					c.anchor = p
				elseif propsReady then
					-- No prop left for this one (or the island never resolved): fall back to open ground, and
					-- raycast down for it. Island X/Z, GARDEN Y -- the island model's pivot sits ~90 studs
					-- UNDER the surface you walk on, the same trap the birds and the birdsong both fell into.
					local b = islandPos or gardenPos
					c.anchor = Vector3.new(b.X, gardenPos.Y, b.Z) + c.anchorOff
					c.needGround = true
				end
			end
			centre = c.anchor
		elseif c.atHive and hivePos then
			-- Read every frame, not cached: the hive is built a few seconds after the bees are, so this is
			-- nil at first and simply falls through to the garden centre until the prop exists.
			centre = hivePos
		else
			centre = gardenPos
		end

		if centre and c.model.Parent then
			-- CULL: freeze anything the player is nowhere near. This is what makes the critters free rather
			-- than merely cheap -- and because every scattered bug owns its own patch, they wake one at a time
			-- as you walk the island instead of all switching on together.
			if me and (centre - me).Magnitude > DRAW_DIST + c.radius then
				if c.body.Transparency < 1 then
					for _, p in ipairs(c.model:GetChildren()) do
						if p:IsA("BasePart") then p.Transparency = 1 end
					end
				end
			else
				if c.body.Transparency >= 1 then
					-- RESTORE FROM EACH PART'S OWN BUILD-TIME VALUE. This used to name body/wings/stripe one by
					-- one, which meant any part added to a critter afterwards was hidden by the first cull and
					-- never came back -- and the cull loop above hides EVERY part, so the omission was silent.
					-- Reading the value back off the part cannot fall out of step with what was built.
					for _, p in ipairs(c.model:GetChildren()) do
						if p:IsA("BasePart") then p.Transparency = p:GetAttribute("BaseT") or 0 end
					end
				end
				-- Only the open-ground fallbacks need a raycast; a bug sitting on a prop already knows its height.
				if c.anchor and c.needGround and not c.grounded then groundAnchor(c); centre = c.anchor end

				if c.kind == "bird" then
					poseBird(c, centre, t)
				else
					local a = t * c.speed + c.phase
					-- a wobbling circle, not a clean one -- a perfect orbit is the tell that something is on rails
					local r = c.radius * (1 + 0.18 * math.sin(a * 1.7 + c.phase))
					local pos = centre + Vector3.new(
						math.cos(a) * r,
						c.height + math.sin(t * c.bobFreq + c.phase) * c.bobAmp,
						math.sin(a) * r
					)
					-- a gnat does not travel, it DARTS: a fast three-axis jitter on top of the drift, which is
					-- the whole read at the size of a speck
					if c.kind == "fly" then
						pos = pos + Vector3.new(
							math.sin(t * 7.3 + c.phase) * 0.55,
							math.sin(t * 9.1 + c.phase * 2) * 0.40,
							math.cos(t * 8.2 + c.phase) * 0.55
						)
					end

					-- ---- DODGE THE PLAYER ----------------------------------------------------------
					-- Measured from the bug's DRIFT position, not from its dodged one, or the push would
					-- feed back into its own input and the bug would jitter on the edge of the radius.
					local want = Vector3.zero
					if me then
						local away = pos - me
						away = Vector3.new(away.X, 0, away.Z)          -- horizontal: being above you is not away
						local d = away.Magnitude
						if d < SHY_RADIUS then
							-- Straight overhead (d ~ 0) has no direction to flee in, so pick one from the
							-- bug's own phase -- deterministic, and different per bug, so a cluster scatters
							-- instead of every one of them leaving on the same heading.
							local dir = (d > 0.05) and (away / d)
								or Vector3.new(math.cos(c.phase), 0, math.sin(c.phase))
							local strength = 1 - (d / SHY_RADIUS)       -- 0 at the rim, 1 on top of you
							want = dir * (SHY_PUSH * strength) + Vector3.new(0, SHY_PUSH * SHY_RISE * strength, 0)
						end
					end
					c.dodge = (c.dodge or Vector3.zero):Lerp(want, SHY_EASE)
					pos = pos + c.dodge

					-- face the way we are going (the tangent of the circle) -- unless it is actively getting
					-- away from you, in which case it faces where it is fleeing, which is what an animal does.
					local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
					if c.dodge.Magnitude > 0.2 then
						local f = Vector3.new(c.dodge.X, 0, c.dodge.Z)
						if f.Magnitude > 0.05 then tangent = f.Unit end
					end
					local cf = CFrame.lookAt(pos, pos + tangent)
					c.body.CFrame = cf
					if c.stripe then c.stripe.CFrame = cf * CFrame.new(0, 0, 0.02) end

					-- WINGS: butterflies, bees and gnats all flap about the body's LONG axis -- they beat up and
					-- down at the sides. (The bird's are a different hinge entirely; see poseBird.)
					local beat = math.sin(t * c.flap + c.phase)
					local deg  = (c.kind == "bee" and 55) or (c.kind == "fly" and 40) or 78
					local open = math.rad(deg) * (0.35 + 0.65 * ((beat + 1) / 2))
					-- the hinge offset scales with the body, or a big island butterfly wears a garden-sized shoulder
					local ws = c.scale or 1
					c.wingL.CFrame = cf * CFrame.new(-0.06 * ws, 0.16 * ws, 0) * CFrame.Angles(0, 0, open)
					c.wingR.CFrame = cf * CFrame.new(0.06 * ws, 0.16 * ws, 0) * CFrame.Angles(0, 0, -open)
				end
			end
		end
	end
end)

print("[Wildlife] ready -- bugs over the garden AND scattered across Bean Farm, birds circling above it (client-side, no replication)")
