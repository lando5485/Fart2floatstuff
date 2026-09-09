--======================================================================
-- Sinkhole.client.luau  (StarterPlayerScripts)  -- CandyRealm
--======================================================================
-- SINKHOLE -- a random island's floor opens; fall in for a private treasure grab.
--
--   * The SERVER picks the island (the most-populated one, so somebody always sees it) and
--     broadcasts one exact floor position -- every player sees the same hole in the same spot.
--   * Step onto it and you DROP: screen fades, you land in a candy cavern far below the map,
--     and you have 30 seconds to grab what is buried there before it seals over.
--   * The cave is PRIVATE and CLIENT-BUILT, exactly like TunnelBlast's underground mine --
--     nothing in it replicates, so every player gets their own untouched treasure room. The
--     per-player X offset is TunnelBlast's trick too: OTHER characters do replicate, so two
--     players in one shared void would haunt each other's caves as floating ghosts.
--
-- ===== THE HOLE NEVER TOUCHES THE REAL FLOOR =====
-- It is a dark disc laid ON the surface plus a swirl of particles -- cosmetic, no collision,
-- and the island's own geometry is never hidden or removed. Hiding floor-sized parts is how
-- island15 lost its chicken-zone floor and island18 its boundary (see the island15 note in the
-- project memory): size, not name, says whether hiding is safe, and a floor is never safe.
-- The "falling in" is a distance check that teleports you, not an actual pit.
--
-- ===== COINS GO THROUGH CoinEvent =====
-- Each candy fires CoinEvent:FireServer(n), the same client->server path every quest reward in
-- this realm uses, so the server-side caps and rate limits apply to this like everything else.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")
local Debris            = game:GetService("Debris")
local TextChatService   = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== TUNING =====
local HOLE_RADIUS   = 8        -- studs: how close to the disc's centre counts as falling in
local CAVE_TIME     = 45       -- seconds inside before it seals. Sized to the room: land on the
                               -- ledge, take the ramp down, cross the chocolate river, climb the
                               -- altar -- a first-timer needs ~25s just to see it all.
-- ⚠ THE CAVE MUST SIT ABOVE Workspace.FallenPartsDestroyHeight. The first version put it at
-- Y=-1600, and Roblox's default destroy plane is -500: the instant the teleport landed, every
-- unanchored part of the character was below the plane, the engine destroyed them, the player
-- died and respawned on the surface. From the player's side that read as "I jumped in and it
-- pushed me straight back out" -- no error, no message, just a silent kill floor.
-- So the depth is COMPUTED, clamped a comfortable margin above whatever the plane actually is,
-- and never lower than -380 (islands start at Y=150, so anything below ~0 is already "deep").
local function caveFloorY()
	local plane = -500
	pcall(function() plane = Workspace.FallenPartsDestroyHeight end)
	return math.max(-380, plane + 120)
end
local CANDY_COUNT   = 8        -- ordinary candies...
local CANDY_COINS   = { 15, 30 }   -- ...worth this range each
local GOLD_COINS    = 100      -- and one golden candy worth this
-- the same verified "heavy thing hits floor" asset LandingImpact and the cave rockfalls use --
-- one impact sound across the realm is what makes it read as one physical world
local THUD_ID       = "rbxassetid://5801257793"

local BROWN   = Color3.fromRGB(74, 48, 30)
local BROWN_D = Color3.fromRGB(38, 24, 14)
local CANDY_COLORS = {
	Color3.fromRGB(255, 92, 138), Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(150, 235, 130), Color3.fromRGB(190, 130, 255),
}
local GOLD = Color3.fromRGB(255, 205, 60)

--======================================================================
-- SMALL HELPERS
--======================================================================
local function mk(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function thud(at, t)
	-- LandingImpact's curve: volume up, pitch DOWN -- lower reads as bigger, not just louder
	local emit = mk({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(at) })
	emit.Parent = Workspace
	local s = Instance.new("Sound")
	s.SoundId = THUD_ID
	s.Volume = 0.25 + 0.75 * t
	s.PlaybackSpeed = 1.45 - 0.75 * t
	s.RollOffMaxDistance = 220
	s.Parent = emit
	s:Play()
	Debris:AddItem(emit, 6)
end

local function fade(toBlack, dur)
	local g = PlayerGui:FindFirstChild("SinkholeFade")
	if not g then
		g = Instance.new("ScreenGui")
		g.Name = "SinkholeFade"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true
		g.DisplayOrder = 80; g.Parent = PlayerGui
		local f = Instance.new("Frame")
		f.Name = "F"; f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = 1; f.BorderSizePixel = 0; f.Parent = g
	end
	TweenService:Create(g.F, TweenInfo.new(dur or 0.35), {
		BackgroundTransparency = toBlack and 0 or 1 }):Play()
end

--======================================================================
-- THE HOLE
--======================================================================
local holeModel, holePos

local function buildHole(pos)
	local m = Instance.new("Model"); m.Name = "SinkholeLocal"

	-- the mouth: a dark disc flush on the floor, with a lighter cracked rim around it. Cylinders
	-- lie on their side by default, so the CFrame stands them up into flat discs.
	local disc = mk({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, HOLE_RADIUS * 2, HOLE_RADIUS * 2),
		Color = Color3.fromRGB(8, 5, 3), Material = Enum.Material.Neon })
	disc.CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = m
	local rim = mk({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, HOLE_RADIUS * 2 + 3, HOLE_RADIUS * 2 + 3),
		Color = BROWN, Material = Enum.Material.Slate })
	rim.CFrame = CFrame.new(pos + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	rim.Parent = m

	-- swirl: dust being pulled DOWN into it, which is what says "this goes somewhere"
	local att = Instance.new("Attachment"); att.WorldPosition = pos + Vector3.new(0, 1, 0); att.Parent = Workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(BROWN, BROWN_D)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0.4) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(0.8, 1.3)
	pe.Rate = 26
	pe.Speed = NumberRange.new(4, 8)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -22, 0)      -- everything it emits gets dragged down the throat
	pe.Parent = att
	-- the attachment lives on Terrain, not in the model, so clearHole() destroys it by hand --
	-- Debris on it here would kill the swirl the moment the hole opened

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 240, 0, 56); bb.StudsOffset = Vector3.new(0, 7, 0)
	bb.AlwaysOnTop = true; bb.MaxDistance = 400; bb.Adornee = disc; bb.Parent = disc
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne; lbl.TextScaled = true
	lbl.TextColor3 = GOLD; lbl.Text = "\u{1F573} SINKHOLE -- JUMP IN!"
	lbl.Parent = bb
	local st = Instance.new("UIStroke"); st.Color = Color3.new(0, 0, 0); st.Thickness = 3; st.Parent = lbl

	-- the disc breathes, so it reads as alive rather than as a decal
	TweenService:Create(disc, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = Vector3.new(0.4, HOLE_RADIUS * 2 + 1.6, HOLE_RADIUS * 2 + 1.6) }):Play()

	m.Parent = Workspace
	return m, att
end

local holeAtt
local function clearHole()
	if holeModel then holeModel:Destroy(); holeModel = nil end
	if holeAtt then holeAtt:Destroy(); holeAtt = nil end
	holePos = nil
end

--======================================================================
-- THE CAVE
--======================================================================
local inCave = false
local caveFolder, returnCF, caveDeadline
local timerGui, timerLabel, grabbed, totalWorth

local function buildTimer()
	if timerGui then return end
	timerGui = Instance.new("ScreenGui")
	timerGui.Name = "SinkholeTimer"; timerGui.ResetOnSpawn = false; timerGui.DisplayOrder = 40
	timerGui.Enabled = false; timerGui.Parent = PlayerGui
	timerLabel = Instance.new("TextLabel")
	timerLabel.AnchorPoint = Vector2.new(0.5, 0); timerLabel.Position = UDim2.new(0.5, 0, 0, 64)
	timerLabel.Size = UDim2.new(0, 460, 0, 40); timerLabel.BackgroundTransparency = 1
	timerLabel.Font = Enum.Font.FredokaOne; timerLabel.TextScaled = true
	timerLabel.TextColor3 = GOLD; timerLabel.Text = ""
	timerLabel.Parent = timerGui
	local st = Instance.new("UIStroke"); st.Color = Color3.new(0, 0, 0); st.Thickness = 3; st.Parent = timerLabel
end

-- one candy the player can grab: a glowing ball on a little rock plinth
local candies = {}
local function placeCandy(at, gold)
	local plinth = mk({ Size = Vector3.new(2.2, 1.2, 2.2), Color = BROWN, Material = Enum.Material.Slate })
	plinth.CFrame = CFrame.new(at) * CFrame.Angles(0, math.random() * 6, 0)
	plinth.Parent = caveFolder
	local sz = gold and 2.4 or (1.3 + math.random() * 0.7)   -- scale variance: no two pickups identical
	local ball = mk({ Shape = Enum.PartType.Ball, Size = Vector3.new(sz, sz, sz),
		Color = gold and GOLD or CANDY_COLORS[math.random(1, #CANDY_COLORS)],
		-- Glass, not Neon: hard candy is glossy, not radioactive. Only the gold glows.
		Material = gold and Enum.Material.Neon or Enum.Material.Glass, Transparency = gold and 0 or 0.12 })
	ball.CFrame = CFrame.new(at + Vector3.new(0, 1.8, 0))
	ball.Parent = caveFolder
	-- LIGHT DISCIPLINE (see the cavern header): the whole cave runs on TWO light colours -- warm
	-- gold and a faint pink. Per-candy coloured lights were nine equal-brightness glows in nine
	-- hues, which is exactly the flat neon wash that reads as generated. The dim pink is just
	-- enough to find a pickup in a dark corner.
	local pl = Instance.new("PointLight")
	pl.Color = gold and GOLD or Color3.fromRGB(255, 214, 224)
	pl.Brightness = gold and 2 or 0.45
	pl.Range = gold and 15 or 6
	pl.Parent = ball
	TweenService:Create(ball, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ CFrame = ball.CFrame + Vector3.new(0, 0.7, 0) }):Play()
	candies[#candies + 1] = { part = ball, plinth = plinth, gold = gold, taken = false }
end

-- where enterCave puts the player: set by buildCave (the entry ledge), read after it returns
local caveSpawn

--============================================================================
-- THE CAVERN
--============================================================================
-- Two jobs, deliberately SEPARATED, because they pull in opposite directions:
--
--   THE SHELL seals. Floor, one overlapping ring of wall slabs, one unbroken cap. Every joint
--   overlaps by at least half a stud (butting parts flush is where hairline cracks come from),
--   nothing in it is tilted, and all of it is collidable. From outside, the cave is a plain
--   closed drum with nothing visible through it; from inside, no seam ever shows sky.
--
--   THE ROCK dresses. All the irregularity -- tilted crag faces, varied colour, stalactites,
--   clutter -- lives INSIDE the shell and owes it nothing. Making the sealing geometry itself
--   irregular is how you get both a leaky cave AND tidy rocks; splitting them gets neither.
--
-- LIGHT DISCIPLINE: two light colours total -- warm gold (chandelier, candles, the prize) and
-- faint pink (crystals, candy). Everything else is allowed to fall DARK, because darkness is
-- what sells a cave; the uniform many-coloured glow of v3 lit it like a vending machine.
--
-- NO Atmosphere INSTANCE, on purpose: SkyByAltitude drives Lighting.Atmosphere every frame, so
-- anything set here is overwritten before it renders (same reason SourRain tints via
-- ColorCorrection). Depth haze is faked locally instead: dark translucent films hung in front
-- of the far walls, which only exist for the 45 seconds the cave does.
--
-- The tour is unchanged from v3: land on the lit ledge, see the whole room, ramp down through
-- the candy field, cross the chocolate river, climb the altar for the gold.
local function buildCave(centre)
	caveFolder = Instance.new("Folder"); caveFolder.Name = "SinkholeCave"; caveFolder.Parent = Workspace
	candies, grabbed, totalWorth = {}, 0, 0
	local rng = Random.new(4241 + player.UserId)   -- YOUR cave is always the same cave
	local CREAM  = Color3.fromRGB(250, 246, 240)
	local RED_C  = Color3.fromRGB(235, 60, 70)
	local CHOC   = Color3.fromRGB(88, 52, 26)
	local CHOC_D = Color3.fromRGB(56, 32, 16)
	local WARM   = Color3.fromRGB(255, 208, 140)
	local PINK_L = Color3.fromRGB(255, 214, 224)

	local function solid(props)
		local pt = mk(props); pt.CanCollide = true; pt.Parent = caveFolder; return pt
	end
	local function deco(props, cf)
		local pt = mk(props); if cf then pt.CFrame = cf end; pt.Parent = caveFolder; return pt
	end
	-- rock never comes in ONE brown: every part gets its own jitter off one of two bases, so
	-- adjacent faces read as strata rather than as copies
	local function rockCol()
		local base = rng:NextNumber() < 0.5 and BROWN or BROWN_D
		local j = rng:NextInteger(-9, 9)
		return Color3.fromRGB(
			math.clamp(base.R * 255 + j, 0, 255),
			math.clamp(base.G * 255 + j, 0, 255),
			math.clamp(base.B * 255 + j, 0, 255))
	end
	local function rockMat()
		return rng:NextNumber() < 0.6 and Enum.Material.Slate or Enum.Material.Rock
	end

	-- ==================== THE SHELL (seals; nothing else may) ====================
	-- floor: bottom of the drum. 124 wide swallows the wall ring's footprint entirely.
	solid({ Size = Vector3.new(124, 4, 124), Color = BROWN_D, Material = Enum.Material.Slate,
		CFrame = CFrame.new(centre) })
	-- wall ring: 16 slabs at r=50. The chord between neighbours at that radius is 19.5 studs,
	-- and every slab is at least 24 wide -- guaranteed overlap at every joint, by construction.
	-- No tilt HERE: a tilted sealing slab opens a wedge of sky at its top edge.
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2
		solid({ Size = Vector3.new(24 + rng:NextNumber(0, 3), 50, 8), Color = rockCol(),
			Material = Enum.Material.Slate,
			CFrame = CFrame.new(centre + Vector3.new(math.cos(a) * 50, 26, math.sin(a) * 50))
				* CFrame.Angles(0, -a + math.rad(90), 0) })
	end
	-- cap: one unbroken slab. Wall tops reach y=51, cap spans y=46..50 -- a 5-stud overlap all
	-- the way round. No sky, no void, no light leaks; the god-ray below is paint, not a hole.
	solid({ Size = Vector3.new(124, 4, 124), Color = BROWN_D, Material = Enum.Material.Slate,
		CFrame = CFrame.new(centre + Vector3.new(0, 48, 0)) })

	-- ==================== THE ROCK (dresses; owes the seal nothing) ====================
	-- crag faces leaning against the shell: every one its own size, tilt, yaw and colour --
	-- the irregularity the shell is not allowed to have
	for i = 1, 20 do
		local a = (i / 20) * math.pi * 2 + rng:NextNumber(-0.12, 0.12)
		local r = 43 + rng:NextNumber(0, 4)
		solid({ Size = Vector3.new(6 + rng:NextNumber(0, 12), 8 + rng:NextNumber(0, 26), 4 + rng:NextNumber(0, 5)),
			Color = rockCol(), Material = rockMat(),
			CFrame = CFrame.new(centre + Vector3.new(math.cos(a) * r, 3 + rng:NextNumber(0, 16), math.sin(a) * r))
				* CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), rng:NextNumber(0, math.pi * 2),
					math.rad(rng:NextNumber(-12, 12))) })
	end
	-- the vaulting under the cap: tilted slabs stepping inward, with jittered size, angle and
	-- radius per slab so the ceiling never shows a repeating pattern
	for ring, spec in ipairs({ { r = 42, y = 36, tilt = 24, n = 11 }, { r = 27, y = 40, tilt = 44, n = 9 },
		{ r = 12, y = 43, tilt = 64, n = 7 } }) do
		for i = 1, spec.n do
			local a = (i / spec.n) * math.pi * 2 + ring * 0.41 + rng:NextNumber(-0.1, 0.1)
			solid({ Size = Vector3.new(2 + rng:NextNumber(0, 1.5), 12 + rng:NextNumber(0, 5), 8 + rng:NextNumber(0, 5)),
				Color = rockCol(), Material = rockMat(),
				CFrame = CFrame.new(centre + Vector3.new(math.cos(a) * (spec.r + rng:NextNumber(-2, 2)),
						spec.y + rng:NextNumber(-1.5, 1.5), math.sin(a) * (spec.r + rng:NextNumber(-2, 2))))
					* CFrame.Angles(0, -a, math.rad(spec.tilt + rng:NextNumber(-6, 6))) })
		end
	end
	-- stalactites, and hardened SUGAR drips between them -- translucent glassy threads at very
	-- different lengths, which is what makes the ceiling read as slowly leaking sweetness
	for _ = 1, 12 do
		local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(6, 38)
		local len = rng:NextNumber(4, 11)
		local top = solid({ Size = Vector3.new(1.4 + rng:NextNumber(0, 1.2), len, 1.4 + rng:NextNumber(0, 1.2)),
			Color = rockCol(), Material = rockMat(),
			CFrame = CFrame.new(centre + Vector3.new(math.cos(a) * r, 34 - len * 0.5, math.sin(a) * r))
				* CFrame.Angles(math.rad(rng:NextNumber(-7, 7)), 0, math.rad(rng:NextNumber(-7, 7))) })
		deco({ Size = Vector3.new(0.7, 2.2, 0.7), Color = BROWN_D, Material = Enum.Material.Slate },
			top.CFrame * CFrame.new(0, -len * 0.5 - 0.9, 0))
	end
	for _ = 1, 9 do
		local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(4, 40)
		local len = rng:NextNumber(2, 9)
		deco({ Size = Vector3.new(0.35, len, 0.35), Color = CREAM, Material = Enum.Material.Glass,
			Transparency = 0.45 },
			CFrame.new(centre + Vector3.new(math.cos(a) * r, 34 - len * 0.5, math.sin(a) * r)))
	end
	for _ = 1, 6 do
		local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(12, 36)
		local len = rng:NextNumber(3, 7)
		solid({ Size = Vector3.new(1.6 + rng:NextNumber(0, 1.4), len, 1.6 + rng:NextNumber(0, 1.4)),
			Color = rockCol(), Material = rockMat(),
			CFrame = CFrame.new(centre + Vector3.new(math.cos(a) * r, 2 + len * 0.5, math.sin(a) * r)) })
	end

	-- ==================== ENTRY: LEDGE, GOD-RAY, RAMP ====================
	local ledge = solid({ Size = Vector3.new(22, 3, 14), Color = rockCol(), Material = Enum.Material.Slate,
		CFrame = CFrame.new(centre + Vector3.new(0, 16, 40)) })
	for _ = 1, 6 do
		deco({ Size = Vector3.new(rng:NextNumber(1, 2.5), rng:NextNumber(0.8, 2), rng:NextNumber(1, 2.5)),
			Color = rockCol(), Material = rockMat() },
			ledge.CFrame * CFrame.new(rng:NextNumber(-9, 9), 2, rng:NextNumber(-5, 5))
				* CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0))
	end
	-- the god-ray is PAINT on a sealed ceiling: a dark scar disc under the cap and a soft beam
	-- below it. It says "you fell in here" without there being any actual hole to leak through.
	deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 9, 9), Color = Color3.fromRGB(6, 4, 2),
		Material = Enum.Material.SmoothPlastic },
		CFrame.new(centre + Vector3.new(0, 45.7, 40)) * CFrame.Angles(0, 0, math.rad(90)))
	deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(28, 6.5, 6.5), Color = Color3.fromRGB(255, 240, 205),
		Material = Enum.Material.Neon, Transparency = 0.88 },
		CFrame.new(centre + Vector3.new(0, 31, 40)) * CFrame.Angles(0, 0, math.rad(90)))
	solid({ Size = Vector3.new(10, 2, 34), Color = rockCol(), Material = Enum.Material.Slate,
		CFrame = CFrame.lookAt(centre + Vector3.new(0, 9, 25), centre + Vector3.new(0, 2, 9)) })
	caveSpawn = CFrame.new(centre + Vector3.new(0, 21, 40))

	-- ==================== THE CHOCOLATE RIVER (kept INSIDE the shell) ====================
	-- v3's bed ran 116 studs and poked out through the walls -- visible from outside, which
	-- fails the seal test. 92 ends it 4 studs inside the ring on both banks.
	solid({ Size = Vector3.new(92, 2, 12), Color = CHOC_D, Material = Enum.Material.Slate,
		CFrame = CFrame.new(centre + Vector3.new(0, 0.4, -16)) })
	deco({ Size = Vector3.new(92, 0.6, 11), Color = CHOC, Material = Enum.Material.Glass,
		Transparency = 0.08, Reflectance = 0.06 }, CFrame.new(centre + Vector3.new(0, 1.9, -16)))
	local fpart = deco({ Size = Vector3.new(1, 1, 1), Transparency = 1 },
		CFrame.lookAt(centre + Vector3.new(-44, 2.6, -16), centre + Vector3.new(44, 2.6, -16)))
	local flow = Instance.new("ParticleEmitter")
	flow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	flow.Color = ColorSequence.new(Color3.fromRGB(150, 96, 48), CHOC)
	flow.Size = NumberSequence.new(0.35)
	flow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	flow.Lifetime = NumberRange.new(2.6, 3.4)
	flow.Rate = 12
	flow.Speed = NumberRange.new(22, 28)
	flow.SpreadAngle = Vector2.new(3, 3)
	flow.EmissionDirection = Enum.NormalId.Front
	flow.Squash = NumberSequence.new(1.6)
	flow.Parent = fpart
	deco({ Size = Vector3.new(0.8, 16, 6), Color = CHOC, Material = Enum.Material.Glass,
		Transparency = 0.1, Reflectance = 0.05 }, CFrame.new(centre + Vector3.new(44, 10, -16)))
	local watt = Instance.new("Attachment")
	watt.WorldPosition = centre + Vector3.new(43, 2.5, -16); watt.Parent = Workspace.Terrain
	local splash = Instance.new("ParticleEmitter")
	splash.Texture = "rbxasset://textures/particles/smoke_main.dds"
	splash.Color = ColorSequence.new(Color3.fromRGB(150, 100, 56), CHOC)
	splash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.5) })
	splash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	splash.Lifetime = NumberRange.new(0.8, 1.4)
	splash.Rate = 10
	splash.Speed = NumberRange.new(2, 5)
	splash.SpreadAngle = Vector2.new(60, 60)
	splash.Parent = watt
	-- the bridge
	solid({ Size = Vector3.new(7, 1.2, 7), Color = CREAM, Material = Enum.Material.Glass, Transparency = 0.05,
		CFrame = CFrame.new(centre + Vector3.new(0, 2.4, -10)) * CFrame.Angles(math.rad(-16), 0, 0) })
	solid({ Size = Vector3.new(7, 1.2, 6), Color = CREAM, Material = Enum.Material.Glass, Transparency = 0.05,
		CFrame = CFrame.new(centre + Vector3.new(0, 3.6, -16)) })
	solid({ Size = Vector3.new(7, 1.2, 7), Color = CREAM, Material = Enum.Material.Glass, Transparency = 0.05,
		CFrame = CFrame.new(centre + Vector3.new(0, 2.4, -22)) * CFrame.Angles(math.rad(16), 0, 0) })

	-- ==================== CANDY CANES: CLUSTERED, NOT ARRAYED ====================
	-- v3 stood four identical straight pillars at even angles -- the single most generated-
	-- looking thing in the room. Now they grow in clumps of 2-4 with a bare gap between clumps,
	-- and every cane rolls its own height (12-34), lean (2-15 deg), thickness and facing. The
	-- segments overlap 0.3 along the lean so a tilted cane shows no hairline rings.
	local function candyCane(base, h, thick, tiltDeg, yaw)
		local up = CFrame.new(base) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(tiltDeg), 0, 0)
		local segH = 2.6
		for seg = 0, math.floor(h / segH) - 1 do
			deco({ Size = Vector3.new(thick, segH + 0.3, thick),
				Color = (seg % 2 == 0) and RED_C or CREAM, Material = Enum.Material.Glass,
				Transparency = 0.04 }, up * CFrame.new(0, seg * segH + segH * 0.5, 0))
		end
	end
	for _, spot in ipairs({ Vector3.new(-30, 0, 16), Vector3.new(26, 0, 26), Vector3.new(34, 0, -2) }) do
		for _ = 1, rng:NextInteger(2, 4) do
			candyCane(centre + spot + Vector3.new(rng:NextNumber(-5, 5), 1.8, rng:NextNumber(-5, 5)),
				rng:NextNumber(12, 34), rng:NextNumber(1.8, 3.4),
				rng:NextNumber(2, 15), rng:NextNumber(0, math.pi * 2))
		end
	end
	candyCane(centre + Vector3.new(-38, 1.8, -30), rng:NextNumber(14, 22), 2.2, 14, rng:NextNumber(0, 6))   -- one loner, leaning hard

	-- ==================== FLORA: MUSHROOMS + GUMDROPS, SIZES ALL OVER ====================
	for _, spot in ipairs({ Vector3.new(-26, 0, 6), Vector3.new(22, 0, 20), Vector3.new(-14, 0, -32) }) do
		for _ = 1, 3 do
			local scale = 0.6 + rng:NextNumber(0, 1.2)          -- 0.6x to 1.8x: no two alike
			local h = (3 + rng:NextNumber(0, 4)) * scale
			local at = centre + spot + Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5))
			deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 1.2 * scale, 1.2 * scale), Color = CREAM,
				Material = Enum.Material.SmoothPlastic },
				CFrame.new(at + Vector3.new(0, 2 + h * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)))
			local capCol = CANDY_COLORS[rng:NextInteger(1, #CANDY_COLORS)]
			local cap = deco({ Shape = Enum.PartType.Ball, Size = Vector3.new(4.4, 2.2, 4.4) * scale,
				Color = capCol, Material = Enum.Material.Glass, Transparency = 0.1 },
				CFrame.new(at + Vector3.new(0, 2.3 + h, 0)))
			-- one in three glows, faintly, warm -- the rest sit dark. See LIGHT DISCIPLINE.
			if rng:NextNumber() < 0.34 then
				local pl = Instance.new("PointLight"); pl.Color = WARM; pl.Brightness = 0.35; pl.Range = 8
				pl.Parent = cap
			end
		end
	end
	for _ = 1, 8 do   -- gumdrops: squashed glassy blobs, field side only
		local a, r = rng:NextNumber(math.rad(-10), math.rad(190)), rng:NextNumber(10, 38)
		local gs = 1 + rng:NextNumber(0, 2.6)
		deco({ Shape = Enum.PartType.Ball, Size = Vector3.new(gs, gs * 0.7, gs),
			Color = CANDY_COLORS[rng:NextInteger(1, #CANDY_COLORS)], Material = Enum.Material.Glass,
			Transparency = 0.22 },
			CFrame.new(centre + Vector3.new(math.cos(a) * r, 2 + gs * 0.35, math.sin(a) * r)))
	end

	-- ==================== FLOOR CLUTTER: WHERE FLOOR MEETS WALL ====================
	-- broken candy shards, spilled sprinkles, rubble at the wall bases. Clean floors are the
	-- other half of the generated look; real spaces are messy at their edges.
	for _ = 1, 10 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = 40 + rng:NextNumber(0, 6)
		deco({ Size = Vector3.new(rng:NextNumber(0.6, 1.6), rng:NextNumber(0.3, 0.7), rng:NextNumber(0.6, 1.8)),
			Color = CANDY_COLORS[rng:NextInteger(1, #CANDY_COLORS)], Material = Enum.Material.Glass,
			Transparency = 0.15 },
			CFrame.new(centre + Vector3.new(math.cos(a) * r, 2.3, math.sin(a) * r))
				* CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), rng:NextNumber(0, 1)))
	end
	for _ = 1, 26 do   -- sprinkles: tiny bright sticks, scattered thickest near the pools
		local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(4, 42)
		local at = centre + Vector3.new(math.cos(a) * r, 2.15, math.sin(a) * r)
		if at.Z > centre.Z - 9 then
			deco({ Size = Vector3.new(0.18, 0.18, 0.8),
				Color = CANDY_COLORS[rng:NextInteger(1, #CANDY_COLORS)],
				Material = Enum.Material.SmoothPlastic },
				CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 6), 0))
		end
	end
	for _ = 1, 6 do    -- dropped wrappers: the one legitimate use of Foil in this room
		local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(14, 40)
		deco({ Size = Vector3.new(1.5, 0.08, 1.9),
			Color = rng:NextNumber() < 0.5 and Color3.fromRGB(214, 216, 222) or Color3.fromRGB(240, 160, 190),
			Material = Enum.Material.Foil },
			CFrame.new(centre + Vector3.new(math.cos(a) * r, 2.12, math.sin(a) * r))
				* CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), rng:NextNumber(0, 6), math.rad(rng:NextNumber(-8, 8))))
	end
	for _ = 1, 12 do   -- rubble against the wall bases
		local a = rng:NextNumber(0, math.pi * 2)
		solid({ Size = Vector3.new(rng:NextNumber(1.5, 4), rng:NextNumber(1, 3), rng:NextNumber(1.5, 4)),
			Color = rockCol(), Material = rockMat(),
			CFrame = CFrame.new(centre + Vector3.new(math.cos(a) * (42 + rng:NextNumber(0, 4)), 2.8, math.sin(a) * (42 + rng:NextNumber(0, 4))))
				* CFrame.Angles(rng:NextNumber(0, 0.5), rng:NextNumber(0, 6), rng:NextNumber(0, 0.5)) })
	end

	-- ==================== LIGHT + AIR ====================
	-- crystals: SIX, pink only, three lit -- down from eight lit in as many colours
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2 + 0.4
		local c = deco({ Size = Vector3.new(1.6, 3.6 + rng:NextNumber(0, 1.5), 1.6),
			Color = Color3.fromRGB(255, 150, 190), Material = Enum.Material.Neon,
			Transparency = 0.15 + rng:NextNumber(0, 0.25) },
			CFrame.new(centre + Vector3.new(math.cos(a) * 22, 30, math.sin(a) * 22))
				* CFrame.Angles(math.rad(rng:NextNumber(-30, 30)), 0, math.rad(rng:NextNumber(-30, 30))))
		if i % 2 == 0 then
			local pl = Instance.new("PointLight"); pl.Color = PINK_L
			pl.Brightness = 0.5 + rng:NextNumber(0, 0.4); pl.Range = 12 + rng:NextNumber(0, 8); pl.Parent = c
		end
	end
	-- sugar pools: only two still glow; the rest are wet glass catching the chandelier
	for n = 1, 8 do
		local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(5, 26)
		local pos = centre + Vector3.new(math.cos(a) * r, 2.1, math.sin(a) * r)
		if pos.Z > centre.Z - 9 then
			local w = 3 + rng:NextNumber(0, 5)
			local glow = n <= 2
			deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, w, w),
				Color = glow and PINK_L or CANDY_COLORS[rng:NextInteger(1, #CANDY_COLORS)],
				Material = glow and Enum.Material.Neon or Enum.Material.Glass,
				Transparency = glow and 0.5 or 0.25, Reflectance = glow and 0 or 0.08 },
				CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)))
		end
	end
	-- depth haze: dark films floating just off the far walls. The poor man's Atmosphere, and
	-- the reason the room's edges recede instead of presenting themselves
	for _, deg in ipairs({ 150, 205, 250, 320 }) do
		local a = math.rad(deg)
		deco({ Size = Vector3.new(34, 30, 0.4), Color = Color3.fromRGB(14, 9, 5),
			Material = Enum.Material.SmoothPlastic, Transparency = 0.72 },
			CFrame.new(centre + Vector3.new(math.cos(a) * 39, 16, math.sin(a) * 39))
				* CFrame.Angles(0, -a + math.rad(90), 0))
	end

	-- ==================== THE CHANDELIER ====================
	local chand = Instance.new("Model"); chand.Name = "Chandelier"
	local hub = mk({ Size = Vector3.new(2.5, 2.5, 2.5), Color = GOLD, Material = Enum.Material.Metal })
	hub.CFrame = CFrame.new(centre + Vector3.new(0, 27, 0)); hub.Parent = chand
	local chain = mk({ Size = Vector3.new(0.4, 19, 0.4), Color = Color3.fromRGB(80, 82, 90), Material = Enum.Material.Metal })
	chain.CFrame = CFrame.new(centre + Vector3.new(0, 37, 0)); chain.Parent = chand
	for i = 1, 7 do
		local a = (i / 7) * math.pi * 2
		local shard = mk({ Size = Vector3.new(1.1 + rng:NextNumber(0, 0.5), 4 + rng:NextNumber(0, 3), 1.1),
			Color = Color3.fromRGB(255, 190, 205), Material = Enum.Material.Glass, Transparency = 0.12 })
		shard.CFrame = CFrame.new(centre + Vector3.new(math.cos(a) * 3.4, 24.6, math.sin(a) * 3.4))
			* CFrame.Angles(math.rad(10 + rng:NextNumber(0, 10)), -a, 0)
		shard.Parent = chand
	end
	local cl = Instance.new("PointLight"); cl.Color = WARM; cl.Brightness = 1.5; cl.Range = 42; cl.Parent = hub
	chand.WorldPivot = CFrame.new(centre + Vector3.new(0, 27, 0))
	chand.Parent = caveFolder
	task.spawn(function()
		local t0 = os.clock()
		while chand.Parent do
			chand:PivotTo(CFrame.new(centre + Vector3.new(0, 27, 0)) * CFrame.Angles(0, (os.clock() - t0) * 0.3, 0))
			task.wait(0.06)
		end
	end)

	-- dust motes, dimmed to match the darker room
	local matt = Instance.new("Attachment"); matt.WorldPosition = centre + Vector3.new(0, 14, 0); matt.Parent = Workspace.Terrain
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(WARM, Color3.fromRGB(255, 255, 255))
	motes.Size = NumberSequence.new(0.22)
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	motes.Lifetime = NumberRange.new(3, 5)
	motes.Rate = 7
	motes.Speed = NumberRange.new(0.5, 1.5)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.LightEmission = 1
	motes.Parent = matt
	caveFolder.AncestryChanged:Connect(function(_, parent)
		if not parent then matt:Destroy(); watt:Destroy() end
	end)

	-- ==================== THE TREASURE ====================
	for i = 1, 5 do
		local a = math.rad(20 + i * 30 + rng:NextNumber(-8, 8))
		placeCandy(centre + Vector3.new(math.cos(a) * (16 + rng:NextNumber(0, 10)), 2.6,
			math.sin(a) * (14 + rng:NextNumber(0, 8))), false)
	end
	placeCandy(centre + Vector3.new(-16, 2.6, -34), false)
	placeCandy(centre + Vector3.new(16, 2.6, -34), false)
	placeCandy(centre + Vector3.new(0, 2.6, -42), false)
	local altarAt = centre + Vector3.new(0, 0, -36)
	for tier, spec in ipairs({ { w = 12, y = 2.8 }, { w = 8.5, y = 4.4 }, { w = 5.5, y = 6 } }) do
		solid({ Size = Vector3.new(spec.w, 1.6, spec.w),
			Color = (tier == 3) and Color3.fromRGB(112, 84, 52) or rockCol(), Material = Enum.Material.Slate,
			CFrame = CFrame.new(altarAt + Vector3.new(0, spec.y, 0)) })
	end
	deco({ Size = Vector3.new(6.2, 0.7, 6.2), Color = GOLD, Material = Enum.Material.Metal },
		CFrame.new(altarAt + Vector3.new(0, 7, 0)))
	for _, cx in ipairs({ -5, 5 }) do
		for _, cz in ipairs({ -5, 5 }) do
			deco({ Size = Vector3.new(0.7, 4.5, 0.7), Color = Color3.fromRGB(70, 58, 30) },
				CFrame.new(altarAt + Vector3.new(cx, 4.2, cz)))
			local flame = deco({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 1.3, 0.9),
				Color = Color3.fromRGB(255, 196, 96), Material = Enum.Material.Neon },
				CFrame.new(altarAt + Vector3.new(cx, 7, cz)))
			local fl = Instance.new("PointLight"); fl.Color = WARM
			fl.Brightness = 0.7 + rng:NextNumber(0, 0.4); fl.Range = 9; fl.Parent = flame
		end
	end
	deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(26, 3.4, 3.4), Color = GOLD,
		Material = Enum.Material.Neon, Transparency = 0.84 },
		CFrame.new(altarAt + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.rad(90)))
	placeCandy(altarAt + Vector3.new(0, 8.2, 0), true)
end

local CoinEvent
local function grab(c)
	if c.taken then return end
	c.taken = true
	grabbed += 1
	local worth = c.gold and GOLD_COINS or math.random(CANDY_COINS[1], CANDY_COINS[2])
	totalWorth += worth
	-- pop: the candy flies up, shrinks and is gone
	TweenService:Create(c.part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = c.part.CFrame + Vector3.new(0, 5, 0),
		Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 }):Play()
	Debris:AddItem(c.part, 0.45)
	if CoinEvent then pcall(function() CoinEvent:FireServer(worth) end) end
	pcall(function() _G.showFloatingText(("+%d \u{1F36C}"):format(worth), c.gold and GOLD or c.part.Color) end)
end

local function exitCave(reason)
	if not inCave then return end
	inCave = false
	fade(true, 0.3)
	task.wait(0.35)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and returnCF then hrp.CFrame = returnCF end
	if caveFolder then caveFolder:Destroy(); caveFolder = nil end
	if timerGui then timerGui.Enabled = false end
	fade(false, 0.4)
	pcall(function() _G.NotifyCenter.push({
		text = ("\u{1F573} %s -- %d candies, +%d coins!"):format(reason, grabbed, totalWorth),
		color = GOLD }) end)
end

local function enterCave()
	if inCave then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	inCave = true
	caveDeadline = os.clock() + CAVE_TIME + 0.7   -- set BEFORE any yield; the fade eats the 0.7

	-- return to the hole's EDGE, not your exact fall spot: coming back onto the disc itself would
	-- drop you straight back in, forever
	local edge = holePos and (holePos + Vector3.new(HOLE_RADIUS + 6, 4, 0)) or hrp.Position
	returnCF = CFrame.new(edge)

	-- per-player offset, TunnelBlast's trick: other CHARACTERS replicate even though the cave
	-- does not, so a shared void means watching a stranger float through your treasure room
	local centre = Vector3.new((player.UserId % 23) * 97, caveFloorY(), (player.UserId % 17) * 61)

	fade(true, 0.3)
	task.wait(0.32)
	buildCave(centre)
	buildTimer()
	hrp.CFrame = caveSpawn or CFrame.new(centre + Vector3.new(0, 4, 0))
	thud(centre, 0.9)                    -- you LANDED somewhere deep; the pitch says how deep
	timerGui.Enabled = true
	caveDeadline = os.clock() + CAVE_TIME   -- re-set now the fade is paid for: you get the full window
	fade(false, 0.4)
end

--======================================================================
-- THE WATCH
--======================================================================
RunService.Heartbeat:Connect(function()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if inCave then
		-- enterCave marks inCave BEFORE its fade finishes; this loop must not read the deadline
		-- until it exists. (The first version did, and errored every frame of the fade.)
		if not caveDeadline then return end
		local left = caveDeadline - os.clock()
		if timerLabel then
			timerLabel.Text = ("\u{1F573} CAVE SEALING IN %ds  --  %d/%d candies")
				:format(math.max(0, math.ceil(left)), grabbed, CANDY_COUNT + 1)
		end
		for _, c in ipairs(candies) do
			if not c.taken and (c.part.Position - hrp.Position).Magnitude < 5 then grab(c) end
		end
		if grabbed >= CANDY_COUNT + 1 then
			task.wait(1.2)                                 -- let the last +coins land on screen
			exitCave("Cleaned out the cave!")
		elseif left <= 0 then
			exitCave("The cave sealed")
		end
		return
	end

	if holePos then
		local d = hrp.Position - holePos
		if math.abs(d.Y) < 8 and Vector3.new(d.X, 0, d.Z).Magnitude < HOLE_RADIUS then
			enterCave()
		end
	end
end)

-- dying mid-cave respawns you on the surface: the cave state has to be let go of, or the next
-- sinkhole finds `inCave` still true and refuses to drop you
player.CharacterAdded:Connect(function()
	if inCave then
		inCave = false
		if caveFolder then caveFolder:Destroy(); caveFolder = nil end
		if timerGui then timerGui.Enabled = false end
	end
end)

--======================================================================
-- THE WIRE
--======================================================================
task.spawn(function()
	CoinEvent = ReplicatedStorage:FindFirstChild("CoinEvent") or ReplicatedStorage:WaitForChild("CoinEvent", 10)
	local ev = ReplicatedStorage:FindFirstChild("SinkholeSync")
		or ReplicatedStorage:WaitForChild("SinkholeSync", 30)
	if not ev then
		print("[Sinkhole] no SinkholeSync -- is BigEvents.server.lua synced into ServerScriptService?")
		return
	end
	ev.OnClientEvent:Connect(function(kind, payload)
		if kind == "start" and typeof(payload) == "table" and typeof(payload.pos) == "Vector3" then
			clearHole()
			holeModel, holeAtt = buildHole(payload.pos)
			holePos = payload.pos
			thud(payload.pos, 1)          -- the floor giving way is the loudest thing this event does
		elseif kind == "stop" then
			clearHole()
			if inCave then exitCave("The cave sealed") end
		end
	end)
	print("[Sinkhole] client ready -- hole visual, fall watch, private candy cave, CoinEvent payouts")
end)

--======================================================================
-- /sinkhole  --  local rehearsal
--======================================================================
-- Opens a hole 20 studs in front of you for 45s, on your screen only -- the same reason /reveal
-- and /sugarblizzard exist: the real event is on a 600s rotation, which is the wrong pacing for
-- tuning a cave layout. Cannot broadcast, so it cannot open holes on a live server.
do
	local function onCmd(msg)
		local m = tostring(msg or ""):lower():gsub("^%s+", "")
		if m:sub(1, 9) ~= "/sinkhole" then return end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		clearHole()
		local pos = hrp.Position + hrp.CFrame.LookVector * 20 - Vector3.new(0, 2.5, 0)
		holeModel, holeAtt = buildHole(pos)
		holePos = pos
		print("[Sinkhole] /sinkhole -- local hole for 45s, walk onto it")
		task.delay(45, function()
			clearHole()
			if inCave then exitCave("The cave sealed") end
		end)
	end
	pcall(function()
		TextChatService.MessageReceived:Connect(function(m)
			if m.TextSource and m.TextSource.UserId == player.UserId then onCmd(m.Text) end
		end)
	end)
	pcall(function() player.Chatted:Connect(onCmd) end)
end
