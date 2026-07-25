--======================================================================
-- RealmPortals.client.luau  (LocalScript)   [SENDING PLACE -- Bean Island]
--======================================================================
-- The three realm portals on Bean Island, built as a polished hub plaza. Dino, Space, Candy.
--
-- PLACEMENT IS YOURS, NOT MINE. Each portal is anchored to ITS OWN marker brick -- the one you placed.
-- Nothing here moves, re-spaces or re-orders them. The bricks say where each portal goes, which way it
-- faces, and how high off the ground it stands; this script only builds detail around that.
-- Your markers sit ~12-14 studs apart, so the whole build is deliberately sized to fit inside that:
-- FOOTPRINT_R caps how far any piece may stray from its own marker, and every platform, arch and
-- decoration is kept inside it. That is what stops the three from bleeding into each other.
--
-- The bricks themselves are invisible and inert -- pure placement markers, never scenery.
--
-- HEADERS ARE ALIGNED. All three name plates are pinned to the SAME world height (the tallest portal's
-- top), so the row reads level even if the bricks are at slightly different heights. One header per
-- portal, each adorned to its own anchor: they can't drift onto a neighbour.
--
-- THE FORCE FIELD IS THE DOOR: it fills the opening, and its Touched starts the transfer. Touch -> fire
-- INTENT (a realm key) -> the SERVER validates the chain gate and teleports. The client never teleports.
--======================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

-- DUPLICATE GUARD: if an old copy of this script got saved into the place file, Rojo adds a SECOND one
-- beside it and both run -- they fight over the portals and you get two of everything. Bail loudly.
if _G.__RealmPortalsClient then
	warn("[RealmPortals] a second copy of RealmPortals.client is running -- this one is bailing out. " ..
		"Delete the stale LocalScript in StarterPlayerScripts and re-sync Rojo.")
	return
end
_G.__RealmPortalsClient = true

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- NEUTRALIZE STALE DUPLICATES: an OLD copy of this LocalScript baked into the place builds a second set of
-- portals and shows its own messages. Destroy every same-named sibling LocalScript (best effort). The clean
-- fix is deleting it in Studio's StarterPlayerScripts.
local function nukeStaleClientCopies()
	local removed = 0
	for _, container in ipairs({ script.Parent, player:FindFirstChild("PlayerScripts"), playerGui, game:GetService("ReplicatedFirst") }) do
		if container then
			for _, inst in ipairs(container:GetDescendants()) do
				if inst ~= script and inst:IsA("LocalScript") and inst.Name == script.Name then
					pcall(function() inst.Disabled = true; inst:Destroy() end)
					removed = removed + 1
				end
			end
		end
	end
	if removed > 0 then warn("[RealmPortals] removed " .. removed .. " STALE duplicate client script(s) -- delete them in Studio for good") end
end
nukeStaleClientCopies()
task.delay(1, nukeStaleClientCopies); task.delay(4, nukeStaleClientCopies)

--------------------------------------------------------------------------------
-- dimensions (studs) -- everything is sized to fit the spacing you already have
--------------------------------------------------------------------------------
local PORTAL_W   = 8.4    -- opening width
local PORTAL_H   = 11     -- opening height
local FOOTPRINT_R = 5.4   -- HARD CAP: no piece of a portal may sit further than this from its marker.
local PLATFORM_R = 5.2    -- circular platform (10.4 wide -> fits inside your ~12-stud gaps, never touches)
local PLATFORM_H = 1.3
local RING_SEGS  = 24     -- stones around the arch
local RUNE_EVERY = 4      -- every Nth stone carries a glowing rune
local PORTAL_YAW = -90    -- degrees CLOCKWISE off the marker's facing. Wrong way round? 0 / 90 / 180.
local BOB_AMP    = 0.3    -- idle float
local BOB_SPEED  = 1.1
local LABEL_RANGE = 50    -- studs: headers/lock/requirement only appear this close, like an NPC name tag

-- MASTER BRIGHTNESS. Every light in every portal comes from these four numbers -- turn them down here and
-- the whole row dims together. Two PointLights per portal is the ENTIRE lighting budget (props glow by
-- being Neon, not by casting light), because Roblox blows out fast and the bloom was eating the stonework.
-- LOOKS[realm].dim trims an individual realm further -- Candy runs low, its pink throws more light.
-- A locked portal isn't a separate level -- it just runs these at 65% (see `k` in render()).
local LIGHT_A     = 0.31  -- the realm's main colour
local LIGHT_B     = 0.20  -- its second colour, blended in
local LIGHT_PULSE = 0.47  -- what LIGHT_A breathes up to on an OPEN portal

--------------------------------------------------------------------------------
-- the three themes -- each gets TWO lights, so the glow is a blend, not a flat wash
--------------------------------------------------------------------------------
-- STYLE: flat, chunky, cartoony -- the look the purple Space portal had. Everything is SmoothPlastic or
-- Neon; there is deliberately NO Rock, Slate, Cobblestone, DiamondPlate, Sand or Glass anywhere in this
-- file. Depth comes from a darker bevel behind a lighter face, not from a gritty texture.
local FLAT = Enum.Material.SmoothPlastic
local GLOW = Enum.Material.Neon
-- STONE is matte Plastic, not SmoothPlastic: it keeps the surface SMOOTH (no pebbles, no grit, no
-- normal-mapped gravel) while giving it the faint matte tooth of poured concrete instead of the wet
-- shine of plastic. Roblox's actual Concrete material is a gritty photo texture -- that's the thing we
-- are avoiding. Candy and glowing pieces stay on SmoothPlastic/Neon, which is where you want the gloss.
local STONE = Enum.Material.Plastic

local LOOKS = {
	space = {
		emoji = "\xF0\x9F\x9A\x80", title = "SPACE REALM", name = "Space Realm",
		stone   = Color3.fromRGB(96, 66, 168),   stoneMat = STONE, -- dark purple stone
		bevel   = Color3.fromRGB(62, 40, 116),                    -- the shadow side of it
		rune    = Color3.fromRGB(150, 120, 255),
		vortex  = Color3.fromRGB(120, 80, 235),
		lightA  = Color3.fromRGB(90, 150, 255),  -- blue...
		lightB  = Color3.fromRGB(185, 120, 255), -- ...and purple
		spark   = Color3.fromRGB(235, 228, 255),
		plate   = Color3.fromRGB(70, 50, 122),
		sparkSize = 0.5, sparkRate = 36, spin = 1.5,
		dim = 1, -- per-realm brightness trim; Candy runs lower because white light blows out
	},
	dino = {
		emoji = "\xF0\x9F\xA6\x96", title = "DINO REALM", name = "Dino Realm",
		-- warm sandstone: distinctly its OWN brick, not the same pale stone as Candy
		stone   = Color3.fromRGB(186, 166, 128), stoneMat = STONE,
		bevel   = Color3.fromRGB(140, 122, 90),
		rune    = Color3.fromRGB(120, 235, 130), -- small green crystal accents
		vortex  = Color3.fromRGB(70, 205, 100),
		lightA  = Color3.fromRGB(105, 235, 130), -- green energy
		lightB  = Color3.fromRGB(190, 245, 140),
		spark   = Color3.fromRGB(210, 255, 170),
		plate   = Color3.fromRGB(120, 150, 96),
		sparkSize = 1.1, sparkRate = 20, spin = 0.8,
		dim = 1,
	},
	candy = {
		emoji = "\xF0\x9F\x8D\xAD", title = "CANDY REALM", name = "Candy Realm",
		-- DEEPER bubblegum pink. The old near-white pink glared next to Dino's sandstone and Space's
		-- purple; this one is saturated rather than pale, so the frosting and gumdrops on the frame still
		-- pop against it instead of washing into it.
		stone   = Color3.fromRGB(214, 96, 156), stoneMat = STONE,
		bevel   = Color3.fromRGB(166, 62, 116),
		rune    = Color3.fromRGB(255, 214, 236),
		vortex  = Color3.fromRGB(222, 96, 170),
		lightA  = Color3.fromRGB(232, 104, 172), -- deeper pink...
		lightB  = Color3.fromRGB(250, 196, 222), -- ...and a soft rose. Pure white blew the portal out.
		spark   = Color3.fromRGB(255, 226, 196),
		plate   = Color3.fromRGB(190, 96, 142),
		sparkSize = 1.6, sparkRate = 18, spin = 0.55,
		dim = 0.45, -- ~45% of Space/Dino: pink throws far more light than the green or the purple
	},
}

-- (There is deliberately no "locked" palette any more. A locked portal keeps its realm's colours and its
-- swirling middle -- it's just dimmer, with the lock sign up. See render().)

local enterEvent = ReplicatedStorage:WaitForChild("RealmPortalEvent", 30)
if not enterEvent then
	warn("[RealmPortals] RealmPortalEvent missing -- is RealmPortals.server.lua running?")
	return
end

--------------------------------------------------------------------------------
-- centre-screen status message
--------------------------------------------------------------------------------
local msgGui = Instance.new("ScreenGui")
msgGui.Name = "RealmPortalMsg"; msgGui.ResetOnSpawn = false; msgGui.IgnoreGuiInset = true
msgGui.DisplayOrder = 60; msgGui.Parent = playerGui

local msgLbl = Instance.new("TextLabel")
msgLbl.AnchorPoint = Vector2.new(0.5, 0.5)
msgLbl.Position = UDim2.new(0.5, 0, 0.42, 0)
msgLbl.Size = UDim2.new(0, 580, 0, 78)
msgLbl.BackgroundColor3 = Color3.fromRGB(14, 14, 22)
msgLbl.BackgroundTransparency = 1
msgLbl.Font = Enum.Font.FredokaOne
msgLbl.TextScaled = true
msgLbl.TextColor3 = Color3.new(1, 1, 1)
msgLbl.Text = ""
msgLbl.Visible = false
msgLbl.Parent = msgGui
Instance.new("UICorner", msgLbl).CornerRadius = UDim.new(0, 16)
local msgStroke = Instance.new("UIStroke", msgLbl); msgStroke.Thickness = 3
local msgPad = Instance.new("UIPadding", msgLbl)
msgPad.PaddingLeft = UDim.new(0, 16); msgPad.PaddingRight = UDim.new(0, 16)
msgPad.PaddingTop  = UDim.new(0, 12); msgPad.PaddingBottom = UDim.new(0, 12)

local msgToken = 0
local function showMsg(text, tint, seconds)
	msgToken += 1
	local mine = msgToken
	msgLbl.Text = text
	msgStroke.Color = tint or Color3.fromRGB(200, 200, 200)
	msgLbl.BackgroundTransparency = 0.15
	msgLbl.Visible = true
	if seconds then
		task.delay(seconds, function()
			if msgToken == mine then
				msgLbl.Visible = false; msgLbl.BackgroundTransparency = 1; msgLbl.Text = ""
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- part builders. Everything is cosmetic + client-only: anchored, no collision, no query, no touch.
-- (The force field re-enables its own CanTouch -- it's the one piece that starts a transfer.)
--------------------------------------------------------------------------------
-- Everything is SOLID by default -- you bump into the stonework, you stand on the plaza, you can't walk
-- through a lantern. The only things you may pass through are listed in PASS_THROUGH below: the portal's
-- own interior (that's the door), and small trip-hazard clutter like flowers and sprinkles that would
-- otherwise snag you as you walk.
local PASS_THROUGH = {
	ForceField = true, Depth1 = true, Depth2 = true, Depth3 = true, Depth4 = true, -- walk INTO the portal
	Swirl1 = true, Swirl2 = true, Anchor = true,
	Flower = true, Grass = true, Sprinkle = true, Star = true,                     -- would only trip you up
	Rune = true, Engraving = true, Spoke = true, Medallion = true,                 -- flush with the floor
}

local function newPart(parent, name, size, cf, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = not PASS_THROUGH[name]
	p.CanQuery = true
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ball(parent, name, d, cf, color, material)
	local p = newPart(parent, name, Vector3.new(d, d, d), cf, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

-- a Cylinder's axis runs along its own X, so `len` is along X and the circular face is Y/Z
local function cyl(parent, name, len, dia, cf, color, material)
	local p = newPart(parent, name, Vector3.new(len, dia, dia), cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

--------------------------------------------------------------------------------
-- themed decoration around each platform
-- Every offset below is kept inside FOOTPRINT_R of the marker -- that is the whole trick to keeping
-- three portals this close together without them visually colliding.
--------------------------------------------------------------------------------
local function buildDinoScenery(f, top, floaters, pulsers)
	local BONE  = Color3.fromRGB(242, 238, 224) -- bright cartoon bone, not weathered ivory
	local ROCK  = Color3.fromRGB(178, 178, 182) -- chunky grey stone
	local FERN  = Color3.fromRGB(96, 190, 78)
	local VINE  = Color3.fromRGB(86, 176, 70)
	local AMBER = Color3.fromRGB(120, 235, 130) -- green crystals now, to match the realm's energy

	for i = -1, 1, 2 do -- ribcage curving up out of the stone, tucked behind the arch
		for r = 1, 3 do
			cyl(f, "Rib", 4.2 - r * 0.45, 0.5,
				top * CFrame.new(i * (3.3 + r * 0.3), 1.3 + r * 0.3, -1.5 - r * 0.7)
					* CFrame.Angles(0, 0, math.rad(90 + (12 + r * 9) * i)),
				BONE, FLAT)
		end
	end

	local skull = ball(f, "Skull", 1.9, top * CFrame.new(-3.6, 0.75, 2.6), BONE, FLAT)
	skull.Size = Vector3.new(1.9, 1.6, 2.5) -- squashed into a snout
	newPart(f, "Jaw", Vector3.new(1.6, 0.34, 2.0), top * CFrame.new(-3.6, 0.05, 2.85), BONE, FLAT)

	for _, s in ipairs({ { 3.4, 2.8, 24 }, { -2.0, -3.3, -40 } }) do -- fossil slabs pressed into the floor
		local slab = newPart(f, "FossilSlab", Vector3.new(2.6, 0.26, 1.9),
			top * CFrame.new(s[1], 0.06, s[2]) * CFrame.Angles(0, math.rad(s[3]), 0),
			Color3.fromRGB(152, 152, 158), STONE)
		for b = -1, 1 do
			ball(f, "Vertebra", 0.55, slab.CFrame * CFrame.new(b * 0.75, 0.14, 0), BONE, FLAT)
		end
	end

	for _, fr in ipairs({ { 4.2, -1.6 }, { -4.1, -2.2 }, { 1.7, 4.0 } }) do -- fern clumps
		for leaf = 0, 4 do
			local a = math.rad(leaf * 72)
			newPart(f, "Fern", Vector3.new(0.28, 2.2, 0.95),
				top * CFrame.new(fr[1] + math.cos(a) * 0.4, 0.95, fr[2] + math.sin(a) * 0.4)
					* CFrame.Angles(math.rad(math.cos(a) * 26), a, math.rad(math.sin(a) * 26)),
				FERN, FLAT)
		end
	end

	for _, b in ipairs({ { -4.4, -0.7, 1.5 }, { 4.4, 2.0, 1.25 }, { 0.5, -4.4, 1.05 } }) do -- chunky boulders
		ball(f, "Boulder", b[3], top * CFrame.new(b[1], b[3] * 0.32, b[2]), ROCK, STONE) -- no cracks: clean shapes
	end

	for i = 1, 3 do -- amber crystals: Neon, but NO PointLight -- they glow without bleaching the scene
		local a = math.rad(30 + i * 118)
		local shard = newPart(f, "AmberCrystal", Vector3.new(0.55, 1.5 + i * 0.2, 0.55),
			top * CFrame.new(math.cos(a) * 4.0, 0.85, math.sin(a) * 4.0) * CFrame.Angles(math.rad(11), a, math.rad(-8)),
			AMBER, Enum.Material.Neon)
		pulsers[#pulsers + 1] = { part = shard, phase = i * 1.7 } -- pulses by transparency, not brightness
	end

	-- (the vines live on the ARCH itself now -- see the frame detail in buildPortal -- so they bob with it
	-- instead of hanging in mid-air while the portal floats)
	for i = 1, 2 do -- creeper roots crawling across the deck toward the frame
		local x = (i == 1) and -2.7 or 2.9
		for seg = 0, 3 do
			newPart(f, "Root", Vector3.new(0.9, 0.14, 0.2),
				top * CFrame.new(x + seg * 0.3 * (i == 1 and 1 or -1), 0.08, -1.4 - seg * 0.85)
					* CFrame.Angles(0, math.rad(seg * 14), 0),
				VINE, FLAT)
		end
	end
end

local function buildSpaceScenery(f, top, floaters, pulsers)
	local ROCK  = Color3.fromRGB(58, 54, 74)
	local STEEL = Color3.fromRGB(150, 155, 170)

	local crystals = {
		{ -4.2, -1.9, 2.8, Color3.fromRGB(90, 160, 255) },
		{ 4.3, -1.3, 2.2, Color3.fromRGB(120, 200, 255) },
		{ -2.5, 3.9, 1.9, Color3.fromRGB(160, 120, 255) },
		{ 3.6, 3.4, 2.4, Color3.fromRGB(110, 140, 255) },
	}
	for i, c in ipairs(crystals) do -- blue crystals on rock bases: Neon only, no PointLight (see the note
		-- on the portal's own lights -- per-prop lights are what washed the detail out)
		local shard = newPart(f, "Crystal", Vector3.new(0.75, c[3], 0.75),
			top * CFrame.new(c[1], c[3] * 0.5, c[2]) * CFrame.Angles(math.rad(8 * i), math.rad(45 * i), math.rad(-6 * i)),
			c[4], Enum.Material.Neon)
		pulsers[#pulsers + 1] = { part = shard, phase = i * 1.4 }
		newPart(f, "CrystalBase", Vector3.new(1.3, 0.5, 1.3), top * CFrame.new(c[1], 0.2, c[2]), ROCK, STONE)
	end

	-- asteroids: they drift and tumble. local_ is their offset from the platform, so they follow it.
	for i, r in ipairs({ { 4.6, 0, 1.25 }, { -4.6, 1.7, 0.95 }, { 0.9, -4.6, 1.1 } }) do
		local localCF = CFrame.new(r[1], 5.6 + i * 1.25, r[2])
		local rock = ball(f, "Asteroid", r[3], top * localCF, ROCK, STONE)
		floaters[#floaters + 1] = { part = rock, local_ = localCF, phase = i * 2.1, amp = 0.55 + i * 0.15, spin = 0.5 + i * 0.25 }
	end

	for i, d in ipairs({ { 3.9, -3.4, 22 }, { -3.7, 2.9, -37 } }) do -- metallic debris half-buried in the deck
		newPart(f, "Debris", Vector3.new(1.9, 0.3, 0.8),
			top * CFrame.new(d[1], 0.14, d[2]) * CFrame.Angles(0, math.rad(d[3]), math.rad(6 * i)),
			STEEL, FLAT)
		cyl(f, "Strut", 1.5, 0.28, top * CFrame.new(d[1] + 0.3, 0.3, d[2] + 0.5) * CFrame.Angles(0, math.rad(d[3]), math.rad(90)),
			STEEL, FLAT)
	end

	for i = 1, 10 do -- stars hanging in the air
		local a = math.rad(i * 36)
		ball(f, "Star", 0.25,
			top * CFrame.new(math.cos(a) * 4.8, 6.5 + (i % 4) * 1.4, math.sin(a) * 4.8),
			Color3.fromRGB(255, 255, 235), Enum.Material.Neon)
	end
end

local function buildCandyScenery(f, top, floaters, pulsers)
	local RED, WHITE = Color3.fromRGB(226, 58, 78), Color3.fromRGB(255, 255, 255)
	local CHOC = Color3.fromRGB(88, 54, 36)

	for _, side in ipairs({ -1, 1 }) do -- candy canes: striped pole + a properly hooked top
		local x = side * 4.4
		for s = 0, 7 do
			cyl(f, "CanePole", 0.95, 0.72, top * CFrame.new(x, 0.5 + s * 0.95, -2.2) * CFrame.Angles(0, 0, math.rad(90)),
				(s % 2 == 0) and RED or WHITE, Enum.Material.SmoothPlastic)
		end
		for h = 1, 4 do
			local a = math.rad(h * 34)
			cyl(f, "CaneHook", 0.95, 0.72,
				top * CFrame.new(x - side * (1 - math.cos(a)) * 1.25, 8.1 + math.sin(a) * 1.15, -2.2)
					* CFrame.Angles(0, 0, math.rad(90) - a * side),
				(h % 2 == 0) and RED or WHITE, Enum.Material.SmoothPlastic)
		end
	end

	for _, lp in ipairs({ { -3.7, 3.5, Color3.fromRGB(255, 120, 190) }, { 4.0, 3.2, Color3.fromRGB(140, 220, 255) } }) do
		cyl(f, "PopStick", 3.0, 0.28, top * CFrame.new(lp[1], 1.5, lp[2]) * CFrame.Angles(0, 0, math.rad(90)),
			WHITE, Enum.Material.SmoothPlastic)
		-- roll the disc 90 degrees so its flat face points at the player, not at the sky
		cyl(f, "PopHead", 0.38, 2.1, top * CFrame.new(lp[1], 3.6, lp[2]) * CFrame.Angles(0, math.rad(90), 0),
			lp[3], Enum.Material.SmoothPlastic) -- plastic, not neon: a lollipop shouldn't glow like a lamp
	end

	for _, g in ipairs({
		{ 2.6, -4.2, 1.2, Color3.fromRGB(120, 230, 140) },
		{ -2.3, -4.4, 1.05, Color3.fromRGB(255, 210, 90) },
		{ 4.5, 0.9, 1.3, Color3.fromRGB(180, 130, 255) },
		{ -4.6, 0.4, 1.1, Color3.fromRGB(255, 140, 120) },
	}) do -- gumdrops: taller than wide, like the real thing
		local d = ball(f, "Gumdrop", g[3], top * CFrame.new(g[1], g[3] * 0.42, g[2]), g[4], Enum.Material.SmoothPlastic)
		d.Size = Vector3.new(g[3], g[3] * 1.25, g[3])
	end

	for _, c in ipairs({ { -1.6, -4.6, 1.35 }, { 3.3, -2.6, 1.1 } }) do -- chocolate rocks
		ball(f, "ChocRock", c[3], top * CFrame.new(c[1], c[3] * 0.34, c[2]), CHOC, STONE)
	end

	for i = 1, 20 do -- frosting piped around the rim
		local a = (i / 20) * math.pi * 2
		ball(f, "Frosting", 1.05,
			top * CFrame.new(math.cos(a) * (PLATFORM_R - 0.3), 0.12, math.sin(a) * (PLATFORM_R - 0.3)),
			WHITE, Enum.Material.SmoothPlastic)
	end

	local SPRINKLE = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 230, 90),
		Color3.fromRGB(150, 255, 150), Color3.fromRGB(220, 140, 255) }
	for i = 1, 18 do -- sprinkles scattered over the deck
		local a, r = math.rad(i * 53), 1.6 + (i % 4) * 0.85
		newPart(f, "Sprinkle", Vector3.new(0.42, 0.12, 0.12),
			top * CFrame.new(math.cos(a) * r, 0.06, math.sin(a) * r) * CFrame.Angles(0, math.rad(i * 37), 0),
			SPRINKLE[(i % #SPRINKLE) + 1], Enum.Material.SmoothPlastic)
	end
end

--------------------------------------------------------------------------------
-- one portal
--------------------------------------------------------------------------------
local portals = {} -- [realmKey] = portal
local markers = {} -- array of { part =, key =, lastCF = }
local state   = {} -- [realmKey] = { unlocked =, built =, reqText = } -- server-pushed, per player

-- Floating label plates: dark rounded card, white outlined text -- readable against the trees.
--
-- CONSTANT ON-SCREEN SIZE. A BillboardGui's Size is a UDim2: the SCALE half is measured in studs (so it
-- shrinks with distance), the OFFSET half is measured in screen pixels (so it does not). Sizing the plate
-- purely in Offset is what holds it at the same apparent size at any range.
--   * MaxDistance = math.huge -> never fades out across the hub.
--   * AlwaysOnTop = true      -> draws over the trees and the arch, so it's always readable.
-- Do NOT add distance-based resizing here. An earlier version scaled the pixel size BY the camera
-- distance, and that is exactly what made the labels balloon as you walked away.
local function makePlate(adornee, w, h, textSize, font)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(w, h) -- pixels only: no Scale component, no distance scaling
	bb.AlwaysOnTop = true
	-- Fade in only when you're near, the way an NPC's name tag does. Across the island the three headers
	-- were just floating clutter; you only need them once you're close enough to actually walk in.
	bb.MaxDistance = LABEL_RANGE
	bb.LightInfluence = 0            -- keeps its own colours instead of soaking up the portal glow
	bb.Adornee = adornee
	bb.Parent = adornee

	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
	card.BackgroundTransparency = 0.3
	card.BorderSizePixel = 0
	card.Parent = bb
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
	local edge = Instance.new("UIStroke", card)
	edge.Color = Color3.fromRGB(255, 255, 255); edge.Transparency = 0.65; edge.Thickness = 1.5

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -12, 1, -8)
	lbl.Position = UDim2.new(0, 6, 0, 4)
	lbl.BackgroundTransparency = 1
	lbl.Font = font or Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.Parent = card
	local stroke = Instance.new("UIStroke", lbl)
	stroke.Color = Color3.new(0, 0, 0); stroke.Thickness = 2.5
	if textSize then lbl.TextScaled = false; lbl.TextSize = textSize end

	return bb, lbl, card
end

local function buildPortal(key)
	local look = LOOKS[key]
	local p = {
		key = key, look = look,
		ring = {}, frame = {}, runes = {}, swirls = {}, depth = {}, floaters = {}, pulsers = {},
		unlocked = false, sending = false, pulse = nil,
		phase = (key == "space" and 0) or (key == "dino" and 2.1) or 4.2, -- so they don't bob in lockstep
	}

	local root = Instance.new("Folder"); root.Name = "RealmPortal_" .. key; root.Parent = Workspace
	p.root = root
	local static = Instance.new("Folder"); static.Name = "Static"; static.Parent = root -- never bobs
	local moving = Instance.new("Folder"); moving.Name = "Moving"; moving.Parent = root -- bobs
	p.static, p.moving = static, moving

	-- ---- circular platform: base slab, a coloured rim, and a glowing inlay disc ----
	p.platform = cyl(static, "Platform", PLATFORM_H, PLATFORM_R * 2, CFrame.new(), Color3.fromRGB(132, 128, 122), STONE)
	p.rim      = cyl(static, "Rim", PLATFORM_H * 0.5, PLATFORM_R * 2 + 1.0, CFrame.new(), look.plate, STONE)
	p.inlay    = cyl(static, "Inlay", PLATFORM_H * 0.62, PLATFORM_R * 1.0, CFrame.new(), look.lightA, Enum.Material.Neon)
	p.inlay.Transparency = 0.72 -- a hint of colour in the floor, not a floodlight

	-- ---- the arch: chunky beveled blocks around an ellipse ----
	-- Each stone is TWO flat parts: a darker bevel sitting slightly proud behind a lighter face. That
	-- clean shadow line along every edge is the whole "low-poly premium" trick -- no cracks, no grit, no
	-- texture. Big simple blocks, few of them, read from a distance.
	local rx, ry = PORTAL_W / 2, PORTAL_H / 2
	local perim  = math.pi * (3 * (rx + ry) - math.sqrt((3 * rx + ry) * (rx + 3 * ry))) -- Ramanujan
	local segLen = (perim / RING_SEGS) * 1.34 -- overlap slightly: no gaps on the curve
	for i = 1, RING_SEGS do
		local a = (i / RING_SEGS) * math.pi * 2
		local tangent = math.atan2(rx * math.sin(a), ry * math.cos(a)) -- lie along the ellipse, not a circle
		local base = CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 0) * CFrame.Angles(0, 0, -tangent)

		local bevel = newPart(moving, "Bevel", Vector3.new(segLen * 1.06, 2.0, 2.4), CFrame.new(), look.bevel, STONE)
		p.ring[#p.ring + 1] = { part = bevel, localCF = base, bevel = true }

		local face = newPart(moving, "Stone", Vector3.new(segLen, 1.6, 2.0), CFrame.new(), look.stone, STONE)
		p.ring[#p.ring + 1] = { part = face, localCF = base * CFrame.new(0, 0, 0.34), bevel = false }

		if i % RUNE_EVERY == 0 then -- glowing accents set into the stone -- these pulse
			local rune = newPart(moving, "Rune", Vector3.new(0.8, 0.8, 0.14), CFrame.new(), look.rune, GLOW)
			p.ring[#p.ring + 1] = { part = rune, localCF = base * CFrame.new(0, 0, 1.36), bevel = false }
			p.runes[#p.runes + 1] = rune
		end
	end

	-- ---- what makes each FRAME its own object, not a recolour of the same ring ----
	-- These hang off the arch itself (localCF is relative to the portal centre), so they float with it.
	-- A frame prop keeps its own colour/material; render() greys them out when the portal is locked.
	local function frameProp(part, localCF)
		p.frame[#p.frame + 1] = { part = part, localCF = localCF, color = part.Color, material = part.Material }
	end

	if key == "space" then
		-- BIG chunky crystals embedded around the frame -- few, large, unmistakable. Plus sci-fi accent
		-- bars. Nothing dark, nothing metallic: the frame is purple stone and glowing candy-bright gems.
		local GEM = { Color3.fromRGB(120, 170, 255), Color3.fromRGB(175, 125, 255), Color3.fromRGB(140, 220, 255) }
		for i = 1, 6 do
			local a = math.rad(28 + i * 58)
			local gem = newPart(moving, "Crystal", Vector3.new(1.05, 2.3 + (i % 3) * 0.5, 1.05), CFrame.new(),
				GEM[(i % #GEM) + 1], GLOW)
			frameProp(gem, CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 1.15) * CFrame.Angles(0, 0, a + math.pi / 2))
			p.pulsers[#p.pulsers + 1] = { part = gem, phase = i * 1.3 }
		end
		for i = 1, 4 do -- glowing accent bars: the sci-fi read, without a single rivet
			local a = math.rad(i * 90 + 45)
			frameProp(newPart(moving, "Accent", Vector3.new(1.9, 0.3, 0.16), CFrame.new(), look.rune, GLOW),
				CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 1.38) * CFrame.Angles(0, 0, a + math.pi / 2))
		end
		local cap = newPart(moving, "Keystone", Vector3.new(2.6, 1.5, 2.6), CFrame.new(), look.bevel, STONE)
		frameProp(cap, CFrame.new(0, ry + 0.75, 0.4))
		local capGem = newPart(moving, "KeystoneGem", Vector3.new(1.2, 1.2, 1.2), CFrame.new(), look.rune, GLOW)
		frameProp(capGem, CFrame.new(0, ry + 0.9, 1.5))
		p.pulsers[#p.pulsers + 1] = { part = capGem, phase = 0.4 }

	elseif key == "dino" then
		local BONE = Color3.fromRGB(240, 236, 220)
		local LEAF = Color3.fromRGB(86, 176, 70)
		-- simple bones laid across the frame -- a shaft with two round ends, the classic cartoon bone
		for i = 1, 4 do
			local a = math.rad(35 + i * 78)
			local at = CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 1.2) * CFrame.Angles(0, 0, a + math.pi / 2)
			frameProp(cyl(moving, "Bone", 2.4, 0.5, CFrame.new(), BONE, FLAT), at * CFrame.Angles(0, 0, math.rad(90)))
			for e = -1, 1, 2 do
				frameProp(ball(moving, "BoneEnd", 0.85, CFrame.new(), BONE, FLAT), at * CFrame.new(0, e * 1.2, 0))
			end
		end
		local skull = newPart(moving, "Skull", Vector3.new(2.4, 1.9, 1.9), CFrame.new(), BONE, FLAT) -- chunky, friendly
		frameProp(skull, CFrame.new(0, ry + 0.7, 0.9))
		frameProp(newPart(moving, "Snout", Vector3.new(1.4, 0.9, 1.2), CFrame.new(), BONE, FLAT),
			CFrame.new(0, ry + 0.35, 1.9))
		for i = 1, 3 do -- small green crystals
			local a = math.rad(200 + i * 50)
			local gem = newPart(moving, "GreenCrystal", Vector3.new(0.6, 1.3, 0.6), CFrame.new(), look.rune, GLOW)
			frameProp(gem, CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 1.25) * CFrame.Angles(0, 0, a + math.pi / 2))
			p.pulsers[#p.pulsers + 1] = { part = gem, phase = i * 1.9 }
		end
		for i = 1, 5 do -- vines spilling over the arch, with a leaf on the end of each
			local x = (i - 3) * 1.6
			for seg = 0, 2 do
				frameProp(newPart(moving, "Vine", Vector3.new(0.26, 1.0, 0.26), CFrame.new(), LEAF, FLAT),
					CFrame.new(x, ry - 0.2 - seg * 0.95, 1.2))
			end
			frameProp(newPart(moving, "Leaf", Vector3.new(0.9, 0.22, 0.55), CFrame.new(), LEAF, FLAT),
				CFrame.new(x + 0.35, ry - 3.0, 1.2) * CFrame.Angles(0, 0, math.rad(22)))
		end

	elseif key == "candy" then
		local WHITE = Color3.fromRGB(255, 255, 255)
		local CANDY = { Color3.fromRGB(255, 105, 135), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 225, 100),
			Color3.fromRGB(150, 245, 160), Color3.fromRGB(200, 150, 255) }

		for i = 0, 9 do -- frosting spread over the top of the arch, with fat rounded drips
			local a = math.rad(18 + i * 16)
			local drip = 0.6 + ((i % 3) * 0.6)
			frameProp(newPart(moving, "Frosting", Vector3.new(1.7, 1.1 + drip, 1.1), CFrame.new(), WHITE, FLAT),
				CFrame.new(math.cos(a) * rx, math.sin(a) * ry - drip * 0.35, 1.05))
			frameProp(ball(moving, "Drip", 0.9, CFrame.new(), WHITE, FLAT),
				CFrame.new(math.cos(a) * rx, math.sin(a) * ry - drip - 0.35, 1.05))
		end
		for i = 1, 8 do -- gumdrops pressed into the stones
			local a = math.rad(i * 45 + 20)
			local g = ball(moving, "FrameGumdrop", 1.1, CFrame.new(), CANDY[(i % #CANDY) + 1], FLAT)
			g.Size = Vector3.new(1.1, 1.35, 1.1)
			frameProp(g, CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 1.35))
		end
		for _, side in ipairs({ -1, 1 }) do -- a lollipop built into each shoulder of the frame
			local at = CFrame.new(side * (rx - 0.2), ry * 0.55, 1.3)
			frameProp(cyl(moving, "FramePopStick", 1.6, 0.28, CFrame.new(), WHITE, FLAT),
				at * CFrame.new(0, -1.3, 0) * CFrame.Angles(0, 0, math.rad(90)))
			local head = cyl(moving, "FramePopHead", 0.4, 2.0, CFrame.new(), CANDY[(side == 1) and 1 or 3], FLAT)
			frameProp(head, at * CFrame.Angles(0, math.rad(90), 0))
		end
		for i = 1, 14 do -- sprinkles
			local a = math.rad(i * 26)
			frameProp(newPart(moving, "Sprinkle", Vector3.new(0.45, 0.14, 0.14), CFrame.new(),
				CANDY[(i % #CANDY) + 1], FLAT),
				CFrame.new(math.cos(a) * (rx - 0.35), math.sin(a) * (ry - 0.35), 1.42) * CFrame.Angles(0, 0, math.rad(i * 41)))
		end
	end

	-- ---- the interior: layered discs receding into the distance, so the door has DEPTH ----
	-- Each layer sits further back, smaller and dimmer -- a tunnel, not a flat pane. They counter-rotate.
	for i = 1, 4 do
		local scale = 1 - i * 0.16
		local disc = newPart(moving, "Depth" .. i,
			Vector3.new(0.4, PORTAL_H * scale, PORTAL_W * scale), CFrame.new(),
			look.vortex, Enum.Material.Neon, 0.35 + i * 0.1)
		disc.Shape = Enum.PartType.Cylinder
		p.depth[i] = {
			part = disc,
			localCF = CFrame.new(0, 0, -0.9 * i) * CFrame.Angles(0, math.rad(90), 0),
			speed = (i % 2 == 0) and (0.5 + i * 0.2) or -(0.4 + i * 0.25), -- alternate direction: it churns
			angle = 0,
		}
	end

	-- ---- THE FORCE FIELD: fills the opening. Touching it starts the transfer. ----
	-- A Cylinder's axis is its X, so roll it 90 degrees to aim that axis down the facing. That leaves
	-- Size.Y as the opening's height and Size.Z as its width -- an oval door, not a circle.
	p.vortex = newPart(moving, "ForceField", Vector3.new(0.6, PORTAL_H, PORTAL_W), CFrame.new(),
		look.vortex, Enum.Material.ForceField, 0.2)
	p.vortex.Shape = Enum.PartType.Cylinder
	p.vortex.CanTouch = true -- the one piece in the whole build you can touch
	p.vortexLocal = CFrame.Angles(0, math.rad(90), 0)

	-- TWO lights per portal, and that is the WHOLE lighting budget for it. The previous build also hung a
	-- PointLight on every crystal and lollipop -- six per portal, eighteen across the row -- and Roblox
	-- blows out well before that: the bloom swallowed the stonework, the runes and the cracks. Props now
	-- glow by being Neon, not by casting light, and these two are dialled well down.
	local d = look.dim or 1 -- the realm's own trim, on top of the master levels
	local lightA = Instance.new("PointLight")
	lightA.Color = look.lightA; lightA.Brightness = LIGHT_A * d; lightA.Range = 20; lightA.Parent = p.vortex
	local lightB = Instance.new("PointLight")
	lightB.Color = look.lightB; lightB.Brightness = LIGHT_B * d; lightB.Range = 15; lightB.Parent = p.vortex
	p.lightA, p.lightB = lightA, lightB

	local sparks = Instance.new("ParticleEmitter") -- motes pulled INTO the door (negative speed)
	sparks.Color = ColorSequence.new(look.spark)
	sparks.Size = NumberSequence.new(look.sparkSize)
	sparks.Lifetime = NumberRange.new(0.8, 1.6)
	sparks.Rate = look.sparkRate * 0.6
	sparks.Speed = NumberRange.new(-4, -1)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.LightEmission = 0.55 -- was 1: full emission is a bloom machine
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.25), NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Parent = p.vortex
	p.sparks = sparks

	for i = 1, 2 do -- swirl bars across the surface
		local arc = newPart(moving, "Swirl" .. i, Vector3.new(PORTAL_W * (i == 1 and 0.78 or 0.52), 0.5, 0.22),
			CFrame.new(), look.rune, Enum.Material.Neon, 0.4)
		p.swirls[i] = { part = arc, speed = (i == 1 and 1 or -1.7), angle = 0 }
	end

	-- ---- ambient glow rising off the platform ----
	p.anchor = newPart(static, "Anchor", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), look.lightA, Enum.Material.Neon, 1)
	local ambient = Instance.new("ParticleEmitter") -- a slow drift of motes off the platform, kept subtle
	ambient.Color = ColorSequence.new(look.lightB)
	ambient.Size = NumberSequence.new(0.6)
	ambient.Lifetime = NumberRange.new(1.8, 3.2)
	ambient.Rate = 7
	ambient.Speed = NumberRange.new(1.4, 2.6)
	ambient.SpreadAngle = Vector2.new(30, 30)
	ambient.LightEmission = 0.4
	ambient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1),
	})
	ambient.Parent = p.anchor
	p.ambient = ambient

	-- ---- labels: ONE header per portal, a lock badge above it, a requirement line beneath ----
	-- All hang off this portal's own anchor, so they can never drift onto a neighbour. The headers get
	-- pinned to a shared world height in alignHeaders(); their Y offsets are set there, not here.
	local nameBB, nameLbl = makePlate(p.anchor, 280, 72)
	nameLbl.Text = look.emoji .. " " .. look.title
	p.nameBB, p.nameLbl = nameBB, nameLbl

	local lockBB, lockLbl, lockCard = makePlate(p.anchor, 66, 66)
	lockLbl.Text = "\xF0\x9F\x94\x92" -- 🔒
	lockCard.BackgroundTransparency = 0.25
	p.lockBB, p.lockLbl = lockBB, lockLbl

	local reqBB, reqLbl = makePlate(p.anchor, 232, 30, nil, Enum.Font.GothamBold)
	reqLbl.TextColor3 = Color3.fromRGB(255, 214, 140)
	reqBB.StudsOffsetWorldSpace = Vector3.new(0, PLATFORM_H - 1.8, 0) -- beneath the portal
	p.reqBB, p.reqLbl = reqBB, reqLbl

	-- ---- touch -> INTENT ONLY. The server owns the gate and the teleport. ----
	function p.enter()
		if p.sending then return end
		p.sending = true
		task.delay(2.5, function() p.sending = false end) -- local debounce; the server has its own
		pcall(function() enterEvent:FireServer(key) end)
	end
	p.vortex.Touched:Connect(function(hit)
		local char = player.Character
		if not (char and hit and hit:IsDescendantOf(char)) then return end -- only our own body
		p.enter()
	end)

	portals[key] = p
	return p
end

--------------------------------------------------------------------------------
-- seating a portal on ITS OWN marker (positions are yours; we never move them)
--------------------------------------------------------------------------------
local function seat(p, marker, rot)
	-- the portal stands on the ground the brick sits on: the BOTTOM of the marker
	local platBaseY = marker.Position.Y - marker.Size.Y * 0.5
	local pos       = marker.Position
	local centreY   = platBaseY + PLATFORM_H + PORTAL_H / 2

	p.baseCF    = CFrame.new(Vector3.new(pos.X, centreY, pos.Z)) * rot -- portal centre
	p.platBaseY = platBaseY
	p.topWorldY = platBaseY + PLATFORM_H + PORTAL_H -- top of the arch: used to align the headers

	local platCF = CFrame.new(pos.X, platBaseY + PLATFORM_H * 0.5, pos.Z) * rot
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- cylinders lie on their X; stand them up
	p.platform.CFrame = platCF * upright
	p.rim.CFrame      = platCF * CFrame.new(0, -0.28, 0) * upright
	p.inlay.CFrame    = platCF * CFrame.new(0, PLATFORM_H * 0.45, 0) * upright
	p.anchor.CFrame   = CFrame.new(pos.X, platBaseY, pos.Z)

	local top = platCF * CFrame.new(0, PLATFORM_H * 0.5, 0) -- the walkable surface

	if not p.sceneryBuilt then
		p.sceneryBuilt = true
		if p.key == "dino"  then buildDinoScenery(p.static, top, p.floaters, p.pulsers) end
		if p.key == "space" then buildSpaceScenery(p.static, top, p.floaters, p.pulsers) end
		if p.key == "candy" then buildCandyScenery(p.static, top, p.floaters, p.pulsers) end
	elseif p.topCF then
		-- reseated (the island moved): carry the scenery across by the same delta rather than rebuild it
		local delta = top * p.topCF:Inverse()
		for _, d in ipairs(p.static:GetChildren()) do
			if d:IsA("BasePart") and d ~= p.platform and d ~= p.rim and d ~= p.inlay and d ~= p.anchor then
				d.CFrame = delta * d.CFrame
			end
		end
	end
	p.topCF = top
end

-- The moving half, re-placed each frame with the idle bob folded in.
local function place(p, bob)
	local face = p.baseCF * CFrame.new(0, bob, 0)
	p.face = face
	for _, e in ipairs(p.ring) do
		e.part.CFrame = face * e.localCF
	end
	for _, e in ipairs(p.frame) do -- the realm-specific frame detail rides with the arch
		e.part.CFrame = face * e.localCF
	end
	for _, d in ipairs(p.depth) do
		d.part.CFrame = face * CFrame.Angles(0, 0, d.angle) * d.localCF
	end
	p.vortex.CFrame = face * p.vortexLocal
	for _, s in ipairs(p.swirls) do
		s.part.CFrame = face * CFrame.Angles(0, 0, s.angle) * CFrame.new(0, 0, -0.4)
	end
end

-- ONE header height for the whole row: pin every name plate to the tallest portal's top, so the three
-- read as a level row even if the bricks aren't at identical heights.
local function alignHeaders()
	local top = -math.huge
	for _, p in pairs(portals) do
		if p.topWorldY then top = math.max(top, p.topWorldY) end
	end
	if top == -math.huge then return end

	-- One shared world height for every header -> the row reads dead level, whatever height the bricks
	-- happen to sit at. The lock badge rides just above its own header.
	for _, p in pairs(portals) do
		if p.anchor then
			local anchorY = p.anchor.Position.Y
			p.nameBB.StudsOffsetWorldSpace = Vector3.new(0, top + 3.4 - anchorY, 0)
			p.lockBB.StudsOffsetWorldSpace = Vector3.new(0, top + 7.2 - anchorY, 0)
		end
	end
end

--------------------------------------------------------------------------------
-- LAYOUT: each portal on its own marker. Positions never change; we only follow them.
--------------------------------------------------------------------------------
local function relayout()
	if #markers == 0 then return end

	-- one shared rotation for the row (from the first marker + the yaw fix), so the three are parallel
	local m1 = markers[1].part
	local rot = (m1.CFrame - m1.CFrame.Position) * CFrame.Angles(0, math.rad(PORTAL_YAW), 0)

	for _, m in ipairs(markers) do
		local p = portals[m.key] or buildPortal(m.key)
		seat(p, m.part, rot)
		place(p, 0)
	end
	alignHeaders()
end

--------------------------------------------------------------------------------
-- lock state (server-pushed, per player)
--------------------------------------------------------------------------------
local function render(p)
	local st, look = state[p.key] or {}, p.look
	local soon = (st.built == false)                  -- Candy: the place isn't built yet
	local open = (st.unlocked == true) and not soon
	p.unlocked = open

	-- EVERY PORTAL IS ALWAYS A PORTAL. It keeps its realm colours, its themed stone and frame, and the
	-- swirling stuff in the middle you walk through -- open, locked or coming-soon alike. Locked used to
	-- strip all that out and leave a dead grey ring, which is what drained the colour out of Dino and left
	-- nothing in its middle. Now "locked" only means: the sign is up, and it's a shade dimmer. The SERVER
	-- is what actually refuses to travel you -- the look never lies about which realm this is.
	for _, e in ipairs(p.ring) do
		e.part.Color    = e.bevel and look.bevel or look.stone
		e.part.Material = look.stoneMat
	end
	for _, e in ipairs(p.frame) do -- bones, crystals, frosting: always their own colours
		e.part.Color    = e.color
		e.part.Material = e.material
	end
	for _, rune in ipairs(p.runes) do
		rune.Color = look.rune
		rune.Material = GLOW
	end
	for _, s in ipairs(p.swirls) do s.part.Transparency = 0.4 end
	for i, d in ipairs(p.depth) do -- the tunnel of depth behind the door
		d.part.Color = look.vortex
		d.part.Transparency = 0.35 + i * 0.1
	end

	p.nameLbl.TextColor3 = look.lightA
	p.inlay.Color        = look.lightA

	-- k: not yet yours -> still lit, still swirling, just quieter than a door you can walk through.
	-- d: the realm's own brightness trim (Candy 0.7 -- its white light blows out at the shared level).
	local k = open and 1 or 0.65
	local d = look.dim or 1
	p.vortex.Color = look.vortex
	p.vortex.Transparency = open and 0.28 or 0.4
	p.lightA.Brightness = LIGHT_A * k * d; p.lightA.Color = look.lightA
	p.lightB.Brightness = LIGHT_B * k * d; p.lightB.Color = look.lightB
	p.sparks.Color = ColorSequence.new(look.spark); p.sparks.Rate = look.sparkRate * 0.6 * k
	p.ambient.Rate = 7 * k * d

	if open then
		p.lockBB.Enabled = false -- no lock badge...
		p.reqBB.Enabled  = false -- ...and the requirement line goes once it's earned
		if not p.pulse then -- an open door breathes, gently -- and the breath is trimmed per realm too
			p.pulse = TweenService:Create(p.lightA,
				TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Brightness = LIGHT_PULSE * d })
			p.pulse:Play()
		end
	else
		-- LOCKED (and "coming soon" Candy): the same 🔒 badge overhead on both, no strapline. The server
		-- sends the centre-screen "not unlocked" message if you actually walk in.
		if p.pulse then p.pulse:Cancel(); p.pulse = nil end
		p.lockBB.Enabled = true
		p.reqBB.Enabled  = false
		p.lockLbl.Text = "\xF0\x9F\x94\x92" -- 🔒
	end
end

--------------------------------------------------------------------------------
-- per-frame: follow the markers, bob, spin, pulse
--------------------------------------------------------------------------------
local t = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt

	-- Did a marker move? PlayerStats repositions Island 1 shortly after we build, and the markers ride
	-- with it. Re-derive from the markers rather than trusting a one-time placement.
	local dirty = false
	for _, m in ipairs(markers) do
		if m.part.Parent and m.part.CFrame ~= m.lastCF then
			m.lastCF = m.part.CFrame
			dirty = true
		end
	end
	if dirty then relayout() end

	for _, p in pairs(portals) do
		if p.baseCF then
			-- Every portal churns, locked or not -- a portal you can't use yet is still a portal. An open
			-- one just turns a little faster, so it reads as the livelier of the two.
			local rate = p.unlocked and 1 or 0.6
			for _, s in ipairs(p.swirls) do s.angle += dt * p.look.spin * s.speed * rate end
			for _, d in ipairs(p.depth) do d.angle += dt * d.speed * 0.5 * rate end

			place(p, math.sin(t * BOB_SPEED + p.phase) * BOB_AMP) -- the idle float

			for _, rune in ipairs(p.runes) do -- runes breathe, slightly out of phase with the bob
				rune.Transparency = p.unlocked and (0.15 + 0.25 * (0.5 + 0.5 * math.sin(t * 2.2 + p.phase))) or 0.6
			end

			for _, pl in ipairs(p.pulsers) do -- crystals breathing: transparency, not light brightness
				pl.part.Transparency = 0.05 + 0.28 * (0.5 + 0.5 * math.sin(t * 1.6 + pl.phase))
			end

			for _, fl in ipairs(p.floaters) do -- Space Realm's asteroids
				fl.part.CFrame = p.topCF * fl.local_
					* CFrame.new(0, math.sin(t * 0.7 + fl.phase) * fl.amp, 0)
					* CFrame.Angles(t * fl.spin * 0.35, t * fl.spin * 0.5, 0)
			end
		end
	end

end)

--------------------------------------------------------------------------------
-- find the marker blocks (they can stream in late -- watch forever, never a one-shot sweep)
--------------------------------------------------------------------------------
local function adopt(part, key)
	for _, m in ipairs(markers) do
		if m.part == part then return end -- already ours
	end

	-- THE MARKER: invisible and inert. It only says where this portal goes and which way it faces.
	part.Transparency = 1
	part.CanCollide   = false
	part.CanTouch     = false -- the force field is what starts a transfer
	part.CastShadow   = false

	-- The big realm name floating INSIDE the portal is not ours -- it's the stale duplicate script,
	-- which adorns its sign straight onto the marker brick. Ours all hang off p.anchor instead. Strip
	-- anything else that tries to label this brick, and keep stripping it, so the only text you see is
	-- the one header above the portal. (Deleting that old script is still the real fix.)
	local function scrubForeignLabels()
		for _, c in ipairs(part:GetChildren()) do
			if c:IsA("BillboardGui") or c:IsA("SurfaceGui") then c:Destroy() end
		end
	end
	scrubForeignLabels()
	part.ChildAdded:Connect(function(c)
		if c:IsA("BillboardGui") or c:IsA("SurfaceGui") then c:Destroy() end
	end)

	markers[#markers + 1] = { part = part, key = key, lastCF = part.CFrame }
	relayout()
	if portals[key] then render(portals[key]) end
	print("[RealmPortals] built the " .. LOOKS[key].title .. " portal on its marker")
end

local function consider(inst)
	if not (inst:IsA("BasePart") and inst.Name == "Portal") then return end
	local function try()
		local key = inst:GetAttribute("Realm")
		if type(key) == "string" and LOOKS[key] then adopt(inst, key) end
	end
	try() -- the attribute may already be there...
	inst:GetAttributeChangedSignal("Realm"):Connect(try) -- ...or the server writes it a moment later
end

for _, d in ipairs(Workspace:GetDescendants()) do consider(d) end
Workspace.DescendantAdded:Connect(consider)

--------------------------------------------------------------------------------
-- what the server tells us
--------------------------------------------------------------------------------
enterEvent.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "state" then -- a: { [realmKey] = { unlocked, built, reqText } }
		if type(a) ~= "table" then return end
		for key, st in pairs(a) do state[key] = st end
		for _, p in pairs(portals) do render(p) end -- lights up the moment the server says it's earned
		return
	end

	if kind ~= "status" then return end
	local key, status, reqText = a, b, c
	local look = LOOKS[key]
	if not look then return end

	if status == "traveling" then
		showMsg(look.emoji .. "  Traveling to the " .. look.name .. "...", look.lightA)
		-- FAILSAFE: if the teleport never lands (Studio, or a TeleportAsync error), don't strand the box.
		task.delay(6, function() msgLbl.Visible = false; msgLbl.BackgroundTransparency = 1 end)
	elseif status == "locked" then
		showMsg("\xF0\x9F\x94\x92  You haven't unlocked the " .. look.name .. " yet!",
			Color3.fromRGB(255, 190, 90), 3.5)
	elseif status == "soon" then
		showMsg("\xF0\x9F\x9A\xA7  " .. look.name .. " \xE2\x80\x94 Coming soon!", look.lightA, 3)
	elseif status == "error" then
		showMsg("Couldn't travel right now, try again", Color3.fromRGB(255, 120, 120), 3)
	end
end)

print("[RealmPortals] client ready -- hub build, watching for Portal marker blocks")
