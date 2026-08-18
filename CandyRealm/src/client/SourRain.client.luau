--======================================================================
-- SourRain.client.luau  --  what SOUR ACID RAIN looks like
--======================================================================
-- The server (SourRain.server.luau) owns the disaster: who is exposed, how fast they melt, when
-- it ends. This file owns nothing but the picture. It is told four things and draws each one:
--
--   "start"   -- rain everywhere, and the banner naming whoever paid for it
--   "shelter" -- true when a roof went over your head, false when it came off. The server sends
--                this ONLY when it changes, so the vignette never flickers.
--   "buyer"   -- you are the one who bought it: gold glow, no rain damage, a different banner
--   "stop"    -- clear everything, and say how many were caught
--
-- ===== THE RAIN FOLLOWS THE CAMERA =====
-- The realm is a 60,000-stud tower and the storm covers all of it. Filling that with particles is
-- absurd; one emitter riding 45 studs above the camera is indistinguishable from it, costs one
-- part, and works on an island nobody has streamed in yet. Nothing here is anchored to the world,
-- so it cannot be left behind when a player teleports mid-storm.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")
local Debris            = game:GetService("Debris")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local SOUR      = Color3.fromRGB(126, 214, 60)     -- the one green everything here uses
local SOUR_DARK = Color3.fromRGB( 74, 142,  34)

--======================================================================
-- THE SCREEN
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "SourRainGui"; gui.ResetOnSpawn = false; gui.DisplayOrder = 30
gui.IgnoreGuiInset = true; gui.Enabled = false; gui.Parent = PlayerGui

-- the vignette: a green wash that says "you are standing in it". Four edge bars rather than one
-- full-screen sheet, so the middle of the screen -- where you are trying to see a roof to run to
-- -- stays clear.
local edges = {}
for _, side in ipairs({ "T", "B", "L", "R" }) do
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0; f.BackgroundColor3 = SOUR; f.BackgroundTransparency = 0.35
	f.ZIndex = 2
	if side == "T" then f.Size = UDim2.new(1, 0, 0.18, 0); f.Position = UDim2.new(0, 0, 0, 0)
	elseif side == "B" then f.Size = UDim2.new(1, 0, 0.18, 0); f.Position = UDim2.new(0, 0, 0.82, 0)
	elseif side == "L" then f.Size = UDim2.new(0.14, 0, 1, 0); f.Position = UDim2.new(0, 0, 0, 0)
	else f.Size = UDim2.new(0.14, 0, 1, 0); f.Position = UDim2.new(0.86, 0, 0, 0) end
	local g = Instance.new("UIGradient")
	g.Rotation = (side == "T" and 90) or (side == "B" and 270) or (side == "L" and 0) or 180
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	f.Parent = gui
	edges[#edges + 1] = f
end

-- (named warnLabel, not warn: `warn` is Luau's own error-logging function and shadowing it in a
-- file that also wants to report problems is a trap for whoever edits this next)
local warnLabel = Instance.new("TextLabel")
warnLabel.AnchorPoint = Vector2.new(0.5, 0)
warnLabel.Position = UDim2.new(0.5, 0, 0.16, 0)
warnLabel.Size = UDim2.new(0, 520, 0, 46)
warnLabel.BackgroundTransparency = 1
warnLabel.Font = Enum.Font.FredokaOne
warnLabel.TextSize = 34
warnLabel.TextColor3 = Color3.new(1, 1, 1)
warnLabel.TextStrokeColor3 = SOUR_DARK
warnLabel.TextStrokeTransparency = 0
warnLabel.ZIndex = 3
warnLabel.Text = ""
warnLabel.Parent = gui

--======================================================================
-- THE RAIN
--======================================================================
local rainPart = Instance.new("Part")
rainPart.Name = "SourRainEmitter"
rainPart.Size = Vector3.new(90, 1, 90)
rainPart.Transparency = 1
rainPart.Anchored = true; rainPart.CanCollide = false; rainPart.CanQuery = false
rainPart.CanTouch = false; rainPart.CastShadow = false

local rain = Instance.new("ParticleEmitter")
rain.Texture = "rbxasset://textures/particles/sparkles_main.dds"
rain.Color = ColorSequence.new(SOUR, SOUR_DARK)
rain.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.35) })
rain.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.85, 0.35),
	NumberSequenceKeypoint.new(1, 1) })
rain.Lifetime = NumberRange.new(1.6, 2.4)
rain.Rate = 0                                   -- switched on for the storm only
rain.Speed = NumberRange.new(85, 110)           -- straight down and fast: this is rain, not snow
rain.SpreadAngle = Vector2.new(6, 6)
rain.Acceleration = Vector3.new(2, -60, 1)      -- a slight lean, so it is not a wall of lines
rain.EmissionDirection = Enum.NormalId.Bottom
rain.LightEmission = 0.35
rain.Parent = rainPart

-- STREAKS, NOT SPARKLES. Squash stretches a particle along its direction of travel, so the same
-- sprite reads as a falling line instead of a dot. Rain is the one effect where the shape of the
-- individual particle is the whole read -- dots at this speed look like static.
rain.Squash = NumberSequence.new(2.6)
rain.ZOffset = 0.2                              -- nudged toward the camera so drops sit in front of haze

local haze = rain:Clone()                       -- a slower, fatter layer for depth
haze.Texture = "rbxasset://textures/particles/smoke_main.dds"
haze.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 5) })
haze.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 1) })
haze.Lifetime = NumberRange.new(2, 3)
haze.Speed = NumberRange.new(25, 40)
haze.Rate = 0
haze.Squash = NumberSequence.new(0)             -- the haze is a cloud, not a streak
haze.Parent = rainPart

-- GROUND MIST: a thin layer of green fog sitting at ankle height, rising slowly. It is what makes
-- the rain look like it is LANDING on the world rather than passing through it, and it reads even
-- when you are looking straight ahead instead of up.
local mistPart = Instance.new("Part")
mistPart.Name = "SourRainMist"
mistPart.Size = Vector3.new(90, 1, 90)
mistPart.Transparency = 1
mistPart.Anchored = true; mistPart.CanCollide = false; mistPart.CanQuery = false
mistPart.CanTouch = false; mistPart.CastShadow = false

local mist = Instance.new("ParticleEmitter")
mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
mist.Color = ColorSequence.new(SOUR_DARK, SOUR)
mist.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
mist.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.88),
	NumberSequenceKeypoint.new(1, 1) })
mist.Lifetime = NumberRange.new(2.2, 3.4)
mist.Rate = 0
mist.Speed = NumberRange.new(1, 4)
mist.SpreadAngle = Vector2.new(180, 180)
mist.Acceleration = Vector3.new(0, 1.5, 0)      -- it lifts, like steam off something being eaten
mist.EmissionDirection = Enum.NormalId.Top
mist.LightEmission = 0.25
mist.Parent = mistPart

--======================================================================
-- THE SKY GOES GREEN
--======================================================================
-- IT RIDES ColorCorrection, NOT Lighting's OWN COLOURS. SkyByAltitude writes ClockTime, Brightness,
-- OutdoorAmbient AND the whole Atmosphere every single frame -- anything this script set on those
-- would be gone before it rendered. ColorCorrectionEffect is a separate post-process that nothing
-- else in the realm touches, so it is the one channel this can own outright.
--
-- Tint PLUS a saturation lift, not tint alone: a tint on its own drags the world toward one flat
-- hue, while pushing saturation with it makes the sky look chemical, which is the idea.
local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "SourRainTint"
cc.Enabled = false
cc.TintColor = Color3.new(1, 1, 1)
cc.Saturation = 0
cc.Contrast = 0
cc.Parent = game:GetService("Lighting")

local SOUR_TINT = Color3.fromRGB(150, 255, 120)
local ccTween
local function setSky(on)
	if ccTween then ccTween:Cancel(); ccTween = nil end
	if on then cc.Enabled = true end
	local goal = on
		and { TintColor = SOUR_TINT, Saturation = 0.45, Contrast = 0.12 }
		or  { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 }
	-- eased over 1.6s: the sky SOURING is the tell that something is coming, and a hard cut to
	-- green reads as a bug rather than as weather
	ccTween = TweenService:Create(cc, TweenInfo.new(1.6, Enum.EasingStyle.Quad), goal)
	ccTween:Play()
	if not on then
		task.delay(1.7, function()
			if cc.Saturation == 0 then cc.Enabled = false end   -- off entirely once it has faded out
		end)
	end
end

--======================================================================
-- STATE
--======================================================================
local active, exposed, isBuyer = false, false, false
local conn

-- ===== SPLASHES =====
-- Rain that passes through the world is a screen effect; rain that BREAKS on it is weather. Every
-- tick this fires a handful of downward rays from random points around you and pops a splash on
-- whatever they hit -- ground, a roof, a crate, a passing NPC. Nothing has to be tagged first.
--
-- Rays, not touch events: a particle cannot tell you what it landed on, and CanTouch drops would
-- mean thousands of collision queries a second. Six rays a tick is a rounding error next to that,
-- and it puts the splash ON the surface at the right angle instead of at a guessed height.
local SPLASH_PER_TICK = 6
local SPLASH_RADIUS   = 46
local splashParams = RaycastParams.new()
splashParams.FilterType = Enum.RaycastFilterType.Exclude
splashParams.IgnoreWater = true

local function splashAt(pos, normal)
	-- the ring: a flat disc that snaps open and fades, laid ON the surface using its normal, so it
	-- sits flush on a slope or the side of a crate instead of hovering level in the air
	local ring = Instance.new("Part")
	ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CanTouch = false
	ring.CastShadow = false; ring.Material = Enum.Material.Neon; ring.Color = SOUR
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.4, 0.05, 0.4)
	ring.CFrame = CFrame.lookAlong(pos + normal * 0.06, normal) * CFrame.Angles(math.rad(90), 0, 0)
	ring.Parent = Workspace
	TweenService:Create(ring, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(2.6, 0.05, 2.6), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.4)

	-- and two specks kicking back off it, so a splash has some height and is not just a decal
	for _ = 1, 2 do
		local d = Instance.new("Part")
		d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
		d.CastShadow = false; d.Material = Enum.Material.Neon; d.Color = SOUR
		d.Shape = Enum.PartType.Ball
		d.Size = Vector3.new(0.22, 0.22, 0.22)
		d.CFrame = CFrame.new(pos + normal * 0.2)
		d.Parent = Workspace
		local away = normal * 1.6 + Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2)
		TweenService:Create(d, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(pos + away), Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 }):Play()
		Debris:AddItem(d, 0.4)
	end
end

local splashClock = 0
local function stepSplashes(dt)
	splashClock += dt
	if splashClock < 0.07 then return end
	splashClock = 0
	local cam = Workspace.CurrentCamera
	if not cam then return end
	splashParams.FilterDescendantsInstances = { player.Character, rainPart, mistPart }
	local origin = cam.CFrame.Position
	for _ = 1, SPLASH_PER_TICK do
		local a = math.random() * math.pi * 2
		-- sqrt keeps the spread EVEN over the disc; without it every splash clumps at your feet
		local r = SPLASH_RADIUS * math.sqrt(math.random())
		local from = origin + Vector3.new(math.cos(a) * r, 30, math.sin(a) * r)
		local hit = Workspace:Raycast(from, Vector3.new(0, -110, 0), splashParams)
		if hit then splashAt(hit.Position, hit.Normal) end
	end
end

local function setRain(on)
	rain.Rate = on and 260 or 0
	haze.Rate = on and 26 or 0
	mist.Rate = on and 14 or 0
	setSky(on)
	if on then
		rainPart.Parent = Workspace
		mistPart.Parent = Workspace
		if not conn then
			-- RenderStepped, not Heartbeat: it rides the camera, and a frame of lag between the
			-- camera moving and the rain following it is a frame of rain visibly sliding sideways
			conn = RunService.RenderStepped:Connect(function(dt)
				local cam = Workspace.CurrentCamera
				if cam then
					rainPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 45, 0))
					mistPart.CFrame = CFrame.new(cam.CFrame.Position - Vector3.new(0, 6, 0))
				end
				stepSplashes(dt)
			end)
		end
	else
		if conn then conn:Disconnect(); conn = nil end
		rainPart.Parent = nil
		mistPart.Parent = nil
	end
end

-- the pulsing tweens are kept and cancelled rather than fired and forgotten: they repeat forever
-- (-1), and ducking in and out of a doorway three times would otherwise leave three of them
-- running on the same property, fighting each other for the rest of the session
local pulses = {}
local function setExposed(on)
	exposed = on
	gui.Enabled = active and on
	for _, t in ipairs(pulses) do t:Cancel() end
	table.clear(pulses)
	if on then
		warnLabel.Text = "\xE2\x98\xA0 GET UNDER COVER!"
		for _, f in ipairs(edges) do
			f.BackgroundTransparency = 0.35
			local t = TweenService:Create(f, TweenInfo.new(0.7, Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.6 })
			t:Play()
			pulses[#pulses + 1] = t
		end
	end
end

local function banner(text, colour, seconds)
	local NC = _G.NotifyCenter
	if NC and NC.push then
		pcall(function()
			NC.push({ text = text, color = colour,
				priority = (NC.PRIORITY and NC.PRIORITY.EVENT) or 80, duration = seconds or 5 })
		end)
	elseif _G.showHudBanner then
		pcall(_G.showHudBanner, text, colour, seconds or 5)
	end
end

--======================================================================
-- THE FOUR MESSAGES
--======================================================================
task.spawn(function()
	local ev = ReplicatedStorage:FindFirstChild("SourRainEvent")
		or ReplicatedStorage:WaitForChild("SourRainEvent", 30)
	if not ev then
		warnLabel.Text = ""      -- (nothing to draw; the server script is not in this place)
		print("[SourRain] no SourRainEvent -- is SourRain.server.luau synced into ServerScriptService?")
		return
	end

	ev.OnClientEvent:Connect(function(kind, a, b)
		if kind == "start" then
			active, isBuyer = true, false
			setRain(true)
			setExposed(false)                       -- the server tells us within a quarter second
			banner(("\xE2\x98\xA0 SOUR RAIN -- %s soured the sky! GET INDOORS!"):format(tostring(a)),
				SOUR, 6)

		elseif kind == "buyer" then
			isBuyer = true
			gui.Enabled = false                     -- immune: no vignette, no countdown, ever
			banner("\xE2\x98\xA0 You soured the whole realm. Watch them melt.",
				Color3.fromRGB(255, 214, 90), 6)

		elseif kind == "shelter" then
			if isBuyer then return end
			setExposed(not a)                       -- a == sheltered

		elseif kind == "stop" then
			active, exposed = false, false
			setRain(false)
			gui.Enabled = false
			local n = tonumber(b) or 0
			banner(n > 0
				and ("\xE2\x98\xA0 The rain passed -- %d melted."):format(n)
				or "\xE2\x98\xA0 The rain passed. Everyone made it inside.", SOUR_DARK, 5)
		end
	end)
	print("[SourRain] client ready -- green sky (ColorCorrection), streaked rain + ground mist, "
		.. "raycast splashes on whatever it lands on, vignette and melting warning")
end)

--======================================================================
-- THE MELTING COUNTDOWN
--======================================================================
-- Read off YOUR OWN humanoid rather than sent down from the server: the number wants to be
-- frame-accurate and it is derived from health, which the client already has. It says how long
-- you have at the rate you are currently losing it, which is the only number worth showing.
RunService.RenderStepped:Connect(function()
	if not (active and exposed) then return end
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if not (hum and hum.Health > 0) then return end
	local secs = math.max(0, hum.Health / 17)       -- DPS in SourRain.server.luau
	warnLabel.Text = ("\xE2\x98\xA0 MELTING -- %.1fs  |  GET UNDER COVER!"):format(secs)
end)
