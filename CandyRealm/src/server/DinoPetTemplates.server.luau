--======================================================================
-- DinoPetTemplates.server.luau  (ServerScriptService.DinoPetTemplates)  -- CandyRealm
--======================================================================
-- GENERATED EXTRACTION -- the BUILDER half of each Dino Realm pet script, verbatim, with the gameplay
-- half deliberately left behind.
--
-- The Dino Realm has no single template file the way it has FoodPetTemplates for the Food pets: each
-- dino's fused model is built inside its own GAMEPLAY script (Stegosaurus.server.luau etc.), tangled up
-- with hatch RemoteEvents, active-pet tracking and PlayerRemoving cleanup. Copying those files here would
-- have imported dino hatching into the candy realm -- so this file carries ONLY the construction: the CSG
-- helpers and the build function from each, byte-for-byte, wrapped per-pet in a `do ... end` block so six
-- copies of the same helper names cannot collide.
--
-- Each build runs in Workspace (UnionAsync is server-only and needs the parts there), is cloned into
-- ReplicatedStorage under the SAME name the Dino Realm publishes (StegosaurusTemplate, ...), and the
-- Workspace original is destroyed -- no dinosaur is left standing in the candy world. The hub'"'"'s DINO tab
-- (CrossRealmPets.client.luau) clones these for its cards, so Candy shows the EXACT models the Dino Realm
-- shows, not approximations.
--
-- Cosmetic only: every part is Anchored, Massless, CanCollide=false. Nothing here can be hatched,
-- equipped or interacted with.
--======================================================================

local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Publish one built model: replace any stale copy, clone to RS, destroy the Workspace original.
local function publish(model, templateName, unionErr)
	local built = model.Name
	for _, c in ipairs(RS:GetChildren()) do
		if c.Name == templateName then c:Destroy() end
	end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then n += 1 end
	end
	local tmpl = model:Clone()
	tmpl.Name = templateName
	tmpl.Parent = RS
	model:Destroy() -- the visible Workspace copy has no business in this realm
	if unionErr then
		warn(("[DinoPetTemplates] %s union FAILED (%s) -- template published with UNFUSED body (still appears)")
			:format(built, tostring(unionErr)))
	else
		print(("[DinoPetTemplates] %s -> ReplicatedStorage.%s (%d parts)"):format(built, templateName, n))
	end
end

-- ============================================================================
-- Stegosaurus -- helpers + build fn extracted VERBATIM from Stegosaurus.server.luau
-- (its hatch/gameplay half stays in the Dino Realm where it belongs)
-- ============================================================================
task.spawn(function()
	local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
	local SMOOTH = Enum.SurfaceType.Smooth
	local function flagPart(p)
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic
		p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
		p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
		return p
	end
	local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
		local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
		local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
		p.CFrame = cf; flagPart(p); p.Parent = model; return p
	end
	local function fuse(model, src, name, color)
		local first = table.remove(src, 1)
		local ok, u = pcall(function() return first:UnionAsync(src) end)
		if ok and typeof(u) == "Instance" then
			first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
			flagPart(u); u.Name = name; u.UsePartColor = true; u.Color = color
			pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
			pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
			pcall(function() u.SmoothingAngle = 60 end)
			u.Parent = model
			return u, nil
		else
			table.insert(src, 1, first)
			for _, p in ipairs(src) do p.Name = name.."Chunk" end
			return nil, tostring(u)
		end
	end
	local function newRoot(model)
		local r = mkPart(model, "Root", BAL, 0.4, 0.4, 0.4, Color3.new(1,1,1), 0, 0, 0); r.Transparency = 1; model.PrimaryPart = r; return r
	end
	local function weldTo(part, target)
		if part and target then
			local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = target; w.Part1 = part; w.Parent = part
		end
		return part
	end
	local EYE_DIA = 0.82
	local function eyes(P, fx, fy, fz)
		for _, sgn in ipairs({ 1, -1 }) do
			local zc = fz * sgn
			P("whitepartofeye", CYL, 0.22, EYE_DIA, EYE_DIA, Color3.fromRGB(16,16,20), fx, fy, zc)
			P("blackpartofeye", CYL, 0.12, EYE_DIA*0.34, EYE_DIA*0.34, Color3.fromRGB(255,255,255), fx + 0.16, fy + EYE_DIA*0.22, zc + EYE_DIA*0.16)
		end
	end
	local function roundedCubeInto(src, P, cx, cy, cz, W, H, D, R, color)
		local iW, iH, iD = W - 2*R, H - 2*R, D - 2*R
		local hW, hH, hD = iW/2, iH/2, iD/2
		local dd = 2*R
		local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = P("b", sh, sx,sy,sz, color, cx+x, cy+y, cz+z, rot) end
		a(BLK, D, iH, iW, 0,0,0)
		a(BLK, iD, H, iW, 0,0,0)
		a(BLK, iD, iH, W, 0,0,0)
		for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
			a(BAL, dd,dd,dd, c[1]*hD, c[2]*hH, c[3]*hW)
		end
		for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do
			a(CYL, iD, dd, dd, 0, e[1]*hH, e[2]*hW)
			a(CYL, iH, dd, dd, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0,0,math.rad(90)))
			a(CYL, iW, dd, dd, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0,math.rad(90),0))
		end
	end
	-- shared chunky body dims (IDENTICAL to the bunny) + display scale
	local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

	-- ============================================================================
	-- STEGOSAURUS -- same rounded-cube body + face + feet as the bunny; bunny
	-- accessories (ears/whiskers/florets/white tail) removed; back plates + a
	-- thagomizer tail added instead.
	-- ============================================================================
	local function buildStegosaurus()
		local s = PSS
		local m = Instance.new("Model"); m.Name = "Stegosaurus"; m.Parent = Workspace
		local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
		newRoot(m)
		-- dino palette: turquoise body, coral plates, cream belly/spikes, darker-teal freckles, dark accents
		local BODY  = Color3.fromRGB(72,190,180)    -- teal / turquoise body
		local BELLY = Color3.fromRGB(214,242,236)   -- pale mint belly + muzzle
		local PLATE = Color3.fromRGB(255,140,90)     -- contrasting coral plates (pop)
		local CREAM = Color3.fromRGB(245,238,214)    -- bone spike tips
		local SPOT  = Color3.fromRGB(48,150,142)     -- darker-teal back freckles
		local DARK  = Color3.fromRGB(34,28,34)       -- eyes / nostrils / mouth

		-- BODY: UNCHANGED rounded-cube union construction (only the colour differs)
		local src = {}
		roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
		local body, err = fuse(m, src, "BodyUnion", BODY)

		-- FEET: 4 stubby feet (front + back pairs)
		P("Foot", BLK, 0.95,0.8,0.95, BODY,  0.95,-1.55, 0.78)
		P("Foot", BLK, 0.95,0.8,0.95, BODY,  0.95,-1.55,-0.78)
		P("Foot", BLK, 0.95,0.8,0.95, BODY, -0.95,-1.55, 0.78)
		P("Foot", BLK, 0.95,0.8,0.95, BODY, -0.95,-1.55,-0.78)

		-- BELLY: a pale patch low on the front (below the face)
		weldTo(P("Belly", BAL, 0.45,1.0,1.9, BELLY, 1.45,-1.15,0), body)

		-- FACE: clustered LOW + CENTERED on the front (+X). Big forward eyes CLOSE together (white eyeball +
		-- dark pupil + glint), a small rounded snout w/ tiny nostrils, and a little happy open mouth w/ teeth.
		local WHITE = Color3.fromRGB(250,250,250)
		for _, sgn in ipairs({ 1, -1 }) do
			local zc = 0.5 * sgn  -- eyes close together
			weldTo(P("whitepartofeye", CYL, 0.20, 0.86, 0.86, WHITE, 1.70, 0.18, zc), body)        -- white eyeball (flat disc, forward)
			weldTo(P("blackpartofeye", CYL, 0.26, 0.52, 0.52, DARK,  1.78, 0.15, zc), body)        -- dark pupil, proud of the white
			weldTo(P("Glint",          CYL, 0.12, 0.20, 0.20, WHITE, 1.92, 0.33, zc + 0.12), body) -- bright glint dot
		end
		weldTo(P("Snout", BAL, 0.5,0.58,0.95, BELLY, 1.78,-0.34,0), body)                          -- small rounded snout (below/between eyes)
		weldTo(P("Nostril", BAL, 0.12,0.12,0.12, DARK, 1.99,-0.22, 0.16), body)                    -- tiny nostril dots
		weldTo(P("Nostril", BAL, 0.12,0.12,0.12, DARK, 1.99,-0.22,-0.16), body)
		weldTo(P("MouthOpen", BAL, 0.26,0.34,0.66, Color3.fromRGB(70,40,46), 1.80,-0.64,0), body)  -- little happy open mouth
		weldTo(P("Tooth", BAL, 0.1,0.14,0.1, WHITE, 1.96,-0.54, 0.16), body)                       -- small cute teeth
		weldTo(P("Tooth", BAL, 0.1,0.14,0.1, WHITE, 1.96,-0.54,-0.16), body)

		-- BACK PLATES: 6 SEPARATE thin upright leaf plates down the top-center of the back (NOT fused --
		-- distinct flat fins). Each plate is a BLOCK (NOT a ball): broad along X (w = front-back), TALL
		-- (Y = h), and THIN in Z (0.12) so it stands up like a flat plate, not a round lump. Biggest in the
		-- middle, smaller toward head + tail; evenly spaced just behind the head -> base of tail (z=0).
		for _, pd in ipairs({ {0.95,0.85}, {0.45,1.2}, {-0.05,1.5}, {-0.55,1.5}, {-1.05,1.2}, {-1.55,0.85} }) do
			local px, h = pd[1], pd[2]
			local w = 0.5 + h * 0.28  -- leaf width along X (front-back); taller plates = wider
			weldTo(P("Plate", BLK, w, h, 0.12, PLATE, px, 1.55 + h * 0.5, 0), body)  -- X=w, Y=h, Z=0.12 (thin = stands up flat)
		end

		-- BACK FRECKLES: a few darker-teal spots for reptile texture
		for _, sp in ipairs({ {0.7,1.25,0.95}, {-0.4,1.4,-0.9}, {0.1,1.0,1.05}, {-1.0,1.05,0.75}, {0.95,1.1,-0.95} }) do
			weldTo(P("Spot", BAL, 0.34,0.3,0.18, SPOT, sp[1], sp[2], sp[3]), body)
		end

		-- TAIL: a short thick nub off the BACK (-X) tapering to a blunt thagomizer (cream tips)
		weldTo(P("Tail", BAL, 1.1,1.0,1.1,   BODY, -1.7,-0.05,0), body)
		weldTo(P("Tail", BAL, 0.72,0.66,0.72, BODY, -2.4,0.12,0), body)
		weldTo(P("Spike", BAL, 0.42,0.42,0.42, CREAM, -2.85,0.45, 0.22), body)
		weldTo(P("Spike", BAL, 0.42,0.42,0.42, CREAM, -2.85,0.45,-0.22), body)
		weldTo(P("Spike", BAL, 0.40,0.40,0.40, CREAM, -2.98,0.20,0), body)

		return m, err
	end

	local ok, model, err = pcall(buildStegosaurus)
	if ok and model then
		publish(model, "StegosaurusTemplate", err)
	else
		warn("[DinoPetTemplates] Stegosaurus build error: " .. tostring(model or err))
	end
end)

-- ============================================================================
-- Velociraptor -- helpers + build fn extracted VERBATIM from Velociraptor.server.luau
-- (its hatch/gameplay half stays in the Dino Realm where it belongs)
-- ============================================================================
task.spawn(function()
	local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
	local SMOOTH = Enum.SurfaceType.Smooth
	local function flagPart(p)
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic
		p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
		p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
		return p
	end
	local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
		local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
		local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
		p.CFrame = cf; flagPart(p); p.Parent = model; return p
	end
	local function fuse(model, src, name, color)
		local first = table.remove(src, 1)
		local ok, u = pcall(function() return first:UnionAsync(src) end)
		if ok and typeof(u) == "Instance" then
			first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
			flagPart(u); u.Name = name; u.UsePartColor = true; u.Color = color
			pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
			pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
			pcall(function() u.SmoothingAngle = 60 end)
			u.Parent = model
			return u, nil
		else
			table.insert(src, 1, first)
			for _, p in ipairs(src) do p.Name = name.."Chunk" end
			return nil, tostring(u)
		end
	end
	local function newRoot(model)
		local r = mkPart(model, "Root", BAL, 0.4, 0.4, 0.4, Color3.new(1,1,1), 0, 0, 0); r.Transparency = 1; model.PrimaryPart = r; return r
	end
	local function weldTo(part, target)
		if part and target then
			local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = target; w.Part1 = part; w.Parent = part
		end
		return part
	end
	local function roundedCubeInto(src, P, cx, cy, cz, W, H, D, R, color)
		local iW, iH, iD = W - 2*R, H - 2*R, D - 2*R
		local hW, hH, hD = iW/2, iH/2, iD/2
		local dd = 2*R
		local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = P("b", sh, sx,sy,sz, color, cx+x, cy+y, cz+z, rot) end
		a(BLK, D, iH, iW, 0,0,0)
		a(BLK, iD, H, iW, 0,0,0)
		a(BLK, iD, iH, W, 0,0,0)
		for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
			a(BAL, dd,dd,dd, c[1]*hD, c[2]*hH, c[3]*hW)
		end
		for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do
			a(CYL, iD, dd, dd, 0, e[1]*hH, e[2]*hW)
			a(CYL, iH, dd, dd, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0,0,math.rad(90)))
			a(CYL, iW, dd, dd, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0,math.rad(90),0))
		end
	end
	-- shared chunky body dims (IDENTICAL to the stego/bunny) + display scale
	local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

	-- ============================================================================
	-- VELOCIRAPTOR -- same rounded-cube body + flat-disc face + 4 feet as the stego;
	-- stego plates/spikes removed; snout/teeth/brow/crest/tail/arms/sickle-claws added.
	-- ============================================================================
	local function buildVelociraptor()
		local s = PSS
		local m = Instance.new("Model"); m.Name = "Velociraptor"; m.Parent = Workspace
		local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
		newRoot(m)
		-- raptor palette
		local BODY  = Color3.fromRGB(140,148,156)  -- cool grey
		local BELLY = Color3.fromRGB(238,232,212)   -- cream belly + snout underside
		local STRIPE= Color3.fromRGB(70,120,210)    -- blue stripe + eye markings + crest
		local DARK  = Color3.fromRGB(30,28,34)      -- pupils / nostrils
		local CLAW  = Color3.fromRGB(26,24,28)      -- dark claws
		local TEETH = Color3.fromRGB(248,244,230)   -- pointed teeth
		local AMBER = Color3.fromRGB(255,196,70)    -- amber iris accent
		local WHITE = Color3.fromRGB(250,250,250)

		-- BODY: UNCHANGED rounded-cube union (only the colour differs)
		local src = {}
		roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
		local body, err = fuse(m, src, "BodyUnion", BODY)

		-- FEET: 4 stubby feet, each with a raised "sickle claw" toe
		for _, fp in ipairs({ {0.95,0.78}, {0.95,-0.78}, {-0.95,0.78}, {-0.95,-0.78} }) do
			P("Foot", BLK, 0.95,0.8,0.95, BODY, fp[1],-1.55,fp[2])
			weldTo(P("SickleClaw", CYL, 0.55,0.16,0.16, CLAW, fp[1]+0.55, -1.35, fp[2], CFrame.Angles(0,0,math.rad(38))), body)
		end

		-- BELLY: pale patch low on the front
		weldTo(P("Belly", BAL, 0.45,1.0,1.9, BELLY, 1.45,-1.15,0), body)

		-- BLUE STRIPE along the TOP spine only (clean + flush). The side stripes were removed -- on the
		-- rounded cube they poked out near the curved edges and read as a random blue blob on the side.
		weldTo(P("Stripe", BLK, 3.0,0.16,0.7, STRIPE, -0.2,1.78,0), body)

		-- FACE: big flat-disc eyes low-center (+X): white eyeball + amber iris + dark pupil + glint,
		-- with a blue marking + an angled brow ridge over each eye (cute-but-fierce).
		for _, sgn in ipairs({1,-1}) do
			local zc = 0.5 * sgn
			weldTo(P("EyeMark", BAL, 0.42,0.5,0.72, STRIPE, 1.64,0.55,zc), body)                                   -- blue marking over the eye
			weldTo(P("Brow",    BLK, 0.55,0.16,0.72, DARK, 1.8,0.56,zc, CFrame.Angles(0,0,math.rad(sgn*16))), body) -- angled brow ridge
			weldTo(P("whitepartofeye", CYL, 0.20, 0.82, 0.82, WHITE, 1.70, 0.18, zc), body)                         -- white eyeball (flat disc)
			weldTo(P("EyeAmber",       CYL, 0.22, 0.60, 0.60, AMBER, 1.74, 0.16, zc), body)                         -- amber iris ring
			weldTo(P("blackpartofeye", CYL, 0.26, 0.40, 0.40, DARK,  1.78, 0.15, zc), body)                         -- dark pupil, proud
			weldTo(P("Glint",          CYL, 0.12, 0.18, 0.18, WHITE, 1.92, 0.32, zc + 0.12), body)                  -- bright glint
		end

		-- SNOUT: a longer, narrower muzzle pushing forward (+X) -- grey top, cream underside
		weldTo(P("Snout",      BAL, 1.5,0.7,0.85, BODY,  2.3,-0.22,0), body)
		weldTo(P("SnoutUnder", BAL, 1.25,0.4,0.7, BELLY, 2.3,-0.5,0), body)
		weldTo(P("Nostril", BAL, 0.12,0.12,0.12, DARK, 2.98,-0.08, 0.18), body)
		weldTo(P("Nostril", BAL, 0.12,0.12,0.12, DARK, 2.98,-0.08,-0.18), body)
		-- small head crest / brow ridge between the eyes
		weldTo(P("Crest", BLK, 0.55,0.24,0.55, STRIPE, 1.5,0.98,0, CFrame.Angles(0,0,math.rad(22))), body)
		-- open mouth + tiny pointed teeth (upper + lower rows)
		weldTo(P("MouthOpen", BAL, 0.95,0.32,0.62, Color3.fromRGB(60,34,40), 2.55,-0.5,0), body)
		for _, tz in ipairs({ -0.26, -0.09, 0.09, 0.26 }) do
			weldTo(P("Tooth", CYL, 0.22,0.1,0.1, TEETH, 2.82,-0.4, tz, CFrame.Angles(0,0,math.rad(90))), body)  -- upper
			weldTo(P("Tooth", CYL, 0.18,0.09,0.09, TEETH, 2.78,-0.6, tz, CFrame.Angles(0,0,math.rad(90))), body) -- lower
		end

		-- ARMS: 2 small NEAT arms tucked flat against the front sides with tiny clawed hands (grey, kept tight)
		for _, sgn in ipairs({1,-1}) do
			weldTo(P("Arm",  BLK, 0.26,0.6,0.26, BODY, 1.35,-0.45,1.05*sgn, CFrame.Angles(math.rad(18),0,0)), body)
			weldTo(P("Hand", BAL, 0.3,0.28,0.28, BODY, 1.55,-0.8,1.08*sgn), body)
			for _, cz in ipairs({ -0.1, 0, 0.1 }) do
				weldTo(P("Claw", CYL, 0.24,0.06,0.06, CLAW, 1.78,-0.84,1.08*sgn + cz, CFrame.Angles(0,math.rad(90),0)), body)
			end
		end

		-- TAIL: a long tapering tail off the BACK (-X), held straight, no spikes; blue stripe continues onto it
		weldTo(P("Tail", BAL, 1.3,1.1,1.1,  BODY, -1.9,0.0,0), body)
		weldTo(P("Tail", BAL, 1.0,0.8,0.8,  BODY, -2.8,0.14,0), body)
		weldTo(P("Tail", BAL, 0.7,0.55,0.55, BODY, -3.6,0.26,0), body)
		weldTo(P("TailTip", BAL, 0.46,0.38,0.38, BODY, -4.25,0.36,0), body)
		weldTo(P("Stripe", BLK, 2.6,0.14,0.5, STRIPE, -2.9,0.62,0), body)

		return m, err
	end

	local ok, model, err = pcall(buildVelociraptor)
	if ok and model then
		publish(model, "VelociraptorTemplate", err)
	else
		warn("[DinoPetTemplates] Velociraptor build error: " .. tostring(model or err))
	end
end)

-- ============================================================================
-- Shark -- helpers + build fn extracted VERBATIM from Shark.server.luau
-- (its hatch/gameplay half stays in the Dino Realm where it belongs)
-- ============================================================================
task.spawn(function()
	local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
	local SMOOTH = Enum.SurfaceType.Smooth
	local function flagPart(p)
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic
		p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
		p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
		return p
	end
	local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
		local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
		local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
		p.CFrame = cf; flagPart(p); p.Parent = model; return p
	end
	local function fuse(model, src, name, color)
		local first = table.remove(src, 1)
		local ok, u = pcall(function() return first:UnionAsync(src) end)
		if ok and typeof(u) == "Instance" then
			first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
			flagPart(u); u.Name = name; u.UsePartColor = true; u.Color = color
			pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
			pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
			pcall(function() u.SmoothingAngle = 60 end)
			u.Parent = model
			return u, nil
		else
			table.insert(src, 1, first)
			for _, p in ipairs(src) do p.Name = name.."Chunk" end
			return nil, tostring(u)
		end
	end
	local function newRoot(model)
		local r = mkPart(model, "Root", BAL, 0.4, 0.4, 0.4, Color3.new(1,1,1), 0, 0, 0); r.Transparency = 1; model.PrimaryPart = r; return r
	end
	local function weldTo(part, target)
		if part and target then
			local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = target; w.Part1 = part; w.Parent = part
		end
		return part
	end
	local function roundedCubeInto(src, P, cx, cy, cz, W, H, D, R, color)
		local iW, iH, iD = W - 2*R, H - 2*R, D - 2*R
		local hW, hH, hD = iW/2, iH/2, iD/2
		local dd = 2*R
		local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = P("b", sh, sx,sy,sz, color, cx+x, cy+y, cz+z, rot) end
		a(BLK, D, iH, iW, 0,0,0)
		a(BLK, iD, H, iW, 0,0,0)
		a(BLK, iD, iH, W, 0,0,0)
		for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
			a(BAL, dd,dd,dd, c[1]*hD, c[2]*hH, c[3]*hW)
		end
		for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do
			a(CYL, iD, dd, dd, 0, e[1]*hH, e[2]*hW)
			a(CYL, iH, dd, dd, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0,0,math.rad(90)))
			a(CYL, iW, dd, dd, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0,math.rad(90),0))
		end
	end
	-- shared chunky body dims (IDENTICAL to the stego/raptor) + display scale
	local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

	-- ============================================================================
	-- SHARK -- same rounded-cube body + flat-disc face + 4 feet as the raptor;
	-- raptor snout/arms/tail removed; shark dorsal/smile/pectorals/tail/gills added.
	-- ============================================================================
	local function buildShark()
		local s = PSS
		local m = Instance.new("Model"); m.Name = "Shark"; m.Parent = Workspace
		local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
		local function W(n,sx,sy,sz,c,x,y,z,r) -- scaled WedgePart (triangular teeth)
			local p = Instance.new("WedgePart"); p.Name = n; p.Size = Vector3.new(sx*s,sy*s,sz*s); p.Color = c
			local cf = CFrame.new(x*s,y*s,z*s); if r then cf = cf*r end; p.CFrame = cf; flagPart(p); p.Parent = m; return p
		end
		newRoot(m)
		-- shark/megalodon palette
		local BODY  = Color3.fromRGB(110,130,150)  -- classic shark blue-grey
		local BELLY = Color3.fromRGB(236,230,208)   -- cream/white belly + chin
		local FIN   = Color3.fromRGB(84,100,120)    -- slightly darker grey fins
		local DARK  = Color3.fromRGB(28,26,32)      -- pupils / gills
		local MOUTH = Color3.fromRGB(70,40,46)       -- dark mouth interior
		local TEETH = Color3.fromRGB(250,250,246)    -- white teeth
		local WHITE = Color3.fromRGB(250,250,250)

		-- BODY: UNCHANGED rounded-cube union (only the colour differs)
		local src = {}
		roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
		local body, err = fuse(m, src, "BodyUnion", BODY)

		-- FEET: 4 stubby feet/fins (same as the raptor)
		for _, fp in ipairs({ {0.95,0.78}, {0.95,-0.78}, {-0.95,0.78}, {-0.95,-0.78} }) do
			weldTo(P("Foot", BLK, 0.95,0.8,0.95, FIN, fp[1],-1.55,fp[2]), body)
		end

		-- BELLY + CHIN: pale cream patch low on the front
		weldTo(P("Belly", BAL, 0.5,1.2,2.1, BELLY, 1.35,-1.05,0), body)

		-- FACE: big flat-disc eyes low-center (+X): white eyeball + dark pupil + glint (same as the others)
		for _, sgn in ipairs({1,-1}) do
			local zc = 0.6 * sgn
			weldTo(P("whitepartofeye", CYL, 0.20, 0.98, 0.98, WHITE, 1.66, 0.42, zc), body) -- big flat white eye
			weldTo(P("blackpartofeye", CYL, 0.26, 0.52, 0.52, DARK,  1.74, 0.40, zc), body) -- big dark pupil
			weldTo(P("Glint",          CYL, 0.12, 0.22, 0.22, WHITE, 1.90, 0.58, zc + 0.12), body) -- bright glint
		end

		-- SMILE: a wide happy open mouth on the front face, with a row of small white triangular teeth (top + bottom)
		weldTo(P("Mouth", BAL, 0.7,0.7,2.1, MOUTH, 1.45,-0.5,0), body)
		weldTo(P("Chin",  BAL, 0.7,0.55,1.7, BELLY, 1.3,-0.98,0), body)
		for _, tz in ipairs({ -0.8, -0.4, 0, 0.4, 0.8 }) do
			weldTo(W("Tooth", 0.16, 0.30, 0.26, TEETH, 1.9, -0.24, tz, CFrame.Angles(math.rad(180),0,0)), body) -- upper (point down)
			weldTo(W("Tooth", 0.16, 0.26, 0.24, TEETH, 1.9, -0.78, tz), body)                                   -- lower (point up)
		end

		-- DORSAL FIN: the classic big shark triangle standing up on top, slightly rounded (flattened ball), leaning back
		weldTo(P("Dorsal", BAL, 1.7,2.7,0.5, FIN, -0.1,1.4,0, CFrame.Angles(0,0,math.rad(-16))), body)

		-- PECTORAL FINS: 2 fins sticking out the lower sides, angled out + back
		for _, sgn in ipairs({1,-1}) do
			weldTo(P("Pectoral", BAL, 1.4,0.4,1.6, FIN, 0.3,-0.95,1.35*sgn, CFrame.Angles(math.rad(22*sgn),0,math.rad(8))), body)
		end

		-- TAIL: a vertical forked tail off the BACK (-X) -- taller TOP lobe + shorter bottom lobe
		weldTo(P("TailBase", BAL, 1.3,1.0,0.8, BODY, -1.5,0.1,0), body)                                       -- embeds into the body
		weldTo(P("TailTop",  BAL, 0.5,1.9,1.0, FIN, -2.05,0.85,0, CFrame.Angles(0,0,math.rad(20))), body)     -- tall top lobe (overlaps base)
		weldTo(P("TailBot",  BAL, 0.5,1.15,0.85, FIN, -2.0,-0.55,0, CFrame.Angles(0,0,math.rad(-12))), body)  -- shorter bottom lobe

		-- GILL LINES: 3 thin dark slits on each side
		for _, sgn in ipairs({1,-1}) do
			for _, gx in ipairs({ 0.7, 0.35, 0.0 }) do
				weldTo(P("Gill", BLK, 0.1,0.95,0.14, DARK, gx,0.05,1.42*sgn, CFrame.Angles(0,0,math.rad(10))), body)
			end
		end

		return m, err
	end

	local ok, model, err = pcall(buildShark)
	if ok and model then
		publish(model, "SharkTemplate", err)
	else
		warn("[DinoPetTemplates] Shark build error: " .. tostring(model or err))
	end
end)

-- ============================================================================
-- Triceratops -- helpers + build fn extracted VERBATIM from Triceratops.server.luau
-- (its hatch/gameplay half stays in the Dino Realm where it belongs)
-- ============================================================================
task.spawn(function()
	local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
	local SMOOTH = Enum.SurfaceType.Smooth
	local function flagPart(p)
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic
		p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
		p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
		return p
	end
	local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
		local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
		local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
		p.CFrame = cf; flagPart(p); p.Parent = model; return p
	end
	local function fuse(model, src, name, color)
		local first = table.remove(src, 1)
		local ok, u = pcall(function() return first:UnionAsync(src) end)
		if ok and typeof(u) == "Instance" then
			first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
			flagPart(u); u.Name = name; u.UsePartColor = true; u.Color = color
			pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
			pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
			pcall(function() u.SmoothingAngle = 60 end)
			u.Parent = model
			return u, nil
		else
			table.insert(src, 1, first)
			for _, p in ipairs(src) do p.Name = name.."Chunk" end
			return nil, tostring(u)
		end
	end
	local function newRoot(model)
		local r = mkPart(model, "Root", BAL, 0.4, 0.4, 0.4, Color3.new(1,1,1), 0, 0, 0); r.Transparency = 1; model.PrimaryPart = r; return r
	end
	local function weldTo(part, target)
		if part and target then
			local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = target; w.Part1 = part; w.Parent = part
		end
		return part
	end
	local function roundedCubeInto(src, P, cx, cy, cz, W, H, D, R, color)
		local iW, iH, iD = W - 2*R, H - 2*R, D - 2*R
		local hW, hH, hD = iW/2, iH/2, iD/2
		local dd = 2*R
		local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = P("b", sh, sx,sy,sz, color, cx+x, cy+y, cz+z, rot) end
		a(BLK, D, iH, iW, 0,0,0)
		a(BLK, iD, H, iW, 0,0,0)
		a(BLK, iD, iH, W, 0,0,0)
		for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
			a(BAL, dd,dd,dd, c[1]*hD, c[2]*hH, c[3]*hW)
		end
		for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do
			a(CYL, iD, dd, dd, 0, e[1]*hH, e[2]*hW)
			a(CYL, iH, dd, dd, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0,0,math.rad(90)))
			a(CYL, iW, dd, dd, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0,math.rad(90),0))
		end
	end
	-- shared chunky body dims (IDENTICAL to the stego/raptor/shark) + display scale
	local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

	-- ============================================================================
	-- TRICERATOPS -- same rounded-cube body + flat-disc face + 4 feet;
	-- shark fins removed; neck frill + 3 horns + beak + stubby tail added.
	-- ============================================================================
	local function buildTriceratops()
		local s = PSS
		local m = Instance.new("Model"); m.Name = "Triceratops"; m.Parent = Workspace
		local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
		newRoot(m)
		-- triceratops palette
		local BODY  = Color3.fromRGB(143,181,104)  -- soft sage / olive green
		local FRILL = Color3.fromRGB(111,154,78)    -- darker green frill
		local BELLY = Color3.fromRGB(200,220,165)   -- lighter cream-green belly
		local HORN  = Color3.fromRGB(236,225,196)   -- cream / bone horns
		local BEAK  = Color3.fromRGB(214,196,150)   -- tan / bone beak
		local DARK  = Color3.fromRGB(28,26,32)      -- pupils / nostrils
		local MOUTH = Color3.fromRGB(90,58,52)       -- smile
		local WHITE = Color3.fromRGB(250,250,250)

		-- BODY: UNCHANGED rounded-cube union (only the colour differs)
		local src = {}
		roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
		local body, err = fuse(m, src, "BodyUnion", BODY)

		-- ===== tapered-cone horn helper: 3 cylinder segments (thick base -> thin) + a rounded ball tip, laid along `dir`.
		-- The base end sits at (bx,by,bz) so sinking that point into the face/frill embeds the horn (no float). =====
		local function horn(nm, bx,by,bz, dir, len, baseR, tipR)
			dir = dir.Unit
			local rot = CFrame.lookAt(Vector3.new(0,0,0), dir) * CFrame.Angles(0, math.rad(90), 0) -- CYL length (local X) -> along dir
			local segN = 3
			for i = 0, segN-1 do
				local r = baseR + (tipR - baseR) * (i / (segN - 1))
				local c = Vector3.new(bx,by,bz) + dir * (len * (i + 0.5) / segN)
				weldTo(P(nm, CYL, len/segN + 0.08, r*2, r*2, HORN, c.X, c.Y, c.Z, rot), body) -- +0.08 overlap so segments merge smoothly
			end
			local tip = Vector3.new(bx,by,bz) + dir * len
			weldTo(P(nm.."Tip", BAL, tipR*2, tipR*2, tipR*2, HORN, tip.X, tip.Y, tip.Z), body) -- rounded point
		end

		-- NECK FRILL: a wide rounded shield behind/above the head, leaning back, framing the face. Built FIRST so the
		-- eyes/horns/beak sit in front of it. SCALLOPED edge = 5 rounded bumps placed ON the (leaned) frill's top rim --
		-- transformed by the frill's own CFrame so they sit on the shield + overlap it (NOT floating above the body).
		local frillCF = CFrame.new(0.15, 1.0, 0) * CFrame.Angles(0,0,math.rad(-20))
		weldTo(P("Frill", BAL, 0.6, 2.9, 3.9, FRILL, frillCF.X, frillCF.Y, frillCF.Z, frillCF - frillCF.Position), body)
		for _, a in ipairs({ -60, -30, 0, 30, 60 }) do
			local wp = frillCF * CFrame.new(0, math.cos(math.rad(a)) * 1.3, math.sin(math.rad(a)) * 1.7) -- on the leaned rim, just inside the edge
			weldTo(P("FrillScallop", BAL, 0.7, 1.05, 1.05, FRILL, wp.X, wp.Y, wp.Z), body)
		end

		-- FEET: 4 stubby feet (same as the others)
		for _, fp in ipairs({ {0.95,0.78}, {0.95,-0.78}, {-0.95,0.78}, {-0.95,-0.78} }) do
			weldTo(P("Foot", BLK, 0.95,0.8,0.95, BODY, fp[1],-1.55,fp[2]), body)
		end

		-- BELLY: lighter cream-green panel low on the front
		weldTo(P("Belly", BAL, 0.5,1.3,2.2, BELLY, 1.3,-1.0,0), body)

		-- FACE: two BIG glossy eyes close together (+X front): white eyeball + dark pupil + bright glint
		for _, sgn in ipairs({1,-1}) do
			local zc = 0.42 * sgn -- close together
			weldTo(P("whitepartofeye", CYL, 0.20, 1.02, 1.02, WHITE, 1.66, 0.08, zc), body)
			weldTo(P("blackpartofeye", CYL, 0.26, 0.56, 0.56, DARK,  1.74, 0.06, zc), body)
			weldTo(P("Glint",          CYL, 0.12, 0.22, 0.22, WHITE, 1.90, 0.24, zc + 0.12), body)
		end

		-- THREE TAPERED HORNS (cream/bone). Brow horns ~1.4x the nose horn; bases sunk into the upper face / snout.
		horn("BrowHorn",  1.35, 0.75,  0.45, Vector3.new(0.45, 1.0,  0.34), 2.0, 0.40, 0.10) -- right brow: up + forward + out
		horn("BrowHorn",  1.35, 0.75, -0.45, Vector3.new(0.45, 1.0, -0.34), 2.0, 0.40, 0.10) -- left  brow
		horn("NoseHorn",  1.45,-0.10,  0.00, Vector3.new(0.62, 1.0,  0.00), 1.4, 0.50, 0.14) -- nose: shorter + thicker, up-forward

		-- BEAK: a small parrot-like beak (tan) at the front of the mouth, with a hooked tip + 2 nostril dots
		weldTo(P("BeakTop",  BAL, 0.8,0.5,0.8, BEAK, 1.68,-0.35,0), body)
		weldTo(P("BeakHook", BAL, 0.45,0.45,0.55, BEAK, 1.98,-0.55,0), body)  -- the hooked point curving down
		weldTo(P("BeakLow",  BAL, 0.55,0.36,0.62, BEAK, 1.6,-0.66,0), body)
		for _, sgn in ipairs({1,-1}) do
			weldTo(P("Nostril", BAL, 0.17,0.17,0.17, DARK, 1.98,-0.28,0.2*sgn), body) -- 2 tiny nostril dots
		end
		-- a small happy SMILE curve just below the beak
		weldTo(P("Smile", BAL, 0.35,0.22,1.15, MOUTH, 1.5,-0.95,0), body)

		-- TAIL: a short stubby tail off the BACK (-X)
		weldTo(P("Tail", BAL, 1.1,0.95,0.95, BODY, -2.0,-0.1,0), body)
		weldTo(P("TailTip", BAL, 0.6,0.55,0.55, BODY, -2.7,0.02,0), body)

		return m, err
	end

	local ok, model, err = pcall(buildTriceratops)
	if ok and model then
		publish(model, "TriceratopsTemplate", err)
	else
		warn("[DinoPetTemplates] Triceratops build error: " .. tostring(model or err))
	end
end)

-- ============================================================================
-- Spinosaurus -- helpers + build fn extracted VERBATIM from Spinosaurus.server.luau
-- (its hatch/gameplay half stays in the Dino Realm where it belongs)
-- ============================================================================
task.spawn(function()
	local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
	local SMOOTH = Enum.SurfaceType.Smooth
	local function flagPart(p)
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic
		p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
		p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
		return p
	end
	local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
		local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
		local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
		p.CFrame = cf; flagPart(p); p.Parent = model; return p
	end
	local function fuse(model, src, name, color)
		local first = table.remove(src, 1)
		local ok, u = pcall(function() return first:UnionAsync(src) end)
		if ok and typeof(u) == "Instance" then
			first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
			flagPart(u); u.Name = name; u.UsePartColor = true; u.Color = color
			pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
			pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
			pcall(function() u.SmoothingAngle = 60 end)
			u.Parent = model
			return u, nil
		else
			table.insert(src, 1, first)
			for _, p in ipairs(src) do p.Name = name.."Chunk" end
			return nil, tostring(u)
		end
	end
	local function newRoot(model)
		local r = mkPart(model, "Root", BAL, 0.4, 0.4, 0.4, Color3.new(1,1,1), 0, 0, 0); r.Transparency = 1; model.PrimaryPart = r; return r
	end
	local function weldTo(part, target)
		if part and target then
			local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = target; w.Part1 = part; w.Parent = part
		end
		return part
	end
	local function roundedCubeInto(src, P, cx, cy, cz, W, H, D, R, color)
		local iW, iH, iD = W - 2*R, H - 2*R, D - 2*R
		local hW, hH, hD = iW/2, iH/2, iD/2
		local dd = 2*R
		local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = P("b", sh, sx,sy,sz, color, cx+x, cy+y, cz+z, rot) end
		a(BLK, D, iH, iW, 0,0,0)
		a(BLK, iD, H, iW, 0,0,0)
		a(BLK, iD, iH, W, 0,0,0)
		for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
			a(BAL, dd,dd,dd, c[1]*hD, c[2]*hH, c[3]*hW)
		end
		for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do
			a(CYL, iD, dd, dd, 0, e[1]*hH, e[2]*hW)
			a(CYL, iH, dd, dd, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0,0,math.rad(90)))
			a(CYL, iW, dd, dd, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0,math.rad(90),0))
		end
	end
	local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

	-- ============================================================================
	-- SPINOSAURUS -- same rounded-cube body + flat-disc face + 4 feet; adds the big
	-- back SAIL, the long crocodile snout with teeth, little arms and a tapered tail.
	-- ============================================================================
	local function buildSpinosaurus()
		local s = PSS
		local m = Instance.new("Model"); m.Name = "Spinosaurus"; m.Parent = Workspace
		local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
		newRoot(m)
		-- swamp spinosaurus palette
		local BODY   = Color3.fromRGB(84,112,92)    -- mossy swamp green
		local BELLY  = Color3.fromRGB(198,208,178)   -- pale belly / lower jaw
		local SAIL   = Color3.fromRGB(156,98,82)     -- classic reddish sail
		local SAILDK = Color3.fromRGB(112,68,56)     -- darker sail spines
		local TEETH  = Color3.fromRGB(248,246,236)
		local DARK   = Color3.fromRGB(28,26,32)      -- pupils / nostrils
		local MOUTH  = Color3.fromRGB(70,44,46)
		local WHITE  = Color3.fromRGB(250,250,250)

		-- BODY: UNCHANGED rounded-cube union (only the colour differs)
		local src = {}
		roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
		local body, err = fuse(m, src, "BodyUnion", BODY)

		-- SAIL: the signature -- a big rounded fan on top (+Y) running front->back (X), thin side-to-side (Z),
		-- base sunk into the back. Built FIRST so the head sits in front of it.
		weldTo(P("Sail", BAL, 3.4, 2.8, 0.5, SAIL, -0.1, 1.7, 0), body)
		for _, sx0 in ipairs({ -1.15, -0.45, 0.3, 1.05 }) do -- darker spine ridges across the sail
			weldTo(P("Spine", CYL, 2.5, 0.16, 0.16, SAILDK, sx0, 1.55, 0.2, CFrame.Angles(0,0,math.rad(90))), body)
		end

		-- FEET: 4 stubby feet
		for _, fp in ipairs({ {0.95,0.78}, {0.95,-0.78}, {-0.95,0.78}, {-0.95,-0.78} }) do
			weldTo(P("Foot", BLK, 0.95,0.85,0.95, BODY, fp[1],-1.55,fp[2]), body)
		end

		-- BELLY: pale patch low on the front
		weldTo(P("Belly", BAL, 0.5,1.2,2.1, BELLY, 1.3,-1.05,0), body)

		-- FACE: big flat-disc eyes (+X front), set a bit high above the long snout
		for _, sgn in ipairs({1,-1}) do
			local zc = 0.55 * sgn
			weldTo(P("whitepartofeye", CYL, 0.20, 0.86, 0.86, WHITE, 1.66, 0.62, zc), body)
			weldTo(P("blackpartofeye", CYL, 0.26, 0.46, 0.46, DARK,  1.74, 0.60, zc), body)
			weldTo(P("Glint",          CYL, 0.12, 0.20, 0.20, WHITE, 1.90, 0.76, zc + 0.12), body)
		end

		-- SNOUT: a long crocodile-like snout jutting from the front (+X), upper + lower jaw, with teeth
		weldTo(P("SnoutBase", BLK, 0.9,1.1,1.3, BODY, 1.65,-0.15,0), body)         -- connects face -> snout
		weldTo(P("SnoutTop",  BLK, 2.2,0.62,1.0, BODY, 2.75,0.0,0), body)          -- upper jaw
		weldTo(P("SnoutBot",  BLK, 2.0,0.42,0.9, BELLY, 2.65,-0.48,0), body)       -- lower jaw
		weldTo(P("Mouth",     BLK, 1.9,0.18,0.85, MOUTH, 2.65,-0.26,0), body)      -- dark mouth line
		for _, sgn in ipairs({1,-1}) do
			weldTo(P("Nostril", BAL, 0.2,0.2,0.2, DARK, 2.45,0.3,0.22*sgn), body)  -- nostril bumps on top
			for _, tx in ipairs({ 2.1, 2.7, 3.3 }) do                              -- small teeth along each jaw
				weldTo(P("Tooth", BAL, 0.18,0.34,0.18, TEETH, tx, -0.26, 0.42*sgn), body)
			end
		end

		-- ARMS: little forelimbs at the front-lower sides
		for _, sgn in ipairs({1,-1}) do
			weldTo(P("Arm", BAL, 0.5,1.0,0.5, BODY, 1.15,-0.85,1.25*sgn, CFrame.Angles(0,0,math.rad(-12*sgn))), body)
			weldTo(P("Claw", BAL, 0.26,0.4,0.26, DARK, 1.35,-1.45,1.35*sgn), body)
		end

		-- TAIL: a tapered tail off the BACK (-X)
		weldTo(P("Tail",    BAL, 1.6,0.95,1.0, BODY, -2.0,-0.1,0), body)
		weldTo(P("TailTip", BAL, 1.3,0.62,0.7, BODY, -2.95,0.02,0), body)

		return m, err
	end

	local ok, model, err = pcall(buildSpinosaurus)
	if ok and model then
		publish(model, "SpinosaurusTemplate", err)
	else
		warn("[DinoPetTemplates] Spinosaurus build error: " .. tostring(model or err))
	end
end)

-- ============================================================================
-- Tyrannosaurus -- helpers + build fn extracted VERBATIM from Tyrannosaurus.server.luau
-- (its hatch/gameplay half stays in the Dino Realm where it belongs)
-- ============================================================================
task.spawn(function()
	local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
	local SMOOTH = Enum.SurfaceType.Smooth
	local function flagPart(p)
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic
		p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
		p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
		return p
	end
	local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
		local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
		local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
		p.CFrame = cf; flagPart(p); p.Parent = model; return p
	end
	local function fuse(model, src, name, color)
		local first = table.remove(src, 1)
		local ok, u = pcall(function() return first:UnionAsync(src) end)
		if ok and typeof(u) == "Instance" then
			first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
			flagPart(u); u.Name = name; u.UsePartColor = true; u.Color = color
			pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
			pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
			pcall(function() u.SmoothingAngle = 60 end)
			u.Parent = model
			return u, nil
		else
			table.insert(src, 1, first)
			for _, p in ipairs(src) do p.Name = name.."Chunk" end
			return nil, tostring(u)
		end
	end
	local function newRoot(model)
		local r = mkPart(model, "Root", BAL, 0.4, 0.4, 0.4, Color3.new(1,1,1), 0, 0, 0); r.Transparency = 1; model.PrimaryPart = r; return r
	end
	local function weldTo(part, target)
		if part and target then
			local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = target; w.Part1 = part; w.Parent = part
		end
		return part
	end
	local function roundedCubeInto(src, P, cx, cy, cz, W, H, D, R, color)
		local iW, iH, iD = W - 2*R, H - 2*R, D - 2*R
		local hW, hH, hD = iW/2, iH/2, iD/2
		local dd = 2*R
		local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = P("b", sh, sx,sy,sz, color, cx+x, cy+y, cz+z, rot) end
		a(BLK, D, iH, iW, 0,0,0)
		a(BLK, iD, H, iW, 0,0,0)
		a(BLK, iD, iH, W, 0,0,0)
		for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
			a(BAL, dd,dd,dd, c[1]*hD, c[2]*hH, c[3]*hW)
		end
		for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do
			a(CYL, iD, dd, dd, 0, e[1]*hH, e[2]*hW)
			a(CYL, iH, dd, dd, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0,0,math.rad(90)))
			a(CYL, iW, dd, dd, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0,math.rad(90),0))
		end
	end
	local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

	local function buildTyrannosaurus()
		local s = PSS
		local m = Instance.new("Model"); m.Name = "Tyrannosaurus"; m.Parent = Workspace
		local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
		local function W(n,sx,sy,sz,c,x,y,z,r) -- scaled WedgePart for triangular teeth
			local p = Instance.new("WedgePart"); p.Name=n; p.Size=Vector3.new(sx*s,sy*s,sz*s); p.Color=c
			local cf=CFrame.new(x*s,y*s,z*s); if r then cf=cf*r end; p.CFrame=cf; flagPart(p); p.Parent=m; return p
		end
		newRoot(m)
		local BODY  = Color3.fromRGB(122,78,62)    -- earthy red-brown (volcanic)
		local BELLY = Color3.fromRGB(202,182,150)   -- tan belly / lower jaw
		local TEETH = Color3.fromRGB(248,246,236)
		local DARK  = Color3.fromRGB(30,26,24)      -- pupils / claws / nostrils / brow
		local MOUTH = Color3.fromRGB(58,30,28)
		local WHITE = Color3.fromRGB(250,250,250)

		-- BODY
		local src = {}
		roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
		local body, err = fuse(m, src, "BodyUnion", BODY)

		-- BIG ROUNDED HEAD jutting from the front (+X) -- T-Rex signature, kept cute/rounded like the other pets
		weldTo(P("HeadBase", BAL, 1.5,1.95,2.1, BODY, 1.5,0.5,0), body)        -- rounded head joining the body
		weldTo(P("Snout", BAL, 1.9,1.15,1.7, BODY, 2.8,0.2,0), body)          -- rounded upper muzzle
		weldTo(P("Jaw",   BAL, 1.6,0.75,1.55, BELLY, 2.7,-0.6,0), body)       -- rounded lower jaw
		weldTo(P("Mouth", BAL, 1.6,0.32,1.4, MOUTH, 2.78,-0.15,0), body)      -- dark mouth
		for _, sgn in ipairs({1,-1}) do
			weldTo(P("Nostril", BAL, 0.2,0.2,0.2, DARK, 3.5,0.42,0.22*sgn), body) -- nostrils on the snout tip
			for _, tx in ipairs({ 2.4, 3.0, 3.5 }) do                             -- triangular teeth, clean rows
				weldTo(W("Tooth", 0.42,0.3,0.2, TEETH, tx, 0.0, 0.6*sgn, CFrame.Angles(math.rad(180),0,0)), body) -- upper (point down)
				weldTo(W("Tooth", 0.38,0.26,0.18, TEETH, tx, -0.36, 0.56*sgn), body)                              -- lower (point up)
			end
		end

		-- FACE: big flat-disc eyes high + forward on the head, with soft rounded brows
		for _, sgn in ipairs({1,-1}) do
			local zc = 0.68 * sgn
			weldTo(P("Brow", BAL, 0.7,0.5,0.85, BODY, 2.15,1.32,zc), body)                 -- rounded brow bump
			weldTo(P("whitepartofeye", CYL, 0.20, 0.82, 0.82, WHITE, 2.3, 0.98, zc), body)
			weldTo(P("blackpartofeye", CYL, 0.26, 0.46, 0.46, DARK,  2.38, 0.96, zc), body)
			weldTo(P("Glint",          CYL, 0.12, 0.20, 0.20, WHITE, 2.52, 1.12, zc + 0.1), body)
		end

		-- TINY ARMS (the famous little T-Rex arms) at the front-lower sides
		for _, sgn in ipairs({1,-1}) do
			weldTo(P("Arm", BAL, 0.42,0.85,0.42, BODY, 1.2,-0.35,1.3*sgn, CFrame.Angles(0,0,math.rad(-14*sgn))), body)
			weldTo(P("Claw", BAL, 0.22,0.34,0.22, DARK, 1.4,-0.95,1.4*sgn), body)
		end

		-- FEET: 4 stubby feet
		for _, fp in ipairs({ {0.95,0.78}, {0.95,-0.78}, {-0.95,0.78}, {-0.95,-0.78} }) do
			weldTo(P("Foot", BLK, 1.0,0.85,1.0, BODY, fp[1],-1.55,fp[2]), body)
		end

		-- BELLY
		weldTo(P("Belly", BAL, 0.5,1.3,2.1, BELLY, 1.3,-1.05,0), body)

		-- LONG HEAVY TAIL off the BACK (-X), tapering
		weldTo(P("Tail",    BAL, 1.8,1.1,1.2, BODY, -2.0,-0.05,0), body)
		weldTo(P("TailMid", BAL, 1.4,0.85,0.9, BODY, -3.0,0.05,0), body)
		weldTo(P("TailTip", BAL, 1.1,0.58,0.6, BODY, -3.85,0.12,0), body)

		return m, err
	end

	local ok, model, err = pcall(buildTyrannosaurus)
	if ok and model then
		publish(model, "TyrannosaurusTemplate", err)
	else
		warn("[DinoPetTemplates] Tyrannosaurus build error: " .. tostring(model or err))
	end
end)

print("[DinoPetTemplates] all 6 dino templates queued -- cosmetic builds only, no gameplay imported")
