--======================================================================
-- SECRET CAVE  (LocalScript, per-player)
--======================================================================
-- The 'secretcave' rock is a door. A hidden switch somewhere on the same island opens it, and walking in
-- teleports you to an underground trader who sells things sold nowhere else.
--
-- ===== THE TRICK, AND WHY IT COSTS THE SERVER NOTHING =====
-- There is no underground area in this game. Nothing is modelled below the map. The cave is a sealed stone
-- box THIS SCRIPT builds at runtime, 9000+ studs off to the side in empty space, and the "door" is a
-- ProximityPrompt that calls char:PivotTo() behind a black fade. That is the whole illusion.
--
-- Because a LocalScript builds it, the box does not replicate: nobody else can see it, wander into it, or
-- stand in your trader. Every player gets their own cave at their own offset, so two people in one server
-- never collide. The server carries none of it.
--
-- ===== THE ONE FOOD-REALM-SPECIFIC HAZARD: THE CAVE MUST BE LOW =====
-- Coins here are paid by ALTITUDE, every half second while flying:
--     coins = height * 0.008 + (height / 500) ^ 2        -- height = hrp.Position.Y
-- Put the cave at its island's altitude (island 10 sits at Y 19000) and you have built a coin printer worth
-- roughly 1,450 coins a second to a player standing still inside a sealed room. So the box sits at Y = 180 --
-- high enough to clear FallenPartsDestroyHeight (-500), low enough that even if flight leaks through, the
-- trickle is under a coin a second. _G.caveNoFly is set as well; belt and braces.
--
-- ===== WHY THE MARKER IS POLLED, NOT LOOKED UP ONCE =====
-- StreamingEnabled is ON. 'secretcave' is a real Studio Part, possibly thousands of studs up, and it streams
-- in LATE -- a single FindFirstChild at script start reliably returns nil and the door silently never exists.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== TUNING =====
-- (no switch-distance constant any more -- the switch is a Part you place in Studio, not one this script
--  generates, so its position is wherever you put it)
local CAVE_W, CAVE_D, CAVE_H = 90, 90, 26
local VOID_Y           = 180   -- see the altitude note above -- do not raise this to match an island
local FADE_TIME        = 0.35

local doorPart, switchPart, caveModel, savedLighting
local isOpen, busy, inside = false, false, false
local doorRunes, leverArm   -- built props: the glowing cracks on the cliff, and the lever handle that swings

--======================================================================
-- helpers
--======================================================================
local function pollFor(name, timeout)
	-- Streaming means "not there yet" is normal for several seconds. Give up eventually so a typo'd marker
	-- reports itself instead of hanging a thread forever.
	local deadline = os.clock() + (timeout or 45)
	repeat
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("BasePart") and string.lower(d.Name) == name then return d end
		end
		task.wait(1)
	until os.clock() > deadline
	return nil
end

local function part(parent, name, size, cf, color, mat)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.CFrame = cf; p.Color = color
	p.Material = mat or Enum.Material.Slate
	p.Anchored = true; p.CanCollide = true; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--======================================================================
-- THE VISIBLE LEVER  (built on your 'switch' Part, always visible)
--======================================================================
-- This is the ONLY thing a player can see before the secret is found, and that is deliberate: it is the
-- breadcrumb. A kid spots a lever sticking out of the ground, pulls it because it is a lever, and the cliff
-- answers. Nothing marks the cave itself beforehand -- if the door were signposted too, there would be no
-- searching left to do.
--
-- Your 'switch' Part stays invisible and is used purely as a POSITION. Building the lever instead of just
-- un-hiding your block means it reads as a machine you operate, whatever size or shape you drew the marker.
local function buildLever(marker)
	-- ===== IT IS BUILT EXACTLY ON YOUR BLOCK, AND IT STAYS THERE =====
	-- The lever's POSITION is your marker's position, full stop -- the base plate is centred on it, so where
	-- you put the block in Studio is where the lever stands.
	--
	-- Its ORIENTATION deliberately is NOT copied wholesale. Reading marker.CFrame would inherit any tilt on
	-- the block -- and a block dropped on a slope, or nudged with rotate on, is very often a few degrees off
	-- without looking it. That tilt would build a lever leaning into the ground, or lying on its side. So only
	-- the Y-axis heading is kept (which way it faces); UP is always world-up.
	local pos = marker.Position
	local look = marker.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)          -- flatten the marker's facing to a pure compass heading
	if look.X * look.X + look.Z * look.Z < 1e-6 then  -- marker pointing straight up/down: no usable heading
		yaw = 0
	end
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)

	local m = Instance.new("Model"); m.Name = "SecretLever"

	-- stone footing, CENTRED ON THE MARKER so the lever sits on the exact spot rather than beside it
	local foot = part(m, "LeverBase", Vector3.new(3.2, 1, 3.2), base,
		Color3.fromRGB(88, 84, 78), Enum.Material.Slate)
	foot.CanCollide = true

	-- the housing the arm pivots in
	part(m, "LeverHousing", Vector3.new(1.6, 1.2, 1.6), base * CFrame.new(0, 0.9, 0),
		Color3.fromRGB(62, 58, 54), Enum.Material.Metal)

	-- ===== THE FRAME AND THE RATCHET =====
	-- A stick in a box reads as debris; a lever held in a rusted frame with a toothed quadrant reads as
	-- MACHINERY -- visibly wired to something. The ratchet teeth are the detail that promises consequences:
	-- levers with ratchets are levers that stay thrown.
	for _, fx in ipairs({ -0.9, 0.9 }) do
		part(m, "LeverFrame", Vector3.new(0.45, 3.2, 0.45), base * CFrame.new(fx, 1.6, 0),
			Color3.fromRGB(96, 74, 52), Enum.Material.CorrodedMetal)
	end
	part(m, "LeverFrameBar", Vector3.new(2.3, 0.4, 0.4), base * CFrame.new(0, 3.2, 0),
		Color3.fromRGB(96, 74, 52), Enum.Material.CorrodedMetal)
	for i = 0, 3 do
		local a = math.rad(-46 + i * 26)   -- a quarter-arc of teeth in the arm's swing plane
		local tooth = part(m, "RatchetTooth", Vector3.new(0.5, 0.3, 0.22),
			base * CFrame.new(0, 1.3 + math.cos(a) * 1.15, math.sin(a) * 1.15) * CFrame.Angles(a, 0, 0),
			Color3.fromRGB(120, 116, 108), Enum.Material.Metal)
		tooth.CanCollide = false
	end

	-- The mechanical dressing that takes it from "shaped like a lever" to "built like one" -- still all
	-- blocks and cylinders, no meshes: a pivot bolt run right through the housing with hex-ish heads on
	-- both sides, gussets bracing the frame to the footing, and a little junction box with a live LED and a
	-- wire disappearing into the ground. The wire is the storytelling part: THIS is how the lever reaches
	-- the door.
	local bolt = part(m, "PivotBolt", Vector3.new(2.1, 0.45, 0.45), base * CFrame.new(0, 1.3, 0),
		Color3.fromRGB(140, 140, 148), Enum.Material.Metal)
	bolt.Shape = Enum.PartType.Cylinder
	bolt.CanCollide = false
	for _, bx in ipairs({ -1.12, 1.12 }) do
		part(m, "BoltHead", Vector3.new(0.28, 0.62, 0.62), base * CFrame.new(bx, 1.3, 0)
			* CFrame.Angles(math.rad(30), 0, 0), Color3.fromRGB(120, 120, 128), Enum.Material.Metal)
			.CanCollide = false
	end
	for _, g in ipairs({ { -0.9, 35 }, { 0.9, -35 } }) do
		part(m, "FrameGusset", Vector3.new(0.32, 1.1, 0.32),
			base * CFrame.new(g[1] * 1.35, 0.6, 0) * CFrame.Angles(0, 0, math.rad(g[2])),
			Color3.fromRGB(96, 74, 52), Enum.Material.CorrodedMetal).CanCollide = false
	end
	local jbox = part(m, "JunctionBox", Vector3.new(0.55, 0.75, 0.38), base * CFrame.new(0.9, 2.35, 0.42),
		Color3.fromRGB(70, 74, 66), Enum.Material.Metal)
	jbox.CanCollide = false
	local jled = part(m, "JunctionLed", Vector3.new(0.14, 0.14, 0.06), base * CFrame.new(0.9, 2.55, 0.63),
		Color3.fromRGB(120, 255, 140), Enum.Material.Neon)
	jled.CanCollide = false; jled.CastShadow = false
	part(m, "JunctionWire", Vector3.new(0.1, 2.6, 0.1), base * CFrame.new(0.98, 1.05, 0.5)
		* CFrame.Angles(0, 0, math.rad(-4)), Color3.fromRGB(34, 32, 36), Enum.Material.SmoothPlastic)
		.CanCollide = false

	-- caution stripe on the footing, and the gang's ring-and-slash chalked on the housing -- the SAME mark
	-- the door wears. A kid who finds the lever has already met the symbol when the doorway reveals it,
	-- which is what makes the two read as one machine owned by one crew.
	part(m, "LeverStripe", Vector3.new(3.3, 0.25, 0.25), base * CFrame.new(0, 0.45, 1.55),
		Color3.fromRGB(245, 205, 48), Enum.Material.SmoothPlastic).CanCollide = false
	for i = 0, 7 do
		if i ~= 2 then   -- one gap, same hurried scrawl as the door's ring
			local a = (i / 8) * math.pi * 2
			local segm = part(m, "LeverMark", Vector3.new(0.28, 0.07, 0.04),
				base * CFrame.new(math.cos(a) * 0.5, 0.9 + math.sin(a) * 0.5, 0.84)
					* CFrame.Angles(0, 0, a + math.pi * 0.5),
				Color3.fromRGB(238, 234, 220), Enum.Material.SmoothPlastic)
			segm.CanCollide = false; segm.CastShadow = false
		end
	end
	part(m, "LeverMarkSlash", Vector3.new(0.07, 1.3, 0.04),
		base * CFrame.new(0, 0.9, 0.84) * CFrame.Angles(0, 0, math.rad(38)),
		Color3.fromRGB(238, 234, 220), Enum.Material.SmoothPlastic).CanCollide = false

	-- THE ARM. Anchored and CFrame-driven rather than hinged: a real HingeConstraint would need unanchored
	-- parts, and an unanchored prop on a cliff edge is a prop that eventually falls off the island.
	leverArm = part(m, "LeverArm", Vector3.new(0.5, 4.2, 0.5),
		base * CFrame.new(0, 2.8, 0) * CFrame.Angles(math.rad(-28), 0, 0),
		Color3.fromRGB(120, 78, 42), Enum.Material.Wood)
	leverArm.CanCollide = false

	-- a bright knob on top -- the bit the eye actually lands on from a distance
	local knob = part(m, "LeverKnob", Vector3.new(1.1, 1.1, 1.1),
		leverArm.CFrame * CFrame.new(0, 2.2, 0), Color3.fromRGB(255, 96, 72), Enum.Material.Neon)
	knob.Shape = Enum.PartType.Ball
	knob.CanCollide = false
	local kl = Instance.new("PointLight")
	kl.Brightness = 1.4; kl.Range = 12; kl.Color = Color3.fromRGB(255, 130, 90); kl.Parent = knob

	-- spark emitter, burst-only: fired the moment the lever is thrown (see pullLever)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxassetid://241876945"
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.25, 0.6)
	sparks.Speed = NumberRange.new(6, 14)
	sparks.Size = NumberSequence.new(0.22)
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90))
	sparks.LightEmission = 1
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Parent = knob

	-- ===== THE IDLE HEARTBEAT =====
	-- Until pulled, the knob breathes red. A small PULSING light catches the eye from far further away than
	-- a static one -- this is the breadcrumb doing its own advertising across the island. The loop ends the
	-- moment the lever is thrown (the Pulled attribute, set in pullLever) and the glow goes steady green.
	task.spawn(function()
		while m.Parent and not knob:GetAttribute("Pulled") do
			TweenService:Create(kl, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Brightness = 0.5 }):Play()
			TweenService:Create(knob, TweenInfo.new(0.9), { Transparency = 0.35 }):Play()
			task.wait(1)
			TweenService:Create(kl, TweenInfo.new(0.9), { Brightness = 1.4 }):Play()
			TweenService:Create(knob, TweenInfo.new(0.9), { Transparency = 0 }):Play()
			task.wait(1)
		end
		knob.Transparency = 0   -- never end mid-fade half-ghosted
	end)

	m.Parent = Workspace

	-- ANCHOR, RE-ASSERTED AFTER PARENTING. part() already anchors, but anchoring only truly settles once the
	-- part is in the world -- and an un-anchored lever on a cliff would slide off and be gone for the session,
	-- taking the only way into the cave with it. Cheap to state twice; expensive to get wrong once.
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end

	local off = (foot.Position - pos).Magnitude
	print(("[SecretCave] lever built ON the 'switch' block at (%.1f, %.1f, %.1f) -- offset %.2f studs, anchored")
		:format(pos.X, pos.Y, pos.Z, off))
	return m, knob
end

-- Swing the arm down when it is pulled. The knob rides with it, which is why it is re-CFramed too.
-- THE THROW: hard swing with overshoot, a burst of sparks off the knob, and the glow flips red -> green --
-- light included, so the pool of light on the ground changes colour too. The sparks read as an old contact
-- arcing: the moment feels ELECTRICAL, like something distant just switched on. Which it did.
local function pullLever(knob)
	if not leverArm then return end
	local down = leverArm.CFrame * CFrame.Angles(math.rad(56), 0, 0)
	TweenService:Create(leverArm, TweenInfo.new(0.45, Enum.EasingStyle.Back), { CFrame = down }):Play()
	if knob then
		knob:SetAttribute("Pulled", true)      -- ends the idle red heartbeat (see buildLever)
		TweenService:Create(knob, TweenInfo.new(0.45, Enum.EasingStyle.Back),
			{ CFrame = down * CFrame.new(0, 2.2, 0) }):Play()
		TweenService:Create(knob, TweenInfo.new(0.6), { Color = Color3.fromRGB(120, 255, 140) }):Play()
		local kl = knob:FindFirstChildOfClass("PointLight")
		if kl then kl.Color = Color3.fromRGB(120, 255, 140); kl.Brightness = 1.4 end
		local sparks = knob:FindFirstChildOfClass("ParticleEmitter")
		if sparks then sparks:Emit(24) end
	end
end

--======================================================================
-- THE CAVE MOUTH  (built ONLY when the lever is pulled)
--======================================================================
-- Nothing here exists until openDoor() calls it. Before that the cliff is just cliff.
local function revealDoor(marker)
	-- ===== BUILT EXACTLY ON YOUR 'secretcave' BLOCK, AND IT STAYS THERE =====
	-- Position AND size both come straight from your block: the opening is centred on it and scaled to it, so
	-- the doorway is however big you drew it, wherever you put it.
	--
	-- Unlike the LEVER, the full CFrame is used here on purpose. The lever ignores the marker's tilt because a
	-- lever must stand upright whatever the block does. A door is the opposite: it has to lie FLAT AGAINST THE
	-- CLIFF FACE, and the block's rotation is the only thing that knows which way that face points. Throwing
	-- it away would paste the opening across the rock at whatever angle it happened to land on.
	--
	-- Both are captured ONCE, here, so nothing that touches the marker afterwards can drag the doorway around.
	local sz = marker.Size
	local cf = marker.CFrame
	local m = Instance.new("Model"); m.Name = "SecretCaveMouth"

	-- ===== THE OPENING IS A CLONE OF YOUR BLOCK =====
	-- Not a panel rebuilt from its numbers. Cloning is EXACT BY CONSTRUCTION: same size, same shape, same
	-- rotation, same position -- and it stays exact if you resize or reshape the block again, with no code to
	-- update. The previous version reconstructed a flat rectangle at 92% scale and 0.4 studs deep, which was
	-- fine for a small block and wrong the moment you enlarged it.
	--
	-- It also survives the block not being a plain Part. A WedgePart, a MeshPart, a union -- a clone matches
	-- all of them; a hand-built Part matches only the first, and would sit inside a wedge as a fat rectangle.
	local mouth = marker:Clone()
	mouth.Name = "Opening"
	mouth:ClearAllChildren()          -- drop the marker's ProximityPrompt etc; the real one lives on the marker
	mouth.CFrame = cf                 -- captured above, so it cannot drift if the marker is touched later
	mouth.Anchored = true
	mouth.CanCollide = false          -- you walk INTO the doorway; it must not be a wall
	mouth.CanQuery = false
	mouth.CastShadow = false
	mouth.Transparency = 0            -- the marker is invisible; this copy is the thing you actually see
	mouth.Color = Color3.fromRGB(6, 5, 8)
	mouth.Material = Enum.Material.SmoothPlastic
	mouth.Reflectance = 0
	mouth.Parent = m

	-- ===== THE GLOW TRACES THE REAL GEOMETRY =====
	-- A SelectionBox adorns the part's ACTUAL outline, so it fits a wedge or a mesh as well as it fits a
	-- block. The old version drew four straight neon bars along a bounding rectangle -- on the enlarged block
	-- those bars would be a rectangle floating around whatever shape you actually made.
	local outline = Instance.new("SelectionBox")
	outline.Adornee = mouth
	outline.LineThickness = math.clamp(math.min(sz.X, sz.Y) * 0.04, 0.12, 0.6) -- scales with the door
	outline.Color3 = Color3.fromRGB(255, 146, 54)
	outline.SurfaceTransparency = 1   -- edges only: a filled overlay would hide the black opening
	outline.Transparency = 1          -- fades in below, so the doorway looks like it CRACKS open
	outline.Parent = mouth
	doorRunes = { outline }

	local pl = Instance.new("PointLight")
	pl.Brightness = 2.5
	pl.Range = math.clamp(math.max(sz.X, sz.Y) * 2, 30, 60)   -- a bigger door lights a bigger area
	pl.Color = Color3.fromRGB(255, 118, 44)
	pl.Parent = mouth

	--==================================================================
	-- DRESSING IT UP
	--==================================================================
	-- Everything below is layered ON the exact clone rather than replacing it, so none of it can knock the
	-- doorway out of alignment with your block. Each piece is scaled from `sz`, so it all grows with the door.

	-- 1. HALO. A slightly larger copy of the same shape, neon and mostly transparent, hugging the opening. It
	--    is a clone too, so on a wedge or a mesh the halo is wedge- or mesh-shaped -- a box would float
	--    around the outside of anything that is not a block.
	local halo = mouth:Clone()
	halo.Name = "Halo"
	halo:ClearAllChildren()
	halo.Size = sz * 1.04
	halo.CFrame = cf
	halo.Material = Enum.Material.Neon
	halo.Color = Color3.fromRGB(196, 68, 34)
	halo.Transparency = 1
	halo.CanCollide = false; halo.CanQuery = false; halo.CastShadow = false
	halo.Parent = m

	-- 2. DEPTH. Two smaller copies at the same centre, progressively darker. Concentric shrinking shapes read
	--    as a tunnel receding into the rock -- and because they are concentric rather than pushed backwards,
	--    it works without knowing which way the block faces (push the wrong way and they'd stick OUT of the
	--    cliff as floating panels).
	local depthLayers, depthScales = {}, { 0.72, 0.46 }
	for i, f in ipairs(depthScales) do
		local layer = mouth:Clone()
		layer.Name = "Depth" .. i
		layer:ClearAllChildren()
		layer.Size = sz * f
		layer.CFrame = cf
		layer.Color = Color3.fromRGB(24 - i * 8, 20 - i * 6, 40 - i * 12)
		layer.Material = Enum.Material.Neon
		layer.Transparency = 0.25 + i * 0.2
		layer.CanCollide = false; layer.CanQuery = false; layer.CastShadow = false
		layer.Parent = m
		depthLayers[i] = layer
	end

	-- ===== THE PULSE =====
	-- Every few seconds a shockwave ring rolls off the opening and the throat layers breathe with it. This
	-- is what separates "active" from "painted on": a static glow is a decal, a doorway with a heartbeat is
	-- a machine that is RUNNING. The ring is another clone of your block, so like everything else here it
	-- matches the door's real shape, whatever that is.
	local pulse = mouth:Clone()
	pulse.Name = "PulseRing"
	pulse:ClearAllChildren()
	pulse.Material = Enum.Material.Neon
	pulse.Color = Color3.fromRGB(255, 146, 54)
	pulse.Transparency = 1
	pulse.CanCollide = false; pulse.CanQuery = false; pulse.CastShadow = false
	pulse.Parent = m
	task.spawn(function()
		while m.Parent do
			-- reset, then swell outward and fade -- reads as a beat coming from INSIDE
			pulse.Size = sz * 1.02
			pulse.CFrame = cf
			pulse.Transparency = 0.45
			TweenService:Create(pulse, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = sz * 1.5, Transparency = 1 }):Play()
			for i, layer in ipairs(depthLayers) do
				layer.Size = sz * depthScales[i]
				layer.CFrame = cf
				TweenService:Create(layer, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{ Size = sz * depthScales[i] * 1.08 }):Play()
			end
			task.wait(3.2)
		end
	end)

	-- 3. MOTES drifting out of the opening. The one thing that stops a doorway reading as a painted-on decal:
	--    something has to be moving.
	local moteAt = Instance.new("Attachment")
	moteAt.Parent = mouth
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxassetid://241876945"
	motes.Rate = math.clamp(sz.X * sz.Y * 0.08, 6, 40)     -- a bigger mouth breathes out more
	motes.Lifetime = NumberRange.new(2.5, 5)
	motes.Speed = NumberRange.new(1.5, 4)
	motes.Size = NumberSequence.new(math.clamp(math.min(sz.X, sz.Y) * 0.06, 0.3, 1.6))
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.3),
		NumberSequenceKeypoint.new(0.75, 0.4), NumberSequenceKeypoint.new(1, 1),
	})
	motes.Color = ColorSequence.new(Color3.fromRGB(255, 170, 90), Color3.fromRGB(180, 40, 30))
	motes.LightEmission = 0.85
	motes.SpreadAngle = Vector2.new(35, 35)
	motes.Acceleration = Vector3.new(0, 1.2, 0)
	motes.Parent = moteAt

	-- 4. CRYSTAL SHARDS around the rim, in the SAME palette as the ones inside the cave. That continuity is
	--    the point: the doorway should look like the first glimpse of the room behind it, not unrelated trim.
	local shardTints = {
		Color3.fromRGB(255, 150, 60), Color3.fromRGB(200, 60, 40), Color3.fromRGB(255, 196, 96),
	}
	local rimX, rimY = sz.X * 0.5, sz.Y * 0.5
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2
		local h = math.clamp(math.min(sz.X, sz.Y) * 0.18, 1.2, 6)
		local shard = part(m, "RimShard", Vector3.new(h * 0.28, h, h * 0.28),
			cf * CFrame.new(math.cos(a) * rimX * 1.02, math.sin(a) * rimY * 1.02, 0)
				* CFrame.Angles(math.rad(20 - (i * 7) % 40), 0, -a + math.pi * 0.5),
			shardTints[(i % 3) + 1], Enum.Material.Neon)
		shard.CanCollide = false; shard.CanQuery = false; shard.CastShadow = false
		shard.Transparency = 0.3
	end

	-- 4b. THE SMUGGLER'S MARK.
	-- A crude chalk symbol scratched on the rock above the opening: a ring with a slash through it, plus
	-- tally scratches. This is the bit that makes the door read as ILLEGAL rather than magical -- a glowing
	-- portal is a fantasy doorway, a glowing portal somebody has TAGGED is a place with an owner and a rule.
	--
	-- Drawn from short bars rather than an image so it needs no uploaded asset, and it is chalk-white against
	-- the amber glow so it reads as hand-drawn on top rather than part of the light.
	-- ===== IT IS DRAWN ON THE DOOR ITSELF, ON BOTH FACES =====
	-- Two things this gets right that the first version did not:
	--
	-- 1. ON THE DOOR, NOT ABOVE IT. It used to sit above the opening on bare rock. The mark belongs on the
	--    thing it is marking -- chalk on the black doorway is what makes it read as tagged.
	-- 2. ON THE SURFACE, NOT THE CENTRE PLANE. It used a flat 0.1-stud offset, which was proud of a thin
	--    block and completely BURIED inside your enlarged one. It now offsets by half the block's depth, so
	--    it sits on the face whatever thickness you drew.
	--
	-- Drawn on BOTH faces because nothing here knows which side of the block the player walks up to -- one
	-- face would be a coin flip between "tagged door" and "blank slab".
	local chalk = Color3.fromRGB(238, 234, 220)
	local markR = math.clamp(math.min(sz.X, sz.Y) * 0.2, 1.2, 6)
	local faceOff = sz.Z * 0.5 + 0.08         -- half the block's depth, plus a hair so it never z-fights
	local markY = sz.Y * 0.16                 -- a little above centre, leaving room for the tallies below

	local function drawMark(zSign)
		local at = cf * CFrame.new(0, markY, faceOff * zSign)
		local segs = 14
		for i = 0, segs - 1 do
			local a1 = (i / segs) * math.pi * 2
			local a2 = ((i + 1) / segs) * math.pi * 2
			local p1 = Vector3.new(math.cos(a1) * markR, math.sin(a1) * markR, 0)
			local p2 = Vector3.new(math.cos(a2) * markR, math.sin(a2) * markR, 0)
			-- one segment left out, so the ring looks scrawled in a hurry rather than compass-drawn
			if i ~= 4 then
				local seg = part(m, "MarkRing", Vector3.new(0.16, (p2 - p1).Magnitude * 1.1, 0.08),
					at * CFrame.new((p1 + p2) * 0.5) * CFrame.Angles(0, 0, -a1 - math.pi * 0.5 + 0.08),
					chalk, Enum.Material.SmoothPlastic)
				seg.CanCollide = false; seg.CanQuery = false; seg.CastShadow = false
			end
		end
		-- the slash through it
		local slash = part(m, "MarkSlash", Vector3.new(0.18, markR * 2.3, 0.08),
			at * CFrame.Angles(0, 0, math.rad(38)), chalk, Enum.Material.SmoothPlastic)
		slash.CanCollide = false; slash.CanQuery = false; slash.CastShadow = false
		-- tally scratches under it: somebody is counting who comes through
		for i = 1, 4 do
			local tick = part(m, "MarkTally", Vector3.new(0.14, markR * 0.75, 0.08),
				at * CFrame.new((i - 2.5) * markR * 0.4, -markR * 1.75, 0)
					* CFrame.Angles(0, 0, math.rad(9 * i - 22)),
				chalk, Enum.Material.SmoothPlastic)
			tick.CanCollide = false; tick.CanQuery = false; tick.CastShadow = false
		end
		-- the crossing scratch through the tallies -- four and a bar through them, a count of five
		local cross = part(m, "MarkTallyCross", Vector3.new(0.14, markR * 1.5, 0.08),
			at * CFrame.new(0, -markR * 1.75, 0) * CFrame.Angles(0, 0, math.rad(74)),
			chalk, Enum.Material.SmoothPlastic)
		cross.CanCollide = false; cross.CanQuery = false; cross.CastShadow = false
	end

	drawMark(1)
	drawMark(-1)

	-- 5. RUBBLE at the foot, as if the rock genuinely broke rather than dissolving politely.
	for i = 1, 7 do
		local s = math.clamp(math.min(sz.X, sz.Y) * 0.1, 0.8, 3)
		local r = part(m, "Rubble", Vector3.new(s, s * 0.7, s),
			cf * CFrame.new((i - 4) * sz.X * 0.16, -rimY - s * 0.3, (i % 3) - 1)
				* CFrame.Angles(i * 0.7, i * 1.3, i * 0.4),
			i % 2 == 0 and Color3.fromRGB(70, 66, 60) or Color3.fromRGB(52, 48, 44), Enum.Material.Slate)
		r.CanCollide = false; r.CastShadow = false
	end

	m.Parent = Workspace

	-- ANCHOR, RE-ASSERTED AFTER PARENTING -- same reason as the lever. part() anchors on creation, but that
	-- only truly settles once the part is in the world, and a doorway that drifts off the cliff face leaves
	-- the Enter prompt sitting on bare rock with the opening visibly somewhere else.
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end

	local off = (mouth.Position - marker.Position).Magnitude
	print(("[SecretCave] doorway CLONED from the 'secretcave' block at (%.1f, %.1f, %.1f) -- size %.1f x %.1f x %.1f, shape %s, offset %.2f studs, anchored")
		:format(marker.Position.X, marker.Position.Y, marker.Position.Z, sz.X, sz.Y, sz.Z,
			marker.ClassName .. (marker:IsA("Part") and ("/" .. marker.Shape.Name) or ""), off))

	-- fade the seams in, then keep them breathing so the opening never looks like a static decal
	for _, seam in ipairs(doorRunes) do
		TweenService:Create(seam, TweenInfo.new(0.9), { Transparency = 0.15 }):Play()
	end
	task.spawn(function()
		-- gated on m.Parent so this thread dies with the model instead of looping forever
		while m.Parent do
			for _, seam in ipairs(doorRunes) do
				TweenService:Create(seam, TweenInfo.new(1.3), { Transparency = 0.45 }):Play()
			end
			task.wait(1.4)
			for _, seam in ipairs(doorRunes) do
				TweenService:Create(seam, TweenInfo.new(1.3), { Transparency = 0.15 }):Play()
			end
			task.wait(1.4)
		end
	end)
	return m
end

local function toast(msg, color)
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(function() _G.NotifyCenter.push({ text = msg, color = color or Color3.fromRGB(255, 214, 120) }) end)
	else
		print("[SecretCave] " .. msg)
	end
end

-- Black wipe. Every teleport hides behind one, because PivotTo is instant and without the cover you see the
-- world snap -- which reads as a glitch, not as walking through a door.
local fadeGui = Instance.new("ScreenGui")
fadeGui.Name = "SecretCaveFade"; fadeGui.IgnoreGuiInset = true; fadeGui.ResetOnSpawn = false
fadeGui.DisplayOrder = 500; fadeGui.Enabled = false; fadeGui.Parent = playerGui
local fade = Instance.new("Frame")
fade.Size = UDim2.fromScale(1, 1); fade.BackgroundColor3 = Color3.new(0, 0, 0)
fade.BackgroundTransparency = 1; fade.Parent = fadeGui

local function withFade(midpoint)
	fadeGui.Enabled = true
	TweenService:Create(fade, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 0 }):Play()
	task.wait(FADE_TIME)
	pcall(midpoint)
	task.wait(0.1)
	TweenService:Create(fade, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 1 }):Play()
	task.wait(FADE_TIME)
	fadeGui.Enabled = false
end

--======================================================================
-- THE CAVE (built once, on first entry -- not at startup)
--======================================================================
-- Built lazily so a player who never finds the switch never pays for the geometry.
-- The build's return table (entry CFrame + prompts) is CACHED here. The old early-return checked whether the
-- cave existed and then returned NOTHING -- so the FIRST visit worked, and every visit after "Climb Out" hit
-- `caveRefs = buildCave()` getting nil, pivoted to nil inside the fade's pcall, and silently left the player
-- standing on the surface staring at a fade that cleared onto nothing. Entering again must hand back the same
-- refs the first build produced.
local builtRefs
local function buildCave()
	if builtRefs and builtRefs.model.Parent then return builtRefs end

	-- Each player's box gets its own corner of the void, derived from their UserId. Two players in one server
	-- must never share coordinates or they would see each other's trader through the walls.
	local ox = 9000 + (player.UserId % 97) * 300
	local oz = 9000 + (player.UserId % 61) * 300
	local origin = Vector3.new(ox, VOID_Y, oz)

	local m = Instance.new("Model"); m.Name = "SecretCaveRoom"
	local rock, dark = Color3.fromRGB(74, 68, 62), Color3.fromRGB(46, 42, 38)

	-- SEALED BOX. The ceiling is not decoration: without it a player who fart-flies indoors leaves the room
	-- and ends up floating in empty blue void with no way back but dying.
	-- SmoothPlastic to match the facet plates laid over it -- the sliver of base floor visible between
	-- facets must not be the one realistic-textured surface in a stylized room
	part(m, "Floor",   Vector3.new(CAVE_W, 2, CAVE_D), CFrame.new(origin), rock, Enum.Material.SmoothPlastic)
	part(m, "Ceiling", Vector3.new(CAVE_W, 2, CAVE_D), CFrame.new(origin + Vector3.new(0, CAVE_H, 0)), dark)
	part(m, "WallN", Vector3.new(CAVE_W, CAVE_H, 2), CFrame.new(origin + Vector3.new(0, CAVE_H/2, -CAVE_D/2)), rock)
	part(m, "WallS", Vector3.new(CAVE_W, CAVE_H, 2), CFrame.new(origin + Vector3.new(0, CAVE_H/2,  CAVE_D/2)), rock)
	part(m, "WallE", Vector3.new(2, CAVE_H, CAVE_D), CFrame.new(origin + Vector3.new( CAVE_W/2, CAVE_H/2, 0)), rock)
	part(m, "WallW", Vector3.new(2, CAVE_H, CAVE_D), CFrame.new(origin + Vector3.new(-CAVE_W/2, CAVE_H/2, 0)), rock)

	-- WHERE THE COUNTER STANDS. Declared HERE, before any of the dressing, because the market props below
	-- (coins, strongbox, scales, rug) all position themselves relative to it. Left where it used to be -- down
	-- in the trader section -- every one of those would read `stallCF` as a nil global and buildCave would
	-- error out, leaving no cave at all. Same trap that has bitten this file twice already.
	local stallCF = CFrame.new(origin + Vector3.new(0, 1, -18))

	-- ===== MAKING IT LOOK LIKE A CAVE AND NOT A BOX =====
	-- The room was six grey slabs. Everything below is there to break up those flat planes, because a sealed
	-- rectangle reads as "unfinished level" no matter how good the trader in it is.

	-- THE RANDOM SOURCE, DECLARED BEFORE ANYTHING THAT ROLLS IT. This line used to live inside section 1,
	-- BELOW the ground facets -- so the facet loop called `rnd` before it existed, got a nil global, and the
	-- whole build crashed on the first Enter ("attempt to call a nil value", the bug that made the cave
	-- unenterable). Deterministic on purpose: the cave looks the SAME every visit, because a room that
	-- reshuffles itself feels broken.
	local seed = 7
	local function rnd(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return (seed / 2147483648) * n
	end

	-- 0. THE GROUND. The floor was one flat slab, and a flat slab is the least low-poly thing there is --
	--    the style lives in FACETS. Big irregular rock plates at slightly different heights and small tilts,
	--    in three alternating stone tones, so light breaks differently across every edge and the ground
	--    reads as carved planes instead of a tabletop.
	--
	--    Collidable ON PURPOSE: they are 0.35-0.75 studs proud at up to ~4 degrees, well inside Roblox's
	--    automatic step-up, so the player walks over them smoothly but FEELS ground that is not billiard-flat.
	-- SMOOTHPLASTIC, NOT SLATE. This is what "low-poly, not realistic" hinges on: Slate carries a baked
	-- photographic rock texture, and no amount of chunky geometry looks stylized under a realistic texture.
	-- SmoothPlastic is pure flat shading -- each plate becomes one clean facet of colour, which IS the
	-- low-poly look. Tilts are also doubled so the facets read as deliberate angles, not imperfections.
	for i = 1, 26 do
		local facet = part(m, "RockFacet",
			Vector3.new(6 + rnd(9), 0.4 + rnd(0.6), 6 + rnd(9)),
			CFrame.new(origin + Vector3.new(rnd(76) - 38, 1 + rnd(0.3), rnd(76) - 38))
				* CFrame.Angles(rnd(0.2) - 0.1, rnd(6.2), rnd(0.2) - 0.1),
			({ Color3.fromRGB(104, 94, 102), Color3.fromRGB(84, 74, 88), Color3.fromRGB(118, 106, 104) })[(i % 3) + 1],
			Enum.Material.SmoothPlastic)
		facet.CastShadow = false
	end

	-- 1. ROUGH THE WALLS. Boulders of varied size and random tilt pushed against the inside faces, so the eye
	--    never gets a clean 90-degree corner or an unbroken straight edge to lock onto.
	for i = 1, 46 do
		local a = (i / 46) * math.pi * 2
		local r = CAVE_W * 0.46
		local s = 5 + rnd(9)
		local b = part(m, "Boulder", Vector3.new(s, s * (0.7 + rnd(0.6)), s),
			CFrame.new(origin + Vector3.new(math.cos(a) * r, rnd(CAVE_H * 0.8), math.sin(a) * r))
				* CFrame.Angles(rnd(0.6), rnd(6.2), rnd(0.6)),
			i % 3 == 0 and dark or rock, Enum.Material.Slate)
		b.CanCollide = false          -- decoration only; the flat walls behind them do the actual containing
	end

	-- 2. STALAGMITES from the floor and STALACTITES from the ceiling, in matched pairs so the room reads as
	--    one continuous rock formation rather than two decorated surfaces.
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2 + rnd(0.4)
		local r = 14 + rnd(26)
		local h = 4 + rnd(9)
		local px, pz = math.cos(a) * r, math.sin(a) * r
		local up = part(m, "Stalagmite", Vector3.new(h, 2 + rnd(2.5), 2 + rnd(2.5)),
			CFrame.new(origin + Vector3.new(px, 1 + h / 2, pz)) * CFrame.Angles(0, 0, math.rad(90)),
			dark, Enum.Material.Slate)
		up.Shape = Enum.PartType.Cylinder
		up.CanCollide = false
		if i % 2 == 0 then
			local dh = 3 + rnd(7)
			local down = part(m, "Stalactite", Vector3.new(dh, 1.6 + rnd(2), 1.6 + rnd(2)),
				CFrame.new(origin + Vector3.new(px + rnd(4) - 2, CAVE_H - dh / 2, pz + rnd(4) - 2))
					* CFrame.Angles(0, 0, math.rad(90)),
				dark, Enum.Material.Slate)
			down.Shape = Enum.PartType.Cylinder
			down.CanCollide = false
		end
	end

	-- 3. GLOWING CRYSTALS in clusters. These are the main light source besides the trader's lamp, and the
	--    reason the cave has any colour in it at all -- bare slate under one warm bulb is just brown.
	-- Purple / green / orange -- the accent triad the whole room runs on. The crystals, the machinery lights
	-- and the conveyor cargo all draw from these three, so the room reads as one deliberate palette instead
	-- of a random handful of glowing things.
	local crystalTints = {
		Color3.fromRGB(180, 120, 255), Color3.fromRGB(120, 255, 140), Color3.fromRGB(255, 165, 70),
	}
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2 + 0.3
		local r = 26 + rnd(14)
		local baseAt = origin + Vector3.new(math.cos(a) * r, 1, math.sin(a) * r)
		local tint = crystalTints[(i % 3) + 1]
		for _ = 1, 3 do   -- a cluster, not a lone spike -- crystals grow in bunches
			local ch = 3 + rnd(5)
			local cry = part(m, "Crystal", Vector3.new(1 + rnd(1.2), ch, 1 + rnd(1.2)),
				CFrame.new(baseAt + Vector3.new(rnd(5) - 2.5, ch / 2, rnd(5) - 2.5))
					* CFrame.Angles(rnd(0.5) - 0.25, rnd(6.2), rnd(0.5) - 0.25),
				tint, Enum.Material.Neon)
			cry.CanCollide = false
			cry.Transparency = 0.25
		end
		local cl = Instance.new("PointLight")
		cl.Brightness = 1.6; cl.Range = 26; cl.Color = tint
		cl.Parent = part(m, "CrystalGlow", Vector3.new(0.4, 0.4, 0.4),
			CFrame.new(baseAt + Vector3.new(0, 3, 0)), tint, Enum.Material.Neon)
	end

	-- 4. A POOL. Still water catches the crystal light and gives the floor something that is not stone.
	local pool = part(m, "Pool", Vector3.new(26, 0.6, 20),
		CFrame.new(origin + Vector3.new(-24, 1.1, 16)), Color3.fromRGB(40, 90, 120), Enum.Material.Glass)
	pool.Transparency = 0.35
	pool.Reflectance = 0.35
	pool.CanCollide = false
	part(m, "PoolRim", Vector3.new(29, 1, 23), CFrame.new(origin + Vector3.new(-24, 0.9, 16)),
		Color3.fromRGB(58, 54, 50), Enum.Material.Slate).CanCollide = false

	-- 5. DUST IN THE AIR. Cheap, and it is what stops a static room feeling like a screenshot.
	local dustAt = Instance.new("Attachment")
	dustAt.Position = Vector3.new(0, CAVE_H * 0.5, 0)
	dustAt.Parent = part(m, "DustAnchor", Vector3.new(0.2, 0.2, 0.2), CFrame.new(origin),
		rock, Enum.Material.Slate)
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxassetid://241876945"
	dust.Rate = 26
	dust.Lifetime = NumberRange.new(6, 12)
	dust.Speed = NumberRange.new(0.4, 1.4)
	dust.Size = NumberSequence.new(0.35)
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.75),
		NumberSequenceKeypoint.new(0.7, 0.75), NumberSequenceKeypoint.new(1, 1),
	})
	dust.Color = ColorSequence.new(Color3.fromRGB(220, 220, 235))
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Acceleration = Vector3.new(0.3, -0.15, 0.2)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Parent = dustAt

	--==================================================================
	-- 6. THE BLACK MARKET
	--==================================================================
	-- The room needs to read as somewhere a trader operates because nobody is allowed to know he does. That is
	-- almost entirely LIGHTING and CLUTTER: pretty even lanterns say "shop", bare bulbs on a sagging wire over
	-- stacked crates say "this was set up in a hurry and can be packed away fast".

	-- 6a. STRUNG BULBS. A drooping cable across the ceiling with bare bulbs hanging off it. The sag is the
	--     detail that sells it -- a straight wire reads as installed, a sagging one reads as rigged.
	local bulbCount = 9
	for i = 0, bulbCount do
		local t = i / bulbCount
		local x = (t - 0.5) * CAVE_W * 0.78
		local sag = math.sin(t * math.pi) * 4.5              -- lowest in the middle of the span
		local at = origin + Vector3.new(x, CAVE_H - 3 - sag, -6)
		if i < bulbCount then                                 -- a cable segment linking this bulb to the next
			local t2 = (i + 1) / bulbCount
			local x2 = (t2 - 0.5) * CAVE_W * 0.78
			local at2 = origin + Vector3.new(x2, CAVE_H - 3 - math.sin(t2 * math.pi) * 4.5, -6)
			local mid = (at + at2) * 0.5
			local wire = part(m, "Cable", Vector3.new(0.12, 0.12, (at2 - at).Magnitude),
				CFrame.lookAt(mid, at2), Color3.fromRGB(28, 26, 24), Enum.Material.Metal)
			wire.CanCollide = false
		end
		local bulb = part(m, "Bulb", Vector3.new(0.7, 0.9, 0.7), CFrame.new(at),
			Color3.fromRGB(255, 176, 92), Enum.Material.Neon)
		bulb.Shape = Enum.PartType.Ball
		bulb.CanCollide = false
		local bl = Instance.new("PointLight")
		bl.Brightness = 1.1; bl.Range = 22; bl.Color = Color3.fromRGB(255, 168, 92); bl.Parent = bulb
		-- one bulb in three flickers, on its own offset rhythm -- a whole string flickering in sync looks
		-- like a broken script, one bad bulb looks like a bad bulb
		if i % 3 == 0 then
			task.spawn(function()
				while m.Parent do
					task.wait(1.5 + rnd(3))
					for _ = 1, 2 + rnd(3) do
						bl.Brightness = 0.15; bulb.Transparency = 0.55
						task.wait(0.04 + rnd(0.08))
						-- restore to a QUARTER of the built value -- the final pass cuts all lights to 25%,
						-- and flickering back to full would make every bad bulb the brightest in the room
						bl.Brightness = 0.28; bulb.Transparency = 0
						task.wait(0.05 + rnd(0.1))
					end
				end
			end)
		end
	end

	-- 6b. BRAZIERS. Open fire in a rusted drum -- warmth, and the smoke gives the air something to catch.
	for _, bx in ipairs({ -30, 30 }) do
		local drumAt = origin + Vector3.new(bx, 2.5, -26)
		local drum = part(m, "Brazier", Vector3.new(3.4, 4, 3.4), CFrame.new(drumAt),
			Color3.fromRGB(78, 46, 30), Enum.Material.CorrodedMetal)
		drum.Shape = Enum.PartType.Cylinder
		drum.CFrame = CFrame.new(drumAt) * CFrame.Angles(0, 0, math.rad(90))
		local emberAt = Instance.new("Attachment")
		emberAt.Position = Vector3.new(0, 2.2, 0); emberAt.Parent = drum
		local fire = Instance.new("Fire")
		fire.Heat = 8; fire.Size = 7
		fire.Color = Color3.fromRGB(255, 150, 60); fire.SecondaryColor = Color3.fromRGB(120, 40, 10)
		fire.Parent = drum
		local fl = Instance.new("PointLight")
		fl.Brightness = 2.2; fl.Range = 28; fl.Color = Color3.fromRGB(255, 130, 60); fl.Parent = drum
	end

	-- 6c. THE STOCK. Crates and barrels stacked against the walls, some open, a couple under tarps. Covered
	--     goods are what make it look like contraband rather than inventory -- you are not meant to see it.
	local crateCols = { Color3.fromRGB(104, 70, 38), Color3.fromRGB(88, 58, 32), Color3.fromRGB(120, 84, 46) }
	for i = 1, 22 do
		local a = (i / 22) * math.pi * 2 + 0.9
		local r = CAVE_W * 0.36 - rnd(7)
		local px, pz = math.cos(a) * r, math.sin(a) * r
		local stack = 1 + math.floor(rnd(2.4))               -- 1-3 high, so the silhouette is uneven
		for s = 0, stack - 1 do
			local cs = 3.4 + rnd(1.6)
			local crate = part(m, "Crate", Vector3.new(cs, cs * 0.85, cs),
				CFrame.new(origin + Vector3.new(px + rnd(1.6) - 0.8, 1.5 + s * cs * 0.9, pz + rnd(1.6) - 0.8))
					* CFrame.Angles(0, rnd(6.2), 0),
				crateCols[(i + s) % 3 + 1], Enum.Material.WoodPlanks)
			crate.CanCollide = false
			-- slat detail, so a crate is not a plain cube
			local slat = part(m, "CrateSlat", Vector3.new(cs * 1.02, cs * 0.12, cs * 1.02),
				crate.CFrame * CFrame.new(0, cs * 0.2, 0), Color3.fromRGB(58, 38, 22), Enum.Material.Wood)
			slat.CanCollide = false
		end
		-- every fourth stack gets a tarp thrown over it
		if i % 4 == 0 then
			local tarp = part(m, "Tarp", Vector3.new(7, 0.3, 7),
				CFrame.new(origin + Vector3.new(px, 1.5 + stack * 3.4, pz)) * CFrame.Angles(rnd(0.2), rnd(6.2), rnd(0.2)),
				Color3.fromRGB(46, 44, 52), Enum.Material.Fabric)
			tarp.CanCollide = false
		end
	end

	-- 6d. BARRELS and SACKS in loose piles.
	for i = 1, 9 do
		local a = (i / 9) * math.pi * 2 + 2.1
		local r = CAVE_W * 0.3 - rnd(9)
		local at = origin + Vector3.new(math.cos(a) * r, 3, math.sin(a) * r)
		local barrel = part(m, "Barrel", Vector3.new(4.4, 3, 3), CFrame.new(at) * CFrame.Angles(0, rnd(6.2), 0),
			Color3.fromRGB(72, 48, 28), Enum.Material.Wood)
		barrel.Shape = Enum.PartType.Cylinder
		barrel.CFrame = CFrame.new(at) * CFrame.Angles(0, rnd(6.2), math.rad(90))
		barrel.CanCollide = false
		local hoop = part(m, "BarrelHoop", Vector3.new(4.5, 3.2, 0.5), barrel.CFrame,
			Color3.fromRGB(48, 44, 40), Enum.Material.Metal)
		hoop.Shape = Enum.PartType.Cylinder
		hoop.CanCollide = false
		local sack = part(m, "Sack", Vector3.new(2.6, 2.2, 2.6),
			CFrame.new(at + Vector3.new(rnd(5) - 2.5, -1.2, rnd(5) - 2.5)) * CFrame.Angles(0, rnd(6.2), 0),
			Color3.fromRGB(120, 104, 74), Enum.Material.Fabric)
		sack.CanCollide = false
	end

	-- 6e. THE COUNTER'S TAKE. Coin piles, a strongbox and hanging scales -- the props that say money changes
	--     hands here, sitting where the player is already looking when they open the shop panel.
	local box = part(m, "Strongbox", Vector3.new(2.6, 1.8, 1.8), stallCF * CFrame.new(-4, 4.4, 0),
		Color3.fromRGB(58, 52, 46), Enum.Material.DiamondPlate)
	box.CanCollide = false
	part(m, "StrongboxLock", Vector3.new(0.7, 0.7, 0.3), stallCF * CFrame.new(-4, 4.2, -0.95),
		Color3.fromRGB(220, 180, 70), Enum.Material.Metal).CanCollide = false
	for i = 1, 3 do
		for j = 1, 3 + i do
			local coin = part(m, "Coin", Vector3.new(0.72, 0.12, 0.72),
				stallCF * CFrame.new(2 + i * 1.1, 3.75 + j * 0.12, rnd(1) - 0.5)
					* CFrame.Angles(0, rnd(6.2), 0),
				Color3.fromRGB(232, 190, 74), Enum.Material.Metal)
			coin.Shape = Enum.PartType.Cylinder
			coin.CFrame = coin.CFrame * CFrame.Angles(0, 0, math.rad(90))
			coin.CanCollide = false
		end
	end
	-- scales hanging over the counter
	local beam = part(m, "ScaleBeam", Vector3.new(4, 0.16, 0.16), stallCF * CFrame.new(0, 7.2, 0),
		Color3.fromRGB(180, 150, 80), Enum.Material.Metal)
	beam.CanCollide = false
	for _, sx in ipairs({ -1.8, 1.8 }) do
		part(m, "ScaleChain", Vector3.new(0.08, 1.4, 0.08), stallCF * CFrame.new(sx, 6.5, 0),
			Color3.fromRGB(120, 110, 90), Enum.Material.Metal).CanCollide = false
		local pan = part(m, "ScalePan", Vector3.new(1.6, 0.14, 1.6), stallCF * CFrame.new(sx, 5.8, 0),
			Color3.fromRGB(190, 160, 90), Enum.Material.Metal)
		pan.Shape = Enum.PartType.Cylinder
		pan.CFrame = pan.CFrame * CFrame.Angles(0, 0, math.rad(90))
		pan.CanCollide = false
	end

	-- 6f. A RUG under the counter, and CHALK TALLY MARKS on the wall behind it -- somebody keeps count here,
	--     and not in a ledger anyone could seize.
	local rug = part(m, "Rug", Vector3.new(18, 0.12, 12), stallCF * CFrame.new(0, -0.9, 6),
		Color3.fromRGB(96, 40, 44), Enum.Material.Fabric)
	rug.CanCollide = false
	for i = 1, 14 do
		local tally = part(m, "Tally", Vector3.new(0.14, 1.1, 0.06),
			CFrame.new(origin + Vector3.new(-16 + i * 1.1 + (i % 5 == 0 and 0.3 or 0), 9, -CAVE_D / 2 + 1.4))
				* CFrame.Angles(0, 0, i % 5 == 0 and math.rad(62) or 0),
			Color3.fromRGB(226, 222, 210), Enum.Material.SmoothPlastic)
		tally.CanCollide = false
		tally.CastShadow = false
	end

	--==================================================================
	-- 6g. PUSHING IT FURTHER
	--==================================================================
	-- Crates and dim bulbs say "storeroom". What makes a place read as CRIMINAL is evidence of three specific
	-- things: someone is watching the door, the goods are locked up because they are worth stealing from the
	-- thief, and somebody has been covering their tracks. Each block below is one of those.

	-- 6g-1. A LOOKOUT. A second hooded figure by the entrance with his back to the room, watching the way in.
	--       He has no prompt and never speaks -- he is not content, he is the reason the room feels watched.
	local lookAt = origin + Vector3.new(0, 1, CAVE_D / 2 - 20)
	local lookout = part(m, "Lookout", Vector3.new(2.6, 5.6, 2.6), CFrame.new(lookAt + Vector3.new(0, 2.8, 0)),
		Color3.fromRGB(32, 30, 38), Enum.Material.Fabric)
	lookout.CanCollide = false
	part(m, "LookoutHood", Vector3.new(3, 2, 3), CFrame.new(lookAt + Vector3.new(0, 6.4, 0)),
		Color3.fromRGB(24, 22, 30), Enum.Material.Fabric).CanCollide = false
	for _, ex in ipairs({ -0.6, 0.6 }) do
		local eye = part(m, "LookoutEye", Vector3.new(0.3, 0.12, 0.15),
			CFrame.new(lookAt + Vector3.new(ex, 6.3, 1.45)), Color3.fromRGB(255, 90, 70), Enum.Material.Neon)
		eye.CanCollide = false
	end
	-- he turns his head to follow you across the room -- the cheapest possible "you have been noticed"
	task.spawn(function()
		while m.Parent do
			task.wait(0.15)
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local flat = Vector3.new(hrp.Position.X, lookAt.Y + 2.8, hrp.Position.Z)
				lookout.CFrame = CFrame.lookAt(lookAt + Vector3.new(0, 2.8, 0), flat)
			end
		end
	end)

	-- 6g-2. A RED SIGNAL LAMP over the entrance. Red means one thing in a room like this, and it is not
	--       "welcome" -- it is the light that goes out when someone should stop talking.
	local signal = part(m, "SignalLamp", Vector3.new(1.6, 1.6, 1.6),
		CFrame.new(origin + Vector3.new(0, CAVE_H - 4, CAVE_D / 2 - 10)),
		Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	signal.Shape = Enum.PartType.Ball
	signal.CanCollide = false
	local sl = Instance.new("PointLight")
	sl.Brightness = 2; sl.Range = 24; sl.Color = Color3.fromRGB(255, 40, 40); sl.Parent = signal
	task.spawn(function()   -- slow menacing pulse, not a disco strobe
		while m.Parent do
			for _, b in ipairs({ 0.5, 2.2 }) do
				sl.Brightness = b
				signal.Transparency = b < 1 and 0.5 or 0
				task.wait(1.1)
			end
		end
	end)

	-- 6g-3. CAGED GOODS. Barred crates with something glowing inside. Locking your stock up in the room you
	--       already hid underground says you do not trust your own customers.
	for _, cx in ipairs({ -34, 34 }) do
		local cageAt = origin + Vector3.new(cx, 4, 8)
		local glow = part(m, "CagedGoods", Vector3.new(3.4, 3.4, 3.4), CFrame.new(cageAt),
			cx < 0 and Color3.fromRGB(170, 130, 255) or Color3.fromRGB(120, 255, 210), Enum.Material.Neon)
		glow.CanCollide = false
		glow.Transparency = 0.35
		local gl = Instance.new("PointLight")
		gl.Brightness = 1.4; gl.Range = 18; gl.Color = glow.Color; gl.Parent = glow
		for b = 0, 5 do            -- the bars
			local ang = (b / 6) * math.pi * 2
			local bar = part(m, "CageBar", Vector3.new(0.22, 5.4, 0.22),
				CFrame.new(cageAt + Vector3.new(math.cos(ang) * 2.6, 0, math.sin(ang) * 2.6)),
				Color3.fromRGB(46, 42, 40), Enum.Material.Metal)
			bar.CanCollide = false
		end
		part(m, "CageTop", Vector3.new(6, 0.4, 6), CFrame.new(cageAt + Vector3.new(0, 2.7, 0)),
			Color3.fromRGB(46, 42, 40), Enum.Material.Metal).CanCollide = false
		part(m, "CagePadlock", Vector3.new(0.9, 1.1, 0.4), CFrame.new(cageAt + Vector3.new(0, -2.4, 2.7)),
			Color3.fromRGB(210, 172, 66), Enum.Material.Metal).CanCollide = false
	end

	-- 6g-4. CHAINS AND HOOKS from the ceiling. Pure silhouette -- they do nothing, and they make the ceiling
	--       feel like somewhere things get moved rather than a flat lid.
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2 + 1.3
		local r = 16 + rnd(18)
		local top = origin + Vector3.new(math.cos(a) * r, CAVE_H - 1, math.sin(a) * r)
		local len = 4 + rnd(7)
		local chain = part(m, "Chain", Vector3.new(0.22, len, 0.22),
			CFrame.new(top - Vector3.new(0, len / 2, 0)), Color3.fromRGB(58, 54, 50), Enum.Material.Metal)
		chain.CanCollide = false
		local hook = part(m, "Hook", Vector3.new(0.7, 0.9, 0.25),
			CFrame.new(top - Vector3.new(0, len + 0.4, 0)) * CFrame.Angles(0, rnd(6.2), math.rad(18)),
			Color3.fromRGB(72, 66, 60), Enum.Material.Metal)
		hook.CanCollide = false
	end

	-- 6g-5. PRIED-OPEN CRATE with its lid on the floor and a crowbar left in it. Evidence of a hurry.
	local pryAt = origin + Vector3.new(20, 2.4, 20)
	local opened = part(m, "PriedCrate", Vector3.new(4.6, 4, 4.6), CFrame.new(pryAt) * CFrame.Angles(0, 0.5, 0),
		Color3.fromRGB(96, 64, 34), Enum.Material.WoodPlanks)
	opened.CanCollide = false
	part(m, "CrateLid", Vector3.new(4.8, 0.35, 4.8),
		CFrame.new(pryAt + Vector3.new(4.4, -2, 1.6)) * CFrame.Angles(math.rad(8), 0.9, math.rad(72)),
		Color3.fromRGB(82, 54, 28), Enum.Material.WoodPlanks).CanCollide = false
	part(m, "Crowbar", Vector3.new(0.28, 4.4, 0.28),
		CFrame.new(pryAt + Vector3.new(-2.6, -1.2, 1)) * CFrame.Angles(math.rad(64), 0.4, 0),
		Color3.fromRGB(126, 40, 34), Enum.Material.Metal).CanCollide = false
	-- straw spilling out of it
	for i = 1, 6 do
		local straw = part(m, "Straw", Vector3.new(0.12, 1.6, 0.12),
			CFrame.new(pryAt + Vector3.new(rnd(4) - 2, 2.2, rnd(4) - 2))
				* CFrame.Angles(rnd(1.4) - 0.7, rnd(6.2), rnd(1.4) - 0.7),
			Color3.fromRGB(198, 170, 92), Enum.Material.Grass)
		straw.CanCollide = false
	end

	-- 6g-6. BURNT PAPERWORK in one brazier and torn scraps on the floor. Somebody destroyed the records.
	for i = 1, 9 do
		local scrap = part(m, "Scrap", Vector3.new(0.9 + rnd(0.7), 0.05, 1.1 + rnd(0.8)),
			CFrame.new(origin + Vector3.new(-30 + rnd(12), 1.15, -26 + rnd(12)))
				* CFrame.Angles(0, rnd(6.2), 0),
			i % 3 == 0 and Color3.fromRGB(48, 42, 38) or Color3.fromRGB(196, 186, 160),
			Enum.Material.SmoothPlastic)
		scrap.CanCollide = false
		scrap.CastShadow = false
	end

	-- 6g-7. A CURTAIN screening a back area you never get into. A room with somewhere you are not allowed is
	--       automatically more secretive than one you can see all of.
	local curtAt = origin + Vector3.new(0, 7, -CAVE_D / 2 + 6)
	for i = 0, 7 do
		local strip = part(m, "CurtainStrip", Vector3.new(2.4, 12, 0.2),
			CFrame.new(curtAt + Vector3.new((i - 3.5) * 2.5, 0, 0)) * CFrame.Angles(0, rnd(0.12) - 0.06, 0),
			i % 2 == 0 and Color3.fromRGB(38, 34, 44) or Color3.fromRGB(30, 27, 36), Enum.Material.Fabric)
		strip.CanCollide = false
	end

	-- 6g-8. HAZE. Thicker and dirtier than the dust above -- smoke off the braziers that never clears, which
	--       is what makes the far corners read as somewhere you cannot quite see into.
	local hazeAt = Instance.new("Attachment")
	hazeAt.Position = Vector3.new(0, CAVE_H * 0.35, 0)
	hazeAt.Parent = part(m, "HazeAnchor", Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(origin + Vector3.new(0, 1, 0)), rock, Enum.Material.Slate)
	local haze = Instance.new("ParticleEmitter")
	haze.Texture = "rbxassetid://241876945"
	haze.Rate = 14
	haze.Lifetime = NumberRange.new(10, 18)
	haze.Speed = NumberRange.new(0.2, 0.8)
	haze.Size = NumberSequence.new(26)
	haze.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.92),
		NumberSequenceKeypoint.new(0.7, 0.92), NumberSequenceKeypoint.new(1, 1),
	})
	haze.Color = ColorSequence.new(Color3.fromRGB(96, 104, 92))
	haze.SpreadAngle = Vector2.new(180, 180)
	haze.Acceleration = Vector3.new(0.15, 0.05, 0.1)
	haze.LockedToPart = false
	haze.Parent = hazeAt

	--==================================================================
	-- 7. THE OPERATION  (the industrial layer)
	--==================================================================
	-- Everything below turns the den into an ABANDONED MINE SOMEBODY RE-WIRED: support beams and rails say
	-- "this was a mine", generators, cables and a conveyor say "someone moved in", and the fencing, cameras
	-- and warning signs say "and they do not want visitors". All low-poly blocks and cylinders, all part of
	-- the same model `m`, all client-side -- roughly 250 extra parts that only this player ever renders.
	--
	-- Every animated piece (fans, conveyor, camera, sign) loops on `while m.Parent` so it dies with the cave.

	-- Sign helper: a board with scaled text on its FRONT face. Boards are placed with CFrame.lookAt, and
	-- lookAt points the front (-Z) face at the target -- so "look at the room centre" makes the text readable
	-- from inside the room with no face math anywhere else.
	local function mkSign(size, cfr, text, textColor, bgColor)
		local board = part(m, "Sign", size, cfr, bgColor or Color3.fromRGB(236, 228, 198), Enum.Material.SmoothPlastic)
		board.CanCollide = false; board.CanQuery = false; board.CastShadow = false
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 0        -- signs must stay readable in a deliberately dark room
		gui.Parent = board
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBlack; lbl.TextScaled = true
		lbl.TextColor3 = textColor; lbl.Text = text
		lbl.Parent = gui
		return board, lbl
	end
	local roomMid = origin + Vector3.new(0, 6, 0)

	-- 7a. MINE SUPPORT BEAMS. Timber frames around the walls -- the single strongest "this used to be a
	--     mine" signal, and they visually chop the walls into bays, which is where the narrow-pathway feel
	--     comes from once the shelving and fencing fill the bays in.
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2 + 0.4
		local at = origin + Vector3.new(math.cos(a) * 40, 0, math.sin(a) * 40)
		local cfB = CFrame.lookAt(at, Vector3.new(origin.X, at.Y, origin.Z))
		for _, side in ipairs({ -2.6, 2.6 }) do
			local post = part(m, "MinePost", Vector3.new(1, CAVE_H - 5, 1),
				cfB * CFrame.new(side, (CAVE_H - 5) / 2 + 1, 0), Color3.fromRGB(112, 78, 44), Enum.Material.Wood)
			post.CanCollide = false
		end
		local lintel = part(m, "MineLintel", Vector3.new(6.6, 1, 1),
			cfB * CFrame.new(0, CAVE_H - 4, 0), Color3.fromRGB(96, 64, 34), Enum.Material.Wood)
		lintel.CanCollide = false
	end

	-- 7b. CRACKED CONCRETE FLOOR. Poured slabs over the mine floor -- somebody upgraded this place to take
	--     weight. Each plate sits at a slightly different height so overlaps stack instead of z-fighting.
	for i = 1, 7 do
		local px, pz = rnd(36) - 18, rnd(36) - 18
		local plate = part(m, "ConcretePlate", Vector3.new(10 + rnd(7), 0.14, 10 + rnd(7)),
			CFrame.new(origin + Vector3.new(px, 1.04 + i * 0.015, pz)) * CFrame.Angles(0, rnd(6.2), 0),
			Color3.fromRGB(146, 144, 138), Enum.Material.Concrete)
		plate.CanCollide = false
		for c = 1, 2 do   -- the cracks: thin dark bars laid across the plate at odd angles
			local crack = part(m, "Crack", Vector3.new(0.16, 0.05, 3 + rnd(5)),
				plate.CFrame * CFrame.new(rnd(6) - 3, 0.09, rnd(6) - 3) * CFrame.Angles(0, rnd(6.2), 0),
				Color3.fromRGB(74, 72, 68), Enum.Material.Concrete)
			crack.CanCollide = false; crack.CastShadow = false
		end
	end

	-- 7c. CABLES ACROSS THE GROUND. Two runs that visibly GO somewhere -- one from each generator toward the
	--     stall -- because cable that connects things reads as wiring and cable that doesn't reads as spaghetti.
	for _, run in ipairs({ { from = Vector3.new(-14, 0, -30) }, { from = Vector3.new(18, 0, -30) } }) do
		local at = origin + run.from + Vector3.new(0, 1.14, 0)
		local goal = origin + Vector3.new(0, 1.14, -20)
		for _ = 1, 5 do
			local dir = (goal - at)
			local step = math.min(dir.Magnitude, 5 + rnd(4))
			if step < 1 then break end
			local aim = CFrame.lookAt(at, goal) * CFrame.Angles(0, rnd(0.7) - 0.35, 0) -- wander, roughly onward
			local seg = part(m, "FloorCable", Vector3.new(0.28, 0.12, step),
				aim * CFrame.new(0, 0, -step / 2), Color3.fromRGB(34, 32, 36), Enum.Material.SmoothPlastic)
			seg.CanCollide = false; seg.CastShadow = false
			at = (aim * CFrame.new(0, 0, -step)).Position
		end
	end
	-- ...and hanging extension cords: loose loops drooping between beam height and head height on the walls
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2 + 1.1
		local at = origin + Vector3.new(math.cos(a) * 41, 12 - rnd(4), math.sin(a) * 41)
		local cord = part(m, "HangingCord", Vector3.new(0.14, 6 + rnd(5), 0.14),
			CFrame.new(at) * CFrame.Angles(rnd(0.5) - 0.25, 0, rnd(0.5) - 0.25),
			Color3.fromRGB(180, 90, 40), Enum.Material.SmoothPlastic)
		cord.CanCollide = false; cord.CastShadow = false
	end

	-- 7d. HEAVY SHELVING along the west wall, packed. Metal uprights, three boards, boxes shoved on anyhow.
	for s, sz2 in ipairs({ -22, -10, 2 }) do
		local shelfCF = CFrame.new(origin + Vector3.new(-39, 0, sz2))
		for _, o in ipairs({ { -2.8, -1 }, { 2.8, -1 }, { -2.8, 1 }, { 2.8, 1 } }) do
			part(m, "ShelfPost", Vector3.new(0.4, 9, 0.4),
				shelfCF * CFrame.new(o[1], 5.5, o[2]), Color3.fromRGB(96, 98, 104), Enum.Material.Metal)
				.CanCollide = false
		end
		for lvl = 1, 3 do
			part(m, "ShelfBoard", Vector3.new(6.4, 0.3, 2.6),
				shelfCF * CFrame.new(0, 1.6 + lvl * 2.6, 0), Color3.fromRGB(122, 124, 130), Enum.Material.DiamondPlate)
				.CanCollide = false
			for b = 1, 2 do
				local box = part(m, "ShelfBox", Vector3.new(1.6 + rnd(0.8), 1.4, 1.6),
					shelfCF * CFrame.new((b - 1.5) * 2.6 + rnd(1) - 0.5, 2.5 + lvl * 2.6, 0)
						* CFrame.Angles(0, rnd(0.6) - 0.3, 0),
					(s + lvl + b) % 2 == 0 and Color3.fromRGB(104, 70, 38) or Color3.fromRGB(88, 92, 86),
					Enum.Material.WoodPlanks)
				box.CanCollide = false
			end
		end
	end
	-- a hand truck parked against the shelves, mid-job
	local htCF = CFrame.new(origin + Vector3.new(-35, 0, -16)) * CFrame.Angles(0, 0.7, 0)
	part(m, "HandTruckPlate", Vector3.new(2, 0.2, 1.4), htCF * CFrame.new(0, 1.1, 0.6),
		Color3.fromRGB(160, 60, 40), Enum.Material.Metal).CanCollide = false
	part(m, "HandTruckFrame", Vector3.new(1.8, 4.6, 0.2),
		htCF * CFrame.new(0, 3.2, -0.2) * CFrame.Angles(math.rad(-12), 0, 0),
		Color3.fromRGB(160, 60, 40), Enum.Material.Metal).CanCollide = false

	-- 7e. WORKBENCH near the stall, with a toolbox and tools left where they were dropped -- the "actively
	--     used" half of "actively used but secretive".
	local wbCF = CFrame.new(origin + Vector3.new(13, 0, -16)) * CFrame.Angles(0, -0.4, 0)
	part(m, "BenchTop", Vector3.new(7, 0.5, 3), wbCF * CFrame.new(0, 3.4, 0),
		Color3.fromRGB(122, 86, 48), Enum.Material.WoodPlanks).CanCollide = false
	for _, o in ipairs({ { -3, -1.2 }, { 3, -1.2 }, { -3, 1.2 }, { 3, 1.2 } }) do
		part(m, "BenchLeg", Vector3.new(0.5, 3.2, 0.5), wbCF * CFrame.new(o[1], 1.6, o[2]),
			Color3.fromRGB(84, 58, 32), Enum.Material.Wood).CanCollide = false
	end
	part(m, "Toolbox", Vector3.new(2.2, 1, 1.1), wbCF * CFrame.new(-1.6, 4.2, 0) * CFrame.Angles(0, 0.3, 0),
		Color3.fromRGB(178, 52, 44), Enum.Material.Metal).CanCollide = false
	for i = 1, 4 do  -- loose tools: bare metal bars on and around the bench
		local tool = part(m, "Tool", Vector3.new(0.2, 0.2, 1.2 + rnd(0.8)),
			wbCF * CFrame.new(rnd(5) - 2.5, i < 3 and 3.8 or 1.15, rnd(2.5) - 1.25) * CFrame.Angles(0, rnd(6.2), 0),
			Color3.fromRGB(150, 150, 158), Enum.Material.Metal)
		tool.CanCollide = false; tool.CastShadow = false
	end

	-- 7f. GENERATORS -- the fiction for where all this light comes from. Orange accent glow, exhaust stack,
	--     oil stain underneath (machines that get maintained do not sit in their own oil; these do).
	for _, gx in ipairs({ -14, 18 }) do
		local gCF = CFrame.new(origin + Vector3.new(gx, 0, -30))
		local body = part(m, "Generator", Vector3.new(4, 3, 2.6), gCF * CFrame.new(0, 2.5, 0),
			Color3.fromRGB(84, 96, 74), Enum.Material.DiamondPlate)
		body.CanCollide = false
		part(m, "GenStack", Vector3.new(0.7, 2.6, 0.7), gCF * CFrame.new(1.2, 5.2, 0),
			Color3.fromRGB(58, 56, 60), Enum.Material.CorrodedMetal).CanCollide = false
		local glow = part(m, "GenGlow", Vector3.new(1.2, 0.8, 0.15), gCF * CFrame.new(-0.8, 2.6, 1.35),
			Color3.fromRGB(255, 150, 60), Enum.Material.Neon)
		glow.CanCollide = false
		local gl = Instance.new("PointLight")
		gl.Brightness = 1.6; gl.Range = 20; gl.Color = Color3.fromRGB(255, 150, 60); gl.Parent = glow
		local stain = part(m, "OilStain", Vector3.new(6 + rnd(2), 0.06, 5 + rnd(2)),
			gCF * CFrame.new(rnd(2) - 1, 1.1, rnd(2) - 1) * CFrame.Angles(0, rnd(6.2), 0),
			Color3.fromRGB(30, 28, 26), Enum.Material.SmoothPlastic)
		stain.CanCollide = false; stain.CastShadow = false
		local smoke = Instance.new("Smoke")   -- lazy chug from the stack
		smoke.Size = 2; smoke.Opacity = 0.12; smoke.RiseVelocity = 3
		smoke.Color = Color3.fromRGB(70, 70, 70)
		smoke.Parent = part(m, "GenStackTip", Vector3.new(0.6, 0.2, 0.6), gCF * CFrame.new(1.2, 6.5, 0),
			Color3.fromRGB(40, 40, 42), Enum.Material.Metal)
	end

	-- 7g. FUEL TANKS feeding generator one through a visible pipe -- connected equipment, same rule as the
	--     cables: plumbing that goes somewhere reads as real.
	for i, tz in ipairs({ -34, -30 }) do
		local tank = part(m, "FuelTank", Vector3.new(7, 3, 3),
			CFrame.new(origin + Vector3.new(-27, 2.6, tz)) * CFrame.Angles(0, 0, math.rad(90)),
			i == 1 and Color3.fromRGB(150, 60, 44) or Color3.fromRGB(150, 120, 50), Enum.Material.CorrodedMetal)
		tank.Shape = Enum.PartType.Cylinder
		tank.CanCollide = false
		part(m, "TankCradle", Vector3.new(3.4, 1.2, 1), CFrame.new(origin + Vector3.new(-27, 1.6, tz)),
			Color3.fromRGB(70, 68, 64), Enum.Material.Metal).CanCollide = false
	end
	part(m, "FuelPipe", Vector3.new(10, 0.5, 0.5), CFrame.new(origin + Vector3.new(-21, 2.4, -31)),
		Color3.fromRGB(110, 84, 52), Enum.Material.CorrodedMetal).CanCollide = false

	-- 7h. RUSTY PIPE RUN along the north wall with a valve wheel and a BURST joint venting steam. The steam
	--     is load-bearing atmosphere: a pipe that leaks is a pipe that is pressurised, i.e. still in use.
	for i = 0, 3 do
		part(m, "WallPipe", Vector3.new(12, 1.1, 1.1),
			CFrame.new(origin + Vector3.new(-18 + i * 12.4, 6, -43)) * CFrame.Angles(0, 0, 0),
			Color3.fromRGB(122, 82, 50), Enum.Material.CorrodedMetal).CanCollide = false
	end
	local valve = part(m, "ValveWheel", Vector3.new(0.4, 1.8, 1.8),
		CFrame.new(origin + Vector3.new(-6, 6, -42.2)) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(160, 50, 40), Enum.Material.Metal)
	valve.Shape = Enum.PartType.Cylinder
	valve.CanCollide = false
	local steamHost = part(m, "PipeBreak", Vector3.new(1.3, 1.3, 1.3),
		CFrame.new(origin + Vector3.new(7, 6, -43)), Color3.fromRGB(80, 60, 40), Enum.Material.CorrodedMetal)
	steamHost.CanCollide = false
	local steamAt = Instance.new("Attachment"); steamAt.Parent = steamHost
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = "rbxassetid://241876945"
	steam.Rate = 18; steam.Lifetime = NumberRange.new(1.2, 2.4)
	steam.Speed = NumberRange.new(4, 8); steam.Size = NumberSequence.new(1.6)
	steam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1),
	})
	steam.Color = ColorSequence.new(Color3.fromRGB(225, 228, 232))
	steam.EmissionDirection = Enum.NormalId.Bottom
	steam.SpreadAngle = Vector2.new(18, 18)
	steam.Parent = steamAt
	local puddle = part(m, "Puddle", Vector3.new(4.4, 0.06, 3.4),
		CFrame.new(origin + Vector3.new(7, 1.08, -40)), Color3.fromRGB(90, 120, 140), Enum.Material.Glass)
	puddle.Transparency = 0.45; puddle.Reflectance = 0.3
	puddle.CanCollide = false; puddle.CastShadow = false
	mkSign(Vector3.new(3.4, 2.2, 0.2),
		CFrame.lookAt(origin + Vector3.new(-1, 9.6, -43), origin + Vector3.new(-1, 9.6, 0)),
		"\xE2\x9A\xA0 DANGER", Color3.new(0, 0, 0), Color3.fromRGB(245, 205, 48))

	-- 7i. VENTILATION -- one wall extractor and one slow ceiling fan, BOTH TURNING. Motion is what separates
	--     "somebody operates this place" from a diorama of one.
	local wallHubCF = CFrame.new(origin + Vector3.new(43.4, 12, 0))
	local ring = part(m, "FanRing", Vector3.new(0.8, 7, 7), wallHubCF, Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
	ring.Shape = Enum.PartType.Cylinder
	ring.CanCollide = false
	local wallBlades = {}
	for i = 0, 1 do
		wallBlades[i + 1] = part(m, "FanBlade", Vector3.new(0.3, 5.8, 0.8),
			wallHubCF * CFrame.Angles(i * math.pi / 2, 0, 0), Color3.fromRGB(52, 54, 58), Enum.Material.Metal)
		wallBlades[i + 1].CanCollide = false
	end
	local ceilHubCF = CFrame.new(origin + Vector3.new(0, CAVE_H - 2, 8))
	part(m, "CeilFanHub", Vector3.new(1, 0.8, 1), ceilHubCF, Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
		.CanCollide = false
	local ceilBlades = {}
	for i = 0, 1 do
		ceilBlades[i + 1] = part(m, "CeilFanBlade", Vector3.new(9, 0.22, 0.9),
			ceilHubCF * CFrame.Angles(0, i * math.pi / 2, 0), Color3.fromRGB(88, 74, 54), Enum.Material.Wood)
		ceilBlades[i + 1].CanCollide = false
	end
	task.spawn(function()
		local ang = 0
		while m.Parent do
			task.wait(0.06)
			ang += 0.22                        -- slow -- these are tired old fans, not jet turbines
			for i, b in ipairs(wallBlades) do
				b.CFrame = wallHubCF * CFrame.Angles(ang + (i - 1) * math.pi / 2, 0, 0)
			end
			for i, b in ipairs(ceilBlades) do
				b.CFrame = ceilHubCF * CFrame.Angles(0, ang * 0.6 + (i - 1) * math.pi / 2, 0)
			end
		end
	end)

	-- 7j. GAS CANISTERS chained together in a cluster. The chain is what says "these matter -- do not tip".
	for i = 1, 5 do
		local can = part(m, "GasCanister", Vector3.new(1.2, 3 + rnd(0.8), 1.2),
			CFrame.new(origin + Vector3.new(25 + (i % 3) * 1.5, 2.6, -20 + math.floor(i / 3) * 1.6))
				* CFrame.Angles(0, rnd(6.2), 0),
			({ Color3.fromRGB(90, 160, 90), Color3.fromRGB(200, 130, 50), Color3.fromRGB(120, 122, 128) })[(i % 3) + 1],
			Enum.Material.Metal)
		can.Shape = Enum.PartType.Cylinder
		can.CFrame = can.CFrame * CFrame.Angles(0, 0, math.rad(90))
		can.CanCollide = false
	end
	part(m, "CanisterChain", Vector3.new(5.4, 0.25, 0.25), CFrame.new(origin + Vector3.new(26.2, 3.4, -19.2)),
		Color3.fromRGB(64, 62, 58), Enum.Material.Metal).CanCollide = false

	-- 7k. THE CONVEYOR -- rollers, rails, and glowing cargo crawling along it in a loop. Deliberately the
	--     most alive thing in the room: mysterious goods ACTIVELY MOVING is the whole operation in one prop.
	local beltY, beltZ = 2.4, 10
	part(m, "ConveyorBed", Vector3.new(26, 0.5, 3.2), CFrame.new(origin + Vector3.new(21, beltY, beltZ)),
		Color3.fromRGB(46, 46, 50), Enum.Material.SmoothPlastic).CanCollide = false
	for _, zo in ipairs({ -1.8, 1.8 }) do
		part(m, "ConveyorRail", Vector3.new(26, 0.35, 0.3),
			CFrame.new(origin + Vector3.new(21, beltY + 0.5, beltZ + zo)),
			Color3.fromRGB(96, 98, 104), Enum.Material.Metal).CanCollide = false
	end
	for i = 0, 3 do
		part(m, "ConveyorLeg", Vector3.new(0.5, beltY, 0.5),
			CFrame.new(origin + Vector3.new(9 + i * 8, beltY / 2 + 1, beltZ)),
			Color3.fromRGB(70, 72, 78), Enum.Material.Metal).CanCollide = false
	end
	local cargo = {}
	local cargoTints = { crystalTints[1], crystalTints[2], crystalTints[3] }
	for k = 1, 3 do
		local box = part(m, "GlowCargo", Vector3.new(1.7, 1.7, 1.7),
			CFrame.new(origin + Vector3.new(10, beltY + 1.4, beltZ)), cargoTints[k], Enum.Material.Neon)
		box.Transparency = 0.2
		box.CanCollide = false; box.CastShadow = false
		local cl = Instance.new("PointLight")
		cl.Brightness = 1; cl.Range = 10; cl.Color = cargoTints[k]; cl.Parent = box
		cargo[k] = box
	end
	task.spawn(function()
		while m.Parent do
			task.wait(0.08)
			local t = os.clock() * 2.6
			for k, box in ipairs(cargo) do
				local x = 8 + ((t + (k - 1) * 8.66) % 26)
				box.CFrame = CFrame.new(origin + Vector3.new(x, beltY + 1.4, beltZ))
					* CFrame.Angles(0, t * 0.3 + k, 0)
			end
		end
	end)

	-- 7l. CHAIN-LINK PEN in the south-west corner with barrels locked inside and a KEEP OUT sign. A fence
	--     INSIDE the hideout repeats the door's trick at smaller scale: another layer you are outside of.
	for _, seg in ipairs({
		{ Vector3.new(0.2, 6, 16), Vector3.new(-26, 4, -34) },   -- run along x = -26
		{ Vector3.new(16, 6, 0.2), Vector3.new(-34, 4, -26) },   -- run along z = -26 (gate gap left at the end)
	}) do
		local net = part(m, "ChainLink", seg[1], CFrame.new(origin + seg[2]),
			Color3.fromRGB(120, 122, 128), Enum.Material.DiamondPlate)
		net.Transparency = 0.45
		net.CanCollide = false
		part(m, "FenceRail", Vector3.new(math.max(seg[1].X, 0.3), 0.3, math.max(seg[1].Z, 0.3)),
			CFrame.new(origin + seg[2] + Vector3.new(0, 3.2, 0)),
			Color3.fromRGB(80, 82, 88), Enum.Material.Metal).CanCollide = false
	end
	for i = 1, 4 do
		local barrel = part(m, "PenBarrel", Vector3.new(3, 2.2, 2.2),
			CFrame.new(origin + Vector3.new(-36 + (i % 2) * 4, 2.6, -36 + math.floor(i / 3) * 4))
				* CFrame.Angles(0, 0, math.rad(90)),
			i % 2 == 0 and Color3.fromRGB(72, 96, 72) or Color3.fromRGB(110, 66, 40), Enum.Material.CorrodedMetal)
		barrel.Shape = Enum.PartType.Cylinder
		barrel.CanCollide = false
	end
	mkSign(Vector3.new(3, 1.6, 0.2),
		CFrame.lookAt(origin + Vector3.new(-26, 6, -30), roomMid), "KEEP OUT",
		Color3.fromRGB(200, 40, 30), Color3.fromRGB(230, 224, 210))

	-- 7m. THE LOCKED DOOR. A steel door in the west wall, chained shut, labelled -- the classic somewhere-
	--     you-cannot-go. It never opens; its entire job is being a question the player cannot answer.
	local doorCF = CFrame.lookAt(origin + Vector3.new(-43.6, 5.5, -6), origin + Vector3.new(0, 5.5, -6))
	part(m, "SteelDoor", Vector3.new(6, 9, 0.6), doorCF, Color3.fromRGB(88, 90, 96), Enum.Material.DiamondPlate)
		.CanCollide = false
	part(m, "SteelDoorBar", Vector3.new(6.6, 0.5, 0.3), doorCF * CFrame.new(0, 0.4, -0.5)
		* CFrame.Angles(0, 0, math.rad(9)), Color3.fromRGB(64, 62, 58), Enum.Material.Metal).CanCollide = false
	part(m, "SteelDoorLock", Vector3.new(0.9, 1.2, 0.4), doorCF * CFrame.new(0.4, 0.35, -0.6),
		Color3.fromRGB(210, 172, 66), Enum.Material.Metal).CanCollide = false
	mkSign(Vector3.new(4.6, 1.3, 0.2), doorCF * CFrame.new(0, 5.6, -0.3),
		"AUTHORIZED PERSONNEL ONLY", Color3.fromRGB(200, 40, 30), Color3.fromRGB(232, 228, 216))

	-- 7n. SECURITY CAMERAS in two opposite corners, panning, with a blinking red eye. Together with the
	--     lookout this closes the loop: you are watched by a person AND a machine.
	for _, corner in ipairs({ Vector3.new(41, 21, 41), Vector3.new(-41, 21, -41) }) do
		local cpos = origin + corner
		local camBase = CFrame.lookAt(cpos, roomMid)
		local cam = part(m, "SecurityCam", Vector3.new(0.9, 0.9, 2), camBase,
			Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
		cam.CanCollide = false
		part(m, "CamMount", Vector3.new(0.3, 2, 0.3), CFrame.new(cpos + Vector3.new(0, 1.4, 0)),
			Color3.fromRGB(52, 54, 58), Enum.Material.Metal).CanCollide = false
		local eye = part(m, "CamEye", Vector3.new(0.25, 0.25, 0.1), camBase * CFrame.new(0, 0.3, -1.05),
			Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
		eye.CanCollide = false; eye.CastShadow = false
		task.spawn(function()
			while m.Parent do
				task.wait(0.12)
				local sweep = math.sin(os.clock() * 0.5) * 0.55
				cam.CFrame = camBase * CFrame.Angles(0, sweep, 0)
				eye.CFrame = cam.CFrame * CFrame.new(0, 0.3, -1.05)
				eye.Transparency = (math.floor(os.clock() * 1.4) % 2 == 0) and 0 or 0.75
			end
		end)
	end

	-- 7o. GRAFFITI. The same ring-and-slash mark from the front door sprayed big and orange on the east
	--     wall -- the gang signs INSIDE its own hideout, which ties door and room into one organisation --
	--     plus a few abstract tags in the accent colours.
	local tagAt = CFrame.lookAt(origin + Vector3.new(43.6, 9, -18), origin + Vector3.new(0, 9, -18))
	for i = 0, 11 do
		if i ~= 3 then
			local a1 = (i / 12) * math.pi * 2
			local sprayR = 3.2
			local strokeCF = tagAt * CFrame.new(math.cos(a1) * sprayR, math.sin(a1) * sprayR, -0.1)
				* CFrame.Angles(0, 0, -a1 - math.pi * 0.5)
			local stroke = part(m, "SprayRing", Vector3.new(0.5, 2, 0.06), strokeCF,
				Color3.fromRGB(255, 130, 40), Enum.Material.Neon)
			stroke.Transparency = 0.35
			stroke.CanCollide = false; stroke.CanQuery = false; stroke.CastShadow = false
		end
	end
	local spraySlash = part(m, "SpraySlash", Vector3.new(0.55, 7.6, 0.06),
		tagAt * CFrame.new(0, 0, -0.1) * CFrame.Angles(0, 0, math.rad(38)),
		Color3.fromRGB(255, 130, 40), Enum.Material.Neon)
	spraySlash.Transparency = 0.35
	spraySlash.CanCollide = false; spraySlash.CanQuery = false; spraySlash.CastShadow = false
	for i = 1, 4 do
		local squiggle = part(m, "SprayTag", Vector3.new(0.4, 2 + rnd(2.4), 0.06),
			CFrame.lookAt(origin + Vector3.new(43.6, 5 + rnd(8), 6 + i * 6), origin + Vector3.new(0, 8, 6 + i * 6))
				* CFrame.new(0, 0, -0.1) * CFrame.Angles(0, 0, rnd(3.1) - 1.55),
			crystalTints[(i % 3) + 1], Enum.Material.Neon)
		squiggle.Transparency = 0.4
		squiggle.CanCollide = false; squiggle.CanQuery = false; squiggle.CastShadow = false
	end

	-- 7p. PAPERS AND BLUEPRINTS pinned to the north wall by the curtain -- plans someone actually consults.
	for i = 1, 5 do
		local isBlue = i % 2 == 0
		local sheet = part(m, "PinnedSheet", Vector3.new(1.6 + rnd(0.8), 2 + rnd(0.8), 0.06),
			CFrame.lookAt(origin + Vector3.new(12 + i * 3.2, 7 + rnd(3), -43.7), origin + Vector3.new(12 + i * 3.2, 8, 0))
				* CFrame.Angles(0, 0, rnd(0.3) - 0.15),
			isBlue and Color3.fromRGB(60, 90, 170) or Color3.fromRGB(226, 222, 208), Enum.Material.SmoothPlastic)
		sheet.CanCollide = false; sheet.CanQuery = false; sheet.CastShadow = false
		if isBlue then   -- white schematic lines on the blueprints
			for _ = 1, 2 do
				local line = part(m, "BlueprintLine", Vector3.new(1, 0.12, 0.02),
					sheet.CFrame * CFrame.new(rnd(0.8) - 0.4, rnd(1) - 0.5, -0.05) * CFrame.Angles(0, 0, rnd(1.4)),
					Color3.fromRGB(220, 230, 250), Enum.Material.SmoothPlastic)
				line.CanCollide = false; line.CanQuery = false; line.CastShadow = false
			end
		end
	end

	-- 7q. MINE RAILS that stop dead mid-room, and a tipped cart still full of crates. Rails from nowhere to
	--     nowhere are the "abandoned mine" past tense; the loaded cart is the operation's present tense.
	for _, rx in ipairs({ -16.9, -15.1 }) do
		part(m, "MineRail", Vector3.new(0.3, 0.25, 38), CFrame.new(origin + Vector3.new(rx, 1.18, -25)),
			Color3.fromRGB(96, 82, 64), Enum.Material.CorrodedMetal).CanCollide = false
	end
	for i = 0, 8 do
		part(m, "RailTie", Vector3.new(2.8, 0.2, 0.7), CFrame.new(origin + Vector3.new(-16, 1.08, -42 + i * 4.4)),
			Color3.fromRGB(78, 56, 32), Enum.Material.Wood).CanCollide = false
	end
	local cartCF = CFrame.new(origin + Vector3.new(-16, 2.4, -9)) * CFrame.Angles(0, 0.3, math.rad(14))
	part(m, "MineCart", Vector3.new(4, 2.6, 5.6), cartCF, Color3.fromRGB(94, 74, 58), Enum.Material.CorrodedMetal)
		.CanCollide = false
	for _, o in ipairs({ { -1.8, -1.9 }, { 1.8, -1.9 }, { -1.8, 1.9 }, { 1.8, 1.9 } }) do
		local wheel = part(m, "CartWheel", Vector3.new(0.4, 1.1, 1.1),
			cartCF * CFrame.new(o[1], -1.4, o[2]) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(50, 48, 46), Enum.Material.Metal)
		wheel.Shape = Enum.PartType.Cylinder
		wheel.CanCollide = false
	end
	for i = 1, 2 do
		part(m, "CartCrate", Vector3.new(2.2, 2, 2.2), cartCF * CFrame.new((i - 1.5) * 2, 1.6, 0)
			* CFrame.Angles(0, rnd(6.2), 0), Color3.fromRGB(104, 70, 38), Enum.Material.WoodPlanks)
			.CanCollide = false
	end

	-- 7r. RAISED TIMBER PLATFORMS in the north-east corner joined by a plank bridge, crates on top --
	--     storage stacked UP, which breaks the room's single flat eye-line and makes it read bigger.
	for _, plat in ipairs({ Vector3.new(36, 7, -36), Vector3.new(18, 7, -36) }) do
		local pCF = CFrame.new(origin + plat)
		part(m, "PlatformTop", Vector3.new(11, 0.6, 11), pCF, Color3.fromRGB(112, 78, 44), Enum.Material.WoodPlanks)
		for _, o in ipairs({ { -4.6, -4.6 }, { 4.6, -4.6 }, { -4.6, 4.6 }, { 4.6, 4.6 } }) do
			part(m, "PlatformPost", Vector3.new(0.8, plat.Y - 1, 0.8),
				CFrame.new(origin + Vector3.new(plat.X + o[1], (plat.Y - 1) / 2 + 1, plat.Z + o[2])),
				Color3.fromRGB(96, 64, 34), Enum.Material.Wood).CanCollide = false
		end
		for c = 1, 2 do
			part(m, "PlatformCrate", Vector3.new(2.6, 2.4, 2.6),
				pCF * CFrame.new(c * 2.6 - 4, 1.6, rnd(4) - 2) * CFrame.Angles(0, rnd(6.2), 0),
				Color3.fromRGB(88, 58, 32), Enum.Material.WoodPlanks).CanCollide = false
		end
	end
	part(m, "PlankBridge", Vector3.new(8, 0.4, 3.4), CFrame.new(origin + Vector3.new(27, 7, -36)),
		Color3.fromRGB(122, 86, 48), Enum.Material.WoodPlanks)

	-- 7s. MAKESHIFT REPAIRS -- planks nailed over wall cracks, a scrap plate bolted on. A place held
	--     together on purpose, by someone who is not going to file a maintenance ticket.
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + 0.2
		local at = origin + Vector3.new(math.cos(a) * 43, 6 + rnd(8), math.sin(a) * 43)
		local patchCF = CFrame.lookAt(at, Vector3.new(origin.X, at.Y, origin.Z))
		for _, tilt in ipairs({ 0.5, -0.6 }) do
			part(m, "RepairPlank", Vector3.new(0.9, 5 + rnd(2), 0.3),
				patchCF * CFrame.new(rnd(1) - 0.5, 0, -0.2) * CFrame.Angles(0, 0, tilt),
				Color3.fromRGB(122, 86, 48), Enum.Material.WoodPlanks).CanCollide = false
		end
		if i % 2 == 0 then
			part(m, "ScrapPlate", Vector3.new(2.6, 2.2, 0.2), patchCF * CFrame.new(0, 0, -0.35),
				Color3.fromRGB(110, 104, 96), Enum.Material.CorrodedMetal).CanCollide = false
		end
	end

	-- 7t. CAUTION TAPE strung crookedly across the cages and the pried crate -- yellow reads instantly at
	--     distance, so these lines pull the eye to exactly the props that sell the story.
	for _, tp in ipairs({
		{ Vector3.new(7, 0.5, 0.1), Vector3.new(-34, 4.5, 4.4), 0.14 },
		{ Vector3.new(7, 0.5, 0.1), Vector3.new(34, 3.9, 4.4), -0.1 },
		{ Vector3.new(6, 0.5, 0.1), Vector3.new(20, 3.4, 17), 0.2 },
	}) do
		local tape = part(m, "CautionTape", tp[1],
			CFrame.new(origin + tp[2]) * CFrame.Angles(0, rnd(6.2), tp[3]),
			Color3.fromRGB(245, 205, 48), Enum.Material.SmoothPlastic)
		tape.CanCollide = false; tape.CanQuery = false; tape.CastShadow = false
	end

	-- 7u. CRYSTALS EMBEDDED IN THE WALLS, high up, half-sunk into the rock. The floor clusters light the
	--     room; these keep the MINE readable -- the thing everyone originally came down here to dig out.
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2 + 0.9
		local at = origin + Vector3.new(math.cos(a) * 43.5, 10 + rnd(10), math.sin(a) * 43.5)
		local wc = part(m, "WallCrystal", Vector3.new(1.4 + rnd(1), 2.6 + rnd(2), 1.4),
			CFrame.lookAt(at, Vector3.new(origin.X, at.Y, origin.Z)) * CFrame.Angles(rnd(0.8) - 0.4, 0, rnd(0.8) - 0.4),
			crystalTints[(i % 3) + 1], Enum.Material.Neon)
		wc.Transparency = 0.3
		wc.CanCollide = false; wc.CastShadow = false
	end

	-- 7v. THE NEON "OPEN" SIGN -- raised to 16 studs and WIRED TO THE CEILING. It used to float at 11, which
	--     put the middle pendant shade (10.6) squarely in front of its bottom edge from the queue side; up
	--     here it owns its own layer of air. Two hanging lines run from the sign's top corners to the
	--     ceiling slab so it hangs from something instead of levitating, and a neon tube border makes it
	--     read as NEON rather than a printed board. The punchline prop: a shop sign in a place that
	--     officially does not exist. Its flicker is irregular on purpose -- steady neon is a diner, dying
	--     neon is a dive.
	local signBoard, signLbl = mkSign(Vector3.new(4.6, 2, 0.25),
		CFrame.lookAt(origin + Vector3.new(0, 16, -22), origin + Vector3.new(0, 16, 20)),
		"OPEN", Color3.fromRGB(120, 255, 140), Color3.fromRGB(18, 18, 22))
	local signEdges = {}
	for i, e in ipairs({
		{ Vector3.new(4.6, 0.14, 0.14), Vector3.new(0, 1.05, 0) },
		{ Vector3.new(4.6, 0.14, 0.14), Vector3.new(0, -1.05, 0) },
		{ Vector3.new(0.14, 2.2, 0.14), Vector3.new(2.35, 0, 0) },
		{ Vector3.new(0.14, 2.2, 0.14), Vector3.new(-2.35, 0, 0) },
	}) do
		local edge = part(m, "SignTube", e[1], signBoard.CFrame * CFrame.new(e[2]),
			Color3.fromRGB(120, 255, 140), Enum.Material.Neon)
		edge.CanCollide = false; edge.CastShadow = false
		signEdges[i] = edge
	end
	for _, cx in ipairs({ -1.9, 1.9 }) do
		local lineLen = (CAVE_H - 1) - 17    -- from the sign's top (17) to the ceiling slab's underside
		part(m, "SignLine", Vector3.new(0.12, lineLen, 0.12),
			CFrame.new(origin + Vector3.new(cx, 17 + lineLen / 2, -22)),
			Color3.fromRGB(58, 54, 50), Enum.Material.Metal).CanCollide = false
	end
	local signGlow = Instance.new("PointLight")
	signGlow.Brightness = 1.6; signGlow.Range = 16; signGlow.Color = Color3.fromRGB(120, 255, 140)
	signGlow.Parent = signBoard
	task.spawn(function()
		while m.Parent do
			task.wait(0.6 + rnd(2.4))
			for _ = 1, 1 + rnd(3) do     -- a burst of stutters, then stable again
				signLbl.TextTransparency = 0.85; signGlow.Brightness = 0.05
				for _, e in ipairs(signEdges) do e.Transparency = 0.7 end
				task.wait(0.05 + rnd(0.08))
				signLbl.TextTransparency = 0
				-- restore to a QUARTER of the built value: the final pass cuts every light in the room to
				-- 25%, and a flicker loop restoring full brightness would quietly undo that for this light
				signGlow.Brightness = 0.4
				for _, e in ipairs(signEdges) do e.Transparency = 0 end
				task.wait(0.06 + rnd(0.1))
			end
		end
	end)

	-- ===== THE TRADER =====
	-- He is a CLONE OF AN ISLAND 'Quest' NPC, not a stack of blocks. Those rigs are the game's established look
	-- for "person you talk to", so the trader reads as one on sight -- and cloning means he inherits whatever
	-- you change about them later instead of drifting into his own art style.
	-- (stallCF is declared up with the room build -- the market props needed it before this point)
	local stall = part(m, "Stall", Vector3.new(12, 4, 3), stallCF * CFrame.new(0, 2, 0),
		Color3.fromRGB(96, 62, 34), Enum.Material.WoodPlanks)

	--==================================================================
	-- SHADY SAL'S WORKSTATION  (the focal point)
	--==================================================================
	-- The desk gets the detail budget the rest of the room deliberately does not: brighter, denser, more
	-- machine. In a dim room the eye goes to the one bright island, so this is UPGRADE not addition -- the
	-- counter itself is reinforced, backed by a supply wall, and lit by its own pendants (~50 parts total)
	-- rather than the whole cave getting another layer of clutter.

	-- Reinforced counter: steel plate top, timber corner posts, a scrap panel bolted over the front, and a
	-- fuel drum shoring up one end -- a counter ASSEMBLED from salvage, not bought.
	part(m, "DeskTop", Vector3.new(12.8, 0.4, 3.5), stallCF * CFrame.new(0, 4.2, 0),
		Color3.fromRGB(116, 118, 124), Enum.Material.DiamondPlate)
	for _, px in ipairs({ -6.1, 6.1 }) do
		part(m, "DeskPost", Vector3.new(0.9, 4.6, 0.9), stallCF * CFrame.new(px, 2.3, 0),
			Color3.fromRGB(84, 58, 32), Enum.Material.Wood)
	end
	part(m, "DeskPlate", Vector3.new(5, 2.4, 0.25),
		stallCF * CFrame.new(2.4, 2.2, 1.65) * CFrame.Angles(0, 0, math.rad(-4)),
		Color3.fromRGB(110, 104, 96), Enum.Material.CorrodedMetal)
	local drum = part(m, "DeskDrum", Vector3.new(4, 2.4, 2.4), stallCF * CFrame.new(-6.8, 2, 1),
		Color3.fromRGB(110, 66, 40), Enum.Material.CorrodedMetal)
	drum.Shape = Enum.PartType.Cylinder
	drum.CFrame = stallCF * CFrame.new(-6.8, 2, 1) * CFrame.Angles(0, 0, math.rad(90))

	-- The supply wall: a tall shelf unit BEHIND Sal, packed. Its job is to give him a backdrop -- a figure
	-- against bare cave wall floats; a figure against his own stacked stock is installed there.
	local backCF = stallCF * CFrame.new(0, 0, -8)
	for _, px in ipairs({ -5.5, 5.5 }) do
		part(m, "BackPost", Vector3.new(0.5, 11, 0.5), backCF * CFrame.new(px, 5.5, 0),
			Color3.fromRGB(96, 98, 104), Enum.Material.Metal)
	end
	for lvl = 1, 3 do
		part(m, "BackBoard", Vector3.new(11.6, 0.35, 2.4), backCF * CFrame.new(0, 1.2 + lvl * 2.9, 0),
			Color3.fromRGB(122, 124, 130), Enum.Material.DiamondPlate)
	end
	part(m, "Lockbox", Vector3.new(2, 1.3, 1.5), backCF * CFrame.new(-3.8, 4.8, 0) * CFrame.Angles(0, 0.2, 0),
		Color3.fromRGB(70, 74, 82), Enum.Material.Metal)
	-- the radio: how a man nobody visits still gets his orders
	local radio = part(m, "Radio", Vector3.new(1.9, 1.1, 0.8), backCF * CFrame.new(2.8, 7.6, 0),
		Color3.fromRGB(56, 66, 52), Enum.Material.Metal)
	part(m, "RadioAerial", Vector3.new(0.08, 2.2, 0.08), backCF * CFrame.new(3.5, 8.9, 0)
		* CFrame.Angles(0, 0, math.rad(-14)), Color3.fromRGB(140, 140, 148), Enum.Material.Metal)
		.CanCollide = false
	local radioLed = part(m, "RadioLed", Vector3.new(0.18, 0.18, 0.08), backCF * CFrame.new(2.1, 7.8, 0.42),
		Color3.fromRGB(120, 255, 140), Enum.Material.Neon)
	radioLed.CanCollide = false; radioLed.CastShadow = false
	for i = 1, 2 do  -- rolled maps leaning in the corner of a shelf
		local map = part(m, "MapRoll", Vector3.new(0.5, 2.4, 0.5),
			backCF * CFrame.new(4.6 - i * 0.5, 5.4, 0.3) * CFrame.Angles(0, 0, math.rad(8 * i)),
			Color3.fromRGB(210, 190, 150), Enum.Material.SmoothPlastic)
		map.CanCollide = false
	end
	local jar = part(m, "GlowJar", Vector3.new(1, 1.5, 1), backCF * CFrame.new(0.4, 10.3, 0),
		crystalTints[2], Enum.Material.Neon)
	jar.Transparency = 0.25; jar.CanCollide = false
	local jl = Instance.new("PointLight")
	jl.Brightness = 1; jl.Range = 10; jl.Color = crystalTints[2]; jl.Parent = jar

	-- THE PENDANTS. Three warm lamps hung low over the counter, each an actual SpotLight aimed down. This is
	-- the trick the whole focal point hangs on: the room's ambient stays dim, the desk sits in its own pool
	-- of light, and the eye has nowhere else it wants to go.
	for _, px in ipairs({ -3.6, 0, 3.6 }) do
		local shadeCF = stallCF * CFrame.new(px, 9.6, 0)
		-- The cord runs from the shade ALL THE WAY to the ceiling slab's underside. The first version was a
		-- 5-stud stub that ended in mid-air -- lamps hanging from nothing, which the eye catches instantly
		-- in a room this dark because the pendants are the brightest thing in it. (Shade sits at 10.6 studs
		-- above the room origin: stallCF is origin+1, the shade +9.6 on top of that.)
		local cordLen = (CAVE_H - 1) - 10.6
		part(m, "PendantCord", Vector3.new(0.08, cordLen, 0.08), shadeCF * CFrame.new(0, cordLen / 2, 0),
			Color3.fromRGB(34, 32, 36), Enum.Material.SmoothPlastic).CanCollide = false
		local shade = part(m, "PendantShade", Vector3.new(0.9, 1.9, 1.9), shadeCF * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(58, 72, 58), Enum.Material.Metal)
		shade.Shape = Enum.PartType.Cylinder
		shade.CanCollide = false
		local bulb = part(m, "PendantBulb", Vector3.new(0.6, 0.6, 0.6), shadeCF * CFrame.new(0, -0.5, 0),
			Color3.fromRGB(255, 214, 150), Enum.Material.Neon)
		bulb.Shape = Enum.PartType.Ball
		bulb.CanCollide = false
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Brightness = 3.4; spot.Range = 20; spot.Angle = 80
		spot.Color = Color3.fromRGB(255, 205, 140)
		spot.Parent = bulb
	end

	-- The paperwork side: a flickering monitor wired to nothing obvious, a clipboard, and a bulletin board
	-- on legs beside the desk -- maps, notes, and one WANTED poster. Sal keeps his records where a raid
	-- would have to read the wall.
	local mon = part(m, "Monitor", Vector3.new(1.7, 1.4, 0.6),
		stallCF * CFrame.new(4.2, 5.1, -0.4) * CFrame.Angles(0, math.rad(18), 0),
		Color3.fromRGB(60, 62, 68), Enum.Material.Metal)
	local screen = part(m, "MonitorScreen", Vector3.new(1.4, 1.1, 0.06),
		mon.CFrame * CFrame.new(0, 0.05, 0.34), Color3.fromRGB(90, 220, 120), Enum.Material.Neon)
	screen.CanCollide = false; screen.CastShadow = false
	part(m, "Clipboard", Vector3.new(1, 0.08, 1.4), stallCF * CFrame.new(-1.8, 4.45, 0.4)
		* CFrame.Angles(0, math.rad(-12), 0), Color3.fromRGB(160, 120, 70), Enum.Material.SmoothPlastic)
		.CanCollide = false
	task.spawn(function()   -- the monitor and the radio LED share one lazy flicker loop
		while m.Parent do
			task.wait(0.4 + rnd(1.8))
			screen.Transparency = 0.5; radioLed.Transparency = 0.7
			task.wait(0.05 + rnd(0.1))
			screen.Transparency = 0; radioLed.Transparency = 0
		end
	end)

	local boardCF = stallCF * CFrame.new(-9.5, 0, -3) * CFrame.Angles(0, math.rad(35), 0)
	part(m, "BulletinBoard", Vector3.new(6, 4.2, 0.3), boardCF * CFrame.new(0, 6, 0),
		Color3.fromRGB(104, 78, 48), Enum.Material.WoodPlanks)
	for _, px in ipairs({ -2.5, 2.5 }) do
		part(m, "BoardLeg", Vector3.new(0.5, 8, 0.5), boardCF * CFrame.new(px, 4, 0),
			Color3.fromRGB(84, 58, 32), Enum.Material.Wood)
	end
	for i = 1, 4 do  -- pinned notes at drunk angles
		local note = part(m, "BoardNote", Vector3.new(1 + rnd(0.5), 1.2 + rnd(0.5), 0.06),
			boardCF * CFrame.new(-1.8 + i * 0.9, 5.4 + (i % 2) * 1.2, 0.2) * CFrame.Angles(0, 0, rnd(0.5) - 0.25),
			i == 2 and Color3.fromRGB(60, 90, 170) or Color3.fromRGB(226, 222, 208), Enum.Material.SmoothPlastic)
		note.CanCollide = false; note.CastShadow = false
	end
	mkSign(Vector3.new(1.5, 1.9, 0.08),
		boardCF * CFrame.new(1.8, 5.6, 0.25) * CFrame.Angles(0, math.pi, math.rad(6)),
		"WANTED", Color3.fromRGB(60, 50, 40), Color3.fromRGB(224, 214, 190))

	-- and one wooden barricade flanking the queue-side of the desk, because even an illegal shop has a
	-- "wait here" line
	local barrCF = stallCF * CFrame.new(9, 0, 3) * CFrame.Angles(0, math.rad(-25), 0)
	for _, tilt in ipairs({ 18, -18 }) do
		part(m, "Barricade", Vector3.new(0.5, 3.4, 0.5), barrCF * CFrame.new(0, 1.6, 0)
			* CFrame.Angles(math.rad(tilt), 0, 0), Color3.fromRGB(112, 78, 44), Enum.Material.Wood)
	end
	part(m, "Barricade", Vector3.new(4.4, 0.5, 0.4), barrCF * CFrame.new(0, 2.6, 0),
		Color3.fromRGB(245, 205, 48), Enum.Material.SmoothPlastic)

	local body                                   -- whatever the shop prompt ends up attached to
	local traderRig, traderShoulder, traderRest   -- for the wave

	-- Find any island's 'Quest' rig to copy. Names carry a trailing space in this place ("Quest "), so match on
	-- the trimmed name rather than equality -- that space has bitten every system that looked for these.
	local template
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name:gsub("%s+$", "") == "Quest"
			and d:FindFirstChild("HumanoidRootPart") then
			template = d; break
		end
	end

	if template then
		local ok, rig = pcall(function() return template:Clone() end)
		if ok and rig then
			-- A cloned rig arrives with a Humanoid that will try to walk, fall, and take damage. None of that
			-- is wanted for a shopkeeper standing in a sealed room, and a Humanoid left alive would ragdoll
			-- him the moment the floor streams oddly.
			local hum = rig:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.WalkSpeed = 0; hum.JumpPower = 0
				hum:ChangeState(Enum.HumanoidStateType.Physics)
				hum.PlatformStand = true
			end
			for _, d in ipairs(rig:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
				-- strip any prompts the original carried, or the player could "talk" to the island's quest
				-- giver from inside the cave and trip that quest's state
				if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then d:Destroy() end
			end
			-- ===== HE MUST NOT STILL BE CALLED 'Quest' =====
			-- The clone inherits the island rig's overhead nametag, so without this the black-market fence is
			-- floating the word "Quest" over his head -- instantly reading as a copy of an NPC from upstairs
			-- rather than someone who is down here because he cannot be up there.
			--
			-- Three separate things can put a name above a head, and the rigs vary, so all three are handled:
			-- the Model name, the Humanoid's DisplayName, and any BillboardGui the rig carries.
			rig.Name = "ShadySal"
			local TRADER_NAME = "Shady Sal"       -- what a person who moves goods nobody asks about is called
			if hum then
				hum.DisplayName = TRADER_NAME
				-- Visible from ANY distance (the earlier 12-stud fade was reverted on request -- in a room
				-- this dark the floating name doubles as the beacon that leads you to the counter).
				-- DisplayDistanceType stays Subject so this number is authoritative: the default (Viewer)
				-- would use the LOCAL player's settings and ignore it entirely.
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
				hum.NameDisplayDistance = 10000
				hum.HealthDisplayDistance = 0     -- no health bar over a shopkeeper
			end
			for _, d in ipairs(rig:GetDescendants()) do
				if d:IsA("BillboardGui") then
					-- DESTROYED, not retitled. Keeping the rig's own billboard AND the Humanoid DisplayName
					-- gave Sal two nametags at once -- the quest rig's big plate floating over the compact
					-- default tag. The SMALL one (the Humanoid tag, styled and range-set above) is the
					-- keeper; the big inherited plate goes.
					d:Destroy()
				end
			end
			rig:PivotTo(stallCF * CFrame.new(0, 3, -4) * CFrame.Angles(0, math.pi, 0)) -- facing the counter
			rig.Parent = m
			traderRig = rig
			body = rig:FindFirstChild("HumanoidRootPart")

			-- THE WAVE: the same joint, the same easing, the same numbers as GardenerWave uses for the island
			-- quest givers (LIFT 105 deg, SWING 22 deg at 9 rad/s over 2.2s, LEFT arm, sign -1). Done here on
			-- the client because this rig is client-built and the server has never heard of it.
			local lua = rig:FindFirstChild("LeftUpperArm")                       -- R15
			traderShoulder = lua and lua:FindFirstChild("LeftShoulder")
			if not (traderShoulder and traderShoulder:IsA("Motor6D")) then
				local torso = rig:FindFirstChild("Torso")                        -- R6
				traderShoulder = torso and torso:FindFirstChild("Left Shoulder")
			end
			if traderShoulder and traderShoulder:IsA("Motor6D") then
				traderRest = traderShoulder.C0   -- captured ONCE; every wave returns to exactly this
			else
				traderShoulder = nil
				warn("[SecretCave] trader rig has no LEFT shoulder Motor6D -- he will not wave")
			end
			print("[SecretCave] trader cloned from '" .. template:GetFullName() .. "'")
		end
	end

	-- FALLBACK. If no Quest rig has streamed in yet there must still be someone to trade with, or the cave is
	-- a room with a table in it and no way to buy anything.
	if not body then
		warn("[SecretCave] no island 'Quest' NPC found to clone -- using the plain hooded figure instead")
		body = part(m, "Trader", Vector3.new(3, 6, 3), stallCF * CFrame.new(0, 3, -3.5),
			Color3.fromRGB(48, 40, 62), Enum.Material.Fabric)
		part(m, "TraderHood", Vector3.new(3.4, 2.2, 3.4), stallCF * CFrame.new(0, 6.4, -3.5),
			Color3.fromRGB(36, 30, 48), Enum.Material.Fabric)
		for _, dx in ipairs({ -0.7, 0.7 }) do
			local eye = part(m, "Eye", Vector3.new(0.35, 0.35, 0.2), stallCF * CFrame.new(dx, 6.1, -5.15),
				Color3.fromRGB(255, 220, 130), Enum.Material.Neon)
			eye.CanCollide = false
		end
	end

	-- He waves when you walk up, on the same 16-stud / 8-second-cooldown rules the island NPCs use, so he does
	-- not wave manically at someone standing at his stall shopping.
	if traderShoulder and traderRest then
		task.spawn(function()
			local lastWave, waving = -math.huge, false
			while m.Parent do            -- gated on the model, so this dies with the cave
				task.wait(0.25)
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hrp and not waving and (hrp.Position - body.Position).Magnitude <= 16
					and (os.clock() - lastWave) >= 8 then
					lastWave = os.clock(); waving = true
					local t0 = os.clock()
					while os.clock() - t0 < 2.2 and m.Parent do
						local t = os.clock() - t0
						local ease = math.clamp(t / 0.25, 0, 1) * math.clamp((2.2 - t) / 0.25, 0, 1)
						local lift  = math.rad(105) * ease
						local swing = math.rad(22) * ease * math.sin(t * 9)
						traderShoulder.C0 = traderRest * CFrame.Angles(0, 0, -1 * (lift + swing))
						task.wait()
					end
					traderShoulder.C0 = traderRest   -- back to rest, exactly
					waving = false
				end
			end
		end)
	end

	-- LIGHT. A cave with default lighting is just a grey room; a cave with NO light is a black screen and a
	-- player who thinks the game broke. One warm lamp over the stall is the whole effect.
	local lamp = part(m, "Lamp", Vector3.new(1.2, 1.2, 1.2), stallCF * CFrame.new(0, 8.5, 0),
		Color3.fromRGB(255, 196, 110), Enum.Material.Neon)
	lamp.CanCollide = false
	local pl = Instance.new("PointLight")
	pl.Brightness = 3; pl.Range = 46; pl.Color = Color3.fromRGB(255, 200, 130); pl.Parent = lamp

	local shopPrompt = Instance.new("ProximityPrompt")
	shopPrompt.ActionText = "Trade"; shopPrompt.ObjectText = "Shady Sal"
	shopPrompt.HoldDuration = 0; shopPrompt.MaxActivationDistance = 14
	shopPrompt.RequiresLineOfSight = false; shopPrompt.Parent = body

	-- EXIT. Its own alcove on the far side, so leaving is a deliberate walk rather than something you trip on
	-- the moment you arrive facing the entrance.
	local exitPad = part(m, "ExitPad", Vector3.new(8, 1, 8), CFrame.new(origin + Vector3.new(0, 1.5, CAVE_D/2 - 8)),
		Color3.fromRGB(120, 104, 78), Enum.Material.Sand)
	local exitPrompt = Instance.new("ProximityPrompt")
	exitPrompt.ActionText = "Climb Out"; exitPrompt.ObjectText = "Way Back Up"
	exitPrompt.HoldDuration = 0.4; exitPrompt.MaxActivationDistance = 12
	exitPrompt.RequiresLineOfSight = false; exitPrompt.Parent = exitPad

	--==================================================================
	-- THE ARRIVAL CLEARING
	--==================================================================
	-- You arrive in the CENTRE of the room, and the centre is GUARANTEED clear. The room is now dense with
	-- randomly-placed clutter, and "random" plus "teleport destination" eventually means materialising inside
	-- a crate. Rather than trusting that no generator above happens to land here (true today, one seed tweak
	-- from false), a sweep DELETES any part inside the arrival cylinder after everything is built.
	--
	-- Flat ground cover is whitelisted -- the floor, concrete plates and their cracks are what you land ON.
	-- The two particle anchors are whitelisted too (destroying them kills the dust and haze) and made
	-- non-collidable instead, since both sit at the room centre by design.
	local CLEAR_AT = origin + Vector3.new(0, 1, 3)   -- just forward of centre, facing the stall
	local CLEAR_R = 7
	local keepClear = {
		Floor = true, ConcretePlate = true, Crack = true, Rug = true,
		DustAnchor = true, HazeAnchor = true,
		RockFacet = true,   -- ground, not debris -- sweeping it would leave a flat bald patch at the spawn
	}

	-- ===== WHICH PROPS ARE SOLID =====
	-- Everything a player would expect to bump into IS bumped into: walking through a crate stack breaks the
	-- room harder than any amount of dressing fixes it. Done by NAME in one pass here, not per-creation-site,
	-- so a prop can never be forgotten -- if it is big, its name is in this set.
	--
	-- Deliberately NOT solid: thin flat things (cables, tape, stains, notes, graffiti), overhead things
	-- (chains, pipes at height, pendants), the curtain (walking through it is the point), and the lookout
	-- (blocking the entrance with an invisible-wall person would read as a bug, not a guard).
	local SOLID = {
		Boulder = true, Stalagmite = true, Crystal = true,
		Crate = true, CrateSlat = true, Tarp = true, Barrel = true, BarrelHoop = true, Sack = true,
		Brazier = true, Strongbox = true, Stall = true,
		DeskTop = true, DeskPost = true, DeskPlate = true, DeskDrum = true,
		BackPost = true, BackBoard = true, Lockbox = true, Radio = true, Monitor = true,
		BulletinBoard = true, BoardLeg = true, Barricade = true,
		PenBarrel = true, CageBar = true, CageTop = true, PriedCrate = true, CrateLid = true,
		Generator = true, GenStack = true, FuelTank = true, TankCradle = true, FuelPipe = true,
		BenchTop = true, BenchLeg = true, Toolbox = true,
		ShelfPost = true, ShelfBoard = true, ShelfBox = true, GasCanister = true,
		ConveyorBed = true, ConveyorRail = true, ConveyorLeg = true,
		ChainLink = true, FenceRail = true, SteelDoor = true,
		MineCart = true, CartWheel = true, CartCrate = true,
		PlatformPost = true, MinePost = true, MineLintel = true,
	}

	-- ===== THE WALK CORRIDOR =====
	-- With props solid, random placement could wall the player in. One guaranteed lane runs from the desk,
	-- through the arrival clearing, to the climb-out pad -- everything solid inside it is deleted, so the
	-- one walk the player MUST make is always possible. Overhead props survive (the y check).
	local function inCorridor(p)
		return math.abs(p.X - origin.X) < 5.5
			and p.Z - origin.Z > -16 and p.Z - origin.Z < 42
			and p.Y < origin.Y + 9
	end

	local swept, solidified, dimmed = 0, 0, 0
	for _, d in ipairs(m:GetDescendants()) do
		-- ===== EVERY LIGHT IN THE ROOM AT HALF POWER =====
		-- Done here, in the one pass that already walks every descendant, rather than by editing forty
		-- Brightness values at forty creation sites -- which guarantees nothing is missed and that any lamp
		-- added later is dimmed automatically. `Light` is the base class, so Point/Spot/Surface all match.
		-- The Neon materials keep their own glow (that is material, not light), so things still LOOK lit --
		-- they just throw half as much light onto everything around them.
		if d:IsA("Light") then
			d.Brightness = d.Brightness * 0.25   -- cut to a QUARTER (halved once, then halved again on
			                                     -- request) -- points of light in the dark, not floodlights
			dimmed += 1
		elseif d:IsA("BasePart") then
			if d.Name == "DustAnchor" or d.Name == "HazeAnchor" then
				d.CanCollide = false
			else
				local flat = d.Position - CLEAR_AT
				local inClearing = not keepClear[d.Name]
					and Vector3.new(flat.X, 0, flat.Z).Magnitude < CLEAR_R
					and d.Position.Y < origin.Y + 12
				if inClearing then
					d:Destroy(); swept += 1
				elseif SOLID[d.Name] then
					if inCorridor(d.Position) then
						d:Destroy(); swept += 1
					else
						d.CanCollide = true; solidified += 1
					end
				end
			end
		end
	end
	print(("[SecretCave] final pass: %d prop(s) solidified, %d swept from the landing zone + walk corridor, %d light(s) dimmed to 25%%")
		:format(solidified, swept, dimmed))

	--==================================================================
	-- THE DETAIL PASS
	--==================================================================
	-- One pass, AFTER the sweep (so nothing is detailed and then deleted), that walks every surviving prop
	-- and adds the small secondary geometry that separates "a box painted like a crate" from "a crate":
	-- battens, bands, rivets, rollers, sockets. Everything is still blocks and cylinders -- the low-poly
	-- look is preserved because complexity comes from MORE SIMPLE SHAPES, never from smoother ones.
	--
	-- The budget is deliberately uneven, matching where players actually look: the desk, the pendants, the
	-- monitor and the machines get the most; ring-wall crates and barrels get one signature accent each;
	-- boulders and wall filler get nothing. Detail spent where nobody looks is just triangles.
	--
	-- Driven by each part's own Size/CFrame in LOCAL space, so it lands correctly whatever the prop's
	-- random rotation -- and any prop added later gets dressed automatically by name.
	local function accent(host, name, size, offsetCF, color, mat)
		local p2 = Instance.new("Part")
		p2.Name = name; p2.Size = size; p2.CFrame = host.CFrame * offsetCF
		p2.Color = color; p2.Material = mat or Enum.Material.Metal
		p2.Anchored = true; p2.CanCollide = false; p2.CanQuery = false; p2.CastShadow = false
		p2.TopSurface = Enum.SurfaceType.Smooth; p2.BottomSurface = Enum.SurfaceType.Smooth
		p2.Parent = m
		return p2
	end
	local woodDark = Color3.fromRGB(70, 46, 24)
	local ironDark = Color3.fromRGB(52, 50, 48)
	local detailed = 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d.Parent == m then
			local n, s = d.Name, d.Size
			if n == "Crate" or n == "CartCrate" or n == "PlatformCrate" or n == "PriedCrate" then
				-- corner battens: THE low-poly crate signature
				for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
					accent(d, "CrateBatten", Vector3.new(s.X * 0.14, s.Y * 1.04, s.Z * 0.14),
						CFrame.new(c[1] * s.X * 0.43, 0, c[2] * s.Z * 0.43), woodDark, Enum.Material.Wood)
				end
				detailed += 1
			elseif n == "ShelfBox" then   -- small boxes get a single lid strip, not the full treatment
				accent(d, "BoxLid", Vector3.new(s.X * 1.04, s.Y * 0.16, s.Z * 1.04),
					CFrame.new(0, s.Y * 0.46, 0), woodDark, Enum.Material.Wood)
				detailed += 1
			elseif n == "Barrel" or n == "PenBarrel" then
				for _, xo in ipairs({ -0.32, 0.32 }) do
					accent(d, "BarrelBand", Vector3.new(s.X * 0.1, s.Y * 1.06, s.Z * 1.06),
						CFrame.new(s.X * xo, 0, 0), ironDark).Shape = Enum.PartType.Cylinder
				end
				accent(d, "BarrelBung", Vector3.new(0.18, 0.5, 0.5),
					CFrame.new(s.X * 0.51, 0, 0), woodDark, Enum.Material.Wood).Shape = Enum.PartType.Cylinder
				detailed += 1
			elseif n == "FuelTank" then
				for _, xo in ipairs({ -0.3, 0.3 }) do
					accent(d, "TankBand", Vector3.new(s.X * 0.08, s.Y * 1.05, s.Z * 1.05),
						CFrame.new(s.X * xo, 0, 0), ironDark).Shape = Enum.PartType.Cylinder
				end
				accent(d, "TankCap", Vector3.new(0.35, 0.6, 0.6),
					CFrame.new(s.X * 0.5, 0, 0), Color3.fromRGB(210, 172, 66)).Shape = Enum.PartType.Cylinder
				detailed += 1
			elseif n == "GasCanister" then
				accent(d, "CanCollar", Vector3.new(s.X * 0.12, s.Y * 0.65, s.Z * 0.65),
					CFrame.new(s.X * 0.4, 0, 0), ironDark).Shape = Enum.PartType.Cylinder
				accent(d, "CanNozzle", Vector3.new(0.3, 0.2, 0.2),
					CFrame.new(s.X * 0.56, 0, 0), Color3.fromRGB(150, 150, 158))
				detailed += 1
			elseif n == "Generator" then
				for i = -1, 1 do   -- intake slats on the face
					accent(d, "GenVent", Vector3.new(s.X * 0.62, 0.14, 0.08),
						CFrame.new(0, i * 0.4, s.Z * 0.52), ironDark)
				end
				detailed += 1
			elseif n == "Sack" then
				accent(d, "SackTie", Vector3.new(0.5, 0.38, 0.5),
					CFrame.new(0, s.Y * 0.55, 0), Color3.fromRGB(150, 128, 90), Enum.Material.Fabric)
				detailed += 1
			elseif n == "Brazier" then   -- glowing coals sitting in the drum mouth
				local coal = accent(d, "BrazierCoals", Vector3.new(0.3, s.Y * 0.78, s.Z * 0.78),
					CFrame.new(s.X * 0.34, 0, 0), Color3.fromRGB(255, 120, 40), Enum.Material.Neon)
				coal.Shape = Enum.PartType.Cylinder
				coal.Transparency = 0.1
				detailed += 1
			elseif n == "SteelDoor" then
				for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
					accent(d, "DoorRivet", Vector3.new(0.22, 0.22, 0.16),
						CFrame.new(c[1] * s.X * 0.4, c[2] * s.Y * 0.44, -s.Z * 0.58),
						Color3.fromRGB(140, 140, 148))
				end
				for _, yo in ipairs({ -0.3, 0.3 }) do
					accent(d, "DoorHinge", Vector3.new(0.28, 0.9, 0.34),
						CFrame.new(-s.X * 0.52, yo * s.Y, 0), ironDark)
				end
				detailed += 1
			elseif n == "MineCart" then
				for _, e in ipairs({   -- rim rails around the lip + axles under the tub
					{ Vector3.new(s.X * 1.08, 0.28, 0.34), CFrame.new(0, s.Y * 0.5, s.Z * 0.47) },
					{ Vector3.new(s.X * 1.08, 0.28, 0.34), CFrame.new(0, s.Y * 0.5, -s.Z * 0.47) },
					{ Vector3.new(0.34, 0.28, s.Z * 1.02), CFrame.new(s.X * 0.47, s.Y * 0.5, 0) },
					{ Vector3.new(0.34, 0.28, s.Z * 1.02), CFrame.new(-s.X * 0.47, s.Y * 0.5, 0) },
					{ Vector3.new(s.X * 1.1, 0.24, 0.24), CFrame.new(0, -s.Y * 0.55, s.Z * 0.34) },
					{ Vector3.new(s.X * 1.1, 0.24, 0.24), CFrame.new(0, -s.Y * 0.55, -s.Z * 0.34) },
				}) do
					accent(d, "CartTrim", e[1], e[2], ironDark)
				end
				detailed += 1
			elseif n == "MinePost" then
				accent(d, "PostStrap", Vector3.new(s.X * 1.16, 0.35, s.Z * 1.16),
					CFrame.new(0, s.Y * 0.28, 0), ironDark)
				detailed += 1
			elseif n == "WallPipe" then
				for _, xo in ipairs({ -0.48, 0.48 }) do
					accent(d, "PipeFlange", Vector3.new(0.18, s.Y * 1.35, s.Z * 1.35),
						CFrame.new(s.X * xo, 0, 0), Color3.fromRGB(96, 74, 52)).Shape = Enum.PartType.Cylinder
				end
				detailed += 1
			elseif n == "ConveyorBed" then
				for i = -2, 2 do   -- rollers under the belt line: the machine's working parts on show
					accent(d, "ConveyorRoller", Vector3.new(s.Z * 0.9, 0.55, 0.55),
						CFrame.new(i * s.X * 0.16, -0.55, 0) * CFrame.Angles(0, math.rad(90), 0),
						Color3.fromRGB(96, 98, 104)).Shape = Enum.PartType.Cylinder
				end
				detailed += 1
			elseif n == "ChainLink" then   -- crossed braces, the cheapest possible read of "mesh"
				local thinX = s.X < s.Z
				local span = thinX and s.Z or s.X
				local diag = math.sqrt(s.Y * s.Y + span * span) * 0.92
				local tilt = math.atan2(span, s.Y)
				for _, sign in ipairs({ 1, -1 }) do
					accent(d, "FenceBrace", Vector3.new(0.15, diag, 0.15),
						thinX and CFrame.Angles(sign * tilt, 0, 0) or CFrame.Angles(0, 0, sign * tilt),
						Color3.fromRGB(96, 98, 104))
				end
				detailed += 1
			elseif n == "Strongbox" or n == "Lockbox" then
				accent(d, "BoxBand", Vector3.new(s.X * 0.16, s.Y * 1.06, s.Z * 1.06),
					CFrame.new(0, 0, 0), ironDark)
				detailed += 1
			elseif n == "Radio" then
				for i = 0, 1 do
					accent(d, "RadioKnob", Vector3.new(0.16, 0.16, 0.1),
						CFrame.new(-s.X * 0.25 + i * 0.45, -s.Y * 0.12, s.Z * 0.55),
						Color3.fromRGB(220, 220, 228))
				end
				detailed += 1
			elseif n == "Monitor" then
				accent(d, "Keyboard", Vector3.new(s.X * 0.95, 0.12, 0.8),
					CFrame.new(0, -s.Y * 0.5, s.Z * 1), Color3.fromRGB(80, 82, 88))
				detailed += 1
			elseif n == "MonitorScreen" then
				for i = 0, 2 do   -- terminal readout lines -- the screen shows SOMETHING, unreadably
					accent(d, "ScreenLine", Vector3.new(s.X * (0.75 - i * 0.18), 0.07, 0.02),
						CFrame.new(-s.X * (0.08 + i * 0.06), s.Y * (0.28 - i * 0.24), s.Z * 0.7),
						Color3.fromRGB(30, 90, 45), Enum.Material.SmoothPlastic)
				end
				detailed += 1
			elseif n == "Tarp" then
				accent(d, "TarpRope", Vector3.new(s.X * 1.06, 0.12, 0.14),
					CFrame.new(0, s.Y * 0.6, 0), Color3.fromRGB(150, 128, 90), Enum.Material.Fabric)
				accent(d, "TarpRope", Vector3.new(0.14, 0.12, s.Z * 1.06),
					CFrame.new(0, s.Y * 0.6, 0), Color3.fromRGB(150, 128, 90), Enum.Material.Fabric)
				detailed += 1
			elseif n == "Bulb" then
				-- ===== ONE FIXTURE FAMILY AROUND THE DESK =====
				-- The pendants over the counter and the string bulbs passing behind it used to be two
				-- different products -- shaded green-metal lamps beside bare orange orbs, which read as a
				-- mistake at the room's brightest spot. Any string bulb within 16 studs of the stall now
				-- gets the SAME mini shade, the same warm bulb colour and the same light colour as the
				-- pendants, so every fixture near Sal matches. Far bulbs keep the plain socket -- out in
				-- the gloom, mismatch reads as scavenged wiring, which is right.
				local dx = d.Position.X - stallCF.Position.X
				local dz = d.Position.Z - stallCF.Position.Z
				if dx * dx + dz * dz <= 16 * 16 then
					accent(d, "BulbShade", Vector3.new(0.7, 1.4, 1.4),
						CFrame.new(0, s.Y * 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)),
						Color3.fromRGB(58, 72, 58)).Shape = Enum.PartType.Cylinder
					accent(d, "BulbSocket", Vector3.new(0.3, 0.45, 0.45),
						CFrame.new(0, s.Y * 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)),
						ironDark).Shape = Enum.PartType.Cylinder
					d.Color = Color3.fromRGB(255, 214, 150)          -- the pendants' bulb colour
					local L = d:FindFirstChildOfClass("PointLight")
					if L then L.Color = Color3.fromRGB(255, 205, 140) end -- and their light colour
				else
					accent(d, "BulbSocket", Vector3.new(0.34, 0.3, 0.34),
						CFrame.new(0, s.Y * 0.52, 0), ironDark)
				end
				detailed += 1
			elseif n == "PendantShade" then
				-- the fixtures over the desk get the full treatment -- rim ring at the mouth, an inner glow
				-- disc so looking up into one shows a lit interior, and a socket collar to the cord
				accent(d, "ShadeRim", Vector3.new(0.1, s.Y * 1.1, s.Z * 1.1),
					CFrame.new(-s.X * 0.47, 0, 0), ironDark).Shape = Enum.PartType.Cylinder
				local disc = accent(d, "ShadeGlow", Vector3.new(0.05, s.Y * 0.72, s.Z * 0.72),
					CFrame.new(-s.X * 0.4, 0, 0), Color3.fromRGB(255, 224, 170), Enum.Material.Neon)
				disc.Shape = Enum.PartType.Cylinder
				disc.Transparency = 0.15
				accent(d, "ShadeSocket", Vector3.new(0.32, 0.5, 0.5),
					CFrame.new(s.X * 0.55, 0, 0), ironDark).Shape = Enum.PartType.Cylinder
				detailed += 1
			end
		end
	end
	print(("[SecretCave] detail pass dressed %d prop(s) -- battens, bands, rivets, rollers, sockets"):format(detailed))

	m.Parent = Workspace
	caveModel = m
	builtRefs = {
		model = m,
		-- Land in the clearing FACING THE TRADER, so the first thing on screen is the reason the room
		-- exists. The old point was by the south wall next to the lookout -- with the room this full, that
		-- meant arriving nose-first into crate stacks.
		entry = CFrame.lookAt(CLEAR_AT + Vector3.new(0, 3.5, 0), Vector3.new(origin.X, CLEAR_AT.Y + 3.5, origin.Z - 18)),
		shop  = shopPrompt,
		exit  = exitPrompt,
	}
	return builtRefs
end

--======================================================================
-- SHOP UI
--======================================================================
local buyRemote  = ReplicatedStorage:WaitForChild("SecretTraderBuy", 30)
local resultRmt  = ReplicatedStorage:WaitForChild("SecretTraderResult", 30)
local stockValue = ReplicatedStorage:WaitForChild("SecretTraderStock", 30)

local shopGui, shopStatus
-- ===== THE PANEL IS DARK, AND THAT IS A DELIBERATE EXCEPTION =====
-- Every other panel in this game is house-blue and bright (and should stay that way). This one is charcoal
-- and amber ON PURPOSE: it opens inside a pitch-black cave, lit by pendant lamps, sold by a man called Shady
-- Sal -- a cheerful blue shop panel here would break the scene harder than any prop could fix. Contrast is
-- kept high (cream text on near-black) so it stays as readable as the bright panels.
local function buildShop()
	if shopGui then return shopGui end
	shopGui = Instance.new("ScreenGui")
	shopGui.Name = "SecretTraderGui"; shopGui.ResetOnSpawn = false; shopGui.Enabled = false
	shopGui.DisplayOrder = 120; shopGui.Parent = playerGui

	local CREAM  = Color3.fromRGB(255, 244, 224)
	local AMBER  = Color3.fromRGB(255, 176, 92)
	local GOLD   = Color3.fromRGB(216, 164, 60)
	local MUTED  = Color3.fromRGB(150, 146, 138)

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(700, 520)      -- the house panel size, same as the Shop
	panel.Position = UDim2.fromScale(0.5, 0.5); panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(26, 24, 30)
	panel.BorderSizePixel = 0; panel.Parent = shopGui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
	local ps = Instance.new("UIStroke", panel); ps.Thickness = 2; ps.Color = AMBER; ps.Transparency = 0.35

	-- header band with the candle title and Sal's motto in small print underneath
	local head = Instance.new("Frame")
	head.Size = UDim2.new(1, 0, 0, 74); head.BackgroundColor3 = Color3.fromRGB(38, 34, 42)
	head.BorderSizePixel = 0; head.Parent = panel
	Instance.new("UICorner", head).CornerRadius = UDim.new(0, 14)
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -140, 0, 44); title.Position = UDim2.fromOffset(18, 6)
	title.BackgroundTransparency = 1; title.Font = Enum.Font.FredokaOne; title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = AMBER; title.Text = "\xF0\x9F\x95\xAF SHADY SAL'S"
	title.Parent = head
	local motto = Instance.new("TextLabel")
	motto.Size = UDim2.new(1, -140, 0, 18); motto.Position = UDim2.fromOffset(20, 50)
	motto.BackgroundTransparency = 1; motto.Font = Enum.Font.Gotham; motto.TextSize = 13
	motto.TextXAlignment = Enum.TextXAlignment.Left
	motto.TextColor3 = MUTED; motto.Text = "everything fell off a blimp. don't ask."
	motto.Parent = head

	-- the NO REFUNDS stamp: rotated, red, slightly transparent -- rubber-stamped over the corner like the
	-- paperwork it replaces
	local stamp = Instance.new("TextLabel")
	stamp.Size = UDim2.fromOffset(150, 34); stamp.Position = UDim2.new(1, -210, 0, 22)
	stamp.BackgroundTransparency = 1; stamp.Font = Enum.Font.FredokaOne; stamp.TextScaled = true
	stamp.TextColor3 = Color3.fromRGB(210, 60, 50); stamp.TextTransparency = 0.15
	stamp.Rotation = -8; stamp.Text = "NO REFUNDS"; stamp.Parent = head
	local ss = Instance.new("UIStroke", stamp); ss.Thickness = 2
	ss.Color = Color3.fromRGB(210, 60, 50); ss.Transparency = 0.5

	-- X ONLY. A stray tap anywhere else must never close this -- and closing must never eject you from the
	-- cave, which is why this button does nothing but hide the panel.
	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(44, 44); close.Position = UDim2.new(1, -54, 0, 14)
	close.BackgroundColor3 = Color3.fromRGB(150, 44, 44); close.Text = "X"
	close.Font = Enum.Font.FredokaOne; close.TextScaled = true
	close.TextColor3 = CREAM; close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)
	close:SetAttribute("BTS_Skip", true)
	close.MouseButton1Click:Connect(function() shopGui.Enabled = false end)

	shopStatus = Instance.new("TextLabel")
	shopStatus.Size = UDim2.new(1, -24, 0, 30); shopStatus.Position = UDim2.new(0, 12, 1, -38)
	shopStatus.BackgroundTransparency = 1; shopStatus.Font = Enum.Font.GothamBold
	shopStatus.TextSize = 17; shopStatus.TextColor3 = AMBER
	shopStatus.Text = "He nods at the crates. Nothing here has papers."; shopStatus.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -24, 1, -126); list.Position = UDim2.fromOffset(12, 82)
	list.BackgroundTransparency = 1; list.BorderSizePixel = 0
	list.ScrollBarThickness = 6; list.ScrollBarImageColor3 = AMBER; list.Parent = panel
	local layout = Instance.new("UIListLayout", list)
	layout.Padding = UDim.new(0, 8)

	-- one emoji per item id so rows are told apart at a glance; anything unrecognised gets Sal's candle
	local ICONS = {
		hotcoins = "\u{1F4B0}", boost2x = "\u{26A1}", boostspeed = "\u{1F680}",
		basiccrate = "\u{1F4E6}", mystery = "\u{2753}",
	}

	-- Stock is drawn from the SERVER's table (published as a StringValue), never from a copy kept here. A
	-- second price list in this file would drift out of step the first time a price changed, and the player
	-- would see one number and be charged another. Field order: id, name, price, street, desc.
	local rows = 0
	for _, entry in ipairs(string.split(stockValue and stockValue.Value or "", "\31")) do
		local f = string.split(entry, "\30")
		if #f >= 5 then
			local id, name, price, street, desc = f[1], f[2], tonumber(f[3]) or 0, tonumber(f[4]) or 0, f[5]
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -12, 0, 92); row.BackgroundColor3 = Color3.fromRGB(42, 38, 46)
			row.BorderSizePixel = 0; row.Parent = list
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
			local rs = Instance.new("UIStroke", row); rs.Thickness = 1
			rs.Color = AMBER; rs.Transparency = 0.7

			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.fromOffset(56, 56); icon.Position = UDim2.fromOffset(12, 18)
			icon.BackgroundColor3 = Color3.fromRGB(28, 26, 32); icon.Font = Enum.Font.FredokaOne
			icon.TextSize = 32; icon.TextColor3 = CREAM
			icon.Text = ICONS[id] or "\xF0\x9F\x95\xAF"; icon.Parent = row
			Instance.new("UICorner", icon).CornerRadius = UDim.new(0, 10)

			local n = Instance.new("TextLabel")
			n.Size = UDim2.new(1, -320, 0, 30); n.Position = UDim2.fromOffset(80, 10)
			n.BackgroundTransparency = 1; n.Font = Enum.Font.FredokaOne; n.TextXAlignment = Enum.TextXAlignment.Left
			n.TextSize = 23; n.TextColor3 = CREAM; n.Text = name; n.Parent = row

			local d = Instance.new("TextLabel")
			d.Size = UDim2.new(1, -320, 0, 44); d.Position = UDim2.fromOffset(80, 40)
			d.BackgroundTransparency = 1; d.Font = Enum.Font.Gotham; d.TextXAlignment = Enum.TextXAlignment.Left
			d.TextYAlignment = Enum.TextYAlignment.Top
			d.TextSize = 14; d.TextWrapped = true; d.TextColor3 = MUTED
			d.Text = desc; d.Parent = row

			-- ===== STREET PRICE vs SAL'S PRICE =====
			-- The struck-through "up top" number is what sells every row as contraband: the same goods, the
			-- legal price, and the number Sal actually wants under it. RichText <s> does the strikethrough;
			-- a street price of 0 means nobody knows what it is worth up top, which gets '???'.
			local streetLbl = Instance.new("TextLabel")
			streetLbl.Size = UDim2.fromOffset(150, 22); streetLbl.Position = UDim2.new(1, -164, 0, 12)
			streetLbl.BackgroundTransparency = 1; streetLbl.Font = Enum.Font.Gotham
			streetLbl.TextSize = 14; streetLbl.RichText = true
			streetLbl.TextXAlignment = Enum.TextXAlignment.Right
			streetLbl.TextColor3 = MUTED
			streetLbl.Text = street > 0
				and ("up top: <s>" .. street .. " \u{1FA99}</s>")
				or "up top: ???"
			streetLbl.Parent = row

			local buy = Instance.new("TextButton")
			buy.Size = UDim2.fromOffset(150, 44); buy.Position = UDim2.new(1, -164, 0, 38)
			buy.BackgroundColor3 = GOLD; buy.Font = Enum.Font.FredokaOne
			buy.TextScaled = true; buy.TextColor3 = Color3.fromRGB(46, 32, 12)
			buy.Text = "SAL: " .. price .. " \u{1FA99}"; buy.Parent = row
			Instance.new("UICorner", buy).CornerRadius = UDim.new(0, 8)
			buy:SetAttribute("BTS_Skip", true)   -- this button paints itself; the global label pass must not repaint it
			buy.MouseButton1Click:Connect(function()
				if buyRemote then buyRemote:FireServer(id) end
			end)
			rows += 1
		end
	end
	list.CanvasSize = UDim2.fromOffset(0, rows * 100)
	if rows == 0 then
		shopStatus.Text = "His stall is empty -- SecretTrader.server.lua did not publish any stock."
	end
	return shopGui
end

if resultRmt then
	resultRmt.OnClientEvent:Connect(function(ok, msg)
		if shopStatus then
			shopStatus.Text = msg or ""
			shopStatus.TextColor3 = ok and Color3.fromRGB(150, 245, 160) or Color3.fromRGB(255, 190, 150)
		end
		toast(msg or "", ok and Color3.fromRGB(120, 240, 140) or Color3.fromRGB(255, 170, 140))
	end)
end

--======================================================================
-- TELEPORTS
--======================================================================
local surfaceReturn, caveRefs

local function enterCave()
	if busy or inside then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	busy = true
	surfaceReturn = hrp.CFrame                   -- exactly where they stood, so coming back is not a guess

	-- THE BUILD IS ALLOWED TO FAIL WITHOUT WEDGING THE DOOR. When the rnd-ordering bug crashed buildCave,
	-- the error unwound past this point with `busy` still true -- so every later Enter press was silently
	-- swallowed by the guard above for the rest of the session. Any future build error now reports itself,
	-- resets the guard, and leaves the player on the surface able to try again.
	local okBuild, refsOrErr = pcall(buildCave)
	if not okBuild or not refsOrErr then
		busy = false
		warn("[SecretCave] buildCave FAILED -- staying on the surface. Error: " .. tostring(refsOrErr))
		toast("The way in seems blocked\xE2\x80\xA6", Color3.fromRGB(255, 170, 140))
		return
	end
	caveRefs = refsOrErr

	withFade(function()
		-- Lighting is GLOBAL and shared with the surface. Save it before stamping the cave look, or the
		-- player climbs out into permanent underground gloom and nothing ever puts it back.
		savedLighting = {
			Ambient = Lighting.Ambient, Outdoor = Lighting.OutdoorAmbient,
			Bright = Lighting.Brightness, Fog = Lighting.FogEnd, FogColor = Lighting.FogColor,
		}
		-- DARK on purpose, and darker than the first pass shipped. The room's whole lighting design is "dim
		-- everywhere except Sal's pendants" -- the lower this ambient goes, the harder that contrast works,
		-- and the more the far corners disappear into fog you cannot quite see into.
		-- BLACK, near enough. Pushed down twice on request: the room is readable ONLY by its own lamps --
		-- pendants, neon, crystals, machine glow -- and everything they do not reach is genuine darkness.
		-- The Neon materials do not need light to be visible, so the glowing props still read even here;
		-- what disappears is everything else, which is the point.
		Lighting.Ambient = Color3.fromRGB(2, 2, 3)
		Lighting.OutdoorAmbient = Color3.fromRGB(2, 2, 3)
		Lighting.Brightness = 0.04
		Lighting.FogEnd = 48; Lighting.FogColor = Color3.fromRGB(3, 3, 5)

		_G.caveNoFly = true       -- see the altitude note at the top: no flying inside
		inside = true
		char:PivotTo(caveRefs.entry)
		if caveRefs.exit then caveRefs.exit.Enabled = true end
	end)
	toast("You slip through the crack in the rock\xE2\x80\xA6", Color3.fromRGB(200, 190, 255))
	busy = false
end

local function restoreLighting()
	if not savedLighting then return end
	Lighting.Ambient = savedLighting.Ambient
	Lighting.OutdoorAmbient = savedLighting.Outdoor
	Lighting.Brightness = savedLighting.Bright
	Lighting.FogEnd = savedLighting.Fog
	Lighting.FogColor = savedLighting.FogColor
	savedLighting = nil
end

local function leaveCave()
	if busy or not inside then return end
	local char = player.Character
	if not char then return end
	busy = true
	if shopGui then shopGui.Enabled = false end
	withFade(function()
		inside = false
		_G.caveNoFly = false
		restoreLighting()
		if surfaceReturn then char:PivotTo(surfaceReturn + Vector3.new(0, 3, 0)) end
	end)
	busy = false
end

-- DEATH UNDERGROUND. Roblox respawns you on the surface, but the lighting stamp and the no-fly flag are
-- global and would otherwise stay stuck on forever -- a permanently dark world you cannot fly in.
player.CharacterAdded:Connect(function()
	if inside or savedLighting or _G.caveNoFly then
		inside = false
		_G.caveNoFly = false
		restoreLighting()
		if shopGui then shopGui.Enabled = false end
	end
end)

--======================================================================
-- THE LEAVE CAVE BUTTON
--======================================================================
-- Docked a few pixels under CoreClient's RETURN TO ISLAND button, at exactly its size, and only visible
-- while you are underground. The exit pad still works; this is the always-on-screen way out, because in a
-- near-black room "walk to the far side and find the sand pad" is a real ask for a lost eight-year-old.
--
-- It lives in its OWN ScreenGui rather than inside ReturnIslandGui -- parenting into another script's GUI
-- means being swept whenever that script rebuilds. Instead a tracker glues it under the Return button every
-- quarter second, wherever the HUD has put it, at whatever size it currently is.
local leaveGui = Instance.new("ScreenGui")
leaveGui.Name = "LeaveCaveGui"; leaveGui.ResetOnSpawn = false
leaveGui.IgnoreGuiInset = true   -- MUST match ReturnIslandGui's setting, or the copied pixel coordinates
                                 -- drift down by the topbar inset and the two buttons overlap
leaveGui.DisplayOrder = 90; leaveGui.Enabled = false; leaveGui.Parent = playerGui

local leaveBtn = Instance.new("TextButton")
leaveBtn.Size = UDim2.fromOffset(180, 56)        -- same footprint as the Return button above it
leaveBtn.Position = UDim2.fromOffset(130, 497)   -- fallback spot if the Return button is ever missing
leaveBtn.BackgroundColor3 = Color3.fromRGB(122, 62, 24)   -- earthy amber: the cave's colour, not Return's orange
leaveBtn.Font = Enum.Font.FredokaOne; leaveBtn.TextScaled = true
leaveBtn.TextColor3 = Color3.fromRGB(255, 244, 224)
leaveBtn.Text = "\u{1F9D7} LEAVE CAVE"
leaveBtn.Parent = leaveGui
Instance.new("UICorner", leaveBtn).CornerRadius = UDim.new(0, 12)
local lst = Instance.new("UIStroke", leaveBtn); lst.Thickness = 2; lst.Color = Color3.fromRGB(60, 30, 10)
leaveBtn:SetAttribute("BTS_Skip", true)          -- self-styled; the global label pass must not repaint it
leaveBtn.MouseButton1Click:Connect(leaveCave)

task.spawn(function()
	while true do
		task.wait(0.25)
		leaveGui.Enabled = inside
		if inside then
			-- glue to a couple of pixels under the Return button, wherever the HUD currently has it
			local rGui = playerGui:FindFirstChild("ReturnIslandGui")
			local rbtn = rGui and rGui:FindFirstChild("ReturnBtn")
			if rbtn then
				local p, sz2 = rbtn.AbsolutePosition, rbtn.AbsoluteSize
				leaveBtn.Position = UDim2.fromOffset(p.X, p.Y + sz2.Y + 4)
				leaveBtn.Size = UDim2.fromOffset(sz2.X, sz2.Y)
			end
			-- ===== WALK-AWAY SHOP CLOSE =====
			-- The one exception to "panels only close on X": walking more than 12 studs from Sal closes his
			-- panel. This is not a stray-tap close (the rule the X-only convention exists to prevent) -- it
			-- is the shopkeeper rule: you left the counter, the deal is off. 12 matches the Trade prompt's
			-- own activation range, so the panel exists exactly where the prompt does.
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp and shopGui and shopGui.Enabled then
				local salPart = builtRefs and builtRefs.shop and builtRefs.shop.Parent
				if salPart and salPart:IsA("BasePart")
					and (hrp.Position - salPart.Position).Magnitude > 12 then
					shopGui.Enabled = false
				end
			end
			-- ===== YANK WATCHDOG =====
			-- RETURN TO ISLAND sits directly above this button and still works while underground: it warps
			-- straight to the island stand, leaving the cave's black lighting stamp and the no-fly flag
			-- stuck on the surface world. If we believe we are 'inside' but the character is nowhere near
			-- the cave, something external moved us -- put the world back, without teleporting anywhere.
			if hrp and builtRefs and builtRefs.model.Parent
				and (hrp.Position - builtRefs.entry.Position).Magnitude > 400 then
				inside = false
				_G.caveNoFly = false
				restoreLighting()
				if shopGui then shopGui.Enabled = false end
			end
		end
	end
end)

--======================================================================
-- THE DOOR + THE HIDDEN SWITCH
--======================================================================
local enterPrompt   -- created up-front, kept DISABLED until the switch is pushed

-- ===== WHY THE PROMPT IS BUILT NOW AND ONLY *ENABLED* LATER =====
-- The first version created this prompt inside openDoor(), 1.7s after the switch was pushed. That is why
-- pressing E on the rock did nothing: until someone found and pushed the switch there was no prompt on the
-- door at all, so there was nothing for E to talk to -- and the switch was a mossy rock this script dropped
-- at a UserId-derived angle, which is a thing you can hunt for a long time without finding.
--
-- Building it here means the prompt provably EXISTS the moment the door resolves. `Enabled` is the only
-- thing the switch changes, which is one boolean instead of a delayed constructor that can silently not run.
local function armDoorPrompt()
	if enterPrompt or not doorPart then return end
	enterPrompt = Instance.new("ProximityPrompt")
	enterPrompt.Name = "EnterSecretCave"
	enterPrompt.ActionText = "Enter"; enterPrompt.ObjectText = "Dark Opening"
	enterPrompt.HoldDuration = 0.5
	-- Reach has to cover the WHOLE doorway, not a fixed radius from its centre. With the block enlarged, a flat
	-- 14 studs would leave the edges of the opening out of prompt range -- you would be stood in the doorway
	-- with nothing to press. Sized here, from the marker, because this is where the prompt is created; doing it
	-- in revealDoor would have been too late (openDoor reveals before it arms) and out of scope besides.
	local s = doorPart.Size
	enterPrompt.MaxActivationDistance = math.clamp(math.max(s.X, s.Y, s.Z) * 0.8, 14, 60)
	enterPrompt.RequiresLineOfSight = false   -- the door is invisible; line-of-sight tests on it are unreliable
	enterPrompt.Enabled = false               -- locked until the switch is pushed
	enterPrompt.Parent = doorPart
	enterPrompt.Triggered:Connect(enterCave)
end

local function openDoor()
	if isOpen or not doorPart then return end
	isOpen = true
	-- The cliff was bare until this moment -- THIS is where the cave becomes visible at all. Nothing marks it
	-- beforehand, so pulling the lever is what turns "an ordinary rock face" into "a way in".
	revealDoor(doorPart)
	armDoorPrompt()
	if enterPrompt then enterPrompt.Enabled = true end
	toast("Something heavy grinds open in the cliff\xE2\x80\xA6", Color3.fromRGB(255, 214, 120))

	-- ===== GUIDE THEM THERE =====
	-- The lever can be a long way from the door, and the player is usually facing the lever when it opens --
	-- pointed away from the thing that just happened. So the existing ground chevrons take them to it.
	--
	-- This drives GardenGuideTrail through _G.guideTrailTo rather than drawing its own arrows: two trails on
	-- screen at once would each be telling the player to walk somewhere different.
	if _G.guideTrailTo then
		pcall(function() _G.guideTrailTo(doorPart.Position) end)
		-- 45s, not 20 -- long enough to actually walk it if the lever is across the island. It also clears
		-- itself the moment they arrive (below), so this is only the backstop for someone who wanders off.
		task.delay(45, function() if _G.guideTrailClear then pcall(_G.guideTrailClear) end end)
	end

	-- clear the trail as soon as they reach the door, so it does not keep pointing at a place they are stood in
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 45 do
			task.wait(0.5)
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - doorPart.Position).Magnitude < 18 then
				if _G.guideTrailClear then pcall(_G.guideTrailClear) end
				return
			end
		end
	end)
end

task.spawn(function()
	doorPart = pollFor("secretcave", 60)
	if not doorPart then
		warn("[SecretCave] no Part named 'secretcave' found in Workspace after 60s -- the door cannot exist. " ..
			"Check the name in Studio (it is matched case-insensitively) and that it is a PART, not an empty Model.")
		return
	end
	-- ===== ANCHORED, INVISIBLE, AND WALK-THROUGH =====
	-- Anchored so it cannot be knocked loose or fall when something bumps it.
	--
	-- Invisible + non-colliding turns this Part into a pure TRIGGER VOLUME. That is the point: the "door" is
	-- not scenery you look at, it is a spot in the cliff you can walk into. Left solid it would be an
	-- invisible wall players bounce off, which reads as a bug; left visible it would be a floating grey block
	-- announcing the secret to everyone who wanders past.
	doorPart.Anchored = true
	doorPart.Transparency = 1
	doorPart.CanCollide = false
	doorPart.CanQuery = false      -- keeps it out of raycasts, so it can't block clicks or other systems' probes
	doorPart.CastShadow = false    -- an invisible part still casts a shadow otherwise -- a shadow with no object
	print(("[SecretCave] door found at (%.0f, %.0f, %.0f) -- anchored, invisible, walk-through"):format(
		doorPart.Position.X, doorPart.Position.Y, doorPart.Position.Z))

	-- The prompt is created NOW, disabled. See armDoorPrompt above for why this is not done inside openDoor.
	armDoorPrompt()

	-- ===== THE SWITCH: YOUR PART, NOT A GENERATED ONE =====
	-- The first version dropped its own rock at a UserId-derived angle and raycast it to the ground. Your log
	-- shows exactly why that was wrong:
	--     door   at (-251, 3597, 211)
	--     switch at (-236, 3645, 158)     <- 48 studs ABOVE the door
	-- The ray hit a rock face partway up the cliff instead of the ground, so the switch ended up planted in
	-- mid-air up the mountain. Unfindable, and its prompt was the only way to open the door.
	--
	-- A Part you placed by hand in Studio has none of that failure mode: it is exactly where you put it. So
	-- this now looks for one named 'switch' and uses it as-is, and generates nothing.
	-- ===== NEVER GIVE UP ON THE MARKER =====
	-- This used to poll for 60 seconds and then RETURN -- and a return here meant no lever was ever built,
	-- for the whole session. Coconut Cove is island 5; a player who spends their first minute on island 1
	-- may not have had 'switch' streamed in yet, and the one hint that the cave exists would simply never
	-- appear. It now retries forever in the background, warning ONCE so a genuinely missing/mis-named part
	-- is still reported, and builds the moment the part shows up however late that is.
	switchPart = pollFor("switch", 45)
	if not switchPart then
		warn("[SecretCave] no Part named 'switch' yet -- still watching. If it never appears, check the name " ..
			"in Studio (matched case-insensitively) and that it is a PART, not an empty Model (empty Models " ..
			"never stream in).")
		repeat
			switchPart = pollFor("switch", 30)
		until switchPart
		print("[SecretCave] 'switch' streamed in late -- building the lever now")
	end

	-- Your marker Part stays invisible and is used only as a POSITION -- a visible LEVER is built on it. The
	-- lever is the one thing in the world that hints any of this exists, so it has to look like a thing you
	-- operate: a plain grey block would read as scenery and get walked past.
	local function hideMarker()
		switchPart.Anchored = true
		switchPart.Transparency = 1
		switchPart.CanCollide = false
		switchPart.CanQuery = false
		switchPart.CastShadow = false
	end
	hideMarker()

	local leverModel, leverKnob = buildLever(switchPart)

	-- ===== THE PROMPT LIVES ON THE LEVER, NOT ON YOUR MARKER =====
	-- StreamingEnabled can remove your Studio-placed 'switch' Part when the player wanders far and put a
	-- FRESH copy back on return -- which would take the prompt away with it and undo the hiding above,
	-- leaving a bare grey block sitting inside the lever. The lever is client-built, so streaming never
	-- touches it: hanging the prompt there means the lever is always operable, and a watcher re-hides the
	-- marker if a new copy streams in.
	local promptHost = leverModel:FindFirstChild("LeverHousing") or leverModel:FindFirstChild("LeverBase")
	local sp = Instance.new("ProximityPrompt")
	sp.Name = "PushSecretSwitch"
	sp.ActionText = "Pull"; sp.ObjectText = "Strange Lever"
	sp.HoldDuration = 0.6
	sp.MaxActivationDistance = 12
	sp.RequiresLineOfSight = false
	sp.Parent = promptHost
	sp.Triggered:Connect(function()
		if isOpen then toast("The way is already open.", Color3.fromRGB(200, 200, 200)); return end
		sp.Enabled = false
		pullLever(leverKnob)      -- the arm swings down and the knob turns green
		openDoor()
	end)

	-- Keep the lever standing and the marker hidden for the rest of the session, whatever streaming does.
	task.spawn(function()
		while true do
			task.wait(2)
			if switchPart.Parent then
				if switchPart.Transparency < 1 then hideMarker() end   -- a fresh copy streamed in: re-hide it
			else
				-- the marker itself was streamed out. The lever does not care (it is ours, and anchored),
				-- but re-resolve so the watcher keeps working when the part comes back.
				local again = pollFor("switch", 20)
				if again then switchPart = again; hideMarker() end
			end
			if leverModel.Parent ~= Workspace then leverModel.Parent = Workspace end -- never let it vanish
		end
	end)

	local d = (switchPart.Position - doorPart.Position).Magnitude
	print(("[SecretCave] switch wired to YOUR part at (%.0f, %.0f, %.0f) -- %.0f studs from the door")
		:format(switchPart.Position.X, switchPart.Position.Y, switchPart.Position.Z, d))
end)

-- wire the cave's own prompts once it exists (they are created inside buildCave)
task.spawn(function()
	while true do
		task.wait(0.5)
		if caveRefs and caveRefs.shop and not caveRefs.shop:GetAttribute("Wired") then
			caveRefs.shop:SetAttribute("Wired", true)
			caveRefs.shop.Triggered:Connect(function()
				local g = buildShop()
				g.Enabled = true
			end)
			caveRefs.exit:SetAttribute("Wired", true)
			caveRefs.exit.Triggered:Connect(leaveCave)
		end
	end
end)

print("[SecretCave] ready -- watching for the 'secretcave' Part; hidden switch opens it, trader waits inside")
