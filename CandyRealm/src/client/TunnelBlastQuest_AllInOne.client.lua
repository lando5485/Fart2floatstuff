--======================================================================
-- TunnelBlastQuest_AllInOne.client.lua   (LocalScript, per-player)
--======================================================================
-- 💥 "BLAST OPEN THE TUNNEL"  -- an individual mining expedition on ISLAND 11.
--
--   Phase 1  Carry 3 Dynamite Crates to the Blast Zone (the painted X on the
--            rock wall). Each crate snaps onto the X. 3 placed -> 3..2..1..BOOM,
--            the wall bursts and a mine shaft opens.
--   Phase 2  Descend (a prompt teleports you) into a PRIVATE underground mine and
--            mine 10 Diamond Ore nodes (a few swings each).
--   Phase 3  Carry the diamonds to the Mine Cart and deposit them until it's full.
--   Phase 4  "Return to the surface!" -- take the shaft back up.
--   Done     Coins/XP/Gems, then the tunnel reseals so you can run it again.
--
-- The whole thing is CLIENT-SIDE + per-player, exactly like the island's other
-- quests: nothing here replicates, so every player gets their OWN blast, their OWN
-- underground cave (built locally, so it's invisible to everyone else), and their
-- OWN 10 nodes. The cave is dropped far below the map at a per-player offset so two
-- players never share the same void.
--
-- WHAT TO PLACE IN STUDIO (all optional -- there are fallbacks):
--   * a Part/Model named "BlastZone" on island11's canyon wall. Its FRONT face
--     (its CFrame LookVector) should point the way the player walks up to it; the
--     painted X + crate slots are built on that face. No marker -> it anchors to
--     island11's edge, or to where you stand when you take the quest.
--   * (optional) a "Candy Npc" / "Miner Npc" near the blast zone gives the quest;
--     with none, a "Take Quest" board is built at the blast zone.
--======================================================================

local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local Debris           = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local SoundService     = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService  = game:GetService("TextChatService")
local Lighting         = game:GetService("Lighting")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_NAMES   = { "island11", "island_11" }
local BLAST_NAMES    = { "blastzone", "blast", "tunnelblast" }
local TNT_NAMES      = { "tnt" }
local NPC_NAMES      = { "minernpc", "candynpc" }
local ISLAND_RANGE   = 900          -- how near island11 the blast zone can be

local CRATES_NEEDED  = 3            -- dynamite crates to plant on the X
local NODES_NEEDED   = 10           -- diamond ore nodes to mine
local SWINGS_PER_NODE = 4           -- slices the drill cuts through one node

local COIN_REWARD    = 750
local XP_REWARD      = 300          -- flavour (shown on the completion card)
local GEM_REWARD     = 20           -- flavour

-- palette (low-poly, cartoon-mine)
local ROCK    = Color3.fromRGB(88, 82, 76)
local ROCK_DK = Color3.fromRGB(58, 53, 48)
local ROCK_LT = Color3.fromRGB(120, 112, 104)
local DIRT    = Color3.fromRGB(74, 58, 42)
local WOOD    = Color3.fromRGB(150, 104, 58)
local WOOD_DK = Color3.fromRGB(104, 70, 38)
local STEEL   = Color3.fromRGB(150, 156, 166)
local STEEL_DK = Color3.fromRGB(96, 100, 108)
local DYN_RED = Color3.fromRGB(198, 52, 42)
local X_RED   = Color3.fromRGB(220, 42, 36)
local DIAMOND = Color3.fromRGB(120, 220, 255)
local FLAME   = Color3.fromRGB(255, 150, 52)
local GOLD    = Color3.fromRGB(255, 210, 74)
-- crystal palette: blue / purple / cyan / emerald (low-poly, calm -- not blinding neon)
local CRYSTAL_COLS = {
	Color3.fromRGB(92, 168, 255), Color3.fromRGB(178, 122, 255),
	Color3.fromRGB(96, 226, 232), Color3.fromRGB(96, 224, 150),
}

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s) return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", "")) end

local function nameHasAny(name, needles)
	local n = norm(name)
	for _, w in ipairs(needles) do if string.find(n, w, 1, true) then return true end end
	return false
end

local function firstBasePart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function mk(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat
		local r = fn(); if r then return r end
		task.wait(0.5)
	until os.clock() - t0 > (timeout or 45)
	return fn()
end

local function findByAnyName(keys, nearPos, maxDist)
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("BasePart")) and nameHasAny(d.Name, keys) and norm(d.Name) ~= "island11" then
			local part = firstBasePart(d)
			if part then
				if not nearPos then return d end
				local dist = (part.Position - nearPos).Magnitude
				if dist <= (maxDist or math.huge) and (not bestD or dist < bestD) then best, bestD = d, dist end
			end
		end
	end
	return best
end

-- find a descendant of `root` whose name exactly matches any key (e.g. the "tnt" part inside island11)
local function findInModel(root, keys)
	if not root then return nil end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Model") or d:IsA("BasePart") then
			local n = norm(d.Name)
			for _, k in ipairs(keys) do if n == k then return d end end
		end
	end
	return nil
end

local function hrpOf()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function humOf()
	local c = player.Character
	return c and c:FindFirstChildWhichIsA("Humanoid")
end

local function notify(text, color)
	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({ text = text, color = color or GOLD }) end)
	end
end

local function pointTo(pos) if pos and _G.guideTrailTo then pcall(function() _G.guideTrailTo(pos) end) end end

-- ============================================================================
-- STATE
-- ============================================================================
local phase        = "idle"   -- idle -> blast -> descend -> mine -> return -> done
local started      = false
local placedCrates = 0
local carryingCrate = false
local minedNodes   = 0
local carriedDiam  = 0
local cartCount    = 0
local busy         = false    -- guards the blast/teleport cinematics

local blastCF                  -- the wall's reference frame (front = LookVector)
local blastWall                -- the model of the rock wall (destroyed on blast)
local mineShaft                -- the opened hole + "Enter the Mine" prompt
local caveModel                -- the private underground cave
local caveEntryCF, caveExitCF  -- teleport targets (into the cave / back to surface)
local surfaceReturnCF          -- where you pop out on top when you leave the mine
local crateSlots = {}          -- world CFrames the placed crates snap to
local placePrompt              -- the "Plant Dynamite" prompt on the blast zone
local heldCrate, heldGem       -- welded-to-hand props
local groundCrates = {}        -- the grabbable dynamite crates by the blast zone
local tntBrick, tntPrompt      -- the world brick named "tnt" you grab charges from (if placed)

-- island-11 "stand" stays LOCKED until this quest is completed (Shop_AllInOne checks the flag +
-- calls the nudge, exactly like island-1's Candy Stand).
_G.tunnelQuestComplete = _G.tunnelQuestComplete or false
_G.tunnelQuestNudge = function()
	notify("💥 Blast open the tunnel & finish the quest to open this stand!", DYN_RED)
end

-- Where the private cave is built. It's a sealed, self-lit box, so the actual world spot only has
-- to be (a) far from every island and (b) ABOVE Workspace.FallenPartsDestroyHeight (default -500) --
-- teleporting the character below that line destroys it and respawns you ("kicked out of the mine").
-- So we tuck it FAR off to the side at a safe altitude, with a per-player offset so nobody overlaps.
local voidOffset = Vector3.new(9000 + (player.UserId % 97) * 300, 600, 9000 + (player.UserId % 61) * 300)

-- ============================================================================
-- OBJECTIVE HUD  (top-centre banner)
-- ============================================================================
local hud = Instance.new("ScreenGui")
hud.Name = "TunnelBlastHUD"; hud.ResetOnSpawn = false; hud.IgnoreGuiInset = true
hud.DisplayOrder = 14; hud.Enabled = false; hud.Parent = PlayerGui

local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5, 0); objFrame.Position = UDim2.new(0.5, 0, 0, 96)
objFrame.Size = UDim2.new(0, 520, 0, 44); objFrame.BackgroundColor3 = Color3.fromRGB(30, 24, 16)
objFrame.BorderSizePixel = 0; objFrame.Parent = hud
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = objFrame
	local s = Instance.new("UIStroke"); s.Color = GOLD; s.Thickness = 2; s.Parent = objFrame
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromRGB(44, 34, 20), Color3.fromRGB(24, 18, 12)); g.Parent = objFrame
end
local objLbl = Instance.new("TextLabel")
objLbl.BackgroundTransparency = 1; objLbl.Size = UDim2.fromScale(1, 1)
objLbl.Font = Enum.Font.FredokaOne; objLbl.TextColor3 = Color3.fromRGB(255, 240, 205)
objLbl.TextScaled = true; objLbl.Parent = objFrame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 19; sz.Parent = objLbl
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14); pad.Parent = objLbl
end

-- "Back to Surface" button (bottom-centre). Cart full -> finishes the quest; otherwise it just
-- climbs you out, keeping your progress + cave so you can re-enter the shaft. Assigned below.
local leaveMine
local surfaceBtn = Instance.new("TextButton")
surfaceBtn.Name = "BackToSurface"; surfaceBtn.AnchorPoint = Vector2.new(0.5, 1)
surfaceBtn.Position = UDim2.new(0.5, 0, 1, -22); surfaceBtn.Size = UDim2.fromOffset(232, 50)
surfaceBtn.BackgroundColor3 = Color3.fromRGB(152, 98, 42); surfaceBtn.AutoButtonColor = true
surfaceBtn.Font = Enum.Font.FredokaOne; surfaceBtn.Text = "⬆ Back to Surface"; surfaceBtn.TextScaled = true
surfaceBtn.TextColor3 = Color3.fromRGB(255, 245, 222); surfaceBtn.Visible = false; surfaceBtn.Parent = hud
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = surfaceBtn
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(92, 56, 22); s.Thickness = 2; s.Parent = surfaceBtn
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 20; sz.Parent = surfaceBtn
end
surfaceBtn.Activated:Connect(function() if leaveMine then leaveMine() end end)

local function updateObjective()
	hud.Enabled = (phase ~= "idle" and phase ~= "done")
	surfaceBtn.Visible = (phase == "mine" or phase == "return")
	if phase == "blast" then
		objLbl.Text = ("💥 Plant Dynamite on the X:   %d / %d crates"):format(placedCrates, CRATES_NEEDED)
	elseif phase == "descend" then
		objLbl.Text = "🕳️ Enter the mine shaft!"
	elseif phase == "mine" then
		if minedNodes < NODES_NEEDED then
			objLbl.Text = ("⛏️ Mine Diamond Ore:   %d / %d   (carrying %d)"):format(minedNodes, NODES_NEEDED, carriedDiam)
		else
			objLbl.Text = ("💎 Take the diamonds to the Mine Cart:   %d / %d in cart"):format(cartCount, NODES_NEEDED)
		end
	elseif phase == "return" then
		objLbl.Text = "🪜 Return to the surface!"
	end
end

-- centre BOOM / countdown card
local cardGui = Instance.new("ScreenGui")
cardGui.Name = "TunnelCard"; cardGui.ResetOnSpawn = false; cardGui.IgnoreGuiInset = true
cardGui.DisplayOrder = 20; cardGui.Enabled = false; cardGui.Parent = PlayerGui
local card = Instance.new("TextLabel")
card.AnchorPoint = Vector2.new(0.5, 0.5); card.Position = UDim2.fromScale(0.5, 0.4)
card.Size = UDim2.fromOffset(560, 130); card.BackgroundTransparency = 1
card.Font = Enum.Font.FredokaOne; card.TextColor3 = Color3.fromRGB(255, 230, 160)
card.TextStrokeColor3 = Color3.fromRGB(30, 12, 4); card.TextStrokeTransparency = 0
card.TextScaled = true; card.Text = ""; card.Parent = cardGui
local function showCard(text, seconds)
	card.Text = text; cardGui.Enabled = true
	if seconds then
		local mine = text
		task.delay(seconds, function() if card.Text == mine then cardGui.Enabled = false end end)
	end
end

-- brief screen shake
local function screenShake(strength, seconds)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < seconds do
			local left = seconds - (os.clock() - t0)
			local m = (left / seconds) * strength
			cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
			RunService.RenderStepped:Wait()
		end
	end)
end

-- ============================================================================
-- CARRY-IN-HAND  (weld a prop into the player's hand; reused for crates + gems)
-- ============================================================================
local function weldToHand(model, drop)
	local char = player.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	if not (hand and hand:IsA("BasePart")) then model:Destroy(); return false end
	local prim = model.PrimaryPart
	if not prim then model:Destroy(); return false end
	model:PivotTo(hand.CFrame * (drop or CFrame.new(0, -2, 0)))
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= prim then
			local w = Instance.new("WeldConstraint"); w.Part0 = prim; w.Part1 = p; w.Parent = p
		end
	end
	local hw = Instance.new("WeldConstraint"); hw.Part0 = hand; hw.Part1 = prim; hw.Parent = prim
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false; p.CanCollide = false; p.CanQuery = false; p.Massless = true end
	end
	model.Parent = char
	return true
end

-- ============================================================================
-- PROP BUILDERS
-- ============================================================================
-- a wooden dynamite crate (returns an anchored Model at local origin, PrimaryPart set)
-- a clean low-poly TNT BUNDLE: 3x2 red sticks (dark end-caps + cream label bands), two dark straps
-- wrapping it, and a fuse with a glowing spark. Invisible core spine = PrimaryPart (hand/throw pivot).
local function buildDynamiteCrate()
	local m = Instance.new("Model"); m.Name = "DynamiteCrate"; m:SetAttribute("QuestProp", true)
	local spine = mk({ Name = "Core", Size = Vector3.new(2.6, 2.8, 2.6), Transparency = 1 })
	spine.Parent = m; m.PrimaryPart = spine
	for gx = -1, 1 do
		for gz = 0, 1 do
			local base = spine.CFrame * CFrame.new(gx * 0.8, 0, gz * 0.85 - 0.42)
			local stick = mk({ Name = "Dynamite", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.7, 0.72, 0.72),
				Color = DYN_RED, Material = Enum.Material.SmoothPlastic })
			stick.CFrame = base * CFrame.Angles(0, 0, math.rad(90)); stick.Parent = m
			for _, ey in ipairs({ -1.28, 1.28 }) do
				local cap = mk({ Name = "DynCap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 0.74, 0.74),
					Color = Color3.fromRGB(58, 40, 30), Material = Enum.Material.SmoothPlastic })
				cap.CFrame = stick.CFrame * CFrame.new(ey, 0, 0); cap.Parent = m
			end
			local band = mk({ Name = "DynBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 0.76, 0.76),
				Color = Color3.fromRGB(244, 224, 180), Material = Enum.Material.SmoothPlastic })
			band.CFrame = stick.CFrame; band.Parent = m
		end
	end
	for _, sy in ipairs({ -0.7, 0.7 }) do
		local strap = mk({ Name = "Strap", Size = Vector3.new(2.9, 0.35, 2.3), Color = Color3.fromRGB(42, 34, 28), Material = Enum.Material.SmoothPlastic })
		strap.CFrame = spine.CFrame * CFrame.new(0, sy, 0); strap.Parent = m
	end
	local fuse = mk({ Name = "Fuse", Size = Vector3.new(0.16, 1.7, 0.16), Color = Color3.fromRGB(48, 42, 34), Material = Enum.Material.SmoothPlastic })
	fuse.CFrame = spine.CFrame * CFrame.new(0.3, 1.7, 0.4) * CFrame.Angles(math.rad(22), 0, math.rad(-12)); fuse.Parent = m
	local spark = mk({ Name = "Spark", Shape = Enum.PartType.Ball, Size = Vector3.new(0.45, 0.45, 0.45),
		Color = Color3.fromRGB(255, 214, 96), Material = Enum.Material.Neon })
	spark.CFrame = fuse.CFrame * CFrame.new(0, 1.0, 0); spark.Parent = m
	local sl = Instance.new("PointLight"); sl.Color = Color3.fromRGB(255, 196, 96); sl.Brightness = 1.1; sl.Range = 7; sl.Shadows = false; sl.Parent = spark
	return m
end

-- a small held diamond (shown while carrying diamonds)
local function buildHeldGem()
	local m = Instance.new("Model"); m.Name = "HeldDiamond"
	local g = mk({ Name = "Gem", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.5, 1.1),
		Color = DIAMOND, Material = Enum.Material.Neon, Reflectance = 0.3 })
	g.Parent = m; m.PrimaryPart = g
	local pl = Instance.new("PointLight"); pl.Color = DIAMOND; pl.Brightness = 2; pl.Range = 8; pl.Parent = g
	return m
end

local function refreshHeldGem()
	if heldGem then heldGem:Destroy(); heldGem = nil end
	if carriedDiam > 0 and phase == "mine" then
		heldGem = buildHeldGem()
		weldToHand(heldGem, CFrame.new(0.2, -1.6, -0.4))
	end
end

-- ============================================================================
-- BLAST ZONE  (rock wall + painted X + crate slots)
-- ============================================================================
local function buildBlastZone()
	local m = Instance.new("Model"); m.Name = "TunnelBlastZone"; m.Parent = Workspace
	local pos, look, right = blastCF.Position, blastCF.LookVector, blastCF.RightVector
	local up = Vector3.new(0, 1, 0)

	-- the rock wall face (a slab of a few boulders so it reads chunky, not flat)
	local wall = mk({ Name = "RockWall", Size = Vector3.new(26, 22, 4), Color = ROCK, Material = Enum.Material.Rock, CanCollide = true })
	wall.CFrame = CFrame.lookAt(pos, pos + look)
	wall.Parent = m
	for i = 1, 8 do
		local b = mk({ Name = "Boulder", Size = Vector3.new(6 + (i % 3) * 3, 6 + (i % 4) * 2, 4),
			Color = (i % 2 == 0) and ROCK_DK or ROCK_LT, Material = Enum.Material.Slate, CanCollide = true })
		b.CFrame = wall.CFrame * CFrame.new(((i % 4) - 1.5) * 6.5, ((math.floor((i - 1) / 4)) - 0.5) * 9, -0.4)
			* CFrame.Angles(0, 0, math.rad((i % 5) * 6))
		b.Parent = m
	end

	-- big painted red X on the face (two crossed bars)
	local faceCF = wall.CFrame * CFrame.new(0, 1, -2.1)
	for _, rot in ipairs({ 38, -38 }) do
		local bar = mk({ Name = "XBar", Size = Vector3.new(2.4, 18, 0.3), Color = X_RED, Material = Enum.Material.Neon })
		bar.CFrame = faceCF * CFrame.Angles(0, 0, math.rad(rot))
		bar.Parent = m
	end
	local label = mk({ Name = "XGlow", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
	label.CFrame = wall.CFrame * CFrame.new(0, 9, -2.2); label.Parent = m
	local bb = Instance.new("BillboardGui"); bb.Adornee = label; bb.Size = UDim2.fromOffset(230, 50)
	bb.AlwaysOnTop = true; bb.MaxDistance = 220; bb.Parent = label
	local bt = Instance.new("TextLabel"); bt.BackgroundTransparency = 1; bt.Size = UDim2.fromScale(1, 1)
	bt.Font = Enum.Font.FredokaOne; bt.Text = "💥 BLAST ZONE"; bt.TextColor3 = X_RED
	bt.TextStrokeColor3 = Color3.new(0, 0, 0); bt.TextStrokeTransparency = 0; bt.TextScaled = true; bt.Parent = bb

	-- three crate slots along the base of the X, a couple studs out in front
	crateSlots = {}
	for i = -1, 1 do
		crateSlots[#crateSlots + 1] = {
			cf = CFrame.lookAt(pos + look * 2.4 + right * (i * 3.4) - up * 8.5, pos + look * 10),
			filled = false,
		}
	end

	-- the "place" trigger sits in front of the X; live while you carry a crate
	local zone = mk({ Name = "PlaceZone", Size = Vector3.new(14, 10, 3), Transparency = 1, CanQuery = true })
	zone.CFrame = CFrame.new(pos + look * 3 - up * 4)
	zone.Parent = m
	placePrompt = Instance.new("ProximityPrompt")
	placePrompt.ActionText = "Plant Dynamite"; placePrompt.ObjectText = "Blast Zone X"
	placePrompt.HoldDuration = 0.2; placePrompt.MaxActivationDistance = 14
	placePrompt.RequiresLineOfSight = false; placePrompt.Enabled = false; placePrompt.Parent = zone

	blastWall = m
end

-- a static crate snapped onto the next free X slot
local function snapCrateToSlot(fromPos)
	for _, slot in ipairs(crateSlots) do
		if not slot.filled then
			slot.filled = true
			local crate = buildDynamiteCrate()
			crate.Parent = blastWall
			if fromPos then
				-- THROW it onto the X: a quick arc from the player's hand to the slot
				local peak = fromPos:Lerp(slot.cf.Position, 0.5) + Vector3.new(0, 6, 0)
				crate:PivotTo(CFrame.new(fromPos))
				task.spawn(function()
					local t0, dur = os.clock(), 0.42
					while os.clock() - t0 < dur do
						local a = (os.clock() - t0) / dur
						local pos = (fromPos:Lerp(peak, a)):Lerp(peak:Lerp(slot.cf.Position, a), a)
						crate:PivotTo(CFrame.new(pos) * CFrame.Angles(a * 8, a * 6, 0))
						RunService.RenderStepped:Wait()
					end
					crate:PivotTo(slot.cf)
					screenShake(0.5, 0.15)
				end)
			else
				crate:PivotTo(slot.cf)
				screenShake(0.4, 0.15)
			end
			return
		end
	end
end

-- ============================================================================
-- THE BOOM  ->  open the shaft
-- ============================================================================
local function openShaft()
	local pos, look, up = blastCF.Position, blastCF.LookVector, Vector3.new(0, 1, 0)
	local right = blastCF.RightVector
	local m = Instance.new("Model"); m.Name = "MineShaft"; m.Parent = Workspace

	-- find the ground at the wall so the whole entrance sits flat (no floating frame/steps)
	local groundY = pos.Y - 7
	do
		local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { player.Character }
		local hit = Workspace:Raycast(pos + Vector3.new(0, 22, 0), Vector3.new(0, -120, 0), rp)
		if hit then groundY = hit.Position.Y end
	end
	local ground = Vector3.new(pos.X, groundY, pos.Z)
	local function sp(name, size, cf, color, collide, mat)
		local p = mk({ Name = name, Size = size, Color = color, Material = mat or Enum.Material.SmoothPlastic, CanCollide = collide and true or false })
		p.CFrame = cf; p.Parent = m; return p
	end

	-- ---- an enclosed dark tunnel throat with receding timber arches -> real depth through the portal
	local tbasis = CFrame.fromMatrix(Vector3.new(), right, up)  -- X=right, Y=up, Z=depth (along the look axis)
	local function tslab(name, w, h, dep, ox, oy, oz, color)
		sp(name, Vector3.new(w, h, dep), tbasis + (ground + right * ox + up * oy - look * oz), color, true)
	end
	tslab("ThroatCeil",  17, 2, 28, 0, 15, 13, Color3.fromRGB(16, 14, 13))
	tslab("ThroatFloor", 17, 2, 28, 0, -0.6, 13, Color3.fromRGB(22, 20, 18))
	tslab("ThroatWallL", 2, 17, 28, -8.5, 7, 13, Color3.fromRGB(18, 16, 15))
	tslab("ThroatWallR", 2, 17, 28, 8.5, 7, 13, Color3.fromRGB(18, 16, 15))
	tslab("ThroatEnd",   17, 17, 2, 0, 7, 26, Color3.fromRGB(9, 8, 8))
	-- receding wooden support arches (smaller + darker as they go in)
	for i = 1, 4 do
		local d = 4 + i * 4.6; local w = 12 - i * 1.5; local hgt = 12.5 - i * 1.3; local b = 0.92 - i * 0.13
		local wcol = Color3.fromRGB(112 * b, 76 * b, 44 * b)
		for _, s in ipairs({ -1, 1 }) do
			sp("ArchPost", Vector3.new(1.1, hgt, 1.1), CFrame.new(ground - look * d + right * s * (w / 2) + up * (hgt / 2)), wcol, false)
		end
		sp("ArchTop", Vector3.new(w + 1.2, 1.1, 1.1), CFrame.new(ground - look * d + up * hgt), wcol, false)
	end
	-- glowing crystals deep in the tunnel + a coloured wash you can see from outside
	for _, c in ipairs({ { -3, 3, 3 }, { 3.5, 2.4, 4 }, { 0, 8, 1 } }) do
		local col = CRYSTAL_COLS[c[3]]
		sp("DeepCrystal", Vector3.new(1.3, 3 + math.random() * 2, 1.3), CFrame.new(ground - look * 20 + right * c[1] + up * c[2]) * CFrame.Angles(math.rad((math.random() - 0.5) * 40), math.random() * 3, 0), col, false, Enum.Material.Neon)
	end
	local deepGlowP = sp("DeepGlow", Vector3.new(1, 1, 1), CFrame.new(ground - look * 20 + up * 5), CRYSTAL_COLS[3]); deepGlowP.Transparency = 1
	local dgl = Instance.new("PointLight"); dgl.Color = CRYSTAL_COLS[3]; dgl.Brightness = 0.09; dgl.Range = 7; dgl.Shadows = false; dgl.Parent = deepGlowP

	-- timber portal: two posts + a double lintel + angled corner braces + head planks
	for _, s in ipairs({ -7, 7 }) do
		sp("Post", Vector3.new(1.5, 15, 1.5), CFrame.new(ground + right * s + up * 7), Color3.fromRGB(104, 70, 40), true)
	end
	sp("Lintel", Vector3.new(16.5, 1.7, 1.9), CFrame.new(ground + up * 14), Color3.fromRGB(88, 58, 32), true)
	sp("Lintel2", Vector3.new(16, 1.1, 1.4), CFrame.new(ground + up * 12.6), Color3.fromRGB(112, 76, 42))
	for _, s in ipairs({ -1, 1 }) do
		sp("Brace", Vector3.new(1.1, 5, 1.1), CFrame.new(ground + right * s * 5.6 + up * 12) * CFrame.Angles(0, 0, math.rad(s * 42)), Color3.fromRGB(96, 64, 36))
	end
	for i = -1, 1 do
		sp("Plank", Vector3.new(15.5, 0.4, 0.5), CFrame.new(ground + up * (13 + i * 0.7) - look * 0.6), Color3.fromRGB(122, 84, 48))
	end

	-- stone steps + rails descending into the dark
	for i = 0, 6 do
		sp("Step", Vector3.new(10, 1, 2.6), CFrame.new(ground - look * (1.6 + i * 2.4) + up * (0.5 - i * 0.9)), Color3.fromRGB(122, 124, 134), true)
	end
	for _, rz in ipairs({ -2.6, 2.6 }) do
		sp("Rail", Vector3.new(0.3, 0.3, 16), CFrame.lookAt(ground - look * 2 + right * rz + up * 0.3, ground - look * 15 - up * 5), Color3.fromRGB(120, 124, 132))
	end

	-- hanging wooden "THE MINE" sign over the entrance
	local sign = sp("MineSign", Vector3.new(6.5, 2.4, 0.4), CFrame.new(ground + up * 16.4 + look * 0.4), Color3.fromRGB(120, 82, 46))
	sp("SignChainL", Vector3.new(0.12, 1.6, 0.12), CFrame.new(ground + right * -2 + up * 15.3 + look * 0.4), Color3.fromRGB(80, 82, 90))
	sp("SignChainR", Vector3.new(0.12, 1.6, 0.12), CFrame.new(ground + right * 2 + up * 15.3 + look * 0.4), Color3.fromRGB(80, 82, 90))

	-- lanterns flanking the portal (warm glow, gently flickering)
	local lanternLights = {}
	for _, s in ipairs({ -8, 8 }) do
		sp("LanternPost", Vector3.new(0.4, 0.5, 0.4), CFrame.new(ground + right * s + up * 10.6), Color3.fromRGB(70, 58, 30))
		local gl = sp("LanternGlow", Vector3.new(1, 1.3, 1), CFrame.new(ground + right * s + up * 10), Color3.fromRGB(255, 196, 110))
		gl.Material = Enum.Material.Neon; gl.Shape = Enum.PartType.Ball
		local pl = Instance.new("PointLight"); pl.Color = Color3.fromRGB(255, 190, 120); pl.Brightness = 0.11; pl.Range = 7; pl.Shadows = false; pl.Parent = gl
		pl:SetAttribute("ph", #lanternLights * 2.1); lanternLights[#lanternLights + 1] = pl
	end

	-- ---- a CLEAN cut-stone surround framing the timber portal (polished, symmetric) ----
	for _, s in ipairs({ -1, 1 }) do
		sp("StonePillar", Vector3.new(3, 17, 3), CFrame.new(ground + right * s * 9.5 + up * 8), Color3.fromRGB(150, 152, 160), true)
		sp("StonePillarCap", Vector3.new(3.6, 1.4, 3.6), CFrame.new(ground + right * s * 9.5 + up * 16.4), Color3.fromRGB(166, 168, 176), true)
		sp("StonePillarBase", Vector3.new(3.6, 1.2, 3.6), CFrame.new(ground + right * s * 9.5 + up * 0.6), Color3.fromRGB(138, 140, 148), true)
	end
	-- a stepped stone arch across the top (3 tidy tiers)
	for i = 0, 2 do
		sp("StoneArch", Vector3.new(22 - i * 3.5, 1.6, 3), CFrame.new(ground + up * (17.4 + i * 1.6)), (i % 2 == 0) and Color3.fromRGB(156, 158, 166) or Color3.fromRGB(142, 144, 152), true)
	end

	-- ---- a clean stone threshold you approach on + a few path tiles leading up to it ----
	sp("ThresholdTrim", Vector3.new(21, 0.6, 13), CFrame.new(ground + look * 5 - up * 0.9), Color3.fromRGB(122, 124, 134), true)
	sp("Threshold", Vector3.new(19, 1, 11.5), CFrame.new(ground + look * 5 - up * 0.3), Color3.fromRGB(152, 154, 162), true)
	for i = 1, 3 do
		sp("PathTile", Vector3.new(6, 0.4, 3.2), CFrame.new(ground + look * (11 + i * 3.7) - up * 0.5),
			(i % 2 == 0) and Color3.fromRGB(140, 142, 150) or Color3.fromRGB(158, 160, 168), true)
	end

	-- two TIDY little rock piles at the base corners (kept neat, not scattered everywhere)
	for _, s in ipairs({ -1, 1 }) do
		for k = 1, 3 do
			sp("Rubble", Vector3.new(1.6 + k * 0.35, 1.2 + k * 0.2, 1.6 + k * 0.35),
				CFrame.new(ground + right * s * 8 + look * 3.5 + up * (0.5 + k * 0.1) + right * s * (k - 2) * 0.7) * CFrame.Angles(k, k * 1.2, k),
				(k % 2 == 0) and Color3.fromRGB(122, 124, 134) or Color3.fromRGB(148, 150, 158), true)
		end
	end

	-- warm glow spilling out + a subtle dust plume from the opening
	local glowP = sp("ShaftGlow", Vector3.new(1, 1, 1), CFrame.new(ground - look * 3 + up * 6), FLAME); glowP.Transparency = 1
	local glow = Instance.new("PointLight"); glow.Color = FLAME; glow.Brightness = 0.17; glow.Range = 10; glow.Shadows = false; glow.Parent = glowP
	local att = Instance.new("Attachment"); att.Parent = glowP
	local dust = Instance.new("ParticleEmitter"); dust.Color = ColorSequence.new(Color3.fromRGB(160, 148, 130)); dust.Size = NumberSequence.new(4)
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.82), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(2, 4); dust.Rate = 3; dust.Speed = NumberRange.new(1, 3); dust.Acceleration = Vector3.new(0, 2, 0); dust.Parent = att

	-- glowing crystal accents growing on/around the portal frame
	for _, spec in ipairs({ { -7.6, 10, 1 }, { 7.6, 12, 3 }, { -4, 0.9, 2 }, { 4.5, 0.9, 4 } }) do
		local col = CRYSTAL_COLS[spec[3]]
		local cr = sp("PortalCrystal", Vector3.new(1.2, 4 + math.random() * 2, 1.2),
			CFrame.new(ground + right * spec[1] + up * spec[2] + look * 1.2) * CFrame.Angles(math.rad((math.random() - 0.5) * 40), math.random() * 3, math.rad((math.random() - 0.5) * 40)),
			col, false, Enum.Material.Neon)
		if spec[2] > 5 then local pl = Instance.new("PointLight"); pl.Color = col; pl.Brightness = 0.06; pl.Range = 5; pl.Shadows = false; pl.Parent = cr end
	end

	-- a parked minecart off to one side of the entrance (a few coloured ore lumps inside)
	do
		local cp = ground + look * 2 + right * 10 + up * 1.6
		sp("EntryCart", Vector3.new(4.4, 2.6, 3.4), CFrame.new(cp), STEEL, true)
		sp("EntryCartIn", Vector3.new(3.8, 2.2, 2.8), CFrame.new(cp + up * 0.4), Color3.fromRGB(40, 42, 46))
		for k = 1, 3 do
			sp("OreLump", Vector3.new(1, 1, 1), CFrame.new(cp + Vector3.new((k - 2) * 0.9, 1.5, 0)) * CFrame.Angles(k, k, k), CRYSTAL_COLS[k], false, Enum.Material.Neon)
		end
		for _, wx in ipairs({ -1.4, 1.4 }) do
			for _, wz in ipairs({ -1.3, 1.3 }) do
				local wheel = sp("Wheel", Vector3.new(0.5, 1.3, 1.3), CFrame.new(cp + Vector3.new(wx, -1.5, wz)) * CFrame.Angles(0, 0, math.rad(90)), STEEL_DK)
				wheel.Shape = Enum.PartType.Cylinder
			end
		end
	end

	-- gentle animated flicker on the lanterns + a breathing glow at the mouth (stops with the shaft)
	task.spawn(function()
		local t = 0
		while m.Parent do
			t = t + 0.12
			if glow then glow.Brightness = 0.15 + math.sin(t * 3) * 0.5 + math.random() * 0.2 end
			for _, lp in ipairs(lanternLights) do lp.Brightness = 0.10 + math.abs(math.sin(t * 2 + (lp:GetAttribute("ph") or 0))) * 0.5 end
			task.wait(0.12)
		end
	end)

	-- the "descend" trigger + a big readable label on the sign
	local enter = mk({ Name = "EnterZone", Size = Vector3.new(13, 15, 7), Transparency = 1, CanQuery = true })
	enter.CFrame = CFrame.new(ground + up * 7); enter.Parent = m
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = "Enter the Mine"; pr.ObjectText = "Mine Shaft"; pr.HoldDuration = 0.3
	pr.MaxActivationDistance = 16; pr.RequiresLineOfSight = false; pr.Parent = enter
	pr.Triggered:Connect(function() if phase == "descend" then enterMine() end end)

	local bb = Instance.new("BillboardGui"); bb.Adornee = sign; bb.Size = UDim2.fromOffset(240, 78)
	bb.StudsOffset = Vector3.new(0, 2.4, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 220; bb.Parent = sign
	local t1 = Instance.new("TextLabel"); t1.BackgroundTransparency = 1; t1.Size = UDim2.new(1, 0, 0.6, 0)
	t1.Font = Enum.Font.FredokaOne; t1.Text = "⛏️ THE MINE"; t1.TextColor3 = Color3.fromRGB(255, 214, 120)
	t1.TextStrokeColor3 = Color3.new(0, 0, 0); t1.TextStrokeTransparency = 0; t1.TextScaled = true; t1.Parent = bb
	local t2 = Instance.new("TextLabel"); t2.BackgroundTransparency = 1; t2.Position = UDim2.new(0, 0, 0.6, 0)
	t2.Size = UDim2.new(1, 0, 0.4, 0); t2.Font = Enum.Font.FredokaOne; t2.Text = "[E] Enter"
	t2.TextColor3 = Color3.fromRGB(255, 245, 220); t2.TextStrokeColor3 = Color3.new(0, 0, 0); t2.TextStrokeTransparency = 0; t2.TextScaled = true; t2.Parent = bb

	mineShaft = m
	surfaceReturnCF = CFrame.new(ground + look * 9 + up * 4)  -- pop out here when you leave the mine
end

-- ============================================================================
-- THE ISLAND SHIFTS  (the moment the cave opens)
-- ============================================================================
-- Blowing a hole into a mountain should be felt across the whole island, not just at the wall
-- you were standing at. This runs for about two and a half seconds and does four things at
-- once, because any one of them alone reads as an effect rather than an event:
--
--   RUMBLE    a sustained shake that BUILDS and then decays, not a single jolt. One sharp
--             knock says "explosion"; a long low roll says "the ground is moving".
--   ROCKS     debris raining down all around you, not just at the blast -- that is what makes
--             it the island reacting rather than one wall breaking.
--   DUST      curtains of it falling out of the air at several points, drifting rather than
--             puffing, so it settles for seconds afterwards.
--   FRAMING   letterbox bars and a lens punch. Cheap, and it is what tells the player to stop
--             playing for a moment and watch.
local function islandQuake(at, seconds)
	seconds = seconds or 2.6
	local cam = Workspace.CurrentCamera

	-- ---- FRAMING: a lens punch only. The letterbox bars are gone -- black edges on the screen
	-- read as a cutscene taking the game off you, and the shake alone does the cinematic job
	-- without covering anything up.
	local fov0 = cam and cam.FieldOfView or 70
	if cam then
		TweenService:Create(cam, TweenInfo.new(0.28, Enum.EasingStyle.Back), { FieldOfView = fov0 + 14 }):Play()
	end

	-- ---- RUMBLE: builds over the first third, holds, then rolls off
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < seconds do
			local u = (os.clock() - t0) / seconds
			-- HARD. The build is quick and the decay is long, so it hits you and then keeps
			-- rolling. Displacement AND rotation on all three axes -- shifting the camera alone
			-- reads as a rattle; turning it as well reads as the ground itself moving.
			local m = (u < 0.18) and (u / 0.18) or (1 - (u - 0.18) / 0.82) ^ 1.3
			m *= 4.2
			if cam then
				cam.CFrame = cam.CFrame
					* CFrame.new((math.random() - 0.5) * m,
					             (math.random() - 0.5) * m,
					             (math.random() - 0.5) * m * 0.5)
					* CFrame.Angles((math.random() - 0.5) * m * 0.016,
					                (math.random() - 0.5) * m * 0.016,
					                (math.random() - 0.5) * m * 0.030)
			end
			RunService.RenderStepped:Wait()
		end
		if cam then
			TweenService:Create(cam, TweenInfo.new(0.5), { FieldOfView = fov0 }):Play()
		end
	end)

	-- ---- ROCKS: they come down all over, at staggered times, and burst into dust on landing
	task.spawn(function()
		local hrp = hrpOf()
		local base = (hrp and hrp.Position) or at
		for i = 1, 26 do
			task.delay(0.15 + math.random() * (seconds - 0.6), function()
				local a  = math.random() * math.pi * 2
				local r  = 18 + math.random() * 110
				local gx = base.X + math.cos(a) * r
				local gz = base.Z + math.sin(a) * r
				local sz = 1.0 + math.random() * 2.6
				local rock = mk({ Name = "Debris", Size = Vector3.new(sz, sz * 0.8, sz * 0.9),
					Color = (i % 2 == 0) and ROCK_DK or ROCK, Material = Enum.Material.Rock })
				rock.CFrame = CFrame.new(gx, base.Y + 70 + math.random() * 50, gz)
				rock.Parent = Workspace
				local land = CFrame.new(gx, base.Y - 2, gz)
					* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
				TweenService:Create(rock, TweenInfo.new(0.85, Enum.EasingStyle.Quad,
					Enum.EasingDirection.In), { CFrame = land }):Play()
				task.delay(0.85, function()
					-- a puff where it lands, so the rock arrives somewhere instead of just stopping
					local att = Instance.new("Attachment")
					att.WorldPosition = Vector3.new(gx, base.Y, gz); att.Parent = Workspace.Terrain
					local pe = Instance.new("ParticleEmitter")
					pe.Color = ColorSequence.new(Color3.fromRGB(150, 138, 122))
					pe.Size = NumberSequence.new(4)
					pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45),
						NumberSequenceKeypoint.new(1, 1) })
					pe.Lifetime = NumberRange.new(0.8, 1.6); pe.Rate = 0
					pe.Speed = NumberRange.new(3, 9); pe.SpreadAngle = Vector2.new(120, 120)
					pe.Parent = att; pe:Emit(14)
					Debris:AddItem(att, 2.4)
					TweenService:Create(rock, TweenInfo.new(0.5), { Transparency = 1 }):Play()
				end)
				Debris:AddItem(rock, 1.6)
			end)
		end
	end)

	-- ---- DUST: curtains sifting out of the air around you, drifting DOWN and lingering
	task.spawn(function()
		local hrp = hrpOf()
		local base = (hrp and hrp.Position) or at
		for i = 1, 7 do
			local a = (i / 7) * math.pi * 2
			local att = Instance.new("Attachment")
			att.WorldPosition = base + Vector3.new(math.cos(a) * 55, 34, math.sin(a) * 55)
			att.Parent = Workspace.Terrain
			local pe = Instance.new("ParticleEmitter")
			pe.Color = ColorSequence.new(Color3.fromRGB(158, 146, 130))
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6),
				NumberSequenceKeypoint.new(1, 16) })
			pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.55), NumberSequenceKeypoint.new(1, 1) })
			pe.Lifetime = NumberRange.new(2.4, 4.2)
			pe.Rate = 9; pe.Speed = NumberRange.new(1, 4)
			pe.SpreadAngle = Vector2.new(60, 60)
			pe.Acceleration = Vector3.new(0, -7, 0)
			pe.Parent = att
			task.delay(seconds, function() pe.Rate = 0 end)
			Debris:AddItem(att, seconds + 5)
		end
	end)
end

local function detonate()
	if busy then return end
	busy = true
	if placePrompt then placePrompt.Enabled = false end
	if tntPrompt then tntPrompt.Enabled = false end
	-- clear any leftover ground crates so none linger after the blast
	for _, c in ipairs(groundCrates) do if c and c.Parent then c:Destroy() end end
	groundCrates = {}
	local pos = blastCF.Position

	-- 3..2..1
	for i = 3, 1, -1 do
		showCard(tostring(i))
		screenShake(0.5, 0.3)
		task.wait(0.75)
	end
	showCard("💥 BOOM! 💥", 1.4)

	-- flash
	local flash = Instance.new("ScreenGui"); flash.IgnoreGuiInset = true; flash.DisplayOrder = 25; flash.Parent = PlayerGui
	local ff = Instance.new("Frame"); ff.Size = UDim2.fromScale(1, 1); ff.BackgroundColor3 = Color3.fromRGB(255, 240, 210)
	ff.BackgroundTransparency = 0.1; ff.BorderSizePixel = 0; ff.Parent = flash
	TweenService:Create(ff, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(flash, 0.7)
	-- the whole island moves, not just the wall you were stood at
	islandQuake(pos, 2.6)

	-- debris + dust from the wall, then remove it
	for i = 1, 24 do
		local chunk = mk({ Name = "Debris", Size = Vector3.new(1.4 + (i % 3), 1.4 + (i % 2), 1.4 + (i % 4)),
			Color = (i % 2 == 0) and ROCK_DK or ROCK, Material = Enum.Material.Rock })
		chunk.CFrame = CFrame.new(pos + Vector3.new((math.random() - 0.5) * 8, (math.random()) * 6, (math.random() - 0.5) * 4))
		chunk.Parent = Workspace
		local dir = Vector3.new((math.random() - 0.5) * 2, math.random() * 1.6 + 0.4, (math.random() - 0.5) * 2)
		TweenService:Create(chunk, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(pos + dir * 26) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), Transparency = 1 }):Play()
		Debris:AddItem(chunk, 1.1)
	end
	local dustAtt = Instance.new("Attachment"); dustAtt.WorldPosition = pos; dustAtt.Parent = Workspace.Terrain
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(Color3.fromRGB(150, 138, 122)); dust.Size = NumberSequence.new(10)
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(1.2, 2.2); dust.Rate = 0; dust.Speed = NumberRange.new(6, 14)
	dust.SpreadAngle = Vector2.new(180, 180); dust.Parent = dustAtt
	dust:Emit(60); Debris:AddItem(dustAtt, 3)

	task.wait(0.35)
	if blastWall then blastWall:Destroy(); blastWall = nil end
	openShaft()

	phase = "descend"
	busy = false
	updateObjective()
	notify("💥 The tunnel is open! Enter the mine shaft.", FLAME)
	pointTo(blastCF.Position)
end

-- ============================================================================
-- UNDERGROUND MINE  (built locally -> private to this player)
-- ============================================================================
local oreNodes = {}   -- { model=, prompt=, hp=, broken=bool }
local mineCart, cartFillParts = nil, {}
local exitPrompt

-- ============================================================================
-- MINER'S GEAR  (hard hat + pack)
-- ============================================================================
-- The same wood-framed pack the camp on island 14 hands out, re-cut in mining colours, plus a
-- hard hat -- and the hat is not decoration: its lamp is a real light pointed wherever you
-- look, and the mine is dark. Both are WELDED, never anchored and re-positioned each frame,
-- which is what makes a prop read as worn rather than as floating alongside you.
-- ONE DIAL FOR THE HAT. Every size and offset below is multiplied by it, so resizing is one
-- number instead of a dozen -- and, more to the point, the offsets scale WITH the sizes, so it
-- never ends up a bigger dome sitting at the old height with its brim through your eyebrows.
local HAT_SCALE = 0.95

-- FIT THE HAT TO THE HEAD THAT IS WEARING IT.
--
-- A fixed-size hat is wrong on almost everybody: hair, horns and hoods are accessories with
-- their own sizes, so the same dome that sits neatly on a bald head has a fringe growing
-- through it on the next player. This measures the head AND every accessory attached to it, in
-- the head's own frame, and returns how wide and how tall the hat has to be to swallow them.
--
-- Distance-gated to 6 studs so it measures headwear and not a back accessory or a tool.
local function headExtent(char, head)
	local rad = math.max(head.Size.X, head.Size.Z) * 0.5
	local top = head.Size.Y * 0.5
	for _, a in ipairs(char:GetChildren()) do
		if a:IsA("Accessory") then
			local h = a:FindFirstChild("Handle")
			if h and h:IsA("BasePart") and (h.Position - head.Position).Magnitude < 6 then
				local o, s = head.CFrame:PointToObjectSpace(h.Position), h.Size * 0.5
				rad = math.max(rad, math.abs(o.X) + s.X, math.abs(o.Z) + s.Z)
				top = math.max(top, o.Y + s.Y)
			end
		end
	end
	return rad, top
end

-- Grow the hat until it covers that, then RAISE it until its crown clears the tallest thing on
-- the head -- growing alone would leave a tall hairstyle poking straight out of the top.
--
-- FIT ON THE BRIM, NOT THE DOME. The brim is 1.66 wide at scale 1 against the dome's 1.30, so
-- it is the brim that does the covering -- and sizing off the narrower dome grew the whole hat
-- about a quarter larger than it needed to be to cover the same hair. Radii at scale 1: brim
-- 0.83, dome 0.65, dome half-height 0.54.
local function fitHat(char, head, base)
	local rad, top = headExtent(char, head)
	local H    = math.clamp(math.max(base, (rad + 0.03) / 0.83), base, 1.55)
	local seat = math.max(0.52 * H, top + 0.05 - 0.54 * H)
	return H, seat
end

-- Anything still standing proud of the crown after all that is taller than a hat can sensibly
-- be -- some hair pieces are half a metre of spikes. Those get hidden while the hat is on
-- rather than growing the hat into something comical, and put back when it comes off.
local function tuckHair(char, head, seat, H, store)
	local crown = seat + 0.54 * H
	for _, a in ipairs(char:GetChildren()) do
		if a:IsA("Accessory") then
			local h = a:FindFirstChild("Handle")
			if h and h:IsA("BasePart") and (h.Position - head.Position).Magnitude < 6 then
				local o, s = head.CFrame:PointToObjectSpace(h.Position), h.Size * 0.5
				if o.Y + s.Y > crown then
					store[h] = h.Transparency
					h.Transparency = 1
				end
			end
		end
	end
end

local minerGear
local hidHair = {}
local function takeGear()
	if minerGear then minerGear:Destroy(); minerGear = nil end
	for h, t in pairs(hidHair) do if h and h.Parent then h.Transparency = t end end
	hidHair = {}
end

local function giveGear()
	if minerGear then return end
	local char  = player.Character
	local head  = char and char:FindFirstChild("Head")
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
	if not (head and torso) then return end

	minerGear = Instance.new("Folder"); minerGear.Name = "MinerGear"; minerGear.Parent = char

	-- weld everything to one root per item, then that root to the body: one joint to place,
	-- and the whole thing moves with the animation instead of chasing it
	local function rig(host, parent, cf, parts)
		local root
		for i, q in ipairs(parts) do
			local p = mk(q.props)
			p.Anchored = false; p.CanCollide = false; p.CanQuery = false; p.Massless = true
			p.CFrame = parent.CFrame * cf * q.at
			p.Parent = host
            if i == 1 then root = p end
		end
		for _, p in ipairs(host:GetChildren()) do
			if p:IsA("BasePart") and p ~= root then
				local wc = Instance.new("WeldConstraint"); wc.Part0 = root; wc.Part1 = p; wc.Parent = root
			end
		end
		local w = Instance.new("Weld")
		w.Part0 = parent; w.Part1 = root; w.C0 = cf; w.Parent = root
		return root
	end

	-- ---- THE HARD HAT. Half the size it was and genuinely round: the dome is a BALL squashed
	-- on Y, not a box, and the brim and band are cylinders. A hard hat is the one piece of kit
	-- with no flat faces on it, so building it out of blocks fought the shape the whole way.
	-- Its lower half sits inside the head, which is what gives the dome its clean rim.
	local hat = Instance.new("Model"); hat.Name = "HardHat"; hat.Parent = minerGear
	local H, seat = fitHat(char, head, HAT_SCALE)
	tuckHair(char, head, seat, H, hidHair)
	rig(hat, head, CFrame.new(0, seat, 0), {
		{ props = { Shape = Enum.PartType.Ball, Color = FLAME,
			Size = Vector3.new(1.30, 1.08, 1.30) * H }, at = CFrame.new() },
		{ props = { Shape = Enum.PartType.Cylinder, Color = FLAME,
			Size = Vector3.new(0.11, 1.66, 1.66) * H },
			at = CFrame.new(0, -0.30 * H, 0) * CFrame.Angles(0, 0, math.rad(90)) },
		{ props = { Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(214, 112, 30),
			Size = Vector3.new(0.26, 1.34, 1.34) * H },
			at = CFrame.new(0, -0.17 * H, 0) * CFrame.Angles(0, 0, math.rad(90)) },
		-- the peak, pulled forward over the lamp
		{ props = { Shape = Enum.PartType.Cylinder, Color = FLAME,
			Size = Vector3.new(0.11, 1.10, 1.10) * H },
			at = CFrame.new(0, -0.28 * H, -0.44 * H) * CFrame.Angles(0, 0, math.rad(90)) },
		{ props = { Color = STEEL_DK, Size = Vector3.new(0.30, 0.24, 0.18) * H },
			at = CFrame.new(0, -0.05 * H, -0.60 * H) },
		-- chin strap, down past the ears
		{ props = { Color = STEEL_DK, Size = Vector3.new(0.08, 0.62, 0.08) * H },
			at = CFrame.new(-0.62 * H, -0.52 * H, 0) },
		{ props = { Color = STEEL_DK, Size = Vector3.new(0.08, 0.62, 0.08) * H },
			at = CFrame.new(0.62 * H, -0.52 * H, 0) },
	})

	-- the lamp itself, welded on separately so it can carry the light
	local lamp = mk({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(255, 246, 200),
		Material = Enum.Material.Neon, Size = Vector3.new(0.10, 0.30, 0.30) * HAT_SCALE })
	-- (lamp size stays on the dial; only where it sits follows the fitted hat)
	lamp.Name = "HatLamp"
	lamp.Anchored = false; lamp.CanCollide = false; lamp.CanQuery = false; lamp.Massless = true
	-- the lens is a disc, so it has to be turned to FACE forward: a cylinder's flat faces are on
	-- its X axis, and unrotated that points out of your ear
	local lampCF = CFrame.new(0, seat - 0.05 * H, -0.72 * H) * CFrame.Angles(0, math.rad(90), 0)
	lamp.CFrame = head.CFrame * lampCF
	lamp.Parent = hat
	local lw = Instance.new("Weld")
	lw.Part0 = head; lw.Part1 = lamp; lw.C0 = lampCF; lw.Parent = lamp

	-- THE BEAM GETS ITS OWN AIM PART, unrotated, so it points wherever the head points.
	-- Hanging the light off the lens meant the beam followed whatever rotation the ART needed --
	-- turn the lens to look right and the beam swings off with it, which is exactly what
	-- happened: it was lighting the wall to your left instead of what you were looking at.
	local aim = mk({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2) })
	aim.Name = "LampAim"
	aim.Anchored = false; aim.CanCollide = false; aim.CanQuery = false; aim.Massless = true
	local aimCF = CFrame.new(0, seat - 0.05 * H, -0.72 * H)
	aim.CFrame = head.CFrame * aimCF
	aim.Parent = hat
	local aw = Instance.new("Weld")
	aw.Part0 = head; aw.Part1 = aim; aw.C0 = aimCF; aw.Parent = aim

	-- A SPOTLIGHT, not a point light: a headlamp throws a cone the way you are facing. A point
	-- light on your head just raises the brightness of the room and the cave stops being dark.
	-- Front is -Z, which is the way a character faces.
	local beam = Instance.new("SpotLight")
	beam.Color = Color3.fromRGB(255, 244, 214); beam.Brightness = 4.2
	beam.Range = 55; beam.Angle = 58; beam.Face = Enum.NormalId.Front
	beam.Shadows = true; beam.Parent = aim

	-- ---- THE PACK: the island 14 shape in mining colours -- frame, sack, rolled top, bedroll
	local pack = Instance.new("Model"); pack.Name = "MinerPack"; pack.Parent = minerGear
	rig(pack, torso, CFrame.new(0, 0.1, 0.92), {
		{ props = { Color = DIRT, Size = Vector3.new(1.8, 1.7, 0.9) }, at = CFrame.new() },
		-- FRAME UPRIGHTS, ENDING AT THE PACK. They used to run 2.8 studs from a low centre, so
		-- they came out under the sack like a pair of poles growing out of your back.
		{ props = { Color = WOOD_DK, Size = Vector3.new(0.18, 2.1, 0.18) }, at = CFrame.new(-0.85, 0.2, 0.52) },
		{ props = { Color = WOOD_DK, Size = Vector3.new(0.18, 2.1, 0.18) }, at = CFrame.new(0.85, 0.2, 0.52) },
		{ props = { Color = WOOD, Size = Vector3.new(1.9, 0.16, 0.16) },  at = CFrame.new(0, 1.16, 0.52) },
		{ props = { Color = WOOD, Size = Vector3.new(1.9, 0.16, 0.16) },  at = CFrame.new(0, -0.76, 0.52) },
		-- rounded pads where the straps cross your shoulders: the one place a pack touches you
		{ props = { Shape = Enum.PartType.Cylinder, Color = WOOD_DK, Size = Vector3.new(0.9, 0.42, 0.42) },
			at = CFrame.new(-0.6, 0.92, -0.44) * CFrame.Angles(0, 0, math.rad(90)) },
		{ props = { Shape = Enum.PartType.Cylinder, Color = WOOD_DK, Size = Vector3.new(0.9, 0.42, 0.42) },
			at = CFrame.new(0.6, 0.92, -0.44) * CFrame.Angles(0, 0, math.rad(90)) },
		{ props = { Color = DIRT, Size = Vector3.new(1.4, 0.7, 0.75) },   at = CFrame.new(0, -1.1, -0.02) },
		{ props = { Shape = Enum.PartType.Cylinder, Color = DIRT, Size = Vector3.new(1.75, 0.46, 0.46) },
			at = CFrame.new(0, 1.0, 0) * CFrame.Angles(0, 0, math.rad(90)) },
		{ props = { Color = WOOD_DK, Size = Vector3.new(1.85, 0.6, 0.96) }, at = CFrame.new(0, 0.78, 0.02) },
		{ props = { Color = STEEL_DK, Size = Vector3.new(0.3, 0.28, 0.14) }, at = CFrame.new(-0.45, 0.2, 0.5) },
		{ props = { Color = STEEL_DK, Size = Vector3.new(0.3, 0.28, 0.14) }, at = CFrame.new(0.45, 0.2, 0.5) },
		-- bedroll slung under it
		{ props = { Shape = Enum.PartType.Cylinder, Color = ROCK_LT, Size = Vector3.new(1.9, 0.6, 0.6) },
			at = CFrame.new(0, -1.45, 0.06) * CFrame.Angles(0, 0, math.rad(90)) },
		-- shoulder straps, over the shoulder and down the chest
		{ props = { Color = WOOD_DK, Size = Vector3.new(0.3, 0.24, 1.4) },
			at = CFrame.new(-0.6, 0.86, -0.58) * CFrame.Angles(math.rad(18), 0, 0) },
		{ props = { Color = WOOD_DK, Size = Vector3.new(0.3, 0.24, 1.4) },
			at = CFrame.new(0.6, 0.86, -0.58) * CFrame.Angles(math.rad(18), 0, 0) },
		{ props = { Color = WOOD_DK, Size = Vector3.new(0.3, 1.4, 0.22) },
			at = CFrame.new(-0.62, 0.06, -1.44) * CFrame.Angles(math.rad(-9), 0, 0) },
		{ props = { Color = WOOD_DK, Size = Vector3.new(0.3, 1.4, 0.22) },
			at = CFrame.new(0.62, 0.06, -1.44) * CFrame.Angles(math.rad(-9), 0, 0) },
		-- a spare pick strapped to the side, so it reads as mining kit and not luggage
		{ props = { Color = WOOD, Size = Vector3.new(0.14, 1.6, 0.14) },
			at = CFrame.new(0.98, 0.2, 0.5) * CFrame.Angles(0, 0, math.rad(-10)) },
		{ props = { Color = STEEL, Size = Vector3.new(1.0, 0.16, 0.16) }, at = CFrame.new(1.12, 0.95, 0.5) },
		-- compression straps round the sack, and a pad on the base it stands on
		{ props = { Color = WOOD_DK, Size = Vector3.new(1.86, 0.14, 0.94) }, at = CFrame.new(0, 0.34, 0.01) },
		{ props = { Color = WOOD_DK, Size = Vector3.new(1.86, 0.14, 0.94) }, at = CFrame.new(0, -0.36, 0.01) },
		{ props = { Color = ROCK_DK, Size = Vector3.new(1.7, 0.18, 0.86) }, at = CFrame.new(0, -0.92, 0) },
		-- a haul loop on top and lash loops down the side: it is the bits you would grab hold of
		-- that make a bag read as carried rather than modelled
		{ props = { Color = WOOD_DK, Size = Vector3.new(0.5, 0.16, 0.16) }, at = CFrame.new(0, 1.5, -0.3) },
		{ props = { Color = WOOD_DK, Size = Vector3.new(0.16, 0.3, 0.16) }, at = CFrame.new(-0.22, 1.38, -0.3) },
		{ props = { Color = WOOD_DK, Size = Vector3.new(0.16, 0.3, 0.16) }, at = CFrame.new(0.22, 1.38, -0.3) },
		{ props = { Color = WOOD_DK, Size = Vector3.new(0.14, 0.26, 0.3) }, at = CFrame.new(-0.94, 0.2, 0.42) },
		{ props = { Color = WOOD_DK, Size = Vector3.new(0.14, 0.26, 0.3) }, at = CFrame.new(-0.94, -0.4, 0.42) },
		-- end caps on the bedroll: a bare cylinder reads as pipe, capped it reads as a roll
		{ props = { Shape = Enum.PartType.Cylinder, Color = ROCK, Size = Vector3.new(0.1, 0.64, 0.64) },
			at = CFrame.new(-0.95, -1.45, 0.06) * CFrame.Angles(0, 0, math.rad(90)) },
		{ props = { Shape = Enum.PartType.Cylinder, Color = ROCK, Size = Vector3.new(0.1, 0.64, 0.64) },
			at = CFrame.new(0.95, -1.45, 0.06) * CFrame.Angles(0, 0, math.rad(90)) },
	})

	print(("[TunnelQuest] miner's gear issued -- hat fitted at %.2f scale, %d hair piece(s) tucked")
		:format(H, (function() local n = 0; for _ in pairs(hidHair) do n += 1 end; return n end)()))
end

-- a respawn drops both welds with the old character, so put them back on
player.CharacterAdded:Connect(function()
	minerGear = nil
	task.delay(1.6, function()
		if phase ~= "idle" and phase ~= "done" then giveGear() end
	end)
end)

-- ============================================================================
-- THE DRILL  (HUD)
-- ============================================================================
-- HOLD TO DRILL. Depth climbs while you hold and the bit heats up; let go and it cools but the
-- depth you have cut STAYS. Push it past the red line and it seizes -- locked out while it
-- cools, and you lose a bite of depth for it.
--
-- That tension is the whole game: the fastest way through is one long hold, and one long hold
-- is exactly what overheats it. Tapping is safe and slow, feathering it right at the red line
-- is fast. A plain hold-to-fill bar has no decision in it anywhere.
--
-- Everything hangs off one table -- cheaper on registers than twenty named locals, and it keeps
-- the whole HUD addressable from one place.
local DRILL = {}
local drillBusy = false

do
	local gui = Instance.new("ScreenGui")
	gui.Name = "MineDrill"; gui.ResetOnSpawn = false; gui.DisplayOrder = 12
	gui.IgnoreGuiInset = true; gui.Enabled = false; gui.Parent = PlayerGui
	DRILL.gui = gui

	local catch = Instance.new("TextButton")
	catch.Size = UDim2.fromScale(1, 1); catch.BackgroundTransparency = 1
	catch.Text = ""; catch.AutoButtonColor = false; catch.ZIndex = 1; catch.Parent = gui
	DRILL.catch = catch

	-- HOME is stored because the panel gets shoved around: it rumbles while the bit is in the
	-- rock and jerks when it seizes, and both need somewhere to return to.
	DRILL.home = UDim2.new(0.5, -300, 0.7, 0)

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 600, 0, 214)
	panel.Position = DRILL.home
	panel.BackgroundColor3 = Color3.fromRGB(14, 18, 24); panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0; panel.ZIndex = 2; panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
	DRILL.panel = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = DIAMOND; stroke.Thickness = 3; stroke.Transparency = 0.12
	stroke.Parent = panel
	DRILL.stroke = stroke

	-- ---- THE BIT. A drill you can watch spin says "you are drilling" faster than any label,
	-- and its speed is the readout: it winds up as you hold and stalls dead when it seizes.
	local bit = Instance.new("Frame")
	bit.Size = UDim2.new(0, 64, 0, 64); bit.Position = UDim2.new(0, 18, 0, 12)
	bit.BackgroundTransparency = 1; bit.ZIndex = 3; bit.Parent = panel
	DRILL.bit = bit
	for i = 1, 3 do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.new(0, 58, 0, 12)
		f.BackgroundColor3 = (i == 1) and Color3.fromRGB(210, 226, 240) or Color3.fromRGB(128, 140, 154)
		f.BorderSizePixel = 0; f.Rotation = (i - 1) * 60; f.ZIndex = 3 + (i == 1 and 1 or 0)
		f.Parent = bit
		Instance.new("UICorner", f).CornerRadius = UDim.new(0, 4)
	end
	local hubf = Instance.new("Frame")
	hubf.AnchorPoint = Vector2.new(0.5, 0.5); hubf.Position = UDim2.fromScale(0.5, 0.5)
	hubf.Size = UDim2.new(0, 22, 0, 22); hubf.BackgroundColor3 = DIAMOND
	hubf.BorderSizePixel = 0; hubf.ZIndex = 5; hubf.Parent = bit
	Instance.new("UICorner", hubf).CornerRadius = UDim.new(1, 0)
	DRILL.hub = hubf

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0, 300, 0, 28); title.Position = UDim2.new(0, 94, 0, 14)
	title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBlack
	title.TextSize = 22; title.TextColor3 = Color3.fromRGB(226, 244, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left; title.ZIndex = 3
	title.Text = "DRILL THE SEAM"; title.Parent = panel

	local state = Instance.new("TextLabel")
	state.Size = UDim2.new(0, 200, 0, 22); state.Position = UDim2.new(0, 94, 0, 42)
	state.BackgroundTransparency = 1; state.Font = Enum.Font.GothamBold
	state.TextSize = 16; state.TextColor3 = DIAMOND
	state.TextXAlignment = Enum.TextXAlignment.Left; state.ZIndex = 3
	state.Text = ""; state.Parent = panel
	DRILL.state = state

	-- the big number: at a glance, how far through the rock you are
	local pct = Instance.new("TextLabel")
	pct.Size = UDim2.new(0, 170, 0, 54); pct.Position = UDim2.new(1, -186, 0, 12)
	pct.BackgroundTransparency = 1; pct.Font = Enum.Font.GothamBlack
	pct.TextSize = 44; pct.TextColor3 = DIAMOND
	pct.TextXAlignment = Enum.TextXAlignment.Right; pct.ZIndex = 3
	pct.Text = "0%"; pct.Parent = panel
	DRILL.pct = pct

	local function bar(y, label, col)
		local cap = Instance.new("TextLabel")
		cap.Size = UDim2.new(0, 70, 0, 20); cap.Position = UDim2.new(0, 18, 0, y)
		cap.BackgroundTransparency = 1; cap.Font = Enum.Font.GothamBold
		cap.TextSize = 14; cap.TextColor3 = Color3.fromRGB(150, 166, 180)
		cap.TextXAlignment = Enum.TextXAlignment.Left; cap.ZIndex = 3
		cap.Text = label; cap.Parent = panel

		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, -114, 0, 26); track.Position = UDim2.new(0, 96, 0, y - 3)
		track.BackgroundColor3 = Color3.fromRGB(9, 12, 16); track.BorderSizePixel = 0
		track.ClipsDescendants = true; track.ZIndex = 3; track.Parent = panel
		Instance.new("UICorner", track).CornerRadius = UDim.new(0, 7)

		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = col
		fill.BorderSizePixel = 0; fill.ZIndex = 4; fill.Parent = track
		return fill, track
	end

	local depth, depthTrack = bar(88, "DEPTH", DIAMOND)
	DRILL.depth = depth
	-- SLICE MARKS. The rock breaks in four bites, and without the marks the bar gives you no
	-- idea how close the next one is -- so a run of drilling feels like nothing is happening
	-- right up until the rock suddenly reacts.
	for i = 1, 3 do
		local t = Instance.new("Frame")
		t.Size = UDim2.new(0, 2, 1, 0); t.Position = UDim2.new(i / 4, 0, 0, 0)
		t.BackgroundColor3 = Color3.fromRGB(58, 72, 86); t.BorderSizePixel = 0
		t.ZIndex = 6; t.Parent = depthTrack
	end

	local heat, heatTrack = bar(130, "HEAT", Color3.fromRGB(255, 168, 60))
	DRILL.heat = heat
	local red = Instance.new("Frame")
	red.Size = UDim2.new(0, 3, 1, 0); red.Position = UDim2.new(0.78, 0, 0, 0)
	red.BackgroundColor3 = Color3.fromRGB(255, 80, 60); red.BorderSizePixel = 0
	red.ZIndex = 6; red.Parent = heatTrack

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -36, 0, 24); hint.Position = UDim2.new(0, 18, 0, 172)
	hint.BackgroundTransparency = 1; hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 15; hint.TextColor3 = Color3.fromRGB(150, 166, 180)
	hint.TextXAlignment = Enum.TextXAlignment.Left; hint.ZIndex = 3
	hint.Text = "Hold anywhere to drill  --  ease off before the red or the bit seizes"
	hint.Parent = panel
end

-- Drill one node. onBite fires each time you cut through another slice, so the rock out in the
-- world shakes and throws chips in step with the bar rather than only at the end.
local function playDrill(bites, onBite)
	if drillBusy then return false end
	drillBusy = true

	DRILL.depth.Size = UDim2.new(0, 0, 1, 0)
	DRILL.heat.Size  = UDim2.new(0, 0, 1, 0)
	DRILL.pct.Text   = "0%"
	DRILL.state.Text = "READY"
	DRILL.gui.Enabled = true
	DRILL.panel.Position = DRILL.home + UDim2.new(0, 0, 0.08, 0)
	TweenService:Create(DRILL.panel, TweenInfo.new(0.22, Enum.EasingStyle.Back),
		{ Position = DRILL.home }):Play()

	local down, depth, heat, seized, done = false, 0, 0, 0, 0
	local spin, rpm = 0, 0
	local c1 = DRILL.catch.MouseButton1Down:Connect(function() down = true end)
	local c2 = DRILL.catch.MouseButton1Up:Connect(function() down = false end)
	local c3 = DRILL.catch.MouseLeave:Connect(function() down = false end)

	while depth < 1 do
		local dt = math.min(task.wait(), 0.05)

		if seized > 0 then
			seized -= dt
			heat = math.max(0, heat - dt * 0.9)          -- it only cools while it is seized
			rpm  = math.max(0, rpm - dt * 2600)          -- and the bit stalls dead
			DRILL.state.Text = "SEIZED  --  BIT JAMMED"
			DRILL.stroke.Color = Color3.fromRGB(255, 80, 60)
		elseif down then
			depth = math.min(1, depth + dt * 0.30)       -- ~3.3s of clean holding, if you could
			heat  = heat + dt * 0.40
			rpm   = math.min(900, rpm + dt * 1800)
			DRILL.state.Text = (heat > 0.78) and "DRILLING  --  RUNNING HOT" or "DRILLING"
			DRILL.stroke.Color = (heat > 0.78) and Color3.fromRGB(255, 168, 60) or DIAMOND
			if heat >= 1 then
				-- pushed past the red: it bites back and you lose ground
				seized = 1.3
				heat   = 1
				depth  = math.max(0, depth - 0.14)
				down   = false
				-- one hard jolt, so a seize is something you feel and not just a word
				DRILL.panel.Position = DRILL.home + UDim2.new(0, math.random(-14, 14), 0, math.random(-10, 10))
			end
		else
			heat = math.max(0, heat - dt * 0.55)         -- cools when you let go; depth stays
			rpm  = math.max(0, rpm - dt * 1200)
			DRILL.state.Text = (heat > 0.05) and "COOLING" or "READY"
			DRILL.stroke.Color = DIAMOND
		end

		-- the bit: speed IS the readout, and the hub glows with the heat
		spin += rpm * dt
		DRILL.bit.Rotation = spin
		DRILL.hub.BackgroundColor3 = DIAMOND:Lerp(Color3.fromRGB(255, 70, 52), heat)

		-- the panel rumbles while the bit is in the rock, harder the hotter it gets
		if seized <= 0 then
			local sh = (rpm / 900) * (1.2 + heat * 2.6)
			DRILL.panel.Position = DRILL.home
				+ UDim2.new(0, math.random(-10, 10) * sh * 0.1, 0, math.random(-10, 10) * sh * 0.1)
		end

		DRILL.depth.Size = UDim2.new(depth, 0, 1, 0)
		DRILL.heat.Size  = UDim2.new(heat, 0, 1, 0)
		DRILL.pct.Text   = ("%d%%"):format(math.floor(depth * 100))
		DRILL.pct.TextColor3 = DIAMOND:Lerp(Color3.fromRGB(255, 168, 60), math.max(0, heat - 0.5) * 2)
		DRILL.heat.BackgroundColor3 = Color3.fromRGB(255, 168, 60)
			:Lerp(Color3.fromRGB(255, 70, 52), math.clamp((heat - 0.55) / 0.45, 0, 1))

		-- every slice cut is a hit on the rock out in the world
		local want = math.floor(depth * bites)
		while done < want and done < bites do
			done += 1
			if onBite then onBite(done) end
			DRILL.pct.TextSize = 54                      -- the number kicks on every bite
			TweenService:Create(DRILL.pct, TweenInfo.new(0.25), { TextSize = 44 }):Play()
		end
	end

	DRILL.state.Text = "THROUGH"
	DRILL.pct.Text = "100%"
	DRILL.panel.Position = DRILL.home
	c1:Disconnect(); c2:Disconnect(); c3:Disconnect()
	task.wait(0.3)
	TweenService:Create(DRILL.panel, TweenInfo.new(0.18),
		{ Position = DRILL.home + UDim2.new(0, 0, 0.12, 0) }):Play()
	task.delay(0.2, function() DRILL.gui.Enabled = false end)
	drillBusy = false
	return true
end

local function buildOreNode(cf, idx)
	local m = Instance.new("Model"); m.Name = "DiamondOre"; m:SetAttribute("QuestProp", true)
	local function piece(props, at)
		local p = mk(props); p.CFrame = at; p.Parent = m; return p
	end

	-- A WORKED DIG, not a pile of rocks. `cf` faces the room centre, so local -Z is the side the
	-- player walks up to: the exposed face, the vein and all the gear go on that side.
	--
	--   rock face  ->  a timbered opening propped around it  ->  a seam of diamonds cut across
	--   it  ->  a lantern over the work, a pick left leaning, a bucket of ore at the foot.

	-- A BOULDER, NOT A SLAB. The old node was three flat blocks with gems stuck on the front,
	-- which reads as a wall with stickers. This is a lumpy mass of angular lumps on stepped
	-- sizes and yaws, with one flatter face turned toward you -- and that face is the only
	-- place the seam has been opened.
	local rock = piece({ Name = "Ore", Size = Vector3.new(4.4, 3.4, 2.4), Color = ROCK,
		Material = Enum.Material.Slate, CanCollide = true, CanQuery = true },
		cf * CFrame.Angles(math.rad(4), 0, math.rad(-3)))
	m.PrimaryPart = rock

	--    x     y     z     sx    sy    sz    yaw   tone
	local LUMPS = {
		{ -2.2, -0.5,  0.3, 2.7, 2.5, 2.2,  0.7, ROCK_DK },
		{  2.3, -0.6,  0.2, 2.4, 2.2, 2.0, -0.6, ROCK_LT },
		{ -1.3,  1.5,  0.5, 2.1, 1.7, 1.8,  0.3, ROCK_LT },
		{  1.4,  1.7,  0.4, 1.8, 1.5, 1.6, -0.9, ROCK    },
		{  0.2, -1.6,  0.6, 3.0, 1.4, 2.1,  0.15, ROCK_DK },
		{ -2.6,  0.9, -0.3, 1.5, 1.4, 1.3,  1.1, ROCK    },
		{  2.7,  0.8, -0.2, 1.4, 1.3, 1.2, -1.2, ROCK_DK },
	}
	for i, L in ipairs(LUMPS) do
		piece({ Name = "Ore", Size = Vector3.new(L[4], L[5], L[6]), Color = L[8],
			Material = Enum.Material.Slate, CanCollide = true },
			cf * CFrame.new(L[1], L[2], L[3])
				* CFrame.Angles(math.rad((i % 3 - 1) * 9), L[7], math.rad((i % 4 - 2) * 7)))
	end

	-- THE POCKET. Every gem sits in a socket cut into the face and only its outer third stands
	-- proud -- a crystal laid flat on the surface reads as a sticker, one set into a recess
	-- reads as something you have to dig out. Two big and four small, clustered rather than
	-- evenly spaced: a vein is a pocket that got opened, not a pattern.
	local GEMS = { { 0.0, 0.35, 1.00 }, { -1.05, -0.10, 0.72 }, { 0.95, 0.55, 0.66 },
	               { -0.45, 1.00, 0.50 }, { 0.35, -0.70, 0.58 }, { 1.55, -0.30, 0.44 } }
	for i, g in ipairs(GEMS) do
		local d  = g[3] * (0.85 + ((i + idx) % 3) * 0.12)
		local at = cf * CFrame.new(g[1], g[2], -1.06)
		-- the socket: a dark recess, so the crystal has somewhere to be set into
		piece({ Name = "OreChip", Size = Vector3.new(d * 2.0, d * 2.0, 0.45), Color = ROCK_DK,
			Material = Enum.Material.Slate }, at * CFrame.Angles(0, 0, i * 0.5))
		-- the crystal, mostly buried
		piece({ Name = "Gem", Size = Vector3.new(d, d * 1.5, d), Color = DIAMOND,
			Material = Enum.Material.Neon, Reflectance = 0.25 },
			at * CFrame.new(0, 0, -0.16) * CFrame.Angles(math.rad(28), math.rad(45), i * 0.4))
		-- a table facet on the big ones, so they read as cut rather than as a lump of light
		if d > 0.6 then
			piece({ Name = "Gem", Size = Vector3.new(d * 0.6, d * 0.6, d * 0.6), Color = DIAMOND,
				Material = Enum.Material.Neon, Reflectance = 0.35 },
				at * CFrame.new(0, 0, -0.42) * CFrame.Angles(math.rad(45), math.rad(45), 0))
		end
	end

	-- and a couple showing in the SIDES of the boulder, so the seam runs into the rock rather
	-- than being painted on the front of it
	for _, s in ipairs({ -1, 1 }) do
		piece({ Name = "Gem", Size = Vector3.new(0.46, 0.66, 0.46), Color = DIAMOND,
			Material = Enum.Material.Neon, Reflectance = 0.25 },
			cf * CFrame.new(s * 2.15, 0.35, 0.15)
				* CFrame.Angles(math.rad(18), math.rad(s * 62), math.rad(s * 22)))
	end

	-- TIMBERED OPENING: two props and a header, braced -- the thing that says "someone is
	-- working this" rather than "a rock happens to have gems in it"
	for _, s in ipairs({ -1, 1 }) do
		piece({ Name = "Prop", Size = Vector3.new(0.5, 3.9, 0.5), Color = WOOD, CanCollide = true,
			Material = Enum.Material.Wood }, cf * CFrame.new(s * 2.5, -0.1, -1.1))
		piece({ Name = "Prop", Size = Vector3.new(0.34, 1.0, 0.4), Color = WOOD_DK,
			Material = Enum.Material.Wood },
			cf * CFrame.new(s * 2.05, 1.45, -1.1) * CFrame.Angles(0, 0, math.rad(s * 42)))
	end
	piece({ Name = "Prop", Size = Vector3.new(5.9, 0.55, 0.66), Color = WOOD_DK,
		Material = Enum.Material.Wood }, cf * CFrame.new(0, 2.05, -1.1))
	piece({ Name = "Prop", Size = Vector3.new(5.5, 0.14, 0.3), Color = WOOD,
		Material = Enum.Material.Wood }, cf * CFrame.new(0, 2.36, -1.28))

	-- a lantern hung over the work: warm, so it reads against the cold blue of the seam
	piece({ Name = "Prop", Size = Vector3.new(0.12, 0.55, 0.12), Color = WOOD_DK,
		Material = Enum.Material.Wood }, cf * CFrame.new(1.1, 1.55, -1.42))
	local lamp = piece({ Name = "LampGlow", Size = Vector3.new(0.46, 0.6, 0.46), Color = FLAME,
		Material = Enum.Material.Neon }, cf * CFrame.new(1.1, 1.05, -1.42))
	local lpl = Instance.new("PointLight")
	lpl.Color = FLAME; lpl.Brightness = 0.10; lpl.Range = 6; lpl.Parent = lamp

	-- a pick left leaning against the prop
	piece({ Name = "Prop", Size = Vector3.new(0.16, 2.5, 0.16), Color = WOOD,
		Material = Enum.Material.Wood },
		cf * CFrame.new(-2.05, -0.65, -1.85) * CFrame.Angles(math.rad(-9), 0, math.rad(14)))
	piece({ Name = "Prop", Size = Vector3.new(1.25, 0.2, 0.2), Color = Color3.fromRGB(96, 100, 108),
		Material = Enum.Material.Metal },
		cf * CFrame.new(-1.75, 0.5, -1.9) * CFrame.Angles(0, 0, math.rad(24)))

	-- a bucket of hewn ore at the foot of the face
	piece({ Name = "Prop", Size = Vector3.new(1.3, 1.05, 1.3), Color = WOOD_DK, CanCollide = true,
		Material = Enum.Material.Wood }, cf * CFrame.new(2.35, -1.35, -2.0))
	piece({ Name = "Prop", Size = Vector3.new(1.4, 0.16, 1.4), Color = Color3.fromRGB(96, 100, 108),
		Material = Enum.Material.Metal }, cf * CFrame.new(2.35, -1.0, -2.0))
	for i = 1, 2 do
		piece({ Name = "Gem", Size = Vector3.new(0.36, 0.48, 0.36), Color = DIAMOND,
			Material = Enum.Material.Neon, Reflectance = 0.2 },
			cf * CFrame.new(2.15 + i * 0.32, -0.72, -2.05)
				* CFrame.Angles(math.rad(28), math.rad(45), i * 0.7))
	end

	-- chippings where the face has been worked
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2 + idx
		piece({ Name = "OreChip", Size = Vector3.new(1.1, 0.7, 1.2),
			Color = (i % 2 == 0) and ROCK_DK or ROCK_LT, Material = Enum.Material.Rock },
			cf * CFrame.new(math.cos(a) * 2.1, -1.55, -1.4 + math.sin(a) * 0.9)
				* CFrame.Angles(math.rad(i * 11), a, math.rad(i * 8)))
	end
	local light = Instance.new("PointLight"); light.Color = DIAMOND; light.Brightness = 0.09; light.Range = 5; light.Parent = rock
	local hl = Instance.new("Highlight"); hl.FillTransparency = 1; hl.OutlineColor = DIAMOND
	hl.OutlineTransparency = 0.25; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = rock; hl.Parent = m

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Drill"; prompt.ObjectText = "Diamond Ore"; prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false; prompt.Parent = rock

	local node = { model = m, prompt = prompt, hp = SWINGS_PER_NODE, broken = false, hl = hl }
	prompt.Triggered:Connect(function()
		if node.broken or phase ~= "mine" or drillBusy then return end
		prompt.Enabled = false
		-- ONE DRILL PER NODE. Each slice the bit cuts through is one hit on the rock, so the
		-- shake and the chips out in the world keep pace with the bar instead of the whole
		-- node breaking in one lump at the end.
		playDrill(SWINGS_PER_NODE, function() mineNode(node) end)
		if not node.broken then prompt.Enabled = true end
	end)
	m.Parent = caveModel
	oreNodes[#oreNodes + 1] = node
	return node
end

function mineNode(node)
	if node.broken or phase ~= "mine" then return end
	node.hp = node.hp - 1
	-- swing hit: shake the rock + chip particles
	local rock = node.model.PrimaryPart
	if rock then
		local base = rock.CFrame
		TweenService:Create(rock, TweenInfo.new(0.06), { CFrame = base * CFrame.new((math.random() - 0.5) * 0.6, 0, (math.random() - 0.5) * 0.6) }):Play()
		task.delay(0.08, function() if rock.Parent then rock.CFrame = base end end)
		for i = 1, 6 do
			local chip = mk({ Name = "Chip", Size = Vector3.new(0.4, 0.4, 0.4), Color = ROCK_LT, Material = Enum.Material.Rock })
			chip.CFrame = base * CFrame.new(0, 1, -1.8); chip.Parent = Workspace
			local dir = Vector3.new((math.random() - 0.5) * 2, math.random() * 1.4, (math.random() - 0.5) * 2)
			TweenService:Create(chip, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = base * CFrame.new(0, 1, -1.8) + dir * 6, Transparency = 1 }):Play()
			Debris:AddItem(chip, 0.6)
		end
	end
	if node.hp > 0 then return end

	-- broken: burst, drop a diamond that flies to you, count it
	node.broken = true
	node.prompt.Enabled = false
	if node.hl then node.hl.Enabled = false end
	minedNodes = minedNodes + 1
	carriedDiam = carriedDiam + 1

	local from = rock and rock.Position or (hrpOf() and hrpOf().Position) or Vector3.new()
	if node.model then node.model:Destroy() end
	-- a diamond that arcs into the player
	local diamond = mk({ Name = "DroppedDiamond", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.6, 1.2),
		Color = DIAMOND, Material = Enum.Material.Neon, Reflectance = 0.3 })
	diamond.CFrame = CFrame.new(from + Vector3.new(0, 2, 0)); diamond.Parent = Workspace
	local pl = Instance.new("PointLight"); pl.Color = DIAMOND; pl.Brightness = 0.14; pl.Range = 4; pl.Parent = diamond
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.6 do
			local hrp = hrpOf()
			if not hrp then break end
			local a = (os.clock() - t0) / 0.6
			diamond.CFrame = CFrame.new(from:Lerp(hrp.Position + Vector3.new(0, 2, 0), a)) * CFrame.Angles(0, a * 12, 0)
			RunService.RenderStepped:Wait()
		end
		diamond:Destroy()
	end)

	refreshHeldGem()
	updateObjective()
	if minedNodes >= NODES_NEEDED then
		notify("💎 All ore mined! Take the diamonds to the Mine Cart.", DIAMOND)
		if mineCart and mineCart.PrimaryPart then pointTo(mineCart.PrimaryPart.Position) end
	else
		notify(("⛏️ Diamond! (%d/%d)"):format(minedNodes, NODES_NEEDED), DIAMOND)
	end
end

local function depositAtCart()
	if phase ~= "mine" or carriedDiam <= 0 then return end
	local n = carriedDiam
	carriedDiam = 0
	refreshHeldGem()
	-- fill the cart visually
	for i = 1, n do
		cartCount = math.min(NODES_NEEDED, cartCount + 1)
		local idx = cartCount
		local gem = mk({ Name = "CartGem", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 1.1, 0.9),
			Color = DIAMOND, Material = Enum.Material.Neon, Reflectance = 0.25 })
		local col = (idx - 1) % 3
		local row = math.floor((idx - 1) / 3)
		if mineCart and mineCart.PrimaryPart then
			gem.CFrame = mineCart.PrimaryPart.CFrame * CFrame.new((col - 1) * 0.9, 0.9 + row * 0.5, 0)
		end
		gem.Parent = mineCart
		cartFillParts[#cartFillParts + 1] = gem
	end
	updateObjective()
	if cartCount >= NODES_NEEDED then
		phase = "return"
		updateObjective()
		notify("🪜 Cart full! Return to the surface.", GOLD)
		if exitPrompt then exitPrompt.Enabled = true end
		if caveExitCF then pointTo(caveExitCF.Position) end
	else
		notify(("💎 Deposited %d  (cart %d/%d)"):format(n, cartCount, NODES_NEEDED), DIAMOND)
	end
end

local function buildCave()
	if caveModel then return end
	-- THE MINE IS MEANT TO BE DARK. Every fixture below was tuned before there was a headlamp,
	-- and a cave you can already see across is a cave where the lamp on your hat is decoration.
	-- The fixtures now mark WHERE things are -- a torch, a vein, the exit -- and the lamp is
	-- what you actually see by.
	local m = Instance.new("Model"); m.Name = "PrivateMine_" .. player.UserId; m.Parent = Workspace
	caveModel = m
	local O = voidOffset   -- cave origin (far below, per-player)

	local W, L, H = 130, 130, 34    -- room footprint / height
	local function slab(name, size, pos, color, mat)
		local p = mk({ Name = name, Size = size, Color = color, Material = mat or Enum.Material.Rock, CanCollide = true })
		p.CFrame = CFrame.new(O + pos); p.Parent = m
		return p
	end
	-- floor / ceiling / four walls (sealed box so you can't fall into the void)
	slab("Floor", Vector3.new(W, 4, L), Vector3.new(0, -2, 0), ROCK_DK, Enum.Material.Slate)
	slab("Ceiling", Vector3.new(W, 4, L), Vector3.new(0, H, 0), Color3.fromRGB(40, 36, 32), Enum.Material.Rock)
	slab("WallN", Vector3.new(W, H + 8, 4), Vector3.new(0, H / 2, -L / 2), ROCK_DK)   -- back = darker stone (depth)
	slab("WallS", Vector3.new(W, H + 8, 4), Vector3.new(0, H / 2, L / 2), ROCK_LT)    -- entrance = lighter stone
	slab("WallE", Vector3.new(4, H + 8, L), Vector3.new(W / 2, H / 2, 0), ROCK)
	slab("WallW", Vector3.new(4, H + 8, L), Vector3.new(-W / 2, H / 2, 0), ROCK)
	-- a bumpy floor so it isn't a flat plane: scattered low rocks + stalagmites
	for i = 1, 22 do
		local a = (i / 22) * math.pi * 2
		local r = 12 + (i % 5) * 9
		local rk = mk({ Name = "Rubble", Size = Vector3.new(2 + (i % 3), 1.4 + (i % 2), 2 + (i % 4)),
			Color = (i % 2 == 0) and ROCK_DK or ROCK, Material = Enum.Material.Slate, CanCollide = true })
		rk.CFrame = CFrame.new(O + Vector3.new(math.cos(a) * r, 0.4, math.sin(a) * r)) * CFrame.Angles(0, i, math.rad((i % 4) * 5))
		rk.Parent = m
	end
	for i = 1, 8 do
		local a = i * 2.3
		local r = 30 + (i % 3) * 12
		local stal = mk({ Name = "Stalagmite", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6 + (i % 3) * 2, 2.2, 2.2),
			Color = ROCK_LT, Material = Enum.Material.Slate, CanCollide = true })
		stal.CFrame = CFrame.new(O + Vector3.new(math.cos(a) * r, 3, math.sin(a) * r)) * CFrame.Angles(0, 0, math.rad(90))
		stal.Parent = m
	end

	-- wall torches for atmosphere (local point lights -- never touch global Lighting)
	for _, tp in ipairs({ Vector3.new(-W / 2 + 4, 12, -20), Vector3.new(-W / 2 + 4, 12, 20),
		Vector3.new(W / 2 - 4, 12, -20), Vector3.new(W / 2 - 4, 12, 20), Vector3.new(0, 12, -L / 2 + 4) }) do
		local post = mk({ Name = "TorchPost", Size = Vector3.new(0.4, 3, 0.4), Color = WOOD_DK, Material = Enum.Material.Wood })
		post.CFrame = CFrame.new(O + tp); post.Parent = m
		local fire = mk({ Name = "TorchFire", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.8, 1.4),
			Color = FLAME, Material = Enum.Material.Neon })
		fire.CFrame = CFrame.new(O + tp + Vector3.new(0, 2, 0)); fire.Parent = m
		local pl = Instance.new("PointLight"); pl.Color = FLAME; pl.Brightness = 0.17; pl.Range = 12; pl.Parent = fire
	end
	-- a dim, warm general fill so the room reads but stays moody + mysterious
	local fill = mk({ Name = "FillLight", Size = Vector3.new(1, 1, 1), Transparency = 1 })
	fill.CFrame = CFrame.new(O + Vector3.new(0, H - 8, 6)); fill.Parent = m
	-- THE AMBIENT FILL is the single reason the mine reads as lit at all. It was a 72-stud wash
	-- showing you the whole room; now it is a faint haze that says "there is a space here" and
	-- leaves the seeing to your headlamp.
	local fpl = Instance.new("PointLight"); fpl.Color = Color3.fromRGB(180, 150, 120)
	fpl.Brightness = 0.09; fpl.Range = 24; fpl.Parent = fill

	-- ======================================================================
	-- ENVIRONMENT DETAIL -- handcrafted mine dressing. EVERYTHING below is decorative and
	-- CanCollide=false (via mk defaults), so it can never block movement, trap the player, or
	-- cover a prompt. The interactables (nodes/cart/entry/exit/stairs) are built AFTER this and
	-- are left exactly where they were; `clearAt()` keeps decor off their footprints + the path.
	-- ======================================================================
	local HW, HL = W / 2, L / 2
	local function deco(name, size, cf, color, mat)   -- decorative part (solidified in the restyle pass)
		local p = mk({ Name = name, Size = size, Color = color, Material = mat or Enum.Material.Slate })
		p.CFrame = cf; p.Parent = m
		return p
	end
	local function stoneByZ(z)   -- lighter near the entrance (+Z), darker toward the back (-Z)
		return ROCK_DK:Lerp(ROCK_LT, math.clamp((z + HL) / L, 0, 1))
	end
	-- analytic footprints of the nodes + cart/entry/exit so nothing decorative lands on them
	-- Node positions are decided ONCE, here, because the decor pass has to keep clear of them.
	-- FOUR SEAMS along the walls rather than one evenly spaced ring: ore comes in veins, and ten
	-- rocks at identical angular spacing reads as placed rather than found.
	local nodeSpots = {}
	do
		local seams = { { 0.55, 46 }, { 2.05, 42 }, { 3.55, 47 }, { 5.05, 43 } }
		local per   = { 3, 3, 2, 2 }                    -- 3+3+2+2 = 10
		for si, s in ipairs(seams) do
			for k = 1, per[si] do
				if #nodeSpots >= NODES_NEEDED then break end
				local a = s[1] + (k - (per[si] + 1) / 2) * 0.17
				local r = s[2] + ((k % 2 == 0) and -5 or 4)
				nodeSpots[#nodeSpots + 1] = { x = math.cos(a) * r, z = math.sin(a) * r, a = a }
			end
		end
	end

	local clearZones = { { 24, -18, 12 }, { 0, HL - 14, 14 }, { 0, -HL + 8, 14 } }
	for _, sp in ipairs(nodeSpots) do
		clearZones[#clearZones + 1] = { sp.x, sp.z, 8 }
	end
	local function clearAt(x, z, pad)
		pad = pad or 0
		if math.abs(x) < 9 and z > 6 then return false end   -- keep the central entrance path/stairs open
		for _, c in ipairs(clearZones) do
			if math.abs(x - c[1]) < c[3] + pad and math.abs(z - c[2]) < c[3] + pad then return false end
		end
		return true
	end

	-- ---- irregular rocky wall skin: overlapping boulders/ledges on the inner faces (the flat
	-- wall slab behind still does the collision), shaded lighter->darker front-to-back ----
	local faces = { { "z", -1 }, { "z", 1 }, { "x", -1 }, { "x", 1 } }
	for _, f in ipairs(faces) do
		for col = -5, 5 do
			for row = 0, 3 do
				local along = col * 11 + (row % 2) * 5
				local y = 2.5 + row * 8 + (col % 2) * 1.5
				local depthIn = 2 + (row % 3)
				local px, pz
				if f[1] == "z" then px, pz = along, f[2] * (HL - depthIn) else px, pz = f[2] * (HW - depthIn), along end
				-- leave the entrance + exit alcoves clean
				if not (math.abs(px) < 11 and math.abs(math.abs(pz) - HL) < 13) then
					local sz = Vector3.new(7 + (col % 3) * 2.5, 7 + (row % 2) * 3, 5 + (col % 2) * 2)
					local cf = CFrame.new(O + Vector3.new(px, y, pz))
						* CFrame.Angles(math.rad((row % 3) * 6 - 6), math.rad(col * 5), math.rad((col % 4) * 6 - 9))
					deco("WallRock", sz, cf, stoneByZ(pz):Lerp(Color3.new(0, 0, 0), (row % 2) * 0.08), Enum.Material.Rock)
				end
			end
		end
	end

	-- ---- wooden support arches down each side wall + a few ceiling cross-beams ----
	for _, sx in ipairs({ -1, 1 }) do
		for _, zc in ipairs({ -40, -14, 12, 36 }) do
			local bx = sx * (HW - 5)
			deco("Beam", Vector3.new(1.7, H - 3, 1.7), CFrame.new(O + Vector3.new(bx, (H - 3) / 2, zc - 5)), WOOD_DK, Enum.Material.Wood)
			deco("Beam", Vector3.new(1.7, H - 3, 1.7), CFrame.new(O + Vector3.new(bx, (H - 3) / 2, zc + 5)), WOOD_DK, Enum.Material.Wood)
			deco("Beam", Vector3.new(1.7, 1.7, 13), CFrame.new(O + Vector3.new(bx, H - 4.5, zc)), WOOD, Enum.Material.Wood)
			deco("Brace", Vector3.new(1.1, 1.1, 8), CFrame.new(O + Vector3.new(bx, H - 7, zc - 3)) * CFrame.Angles(math.rad(38), 0, 0), WOOD, Enum.Material.Wood)
			deco("Brace", Vector3.new(1.1, 1.1, 8), CFrame.new(O + Vector3.new(bx, H - 7, zc + 3)) * CFrame.Angles(math.rad(-38), 0, 0), WOOD, Enum.Material.Wood)
		end
	end
	for _, zc in ipairs({ -32, -4, 24 }) do
		deco("CeilBeam", Vector3.new(W - 10, 1.5, 1.5), CFrame.new(O + Vector3.new(0, H - 3.5, zc)), WOOD_DK, Enum.Material.Wood)
	end

	-- ---- worn, uneven floor: gravel patches, worn path, shallow pits, loose pebbles (all thin +
	-- non-colliding, so you still walk on the real flat floor beneath) ----
	for i = 1, 26 do
		local a = i * 2.399; local r = 8 + (i % 6) * 8
		local x, z = math.cos(a) * r, math.sin(a) * r
		if clearAt(x, z, 2) then
			deco("Gravel", Vector3.new(5 + (i % 4) * 2, 0.3, 5 + (i % 3) * 2),
				CFrame.new(O + Vector3.new(x, 0.15, z)) * CFrame.Angles(0, i, 0),
				(i % 3 == 0) and DIRT or stoneByZ(z), Enum.Material.Ground)
		end
	end
	for i = 1, 5 do
		local a = i * 1.7; local r = 40 + (i % 2) * 8
		local x, z = math.cos(a) * r, math.sin(a) * r
		if clearAt(x, z, 4) then deco("Pit", Vector3.new(7, 0.2, 7), CFrame.new(O + Vector3.new(x, 0.12, z)), Color3.fromRGB(24, 20, 16), Enum.Material.Ground) end
	end
	for i = 0, 8 do
		deco("Path", Vector3.new(7, 0.25, 6), CFrame.new(O + Vector3.new((i % 2) * 1.2 - 0.6, 0.16, HL - 16 - i * 5)), DIRT, Enum.Material.Ground)
	end
	for i = 1, 44 do
		local a = i * 0.97; local r = 6 + (i % 9) * 6.2
		local x, z = math.cos(a) * r, math.sin(a) * r
		deco("Pebble", Vector3.new(0.6 + (i % 3) * 0.25, 0.5, 0.6 + (i % 2) * 0.25),
			CFrame.new(O + Vector3.new(x, 0.3, z)) * CFrame.Angles(i, i * 2, i), stoneByZ(z), Enum.Material.Rock)
	end

	-- ---- glowing crystal veins embedded in the walls ----
	for i = 1, 20 do
		local wall = i % 4
		local along = (math.random() - 0.5) * (W - 26)
		local y = 4 + math.random() * (H - 11)
		local px, pz
		if wall == 0 then px, pz = along, -HL + 3
		elseif wall == 1 then px, pz = along, HL - 3
		elseif wall == 2 then px, pz = -HW + 3, along
		else px, pz = HW - 3, along end
		local col = CRYSTAL_COLS[(i % 4) + 1]
		local vein = deco("CrystalVein", Vector3.new(1 + math.random() * 1.5, 2 + math.random() * 2, 1 + math.random() * 1.5),
			CFrame.new(O + Vector3.new(px, y, pz)) * CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3),
			col, Enum.Material.Neon)
		vein.Reflectance = 0.2
		for _ = 1, 3 do
			deco("Shard", Vector3.new(0.4, 1 + math.random(), 0.4),
				vein.CFrame * CFrame.new((math.random() - 0.5) * 3, (math.random() - 0.5) * 3, 0.2) * CFrame.Angles(math.random() * 3, 0, math.random() * 3),
				col, Enum.Material.Neon)
		end
		if i % 3 == 0 then
			local pl = Instance.new("PointLight"); pl.Color = col; pl.Brightness = 0.06; pl.Range = 5; pl.Shadows = false; pl.Parent = vein
		end
	end

	-- ---- BIG DIAMOND CHAMBER at the back: blue crystal clusters flanking the back wall (the exit
	-- shaft in the middle stays clear) + a soft blue wash over the whole back ----
	for ci, cx in ipairs({ -36, -22, 22, 36 }) do
		local col = CRYSTAL_COLS[(ci % 4) + 1]
		local h = 8 + math.random() * 6
		local big = deco("BigCrystal", Vector3.new(3, h, 3),
			CFrame.new(O + Vector3.new(cx, h / 2 + 0.5, -HL + 6)) * CFrame.Angles(math.rad((math.random() - 0.5) * 20), math.random() * 3, math.rad((math.random() - 0.5) * 20)),
			col, Enum.Material.Neon)
		deco("Crystal", Vector3.new(2.1, 2.1, 2.1), big.CFrame * CFrame.new(0, h / 2, 0) * CFrame.Angles(math.rad(45), math.rad(35), 0), col, Enum.Material.Neon) -- faceted top point
		for _ = 1, 4 do
			local sh = 3 + math.random() * 4
			local sub = deco("Crystal", Vector3.new(1.6, sh, 1.6),
				CFrame.new(O + Vector3.new(cx + (math.random() - 0.5) * 6, 2 + math.random() * 3, -HL + 6 + math.random() * 3)) * CFrame.Angles(math.rad((math.random() - 0.5) * 30), math.random() * 3, math.rad((math.random() - 0.5) * 30)),
				col, Enum.Material.Neon)
			deco("Crystal", Vector3.new(1.15, 1.15, 1.15), sub.CFrame * CFrame.new(0, sh / 2, 0) * CFrame.Angles(math.rad(45), math.rad(35), 0), col, Enum.Material.Neon) -- point
		end
		-- subtle coloured pool (calm, no overwhelming bloom)
		local pl = Instance.new("PointLight"); pl.Color = col; pl.Brightness = 0.09; pl.Range = 7; pl.Shadows = false; pl.Parent = big
	end
	local backGlow = deco("BackGlow", Vector3.new(1, 1, 1), CFrame.new(O + Vector3.new(0, 12, -HL + 16)), DIAMOND); backGlow.Transparency = 1
	local bgl = Instance.new("PointLight"); bgl.Color = Color3.fromRGB(140, 200, 255); bgl.Brightness = 0.07; bgl.Range = 19; bgl.Shadows = false; bgl.Parent = backGlow
	-- gentle shimmer on the diamond chamber (breathing glow; stops when the cave is torn down)
	task.spawn(function()
		local t = 0
		while m.Parent do t = t + 0.1; bgl.Brightness = 0.06 + math.abs(math.sin(t)) * 0.6; task.wait(0.1) end
	end)

	-- ---- EVERYTHING hanging from the ceiling is a CRYSTAL formation (low-poly faceted gems). A tiny
	-- grey rock mount is where each cluster grows from the roof; only the big showpieces get a glow. ----
	local function crystalTip(cf, w, col)   -- a faceted point on the end of a spike
		deco("Crystal", Vector3.new(w * 0.72, w * 0.72, w * 0.72), cf * CFrame.Angles(math.rad(45), math.rad(35), 0), col, Enum.Material.Neon)
	end
	local function crystalSpike(name, x, topY, z, len, w, col)
		local body = deco(name, Vector3.new(w, len, w),
			CFrame.new(O + Vector3.new(x, topY - len / 2, z)) * CFrame.Angles(math.rad((math.random() - 0.5) * 16), math.random() * 3, math.rad((math.random() - 0.5) * 16)),
			col, Enum.Material.Neon)
		crystalTip(body.CFrame * CFrame.new(0, -len / 2, 0), w, col)   -- pointed bottom tip
		return body
	end
	local function hangCrystals(x, z, col, big)
		local topY = H - 2
		deco("Rubble", Vector3.new(big and 3.4 or 2.4, 1.3, big and 3.4 or 2.4), CFrame.new(O + Vector3.new(x, topY + 0.4, z)), ROCK_LT, Enum.Material.Slate) -- roof mount
		local main = crystalSpike("BigCrystal", x, topY, z, (big and 7 or 4.5) + math.random() * 3, big and 1.9 or 1.35, col)
		for _ = 1, (big and 3 or 2) do
			crystalSpike("Crystal", x + (math.random() - 0.5) * 3, topY - math.random() * 1.6, z + (math.random() - 0.5) * 3,
				(big and 3 or 2.2) + math.random() * 2.5, big and 0.9 or 0.7, col)
		end
		if big then
			local pl = Instance.new("PointLight"); pl.Color = col; pl.Brightness = 0.07; pl.Range = 6; pl.Shadows = false; pl.Parent = main
		end
	end
	local ci = 0
	for i = 1, 10 do
		local a = i * 2.1; local r = 15 + (i % 5) * 8
		ci = ci + 1
		hangCrystals(math.cos(a) * r, math.sin(a) * r, CRYSTAL_COLS[(ci % 4) + 1], false)
	end
	for _, sp in ipairs({ { -20, 8 }, { 22, -6 }, { -8, -26 }, { 14, 22 }, { 0, -8 }, { -30, -30 } }) do
		ci = ci + 1
		hangCrystals(sp[1], sp[2], CRYSTAL_COLS[(ci % 4) + 1], true)
	end

	-- ---- crystal clusters rising from the FLOOR (colourful showpieces near the edges) ----
	local function floorCluster(x, z, col)
		if not clearAt(x, z, 4) then return end
		deco("Rubble", Vector3.new(4, 1, 4), CFrame.new(O + Vector3.new(x, 0.4, z)), ROCK_LT, Enum.Material.Slate) -- base rock
		local function spike(bx, bz, w, len)
			local body = deco(w > 1.3 and "BigCrystal" or "Crystal", Vector3.new(w, len, w),
				CFrame.new(O + Vector3.new(bx, 0.6 + len / 2, bz)) * CFrame.Angles(math.rad((math.random() - 0.5) * 22), math.random() * 3, math.rad((math.random() - 0.5) * 22)),
				col, Enum.Material.Neon)
			deco("Crystal", Vector3.new(w * 0.7, w * 0.7, w * 0.7), body.CFrame * CFrame.new(0, len / 2, 0) * CFrame.Angles(math.rad(45), math.rad(35), 0), col, Enum.Material.Neon)
			return body
		end
		local main = spike(x, z, 1.7, 5 + math.random() * 3)
		for _ = 1, 3 do spike(x + (math.random() - 0.5) * 3.5, z + (math.random() - 0.5) * 3.5, 1, 3 + math.random() * 2.5) end
		local pl = Instance.new("PointLight"); pl.Color = col; pl.Brightness = 0.07; pl.Range = 6; pl.Shadows = false; pl.Parent = main
	end
	for fi, sp in ipairs({ { -50, 18 }, { 52, -22 }, { -46, -40 }, { 44, 40 }, { 18, -52 } }) do
		floorCluster(sp[1], sp[2], CRYSTAL_COLS[(fi % 4) + 1])
	end

	-- ---- lanterns / hanging mining lamps (warm subtle glow) ----
	local function lantern(x, z)
		deco("LampRope", Vector3.new(0.12, 6, 0.12), CFrame.new(O + Vector3.new(x, H - 6, z)), Color3.fromRGB(58, 46, 30))
		deco("Lamp", Vector3.new(1.3, 1.9, 1.3), CFrame.new(O + Vector3.new(x, H - 9.5, z)), Color3.fromRGB(72, 58, 30), Enum.Material.Metal)
		local glow = deco("LampGlow", Vector3.new(0.95, 1.1, 0.95), CFrame.new(O + Vector3.new(x, H - 9.5, z)), Color3.fromRGB(255, 196, 110), Enum.Material.Neon)
		glow.Shape = Enum.PartType.Ball
		local pl = Instance.new("PointLight"); pl.Color = Color3.fromRGB(255, 188, 118); pl.Brightness = 0.13; pl.Range = 10; pl.Shadows = false; pl.Parent = glow
	end
	for _, lp in ipairs({ { -26, 24 }, { 28, 26 }, { -30, -12 }, { 30, -20 }, { 0, 0 } }) do lantern(lp[1], lp[2]) end

	-- ---- prop clusters: crates, barrels, broken boards, pickaxes, tools (near the walls) ----
	local function pickaxe(pos, rot)
		local h = deco("PickHandle", Vector3.new(0.35, 4, 0.35), CFrame.new(O + pos + Vector3.new(0, 2, 0)) * CFrame.Angles(math.rad(62), rot or 0, 0), WOOD, Enum.Material.Wood)
		deco("PickHead", Vector3.new(3.4, 0.5, 0.5), h.CFrame * CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, math.rad(20)), STEEL, Enum.Material.Metal)
	end
	local function propCluster(x, z)
		if not clearAt(x, z, 3) then return end
		local b = Vector3.new(x, 0, z)
		deco("Crate", Vector3.new(2.6, 2.6, 2.6), CFrame.new(O + b + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, math.random() * 3, 0), WOOD, Enum.Material.WoodPlanks)
		deco("Crate", Vector3.new(2.0, 2.0, 2.0), CFrame.new(O + b + Vector3.new(0.5, 3.5, 0.3)) * CFrame.Angles(0, math.random() * 3, 0), WOOD, Enum.Material.WoodPlanks)
		deco("Crate", Vector3.new(2.2, 2.2, 2.2), CFrame.new(O + b + Vector3.new(2.8, 1.2, 0.6)) * CFrame.Angles(0, math.random() * 3, 0), WOOD_DK, Enum.Material.WoodPlanks)
		local barrel = deco("Barrel", Vector3.new(3, 2.6, 2.6), CFrame.new(O + b + Vector3.new(-2.6, 1.5, 0.4)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(92, 60, 34), Enum.Material.Wood)
		barrel.Shape = Enum.PartType.Cylinder
		for i = 1, 3 do
			deco("Board", Vector3.new(0.35, 0.3, 4 + i), CFrame.new(O + b + Vector3.new(1.6 - i, 0.3, -2 + i)) * CFrame.Angles(0, i, math.rad(6)), WOOD_DK, Enum.Material.Wood)
		end
		pickaxe(b + Vector3.new(2.0, 0, -1.8), math.random() * 3)
	end
	for _, sp in ipairs({ { -HW + 12, 20 }, { HW - 12, 6 }, { -HW + 14, -30 }, { HW - 14, -34 }, { -18, HL - 20 } }) do
		propCluster(sp[1], sp[2])
	end

	-- ---- storytelling wreckage: a tipped broken cart, broken rails, collapsed beams ----
	do
		local cp = Vector3.new(-HW + 13, 1.6, HL - 22)
		if clearAt(cp.X, cp.Z, 2) then
			local bc = deco("BrokenCart", Vector3.new(5.5, 3, 4), CFrame.new(O + cp) * CFrame.Angles(math.rad(78), math.rad(28), 0), Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
			for _, wx in ipairs({ -1.8, 1.8 }) do
				deco("Wheel", Vector3.new(0.6, 1.6, 1.6), bc.CFrame * CFrame.new(wx, -1.7, 0) * CFrame.Angles(0, 0, math.rad(90)), STEEL_DK, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
			end
		end
	end
	for i = 1, 6 do
		local a = i * 1.3; local r = 44 + (i % 3) * 6
		local x, z = math.cos(a) * r, math.sin(a) * r
		if clearAt(x, z, 3) then deco("BrokenRail", Vector3.new(6, 0.3, 0.4), CFrame.new(O + Vector3.new(x, 0.3, z)) * CFrame.Angles(0, i, math.rad((i % 3) * 6)), STEEL_DK, Enum.Material.Metal) end
	end
	for _, sc in ipairs({ { -HW + 6, 0, 55 }, { HW - 6, 22, -50 }, { 22, HL - 6, 200 } }) do
		deco("CollapsedBeam", Vector3.new(1.6, 16, 1.6), CFrame.new(O + Vector3.new(sc[1], 6, sc[2])) * CFrame.Angles(math.rad(sc[3]), 0, math.rad(30)), WOOD_DK, Enum.Material.Wood)
	end

	-- ---- blocked side tunnels (dark mouths choked with rubble) + warning signs / barricades /
	-- hanging ropes -> makes the mine feel bigger + actively worked ----
	local function sign(x, z, text)
		deco("SignPost", Vector3.new(0.3, 5, 0.3), CFrame.new(O + Vector3.new(x, 2.5, z)), WOOD_DK, Enum.Material.Wood)
		local board = deco("Sign", Vector3.new(4, 2.3, 0.2), CFrame.new(O + Vector3.new(x, 5, z)), Color3.fromRGB(205, 172, 72), Enum.Material.WoodPlanks)
		local bb = Instance.new("BillboardGui"); bb.Adornee = board; bb.Size = UDim2.fromOffset(120, 42); bb.AlwaysOnTop = true; bb.MaxDistance = 80; bb.Parent = board
		local tl = Instance.new("TextLabel"); tl.BackgroundTransparency = 1; tl.Size = UDim2.fromScale(1, 1); tl.Font = Enum.Font.FredokaOne
		tl.Text = text; tl.TextColor3 = Color3.fromRGB(40, 22, 10); tl.TextScaled = true; tl.Parent = bb
	end
	local tunnelSpots = { { -HW + 2, 30, "x" }, { HW - 2, -34, "x" }, { -28, -HL + 2, "z" }, { 30, -HL + 2, "z" } }
	for _, tp in ipairs(tunnelSpots) do
		local x, z, ax = tp[1], tp[2], tp[3]
		local mouth = deco("TunnelMouth", (ax == "x") and Vector3.new(2, 13, 13) or Vector3.new(13, 13, 2), CFrame.new(O + Vector3.new(x, 6, z)), Color3.fromRGB(12, 10, 9), Enum.Material.Slate)
		-- subtle dust/smoke drifting out of the collapse
		local smokePE = Instance.new("ParticleEmitter")
		smokePE.Color = ColorSequence.new(Color3.fromRGB(120, 120, 128)); smokePE.Size = NumberSequence.new(6)
		smokePE.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 1) })
		smokePE.Lifetime = NumberRange.new(3, 6); smokePE.Rate = 1.4; smokePE.Speed = NumberRange.new(0.3, 1)
		smokePE.Acceleration = Vector3.new(0, 0.4, 0); smokePE.LightEmission = 0.1; smokePE.Parent = mouth
		for k = 1, 7 do
			local off = (ax == "x")
				and Vector3.new(x - (x > 0 and 3 or -3), 1 + (k * 1.4) % 6, z + (math.random() - 0.5) * 9)
				or Vector3.new(x + (math.random() - 0.5) * 9, 1 + (k * 1.4) % 6, z - (z > 0 and 3 or -3))
			deco("CaveIn", Vector3.new(3 + math.random() * 3, 3 + math.random() * 3, 3 + math.random() * 3),
				CFrame.new(O + off) * CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3),
				(k % 2 == 0) and ROCK_DK or ROCK, Enum.Material.Rock)
		end
		-- barricade planks + a warning sign just in front of the blocked mouth
		local inX = (ax == "x") and (x - (x > 0 and 6 or -6)) or x
		local inZ = (ax == "z") and (z + 6) or z
		for _, r in ipairs({ 8, -8 }) do
			deco("Barricade", Vector3.new((ax == "x") and 0.5 or 9, 0.7, (ax == "x") and 9 or 0.5), CFrame.new(O + Vector3.new(inX, 3, inZ)) * CFrame.Angles(0, 0, math.rad(r)), WOOD, Enum.Material.Wood)
		end
		if clearAt(inX, inZ, 2) then sign(inX + 2, inZ + 2, "⚠ KEEP OUT") end
	end
	for _, rp in ipairs({ { -20, 30 }, { 24, 34 }, { -34, -18 }, { 34, -6 }, { 0, 40 } }) do
		deco("HangRope", Vector3.new(0.14, 10 + math.random() * 6, 0.14), CFrame.new(O + Vector3.new(rp[1], H - 8, rp[2])), Color3.fromRGB(58, 46, 30))
	end

	-- ---- ATMOSPHERE: drifting cave dust + light floor fog + occasional falling pebbles ----
	for _, fp in ipairs({ Vector3.new(0, 3, 0), Vector3.new(-30, 3, 20), Vector3.new(30, 3, -20), Vector3.new(0, 3, -40), Vector3.new(0, 16, 0) }) do
		local att = Instance.new("Attachment"); att.Parent = Workspace.Terrain; att.WorldPosition = O + fp
		local dustPE = Instance.new("ParticleEmitter")
		dustPE.Color = ColorSequence.new(Color3.fromRGB(180, 165, 140))
		dustPE.Size = NumberSequence.new(fp.Y > 10 and 3 or 14)
		dustPE.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(1, 1) })
		dustPE.Lifetime = NumberRange.new(4, 8); dustPE.Rate = fp.Y > 10 and 4 or 2
		dustPE.Speed = NumberRange.new(0.3, 1.2); dustPE.SpreadAngle = Vector2.new(60, 60)
		dustPE.Acceleration = Vector3.new(0, fp.Y > 10 and -0.6 or 0.15, 0); dustPE.LightEmission = 0.2
		dustPE.Parent = att
		-- the attachment lives on Terrain (persistent) -> clean it up with the cave
		m.Destroying:Connect(function() att:Destroy() end)
	end
	-- small falling pebbles now and then (anchored, tweened down, self-cleaning; stops with the cave)
	task.spawn(function()
		while m.Parent do
			task.wait(1.6 + math.random() * 2.2)
			if not m.Parent then break end
			local x, z = (math.random() - 0.5) * (W - 30), (math.random() - 0.5) * (L - 30)
			local peb = mk({ Name = "FallingPebble", Size = Vector3.new(0.6, 0.6, 0.6), Color = ROCK_LT, Material = Enum.Material.Rock })
			peb.CFrame = CFrame.new(O + Vector3.new(x, H - 4, z)); peb.Parent = m
			TweenService:Create(peb, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(O + Vector3.new(x, 0.4, z)) }):Play()
			Debris:AddItem(peb, 1.1)
		end
	end)

	-- entry landing (where you teleport in, by the stairs) + exit shaft (back up)
	caveEntryCF = CFrame.new(O + Vector3.new(0, 4, L / 2 - 14)) * CFrame.Angles(0, math.rad(180), 0)
	-- staircase leading "down" into the room from the entry, purely cosmetic
	for i = 0, 6 do
		local step = mk({ Name = "Step", Size = Vector3.new(10, 1, 2.4), Color = ROCK_LT, Material = Enum.Material.Slate, CanCollide = true })
		step.CFrame = CFrame.new(O + Vector3.new(0, 6 - i * 1.0, L / 2 - 8 - i * 2.4)); step.Parent = m
	end

	-- the exit shaft (a lit alcove with a "Climb to the Surface" prompt; enabled in phase 'return')
	local exitPad = mk({ Name = "ExitShaft", Size = Vector3.new(8, 12, 8), Color = Color3.fromRGB(30, 26, 22),
		Material = Enum.Material.Rock, CanCollide = false })
	exitPad.CFrame = CFrame.new(O + Vector3.new(0, 6, -L / 2 + 8)); exitPad.Parent = m
	local ladder = mk({ Name = "Ladder", Size = Vector3.new(2.2, 12, 0.4), Color = WOOD, Material = Enum.Material.Wood })
	ladder.CFrame = CFrame.new(O + Vector3.new(0, 6, -L / 2 + 5)); ladder.Parent = m
	local epl = Instance.new("PointLight"); epl.Color = Color3.fromRGB(180, 210, 255); epl.Brightness = 2; epl.Range = 24; epl.Parent = exitPad
	caveExitCF = exitPad.CFrame
	local exitZone = mk({ Name = "ExitZone", Size = Vector3.new(8, 12, 8), Transparency = 1, CanQuery = true })
	exitZone.CFrame = exitPad.CFrame; exitZone.Parent = m
	exitPrompt = Instance.new("ProximityPrompt")
	exitPrompt.ActionText = "Climb to the Surface"; exitPrompt.ObjectText = "Mine Shaft"
	exitPrompt.HoldDuration = 0.3; exitPrompt.MaxActivationDistance = 12; exitPrompt.RequiresLineOfSight = false
	exitPrompt.Enabled = false; exitPrompt.Parent = exitZone
	exitPrompt.Triggered:Connect(function() if phase == "return" then returnToSurface() end end)

	-- the mine cart on a short rail
	local cart = Instance.new("Model"); cart.Name = "MineCart"; cart.Parent = m
	local cartPos = O + Vector3.new(24, 3, -18)
	local bin = mk({ Name = "CartBin", Size = Vector3.new(6, 3.4, 4.4), Color = STEEL, Material = Enum.Material.Metal, CanCollide = true })
	bin.CFrame = CFrame.new(cartPos); bin.Parent = cart; cart.PrimaryPart = bin
	local inside = mk({ Name = "CartInside", Size = Vector3.new(5.2, 3, 3.6), Color = Color3.fromRGB(40, 42, 46), Material = Enum.Material.Metal })
	inside.CFrame = bin.CFrame * CFrame.new(0, 0.4, 0); inside.Parent = cart
	for _, wx in ipairs({ -2, 2 }) do
		for _, wz in ipairs({ -1.6, 1.6 }) do
			local wheel = mk({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 1.6, 1.6),
				Color = STEEL_DK, Material = Enum.Material.Metal })
			wheel.CFrame = bin.CFrame * CFrame.new(wx, -1.9, wz) * CFrame.Angles(0, 0, math.rad(90))
			wheel.Parent = cart
		end
	end
	for _, rz in ipairs({ -1.7, 1.7 }) do
		local rail = mk({ Name = "Rail", Size = Vector3.new(24, 0.3, 0.4), Color = STEEL_DK, Material = Enum.Material.Metal })
		rail.CFrame = CFrame.new(cartPos + Vector3.new(0, -2.5, rz)); rail.Parent = cart
	end
	-- ---- extra cart detailing (low-poly): rim, flared sides, riveted band, push handle, axles,
	-- wooden sleepers -- all built around the SAME cart position (nothing interactable moves) ----
	local function cpart(name, size, cf, color, shape)
		local p = mk({ Name = name, Size = size, Color = color, Material = Enum.Material.SmoothPlastic })
		if shape then p.Shape = shape end
		p.CFrame = cf; p.Parent = cart; return p
	end
	cpart("CartRim", Vector3.new(6.5, 0.5, 4.9), bin.CFrame * CFrame.new(0, 1.85, 0), STEEL_DK)
	for _, s in ipairs({ -1, 1 }) do
		cpart("CartSide", Vector3.new(6.3, 3.4, 0.3), bin.CFrame * CFrame.new(0, 0.3, s * 2.35) * CFrame.Angles(math.rad(s * -9), 0, 0), STEEL)
	end
	cpart("CartBand", Vector3.new(6.35, 0.5, 4.75), bin.CFrame * CFrame.new(0, -0.5, 0), STEEL_DK)
	for i = -2, 2 do
		cpart("Rivet", Vector3.new(0.24, 0.24, 0.24), bin.CFrame * CFrame.new(i * 1.2, -0.5, 2.28), Color3.fromRGB(184, 188, 196))
		cpart("Rivet", Vector3.new(0.24, 0.24, 0.24), bin.CFrame * CFrame.new(i * 1.2, -0.5, -2.28), Color3.fromRGB(184, 188, 196))
	end
	-- push handle (two posts + a cross bar) at the back
	for _, hz in ipairs({ -1.7, 1.7 }) do
		cpart("Handle", Vector3.new(0.35, 4.2, 0.35), bin.CFrame * CFrame.new(-3.5, 0.7, hz) * CFrame.Angles(math.rad(24), 0, 0), WOOD_DK)
	end
	cpart("HandleBar", Vector3.new(0.4, 0.4, 4), bin.CFrame * CFrame.new(-4.4, 2.4, 0), WOOD)
	-- axles between the wheel pairs
	for _, wx in ipairs({ -2, 2 }) do
		cpart("Axle", Vector3.new(3.6, 0.3, 0.3), bin.CFrame * CFrame.new(wx, -1.9, 0) * CFrame.Angles(0, math.rad(90), 0), STEEL_DK, Enum.PartType.Cylinder)
	end
	-- wooden sleepers (cross-ties) under the track
	for i = -2, 2 do
		cpart("Sleeper", Vector3.new(0.8, 0.4, 4.8), CFrame.new(cartPos + Vector3.new(i * 4.4, -2.75, 0)), WOOD_DK)
	end
	local cbb = Instance.new("BillboardGui"); cbb.Adornee = bin; cbb.Size = UDim2.fromOffset(180, 44)
	cbb.StudsOffset = Vector3.new(0, 3.4, 0); cbb.AlwaysOnTop = true; cbb.MaxDistance = 120; cbb.Parent = bin
	local cbt = Instance.new("TextLabel"); cbt.BackgroundTransparency = 1; cbt.Size = UDim2.fromScale(1, 1)
	cbt.Font = Enum.Font.FredokaOne; cbt.Text = "💎 Mine Cart"; cbt.TextColor3 = DIAMOND
	cbt.TextStrokeColor3 = Color3.new(0, 0, 0); cbt.TextStrokeTransparency = 0; cbt.TextScaled = true; cbt.Parent = cbb
	local depositZone = mk({ Name = "DepositZone", Size = Vector3.new(9, 6, 8), Transparency = 1, CanQuery = true })
	depositZone.CFrame = bin.CFrame; depositZone.Parent = cart
	local dp = Instance.new("ProximityPrompt")
	dp.ActionText = "Deposit Diamonds"; dp.ObjectText = "Mine Cart"; dp.HoldDuration = 0.25
	dp.MaxActivationDistance = 12; dp.RequiresLineOfSight = false; dp.Parent = depositZone
	dp.Triggered:Connect(depositAtCart)
	mineCart = cart

	-- the ore nodes, on the seam positions worked out above (so the decor already avoided them)
	oreNodes = {}
	for i, sp in ipairs(nodeSpots) do
		-- AIMED AT THE ROOM CENTRE. buildOreNode puts the worked face, the seam, the timbering
		-- and all the gear on local -Z, so the dig has to face the way the player walks up to
		-- it -- the old CFrame.Angles(0, -a, 0) left them pointing whichever way the maths fell.
		local at = O + Vector3.new(sp.x, 1.6, sp.z)
		buildOreNode(CFrame.new(at, O + Vector3.new(0, 1.6, 0)), i)
	end

	-- ======================================================================
	-- LOW-POLY SIMULATOR RESTYLE + SOLIDIFY PASS (runs over the whole cave for a consistent look)
	--  * flatten realistic materials -> clean SmoothPlastic (no PBR/rock textures)
	--  * retint the stone family to bright stylised greys (lighter at the front, darker at the back)
	--  * calm the crystals (SmoothPlastic gem, no neon bloom) -- keep torch/lamp/ore-gem glow
	--  * SOLIDIFY: every VISIBLE part gets CanCollide=true so you can't walk through the cave;
	--    invisible trigger/marker parts (deposit/exit zones, light markers) stay non-solid so the
	--    prompts + teleports still work.
	-- ======================================================================
	-- THE STONE GOT DARKER WITH THE LIGHTS. Pale grey rock looks lit even with nothing shining on
	-- it, so dimming the fixtures alone left the cave bright-LOOKING but unlit -- the worst of
	-- both. Roughly half the old values.
	local GREY = { Color3.fromRGB(52, 54, 60), Color3.fromRGB(41, 43, 48), Color3.fromRGB(31, 33, 38), Color3.fromRGB(22, 23, 28) }
	local function greyByZ(z, jit)
		local base = GREY[4]:Lerp(GREY[1], math.clamp((z + HL) / L, 0, 1))
		return (jit % 2 == 0) and base:Lerp(Color3.new(1, 1, 1), 0.05) or base:Lerp(Color3.new(0, 0, 0), 0.05)
	end
	local STONE = { WallRock = true, Floor = true, WallN = true, WallS = true, WallE = true, WallW = true,
		Rubble = true, Stalagmite = true, Stalactite = true, Gravel = true, Pebble = true, CaveIn = true,
		TunnelMouth = true, Ore = true, OreChip = true, Step = true }
	-- these WERE called "Chunk". The cookie quest on island 3 sweeps all of Workspace for any
	-- name containing "chunk" and turns each one into a chocolate pickup, so the mine was
	-- growing chocolate every time you walked into it. Both ends are fixed: the sweep is now
	-- distance-scoped to island 3, and nothing down here shares the name any more.
	local CRYSTAL = { BigCrystal = true, Crystal = true, CrystalVein = true, Shard = true }
	local KEEPNEON = { TorchFire = true, LampGlow = true, Gem = true }
	local gi = 0
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			gi = gi + 1
			-- THE CRYSTALS AND GEMS ARE THE EXCEPTION TO ALL THE DIMMING.
			--
			-- They were flattened to SmoothPlastic when the cave was a lit room, where a matte
			-- crystal catching the torchlight looked right. In a black cave a matte crystal is
			-- simply invisible -- and these are the things you are down here to find, plus the
			-- only landmarks you have to navigate by. So they go NEON, and their lights are set
			-- to fixed values rather than inheriting the dimming the rest of the cave got: the
			-- point of the dark is to make these stand out, not to hide them too.
			if CRYSTAL[p.Name] then
				p.Material = Enum.Material.Neon; p.Reflectance = 0.1
				for _, l in ipairs(p:GetChildren()) do
					if l:IsA("PointLight") then
						l.Brightness = 1.8; l.Range = 21; l.Shadows = false
					end
				end
			elseif KEEPNEON[p.Name] then
				for _, l in ipairs(p:GetChildren()) do
					if l:IsA("PointLight") then
						l.Brightness = (p.Name == "Gem") and 3.0 or 2.0
						l.Range      = (p.Name == "Gem") and 20 or 18
					end
				end
			else
				p.Material = Enum.Material.SmoothPlastic
			end
			if p.Name == "Ceiling" then
				p.Color = GREY[4]
			elseif STONE[p.Name] then
				p.Color = greyByZ((p.Position - O).Z, gi)
			end
			-- visible = solid (can't walk through the cave); invisible triggers + the exit alcove you
			-- stand inside stay walk-through
			p.CanCollide = (p.Transparency < 1) and p.Name ~= "ExitShaft"
		end
	end
end

-- ============================================================================
-- TELEPORTS  (into / out of the private mine)
-- ============================================================================
-- ============================================================================
-- CAVE DARKNESS
-- ============================================================================
-- The build deliberately never touched global Lighting -- correct, because the mine used to be
-- one room in a bright outdoor game and stamping on Lighting would have dimmed the islands too.
--
-- It is worth it now, and only now, because three things are true: the mine is a PRIVATE,
-- per-player model you can only be inside alone, you are wearing a headlamp built to be the
-- thing you see by, and this is a LocalScript so it changes nothing for anybody else. Fixtures
-- and stone colours can only take you so far -- ambient light reaches every surface no matter
-- how dim the lamps are, and while that stays at daylight levels the cave cannot be dark.
--
-- Everything is captured before it is touched and put straight back on the way out, including
-- if you die down there.
local litSaved
local function caveDark(on)
	if on then
		if litSaved then return end
		litSaved = {
			amb  = Lighting.Ambient,
			out  = Lighting.OutdoorAmbient,
			bri  = Lighting.Brightness,
			fog  = Lighting.FogEnd,
			fogs = Lighting.FogStart,
			fogc = Lighting.FogColor,
		}
		-- BLACK, not dim. Ambient is what stops a cave being dark, so it goes to nothing; the
		-- fog closes to 90 studs so anything past your lamp is gone rather than merely faint.
		Lighting.Ambient        = Color3.fromRGB(0, 0, 0)
		Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
		Lighting.Brightness     = 0
		Lighting.FogEnd         = 90
		Lighting.FogStart       = 12
		Lighting.FogColor       = Color3.fromRGB(0, 0, 0)
	elseif litSaved then
		Lighting.Ambient        = litSaved.amb
		Lighting.OutdoorAmbient = litSaved.out
		Lighting.Brightness     = litSaved.bri
		Lighting.FogEnd         = litSaved.fog
		Lighting.FogStart       = litSaved.fogs
		Lighting.FogColor       = litSaved.fogc
		litSaved = nil
	end
end

-- dying underground must not leave the whole game dark
player.CharacterAdded:Connect(function()
	if phase ~= "mine" then caveDark(false) end
end)

function enterMine()
	if busy or phase ~= "descend" then return end
	busy = true
	buildCave()
	-- quick fade so the teleport isn't jarring
	local fade = Instance.new("ScreenGui"); fade.IgnoreGuiInset = true; fade.DisplayOrder = 30; fade.Parent = PlayerGui
	local ff = Instance.new("Frame"); ff.Size = UDim2.fromScale(1, 1); ff.BackgroundColor3 = Color3.new(0, 0, 0)
	ff.BackgroundTransparency = 1; ff.BorderSizePixel = 0; ff.Parent = fade
	TweenService:Create(ff, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
	task.wait(0.4)
	local char = player.Character
	if char and caveEntryCF then char:PivotTo(caveEntryCF) end
	phase = "mine"
	caveDark(true)
	updateObjective()
	task.wait(0.15)
	TweenService:Create(ff, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(fade, 0.5)
	notify("⛏️ Mine 10 Diamond Ore nodes down here!", DIAMOND)
	busy = false
end

function returnToSurface()
	if busy or phase ~= "return" then return end
	busy = true
	if exitPrompt then exitPrompt.Enabled = false end
	local fade = Instance.new("ScreenGui"); fade.IgnoreGuiInset = true; fade.DisplayOrder = 30; fade.Parent = PlayerGui
	local ff = Instance.new("Frame"); ff.Size = UDim2.fromScale(1, 1); ff.BackgroundColor3 = Color3.new(0, 0, 0)
	ff.BackgroundTransparency = 1; ff.BorderSizePixel = 0; ff.Parent = fade
	TweenService:Create(ff, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
	task.wait(0.4)
	local char = player.Character
	if char and surfaceReturnCF then char:PivotTo(surfaceReturnCF) end
	task.wait(0.15)
	TweenService:Create(ff, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(fade, 0.5)
	busy = false
	completeQuest()
end

-- leaveMine(): the "Back to Surface" button. If the cart is full it finishes the quest; otherwise
-- it climbs you out but KEEPS the cave + progress and re-arms the shaft (phase 'descend') so you
-- can walk back into it and carry on. (Assigned to the forward-declared upvalue above.)
leaveMine = function()
	if busy then return end
	if phase == "return" then returnToSurface(); return end
	if phase ~= "mine" then return end
	busy = true
	local fade = Instance.new("ScreenGui"); fade.IgnoreGuiInset = true; fade.DisplayOrder = 30; fade.Parent = PlayerGui
	local ff = Instance.new("Frame"); ff.Size = UDim2.fromScale(1, 1); ff.BackgroundColor3 = Color3.new(0, 0, 0)
	ff.BackgroundTransparency = 1; ff.BorderSizePixel = 0; ff.Parent = fade
	TweenService:Create(ff, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
	task.wait(0.4)
	local char = player.Character
	if char and surfaceReturnCF then char:PivotTo(surfaceReturnCF) end
	caveDark(false)
	phase = "descend"
	updateObjective()
	task.wait(0.15)
	TweenService:Create(ff, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(fade, 0.5)
	busy = false
	notify("⛏️ You climbed out. Re-enter the shaft to keep mining.", GOLD)
end

-- ============================================================================
-- COMPLETE + RESET
-- ============================================================================
local function grantRewards()
	local coinEvent = ReplicatedStorage:FindFirstChild("CoinEvent")
	if coinEvent then pcall(function() coinEvent:FireServer(COIN_REWARD) end) end
	-- XP / Gems are shown on the card; wire real remotes here if/when they exist.
end

function completeQuest()
	caveDark(false)
	phase = "done"
	takeGear()                                   -- the kit goes back with the job
	updateObjective()
	grantRewards()
	_G.tunnelQuestComplete = true   -- unlocks the island-11 stand (Shop_AllInOne)
	if heldGem then heldGem:Destroy(); heldGem = nil end
	showCard(("✅ QUEST COMPLETE!\n+%d Coins   +%d XP   +%d Gems"):format(COIN_REWARD, XP_REWARD, GEM_REWARD), 4.5)
	notify(("🏆 Tunnel cleared! +%d Coins, +%d XP, +%d Gems"):format(COIN_REWARD, XP_REWARD, GEM_REWARD), GOLD)

	-- reseal after a bit so the player can run it again
	task.delay(6, function()
		if caveModel then caveModel:Destroy(); caveModel = nil end
		if mineShaft then mineShaft:Destroy(); mineShaft = nil end
		if heldCrate then heldCrate:Destroy(); heldCrate = nil end
		for _, c in ipairs(groundCrates) do if c and c.Parent then c:Destroy() end end
		groundCrates = {}
		oreNodes = {}; cartFillParts = {}; mineCart = nil; exitPrompt = nil
		placedCrates = 0; minedNodes = 0; carriedDiam = 0; cartCount = 0
		carryingCrate = false; started = false; phase = "idle"
		if blastWall then blastWall:Destroy(); blastWall = nil end
		buildBlastZone()          -- wall back up, ready to blast again (crates spawn when re-taken)
		enableStart()
		updateObjective()
		notify("⛏️ The tunnel sealed back up -- take the quest again anytime!", ROCK_LT)
	end)
end

-- ============================================================================
-- DYNAMITE CRATE PICKUPS  (grab -> carry in hand -> plant on the X)
-- ============================================================================
local function spawnCrateAt(pos)
	local m = buildDynamiteCrate()
	m:PivotTo(CFrame.new(pos + Vector3.new(0, 1.4, 0)))
	local main = m.PrimaryPart
	main.CanQuery = true
	local hl = Instance.new("Highlight"); hl.FillTransparency = 1; hl.OutlineColor = DYN_RED
	hl.OutlineTransparency = 0.2; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = m; hl.Parent = m
	m.Parent = Workspace
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab Dynamite"; prompt.ObjectText = "Dynamite"; prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 10; prompt.RequiresLineOfSight = false; prompt.Parent = main
	prompt.Triggered:Connect(function()
		if phase ~= "blast" or carryingCrate then
			if carryingCrate then notify("💥 Plant the crate you're holding on the X first!", DYN_RED) end
			return
		end
		carryingCrate = true
		if hl then hl.Enabled = false end
		prompt.Enabled = false
		m:Destroy()   -- consumed -> you're now holding it
		heldCrate = buildDynamiteCrate()
		weldToHand(heldCrate, CFrame.new(0, -2.4, -0.4))
		if placePrompt then placePrompt.Enabled = true end
		pointTo(blastCF.Position)
		notify("💥 Carry it to the Blast Zone X and plant it!", DYN_RED)
	end)
	groundCrates[#groundCrates + 1] = m
end

function spawnGroundCrates()
	for _, c in ipairs(groundCrates) do if c and c.Parent then c:Destroy() end end
	groundCrates = {}
	local pos, right, look = blastCF.Position, blastCF.RightVector, blastCF.LookVector
	-- a little stack of crates off to the side of the blast zone
	for i = 1, CRATES_NEEDED do
		spawnCrateAt(pos + look * 14 + right * ((i - 2) * 4) - Vector3.new(0, 8, 0))
	end
end

-- planting/throwing the carried charge onto the X
local function wirePlacePrompt()
	if not placePrompt then return end
	placePrompt.Triggered:Connect(function()
		if phase ~= "blast" or not carryingCrate then return end
		local fromPos = heldCrate and heldCrate.PrimaryPart and heldCrate.PrimaryPart.Position
		carryingCrate = false
		if heldCrate then heldCrate:Destroy(); heldCrate = nil end
		placePrompt.Enabled = false
		snapCrateToSlot(fromPos)   -- arcs the TNT onto the X
		placedCrates = placedCrates + 1
		updateObjective()
		if placedCrates >= CRATES_NEEDED then
			notify("💥 All charges set! Stand back...", DYN_RED)
			task.delay(0.9, detonate)
		else
			notify(("💥 Charge %d/%d set -- grab another!"):format(placedCrates, CRATES_NEEDED), DYN_RED)
			-- nudge back toward the TNT source (the brick, or a leftover ground crate)
			if tntBrick and firstBasePart(tntBrick) then
				pointTo(firstBasePart(tntBrick).Position)
			else
				for _, c in ipairs(groundCrates) do
					if c and c.Parent then pointTo(c.PrimaryPart and c.PrimaryPart.Position or blastCF.Position); break end
				end
			end
		end
	end)
end

-- wireTntSource(): make the world brick named "tnt" the (repeatable) place you grab charges from --
-- walk up, "Grab TNT", carry it to the X, throw it on. Returns false if no such brick exists.
local function wireTntSource()
	local part = tntBrick and firstBasePart(tntBrick)
	if not part then return false end
	if not tntPrompt then
		-- hide the plain marker brick and stand a clearly-labelled DYNAMITE barrel where it was
		local pos = part.Position
		for _, q in ipairs(tntBrick:IsA("Model") and tntBrick:GetDescendants() or { tntBrick }) do
			if q:IsA("BasePart") then q.Transparency = 1; q.CanCollide = false; q.CanQuery = false end
		end
		local sup = Instance.new("Model"); sup.Name = "DynamiteSupply"; sup.Parent = Workspace
		local barrel = mk({ Name = "DynBarrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 4.6, 4.6),
			Color = Color3.fromRGB(150, 58, 44), Material = Enum.Material.SmoothPlastic, CanCollide = true })
		barrel.CFrame = CFrame.new(pos + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
		barrel.Parent = sup; sup.PrimaryPart = barrel
		for _, hy in ipairs({ -1.7, 0, 1.7 }) do
			local hoop = mk({ Name = "Hoop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4.75, 4.75),
				Color = STEEL_DK, Material = Enum.Material.SmoothPlastic })
			hoop.CFrame = barrel.CFrame * CFrame.new(hy, 0, 0); hoop.Parent = sup
		end
		-- a yellow hazard band + dynamite sticks poking out the top
		local band = mk({ Name = "HazardBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 4.8, 4.8),
			Color = Color3.fromRGB(240, 205, 70), Material = Enum.Material.SmoothPlastic })
		band.CFrame = barrel.CFrame; band.Parent = sup
		for i = -1, 1 do
			local stick = mk({ Name = "Dynamite", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 0.7, 0.7),
				Color = DYN_RED, Material = Enum.Material.SmoothPlastic })
			stick.CFrame = CFrame.new(pos + Vector3.new(i * 0.85, 5.7, 0)) * CFrame.Angles(0, 0, math.rad(90)); stick.Parent = sup
		end
		local hl = Instance.new("Highlight"); hl.FillColor = DYN_RED; hl.FillTransparency = 0.85
		hl.OutlineColor = Color3.fromRGB(255, 200, 60); hl.OutlineTransparency = 0.1; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = sup; hl.Parent = sup
		-- big readable "DYNAMITE" label so players know what it is
		local bb = Instance.new("BillboardGui"); bb.Adornee = barrel; bb.Size = UDim2.fromOffset(200, 66)
		bb.StudsOffset = Vector3.new(0, 4.4, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 150; bb.Parent = barrel
		local t1 = Instance.new("TextLabel"); t1.BackgroundTransparency = 1; t1.Size = UDim2.new(1, 0, 0.62, 0)
		t1.Font = Enum.Font.FredokaOne; t1.Text = "🧨 DYNAMITE"; t1.TextColor3 = Color3.fromRGB(255, 90, 70)
		t1.TextStrokeColor3 = Color3.new(0, 0, 0); t1.TextStrokeTransparency = 0; t1.TextScaled = true; t1.Parent = bb
		local t2 = Instance.new("TextLabel"); t2.BackgroundTransparency = 1; t2.Position = UDim2.new(0, 0, 0.62, 0)
		t2.Size = UDim2.new(1, 0, 0.38, 0); t2.Font = Enum.Font.FredokaOne; t2.Text = "[E] Grab"
		t2.TextColor3 = Color3.fromRGB(255, 240, 200); t2.TextStrokeColor3 = Color3.new(0, 0, 0); t2.TextStrokeTransparency = 0; t2.TextScaled = true; t2.Parent = bb
		part = barrel   -- the prompt now lives on the barrel
		part.CanQuery = true
		tntPrompt = Instance.new("ProximityPrompt")
		tntPrompt.ActionText = "Grab Dynamite"; tntPrompt.ObjectText = "Dynamite"; tntPrompt.HoldDuration = 0.2
		tntPrompt.MaxActivationDistance = 12; tntPrompt.RequiresLineOfSight = false; tntPrompt.Parent = part
		tntPrompt.Triggered:Connect(function()
			if phase ~= "blast" or carryingCrate then
				if carryingCrate then notify("💥 Throw the dynamite you're holding onto the X first!", DYN_RED) end
				return
			end
			if placedCrates >= CRATES_NEEDED then return end
			carryingCrate = true
			heldCrate = buildDynamiteCrate()
			weldToHand(heldCrate, CFrame.new(0, -2.4, -0.4))
			if placePrompt then placePrompt.Enabled = true end
			pointTo(blastCF.Position)
			notify("🧨 Carry the dynamite to the X and throw it on!", DYN_RED)
		end)
	end
	tntPrompt.Enabled = true
	return true
end

-- ============================================================================
-- START  (NPC prompt if present, else a quest board at the blast zone)
-- ============================================================================
local startPrompt

function enableStart()
	if startPrompt then startPrompt.Enabled = true end
end

local function beginQuest()
	if started then return end
	started = true
	phase = "blast"
	giveGear()                                   -- hard hat + pack, before you go anywhere near the dark
	if startPrompt then startPrompt.Enabled = false end
	wirePlacePrompt()
	-- prefer the placed "tnt" brick as the charge source; otherwise spawn a stack of crates
	if not (tntBrick and wireTntSource()) then spawnGroundCrates() end
	updateObjective()
	if tntBrick then
		notify("💥 Blast Open the Tunnel! Grab TNT and throw 3 charges onto the X.", DYN_RED)
	else
		notify("💥 Blast Open the Tunnel! Carry 3 Dynamite Crates to the X.", DYN_RED)
	end
	pointTo((tntBrick and firstBasePart(tntBrick) and firstBasePart(tntBrick).Position) or blastCF.Position)
end

local function buildStartBoard()
	local board = mk({ Name = "TunnelQuestBoard", Size = Vector3.new(0.4, 6, 5), Color = WOOD_DK, Material = Enum.Material.Wood, CanCollide = true, CanQuery = true })
	board.CFrame = CFrame.new(blastCF.Position + blastCF.LookVector * 10 - Vector3.new(0, 3, 0))
	board.Parent = blastWall or Workspace
	local sign = mk({ Name = "Sign", Size = Vector3.new(0.2, 3.4, 4.4), Color = Color3.fromRGB(60, 46, 30), Material = Enum.Material.WoodPlanks })
	sign.CFrame = board.CFrame * CFrame.new(0.3, 1.4, 0); sign.Parent = board.Parent
	local bb = Instance.new("BillboardGui"); bb.Adornee = sign; bb.Size = UDim2.fromOffset(220, 70)
	bb.StudsOffset = Vector3.new(0, 2.6, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 160; bb.Parent = sign
	local tl = Instance.new("TextLabel"); tl.BackgroundTransparency = 1; tl.Size = UDim2.fromScale(1, 1)
	tl.Font = Enum.Font.FredokaOne; tl.Text = "💥 Blast Open\nthe Tunnel"; tl.TextColor3 = GOLD
	tl.TextStrokeColor3 = Color3.new(0, 0, 0); tl.TextStrokeTransparency = 0; tl.TextScaled = true; tl.Parent = bb
	startPrompt = Instance.new("ProximityPrompt")
	startPrompt.ActionText = "Take Quest"; startPrompt.ObjectText = "Miner's Job"; startPrompt.HoldDuration = 0
	startPrompt.MaxActivationDistance = 12; startPrompt.RequiresLineOfSight = false; startPrompt.Parent = sign
	startPrompt.Triggered:Connect(beginQuest)
end

-- ============================================================================
-- QUEST NPC -- paged speech-bubble dialogue that gives + starts the quest (the same pattern the
-- other island NPCs use). Reading past the last page accepts the job and kicks off Phase 1.
-- ============================================================================
local function npcBubble(head, text, footer)
	local prev = head:FindFirstChild("SpeechBubble"); if prev then prev:Destroy() end
	local bb = Instance.new("BillboardGui"); bb.Name = "SpeechBubble"; bb.Adornee = head
	bb.Size = UDim2.new(0, 330, 0, 150); bb.StudsOffset = Vector3.new(0, 5.5, 0)
	bb.AlwaysOnTop = true; bb.MaxDistance = 120; bb.Parent = head
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = Color3.fromRGB(255, 246, 232)
	f.BackgroundTransparency = 0.05; f.BorderSizePixel = 0; f.Parent = bb
	local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0, 14); cr.Parent = f
	local st = Instance.new("UIStroke"); st.Color = GOLD; st.Thickness = 2; st.Parent = f
	local pd = Instance.new("UIPadding"); pd.PaddingTop = UDim.new(0, 12); pd.PaddingBottom = UDim.new(0, 12); pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = f
	local l = Instance.new("TextLabel"); l.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1; l.Font = Enum.Font.FredokaOne; l.Text = text
	l.TextColor3 = Color3.fromRGB(70, 46, 20); l.TextScaled = true; l.TextWrapped = true; l.Parent = f
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 20; sz.Parent = l
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1, 0.2); h.Position = UDim2.fromScale(0, 0.8)
		h.BackgroundTransparency = 1; h.Font = Enum.Font.FredokaOne; h.Text = footer
		h.TextColor3 = Color3.fromRGB(150, 110, 50); h.TextScaled = true; h.Parent = f
		local hs = Instance.new("UITextSizeConstraint"); hs.MaxTextSize = 13; hs.Parent = h
	end
	return bb
end

local function questPages()
	if started then return { "The tunnel's blasting -- get down there and grab those diamonds! ⛏️" } end
	return {
		"Well howdy! I'm the mine foreman. 🪓",
		"There's a sealed tunnel deep in this canyon -- packed with DIAMONDS.",
		"Grab the TNT and throw 3 charges onto the big red X to BLAST it open! 💥",
		"Then head down, mine 10 diamond ore, load the cart, and climb back up.",
		"Ready? Let's blow it open!",
	}
end

local function wireQuestNPC(head)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = "Mine Foreman"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false; prompt.Parent = head
	local pages, index = nil, 0
	local function close() local b = head:FindFirstChild("SpeechBubble"); if b then b:Destroy() end; index = 0; pages = nil; prompt.ActionText = "Talk" end
	prompt.Triggered:Connect(function()
		if started then close(); return end
		if index == 0 then pages = questPages() end
		index += 1
		if not pages or index > #pages then close(); beginQuest(); return end   -- read everything -> start
		local last = index >= #pages
		npcBubble(head, pages[index], last and "[E] start!" or ("[E] more  (%d/%d)"):format(index, #pages))
		prompt.ActionText = last and "Start" or "Continue"
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then close() end end)
	startPrompt = prompt   -- so beginQuest can disable it, and enableStart() can re-arm it on reset
end

-- ============================================================================
-- BOOT
-- ============================================================================
task.spawn(function()
	-- find the blast zone marker (preferred) or fall back to island11's edge
	local island = pollFor(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("Model") and nameHasAny(d.Name, ISLAND_NAMES) then return d end
		end
		return nil
	end, 60)
	local islandPos
	if island then
		local ok, cf = pcall(function() return (select(1, island:GetBoundingBox())) end)
		islandPos = (ok and cf) and cf.Position or nil
	end

	local marker = findByAnyName(BLAST_NAMES, islandPos, ISLAND_RANGE)
		or pollFor(function() return findByAnyName(BLAST_NAMES, islandPos, ISLAND_RANGE) end, 30)
	if marker then
		local part = firstBasePart(marker)
		blastCF = part.CFrame
		-- hide the marker itself -- it's only a reference
		for _, p in ipairs(marker:IsA("Model") and marker:GetDescendants() or { marker }) do
			if p:IsA("BasePart") then p.Transparency = 1; p.CanCollide = false; p.CanQuery = false end
		end
	elseif islandPos then
		blastCF = CFrame.new(islandPos + Vector3.new(0, 4, 40), islandPos)  -- face inward from the edge
		warn("[TunnelQuest] no 'BlastZone' marker -- anchoring the blast zone to island11's edge")
	else
		-- last resort: anchor near where the player is standing
		local hrp = pollFor(hrpOf, 30)
		local base = hrp and hrp.Position or Vector3.new(0, 10, 0)
		blastCF = CFrame.new(base + Vector3.new(0, 0, 20), base)
		warn("[TunnelQuest] island11 not found -- anchoring the blast zone near the player")
	end

	buildBlastZone()

	-- the part named "tnt" (inside the island11 model) marks where the dynamite supply sits
	tntBrick = findInModel(island, TNT_NAMES) or findByAnyName(TNT_NAMES, blastCF.Position, 900)
	if tntBrick then
		wireTntSource()                                   -- stand the DYNAMITE barrel at that part now
		if tntPrompt then tntPrompt.Enabled = false end   -- only grabbable once the quest is started
	end

	-- prefer an NPC to give the quest via paged dialogue (like the other islands); else a quest board
	local npc = findByAnyName(NPC_NAMES, blastCF.Position, 160)
	if npc then
		local head = (npc:IsA("Model") and (npc:FindFirstChild("Head") or npc.PrimaryPart)) or firstBasePart(npc)
		if head then wireQuestNPC(head) else buildStartBoard() end
	else
		buildStartBoard()
	end

	print(("[TunnelQuest] ready on island11 -- blast zone at %.0f,%.0f,%.0f (%s); tnt=%s, npc=%s"):format(
		blastCF.Position.X, blastCF.Position.Y, blastCF.Position.Z, marker and "marker" or "fallback",
		tntBrick and "found" or "none", npc and "found" or "none"))
end)

-- ============================================================================
-- DEATH RECOVERY  (respawning drops held props + can strand you underground)
-- Dying in the mine covers the screen in black with "Welcome To The Caramel Cave" until you're
-- placed back inside the cave, then fades in -- so you never see the surface spawn flash by.
-- ============================================================================
local function showCaveVeil()   -- persistent black overlay + title (idempotent)
	local g = PlayerGui:FindFirstChild("CaveVeil")
	if g then return g end
	g = Instance.new("ScreenGui"); g.Name = "CaveVeil"; g.IgnoreGuiInset = true; g.DisplayOrder = 50; g.ResetOnSpawn = false; g.Parent = PlayerGui
	local ff = Instance.new("Frame"); ff.Size = UDim2.fromScale(1, 1); ff.BackgroundColor3 = Color3.new(0, 0, 0); ff.BorderSizePixel = 0; ff.Parent = g
	local tl = Instance.new("TextLabel"); tl.AnchorPoint = Vector2.new(0.5, 0.5); tl.Position = UDim2.fromScale(0.5, 0.5)
	tl.Size = UDim2.fromOffset(680, 120); tl.BackgroundTransparency = 1; tl.Font = Enum.Font.FredokaOne
	tl.Text = "Welcome To The Caramel Cave"; tl.TextColor3 = Color3.fromRGB(255, 224, 178); tl.TextScaled = true; tl.Parent = ff
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 42; sz.Parent = tl
	return g
end
local function hideCaveVeil(g)
	g = g or PlayerGui:FindFirstChild("CaveVeil")
	if not g then return end
	local ff = g:FindFirstChildWhichIsA("Frame")
	local tl = ff and ff:FindFirstChildWhichIsA("TextLabel")
	if ff then TweenService:Create(ff, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play() end
	if tl then TweenService:Create(tl, TweenInfo.new(0.6), { TextTransparency = 1 }):Play() end
	Debris:AddItem(g, 0.75)
end

player.CharacterAdded:Connect(function(char)
	local underground = (phase == "mine" or phase == "return") and caveModel ~= nil
	if underground then showCaveVeil() end   -- keep the screen black through the respawn
	task.wait(0.6)
	heldCrate = nil; heldGem = nil; carryingCrate = false
	if phase == "blast" then
		if placePrompt then placePrompt.Enabled = false end
		local avail = 0
		for _, c in ipairs(groundCrates) do if c and c.Parent then avail = avail + 1 end end
		if avail < (CRATES_NEEDED - placedCrates) then spawnGroundCrates() end
	elseif underground and caveEntryCF then
		-- drop them back at the mine entrance (not the surface), then reveal the cave
		char:PivotTo(caveEntryCF)
		refreshHeldGem()
		task.wait(1.0)
		hideCaveVeil()
	end
	-- arm the NEXT death: raise the veil the instant they die underground (covers the death too)
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum.Died:Connect(function()
			if (phase == "mine" or phase == "return") and caveModel then showCaveVeil() end
		end)
	end
end)

-- ============================================================================
-- DEV COMMANDS  (only near the blast zone):  /blast  = auto-run to the mine
-- ============================================================================
local lastCmd, lastCmdAt = "", 0
local function onCommand(msg)
	local m = tostring(msg or ""):lower()
	-- both TextChatService and player.Chatted fire for one message -> debounce identical commands
	if m == lastCmd and (os.clock() - lastCmdAt) < 0.6 then return end
	lastCmd = m; lastCmdAt = os.clock()
	if m:sub(1, 6) == "/blast" then
		if not started then beginQuest() end
		-- auto-plant all charges + detonate, THEN auto-enter the mine (one-command test)
		if phase == "blast" then
			carryingCrate = false
			if heldCrate then heldCrate:Destroy(); heldCrate = nil end
			while placedCrates < CRATES_NEEDED do
				snapCrateToSlot(); placedCrates = placedCrates + 1
			end
			updateObjective()
			task.delay(0.4, detonate)
			-- once the blast opens the shaft (phase 'descend'), drop straight into the tunnel
			task.spawn(function()
				local t0 = os.clock()
				while phase ~= "descend" and os.clock() - t0 < 15 do task.wait(0.2) end
				if phase == "descend" then enterMine() end
			end)
		elseif phase == "descend" then
			enterMine()
		end
		print("[TunnelQuest][DEV] /blast -- charges auto-planted, entering mine")
	elseif m:sub(1, 5) == "/mine" then
		-- fill the cart instantly (for testing phase 4)
		if phase == "mine" then
			minedNodes = NODES_NEEDED; carriedDiam = NODES_NEEDED - cartCount
			depositAtCart()
		end
	end
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(mm)
		if mm.TextSource and mm.TextSource.UserId == player.UserId then onCommand(mm.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
