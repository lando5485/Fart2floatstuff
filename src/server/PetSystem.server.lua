-- ============================================================================================
-- PET SYSTEM (server) -- COSMETIC ONLY. First pet: BroccoliPet on Broccoli Bluff (Island 2).
-- ============================================================================================
-- Flow: player finds 3 hidden broccoli pieces -> egg appears at I2PetBlock -> claim (E) -> a
-- broccoli pet follows them forever (saved). This file owns the AUTHORITATIVE state (piece counts,
-- ownership, persistence handshake) + the world MARKERS. The per-player pieces/egg visuals AND the
-- follow pet are built CLIENT-SIDE (PetFollow.client.lua) so they can be per-player and follow
-- smoothly during fast flight. NOTHING here touches flight/gas/coins/balance -- purely cosmetic.
--
-- MODULAR: to add pet #2, add another entry to PETS below (marker names + island prefix) and reuse
-- the same remotes (the piece/egg/claim protocol is keyed by petId).
-- ============================================================================================

local Players   = game:GetService("Players")
local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Shared ownership table (PlayerStats persists it under saved.ownedPets; we read/write it on claim).
_G.playerOwnedPets = _G.playerOwnedPets or {}

-- Per-SESSION piece progress (NOT saved -- only ownership persists; an owner skips finding entirely).
local piecesFound = {}  -- [player] = { [petId] = { [pieceIndex]=true, ... } }

-- ===== PET CATALOG (extend this to add more pets later) =====
local PETS = {
	BroccoliPet = {
		displayName  = "Broccoli Dino",
		islandName   = "Broccoli Bluff",
		questDesc    = "Find 3 broccoli pieces hidden on the island",
		questType    = "find",                -- find 3 pieces -> egg -> hatch
		islandPrefix = "Island_2_",          -- the Workspace island model this pet's markers live in
		eggMarker    = "I2PetBlock",          -- where the egg appears
		pieceMarkers = { "BroccoliPiece1", "BroccoliPiece2", "BroccoliPiece3" },
		-- ===== LEVELING (cosmetic-only, ~3 tiers, extensible) =====
		maxLevel     = 3,
		-- ACHIEVEMENT thresholds to REACH each level (placeholder/easy for now -- tune next build). A tier
		-- unlocks once EITHER the equipped-pet's peak flight height OR its total time-with-pet reaches it.
		tiers = {
			[2] = { height = 1200, time = 90 },
			[3] = { height = 6000, time = 300 },
		},
	},
	-- PET #2: COCONUT CRAB on Coconut Cove (Island 5). Harder multi-stage quest: CRACK 7 coconuts (tap
	-- minigame) -> earn the Cave Key -> open the chest in the cave -> egg -> hatch. The server treats the 7
	-- coconuts as "pieces" and the chest as the "egg" marker, so the generic collect/claim/inventory/leveling
	-- logic is reused; the client builds the crack minigame + chest + key gate from these same positions.
	CoconutCrab = {
		displayName  = "Coconut Crab",
		islandName   = "Coconut Cove",
		questDesc    = "Crack 7 coconuts, then find the cave chest",
		questType    = "crack",
		islandPrefix = "Island_5_",          -- Coconut Cove
		eggMarker    = "CoconutChest",        -- the treasure chest (in the cave) = where the egg appears
		pieceMarkers = { "Coconut1","Coconut2","Coconut3","Coconut4","Coconut5","Coconut6","Coconut7" },
		maxLevel     = 3,
		tiers = {
			[2] = { height = 2000, time = 120 },
			[3] = { height = 8000, time = 400 },
		},
	},
	-- PET #3: POPCORN SHEEP on Popcorn Pinnacle (Island 8). Movie-theater themed. questType "film-reels":
	-- find 6 FILM REELS -> load them at the PROJECTOR -> a mini-movie plays on the SCREEN -> the egg
	-- materializes in a spotlight at PopcornEggSpot -> hatch. The server treats the 6 reels as "pieces" and
	-- PopcornEggSpot as the "egg" marker, so the generic collect/claim/inventory/leveling logic is reused;
	-- the client builds the reels + projector + screen mini-movie + spotlight egg from these positions. The
	-- extra (non-collectible) PROJECTOR + SCREEN positions ride alongside in extraMarkers.
	PopcornSheep = {
		displayName  = "Popcorn Sheep",
		islandName   = "Popcorn Pinnacle",
		questDesc    = "Find 6 film reels, then start the show at the projector",
		questType    = "film-reels",
		questUnit    = "reels",               -- inventory progress label ("4/6 reels")
		islandPrefix = "Island_8_",          -- Popcorn Pinnacle
		eggMarker    = "PopcornEggSpot",      -- floor in front of the screen = where the egg appears (in a spotlight)
		pieceMarkers = { "FilmReel1","FilmReel2","FilmReel3","FilmReel4","FilmReel5","FilmReel6" },
		extraMarkers = { projector = "PopcornProjector", screen = "PopcornScreen" }, -- fixed props
		-- "use existing" extras: keep the placed instance VISIBLE + send its reference (the client renders the
		-- mini-movie ON the user's real PopcornScreen). Others (projector) are hidden + rebuilt client-side.
		extraExisting = { screen = true },
		maxLevel     = 3,
		tiers = {
			[2] = { height = 13000, time = 150 },
			[3] = { height = 22000, time = 500 },
		},
	},
	-- PET #4: BUTTER DUCK on Butter Swamp (Island 10). "Hook & Reel" FISHING quest: grab a rod at the barrel
	-- -> fish near/over the ButterLake UNION -> cast -> bite/hook (reaction) -> reel-in tension minigame -> the
	-- SERVER rolls the catch (pity-ramped egg chance + funny junk for misses) -> the egg appears IN FRONT of the
	-- player -> hatch. NO pieces + NO egg marker (the egg spawns where caught). Markers = the fishable lake union
	-- + the rod barrel. The catch ROLL is server-authoritative (PetFishRoll RF below) with a per-player pity ramp.
	ButterDuck = {
		displayName  = "Butter Duck",
		islandName   = "Butter Swamp",
		questDesc    = "Grab a rod from the barrel, then fish in the butter swamp to catch the egg",
		questType    = "fishing",
		questUnit    = "catches",
		islandPrefix = "Island_10_",         -- Butter Swamp
		pieceMarkers = {},                    -- fishing has no collectible pieces
		-- eggMarker = nil: the caught egg appears IN FRONT of the player (not at a fixed marker)
		extraMarkers = { butterlake = "ButterLake", rodbarrel = "RodBarrel" },
		extraExisting = { butterlake = true }, -- ButterLake is the VISIBLE butter UNION -- keep it, don't hide it
		maxLevel     = 3,
		tiers = {
			[2] = { height = 19000, time = 180 },
			[3] = { height = 28000, time = 600 },
		},
	},
}

local function getOrCreateRemote(name)
	local r = RS:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = RS end
	return r
end
local function getOrCreateRF(name)
	local r = RS:FindFirstChild(name)
	if not r then r = Instance.new("RemoteFunction"); r.Name = name; r.Parent = RS end
	return r
end
local PetCollectEvent      = getOrCreateRemote("PetCollectEvent")      -- c->s: (petId, pieceIndex)
local PetClaimEvent        = getOrCreateRemote("PetClaimEvent")        -- c->s: (petId)
local PetRequestStateEvent = getOrCreateRemote("PetRequestStateEvent") -- c->s: () handshake
local PetGetMarkers        = getOrCreateRF("PetGetMarkers")            -- c->s RF: (petId) -> {pieces={Vector3..}, egg=Vector3}

-- SERVER-OWNED marker POSITIONS, captured once on the marker scan below. The client never searches
-- Workspace itself -- it asks for these coordinates via PetGetMarkers. [petId] = {pieces={...}, egg=...}.
local markerPositions = {}
local PetStateEvent        = getOrCreateRemote("PetStateEvent")        -- s->c: (stateTable)

-- ===== PET INVENTORY / EQUIP / LEVELING remotes (cosmetic-only) =====
local PetEquipEvent     = getOrCreateRemote("PetEquipEvent")           -- c->s: (petId|false) equip / unequip
local PetInventoryEvent = getOrCreateRemote("PetInventoryEvent")       -- s->c: (inventory table for the GUI)
local PetUpgradeEvent   = getOrCreateRemote("PetUpgradeEvent")         -- c->s: (petId) free achievement upgrade
local PetProgressEvent  = getOrCreateRemote("PetProgressEvent")        -- c->s: (petId, peakHeight, addTime)
local PetPendingUpgrade = getOrCreateRemote("PetPendingUpgradeEvent")  -- c->s: (petId) declared before a Robux prompt
local PetQuestDiscovered = getOrCreateRemote("PetQuestDiscoveredEvent") -- c->s: (petId) the player landed on this pet's island
local PetFishRoll = getOrCreateRF("PetFishRollEvent")                 -- c->s RF: () player reeled in -> SERVER rolls the catch (pity)
local fishCatches  = {}  -- [player] = number of successful reel-ins (drives the pity ramp; session-only, not saved)
local fishEggReady = {}  -- [player] = true once the SERVER has rolled the EGG (gates the ButterDuck claim, anti-cheat)
_G.playerDiscoveredQuests = _G.playerDiscoveredQuests or {}           -- [player] = { [petId]=true } (persisted by PlayerStats)
_G.playerEquippedPet = _G.playerEquippedPet or {}                      -- [player] = petId (persisted by PlayerStats)
local pendingRobuxPet = {}                                             -- [userId] = petId awaiting a Robux receipt
local upgradeReady    = {}                                            -- [player][petId] = last canUpgrade (to avoid resend spam)
-- ⚠ REPLACE WITH REAL DEV PRODUCT ID: the Robux "skip the grind" pet-upgrade Developer Product. While this
-- is 0 the Robux button is a stub (the prompt won't open and no level is granted) -- create the product and
-- set its id here (and the matching id in PetFollow.client.lua) to enable the paid path.
local PET_UPGRADE_PRODUCT_ID = 0

-- ============================================================================================
-- PET MODEL TEMPLATE: "BROCCOLI DINO" (FRESH BUILD). CSG/UnionAsync is SERVER-ONLY, so we construct +
-- fuse the rounded-cube body HERE once at startup, store the finished Model in ReplicatedStorage, and the
-- client CLONES it for the follow loop. This is purely the MODEL builder -- the find/egg/hatch/follow/UI/
-- persistence system is untouched and plugs into the same invisible-root PrimaryPart + role-named parts
-- (Eye/Highlight blink, Leg/ToeClaw gait, Tail/TailSpike wiggle, everything else rides the body).
-- Cosmetic only (Anchored, Massless, CanCollide=false). Local frame: +X = forward, +Y = up, +Z = width.
-- ============================================================================================
local function buildPetTemplate()
	local s = 0.9 -- display scale baked into the template

	-- bright, saturated palette (nudged up a touch so it pops through the game's dark lighting)
	local LIME   = Color3.fromRGB(146, 205, 78)  -- body
	local FOREST = Color3.fromRGB(50, 148, 62)   -- florets / claws / spikes
	local PALE   = Color3.fromRGB(214, 236, 158) -- belly
	local NDARK  = Color3.fromRGB(70, 120, 42)   -- nostril dents
	local BLACK  = Color3.fromRGB(0, 0, 0)       -- eyes
	local WHITE  = Color3.fromRGB(255, 255, 255) -- highlights / fangs
	local MOUTH  = Color3.fromRGB(38, 24, 24)    -- smile
	local BLK, BAL, CYL = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder

	local model = Instance.new("Model"); model.Name = "BroccoliDinoTemplate"
	-- one place to stamp the cosmetic flags on every part
	local function flag(p)
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.SmoothPlastic
		return p
	end
	-- make a part: name, shape, (sx,sy,sz) studs (pre-scale), color, (x,y,z) studs, optional local rotation
	local function part(name, shape, sx, sy, sz, color, x, y, z, rot)
		local p = Instance.new("Part"); p.Name = name; p.Shape = shape
		p.Size = Vector3.new(sx, sy, sz) * s; p.Color = color
		local cf = CFrame.new(x*s, y*s, z*s); if rot then cf = cf * rot end
		p.CFrame = cf; flag(p); return p
	end

	-- invisible root = PrimaryPart (the follow loop drives this; animations are offsets around it)
	local root = part("Root", BAL, 0.4, 0.4, 0.4, WHITE, 0, 0, 0); root.Transparency = 1
	root.Parent = model; model.PrimaryPart = root
	model.Parent = Workspace -- CSG needs the parts in the DataModel; we move the Model to RS after fusing

	-- ===== 1) ROUNDED-CUBE BODY/HEAD (one combined piece, ~1:1:0.8, ~4 wide) ============================
	-- Built as a fillet/Minkowski rounded box so EVERY corner+edge is soft: 3 cross slabs (the flat faces) +
	-- 8 corner spheres + 12 edge cylinders, plus a puffy rounded snout -- all lime, fused into ONE solid.
	local W, H, Dp, R = 4.2, 4.2, 3.4, 1.0          -- width(Z), height(Y), depth(X), fillet radius
	local iW, iH, iD = W - 2*R, H - 2*R, Dp - 2*R    -- inner-box dims (the flat extents)
	local hW, hH, hD = iW/2, iH/2, iD/2
	local d = 2*R                                     -- fillet diameter
	local bodySrc = {}
	local function bodyPart(name, shape, sx, sy, sz, x, y, z, rot)
		local p = part(name, shape, sx, sy, sz, LIME, x, y, z, rot); p.Parent = model; bodySrc[#bodySrc+1] = p
	end
	-- 3 cross slabs (axis-full in one dimension, inner in the others) form the flat faces
	bodyPart("BodySlab", BLK, Dp, iH, iW, 0, 0, 0)
	bodyPart("BodySlab", BLK, iD, H, iW, 0, 0, 0)
	bodyPart("BodySlab", BLK, iD, iH, W, 0, 0, 0)
	-- 8 corner spheres
	for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
		bodyPart("BodyCorner", BAL, d, d, d, c[1]*hD, c[2]*hH, c[3]*hW)
	end
	-- 12 edge cylinders (4 along each axis)
	for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do
		bodyPart("EdgeX", CYL, iD, d, d, 0, e[1]*hH, e[2]*hW)
		bodyPart("EdgeY", CYL, iH, d, d, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0, 0, math.rad(90)))
		bodyPart("EdgeZ", CYL, iW, d, d, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0, math.rad(90), 0))
	end
	-- puffy rounded SNOUT (~38% of width), lower-centre, protruding forward -- fused into the body
	bodyPart("Snout", BAL, 1.45, 1.3, 1.6, 1.95, -0.85, 0)

	-- fuse on the server
	local unionErr
	local first = table.remove(bodySrc, 1)
	local ok, union = pcall(function() return first:UnionAsync(bodySrc) end)
	if ok and typeof(union) == "Instance" then
		first:Destroy(); for _, p in ipairs(bodySrc) do p:Destroy() end
		flag(union); union.Name = "BodyUnion"; union.UsePartColor = true; union.Color = LIME
		pcall(function() union.RenderFidelity = Enum.RenderFidelity.Precise end)
		pcall(function() union.CollisionFidelity = Enum.CollisionFidelity.Box end)
		pcall(function() union.SmoothingAngle = 60 end) -- soft satin shading across the fused body
		union.Parent = model
	else
		-- CSG unavailable: keep the (unfused) lime chunks so the FULL pet still appears (client treats
		-- unknown names as role "body"). The log will report this so we know fusion didn't run.
		unionErr = tostring(union)
		table.insert(bodySrc, 1, first)
		for _, p in ipairs(bodySrc) do p.Name = "BodyChunk" end
	end

	-- ===== separate coloured parts =================================================================
	local function add(name, shape, sx, sy, sz, color, x, y, z, rot)
		local p = part(name, shape, sx, sy, sz, color, x, y, z, rot); p.Parent = model; return p
	end

	-- 2) EYES: huge black ovals (taller than wide), domed out, wide apart on the upper face; each with
	-- EXACTLY two white highlights (big upper-left + small lower-right) seated just in front of the black.
	for _, ez in ipairs({ 1.12, -1.12 }) do
		local eye = add("Eye", BAL, 0.6, 1.9, 1.5, BLACK, 1.74, 0.98, ez)
		eye.Reflectance = 0.06 -- subtle glossy-bead shine (not a marble)
		add("Highlight", BAL, 0.12, 0.48, 0.4, WHITE, 2.06, 1.46, ez + 0.32) -- big, upper-left
		add("Highlight", BAL, 0.1, 0.22, 0.2, WHITE, 2.08, 0.62, ez - 0.3)   -- small, lower-right
	end

	-- 3) SNOUT FACE: subtle nostril dents on top + a thin dark upturned SMILE + two white down-fangs.
	for _, nz in ipairs({ 0.22, -0.22 }) do add("Nostril", BAL, 0.16, 0.1, 0.16, NDARK, 2.42, -0.42, nz) end
	add("Mouth", BAL, 0.18, 0.16, 0.74, MOUTH, 2.5, -1.3, 0)      -- smile centre (low)
	add("Mouth", BAL, 0.16, 0.16, 0.24, MOUTH, 2.46, -1.15, 0.44) -- corner, upturned
	add("Mouth", BAL, 0.16, 0.16, 0.24, MOUTH, 2.46, -1.15, -0.44)
	for _, fz in ipairs({ 0.36, -0.36 }) do add("Fang", BAL, 0.14, 0.32, 0.16, WHITE, 2.46, -1.55, fz) end

	-- 4) BELLY: pale rounded oval on the lower-front centre.
	add("Belly", BAL, 0.45, 2.2, 2.0, PALE, 1.55, -0.95, 0)

	-- 5) BROCCOLI CROWN: 6 large forest-green florets (fuzzy Grass) clustered into a dome ~as wide as the
	-- head, taller at back-centre, each on a VISIBLE lime stalk whose length is computed to seat it flush
	-- from inside the head top up into the floret (no floating).
	local headTop = H/2 -- 2.1
	for _, f in ipairs({
		{ x = -0.55, z =  0.0,  fy = 3.25, d = 1.8 },
		{ x = -0.1,  z =  0.0,  fy = 3.1,  d = 1.65 },
		{ x =  0.1,  z =  0.85, fy = 2.9,  d = 1.55 },
		{ x =  0.1,  z = -0.85, fy = 2.9,  d = 1.55 },
		{ x =  0.75, z =  0.42, fy = 2.75, d = 1.45 },
		{ x =  0.75, z = -0.42, fy = 2.75, d = 1.45 },
	}) do
		local sBot, sTop = headTop - 0.25, f.fy - f.d*0.35 -- stalk spans from just inside the head into the floret
		add("Stalk", CYL, sTop - sBot, 0.5, 0.5, LIME, f.x, (sBot + sTop)/2, f.z, CFrame.Angles(0, 0, math.rad(90)))
		local floret = add("Floret", BAL, f.d, f.d, f.d, FOREST, f.x, f.fy, f.z)
		pcall(function() floret.Material = Enum.Material.Grass end) -- fuzzy broccoli texture (florets only)
	end

	-- 6) ARMS: tiny stubby box-arms on the front-sides, angled DOWN + FORWARD, each with 3 claw nubs.
	for _, az in ipairs({ 1, -1 }) do
		local arm = add("Arm", BLK, 0.55, 0.55, 1.0, LIME, 1.0, -0.55, az*1.7, CFrame.Angles(math.rad(38), 0, math.rad(-32)*az))
		local tip = arm.CFrame * CFrame.new(0, 0, -0.55*s) -- the down-forward end of the angled arm
		for _, cx in ipairs({ -0.18, 0, 0.18 }) do
			local claw = add("ArmClaw", BAL, 0.2, 0.2, 0.22, FOREST, 0, 0, 0)
			claw.CFrame = tip * CFrame.new(cx*s, -0.08*s, 0)
		end
	end

	-- 7) LEGS: two short THICK stubby legs under the body, with 3 toe-claws each on the front edge.
	for _, lz in ipairs({ 0.95, -0.95 }) do
		add("Leg", BLK, 1.2, 1.2, 1.2, LIME, 0.2, -2.6, lz)
		for _, cz in ipairs({ -0.3, 0, 0.3 }) do add("ToeClaw", BAL, 0.32, 0.24, 0.26, FOREST, 0.8, -3.0, lz + cz) end
	end

	-- 8) TAIL: chunky tapering tail off the lower back curving up (3 shrinking segments) + 3 ridge spikes.
	add("Tail", BAL, 1.7, 1.45, 1.45, LIME, -2.0, -0.55, 0)
	add("Tail", BAL, 1.15, 1.0, 1.0, LIME, -2.85, -0.05, 0)
	add("Tail", BAL, 0.7, 0.62, 0.62, LIME, -3.45, 0.3, 0)
	for _, ts in ipairs({ {-2.0, 0.7, 0.5}, {-2.6, 0.85, 0.44}, {-3.1, 0.78, 0.36} }) do
		add("TailSpike", BAL, ts[3], ts[3]*1.6, ts[3], FOREST, ts[1], ts[2], 0)
	end

	-- ===== EFFECTS: subtle twinkle sparkles + a few drifting green leaf motes (emit from the root) ======
	local sp = Instance.new("ParticleEmitter"); sp.Name = "Sparkles"
	sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sp.Color = ColorSequence.new(Color3.fromRGB(235,255,180)); sp.Rate = 5
	sp.Lifetime = NumberRange.new(0.8,1.6); sp.Speed = NumberRange.new(0.5,1.5); sp.Size = NumberSequence.new(0.28)
	sp.Transparency = NumberSequence.new(0.2); sp.SpreadAngle = Vector2.new(180,180); sp.LightEmission = 0.8
	sp.Rotation = NumberRange.new(0,360); sp.Parent = root
	local lf = Instance.new("ParticleEmitter"); lf.Name = "Leaves"
	lf.Color = ColorSequence.new(Color3.fromRGB(60,180,50)); lf.Rate = 2
	lf.Lifetime = NumberRange.new(2,3.5); lf.Speed = NumberRange.new(0.4,1.0); lf.Size = NumberSequence.new(0.22)
	lf.Transparency = NumberSequence.new(0.1); lf.SpreadAngle = Vector2.new(180,180); lf.Acceleration = Vector3.new(0,0.6,0)
	lf.Rotation = NumberRange.new(0,360); lf.RotSpeed = NumberRange.new(-40,40); lf.Parent = root

	-- SLIGHT GLOSS: a hint of reflectance on the solid SmoothPlastic parts for a shiny collectible-toy
	-- sheen (skips the fuzzy Grass florets and the invisible root).
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Material == Enum.Material.SmoothPlastic and p.Transparency < 1 then
			p.Reflectance = math.max(p.Reflectance, 0.04)
		end
	end

	model.Parent = RS -- replicate the finished template to clients (they clone it)
	return model, unionErr
end
task.spawn(function()
	local model, err = buildPetTemplate()
	if model and not err then
		print("[Pet][UNION] server union SUCCESS - Broccoli Dino ready")
	elseif model and err then
		warn("[Pet][UNION] server union failed (" .. tostring(err) .. ") - Broccoli Dino ready with UNFUSED body (still the full pet)")
	else
		warn("[Pet][UNION] server pet template build FAILED: " .. tostring(err))
	end
end)

-- ===== STATE HELPERS =====
local function ownsPet(player, petId)
	local op = _G.playerOwnedPets[player]
	return op ~= nil and op[petId] ~= nil -- value may be `true` (legacy) or a {level,height,time} table
end

local function foundCount(player, petId)
	local s = piecesFound[player] and piecesFound[player][petId]
	if not s then return 0 end
	local n = 0; for _ in pairs(s) do n = n + 1 end; return n
end

-- ===== LEVELING (cosmetic) =====
-- Normalize an owned entry to a {level,height,time} table (legacy saves stored `true`).
local function getPetData(player, petId)
	local op = _G.playerOwnedPets[player]; if not op then return nil end
	local v = op[petId]; if v == nil then return nil end
	if type(v) ~= "table" then v = {}; op[petId] = v end
	v.level = v.level or 1; v.height = v.height or 0; v.time = v.time or 0
	return v
end
-- The next level + its achievement threshold (nil if already maxed).
local function nextTier(player, petId)
	local def = PETS[petId]; local d = getPetData(player, petId)
	if not (def and d) then return nil end
	local nl = d.level + 1
	if nl > (def.maxLevel or 1) then return nil end
	return nl, def.tiers and def.tiers[nl]
end
-- Has the achievement threshold for the next level been met?
local function canUpgrade(player, petId)
	local nl, th = nextTier(player, petId)
	if not nl then return false end
	if not th then return true end -- no threshold defined -> always available
	local d = getPetData(player, petId)
	return (d.height >= (th.height or math.huge)) or (d.time >= (th.time or math.huge))
end

-- Build the full state for one player across all pets and send it to that client.
local function sendState(player)
	local state = {}
	local equipped = _G.playerEquippedPet[player]
	for petId, def in pairs(PETS) do
		local owns = ownsPet(player, petId)
		state[petId] = {
			found = foundCount(player, petId), total = #def.pieceMarkers, owns = owns,
			equipped = owns and (equipped == petId) or false, -- the client only spawns the EQUIPPED follower
			level = owns and getPetData(player, petId).level or 1,
		}
	end
	pcall(function() PetStateEvent:FireClient(player, state) end)
end

-- True if this player has DISCOVERED a pet's quest (landed on its island, or owns the pet).
local function questDiscovered(player, petId)
	if ownsPet(player, petId) then return true end
	local dq = _G.playerDiscoveredQuests[player]
	return dq ~= nil and dq[petId] == true
end

-- Build + send the TWO-SECTION inventory payload to the GUI:
--   owned     = full cards (level/equip/upgrade) per OWNED pet
--   quests    = discovered quests (island/status/desc/progress) -- only once landed/owned
--   totalPets = how many pets exist in the catalog (so the client can show LOCKED "?" slots for the rest)
local function sendInventory(player)
	local equipped = _G.playerEquippedPet[player]
	local payload = { owned = {}, quests = {}, totalPets = 0 }
	for petId, def in pairs(PETS) do
		payload.totalPets = payload.totalPets + 1
		local owns = ownsPet(player, petId)
		if owns then
			local d = getPetData(player, petId)
			local nl, th = nextTier(player, petId)
			payload.owned[petId] = {
				displayName = def.displayName or petId,
				level = d.level, maxLevel = def.maxLevel or 1,
				height = math.floor(d.height), time = math.floor(d.time),
				equipped = (equipped == petId),
				canUpgrade = canUpgrade(player, petId),
				nextLevel = nl, nextHeight = th and th.height or nil, nextTime = th and th.time or nil,
			}
		end
		if questDiscovered(player, petId) then
			local found = foundCount(player, petId)
			local total = #def.pieceMarkers
			local status = owns and "done" or (found > 0 and "inprogress" or "available")
			payload.quests[petId] = {
				islandName = def.islandName or petId,
				desc = def.questDesc or "",
				status = status, found = found, total = total,
				unit = def.questUnit or ((def.questType == "crack") and "coconuts" or "pieces"),
			}
		end
	end
	pcall(function() PetInventoryEvent:FireClient(player, payload) end)
end

-- Level a pet up by one (both the achievement and Robux paths funnel here). Re-syncs follower + GUI.
local function levelUp(player, petId, via)
	local def = PETS[petId]; local d = getPetData(player, petId)
	if not (def and d) then return false end
	if d.level >= (def.maxLevel or 1) then return false end
	d.level = d.level + 1
	print("[PetInv] "..petId.." leveled up to "..d.level.." (via "..tostring(via)..")")
	sendState(player)     -- the follower re-applies its per-level visual
	sendInventory(player) -- the card shows the new level
	return true
end

-- ===== MARKERS: locate + hide the raw marker parts (kept in place so clients can read positions) =====
local function findIsland(prefix)
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.find(m.Name, prefix, 1, true) then return m end
	end
	return nil
end
local function hideMarker(part)
	if part and part:IsA("BasePart") then
		part.Transparency = 1; part.CanCollide = false; part.CanQuery = false; part.CanTouch = false
		return true
	end
	return false
end
-- Resolve a marker by EXACT name (case-sensitive): (a) inside the island model (recursive), then
-- (b) Workspace top level, then (c) anywhere in Workspace -- so markers work whether placed inside the
-- island OR at Workspace root (the user's are at Workspace top level).
local function resolveMarker(island, name)
	local p = island and island:FindFirstChild(name, true)
	if not p then p = Workspace:FindFirstChild(name) end        -- top-level Workspace child
	if not p then p = Workspace:FindFirstChild(name, true) end  -- anywhere in Workspace (recursive)
	return p
end
-- Get a marker's WORLD POSITION whether it's a single BasePart OR a built MODEL (e.g. the user's
-- PopcornProjector is a Model, not one Part -- hideMarker() alone would skip it). Hides it (all of the
-- model's BaseParts) so a client-rebuilt prop doesn't double with the placed one, and returns the position.
local function captureMarkerPos(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then
		hideMarker(inst)
		return inst.Position
	elseif inst:IsA("Model") then
		local pos
		pcall(function() pos = inst:GetPivot().Position end)                 -- pivot works even with no PrimaryPart
		if not pos and inst.PrimaryPart then pos = inst.PrimaryPart.Position end
		if not pos then pcall(function() local cf = inst:GetBoundingBox(); pos = cf.Position end) end -- bbox centre fallback
		for _, d in ipairs(inst:GetDescendants()) do if d:IsA("BasePart") then hideMarker(d) end end
		return pos
	end
	return nil -- some other instance type (Folder/Attachment/etc) -- not positionable as a marker
end
task.spawn(function()
	-- TIMING (critical): PlayerStats REPOSITIONS the islands at runtime (e.g. Island_2 -> Y=790). The
	-- markers are now CHILDREN of the island model, so they MOVE WITH IT. We must capture positions
	-- AFTER that move or we'd record the pre-move coords (the old Y=-18 bug). PlayerStats sets
	-- workspace:SetAttribute("StandsReady", true) once islands are positioned + stands are set up
	-- ("STANDS SETUP COMPLETE"), so we WAIT for that flag before reading any marker.
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 60 do task.wait(0.5); waited = waited + 0.5 end
	if Workspace:GetAttribute("StandsReady") then
		print("[Pet][DIAG] StandsReady=true after "..waited.."s -- islands are positioned; capturing marker positions")
	else
		warn("[Pet][DIAG] StandsReady never set after "..waited.."s -- capturing anyway (positions may be pre-move)")
	end
	-- Give the positioned island a moment, then find + hide each pet's markers and log diagnostics.
	for petId, def in pairs(PETS) do
		local island
		for _ = 1, 30 do island = findIsland(def.islandPrefix); if island then break end; task.wait(1) end
		if not island then
			print("[Pet] island '"..def.islandPrefix.."' not found -- resolving markers at Workspace top level instead")
		else
			print(string.format("[Pet][DIAG] island 2 positioned at Y=%.0f, capturing marker positions now", island:GetPivot().Position.Y))
		end
		-- Resolve each marker ISLAND-FIRST (they're grouped inside the island now), Workspace as backup,
		-- CAPTURE its post-positioning world position (the client builds from these coords), and hide it.
		local foundN = 0
		local piecePos = {}
		for i, name in ipairs(def.pieceMarkers) do
			local p = resolveMarker(island, name)
			if hideMarker(p) then foundN = foundN + 1; piecePos[i] = p.Position else warn("[Pet] piece marker '"..name.."' MISSING (not in island OR Workspace)") end
		end
		local eggPos = nil
		if def.eggMarker then -- fishing has NO egg marker (the egg appears where caught) -> skip the egg lookup entirely
		local egg = resolveMarker(island, def.eggMarker)
		if hideMarker(egg) then
			eggPos = egg.Position
		else
			warn("[Pet] "..def.eggMarker.." MISSING (not in island OR Workspace)")
			-- DIAGNOSTIC DUMP: the marker wasn't found by exact name -> scan the island (recursive) + Workspace
			-- top level for anything chest/coconut/crab-like so we can see the real name/location to fix it.
			local function scanList(list, where)
				for _, m in ipairs(list) do
					local n = m.Name:lower()
					if n:find("chest") or n:find("coconut") or n:find("crab") then
						print("[Pet][DIAG] chest-like found: '"..m.Name.."' ("..m.ClassName..") at "..m:GetFullName().." ["..where.."]")
					end
				end
			end
			pcall(function() if island then scanList(island:GetDescendants(), "island") end end)
			pcall(function() scanList(Workspace:GetChildren(), "Workspace top") end)
		end
		end -- close: if def.eggMarker
		-- EXTRA (non-collectible) markers -- fixed props like the projector + screen. Capture positions the same
		-- way (resolve island-first then Workspace; hide the raw marker; the client rebuilds the visuals). These
		-- may be MODELS (the user's PopcornProjector is a built Model), so use captureMarkerPos (Part OR Model).
		local extraPos, extraFound, extraInst, extraSize = {}, {}, {}, {}
		if def.extraMarkers then
			-- DIAGNOSTIC DUMP (film-reels): list every projector/popcorn-like instance (name + class + full path)
			-- so the projector's real name + whether it's a Model is visible even if the exact-name lookup misses.
			if def.questType == "film-reels" then
				local function dumpLike(list, where)
					for _, m in ipairs(list) do
						local n = m.Name:lower()
						if n:find("projector") or n:find("popcorn") then
							print("[Pet][DIAG] projector-like found: '"..m.Name.."' ("..m.ClassName..") at "..m:GetFullName().." ["..where.."]")
						end
					end
				end
				pcall(function() if island then dumpLike(island:GetDescendants(), "island") end end)
				pcall(function() dumpLike(Workspace:GetChildren(), "Workspace top") end)
			end
			for key, name in pairs(def.extraMarkers) do
				local inst = resolveMarker(island, name)
				local useExisting = def.extraExisting and def.extraExisting[key]
				local pos
				if inst and useExisting then
					-- KEEP the placed instance visible + send its reference (client renders directly on it)
					if inst:IsA("BasePart") then pos = inst.Position
					elseif inst:IsA("Model") then pcall(function() pos = inst:GetPivot().Position end) end
					if pos then extraInst[key] = inst end
				elseif inst then
					pos = captureMarkerPos(inst) -- hide it; the client rebuilds a prop at this position
				end
				if pos then
					extraPos[key] = pos; extraFound[key] = true
					-- also capture the marker's bounding-box SIZE (e.g. the ButterLake union) for client proximity checks
					if inst:IsA("BasePart") then extraSize[key] = inst.Size
					else pcall(function() local _, sz = inst:GetBoundingBox(); extraSize[key] = sz end) end
					print(string.format("[Pet][DIAG] extra marker '%s' resolved to '%s' (%s)%s at (%.0f,%.0f,%.0f)",
						key, inst and inst.Name or "?", inst and inst.ClassName or "?",
						useExisting and " [kept visible, sent to client]" or "", pos.X, pos.Y, pos.Z))
				else
					warn("[Pet] extra marker '"..name.."' ("..key..") MISSING (not found as a Part OR Model in island/Workspace)")
				end
			end
		end
		-- generic across pets: e.g. "[Pet] CoconutCrab markers found: 7/7, chest found: yes"
		if def.questType == "fishing" then
			print("[Pet] "..petId.." markers found: butterlake="..(extraFound.butterlake and "yes" or "no")
				.." (union), rodbarrel="..(extraFound.rodbarrel and "yes" or "no"))
		elseif def.questType == "film-reels" then
			print("[Pet] "..petId.." markers found: "..foundN.."/"..#def.pieceMarkers
				..", projector/screen/eggspot found: "..(extraFound.projector and "yes" or "no")
				.."/"..(extraFound.screen and "yes" or "no").."/"..(eggPos and "yes" or "no"))
		else
			print("[Pet] "..petId.." markers found: "..foundN.."/"..#def.pieceMarkers..", "
				..(def.questType == "crack" and "chest" or "egg").." found: "..(eggPos and "yes" or "no"))
		end
		markerPositions[petId] = { pieces = piecePos, egg = eggPos, extra = extraPos, extraInst = extraInst, extraSize = extraSize } -- ready for PetGetMarkers to hand to clients
	end
end)

-- ===== POSITIONS RF: the client asks for a pet's marker coordinates (it never searches Workspace) =====
local function vstr(p) return p and string.format("(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z) or "nil" end
PetGetMarkers.OnServerInvoke = function(player, petId)
	petId = petId or "BroccoliPet"
	local def = PETS[petId]
	if not def then
		warn("[Pet][DIAG] PetGetMarkers: unknown petId '"..tostring(petId).."' requested by "..player.Name)
		return nil
	end
	-- The marker scan runs at startup and may not be done yet when the client asks; wait for it.
	local waited = 0
	while not markerPositions[petId] and waited < 90 do task.wait(0.5); waited = waited + 0.5 end -- 90s: covers the StandsReady wait + island find before positions are captured
	local mp = markerPositions[petId]
	if not mp then
		warn("[Pet][DIAG] PetGetMarkers: positions for "..petId.." NOT READY for "..player.Name.." -- markers were never found server-side")
		return nil
	end
	local pp = mp.pieces or {}
	local n = 0; for _ in pairs(pp) do n = n + 1 end
	local label = (PETS[petId].questType == "crack") and "coconut" or "marker"
	print("[Pet] sending "..label.." positions to "..player.Name.." ("..n.." pieces, "..(PETS[petId].questType == "crack" and "chest" or "egg").."="..vstr(mp.egg)..")")
	return mp
end

-- ===== HANDSHAKE: PlayerStats calls this once the player's saved data (ownedPets) is loaded =====
_G.petsApplyOnJoin = function(player)
	piecesFound[player] = piecesFound[player] or {}
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	-- normalize any legacy `true` ownership into the {level,height,time} table; owning a pet implies its quest
	-- was discovered (so the quests panel shows it as Done even on a fresh session).
	for petId in pairs(PETS) do
		if ownsPet(player, petId) then getPetData(player, petId); _G.playerDiscoveredQuests[player][petId] = true end
	end
	-- default-equip an owned pet if none is equipped (legacy saves / first pet) so it still follows
	if not _G.playerEquippedPet[player] then
		for petId in pairs(PETS) do if ownsPet(player, petId) then _G.playerEquippedPet[player] = petId; break end end
	end
	sendState(player)     -- tells the client what they own + which is equipped (spawns that follower)
	sendInventory(player) -- fills the Pet Inventory GUI
	for petId in pairs(PETS) do
		if ownsPet(player, petId) then print("[Pet] "..petId.." owned by "..player.Name.." (equipped="..tostring(_G.playerEquippedPet[player] == petId)..")") end
	end
end

-- ===== REMOTE HANDLERS =====
PetRequestStateEvent.OnServerEvent:Connect(function(player)
	-- Client handshake (fires when its pet UI is ready). Respond with whatever we know so far; if the
	-- save hasn't loaded yet, ownedPets is nil -> empty, and petsApplyOnJoin will push the real state.
	piecesFound[player] = piecesFound[player] or {}
	sendState(player)
	sendInventory(player)
end)

PetCollectEvent.OnServerEvent:Connect(function(player, petId, pieceIndex)
	local def = PETS[petId]; if not def then return end
	pieceIndex = tonumber(pieceIndex)
	if not pieceIndex or pieceIndex < 1 or pieceIndex > #def.pieceMarkers then return end
	if ownsPet(player, petId) then return end -- already have the pet; ignore
	piecesFound[player] = piecesFound[player] or {}
	piecesFound[player][petId] = piecesFound[player][petId] or {}
	local set = piecesFound[player][petId]
	if set[pieceIndex] then return end -- already counted this exact piece (idempotent; no double-count)
	set[pieceIndex] = true
	local n = foundCount(player, petId)
	if def.questType == "crack" then
		print("[Pet] "..player.Name.." cracked coconut "..n.."/"..#def.pieceMarkers)
		if n == #def.pieceMarkers then print("[Pet] "..player.Name.." earned the Cave Key") end
	elseif def.questType == "film-reels" then
		print("[Pet] "..player.Name.." took film reel "..n.."/"..#def.pieceMarkers)
		if n == #def.pieceMarkers then print("[Pet] "..player.Name.." has all 6 film reels - load them at the projector") end
	else
		print("[Pet] "..player.Name.." collected piece "..n.."/"..#def.pieceMarkers)
		if n == #def.pieceMarkers then print("[Pet] egg appeared for "..player.Name.." at "..def.eggMarker) end
	end
	sendState(player)
	sendInventory(player) -- keep the quests panel's progress (N/total) current as pieces/coconuts are collected
end)

PetClaimEvent.OnServerEvent:Connect(function(player, petId)
	local def = PETS[petId]; if not def then return end
	if ownsPet(player, petId) then return end                 -- already owned
	if def.questType == "fishing" then
		-- fishing has no pieces: the SERVER-rolled egg flag is the anti-cheat gate (client can't fake a catch)
		if not fishEggReady[player] then print("[Pet] "..player.Name.." tried to claim "..petId.." without catching the egg"); return end
	else
		if foundCount(player, petId) < #def.pieceMarkers then return end -- must have all pieces (anti-cheat gate)
	end
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	_G.playerOwnedPets[player][petId] = { level = 1, height = 0, time = 0 } -- now a table (PlayerStats saves it)
	if not _G.playerEquippedPet[player] then _G.playerEquippedPet[player] = petId end -- auto-equip your first pet
	print("[Pet] "..player.Name.." claimed "..petId)
	print("[Pet] "..petId.." following "..player.Name)
	sendState(player)     -- client hides egg/pieces and spawns the equipped follower
	sendInventory(player) -- the new pet shows up in the inventory GUI
end)

-- ===== FISHING CATCH ROLL (SERVER-AUTHORITATIVE): the client invokes this after a successful reel-in. The
-- server owns the roll + the per-player pity counter so the client can NEVER decide what it catches. Egg chance
-- starts ~25% and ramps each catch, GUARANTEED by catch 8 (no endless bad luck -- it's an easy pet). A miss =
-- a funny junk item (just for variety). Returns { egg=true } or { egg=false, junk="..." } to the client. =====
local FISH_JUNK = { "an old boot", "a butter blob", "a rubber duck", "a soggy sock", "a rusty tin can",
                    "a clump of swamp weed", "a lost flip-flop", "a message in a bottle" }
PetFishRoll.OnServerInvoke = function(player)
	if ownsPet(player, "ButterDuck") then return { egg = true, already = true } end -- already have the duck
	fishCatches[player] = (fishCatches[player] or 0) + 1
	local n = fishCatches[player]
	local eggChance = math.min(1, 0.25 + (n - 1) * 0.11) -- 0.25 at catch 1 -> ramps to 1.0 by catch ~8
	local gotEgg = (n >= 8) or (math.random() < eggChance) -- pity: guaranteed by catch 8
	if gotEgg then
		fishEggReady[player] = true -- the claim gate (above) now allows ButterDuck
		print("[Pet] "..player.Name.." reeled in -> caught the EGG (catch "..n..")")
		return { egg = true, catch = n }
	else
		local junk = FISH_JUNK[math.random(1, #FISH_JUNK)]
		print(string.format("[Pet] %s reeled in -> caught: %s (catch %d, egg chance now %d%%)", player.Name, junk, n, math.floor(eggChance * 100)))
		return { egg = false, junk = junk, catch = n, chance = math.floor(eggChance * 100) }
	end
end

-- ===== INVENTORY: EQUIP / UNEQUIP (one at a time) =====
PetEquipEvent.OnServerEvent:Connect(function(player, petId)
	if petId == false or petId == nil then
		_G.playerEquippedPet[player] = nil
		print("[PetInv] unequipped (none) for "..player.Name)
	else
		if not ownsPet(player, petId) then return end -- can only equip what you own
		_G.playerEquippedPet[player] = petId
		print("[PetInv] equipped "..petId)
	end
	sendState(player)     -- client spawns/despawns the follower to match
	sendInventory(player)
end)

-- ===== FREE (achievement) upgrade -- gated on the threshold being met =====
PetUpgradeEvent.OnServerEvent:Connect(function(player, petId)
	if not ownsPet(player, petId) then return end
	if not canUpgrade(player, petId) then
		print("[PetInv] "..tostring(petId).." upgrade requested but threshold NOT met")
		return
	end
	levelUp(player, petId, "achievement")
end)

-- ===== FLIGHT-ACHIEVEMENT progress accumulation (per EQUIPPED pet). Cosmetic: only feeds the level gate;
-- never touches flight/gas/coins. The client reads the flight stats (peak height + airtime) and reports. =====
PetProgressEvent.OnServerEvent:Connect(function(player, petId, peakHeight, addTime)
	if not ownsPet(player, petId) then return end
	if _G.playerEquippedPet[player] ~= petId then return end -- only the equipped pet accrues progress
	local d = getPetData(player, petId)
	peakHeight = tonumber(peakHeight) or 0; addTime = tonumber(addTime) or 0
	if peakHeight > d.height then d.height = peakHeight end
	if addTime > 0 and addTime <= 30 then d.time = d.time + addTime end -- clamp per tick (sanity)
	local nl = nextTier(player, petId)
	local avail = canUpgrade(player, petId)
	print(string.format("[PetInv] %s flight progress: height=%d time=%d -> tier %s available: %s",
		petId, math.floor(d.height), math.floor(d.time), tostring(nl or "max"), avail and "yes" or "no"))
	-- only re-push the inventory GUI when upgrade-availability actually CHANGES (avoids per-tick resend spam)
	upgradeReady[player] = upgradeReady[player] or {}
	if upgradeReady[player][petId] ~= avail then upgradeReady[player][petId] = avail; sendInventory(player) end
end)

-- ===== ROBUX path: client declares which pet it's upgrading, THEN prompts the Developer Product. =====
PetPendingUpgrade.OnServerEvent:Connect(function(player, petId)
	if ownsPet(player, petId) then pendingRobuxPet[player.UserId] = petId end
end)
-- Called by PlayerStats' single MarketplaceService.ProcessReceipt for the pet-upgrade product. Gated behind
-- the receipt -- a real purchase is required to grant the level (never faked).
_G.petsHandleReceipt = function(player, productId)
	if PET_UPGRADE_PRODUCT_ID == 0 or productId ~= PET_UPGRADE_PRODUCT_ID then return false end -- not ours / stub
	local petId = pendingRobuxPet[player.UserId]; pendingRobuxPet[player.UserId] = nil
	if not (petId and ownsPet(player, petId)) then return false end
	return levelUp(player, petId, "robux")
end

-- ===== QUEST DISCOVERY: the client fires this when the player LANDS on a pet's island. Records it
-- (persisted by PlayerStats), so the quest shows in the inventory's quests panel permanently. =====
PetQuestDiscovered.OnServerEvent:Connect(function(player, petId)
	local def = PETS[petId]; if not def then return end
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	if _G.playerDiscoveredQuests[player][petId] then return end -- already discovered (idempotent)
	_G.playerDiscoveredQuests[player][petId] = true
	print("[PetInv] quest discovered: "..petId.." on "..(def.islandName or "?"))
	sendInventory(player) -- the quest now appears in the player's quests panel
end)

Players.PlayerRemoving:Connect(function(player)
	piecesFound[player] = nil -- ownership/equipped/discovered clears are handled by PlayerStats (after it saves)
	pendingRobuxPet[player.UserId] = nil
	upgradeReady[player] = nil
	fishCatches[player] = nil; fishEggReady[player] = nil -- fishing pity is session-only (not persisted)
end)

print("[Pet] PetSystem ready (cosmetic-only)")
