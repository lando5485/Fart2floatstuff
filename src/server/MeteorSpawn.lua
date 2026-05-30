--======================================================================
-- MeteorSpawn.lua  (ModuleScript)
--======================================================================
-- Spawns falling meteors for the global "MeteorStorm" event.
--
-- Everything in here creates real Workspace instances on the SERVER so
-- every client sees the IDENTICAL meteor (server-authoritative). Each
-- meteor is one rock Part with a long cinematic trail (fire + smoke +
-- sparks + embers via ParticleEmitters + a Trail) and is moved down a
-- long arc to its island impact point via a Heartbeat lerp + PivotTo
-- (NEVER teleported). On landing it calls back into MeteorImpact.
--
-- This module is a PURE SPECTACLE + delivery system. It does NOT read or
-- modify the player's fart meter, flight, food, guts, island heights,
-- earn rate, coins, the falling-junk hazard, or the plane hazard. The
-- only gameplay touch-points (knockback + coin reward) live in
-- MeteorImpact / MeteorReward, driven by CONFIG.
--
-- PERFORMANCE:
--   * MeteorManager enforces CONFIG.MAX_METEORS simultaneous meteors; this
--     module also tracks a live count and refuses to exceed it.
--   * Every emitter Rate is capped (CONFIG.MAX_PARTICLE_RATE).
--   * Every instance + Heartbeat connection we create is tracked and
--     destroyed/disconnected in cleanup() (no leaks).
--======================================================================

local MeteorSpawn = {}

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- Set by init(): the shared CONFIG table (owned by MeteorManager) and the
-- MeteorImpact module (required by the manager and handed to us so we don't
-- create a require cycle).
local CONFIG = nil
local MeteorImpact = nil

-- Folder holding every meteor + trail instance we spawn (cleanup = destroy it).
local meteorFolder = nil

-- Live tracking for cleanup + the simultaneous cap.
local activeConnections = {}   -- Heartbeat connections driving falls
local liveMeteorCount = 0      -- meteors currently falling

--======================================================================
-- VARIANT DEFINITIONS: colors / glow / material per meteor variant.
-- "normal" = red/orange, "toxic" = green, "ice" = blue/white,
-- "rainbow" = cycling, "alien" = purple, "legendary" = gold.
--======================================================================
local VARIANTS = {
	normal = {
		core = Color3.fromRGB(80, 50, 40),
		flame = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 70, 0)),
		trail = ColorSequence.new(Color3.fromRGB(255, 140, 40), Color3.fromRGB(120, 30, 0)),
		light = Color3.fromRGB(255, 120, 40),
	},
	toxic = {
		core = Color3.fromRGB(40, 70, 30),
		flame = ColorSequence.new(Color3.fromRGB(180, 255, 120), Color3.fromRGB(40, 160, 30)),
		trail = ColorSequence.new(Color3.fromRGB(120, 255, 90), Color3.fromRGB(20, 90, 10)),
		light = Color3.fromRGB(120, 255, 90),
	},
	ice = {
		core = Color3.fromRGB(150, 200, 230),
		flame = ColorSequence.new(Color3.fromRGB(220, 245, 255), Color3.fromRGB(90, 170, 255)),
		trail = ColorSequence.new(Color3.fromRGB(200, 235, 255), Color3.fromRGB(120, 180, 255)),
		light = Color3.fromRGB(170, 215, 255),
	},
	rainbow = {
		core = Color3.fromRGB(255, 255, 255),
		-- A full hue sweep for the cinematic confetti look.
		flame = ColorSequence.new({
			ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 120)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 180, 255)),
			ColorSequenceKeypoint.new(1.0, Color3.fromRGB(220, 100, 255)),
		}),
		trail = ColorSequence.new({
			ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 120)),
			ColorSequenceKeypoint.new(1.0, Color3.fromRGB(120, 120, 255)),
		}),
		light = Color3.fromRGB(255, 255, 255),
	},
	alien = {
		core = Color3.fromRGB(120, 60, 160),
		flame = ColorSequence.new(Color3.fromRGB(210, 130, 255), Color3.fromRGB(90, 0, 160)),
		trail = ColorSequence.new(Color3.fromRGB(190, 110, 255), Color3.fromRGB(60, 0, 110)),
		light = Color3.fromRGB(190, 110, 255),
	},
	legendary = {
		core = Color3.fromRGB(255, 215, 60),
		flame = ColorSequence.new(Color3.fromRGB(255, 245, 170), Color3.fromRGB(255, 170, 0)),
		trail = ColorSequence.new(Color3.fromRGB(255, 235, 120), Color3.fromRGB(220, 150, 0)),
		light = Color3.fromRGB(255, 220, 90),
	},
}

--------------------------------------------------------------------
-- init(config, impactModule): wire the shared CONFIG + impact module in.
-- Called once by MeteorManager before any spawn.
--------------------------------------------------------------------
function MeteorSpawn.init(config, impactModule)
	CONFIG = config
	MeteorImpact = impactModule
end

--------------------------------------------------------------------
-- ensureFolder(): make sure we have a fresh folder to host meteors.
--------------------------------------------------------------------
local function ensureFolder()
	if not meteorFolder or not meteorFolder.Parent then
		meteorFolder = Instance.new("Folder")
		meteorFolder.Name = "MeteorStormMeteors"
		meteorFolder.Parent = workspace
	end
	return meteorFolder
end

--------------------------------------------------------------------
-- makeEmitter(parent, props): capped ParticleEmitter helper.
-- Rate is hard-capped by CONFIG.MAX_PARTICLE_RATE so several meteors at
-- once never flood the renderer.
--------------------------------------------------------------------
local function makeEmitter(parent, props)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = props.Texture or "rbxasset://textures/particles/smoke_main.dds"
	pe.Rate = math.min(props.Rate or 10, CONFIG.MAX_PARTICLE_RATE)
	pe.Lifetime = props.Lifetime or NumberRange.new(0.6, 1.2)
	pe.Speed = props.Speed or NumberRange.new(2, 5)
	pe.SpreadAngle = props.SpreadAngle or Vector2.new(20, 20)
	pe.Rotation = props.Rotation or NumberRange.new(0, 360)
	pe.Size = props.Size or NumberSequence.new(2)
	pe.Transparency = props.Transparency or NumberSequence.new(0.2)
	pe.Color = props.Color or ColorSequence.new(Color3.new(1, 1, 1))
	pe.LightEmission = props.LightEmission or 0
	pe.Acceleration = props.Acceleration or Vector3.new(0, 0, 0)
	pe.Enabled = props.Enabled ~= false
	pe.Parent = parent
	return pe
end

--------------------------------------------------------------------
-- pickSize(): roll a size category + radius from CONFIG ranges.
-- Returns radius (studs) and a 0..1 "bigness" used to scale effects.
--------------------------------------------------------------------
local function pickSize(forceLegendary)
	if forceLegendary then
		return CONFIG.LEGENDARY_SIZE, 1.0
	end
	local roll = math.random()
	if roll < 0.5 then
		-- small
		local r = math.random(CONFIG.SMALL_SIZE_MIN * 10, CONFIG.SMALL_SIZE_MAX * 10) / 10
		return r, 0.2
	elseif roll < 0.85 then
		-- medium
		local r = math.random(CONFIG.MEDIUM_SIZE_MIN * 10, CONFIG.MEDIUM_SIZE_MAX * 10) / 10
		return r, 0.55
	else
		-- large
		local r = math.random(CONFIG.LARGE_SIZE_MIN * 10, CONFIG.LARGE_SIZE_MAX * 10) / 10
		return r, 1.0
	end
end

--------------------------------------------------------------------
-- rollVariant(): pick a meteor variant from CONFIG chances.
-- Legendary is decided by the caller (manager) and forced in here.
--------------------------------------------------------------------
local function rollVariant(forceLegendary)
	if forceLegendary then return "legendary" end
	local r = math.random()
	if r < CONFIG.TOXIC_CHANCE then return "toxic" end
	r = r - CONFIG.TOXIC_CHANCE
	if r < CONFIG.ICE_CHANCE then return "ice" end
	r = r - CONFIG.ICE_CHANCE
	if r < CONFIG.RAINBOW_CHANCE then return "rainbow" end
	r = r - CONFIG.RAINBOW_CHANCE
	if r < CONFIG.ALIEN_CHANCE then return "alien" end
	return "normal"
end

--======================================================================
-- spawnMeteor(targetPos, opts):
--   targetPos = Vector3 impact point on an island top surface.
--   opts = { legendary = bool, harmless = bool, variant = string? }
--     * harmless = a tiny warning-phase streak that fades in the sky and
--       does NOT impact (used during the WARNING phase).
-- Returns true if spawned, false if the simultaneous cap was hit.
--======================================================================
function MeteorSpawn.spawnMeteor(targetPos, opts)
	opts = opts or {}
	if liveMeteorCount >= CONFIG.MAX_METEORS then
		return false -- respect the hard simultaneous cap
	end

	local folder = ensureFolder()
	local legendary = opts.legendary == true
	local variant = opts.variant or rollVariant(legendary)
	local vdef = VARIANTS[variant] or VARIANTS.normal
	local radius, bigness = pickSize(legendary)
	if opts.harmless then
		-- Warning streaks are small + cosmetic regardless of roll.
		radius = math.random(8, 14) / 10
		bigness = 0.1
	end

	-- ---- The meteor rock (one Part). CanCollide=false so it never traps a
	--      player even mid-fall; impact damage/knockback is decided by the
	--      server proximity check, NOT by physical collision. ----
	local rock = Instance.new("Part")
	rock.Name = "Meteor_" .. variant
	rock.Shape = Enum.PartType.Ball
	rock.Material = Enum.Material.Slate
	rock.Color = vdef.core
	rock.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	rock.Anchored = true          -- driven by lerp + PivotTo (no physics)
	rock.CanCollide = false
	rock.CanTouch = false
	rock.CanQuery = false
	rock.CastShadow = false
	rock.Parent = folder

	-- Glowing molten core on fast/big/legendary meteors (a PointLight + neon
	-- shell), capped to bigger rocks so we don't add lights to every pebble.
	if bigness >= CONFIG.GLOW_THRESHOLD or legendary then
		local light = Instance.new("PointLight")
		light.Color = vdef.light
		light.Brightness = legendary and 6 or 3
		light.Range = math.clamp(radius * 6, 20, 60)
		light.Parent = rock
	end

	-- ---- Long cinematic Trail (the streak across the sky). Bigger meteor =
	--      longer/wider streak. ----
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA0"
	a0.Position = Vector3.new(0, radius * 0.6, 0)
	a0.Parent = rock
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailA1"
	a1.Position = Vector3.new(0, -radius * 0.6, 0)
	a1.Parent = rock
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = vdef.trail
	trail.Lifetime = math.clamp(0.8 + bigness * 1.6, 0.8, 2.6) -- bigger = longer streak
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Parent = rock

	-- ---- Flame emitter (brighter on bigger meteors). ----
	makeEmitter(rock, {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Rate = math.floor(14 + bigness * 16),
		Lifetime = NumberRange.new(0.3, 0.7),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(40, 40),
		Size = NumberSequence.new(radius * (1.2 + bigness)),
		Color = vdef.flame,
		LightEmission = 1,
		Transparency = NumberSequence.new(0.1),
	})

	-- ---- Smoke emitter (thicker on bigger meteors). ----
	makeEmitter(rock, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = math.floor(10 + bigness * 14),
		Lifetime = NumberRange.new(1.0, 2.2),
		Speed = NumberRange.new(1, 4),
		SpreadAngle = Vector2.new(50, 50),
		Size = NumberSequence.new(radius * (1.5 + bigness * 2)),
		Color = ColorSequence.new(Color3.fromRGB(60, 55, 50)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	-- ---- Sparks + embers (bright, short-lived flecks). ----
	makeEmitter(rock, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = math.floor(8 + bigness * 12),
		Lifetime = NumberRange.new(0.2, 0.6),
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(60, 60),
		Size = NumberSequence.new(0.5 + bigness * 0.6),
		Color = vdef.flame,
		LightEmission = 1,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	-- ---- Compute the long arc: a high spawn offset to one side of the
	--      target so it streaks DOWN diagonally (cinematic), ending exactly
	--      at targetPos. ----
	local sideX = math.random(-1, 1) == 0 and 1 or math.random(-1, 1)
	if sideX == 0 then sideX = 1 end
	local offset = Vector3.new(
		(math.random(-1, 1) == 0 and 1 or -1) * math.random(200, 500),
		CONFIG.METEOR_SPAWN_HEIGHT + math.random(0, 300),
		(math.random(-1, 1) == 0 and 1 or -1) * math.random(200, 500))
	local startPos = targetPos + offset

	-- Harmless warning streaks end high in the sky (no impact), so we aim at a
	-- point ABOVE the target rather than the ground.
	local endPos = opts.harmless and (targetPos + Vector3.new(0, 600, 0)) or targetPos

	rock.CFrame = CFrame.new(startPos, endPos)

	local fallTime = opts.harmless
		and (CONFIG.WARNING_STREAK_FALL or 1.6)
		or  (CONFIG.METEOR_FALL_TIME_MIN
			+ math.random() * (CONFIG.METEOR_FALL_TIME_MAX - CONFIG.METEOR_FALL_TIME_MIN))

	liveMeteorCount = liveMeteorCount + 1

	-- ---- Drive the fall with a Heartbeat lerp + PivotTo (NO teleport). ----
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		-- If cleanup destroyed the rock mid-fall, bail safely.
		if not rock or not rock.Parent then
			conn:Disconnect()
			return
		end
		local alpha = math.clamp((os.clock() - t0) / fallTime, 0, 1)
		local eased = alpha * alpha -- accelerate downward (gravity feel)
		local pos = startPos:Lerp(endPos, eased)
		-- Keep the rock oriented along its travel direction so the trail trails.
		rock.CFrame = CFrame.new(pos, pos + (endPos - startPos))
		if alpha >= 1 then
			conn:Disconnect()
			-- Remove from our connection list.
			for i, c in ipairs(activeConnections) do
				if c == conn then table.remove(activeConnections, i) break end
			end

			if opts.harmless then
				-- Fade + remove the streak; no impact.
				for _, pe in ipairs(rock:GetChildren()) do
					if pe:IsA("ParticleEmitter") then pe.Enabled = false end
				end
				if trail then trail.Enabled = false end
				Debris:AddItem(rock, 2)
				liveMeteorCount = math.max(0, liveMeteorCount - 1)
			else
				-- Real impact: hand off to MeteorImpact, then remove the rock.
				if MeteorImpact then
					-- impact info passed through so impact/reward can scale + roll.
					MeteorImpact.onImpact({
						position = endPos,
						radius = radius,
						bigness = bigness,
						variant = variant,
						legendary = legendary,
						lightColor = vdef.light,
					})
				end
				-- Disable emitters so they don't keep puffing after the rock is gone.
				for _, pe in ipairs(rock:GetChildren()) do
					if pe:IsA("ParticleEmitter") then pe.Enabled = false end
				end
				if trail then trail.Enabled = false end
				Debris:AddItem(rock, 1)
				liveMeteorCount = math.max(0, liveMeteorCount - 1)
			end
		end
	end)
	table.insert(activeConnections, conn)

	return true
end

--------------------------------------------------------------------
-- getLiveCount(): how many meteors are currently falling (for the manager).
--------------------------------------------------------------------
function MeteorSpawn.getLiveCount()
	return liveMeteorCount
end

--======================================================================
-- cleanup(): disconnect every fall connection + destroy every meteor.
-- No leaks: connections dropped, folder destroyed, counter reset.
--======================================================================
function MeteorSpawn.cleanup()
	for _, conn in ipairs(activeConnections) do
		if conn.Connected then conn:Disconnect() end
	end
	activeConnections = {}

	if meteorFolder and meteorFolder.Parent then
		meteorFolder:Destroy()
	end
	meteorFolder = nil
	liveMeteorCount = 0
end

return MeteorSpawn
