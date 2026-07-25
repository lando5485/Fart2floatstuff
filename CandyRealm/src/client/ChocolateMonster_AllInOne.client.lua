--======================================================================
-- ChocolateMonster_AllInOne.client.lua  (LocalScript)
--======================================================================
-- ISLAND-3: a GIANT CHOCOLATE MONSTER that hunts you.
--
-- A big built-in-code chocolate beast roams island3. Get near and it WAKES UP,
-- roars, and chases you down -- faster the longer it hunts. Catch you and it
-- shoves you back with a screen-shake scare (never kills). Shove it back (hold E
-- when close) to stun it and knock it away for a few seconds.
--
-- It ties into the Cookie quest: it's the thing that "stole the chocolate", and
-- every few good shoves it coughs up a chocolate chunk. Purely client-side and
-- scoped to island3, so it never wanders onto another island.
--======================================================================

local Players       = game:GetService("Players")
local Workspace     = game:GetService("Workspace")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")
local Debris        = game:GetService("Debris")
local SoundService  = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- server relay that hides a swallowed player from EVERYONE (fetched async so it
-- never blocks setup; if the server script is missing we just skip the hide).
-- The OnClientEvent hookup + trapped-bulge visuals live further down, once mk()
-- and monBody exist.
local eatRemote
local function setEatenHidden(b)
	if eatRemote then pcall(function() eatRemote:FireServer(b) end) end
end

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_NAME   = "island3"
local ISLAND_RANGE  = 700          -- how far from island3 the monster stays "at home"
local SPAWN_NAME    = "monsterspawn"  -- optional part to spawn it on

local AGGRO_RANGE   = 90           -- get this close and it wakes + hunts
local LEASH_RANGE   = 260          -- run this far and it gives up + strolls home
local CATCH_RANGE   = 6            -- this close = it grabs you (shove-back)
local SHOVE_RANGE   = 12           -- hold-E within this to shove IT

-- NOTE: your default WalkSpeed is 16. These stay UNDER that on purpose so you can
-- always out-run it in a straight line ("a bit faster than him") -- it only catches
-- kids who stop, get cornered, or run into it.
local SPEED_MIN     = 9            -- chase speed when it just woke
local SPEED_MAX     = 14           -- ...ramping to this the longer it chases (still < 16)
local RAMP_TIME     = 14           -- seconds of chasing to reach SPEED_MAX
local WANDER_SPEED  = 5

local KNOCK_BACK    = 60           -- how hard it shoves YOU
local KNOCK_UP      = 22
local STUN_TIME     = 4            -- seconds it's stunned after you shove it
local SHOVES_PER_CHUNK = 2         -- shoves before it coughs up a chocolate chunk

-- audio (owned ids only; "" silent)
local SOUND_ROAR   = ""
local SOUND_STOMP  = ""

local CHOC   = Color3.fromRGB(82, 46, 23)     -- rich milk-chocolate
local CHOC_HI = Color3.fromRGB(132, 84, 46)   -- glossy highlight chocolate
local BODY_BASE = Vector3.new(9, 10, 9)   -- the body's resting size (breathing/enrage scale off this)

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s) return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", "")) end
local function firstBasePart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end
local function pollFor(fn, t)
	local t0 = os.clock()
	repeat local r = fn(); if r then return r end; task.wait(0.5) until os.clock() - t0 > (t or 45)
	return fn()
end
local function mk(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end
local function playSound(id, vol)
	if not id or id == "" then return end
	local s = Instance.new("Sound"); s.SoundId = id; s.Volume = vol or 0.7
	s.Parent = SoundService; s:Play(); Debris:AddItem(s, 6)
end
local function hrpOf()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- every player's root part, if they have a character
local function hrpFor(plr)
	local c = plr.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- ============================================================================
-- STATE
-- ============================================================================
local islandPos, homePos
local monster, monBody           -- the model + its main part
local state = "sleep"            -- sleep | hunt | stunned | strollhome
local chaseT = 0
local stunUntil = 0
local shoveCount = 0
local targetPlayer = nil         -- which kid it's currently locked onto
local retargetAt = 0             -- next time it re-evaluates who to chase
local poseSwing = 0              -- 0 = still, ~1 = full running gait (drives the walk cycle)
local monTag = nil               -- floating mood label above its head
local lastFootPos = nil          -- last spot it stamped a chocolate footprint
local lastStomp = 0              -- throttles the stomp shockwave rings
local stompRing                  -- forward-declared: dust shockwave (defined near the hunt loop, used in the eat burst)
local eating = false             -- true while it's gulping you (freezes it so the mouth holds still)

-- Pick who to hunt: the nearest player standing on island3. It re-picks every few
-- seconds so it doesn't fixate on one kid, BUT anyone who gets really close is grabbed
-- immediately regardless -- so it always goes for whoever's on top of it.
local function pickTarget(preferClose)
	if not (monBody and homePos) then return nil end
	local here = monBody.Position
	local best, bestD
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = hrpFor(plr)
		if hrp and (hrp.Position - homePos).Magnitude <= ISLAND_RANGE then
			local d = (hrp.Position - here).Magnitude
			if not bestD or d < bestD then best, bestD = plr, d end
		end
	end
	-- someone right on top of it always wins the lock
	if preferClose and best and bestD and bestD <= CATCH_RANGE + 3 then return best end
	return best
end

local function targetHRP()
	return targetPlayer and hrpFor(targetPlayer) or nil
end

-- ============================================================================
-- WALK-CYCLE ANIMATION -- each returns a per-frame CFrame delta for its limb.
-- `swing` is 0 (still) .. ~1 (full run); `phase` is a shared marching clock.
-- ============================================================================
-- swing a limb like a pendulum about a joint `pivotY` studs ABOVE its own centre,
-- so arms/legs rotate from the shoulder/hip and stay attached instead of sliding.
-- Parts stacked on the same joint (arm+fist, leg+foot) share ph0/maxAng so they
-- rotate by the identical angle about the identical world point -> move as one piece.
local function pivotSwing(ph0, pivotY, maxAng)
	return function(phase, swing)
		local ang = math.sin(phase + ph0) * maxAng * swing
		return CFrame.new(0, pivotY, 0) * CFrame.Angles(ang, 0, 0) * CFrame.new(0, -pivotY, 0)
	end
end
local function bellyJiggle()   -- the gut bounces/rocks, jiggling faster while running
	return function(phase, swing)
		local amp = 0.3 + swing * 0.9
		return CFrame.new(0, math.sin(phase * 2) * 0.28 * amp, math.sin(phase * 2 + 1) * 0.22 * amp)
	end
end
local function jawChomp()      -- jaw gnashes constantly, harder while running
	return function(phase, swing)
		local open = (math.sin(phase * 2.2) * 0.5 + 0.5) * (0.3 + swing * 0.4)
		return CFrame.Angles(open, 0, 0) * CFrame.new(0, -open * 0.5, 0)
	end
end

-- ============================================================================
-- BUILD THE MONSTER
-- ============================================================================
local monParts = {}
local eyeL, eyeR, jaw, maw
local droolPE, steamMon   -- drool while hunting, heat-steam when enraged
local function buildMonster(at)
	local m = Instance.new("Model"); m.Name = "ChocolateMonster"
	m:SetAttribute("QuestProp", true)

	local body = mk({ Name = "Body", Shape = Enum.PartType.Ball, Size = BODY_BASE,
		Color = CHOC, Material = Enum.Material.SmoothPlastic, Reflectance = 0.24, CanCollide = false })
	body.CFrame = CFrame.new(at + Vector3.new(0, 7, 0))
	body.Parent = m; m.PrimaryPart = body
	monBody = body

	local function attach(name, size, off, colour, shape, anim)
		local p = mk({ Name = name, Size = size, Color = colour or CHOC, Material = Enum.Material.SmoothPlastic })
		if shape then p.Shape = shape end
		p.Parent = m
		monParts[#monParts + 1] = { part = p, off = off, anim = anim }
		return p
	end

	-- big overlapping shoulders/haunches so it reads as one lumpy chocolate mass
	attach("LumpL", Vector3.new(5, 5, 5), CFrame.new(-4, 1.4, 0), CHOC_HI, Enum.PartType.Ball)
	attach("LumpR", Vector3.new(5, 5, 5), CFrame.new(4, 1.4, 0), CHOC_HI, Enum.PartType.Ball)
	-- big round belly (fat all around) + a neck that bridges the torso into the head
	attach("Belly", Vector3.new(8, 7, 7.5), CFrame.new(0, -1.3, 0), CHOC_HI, Enum.PartType.Ball, bellyJiggle())
	attach("Neck",  Vector3.new(3.8, 3.4, 3.8), CFrame.new(0, 3.3, -0.3), CHOC, Enum.PartType.Ball)
	attach("Head",  Vector3.new(5.6, 5.1, 5.6), CFrame.new(0, 4.4, -0.5), CHOC, Enum.PartType.Ball)

	-- hip fillers that bridge the body down into the legs (no gap)
	attach("HipL", Vector3.new(3.6, 3.6, 3.6), CFrame.new(-2.2, -4.0, 0), CHOC, Enum.PartType.Ball)
	attach("HipR", Vector3.new(3.6, 3.6, 3.6), CFrame.new(2.2, -4.0, 0), CHOC, Enum.PartType.Ball)

	-- arms plug into the shoulders; arm + fist swing from the shoulder joint as ONE piece
	attach("ArmL", Vector3.new(2.8, 5.4, 2.8), CFrame.new(-4.7, 0.2, 0), CHOC, nil, pivotSwing(math.pi, 2.8, 0.5))
	attach("ArmR", Vector3.new(2.8, 5.4, 2.8), CFrame.new(4.7, 0.2, 0), CHOC, nil, pivotSwing(0, 2.8, 0.5))
	attach("FistL", Vector3.new(3.2, 3.2, 3.2), CFrame.new(-4.7, -3.6, 0), CHOC_HI, Enum.PartType.Ball, pivotSwing(math.pi, 6.6, 0.5))
	attach("FistR", Vector3.new(3.2, 3.2, 3.2), CFrame.new(4.7, -3.6, 0), CHOC_HI, Enum.PartType.Ball, pivotSwing(0, 6.6, 0.5))

	-- legs swing from the hips; feet swing with them as ONE piece
	attach("LegL", Vector3.new(3, 4.6, 3), CFrame.new(-2.2, -5.6, 0), CHOC, nil, pivotSwing(0, 2.0, 0.45))
	attach("LegR", Vector3.new(3, 4.6, 3), CFrame.new(2.2, -5.6, 0), CHOC, nil, pivotSwing(math.pi, 2.0, 0.45))
	attach("FootL", Vector3.new(3.2, 2.2, 4.2), CFrame.new(-2.2, -7.8, -0.6), CHOC_HI, nil, pivotSwing(0, 4.2, 0.45))
	attach("FootR", Vector3.new(3.2, 2.2, 4.2), CFrame.new(2.2, -7.8, -0.6), CHOC_HI, nil, pivotSwing(math.pi, 4.2, 0.45))

	-- angry glowing eyes with dark pupils
	eyeL = attach("EyeL", Vector3.new(1.4, 1.4, 0.7), CFrame.new(-1.4, 5, -2.5), Color3.fromRGB(255, 232, 120), Enum.PartType.Ball)
	eyeR = attach("EyeR", Vector3.new(1.4, 1.4, 0.7), CFrame.new(1.4, 5, -2.5), Color3.fromRGB(255, 232, 120), Enum.PartType.Ball)
	eyeL.Material = Enum.Material.Neon; eyeR.Material = Enum.Material.Neon
	attach("PupL", Vector3.new(0.55, 0.6, 0.4), CFrame.new(-1.4, 4.9, -2.95), Color3.fromRGB(20, 10, 6), Enum.PartType.Ball)
	attach("PupR", Vector3.new(0.55, 0.6, 0.4), CFrame.new(1.4, 4.9, -2.95), Color3.fromRGB(20, 10, 6), Enum.PartType.Ball)

	-- heavy angry brows
	attach("BrowL", Vector3.new(2.0, 0.6, 0.6), CFrame.new(-1.4, 6.0, -2.6) * CFrame.Angles(0, 0, math.rad(-22)), Color3.fromRGB(40, 22, 12))
	attach("BrowR", Vector3.new(2.0, 0.6, 0.6), CFrame.new(1.4, 6.0, -2.6) * CFrame.Angles(0, 0, math.rad(22)), Color3.fromRGB(40, 22, 12))

	-- nostrils
	attach("NoseL", Vector3.new(0.45, 0.35, 0.35), CFrame.new(-0.6, 4.2, -3.0), Color3.fromRGB(28, 15, 9), Enum.PartType.Ball)
	attach("NoseR", Vector3.new(0.45, 0.35, 0.35), CFrame.new(0.6, 4.2, -3.0), Color3.fromRGB(28, 15, 9), Enum.PartType.Ball)

	-- dark inner maw -- the "gut" you get sucked into, recessed behind the teeth
	maw = attach("Maw", Vector3.new(3.0, 2.3, 1.8), CFrame.new(0, 3.35, -2.6), Color3.fromRGB(16, 8, 4), Enum.PartType.Ball)

	-- dripping jaw
	jaw = attach("Jaw", Vector3.new(3.8, 1.5, 2.1), CFrame.new(0, 2.6, -2.4), Color3.fromRGB(50, 28, 15), nil, jawChomp())

	-- jagged teeth, upper row + lower row
	for i = -2, 2 do
		attach("ToothU" .. i, Vector3.new(0.5, 1.0, 0.35), CFrame.new(i * 0.75, 4.0, -3.15), Color3.fromRGB(240, 235, 220))
	end
	for i = -1, 1 do
		attach("ToothL" .. i, Vector3.new(0.5, 0.8, 0.35), CFrame.new(i * 0.9, 2.9, -3.25), Color3.fromRGB(240, 235, 220))
	end

	-- little chocolate horns
	attach("HornL", Vector3.new(1.0, 2.4, 1.0), CFrame.new(-1.8, 7.3, -0.4) * CFrame.Angles(math.rad(12), 0, math.rad(-20)), Color3.fromRGB(52, 30, 16), Enum.PartType.Ball)
	attach("HornR", Vector3.new(1.0, 2.4, 1.0), CFrame.new(1.8, 7.3, -0.4) * CFrame.Angles(math.rad(12), 0, math.rad(20)), Color3.fromRGB(52, 30, 16), Enum.PartType.Ball)

	-- gooey chocolate drips hanging off it (arm drips swing with the arms)
	attach("DripChin", Vector3.new(1.1, 2.6, 1.1), CFrame.new(0, 1.3, -2.4), CHOC, Enum.PartType.Ball)
	attach("DripBelly", Vector3.new(1.4, 3.0, 1.4), CFrame.new(-1.8, -4.8, -1.6), CHOC, Enum.PartType.Ball)
	attach("DripBelly2", Vector3.new(1.2, 2.4, 1.2), CFrame.new(1.9, -5.0, -1.2), CHOC_HI, Enum.PartType.Ball)
	attach("DripArmL", Vector3.new(0.9, 2.0, 0.9), CFrame.new(-4.7, -5.4, 0), CHOC, Enum.PartType.Ball, pivotSwing(math.pi, 8.4, 0.5))
	attach("DripArmR", Vector3.new(0.9, 2.0, 0.9), CFrame.new(4.7, -5.4, 0), CHOC, Enum.PartType.Ball, pivotSwing(0, 8.4, 0.5))

	-- rainbow candy sprinkles stuck in the chocolate (candy-realm flavour)
	local SPRINKLE = { Color3.fromRGB(255,120,180), Color3.fromRGB(120,200,255), Color3.fromRGB(255,225,90),
		Color3.fromRGB(140,230,140), Color3.fromRGB(255,255,255), Color3.fromRGB(255,120,110) }
	for i = 1, 18 do
		local u, v = math.random(), math.random()
		local theta = 2 * math.pi * u
		local phi = math.acos(2 * v - 1)
		local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta))
		local off = CFrame.new(dir * 4.5) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		attach("Sprinkle" .. i, Vector3.new(1.0, 0.32, 0.32), off, SPRINKLE[(i % #SPRINKLE) + 1], Enum.PartType.Cylinder)
	end

	-- glossy candy-coat: a subtle sheen across the whole chocolate mass so it reads as real, wet
	-- chocolate (skip the eyes/teeth/pupils/sprinkles so they stay bright/matte, not mirror-y).
	for _, e in ipairs(monParts) do
		local nm = e.part.Name
		if not (nm:match("^Eye") or nm:match("^Pup") or nm:match("^Tooth") or nm:match("^Brow")
			or nm:match("^Nose") or nm:match("^Sprinkle") or nm == "Maw") then
			e.part.Reflectance = 0.12
		end
	end

	-- melty chocolate drips off the body (particles)
	local att = Instance.new("Attachment"); att.Position = Vector3.new(0, -4, 0); att.Parent = body
	local drip = Instance.new("ParticleEmitter")
	drip.Color = ColorSequence.new(CHOC); drip.Size = NumberSequence.new(0.8)
	drip.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	drip.Lifetime = NumberRange.new(0.6, 1.1); drip.Rate = 8; drip.Speed = NumberRange.new(1, 3)
	drip.Acceleration = Vector3.new(0, -20, 0); drip.SpreadAngle = Vector2.new(20, 20); drip.Parent = att

	-- drool that strings from the mouth while it's hunting (toggled by state)
	local mouthAtt = Instance.new("Attachment"); mouthAtt.Position = Vector3.new(0, 3.0, -3.1); mouthAtt.Parent = body
	droolPE = Instance.new("ParticleEmitter")
	droolPE.Color = ColorSequence.new(CHOC_HI); droolPE.Size = NumberSequence.new(0.55)
	droolPE.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	droolPE.Lifetime = NumberRange.new(0.7, 1.2); droolPE.Rate = 7; droolPE.Speed = NumberRange.new(0.5, 1.5)
	droolPE.Acceleration = Vector3.new(0, -22, 0); droolPE.SpreadAngle = Vector2.new(12, 12)
	droolPE.Enabled = false; droolPE.Parent = mouthAtt

	-- heat-steam rising off it when enraged (toggled by state)
	steamMon = Instance.new("Smoke")
	steamMon.Color = Color3.fromRGB(120, 100, 90); steamMon.Opacity = 0.25; steamMon.RiseVelocity = 6
	steamMon.Size = 6; steamMon.Enabled = false; steamMon.Parent = body

	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(150, 100, 58); hl.FillTransparency = 0.72   -- stronger wet-chocolate sheen
	hl.OutlineColor = Color3.fromRGB(30, 16, 8); hl.OutlineTransparency = 0.3
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = body; hl.Parent = m

	-- floating mood label above its head (reacts to state in the warn loop)
	local tag = Instance.new("BillboardGui")
	tag.Name = "MonTag"; tag.Size = UDim2.fromOffset(240, 54); tag.StudsOffset = Vector3.new(0, 8, 0)
	tag.AlwaysOnTop = true; tag.MaxDistance = 220; tag.Adornee = body; tag.Parent = body
	monTag = Instance.new("TextLabel")
	monTag.Size = UDim2.fromScale(1, 1); monTag.BackgroundTransparency = 1
	monTag.Font = Enum.Font.GothamBlack; monTag.TextScaled = true
	monTag.TextColor3 = Color3.fromRGB(255, 255, 255)
	monTag.TextStrokeColor3 = Color3.fromRGB(30, 16, 8); monTag.TextStrokeTransparency = 0
	monTag.Text = "\xF0\x9F\x8D\xAB Chocolate Monster"; monTag.Parent = tag

	m.Parent = Workspace
	monster = m

	-- SHOVE prompt: hold E when close to knock it away
	body.CanQuery = true
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "SHOVE"; prompt.ObjectText = "Chocolate Monster"
	prompt.HoldDuration = 0; prompt.MaxActivationDistance = SHOVE_RANGE   -- tap E, no holding
	prompt.RequiresLineOfSight = false; prompt.Parent = body
	prompt.Triggered:Connect(shoveMonster)

	return m
end

-- keep every attached part glued to the body at its offset, applying its walk-cycle
-- delta so limbs stomp/swing and the jaw gnashes as the whole thing moves.
local function poseMonster()
	if not (monBody and monBody.Parent) then return end
	local phase = os.clock() * 9
	for _, e in ipairs(monParts) do
		if e.part.Parent then
			local base = monBody.CFrame * e.off
			e.part.CFrame = e.anim and (base * e.anim(phase, poseSwing)) or base
		end
	end
end

-- ============================================================================
-- ROAR + FACE + FEELERS
-- ============================================================================
local warnGui = Instance.new("ScreenGui")
warnGui.Name = "MonsterWarn"; warnGui.ResetOnSpawn = false; warnGui.DisplayOrder = 14
warnGui.IgnoreGuiInset = true; warnGui.Enabled = false; warnGui.Parent = PlayerGui
local warnEdge = Instance.new("Frame")
warnEdge.Size = UDim2.fromScale(1, 1); warnEdge.BackgroundTransparency = 1; warnEdge.BorderSizePixel = 0
warnEdge.Parent = warnGui
local wStroke = Instance.new("UIStroke"); wStroke.Color = Color3.fromRGB(90, 40, 20); wStroke.Thickness = 14; wStroke.Transparency = 1; wStroke.Parent = warnEdge
local wGrad = Instance.new("UIGradient"); wGrad.Parent = wStroke

local function roar()
	playSound(SOUND_ROAR, 0.9)
	-- eyes flare, jaw drops
	if eyeL then
		TweenService:Create(eyeL, TweenInfo.new(0.15), { Color = Color3.fromRGB(255, 90, 40) }):Play()
		TweenService:Create(eyeR, TweenInfo.new(0.15), { Color = Color3.fromRGB(255, 90, 40) }):Play()
		task.delay(0.6, function()
			if eyeL then TweenService:Create(eyeL, TweenInfo.new(0.4), { Color = Color3.fromRGB(255, 232, 120) }):Play() end
			if eyeR then TweenService:Create(eyeR, TweenInfo.new(0.4), { Color = Color3.fromRGB(255, 232, 120) }):Play() end
		end)
	end
	-- screen edge pulse
	warnGui.Enabled = true
	wStroke.Transparency = 0.2
	TweenService:Create(wStroke, TweenInfo.new(0.9), { Transparency = 1 }):Play()
end

-- ============================================================================
-- SHOVE IT BACK
-- ============================================================================
function shoveMonster()
	if not (monBody and monBody.Parent) then return end
	local hrp = hrpOf(); if not hrp then return end
	if (hrp.Position - monBody.Position).Magnitude > SHOVE_RANGE + 3 then return end

	state = "stunned"
	stunUntil = os.clock() + STUN_TIME
	shoveCount += 1

	-- fling it away from you
	local away = (monBody.Position - hrp.Position) * Vector3.new(1, 0, 1)
	away = (away.Magnitude > 0.5) and away.Unit or Vector3.new(0, 0, 1)
	local land = monBody.Position + away * 22
	TweenService:Create(monBody, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(land + Vector3.new(0, 3, 0)) }):Play()

	-- splat of chocolate
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2
		local blob = mk({ Name = "ChocSplat", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9),
			Color = CHOC_HI, Material = Enum.Material.SmoothPlastic })
		blob.CFrame = monBody.CFrame
		blob.Parent = Workspace
		TweenService:Create(blob, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = monBody.CFrame * CFrame.new(math.cos(a) * 8, -2, math.sin(a) * 8), Transparency = 1 }):Play()
		Debris:AddItem(blob, 0.8)
	end

	-- dazed eyes
	if eyeL then eyeL.Color = Color3.fromRGB(150, 150, 160); eyeR.Color = Color3.fromRGB(150, 150, 160) end

	-- dizzy stars orbiting its head while it's seeing stars
	task.spawn(function()
		local stars = {}
		for i = 1, 4 do
			stars[i] = mk({ Name = "DizzyStar", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6),
				Color = Color3.fromRGB(255, 240, 120), Material = Enum.Material.Neon })
			stars[i].Parent = Workspace
		end
		local t0 = os.clock()
		while os.clock() - t0 < STUN_TIME and monBody and monBody.Parent do
			local c = monBody.Position + Vector3.new(0, 6.5, 0)
			for i, s in ipairs(stars) do
				local a = os.clock() * 4 + i * (math.pi / 2)
				s.CFrame = CFrame.new(c + Vector3.new(math.cos(a) * 3, math.sin(a * 2) * 0.5, math.sin(a) * 3))
			end
			RunService.RenderStepped:Wait()
		end
		for _, s in ipairs(stars) do s:Destroy() end
	end)

	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({ text = "\xF0\x9F\x8D\xAB You shoved the Chocolate Monster back!", color = CHOC_HI }) end)
	end

	-- every couple of shoves it coughs up a chocolate chunk (feeds the Cookie quest theme)
	if shoveCount % SHOVES_PER_CHUNK == 0 then
		local chunk = Instance.new("Model"); chunk.Name = "chunk"   -- the Cookie quest turns "chunk" into a pickup
		chunk:SetAttribute("QuestProp", false)
		local c = mk({ Name = "ChunkBit", Size = Vector3.new(2, 1.4, 2), Color = CHOC,
			Material = Enum.Material.SmoothPlastic, Reflectance = 0.06, CanQuery = true })
		-- Drop it on the GROUND, not at the monster's floating body. The Cookie quest turns this
		-- "chunk" into a bobbing pickup from wherever it lands -- spawn it in mid-air (the body hovers
		-- ~9 studs up) and the pickup hovers in the sky forever ("levitating chocolate"). Raycast down.
		local dropXZ = monBody.Position + Vector3.new(0, 0, -4)
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		local filter = { monster }
		if player.Character then filter[#filter + 1] = player.Character end
		rp.FilterDescendantsInstances = filter
		local hit = Workspace:Raycast(dropXZ + Vector3.new(0, 30, 0), Vector3.new(0, -200, 0), rp)
		local gy = hit and hit.Position.Y or (monBody.Position.Y - 9)
		c.CFrame = CFrame.new(dropXZ.X, gy + 0.8, dropXZ.Z)
		c.Parent = chunk; chunk.PrimaryPart = c
		chunk.Parent = Workspace
		if _G.NotifyCenter then
			pcall(function() _G.NotifyCenter.push({ text = "\xF0\x9F\x8D\xAB ...and dropped a chocolate chunk!", color = CHOC }) end)
		end
	end
end

-- ============================================================================
-- CATCH -- it GULPS you (screen dark-chocolate), SPITS you across the island,
-- and leaves you COATED in dripping chocolate + slowed. Never kills.
-- ============================================================================
-- full-screen chocolate splat overlay (built once)
local splatGui = Instance.new("ScreenGui")
splatGui.Name = "ChocSplat"; splatGui.ResetOnSpawn = false; splatGui.DisplayOrder = 22
splatGui.IgnoreGuiInset = true; splatGui.Enabled = false; splatGui.Parent = PlayerGui
local splat = Instance.new("Frame")
splat.Size = UDim2.fromScale(1, 1); splat.BackgroundColor3 = Color3.fromRGB(48, 26, 12)
splat.BackgroundTransparency = 1; splat.BorderSizePixel = 0; splat.Parent = splatGui
-- a few big blobs so it reads as a splat, not a flat fade
local splatBlobs = {}
for i = 1, 7 do
	local b = Instance.new("Frame")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromScale(0.15 + (i % 4) * 0.24, 0.2 + (i % 3) * 0.3)
	b.Size = UDim2.fromScale(0.35 + (i % 3) * 0.15, 0.35 + (i % 3) * 0.15)
	b.BackgroundColor3 = Color3.fromRGB(60, 34, 16); b.BackgroundTransparency = 1; b.BorderSizePixel = 0
	b.Parent = splatGui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = b
	splatBlobs[#splatBlobs + 1] = b
end

-- ============================================================================
-- INSIDE-THE-BELLY overlay -- the churning chocolate gut you land in when eaten,
-- with rising bubbles, squeezing walls, and a MASH-E-to-escape struggle bar.
-- ============================================================================
local bellyGui = Instance.new("ScreenGui")
bellyGui.Name = "MonsterBelly"; bellyGui.ResetOnSpawn = false; bellyGui.DisplayOrder = 23
bellyGui.IgnoreGuiInset = true; bellyGui.Enabled = false; bellyGui.Parent = PlayerGui
local bellyBG = Instance.new("Frame")
bellyBG.Size = UDim2.fromScale(1, 1); bellyBG.BackgroundColor3 = Color3.fromRGB(54, 29, 13)
bellyBG.BorderSizePixel = 0; bellyBG.Parent = bellyGui
-- fleshy depth: warm in the middle, darker at the top/bottom edges -> a soft enclosed vignette
local bgGrad = Instance.new("UIGradient")
bgGrad.Rotation = 90
bgGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 40, 22)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 235, 220)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(58, 30, 16)),
})
bgGrad.Parent = bellyBG
-- dark gooey blobs crowding the edges (fleshy gut walls)
for i = 1, 6 do
	local d = Instance.new("Frame"); d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.fromScale((i % 3) * 0.5, (i < 4) and 0.02 or 0.98)
	d.Size = UDim2.fromScale(0.55, 0.5); d.BackgroundColor3 = Color3.fromRGB(28, 14, 5)
	d.BorderSizePixel = 0; d.Parent = bellyGui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = d
end
-- rising gut bubbles
local bellyBubbles = {}
for i = 1, 16 do
	local b = Instance.new("Frame"); b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.BackgroundColor3 = Color3.fromRGB(98, 60, 30); b.BackgroundTransparency = 0.4
	b.BorderSizePixel = 0; b.Parent = bellyGui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = b
	bellyBubbles[i] = { f = b, seed = i * 0.37, sp = 0.5 + (i % 5) * 0.15, sz = 40 + (i % 4) * 34 }
end
-- struggle prompt + meter
local bellyLbl = Instance.new("TextLabel")
bellyLbl.AnchorPoint = Vector2.new(0.5, 0.5); bellyLbl.Position = UDim2.new(0.5, 0, 0.72, 0)
bellyLbl.Size = UDim2.fromOffset(460, 46); bellyLbl.BackgroundTransparency = 1
bellyLbl.Font = Enum.Font.GothamBlack; bellyLbl.TextScaled = true
bellyLbl.TextColor3 = Color3.fromRGB(255, 240, 150); bellyLbl.TextStrokeColor3 = Color3.fromRGB(20, 10, 4)
bellyLbl.TextStrokeTransparency = 0; bellyLbl.Text = "MASH  E  TO  ESCAPE!"; bellyLbl.ZIndex = 10; bellyLbl.Parent = bellyGui
local bellyBar = Instance.new("Frame")
bellyBar.AnchorPoint = Vector2.new(0.5, 0.5); bellyBar.Position = UDim2.new(0.5, 0, 0.8, 0)
bellyBar.Size = UDim2.fromOffset(360, 30); bellyBar.BackgroundColor3 = Color3.fromRGB(22, 11, 4)
bellyBar.BorderSizePixel = 0; bellyBar.ZIndex = 10; bellyBar.Parent = bellyGui
local bbCorner = Instance.new("UICorner"); bbCorner.CornerRadius = UDim.new(1, 0); bbCorner.Parent = bellyBar
local bbStroke = Instance.new("UIStroke"); bbStroke.Color = Color3.fromRGB(80, 46, 22); bbStroke.Thickness = 3; bbStroke.Parent = bellyBar
local bellyFill = Instance.new("Frame")
bellyFill.Size = UDim2.new(0, 0, 1, 0); bellyFill.BackgroundColor3 = Color3.fromRGB(120, 225, 120)
bellyFill.BorderSizePixel = 0; bellyFill.ZIndex = 11; bellyFill.Parent = bellyBar
local bfCorner = Instance.new("UICorner"); bfCorner.CornerRadius = UDim.new(1, 0); bfCorner.Parent = bellyFill

-- queasy green bile wash that creeps in the longer you're stuck
local bellyBile = Instance.new("Frame")
bellyBile.Size = UDim2.fromScale(1, 1); bellyBile.BackgroundColor3 = Color3.fromRGB(70, 120, 30)
bellyBile.BackgroundTransparency = 1; bellyBile.BorderSizePixel = 0; bellyBile.Parent = bellyGui
-- heartbeat red vignette pulse
local bellyHeart = Instance.new("Frame")
bellyHeart.Size = UDim2.fromScale(1, 1); bellyHeart.BackgroundColor3 = Color3.fromRGB(120, 20, 10)
bellyHeart.BackgroundTransparency = 1; bellyHeart.BorderSizePixel = 0; bellyHeart.Parent = bellyGui
-- teeth framing the top + bottom, like you're wedged in a maw
for row = 0, 1 do
	for i = 0, 9 do
		local t = Instance.new("Frame"); t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(i / 9, row)              -- along the top (0) or bottom (1) edge
		t.Size = UDim2.fromOffset(96, 96); t.Rotation = 45     -- a diamond; only the inner point shows
		t.BackgroundColor3 = Color3.fromRGB(240, 235, 220); t.BorderSizePixel = 0; t.ZIndex = 3; t.Parent = bellyGui
		local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 12); tc.Parent = t   -- softly rounded points
		local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(120, 90, 70); ts.Thickness = 2; ts.Transparency = 0.2; ts.Parent = t
		local tg = Instance.new("UIGradient"); tg.Rotation = (row == 0) and 90 or 270   -- top-lit gloss on both rows
		tg.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(206, 198, 178)); tg.Parent = t
	end
end
-- acid streaks oozing down the screen
local bellyDrips = {}
for i = 1, 6 do
	local d = Instance.new("Frame"); d.AnchorPoint = Vector2.new(0.5, 0)
	d.Size = UDim2.fromOffset(10, 60); d.BackgroundColor3 = Color3.fromRGB(120, 150, 40)
	d.BackgroundTransparency = 0.3; d.BorderSizePixel = 0; d.Parent = bellyGui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = d
	bellyDrips[i] = { f = d, x = 0.08 + i * 0.14, seed = i * 0.6, sp = 0.35 + (i % 3) * 0.12 }
end

-- coat the character in chocolate: brown highlight + drip particles, wiped after a while
local function coatInChocolate(seconds)
	local char = player.Character; if not char then return end
	local hl = char:FindFirstChild("ChocCoat")
	if not hl then
		hl = Instance.new("Highlight"); hl.Name = "ChocCoat"
		hl.FillColor = CHOC; hl.FillTransparency = 0.15
		hl.OutlineColor = Color3.fromRGB(40, 22, 12); hl.OutlineTransparency = 0.2
		hl.Adornee = char; hl.Parent = char
	end
	-- drip particles off the torso
	local torso = char:FindFirstChild("HumanoidRootPart")
	if torso and not torso:FindFirstChild("ChocDripAtt") then
		local att = Instance.new("Attachment"); att.Name = "ChocDripAtt"; att.Parent = torso
		local pe = Instance.new("ParticleEmitter"); pe.Name = "ChocDrip"
		pe.Color = ColorSequence.new(CHOC); pe.Size = NumberSequence.new(0.4)
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = NumberRange.new(0.5, 0.9); pe.Rate = 14; pe.Speed = NumberRange.new(0.5, 2)
		pe.Acceleration = Vector3.new(0, -18, 0); pe.Parent = att
	end
	task.delay(seconds, function()
		local c = player.Character; if not c then return end
		local h = c:FindFirstChild("ChocCoat"); if h then h:Destroy() end
		local t = c:FindFirstChild("HumanoidRootPart")
		local a = t and t:FindFirstChild("ChocDripAtt"); if a then a:Destroy() end
	end)
end

-- a spot on island3 to fling the player to -- well away from the monster
local function spitLandingSpot()
	local base = homePos or (hrpOf() and hrpOf().Position) or Vector3.new()
	local a = math.random() * math.pi * 2
	local r = 55 + math.random() * 45
	local target = base + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	-- drop onto the ground there
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { player.Character, monster }
	local hit = Workspace:Raycast(target + Vector3.new(0, 60, 0), Vector3.new(0, -220, 0), rp)
	local y = (hit and hit.Position.Y or base.Y) + 5
	return Vector3.new(target.X, y, target.Z)
end

-- where the mouth is in the world (the jaw part, else in front of the body)
local function mouthPos()
	if jaw and jaw.Parent then return jaw.Position + Vector3.new(0, 0.3, 0) end
	if monBody and monBody.Parent then return monBody.Position + monBody.CFrame.LookVector * 2 + Vector3.new(0, 3, 0) end
	return Vector3.new()
end

-- the R15 body-scale NumberValues, so we can shrink the avatar as it's swallowed
local function bodyScales()
	local hum = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	local t = {}
	if hum then
		for _, n in ipairs({ "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }) do
			local v = hum:FindFirstChild(n)
			if v and v:IsA("NumberValue") then t[n] = v end
		end
	end
	return t
end

local lastCatch = 0
local caughtNow = false
local function catchPlayer(hrp)
	if os.clock() - lastCatch < 3 or caughtNow then return end
	lastCatch = os.clock()
	caughtNow = true
	eating = true

	roar()
	local char = player.Character
	local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (char and hum and root) then caughtNow = false; eating = false; return end

	-- lock you in place: no input, no gravity fighting the pull-in
	hum.WalkSpeed = 0; hum.JumpPower = 0; hum.PlatformStand = true
	local wasAnchored = root.Anchored
	root.Anchored = true

	-- remember body scale so we can shrink then restore it
	local scales, origScale = bodyScales(), {}
	for n, v in pairs(scales) do origScale[n] = v.Value end
	local inBelly = false   -- hoisted so the watchdog can also end the belly phase

	-- chocolate torn off you and sucked toward the mouth
	local suckAtt = Instance.new("Attachment"); suckAtt.Parent = root
	local suckPE = Instance.new("ParticleEmitter")
	suckPE.Color = ColorSequence.new(CHOC_HI); suckPE.Size = NumberSequence.new(0.6)
	suckPE.Transparency = NumberSequence.new(0.1); suckPE.Lifetime = NumberRange.new(0.25, 0.5)
	suckPE.Rate = 45; suckPE.Speed = NumberRange.new(7, 12); suckPE.SpreadAngle = Vector2.new(35, 35)
	suckPE.Parent = suckAtt

	-- a swirling chocolate whirlpool spun up at the mouth to pull you in
	local vortex = {}
	for i = 1, 12 do
		vortex[i] = mk({ Name = "SuckSwirl", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8),
			Color = (i % 2 == 0) and CHOC or CHOC_HI, Material = Enum.Material.SmoothPlastic })
		vortex[i].Parent = Workspace
	end
	-- the maw gapes wide open
	local mawBase = maw and maw.Size or Vector3.new(3, 2.3, 1.8)
	if maw then TweenService:Create(maw, TweenInfo.new(0.15), { Size = mawBase * 1.9 }):Play() end

	splatGui.Enabled = true

	-- safety net: if anything goes wrong, unfreeze + restore within a few seconds
	task.delay(8, function()
		if caughtNow then
			caughtNow = false; eating = false; inBelly = false
			if root then root.Anchored = wasAnchored end
			if hum then hum.PlatformStand = false; hum.WalkSpeed = 16; hum.JumpPower = 50 end
			for n, v in pairs(scales) do if v and v.Parent then v.Value = origScale[n] end end
			for _, b in ipairs(vortex) do if b and b.Parent then b:Destroy() end end
			if maw and maw.Parent then maw.Size = mawBase end
			splatGui.Enabled = false; bellyGui.Enabled = false
			setEatenHidden(false)   -- make sure they never stay invisible
		end
	end)

	task.spawn(function()
		-- 1) SUCK-IN: spiral you into the mouth, shrinking as you go
		local startPos = root.Position
		local up = Vector3.new(0, 1, 0)
		local dur, t0 = 0.6, os.clock()
		while root.Parent do
			local a = (os.clock() - t0) / dur
			if a >= 1 then break end
			local mouth = mouthPos()
			local pos = startPos:Lerp(mouth, a)
			local toM = mouth - pos
			local side = toM.Magnitude > 0.05 and toM.Unit:Cross(up) or Vector3.new(1, 0, 0)
			-- a shrinking corkscrew around the pull-line
			local orbit = side * (math.cos(a * math.pi * 6) * (1 - a) * 4) + up * (math.sin(a * math.pi * 6) * (1 - a) * 2)
			root.CFrame = CFrame.new(pos + orbit) * CFrame.Angles(0, a * math.pi * 8, a * 0.7)
			-- shrink overall, but stretch depth mid-way so you get pulled like taffy
			for n, v in pairs(scales) do
				local s = 1 - a * 0.85
				if n == "BodyDepthScale" then s = s * (1 + math.sin(a * math.pi) * 0.7) end
				v.Value = origScale[n] * s
			end
			-- whirlpool of chocolate spiralling inward around the mouth
			local now2 = os.clock()
			for i, b in ipairs(vortex) do
				if b.Parent then
					local frac = ((i / #vortex) + now2 * 0.9) % 1        -- 0 (far) -> 1 (at mouth)
					local ang = frac * math.pi * 10 + i
					local r = (1 - frac) * 7 + 0.6
					b.CFrame = CFrame.new(mouth + Vector3.new(math.cos(ang) * r, (1 - frac) * 2.5, math.sin(ang) * r))
					b.Size = Vector3.new(1, 1, 1) * (0.3 + frac * 0.7)
				end
			end
			-- screen chocolate closing in + swirling
			splat.BackgroundTransparency = 1 - a * 0.85
			for i, f in ipairs(splatBlobs) do
				f.BackgroundTransparency = 1 - a * 0.92
				f.Rotation = a * 220 * (i % 2 == 0 and 1 or -1)
				f.Position = f.Position:Lerp(UDim2.fromScale(0.5, 0.5), 0.04)
			end
			RunService.RenderStepped:Wait()
		end

		-- 2) GULP: you vanish into the mouth, whirlpool gulped down with you
		if root.Parent then root.CFrame = CFrame.new(mouthPos()) end
		suckPE.Enabled = false
		for _, b in ipairs(vortex) do b:Destroy() end
		if _G.NotifyCenter then
			pcall(function() _G.NotifyCenter.push({ text = "\xF0\x9F\x8D\xAB GULP! Swallowed by the Chocolate Monster!", color = Color3.fromRGB(120, 40, 20) }) end)
		end

		-- hide the swallowed player from everyone else (server replicates it)
		setEatenHidden(true)

		-- ---- 2b) INSIDE THE BELLY: churning gut, mash E to wriggle free --------
		splatGui.Enabled = false
		bellyGui.Enabled = true
		bellyFill.Size = UDim2.new(0, 0, 1, 0)
		inBelly = true

		-- bubbling gut + squeezing walls + heartbeat + oozing acid
		local bellyStart = os.clock()
		task.spawn(function()
			while inBelly do
				local t = os.clock()
				local elapsed = t - bellyStart
				bellyBG.BackgroundTransparency = 0.02 + (math.sin(t * 4) * 0.5 + 0.5) * 0.06   -- contractions
				for _, bb in ipairs(bellyBubbles) do
					local prog = ((t * bb.sp) + bb.seed) % 1                 -- rise bottom -> top
					local x = 0.5 + math.sin((prog + bb.seed) * math.pi * 4) * 0.34
					bb.f.Position = UDim2.fromScale(x, 1.1 - prog * 1.2)
					local grow = bb.sz * (0.4 + prog * 0.8)
					bb.f.Size = UDim2.fromOffset(grow, grow)
					bb.f.BackgroundTransparency = 0.35 + prog * 0.5
				end
				-- acid streaks ooze down and reset
				for _, dp in ipairs(bellyDrips) do
					local prog = ((t * dp.sp) + dp.seed) % 1
					dp.f.Position = UDim2.fromScale(dp.x, -0.05 + prog * 1.05)
					dp.f.Size = UDim2.fromOffset(10, 50 + prog * 120)
				end
				-- double-thump heartbeat -> red vignette pulse
				local beat = (t * 1.6) % 1
				local thump = math.max(math.exp(-((beat) ^ 2) * 60), math.exp(-((beat - 0.16) ^ 2) * 60))
				bellyHeart.BackgroundTransparency = 1 - thump * 0.4
				-- queasy green bile creeps in the longer you take (maxes ~0.45)
				bellyBile.BackgroundTransparency = 1 - math.clamp(elapsed / 5, 0, 1) * 0.45
				RunService.RenderStepped:Wait()
			end
		end)

		-- the monster's belly bulges + a squirming lump (YOU) slides around inside it
		local lump = mk({ Name = "BellyLump", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3),
			Color = CHOC_HI, Material = Enum.Material.SmoothPlastic, Reflectance = 0.16 })
		lump.Parent = Workspace
		task.spawn(function()
			while inBelly and monBody and monBody.Parent do
				local t = os.clock()
				lump.CFrame = monBody.CFrame * CFrame.new(math.sin(t * 5) * 3, math.cos(t * 4) * 2 - 1, 4.2)
				RunService.RenderStepped:Wait()
			end
			if lump then lump:Destroy() end
		end)

		-- MASH E to escape (auto-frees after a few seconds so nobody gets stuck)
		local struggle, NEED, tStart = 0, 6, os.clock()
		local bodyBaseSize = monBody and monBody.Size or Vector3.new(9, 10, 9)
		local function jiggle()   -- each tap pops the belly + fills the bar
			if monBody and monBody.Parent then
				TweenService:Create(monBody, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = bodyBaseSize * 1.14 }):Play()
				task.delay(0.1, function() if monBody and monBody.Parent then TweenService:Create(monBody, TweenInfo.new(0.14), { Size = bodyBaseSize }):Play() end end)
			end
		end
		local conn = UserInputService.InputBegan:Connect(function(input, gp)
			if gp or not inBelly then return end
			if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Space then
				struggle += 1; jiggle()
			end
		end)
		while inBelly do
			local byTaps = struggle / NEED
			local byTime = (os.clock() - tStart) / 4.5      -- guaranteed out by ~4.5s
			local fill = math.clamp(math.max(byTaps, byTime), 0, 1)
			bellyFill.Size = UDim2.new(fill, 0, 1, 0)
			bellyFill.BackgroundColor3 = Color3.fromRGB(120, 225, 120):Lerp(Color3.fromRGB(255, 240, 150), fill)
			if fill >= 1 then inBelly = false end
			RunService.RenderStepped:Wait()
		end
		conn:Disconnect()
		bellyGui.Enabled = false
		if monBody and monBody.Parent then monBody.Size = bodyBaseSize end   -- settle the belly

		-- 3) SPIT: restore size, fling you across the island, coated in chocolate
		for n, v in pairs(scales) do if v and v.Parent then v.Value = origScale[n] end end
		if suckAtt then suckAtt:Destroy() end
		if maw and maw.Parent then TweenService:Create(maw, TweenInfo.new(0.25), { Size = mawBase }):Play() end
		local land = spitLandingSpot()
		root.Anchored = wasAnchored
		hum.PlatformStand = false
		if player.Character then player.Character:PivotTo(CFrame.new(land)) end
		coatInChocolate(4)
		setEatenHidden(false)   -- pop back into view, spat across the island

		-- ESCAPE BURST: it heaves and blasts chocolate everywhere as it spits you out
		if monBody and monBody.Parent then
			local c = monBody.Position
			for i = 1, 18 do
				local a = (i / 18) * math.pi * 2
				local blob = mk({ Name = "EscSplat", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2),
					Color = (i % 2 == 0) and CHOC or CHOC_HI, Material = Enum.Material.SmoothPlastic })
				blob.CFrame = CFrame.new(c + Vector3.new(0, 2, 0)); blob.Parent = Workspace
				local dir = Vector3.new(math.cos(a), 0.7, math.sin(a))
				TweenService:Create(blob, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ CFrame = CFrame.new(c + dir * 15), Transparency = 1 }):Play()
				Debris:AddItem(blob, 0.7)
			end
			stompRing(c)
			-- BURRRP! a chocolate puff belches from its mouth
			local mp = mouthPos()
			for i = 1, 6 do
				local puff = mk({ Name = "BurpPuff", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2),
					Color = Color3.fromRGB(90, 60, 34), Material = Enum.Material.SmoothPlastic, Transparency = 0.3 })
				puff.CFrame = CFrame.new(mp + Vector3.new((math.random() - 0.5) * 2, 0, 0)); puff.Parent = Workspace
				TweenService:Create(puff, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = Vector3.new(6, 6, 6), CFrame = CFrame.new(mp + monBody.CFrame.LookVector * 6 + Vector3.new(0, 2, 0)), Transparency = 1 }):Play()
				Debris:AddItem(puff, 0.9)
			end
			-- gag recoil: rear back toward where it spat you, then settle (eating holds the pose)
			local rc = CFrame.lookAt(c, Vector3.new(land.X, c.Y, land.Z))
			monBody.CFrame = rc
			TweenService:Create(monBody, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ CFrame = rc * CFrame.Angles(math.rad(34), 0, 0) }):Play()
			task.delay(0.24, function()
				if monBody and monBody.Parent then TweenService:Create(monBody, TweenInfo.new(0.2), { CFrame = rc }):Play() end
			end)
		end
		task.wait(0.5)
		eating = false

		for _, f in ipairs(splatGui:GetChildren()) do
			if f:IsA("Frame") then TweenService:Create(f, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play() end
		end
		-- reset the swirled blobs to their spots for next time
		task.delay(0.9, function()
			splatGui.Enabled = false
			for i, f in ipairs(splatBlobs) do
				f.Rotation = 0
				f.Position = UDim2.fromScale(0.15 + (i % 4) * 0.24, 0.2 + (i % 3) * 0.3)
			end
		end)

		-- 4) DAZED: slowed while the chocolate drips off, then back to normal
		local h2 = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
		if h2 then
			h2.JumpPower = 50; h2.WalkSpeed = 8
			task.delay(4, function()
				local h3 = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
				if h3 then h3.WalkSpeed = 16 end
			end)
		end
		if _G.NotifyCenter then
			pcall(function() _G.NotifyCenter.push({ text = "\xF0\x9F\x8D\xAB BURRP! You wriggled free -- spat across the island.", color = CHOC_HI }) end)
		end
		caughtNow = false
	end)
end

-- a visual-only lunge when it catches ANOTHER kid (their client does their knockback)
local lastLunge = 0
function lungeAt(hrp)
	if os.clock() - lastLunge < 1.2 then return end
	lastLunge = os.clock()
	roar()
	if monBody then
		local snap = monBody.CFrame
		monBody.CFrame = snap + (hrp.Position - monBody.Position).Unit * 2   -- a quick jab forward
	end
end

-- ============================================================================
-- THE HUNT LOOP
-- ============================================================================
local function groundY(pos)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { monster }
	if player.Character then filter[#filter + 1] = player.Character end
	rp.FilterDescendantsInstances = filter
	local hit = Workspace:Raycast(pos + Vector3.new(0, 30, 0), Vector3.new(0, -200, 0), rp)
	return hit and hit.Position.Y or pos.Y
end

-- melty chocolate footprints stamped on the ground as it walks, fading over ~3s
local function dropFootprint(pos)
	if lastFootPos and (pos - lastFootPos).Magnitude < 6 then return end
	lastFootPos = pos
	local gy = groundY(pos)
	local pf = mk({ Name = "ChocPrint", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 2.6, 2.6),
		Color = CHOC, Material = Enum.Material.SmoothPlastic, Transparency = 0.15 })
	pf.CFrame = CFrame.new(pos.X, gy + 0.12, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	pf.Parent = Workspace
	TweenService:Create(pf, TweenInfo.new(3, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	Debris:AddItem(pf, 3.1)
end

-- a flat dust shockwave ring that bursts out from a heavy footfall
stompRing = function(pos)
	local gy = groundY(pos)
	local ring = mk({ Name = "StompRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 3, 3),
		Color = Color3.fromRGB(90, 62, 40), Material = Enum.Material.SmoothPlastic, Transparency = 0.3 })
	ring.CFrame = CFrame.new(pos.X, gy + 0.2, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.4, 22, 22), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.55)
end

RunService.RenderStepped:Connect(function(dt)
	if not (monBody and monBody.Parent) then return end
	local here = monBody.Position
	local now = os.clock()

	-- while it's mid-gulp, hold it still (mouth stays put) and gape wide
	if eating then
		poseSwing = 1.0
		poseMonster()
		return
	end

	-- ---- state machine -------------------------------------------------
	if state == "stunned" then
		poseSwing = 0
		if now >= stunUntil then
			state = "hunt"; chaseT = now
			if eyeL then eyeL.Color = Color3.fromRGB(255, 232, 120); eyeR.Color = Color3.fromRGB(255, 232, 120) end
		end
		poseMonster()
		return
	end

	if state == "sleep" then
		poseSwing = 0
		monBody.Size = BODY_BASE * (1 + math.sin(now * 1.5) * 0.035)   -- slow breathing
		monBody.CFrame = CFrame.new(here.X, groundY(here) + 8.5 + math.sin(now) * 0.3, here.Z) * (monBody.CFrame - monBody.CFrame.Position)
		-- wake if ANY player wanders into aggro range on the island
		local near = pickTarget(false)
		if near then
			local hrp = hrpFor(near)
			if hrp and (hrp.Position - here).Magnitude <= AGGRO_RANGE then
				targetPlayer = near; retargetAt = now + 6
				state = "hunt"; chaseT = now; roar()
			end
		end
		poseMonster()
		return
	end

	if state == "hunt" then
		-- someone right on top of it steals the lock; otherwise re-pick every few seconds
		local snatched = pickTarget(true)
		if snatched and snatched ~= targetPlayer then
			local shrp = hrpFor(snatched)
			if shrp and (shrp.Position - here).Magnitude <= CATCH_RANGE + 3 then targetPlayer = snatched end
		elseif now >= retargetAt then
			retargetAt = now + 6
			targetPlayer = pickTarget(false) or targetPlayer   -- switch to whoever's nearest now
		end

		local hrp = targetHRP()
		local nearIsland = hrp and (hrp.Position - homePos).Magnitude <= ISLAND_RANGE
		local dist = hrp and (hrp.Position - here).Magnitude or math.huge
		-- lost the target? try to grab a new one before giving up
		if not hrp or not nearIsland or dist > LEASH_RANGE then
			local next_ = pickTarget(false)
			if next_ then targetPlayer = next_; poseMonster(); return end
			targetPlayer = nil; state = "strollhome"; poseMonster(); return
		end

		local frac = math.min(1, (now - chaseT) / RAMP_TIME)
		local speed = SPEED_MIN + (SPEED_MAX - SPEED_MIN) * frac
		poseSwing = 0.7 + frac * 0.4                 -- gait gets more frantic as it speeds up
		-- eyes redden + body swells the angrier (faster) it gets
		if eyeL and eyeL.Parent then
			local col = Color3.fromRGB(255, 232, 120):Lerp(Color3.fromRGB(255, 70, 40), frac)
			eyeL.Color = col; eyeR.Color = col
		end
		monBody.Size = BODY_BASE * (1 + frac * 0.12)
		local dir = (hrp.Position - here) * Vector3.new(1, 0, 1)
		if dir.Magnitude > 0.5 then
			dir = dir.Unit
			local np = here + dir * speed * dt
			local y = groundY(np) + 8.5 + math.abs(math.sin(now * 9)) * 0.5   -- bob once per footfall
			local roll = math.sin(now * 9) * 0.16 * poseSwing   -- heavy side-to-side waddle
			monBody.CFrame = CFrame.lookAt(Vector3.new(np.X, y, np.Z), Vector3.new(hrp.Position.X, y, hrp.Position.Z))
				* CFrame.Angles(0, 0, roll)
			dropFootprint(np)
			-- heavy footfalls kick up dust shockwaves (more often the faster it runs)
			if now - lastStomp > 0.5 - frac * 0.22 then
				lastStomp = now
				stompRing(np - dir * 3)
			end
		end
		-- the scare (knockback + shake) only fires for the LOCAL player -- other kids get
		-- caught on their OWN client. It still LUNGES visibly at whoever it catches.
		-- measure horizontally so its tall body doesn't make the grab too tight.
		local horiz = ((hrp.Position - here) * Vector3.new(1, 0, 1)).Magnitude
		if horiz <= CATCH_RANGE then
			if targetPlayer == player then catchPlayer(hrp) else lungeAt(hrp) end
		end
		poseMonster()
		return
	end

	if state == "strollhome" then
		poseSwing = 0.5
		monBody.Size = BODY_BASE   -- calm back down to normal size
		local target = homePos or here
		local dir = (target - here) * Vector3.new(1, 0, 1)
		if dir.Magnitude <= 4 then
			state = "sleep"
		else
			dir = dir.Unit
			local np = here + dir * WANDER_SPEED * dt
			local y = groundY(np) + 8.5 + math.sin(now * 3) * 0.3
			local roll = math.sin(now * 6) * 0.08
			monBody.CFrame = CFrame.lookAt(Vector3.new(np.X, y, np.Z), Vector3.new(target.X, y, target.Z))
				* CFrame.Angles(0, 0, roll)
			dropFootprint(np)
		end
		-- re-aggro if anyone comes close again
		local near = pickTarget(false)
		if near then
			local hrp = hrpFor(near)
			if hrp and (hrp.Position - here).Magnitude <= AGGRO_RANGE * 0.7 then
				targetPlayer = near; state = "hunt"; chaseT = now; roar()
			end
		end
		poseMonster()
		return
	end
end)

-- mood label above its head reacts to what it's doing
task.spawn(function()
	while true do
		task.wait(0.15)
		if monTag then
			if state == "hunt" then
				monTag.Text = "\xF0\x9F\x8D\xAB GRRR!"; monTag.TextColor3 = Color3.fromRGB(255, 90, 60)
			elseif state == "stunned" then
				monTag.Text = "\xF0\x9F\x8D\xAB ...ow."; monTag.TextColor3 = Color3.fromRGB(200, 200, 210)
			elseif state == "sleep" then
				monTag.Text = "\xF0\x9F\x92\xA4"; monTag.TextColor3 = Color3.fromRGB(190, 165, 255)
			else
				monTag.Text = "\xF0\x9F\x8D\xAB Chocolate Monster"; monTag.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end
end)

-- drool + heat-steam only while it's actively hunting
task.spawn(function()
	while true do
		task.wait(0.12)
		if droolPE then droolPE.Enabled = (state == "hunt") end
		if steamMon then steamMon.Enabled = (state == "hunt") end
	end
end)

-- occasional blink (squash the eyes shut for a beat)
local EYE_SIZE = Vector3.new(1.4, 1.4, 0.7)
task.spawn(function()
	while true do
		task.wait(math.random(3, 6))
		if eyeL and eyeL.Parent and eyeR and eyeR.Parent and state ~= "stunned" then
			local shut = Vector3.new(EYE_SIZE.X, 0.14, EYE_SIZE.Z)
			TweenService:Create(eyeL, TweenInfo.new(0.07), { Size = shut }):Play()
			TweenService:Create(eyeR, TweenInfo.new(0.07), { Size = shut }):Play()
			task.wait(0.12)
			if eyeL and eyeL.Parent then TweenService:Create(eyeL, TweenInfo.new(0.07), { Size = EYE_SIZE }):Play() end
			if eyeR and eyeR.Parent then TweenService:Create(eyeR, TweenInfo.new(0.07), { Size = EYE_SIZE }):Play() end
		end
	end
end)

-- proximity camera shake -- the ground trembles as it bears down on YOU
RunService.RenderStepped:Connect(function()
	local hum = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	if not hum then return end
	local want = Vector3.zero
	if state == "hunt" and targetPlayer == player and monBody and monBody.Parent then
		local hrp = hrpOf()
		if hrp then
			local d = (hrp.Position - monBody.Position).Magnitude
			if d < 24 then
				local amt = (1 - d / 24) * 0.7
				local t = os.clock() * 40
				want = Vector3.new(math.sin(t) * amt, math.cos(t * 1.3) * amt, 0)
			end
		end
	end
	hum.CameraOffset = hum.CameraOffset:Lerp(want, 0.5)
end)

-- eye/edge warning while it hunts
task.spawn(function()
	while true do
		task.wait(0.1)
		warnEdge.Visible = (state == "hunt")
		-- the red edge-vignette only warns YOU when it's hunting YOU specifically
		if state == "hunt" and targetPlayer == player then
			local hrp = hrpOf()
			local close = hrp and monBody and (hrp.Position - monBody.Position).Magnitude or 999
			local danger = math.clamp(1 - close / AGGRO_RANGE, 0, 1)
			warnGui.Enabled = true
			wStroke.Transparency = 1 - danger * 0.55
		elseif state ~= "hunt" and warnGui.Enabled and wStroke.Transparency > 0.98 then
			-- leave the roar pulse alone; only hide when fully faded
		end
	end
end)

-- a spray of chocolate crumbs from the mouth as it chomps down on someone
local function chompBurst()
	if not (monBody and monBody.Parent) then return end
	local mp = mouthPos()
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2
		local crumb = mk({ Name = "Crumb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5),
			Color = (i % 2 == 0) and CHOC or CHOC_HI, Material = Enum.Material.SmoothPlastic })
		crumb.CFrame = CFrame.new(mp); crumb.Parent = Workspace
		local dir = Vector3.new(math.cos(a), 0.4, math.sin(a))
		TweenService:Create(crumb, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(mp + dir * 8 + Vector3.new(0, -3, 0)), Transparency = 1 }):Play()
		Debris:AddItem(crumb, 0.6)
	end
end

-- a quick camera thud for anyone standing near the monster when it gulps
local function gulpJolt()
	local hum = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	local hrp = hrpOf()
	if hum and hrp and monBody and monBody.Parent then
		local d = (hrp.Position - monBody.Position).Magnitude
		if d < 70 then
			local amt = (1 - d / 70) * 1.1
			hum.CameraOffset = Vector3.new((math.random() - 0.5) * amt * 2.2, (math.random() - 0.5) * amt * 2.2, 0)
		end
	end
end

-- when ANOTHER player is swallowed, our monster shows a squirming, named belly
-- bulge so it's obvious from the outside that someone's trapped in there.
local extTrapped = {}   -- [player] = true while they're inside
local function showExternalTrapped(who)
	if extTrapped[who] then return end
	extTrapped[who] = true
	chompBurst(); gulpJolt()   -- it visibly + physically chomps down
	task.spawn(function()
		local bulge = mk({ Name = "TrappedBulge", Shape = Enum.PartType.Ball, Size = Vector3.new(3.2, 3.2, 3.2),
			Color = Color3.fromRGB(96, 58, 28), Material = Enum.Material.SmoothPlastic, Reflectance = 0.14 })
		bulge.Parent = Workspace
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(210, 44); bb.StudsOffset = Vector3.new(0, 2.6, 0)
		bb.AlwaysOnTop = true; bb.MaxDistance = 200; bb.Adornee = bulge; bb.Parent = bulge
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBlack; lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(255, 235, 150); lbl.TextStrokeColor3 = Color3.fromRGB(30, 16, 8)
		lbl.TextStrokeTransparency = 0; lbl.Text = who.Name .. ": let me out!"; lbl.Parent = bb
		while extTrapped[who] and monBody and monBody.Parent do
			local t = os.clock()
			bulge.CFrame = monBody.CFrame * CFrame.new(math.sin(t * 5) * 3, math.cos(t * 4) * 2 - 1, 3.8)
			RunService.RenderStepped:Wait()
		end
		bulge:Destroy()
	end)
end

task.spawn(function()
	eatRemote = ReplicatedStorage:WaitForChild("MonsterEatEvent", 15)
	if eatRemote then
		eatRemote.OnClientEvent:Connect(function(who, eaten)
			if who == player or not who then return end   -- our own gulp is handled locally
			if eaten then showExternalTrapped(who) else extTrapped[who] = nil end
		end)
	end
end)
Players.PlayerRemoving:Connect(function(p) extTrapped[p] = nil end)

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	local isle = pollFor(function()
		local x = Workspace:FindFirstChild(ISLAND_NAME)
		if x then return x end
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("Model") and string.lower(d.Name):match("^island_?3$") then return d end
		end
		return nil
	end, 60)
	if isle then
		local ok, cf = pcall(function() return (select(1, isle:GetBoundingBox())) end)
		islandPos = (ok and cf) and cf.Position or nil
	end

	-- spawn point: the part you named "monsterspawn". POLL for it -- with StreamingEnabled
	-- island3's parts only arrive once you're near, so a one-shot scan (what missed it
	-- before) finds nothing and the monster spawns at the island centre by mistake.
	local spawnPart = pollFor(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("BasePart") and norm(d.Name) == SPAWN_NAME then
				if not islandPos or (d.Position - islandPos).Magnitude <= 1200 then return d end
			end
		end
		return nil
	end, 120)

	if spawnPart then
		homePos = spawnPart.Position
		-- the brick is only a marker -- hide it, no collision, not clickable
		spawnPart.Transparency = 1
		spawnPart.CanCollide = false
		spawnPart.CanQuery = false
	else
		homePos = islandPos
		warn("[ChocMonster] no 'monsterspawn' part found -- using island3 centre")
	end
	if not homePos then
		warn("[ChocMonster] island3 not found -- monster inactive")
		return
	end

	-- HIDDEN UNTIL YOU TALK TO THE NPC: the island-3 Candy NPC's quest (CookieRepairQuest) sets
	-- _G.cookieQuestStarted when you accept it. Hold here until then so the monster never appears
	-- (or hunts) before the player has met the NPC.
	while not _G.cookieQuestStarted do task.wait(0.5) end

	buildMonster(homePos)
	monBody.CFrame = CFrame.new(homePos.X, groundY(homePos) + 8.5, homePos.Z)
	poseMonster()
	-- big entrance ROAR the moment he appears
	task.delay(0.2, function() pcall(roar) end)
	print(("[ChocMonster] awake at %s (%.0f,%.0f,%.0f) -- hunts within %d studs"):format(
		spawnPart and "'monsterspawn'" or "island centre", homePos.X, homePos.Y, homePos.Z, AGGRO_RANGE))
end)
