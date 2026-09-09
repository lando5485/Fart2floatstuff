--======================================================================
-- AFKTokenFarm.server.lua  (Script -> ServerScriptService)
--======================================================================
-- THE AFK TOKEN FARM. A compact token-processing machine that builds itself on EVERY island, centred on a
-- placement point you drop in Studio: a Part (or Attachment) named "AFK Tank".
--
-- ===== VISUAL ONLY =====
-- This file builds geometry and signs. It creates no RemoteEvents, no ProximityPrompts, no ScreenGuis and
-- no currency. The [ E ] console is a SIGN -- nothing is bound to the E key -- and the storage gauge
-- reading 240 / 1,000 is painted on. Nothing here pays anybody anything. When the feature is real the
-- gameplay hooks onto this model; until then a station is scenery that looks like a promise.
--
-- THE ADVERTISED RATE IS +40 TOKENS / HOUR (960 a day, ~6 Normal Pet Crates at 160 each). It appears in
-- exactly ONE place, the plaque on the poster, so there is a single string to change when the real number
-- is decided. Nothing anywhere quotes a per-minute figure.
--
-- ===== THE MARKER IS YOURS AND IS NEVER TOUCHED =====
-- Every other builder in this place hides its marker once it has read it (PetBarn sets Transparency = 1).
-- This one deliberately does NOT: the brief says do not move, rename, delete or modify the placement point,
-- so it is read and left exactly as it was found. The station is laid out so the pad swallows it -- drop the
-- marker at ground level and it ends up inside the dirt plinth. If you would rather it vanish, set the
-- Part's Transparency and CanCollide in Studio; nothing here will fight you.
--
-- ===== WHICH WAY IT FACES =====
-- The marker's own yaw aims the station, so you can spin it in Studio and the signs follow.
--   * marker rotated (any yaw)  -> the station faces the way the marker faces
--   * marker at yaw 0 (default) -> the station turns to face its ISLAND'S CENTRE, which is the direction
--     players walk in from. A marker you dropped and never rotated therefore still aims itself sensibly.
--
-- ===== ONE PER ISLAND =====
-- Every marker gets a station, but two markers on the SAME island get one station and a warning -- the
-- brief rules out doubling up, and a duplicate is far more likely to be a stray copy than an intention.
--
-- ===== SAME MACHINE, DIFFERENT ISLAND =====
-- The machine -- tank, storage, pipes, emblem, signs -- is identical everywhere, so it is recognisable at a
-- glance on island 14 if you learned it on island 1. What changes is the ground it stands on and the litter
-- around it: THEMES below gives each island its own dirt colour, fence style and props. The theme is chosen
-- from the island the marker sits in, with keyword fallbacks (candy / snow / space / volcano / desert /
-- forest) so this same file behaves itself if it is ever dropped into one of the other realms.
--======================================================================

local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- DUPLICATE GUARD. Rojo ADDS, it never overwrites, so a stale copy baked into the place file runs alongside
-- this one -- and two copies means two stations per marker, z-fighting through each other.
if _G.__AFKTokenFarmServer then
	warn("[AFKFarm] a SECOND copy of AFKTokenFarm.server is running -- this one is bailing out. " ..
		"Delete the stale Script in Studio (Explorer > search 'AFKTokenFarm') and re-sync Rojo.")
	return
end
_G.__AFKTokenFarmServer = true

--======================================================================
-- TUNING
--======================================================================
-- THE ONE REMOTE. The station is server-owned (it hands out real currency, so it has to be), but the
-- BANNERS are a client thing -- NotifyCenter owns the top-centre lane and nothing else is allowed to draw
-- there. So the server says what happened and AFKFarmClient decides how to say it.
local AFKFarmEvent = ReplicatedStorage:FindFirstChild("AFKFarmEvent")
if not AFKFarmEvent then
	AFKFarmEvent = Instance.new("RemoteEvent")
	AFKFarmEvent.Name = "AFKFarmEvent"
	AFKFarmEvent.Parent = ReplicatedStorage
end

local MARKER_NAMES = { ["afk tank"] = true, ["afktank"] = true, ["afk_tank"] = true } -- matched lowercased
local MODEL_NAME   = "AFK Token Farm"

local PAD_R      = 12.4   -- the themed apron: the station's whole footprint. Keep it compact
local DECK_R     = 10.4   -- the built platform the machine stands on
local DECK       =  0.73  -- deck surface height above the ground. Machine + signs are built from here
local FENCE_R    =  9.8   -- fence ring, inside the deck edge
local DOOR_HALF  = 44     -- degrees either side of front left OPEN, so the way in is unmistakable
local SCAN_SECS  = 90     -- how long to keep looking for markers as the world streams in

-- ===== WHICH ISLANDS GET A STATION =====
-- ISLAND 1 ONLY. There used to be one on every island that had a marker (ten of them), which meant the same
-- machine appeared over and over the whole way up the tower -- and since a station pays nothing yet (see the
-- VISUAL ONLY note at the top), ten copies of a promise is nine more than the idea needs. One on Bean Farm,
-- where every player starts and will actually see it, says the same thing once.
--
-- A SET, not a number, so adding islands back later is a one-line edit and never a code change:
--   ONLY_ISLANDS = { [1] = true, [7] = true }     -- Bean Farm and Pasta Peak
--   ONLY_ISLANDS = nil                            -- every island with a marker, the old behaviour
local ONLY_ISLANDS = { [1] = true }

-- ===== WHAT HAPPENS TO THE PLACEMENT MARKER =====
-- It is HIDDEN (Transparency 1) and made non-solid (CanCollide false) once it has been read. This file used
-- to leave markers exactly as found, on the grounds that they were yours; the practical result was a stray
-- block sitting in the dirt on every island, and on the islands that no longer get a station there would be
-- nothing to hide it inside at all.
--
-- ONLY THE PROPERTIES ABOVE CHANGE. The part is never renamed, reparented, moved or destroyed, so it stays
-- exactly where you put it in Studio and stays findable in the Explorer -- flip Transparency back to 0 and
-- it is visible again.
--
-- SIZE GUARD: anything bigger than this is not a placement marker, it is scenery (or an island's floor) that
-- happens to share the name -- hiding one of those takes a chunk of the island with it. Over the limit, it
-- is read and left completely alone, with a warning naming it.
local HIDE_MARKERS   = true
local MARKER_MAX_STUD = 24

-- THE RATE, IN ONE PLACE. 40 an hour is 1 token every 90 seconds, which is also why the panel below moves
-- in visible steps rather than crawling: a bar that ticks is a bar you believe.
local TOKENS_PER_HOUR = 40
-- PET: FROST PENGUIN'S "COLD STORAGE" (+12%..+60%). Scales what the farm actually CREDITS, both on the
-- live loop and on a rejoin claim. Applied to the credited tokens only and never to the paidUpTo clock --
-- advancing that by a boosted figure would pay the bonus once and then bill the player for the time it
-- stood for, so the bonus would silently cancel itself out over an hour.
local function petAfkScale(plr, n)
	if not _G.petAbility then return n end
	return math.floor(n * _G.petAbility(plr, "afkRate"))
end
local STORAGE_CAP     = 1000
local function comma(n)
	local out, str = "", tostring(math.floor(tonumber(n) or 0))
	while #str > 3 do out = "," .. str:sub(-3) .. out; str = str:sub(1, -4) end
	return str .. out
end
local STORAGE_CAP_TEXT = comma(STORAGE_CAP)
local HOSE_RANGE      = 34    -- studs from the station before the hose pops off by itself
-- The cord's RESTING width. The pulse below swells off these, so they are declared once rather than typed
-- into the builder and again into the loop -- the classic way a throb ends up drifting away from its base.
local HOSE_W0, HOSE_W1 = 1.45, 1.15

-- ===== THE TWO STATE TABLES, DECLARED HERE AND NOWHERE ELSE =====
-- Up at the top because half a dozen functions below close over them, and a Lua local is only visible to
-- code written AFTER it: a function defined above its declaration silently compiles to a GLOBAL lookup and
-- comes back nil at runtime. Declaring them here is what lets the panel refresher, the pulse and the tick
-- loop all read the same tables no matter what order the file happens to be in.
local hoses   = {}   -- [player] = { rig=, hose=, station=, accrued=, paidUpTo= }  -- who is plugged in
local stations = {}  -- { model=, floaters=, pos=, panel=, hoseAnchor= }           -- every built farm

-- THE MACHINE'S OWN COLOURS. Identical on every island on purpose -- this is the part that has to be
-- recognisable from island 1 to island 14.
--
-- ===== THE GLOW IS AT HALF BRIGHTNESS =====
-- Neon renders a part's colour at full emission, so the ONLY way to dim it is to darken the colour itself.
-- GLOW is LIME with every channel halved, and the point light is halved to match. The full-strength values
-- are kept below so turning it back up is one edit and not a guess:
--     full lime  = (158, 255, 74)      half = (79, 128, 37)
-- Everything neon in this file uses GLOW, so brightness is one number for the whole station.
--
-- SIGN PAINT IS A SEPARATE NUMBER, and deliberately not halved as far. A SurfaceGui panel does not emit
-- light -- it is ink on a board -- and taking it down to GLOW would put near-black text on a dark green
-- field and cost the signs their legibility, which is the one thing they exist for. LIME_UI sits between
-- the two: clearly calmer than the old full-strength lime, still high contrast against INK.
local METAL_D = Color3.fromRGB( 34,  38,  48)  -- the dark body
local METAL_M = Color3.fromRGB( 56,  62,  76)  -- collars, pipe runs, posts
local METAL_L = Color3.fromRGB( 96, 104, 122)  -- bolts, ribs, frames, bright edges
local LIME    = Color3.fromRGB(158, 255,  74)  -- the FULL-strength lime, kept for reference
local GLOW    = Color3.fromRGB( 79, 128,  37)  -- what every neon part actually uses (50% of LIME)
local LIME_UI = Color3.fromRGB(126, 204,  60)  -- PAINT, not light: sign panels and label text (see below)
local LIME_D  = Color3.fromRGB( 46,  84,  24)  -- the glow's shadow side: troughs, key surround
-- ===== TOKENS ARE RED, AND THAT IS THE POINT =====
-- Gold discs are COINS, and this game already has coins -- a gold disc floating over a machine that pays
-- Crate Tokens tells a player the wrong currency before they have read a single word. Red separates the two
-- at a glance from any distance, which is the only job this colour has.
-- Kept at the same dimmed level as the rest of the station's neon (see GLOW above).
local TOKEN_RED  = Color3.fromRGB(196,  62,  58)  -- token faces
local TOKEN_RED_D = Color3.fromRGB(138,  32,  30) -- token rims
local TOKEN_INK  = Color3.fromRGB(248, 240, 238)  -- the T. Cream on red, not near-black: it has to READ
local INK     = Color3.fromRGB( 22,  24,  30)  -- the T on a token, sign text, recessed wells

--======================================================================
-- ISLAND THEMES
--======================================================================
-- Only the SURROUND changes: the dirt under the machine, the fence, the rocks and the litter. Fields:
--   ground / rim  the pad and its edge ring
--   fence         post + rail colour
--   style         "wood" | "stone" | "metal" | "ice" | "candy"   (what the fence is made of)
--   rock          chunky low-poly boulders scattered outside the fence
--   deco          "grass" | "reeds" | "snow" | "sand" | "crystal" | "candy" | "ember" | "none"
--   decoColor     the tufts / shards / stripes
local THEMES = {
	[1]  = { ground = Color3.fromRGB(122,  84,  52), rim = Color3.fromRGB( 96,  64,  38), fence = Color3.fromRGB(150, 104,  60), style = "wood",  rock = Color3.fromRGB(126, 132, 140), deco = "grass",   decoColor = Color3.fromRGB(106, 190,  76) }, -- Bean Farm
	[2]  = { ground = Color3.fromRGB(104,  78,  48), rim = Color3.fromRGB( 82,  60,  36), fence = Color3.fromRGB(142,  98,  56), style = "wood",  rock = Color3.fromRGB(118, 126, 134), deco = "grass",   decoColor = Color3.fromRGB( 84, 176,  70) }, -- Broccoli Bluff
	[3]  = { ground = Color3.fromRGB(126, 128, 132), rim = Color3.fromRGB( 98, 100, 106), fence = Color3.fromRGB(140, 142, 148), style = "stone", rock = Color3.fromRGB(150, 152, 158), deco = "grass",   decoColor = Color3.fromRGB(120, 186,  96) }, -- Cabbage Cliffs
	[4]  = { ground = Color3.fromRGB(116,  90,  62), rim = Color3.fromRGB( 90,  68,  46), fence = Color3.fromRGB(154, 112,  70), style = "wood",  rock = Color3.fromRGB(128, 130, 136), deco = "grass",   decoColor = Color3.fromRGB(148, 122, 196) }, -- Turnip Tranquil
	[5]  = { ground = Color3.fromRGB(228, 206, 152), rim = Color3.fromRGB(200, 176, 124), fence = Color3.fromRGB(168, 128,  84), style = "wood",  rock = Color3.fromRGB(184, 178, 164), deco = "sand",    decoColor = Color3.fromRGB(240, 224, 178) }, -- Coconut Cove
	[6]  = { ground = Color3.fromRGB(178, 132,  78), rim = Color3.fromRGB(146, 104,  58), fence = Color3.fromRGB(196, 152,  96), style = "wood",  rock = Color3.fromRGB(170, 146, 116), deco = "sand",    decoColor = Color3.fromRGB(226, 190, 132) }, -- Bread Board
	[7]  = { ground = Color3.fromRGB(160, 118,  88), rim = Color3.fromRGB(128,  92,  66), fence = Color3.fromRGB(148, 150, 156), style = "stone", rock = Color3.fromRGB(142, 138, 132), deco = "grass",   decoColor = Color3.fromRGB(126, 176,  92) }, -- Pasta Peak
	[8]  = { ground = Color3.fromRGB(206, 190, 148), rim = Color3.fromRGB(176, 160, 120), fence = Color3.fromRGB(230, 224, 200), style = "metal", rock = Color3.fromRGB(196, 192, 180), deco = "sand",    decoColor = Color3.fromRGB(250, 244, 214) }, -- Popcorn Pinnacle
	[9]  = { ground = Color3.fromRGB( 86, 104,  84), rim = Color3.fromRGB( 66,  82,  66), fence = Color3.fromRGB(124, 106,  74), style = "wood",  rock = Color3.fromRGB(110, 120, 116), deco = "reeds",   decoColor = Color3.fromRGB( 96, 158, 110) }, -- Milk Marsh
	[10] = { ground = Color3.fromRGB( 96,  92,  56), rim = Color3.fromRGB( 74,  70,  42), fence = Color3.fromRGB(132, 112,  64), style = "wood",  rock = Color3.fromRGB(112, 112,  96), deco = "reeds",   decoColor = Color3.fromRGB(150, 168,  78) }, -- Butter Swamp
	[11] = { ground = Color3.fromRGB(226, 236, 244), rim = Color3.fromRGB(186, 206, 226), fence = Color3.fromRGB(198, 226, 240), style = "ice",   rock = Color3.fromRGB(206, 220, 232), deco = "snow",    decoColor = Color3.fromRGB(246, 250, 255) }, -- Ice Cream Isle
	[12] = { ground = Color3.fromRGB( 92,  74,  58), rim = Color3.fromRGB( 70,  56,  44), fence = Color3.fromRGB(104, 108, 116), style = "metal", rock = Color3.fromRGB(120, 112, 104), deco = "ember",   decoColor = Color3.fromRGB(255, 148,  52) }, -- Burger Bluff
	[13] = { ground = Color3.fromRGB(214, 172, 112), rim = Color3.fromRGB(184, 142,  86), fence = Color3.fromRGB(158, 118,  72), style = "wood",  rock = Color3.fromRGB(178, 148, 112), deco = "sand",    decoColor = Color3.fromRGB(232, 198, 140) }, -- Burrito Barrens
	[14] = { ground = Color3.fromRGB(196, 140,  92), rim = Color3.fromRGB(162, 112,  70), fence = Color3.fromRGB(176, 128,  78), style = "wood",  rock = Color3.fromRGB(166, 146, 124), deco = "grass",   decoColor = Color3.fromRGB(118, 182,  84) }, -- Pizza Palms
}
-- Fallbacks by NAME, for the other realms and for any island added later. First keyword found in the island
-- model's name wins; DEFAULT covers anything unrecognised, so a station never fails to build over a theme.
local THEME_WORDS = {
	{ "candy",   { ground = Color3.fromRGB(246, 194, 222), rim = Color3.fromRGB(224, 156, 196), fence = Color3.fromRGB(255, 250, 250), style = "candy", rock = Color3.fromRGB(238, 198, 232), deco = "candy",   decoColor = Color3.fromRGB(255, 116, 168) } },
	{ "snow",    { ground = Color3.fromRGB(226, 236, 244), rim = Color3.fromRGB(186, 206, 226), fence = Color3.fromRGB(198, 226, 240), style = "ice",   rock = Color3.fromRGB(206, 220, 232), deco = "snow",    decoColor = Color3.fromRGB(246, 250, 255) } },
	{ "ice",     { ground = Color3.fromRGB(226, 236, 244), rim = Color3.fromRGB(186, 206, 226), fence = Color3.fromRGB(198, 226, 240), style = "ice",   rock = Color3.fromRGB(206, 220, 232), deco = "snow",    decoColor = Color3.fromRGB(246, 250, 255) } },
	{ "space",   { ground = Color3.fromRGB( 62,  66,  84), rim = Color3.fromRGB( 44,  48,  62), fence = Color3.fromRGB(118, 126, 148), style = "metal", rock = Color3.fromRGB( 92,  96, 116), deco = "crystal", decoColor = Color3.fromRGB(140, 190, 255) } },
	{ "moon",    { ground = Color3.fromRGB( 92,  94, 102), rim = Color3.fromRGB( 70,  72,  80), fence = Color3.fromRGB(122, 128, 144), style = "metal", rock = Color3.fromRGB(120, 122, 130), deco = "crystal", decoColor = Color3.fromRGB(170, 200, 255) } },
	{ "volcano", { ground = Color3.fromRGB( 56,  48,  46), rim = Color3.fromRGB( 40,  34,  32), fence = Color3.fromRGB( 82,  74,  70), style = "metal", rock = Color3.fromRGB( 66,  58,  56), deco = "ember",   decoColor = Color3.fromRGB(255, 116,  36) } },
	{ "lava",    { ground = Color3.fromRGB( 56,  48,  46), rim = Color3.fromRGB( 40,  34,  32), fence = Color3.fromRGB( 82,  74,  70), style = "metal", rock = Color3.fromRGB( 66,  58,  56), deco = "ember",   decoColor = Color3.fromRGB(255, 116,  36) } },
	{ "desert",  { ground = Color3.fromRGB(214, 172, 112), rim = Color3.fromRGB(184, 142,  86), fence = Color3.fromRGB(158, 118,  72), style = "wood",  rock = Color3.fromRGB(178, 148, 112), deco = "sand",    decoColor = Color3.fromRGB(232, 198, 140) } },
	{ "sand",    { ground = Color3.fromRGB(228, 206, 152), rim = Color3.fromRGB(200, 176, 124), fence = Color3.fromRGB(168, 128,  84), style = "wood",  rock = Color3.fromRGB(184, 178, 164), deco = "sand",    decoColor = Color3.fromRGB(240, 224, 178) } },
	{ "forest",  { ground = Color3.fromRGB( 96,  72,  46), rim = Color3.fromRGB( 74,  56,  36), fence = Color3.fromRGB(134,  94,  54), style = "wood",  rock = Color3.fromRGB(112, 120, 112), deco = "grass",   decoColor = Color3.fromRGB( 76, 158,  66) } },
	{ "jungle",  { ground = Color3.fromRGB( 96,  72,  46), rim = Color3.fromRGB( 74,  56,  36), fence = Color3.fromRGB(134,  94,  54), style = "wood",  rock = Color3.fromRGB(112, 120, 112), deco = "grass",   decoColor = Color3.fromRGB( 76, 158,  66) } },
	{ "dino",    { ground = Color3.fromRGB(110,  92,  62), rim = Color3.fromRGB( 86,  70,  46), fence = Color3.fromRGB(140, 106,  62), style = "wood",  rock = Color3.fromRGB(124, 126, 120), deco = "grass",   decoColor = Color3.fromRGB( 98, 168,  78) } },
}
local DEFAULT_THEME = THEMES[1]

--======================================================================
-- PART HELPERS
--======================================================================
-- Everything is anchored, shadowless where it does not matter, and SmoothPlastic unless it is Neon or Glass.
-- Roblox's Wood / Slate / Grass materials carry real surface textures, which is the one thing that would stop
-- this reading as low-poly -- the theming is done with COLOUR and SHAPE instead.
local function part(parent, name, size, cf, color, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = opts.material or Enum.Material.SmoothPlastic
	p.Transparency = opts.transparency or 0
	p.Reflectance = opts.reflectance or 0
	p.Anchored = true
	p.CanCollide = opts.collide == true
	p.CanQuery = false          -- nothing here should ever be hit by a raycast (ours included)
	p.CanTouch = false
	p.CastShadow = opts.shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.shape then p.Shape = opts.shape end
	p.Parent = parent
	return p
end

-- A cylinder standing on its END. Roblox cylinders run along their X axis, so a vertical one is rolled 90
-- degrees about Z and sized (height, diameter, diameter).
local function pillar(parent, name, cf, dia, height, color, opts)
	local p = part(parent, name, Vector3.new(height, dia, dia), cf * CFrame.Angles(0, 0, math.rad(90)), color, opts)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A cylinder lying along the CFrame's own -Z (a pipe run). Length along Z, so pipes can be aimed with lookAt.
local function pipe(parent, name, cf, dia, length, color, opts)
	local p = part(parent, name, Vector3.new(length, dia, dia), cf * CFrame.Angles(0, math.rad(90), 0), color, opts)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A flat glowing ring around a tank: a wide, thin cylinder. Cheaper and cleaner than a torus mesh, and at
-- this scale it reads as exactly the same thing.
local function ring(parent, name, cf, dia, thick, color)
	return pillar(parent, name, cf, dia, thick, color, { material = Enum.Material.Neon })
end

-- A sign board with text on the face pointing at the player (+Z in this build's local space). Returns the
-- board part and the SurfaceGui, so the caller can hang whatever it likes inside. The canvas is generous and
-- every label is TextScaled -- these are read from the ground, at a distance, by kids, so nothing on them is
-- ever small.
--
-- ===== WHY Face = Back =====
-- Roblox's NormalId.FRONT is the -Z face (Vector3.FromNormalId(Front) is (0, 0, -1)); Back is +Z. Every
-- board in this file is placed with its +Z toward the approach, because that is the station's forward, so
-- the readable face is BACK. Set this to Front and every sign renders its text on the side facing the
-- machine -- a wall of blank dark panels from where the player is standing, and nothing in the log to say
-- why. The lime trims are offset along -Z for the same reason: behind the text, not in front of it.
local function board(parent, name, w, h, thick, cf, color, canvasW, canvasH)
	local b = part(parent, name, Vector3.new(w, h, thick), cf, color)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Face"
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(canvasW or 600, canvasH or 400)
	sg.LightInfluence = 0        -- lit, not shaded: readable at dusk and inside the machine's own shadow
	sg.AlwaysOnTop = false
	sg.MaxDistance = 420
	sg.Parent = b
	return b, sg
end

local function label(parent, text, pos, size, colour, font, align)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Font = font or Enum.Font.FredokaOne
	t.Text = text
	t.TextColor3 = colour
	t.TextScaled = true
	t.TextXAlignment = align or Enum.TextXAlignment.Center
	t.Parent = parent
	return t
end

local function frame(parent, pos, size, colour, corner)
	local f = Instance.new("Frame")
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = colour
	f.BorderSizePixel = 0
	f.Parent = parent
	if corner then Instance.new("UICorner", f).CornerRadius = UDim.new(0, corner) end
	return f
end

--======================================================================
-- THE TOKEN
--======================================================================
-- A gold disc with a dark T on it, used for the emblem on the tank and for the icons floating above it.
-- `faceAxis` is the direction the T reads from: "z" for a coin standing up against the tank, "y" for one
-- lying flat and spinning overhead.
local function token(parent, name, cf, dia, faceAxis)
	local thick = dia * 0.14
	local root
	if faceAxis == "y" then
		root = pillar(parent, name, cf, dia, thick, TOKEN_RED, { material = Enum.Material.Neon })
	else
		root = pipe(parent, name, cf, dia, thick, TOKEN_RED, { material = Enum.Material.Neon })
	end
	-- The rim: a slightly larger, darker disc a hair behind it, so the coin has an edge instead of being a
	-- flat sticker. Two parts is all a token needs at this size.
	if faceAxis == "y" then
		pillar(parent, name .. "Rim", cf * CFrame.new(0, -thick * 0.6, 0), dia * 1.16, thick * 0.7, TOKEN_RED_D)
	else
		pipe(parent, name .. "Rim", cf * CFrame.new(0, 0, -thick * 0.6), dia * 1.16, thick * 0.7, TOKEN_RED_D)
	end
	-- The T itself, built from two chunky bars standing proud of the face -- a painted-on letter would
	-- disappear at any angle, and this is the emblem the whole machine is named for.
	local out = (faceAxis == "y") and CFrame.new(0, thick * 0.75, 0) or CFrame.new(0, 0, thick * 0.75)
	local flat = (faceAxis == "y") and CFrame.Angles(math.rad(90), 0, 0) or CFrame.new()
	part(parent, name .. "TBar",  Vector3.new(dia * 0.56, dia * 0.13, dia * 0.10), cf * out * flat * CFrame.new(0, dia * 0.16, 0), TOKEN_INK)
	part(parent, name .. "TStem", Vector3.new(dia * 0.13, dia * 0.46, dia * 0.10), cf * out * flat * CFrame.new(0, -dia * 0.10, 0), TOKEN_INK)
	return root
end

--======================================================================
-- THE DECK  (the half that changes per island)
--======================================================================
-- A THREE-STEP PLINTH, not a disc on the grass. The first version laid one flat pad down and scattered
-- props on it, and it read as a sticker: the machine and the island were two separate things touching.
-- Three tiers fix that for three parts -- a wide themed APRON that tucks into whatever the terrain is
-- doing, a dark structural BASE, and the DECK the machine actually stands on, each smaller than the one
-- under it. The eye reads a built foundation rising out of the ground rather than an object placed on it.
local function buildDeck(model, base, theme, rng)
	-- APRON: themed dirt/sand/snow, sunk so its rim buries into the island. On a slope it cuts in on the
	-- high side rather than floating on the low side -- which is the honest way round.
	pillar(model, "GroundApron", base * CFrame.new(0, -0.28, 0), PAD_R * 2,       0.80, theme.ground, { collide = true })
	pillar(model, "PlinthBase",  base * CFrame.new(0,  0.16, 0), DECK_R * 2 + 1.2, 0.62, theme.rim,    { collide = true })
	pillar(model, "Deck",        base * CFrame.new(0,  0.52, 0), DECK_R * 2,       0.42, theme.deck,   { collide = true })
	-- A glowing inlay ring set into the deck, just inside its edge. One part, and it is what ties the
	-- ground to the machine: the platform now belongs to the reactor rather than to the island.
	ring(model, "DeckInlay", base * CFrame.new(0, DECK + 0.02, 0), DECK_R * 2 - 1.6, 0.10, GLOW)
	pillar(model, "DeckInlayInner", base * CFrame.new(0, DECK + 0.02, 0), DECK_R * 2 - 2.4, 0.08, theme.rim)

	-- THE APPROACH. A darker inlay strip from the entrance to the console, so the way in is drawn on the
	-- floor. Ends AT the console rather than running under it.
	part(model, "ApproachInlay", Vector3.new(4.2, 0.36, DECK_R - 1.0),
		base * CFrame.new(0, DECK - 0.02, (DECK_R + 1.0) * 0.5), theme.rim)
end

--======================================================================
-- THE FENCE AND THE GROUND DETAIL  (also per-island)
--======================================================================
local function buildSurround(model, base, theme, rng)
	-- A LOW FENCE, and a wide way in. Twelve posts rather than sixteen: the gaps between them are what make
	-- it read as a fence instead of a wall, and fewer, chunkier posts is the low-poly answer every time.
	local STYLE = theme.style
	local posts, N = {}, 12
	for i = 0, N - 1 do
		local deg = (i / N) * 360
		local rel = ((deg + 180) % 360) - 180          -- -180..180, 0 = dead front
		if math.abs(rel) > DOOR_HALF then              -- the front arc stays open
			local a = math.rad(deg)
			local at = base * CFrame.new(math.sin(a) * FENCE_R, DECK, math.cos(a) * FENCE_R) * CFrame.Angles(0, a, 0)
			if STYLE == "stone" then
				pillar(model, "FencePost", at * CFrame.new(0, 0.75, 0), 1.15, 1.5, theme.fence, { collide = true })
				pillar(model, "FencePostCap", at * CFrame.new(0, 1.60, 0), 0.85, 0.28, theme.rim)
			elseif STYLE == "metal" then
				pillar(model, "FencePost", at * CFrame.new(0, 1.20, 0), 0.42, 2.4, theme.fence, { collide = true })
				ring(model, "FencePostGlow", at * CFrame.new(0, 2.32, 0), 0.72, 0.20, GLOW)
			elseif STYLE == "ice" then
				part(model, "FencePost", Vector3.new(0.62, 2.3, 0.62), at * CFrame.new(0, 1.15, 0), theme.fence,
					{ collide = true, transparency = 0.22, reflectance = 0.14 })
				part(model, "FenceSpike", Vector3.new(0.42, 0.85, 0.42), at * CFrame.new(0, 2.55, 0), theme.fence,
					{ transparency = 0.28, reflectance = 0.18 })
			elseif STYLE == "candy" then
				pillar(model, "FencePost", at * CFrame.new(0, 1.15, 0), 0.62, 2.3, theme.fence, { collide = true })
				for k = 0, 2 do
					ring(model, "FenceStripe", at * CFrame.new(0, 0.55 + k * 0.72, 0), 0.74, 0.28, theme.decoColor)
				end
			else -- wood: a squared post with a chamfered cap, the shape everybody reads as a fence
				part(model, "FencePost", Vector3.new(0.52, 2.3, 0.52), at * CFrame.new(0, 1.15, 0), theme.fence, { collide = true })
				part(model, "FencePostCap", Vector3.new(0.74, 0.22, 0.74), at * CFrame.new(0, 2.38, 0), theme.rim)
			end
			posts[#posts + 1] = at.Position
		else
			posts[#posts + 1] = false                  -- a hole in the run: no rail crosses the doorway
		end
	end
	if STYLE == "wood" or STYLE == "metal" or STYLE == "candy" then
		for i = 1, #posts do
			local a, b = posts[i], posts[(i % #posts) + 1]
			if a and b then
				local d = (b - a)
				local mid = a + d * 0.5
				local heights = (STYLE == "wood") and { 0.80, 1.70 } or { 1.55 }
				for _, hy in ipairs(heights) do
					part(model, "FenceRail", Vector3.new(0.26, 0.30, d.Magnitude + 0.25),
						CFrame.lookAt(mid + Vector3.new(0, hy, 0), b + Vector3.new(0, hy, 0)), theme.fence)
				end
			end
		end
	end

	-- ROCKS. Rotated BLOCKS, not Balls: a Ball part always renders a true sphere off its SMALLEST axis, so
	-- a boulder sized (3, 2, 2.4) comes out as a 2-stud marble. Five, not seven -- they frame the platform,
	-- they are not scenery in their own right.
	for i = 1, 5 do
		local a = math.rad(rng:NextNumber(0, 360))
		local r = PAD_R + rng:NextNumber(0.4, 2.6)
		local s = rng:NextNumber(1.0, 2.2)
		part(model, "Rock", Vector3.new(s * 1.5, s, s * 1.2),
			base * CFrame.new(math.sin(a) * r, s * 0.26, math.cos(a) * r)
				* CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 6.2), rng:NextNumber(-0.35, 0.35)),
			theme.rock, { collide = true })
	end

	-- THE LITTER. Eight clumps in a BAND just outside the plinth, never on the deck: the machine's own
	-- platform stays clean, which is most of what "polished" means here. This is also the only layer that
	-- says which island you are standing on.
	local D = theme.deco
	if D ~= "none" then
		for i = 1, 8 do
			local a = math.rad(rng:NextNumber(0, 360))
			local r = PAD_R * rng:NextNumber(0.86, 1.20)
			local at = base * CFrame.new(math.sin(a) * r, 0, math.cos(a) * r)
			if D == "grass" then
				for k = 1, 2 do
					part(model, "GrassTuft", Vector3.new(0.16, rng:NextNumber(0.7, 1.2), 0.16),
						at * CFrame.new((k - 1.5) * 0.26, 0.45, 0)
							* CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)),
						theme.decoColor)
				end
			elseif D == "reeds" then
				part(model, "Reed", Vector3.new(0.18, rng:NextNumber(1.5, 2.5), 0.18),
					at * CFrame.new(0, 1.0, 0) * CFrame.Angles(rng:NextNumber(-0.18, 0.18), 0, rng:NextNumber(-0.18, 0.18)),
					theme.decoColor)
			elseif D == "snow" then
				pillar(model, "SnowDrift", at * CFrame.new(0, 0.10, 0), rng:NextNumber(1.8, 3.0), 0.32, theme.decoColor)
			elseif D == "sand" then
				pillar(model, "SandPatch", at * CFrame.new(0, 0.07, 0), rng:NextNumber(1.6, 2.8), 0.20, theme.decoColor)
			elseif D == "crystal" then
				part(model, "Crystal", Vector3.new(0.48, rng:NextNumber(1.0, 2.0), 0.48),
					at * CFrame.new(0, 0.75, 0)
						* CFrame.Angles(rng:NextNumber(-0.28, 0.28), rng:NextNumber(0, 6.2), rng:NextNumber(-0.28, 0.28)),
					theme.decoColor, { material = Enum.Material.Neon, transparency = 0.3 })
			elseif D == "candy" then
				pillar(model, "Sprinkle", at * CFrame.new(0, 0.18, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-40, 40))),
					0.30, rng:NextNumber(0.6, 1.0), theme.decoColor)
			elseif D == "ember" then
				part(model, "Ember", Vector3.new(0.38, 0.28, 0.38), at * CFrame.new(0, 0.18, 0), theme.decoColor,
					{ material = Enum.Material.Neon })
			end
		end
	end
end

--======================================================================
-- THE MACHINE
--======================================================================
-- deck = a yaw-only CFrame sitting on the DECK SURFACE at the centre of the station, +Z pointing the way
-- the player walks in. Everything below is written in that space, so the whole build turns as one.
--
-- ===== THE SILHOUETTE IS THE DESIGN =====
-- A tank is a cylinder, and a cylinder with rings painted on it is a barrel. What makes this read as a
-- REACTOR from across the island is the profile: wide skirt, drum, a NARROW GLOWING WAIST, a second drum,
-- shoulder, dome, crown. Five changes of width up the height, so the outline alone tells you what it is
-- before a single detail resolves. Everything else here -- ribs, slots, bolts, flanges -- is texture hung
-- on that shape, and none of it is allowed to blur it.
local function buildMachine(model, deck)
	local tank = deck * CFrame.new(-0.8, 0, -2.6)

	----------------------------------------------------------------
	-- REACTOR
	----------------------------------------------------------------
	pillar(model, "ReactorSkirt",   tank * CFrame.new(0, 0.45, 0), 8.0, 0.90, METAL_M, { collide = true })
	pillar(model, "ReactorBevel",   tank * CFrame.new(0, 1.05, 0), 7.2, 0.34, METAL_L)
	pillar(model, "ReactorDrumLow", tank * CFrame.new(0, 2.60, 0), 6.4, 3.20, METAL_D, { collide = true, shadow = true })
	-- THE WAIST. Narrower than both drums, so the light in it sits in a shadowed groove instead of being a
	-- stripe painted on a straight side. This one step is most of the silhouette.
	pillar(model, "ReactorWaist",   tank * CFrame.new(0, 5.00, 0), 5.4, 1.60, INK)
	-- The glowing waist band IS the hose anchor: "the middle of the big tank" is exactly where a pipe
	-- should plug in, and it is the one part of the reactor that reads as an opening.
	local core = ring(model, "ReactorCore", tank * CFrame.new(0, 5.00, 0), 5.6, 1.10, GLOW)
	pillar(model, "ReactorDrumTop", tank * CFrame.new(0, 7.30, 0), 6.4, 3.00, METAL_D, { collide = true, shadow = true })
	pillar(model, "ReactorShoulder", tank * CFrame.new(0, 8.95, 0), 7.0, 0.44, METAL_L)
	part(model, "ReactorDome", Vector3.new(6.4, 6.4, 6.4), tank * CFrame.new(0, 9.20, 0), METAL_D,
		{ shape = Enum.PartType.Ball, shadow = true })
	pillar(model, "CrownNeck", tank * CFrame.new(0, 11.60, 0), 1.9, 1.10, METAL_M)
	ring(model,   "CrownRing", tank * CFrame.new(0, 12.30, 0), 2.7, 0.34, GLOW)

	-- RIBS at the diagonals and GLOW SLOTS at the axes, alternating every 45 degrees around the lower drum.
	-- Alternating is the whole trick: metal, light, metal, light as you walk round it, instead of one busy
	-- band of detail.
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		part(model, "ReactorRib", Vector3.new(0.46, 3.3, 0.46),
			tank * CFrame.new(math.sin(a) * 3.15, 2.60, math.cos(a) * 3.15) * CFrame.Angles(0, a, 0), METAL_L)
	end
	for i = 0, 3 do
		local a = math.rad(i * 90)
		part(model, "ReactorSlot", Vector3.new(0.60, 2.30, 0.30),
			tank * CFrame.new(math.sin(a) * 3.22, 2.60, math.cos(a) * 3.22) * CFrame.Angles(0, a, 0), GLOW,
			{ material = Enum.Material.Neon })
	end
	for i = 0, 5 do
		local a = math.rad(30 + i * 60)
		pillar(model, "SkirtBolt", tank * CFrame.new(math.sin(a) * 3.5, 1.08, math.cos(a) * 3.5), 0.72, 0.26, METAL_L)
	end

	----------------------------------------------------------------
	-- THE T EMBLEM -- on a raised bezel, dead centre of the upper drum.
	----------------------------------------------------------------
	-- ON THE FLAT OF THE DRUM, not on the dome. The dome is a 6.4 ball centred at 9.2, so anything mounted
	-- up there at a plausible-looking height sits INSIDE it and is never seen. The upper drum runs 5.8 to
	-- 8.8 and its face is at radius 3.2; the bezel takes that face and the token stands proud of the bezel.
	pipe(model, "EmblemBezel", tank * CFrame.new(0, 7.30, 3.24), 4.6, 0.34, METAL_M)
	pipe(model, "EmblemBezelRim", tank * CFrame.new(0, 7.30, 3.30), 4.9, 0.18, GLOW, { material = Enum.Material.Neon })
	token(model, "TankEmblem", tank * CFrame.new(0, 7.30, 3.50), 3.5, "z")

	----------------------------------------------------------------
	-- TOKEN STORAGE -- a capsule, off to the right and forward so it never hides behind the reactor.
	----------------------------------------------------------------
	local sto = deck * CFrame.new(6.4, 0, 1.0)
	pillar(model, "StorageSkirt", sto * CFrame.new(0, 0.35, 0), 4.6, 0.70, METAL_M, { collide = true })
	pillar(model, "StorageBody",  sto * CFrame.new(0, 2.90, 0), 3.6, 4.40, METAL_D, { collide = true, shadow = true })
	part(model, "StorageCap", Vector3.new(3.6, 3.6, 3.6), sto * CFrame.new(0, 5.10, 0), METAL_D,
		{ shape = Enum.PartType.Ball })
	ring(model, "StorageCollar", sto * CFrame.new(0, 4.95, 0), 3.9, 0.28, GLOW)
	-- THE GAUGE. A recessed dark column with the level glowing inside it and three tick marks across --
	-- the ticks are what turn a green bar into an instrument. Filled to 24%, which is the 240 of 1,000 the
	-- panel below claims: the tank and its own readout must never say two different things.
	part(model, "GaugeRecess", Vector3.new(1.70, 3.40, 0.42), sto * CFrame.new(0, 2.90, 1.72), INK)
	part(model, "GaugeFill",   Vector3.new(1.34, 0.82, 0.44), sto * CFrame.new(0, 1.61, 1.80), GLOW,
		{ material = Enum.Material.Neon })
	for i = 1, 3 do
		part(model, "GaugeTick", Vector3.new(1.74, 0.08, 0.10), sto * CFrame.new(0, 1.90 + i * 0.72, 1.90), METAL_L)
	end

	----------------------------------------------------------------
	-- PIPES -- reactor to storage, worked out in the STATION'S OWN SPACE.
	----------------------------------------------------------------
	-- Local offsets converted at the end, never world X/Z mixed from two points: that version only lines up
	-- when the station happens to face down the world axes, and on a rotated island the elbow swings off to
	-- one side and the run stops short of the tank entirely.
	--
	-- Every run gets FLANGES where it meets something and a small neon collar partway along. The flanges
	-- are what stop a pipe reading as a stick pushed into a barrel.
	for i, spec in ipairs({ { y = 2.10, dia = 1.05 }, { y = 3.70, dia = 0.75 } }) do
		local aL = Vector3.new(1.6, spec.y, -2.6)          -- leaves the reactor's flank
		local bL = Vector3.new(4.6, spec.y,  1.0)          -- meets the storage tank
		local eL = Vector3.new(bL.X, spec.y, aL.Z)         -- the corner: out along X, then forward along Z
		local A = (deck * CFrame.new(aL)).Position
		local B = (deck * CFrame.new(bL)).Position
		local E = (deck * CFrame.new(eL)).Position
		for k, seg in ipairs({ { A, E }, { E, B } }) do
			local d = seg[2] - seg[1]
			if d.Magnitude > 0.2 then
				local mid = CFrame.lookAt(seg[1] + d * 0.5, seg[2])
				pipe(model, "Pipe" .. i .. "_" .. k, mid, spec.dia, d.Magnitude, METAL_M)
				pipe(model, "PipeCollar" .. i .. "_" .. k, CFrame.lookAt(seg[1] + d * 0.34, seg[2]),
					spec.dia * 1.22, 0.30, GLOW, { material = Enum.Material.Neon })
				pipe(model, "PipeFlange" .. i .. "_" .. k, CFrame.lookAt(seg[1] + d.Unit * 0.35, seg[2]),
					spec.dia * 1.45, 0.26, METAL_L)
			end
		end
		part(model, "PipeElbow" .. i, Vector3.new(spec.dia * 1.4, spec.dia * 1.4, spec.dia * 1.4),
			CFrame.new(E), METAL_L, { shape = Enum.PartType.Ball })
	end
	-- One support leg under the elbow, down to the deck. A pipe corner hanging in mid-air is the detail
	-- that makes a build look unfinished even when nobody can say why.
	part(model, "PipeSupport", Vector3.new(0.34, 2.10, 0.34), deck * CFrame.new(4.6, 1.05, -2.6), METAL_M)

	----------------------------------------------------------------
	-- ENERGY -- one emitter, one light. This is scenery on fourteen islands at once.
	----------------------------------------------------------------
	local emit = part(model, "EnergyCore", Vector3.new(0.6, 0.6, 0.6), tank * CFrame.new(0, 12.9, 0), GLOW,
		{ material = Enum.Material.Neon, transparency = 1 })
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(GLOW, Color3.fromRGB(150, 190, 110))
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.04) })
	pe.Lifetime = NumberRange.new(1.1, 2.0)
	pe.Rate = 7
	pe.Speed = NumberRange.new(2.2, 4.5)
	pe.SpreadAngle = Vector2.new(16, 16)
	pe.Acceleration = Vector3.new(0, 3.2, 0)   -- token energy RISES; falling sparks read as damage
	pe.Parent = emit
	local lt = Instance.new("PointLight")
	lt.Color = GLOW; lt.Brightness = 1.1; lt.Range = 24
	lt.Parent = emit

	----------------------------------------------------------------
	-- FLOATING TOKENS -- three above the crown, each on its own halo.
	----------------------------------------------------------------
	-- THEY ORBIT THE TANK, they do not hover in three fixed spots turning on the spot. A ring of small
	-- tokens circling the reactor is what makes the machine look like it is DOING something from across the
	-- island -- three stationary discs read as decoration.
	--
	-- Each one keeps its own `centre` (the tank's axis at its own height) and `radius`, so the loop that
	-- moves them is pure arithmetic and nothing has to be re-derived per frame.
	local floaters = {}
	local ORBIT_R = 3.4
	for i = 1, 3 do
		local holder = Instance.new("Model")
		holder.Name = "FloatingToken" .. i
		holder.Parent = model
		-- built out on the ring so the pieces are welded in the right relative places; the loop takes over
		local centre = tank * CFrame.new(0, 14.6 + (i % 2) * 0.8, 0)
		local at = centre * CFrame.new(0, 0, ORBIT_R)
		holder.PrimaryPart = token(holder, "Ticket", at, 1.35, "z")
		ring(holder, "TicketHalo", at * CFrame.new(0, -0.95, 0), 1.7, 0.09, GLOW)
		floaters[#floaters + 1] = {
			model = holder, home = at, centre = centre, radius = ORBIT_R,
			phase = (i - 1) * (math.pi * 2 / 3),   -- evenly spaced around the ring, not clustered
		}
	end
	return floaters, core
end

--======================================================================
-- THE SIGNS
--======================================================================
-- TWO SIGNS, AND THEY DO DIFFERENT JOBS. The board off to the left is the poster -- read once, from a
-- distance, tells you what this thing is and what it pays. The console out front is the control -- read up
-- close, tells you which key to press. Giving each its own shape, height and angle is what stops the
-- station looking like a pile of notices.
local function buildSigns(model, deck)
	----------------------------------------------------------------
	-- THE POSTER
	----------------------------------------------------------------
	-- Pulled inboard from (-7.6, 2.4): with the 24-degree turn, its outer post landed at radius 10.66 and
	-- the deck stops at 10.4 -- a signpost standing on thin air, which is exactly the kind of thing that
	-- looks fine from three angles and wrong from the fourth.
	local signCF = deck * CFrame.new(-6.6, 0, 2.0) * CFrame.Angles(0, math.rad(24), 0)
	for _, x in ipairs({ -2.7, 2.7 }) do
		part(model, "SignPost", Vector3.new(0.50, 7.2, 0.50), signCF * CFrame.new(x, 3.6, 0), METAL_M, { collide = true })
		part(model, "SignPostFoot", Vector3.new(0.86, 0.34, 0.86), signCF * CFrame.new(x, 0.17, 0), METAL_L)
	end
	part(model, "SignBrace", Vector3.new(5.6, 0.34, 0.34), signCF * CFrame.new(0, 2.2, 0), METAL_M)
	-- The board, its dark frame, and a glowing sill along the bottom edge. The sill is one part and it does
	-- more for "this is a lit sign, not a plank" than any amount of extra geometry would.
	part(model, "SignFrame", Vector3.new(7.9, 6.0, 0.34), signCF * CFrame.new(0, 8.0, -0.14), METAL_L)
	local _, gui = board(model, "MainSign", 7.4, 5.6, 0.46, signCF * CFrame.new(0, 8.0, 0), METAL_D, 740, 560)
	part(model, "SignSill", Vector3.new(7.9, 0.26, 0.46), signCF * CFrame.new(0, 5.10, 0), GLOW,
		{ material = Enum.Material.Neon })

	-- ===== THE LAYOUT IS A HIERARCHY, NOT A LIST =====
	-- Header, then the shout, then one quiet line, then the number in a slab of its own. Each block gets a
	-- clear gap above and below it; nothing is centred against nothing. The RATE is the largest thing on
	-- the board after the header, because the rate is the reason anybody stops to read it.
	frame(gui, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.19), LIME_UI, 0)                -- header bar
	label(gui, "TICKET FARM",   UDim2.fromScale(0.05, 0.015), UDim2.fromScale(0.90, 0.16), INK)
	label(gui, "AFK FARMING!", UDim2.fromScale(0.05, 0.235), UDim2.fromScale(0.90, 0.155), Color3.new(1, 1, 1))
	label(gui, "Earn Tickets while you're away!", UDim2.fromScale(0.05, 0.415), UDim2.fromScale(0.90, 0.10),
		Color3.fromRGB(198, 214, 230), Enum.Font.GothamBold)
	local plaque = frame(gui, UDim2.fromScale(0.06, 0.585), UDim2.fromScale(0.88, 0.335), LIME_UI, 22)
	Instance.new("UIStroke", plaque).Color = INK
	label(plaque, "+40 TICKETS / HOUR", UDim2.fromScale(0.04, 0.14), UDim2.fromScale(0.92, 0.72), INK)

	----------------------------------------------------------------
	-- TOKEN STORAGE PANEL -- its own small console beside the tank, at reading height.
	----------------------------------------------------------------
	-- NOT stacked on top of the tank. Signs floating above a dome are the single easiest way to make a
	-- build look thrown together, and a readout you have to look UP at is a readout nobody reads.
	local stoCF = deck * CFrame.new(6.4, 0, 3.4)
	for _, x in ipairs({ -1.9, 1.9 }) do
		part(model, "StoragePanelPost", Vector3.new(0.34, 2.6, 0.34), stoCF * CFrame.new(x, 1.3, 0), METAL_M, { collide = true })
	end
	part(model, "StoragePanelFrame", Vector3.new(5.0, 2.9, 0.30),
		stoCF * CFrame.new(0, 3.7, -0.12) * CFrame.Angles(math.rad(10), 0, 0), METAL_L)
	local _, sgui = board(model, "StoragePanel", 4.6, 2.5, 0.34,
		stoCF * CFrame.new(0, 3.7, 0) * CFrame.Angles(math.rad(10), 0, 0), METAL_D, 560, 300)
	-- LIVE, AND IT STARTS AT ZERO. This was a painted-on "240 / 1,000" before -- a number that never moved,
	-- which is the one thing a progress readout must not be. The handles come back to the caller so the
	-- accrual loop can drive them.
	label(sgui, "TICKET STORAGE", UDim2.fromScale(0.05, 0.06), UDim2.fromScale(0.90, 0.26), LIME_UI)
	local trough = frame(sgui, UDim2.fromScale(0.06, 0.40), UDim2.fromScale(0.88, 0.20), INK, 12)
	Instance.new("UIStroke", trough).Color = LIME_D
	local fill = frame(trough, UDim2.fromScale(0, 0), UDim2.fromScale(0, 1), LIME_UI, 12)
	local count = label(sgui, "0 / " .. STORAGE_CAP_TEXT, UDim2.fromScale(0.06, 0.63), UDim2.fromScale(0.88, 0.20), Color3.new(1, 1, 1))
	local status = label(sgui, "IDLE", UDim2.fromScale(0.06, 0.83), UDim2.fromScale(0.88, 0.14),
		Color3.fromRGB(150, 162, 178), Enum.Font.GothamBold)

	----------------------------------------------------------------
	-- THE CONSOLE -- straight in front, and the E is a real object.
	----------------------------------------------------------------
	-- The key is BUILT, not printed. A letter drawn on a flat board is a notice; a raised cap standing
	-- proud between two bracket bars, lit from behind, is a button -- and a player reads "press this"
	-- before they have read a single word. That is the whole reason this is geometry and not a texture.
	--
	-- No ProximityPrompt is attached: this is the 3D presentation only, and nothing here is wired to a key.
	local conCF = deck * CFrame.new(0, 0, 6.4) * CFrame.Angles(math.rad(-14), 0, 0)
	part(model, "ConsolePlinth", Vector3.new(6.0, 1.5, 1.9), deck * CFrame.new(0, 0.75, 6.4), METAL_D, { collide = true })
	part(model, "ConsolePlinthTrim", Vector3.new(6.3, 0.26, 2.1), deck * CFrame.new(0, 1.55, 6.4), METAL_L)
	-- 2.6, not 2.85: the board leans back as it rises (that is what the tilt does), and at 2.85 its bottom
	-- edge cleared the plinth by a fifth of a stud and read as floating.
	part(model, "ConsoleFrame", Vector3.new(6.7, 2.5, 0.34), conCF * CFrame.new(0, 2.60, -0.14), METAL_L)
	local _, cgui = board(model, "ConsoleSign", 6.3, 2.2, 0.42, conCF * CFrame.new(0, 2.60, 0), METAL_D, 630, 220)
	-- the words sit to the RIGHT of the key, which occupies the left third of the board
	label(cgui, "START AFK", UDim2.fromScale(0.40, 0.10), UDim2.fromScale(0.56, 0.40), Color3.new(1, 1, 1), nil, Enum.TextXAlignment.Left)
	label(cgui, "FARMING",   UDim2.fromScale(0.40, 0.52), UDim2.fromScale(0.56, 0.38), LIME_UI, nil, Enum.TextXAlignment.Left)

	-- [ E ] -- glow plate, then the bracket bars, then the cap standing proud of both.
	local keyCF = conCF * CFrame.new(-2.05, 2.60, 0)
	part(model, "KeyGlow", Vector3.new(3.3, 3.3, 0.16), keyCF * CFrame.new(0, 0, 0.24), GLOW,
		{ material = Enum.Material.Neon, transparency = 0.62 })
	for _, x in ipairs({ -1.28, 1.28 }) do
		part(model, "KeyBracket", Vector3.new(0.26, 2.3, 0.26), keyCF * CFrame.new(x, 0, 0.52), GLOW,
			{ material = Enum.Material.Neon })
	end
	part(model, "KeyCapBase", Vector3.new(1.95, 1.95, 0.42), keyCF * CFrame.new(0, 0, 0.44), LIME_D)
	local cap = part(model, "KeyCap", Vector3.new(1.70, 1.70, 0.46), keyCF * CFrame.new(0, 0, 0.62), GLOW,
		{ material = Enum.Material.Neon })
	local ksg = Instance.new("SurfaceGui")
	ksg.Name = "Face"; ksg.Face = Enum.NormalId.Back      -- Back is +Z; see the note on board()
	ksg.CanvasSize = Vector2.new(200, 200); ksg.LightInfluence = 0; ksg.MaxDistance = 260
	ksg.Parent = cap
	label(ksg, "E", UDim2.fromScale(0.06, 0.02), UDim2.fromScale(0.88, 0.96), INK)

	-- THE REAL PROMPT. The keycap above is the art; this is the thing Roblox actually listens to, and
	-- without it the console was a sign that said "press E" while nothing on the station was bound to E --
	-- worse than no sign at all.
	--
	-- RequiresLineOfSight = false on purpose: the board it lives on is CanQuery = false (nothing in this
	-- build should ever be hit by a raycast), and a prompt that line-of-sight-checks against geometry it
	-- cannot see itself is a prompt that flickers.
	local panel = { fill = fill, count = count, status = status }

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AFKFarmPrompt"
	prompt.ActionText = "Start AFK Farming"
	prompt.ObjectText = "Ticket Farm"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = cgui.Parent   -- the console board
	return prompt, panel
end

--======================================================================
-- WHERE A STATION GOES
--======================================================================
-- The island a marker belongs to, by walking UP from the marker. Returns the island model and its number
-- (nil if the name carries no number). Falls back to the nearest island-looking model in Workspace, so a
-- marker parented straight to Workspace still gets themed and still faces the right way.
local function islandFor(inst)
	local node = inst.Parent
	while node and node ~= Workspace do
		if node:IsA("Model") then
			local n = node.Name:lower():match("^island[_%s]*(%d+)") or node.Name:lower():match("island[_%s]*(%d+)")
			if n then return node, tonumber(n) end
		end
		node = node.Parent
	end
	-- Nothing above us says "island". Take the nearest top-level model whose name starts with island.
	local pos = (inst:IsA("BasePart") and inst.Position) or (inst:IsA("Attachment") and inst.WorldPosition) or nil
	if not pos then return nil, nil end
	local best, bestD, bestN = nil, math.huge, nil
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and m.Name:lower():find("island") then
			local ok, cf = pcall(function() return m:GetPivot() end)
			if ok and cf then
				local d = (cf.Position - pos).Magnitude
				if d < bestD then best, bestD, bestN = m, d, tonumber(m.Name:lower():match("island[_%s]*(%d+)") or "") end
			end
		end
	end
	return best, bestN
end

-- The DECK colour is DERIVED, not authored. It is the theme's own rim pulled most of the way toward a
-- neutral structural grey, so the platform reads as something that was BUILT on the island rather than a
-- second patch of its dirt -- and adding a theme later still only means picking ground/rim/fence/rock.
-- Cached onto the theme table the first time it is asked for.
local function withDeck(t)
	if not t.deck then t.deck = t.rim:Lerp(Color3.fromRGB(118, 124, 138), 0.45) end
	return t
end
local function themeFor(island, num)
	if num and THEMES[num] then return withDeck(THEMES[num]) end
	if island then
		local lower = island.Name:lower()
		for _, entry in ipairs(THEME_WORDS) do
			if lower:find(entry[1], 1, true) then return withDeck(entry[2]) end
		end
	end
	return withDeck(DEFAULT_THEME)
end

-- THE GROUND UNDER THE PAD. Five rays -- centre and four points near the pad's edge -- and the LOWEST hit
-- wins, so on a slope the pad cuts into the hill instead of hanging off it. Everything already built is
-- excluded, as are characters, so a player standing on the marker cannot become the floor.
local function groundY(pos, ignore)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	rp.IgnoreWater = true
	local lowest, hits = nil, 0
	for _, off in ipairs({ Vector3.new(0, 0, 0), Vector3.new(PAD_R * 0.8, 0, 0), Vector3.new(-PAD_R * 0.8, 0, 0),
	                       Vector3.new(0, 0, PAD_R * 0.8), Vector3.new(0, 0, -PAD_R * 0.8) }) do
		local from = pos + off + Vector3.new(0, 40, 0)
		local hit = Workspace:Raycast(from, Vector3.new(0, -260, 0), rp)
		if hit then
			hits = hits + 1
			if not lowest or hit.Position.Y < lowest then lowest = hit.Position.Y end
		end
	end
	return lowest, hits
end

--======================================================================
-- THE STORAGE READOUT
--======================================================================
-- Driven from the server because the server is the only thing that knows the number. Writing a Frame's Size
-- and two Text properties twice a second replicates for almost nothing, and it means every player standing
-- at the station sees the same tank filling -- which is the point of putting it on the machine rather than
-- in somebody's HUD.
--
-- `amount = nil` means nobody is plugged in: empty bar, IDLE.
local function setPanel(st, amount, riders)
	local pn = st and st.panel
	if not pn then return end
	pcall(function()
		if not riders or riders <= 0 then
			pn.fill.Size = UDim2.fromScale(0, 1)
			pn.count.Text = "0 / " .. STORAGE_CAP_TEXT
			pn.status.Text = "IDLE"
			pn.status.TextColor3 = Color3.fromRGB(150, 162, 178)
		else
			pn.fill.Size = UDim2.fromScale(math.clamp(amount / STORAGE_CAP, 0, 1), 1)
			pn.count.Text = comma(amount) .. " / " .. STORAGE_CAP_TEXT
			pn.status.Text = (riders == 1)
				and ("FARMING  +" .. TOKENS_PER_HOUR .. "/HOUR")
				or  (riders .. " PLUGGED IN  \xE2\x80\xA2  +" .. (TOKENS_PER_HOUR * riders) .. "/HOUR")
			pn.status.TextColor3 = LIME_UI
		end
	end)
end

-- ===== HOW MANY PLAYERS CAN SHARE ONE FARM: ALL OF THEM =====
-- There is no cap, and nothing in this file queues, reserves or locks a station. Each player gets their own
-- hose, their own attachment on the tank, their own coupling and their own timestamp -- all keyed by the
-- player, none of it shared -- so a station with nine people on it behaves exactly like nine stations with
-- one. Everybody earns the full rate; they are not splitting a pot.
--
-- The ONE thing genuinely shared is this panel, and two players writing their own totals to it twice a
-- second is how it ends up strobing between two numbers. So the readout is the STATION's: the sum of what
-- everyone plugged into it has earned this session, plus a headcount once it is more than one. Recomputed
-- from scratch rather than incremented, so it cannot drift when somebody unplugs or disconnects.
local function refreshPanels()
	local sum, riders = {}, {}
	for _, h in pairs(hoses) do
		local st = h.station
		if st then
			sum[st] = (sum[st] or 0) + (h.accrued or 0)
			riders[st] = (riders[st] or 0) + 1
		end
	end
	for _, st in ipairs(stations) do
		setPanel(st, sum[st] or 0, riders[st] or 0)
	end
end

--======================================================================
-- STAYING PLUGGED IN WHILE YOU ARE GONE
--======================================================================
-- The live loop below only pays while you are in the server, and Roblox disconnects an idle client after
-- about twenty minutes -- so "leave it running overnight" paid about 13 tokens and then stopped. This is
-- what makes 24 hours actually mean 960.
--
-- ===== ONE CLOCK, NOT TWO =====
-- The rule is: plugging in writes a TIMESTAMP, and everything else is arithmetic on it. The live tick pays
-- from wall-clock too (see the loop) rather than counting its own ticks, so online and offline earning are
-- computed the same way and cannot disagree. A loop that counts ticks and a timestamp that counts seconds
-- would drift apart the first time the server hitched.
--
-- ===== LEAVING KEEPS YOU PLUGGED IN. UNPLUGGING DOES NOT. =====
-- Every way of coming off the hose clears the stored session EXCEPT closing the game:
--     E again / walked off / died / respawned  -> cleared. You chose to stop.
--     left the game                            -> KEPT. That is the whole feature.
-- On your next join the elapsed time is paid out and the session is cleared, so you press E again to start
-- another one. Nothing accrues twice: the moment it pays, the record is gone.
--
-- ===== ITS OWN DATASTORE, ON PURPOSE =====
-- PlayerStats' save table is big, load-bearing and shared by a dozen systems; bolting a field onto it means
-- touching its load path, its default table and its migration. One key holding one number does not justify
-- that. This is the same shape BlimpService uses for its own store, and it is independent of
-- DISABLE_SAVE_FOR_TESTING -- which means away-time works in a test session, but ALSO that it needs Studio
-- API access ticked on before it will do anything in Studio.
local DataStoreService = game:GetService("DataStoreService")
local MAX_AWAY_HOURS   = 24     -- the ceiling. 24 x 40 = 960, which is the number on the sign's maths
local awayStore
pcall(function() awayStore = DataStoreService:GetDataStore("AFKTokenFarm_v1") end)

local function awayKey(plr) return "afk_" .. plr.UserId end

-- Written the moment you plug in. Nothing else in this file writes it, so there is exactly one place a
-- session can begin.
local function openSession(plr)
	if not awayStore then return end
	task.spawn(function()
		local ok, err = pcall(function()
			awayStore:SetAsync(awayKey(plr), { at = os.time() })
		end)
		if not ok then
			warn("[AFKFarm] could not save the away-session for " .. plr.Name ..
				" (" .. tostring(err) .. ") -- online earning still works, offline will not")
		end
	end)
end

-- ===== THE RECORD IS MOVED FORWARD EVERY TIME WE PAY =====
-- Without this the stored timestamp stays at the moment you PLUGGED IN, so a player who farms online for
-- three hours and then closes the game gets those three hours paid a SECOND time on rejoin. Advancing the
-- mark on every payout means the record always says "paid up to here", and away time can only ever start
-- from the last token that actually landed.
--
-- Doing it here rather than on PlayerRemoving is also what makes it survive a crash, an alt-F4 or a Roblox
-- shutdown -- none of which give a leaving player enough time for a DataStore write. The cost of being at
-- most one payout stale is at most one token; the cost of writing on the way out is losing the lot.
local function touchSession(plr, at)
	if not awayStore then return end
	task.spawn(function()
		pcall(function() awayStore:SetAsync(awayKey(plr), { at = math.floor(at) }) end)
	end)
end

local function closeSession(plr)
	if not awayStore then return end
	task.spawn(function()
		pcall(function() awayStore:RemoveAsync(awayKey(plr)) end)
	end)
end

-- Paid on join, once, and then the record is removed. Capped at MAX_AWAY_HOURS so a player who plugs in and
-- disappears for a fortnight collects a day, not a fortnight.
local function claimAway(plr)
	if not awayStore then return end

	-- WAIT FOR THE SAVE TO LAND FIRST. PlayerStats creates the CrateTokens leaderstat as it loads a player,
	-- and crediting before that load finishes is how an award gets quietly overwritten by the saved balance
	-- a second later. The leaderstat existing is the signal; the extra pause covers the rest of the load.
	local ls = plr:WaitForChild("leaderstats", 30)
	if not ls or not ls:WaitForChild("CrateTokens", 20) then return end
	task.wait(3)
	if not plr.Parent then return end

	local ok, rec = pcall(function() return awayStore:GetAsync(awayKey(plr)) end)
	if not ok or type(rec) ~= "table" or not tonumber(rec.at) then return end
	closeSession(plr)

	local secs = math.clamp(os.time() - tonumber(rec.at), 0, MAX_AWAY_HOURS * 3600)
	local pay  = math.floor(secs * TOKENS_PER_HOUR / 3600)
	if pay <= 0 then
		print(("[AFKFarm] %s was away %ds -- not a whole token yet, nothing paid"):format(plr.Name, secs))
		return
	end
	pay = petAfkScale(plr, pay)   -- Cold Storage: the offline claim is boosted too, not just the live loop

	local fired, result = pcall(_G.addSkinTokens, plr, pay, "afk ticket farm (away)")
	if not (fired and result ~= false) then
		warn("[AFKFarm] away payout of " .. pay .. " for " .. plr.Name .. " was REFUSED -- balance unchanged")
		return
	end
	pcall(function() AFKFarmEvent:FireClient(plr, "away", pay, secs) end)
	print(("[AFKFarm] %s was plugged in for %.1fh while away -> +%d tokens (cap %dh)")
		:format(plr.Name, secs / 3600, pay, MAX_AWAY_HOURS))
end

Players.PlayerAdded:Connect(function(plr) task.spawn(claimAway, plr) end)
for _, plr in ipairs(Players:GetPlayers()) do task.spawn(claimAway, plr) end

--======================================================================
-- THE HOSE  (press E -> a suction cup clamps on and a hose runs to the tank)
--======================================================================
-- This is the one part of the station that is NOT just scenery. Pressing E clamps a little suction cup to
-- the back of your character and runs a hose from it to the middle of the reactor -- you are plugged into
-- the machine, and everybody in the server can see who is farming.
--
-- ===== WHY A BEAM AND NOT A ROW OF PARTS =====
-- A hose between two things that MOVE is the classic reason builds get expensive: the naive version is a
-- chain of parts re-CFramed every frame, per player, replicating the whole way. A Beam is drawn by the GPU
-- between two Attachments, updates itself when either end moves, needs no loop at all, and replicates once.
-- CurveSize gives it the sag a real hose has, and FaceCamera keeps the ribbon turned edge-on to nobody --
-- so a flat beam reads as a round tube from every angle.
--
-- Two beams, not one: a dark rubber line, and a thinner brighter one laid over it. That is what stops it
-- reading as a flat green stripe.

local function detachHose(plr, why)
	local h = hoses[plr]
	if not h then return end
	hoses[plr] = nil
	pcall(function() if h.rig then h.rig:Destroy() end end)          -- cup, rim, nozzle, collar and beams
	pcall(function() if h.tankAtt then h.tankAtt:Destroy() end end)
	pcall(function() if h.coupling then h.coupling:Destroy() end end)
	pcall(function() plr:SetAttribute("AFKFarming", false) end)
	-- THE ONE EXCEPTION. Closing the game leaves you plugged in so the away clock keeps running; every
	-- other way off the hose is a decision to stop, and clears it.
	if why ~= "left the game" then closeSession(plr) end
	pcall(function() AFKFarmEvent:FireClient(plr, "disconnected", why, h.accrued or 0) end)
	refreshPanels()   -- recomputed from who is LEFT, so a tank with others on it keeps running
	print(("[AFKFarm] %s unplugged (%s)"):format(plr.Name, why or "toggled off"))
end

local function attachHose(plr, st)
	if hoses[plr] then detachHose(plr, "re-plugged") end
	local char = plr.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and st.hoseAnchor and st.hoseAnchor.Parent) then return end

	-- THE CUP. Welded to the HumanoidRootPart, so it rides the character for free -- no loop, and it stays
	-- put through walking, jumping and flying. Massless and non-colliding: an accessory that changes how a
	-- player moves is a bug, not a feature.
	--
	-- The root's -Z is forward, so +Z is behind; a little below centre puts it exactly where the joke wants
	-- it. Cup, then a rim, then a short nozzle for the hose to leave from.
	local cupCF = hrp.CFrame * CFrame.new(0, -0.55, 0.95)

	-- ===== THE CYLINDER AXIS, WHICH IS THE EASY THING TO GET WRONG =====
	-- A Cylinder's Size.X is its LENGTH along its own axis; Size.Y and Size.Z are the two diameters. So a
	-- disc 1.5 across and 0.42 thick is (0.42, 1.5, 1.5), NOT (1.5, 1.5, 0.42) -- that second one is a
	-- 1.5-long tube with a squashed oval cross-section, which is not a suction cup by any description.
	--
	-- Then it has to be AIMED: rotating -90 degrees about Y maps the cylinder's X axis onto +Z, and +Z on a
	-- HumanoidRootPart is BEHIND the character (its -Z is forward). So the disc lies flat against the back
	-- and the nozzle points away from it, which is where the hose needs to leave from.
	local BACK = CFrame.Angles(0, math.rad(-90), 0)

	-- ONE RIG, ONE DESTROY. Every piece goes in a single Model under the character, so unplugging is one
	-- :Destroy() and there is nothing left to leak. Parenting them straight to the character instead means
	-- the cup goes and the nozzle, rim and collar stay welded to a part that no longer exists -- which is
	-- to say they hang off the player forever.
	local rig = Instance.new("Model")
	rig.Name = "AFKHoseRig"
	rig.Parent = char

	local function stick(name, size, cf, colour, mat, weldTo)
		local p = Instance.new("Part")
		p.Name = name; p.Size = size; p.CFrame = cf; p.Color = colour
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Shape = Enum.PartType.Cylinder
		p.Anchored = false; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.Massless = true; p.CastShadow = false   -- an accessory must never change how a player moves
		p.Parent = rig
		local ww = Instance.new("WeldConstraint"); ww.Part0 = weldTo; ww.Part1 = p; ww.Parent = p
		return p
	end

	-- Scaled up with the hose. A 1.45-wide cord leaving a 0.7 nozzle looks like the hose is swallowing the
	-- fitting -- every diameter here is now bigger than the beam it carries.
	local cup = stick("AFKSuctionCup", Vector3.new(0.46, 2.0, 2.0), cupCF * BACK, INK, nil, hrp)
	stick("AFKSuctionRim",  Vector3.new(0.26, 2.4, 2.4), cupCF * CFrame.new(0, 0, -0.07) * BACK, METAL_M, nil, cup)
	local noz = stick("AFKHoseNozzle", Vector3.new(0.95, 1.35, 1.35), cupCF * CFrame.new(0, 0, 0.55) * BACK, METAL_L, nil, cup)
	stick("AFKHoseCollar", Vector3.new(0.30, 1.65, 1.65), cupCF * CFrame.new(0, 0, 0.95) * BACK, GLOW, Enum.Material.Neon, cup)

	-- THE RUN. One attachment on the nozzle, one in the middle of the reactor, and the beams between them.
	local a0 = Instance.new("Attachment"); a0.Name = "HoseEnd"; a0.Position = Vector3.new(0.58, 0, 0); a0.Parent = noz
	local a1 = Instance.new("Attachment"); a1.Name = "HoseTankEnd_" .. plr.Name; a1.Parent = st.hoseAnchor

	-- ===== ONE BEAM. THE FLICKER WAS TWO. =====
	-- The first version drew a fat dark beam and a thin bright one along the SAME two attachments with the
	-- same CurveSize -- two ribbons occupying exactly the same surface in space. That is textbook
	-- z-fighting: every frame the GPU picks a different winner and the hose strobes. It is not a Roblox
	-- quirk and no amount of transparency tuning fixes it; the second ribbon has to go.
	--
	-- So the detail that the glow beam was providing is baked into ONE beam instead. A Beam's ColorSequence
	-- runs along its LENGTH, so alternating dark and lit keypoints gives banding down the hose -- it reads
	-- as ribbed rubber with something bright pulsing through it, from a single opaque surface that has
	-- nothing to fight with.
	--
	-- Fully opaque (Transparency 0) on purpose too: a semi-transparent beam blends against whatever is
	-- behind it, and against MOVING scenery -- a spinning token, the player's own pet -- that blend changes
	-- every frame and reads as shimmer even with only one ribbon.
	local hose = Instance.new("Beam")
	hose.Name = "AFKHose"
	hose.Attachment0 = a0
	hose.Attachment1 = a1
	-- WIDTH IS IN STUDS, and 0.6 is a wire. A hose thick enough to be plumbing on a character-sized rig is
	-- north of a stud; these are the numbers that make it read as a CORD from ten paces. Slightly fatter at
	-- the player end than at the tank, so it tapers into the machine instead of being a uniform tube.
	hose.Width0 = HOSE_W0
	hose.Width1 = HOSE_W1
	-- 3.5, not 5: less whip when you turn on the spot. The sag still reads as weight.
	hose.CurveSize0 = 3.5
	hose.CurveSize1 = 3.5
	hose.Segments = 24               -- more segments = a smooth curve instead of a visible chain of facets
	hose.FaceCamera = true           -- keeps the flat ribbon turned toward the viewer, so it reads as a tube
	hose.LightInfluence = 0
	hose.Transparency = NumberSequence.new(0)
	local RUB, LIT = Color3.fromRGB(34, 38, 46), Color3.fromRGB(74, 96, 58)
	hose.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, RUB), ColorSequenceKeypoint.new(0.10, LIT),
		ColorSequenceKeypoint.new(0.20, RUB), ColorSequenceKeypoint.new(0.32, LIT),
		ColorSequenceKeypoint.new(0.44, RUB), ColorSequenceKeypoint.new(0.56, GLOW),
		ColorSequenceKeypoint.new(0.68, RUB), ColorSequenceKeypoint.new(0.80, LIT),
		ColorSequenceKeypoint.new(0.90, RUB), ColorSequenceKeypoint.new(1.00, RUB),
	})
	hose.LightEmission = 0.15
	hose.Parent = cup

	-- A COUPLING WHERE IT MEETS THE TANK. Static geometry, so it cannot shimmer, and it stops the beam
	-- ending in mid-air against the reactor's side -- the hose now visibly plugs into something.
	local coupling = Instance.new("Part")
	coupling.Name = "AFKHoseCoupling_" .. plr.Name
	coupling.Size = Vector3.new(0.6, 1.85, 1.85)   -- wider than the 1.15 beam end, so the hose plugs INTO it
	coupling.CFrame = CFrame.new(a1.WorldPosition, hrp.Position) * CFrame.Angles(0, math.rad(90), 0)
	coupling.Color = METAL_L
	coupling.Material = Enum.Material.SmoothPlastic
	coupling.Shape = Enum.PartType.Cylinder
	coupling.Anchored = true; coupling.CanCollide = false; coupling.CanQuery = false
	coupling.CanTouch = false; coupling.CastShadow = false
	coupling.Parent = st.model

	-- paidUpTo is a WALL-CLOCK mark, not a tick counter: the live loop pays for the seconds that have
	-- actually passed, which is the same sum the away payout does. One formula, two situations.
	hoses[plr] = { rig = rig, cup = cup, hose = hose, tankAtt = a1, coupling = coupling,
		station = st, accrued = 0, paidUpTo = os.time() }
	openSession(plr)
	refreshPanels()
	plr:SetAttribute("AFKFarming", true)
	pcall(function() AFKFarmEvent:FireClient(plr, "connected", TOKENS_PER_HOUR) end)
	print(("[AFKFarm] %s plugged in at %s"):format(plr.Name, tostring(st.pos)))
end

local function toggleHose(plr, st)
	if hoses[plr] then detachHose(plr, "pressed E again") else attachHose(plr, st) end
end

-- The hose lets go by itself when it should: you walked off, you died, you left. A hose still stretching to
-- a tank from the other side of the island is the kind of thing players screenshot.
Players.PlayerRemoving:Connect(function(plr) detachHose(plr, "left the game") end)
Players.PlayerAdded:Connect(function(plr)
	plr.CharacterRemoving:Connect(function() detachHose(plr, "respawned") end)
end)
for _, plr in ipairs(Players:GetPlayers()) do
	plr.CharacterRemoving:Connect(function() detachHose(plr, "respawned") end)
end

--======================================================================
-- THE TICK -- the only thing in this file that pays anybody
--======================================================================
-- ONE loop for every plugged-in player: it drops the hose when it should, accrues at TOKENS_PER_HOUR, and
-- pays whole tokens through SkinCrateService's own hook.
--
-- ===== IT GOES THROUGH _G.addSkinTokens, NEVER _G.playerCrateTokens =====
-- SkinCrateService owns the balance. Its hook clamps, logs and saves on the same path a Robux token pack
-- takes, and it pushes the new balance to the client -- which is what makes the counter in the HUD capsule
-- move on its own. Writing the table directly would skip every one of those and drift the moment that file
-- changes.
--
-- The FRACTION is carried between ticks rather than rounded away: at 40/hour a half-second tick earns
-- 0.00555 of a token, and a loop that floors each tick pays out exactly nothing, forever.
local TICK = 0.5
task.spawn(function()
	while true do
		task.wait(TICK)
		for plr, h in pairs(hoses) do
			local char = plr.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			local hum  = char and char:FindFirstChildOfClass("Humanoid")
			if not (hrp and h.rig and h.rig.Parent) then
				detachHose(plr, "character gone")
			elseif hum and hum.Health <= 0 then
				detachHose(plr, "died")
			elseif (hrp.Position - h.station.pos).Magnitude > HOSE_RANGE then
				detachHose(plr, "walked out of range")
			else
				-- SECONDS SINCE WE LAST PAID, not ticks since we last paid. A server that hitches, or a
				-- loop that gets scheduled late, still owes you exactly the same tokens -- and it is the
				-- identical sum claimAway does on a rejoin.
				local secs = os.time() - (h.paidUpTo or os.time())
				local pay  = math.floor(secs * TOKENS_PER_HOUR / 3600)
				if pay > 0 then
					h.paidUpTo = (h.paidUpTo or os.time()) + pay * (3600 / TOKENS_PER_HOUR)
					h.accrued = math.min((h.accrued or 0) + petAfkScale(plr, pay), STORAGE_CAP)
					-- Two different failures, and only one of them is worth a warning: pcall's flag says the
					-- call itself blew up, the RETURN says SkinCrateService refused it (bad player, at the
					-- balance ceiling). Collapsing them would hide a real breakage behind a normal refusal.
					local ok = false
					if type(_G.addSkinTokens) == "function" then
						local fired, result = pcall(_G.addSkinTokens, plr, pay, "afk ticket farm")
						ok = fired and result ~= false
					end
					if not ok then
						warn("[AFKFarm] could not credit " .. plr.Name ..
							" -- SkinCrateService's _G.addSkinTokens is missing; nothing was paid")
					end
					touchSession(plr, h.paidUpTo)   -- away time now starts from THIS token, not from plug-in
					pcall(function() AFKFarmEvent:FireClient(plr, "token", pay, h.accrued) end)
					print(("[AFKFarm] %s +%d token(s) (%d this session)"):format(plr.Name, pay, h.accrued))
				end
			end
		end

		-- ONE write per station per tick, after everybody has been paid. Doing it inside the player loop
		-- meant two people on the same tank each stamped their own number twice a second and the readout
		-- strobed between them.
		refreshPanels()
	end
end)

--======================================================================
-- BUILD ONE
--======================================================================

-- Hide-and-unsolidify, applied to a marker AFTER its CFrame has been read. Separate from the build so a
-- marker on a skipped island still gets tidied -- that is the case that matters most, because there is no
-- station standing over it to swallow it.
local function retireMarker(marker)
	if not (HIDE_MARKERS and marker and marker:IsA("BasePart")) then return end
	local sz = marker.Size
	if math.max(sz.X, sz.Y, sz.Z) > MARKER_MAX_STUD then
		warn(string.format("[AFKFarm] '%s' is %.0fx%.0fx%.0f studs -- too big to be a placement marker, so it "
			.. "has been left visible and solid. If that really is the marker, shrink it; if it is scenery, "
			.. "rename it.", marker:GetFullName(), sz.X, sz.Y, sz.Z))
		return
	end
	marker.Transparency = 1
	marker.CanCollide = false
end

local function buildStation(marker)
	local island, num = islandFor(marker)
	local theme = themeFor(island, num)

	-- NOT ON THIS ISLAND. Checked before any geometry is made, so a skipped island costs one comparison
	-- rather than a full build that is then thrown away. The marker is still retired -- an unhidden block on
	-- an island with no station is the most visible loose end of all.
	-- FAILS CLOSED. A marker whose island cannot be resolved (num == nil) is SKIPPED, not built: "only on
	-- island 1" has to mean that even when the lookup is the thing that went wrong, and a station built off
	-- an unknown marker is exactly the stray one this change exists to remove. Warned, because a nil here on
	-- Bean Farm would mean island 1 silently loses its station too.
	if ONLY_ISLANDS and not (num and ONLY_ISLANDS[num]) then
		if not num then
			warn("[AFKFarm] '" .. marker:GetFullName() .. "' could not be traced to an island, so it was "
				.. "skipped. If this marker IS on island 1, check it is parented inside the island model.")
		end
		retireMarker(marker)
		return nil
	end

	-- Read the marker. NOTHING here writes to it -- not its transparency, not its parent, not its name.
	local markerCF
	if marker:IsA("BasePart") then
		markerCF = marker.CFrame
	elseif marker:IsA("Attachment") then
		markerCF = marker.WorldCFrame
	elseif marker:IsA("Model") then
		local ok, cf = pcall(function() return (marker:GetBoundingBox()) end)
		markerCF = ok and cf or nil
	end
	if not markerCF then
		warn("[AFKFarm] '" .. marker.Name .. "' is a " .. marker.ClassName .. " -- expected a Part, Attachment or Model. Skipped.")
		return nil
	end

	-- FACING. Yaw only: a marker tipped over in Studio must not tip the whole station over with it.
	local _, yaw = markerCF:ToEulerAnglesYXZ()
	if math.abs(yaw) < 0.02 and island then
		-- Never rotated -> aim at the island's centre, which is the side players walk in from.
		local ok, cf = pcall(function() return island:GetPivot() end)
		if ok and cf then
			local to = Vector3.new(cf.Position.X - markerCF.Position.X, 0, cf.Position.Z - markerCF.Position.Z)
			if to.Magnitude > 1 then yaw = math.atan2(to.X, to.Z) end
		end
	end

	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	-- Sit it on the island's surface. If nothing is under the marker (the island has not streamed in on the
	-- server, or the marker is over a hole) we use the marker's own Y and say so, rather than dropping the
	-- station into the sky silently.
	-- Exclude every character: a player standing on the marker while the station builds would otherwise BE
	-- the ground, and the pad would be laid on their head. (Our own parts are all CanQuery = false, so a
	-- station already standing nearby can never be mistaken for terrain either.)
	local ignore = { model }
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then ignore[#ignore + 1] = plr.Character end
	end
	local gy, hits = groundY(markerCF.Position, ignore)
	local baseY = gy or markerCF.Position.Y
	if not gy then
		warn(string.format("[AFKFarm] nothing under the '%s' marker at %s -- using the marker's own height. " ..
			"If the station ends up floating, move the marker down onto the island surface.",
			marker.Name, tostring(markerCF.Position)))
	end
	local base = CFrame.new(markerCF.Position.X, baseY, markerCF.Position.Z) * CFrame.Angles(0, yaw, 0)

	local rng = Random.new(math.floor(markerCF.Position.X * 7 + markerCF.Position.Z * 13 + baseY))
	-- Deck first (everything else stands on it), then the machine and the signs in DECK space, then the
	-- fence and the litter last so they can be laid around a build that already exists.
	local deck = base * CFrame.new(0, DECK, 0)
	buildDeck(model, base, theme, rng)
	local floaters, hoseAnchor = buildMachine(model, deck)
	local prompt, panel = buildSigns(model, deck)
	buildSurround(model, base, theme, rng)

	-- FINAL SWEEP. Anchored is set by part(), but assert it: one unanchored brick in a build this size falls
	-- through the island at 3am and takes half the machine with it. Reflectance is stripped for the same
	-- reason the materials are -- a shiny face breaks the flat cartoon read the whole place is built on.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			if d.Material ~= Enum.Material.Neon then d.Reflectance = math.min(d.Reflectance, 0.2) end
		end
	end

	model.PrimaryPart = model:FindFirstChild("Deck")
	-- StreamingEnabled is ON and these sit on islands thousands of studs apart. Without Persistent a station
	-- is invisible to anybody who did not walk up to it as it loaded.
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
	-- PARENTED TO WORKSPACE, NOT TO THE ISLAND -- deliberately, and it is the safer of two tempting options.
	-- Dropping the station inside the island model would make it travel if the island ever moved, but it
	-- would also put a 15-stud tower inside that model's BOUNDING BOX, and several systems in this place ask
	-- an island for its pivot or its bounds (that is how this very file finds the nearest island). Growing an
	-- island's bounds sideways is exactly the sort of change that moves something else a stud and a half a
	-- week later with no obvious cause. The brief says do not modify existing island objects; adding a child
	-- to one counts.
	model.Parent = Workspace

	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end
	-- Read, positioned, built -- the marker has done its job and can get out of the way.
	retireMarker(marker)

	print(string.format("[AFKFarm] built on %s (island %s, %s theme) at %s -- %d parts, facing %.0f deg, ground %s",
		island and island.Name or "no island", tostring(num or "?"), theme.deco,
		tostring(base.Position), n, math.deg(yaw), gy and (hits .. "/5 rays") or "MARKER Y (no hit)"))

	local st = { model = model, floaters = floaters, pos = base.Position, hoseAnchor = hoseAnchor,
		panel = panel, energy = model:FindFirstChild("EnergyCore", true) }
	-- E plugs you in. The prompt is per-station, so the hose always runs to the tank you are standing at.
	if prompt then
		prompt.Triggered:Connect(function(plr) toggleHose(plr, st) end)
	end
	stations[#stations + 1] = st
	return st
end

--======================================================================
-- FIND THE MARKERS
--======================================================================
local function isMarker(d)
	return MARKER_NAMES[d.Name:lower()] and (d:IsA("BasePart") or d:IsA("Attachment") or d:IsA("Model"))
end

local function clearOldStations()
	local n = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == MODEL_NAME then d:Destroy(); n = n + 1 end
	end
	if n > 0 then print("[AFKFarm] cleared " .. n .. " station(s) from a previous run") end
end

-- ONE STATION PER MARKER, WITHOUT WALKING THE WHOLE WORLD ONCE A SECOND.
-- StreamingEnabled is a CLIENT thing: the server holds the entire place from startup, so a single sweep
-- finds every marker that shipped in the file. What a sweep can miss is a marker ADDED later -- a Rojo sync
-- while a test server is up, or a drag in Studio -- so DescendantAdded covers the rest, and two late
-- re-sweeps cover anything that arrived in a batch the signal coalesced.
local considered = {}   -- marker instance -> true
local claimed    = {}   -- island instance -> the marker that got there first
local built      = 0

local function consider(d)
	if considered[d] or not isMarker(d) then return end
	if d:FindFirstAncestor(MODEL_NAME) then return end -- something of ours, not a placement point
	considered[d] = true
	local island = islandFor(d)
	local key = island or Workspace
	if claimed[key] then
		-- ONE PER ISLAND. A second marker on the same island is almost always a stray duplicate, and
		-- building on it would put two machines on one island -- explicitly ruled out.
		warn(string.format("[AFKFarm] a SECOND '%s' marker on %s -- ignored, one station per island. " ..
			"Delete the spare in Studio if it is not meant to be there.",
			d.Name, island and island.Name or "no island"))
		return
	end
	claimed[key] = d
	local ok, err = pcall(buildStation, d)
	if ok then
		built = built + 1
	else
		warn("[AFKFarm] station build FAILED for a marker on " ..
			(island and island.Name or "no island") .. ": " .. tostring(err))
	end
end

local function sweep()
	for _, d in ipairs(Workspace:GetDescendants()) do consider(d) end
end

task.spawn(function()
	-- ===== WAIT FOR THE ISLANDS TO STOP MOVING =====
	-- PlayerStats REPOSITIONS every island at boot ("Positioned Island_1_BeanFarm at Y=150"), several
	-- seconds after this script starts. A marker is a child of its island and travels with it; a station
	-- parented to Workspace does not. Build first and the log reads exactly like the first run of this file
	-- did: "[AFKFarm] built on Island_1_BeanFarm ... at 858, -21, -812", and then two seconds later the farm
	-- moves to Y=150 and leaves the whole station behind in the empty sky, 1,000 studs from anywhere.
	--
	-- Workspace's "StandsReady" attribute is PlayerStats' "islands are where they are going to be" signal.
	-- PetBarn, Campfire, CommunityGarden, IslandNPCs, SecretCave, RocketRide and PetSystem all wait on it
	-- before reading a marker position; so does this. Same 90-second budget they use.
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end
	if Workspace:GetAttribute("StandsReady") then
		print(string.format("[AFKFarm] StandsReady after %.1fs -- islands are positioned, safe to read markers", waited))
	else
		warn("[AFKFarm] StandsReady never set after 90s -- building anyway, but if a station ends up floating " ..
			"in the sky a long way from its island, that is why.")
	end

	clearOldStations()
	sweep()
	Workspace.DescendantAdded:Connect(function(d)
		-- A marker that turns up later still gets its station. Deferred a beat so an island parented in one
		-- go is read after its children exist rather than halfway through.
		task.delay(0.5, function() pcall(consider, d) end)
	end)
	if built == 0 then
		print("[AFKFarm] no 'AFK Tank' markers found yet. Drop a Part named 'AFK Tank' on each island " ..
			"(any size, sitting on the ground, rotated to face the way players walk in) and it builds itself.")
	end
	task.wait(10);              sweep()
	task.wait(SCAN_SECS - 10);  sweep()
	local where = "every island with a marker"
	if ONLY_ISLANDS then
		local ns = {}
		for n in pairs(ONLY_ISLANDS) do ns[#ns + 1] = n end
		table.sort(ns)
		where = "island " .. table.concat(ns, ", ") .. " only"
	end
	print(string.format("[AFKFarm] %d station(s) standing (%s). Markers are hidden + CanCollide=false once "
		.. "read, but never renamed, moved or destroyed; each station is one Model named '%s'.",
		built, where, MODEL_NAME))
end)

--======================================================================
-- THE FLOATING TOKENS TURN
--======================================================================
-- The only moving part in the whole build, and it is deliberately cheap: one loop for every station in the
-- game, ticking 12 times a second, and a station whose nearest player is over 260 studs away is skipped
-- entirely. Fourteen stations spinning three coins each at 60Hz, forever, to nobody, is exactly the kind of
-- thing that quietly costs a server its frame -- so they hold still until somebody is there to see it.
task.spawn(function()
	local t = 0
	while true do
		task.wait(1 / 12)
		t = t + 1 / 12
		if #stations > 0 then
			local players = Players:GetPlayers()
			for _, st in ipairs(stations) do
				if st.model.Parent then
					local near = false
					for _, plr in ipairs(players) do
						local ch = plr.Character
						local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
						if hrp and (hrp.Position - st.pos).Magnitude < 260 then near = true; break end
					end
					-- ===== THE PULSE =====
					-- While somebody is plugged into THIS station the reactor breathes: the core band fades
					-- in and out and the light swells with it. It rides the loop that is already running
					-- and only touches two properties, so "the machine is working" costs a transparency and
					-- a brightness rather than a second loop or a particle storm.
					--
					-- Anyone plugged in is by definition standing here, so `near` is already true -- this
					-- never runs for an empty station.
					local busy = false
					for _, h in pairs(hoses) do if h.station == st then busy = true; break end end
					local core = st.hoseAnchor
					if core and core.Parent then
						core.Transparency = busy and (0.10 + 0.28 * (0.5 + 0.5 * math.sin(t * 4.2))) or 0
					end
					if st.energy and st.energy.Parent then
						local lt = st.energy:FindFirstChildOfClass("PointLight")
						if lt then lt.Brightness = busy and (1.1 + 1.5 * (0.5 + 0.5 * math.sin(t * 4.2))) or 1.1 end
						local pe = st.energy:FindFirstChildOfClass("ParticleEmitter")
						if pe then pe.Rate = busy and 26 or 7 end
					end

					-- THE READOUT BREATHES TOO. The bar filling is slow by design -- one token every ninety
					-- seconds -- so between ticks there is nothing on the panel to prove it is alive. The
					-- fill brightening and the status line blinking is that proof, and it costs a colour
					-- and a transparency.
					local pn = st.panel
					if pn and pn.fill and pn.fill.Parent then
						local k = 0.5 + 0.5 * math.sin(t * 3.4)
						pn.fill.BackgroundColor3 = busy and LIME_UI:Lerp(Color3.fromRGB(190, 255, 120), k) or LIME_UI
						pn.status.TextTransparency = busy and (0.10 * k) or 0
						pn.status.TextStrokeTransparency = busy and (0.6 - 0.4 * k) or 1
					end

					if near then
						for _, f in ipairs(st.floaters) do
							if f.model.Parent then
								-- ORBIT + BOB. The angle carries the token round the tank; the phase spaces
								-- the three evenly and also staggers their bob, so they rise and fall out of
								-- step instead of moving as one rigid ring.
								--
								-- Offsetting along +Z after the yaw means each token's own face points OUT
								-- from the tank as it travels -- you always see the T, never the edge.
								local ang = t * 0.85 + f.phase
								local bob = math.sin(t * 1.6 + f.phase) * 0.45
								pcall(function()
									f.model:PivotTo(f.centre
										* CFrame.Angles(0, ang, 0)
										* CFrame.new(0, bob, f.radius))
								end)
							end
						end
					end
				end
			end
		end

		-- THE CORD PULSES. Width swells and the emission comes up together, which reads as something being
		-- PUMPED along it rather than as a glowing stick. Driven off the same clock as the reactor so the
		-- machine and its hose breathe in time -- two throbs at different speeds looks broken, not busy.
		for _, h in pairs(hoses) do
			local b = h.hose
			if b and b.Parent then
				local k = 0.5 + 0.5 * math.sin(t * 5.0)
				b.Width0 = HOSE_W0 + 0.18 * k
				b.Width1 = HOSE_W1 + 0.14 * k
				b.LightEmission = 0.12 + 0.42 * k
			end
		end
	end
end)
