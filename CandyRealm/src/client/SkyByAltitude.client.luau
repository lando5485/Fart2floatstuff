-- SkyByAltitude.client.luau  (LocalScript)  -- the sky thins and darkens as you climb.
--
-- Candy Cane Court sits at Y≈220 and Bakery Summit at Y≈81,620, and the air looked IDENTICAL at both ends.
-- You spend an hour ascending and the world never once acknowledges it. The climb is the whole game; the sky
-- should be a progress bar you can feel.
--
-- ⚠ EVERY HEIGHT IN THIS FILE IS DERIVED FROM IslandOrder, NOT WRITTEN DOWN.
-- This file used to carry the FOOD realm's absolute Ys (Bean Farm 245, Turnip Tranquil 2492, Pizza Palms
-- 24,012) with a "vacuum" band at 27,000. Candy never had those islands, and when the space-economy port
-- re-spaced the tower to 81,620 the entire top two-thirds of the climb fell past the last keyframe into
-- flat vacuum -- while the orbiting satellites, pinned at 25,600-30,500, ended up parked inside slot 8.
-- Keying the gradient to SLOT NUMBERS and the fleet to the SUMMIT means a re-spacing moves the sky with
-- the tower automatically, and this cannot rot again.
--
-- So it's a GRADIENT, driven by the player's height:
--   * ground  -> thick, warm, hazy. Humid farm air; you can't see far.
--   * middle  -> the haze lifts, the blue deepens, the light goes hard and cold.
--   * top     -> almost no air left to scatter light. The sky goes black and the stars come out.
--
-- No cloud parts, no fog, no props -- just Lighting.Atmosphere + ClockTime, eased. Purely cosmetic, purely
-- client-side (Lighting is per-client anyway), and it changes no gameplay value.
--
-- ⚠ EVENTS ARE LEFT COMPLETELY ALONE. The thunderstorm, windstorm, meteor and server events all drive the sky
-- themselves (the storm even DELETES the Atmosphere instance and swaps in classic Fog). While any of them is
-- running, this script writes NOTHING and restores NOTHING -- the event owns the sky and puts it back exactly
-- as it did before this file existed. We ease back in from wherever the event left things.

local RunService = game:GetService("RunService")
local Lighting   = game:GetService("Lighting")
local Players    = game:GetService("Players")

local player = Players.LocalPlayer

-- ============================================================================
-- WHERE THE ISLANDS ACTUALLY ARE. IslandOrder.SLOT_POS is the one table that positions the
-- tower, so reading it here is what keeps the sky and the world in step.
--
-- Falls back to the shipped ladder if the module is missing, rather than collapsing every
-- keyframe onto Y=0 -- a sky stuck in ground haze is a bug you might not notice for a week.
-- ============================================================================
local FALLBACK_Y = { 150, 780, 1848, 3090, 4395, 6187.5, 8073, 10555.5, 13165.5, 16614, 20239.5, 25066.5, 31266.5 }
local slotY, SUMMIT_SLOT, SUMMIT_POS do
	local ok, IslandOrder = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("IslandOrder"))
	end)
	if ok and IslandOrder and IslandOrder.SLOT_POS and #IslandOrder.SLOT_POS > 0 then
		SUMMIT_SLOT = #IslandOrder.SLOT_POS
		SUMMIT_POS  = IslandOrder.SLOT_POS[SUMMIT_SLOT]
		slotY = function(n)
			local pos = IslandOrder.SLOT_POS[math.clamp(n, 1, SUMMIT_SLOT)]
			return pos and pos.Y or (FALLBACK_Y[n] or 0)
		end
	else
		warn("[Sky] IslandOrder unavailable -- falling back to the shipped ladder heights")
		SUMMIT_SLOT = #FALLBACK_Y
		SUMMIT_POS  = Vector3.new(340, FALLBACK_Y[SUMMIT_SLOT], -300)
		slotY = function(n) return FALLBACK_Y[math.clamp(n, 1, SUMMIT_SLOT)] end
	end
end
local SUMMIT_Y = slotY(SUMMIT_SLOT)

-- ============================================================================
-- THE GRADIENT, keyed to CLIMB SLOTS rather than to absolute heights.
--
-- Each keyframe describes the air on arrival at that slot; the script blends between the two
-- bracketing the player. `space` is how "airless" it is: 0 = normal day, 1 = full night.
--
-- Keying to the islands themselves means the sky changes exactly as you ARRIVE somewhere,
-- instead of at some arbitrary number that happens to fall mid-flight -- and, since the Ys
-- come from IslandOrder, re-spacing the tower drags the whole gradient along with it.
--
-- THE SHAPE (unchanged from the original; only the rungs it hangs on have moved): daylight
-- holds most of the climb, then the last five rungs darken on an ACCELERATING curve. A linear
-- ramp would make the midpoint look half-dark the moment you land on it, giving the whole
-- climb away at once -- the point is that it creeps up on you.
-- ============================================================================
local KEYS = {
	{	slot = 1,    -- CANDY CANE COURT. Humid, hazy, warm. You can smell the sugar.
		density = 0.0, offset = 0.0, haze = 0.0, glare = 0.0, -- NO ground haze: the custom skybox shows fully, no gray band
		color = Color3.fromRGB(206, 190, 170), decay = Color3.fromRGB(106, 118, 140),
		space = 0,
	},
	{	slot = 4,    -- GUMTREE PARK. The haze starts to lift; you can see further.
		density = 0.0, offset = 0.0, haze = 0.0, glare = 0.0,
		color = Color3.fromRGB(198, 198, 196), decay = Color3.fromRGB(96, 112, 142),
		space = 0,
	},
	{	slot = 6,    -- CRYSTAL CANDY CAVES. Proper altitude. Thin, clean, the blue deepens.
		density = 0.08, offset = 0.02, haze = 0.2, glare = 0.03,
		color = Color3.fromRGB(180, 194, 214), decay = Color3.fromRGB(70, 96, 140),
		space = 0,
	},
	-- SLOTS 8 -> 12 ARE THE DARKENING, on the accelerating curve described above.
	{	slot = 9,    -- LICORICE TUNNELS. The light has *just* begun to cool. Barely noticeable, deliberately.
		density = 0.21, offset = 0.00, haze = 0.68, glare = 0.03,
		color = Color3.fromRGB(162, 182, 214), decay = Color3.fromRGB(52, 76, 122),
		space = 0.06,
	},
	{	slot = 10,   -- FROSTBELL PEAK. Late afternoon. You can tell now, if you look up.
		density = 0.18, offset = 0.00, haze = 0.52, glare = 0.02,
		color = Color3.fromRGB(150, 172, 206), decay = Color3.fromRGB(44, 66, 110),
		space = 0.18,
	},
	{	slot = 11,   -- MARSHMALLOW CAMP. Evening. Blue going deep; a first star or two.
		density = 0.14, offset = 0.00, haze = 0.34, glare = 0.01,
		color = Color3.fromRGB(134, 156, 196), decay = Color3.fromRGB(32, 50, 92),
		space = 0.38,
	},
	{	slot = 12,   -- SUGARBEET FARM. Dusk. Stars are properly out; the sky is nearly black.
		density = 0.07, offset = 0.00, haze = 0.14, glare = 0.00,
		color = Color3.fromRGB(112, 132, 174), decay = Color3.fromRGB(18, 30, 62),
		space = 0.66,
	},
	{	slot = 13,   -- BAKERY SUMMIT. Night. Density near zero so the stars are CRISP, not washed out.
		density = 0.015, offset = 0.00, haze = 0.0, glare = 0.00,
		color = Color3.fromRGB(88, 106, 148), decay = Color3.fromRGB(4, 7, 18),
		space = 1,
	},
	{	above = 8000, -- ABOVE THE TOWER (where the fleet orbits). Vacuum.
		density = 0.0, offset = 0.00, haze = 0.0, glare = 0.00,
		color = Color3.fromRGB(80, 96, 136), decay = Color3.fromRGB(2, 3, 10),
		space = 1,
	},
}

-- Resolve every keyframe to a real Y once, at load. `slot` reads the island's height straight
-- out of IslandOrder; `above` is an offset past the summit for the one band with no island
-- under it. The blend below only ever reads `.y`, so nothing downstream changes.
for _, k in ipairs(KEYS) do
	k.y = k.slot and slotY(k.slot) or (SUMMIT_Y + (k.above or 0))
end

local SMOOTH = 2.2 -- how fast the sky chases the target. Too high and it strobes on a fast climb.

-- ===== NIGHT AT THE TOP =====
-- Atmosphere DENSITY is what washes stars out -- haze scatters light across the whole sky and drowns them. So
-- the top keyframes drive density to ~0: that, plus a black ambient, is what makes the star field actually
-- read instead of being a faint speckle behind a grey veil.
-- ⚠ THE CLIMB NO LONGER DARKENS. Daylight is held at every altitude; see the write in the render
-- loop for the full reasoning. The two NIGHT_* values below are only read when this is true.
local DARKEN_WITH_ALTITUDE = false
local NIGHT_BRIGHTNESS = 0.25                      -- was 0.6 -- properly dark, not just dim
local NIGHT_AMBIENT    = Color3.fromRGB(8, 9, 18)  -- near-black; anything lighter greys out the stars
local STAR_COUNT       = 9000                      -- a dense field, not the sparse default

-- ============================================================================

-- Capture the world's NORMAL daytime look ONCE, before we touch anything. The night blend below is measured
-- FROM these, so at ground level the sky is bit-for-bit what it always was.
local DAY = {
	clock   = Lighting.ClockTime,
	bright  = Lighting.Brightness,
	ambient = Lighting.OutdoorAmbient,
}

-- Stars need a Sky. If the game already has one, its skybox TEXTURES are left alone (replacing them would be a
-- visual change nobody asked for) -- we only touch what the night sky needs.
--
-- NO MOON. Note we do NOT do this by switching CelestialBodiesShown off: that flag governs the sun AND the
-- moon together, so killing it would delete the sun from the daytime sky as well -- which you'd notice
-- instantly at Bean Farm. Blanking the moon's texture and shrinking it to nothing removes ONLY the moon.
do
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
	end
	if sky.StarCount < STAR_COUNT then sky.StarCount = STAR_COUNT end
	sky.CelestialBodiesShown = true -- keeps the SUN; the moon is removed below
	sky.MoonTextureId   = ""
	sky.MoonAngularSize = 0
end

-- Remove the Terrain "Clouds" layer (the gray, cloud-like shadow overhead) so the
-- skybox shows uninterrupted across the WHOLE sky, not just part of it. Re-checks a
-- couple times in case clouds are added late.
task.spawn(function()
	for _ = 1, 5 do
		local terrain = workspace:FindFirstChildOfClass("Terrain")
		local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
		if clouds then clouds:Destroy() end
		task.wait(1)
	end
end)

-- ============================================================================
-- THE SPACE STATION. Slowly orbits above the top of the tower. Client-side only: it's built from a LocalScript
-- into Workspace, so it exists on THIS client alone -- nothing replicates and the server pays nothing.
--
-- Sized to be READ, not to be to scale. A realistically-tiny station 3,000 studs away is one grey pixel; this
-- is ~150 studs across so it's unmistakably a space station when you finally get up there.
-- ============================================================================

-- ===== CHRISTMAS CANDY-CANE PALETTE =====
-- These six craft came over from the Space Realm with the rest of this file: a grey-hulled station
-- with navy solar arrays and gold-foil satellite buses. Correct for that game, and the only thing
-- in the candy sky that still looked like hardware. The SHAPES stay -- they read well at 2,000
-- studs and the orbit maths is built around their sizes -- but every surface is now confectionery.
--
-- The names are kept (HULL, TRUSS, PANEL...) because they are used in a dozen places below and a
-- rename would touch far more than a re-skin needs to. What each one MEANS is in its comment.
local HULL       = Color3.fromRGB(252, 248, 244)  -- peppermint white: the sugar body of everything
local TRUSS      = Color3.fromRGB(236,  72, 110)  -- candy-cane red: booms, spars and stripes
local PANEL      = Color3.fromRGB(150, 225, 190)  -- spearmint green, where the solar arrays were
local PANEL_EDGE = Color3.fromRGB(255, 205,  90)  -- gold sugar trim along every panel edge
local GOLD_FOIL  = Color3.fromRGB(236,  72, 110)  -- red foil wrapper on the satellite bus
local CANE_WHITE = Color3.fromRGB(252, 248, 244)  -- the white half of a barber stripe
local HOLLY      = Color3.fromRGB( 86, 168, 104)  -- the one non-candy note, for the station's holly
local UPX        = CFrame.Angles(0, 0, math.rad(90)) -- Roblox cylinders run along X; stand them upright

local skyFolder = Instance.new("Folder")
skyFolder.Name   = "Orbit"
skyFolder.Parent = Workspace

local function mkPart(model, name, shape, size, color, cf, material)
	local p = Instance.new("Part")
	p.Name       = name
	p.Shape      = shape
	p.Size       = size
	p.Color      = color
	p.CFrame     = cf
	p.Material   = material or Enum.Material.SmoothPlastic
	p.Anchored   = true
	p.CanCollide = false -- you can fly up here; solid orbital junk would swat you out of the sky
	p.CanQuery   = false
	p.CanTouch   = false
	p.CastShadow = false
	p.Parent     = model
	return p
end

-- Give a craft a blinking RED beacon and return it, so the orbit loop can pulse it.
--
-- A Neon ball + a PointLight -- the physical light on the craft itself, nothing else. (An earlier attempt bolted
-- a screen-space BillboardGui dot on top of this to fight the viewing distance; it looked like a UI sticker
-- stuck to the sky rather than a light on a spacecraft, so it's gone.)
--
-- BRIGHTER: the ball is bigger, the Neon is pure red so it blooms, and the PointLight's Brightness and Range
-- are both way up -- so it genuinely burns rather than glowing politely.
local BEACON_RED = Color3.fromRGB(255, 30, 30)

local function addBeacon(model, at, scale)
	local s = scale or 1
	local b = mkPart(model, "Beacon", Enum.PartType.Ball, Vector3.new(7, 7, 7) * s, BEACON_RED, at, Enum.Material.Neon)

	local l = Instance.new("PointLight")
	l.Color      = BEACON_RED
	l.Range      = 160  -- was 40
	l.Brightness = 14   -- was 3
	l.Shadows    = false -- a beacon shouldn't cast shadows through its own solar panels
	l.Parent     = b

	return b, l
end

-- ===== THE STATION =====
-- Sized to be READ, not to scale. A realistically-tiny station 2,600 studs away is one grey pixel; this is
-- ~150 studs across, so it's unmistakably a space station when you finally get up there.
local function buildStation()
	local m = Instance.new("Model")
	m.Name = "SpaceStation"

	-- THE SPINE IS A CANDY CANE. It used to be one flat grey bar 150 studs long -- the single most
	-- hardware-looking thing in the sky. Built as alternating red and white segments instead, which
	-- is the whole trick: a barber stripe reads as a candy cane from any distance, where a solid
	-- red bar would just read as a red bar.
	do
		local SEGS, LEN = 15, 150
		local seg = LEN / SEGS
		for k = 0, SEGS - 1 do
			mkPart(m, "Spine" .. k, Enum.PartType.Cylinder, Vector3.new(seg, 6, 6),
				(k % 2 == 0) and TRUSS or CANE_WHITE,
				CFrame.new(-LEN/2 + seg*(k + 0.5), 0, 0) * CFrame.Angles(0, math.rad(90), 0) * UPX)
		end
		-- ...and it hooks at one end, so the silhouette is unmistakably a cane and not a striped pole
		for k = 0, 3 do
			local a = math.rad(28 + k * 34)
			mkPart(m, "Hook" .. k, Enum.PartType.Cylinder, Vector3.new(seg, 6, 6),
				(k % 2 == 0) and CANE_WHITE or TRUSS,
				CFrame.new(LEN/2, 0, 0) * CFrame.Angles(0, 0, a) * CFrame.new(seg*(k*0.9 + 0.5), seg*0.7, 0)
					* CFrame.Angles(0, math.rad(90), 0) * UPX)
		end
	end

	-- Pressurised modules -- cylinders, the giveaway shape of a station.
	mkPart(m, "ModuleA", Enum.PartType.Cylinder, Vector3.new(34, 15, 15), HULL, CFrame.new(0, -10, 0) * CFrame.Angles(0, math.rad(90), 0))
	mkPart(m, "ModuleB", Enum.PartType.Cylinder, Vector3.new(22, 12, 12), HULL, CFrame.new(0, -10, 22) * CFrame.Angles(0, math.rad(90), 0) * UPX)
	mkPart(m, "ModuleC", Enum.PartType.Cylinder, Vector3.new(18, 10, 10), HULL, CFrame.new(0, -10, -22) * CFrame.Angles(0, math.rad(90), 0) * UPX)
	mkPart(m, "Node",    Enum.PartType.Ball,     Vector3.new(16, 16, 16), HULL, CFrame.new(0, -10, 0))

	-- SOLAR ARRAYS. Four big wings -- the silhouette everyone recognises. Without them it's just a pipe.
	for i, sx in ipairs({ -52, -26, 26, 52 }) do
		mkPart(m, "Array" .. i, Enum.PartType.Block, Vector3.new(20, 0.6, 76), PANEL, CFrame.new(sx, 0, 0))
		-- Gold edge strips: they catch the light and stop the panels reading as flat blue slabs.
		mkPart(m, "ArrayEdgeA" .. i, Enum.PartType.Block, Vector3.new(20, 1.0, 2), PANEL_EDGE, CFrame.new(sx, 0, 38))
		mkPart(m, "ArrayEdgeB" .. i, Enum.PartType.Block, Vector3.new(20, 1.0, 2), PANEL_EDGE, CFrame.new(sx, 0, -38))
		mkPart(m, "ArrayBoom" .. i, Enum.PartType.Cylinder, Vector3.new(6, 2, 2), TRUSS,
			CFrame.new(sx, 0, 0) * CFrame.Angles(0, math.rad(90), 0) * UPX)
	end

	-- Where the radiators were: a ribbon and a sprig of holly, so the station reads as a present
	-- rather than a machine. Same footprint, so nothing about the silhouette's size changes.
	mkPart(m, "RibbonA", Enum.PartType.Block, Vector3.new(30, 1.2, 16), TRUSS,      CFrame.new(0,  14, 0))
	mkPart(m, "RibbonB", Enum.PartType.Block, Vector3.new(30, 1.2, 16), CANE_WHITE, CFrame.new(0, -30, 0))
	for k = 0, 2 do
		mkPart(m, "Holly" .. k, Enum.PartType.Block, Vector3.new(12, 1.0, 5), HOLLY,
			CFrame.new(0, 16, 0) * CFrame.Angles(0, k * math.rad(60), 0) * CFrame.new(7, 0, 0))
	end
	mkPart(m, "Berry", Enum.PartType.Ball, Vector3.new(4, 4, 4), Color3.fromRGB(226, 44, 66), CFrame.new(0, 17, 0))

	local beacon, light = addBeacon(m, CFrame.new(0, -10, 30), 1.4) -- station gets the biggest beacon
	return m, beacon, light
end

-- ===== A SMALL SATELLITE =====
-- Gold foil bus, two panels, a dish. Much simpler than the station, because at this distance the silhouette is
-- all you get: a bright body, two wings, a dish.
local function buildSatellite(scale)
	local m = Instance.new("Model")
	m.Name = "Satellite"
	local s = scale or 1

	mkPart(m, "Bus",  Enum.PartType.Block, Vector3.new(14, 12, 12) * s, GOLD_FOIL, CFrame.new())
	-- A wrapper band across the bus, so it reads as a sweet rather than a red box
	mkPart(m, "BusBand", Enum.PartType.Block, Vector3.new(15, 4, 13) * s, CANE_WHITE, CFrame.new())
	-- THE BOOM IS A CANDY CANE, same trick as the station's spine: eleven alternating segments
	-- instead of one solid red cylinder.
	do
		local SEGS, LEN = 11, 46
		local seg = LEN / SEGS
		for k = 0, SEGS - 1 do
			mkPart(m, "Cane" .. k, Enum.PartType.Cylinder, Vector3.new(seg, 2.2, 2.2) * s,
				(k % 2 == 0) and TRUSS or CANE_WHITE,
				CFrame.new(0, (-LEN/2 + seg*(k + 0.5)) * s, 0) * CFrame.Angles(0, 0, math.rad(90)) * UPX)
		end
	end

	for _, sx in ipairs({ -1, 1 }) do
		mkPart(m, "Panel", Enum.PartType.Block, Vector3.new(1, 10, 30) * s, PANEL, CFrame.new(sx * 24 * s, 0, 0))
		mkPart(m, "PanelEdge", Enum.PartType.Block, Vector3.new(1.4, 11, 2) * s, PANEL_EDGE, CFrame.new(sx * 24 * s, 0, 15 * s))
	end

	-- Dish
	mkPart(m, "DishNeck", Enum.PartType.Cylinder, Vector3.new(6, 1.4, 1.4) * s, TRUSS,
		CFrame.new(0, 8 * s, 0) * CFrame.Angles(0, math.rad(90), 0) * UPX)
	mkPart(m, "Dish", Enum.PartType.Cylinder, Vector3.new(1.6, 14, 14) * s, Color3.fromRGB(236, 238, 242),
		CFrame.new(0, 12 * s, 0) * UPX)

	local beacon, light = addBeacon(m, CFrame.new(0, -7 * s, 0), s)
	return m, beacon, light
end

-- ===== THE FLEET =====
-- Different radii, altitudes, speeds, tilts and phases, so they never sit in a neat line -- a sky where
-- everything orbits at the same rate reads as a carousel, not as space.
-- Centred over the SUMMIT island, not over a hard-coded XZ. The old value (380, -391) was Pizza
-- Palms in the Food realm; Candy summits at a different corner of the map entirely.
local CENTRE = Vector3.new(SUMMIT_POS.X, 0, SUMMIT_POS.Z)

-- ===== THE FLEET =====
-- Different radii, altitudes, speeds, tilts and phases, so they never sit in a neat line -- a sky
-- where everything orbits at the same rate reads as a carousel, not as space.
--
-- ALTITUDES ARE OFFSETS ABOVE THE SUMMIT, not absolute Ys. They used to be absolute (25,600 to
-- 30,500), which put them a comfortable 1.5k-6.5k above the Food realm's 24,012 summit -- and
-- then squarely INSIDE slot 8 once the candy tower grew to 81,620. The original spread is kept
-- exactly; only its anchor moved, so the fleet now floats over whatever the top island is.
local FLEET_BASE = SUMMIT_Y
local FLEET = {
	{ kind = "station", up = 3500, radius = 2600, seconds = 240, phase = 0.00, tilt = 8,   bob = 260 },
	{ kind = "sat",     up = 2200, radius = 3400, seconds = 155, phase = 1.90, tilt = -14, bob = 420, scale = 1.0 },
	{ kind = "sat",     up = 5000, radius = 2100, seconds = 110, phase = 3.60, tilt = 22,  bob = 300, scale = 0.7 },
	{ kind = "sat",     up = 1600, radius = 4200, seconds = 300, phase = 5.10, tilt = -6,  bob = 520, scale = 1.4 },
	{ kind = "sat",     up = 6500, radius = 2800, seconds = 190, phase = 2.70, tilt = 30,  bob = 240, scale = 0.85 },
	{ kind = "sat",     up = 4200, radius = 5000, seconds = 380, phase = 4.40, tilt = 12,  bob = 600, scale = 1.2 },
}
for _, cfg in ipairs(FLEET) do
	cfg.y = FLEET_BASE + cfg.up
end

local craft = {} -- [{ model, beacon, light, cfg }]

for _, cfg in ipairs(FLEET) do
	local model, beacon, light
	if cfg.kind == "station" then
		model, beacon, light = buildStation()
	else
		model, beacon, light = buildSatellite(cfg.scale)
	end

	local root = mkPart(model, "Root", Enum.PartType.Block, Vector3.new(1, 1, 1), HULL, CFrame.new())
	root.Transparency = 1
	model.PrimaryPart = root
	model.Parent      = skyFolder

	-- StreamingEnabled is ON in this place. Client-created parts aren't streamed away, but these sit thousands
	-- of studs from the player for most of the game -- mark them Persistent anyway. The donation blimp was
	-- invisible for exactly this reason and it costs nothing to be sure.
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)

	craft[#craft + 1] = { model = model, beacon = beacon, light = light, cfg = cfg }
end

local function ensureAtmosphere()
	local a = Lighting:FindFirstChildOfClass("Atmosphere")
	if not a then
		a = Instance.new("Atmosphere")
		a.Name   = "Atmosphere"
		a.Parent = Lighting
	end
	return a
end

-- Find the two keyframes bracketing `y` and blend between them.
local function sample(y)
	if y <= KEYS[1].y then return KEYS[1] end
	if y >= KEYS[#KEYS].y then return KEYS[#KEYS] end
	for i = 1, #KEYS - 1 do
		local a, b = KEYS[i], KEYS[i + 1]
		if y >= a.y and y <= b.y then
			local t = (y - a.y) / (b.y - a.y)
			return {
				density = a.density + (b.density - a.density) * t,
				offset  = a.offset  + (b.offset  - a.offset)  * t,
				haze    = a.haze    + (b.haze    - a.haze)    * t,
				glare   = a.glare   + (b.glare   - a.glare)   * t,
				space   = a.space   + (b.space   - a.space)   * t,
				color   = a.color:Lerp(b.color, t),
				decay   = a.decay:Lerp(b.decay, t),
			}
		end
	end
	return KEYS[#KEYS]
end

-- Where the sky currently IS (not where it wants to be). It eases toward the target instead of snapping, or a
-- fast climb would strobe through the bands.
local cur = nil
local clock = 0 -- drives the station's orbit; ticks regardless of events so it never teleports

RunService.RenderStepped:Connect(function(dt)
	-- ORBIT THE FLEET. Outside the event guard on purpose: these are physical objects in the sky, not a lighting
	-- effect, so they should keep drifting through a thunderstorm rather than freezing mid-orbit and then
	-- jumping when the storm ends.
	clock += dt
	for i, c in ipairs(craft) do
		local cfg = c.cfg
		local a   = (clock / cfg.seconds) * math.pi * 2 + cfg.phase
		local pos = Vector3.new(
			CENTRE.X + math.cos(a) * cfg.radius,
			cfg.y + math.sin(a * 2) * cfg.bob, -- gentle rise and fall, so the orbit isn't a flat ring
			CENTRE.Z + math.sin(a) * cfg.radius
		)
		-- Nose along the tangent: they should look like they're travelling, not sliding sideways.
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		c.model:PivotTo(CFrame.lookAt(pos, pos + tangent) * CFrame.Angles(0, 0, math.rad(cfg.tilt)))

		-- Each beacon blinks at its own rate. A fleet blinking in unison looks like one object, or a bug.
		-- A SHARP blink, not a fade: the dot is either fully on or fully gone. A soft pulse at this distance
		-- just reads as a dim smudge -- the hard on/off is what makes it obviously a beacon.
		local blink = math.sin(clock * (1.6 + i * 0.35)) > 0.55
		c.beacon.Transparency = blink and 0 or 1
		c.light.Enabled       = blink
	end

	-- ANY big event owns the sky. Same flags CoreClient gates on (CoreClient.client.lua:749), plus the meteor.
	-- The thunderstorm DELETES the Atmosphere outright, so we must not touch it OR recreate what it removed.
	if _G.thunderstormActive or _G.windstormActive or _G.serverEventActive or _G.meteorEventActive then
		cur = nil -- forget our state, so when the event ends we ease in from the event's sky, not a stale one
		return
	end

	-- A QUEST THAT OWNS THE SKY OWNS IT, for exactly as long as it says so.
	--
	-- The `else` branch below writes ClockTime, Brightness and OutdoorAmbient EVERY FRAME, on purpose --
	-- "the sky is the thing that owns them here". That is right for scenery and wrong for the four quests
	-- that darken the world as their main effect, because it silently undid all four:
	--   * TaffyStorm dims to 45% brightness for the storm      -> back to full daylight next frame
	--   * SummitBell drops the light for the blizzard whiteout -> same
	--   * TunnelBlast sets Brightness 0 for a sealed black mine, and its own comment says "ambient light
	--     is what stops a cave being dark"                     -> the cave was never dark
	--   * CandyMine's finale storm                             -> same
	-- Only their FOG survived, because fog is the one thing this file deliberately never touches. So each
	-- of those quests now registers a claim (see setStormSky / setWeather / caveDark) and we stand down
	-- the same way we do for a server event -- including forgetting `cur`, so the sky eases back in from
	-- whatever the quest left rather than lurching from a stale value.
	local claims = _G.questSkyClaims
	if claims and next(claims) ~= nil then
		cur = nil
		return
	end

	-- THE INTRO STAYS IN DAYLIGHT, ON PURPOSE. An earlier pass had the cinematic publish the altitude it
	-- was filming so the summit shots played under the dark high-altitude sky -- and the owner's verdict
	-- was that the intro must stay BRIGHT. Since the cinematic never moves the character (it moves the
	-- streaming focus), sampling the character's height here does exactly that: the body stands on
	-- island 1 for the whole intro, so every shot renders in ground-level candy daylight. During real
	-- gameplay this is simply the correct behaviour it always was.
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local target = sample(hrp.Position.Y)

	if not cur then
		-- First frame, or straight out of an event: adopt the target wholesale rather than easing from stale
		-- values, which would look like the sky lurching for no reason.
		cur = {
			density = target.density, offset = target.offset, haze = target.haze,
			glare = target.glare, space = target.space, color = target.color, decay = target.decay,
		}
	else
		-- Frame-rate independent easing: the alpha depends on dt, so the sky moves at the same speed at 30fps
		-- and at 144fps. A flat per-frame lerp would ease ~5x faster on a high-refresh monitor.
		local k = 1 - math.exp(-SMOOTH * dt)
		cur.density = cur.density + (target.density - cur.density) * k
		cur.offset  = cur.offset  + (target.offset  - cur.offset)  * k
		cur.haze    = cur.haze    + (target.haze    - cur.haze)    * k
		cur.glare   = cur.glare   + (target.glare   - cur.glare)   * k
		cur.space   = cur.space   + (target.space   - cur.space)   * k
		cur.color   = cur.color:Lerp(target.color, k)
		cur.decay   = cur.decay:Lerp(target.decay, k)
	end

	local atm = ensureAtmosphere()
	atm.Density = cur.density
	atm.Offset  = cur.offset
	atm.Haze    = cur.haze
	atm.Glare   = cur.glare
	atm.Color   = cur.color
	atm.Decay   = cur.decay

	-- SPACE / DARKENING -- OFF. It is DAYLIGHT AT EVERY ALTITUDE now.
	--
	-- The climb used to drive ClockTime toward midnight from island 10 up, dropping Brightness to
	-- 0.25 and the ambient to near-black so the stars came out at the summit. It reads as dusk
	-- falling on you the higher you get, and it takes the top third of the tower -- the islands with
	-- the most built on them -- and puts them in the dark. Not what this realm wants.
	--
	-- The ATMOSPHERE gradient above is untouched and still runs the whole height: the air still
	-- thins, the haze still drops, the horizon still opens up as you climb. That was always the part
	-- doing the "you are getting high up" work. Only the light level is pinned.
	--
	-- Set DARKEN_WITH_ALTITUDE back to true to restore the night sky exactly as it was -- `cur.space`
	-- is still tracked and eased every frame, so nothing else has to change.
	if DARKEN_WITH_ALTITUDE then
		Lighting.ClockTime      = DAY.clock + (0 - DAY.clock) * cur.space
		Lighting.Brightness     = DAY.bright + (NIGHT_BRIGHTNESS - DAY.bright) * cur.space
		Lighting.OutdoorAmbient = DAY.ambient:Lerp(NIGHT_AMBIENT, cur.space)
	else
		-- written every frame, not once: an event or another script can move these, and the sky is
		-- the thing that owns them here
		Lighting.ClockTime      = DAY.clock
		Lighting.Brightness     = DAY.bright
		Lighting.OutdoorAmbient = DAY.ambient
	end

	-- Fog is deliberately NOT touched: the thunderstorm drives FogStart/FogEnd/FogColor as its main effect, and
	-- two systems writing the same properties would fight every frame.
end)

print(("[Sky] ready -- gradient Y=%d..%d, DAYLIGHT AT ALL ALTITUDES (no darkening), %d craft in orbit, no moon (events untouched)")
	:format(KEYS[1].y, KEYS[#KEYS].y, #FLEET))
