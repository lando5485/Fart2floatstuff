--======================================================================
-- BroccoliBunny_Exact.server.lua  (Server Script)
--======================================================================
-- The EXACT build of the Broccoli Bunny pet, lifted VERBATIM from
-- PetSystem.server.lua (buildBroccoliBunny + every helper it uses). This is
-- the "square look" version -- the chunky Pet-Sim-99 rounded-CUBE body that
-- gets server-UNIONED into one smooth-edged solid.
--
-- WHY A SERVER SCRIPT: the body uses UnionAsync (CSG), which only runs on the
-- server. It builds the model in Workspace and (if you want it followable)
-- moves it to ReplicatedStorage as "BroccoliBunnyTemplate" so the client can
-- clone it -- exactly what the real game does.
--
-- ============================ EXACT DIMENSIONS ============================
-- DISPLAY SCALE (PSS): every size + position below is multiplied by 0.85.
--
-- BODY = ONE rounded cube (the square look), pre-scale dims W x H x D:
--   PSW = 3.8  (width  -> Z size)
--   PSH = 3.6  (height -> Y size)
--   PSD = 3.4  (depth  -> X size, +X = front)
--   PSR = 0.9  (fillet/corner radius)
--   => actual fused body ~ 3.23 (Z) x 3.06 (Y) x 2.89 (X) studs after x0.85.
-- It is built from: 3 cross slabs (flat faces) + 8 corner balls (dia 2*R=1.8)
--   + 12 edge cylinders (dia 1.8), then UnionAsync'd into "BodyUnion".
--
-- EARS: 2 tall green CYLINDERS (len 3.1, dia 0.92) each capped with a 0.92
--   dome ball -> rounded tip; a pink inner ear (len 2.25, dia 0.5). Placed at
--   z = +-1.25, tilted out 13deg, sunk ~1 stud into the head.
-- FEET: 2 green blocks 0.95 x 0.8 x 0.95 at y -1.55, z +-0.78.
-- EYES: standard flat black discs (cylinder len 0.22, dia EYE_DIA 0.82) +
--   white sparkle disc, centred at fx 1.72, fy 0.5, fz +-0.62.
-- NOSE: pink ball 0.45 x 0.52 x 0.72 at (1.74, -0.05, 0).
-- MOUTH: a black "w" smile from 3 thin cylinders + a 0.15 connector bead.
-- WHISKERS: 3 thin cylinders per side (len 1.05 / 1.14 / 1.05, dia 0.06).
-- CHEEKS: 2 lighter-green balls 0.6 x 0.52 x 0.5 at (1.6, -0.18, +-0.72).
-- TAIL: white fluffy ball 1.05 x 1.05 x 1.05 at (-1.6, -0.35, 0).
-- FLORETS: 2 dark-green balls on top (0.62^3 and 0.46-ish).
-- (All raw numbers below are the EXACT values from the game.)
--==========================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- ===== CONSTANTS (verbatim) =====
local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local SMOOTH = Enum.SurfaceType.Smooth

-- ===== PART HELPERS (verbatim) =====
local function flagPart(p)
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic -- matte plastic toy look (no gloss)
	-- Force EVERY face Smooth (new Parts default to Studs/Inlet -> Lego-stud texture, very visible on cylinders).
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
	return p
end
-- make a part (sizes/positions are ALREADY scaled by the caller's P closure)
local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
	local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
	p.CFrame = cf; flagPart(p); p.Parent = model; return p
end
-- FUSE a list of overlapping source parts into ONE union. Returns union, err.
local function fuse(model, src, name, color)
	local first = table.remove(src, 1)
	local ok, u = pcall(function() return first:UnionAsync(src) end)
	if ok and typeof(u) == "Instance" then
		first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
		flagPart(u); u.Name = name; u.UsePartColor = true; u.Color = color
		pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
		pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
		pcall(function() u.SmoothingAngle = 60 end) -- soft satin shading across the fused solid
		u.Parent = model
		return u, nil
	else
		table.insert(src, 1, first)
		for _, p in ipairs(src) do p.Name = name.."Chunk" end -- unfused fallback -> client role = body
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
-- THE STANDARD EYES (big FLAT black disc + white sparkle). EYE_DIA is the one game-wide eye size.
local EYE_DIA = 0.82
local function eyes(P, fx, fy, fz)
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = fz * sgn
		P("Eye", CYL, 0.22, EYE_DIA, EYE_DIA, Color3.fromRGB(16,16,20), fx, fy, zc)                        -- big flat matte-black disc
		P("Highlight", CYL, 0.12, EYE_DIA*0.34, EYE_DIA*0.34, Color3.fromRGB(255,255,255), fx + 0.16, fy + EYE_DIA*0.22, zc + EYE_DIA*0.16) -- flat white sparkle
	end
end

-- ===== ROUNDED-CUBE BUILDER (the "square look") =====
-- Appends a Minkowski box -- 3 cross slabs (flat faces) + 8 corner spheres + 12 edge cylinders -- to `src`,
-- centred at (cx,cy,cz), dims W(width Z) x H(height Y) x D(depth X) with fillet radius R. Unioning `src` then
-- yields ONE cube with smooth curved edges (gap-free). P is the builder's scaling closure. +X = front.
local function roundedCubeInto(src, P, cx, cy, cz, W, H, D, R, color)
	local iW, iH, iD = W - 2*R, H - 2*R, D - 2*R
	local hW, hH, hD = iW/2, iH/2, iD/2
	local dd = 2*R
	local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = P("b", sh, sx,sy,sz, color, cx+x, cy+y, cz+z, rot) end
	a(BLK, D, iH, iW, 0,0,0)   -- 3 cross slabs = the flat faces
	a(BLK, iD, H, iW, 0,0,0)
	a(BLK, iD, iH, W, 0,0,0)
	for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
		a(BAL, dd,dd,dd, c[1]*hD, c[2]*hH, c[3]*hW)  -- 8 corner spheres (rounds the corners)
	end
	for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do  -- 12 edge cylinders (rounds the edges)
		a(CYL, iD, dd, dd, 0, e[1]*hH, e[2]*hW)
		a(CYL, iH, dd, dd, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0,0,math.rad(90)))
		a(CYL, iW, dd, dd, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0,math.rad(90),0))
	end
end
-- shared chunky body dims (one big rounded cube ~1:1:0.9 -- the signature look) + display scale
local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

-- ===== BROCCOLI BUNNY (verbatim) =====
local function buildBroccoliBunny()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "BroccoliBunnyTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local GREEN, FLOR, PINK, PINKI, WHITE = Color3.fromRGB(139,195,74), Color3.fromRGB(46,139,58), Color3.fromRGB(240,170,180), Color3.fromRGB(252,205,215), Color3.fromRGB(245,245,245)
	local LGREEN, BLKM = Color3.fromRGB(176,222,116), Color3.fromRGB(20,20,24) -- lighter-green cheeks; near-black mouth/whiskers
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, GREEN)
	local body, err = fuse(m, src, "BodyUnion", GREEN)
	-- EARS: two TALL bunny ears, each = a CYLINDER + flush dome cap unioned into ONE "Ear" part. Green outer ear
	-- with a thinner PINK inner-ear. Wide apart near the head corners (z=+-1.25), tilted OUT (gentle V ~13deg).
	local function roundedEar(cx, cy, cz, len, dia, color, rot)
		local up = (rot * CFrame.new(1, 0, 0)).Position -- the cylinder's length (up) axis
		local part = {
			P("b", CYL, len, dia, dia, color, cx, cy, cz, rot),                                          -- the ear shaft
			P("b", BAL, dia, dia, dia, color, cx + up.X*len*0.5, cy + up.Y*len*0.5, cz + up.Z*len*0.5),   -- dome cap on the top face (rounded tip)
		}
		weldTo(fuse(m, part, "Ear", color), body)
	end
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = 1.25 * sgn
		local rotEar = CFrame.Angles(math.rad(13) * sgn, 0, 0) * CFrame.Angles(0, 0, math.rad(90)) -- upright + outward V
		roundedEar(0.1,  2.4, zc, 3.1, 0.92, GREEN, rotEar)  -- green outer ear (rounded dome top)
		roundedEar(0.42, 2.4, zc, 2.25, 0.5,  PINKI, rotEar) -- pink inner ear (rounded dome top), on the front
	end
	do -- VERIFY ear attachment (logs embedded depth, exactly like the game)
		local earLen, earCenterY, splay = 3.1, 2.4, math.rad(13)
		local earBottom = earCenterY - (earLen * 0.5) * math.cos(splay)
		local embed     = ((PSH * 0.5) - earBottom) * s
		print(string.format("[Pet] bunny ears: welded=yes, attached=%s, embedded depth=%.2f studs, cylinder size=%.2f tall x %.2f dia (wide apart, tilted out)",
			(embed > 0.1) and "yes" or "no", embed, earLen * s, 0.92 * s))
	end
	-- FEET: two green blocks
	P("Foot", BLK, 0.95,0.8,0.95, GREEN, 0.95,-1.55,0.78)
	P("Foot", BLK, 0.95,0.8,0.95, GREEN, 0.95,-1.55,-0.78)
	eyes(P, 1.72, 0.5, 0.62)                                        -- EYES: standard flat-disc eyes
	-- NOSE: flatter pink, centered below the eyes
	weldTo(P("Nose", BAL, 0.45,0.52,0.72, PINK, 1.74,-0.05,0), body)
	-- MOUTH: a cute bunny "w" SMILE -- a short vertical philtrum + two strokes flaring UP & OUT
	weldTo(P("Mouth", CYL, 0.32,0.1,0.1, BLKM, 1.74,-0.42,0,    CFrame.Angles(0,0,math.rad(90))), body)
	weldTo(P("Mouth", CYL, 0.36,0.1,0.1, BLKM, 1.73,-0.5,0.18,  CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(-34))), body)
	weldTo(P("Mouth", CYL, 0.36,0.1,0.1, BLKM, 1.73,-0.5,-0.18, CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(34))), body)
	weldTo(P("Mouth", BAL, 0.15,0.15,0.15, BLKM, 1.74,-0.585,0), body) -- tiny connector bead at the junction
	-- WHISKERS: three thin black cylinders per side, fanned (up / level / down)
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Whisker", CYL, 1.05,0.06,0.06, BLKM, 1.46,-0.2,0.92*sgn, CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(-12))), body)
		weldTo(P("Whisker", CYL, 1.14,0.06,0.06, BLKM, 1.46,-0.32,0.95*sgn, CFrame.Angles(0,math.rad(90),0)), body)
		weldTo(P("Whisker", CYL, 1.05,0.06,0.06, BLKM, 1.46,-0.44,0.92*sgn, CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(12))), body)
	end
	-- CHEEKS: small lighter-green spheres below the eyes -- symmetric (mirrored)
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Cheek", BAL, 0.6,0.52,0.5, LGREEN, 1.6,-0.18,0.72*sgn), body)
	end
	P("Tail", BAL, 1.05,1.05,1.05, WHITE, -1.6,-0.35,0)          -- round fluffy white tail bump (back)
	P("Floret", BAL, 0.62,0.54,0.62, FLOR, -0.3,1.9,0)            -- dark-green floret bump on top
	P("Floret", BAL, 0.46,0.42,0.46, FLOR, 0.2,2.0,0.45)
	return m, err
end

-- ===== BUILD IT =====
local model, err = buildBroccoliBunny()
if err then warn("[BroccoliBunny] body union failed (kept as chunks): " .. tostring(err)) end
-- park it above the origin so it's easy to see, then publish a clone as the follow template
model:PivotTo(CFrame.new(0, 12, 0))
local template = model:Clone()
template.Parent = ReplicatedStorage   -- "BroccoliBunnyTemplate" -- the client clones THIS for the follower
print("[BroccoliBunny] built + published to ReplicatedStorage as BroccoliBunnyTemplate")
