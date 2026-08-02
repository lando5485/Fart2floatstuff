--======================================================================
-- CrystalMineQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- ISLAND-8 QUEST: "Candy Crystal Mine" -- adapted from the Mars crystal-mining task,
-- but SELF-CONTAINED and client-side (like CandyRealm's other island quests -- no
-- server modules, no remotes).
--
-- WHAT THE WORLD PROVIDES (name these in Studio, on island8):
--   * some objects named  crystal  (Part, Union, or Model) sitting on island8
--   * a "Candy Npc" (island8's) -- picked as the one NEAREST island8
--
-- WHAT THIS SCRIPT DOES (per-player, client-side):
--   * Talk to the Candy Npc -> accept -> you're handed a Pickaxe (built in code).
--   * Equip it and swing (click) at a crystal you're facing: each hit chips it smaller
--     (base stays planted), and the final hit SHATTERS it in a candy spark burst.
--   * Mine them all -> firework + "Crystals mined!" + _G.crystalQuestComplete.
--   * /complete finishes it instantly (near island8).
--======================================================================

local Players         = game:GetService("Players")
local Workspace       = game:GetService("Workspace")
local TweenService    = game:GetService("TweenService")
local Debris          = game:GetService("Debris")
local RunService      = game:GetService("RunService")   -- camera shake (cinematic + hazards)
local TextChatService = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_NAME       = "island8"
local CRYSTAL_NAME      = "crystal"          -- matched case-insensitively (== or contains)
local NPC_NAMES         = { "candy npc", "candynpc" }
local TALK_DISTANCE     = 12
local BANNER_RANGE      = 320
local HITS_PER_CRYSTAL  = 6                  -- pickaxe hits to shatter a crystal
-- Halfway through, the NPC re-forges your pickaxe: it hits harder, so the back half of
-- the job speeds up instead of dragging (the usual problem with "collect N" quests).
local UPGRADE_AFTER     = 3                  -- crystals mined before the upgrade fires
local UPGRADED_HITS     = 4                  -- hits per crystal once it's upgraded
-- Cave hazards: gentle on purpose -- they push you back a step, they don't kill you.
local HAZARDS_ON        = true
local ROCK_DROP_NAME    = "rockdrop"         -- parts named "rock drop" are the ceiling holes
local ROCKFALL_EVERY    = 12                 -- seconds between rockfalls at each drop point
local ROCK_LINGER       = 4                  -- seconds a landed boulder stays solid before crumbling
-- Poison sugar-gas vents erupt from parts you named "gas vents" in Studio. While a vent
-- is blowing you can't mine -- the gas fogs your view for a few seconds first.
local VENT_NAME         = "gasvent"          -- matched loosely: "gas vents", "GasVent2", ...
local VENT_EVERY        = 12                 -- seconds between eruptions AT EACH vent (per vent,
                                             -- not global -- each one runs its own timer)
local VENT_ACTIVE_TIME  = 4                  -- how long each eruption lasts
local VENT_MARGIN       = 14                 -- cloud reach BEYOND the vent part's own footprint
-- Each vent belongs to a crystal: mine that crystal and its vent is capped for good.
-- Pairing is automatic because the vents are modelled INSIDE crystal1..crystal4 -- the
-- vent's own crystal model IS the pairing. This table is only an override for any vent
-- that ends up outside its model. Names matched loosely (case/spaces/underscores ignored).
local VENT_PAIRS = {
	-- ["gas vent 1"] = "crystal1",
}
local GAS_BLUR_TIME     = 4                  -- seconds the screen stays FULLY fogged...
local GAS_FADE_TIME     = 1.8                -- ...then this long fading back to clear
local MINE_RANGE        = 14                 -- studs: how close/front a crystal must be to hit
local FACING_DOT        = 0.15               -- must be roughly facing the crystal
local HIT_COOLDOWN      = 0.35               -- seconds between counted swings
local MIN_VISIBLE_SCALE = 0.4                -- crystal never shrinks below this fraction...
local MIN_VISIBLE_STUDS = 3                  -- ...nor shorter than this many studs (stays hittable)

-- candy palette
local FILL   = Color3.fromRGB(255, 240, 248)
local STROKE = Color3.fromRGB(200, 60, 120)
local TEXTC  = Color3.fromRGB(80, 30, 60)
local HINTC  = Color3.fromRGB(150, 120, 160)
local PINK   = Color3.fromRGB(255, 95, 160)
local GOLD   = Color3.fromRGB(255, 205, 90)
local GREEN  = Color3.fromRGB(110, 210, 120)

-- ============================================================================
-- HELPERS
-- ============================================================================
local function firstBasePart(inst)
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end
-- lowercase, strip spaces/underscores/hyphens -- used for every name match in this file
local function loose(s) return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", "")) end
local function isVentName(n) return string.find(loose(n), VENT_NAME, 1, true) ~= nil end

-- The gas vent blocks live INSIDE the crystal models, and a vent can easily be bigger
-- than the crystal itself -- so they're excluded here, or a vent would get registered as
-- the mineable crystal and the real one would be untouchable.
local function largestBasePart(model)
	local best, bestMag = nil, -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not isVentName(d.Name) and d.Size.Magnitude > bestMag then
			best, bestMag = d, d.Size.Magnitude
		end
	end
	return best
end
local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat local r = fn(); if r then return r end; task.wait(0.5) until os.clock() - t0 > (timeout or 45)
	return fn()
end
local function findIsland8()
	return Workspace:FindFirstChild(ISLAND_NAME)
		or (function()
			for _, d in ipairs(Workspace:GetDescendants()) do
				if d:IsA("Model") and string.lower(d.Name):match("^island_?8$") then return d end
			end
		end)()
end
local function isCrystalName(name)
	return string.lower(name):match("^" .. CRYSTAL_NAME) ~= nil -- "crystal", "crystal1", "Crystal 2", ...
end
local function npcHeadOf(inst)
	if not inst then return nil end
	return (inst:IsA("Model") and (inst:FindFirstChild("Head") or inst.PrimaryPart or firstBasePart(inst)))
		or (inst:IsA("BasePart") and inst) or firstBasePart(inst)
end
local NPC_MAX_DIST = 400 -- an NPC must be within this of island8's centre to count as island8's (like island1)
local function findNPCNear(refPos)
	if not refPos then return nil end -- island8 not loaded yet -> DON'T grab a far NPC (e.g. island1's Candy Npc)
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		local nm = string.lower(d.Name)
		local match = false
		for _, want in ipairs(NPC_NAMES) do if nm == want then match = true; break end end
		if match then
			local head = npcHeadOf(d)
			if head then
				local dist = (head.Position - refPos).Magnitude
				if dist <= NPC_MAX_DIST and (not bestD or dist < bestD) then best, bestD = head, dist end
			end
		end
	end
	return best
end
local function pointTo(pos) if pos and _G.guideTrailTo then pcall(function() _G.guideTrailTo(pos) end) end end

-- ============================================================================
-- STATE
-- ============================================================================
local accepted   = false
local done       = false
local mined       = 0
local total       = 0
local crystals    = {}   -- [part] = { hits, size, cframe }
local npcHead
local islandRef            -- a reference position on island8
local pickaxeGranted = false
local pickaxeUpgraded = false
local upgradePickaxe   -- defined with the pickaxe; mineHit calls it at the halfway mark
-- the gas hazard lives further down the file, but the pickaxe swing (above it) has to
-- ask whether you're gassed before it lets you mine
local isGassed, inActiveGas, gasScreen, wireGasVents, killVentsFor, wireRockDrops

-- ============================================================================
-- SPEECH BUBBLE + OBJECTIVE BANNER  (island1 look/behaviour)
-- ============================================================================
local function hideBubble(a) local p = a:FindFirstChild("SpeechBubble"); if p then p:Destroy() end end
local function showBubble(a, text, persist, footer)
	hideBubble(a)
	local bb = Instance.new("BillboardGui"); bb.Name = "SpeechBubble"; bb.Adornee = a
	bb.Size = UDim2.new(0,320,0,150); bb.StudsOffset = Vector3.new(0,5.5,0); bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1,1); f.BackgroundColor3 = FILL; f.BackgroundTransparency = 0.05; f.BorderSizePixel = 0; f.Parent = bb
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,18)
	local st = Instance.new("UIStroke"); st.Color = STROKE; st.Thickness = 2; st.Transparency = 0.3; st.Parent = f
	local pd = Instance.new("UIPadding"); pd.PaddingTop=UDim.new(0,12); pd.PaddingBottom=UDim.new(0,12); pd.PaddingLeft=UDim.new(0,14); pd.PaddingRight=UDim.new(0,14); pd.Parent = f
	local l = Instance.new("TextLabel"); l.Size = footer and UDim2.fromScale(1,0.78) or UDim2.fromScale(1,1); l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne; l.Text = text; l.TextColor3 = TEXTC; l.TextScaled = true; l.TextWrapped = true; l.Parent = f
	Instance.new("UITextSizeConstraint", l).MaxTextSize = 22
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1,0.2); h.Position = UDim2.fromScale(0,0.8); h.BackgroundTransparency = 1
		h.Font = Enum.Font.FredokaOne; h.Text = footer; h.TextColor3 = HINTC; h.TextScaled = true; h.Parent = f
		Instance.new("UITextSizeConstraint", h).MaxTextSize = 14
	end
	bb.Parent = a
	if not persist then task.delay(9, function() if bb and bb.Parent == a and bb.Name == "SpeechBubble" then bb:Destroy() end end) end
end

local objGui = Instance.new("ScreenGui"); objGui.Name = "CrystalQuestObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7; objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame"); objFrame.AnchorPoint = Vector2.new(0.5,0); objFrame.Position = UDim2.new(0.5,0,0,12); objFrame.Size = UDim2.new(0,520,0,52)
objFrame.BackgroundColor3 = FILL; objFrame.Visible = false; objFrame.Parent = objGui
Instance.new("UICorner", objFrame).CornerRadius = UDim.new(0,16)
do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 3; s.Parent = objFrame end
local objLabel = Instance.new("TextLabel"); objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1,1); objLabel.Font = Enum.Font.FredokaOne
objLabel.TextColor3 = TEXTC; objLabel.TextScaled = true; objLabel.Parent = objFrame
do local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = objLabel
   local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,14); pad.PaddingRight = UDim.new(0,14); pad.Parent = objLabel end

local function baseText()
	if done then return "\xE2\x9B\x8F All crystals mined -- nice work!" end
	if not accepted then return "\xF0\x9F\x92\xAC Go talk to the Candy NPC!" end
	return ("\xE2\x9B\x8F Equip your Pickaxe & mine the crystals:  %d/%d"):format(mined, math.max(total, mined))
end
local flashTok = 0
local function refreshBanner() objLabel.Text = baseText() end
local function flashBanner(text, secs)
	flashTok += 1; local t = flashTok; objLabel.Text = text
	task.delay(secs or 2.5, function() if t == flashTok then refreshBanner() end end)
end
task.spawn(function()
	while true do
		local vis = false
		if done then vis = false
		elseif accepted then vis = true
		elseif npcHead and npcHead.Parent then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			vis = hrp ~= nil and (hrp.Position - npcHead.Position).Magnitude <= BANNER_RANGE
		end
		objFrame.Visible = vis
		task.wait(0.4)
	end
end)

-- ============================================================================
-- FX  (spark burst + white hit flash, like the Mars task -- built-in textures only)
-- ============================================================================
local function sparkBurst(part, count, color)
	local att = Instance.new("Attachment"); att.Parent = part
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color or PINK, GOLD)
	pe.Size = NumberSequence.new(0.7, 0.1); pe.Lifetime = NumberRange.new(0.25, 0.55)
	pe.Speed = NumberRange.new(6, 14); pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -26, 0); pe.Rate = 0; pe.Enabled = false; pe.Parent = att
	pe:Emit(count); Debris:AddItem(att, 1)
end
local function hitFlash(part)
	local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(255,255,255); hl.FillTransparency = 0.45
	hl.OutlineColor = GOLD; hl.OutlineTransparency = 0; hl.Adornee = part; hl.Parent = part
	Debris:AddItem(hl, 0.1)
end

-- resize `part` to size*scale about its centre, then re-plant its bottom (raise by half the
-- height lost) so the base stays on the ground as it shrinks.
local function resizePlanted(part, baseSize, scale)
	local oldY = part.Size.Y
	part.Size = baseSize * scale
	part.CFrame = part.CFrame + Vector3.new(0, (part.Size.Y - oldY) / 2, 0)
end
local function minScaleFor(h) return math.max(MIN_VISIBLE_SCALE, MIN_VISIBLE_STUDS / math.max(h, 0.1)) end

-- ============================================================================
-- FIREWORK + WIN BANNER
-- ============================================================================
local FW = { Color3.fromRGB(255,92,138), Color3.fromRGB(120,200,255), Color3.fromRGB(150,235,130), Color3.fromRGB(255,205,90), Color3.fromRGB(190,130,255) }
local function mkNeon(props)
	local p = Instance.new("Part"); p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false; p.Material = Enum.Material.Neon
	for k,v in pairs(props) do p[k] = v end; return p
end
local function burst(at, color)
	for i = 1, 24 do
		local s = mkNeon({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.5,0.5,0.5), Color = color })
		s.CFrame = CFrame.new(at); s.Parent = Workspace
		local dest = at + Vector3.new((i % 7) - 3, (i % 5), ((i * 3) % 7) - 3).Unit * 13
		TweenService:Create(s, TweenInfo.new(0.9), { CFrame = CFrame.new(dest), Transparency = 1, Size = Vector3.new(0.1,0.1,0.1) }):Play()
		Debris:AddItem(s, 1)
	end
end
local function fireworks(from)
	for i = 1, 3 do
		task.delay(i * 0.35, function()
			local r = mkNeon({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.6,0.6,0.6), Color = Color3.fromRGB(255,240,200) })
			local start = from + Vector3.new((i - 2) * 6, 3, 0); r.CFrame = CFrame.new(start); r.Parent = Workspace
			local up = TweenService:Create(r, TweenInfo.new(0.9), { CFrame = CFrame.new(start + Vector3.new(0, 45 + i * 6, 0)) })
			up.Completed:Connect(function() burst(r.Position, FW[((i - 1) % #FW) + 1]); r:Destroy() end); up:Play()
		end)
	end
end
local function winBanner()
	local g = Instance.new("ScreenGui"); g.Name = "CrystalWin"; g.ResetOnSpawn = false; g.DisplayOrder = 20; g.IgnoreGuiInset = true; g.Parent = PlayerGui
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5,0.5); f.Position = UDim2.new(0.5,0,0.42,0); f.Size = UDim2.new(0,0,0,90); f.BackgroundColor3 = FILL; f.Parent = g
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,18)
	do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 4; s.Parent = f end
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Size = UDim2.fromScale(1,1); l.Font = Enum.Font.FredokaOne; l.TextColor3 = TEXTC; l.TextScaled = true
	l.Text = "\xE2\x9B\x8F Crystals mined!"; l.Parent = f
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,24); pad.PaddingRight = UDim.new(0,24); pad.Parent = l
	Instance.new("UITextSizeConstraint", l).MaxTextSize = 32
	TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0,560,0,90) }):Play()
	task.delay(5, function() TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play(); TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play(); task.delay(0.5, function() g:Destroy() end) end)
end
-- CINEMATIC FINISH: pull the camera back onto the mine, thump it, then the fireworks.
local function cinematicFinish(at)
	local cam = workspace.CurrentCamera
	if not cam then fireworks(at); winBanner(); return end

	local charPos = (player.Character and player.Character:GetPivot().Position) or (at + Vector3.new(0, 12, 40))
	local away = (charPos - at) * Vector3.new(1, 0, 1)
	away = (away.Magnitude > 1) and away.Unit or Vector3.new(0, 0, 1)
	local camCF = CFrame.lookAt(at + away * 34 + Vector3.new(0, 16, 0), at)

	local hum = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	cam.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(cam, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = camCF }):Play()

	task.delay(1.05, function()
		-- shockwave rings off the mine floor
		for i, col in ipairs({ PINK, GOLD }) do
			task.delay((i - 1) * 0.12, function()
				local ring = Instance.new("Part")
				ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CastShadow = false
				ring.Shape = Enum.PartType.Cylinder; ring.Size = Vector3.new(0.7, 6, 6)
				ring.Color = col; ring.Material = Enum.Material.Neon; ring.Transparency = 0.1
				ring.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))
				ring.Parent = workspace
				TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{ Size = Vector3.new(0.7, 90, 90), Transparency = 1 }):Play()
				Debris:AddItem(ring, 1.1)
			end)
		end
		-- 0.6s of decaying shake
		local t0, SHAKE = os.clock(), 0.6
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local left = SHAKE - (os.clock() - t0)
			if left <= 0 or cam.CameraType ~= Enum.CameraType.Scriptable then
				conn:Disconnect()
				if cam.CameraType == Enum.CameraType.Scriptable then cam.CFrame = camCF end
				return
			end
			local m = (left / SHAKE) ^ 2 * 2.6
			cam.CFrame = camCF * CFrame.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
		end)
	end)

	task.delay(1.5, function() fireworks(at) end)
	task.delay(1.7, winBanner)
	task.delay(4.4, function()
		cam.CameraType = Enum.CameraType.Custom
		if hum then cam.CameraSubject = hum end
	end)
end

local function winQuest()
	if done then return end
	done = true
	_G.crystalQuestComplete = true
	refreshBanner()
	local at = (islandRef or (player.Character and player.Character:GetPivot().Position)) + Vector3.new(0, 8, 0)
	cinematicFinish(at)
	if _G.NotifyCenter then pcall(function() _G.NotifyCenter.push({ text = "\xE2\x9B\x8F All crystals mined!", color = STROKE }) end) end
	task.delay(6, function() objFrame.Visible = false end)
	print("[CrystalMine] complete -- all crystals mined")
end

-- ============================================================================
-- CRYSTALS -- register each, shrink on hit, shatter on the final hit
-- ============================================================================
-- a subtle sparkle that twinkles around the crystal (a few at a time -- not a cloud)
local function decorateCrystal(part)
	part.Reflectance = math.max(part.Reflectance, 0.12) -- slight gem sheen
	local att = Instance.new("Attachment"); att.Name = "CrystalSparkle"; att.Parent = part
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 240, 255), GOLD)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.3, 0.4), NumberSequenceKeypoint.new(1, 0.02) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(0.7, 1.3)
	pe.Speed = NumberRange.new(0.4, 1.4)
	pe.Rotation = NumberRange.new(0, 360)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, 1.2, 0)
	pe.LightEmission = 0.7
	pe.Rate = 4 -- subtle: only a few twinkles floating at once
	pe.Parent = att
	return pe
end
local shimmerPhase = 0
local function registerCrystal(inst)
	local part = inst:IsA("BasePart") and inst or (inst.PrimaryPart or largestBasePart(inst))
	-- PrimaryPart could itself be the vent; fall back to the largest non-vent part
	if part and isVentName(part.Name) and inst:IsA("Model") then part = largestBasePart(inst) end
	if not part or isVentName(part.Name) then return end
	if crystals[part] then return end
	part.Anchored = true -- crystals never fall (also lets the mining shrink stay put)
	shimmerPhase += 1.7
	local startHits = pickaxeUpgraded and UPGRADED_HITS or HITS_PER_CRYSTAL
	crystals[part] = { hits = startHits, maxHits = startHits, size = part.Size, cframe = part.CFrame, phase = shimmerPhase, pe = decorateCrystal(part) }
	total += 1
	refreshBanner()
end
local function scanCrystals()
	-- scan ALL of Workspace by name (don't depend on finding an 'island8' model)
	for _, d in ipairs(Workspace:GetDescendants()) do
		if isCrystalName(d.Name) and (d:IsA("BasePart") or d:IsA("Model")) then registerCrystal(d) end
	end
end
local function crystalsCentroid()
	local sum, n = Vector3.zero, 0
	for part in pairs(crystals) do if part.Parent then sum += part.Position; n += 1 end end
	if n == 0 then return nil end
	return sum / n
end

-- gentle shimmer: sweep each crystal's reflectance a little so it glints (cheap, ~12 fps)
task.spawn(function()
	while true do
		local now = os.clock()
		for part, rec in pairs(crystals) do
			if part.Parent and rec.hits > 0 and part.Transparency < 1 then
				part.Reflectance = 0.16 + 0.13 * (0.5 + 0.5 * math.sin(now * 2 + rec.phase))
			end
		end
		task.wait(0.08)
	end
end)

-- ---------------------------------------------------------------------------
-- DAMAGE CRACKS -- each hit scars the crystal so you can SEE how close it is to
-- going. Offsets are stored as fractions of the crystal's size, so the cracks
-- stay stuck to the surface as it shrinks.
-- ---------------------------------------------------------------------------
local function addCrack(part, rec)
	rec.cracks = rec.cracks or {}
	-- pick a face and a spot on it
	local f = Vector3.new((math.random() - 0.5) * 0.9, (math.random() - 0.5) * 0.8, 0.5)
	if math.random() < 0.5 then f = Vector3.new(0.5, f.Y, (math.random() - 0.5) * 0.9) end

	local crack = Instance.new("Part")
	crack.Anchored = true; crack.CanCollide = false; crack.CanQuery = false; crack.CastShadow = false
	crack.Size = Vector3.new(0.12, 0.7 + math.random() * 0.9, 0.12)
	crack.Color = Color3.fromRGB(58, 24, 44)
	crack.Material = Enum.Material.SmoothPlastic
	crack.Parent = workspace

	local rec2 = { part = crack, frac = f, tilt = CFrame.Angles(0, 0, (math.random() - 0.5) * 2.2) }
	rec.cracks[#rec.cracks + 1] = rec2
	return rec2
end

-- re-seat every crack against the crystal's CURRENT size
local function reseatCracks(part, rec)
	if not rec.cracks then return end
	local s = part.Size
	for _, c in ipairs(rec.cracks) do
		if c.part.Parent then
			c.part.CFrame = part.CFrame
				* CFrame.new(c.frac.X * s.X, c.frac.Y * s.Y, c.frac.Z * s.Z)
				* c.tilt
		end
	end
end

local function clearCracks(rec)
	if not rec.cracks then return end
	for _, c in ipairs(rec.cracks) do
		if c.part.Parent then Debris:AddItem(c.part, 0) end
	end
	rec.cracks = nil
end

-- ---------------------------------------------------------------------------
-- On shatter, shards spiral up and streak into you -- it reads as collecting
-- something rather than just deleting the crystal.
-- ---------------------------------------------------------------------------
local function shardsToPlayer(fromPart)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local origin = fromPart.Position
	for i = 1, 6 do
		local sh = Instance.new("Part")
		sh.Anchored = true; sh.CanCollide = false; sh.CanQuery = false; sh.CastShadow = false
		sh.Size = Vector3.new(0.5, 0.9, 0.5)
		sh.Color = (i % 2 == 0) and PINK or GOLD
		sh.Material = Enum.Material.Neon
		sh.CFrame = CFrame.new(origin) * CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3)
		sh.Parent = workspace

		-- pop up and out first...
		local a = (i / 6) * math.pi * 2
		local apex = origin + Vector3.new(math.cos(a) * 3.5, 4.5 + math.random() * 2, math.sin(a) * 3.5)
		local up = TweenService:Create(sh, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(apex) * CFrame.Angles(math.random() * 3, math.random() * 3, 0) })
		up.Completed:Connect(function()
			-- ...then home in on you
			local target = (hrp and hrp.Parent) and hrp.Position or (apex - Vector3.new(0, 6, 0))
			local inTw = TweenService:Create(sh, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = CFrame.new(target), Size = Vector3.new(0.15, 0.15, 0.15), Transparency = 1 })
			inTw:Play()
			Debris:AddItem(sh, 0.5)
		end)
		up:Play()
	end
end

local function mineHit(part)
	local rec = crystals[part]
	if not rec or rec.hits <= 0 or done then return end
	rec.hits -= 1
	if rec.hits > 0 then
		-- shrink proportionally to THIS crystal's own hit count, so an upgraded pickaxe
		-- still chips it down smoothly rather than jumping
		local maxHits = rec.maxHits or HITS_PER_CRYSTAL
		local taken = maxHits - rec.hits
		local floor = minScaleFor(rec.size.Y)
		local frac  = (maxHits > 1) and (taken / (maxHits - 1)) or 1
		local scale = math.clamp(1.0 - frac * (1.0 - floor), floor, 1.0)
		resizePlanted(part, rec.size, scale)
		addCrack(part, rec)          -- a new scar every swing...
		reseatCracks(part, rec)      -- ...and keep them all on the shrinking surface
		hitFlash(part); sparkBurst(part, 10, PINK)
	else
		sparkBurst(part, 28, GOLD)
		shardsToPlayer(part)   -- the crystal comes to you
		clearCracks(rec)
		part.Transparency = 1; part.CanCollide = false; part.CanQuery = false
		if rec.pe then rec.pe.Enabled = false; Debris:AddItem(rec.pe.Parent, 1.5) end -- stop the shimmer sparkle
		mined += 1
		if killVentsFor then killVentsFor(part) end   -- its geyser stops for good
		flashBanner(("\xE2\x9B\x8F Crystal mined!  %d/%d"):format(mined, total))
		refreshBanner()
		if _G.NotifyCenter then pcall(function() _G.NotifyCenter.push({ text = ("\xE2\x9B\x8F Crystal mined (%d/%d)"):format(mined, total), color = STROKE }) end) end
		if upgradePickaxe and mined == UPGRADE_AFTER and mined < total then upgradePickaxe() end
		if mined >= total and total > 0 then winQuest() end
	end
end

-- nearest mineable crystal in front of the player, within range
local function nearestCrystal()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local origin = hrp.Position
	local look = hrp.CFrame.LookVector; look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 1e-3 then return nil end
	look = look.Unit
	local best, bestD
	for part, rec in pairs(crystals) do
		if part.Parent and rec.hits > 0 and part.Transparency < 1 then
			local delta = part.Position - origin
			local dist = delta.Magnitude
			if dist <= MINE_RANGE then
				local flat = Vector3.new(delta.X, 0, delta.Z)
				if flat.Magnitude > 1e-3 and look:Dot(flat.Unit) >= FACING_DOT and (not bestD or dist < bestD) then
					best, bestD = part, dist
				end
			end
		end
	end
	return best
end

-- the right-shoulder Motor6D (R6 "Right Shoulder" or R15 "RightShoulder") so we can swing the arm
local function getRightShoulder(char)
	local torso = char:FindFirstChild("Torso")
	if torso then local m = torso:FindFirstChild("Right Shoulder"); if m and m:IsA("Motor6D") then return m end end
	local rua = char:FindFirstChild("RightUpperArm")
	if rua then local m = rua:FindFirstChild("RightShoulder"); if m and m:IsA("Motor6D") then return m end end
	return nil
end

-- ============================================================================
-- YOUR PICKAXE FROM THE WORLD. A part or model named "Pickaxe" placed on one of
-- the Studio models is cloned onto the Tool in place of the code-built head --
-- the same model the Tunnel Blast mine holds. The original stays put as set
-- dressing. Cached by a poller because it may STREAM IN late; if the tool is
-- granted before it arrives, the code-built pickaxe is the fallback.
-- ============================================================================
local worldPickaxe = nil
task.spawn(function()
	for _ = 1, 60 do          -- ~3 minutes of looking, then give up quietly
		for _, d in ipairs(Workspace:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("Model")) and loose(d.Name) == "pickaxe"
				and not d:FindFirstAncestorOfClass("Tool") then
				local inChar = false
				for _, pl in ipairs(Players:GetPlayers()) do
					if pl.Character and d:IsDescendantOf(pl.Character) then inChar = true; break end
				end
				if not inChar and (d:IsA("BasePart") or d:FindFirstChildWhichIsA("BasePart", true)) then
					worldPickaxe = d
					print("[CrystalMine] world 'Pickaxe' found: " .. d:GetFullName())
					return
				end
			end
		end
		task.wait(3)
	end
end)

-- longest axis = the shaft; the head is whichever end carries most of the part
-- volume (the island-14 axe's trick). Returns a world frame at the hand's grip
-- point with -Z running up the shaft toward the head, plus the shaft length.
local function pickaxeGrip(model)
	local bcf, bsz
	if model:IsA("BasePart") then bcf, bsz = model.CFrame, model.Size
	else bcf, bsz = model:GetBoundingBox() end
	local axes = { { Vector3.new(1, 0, 0), bsz.X }, { Vector3.new(0, 1, 0), bsz.Y },
	               { Vector3.new(0, 0, 1), bsz.Z } }
	table.sort(axes, function(a, b) return a[2] > b[2] end)
	local ax, len = axes[1][1], axes[1][2]
	local sum, tot = 0, 0
	for _, d in ipairs(model:IsA("BasePart") and { model } or model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = math.max(0.001, d.Size.X * d.Size.Y * d.Size.Z)
			sum += bcf:PointToObjectSpace(d.Position):Dot(ax) * v
			tot += v
		end
	end
	local headSide = ((tot > 0 and sum / tot or 0) >= 0) and 1 or -1
	local gripPos = (bcf * CFrame.new(ax * (-headSide * len * 0.12))).Position
	local headDir = (bcf - bcf.Position) * (ax * headSide)
	if headDir.Magnitude < 0.01 then headDir = Vector3.new(0, 1, 0) end
	return CFrame.lookAt(gripPos, gripPos + headDir), len
end

-- clone the world pickaxe onto the tool: scaled to hand size, every part welded
-- to the Handle so the existing Grip/swing animation drives it unchanged
local function skinToolWithWorldPickaxe(tool, handle)
	local src = worldPickaxe
	if not (src and src.Parent) then return false end
	local wasArch = src.Archivable
	src.Archivable = true
	local c = src:Clone()
	src.Archivable = wasArch
	if not c then return false end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			d:Destroy()
		end
	end
	local wrap = c
	if c:IsA("BasePart") then
		wrap = Instance.new("Model"); c.Parent = wrap; wrap.PrimaryPart = c
	end
	local _, len = pickaxeGrip(wrap)
	local s = math.clamp(3.2 / math.max(len, 0.5), 0.05, 20)
	if math.abs(s - 1) > 0.1 then pcall(function() wrap:ScaleTo(s) end) end
	local gripCF = pickaxeGrip(wrap)
	local R = CFrame.Angles(math.rad(90), 0, 0)   -- grip's -Z (up the shaft) -> Handle's +Y
	for _, d in ipairs(wrap:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false; d.CanCollide = false; d.CanQuery = false; d.Massless = true
			d:SetAttribute("WorldSkin", true)
			local C0 = R * gripCF:ToObjectSpace(d.CFrame)
			d.Parent = tool
			local w = Instance.new("Weld"); w.Part0 = handle; w.Part1 = d; w.C0 = C0; w.Parent = d
		end
	end
	wrap:Destroy()
	tool:SetAttribute("WorldSkin", true)
	print("[CrystalMine] tool skinned with your world 'Pickaxe' -- code-built head skipped")
	return true
end

-- ============================================================================
-- PICKAXE  (built in code; swing animates the Grip + the arm + mines the crystal)
-- ============================================================================
local function buildPickaxe()
	local tool = Instance.new("Tool")
	tool.Name = "Pickaxe"; tool.RequiresHandle = true; tool.CanBeDropped = false; tool.ToolTip = "Mine the candy crystals!"
	local WOOD  = Color3.fromRGB(120, 78, 46)
	local STEEL = Color3.fromRGB(122, 126, 138)

	-- wooden shaft (the Handle) -- smaller
	local handle = Instance.new("Part"); handle.Name = "Handle"; handle.Size = Vector3.new(0.26, 2.8, 0.26)
	handle.Color = WOOD; handle.Material = Enum.Material.Wood; handle.CanCollide = false; handle.Parent = tool

	local function weldPart(size, color, material, c0, shape)
		local p = Instance.new("Part"); p.Size = size; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic; p.CanCollide = false
		if shape then p.Shape = shape end
		p.Parent = tool
		local w = Instance.new("Weld"); w.Part0 = handle; w.Part1 = p; w.C0 = c0; w.Parent = p
		return p
	end
	-- YOUR pickaxe if the world provides one; the code-built head only otherwise
	if skinToolWithWorldPickaxe(tool, handle) then
		handle.Transparency = 1     -- the model IS the pickaxe; the shaft stays as the grip bone
	else
		-- compact steel head near the top: eye, cross bar, a pointed pick tip + a flat adze
		weldPart(Vector3.new(0.4, 0.4, 0.38),   STEEL, Enum.Material.Metal, CFrame.new(0, 1.28, 0)).Reflectance = 0.12       -- eye
		weldPart(Vector3.new(1.5, 0.3, 0.36),   STEEL, Enum.Material.Metal, CFrame.new(0, 1.28, 0)).Reflectance = 0.12       -- cross bar
		weldPart(Vector3.new(0.46, 0.32, 0.4),  STEEL, Enum.Material.Metal, CFrame.new(-0.95, 1.28, 0)).Reflectance = 0.12   -- flat adze (-X)
		weldPart(Vector3.new(0.58, 0.34, 0.34), STEEL, Enum.Material.Metal, CFrame.new(0.9, 1.24, 0) * CFrame.Angles(0,0,math.rad(20))).Reflectance = 0.12 -- pick shoulder (+X)
		weldPart(Vector3.new(0.4, 0.3, 0.34),   STEEL, Enum.Material.Metal, CFrame.new(1.32, 1.1, 0) * CFrame.Angles(0,0,math.rad(90)), Enum.PartType.Wedge).Reflectance = 0.15 -- pointed pick tip
		-- candy touches: gold collar + pink grip wrap + gold pommel
		weldPart(Vector3.new(0.3, 0.34, 0.3), GOLD, Enum.Material.Metal, CFrame.new(0, 1.02, 0))
		weldPart(Vector3.new(0.3, 0.75, 0.3), Color3.fromRGB(210, 70, 120), Enum.Material.SmoothPlastic, CFrame.new(0, -0.85, 0)) -- grip wrap
		weldPart(Vector3.new(0.3, 0.2, 0.3),  GOLD, Enum.Material.Metal, CFrame.new(0, -1.32, 0))                                -- pommel cap
	end

	-- rest pose (held ready). Extra 90° clockwise roll on top of the 180° flip. Tweak if odd.
	local rest = CFrame.new(0, -0.35, 0) * CFrame.Angles(math.rad(-12), math.rad(180), 0) * CFrame.Angles(0, 0, math.rad(-90))
	tool.Grip = rest
	local windup = rest * CFrame.Angles(math.rad(-78), 0, math.rad(8))   -- raise
	local strike = rest * CFrame.Angles(math.rad(72), 0, math.rad(-6))   -- chop

	-- ---- natural swing: ease in/out through wind-up -> fast chop -> rebound -> settle ----
	local function ease(a, kind)
		a = math.clamp(a, 0, 1)
		if kind == "in" then return a*a*a
		elseif kind == "out" then return 1 - (1-a)^3
		else return a*a*(3 - 2*a) end
	end
	local function animGrip(fromCF, toCF, dur, kind)
		local t = 0
		while t < dur do t += task.wait(); tool.Grip = fromCF:Lerp(toCF, ease(t/dur, kind)) end
		tool.Grip = toCF
	end

	-- capture the right-shoulder joint + its default pose when the pickaxe is equipped
	local shoulderJoint, shoulderDefault
	tool.Equipped:Connect(function()
		local char = tool.Parent
		shoulderJoint = char and getRightShoulder(char)
		shoulderDefault = shoulderJoint and shoulderJoint.C0
	end)

	-- lerp the Grip AND the arm together over `dur`
	local function step(gFrom, gTo, aFrom, aTo, dur, kind)
		local t = 0
		while t < dur do
			t += task.wait(); local a = ease(t / dur, kind)
			tool.Grip = gFrom:Lerp(gTo, a)
			if shoulderJoint and shoulderJoint.Parent and aFrom and aTo then shoulderJoint.C0 = aFrom:Lerp(aTo, a) end
		end
		tool.Grip = gTo
		if shoulderJoint and shoulderJoint.Parent and aTo then shoulderJoint.C0 = aTo end
	end

	local swinging, lastFire = false, -math.huge
	local function swing()
		if swinging then return end

		-- You can't mine through poison sugar gas. Either you're still fogged from a
		-- lungful, or the crystal you're aiming at is inside a cloud that's blowing.
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local target = nearestCrystal()
		if isGassed() or (hrp and inActiveGas(hrp.Position))
			or (target and inActiveGas(target.Position)) then
			flashBanner("\xE2\x98\xA0 POISON SUGAR GAS -- you can't mine through that!", 2.5)
			if not isGassed() then gasScreen() end
			return
		end

		swinging = true
		local now = os.clock()
		local crystal = ((now - lastFire) >= HIT_COOLDOWN) and target or nil
		-- arm poses relative to its default: raise overhead (wind-up) -> chop down (strike)
		local base    = shoulderDefault
		local armUp   = base and base * CFrame.Angles(math.rad(-150), 0, math.rad(-12))
		local armDown = base and base * CFrame.Angles(math.rad(-35), 0, math.rad(6))
		task.spawn(function()
			step(rest, windup, base, armUp, 0.17, "out")      -- wind up: raise the arm overhead
			step(windup, strike, armUp, armDown, 0.08, "in")  -- chop down fast (arm drives it)
			if crystal and crystal.Parent then lastFire = os.clock(); mineHit(crystal) end -- impact at the bottom
			local rebound = strike * CFrame.Angles(math.rad(10), 0, 0)
			step(strike, rebound, armDown, armDown, 0.05, "out") -- small bounce off the crystal
			step(rebound, rest, armDown, base, 0.24, "inout")    -- settle arm + tool back to ready
			if shoulderJoint and shoulderJoint.Parent and base then shoulderJoint.C0 = base end
			tool.Grip = rest; swinging = false
		end)
	end
	tool.Activated:Connect(swing)
	tool.Unequipped:Connect(function()
		tool.Grip = rest; swinging = false
		if shoulderJoint and shoulderJoint.Parent and shoulderDefault then shoulderJoint.C0 = shoulderDefault end -- un-pose the arm
	end)
	return tool
end

-- ---------------------------------------------------------------------------
-- MINER'S HELMET -- hard hat with a working headlamp, welded to your head so it
-- turns as you look. Comes with the pickaxe; re-applied on respawn.
-- ---------------------------------------------------------------------------
local function giveHelmet()
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return end
	if char:FindFirstChild("MinerHelmet") then return end

	local holder = Instance.new("Model"); holder.Name = "MinerHelmet"; holder.Parent = char

	local function piece(name, size, offset, colour, material, shape)
		local p = Instance.new("Part")
		p.Name = name; p.Size = size; p.Color = colour
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide = false; p.CanQuery = false; p.Massless = true; p.Anchored = false
		if shape then p.Shape = shape end
		p.CFrame = head.CFrame * offset
		p.Parent = holder
		local w = Instance.new("WeldConstraint"); w.Part0 = head; w.Part1 = p; w.Parent = p
		return p
	end

	local HAT    = Color3.fromRGB(250, 190, 32)   -- safety yellow
	local HAT_D  = Color3.fromRGB(214, 152, 20)   -- shaded yellow for the crest/brim edge
	local RUBBER = Color3.fromRGB(46, 42, 38)
	local STEELC = Color3.fromRGB(150, 154, 164)

	-- shell: a squashed dome, a full brim ring, and a wider peak out front
	piece("Shell", Vector3.new(2.05, 1.55, 2.15), CFrame.new(0, 0.66, 0), HAT,
		Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	piece("Brim", Vector3.new(0.16, 2.62, 2.62), CFrame.new(0, 0.34, 0) * CFrame.Angles(0, 0, math.rad(90)),
		HAT_D, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	piece("Peak", Vector3.new(1.9, 0.16, 0.95), CFrame.new(0, 0.36, -1.05) * CFrame.Angles(math.rad(-7), 0, 0), HAT_D)

	-- the ridge every hard hat has, running front to back
	piece("Crest",  Vector3.new(0.3, 0.42, 2.0),  CFrame.new(0, 1.24, 0), HAT_D)
	piece("CrestF", Vector3.new(0.22, 0.3, 0.5),  CFrame.new(0, 1.06, -0.86), HAT_D)

	-- sweatband + side rivets + chin strap
	piece("Band", Vector3.new(2.1, 0.22, 2.2), CFrame.new(0, 0.4, 0), RUBBER,
		Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	piece("RivetL", Vector3.new(0.26, 0.26, 0.26), CFrame.new(-1.02, 0.6, 0), STEELC, Enum.Material.Metal, Enum.PartType.Ball)
	piece("RivetR", Vector3.new(0.26, 0.26, 0.26), CFrame.new( 1.02, 0.6, 0), STEELC, Enum.Material.Metal, Enum.PartType.Ball)
	piece("StrapL", Vector3.new(0.1, 0.85, 0.16), CFrame.new(-0.96, 0.02, 0.12), RUBBER)
	piece("StrapR", Vector3.new(0.1, 0.85, 0.16), CFrame.new( 0.96, 0.02, 0.12), RUBBER)

	-- LAMP: steel housing, chrome bezel, glowing lens, and a visible shaft of light
	piece("LampMount", Vector3.new(0.7, 0.5, 0.22), CFrame.new(0, 0.72, -0.92), RUBBER)
	piece("LampBody",  Vector3.new(0.34, 0.62, 0.62), CFrame.new(0, 0.74, -1.06) * CFrame.Angles(0, 0, math.rad(90)),
		STEELC, Enum.Material.Metal, Enum.PartType.Cylinder)
	piece("LampBezel", Vector3.new(0.12, 0.72, 0.72), CFrame.new(0, 0.74, -1.2) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(206, 210, 220), Enum.Material.Metal, Enum.PartType.Cylinder)

	local lens = piece("Lens", Vector3.new(0.1, 0.56, 0.56), CFrame.new(0, 0.74, -1.24) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(255, 248, 214), Enum.Material.Neon, Enum.PartType.Cylinder)

	-- a faint shaft of light hanging in the cave air. Kept short (12 studs) on purpose --
	-- a long one pokes through walls and looks worse than no beam at all.
	local shaft = piece("Beam", Vector3.new(12, 1.3, 1.3), CFrame.new(0, 0.74, -7.2) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(255, 246, 208), Enum.Material.Neon, Enum.PartType.Cylinder)
	shaft.Transparency = 0.93
	shaft.CastShadow = false

	local beam = Instance.new("SpotLight")
	beam.Color = Color3.fromRGB(255, 246, 214); beam.Brightness = 4
	beam.Range = 48; beam.Angle = 58; beam.Face = Enum.NormalId.Front
	beam.Shadows = true; beam.Parent = lens

	-- a soft pool of light right in front of you too, so the ground isn't pitch black
	local fill = Instance.new("PointLight")
	fill.Color = Color3.fromRGB(255, 244, 208); fill.Brightness = 1.2; fill.Range = 16
	fill.Parent = lens
end

local function grantPickaxe()
	if pickaxeGranted then return end
	local bp = player:FindFirstChildOfClass("Backpack")
	if not bp then return end
	giveHelmet()
	if bp:FindFirstChild("Pickaxe") or (player.Character and player.Character:FindFirstChild("Pickaxe")) then pickaxeGranted = true; return end
	buildPickaxe().Parent = bp
	pickaxeGranted = true
end
-- ---------------------------------------------------------------------------
-- HALFWAY UPGRADE: re-forge the pickaxe so the back half goes quicker. Bigger
-- glowing head, and every crystal from here needs UPGRADED_HITS instead of six.
-- ---------------------------------------------------------------------------
upgradePickaxe = function()
	if pickaxeUpgraded then return end
	pickaxeUpgraded = true

	-- everything still in the ground gets easier, scaled so part-mined crystals
	-- don't suddenly gain health
	for _, rec in pairs(crystals) do
		if rec.hits > 0 then
			local frac = rec.hits / (rec.maxHits or HITS_PER_CRYSTAL)
			rec.maxHits = UPGRADED_HITS
			rec.hits = math.max(1, math.ceil(frac * UPGRADED_HITS))
		end
	end

	-- beef up the head on whichever copy of the tool the player has. A tool
	-- skinned with the player's own world "Pickaxe" keeps ITS look -- it gets a
	-- golden glow instead of being recoloured neon and inflated part by part
	-- (which would shred a modelled pickaxe into gaps).
	local function reforge(tool)
		if not tool then return end
		if tool:GetAttribute("WorldSkin") then
			if not tool:FindFirstChild("ReforgeGlow") then
				local hl = Instance.new("Highlight")
				hl.Name = "ReforgeGlow"; hl.FillColor = Color3.fromRGB(255, 214, 120)
				hl.FillTransparency = 0.75; hl.OutlineColor = Color3.fromRGB(255, 226, 150)
				hl.OutlineTransparency = 0.2; hl.Adornee = tool; hl.Parent = tool
			end
		else
			for _, p in ipairs(tool:GetChildren()) do
				if p:IsA("BasePart") and p.Name ~= "Handle" then
					p.Color = Color3.fromRGB(214, 226, 246)
					p.Material = Enum.Material.Neon
					p.Reflectance = 0.25
					p.Size = p.Size * 1.25
				end
			end
		end
		tool.ToolTip = "Re-forged! Mines crystals faster."
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	reforge(bp and bp:FindFirstChild("Pickaxe"))
	reforge(player.Character and player.Character:FindFirstChild("Pickaxe"))

	flashBanner("\xE2\x9B\x8F Your pickaxe has been RE-FORGED -- it hits harder now!", 3.5)
	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({
			text = "\xE2\x9B\x8F Pickaxe re-forged! Crystals break faster now.", color = GOLD }) end)
	end
	print("[CrystalMine] pickaxe upgraded")
end

-- re-grant on respawn while the quest is active
player.CharacterAdded:Connect(function()
	task.wait(0.6)
	if accepted and not done then
		pickaxeGranted = false; grantPickaxe()   -- also re-fits the helmet on the new body
		if pickaxeUpgraded then
			local bp = player:FindFirstChildOfClass("Backpack")
			local t = bp and bp:FindFirstChild("Pickaxe")
			if t then
				for _, p in ipairs(t:GetChildren()) do
					if p:IsA("BasePart") and p.Name ~= "Handle" then
						p.Color = Color3.fromRGB(214, 226, 246); p.Material = Enum.Material.Neon; p.Size = p.Size * 1.25
					end
				end
			end
		end
	end
end)

-- ============================================================================
-- CAVE HAZARDS -- rockfalls and sugar-gas vents. They shove you and rattle the
-- screen; they never damage you. Only active while you're actually mining.
-- ============================================================================
-- Hazards are part of the CAVE, not the quest: they run the moment you set foot on the
-- island, whether or not you've talked to the NPC or already finished. Rockfalls never
-- stop; a gas vent only stops when its own crystal gets mined (see killVentsFor).
local HAZARD_RANGE = 420
local function nearMine()
	if not islandRef then return false end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	return (hrp.Position - islandRef).Magnitude <= HAZARD_RANGE
end

local function nudgeCamera(strength, seconds)
	local cam = workspace.CurrentCamera
	if not cam or cam.CameraType == Enum.CameraType.Scriptable then return end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < seconds do
			local left = seconds - (os.clock() - t0)
			local m = (left / seconds) ^ 2 * strength
			cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
			RunService.RenderStepped:Wait()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- ROCKFALL -- boulders drop from the parts you named "rock drop". Each boulder is
-- a cluster of irregular chunks so it reads as rock, not a cube, and it bursts
-- into shards + dust on impact.
-- ---------------------------------------------------------------------------
local rockDrops = {}

local ROCK_TONES = {
	Color3.fromRGB(176, 108, 152),
	Color3.fromRGB(152, 92, 134),
	Color3.fromRGB(198, 130, 172),
	Color3.fromRGB(134, 80, 120),
}

-- an irregular lump: a core with chunks jutting off it at odd angles + a few candy shards
local function buildBoulder(scale)
	local m = Instance.new("Model"); m.Name = "FallenRock"
	local s = scale or 1

	-- CanCollide stays false while it's in the air (an anchored solid moving through you
	-- shoves you around), and is switched on the moment it lands.
	local function chunk(size, cf, colour, material, shape)
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = true
		p.Size = size; p.Color = colour; p.Material = material or Enum.Material.Slate
		if shape then p.Shape = shape end
		p.CFrame = cf
		p.Parent = m
		return p
	end

	local core = chunk(Vector3.new(2.4 * s, 2.1 * s, 2.3 * s), CFrame.new(),
		ROCK_TONES[1], Enum.Material.Slate)
	m.PrimaryPart = core

	-- lumps around the core, each rotated randomly so no two silhouettes match
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2 + math.random() * 0.6
		local r = (0.7 + math.random() * 0.5) * s
		chunk(
			Vector3.new((0.9 + math.random() * 1.1) * s, (0.8 + math.random() * 1.0) * s, (0.9 + math.random() * 1.0) * s),
			CFrame.new(math.cos(a) * r, (math.random() - 0.5) * 1.3 * s, math.sin(a) * r)
				* CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3),
			ROCK_TONES[math.random(1, #ROCK_TONES)], Enum.Material.Slate)
	end

	-- a couple of candy crystals embedded in it, catching the light
	for i = 1, 2 do
		local a = math.random() * math.pi * 2
		chunk(Vector3.new(0.45 * s, 1.0 * s, 0.45 * s),
			CFrame.new(math.cos(a) * 1.0 * s, (math.random() - 0.3) * 1.2 * s, math.sin(a) * 1.0 * s)
				* CFrame.Angles(math.random() * 2, math.random() * 2, math.random() * 2),
			(i == 1) and PINK or GOLD, Enum.Material.Glass).Reflectance = 0.3
	end

	return m, core
end

-- where does a rock dropped from `fromPos` land?
local function floorUnder(fromPos)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local filter = {}
	if player.Character then filter[#filter + 1] = player.Character end
	rp.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(fromPos, Vector3.new(0, -260, 0), rp)
	return hit and hit.Position or (fromPos - Vector3.new(0, 40, 0))
end

local function rockfallFrom(dropPart)
	if not (dropPart and dropPart.Parent) then return end
	local start = dropPart.Position - Vector3.new(0, dropPart.Size.Y * 0.5, 0)
	local land  = floorUnder(start - Vector3.new(0, 1, 0))

	-- grit trickles out of the hole a moment before the boulder comes -- the tell is
	-- diegetic, so no UI marker is needed
	for i = 1, 8 do
		task.delay(i * 0.05, function()
			local g = Instance.new("Part")
			g.Anchored = true; g.CanCollide = false; g.CanQuery = false; g.CastShadow = false
			g.Size = Vector3.new(0.28, 0.28, 0.28); g.Color = ROCK_TONES[math.random(1, #ROCK_TONES)]
			g.Material = Enum.Material.Slate
			g.CFrame = CFrame.new(start + Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3))
			g.Parent = workspace
			TweenService:Create(g, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = CFrame.new(Vector3.new(g.Position.X, land.Y + 0.3, g.Position.Z)), Transparency = 1 }):Play()
			Debris:AddItem(g, 0.9)
		end)
	end

	task.delay(0.85, function()
		local boulder, core = buildBoulder(0.9 + math.random() * 0.5)
		boulder:PivotTo(CFrame.new(start))
		boulder.Parent = workspace

		-- tumble as it falls
		local spin = CFrame.Angles(math.random() * 4, math.random() * 4, math.random() * 4)
		local dist = math.max(6, start.Y - land.Y)
		local fallTime = math.clamp(dist / 90, 0.25, 0.8)

		local t0 = os.clock()
		local from = CFrame.new(start)
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local a = math.min(1, (os.clock() - t0) / fallTime)
			local eased = a * a                                  -- accelerate like gravity
			boulder:PivotTo(
				from:Lerp(CFrame.new(Vector3.new(start.X, land.Y + 1.2, start.Z)), eased)
				* CFrame.Angles(spin.X * eased, spin.Y * eased, spin.Z * eased))
			if a >= 1 then
				conn:Disconnect()

				-- IMPACT
				sparkBurst(core, 18, PINK)
				nudgeCamera(1.6, 0.4)

				-- it's a real rock now: solid, you can bump into it or climb it
				for _, p in ipairs(boulder:GetDescendants()) do
					if p:IsA("BasePart") then p.CanCollide = true end
				end

				-- shards fly out across the floor
				for i = 1, 9 do
					local ang = (i / 9) * math.pi * 2
					local sh = Instance.new("Part")
					sh.Anchored = true; sh.CanCollide = false; sh.CanQuery = false; sh.CastShadow = false
					sh.Size = Vector3.new(0.5 + math.random() * 0.5, 0.4, 0.5 + math.random() * 0.5)
					sh.Color = ROCK_TONES[math.random(1, #ROCK_TONES)]; sh.Material = Enum.Material.Slate
					sh.CFrame = CFrame.new(Vector3.new(start.X, land.Y + 0.8, start.Z))
					sh.Parent = workspace
					TweenService:Create(sh, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						CFrame = CFrame.new(Vector3.new(start.X + math.cos(ang) * (7 + math.random() * 4),
							land.Y + 0.3, start.Z + math.sin(ang) * (7 + math.random() * 4)))
							* CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3),
						Transparency = 1 }):Play()
					Debris:AddItem(sh, 0.9)
				end

				-- dust ring rolling outward
				for i = 1, 6 do
					local ang = (i / 6) * math.pi * 2
					local d = Instance.new("Part")
					d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CastShadow = false
					d.Shape = Enum.PartType.Ball; d.Size = Vector3.new(3, 3, 3)
					d.Color = Color3.fromRGB(214, 176, 202); d.Material = Enum.Material.SmoothPlastic
					d.Transparency = 0.45
					d.CFrame = CFrame.new(Vector3.new(start.X, land.Y + 0.8, start.Z))
					d.Parent = workspace
					TweenService:Create(d, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						CFrame = CFrame.new(Vector3.new(start.X + math.cos(ang) * 9, land.Y + 1.6, start.Z + math.sin(ang) * 9)),
						Transparency = 1, Size = Vector3.new(7, 7, 7) }):Play()
					Debris:AddItem(d, 1.2)
				end

				-- shove anyone standing underneath (never damages them)
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hrp and (hrp.Position - Vector3.new(start.X, land.Y, start.Z)).Magnitude < 9 then
					local push = (hrp.Position - Vector3.new(start.X, land.Y, start.Z)) * Vector3.new(1, 0, 1)
					push = (push.Magnitude > 0.1) and push.Unit or Vector3.new(1, 0, 0)
					hrp.AssemblyLinearVelocity = push * 38 + Vector3.new(0, 16, 0)
					flashBanner("\xE2\x9A\xA0 Rockfall! Watch the ceiling.", 2)
				end

				-- it sits there as a solid obstacle for a good few seconds, then crumbles.
				-- Collision is dropped as the crumble starts so nobody gets left standing
				-- on a rock that's fading out from under them.
				task.delay(ROCK_LINGER, function()
					for _, p in ipairs(boulder:GetDescendants()) do
						if p:IsA("BasePart") then
							p.CanCollide = false
							TweenService:Create(p, TweenInfo.new(0.7), { Transparency = 1, Size = p.Size * 0.3 }):Play()
						end
					end
					Debris:AddItem(boulder, 0.9)
				end)
			end
		end)
	end)
end

-- find the drop points and start each one cycling
wireRockDrops = function()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and string.find(loose(d.Name), ROCK_DROP_NAME, 1, true) then
			d.Transparency = 1; d.CanCollide = false; d.CanQuery = false   -- marker only
			rockDrops[#rockDrops + 1] = d
		end
	end
	if #rockDrops == 0 then
		warn("[CrystalMine] no parts named 'rock drop' found -- no rockfalls")
		return
	end
	print(("[CrystalMine] %d rock drop(s) wired"):format(#rockDrops))
	for i, dp in ipairs(rockDrops) do
		task.spawn(function()
			task.wait(4 + i * (ROCKFALL_EVERY / math.max(1, #rockDrops)))
			while true do
				if nearMine() then rockfallFrom(dp) end
				task.wait(ROCKFALL_EVERY)
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- POISON SUGAR GAS
-- ---------------------------------------------------------------------------
local Lighting = game:GetService("Lighting")
local vents    = {}          -- { part = , active = bool }
local gassedUntil = 0

isGassed = function() return os.clock() < gassedUntil end

-- fog the player's view: blur + a sickly green wash that fades out on its own
local blurFx, tintFx
gasScreen = function()
	gassedUntil = math.max(gassedUntil, os.clock() + GAS_BLUR_TIME)

	if not blurFx or not blurFx.Parent then
		blurFx = Instance.new("BlurEffect"); blurFx.Name = "SugarGasBlur"; blurFx.Size = 0; blurFx.Parent = Lighting
	end
	if not tintFx or not tintFx.Parent then
		tintFx = Instance.new("ColorCorrectionEffect"); tintFx.Name = "SugarGasTint"
		tintFx.TintColor = Color3.fromRGB(255, 255, 255); tintFx.Saturation = 0; tintFx.Parent = Lighting
	end

	-- snap in, hold FULLY fogged for the whole GAS_BLUR_TIME, and only then fade off
	TweenService:Create(blurFx, TweenInfo.new(0.35), { Size = 26 }):Play()
	TweenService:Create(tintFx, TweenInfo.new(0.35), {
		TintColor = Color3.fromRGB(176, 255, 206), Saturation = -0.4, Brightness = -0.06 }):Play()

	task.delay(GAS_BLUR_TIME, function()
		-- a fresh lungful since this one started? let the newer timer own the fade
		if os.clock() < gassedUntil - 0.05 then return end
		if blurFx then TweenService:Create(blurFx, TweenInfo.new(GAS_FADE_TIME), { Size = 0 }):Play() end
		if tintFx then TweenService:Create(tintFx, TweenInfo.new(GAS_FADE_TIME), {
			TintColor = Color3.fromRGB(255, 255, 255), Saturation = 0, Brightness = 0 }):Play() end
	end)
end

-- is this point inside any vent that's currently blowing? each vent's cloud is sized to
-- its own part, so a long vent block gasses a long strip rather than a fixed circle
inActiveGas = function(pos)
	for _, v in ipairs(vents) do
		if v.active and not v.dead and v.part and v.part.Parent then
			if (pos - v.part.Position).Magnitude <= (v.radius or VENT_MARGIN) then return true end
		end
	end
	return false
end

-- one eruption from a specific vent part
local function erupt(v)
	local part = v.part
	if not (part and part.Parent) then return end
	if v.dead then return end                                     -- its crystal is mined; capped
	if v.active then return end                                   -- already blowing
	if v.lastBlow and (os.clock() - v.lastBlow) < VENT_EVERY then return end  -- still on cooldown
	v.lastBlow = os.clock()
	v.active = true

	-- the gas comes off the WHOLE block: puffs are seeded right across its top face,
	-- in its own local space, so a rotated or long vent erupts along its full length
	local sx, sz = part.Size.X, part.Size.Z
	local topLocalY = part.Size.Y * 0.5

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(180, 255, 210); glow.Brightness = 3; glow.Range = v.radius or 24
	glow.Parent = part

	-- billowing cloud for as long as the vent is blowing
	task.spawn(function()
		local t0 = os.clock()
		-- more puffs on a bigger vent, so a long block doesn't look sparse
		local perTick = math.clamp(math.floor((sx + sz) / 6), 3, 12)
		-- stops early if the crystal feeding it gets mined mid-eruption
		while os.clock() - t0 < VENT_ACTIVE_TIME and part.Parent and not v.dead do
			for _ = 1, perTick do
				local puff = Instance.new("Part")
				puff.Anchored = true; puff.CanCollide = false; puff.CanQuery = false; puff.CastShadow = false
				puff.Shape = Enum.PartType.Ball
				puff.Size = Vector3.new(6, 6, 6)
				puff.Color = Color3.fromRGB(196, 255, 214); puff.Material = Enum.Material.Neon
				puff.Transparency = 0.45
				-- anywhere on the block's top surface
				puff.CFrame = part.CFrame * CFrame.new(
					(math.random() - 0.5) * sx,
					topLocalY,
					(math.random() - 0.5) * sz)
				puff.Parent = workspace
				TweenService:Create(puff, TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					CFrame = puff.CFrame + Vector3.new((math.random() - 0.5) * 16, 16, (math.random() - 0.5) * 16),
					Transparency = 1, Size = Vector3.new(22, 22, 22) }):Play()
				Debris:AddItem(puff, 2.2)
			end
			task.wait(0.22)
		end
		glow:Destroy()
		v.active = false
	end)

	-- the ground shudders while it's venting
	nudgeCamera(1.2, 0.5)

	-- anyone caught in the cloud gets fogged
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < VENT_ACTIVE_TIME and not v.dead do
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - part.Position).Magnitude <= (v.radius or VENT_MARGIN) then
				if not isGassed() then
					flashBanner("\xE2\x98\xA0 POISON SUGAR GAS! Back off until it clears.", 2.5)
					nudgeCamera(1.3, 0.4)
				end
				gasScreen()
			end
			task.wait(0.4)
		end
	end)
end

-- find the vent parts and start them cycling (staggered so they don't all blow together)
-- mining a crystal caps whichever vent(s) were feeding off it
killVentsFor = function(crystalPart)
	for _, v in ipairs(vents) do
		if v.crystal == crystalPart and not v.dead then
			v.dead = true
			v.active = false          -- any cloud in the air finishes and doesn't come back
			if v.part then
				for _, l in ipairs(v.part:GetChildren()) do
					if l:IsA("PointLight") then l:Destroy() end
				end
			end
			print(("[CrystalMine] vent '%s' capped -- its crystal was mined"):format(v.part and v.part.Name or "?"))
		end
	end
end

-- ---------------------------------------------------------------------------
-- WARNING SIGNS -- built on the parts you named "sign". Marker's CFrame sets the
-- position AND which way the sign faces, so aim it in Studio.
-- ---------------------------------------------------------------------------
local function buildWarningSigns()
	local made = 0
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and loose(d.Name) == "sign" then
			made += 1
			local base = CFrame.new(d.Position - Vector3.new(0, d.Size.Y * 0.5, 0)) * (d.CFrame - d.CFrame.Position)
			d.Transparency = 1; d.CanCollide = false; d.CanQuery = false   -- marker only

			local m = Instance.new("Model"); m.Name = "GasWarningSign"; m.Parent = workspace
			local function bit(name, size, cf, colour, material, shape)
				local p = Instance.new("Part")
				p.Name = name; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
				p.Size = size; p.Color = colour; p.Material = material or Enum.Material.SmoothPlastic
				if shape then p.Shape = shape end
				p.CFrame = base * cf; p.Parent = m
				return p
			end

			local YEL   = Color3.fromRGB(250, 202, 34)
			local BLK   = Color3.fromRGB(26, 24, 20)
			local STEEL = Color3.fromRGB(142, 146, 156)

			-- weighted foot, so it looks planted rather than stuck in the floor
			bit("Foot",  Vector3.new(2.0, 0.4, 1.4), CFrame.new(0, 0.2, 0), Color3.fromRGB(84, 84, 90), Enum.Material.Concrete)
			bit("FootCap", Vector3.new(1.5, 0.18, 1.0), CFrame.new(0, 0.46, 0), Color3.fromRGB(104, 104, 112), Enum.Material.Metal)
			-- SUPPORT POLE -- lives entirely behind the board.
			--   board front face sits at z ~= -0.07; the board leans 8 deg back, so its
			--   rear face never goes further back than z ~= +0.27. The pole is parked at
			--   z = +0.45 (still inside the foot's 1.4-deep footprint, so it reads as
			--   standing on the base) and so cannot cross the face at any height or angle.
			bit("Post",   Vector3.new(0.24, 5.4, 0.24), CFrame.new(0, 2.75, 0.45), STEEL, Enum.Material.Metal)
			bit("Collar", Vector3.new(0.4, 0.3, 0.4),   CFrame.new(0, 0.72, 0.45), STEEL, Enum.Material.Metal)

			-- the board, tilted back slightly like a real roadside sign. Everything behind
			-- it lives at +Z; the face is at -Z, so nothing structural crosses the front.
			local TILT = CFrame.Angles(math.rad(-8), 0, 0)
			-- two short arms bridging the pole to the BACK of the board. Their front edge
			-- stops at z = +0.12, still well behind the panel's rear face (z ~= +0.03).
			bit("BracketTop", Vector3.new(0.32, 0.32, 0.4), CFrame.new(0, 5.95, 0.32), STEEL, Enum.Material.Metal)
			bit("BracketLow", Vector3.new(0.32, 0.32, 0.4), CFrame.new(0, 4.65, 0.32), STEEL, Enum.Material.Metal)
			bit("Backing", Vector3.new(4.0, 3.0, 0.14), CFrame.new(0, 5.3, 0.06) * TILT, BLK, Enum.Material.Metal)
			local panel = bit("Panel", Vector3.new(3.7, 2.7, 0.1), CFrame.new(0, 5.3, -0.02) * TILT, YEL)

			-- hazard chevrons top and bottom
			bit("StripeT", Vector3.new(3.7, 0.34, 0.12), CFrame.new(0, 6.5, -0.04) * TILT, BLK)
			bit("StripeB", Vector3.new(3.7, 0.34, 0.12), CFrame.new(0, 4.1, -0.04) * TILT, BLK)
			-- corner bolts
			for _, o in ipairs({ Vector3.new(-1.65, 6.05, 0), Vector3.new(1.65, 6.05, 0),
			                     Vector3.new(-1.65, 4.55, 0), Vector3.new(1.65, 4.55, 0) }) do
				bit("Bolt", Vector3.new(0.16, 0.16, 0.16), CFrame.new(o.X, o.Y, -0.06) * TILT,
					Color3.fromRGB(198, 202, 210), Enum.Material.Metal, Enum.PartType.Ball)
			end

			-- a little hooded lamp over the board so it's readable in a dark mine
			bit("Hood", Vector3.new(1.1, 0.16, 0.5), CFrame.new(0, 6.95, -0.24), STEEL, Enum.Material.Metal)
			local bulb = bit("Bulb", Vector3.new(0.3, 0.16, 0.3), CFrame.new(0, 6.84, -0.24),
				Color3.fromRGB(255, 240, 190), Enum.Material.Neon)
			local lp = Instance.new("PointLight")
			lp.Color = Color3.fromRGB(255, 236, 180); lp.Brightness = 1.6; lp.Range = 12; lp.Parent = bulb

			-- the face itself
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(370, 270)
			sg.LightInfluence = 0.2; sg.Adornee = panel; sg.Parent = panel
			local skull = Instance.new("TextLabel")
			skull.BackgroundTransparency = 1; skull.Position = UDim2.new(0, 0, 0, 6)
			skull.Size = UDim2.new(1, 0, 0, 120); skull.Font = Enum.Font.FredokaOne
			skull.Text = "\xE2\x98\xA0"; skull.TextColor3 = BLK; skull.TextScaled = true; skull.Parent = sg
			local txt = Instance.new("TextLabel")
			txt.BackgroundTransparency = 1; txt.Position = UDim2.new(0, 8, 0, 126)
			txt.Size = UDim2.new(1, -16, 0, 130); txt.Font = Enum.Font.FredokaOne
			txt.Text = "POISON\nSUGAR GAS"; txt.TextColor3 = BLK; txt.TextScaled = true; txt.Parent = sg
		end
	end
	if made > 0 then print(("[CrystalMine] %d warning sign(s) built"):format(made))
	else warn("[CrystalMine] no parts named 'sign' found -- no warning signs") end
end

wireGasVents = function()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and isVentName(d.Name) then
			-- the block is only a marker for where the gas comes from: invisible, no
			-- collision, not clickable
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
			-- cloud reach = the block's own footprint plus a margin, so a long vent gasses
			-- a long strip instead of a fixed circle
			local half = math.max(d.Size.X, d.Size.Z) * 0.5
			vents[#vents + 1] = { part = d, active = false, radius = half + VENT_MARGIN }

			-- (warning signs are built separately, on the parts you named "sign")
		end
	end

	-- Link each vent to its crystal. The vents are modelled INSIDE the crystal models
	-- (crystal1..crystal4), so ancestry is exact -- no names or distances to guess at.
	for _, v in ipairs(vents) do
		-- 1) walk up to the crystal model this vent is built into
		local node = v.part.Parent
		while node and node ~= workspace do
			if node:IsA("Model") and isCrystalName(node.Name) then
				for part in pairs(crystals) do
					if part:IsDescendantOf(node) then v.crystal = part; v.owner = node; break end
				end
				if v.crystal then break end
			end
			node = node.Parent
		end

		-- 2) explicit override, if you ever list one
		if not v.crystal then
			local wanted = VENT_PAIRS[v.part.Name] or VENT_PAIRS[loose(v.part.Name)]
			if wanted then
				for part in pairs(crystals) do
					if loose(part.Name) == loose(wanted) then v.crystal = part; break end
				end
			end
		end

		-- 3) last resort: nearest crystal
		if not v.crystal then
			local best, bestD
			for part in pairs(crystals) do
				local dd = (part.Position - v.part.Position).Magnitude
				if not bestD or dd < bestD then best, bestD = part, dd end
			end
			v.crystal = best
		end

		if v.crystal then
			print(("[CrystalMine] vent '%s' -> crystal '%s'%s"):format(
				v.part.Name, v.crystal.Name, v.owner and (" (inside " .. v.owner.Name .. ")") or " (by distance)"))
		else
			warn(("[CrystalMine] vent '%s' has no crystal to pair with"):format(v.part.Name))
		end
	end
	if #vents == 0 then
		warn("[CrystalMine] no parts named 'gas vents' found -- no gas hazard")
		return
	end
	print(("[CrystalMine] %d gas vent(s) wired"):format(#vents))
	buildWarningSigns()
	for i, v in ipairs(vents) do
		task.spawn(function()
			task.wait(3 + i * (VENT_EVERY / math.max(1, #vents)))
			while true do
				if nearMine() then erupt(v) end
				task.wait(VENT_EVERY)
			end
		end)
	end
end

-- (rockfalls and gas vents are both started from the GO block, once the world's parts
--  have actually streamed in -- see wireRockDrops / wireGasVents)

-- ============================================================================
-- NPC DIALOGUE
-- ============================================================================
local function questPages()
	if done then return { "You cleared out every crystal -- sweet work! \xE2\x9B\x8F" } end
	if accepted then return { ("You've mined %d of %d crystals."):format(mined, total), "Equip your Pickaxe and swing at them!" } end
	return {
		"Our candy crystals need harvesting!",
		"Take this Pickaxe -- equip it and swing at each crystal to mine it.",
		"Mine them all and come back!",
	}
end
local function wireNPC(head)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = "Candy Npc"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = TALK_DISTANCE; prompt.RequiresLineOfSight = false; prompt.Parent = head
	local pages, index, watching = nil, 0, false
	local function close() hideBubble(head); prompt.ActionText = "Talk"; index = 0; pages = nil end
	local function watch()
		if watching then return end; watching = true
		task.spawn(function()
			while index ~= 0 do
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if not hrp or (hrp.Position - head.Position).Magnitude > TALK_DISTANCE then close(); break end
				task.wait(0.25)
			end
			watching = false
		end)
	end
	prompt.Triggered:Connect(function()
		if index == 0 then pages = questPages() end
		index += 1
		if not pages or index > #pages then close(); return end
		if index == 2 and not accepted then
			accepted = true; grantPickaxe(); refreshBanner()
			if crystals then for part in pairs(crystals) do pointTo(part.Position); break end end
		end
		local last = index >= #pages
		showBubble(head, pages[index], true, last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages))
		prompt.ActionText = last and "Close" or "Continue"
		watch()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then close() end end)
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	-- crystals stream in (StreamingEnabled) -- scan ALL of Workspace by name + catch late ones
	scanCrystals()
	task.spawn(function() local a = 0; while a < 40 do task.wait(1); scanCrystals(); a += 1 end end)
	Workspace.DescendantAdded:Connect(function(d) if isCrystalName(d.Name) and (d:IsA("BasePart") or d:IsA("Model")) then registerCrystal(d) end end)

	-- reference for the NPC + firework = the crystals' centre (fall back to an island8 model, else nil)
	islandRef = pollFor(function()
		local c = crystalsCentroid()
		if c then return c end
		local isle = findIsland8()
		if isle then
			local cf = isle:IsA("Model") and isle:GetBoundingBox() or (firstBasePart(isle) and firstBasePart(isle).CFrame)
			return cf and cf.Position or nil
		end
		return nil
	end, 30)

	npcHead = pollFor(function() return findNPCNear(islandRef) end, 45)
	if npcHead then wireNPC(npcHead); print("[CrystalMine] Candy Npc wired") else warn("[CrystalMine] no 'Candy Npc' found near the crystals") end

	refreshBanner()
	if HAZARDS_ON and wireGasVents then wireGasVents() end
	if HAZARDS_ON and wireRockDrops then wireRockDrops() end
	print(("[CrystalMine] ready -- %d crystal(s) found"):format(total))

	-- DIAGNOSTIC: if nothing matched, list objects whose name has 'crystal'/'island8' so the real name shows
	task.delay(6, function()
		if total == 0 then
			warn("[CrystalMine] 0 crystals found -- listing objects containing 'crystal' / 'island8' (so the actual name is visible):")
			local shown = 0
			for _, d in ipairs(Workspace:GetDescendants()) do
				local n = string.lower(d.Name)
				if (n:find("crystal", 1, true) or n:find("island8", 1, true) or n:find("island 8", 1, true)) and shown < 40 then
					shown += 1
					warn(("[CrystalMine]   '%s'  (%s)"):format(d:GetFullName(), d.ClassName))
				end
			end
			if shown == 0 then warn("[CrystalMine]   nothing with 'crystal' or 'island8' in its name exists in Workspace -- check the names in Studio") end
		end
	end)
end)

-- ============================================================================
-- /complete -- test command: instantly mine everything (near island8)
-- ============================================================================
local function onCommand(msg)
	if tostring(msg or ""):lower():sub(1, 9) ~= "/complete" then return end
	-- only completes when you're actually ON island8 (near its NPC / the mine), so /complete
	-- typed on another island never fires this quest's banner/win.
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local ref = (npcHead and npcHead.Parent and npcHead.Position) or islandRef
	if not (hrp and ref) then return end
	if (hrp.Position - ref).Magnitude > BANNER_RANGE then return end
	accepted = true
	for part, rec in pairs(crystals) do
		if rec.hits > 0 then rec.hits = 0; part.Transparency = 1; part.CanCollide = false; part.CanQuery = false; if rec.pe then rec.pe.Enabled = false end; mined += 1 end
	end
	if total == 0 then total = mined end
	winQuest()
	print("[CrystalMine][TEST] /complete -- all crystals mined")
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m) if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
