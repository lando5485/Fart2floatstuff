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
local player      = Players.LocalPlayer

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
		questHint    = "Pet Quest Available on this island...",      -- the mysterious landing hint
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
		questHint    = "Pet Quest Available on this island...",
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
		questHint    = "Pet Quest Available on this island...",
		allFoundMsg  = "All 6 found! Load reels at the projector!",  -- tracker text at full count (data-driven)
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
		questHint    = "Pet Quest Available on this island...",
		allFoundMsg  = "Fish in the butter to catch the egg!",
	},
}

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
-- ⚠ REPLACE WITH REAL DEV PRODUCT ID (must match PET_UPGRADE_PRODUCT_ID in PetSystem.server.lua). While 0
-- the Robux upgrade button is a stub (the purchase prompt won't open).
local PET_UPGRADE_PRODUCT_ID = 0

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
			if n == "Leg" or n == "ToeClaw" then role = "leg"      -- chunky legs + their toe-claws do the gait
			elseif n == "Tail" or n == "TailSpike" then role = "tail" -- tail + ridge spikes wiggle
			elseif n == "Eye" or n == "Highlight" then eye = true end -- ride the rigid body, but blink
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

-- REEL-IN minigame: a vertical TENSION bar. HOLD (anywhere) to raise a green "reel zone"; it falls when you
-- release. A fish marker drifts up/down. Keep the fish INSIDE the zone to FILL the catch meter; let it slip out
-- and the meter drains. Fill it -> reeled in. Empty -> it escapes. DISTINCT from the coconut tap-fill + the
-- popcorn stop-the-marker. Tuned EASY + mobile-friendly (press/hold). onDone(success) when finished.
local reelUI, reelBusy = nil, false
local function ensureReelUI()
	if reelUI then return reelUI end
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "ButterReelGui"; g.ResetOnSpawn = false; g.DisplayOrder = 90; g.Enabled = false; g.Parent = pgui
	local film = Instance.new("Frame"); film.Size = UDim2.new(1,0,1,0); film.BackgroundColor3 = Color3.new(0,0,0); film.BackgroundTransparency = 0.5; film.Active = true; film.Parent = g
	local panel = Instance.new("Frame"); panel.Size = UDim2.new(0,360,0,300); panel.Position = UDim2.new(0.5,0,0.5,0); panel.AnchorPoint = Vector2.new(0.5,0.5)
	panel.BackgroundColor3 = Color3.fromRGB(25,90,185); panel.Parent = g
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16); local ps = Instance.new("UIStroke", panel); ps.Color = Color3.new(1,1,1); ps.Thickness = 3
	local titl = Instance.new("TextLabel"); titl.Size = UDim2.new(1,-20,0,30); titl.Position = UDim2.new(0,10,0,10); titl.BackgroundTransparency = 1
	titl.Font = Enum.Font.GothamBold; titl.TextSize = 22; titl.TextColor3 = Color3.fromRGB(255,215,0); titl.Text = "REEL IT IN!"; titl.Parent = panel
	local hintL = Instance.new("TextLabel"); hintL.Size = UDim2.new(1,-20,0,18); hintL.Position = UDim2.new(0,10,0,42); hintL.BackgroundTransparency = 1
	hintL.Font = Enum.Font.Gotham; hintL.TextSize = 13; hintL.TextColor3 = Color3.new(1,1,1); hintL.Text = "HOLD to reel up - keep the fish in the green zone!"; hintL.Parent = panel
	-- the vertical TRACK (left) with the moving green ZONE + the drifting FISH
	local track = Instance.new("Frame"); track.Size = UDim2.new(0,70,0,196); track.Position = UDim2.new(0,40,0,76)
	track.BackgroundColor3 = Color3.fromRGB(12,34,76); track.Parent = panel; Instance.new("UICorner", track).CornerRadius = UDim.new(0,10)
	local zone = Instance.new("Frame"); zone.Size = UDim2.new(1,-8,0.26,0); zone.Position = UDim2.new(0.5,0,0.5,0); zone.AnchorPoint = Vector2.new(0.5,0.5)
	zone.BackgroundColor3 = Color3.fromRGB(70,210,90); zone.BackgroundTransparency = 0.25; zone.BorderSizePixel = 0; zone.Parent = track; Instance.new("UICorner", zone).CornerRadius = UDim.new(0,6)
	local fish = Instance.new("TextLabel"); fish.Size = UDim2.new(0,40,0,40); fish.AnchorPoint = Vector2.new(0.5,0.5); fish.Position = UDim2.new(0.5,0,0.5,0)
	fish.BackgroundTransparency = 1; fish.Font = Enum.Font.GothamBold; fish.TextSize = 30; fish.Text = "\xF0\x9F\x90\x9F"; fish.ZIndex = 3; fish.Parent = track
	-- the catch PROGRESS meter (right), fills bottom-up
	local pbBg = Instance.new("Frame"); pbBg.Size = UDim2.new(0,34,0,196); pbBg.Position = UDim2.new(1,-58,0,76)
	pbBg.BackgroundColor3 = Color3.fromRGB(15,40,90); pbBg.Parent = panel; Instance.new("UICorner", pbBg).CornerRadius = UDim.new(0,8)
	local pb = Instance.new("Frame"); pb.Size = UDim2.new(1,0,0.4,0); pb.Position = UDim2.new(0,0,1,0); pb.AnchorPoint = Vector2.new(0,1)
	pb.BackgroundColor3 = Color3.fromRGB(255,205,60); pb.BorderSizePixel = 0; pb.Parent = pbBg; Instance.new("UICorner", pb).CornerRadius = UDim.new(0,8)
	local pbl = Instance.new("TextLabel"); pbl.Size = UDim2.new(0,80,0,16); pbl.Position = UDim2.new(1,-86,0,276-18); pbl.BackgroundTransparency = 1
	pbl.Font = Enum.Font.GothamBold; pbl.TextSize = 12; pbl.TextColor3 = Color3.fromRGB(255,225,120); pbl.Text = "CATCH"; pbl.Parent = panel
	reelUI = { gui = g, zone = zone, fish = fish, pb = pb, hint = hintL }
	return reelUI
end
local function openReelMinigame(onDone)
	if reelBusy then if onDone then onDone(false) end return end
	reelBusy = true
	local UIS = game:GetService("UserInputService")
	local ui = ensureReelUI()
	local ZONE_H = 0.26          -- zone half-handled below; this is the zone's fractional height
	local zone, zoneVel = 0.45, 0
	local fishF, fishTarget, fishTimer = 0.5, 0.5, 0
	local progress = 0.42        -- start partway so it isn't an instant win/lose
	ui.zone.Size = UDim2.new(1,-8,ZONE_H,0)
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
		local last = os.clock()
		while not done do
			local now = os.clock(); local dt = math.min(now - last, 0.05); last = now
			-- ZONE physics: hold pushes up, gravity pulls down, light damping
			zoneVel = (zoneVel + (holding and 2.3 or -1.15) * dt) * 0.90
			zone = zone + zoneVel * dt
			if zone < ZONE_H/2 then zone = ZONE_H/2; zoneVel = 0 elseif zone > 1 - ZONE_H/2 then zone = 1 - ZONE_H/2; zoneVel = 0 end
			-- FISH drift toward a slowly-changing target (gentle = easy)
			fishTimer = fishTimer - dt
			if fishTimer <= 0 then fishTarget = 0.12 + math.random() * 0.76; fishTimer = 0.5 + math.random() * 1.3 end
			fishF = fishF + (fishTarget - fishF) * math.min(dt * 1.7, 1)
			-- PROGRESS: fill if the fish is inside the zone, drain (slower = forgiving) if it slips out
			local inZone = math.abs(fishF - zone) <= (ZONE_H/2)
			progress = math.clamp(progress + (inZone and 0.42 or -0.26) * dt, 0, 1)
			-- visuals (f=1 is the TOP of the track)
			ui.zone.Position = UDim2.new(0.5, 0, 1 - zone, 0)
			ui.zone.BackgroundColor3 = inZone and Color3.fromRGB(70,225,95) or Color3.fromRGB(70,150,90)
			ui.fish.Position = UDim2.new(0.5, 0, 1 - fishF, 0)
			ui.pb.Size = UDim2.new(1, 0, progress, 0)
			ui.pb.BackgroundColor3 = (progress > 0.5) and Color3.fromRGB(120,235,110) or Color3.fromRGB(255,205,60)
			if progress >= 1 then finish(true); break elseif progress <= 0 then finish(false); break end
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

	-- ===== ROD BARREL (client-built prop at the captured position) + "Grab Fishing Rod" prompt =====
	if typeof(barrelPos) == "Vector3" then
		local barrel = Instance.new("Model"); barrel.Name = petId.."RodBarrel"
		local body = newPart(barrel, "Barrel", Enum.PartType.Cylinder, Vector3.new(3.2,2.4,2.4), Color3.fromRGB(120,80,42), CFrame.new(barrelPos + Vector3.new(0,1.6,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Wood)
		barrel.PrimaryPart = body
		for _, oy in ipairs({0.7, 1.6, 2.5}) do newPart(barrel, "Hoop", Enum.PartType.Cylinder, Vector3.new(3.3,2.6,2.6), Color3.fromRGB(70,70,80), CFrame.new(barrelPos + Vector3.new(0,oy,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Metal) end
		-- a fishing rod sticking out of the barrel
		newPart(barrel, "Rod", Enum.PartType.Cylinder, Vector3.new(7,0.2,0.2), Color3.fromRGB(110,70,40), CFrame.new(barrelPos + Vector3.new(1.2,4.2,0)) * CFrame.Angles(0,0,math.rad(60)), Enum.Material.Wood)
		newPart(barrel, "Reel", Enum.PartType.Cylinder, Vector3.new(0.5,0.9,0.9), Color3.fromRGB(40,40,46), CFrame.new(barrelPos + Vector3.new(0.2,3.0,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Metal)
		barrel.Parent = Workspace
		st.fishProps[#st.fishProps+1] = barrel
		local grab = addPrompt(body, "Grab Fishing Rod", "Rod Barrel", function()
			if st.owns then return end
			if not st.hasRod then
				st.hasRod = true
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

	-- ===== proximity to the butter (within the lake's bounding box + a margin, near its surface) =====
	local function isNearButter()
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false end
		local hx = (typeof(lakeSize) == "Vector3") and lakeSize.X/2 + 16 or 60
		local hz = (typeof(lakeSize) == "Vector3") and lakeSize.Z/2 + 16 or 60
		local dy = (typeof(lakeSize) == "Vector3") and lakeSize.Y/2 + 32 or 40
		return math.abs(hrp.Position.X - lakePos.X) <= hx and math.abs(hrp.Position.Z - lakePos.Z) <= hz and math.abs(hrp.Position.Y - lakePos.Y) <= dy
	end

	-- ===== the FISH prompt (an invisible anchor over the lake) =====
	local fishAnchor = newPart(Workspace, petId.."FishSpot", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.new(1,1,1), CFrame.new(lakePos + Vector3.new(0, (typeof(lakeSize)=="Vector3" and lakeSize.Y/2 or 0) + 2, 0)))
	fishAnchor.Transparency = 1
	st.fishProps[#st.fishProps+1] = fishAnchor
	local fishing = false
	local fishPrompt -- forward-declared so the closure below captures THIS local (not a nil global)
	fishPrompt = addPrompt(fishAnchor, "Fish", "Butter Lake", function()
		if st.owns or st.eggCaught or fishing then return end
		if not st.hasRod then floatText((player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or lakePos) + Vector3.new(0,3,0), "Grab a rod from the barrel first!"); return end
		if not isNearButter() then floatText(lakePos + Vector3.new(0,3,0), "Get closer to the butter to fish!"); return end
		fishing = true; fishPrompt.Enabled = false
		task.spawn(function()
			local TS = game:GetService("TweenService")
			local keepGoing = true
			-- STOP when the player owns it OR wanders away from the butter. Without the isNearButter() gate the
			-- loop recast FOREVER and left the blue "status" HUD bar stuck on screen (the stray blue line).
			while keepGoing and not st.owns and isNearButter() do
				-- STEP 1: CAST -- a bobber arcs from the player into the butter
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local hx = (typeof(lakeSize)=="Vector3") and math.clamp((hrp and hrp.Position.X or lakePos.X), lakePos.X - lakeSize.X/2 + 5, lakePos.X + lakeSize.X/2 - 5) or lakePos.X
				local hz = (typeof(lakeSize)=="Vector3") and math.clamp((hrp and hrp.Position.Z or lakePos.Z), lakePos.Z - lakeSize.Z/2 + 5, lakePos.Z + lakeSize.Z/2 - 5) or lakePos.Z
				local target = Vector3.new(hx, surfaceY + 0.4, hz)
				local toC = Vector3.new(lakePos.X - hx, 0, lakePos.Z - hz); if toC.Magnitude > 1 then target = target + toC.Unit * math.min(8, toC.Magnitude*0.4) end
				local startP = hrp and (hrp.Position + Vector3.new(0,1.5,0)) or target
				local bob = newPart(Workspace, petId.."Bobber", Enum.PartType.Ball, Vector3.new(0.85,0.85,0.85), Color3.fromRGB(230,60,60), CFrame.new(startP))
				local nv = Instance.new("NumberValue"); nv.Value = 0; nv.Parent = bob
				nv:GetPropertyChangedSignal("Value"):Connect(function() local t = nv.Value; bob.CFrame = CFrame.new(startP:Lerp(target, t) + Vector3.new(0, math.sin(t*math.pi)*6, 0)) end)
				TS:Create(nv, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {Value = 1}):Play()
				print("[Pet] "..player.Name.." cast"); setStatus("Waiting for a bite...")
				task.wait(0.65 + 1 + math.random() * 3) -- cast settle + random 1-4s until a bite
				if st.owns or not isNearButter() then pcall(function() bob:Destroy() end) break end -- walked away (or owns) -> stop; loop-end hides the status
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
						-- STEP 4: SERVER rolls the catch (pity) -- the client NEVER decides
						local ok, res = pcall(function() return PetFishRoll:InvokeServer() end)
						if ok and type(res) == "table" and res.egg then
							setStatus("You reeled in... an EGG! \xF0\x9F\xA5\x9A"); keepGoing = false
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
	fishPrompt.MaxActivationDistance = (typeof(lakeSize) == "Vector3") and math.clamp(math.max(lakeSize.X, lakeSize.Z)/2 + 24, 30, 160) or 90
	fishPrompt.HoldDuration = 0
	print(string.format("[Pet][DIAG] butter fishing ready: lake=(%.0f,%.0f,%.0f) size=%s", lakePos.X, lakePos.Y, lakePos.Z, (typeof(lakeSize)=="Vector3") and string.format("(%.0f,%.0f,%.0f)", lakeSize.X, lakeSize.Y, lakeSize.Z) or "?"))

	-- avoid a flash of the props for someone who already OWNS the duck
	if st.owns then for _, o in ipairs(st.fishProps) do setVisible(o, false) end end
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
local FOLLOW_K      = 12   -- responsiveness (higher = tighter follow)
local MAX_TRAIL     = 45   -- never let the pet fall further than this behind -> can't be lost in a fast ascent
local petSmoothPos  = nil  -- smoothed follow position (no bob)
local bobT          = 0

-- STUB per-level visual (cosmetic -- refine real per-level looks next build): a level-tinted glow outline
-- + a "Lv N" billboard above the pet. Lv1 = plain. This is the visual payoff stub; the framework is real.
local function applyLevelVisual(pet, level)
	if not pet then return end
	local glow = pet:FindFirstChild("LevelGlow"); if glow then glow:Destroy() end
	if level and level >= 2 then
		local hl = Instance.new("Highlight"); hl.Name = "LevelGlow"; hl.FillTransparency = 1
		hl.OutlineColor = (level >= 3) and Color3.fromRGB(255,215,0) or Color3.fromRGB(120,220,255)
		hl.OutlineTransparency = 0.1; hl.Adornee = pet; hl.Parent = pet
	end
	local root = pet.PrimaryPart
	if root then
		local bb = root:FindFirstChild("LevelTag")
		if not bb then
			bb = Instance.new("BillboardGui"); bb.Name = "LevelTag"; bb.Size = UDim2.new(0,64,0,24)
			bb.StudsOffset = Vector3.new(0,3.4,0); bb.AlwaysOnTop = true; bb.Parent = root
			local lbl = Instance.new("TextLabel"); lbl.Name = "L"; lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1
			lbl.Font = Enum.Font.FredokaOne; lbl.TextSize = 18; lbl.TextColor3 = Color3.fromRGB(255,255,255); lbl.Parent = bb
			Instance.new("UIStroke").Parent = lbl
		end
		bb.L.Text = "Lv " .. tostring(level or 1)
	end
end

local function spawnFollowerPet(petId)
	local st = petState[petId]
	if st.pet then -- already following: just refresh the level visual if it changed (e.g. after an upgrade)
		if st.appliedLevel ~= st.level then st.appliedLevel = st.level; applyLevelVisual(st.pet, st.level or 1) end
		return
	end
	-- pick the builder by pet (modular): CoconutCrab + PopcornSheep + ButterDuck are client-built; BroccoliPet clones the server union template
	if petId == "CoconutCrab" then st.pet = buildCoconutCrab(0.9)
	elseif petId == "PopcornSheep" then st.pet = buildPopcornSheep(0.9)
	elseif petId == "ButterDuck" then st.pet = buildButterDuck(0.9)
	else st.pet = buildBroccoliDino(0.9) end
	st.pet.Name = petId
	st.pet.Parent = Workspace
	st.appliedLevel = st.level
	applyLevelVisual(st.pet, st.level or 1)
	print("[Pet][DIAG] pet spawned, following player ("..petId..") at Lv "..tostring(st.level or 1))
end

-- Despawn the follower (used when a pet is UNEQUIPPED). Cosmetic-only.
local function despawnFollowerPet(petId)
	local st = petState[petId]
	if st and st.pet then
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
	-- GLOBAL (local frame: +X = front): slow breathing bob (idle) + bounce (moving) + a forward lean.
	-- Lean = pitch the front (+X) down -> rotate about the lateral Z axis, pivoted at the body centre.
	-- IDLE: gentle float bob. MOVING: a soft cute BOUNCE (abs-sine, modest amplitude -- bouncy, not jarring).
	local bobY = math.sin(t * 1.7) * 0.05 * s + math.abs(math.sin(t * (6 + 3 * mv))) * 0.20 * s * mv
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
		else
			localCF = globalT * bp
		end
		e.part.CFrame = rootCF * localCF
		if e.eye then -- blink squash: shrink the eye block vertically (Part.Size.Y)
			e.part.Size = Vector3.new(e.baseSize.X, e.baseSize.Y * eyeY, e.baseSize.Z)
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
				-- frame-rate-independent smoothing
				local alpha = 1 - math.exp(-FOLLOW_K * dt)
				petSmoothPos = petSmoothPos:Lerp(targetPos, alpha)
				-- clamp the trail so a very fast fart-ascent never strands the pet
				local back = petSmoothPos - targetPos
				if back.Magnitude > MAX_TRAIL then petSmoothPos = targetPos + back.Unit * MAX_TRAIL end
				-- small ambient float (the lively bob/breath/lean is added by animatePet) + face travel dir
				bobT = bobT + dt
				local renderPos = petSmoothPos + Vector3.new(0, math.sin(bobT * 3) * 0.12, 0)
				local fwd = hrp.CFrame.LookVector
				fwd = Vector3.new(fwd.X, 0, fwd.Z)
				if fwd.Magnitude < 0.05 then fwd = Vector3.new(0, 0, -1) end
				-- the model is built with +X = front, so yaw the look-at +90 deg to point its +X along travel
				pet:PivotTo(CFrame.lookAt(renderPos, renderPos + fwd.Unit) * CFrame.Angles(0, math.rad(90), 0))
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

-- (2b) CORNER TRACKER: top-right, persistent
local tracker = Instance.new("Frame")
tracker.Name="Tracker"; tracker.AnchorPoint=Vector2.new(1,0); tracker.Position=UDim2.new(1,-14,0,14); tracker.Size=UDim2.new(0,190,0,40)
tracker.BackgroundColor3=Color3.fromRGB(28,52,28); tracker.BackgroundTransparency=0.12; tracker.Visible=false; tracker.Parent=questGui
uiCorner(tracker, 10); uiStroke(tracker, 2, Color3.fromRGB(120,220,120))
local trkIcon = Instance.new("TextLabel"); trkIcon.BackgroundTransparency=1; trkIcon.Font=Enum.Font.Gotham; trkIcon.TextSize=22; trkIcon.Size=UDim2.new(0,32,1,0); trkIcon.Position=UDim2.new(0,6,0,0); trkIcon.Text=""; trkIcon.Parent=tracker
local trkLabel = Instance.new("TextLabel"); trkLabel.BackgroundTransparency=1; trkLabel.Font=Enum.Font.FredokaOne; trkLabel.TextSize=18; trkLabel.TextColor3=Color3.fromRGB(255,255,255); trkLabel.Size=UDim2.new(1,-42,1,0); trkLabel.Position=UDim2.new(0,38,0,0); trkLabel.TextXAlignment=Enum.TextXAlignment.Left; trkLabel.Text=""; trkLabel.Parent=tracker; uiStroke(trkLabel,2)

-- (3) POINTER: on-screen arrow guiding to the egg (shown at 3/3)
local pointer = Instance.new("TextLabel")
pointer.Name="Pointer"; pointer.AnchorPoint=Vector2.new(0.5,0.5); pointer.Size=UDim2.new(0,60,0,60)
pointer.BackgroundTransparency=1; pointer.Font=Enum.Font.GothamBold; pointer.TextSize=46; pointer.TextColor3=Color3.fromRGB(150,255,140); pointer.Text="\xE2\x9E\xA4"; pointer.Visible=false; pointer.Parent=questGui; uiStroke(pointer,2)

local activeUiPet = nil -- petId currently driving the tracker/pointer
local onIsland = {}     -- [petId] = bool (for the once-per-visit landing hint)

local function flashHint(def)
	-- SHORT on-landing popup that points the player to the Pet Inventory (replaces the old per-island hint)
	hint.Text = "\xF0\x9F\x90\xBe Pet Quest Available! See more in Pet Inventory"
	hint.TextTransparency = 1; hintStroke.Transparency = 1
	TweenService:Create(hint, TweenInfo.new(0.6), {TextTransparency=0}):Play()
	TweenService:Create(hintStroke, TweenInfo.new(0.6), {Transparency=0}):Play()
	task.delay(3.0, function()
		TweenService:Create(hint, TweenInfo.new(1.0), {TextTransparency=1}):Play()
		TweenService:Create(hintStroke, TweenInfo.new(1.0), {Transparency=1}):Play()
	end)
	print("[Pet][UI] on-landing pet-quest hint shown (points to inventory)")
end

local function setTracker(def, found, total)
	trkIcon.Text = def.iconEmoji or "\xF0\x9F\x90\xBE"
	if found >= total then
		trkLabel.Text = def.allFoundMsg or "All found! Find the egg!"; trkLabel.TextColor3 = Color3.fromRGB(255,240,130)
	else
		trkLabel.Text = (def.pieceLabel or "Pieces")..": "..found.."/"..total; trkLabel.TextColor3 = Color3.fromRGB(255,255,255)
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
		st.owns = info.owns == true
		st.equipped = info.equipped == true
		st.level = info.level or 1
		if st.equipped then equippedPetId = petId elseif equippedPetId == petId then equippedPetId = nil end
		st.uiFound = info.found
		st.total = info.total
		if st.owns then
			-- owns the pet: hide find-pieces + egg + chest, follow ONLY if equipped, and tear down the quest UI
			for i, piece in pairs(st.pieces) do setVisible(piece, false) end
			setVisible(st.egg, false)
			if st.chest then setVisible(st.chest, false) end
			if st.filmProps then for _, o in ipairs(st.filmProps) do setVisible(o, false) end end -- (empty now: the projector + beam are PERMANENT, never hidden)
			if st.fishProps then for _, o in ipairs(st.fishProps) do setVisible(o, false) end end -- fishing: hide the rod barrel + fish spot (prompt) once owned
			-- NOTE: st.movieGui is intentionally NOT destroyed here -- the finale end card holds on the screen permanently
			if st.hatchScreenEgg then st.hatchScreenEgg() end -- popcorn: now owned -> crack the egg off the screen end frame, revealing the sheep
			if st.equipped then spawnFollowerPet(petId) else despawnFollowerPet(petId) end
			hideQuestUI(petId)
			if not st.uiDoneLogged then st.uiDoneLogged = true; print("[Pet][UI] quest complete - UI hidden") end
		else
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
			elseif st.isFishing then
				-- fishing: the rod barrel + Fish prompt are static; the egg appears ONLY when CAUGHT (spawnButterEgg),
				-- so don't auto-reveal anything here -- st.egg stays nil until the player reels in the egg.
			elseif not st.hatching then
				setVisible(st.egg, info.found >= info.total)
			end
			-- ===== QUEST UI (driven by the live found/owns state) =====
			if info.found >= 1 then
				activeUiPet = petId
				if prevFound < 1 then showDiscoveryPopup(def, info.found, info.total) end -- first piece = the reveal
				setTracker(def, info.found, info.total)
				if info.found ~= prevFound then print("[Pet][UI] tracker updated: "..info.found.."/"..info.total) end
			else
				tracker.Visible = false
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
end
if PetStateEvent then PetStateEvent.OnClientEvent:Connect(applyState) end -- guarded: a missing remote can't crash the script

-- ===== STARTUP: handshake for state, then ASK THE SERVER for marker positions and build =====
-- Fire the state handshake FIRST so an OWNED pet spawns immediately (the follower needs no markers).
if PetRequestStateEvent then pcall(function() PetRequestStateEvent:FireServer() end) end

-- Per pet: ASK the server for the marker coordinates (no Workspace searching) and build from them.
for petId, def in pairs(PETS) do
	petState[petId] = petState[petId] or { pieces = {}, collected = {}, egg = nil, pet = nil, built = false, owns = false }
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
					local incomplete = (#def.pieceMarkers == 0) or (st.uiFound or 0) < #def.pieceMarkers -- fishing has 0 pieces -> incomplete until owned
					if not st.owns and incomplete then flashHint(def) end
				elseif not inArea and onIsland[petId] then
					onIsland[petId] = false
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
invGui.Name = "PetInventoryUI"; invGui.ResetOnSpawn = false; invGui.DisplayOrder = 100 -- above the HUD, like the other popups
invGui.Parent = pg
local function uicorner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function uistroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 2; s.Parent = o; return s end

-- INVISIBLE click-block behind the panel (NO dark film): fully transparent + Active so the rest of the
-- HUD stays VISIBLE but non-interactable while the panel is open -- same treatment as the food shop.
local dim = Instance.new("Frame"); dim.Name = "Dim"; dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0)
-- Active=FALSE so clicks OUTSIDE the panel fall through to the HUD MENU BUTTONS (direct click-to-switch). The
-- panel itself is Active=true so panel clicks don't leak to the HUD behind it.
dim.BackgroundTransparency = 1; dim.Visible = false; dim.Active = false; dim.Parent = invGui

-- PANEL -- matches the FOOD SHOP panel (700 x 520, nudged up 45px); the Stomach Shop matches this too
local panel = Instance.new("Frame"); panel.Name = "Panel"
panel.Size = UDim2.new(0,700,0,520); panel.Position = UDim2.new(0.5,0,0.5,-45); panel.AnchorPoint = Vector2.new(0.5,0.5) -- matches the FOOD SHOP panel size + on-screen position (700x520, nudged up 45px)
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
-- sections fill the wider 700px panel: pets 12..400 (2 cards/row), quests 412..688 -> 12px margins both sides
local petsSection, petsScroll = makeSection(12, 388, "\xF0\x9F\x90\xBe PETS")
local petsGrid = Instance.new("UIGridLayout"); petsGrid.CellSize = UDim2.new(0,176,0,158); petsGrid.CellPadding = UDim2.new(0,8,0,8)
petsGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left; petsGrid.Parent = petsScroll
local questsSection, questsScroll = makeSection(412, 276, "\xF0\x9F\x97\xBA QUESTS") -- widened +20 to fill the 700px panel
local questsList = Instance.new("UIListLayout"); questsList.Padding = UDim.new(0,8); questsList.SortOrder = Enum.SortOrder.LayoutOrder; questsList.Parent = questsScroll
local questsEmpty = Instance.new("TextLabel"); questsEmpty.Size = UDim2.new(1,-12,0,70); questsEmpty.Position = UDim2.new(0,8,0,34)
questsEmpty.BackgroundTransparency = 1; questsEmpty.Font = Enum.Font.Gotham; questsEmpty.TextSize = 13; questsEmpty.TextWrapped = true
questsEmpty.TextColor3 = Color3.fromRGB(200,220,255); questsEmpty.Text = "Land on islands to discover pet quests!"; questsEmpty.Visible = false; questsEmpty.Parent = questsSection

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY: shared manager (one instance across client scripts, via _G). Guarded
-- factory so whichever client script loads first creates it. The Pet Hub joins the "only one open" group. =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h = mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name
	end
	function mgr.notifyClosed(name) if mgr.current == name then mgr.current = nil end end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
_G.MainMenuManager.register("PetInv", function() panel.Visible = false; dim.Visible = false end) -- full-hide the Pet Hub

local latestInv = { owned = {}, quests = {}, totalPets = 0 }
local function openPanel(open)
	if open then _G.MainMenuManager.notifyOpened("PetInv") end -- direct switch: close any other open main menu first
	panel.Visible = open; dim.Visible = open
	if open then
		local nOwned = 0; for _ in pairs(latestInv.owned or {}) do nOwned = nOwned + 1 end
		local nQuests = 0; for _ in pairs(latestInv.quests or {}) do nQuests = nQuests + 1 end
		print("[PetInv] inventory opened - owned: " .. nOwned .. ", quests discovered: " .. nQuests)
	else
		_G.MainMenuManager.notifyClosed("PetInv")
	end
end
closeBtn.MouseButton1Click:Connect(function() openPanel(false) end)
dim.InputBegan:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then openPanel(false) end
end)
-- the ONE pet button (the repurposed daily-rewards HUD button in CoreClient) toggles this panel via here
local toggleEvent = Instance.new("BindableEvent"); toggleEvent.Name = "PetInvToggle"; toggleEvent.Parent = pg
toggleEvent.Event:Connect(function() openPanel(not panel.Visible) end)

-- one OWNED pet card (icon/name/level/equip/upgrade/robux) into the PETS grid
local function buildPetCard(petId, p, order)
	local card = Instance.new("Frame"); card.Name = petId; card.LayoutOrder = order; card.BackgroundColor3 = Color3.fromRGB(20,70,160); card.Parent = petsScroll
	uicorner(card, 10)
	uistroke(card, p.equipped and Color3.fromRGB(255,215,0) or Color3.fromRGB(10,40,100), p.equipped and 3 or 1)
	local icon = Instance.new("TextLabel"); icon.Size = UDim2.new(1,0,0,40); icon.Position = UDim2.new(0,0,0,6)
	icon.BackgroundTransparency = 1; icon.Font = Enum.Font.GothamBold; icon.TextSize = 30; icon.Parent = card
	icon.Text = (PETS[petId] and PETS[petId].iconEmoji) or "\xF0\x9F\xA5\xA6" -- per-pet icon (🥦 / 🥥)
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-8,0,18); nm.Position = UDim2.new(0,4,0,46)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 15; nm.TextColor3 = Color3.new(1,1,1); nm.Text = p.displayName; nm.Parent = card
	local lv = Instance.new("TextLabel"); lv.Size = UDim2.new(1,-8,0,16); lv.Position = UDim2.new(0,4,0,64)
	lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold; lv.TextSize = 12; lv.TextColor3 = Color3.fromRGB(255,215,0)
	lv.Text = "Lv " .. p.level .. " / " .. p.maxLevel .. (p.equipped and "  \xE2\x80\xA2 EQUIPPED" or ""); lv.Parent = card
	local eq = Instance.new("TextButton"); eq.Size = UDim2.new(1,-12,0,26); eq.Position = UDim2.new(0,6,0,86)
	eq.Font = Enum.Font.GothamBold; eq.TextSize = 14; eq.TextColor3 = Color3.new(1,1,1)
	eq.BackgroundColor3 = p.equipped and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50)
	eq.Text = p.equipped and "UNEQUIP" or "EQUIP"; eq.Parent = card
	uicorner(eq, 8); uistroke(eq, Color3.new(0,0,0), 1)
	eq.MouseButton1Click:Connect(function()
		if p.equipped then pcall(function() PetEquipEvent:FireServer(false) end)
		else pcall(function() PetEquipEvent:FireServer(petId) end) end
	end)
	local up = Instance.new("TextButton"); up.Size = UDim2.new(0.6,-7,0,24); up.Position = UDim2.new(0,6,0,116)
	up.Font = Enum.Font.GothamBold; up.TextSize = 11; up.TextColor3 = Color3.new(1,1,1); up.Parent = card
	uicorner(up, 8)
	if p.level >= p.maxLevel then up.Text = "MAX"; up.BackgroundColor3 = Color3.fromRGB(90,90,90); up.AutoButtonColor = false
	elseif p.canUpgrade then up.Text = "UPGRADE!"; up.BackgroundColor3 = Color3.fromRGB(255,140,0)
		up.MouseButton1Click:Connect(function() pcall(function() PetUpgradeEvent:FireServer(petId) end) end)
	else up.Text = "Lv" .. tostring(p.nextLevel or "?") .. " \xF0\x9F\x94\x92"; up.BackgroundColor3 = Color3.fromRGB(40,80,150); up.AutoButtonColor = false end
	local rb = Instance.new("TextButton"); rb.Size = UDim2.new(0.4,-5,0,24); rb.Position = UDim2.new(0.6,3,0,116)
	rb.Font = Enum.Font.GothamBold; rb.TextSize = 11; rb.TextColor3 = Color3.new(1,1,1); rb.Parent = card
	uicorner(rb, 8)
	if p.level >= p.maxLevel then rb.Text = "\xE2\x80\x94"; rb.BackgroundColor3 = Color3.fromRGB(90,90,90); rb.AutoButtonColor = false
	else rb.Text = "R$"; rb.BackgroundColor3 = Color3.fromRGB(50,200,50) -- Robux skip (stub until the dev product id is set)
		rb.MouseButton1Click:Connect(function()
			pcall(function() PetPendingUpgrade:FireServer(petId) end)
			task.wait(0.15)
			pcall(function() game:GetService("MarketplaceService"):PromptProductPurchase(player, PET_UPGRADE_PRODUCT_ID) end)
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

local function rebuildInventory(payload)
	latestInv = payload or { owned = {}, quests = {}, totalPets = 0 }
	local owned, quests, totalPets = latestInv.owned or {}, latestInv.quests or {}, latestInv.totalPets or 0
	-- PETS section: owned cards first, then locked "?" slots for the rest
	for _, c in ipairs(petsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	local ownedCount, order = 0, 0
	for petId, p in pairs(owned) do ownedCount = ownedCount + 1; order = order + 1; buildPetCard(petId, p, order) end
	local locked = math.max(0, totalPets - ownedCount)
	for k = 1, locked do buildLockedSlot(1000 + k) end -- locked slots sort AFTER the owned cards
	petsScroll.CanvasSize = UDim2.new(0,0,0, math.ceil((ownedCount + locked) / 2) * 166 + 8) -- 2 cards per row
	-- QUESTS section: discovered quests
	for _, c in ipairs(questsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	local qCount = 0
	for _, q in pairs(quests) do qCount = qCount + 1; buildQuestEntry(q, qCount) end
	questsEmpty.Visible = (qCount == 0)
	questsScroll.CanvasSize = UDim2.new(0,0,0, qCount * 100 + 8)
end
if PetInventoryEvent then PetInventoryEvent.OnClientEvent:Connect(rebuildInventory) end

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
