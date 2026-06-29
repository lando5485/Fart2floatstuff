-- ============================================================================
-- POPCORN TREES (easter egg) — on Popcorn Pinnacle there are two popcorn trees named "PopTree1"/"PopTree2".
-- Walk up and press E to TOGGLE a popping show: the tree HEATS UP (warm glow + rising steam, kernels quiver),
-- then it POPS — real popcorn-shaped kernels (bumpy clusters) burst into the air with puffs (+ optional sound).
-- Press E again — or wait it out — and it cools down and settles. Fully cosmetic + server-side.
-- ============================================================================

local Workspace    = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

-- =========================== EASY-EDIT CONFIG ===============================
local CONFIG = {
	treeNames    = { "PopTree1", "PopTree2" },    -- the popcorn-tree models to wire up
	promptText   = "Pop the Popcorn!",
	stopText     = "Settle Down",
	promptDist   = 14,                            -- how close you have to be (studs)
	promptDrop   = 4,                             -- lower the prompt this many studs below the tree centre (easier reach)
	heatTime     = 1.5,                           -- "heating up" buildup before the first pop (seconds)
	popInterval  = 0.18,                          -- seconds between pops while active
	piecesPerPop = 3,                             -- popcorn kernels launched per pop
	jigglePerPop = 3,                             -- how many tree kernels bounce per pop
	showDuration = 7,                             -- popping lasts this long, then auto-settles
	pieceSize    = 0.62,                          -- popcorn piece size (studs)
	popSoundId   = "",                            -- TODO optional: a soft "pop" sound id (rbxassetid://...)
}
-- ============================================================================

local SMOOTH = Enum.SurfaceType.Smooth
-- buttery white/cream popcorn tones
local POP_COLORS = { Color3.fromRGB(255, 252, 236), Color3.fromRGB(255, 246, 214), Color3.fromRGB(252, 236, 186), Color3.fromRGB(255, 240, 198) }
local function rnd(a, b) return a + math.random() * (b - a) end
local function newBall(size, color)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball; p.Size = size; p.Color = color; p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH
	p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.Massless = true; p.Anchored = false
	return p
end

-- a single popped kernel = a bumpy CLUSTER of welded blobs (reads as real popcorn), launched with physics
local function launchPiece(origin)
	local m = Instance.new("Model"); m.Name = "Popcorn"
	local base = CONFIG.pieceSize * rnd(0.8, 1.25)
	local root = newBall(Vector3.new(base, base * 0.95, base * rnd(0.9, 1.05)), POP_COLORS[math.random(1, #POP_COLORS)])
	root.Position = origin
	root.Parent = m; m.PrimaryPart = root
	for _ = 1, math.random(2, 3) do -- the lumpy bits that make it look popped
		local b = newBall(root.Size * rnd(0.5, 0.78), POP_COLORS[math.random(1, #POP_COLORS)])
		b.CFrame = root.CFrame * CFrame.new(rnd(-1, 1) * base * 0.5, rnd(-1, 1) * base * 0.5, rnd(-1, 1) * base * 0.5)
		b.Parent = m
		local w = Instance.new("WeldConstraint"); w.Part0 = root; w.Part1 = b; w.Parent = b
	end
	m.Parent = Workspace
	root.AssemblyLinearVelocity = Vector3.new(rnd(-28, 28), rnd(34, 58), rnd(-28, 28)) -- pop up + outward
	root.AssemblyAngularVelocity = Vector3.new(rnd(-16, 16), rnd(-16, 16), rnd(-16, 16))
	Debris:AddItem(m, 2.8)
end

-- briefly bulge a kernel part (scale = how big the bounce). Returns to its stored size even if the show stops.
local function jiggle(part, orig, scale)
	if part:GetAttribute("Popping") then return end
	part:SetAttribute("Popping", true)
	TweenService:Create(part, TweenInfo.new(0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = orig * scale }):Play()
	task.delay(0.09, function()
		if part.Parent then TweenService:Create(part, TweenInfo.new(0.13, Enum.EasingStyle.Quad), { Size = orig }):Play() end
		task.delay(0.16, function() if part.Parent then part:SetAttribute("Popping", nil) end end)
	end)
end

local function setupTree(tree)
	local cf, size
	if tree:IsA("Model") then cf, size = tree:GetBoundingBox()
	elseif tree:IsA("BasePart") then cf, size = tree.CFrame, tree.Size
	else return end

	-- kernels = parts in the upper portion (where the popcorn is). Fall back to all parts.
	local kernels = {}
	if tree:IsA("BasePart") then
		kernels[1] = { tree, tree.Size }
	else
		for _, d in ipairs(tree:GetDescendants()) do
			if d:IsA("BasePart") and d.Position.Y > cf.Position.Y + size.Y * 0.05 then kernels[#kernels + 1] = { d, d.Size } end
		end
		if #kernels == 0 then for _, d in ipairs(tree:GetDescendants()) do if d:IsA("BasePart") then kernels[#kernels + 1] = { d, d.Size } end end end
	end

	-- invisible anchor at the tree centre to host the prompt + glow + particles
	local anchor = Instance.new("Part")
	anchor.Name = "PopAnchor"; anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false
	anchor.Transparency = 1; anchor.Size = Vector3.new(1, 1, 1); anchor.CFrame = CFrame.new(cf.Position); anchor.Parent = tree

	local origin = cf.Position + Vector3.new(0, size.Y * 0.18, 0) -- where kernels pop from (upper canopy)
	local pAtt = Instance.new("Attachment"); pAtt.WorldPosition = origin; pAtt.Parent = anchor

	-- HEAT GLOW: warm light that builds while heating, flickers while popping, fades when settling
	local heat = Instance.new("PointLight")
	heat.Color = Color3.fromRGB(255, 138, 46); heat.Range = math.clamp(size.Magnitude * 0.35, 8, 22); heat.Brightness = 0; heat.Parent = anchor

	-- STEAM: gentle rising steam while the tree is hot
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.5), NumberSequenceKeypoint.new(1, 1) })
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.5) })
	steam.Lifetime = NumberRange.new(1, 1.9); steam.Speed = NumberRange.new(1.5, 3); steam.Rate = 0
	steam.SpreadAngle = Vector2.new(28, 28); steam.LightEmission = 0.3; steam.Acceleration = Vector3.new(0, 6, 0); steam.Parent = pAtt

	-- PUFF: a quick burst on each pop
	local puff = Instance.new("ParticleEmitter")
	puff.Texture = "rbxasset://textures/particles/smoke_main.dds"
	puff.Color = ColorSequence.new(Color3.fromRGB(255, 255, 252)); puff.Transparency = NumberSequence.new(0.35)
	puff.Lifetime = NumberRange.new(0.4, 0.8); puff.Speed = NumberRange.new(1, 3); puff.Rate = 0
	puff.SpreadAngle = Vector2.new(80, 80); puff.Size = NumberSequence.new(0.8); puff.LightEmission = 0.2
	puff.Acceleration = Vector3.new(0, 4, 0); puff.Parent = pAtt

	-- the prompt sits a bit LOWER than the tree centre so it's a comfortable height to walk up to
	local promptY = cf.Position.Y - math.min(CONFIG.promptDrop, size.Y * 0.4)
	local promptAnchor = Instance.new("Part")
	promptAnchor.Name = "PopPrompt"; promptAnchor.Anchored = true; promptAnchor.CanCollide = false; promptAnchor.CanQuery = false
	promptAnchor.Transparency = 1; promptAnchor.Size = Vector3.new(1, 1, 1)
	promptAnchor.CFrame = CFrame.new(cf.Position.X, promptY, cf.Position.Z); promptAnchor.Parent = tree
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = CONFIG.promptText; prompt.ObjectText = "Popcorn Tree"
	prompt.KeyboardKeyCode = Enum.KeyCode.E; prompt.MaxActivationDistance = CONFIG.promptDist
	prompt.RequiresLineOfSight = false; prompt.HoldDuration = 0; prompt.Parent = promptAnchor

	local active = false
	local function onePop()
		for _ = 1, CONFIG.piecesPerPop do
			launchPiece(origin + Vector3.new(rnd(-1, 1) * size.X * 0.4, rnd(-1, 1) * size.Y * 0.25, rnd(-1, 1) * size.Z * 0.4))
		end
		for _ = 1, CONFIG.jigglePerPop do local k = kernels[math.random(1, #kernels)]; if k then jiggle(k[1], k[2], 1.28) end end
		puff:Emit(3)
		if CONFIG.popSoundId ~= "" then
			local snd = Instance.new("Sound"); snd.SoundId = CONFIG.popSoundId; snd.Volume = 0.6
			snd.PlaybackSpeed = rnd(0.85, 1.25); snd.RollOffMaxDistance = 70; snd.Parent = anchor
			pcall(function() snd:Play() end); Debris:AddItem(snd, 2)
		end
	end

	local function startShow()
		if active then return end
		active = true; prompt.ActionText = CONFIG.stopText
		task.spawn(function()
			-- ---- HEATING UP: glow builds, steam rises, kernels quiver (anticipation before the pop) ----
			steam.Rate = 8
			TweenService:Create(heat, TweenInfo.new(CONFIG.heatTime, Enum.EasingStyle.Quad), { Brightness = 2.6 }):Play()
			local hr = 0
			while active and hr < CONFIG.heatTime do
				local k = kernels[math.random(1, #kernels)]; if k then jiggle(k[1], k[2], 1.08) end -- small quiver
				task.wait(0.12); hr = hr + 0.12
			end
			-- ---- POPPING ----
			local t = 0
			while active and t < CONFIG.showDuration do
				onePop()
				heat.Brightness = 2.0 + math.random() * 1.3 -- flicker hot
				task.wait(CONFIG.popInterval); t = t + CONFIG.popInterval
			end
			-- ---- COOL DOWN + SETTLE ----
			active = false; prompt.ActionText = CONFIG.promptText
			steam.Rate = 0
			TweenService:Create(heat, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
		end)
	end

	prompt.Triggered:Connect(function()
		if active then active = false else startShow() end -- toggle (the show task handles cool-down on stop)
	end)
	print("[PopcornTrees] ready: " .. tree.Name .. " (" .. #kernels .. " kernels)")
end

task.spawn(function()
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end
	for _, name in ipairs(CONFIG.treeNames) do
		task.spawn(function()
			local tree
			for _ = 1, 40 do tree = Workspace:FindFirstChild(name, true); if tree then break end; task.wait(1) end
			if not tree then warn("[PopcornTrees] '" .. name .. "' not found in Workspace -> skipped (check the name).") return end
			local ok, err = pcall(setupTree, tree)
			if not ok then warn("[PopcornTrees] setup failed for " .. name .. ": " .. tostring(err)) end
		end)
	end
end)
