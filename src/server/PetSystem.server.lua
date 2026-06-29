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
		displayName  = "Broccoli Bunny",
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
	-- PET #5: BURRITO ARMADILLO on Burrito Barrens (Island 13). "Dig for buried treasure" quest: grab a SHOVEL
	-- at ShovelSpot -> a HOT/COLD meter guides you to the buried egg -> DIG (hold/tap minigame) at dig spots ->
	-- DigSpot1-4 are DECOYS (junk), BuriedEggSpot is the REAL one (the armadillo egg) -> hatch. NO pieces + NO
	-- egg marker (the egg appears where dug). Markers = the shovel spot + 4 decoy dig spots + the buried egg spot.
	-- The real-dig completion is server-gated (PetDigEvent below sets digEggReady) so the claim can't be faked.
	BurritoArmadillo = {
		displayName  = "Burrito Armadillo",
		islandName   = "Burrito Barrens",
		questDesc    = "Grab a shovel and dig up the buried armadillo egg - use the hot/cold meter to find it",
		questType    = "dig",
		questUnit    = "digs",
		islandPrefix = "Island_13_",         -- Burrito Barrens
		pieceMarkers = {},                    -- dig has no collectible pieces
		-- eggMarker = nil: the unearthed egg appears at the dug spot (not auto-revealed at a marker)
		extraMarkers = { shovel = "ShovelSpot", dig1 = "DigSpot1", dig2 = "DigSpot2", dig3 = "DigSpot3", dig4 = "DigSpot4", dig5 = "DigSpot5", buriedegg = "BuriedEggSpot" },
		maxLevel     = 3,
		tiers = {
			[2] = { height = 22000, time = 200 },
			[3] = { height = 37000, time = 650 },
		},
	},
	-- ===== SEASONAL PETS (Community Garden rewards) -- NO island quest: they are GRANTED by the garden harvest
	-- (Summer->Sunflower Bee, Autumn->Maple Fox, Winter->Frost Penguin, Spring->Blossom Bunny). questType="seasonal"
	-- + no islandPrefix -> the island marker scan skips them; pieceMarkers={} keeps the generic state/inventory happy.
	SunflowerBee = {
		displayName = "Sunflower Bee", islandName = "Community Garden", questType = "seasonal", season = "Summer",
		questDesc = "Earned from the Summer Community Garden harvest", pieceMarkers = {},
		maxLevel = 3, tiers = { [2] = { height = 1500, time = 120 }, [3] = { height = 7000, time = 400 } },
	},
	MapleFox = {
		displayName = "Maple Fox", islandName = "Community Garden", questType = "seasonal", season = "Autumn",
		questDesc = "Earned from the Autumn Community Garden harvest", pieceMarkers = {},
		maxLevel = 3, tiers = { [2] = { height = 1500, time = 120 }, [3] = { height = 7000, time = 400 } },
	},
	FrostPenguin = {
		displayName = "Frost Penguin", islandName = "Community Garden", questType = "seasonal", season = "Winter",
		questDesc = "Earned from the Winter Community Garden harvest", pieceMarkers = {},
		maxLevel = 3, tiers = { [2] = { height = 1500, time = 120 }, [3] = { height = 7000, time = 400 } },
	},
	BlossomBunny = {
		displayName = "Blossom Bunny", islandName = "Community Garden", questType = "seasonal", season = "Spring",
		questDesc = "Earned from the Spring Community Garden harvest", pieceMarkers = {},
		maxLevel = 3, tiers = { [2] = { height = 1500, time = 120 }, [3] = { height = 7000, time = 400 } },
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
local PetDigEvent = getOrCreateRemote("PetDigEvent")                  -- c->s: (petId) player dug the REAL buried-egg spot -> server unlocks the claim
local PetRareEvent = getOrCreateRemote("PetRareEvent")                -- s->c: (petId, rareName) a RARE hatched -> client plays the fanfare
local PetEquipBroadcast = getOrCreateRemote("PetEquipBroadcast")      -- s->c (ALL): a player's equipped-pet info {userId,petId,level,isRare,variant} -> RemotePets renders OTHER players' followers
-- ===== STAGE 3 TRADE remotes (client sends INTENTS only; the server owns + validates everything) =====
local PetTradeRequest = getOrCreateRemote("PetTradeRequestEvent")     -- c->s: (targetUserId) ask to trade
local PetTradeRespond = getOrCreateRemote("PetTradeRespondEvent")     -- c->s: (accept:bool) answer a request
local PetTradeOffer   = getOrCreateRemote("PetTradeOfferEvent")       -- c->s: (petId, add:bool) add/remove a pet from your offer
local PetTradeConfirm = getOrCreateRemote("PetTradeConfirmEvent")     -- c->s: () lock in your current offer
local PetTradeCancel  = getOrCreateRemote("PetTradeCancelEvent")      -- c->s: () cancel the trade
local PetTradeState   = getOrCreateRemote("PetTradeStateEvent")       -- s->c: (perspective state) live trade window
local PetTradePrompt  = getOrCreateRemote("PetTradeRequestPromptEvent") -- s->c: (fromUserId, fromName) incoming request popup
local fishCatches  = {}  -- [player] = number of successful reel-ins (drives the pity ramp; session-only, not saved)
local fishEggReady = {}  -- [player] = true once the SERVER has rolled the EGG (gates the ButterDuck claim, anti-cheat)
local digEggReady  = {}  -- [player] = true once the player DUG the real buried egg (gates the BurritoArmadillo claim, anti-cheat)
-- (The BurritoArmadillo "Armadillo Trail" uses CLIENT-BUILT low-poly part mounds dug one-at-a-time -- no server
-- terrain. The only server piece is the claim gate above + PetDigEvent below.)
_G.playerDiscoveredQuests = _G.playerDiscoveredQuests or {}           -- [player] = { [petId]=true } (persisted by PlayerStats)
_G.playerEverCompletedQuests = _G.playerEverCompletedQuests or {}     -- [player] = { [petId]=true } PERMANENT "ever completed quest X" (persisted) -- gates the first-time-only rare roll, separate from ownership
_G.playerEquippedPet = _G.playerEquippedPet or {}                      -- [player] = petId (persisted by PlayerStats)
local pendingRobuxPet = {}                                             -- [userId] = petId awaiting a Robux receipt
local upgradeReady    = {}                                            -- [player][petId] = last canUpgrade (to avoid resend spam)
-- \xE2\x9A\xA0 REPLACE BEFORE LAUNCH: placeholder pet-skip Developer Product ID. The Robux "Skip" fills the current
-- level's remaining XP (one level up), gated behind ProcessReceipt. This is a PLACEHOLDER id -- create the real
-- Developer Product(s) and set the id here (and the matching id in PetFollow.client.lua). Until replaced, real
-- purchases won't grant (the prompt errors harmlessly); test accounts use the instant test-skip path instead.
-- (Price scales with level in the UI label; at launch, map level brackets to per-bracket product IDs here.)
local PET_UPGRADE_PRODUCT_ID = 123456789 -- \xE2\x9A\xA0 (legacy, no longer used -- superseded by the TIER-SKIP products below)

-- \xE2\x9A\xA0 REPLACE BEFORE LAUNCH: placeholder TIER-SKIP Developer Product IDs (4 prices). Each jumps the pet to
-- the FIRST level of the NEXT tier. Tiers: Common 1-5, Uncommon 6-10, Rare 11-15, Epic 16-20, Legendary 21-25.
-- SERVER-AUTHORITATIVE: a receipt only applies if the pet is actually in that product's SOURCE tier (srcMin..
-- srcMax) -- so a cheap product can NEVER be used to jump a higher tier. The matching ids live in
-- PetFollow.client.lua (PET_SKIP_PRODUCTS). REPLACE ALL FOUR with the real Developer Product IDs before launch.
local PET_SKIP_PRODUCTS = {
	[123456701] = { target = 6,  srcMin = 1,  srcMax = 5,  price = 49,  to = "Uncommon"  }, -- Common  -> Uncommon
	[123456702] = { target = 11, srcMin = 6,  srcMax = 10, price = 99,  to = "Rare"      }, -- Uncommon-> Rare
	[123456703] = { target = 16, srcMin = 11, srcMax = 15, price = 299, to = "Epic"      }, -- Rare    -> Epic
	[123456704] = { target = 21, srcMin = 16, srcMax = 20, price = 599, to = "Legendary" }, -- Epic    -> Legendary
}

-- ============================================================================================
-- PET MODEL TEMPLATES (all 5 pets). CSG/UnionAsync is SERVER-ONLY, so each pet's BODY+HEAD (+ears/neck/
-- shell ridges that share its colour) is FUSED into ONE smooth gap-free solid HERE at startup, stored in
-- ReplicatedStorage, and the client CLONES it for the follow loop. Heavy overlap -> seamless fusion (no
-- "balls with gaps"). Separate parts (eyes + differently-coloured limbs/bills) keep their own colours and
-- are role-named so the client animator drives them: Eye/Highlight blink, Leg gait, Tail wiggle, everything
-- else rides the fused body. Cosmetic only (Anchored, Massless, CanCollide=false). Local frame: +X = front.
-- ============================================================================================
local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local SMOOTH = Enum.SurfaceType.Smooth
local function flagPart(p)
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic -- matte plastic toy look (no gloss)
	-- Force EVERY face Smooth: new Parts default TopSurface=Studs / BottomSurface=Inlet, which render the
	-- Lego-stud/notch texture (very visible on cylinders). Smooth on all 6 faces -> clean matte plastic, no notches.
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
	return p
end
-- make a part (sizes/positions are ALREADY scaled by the caller's P closure)
local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
	local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
	p.CFrame = cf; flagPart(p); p.Parent = model; return p
end
-- FUSE a list of overlapping source parts into ONE union named `name`, coloured `color`. Returns union, err.
-- On CSG failure it keeps the (unfused) parts renamed so the client still treats them as the body (pet still appears).
local function fuse(model, src, name, color)
	local first = table.remove(src, 1)
	local ok, u = pcall(function() return first:UnionAsync(src) end)
	if ok and typeof(u) == "Instance" then
		first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
		flagPart(u); u.Name = name; u.UsePartColor = true; u.Color = color
		pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
		pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
		pcall(function() u.SmoothingAngle = 60 end) -- soft satin shading across the fused solid
		u.Parent = model
		return u, nil
	else
		table.insert(src, 1, first)
		for _, p in ipairs(src) do p.Name = name.."Chunk" end -- unfused fallback -> client role = body
		return nil, tostring(u)
	end
end
local function newRoot(model)
	local r = mkPart(model, "Root", BAL, 0.4, 0.4, 0.4, Color3.new(1,1,1), 0, 0, 0); r.Transparency = 1; model.PrimaryPart = r; return r
end
-- WELD a cosmetic part firmly to a target (the fused head/body). Returns the part for chaining. In this system
-- every part is also anchored + code-positioned relative to the root each frame (that is what actually keeps
-- parts glued with no gap), so the weld is a belt-and-suspenders bind that also documents the parent.
local function weldTo(part, target)
	if part and target then
		local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = target; w.Part1 = part; w.Parent = part
	end
	return part
end
-- THE STANDARD EYES (the armadillo's EXACT construction -- reused on EVERY pet so they all have the same good
-- eyes). Each eye is a big FLAT black disc (a thin cylinder -> flat, never a bulging sphere) whose BACK embeds
-- into the face surface and whose FRONT sits just proud (no gap, no float), plus a small FLAT white sparkle disc
-- on the upper-front. A cylinder's circular faces point along its LOCAL X, so an un-rotated thin cylinder IS a
-- disc facing +X (the front). `fx` = eye CENTRE -- set it per pet so the disc backs into THAT pet's face surface
-- (centre ~ surface_x, so back ~0.11 in / front ~0.11 proud). `fy` height, `fz` lateral spread. Named
-- Eye/Highlight so the client blink squashes them together.
local EYE_DIA = 0.82  -- ONE standard eye size for the whole game (the armadillo's eye)
local function eyes(P, fx, fy, fz)
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = fz * sgn
		P("Eye", CYL, 0.22, EYE_DIA, EYE_DIA, Color3.fromRGB(16,16,20), fx, fy, zc)                        -- big flat matte-black disc (back embedded, front proud)
		P("Highlight", CYL, 0.12, EYE_DIA*0.34, EYE_DIA*0.34, Color3.fromRGB(255,255,255), fx + 0.16, fy + EYE_DIA*0.22, zc + EYE_DIA*0.16) -- flat white sparkle on the eye
	end
end
-- a CLEAN single-shape mouth: ONE thin rounded bar laid horizontally across the +X face (a cylinder rotated so
-- its length runs along Z). `fx,fy` = where it sits on the face, `w` = mouth width. (Ducks DON'T call this -- the
-- bill IS the mouth.)
local function mouth(P, fx, fy, w)
	P("Mouth", CYL, w, 0.18, 0.18, Color3.fromRGB(48,32,30), fx, fy, 0, CFrame.Angles(0, math.rad(90), 0))
end

-- ROUNDED-CUBE BODY (Pet-Sim-99 chunky style): appends a fillet/Minkowski box -- 3 cross slabs (the flat
-- faces) + 8 corner spheres + 12 edge cylinders -- to `src`, centred at (cx,cy,cz), dims W(width Z) x
-- H(height Y) x D(depth X) with fillet radius R. Server-unioning `src` then yields ONE cube with smooth
-- curved edges (gap-free). P is the builder's scaling closure. +X = front.
local function roundedCubeInto(src, P, cx, cy, cz, W, H, D, R, color)
	local iW, iH, iD = W - 2*R, H - 2*R, D - 2*R
	local hW, hH, hD = iW/2, iH/2, iD/2
	local dd = 2*R
	local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = P("b", sh, sx,sy,sz, color, cx+x, cy+y, cz+z, rot) end
	a(BLK, D, iH, iW, 0,0,0)   -- 3 cross slabs = the flat faces
	a(BLK, iD, H, iW, 0,0,0)
	a(BLK, iD, iH, W, 0,0,0)
	for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
		a(BAL, dd,dd,dd, c[1]*hD, c[2]*hH, c[3]*hW)  -- 8 corner spheres (rounds the corners)
	end
	for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do  -- 12 edge cylinders (rounds the edges)
		a(CYL, iD, dd, dd, 0, e[1]*hH, e[2]*hW)
		a(CYL, iH, dd, dd, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0,0,math.rad(90)))
		a(CYL, iW, dd, dd, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0,math.rad(90),0))
	end
end
-- shared chunky body dims (one big rounded cube ~1:1:0.9 -- the signature look) + display scale
local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

-- 1) BROCCOLI BUNNY (island 2): rounded-cube green body (+feet/eyes unchanged). Attach tall green CYLINDER ears
-- with pink inner-ears (wide apart, tilted out, welded + deeply embedded), a flatter pink nose, a black "w"
-- mouth, 3 whiskers per side, lighter-green cheeks, a fluffy white tail, dark-green floret bumps on top.
local function buildBroccoliBunny()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "BroccoliBunnyTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local GREEN, FLOR, PINK, PINKI, WHITE = Color3.fromRGB(139,195,74), Color3.fromRGB(46,139,58), Color3.fromRGB(240,170,180), Color3.fromRGB(252,205,215), Color3.fromRGB(245,245,245)
	local LGREEN, BLKM = Color3.fromRGB(176,222,116), Color3.fromRGB(20,20,24) -- lighter-green cheeks; near-black mouth/whiskers
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, GREEN)
	local body, err = fuse(m, src, "BodyUnion", GREEN)
	-- EARS: two TALL bunny ears, each = a CYLINDER capped on top with a half-sphere DOME (same colour) so the
	-- tip is ROUNDED, not flat. The cylinder + dome are UNIONED into ONE "Ear" part -- the dome is fused flush to
	-- the cylinder top (can't float) and the whole ear wiggles as one rigid unit. Green outer ear with a thinner
	-- PINK inner-ear (also cylinder + dome) on its front. Wide apart near the head corners (z=+-1.25), tilted OUT
	-- (gentle V ~13deg), bases sunk ~1 stud deep into the head AND welded to it.
	local function roundedEar(cx, cy, cz, len, dia, color, rot) -- cylinder + flush dome cap -> unioned into one "Ear"
		local up = (rot * CFrame.new(1, 0, 0)).Position -- the cylinder's length (up) axis
		local part = {
			P("b", CYL, len, dia, dia, color, cx, cy, cz, rot),                                          -- the ear shaft
			P("b", BAL, dia, dia, dia, color, cx + up.X*len*0.5, cy + up.Y*len*0.5, cz + up.Z*len*0.5),   -- dome cap on the top face (half pokes out -> rounded tip)
		}
		weldTo(fuse(m, part, "Ear", color), body) -- one rounded-top ear part (role "ear" -> wiggles as a unit), welded to the head
	end
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = 1.25 * sgn
		local rotEar = CFrame.Angles(math.rad(13) * sgn, 0, 0) * CFrame.Angles(0, 0, math.rad(90)) -- upright + outward V
		roundedEar(0.1,  2.4, zc, 3.1, 0.92, GREEN, rotEar)  -- green outer ear (rounded dome top) -- barely shorter (3.4 -> 3.1)
		roundedEar(0.42, 2.4, zc, 2.25, 0.5,  PINKI, rotEar) -- pink inner ear (rounded dome top), on the front -- barely shorter (2.5 -> 2.25)
	end
	-- VERIFY ear attachment: ears are welded to the fused head AND code-positioned relative to the root every frame
	-- AND their bases are embedded ~1 stud into the head -> three things ensuring no gap / no float.
	do
		local earLen, earCenterY, splay = 3.1, 2.4, math.rad(13)
		local earBottom = earCenterY - (earLen * 0.5) * math.cos(splay)  -- vertical reach of the tilted ear
		local embed     = ((PSH * 0.5) - earBottom) * s                  -- how deep the base sinks into the head
		print(string.format("[Pet] bunny ears: welded=yes, attached=%s, embedded depth=%.2f studs, cylinder size=%.2f tall x %.2f dia (wide apart, tilted out)",
			(embed > 0.1) and "yes" or "no", embed, earLen * s, 0.92 * s))
	end
	-- FEET: unchanged (kept exactly as before)
	P("Foot", BLK, 0.95,0.8,0.95, GREEN, 0.95,-1.55,0.78)
	P("Foot", BLK, 0.95,0.8,0.95, GREEN, 0.95,-1.55,-0.78)
	eyes(P, 1.72, 0.5, 0.62)                                        -- EYES: unchanged (the good standard eyes, kept exactly)
	-- NOSE: kept pink, but FLATTER (shallower in X) and CENTERED below the eyes
	weldTo(P("Nose", BAL, 0.45,0.52,0.72, PINK, 1.74,-0.05,0), body)
	-- MOUTH: a cute bunny "w" SMILE from thin black cylinders directly below the nose -- a short vertical philtrum
	-- + two strokes that flare UP & OUT (corners turned UP -> happy smile, the "w" flipped right-side up).
	weldTo(P("Mouth", CYL, 0.32,0.1,0.1, BLKM, 1.74,-0.42,0,    CFrame.Angles(0,0,math.rad(90))), body)
	weldTo(P("Mouth", CYL, 0.36,0.1,0.1, BLKM, 1.73,-0.5,0.18,  CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(-34))), body)
	weldTo(P("Mouth", CYL, 0.36,0.1,0.1, BLKM, 1.73,-0.5,-0.18, CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(34))), body)
	weldTo(P("Mouth", BAL, 0.15,0.15,0.15, BLKM, 1.74,-0.585,0), body) -- tiny connector bead at the junction -> closes the gap where the philtrum + the two smile strokes meet
	-- WHISKERS: three thin black cylinders on each side of the mouth, fanned (up / level / down), poking outward
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Whisker", CYL, 1.05,0.06,0.06, BLKM, 1.46,-0.2,0.92*sgn, CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(-12))), body)
		weldTo(P("Whisker", CYL, 1.14,0.06,0.06, BLKM, 1.46,-0.32,0.95*sgn, CFrame.Angles(0,math.rad(90),0)), body)
		weldTo(P("Whisker", CYL, 1.05,0.06,0.06, BLKM, 1.46,-0.44,0.92*sgn, CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(12))), body)
	end
	-- CHEEKS: small lighter-green spheres below the eyes -- SYMMETRIC (mirrored): both at the same height
	-- (y -0.18) and the same distance out from centre (z = +-0.72). No left/right offset -> equal positions.
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Cheek", BAL, 0.6,0.52,0.5, LGREEN, 1.6,-0.18,0.72*sgn), body)
	end
	P("Tail", BAL, 1.05,1.05,1.05, WHITE, -1.6,-0.35,0)          -- round fluffy white tail bump (back)
	P("Floret", BAL, 0.62,0.54,0.62, FLOR, -0.3,1.9,0)            -- dark-green floret bump on top
	P("Floret", BAL, 0.46,0.42,0.46, FLOR, 0.2,2.0,0.45)
	return m, err
end

-- 2) COCONUT CRAB (island 5): SMALL cute wide/flat rounded shell. Attach 2 scuttling claws + 6 little legs
-- (separate, animated), 2 coconut spots, big eyes set high on the shell, a small mouth.
local function buildCoconutCrabT()
	local s = PSS * 0.78  -- noticeably SMALLER -> cute little crab
	local m = Instance.new("Model"); m.Name = "CoconutCrabTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local BROWN, DARK, CLAW = Color3.fromRGB(150,72,52), Color3.fromRGB(110,52,36), Color3.fromRGB(176,92,68)
	local src = {}
	-- a wider/flatter rounded shell -> crab body (not a tall cube)
	roundedCubeInto(src, P, 0,0,0, PSW*1.05, PSH*0.72, PSD, PSR*0.95, BROWN)
	local _, err = fuse(m, src, "BodyUnion", BROWN)
	-- 2 CLAWS out the front (role claw -> scuttle), raised pincers
	for _, sgn in ipairs({1,-1}) do P("Claw", BAL, 1.2,1.0,1.05, CLAW, 1.7,-0.1,1.15*sgn) end
	-- 6 LEGS (role leg -> gait scuttle): 3 down each side, thin little legs poking out + down
	for _, sgn in ipairs({1,-1}) do
		for _, lx in ipairs({ 0.7, 0.0, -0.7 }) do
			P("Leg", BLK, 0.32,1.0,0.32, CLAW, lx,-1.05,1.55*sgn, CFrame.Angles(math.rad(22)*sgn,0,0))
		end
	end
	for _, d in ipairs({ {1.55,0.55,0.42},{1.55,0.55,-0.42} }) do P("Dot", BAL, 0.34,0.24,0.34, DARK, d[1],d[2],d[3]) end -- 2 small coconut spots
	eyes(P, 1.34, 1.18, 0.6)  -- STANDARD eyes, moved UP a little higher on the shell (more apparent)
	mouth(P, 1.5, -0.05, 0.42)
	return m, err
end

-- 3) POPCORN SHEEP (island 8): fluffy WHITE/cream wool body. Attach 4 black legs + black floppy ears, and a
-- raised BLACK FACE PATCH (face area only) carrying the standard eyes + a small snout/mouth (its own sheep face).
local function buildPopcornSheepT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "PopcornSheepTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	-- BLACK against the cream wool (legs/ears darkest); the FACE patch is a hair lighter charcoal so the
	-- standard pure-black eyes (16,16,20) still contrast and read clearly on it.
	local CREAM, BLACK, FACEBLK, SNOUT = Color3.fromRGB(252,248,228), Color3.fromRGB(26,26,30), Color3.fromRGB(46,46,52), Color3.fromRGB(64,64,72)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, CREAM)
	for _, b in ipairs({ {0.0,1.75,0.55},{0.0,1.75,-0.55},{-0.7,1.8,0.0},{0.7,1.65,0.0},{-1.55,0.6,0.0},{0.0,0.6,1.6},{0.0,0.6,-1.6} }) do
		src[#src+1] = P("b", BAL, 1.15,1.1,1.15, CREAM, b[1],b[2],b[3]) -- chunkier wool bumps that clearly read (still fused -> fluffy white body)
	end
	local _, err = fuse(m, src, "BodyUnion", CREAM)
	-- 4 dark block LEGS (role leg -> waddle), front + back pairs, embedded into the base
	P("Foot", BLK, 0.85,0.9,0.9, BLACK, 1.0,-1.7,0.78)
	P("Foot", BLK, 0.85,0.9,0.9, BLACK, 1.0,-1.7,-0.78)
	P("Foot", BLK, 0.85,0.9,0.9, BLACK, -1.0,-1.7,0.78)
	P("Foot", BLK, 0.85,0.9,0.9, BLACK, -1.0,-1.7,-0.78)
	-- black floppy ears (role ear -> wiggle), bases embedded into the head top but tops standing proud above it
	P("Ear", BAL, 0.55,0.8,0.46, BLACK, 0.55,1.78,0.95)
	P("Ear", BAL, 0.55,0.8,0.46, BLACK, 0.55,1.78,-0.95)
	-- BLACK-FACED SHEEP: a raised BLACK FACE PATCH covering JUST the face area (not the whole front) and
	-- PROTRUDING from the white fluffy body. The standard eyes + a small snout/mouth sit ON this black face.
	-- black face patch: ~2x the frontal AREA (taller + wider: 1.75x1.85 -> 2.5x2.65) so it covers much more
	-- black around the eyes. SAME depth out: X-size (1.25) and centre x (1.45) are UNCHANGED -> the front pole
	-- still sits at x2.075, so it does NOT protrude any further than before.
	local facePatch = P("FacePatch", BAL, 1.25,2.5,2.65, FACEBLK, 1.45,0.05,0)
	-- area dims are Y(height) x Z(width): old 1.75x1.85 = 3.24 -> new 2.50x2.65 = 6.63 (~2.05x). X(depth) kept 1.25.
	local _oldArea, _newArea = 1.75*1.85, 2.50*2.65
	print(string.format("[Pet] sheep black face resized from 1.25x1.75x1.85 to 1.25x2.50x2.65 (face area %.2f -> %.2f, ~%.2fx); actual scaled Size now = %s",
		_oldArea, _newArea, _newArea/_oldArea, tostring(facePatch.Size)))
	P("Snout", BAL, 0.9,0.85,1.0, SNOUT, 2.0,-0.5,0)              -- small protruding snout on the black face
	eyes(P, 1.9, 0.45, 0.5)                                        -- SAME good eyes, pushed IN 0.1 (fx 2.0 -> 1.9) so the disc embeds FLUSH into the face patch with no gap, like the duck
	P("Nose", BAL, 0.34,0.26,0.46, Color3.fromRGB(16,16,20), 2.32,-0.45,0) -- small nose on the snout tip
	mouth(P, 2.18, -0.82, 0.34)                                    -- small clean mouth under the snout (not a smiley)
	return m, err
end

-- 4) BUTTER DUCK (island 10): rounded-cube golden body (+upturned tail bump, fused). Attach 2 flapping wings
-- (separate, animated), a flat orange bill (= the mouth, NO smile), 2 webbed feet, big eyes.
local function buildButterDuckT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "ButterDuckTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local BUTTER, BILL = Color3.fromRGB(248,214,96), Color3.fromRGB(244,150,40)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BUTTER)
	src[#src+1] = P("b", BAL, 0.9,0.9,1.0, BUTTER, -1.6,0.5,0, CFrame.Angles(0,0,math.rad(28)))  -- upturned tail bump (fused)
	local _, err = fuse(m, src, "BodyUnion", BUTTER)
	-- 2 WINGS: SEPARATE flat-ish parts (role wing -> flap), inner edge embedded into the body sides
	P("Wing", BLK, 1.3,0.45,1.5, BUTTER, -0.1,0.25,1.55)
	P("Wing", BLK, 1.3,0.45,1.5, BUTTER, -0.1,0.25,-1.55)
	P("Bill", BLK, 0.55,0.65,1.25, BILL, 1.85,-0.05,0)           -- flat orange bill OUT on the front (this IS the mouth -> no smile)
	P("Foot", BLK, 0.85,0.7,1.05, BILL, 0.85,-1.62,0.72)        -- orange webbed block feet (role leg -> paddle)
	P("Foot", BLK, 0.85,0.7,1.05, BILL, 0.85,-1.62,-0.72)
	eyes(P, 1.72, 0.6, 0.6)  -- STANDARD eyes (fx=1.72 -> black disc backs into the body face at x1.7, front proud -> black eyes clearly visible). Bill is the mouth -> no smile.
	return m, err
end

-- 5) BURRITO ARMADILLO (island 13): rounded-cube tan body (+BANDED shell ridges + head bump, fused). Attach 4
-- waddling legs + a wiggling tail (separate, animated), a tiny nose, big eyes, a small mouth.
local function buildBurritoArmadilloT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "BurritoArmadilloTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local TAN, SNT, BAND = Color3.fromRGB(196,150,100), Color3.fromRGB(150,96,56), Color3.fromRGB(168,124,80)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, TAN)
	for _, bx in ipairs({ -0.8,-0.2,0.4 }) do src[#src+1] = P("b", BAL, 0.55,0.9,2.7, BAND, bx,1.95,0) end -- RAISED banded shell ridges across the top (fused)
	src[#src+1] = P("b", BAL, 1.4,1.3,1.5, TAN, 1.82,0.0,0)         -- snout / head bump OUT at the front (fused)
	local _, err = fuse(m, src, "BodyUnion", TAN)
	-- 4 LEGS (role leg -> waddle), front + back pairs, embedded into the base
	P("Foot", BLK, 0.8,0.85,0.85, SNT, 1.0,-1.65,0.82)
	P("Foot", BLK, 0.8,0.85,0.85, SNT, 1.0,-1.65,-0.82)
	P("Foot", BLK, 0.8,0.85,0.85, SNT, -1.0,-1.65,0.82)
	P("Foot", BLK, 0.8,0.85,0.85, SNT, -1.0,-1.65,-0.82)
	-- tapering TAIL out the back (role tail -> wiggle)
	P("Tail", BAL, 1.5,0.5,0.5, SNT, -2.1,-0.45,0, CFrame.Angles(0,0,math.rad(-12)))
	P("Nose", BAL, 0.34,0.28,0.34, SNT, 2.4,-0.22,0)             -- nose on the head bump front
	eyes(P, 1.72, 0.95, 0.5)                                        -- eyes embedded FLUSH into the FLAT cube body face (fx 1.72, exactly like the duck -> no gap), raised to sit on the body above the snout bump
	mouth(P, 2.18, -0.6, 0.32)                                      -- TUCKED into the snout (pushed in + down -> flusher, sits in the snout area)
	return m, err
end

-- (legacy single-template builder kept below but UNUSED -- the 5-pet loop above replaces it)
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

-- ===== SEASONAL PETS (Community Garden rewards) -- SAME rounded-cube union style/scale as the pets above
-- (roundedCubeInto -> fuse body, then welded features), reusing the shared eyes()/mouth() so they're equally cute.
-- SUMMER: SUNFLOWER BEE -- yellow striped body, white wings, a ring of sunflower petals round the face, antennae.
local function buildSunflowerBeeT()
	local s = PSS * 0.92
	local m = Instance.new("Model"); m.Name = "SunflowerBeeTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local YEL, BLKC, WHITE, PET = Color3.fromRGB(250,205,60), Color3.fromRGB(28,28,32), Color3.fromRGB(248,248,245), Color3.fromRGB(245,180,40)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, YEL); local body, err = fuse(m, src, "BodyUnion", YEL)
	for _, xo in ipairs({ -0.9, 0.0, 0.9 }) do weldTo(P("Stripe", BLK, 0.42, PSH*0.98, PSD*0.98, BLKC, xo, 0, 0), body) end -- black stripes
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Wing", BLK, 0.18, 1.7, 1.3, WHITE, -0.3, 1.5, 1.2*sgn, CFrame.Angles(math.rad(22*sgn),0,0)), body) end -- white wings (flap)
	for i = 0, 9 do local a = i*(2*math.pi/10); weldTo(P("Petal", BAL, 0.32, 0.5, 1.15, PET, 1.5, math.cos(a)*1.5, math.sin(a)*1.5, CFrame.Angles(a,0,0)), body) end -- sunflower-petal collar
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Antenna", CYL, 1.0, 0.1, 0.1, BLKC, 1.0, 2.4, 0.35*sgn, CFrame.Angles(0,0,math.rad(22))), body)
		weldTo(P("AntTip", BAL, 0.3,0.3,0.3, BLKC, 1.4, 2.85, 0.35*sgn), body)
	end
	eyes(P, 1.72, 0.45, 0.6); mouth(P, 1.78, -0.35, 0.62)
	return m, err
end
-- AUTUMN: MAPLE FOX -- orange body, pointy ears (white inner), white snout/cheeks, bushy white-tipped tail.
local function buildMapleFoxT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "MapleFoxTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local ORG, DORG, WHITE, BLKC = Color3.fromRGB(222,120,52), Color3.fromRGB(190,92,40), Color3.fromRGB(245,242,235), Color3.fromRGB(28,24,26)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, ORG); local body, err = fuse(m, src, "BodyUnion", ORG)
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = 1.0*sgn
		weldTo(P("Ear", BLK, 0.5, 1.5, 1.0, ORG, 0.2, 2.35, zc, CFrame.Angles(math.rad(16*sgn),0,0)), body)   -- pointy outer ear
		weldTo(P("Ear", BAL, 0.42, 0.8, 0.55, DORG, 0.3, 3.05, zc), body)                                       -- darker pointed tip
		weldTo(P("Ear", BLK, 0.3, 0.95, 0.5, WHITE, 0.42, 2.35, zc, CFrame.Angles(math.rad(16*sgn),0,0)), body) -- white inner
	end
	weldTo(P("Snout", BAL, 0.6, 0.7, 0.95, WHITE, 1.5, -0.4, 0), body)
	weldTo(P("Nose", BAL, 0.34,0.3,0.44, BLKC, 1.98, -0.3, 0), body)
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Cheek", BAL, 0.5,0.55,0.5, WHITE, 1.55, -0.12, 0.72*sgn), body) end
	P("Tail", BAL, 1.3,1.0,1.0, ORG, -1.7,-0.1,0); P("Tail", BAL, 0.85,0.85,0.85, WHITE, -2.45,0.1,0) -- bushy white-tipped tail
	P("Foot", BLK, 0.9,0.7,0.9, DORG, 0.95,-1.6,0.8); P("Foot", BLK, 0.9,0.7,0.9, DORG, 0.95,-1.6,-0.8)
	eyes(P, 1.72, 0.5, 0.62); mouth(P, 1.7, -0.7, 0.5)
	return m, err
end
-- WINTER: FROST PENGUIN -- navy body, white belly, orange beak/feet, side flippers, ice crystals on top.
local function buildFrostPenguinT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "FrostPenguinTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local NAVY, BELLY, ORG, ICE = Color3.fromRGB(38,46,74), Color3.fromRGB(244,246,250), Color3.fromRGB(240,150,40), Color3.fromRGB(180,225,245)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, NAVY); local body, err = fuse(m, src, "BodyUnion", NAVY)
	weldTo(P("Belly", BLK, 0.3, 2.5, 2.3, BELLY, 1.55, -0.3, 0), body)            -- white belly (flat front)
	weldTo(P("Beak", BAL, 0.75, 0.5, 0.7, ORG, 1.95, 0.05, 0), body)             -- orange beak (the mouth)
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Wing", BLK, 0.9, 1.9, 0.26, NAVY, -0.1, 0.1, 1.85*sgn, CFrame.Angles(math.rad(12*sgn),0,0)), body) end -- flippers (flap)
	P("Foot", BLK, 1.1,0.45,0.8, ORG, 0.9,-1.7,0.7); P("Foot", BLK, 1.1,0.45,0.8, ORG, 0.9,-1.7,-0.7)
	for _, d in ipairs({ {0,2.25,0,0.6}, {0.5,2.1,0.6,0.42}, {-0.5,2.1,-0.55,0.42} }) do
		weldTo(P("Crystal", BLK, d[4],d[4],d[4], ICE, d[1], d[2], d[3], CFrame.Angles(0,math.rad(45),math.rad(45))), body) -- ice crystals on top
	end
	eyes(P, 1.72, 0.6, 0.5)
	return m, err
end
-- SPRING: BLOSSOM BUNNY -- pale-green body, long ears (pink inner), a flower crown, pink cheeks/nose, fluffy tail.
local function buildBlossomBunnyT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "BlossomBunnyTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local PGREEN, PINK, WHITE, FLPINK, FLWHT, YEL = Color3.fromRGB(186,224,150), Color3.fromRGB(240,150,180), Color3.fromRGB(248,248,245), Color3.fromRGB(245,160,195), Color3.fromRGB(250,248,250), Color3.fromRGB(250,215,90)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, PGREEN); local body, err = fuse(m, src, "BodyUnion", PGREEN)
	local function ear(cx,cy,cz,len,dia,color,rot) -- cylinder + flush dome cap -> one rounded "Ear" (wiggles)
		local up = (rot * CFrame.new(1,0,0)).Position
		local part = { P("b",CYL,len,dia,dia,color,cx,cy,cz,rot), P("b",BAL,dia,dia,dia,color,cx+up.X*len*0.5,cy+up.Y*len*0.5,cz+up.Z*len*0.5) }
		weldTo(fuse(m, part, "Ear", color), body)
	end
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = 1.1*sgn; local rot = CFrame.Angles(math.rad(10*sgn),0,0) * CFrame.Angles(0,0,math.rad(90))
		ear(0.1, 2.9, zc, 3.9, 0.85, PGREEN, rot)  -- long ear
		ear(0.42, 2.9, zc, 3.0, 0.46, FLPINK, rot) -- pink inner
	end
	for i = -2, 2 do -- flower crown: a row of small flowers across the top-front of the head
		local zz = i * 0.66; local col = (i % 2 == 0) and FLPINK or FLWHT
		weldTo(P("Flower", BAL, 0.42,0.42,0.42, col, 0.35, 2.05, zz), body)
		weldTo(P("FlowerCtr", BAL, 0.2,0.2,0.2, YEL, 0.52, 2.1, zz), body)
	end
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Cheek", BAL, 0.5,0.45,0.45, PINK, 1.6,-0.15,0.7*sgn), body) end
	weldTo(P("Nose", BAL, 0.34,0.32,0.46, PINK, 1.78,-0.05,0), body)
	P("Tail", BAL, 1.0,1.0,1.0, WHITE, -1.65,-0.3,0)
	P("Foot", BLK, 0.9,0.75,0.9, PGREEN, 0.95,-1.55,0.78); P("Foot", BLK, 0.9,0.75,0.9, PGREEN, 0.95,-1.55,-0.78)
	eyes(P, 1.72, 0.5, 0.62); mouth(P, 1.74, -0.42, 0.4)
	return m, err
end

-- Build ALL fused pet templates at startup, apply a slight toy gloss, and store each in ReplicatedStorage
-- (the client clones them). Each logs its own union result. (buildPetTemplate above is legacy/unused.)
local PET_TEMPLATE_BUILDERS = {
	{ id = "BroccoliPet",      fn = buildBroccoliBunny },
	{ id = "CoconutCrab",      fn = buildCoconutCrabT },
	{ id = "PopcornSheep",     fn = buildPopcornSheepT },
	{ id = "ButterDuck",       fn = buildButterDuckT },
	{ id = "BurritoArmadillo", fn = buildBurritoArmadilloT },
	{ id = "SunflowerBee",     fn = buildSunflowerBeeT,     seasonal = true, name = "Sunflower Bee" },
	{ id = "MapleFox",         fn = buildMapleFoxT,         seasonal = true, name = "Maple Fox" },
	{ id = "FrostPenguin",     fn = buildFrostPenguinT,     seasonal = true, name = "Frost Penguin" },
	{ id = "BlossomBunny",     fn = buildBlossomBunnyT,     seasonal = true, name = "Blossom Bunny" },
}
task.spawn(function()
	local totalSmoothed = 0
	for _, b in ipairs(PET_TEMPLATE_BUILDERS) do
		local ok, model, err = pcall(b.fn)
		if ok and model then
			-- (no gloss pass: all pet parts are matte Enum.Material.Plastic + all surfaces Smooth via flagPart ->
			-- clean matte plastic, no Lego-stud/notch texture)
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end
			totalSmoothed = totalSmoothed + n
			model.Parent = RS -- replicate the finished template to clients
			if err then
				warn("[Pet][UNION] "..b.id.." union FAILED ("..tostring(err)..") -- template ready with UNFUSED body (still appears)")
			else
				print("[Pet][UNION] "..b.id.." rounded-cube body SUCCESS ("..n.." parts -> matte Plastic + Smooth surfaces)")
			end
			if b.seasonal then print("[Pet] seasonal "..b.name.." built ("..(err and "union FAILED" or "union ok")..")") end
		else
			warn("[Pet][UNION] "..b.id.." template build error: "..tostring(model or err))
		end
	end
	print("[Pet] surface sweep: "..totalSmoothed.." pet parts set to clean matte Plastic + all faces Smooth (no stud/notch texture)")
end)

-- ===== STATE HELPERS =====
-- ownsPet checks a STORAGE KEY exactly (the unit of equip/level/trade). A key is either a species id ("ButterDuck",
-- the NORMAL variant) or a species id + the rare suffix ("ButterDuck#R", the RARE variant). Normal pets keep key==petId
-- so all existing single-pet code is unchanged; rares get the suffix so a normal AND a rare of one species can coexist.
local function ownsPet(player, key)
	local op = _G.playerOwnedPets[player]
	return op ~= nil and op[key] ~= nil -- value may be `true` (legacy) or a {level,height,time,count,rare} table
end
local RARE_SUFFIX = "#R"
local function variantKey(petId, rare) return rare and (petId .. RARE_SUFFIX) or petId end -- (species,variant) -> storage key
local function speciesOf(key) if type(key) ~= "string" then return key end return (key:gsub(RARE_SUFFIX .. "$", "")) end -- storage key -> species id
-- owns ANY variant (normal OR rare) of a species -- used by quest gates / "do you have this pet at all" checks.
local function ownsSpecies(player, petId)
	return ownsPet(player, petId) or ownsPet(player, petId .. RARE_SUFFIX)
end
-- the storage keys a player owns for a species (0..2: the normal slot and/or the rare slot)
local function ownedKeysOf(player, petId)
	local t = {}
	if ownsPet(player, petId) then t[#t + 1] = petId end
	if ownsPet(player, petId .. RARE_SUFFIX) then t[#t + 1] = petId .. RARE_SUFFIX end
	return t
end

local function foundCount(player, petId)
	local s = piecesFound[player] and piecesFound[player][petId]
	if not s then return 0 end
	local n = 0; for _ in pairs(s) do n = n + 1 end; return n
end

-- RE-DOABLE QUESTS: a pet quest is DOABLE AGAIN whenever the player currently owns ZERO of that species
-- (e.g. they traded their only one away). Owning >=1 keeps it completed/locked -> no farming duplicates.
-- everCompleted is a PERMANENT flag used ONLY to gate the rare roll (see PetClaimEvent); it does NOT lock the quest.
local function questAvailable(player, petId)
	local owns = ownsSpecies(player, petId) -- owning ANY variant (normal or rare) locks the quest
	local ever = (_G.playerEverCompletedQuests[player] or {})[petId] == true
	local available = not owns
	print(string.format("[PetQuest] %s quest %s availability: ownsCount=%d, everCompleted=%s -> available=%s",
		player.Name, petId, owns and 1 or 0, ever and "y" or "n", available and "y" or "n"))
	return available
end
-- Wipe a pet's quest PROGRESS so it must be genuinely re-done from scratch (used when ownership drops to zero
-- via a trade). Session-only progress: collected pieces + the fishing/dig anti-cheat gates.
local function resetQuestProgress(player, petId)
	if piecesFound[player] then piecesFound[player][petId] = nil end
	if petId == "ButterDuck" then fishEggReady[player] = nil; fishCatches[player] = nil end -- duck must re-catch the egg
	if petId == "BurritoArmadillo" then digEggReady[player] = nil end                       -- armadillo must re-dig the egg
end

-- ===== LEVELING (cosmetic prestige -- 1..50, XP-driven, NO gameplay/flight effect whatsoever) =====
local PET_MAX_LEVEL = 25
-- Rising XP curve: each level needs progressively more (base * level^1.6) so 1->8 is quick and 20->25 is a
-- real grind. xpNeeded(L) = XP to go from level L to L+1. (Rescaled for a 25-level cap.)
local PET_XP_BASE, PET_XP_EXP = 80, 1.6
local function xpNeeded(level)
	if level >= PET_MAX_LEVEL then return math.huge end
	return math.floor(PET_XP_BASE * (level ^ PET_XP_EXP))
end
-- XP award RATES (all tuning lives here). Cosmetic-only -- these NEVER touch flight/gas/coins balance.
local XP_PER_COIN        = 0.15  -- coins earned -> XP (proportional)
local XP_PER_FLIGHT_TICK = 6     -- each 0.5s coin tick fires DURING FLIGHT -> "distance flown" XP
local XP_PER_GAS         = 0.5   -- gas/power gained from eating food -> XP
local XP_PER_ISLAND      = 600   -- reaching a NEW island -> a chunk of XP
-- The cosmetic VISUAL tier name for a level (milestones at 10/20/30/40/50) -- diagnostics + card hint only.
local function tierVisual(level)
	if level >= 25 then return "MAX (all accessories + gold + shimmer)"
	elseif level >= 23 then return "5 accessories + full trail/aura/sparkles"
	elseif level >= 18 then return "4 accessories + sparkles + growing"
	elseif level >= 15 then return "3 accessories + sparkles + growing"
	elseif level >= 13 then return "3 accessories + aura + growing"
	elseif level >= 10 then return "2 accessories + aura + growing"
	elseif level >= 8 then return "2 accessories + trail + growing"
	elseif level >= 5 then return "1 accessory + trail + growing"
	elseif level >= 3 then return "1 accessory, growing"
	else return "starter (growing)" end
end
local function nextMilestoneHint(level)
	if level >= 25 then return "MAX reached"
	elseif level >= 23 then return "Lvl 25: MAX (gold + shimmer)"
	elseif level >= 18 then return "Lvl 23: accessory #5"
	elseif level >= 13 then return "Lvl 18: accessory #4"
	elseif level >= 8 then return "Lvl 13: accessory #3 (hat)"
	elseif level >= 3 then return "Lvl 8: accessory #2 (glasses)"
	else return "Lvl 3: accessory #1" end
end
local function isMilestone(level) return level==3 or level==8 or level==13 or level==18 or level==23 or level==25 end
-- ===== RARE HATCH VARIANTS (Stage 2): ~1% (1/99) chance on hatch, EXCEPT Butter Duck (ultra-rare 1/500). A
-- rare is a FLAG on the owned pet (additive: data.rare=true), comes PRE-MAXED + a unique rare look. Cosmetic.
local RARE_NAMES = {
	BroccoliPet = "Emerald Bunny", CoconutCrab = "Golden Crab", PopcornSheep = "Cloud Sheep",
	BurritoArmadillo = "Crystal Armadillo", ButterDuck = "Cosmic Duck",
}
local function rareOdds(petId) return (petId == "ButterDuck") and 500 or 99 end
-- Normalize an owned entry to a {level,xp,height,time} table (legacy saves stored `true`; xp is ADDITIVE --
-- missing pets/fields default to level 1, 0 XP so existing saves are never broken).
local function getPetData(player, petId)
	local op = _G.playerOwnedPets[player]; if not op then return nil end
	local v = op[petId]; if v == nil then return nil end
	if type(v) ~= "table" then v = {}; op[petId] = v end
	v.level = v.level or 1; v.xp = v.xp or 0; v.height = v.height or 0; v.time = v.time or 0
	v.count = math.max(1, math.floor(tonumber(v.count) or 1)) -- how many of THIS variant the player has stacked (legacy saves -> 1)
	if v.level > PET_MAX_LEVEL then v.level = PET_MAX_LEVEL; v.xp = 0 end -- clamp legacy saves to the new 25 cap
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
	local eq = _G.playerEquippedPet[player]                       -- a STORAGE KEY (petId or petId#R)
	local eqSpecies = eq and speciesOf(eq) or nil
	for petId, def in pairs(PETS) do
		local owns = ownsSpecies(player, petId)
		local isEquipped = owns and (eqSpecies == petId) or false  -- the client only spawns the EQUIPPED follower
		-- follower look comes from the EQUIPPED stack if this species is equipped, else any owned stack (normal first)
		local d = isEquipped and getPetData(player, eq)
			or (owns and (getPetData(player, petId) or getPetData(player, variantKey(petId, true))))
		state[petId] = {
			found = foundCount(player, petId), total = #def.pieceMarkers, owns = owns,
			equipped = isEquipped,
			level = (d and d.level) or 1,
			rare = (d and d.rare) or false, -- rare variant flag (client applies pre-maxed + rare look)
		}
	end
	pcall(function() PetStateEvent:FireClient(player, state) end)
end

-- True if this player has DISCOVERED a pet's quest (landed on its island, or owns the pet).
local function questDiscovered(player, petId)
	if ownsSpecies(player, petId) then return true end
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
		-- ONE card per OWNED STACK: a species can have up to two (a normal stack and/or a separate rare stack). Each
		-- entry is keyed by its STORAGE KEY (petId or petId#R) and carries petId=the SPECIES (the client keys icons/
		-- templates/equip on that) so normal + rare show as separate cards and each can be equipped/traded on its own.
		for _, skey in ipairs(ownedKeysOf(player, petId)) do
			local d = getPetData(player, skey)
			payload.owned[skey] = {
				petId = petId,
				displayName = def.displayName or petId,
				level = d.level, maxLevel = PET_MAX_LEVEL,
				xp = math.floor(d.xp), xpNeed = (d.level >= PET_MAX_LEVEL) and 0 or xpNeeded(d.level),
				milestone = nextMilestoneHint(d.level), tierVisual = tierVisual(d.level),
				equipped = (equipped == skey),
				height = math.floor(d.height), time = math.floor(d.time),
				rare = d.rare and true or false, rareName = d.rare and RARE_NAMES[petId] or nil, -- RARE badge + variant name
				count = d.count or 1, -- how many of this exact variant are stacked (shows as "xN")
			}
		end
		if questDiscovered(player, petId) and def.questType ~= "seasonal" then -- seasonal pets are garden rewards, not island quests
			local found = foundCount(player, petId)
			local total = #def.pieceMarkers
			local status = ownsSpecies(player, petId) and "done" or (found > 0 and "inprogress" or "available")
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

-- ============================================================================================
-- CROSS-PLAYER PET VISIBILITY (Option B) -- ADDITIVE. Besides the owner-only sendState/sendInventory
-- above, BROADCAST each player's equipped-pet info to ALL clients so RemotePets.client.lua can build +
-- follow OTHER players' pets. This NEVER changes sendState/sendInventory or how the owner's own pet
-- (PetFollow) works -- it's an extra fire-and-forget message. No server-side pet models / CSG here.
-- ============================================================================================
local function buildEquipPayload(player)
	local skey = _G.playerEquippedPet[player]
	local petId, level, isRare, variant = nil, 1, false, nil
	if skey and ownsPet(player, skey) then
		local d = getPetData(player, skey)
		petId = speciesOf(skey) -- remote clients render by SPECIES (+ the rare flag/variant below)
		if d then level = d.level or 1; isRare = d.rare and true or false end
		if isRare then variant = RARE_NAMES[petId] end
	end
	return { userId = player.UserId, petId = petId, level = level, isRare = isRare, variant = variant }
end
local function broadcastEquip(player, reason)
	if not player then return end
	local payload = buildEquipPayload(player)
	pcall(function() PetEquipBroadcast:FireAllClients(payload) end)
	print(string.format("[RemotePets] broadcast %s pet=%s lvl=%d rare=%s (reason=%s)",
		player.Name, tostring(payload.petId), payload.level, payload.isRare and "y" or "n", tostring(reason)))
end
-- Send the CURRENT equipped pet of everyone ALREADY in the server to ONE (newly-joined) client, so late
-- joiners immediately see existing players' pets (existing players don't re-broadcast just because one joins).
local function sendAllEquipsTo(target)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= target then
			pcall(function() PetEquipBroadcast:FireClient(target, buildEquipPayload(p)) end)
		end
	end
end

-- Level a pet up by one (the XP auto-level loop and the Robux/test skip all funnel here). Re-syncs follower + GUI.
local function levelUp(player, petId, via)
	local def = PETS[petId]; local d = getPetData(player, petId)
	if not (def and d) then return false end
	if d.level >= PET_MAX_LEVEL then return false end
	d.level = d.level + 1
	print("[PetLvl] "..petId.." LEVELED UP to "..d.level.." (via "..tostring(via)..")")
	if isMilestone(d.level) then print("[PetLvl] "..petId.." hit milestone "..d.level.." -> "..tierVisual(d.level)) end
	sendState(player)     -- the follower re-applies its per-level cosmetic tier visual
	sendInventory(player) -- the card shows the new level + reset XP bar
	if _G.playerEquippedPet[player] == petId then broadcastEquip(player, "levelup") end -- remote viewers see the new level look
	return true
end

-- Throttle the XP-bar inventory resend (coins/flight feed XP fast). Always force on level-up.
local lastInvSync = {}
local lastXpPrint = {} -- throttle the per-tick "+XP" diagnostic for the high-frequency coins/distance sources
local function syncXP(player, force)
	local now = os.clock()
	if force or not lastInvSync[player] or (now - lastInvSync[player]) >= 2.5 then
		lastInvSync[player] = now; sendInventory(player)
	end
end
-- Award XP to the player's EQUIPPED pet ONLY. Cosmetic prestige -- NEVER affects flight/gas/coins. Auto-levels
-- (carrying the remainder) while XP fills, up to MAX (50). Diagnostics per the spec.
local function awardXP(player, amount, source)
	amount = tonumber(amount) or 0; if amount <= 0 then return end
	local petId = _G.playerEquippedPet[player]; if not petId or not ownsPet(player, petId) then return end
	local d = getPetData(player, petId); if not d then return end
	if d.level >= PET_MAX_LEVEL then return end -- maxed -> no XP needed
	d.xp = d.xp + amount
	local leveled = false
	while d.level < PET_MAX_LEVEL do
		local need = xpNeeded(d.level)
		if d.xp < need then break end
		d.xp = d.xp - need
		levelUp(player, petId, "xp:"..tostring(source)) -- force-syncs follower + GUI
		leveled = true
	end
	if d.level >= PET_MAX_LEVEL then d.xp = 0 end
	-- Diagnostic: always for level-ups + low-frequency sources (island/gas); throttle the per-0.5s coins/distance.
	local hi = (source == "coins" or source == "distance")
	local now = os.clock()
	if leveled or not hi or not lastXpPrint[player] or (now - lastXpPrint[player]) >= 2.5 then
		if hi then lastXpPrint[player] = now end
		print(string.format("[PetLvl] %s +%d XP to %s from %s -> %d/%s",
			player.Name, math.floor(amount), petId, tostring(source), math.floor(d.xp),
			(d.level >= PET_MAX_LEVEL) and "MAX" or tostring(xpNeeded(d.level))))
	end
	if not leveled then syncXP(player, false) end -- level-up already force-synced
end
-- XP SOURCE HOOKS (called from PlayerStats' coin/food/island handlers; all rate tuning lives above). --
_G.petAwardXP      = function(player, amount, source) awardXP(player, amount, source) end
_G.petOnCoins      = function(player, coins) awardXP(player, (tonumber(coins) or 0) * XP_PER_COIN, "coins") end
_G.petOnFlightTick = function(player)        awardXP(player, XP_PER_FLIGHT_TICK, "distance") end
_G.petOnGas        = function(player, gas)   awardXP(player, (tonumber(gas) or 0) * XP_PER_GAS, "gas") end
_G.petOnIsland     = function(player)        awardXP(player, XP_PER_ISLAND, "island") end

-- ===== METEOR CRATE HOOKS (pet-level reward) =====
-- The Mystery Meteor Crate grants LEVELS to a player-chosen owned pet. These funnel through the
-- same levelUp() path (re-syncs follower + GUI + remote broadcast each step), and the owned-pets
-- table they mutate is exactly what PlayerStats persists on autosave/leave -- so grants survive.

-- List the player's OWNED pets for the crate picker: { {petId, displayName, level, maxed}, ... },
-- sorted by petId for a deterministic order (server picker fallback + stable client list).
_G.petListOwned = function(player)
	local list = {}
	local op = _G.playerOwnedPets[player]; if not op then return list end
	for petId in pairs(op) do
		if ownsPet(player, petId) then
			local def = PETS[petId]; local d = getPetData(player, petId)
			if def and d then
				local maxed = d.level >= PET_MAX_LEVEL
				local need = maxed and 0 or xpNeeded(d.level)
				local pct = maxed and 100 or (need > 0 and math.clamp((d.xp / need) * 100, 0, 100) or 0)
				table.insert(list, {
					petId = petId,
					displayName = def.displayName or petId,
					level = d.level,
					maxed = maxed,
					xp = math.floor(d.xp),
					xpNeed = need,        -- XP required for the next level (0 when maxed)
					xpPct = pct,          -- 0..100 progress to the next level (100 when maxed)
				})
			end
		end
	end
	table.sort(list, function(a, b) return a.petId < b.petId end)
	return list
end

-- True if the player owns at least one pet that is NOT yet at the level cap.
_G.petHasUnmaxed = function(player)
	for _, p in ipairs(_G.petListOwned(player)) do
		if not p.maxed then return true end
	end
	return false
end

-- Grant N levels to a specific owned pet (crate reward). Validates ownership, clamps at
-- PET_MAX_LEVEL, and re-syncs via levelUp() per step. Returns oldLevel, newLevel, levelsAdded
-- (levelsAdded == 0 if the pet was already maxed; nil on invalid pet / not owned).
_G.petGrantLevels = function(player, petId, n)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then return nil end
	if not ownsPet(player, petId) then return nil end
	local d = getPetData(player, petId); if not d then return nil end
	local oldLevel = d.level
	if oldLevel >= PET_MAX_LEVEL then return oldLevel, oldLevel, 0 end
	local target = math.min(PET_MAX_LEVEL, oldLevel + n)
	while d.level < target do
		if not levelUp(player, petId, "crate") then break end
	end
	return oldLevel, d.level, (d.level - oldLevel)
end

-- SKIP: instantly FILL the current level's remaining XP -> the pet levels up once (Robux product OR test path).
local function petSkip(player, petId, via)
	if not ownsPet(player, petId) then return false end
	local d = getPetData(player, petId); if not d then return false end
	if d.level >= PET_MAX_LEVEL then return false end
	d.xp = 0
	local ok = levelUp(player, petId, "skip:"..tostring(via))
	if ok then print("[PetLvl] skip "..tostring(via).." for "..petId.." -> filled to Lvl "..d.level) end
	return ok
end

-- TIER SKIP: jump the pet to the FIRST level of the NEXT tier (Common1-5 -> 6, Uncommon6-10 -> 11,
-- Rare11-15 -> 16, Epic16-20 -> 21). Returns nil at the top tier (Legendary 21-25 -> nothing to skip).
local function nextTierTarget(level)
	if level <= 5 then return 6
	elseif level <= 10 then return 11
	elseif level <= 15 then return 16
	elseif level <= 20 then return 21
	else return nil end -- Legendary (top tier) -> no skip
end
-- Apply a one-tier jump from the pet's CURRENT level (used by the test path; computed server-side so it can
-- never skip more than one tier). Re-syncs the follower + GUI like levelUp does.
local function tierSkip(player, petId, via)
	if not ownsPet(player, petId) then return false end
	local d = getPetData(player, petId); if not d then return false end
	local target = nextTierTarget(d.level)
	if not target then return false end -- already at the top tier
	d.level = target; d.xp = 0
	sendState(player); sendInventory(player)
	if _G.playerEquippedPet[player] == petId then broadcastEquip(player, "levelup") end -- remote viewers see the tier-skip look
	print("[PetLvl] tier-skip "..tostring(via).." for "..petId.." -> Lvl "..d.level)
	return true
end

-- \xE2\x9A\xA0 TEST COMMAND /allpets - grants all pets to test accounts. REMOVE BEFORE LAUNCH.
-- Grants EVERY pet in the catalog to the player using the SAME ownership structure a normal claim writes
-- ({level=1,height=0,time=0}), marks each quest discovered, auto-equips one if none is equipped, then
-- re-sends state + inventory so all pets show OWNED + equippable immediately (no rejoin). Gated by the
-- CALLER (PlayerStats /allpets handler, test accounts only). Returns how many NEW pets were granted.
_G.petsGrantAll = function(player)
	if not player then return 0 end
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	local granted = 0
	for petId in pairs(PETS) do
		if not ownsPet(player, petId) then
			_G.playerOwnedPets[player][petId] = { level = 1, height = 0, time = 0 } -- same table PetClaimEvent writes
			granted = granted + 1
		end
		_G.playerDiscoveredQuests[player][petId] = true -- so the quests panel shows it as done too
	end
	if not _G.playerEquippedPet[player] then for petId in pairs(PETS) do _G.playerEquippedPet[player] = petId; break end end
	sendState(player)     -- spawns the equipped follower + flags everything owned
	sendInventory(player) -- all pets now appear in the inventory, equippable
	broadcastEquip(player, "equip") -- let other clients render the (test-)equipped pet
	return granted
end
-- \xE2\x9A\xA0 TEST COMMAND /rarepets - grants every pet as its RARE variant (pre-maxed + rare flag) so all 5 rare
-- looks can be seen without gambling the odds. REMOVE BEFORE LAUNCH.
_G.petsGrantRare = function(player)
	if not player then return 0 end
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	local granted = 0
	for petId in pairs(PETS) do
		_G.playerOwnedPets[player][variantKey(petId, true)] = { level = PET_MAX_LEVEL, xp = 0, height = 0, time = 0, rare = true } -- RARE + pre-maxed (own rare slot)
		_G.playerDiscoveredQuests[player][petId] = true
		granted = granted + 1
		print(string.format("[PetRare] rare %s displayed pre-maxed + rare effect %s", petId, RARE_NAMES[petId] or petId))
	end
	if not _G.playerEquippedPet[player] then for petId in pairs(PETS) do _G.playerEquippedPet[player] = variantKey(petId, true); break end end
	sendState(player); sendInventory(player)
	broadcastEquip(player, "rare") -- let other clients render the (test-)equipped rare pet
	return granted
end

-- ===== SEASONAL PET ENTITLEMENT: grant ONE seasonal pet for a season (called by the Community Garden harvest and by
-- the /grantpet test command). Adds it with the SAME ownership structure as a normal claim, so it persists (via
-- PlayerStats saved.ownedPets), shows OWNED in the inventory, and is equippable through the normal pet path. =====
local SEASON_TO_PET = { Summer = "SunflowerBee", Autumn = "MapleFox", Winter = "FrostPenguin", Spring = "BlossomBunny" }
_G.grantSeasonalPet = function(player, season)
	if not (player and season) then return false end
	season = tostring(season)
	local key = season:sub(1, 1):upper() .. season:sub(2):lower() -- accept "summer"/"Summer"/"SUMMER"
	local petId = SEASON_TO_PET[key]
	if not petId then warn("[Pet] grantSeasonalPet: unknown season '"..season.."'"); return false end
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	if ownsSpecies(player, petId) then return true end -- already owned -> nothing to do
	_G.playerOwnedPets[player][petId] = { level = 1, height = 0, time = 0 } -- same table a normal claim writes (persists)
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	_G.playerDiscoveredQuests[player][petId] = true
	sendState(player); sendInventory(player) -- now shows OWNED + equippable immediately (no rejoin)
	print("[Pet] seasonal "..petId.." granted to "..player.Name.." ("..key.." reward)")
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
		if not def.islandPrefix then continue end -- seasonal/grant-only pet: no island markers to scan
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
		elseif def.questType == "dig" then
			local digN = 0; for _, k in ipairs({ "dig1","dig2","dig3","dig4","dig5" }) do if extraFound[k] then digN = digN + 1 end end
			print("[Pet] "..petId.." markers found: shovel="..(extraFound.shovel and "yes" or "no")
				..", digspots="..digN.."/5, buriedegg="..(extraFound.buriedegg and "yes" or "no"))
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
	-- MIGRATION (one-time per save): legacy saves stored a rare under its PLAIN species key. Re-key it to the rare
	-- slot (petId#R) so a normal of the same species can now coexist as a separate entry. Keeps the equip pointer valid.
	local op = _G.playerOwnedPets[player]
	if op then
		for petId in pairs(PETS) do
			local v = op[petId]
			if type(v) == "table" and v.rare and op[variantKey(petId, true)] == nil then
				op[variantKey(petId, true)] = v; op[petId] = nil
				if _G.playerEquippedPet[player] == petId then _G.playerEquippedPet[player] = variantKey(petId, true) end
			end
		end
		for skey in pairs(op) do getPetData(player, skey) end -- normalize legacy `true`/missing level/xp/count on every stack
	end
	-- owning a pet implies its quest was discovered (so the quests panel shows Done even on a fresh session).
	for petId in pairs(PETS) do
		if ownsSpecies(player, petId) then _G.playerDiscoveredQuests[player][petId] = true end
	end
	-- default-equip an owned stack if none is equipped (or the saved one is no longer valid) so a pet still follows
	if not (_G.playerEquippedPet[player] and ownsPet(player, _G.playerEquippedPet[player])) then
		_G.playerEquippedPet[player] = nil
		for petId in pairs(PETS) do local ks = ownedKeysOf(player, petId); if ks[1] then _G.playerEquippedPet[player] = ks[1]; break end end
	end
	sendState(player)     -- tells the client what they own + which is equipped (spawns that follower)
	sendInventory(player) -- fills the Pet Inventory GUI
	for petId in pairs(PETS) do
		for _, skey in ipairs(ownedKeysOf(player, petId)) do print("[Pet] "..skey.." owned by "..player.Name.." (equipped="..tostring(_G.playerEquippedPet[player] == skey)..")") end
	end
	broadcastEquip(player, "join")  -- tell everyone what this (now-loaded) player has equipped
	sendAllEquipsTo(player)         -- and tell THIS player what everyone already here has equipped (late-join catch-up)
end

-- ADDITIVE lifecycle for cross-player pets: re-broadcast a player's pet when their character (re)spawns so
-- remote clients re-attach the follower to the new body. (RemotePets also reads the live character each frame,
-- so this is belt-and-suspenders.) Never touches the owner's own PetFollow pet.
local function hookRemotePetLifecycle(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.4) -- let the new HumanoidRootPart exist before remote clients re-target
		broadcastEquip(player, "respawn")
	end)
end
Players.PlayerAdded:Connect(hookRemotePetLifecycle)
for _, p in ipairs(Players:GetPlayers()) do hookRemotePetLifecycle(p) end

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
	if ownsSpecies(player, petId) then return end -- already have the pet (any variant); ignore
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
	if ownsSpecies(player, petId) then return end             -- already own this species (any variant)
	if def.questType == "fishing" then
		-- fishing has no pieces: the SERVER-rolled egg flag is the anti-cheat gate (client can't fake a catch)
		if not fishEggReady[player] then print("[Pet] "..player.Name.." tried to claim "..petId.." without catching the egg"); return end
	elseif def.questType == "dig" then
		-- dig has no pieces: the player must have DUG the real buried-egg spot (PetDigEvent set this gate)
		if not digEggReady[player] then print("[Pet] "..player.Name.." tried to claim "..petId.." without digging up the egg"); return end
	else
		if foundCount(player, petId) < #def.pieceMarkers then return end -- must have all pieces (anti-cheat gate)
	end
	-- RARE ROLL is FIRST-TIME-ONLY (permanent): the very FIRST ever completion of this quest rolls rare
	-- (~1/99, 1/500 for the duck, server-authoritative). Every RE-completion (quest redone after trading the
	-- species away) grants a GUARANTEED NORMAL pet -- the rare roll never happens again, so rares can never be
	-- re-farmed (they only come from that one first roll, or from trading). everCompleted persists across sessions.
	_G.playerEverCompletedQuests[player] = _G.playerEverCompletedQuests[player] or {}
	local firstTime = not _G.playerEverCompletedQuests[player][petId]
	local isRare = false
	if firstTime then
		local odds = rareOdds(petId)
		isRare = (math.random(1, odds) == 1)
		print(string.format("[PetRare] %s hatched %s - rare roll: %s (odds 1/%d)", player.Name, petId, isRare and "hit" or "miss", odds))
	else
		print(string.format("[PetRare] %s re-completed %s - rare roll SKIPPED (guaranteed normal)", player.Name, petId))
	end
	_G.playerEverCompletedQuests[player][petId] = true -- PERMANENT: this quest has now been completed at least once
	local data = { level = 1, xp = 0, height = 0, time = 0 }
	if isRare then
		data.rare = true
		data.level = PET_MAX_LEVEL -- pre-maxed: rares skip the grind, instantly at the full lvl-25 look
		print(string.format("[PetRare] %s got RARE %s!", player.Name, RARE_NAMES[petId] or petId))
	end
	print(string.format("[PetQuest] %s completed %s quest: firstTime=%s -> rareRoll=%s, granted %s",
		player.Name, petId, firstTime and "y" or "n", firstTime and "done" or "skipped",
		isRare and ((RARE_NAMES[petId] or petId).." (rare)") or "normal"))
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	local skey = variantKey(petId, isRare)         -- a rare goes in its own slot so a normal can coexist later
	_G.playerOwnedPets[player][skey] = data         -- now a table (PlayerStats saves it, incl. the rare flag)
	if not _G.playerEquippedPet[player] then _G.playerEquippedPet[player] = skey end -- auto-equip your first pet
	print("[Pet] "..player.Name.." claimed "..skey)
	print("[Pet] "..skey.." following "..player.Name)
	if isRare then pcall(function() PetRareEvent:FireClient(player, petId, RARE_NAMES[petId] or petId) end) end -- hatch fanfare
	sendState(player)     -- client hides egg/pieces and spawns the equipped follower
	sendInventory(player) -- the new pet shows up in the inventory GUI
	if _G.playerEquippedPet[player] == skey then broadcastEquip(player, isRare and "rare" or "equip") end -- auto-equipped first pet -> show to others
end)

-- ===== FISHING CATCH ROLL (SERVER-AUTHORITATIVE): the client invokes this after a successful reel-in. The
-- server owns the roll + the per-player pity counter so the client can NEVER decide what it catches. Egg chance
-- starts ~25% and ramps each catch, GUARANTEED by catch 8 (no endless bad luck -- it's an easy pet). A miss =
-- a funny junk item (just for variety). Returns { egg=true } or { egg=false, junk="..." } to the client. =====
local FISH_JUNK = { "an old boot", "a butter blob", "a rubber duck", "a soggy sock", "a rusty tin can",
                    "a clump of swamp weed", "a lost flip-flop", "a message in a bottle" }
PetFishRoll.OnServerInvoke = function(player)
	if ownsSpecies(player, "ButterDuck") then return { egg = true, already = true } end -- already have the duck (any variant)
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

-- ===== DIG (BurritoArmadillo): the client fires this when it finishes digging the REAL BuriedEggSpot. The
-- server unlocks the claim gate (digEggReady) so PetClaimEvent will accept the armadillo. Decoy digs (junk) are
-- purely client-side cosmetic and never call this -- only the real buried egg does. =====
PetDigEvent.OnServerEvent:Connect(function(player, petId)
	local def = PETS[petId]; if not def or def.questType ~= "dig" then return end
	if ownsSpecies(player, petId) then return end
	digEggReady[player] = true
	print("[Pet] "..player.Name.." dug BuriedEggSpot -> EGG (claim unlocked)")
end)

-- ===== INVENTORY: EQUIP / UNEQUIP (one at a time) =====
PetEquipEvent.OnServerEvent:Connect(function(player, petId)
	if petId == false or petId == nil then
		_G.playerEquippedPet[player] = nil
		print("[PetInv] unequipped (none) for "..player.Name)
	else
		if not ownsPet(player, petId) then return end -- can only equip what you own
		_G.playerEquippedPet[player] = petId
		local d = getPetData(player, petId)
		print(string.format("[PetLvl] %s equipped %s Lvl %d (%d/%s) tier visual: %s",
			player.Name, petId, d.level, math.floor(d.xp),
			(d.level >= PET_MAX_LEVEL) and "MAX" or tostring(xpNeeded(d.level)), tierVisual(d.level)))
	end
	sendState(player)     -- client spawns/despawns the follower to match
	sendInventory(player)
	broadcastEquip(player, _G.playerEquippedPet[player] and "equip" or "unequip") -- mirror the change to every other client
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

-- ===== ROBUX SKIP path: client declares which pet it's skipping, THEN prompts the Developer Product. The
-- actual XP-fill is gated behind ProcessReceipt (a real purchase). =====
PetPendingUpgrade.OnServerEvent:Connect(function(player, petId)
	if not ownsPet(player, petId) then return end
	-- \xE2\x9A\xA0 TEST skip path: test accounts skip-fill INSTANTLY (no real purchase) so the flow is testable. REMOVE BEFORE LAUNCH.
	if _G.isAllowedTestUser and _G.isAllowedTestUser(player) then
		tierSkip(player, petId, "test") -- testers TIER-skip instantly (no purchase) -- REMOVE BEFORE LAUNCH
		return
	end
	pendingRobuxPet[player.UserId] = petId
end)
-- Called by PlayerStats' single MarketplaceService.ProcessReceipt for the pet-SKIP product. Gated behind the
-- receipt -- a real purchase is required to fill the level (never faked).
_G.petsHandleReceipt = function(player, productId)
	local prod = PET_SKIP_PRODUCTS[productId]
	if not prod then return false end -- not one of our tier-skip products
	local petId = pendingRobuxPet[player.UserId]; pendingRobuxPet[player.UserId] = nil
	if not (petId and ownsPet(player, petId)) then return false end
	local d = getPetData(player, petId); if not d then return false end
	if d.level >= prod.srcMin and d.level <= prod.srcMax then
		d.level = prod.target; d.xp = 0 -- SERVER-AUTHORITATIVE: only applies in this product's source tier
		sendState(player); sendInventory(player)
		print("[PetLvl] tier-skip PURCHASED (to "..prod.to..") for "..petId.." -> Lvl "..d.level)
		return true
	end
	-- not in this product's source tier (pet leveled past it before the receipt) -> consume WITHOUT a wrong jump
	warn("[PetLvl] tier-skip product "..tostring(productId).." not applicable for "..petId.." (Lvl "..d.level.."); consumed, no jump")
	return true
end

-- ===== QUEST DISCOVERY: the client fires this when the player LANDS on a pet's island. Records it
-- (persisted by PlayerStats), so the quest shows in the inventory's quests panel permanently. =====
PetQuestDiscovered.OnServerEvent:Connect(function(player, petId)
	local def = PETS[petId]; if not def then return end
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	if _G.playerDiscoveredQuests[player][petId] then return end -- already discovered (idempotent)
	_G.playerDiscoveredQuests[player][petId] = true
	print("[PetInv] quest discovered: "..petId.." on "..(def.islandName or "?"))
	questAvailable(player, petId) -- log doable/locked state (available iff they own zero of this species)
	sendInventory(player) -- the quest now appears in the player's quests panel
end)

-- =====================================================================================================
-- STAGE 3: PLAYER-TO-PLAYER TRADING (server-authoritative, atomic, anti-dupe). The client only sends INTENTS;
-- the server validates ownership, owns the offer/confirm state, and executes the swap in one synchronous step.
-- =====================================================================================================
local tradeOf    = {} -- [player] = session (a player is in at most ONE trade -> a pet can't be in two trades)
local incomingReq = {} -- [targetPlayer] = requesterPlayer (one pending incoming request)

local function keyList(set) local t = {}; for k in pairs(set) do t[#t+1] = k end; return table.concat(t, ",") end
local function ownedKeyList(player) local t = {}; for k in pairs(_G.playerOwnedPets[player] or {}) do t[#t+1] = k end; return table.concat(t, ",") end
-- compact display payload for an offered pet (skey = the storage key being offered; petId = its SPECIES for the icon)
local function petBrief(player, skey)
	local d = getPetData(player, skey); local sp = speciesOf(skey); local def = PETS[sp]; if not d then return nil end
	return { key = skey, petId = sp, name = (d.rare and RARE_NAMES[sp]) or (def and def.displayName) or sp, level = d.level, rare = d.rare and true or false }
end
local function offerList(owner, offerSet)
	local list = {}; for skey in pairs(offerSet) do local b = petBrief(owner, skey); if b then list[#list+1] = b end end; return list
end
local function tradeStatus(myC, theirC)
	if myC and theirC then return "trading" elseif myC then return "waiting_them" elseif theirC then return "waiting_you" else return "open" end
end
local function sendTradeState(session)
	local A, B = session.a, session.b
	pcall(function() if A.Parent then PetTradeState:FireClient(A, { active=true, withName=B.Name,
		mine=offerList(A, session.offerA), theirs=offerList(B, session.offerB),
		myConfirm=session.confirmA, theirConfirm=session.confirmB, status=tradeStatus(session.confirmA, session.confirmB) }) end end)
	pcall(function() if B.Parent then PetTradeState:FireClient(B, { active=true, withName=A.Name,
		mine=offerList(B, session.offerB), theirs=offerList(A, session.offerA),
		myConfirm=session.confirmB, theirConfirm=session.confirmA, status=tradeStatus(session.confirmB, session.confirmA) }) end end)
end
local function closeTrade(session, reason, doneFlag)
	if not tradeOf[session.a] and not tradeOf[session.b] then return end -- already closed
	tradeOf[session.a] = nil; tradeOf[session.b] = nil
	pcall(function() if session.a.Parent then PetTradeState:FireClient(session.a, { active=false, reason=reason }) end end)
	pcall(function() if session.b.Parent then PetTradeState:FireClient(session.b, { active=false, reason=reason }) end end)
	if not doneFlag then print("[Trade] CANCELLED ("..tostring(reason)..")") end
end
-- ATOMIC, server-validated swap. Runs synchronously (no yields) -> no duplication window.
local function executeTrade(session)
	local A, B = session.a, session.b
	if not (A.Parent and B.Parent) then closeTrade(session, "a player left"); return end
	-- SECURITY re-check at execution: both must still OWN everything they're offering (not just when added).
	for petId in pairs(session.offerA) do if not ownsPet(A, petId) then closeTrade(session, A.Name.." no longer owns "..petId); return end end
	for petId in pairs(session.offerB) do if not ownsPet(B, petId) then closeTrade(session, B.Name.." no longer owns "..petId); return end end
	-- OPEN TRADING with STACKING + VARIANTS: ANY pet for ANY pet. Offers are STORAGE KEYS (petId or petId#R), so a
	-- normal and a rare of one species are independent units. Receiving a key you already own STACKS it (count++,
	-- shared at the higher level); receiving a DIFFERENT variant key just lands as its own separate entry. Nothing to
	-- reject -- different variants can't overwrite each other because they live under different keys.
	local op = _G.playerOwnedPets
	print(string.format("[Trade] EXECUTING %s[%s] <-> %s[%s] - validated ownership both sides (stacking+variants on)", A.Name, keyList(session.offerA), B.Name, keyList(session.offerB)))
	-- snapshot the UNIT each side gives (level/xp/rare), remove ONE from each giver (count--, or drop the stack at 0),
	-- then add ONE to each receiver: STACK if they already own that exact key (count++, keep the higher level) else new.
	local giveA, giveB = {}, {}
	for skey in pairs(session.offerA) do local d = getPetData(A, skey); giveA[skey] = d and { level = d.level, xp = d.xp, height = d.height, time = d.time, rare = d.rare } end
	for skey in pairs(session.offerB) do local d = getPetData(B, skey); giveB[skey] = d and { level = d.level, xp = d.xp, height = d.height, time = d.time, rare = d.rare } end
	local function removeOne(owner, skey)
		local d = op[owner][skey]; if not d then return end
		local c = (d.count or 1) - 1
		if c <= 0 then op[owner][skey] = nil else d.count = c end
	end
	local function addOne(owner, skey, unit)
		if not unit then return end
		local d = op[owner][skey]
		if d then -- same exact key -> stack, keeping the higher level so no progress is lost
			d.count = (d.count or 1) + 1
			if (unit.level or 1) > (d.level or 1) then d.level = unit.level; d.xp = unit.xp or 0 end
		else
			op[owner][skey] = { level = unit.level or 1, xp = unit.xp or 0, height = unit.height or 0, time = unit.time or 0, rare = unit.rare or nil, count = 1 }
		end
	end
	for skey in pairs(session.offerA) do removeOne(A, skey) end
	for skey in pairs(session.offerB) do removeOne(B, skey) end
	for skey, unit in pairs(giveA) do addOne(B, skey, unit) end -- A's unit -> B (stacks onto B's matching key)
	for skey, unit in pairs(giveB) do addOne(A, skey, unit) end -- B's unit -> A (stacks onto A's matching key)
	-- RE-DOABLE QUESTS: whoever traded away their LAST of a SPECIES (owns neither variant now) gets that quest reset
	-- so they can earn it again. A re-completion grants a GUARANTEED NORMAL (rare roll is first-time-only).
	for skey in pairs(giveA) do local sp = speciesOf(skey); if not ownsSpecies(A, sp) then resetQuestProgress(A, sp); questAvailable(A, sp) end end
	for skey in pairs(giveB) do local sp = speciesOf(skey); if not ownsSpecies(B, sp) then resetQuestProgress(B, sp); questAvailable(B, sp) end end
	-- clear equipped if it was traded away (keep equip state sane)
	if _G.playerEquippedPet[A] and not ownsPet(A, _G.playerEquippedPet[A]) then _G.playerEquippedPet[A] = nil end
	if _G.playerEquippedPet[B] and not ownsPet(B, _G.playerEquippedPet[B]) then _G.playerEquippedPet[B] = nil end
	tradeOf[A] = nil; tradeOf[B] = nil
	print(string.format("[Trade] DONE - %s now owns %s, %s now owns %s", A.Name, ownedKeyList(A), B.Name, ownedKeyList(B)))
	-- refresh both clients FIRST (the swap is already done in memory), then persist (SetAsync yields).
	sendState(A); sendInventory(A); sendState(B); sendInventory(B)
	broadcastEquip(A, "equip"); broadcastEquip(B, "equip") -- a traded-away equipped pet may have changed -> update remote views
	pcall(function() if A.Parent then PetTradeState:FireClient(A, { active=false, reason="completed" }) end end)
	pcall(function() if B.Parent then PetTradeState:FireClient(B, { active=false, reason="completed" }) end end)
	if _G.savePlayerData then pcall(function() _G.savePlayerData(A, "trade") end); pcall(function() _G.savePlayerData(B, "trade") end) end -- persist BOTH now (anti-dupe)
end

PetTradeRequest.OnServerEvent:Connect(function(player, targetUserId)
	if tradeOf[player] then return end -- already in a trade
	local target = Players:GetPlayerByUserId(tonumber(targetUserId) or 0)
	if not target or target == player or tradeOf[target] then return end
	incomingReq[target] = player
	print(string.format("[Trade] %s requested trade with %s", player.Name, target.Name))
	pcall(function() PetTradePrompt:FireClient(target, player.UserId, player.Name) end)
end)

PetTradeRespond.OnServerEvent:Connect(function(player, accept)
	local requester = incomingReq[player]; incomingReq[player] = nil
	if not (requester and requester.Parent) then return end
	if accept == true and not tradeOf[player] and not tradeOf[requester] then
		local session = { a = requester, b = player, offerA = {}, offerB = {}, confirmA = false, confirmB = false }
		tradeOf[requester] = session; tradeOf[player] = session
		print(string.format("[Trade] %s accepted trade with %s", player.Name, requester.Name))
		sendTradeState(session)
	else
		print(string.format("[Trade] %s declined trade from %s", player.Name, requester.Name))
		pcall(function() if requester.Parent then PetTradeState:FireClient(requester, { active=false, reason="declined" }) end end)
	end
end)

PetTradeOffer.OnServerEvent:Connect(function(player, petId, add)
	local session = tradeOf[player]; if not session or type(petId) ~= "string" then return end
	local mine = (session.a == player) and session.offerA or session.offerB
	if add == true then
		if not ownsPet(player, petId) then return end -- can only offer what you actually own
		if _G.playerEquippedPet[player] == petId then -- auto-unequip the equipped pet when you offer it
			_G.playerEquippedPet[player] = nil; sendState(player); sendInventory(player)
			broadcastEquip(player, "unequip") -- remove the follower from other clients too
		end
		mine[petId] = true
		print(string.format("[Trade] %s added %s to offer", player.Name, petId))
	else
		mine[petId] = nil
		print(string.format("[Trade] %s removed %s from offer", player.Name, petId))
	end
	session.confirmA = false; session.confirmB = false -- ANY offer change RESETS both confirms (anti-scam)
	sendTradeState(session)
end)

PetTradeConfirm.OnServerEvent:Connect(function(player)
	local session = tradeOf[player]; if not session then return end
	if session.a == player then session.confirmA = true else session.confirmB = true end
	print(string.format("[Trade] %s confirmed (offers locked: %s=[%s] %s=[%s])", player.Name, session.a.Name, keyList(session.offerA), session.b.Name, keyList(session.offerB)))
	if session.confirmA and session.confirmB then executeTrade(session) else sendTradeState(session) end
end)

PetTradeCancel.OnServerEvent:Connect(function(player)
	local session = tradeOf[player]; if session then closeTrade(session, "cancelled by "..player.Name) end
end)

Players.PlayerRemoving:Connect(function(player)
	piecesFound[player] = nil -- ownership/equipped/discovered clears are handled by PlayerStats (after it saves)
	pendingRobuxPet[player.UserId] = nil
	upgradeReady[player] = nil
	lastInvSync[player] = nil; lastXpPrint[player] = nil -- XP-sync / diagnostic throttles (session-only)
	fishCatches[player] = nil; fishEggReady[player] = nil -- fishing pity is session-only (not persisted)
	digEggReady[player] = nil -- dig gate is session-only (not persisted)
	-- TRADE: if they were trading, cancel cleanly (no item loss/dupe -- nothing was swapped until both confirmed).
	local session = tradeOf[player]; if session then closeTrade(session, player.Name.." left") end
	incomingReq[player] = nil
	for tgt, req in pairs(incomingReq) do if req == player then incomingReq[tgt] = nil end end
end)

print("[Pet] PetSystem ready (cosmetic-only)")
