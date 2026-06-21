-- ============================================================================================
-- PET SYSTEM (client) -- COSMETIC ONLY. Builds the per-player broccoli PIECES + EGG at the island
-- markers, and the follower PET that trails the player (smoothly, INCLUDING during fast fart-flight).
-- ============================================================================================
-- The server (PetSystem.server.lua) owns the authoritative state (piece counts, ownership,
-- persistence). This client builds the visuals per-player and drives the follow. It NEVER touches
-- the player's physics: the pet is anchored + CanCollide/CanQuery false and moved kinematically via
-- Model:PivotTo, so it cannot affect flight, gas, coins, or anything. Purely visual.
--
-- Protocol: PetStateEvent (s->c) tells us {found,total,owns} per pet. We fire PetCollectEvent /
-- PetClaimEvent (c->s) from the prompts, and PetRequestStateEvent (c->s) once as a handshake.
-- ============================================================================================

local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local RunService  = game:GetService("RunService")
local Workspace   = game:GetService("Workspace")
local SoundService    = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local player      = Players.LocalPlayer

-- ===== HATCH SOUNDS (shared by ALL pets' hatch flow) =====
-- Created + PRELOADED ONCE at startup so they play INSTANTLY. (Previously a fresh Instance.new("Sound") +
-- :Play() loaded the asset on first use, which delayed the crack ~2s -- so it seemed to start ~2s late.
-- Preloading removes that delay, so the crack now fires right at the TRUE hatch start and the unlock lands
-- on the reveal.) Volumes are boosted ABOVE 1.0 (Roblox allows up to 10) for a genuinely LOUD/impactful hatch.
local hatchCrackSound = Instance.new("Sound")
hatchCrackSound.Name = "HatchCrackSound"; hatchCrackSound.SoundId = "rbxassetid://126450028713974"
hatchCrackSound.Volume = 3; hatchCrackSound.Parent = SoundService
local hatchUnlockSound = Instance.new("Sound")
hatchUnlockSound.Name = "HatchUnlockSound"; hatchUnlockSound.SoundId = "rbxassetid://92880640988467"
hatchUnlockSound.Volume = 3; hatchUnlockSound.Parent = SoundService
task.spawn(function() pcall(function() ContentProvider:PreloadAsync({ hatchCrackSound, hatchUnlockSound }) end) end)

-- Mirror of the server catalog (marker names so we can find them in Workspace).
local PETS = {
	BroccoliPet = {
		questType    = "find",
		islandPrefix = "Island_2_",
		eggMarker    = "I2PetBlock",
		pieceMarkers = { "BroccoliPiece1", "BroccoliPiece2", "BroccoliPiece3" },
		-- UI metadata (DATA-DRIVEN: the quest UI reads these, so future pet islands reuse it with no hardcoding)
		pieceLabel   = "Broccoli",                                  -- tracker/popup label ("Broccoli: 1/3")
		iconEmoji    = "\xF0\x9F\xA5\xA6",                           -- 🥦 tracker icon
		questName    = "Broccoli Bunny Quest",                       -- HUD indicator: the quest's real NAME
		objective    = "Find 3 broccoli pieces",                     -- HUD indicator: short objective line
		trackWord    = "Pieces",                                     -- HUD minimized tracker word ("Pieces X/3")
		nextStep     = "Hatch the egg",                              -- tracker text once the count is complete
	},
	-- PET #2: COCONUT CRAB (Coconut Cove). questType "crack": 7 coconuts (tap-to-crack minigame) -> Cave Key
	-- -> chest in the cave -> egg -> hatch. Same marker->position->visual architecture as broccoli.
	CoconutCrab = {
		questType    = "crack",
		islandPrefix = "Island_5_",
		eggMarker    = "CoconutChest",
		pieceMarkers = { "Coconut1","Coconut2","Coconut3","Coconut4","Coconut5","Coconut6","Coconut7" },
		pieceLabel   = "Coconut",
		iconEmoji    = "\xF0\x9F\xA5\xA5",                           -- 🥥 tracker icon
		questName    = "Coconut Crab Quest",
		objective    = "Crack 7 coconuts",
		trackWord    = "Coconuts",                                   -- "Coconuts X/7"
		nextStep     = "Unlock the chest",
	},
	-- PET #3: POPCORN SHEEP (Popcorn Pinnacle). questType "film-reels": find 6 FILM REELS -> load them at
	-- the PROJECTOR -> a mini-movie plays on the SCREEN -> the egg materializes in a spotlight at the
	-- PopcornEggSpot -> hatch. Same marker->position->visual architecture; projector + screen positions ride
	-- in extraMarkers (the client builds those props). Movie-theater themed, cosmetic-only.
	PopcornSheep = {
		questType    = "film-reels",
		islandPrefix = "Island_8_",
		eggMarker    = "PopcornEggSpot",
		pieceMarkers = { "FilmReel1","FilmReel2","FilmReel3","FilmReel4","FilmReel5","FilmReel6" },
		extraMarkers = { projector = "PopcornProjector", screen = "PopcornScreen" },
		pieceLabel   = "Film Reel",
		iconEmoji    = "\xF0\x9F\x90\x91",                           -- 🐑 tracker icon
		allFoundMsg  = "All 6 found! Load reels at the projector!",  -- tracker text at full count (data-driven)
		questName    = "Popcorn Sheep Quest",
		objective    = "Collect 6 film reels",
		trackWord    = "Reels",                                      -- "Reels X/6"
		nextStep     = "Load the projector",
	},
	-- PET #4: BUTTER DUCK (Butter Swamp). questType "fishing": grab a rod at the barrel -> fish near/over the
	-- ButterLake UNION -> cast -> bite/hook (reaction) -> reel-in tension minigame -> the SERVER rolls the catch
	-- (pity egg chance + funny junk) -> the egg appears IN FRONT of the player -> hatch. No pieces/egg marker.
	ButterDuck = {
		questType    = "fishing",
		islandPrefix = "Island_10_",
		pieceMarkers = {},                                          -- fishing has no collectible pieces
		extraMarkers = { butterlake = "ButterLake", rodbarrel = "RodBarrel" },
		pieceLabel   = "Catch",
		iconEmoji    = "\xF0\x9F\xA6\x86",                           -- 🦆 tracker icon
		allFoundMsg  = "Fish in the butter to catch the egg!",
		questName    = "Butter Duck Quest",
		objective    = "Catch what's in the butter lake",
		trackWord    = "Reeled in",                                  -- fishing has no fixed total -> "Reeled in: X"
		nextStep     = "Hatch the egg",
	},
	-- PET #5: BURRITO ARMADILLO (Burrito Barrens). questType "dig": grab a SHOVEL -> hot/cold hunt -> DIG
	-- minigame at dig spots -> DigSpot1-4 are decoys (junk), BuriedEggSpot is the real one (the egg) -> hatch.
	BurritoArmadillo = {
		questType    = "dig",
		islandPrefix = "Island_13_",
		pieceMarkers = {},                                          -- dig has no collectible pieces
		extraMarkers = { shovel = "ShovelSpot", dig1 = "DigSpot1", dig2 = "DigSpot2", dig3 = "DigSpot3", dig4 = "DigSpot4", dig5 = "DigSpot5", buriedegg = "BuriedEggSpot" },
		pieceLabel   = "Dig",
		iconEmoji    = "\xF0\x9F\xAA\x96",                           -- 🪖 (armadillo-ish) tracker icon
		allFoundMsg  = "Dig up the buried armadillo egg!",
		questName    = "Burrito Armadillo Quest",
		objective    = "Dig up what's buried",
		trackWord    = "Mounds",                                     -- "Mounds X/6"
		nextStep     = "Dig up the egg",
	},
	-- ===== SEASONAL PETS (Community Garden rewards) -- NO island quest (granted by the harvest). questType="seasonal"
	-- so the startup world-builder skips them; they ONLY ever appear as the equipped FOLLOWER (cloned from the server
	-- template via PET_TEMPLATE_NAME) + an owned inventory card. Must exist here so applyState() spawns the follower.
	SunflowerBee = { questType = "seasonal", pieceMarkers = {}, displayName = "Sunflower Bee", iconEmoji = "\xF0\x9F\x90\x9D" },
	MapleFox     = { questType = "seasonal", pieceMarkers = {}, displayName = "Maple Fox",     iconEmoji = "\xF0\x9F\xA6\x8A" },
	FrostPenguin = { questType = "seasonal", pieceMarkers = {}, displayName = "Frost Penguin", iconEmoji = "\xF0\x9F\x90\xA7" },
	BlossomBunny = { questType = "seasonal", pieceMarkers = {}, displayName = "Blossom Bunny", iconEmoji = "\xF0\x9F\x90\xB0" },
}

-- ============================================================================================
-- HUD QUEST INDICATOR -- shared progress state. The on-screen tracker shows each quest's real NAME +
-- objective while it's AVAILABLE on the player's island, then MINIMIZES to a small live progress counter
-- once STARTED. Piece quests (broccoli/coconut/sheep) drive it from the server found/total; the count-less
-- quests (fishing/dig) push progress here from their own interaction code. Forward-declared so that the
-- interaction code (which lives ABOVE the HUD GUI in this file) can update it. COSMETIC-ONLY.
local localQuestProg = {}    -- [petId] = { started=bool, found=n, total=n_or_nil, complete=bool } (fishing/dig)
local refreshQuestHUD        -- assigned where the tracker GUI is built (below); closures capture this upvalue
local function pushQuestProg(petId, fields)
	local lp = localQuestProg[petId] or {}
	for k, v in pairs(fields) do lp[k] = v end
	localQuestProg[petId] = lp
	if refreshQuestHUD then pcall(refreshQuestHUD) end
end

local PetCollectEvent      = RS:WaitForChild("PetCollectEvent", 30)
local PetClaimEvent        = RS:WaitForChild("PetClaimEvent", 30)
local PetRequestStateEvent = RS:WaitForChild("PetRequestStateEvent", 30)
local PetStateEvent        = RS:WaitForChild("PetStateEvent", 30)
local PetGetMarkers        = RS:WaitForChild("PetGetMarkers", 30) -- RF: ask the server for marker COORDINATES (client never searches Workspace)
-- pet inventory / equip / leveling remotes (cosmetic-only)
local PetEquipEvent     = RS:WaitForChild("PetEquipEvent", 30)
local PetInventoryEvent = RS:WaitForChild("PetInventoryEvent", 30)
local PetUpgradeEvent   = RS:WaitForChild("PetUpgradeEvent", 30)
local PetProgressEvent  = RS:WaitForChild("PetProgressEvent", 30)
local PetPendingUpgrade = RS:WaitForChild("PetPendingUpgradeEvent", 30)
local PetQuestDiscovered = RS:WaitForChild("PetQuestDiscoveredEvent", 30) -- c->s: landed on a pet's island
local PetFishRoll = RS:WaitForChild("PetFishRollEvent", 30) -- c->s RF: reeled in -> SERVER rolls the catch (pity)
local PetDigEvent = RS:WaitForChild("PetDigEvent", 30) -- c->s: dug the REAL buried-egg spot -> server unlocks the BurritoArmadillo claim
local PetRareEvent = RS:WaitForChild("PetRareEvent", 30) -- s->c: (petId, rareName) a RARE hatched -> play the fanfare
-- STAGE 3 TRADE remotes (client sends intents only)
local PetTradeRequest = RS:WaitForChild("PetTradeRequestEvent", 30)
local PetTradeRespond = RS:WaitForChild("PetTradeRespondEvent", 30)
local PetTradeOffer   = RS:WaitForChild("PetTradeOfferEvent", 30)
local PetTradeConfirm = RS:WaitForChild("PetTradeConfirmEvent", 30)
local PetTradeCancel  = RS:WaitForChild("PetTradeCancelEvent", 30)
local PetTradeState   = RS:WaitForChild("PetTradeStateEvent", 30)
local PetTradePrompt  = RS:WaitForChild("PetTradeRequestPromptEvent", 30)
-- ⚠ REPLACE BEFORE LAUNCH: placeholder TIER-SKIP Developer Product IDs (must match PET_SKIP_PRODUCTS in
-- PetSystem.server.lua). Each jumps the pet to the FIRST level of the next tier; the Skip button prompts the
-- one for the pet's current tier. Until the real products exist the prompt errors harmlessly for real players;
-- test accounts tier-skip instantly via the server test path. (Ordered 1=Common->Uncommon ... 4=Epic->Legendary.)
local PET_SKIP_PRODUCTS = {
	{ to = "Uncommon",  price = 49,  id = 123456701 }, -- ⚠ placeholder product id -- REPLACE BEFORE LAUNCH
	{ to = "Rare",      price = 99,  id = 123456702 }, -- ⚠ REPLACE BEFORE LAUNCH
	{ to = "Epic",      price = 299, id = 123456703 }, -- ⚠ REPLACE BEFORE LAUNCH
	{ to = "Legendary", price = 599, id = 123456704 }, -- ⚠ REPLACE BEFORE LAUNCH
}

-- ===== low-poly build helpers =====
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape
	p.Size = size; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end

-- A small broccoli "thing" (stalk + green florets) built around a root CFrame; returns the Model.
local function buildBroccoliBlob(scale, withFace)
	local model = Instance.new("Model"); model.Name = "BroccoliBlob"
	local s = scale or 1
	-- Upright BLOCK stalk as PrimaryPart (identity orientation) so Model:PivotTo orients the whole pet
	-- cleanly (a rotated PrimaryPart would skew the florets/eyes when we PivotTo each frame).
	local stalk = newPart(model, "Stalk", Enum.PartType.Block, Vector3.new(0.85*s, 1.3*s, 0.85*s), Color3.fromRGB(175, 200, 140), CFrame.new(0,0,0))
	model.PrimaryPart = stalk
	local crownC = Color3.fromRGB(60, 160, 60)
	newPart(model, "Floret0", Enum.PartType.Ball, Vector3.new(1.5*s,1.5*s,1.5*s), crownC, CFrame.new(0, 1.1*s, 0))
	for i = 1, 5 do
		local a = (i-1) * (2*math.pi/5)
		newPart(model, "Floret"..i, Enum.PartType.Ball, Vector3.new(1.05*s,1.05*s,1.05*s), crownC,
			CFrame.new(math.cos(a)*0.85*s, 0.95*s, math.sin(a)*0.85*s))
	end
	if withFace then
		-- eyes on the FRONT (-Z) of the crown; pupils slightly in front so they read at distance.
		for _, sx in ipairs({-0.35, 0.35}) do
			newPart(model, "Eye", Enum.PartType.Ball, Vector3.new(0.42*s,0.42*s,0.42*s), Color3.fromRGB(255,255,255), CFrame.new(sx*s, 1.15*s, -0.62*s))
			newPart(model, "Pupil", Enum.PartType.Ball, Vector3.new(0.22*s,0.22*s,0.22*s), Color3.fromRGB(20,20,20), CFrame.new(sx*s, 1.15*s, -0.78*s))
		end
	end
	return model
end

-- A cute cartoony broccoli-themed DINO (the pet). Built low-poly around an INVISIBLE anchored Root as
-- PrimaryPart (identity orientation) so Model:PivotTo follows + ScaleTo pops without skewing; -Z = front
-- (the follow loop faces the pet's -Z toward travel, so the eyes point forward). Modular: future pets can
-- have their own buildXyz() and spawnFollowerPet just swaps which builder it calls.
-- Animator registry: model -> { parts = { {part, base (local CFrame vs root), baseSize, role, eye?, breath?}.. },
-- s, t, move (0..1), blink, lastPos }. Weak keys so a destroyed pet is GC'd. animatePet() (below) reads
-- this each frame and writes LOCAL offsets onto the sub-parts -- the root keeps following the player.
local petAnims = setmetatable({}, { __mode = "k" })

-- FRIENDLY CARTOON DINO: a soft, smooth, rounded long-neck dinosaur. EVERYTHING is a rounded ellipsoid
-- (Ball, SmoothPlastic) -- NO blocks, no sharp edges. Parts overlap generously so they blend into ONE
-- connected smooth animal, while the long-neck-up / snout-forward / long-tail-back / standing-on-legs
-- proportions keep it readable as a dinosaur. Big cute eyes = friendly. Broccoli-green with rounded
-- floret bumps as a head crest + back ridge. Local frame: +X = FORWARD/facing (the follow loop yaws the
-- root so +X leads travel). role groups parts for the animator (body/head/tail/leg); eye=true blinks.
-- The long NECK is tagged "head" so it sways smoothly with the head (a gentle, friendly dino motion).
-- NOTE: this is the FALLBACK builder (separate parts) used only if the server's fused Union template is
-- missing. Normally buildBroccoliDino() clones the pre-fused server Union from ReplicatedStorage instead.
local function buildBroccoliDinoFallback(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "BroccoliDino"
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1
	model.PrimaryPart = root
	local bodyC  = Color3.fromRGB(60,140,55)
	local legC   = Color3.fromRGB(45,110,45)
	local crownC = Color3.fromRGB(40,100,40)
	local whiteC = Color3.fromRGB(245,245,245)
	local darkC  = Color3.fromRGB(30,30,30)
	local parts = {}
	local function record(part, role, eye)
		local e = { part = part, base = part.CFrame, baseSize = part.Size, role = role, eye = eye }
		parts[#parts+1] = e
		return e
	end
	-- a part (Block or Ball) at a position, with optional local rotation (for the angled neck). SmoothPlastic.
	local function add(name, role, ptype, size, color, x, y, z, rot, eye)
		local cf = CFrame.new(x*s, y*s, z*s)
		if rot then cf = cf * rot end
		local part = newPart(model, name, ptype, Vector3.new(size[1], size[2], size[3]) * s, color, cf)
		return record(part, role, eye)
	end
	local BAL = Enum.PartType.Ball -- everything is a smooth rounded Ball ellipsoid (no blocks)

	-- ===== FALLBACK body parts (separate rounded ellipsoids). Used only when the server Union template is
	-- missing -- they animate per-role (neck/tail sway) so the pet still looks alive without the fusion.
	-- 1) BODY: a big soft rounded torso.
	add("Body", "body", BAL, {2.9, 1.85, 2.05}, bodyC, 0, 0, 0).bodyGroup = true
	-- 2) NECK: two rounded ellipsoids sweeping UP-and-FORWARD, overlapping body + head -> one smooth neck.
	add("NeckLow", "head", BAL, {1.15, 1.5, 1.15}, bodyC, 1.35, 1.05, 0, CFrame.Angles(0, 0, math.rad(-30))).bodyGroup = true
	add("Neck",    "head", BAL, {1.0, 1.7, 1.0},  bodyC, 1.85, 1.95, 0, CFrame.Angles(0, 0, math.rad(-26))).bodyGroup = true
	-- 3) HEAD + SNOUT.
	add("Head", "head", BAL, {1.35, 1.2, 1.25}, bodyC, 2.35, 2.55, 0).bodyGroup = true
	add("Snout", "head", BAL, {1.1, 0.85, 0.95}, bodyC, 3.0, 2.35, 0).bodyGroup = true
	-- 4) TAIL: a long tapering tail, each segment overlapping the previous, stepping DOWN-and-BACK.
	add("Tail", "tail", BAL, {1.6, 1.15, 1.15}, bodyC, -1.85, -0.05, 0).bodyGroup = true
	add("Tail", "tail", BAL, {1.15, 0.8, 0.8},  bodyC, -2.7, -0.4, 0).bodyGroup = true
	add("Tail", "tail", BAL, {0.75, 0.5, 0.5},  bodyC, -3.4, -0.7, 0).bodyGroup = true
	add("Tail", "tail", BAL, {0.42, 0.34, 0.34},bodyC, -3.9, -0.95, 0).bodyGroup = true

	-- ===== SEPARATE parts (NOT unioned) -- they keep their own colors/animation. .lockOnUnion = they snap
	-- to riding rigidly with the fused union once it exists (so they don't drift off the now-solid body).
	-- EYES: BIG friendly rounded eyes (white) + big dark pupils, proud of the head front.
	for _, ez in ipairs({0.42, -0.42}) do
		add("Eye",   "head", BAL, {0.52, 0.62, 0.46}, whiteC, 2.62, 2.7, ez, nil, true).lockOnUnion = true
		add("Pupil", "head", BAL, {0.3, 0.42, 0.3},   darkC,  2.82, 2.66, ez, nil, true).lockOnUnion = true
	end
	-- LEGS: four soft rounded leg stubs (kept SEPARATE -- thin parts union poorly, and they keep their gait).
	for _, lp in ipairs({ {1.0,0.62}, {1.0,-0.62}, {-1.0,0.62}, {-1.0,-0.62} }) do
		add("Leg", "leg", BAL, {0.8, 1.35, 0.8}, legC, lp[1], -1.2, lp[2])
	end
	-- BROCCOLI THEME: rounded floret bumps as a HEAD CREST + a NECK/BACK RIDGE (separate green parts).
	for _, f in ipairs({
		{x=2.3, y=3.05,z=0.00, r=0.56, role="head"}, {x=2.05,y=2.95,z=0.26, r=0.44, role="head"},
		{x=2.55,y=2.95,z=-0.24,r=0.46, role="head"}, {x=1.85,y=2.25,z=0.00, r=0.46, role="head"}, -- crest + upper neck
		{x=0.5, y=1.15,z=0.00, r=0.56, role="body"}, {x=-0.55,y=1.05,z=0.00, r=0.5, role="body"}, -- back ridge
	}) do
		add("Floret", f.role, BAL, {f.r, f.r, f.r}, crownC, f.x, f.y, f.z).lockOnUnion = true
	end

	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- Register a CLONED server template (its body is ONE fused UnionOperation -> smooth, not loose spheres).
-- Derive each part's animator role from its name. The body is now one rigid union, so the head/neck/tail
-- can't sway independently -- everything (union + eyes + florets) rides the whole-body bob/sway/lean as a
-- unit; eyes still blink; the separate legs still do their gait.
local function registerClonedTemplate(model)
	local root = model:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then return false end
	model.PrimaryPart = root
	local rootCF = root.CFrame
	local parts = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			local role, eye = "body", false
			local n = p.Name
			if n == "Leg" or n == "Foot" or n == "ToeClaw" then role = "leg"   -- legs/feet do the gait
			elseif n == "Tail" or n == "TailSpike" then role = "tail" -- tail wiggle
			elseif n == "Ear" then role = "ear"                       -- ears wiggle/flop (bunny, sheep)
			elseif n == "Wing" then role = "wing"                     -- wings flap (duck)
			elseif n == "Claw" then role = "claw"                     -- claws scuttle (crab)
			elseif n == "Eye" or n == "Highlight" then eye = true end -- ride the body, but blink
			parts[#parts+1] = { part = p, base = rootCF:ToObjectSpace(p.CFrame), baseSize = p.Size, role = role, eye = eye }
		end
	end
	petAnims[model] = { s = 0.9, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil, unionized = true }
	return true
end

-- The pet builder: CLONE the server's pre-fused Union template (smooth body) if present; otherwise fall
-- back to the client-built separate-parts dino so the pet always appears.
local function buildBroccoliDino(scale)
	-- instant if already replicated; else wait briefly for it (covers join-time replication lag)
	local template = RS:FindFirstChild("BroccoliDinoTemplate") or RS:WaitForChild("BroccoliDinoTemplate", 3)
	if template then
		local clone = template:Clone()
		clone.Name = "BroccoliDino"
		if registerClonedTemplate(clone) then
			print("[Pet][UNION] cloned server Union template (smooth fused body)")
			return clone
		end
		clone:Destroy()
	end
	warn("[Pet][UNION] BroccoliDinoTemplate not found in ReplicatedStorage -- using separate-parts fallback")
	return buildBroccoliDinoFallback(scale)
end

local function setVisible(model, on)
	if not model then return end
	model.Parent = on and Workspace or nil
end

-- ===== marker lookup =====
-- (REMOVED: the client no longer SEARCHES Workspace/island for markers. The server owns the marker
-- POSITIONS and hands them over via the PetGetMarkers RemoteFunction; we build from those coordinates.)

-- ===== per-pet client state =====
local petState = {}  -- [petId] = { pieces={[i]=model}, collected={[i]=bool}, egg=model, pet=model, built=bool }

local function addPrompt(rootPart, actionText, objectText, onTriggered)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = actionText; pp.ObjectText = objectText
	pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0
	pp.MaxActivationDistance = 12; pp.RequiresLineOfSight = false
	pp.Parent = rootPart
	pp.Triggered:Connect(onTriggered)
	return pp
end

local function floatText(pos, text)
	local a = Instance.new("Part"); a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.Transparency=1; a.Size=Vector3.new(1,1,1); a.CFrame=CFrame.new(pos); a.Parent=Workspace
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,180,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.Parent=a
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=22; lbl.TextColor3=Color3.fromRGB(120,255,120); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	game:GetService("TweenService"):Create(a, TweenInfo.new(1.2), {Transparency=1}):Play()
	game:GetService("TweenService"):Create(lbl, TweenInfo.new(1.2), {TextTransparency=1}):Play()
	task.delay(1.3, function() a:Destroy() end)
end

local hatchEgg -- forward declaration; assigned below (after the spawnFollowerPet/setEggGlow it relies on)

-- ============================================================================================
-- COCONUT CRAB QUEST (questType "crack"). A harder multi-stage quest: CRACK 7 coconuts (a tap minigame)
-- -> earn the CAVE KEY -> open the key-gated CHEST in the cave -> egg -> hatch -> the Coconut Crab follows.
-- Reuses the same server collect/claim/inventory + the broccoli HATCH flow. All cosmetic-only.
-- ============================================================================================

-- placeholder COCONUT CRAB follower (brown coconut-shell body + 3 spots, claws, legs, cute eyes). Registers
-- parts into petAnims (body/leg roles + eye) so the existing animator gives it idle bob, blink, leg gait.
local function buildCoconutCrab(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "CoconutCrab"
	local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye, mat)
		local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s), mat)
		parts[#parts+1] = { part = p, base = p.CFrame, baseSize = p.Size, role = role or "body", eye = eye }
		return p
	end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1; model.PrimaryPart = root -- +X = front (the follow loop yaws +X toward travel)
	local BROWN, DARK, CLAW = Color3.fromRGB(112,72,42), Color3.fromRGB(66,40,22), Color3.fromRGB(150,72,46)
	mk("Body", Enum.PartType.Ball, 2.1,1.8,2.1, BROWN, 0,0,0, "body")
	mk("Spot", Enum.PartType.Ball, 0.34,0.34,0.22, DARK, 0.95,0.15,0, "body")      -- the 3 coconut "eyes"
	mk("Spot", Enum.PartType.Ball, 0.3,0.3,0.2, DARK, 0.9,-0.35,-0.4, "body")
	mk("Spot", Enum.PartType.Ball, 0.3,0.3,0.2, DARK, 0.9,-0.35,0.4, "body")
	for _, ez in ipairs({-0.45, 0.45}) do                                          -- cute eyes
		mk("Eye", Enum.PartType.Ball, 0.42,0.42,0.42, Color3.fromRGB(245,245,245), 0.55,1.0,ez, "body", true)
		mk("Pupil", Enum.PartType.Ball, 0.22,0.22,0.22, Color3.fromRGB(18,18,18), 0.78,1.02,ez, "body", true)
	end
	for _, cs in ipairs({-1, 1}) do                                                -- two claws
		mk("Claw", Enum.PartType.Ball, 0.78,0.66,0.6, CLAW, 0.7,-0.15,cs*1.2, "body")
		mk("ClawTip", Enum.PartType.Ball, 0.46,0.34,0.34, CLAW, 1.05,-0.05,cs*1.45, "body")
	end
	for _, ls in ipairs({-1, 1}) do                                                -- 6 little legs
		for i = 1, 3 do mk("Leg", Enum.PartType.Ball, 0.26,0.62,0.26, DARK, -0.5+(i-1)*0.5, -0.9, ls*0.95, "leg") end
	end
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- CRACK MINIGAME: a small popup -- tap the coconut NEED times within WINDOW seconds to crack it.
local crackUI, crackBusy = nil, false
local function ensureCrackUI()
	if crackUI then return crackUI end
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "CoconutCrackGui"; g.ResetOnSpawn = false; g.DisplayOrder = 90; g.Enabled = false; g.Parent = pgui
	local film = Instance.new("Frame"); film.Size = UDim2.new(1,0,1,0); film.BackgroundColor3 = Color3.new(0,0,0); film.BackgroundTransparency = 0.5; film.Active = true; film.Parent = g
	local panel = Instance.new("Frame"); panel.Size = UDim2.new(0,300,0,310); panel.Position = UDim2.new(0.5,0,0.5,0); panel.AnchorPoint = Vector2.new(0.5,0.5)
	panel.BackgroundColor3 = Color3.fromRGB(25,90,185); panel.Parent = g
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16); local ps = Instance.new("UIStroke", panel); ps.Color = Color3.new(1,1,1); ps.Thickness = 3
	local titl = Instance.new("TextLabel"); titl.Size = UDim2.new(1,-20,0,30); titl.Position = UDim2.new(0,10,0,8); titl.BackgroundTransparency = 1
	titl.Font = Enum.Font.GothamBold; titl.TextSize = 20; titl.TextColor3 = Color3.fromRGB(255,215,0); titl.Text = "CRACK THE COCONUT!"; titl.Parent = panel
	local hintL = Instance.new("TextLabel"); hintL.Size = UDim2.new(1,-20,0,18); hintL.Position = UDim2.new(0,10,0,38); hintL.BackgroundTransparency = 1
	hintL.Font = Enum.Font.Gotham; hintL.TextSize = 13; hintL.TextColor3 = Color3.new(1,1,1); hintL.Text = "Tap fast!"; hintL.Parent = panel
	local coco = Instance.new("TextButton"); coco.Size = UDim2.new(0,150,0,150); coco.Position = UDim2.new(0.5,0,0.5,8); coco.AnchorPoint = Vector2.new(0.5,0.5)
	coco.BackgroundColor3 = Color3.fromRGB(112,72,42); coco.Text = "\xF0\x9F\xA5\xA5"; coco.TextSize = 90; coco.Font = Enum.Font.GothamBold; coco.Parent = panel
	Instance.new("UICorner", coco).CornerRadius = UDim.new(1,0)
	local cnt = Instance.new("TextLabel"); cnt.Size = UDim2.new(1,-20,0,26); cnt.Position = UDim2.new(0,10,1,-58); cnt.BackgroundTransparency = 1
	cnt.Font = Enum.Font.GothamBold; cnt.TextSize = 18; cnt.TextColor3 = Color3.new(1,1,1); cnt.Text = "0"; cnt.Parent = panel
	local barBg = Instance.new("Frame"); barBg.Size = UDim2.new(1,-20,0,14); barBg.Position = UDim2.new(0,10,1,-26); barBg.BackgroundColor3 = Color3.fromRGB(15,40,90); barBg.Parent = panel
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0,6)
	local bar = Instance.new("Frame"); bar.Size = UDim2.new(1,0,1,0); bar.BackgroundColor3 = Color3.fromRGB(80,220,80); bar.Parent = barBg
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0,6)
	crackUI = { gui = g, coco = coco, cnt = cnt, bar = bar, hint = hintL }
	return crackUI
end
-- Per-coconut difficulty for the TUG-OF-WAR crack: drain = how fast the bar falls/sec; fill = how much each
-- tap pushes it up. Success when the bar reaches the TOP (need taps/sec > drain/fill). Tuned EASIER than the
-- old tap-count -- a few easy, a couple medium, a couple hard; even the hard ones are doable by a fast tapper.
local CRACK_DIFFICULTY = {
	[1] = { drain = 0.35, fill = 0.22, name = "Easy" },   -- need >~1.6 taps/sec
	[2] = { drain = 0.35, fill = 0.22, name = "Easy" },
	[3] = { drain = 0.45, fill = 0.20, name = "Easy" },   -- ~2.3/sec
	[4] = { drain = 0.55, fill = 0.18, name = "Medium" }, -- ~3.1/sec
	[5] = { drain = 0.58, fill = 0.17, name = "Medium" },
	[6] = { drain = 0.60, fill = 0.17, name = "Hard" },   -- ~3.5 taps/sec (toned down: comfy one-finger on mobile)
	[7] = { drain = 0.63, fill = 0.17, name = "Hard" },   -- ~3.7 taps/sec (hardest, still mobile-doable -- a touch above medium)
}

-- TUG-OF-WAR crack: the fill bar constantly DRAINS down; each tap pushes it UP. Fill it to the TOP to crack.
-- Forgiving -- if it drains all the way to empty the GUI just closes (retry), no hard fail.
local function openCrackMinigame(onCracked, diff)
	if crackBusy then return end
	crackBusy = true
	local ui = ensureCrackUI()
	diff = diff or { drain = 0.5, fill = 0.18, name = "" }
	local fill = 0.28 -- start partway up so it isn't instantly empty
	local done = false
	local started = false -- the bar holds steady until the FIRST tap; drain only begins then (a moment to react)
	ui.hint.Text = "Tap to FILL the bar before it drains!"
	ui.cnt.Text = "Crack it!" -- NO difficulty shown to the player (the tier still varies under the hood)
	ui.bar.Size = UDim2.new(fill, 0, 1, 0); ui.bar.BackgroundColor3 = Color3.fromRGB(80,220,80)
	ui.gui.Enabled = true
	local conn
	local function finish(success)
		if done then return end
		done = true; if conn then conn:Disconnect() end
		ui.gui.Enabled = false; crackBusy = false
		if success then onCracked() end
	end
	conn = ui.coco.MouseButton1Click:Connect(function()
		if done then return end
		started = true -- first tap arms the drain (the tug-of-war is now on)
		fill = math.min(1, fill + diff.fill)
		ui.bar.Size = UDim2.new(fill, 0, 1, 0)
		pcall(function() game:GetService("TweenService"):Create(ui.coco, TweenInfo.new(0.05), { Rotation = math.random(-12,12) }):Play() end)
		if fill >= 1 then finish(true) end
	end)
	task.spawn(function()
		local last = os.clock()
		while not done do
			local now = os.clock(); local dt = now - last; last = now -- keep `last` current even while paused (no drain accrues before the first tap)
			if started then -- the bar only starts draining AGAINST the player after their first tap
				fill = math.max(0, fill - diff.drain * dt)
				ui.bar.Size = UDim2.new(fill, 0, 1, 0)
				ui.bar.BackgroundColor3 = (fill > 0.5) and Color3.fromRGB(80,220,80) or Color3.fromRGB(235,170,55)
				if fill <= 0 then ui.hint.Text = "Drained! Try again."; task.wait(0.35); finish(false); break end
			end
			task.wait()
		end
	end)
end

-- CAVE KEY reveal: a key pops up centre-screen, holds, then floats away + fades.
local function showKeyReveal()
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "CaveKeyReveal"; g.ResetOnSpawn = false; g.DisplayOrder = 95; g.Parent = pgui
	local f = Instance.new("Frame"); f.Size = UDim2.new(0,40,0,24); f.Position = UDim2.new(0.5,0,0.4,0); f.AnchorPoint = Vector2.new(0.5,0.5)
	f.BackgroundColor3 = Color3.fromRGB(25,90,185); f.BackgroundTransparency = 0.05; f.Parent = g
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,16); local s = Instance.new("UIStroke", f); s.Color = Color3.fromRGB(255,215,0); s.Thickness = 3
	local key = Instance.new("TextLabel"); key.Size = UDim2.new(1,0,0,80); key.Position = UDim2.new(0,0,0,12); key.BackgroundTransparency = 1
	key.Font = Enum.Font.GothamBold; key.TextSize = 56; key.Text = "\xF0\x9F\x97\x9D\xEF\xB8\x8F"; key.Parent = f
	local txt = Instance.new("TextLabel"); txt.Size = UDim2.new(1,-16,0,40); txt.Position = UDim2.new(0,8,1,-52); txt.BackgroundTransparency = 1
	txt.Font = Enum.Font.GothamBold; txt.TextSize = 20; txt.TextColor3 = Color3.fromRGB(255,215,0); txt.Text = "You got the Cave Key!"; txt.Parent = f
	local TW = game:GetService("TweenService")
	TW:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0,260,0,150)}):Play()
	task.delay(2.0, function()
		TW:Create(f, TweenInfo.new(0.5), {Position = UDim2.new(0.5,0,0.25,0), BackgroundTransparency = 1}):Play()
		TW:Create(s, TweenInfo.new(0.5), {Transparency = 1}):Play()
		TW:Create(key, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
		TW:Create(txt, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
		task.delay(0.6, function() g:Destroy() end)
	end)
	print("[Pet][UI] cave key reveal shown")
end

-- Build the COCONUT quest world: 7 crackable coconuts + the chest (key-gated) that reveals the egg on open.
local function buildCoconutWorld(petId, def, positions)
	local st = petState[petId]
	if st.built then return end
	st.built = true; st.isCrack = true
	local pieces = positions.pieces or {}
	-- 7 coconuts (hidden until applyState confirms !owns). Hold E -> crack minigame -> count + server collect.
	for i = 1, #def.pieceMarkers do
		local pos = pieces[i]
		if typeof(pos) == "Vector3" then
			st.hintAnchor = st.hintAnchor or pos -- the on-landing hint anchors at a COCONUT (on the island), not the cave chest
			local coco = Instance.new("Model"); coco.Name = "Coconut"..i
			local b = newPart(coco, "Coco", Enum.PartType.Ball, Vector3.new(1.6,1.6,1.6), Color3.fromRGB(112,72,42), CFrame.new(pos), Enum.Material.Wood)
			coco.PrimaryPart = b
			for _, sp in ipairs({ {0,0.2,0.65}, {-0.3,-0.2,0.6}, {0.3,-0.2,0.6} }) do
				newPart(coco, "Spot", Enum.PartType.Ball, Vector3.new(0.3,0.3,0.2), Color3.fromRGB(66,40,22), CFrame.new(pos) * CFrame.new(sp[1],sp[2],sp[3]))
			end
			local pp = addPrompt(b, "Crack Coconut", "Coconut", function()
				if st.collected[i] or st.owns then return end
				openCrackMinigame(function()
					if st.collected[i] or st.owns then return end
					st.collected[i] = true
					local count = 0; for _, v in pairs(st.collected) do if v then count = count + 1 end end
					setVisible(coco, false)
					floatText(pos + Vector3.new(0,2,0), "Coconut cracked! "..count.."/"..#def.pieceMarkers)
					pcall(function() PetCollectEvent:FireServer(petId, i) end)
					-- the 7th distinct crack (in ANY order) grants the CAVE KEY -> reveal + unlock the chest
					if count >= #def.pieceMarkers and not st.hasKey then
						st.hasKey = true
						showKeyReveal()
						if st.chestGlow then st.chestGlow(true) end
						print("[Pet] "..player.Name.." cracked 7/7 -> Cave Key granted")
					end
				end, CRACK_DIFFICULTY[i])
			end)
			pp.HoldDuration = 0.5 -- HOLD E to start the minigame
			st.pieces[i] = coco
			setVisible(coco, false)
			print(string.format("[Pet][DIAG] built coconut %d (%s) at (%.0f,%.0f,%.0f)", i, (CRACK_DIFFICULTY[i] and CRACK_DIFFICULTY[i].name or "?"), pos.X, pos.Y, pos.Z))
		else
			warn("[Pet][DIAG] coconut "..i.." position MISSING for "..petId)
		end
	end
	-- CHEST in the cave (always visible to non-owners). Key-gated prompt -> opens -> reveals the egg.
	local eggPos = positions.egg
	if typeof(eggPos) ~= "Vector3" then warn("[Pet][DIAG] chest position MISSING for "..petId); return end
	st.eggPos = eggPos
	-- rotate the WHOLE chest 130 deg CCW about Y (positive Y = CCW from above) so it faces the player's approach
	local chestRot = CFrame.Angles(0, math.rad(130), 0)
	local function chestCF(ox, oy, oz) return CFrame.new(eggPos) * chestRot * CFrame.new(ox, oy, oz) end
	local chest = Instance.new("Model"); chest.Name = petId.."Chest"
	local base = newPart(chest, "ChestBase", Enum.PartType.Block, Vector3.new(4,2.2,3), Color3.fromRGB(120,78,40), chestCF(0,1.1,0), Enum.Material.Wood)
	chest.PrimaryPart = base
	newPart(chest, "Band", Enum.PartType.Block, Vector3.new(4.1,0.4,3.1), Color3.fromRGB(70,70,80), chestCF(0,0.6,0), Enum.Material.Metal)
	newPart(chest, "Band", Enum.PartType.Block, Vector3.new(4.1,0.4,3.1), Color3.fromRGB(70,70,80), chestCF(0,1.7,0), Enum.Material.Metal)
	local lid = Instance.new("Model"); lid.Name = "Lid"; lid.Parent = chest
	local lidHinge = chestCF(0, 2.2, -1.5).Position -- back-top hinge (in the rotated frame)
	local lidPart = newPart(lid, "ChestLid", Enum.PartType.Block, Vector3.new(4,1.2,3), Color3.fromRGB(138,92,50), chestCF(0,2.6,0), Enum.Material.Wood)
	lid.PrimaryPart = lidPart
	newPart(lid, "Lock", Enum.PartType.Block, Vector3.new(0.7,0.9,0.4), Color3.fromRGB(220,190,60), chestCF(0,2.1,1.55), Enum.Material.Metal)
	chest.Parent = Workspace
	st.chest = chest
	-- toggle a gold glow on the chest once the player has the Cave Key (used by applyState)
	st.chestGlow = function(on)
		if on and not st.chestHl then
			local hl = Instance.new("Highlight"); hl.Name = "ChestGlow"; hl.FillColor = Color3.fromRGB(255,225,120); hl.FillTransparency = 0.6
			hl.OutlineColor = Color3.fromRGB(255,215,0); hl.Adornee = chest; hl.Parent = chest; st.chestHl = hl
		elseif not on and st.chestHl then st.chestHl:Destroy(); st.chestHl = nil end
	end
	-- reveal the EGG (themed coconut egg) above the open chest, with the hatch prompt
	local function revealEgg()
		if st.egg then return end
		local egg = Instance.new("Model"); egg.Name = petId.."Egg"
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(120,80,46), nil)
		local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Scale = Vector3.new(3.0,4.0,3.0); m.Parent = shell
		visual.PrimaryPart = shell
		for _, sp in ipairs({ {0,0.4,1.35}, {-0.55,-0.2,1.25}, {0.55,-0.2,1.25} }) do
			newPart(visual, "Spot", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.35), Color3.fromRGB(66,40,22), CFrame.new(sp[1],sp[2],sp[3]))
		end
		st.eggBaseCF = CFrame.new(eggPos + Vector3.new(0, 3.6, 0))
		st.eggVisual = visual; visual:PivotTo(st.eggBaseCF)
		st.egg = egg; egg.Parent = Workspace
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(255,235,150); hl.FillTransparency = 0.55; hl.OutlineColor = Color3.fromRGB(255,215,0); hl.Adornee = visual; hl.Parent = egg
		addPrompt(shell, "Hatch", "Coconut Egg", function()
			if st.owns or st.hatching then return end
			if hatchEgg then hatchEgg(petId, def) end
		end)
		task.spawn(function()
			local t = 0
			while st.egg do t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.3, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end)
				end
				task.wait(0.05)
			end
		end)
	end
	-- open the chest: rotate the lid up about its hinge + sparkle, then reveal the egg
	local function openChest()
		pcall(function()
			local TW = game:GetService("TweenService")
			local startCF = lid:GetPivot()
			local nv = Instance.new("NumberValue"); nv.Value = 0
			local hingeFrame = CFrame.new(lidHinge) * chestRot -- pitch about the chest's LOCAL X (the hinge), so it opens UP relative to the rotated chest
			nv:GetPropertyChangedSignal("Value"):Connect(function()
				pcall(function() lid:PivotTo(hingeFrame * CFrame.Angles(math.rad(-100*nv.Value),0,0) * hingeFrame:Inverse() * startCF) end)
			end)
			TW:Create(nv, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Value = 1}):Play()
		end)
		pcall(function()
			local fx = Instance.new("Part"); fx.Anchored = true; fx.CanCollide = false; fx.CanQuery = false; fx.Transparency = 1; fx.Size = Vector3.new(1,1,1); fx.CFrame = CFrame.new(eggPos + Vector3.new(0,2.5,0)); fx.Parent = Workspace
			local em = Instance.new("ParticleEmitter"); em.Texture = "rbxasset://textures/particles/sparkles_main.dds"; em.Color = ColorSequence.new(Color3.fromRGB(255,235,150))
			em.Lifetime = NumberRange.new(0.5,1.0); em.Speed = NumberRange.new(4,10); em.SpreadAngle = Vector2.new(180,180); em.Rate = 0; em.Size = NumberSequence.new(1.2); em.LightEmission = 0.9; em.Parent = fx
			em:Emit(40); game:GetService("Debris"):AddItem(fx, 1.2)
		end)
		task.delay(0.5, revealEgg)
	end
	-- the key-gated chest prompt
	local prompt
	prompt = addPrompt(base, "Use Cave Key", "Treasure Chest", function()
		if st.owns or st.chestOpened then return end
		if not (st.hasKey or (st.uiFound or 0) >= #def.pieceMarkers) then -- locked until the Cave Key is earned (7/7)
			floatText(eggPos + Vector3.new(0,3.2,0), "Locked \xE2\x80\x94 find the Cave Key")
			print("[Pet] "..player.Name.." opened the chest blocked (no key)")
			return
		end
		st.chestOpened = true
		prompt.Enabled = false -- REMOVE the chest prompt the moment it opens, so it never overlaps the egg's hatch prompt
		print("[Pet] "..player.Name.." opened the chest (had key)")
		openChest() -- the egg's Hatch prompt appears ~0.5s later (revealEgg), after this one is already off -> only one prompt active
	end)
	prompt.HoldDuration = 0.4
	print(string.format("[Pet][DIAG] built coconut chest at (%.0f,%.0f,%.0f)", eggPos.X, eggPos.Y, eggPos.Z))
end

-- ============================================================================================
-- POPCORN SHEEP QUEST (questType "film-reels"). Movie-theater themed multi-stage quest: find 6 FILM REELS
-- -> LOAD them at the PROJECTOR -> a mini-movie plays on the SCREEN (flicker -> egg falls/bounces ->
-- "NEW PET!") -> the egg materializes in a SPOTLIGHT at PopcornEggSpot -> hatch -> the Popcorn Sheep
-- follows. Reuses the same server collect/claim/inventory + the shared HATCH flow. Cosmetic-only.
-- ============================================================================================

-- ===== FILM REEL MINIGAME: a SPINNING/SWEEPING METER (deliberately DIFFERENT from the coconut tug-of-war).
-- A marker sweeps back and forth across a track with a green TARGET ZONE; tap STOP to halt it. Stop inside the
-- zone -> the reel is collected; miss -> the sweep keeps going so you can try again (not punishing). Per reel,
-- with the zone shrinking + the sweep speeding up for later reels. Single-tap = mobile-friendly. Cosmetic-only.
local spinUI, spinBusy = nil, false
local function ensureSpinUI()
	if spinUI then return spinUI end
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "FilmReelSpinGui"; g.ResetOnSpawn = false; g.DisplayOrder = 90; g.Enabled = false; g.Parent = pgui
	local film = Instance.new("Frame"); film.Size = UDim2.new(1,0,1,0); film.BackgroundColor3 = Color3.new(0,0,0); film.BackgroundTransparency = 0.5; film.Active = true; film.Parent = g
	local panel = Instance.new("Frame"); panel.Size = UDim2.new(0,360,0,240); panel.Position = UDim2.new(0.5,0,0.5,0); panel.AnchorPoint = Vector2.new(0.5,0.5)
	panel.BackgroundColor3 = Color3.fromRGB(25,90,185); panel.Parent = g
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16); local ps = Instance.new("UIStroke", panel); ps.Color = Color3.new(1,1,1); ps.Thickness = 3
	local titl = Instance.new("TextLabel"); titl.Size = UDim2.new(1,-20,0,30); titl.Position = UDim2.new(0,10,0,10); titl.BackgroundTransparency = 1
	titl.Font = Enum.Font.GothamBold; titl.TextSize = 22; titl.TextColor3 = Color3.fromRGB(255,215,0); titl.Text = "STOP THE REEL!"; titl.Parent = panel
	local hintL = Instance.new("TextLabel"); hintL.Size = UDim2.new(1,-20,0,18); hintL.Position = UDim2.new(0,10,0,42); hintL.BackgroundTransparency = 1
	hintL.Font = Enum.Font.Gotham; hintL.TextSize = 13; hintL.TextColor3 = Color3.new(1,1,1); hintL.Text = "Tap STOP when the marker is in the green zone!"; hintL.Parent = panel
	-- the TRACK (a horizontal bar) with the green target ZONE + the sweeping MARKER
	local track = Instance.new("Frame"); track.Size = UDim2.new(1,-40,0,34); track.Position = UDim2.new(0.5,0,0,98); track.AnchorPoint = Vector2.new(0.5,0)
	track.BackgroundColor3 = Color3.fromRGB(15,40,90); track.Parent = panel; Instance.new("UICorner", track).CornerRadius = UDim.new(0,8)
	local zone = Instance.new("Frame"); zone.BackgroundColor3 = Color3.fromRGB(70,210,90); zone.BorderSizePixel = 0; zone.Parent = track
	Instance.new("UICorner", zone).CornerRadius = UDim.new(0,6)
	local marker = Instance.new("Frame"); marker.Size = UDim2.new(0,8,1,8); marker.AnchorPoint = Vector2.new(0.5,0.5); marker.Position = UDim2.new(0,0,0.5,0)
	marker.BackgroundColor3 = Color3.fromRGB(255,230,80); marker.ZIndex = 2; marker.Parent = track
	Instance.new("UICorner", marker).CornerRadius = UDim.new(0,3); local ms = Instance.new("UIStroke", marker); ms.Color = Color3.new(0,0,0); ms.Thickness = 1
	local stop = Instance.new("TextButton"); stop.Size = UDim2.new(0,180,0,48); stop.Position = UDim2.new(0.5,0,1,-18); stop.AnchorPoint = Vector2.new(0.5,1)
	stop.BackgroundColor3 = Color3.fromRGB(220,60,60); stop.Text = "STOP"; stop.Font = Enum.Font.GothamBold; stop.TextSize = 24; stop.TextColor3 = Color3.new(1,1,1); stop.Parent = panel
	Instance.new("UICorner", stop).CornerRadius = UDim.new(0,10); local ss = Instance.new("UIStroke", stop); ss.Color = Color3.new(0,0,0); ss.Thickness = 2
	local close = Instance.new("TextButton"); close.Size = UDim2.new(0,30,0,30); close.Position = UDim2.new(1,-38,0,8); close.BackgroundColor3 = Color3.fromRGB(120,40,40)
	close.Text = "X"; close.Font = Enum.Font.GothamBold; close.TextSize = 16; close.TextColor3 = Color3.new(1,1,1); close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0,8)
	spinUI = { gui = g, panel = panel, track = track, zone = zone, marker = marker, stop = stop, close = close, hint = hintL }
	return spinUI
end
-- per-reel difficulty: zone = target width (fraction of the track), speed = sweeps/sec. Earlier reels are easy;
-- later reels have a smaller zone + a faster sweep. Even reel 6 stays single-tap-doable on mobile.
local SPIN_DIFFICULTY = {
	[1] = { zone = 0.34, speed = 0.55 },
	[2] = { zone = 0.32, speed = 0.62 },
	[3] = { zone = 0.28, speed = 0.72 },
	[4] = { zone = 0.26, speed = 0.84 },
	[5] = { zone = 0.23, speed = 0.96 },
	[6] = { zone = 0.20, speed = 1.10 },
}
local function openSpinMinigame(onSuccess, diff)
	if spinBusy then return end
	spinBusy = true
	local ui = ensureSpinUI()
	diff = diff or { zone = 0.28, speed = 0.8 }
	local zoneW = diff.zone
	local zoneX = 0.04 + math.random() * math.max(0, 0.92 - zoneW) -- random target position, fully inside the track
	ui.zone.Size = UDim2.new(zoneW, 0, 1, 0); ui.zone.Position = UDim2.new(zoneX, 0, 0, 0)
	ui.hint.Text = "Tap STOP when the marker is in the green zone!"
	ui.marker.BackgroundColor3 = Color3.fromRGB(255,230,80)
	ui.gui.Enabled = true
	local done = false
	local pos = math.random()                      -- marker start (0..1)
	local dir = (math.random() < 0.5) and 1 or -1  -- random initial direction
	local conns = {}
	local function finish(success)
		if done then return end
		done = true
		for _, c in ipairs(conns) do c:Disconnect() end
		ui.gui.Enabled = false; spinBusy = false
		if success then onSuccess() end
	end
	conns[#conns+1] = ui.stop.MouseButton1Click:Connect(function()
		if done then return end
		if pos >= zoneX and pos <= (zoneX + zoneW) then
			ui.marker.BackgroundColor3 = Color3.fromRGB(90,235,110); ui.hint.Text = "Nice \xE2\x80\x94 reel grabbed!"
			task.wait(0.25); finish(true)
		else
			ui.marker.BackgroundColor3 = Color3.fromRGB(235,90,80); ui.hint.Text = "Missed! Keep going \xE2\x80\x94 tap in the green."
			task.delay(0.45, function() if not done then ui.marker.BackgroundColor3 = Color3.fromRGB(255,230,80) end end)
			-- NOT punishing: the sweep simply continues so the player can try again
		end
	end)
	conns[#conns+1] = ui.close.MouseButton1Click:Connect(function() finish(false) end)
	task.spawn(function()
		local last = os.clock()
		while not done do
			local now = os.clock(); local dt = now - last; last = now
			pos = pos + dir * diff.speed * dt
			if pos >= 1 then pos = 1; dir = -1 elseif pos <= 0 then pos = 0; dir = 1 end -- ping-pong sweep
			ui.marker.Position = UDim2.new(pos, 0, 0.5, 0)
			task.wait()
		end
	end)
end

-- a low-poly FILM REEL collectible: a flat dark disc (round face up) + a raised hub + a few holes. Built in
-- place at `pos` (with an optional yaw) -- like the coconuts -- so the flat orientation isn't lost to PivotTo.
local function buildFilmReel(pos, yaw)
	local model = Instance.new("Model"); model.Name = "FilmReel"
	local DARK, RIM, HUB, HOLE = Color3.fromRGB(28,28,32), Color3.fromRGB(58,58,66), Color3.fromRGB(82,82,92), Color3.fromRGB(12,12,15)
	local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder's round faces are on local X; rotate X->Y so the disc lies FLAT (face up)
	local frame = CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0)
	local function at(ox, oy, oz) return frame * CFrame.new(ox, oy, oz) * FLAT end -- oy = up (face normal); ox/oz spread on the disc
	local disc = newPart(model, "Reel", Enum.PartType.Cylinder, Vector3.new(0.5,2.6,2.6), DARK, at(0,0,0))
	model.PrimaryPart = disc
	newPart(model, "Rim", Enum.PartType.Cylinder, Vector3.new(0.42,2.9,2.9), RIM, at(0,-0.04,0))     -- classic reel edge
	newPart(model, "Hub", Enum.PartType.Cylinder, Vector3.new(0.7,0.9,0.9), HUB, at(0,0.16,0))        -- raised centre hub
	newPart(model, "HubHole", Enum.PartType.Cylinder, Vector3.new(0.74,0.34,0.34), HOLE, at(0,0.2,0))
	for k = 1, 5 do -- 5 round holes in a ring (the "couple of smaller circles" look)
		local a = (k-1) * (2*math.pi/5)
		newPart(model, "Hole", Enum.PartType.Cylinder, Vector3.new(0.56,0.66,0.66), HOLE, at(math.sin(a)*0.95, 0.18, math.cos(a)*0.95))
	end
	return model
end

-- placeholder POPCORN SHEEP follower: a fluffy off-white popcorn-wool body (cluster of bumps), a small face,
-- little legs, cute eyes. Registers parts into petAnims (body/head/leg/tail roles + eye) so the existing
-- animator gives it idle bob, blink, leg gait, head/tail sway. Refine the looks later. Cosmetic-only.
local function buildPopcornSheep(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "PopcornSheep"
	local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye, mat)
		local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s), mat)
		parts[#parts+1] = { part = p, base = p.CFrame, baseSize = p.Size, role = role or "body", eye = eye }
		return p
	end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1; model.PrimaryPart = root -- +X = front (the follow loop yaws +X toward travel)
	local WOOL, FACE, LEG, DARK = Color3.fromRGB(252,248,228), Color3.fromRGB(58,46,40), Color3.fromRGB(70,56,46), Color3.fromRGB(24,24,24)
	-- BODY core + a cluster of popcorn-wool bumps all over it
	mk("Body", Enum.PartType.Ball, 2.4,2.0,2.2, WOOL, 0,0,0, "body")
	for _, b in ipairs({ {0.8,0.9,0.6},{0.6,1.0,-0.6},{-0.2,1.15,0.0},{-0.9,0.85,0.5},{-0.9,0.7,-0.5},{0.15,0.55,1.0},
	                     {0.15,0.5,-1.0},{-0.5,0.2,0.98},{-0.5,0.1,-0.98},{0.7,0.0,0.92},{0.7,-0.1,-0.92},{-1.05,0.05,0.0} }) do
		local r = 0.72 + math.abs(b[2])*0.04
		mk("Wool", Enum.PartType.Ball, r,r,r, WOOL, b[1],b[2],b[3], "body")
	end
	-- HEAD (small dark face at the front) + a wool tuft + ears
	mk("Head", Enum.PartType.Ball, 1.0,1.05,0.95, FACE, 1.25,0.35,0, "head")
	mk("Tuft", Enum.PartType.Ball, 0.78,0.7,0.78, WOOL, 1.12,1.05,0, "head")
	mk("Ear", Enum.PartType.Ball, 0.3,0.52,0.22, FACE, 1.0,0.7,0.62, "head")
	mk("Ear", Enum.PartType.Ball, 0.3,0.52,0.22, FACE, 1.0,0.7,-0.62, "head")
	for _, ez in ipairs({0.32, -0.32}) do -- cute eyes
		mk("Eye", Enum.PartType.Ball, 0.3,0.38,0.26, Color3.fromRGB(245,245,245), 1.74,0.45,ez, "head", true)
		mk("Pupil", Enum.PartType.Ball, 0.16,0.2,0.16, DARK, 1.9,0.42,ez, "head", true)
	end
	mk("Snout", Enum.PartType.Ball, 0.52,0.4,0.56, Color3.fromRGB(80,66,56), 1.78,0.06,0, "head")
	for _, lp in ipairs({ {0.8,0.7},{0.8,-0.7},{-0.7,0.7},{-0.7,-0.7} }) do -- 4 little legs
		mk("Leg", Enum.PartType.Ball, 0.42,1.0,0.42, LEG, lp[1],-1.4,lp[2], "leg")
	end
	mk("Tail", Enum.PartType.Ball, 0.55,0.55,0.55, WOOL, -1.3,0.3,0, "tail") -- tiny tail tuft
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- placeholder BUTTER DUCK follower: a glossy golden duck (rounded body, head + flat bill, little wings, cute
-- eyes). Registers parts (body/head/wing->tail/leg roles + eye) so the existing animator gives it idle bob,
-- blink, wing/tail flap, leg paddle. Refine the looks later. Cosmetic-only.
local function buildButterDuck(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "ButterDuck"
	local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye, mat)
		local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s), mat)
		parts[#parts+1] = { part = p, base = p.CFrame, baseSize = p.Size, role = role or "body", eye = eye }
		return p
	end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1; model.PrimaryPart = root -- +X = front (the follow loop yaws +X toward travel)
	local BUTTER, DEEP, BILL, DARK = Color3.fromRGB(248,214,96), Color3.fromRGB(232,188,70), Color3.fromRGB(244,150,40), Color3.fromRGB(28,24,18)
	mk("Body", Enum.PartType.Ball, 2.5,2.0,2.1, BUTTER, 0,0,0, "body")          -- rounded duck body
	mk("Rump", Enum.PartType.Ball, 1.1,1.0,1.0, BUTTER, -1.25,0.35,0, "tail")    -- upturned tail end
	mk("TailTip", Enum.PartType.Ball, 0.5,0.5,0.7, DEEP, -1.85,0.6,0, "tail")
	mk("Neck", Enum.PartType.Ball, 0.95,1.2,0.95, BUTTER, 1.05,0.85,0, "head")   -- neck sweeping up
	mk("Head", Enum.PartType.Ball, 1.15,1.15,1.1, BUTTER, 1.5,1.6,0, "head")     -- round head, up front
	mk("Bill", Enum.PartType.Ball, 0.95,0.35,0.8, BILL, 2.2,1.45,0, "head")      -- flat duck bill
	mk("BillTip", Enum.PartType.Ball, 0.55,0.28,0.66, BILL, 2.55,1.4,0, "head")
	for _, ez in ipairs({0.42, -0.42}) do -- cute eyes on the head front
		mk("Eye", Enum.PartType.Ball, 0.34,0.4,0.3, Color3.fromRGB(245,245,245), 1.92,1.78,ez, "head", true)
		mk("Pupil", Enum.PartType.Ball, 0.18,0.22,0.18, DARK, 2.1,1.76,ez, "head", true)
	end
	for _, ws in ipairs({1, -1}) do mk("Wing", Enum.PartType.Ball, 1.3,0.7,0.5, DEEP, -0.1,0.2,ws*1.15, "tail") end -- little side wings (flap with the tail role)
	for _, ls in ipairs({0.55, -0.55}) do mk("Leg", Enum.PartType.Ball, 0.4,0.7,0.5, BILL, 0.2,-1.35,ls, "leg") end  -- two webbed legs
	-- glossy buttery sheen on the solid body parts
	for _, e in ipairs(parts) do if e.part.Transparency < 1 then e.part.Reflectance = math.max(e.part.Reflectance, 0.08) end end
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- placeholder BURRITO ARMADILLO follower: a rounded tan armadillo with a banded burrito/tortilla shell back
-- (toasted bands arcing over the back), a pale belly, a pointy snout, little legs + tail, cute eyes. Registers
-- parts (body/head/leg/tail roles + eye) so the existing animator gives it idle bob, blink, leg gait, head/tail
-- sway. Placeholder -- refine the looks later. Cosmetic-only.
local function buildBurritoArmadillo(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "BurritoArmadillo"
	local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye, mat)
		local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s), mat)
		parts[#parts+1] = { part = p, base = p.CFrame, baseSize = p.Size, role = role or "body", eye = eye }
		return p
	end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1; model.PrimaryPart = root -- +X = front (the follow loop yaws +X toward travel)
	local TORT, TOAST, BELLY, SNT, DARK = Color3.fromRGB(214,170,110), Color3.fromRGB(176,118,64), Color3.fromRGB(236,212,170), Color3.fromRGB(150,96,56), Color3.fromRGB(26,20,16)
	mk("Body", Enum.PartType.Ball, 2.6,2.0,2.2, TORT, 0,0,0, "body")                 -- rounded tan body
	for i = -2, 2 do mk("Band", Enum.PartType.Ball, 0.42,1.75,2.05, TOAST, i*0.5,0.55,0, "body") end -- toasted tortilla bands over the back
	mk("Belly", Enum.PartType.Ball, 2.2,1.0,1.9, BELLY, 0.1,-0.7,0, "body")          -- pale belly
	mk("Head", Enum.PartType.Ball, 1.1,1.05,1.0, TORT, 1.5,0.2,0, "head")
	mk("Snout", Enum.PartType.Ball, 0.85,0.5,0.5, SNT, 2.25,-0.05,0, "head")         -- pointy snout
	mk("SnoutTip", Enum.PartType.Ball, 0.32,0.3,0.34, DARK, 2.72,-0.05,0, "head")
	mk("Ear", Enum.PartType.Ball, 0.22,0.5,0.16, SNT, 1.15,0.85,0.42, "head")
	mk("Ear", Enum.PartType.Ball, 0.22,0.5,0.16, SNT, 1.15,0.85,-0.42, "head")
	for _, ez in ipairs({0.34,-0.34}) do
		mk("Eye", Enum.PartType.Ball, 0.3,0.36,0.26, Color3.fromRGB(245,245,245), 1.9,0.42,ez, "head", true)
		mk("Pupil", Enum.PartType.Ball, 0.16,0.2,0.16, DARK, 2.05,0.4,ez, "head", true)
	end
	for _, lp in ipairs({ {0.8,0.7},{0.8,-0.7},{-0.7,0.7},{-0.7,-0.7} }) do          -- four little legs
		mk("Leg", Enum.PartType.Ball, 0.42,0.9,0.42, SNT, lp[1],-1.35,lp[2], "leg")
	end
	mk("Tail", Enum.PartType.Ball, 0.7,0.6,0.6, TOAST, -1.5,-0.1,0, "tail")          -- tapering tail
	mk("TailTip", Enum.PartType.Ball, 0.4,0.34,0.34, SNT, -2.0,0.05,0, "tail")
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- the 6 face normals (local space), used to pick which face of the EXISTING screen points at the player.
local FACE_NORMALS = {
	[Enum.NormalId.Front]  = Vector3.new(0,0,-1), [Enum.NormalId.Back]   = Vector3.new(0,0,1),
	[Enum.NormalId.Right]  = Vector3.new(1,0,0),  [Enum.NormalId.Left]   = Vector3.new(-1,0,0),
	[Enum.NormalId.Top]    = Vector3.new(0,1,0),  [Enum.NormalId.Bottom] = Vector3.new(0,-1,0),
}
-- the user's PopcornScreen is normally a single Part; if it's a Model, use its PrimaryPart / biggest BasePart.
local function screenSurfacePart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then
		if inst.PrimaryPart then return inst.PrimaryPart end
		local biggest, bv
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then local v = d.Size.X * d.Size.Y * d.Size.Z; if not bv or v > bv then bv = v; biggest = d end end
		end
		return biggest
	end
	return nil
end
-- CLIENT-side resolve of the real, still-visible PopcornScreen (island-then-Workspace, exact name). Needed
-- because with StreamingEnabled an Instance reference sent over the RemoteFunction arrives nil while island 8 is
-- streamed out -- so the client finds the part itself (the server keeps it in the world, un-hidden). Resolved
-- lazily at show time, when the player is standing right next to it, so it's guaranteed streamed in.
local function findIslandClient(prefix)
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.find(m.Name, prefix, 1, true) then return m end
	end
	return nil
end
local function resolveScreenPart(def)
	local name = (def.extraMarkers and def.extraMarkers.screen) or "PopcornScreen"
	local island = def.islandPrefix and findIslandClient(def.islandPrefix)
	local inst = (island and island:FindFirstChild(name, true)) or Workspace:FindFirstChild(name) or Workspace:FindFirstChild(name, true)
	return screenSurfacePart(inst)
end
local function dumpScreenLike(def)
	print("[Pet][DIAG] PopcornScreen NOT found by client - dump of screen-like parts:")
	local function scan(list, where)
		for _, m in ipairs(list) do
			local n = m.Name:lower()
			if n:find("screen") or n:find("popcorn") then
				print("[Pet][DIAG] screen-like: '"..m.Name.."' ("..m.ClassName..") at "..m:GetFullName().." ["..where.."]")
			end
		end
	end
	local island = def.islandPrefix and findIslandClient(def.islandPrefix)
	pcall(function() if island then scan(island:GetDescendants(), "island") end end)
	pcall(function() scan(Workspace:GetChildren(), "Workspace top") end)
end

-- Build the POPCORN quest world: 6 film reels + a projector (Load Reels) + a screen (mini-movie) + the
-- spotlight egg at PopcornEggSpot. Reuses the shared hatch flow (hatchEgg) once the egg is revealed.
local function buildPopcornWorld(petId, def, positions)
	local st = petState[petId]
	if st.built then return end
	st.built = true; st.isFilm = true
	local pieces = positions.pieces or {}
	local extra  = positions.extra or {}

	-- STAGE 1: 6 FILM REELS (hidden until applyState confirms !owns). E -> take -> count + server collect.
	for i = 1, #def.pieceMarkers do
		local pos = pieces[i]
		if typeof(pos) == "Vector3" then
			st.hintAnchor = st.hintAnchor or pos -- the on-landing hint anchors at a REEL (on the island)
			local reel = buildFilmReel(pos, math.rad(i * 43)) -- built flat, in place, with a varied yaw
			local pp = addPrompt(reel.PrimaryPart, "Take Film Reel", "Film Reel", function()
				if st.collected[i] or st.owns then return end
				openSpinMinigame(function() -- STOP-the-marker timing minigame per reel (not the coconut tap-fill)
					if st.collected[i] or st.owns then return end
					st.collected[i] = true
					local count = 0; for _, v in pairs(st.collected) do if v then count = count + 1 end end
					setVisible(reel, false)
					floatText(pos + Vector3.new(0,2,0), "Film reel "..count.."/"..#def.pieceMarkers.."!")
					pcall(function() PetCollectEvent:FireServer(petId, i) end)
				end, SPIN_DIFFICULTY[i])
			end)
			pp.HoldDuration = 0.4 -- HOLD E to start the spinning-meter minigame
			st.pieces[i] = reel
			setVisible(reel, false)
			print(string.format("[Pet][DIAG] built film reel %d at (%.0f,%.0f,%.0f)", i, pos.X, pos.Y, pos.Z))
		else
			warn("[Pet][DIAG] film reel "..i.." position MISSING for "..petId)
		end
	end

	local eggPos    = positions.egg
	local projPos   = extra.projector
	local screenPos = extra.screen
	if typeof(eggPos) ~= "Vector3" then warn("[Pet][DIAG] PopcornEggSpot position MISSING for "..petId); return end
	st.eggPos = eggPos
	st.filmProps = {}
	-- at 6/6 the on-screen pointer guides to the PROJECTOR (load reels); after the show it points at the egg
	st.pointTarget = (typeof(projPos) == "Vector3") and projPos or eggPos

	-- ===== THE SCREEN: play the mini-movie on the user's EXISTING, still-visible PopcornScreen (NO duplicate
	-- code screen). The client RESOLVES the real screen BY NAME (island-then-Workspace) and remembers the broad
	-- face that points at the play area. With StreamingEnabled the screen may be streamed OUT at join, so this
	-- can fail now -- that's fine: playMovie retries it when the player is standing right at the screen. =====
	local function setupScreen()
		if st.screenPart and st.screenPart.Parent then return true end
		local part = resolveScreenPart(def)
		if not part then return false end
		local sz = part.Size
		local faces -- broad faces lie on the THINNEST axis; pick whichever points toward the egg/player
		if sz.Z <= sz.X and sz.Z <= sz.Y then faces = { Enum.NormalId.Front, Enum.NormalId.Back }
		elseif sz.X <= sz.Y and sz.X <= sz.Z then faces = { Enum.NormalId.Right, Enum.NormalId.Left }
		else faces = { Enum.NormalId.Top, Enum.NormalId.Bottom } end
		local aim = eggPos - part.Position -- the player stands at the egg spot, in front of the screen
		local best, bestDot
		for _, f in ipairs(faces) do
			local n = part.CFrame:VectorToWorldSpace(FACE_NORMALS[f])
			local d = (aim.Magnitude > 0.001) and n:Dot(aim.Unit) or 1
			if not bestDot or d > bestDot then bestDot = d; best = f end
		end
		local fw, fh -- the chosen face's width/height -> a matching canvas aspect (so the movie isn't stretched)
		if best == Enum.NormalId.Front or best == Enum.NormalId.Back then fw, fh = sz.X, sz.Y
		elseif best == Enum.NormalId.Left or best == Enum.NormalId.Right then fw, fh = sz.Z, sz.Y
		else fw, fh = sz.X, sz.Z end
		st.screenPart = part
		st.movieFace = best
		st.movieCanvas = Vector2.new(600, math.clamp(math.floor(600 * fh / math.max(fw, 1)), 150, 900))
		print("[Pet][DIAG] PopcornScreen resolved at "..part:GetFullName()..", attaching mini-movie SurfaceGui to "..best.Name.." face")
		return true
	end
	st.setupScreen = setupScreen
	setupScreen() -- try now; if the screen is streamed out at join this just no-ops -- playMovie retries (+ dumps) when the player is at it

	-- ===== THE PROJECTOR: a client-built prop at the marker, facing the screen + a translucent light BEAM =====
	local projBody
	if typeof(projPos) == "Vector3" then
		local faceTo = (typeof(screenPos) == "Vector3") and screenPos or eggPos
		local pdir = Vector3.new(faceTo.X - projPos.X, 0, faceTo.Z - projPos.Z)
		if pdir.Magnitude < 0.05 then pdir = Vector3.new(0,0,1) end
		local projCF = CFrame.lookAt(projPos, projPos + pdir.Unit) * CFrame.new(0, -1.0, 0) -- -Z points at the screen; net -1.0 (dropped 2.5 then raised 1.5) so the prop rests at the right height
		local proj = Instance.new("Model"); proj.Name = petId.."Projector"
		projBody = newPart(proj, "ProjBody", Enum.PartType.Block, Vector3.new(2.4,1.8,3.4), Color3.fromRGB(42,42,48), projCF * CFrame.new(0,1.4,0), Enum.Material.Metal)
		proj.PrimaryPart = projBody
		newPart(proj, "Lens", Enum.PartType.Cylinder, Vector3.new(1.2,1.1,1.1), Color3.fromRGB(150,210,255), projCF * CFrame.new(0,1.4,-1.9) * CFrame.Angles(0,math.rad(90),0), Enum.Material.Neon)
		newPart(proj, "ReelTop", Enum.PartType.Cylinder, Vector3.new(0.5,1.6,1.6), Color3.fromRGB(28,28,32), projCF * CFrame.new(-0.6,2.6,0.5) * CFrame.Angles(0,0,math.rad(90)))
		newPart(proj, "ReelTop", Enum.PartType.Cylinder, Vector3.new(0.5,1.6,1.6), Color3.fromRGB(28,28,32), projCF * CFrame.new(0.7,2.6,-0.5) * CFrame.Angles(0,0,math.rad(90)))
		newPart(proj, "Stand", Enum.PartType.Block, Vector3.new(0.7,1.4,0.7), Color3.fromRGB(30,30,34), projCF * CFrame.new(0,0.2,0))
		proj.Parent = Workspace
		-- gold glow on the projector (SAME chest-style Highlight) so the player can find it once the reels are
		-- collected; toggled by applyState. st.* fields only -- no new module-scope locals.
		st.projector = proj
		st.projGlow = function(on)
			if on and not st.projHl then
				local hl = Instance.new("Highlight"); hl.Name = "ProjGlow"; hl.FillColor = Color3.fromRGB(255,225,120); hl.FillTransparency = 0.6
				hl.OutlineColor = Color3.fromRGB(255,215,0); hl.Adornee = proj; hl.Parent = proj; st.projHl = hl
			elseif not on and st.projHl then st.projHl:Destroy(); st.projHl = nil end
		end
		-- PERMANENT prop: NOT added to st.filmProps, so applyState never hides it -- the projector always stays
		-- in the world (a fixed prop for any player arriving), even after the quest/movie.
		-- translucent light BEAM from the lens toward the screen -- off until the projector turns ON (movie start),
		-- then it stays lit continuously while the projector is on (the movie / held end frame).
		if typeof(screenPos) == "Vector3" then
			local lensPos = (projCF * CFrame.new(0,1.4,-1.9)).Position
			local mid = (lensPos + screenPos) / 2
			local len = (screenPos - lensPos).Magnitude
			local beam = newPart(Workspace, petId.."Beam", Enum.PartType.Cylinder, Vector3.new(len, 6, 6), Color3.fromRGB(170,210,255), CFrame.lookAt(mid, screenPos) * CFrame.Angles(0,math.rad(90),0), Enum.Material.Neon)
			beam.Transparency = 1 -- off until the projector turns on; then it stays on (never added to filmProps -> never hidden)
			st.beam = beam
		end
		print(string.format("[Pet][DIAG] built projector at (%.0f,%.0f,%.0f)", projPos.X, projPos.Y, projPos.Z))
	else
		warn("[Pet][DIAG] PopcornProjector position MISSING for "..petId)
	end

	-- ===== STAGE 4: reveal the themed popcorn egg in a SPOTLIGHT at PopcornEggSpot (with the Hatch prompt) =====
	local function revealEgg()
		if st.egg then return end
		local egg = Instance.new("Model"); egg.Name = petId.."Egg"
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(245,228,150), nil)
		shell.Reflectance = 0.04
		local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Scale = Vector3.new(3.0,4.0,3.0); m.Parent = shell
		visual.PrimaryPart = shell
		for j = 1, 10 do -- popcorn-kernel bumps hugging the ovoid surface
			local a = (j-1) * (2*math.pi/10)
			local y = math.sin(a*1.7) * 1.0
			local r = 1.35 * math.sqrt(math.max(0, 1 - (y/2.0)^2)) + 0.05
			newPart(visual, "Kernel", Enum.PartType.Ball, Vector3.new(0.55,0.55,0.55), Color3.fromRGB(255,248,212), CFrame.new(math.sin(a)*r, y, math.cos(a)*r))
		end
		st.eggBaseCF = CFrame.new(eggPos + Vector3.new(0, 3.2, 0))
		st.eggVisual = visual; visual:PivotTo(st.eggBaseCF)
		st.egg = egg; egg.Parent = Workspace
		-- SPOTLIGHT: a bright translucent light column down onto the egg + a SpotLight from above + a glow
		local colH = 16
		local col = newPart(egg, "Spotlight", Enum.PartType.Cylinder, Vector3.new(colH, 7, 7), Color3.fromRGB(255,245,205), CFrame.new(eggPos + Vector3.new(0, colH/2 + 1, 0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Neon)
		col.Transparency = 0.72
		local lamp = newPart(egg, "SpotRig", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.new(0,0,0), CFrame.new(eggPos + Vector3.new(0, colH + 2, 0))); lamp.Transparency = 1
		local sl = Instance.new("SpotLight"); sl.Face = Enum.NormalId.Bottom; sl.Angle = 50; sl.Brightness = 6; sl.Range = colH + 10; sl.Color = Color3.fromRGB(255,245,210); sl.Parent = lamp
		local pl = Instance.new("PointLight"); pl.Brightness = 4; pl.Range = 18; pl.Color = Color3.fromRGB(255,240,185); pl.Parent = shell
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(255,245,180); hl.FillTransparency = 0.5; hl.OutlineColor = Color3.fromRGB(255,215,0); hl.Adornee = visual; hl.Parent = egg
		addPrompt(shell, "Hatch", "Popcorn Egg", function()
			if st.owns or st.hatching then return end
			if hatchEgg then hatchEgg(petId, def) end
		end)
		task.spawn(function() -- gentle bob (paused during the hatch); the spotlight stays put
			local t = 0
			while st.egg do t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.28, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end)
				end
				task.wait(0.05)
			end
		end)
		print("[Pet] mini-movie played -> egg in spotlight at PopcornEggSpot")
	end

	-- ===== STAGE 3: the SCREEN comes alive -- a ~30s themed CINEMATIC (studio card -> title -> egg falls
	-- through space -> journey -> lands on the popcorn mountain -> "A NEW FRIEND HATCHES"), then the egg
	-- reveals. The SurfaceGui is NEVER destroyed: it HOLDS the final frame permanently (never blank/white). =====
	local function playMovie()
		local TweenService = game:GetService("TweenService") -- the file-level TweenService local is declared later (lexical scope)
		-- the player is now standing at the projector/screen on island 8, so the screen is definitely streamed in
		-- -- retry the by-name resolve in case it was streamed out at build/join time.
		if not (st.screenPart and st.screenPart.Parent) and st.setupScreen then
			if not st.setupScreen() then dumpScreenLike(def) end
		end
		if not (st.screenPart and st.screenPart.Parent) then revealEgg(); return end -- still no screen: complete the quest anyway
		-- build the movie SurfaceGui for the existing PopcornScreen's player-facing face (right-side-up). It lives
		-- in PlayerGui with Adornee = the screen, so its content SURVIVES StreamingEnabled stream-out/in + respawns
		-- (when the player flies up past island 8). A tiny watcher re-points the Adornee when the screen streams
		-- back in. It is NEVER destroyed -- after the feature it HOLDS the final frame on the screen forever.
		local pgui = player:WaitForChild("PlayerGui")
		local sg = Instance.new("SurfaceGui"); sg.Name = petId.."Movie"; sg.Face = st.movieFace
		sg.CanvasSize = st.movieCanvas; sg.LightInfluence = 0; sg.Brightness = 2; sg.ZOffset = 0.05
		sg.ResetOnSpawn = false; sg.Adornee = st.screenPart; sg.Parent = pgui
		st.movieGui = sg
		task.spawn(function() -- keep the end card pinned to the screen across streaming / respawns (re-link Adornee)
			while st.movieGui and st.movieGui.Parent do
				if not (st.screenPart and st.screenPart.Parent) and st.setupScreen then st.setupScreen() end
				if st.screenPart and st.screenPart.Parent and st.movieGui.Adornee ~= st.screenPart then st.movieGui.Adornee = st.screenPart end
				task.wait(2)
			end
		end)
		local bg = Instance.new("Frame"); bg.Size = UDim2.new(1,0,1,0); bg.BackgroundColor3 = Color3.fromRGB(6,7,16)
		bg.BackgroundTransparency = 1; bg.BorderSizePixel = 0; bg.ClipsDescendants = true; bg.Parent = sg
		local flash = Instance.new("Frame"); flash.Size = UDim2.new(1,0,1,0); flash.BackgroundColor3 = Color3.fromRGB(245,240,255)
		flash.BackgroundTransparency = 1; flash.BorderSizePixel = 0; flash.ZIndex = 50; flash.Parent = bg
		if st.beam then st.beam.Transparency = 0.86 end -- projector beam stays on (the screen is always "playing")

		-- ===== little 2D builders (all parented to bg; one cohesive dark-cinematic palette) =====
		local function tw(o, t, props, style, dir)
			return TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
		end
		local function mkLabel(text, font, size, color)
			local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Font = font; l.TextSize = size; l.TextColor3 = color
			l.Text = text; l.TextStrokeTransparency = 0.3; l.AnchorPoint = Vector2.new(0.5,0.5); l.Parent = bg; return l
		end
		local function mkEgg() -- a cute 2D egg (rounded oval + popcorn speckles + a highlight)
			local e = Instance.new("Frame"); e.AnchorPoint = Vector2.new(0.5,0.5); e.BackgroundColor3 = Color3.fromRGB(248,236,170); e.BorderSizePixel = 0; e.Parent = bg
			Instance.new("UICorner", e).CornerRadius = UDim.new(0.5, 0)
			local es = Instance.new("UIStroke", e); es.Color = Color3.fromRGB(210,180,90); es.Thickness = 2
			for _, p in ipairs({ {0.34,0.32},{0.62,0.5},{0.42,0.66},{0.6,0.28} }) do
				local sp = Instance.new("Frame"); sp.AnchorPoint = Vector2.new(0.5,0.5); sp.Size = UDim2.new(0.16,0,0.12,0)
				sp.Position = UDim2.new(p[1],0,p[2],0); sp.BackgroundColor3 = Color3.fromRGB(255,250,222); sp.BorderSizePixel = 0; sp.Parent = e
				Instance.new("UICorner", sp).CornerRadius = UDim.new(1,0)
			end
			local hl = Instance.new("Frame"); hl.AnchorPoint = Vector2.new(0.5,0.5); hl.Size = UDim2.new(0.22,0,0.16,0)
			hl.Position = UDim2.new(0.32,0,0.26,0); hl.BackgroundColor3 = Color3.fromRGB(255,255,245); hl.BackgroundTransparency = 0.15; hl.BorderSizePixel = 0; hl.Parent = e
			Instance.new("UICorner", hl).CornerRadius = UDim.new(1,0)
			return e
		end
		local function makeStars(n) -- a twinkling star field (each star reverses forever -- alive, never resets)
			for _ = 1, n do
				local s = Instance.new("Frame"); s.AnchorPoint = Vector2.new(0.5,0.5)
				local d = 2 + math.random()*4; s.Size = UDim2.new(0,d,0,d)
				s.Position = UDim2.new(math.random(), 0, math.random()*0.82, 0)
				s.BackgroundColor3 = Color3.fromRGB(255,255,238); s.BorderSizePixel = 0; s.BackgroundTransparency = 0.2 + math.random()*0.5
				Instance.new("UICorner", s).CornerRadius = UDim.new(1,0); s.Parent = bg
				TweenService:Create(s, TweenInfo.new(0.6 + math.random()*1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, math.random()*0.8), {BackgroundTransparency = 0.92}):Play()
			end
		end
		local function mkCloud(x, y, scale)
			local c = Instance.new("Frame"); c.AnchorPoint = Vector2.new(0.5,0.5); c.Size = UDim2.new(0, 130*scale, 0, 46*scale)
			c.Position = UDim2.new(x,0,y,0); c.BackgroundTransparency = 1; c.Parent = bg
			for _, p in ipairs({ {0.5,0.6,1.0},{0.28,0.66,0.7},{0.72,0.66,0.7},{0.4,0.46,0.62},{0.62,0.46,0.62} }) do
				local b = Instance.new("Frame"); b.AnchorPoint = Vector2.new(0.5,0.5); b.Size = UDim2.new(p[3],0,p[3]*1.5,0)
				b.Position = UDim2.new(p[1],0,p[2],0); b.BackgroundColor3 = Color3.fromRGB(210,216,238); b.BackgroundTransparency = 0.3; b.BorderSizePixel = 0; b.Parent = c
				Instance.new("UICorner", b).CornerRadius = UDim.new(1,0)
			end
			return c
		end
		local function shootingStar()
			local s = Instance.new("Frame"); s.AnchorPoint = Vector2.new(0.5,0.5); s.Size = UDim2.new(0,7,0,7)
			s.BackgroundColor3 = Color3.fromRGB(255,255,235); s.BorderSizePixel = 0; s.Position = UDim2.new(-0.1,0, math.random()*0.4, 0); s.Parent = bg
			Instance.new("UICorner", s).CornerRadius = UDim.new(1,0)
			local trail = Instance.new("UIStroke", s); trail.Color = Color3.fromRGB(255,255,225); trail.Thickness = 2; trail.Transparency = 0.2
			tw(s, 0.85, {Position = UDim2.new(1.1,0, math.random()*0.5+0.1, 0), Size = UDim2.new(0,2,0,2)}, Enum.EasingStyle.Quad, Enum.EasingDirection.In):Play()
			task.delay(0.9, function() s:Destroy() end)
		end
		local function mkMountain() -- a popcorn-mountain silhouette (a dark ridge + pale popcorn humps)
			local m = Instance.new("Frame"); m.Size = UDim2.new(1,0,0.34,0); m.Position = UDim2.new(0,0,0.74,0); m.BackgroundTransparency = 1; m.Parent = bg
			local base = Instance.new("Frame"); base.Size = UDim2.new(1,0,0.55,0); base.Position = UDim2.new(0,0,0.55,0); base.BackgroundColor3 = Color3.fromRGB(34,30,54); base.BorderSizePixel = 0; base.Parent = m
			for _, p in ipairs({ {0.5,0.0,0.52},{0.3,0.16,0.36},{0.7,0.16,0.36},{0.15,0.3,0.26},{0.85,0.3,0.26} }) do
				local h = Instance.new("Frame"); h.AnchorPoint = Vector2.new(0.5,0.5); h.Size = UDim2.new(p[3],0,p[3]*1.25,0)
				h.Position = UDim2.new(p[1],0,0.24+p[2],0); h.BackgroundColor3 = Color3.fromRGB(246,240,206); h.BackgroundTransparency = 0.05; h.BorderSizePixel = 0; h.Parent = m
				Instance.new("UICorner", h).CornerRadius = UDim.new(1,0)
			end
			return m
		end
		local function puff(x, y) -- a quick dust/popcorn puff on landing
			for i = 1, 8 do
				local d = Instance.new("Frame"); d.AnchorPoint = Vector2.new(0.5,0.5); d.Size = UDim2.new(0,10,0,10); d.Position = UDim2.new(x,0,y,0)
				d.BackgroundColor3 = Color3.fromRGB(250,245,222); d.BackgroundTransparency = 0.2; d.BorderSizePixel = 0; d.Parent = bg
				Instance.new("UICorner", d).CornerRadius = UDim.new(1,0)
				local a = (i-1)*(math.pi*2/8)
				tw(d, 0.6, {Position = UDim2.new(x+math.cos(a)*0.12,0,y+math.sin(a)*0.1,0), Size = UDim2.new(0,2,0,2), BackgroundTransparency = 1}):Play()
				task.delay(0.65, function() d:Destroy() end)
			end
		end
		local function sparkle(x, y)
			local s = mkLabel("\xE2\x9C\xA8", Enum.Font.GothamBold, 22, Color3.fromRGB(255,246,184))
			s.Size = UDim2.new(0,30,0,30); s.Position = UDim2.new(x,0,y,0); s.TextTransparency = 0.05
			tw(s, 0.7, {TextTransparency = 1, Size = UDim2.new(0,46,0,46)}):Play()
			task.delay(0.75, function() s:Destroy() end)
		end
		local function mkSheep() -- a cute fluffy sheep that peeks up at the finale
			local s = Instance.new("Frame"); s.AnchorPoint = Vector2.new(0.5,0.5); s.Size = UDim2.new(0,96,0,76); s.BackgroundTransparency = 1; s.Parent = bg
			for _, p in ipairs({ {0.5,0.55,0.62},{0.28,0.5,0.46},{0.72,0.5,0.46},{0.38,0.74,0.42},{0.62,0.74,0.42},{0.5,0.28,0.5} }) do
				local b = Instance.new("Frame"); b.AnchorPoint = Vector2.new(0.5,0.5); b.Size = UDim2.new(p[3],0,p[3],0); b.Position = UDim2.new(p[1],0,p[2],0)
				b.BackgroundColor3 = Color3.fromRGB(250,248,236); b.BorderSizePixel = 0; b.Parent = s
				Instance.new("UICorner", b).CornerRadius = UDim.new(1,0)
			end
			local face = Instance.new("Frame"); face.AnchorPoint = Vector2.new(0.5,0.5); face.Size = UDim2.new(0.4,0,0.48,0); face.Position = UDim2.new(0.5,0,0.36,0)
			face.BackgroundColor3 = Color3.fromRGB(54,44,40); face.BorderSizePixel = 0; face.ZIndex = 2; face.Parent = s
			Instance.new("UICorner", face).CornerRadius = UDim.new(0.5,0)
			for _, ex in ipairs({0.4,0.6}) do
				local e = Instance.new("Frame"); e.AnchorPoint = Vector2.new(0.5,0.5); e.Size = UDim2.new(0.1,0,0.13,0); e.Position = UDim2.new(ex,0,0.32,0)
				e.BackgroundColor3 = Color3.fromRGB(245,245,245); e.BorderSizePixel = 0; e.ZIndex = 3; e.Parent = s
				Instance.new("UICorner", e).CornerRadius = UDim.new(1,0)
			end
			return s
		end
		-- ===== cosmic-journey builders (planets, ring/portal, comet, nebula, asteroid, star cluster) =====
		local function mkPlanet(x, y, d, color, ringed)
			local p = Instance.new("Frame"); p.AnchorPoint = Vector2.new(0.5,0.5); p.Size = UDim2.new(0,d,0,d); p.Position = UDim2.new(x,0,y,0)
			p.BackgroundColor3 = color; p.BorderSizePixel = 0; p.Parent = bg
			Instance.new("UICorner", p).CornerRadius = UDim.new(1,0)
			local hl = Instance.new("Frame"); hl.AnchorPoint = Vector2.new(0.5,0.5); hl.Size = UDim2.new(0.42,0,0.42,0); hl.Position = UDim2.new(0.32,0,0.3,0)
			hl.BackgroundColor3 = Color3.fromRGB(255,255,255); hl.BackgroundTransparency = 0.62; hl.BorderSizePixel = 0; hl.Parent = p
			Instance.new("UICorner", hl).CornerRadius = UDim.new(1,0)
			if ringed then
				local r = Instance.new("Frame"); r.AnchorPoint = Vector2.new(0.5,0.5); r.Size = UDim2.new(1.8,0,0.55,0); r.Position = UDim2.new(0.5,0,0.5,0)
				r.BackgroundTransparency = 1; r.Rotation = -22; r.Parent = p
				Instance.new("UICorner", r).CornerRadius = UDim.new(1,0)
				local rs = Instance.new("UIStroke", r); rs.Color = Color3.fromRGB(232,222,180); rs.Thickness = 3; rs.Transparency = 0.15
			end
			return p
		end
		local function mkRing(x, y, d) -- a glowing portal/ring the egg zooms through
			local r = Instance.new("Frame"); r.AnchorPoint = Vector2.new(0.5,0.5); r.Size = UDim2.new(0,d,0,d); r.Position = UDim2.new(x,0,y,0); r.BackgroundTransparency = 1; r.Parent = bg
			Instance.new("UICorner", r).CornerRadius = UDim.new(1,0)
			local s1 = Instance.new("UIStroke", r); s1.Color = Color3.fromRGB(120,220,255); s1.Thickness = 5; s1.Transparency = 0.08
			local inner = Instance.new("Frame"); inner.AnchorPoint = Vector2.new(0.5,0.5); inner.Size = UDim2.new(0.72,0,0.72,0); inner.Position = UDim2.new(0.5,0,0.5,0)
			inner.BackgroundColor3 = Color3.fromRGB(150,230,255); inner.BackgroundTransparency = 0.78; inner.BorderSizePixel = 0; inner.Parent = r
			Instance.new("UICorner", inner).CornerRadius = UDim.new(1,0)
			return r
		end
		local function mkComet() -- a bright head + a fading tail streaking across
			local c = Instance.new("Frame"); c.AnchorPoint = Vector2.new(0.5,0.5); c.Size = UDim2.new(0,13,0,13); c.Position = UDim2.new(-0.12,0,0.14,0)
			c.BackgroundColor3 = Color3.fromRGB(190,238,255); c.BorderSizePixel = 0; c.ZIndex = 2; c.Parent = bg
			Instance.new("UICorner", c).CornerRadius = UDim.new(1,0)
			local t = Instance.new("Frame"); t.AnchorPoint = Vector2.new(1,0.5); t.Size = UDim2.new(0,64,0,7); t.Position = UDim2.new(0.5,0,0.5,0); t.Rotation = 10
			t.BackgroundColor3 = Color3.fromRGB(150,210,255); t.BorderSizePixel = 0; t.Parent = c
			Instance.new("UICorner", t).CornerRadius = UDim.new(1,0)
			local g = Instance.new("UIGradient", t); g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(1,0.15) })
			tw(c, 3.6, {Position = UDim2.new(1.12,0,0.34,0)}, Enum.EasingStyle.Linear):Play()
			task.delay(3.7, function() c:Destroy() end)
			return c
		end
		local function mkNebula(x, y, scale, color) -- a soft translucent colored nebula wisp
			local c = Instance.new("Frame"); c.AnchorPoint = Vector2.new(0.5,0.5); c.Size = UDim2.new(0, 150*scale, 0, 80*scale); c.Position = UDim2.new(x,0,y,0); c.BackgroundTransparency = 1; c.Parent = bg
			for _, p in ipairs({ {0.5,0.5,1.0},{0.3,0.6,0.72},{0.7,0.44,0.72},{0.46,0.34,0.62},{0.64,0.62,0.58} }) do
				local b = Instance.new("Frame"); b.AnchorPoint = Vector2.new(0.5,0.5); b.Size = UDim2.new(p[3],0,p[3],0); b.Position = UDim2.new(p[1],0,p[2],0)
				b.BackgroundColor3 = color; b.BackgroundTransparency = 0.62; b.BorderSizePixel = 0; b.Parent = c
				Instance.new("UICorner", b).CornerRadius = UDim.new(1,0)
			end
			return c
		end
		local function mkAsteroid(x, y, d)
			local a = Instance.new("Frame"); a.AnchorPoint = Vector2.new(0.5,0.5); a.Size = UDim2.new(0,d,0,d); a.Position = UDim2.new(x,0,y,0)
			a.BackgroundColor3 = Color3.fromRGB(122,114,106); a.BorderSizePixel = 0; a.Parent = bg
			Instance.new("UICorner", a).CornerRadius = UDim.new(0.5,0)
			for _, p in ipairs({ {0.36,0.4,0.24},{0.62,0.56,0.18},{0.5,0.3,0.14} }) do
				local cr = Instance.new("Frame"); cr.AnchorPoint = Vector2.new(0.5,0.5); cr.Size = UDim2.new(p[3],0,p[3],0); cr.Position = UDim2.new(p[1],0,p[2],0)
				cr.BackgroundColor3 = Color3.fromRGB(92,86,80); cr.BorderSizePixel = 0; cr.Parent = a
				Instance.new("UICorner", cr).CornerRadius = UDim.new(1,0)
			end
			return a
		end
		local function mkCluster(x, y) -- a twinkling star cluster / constellation
			local g = Instance.new("Frame"); g.AnchorPoint = Vector2.new(0.5,0.5); g.Size = UDim2.new(0,86,0,64); g.Position = UDim2.new(x,0,y,0); g.BackgroundTransparency = 1; g.Parent = bg
			for _, p in ipairs({ {0.2,0.3},{0.45,0.14},{0.6,0.46},{0.82,0.3},{0.4,0.62},{0.72,0.72} }) do
				local s = Instance.new("Frame"); s.AnchorPoint = Vector2.new(0.5,0.5); s.Size = UDim2.new(0,5,0,5); s.Position = UDim2.new(p[1],0,p[2],0)
				s.BackgroundColor3 = Color3.fromRGB(220,234,255); s.BorderSizePixel = 0; s.Parent = g
				Instance.new("UICorner", s).CornerRadius = UDim.new(1,0)
				TweenService:Create(s, TweenInfo.new(0.8 + math.random()*1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, math.random()), {BackgroundTransparency = 0.7}):Play()
			end
			return g
		end
		local function fadeAndDestroy(o, t) -- fade a composite element (and its children) then remove it
			for _, d in ipairs(o:GetDescendants()) do
				if d:IsA("GuiObject") then tw(d, t, {BackgroundTransparency = 1}):Play() end
				if d:IsA("UIStroke") then tw(d, t, {Transparency = 1}):Play() end
			end
			if o:IsA("GuiObject") then tw(o, t, {BackgroundTransparency = 1}):Play() end
			game:GetService("Debris"):AddItem(o, t + 0.15)
		end

		task.spawn(function()
			-- ===== OPENING (~3.7s): the screen TURNS ON (flicker) -> studio card =====
			tw(bg, 0.3, {BackgroundTransparency = 0}):Play()
			for _ = 1, 6 do flash.BackgroundTransparency = 0.2; task.wait(0.05); flash.BackgroundTransparency = 0.9; task.wait(0.05) end
			tw(flash, 0.3, {BackgroundTransparency = 1}):Play()
			local corn = mkLabel("\xF0\x9F\x8D\xBF", Enum.Font.GothamBold, 44, Color3.new(1,1,1))
			corn.Size = UDim2.new(0,64,0,64); corn.Position = UDim2.new(0.5,0,0.3,0); corn.TextTransparency = 1
			local studio = mkLabel("POPCORN PICTURES", Enum.Font.GothamBold, 30, Color3.fromRGB(255,226,150))
			studio.Size = UDim2.new(0.85,0,0,40); studio.Position = UDim2.new(0.5,0,0.46,0); studio.TextTransparency = 1
			local pres = mkLabel("presents", Enum.Font.Gotham, 18, Color3.fromRGB(214,218,235))
			pres.Size = UDim2.new(0.6,0,0,24); pres.Position = UDim2.new(0.5,0,0.58,0); pres.TextTransparency = 1
			tw(corn, 0.6, {TextTransparency = 0}):Play(); tw(studio, 0.7, {TextTransparency = 0}):Play()
			tw(corn, 1.2, {Position = UDim2.new(0.5,0,0.26,0)}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut):Play()
			task.wait(0.7); tw(pres, 0.5, {TextTransparency = 0}):Play()
			task.wait(2.4)
			for _, o in ipairs({corn, studio, pres}) do tw(o, 0.5, {TextTransparency = 1}):Play() end
			task.wait(0.6); corn:Destroy(); studio:Destroy(); pres:Destroy()

			-- ===== TITLE CARD (~4.5s): the movie title zooms + glows in, holds, fades =====
			local title = mkLabel("FLUFF FROM ABOVE", Enum.Font.FredokaOne, 10, Color3.fromRGB(255,216,0))
			title.Size = UDim2.new(0.2,0,0,60); title.Position = UDim2.new(0.5,0,0.46,0); title.TextScaled = true; title.TextStrokeTransparency = 0
			local tglow = Instance.new("UIStroke", title); tglow.Color = Color3.fromRGB(255,150,30); tglow.Thickness = 0
			local sub = mkLabel("the legend of the popcorn sheep", Enum.Font.Gotham, 16, Color3.fromRGB(220,224,240))
			sub.Size = UDim2.new(0.75,0,0,22); sub.Position = UDim2.new(0.5,0,0.62,0); sub.TextTransparency = 1
			tw(title, 0.8, {Size = UDim2.new(0.9,0,0,92)}, Enum.EasingStyle.Back):Play(); tw(tglow, 0.8, {Thickness = 3}):Play()
			task.wait(0.9); tw(sub, 0.6, {TextTransparency = 0}):Play()
			tw(title, 1.6, {Size = UDim2.new(0.94,0,0,98)}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut):Play()
			task.wait(2.8)
			tw(title, 0.7, {TextTransparency = 1}):Play(); tw(tglow, 0.7, {Transparency = 1}):Play(); tw(sub, 0.6, {TextTransparency = 1}):Play()
			task.wait(0.8); title:Destroy(); sub:Destroy()

			-- ===== STORY ACTS 1-2 (~12s): THE EGG'S JOURNEY -- a busy, lively cosmic adventure. A swooping path:
			-- drift in -> curve around a planet -> ZOOM through a glow ring -> glance off a cloud -> dodge an
			-- asteroid -> settle. The egg tumbles + trails sparkles, past drifting planets, a nebula, a star
			-- cluster, shooting stars + a comet (parallax: far = slow, near = fast). Busy but readable. =====
			makeStars(50) -- far twinkling field (static = slowest depth layer)
			local journeyFx = {}
			local function jfx(o) journeyFx[#journeyFx+1] = o; return o end
			-- drifting cosmic set (parallax)
			local planet = jfx(mkPlanet(0.72, 0.18, 66, Color3.fromRGB(120,150,235), true))
			tw(planet, 12.0, {Position = UDim2.new(0.68,0,0.24,0)}, Enum.EasingStyle.Linear):Play()
			local moon = jfx(mkPlanet(0.18, 0.4, 32, Color3.fromRGB(205,165,120), false))
			tw(moon, 12.0, {Position = UDim2.new(0.22,0,0.48,0)}, Enum.EasingStyle.Linear):Play()
			jfx(mkCluster(0.85, 0.58))
			local neb = jfx(mkNebula(0.3, 0.7, 1.2, Color3.fromRGB(150,90,200)))
			tw(neb, 12.0, {Position = UDim2.new(0.2,0,0.64,0)}, Enum.EasingStyle.Linear):Play()
			local ring = jfx(mkRing(0.42, 0.42, 58))
			TweenService:Create(ring, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Rotation = 14}):Play()
			local cloud = jfx(mkCloud(0.58, 0.52, 1.15))
			local roid = jfx(mkAsteroid(0.5, 0.62, 26))
			TweenService:Create(roid, TweenInfo.new(2.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {Rotation = 360}):Play()
			-- background flair (timed across the descent)
			task.delay(0.6, shootingStar); task.delay(2.6, shootingStar); task.delay(4.6, shootingStar)
			task.delay(7.4, shootingStar); task.delay(9.6, shootingStar)
			task.delay(3.4, mkComet)

			-- THE EGG: enters small at the top, tumbles continuously, and trails twinkling sparkles
			local egg = mkEgg()
			egg.Size = UDim2.new(0,26,0,34); egg.Position = UDim2.new(0.5,0,0.05,0); egg.ZIndex = 4
			local spinTween = TweenService:Create(egg, TweenInfo.new(1.3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {Rotation = 360})
			spinTween:Play()
			local trailing = true
			task.spawn(function() -- SPARKLE TRAIL: little twinkles spawned at the egg's live position as it flies
				while trailing do
					local d = Instance.new("Frame"); d.AnchorPoint = Vector2.new(0.5,0.5); local sz = 4 + math.random()*4
					d.Size = UDim2.new(0,sz,0,sz); d.Position = egg.Position; d.BackgroundColor3 = Color3.fromRGB(255,250,205)
					d.BorderSizePixel = 0; d.ZIndex = 3; d.Parent = bg
					Instance.new("UICorner", d).CornerRadius = UDim.new(1,0)
					tw(d, 0.7, {Size = UDim2.new(0,1,0,1), BackgroundTransparency = 1, Rotation = 40}):Play()
					game:GetService("Debris"):AddItem(d, 0.75)
					task.wait(0.06)
				end
			end)
			-- glide the egg to a waypoint over t secs (Sine = smooth curves), growing as it nears
			local function go(t, x, y, w, h, style, dir)
				tw(egg, t, { Position = UDim2.new(x,0,y,0), Size = UDim2.new(0,w,0,h) }, style or Enum.EasingStyle.Sine, dir or Enum.EasingDirection.InOut):Play()
				task.wait(t)
			end
			go(2.4, 0.34, 0.16, 34, 44)                                            -- drift in toward the planet
			-- curve / loop gracefully around the planet
			go(1.1, 0.54, 0.1, 36, 48)
			go(1.1, 0.84, 0.18, 40, 52)
			go(1.1, 0.7, 0.32, 42, 55)
			go(1.0, 0.5, 0.4, 46, 60)                                              -- glide down toward the ring
			-- ZOOM through the glowing ring (speed up) + a ring pulse as it passes
			TweenService:Create(ring, TweenInfo.new(0.18), {Size = UDim2.new(0,74,0,74)}):Play()
			task.delay(0.22, function() if ring.Parent then TweenService:Create(ring, TweenInfo.new(0.3), {Size = UDim2.new(0,58,0,58)}):Play() end end)
			go(0.5, 0.42, 0.42, 48, 62, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			-- GLANCE off the cloud (it jiggles), deflecting the egg
			go(0.8, 0.6, 0.5, 54, 70, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(cloud, TweenInfo.new(0.15), {Position = UDim2.new(0.62,0,0.53,0)}):Play()
			task.delay(0.18, function() if cloud.Parent then TweenService:Create(cloud, TweenInfo.new(0.5, Enum.EasingStyle.Elastic), {Position = UDim2.new(0.58,0,0.52,0)}):Play() end end)
			go(0.6, 0.46, 0.54, 58, 76, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			-- WEAVE / dodge the asteroid
			go(0.6, 0.64, 0.56, 64, 84)
			go(0.6, 0.5, 0.52, 70, 92)
			go(0.9, 0.5, 0.5, 72, 94)                                              -- settle into the landing approach
			-- end the journey: stop the trail + spin, clear the cosmic set (keep the far star field)
			trailing = false
			spinTween:Cancel(); egg.Rotation = 0
			for _, o in ipairs(journeyFx) do fadeAndDestroy(o, 0.5) end

			-- ===== STORY ACT 3 (~4.5s): the egg lands softly on the popcorn mountain, puffs, settles + glows =====
			mkMountain()
			tw(egg, 1.0, {Position = UDim2.new(0.5,0,0.64,0), Rotation = 360}, Enum.EasingStyle.Bounce):Play()
			task.wait(1.0)
			puff(0.5, 0.7)
			tw(egg, 0.16, {Size = UDim2.new(0,88,0,74)}):Play(); task.wait(0.16)
			tw(egg, 0.24, {Size = UDim2.new(0,72,0,94)}, Enum.EasingStyle.Back):Play(); task.wait(0.3)
			local eglow = Instance.new("UIStroke", egg); eglow.Color = Color3.fromRGB(255,240,170); eglow.Thickness = 0
			tw(eglow, 1.2, {Thickness = 5}):Play()
			task.wait(3.0)

			-- ===== REVEAL (~5s, then PERMANENT): "A NEW FRIEND HATCHES!" + sparkles + a sheep peeking. The real
			-- 3D spotlight egg appears at PopcornEggSpot now, and this final frame HOLDS forever (never blank). =====
			revealEgg()
			st.pointTarget = eggPos -- the on-screen pointer now guides to the real egg
			local sheep = mkSheep(); sheep.Position = UDim2.new(0.5,0,1.2,0)
			tw(sheep, 0.9, {Position = UDim2.new(0.5,0,0.66,0)}, Enum.EasingStyle.Back):Play()
			local cap = mkLabel("A NEW FRIEND HATCHES!", Enum.Font.FredokaOne, 10, Color3.fromRGB(255,236,150))
			cap.Size = UDim2.new(0.2,0,0,50); cap.Position = UDim2.new(0.5,0,0.2,0); cap.TextScaled = true; cap.TextStrokeTransparency = 0
			local cglow = Instance.new("UIStroke", cap); cglow.Color = Color3.fromRGB(255,150,30); cglow.Thickness = 2
			task.wait(0.4)
			tw(cap, 0.7, {Size = UDim2.new(0.94,0,0,86)}, Enum.EasingStyle.Back):Play()
			for i = 1, 12 do task.delay(i*0.12, function() sparkle(0.5 + (math.random()-0.5)*0.5, 0.52 + (math.random()-0.5)*0.45) end) end
			-- keep the held finale ALIVE (gentle infinite pulses) but never resetting / clearing
			TweenService:Create(cap, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {TextStrokeTransparency = 0.45}):Play()
			TweenService:Create(eglow, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Thickness = 2}):Play()
			-- TWO end-frame states: BEFORE hatch the egg sits in FRONT of the sheep (covering it, "about to
			-- hatch"). hatchScreenEgg() (fired by applyState when the player CLAIMS the spotlight egg) cracks +
			-- removes the screen egg so the SHEEP is revealed, and updates the caption to the hatched state.
			st.screenHatched = false
			st.hatchScreenEgg = function()
				if st.screenHatched then return end
				st.screenHatched = true
				pcall(function() puff(0.5, 0.64) end) -- a little crack/poof where the egg was
				for i = 1, 8 do task.delay(i*0.05, function() sparkle(0.5 + (math.random()-0.5)*0.3, 0.62 + (math.random()-0.5)*0.18) end) end
				if egg and egg.Parent then -- crack the egg off the screen
					tw(egg, 0.35, {Size = UDim2.new(0,4,0,4), BackgroundTransparency = 1, Rotation = 60}):Play()
					local de = egg; task.delay(0.4, function() pcall(function() de:Destroy() end) end)
				end
				if sheep and sheep.Parent then -- reveal the sheep (a happy little pop forward)
					tw(sheep, 0.45, {Position = UDim2.new(0.5,0,0.6,0), Size = UDim2.new(0,112,0,90)}, Enum.EasingStyle.Back):Play()
				end
				if cap and cap.Parent then cap.Text = "A NEW FRIEND HATCHED!" end
				print("[Pet] screen end frame -> sheep revealed (player hatched the Popcorn Sheep)")
			end
			if st.owns then st.hatchScreenEgg() end -- already owned by now (hatched fast) -> reveal immediately
			-- (intentionally NO destroy/fade here -- the SurfaceGui holds this end card on the screen permanently)
			print("[Pet] mini-movie played -> egg in spotlight at PopcornEggSpot")
		end)
	end

	-- ===== STAGE 2: PROJECTOR "Load Reels" prompt (needs all 6 reels) =====
	if projBody then
		local prompt
		prompt = addPrompt(projBody, "Load Reels", "Projector", function()
			if st.owns or st.showPlayed then return end
			local count = 0; for _, v in pairs(st.collected) do if v then count = count + 1 end end
			local have = math.max(count, st.uiFound or 0) -- server-confirmed count as a backup
			if have < #def.pieceMarkers then
				floatText(projPos + Vector3.new(0,3.5,0), "Find all 6 film reels first")
				print("[Pet] "..player.Name.." tried to load reels ("..have.."/6) -- not enough")
				return
			end
			st.showPlayed = true
			prompt.Enabled = false -- one show; remove the prompt so it never overlaps the egg's hatch prompt
			print("[Pet] "..player.Name.." loaded reels -> show starting")
			playMovie()
		end)
		prompt.HoldDuration = 0.4
	end

	-- (st.filmProps is empty now -- the projector + beam are PERMANENT props that are never hidden, for owners or not)
	if st.owns and st.filmProps then for _, o in ipairs(st.filmProps) do setVisible(o, false) end end
end

-- ============================================================================================
-- BUTTER DUCK QUEST (questType "fishing"). "Hook & Reel": grab a rod at the barrel -> fish near/over the
-- ButterLake UNION -> cast -> bite/hook (reaction) -> reel-in TENSION minigame -> the SERVER rolls the catch
-- (pity egg + funny junk) -> the egg appears IN FRONT of the player -> hatch -> the Butter Duck follows.
-- Reuses the shared hatch flow + claim/inventory. Cosmetic-only.
-- ============================================================================================

-- REEL-IN minigame: the standard FISCH-STYLE reel Roblox players recognize on sight. A tall vertical BAR
-- holds a drifting FISH marker and a player-controlled SLIDER (the catch zone). HOLD (click/tap anywhere)
-- to push the slider UP; RELEASE and it falls DOWN under gravity -- that single hold/release is the whole
-- control, exactly like Fisch. Keep the slider OVERLAPPING the fish to FILL the catch PROGRESS bar; when the
-- fish slips outside the slider, progress slowly drains. Fill to the top = caught; drain to zero = it got
-- away. A brief ~1.2s locked intro ("GET READY") lets the player orient before it goes live. Tuned EASY +
-- mobile-friendly (single hold/release works on touch). onDone(success) when finished.
local reelUI, reelBusy = nil, false
local function ensureReelUI()
	if reelUI then return reelUI end
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "ButterReelGui"; g.ResetOnSpawn = false; g.DisplayOrder = 90; g.Enabled = false; g.Parent = pgui
	local dim = Instance.new("Frame"); dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0); dim.BackgroundTransparency = 0.5; dim.Active = true; dim.Parent = g
	local panel = Instance.new("Frame"); panel.Size = UDim2.new(0,300,0,360); panel.Position = UDim2.new(0.5,0,0.5,0); panel.AnchorPoint = Vector2.new(0.5,0.5)
	panel.BackgroundColor3 = Color3.fromRGB(25,90,185); panel.Parent = g
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16); local ps = Instance.new("UIStroke", panel); ps.Color = Color3.new(1,1,1); ps.Thickness = 3
	local titl = Instance.new("TextLabel"); titl.Size = UDim2.new(1,-20,0,30); titl.Position = UDim2.new(0,10,0,10); titl.BackgroundTransparency = 1
	titl.Font = Enum.Font.GothamBold; titl.TextSize = 22; titl.TextColor3 = Color3.fromRGB(255,215,0); titl.Text = "REEL IT IN!"; titl.Parent = panel
	-- the tall vertical REEL BAR (holds the drifting fish + the player-controlled slider)
	local track = Instance.new("Frame"); track.Size = UDim2.new(0,90,0,250); track.Position = UDim2.new(0,40,0,90)
	track.BackgroundColor3 = Color3.fromRGB(12,34,76); track.Parent = panel; Instance.new("UICorner", track).CornerRadius = UDim.new(0,12)
	local tstk = Instance.new("UIStroke", track); tstk.Color = Color3.new(1,1,1); tstk.Transparency = 0.55; tstk.Thickness = 2
	-- the SLIDER (catch zone) the player moves with hold/release
	local zone = Instance.new("Frame"); zone.Size = UDim2.new(1,-10,0.30,0); zone.Position = UDim2.new(0.5,0,0.5,0); zone.AnchorPoint = Vector2.new(0.5,0.5)
	zone.BackgroundColor3 = Color3.fromRGB(70,210,90); zone.BackgroundTransparency = 0.2; zone.BorderSizePixel = 0; zone.Parent = track; Instance.new("UICorner", zone).CornerRadius = UDim.new(0,8)
	local zstk = Instance.new("UIStroke", zone); zstk.Color = Color3.fromRGB(225,255,225); zstk.Thickness = 2
	-- the FISH marker that drifts up/down inside the bar
	local fish = Instance.new("TextLabel"); fish.Size = UDim2.new(0,46,0,46); fish.AnchorPoint = Vector2.new(0.5,0.5); fish.Position = UDim2.new(0.5,0,0.5,0)
	fish.BackgroundTransparency = 1; fish.Font = Enum.Font.GothamBold; fish.TextSize = 34; fish.Text = "\xF0\x9F\x90\x9F"; fish.ZIndex = 4; fish.Parent = track
	-- the catch PROGRESS bar (vertical, right side), fills bottom-up
	local pbBg = Instance.new("Frame"); pbBg.Size = UDim2.new(0,40,0,250); pbBg.Position = UDim2.new(1,-70,0,90)
	pbBg.BackgroundColor3 = Color3.fromRGB(15,40,90); pbBg.Parent = panel; Instance.new("UICorner", pbBg).CornerRadius = UDim.new(0,10)
	local pb = Instance.new("Frame"); pb.Size = UDim2.new(1,0,0.45,0); pb.Position = UDim2.new(0,0,1,0); pb.AnchorPoint = Vector2.new(0,1)
	pb.BackgroundColor3 = Color3.fromRGB(255,205,60); pb.BorderSizePixel = 0; pb.Parent = pbBg; Instance.new("UICorner", pb).CornerRadius = UDim.new(0,10)
	local pbl = Instance.new("TextLabel"); pbl.Size = UDim2.new(0,80,0,16); pbl.AnchorPoint = Vector2.new(0.5,0); pbl.Position = UDim2.new(1,-50,1,-26); pbl.BackgroundTransparency = 1
	pbl.Font = Enum.Font.GothamBold; pbl.TextSize = 12; pbl.TextColor3 = Color3.fromRGB(255,225,120); pbl.Text = "CATCH"; pbl.Parent = panel
	-- center "GET READY" overlay for the brief locked intro
	local ready = Instance.new("TextLabel"); ready.AnchorPoint = Vector2.new(0.5,0.5); ready.Position = UDim2.new(0.5,0,0.5,0); ready.Size = UDim2.new(1,-20,0,40)
	ready.BackgroundTransparency = 1; ready.Font = Enum.Font.FredokaOne; ready.TextSize = 28; ready.TextColor3 = Color3.fromRGB(255,240,120); ready.Text = "GET READY..."; ready.ZIndex = 6; ready.Parent = panel
	Instance.new("UIStroke", ready).Thickness = 2
	-- bottom hint (the familiar Fisch layout already makes it clear; this is a gentle reminder)
	local hintL = Instance.new("TextLabel"); hintL.Size = UDim2.new(1,-20,0,20); hintL.Position = UDim2.new(0,10,1,-28); hintL.BackgroundTransparency = 1
	hintL.Font = Enum.Font.Gotham; hintL.TextSize = 13; hintL.TextColor3 = Color3.new(1,1,1); hintL.Text = "HOLD to rise \xE2\x80\xA2 RELEASE to drop \xE2\x80\x94 keep \xF0\x9F\x90\x9F in the zone"; hintL.Parent = panel
	reelUI = { gui = g, zone = zone, fish = fish, pb = pb, hint = hintL, ready = ready }
	return reelUI
end
local function openReelMinigame(onDone)
	if reelBusy then if onDone then onDone(false) end return end
	reelBusy = true
	local UIS = game:GetService("UserInputService")
	local ui = ensureReelUI()
	local ZONE_H = 0.30          -- slider height as a fraction of the bar (WIDE = easy; this is an easy pet)
	local zone, zoneVel = 0.45, 0
	local fishF, fishTarget, fishTimer = 0.5, 0.5, 0
	local progress = 0.45        -- start partway so it isn't an instant win/lose
	ui.zone.Size = UDim2.new(1,-10,ZONE_H,0)
	ui.pb.Size = UDim2.new(1,0,progress,0)
	local done, holding = false, false
	local c1, c2
	local function isHold(t) return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch end
	c1 = UIS.InputBegan:Connect(function(i) if isHold(i.UserInputType) then holding = true end end)
	c2 = UIS.InputEnded:Connect(function(i) if isHold(i.UserInputType) then holding = false end end)
	ui.gui.Enabled = true
	local function finish(success)
		if done then return end
		done = true; if c1 then c1:Disconnect() end; if c2 then c2:Disconnect() end
		ui.gui.Enabled = false; reelBusy = false
		if onDone then onDone(success) end
	end
	task.spawn(function()
		-- BRIEF LOCKED INTRO (~1.2s, like Fisch): the fish + slider are shown and the slider already responds
		-- to hold/release so the player can pre-position, but the catch PROGRESS doesn't move until it goes live.
		local introT = 1.2
		ui.ready.Visible = true
		local last = os.clock()
		while not done do
			local now = os.clock(); local dt = math.min(now - last, 0.05); last = now
			-- SLIDER physics: HOLD pushes up, gravity pulls down, light damping -- the whole control
			zoneVel = (zoneVel + (holding and 2.4 or -1.15) * dt) * 0.90
			zone = zone + zoneVel * dt
			if zone < ZONE_H/2 then zone = ZONE_H/2; zoneVel = 0 elseif zone > 1 - ZONE_H/2 then zone = 1 - ZONE_H/2; zoneVel = 0 end
			-- FISH drift toward a slowly-changing target (gentle = easy)
			fishTimer = fishTimer - dt
			if fishTimer <= 0 then fishTarget = 0.14 + math.random() * 0.72; fishTimer = 0.6 + math.random() * 1.4 end
			fishF = fishF + (fishTarget - fishF) * math.min(dt * 1.6, 1)
			local inZone = math.abs(fishF - zone) <= (ZONE_H/2)
			if introT > 0 then
				introT = introT - dt
				if introT <= 0 then ui.ready.Visible = false end
			else
				-- LIVE: fill while the fish is inside the slider, drain (slower = forgiving) when it slips out
				progress = math.clamp(progress + (inZone and 0.46 or -0.22) * dt, 0, 1)
			end
			-- visuals (f=1 is the TOP of the bar)
			ui.zone.Position = UDim2.new(0.5, 0, 1 - zone, 0)
			ui.zone.BackgroundColor3 = inZone and Color3.fromRGB(70,225,95) or Color3.fromRGB(90,150,110)
			ui.fish.Position = UDim2.new(0.5, 0, 1 - fishF, 0)
			ui.pb.Size = UDim2.new(1, 0, progress, 0)
			ui.pb.BackgroundColor3 = (progress > 0.5) and Color3.fromRGB(120,235,110) or Color3.fromRGB(255,205,60)
			if introT <= 0 then
				if progress >= 1 then finish(true); break elseif progress <= 0 then finish(false); break end
			end
			task.wait()
		end
	end)
end

-- Build the BUTTER fishing world: a rod barrel (grab the rod) + a Fish prompt near/over the ButterLake union,
-- and the full cast -> bite/hook -> reel-in -> server-roll -> egg-in-front flow.
local function buildButterWorld(petId, def, positions)
	local st = petState[petId]
	if st.built then return end
	st.built = true; st.isFishing = true
	local extra = positions.extra or {}
	local sizes = positions.extraSize or {}
	local lakePos  = extra.butterlake
	local lakeSize = sizes.butterlake
	local barrelPos = extra.rodbarrel
	st.fishProps = {}
	st.hintAnchor = barrelPos or lakePos
	if typeof(lakePos) ~= "Vector3" then warn("[Pet][DIAG] ButterLake position MISSING for "..petId.." -- fishing disabled"); return end
	local surfaceY = lakePos.Y + ((typeof(lakeSize) == "Vector3") and lakeSize.Y/2 or 0)

	-- ===== REALISTIC FISHING VISUALS: rod-in-hand + line + floating red/white bobber =====
	-- A thin rod model rides on the player's hand (updated each frame to follow it, angled forward+up). On
	-- cast, a Beam "line" runs from the rod TIP to a classic red-top/white-bottom bobber that arcs out and
	-- floats on the butter. Lightweight (a handful of parts) but clearly reads as fishing. Defined before the
	-- rod-barrel block so the "Grab Fishing Rod" handler can start the held rod.
	local heldRod, rodTip, rodTipAtt
	local function startHeldRod()
		if heldRod then return end
		local rod = Instance.new("Model"); rod.Name = petId.."HeldRod"
		local function rp(name, shape, size, color, mat)
			local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
			p.Material = mat or Enum.Material.SmoothPlastic; p.Anchored = true; p.CanCollide = false
			p.CanQuery = false; p.CastShadow = false; p.Parent = rod; return p
		end
		local shaft = rp("Shaft", Enum.PartType.Cylinder, Vector3.new(6,0.16,0.16), Color3.fromRGB(110,70,40), Enum.Material.Wood)
		local grip  = rp("Grip",  Enum.PartType.Cylinder, Vector3.new(1.1,0.26,0.26), Color3.fromRGB(35,30,28))
		local reel  = rp("Reel",  Enum.PartType.Cylinder, Vector3.new(0.3,0.7,0.7), Color3.fromRGB(40,40,46), Enum.Material.Metal)
		rodTip = rp("Tip", Enum.PartType.Ball, Vector3.new(0.16,0.16,0.16), Color3.fromRGB(235,235,235)); rodTip.Transparency = 1
		rodTipAtt = Instance.new("Attachment"); rodTipAtt.Parent = rodTip
		rod.Parent = Workspace; heldRod = rod; st.fishProps[#st.fishProps+1] = rod
		task.spawn(function()
			while heldRod and heldRod.Parent and not st.owns do
				local char = player.Character
				local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hand and hrp then
					local look = hrp.CFrame.LookVector; look = Vector3.new(look.X, 0, look.Z)
					if look.Magnitude < 0.1 then look = Vector3.new(0,0,-1) end
					local rodDir = (look.Unit + Vector3.new(0, 0.62, 0)).Unit       -- forward + up
					local center = hand.Position + look.Unit * 0.4 + rodDir * 3.0
					local cf = CFrame.lookAt(center, center + rodDir) * CFrame.Angles(0, math.rad(90), 0) -- align cylinder length (X) to rodDir
					shaft.CFrame = cf
					grip.CFrame  = cf * CFrame.new(-2.6, 0, 0)
					reel.CFrame  = cf * CFrame.new(-2.0, -0.35, 0) * CFrame.Angles(0,0,math.rad(90))
					rodTip.CFrame = cf * CFrame.new(3.0, 0, 0)                       -- far end of the shaft (line origin)
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end
	-- classic bobber: white body + red cap + red antenna (reads red-top/white-bottom). Root = white body
	-- (anchored, moved by CFrame); cap + antenna welded so they follow. Returns the root part.
	local function buildBobber(cf)
		local root = Instance.new("Part"); root.Name = petId.."Bobber"; root.Shape = Enum.PartType.Ball
		root.Size = Vector3.new(0.55,0.55,0.55); root.Color = Color3.fromRGB(240,240,245); root.Material = Enum.Material.SmoothPlastic
		root.Anchored = true; root.CanCollide = false; root.CanQuery = false; root.CastShadow = false; root.CFrame = cf; root.Parent = Workspace
		local function weldTo(part) local w = Instance.new("WeldConstraint"); w.Part0 = root; w.Part1 = part; w.Parent = root end
		local cap = Instance.new("Part"); cap.Name="Cap"; cap.Shape=Enum.PartType.Ball; cap.Size=Vector3.new(0.6,0.6,0.6)
		cap.Color=Color3.fromRGB(225,55,55); cap.Material=Enum.Material.SmoothPlastic
		cap.Anchored=false; cap.CanCollide=false; cap.CanQuery=false; cap.CastShadow=false; cap.Massless=true; cap.CFrame=cf*CFrame.new(0,0.22,0); cap.Parent=root; weldTo(cap)
		local ant = Instance.new("Part"); ant.Name="Antenna"; ant.Shape=Enum.PartType.Cylinder; ant.Size=Vector3.new(0.5,0.07,0.07)
		ant.Color=Color3.fromRGB(225,55,55); ant.Material=Enum.Material.SmoothPlastic
		ant.Anchored=false; ant.CanCollide=false; ant.CanQuery=false; ant.CastShadow=false; ant.Massless=true; ant.CFrame=cf*CFrame.new(0,0.62,0)*CFrame.Angles(0,0,math.rad(90)); ant.Parent=root; weldTo(ant)
		return root
	end
	-- the LINE: a Beam from the rod tip to the bobber. Att1 + Beam live ON the bobber, so destroying the
	-- bobber removes them; Att0 is the persistent rod-tip attachment (so the line tracks the moving rod).
	local function attachLine(bobRoot)
		if not rodTipAtt then return end
		local a1 = Instance.new("Attachment"); a1.Name = "LineEnd"; a1.Parent = bobRoot
		local beam = Instance.new("Beam"); beam.Attachment0 = rodTipAtt; beam.Attachment1 = a1
		beam.Width0 = 0.05; beam.Width1 = 0.05; beam.FaceCamera = true; beam.Segments = 4
		beam.Color = ColorSequence.new(Color3.fromRGB(235,235,235)); beam.Transparency = NumberSequence.new(0.15)
		beam.LightInfluence = 1; beam.Parent = bobRoot
	end

	-- ===== ROD BARREL (client-built prop at the captured position) + "Grab Fishing Rod" prompt =====
	if typeof(barrelPos) == "Vector3" then
		local barrel = Instance.new("Model"); barrel.Name = petId.."RodBarrel"
		-- WOODEN BARREL: a brown wood cylinder standing upright (axis = Y) with darker slat BANDS around it.
		local body = newPart(barrel, "Barrel", Enum.PartType.Cylinder, Vector3.new(3.4,3.0,3.0), Color3.fromRGB(124,82,44), CFrame.new(barrelPos + Vector3.new(0,1.7,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Wood)
		barrel.PrimaryPart = body
		newPart(barrel, "Lip", Enum.PartType.Cylinder, Vector3.new(0.5,3.2,3.2), Color3.fromRGB(96,62,32), CFrame.new(barrelPos + Vector3.new(0,3.35,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Wood) -- top rim
		newPart(barrel, "Inside", Enum.PartType.Cylinder, Vector3.new(0.4,2.5,2.5), Color3.fromRGB(48,32,18), CFrame.new(barrelPos + Vector3.new(0,3.3,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Wood) -- dark opening (so rods read as sticking OUT of it)
		for _, oy in ipairs({0.7, 1.8, 2.9}) do newPart(barrel, "Band", Enum.PartType.Cylinder, Vector3.new(0.28,3.5,3.5), Color3.fromRGB(58,40,24), CFrame.new(barrelPos + Vector3.new(0,oy,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Wood) end -- dark slat bands
		-- SEVERAL FISHING RODS sticking up and OUTWARD out of the barrel, at slight angles around the rim.
		local rimY = barrelPos + Vector3.new(0, 3.0, 0)
		local NRODS = 4
		for i = 0, NRODS - 1 do
			local ang = i * (2*math.pi / NRODS) + 0.4
			local outward = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local tiltDeg = 20
			local rodLen = 6.5
			local up = math.cos(math.rad(tiltDeg)); local out = math.sin(math.rad(tiltDeg))
			local axis = (outward * out + Vector3.new(0, up, 0)).Unit          -- the rod's lean direction
			local center = rimY + outward * 0.7 + axis * (rodLen/2)
			local cf = CFrame.lookAt(center, center + axis) * CFrame.Angles(0, math.rad(90), 0) -- align cylinder length (local X) to axis
			newPart(barrel, "Rod", Enum.PartType.Cylinder, Vector3.new(rodLen,0.16,0.16), Color3.fromRGB(110,70,40), cf, Enum.Material.Wood)
			-- a small dark reel near the rod's base + a tiny tip bead so it reads as a real rod
			newPart(barrel, "RodReel", Enum.PartType.Cylinder, Vector3.new(0.28,0.6,0.6), Color3.fromRGB(38,38,44), cf * CFrame.new(-rodLen/2 + 0.9, -0.32, 0) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Metal)
			newPart(barrel, "RodTip", Enum.PartType.Ball, Vector3.new(0.22,0.22,0.22), Color3.fromRGB(235,235,235), cf * CFrame.new(rodLen/2, 0, 0))
		end
		barrel.Parent = Workspace
		st.fishProps[#st.fishProps+1] = barrel
		local grab = addPrompt(body, "Grab Fishing Rod", "Rod Barrel", function()
			if st.owns then return end
			if not st.hasRod then
				st.hasRod = true
				startHeldRod() -- show the rod in the player's hand from now on
				floatText(barrelPos + Vector3.new(0,4,0), "Got a fishing rod! \xF0\x9F\x8E\xA3")
				print("[Pet] "..player.Name.." grabbed rod")
			else
				floatText(barrelPos + Vector3.new(0,4,0), "You already have a rod!")
			end
		end)
		grab.HoldDuration = 0.3
		print(string.format("[Pet][DIAG] built rod barrel at (%.0f,%.0f,%.0f)", barrelPos.X, barrelPos.Y, barrelPos.Z))
	else
		warn("[Pet][DIAG] RodBarrel position MISSING for "..petId)
	end

	-- ===== FISHING HUD (status + tap-to-hook + junk popup) =====
	local pgui = player:WaitForChild("PlayerGui")
	local hud = Instance.new("ScreenGui"); hud.Name = "ButterFishingHUD"; hud.ResetOnSpawn = false; hud.DisplayOrder = 88; hud.Parent = pgui
	-- status = a blue BACKDROP FRAME (the pill) with a child text label. Visible=FALSE at rest; setStatus/hideStatus
	-- toggle the FRAME's visibility -- so the empty backdrop never lingers on screen when no message is showing.
	local status = Instance.new("Frame"); status.AnchorPoint = Vector2.new(0.5,0); status.Position = UDim2.new(0.5,0,0.12,0); status.Size = UDim2.new(0,440,0,40)
	status.BackgroundColor3 = Color3.fromRGB(25,90,185); status.BackgroundTransparency = 0.12; status.BorderSizePixel = 0; status.Visible = false; status.Parent = hud
	Instance.new("UICorner", status).CornerRadius = UDim.new(0,10); local sstk = Instance.new("UIStroke", status); sstk.Color = Color3.fromRGB(255,215,0); sstk.Thickness = 2
	local statusText = Instance.new("TextLabel"); statusText.Size = UDim2.new(1,0,1,0); statusText.BackgroundTransparency = 1
	statusText.Font = Enum.Font.GothamBold; statusText.TextSize = 20; statusText.TextColor3 = Color3.new(1,1,1); statusText.Text = ""; statusText.Parent = status
	local function setStatus(txt) statusText.Text = txt; status.Visible = true end -- show the backdrop FRAME (+ message)
	local function hideStatus() status.Visible = false end                          -- hide the backdrop FRAME entirely
	local JUNK_EMOJI = {
		["an old boot"] = "\xF0\x9F\xA5\xBE", ["a butter blob"] = "\xF0\x9F\xA7\x88", ["a rubber duck"] = "\xF0\x9F\xA6\x86",
		["a soggy sock"] = "\xF0\x9F\xA7\xA6", ["a rusty tin can"] = "\xF0\x9F\xA5\xAB", ["a clump of swamp weed"] = "\xF0\x9F\x8C\xBF",
		["a lost flip-flop"] = "\xF0\x9F\xA9\xB4", ["a message in a bottle"] = "\xF0\x9F\x8D\xBE",
	}
	local function showJunk(junk)
		local pop = Instance.new("TextLabel"); pop.AnchorPoint = Vector2.new(0.5,0.5); pop.Position = UDim2.new(0.5,0,0.42,0); pop.Size = UDim2.new(0,60,0,60)
		pop.BackgroundTransparency = 1; pop.Font = Enum.Font.GothamBold; pop.TextSize = 70; pop.Text = JUNK_EMOJI[junk] or "\xF0\x9F\xA5\xBE"; pop.TextTransparency = 1; pop.Parent = hud
		local TS = game:GetService("TweenService")
		TS:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0,120,0,120), TextTransparency = 0}):Play()
		task.delay(1.2, function() TS:Create(pop, TweenInfo.new(0.4), {TextTransparency = 1}):Play(); task.delay(0.45, function() pop:Destroy() end) end)
	end
	local function waitForTap(timeout)
		local tapped = false
		local catcher = Instance.new("TextButton"); catcher.Size = UDim2.new(1,0,1,0); catcher.BackgroundColor3 = Color3.fromRGB(255,120,40)
		catcher.BackgroundTransparency = 0.8; catcher.AutoButtonColor = false; catcher.Text = ""; catcher.Parent = hud
		local big = Instance.new("TextLabel"); big.AnchorPoint = Vector2.new(0.5,0.5); big.Position = UDim2.new(0.5,0,0.5,0); big.Size = UDim2.new(0,320,0,120)
		big.BackgroundTransparency = 1; big.Font = Enum.Font.FredokaOne; big.TextSize = 60; big.TextColor3 = Color3.fromRGB(255,240,120); big.Text = "TAP TO HOOK!"; big.Parent = catcher
		Instance.new("UIStroke", big).Thickness = 3
		local c = catcher.MouseButton1Click:Connect(function() tapped = true end)
		local t = 0; while t < timeout and not tapped do t = t + task.wait() end
		c:Disconnect(); catcher:Destroy()
		return tapped
	end

	-- ===== the BUTTER EGG (caught) -> appears IN FRONT of the player, with a Hatch prompt (reuses hatchEgg) =====
	local function spawnButterEgg()
		if st.egg then return end
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local fwd = hrp.CFrame.LookVector; fwd = Vector3.new(fwd.X, 0, fwd.Z); if fwd.Magnitude < 0.1 then fwd = Vector3.new(0,0,-1) end
		local center = hrp.Position + fwd.Unit * 6 + Vector3.new(0, -1.0, 0) -- a few studs in front, near the ground
		st.eggPos = center; st.eggCaught = true
		local egg = Instance.new("Model"); egg.Name = petId.."Egg"
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(250,224,120), nil)
		shell.Reflectance = 0.08
		local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Scale = Vector3.new(3.0,4.0,3.0); m.Parent = shell
		visual.PrimaryPart = shell
		for j = 1, 8 do local a = (j-1)*(2*math.pi/8); local y = math.sin(a*1.7)*1.0; local r = 1.3*math.sqrt(math.max(0, 1-(y/2)^2))+0.05
			newPart(visual, "Drip", Enum.PartType.Ball, Vector3.new(0.45,0.45,0.45), Color3.fromRGB(255,236,150), CFrame.new(math.sin(a)*r, y, math.cos(a)*r)) end
		st.eggBaseCF = CFrame.new(center)
		st.eggVisual = visual; visual:PivotTo(st.eggBaseCF)
		st.egg = egg; egg.Parent = Workspace
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(255,235,140); hl.FillTransparency = 0.5; hl.OutlineColor = Color3.fromRGB(255,210,80); hl.Adornee = visual; hl.Parent = egg
		addPrompt(shell, "Hatch", "Butter Egg", function()
			if st.owns or st.hatching then return end
			if hatchEgg then hatchEgg(petId, def) end
		end)
		task.spawn(function() local t = 0
			while st.egg do t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.28, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end)
				end
				task.wait(0.05)
			end
		end)
		print("[Pet] butter egg caught -> appeared in front of "..player.Name)
	end

	-- ===== near the EXPOSED butter EDGE (so you can fish from the shore, on land) =====
	-- The ButterLake union extends UNDER the whole landmass, so its bounding box covers the island and a
	-- box/center distance check is useless. Instead we PROBE for exposed butter with downward rays in a
	-- small ring AROUND the player: if a ray straight DOWN from the player OR from any nearby ring point
	-- hits the ButterLake union FIRST, the player is standing on/beside EXPOSED butter (i.e. at the shore).
	-- This lets them fish from LAND a few studs from the edge without stepping onto the butter, and it does
	-- NOT trigger in the island middle (every probe there hits land first). butterProbe() returns the
	-- nearest exposed-butter world point within reach (so the line can cast OUT INTO the butter), or nil.
	-- (All our client props are CanQuery=false, so the rays ignore them and only hit real world geometry.)
	local EDGE_REACH = 7   -- TIGHT: only a few studs from the exposed butter counts as "at the edge" (must be right at the shoreline, not partway into the island)
	local function butterProbe()
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return nil end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character }
		params.IgnoreWater = true
		local origin = hrp.Position
		local function probe(px, pz)
			local r = Workspace:Raycast(Vector3.new(px, origin.Y + 5, pz), Vector3.new(0, -400, 0), params)
			if not r or not r.Instance then return nil end
			local inst = r.Instance
			if inst.Name == "ButterLake" or inst:FindFirstAncestor("ButterLake") ~= nil then return r.Position end
			return nil
		end
		local p = probe(origin.X, origin.Z); if p then return p end          -- standing right on the butter
		for _, rad in ipairs({ EDGE_REACH * 0.55, EDGE_REACH }) do           -- else a SMALL ring out to the edge only
			for i = 0, 11 do                                                 -- 12 dirs (denser, since the radius is tiny)
				local a = i * (math.pi / 6)
				p = probe(origin.X + math.cos(a) * rad, origin.Z + math.sin(a) * rad)
				if p then return p end
			end
		end
		return nil
	end
	local function isNearButterEdge() return butterProbe() ~= nil end

	-- ===== where the cast LANDS: a point OUT on the butter, in front of the player =====
	-- The old target (butterProbe's first hit) often landed at the player's feet or off to a fixed side.
	-- Instead: find the horizontal DIRECTION toward the butter (toward the nearest butter, or the player's
	-- facing if already standing on butter), then march OUT along it and drop the bobber a few studs ONTO
	-- the open butter past the edge. Returns a Vector3 on the butter surface, or nil if no butter found.
	local function castTarget()
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return nil end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character }
		params.IgnoreWater = true
		local origin = hrp.Position
		local function butterY(px, pz) -- butter surface Y at (px,pz) if the FIRST thing below is butter, else nil
			local r = Workspace:Raycast(Vector3.new(px, origin.Y + 8, pz), Vector3.new(0, -400, 0), params)
			if not r or not r.Instance then return nil end
			local inst = r.Instance
			if inst.Name == "ButterLake" or inst:FindFirstAncestor("ButterLake") ~= nil then return r.Position.Y end
			return nil
		end
		-- 1) direction toward the butter
		local look = hrp.CFrame.LookVector; look = Vector3.new(look.X, 0, look.Z)
		look = (look.Magnitude > 0.1) and look.Unit or Vector3.new(0, 0, -1)
		local dir
		if butterY(origin.X, origin.Z) then
			dir = look                                   -- already on butter -> cast where we're facing
		else
			local best, bestDist                         -- nearest butter around us -> head that way
			for i = 0, 11 do
				local a = i * (math.pi / 6)
				local d = Vector3.new(math.cos(a), 0, math.sin(a))
				for _, rad in ipairs({ 3, 6, 9, 12 }) do
					if butterY(origin.X + d.X * rad, origin.Z + d.Z * rad) then
						if not bestDist or rad < bestDist then bestDist = rad; best = d end
						break
					end
				end
			end
			dir = best or look
		end
		-- 2) march OUT along dir; drop the bobber a few studs onto the butter, past where it starts
		local CAST_OUT, CAST_MAX, STEP = 8, 28, 2
		local edgeDist, lastY, lastD
		for d = 1, CAST_MAX, STEP do
			local by = butterY(origin.X + dir.X * d, origin.Z + dir.Z * d)
			if by then
				edgeDist = edgeDist or d
				lastY, lastD = by, d
				if d >= edgeDist + CAST_OUT then
					return Vector3.new(origin.X + dir.X * d, by + 0.45, origin.Z + dir.Z * d) -- out on open butter
				end
			end
		end
		if lastY then return Vector3.new(origin.X + dir.X * lastD, lastY + 0.45, origin.Z + dir.Z * lastD) end -- furthest butter we found
		return nil
	end

	-- ===== the FISH prompt (lives on a part that FOLLOWS the player, NOT a fixed island-center anchor) =====
	-- The follower part is repositioned to the player every frame (loop below), so the "[E] Fish" prompt
	-- appears NEXT TO THE PLAYER at the shore. A ProximityPrompt natively shows "[E] Fish" on desktop + a
	-- tap button on mobile; we enable it only while near the exposed butter edge.
	local fishFollower = newPart(Workspace, petId.."FishSpot", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.new(1,1,1), CFrame.new(lakePos))
	fishFollower.Transparency = 1
	st.fishProps[#st.fishProps+1] = fishFollower
	local fishing = false
	local fishPrompt -- forward-declared so the closure below captures THIS local (not a nil global)
	fishPrompt = addPrompt(fishFollower, "Fish", "Butter Swamp", function()
		if st.owns or st.eggCaught or fishing then return end
		if not st.hasRod then floatText((player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or lakePos) + Vector3.new(0,3,0), "Grab a rod from the barrel first!"); return end
		if not isNearButterEdge() then floatText((player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or lakePos) + Vector3.new(0,3,0), "Get closer to the butter's edge to fish!"); return end
		fishing = true; fishPrompt.Enabled = false
		pushQuestProg(petId, { started = true }) -- HUD: minimize to the live fishing tracker
		task.spawn(function()
			local TS = game:GetService("TweenService")
			local keepGoing = true
			-- STOP when the player owns it OR walks away from the butter edge. Without the isNearButterEdge()
			-- gate the loop recast FOREVER and left the blue "status" HUD bar stuck on screen.
			while keepGoing and not st.owns and isNearButterEdge() do
				-- STEP 1: CAST -- a bobber arcs from the rod tip OUT onto the butter in FRONT of the player.
				-- castTarget() aims toward the nearest butter and lands the bobber a few studs out from the edge.
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local target = castTarget()  -- a point OUT on the butter in front of the player (toward nearest butter)
					or (hrp and Vector3.new(hrp.Position.X, surfaceY + 0.4, hrp.Position.Z))
					or Vector3.new(lakePos.X, surfaceY + 0.4, lakePos.Z)
				-- cast the line from the ROD TIP (in hand) out to a red/white BOBBER that arcs in + floats.
				local startP = (rodTip and rodTip.Position) or (hrp and (hrp.Position + Vector3.new(0,1.5,0))) or target
				local bob = buildBobber(CFrame.new(startP)); attachLine(bob) -- bobber + the line beam to the rod tip
				local nv = Instance.new("NumberValue"); nv.Value = 0; nv.Parent = bob
				nv:GetPropertyChangedSignal("Value"):Connect(function() local t = nv.Value; bob.CFrame = CFrame.new(startP:Lerp(target, t) + Vector3.new(0, math.sin(t*math.pi)*6, 0)) end)
				TS:Create(nv, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {Value = 1}):Play()
				print("[Pet] "..player.Name.." cast"); setStatus("Waiting for a bite...")
				-- gentle idle BOB on the butter surface once the cast lands (until the bite takes over).
				local floating = true
				task.spawn(function()
					task.wait(0.62)
					local ft = 0
					while floating and bob.Parent do ft = ft + 0.05; pcall(function() bob.CFrame = CFrame.new(target + Vector3.new(0, math.sin(ft*2.2)*0.16, 0)) end); task.wait(0.05) end
				end)
				task.wait(0.65 + 1 + math.random() * 3) -- cast settle + random 1-4s until a bite
				floating = false
				if st.owns or not isNearButterEdge() then pcall(function() bob:Destroy() end) break end -- walked away from the butter edge (or owns) -> stop; loop-end hides the status
				-- STEP 2: THE BITE -- bobber dips/wiggles + "!" ; tap within ~1.3s to HOOK
				print("[Pet] "..player.Name.." bite")
				local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,36,0,36); bb.StudsOffset = Vector3.new(0,2.4,0); bb.AlwaysOnTop = true; bb.Parent = bob
				local bl = Instance.new("TextLabel"); bl.Size = UDim2.new(1,0,1,0); bl.BackgroundTransparency = 1; bl.Font = Enum.Font.GothamBold; bl.TextSize = 34; bl.TextColor3 = Color3.fromRGB(255,70,70); bl.Text = "!"; bl.Parent = bb
				local biteBase = bob.Position
				local wiggling = true
				task.spawn(function() local t = 0; while wiggling and bob.Parent do t = t + 0.04; pcall(function() bob.CFrame = CFrame.new(biteBase + Vector3.new(math.sin(t*30)*0.18, -math.abs(math.sin(t*16))*0.5, math.cos(t*30)*0.18)) end); task.wait(0.03) end end)
				setStatus("Something's biting! TAP!")
				local hooked = waitForTap(1.3)
				wiggling = false
				if not hooked then
					setStatus("It got away!"); print("[Pet] "..player.Name.." missed the hook")
					pcall(function() bob:Destroy() end); task.wait(1.1)
				else
					print("[Pet] "..player.Name.." hooked"); setStatus("Reel it in!")
					pcall(function() bob:Destroy() end)
					-- STEP 3: REEL-IN tension minigame (blocks until done)
					local rDone, rWin = false, false
					openReelMinigame(function(s) rWin = s; rDone = true end)
					while not rDone do task.wait() end
					if not rWin then
						setStatus("It got away!"); print("[Pet] "..player.Name.." reel-in failed"); task.wait(1.1)
					else
						print("[Pet] "..player.Name.." reeled in")
						pushQuestProg(petId, { started = true, found = ((localQuestProg[petId] and localQuestProg[petId].found) or 0) + 1 }) -- HUD: bump the reeled-in counter
						-- STEP 4: SERVER rolls the catch (pity) -- the client NEVER decides
						local ok, res = pcall(function() return PetFishRoll:InvokeServer() end)
						if ok and type(res) == "table" and res.egg then
							setStatus("You reeled in... an EGG! \xF0\x9F\xA5\x9A"); keepGoing = false; pushQuestProg(petId, { complete = true }) -- HUD: quest complete
							task.wait(0.6); spawnButterEgg(); task.wait(1.4) -- show "EGG!" a moment; the loop-end below hides the backdrop
						elseif ok and type(res) == "table" then
							setStatus("You caught: "..(res.junk or "junk").."!"); showJunk(res.junk or ""); task.wait(1.8)
						else
							setStatus("It got away!"); task.wait(1.1)
						end
					end
				end
			end
			fishing = false
			hideStatus() -- ALWAYS hide the status backdrop when the flow ends (got-away / caught / walked away / owned) so it never lingers
			if not st.owns and not st.eggCaught then fishPrompt.Enabled = true end
		end)
	end)
	-- The prompt part rides ON the player, so the activation distance only needs to cover that tiny gap.
	fishPrompt.MaxActivationDistance = 16
	fishPrompt.HoldDuration = 0
	fishPrompt.Enabled = false  -- starts hidden (the follower begins at lakePos); the loop enables it only at the edge
	-- FOLLOW THE PLAYER + GATE: every frame, move the prompt part to the player so "[E] Fish" appears next to
	-- them (never at the island center). Enable it ONLY while near the exposed butter EDGE (probe throttled to
	-- ~0.2s) so it shows at the shore and hides in the island middle. While a fishing attempt is running, that
	-- attempt owns the prompt's Enabled state (it disables it during cast/reel), so we leave it alone then.
	task.spawn(function()
		local probeTimer, nearCached = 0, false
		while st and not st.owns do
			local dt = RunService.Heartbeat:Wait()
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then fishFollower.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 1.5, 0)) end
			probeTimer = probeTimer - dt
			if probeTimer <= 0 then probeTimer = 0.2; nearCached = isNearButterEdge() end
			if not fishing and not st.eggCaught then fishPrompt.Enabled = (hrp ~= nil) and nearCached end
		end
	end)
	print(string.format("[Pet][DIAG] butter fishing ready: lake=(%.0f,%.0f,%.0f) size=%s", lakePos.X, lakePos.Y, lakePos.Z, (typeof(lakeSize)=="Vector3") and string.format("(%.0f,%.0f,%.0f)", lakeSize.X, lakeSize.Y, lakeSize.Z) or "?"))

	-- avoid a flash of the props for someone who already OWNS the duck
	if st.owns then for _, o in ipairs(st.fishProps) do setVisible(o, false) end end
end

-- ============================================================================================
-- BURRITO ARMADILLO QUEST (questType "dig"). "ARMADILLO TRAIL": grab a SHOVEL at the stand -> dig the active
-- low-poly dirt MOUND (multi-swing: each E-tap shrinks it away + dirt burst) -> fully dug, a DECOY reveals junk
-- + lays ARMADILLO TRACKS leading to the NEXT mound (which then appears) -> follow the trail DigSpot1 -> 2 -> 3
-- -> 4 -> 5 -> BuriedEggSpot, ONE mound at a time (~3-min hunt across the island) -> the final spot reveals the
-- armadillo EGG (rises out) -> Hatch prompt -> shared hatch flow -> the Burrito Armadillo follows. Mounds are
-- CLIENT-BUILT low-poly PARTS (no terrain). The real-dig completion is server-gated (PetDigEvent). Cosmetic-only.
-- ============================================================================================
local function buildBurritoWorld(petId, def, positions)
	local st = petState[petId]
	if st.built then return end
	st.built = true; st.isDigging = true
	local TS = game:GetService("TweenService")
	local extra = positions.extra or {}
	local shovelPos = extra.shovel
	local buriedPos = extra.buriedegg
	-- ARMADILLO TRAIL order: DigSpot1 -> 2 -> 3 -> 4 -> 5 -> BuriedEggSpot (one mound active at a time)
	local digSpots = {
		{ key="dig1", pos=extra.dig1, real=false, label="DigSpot1" },
		{ key="dig2", pos=extra.dig2, real=false, label="DigSpot2" },
		{ key="dig3", pos=extra.dig3, real=false, label="DigSpot3" },
		{ key="dig4", pos=extra.dig4, real=false, label="DigSpot4" },
		{ key="dig5", pos=extra.dig5, real=false, label="DigSpot5" },
		{ key="buriedegg", pos=buriedPos, real=true, label="BuriedEggSpot" },
	}
	st.digProps = {}
	st.hintAnchor = shovelPos or buriedPos -- the on-landing pet-quest hint anchors on the island
	if typeof(buriedPos) ~= "Vector3" then warn("[Pet][DIAG] BuriedEggSpot position MISSING for "..petId.." -- dig quest may not complete") end

	local pgui = player:WaitForChild("PlayerGui")
	-- ===== HUD: just a status pill for dig-result messages (no hot/cold meter -- the dig feedback is in-world) =====
	local hud = Instance.new("ScreenGui"); hud.Name = "BurritoDigHUD"; hud.ResetOnSpawn = false; hud.DisplayOrder = 88; hud.Parent = pgui
	local status = Instance.new("Frame"); status.AnchorPoint = Vector2.new(0.5,0); status.Position = UDim2.new(0.5,0,0.12,0); status.Size = UDim2.new(0,470,0,40)
	status.BackgroundColor3 = Color3.fromRGB(150,96,40); status.BackgroundTransparency = 0.12; status.BorderSizePixel = 0; status.Visible = false; status.Parent = hud
	Instance.new("UICorner", status).CornerRadius = UDim.new(0,10); local sstk = Instance.new("UIStroke", status); sstk.Color = Color3.fromRGB(255,225,150); sstk.Thickness = 2
	local statusText = Instance.new("TextLabel"); statusText.Size = UDim2.new(1,0,1,0); statusText.BackgroundTransparency = 1
	statusText.Font = Enum.Font.GothamBold; statusText.TextSize = 20; statusText.TextColor3 = Color3.new(1,1,1); statusText.Text = ""; statusText.Parent = status
	local function setStatus(t) statusText.Text = t; status.Visible = true end
	local function hideStatus() status.Visible = false end
	-- (NO hot/cold meter -- players find the buried egg by EXPLORING + digging the visible mounds themselves.)
	-- desert junk items (the in-world reveal that RISES out of a decoy hole uses these emoji)
	local DIG_JUNK = { "an old boot", "a cattle skull", "a rusty can", "a prickly cactus", "a horseshoe", "a coyote bone", "a tumbleweed" }
	local DIG_JUNK_EMOJI = { ["an old boot"]="\xF0\x9F\xA5\xBE", ["a cattle skull"]="\xF0\x9F\x92\x80", ["a rusty can"]="\xF0\x9F\xA5\xAB", ["a prickly cactus"]="\xF0\x9F\x8C\xB5", ["a horseshoe"]="\xF0\x9F\xA7\xB2", ["a coyote bone"]="\xF0\x9F\xA6\xB4", ["a tumbleweed"]="\xF0\x9F\x8C\xBE" }

	-- ===== SHARED LOW-POLY SHOVEL + BARREL STYLE (so the barrel, the shovels in it, and the held shovel all
	-- match): one wood-brown tone, one blade metal, one faceting level. =====
	local SH_WOOD   = Color3.fromRGB(124,82,44)   -- wood-brown for ALL wood (barrel staves + shovel shafts/grips)
	local SH_WOOD_D = Color3.fromRGB(94,60,30)    -- darker wood (barrel rims)
	local SH_HOOP   = Color3.fromRGB(96,98,108)   -- metal barrel band/hoop
	local SH_BLADE  = Color3.fromRGB(150,154,164) -- shovel blade metal
	local SH_LEN    = 4.4                          -- shovel shaft length
	-- Build a low-poly SHOVEL model in LOCAL space: PrimaryPart (Root) at the GRIP; local +X runs DOWN the shaft
	-- toward the BLADE. Place it by PivotTo(cf) where cf's +X (RightVector) points grip->blade. Used by both the
	-- barrel (static) and the held shovel (follows the hand) so they're identical.
	local function buildShovel()
		local m = Instance.new("Model"); m.Name = petId.."Shovel"
		local function rp(name, shape, size, color, cf, mat)
			local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
			p.Material = mat or Enum.Material.SmoothPlastic; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false; p.Parent = m
			p.CFrame = cf; return p
		end
		local root = rp("Root", Enum.PartType.Ball, Vector3.new(0.2,0.2,0.2), SH_WOOD, CFrame.new()); root.Transparency = 1; m.PrimaryPart = root
		rp("Handle", Enum.PartType.Cylinder, Vector3.new(SH_LEN,0.26,0.26), SH_WOOD, CFrame.new(SH_LEN/2,0,0), Enum.Material.Wood)        -- shaft along +X
		rp("Grip",   Enum.PartType.Cylinder, Vector3.new(1.3,0.24,0.24), SH_WOOD, CFrame.new(-0.1,0,0) * CFrame.Angles(0,math.rad(90),0), Enum.Material.Wood) -- T grip cross-bar at the top
		rp("Socket", Enum.PartType.Cylinder, Vector3.new(0.6,0.34,0.34), SH_BLADE, CFrame.new(SH_LEN+0.1,0,0), Enum.Material.Metal)        -- shaft->blade collar
		rp("Blade",  Enum.PartType.Block,    Vector3.new(0.45,1.4,1.2), SH_BLADE, CFrame.new(SH_LEN+0.85,0,0), Enum.Material.Metal)        -- flat metal scoop at the far end
		m.Parent = Workspace
		return m
	end
	-- align a model's local +X (shaft) to a world direction `d`, with the grip (pivot) at `gripPos`
	local function shovelCF(gripPos, d) return CFrame.lookAt(gripPos, gripPos + d) * CFrame.Angles(0, math.rad(90), 0) end

	-- ===== HELD SHOVEL (rides on the player's hand once grabbed) =====
	local heldShovel
	local function startHeldShovel()
		if heldShovel then return end
		heldShovel = buildShovel(); heldShovel.Name = petId.."HeldShovel"; st.digProps[#st.digProps+1] = heldShovel
		task.spawn(function()
			while heldShovel and heldShovel.Parent and not st.owns do
				local char = player.Character
				local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hand and hrp then
					local look = hrp.CFrame.LookVector; look = Vector3.new(look.X,0,look.Z)
					if look.Magnitude < 0.1 then look = Vector3.new(0,0,-1) end
					-- shaft points FORWARD + DOWN so the BLADE is toward the ground in front (the 180 FLIP fix);
					-- grip sits at the hand. (Previously the shaft pointed up + the blade faced the wrong way.)
					local dirShaft = (look.Unit + Vector3.new(0,-0.5,0)).Unit
					local gripPos = hand.Position + Vector3.new(0,-0.1,0) - dirShaft*0.4
					heldShovel:PivotTo(shovelCF(gripPos, dirShaft))
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end

	-- ===== SHOVEL BARREL (low-poly wooden barrel of shovels) + "Grab Shovel" prompt =====
	if typeof(shovelPos) == "Vector3" then
		local stand = Instance.new("Model"); stand.Name = petId.."ShovelStand"
		local cyc = function(y) return CFrame.new(shovelPos + Vector3.new(0,y,0)) * CFrame.Angles(0,0,math.rad(90)) end -- vertical cylinder CFrame at height y
		local body = newPart(stand, "Barrel", Enum.PartType.Cylinder, Vector3.new(3.4,2.4,2.4), SH_WOOD, cyc(1.7), Enum.Material.Wood)
		stand.PrimaryPart = body
		newPart(stand, "Bulge", Enum.PartType.Cylinder, Vector3.new(1.5,2.85,2.85), SH_WOOD, cyc(1.7), Enum.Material.Wood)            -- slight middle bulge (classic barrel)
		newPart(stand, "RimBot", Enum.PartType.Cylinder, Vector3.new(0.5,2.55,2.55), SH_WOOD_D, cyc(0.45), Enum.Material.Wood)        -- top + bottom rims
		newPart(stand, "RimTop", Enum.PartType.Cylinder, Vector3.new(0.5,2.55,2.55), SH_WOOD_D, cyc(2.95), Enum.Material.Wood)
		newPart(stand, "Inside", Enum.PartType.Cylinder, Vector3.new(0.4,2.0,2.0), Color3.fromRGB(46,30,16), cyc(3.05), Enum.Material.Wood) -- dark opening (shovels read as sticking OUT of it)
		for _, oy in ipairs({1.0, 2.4}) do newPart(stand, "Hoop", Enum.PartType.Cylinder, Vector3.new(0.32,2.75,2.75), SH_HOOP, cyc(oy), Enum.Material.Metal) end -- metal barrel bands/hoops
		stand.Parent = Workspace; st.digProps[#st.digProps+1] = stand
		-- SHOVELS sticking up out of the barrel (same low-poly shovel as the held one -> matching set): grip + handle
		-- poke UP/out, blade down inside the barrel.
		for i = 1, 3 do
			local ang = (i - 2) * 0.7
			local outward = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local gripPos = shovelPos + Vector3.new(0, 4.8, 0) + outward * 1.1   -- grip high + out (handle sticks out)
			local dirShaft = (Vector3.new(0,-1.6,0) - outward * 0.55).Unit       -- shaft runs DOWN + inward (blade into the barrel)
			local sv = buildShovel(); sv:PivotTo(shovelCF(gripPos, dirShaft)); st.digProps[#st.digProps+1] = sv
		end
		local grab = addPrompt(body, "Grab Shovel", "Shovel Stand", function()
			if st.owns then return end
			if not st.hasShovel then
				st.hasShovel = true
				startHeldShovel()
				floatText(shovelPos + Vector3.new(0,4,0), "Got a shovel! Now find + dig the mounds. \xE2\x9B\x8F")
				print("[Pet] "..player.Name.." grabbed shovel (can dig the mounds now)")
			else
				floatText(shovelPos + Vector3.new(0,4,0), "You already have a shovel!")
			end
		end)
		grab.HoldDuration = 0.3
		print(string.format("[Pet][DIAG] built shovel stand at (%.0f,%.0f,%.0f)", shovelPos.X, shovelPos.Y, shovelPos.Z))
	else
		warn("[Pet][DIAG] ShovelSpot position MISSING for "..petId)
	end

	local N_SWINGS = 6 -- E-taps ("swings") to fully dig a mound away (the active mound shrinks one step per swing)
	-- a dug-up JUNK item RISES out of the decoy hole (in-world reveal), holds, then fades away
	local function junkRise(pos, junkName)
		local j = newPart(Workspace, petId.."DugJunk", Enum.PartType.Ball, Vector3.new(1.3,1.3,1.3), Color3.fromRGB(120,92,60), CFrame.new(pos + Vector3.new(0, -3.0, 0)), Enum.Material.SmoothPlastic)
		st.digProps[#st.digProps+1] = j
		local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,64,0,64); bb.StudsOffset = Vector3.new(0,2.0,0); bb.AlwaysOnTop = true; bb.Adornee = j; bb.Parent = j
		local lb = Instance.new("TextLabel"); lb.Size = UDim2.new(1,0,1,0); lb.BackgroundTransparency = 1; lb.Font = Enum.Font.GothamBold; lb.TextSize = 50; lb.Text = DIG_JUNK_EMOJI[junkName] or "\xF0\x9F\xA6\xB4"; lb.Parent = bb
		TS:Create(j, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = CFrame.new(pos + Vector3.new(0, 1.3, 0)) }):Play() -- rises up out of the hole
		task.delay(2.4, function()
			pcall(function() lb.TextTransparency = 1 end)
			TS:Create(j, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			task.delay(0.6, function() pcall(function() j:Destroy() end) end)
		end)
	end

	-- ===== the ARMADILLO EGG (desert/sandy) RISES UP out of the real hole -> Hatch prompt -> shared hatch flow =====
	local function spawnArmadilloEgg(atPos)
		if st.egg then return end
		st.eggPos = atPos; st.eggCaught = true
		local egg = Instance.new("Model"); egg.Name = petId.."Egg"
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(224,194,148), nil)
		shell.Reflectance = 0.05
		local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Scale = Vector3.new(3.0,4.0,3.0); m.Parent = shell
		visual.PrimaryPart = shell
		for j = 1, 6 do local a = (j-1)*(2*math.pi/6); newPart(visual, "Speck", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.fromRGB(176,118,64), CFrame.new(math.sin(a)*1.2, (j%2==0 and 0.5 or -0.5), math.cos(a)*1.2)) end
		local eggCenter = atPos + Vector3.new(0, 1.7, 0)
		st.eggBaseCF = CFrame.new(eggCenter); st.eggVisual = visual
		local startCF = CFrame.new(atPos + Vector3.new(0, -3.4, 0)) -- start DOWN inside the dug hole...
		st.eggRising = true; visual:PivotTo(startCF)
		st.egg = egg; egg.Parent = Workspace; st.digProps[#st.digProps+1] = egg
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(235,205,150); hl.FillTransparency = 0.5; hl.OutlineColor = Color3.fromRGB(210,168,90); hl.Adornee = visual; hl.Parent = egg
		local hp = addPrompt(shell, "Hatch", "Armadillo Egg", function()
			if st.owns or st.hatching then return end
			if hatchEgg then hatchEgg(petId, def) end
		end)
		hp.Enabled = false -- can't hatch until it has fully risen out of the ground
		-- RISE: tween the egg UP out of the hole (a CFrame lerp via a NumberValue, since Models can't tween directly)
		task.spawn(function()
			local nv = Instance.new("NumberValue"); nv.Value = 0
			nv:GetPropertyChangedSignal("Value"):Connect(function() local t = nv.Value; pcall(function() visual:PivotTo(startCF:Lerp(st.eggBaseCF, t)) end) end)
			TS:Create(nv, TweenInfo.new(1.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 }):Play()
			task.wait(1.2); st.eggRising = false; pcall(function() nv:Destroy() end); hp.Enabled = true
		end)
		-- gentle bob (only AFTER it has risen + while not hatching)
		task.spawn(function() local t = 0
			while st.egg do t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching and not st.eggRising then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.28, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end)
				end
				task.wait(0.05)
			end
		end)
		print("[Pet] armadillo egg rose out of the ground for "..player.Name)
	end

	-- ===== ARMADILLO TRAIL: low-poly PART dirt mounds dug ONE AT A TIME. Each E-tap = one swing that SHRINKS the
	-- mound away + bursts dirt + sound + camera kick (the prompt is on its own anchor so it RE-ARMS every swing).
	-- Fully digging a DECOY reveals JUNK + lays ARMADILLO TRACKS to the NEXT mound (which then appears); the final
	-- spot (BuriedEggSpot) reveals the egg. Spread across the island + done sequentially -> a ~3-minute hunt. =====
	local DIRT, DIRT2 = Color3.fromRGB(150,110,70), Color3.fromRGB(134,96,58)
	-- a LOW-POLY DIRT PILE: a few stacked, rotated square blocks tapering up into a faceted cone/pile -> reads as
	-- ONE angular pile of dirt (NOT stacked bubble-circles). Built around `pos`; digging shrinks the whole model.
	local function buildMound(pos)
		local m = Instance.new("Model"); m.Name = petId.."DigMound"
		local base
		for i, L in ipairs({
			{ w=5.4, h=1.3, y=0.65, yaw=0,  col=DIRT  },
			{ w=4.0, h=1.3, y=1.75, yaw=45, col=DIRT2 },
			{ w=2.7, h=1.2, y=2.75, yaw=20, col=DIRT  },
			{ w=1.5, h=1.1, y=3.6,  yaw=58, col=DIRT2 },
		}) do
			local p = newPart(m, "MoundLayer", Enum.PartType.Block, Vector3.new(L.w, L.h, L.w), L.col, CFrame.new(pos + Vector3.new(0, L.y, 0)) * CFrame.Angles(0, math.rad(L.yaw), 0), Enum.Material.Sand)
			if i == 1 then base = p end
		end
		m.PrimaryPart = base
		m.Parent = Workspace
		return m
	end
	-- ARMADILLO TRACKS: a line of little footprint marks (flat oval + 3 toe dots) on the ground from one mound
	-- toward the next, leading MOST of the way -- the cue the player follows to reach the next mound.
	local function spawnTracks(fromPos, toPos)
		if typeof(fromPos) ~= "Vector3" or typeof(toPos) ~= "Vector3" then return end
		local flat = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
		local dist = flat.Magnitude; if dist < 3 then return end
		local dir = flat.Unit
		local right = Vector3.new(-dir.Z, 0, dir.X)
		local n = math.clamp(math.floor(dist / 7), 4, 16) -- a footprint roughly every ~7 studs
		for k = 1, n do
			local frac = (k / (n + 1)) * 0.85 + 0.05 -- lead MOST of the way (stop short of the next mound)
			local p = fromPos + dir * (dist * frac)
			local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { player.Character }; rp.IgnoreWater = true
			local hit = Workspace:Raycast(p + Vector3.new(0,14,0), Vector3.new(0,-90,0), rp)
			local y = hit and hit.Position.Y or p.Y
			local side = (k % 2 == 0) and 1 or -1
			local fp = Vector3.new(p.X, y + 0.08, p.Z) + right * (side * 0.7)
			local cf = CFrame.lookAt(fp, fp + dir)
			local foot = newPart(Workspace, petId.."Track", Enum.PartType.Ball, Vector3.new(0.95,0.12,1.35), Color3.fromRGB(96,62,34), cf) -- flat oval print
			foot.Transparency = 1; st.digProps[#st.digProps+1] = foot
			for _, tx in ipairs({ -0.3, 0, 0.3 }) do -- 3 toe dots ahead -> armadillo-print look
				local toe = newPart(Workspace, petId.."Track", Enum.PartType.Ball, Vector3.new(0.26,0.1,0.26), Color3.fromRGB(80,52,28), cf * CFrame.new(tx, 0, -0.72))
				toe.Transparency = 1; st.digProps[#st.digProps+1] = toe
			end
			TS:Create(foot, TweenInfo.new(0.3), { Transparency = 0.1 }):Play()
		end
	end

	local spots = {}   -- [i] = { spot, mound, prompt } (or false if the marker position is missing)
	local activateStep -- forward-decl (doSwing advances the trail via this)

	for i, spot in ipairs(digSpots) do
		if typeof(spot.pos) ~= "Vector3" then
			warn("[Pet][DIAG] dig spot "..spot.label.." position MISSING for "..petId)
			spots[i] = false
		else
			local mound = buildMound(spot.pos); setVisible(mound, false) -- built hidden; shown when this step is active
			st.digProps[#st.digProps+1] = mound
			-- the "Dig" prompt rides on its OWN persistent anchor, so shrinking/hiding the mound never removes it
			-- (BUGFIX kept) -> it re-arms every E-press (HoldDuration 0 -> one swing per press) until fully dug.
			local promptAnchor = newPart(Workspace, petId.."DigPrompt", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.new(1,1,1), CFrame.new(spot.pos + Vector3.new(0,1.5,0)))
			promptAnchor.Transparency = 1; st.digProps[#st.digProps+1] = promptAnchor
			local swings, fxAnchor, em, snd, done = 0, nil, nil, nil, false
			local prompt -- forward-decl so doSwing can disable it on the final swing
			local function doSwing()
				if not fxAnchor then
					fxAnchor = newPart(Workspace, petId.."DigFX", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(120,84,52), CFrame.new(spot.pos + Vector3.new(0,0.6,0)))
					fxAnchor.Transparency = 1
					em = Instance.new("ParticleEmitter"); em.Texture = "rbxasset://textures/particles/smoke_main.dds"
					em.Color = ColorSequence.new(Color3.fromRGB(150,110,70), Color3.fromRGB(110,78,46)); em.Lifetime = NumberRange.new(0.4,0.85)
					em.Speed = NumberRange.new(10,18); em.SpreadAngle = Vector2.new(40,40); em.EmissionDirection = Enum.NormalId.Top
					em.Acceleration = Vector3.new(0,-44,0); em.Size = NumberSequence.new(0.9); em.Rate = 0; em.Rotation = NumberRange.new(0,360); em.Parent = fxAnchor
					snd = Instance.new("Sound"); snd.SoundId = "rbxassetid://9114065998"; snd.Volume = 0.55; snd.Parent = fxAnchor -- PLACEHOLDER dirt/shovel dig sound -- swap freely
				end
				swings = swings + 1
				pcall(function() mound:ScaleTo(math.max(0.06, 1 - swings / N_SWINGS)) end) -- SHRINK the low-poly mound away one step (the part-based dig)
				pcall(function() em:Emit(20) end)                              -- DIRT burst this swing
				pcall(function() snd.TimePosition = 0; snd:Play() end)         -- dig SOUND this swing
				pcall(function()                                               -- small camera kick for feel
					local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if hum then hum.CameraOffset = Vector3.new((math.random()-0.5)*0.5, -0.35, 0); TS:Create(hum, TweenInfo.new(0.18), {CameraOffset = Vector3.zero}):Play() end
				end)
				print(string.format("[Pet][DIG] swing %d/%d on %s", swings, N_SWINGS, spot.label))
				if swings >= N_SWINGS then -- mound fully dug -> reveal + advance the trail
					done = true; prompt.Enabled = false
					pushQuestProg(petId, { started = true, found = ((localQuestProg[petId] and localQuestProg[petId].found) or 0) + 1, total = #digSpots }) -- HUD: "Mounds X/6"
					pcall(function() setVisible(mound, false) end)
					if em then task.delay(0.4, function() em.Enabled = false end) end
					if fxAnchor then game:GetService("Debris"):AddItem(fxAnchor, 1.2) end
					if spot.real then
						print("[Pet][DIG] BuriedEggSpot dug -> EGG rises")
						pcall(function() PetDigEvent:FireServer(petId) end) -- server unlocks the claim (anti-cheat gate)
						pushQuestProg(petId, { complete = true }) -- HUD: armadillo quest complete
						setStatus("You unearthed the armadillo egg! \xF0\x9F\xA5\x9A"); task.delay(2.6, hideStatus)
						spawnArmadilloEgg(spot.pos)
					else
						local junk = DIG_JUNK[math.random(1, #DIG_JUNK)]
						junkRise(spot.pos, junk)
						local nextSpot = digSpots[i+1]
						local nextPos = nextSpot and nextSpot.pos
						local nextLabel = (nextSpot and nextSpot.label) or "?"
						if nextPos then spawnTracks(spot.pos, nextPos) end
						print(string.format("[Pet][DIG] %s dug -> junk (%s), tracks spawned toward %s", spot.label, junk, nextLabel))
						setStatus("You dug up: "..junk.."! Follow the tracks..."); task.delay(2.6, hideStatus)
						task.delay(0.4, function() activateStep(i + 1) end)
					end
				end
			end
			prompt = addPrompt(promptAnchor, "Dig", "Dig Spot", function() -- each E-tap = ONE swing (HoldDuration 0 -> per-press)
				if st.owns or st.eggCaught or done then return end
				if not st.hasShovel then floatText(spot.pos + Vector3.new(0,3,0), "Grab a shovel first!"); return end
				doSwing()
			end)
			prompt.HoldDuration = 0; prompt.MaxActivationDistance = 12; prompt.Enabled = false -- enabled by activateStep when this is the active mound
			spots[i] = { spot = spot, mound = mound, prompt = prompt }
			print(string.format("[Pet][DIAG] built trail mound %s (step %d/%d, real=%s) at (%.0f,%.0f,%.0f)", spot.label, i, #digSpots, tostring(spot.real), spot.pos.X, spot.pos.Y, spot.pos.Z))
		end
	end

	-- show + enable the active step's mound (one at a time); skip any step whose marker position is missing
	activateStep = function(n)
		if n > #digSpots then return end
		local e = spots[n]
		if not e then return activateStep(n + 1) end
		setVisible(e.mound, true)
		if not st.owns and not st.eggCaught then e.prompt.Enabled = true end
		print(string.format("[Pet][DIG] active mound: %s (trail step %d/%d)", e.spot.label, n, #digSpots))
	end
	if not st.owns then activateStep(1) end -- start the Armadillo Trail at the first mound

	print(string.format("[Pet][DIAG] burrito dig ready: shovel=%s buriedegg=%s", shovelPos and "yes" or "no", buriedPos and "yes" or "no"))
	-- avoid a flash of the props for someone who already OWNS the armadillo
	if st.owns then for _, o in ipairs(st.digProps) do setVisible(o, false) end end
end

-- Build the pieces + egg for a pet from SERVER-PROVIDED positions (the client never searches Workspace).
-- positions = { pieces = { [i]=Vector3 }, egg = Vector3 }. Pieces/egg start hidden; PetStateEvent reveals
-- the uncollected pieces (when !owns) and the egg (when found==total).
local function buildPetWorld(petId, def, positions)
	local st = petState[petId]
	if st.built then return end
	positions = positions or {}
	if def.questType == "crack" then return buildCoconutWorld(petId, def, positions) end -- coconut quest has its own world
	if def.questType == "film-reels" then return buildPopcornWorld(petId, def, positions) end -- popcorn quest has its own world
	if def.questType == "fishing" then return buildButterWorld(petId, def, positions) end -- butter duck quest has its own world
	if def.questType == "dig" then return buildBurritoWorld(petId, def, positions) end -- burrito armadillo dig quest has its own world
	st.built = true
	local pieces = positions.pieces or {}
	-- 3 collectible pieces (built at the received coordinates)
	for i = 1, #def.pieceMarkers do
		local pos = pieces[i]
		if typeof(pos) == "Vector3" then
			local piece = buildBroccoliBlob(0.7, false)
			piece:PivotTo(CFrame.new(pos))
			addPrompt(piece.PrimaryPart, "Collect", (def.pieceLabel or "Pet").." Piece", function() -- no name-number: which piece doesn't matter
				if st.collected[i] or st.owns then return end
				st.collected[i] = true -- track WHICH pieces (index = dedup key); the same piece can't count twice
				-- DISPLAYED number = how many DISTINCT pieces collected so far (running total), NOT the piece index i
				local count = 0; for _, v in pairs(st.collected) do if v then count = count + 1 end end
				setVisible(piece, false)
				floatText(pos, (def.pieceLabel or "Pet").." piece "..count.."/"..#def.pieceMarkers.."!")
				pcall(function() PetCollectEvent:FireServer(petId, i) end) -- send the index so the server dedups by piece
			end)
			st.pieces[i] = piece
			setVisible(piece, false) -- hidden until PetStateEvent confirms !owns (avoids a flash for owners)
			print(string.format("[Pet][DIAG] built piece %d at (%.0f,%.0f,%.0f) with Collect prompt", i, pos.X, pos.Y, pos.Z))
		else
			warn("[Pet][DIAG] piece "..i.." position MISSING from server for "..petId)
		end
	end
	-- EGG (ovoid) sitting in a twiggy NEST, built at the received coordinate; shown only when found==total.
	local eggPos = positions.egg
	if typeof(eggPos) == "Vector3" then
		st.eggPos = eggPos -- raw egg coordinate (for the quest pointer + landing-hint island anchor)
		local egg = Instance.new("Model"); egg.Name = petId.."Egg" -- CONTAINER (egg visual + nest -> one visibility toggle)

		-- NEST: low-poly brown twig ring/bowl the egg nestles into (STATIC -- does not bob).
		local nest = Instance.new("Model"); nest.Name = "Nest"; nest.Parent = egg
		local nestCenter = CFrame.new(eggPos + Vector3.new(0, 1.0, 0))
		for k = 1, 14 do
			local a = (k-1) * (2*math.pi/14)
			local twig = newPart(nest, "Twig", Enum.PartType.Cylinder, Vector3.new(2.2, 0.55, 0.55), Color3.fromRGB(105, 65, 38), nil, Enum.Material.Wood)
			twig.CFrame = nestCenter * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.7) * CFrame.Angles(0, math.rad(90), math.rad(18))
		end
		for k = 1, 10 do -- a lower second layer for a bowl look
			local a = (k-1) * (2*math.pi/10) + 0.3
			local twig = newPart(nest, "Twig", Enum.PartType.Cylinder, Vector3.new(2.0, 0.5, 0.5), Color3.fromRGB(90, 55, 32), nil, Enum.Material.Wood)
			twig.CFrame = nestCenter * CFrame.new(0, -0.7, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.2) * CFrame.Angles(0, math.rad(90), math.rad(30))
		end

		-- EGG VISUAL: an ovoid (taller than wide, tapered top) with broccoli-green speckles. This sub-model
		-- BOBS and is what CRACKS on hatch (the nest stays put). PrimaryPart = the main shell.
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		-- ONE smooth egg ovoid (NOT two stacked spheres): a unit Part with a built-in Sphere SpecialMesh
		-- stretched taller-than-wide via a non-uniform Mesh.Scale -> a single continuous egg silhouette.
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1, 1, 1), Color3.fromRGB(208, 232, 178), nil)
		shell.Reflectance = 0.06 -- slight gloss
		local eggMesh = Instance.new("SpecialMesh")
		eggMesh.MeshType = Enum.MeshType.Sphere
		eggMesh.Scale = Vector3.new(3.0, 4.2, 3.0) -- W x H x D: taller than wide = egg shape
		eggMesh.Parent = shell
		visual.PrimaryPart = shell
		-- broccoli-green speckles dusted around the single ovoid surface (x/z radius ~1.5, height ~2.1)
		for j = 1, 9 do
			local a = (j-1) * (2*math.pi/9)
			local y = math.sin(a*1.8) * 1.05 -- wander up/down the egg
			local r = 1.42 * math.sqrt(math.max(0, 1 - (y/2.1)^2)) + 0.04 -- hug the ovoid surface at this height
			newPart(visual, "Spot", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.fromRGB(70, 150, 70),
				CFrame.new(math.sin(a)*r, y, math.cos(a)*r))
		end

		st.eggBaseCF = CFrame.new(eggPos + Vector3.new(0, 2.6, 0)) -- the egg sits IN the nest
		st.eggVisual = visual
		visual:PivotTo(st.eggBaseCF)
		st.egg = egg
		setVisible(egg, false)

		addPrompt(shell, "Hatch", (def.pieceLabel or "Pet").." Egg", function()
			if st.owns or st.hatching then return end
			if hatchEgg then hatchEgg(petId, def) end -- E -> hatch animation, THEN the claim registers
		end)

		-- gentle idle bob/wiggle for the EGG VISUAL only (paused during the hatch); the nest stays still
		task.spawn(function()
			local t = 0
			while st.egg do
				t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.3, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.12, math.rad(math.sin(t*2)*5))) end)
				end
				task.wait(0.05)
			end
		end)
		print(string.format("[Pet][DIAG] egg + nest built at (%.0f,%.0f,%.0f) (shows at 3/3)", eggPos.X, eggPos.Y, eggPos.Z))
	else
		warn("[Pet][DIAG] egg position MISSING from server for "..petId)
	end
end

-- ===== FOLLOWER PET (the key part: smooth follow, keeps up during fast flight) =====
local FOLLOW_OFFSET = Vector3.new(3.5, 1.5, 5)  -- right, up, BEHIND (+Z) in the player's local frame
local FOLLOW_K      = 6    -- POSITION responsiveness (lower = softer, flowier glide -- was 12, now eased)
local FACE_K        = 4    -- FACING responsiveness (slower than FOLLOW_K so the pet SWINGS round to turn, not snap)
local MAX_TRAIL     = 45   -- never let the pet fall further than this behind -> can't be lost in a fast ascent
local petSmoothPos  = nil  -- smoothed follow position (no bob)
local petSmoothFwd  = nil  -- smoothed facing direction (eased -> graceful swing turns)
local bobT          = 0

-- ============================================================================================
-- ACCUMULATING PRESTIGE VISUALS (Stage 1 visual progression). PURELY COSMETIC -- every effect is Massless,
-- CanCollide=false, no physics/flight role. As a pet levels 1->50 it accumulates: a small CONTINUOUS color/
-- intensity creep EVERY level, plus STACKING milestone pieces -- 10 trail, 20 aura, 30 sparkles + slightly
-- bigger, 40 a themed accessory, 50 MAX (rainbow shimmer + biggest trail + max sparkles + GOLD accessory +
-- MAX badge). Themed per pet. Idempotent: clears + re-applies so equip and live level-ups refresh cleanly.
-- ============================================================================================
local PRESTIGE_GOLD = Color3.fromRGB(255,200,40)
-- per-pet UPGRADE theme: themed effect color (trail/aura/sparkles), per-location anchors in the pet's own model
-- space (head/face/neck/back/ear/side), glasses lens half-spread, and the EXACT accessory schedule (level ->
-- accessory key). The BASE PET IS NEVER MODIFIED -- only size, the listed effects, and these accessories are added.
local PET_THEME = {
	BroccoliPet = { color=Color3.fromRGB(120,210,70),
		head=CFrame.new(0.05,1.62,0), face=CFrame.new(1.5,0.45,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(0.1,1.7,0.95), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	CoconutCrab = { color=Color3.fromRGB(170,100,60),
		head=CFrame.new(-0.1,1.0,0), face=CFrame.new(0.92,0.78,0), glassW=0.4, neck=CFrame.new(0.7,0.05,0), back=CFrame.new(-0.85,0.45,0), side=CFrame.new(0,0.2,1.15), side2=CFrame.new(0,0.2,-1.15),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"piratehat"},{13,"backpack"},{17,"sword"},{20,"gemcluster"},{23,"anchor"} } },
	PopcornSheep = { color=Color3.fromRGB(248,244,230),
		head=CFrame.new(1.1,1.55,0), face=CFrame.new(1.65,0.4,0), glassW=0.45, neck=CFrame.new(1.1,-0.35,0), back=CFrame.new(-1.4,0.4,0), ear=CFrame.new(0.5,1.6,0.85), side=CFrame.new(0.3,-0.2,1.4),
		accs={ {3,"bell"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"flower"},{20,"cloudcluster"},{23,"crook"} } },
	ButterDuck = { color=Color3.fromRGB(250,205,75),
		head=CFrame.new(0.15,1.6,0), face=CFrame.new(1.5,0.5,0), glassW=0.5, neck=CFrame.new(1.3,-0.3,0), back=CFrame.new(-1.4,0.4,0), side=CFrame.new(0.3,-0.3,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"monocle"},{20,"sparklecluster"},{23,"cane"} } },
	BurritoArmadillo = { color=Color3.fromRGB(200,160,110),
		head=CFrame.new(1.15,1.4,0), face=CFrame.new(1.5,0.8,0), glassW=0.45, neck=CFrame.new(1.2,0.15,0), back=CFrame.new(-1.5,0.35,0), side=CFrame.new(0.2,-0.1,1.5), side2=CFrame.new(0.2,-0.1,-1.5),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"safari"},{13,"backpack"},{17,"gemstuds"},{20,"lantern"},{23,"pickaxe"} } },
	-- SEASONAL PETS: reuse the standard body/head anchors so they get the same level scaling + accessory schedule.
	SunflowerBee = { color=Color3.fromRGB(250,205,60),
		head=CFrame.new(0.05,1.62,0), face=CFrame.new(1.5,0.45,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(0.1,1.7,0.95), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	MapleFox = { color=Color3.fromRGB(222,120,52),
		head=CFrame.new(0.05,1.62,0), face=CFrame.new(1.5,0.45,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(0.2,2.35,1.0), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	FrostPenguin = { color=Color3.fromRGB(120,150,200),
		head=CFrame.new(0.15,1.6,0), face=CFrame.new(1.5,0.5,0), glassW=0.5, neck=CFrame.new(1.3,-0.3,0), back=CFrame.new(-1.4,0.4,0), side=CFrame.new(0.3,-0.3,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"monocle"},{20,"sparklecluster"},{23,"cane"} } },
	BlossomBunny = { color=Color3.fromRGB(186,224,150),
		head=CFrame.new(0.05,1.62,0), face=CFrame.new(1.5,0.45,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(0.1,1.7,0.95), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
}
local petFX = {}         -- [pet] = animated effect state (orbs/ring/pulse/burst/shimmer) driven by the FX loop
-- RARE variant looks (Stage 2): body sheen (color/material/reflectance) + a rare-only sparkle aura. Cosmetic.
local RARE_LOOK = {
	BroccoliPet      = { name="Emerald Bunny",    body=Color3.fromRGB(20,150,80),   mat=Enum.Material.Glass,  refl=0.25, fx=Color3.fromRGB(70,255,150) },                       -- emerald crystal sheen + green crystal sparkles
	CoconutCrab      = { name="Golden Crab",      body=Color3.fromRGB(255,200,40),  mat=Enum.Material.Metal,  refl=0.35, fx=Color3.fromRGB(255,225,90) },                        -- solid shiny gold + gold sparkles
	PopcornSheep     = { name="Cloud Sheep",      body=Color3.fromRGB(212,232,255), mat=Enum.Material.Plastic,refl=0.1,  fx=Color3.fromRGB(225,242,255), puffs=true, light=true }, -- white-blue cloud sheen + cloud puffs + soft light
	BurritoArmadillo = { name="Crystal Armadillo",body=Color3.fromRGB(150,80,210),  mat=Enum.Material.Glass,  refl=0.25, fx=Color3.fromRGB(195,125,255) },                       -- amethyst crystal sheen + crystal-shard sparkles
	ButterDuck       = { name="Cosmic Duck",      body=Color3.fromRGB(30,24,66),    mat=Enum.Material.Plastic,refl=0.1,  fx=Color3.fromRGB(180,140,255), cosmic=true, light=true }, -- deep-space body + swirling stars + rainbow cosmic aura (showstopper)
}
-- ===== RARITY TIER LABELS (shared by the inventory card + the floating overhead label) =====
-- Normal pets: tier by LEVEL (Common->Legendary). Rare variants: special TOP tiers (Exotic, or Mythical for the
-- 1/500 Cosmic Duck) that outrank Legendary. Escalating colors; Exotic/Mythical are the flashiest (glow).
local function petTier(level, isRare, petId)
	if isRare then
		if petId == "ButterDuck" then return "Mythical", Color3.fromRGB(255,70,230), true, true  -- top tier, flashiest (magenta glow)
		else return "Exotic", Color3.fromRGB(40,235,225), true, true end                          -- above Legendary (bright cyan/teal glow)
	end
	if level <= 5      then return "Common",    Color3.fromRGB(175,180,190), false, false
	elseif level <= 10 then return "Uncommon",  Color3.fromRGB(90,210,90),   false, false
	elseif level <= 15 then return "Rare",      Color3.fromRGB(70,140,255),  false, false
	elseif level <= 20 then return "Epic",      Color3.fromRGB(180,90,235),  false, false
	else                    return "Legendary", Color3.fromRGB(255,170,40),  false, false end
end
local PET_DISPLAY = { BroccoliPet="Broccoli Bunny", CoconutCrab="Coconut Crab", PopcornSheep="Popcorn Sheep", ButterDuck="Butter Duck", BurritoArmadillo="Burrito Armadillo",
	SunflowerBee="Sunflower Bee", MapleFox="Maple Fox", FrostPenguin="Frost Penguin", BlossomBunny="Blossom Bunny" }
-- the name shown above a pet: the rare variant name if rare, else the normal display name.
local function petDisplayName(petId, isRare) return (isRare and RARE_LOOK[petId] and RARE_LOOK[petId].name) or PET_DISPLAY[petId] or petId end
local function flagAccPart(p) -- clean matte-plastic cosmetic flags (matches the pet style; never collides/affects physics)
	p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.CastShadow=false; p.Massless=true
	p.Material=Enum.Material.Plastic
	local SM=Enum.SurfaceType.Smooth
	p.TopSurface=SM; p.BottomSurface=SM; p.LeftSurface=SM; p.RightSurface=SM; p.FrontSurface=SM; p.BackSurface=SM
end
local accScale = 1
-- create one ACCESSORY part, WELD it into the pet's animation list (role "body" -> tracks the pet's bob/sway +
-- the size tier each frame; it can never float off). `cf` is object-space relative to the root. Returns the part.
local function accPart(pet, A, root, shape, sx, sy, sz, color, cf)
	local R = accScale
	local size = Vector3.new(sx*R, sy*R, sz*R)
	local bcf = CFrame.new(cf.Position * R) * (cf - cf.Position) -- scale offset, keep rotation
	local p = Instance.new("Part"); p.Name="EvoPart"; p.Shape=shape; p.Size=size; p.Color=color
	flagAccPart(p); p.CFrame = root.CFrame * bcf; p.Parent = pet
	A.parts[#A.parts+1] = { part=p, base=bcf, baseSize=size, role="body", eye=false }
	return p
end
-- create a free-standing EFFECT part (orbs/ring/pulse): parented to the pet but NOT animated by animatePet -- the
-- FX loop positions/scales it each frame. Glowing (Neon) when `neon`. Massless/CanCollide=false (no flight impact).
local function fxPart(pet, name, shape, sx, sy, sz, color, neon)
	local p = Instance.new("Part"); p.Name=name; p.Shape=shape; p.Size=Vector3.new(sx,sy,sz); p.Color=color
	flagAccPart(p); if neon then p.Material = Enum.Material.Neon end
	p.Parent = pet; return p
end
local BAL_, BLK_, CYL_ = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
-- Build ONE accessory by key, welded onto the pet (base pet untouched), at the right per-pet anchor for its
-- location. GOLD-trimmed when `gold` (lvl 25 MAX). Builds EXACTLY the listed parts -- nothing extra.
local function buildAccessoryByKey(pet, A, root, theme, key, gold)
	if key == "bowtie" then                 -- two wings + a center knot, at the neck
		local n = theme.neck; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(175,45,55)
		for _,sgn in ipairs({1,-1}) do accPart(pet,A,root, BLK_, 0.16,0.36,0.4, c, n * CFrame.new(0,0,0.3*sgn) * CFrame.Angles(math.rad(22*sgn),0,0)) end
		accPart(pet,A,root, BLK_, 0.2,0.22,0.22, gold and Color3.fromRGB(225,180,60) or Color3.fromRGB(120,30,40), n)
	elseif key == "glasses" then            -- two round lens frames over the eyes (no bridge)
		local f = theme.face; local w = theme.glassW or 0.48; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(30,30,36)
		for _,sgn in ipairs({1,-1}) do accPart(pet,A,root, CYL_, 0.1,0.42,0.42, c, f * CFrame.new(0,0,w*sgn)) end
	elseif key == "monocle" then            -- a single round lens over one eye
		local f = theme.face; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(30,30,36)
		accPart(pet,A,root, CYL_, 0.12,0.46,0.46, c, f * CFrame.new(0,0,(theme.glassW or 0.5)))
	elseif key == "bell" then               -- a collar band + a round bell, around the neck
		local collar = gold and PRESTIGE_GOLD or Color3.fromRGB(170,45,55)
		local bell   = gold and PRESTIGE_GOLD or Color3.fromRGB(212,176,80)
		accPart(pet,A,root, CYL_, 1.5,0.22,0.22, collar, theme.neck * CFrame.Angles(0,math.rad(90),0))
		accPart(pet,A,root, BAL_, 0.42,0.46,0.42, bell, theme.neck * CFrame.new(0.05,-0.34,0))
	elseif key == "scarf" then              -- a scarf band around the neck + a hanging end
		local n = theme.neck; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(70,120,180)
		accPart(pet,A,root, CYL_, 1.4,0.26,0.26, c, n * CFrame.Angles(0,math.rad(90),0))
		accPart(pet,A,root, BLK_, 0.5,0.16,0.3, c, n * CFrame.new(-0.18,-0.42,0.32))
	elseif key == "backpack" then           -- a pack box + two straps, on the back
		local b = theme.back; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(120,90,58)
		accPart(pet,A,root, BLK_, 0.65,0.8,0.9, c, b)
		for _,sgn in ipairs({1,-1}) do accPart(pet,A,root, BLK_, 0.55,0.12,0.16, gold and Color3.fromRGB(225,185,70) or Color3.fromRGB(88,64,40), b * CFrame.new(0.5,0.12,0.42*sgn)) end
	elseif key == "flower" then             -- 5 petals + a center, tucked by one ear
		local e = theme.ear; local petal = gold and PRESTIGE_GOLD or Color3.fromRGB(240,120,160); local center = gold and PRESTIGE_GOLD or Color3.fromRGB(250,210,90)
		for k=0,4 do local ang=math.rad(k*72); accPart(pet,A,root, BAL_, 0.22,0.22,0.22, petal, e * CFrame.new(math.sin(ang)*0.24, math.cos(ang)*0.24, 0)) end
		accPart(pet,A,root, BAL_, 0.18,0.18,0.18, center, e)
	elseif key == "sword" then              -- a small cutlass (handle + guard + blade), on the shell side
		local s = theme.side; local blade = gold and PRESTIGE_GOLD or Color3.fromRGB(200,205,215)
		accPart(pet,A,root, BLK_, 0.16,0.28,0.16, Color3.fromRGB(90,60,38), s)                       -- handle
		accPart(pet,A,root, BLK_, 0.34,0.12,0.12, gold and PRESTIGE_GOLD or Color3.fromRGB(205,170,70), s * CFrame.new(0,0.16,0)) -- guard
		accPart(pet,A,root, BLK_, 0.14,1.0,0.14, blade, s * CFrame.new(0,0.7,0))                      -- blade (up)
	elseif key == "crown" then              -- band + 5 prongs, on top of the head
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(212,182,66)
		accPart(pet,A,root, CYL_, 0.16,1.05,1.05, c, h * CFrame.Angles(0,0,math.rad(90)))
		for i=0,4 do local ang=math.rad(i*72); accPart(pet,A,root, CYL_, 0.5,0.16,0.16, c, h * CFrame.new(math.sin(ang)*0.42, 0.3, math.cos(ang)*0.42) * CFrame.Angles(0,0,math.rad(90))) end
	elseif key == "piratehat" then          -- brim + crown + front trim, on top
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(34,34,40)
		accPart(pet,A,root, BAL_, 1.5,0.45,1.15, c, h)
		accPart(pet,A,root, BAL_, 0.95,0.78,0.85, c, h * CFrame.new(-0.05,0.45,0))
		accPart(pet,A,root, CYL_, 1.0,0.2,0.2, gold and Color3.fromRGB(255,225,90) or Color3.fromRGB(225,185,70), h * CFrame.new(0.45,0.05,0) * CFrame.Angles(0,math.rad(90),0))
	elseif key == "tophat" then             -- brim + crown + band, on top
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(35,35,40)
		accPart(pet,A,root, CYL_, 0.12,1.2,1.2, c, h * CFrame.new(0,-0.05,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.78,0.74,0.74, c, h * CFrame.new(0,0.42,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.2,0.78,0.78, gold and Color3.fromRGB(225,180,60) or Color3.fromRGB(170,40,50), h * CFrame.new(0,0.16,0) * CFrame.Angles(0,0,math.rad(90)))
	elseif key == "safari" then             -- wide brim + shallow crown + band, on top
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(156,138,96)
		accPart(pet,A,root, CYL_, 0.12,1.5,1.5, c, h * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, BAL_, 0.95,0.66,0.95, c, h * CFrame.new(0,0.34,0))
		accPart(pet,A,root, CYL_, 0.2,0.92,0.92, gold and Color3.fromRGB(255,225,90) or Color3.fromRGB(110,92,60), h * CFrame.new(0,0.12,0) * CFrame.Angles(0,0,math.rad(90)))
	elseif key == "haloring" then           -- BUNNY: a glowing ring of beads above the head
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(150,235,90)
		for i=0,9 do local ang=math.rad(i*36); local p=accPart(pet,A,root, BAL_, 0.16,0.16,0.16, c, h * CFrame.new(math.sin(ang)*0.6, 0.85, math.cos(ang)*0.6)); p.Material=Enum.Material.Neon end
	elseif key == "staff" then              -- BUNNY: a side scepter (shaft + glowing orb top)
		local s = theme.side
		accPart(pet,A,root, CYL_, 1.7,0.14,0.14, Color3.fromRGB(120,84,46), s * CFrame.new(0,0.4,0) * CFrame.Angles(0,0,math.rad(90)))
		local p=accPart(pet,A,root, BAL_, 0.42,0.42,0.42, gold and PRESTIGE_GOLD or Color3.fromRGB(150,235,90), s * CFrame.new(0,1.3,0)); p.Material=Enum.Material.Neon
	elseif key == "anchor" then             -- CRAB: a tiny anchor on the other shell side (shaft + crossbar + flukes)
		local s = theme.side2 or theme.side; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(150,154,164)
		accPart(pet,A,root, CYL_, 1.0,0.14,0.14, c, s * CFrame.new(0,0.2,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.6,0.14,0.14, c, s * CFrame.new(0,0.6,0) * CFrame.Angles(math.rad(90),0,0))
		for _,sgn in ipairs({1,-1}) do accPart(pet,A,root, BLK_, 0.4,0.14,0.14, c, s * CFrame.new(0.18*sgn,-0.2,0) * CFrame.Angles(0,0,math.rad(40*sgn))) end
	elseif key == "gemcluster" then         -- CRAB: a cluster of glowing gem studs on the shell top
		local cols = { Color3.fromRGB(95,215,205), Color3.fromRGB(120,180,255), Color3.fromRGB(235,225,205) }
		for k=0,3 do local p=accPart(pet,A,root, BAL_, 0.3,0.3,0.3, gold and PRESTIGE_GOLD or cols[(k%3)+1], CFrame.new(-0.35+k*0.28, 0.95, -0.1+(k%2)*0.3)); p.Material=Enum.Material.Neon end
	elseif key == "crook" then              -- SHEEP: a side shepherd's-crook (shaft + hook)
		local s = theme.side; local c = Color3.fromRGB(150,110,64)
		accPart(pet,A,root, CYL_, 1.8,0.14,0.14, c, s * CFrame.new(0,0.4,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.5,0.13,0.13, c, s * CFrame.new(-0.18,1.35,0) * CFrame.Angles(0,0,math.rad(35)))
		accPart(pet,A,root, CYL_, 0.4,0.13,0.13, c, s * CFrame.new(-0.42,1.18,0) * CFrame.Angles(0,0,math.rad(80)))
	elseif key == "cloudcluster" then       -- SHEEP: a small cluster of cloud puffs above
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(255,255,255)
		for k=0,3 do local ang=math.rad(k*90); accPart(pet,A,root, BAL_, 0.45,0.4,0.45, c, h * CFrame.new(math.sin(ang)*0.5, 0.8, math.cos(ang)*0.5)) end
	elseif key == "sparklecluster" then     -- DUCK: a small cluster of glowing butter sparkles
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(255,225,110)
		for k=0,3 do local ang=math.rad(k*90); local p=accPart(pet,A,root, BAL_, 0.26,0.26,0.26, c, h * CFrame.new(math.sin(ang)*0.7, 0.55, math.cos(ang)*0.7)); p.Material=Enum.Material.Neon end
	elseif key == "cane" then               -- DUCK: a side cane (shaft + J handle)
		local s = theme.side; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(40,30,26)
		accPart(pet,A,root, CYL_, 1.7,0.13,0.13, c, s * CFrame.new(0,0.35,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.45,0.13,0.13, c, s * CFrame.new(-0.16,1.25,0) * CFrame.Angles(0,0,math.rad(55)))
	elseif key == "gemstuds" then           -- ARMADILLO: a row of glowing gem studs on the shell
		for k=0,3 do local p=accPart(pet,A,root, BAL_, 0.26,0.26,0.26, gold and PRESTIGE_GOLD or Color3.fromRGB(120,200,210), CFrame.new(-0.7+k*0.5, 1.6, 0)); p.Material=Enum.Material.Neon end
	elseif key == "lantern" then            -- ARMADILLO: a tiny glowing lantern at the side
		local s = theme.side; local frame = gold and PRESTIGE_GOLD or Color3.fromRGB(90,72,46)
		accPart(pet,A,root, CYL_, 0.16,0.1,0.1, frame, s * CFrame.new(0,0.55,0) * CFrame.Angles(0,0,math.rad(90)))
		local p=accPart(pet,A,root, BLK_, 0.5,0.6,0.5, Color3.fromRGB(255,225,110), s); p.Material=Enum.Material.Neon
		accPart(pet,A,root, BLK_, 0.6,0.12,0.6, frame, s * CFrame.new(0,-0.34,0))
	elseif key == "pickaxe" then            -- ARMADILLO: a tiny pickaxe on the other shell side
		local s = theme.side2 or theme.side; local wood = Color3.fromRGB(120,84,46); local head = gold and PRESTIGE_GOLD or Color3.fromRGB(150,154,164)
		accPart(pet,A,root, CYL_, 1.3,0.13,0.13, wood, s * CFrame.new(0,0.3,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, BLK_, 0.9,0.16,0.16, head, s * CFrame.new(0,0.85,0) * CFrame.Angles(0,0,math.rad(18)))
	end
end
-- clear ALL added parts + effects (accessories, emitters, lights, trail, orbs/ring/pulse/burst) so a re-apply
-- (equip / level-up) is clean (idempotent). The BASE PET parts are never touched.
local function clearEvo(pet, A)
	local g = pet:FindFirstChild("LevelGlow"); if g then g:Destroy() end
	local root = pet.PrimaryPart
	if root then for _, c in ipairs(root:GetChildren()) do
		local n = c.Name
		if n=="PetSparkle" or n=="PetTrail" or n=="PTrailA0" or n=="PTrailA1" or n=="PetAura" or n=="PetAuraLight" or n=="PetBurst" or n=="PetRareFX" or n=="PetRareLight" then c:Destroy() end
	end end
	for _, c in ipairs(pet:GetChildren()) do
		if c.Name=="EvoPart" or c.Name=="PetOrb" or c.Name=="PetRing" or c.Name=="PetPulse" then c:Destroy() end
	end
	if A then for i = #A.parts, 1, -1 do if A.parts[i].part and A.parts[i].part.Name == "EvoPart" then A.parts[i].part:Destroy(); table.remove(A.parts, i) end end end
	petFX[pet] = nil
end
-- build the animated EFFECT parts (orbs/ring/pulse/burst) for `level` into petFX[pet]; the FX loop animates them.
local function buildFX(pet, root, theme, level, gold)
	local col = gold and PRESTIGE_GOLD or theme.color
	local fx = { t=0, burstClock=0, orbs={}, ring={}, pulse=nil, burst=nil, shimmer=(level>=25),
		orbR=2.0, orbH=0.45, ringR=2.2, ringY=0.3, ringTilt=22 }
	local orbCount = (level>=11 and 1 or 0) + (level>=14 and 1 or 0) + (level>=19 and 1 or 0) -- ORBS: 1@11, 2@14, 3@19
	for _=1,orbCount do fx.orbs[#fx.orbs+1] = fxPart(pet, "PetOrb", BAL_, 0.42,0.42,0.42, col, true) end
	if level >= 15 then -- RING: a glowing energy ring of 8 beads, spinning on a tilted circle
		for i=0,7 do fx.ring[#fx.ring+1] = { part = fxPart(pet,"PetRing", BAL_, 0.28,0.28,0.28, col, true), base = math.rad(i*45) } end
	end
	if level >= 18 then -- PULSE: an expanding-fading ring burst
		fx.pulse = fxPart(pet, "PetPulse", CYL_, 0.3,1.2,1.2, col, true); fx.pulseBase = Vector3.new(0.3,1.2,1.2)
	end
	if level >= 24 then -- BURST: periodic ambient particle burst
		local b = Instance.new("ParticleEmitter"); b.Name="PetBurst"; b.Color=ColorSequence.new(col)
		b.Rate=0; b.Lifetime=NumberRange.new(0.4,0.8); b.Speed=NumberRange.new(4,9); b.Size=NumberSequence.new(0.5)
		b.LightEmission=0.8; b.Rotation=NumberRange.new(0,360); b.Parent=root; fx.burst=b
	end
	petFX[pet] = fx
end
-- RARE-only look (Stage 2): a body sheen (color/material/reflectance) + a rare sparkle aura (+ cloud puffs / soft
-- light / cosmic rainbow). Applied ON TOP of the pre-maxed visuals. Eyes + accessories + leveling FX are left as-is.
local function applyRareLook(pet, A, root, petId)
	local r = RARE_LOOK[petId]; if not r then return end
	for _, d in ipairs(pet:GetDescendants()) do          -- (1) body sheen (skip eyes / accessories / leveling FX)
		if d:IsA("BasePart") and d ~= root then
			local n = d.Name
			if n~="Eye" and n~="Highlight" and n~="EvoPart" and n~="PetOrb" and n~="PetRing" and n~="PetPulse" then
				d.Color = r.body; d.Material = r.mat; d.Reflectance = r.refl
			end
		end
	end
	local rfx = Instance.new("ParticleEmitter"); rfx.Name="PetRareFX"; rfx.Color=ColorSequence.new(r.fx); rfx.LightEmission=0.85
	rfx.Rate = r.cosmic and 65 or 32; rfx.Lifetime = NumberRange.new(0.6,1.2); rfx.Rotation = NumberRange.new(0,360)
	rfx.Speed = NumberRange.new(r.cosmic and 1.4 or 0.5, r.cosmic and 3.2 or 1.4); rfx.Size = NumberSequence.new(r.cosmic and 0.45 or 0.4)
	rfx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) }); rfx.Parent = root
	if r.light then local pl = Instance.new("PointLight"); pl.Name="PetRareLight"; pl.Color=r.fx; pl.Brightness=3; pl.Range=12; pl.Parent=root end
	if r.puffs and A then for k=0,3 do local ang=math.rad(k*90); accPart(pet,A,root, BAL_, 0.55,0.5,0.55, Color3.fromRGB(255,255,255), CFrame.new(math.sin(ang)*1.6, 0.7, math.cos(ang)*1.6)) end end
	if r.cosmic and petFX[pet] then petFX[pet].cosmic = true end -- the FX loop rainbow-cycles the rare light + stars
end
-- (Body-evolution REMOVED: the base pet's own parts are never modified. Upgrades = accessories + size + effects.)

-- `lite` (used by the menu/trade ICON clones): build ONLY size + accessories + rare body recolor; SKIP every
-- particle/highlight/trail/light/billboard FX (they don't render usefully in a static ViewportFrame icon and
-- were only being created then stripped). This keeps the per-icon build cheap so many maxed/rare icons can't
-- spike the frame / exhaust execution time.
local function applyLevelVisual(pet, level, petId, isRare, lite)
	if not pet then return end
	level = level or 1
	local root = pet.PrimaryPart
	local A = petAnims[pet]
	local theme = PET_THEME[petId] or PET_THEME[pet.Name]
	if not theme then return end -- only the 5 known pets have upgrade visuals
	if isRare then level = 25 end -- RARE pets display PRE-MAXED (full lvl-25 look) regardless of stored level
	local MAXL = 25
	local frac = math.clamp((level - 1) / (MAXL - 1), 0, 1) -- 0 at Lv1 -> 1 at Lv25
	local atMax = (level >= MAXL)
	local prevLevel = A and A.lastVisualLevel or nil
	accScale = 1
	clearEvo(pet, A) -- removes ONLY the added effects + EvoPart accessories; the BASE PET is never touched
	-- (1) SIZE: 60% at Lv1 -> 100% at Lv25 (+1.667%/level) -- the guaranteed visible change every level. (popMul = level-up bounce)
	if A then A.sizeMul = 0.6 + 0.4 * frac end
	local function ramp(startL) return math.clamp((level - startL) / (MAXL - startL), 0, 1) end
	-- (2) AURA: appears at Lv2; brightens each level. BOLD = a bright themed Highlight glow + a PointLight + soft particles.
	if level >= 2 and root and not lite then
		local t = ramp(2)
		local hl = Instance.new("Highlight"); hl.Name="LevelGlow"; hl.Adornee=pet
		pcall(function() hl.DepthMode = Enum.HighlightDepthMode.Occluded end)
		hl.FillColor = theme.color; hl.OutlineColor = theme.color
		hl.FillTransparency = math.clamp(0.8 - 0.45*t, 0, 1); hl.OutlineTransparency = math.clamp(0.4 - 0.4*t, 0, 1)
		hl.Parent = pet
		local pl = Instance.new("PointLight"); pl.Name="PetAuraLight"; pl.Color=theme.color; pl.Brightness=2.5+4*t; pl.Range=8+8*t; pl.Parent=root
		local ae = Instance.new("ParticleEmitter"); ae.Name="PetAura"; ae.Color=ColorSequence.new(theme.color); ae.LightEmission=0.7
		ae.Rate=8+34*t; ae.Lifetime=NumberRange.new(0.6,1.1); ae.Speed=NumberRange.new(0.2,0.8); ae.Size=NumberSequence.new(0.5+0.5*t)
		ae.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,0.3), NumberSequenceKeypoint.new(1,1) }); ae.Parent=root
	end
	-- (3) TRAIL: appears at Lv5; lengthens/brightens each level. BOLD = long, wide, bright themed trail.
	if level >= 5 and root and not lite then
		local t = ramp(5)
		local a0 = Instance.new("Attachment"); a0.Name="PTrailA0"; a0.Position=Vector3.new(0, 1.0, 0); a0.Parent=root
		local a1 = Instance.new("Attachment"); a1.Name="PTrailA1"; a1.Position=Vector3.new(0,-1.0, 0); a1.Parent=root
		local tr = Instance.new("Trail"); tr.Name="PetTrail"; tr.Attachment0=a0; tr.Attachment1=a1
		tr.Color = ColorSequence.new(theme.color); tr.LightEmission = 0.6; tr.Lifetime = 0.5 + 1.1*t
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, math.clamp(0.35 - 0.3*t, 0, 1)), NumberSequenceKeypoint.new(1, 1) })
		tr.Parent = root
	end
	-- (4) SPARKLES: appear at Lv8; density up each level. BOLD = dense themed sparkle particles.
	if level >= 8 and root and not lite then
		local t = ramp(8)
		local pe = Instance.new("ParticleEmitter"); pe.Name="PetSparkle"
		pe.Rate = 14 + 90*t; pe.LightEmission = 0.7; pe.Rotation = NumberRange.new(0,360)
		pe.Lifetime = NumberRange.new(0.5, 1.0); pe.Speed = NumberRange.new(0.6, 1.6); pe.Size = NumberSequence.new(0.34)
		pe.Color = ColorSequence.new(theme.color)
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) })
		pe.Parent = root
	end
	-- (5) ANIMATED EFFECTS: orbs (11/14/19), energy ring (15), pulse (18), burst (24) -- built into petFX, animated by the FX loop.
	if root and not lite then buildFX(pet, root, theme, level, atMax) end
	-- (6) ACCESSORIES: the per-pet list, each at its exact level (3/7/10/13/17/20/23), accumulating. GOLD trim at MAX.
	if A and root then
		for _, e in ipairs(theme.accs) do if level >= e[1] then buildAccessoryByKey(pet, A, root, theme, e[2], atMax) end end
	end
	-- (7) RARE: pre-maxed (above) + the unique rare body sheen/aura on top.
	if isRare and root then applyRareLook(pet, A, root, petId) end
	-- TIER BADGE (overhead): pet NAME + a colored TIER badge. Normal = Common->Legendary by level (+ "Lv N");
	-- rare variants = Exotic, or Mythical for the Cosmic Duck (no level). Colors escalate; Exotic/Mythical glow.
	if root and not lite then
		local bb = root:FindFirstChild("LevelTag")
		if not bb then
			bb = Instance.new("BillboardGui"); bb.Name="LevelTag"; bb.Size=UDim2.new(0,200,0,42)
			bb.StudsOffset=Vector3.new(0,3.7,0); bb.AlwaysOnTop=true; bb.Parent=root
			local lbl = Instance.new("TextLabel"); lbl.Name="L"; lbl.Size=UDim2.new(1,0,0,20); lbl.Position=UDim2.new(0,0,0,0); lbl.BackgroundTransparency=1
			lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=16; lbl.Parent=bb; Instance.new("UIStroke").Parent=lbl
			local tg = Instance.new("TextLabel"); tg.Name="Tag"; tg.AnchorPoint=Vector2.new(0.5,0); tg.Position=UDim2.new(0.5,0,0,22)
			tg.AutomaticSize=Enum.AutomaticSize.X; tg.Size=UDim2.new(0,0,0,16); tg.Font=Enum.Font.GothamBold; tg.TextSize=11; tg.TextColor3=Color3.new(1,1,1); tg.Parent=bb
			local pad=Instance.new("UIPadding", tg); pad.PaddingLeft=UDim.new(0,6); pad.PaddingRight=UDim.new(0,6)
			Instance.new("UICorner", tg).CornerRadius=UDim.new(0,5); Instance.new("UIStroke", tg)
		end
		local tierName, tierColor, isVariant, flashy = petTier(level, isRare, petId)
		bb.L.Text = petDisplayName(petId, isRare)
		bb.L.TextColor3 = isVariant and tierColor or Color3.new(1,1,1)
		bb.Tag.Text = isVariant and tierName or (tierName .. "  Lv " .. tostring(level))
		bb.Tag.BackgroundColor3 = tierColor
		local stk = bb.Tag:FindFirstChildOfClass("UIStroke")
		if stk then
			if flashy then -- Exotic/Mythical: thin CLEAN border on the badge EDGE (not a thick text halo) -> readable
				stk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; stk.Color = Color3.fromRGB(255,255,255); stk.Thickness = 1; stk.Transparency = 0.2
			else -- normal tiers: unchanged (thin dark text outline)
				stk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; stk.Color = Color3.fromRGB(0,0,0); stk.Thickness = 1; stk.Transparency = 0.35
			end
		end
	end
	-- (7) LEVEL-UP POP: every live level-up -> a tiny scale-pop + a one-shot sparkle burst (feedback).
	local leveledUp = prevLevel and level > prevLevel
	if leveledUp then
		if A then A.popClock = 0.4 end
		if root then
			local burst = Instance.new("ParticleEmitter"); burst.Color=ColorSequence.new(theme.color); burst.LightEmission=0.85
			burst.Lifetime=NumberRange.new(0.35,0.7); burst.Speed=NumberRange.new(3,7); burst.Rotation=NumberRange.new(0,360)
			burst.Size=NumberSequence.new(0.45); burst.Rate=0; burst.Parent=root
			burst:Emit(20)
			game:GetService("Debris"):AddItem(burst, 1.1)
		end
	end
	if A then A.lastVisualLevel = level end
	if lite then return end -- icon clones: size + accessories + rare recolor only; skip the level-up pop + diagnostics
	-- DIAGNOSTICS
	local nAcc = 0; for _, e in ipairs(theme.accs) do if level >= e[1] then nAcc = nAcc + 1 end end
	local nOrb = (level>=11 and 1 or 0)+(level>=14 and 1 or 0)+(level>=19 and 1 or 0)
	print(string.format("[PetEvo] %s Lvl %d: size %d%%, aura %s, trail %s, sparkles %s, orbs %d, ring %s, pulse %s, burst %s, accessories %d, shimmer %s",
		pet.Name, level, math.floor((0.6 + 0.4*frac)*100),
		(level>=2) and "on" or "off", (level>=5) and "on" or "off", (level>=8) and "on" or "off",
		nOrb, (level>=15) and "on" or "off", (level>=18) and "on" or "off", (level>=24) and "on" or "off", nAcc, atMax and "on" or "off"))
	if leveledUp then
		local added = "size"
		if level==2 then added="aura" elseif level==5 then added="trail" elseif level==8 then added="sparkles"
		elseif level==11 or level==14 or level==19 then added="floating orb" elseif level==15 then added="energy ring"
		elseif level==18 then added="pulse" elseif level==24 then added="burst" elseif atMax then added="MAX: gold trim + shimmer" end
		for _, e in ipairs(theme.accs) do if e[1] == level then added = "accessory ("..tostring(e[2])..")" end end
		print(string.format("[PetEvo] %s level-up %d -> added %s", pet.Name, level, added))
	end
end
-- FX LOOP: animate each active pet's orbs (orbit), energy ring (spin), pulse (expand+fade), burst (periodic emit),
-- and the MAX shimmer (cycle aura/trail/orb/ring colors). One Heartbeat connection for all pets.
do
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		for pet, fx in pairs(petFX) do
			local root = pet.Parent and pet.PrimaryPart
			if root then
				fx.t = fx.t + dt
				local t = fx.t
				local rootCF = root.CFrame
				local sm = (petAnims[pet] and petAnims[pet].sizeMul) or 1
				local n = #fx.orbs
				for i, orb in ipairs(fx.orbs) do
					local a = t*1.7 + (i-1)*(2*math.pi/math.max(1,n))
					orb.CFrame = rootCF * CFrame.new(math.cos(a)*fx.orbR*sm, fx.orbH*sm, math.sin(a)*fx.orbR*sm)
				end
				for _, seg in ipairs(fx.ring) do
					local a = t*1.9 + seg.base
					seg.part.CFrame = rootCF * CFrame.new(0, fx.ringY*sm, 0) * CFrame.Angles(math.rad(fx.ringTilt),0,0) * CFrame.new(math.cos(a)*fx.ringR*sm, 0, math.sin(a)*fx.ringR*sm)
				end
				if fx.pulse then
					local ph = (t % 1.3) / 1.3
					fx.pulse.Size = fx.pulseBase * (1 + ph*2.2) * sm
					fx.pulse.Transparency = math.clamp(ph, 0, 1)
					fx.pulse.CFrame = rootCF * CFrame.new(0, 0.2*sm, 0) * CFrame.Angles(0,0,math.rad(90))
				end
				if fx.burst then
					fx.burstClock = fx.burstClock - dt
					if fx.burstClock <= 0 then fx.burstClock = 1.3; fx.burst:Emit(18) end
				end
				if fx.cosmic then -- COSMIC DUCK rare: vivid rainbow cycle on the rare light + star sparkles
					local cc = Color3.fromHSV((t * 0.4) % 1, 0.7, 1)
					local rl = root:FindFirstChild("PetRareLight"); if rl then rl.Color = cc end
					local rfx = root:FindFirstChild("PetRareFX"); if rfx then rfx.Color = ColorSequence.new(cc) end
				end
				if fx.shimmer then
					-- SUBTLE rainbow sheen: cycle a gentle hue (lower saturation/value) and keep the Highlight FILL
					-- nearly transparent so it reads as a soft sheen ON the pet, NOT a bright wash that hides it.
					local hue = (t * 0.25) % 1
					local c = Color3.fromHSV(hue, 0.45, 0.9)
					local hl = pet:FindFirstChild("LevelGlow")
					if hl then
						hl.OutlineColor = c; hl.OutlineTransparency = 0.25 -- a thin rainbow edge sheen (doesn't cover the body)
						hl.FillColor = c; hl.FillTransparency = 0.88       -- very light fill so the pet's features stay clearly visible
					end
					local tr = root:FindFirstChild("PetTrail"); if tr then tr.Color = ColorSequence.new(Color3.fromHSV((hue+0.5)%1, 0.6, 1)) end
					for _, orb in ipairs(fx.orbs) do orb.Color = c end
					for _, seg in ipairs(fx.ring) do seg.part.Color = c end
				end
			else
				petFX[pet] = nil
			end
		end
	end)
end

-- Every pet now clones its SERVER-FUSED union template (smooth gap-free body). The client part-cluster
-- builders are kept only as FALLBACKS if a template hasn't replicated (so a pet always appears).
local PET_TEMPLATE_NAME = {
	BroccoliPet      = "BroccoliBunnyTemplate",
	CoconutCrab      = "CoconutCrabTemplate",
	PopcornSheep     = "PopcornSheepTemplate",
	ButterDuck       = "ButterDuckTemplate",
	BurritoArmadillo = "BurritoArmadilloTemplate",
	SunflowerBee     = "SunflowerBeeTemplate",   -- seasonal (Summer)
	MapleFox         = "MapleFoxTemplate",        -- seasonal (Autumn)
	FrostPenguin     = "FrostPenguinTemplate",    -- seasonal (Winter)
	BlossomBunny     = "BlossomBunnyTemplate",    -- seasonal (Spring)
}
local PET_FALLBACK = {
	CoconutCrab      = buildCoconutCrab,
	PopcornSheep     = buildPopcornSheep,
	ButterDuck       = buildButterDuck,
	BurritoArmadillo = buildBurritoArmadillo,
	BroccoliPet      = buildBroccoliDinoFallback,
}
local function buildPetModel(petId)
	local tn = PET_TEMPLATE_NAME[petId]
	local template = tn and (RS:FindFirstChild(tn) or RS:WaitForChild(tn, 4)) -- instant if replicated; brief wait covers join lag
	if template then
		local clone = template:Clone(); clone.Name = petId
		if registerClonedTemplate(clone) then
			print("[Pet][UNION] cloned server template "..tn.." for "..petId.." (smooth fused body)")
			return clone
		end
		clone:Destroy()
	end
	warn("[Pet][UNION] "..petId.." template missing -- using client-built fallback")
	local fb = PET_FALLBACK[petId]
	local fallback = (fb and fb(0.9)) or buildBroccoliDinoFallback(0.9)
	-- match the server pets: force every fallback PET part to clean matte plastic + Smooth faces (no Lego-stud/
	-- notch texture). Pet-only -- this never touches quest props (they use their own newPart elsewhere).
	if fallback then
		local SM = Enum.SurfaceType.Smooth
		for _, d in ipairs(fallback:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Transparency < 1 then d.Material = Enum.Material.Plastic end -- keep invisible roots untouched
				d.TopSurface = SM; d.BottomSurface = SM; d.LeftSurface = SM
				d.RightSurface = SM; d.FrontSurface = SM; d.BackSurface = SM
			end
		end
	end
	return fallback
end
local function spawnFollowerPet(petId)
	local st = petState[petId]
	if st.pet then -- already following: just refresh the visual if the level OR the rare flag changed
		if st.appliedLevel ~= st.level or st.appliedRare ~= st.rare then
			st.appliedLevel = st.level; st.appliedRare = st.rare; applyLevelVisual(st.pet, st.level or 1, petId, st.rare)
		end
		return
	end
	if PETS[petId] and PETS[petId].questType == "seasonal" then
		print("[PetFollow] building seasonal "..(PETS[petId].displayName or petId).." follower")
	end
	st.pet = buildPetModel(petId)
	st.pet.Name = petId
	st.pet.Parent = Workspace
	st.appliedLevel = st.level; st.appliedRare = st.rare
	applyLevelVisual(st.pet, st.level or 1, petId, st.rare)
	print("[Pet][DIAG] pet spawned, following player ("..petId..") at Lv "..tostring(st.level or 1))
end

-- Despawn the follower (used when a pet is UNEQUIPPED). Cosmetic-only.
local function despawnFollowerPet(petId)
	local st = petState[petId]
	if st and st.pet then
		petFX[st.pet] = nil -- stop the FX loop tracking this pet before it's destroyed
		petAnims[st.pet] = nil
		pcall(function() st.pet:Destroy() end)
		st.pet = nil; st.appliedLevel = nil
		print("[Pet][DIAG] pet despawned (unequipped) ("..petId..")")
	end
end

-- ===== PET ANIMATION (idle + movement). Drives the sub-parts as LOCAL offsets around the root, so the
-- root keeps following the player (this NEVER moves the root -- it only re-poses children each frame).
-- Role-based: the head bobs/nods, the tail wiggles, the legs do a gait swing, the eyes blink, and the
-- whole pet does a gentle idle float + a Crossy-Road hop when moving. Modular: any pet whose builder
-- registers parts with body/head/tail/leg roles + an eye flag animates for free.
local function pivotRotate(pivot, rot) -- rotate about a local pivot point (not the part's own centre)
	return CFrame.new(pivot) * rot * CFrame.new(-pivot)
end
local function animatePet(model, dt)
	local A = petAnims[model]; if not A then return end
	local root = model.PrimaryPart; if not (root and root.Parent) then return end
	local rootCF = root.CFrame
	local s = A.s
	A.t = A.t + dt
	local t = A.t
	-- LEVEL-UP POP: a quick cosmetic scale-bounce (1 -> ~1.25 -> 1 over ~0.4s) whenever applyLevelVisual sets
	-- A.popClock on a level-up, so EVERY level-up is instantly, visibly rewarding. Purely visual.
	A.popMul = 1
	if A.popClock and A.popClock > 0 then
		A.popClock = math.max(0, A.popClock - dt)
		A.popMul = 1 + 0.25 * math.sin(math.pi * (1 - A.popClock / 0.4))
	end
	-- MOVING? measure the root's HORIZONTAL speed (ignore the ambient vertical bob) and smooth it to 0..1.
	local pos = rootCF.Position
	if A.lastPos then
		local d = pos - A.lastPos
		local sp = Vector3.new(d.X, 0, d.Z).Magnitude / math.max(dt, 1e-3)
		local target = math.clamp(sp / (26 * s), 0, 1)
		A.move = A.move + (target - A.move) * math.clamp(dt * 5, 0, 1)
	end
	A.lastPos = pos
	local mv = A.move
	-- GLOBAL (local frame: +X = front): SOFT slow breathing bob (idle) + a gentle slow bob when moving + a
	-- forward lean. Lean = pitch the front (+X) down -> rotate about the lateral Z axis, pivoted at the centre.
	-- (Soft sine, low frequency/amplitude -- no fast abs-sine jackhammer, so the motion is flowy, not jittery.)
	local bobY = math.sin(t * 1.5) * 0.06 * s + math.sin(t * (3.0 + 1.5 * mv)) * 0.09 * s * mv
	-- a gentle whole-body sway (yaw + roll) keeps the pet alive as ONE unit -- important once the body is a
	-- single fused union (which can no longer sway its neck/tail independently). Applied to every part.
	local swayY = math.rad(3) * math.sin(t * 0.8)
	local swayZ = math.rad(2) * math.sin(t * 1.1)
	local globalT = CFrame.new(0, bobY, 0) * pivotRotate(Vector3.new(0, 0, 0), CFrame.Angles(0, swayY, -math.rad(13) * mv + swayZ))
	-- HEAD: a little Y bob + idle nod (pitch about Z) + side glance (yaw about Y), small dip when moving,
	-- pivoted at the neck (between body centre and the head at +X).
	local headBob = math.sin(t * 1.7 + 0.5) * 0.05 * s + math.sin(t * (8 + 4 * mv)) * 0.05 * s * mv
	local headRot = CFrame.Angles(0, math.rad(8) * math.sin(t * 0.6), 0) * CFrame.Angles(0, 0, math.rad(5) * math.sin(t * 1.1) - math.rad(7) * mv)
	local headT = CFrame.new(0, headBob, 0) * pivotRotate(Vector3.new(1.2 * s, 0.6 * s, 0), headRot) -- pivot at the NECK BASE so the long neck sways
	-- TAIL: side-to-side sway (yaw about Y), pivoted where it meets the body back (-X).
	local tailRot = pivotRotate(Vector3.new(-1.5 * s, 0, 0), CFrame.Angles(0, math.sin(t * (2.2 + 3 * mv)) * (math.rad(14) + math.rad(16) * mv), 0))
	-- BLINK: quick eye squash every ~2-5s (random) so it feels natural.
	A.blink = A.blink - dt
	local eyeY = 1
	if A.blink <= 0 then
		local since = -A.blink
		if since < 0.16 then
			eyeY = 1 - 0.85 * (1 - math.abs((since / 0.16) * 2 - 1)) -- close then open
		else
			A.blink = 1.8 + math.random() * 3.4 -- schedule the next blink
		end
	end
	-- Apply per part: each block keeps its clean local placement (bp = base) + a role transform
	-- (head bob / tail wiggle / leg gait) + the global hop/lean. Blocks stay snapped (no scale = no gaps).
	for _, e in ipairs(A.parts) do
		local bp = e.base
		local localCF
		if e.role == "head" then
			localCF = globalT * headT * bp
		elseif e.role == "tail" then
			localCF = globalT * tailRot * bp
		elseif e.role == "leg" then
			-- diagonal gait: front-left + back-right swing together, opposite pair anti-phase. Legs swing
			-- fore/aft (in X) -> rotate about the lateral Z axis, pivoted at the hip (body underside).
			local bx, bz = e.base.Position.X, e.base.Position.Z
			local phase = ((bx >= 0) == (bz >= 0)) and 0 or math.pi
			local swing = math.rad(18) * mv * math.sin(t * (9 + 3 * mv) + phase)
			localCF = globalT * pivotRotate(Vector3.new(bx, -0.7 * s, bz), CFrame.Angles(0, 0, swing)) * bp
		elseif e.role == "ear" then
			-- EARS (bunny/sheep): gentle floppy wiggle -- rock fore/aft (about Z) + a touch of side splay
			-- (about X), pivoted at the EAR BASE (down at the head top) so the tip swings, not the whole ear.
			local bzs = e.base.Position.Z >= 0 and 1 or -1
			local flop = math.rad(7) * math.sin(t * 1.6) + math.rad(9) * mv * math.sin(t * (7 + 2 * mv))
			local splay = math.rad(5) * math.sin(t * 1.3 + bzs) * bzs
			local pv = Vector3.new(e.base.Position.X, e.base.Position.Y - 1.0 * s, e.base.Position.Z)
			localCF = globalT * pivotRotate(pv, CFrame.Angles(0, 0, flop) * CFrame.Angles(splay, 0, 0)) * bp
		elseif e.role == "wing" then
			-- WINGS (duck): flap up/down -- rotate about the fore/aft X axis, pivoted at the INNER edge
			-- (where the wing meets the body, toward Z=0) so the outer tip lifts. Idle = slow settle.
			local sgn = e.base.Position.Z >= 0 and 1 or -1
			local flap = (math.rad(10) + math.rad(26) * mv) * math.sin(t * (3 + 9 * mv)) * sgn
			local pv = Vector3.new(e.base.Position.X, e.base.Position.Y, e.base.Position.Z - 1.0 * s * sgn)
			localCF = globalT * pivotRotate(pv, CFrame.Angles(flap, 0, 0)) * bp
		elseif e.role == "claw" then
			-- CLAWS/legs (crab): scuttle -- a quick small open/close yaw (about Y) + tiny tilt, pivoted at the
			-- shoulder (toward the body, lower X). Left/right anti-phase so it looks like a busy little crab.
			local sgn = e.base.Position.Z >= 0 and 1 or -1
			local sc = (math.rad(6) + math.rad(10) * mv) * math.sin(t * (5 + 6 * mv) + (sgn > 0 and 0 or math.pi))
			local pv = Vector3.new(e.base.Position.X - 0.8 * s, e.base.Position.Y, e.base.Position.Z)
			localCF = globalT * pivotRotate(pv, CFrame.Angles(0, sc * sgn, sc * 0.5)) * bp
		else
			localCF = globalT * bp
		end
		-- COSMETIC SIZE TIER (lvl >=30): scale every part's offset-from-root + its size uniformly, so the whole
		-- pet grows about its root. sm==1 (levels <30) keeps the EXACT original behavior (only eyes set Size).
		local sm = (A.sizeMul or 1) * (A.popMul or 1)
		if sm ~= 1 then
			local pos = localCF.Position
			localCF = CFrame.new(pos * sm) * (localCF - pos) -- scale translation, keep rotation
		end
		e.part.CFrame = rootCF * localCF
		if e.eye then -- blink squash: shrink the eye block vertically (Part.Size.Y)
			e.part.Size = Vector3.new(e.baseSize.X * sm, e.baseSize.Y * eyeY * sm, e.baseSize.Z * sm)
		elseif sm ~= 1 then
			e.part.Size = e.baseSize * sm
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	-- follow for any owned/spawned pet (currently one; the loop supports more)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	for _, st in pairs(petState) do
		local pet = st.pet
		if pet and pet.Parent and pet.PrimaryPart and not st.emerging then -- 'emerging' = the hatch pop controls the pet
			if not hrp then
				-- no character (respawning) -> just leave the pet where it is
			else
				local targetCF = hrp.CFrame * CFrame.new(FOLLOW_OFFSET.X, FOLLOW_OFFSET.Y, FOLLOW_OFFSET.Z)
				local targetPos = targetCF.Position
				if not petSmoothPos then petSmoothPos = targetPos end
				-- SOFT eased position smoothing (frame-rate-independent) -> the pet glides, no micro-bounce
				local alpha = 1 - math.exp(-FOLLOW_K * dt)
				petSmoothPos = petSmoothPos:Lerp(targetPos, alpha)
				-- clamp the trail so a very fast fart-ascent never strands the pet
				local back = petSmoothPos - targetPos
				if back.Magnitude > MAX_TRAIL then petSmoothPos = targetPos + back.Unit * MAX_TRAIL end
				-- ONE gentle slow bob (the breath/lean lives in animatePet) -- soft + low frequency, no jitter
				bobT = bobT + dt
				local renderPos = petSmoothPos + Vector3.new(0, math.sin(bobT * 1.4) * 0.10, 0)
				-- FACING: ease the look direction toward the player's heading on a SLOWER spring than position,
				-- so the pet smoothly SWINGS around to turn (trailing gracefully) instead of snapping in lock-step.
				local fwd = hrp.CFrame.LookVector
				fwd = Vector3.new(fwd.X, 0, fwd.Z)
				if fwd.Magnitude < 0.05 then fwd = (petSmoothFwd or Vector3.new(0, 0, -1)) end
				fwd = fwd.Unit
				if not petSmoothFwd then petSmoothFwd = fwd end
				local fAlpha = 1 - math.exp(-FACE_K * dt)
				petSmoothFwd = petSmoothFwd:Lerp(fwd, fAlpha)
				if petSmoothFwd.Magnitude < 0.05 then petSmoothFwd = fwd end
				local face = petSmoothFwd.Unit
				-- the model is built with +X = front, so yaw the look-at +90 deg to point its +X along travel
				pet:PivotTo(CFrame.lookAt(renderPos, renderPos + face) * CFrame.Angles(0, math.rad(90), 0))
			end
			-- animate the sub-parts AFTER positioning the root (local offsets on top of the follow)
			animatePet(pet, dt)
		end
	end
end)

-- ============================================================================================
-- PET QUEST UI -- mysterious landing hint -> discovery popup -> corner tracker -> 3/3 pointer + glowing
-- egg. Reflects the EXISTING per-player progress (found count + owns from PetStateEvent) and is fully
-- DATA-DRIVEN from each pet's catalog entry (pieceLabel / iconEmoji / questHint) so future pet islands
-- reuse it with zero broccoli-specific hardcoding. COSMETIC ONLY -- no gameplay effects.
-- ============================================================================================
local TweenService = game:GetService("TweenService")
local Camera = Workspace.CurrentCamera
local questGui = Instance.new("ScreenGui")
questGui.Name = "PetQuestUI"; questGui.ResetOnSpawn = false; questGui.DisplayOrder = 30
questGui.Parent = player:WaitForChild("PlayerGui")

local function uiStroke(o, th, col) local s=Instance.new("UIStroke"); s.Color=col or Color3.fromRGB(0,0,0); s.Thickness=th or 2; s.Parent=o; return s end
local function uiCorner(o, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0, r or 12); c.Parent=o; return c end

-- (1) HINT: subtle, top-center, fades in then out
local hint = Instance.new("TextLabel")
hint.Name="Hint"; hint.AnchorPoint=Vector2.new(0.5,0); hint.Position=UDim2.new(0.5,0,0.07,0); hint.Size=UDim2.new(0,500,0,34)
hint.BackgroundTransparency=1; hint.Font=Enum.Font.FredokaOne; hint.TextSize=22; hint.TextColor3=Color3.fromRGB(225,232,255); hint.TextTransparency=1; hint.Text=""; hint.Parent=questGui
local hintStroke = uiStroke(hint, 2); hintStroke.Transparency=1

-- (2a) DISCOVERY POPUP: center reveal that animates toward the corner tracker
local popup = Instance.new("Frame")
popup.Name="Popup"; popup.AnchorPoint=Vector2.new(0.5,0.5); popup.Position=UDim2.new(0.5,0,0.4,0); popup.Size=UDim2.new(0,300,0,110)
popup.BackgroundColor3=Color3.fromRGB(38,72,38); popup.BackgroundTransparency=0.05; popup.Visible=false; popup.Parent=questGui
uiCorner(popup, 16); uiStroke(popup, 3, Color3.fromRGB(120,220,120))
local popTitle = Instance.new("TextLabel"); popTitle.BackgroundTransparency=1; popTitle.Font=Enum.Font.FredokaOne; popTitle.TextSize=26; popTitle.TextColor3=Color3.fromRGB(180,255,180); popTitle.Size=UDim2.new(1,-12,0,40); popTitle.Position=UDim2.new(0,6,0,8); popTitle.Text="Pet Search Active!"; popTitle.Parent=popup; uiStroke(popTitle,2)
local popSub = Instance.new("TextLabel"); popSub.BackgroundTransparency=1; popSub.Font=Enum.Font.FredokaOne; popSub.TextSize=22; popSub.TextColor3=Color3.fromRGB(255,255,255); popSub.Size=UDim2.new(1,-12,0,36); popSub.Position=UDim2.new(0,6,0,54); popSub.Text=""; popSub.Parent=popup; uiStroke(popSub,2)

-- (2b) CORNER TRACKER: top-right, persistent. Two modes -- "available" shows quest NAME + objective on two
-- lines; "progress"/"complete" minimize to a single compact counter line. refreshQuestHUD() drives both.
local tracker = Instance.new("Frame")
tracker.Name="Tracker"; tracker.AnchorPoint=Vector2.new(0.5,0); tracker.Position=UDim2.new(0.5,0,0,14); tracker.Size=UDim2.new(0,240,0,52) -- TOP-CENTER (anchor 0.5,0 keeps it centered as Size changes per mode)
tracker.BackgroundColor3=Color3.fromRGB(28,52,28); tracker.BackgroundTransparency=0.12; tracker.Visible=false; tracker.Parent=questGui
uiCorner(tracker, 10); uiStroke(tracker, 2, Color3.fromRGB(120,220,120))
local trkIcon = Instance.new("TextLabel"); trkIcon.BackgroundTransparency=1; trkIcon.Font=Enum.Font.Gotham; trkIcon.TextSize=24; trkIcon.Size=UDim2.new(0,30,1,0); trkIcon.Position=UDim2.new(0,8,0,0); trkIcon.Text=""; trkIcon.Parent=tracker
local trkLabel = Instance.new("TextLabel"); trkLabel.BackgroundTransparency=1; trkLabel.Font=Enum.Font.FredokaOne; trkLabel.TextSize=16; trkLabel.TextColor3=Color3.fromRGB(255,255,255); trkLabel.Size=UDim2.new(1,-50,1,0); trkLabel.Position=UDim2.new(0,42,0,0); trkLabel.TextXAlignment=Enum.TextXAlignment.Center; trkLabel.Text=""; trkLabel.Parent=tracker; uiStroke(trkLabel,2) -- centered in the box
local trkSub = Instance.new("TextLabel"); trkSub.BackgroundTransparency=1; trkSub.Font=Enum.Font.Gotham; trkSub.TextSize=13; trkSub.TextColor3=Color3.fromRGB(210,235,210); trkSub.Size=UDim2.new(1,-50,0,18); trkSub.Position=UDim2.new(0,42,0,28); trkSub.TextXAlignment=Enum.TextXAlignment.Left; trkSub.Text=""; trkSub.Visible=false; trkSub.Parent=tracker; uiStroke(trkSub,1)

-- (3) POINTER: on-screen arrow guiding to the egg (shown at 3/3)
local pointer = Instance.new("TextLabel")
pointer.Name="Pointer"; pointer.AnchorPoint=Vector2.new(0.5,0.5); pointer.Size=UDim2.new(0,60,0,60)
pointer.BackgroundTransparency=1; pointer.Font=Enum.Font.GothamBold; pointer.TextSize=46; pointer.TextColor3=Color3.fromRGB(150,255,140); pointer.Text="\xE2\x9E\xA4"; pointer.Visible=false; pointer.Parent=questGui; uiStroke(pointer,2)

local activeUiPet = nil -- petId currently driving the tracker/pointer
local onIsland = {}     -- [petId] = bool (for the once-per-visit landing hint)

local function flashHint(def)
	-- SHORT on-landing reveal showing the quest's real NAME + objective (the corner tracker then persists it)
	hint.Text = (def.iconEmoji or "\xF0\x9F\x90\xBe").."  "..(def.objective or "Pet Quest") -- objective only, no "???" (note: flashHint is no longer called)
	hint.TextTransparency = 1; hintStroke.Transparency = 1
	TweenService:Create(hint, TweenInfo.new(0.6), {TextTransparency=0}):Play()
	TweenService:Create(hintStroke, TweenInfo.new(0.6), {Transparency=0}):Play()
	task.delay(3.0, function()
		TweenService:Create(hint, TweenInfo.new(1.0), {TextTransparency=1}):Play()
		TweenService:Create(hintStroke, TweenInfo.new(1.0), {Transparency=1}):Play()
	end)
	print("[Pet][UI] on-landing pet-quest hint shown (points to inventory)")
end

-- progress for ONE quest: found, total (nil = count-less), started, complete. Piece quests read the server
-- found/total; the count-less ones (fishing/dig) read the client-tracked localQuestProg.
local function questProgress(petId, def, st)
	local qt = def.questType
	if qt == "dig" or qt == "fishing" then
		local lp = localQuestProg[petId] or {}
		local total = lp.total
		local complete = (lp.complete == true) or (total ~= nil and total >= 1 and (lp.found or 0) >= total)
		return lp.found or 0, total, lp.started == true, complete
	end
	local found = (st and st.uiFound) or 0
	local total = (st and st.total) or #def.pieceMarkers
	-- piece quests: started once the first piece is found; COMPLETE at full count -> the tracker swaps to the
	-- next-step text (def.nextStep). owns=true (hatched) hides the tracker; the on-screen pointer guides to the egg.
	return found, total, found >= 1, (total >= 1 and found >= total)
end

-- THE on-screen quest indicator. Picks the quest to show (a started/finished one wins over a merely
-- available one), then renders it: AVAILABLE -> name + objective (two lines); STARTED -> compact live
-- counter; full -> "Complete!"; hatched -> hidden. Assigned to the forward-declared upvalue. Cosmetic-only.
refreshQuestHUD = function()
	local showId, mode
	-- 1) a STARTED-but-unfinished quest wins (progress); a finished-but-unhatched one shows "Complete!"
	--    ISLAND-BOUND: `and onIsland[petId]` so the on-screen tracker only shows while the player is ON that
	--    quest's island (hides elsewhere, reappears on return). The pet GUI quest TAB is unaffected.
	for petId, def in pairs(PETS) do
		local st = petState[petId]
		if st and not st.owns and onIsland[petId] then
			local _, _, started, complete = questProgress(petId, def, st)
			if complete then showId, mode = petId, "complete"; break
			elseif started then showId, mode = petId, "progress"; break end
		end
	end
	-- 2) else an AVAILABLE quest on whatever island the player is standing on
	if not showId then
		for petId, def in pairs(PETS) do
			local st = petState[petId]
			if st and not st.owns and onIsland[petId] then showId, mode = petId, "available"; break end
		end
	end
	if not showId then tracker.Visible = false; activeUiPet = nil; return end
	activeUiPet = showId
	local def = PETS[showId]; local st = petState[showId]
	trkIcon.Text = def.iconEmoji or "\xF0\x9F\x90\xBE"
	if mode == "available" then
		-- AVAILABLE: show the OBJECTIVE cleanly (no "???"). TextWrapped so a longer objective fits two lines.
		tracker.Size = UDim2.new(0,224,0,52)
		trkLabel.TextWrapped = true
		trkLabel.Position = UDim2.new(0,36,0,4); trkLabel.Size = UDim2.new(1,-44,0,44) -- centered (icon left ~36, equal-ish right margin)
		trkLabel.Text = def.objective or ""; trkLabel.TextColor3 = Color3.fromRGB(255,240,150)
		trkSub.Visible = false
	else
		tracker.Size = UDim2.new(0,200,0,38)
		trkLabel.TextWrapped = false
		trkLabel.Position = UDim2.new(0,36,0,0); trkLabel.Size = UDim2.new(1,-44,1,0) -- centered (icon left ~36, equal-ish right margin)
		trkSub.Visible = false
		if mode == "complete" then
			-- count finished -> show the NEXT step for this quest (def.nextStep), not the finished count
			trkLabel.Text = def.nextStep or "Complete!"; trkLabel.TextColor3 = Color3.fromRGB(160,255,160)
		else
			local found, total = questProgress(showId, def, st)
			local word = def.trackWord or def.pieceLabel or "Progress"
			trkLabel.Text = (total ~= nil) and (word.." "..found.."/"..total) or (word..": "..found)
			trkLabel.TextColor3 = Color3.fromRGB(255,255,255)
		end
	end
	tracker.Visible = true
end

local function showDiscoveryPopup(def, found, total)
	popSub.Text = found.."/"..total.." "..(def.pieceLabel or "Pieces").." Found"
	popTitle.TextTransparency=0; popSub.TextTransparency=0; popup.BackgroundTransparency=0.05
	popup.Position = UDim2.new(0.5,0,0.4,0); popup.Size = UDim2.new(0,240,0,88); popup.Visible = true
	TweenService:Create(popup, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size=UDim2.new(0,300,0,110)}):Play()
	print("[Pet][UI] discovery popup shown ("..found.."/"..total..")")
	task.delay(2.0, function()
		local ti = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(popup, ti, {Position=tracker.Position, Size=UDim2.new(0,180,0,40), BackgroundTransparency=1}):Play()
		TweenService:Create(popTitle, ti, {TextTransparency=1}):Play()
		TweenService:Create(popSub, ti, {TextTransparency=1}):Play()
		task.delay(0.6, function() popup.Visible=false end)
	end)
end

local function setEggGlow(petId, on)
	local st = petState[petId]; if not st then return end
	if on and not st.eggGlow and st.egg then
		local hl = Instance.new("Highlight"); hl.FillColor=Color3.fromRGB(120,255,120); hl.FillTransparency=0.45
		hl.OutlineColor=Color3.fromRGB(230,255,180); hl.OutlineTransparency=0; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = st.eggVisual or st.egg; hl.Parent = st.egg; st.eggGlow = hl
		local shell = st.egg:FindFirstChild("Shell", true)
		if shell then
			local pl=Instance.new("PointLight"); pl.Name="EggGlowLight"; pl.Color=Color3.fromRGB(150,255,150); pl.Brightness=4; pl.Range=26; pl.Parent=shell
			local em=Instance.new("ParticleEmitter"); em.Name="EggGlowSparkle"; em.Texture="rbxasset://textures/particles/sparkles_main.dds"; em.Color=ColorSequence.new(Color3.fromRGB(210,255,180)); em.Rate=16; em.Lifetime=NumberRange.new(0.6,1.1); em.Speed=NumberRange.new(2,6); em.Size=NumberSequence.new(0.9); em.LightEmission=0.85; em.Parent=shell
		end
	elseif not on and st.eggGlow then
		st.eggGlow:Destroy(); st.eggGlow=nil
		local shell = st.egg and st.egg:FindFirstChild("Shell", true)
		if shell then for _,n in ipairs({"EggGlowLight","EggGlowSparkle"}) do local o=shell:FindFirstChild(n); if o then o:Destroy() end end end
	end
end

local function hideQuestUI(petId)
	tracker.Visible = false; pointer.Visible = false
	setEggGlow(petId, false)
	if activeUiPet == petId then activeUiPet = nil end
end

-- ===== HATCH: press E -> shake -> crack -> pet pops out -> follows, THEN the claim registers =====
-- Purely visual; the resulting pet is the same broccoli pet and ownership/persistence still saves via
-- the existing PetClaimEvent (fired AFTER the animation). Assigns the forward-declared `hatchEgg`.
hatchEgg = function(petId, def)
	local st = petState[petId]
	if not st or st.hatching or st.owns then return end
	st.hatching = true -- pauses the egg bob + (below) blocks applyState from re-touching the egg/glow
	print("[Pet][HATCH] hatch started for "..player.Name)
	-- HATCH SOUND #1: play the PRELOADED egg-CRACK sound the INSTANT the hatch begins (no load delay now, so it
	-- fires right at the true hatch start + leads in through the shake). The unlock follows at the crack beat below.
	pcall(function() hatchCrackSound.TimePosition = 0; hatchCrackSound:Play() end)
	local prompt = st.egg and st.egg:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then prompt.Enabled = false end -- can't re-trigger mid-hatch
	setEggGlow(petId, false)
	local visual = st.eggVisual
	local base = st.eggBaseCF or CFrame.new((st.eggPos or Vector3.zero) + Vector3.new(0, 2.6, 0))

	-- 1) SHAKE ~2.0s, intensity ramps up
	local SHAKE, t0 = 2.0, os.clock()
	while os.clock() - t0 < SHAKE do
		local p = (os.clock() - t0) / SHAKE
		local amp = 0.1 + p * p * 0.9
		if visual and visual.PrimaryPart then
			pcall(function()
				visual:PivotTo(base
					* CFrame.new((math.random()-0.5)*amp*1.4, math.abs(math.sin((os.clock()-t0)*22))*amp*0.5, (math.random()-0.5)*amp*1.4)
					* CFrame.Angles(math.rad((math.random()-0.5)*amp*55), math.rad((math.random()-0.5)*amp*80), math.rad((math.random()-0.5)*amp*55)))
			end)
		end
		task.wait()
	end

	-- 2) CRACK: particle burst + sound, fling shell shards, remove the intact egg visual
	print("[Pet][HATCH] egg cracked, pet emerging")
	-- HATCH SOUND #2: the PRELOADED PET-UNLOCK sound lands HERE at the crack/shatter beat as the pet reveals
	-- (preloaded, so it fires on time -- no ~2s load delay -- layered over the tail of the crack as the payoff).
	pcall(function() hatchUnlockSound.TimePosition = 0; hatchUnlockSound:Play() end)
	pcall(function()
		local fx = Instance.new("Part"); fx.Anchored=true; fx.CanCollide=false; fx.CanQuery=false; fx.Transparency=1; fx.Size=Vector3.new(1,1,1); fx.CFrame=base; fx.Parent=Workspace
		local em=Instance.new("ParticleEmitter"); em.Texture="rbxasset://textures/particles/sparkles_main.dds"; em.Color=ColorSequence.new(Color3.fromRGB(210,255,180)); em.Lifetime=NumberRange.new(0.4,0.8); em.Speed=NumberRange.new(8,16); em.SpreadAngle=Vector2.new(180,180); em.Size=NumberSequence.new(1.4); em.Rate=0; em.LightEmission=0.9; em.Parent=fx
		em:Emit(40)
		local snd=Instance.new("Sound"); snd.SoundId="rbxassetid://9116458024"; snd.Volume=0.6; snd.Parent=fx; snd:Play()
		game:GetService("Debris"):AddItem(fx, 1.2)
	end)
	if visual then
		pcall(function()
			for s = 1, 6 do
				local ang = (s-1) * (2*math.pi/6)
				local shard = Instance.new("Part"); shard.Shape=Enum.PartType.Ball; shard.Size=Vector3.new(1.1,0.7,1.1); shard.Color=Color3.fromRGB(210,234,182); shard.Material=Enum.Material.SmoothPlastic
				shard.Anchored=true; shard.CanCollide=false; shard.CanQuery=false; shard.CastShadow=false; shard.CFrame=base*CFrame.new(0,1,0); shard.Parent=Workspace
				TweenService:Create(shard, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{CFrame=base*CFrame.new(math.cos(ang)*5, math.random()*3-1, math.sin(ang)*5), Transparency=1, Size=Vector3.new(0.2,0.2,0.2)}):Play()
				game:GetService("Debris"):AddItem(shard, 0.8)
			end
		end)
		pcall(function() visual:Destroy() end); st.eggVisual = nil
	end

	-- 3) PET POPS OUT: spawn the follower, scale-pop it at the nest, then hand off to the follow loop
	spawnFollowerPet(petId)
	local pet = st.pet
	st.emerging = true -- follow loop skips it while we control the pop
	if pet then
		pcall(function() pet:ScaleTo(0.2) end)
		local POP, pop0 = 0.45, os.clock()
		while os.clock() - pop0 < POP do
			local p = (os.clock() - pop0) / POP
			pcall(function() pet:ScaleTo(0.2 + p * 0.8); pet:PivotTo(base * CFrame.new(0, math.sin(p * math.pi) * 2.2, 0)) end)
			task.wait()
		end
		pcall(function() pet:ScaleTo(1) end)
	end
	petSmoothPos = base.Position -- the pet flies OUT from the nest toward the player
	st.emerging = false

	-- 4) register the claim (ownership + persistence) -- AFTER the animation, per design
	pcall(function() PetClaimEvent:FireServer(petId) end)
	print("[Pet][HATCH] hatch complete, pet now following")
	st.hatching = false
	task.delay(2.0, function() if st.egg then pcall(function() st.egg:Destroy() end); st.egg = nil end end) -- clean up the nest container
end

-- ===== STATE SYNC =====
local equippedPetId = nil -- the petId currently equipped (drives the follower + flight-progress accrual)
local function applyState(state)
	for petId, def in pairs(PETS) do
		petState[petId] = petState[petId] or { pieces = {}, collected = {}, egg = nil, pet = nil, built = false, owns = false }
		local st = petState[petId]
		local info = state[petId] or { found = 0, total = #def.pieceMarkers, owns = false }
		local prevFound = st.uiFound or 0
		local wasOwned = st.owns -- RE-DOABLE QUEST: detect a pet we JUST lost (traded away) to reset its local quest progress
		st.owns = info.owns == true
		st.equipped = info.equipped == true
		st.level = info.level or 1
		st.rare = info.rare == true -- rare variant flag (drives pre-maxed + rare look)
		if st.equipped then equippedPetId = petId elseif equippedPetId == petId then equippedPetId = nil end
		st.uiFound = info.found
		st.total = info.total
		if st.owns then
			-- owns the pet: hide find-pieces + egg + chest, follow ONLY if equipped, and tear down the quest UI
			for i, piece in pairs(st.pieces) do setVisible(piece, false) end
			setVisible(st.egg, false)
			if st.chest then setVisible(st.chest, false) end
			if st.filmProps then for _, o in ipairs(st.filmProps) do setVisible(o, false) end end -- (empty now: the projector + beam are PERMANENT, never hidden)
			if st.projGlow then st.projGlow(false) end -- owned -> remove the projector glow

			if st.fishProps then for _, o in ipairs(st.fishProps) do setVisible(o, false) end end -- fishing: hide the rod barrel + fish spot (prompt) once owned
			if st.digProps then for _, o in ipairs(st.digProps) do setVisible(o, false) end end -- dig: hide the shovel stand + dig mounds + held shovel once owned
			-- NOTE: st.movieGui is intentionally NOT destroyed here -- the finale end card holds on the screen permanently
			if st.hatchScreenEgg then st.hatchScreenEgg() end -- popcorn: now owned -> crack the egg off the screen end frame, revealing the sheep
			if st.equipped then spawnFollowerPet(petId) else despawnFollowerPet(petId) end
			hideQuestUI(petId)
			if not st.uiDoneLogged then st.uiDoneLogged = true; print("[Pet][UI] quest complete - UI hidden") end
		else
			-- RE-DOABLE QUEST: if we JUST lost this pet (traded it away), the server has reset its quest progress
			-- to zero -- wipe the stale LOCAL progress so the pieces/egg/chest reappear and it can be re-done now.
			if wasOwned then st.collected = {}; st.hasKey = false; st.uiFound = 0; info.found = 0 end
			-- not owned yet: show uncollected pieces/coconuts. For "find" the egg appears at full count; for
			-- "crack" the CHEST stays visible and glows once the player has the Cave Key (the egg is revealed
			-- only when they open the chest). While st.hatching, leave the egg/glow alone.
			for i, piece in pairs(st.pieces) do setVisible(piece, not st.collected[i]) end
			if st.isCrack then
				if st.chest then setVisible(st.chest, true) end
				if st.chestGlow then st.chestGlow(st.hasKey or info.found >= info.total) end -- glow once the Cave Key is earned (local or server-confirmed)
			elseif st.isFilm then
				-- projector + screen are static props (built visible); the egg appears ONLY after the projector
				-- show (revealEgg), so don't auto-reveal it here -- st.egg stays nil until the mini-movie plays.
				-- HIGHLIGHT the projector once all reels are collected (so the player finds where to load them);
				-- turn it off once the egg has appeared (movie played).
				if st.projGlow then st.projGlow(info.found >= info.total and not st.egg) end
			elseif st.isFishing then
				-- fishing: the rod barrel + Fish prompt are static; the egg appears ONLY when CAUGHT (spawnButterEgg),
				-- so don't auto-reveal anything here -- st.egg stays nil until the player reels in the egg.
			elseif st.isDigging then
				-- dig: the shovel stand + dig mounds are static; the egg appears ONLY when the REAL spot is dug
				-- (spawnArmadilloEgg), so don't auto-reveal anything here -- st.egg stays nil until then.
			elseif not st.hatching then
				setVisible(st.egg, info.found >= info.total)
			end
			-- ===== QUEST UI: the on-screen tracker is refreshed ONCE after this loop (refreshQuestHUD picks
			-- which quest to show); here we only fire the first-piece discovery popup + the progress log. =====
			if info.found >= 1 then
				if prevFound < 1 then showDiscoveryPopup(def, info.found, info.total) end -- first piece = the reveal
				if info.found ~= prevFound then print("[Pet][UI] tracker updated: "..info.found.."/"..info.total) end
			end
			if info.found >= info.total and info.found >= 1 then
				if not st.isCrack and not st.isFilm and not st.isFishing and not st.hatching then setEggGlow(petId, true) end -- broccoli: glowing egg at full count (crack/film/fishing reveal their egg via an interaction)
				if not st.ui3of3Logged then st.ui3of3Logged = true; print("[Pet][UI] "..info.total.."/"..info.total.." reached") end
			else
				if not st.isCrack and not st.isFilm and not st.isFishing then setEggGlow(petId, false) end
				st.ui3of3Logged = false
			end
		end
	end
	refreshQuestHUD() -- re-pick + render the on-screen quest indicator from the latest state
end
if PetStateEvent then PetStateEvent.OnClientEvent:Connect(applyState) end -- guarded: a missing remote can't crash the script

-- RARE HATCH FANFARE: the server fires this when a rare hatches -> a big on-screen "RARE!" callout + an extra
-- sparkle burst on the new pet, so the player clearly knows they got something special. Cosmetic-only.
if PetRareEvent then
	PetRareEvent.OnClientEvent:Connect(function(petId, rareName)
		print(string.format("[PetRare] RARE hatch fanfare: %s (%s)", tostring(rareName), tostring(petId)))
		local TW = game:GetService("TweenService")
		local sg = Instance.new("ScreenGui"); sg.Name="RareHatchFanfare"; sg.ResetOnSpawn=false; sg.DisplayOrder=60; sg.IgnoreGuiInset=true
		sg.Parent = player:WaitForChild("PlayerGui")
		local lbl = Instance.new("TextLabel"); lbl.AnchorPoint=Vector2.new(0.5,0.5); lbl.Position=UDim2.new(0.5,0,0.32,0); lbl.Size=UDim2.new(0,540,0,90)
		lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextScaled=true; lbl.TextColor3=Color3.fromRGB(255,170,245)
		lbl.Text="\xE2\x9C\xA8 RARE!  "..tostring(rareName).."  \xE2\x9C\xA8"; lbl.Parent=sg
		local stk=Instance.new("UIStroke", lbl); stk.Color=Color3.fromRGB(150,20,140); stk.Thickness=3
		lbl.TextTransparency=1; stk.Transparency=1
		TW:Create(lbl, TweenInfo.new(0.3), {TextTransparency=0}):Play(); TW:Create(stk, TweenInfo.new(0.3), {Transparency=0}):Play()
		task.delay(2.0, function()
			TW:Create(lbl, TweenInfo.new(0.6), {TextTransparency=1, Position=UDim2.new(0.5,0,0.26,0)}):Play()
			TW:Create(stk, TweenInfo.new(0.6), {Transparency=1}):Play()
			task.wait(0.7); sg:Destroy()
		end)
		task.delay(0.4, function() -- let the pet spawn, then a celebratory burst on it
			local st = petState[petId]; local pet = st and st.pet; local root = pet and pet.PrimaryPart
			if root then
				local b = Instance.new("ParticleEmitter"); b.Color=ColorSequence.new(Color3.fromRGB(255,150,240)); b.LightEmission=0.9
				b.Lifetime=NumberRange.new(0.5,1.0); b.Speed=NumberRange.new(6,14); b.Size=NumberSequence.new(0.7); b.Rate=0; b.Rotation=NumberRange.new(0,360); b.Parent=root
				b:Emit(60); game:GetService("Debris"):AddItem(b, 1.4)
			end
		end)
	end)
end

-- ===== STARTUP: handshake for state, then ASK THE SERVER for marker positions and build =====
-- Fire the state handshake FIRST so an OWNED pet spawns immediately (the follower needs no markers).
if PetRequestStateEvent then pcall(function() PetRequestStateEvent:FireServer() end) end

-- Per pet: ASK the server for the marker coordinates (no Workspace searching) and build from them.
for petId, def in pairs(PETS) do
	petState[petId] = petState[petId] or { pieces = {}, collected = {}, egg = nil, pet = nil, built = false, owns = false }
	if def.questType == "seasonal" then continue end -- seasonal pets have NO island quest world to build (granted by the garden)
	task.spawn(function()
		if not PetGetMarkers then
			warn("[Pet][DIAG] PetGetMarkers RemoteFunction MISSING -- cannot build "..petId.." (server PetSystem not loaded/synced?)")
			return
		end
		local ok, positions = pcall(function() return PetGetMarkers:InvokeServer(petId) end)
		if not ok then
			warn("[Pet][DIAG] PetGetMarkers invoke FAILED for "..petId..": "..tostring(positions))
			return
		end
		if type(positions) ~= "table" then
			warn("[Pet][DIAG] received NIL/invalid positions for "..petId.." -- server had no markers (check the server '[Pet] markers found' logs)")
			return
		end
		local pp = positions.pieces or {}
		local function v(p) return (typeof(p) == "Vector3") and string.format("(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z) or "nil" end
		print("[Pet][DIAG] received positions: piece1="..v(pp[1]).." piece2="..v(pp[2]).." piece3="..v(pp[3]).." egg="..v(positions.egg))
		buildPetWorld(petId, def, positions)
	end)
end

-- re-handshake on respawn (cheap; keeps things in sync if the server pushed state while we were dead)
player.CharacterAdded:Connect(function()
	task.wait(1)
	if PetRequestStateEvent then pcall(function() PetRequestStateEvent:FireServer() end) end
end)

-- ===== MYSTERIOUS LANDING HINT: when the player is grounded on a pet-quest island and hasn't
-- started/finished it, flash the subtle hint ONCE per visit. Island anchor = the egg coordinate
-- (server-provided, on the island). Resets when they leave so it can re-show on a later visit.
task.spawn(function()
	while true do
		task.wait(0.5)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		for petId, def in pairs(PETS) do
			local st = petState[petId]
			local anchor = st and (st.hintAnchor or st.eggPos) -- coconut: anchor the on-landing hint at a COCONUT (island), not the cave chest
			if hrp and anchor then
				local dx, dz = hrp.Position.X - anchor.X, hrp.Position.Z - anchor.Z
				local inArea = math.sqrt(dx*dx + dz*dz) < 200 and math.abs(hrp.Position.Y - anchor.Y) < 90
				local grounded = hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
				if inArea and grounded and not onIsland[petId] then
					onIsland[petId] = true
					pcall(function() PetQuestDiscovered:FireServer(petId) end) -- record the quest as DISCOVERED (server dedups + persists)
					-- (landing card removed: the big "??? Quest" flashHint card no longer shows on landing.)
					-- Reveal the island-bound tracker only AFTER the island arrival intro finishes, so the
					-- top-center tracker isn't covered by the "You reached ..." banner. Wait for the arrival
					-- frame to hide (re-visits = no intro -> shows quickly), then show if still on the island.
					task.spawn(function()
						task.wait(0.6) -- let the arrival intro (if any) appear first
						for _ = 1, 40 do
							local af = _G.gui and _G.gui.arrivalFrame
							if not (af and af.Visible) then break end
							task.wait(0.15)
						end
						if onIsland[petId] then refreshQuestHUD() end
					end)
				elseif not inArea and onIsland[petId] then
					onIsland[petId] = false
					refreshQuestHUD() -- left the island: drop the AVAILABLE card (a started counter stays up)
				end
			end
		end
	end
end)

-- ===== EGG POINTER: when the active pet is at 3/3 (egg available, not owned), point an on-screen
-- arrow at the egg's world position (clamped to the screen edge when it's off-screen/behind).
RunService.RenderStepped:Connect(function()
	local petId = activeUiPet
	local st = petId and petState[petId]
	if not st or st.owns or not st.eggPos or (st.uiFound or 0) < (st.total or 3) then pointer.Visible = false; return end
	local target = (st.pointTarget or st.eggPos) + Vector3.new(0, 2.3, 0) -- film-reels: points at the projector until the show, then the egg
	local vp = Camera:WorldToViewportPoint(target)
	local vs = Camera.ViewportSize
	local cx, cy = vs.X * 0.5, vs.Y * 0.5
	if vp.Z > 0 and vp.X >= 0 and vp.X <= vs.X and vp.Y >= 0 and vp.Y <= vs.Y then
		pointer.Position = UDim2.new(0, vp.X, 0, math.max(vp.Y - 64, 36)) -- hover above the egg
		pointer.Rotation = 90 -- "➤" rotated to point DOWN at it
	else
		local dx, dy
		if vp.Z > 0 then dx, dy = vp.X - cx, vp.Y - cy else dx, dy = cx - vp.X, cy - vp.Y end -- behind camera -> invert
		local mag = math.sqrt(dx*dx + dy*dy); if mag < 1 then dx, dy, mag = 0, -1, 1 end
		dx, dy = dx/mag, dy/mag
		pointer.Position = UDim2.new(0, cx + dx * (cx - 70), 0, cy + dy * (cy - 70)) -- clamp to screen edge
		pointer.Rotation = math.deg(math.atan2(dy, dx)) -- "➤" points along +X at rotation 0
	end
	pointer.Visible = true
end)

-- ============================================================================================
-- PET INVENTORY GUI -- storage (grid of OWNED pets) + EQUIP toggle (one at a time) + a wired-but-stubbed
-- LEVELING/UPGRADE framework (achievement progress OR Robux). Server-authoritative (PetInventoryEvent);
-- the buttons just fire remotes. Cosmetic-only. Data-driven from the inventory table so future pets/tiers
-- plug in with no GUI changes.
-- ============================================================================================
-- Styled to MATCH the game's existing GUI (Shop / former Daily popup): a blue panel (25,90,185) with a
-- white stroke + rounded corners, a darker-blue header (15,60,140) with a GOLD GothamBold title + white
-- Gotham subtitle, and a red close button. There is NO separate paw button here anymore -- the ONE pet
-- button is the repurposed HUD button (CoreClient), which toggles this panel via a BindableEvent.
local pg = player:WaitForChild("PlayerGui")
local invGui = Instance.new("ScreenGui")
invGui.Name = "PetInventoryUI"; invGui.ResetOnSpawn = false; invGui.DisplayOrder = 100 -- EXACT same ScreenGui settings as the SHOP (PremiumShopGui): DisplayOrder 100, no IgnoreGuiInset
invGui.Parent = pg
local function uicorner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function uistroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 2; s.Parent = o; return s end

-- INVISIBLE click-block behind the panel (NO dark film): fully transparent + Active so the rest of the
-- HUD stays VISIBLE but non-interactable while the panel is open -- same treatment as the food shop.
local dim = Instance.new("Frame"); dim.Name = "Dim"; dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0)
-- Active=FALSE so clicks OUTSIDE the panel fall through to the HUD MENU BUTTONS (direct click-to-switch). The
-- panel itself is Active=true so panel clicks don't leak to the HUD behind it.
dim.BackgroundTransparency = 1; dim.Visible = false; dim.Active = false; dim.Parent = invGui

-- PANEL -- EXACT same Size + Position + AnchorPoint as the SHOP menu's FINAL layout (PremiumShopGui's premPanel,
-- after its layout pass): 700 x 520 fixed, centered, nudged up 45px. No UIScale/UISizeConstraint/UIAspectRatioConstraint on the Shop.
local panel = Instance.new("Frame"); panel.Name = "Panel"
panel.Size = UDim2.new(0,700,0,520); panel.Position = UDim2.new(0.5,0,0.5,-45); panel.AnchorPoint = Vector2.new(0.5,0.5) -- copied verbatim from the SHOP panel's final values (do NOT recompute / no responsive fit)
panel.BackgroundColor3 = Color3.fromRGB(25,90,185); panel.ClipsDescendants = true; panel.Visible = false; panel.Active = true; panel.Parent = invGui -- Active=true so panel clicks don't leak to the HUD behind it
uicorner(panel, 18); uistroke(panel, Color3.new(1,1,1), 3)

-- HEADER
local header = Instance.new("Frame"); header.Size = UDim2.new(1,0,0,60); header.BackgroundColor3 = Color3.fromRGB(15,60,140); header.Parent = panel
uicorner(header, 18)
local title = Instance.new("TextLabel"); title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBold; title.TextSize = 26
title.TextColor3 = Color3.fromRGB(255,215,0); title.Text = "\xF0\x9F\x90\xBE PET HUB"; title.TextXAlignment = Enum.TextXAlignment.Left
title.Size = UDim2.new(1,-60,0,34); title.Position = UDim2.new(0,14,0,5); title.Parent = header
uistroke(title, Color3.new(0,0,0), 2)
local subtitle = Instance.new("TextLabel"); subtitle.BackgroundTransparency = 1; subtitle.Font = Enum.Font.Gotham; subtitle.TextSize = 13
subtitle.TextColor3 = Color3.new(1,1,1); subtitle.Text = "Your pets & quest progress"; subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Size = UDim2.new(1,-60,0,16); subtitle.Position = UDim2.new(0,14,0,40); subtitle.Parent = header
local closeBtn = Instance.new("TextButton"); closeBtn.Size = UDim2.new(0,40,0,40); closeBtn.Position = UDim2.new(1,-48,0,10)
closeBtn.BackgroundColor3 = Color3.fromRGB(220,50,50); closeBtn.Text = "X"; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22 -- plain "X" matches the other GUIs' close buttons
closeBtn.TextColor3 = Color3.new(1,1,1); closeBtn.Parent = header
uicorner(closeBtn, 8); uistroke(closeBtn, Color3.new(0,0,0), 2)

-- ===== TWO SECTIONS: LEFT = PETS (owned cards + locked "?" slots), RIGHT = QUESTS (discovered quests) =====
local function makeSection(x, w, titleText)
	local sec = Instance.new("Frame"); sec.Size = UDim2.new(0,w,1,-74); sec.Position = UDim2.new(0,x,0,68)
	sec.BackgroundColor3 = Color3.fromRGB(18,66,150); sec.BackgroundTransparency = 0.25; sec.Parent = panel
	uicorner(sec, 12); uistroke(sec, Color3.fromRGB(10,40,100), 2)
	local t = Instance.new("TextLabel"); t.Size = UDim2.new(1,-12,0,22); t.Position = UDim2.new(0,8,0,6)
	t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold; t.TextSize = 16; t.TextColor3 = Color3.fromRGB(255,215,0)
	t.TextXAlignment = Enum.TextXAlignment.Left; t.Text = titleText; t.Parent = sec
	local sc = Instance.new("ScrollingFrame"); sc.Size = UDim2.new(1,-12,1,-34); sc.Position = UDim2.new(0,6,0,30)
	sc.BackgroundTransparency = 1; sc.BorderSizePixel = 0; sc.ScrollBarThickness = 6; sc.ScrollBarImageColor3 = Color3.fromRGB(255,215,0)
	sc.CanvasSize = UDim2.new(0,0,0,0); sc.Parent = sec
	return sec, sc
end
-- PETS now fills the FULL panel width (the pets are the star) -> 2 BIG cards per row with large 3D pictures.
local petsSection, petsScroll = makeSection(12, 676, "\xF0\x9F\x90\xBe PETS")
-- Panel now uses the SHOP's scale-based size (0.9 x 0.85), so make this section fill it responsively (scale width,
-- like the quests overlay) instead of a fixed 676px -- the centered grid then sits properly at any panel width.
petsSection.Size = UDim2.new(1, -24, 1, -74); petsSection.Position = UDim2.new(0, 12, 0, 68)
local petsGrid = Instance.new("UIGridLayout"); petsGrid.CellSize = UDim2.new(0,322,0,252); petsGrid.CellPadding = UDim2.new(0,10,0,12)
petsGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center; petsGrid.Parent = petsScroll
-- small TOP/side padding so the first row of pet cards isn't clipped at the scroll's top edge. Wrapped in a
-- do-block on purpose: the `pad` local is block-scoped (freed immediately), so it adds NO persistent
-- module-scope local -- avoiding Luau's 200-local main-chunk limit that broke the earlier all-at-once tries.
do
	local pad = Instance.new("UIPadding"); pad.Name = "PetsTopPad"
	pad.PaddingTop = UDim.new(0,10); pad.PaddingLeft = UDim.new(0,4); pad.PaddingRight = UDim.new(0,4)
	pad.Parent = petsScroll
end

-- QUEST INFO is tucked into a small COLLAPSIBLE overlay (hidden until the header "QUESTS" tab is tapped), so
-- it no longer takes prime space away from the pets. Same look as the trade overlay.
local questsOverlay = Instance.new("Frame"); questsOverlay.Name = "QuestsOverlay"; questsOverlay.Size = UDim2.new(1,-24,1,-74); questsOverlay.Position = UDim2.new(0,12,0,68)
questsOverlay.BackgroundColor3 = Color3.fromRGB(16,60,140); questsOverlay.Visible = false; questsOverlay.Parent = panel; uicorner(questsOverlay, 12); uistroke(questsOverlay, Color3.fromRGB(10,40,100), 2)
local qoTitle = Instance.new("TextLabel"); qoTitle.Size = UDim2.new(1,-120,0,28); qoTitle.Position = UDim2.new(0,12,0,8); qoTitle.BackgroundTransparency = 1
qoTitle.Font = Enum.Font.GothamBold; qoTitle.TextSize = 18; qoTitle.TextColor3 = Color3.fromRGB(255,215,0); qoTitle.TextXAlignment = Enum.TextXAlignment.Left; qoTitle.Text = "\xF0\x9F\x97\xBA Pet Quests"; qoTitle.Parent = questsOverlay
local qoBack = Instance.new("TextButton"); qoBack.Size = UDim2.new(0,100,0,28); qoBack.Position = UDim2.new(1,-108,0,8); qoBack.BackgroundColor3 = Color3.fromRGB(120,120,120)
qoBack.Font = Enum.Font.GothamBold; qoBack.TextSize = 13; qoBack.TextColor3 = Color3.new(1,1,1); qoBack.Text = "\xE2\x97\x80 Pets"; qoBack.Parent = questsOverlay; uicorner(qoBack, 8)
local questsScroll = Instance.new("ScrollingFrame"); questsScroll.Size = UDim2.new(1,-16,1,-46); questsScroll.Position = UDim2.new(0,8,0,42); questsScroll.BackgroundTransparency = 1; questsScroll.BorderSizePixel = 0
questsScroll.ScrollBarThickness = 6; questsScroll.ScrollBarImageColor3 = Color3.fromRGB(255,215,0); questsScroll.CanvasSize = UDim2.new(0,0,0,0); questsScroll.Parent = questsOverlay
local questsList = Instance.new("UIListLayout"); questsList.Padding = UDim.new(0,8); questsList.SortOrder = Enum.SortOrder.LayoutOrder; questsList.Parent = questsScroll
local questsEmpty = Instance.new("TextLabel"); questsEmpty.Size = UDim2.new(1,-24,0,70); questsEmpty.Position = UDim2.new(0,12,0,46)
questsEmpty.BackgroundTransparency = 1; questsEmpty.Font = Enum.Font.Gotham; questsEmpty.TextSize = 14; questsEmpty.TextWrapped = true
questsEmpty.TextColor3 = Color3.fromRGB(200,220,255); questsEmpty.Text = "Land on islands to discover pet quests!"; questsEmpty.Visible = false; questsEmpty.Parent = questsOverlay

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY: shared manager (one instance across client scripts, via _G). Guarded
-- factory so whichever client script loads first creates it. The Pet Hub joins the "only one open" group. =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible)                                                -- hide/show the WHOLE bottom HUD (gut pill + gas meter + fart button all live in BottomStackGui)
		local lp = game:GetService("Players").LocalPlayer
		local pgx = lp and lp:FindFirstChildOfClass("PlayerGui")
		local g = pgx and pgx:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h = mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name
		mgr.setHud(false)                                                       -- a main menu is now open -> hide the bottom HUD (Shop/Pet Hub/Seasonal Pets all route through here)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end                         -- last menu closed -> restore the bottom HUD
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
_G.MainMenuManager.register("PetInv", function() panel.Visible = false; dim.Visible = false end) -- full-hide the Pet Hub

local latestInv = { owned = {}, quests = {}, totalPets = 0 }
-- Defensive de-dup: multiple StyleLinks under CoreGui cause "undefined behavior" GUI warnings/glitches. We
-- never create StyleLinks, but if extras appear we keep ONE and drop the rest. Guarded (CoreGui may be
-- write-protected for non-core scripts -> the pcall just no-ops then). Cosmetic/safety only.
local function dedupeStyleLinks()
	pcall(function()
		local cg = game:GetService("CoreGui")
		local seen = false
		for _, c in ipairs(cg:GetChildren()) do
			if c:IsA("StyleLink") then
				if seen then c:Destroy() else seen = true end
			end
		end
	end)
end
dedupeStyleLinks()

-- Open/close the Pet Hub ROBUSTLY. The panel is shown/hidden FIRST (so the menu state is always correct),
-- then the manager-notify + counting/logging run inside a pcall so a single error (e.g. while building the
-- heavier 3D pet icons) can NEVER leave the Hub stuck unable to open. Errors are printed, not swallowed.
local function openPanel(open)
	open = open and true or false
	local okShow = pcall(function() panel.Visible = open; dim.Visible = open end) -- SHOW/HIDE FIRST, no matter what
	if not okShow then warn("[PetInv] ERROR opening/building: panel reference invalid (could not set Visible)"); return end
	local ok, err = pcall(function()
		if open then
			pcall(function() questsOverlay.Visible = false end) -- a fresh open lands on the pet cards, not a stuck sub-tab
			dedupeStyleLinks() -- clean up any extra StyleLinks each open (addresses the CoreGui warning)
			_G.MainMenuManager.notifyOpened("PetInv") -- direct switch: close any other open main menu first
			local nOwned = 0; for _ in pairs(latestInv.owned or {}) do nOwned = nOwned + 1 end
			local nQuests = 0; for _ in pairs(latestInv.quests or {}) do nQuests = nQuests + 1 end
			print("[PetInv] inventory opened - owned: " .. nOwned .. ", quests discovered: " .. nQuests)
			if _G.applyHudScaling then _G.applyHudScaling() end -- re-apply the SHOP's identical UIScale so this panel matches the Shop size exactly
			task.defer(function() print("[UIFix] PetHub AbsoluteSize=" .. tostring(panel.AbsoluteSize) .. " AbsolutePosition=" .. tostring(panel.AbsolutePosition)) end) -- resolved on-screen size, to compare vs the SHOP
		else
			_G.MainMenuManager.notifyClosed("PetInv")
			pcall(function() questsOverlay.Visible = false end) -- reset sub-overlays on close so it re-opens clean
		end
	end)
	if not ok then
		warn("[PetInv] ERROR opening/building: " .. tostring(err))
		-- SELF-HEAL the manager so a failed open can never leave it stuck (every later click still works):
		-- if we were opening, the panel IS shown so claim "PetInv"; otherwise clear it.
		pcall(function()
			if open then _G.MainMenuManager.current = "PetInv" else _G.MainMenuManager.notifyClosed("PetInv") end
		end)
	end
end
closeBtn.MouseButton1Click:Connect(function() openPanel(false) end)
dim.InputBegan:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then openPanel(false) end
end)
-- the ONE pet button (the repurposed daily-rewards HUD button in CoreClient) toggles this panel via here
local toggleEvent = Instance.new("BindableEvent"); toggleEvent.Name = "PetInvToggle"; toggleEvent.Parent = pg
toggleEvent.Event:Connect(function()
	local current = _G.MainMenuManager and _G.MainMenuManager.current
	local isOpen = false; pcall(function() isOpen = panel.Visible == true end) -- read actual visibility safely
	print("[MenuMgr] PetInv click - current open menu = " .. tostring(current) .. ", panel open = " .. tostring(isOpen) .. " -> " .. (isOpen and "closing" or "opening (proceeding)"))
	openPanel(not isOpen)
end)

-- ===== 3D VIEWPORT ICONS: each owned pet card's icon is a CLONE of the real pet model at its current-level
-- look (accessories/colors/variant), slowly auto-rotating. Clones never touch the real follow pets. =====
local iconSpins = {} -- list of { model } icon clones to slowly spin (only while the menu is open)
local function stripIconEffects(model) -- drop particle/glow/orbit effects (don't render in a viewport / would clutter it); keep body + accessories
	for _, d in ipairs(model:GetDescendants()) do
		local n = d.Name
		if n=="PetOrb" or n=="PetRing" or n=="PetPulse" or n=="PetSparkle" or n=="PetAura" or n=="PetAuraLight"
			or n=="PetBurst" or n=="PetTrail" or n=="PTrailA0" or n=="PTrailA1" or n=="PetRareFX" or n=="PetRareLight"
			or n=="LevelGlow" or n=="LevelTag" then d:Destroy() end
	end
end
-- a CLONE of a pet at its current-level look (same accessories/colors/variant as the real pet) for the icon.
local function buildIconModel(petId, level, isRare)
	local tn = PET_TEMPLATE_NAME[petId]
	local template = tn and RS:FindFirstChild(tn)
	local model = template and template:Clone()
	if not model then local fb = PET_FALLBACK[petId]; model = (fb and fb(0.9)) or buildBroccoliDinoFallback(0.9) end
	model.Name = petId .. "Icon"
	if not model.PrimaryPart then model.PrimaryPart = model:FindFirstChild("Root") end
	petAnims[model] = { s = 0.9, parts = {}, t = 0 } -- temp entry so the accessory builder can attach; removed right after (icon is static)
	pcall(function() applyLevelVisual(model, level or 1, petId, isRare, true) end) -- LITE: size + accessories + rare recolor only (no heavy FX)
	stripIconEffects(model)
	petFX[model] = nil; petAnims[model] = nil -- detach from the global anim/FX loops (icon is a static, separately-spun clone)
	return model
end
-- DEFERRED ICON BUILDER. The heavy 3D clone build (clone template + apply lvl-25/rare visuals + frame the
-- camera) is NOT done synchronously -- doing 5 maxed/rare pets at once (especially right after /rarepets,
-- alongside the rare fanfare + follow-pet spawn) was a single huge burst that could exhaust execution time
-- and HANG the PetFollow script, severing its connections so the menu's toggle handler never ran again.
-- Instead each icon is queued and built ONE-PER-FRAME by a single worker, each in its OWN pcall, with a paw
-- placeholder shown until it's ready (or kept as the fallback if that one icon fails). One bad/maxed/rare
-- icon can NEVER stall the others or the menu.
local iconQueue = {}            -- pending { vp, cam, ph, petId, level, isRare }
local iconWorkerActive = false
local function startIconWorker()
	if iconWorkerActive then return end
	iconWorkerActive = true
	task.spawn(function()
		while true do
			local req = table.remove(iconQueue, 1)
			if not req then break end
			if req.vp.Parent then -- skip viewports a later rebuild already destroyed
				local ok, model = pcall(buildIconModel, req.petId, req.level, req.isRare)
				if ok and model and req.vp.Parent then
					local okFrame = pcall(function()
						model:PivotTo(CFrame.new()) -- root at origin
						model.Parent = req.vp
						local cf, size = model:GetBoundingBox()
						local maxe = math.max(size.X, size.Y, size.Z, 1)
						local center = cf.Position
						local dir = Vector3.new(0.8, 0.5, 0.55).Unit -- 3/4 front view (pets face +X), slightly above
						req.cam.CFrame = CFrame.lookAt(center + dir * (maxe * 1.45 + 1), center) -- distance fits any size
						iconSpins[#iconSpins+1] = { model = model, center = center }
					end)
					if okFrame then if req.ph then req.ph.Visible = false end
					else warn("[PetInv] icon frame failed for " .. tostring(req.petId) .. " (keeping placeholder)") end
				else
					if model then pcall(function() model:Destroy() end) end
					if not ok then warn("[PetInv] ERROR building icon for " .. tostring(req.petId) .. ": " .. tostring(model) .. " (keeping placeholder)") end
				end
			end
			task.wait() -- one icon per frame -> no single heavy synchronous burst (never exhausts execution time)
		end
		iconWorkerActive = false
		if #iconQueue > 0 then startIconWorker() end -- close the enqueue-just-as-we-exit race
	end)
end
-- (sizeU/posU/anchorV optional: the menu cards pass a BIG size; the trade window reuses this for both offers)
-- Creates the ViewportFrame + a paw placeholder IMMEDIATELY (cheap) and QUEUES the heavy 3D build (see above).
local function makeViewportIcon(card, petId, level, isRare, sizeU, posU, anchorV)
	local vp = Instance.new("ViewportFrame"); vp.Name = "Icon3D"
	vp.AnchorPoint = anchorV or Vector2.new(0.5,0); vp.Size = sizeU or UDim2.new(0,54,0,34); vp.Position = posU or UDim2.new(0.5,0,0,2)
	vp.BackgroundColor3 = Color3.fromRGB(12,34,78); vp.BackgroundTransparency = 0.15; vp.Parent = card
	uicorner(vp, 8)
	vp.Ambient = Color3.fromRGB(185,185,195); vp.LightColor = Color3.fromRGB(255,255,255); vp.LightDirection = Vector3.new(-0.4,-1,-0.5)
	local cam = Instance.new("Camera"); cam.FieldOfView = 50; cam.Parent = vp; vp.CurrentCamera = cam
	local ph = Instance.new("TextLabel"); ph.Name = "IconPlaceholder"; ph.Size = UDim2.new(1,0,1,0); ph.BackgroundTransparency = 1
	ph.Font = Enum.Font.FredokaOne; ph.TextScaled = true; ph.TextColor3 = Color3.fromRGB(150,180,235); ph.Text = "\xF0\x9F\x90\xBE"; ph.Parent = vp
	iconQueue[#iconQueue + 1] = { vp = vp, cam = cam, ph = ph, petId = petId, level = level, isRare = isRare }
	startIconWorker()
	return vp
end
-- ONE slow auto-rotate loop for ALL icon clones; only runs while the pet menu is OPEN (so closed = no cost,
-- and ViewportFrames only render while visible anyway).
do
	local angle = 0
	game:GetService("RunService").RenderStepped:Connect(function(dt)
		if not panel.Visible or #iconSpins == 0 then return end
		angle = (angle + dt * 0.6) % (2 * math.pi) -- slow + smooth
		for i = #iconSpins, 1, -1 do
			local ic = iconSpins[i]
			if ic.model and ic.model.Parent then
				ic.model:PivotTo(CFrame.new(ic.center) * CFrame.Angles(0, angle, 0) * CFrame.new(-ic.center))
			else
				table.remove(iconSpins, i)
			end
		end
	end)
end

-- one OWNED pet card (icon/name/level/equip/upgrade/robux) into the PETS grid
local function buildPetCard(petId, p, order)
	local card = Instance.new("Frame"); card.Name = petId; card.LayoutOrder = order
	card.BackgroundColor3 = p.rare and Color3.fromRGB(46,28,86) or Color3.fromRGB(20,70,160); card.Parent = petsScroll
	uicorner(card, 12)
	local tierName, tierColor, isVariant, flashy = petTier(p.level, p.rare, petId)
	-- border: variant = its tier color (Exotic/Mythical) glow; else equipped = gold; else default.
	uistroke(card, isVariant and tierColor or (p.equipped and Color3.fromRGB(255,215,0) or Color3.fromRGB(10,40,100)), (isVariant or p.equipped) and 3 or 1)
	-- BIG 3D picture across the top of the card -- the pets are the star of the menu
	makeViewportIcon(card, petId, p.level, p.rare, UDim2.new(0,310,0,140), UDim2.new(0.5,0,0,6), Vector2.new(0.5,0))
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-16,0,18); nm.Position = UDim2.new(0,8,0,150)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 16
	nm.TextColor3 = isVariant and tierColor or Color3.new(1,1,1)
	nm.Text = p.rare and (p.rareName or p.displayName) or p.displayName; nm.Parent = card -- show the variant name (e.g. "Cosmic Duck") for rares
	if isVariant then -- a flashy TIER badge (Exotic / Mythical) in the top-right corner
		local tag = Instance.new("TextLabel"); tag.AutomaticSize = Enum.AutomaticSize.X; tag.Size = UDim2.new(0,0,0,18); tag.Position = UDim2.new(1,-6,0,8); tag.AnchorPoint = Vector2.new(1,0)
		tag.BackgroundColor3 = tierColor; tag.Font = Enum.Font.GothamBold; tag.TextSize = 11; tag.TextColor3 = Color3.new(1,1,1); tag.Text = tierName; tag.Parent = card
		local pad = Instance.new("UIPadding", tag); pad.PaddingLeft = UDim.new(0,5); pad.PaddingRight = UDim.new(0,5)
		uicorner(tag, 5)
		-- thin CLEAN border (not a thick text halo) so the Exotic/Mythical text stays readable
		local ts = Instance.new("UIStroke"); ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ts.Color = Color3.fromRGB(255,255,255); ts.Thickness = 1; ts.Transparency = 0.2; ts.Parent = tag
	end
	local cap = p.maxLevel or 25
	local maxed = (p.level >= cap)
	-- TIER line: NORMAL = "<Tier>  Lv N" (tier-colored); VARIANT = "<Tier>" (Exotic / Mythical). + EQUIPPED.
	local lv = Instance.new("TextLabel"); lv.Size = UDim2.new(1,-16,0,16); lv.Position = UDim2.new(0,8,0,170)
	lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold; lv.TextSize = 13
	lv.Text = (isVariant and tierName or (tierName .. "  Lv " .. p.level)) .. (p.equipped and "  \xE2\x80\xA2 EQUIPPED" or ""); lv.Parent = card
	lv.TextColor3 = tierColor
	-- XP PROGRESS BAR (current XP / XP needed for the next level)
	local barBG = Instance.new("Frame"); barBG.Size = UDim2.new(1,-16,0,14); barBG.Position = UDim2.new(0,8,0,188)
	barBG.BackgroundColor3 = Color3.fromRGB(12,40,90); barBG.BorderSizePixel = 0; barBG.Parent = card; uicorner(barBG, 7); uistroke(barBG, Color3.fromRGB(8,26,64), 1)
	local frac = maxed and 1 or math.clamp((p.xp or 0) / math.max(1, p.xpNeed or 1), 0, 1)
	local fill = Instance.new("Frame"); fill.Size = UDim2.new(frac, 0, 1, 0); fill.BorderSizePixel = 0
	fill.BackgroundColor3 = maxed and Color3.fromRGB(255,200,40) or Color3.fromRGB(80,220,120); fill.Parent = barBG; uicorner(fill, 7)
	local xpTxt = Instance.new("TextLabel"); xpTxt.Size = UDim2.new(1,0,1,0); xpTxt.BackgroundTransparency = 1
	xpTxt.Font = Enum.Font.GothamBold; xpTxt.TextSize = 10; xpTxt.TextColor3 = Color3.new(1,1,1); xpTxt.Parent = barBG
	xpTxt.Text = maxed and "MAX" or ((p.xp or 0) .. " / " .. (p.xpNeed or 0) .. " XP")
	-- NEXT MILESTONE hint (small, bottom of the card)
	local ms = Instance.new("TextLabel"); ms.Size = UDim2.new(1,-16,0,14); ms.Position = UDim2.new(0,8,0,236)
	ms.BackgroundTransparency = 1; ms.Font = Enum.Font.Gotham; ms.TextSize = 11; ms.TextColor3 = Color3.fromRGB(185,212,255)
	ms.Text = "\xE2\x9C\xA8 " .. (p.milestone or ""); ms.Parent = card
	-- EQUIP toggle (left half) + SKIP (right half), side by side to keep the picture big
	local eq = Instance.new("TextButton"); eq.Size = UDim2.new(0,149,0,26); eq.Position = UDim2.new(0,8,0,208)
	eq.Font = Enum.Font.GothamBold; eq.TextSize = 13; eq.TextColor3 = Color3.new(1,1,1)
	eq.BackgroundColor3 = p.equipped and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50)
	eq.Text = p.equipped and "UNEQUIP" or "EQUIP"; eq.Parent = card
	uicorner(eq, 8); uistroke(eq, Color3.new(0,0,0), 1)
	eq.MouseButton1Click:Connect(function()
		if p.equipped then pcall(function() PetEquipEvent:FireServer(false) end)
		else pcall(function() PetEquipEvent:FireServer(petId) end) end
	end)
	-- TIER SKIP (Robux): jump the WHOLE next tier at once (lands on its first level). Button shows the next
	-- tier + price; at the top tier (Legendary) there's nothing to skip. The SERVER validates + applies the jump.
	local sk = Instance.new("TextButton"); sk.Size = UDim2.new(0,149,0,26); sk.Position = UDim2.new(0,165,0,208)
	sk.Font = Enum.Font.GothamBold; sk.TextSize = 12; sk.TextColor3 = Color3.new(1,1,1); sk.Parent = card; uicorner(sk, 8)
	-- which tier-skip step applies to this pet's CURRENT level (Common 1-5 / Uncommon 6-10 / Rare 11-15 / Epic 16-20)
	local skipStep = (p.level <= 5 and PET_SKIP_PRODUCTS[1]) or (p.level <= 10 and PET_SKIP_PRODUCTS[2])
		or (p.level <= 15 and PET_SKIP_PRODUCTS[3]) or (p.level <= 20 and PET_SKIP_PRODUCTS[4]) or nil
	if maxed or not skipStep then
		sk.Text = maxed and "MAX LEVEL" or "MAX TIER"; sk.BackgroundColor3 = Color3.fromRGB(90,90,90); sk.AutoButtonColor = false
	else
		sk.Text = "Skip to " .. skipStep.to .. "  R$" .. skipStep.price; sk.BackgroundColor3 = Color3.fromRGB(50,170,90)
		sk.MouseButton1Click:Connect(function()
			pcall(function() PetPendingUpgrade:FireServer(petId) end) -- declare the pet (testers tier-skip instantly here)
			task.wait(0.15)
			pcall(function() game:GetService("MarketplaceService"):PromptProductPurchase(player, skipStep.id) end)
		end)
	end
end

-- a LOCKED "?" slot (an unowned pet -- no details revealed until earned)
local function buildLockedSlot(order)
	local slot = Instance.new("Frame"); slot.Name = "Locked"; slot.LayoutOrder = order; slot.BackgroundColor3 = Color3.fromRGB(14,46,104); slot.Parent = petsScroll
	uicorner(slot, 10); uistroke(slot, Color3.fromRGB(10,30,80), 1)
	local q = Instance.new("TextLabel"); q.Size = UDim2.new(1,0,1,-22); q.BackgroundTransparency = 1; q.Font = Enum.Font.GothamBold; q.TextSize = 46; q.TextColor3 = Color3.fromRGB(70,100,170); q.Text = "?"; q.Parent = slot
	local lk = Instance.new("TextLabel"); lk.Size = UDim2.new(1,-8,0,18); lk.Position = UDim2.new(0,4,1,-22); lk.BackgroundTransparency = 1; lk.Font = Enum.Font.Gotham; lk.TextSize = 12; lk.TextColor3 = Color3.fromRGB(130,160,220); lk.Text = "\xF0\x9F\x94\x92 Locked"; lk.Parent = slot
end

-- one discovered-quest entry (island name + status + short how-to + small progress) into the QUESTS list
local function buildQuestEntry(q, order)
	local qf = Instance.new("Frame"); qf.Name = "Quest"; qf.LayoutOrder = order; qf.Size = UDim2.new(1,-4,0,92); qf.BackgroundColor3 = Color3.fromRGB(20,70,160); qf.Parent = questsScroll
	uicorner(qf, 8); uistroke(qf, Color3.fromRGB(10,40,100), 1)
	local qn = Instance.new("TextLabel"); qn.Size = UDim2.new(1,-10,0,18); qn.Position = UDim2.new(0,6,0,4)
	qn.BackgroundTransparency = 1; qn.Font = Enum.Font.GothamBold; qn.TextSize = 14; qn.TextColor3 = Color3.new(1,1,1); qn.TextXAlignment = Enum.TextXAlignment.Left; qn.Text = q.islandName or "?"; qn.Parent = qf
	local statusCol = (q.status == "done") and Color3.fromRGB(120,255,120) or (q.status == "inprogress") and Color3.fromRGB(255,205,90) or Color3.fromRGB(180,220,255)
	local statusTxt = (q.status == "done") and "Done \xE2\x9C\x94"
		or (q.status == "inprogress") and ("In Progress  "..(q.found or 0).."/"..(q.total or 0).." "..(q.unit or ""))
		or "Available"
	local qs = Instance.new("TextLabel"); qs.Size = UDim2.new(1,-10,0,14); qs.Position = UDim2.new(0,6,0,22)
	qs.BackgroundTransparency = 1; qs.Font = Enum.Font.GothamBold; qs.TextSize = 11; qs.TextColor3 = statusCol; qs.TextXAlignment = Enum.TextXAlignment.Left; qs.Text = statusTxt; qs.Parent = qf
	local qd = Instance.new("TextLabel"); qd.Size = UDim2.new(1,-12,0,46); qd.Position = UDim2.new(0,6,0,38)
	qd.BackgroundTransparency = 1; qd.Font = Enum.Font.Gotham; qd.TextSize = 11; qd.TextColor3 = Color3.fromRGB(205,222,255); qd.TextWrapped = true
	qd.TextXAlignment = Enum.TextXAlignment.Left; qd.TextYAlignment = Enum.TextYAlignment.Top; qd.Text = q.desc or ""; qd.Parent = qf
end

-- Rebuild is FAILURE-TOLERANT: each card/icon build is pcall'd so one bad pet (e.g. a rare-variant 3D icon
-- that fails to build) can't abort the whole rebuild and leave the menu empty/broken. The whole thing is
-- pcall-wrapped too, so a rebuild error can never knock the Hub into a state where it won't open.
local function rebuildInventory(payload)
	local ok, err = pcall(function()
		latestInv = payload or { owned = {}, quests = {}, totalPets = 0 }
		local owned, quests, totalPets = latestInv.owned or {}, latestInv.quests or {}, latestInv.totalPets or 0
		-- PETS section: ONLY owned-pet cards (no empty/locked placeholder slots); empty -> a "No Pets Unlocked" message
		table.clear(iconSpins) -- the old card viewports (+ their icon clones) are destroyed below; drop their spin entries
		for _, c in ipairs(petsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		local ownedCount, order = 0, 0
		-- SORT owned pets by RARITY TIER (Mythical > Exotic > Legendary > Epic > Rare > Uncommon > Common),
		-- then by LEVEL (high->low). The Cosmic Duck (Mythical, rank 7) ranks ABOVE the 1/99 Exotics (rank 6).
		-- All locals here are function-scoped (no new module-scope locals).
		local rank = { Mythical = 7, Exotic = 6, Legendary = 5, Epic = 4, Rare = 3, Uncommon = 2, Common = 1 }
		local ids = {}
		for petId in pairs(owned) do ids[#ids + 1] = petId end
		table.sort(ids, function(a, b)
			local pa, pb = owned[a], owned[b]
			local ra = rank[petTier(pa.level or 1, pa.rare, a)] or 0 -- petTier's 1st return value = tier name
			local rb = rank[petTier(pb.level or 1, pb.rare, b)] or 0
			if ra ~= rb then return ra > rb end                       -- higher tier first (Mythical leads)
			return (pa.level or 0) > (pb.level or 0)                  -- same tier: higher level first
		end)
		for _, petId in ipairs(ids) do
			ownedCount = ownedCount + 1; order = order + 1
			local okc, ec = pcall(buildPetCard, petId, owned[petId], order) -- per-card: a bad icon can't abort the rest
			if not okc then warn("[PetInv] card build failed for " .. tostring(petId) .. ": " .. tostring(ec)) end
		end
		-- ONLY owned pets are shown (NO empty/locked placeholder slots). When the player owns zero, a
		-- "No Pets Unlocked" message is shown instead. This message Frame is a child of petsScroll, so the
		-- clear loop above auto-destroys it on the next rebuild (no accumulation, no module-scope local).
		if ownedCount == 0 then
			local em = Instance.new("Frame"); em.Name = "PetsEmpty"; em.Size = UDim2.new(1,-20,0,90); em.Position = UDim2.new(0,10,0,8); em.BackgroundTransparency = 1; em.Parent = petsScroll
			local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 20; lbl.TextWrapped = true; lbl.TextColor3 = Color3.fromRGB(190,210,255); lbl.Text = "No Pets Unlocked\nComplete pet quests on the islands to hatch your first pet!"; lbl.Parent = em
		end
		petsScroll.CanvasSize = UDim2.new(0,0,0, math.ceil(ownedCount / 2) * 264 + 20) -- 2 BIG cards/row (252+12) + top padding; only owned cards (no empty slots)
		-- QUESTS section: discovered quests
		for _, c in ipairs(questsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		local qCount = 0
		for _, q in pairs(quests) do qCount = qCount + 1; pcall(buildQuestEntry, q, qCount) end
		questsEmpty.Visible = (qCount == 0)
		questsScroll.CanvasSize = UDim2.new(0,0,0, qCount * 100 + 8)
	end)
	if not ok then warn("[PetInv] ERROR building inventory: " .. tostring(err)) end
end
if PetInventoryEvent then PetInventoryEvent.OnClientEvent:Connect(rebuildInventory) end

-- =====================================================================================================
-- STAGE 3: TRADE UI (housed in the Pet Hub). The client sends INTENTS only; the server owns the trade.
-- =====================================================================================================
local PlayersSvc = game:GetService("Players")
local tradeState = nil -- latest server trade state (active=true while trading)

-- a compact offered-pet row (reuses the tier colors). `onClick` makes it a button (add/remove).
local function makeOfferRow(parent, brief, order, onClick)
	local row = Instance.new(onClick and "TextButton" or "TextLabel"); row.Size = UDim2.new(1,-6,0,26); row.LayoutOrder = order
	row.BackgroundColor3 = Color3.fromRGB(20,70,160); row.Text = ""; row.Parent = parent; uicorner(row, 6)
	if onClick then row.AutoButtonColor = true end
	local tname, tcol = petTier(brief.level, brief.rare, brief.petId)
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-10,1,0); nm.Position = UDim2.new(0,6,0,0); nm.BackgroundTransparency = 1
	nm.Font = Enum.Font.GothamBold; nm.TextSize = 12; nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextColor3 = tcol
	nm.Text = brief.name .. "  (" .. tname .. (brief.rare and "" or ("  Lv" .. tostring(brief.level))) .. ")"; nm.Parent = row
	if onClick then row.MouseButton1Click:Connect(onClick) end
	return row
end

-- an OFFERED-pet CARD with the pet's real 3D PICTURE + name + level + rarity tier (anti-scam: each player
-- can SEE exactly what's being offered). Reuses the same ViewportFrame renderer as the menu icons. `onClick`
-- (your side) makes it a remove button; their side passes nil (read-only).
local function makeOfferCard(parent, brief, order, onClick)
	local card = Instance.new(onClick and "TextButton" or "TextLabel")
	card.Size = UDim2.new(1,-6,0,76); card.LayoutOrder = order
	card.BackgroundColor3 = brief.rare and Color3.fromRGB(46,28,86) or Color3.fromRGB(20,70,160)
	card.Text = ""; if onClick then card.AutoButtonColor = true end; card.Parent = parent; uicorner(card, 8)
	local tname, tcol, isVariant = petTier(brief.level, brief.rare, brief.petId)
	uistroke(card, isVariant and tcol or Color3.fromRGB(10,40,100), isVariant and 2 or 1)
	makeViewportIcon(card, brief.petId, brief.level, brief.rare, UDim2.new(0,96,0,68), UDim2.new(0,4,0,4), Vector2.new(0,0))
	local nm = Instance.new("TextLabel"); nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 14
	nm.TextColor3 = isVariant and tcol or Color3.new(1,1,1); nm.TextXAlignment = Enum.TextXAlignment.Left
	nm.Position = UDim2.new(0,108,0,8); nm.Size = UDim2.new(1,-114,0,20); nm.Text = brief.name; nm.Parent = card
	local lv = Instance.new("TextLabel"); lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold; lv.TextSize = 12
	lv.TextColor3 = tcol; lv.TextXAlignment = Enum.TextXAlignment.Left
	lv.Position = UDim2.new(0,108,0,32); lv.Size = UDim2.new(1,-114,0,18)
	lv.Text = isVariant and tname or (tname .. "  Lv " .. tostring(brief.level)); lv.Parent = card
	if onClick then
		local h = Instance.new("TextLabel"); h.BackgroundTransparency = 1; h.Font = Enum.Font.Gotham; h.TextSize = 11; h.TextColor3 = Color3.fromRGB(255,190,190)
		h.TextXAlignment = Enum.TextXAlignment.Left; h.Position = UDim2.new(0,108,0,52); h.Size = UDim2.new(1,-114,0,16); h.Text = "Click to remove \xE2\x9C\x95"; h.Parent = card
		card.MouseButton1Click:Connect(onClick)
	end
	return card
end

-- TRADE button in the Pet Hub header
local tradeBtn = Instance.new("TextButton"); tradeBtn.Size = UDim2.new(0,96,0,34); tradeBtn.Position = UDim2.new(1,-150,0,13)
tradeBtn.BackgroundColor3 = Color3.fromRGB(80,160,255); tradeBtn.Font = Enum.Font.GothamBold; tradeBtn.TextSize = 14; tradeBtn.TextColor3 = Color3.new(1,1,1)
tradeBtn.Text = "\xF0\x9F\x94\x81 TRADE"; tradeBtn.Parent = header; uicorner(tradeBtn, 8); uistroke(tradeBtn, Color3.new(0,0,0), 2)

-- TRADE OVERLAY (covers the panel body)
local tradeOverlay = Instance.new("Frame"); tradeOverlay.Name = "TradeOverlay"; tradeOverlay.Size = UDim2.new(1,-24,1,-74); tradeOverlay.Position = UDim2.new(0,12,0,68)
tradeOverlay.BackgroundColor3 = Color3.fromRGB(16,60,140); tradeOverlay.Visible = false; tradeOverlay.Parent = panel; uicorner(tradeOverlay, 12); uistroke(tradeOverlay, Color3.fromRGB(10,40,100), 2)
local ovTitle = Instance.new("TextLabel"); ovTitle.Size = UDim2.new(1,-120,0,28); ovTitle.Position = UDim2.new(0,12,0,8); ovTitle.BackgroundTransparency = 1
ovTitle.Font = Enum.Font.GothamBold; ovTitle.TextSize = 18; ovTitle.TextColor3 = Color3.fromRGB(255,215,0); ovTitle.TextXAlignment = Enum.TextXAlignment.Left; ovTitle.Text = "Trade"; ovTitle.Parent = tradeOverlay
local ovBack = Instance.new("TextButton"); ovBack.Size = UDim2.new(0,100,0,28); ovBack.Position = UDim2.new(1,-108,0,8); ovBack.BackgroundColor3 = Color3.fromRGB(120,120,120)
ovBack.Font = Enum.Font.GothamBold; ovBack.TextSize = 13; ovBack.TextColor3 = Color3.new(1,1,1); ovBack.Text = "\xE2\x97\x80 Pets"; ovBack.Parent = tradeOverlay; uicorner(ovBack, 8)

-- VIEW 1: pick a player to request a trade
local pickerView = Instance.new("Frame"); pickerView.Size = UDim2.new(1,-16,1,-46); pickerView.Position = UDim2.new(0,8,0,42); pickerView.BackgroundTransparency = 1; pickerView.Parent = tradeOverlay
local pickerScroll = Instance.new("ScrollingFrame"); pickerScroll.Size = UDim2.new(1,0,1,0); pickerScroll.BackgroundTransparency = 1; pickerScroll.BorderSizePixel = 0
pickerScroll.ScrollBarThickness = 6; pickerScroll.ScrollBarImageColor3 = Color3.fromRGB(255,215,0); pickerScroll.CanvasSize = UDim2.new(0,0,0,0); pickerScroll.Parent = pickerView
local pickerLayout = Instance.new("UIListLayout"); pickerLayout.Padding = UDim.new(0,6); pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder; pickerLayout.Parent = pickerScroll

-- VIEW 2: the trade window (your side / their side / add list / confirm + cancel)
local windowView = Instance.new("Frame"); windowView.Size = UDim2.new(1,-16,1,-46); windowView.Position = UDim2.new(0,8,0,42); windowView.BackgroundTransparency = 1; windowView.Visible = false; windowView.Parent = tradeOverlay
local function colTitle(text, x) local l = Instance.new("TextLabel"); l.Size = UDim2.new(0,310,0,18); l.Position = UDim2.new(0,x,0,0); l.BackgroundTransparency = 1; l.Font = Enum.Font.GothamBold; l.TextSize = 14; l.TextColor3 = Color3.fromRGB(255,215,0); l.TextXAlignment = Enum.TextXAlignment.Left; l.Text = text; l.Parent = windowView; return l end
local function colScroll(x, y, h) local s = Instance.new("ScrollingFrame"); s.Size = UDim2.new(0,310,0,h); s.Position = UDim2.new(0,x,0,y); s.BackgroundColor3 = Color3.fromRGB(12,44,104); s.BorderSizePixel = 0; s.ScrollBarThickness = 5; s.CanvasSize = UDim2.new(0,0,0,0); s.Parent = windowView; uicorner(s,8); local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0,4); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = s; return s end
colTitle("YOUR OFFER (click to remove)", 0)
local yourOfferScroll = colScroll(0, 20, 150)
local addTitleLbl = colTitle("YOUR PETS (click to add)", 0); addTitleLbl.Position = UDim2.new(0,0,0,176)
local addScroll = colScroll(0, 196, 200)
colTitle("THEIR OFFER", 330)
local theirOfferScroll = colScroll(330, 20, 150)
local statusLbl = Instance.new("TextLabel"); statusLbl.Size = UDim2.new(0,310,0,108); statusLbl.Position = UDim2.new(0,330,0,178); statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.GothamBold; statusLbl.TextSize = 14; statusLbl.TextColor3 = Color3.new(1,1,1); statusLbl.TextWrapped = true; statusLbl.TextYAlignment = Enum.TextYAlignment.Top; statusLbl.Text = ""; statusLbl.Parent = windowView
local cancelBtn = Instance.new("TextButton"); cancelBtn.Size = UDim2.new(0,150,0,34); cancelBtn.Position = UDim2.new(0,330,0,300); cancelBtn.BackgroundColor3 = Color3.fromRGB(220,60,60)
cancelBtn.Font = Enum.Font.GothamBold; cancelBtn.TextSize = 15; cancelBtn.TextColor3 = Color3.new(1,1,1); cancelBtn.Text = "CANCEL"; cancelBtn.Parent = windowView; uicorner(cancelBtn,8); uistroke(cancelBtn, Color3.new(0,0,0),2)
local confirmBtn = Instance.new("TextButton"); confirmBtn.Size = UDim2.new(0,150,0,34); confirmBtn.Position = UDim2.new(0,490,0,300); confirmBtn.BackgroundColor3 = Color3.fromRGB(50,200,50)
confirmBtn.Font = Enum.Font.GothamBold; confirmBtn.TextSize = 15; confirmBtn.TextColor3 = Color3.new(1,1,1); confirmBtn.Text = "CONFIRM"; confirmBtn.Parent = windowView; uicorner(confirmBtn,8); uistroke(confirmBtn, Color3.new(0,0,0),2)

local function clearScroll(s) for _, c in ipairs(s:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end end
local function refreshPicker()
	clearScroll(pickerScroll)
	local order, n = 0, 0
	for _, pl in ipairs(PlayersSvc:GetPlayers()) do
		if pl ~= player then
			n = n + 1; order = order + 1
			local row = Instance.new("Frame"); row.Size = UDim2.new(1,-6,0,30); row.LayoutOrder = order; row.BackgroundColor3 = Color3.fromRGB(20,70,160); row.Parent = pickerScroll; uicorner(row,6)
			local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-94,1,0); nm.Position = UDim2.new(0,8,0,0); nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 13; nm.TextColor3 = Color3.new(1,1,1); nm.TextXAlignment = Enum.TextXAlignment.Left; nm.Text = pl.DisplayName .. " (@" .. pl.Name .. ")"; nm.Parent = row
			local req = Instance.new("TextButton"); req.Size = UDim2.new(0,82,0,24); req.Position = UDim2.new(1,-86,0,3); req.BackgroundColor3 = Color3.fromRGB(50,200,50); req.Font = Enum.Font.GothamBold; req.TextSize = 12; req.TextColor3 = Color3.new(1,1,1); req.Text = "REQUEST"; req.Parent = row; uicorner(req,6)
			local uid = pl.UserId
			req.MouseButton1Click:Connect(function() pcall(function() PetTradeRequest:FireServer(uid) end); ovTitle.Text = "Request sent to " .. pl.DisplayName .. "..." end)
		end
	end
	if n == 0 then
		local e = Instance.new("TextLabel"); e.Size = UDim2.new(1,-6,0,40); e.BackgroundTransparency = 1; e.Font = Enum.Font.Gotham; e.TextSize = 13; e.TextColor3 = Color3.fromRGB(200,220,255); e.TextWrapped = true; e.Text = "No other players in the server to trade with."; e.Parent = pickerScroll
	end
	pickerScroll.CanvasSize = UDim2.new(0,0,0, n*36 + 8)
end
local function showPicker() pickerView.Visible = true; windowView.Visible = false; ovTitle.Text = "Trade \xE2\x80\x94 pick a player"; refreshPicker() end
local function renderTradeWindow(state)
	pickerView.Visible = false; windowView.Visible = true; ovTitle.Text = "Trading with " .. tostring(state.withName)
	clearScroll(yourOfferScroll); for i, b in ipairs(state.mine or {}) do makeOfferCard(yourOfferScroll, b, i, function() pcall(function() PetTradeOffer:FireServer(b.petId, false) end) end) end
	yourOfferScroll.CanvasSize = UDim2.new(0,0,0, #(state.mine or {}) * 80 + 4)
	clearScroll(theirOfferScroll); for i, b in ipairs(state.theirs or {}) do makeOfferCard(theirOfferScroll, b, i, nil) end
	theirOfferScroll.CanvasSize = UDim2.new(0,0,0, #(state.theirs or {}) * 80 + 4)
	local offered = {}; for _, b in ipairs(state.mine or {}) do offered[b.petId] = true end
	clearScroll(addScroll); local idx = 0
	for petId, p in pairs(latestInv.owned or {}) do
		if not offered[petId] then idx = idx + 1
			makeOfferRow(addScroll, { petId = petId, name = (p.rare and p.rareName) or p.displayName, level = p.level, rare = p.rare }, idx, function() pcall(function() PetTradeOffer:FireServer(petId, true) end) end)
		end
	end
	addScroll.CanvasSize = UDim2.new(0,0,0, idx * 30 + 4)
	local st = state.status
	statusLbl.Text = (st=="trading" and "\xE2\x9C\xA8 Both confirmed - trading!") or (st=="waiting_them" and ("You confirmed.\nWaiting for " .. state.withName .. "...")) or (st=="waiting_you" and (state.withName .. " confirmed.\nYour move!")) or "Add pets, then both CONFIRM.\n(changing an offer resets both confirms)"
	confirmBtn.Text = state.myConfirm and "\xE2\x9C\x94 CONFIRMED" or "CONFIRM"
	confirmBtn.BackgroundColor3 = state.myConfirm and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50)
end
ovBack.MouseButton1Click:Connect(function() tradeOverlay.Visible = false end) -- back to pet cards (trade stays live; reopen via TRADE)
cancelBtn.MouseButton1Click:Connect(function() pcall(function() PetTradeCancel:FireServer() end) end)
confirmBtn.MouseButton1Click:Connect(function() pcall(function() PetTradeConfirm:FireServer() end) end)
tradeBtn.MouseButton1Click:Connect(function()
	questsOverlay.Visible = false -- TRADE + QUESTS overlays are mutually exclusive over the pet grid
	if tradeState and tradeState.active then tradeOverlay.Visible = true; renderTradeWindow(tradeState)
	else tradeOverlay.Visible = not tradeOverlay.Visible; if tradeOverlay.Visible then showPicker() end end
end)

-- QUESTS tab in the header -> opens the tucked-away discovered-quests overlay (the quest info lives here now,
-- off the main pet grid). Mutually exclusive with the TRADE overlay.
local questsBtn = Instance.new("TextButton"); questsBtn.Size = UDim2.new(0,96,0,34); questsBtn.Position = UDim2.new(1,-252,0,13)
questsBtn.BackgroundColor3 = Color3.fromRGB(120,170,60); questsBtn.Font = Enum.Font.GothamBold; questsBtn.TextSize = 14; questsBtn.TextColor3 = Color3.new(1,1,1)
questsBtn.Text = "\xF0\x9F\x97\xBA QUESTS"; questsBtn.Parent = header; uicorner(questsBtn, 8); uistroke(questsBtn, Color3.new(0,0,0), 2)
questsBtn.MouseButton1Click:Connect(function() tradeOverlay.Visible = false; questsOverlay.Visible = not questsOverlay.Visible end)
qoBack.MouseButton1Click:Connect(function() questsOverlay.Visible = false end)

-- live trade state from the server
if PetTradeState then PetTradeState.OnClientEvent:Connect(function(state)
	tradeState = state
	if state and state.active then
		openPanel(true); tradeOverlay.Visible = true; renderTradeWindow(state) -- ensure the Hub is open so both players see the trade window
	else
		local reason = state and state.reason
		print("[Trade] window closed (" .. tostring(reason) .. ")")
		tradeState = nil
		if tradeOverlay.Visible then ovTitle.Text = "Trade " .. (reason and ("\xE2\x80\x94 " .. reason) or "closed"); showPicker() end
	end
end) end

-- incoming-request popup (shows even if the Hub is closed)
local reqPopup = Instance.new("Frame"); reqPopup.Name = "TradeRequestPopup"; reqPopup.AnchorPoint = Vector2.new(0.5,0.5); reqPopup.Position = UDim2.new(0.5,0,0.4,0); reqPopup.Size = UDim2.new(0,320,0,130)
reqPopup.BackgroundColor3 = Color3.fromRGB(25,90,185); reqPopup.Visible = false; reqPopup.ZIndex = 50; reqPopup.Parent = invGui; uicorner(reqPopup, 12); uistroke(reqPopup, Color3.fromRGB(255,215,0), 3)
local reqLbl = Instance.new("TextLabel"); reqLbl.Size = UDim2.new(1,-20,0,60); reqLbl.Position = UDim2.new(0,10,0,10); reqLbl.BackgroundTransparency = 1; reqLbl.ZIndex = 51; reqLbl.Font = Enum.Font.GothamBold; reqLbl.TextSize = 16; reqLbl.TextColor3 = Color3.new(1,1,1); reqLbl.TextWrapped = true; reqLbl.Text = ""; reqLbl.Parent = reqPopup
local reqAccept = Instance.new("TextButton"); reqAccept.Size = UDim2.new(0,140,0,38); reqAccept.Position = UDim2.new(0,12,1,-46); reqAccept.BackgroundColor3 = Color3.fromRGB(50,200,50); reqAccept.ZIndex = 51; reqAccept.Font = Enum.Font.GothamBold; reqAccept.TextSize = 15; reqAccept.TextColor3 = Color3.new(1,1,1); reqAccept.Text = "ACCEPT"; reqAccept.Parent = reqPopup; uicorner(reqAccept,8)
local reqDecline = Instance.new("TextButton"); reqDecline.Size = UDim2.new(0,140,0,38); reqDecline.Position = UDim2.new(1,-152,1,-46); reqDecline.BackgroundColor3 = Color3.fromRGB(220,60,60); reqDecline.ZIndex = 51; reqDecline.Font = Enum.Font.GothamBold; reqDecline.TextSize = 15; reqDecline.TextColor3 = Color3.new(1,1,1); reqDecline.Text = "DECLINE"; reqDecline.Parent = reqPopup; uicorner(reqDecline,8)
reqAccept.MouseButton1Click:Connect(function() reqPopup.Visible = false; pcall(function() PetTradeRespond:FireServer(true) end) end)
reqDecline.MouseButton1Click:Connect(function() reqPopup.Visible = false; pcall(function() PetTradeRespond:FireServer(false) end) end)
if PetTradePrompt then PetTradePrompt.OnClientEvent:Connect(function(fromUserId, fromName)
	reqLbl.Text = "\xF0\x9F\x94\x81 " .. tostring(fromName) .. " wants to trade pets with you!"
	reqPopup.Visible = true
	task.delay(15, function() if reqPopup.Visible then reqPopup.Visible = false end end) -- auto-dismiss if ignored
end) end

-- FLIGHT-ACHIEVEMENT progress: while a pet is EQUIPPED, report peak height (the flight system's _G.peakHeight
-- / live Y) + airtime to the server, which accrues it on that pet and gates the next level. READ-ONLY of the
-- flight stats -- never modifies flight/gas/coins. Cosmetic-only.
task.spawn(function()
	local TICK = 3
	while true do
		task.wait(TICK)
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if equippedPetId and hrp then
			local peak = math.max(hrp.Position.Y, _G.peakHeight or 0)
			pcall(function() PetProgressEvent:FireServer(equippedPetId, peak, TICK) end)
		end
	end
end)
