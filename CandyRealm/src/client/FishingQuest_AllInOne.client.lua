--======================================================================
-- FishingQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of how BUTTER SWAMP (the Butter Duck fishing quest)
-- works, lifted VERBATIM from buildButterWorld + the reel minigame in
-- PetFollow.client.lua, ready to drop onto ANY fishing island.
--
-- THE FLOW (exactly like Butter Swamp):
--   1. Grab a fishing ROD from the rod barrel (E) -> a rod rides your hand.
--   2. Stand at the WATER'S EDGE (a downward-ray probe detects exposed water
--      around you, so you fish from the shore on land).
--   3. Press the "[E] Fish" prompt (it follows you, only enabled at the edge).
--   4. CAST -> a red/white bobber arcs out onto the water with a line beam.
--   5. BITE -> the bobber dips + "!" -> TAP TO HOOK within ~1.3s.
--   6. REEL-IN -> the Fisch-style hold/release tension minigame (fill the bar).
--   7. The catch is ROLLED (pity-ramped egg chance + funny junk for misses).
--      An egg -> appears IN FRONT of you -> Hatch. Junk -> a popup, recast.
--
-- CONFIG below: set `lakeName` to the Name of your water Part/Model and either
-- name a barrel-spot Part or give a Vector3. The catch roll runs client-side
-- here; in the real game it's SERVER-AUTHORITATIVE (PetFishRoll) -- if that
-- remote exists this file uses it automatically. Drop into StarterPlayer >
-- StarterPlayerScripts.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TS         = game:GetService("TweenService")
local UIS        = game:GetService("UserInputService")
local RS         = game:GetService("ReplicatedStorage")
local player     = Players.LocalPlayer
local prefix     = "Fish"

-- ============================================================================
-- CONFIG -- point this at your island's water + barrel spot.
-- ============================================================================
local CONFIG = {
	lakeName       = "ButterLake",     -- the Name of the water Part/Model you fish IN (rays test for this name)
	barrelSpotName = "RodBarrelSpot",  -- a Part marking where the rod barrel stands (optional)
	barrelPosFallback = nil,           -- or hardcode a Vector3 here if you don't place a spot part
	eggShell  = Color3.fromRGB(250,224,120), -- egg color (butter-yellow by default)
	eggDrip   = Color3.fromRGB(255,236,150),
	petName   = "Swamp Pet",
}
-- pity-ramped catch roll + the junk pool (verbatim from the server's PetFishRoll).
local FISH_JUNK = { "an old boot", "a butter blob", "a rubber duck", "a soggy sock", "a rusty tin can",
                    "a clump of swamp weed", "a lost flip-flop", "a message in a bottle" }
local PetFishRoll = RS:FindFirstChild("PetFishRollEvent") -- if the real server remote exists, use it (server-authoritative)
local fishCatches = 0
local function rollCatch()
	if PetFishRoll then local ok, res = pcall(function() return PetFishRoll:InvokeServer() end); if ok then return res end end
	-- client fallback (standalone): egg chance 25% ramping +11%/catch, GUARANTEED by catch 8
	fishCatches = fishCatches + 1
	local n = fishCatches
	local eggChance = math.min(1, 0.25 + (n - 1) * 0.11)
	if (n >= 8) or (math.random() < eggChance) then return { egg = true, catch = n }
	else return { egg = false, junk = FISH_JUNK[math.random(1, #FISH_JUNK)], catch = n } end
end

-- ============================================================================
-- GENERIC HELPERS (from PetFollow.client.lua)
-- ============================================================================
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
	pp.Parent = rootPart; pp.Triggered:Connect(onTriggered)
	return pp
end
local function floatText(pos, text)
	local a = Instance.new("Part"); a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.Transparency=1; a.Size=Vector3.new(1,1,1); a.CFrame=CFrame.new(pos); a.Parent=Workspace
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,200,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.Parent=a
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=22; lbl.TextColor3=Color3.fromRGB(255,235,140); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	TS:Create(a, TweenInfo.new(1.4), {Transparency=1}):Play(); TS:Create(lbl, TweenInfo.new(1.4), {TextTransparency=1}):Play()
	task.delay(1.5, function() a:Destroy() end)
end
local function setVisible(model, on) if model then model.Parent = on and Workspace or nil end end

local st = { built=false, owns=false, hatching=false, hasRod=false, eggCaught=false, fishProps={} }
local function pushQuestProg(_, fields) if fields.found then print("[Fish][HUD] reeled in: "..fields.found) end; if fields.complete then print("[Fish][HUD] quest complete") end end
local localQuestProg = { [prefix] = { found = 0 } }

-- minimal HATCH stub (the real game shares hatchEgg: shake -> crack -> pet pops + claim)
local function hatchEgg()
	if st.hatching or st.owns then return end
	st.hatching = true
	local v = st.eggVisual; local base = st.eggBaseCF
	if v then local t0 = os.clock()
		while os.clock()-t0 < 1.4 do local p=(os.clock()-t0)/1.4; local amp=0.1+p*p*0.9
			pcall(function() v:PivotTo(base * CFrame.new((math.random()-0.5)*amp,0,(math.random()-0.5)*amp) * CFrame.Angles(0, math.rad((math.random()-0.5)*60), 0)) end); task.wait() end
		pcall(function() v:Destroy() end)
	end
	floatText((st.eggPos or Vector3.zero)+Vector3.new(0,3,0), CONFIG.petName.." hatched! \xF0\x9F\xA6\x86")
	st.owns = true; st.hatching = false
	task.delay(1.5, function() if st.egg then pcall(function() st.egg:Destroy() end) end end)
end

-- ============================================================================
-- REEL-IN MINIGAME (Fisch-style hold/release) -- VERBATIM
-- ============================================================================
local reelUI, reelBusy = nil, false
local function ensureReelUI()
	if reelUI then return reelUI end
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "FishReelGui"; g.ResetOnSpawn = false; g.DisplayOrder = 90; g.Enabled = false; g.Parent = pgui
	local dim = Instance.new("Frame"); dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0); dim.BackgroundTransparency = 0.5; dim.Active = true; dim.Parent = g
	local panel = Instance.new("Frame"); panel.Size = UDim2.new(0,300,0,360); panel.Position = UDim2.new(0.5,0,0.5,0); panel.AnchorPoint = Vector2.new(0.5,0.5)
	panel.BackgroundColor3 = Color3.fromRGB(25,90,185); panel.Parent = g
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16); local ps = Instance.new("UIStroke", panel); ps.Color = Color3.new(1,1,1); ps.Thickness = 3
	local titl = Instance.new("TextLabel"); titl.Size = UDim2.new(1,-20,0,30); titl.Position = UDim2.new(0,10,0,10); titl.BackgroundTransparency = 1
	titl.Font = Enum.Font.GothamBold; titl.TextSize = 22; titl.TextColor3 = Color3.fromRGB(255,215,0); titl.Text = "REEL IT IN!"; titl.Parent = panel
	local track = Instance.new("Frame"); track.Size = UDim2.new(0,90,0,250); track.Position = UDim2.new(0,40,0,90)
	track.BackgroundColor3 = Color3.fromRGB(12,34,76); track.Parent = panel; Instance.new("UICorner", track).CornerRadius = UDim.new(0,12)
	local tstk = Instance.new("UIStroke", track); tstk.Color = Color3.new(1,1,1); tstk.Transparency = 0.55; tstk.Thickness = 2
	local zone = Instance.new("Frame"); zone.Size = UDim2.new(1,-10,0.30,0); zone.Position = UDim2.new(0.5,0,0.5,0); zone.AnchorPoint = Vector2.new(0.5,0.5)
	zone.BackgroundColor3 = Color3.fromRGB(70,210,90); zone.BackgroundTransparency = 0.2; zone.BorderSizePixel = 0; zone.Parent = track; Instance.new("UICorner", zone).CornerRadius = UDim.new(0,8)
	local zstk = Instance.new("UIStroke", zone); zstk.Color = Color3.fromRGB(225,255,225); zstk.Thickness = 2
	local fish = Instance.new("TextLabel"); fish.Size = UDim2.new(0,46,0,46); fish.AnchorPoint = Vector2.new(0.5,0.5); fish.Position = UDim2.new(0.5,0,0.5,0)
	fish.BackgroundTransparency = 1; fish.Font = Enum.Font.GothamBold; fish.TextSize = 34; fish.Text = "\xF0\x9F\x90\x9F"; fish.ZIndex = 4; fish.Parent = track
	local pbBg = Instance.new("Frame"); pbBg.Size = UDim2.new(0,40,0,250); pbBg.Position = UDim2.new(1,-70,0,90)
	pbBg.BackgroundColor3 = Color3.fromRGB(15,40,90); pbBg.Parent = panel; Instance.new("UICorner", pbBg).CornerRadius = UDim.new(0,10)
	local pb = Instance.new("Frame"); pb.Size = UDim2.new(1,0,0.45,0); pb.Position = UDim2.new(0,0,1,0); pb.AnchorPoint = Vector2.new(0,1)
	pb.BackgroundColor3 = Color3.fromRGB(255,205,60); pb.BorderSizePixel = 0; pb.Parent = pbBg; Instance.new("UICorner", pb).CornerRadius = UDim.new(0,10)
	local pbl = Instance.new("TextLabel"); pbl.Size = UDim2.new(0,80,0,16); pbl.AnchorPoint = Vector2.new(0.5,0); pbl.Position = UDim2.new(1,-50,1,-26); pbl.BackgroundTransparency = 1
	pbl.Font = Enum.Font.GothamBold; pbl.TextSize = 12; pbl.TextColor3 = Color3.fromRGB(255,225,120); pbl.Text = "CATCH"; pbl.Parent = panel
	local ready = Instance.new("TextLabel"); ready.AnchorPoint = Vector2.new(0.5,0.5); ready.Position = UDim2.new(0.5,0,0.5,0); ready.Size = UDim2.new(1,-20,0,40)
	ready.BackgroundTransparency = 1; ready.Font = Enum.Font.FredokaOne; ready.TextSize = 28; ready.TextColor3 = Color3.fromRGB(255,240,120); ready.Text = "GET READY..."; ready.ZIndex = 6; ready.Parent = panel
	Instance.new("UIStroke", ready).Thickness = 2
	local hintL = Instance.new("TextLabel"); hintL.Size = UDim2.new(1,-20,0,20); hintL.Position = UDim2.new(0,10,1,-28); hintL.BackgroundTransparency = 1
	hintL.Font = Enum.Font.Gotham; hintL.TextSize = 13; hintL.TextColor3 = Color3.new(1,1,1); hintL.Text = "HOLD to rise \xE2\x80\xA2 RELEASE to drop \xE2\x80\x94 keep \xF0\x9F\x90\x9F in the zone"; hintL.Parent = panel
	reelUI = { gui = g, zone = zone, fish = fish, pb = pb, hint = hintL, ready = ready }
	return reelUI
end
local function openReelMinigame(onDone)
	if reelBusy then if onDone then onDone(false) end return end
	reelBusy = true
	local ui = ensureReelUI()
	local ZONE_H = 0.30
	local zone, zoneVel = 0.45, 0
	local fishF, fishTarget, fishTimer = 0.5, 0.5, 0
	local progress = 0.45
	ui.zone.Size = UDim2.new(1,-10,ZONE_H,0)
	ui.pb.Size = UDim2.new(1,0,progress,0)
	local done, holding = false, false
	local c1, c2
	local function isHold(t) return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch end
	c1 = UIS.InputBegan:Connect(function(i) if isHold(i.UserInputType) then holding = true end end)
	c2 = UIS.InputEnded:Connect(function(i) if isHold(i.UserInputType) then holding = false end end)
	ui.gui.Enabled = true
	local function finish(success)
		if done then return end
		done = true; if c1 then c1:Disconnect() end; if c2 then c2:Disconnect() end
		ui.gui.Enabled = false; reelBusy = false
		if onDone then onDone(success) end
	end
	task.spawn(function()
		local introT = 1.2
		ui.ready.Visible = true
		local last = os.clock()
		while not done do
			local now = os.clock(); local dt = math.min(now - last, 0.05); last = now
			zoneVel = (zoneVel + (holding and 2.4 or -1.15) * dt) * 0.90
			zone = zone + zoneVel * dt
			if zone < ZONE_H/2 then zone = ZONE_H/2; zoneVel = 0 elseif zone > 1 - ZONE_H/2 then zone = 1 - ZONE_H/2; zoneVel = 0 end
			fishTimer = fishTimer - dt
			if fishTimer <= 0 then fishTarget = 0.14 + math.random() * 0.72; fishTimer = 0.6 + math.random() * 1.4 end
			fishF = fishF + (fishTarget - fishF) * math.min(dt * 1.6, 1)
			local inZone = math.abs(fishF - zone) <= (ZONE_H/2)
			if introT > 0 then introT = introT - dt; if introT <= 0 then ui.ready.Visible = false end
			else progress = math.clamp(progress + (inZone and 0.46 or -0.22) * dt, 0, 1) end
			ui.zone.Position = UDim2.new(0.5, 0, 1 - zone, 0)
			ui.zone.BackgroundColor3 = inZone and Color3.fromRGB(70,225,95) or Color3.fromRGB(90,150,110)
			ui.fish.Position = UDim2.new(0.5, 0, 1 - fishF, 0)
			ui.pb.Size = UDim2.new(1, 0, progress, 0)
			ui.pb.BackgroundColor3 = (progress > 0.5) and Color3.fromRGB(120,235,110) or Color3.fromRGB(255,205,60)
			if introT <= 0 then if progress >= 1 then finish(true); break elseif progress <= 0 then finish(false); break end end
			task.wait()
		end
	end)
end

-- ============================================================================
-- THE FISHING WORLD (VERBATIM from buildButterWorld). `lakePos`/`lakeSize`/
-- `barrelPos` come from CONFIG (the real game gets them from server markers).
-- ============================================================================
local function buildFishingWorld(lakePos, lakeSize, barrelPos)
	if st.built then return end
	st.built = true; st.isFishing = true
	st.fishProps = {}
	if typeof(lakePos) ~= "Vector3" then warn("[Fish] lake position MISSING -- fishing disabled"); return end
	local surfaceY = lakePos.Y + ((typeof(lakeSize) == "Vector3") and lakeSize.Y/2 or 0)
	local LAKE = CONFIG.lakeName

	-- ===== rod-in-hand + line + bobber =====
	local heldRod, rodTip, rodTipAtt
	local function startHeldRod()
		if heldRod then return end
		local rod = Instance.new("Model"); rod.Name = prefix.."HeldRod"
		local function rp(name, shape, size, color, mat)
			local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
			p.Material = mat or Enum.Material.SmoothPlastic; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false; p.Parent = rod; return p
		end
		local shaft = rp("Shaft", Enum.PartType.Cylinder, Vector3.new(6,0.16,0.16), Color3.fromRGB(110,70,40), Enum.Material.Wood)
		local grip  = rp("Grip",  Enum.PartType.Cylinder, Vector3.new(1.1,0.26,0.26), Color3.fromRGB(35,30,28))
		local reel  = rp("Reel",  Enum.PartType.Cylinder, Vector3.new(0.3,0.7,0.7), Color3.fromRGB(40,40,46), Enum.Material.Metal)
		rodTip = rp("Tip", Enum.PartType.Ball, Vector3.new(0.16,0.16,0.16), Color3.fromRGB(235,235,235)); rodTip.Transparency = 1
		rodTipAtt = Instance.new("Attachment"); rodTipAtt.Parent = rodTip
		rod.Parent = Workspace; heldRod = rod; st.fishProps[#st.fishProps+1] = rod
		task.spawn(function()
			while heldRod and heldRod.Parent and not st.owns do
				local char = player.Character
				local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hand and hrp then
					local look = hrp.CFrame.LookVector; look = Vector3.new(look.X, 0, look.Z)
					if look.Magnitude < 0.1 then look = Vector3.new(0,0,-1) end
					local rodDir = (look.Unit + Vector3.new(0, 0.62, 0)).Unit
					local center = hand.Position + look.Unit * 0.4 + rodDir * 3.0
					local cf = CFrame.lookAt(center, center + rodDir) * CFrame.Angles(0, math.rad(90), 0)
					shaft.CFrame = cf
					grip.CFrame  = cf * CFrame.new(-2.6, 0, 0)
					reel.CFrame  = cf * CFrame.new(-2.0, -0.35, 0) * CFrame.Angles(0,0,math.rad(90))
					rodTip.CFrame = cf * CFrame.new(3.0, 0, 0)
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end
	local function buildBobber(cf)
		local root = Instance.new("Part"); root.Name = prefix.."Bobber"; root.Shape = Enum.PartType.Ball
		root.Size = Vector3.new(0.55,0.55,0.55); root.Color = Color3.fromRGB(240,240,245); root.Material = Enum.Material.SmoothPlastic
		root.Anchored = true; root.CanCollide = false; root.CanQuery = false; root.CastShadow = false; root.CFrame = cf; root.Parent = Workspace
		local function weldTo(part) local w = Instance.new("WeldConstraint"); w.Part0 = root; w.Part1 = part; w.Parent = root end
		local cap = Instance.new("Part"); cap.Name="Cap"; cap.Shape=Enum.PartType.Ball; cap.Size=Vector3.new(0.6,0.6,0.6)
		cap.Color=Color3.fromRGB(225,55,55); cap.Material=Enum.Material.SmoothPlastic
		cap.Anchored=false; cap.CanCollide=false; cap.CanQuery=false; cap.CastShadow=false; cap.Massless=true; cap.CFrame=cf*CFrame.new(0,0.22,0); cap.Parent=root; weldTo(cap)
		local ant = Instance.new("Part"); ant.Name="Antenna"; ant.Shape=Enum.PartType.Cylinder; ant.Size=Vector3.new(0.5,0.07,0.07)
		ant.Color=Color3.fromRGB(225,55,55); ant.Material=Enum.Material.SmoothPlastic
		ant.Anchored=false; ant.CanCollide=false; ant.CanQuery=false; ant.CastShadow=false; ant.Massless=true; ant.CFrame=cf*CFrame.new(0,0.62,0)*CFrame.Angles(0,0,math.rad(90)); ant.Parent=root; weldTo(ant)
		return root
	end
	local function attachLine(bobRoot)
		if not rodTipAtt then return end
		local a1 = Instance.new("Attachment"); a1.Name = "LineEnd"; a1.Parent = bobRoot
		local beam = Instance.new("Beam"); beam.Attachment0 = rodTipAtt; beam.Attachment1 = a1
		beam.Width0 = 0.05; beam.Width1 = 0.05; beam.FaceCamera = true; beam.Segments = 4
		beam.Color = ColorSequence.new(Color3.fromRGB(235,235,235)); beam.Transparency = NumberSequence.new(0.15)
		beam.LightInfluence = 1; beam.Parent = bobRoot
	end

	-- ===== ROD BARREL + "Grab Fishing Rod" prompt =====
	if typeof(barrelPos) == "Vector3" then
		local barrel = Instance.new("Model"); barrel.Name = prefix.."RodBarrel"
		local body = newPart(barrel, "Barrel", Enum.PartType.Cylinder, Vector3.new(3.4,3.0,3.0), Color3.fromRGB(124,82,44), CFrame.new(barrelPos + Vector3.new(0,1.7,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Wood)
		barrel.PrimaryPart = body
		newPart(barrel, "Lip", Enum.PartType.Cylinder, Vector3.new(0.5,3.2,3.2), Color3.fromRGB(96,62,32), CFrame.new(barrelPos + Vector3.new(0,3.35,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Wood)
		newPart(barrel, "Inside", Enum.PartType.Cylinder, Vector3.new(0.4,2.5,2.5), Color3.fromRGB(48,32,18), CFrame.new(barrelPos + Vector3.new(0,3.3,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Wood)
		for _, oy in ipairs({0.7, 1.8, 2.9}) do newPart(barrel, "Band", Enum.PartType.Cylinder, Vector3.new(0.28,3.5,3.5), Color3.fromRGB(58,40,24), CFrame.new(barrelPos + Vector3.new(0,oy,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Wood) end
		local rimY = barrelPos + Vector3.new(0, 3.0, 0)
		local NRODS = 4
		for i = 0, NRODS - 1 do
			local ang = i * (2*math.pi / NRODS) + 0.4
			local outward = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local tiltDeg = 20; local rodLen = 6.5
			local up = math.cos(math.rad(tiltDeg)); local out = math.sin(math.rad(tiltDeg))
			local axis = (outward * out + Vector3.new(0, up, 0)).Unit
			local center = rimY + outward * 0.7 + axis * (rodLen/2)
			local cf = CFrame.lookAt(center, center + axis) * CFrame.Angles(0, math.rad(90), 0)
			newPart(barrel, "Rod", Enum.PartType.Cylinder, Vector3.new(rodLen,0.16,0.16), Color3.fromRGB(110,70,40), cf, Enum.Material.Wood)
			newPart(barrel, "RodReel", Enum.PartType.Cylinder, Vector3.new(0.28,0.6,0.6), Color3.fromRGB(38,38,44), cf * CFrame.new(-rodLen/2 + 0.9, -0.32, 0) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Metal)
			newPart(barrel, "RodTip", Enum.PartType.Ball, Vector3.new(0.22,0.22,0.22), Color3.fromRGB(235,235,235), cf * CFrame.new(rodLen/2, 0, 0))
		end
		barrel.Parent = Workspace; st.fishProps[#st.fishProps+1] = barrel
		local grab = addPrompt(body, "Grab Fishing Rod", "Rod Barrel", function()
			if st.owns then return end
			if not st.hasRod then
				st.hasRod = true; startHeldRod()
				floatText(barrelPos + Vector3.new(0,4,0), "Got a fishing rod! \xF0\x9F\x8E\xA3")
				print("[Fish] "..player.Name.." grabbed rod")
			else floatText(barrelPos + Vector3.new(0,4,0), "You already have a rod!") end
		end)
		grab.HoldDuration = 0.3
		print(string.format("[Fish] built rod barrel at (%.0f,%.0f,%.0f)", barrelPos.X, barrelPos.Y, barrelPos.Z))
	else
		warn("[Fish] barrel position MISSING")
	end

	-- ===== FISHING HUD (status + tap-to-hook + junk popup) =====
	local pgui = player:WaitForChild("PlayerGui")
	local hud = Instance.new("ScreenGui"); hud.Name = "FishingHUD"; hud.ResetOnSpawn = false; hud.DisplayOrder = 88; hud.Parent = pgui
	local status = Instance.new("Frame"); status.AnchorPoint = Vector2.new(0.5,0); status.Position = UDim2.new(0.5,0,0.12,0); status.Size = UDim2.new(0,440,0,40)
	status.BackgroundColor3 = Color3.fromRGB(25,90,185); status.BackgroundTransparency = 0.12; status.BorderSizePixel = 0; status.Visible = false; status.Parent = hud
	Instance.new("UICorner", status).CornerRadius = UDim.new(0,10); local sstk = Instance.new("UIStroke", status); sstk.Color = Color3.fromRGB(255,215,0); sstk.Thickness = 2
	local statusText = Instance.new("TextLabel"); statusText.Size = UDim2.new(1,0,1,0); statusText.BackgroundTransparency = 1
	statusText.Font = Enum.Font.GothamBold; statusText.TextSize = 20; statusText.TextColor3 = Color3.new(1,1,1); statusText.Text = ""; statusText.Parent = status
	local function setStatus(txt) statusText.Text = txt; status.Visible = true end
	local function hideStatus() status.Visible = false end
	local JUNK_EMOJI = {
		["an old boot"]="\xF0\x9F\xA5\xBE", ["a butter blob"]="\xF0\x9F\xA7\x88", ["a rubber duck"]="\xF0\x9F\xA6\x86",
		["a soggy sock"]="\xF0\x9F\xA7\xA6", ["a rusty tin can"]="\xF0\x9F\xA5\xAB", ["a clump of swamp weed"]="\xF0\x9F\x8C\xBF",
		["a lost flip-flop"]="\xF0\x9F\xA9\xB4", ["a message in a bottle"]="\xF0\x9F\x8D\xBE",
	}
	local function showJunk(junk)
		local pop = Instance.new("TextLabel"); pop.AnchorPoint = Vector2.new(0.5,0.5); pop.Position = UDim2.new(0.5,0,0.42,0); pop.Size = UDim2.new(0,60,0,60)
		pop.BackgroundTransparency = 1; pop.Font = Enum.Font.GothamBold; pop.TextSize = 70; pop.Text = JUNK_EMOJI[junk] or "\xF0\x9F\xA5\xBE"; pop.TextTransparency = 1; pop.Parent = hud
		TS:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0,120,0,120), TextTransparency = 0}):Play()
		task.delay(1.2, function() TS:Create(pop, TweenInfo.new(0.4), {TextTransparency = 1}):Play(); task.delay(0.45, function() pop:Destroy() end) end)
	end
	local function waitForTap(timeout)
		local tapped = false
		local catcher = Instance.new("TextButton"); catcher.Size = UDim2.new(1,0,1,0); catcher.BackgroundColor3 = Color3.fromRGB(255,120,40)
		catcher.BackgroundTransparency = 0.8; catcher.AutoButtonColor = false; catcher.Text = ""; catcher.Parent = hud
		local big = Instance.new("TextLabel"); big.AnchorPoint = Vector2.new(0.5,0.5); big.Position = UDim2.new(0.5,0,0.5,0); big.Size = UDim2.new(0,320,0,120)
		big.BackgroundTransparency = 1; big.Font = Enum.Font.FredokaOne; big.TextSize = 60; big.TextColor3 = Color3.fromRGB(255,240,120); big.Text = "TAP TO HOOK!"; big.Parent = catcher
		Instance.new("UIStroke", big).Thickness = 3
		local c = catcher.MouseButton1Click:Connect(function() tapped = true end)
		local t = 0; while t < timeout and not tapped do t = t + task.wait() end
		c:Disconnect(); catcher:Destroy()
		return tapped
	end

	-- ===== the EGG (caught) -> appears IN FRONT of the player, with a Hatch prompt =====
	local function spawnEgg()
		if st.egg then return end
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart"); if not hrp then return end
		local fwd = hrp.CFrame.LookVector; fwd = Vector3.new(fwd.X, 0, fwd.Z); if fwd.Magnitude < 0.1 then fwd = Vector3.new(0,0,-1) end
		local center = hrp.Position + fwd.Unit * 6 + Vector3.new(0, -1.0, 0)
		st.eggPos = center; st.eggCaught = true
		local egg = Instance.new("Model"); egg.Name = prefix.."Egg"
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1,1,1), CONFIG.eggShell, nil)
		shell.Reflectance = 0.08
		local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Scale = Vector3.new(3.0,4.0,3.0); m.Parent = shell
		visual.PrimaryPart = shell
		for j = 1, 8 do local a = (j-1)*(2*math.pi/8); local y = math.sin(a*1.7)*1.0; local r = 1.3*math.sqrt(math.max(0, 1-(y/2)^2))+0.05
			newPart(visual, "Drip", Enum.PartType.Ball, Vector3.new(0.45,0.45,0.45), CONFIG.eggDrip, CFrame.new(math.sin(a)*r, y, math.cos(a)*r)) end
		st.eggBaseCF = CFrame.new(center); st.eggVisual = visual; visual:PivotTo(st.eggBaseCF)
		st.egg = egg; egg.Parent = Workspace
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(255,235,140); hl.FillTransparency = 0.5; hl.OutlineColor = Color3.fromRGB(255,210,80); hl.Adornee = visual; hl.Parent = egg
		addPrompt(shell, "Hatch", "Egg", function() if st.owns or st.hatching then return end; hatchEgg() end)
		task.spawn(function() local t = 0
			while st.egg do t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.28, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end)
				end
				task.wait(0.05)
			end
		end)
		print("[Fish] egg caught -> appeared in front of "..player.Name)
	end

	-- ===== shore-edge probe: is the player at the exposed water's edge? =====
	local EDGE_REACH = 7
	local function isInLake(inst) return inst.Name == LAKE or inst:FindFirstAncestor(LAKE) ~= nil end
	local function butterProbe()
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart"); if not hrp then return nil end
		local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character }; params.IgnoreWater = true
		local origin = hrp.Position
		local function probe(px, pz)
			local r = Workspace:Raycast(Vector3.new(px, origin.Y + 5, pz), Vector3.new(0, -400, 0), params)
			if not r or not r.Instance then return nil end
			if isInLake(r.Instance) then return r.Position end
			return nil
		end
		local p = probe(origin.X, origin.Z); if p then return p end
		for _, rad in ipairs({ EDGE_REACH * 0.55, EDGE_REACH }) do
			for i = 0, 11 do local a = i * (math.pi / 6); p = probe(origin.X + math.cos(a)*rad, origin.Z + math.sin(a)*rad); if p then return p end end
		end
		return nil
	end
	local function isNearEdge() return butterProbe() ~= nil end

	-- ===== where the cast lands: a point OUT on the water in front of the player =====
	local function castTarget()
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart"); if not hrp then return nil end
		local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character }; params.IgnoreWater = true
		local origin = hrp.Position
		local function waterY(px, pz)
			local r = Workspace:Raycast(Vector3.new(px, origin.Y + 8, pz), Vector3.new(0, -400, 0), params)
			if not r or not r.Instance then return nil end
			if isInLake(r.Instance) then return r.Position.Y end
			return nil
		end
		local look = hrp.CFrame.LookVector; look = Vector3.new(look.X, 0, look.Z)
		look = (look.Magnitude > 0.1) and look.Unit or Vector3.new(0, 0, -1)
		local dir
		if waterY(origin.X, origin.Z) then dir = look
		else
			local best, bestDist
			for i = 0, 11 do local a = i * (math.pi / 6); local d = Vector3.new(math.cos(a), 0, math.sin(a))
				for _, rad in ipairs({ 3, 6, 9, 12 }) do if waterY(origin.X + d.X*rad, origin.Z + d.Z*rad) then if not bestDist or rad < bestDist then bestDist = rad; best = d end break end end
			end
			dir = best or look
		end
		local CAST_OUT, CAST_MAX, STEP = 8, 28, 2
		local edgeDist, lastY, lastD
		for d = 1, CAST_MAX, STEP do
			local by = waterY(origin.X + dir.X*d, origin.Z + dir.Z*d)
			if by then edgeDist = edgeDist or d; lastY, lastD = by, d
				if d >= edgeDist + CAST_OUT then return Vector3.new(origin.X + dir.X*d, by + 0.45, origin.Z + dir.Z*d) end
			end
		end
		if lastY then return Vector3.new(origin.X + dir.X*lastD, lastY + 0.45, origin.Z + dir.Z*lastD) end
		return nil
	end

	-- ===== the FISH prompt (follows the player; enabled only at the edge) =====
	local fishFollower = newPart(Workspace, prefix.."FishSpot", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.new(1,1,1), CFrame.new(lakePos))
	fishFollower.Transparency = 1; st.fishProps[#st.fishProps+1] = fishFollower
	local fishing = false
	local fishPrompt
	fishPrompt = addPrompt(fishFollower, "Fish", "Water's Edge", function()
		if st.owns or st.eggCaught or fishing then return end
		local hrpPos = (player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position) or lakePos
		if not st.hasRod then floatText(hrpPos + Vector3.new(0,3,0), "Grab a rod from the barrel first!"); return end
		if not isNearEdge() then floatText(hrpPos + Vector3.new(0,3,0), "Get closer to the water's edge to fish!"); return end
		fishing = true; fishPrompt.Enabled = false
		pushQuestProg(prefix, { started = true })
		task.spawn(function()
			local keepGoing = true
			while keepGoing and not st.owns and isNearEdge() do
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local target = castTarget()
					or (hrp and Vector3.new(hrp.Position.X, surfaceY + 0.4, hrp.Position.Z))
					or Vector3.new(lakePos.X, surfaceY + 0.4, lakePos.Z)
				local startP = (rodTip and rodTip.Position) or (hrp and (hrp.Position + Vector3.new(0,1.5,0))) or target
				local bob = buildBobber(CFrame.new(startP)); attachLine(bob)
				local nv = Instance.new("NumberValue"); nv.Value = 0; nv.Parent = bob
				nv:GetPropertyChangedSignal("Value"):Connect(function() local t = nv.Value; bob.CFrame = CFrame.new(startP:Lerp(target, t) + Vector3.new(0, math.sin(t*math.pi)*6, 0)) end)
				TS:Create(nv, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {Value = 1}):Play()
				print("[Fish] "..player.Name.." cast"); setStatus("Waiting for a bite...")
				local floating = true
				task.spawn(function()
					task.wait(0.62); local ft = 0
					while floating and bob.Parent do ft = ft + 0.05; pcall(function() bob.CFrame = CFrame.new(target + Vector3.new(0, math.sin(ft*2.2)*0.16, 0)) end); task.wait(0.05) end
				end)
				task.wait(0.65 + 1 + math.random() * 3)
				floating = false
				if st.owns or not isNearEdge() then pcall(function() bob:Destroy() end) break end
				print("[Fish] "..player.Name.." bite")
				local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,36,0,36); bb.StudsOffset = Vector3.new(0,2.4,0); bb.AlwaysOnTop = true; bb.Parent = bob
				local bl = Instance.new("TextLabel"); bl.Size = UDim2.new(1,0,1,0); bl.BackgroundTransparency = 1; bl.Font = Enum.Font.GothamBold; bl.TextSize = 34; bl.TextColor3 = Color3.fromRGB(255,70,70); bl.Text = "!"; bl.Parent = bb
				local biteBase = bob.Position; local wiggling = true
				task.spawn(function() local t = 0; while wiggling and bob.Parent do t = t + 0.04; pcall(function() bob.CFrame = CFrame.new(biteBase + Vector3.new(math.sin(t*30)*0.18, -math.abs(math.sin(t*16))*0.5, math.cos(t*30)*0.18)) end); task.wait(0.03) end end)
				setStatus("Something's biting! TAP!")
				local hooked = waitForTap(1.3)
				wiggling = false
				if not hooked then
					setStatus("It got away!"); print("[Fish] missed the hook"); pcall(function() bob:Destroy() end); task.wait(1.1)
				else
					print("[Fish] hooked"); setStatus("Reel it in!"); pcall(function() bob:Destroy() end)
					local rDone, rWin = false, false
					openReelMinigame(function(s) rWin = s; rDone = true end)
					while not rDone do task.wait() end
					if not rWin then setStatus("It got away!"); print("[Fish] reel-in failed"); task.wait(1.1)
					else
						print("[Fish] reeled in")
						pushQuestProg(prefix, { started = true, found = ((localQuestProg[prefix] and localQuestProg[prefix].found) or 0) + 1 })
						local res = rollCatch()
						if type(res) == "table" and res.egg then
							setStatus("You reeled in... an EGG! \xF0\x9F\xA5\x9A"); keepGoing = false; pushQuestProg(prefix, { complete = true })
							task.wait(0.6); spawnEgg(); task.wait(1.4)
						elseif type(res) == "table" then
							setStatus("You caught: "..(res.junk or "junk").."!"); showJunk(res.junk or ""); task.wait(1.8)
						else setStatus("It got away!"); task.wait(1.1) end
					end
				end
			end
			fishing = false; hideStatus()
			if not st.owns and not st.eggCaught then fishPrompt.Enabled = true end
		end)
	end)
	fishPrompt.MaxActivationDistance = 16; fishPrompt.HoldDuration = 0; fishPrompt.Enabled = false
	task.spawn(function()
		local probeTimer, nearCached = 0, false
		while st and not st.owns do
			local dt = RunService.Heartbeat:Wait()
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then fishFollower.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 1.5, 0)) end
			probeTimer = probeTimer - dt
			if probeTimer <= 0 then probeTimer = 0.2; nearCached = isNearEdge() end
			if not fishing and not st.eggCaught then fishPrompt.Enabled = (hrp ~= nil) and nearCached end
		end
	end)
	print(string.format("[Fish] fishing ready: lake=(%.0f,%.0f,%.0f)", lakePos.X, lakePos.Y, lakePos.Z))
	if st.owns then for _, o in ipairs(st.fishProps) do setVisible(o, false) end end
end

-- ============================================================================
-- BOOT: find the water + barrel spot by name, then build.
-- ============================================================================
task.spawn(function()
	local lake = Workspace:FindFirstChild(CONFIG.lakeName) or Workspace:FindFirstChild(CONFIG.lakeName, true)
	if not lake then warn("[Fish] no part/model named '"..CONFIG.lakeName.."' found in Workspace -- set CONFIG.lakeName"); return end
	local lakePos, lakeSize
	if lake:IsA("BasePart") then lakePos = lake.Position; lakeSize = lake.Size
	else lakePos = lake:GetPivot().Position; local _, sz = lake:GetBoundingBox(); lakeSize = sz end
	local barrelPos = CONFIG.barrelPosFallback
	local spot = Workspace:FindFirstChild(CONFIG.barrelSpotName) or Workspace:FindFirstChild(CONFIG.barrelSpotName, true)
	if spot and spot:IsA("BasePart") then barrelPos = spot.Position end
	if not barrelPos then -- no spot placed -> drop the barrel a few studs toward +X of the lake edge
		barrelPos = lakePos + Vector3.new((lakeSize and lakeSize.X/2 or 8) + 4, 0, 0)
	end
	buildFishingWorld(lakePos, lakeSize, barrelPos)
end)
