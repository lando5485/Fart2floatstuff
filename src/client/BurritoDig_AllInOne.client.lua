--======================================================================
-- BurritoDig_AllInOne.client.lua  (LocalScript)
--======================================================================
-- EXACTLY how Burrito Barrens (island 13) does its DIGGING quest + animation,
-- lifted VERBATIM from buildBurritoWorld (PetFollow.client.lua). Self-contained:
-- it lays the props out in front of you at runtime and runs the whole hunt.
--
-- THE QUEST (a ~3-minute hunt):
--   1. GRAB a shovel from the wooden barrel (E, 0.3s hold) -> a low-poly shovel
--      rides on your right hand, blade pointed down-forward.
--   2. DIG the mounds, ONE AT A TIME (the "Armadillo Trail"). Each E-tap = one
--      SWING: the mound SHRINKS a step (ScaleTo), bursts dirt, plays a dig sound,
--      and kicks the camera. 6 swings fully digs a mound.
--   3. A fully-dug DECOY reveals JUNK that RISES out of the hole + lays ARMADILLO
--      TRACKS toward the NEXT mound (which then appears). 5 decoys, then...
--   4. The final BuriedEggSpot reveals the real ARMADILLO EGG, which RISES up out
--      of the hole -> "Hatch" prompt -> hatch.
--
-- SERVER GATE (anti-cheat, noted at the bottom): digging the REAL spot fires
-- PetDigEvent so the server unlocks the claim -- the client can't fake the catch.
--
-- Drop into StarterPlayer > StarterPlayerScripts. (PetDigEvent is fired only if
-- the remote exists, so it runs standalone.)
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TS         = game:GetService("TweenService")
local RS         = game:GetService("ReplicatedStorage")
local Debris     = game:GetService("Debris")

local player = Players.LocalPlayer
local petId  = "BurritoArmadillo"
local def    = {}
local PetDigEvent = RS:FindFirstChild("PetDigEvent") -- c->s: dug the REAL spot -> server unlocks the claim (optional here)

-- ===== generic helpers (from PetFollow.client.lua) =====
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape
	p.Size = size; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end
local function addPrompt(rootPart, actionText, objectText, onTriggered)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = actionText; pp.ObjectText = objectText
	pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0
	pp.MaxActivationDistance = 12; pp.RequiresLineOfSight = false
	pp.Parent = rootPart
	pp.Triggered:Connect(onTriggered)
	return pp
end
local function floatText(pos, text)
	local a = Instance.new("Part"); a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.Transparency=1; a.Size=Vector3.new(1,1,1); a.CFrame=CFrame.new(pos); a.Parent=Workspace
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,200,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.Parent=a
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=22; lbl.TextColor3=Color3.fromRGB(235,205,150); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	TS:Create(a, TweenInfo.new(1.4), {Transparency=1}):Play()
	TS:Create(lbl, TweenInfo.new(1.4), {TextTransparency=1}):Play()
	task.delay(1.5, function() a:Destroy() end)
end
local function setVisible(model, on) if model then model.Parent = on and Workspace or nil end end

-- ===== single-pet state (the real game keys this per pet) =====
local st = { built=false, owns=false, hatching=false, hasShovel=false, eggCaught=false, digProps={} }
-- minimal quest-progress HUD stub (the game shows "Mounds X/6"); here it just prints
local localQuestProg = { [petId] = { found = 0 } }
local function pushQuestProg(id, fields) local lp = localQuestProg[id] or {}; for k,v in pairs(fields) do lp[k]=v end; localQuestProg[id]=lp
	if fields.found then print("[Dig][HUD] Mounds "..fields.found.."/"..(fields.total or 6)) end
	if fields.complete then print("[Dig][HUD] armadillo quest COMPLETE") end
end

-- ===== minimal HATCH (the real game shares hatchEgg: shake -> crack -> pet pops). Kept short here. =====
local function hatchEgg()
	if st.hatching or st.owns then return end
	st.hatching = true
	print("[Dig] hatching the armadillo egg!")
	local visual = st.eggVisual; local base = st.eggBaseCF
	if visual then
		local t0 = os.clock()
		while os.clock() - t0 < 1.6 do
			local p = (os.clock()-t0)/1.6; local amp = 0.1 + p*p*0.9
			pcall(function() visual:PivotTo(base * CFrame.new((math.random()-0.5)*amp, 0, (math.random()-0.5)*amp) * CFrame.Angles(0, math.rad((math.random()-0.5)*60), 0)) end)
			task.wait()
		end
		pcall(function() visual:Destroy() end)
	end
	floatText((st.eggPos or Vector3.zero) + Vector3.new(0,3,0), "Burrito Armadillo hatched! \xF0\x9F\xA6\xAB")
	st.owns = true; st.hatching = false
	task.delay(1.5, function() if st.egg then pcall(function() st.egg:Destroy() end) end end)
end

-- ============================================================================
-- THE DIG WORLD (VERBATIM from buildBurritoWorld). `positions` carries the marker
-- coords; the real game gets them from the server, here we lay them out in front
-- of the player.
-- ============================================================================
local function buildBurritoWorld(positions)
	if st.built then return end
	st.built = true; st.isDigging = true
	local extra = positions.extra or {}
	local shovelPos = extra.shovel
	local buriedPos = extra.buriedegg
	-- ARMADILLO TRAIL order: DigSpot1 -> 2 -> 3 -> 4 -> 5 -> BuriedEggSpot (one mound active at a time)
	local digSpots = {
		{ key="dig1", pos=extra.dig1, real=false, label="DigSpot1" },
		{ key="dig2", pos=extra.dig2, real=false, label="DigSpot2" },
		{ key="dig3", pos=extra.dig3, real=false, label="DigSpot3" },
		{ key="dig4", pos=extra.dig4, real=false, label="DigSpot4" },
		{ key="dig5", pos=extra.dig5, real=false, label="DigSpot5" },
		{ key="buriedegg", pos=buriedPos, real=true, label="BuriedEggSpot" },
	}
	st.digProps = {}

	local pgui = player:WaitForChild("PlayerGui")
	-- ===== HUD: a status pill for dig-result messages =====
	local hud = Instance.new("ScreenGui"); hud.Name = "BurritoDigHUD"; hud.ResetOnSpawn = false; hud.DisplayOrder = 88; hud.Parent = pgui
	local status = Instance.new("Frame"); status.AnchorPoint = Vector2.new(0.5,0); status.Position = UDim2.new(0.5,0,0.12,0); status.Size = UDim2.new(0,470,0,40)
	status.BackgroundColor3 = Color3.fromRGB(150,96,40); status.BackgroundTransparency = 0.12; status.BorderSizePixel = 0; status.Visible = false; status.Parent = hud
	Instance.new("UICorner", status).CornerRadius = UDim.new(0,10); local sstk = Instance.new("UIStroke", status); sstk.Color = Color3.fromRGB(255,225,150); sstk.Thickness = 2
	local statusText = Instance.new("TextLabel"); statusText.Size = UDim2.new(1,0,1,0); statusText.BackgroundTransparency = 1
	statusText.Font = Enum.Font.GothamBold; statusText.TextSize = 20; statusText.TextColor3 = Color3.new(1,1,1); statusText.Text = ""; statusText.Parent = status
	local function setStatus(t) statusText.Text = t; status.Visible = true end
	local function hideStatus() status.Visible = false end
	-- desert junk items (the in-world reveal that RISES out of a decoy hole uses these emoji)
	local DIG_JUNK = { "an old boot", "a cattle skull", "a rusty can", "a prickly cactus", "a horseshoe", "a coyote bone", "a tumbleweed" }
	local DIG_JUNK_EMOJI = { ["an old boot"]="\xF0\x9F\xA5\xBE", ["a cattle skull"]="\xF0\x9F\x92\x80", ["a rusty can"]="\xF0\x9F\xA5\xAB", ["a prickly cactus"]="\xF0\x9F\x8C\xB5", ["a horseshoe"]="\xF0\x9F\xA7\xB2", ["a coyote bone"]="\xF0\x9F\xA6\xB4", ["a tumbleweed"]="\xF0\x9F\x8C\xBE" }

	-- ===== SHARED LOW-POLY SHOVEL + BARREL STYLE =====
	local SH_WOOD   = Color3.fromRGB(124,82,44)
	local SH_WOOD_D = Color3.fromRGB(94,60,30)
	local SH_HOOP   = Color3.fromRGB(96,98,108)
	local SH_BLADE  = Color3.fromRGB(150,154,164)
	local SH_LEN    = 4.4
	-- Build a low-poly SHOVEL in LOCAL space: PrimaryPart (Root) at the GRIP; local +X runs DOWN the shaft to the BLADE.
	local function buildShovel()
		local m = Instance.new("Model"); m.Name = petId.."Shovel"
		local function rp(name, shape, size, color, cf, mat)
			local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
			p.Material = mat or Enum.Material.SmoothPlastic; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false; p.Parent = m
			p.CFrame = cf; return p
		end
		local root = rp("Root", Enum.PartType.Ball, Vector3.new(0.2,0.2,0.2), SH_WOOD, CFrame.new()); root.Transparency = 1; m.PrimaryPart = root
		rp("Handle", Enum.PartType.Cylinder, Vector3.new(SH_LEN,0.26,0.26), SH_WOOD, CFrame.new(SH_LEN/2,0,0), Enum.Material.Wood)        -- shaft along +X
		rp("Grip",   Enum.PartType.Cylinder, Vector3.new(1.3,0.24,0.24), SH_WOOD, CFrame.new(-0.1,0,0) * CFrame.Angles(0,math.rad(90),0), Enum.Material.Wood) -- T grip cross-bar
		rp("Socket", Enum.PartType.Cylinder, Vector3.new(0.6,0.34,0.34), SH_BLADE, CFrame.new(SH_LEN+0.1,0,0), Enum.Material.Metal)        -- shaft->blade collar
		rp("Blade",  Enum.PartType.Block,    Vector3.new(0.45,1.4,1.2), SH_BLADE, CFrame.new(SH_LEN+0.85,0,0), Enum.Material.Metal)        -- flat metal scoop
		m.Parent = Workspace
		return m
	end
	-- align a model's local +X (shaft) to a world direction `d`, with the grip (pivot) at `gripPos`
	local function shovelCF(gripPos, d) return CFrame.lookAt(gripPos, gripPos + d) * CFrame.Angles(0, math.rad(90), 0) end

	-- ===== HELD SHOVEL (rides on the player's hand once grabbed) =====
	local heldShovel
	local function startHeldShovel()
		if heldShovel then return end
		heldShovel = buildShovel(); heldShovel.Name = petId.."HeldShovel"; st.digProps[#st.digProps+1] = heldShovel
		task.spawn(function()
			while heldShovel and heldShovel.Parent and not st.owns do
				local char = player.Character
				local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hand and hrp then
					local look = hrp.CFrame.LookVector; look = Vector3.new(look.X,0,look.Z)
					if look.Magnitude < 0.1 then look = Vector3.new(0,0,-1) end
					-- shaft points FORWARD + DOWN so the BLADE is toward the ground in front; grip sits at the hand.
					local dirShaft = (look.Unit + Vector3.new(0,-0.5,0)).Unit
					local gripPos = hand.Position + Vector3.new(0,-0.1,0) - dirShaft*0.4
					heldShovel:PivotTo(shovelCF(gripPos, dirShaft))
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end

	-- ===== SHOVEL BARREL + "Grab Shovel" prompt =====
	if typeof(shovelPos) == "Vector3" then
		local stand = Instance.new("Model"); stand.Name = petId.."ShovelStand"
		local cyc = function(y) return CFrame.new(shovelPos + Vector3.new(0,y,0)) * CFrame.Angles(0,0,math.rad(90)) end
		local body = newPart(stand, "Barrel", Enum.PartType.Cylinder, Vector3.new(3.4,2.4,2.4), SH_WOOD, cyc(1.7), Enum.Material.Wood)
		stand.PrimaryPart = body
		newPart(stand, "Bulge", Enum.PartType.Cylinder, Vector3.new(1.5,2.85,2.85), SH_WOOD, cyc(1.7), Enum.Material.Wood)
		newPart(stand, "RimBot", Enum.PartType.Cylinder, Vector3.new(0.5,2.55,2.55), SH_WOOD_D, cyc(0.45), Enum.Material.Wood)
		newPart(stand, "RimTop", Enum.PartType.Cylinder, Vector3.new(0.5,2.55,2.55), SH_WOOD_D, cyc(2.95), Enum.Material.Wood)
		newPart(stand, "Inside", Enum.PartType.Cylinder, Vector3.new(0.4,2.0,2.0), Color3.fromRGB(46,30,16), cyc(3.05), Enum.Material.Wood)
		for _, oy in ipairs({1.0, 2.4}) do newPart(stand, "Hoop", Enum.PartType.Cylinder, Vector3.new(0.32,2.75,2.75), SH_HOOP, cyc(oy), Enum.Material.Metal) end
		stand.Parent = Workspace; st.digProps[#st.digProps+1] = stand
		-- SHOVELS sticking up out of the barrel (grip + handle poke UP/out, blade down inside)
		for i = 1, 3 do
			local ang = (i - 2) * 0.7
			local outward = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local gripPos = shovelPos + Vector3.new(0, 4.8, 0) + outward * 1.1
			local dirShaft = (Vector3.new(0,-1.6,0) - outward * 0.55).Unit
			local sv = buildShovel(); sv:PivotTo(shovelCF(gripPos, dirShaft)); st.digProps[#st.digProps+1] = sv
		end
		local grab = addPrompt(body, "Grab Shovel", "Shovel Stand", function()
			if st.owns then return end
			if not st.hasShovel then
				st.hasShovel = true
				startHeldShovel()
				floatText(shovelPos + Vector3.new(0,4,0), "Got a shovel! Now find + dig the mounds. \xE2\x9B\x8F")
				print("[Pet] "..player.Name.." grabbed shovel (can dig the mounds now)")
			else
				floatText(shovelPos + Vector3.new(0,4,0), "You already have a shovel!")
			end
		end)
		grab.HoldDuration = 0.3
	end

	local N_SWINGS = 6 -- E-taps ("swings") to fully dig a mound away
	-- a dug-up JUNK item RISES out of the decoy hole (in-world reveal), holds, then fades
	local function junkRise(pos, junkName)
		local j = newPart(Workspace, petId.."DugJunk", Enum.PartType.Ball, Vector3.new(1.3,1.3,1.3), Color3.fromRGB(120,92,60), CFrame.new(pos + Vector3.new(0, -3.0, 0)), Enum.Material.SmoothPlastic)
		st.digProps[#st.digProps+1] = j
		local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,64,0,64); bb.StudsOffset = Vector3.new(0,2.0,0); bb.AlwaysOnTop = true; bb.Adornee = j; bb.Parent = j
		local lb = Instance.new("TextLabel"); lb.Size = UDim2.new(1,0,1,0); lb.BackgroundTransparency = 1; lb.Font = Enum.Font.GothamBold; lb.TextSize = 50; lb.Text = DIG_JUNK_EMOJI[junkName] or "\xF0\x9F\xA6\xB4"; lb.Parent = bb
		TS:Create(j, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = CFrame.new(pos + Vector3.new(0, 1.3, 0)) }):Play()
		task.delay(2.4, function()
			pcall(function() lb.TextTransparency = 1 end)
			TS:Create(j, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			task.delay(0.6, function() pcall(function() j:Destroy() end) end)
		end)
	end

	-- ===== the ARMADILLO EGG RISES UP out of the real hole -> Hatch prompt =====
	local function spawnArmadilloEgg(atPos)
		if st.egg then return end
		st.eggPos = atPos; st.eggCaught = true
		local egg = Instance.new("Model"); egg.Name = petId.."Egg"
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(224,194,148), nil)
		shell.Reflectance = 0.05
		local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Scale = Vector3.new(3.0,4.0,3.0); m.Parent = shell
		visual.PrimaryPart = shell
		for j = 1, 6 do local a = (j-1)*(2*math.pi/6); newPart(visual, "Speck", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.fromRGB(176,118,64), CFrame.new(math.sin(a)*1.2, (j%2==0 and 0.5 or -0.5), math.cos(a)*1.2)) end
		local eggCenter = atPos + Vector3.new(0, 1.7, 0)
		st.eggBaseCF = CFrame.new(eggCenter); st.eggVisual = visual
		local startCF = CFrame.new(atPos + Vector3.new(0, -3.4, 0)) -- start DOWN inside the dug hole...
		st.eggRising = true; visual:PivotTo(startCF)
		st.egg = egg; egg.Parent = Workspace; st.digProps[#st.digProps+1] = egg
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(235,205,150); hl.FillTransparency = 0.5; hl.OutlineColor = Color3.fromRGB(210,168,90); hl.Adornee = visual; hl.Parent = egg
		local hp = addPrompt(shell, "Hatch", "Armadillo Egg", function()
			if st.owns or st.hatching then return end
			hatchEgg()
		end)
		hp.Enabled = false -- can't hatch until it has fully risen out of the ground
		-- RISE: tween the egg UP out of the hole (a CFrame lerp via a NumberValue, since Models can't tween directly)
		task.spawn(function()
			local nv = Instance.new("NumberValue"); nv.Value = 0
			nv:GetPropertyChangedSignal("Value"):Connect(function() local t = nv.Value; pcall(function() visual:PivotTo(startCF:Lerp(st.eggBaseCF, t)) end) end)
			TS:Create(nv, TweenInfo.new(1.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 }):Play()
			task.wait(1.2); st.eggRising = false; pcall(function() nv:Destroy() end); hp.Enabled = true
		end)
		-- gentle bob (only AFTER it has risen + while not hatching)
		task.spawn(function() local t = 0
			while st.egg do t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching and not st.eggRising then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.28, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end)
				end
				task.wait(0.05)
			end
		end)
		print("[Pet] armadillo egg rose out of the ground for "..player.Name)
	end

	-- ===== ARMADILLO TRAIL: low-poly dirt mounds dug ONE AT A TIME =====
	local DIRT, DIRT2 = Color3.fromRGB(150,110,70), Color3.fromRGB(134,96,58)
	-- a LOW-POLY DIRT PILE: stacked, rotated square blocks tapering up into a faceted pile. Digging shrinks the model.
	local function buildMound(pos)
		local m = Instance.new("Model"); m.Name = petId.."DigMound"
		local base
		for i, L in ipairs({
			{ w=5.4, h=1.3, y=0.65, yaw=0,  col=DIRT  },
			{ w=4.0, h=1.3, y=1.75, yaw=45, col=DIRT2 },
			{ w=2.7, h=1.2, y=2.75, yaw=20, col=DIRT  },
			{ w=1.5, h=1.1, y=3.6,  yaw=58, col=DIRT2 },
		}) do
			local p = newPart(m, "MoundLayer", Enum.PartType.Block, Vector3.new(L.w, L.h, L.w), L.col, CFrame.new(pos + Vector3.new(0, L.y, 0)) * CFrame.Angles(0, math.rad(L.yaw), 0), Enum.Material.Sand)
			if i == 1 then base = p end
		end
		m.PrimaryPart = base
		m.Parent = Workspace
		return m
	end
	-- ARMADILLO TRACKS: a line of footprint marks (flat oval + 3 toe dots) leading MOST of the way to the next mound.
	local function spawnTracks(fromPos, toPos)
		if typeof(fromPos) ~= "Vector3" or typeof(toPos) ~= "Vector3" then return end
		local flat = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
		local dist = flat.Magnitude; if dist < 3 then return end
		local dir = flat.Unit
		local right = Vector3.new(-dir.Z, 0, dir.X)
		local n = math.clamp(math.floor(dist / 7), 4, 16)
		for k = 1, n do
			local frac = (k / (n + 1)) * 0.85 + 0.05
			local p = fromPos + dir * (dist * frac)
			local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { player.Character }; rp.IgnoreWater = true
			local hit = Workspace:Raycast(p + Vector3.new(0,14,0), Vector3.new(0,-90,0), rp)
			local y = hit and hit.Position.Y or p.Y
			local side = (k % 2 == 0) and 1 or -1
			local fp = Vector3.new(p.X, y + 0.08, p.Z) + right * (side * 0.7)
			local cf = CFrame.lookAt(fp, fp + dir)
			local foot = newPart(Workspace, petId.."Track", Enum.PartType.Ball, Vector3.new(0.95,0.12,1.35), Color3.fromRGB(96,62,34), cf)
			foot.Transparency = 1; st.digProps[#st.digProps+1] = foot
			for _, tx in ipairs({ -0.3, 0, 0.3 }) do
				local toe = newPart(Workspace, petId.."Track", Enum.PartType.Ball, Vector3.new(0.26,0.1,0.26), Color3.fromRGB(80,52,28), cf * CFrame.new(tx, 0, -0.72))
				toe.Transparency = 1; st.digProps[#st.digProps+1] = toe
			end
			TS:Create(foot, TweenInfo.new(0.3), { Transparency = 0.1 }):Play()
		end
	end

	local spots = {}   -- [i] = { spot, mound, prompt } (or false if the marker position is missing)
	local activateStep -- forward-decl (doSwing advances the trail via this)

	for i, spot in ipairs(digSpots) do
		if typeof(spot.pos) ~= "Vector3" then
			spots[i] = false
		else
			local mound = buildMound(spot.pos); setVisible(mound, false) -- built hidden; shown when active
			st.digProps[#st.digProps+1] = mound
			-- the "Dig" prompt rides on its OWN persistent anchor, so shrinking the mound never removes it -> re-arms each E.
			local promptAnchor = newPart(Workspace, petId.."DigPrompt", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.new(1,1,1), CFrame.new(spot.pos + Vector3.new(0,1.5,0)))
			promptAnchor.Transparency = 1; st.digProps[#st.digProps+1] = promptAnchor
			local swings, fxAnchor, em, snd, done = 0, nil, nil, nil, false
			local prompt -- forward-decl so doSwing can disable it on the final swing
			local function doSwing()
				if not fxAnchor then
					fxAnchor = newPart(Workspace, petId.."DigFX", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(120,84,52), CFrame.new(spot.pos + Vector3.new(0,0.6,0)))
					fxAnchor.Transparency = 1
					em = Instance.new("ParticleEmitter"); em.Texture = "rbxasset://textures/particles/smoke_main.dds"
					em.Color = ColorSequence.new(Color3.fromRGB(150,110,70), Color3.fromRGB(110,78,46)); em.Lifetime = NumberRange.new(0.4,0.85)
					em.Speed = NumberRange.new(10,18); em.SpreadAngle = Vector2.new(40,40); em.EmissionDirection = Enum.NormalId.Top
					em.Acceleration = Vector3.new(0,-44,0); em.Size = NumberSequence.new(0.9); em.Rate = 0; em.Rotation = NumberRange.new(0,360); em.Parent = fxAnchor
					snd = Instance.new("Sound"); snd.SoundId = "rbxassetid://9114065998"; snd.Volume = 0.55; snd.Parent = fxAnchor -- PLACEHOLDER dirt/shovel dig sound -- swap freely
				end
				swings = swings + 1
				pcall(function() mound:ScaleTo(math.max(0.06, 1 - swings / N_SWINGS)) end) -- SHRINK the low-poly mound away one step
				pcall(function() em:Emit(20) end)                              -- DIRT burst this swing
				pcall(function() snd.TimePosition = 0; snd:Play() end)         -- dig SOUND this swing
				pcall(function()                                               -- small camera kick for feel
					local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if hum then hum.CameraOffset = Vector3.new((math.random()-0.5)*0.5, -0.35, 0); TS:Create(hum, TweenInfo.new(0.18), {CameraOffset = Vector3.zero}):Play() end
				end)
				print(string.format("[Pet][DIG] swing %d/%d on %s", swings, N_SWINGS, spot.label))
				if swings >= N_SWINGS then -- mound fully dug -> reveal + advance the trail
					done = true; prompt.Enabled = false
					pushQuestProg(petId, { started = true, found = ((localQuestProg[petId] and localQuestProg[petId].found) or 0) + 1, total = #digSpots }) -- HUD: "Mounds X/6"
					pcall(function() setVisible(mound, false) end)
					if em then task.delay(0.4, function() em.Enabled = false end) end
					if fxAnchor then Debris:AddItem(fxAnchor, 1.2) end
					if spot.real then
						print("[Pet][DIG] BuriedEggSpot dug -> EGG rises")
						if PetDigEvent then pcall(function() PetDigEvent:FireServer(petId) end) end -- server unlocks the claim (anti-cheat gate)
						pushQuestProg(petId, { complete = true })
						setStatus("You unearthed the armadillo egg! \xF0\x9F\xA5\x9A"); task.delay(2.6, hideStatus)
						spawnArmadilloEgg(spot.pos)
					else
						local junk = DIG_JUNK[math.random(1, #DIG_JUNK)]
						junkRise(spot.pos, junk)
						local nextSpot = digSpots[i+1]
						local nextPos = nextSpot and nextSpot.pos
						if nextPos then spawnTracks(spot.pos, nextPos) end
						setStatus("You dug up: "..junk.."! Follow the tracks..."); task.delay(2.6, hideStatus)
						task.delay(0.4, function() activateStep(i + 1) end)
					end
				end
			end
			prompt = addPrompt(promptAnchor, "Dig", "Dig Spot", function() -- each E-tap = ONE swing (HoldDuration 0)
				if st.owns or st.eggCaught or done then return end
				if not st.hasShovel then floatText(spot.pos + Vector3.new(0,3,0), "Grab a shovel first!"); return end
				doSwing()
			end)
			prompt.HoldDuration = 0; prompt.MaxActivationDistance = 12; prompt.Enabled = false -- enabled by activateStep when active
			spots[i] = { spot = spot, mound = mound, prompt = prompt }
		end
	end

	-- show + enable the active step's mound (one at a time); skip any step whose marker is missing
	activateStep = function(n)
		if n > #digSpots then return end
		local e = spots[n]
		if not e then return activateStep(n + 1) end
		setVisible(e.mound, true)
		if not st.owns and not st.eggCaught then e.prompt.Enabled = true end
		print(string.format("[Pet][DIG] active mound: %s (trail step %d/%d)", e.spot.label, n, #digSpots))
	end
	if not st.owns then activateStep(1) end -- start the Armadillo Trail at the first mound
end

-- ============================================================================
-- LAYOUT: drop the shovel barrel + a wandering 6-stop trail in front of the
-- player (the real game gets these positions from the server's island markers).
-- ============================================================================
local function makePositions()
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	local base = hrp and hrp.Position or Vector3.new(0, 5, 0)
	-- ground the trail with a downward ray so mounds sit on the floor
	local function ground(p)
		local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { char }
		local hit = Workspace:Raycast(p + Vector3.new(0,20,0), Vector3.new(0,-200,0), rp)
		return hit and Vector3.new(p.X, hit.Position.Y, p.Z) or p
	end
	local fwd = hrp and Vector3.new(hrp.CFrame.LookVector.X,0,hrp.CFrame.LookVector.Z).Unit or Vector3.new(0,0,-1)
	local right = Vector3.new(-fwd.Z, 0, fwd.X)
	local function at(f, s) return ground(base + fwd*f + right*s) end
	return { extra = {
		shovel    = at(8,  -6),
		dig1      = at(16,  4),
		dig2      = at(28, -8),
		dig3      = at(40,  10),
		dig4      = at(54, -4),
		dig5      = at(66,  8),
		buriedegg = at(80, -2),
	} }
end

buildBurritoWorld(makePositions())
floatText((player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or Vector3.new(0,5,0)) + Vector3.new(0,4,0), "Grab a shovel + follow the armadillo trail! \xE2\x9B\x8F")
print("[BurritoDig] dig quest ready -- grab the shovel, then dig the mounds (E to swing)")

-- ============================================================================
-- SERVER GATE (for reference -- in PetSystem.server.lua):
--   PetDigEvent.OnServerEvent: digEggReady[player] = true  (set when the REAL spot is dug)
--   PetClaimEvent: rejects the BurritoArmadillo claim unless digEggReady[player] is set,
--   so a client can never fake unearthing the egg. digEggReady is session-only (re-dig on rejoin).
-- ============================================================================
