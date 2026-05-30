--======================================================================
-- UFOBeam.lua  (ModuleScript)
--======================================================================
-- The giant downward tractor beams for the global "UFO" event.
--
-- This module (SERVER-authoritative) owns:
--   * the bright cone/cylinder beam parts (CanCollide=false), particle /
--     atmosphere distortion, and a moving spotlight, aiming straight down
--     from the UFO onto RANDOM islands. Capped at CONFIG.MAX_BEAMS.
--   * SERVER-AUTHORITATIVE proximity detection: each beam knows its ground
--     target; it finds players within CONFIG.BEAM_RADIUS of that target and
--     tells THOSE clients (via UFOSync "engage") that they are in a beam.
--     The client then does the grounded/flying validation, captures the
--     player's start CFrame, rides them, and restores them (see UFOUI). The
--     server NEVER moves a player's character.
--   * hands off NON-player abductees (NPCs / props / items) to UFOAbduction,
--     which moves them server-side (replicated).
--
-- ★ POSITION SAFETY ★ The server only DECIDES which islands are beamed and
-- which players are within radius -- it never teleports or velocity-sets a
-- player. The grounded check, capture, ride, and restore all happen on the
-- affected client, which guarantees a player is only ever returned to the
-- exact spot it was grabbed from (same island), never deposited higher.
--======================================================================

local UFOBeam = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Wired by init().
local CONFIG = nil
local UFOSync = nil
local UFOAbduction = nil

-- State.
local beamFolder = nil      -- holds all beam parts
local beams = {}            -- active beams: { part, light, groundPos, topPos }
local ufoPos = nil          -- current UFO position beams hang from
local currentVariant = "normal"
-- Players we have already told to engage this ABDUCTION phase, so we don't
-- spam the "engage" message every tick. Cleared on stopAll()/cleanup().
local engagedPlayers = {}   -- [player] = true

--------------------------------------------------------------------
-- init(config, syncEvent, abductionModule): wire shared dependencies.
--------------------------------------------------------------------
function UFOBeam.init(config, syncEvent, abductionModule)
	CONFIG = config
	UFOSync = syncEvent
	UFOAbduction = abductionModule
end

--------------------------------------------------------------------
-- ensureFolder(): fresh folder for beam parts.
--------------------------------------------------------------------
local function ensureFolder()
	if not beamFolder or not beamFolder.Parent then
		beamFolder = Instance.new("Folder")
		beamFolder.Name = "UFOEventBeams"
		beamFolder.Parent = workspace
	end
	return beamFolder
end

-- Variant -> beam glow colour (matches UFOEffects).
local function variantColor(variant)
	if variant == "golden" then return Color3.fromRGB(255, 215, 70) end
	if variant == "hostile" then return Color3.fromRGB(255, 60, 60) end
	return Color3.fromRGB(130, 255, 170) -- alien green
end

-- effectivePull(): pull strength for the current variant (hostile is stronger,
-- still a ride, still returns to start). Sent to the client for the ride.
local function effectivePull()
	local pull = CONFIG.BEAM_PULL_STRENGTH
	if currentVariant == "hostile" then
		pull = pull * CONFIG.HOSTILE_PULL_MULT
	end
	return pull
end

--------------------------------------------------------------------
-- buildBeam(groundPos): create one tractor beam part from the UFO down to
-- the island ground point. A tall translucent cone/cylinder + spotlight +
-- a couple of capped emitters for the "atmosphere distortion".
--------------------------------------------------------------------
local function buildBeam(groundPos)
	local folder = ensureFolder()
	local glow = variantColor(currentVariant)
	local topY = ufoPos and ufoPos.Y or (groundPos.Y + 900)
	local height = math.max(50, topY - groundPos.Y)

	-- The beam shaft (cylinder standing from ground up to the UFO).
	local shaft = Instance.new("Part")
	shaft.Name = "TractorBeam"
	shaft.Shape = Enum.PartType.Cylinder
	shaft.Material = Enum.Material.ForceField
	shaft.Color = glow
	shaft.Transparency = 0.55
	-- Cylinder length axis is X; stand it up by rotating 90 about Z.
	shaft.Size = Vector3.new(height, CONFIG.BEAM_RADIUS * 2, CONFIG.BEAM_RADIUS * 2)
	shaft.Anchored = true
	shaft.CanCollide = false
	shaft.CanQuery = false
	shaft.CanTouch = false
	shaft.CFrame = CFrame.new(groundPos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shaft.Parent = folder

	-- A bright spotlight at the ground end (the "scanning" pool of light).
	local pool = Instance.new("Part")
	pool.Name = "BeamPool"
	pool.Shape = Enum.PartType.Cylinder
	pool.Material = Enum.Material.Neon
	pool.Color = glow
	pool.Transparency = 0.3
	pool.Size = Vector3.new(0.6, CONFIG.BEAM_RADIUS * 2.2, CONFIG.BEAM_RADIUS * 2.2)
	pool.Anchored = true
	pool.CanCollide = false
	pool.CanQuery = false
	pool.CanTouch = false
	pool.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pool.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Brightness = 5
	light.Range = CONFIG.BEAM_RADIUS * 1.5
	light.Parent = pool

	-- Capped rising-particle "distortion" inside the beam.
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Rate = math.min(16, CONFIG.MAX_PARTICLE_RATE)
	pe.Lifetime = NumberRange.new(1.5, 3)
	pe.Speed = NumberRange.new(20, 40)          -- rising up the beam
	pe.SpreadAngle = Vector2.new(10, 10)
	pe.Size = NumberSequence.new(3)
	pe.Color = ColorSequence.new(glow)
	pe.LightEmission = 1
	pe.Acceleration = Vector3.new(0, 30, 0)     -- pull upward
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Parent = pool

	-- Pop the shaft in with a quick fade so it appears as a beam "switching on".
	shaft.Transparency = 1
	TweenService:Create(shaft, TweenInfo.new(0.4), { Transparency = 0.55 }):Play()

	return { part = shaft, pool = pool, light = light, groundPos = groundPos }
end

--======================================================================
-- setTargets(targetList, ufoPosition, variant): (re)point the beams onto a
-- new set of island ground positions. Destroys old beams, builds new ones
-- (capped at MAX_BEAMS), and tells UFOAbduction to scan each beam for
-- abductable NPCs/props/items.
--   targetList = list of { index, position }
--======================================================================
function UFOBeam.setTargets(targetList, ufoPosition, variant)
	currentVariant = variant or "normal"
	ufoPos = ufoPosition

	-- Tear down the old beams first (they are purely cosmetic shafts).
	for _, b in ipairs(beams) do
		if b.part then b.part:Destroy() end
		if b.pool then b.pool:Destroy() end
	end
	beams = {}

	-- Build up to MAX_BEAMS new beams.
	local count = math.min(CONFIG.MAX_BEAMS, #targetList)
	for i = 1, count do
		local t = targetList[i]
		local beam = buildBeam(t.position)
		table.insert(beams, beam)
		-- Ask the abduction module to lift nearby NPCs/props/items into THIS
		-- beam (server-moved, replicated). Capped internally by MAX_ABDUCTEES.
		if UFOAbduction then
			UFOAbduction.scanBeam(t.position, CONFIG.BEAM_RADIUS, ufoPos, currentVariant)
		end
	end
end

--======================================================================
-- update(): per-tick SERVER proximity check. For each beam, find players
-- horizontally within BEAM_RADIUS of the beam's ground point and tell those
-- clients to ENGAGE (the client validates grounded/flying, captures, rides,
-- restores). We do NOT move the player here.
--======================================================================
function UFOBeam.update()
	if #beams == 0 then return end
	for _, plr in ipairs(Players:GetPlayers()) do
		if not engagedPlayers[plr] then
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				-- Which beam (if any) is this player standing under?
				for _, b in ipairs(beams) do
					local d = hrp.Position - b.groundPos
					-- Horizontal distance only (a beam is a vertical column).
					local horiz = Vector3.new(d.X, 0, d.Z).Magnitude
					-- Must also be near the ground point's height (i.e. ON that
					-- island), not way above/below it -- a generous vertical band.
					local vert = math.abs(d.Y)
					if horiz <= CONFIG.BEAM_RADIUS and vert <= 120 then
						engagedPlayers[plr] = true
						-- Tell the client to (validate +) ride. Roll the inside-UFO
						-- chance HERE on the server so it's authoritative, and pass
						-- it to the client which will honour it after the lift.
						local goInside = math.random() < CONFIG.INSIDE_UFO_CHANCE
							local insideCF = nil
							if goInside and UFOAbduction then
								insideCF = UFOAbduction.getInsideChamberCF()
							end
							if currentVariant == "golden" and CONFIG.GOLDEN_COIN_REWARD > 0 and UFOAbduction then
								UFOAbduction.awardGolden(plr, CONFIG.GOLDEN_COIN_REWARD)
							end
						UFOSync:FireClient(plr, "engage", {
							beamGround = b.groundPos,           -- the column center on the ground
							ufoPos = ufoPos,                    -- pull target (toward the saucer)
							pull = effectivePull(),             -- studs/sec lift (variant-adjusted)
							liftHeight = CONFIG.ABDUCT_LIFT_HEIGHT,
							spinRate = CONFIG.BEAM_SPIN_RATE,
							radius = CONFIG.BEAM_RADIUS,
							escapeSensitivity = CONFIG.ESCAPE_SENSITIVITY,
							goInside = goInside,                -- client triggers inside scene if true
							insideCF = insideCF,                -- enclosed-chamber spawn CFrame (or nil)
							insideDuration = CONFIG.INSIDE_UFO_DURATION,
							variant = currentVariant,
						})
						break
					end
				end
			end
		end
	end
end

--======================================================================
-- stopAll(): turn off all beams + release every player (clients restore on
-- their own "release"), and return any object still rising. Called at the
-- end of the ABDUCTION phase (the UFO stays for the ENDING).
--======================================================================
function UFOBeam.stopAll()
	for _, b in ipairs(beams) do
		if b.part then b.part:Destroy() end
		if b.pool then b.pool:Destroy() end
	end
	beams = {}
	-- Tell every engaged player to end their ride + restore to captured spot.
	for plr in pairs(engagedPlayers) do
		if plr and plr.Parent then
			UFOSync:FireClient(plr, "release")
		end
	end
	engagedPlayers = {}
	if UFOAbduction then
		UFOAbduction.releaseAll()
	end
end

--======================================================================
-- cleanup(): destroy all beam instances + force-release players. No leaks.
--======================================================================
function UFOBeam.cleanup()
	UFOBeam.stopAll()
	if beamFolder and beamFolder.Parent then
		beamFolder:Destroy()
	end
	beamFolder = nil
	ufoPos = nil
end

return UFOBeam
