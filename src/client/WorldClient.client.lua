print("WORLDCLIENT STARTED")
repeat task.wait() until _G.CoreClientReady

local Players = game.Players
local player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local IslandUnlockEvent = game:GetService("ReplicatedStorage"):FindFirstChild("IslandUnlockEvent")

local currentKnownIsland = 0
local playerBillboards = {}

local function makeBillboard(parent, text, textColor, textSize)
	local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,120,0,30); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=false; bb.Parent=parent
	local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=textSize or 13; lbl.TextColor3=textColor or Color3.new(1,1,1); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent=lbl
	return bb, lbl
end

-- BUBBLE DRIFT: gently wander an anchored bubble (gas pocket / coin sphere) within a BOX zone around its
-- spawn point so the player has to go off-course to catch it. SLOW (catchable) + changes direction
-- periodically (organic). Anchored + moved by code only -> never touches flight physics. The collection
-- loops read the part's CURRENT .Position, so it still collects at the moving spot (rising or falling).
--   homePos = the spawn point (zone centre);  HR = horizontal half-extent;  VR = vertical half-extent.
local getStandPosition -- forward-declared (assigned below) so the drift can derive a bubble's island gap
local function startBubbleDrift(part, homePos, HR, VR)
	task.spawn(function()
		local rng = Random.new()
		local SPEED = 15 -- studs/sec (was 12, originally 5): livelier wandering so pickups clearly read as
		                 -- moving targets worth chasing, still well under flight speed so they stay catchable
		local function randDir()
			local d = Vector3.new(rng:NextNumber()-0.5, (rng:NextNumber()-0.5)*0.7, rng:NextNumber()-0.5)
			return (d.Magnitude > 0) and d.Unit or Vector3.new(1,0,0)
		end
		local vel = randDir()
		local retime = 0
		local last = os.clock()
		-- THIS bubble's island GAP, from its home Y, so the enlarged vertical band can't spill into the next
		-- island. Gap airspace = [lowerStand+120, upperStand-200] (same margins the spawner used). If the gap
		-- is shorter than the requested +/-VR, the gap wins (vertical is clamped; horizontal still gets full HR).
		local yMin, yMax = homePos.Y - VR, homePos.Y + VR
		pcall(function()
			local belowY, aboveY = -math.huge, math.huge
			for i = 1, 14 do
				local sy = getStandPosition(i).Y
				if sy <= homePos.Y and sy > belowY then belowY = sy end
				if sy >= homePos.Y and sy < aboveY then aboveY = sy end
			end
			if belowY > -math.huge then yMin = math.max(yMin, belowY + 120) end
			if aboveY <  math.huge then yMax = math.min(yMax, aboveY - 200) end
		end)
		if yMin > yMax then yMin, yMax = homePos.Y, homePos.Y end -- degenerate-gap guard
		while part.Parent do
			-- COIN MAGNET HAND-OFF. While the magnet has hold of this pickup it owns the Position, and this
			-- loop must not write it -- two loops setting .CFrame on the same frame produce a jitter that
			-- looks exactly like lag. The magnet sets the attribute when it grabs and clears it if the player
			-- flies out of range, at which point the drift picks up from wherever the part now is.
			--
			-- `last` is reset on the way out so the first frame after a hand-back uses a real dt instead of
			-- the whole duration of the pull, which would teleport the bubble across its box.
			if part:GetAttribute("Magnetized") then
				last = os.clock()
				task.wait()
				continue
			end
			local now = os.clock(); local dt = math.min(now - last, 0.2); last = now
			retime = retime - dt
			if retime <= 0 then -- re-aim OFTEN with a SHARP turn -> erratic, darting, hard to predict
				vel = (vel * 0.25 + randDir()) -- new random heading dominates -> abrupt direction changes (not smooth)
				vel = (vel.Magnitude > 0) and vel.Unit or randDir()
				retime = 0.35 + rng:NextNumber() * 0.95 -- new heading every ~0.35-1.3s (was 2-4.5s)
			end
			local np = part.Position + vel * SPEED * dt
			-- clamp X/Z to the +/-HR box around home, and Y to this gap's [yMin,yMax]; bounce velocity inward at edges
			local cx = math.clamp(np.X, homePos.X - HR, homePos.X + HR)
			local cy = math.clamp(np.Y, yMin, yMax)
			local cz = math.clamp(np.Z, homePos.Z - HR, homePos.Z + HR)
			if cx ~= np.X then vel = Vector3.new(-vel.X, vel.Y, vel.Z) end
			if cy ~= np.Y then vel = Vector3.new(vel.X, -vel.Y, vel.Z) end -- gap floor/ceiling bounce
			if cz ~= np.Z then vel = Vector3.new(vel.X, vel.Y, -vel.Z) end
			pcall(function() part.CFrame = CFrame.new(cx, cy, cz) end)
			task.wait() -- per-FRAME update: smooth at the higher speed so the per-frame collection loop always matches the bubble's current position
		end
	end)
end

local function spawnRing(pos, color, dataIndex, dirVec)
	-- COIN-BOOST BUBBLE: now a SPHERE (was a flat ring/cylinder) that slowly drifts. Keeps its coin COLOR
	-- + "+BONUS" label + reward. dirVec is kept in the entry only so the existing respawn signature/logic
	-- is unchanged (orientation no longer matters for a ball).
	local ring=Instance.new("Part"); ring.Shape=Enum.PartType.Ball; ring.Size=Vector3.new(24,24,24)
	ring.Material=Enum.Material.Neon; ring.Color=color; ring.CanCollide=false; ring.Anchored=true; ring.Transparency=0.2; ring.CastShadow=false; ring.Position=pos; ring.Parent=workspace
	makeBillboard(ring,"\xF0\x9F\x92\xB0 +BONUS",Color3.new(1,1,1),14)
	local entry={part=ring,pos=pos,color=color,idx=dataIndex,dir=dirVec}
	table.insert(_G.activeRings,entry)
	startBubbleDrift(ring, pos, 180, 280) -- ~4x bigger wander zone (was 45/70); Y clamped to the island gap inside startBubbleDrift
end
_G.spawnRing=spawnRing

local function findIsland(num)
	for _,obj in ipairs(workspace:GetChildren()) do
		if obj.Name:match("^Island_"..num.."_") then return obj end
	end
	return nil
end

local function findStandOnIsland(islandNum)
	local island = findIsland(islandNum)
	if not island then return nil end
	for _, obj in ipairs(island:GetDescendants()) do
		if obj.Name == "Stand_"..islandNum or obj.Name:match("^Stand") then
			if obj:IsA("Model") then
				local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
				if part then return part end
			end
		end
	end
	return island.PrimaryPart or island:FindFirstChildWhichIsA("BasePart")
end

-- spawnLandingPad REMOVED: these were the "Land Here First!" target markers for
-- the (now removed) perfect-landing reward. With the reward gone there is nothing
-- to aim for, so the markers are no longer spawned. _G.landingPads stays an empty
-- table; nothing reads it anymore.

local function startGasPocketPulse(part)
	local function doPulse()
		if not part.Parent then return end
		local t1=TweenService:Create(part,TweenInfo.new(1,Enum.EasingStyle.Sine),{Size=Vector3.new(17,17,17)}); t1:Play()
		t1.Completed:Connect(function()
			if not part.Parent then return end
			local t2=TweenService:Create(part,TweenInfo.new(1,Enum.EasingStyle.Sine),{Size=Vector3.new(13,13,13)}); t2:Play()
			t2.Completed:Connect(function() doPulse() end)
		end)
	end
	doPulse()
end

local function spawnGasPocket(pos)
	local p=Instance.new("Part"); p.Shape=Enum.PartType.Ball; p.Size=Vector3.new(20,20,20)
	p.Material=Enum.Material.Neon; p.Color=Color3.fromRGB(0,255,100); p.Transparency=0.4; p.CanCollide=false; p.Anchored=true; p.CastShadow=false; p.Position=pos; p.Parent=workspace
	local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,80,0,30); bb.StudsOffset=Vector3.new(0,12,0); bb.AlwaysOnTop=false; bb.Parent=p
	local bl=Instance.new("TextLabel"); bl.Size=UDim2.new(1,0,1,0); bl.BackgroundTransparency=1; bl.Font=Enum.Font.GothamBold; bl.TextSize=16; bl.TextColor3=Color3.fromRGB(0,255,100); bl.Text="\xF0\x9F\x92\xA8 GAS!"; bl.Parent=bb; Instance.new("UIStroke").Parent=bl
	table.insert(_G.activeGasPockets,p); startGasPocketPulse(p)
	startBubbleDrift(p, pos, 180, 280) -- ~4x bigger wander zone (was 45/70); Y clamped to the island gap inside startBubbleDrift
end
_G.spawnGasPocket=spawnGasPocket

-- popGasPocket(part): PURELY VISUAL pop when the player touches a fart/gas bubble.
-- A quick expand + fade, a green particle burst, and a pop sound, then it's destroyed.
-- Gives NO gas/power and NO coins -- the caller (CoreClient) handles only this visual.
local function popGasPocket(part)
	if not part or not part.Parent then return end
	-- hide the "GAS!" label immediately so only the pop shows
	local bb = part:FindFirstChildOfClass("BillboardGui"); if bb then bb.Enabled = false end
	-- green sparkle burst (matches the bubble colour)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(0,255,100))
	emitter.Lifetime = NumberRange.new(0.3,0.6)
	emitter.Speed = NumberRange.new(12,22)
	emitter.SpreadAngle = Vector2.new(180,180)
	emitter.Size = NumberSequence.new(1.3)
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(26)
	-- pop sound (PLACEHOLDER id -- swap to your preferred bubble-pop sfx)
	local s = Instance.new("Sound"); s.SoundId = "rbxassetid://9114402399"; s.Volume = 0.5; s.Parent = part; s:Play()
	-- quick expand + fade, then destroy
	local t = TweenService:Create(part, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(30,30,30), Transparency = 1 })
	t:Play()
	t.Completed:Connect(function() if part.Parent then part:Destroy() end end)
	game:GetService("Debris"):AddItem(part, 1.2)  -- backup cleanup
end
_G.popGasPocket = popGasPocket

-- PERFECT/FIRST-LANDING SYSTEM REMOVED: the perfect-landing reward, its
-- "First Landing!" popup/flash/pad-hide effect, and the target pad markers are
-- all gone. There is no longer any bonus or notification for landing precisely
-- on a stand. Normal landing (power refill from the stand, flight counting) is
-- unaffected — it lives entirely in CoreClient's onLand and is untouched.
-- (Previously: islandsLanded guard + showPerfectLanding(pad) + _G.showPerfectLanding.)

getStandPosition = function(islandNum) -- (forward-declared above for startBubbleDrift)
	local standPart = findStandOnIsland(islandNum)
	if standPart then return standPart.Position + Vector3.new(0, 25, 0) end
	local p = _G.ISLAND_POS[islandNum]
	return Vector3.new(p.x, p.y+20, p.z)
end

-- ============================================================================================
-- BlackHole: visual landmark + SPACE REALM TELEPORT (wired at the bottom of buildBlackHole). A low-poly
-- black hole high above Pizza Palms (Island 14). The look NEVER collides/affects gas/coins/flight; it only
-- looks cool + spins. An invisible touch sphere detects the player touching it and fires the SERVER, which
-- teleports them to the Space Realm place (tester-locked for now). Built HERE in WorldClient (which is
-- already mapped + reliably runs and already knows
-- island positions) instead of a standalone file -- the standalone BlackHole LocalScript was never
-- synced by Rojo, so it never ran. This placement is guaranteed to execute.
-- ============================================================================================
local BH_HEIGHT_OFFSET = 1500   -- studs ABOVE Pizza Palms (-> ~Y 25500); height UNCHANGED, only bigger
local BH_TILT_DEG      = 25     -- accretion disk tilt from horizontal -> seen as an ELLIPSE (Interstellar look), NOT a flat bullseye
local BH_SCALE         = 4.5    -- MASSIVE: every length (core, disk radii, rim, segments, particle scale) x4.5
local BH_CORE_SIZE     = 40 * BH_SCALE  -- pure-black "hole" sphere diameter (40 -> 180)
local function bhInert(p)
	p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
	return p
end
local function buildBlackHole(center)
	local model = Instance.new("Model"); model.Name = "BlackHole"
	local coreCF = CFrame.new(center)
	-- The accretion plane is TILTED from horizontal so the rings read as an ELLIPSE at an angle
	-- (Interstellar look) instead of a flat target facing the player.
	local planeCF = coreCF * CFrame.Angles(math.rad(BH_TILT_DEG), 0, 0)

	-- 1) CORE: pure-black opaque sphere -- the "void".
	local core = Instance.new("Part"); core.Name = "Core"; core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(BH_CORE_SIZE, BH_CORE_SIZE, BH_CORE_SIZE)
	core.Color = Color3.fromRGB(0, 0, 0); core.Material = Enum.Material.SmoothPlastic; core.Transparency = 0
	core.CFrame = coreCF; bhInert(core); core.Parent = model
	-- subtle purple light so the black void pops against dark space.
	local light = Instance.new("PointLight"); light.Color = Color3.fromRGB(150, 70, 230); light.Brightness = 5; light.Range = 60; light.Parent = core

	-- A segmented ring is a REAL ANNULUS (the core shows through the hole). Segments orbit in the tilted
	-- plane, so each ring both LOOKS like a ring and visibly SPINS. Seg Size = (radialWidth, thickness, arcLen);
	-- arcLen ~= the gap between segments (x1.15) so the band reads continuous. spin = radians/sec.
	local rings = {}
	local function segRing(name, count, radius, radialW, thickness, color, spinSpeed)
		local arcLen = (2 * math.pi * radius / count) * 1.15
		local segs = {}
		for i = 1, count do
			local s = Instance.new("Part"); s.Name = name .. "_Seg" .. i
			s.Size = Vector3.new(radialW, thickness, arcLen)
			s.Color = color; s.Material = Enum.Material.Neon; s.Transparency = 0.05
			bhInert(s); s.Parent = model
			segs[i] = { part = s, baseAngle = (i - 1) * (2 * math.pi / count) }
		end
		table.insert(rings, { segs = segs, radius = radius, spin = spinSpeed })
	end

	-- 3) PHOTON RIM: a thin BRIGHT ring hugging the core's edge -> a glowing outline so the void pops.
	segRing("PhotonRim", 32, BH_CORE_SIZE * 0.62, 3 * BH_SCALE, 3 * BH_SCALE, Color3.fromRGB(235, 200, 255), 0.8)
	-- 2) ACCRETION DISK: 3 concentric annulus rings, HOT white-purple inner -> deep purple/blue outer
	-- (outer Ø ~720 after the x4.5). Differential rotation (inner faster) like a real accretion disk. Core shows through.
	segRing("DiskHot",  30, 34 * BH_SCALE, 13 * BH_SCALE, 3.0 * BH_SCALE, Color3.fromRGB(230, 180, 255), 2.0)  -- hot inner, fastest (~3.1s/rev)
	segRing("DiskMid",  40, 56 * BH_SCALE, 16 * BH_SCALE, 3.0 * BH_SCALE, Color3.fromRGB(160, 90, 230), 1.75)
	segRing("DiskCool", 50, 80 * BH_SCALE, 18 * BH_SCALE, 2.5 * BH_SCALE, Color3.fromRGB(90, 50, 180), 1.5)    -- cool outer, slowest (~4.2s/rev)

	-- 4) DENSE INWARD PARTICLES: a ring of emitters just outside the disk, each pulling particles HARD
	-- toward the core -> a dramatic "sucked in" stream (8 emitters x rate 16 = ~128/s).
	local EMITTERS, emitRadius = 8, 92 * BH_SCALE  -- spawn from the now-larger disk edge (~414)
	for i = 1, EMITTERS do
		local ang = (i - 1) * (2 * math.pi / EMITTERS)
		local fromPos = (planeCF * CFrame.new(math.cos(ang) * emitRadius, 0, math.sin(ang) * emitRadius)).Position
		local host = Instance.new("Part"); host.Name = "Emitter" .. i; host.Size = Vector3.new(1, 1, 1); host.Transparency = 1
		bhInert(host); host.CFrame = CFrame.new(fromPos); host.Parent = model
		local em = Instance.new("ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		em.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(170, 110, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 120, 255)) })
		em.Lifetime = NumberRange.new(1.3, 1.8); em.Rate = 36; em.Speed = NumberRange.new(8 * BH_SCALE, 16 * BH_SCALE); em.SpreadAngle = Vector2.new(14, 14)
		em.Acceleration = (center - fromPos).Unit * (80 * BH_SCALE) -- STRONG pull toward the core (scaled with the bigger distance)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2 * BH_SCALE), NumberSequenceKeypoint.new(1, 0.1 * BH_SCALE) })
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.85, 0.4), NumberSequenceKeypoint.new(1, 1) })
		em.LightEmission = 0.9; em.Parent = host
	end

	model.Parent = workspace

	-- DRAMATIC ANIMATION: spin each ring in its own tilted plane (differential -> inner faster, keeps the
	-- tilt), and pulse the Neon transparency + core light for a "living" energy feel.
	local pulseT = 0
	local angles = {}; for i = 1, #rings do angles[i] = 0 end
	RunService.Heartbeat:Connect(function(dt)
		if not model.Parent then return end
		pulseT = pulseT + dt
		local pulse = (math.sin(pulseT * 2.4) + 1) * 0.5 -- 0..1
		local segTrans = 0.05 + pulse * 0.18
		for ri, ring in ipairs(rings) do
			angles[ri] = angles[ri] + ring.spin * dt
			local sp = angles[ri]
			for _, s in ipairs(ring.segs) do
				local a = s.baseAngle + sp
				s.part.CFrame = planeCF
					* CFrame.new(math.cos(a) * ring.radius, 0, math.sin(a) * ring.radius)
					* CFrame.Angles(0, -a, 0)
				s.part.Transparency = segTrans
			end
		end
		light.Brightness = 4 + pulse * 4; light.Range = 45 + pulse * 15
	end)

	-- ============================================================================================
	-- SPACE REALM TELEPORT (now wired). Touching the orb fires an INTENT to the SERVER, which is the single
	-- authoritative gate: it checks the tester lock, tells us what to show, then teleports us itself (the
	-- client never decides who may teleport, and never teleports itself). The VISUAL above is untouched --
	-- this only adds an invisible touch sphere + a small on-screen message. All locals here are
	-- FUNCTION-SCOPED (no new module-scope locals). The tester lock + easy-open flag live on the SERVER
	-- (BlackHoleTeleport.server.lua, SPACE_REALM_TESTERS_ONLY).
	-- ============================================================================================
	-- invisible touch sphere matching the void (CanTouch=true). The visual Core stays CanCollide/CanTouch=false.
	local touchOrb = Instance.new("Part"); touchOrb.Name = "TeleportTouch"; touchOrb.Shape = Enum.PartType.Ball
	touchOrb.Size = Vector3.new(BH_CORE_SIZE, BH_CORE_SIZE, BH_CORE_SIZE); touchOrb.CFrame = coreCF
	touchOrb.Anchored = true; touchOrb.CanCollide = false; touchOrb.CanQuery = false; touchOrb.CanTouch = true
	touchOrb.Transparency = 1; touchOrb.CastShadow = false; touchOrb.Parent = model
	-- ...and THE RINGS COUNT TOO. Hitting the accretion disk used to do nothing -- you had to thread the
	-- black ball itself, which is a tiny target when you arrive at speed. This is one invisible DISC lying
	-- in the same tilted plane, out to the outer ring's edge, so touching ANY part of the rift teleports.
	-- One part beats touch-enabling the ~150 orbiting ring segments (each would need its own connection).
	local BH_DISK_R = (80 + 18 / 2) * BH_SCALE -- outer ring radius + half its radial width
	local touchDisk = Instance.new("Part"); touchDisk.Name = "TeleportTouchDisk"; touchDisk.Shape = Enum.PartType.Cylinder
	touchDisk.Size = Vector3.new(10 * BH_SCALE, BH_DISK_R * 2, BH_DISK_R * 2) -- (thickness, diameter, diameter)
	touchDisk.CFrame = planeCF * CFrame.Angles(0, 0, math.rad(90))            -- a Cylinder's round faces are on local X: rotate X->Y so it lies FLAT in the tilted plane
	touchDisk.Anchored = true; touchDisk.CanCollide = false; touchDisk.CanQuery = false; touchDisk.CanTouch = true
	touchDisk.Transparency = 1; touchDisk.CastShadow = false; touchDisk.Parent = model

	-- ===== STATUS MESSAGES ARE BANNERS NOW -- the mid-screen box is deleted =====
	-- This was a 540x72 label at y 0.42 in its own ScreenGui ("SpaceRealmMsg"), shown by flipping Visible
	-- and hidden by an unguarded task.delay that ALSO cleared the `traveling` debounce. Two failure modes
	-- fell out of that: an older timer could hide a newer message, and any error between the show and the
	-- hide left the box on screen for good (ResetOnSpawn = false, so it outlives the character).
	--
	-- These are the same class of message as the wormhole's "land on an island first" -- a short answer to
	-- something the player just tried -- so they go in the hero lane with every other answer: same card,
	-- same size, same place, same priority order. EVENT priority means a travel refusal never shoves an
	-- island landing off screen, and it queues behind the watering directions and any exclusive tutorial
	-- moment instead of talking over them. NotifyCenter owns the hide, so no timer here can strand anything.
	local SPACE_PURPLE = Color3.fromRGB(150, 70, 230)
	local function showMsg(t)
		local NC = _G.NotifyCenter
		if NC and NC.push then
			pcall(NC.push, {
				text     = t,
				color    = SPACE_PURPLE,
				priority = (NC.PRIORITY and NC.PRIORITY.EVENT) or 80,
				duration = 2.5,
			})
			return
		end
		warn("[WorldClient][BlackHole] " .. t .. "  (NotifyCenter unavailable -- not shown on screen)")
	end
	-- SWEEP THE OLD BOX: one left by a previous session or by a stale baked-in copy of this script has
	-- nothing left to hide it.
	task.spawn(function()
		local pg = player:FindFirstChild("PlayerGui")
		for _ = 1, 5 do
			local old = pg and pg:FindFirstChild("SpaceRealmMsg")
			if old then
				old:Destroy()
				print("[WorldClient][BlackHole] removed a leftover SpaceRealmMsg box -- status is a banner now")
			end
			task.wait(2)
		end
	end)

	-- ============================================================================================
	-- "SUCKED IN" -- the crossing into the Space Realm.
	-- ============================================================================================
	-- Built in the same spirit as the Space Realm's own DinoRift shot (camera locked Scriptable every frame,
	-- os.clock beats, one idempotent restore, ends on black and lets the teleport BE the cut) but deliberately
	-- NOT the same effect. That one is time travel: rings collapse straight in, a year counter spins back,
	-- amber and jungle. This is GRAVITY, so everything here says "falling in" instead:
	--
	--   * rings collapse WHILE ROTATING -- a spiral, not a straight fall. Spin is the whole difference
	--     between "time is rewinding" and "something is pulling me".
	--   * FOV NARROWS instead of punching wide. Wide reads as being thrown forward; narrow reads as
	--     being squeezed down a drain, which is the sensation we want.
	--   * YOUR HUD GETS SUCKED IN. Before the interface is hidden, every visible piece of it is measured
	--     and a ghost rectangle is spawned over the real thing, then spiralled into the singularity. The
	--     game itself comes apart and goes down the hole -- that is the "video HUD" beat.
	--   * purple/white, the black hole's own palette, not the wormhole's blue or the rift's amber.
	--
	-- Every FX touch is pcall'd, so a bad tween or a missing part costs a detail and never the teleport.
	-- Function-scoped, like everything else in this section -- WorldClient declares neither of these at
	-- module level, and the black-hole block's rule is that it adds no module-scope locals.
	local Lighting = game:GetService("Lighting")
	local Debris   = game:GetService("Debris")

	-- THE SAME TRAVEL SOUND THE REALM PORTALS USE. Both are "you are leaving this place through a hole in
	-- it", and one recurring travel cue across every crossing is what makes them feel like one mechanic
	-- rather than three unrelated set pieces. 2D, because it is the player's own crossing.
	local TRAVEL_SOUND_ID = "rbxassetid://111559442515692"
	local TRAVEL_VOLUME   = 0.8
	local travelSound = Instance.new("Sound")
	travelSound.Name = "BlackHoleTravel"
	travelSound.SoundId = TRAVEL_SOUND_ID
	travelSound.Volume = TRAVEL_VOLUME
	travelSound.Parent = game:GetService("SoundService")
	task.spawn(function()
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync({ travelSound }, function(_, status)
				if status == Enum.AssetFetchStatus.Success then
					print(string.format("[BlackHole] travel sound %s loaded OK (length %.2fs)",
						TRAVEL_SOUND_ID, travelSound.TimeLength))
				else
					warn(string.format("[BlackHole] travel sound %s FAILED to load (%s) -- not an audio asset, "
						.. "or not approved for this experience's creator.", TRAVEL_SOUND_ID, tostring(status)))
				end
			end)
		end)
	end)

	local CINEMATIC_SECONDS = 6.2 -- MUST match the task.wait in BlackHoleTeleport.server.lua
	local T_GRAB, T_SPIRAL, T_HORIZON, T_BLACK = 1.2, 2.6, 1.4, 1.0
	-- Shifted off magenta as well: 178,108,255 had enough red in it to read pink once dozens of rings and
	-- streaks overlapped. This is the same brightness in blue-indigo, so the shot keeps its colour without
	-- ever going candy-coloured.
	local VIOLET = Color3.fromRGB(120, 110, 255)
	local WHITEHOT = Color3.fromRGB(225, 232, 255)

	local suckRunning = false
	local function playSuckIn()
		if suckRunning then return end
		suckRunning = true

		-- ONCE, AND THEN LEFT ALONE.
		-- This is a LONG cue, and the rift has TWO touch volumes (the core orb and the accretion disk), so
		-- arriving at speed can trip both in the same instant. Calling :Play() on a Sound that is already
		-- playing RESTARTS it from zero -- so a retrigger does not double the sound, it truncates it: you
		-- hear the first fraction of a second over and over and the clip never gets anywhere. Setting
		-- TimePosition = 0 does the same thing for the same reason.
		--
		-- So: if it is already running, leave it running. A cue that is mid-play is already doing its job,
		-- and the correct response to "play this again" is to do nothing at all.
		pcall(function()
			if travelSound.IsPlaying then return end
			travelSound:Play()
			print(string.format("[BlackHole] travel sound started (loaded=%s vol=%.2f)",
				tostring(travelSound.IsLoaded), travelSound.Volume))
		end)

		local cam = workspace.CurrentCamera
		local origFov = cam and cam.FieldOfView or 70
		local currentCF = cam and cam.CFrame or CFrame.new()
		local restored, renderConn, guiAddedConn, blur, cc, gui = false, nil, nil, nil, nil, nil
		local hidden = {}
		local shakeMag, squeeze = 0, 0

		-- ONE teardown, every failure path lands here. The SUCCESS path never calls it: we hold on black
		-- and the teleport takes us. (Studio, where the teleport does nothing, is rescued by the timeout.)
		local function restore()
			if restored then return end
			restored = true
			if renderConn then renderConn:Disconnect() end
			if guiAddedConn then guiAddedConn:Disconnect() end
			pcall(function()
				local c = workspace.CurrentCamera
				if c then
					c.CameraType = Enum.CameraType.Custom
					local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if hum then c.CameraSubject = hum end
					c.FieldOfView = origFov
				end
			end)
			if blur then pcall(function() blur:Destroy() end) end
			if cc then pcall(function() cc:Destroy() end) end
			for sg, wasOn in pairs(hidden) do pcall(function() sg.Enabled = wasOn end) end
			pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
			if gui then pcall(function() gui:Destroy() end) end
			suckRunning = false
		end
		task.delay(CINEMATIC_SECONDS + 12, restore) -- hard backstop if the teleport never happens

		gui = Instance.new("ScreenGui")
		gui.Name = "BlackHoleSuckIn"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Global; gui.DisplayOrder = 10000
		gui.Parent = player:WaitForChild("PlayerGui")

		local shell = Instance.new("Frame") -- everything rides in here; shaking = offsetting this
		shell.Size = UDim2.new(1, 0, 1, 0); shell.BackgroundTransparency = 1; shell.ZIndex = 2
		shell.Parent = gui

		-- ---------- MEASURE THE HUD, THEN TAKE IT APART ----------
		-- Snapshot each visible piece where it actually sits on screen, so the ghosts line up exactly with
		-- what the player was looking at a frame ago. Capped: a couple of dozen shards reads as "everything",
		-- and spawning one per GuiObject in this game would be hundreds of frames of tweening.
		local ghosts = {}
		pcall(function()
			-- The old exclusion was `sg ~= msgGui` -- the bespoke status box, so the words telling you what
			-- was happening did not shatter along with the HUD. That box is gone (its messages are hero
			-- banners now), so the exclusion moves to the banner lanes by NAME: NotifyHero/NotifySocial are
			-- live messages, not furniture, and ghosting them would tear up a sentence mid-read.
			local NO_GHOST = { NotifyHero = true, NotifySocial = true }
			for _, sg in ipairs(player.PlayerGui:GetChildren()) do
				if sg:IsA("ScreenGui") and sg.Enabled and sg ~= gui and not NO_GHOST[sg.Name] then
					for _, obj in ipairs(sg:GetChildren()) do
						if #ghosts >= 24 then break end
						if obj:IsA("GuiObject") and obj.Visible and obj.AbsoluteSize.X > 24 and obj.AbsoluteSize.Y > 12 then
							local g = Instance.new("Frame")
							g.Position = UDim2.fromOffset(obj.AbsolutePosition.X, obj.AbsolutePosition.Y)
							g.Size = UDim2.fromOffset(obj.AbsoluteSize.X, obj.AbsoluteSize.Y)
							g.BackgroundColor3 = obj.BackgroundColor3
							-- FAINT, AND WITH NO EDGE. A ghost at full opacity with a corner radius and a coloured
							-- outline is a RECTANGLE flying across the screen, and the eye names it instantly.
							-- Faint, un-outlined, and feathered to nothing at both ends, it reads as a smear of
							-- the colour that used to be there -- an interface dissolving rather than furniture
							-- being thrown around. The outline is the single biggest tell; it is gone.
							g.BackgroundTransparency = math.clamp(obj.BackgroundTransparency, 0.55, 0.82)
							g.BorderSizePixel = 0; g.ZIndex = 8; g.Parent = shell
							local gg = Instance.new("UIGradient")
							gg.Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 1),
								NumberSequenceKeypoint.new(0.5, 0),
								NumberSequenceKeypoint.new(1, 1),
							})
							gg.Rotation = 90
							gg.Parent = g
							ghosts[#ghosts + 1] = g
						end
					end
				end
			end
		end)

		local function hideOne(child)
			if child == gui or not child:IsA("ScreenGui") then return end
			if hidden[child] == nil then hidden[child] = child.Enabled; child.Enabled = false end
		end
		for _, c in ipairs(player.PlayerGui:GetChildren()) do hideOne(c) end
		guiAddedConn = player.PlayerGui.ChildAdded:Connect(hideOne) -- catch anything that appears mid-shot
		pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)

		-- ---------- backdrop + the singularity you are falling into ----------
		local backdrop = Instance.new("Frame")
		backdrop.Size = UDim2.new(1, 0, 1, 0); backdrop.BackgroundColor3 = Color3.fromRGB(6, 2, 14)
		backdrop.BackgroundTransparency = 1; backdrop.BorderSizePixel = 0; backdrop.ZIndex = 1
		backdrop.Parent = gui

		local core = Instance.new("Frame")
		core.AnchorPoint = Vector2.new(0.5, 0.5); core.Position = UDim2.new(0.5, 0, 0.5, 0)
		core.Size = UDim2.new(0, 10, 0, 10)
		core.BackgroundColor3 = Color3.new(0, 0, 0)
		core.BackgroundTransparency = 1; core.BorderSizePixel = 0; core.ZIndex = 10; core.Parent = shell
		Instance.new("UICorner", core).CornerRadius = UDim.new(1, 0)
		-- NO STROKE. A coloured ring drawn round a black circle is a clean geometric outline sitting dead
		-- centre and growing -- the most object-like thing that was on screen, and the eye locks onto it.
		-- Instead the disc feathers to nothing through a gradient, so it has no boundary at all: it simply
		-- stops being dark. Nothing here has an edge you can point at.
		do
			local cg = Instance.new("UIGradient")
			cg.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.42, 0),
				NumberSequenceKeypoint.new(0.58, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			cg.Parent = core
		end
		-- the light around it: a wider, softer disc that also fades out to nothing at its rim
		local halo = Instance.new("Frame")
		halo.AnchorPoint = Vector2.new(0.5, 0.5); halo.Position = UDim2.new(0.5, 0, 0.5, 0)
		halo.Size = UDim2.new(0, 10, 0, 10)
		halo.BackgroundColor3 = VIOLET
		halo.BackgroundTransparency = 1; halo.BorderSizePixel = 0; halo.ZIndex = 9; halo.Parent = shell
		Instance.new("UICorner", halo).CornerRadius = UDim.new(1, 0)
		do
			local hg = Instance.new("UIGradient")
			hg.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.45),
				NumberSequenceKeypoint.new(0.5, 0.15),
				NumberSequenceKeypoint.new(0.7, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			})
			hg.Parent = halo
		end

		-- vignette: the edges closing in as gravity narrows what you can still see
		local vign = Instance.new("Frame")
		vign.Size = UDim2.new(1, 0, 1, 0); vign.BackgroundTransparency = 1; vign.BorderSizePixel = 0
		vign.ZIndex = 14; vign.Parent = gui
		do
			local vg = Instance.new("UIGradient")
			vg.Color = ColorSequence.new(Color3.new(0, 0, 0))
			vg.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0),
			})
			vg.Parent = vign
		end

		-- ---------- a ring that collapses AND spins: the spiral read ----------
		local function spawnSpiralRing()
			local r = Instance.new("Frame")
			r.AnchorPoint = Vector2.new(0.5, 0.5); r.Position = UDim2.new(0.5, 0, 0.5, 0)
			r.Size = UDim2.new(0, 1500, 0, 1500) -- born past the screen edge...
			r.BackgroundTransparency = 1; r.BorderSizePixel = 0; r.ZIndex = 4; r.Parent = shell
			Instance.new("UICorner", r).CornerRadius = UDim.new(1, 0)
			local st = Instance.new("UIStroke", r)
			st.Color = (math.random() < 0.5) and VIOLET or WHITEHOT
			-- Thinner and much fainter than before (was up to 7px at 0.3). A crisp bright ring is a drawn
			-- circle; a faint one is a wavefront. A UIGradient INSIDE the stroke then fades it away around
			-- its own circumference, so no ring is ever a complete, evenly-lit outline -- it is an arc of
			-- light that happens to curve, which is what kills the "geometry" read.
			st.Thickness = 1 + math.random() * 2.5; st.Transparency = 0.62
			local sg = Instance.new("UIGradient")
			sg.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			sg.Rotation = math.random(0, 359)
			sg.Parent = st
			local dur = 0.8 + math.random() * 0.3
			pcall(function()
				-- ...and is dragged down to a point. Easing In means it ACCELERATES as it falls, which is
				-- what a gravity well does and a constant-speed collapse does not.
				TweenService:Create(r, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Size = UDim2.new(0, 8, 0, 8), Rotation = 120 + math.random() * 90,
				}):Play()
				TweenService:Create(st, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Transparency = 1,
				}):Play()
			end)
			Debris:AddItem(r, dur + 0.1)
		end

		-- ---------- matter streaks: thrown outward-ish, then curved in ----------
		local function spawnStreak()
			local s = Instance.new("Frame")
			local ang = math.rad(math.random(0, 359))
			local dist = 0.55 + math.random() * 0.5
			s.AnchorPoint = Vector2.new(0.5, 0.5)
			s.Position = UDim2.new(0.5 + math.cos(ang) * dist, 0, 0.5 + math.sin(ang) * dist, 0)
			s.Size = UDim2.new(0, 2 + math.random() * 2, 0, 26 + math.random() * 70)
			s.BackgroundColor3 = (math.random() < 0.4) and VIOLET or WHITEHOT
			s.BackgroundTransparency = 0.35; s.BorderSizePixel = 0
			s.Rotation = math.deg(ang) + 90 -- lie along the direction of travel, so it streaks rather than tumbles
			s.ZIndex = 5; s.Parent = shell
			-- THE BIGGEST SINGLE FIX. A rounded rectangle is a capsule -- a little pill tumbling across the
			-- screen, and forty of them look like confetti. Fading it to nothing at BOTH ends turns the same
			-- frame into a streak of light with no start and no finish: motion blur rather than an object.
			-- The corner radius goes with it; once both ends are transparent there is no corner left to see.
			local sg = Instance.new("UIGradient")
			sg.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.45, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			})
			sg.Rotation = 90 -- along the streak's long axis
			sg.Parent = s
			local dur = 0.3 + math.random() * 0.3
			pcall(function()
				TweenService:Create(s, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.new(0.5, 0, 0.5, 0),
					Size = UDim2.new(0, 1, 0, 8),
					BackgroundTransparency = 1,
					Rotation = s.Rotation + 80, -- the curve: matter does not fall straight in, it winds in
				}):Play()
			end)
			Debris:AddItem(s, dur + 0.1)
		end

		-- ---------- camera held Scriptable EVERY frame; shake + squeeze applied to the shell ----------
		renderConn = RunService.RenderStepped:Connect(function()
			if restored then return end
			local c = workspace.CurrentCamera
			if c then c.CameraType = Enum.CameraType.Scriptable; c.CFrame = currentCF end
			local ox = (shakeMag > 0) and math.random(-10, 10) * shakeMag or 0
			local oy = (shakeMag > 0) and math.random(-10, 10) * shakeMag or 0
			-- SQUEEZE: the whole frame shrinks toward the middle late in the shot, so the picture itself
			-- looks like it is being pulled through the hole rather than merely covered by an overlay.
			local k = squeeze
			shell.Size = UDim2.new(1 - k, 0, 1 - k, 0)
			shell.Position = UDim2.new(k / 2, ox, k / 2, oy)
		end)

		blur = Instance.new("BlurEffect"); blur.Size = 0; blur.Parent = Lighting
		cc = Instance.new("ColorCorrectionEffect"); cc.Parent = Lighting

		local ok, err = pcall(function()
			-- Look at the hole from wherever the player is, and ride toward it.
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local target = model.PrimaryPart and model.PrimaryPart.Position or (hrp and hrp.Position)
			local from = hrp and (hrp.Position + Vector3.new(0, 4, 0)) or currentCF.Position
			if target then currentCF = CFrame.lookAt(from, target) end

			-- ===== BEAT 1: GRAB (1.2s) -- it notices you =====
			pcall(function()
				TweenService:Create(backdrop, TweenInfo.new(T_GRAB), { BackgroundTransparency = 0.25 }):Play()
				TweenService:Create(blur, TweenInfo.new(T_GRAB), { Size = 14 }):Play()
				TweenService:Create(vign, TweenInfo.new(T_GRAB), { BackgroundTransparency = 0.35 }):Play()
				TweenService:Create(halo, TweenInfo.new(T_GRAB), {
					BackgroundTransparency = 0.25, Size = UDim2.new(0, 320, 0, 320),
				}):Play()
				TweenService:Create(core, TweenInfo.new(T_GRAB), {
					BackgroundTransparency = 0, Size = UDim2.new(0, 70, 0, 70),
				}):Play()
			end)
			local t0 = os.clock()
			while not restored and (os.clock() - t0) < T_GRAB do
				local a = (os.clock() - t0) / T_GRAB
				local e = TweenService:GetValue(a, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				shakeMag = e * 0.8
				if cam then cam.FieldOfView = origFov - e * 18 end -- NARROWING: squeezed, not thrown
				if target and hrp then
					currentCF = CFrame.lookAt(from:Lerp(target, e * 0.5), target)
				end
				task.wait()
			end
			if restored then return end

			-- ===== BEAT 2: SPIRAL (2.6s) -- the HUD and everything else goes down the drain =====
			-- The ghosts launch together on the first frame of this beat: the interface coming apart is the
			-- moment the player understands they are the thing being pulled, not the scenery.
			for i, g in ipairs(ghosts) do
				local delay = (i - 1) * 0.045
				task.delay(delay, function()
					pcall(function()
						TweenService:Create(g, TweenInfo.new(0.85 + math.random() * 0.4,
							Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
							Position = UDim2.new(0.5, 0, 0.5, 0),
							Size = UDim2.fromOffset(6, 6),
							Rotation = (math.random() < 0.5 and -1 or 1) * (180 + math.random(0, 220)),
							BackgroundTransparency = 1,
						}):Play()
					end)
				end)
				Debris:AddItem(g, 2)
			end

			pcall(function()
				TweenService:Create(backdrop, TweenInfo.new(0.8), { BackgroundTransparency = 0 }):Play()
			end)
			local ringClock, streakClock = 0, 0
			t0 = os.clock()
			while not restored and (os.clock() - t0) < T_SPIRAL do
				local dt = task.wait()
				local a = (os.clock() - t0) / T_SPIRAL
				shakeMag = 0.6 + a * 0.9
				squeeze = a * 0.10
				if cam then cam.FieldOfView = origFov - 18 - a * 16 end
				-- NO PINK. This used to hold red and blue at full while pulling GREEN down, which is exactly
				-- how you make magenta -- it washed the whole shot pink. Pulling RED down instead leaves a
				-- cold blue-white, which is what a collapsing star should look like anyway.
				cc.TintColor = Color3.fromRGB(255 - math.floor(a * 55), 255 - math.floor(a * 18), 255)
				cc.Contrast = a * 0.4
				pcall(function()
					local d = 70 + a * 130
					core.Size = UDim2.new(0, d, 0, d)
					halo.Size = UDim2.new(0, d * 3.4, 0, d * 3.4) -- the glow always outruns the dark centre
				end)
				-- the barrel roll TIGHTENS as we fall -- the spin of the accretion disk taking us with it
				currentCF = currentCF * CFrame.Angles(0, 0, math.rad(dt * (30 + a * 90)))
				ringClock += dt; streakClock += dt
				-- FEWER, NOT MORE. Restraint is most of what separates a finished transition from a busy one:
				-- the old rates (a ring every 0.11s, two streaks every 0.025s) put so much on screen at once
				-- that you stopped seeing an effect and started seeing individual moving parts.
				if ringClock > 0.19 then ringClock = 0; spawnSpiralRing() end
				if streakClock > 0.045 then streakClock = 0; spawnStreak() end
			end
			if restored then return end

			-- ===== BEAT 3: HORIZON (1.4s) -- crossing it =====
			pcall(function() blur.Size = 26 end)
			for _ = 1, 18 do spawnStreak() end -- was 50; a wall of them read as debris, not speed
			local flash = Instance.new("Frame")
			flash.Size = UDim2.new(1, 0, 1, 0); flash.BackgroundColor3 = WHITEHOT
			flash.BackgroundTransparency = 1; flash.BorderSizePixel = 0; flash.ZIndex = 20; flash.Parent = gui
			pcall(function()
				-- the hole swells to swallow the frame, then the crossing whites out
				TweenService:Create(core, TweenInfo.new(T_HORIZON * 0.7, Enum.EasingStyle.Quint,
					Enum.EasingDirection.In), { Size = UDim2.new(2.2, 0, 2.2, 0) }):Play()
				TweenService:Create(halo, TweenInfo.new(T_HORIZON * 0.7, Enum.EasingStyle.Quint,
					Enum.EasingDirection.In), { Size = UDim2.new(5, 0, 5, 0), BackgroundTransparency = 0 }):Play()
				TweenService:Create(flash, TweenInfo.new(T_HORIZON * 0.55, Enum.EasingStyle.Quad,
					Enum.EasingDirection.In), { BackgroundTransparency = 0 }):Play()
			end)
			t0 = os.clock()
			while not restored and (os.clock() - t0) < T_HORIZON do
				local a = (os.clock() - t0) / T_HORIZON
				shakeMag = 2.2 * (1 - a)
				squeeze = 0.10 + a * 0.16
				if cam then cam.FieldOfView = origFov - 34 + a * 10 end
				task.wait()
			end
			if restored then return end

			-- ===== BEAT 4: BLACK (1.0s) -- hold. The teleport is the cut. =====
			shakeMag = 0
			-- Same card treatment as the realm portals, so both crossings end the same way: a near-black
			-- tinted toward the destination rather than flat black, a wide feathered glow behind the words
			-- so there is depth instead of absence, a title that settles from oversized rather than simply
			-- appearing, and a feathered light under it. See the long note in RealmPortals for the reasoning.
			local black = Instance.new("Frame")
			black.Size = UDim2.new(1, 0, 1, 0)
			black.BackgroundColor3 = VIOLET:Lerp(Color3.new(0, 0, 0), 0.94)
			black.BackgroundTransparency = 1; black.BorderSizePixel = 0; black.ZIndex = 25; black.Parent = gui

			local cglow = Instance.new("Frame")
			cglow.AnchorPoint = Vector2.new(0.5, 0.5); cglow.Position = UDim2.new(0.5, 0, 0.5, 0)
			cglow.Size = UDim2.new(1.4, 0, 0, 420)
			cglow.BackgroundColor3 = VIOLET
			cglow.BackgroundTransparency = 1; cglow.BorderSizePixel = 0; cglow.ZIndex = 26; cglow.Parent = gui
			Instance.new("UICorner", cglow).CornerRadius = UDim.new(1, 0)
			do
				local gg = Instance.new("UIGradient")
				gg.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0.82),
					NumberSequenceKeypoint.new(1, 1),
				})
				gg.Parent = cglow
			end

			local card = Instance.new("TextLabel")
			card.AnchorPoint = Vector2.new(0.5, 0.5); card.Position = UDim2.new(0.5, 0, 0.5, 0)
			card.Size = UDim2.new(1.02, 0, 0, 102); card.BackgroundTransparency = 1
			card.Font = Enum.Font.FredokaOne; card.TextScaled = true
			card.TextColor3 = WHITEHOT; card.TextTransparency = 1
			card.Text = "SPACE REALM"; card.ZIndex = 28; card.Parent = gui
			do local c = Instance.new("UITextSizeConstraint", card); c.MaxTextSize = 58 end
			local cardStroke = Instance.new("UIStroke", card)
			cardStroke.Color = VIOLET; cardStroke.Thickness = 3; cardStroke.Transparency = 1

			local sub = Instance.new("TextLabel")
			sub.AnchorPoint = Vector2.new(0.5, 0.5); sub.Position = UDim2.new(0.5, 0, 0.5, 62)
			sub.Size = UDim2.new(0.8, 0, 0, 30); sub.BackgroundTransparency = 1
			sub.Font = Enum.Font.GothamMedium; sub.TextScaled = true
			sub.TextColor3 = VIOLET; sub.TextTransparency = 1
			sub.Text = "\xF0\x9F\x9A\x80  through the black hole"
			sub.ZIndex = 28; sub.Parent = gui
			do local c = Instance.new("UITextSizeConstraint", sub); c.MaxTextSize = 20 end

			local line = Instance.new("Frame")
			line.AnchorPoint = Vector2.new(0.5, 0.5); line.Position = UDim2.new(0.5, 0, 0.5, 38)
			line.Size = UDim2.new(0, 0, 0, 2)
			line.BackgroundColor3 = VIOLET
			line.BackgroundTransparency = 0.25; line.BorderSizePixel = 0; line.ZIndex = 28; line.Parent = gui
			do
				local lg = Instance.new("UIGradient")
				lg.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				})
				lg.Parent = line
			end

			pcall(function()
				TweenService:Create(black, TweenInfo.new(0.45, Enum.EasingStyle.Quad,
					Enum.EasingDirection.In), { BackgroundTransparency = 0 }):Play()
			end)
			task.wait(0.45)
			pcall(function()
				TweenService:Create(cglow, TweenInfo.new(0.6), { BackgroundTransparency = 0 }):Play()
				TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Quint,
					Enum.EasingDirection.Out), { TextTransparency = 0, Size = UDim2.new(0.9, 0, 0, 90) }):Play()
				TweenService:Create(cardStroke, TweenInfo.new(0.45), { Transparency = 0 }):Play()
				TweenService:Create(line, TweenInfo.new(0.55, Enum.EasingStyle.Quint,
					Enum.EasingDirection.Out), { Size = UDim2.new(0.42, 0, 0, 2) }):Play()
			end)
			task.delay(0.2, function()
				pcall(function()
					TweenService:Create(sub, TweenInfo.new(0.4), { TextTransparency = 0.25 }):Play()
				end)
			end)
			-- HOLD ON BLACK -- no restore. The server teleports us while this is up.
		end)

		if not ok then
			warn("[BlackHole] suck-in cinematic error: " .. tostring(err))
			restore()
		end
	end

	local enterEvent = game:GetService("ReplicatedStorage"):WaitForChild("BlackHoleEnterEvent", 30)
	local traveling = false -- per-player debounce (this is the local player's client)
	if enterEvent then
		enterEvent.OnClientEvent:Connect(function(status) -- the SERVER tells us what to show
			if status == "traveling" then
				task.spawn(playSuckIn) -- the shot replaces the old "Traveling..." text box entirely
			-- The banner hides itself; these timers now only release the touch debounce. Untangling the two
			-- is the point -- a missed hide and a stuck debounce used to be the same bug.
			elseif status == "locked" then
				showMsg("\xF0\x9F\x94\x92 Space Realm \xE2\x80\x94 Coming soon!"); task.delay(2.5, function() traveling = false end)
			elseif status == "error" then
				showMsg("Couldn't travel right now, try again"); task.delay(2.5, function() traveling = false end)
			end
		end)
	end

	-- ONE handler for both trigger volumes: the core void AND the accretion disk (the rings).
	local function onRiftTouched(hit)
		if traveling then return end
		local char = player.Character
		if not (char and hit and hit:IsDescendantOf(char)) then return end -- only the LOCAL player's character
		traveling = true
		if enterEvent then pcall(function() enterEvent:FireServer() end) end -- send INTENT; the SERVER gates + teleports
	end
	touchOrb.Touched:Connect(onRiftTouched)
	touchDisk.Touched:Connect(onRiftTouched)

	return model
end

-- Navigation GUI
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end

local navSg=Instance.new("ScreenGui"); navSg.Name="NavGui"; navSg.ResetOnSpawn=false; navSg.Parent=player.PlayerGui
-- NEXT-ISLAND POINTER: a big, bold, no-background WHITE up-arrow with a thick black outline. It tracks the next
-- island (the loop below rotates it toward the target). navFrame is just the transparent host that gets positioned.
local navFrame=mkFrame(navSg,{Size=UDim2.new(0,54,0,54),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,Visible=false})
local navArrow=mkLabel(navFrame,{Text="\xe2\x86\x91",Font=Enum.Font.GothamBold,TextSize=48,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,1,0),TextXAlignment=Enum.TextXAlignment.Center})
local navArrowStroke=mkStroke(navArrow,Color3.new(0,0,0),5); navArrowStroke.LineJoinMode=Enum.LineJoinMode.Round -- thick black outline
local navName=mkLabel(navSg,{Text="",Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.new(1,1,1),Size=UDim2.new(0,120,0,16),AnchorPoint=Vector2.new(0.5,0),TextXAlignment=Enum.TextXAlignment.Center,Visible=false}); mkStroke(navName,Color3.new(0,0,0),1)

-- Spawn world objects
task.spawn(function()
	task.wait(3)
	local rng=Random.new(); local ridx=0
	local RINGS_PER_GAP = 2  -- rings per island gap. FEWER = MORE distance between rings. Was 6 (spacing = gap/7); 2 => spacing = gap/3 (~2.3x farther apart).
	-- Horizontal spread of rings OFF the straight-up climb line (was a tiny +/-15 jitter).
	-- Each ring sits a random direction out at MIN..MAX studs, so collecting is a real choice.
	local RING_SPREAD_MIN = 85   -- min studs off the centerline (was 55) -- wider sideways spread
	local RING_SPREAD_MAX = 145  -- max studs off the centerline (was 110)
	for i=1,13 do
		local startPos=getStandPosition(i); local endPos=getStandPosition(i+1)
		local safeStart=startPos+Vector3.new(0,120,0)
		local safeEnd=endPos-Vector3.new(0,200,0)
		if safeEnd.Y > endPos.Y-200 then safeEnd=Vector3.new(safeEnd.X,endPos.Y-200,safeEnd.Z) end
		local dVec=safeEnd-safeStart; local dUnit=dVec.Magnitude>0 and dVec.Unit or Vector3.new(0,1,0)
		local ringBaseAng=math.random()*2*math.pi  -- per-gap base angle; the gap's rings are spread apart from it
		for j=1,RINGS_PER_GAP do
			local ang=ringBaseAng + (j-1)*(2*math.pi/RINGS_PER_GAP) -- put the gap's rings on OPPOSITE sides (further from each other)
				local rad=RING_SPREAD_MIN+math.random()*(RING_SPREAD_MAX-RING_SPREAD_MIN)
				-- Push the ring FAR off the straight-up climb line so collecting it is a real
				-- CHOICE (players deviate sideways), not something they fly through on a normal ascent.
				local pos=safeStart:Lerp(safeEnd,j/(RINGS_PER_GAP+1))+Vector3.new(math.cos(ang)*rad,0,math.sin(ang)*rad)
			ridx=ridx+1; spawnRing(pos,_G.RING_COLORS[((j-1)%3)+1],ridx,dUnit)
		end
	end
	-- Landing-pad target markers removed alongside the perfect-landing reward (see above).
	-- Gas bubbles: spread FAR off the central climb line (like rings; was just a +/-30 jitter) so
	-- grabbing one is a deliberate sideways move, and the two bubbles in a gap sit on ~OPPOSITE sides
	-- so they're far from each other too. Vertical placement (t=0.35 / 0.65) is unchanged.
	local BUBBLE_SPREAD_MIN = 60   -- min studs off the centerline (was a ~+/-30 jitter)
	local BUBBLE_SPREAD_MAX = 110  -- max studs off the centerline
	for i=1,13 do
		local startPos=getStandPosition(i); local endPos=getStandPosition(i+1)
		local safeStart=startPos+Vector3.new(0,120,0)
		local safeEnd=endPos-Vector3.new(0,200,0)
		if safeEnd.Y > endPos.Y-200 then safeEnd=Vector3.new(safeEnd.X,endPos.Y-200,safeEnd.Z) end
		local pocketBaseAng=rng:NextNumber()*2*math.pi
		local function lerpPocket(t, ang)
			local rad=BUBBLE_SPREAD_MIN+rng:NextNumber()*(BUBBLE_SPREAD_MAX-BUBBLE_SPREAD_MIN)
			return safeStart:Lerp(safeEnd, t) + Vector3.new(math.cos(ang)*rad, 0, math.sin(ang)*rad)
		end
		spawnGasPocket(lerpPocket(0.35, pocketBaseAng)); spawnGasPocket(lerpPocket(0.65, pocketBaseAng + math.pi))
	end
	-- BLACK HOLE (VISUAL ONLY): place it high above Pizza Palms (Island 14). getStandPosition(14) is
	-- the real island-14 top (already used by the loops above, so island 14 exists by now). pcall'd so
	-- a build hiccup can't stop the world spawn, and the placement Y is printed either way.
	local pizzaPos = getStandPosition(14)
	local bhCenter = Vector3.new(pizzaPos.X, pizzaPos.Y + BH_HEIGHT_OFFSET, pizzaPos.Z)
	local okBH, errBH = pcall(function() buildBlackHole(bhCenter) end)
	if okBH then
		print(string.format("[BlackHole] placed at (%.0f, %.0f, %.0f) above Pizza Palms - touch -> Space Realm teleport wired (tester-locked) [baseY=%.0f + offset=%d]",
			bhCenter.X, bhCenter.Y, bhCenter.Z, pizzaPos.Y, BH_HEIGHT_OFFSET))
	else
		warn("[BlackHole] BUILD ERROR (no model created): " .. tostring(errBH))
	end
	print("WORLD OBJECTS SPAWNED")
end)

-- OWNER overhead tags: these 3 usernames (lando5485 also matched by UserId for safety) show a single
-- green "Owner" tag instead of the normal island/name billboard. Every OTHER player is unchanged.
local OWNER_NAMES = { ["Broskie310111"] = true, ["lando5485"] = true }
local OWNER_USERIDS = { [1086836724] = true } -- lando5485 (extra safety; the username above also matches)
local function isOwner(p)
	return OWNER_NAMES[p.Name] == true or OWNER_USERIDS[p.UserId] == true
end

-- Ghost trail + flying count loop
task.spawn(function()
	while true do
		task.wait(1)
		local flyingCount=0
		for _,p in ipairs(Players:GetPlayers()) do
			if p~=player then
				local char2=p.Character
				if char2 then local hrp2=char2:FindFirstChild("HumanoidRootPart"); if hrp2 and hrp2:FindFirstChild("FartVelocity") then flyingCount=flyingCount+1 end end
			end
		end
		if _G.isFlying then flyingCount=flyingCount+1 end
		if _G.flyingLabel then _G.flyingLabel.Text=flyingCount>0 and (flyingCount.." player"..(flyingCount==1 and "" or "s").." flying now") or "" end
		for _,p in ipairs(Players:GetPlayers()) do
			if p~=player then
				pcall(function()
					local char2=p.Character; if not char2 then playerBillboards[p]=nil; return end
					local head2=char2:FindFirstChild("Head"); if not head2 then return end
					local bb=playerBillboards[p]
					if not bb or not bb.Parent then
						bb=Instance.new("BillboardGui"); bb.Name="GhostTrailBB"; bb.Size=UDim2.new(0,120,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=false; bb.Parent=head2; playerBillboards[p]=bb
						local dot=Instance.new("Frame"); dot.Name="Dot"; dot.Size=UDim2.new(0,10,0,10); dot.Position=UDim2.new(0,2,0.5,-5); dot.BorderSizePixel=0; dot.ZIndex=2; dot.Parent=bb; local dc=Instance.new("UICorner"); dc.CornerRadius=UDim.new(1,0); dc.Parent=dot
						local lbl=Instance.new("TextLabel"); lbl.Name="Info"; lbl.Size=UDim2.new(1,-14,1,0); lbl.Position=UDim2.new(0,14,0,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=13; lbl.TextColor3=Color3.new(1,1,1); lbl.TextWrapped=true; lbl.LineHeight=1.1; lbl.Parent=bb
						local st=Instance.new("UIStroke"); st.Color=Color3.new(0,0,0); st.Thickness=1.5; st.Parent=lbl
					end
					if isOwner(p) then
						-- OWNER: a single green "Owner" tag — no dot, no username, no island. Also hide the
						-- default Roblox name/health overhead so NOTHING else shows over their head.
						local hum2=char2:FindFirstChildOfClass("Humanoid")
						if hum2 then hum2.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None end
						local dot2=bb:FindFirstChild("Dot"); if dot2 then dot2.Visible=false end
						local lbl2=bb:FindFirstChild("Info")
						if lbl2 then
							lbl2.Text="Owner"; lbl2.TextColor3=Color3.fromRGB(0,255,0)
							lbl2.Position=UDim2.new(0,0,0,0); lbl2.Size=UDim2.new(1,0,1,0)
							lbl2.TextXAlignment=Enum.TextXAlignment.Center
						end
					else
						-- Everyone else: unchanged normal overhead (island-colored dot + Username + Island name).
						local pIsland=1
						pcall(function() local pls2=p:FindFirstChild("leaderstats"); if pls2 then local i2=pls2:FindFirstChild("Island"); if i2 then pIsland=i2.Value end end end)
						local ic=_G.ISLAND_COLORS[pIsland] or Color3.fromRGB(100,200,100)
						local iname2=_G.ISLAND_DISPLAY_NAMES[pIsland] or ("Island "..pIsland)
						local dot2=bb:FindFirstChild("Dot"); if dot2 then dot2.BackgroundColor3=ic end
						local lbl2=bb:FindFirstChild("Info"); if lbl2 then lbl2.Text=p.Name.."\n"..iname2 end
					end
				end)
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(p) playerBillboards[p]=nil end)

-- Island arrival: only triggers when player physically lands on an island surface
RunService.Heartbeat:Connect(function()
	pcall(function()
		local character = player.Character; if not character then return end
		local hum = character:FindFirstChild("Humanoid"); if not hum then return end
		local hrp = character:FindFirstChild("HumanoidRootPart"); if not hrp then return end
		if hum.FloorMaterial == Enum.Material.Air then return end
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {character}
		local result = workspace:Raycast(hrp.Position, Vector3.new(0,-4,0), rayParams)
		if result and result.Instance then
			local testObj = result.Instance
			while testObj and testObj ~= workspace do
				local islandNum = testObj.Name:match("^Island_(%d+)_")
				if islandNum then
					islandNum = tonumber(islandNum)
					if islandNum and islandNum > currentKnownIsland then
						currentKnownIsland = islandNum
						-- NOTE: no welcome here. The "You reached [Island]!" welcome is fired by the
						-- server's authoritative physical-landing detection (WelcomeEvent), not client-side.
						_G.unlockedIslands = _G.unlockedIslands or {}
						for i = 1, islandNum do _G.unlockedIslands[i] = true end
						if IslandUnlockEvent then
							print("ISLAND LANDING DETECTED:", islandNum)
							IslandUnlockEvent:FireServer(islandNum)
						end
					end
					break
				end
				testObj = testObj.Parent
			end
		end
	end)
end)

-- Navigation arrow loop
task.spawn(function()
	local Camera=workspace.CurrentCamera
	while true do
		task.wait(0.1)
		pcall(function()
			local ls=_G.leaderstats; if not ls then navFrame.Visible=false; navName.Visible=false; return end
			local islVal=ls:FindFirstChild("Island"); if not islVal then navFrame.Visible=false; navName.Visible=false; return end
			local nextIsland=islVal.Value+1; if nextIsland>14 then navFrame.Visible=false; navName.Visible=false; return end
			local tp=_G.ISLAND_POS[nextIsland]; local target3D=Vector3.new(tp.x,tp.y,tp.z)
			local vp=Camera.ViewportSize; local cx,cy=vp.X/2,vp.Y/2
			local screenPos,onScreen=Camera:WorldToScreenPoint(target3D)
			local dx,dy=screenPos.X-cx,screenPos.Y-cy
			local margin=60; local maxX=cx-margin; local maxY=cy-margin
			local ex,ey
			if onScreen and screenPos.Z>0 and math.abs(dx)<maxX and math.abs(dy)<maxY then
				ex=screenPos.X; ey=screenPos.Y
			else
				if math.abs(dx)*maxY>=math.abs(dy)*maxX then
					local sign=dx>=0 and 1 or -1; ex=cx+sign*maxX; ey=cy+dy*(maxX/math.max(math.abs(dx),0.001))
				else
					local sign=dy>=0 and 1 or -1; ey=cy+sign*maxY; ex=cx+dx*(maxY/math.max(math.abs(dy),0.001))
				end
			end
			navFrame.Position=UDim2.new(0,ex,0,ey); navName.Position=UDim2.new(0,ex,0,ey+26)
			navArrow.Rotation=math.deg(math.atan2(dy,dx))+90; navFrame.Visible=true
			-- ISLAND-NAME REVEAL: only show the real name once THIS player has REACHED the island.
			-- "HighestIsland" is a per-player, server-authoritative attribute (replicated to the owning
			-- client and updated the instant the player reaches/skips to a new island). We read it via
			-- the LocalPlayer, so each player sees names based on THEIR OWN progress only. This loop
			-- polls every 0.1s, so the label flips on the moment their HighestIsland increases.
			local highest = player:GetAttribute("HighestIsland") or 0
			if nextIsland <= highest then
				-- Visited (island number <= highest reached): show the real island name.
				navName.Text=_G.ISLAND_DISPLAY_NAMES[nextIsland] or ("Island "..nextIsland)
				navName.Visible=true
			else
				-- Not yet visited: NO "???" -- just the pointer, no mystery label.
				navName.Visible=false
			end
		end)
	end
end)

print("WORLDCLIENT READY")
