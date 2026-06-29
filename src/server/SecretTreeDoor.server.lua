-- ============================================================================
-- SECRET TREE DOOR (easter egg) — a hidden, framed doorway carved into the existing "SecretTree", with a
-- LITTLE GUY (a tiny gnome/creature) living inside. Knock (E): the door creaks open, the little guy WALKS OUT
-- of the dark hollow, faces you, hands over a reward in his speech bubble, waves, and walks back in as the door
-- shuts. ONE-TIME per player (server-validated + DataStore-saved); after that he pops out with a flavour line and
-- gives nothing. Built from simple SmoothPlastic parts (no studs), in the existing easter-egg style.
-- ============================================================================

local Workspace        = game:GetService("Workspace")
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage    = game:GetService("ServerStorage")
local RunService       = game:GetService("RunService")

-- =========================== EASY-EDIT CONFIG ===============================
local CONFIG = {
	treeName     = "SecretTree",                  -- attach the door to this EXISTING tree in Workspace
	sideShift    = 0.0,                           -- shift the whole assembly along the trunk face to centre it (+= right)
	backShift    = 0.1,                           -- push the whole assembly into the trunk (+= backwards/recessed)
	-- COSMETIC SET DRESSING (mat + sign + mailbox + ambient life — all non-colliding, won't block the prompt/walk):
	signText       = "Gnome Home",
	butterflyCount = 3,                           -- little butterflies bobbing near the doorway (0 = none)
	pollenRate     = 5,                           -- drifting pollen motes per second (0 = off)
	gnomeScale   = 0.55,                          -- the little guy = a garden gnome shrunk to this scale (~55%)
	-- REWARD (easy to swap — see grantReward() to tie into another system instead of coins):
	rewardCoins  = 100,
	claimMode    = "once",                        -- "once" = one-time per player (saved) | "cooldown" = repeatable
	cooldownSecs = 24 * 3600,                     -- only used when claimMode == "cooldown" (once per day)
	-- LITTLE GUY — walk speed / timing (seconds) + his lines (all easy to edit):
	walkTime     = 1.4,                           -- time to walk out (and back)
	doorOpenWait = 0.55,                          -- after the door starts opening, before he steps out
	pauseTime    = 0.35,                          -- settle before handing over
	holdTime     = 1.6,                           -- how long he stays out after handing over
	giveLines    = { "Here, take this!", "A little gift for you!", "You found me! Here ya go!" },
	emptyLines   = { "Nothing today \xE2\x80\x94 come back later!", "All out for now... try again another day!" },
	-- prompt:
	promptText   = "Knock",
	promptDist   = 8,                             -- must be close (it's a secret)
	-- POLISH sounds (blank by default so nothing fails to load; drop in rbxassetid:// to enable):
	creakSoundId   = "",                          -- TODO: a soft creak on open
	ambientSoundId = "",                          -- TODO: a faint looping hum near the tree
}
-- ============================================================================

local SMOOTH = Enum.SurfaceType.Smooth
local SMOOTHPLASTIC = Enum.Material.SmoothPlastic
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part")
	p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
	p.Material = material or SMOOTHPLASTIC -- default SmoothPlastic -> no stud texture
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH -- all faces smooth -> no studs/dots
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end
local function pick(t) return t[math.random(1, #t)] end

-- ----- overhead bubble (same white rounded style the cow/farmer use) -----
local function makeBubble(adornee, heightY)
	local bb = Instance.new("BillboardGui")
	bb.Name = "DoorBubble"; bb.Adornee = adornee
	bb.Size = UDim2.fromOffset(230, 60); bb.StudsOffset = Vector3.new(0, heightY, 0)
	bb.AlwaysOnTop = true; bb.LightInfluence = 0; bb.MaxDistance = 26; bb.Enabled = false; bb.Parent = adornee
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1); frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BackgroundTransparency = 0.05; frame.BorderSizePixel = 0; frame.Parent = bb
	Instance.new("UICorner").Parent = frame
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(40, 40, 46); stroke.Thickness = 2; stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1; label.Size = UDim2.new(1, -16, 1, -10); label.Position = UDim2.fromOffset(8, 5)
	label.Font = Enum.Font.GothamBold; label.TextSize = 18; label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(34, 34, 40); label.Text = ""; label.Parent = frame
	return { gui = bb, label = label }
end
local function bubbleSay(bubble, msg, secs)
	if not (bubble and bubble.gui.Parent) then return end
	bubble.label.Text = msg; bubble.gui.Enabled = true
	task.delay(secs or 4, function() if bubble.gui.Parent then bubble.gui.Enabled = false end end)
end

-- =============================== DATASTORE CLAIM ============================
local CLAIM_STORE = DataStoreService:GetDataStore("SecretTreeDoor_v1")
local claimedAt, loaded = {}, {} -- [player] = unix time of last claim (0 = never)
local function loadClaim(p)
	local ok, v = pcall(function() return CLAIM_STORE:GetAsync(tostring(p.UserId)) end)
	claimedAt[p] = (ok and type(v) == "number") and v or 0
	loaded[p] = true
end
local function saveClaim(p) pcall(function() CLAIM_STORE:SetAsync(tostring(p.UserId), claimedAt[p] or 0) end) end
local function canClaim(p)
	if not loaded[p] then loadClaim(p) end
	local last = claimedAt[p] or 0
	if last == 0 then return true end
	if CONFIG.claimMode == "cooldown" then return (os.time() - last) >= CONFIG.cooldownSecs end
	return false -- "once" and already claimed
end
Players.PlayerAdded:Connect(function(p) task.spawn(loadClaim, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(loadClaim, p) end
Players.PlayerRemoving:Connect(function(p) claimedAt[p] = nil; loaded[p] = nil end)

-- REWARD: easy to swap. Default = coins. To tie into another system, replace the body, e.g.:
--   if _G.grantGutSkin then _G.grantGutSkin(p, "Gold") end      -- a cosmetic skin / pet item / crate / etc.
local function grantReward(p)
	local ls = p:FindFirstChild("leaderstats")
	local coins = ls and ls:FindFirstChild("Coins")
	local tce   = ls and ls:FindFirstChild("TotalCoinsEarned")
	if coins then coins.Value = coins.Value + CONFIG.rewardCoins end
	if tce then tce.Value = tce.Value + CONFIG.rewardCoins end
end

-- ================= the EMBEDDED, FRAMED DOORWAY (carved-look) ==============
local function buildDoor(treeCF, trunkR, parent)
	local model = Instance.new("Model"); model.Name = "SecretDoor"; model.Parent = parent
	local function cx(x, y, z) return treeCF * CFrame.new(x, y, z) end
	local surf = trunkR -- the bark front is at local z = -surf

	-- (4) proportion to the trunk: small + never wider than the trunk, sits flat on the ground at the base.
	-- (trunkR is estimated from the bounding box, so keep the door modest so it stays "small + hidden".)
	local dW = math.clamp(trunkR * 1.0, 1.0, 1.5)
	local dH = math.clamp(trunkR * 1.8, 1.9, 2.5)
	local dT, fW, fT = 0.14, 0.16, 0.26
	local doorY = dH / 2 -- door bottom rests on the ground

	local DOOR  = Color3.fromRGB(82, 58, 38)  -- (5) the door
	local FRAME = Color3.fromRGB(45, 32, 22)  -- (3) frame: darker brown than the trunk
	local DARK  = Color3.fromRGB(14, 11, 9)   -- (2) dark hollow you see when it opens

	-- (2) dark backing right at the bark -> a dark opening shows when the door swings aside (never grass)
	newPart(model, "Backing", Enum.PartType.Block, Vector3.new(dW + 0.06, dH + 0.06, 0.12), DARK, cx(0, doorY, -(surf + 0.04)), SMOOTHPLASTIC)
	-- (3) simple wood FRAME (left / right / top), protrudes a touch so the door reads as recessed within it
	newPart(model, "FrameL", Enum.PartType.Block, Vector3.new(fW, dH + fW, fT), FRAME, cx(-(dW / 2 + fW / 2), doorY, -(surf + 0.12)), Enum.Material.Wood)
	newPart(model, "FrameR", Enum.PartType.Block, Vector3.new(fW, dH + fW, fT), FRAME, cx( (dW / 2 + fW / 2), doorY, -(surf + 0.12)), Enum.Material.Wood)
	newPart(model, "FrameT", Enum.PartType.Block, Vector3.new(dW + fW * 2, fW, fT), FRAME, cx(0, dH + fW / 2, -(surf + 0.12)), Enum.Material.Wood)

	-- (1)(2) DOOR: SmoothPlastic, recessed within the frame (set back from the frame's front lip)
	local closedCF = cx(0, doorY, -(surf + 0.12))
	local door = newPart(model, "Door", Enum.PartType.Block, Vector3.new(dW, dH, dT), DOOR, closedCF, SMOOTHPLASTIC)
	door.CanQuery = true -- so the ProximityPrompt is interactable
	-- (5) brass/gold knob, SmoothPlastic
	newPart(model, "Knob", Enum.PartType.Ball, Vector3.new(0.16, 0.16, 0.16), Color3.fromRGB(214, 176, 92),
		closedCF * CFrame.new(dW * 0.33, 0, -(dT / 2 + 0.04)), SMOOTHPLASTIC)
	-- hinge on the LEFT edge -> swing open about it
	local hingeCF = closedCF * CFrame.new(-dW / 2, 0, 0)
	local openCF  = hingeCF * CFrame.Angles(0, math.rad(108), 0) * CFrame.new(dW / 2, 0, 0)

	-- faint glow inside + soft hum so observant players notice something's here
	local backing = model:FindFirstChild("Backing")
	local glow = Instance.new("PointLight"); glow.Color = Color3.fromRGB(255, 222, 150); glow.Brightness = 1.2; glow.Range = 7; glow.Parent = backing
	if CONFIG.ambientSoundId ~= "" then
		local s = Instance.new("Sound"); s.SoundId = CONFIG.ambientSoundId; s.Looped = true; s.Volume = 0.25
		s.RollOffMaxDistance = 28; s.RollOffMinDistance = 6; s.Parent = backing; pcall(function() s:Play() end)
	end

	return { model = model, door = door, closedCF = closedCF, openCF = openCF, surf = surf }
end

-- smooth matte, no studs/decals (used for the trunk + the cloned gnome)
local function cleanSmooth(part)
	part.Material = SMOOTHPLASTIC
	part.TopSurface = SMOOTH; part.BottomSurface = SMOOTH; part.LeftSurface = SMOOTH
	part.RightSurface = SMOOTH; part.FrontSurface = SMOOTH; part.BackSurface = SMOOTH
end

-- ===================== the LITTLE GUY = a shrunk GARDEN GNOME ==============
-- Clone the existing CommunityGarden gnome ("GardenGnome" clone, or the "Gnome" template), shrink it, and clean it
-- to the same smooth matte look (no studs/decals). Falls back to a tiny built gnome if the garden gnome isn't found.
local function buildGnome(parent)
	local src = Workspace:FindFirstChild("GardenGnome", true) or Workspace:FindFirstChild("Gnome", true)
		or ServerStorage:FindFirstChild("Gnome", true)
	local model
	if src and src:IsA("Model") then
		model = src:Clone()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
				cleanSmooth(d); if d:IsA("MeshPart") then d.TextureID = "" end
			elseif d:IsA("Decal") or d:IsA("Texture") then d:Destroy()           -- kill pasted-on stud/texture decals
			elseif d:IsA("Humanoid") or d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end -- static cosmetic only
		end
		pcall(function() model:ScaleTo(CONFIG.gnomeScale) end) -- shrink to a smaller version that fits the door
	else
		model = Instance.new("Model") -- fallback: a tiny smooth gnome so the feature still works
		local b = newPart(model, "Body", Enum.PartType.Ball, Vector3.new(0.8, 0.9, 0.8), Color3.fromRGB(86, 128, 70), CFrame.new()); b.Anchored = true; model.PrimaryPart = b
		newPart(model, "Head", Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(255, 214, 170), CFrame.new(0, 0.55, 0))
		newPart(model, "Hat",  Enum.PartType.Ball, Vector3.new(0.66, 0.5, 0.66), Color3.fromRGB(180, 62, 56), CFrame.new(0, 0.85, 0))
		newPart(model, "HatTip", Enum.PartType.Ball, Vector3.new(0.28, 0.36, 0.28), Color3.fromRGB(180, 62, 56), CFrame.new(0, 1.06, 0))
	end
	model.Name = "LittleGuy"; model.Parent = parent
	if not model.PrimaryPart then -- pick the highest part (~= the head) as the bubble anchor
		local top; for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") and (not top or d.Position.Y > top.Position.Y) then top = d end end
		model.PrimaryPart = top
	end
	-- snapshot each part's transparency so we can hide him in the hollow and restore him exactly
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then parts[#parts + 1] = { d, d.Transparency } end end
	return { model = model, parts = parts }
end
local function setGnomeVisible(g, v)
	for _, e in ipairs(g.parts) do e[1].Transparency = v and e[2] or 1 end
end

-- ===================== cosmetic SET DRESSING around the door ==============
-- Welcome mat + "Gnome Home" sign + tiny mailbox + gentle butterflies/pollen. All built off doorCF, on the
-- ground, non-colliding (newPart -> CanCollide false), so nothing blocks the prompt or the gnome's walk-out.
local function buildSetDressing(doorCF, surf, parent)
	local model = Instance.new("Model"); model.Name = "SecretDoorDressing"; model.Parent = parent
	local function at(x, h, z) return doorCF * CFrame.new(x, h, z) end
	local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- stands a Cylinder (length = X) up vertically
	local WOOD = Color3.fromRGB(96, 66, 42)

	-- WELCOME MAT: a thin flat oval (rounded), flush on the ground, centred in front of the door
	newPart(model, "WelcomeMat", Enum.PartType.Cylinder, Vector3.new(0.08, 1.4, 1.05), Color3.fromRGB(166, 126, 84), at(0, 0.04, -(surf + 1.15)) * FLAT)
	newPart(model, "MatTrim",    Enum.PartType.Cylinder, Vector3.new(0.085, 1.0, 0.72), Color3.fromRGB(122, 90, 58), at(0, 0.045, -(surf + 1.15)) * FLAT)

	-- "GNOME HOME" SIGN: small post + board to the LEFT, board facing the player's approach (-Z)
	local sx = -1.5
	newPart(model, "SignPost", Enum.PartType.Cylinder, Vector3.new(1.1, 0.12, 0.12), WOOD, at(sx, 0.55, -(surf + 0.8)) * FLAT)
	local board = newPart(model, "SignBoard", Enum.PartType.Block, Vector3.new(1.0, 0.44, 0.08), Color3.fromRGB(204, 170, 120), at(sx, 1.18, -(surf + 0.8)))
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.Parent = board
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne; lbl.TextScaled = true; lbl.Text = CONFIG.signText; lbl.TextColor3 = Color3.fromRGB(70, 46, 28)
	local ls = Instance.new("UIStroke"); ls.Color = Color3.fromRGB(235, 220, 190); ls.Thickness = 1; ls.Parent = lbl
	lbl.Parent = sg

	-- TINY MAILBOX: post + rounded box to the RIGHT, with a little red flag (purely cosmetic)
	local mx = 1.5
	newPart(model, "MailPost", Enum.PartType.Cylinder, Vector3.new(1.05, 0.12, 0.12), WOOD, at(mx, 0.52, -(surf + 0.7)) * FLAT)
	newPart(model, "MailBox",  Enum.PartType.Block, Vector3.new(0.5, 0.36, 0.64), Color3.fromRGB(70, 112, 170), at(mx, 1.12, -(surf + 0.7)))
	newPart(model, "MailLid",  Enum.PartType.Cylinder, Vector3.new(0.5, 0.46, 0.66), Color3.fromRGB(70, 112, 170), at(mx, 1.30, -(surf + 0.7))) -- rounded top (axis along X)
	newPart(model, "FlagPole", Enum.PartType.Block, Vector3.new(0.04, 0.32, 0.04), WOOD, at(mx + 0.27, 1.22, -(surf + 0.7)))
	newPart(model, "Flag",     Enum.PartType.Block, Vector3.new(0.04, 0.18, 0.2), Color3.fromRGB(200, 62, 55), at(mx + 0.27, 1.32, -(surf + 0.6)))

	-- POLLEN: a gentle drift of pale motes near the doorway (daytime, not glowy). Rate is easy to tune.
	if CONFIG.pollenRate > 0 then
		local anchor = newPart(model, "PollenAnchor", Enum.PartType.Block, Vector3.new(0.1, 0.1, 0.1), Color3.fromRGB(255, 255, 255), at(0, 1.1, -(surf + 0.7)))
		anchor.Transparency = 1
		local att = Instance.new("Attachment"); att.Parent = anchor
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(Color3.fromRGB(245, 238, 200)); pe.Transparency = NumberSequence.new(0.45)
		pe.Lifetime = NumberRange.new(3, 5); pe.Speed = NumberRange.new(0.3, 0.8); pe.Rate = CONFIG.pollenRate
		pe.SpreadAngle = Vector2.new(60, 60); pe.Size = NumberSequence.new(0.12); pe.LightEmission = 0
		pe.Acceleration = Vector3.new(0, 0.25, 0); pe.Rotation = NumberRange.new(0, 360); pe.RotSpeed = NumberRange.new(-30, 30)
		pe.EmissionDirection = Enum.NormalId.Top; pe.Parent = att
	end

	-- BUTTERFLIES: a few that gently bob + drift near the doorway. Count is easy to tune.
	local wingColors = { Color3.fromRGB(245, 225, 130), Color3.fromRGB(240, 180, 205), Color3.fromRGB(172, 202, 240), Color3.fromRGB(200, 235, 175) }
	local flock = {}
	for i = 1, math.max(0, CONFIG.butterflyCount) do
		local ang  = (i / math.max(1, CONFIG.butterflyCount)) * math.pi * 2
		local home = at(math.cos(ang) * 1.1, 1.35 + (i % 2) * 0.4, -(surf + 1.0 + math.sin(ang) * 0.5))
		local bm   = Instance.new("Model"); bm.Name = "Butterfly"; bm.Parent = model
		local col  = wingColors[((i - 1) % #wingColors) + 1]
		local body = newPart(bm, "BBody", Enum.PartType.Ball, Vector3.new(0.09, 0.2, 0.09), Color3.fromRGB(45, 38, 32), home); body.Anchored = true
		local function weld(p) p.Anchored = false; local w = Instance.new("WeldConstraint"); w.Part0 = body; w.Part1 = p; w.Parent = p end
		weld(newPart(bm, "WingL", Enum.PartType.Block, Vector3.new(0.03, 0.24, 0.32), col, home * CFrame.new(-0.15, 0, 0) * CFrame.Angles(0, 0, math.rad(22))))
		weld(newPart(bm, "WingR", Enum.PartType.Block, Vector3.new(0.03, 0.24, 0.32), col, home * CFrame.new( 0.15, 0, 0) * CFrame.Angles(0, 0, math.rad(-22))))
		flock[#flock + 1] = { part = body, home = home, phase = ang, speed = 1.4 + (i % 3) * 0.25 }
	end
	if #flock > 0 then
		local t = 0
		RunService.Heartbeat:Connect(function(dt)
			t = t + dt
			for _, b in ipairs(flock) do
				local bob = math.sin(t * b.speed + b.phase) * 0.32
				local dx  = math.cos(t * b.speed * 0.6 + b.phase) * 0.35
				local dz  = math.sin(t * b.speed * 0.5 + b.phase) * 0.35
				b.part.CFrame = b.home * CFrame.new(dx, bob, dz) * CFrame.Angles(0, math.sin(t * 0.6 + b.phase) * 0.8, 0)
			end
		end)
	end
end

-- =============================== WIRE IT UP ================================
task.spawn(function()
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end

	-- find the EXISTING tree named CONFIG.treeName (retry a bit in case it streams/loads in)
	local treeInst
	for _ = 1, 30 do treeInst = Workspace:FindFirstChild(CONFIG.treeName, true); if treeInst then break end; task.wait(1) end
	if not treeInst then
		warn(("[SecretDoor] '%s' not found in Workspace -> door NOT attached. Check the tree's name/location."):format(CONFIG.treeName))
		return
	end

	-- bottom-centre + size of the tree (Model -> bounding box; Part -> itself; container -> first part inside)
	local centerCF, size
	if treeInst:IsA("Model") then centerCF, size = treeInst:GetBoundingBox()
	elseif treeInst:IsA("BasePart") then centerCF, size = treeInst.CFrame, treeInst.Size
	else
		local part = treeInst:FindFirstChildWhichIsA("BasePart", true)
		if not part then warn(("[SecretDoor] '%s' has no parts -> door NOT attached."):format(CONFIG.treeName)); return end
		centerCF, size = part.CFrame, part.Size
	end
	local basePos = Vector3.new(centerCF.X, centerCF.Y - size.Y / 2, centerCF.Z)
	local trunkR  = math.clamp(math.min(size.X, size.Z) * 0.5, 0.8, 3)

	-- which side of the trunk faces the garden (so the door goes on that side)
	local garden = Workspace:FindFirstChild("CommunityGardenBuild", true) or Workspace:FindFirstChild("GardenHardscape", true)
	local facePos = basePos + Vector3.new(0, 0, -10)
	if garden and garden:IsA("Model") then facePos = garden:GetBoundingBox().Position
	elseif garden then local gp = garden:FindFirstChildWhichIsA("BasePart", true); if gp then facePos = gp.Position end end
	local gardenDir = Vector3.new(facePos.X - basePos.X, 0, facePos.Z - basePos.Z)
	gardenDir = (gardenDir.Magnitude > 0.1) and gardenDir.Unit or Vector3.new(0, 0, -1)

	-- (2) NO ANGLE: align the door to the TRUNK's own face. Snap to the tree's horizontal axis that points most
	-- toward the garden, then face the door straight along it -> upright (no tilt), flat + flush against that face.
	local treeCFrame = (treeInst:IsA("Model") and treeInst:GetPivot())
		or (treeInst:IsA("BasePart") and treeInst.CFrame) or CFrame.new(basePos)
	local axes = {}
	for _, v in ipairs({ treeCFrame.LookVector, -treeCFrame.LookVector, treeCFrame.RightVector, -treeCFrame.RightVector }) do
		local f = Vector3.new(v.X, 0, v.Z) -- flatten to horizontal so the door always stands straight up
		if f.Magnitude > 0.05 then axes[#axes + 1] = f.Unit end
	end
	if #axes == 0 then axes = { Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) } end
	local bestDir, bestDot = axes[1], -math.huge
	for _, a in ipairs(axes) do local d = a:Dot(gardenDir); if d > bestDot then bestDot, bestDir = d, a end end
	local treeCF = CFrame.lookAt(basePos, basePos + bestDir) -- upright; -Z (door front) flush to the chosen trunk face

	local parent = (treeInst:IsA("Model") and treeInst) or Workspace

	-- (3) clean the TRUNK: smooth all faces + SmoothPlastic so no studs show (mesh textures, if any, are kept)
	if treeInst:IsA("BasePart") then cleanSmooth(treeInst) end
	for _, d in ipairs(treeInst:GetDescendants()) do if d:IsA("BasePart") then cleanSmooth(d) end end

	-- (1) shift the whole door assembly along the trunk face so it centres better on the trunk
	local doorCF = treeCF * CFrame.new(CONFIG.sideShift, 0, CONFIG.backShift)
	local tree = buildDoor(doorCF, trunkR, parent)
	local surf = tree.surf

	-- cosmetic set dressing (mat + "Gnome Home" sign + mailbox + butterflies/pollen), aligned to the door
	pcall(buildSetDressing, doorCF, surf, parent)

	-- (2) the little guy = a shrunk garden gnome, hidden just inside the doorway, feet on the ground
	local gnome = buildGnome(parent)
	local R0 = gnome.model:GetPivot().Rotation -- the orientation that keeps the (cloned) gnome upright
	local homePos = (doorCF * CFrame.new(0, 0, -(surf + 0.1))).Position
	gnome.model:PivotTo(CFrame.new(homePos) * R0)
	local gcf, gsize = gnome.model:GetBoundingBox()
	gnome.model:PivotTo(gnome.model:GetPivot() + Vector3.new(0, basePos.Y - (gcf.Position.Y - gsize.Y / 2), 0)) -- feet on the door base
	local homePivot = gnome.model:GetPivot()
	setGnomeVisible(gnome, false) -- hidden in the dark hollow until knocked

	-- bubble above his head + a sparkle on him (PrimaryPart ≈ his head, picked in buildGnome)
	local head = gnome.model.PrimaryPart
	local bcf, bsize = gnome.model:GetBoundingBox()
	local bubble = makeBubble(head, (bcf.Position.Y + bsize.Y / 2 - head.Position.Y) + 0.6)
	local sAtt = Instance.new("Attachment"); sAtt.Position = Vector3.new(0, 0.2, 0); sAtt.Parent = head
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150))
	sparkle.Lifetime = NumberRange.new(0.6, 1.1); sparkle.Speed = NumberRange.new(1, 3); sparkle.Rate = 0
	sparkle.SpreadAngle = Vector2.new(50, 50); sparkle.Size = NumberSequence.new(0.5); sparkle.LightEmission = 0.6
	sparkle.Parent = sAtt

	-- door + gnome motion (the walk-out is purely VISUAL; the reward is granted server-side below)
	local function openDoor()
		TweenService:Create(tree.door, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = tree.openCF }):Play()
		if CONFIG.creakSoundId ~= "" then
			local s = Instance.new("Sound"); s.SoundId = CONFIG.creakSoundId; s.Volume = 0.5; s.Parent = tree.door
			pcall(function() s:Play() end); task.delay(3, function() s:Destroy() end)
		end
	end
	local function closeDoor()
		TweenService:Create(tree.door, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = tree.closedCF }):Play()
	end
	-- manual MODEL tween (TweenService can't tween a Model): lerp the pivot -> walks the whole anchored gnome.
	local function walkGnome(targetCF, dur)
		local startCF = gnome.model:GetPivot()
		local t0 = os.clock()
		while true do
			local a = math.clamp((os.clock() - t0) / dur, 0, 1)
			gnome.model:PivotTo(startCF:Lerp(targetCF, a * a * (3 - 2 * a))) -- smoothstep ease
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end
	end
	-- he stands just outside the door (keeping his upright orientation; translate-only avoids tilting the clone)
	local outFlat = (doorCF * CFrame.new(0, 0, -(surf + 1.9))).Position
	local gnomeOutPivot = CFrame.new(Vector3.new(outFlat.X, homePivot.Position.Y, outFlat.Z)) * R0
	local function waveGnome() -- a friendly little hop
		local base = gnome.model:GetPivot()
		walkGnome(base * CFrame.new(0, 0.3, 0), 0.18); walkGnome(base, 0.18)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = CONFIG.promptText; prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E; prompt.MaxActivationDistance = CONFIG.promptDist
	prompt.RequiresLineOfSight = false; prompt.HoldDuration = 0; prompt.Parent = tree.door

	local busy = false
	prompt.Triggered:Connect(function(player)
		if busy then return end -- one interaction at a time (also prevents double-claim while he's out)
		busy = true
		local eligible = canClaim(player) -- SERVER decides up front whether this player gets a reward
		task.spawn(function()
			openDoor()
			task.wait(CONFIG.doorOpenWait)
			setGnomeVisible(gnome, true)             -- he appears in the now-open doorway
			walkGnome(gnomeOutPivot, CONFIG.walkTime); task.wait(CONFIG.pauseTime)
			-- HAND OVER (or empty). The reward grant + claim save happen HERE on the server.
			if eligible then
				claimedAt[player] = os.time(); task.spawn(saveClaim, player)
				grantReward(player)
				sparkle:Emit(22)
				bubbleSay(bubble, pick(CONFIG.giveLines), 3)
				print(("[SecretDoor] %s received the reward from the little gnome"):format(player.Name))
			else
				bubbleSay(bubble, pick(CONFIG.emptyLines), 3) -- already claimed / on cooldown -> no grant
			end
			task.wait(CONFIG.holdTime)
			waveGnome(); task.wait(0.3)
			walkGnome(homePivot, CONFIG.walkTime)
			setGnomeVisible(gnome, false)            -- back into the dark hollow
			closeDoor()
			busy = false
		end)
	end)

	print("[SecretDoor] secret tree door + little gnome ready on '" .. CONFIG.treeName .. "' (knock to meet him).")
end)
