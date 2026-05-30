--======================================================================
-- MutationEffects.lua  (ModuleScript)
--======================================================================
-- World VISUALS for the global "MutationEvent" (SERVER-authoritative; all
-- parts replicate so every client sees the same mutated world).
--
-- Responsibilities:
--   * GLOBAL VFX: toxic green/purple fog hubs that rise BETWEEN islands,
--     drifting radiation spores, glowing cracks, toxic smoke, electrical
--     surge flashes, and an occasional sky "glitch" pulse (client-side).
--   * WORLD MUTATIONS (VISUAL ONLY): giant glowing bean growths, pulsing
--     crystals, floating rocks, toxic slime puddles, giant eyeballs opening
--     in terrain, weird plants. All CanCollide=false — never change island
--     collision/shape, never block movement or shops.
--   * RADIOACTIVE STORMS: random green lightning striking islands + toxic
--     shockwaves. The manager (not this module) decides who is nearby and
--     messages those clients a STRONGER mutation; this module just makes the
--     visual strike + shockwave and returns the strike position.
--
-- ★ HARD RULES ★
--   * EVERY part created here is CanCollide=false (+ CanQuery=false /
--     CanTouch=false). It must NOT change island collision/shape, block
--     movement, or block shop access. World mutations float at/around the
--     surface and never replace island geometry.
--   * PERFORMANCE: a HARD running cap of CONFIG.MAX_WORLD_MUTATIONS
--     simultaneous world-mutation parts; every emitter Rate clamped to
--     CONFIG.MAX_PARTICLE_RATE.
--   * NEVER touches the fart meter / power / flight / coins / food / guts.
--   * cleanup() destroys EVERYTHING + releases every connection (no leaks).
--======================================================================

local MutationEffects = {}

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- Wired by init().
local CONFIG = nil
local MutationSync = nil

-- State.
local worldFolder = nil       -- holds all world-mutation + fog/VFX parts
local stormFolder = nil       -- holds transient storm bolts/shockwaves
local worldCount = 0          -- live count toward MAX_WORLD_MUTATIONS
local fadeParts = {}          -- parts faded out during ENDING
local activeConns = {}        -- Heartbeat connections (floating rocks etc.) to release

--------------------------------------------------------------------
-- init(config, syncEvent): wire shared dependencies.
--------------------------------------------------------------------
function MutationEffects.init(config, syncEvent)
	CONFIG = config
	MutationSync = syncEvent
end

--------------------------------------------------------------------
-- Folder helpers.
--------------------------------------------------------------------
local function ensureWorldFolder()
	if not worldFolder or not worldFolder.Parent then
		worldFolder = Instance.new("Folder")
		worldFolder.Name = "MutationWorldVFX"
		worldFolder.Parent = workspace
	end
	return worldFolder
end

local function ensureStormFolder()
	if not stormFolder or not stormFolder.Parent then
		stormFolder = Instance.new("Folder")
		stormFolder.Name = "MutationStorms"
		stormFolder.Parent = workspace
	end
	return stormFolder
end

--------------------------------------------------------------------
-- canSpawn(n): central PERFORMANCE guard for world-mutation parts.
--------------------------------------------------------------------
local function canSpawn(n)
	return (worldCount + (n or 1)) <= CONFIG.MAX_WORLD_MUTATIONS
end

--------------------------------------------------------------------
-- newPart(props): create + register one CanCollide=false world part.
-- Centralizes the safety flags, the cap accounting + the fade list.
-- Returns the part, or nil if the cap is hit.
--------------------------------------------------------------------
local function newPart(props)
	if not canSpawn(1) then return nil end
	local p = Instance.new("Part")
	p.Name = props.Name or "Mutation"
	p.Material = props.Material or Enum.Material.Neon
	p.Color = props.Color or Color3.fromRGB(120, 255, 120)
	p.Transparency = props.Transparency or 0.2
	p.Size = props.Size or Vector3.new(2, 2, 2)
	p.Anchored = true
	-- ★ VISUAL ONLY: never collide / never block / never change island shape ★
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if props.Shape then p.Shape = props.Shape end
	if props.Reflectance then p.Reflectance = props.Reflectance end
	p.CFrame = props.CFrame or CFrame.new()
	p.Parent = props.Parent or ensureWorldFolder()
	worldCount = worldCount + 1
	table.insert(fadeParts, p)
	return p
end

--------------------------------------------------------------------
-- makeEmitter(parent, props): capped emitter helper. Rate is ALWAYS clamped
-- to CONFIG.MAX_PARTICLE_RATE (the #1 lag guard).
--------------------------------------------------------------------
local function makeEmitter(parent, props)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = props.Texture or "rbxasset://textures/particles/sparkles_main.dds"
	pe.Rate = math.min(props.Rate or 8, CONFIG.MAX_PARTICLE_RATE)
	pe.Lifetime = props.Lifetime or NumberRange.new(1, 2)
	pe.Speed = props.Speed or NumberRange.new(1, 3)
	pe.SpreadAngle = props.SpreadAngle or Vector2.new(30, 30)
	pe.Size = props.Size or NumberSequence.new(0.6)
	pe.Transparency = props.Transparency or NumberSequence.new(0.3)
	pe.Color = props.Color or ColorSequence.new(Color3.fromRGB(120, 255, 120))
	pe.LightEmission = props.LightEmission or 0.4
	pe.Acceleration = props.Acceleration or Vector3.new(0, 1, 0)
	pe.Enabled = props.Enabled ~= false
	pe.Parent = parent
	return pe
end

-- toxicColor(): pick a toxic green or purple tint at random (event palette).
local function toxicColor()
	if math.random() < 0.5 then
		return Color3.fromRGB(120, 255, 120) -- neon green
	end
	return Color3.fromRGB(170, 90, 255)      -- toxic purple
end

--======================================================================
-- startFog(targets): WARNING -> green/purple fog rises BETWEEN islands +
-- toxic spores drift. We place a few fog hubs at the vertical midpoints
-- between consecutive island targets. Cheap; capped.
--======================================================================
function MutationEffects.startFog(targets)
	ensureWorldFolder()
	if not targets or #targets == 0 then return end
	for i = 1, #targets do
		local a = targets[i]
		local b = targets[i + 1] or targets[i]
		local mid = a.position:Lerp(b.position, 0.5) + Vector3.new(0, 30, 0)
		local hub = newPart({
			Name = "FogHub",
			Material = Enum.Material.ForceField,
			Color = toxicColor(),
			Transparency = 1,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(mid),
		})
		if not hub then break end
		makeEmitter(hub, {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Rate = 6,
			Lifetime = NumberRange.new(3, 6),
			Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new(22),
			Color = ColorSequence.new(hub.Color),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Acceleration = Vector3.new(0, 2, 0), -- fog rises
		})
		-- A faint drifting spore emitter alongside.
		makeEmitter(hub, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Rate = 5,
			Lifetime = NumberRange.new(2, 4),
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(120, 120),
			Size = NumberSequence.new(0.5),
			Color = ColorSequence.new(Color3.fromRGB(150, 255, 150)),
		})
	end
end

--======================================================================
-- Model + glow helpers for the DETAILED world mutations. Each world mutation
-- is ONE tidy Model (parented to the world folder); its detail parts are made
-- through newPart() with Parent=model, so they all inherit the CanCollide=
-- false safety flags, the MAX_WORLD_MUTATIONS cap accounting, and the melt/
-- fade + cleanup bookkeeping. startModel() reserves capacity for the whole
-- model up front so we never build a half-finished one when the cap is near.
--======================================================================
local function startModel(name, approxParts)
	if not canSpawn(approxParts) then return nil end
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = ensureWorldFolder()
	return m
end

-- glowLight(part, color, brightness, range, pulse): attach a PointLight to a
-- part; if pulse, tween its brightness in a gentle infinite loop (cosmetic).
local function glowLight(part, color, brightness, range, pulse)
	if not part then return nil end
	local pl = Instance.new("PointLight")
	pl.Color = color
	pl.Brightness = brightness
	pl.Range = range
	pl.Parent = part
	if pulse then
		TweenService:Create(pl, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Brightness = brightness * 0.35 }):Play()
	end
	return pl
end

--======================================================================
-- startWorldMutations(targets): MAIN -> sprout DETAILED, organic world
-- mutations on + around each island. Each type is a multi-part Model with
-- fitting materials/colours and gentle animation: a giant glossy EYEBALL
-- (sclera + veins + iris + pupil + wet highlight + two blinking eyelids), a
-- clustered glowing BEAN growth, a faceted translucent CRYSTAL formation, a
-- jagged bobbing ROCK chunk, a glossy bubbling SLIME puddle, and a twisting
-- glowing PLANT. All VISUAL, CanCollide=false, capped, and they melt + clean
-- up with the event.
--======================================================================
function MutationEffects.startWorldMutations(targets)
	ensureWorldFolder()
	for _, t in ipairs(targets or {}) do
		local sx = (t.size and t.size.X or 120)
		local sz = (t.size and t.size.Z or 120)
		local function rndOffset()
			return Vector3.new((math.random() - 0.5) * sx * 0.6, 0, (math.random() - 0.5) * sz * 0.6)
		end

		----------------------------------------------------------------
		-- GIANT EYEBALL opening in the terrain. White glossy sclera + reddish
		-- veins + a coloured glowing iris + dark pupil + a wet highlight, with
		-- two fleshy eyelids that tween OPEN on spawn then BLINK occasionally.
		----------------------------------------------------------------
		-- Bumped reservation: bigger, more lifelike eye (sclera, 3 veins, iris +
		-- 2 detail rings + rim, pupil, highlight, 2 lids = up to ~12 parts).
		local eyeModel = startModel("GiantEye", 12)
		if eyeModel then
			local D = math.random(7, 9)                       -- sclera diameter (bigger)
			local center = t.position + rndOffset() + Vector3.new(0, D * 0.45, 0)
			local eyeCF = CFrame.new(center) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
			local irisColor = toxicColor()

			-- Sclera: white, glossy/wet (reflectance), grows open from small.
			local sclera = newPart({
				Name = "Sclera", Parent = eyeModel,
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(238, 244, 236),
				Transparency = 0, Reflectance = 0.25,
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.5, 0.5, 0.5),
				CFrame = eyeCF,
			})
			if sclera then
				TweenService:Create(sclera, TweenInfo.new(1.8, Enum.EasingStyle.Back),
					{ Size = Vector3.new(D, D, D) }):Play()
			end

			-- A few thin reddish veins creeping across the sclera (organic, varied).
			for _ = 1, 3 do
				newPart({
					Name = "Vein", Parent = eyeModel,
					Material = Enum.Material.SmoothPlastic,
					Color = Color3.fromRGB(180, 70, 70),
					Transparency = 0.1,
					Size = Vector3.new(D * (0.7 + math.random() * 0.3), 0.1, 0.1),
					CFrame = eyeCF
						* CFrame.Angles(math.rad(math.random(-50, 50)), math.rad(math.random(0, 360)), math.rad(math.random(-50, 50)))
						* CFrame.new(0, 0, -D * 0.45),
				})
			end

			-- Iris (coloured, glowing) + concentric detail rings + darker rim +
			-- dark pupil + wet highlight, all on the front of the sclera.
			local front = eyeCF * CFrame.new(0, 0, -D * 0.46)
			-- Darker outer rim: a slightly larger flat ball just behind the iris.
			newPart({
				Name = "IrisRim", Parent = eyeModel,
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(
					math.floor(irisColor.R * 255 * 0.45),
					math.floor(irisColor.G * 255 * 0.45),
					math.floor(irisColor.B * 255 * 0.45)
				),
				Transparency = 0.05,
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(D * 0.58, D * 0.58, 0.36),
				CFrame = front * CFrame.new(0, 0, 0.02),
			})
			local iris = newPart({
				Name = "Iris", Parent = eyeModel,
				Material = Enum.Material.Neon,
				Color = irisColor,
				Transparency = 0.05,
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(D * 0.5, D * 0.5, 0.4),
				CFrame = front,
			})
			-- A subtle inner concentric ring (slightly darker neon) for radial detail.
			newPart({
				Name = "IrisRing", Parent = eyeModel,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(
					math.floor(irisColor.R * 255 * 0.7),
					math.floor(irisColor.G * 255 * 0.7),
					math.floor(irisColor.B * 255 * 0.7)
				),
				Transparency = 0.1,
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(D * 0.36, D * 0.36, 0.42),
				CFrame = front * CFrame.new(0, 0, -0.02),
			})
			newPart({
				Name = "Pupil", Parent = eyeModel,
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(12, 12, 16),
				Transparency = 0,
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(D * 0.22, D * 0.22, 0.44),
				CFrame = front * CFrame.new(0, 0, -0.05),
			})
			newPart({
				Name = "Highlight", Parent = eyeModel,
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(255, 255, 255),
				Transparency = 0.1, Reflectance = 0.4,
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(D * 0.12, D * 0.12, 0.3),
				CFrame = front * CFrame.new(D * 0.14, D * 0.14, -0.08),
			})
			if iris then glowLight(iris, iris.Color, 3, 16, true) end

			-- Two fleshy eyelids (a bit larger than the sclera). Closed = meeting
			-- at the centre (covering the eye); open = separated up/down. They
			-- tween open on spawn, then blink on a random interval.
			local lidSize = Vector3.new(D * 1.18, D * 1.18, D * 1.18)
			local up = Vector3.new(0, 1, 0)
			local function lidClosedCF(sign) return CFrame.new(center + up * (sign * D * 0.55)) end
			local function lidOpenCF(sign)   return CFrame.new(center + up * (sign * D * 1.18)) end
			local lidColor = Color3.fromRGB(120, 170, 95)
			local topLid = newPart({
				Name = "TopLid", Parent = eyeModel,
				Material = Enum.Material.SmoothPlastic, Color = lidColor,
				Transparency = 0, Reflectance = 0.08,
				Shape = Enum.PartType.Ball, Size = lidSize,
				CFrame = lidClosedCF(1),
			})
			local botLid = newPart({
				Name = "BotLid", Parent = eyeModel,
				Material = Enum.Material.SmoothPlastic, Color = lidColor,
				Transparency = 0, Reflectance = 0.08,
				Shape = Enum.PartType.Ball, Size = lidSize,
				CFrame = lidClosedCF(-1),
			})
			if topLid and botLid then
				-- Open after the sclera grows in.
				TweenService:Create(topLid, TweenInfo.new(1.0, Enum.EasingStyle.Quad), { CFrame = lidOpenCF(1) }):Play()
				TweenService:Create(botLid, TweenInfo.new(1.0, Enum.EasingStyle.Quad), { CFrame = lidOpenCF(-1) }):Play()
				-- Blink loop (Heartbeat-timed; registered for cleanup).
				local nextBlink = os.clock() + math.random(3, 6)
				local conn
				conn = RunService.Heartbeat:Connect(function()
					if not topLid.Parent or not botLid.Parent then
						conn:Disconnect(); activeConns[conn] = nil; return
					end
					if os.clock() >= nextBlink then
						nextBlink = os.clock() + math.random(3, 6)
						local q = TweenInfo.new(0.1, Enum.EasingStyle.Quad)
						TweenService:Create(topLid, q, { CFrame = lidClosedCF(1) }):Play()
						TweenService:Create(botLid, q, { CFrame = lidClosedCF(-1) }):Play()
						task.delay(0.14, function()
							if topLid.Parent and botLid.Parent then
								local o = TweenInfo.new(0.16, Enum.EasingStyle.Quad)
								TweenService:Create(topLid, o, { CFrame = lidOpenCF(1) }):Play()
								TweenService:Create(botLid, o, { CFrame = lidOpenCF(-1) }):Play()
							end
						end)
					end
				end)
				activeConns[conn] = true
			end
		end

		----------------------------------------------------------------
		-- GIANT GLOWING BEAN GROWTH: a CLUSTER of organic, ELONGATED bean pods
		-- of VARIED size/tilt (not uniform spheres), neon green, each gently
		-- pulsing in size AND transparency, with thin tendril stalks at the base
		-- and a pulsing PointLight glow.
		-- Parts: ~4 pods + ~3 tendrils = up to 7.
		----------------------------------------------------------------
		local beanModel = startModel("GiantBean", 7)
		if beanModel then
			local base = t.position + rndOffset() + Vector3.new(0, 4, 0)
			local glowAnchor
			-- Cluster of ovoid pods: each its own random size, lean and offset.
			for i = 1, 4 do
				local podW = math.random(22, 34) / 10          -- width (varied)
				local podH = math.random(55, 100) / 10         -- height -> elongated/ovoid
				local podBase = base + Vector3.new((math.random() - 0.5) * 7, math.random(0, 4), (math.random() - 0.5) * 7)
				local pod = newPart({
					Name = "BeanPod", Parent = beanModel,
					Material = Enum.Material.Neon,
					Color = Color3.fromRGB(110, 240, 95),
					Transparency = 0.1,
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(podW, podH, podW),    -- elongated ovoid, not a sphere
					CFrame = CFrame.new(podBase)
						* CFrame.Angles(math.rad(math.random(-30, 30)), math.rad(math.random(0, 360)), math.rad(math.random(-30, 30))),
				})
				if pod then
					glowAnchor = glowAnchor or pod
					-- Pulsing GLOW: gently breathe both size and transparency in a loop.
					TweenService:Create(pod, TweenInfo.new(1.4 + i * 0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
						{ Size = pod.Size + Vector3.new(0.6, 1, 0.6), Transparency = 0.35 }):Play()
					-- A thin tendril stalk anchoring this pod to the ground.
					newPart({
						Name = "BeanTendril", Parent = beanModel,
						Material = Enum.Material.Neon,
						Color = Color3.fromRGB(90, 180, 70),
						Transparency = 0.2,
						Size = Vector3.new(0.35, podH * 0.6, 0.35),
						CFrame = CFrame.new(podBase - Vector3.new(0, podH * 0.5, 0))
							* CFrame.Angles(math.rad(math.random(-15, 15)), math.rad(math.random(0, 360)), math.rad(math.random(-15, 15))),
					})
				end
			end
			-- Pulsing glow centred on the cluster.
			glowLight(glowAnchor, Color3.fromRGB(120, 255, 120), 2.5, 20, true)
		end

		----------------------------------------------------------------
		-- PULSING CRYSTALS: a CLUSTER of jagged faceted shards of VARIED heights
		-- and angles, translucent (Glass, low Transparency), with an internal
		-- pulse glow (pulsing PointLight) and glowing NEON edge trim caps on the
		-- shard tips. Parts: ~4 shards + ~2 neon edge trims = up to 6.
		----------------------------------------------------------------
		local crystalModel = startModel("PulseCrystal", 6)
		if crystalModel then
			local base = t.position + rndOffset() + Vector3.new(0, 1, 0)
			local glowAnchor
			local crystalColor = toxicColor()
			for i = 1, 4 do
				local h = math.random(45, 110) / 10                 -- varied heights
				local w = math.random(10, 24) / 10                  -- varied widths
				local shardCF = CFrame.new(base + Vector3.new((math.random() - 0.5) * 6, h * 0.5, (math.random() - 0.5) * 6))
					* CFrame.Angles(math.rad(math.random(-30, 30)), math.rad(math.random(0, 360)), math.rad(math.random(-30, 30)))
				local shard = newPart({
					Name = "Shard", Parent = crystalModel,
					Material = Enum.Material.Glass,
					Color = crystalColor,
					Transparency = 0.4, Reflectance = 0.2,
					Size = Vector3.new(w, h, w),
					CFrame = shardCF,
				})
				if shard then
					glowAnchor = glowAnchor or shard
					-- Internal pulse: translucency breathes in a loop.
					TweenService:Create(shard, TweenInfo.new(1.3 + i * 0.07, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
						{ Transparency = 0.7 }):Play()
					-- Glowing neon edge trim on the first two shards' tips (thin caps).
					if i <= 2 then
						local trim = newPart({
							Name = "ShardTrim", Parent = crystalModel,
							Material = Enum.Material.Neon,
							Color = crystalColor,
							Transparency = 0.05,
							Size = Vector3.new(w * 0.55, h * 0.22, w * 0.55),
							CFrame = shardCF * CFrame.new(0, h * 0.5, 0),
						})
						if trim then
							TweenService:Create(trim, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
								{ Transparency = 0.45 }):Play()
						end
					end
				end
			end
			-- Internal pulse glow at the cluster core.
			if glowAnchor then glowLight(glowAnchor, glowAnchor.Color, 2.5, 18, true) end
		end

		----------------------------------------------------------------
		-- FLOATING ROCK: a jagged chunk of a few rough rock sub-parts at random
		-- angles (not a cube), slowly bobbing + rotating as one rigid body.
		----------------------------------------------------------------
		local rockModel = startModel("FloatRock", 3)
		if rockModel then
			local base = t.position + rndOffset() + Vector3.new(0, 9, 0)
			local biggest
			for _ = 1, 3 do
				local s = Vector3.new(math.random(20, 40) / 10, math.random(20, 38) / 10, math.random(20, 40) / 10)
				local chunk = newPart({
					Name = "RockChunk", Parent = rockModel,
					Material = Enum.Material.Slate,
					Color = Color3.fromRGB(86, 96, 84),
					Transparency = 0,
					Size = s,
					CFrame = CFrame.new(base + Vector3.new((math.random() - 0.5) * 2.4, (math.random() - 0.5) * 2.4, (math.random() - 0.5) * 2.4))
						* CFrame.Angles(math.rad(math.random(0, 360)), math.rad(math.random(0, 360)), math.rad(math.random(0, 360))),
				})
				if chunk and (not biggest or s.Y > biggest.Size.Y) then biggest = chunk end
			end
			if biggest then
				rockModel.PrimaryPart = biggest
				glowLight(biggest, Color3.fromRGB(120, 255, 120), 1.4, 14, false)
				local baseCF = rockModel:GetPivot()
				local phase = math.random() * math.pi * 2
				local conn
				conn = RunService.Heartbeat:Connect(function()
					if not rockModel.Parent or not biggest.Parent then
						conn:Disconnect(); activeConns[conn] = nil; return
					end
					local y = math.sin(os.clock() * 1.0 + phase) * 1.5
					rockModel:PivotTo(baseCF * CFrame.new(0, y, 0) * CFrame.Angles(0, os.clock() * 0.4, 0))
				end)
				activeConns[conn] = true
			end
		end

		----------------------------------------------------------------
		-- TOXIC SLIME PUDDLE: glossy bubbling green OOZE. An IRREGULAR puddle made
		-- of several OVERLAPPING flat disc lobes of varied size/offset (so the
		-- outline is non-circular), glossy (Glass + Reflectance) with a slight
		-- glow, raised goo blobs that wobble, and bubble particles that pop in/out
		-- via a capped makeEmitter (rising + short-lived = pop). Parts: ~3 lobes +
		-- ~2 blobs = up to 5.
		----------------------------------------------------------------
		local slimeModel = startModel("SlimePuddle", 5)
		if slimeModel then
			local base = t.position + rndOffset() + Vector3.new(0, 0.35, 0)
			local r = math.random(7, 12)
			local mainLobe
			-- Several overlapping flat cylinder lobes -> irregular, non-circular puddle.
			for i = 1, 3 do
				local lobeR = r * (i == 1 and 1.0 or (0.45 + math.random() * 0.4))
				local lobeOff = (i == 1) and Vector3.new(0, 0, 0)
					or Vector3.new((math.random() - 0.5) * r * 1.1, 0, (math.random() - 0.5) * r * 1.1)
				local lobe = newPart({
					Name = "Goo", Parent = slimeModel,
					Material = Enum.Material.Glass,
					Color = Color3.fromRGB(118, 224, 86),
					Transparency = 0.2, Reflectance = 0.25,
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.5, 4, 4),
					CFrame = CFrame.new(base + lobeOff) * CFrame.Angles(0, 0, math.rad(90)),
				})
				if lobe then
					mainLobe = mainLobe or lobe
					-- Ooze: grow each lobe out to its (varied) radius.
					TweenService:Create(lobe, TweenInfo.new(3, Enum.EasingStyle.Sine),
						{ Size = Vector3.new(0.5, lobeR * 2, lobeR * 2) }):Play()
				end
			end
			if mainLobe then
				-- Slight glow so the ooze reads as toxic.
				glowLight(mainLobe, Color3.fromRGB(150, 255, 120), 1.2, 16, false)
				-- Bubbles that pop in/out: short lifetime + rising = appear then vanish.
				makeEmitter(mainLobe, {
					Texture = "rbxasset://textures/particles/sparkles_main.dds",
					Rate = 7,
					Lifetime = NumberRange.new(0.5, 1.1),     -- short -> "pop"
					Speed = NumberRange.new(1, 3),
					SpreadAngle = Vector2.new(40, 40),
					Size = NumberSequence.new({              -- swell then pop to nothing
						NumberSequenceKeypoint.new(0, 0.2),
						NumberSequenceKeypoint.new(0.7, 1.0),
						NumberSequenceKeypoint.new(1, 0),
					}),
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.2),
						NumberSequenceKeypoint.new(1, 1),
					}),
					Color = ColorSequence.new(Color3.fromRGB(170, 255, 130)),
					Acceleration = Vector3.new(0, 4, 0),     -- bubbles rise
				})
			end
			-- A couple of raised goo blobs that wobble (size pulse loop).
			for _ = 1, 2 do
				local blob = newPart({
					Name = "GooBlob", Parent = slimeModel,
					Material = Enum.Material.Glass,
					Color = Color3.fromRGB(130, 235, 95),
					Transparency = 0.2, Reflectance = 0.25,
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(2, 1.4, 2),
					CFrame = CFrame.new(base + Vector3.new((math.random() - 0.5) * r, 0.4, (math.random() - 0.5) * r)),
				})
				if blob then
					TweenService:Create(blob, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
						{ Size = Vector3.new(2.4, 1.0, 2.4) }):Play()
				end
			end
		end

		----------------------------------------------------------------
		-- WEIRD PLANT: a TWISTING stalk built from two angled segments, a glowing
		-- bulbous tip, and a few glowing LEAVES that PULSE (gentle scale +
		-- transparency tween loop). The whole plant sways from its base.
		-- Parts: 2 stalk segments + tip + ~3 leaves = up to 6.
		----------------------------------------------------------------
		local plantModel = startModel("WeirdPlant", 6)
		if plantModel then
			local base = t.position + rndOffset() + Vector3.new(0, 0.5, 0)
			local h = math.random(60, 110) / 10
			-- Lower stalk segment.
			local lowerCF = CFrame.new(base + Vector3.new(0, h * 0.25, 0))
				* CFrame.Angles(math.rad(math.random(-12, 12)), 0, math.rad(math.random(-12, 12)))
			local stalk = newPart({
				Name = "Stalk", Parent = plantModel,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(150, 220, 70),
				Transparency = 0.1,
				Size = Vector3.new(0.8, h * 0.55, 0.8),
				CFrame = lowerCF,
			})
			-- Upper stalk segment: twists off at an angle from the lower tip.
			local upperBaseCF = lowerCF * CFrame.new(0, h * 0.27, 0)
			local upperCF = upperBaseCF
				* CFrame.Angles(math.rad(math.random(-25, 25)), math.rad(math.random(0, 360)), math.rad(math.random(-25, 25)))
				* CFrame.new(0, h * 0.27, 0)
			newPart({
				Name = "StalkUpper", Parent = plantModel,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(150, 220, 70),
				Transparency = 0.1,
				Size = Vector3.new(0.6, h * 0.55, 0.6),
				CFrame = upperCF,
			})
			-- Glowing bulbous tip at the end of the upper segment.
			local tip = newPart({
				Name = "Tip", Parent = plantModel,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(200, 255, 120),
				Transparency = 0,
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.8, 1.8, 1.8),
				CFrame = upperCF * CFrame.new(0, h * 0.3, 0),
			})
			if tip then glowLight(tip, Color3.fromRGB(190, 255, 110), 2, 14, true) end
			-- Glowing leaves that PULSE: scale + transparency breathe in a loop.
			for _ = 1, 3 do
				local leafSize = Vector3.new(math.random(22, 32) / 10, 0.2, math.random(11, 16) / 10)
				local leaf = newPart({
					Name = "Leaf", Parent = plantModel,
					Material = Enum.Material.Neon,
					Color = Color3.fromRGB(120, 210, 80),
					Transparency = 0.15,
					Size = leafSize,
					CFrame = lowerCF * CFrame.new(0, math.random(-20, 30) / 10, 0)
						* CFrame.Angles(0, math.rad(math.random(0, 360)), math.rad(math.random(20, 50)))
						* CFrame.new(1.4, 0, 0),
				})
				if leaf then
					TweenService:Create(leaf, TweenInfo.new(1.6 + math.random() * 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
						{ Size = leafSize + Vector3.new(0.5, 0, 0.3), Transparency = 0.4 }):Play()
				end
			end
			-- Gentle sway, rotating the whole plant about its GROUND base so the
			-- base stays planted while the tip leans.
			if stalk then
				plantModel.PrimaryPart = stalk
				local baseCF = plantModel:GetPivot()
				local pivotPoint = CFrame.new(base)
				local phase = math.random() * math.pi * 2
				local conn
				conn = RunService.Heartbeat:Connect(function()
					if not plantModel.Parent or not stalk.Parent then
						conn:Disconnect(); activeConns[conn] = nil; return
					end
					local sway = math.sin(os.clock() * 0.8 + phase) * 0.18
					local T = pivotPoint * CFrame.Angles(0, sway * 0.4, sway) * pivotPoint:Inverse()
					plantModel:PivotTo(T * baseCF)
				end)
				activeConns[conn] = true
			end
		end
	end
end

--======================================================================
-- electricalSurge(): WARNING/MAIN flavour -> a brief electrical surge flash.
-- Spawns a quick neon arc over a random island + tells clients to flash/
-- glitch the sky. VISUAL ONLY.
--======================================================================
function MutationEffects.electricalSurge(targets)
	if not targets or #targets == 0 then return end
	if not canSpawn(1) then
		-- Even if part cap is hit, still send the client glitch cue.
		if MutationSync then MutationSync:FireAllClients("surge") end
		return
	end
	local t = targets[math.random(1, #targets)]
	local folder = ensureStormFolder()
	local arc = Instance.new("Part")
	arc.Name = "Surge"
	arc.Material = Enum.Material.Neon
	arc.Color = Color3.fromRGB(150, 255, 180)
	arc.Transparency = 0.1
	arc.Size = Vector3.new(0.8, 300, 0.8)
	arc.Anchored = true
	arc.CanCollide = false
	arc.CanQuery = false
	arc.CanTouch = false
	arc.CFrame = CFrame.new(t.position + Vector3.new((math.random() - 0.5) * 60, 150, (math.random() - 0.5) * 60))
		* CFrame.Angles(0, 0, math.rad(math.random(-12, 12)))
	arc.Parent = folder
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(150, 255, 180); pl.Brightness = 6; pl.Range = 90
	pl.Parent = arc
	TweenService:Create(arc, TweenInfo.new(0.35), { Transparency = 1 }):Play()
	Debris:AddItem(arc, 0.6)
	if MutationSync then MutationSync:FireAllClients("surge") end
end

--======================================================================
-- radioactiveStorm(targets): MAIN -> a green lightning bolt strikes a random
-- island + a toxic shockwave ring expands from the impact. Returns the
-- strike POSITION so the manager can find nearby players + message them a
-- STRONGER mutation. VISUAL ONLY here.
--======================================================================
function MutationEffects.radioactiveStorm(targets)
	if not targets or #targets == 0 then return nil end
	local t = targets[math.random(1, #targets)]
	local strikePos = t.position + Vector3.new((math.random() - 0.5) * 40, 0, (math.random() - 0.5) * 40)
	local folder = ensureStormFolder()

	-- ---- Green lightning bolt down to the island. ----
	local bolt = Instance.new("Part")
	bolt.Name = "StormBolt"
	bolt.Material = Enum.Material.Neon
	bolt.Color = Color3.fromRGB(140, 255, 120)
	bolt.Transparency = 0.05
	bolt.Size = Vector3.new(1.6, 450, 1.6)
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.CanQuery = false
	bolt.CanTouch = false
	bolt.CFrame = CFrame.new(strikePos + Vector3.new(0, 225, 0))
		* CFrame.Angles(0, 0, math.rad(math.random(-10, 10)))
	bolt.Parent = folder
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(140, 255, 120); pl.Brightness = 10; pl.Range = 140
	pl.Parent = bolt
	TweenService:Create(bolt, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	Debris:AddItem(bolt, 0.6)

	-- ---- Toxic shockwave ring expanding from the impact. ----
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(120, 255, 120)
	ring.Transparency = 0.3
	ring.Size = Vector3.new(0.6, 4, 4)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CFrame = CFrame.new(strikePos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder
	local radius = CONFIG.STORM_RADIUS or 60
	TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
		Size = Vector3.new(0.6, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 1.2)

	-- Client cue: storm flash + camera shake near the strike.
	if MutationSync then
		MutationSync:FireAllClients("storm", { position = strikePos })
	end

	return strikePos
end

--======================================================================
-- startMelt(): ENDING -> fade all world mutations toward transparent so the
-- world visibly returns to normal before cleanup() destroys everything.
--======================================================================
function MutationEffects.startMelt()
	local dur = math.max(2, (CONFIG.ENDING_DURATION or 12) - 1)
	for _, p in ipairs(fadeParts) do
		if p and p.Parent then
			TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Linear),
				{ Transparency = 1 }):Play()
		end
	end
end

--======================================================================
-- cleanup(): disconnect every connection, destroy all world/storm parts.
-- No leaks, no permanent world change (we never modified island geometry).
--======================================================================
function MutationEffects.cleanup()
	for conn in pairs(activeConns) do
		if conn.Connected then conn:Disconnect() end
	end
	activeConns = {}

	if worldFolder and worldFolder.Parent then worldFolder:Destroy() end
	if stormFolder and stormFolder.Parent then stormFolder:Destroy() end
	worldFolder = nil
	stormFolder = nil

	fadeParts = {}
	worldCount = 0
end

return MutationEffects
