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
		local SPEED = 12 -- studs/sec: ~2.4x the old 5 -- a real chase, but still catchable by a determined flyer
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
	makeBillboard(ring,"\xF0\x9F\xAA\x99 +BONUS",Color3.new(1,1,1),14)
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
-- BlackHole: VISUAL ONLY. Teleport to Space Realm wired later. Do not add Touched/Teleport logic yet.
-- A purely decorative low-poly black hole landmark high above Pizza Palms (Island 14). It does NOT
-- teleport, NOT trigger anything, NOT collide, NOT touch, NOT affect gas/coins/flight. It only looks
-- cool + spins. Built HERE in WorldClient (which is already mapped + reliably runs and already knows
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

	return model
end

-- Navigation GUI
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end

local navSg=Instance.new("ScreenGui"); navSg.Name="NavGui"; navSg.ResetOnSpawn=false; navSg.Parent=player.PlayerGui
local navFrame=mkFrame(navSg,{Size=UDim2.new(0,44,0,44),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(255,200,0),BackgroundTransparency=0.2,Visible=false}); mkCorner(navFrame,22); mkStroke(navFrame,Color3.fromRGB(200,140,0),2)
local navArrow=mkLabel(navFrame,{Text="\xe2\x86\x91",Font=Enum.Font.GothamBold,TextSize=26,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,1,0),TextXAlignment=Enum.TextXAlignment.Center}); mkStroke(navArrow,Color3.new(0,0,0),1.5)
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
		print(string.format("[BlackHole] placed at (%.0f, %.0f, %.0f) above Pizza Palms - VISUAL ONLY, non-functional [baseY=%.0f + offset=%d]",
			bhCenter.X, bhCenter.Y, bhCenter.Z, pizzaPos.Y, BH_HEIGHT_OFFSET))
	else
		warn("[BlackHole] BUILD ERROR (no model created): " .. tostring(errBH))
	end
	print("WORLD OBJECTS SPAWNED")
end)

-- OWNER overhead tags: these 3 usernames (lando5485 also matched by UserId for safety) show a single
-- green "Owner" tag instead of the normal island/name billboard. Every OTHER player is unchanged.
local OWNER_NAMES = { ["Broskie310111"] = true, ["itsmaddmax2"] = true, ["lando5485"] = true }
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
			-- polls every 0.1s, so the label flips from "???" to the real name live the moment their
			-- HighestIsland increases — no respawn or rejoin needed.
			local highest = player:GetAttribute("HighestIsland") or 0
			if nextIsland <= highest then
				-- Visited (island number <= highest reached): show the real island name.
				navName.Text=_G.ISLAND_DISPLAY_NAMES[nextIsland] or ("Island "..nextIsland)
			else
				-- Not yet visited (island number > highest reached): hide the name.
				navName.Text="???"
			end
			navName.Visible=true
		end)
	end
end)

print("WORLDCLIENT READY")
