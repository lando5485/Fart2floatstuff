--======================================================================
-- Blizzard.client.luau  (StarterPlayerScripts)  -- CandyRealm
--======================================================================
-- POWDERED SUGAR BLIZZARD -- the cold front that shuts the realm down for a minute.
--
--   * VISIBILITY collapses, and it does it FAST -- full force ten seconds after the first flake.
--     Fog closes to 95 studs and a white sheet comes over the screen, so the island you were flying
--     to stops existing and you have to fly the one you can still see.
--   * POWDERED SUGAR blows HORIZONTALLY, in three layers: a sheet across the middle distance, huge
--     smears whipping past your face, and drift scoured off the ground. Not falling snow -- all of it
--     going sideways at speed, which is the single thing that separates a blizzard from weather.
--     Every layer surges on one shared gust value, so a gust is one event you see, feel and get
--     shoved by at the same instant.
--   * WIND PUSHES you. A real force on the character, gusting, so holding a line costs you.
--   * EXPOSURE COSTS YOU. Out in it, you get slower on the ground and weaker in the air, and it
--     gets worse the longer you stay out. Duck under any roof and it stops and recovers.
--
-- ===== SHELTER IS THE SERVER'S CALL, NOT MINE =====
-- Whether you are under cover is decided by SourRain.server.luau's exact test, run by BigEvents:
-- one 30-stud ray straight up, ignoring every character. That number is load-bearing and is
-- explained over there -- longer and the top island reads as indoors and the whole event does
-- nothing to anybody. Reimplementing the check on the client would mean two answers to the same
-- question and a player melting under a roof because their ray disagreed with the server's.
--
-- ===== IT OWNS FOG, AND NOTHING ELSE OWNS FOG =====
-- SkyByAltitude deliberately does not touch fog, and says so, for exactly this reason: two systems
-- writing FogEnd every frame would fight. EventClient's thunderstorm does drive fog -- so this
-- event and that one must never run at once, which is why BigEvents runs one set piece at a time.
-- The pre-storm values are captured on start and put back on stop, whatever else happened.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local SUGAR      = Color3.fromRGB(252, 250, 255)
local SUGAR_DIM  = Color3.fromRGB(206, 214, 232)

-- ===== TUNING =====
-- ===== THE BUILD =====
-- Full force in TEN SECONDS from the first flake. Weather that creeps in over a minute reads as a
-- graphics setting changing; weather that lands on you reads as an event. Everything visual rides
-- one `intensity` value on this curve -- fog, screen haze, particle rate, edge wash -- so they can
-- never disagree about how bad it is.
local BUILD_SECS     = 10
local FOG_END        = 95      -- studs at full force. Near-whiteout: you can see the ground you are
                               -- stood on and roughly one building, and nothing else.
local FOG_START      = 8
local HAZE_MIN       = 0.42    -- the full-screen sheet at full force. NOT opaque, on purpose: at 0 you
                               -- cannot find a roof, which turns a hazard into a death sentence.
local WIND_FORCE     = 42      -- studs/s^2 of shove at full strength
local GUST_PERIOD    = 3.4     -- seconds per gust cycle; the wind swells and drops rather than blowing flat
local EXPOSURE_RAMP  = 22      -- seconds out in it to reach the full penalty
local MAX_SLOW       = 0.45    -- worst case: you keep 45% of your speed, never zero -- being unable to move is
                               -- not a hazard, it is a softlock with weather on top

--======================================================================
-- THE SCREEN
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "BlizzardGui"; gui.ResetOnSpawn = false; gui.DisplayOrder = 29
gui.IgnoreGuiInset = true; gui.Enabled = false; gui.Parent = PlayerGui

-- a white wash at the edges: the same four-bar shape SourRain uses, for the same reason -- the
-- middle of the screen is where you are trying to find a roof, so it stays clear
local edges = {}
for _, side in ipairs({ "T", "B", "L", "R" }) do
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0; f.BackgroundColor3 = SUGAR; f.BackgroundTransparency = 0.55
	if side == "T" then f.Size = UDim2.new(1, 0, 0, 150); f.Position = UDim2.new(0, 0, 0, 0)
	elseif side == "B" then f.Size = UDim2.new(1, 0, 0, 150); f.Position = UDim2.new(0, 0, 1, -150)
	elseif side == "L" then f.Size = UDim2.new(0, 190, 1, 0); f.Position = UDim2.new(0, 0, 0, 0)
	else f.Size = UDim2.new(0, 190, 1, 0); f.Position = UDim2.new(1, -190, 0, 0) end
	f.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = (side == "T" and 90) or (side == "B" and 270) or (side == "L" and 0) or 180
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	edges[#edges + 1] = f
end

-- THE SHEET. The edge bars alone keep the middle of the screen clear, which is right for sour rain
-- (you need to see where you are running) but wrong for a blizzard -- the whole point is that you
-- CANNOT see. So a full-screen wash goes over them, and the bars stay to darken the corners further.
local haze = Instance.new("Frame")
haze.Name = "Whiteout"
haze.Size = UDim2.new(1, 0, 1, 0)
haze.BackgroundColor3 = SUGAR
haze.BackgroundTransparency = 1
haze.BorderSizePixel = 0
haze.ZIndex = 2
haze.Parent = gui

local warnLabel = Instance.new("TextLabel")
warnLabel.BackgroundTransparency = 1
warnLabel.AnchorPoint = Vector2.new(0.5, 0); warnLabel.Position = UDim2.new(0.5, 0, 0, 180)
warnLabel.Size = UDim2.new(1, -80, 0, 34)
warnLabel.Font = Enum.Font.FredokaOne; warnLabel.TextScaled = true
warnLabel.TextColor3 = Color3.fromRGB(60, 74, 104); warnLabel.Text = ""
warnLabel.ZIndex = 3
warnLabel.Parent = gui
do local st = Instance.new("UIStroke"); st.Color = Color3.new(1, 1, 1); st.Thickness = 3; st.Parent = warnLabel end

--======================================================================
-- THE SUGAR
--======================================================================
-- HORIZONTAL, and that is the whole effect. EmissionDirection Front with a huge Speed and almost
-- no Acceleration means it crosses your view rather than falling through it; Squash stretches each
-- flake along that travel so it reads as a streak of powder, not a snowflake. Falling snow already
-- exists in this realm (ColdIsland) and reads as pretty -- this has to read as hostile.
local sugarPart = Instance.new("Part")
sugarPart.Name = "BlizzardEmitter"
sugarPart.Size = Vector3.new(120, 120, 1)
sugarPart.Transparency = 1
sugarPart.Anchored = true; sugarPart.CanCollide = false; sugarPart.CanQuery = false
sugarPart.CanTouch = false; sugarPart.CastShadow = false

local sugar = Instance.new("ParticleEmitter")
sugar.Texture = "rbxasset://textures/particles/smoke_main.dds"
sugar.Color = ColorSequence.new(SUGAR, SUGAR_DIM)
sugar.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.2) })
sugar.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.12, 0.35),
	NumberSequenceKeypoint.new(0.85, 0.45), NumberSequenceKeypoint.new(1, 1) })
sugar.Lifetime = NumberRange.new(1.1, 1.8)
sugar.Rate = 0
sugar.Speed = NumberRange.new(180, 250)          -- fast enough to streak past, not drift
sugar.SpreadAngle = Vector2.new(14, 14)
sugar.Acceleration = Vector3.new(0, -6, 0)       -- barely any: gravity would turn this back into snow
sugar.EmissionDirection = Enum.NormalId.Front
sugar.Squash = NumberSequence.new(3.2)
sugar.LightEmission = 0.6
sugar.Parent = sugarPart

-- THE NEAR LAYER. The sheet above is the storm at distance; this is the powder going past your FACE
-- -- fewer particles, much bigger, much closer, and far more transparent so it smears across the view
-- instead of blocking it. Two layers at different depths is what stops a blizzard reading as a flat
-- texture pasted on the camera: the near one moves fast against the far one, and that parallax is the
-- whole sensation of being inside it.
local nearPart = Instance.new("Part")
nearPart.Name = "BlizzardNear"
nearPart.Size = Vector3.new(40, 40, 1)
nearPart.Transparency = 1
nearPart.Anchored = true; nearPart.CanCollide = false; nearPart.CanQuery = false
nearPart.CanTouch = false; nearPart.CastShadow = false

local nearSugar = sugar:Clone()
nearSugar.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 3.5), NumberSequenceKeypoint.new(1, 7) })
nearSugar.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.72),
	NumberSequenceKeypoint.new(0.8, 0.8), NumberSequenceKeypoint.new(1, 1) })
nearSugar.Lifetime = NumberRange.new(0.5, 0.9)
nearSugar.Speed = NumberRange.new(260, 340)     -- faster than the far layer: that difference IS the parallax
nearSugar.Squash = NumberSequence.new(5)        -- long smears at this range
nearSugar.SpreadAngle = Vector2.new(30, 30)
nearSugar.Rate = 0
nearSugar.Parent = nearPart

-- GROUND DRIFT. Powder picked up off the surface and thrown along it -- the layer that says the storm
-- is scouring the island rather than just falling on it. Emitted upward from underfoot so it curls.
local driftPart = Instance.new("Part")
driftPart.Name = "BlizzardDrift"
driftPart.Size = Vector3.new(80, 1, 80)
driftPart.Transparency = 1
driftPart.Anchored = true; driftPart.CanCollide = false; driftPart.CanQuery = false
driftPart.CanTouch = false; driftPart.CastShadow = false

local drift = Instance.new("ParticleEmitter")
drift.Texture = "rbxasset://textures/particles/smoke_main.dds"
drift.Color = ColorSequence.new(SUGAR, SUGAR_DIM)
drift.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 14) })
drift.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.78),
	NumberSequenceKeypoint.new(1, 1) })
drift.Lifetime = NumberRange.new(1.4, 2.2)
drift.Rate = 0
drift.Speed = NumberRange.new(60, 110)
drift.SpreadAngle = Vector2.new(60, 60)
drift.Acceleration = Vector3.new(0, 8, 0)       -- it lifts off the ground as it travels
drift.EmissionDirection = Enum.NormalId.Top
drift.LightEmission = 0.5
drift.Parent = driftPart

--======================================================================
-- STATE
--======================================================================
local active, sheltered = false, true
-- TWO SEPARATE CURVES, and keeping them apart is the whole feel of the event:
--   intensity -- how hard it is BLOWING. 0->1 over 10s, the same for everybody, shelter or not.
--                A blizzard does not get milder because you found a door.
--   exposure  -- how much it has WORN YOU DOWN. Slower (22s), and it recovers under a roof.
-- Merging them would mean stepping inside instantly clears the sky, or that the penalty arrives as
-- fast as the visuals. Both are wrong.
local intensity = 0
local exposure = 0          -- 0..1, how long you have been out in it
local conn, windDir, savedFog
local hum, hrpForce

local function setForce(on)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if on then
		if not (hrpForce and hrpForce.Parent) then
			-- VectorForce on the root, not a velocity write: writing AssemblyLinearVelocity every
			-- frame fights the flight system for the same property and one of them wins at random.
			-- A force ADDS to whatever you are already doing, which is what wind is.
			local att = hrp:FindFirstChild("RootAttachment") or Instance.new("Attachment", hrp)
			hrpForce = Instance.new("VectorForce")
			hrpForce.Name = "BlizzardWind"
			hrpForce.Attachment0 = att
			hrpForce.RelativeTo = Enum.ActuatorRelativeTo.World
			hrpForce.ApplyAtCenterOfMass = true
			hrpForce.Force = Vector3.zero
			hrpForce.Parent = hrp
		end
	elseif hrpForce then
		hrpForce:Destroy(); hrpForce = nil
	end
end

local function setBlizzard(on)
	if on == active then return end
	active = on
	gui.Enabled = on
	sugar.Rate = on and 900 or 0

	if on then
		savedFog = { s = Lighting.FogStart, e = Lighting.FogEnd, c = Lighting.FogColor }
		-- fog is driven per-frame off `intensity` below, NOT tweened here: a tween would race the
		-- build curve and the two would disagree about how thick the air is
		Lighting.FogColor = SUGAR_DIM
		intensity = 0
		sugarPart.Parent = Workspace
		nearPart.Parent = Workspace
		driftPart.Parent = Workspace
		-- one wind direction for the whole event, horizontal: a blizzard comes FROM somewhere, and
		-- a direction that rerolls every gust reads as random shoving rather than as weather
		local a = math.random() * math.pi * 2
		windDir = Vector3.new(math.cos(a), 0, math.sin(a))
		exposure = 0
		setForce(true)

		if not conn then
			conn = RunService.RenderStepped:Connect(function(dt)
				-- ONE GUST VALUE FOR EVERYTHING. The wind force, all three particle layers and the
				-- screen wash surge off the SAME number, so a gust is a single event you see, feel and
				-- get shoved by at once. Driving them from separate clocks is what makes weather look
				-- like three unrelated effects running near each other.
				--
				-- Two sine waves at different periods rather than one: a single sine is a metronome and
				-- you start predicting it within about fifteen seconds. Beating them together gives
				-- gusts that arrive at uneven intervals without ever being random enough to feel unfair.
				local t = os.clock()
				local gust = 0.55
					+ 0.30 * math.sin(t * (math.pi * 2 / GUST_PERIOD))
					+ 0.15 * math.sin(t * (math.pi * 2 / (GUST_PERIOD * 0.37)))

				local cam = Workspace.CurrentCamera
				if cam then
					-- the emitters sit upwind of you and face downwind, so the sugar crosses your view
					-- no matter which way you turn. The near layer wanders a few studs off the wind
					-- line each gust, so the powder is not a rigid tube pointing at your face.
					local wobble = Vector3.new(math.sin(t * 1.7) * 0.25, 0, math.cos(t * 2.3) * 0.25)
					local gustDir = (windDir + wobble).Unit
					local at = cam.CFrame.Position - gustDir * 55 + Vector3.new(0, 8, 0)
					sugarPart.CFrame = CFrame.lookAt(at, at + gustDir)
					local nearAt = cam.CFrame.Position - gustDir * 14 + Vector3.new(0, 2, 0)
					nearPart.CFrame = CFrame.lookAt(nearAt, nearAt + gustDir)
					driftPart.CFrame = CFrame.new(cam.CFrame.Position - Vector3.new(0, 9, 0))
				end

				-- THE BUILD: 0 -> 1 in BUILD_SECS, then held. Eased so the first second is a gust and
				-- the last is the sky closing, rather than a linear fade that reads as a slider.
				intensity = math.min(1, intensity + dt / BUILD_SECS)
				local i = intensity * intensity * (3 - 2 * intensity)   -- smoothstep

				-- FOG. From wherever the sky was to near-whiteout, every frame, so it tracks the build.
				local baseEnd = (savedFog and savedFog.e) or 100000
				local baseStart = (savedFog and savedFog.s) or 0
				Lighting.FogEnd   = baseEnd + (FOG_END - baseEnd) * i
				Lighting.FogStart = baseStart + (FOG_START - baseStart) * i

				-- THE SHEET. Under a roof it thins by two thirds -- you are still in a blizzard and the
				-- sky is still gone, but you can see well enough to be somewhere. That contrast is what
				-- makes a doorway feel like safety instead of a stat change.
				local shelterEase = sheltered and 0.34 or 1
				-- the sheet BREATHES with the gust (a fifth of its strength), so a hard gust visibly
				-- takes the last of your visibility with it rather than just pushing you
				haze.BackgroundTransparency = 1 - (1 - HAZE_MIN) * i * shelterEase * (0.8 + 0.2 * gust)
				local flow = i * (sheltered and 0.25 or 1) * gust
				sugar.Rate     = 1600 * flow
				nearSugar.Rate = 90 * flow      -- few, but they are enormous and right on the lens
				drift.Rate     = 260 * flow

				-- exposure builds while you are out in it and RECOVERS twice as fast under a roof:
				-- shelter has to feel like relief, not merely like a pause
				local target = sheltered and -2 or 1
				exposure = math.clamp(exposure + (dt / EXPOSURE_RAMP) * target, 0, 1)

				local char = player.Character
				hum = char and char:FindFirstChildWhichIsA("Humanoid")
				if hum then
					-- 16 is Roblox's default walk speed; scaling off the LIVE value would compound
					-- every frame and creep the player to a standstill
					hum.WalkSpeed = 16 * (1 - (1 - MAX_SLOW) * exposure)
				end
				-- the flight engine reads this every frame (PropelSystem:190)
				_G.serverEventSpeedMult = 1 - (1 - MAX_SLOW) * exposure

				if hrpForce and hrpForce.Parent then
					-- the same gust the sugar is riding, scaled by the build: the shove arrives with
					-- the powder that visibly caused it, and both grow over the first ten seconds
					local mass = (hrpForce.Attachment0 and hrpForce.Attachment0.Parent
						and hrpForce.Attachment0.Parent.AssemblyMass) or 1
					hrpForce.Force = sheltered and Vector3.zero
						or (windDir * WIND_FORCE * gust * i * mass)
				end

				warnLabel.Text = sheltered and ""
					or ("\u{2744} POWDERED SUGAR BLIZZARD -- %d%% slowed. GET UNDER COVER!")
						:format(math.floor((1 - MAX_SLOW) * exposure * 100))
				for _, f in ipairs(edges) do
					f.BackgroundTransparency = 1 - 0.55 * i * shelterEase
				end
			end)
		end
	else
		if conn then conn:Disconnect(); conn = nil end
		sugarPart.Parent = nil
		nearPart.Parent = nil
		driftPart.Parent = nil
		nearSugar.Rate, drift.Rate = 0, 0
		setForce(false)
		intensity, exposure = 0, 0
		haze.BackgroundTransparency = 1
		for _, f in ipairs(edges) do f.BackgroundTransparency = 1 end
		_G.serverEventSpeedMult = 1                    -- hand the flight engine back its speed
		if hum then hum.WalkSpeed = 16 end
		if savedFog then
			TweenService:Create(Lighting, TweenInfo.new(3), {
				FogStart = savedFog.s, FogEnd = savedFog.e, FogColor = savedFog.c }):Play()
			savedFog = nil
		end
	end
end

-- A blizzard that survives its own event is a realm nobody can play. Respawning mid-storm rebuilds
-- the character, so the force has to be re-attached to the NEW root rather than mourned on the old.
player.CharacterAdded:Connect(function()
	task.wait(0.4)
	if active then setForce(true) end
end)


--======================================================================
-- /sugarblizzard  --  run it on demand
--======================================================================
-- Same reason /thunderstorm exists: BigEvents puts this on a 600s rotation, which is the right
-- pacing to play against and the wrong pacing to tune fog, gust strength or the exposure ramp.
--
-- NOT named /blizzard -- SummitBellQuest already owns that one for island4's whiteout, and two
-- handlers on the same string would both fire and fight over the screen.
--
-- ⚠ LOCAL REHEARSAL ONLY. It cannot broadcast, so it cannot force weather on a live server. The
-- shelter test below is the client's own copy, used ONLY here: during the real event the server is
-- the single authority and this loop never runs. That is deliberate -- one answer in production,
-- and a way to see the mechanic solo.
do
	local TextChatService = game:GetService("TextChatService")

	local testRay = RaycastParams.new()
	testRay.FilterType = Enum.RaycastFilterType.Exclude

	local function runLocal(secs)
		sheltered = false
		setBlizzard(true)
		local endAt = os.clock() + secs
		task.spawn(function()
			while os.clock() < endAt and active do
				local char = player.Character
				testRay.FilterDescendantsInstances = { char }
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				sheltered = hrp and Workspace:Raycast(hrp.Position + Vector3.new(0, 2, 0),
					Vector3.new(0, 30, 0), testRay) ~= nil or false
				task.wait(0.25)
			end
			setBlizzard(false)
		end)
	end

	local function onCmd(msg)
		local m = tostring(msg or ""):lower():gsub("^%s+", "")
		if m:sub(1, 14) == "/sugarblizzard" then
			local secs = tonumber(m:match("(%d+)")) or 75
			print(("[Blizzard] /sugarblizzard -- running locally for %ds (walk under a roof to see it stop)")
				:format(secs))
			runLocal(secs)
		elseif m:sub(1, 12) == "/blizzardend" then
			print("[Blizzard] /blizzardend -- stopped")
			setBlizzard(false)
		end
	end

	pcall(function()
		TextChatService.MessageReceived:Connect(function(m)
			if m.TextSource and m.TextSource.UserId == player.UserId then onCmd(m.Text) end
		end)
	end)
	pcall(function() player.Chatted:Connect(onCmd) end)
end

--======================================================================
-- THE WIRE
--======================================================================
task.spawn(function()
	local ev = ReplicatedStorage:FindFirstChild("BlizzardSync")
		or ReplicatedStorage:WaitForChild("BlizzardSync", 30)
	if not ev then
		print("[Blizzard] no BlizzardSync -- is BigEvents.server.lua synced into ServerScriptService?")
		return
	end
	ev.OnClientEvent:Connect(function(kind, a)
		if kind == "start" then
			sheltered = false
			setBlizzard(true)
		elseif kind == "shelter" then
			sheltered = (a == true)
		elseif kind == "stop" then
			setBlizzard(false)
		end
	end)
	print("[Blizzard] client ready -- horizontal sugar, fog-out, gusting wind, exposure slow, shelter relief")
end)
