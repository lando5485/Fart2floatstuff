-- ============================================================================================================
-- LANDING IMPACT  (client)
--
-- You fall forty thousand studs and arrive in total silence, with nothing happening. The entire climb is the
-- game, and the moment it ends is currently the one moment with no feedback at all.
--
-- So: a landing now COSTS something to look at. Dust, a thud, and a camera jolt -- all scaled by how hard you
-- actually hit. A hop off a crate barely puffs; a dead drop from Pizza Palms cracks the ground.
--
-- ===== IT IS ALL ONE NUMBER =====
-- Everything below is driven by `t`, a 0..1 "how hard was that" derived from the fall speed at touchdown. Dust
-- count, dust size, thud volume, thud PITCH and camera shake are all just curves on t. That is what keeps a
-- gentle landing from feeling like a scripted event and a huge one from feeling identical to a small one --
-- there is no threshold where the effect "turns on", it grows continuously with the fall.
--
-- ===== THE DUST IS THE COLOUR OF THE FLOOR =====
-- A raycast reads the actual part you landed on and tints the dust to match it. This is why it works on all 14
-- islands without a per-island table: grass throws up green-brown, the toaster throws up grey, Ice Cream Isle
-- throws up pink. A hard-coded dust colour would look wrong on 13 of the 14.
--
-- ===== WHY NOT REUSE CORECLIENT'S LANDING HOOK =====
-- CoreClient already spots the touchdown (it fires LandingEvent) -- but it is at Luau's 200-local ceiling, and
-- one more local in that file silently kills the WHOLE script. So this detects its own landing. The detection
-- is four lines; the alternative is a game that does not boot.
--
-- Client-side: dust and shake are per-viewer by nature. On the server they would replicate instances so every
-- other player could watch a puff of dust they cannot see the cause of.
-- ============================================================================================================

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local Debris       = game:GetService("Debris")
local Workspace    = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ===== TUNING =====
-- The whole feel of this lives in these two numbers. MIN is the speed below which nothing happens at all --
-- it MUST sit above a normal jump's landing speed (~50), or you kick up dust every time you hop, which reads
-- as a bug rather than as weight. MAX is the speed that produces the full effect; anything faster is clamped,
-- so a 40,000-stud drop and a 4,000-stud drop both bottom out at "enormous" rather than one being 10x sillier.
-- Raised 55 -> 95: a plain jump-in-place was landing above 55 in this game and setting off the thud, which
-- read as a bug. 95 sits well clear of any hop, so ONLY a real fall from the air (a drop off a ledge, a
-- landing after flight) makes the smash -- exactly what a jump should NOT do.
local MIN_SPEED = 95    -- studs/sec downward: below this, a landing is silent and invisible (a hop)
local MAX_SPEED = 260   -- studs/sec: at or above this, the effect is at full strength

-- A landing is only a landing if you were actually in the air for a moment. Without this, every respawn and
-- every teleport arrival slams the camera and throws dust, because the character technically "arrives" at speed.
local MIN_AIR_TIME = 0.35

local SHAKE_FROM  = 0.30  -- t below this does not shake the camera. Small landings should not move the screen.
local SHAKE_SECS  = 0.30
local SHAKE_MAX   = 2.2   -- degrees-ish of jolt at t = 1

local THUD_ID     = "rbxassetid://5801257793" -- the low boom already used (and verified working) for meteor/
                                              -- rocket impacts. Deliberately NOT a guessed footstep asset --
                                              -- this repo already carries six dead sound IDs.

-- ===== WHAT DID WE LAND ON? =====
-- Raycast straight down from the feet and take the part's colour. Purely visual, so it fails soft: no hit (or
-- a hit on something odd) just gives a neutral dust, never an error.
local dustParams = RaycastParams.new()
dustParams.FilterType = Enum.RaycastFilterType.Exclude

local function floorColor(char, hrp)
	dustParams.FilterDescendantsInstances = { char }
	local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -12, 0), dustParams)
	if hit and hit.Instance and hit.Instance:IsA("BasePart") then
		return hit.Instance.Color
	end
	return Color3.fromRGB(150, 140, 125) -- neutral dirt, if we somehow landed on nothing
end

-- ===== FOOTPRINTS =====
-- Dust says "you hit the ground". Footprints say "you were HERE" -- they are the only thing in the game that
-- leaves any trace of the player having existed, and a trail behind you is what turns a floor into ground.
--
-- They are pressed, not painted: each print is tinted a DARKER version of the floor it is on, so it reads as
-- compressed earth rather than as a black sticker. On grass it is dark green; on the toaster, dark grey.
local FOOT_FADE   = 2.6   -- seconds a print takes to fade away completely
local STEP_DIST   = 2.6   -- studs of travel between prints -- roughly one stride at default WalkSpeed
local FOOT_WIDTH  = 0.55
local FOOT_LEN    = 1.05
local FOOT_SPREAD = 0.55  -- studs either side of centre, so left and right prints do not sit on top of each other
local FOOT_ALPHA  = 0.35  -- starting transparency. Fully opaque prints look like paint, not pressure.
local FOOT_DARK   = 0.65  -- how far the print is lerped toward black from the floor's own colour (was 0.45)
local MAX_PRINTS  = 40    -- hard cap. Without it, a long walk quietly spawns hundreds of parts and the frame
                          -- rate dies somewhere on island 9 for reasons nobody can find.

local prints = {}         -- oldest-first; the cap is enforced by destroying prints[1]

local function stampFoot(char, hrp, sign)
	dustParams.FilterDescendantsInstances = { char }
	local origin = hrp.Position
	local hit = Workspace:Raycast(origin, Vector3.new(0, -8, 0), dustParams)
	if not (hit and hit.Instance and hit.Instance:IsA("BasePart")) then return end

	-- Lay the print FLAT ON THE SURFACE, not flat on the world. Bean Farm has slopes and ramps, and a print
	-- that is level with the world sinks half into a hillside and floats off the other half.
	local up = hit.Normal
	local look = hrp.CFrame.LookVector
	local right = look:Cross(up)
	if right.Magnitude < 0.01 then return end -- looking straight up/down the surface normal: no sane facing
	right = right.Unit
	local fwd = up:Cross(right).Unit

	local pos = hit.Position + up * 0.03 + right * (FOOT_SPREAD * sign) -- 0.03 above, or it z-fights the floor

	local p = Instance.new("Part")
	p.Name         = "Footprint"
	p.Size         = Vector3.new(FOOT_WIDTH, 0.05, FOOT_LEN)
	p.CFrame       = CFrame.fromMatrix(pos, right, up, -fwd)
	p.Anchored     = true
	p.CanCollide   = false
	p.CanQuery     = false  -- so the NEXT footprint's raycast does not land on THIS one and stack prints
	p.CanTouch     = false  -- upward forever
	p.Material     = Enum.Material.SmoothPlastic
	p.Color        = hit.Instance.Color:Lerp(Color3.new(0, 0, 0), FOOT_DARK) -- pressed earth: the floor, darker
	p.Transparency = FOOT_ALPHA
	p.Parent       = Workspace

	local c = Instance.new("SpecialMesh") -- a squashed sphere reads as a soft oval sole; a bare block reads
	c.MeshType = Enum.MeshType.Sphere     -- as a domino
	c.Scale    = Vector3.new(1, 1, 1)
	c.Parent   = p

	prints[#prints + 1] = p
	if #prints > MAX_PRINTS then
		local oldest = table.remove(prints, 1)
		if oldest then oldest:Destroy() end
	end

	TweenService:Create(p, TweenInfo.new(FOOT_FADE, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	Debris:AddItem(p, FOOT_FADE + 0.2)
end

-- ===== THE DUST =====
-- Emitted in ONE burst from a temporary anchored part at the feet, not from an emitter parented to the
-- character -- a burst that follows you around as you walk away is not dust, it is a jetpack.
local function puff(pos, color, t)
	local anchor = Instance.new("Part")
	anchor.Name         = "LandingDust"
	anchor.Size         = Vector3.new(0.6, 0.2, 0.6) -- thin plate: an emitter fires from a part's whole VOLUME,
	anchor.Anchored     = true                       -- so a big cube would spray dust from inside your shins
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CanTouch     = false
	anchor.Transparency = 1
	anchor.CFrame       = CFrame.new(pos) -- unrotated on purpose, so "up" is world up
	anchor.Parent       = Workspace

	local e = Instance.new("ParticleEmitter")
	e.Texture      = "rbxassetid://243664672" -- Roblox's stock soft smoke puff
	e.Color        = ColorSequence.new(color)
	e.Orientation  = Enum.ParticleOrientation.FacingCamera -- identical thickness from any viewing angle
	e.LightInfluence = 0.6
	e.Rotation     = NumberRange.new(0, 360) -- each puff rotated differently, or the ring looks stamped
	e.RotSpeed     = NumberRange.new(-40, 40)

	-- Dust goes OUT, not up. Real impact dust is thrown sideways along the ground and only drifts upward as it
	-- slows -- a plume that shoots straight up reads as a smoke grenade, not as something hitting the floor.
	e.SpreadAngle  = Vector2.new(85, 85)
	e.Speed        = NumberRange.new(6 + 22 * t, 12 + 40 * t)
	e.Acceleration = Vector3.new(0, 5, 0) -- gentle lift as it slows, so it billows instead of dropping flat
	e.Drag         = 3.5                  -- and it DIES quickly, which is what makes it read as heavy dust

	e.Lifetime     = NumberRange.new(0.5, 0.9 + 0.7 * t)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2 + 4.5 * t),
		NumberSequenceKeypoint.new(1, 3.5 + 11 * t),   -- expands as it disperses
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Rate    = 0
	e.Enabled = false
	e.Parent  = anchor

	e:Emit(math.floor(9 + 46 * t)) -- one burst; count scales with the fall
	Debris:AddItem(anchor, 3)      -- the anchor outlives the puffs, then removes itself. Nothing accumulates.
end

-- ===== THE THUD =====
-- Volume AND pitch both scale. Pitch is the important one: the same sample played LOWER reads as bigger and
-- heavier, which is why a huge landing sounds like a different event rather than just a louder small one.
local function thud(hrp, t)
	local s = Instance.new("Sound")
	s.SoundId       = THUD_ID
	s.Volume        = 0.25 + 0.75 * t
	s.PlaybackSpeed = 1.45 - 0.75 * t  -- light landing = a quick high tap; heavy = a deep slow boom
	s.RollOffMaxDistance = 220
	s.Parent = hrp
	s:Play()
	Debris:AddItem(s, 6)
end

-- ===== THE CAMERA =====
-- Written to the camera's CFrame each frame and DECAYING to zero, then simply stopped -- it never writes a
-- "restore" value. Anything that snapshots the camera and puts it back will fight the player's own mouse look
-- and stutter. Fading the offset to nothing leaves the camera exactly where the player pointed it.
local function shake(t)
	if t < SHAKE_FROM then return end
	local mag = SHAKE_MAX * t
	task.spawn(function()
		local cam = Workspace.CurrentCamera
		local t0 = os.clock()
		while os.clock() - t0 < SHAKE_SECS do
			cam = Workspace.CurrentCamera
			if not cam then return end
			local left = 1 - (os.clock() - t0) / SHAKE_SECS  -- linear fade to zero
			local m = math.rad(mag * left)
			cam.CFrame = cam.CFrame * CFrame.Angles(
				(math.random() - 0.5) * m,
				(math.random() - 0.5) * m,
				(math.random() - 0.5) * m * 0.5
			)
			RunService.RenderStepped:Wait()
		end
	end)
end

-- ===== DETECTION =====
-- The touchdown FRAME is useless for measuring the fall: the collision has already killed the velocity by the
-- time FloorMaterial changes. So the fall speed is sampled continuously while airborne and the PEAK downward
-- speed is remembered -- that peak is what the landing is scored on.
local function watch(char)
	local hum = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not (hum and hrp) then return end

	local airborne   = false
	local airStart   = 0
	local peakFall   = 0    -- studs/sec, positive = downward
	local wasAir     = hum.FloorMaterial == Enum.Material.Air

	-- Footprints are spaced by DISTANCE TRAVELLED, not by a timer. A timer would drop prints in a heap while
	-- you stand still and spread them miles apart when a speed boost is active; distance gives a real stride
	-- that automatically stays correct at any WalkSpeed.
	local walked   = 0
	local lastPos  = hrp.Position
	local footSign = 1

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not (char.Parent and hrp.Parent and hum.Parent) then
			conn:Disconnect()
			return
		end

		local inAir = hum.FloorMaterial == Enum.Material.Air

		-- ---- FOOTPRINTS: only while actually walking on the ground ----
		local here = hrp.Position
		if inAir then
			lastPos = here -- do not bank distance covered in flight, or you touch down and instantly stamp a
			               -- print for every stud you flew
		else
			local flat = Vector3.new(here.X - lastPos.X, 0, here.Z - lastPos.Z) -- horizontal only: standing on
			lastPos = here                                                       -- a lift is not walking
			walked += flat.Magnitude
			if walked >= STEP_DIST then
				walked = 0
				stampFoot(char, hrp, footSign)
				footSign = -footSign -- alternate left, right, left...
			end
		end

		if inAir then
			if not airborne then
				airborne = true
				airStart = os.clock()
				peakFall = 0
			end
			-- Only DOWNWARD motion counts. The whole ascent is upward velocity, and a flight that rose 40,000
			-- studs and then gently drifted down is a soft landing, not a huge one.
			local vy = hrp.AssemblyLinearVelocity.Y
			if vy < 0 then
				local fall = -vy
				if fall > peakFall then peakFall = fall end
			end
		elseif wasAir then
			-- TOUCHDOWN.
			local airTime = os.clock() - airStart
			if airborne and airTime >= MIN_AIR_TIME and peakFall >= MIN_SPEED then
				local t = math.clamp((peakFall - MIN_SPEED) / (MAX_SPEED - MIN_SPEED), 0, 1)
				-- at the feet, not at the root -- the root is at chest height, and dust from your chest is
				-- not dust, it is a chest wound
				local feet = hrp.Position - Vector3.new(0, hrp.Size.Y * 0.5 + 1.4, 0)
				puff(feet, floorColor(char, hrp), t)
				thud(hrp, t)
				shake(t)
				-- and stamp BOTH feet where you actually came down -- you landed on two feet, not one, and
				-- the prints you leave at the point of impact are the ones worth seeing
				stampFoot(char, hrp, 1)
				stampFoot(char, hrp, -1)
			end
			airborne = false
			peakFall = 0
			walked   = 0  -- do not let a landing immediately trigger a stray third print
		end

		wasAir = inAir
	end)
end

if player.Character then task.spawn(watch, player.Character) end
player.CharacterAdded:Connect(function(c) task.spawn(watch, c) end)

print(("[LandingImpact] ready -- dust + thud + shake scaled by fall speed (%d..%d studs/s), footprints every %.1f studs (fade %.1fs, max %d)")
	:format(MIN_SPEED, MAX_SPEED, STEP_DIST, FOOT_FADE, MAX_PRINTS))
