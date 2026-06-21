--======================================================================
-- ToasterEasterEgg.server.lua  (Script)  -- STANDALONE, MODULAR easter egg
--======================================================================
-- A discovery easter egg on Island 6 (Bread Board): a classic 2-slice toaster sitting LOADED with two
-- pieces of toast. It does NOTHING until a player finds it and uses its ProximityPrompt. On use, the
-- toast + lever push DOWN; ~5s later a "DING!" plays and both pieces LAUNCH high into the sky, arc back
-- down + fade; then a FRESH pair pops back up into the slots and it's READY again. Debounced so it can't
-- be spammed mid-cycle.
--
-- PURELY COSMETIC -- it never touches flight, pets, coins, gas, the black hole, shop, events, storms,
-- planes, the cow, the garden, or any gameplay. Anchored + CanCollide=false, so players fly through it
-- harmlessly. It only does work when a player interacts.
--
-- ART STYLE: matte low-poly, consistent with the cow/pets -- the body + each toast slice are built as a
-- rounded-cube UNION (fillet box -> ONE clean beveled solid), NOT a pile of loose spheres. On CSG failure
-- it falls back to a plain block so the toaster still appears.
--
-- NOTE: this is a NEW server script -> it needs a Rojo restart (entry added to default.project.json).
--======================================================================

local Workspace = game:GetService("Workspace")

-- ⚠ PLACEHOLDER SOUNDS -- REPLACE WITH REAL ASSET IDS BEFORE LAUNCH. Left "" (silent, no broken-id spam),
-- same safe approach as the cow easter egg.
local DING_SOUND_ID  = "" -- ⚠ REPLACE WITH TOASTER DING SOUND
local LEVER_SOUND_ID = "" -- ⚠ REPLACE WITH LEVER PUSH CLICK SOUND (optional)

-- tuning
local STEP           = 0.04   -- seconds per animation frame
local GROUND_OFFSET  = 2.0    -- body-centre height above the marker so the toaster rests on the spot
local DOWN_TIME      = 5.0    -- seconds the toast sits pressed-down before the DING + launch
local DOWN_DUR       = 0.32   -- how long the press-down animation takes
local RELOAD_DUR     = 0.30   -- how long the fresh toast takes to pop back up

local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local SMOOTH = Enum.SurfaceType.Smooth

-- palette
local CHROME   = Color3.fromRGB(206, 212, 222) -- matte light-silver body
local CHROME_D = Color3.fromRGB(150, 156, 168) -- darker chrome (base / trim)
local SLOT     = Color3.fromRGB(38, 38, 44)     -- dark slot openings
local LEVER    = Color3.fromRGB(70, 74, 84)     -- lever knob

-- BREAD color tiers (fresh -> toasted -> burnt), for the soft INNER and the browner CRUST rim separately
local BREAD_INNER_FRESH = Color3.fromRGB(248, 232, 196) -- pale soft inside
local BREAD_CRUST_FRESH = Color3.fromRGB(224, 196, 150) -- light tan crust
local BREAD_INNER_TOAST = Color3.fromRGB(205, 165, 110) -- toasted inside
local BREAD_CRUST_TOAST = Color3.fromRGB(150, 104,  60) -- toasted crust
local BREAD_INNER_BURNT = Color3.fromRGB( 64,  50,  42) -- charred inside
local BREAD_CRUST_BURNT = Color3.fromRGB( 34,  27,  24) -- charred crust (near black)

local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds" -- built-in smoke texture (safe, not a custom asset)

--======================================================================
-- LOW-LEVEL BUILD HELPER (pet/cow art style: matte, ALL surfaces Smooth, massless, no collide/query).
--======================================================================
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part")
	p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	p.TopSurface = SMOOTH;  p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH;  p.BackSurface = SMOOTH
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end

-- Build a rounded-cube (fillet box: 3 slabs + 8 corner spheres + 12 edge cylinders) centred at baseCF and
-- FUSE it into ONE beveled solid (matte). On CSG failure, return a plain block fallback so it still shows.
-- Same technique the cow/pets use. Returns the resulting BasePart.
local function roundedSolid(parent, baseCF, sx, sy, sz, R, color, material, name)
	local iX, iY, iZ = sx - 2*R, sy - 2*R, sz - 2*R
	local hX, hY, hZ = iX/2, iY/2, iZ/2
	local dd = 2*R
	local src = {}
	local function a(shape, dx, dy, dz, x, y, z, rot)
		src[#src+1] = newPart(Workspace, "rs", shape, Vector3.new(dx,dy,dz), color, baseCF * CFrame.new(x,y,z) * (rot or CFrame.new()), material)
	end
	a(BLK, sx, iY, iZ, 0,0,0); a(BLK, iX, sy, iZ, 0,0,0); a(BLK, iX, iY, sz, 0,0,0) -- 3 flat-face slabs
	for _, c in ipairs({{1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1}}) do
		a(BAL, dd,dd,dd, c[1]*hX, c[2]*hY, c[3]*hZ) -- 8 corner spheres
	end
	for _, e in ipairs({{1,1},{1,-1},{-1,1},{-1,-1}}) do -- 12 edge cylinders
		a(CYL, iX,dd,dd, 0, e[1]*hY, e[2]*hZ)                                   -- edges along X
		a(CYL, iY,dd,dd, e[1]*hX, 0, e[2]*hZ, CFrame.Angles(0,0,math.rad(90)))  -- edges along Y
		a(CYL, iZ,dd,dd, e[1]*hX, e[2]*hY, 0, CFrame.Angles(0,math.rad(90),0))  -- edges along Z
	end
	local first = table.remove(src, 1)
	local ok, u = pcall(function() return first:UnionAsync(src) end)
	if ok and typeof(u) == "Instance" then
		first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
		u.Name = name; u.Anchored = true; u.CanCollide = false; u.CanQuery = false; u.CanTouch = false
		u.CastShadow = false; u.Massless = true; u.Material = material; u.UsePartColor = true; u.Color = color
		pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
		pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
		pcall(function() u.SmoothingAngle = 60 end)
		u.Parent = parent
		return u
	else
		table.insert(src, 1, first)
		for _, p in ipairs(src) do p:Destroy() end
		return newPart(parent, name, BLK, Vector3.new(sx,sy,sz), color, baseCF, material) -- plain-block fallback
	end
end

-- a small upward-wisping smoke emitter (built-in texture). `isTrail` = the lighter puff that follows flying toast.
local function makeSmoke(parent, isTrail)
	local em = Instance.new("ParticleEmitter")
	em.Texture = SMOKE_TEX
	em.Color = ColorSequence.new(Color3.fromRGB(92,92,92), Color3.fromRGB(44,44,44))
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(0.2,0.45), NumberSequenceKeypoint.new(1,1) })
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.4), NumberSequenceKeypoint.new(1, isTrail and 1.9 or 2.6) })
	em.Lifetime = NumberRange.new(0.8, 1.6)
	em.Rate = isTrail and 16 or 10
	em.Speed = NumberRange.new(1.5, 3.5)
	em.SpreadAngle = Vector2.new(18, 18)
	em.Acceleration = Vector3.new(0, 6, 0) -- wisp upward (world space)
	em.LightEmission = 0
	em.Enabled = false                      -- off by default; toggled during the cycle
	em.Parent = parent
	return em
end

-- A real BREAD SLICE (not a puck): a rounded-square body + a classic domed/arch top, with thickness. Two-tone:
-- a CRUST silhouette UNION (browner; rim + edges + domed top) plus a lighter INNER panel that pokes through
-- both wide faces (the soft inside, framed by the crust). Built as a MODEL with an invisible Root as its
-- PrimaryPart, so it moves rigidly via PivotTo regardless of the union re-centring its own CFrame.
-- Local axes: thin in X (slice thickness), tall in Y, wide in Z. Starts FRESH (light); recolour-able.
local function buildToast(parent, cf)
	local THICK, HEIGHT, WIDTH = 0.62, 2.7, 2.3
	local model = Instance.new("Model"); model.Name = "Toast"
	model.Parent = parent

	local root = newPart(model, "Root", BLK, Vector3.new(0.2,0.2,0.2), BREAD_CRUST_FRESH, cf)
	root.Transparency = 1; model.PrimaryPart = root
	makeSmoke(root, true) -- trailing smoke for when it launches burnt (enabled at launch)

	-- CRUST = rounded-rectangle body (bottom) + cylinder ARCH on top -> ONE union (the bread silhouette)
	local domeR  = WIDTH / 2
	local domeCY = HEIGHT/2 - domeR                 -- arch centre so the dome top reaches +HEIGHT/2
	local bodyTop, bodyBot = domeCY, -HEIGHT/2
	local bodyH  = bodyTop - bodyBot
	local bodyCY = (bodyTop + bodyBot) / 2
	local R = 0.16                                   -- rounded body corners
	local iY, iZ = bodyH - 2*R, WIDTH - 2*R
	local hY, hZ = iY/2, iZ/2
	local dd = 2*R
	local src = {}
	local function a(shape, dx,dy,dz, x,y,z)
		src[#src+1] = newPart(Workspace, "br", shape, Vector3.new(dx,dy,dz), BREAD_CRUST_FRESH, cf*CFrame.new(x,y,z), Enum.Material.SmoothPlastic)
	end
	a(BLK, THICK, iY, WIDTH, 0, bodyCY, 0)                       -- body slab (full width)
	a(BLK, THICK, bodyH, iZ, 0, bodyCY, 0)                       -- body slab (full height)
	a(CYL, THICK, dd, dd, 0, bodyCY + hY,  hZ)                   -- 4 rounded body corners (cylinders, axis X)
	a(CYL, THICK, dd, dd, 0, bodyCY + hY, -hZ)
	a(CYL, THICK, dd, dd, 0, bodyCY - hY,  hZ)
	a(CYL, THICK, dd, dd, 0, bodyCY - hY, -hZ)
	a(CYL, THICK, WIDTH, WIDTH, 0, domeCY, 0)                    -- domed arch top (cylinder, axis X)

	local crust
	local first = table.remove(src, 1)
	local ok, u = pcall(function() return first:UnionAsync(src) end)
	if ok and typeof(u) == "Instance" then
		first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
		u.Name = "Crust"; u.Anchored = true; u.CanCollide = false; u.CanQuery = false; u.CanTouch = false
		u.CastShadow = false; u.Massless = true; u.Material = Enum.Material.SmoothPlastic; u.UsePartColor = true; u.Color = BREAD_CRUST_FRESH
		pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
		pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
		pcall(function() u.SmoothingAngle = 50 end)
		u.Parent = model; crust = u
	else
		table.insert(src, 1, first)
		for _, p in ipairs(src) do p.Name = "CrustChunk"; p.Parent = model end -- fallback: keep the cluster
		crust = src[1]
	end

	-- INNER soft crumb: a lighter panel slightly THICKER than the crust so it shows on both wide faces, framed
	-- by the crust rim + dome. (Plain block -> a clean lighter centre, no extra union cost.)
	newPart(model, "Inner", BLK, Vector3.new(THICK + 0.08, 1.5, 1.8), BREAD_INNER_FRESH, cf * CFrame.new(0, -0.05, 0))

	return model
end

-- recolour a toast slice (crust rim vs soft inner) -- used to darken it fresh -> toasted -> burnt
local function toastSetColors(toast, crustC, innerC)
	for _, d in ipairs(toast:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Inner" then d.Color = innerC
			elseif d.Name == "Crust" or d.Name == "CrustChunk" then d.Color = crustC end
		end
	end
end
-- fade a toast slice (everything but the invisible Root)
local function toastSetTransparency(toast, v)
	for _, d in ipairs(toast:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Root" then d.Transparency = v end
	end
end
-- toggle a toast slice's trailing smoke
local function toastSmoke(toast, on)
	local em = toast:FindFirstChildWhichIsA("ParticleEmitter", true)
	if em then em.Enabled = on end
end

--======================================================================
-- THE TOASTER. Body = ONE chrome rounded-cube union. Slots + lever + base = flush matte parts. Two toast
-- slices sit loaded in the slots. Returns a table describing it + the loaded/down CFrames for the cycle.
-- Local axes: +X = right (lever side), -Z = front, +Y = up.
--======================================================================
local function buildToaster(rootCF)
	local model = Instance.new("Model"); model.Name = "EasterToaster"
	model.Parent = Workspace -- parented before UnionAsync (CSG needs parts in the world)

	-- body (chrome rounded solid) -- 6 wide x 3.6 tall x 3.2 deep, centre at rootCF
	local body = roundedSolid(model, rootCF, 6, 3.6, 3.2, 0.7, CHROME, Enum.Material.SmoothPlastic, "ToasterBody")
	model.PrimaryPart = body

	-- base plate (slightly larger, darker chrome) so it reads as sitting on a surface
	newPart(model, "Base", BLK, Vector3.new(6.4, 0.5, 3.6), CHROME_D, rootCF * CFrame.new(0, -1.75, 0))

	-- two dark slot openings on top (left + right), recessed just below the top face
	local slotL = newPart(model, "SlotL", BLK, Vector3.new(0.95, 0.4, 2.5), SLOT, rootCF * CFrame.new(-1.3, 1.7, 0))
	local slotR = newPart(model, "SlotR", BLK, Vector3.new(0.95, 0.4, 2.5), SLOT, rootCF * CFrame.new( 1.3, 1.7, 0))
	-- smoke that wisps up out of the slots WHILE toasting (off by default)
	local smokeL = makeSmoke(slotL, false)
	local smokeR = makeSmoke(slotR, false)

	-- lever track (a thin dark recess down the right side) + the lever knob that slides in it
	newPart(model, "LeverTrack", BLK, Vector3.new(0.25, 2.0, 0.5), SLOT, rootCF * CFrame.new(3.02, 0.3, 0))
	local lever = newPart(model, "Lever", BLK, Vector3.new(0.7, 0.7, 0.95), LEVER, rootCF * CFrame.new(3.2, 1.0, 0))

	-- the two loaded toast slices
	local leftLoaded  = rootCF * CFrame.new(-1.3, 1.75, 0)
	local rightLoaded = rootCF * CFrame.new( 1.3, 1.75, 0)
	local leftDown    = rootCF * CFrame.new(-1.3, 0.35, 0)
	local rightDown   = rootCF * CFrame.new( 1.3, 0.35, 0)
	local leverUp     = rootCF * CFrame.new(3.2,  1.0, 0)
	local leverDown   = rootCF * CFrame.new(3.2, -0.4, 0)

	local leftToast  = buildToast(model, leftLoaded)
	local rightToast = buildToast(model, rightLoaded)

	-- sounds on the body (placeholders -> see top of file)
	local ding = Instance.new("Sound"); ding.Name = "DingSound"; ding.SoundId = DING_SOUND_ID -- ⚠ REPLACE WITH TOASTER DING SOUND
	ding.Volume = 0.7; ding.RollOffMinDistance = 10; ding.RollOffMaxDistance = 120; ding.Parent = body
	local click = Instance.new("Sound"); click.Name = "LeverClick"; click.SoundId = LEVER_SOUND_ID -- ⚠ REPLACE WITH LEVER PUSH CLICK SOUND
	click.Volume = 0.45; click.RollOffMinDistance = 8; click.RollOffMaxDistance = 80; click.Parent = body

	return {
		model = model, body = body, lever = lever,
		leftToast = leftToast, rightToast = rightToast,
		leftLoaded = leftLoaded, rightLoaded = rightLoaded,
		leftDown = leftDown, rightDown = rightDown,
		leverUp = leverUp, leverDown = leverDown,
		smokeL = smokeL, smokeR = smokeR,
		busy = false,
	}
end

--======================================================================
-- ANIMATION HELPERS
--======================================================================
-- smoothly lerp a set of { pv=, from=, to= } over `dur` seconds (eased). pv is any PVInstance (the toast
-- MODELS or the lever PART) -> moved rigidly via PivotTo.
local function lerpMove(items, dur)
	local t = 0
	while t < dur do
		t = math.min(dur, t + STEP)
		local a = (math.sin((t / dur - 0.5) * math.pi) + 1) / 2 -- ease in-out
		for _, it in ipairs(items) do
			if it.pv and it.pv.Parent then pcall(function() it.pv:PivotTo(it.from:Lerp(it.to, a)) end) end
		end
		task.wait(STEP)
	end
	for _, it in ipairs(items) do
		if it.pv and it.pv.Parent then pcall(function() it.pv:PivotTo(it.to) end) end
	end
end

-- launch ONE (burnt) toast slice: rocket UP fast + high, arc over, fall back down, fade, despawn -- trailing
-- a little smoke as it flies. Parabolic (manual sim). `toast` is the slice MODEL.
local function launchToast(toast, dirSign)
	if not toast then return end
	task.spawn(function()
		pcall(function()
			toastSmoke(toast, true) -- burnt toast trails smoke through the air
			local startPos = toast:GetPivot().Position
			local apex   = 105 + math.random() * 35           -- studs above the toaster (high)
			local tUp    = 0.85                                -- time to reach apex (fast up)
			local total  = 2.6                                 -- total flight before despawn
			local g      = 2 * apex / (tUp * tUp)              -- gravity that peaks at `apex` at t=tUp
			local v0     = g * tUp                             -- initial up speed
			local drift  = Vector3.new(dirSign * (5 + math.random() * 4), 0, (math.random() - 0.5) * 6) -- slight outward spread
			local sx, sy, sz = (math.random() - 0.5) * 9, (math.random() - 0.5) * 9, (math.random() - 0.5) * 9 -- tumble
			local t = 0
			while t < total and toast.Parent do
				t = t + STEP
				local y = v0 * t - 0.5 * g * t * t            -- parabola (up then down)
				local pos = startPos + Vector3.new(0, y, 0) + drift * t
				pcall(function() toast:PivotTo(CFrame.new(pos) * CFrame.Angles(sx * t, sy * t, sz * t)) end)
				if t > total - 1.0 then                        -- fade out over the last second of the fall
					toastSetTransparency(toast, math.clamp((t - (total - 1.0)) / 1.0, 0, 1))
				end
				task.wait(STEP)
			end
			pcall(function() toast:Destroy() end)
		end)
	end)
end

--======================================================================
-- THE USE CYCLE: down -> 5s -> DING + launch -> reload -> ready. Debounced via toaster.busy.
--======================================================================
local function useToaster(toaster, plr)
	if toaster.busy then return end          -- debounce: ignore interactions mid-cycle
	if not toaster.model.Parent then return end
	toaster.busy = true
	print("[EasterEgg] toaster used by " .. (plr and plr.Name or "?") .. " - toast going down")

	-- 1) toast + lever push DOWN (fresh bread, with a soft lever click)
	pcall(function() local c = toaster.body:FindFirstChild("LeverClick"); if c then c.TimePosition = 0; c:Play() end end)
	lerpMove({
		{ pv = toaster.leftToast,  from = toaster.leftLoaded,  to = toaster.leftDown  },
		{ pv = toaster.rightToast, from = toaster.rightLoaded, to = toaster.rightDown },
		{ pv = toaster.lever,      from = toaster.leverUp,     to = toaster.leverDown },
	}, DOWN_DUR)

	-- 2) ~5s toasting: smoke wisps up from the slots + the bread gradually darkens (fresh -> toasted)
	pcall(function() toaster.smokeL.Enabled = true; toaster.smokeR.Enabled = true end)
	local elapsed, dt = 0, 0.15
	while elapsed < DOWN_TIME and toaster.model.Parent do
		task.wait(dt); elapsed = elapsed + dt
		local f = math.clamp(elapsed / DOWN_TIME, 0, 1)
		local crustC = BREAD_CRUST_FRESH:Lerp(BREAD_CRUST_TOAST, f)
		local innerC = BREAD_INNER_FRESH:Lerp(BREAD_INNER_TOAST, f)
		if toaster.leftToast  then pcall(toastSetColors, toaster.leftToast,  crustC, innerC) end
		if toaster.rightToast then pcall(toastSetColors, toaster.rightToast, crustC, innerC) end
	end
	pcall(function() toaster.smokeL.Enabled = false; toaster.smokeR.Enabled = false end)
	if not toaster.model.Parent then return end

	-- 3) DING + LAUNCH both pieces high into the sky -- now BURNT (charred)
	pcall(function() local d = toaster.body:FindFirstChild("DingSound"); if d then d.TimePosition = 0; d:Play() end end)
	print("[EasterEgg] toaster DING - toast launched")
	local lt, rt = toaster.leftToast, toaster.rightToast
	toaster.leftToast, toaster.rightToast = nil, nil -- detach -> they become projectiles
	if lt then pcall(toastSetColors, lt, BREAD_CRUST_BURNT, BREAD_INNER_BURNT) end
	if rt then pcall(toastSetColors, rt, BREAD_CRUST_BURNT, BREAD_INNER_BURNT) end
	launchToast(lt, -1)
	launchToast(rt,  1)

	-- 4) reload: FRESH light bread pops UP into the slots + lever pops back up -> READY
	task.wait(0.18)
	if not toaster.model.Parent then return end
	local nl = buildToast(toaster.model, toaster.leftDown)   -- buildToast defaults to FRESH colours
	local nr = buildToast(toaster.model, toaster.rightDown)
	toaster.leftToast, toaster.rightToast = nl, nr
	lerpMove({
		{ pv = nl,            from = toaster.leftDown,  to = toaster.leftLoaded  },
		{ pv = nr,            from = toaster.rightDown, to = toaster.rightLoaded },
		{ pv = toaster.lever, from = toaster.leverDown, to = toaster.leverUp     },
	}, RELOAD_DUR)

	print("[EasterEgg] toaster reloaded, ready")
	toaster.busy = false
end

--======================================================================
-- MARKER / ISLAND RESOLUTION (by name, same as the cow easter egg + the pet quest markers).
--======================================================================
local function findIsland(prefix)
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.find(m.Name, prefix, 1, true) then return m end
	end
	return nil
end
local function resolveMarker(island, name)
	local p = island and island:FindFirstChild(name, true)
	if not p then p = Workspace:FindFirstChild(name) end
	if not p then p = Workspace:FindFirstChild(name, true) end
	return p
end

--======================================================================
-- SETUP: wait for islands to be positioned, find the "Toaster" marker on Island 6, build there, wire prompt.
--======================================================================
local function setup()
	-- wait until islands are at their final positions (Island 6 ends up high up) -- same signal the cow/pet use
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end

	local island; for _ = 1, 30 do island = findIsland("Island_6_BreadBoard"); if island then break end; task.wait(1) end
	local marker = resolveMarker(island, "Toaster")
	if not (marker and marker:IsA("BasePart")) then
		warn("[EasterEgg] Toaster marker not found on Island 6 -- toaster disabled")
		return
	end

	-- hide the marker part itself (keep it in place as the anchor spot)
	pcall(function() marker.Transparency = 1; marker.CanCollide = false; marker.CanQuery = false end)

	local spotPos = marker.Position
	-- same marker position, spun 180 degrees about Y so the toaster faces the other way (lever to the other side)
	local rootCF = CFrame.new(spotPos.X, spotPos.Y + GROUND_OFFSET, spotPos.Z) * CFrame.Angles(0, math.rad(180), 0)

	local toaster = buildToaster(rootCF)

	-- player-activated prompt -- the toaster sits loaded + does nothing until someone uses this
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UseToasterPrompt"
	prompt.ActionText = "Use Toaster"
	prompt.ObjectText = "Toaster"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = toaster.body
	prompt.Triggered:Connect(function(plr)
		local ok, err = pcall(useToaster, toaster, plr)
		if not ok then
			warn("[EasterEgg] toaster cycle error: " .. tostring(err))
			toaster.busy = false -- never get stuck if the cycle errors
		end
	end)

	print("[EasterEgg] toaster built at Toaster spot (Island 6)")
end

task.spawn(function()
	local ok, err = pcall(setup)
	if not ok then warn("[EasterEgg] toaster setup error: " .. tostring(err)) end
end)
