--======================================================================
-- AncientTreeQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- "THE FORGOTTEN PARK" -- Island 13 (Burrito Barrens).
--
-- >>> ALL THREE STEPS ARE LIVE. Set FOUNTAIN_ONLY = true to cut back to just the fountain
-- >>> (handy for tweaking its look). FOUNTAIN_RADIUS sets how big the fountain is.
-- >>>
-- >>> 'garden1..3' and 'ancienttree' are treated as REAL ART: the quest records every part's
-- >>> original colour AND SIZE, wilts them (planting is also shrunk right down), then restores
-- >>> those exact values as you fix the park. Nothing is ever built on top of your models --
-- >>> only the fountain and the three gates are constructed.
-- >>>
-- >>> THERE ARE NO VISIBLE CHANNELS. The irrigation is underground, so the park above ground
-- >>> stays clean; the water only appears again inside the gardens.
--
--   STEP 1  Restore the Fountain   -- the fountain is bone dry. Turn the valve and the water
--                                     comes back, which brings the buried mains live.
--   STEP 2  Redirect the Water     -- three gates are seized shut. Take each crank and heave
--                                     it round; water runs underground to that garden, then
--                                     SURFACES INSIDE THE PLANTING and spreads across it,
--                                     growing the flowers as the wave reaches them.
--   STEP 3  Awaken the Ancient Tree -- fires by itself once all three gardens are back.
--
-- WHAT THE WORLD PROVIDES -- rename PARTS to these. Matching ignores case, spaces, underscores
-- and hyphens.
--
--   fountain      REQUIRED. A position marker; the fountain is built on it and it's hidden.
--                 FOUNTAIN_RADIUS below sets the size -- the part's own size is ignored.
--   gate          THREE parts, all named exactly "gate". Each marks where one gate stands and
--                 is paired with whichever garden it is nearest. Hidden once its gate is built.
--   garden1..3    Your real garden models. Never hidden, never built over -- only recoloured
--                 and regrown. A bare partless marker falls back to a procedural bed.
--   ancienttree   Your real tree model. Parts named "ball" are its orbs.
--   offering      Where the GROVE KEEPER stands -- the person you hand the harvest to. The
--                 part is a placement block only and is hidden. Without it the Keeper falls
--                 back to the tree's roots.
--   Candy Npc     The quest giver, matched within 600 studs of the fountain. Optional: with no
--                 NPC the fountain valve simply opens by itself.
--
-- Everything is client-side and per-player, like the island's other quests.
--======================================================================

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace        = game:GetService("Workspace")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local Debris           = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local SoundService     = game:GetService("SoundService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- SYNC CHECK: if you DON'T see this line in Output when you play, Rojo isn't syncing this file.
print("[Park] >>> VERSION harvest-v1 loaded <<<")

-- ============================================================================
-- CONFIG
-- ============================================================================
-- The park lives on Burrito Barrens. Matched as a NORMALISED PREFIX, so "island13",
-- "Island_13", "Island 13" and "Island_13_BurritoBarrens" all hit -- and "island1" doesn't.
local ISLAND_PREFIX  = "island13"
local FOUNTAIN_NAME  = "fountain"
local GARDEN_NAMES   = { "garden1", "garden2", "garden3" }
-- All three gate parts are simply named "gate", so they're gathered as a LIST and then each
-- one is paired with whichever garden it stands closest to.
local GATE_NAME      = "gate"
-- Parts inside a garden carrying this in their name are CROP SPOTS: a plant is built standing
-- on each one and the marker itself is hidden. Matched LOOSELY, so "BubbleCrop", "BubbleCrop2"
-- and "bubble crop 3" all count. If a garden has none, "crop" on its own is tried as a fallback.
local CROP_NAME      = "bubblecrop"
local CROP_FALLBACK  = "crop"
-- name a part this and the Grove Keeper stands on it; the part itself is hidden
local OFFER_NAME     = "offering"
local CROP_SPACING   = 3.0      -- studs between plants along a marker; shorter = denser rows
local SOIL_SIDE_STEP = 1.8      -- studs between soil blocks along a bed's sides; lower = denser
local CROP_SCALE     = 1.45     -- overall crop size. One knob: raise for chunkier plants.
local CROP_MAX       = 220      -- PLANTS per garden, so a stray naming sweep can't explode

-- HARVEST. Once a garden is watered some of its crops ripen; you pick those and carry them to
-- the Ancient Tree. It only wakes once it has produce from all three gardens.
local RIPE_PER_GARDEN  = 8      -- how many crops ripen (a couple more than the quota, so you choose)
local OFFER_PER_GARDEN = 5      -- how many each garden owes the tree
local CARRY_MAX        = 3      -- armful size -- 5 per garden at 3 a trip means two trips
local TREE_NAME      = "ancienttree"     -- reserved for step 3

-- FOUNTAIN ONLY. Nothing but the fountain is built while this is true -- no irrigation ring,
-- no channels, no gate cranks, no garden beds. Flip to false to bring steps 2-3 back.
local FOUNTAIN_ONLY  = false

-- THE FOUNTAIN'S SIZE, in studs, as the radius of its basin. The whole model scales off this
-- one number: 5 is a small park fountain roughly two players wide and a bit over head height.
-- The marker part is only used for POSITION -- a 4x1x2 brick can't imply a sensible basin.
-- Set to 0 to go back to reading the width off the marker's footprint instead.
local FOUNTAIN_RADIUS = 5

-- THE BURST MAINS. Restoring the fountain used to be a single 1.4-second hold; these turn it
-- into a job. PIPE_COUNT pits are dug around the basin, each needing PIPE_TURNS pulls on its
-- wrench at PIPE_HOLD seconds a pull -- roughly 20 seconds of work, plus the walk between
-- them, before the valve is worth touching. Drop PIPE_COUNT to 0 to skip the step entirely.
local PIPE_COUNT     = 4
local PIPE_TURNS     = 4
local PIPE_HOLD      = 0.3   -- hold on the prompt; the work itself is the wrench HUD

-- Trim for the three irrigation gates. Applied to the ONE frame the whole gate is built
-- against, so the posts, sluice, handwheel, chute and the water that runs out of it all move
-- together -- nudging the parts individually is what leaves a gate with its water beside it.
local GATE_YAW       = 15    -- degrees counterclockwise, seen from above
local GATE_DROP      = -2    -- studs down
local GATE_FWD       = -2    -- studs along the way it faces (negative pushes it back)

local RING_GAP       = 9        -- studs between the basin's edge and the irrigation ring
local RING_SEGMENTS  = 28       -- arc pieces in the ring (more = rounder, heavier)
local GARDEN_DIST    = 78       -- how far out auto-placed gardens sit from the fountain
local GARDEN_SIZE    = 34       -- default plot width when there's no marker to read
local CHANNEL_W      = 4.4      -- width of the (buried) conduit, still used to size the gates
local FILL_SPEED     = 26       -- studs/sec the water travels underground from gate to garden

-- The water arrives INSIDE each garden and spreads across it. Plants grow as the wave
-- reaches them, so the flooding and the growing are the same animation.
-- The water leaves the gate and spreads out as a wavefront, stands a while, then drains away
-- in the order it arrived. Deliberately unhurried: this is the payoff for the gate puzzle, so
-- it is meant to be watched rather than got through.
local FLOOD_TIME     = 11.0     -- the water spreading from the gate to the furthest corner
local HOLD_TIME      = 4.5      -- how long it stands full
local SOAK_TIME      = 7.0      -- draining away, bed settling back to its natural dirt
local FLOOD_GRID     = 8        -- fallback grid, only for a plot with no "water" part of its own
local PLANT_MAX      = 12       -- parts bigger than this are scenery, not planting
local PLANT_SHRINK   = 0.12     -- how small a plant is shrunk to while the garden is dead

local CRANK_TURNS    = 3        -- full revolutions to free a gate
local CRANK_SPEED    = 330      -- degrees/sec while you're heaving on it
local CRANK_DECAY    = 150      -- degrees/sec it slips back when you let go
local SEIZE_POINTS   = { 0.38, 0.76 }   -- fractions where it jams and you must re-grip
local CRANK_RANGE    = 16       -- how close you must be to take a crank

local COIN_REWARD    = 2500     -- paid on step 3. Say the word and I'll change it.

-- Audio: drop in your OWN asset ids. "" = silent, and nothing is created for an empty id --
-- given how many ids in this place fail auth, silence is the safe default.
local SOUND_VALVE    = ""       -- the fountain valve creaking open
local SOUND_WATER    = ""       -- LOOPING water burble from the fountain once it runs
local SOUND_RUSH     = ""       -- water surging down a channel
local SOUND_CLUNK    = ""       -- a gate finally giving way
local SOUND_BLOOM    = ""       -- the garden coming to life
local WATER_VOLUME   = 0.4
local WATER_RANGE    = 120      -- studs you can hear the fountain from

-- palette
-- PALETTE. Folded into ONE table on purpose: Luau caps a function at 200 local
-- registers and the main chunk of this file was sitting right on the limit, which
-- stopped the whole script compiling. Forty colours as forty locals cost forty
-- registers; as one table they cost one.
local PAL = {
	STONE         = Color3.fromRGB(178, 172, 158),
	STONE_D       = Color3.fromRGB(126, 120, 108),
	STONE_W       = Color3.fromRGB(206, 201, 188),
	MOSS          = Color3.fromRGB(96, 118, 72),
	DUST          = Color3.fromRGB(154, 140, 116),
	WATER         = Color3.fromRGB(92, 182, 228),
	WATER_D       = Color3.fromRGB(46, 124, 186),
	WATER_L       = Color3.fromRGB(152, 234, 255),   -- bright crystal-clear water
	WATER_G       = Color3.fromRGB(212, 248, 255),   -- foam / glow / crests
	STONE_HL      = Color3.fromRGB(228, 224, 212),   -- chamfered edges catch the light
	WOOD          = Color3.fromRGB(178, 126, 78),
	WOOD_D        = Color3.fromRGB(134, 92, 56),
	WOOD_L        = Color3.fromRGB(210, 160, 108),   -- chamfered timber edges
	DAMP          = Color3.fromRGB(92, 74, 56),   -- ground darkened where water soaks in
	IRON          = Color3.fromRGB(98, 102, 110),
	IRON_D        = Color3.fromRGB(62, 66, 72),
	BRASS         = Color3.fromRGB(198, 152, 64),
	BRASS_D       = Color3.fromRGB(132, 98, 38),
	RUST          = Color3.fromRGB(140, 82, 48),
	SOIL          = Color3.fromRGB(96, 70, 48),
	SOIL_DRY      = Color3.fromRGB(146, 128, 100),
	LEAF          = Color3.fromRGB(86, 168, 74),
	LEAF_D        = Color3.fromRGB(58, 122, 52),
	PANEL         = Color3.fromRGB(34, 30, 24),
	PANEL_2       = Color3.fromRGB(54, 47, 37),
	CREAM         = Color3.fromRGB(248, 240, 220),
	DEAD_BARK     = Color3.fromRGB(74, 71, 67),
	DEAD_ORB      = Color3.fromRGB(58, 57, 56),
	DEAD_LEAF     = Color3.fromRGB(101, 92, 70),   -- gardens wilt brown, not stone grey
	DEAD_SOIL     = Color3.fromRGB(120, 107, 88),
	DRY_BED       = Color3.fromRGB(126, 112, 92),   -- the garden's "water" part while it's empty
	CROP_LEAF     = Color3.fromRGB(112, 202, 96),
	CROP_LEAF2    = Color3.fromRGB(74, 158, 78),
	CROP_STEM     = Color3.fromRGB(134, 184, 88),
	SOIL_DARK     = Color3.fromRGB(70, 50, 34),   -- the bank's footing, watered
	SOIL_DARK_DRY = Color3.fromRGB(118, 102, 80),   -- ...and parched
	BUB_FILL      = Color3.fromRGB(255, 240, 248),
	BUB_STROKE    = Color3.fromRGB(214, 92, 158),
	BUB_TEXT      = Color3.fromRGB(74, 30, 58),
	BUB_HINT      = Color3.fromRGB(170, 130, 150),
}

local PETALS = {
	Color3.fromRGB(244, 118, 152), Color3.fromRGB(250, 196, 78), Color3.fromRGB(168, 128, 238),
	Color3.fromRGB(246, 246, 250), Color3.fromRGB(240, 106, 92),  Color3.fromRGB(120, 196, 246),
}

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s)
	return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", ""))
end

local function mk(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function playSound(id, volume)
	if not id or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = id; s.Volume = volume or 0.6; s.Parent = SoundService
	s:Play(); Debris:AddItem(s, 5)
end

local function tween(inst, time, goal, style)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad), goal)
	t:Play(); return t
end

local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat
		local r = fn()
		if r then return r end
		task.wait(0.5)
	until os.clock() - t0 > (timeout or 60)
	return fn()
end

-- the island model, so we only ever match markers inside the park
local function findIsland()
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.sub(norm(m.Name), 1, #ISLAND_PREFIX) == ISLAND_PREFIX then
			return m
		end
	end
	return nil
end

-- a marker by name -- inside the island if we found it, anywhere in Workspace otherwise
local function findMarker(key, island)
	local scope = island or Workspace
	for _, d in ipairs(scope:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and norm(d.Name) == key then return d end
	end
	if island then   -- fall back to a global sweep in case it was placed outside the model
		for _, d in ipairs(Workspace:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("Model")) and norm(d.Name) == key then return d end
		end
	end
	return nil
end

-- every marker with this name, not just the first -- the three gates share one name
local function findAllMarkers(key, island)
	local out, scope = {}, island or Workspace
	for _, d in ipairs(scope:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and norm(d.Name) == key then table.insert(out, d) end
	end
	return out
end

local function pivotOf(inst)
	if inst:IsA("Model") then return inst:GetPivot() end
	return inst.CFrame
end

local function sizeOf(inst)
	if inst:IsA("Model") then local _, s = inst:GetBoundingBox(); return s end
	return inst.Size
end

-- hide a marker without deleting it -- it stays in Studio for you to move later
-- Transparency ALONE is not enough to hide a marker: a Decal or Texture child keeps drawing on
-- a fully transparent part, and a SurfaceAppearance overrides the transparency outright. Both
-- have to be dealt with or the placement brick stays visible -- which is exactly what happened
-- with the crop markers in garden 3.
local function hideMarker(inst)
	local function hide(d)
		d.Transparency = 1
		d.CanCollide   = false
		d.CanQuery     = false
		d.CastShadow   = false
		for _, c in ipairs(d:GetChildren()) do
			if c:IsA("Decal") or c:IsA("Texture") then c.Transparency = 1
			elseif c:IsA("SurfaceAppearance") then c:Destroy() end
		end
	end

	if inst:IsA("BasePart") then
		hide(inst)
	elseif inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then hide(d) end
		end
	end
end

-- ============================================================================
-- STATE
-- ============================================================================
local park                  -- Folder holding everything we build
local island, fountainMark
local groundY  = 0          -- the park's floor height, taken off the fountain marker's top
local basinR   = 14         -- basin radius, read off the marker's footprint
local center   = Vector3.new()

local F        = {}         -- fountain: { jets, water, glowLight, ambience, dust }
local ring     = {}         -- the irrigation ring's water pieces, in order round the circle
local gardens  = {}         -- 3 x { mark, pos, size, channel, gate, bloomed }
local butterflies = {}      -- live butterflies, driven by one RenderStepped loop

local step          = 0     -- 0 = dry, 1 = fountain running, 2 = all gates open, 3 = tree awake
local gatesOpen     = 0
local cranking      = nil   -- the garden whose crank we're holding, or nil
local refreshBanner         -- defined in the BANNER section
local takeCrank             -- defined by the console, wired by the gate prompts
local awakenTree            -- the finale; the harvest calls it once every offering is in
local showBubble            -- defined with the Candy Npc; the Keeper borrows it
local offeringsText         -- defined with the banner; the Keeper's dialogue uses it
local ripenGarden           -- defined with the harvest, called when a garden finishes blooming
local playWrench            -- the HUD; the crop prompts are built long before it is defined
local pipes         = {}    -- the burst mains: { turns, prompt, em, collar, wrench, fixed }
local pipesFixed    = 0
local questAccepted = false -- the Candy Npc gates the valve, like island 1 gates its gumballs
local npcHead, valvePrompt

_G.parkQuestStep = 0

-- ============================================================================
-- GROUND
-- ============================================================================
-- Raycast down for the real floor so channels follow the island instead of floating.
-- Anything we built is ignored, so a channel can't land on top of another channel.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshGroundFilter()
	local list = {}
	if park then table.insert(list, park) end
	if player.Character then table.insert(list, player.Character) end
	groundParams.FilterDescendantsInstances = list
end

local function groundYAt(pos)
	refreshGroundFilter()
	local hit = Workspace:Raycast(Vector3.new(pos.X, groundY + 60, pos.Z), Vector3.new(0, -220, 0), groundParams)
	if hit then return hit.Position.Y end
	return groundY
end

-- Read a marker into (floor position, footprint width).
--
-- A marker PART gives us both for free: its top face is the floor and its X/Z is the footprint.
-- An EMPTY MODEL -- which is what garden1..3 and ancienttree actually are in this place -- carries
-- no size at all and its pivot can sit anywhere, so we drop a ray to find the real ground under it
-- and fall back to a sensible default width.
local function readMarker(inst, fallbackFootprint)
	refreshGroundFilter()
	local cf, sz = pivotOf(inst), sizeOf(inst)
	local p = cf.Position

	local foot = math.min(sz.X, sz.Z)
	if foot < 2 then foot = fallbackFootprint end

	local floorY
	if sz.Y > 0.05 then
		floorY = p.Y + sz.Y * 0.5                     -- stand on the part's top face
	else
		local hit = Workspace:Raycast(p + Vector3.new(0, 80, 0), Vector3.new(0, -400, 0), groundParams)
		floorY = hit and hit.Position.Y or p.Y        -- empty model: find the ground beneath it
	end

	return Vector3.new(p.X, floorY, p.Z), foot
end

-- ============================================================================
-- THE FOUNTAIN
-- ============================================================================
-- Built standing on the marker's floor height. Starts DRY: grey, mossy, with a thin drift
-- of dust instead of water.
--
-- SIZE: every dimension is a fraction of R (the basin radius), so changing FOUNTAIN_RADIUS
-- at the top of the file resizes the whole thing in proportion. Nothing here is an absolute
-- stud measurement. At R = 5 it comes out ~12.2 studs wide and ~6 tall.
--
-- SHAPE: LOW POLY. Every round element is a true OCTAGON built from 8 flat slabs -- no
-- cylinders, no smoothing, no colour jitter. Each slab's outer face IS one of the octagon's
-- eight sides, so the silhouette is genuinely faceted rather than a cylinder pretending.
-- Flat SmoothPlastic throughout: low poly lives on clean unbroken colour per facet.
--
-- Sizes are given as the APOTHEM (centre to the middle of a flat side), which is what makes
-- the octagon maths work out exactly; the corners sit ~8% further out than that.
local FACETS = 8

local function buildFountain()
	local folder = Instance.new("Folder"); folder.Name = "Fountain"; folder.Parent = park
	local R = basinR

	local function part(props) local p = mk(props); p.Parent = folder; return p end
	-- the solid masses cast shadows; trim, water and dressing don't -- their shadows read as
	-- noise at this scale and cost more than they're worth
	local function mass(props) props.CastShadow = true; return part(props) end

	-- the length of one octagon side for a given apothem
	local function edgeOf(ap) return 2 * ap * math.tan(math.pi / FACETS) end

	-- Slabs in these rings OVERLAP -- radially in the middle of a disc, and at the corners of
	-- a ring. Overlapping boxes whose top faces sit at exactly the same height Z-FIGHT, which
	-- shows up as a flickering star across every flat surface. Staggering each slab by a few
	-- thousandths of a stud breaks the tie: invisible at any real viewing distance, and it
	-- costs nothing.
	local function stagger(i) return i * 0.0025 end

	-- A SOLID octagonal prism: 8 slabs each running from the centre out to one flat side.
	local function octaDisc(ap, h, y, col, mat)
		local e = edgeOf(ap)
		for i = 1, FACETS do
			local a = ((i - 0.5) / FACETS) * math.pi * 2
			mass({
				Material = mat or Enum.Material.SmoothPlastic, Color = col,
				Size = Vector3.new(ap, h, e),
				CFrame = CFrame.new(center + Vector3.new(math.cos(a) * ap * 0.5, y + stagger(i), math.sin(a) * ap * 0.5))
					* CFrame.Angles(0, -a, 0),
			})
		end
	end

	-- A HOLLOW octagonal ring -- walls and rims. `thick` is added to the side length so the
	-- eight corners close up instead of leaving gaps.
	local function octaRing(ap, thick, h, y, col, mat)
		local e = edgeOf(ap) + thick
		for i = 1, FACETS do
			local a = ((i - 0.5) / FACETS) * math.pi * 2
			local d = ap - thick * 0.5
			mass({
				Material = mat or Enum.Material.SmoothPlastic, Color = col,
				Size = Vector3.new(thick, h, e),
				CFrame = CFrame.new(center + Vector3.new(math.cos(a) * d, y + stagger(i), math.sin(a) * d))
					* CFrame.Angles(0, -a, 0),
			})
		end
	end

	-- A CHAMFER: a thin, slightly inset lighter strip along a top edge. A hard 90-degree
	-- corner reads flat and cheap in a flat-shaded style; a bevel catches the light and is
	-- the single biggest difference between "boxes stacked up" and "carved stone".
	local function octaChamfer(ap, y, h, col)
		octaRing(ap - h * 0.5, h * 1.7, h, y, col)
	end

	-- --- two shallow ground steps, each with a chamfered top edge
	octaDisc(R * 1.22, R * 0.12, R * 0.060, PAL.STONE_D)
	octaChamfer(R * 1.22, R * 0.113, R * 0.026, PAL.STONE)
	octaDisc(R * 1.10, R * 0.10, R * 0.170, PAL.STONE)
	octaChamfer(R * 1.10, R * 0.212, R * 0.024, PAL.STONE_HL)

	-- --- the basin floor
	octaDisc(R * 0.82, R * 0.08, R * 0.26, PAL.STONE_D)

	-- --- the basin wall. This used to be two courses of four bricks per facet over a mortar
	-- backing -- 72 parts, and at a 5-stud basin all that joint detail just read as noise.
	-- It's now two clean bands: 16 parts, and the octagon's eight faces actually show.
	octaRing(R * 1.00, R * 0.20, R * 0.26, R * 0.35, PAL.STONE)
	octaRing(R * 1.01, R * 0.22, R * 0.13, R * 0.545, PAL.STONE_W)

	-- --- rim coping, chamfered
	octaRing(R * 1.06, R * 0.28, R * 0.09, R * 0.665, PAL.STONE_W)
	octaChamfer(R * 1.06, R * 0.706, R * 0.030, PAL.STONE_HL)

	-- --- lower column, with a collar at the foot and a capital under the middle bowl
	octaDisc(R * 0.30, R * 0.07, R * 0.335, PAL.STONE)
	octaDisc(R * 0.20, R * 0.62, R * 0.610, PAL.STONE_W)
	octaDisc(R * 0.30, R * 0.07, R * 0.885, PAL.STONE)

	-- --- four brass spouts that pour into the basin once the water's on
	F.spouts = {}
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + math.pi / 4
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local sp = mass({
			Material = Enum.Material.Metal, Color = PAL.BRASS,
			Size = Vector3.new(R * 0.20, R * 0.09, R * 0.09),
			CFrame = CFrame.new(center + Vector3.new(0, R * 0.80, 0) + dir * R * 0.26)
				* CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(-14)),
		})
		table.insert(F.spouts, { part = sp, dir = dir,
			tip = center + Vector3.new(0, R * 0.77, 0) + dir * R * 0.36 })
	end

	-- --- MIDDLE BOWL
	octaDisc(R * 0.34, R * 0.06, R * 0.900, PAL.STONE)      -- underside boss
	octaDisc(R * 0.60, R * 0.11, R * 0.975, PAL.STONE_W)
	octaRing(R * 0.62, R * 0.10, R * 0.06, R * 1.060, PAL.STONE)

	-- --- upper column
	octaDisc(R * 0.15, R * 0.44, R * 1.250, PAL.STONE_W)

	-- --- TOP BOWL
	octaDisc(R * 0.38, R * 0.09, R * 1.515, PAL.STONE_W)
	octaRing(R * 0.40, R * 0.08, R * 0.05, R * 1.585, PAL.STONE)

	-- --- stem, cap, and a faceted finial: a cube tipped on two axes reads as a cut gem,
	-- which is the low-poly way to get a "bud" without a smooth sphere
	octaDisc(R * 0.09, R * 0.20, R * 1.660, PAL.STONE)
	octaDisc(R * 0.16, R * 0.08, R * 1.800, PAL.STONE_W)
	F.finial = mass({
		Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_W,
		Size = Vector3.new(R * 0.24, R * 0.24, R * 0.24),
		CFrame = CFrame.new(center + Vector3.new(0, R * 1.92, 0))
			* CFrame.Angles(math.rad(35), math.rad(45), 0),
	})

	-- No weathering on the fountain at all any more. The moss slabs inside the basin were the
	-- last fussy detail on it -- at this size they read as smudges rather than moss, and the
	-- unbroken octagon is the best line on the model. The dry state is carried by the dead
	-- leaves and the dust, which both clear the moment the water returns.
	F.leaves = {}
	for i = 1, 4 do
		local a, d = math.random() * math.pi * 2, math.random() * R * 0.66
		local l = part({
			Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(146, 112, 62),
			Size = Vector3.new(R * 0.11, R * 0.012, R * 0.075),
			CFrame = CFrame.new(center + Vector3.new(math.cos(a) * d, R * 0.33, math.sin(a) * d))
				* CFrame.Angles(0, math.random() * 6.28, 0),
		})
		table.insert(F.leaves, l)
	end

	-- a listless puff of dust drifting out of the dry bowl
	do
		local host = part({ Transparency = 1, Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(center + Vector3.new(0, R * 0.55, 0)) })
		local em = Instance.new("ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/smoke_main.dds"
		em.Color = ColorSequence.new(PAL.DUST)
		em.Lifetime = NumberRange.new(1.6, 2.8); em.Rate = 5
		em.Speed = NumberRange.new(R * 0.07, R * 0.21)
		em.SpreadAngle = Vector2.new(40, 40); em.Size = NumberSequence.new(R * 0.23)
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(1, 1) })
		em.Acceleration = Vector3.new(0.4, 0.6, 0); em.Parent = host
		F.dust = em
	end

	-- --- the water, built now but fully hidden until the valve turns.
	-- Full sizes are worked out HERE and stashed, so startFountain never redoes the maths.
	--
	-- The surfaces are round, not octagonal, ON PURPOSE: each is sized to the octagon's
	-- CIRCUMRADIUS (apothem / cos(22.5 deg)), so the disc reaches into the corners and its
	-- curved edge is buried inside the stone. You get filled corners with no visible curve.
	F.waterFull = Vector3.new(R * 0.28, R * 0.866 * 2, R * 0.866 * 2)   -- basin
	F.upperFull = Vector3.new(R * 0.06, R * 0.600 * 2, R * 0.600 * 2)   -- middle bowl
	F.topFull   = Vector3.new(R * 0.05, R * 0.390 * 2, R * 0.390 * 2)   -- top bowl

	local function pool(full, y)
		return part({
			Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = PAL.WATER_L,
			Reflectance = 0.28, Transparency = 1,
			Size = Vector3.new(R * 0.01, full.Y, full.Z),
			CFrame = CFrame.new(center + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		})
	end
	F.water      = pool(F.waterFull, R * 0.440)
	F.upperWater = pool(F.upperFull, R * 1.055)
	F.topWater   = pool(F.topFull,   R * 1.575)

	-- spill sheets: top bowl down into the middle bowl, middle bowl down into the basin
	F.spills = {}
	local function spillRing(count, radius, h, y, w)
		for i = 1, count do
			local a = (i / count) * math.pi * 2
			table.insert(F.spills, part({
				Material = Enum.Material.SmoothPlastic, Color = PAL.WATER_L, Transparency = 1, Reflectance = 0.2,
				Size = Vector3.new(R * 0.05, h, w),
				CFrame = CFrame.new(center + Vector3.new(math.cos(a) * radius, y, math.sin(a) * radius))
					* CFrame.Angles(0, -a, 0),
			}))
		end
	end
	spillRing(4, R * 0.34, R * 0.42, R * 1.260, R * 0.11)   -- top -> middle
	spillRing(6, R * 0.56, R * 0.34, R * 0.750, R * 0.13)   -- middle -> basin

	-- THE MAIN JET out of the finial. Speed AND gravity both scale with R, so the plume's arc
	-- height scales with the fountain rather than being a fixed number of studs.
	do
		local host = part({ Transparency = 1, Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(center + Vector3.new(0, R * 2.14, 0)) })
		local em = Instance.new("ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		em.Color = ColorSequence.new(PAL.WATER_G, PAL.WATER_L)
		em.Lifetime = NumberRange.new(1.1, 1.8); em.Rate = 0
		em.Speed = NumberRange.new(R * 1.75, R * 2.45)      -- taller than before
		em.SpreadAngle = Vector2.new(11, 11); em.Size = NumberSequence.new(R * 0.09)
		em.Acceleration = Vector3.new(0, -R * 3.3, 0); em.LightEmission = 0.85
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		em.Parent = host
		F.jet = em
		F.jetHost = host
	end

	-- A CROWN OF SMALLER JETS around the main one, rising off the top bowl's rim and leaning
	-- outward so they arc away from the centre column instead of fighting the main plume.
	F.crownJets = {}
	for i = 1, 8 do
		local a   = (i / 8) * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local aim = (Vector3.new(0, 1, 0) * 0.86 + dir * 0.5).Unit
		local at  = center + Vector3.new(0, R * 1.60, 0) + dir * R * 0.30
		local host = part({ Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(at, at + aim) })
		local em = Instance.new("ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		em.Color = ColorSequence.new(PAL.WATER_G, PAL.WATER_L)
		em.EmissionDirection = Enum.NormalId.Front
		em.Lifetime = NumberRange.new(0.55, 0.9); em.Rate = 0
		em.Speed = NumberRange.new(R * 0.85, R * 1.15)
		em.SpreadAngle = Vector2.new(6, 6); em.Size = NumberSequence.new(R * 0.05)
		em.Acceleration = Vector3.new(0, -R * 3.0, 0); em.LightEmission = 0.8
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
		em.Parent = host
		table.insert(F.crownJets, em)
	end

	-- the four spouts pour outward and down into the basin. EmissionDirection is Front and
	-- the host is aimed with CFrame.new(pos, target), so each stream follows its own spout.
	F.spoutJets = {}
	for _, s in ipairs(F.spouts) do
		local aim = (s.dir * 0.85 + Vector3.new(0, -0.55, 0)).Unit
		local host = part({ Transparency = 1, Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(s.tip, s.tip + aim) })
		local em = Instance.new("ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		em.Color = ColorSequence.new(PAL.WATER, PAL.WATER_D)
		em.EmissionDirection = Enum.NormalId.Front
		em.Lifetime = NumberRange.new(0.35, 0.6); em.Rate = 0
		em.Speed = NumberRange.new(R * 0.75, R * 1.05)
		em.SpreadAngle = Vector2.new(7, 7); em.Size = NumberSequence.new(R * 0.055)
		em.Acceleration = Vector3.new(0, -R * 3.0, 0); em.LightEmission = 0.4
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
		em.Parent = host
		table.insert(F.spoutJets, em)
	end

	-- --- SOFT MIST hanging low over the basin: big, slow, nearly transparent puffs. Kept
	-- separate from the sparkles because they want opposite settings -- mist is large, slow
	-- and dim; sparkles are tiny, drifting and bright.
	do
		local host = part({ Transparency = 1, Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(center + Vector3.new(0, R * 0.62, 0)) })
		local em = Instance.new("ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/smoke_main.dds"
		em.Color = ColorSequence.new(PAL.WATER_G)
		em.Lifetime = NumberRange.new(2.2, 3.6); em.Rate = 0
		em.Speed = NumberRange.new(R * 0.05, R * 0.18); em.SpreadAngle = Vector2.new(75, 75)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, R * 0.30), NumberSequenceKeypoint.new(1, R * 0.85) })
		em.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.86), NumberSequenceKeypoint.new(1, 1) })
		em.Acceleration = Vector3.new(0, R * 0.1, 0); em.LightEmission = 0.35
		em.Parent = host
		F.mist = em
	end

	-- --- TINY SPARKLES drifting around the whole fountain: the "magical" read
	do
		local host = part({ Transparency = 1, Size = Vector3.new(R * 2.2, R * 2.0, R * 2.2),
			CFrame = CFrame.new(center + Vector3.new(0, R * 1.0, 0)) })
		local em = Instance.new("ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		em.Color = ColorSequence.new(PAL.WATER_G, Color3.fromRGB(255, 255, 255))
		em.Lifetime = NumberRange.new(1.8, 3.2); em.Rate = 0
		em.Speed = NumberRange.new(R * 0.04, R * 0.14); em.SpreadAngle = Vector2.new(180, 180)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, R * 0.05), NumberSequenceKeypoint.new(1, 0) })
		em.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.1), NumberSequenceKeypoint.new(1, 1) })
		em.Acceleration = Vector3.new(0, R * 0.06, 0); em.LightEmission = 1
		em.Parent = host
		F.sparkles = em
	end

	-- --- a faint glow disc sitting just under the basin surface, so the water looks lit from
	-- within rather than merely tinted
	F.glow = part({
		Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = PAL.WATER_G,
		Transparency = 1, Size = Vector3.new(R * 0.02, R * 1.55, R * 1.55),
		CFrame = CFrame.new(center + Vector3.new(0, R * 0.325, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})

	-- a soft light in the bowl, off until the water runs
	local lt = Instance.new("PointLight")
	lt.Brightness = 0; lt.Range = math.max(10, R * 2.8); lt.Color = PAL.WATER_L; lt.Parent = F.water
	F.light = lt

	-- looping burble, created silent and only started with the water
	if SOUND_WATER ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = SOUND_WATER; s.Looped = true; s.Volume = 0; s.RollOffMaxDistance = WATER_RANGE
		s.RollOffMode = Enum.RollOffMode.InverseTapered; s.Parent = F.water
		pcall(function() s:Play() end)
		F.ambience = s
	end

	F.folder = folder
end

local function startFountain()
	playSound(SOUND_VALVE, 0.7)
	if F.dust then F.dust.Rate = 0 end

	local R = basinR

	-- the dead leaves get washed away
	for _, l in ipairs(F.leaves or {}) do
		tween(l, 1.2, { Transparency = 1, CFrame = l.CFrame + Vector3.new(0, -R * 0.3, 0) })
		Debris:AddItem(l, 1.4)
	end

	-- it fills from the TOP DOWN, one tier at a time: top bowl, middle bowl, then the basin.
	-- That ordering is what makes it read as water arriving rather than three pools appearing.
	task.delay(0.35, function()
		if F.jet then F.jet.Rate = 90 end
		tween(F.topWater, 0.7, { Transparency = 0.35, Size = F.topFull })
	end)
	task.delay(0.75, function()
		tween(F.upperWater, 0.8, { Transparency = 0.35, Size = F.upperFull })
	end)
	task.delay(0.55, function()
		for _, em in ipairs(F.crownJets or {}) do em.Rate = 26 end
	end)
	task.delay(0.9, function()
		for _, sp in ipairs(F.spills or {}) do tween(sp, 0.6, { Transparency = 0.42 }) end
		for _, em in ipairs(F.spoutJets or {}) do em.Rate = 34 end
		-- eased back: at the old rates the mist and sparkles were reading as haze over the
		-- stonework rather than as atmosphere around it
		if F.mist then F.mist.Rate = 4 end
		if F.sparkles then F.sparkles.Rate = 9 end
	end)
	task.delay(1.3, function()
		tween(F.water, 1.6, { Transparency = 0.22, Size = F.waterFull })
		tween(F.light, 1.6, { Brightness = 1.4 })
		if F.glow then tween(F.glow, 1.8, { Transparency = 0.82 }) end
		if F.ambience then tween(F.ambience, 1.6, { Volume = WATER_VOLUME }) end
	end)

	-- ripples: the basin surface breathes so it never reads as a flat disc
	task.spawn(function()
		local t, base, amp = 0, F.water.CFrame, R * 0.012
		while F.water and F.water.Parent do
			t += 0.06
			F.water.CFrame = base * CFrame.new(0, 0, math.sin(t * 1.7) * amp)
			task.wait(0.06)
		end
	end)

	-- RIPPLES WHERE THE PAL.WATER ACTUALLY LANDS. Six spill sheets come down on a ring of radius
	-- 0.56R, so the rings start there and spread outward -- rippling from the dead centre
	-- (where nothing hits) was the thing that read as fake.
	task.delay(1.9, function()
		local i = 0
		while F.water and F.water.Parent do
			i += 1
			local a  = (i / 6) * math.pi * 2
			local at = center + Vector3.new(math.cos(a) * R * 0.56, R * 0.585, math.sin(a) * R * 0.56)
			local ring = mk({
				Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = PAL.WATER_G,
				Size = Vector3.new(R * 0.006, R * 0.10, R * 0.10), Transparency = 0.4,
				CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
				Parent = F.folder,
			})
			tween(ring, 1.6, { Size = Vector3.new(R * 0.006, R * 0.78, R * 0.78), Transparency = 1 })
			Debris:AddItem(ring, 1.8)

			-- a small splash where that sheet meets the pool
			local sp = Instance.new("ParticleEmitter")
			sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sp.Color = ColorSequence.new(PAL.WATER_G); sp.Lifetime = NumberRange.new(0.3, 0.55)
			sp.Rate = 0; sp.Speed = NumberRange.new(R * 0.25, R * 0.6)
			sp.SpreadAngle = Vector2.new(60, 60); sp.Size = NumberSequence.new(R * 0.045)
			sp.Acceleration = Vector3.new(0, -R * 3, 0); sp.LightEmission = 0.8
			sp.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			sp.Parent = ring; sp:Emit(7)

			task.wait(0.42)
		end
	end)
end

-- ============================================================================
-- THE ANCIENT TREE -- dead until the park is saved
-- ============================================================================
-- 'ancienttree' is REAL ART, not a marker, so we never build or move it: we only recolour it.
-- Every BasePart's original Color / Material / texture is recorded first, so reviving is an
-- exact restore rather than a guess at what it used to be.
--
-- The orbs (the many parts named "ball") go grey along with the bark, as asked -- they're the
-- thing that reads as "the lights have gone out".
--
-- MeshPart textures are cleared while dead and put back on revive. Without that, a textured
-- mesh ignores Color entirely and the tree would stay green no matter what we set.

local orig = {}          -- instance -> { Color, Material, TextureID / TextureId }

local function treeColour(d)
	return string.find(norm(d.Name), "ball", 1, true) and PAL.DEAD_ORB or PAL.DEAD_BARK
end

local function gardenColour(d)
	local n = norm(d.Name)
	if string.find(n, "soil", 1, true) or string.find(n, "dirt", 1, true)
		or string.find(n, "ground", 1, true) or string.find(n, "grass", 1, true) then
		return PAL.DEAD_SOIL
	end
	return PAL.DEAD_LEAF
end

-- Is this part planting, or is it scenery? Only planting gets shrunk down and grown back --
-- shrinking a fence, a path or the ground itself would just look broken.
local SCENERY_WORDS = { "ground", "soil", "dirt", "grass", "fence", "wall", "path", "rock",
                        "stone", "base", "floor", "terrain", "pot", "plot", "border", "water" }

local function isPlantPart(d)
	local n = norm(d.Name)
	for _, w in ipairs(SCENERY_WORDS) do
		if string.find(n, w, 1, true) then return false end
	end
	local s = d.Size
	return math.max(s.X, s.Y, s.Z) <= PLANT_MAX
end

-- Parts the wilt system must never touch again: hidden crop markers and the water beds, both
-- of which are handled on their own terms. Without this the 10-second re-wilt sweep could
-- reclaim them, re-shrink a marker and quietly re-add it to the growth set.
local skipParts = {}

local function recolourPart(d, colFn, shrink)
	if not d:IsA("BasePart") or skipParts[d] then return false end
	if orig[d] == nil then
		orig[d] = { Color = d.Color, Material = d.Material, Size = d.Size, CFrame = d.CFrame,
		            TextureID = d:IsA("MeshPart") and d.TextureID or nil }
	end
	d.Color    = colFn(d)
	d.Material = Enum.Material.Slate

	-- shrink planting toward the GROUND, not toward its own centre: drop it by half the
	-- height it just lost, so a shrunken flower still sits on the soil instead of hovering
	if shrink and isPlantPart(d) then
		local o = orig[d]
		local small = o.Size * PLANT_SHRINK
		d.Size   = small
		d.CFrame = o.CFrame * CFrame.new(0, -(o.Size.Y - small.Y) * 0.5, 0)
	end
	-- TextureID isn't writable on every MeshPart; if it refuses, that mesh just keeps its
	-- texture rather than taking the whole pass down with it.
	if d:IsA("MeshPart") then pcall(function() d.TextureID = "" end) end
	for _, m in ipairs(d:GetChildren()) do        -- SpecialMesh textures hide Color the same way
		if m:IsA("SpecialMesh") and m.TextureId ~= "" then
			if orig[m] == nil then orig[m] = { TextureId = m.TextureId } end
			pcall(function() m.TextureId = "" end)
		end
	end
	return true
end

-- `growTime` > 0 makes a shrunken plant TWEEN back to full size instead of snapping there,
-- which is what turns "the colours came back" into "it grew".
local function restorePart(p, growTime)
	local o = orig[p]
	if not (o and p.Parent) then return nil end
	p.Color    = o.Color
	p.Material = o.Material
	if o.TextureID and p:IsA("MeshPart") then pcall(function() p.TextureID = o.TextureID end) end
	for _, m in ipairs(p:GetChildren()) do
		local mo = orig[m]
		if mo and mo.TextureId then pcall(function() m.TextureId = mo.TextureId end) end
	end
	if o.Size and (p.Size - o.Size).Magnitude > 0.05 then
		if growTime and growTime > 0 then
			tween(p, growTime, { Size = o.Size, CFrame = o.CFrame }, Enum.EasingStyle.Back)
		else
			p.Size, p.CFrame = o.Size, o.CFrame
		end
	end
	return o
end

-- Wilt a whole model. Returns a "patch" handle you later hand to revive().
local function wilt(model, colFn, label, shrink)
	local patch = { model = model, dead = true, seen = {} }
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if recolourPart(d, colFn, shrink) then patch.seen[d] = true; n += 1 end
	end

	-- StreamingEnabled hands parts back as you approach, freshly coloured from the server, so
	-- a one-shot pass would leave half the model alive. Catch anything that arrives late, and
	-- sweep periodically for parts that were re-sent rather than re-added.
	model.DescendantAdded:Connect(function(d)
		if not patch.dead then return end
		task.defer(function()
			if patch.dead and recolourPart(d, colFn, shrink) then patch.seen[d] = true end
		end)
	end)
	task.spawn(function()
		while patch.dead do
			task.wait(10)
			if patch.dead and model.Parent then
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d.Material ~= Enum.Material.Slate then
						if recolourPart(d, colFn, shrink) then patch.seen[d] = true end
					end
				end
			end
		end
	end)

	print(("[Park] %s wilted -- %d part(s) recorded"):format(label, n))
	return patch
end

-- Restore a patch in a visible sweep. `sortFn` decides the direction life travels;
-- `onEach` gets each part plus its original values, for per-part flourishes.
--
-- The sweep is paced to a fixed TOTAL duration and yields in batches, not once per part --
-- these models run to hundreds of parts, and a task.wait() each would either crawl or stutter.
local function revive(patch, sortFn, duration, onEach)
	if not (patch and patch.dead) then return end
	patch.dead = false

	local parts = {}
	for p in pairs(patch.seen) do
		if p.Parent then table.insert(parts, p) end
	end
	table.sort(parts, sortFn)

	task.spawn(function()
		local per, acc = (duration or 2.2) / math.max(1, #parts), 0
		for _, p in ipairs(parts) do
			local o = restorePart(p)
			if o and onEach then onEach(p, o) end
			acc += per
			if acc >= 0.03 then task.wait(acc); acc = 0 end
		end
	end)
	return #parts
end

-- ---- the tree ---------------------------------------------------------------
local tree, treePatch

local function killTree()
	tree = tree or findMarker(TREE_NAME, island)
	if not tree then warn("[Park] no 'ancienttree' found -- skipping the tree"); return false end
	treePatch = wilt(tree, treeColour, "ancient tree")
	return true
end

local function reviveTree()
	if not treePatch then return end
	-- bottom to top, so life visibly climbs the trunk into the branches
	revive(treePatch, function(a, b) return a.Position.Y < b.Position.Y end, 3.4, function(p, o)
		if string.find(norm(p.Name), "ball", 1, true) then
			local glow = Instance.new("PointLight")
			glow.Color = o.Color; glow.Brightness = 3; glow.Range = 14; glow.Parent = p
			tween(glow, 1.4, { Brightness = 0 })
			Debris:AddItem(glow, 1.6)
		end
	end)
	print("[Park] ancient tree restoring to its original colours")
end

-- ============================================================================
-- THE UNDERGROUND CONDUIT
-- ============================================================================
-- There are NO VISIBLE CHANNELS. The irrigation runs buried, so the park above ground stays
-- clean and uncluttered -- opening a gate simply sends water underground to that garden, and
-- every bit of the payoff happens inside the planting itself.
--
-- Nothing is built here at all. The "conduit" is only a route and a travel time: putting real
-- geometry under the ground would cost parts for something nobody can ever see.

-- A continuous little splash, for where water surfaces inside a garden.
local function splashAt(pos, folder)
	local host = mk({ Transparency = 1, Size = Vector3.new(1, 1, 1),
	                  CFrame = CFrame.new(pos), Parent = folder or park })
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(PAL.WATER_G, PAL.WATER_L)
	em.Lifetime = NumberRange.new(0.35, 0.7); em.Rate = 0
	em.Speed = NumberRange.new(2, 6); em.SpreadAngle = Vector2.new(55, 55)
	em.Size = NumberSequence.new(0.34); em.LightEmission = 0.8
	em.Acceleration = Vector3.new(0, -16, 0)
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	em.Parent = host
	return em
end

-- Where a garden's water comes from, and which way it faces. buildGate needs channelDir for
-- the gate's facing, and floodGarden needs the entry point, so this runs before both.
local function planRoute(g)
	local flat = (g.pos - center) * Vector3.new(1, 0, 1)
	g.channelDir  = (flat.Magnitude > 0.01) and flat.Unit or Vector3.new(0, 0, 1)
	g.channelFrom = center + g.channelDir * (basinR + RING_GAP)
	g.channelSpan = flat.Magnitude
	g.segLen      = 7
	g.segments    = {}
end

-- The water runs from the gate to the garden out of sight, so all the player is owed is a
-- believable delay before it surfaces.
local function deliverWater(g, onArrive)
	playSound(SOUND_RUSH, 0.6)
	local from = g.gatePos or g.channelFrom or center
	local dist = ((g.pos - from) * Vector3.new(1, 0, 1)).Magnitude
	task.delay(math.clamp(dist / FILL_SPEED, 0.8, 4.5), function()
		if onArrive then onArrive() end
	end)
end

-- ============================================================================
-- THE GATES -- an old wooden garden water control, seized shut
-- ============================================================================
local function buildGate(g, idx)
	local folder = Instance.new("Folder"); folder.Name = "Gate" .. idx; folder.Parent = park

	local pos = g.gateMark and pivotOf(g.gateMark).Position
		or (g.channelFrom + g.channelDir * (g.channelSpan * 0.33))
	local y   = groundYAt(pos)
	if g.gateMark then hideMarker(g.gateMark) end   -- it only marks the spot; the gate is built here
	local at  = Vector3.new(pos.X, y, pos.Z)
	g.gatePos = at

	-- Face the handwheel back toward the FOUNTAIN, worked out from where this gate actually
	-- stands rather than from the garden's bearing -- your gate parts aren't necessarily on
	-- the straight line between the two.
	local toF = (center - at) * Vector3.new(1, 0, 1)
	local face = (toF.Magnitude > 0.5) and toF.Unit or -g.channelDir
	-- yaw first, then walk it along its OWN forward axis, then drop it in world Y. Done in
	-- that order the nudge follows the gate's new heading rather than the old one.
	local base = CFrame.new(at, at + face)
		* CFrame.Angles(0, math.rad(GATE_YAW), 0)
		* CFrame.new(0, 0, -GATE_FWD)
		+ Vector3.new(0, GATE_DROP, 0)

	-- An old garden water control: two timber posts on stone footings, a crossbeam, and a
	-- planked sluice board on iron straps that winds up when you turn the handwheel.
	local hw = CHANNEL_W / 2
	local px = hw + 0.75                      -- how far out the posts stand

	for _, s in ipairs({ -1, 1 }) do
		-- stone footing
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_D, Size = Vector3.new(1.5, 0.9, 2.5),
		     CFrame = base * CFrame.new(s * px, 0.45, 0), Parent = folder })
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_HL, Size = Vector3.new(1.2, 0.1, 2.2),
		     CFrame = base * CFrame.new(s * px, 0.92, 0), Parent = folder })
		-- timber post, chamfered down its outer edges with a collar top and bottom
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.WOOD, Size = Vector3.new(0.78, 4.6, 0.78),
		     CFrame = base * CFrame.new(s * px, 3.2, 0), Parent = folder })
		for _, cz in ipairs({ -0.33, 0.33 }) do
			mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.WOOD_L, Size = Vector3.new(0.22, 4.5, 0.22),
			     CFrame = base * CFrame.new(s * (px + 0.33), 3.2, cz), Parent = folder })
		end
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.WOOD_D, Size = Vector3.new(1.0, 0.34, 1.0),
		     CFrame = base * CFrame.new(s * px, 1.06, 0), Parent = folder })
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.WOOD_D, Size = Vector3.new(0.96, 0.28, 0.96),
		     CFrame = base * CFrame.new(s * px, 5.42, 0), Parent = folder })
		-- a diagonal brace up into the crossbeam
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.WOOD_D, Size = Vector3.new(0.40, 1.9, 0.40),
		     CFrame = base * CFrame.new(s * (px - 0.52), 4.85, 0) * CFrame.Angles(0, 0, math.rad(38 * s)),
		     Parent = folder })

		-- iron hinge plates bolted to the post, with visible bolt heads
		for _, hy in ipairs({ 1.7, 3.6 }) do
			mk({ Material = Enum.Material.Metal, Color = PAL.IRON, Size = Vector3.new(0.94, 0.44, 0.98),
			     CFrame = base * CFrame.new(s * px, hy, 0), Parent = folder })
			mk({ Material = Enum.Material.Metal, Color = PAL.IRON_D, Size = Vector3.new(0.99, 0.14, 0.30),
			     CFrame = base * CFrame.new(s * px, hy, s * 0.02), Parent = folder })
			for _, bz in ipairs({ -0.32, 0.32 }) do
				mk({ Material = Enum.Material.Metal, Color = PAL.IRON_D, Size = Vector3.new(0.16, 0.16, 0.16),
				     CFrame = base * CFrame.new(s * (px + 0.46), hy, bz), Parent = folder })
			end
		end
	end

	-- crossbeam over the top, with a chamfer so it doesn't read as a bare box
	mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.WOOD_D, Size = Vector3.new(px * 2 + 1.1, 0.62, 0.9),
	     CFrame = base * CFrame.new(0, 5.65, 0), Parent = folder })
	mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.WOOD, Size = Vector3.new(px * 2 + 0.7, 0.1, 0.72),
	     CFrame = base * CFrame.new(0, 5.98, 0), Parent = folder })
	-- the iron screw the board rides up
	mk({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, Color = PAL.IRON_D,
	     Size = Vector3.new(2.4, 0.26, 0.26),
	     CFrame = base * CFrame.new(0, 4.4, 0) * CFrame.Angles(0, 0, math.rad(90)), Parent = folder })

	-- --- THE DOORWAY the water comes out of: stone jambs either side and a lintel over the top,
	-- so the opening reads as a built sluice door rather than a gap between two posts.
	--
	-- The frame sits at z +0.72 -- downstream, on the garden side -- while the board is at z 0.
	-- Keeping them apart matters: the board travels 2.7 studs up when the gate opens, and if
	-- the frame shared its plane the plank would sweep straight through the lintel.
	local openW = 2.05                                  -- half-width of the opening
	local jambW = px - openW + 0.1
	-- The jambs are LAID IN COURSES rather than being one tall box, with the tones stepping
	-- through a fixed set and alternate courses set back slightly. Same masonry language as the
	-- fountain's basin wall, and it stops the doorway reading as two grey slabs.
	local COURSE = { PAL.STONE, PAL.STONE_W, PAL.STONE_D, PAL.STONE_W, PAL.STONE }
	for _, s in ipairs({ -1, 1 }) do
		local x = s * (openW + jambW * 0.5)
		for c = 1, 5 do
			local h = 3.1 / 5
			mk({ Material = Enum.Material.SmoothPlastic, Color = COURSE[c],
			     Size = Vector3.new(jambW * ((c % 2 == 0) and 0.93 or 1.0), h * 0.95, 0.9),
			     CFrame = base * CFrame.new(x, (c - 0.5) * h, 0.72), Parent = folder })
		end
		-- a wider footing course at the bottom, and the chamfer along the top edge
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_D,
		     Size = Vector3.new(jambW * 1.14, 0.34, 1.04),
		     CFrame = base * CFrame.new(x, 0.17, 0.72), Parent = folder })
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_HL,
		     Size = Vector3.new(jambW * 0.9, 0.12, 0.3),
		     CFrame = base * CFrame.new(x, 3.13, 1.13), Parent = folder })
		-- moss creeping up out of the joints, low and sparse
		mk({ Material = Enum.Material.Grass, Color = PAL.MOSS,
		     Size = Vector3.new(jambW * 0.5, 0.16, 0.26),
		     CFrame = base * CFrame.new(x - s * jambW * 0.12, 0.42, 1.14), Parent = folder })
	end
	mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_D,
	     Size = Vector3.new(px * 2 + 0.4, 0.62, 0.9),
	     CFrame = base * CFrame.new(0, 3.42, 0.72), Parent = folder })
	mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_HL,
	     Size = Vector3.new(px * 2 + 0.46, 0.13, 0.3),
	     CFrame = base * CFrame.new(0, 3.75, 1.13), Parent = folder })
	-- a keystone over the middle of the opening, with iron tie-plates either side of it
	mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_W,
	     Size = Vector3.new(0.7, 0.86, 0.96),
	     CFrame = base * CFrame.new(0, 3.42, 0.72), Parent = folder })
	for _, s in ipairs({ -1, 1 }) do
		mk({ Material = Enum.Material.Metal, Color = PAL.IRON,
		     Size = Vector3.new(0.5, 0.34, 0.1),
		     CFrame = base * CFrame.new(s * 1.35, 3.42, 1.18), Parent = folder })
		for _, by in ipairs({ -0.09, 0.09 }) do
			mk({ Material = Enum.Material.Metal, Color = PAL.IRON_D,
			     Size = Vector3.new(0.12, 0.12, 0.08),
			     CFrame = base * CFrame.new(s * 1.35, 3.42 + by, 1.24), Parent = folder })
		end
	end

	-- --- the sluice board: three planks and two iron straps. They all lift together, so they
	-- are collected in plateParts rather than being one box (openGate tweens the whole list).
	g.plateParts = {}
	for i = -1, 1 do
		table.insert(g.plateParts, mk({
			Material = Enum.Material.SmoothPlastic, Color = (i == 0) and PAL.WOOD or PAL.WOOD_D,
			Size = Vector3.new(1.28, 2.9, 0.24),
			CFrame = base * CFrame.new(i * 1.33, 1.55, 0), Parent = folder }))
	end
	for _, sy in ipairs({ 0.75, 2.35 }) do
		table.insert(g.plateParts, mk({
			Material = Enum.Material.Metal, Color = PAL.IRON,
			Size = Vector3.new(4.05, 0.24, 0.32),
			CFrame = base * CFrame.new(0, sy, 0), Parent = folder }))
		-- bolt heads along the strap. They go in plateParts too, so they lift WITH the board
		-- instead of being left hanging in the air when it opens.
		for bi = -2, 2 do
			table.insert(g.plateParts, mk({
				Material = Enum.Material.Metal, Color = PAL.IRON_D,
				Size = Vector3.new(0.18, 0.18, 0.14),
				CFrame = base * CFrame.new(bi * 0.92, sy, -0.20), Parent = folder }))
		end
	end
	g.plate = g.plateParts[2]                 -- the middle plank, for the dust emitter

	-- --- stone sill under the board, and the apron the water spills onto downstream.
	-- Downstream is local +Z: `base` looks toward the fountain, so +Z is the garden side.
	mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_D,
	     Size = Vector3.new(CHANNEL_W + 1.4, 0.6, 1.2),
	     CFrame = base * CFrame.new(0, 0.30, 0.45), Parent = folder })
	mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE,
	     Size = Vector3.new(CHANNEL_W + 1.9, 0.42, 4.2),
	     CFrame = base * CFrame.new(0, 0.21, 3.2), Parent = folder })
	mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_HL,
	     Size = Vector3.new(CHANNEL_W + 1.9, 0.10, 0.34),
	     CFrame = base * CFrame.new(0, 0.44, 5.16), Parent = folder })
	for _, s in ipairs({ -1, 1 }) do          -- low kerbs either side of the apron
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_D,
		     Size = Vector3.new(0.5, 0.5, 4.2),
		     CFrame = base * CFrame.new(s * (CHANNEL_W * 0.5 + 1.2), 0.42, 3.2), Parent = folder })
	end

	-- --- the handwheel: a wooden octagon rim, four spokes, four grip knobs, iron hub.
	-- Still a Model called Wheel pivoted about wheelCF, so the crank code drives it unchanged.
	local wheel   = Instance.new("Model"); wheel.Name = "Wheel"; wheel.Parent = folder
	-- the handwheel sits on the FOUNTAIN side (local -Z). base looks toward the fountain,
	-- so -Z is where the player walks in from and where the crank camera sits; on +Z the
	-- doorway and the raised board stood between the camera and the wheel.
	local wheelCF = base * CFrame.new(0, 3.95, -1.15)
	-- A CARTWHEEL, not an octagon: a 12-sided wooden felloe with an iron tyre banded round the
	-- outside of it, six spokes, and a machined hub. Eight segments read as a stop sign; twelve
	-- read as round while still being obviously faceted.
	local rimR  = 1.75
	local SEG   = 12
	local chord = 2 * rimR * math.tan(math.pi / SEG) * 1.06

	for i = 1, SEG do
		local a  = (i / SEG) * math.pi * 2
		local cf = wheelCF * CFrame.new(math.cos(a) * rimR, math.sin(a) * rimR, 0)
			* CFrame.Angles(0, 0, a)
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.WOOD,          -- felloe
		     Size = Vector3.new(0.34, chord, 0.46), CFrame = cf, Parent = wheel })
		mk({ Material = Enum.Material.Metal, Color = PAL.IRON,                  -- iron tyre
		     Size = Vector3.new(0.13, chord * 1.02, 0.56),
		     CFrame = cf * CFrame.new(0.23, 0, 0), Parent = wheel })
	end

	-- three bars through the hub make six spokes
	for i = 1, 3 do
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.WOOD_D,
		     Size = Vector3.new(0.22, rimR * 2, 0.30),
		     CFrame = wheelCF * CFrame.Angles(0, 0, (i / 3) * math.pi), Parent = wheel })
	end

	-- hub: a machined drum with a cap on the face you look at
	mk({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, Color = PAL.IRON,
	     Size = Vector3.new(0.72, 1.02, 1.02),
	     CFrame = wheelCF * CFrame.Angles(0, math.rad(90), 0), Parent = wheel })
	mk({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, Color = PAL.IRON_D,
	     Size = Vector3.new(0.18, 0.62, 0.62),
	     CFrame = wheelCF * CFrame.new(0, 0, -0.44) * CFrame.Angles(0, math.rad(90), 0), Parent = wheel })

	-- grip handles, on the -Z face: that's the fountain side, where the player stands and where
	-- the crank camera sits. On +Z they'd be hidden behind the wheel.
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + math.pi / 8
		local at = wheelCF * CFrame.new(math.cos(a) * rimR, math.sin(a) * rimR, -0.56)
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.WOOD_L,
		     Size = Vector3.new(0.30, 0.30, 0.86), CFrame = at, Parent = wheel })
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.WOOD_D,
		     Size = Vector3.new(0.40, 0.40, 0.22),
		     CFrame = at * CFrame.new(0, 0, -0.40), Parent = wheel })
	end

	-- the axle running back into the frame
	mk({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, Color = PAL.IRON_D,
	     Size = Vector3.new(1.5, 0.30, 0.30),
	     CFrame = wheelCF * CFrame.new(0, 0, 0.7) * CFrame.Angles(0, math.rad(90), 0), Parent = wheel })
	wheel.WorldPivot = wheelCF

	-- --- the water that pours out of the gate. Built now, hidden until it opens.
	local chuteLen = 3.6
	g.chuteCF = base * CFrame.new(0, 0.78, 1.65) * CFrame.Angles(math.rad(38), 0, 0)
	g.chute = mk({
		Material = Enum.Material.SmoothPlastic, Color = PAL.WATER_L, Reflectance = 0.26,
		Transparency = 1, Size = Vector3.new(CHANNEL_W - 0.7, 0.24, chuteLen),
		CFrame = g.chuteCF, Parent = folder })
	g.chuteLen = chuteLen

	-- --- THE MOUTH. A bare angled slab reads as a ramp; a weir the water breaks over, with
	-- cheeks either side to contain the sheet, reads as a spout.
	-- the weir sits just past the doorway, so the water breaks over it as it leaves the opening
	mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_D,
	     Size = Vector3.new(CHANNEL_W + 1.0, 0.6, 0.8),
	     CFrame = base * CFrame.new(0, 1.02, 1.28), Parent = folder })
	mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_HL,     -- chamfered lip
	     Size = Vector3.new(CHANNEL_W + 1.0, 0.13, 0.34),
	     CFrame = base * CFrame.new(0, 1.32, 1.08), Parent = folder })
	for _, s in ipairs({ -1, 1 }) do
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE,
		     Size = Vector3.new(0.5, 0.98, chuteLen * 1.04),
		     CFrame = g.chuteCF * CFrame.new(s * ((CHANNEL_W - 0.7) * 0.5 + 0.25), 0.3, 0),
		     Parent = folder })
		mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.STONE_HL,
		     Size = Vector3.new(0.26, 0.11, chuteLen * 1.0),
		     CFrame = g.chuteCF * CFrame.new(s * ((CHANNEL_W - 0.7) * 0.5 + 0.37), 0.78, 0),
		     Parent = folder })
	end

	g.gatePool = mk({
		Material = Enum.Material.SmoothPlastic, Color = PAL.WATER_L, Reflectance = 0.26,
		Transparency = 1, Size = Vector3.new(CHANNEL_W + 0.9, 0.16, 3.4),
		CFrame = base * CFrame.new(0, 0.46, 3.3), Parent = folder })

	-- white water: a foam line where the sheet breaks over the weir, and a foam patch where it
	-- lands. Both hidden until the gate opens.
	g.foamTop = mk({ Material = Enum.Material.Neon, Color = PAL.WATER_G, Transparency = 1,
	                 Size = Vector3.new(CHANNEL_W - 0.75, 0.18, 0.55),
	                 CFrame = g.chuteCF * CFrame.new(0, 0.20, -chuteLen * 0.44), Parent = folder })
	g.foamBase = mk({ Material = Enum.Material.Neon, Color = PAL.WATER_G, Transparency = 1,
	                  Size = Vector3.new(CHANNEL_W + 0.3, 0.13, 1.6),
	                  CFrame = base * CFrame.new(0, 0.54, 2.65), Parent = folder })

	g.gateBase  = base
	g.splashPos = (base * CFrame.new(0, 0.55, 2.5)).Position

	-- rust flakes that shake loose while you heave on it
	local flakes = Instance.new("ParticleEmitter")
	flakes.Texture = "rbxasset://textures/particles/smoke_main.dds"
	flakes.Color = ColorSequence.new(PAL.RUST); flakes.Lifetime = NumberRange.new(0.5, 1.0)
	flakes.Rate = 0; flakes.Speed = NumberRange.new(2, 6); flakes.SpreadAngle = Vector2.new(70, 70)
	flakes.Size = NumberSequence.new(0.5); flakes.Acceleration = Vector3.new(0, -22, 0)
	flakes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	flakes.Parent = g.plate

	-- the prompt part: invisible but QUERYABLE, unlike everything else we build
	local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(6, 8, 6),
	                 CFrame = base * CFrame.new(0, 4.5, -1.4), Parent = folder })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CrankPrompt"
	prompt.ActionText = "Take the Crank"
	prompt.ObjectText = "Irrigation Gate " .. idx
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = CRANK_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false                     -- nothing to crank until the water is back
	prompt.Parent = hit
	prompt.Triggered:Connect(function(plr)
		if plr == player and takeCrank then takeCrank(g) end
	end)

	g.wheel     = wheel
	g.wheelCF   = wheelCF
	g.flakes    = flakes
	g.prompt    = prompt
	g.gateFacing = face
	g.angle     = 0
	g.progress  = 0
	g.seizeIdx  = 1
	g.gateFolder = folder
end


-- Decide how each garden is handled.
--
-- If 'gardenN' is REAL ART -- a model with actual parts, which is what island 13 has -- we
-- wilt it and later restore its own colours. Nothing is ever built on top of your model.
-- Only a bare, partless marker falls back to the procedural bed above.
-- ============================================================================
-- CROPS
-- ============================================================================
-- One plant built standing on a crop marker. Three shapes, picked at random, all flat-shaded
-- and bright to match the rest of the park. `s` scales the whole thing off the marker's size.
local function buildCrop(rootCF, s, folder)
	local parts  = {}
	local accent = PETALS[math.random(1, #PETALS)]
	local function add(col, size, cf, shape)
		local p = mk({ Material = Enum.Material.SmoothPlastic, Color = col, Size = size, CFrame = cf })
		if shape then p.Shape = shape end
		p.Parent = folder
		table.insert(parts, p)
		return p
	end

	-- a little heap of turned earth at the base of every plant. Without it a crop reads as
	-- stuck INTO flat soil rather than grown out of it, whichever variant it is.
	add(PAL.SOIL_DARK, Vector3.new(0.92 * s, 0.26 * s, 0.92 * s), rootCF * CFrame.new(0, 0.09 * s, 0))
	add(PAL.SOIL, Vector3.new(0.62 * s, 0.20 * s, 0.62 * s),
		rootCF * CFrame.new(0, 0.17 * s, 0) * CFrame.Angles(0, 0.7, 0))

	local kind, fruit = math.random(1, 3), nil
	if kind == 1 then
		-- leafy bush with fruit sitting on top
		add(PAL.CROP_STEM, Vector3.new(0.22 * s, 1.2 * s, 0.22 * s), rootCF * CFrame.new(0, 0.60 * s, 0))
		for i = 1, 5 do
			local a = (i / 5) * math.pi * 2
			add((i % 2 == 0) and PAL.CROP_LEAF or PAL.CROP_LEAF2,
				Vector3.new(1.00 * s, 0.15 * s, 0.52 * s),
				rootCF * CFrame.new(math.cos(a) * 0.44 * s, 0.52 * s, math.sin(a) * 0.44 * s)
					* CFrame.Angles(0, -a, math.rad(26)))
		end
		fruit = add(accent, Vector3.new(0.66 * s, 0.66 * s, 0.66 * s),
			rootCF * CFrame.new(0, 1.36 * s, 0), Enum.PartType.Ball)
		add(accent, Vector3.new(0.38 * s, 0.38 * s, 0.38 * s),
			rootCF * CFrame.new(0.38 * s, 1.02 * s, -0.22 * s), Enum.PartType.Ball)

	elseif kind == 2 then
		-- tall stalk with pods up the side
		for _, dx in ipairs({ -0.16, 0.16 }) do
			add(PAL.CROP_STEM, Vector3.new(0.18 * s, 2.0 * s, 0.18 * s),
				rootCF * CFrame.new(dx * s, 1.0 * s, 0))
		end
		for i = 1, 4 do
			local a = (i / 4) * math.pi * 2
			add((i % 2 == 0) and PAL.CROP_LEAF or PAL.CROP_LEAF2,
				Vector3.new(0.90 * s, 0.14 * s, 0.34 * s),
				rootCF * CFrame.new(math.cos(a) * 0.40 * s, (0.55 + i * 0.32) * s, math.sin(a) * 0.40 * s)
					* CFrame.Angles(0, -a, math.rad(34)))
		end
		for i = 1, 3 do
			local pod = add(accent, Vector3.new(0.32 * s, 0.50 * s, 0.32 * s),
				rootCF * CFrame.new(0, (1.20 + i * 0.34) * s, 0.24 * s), Enum.PartType.Ball)
			if i == 3 then fruit = pod end       -- the topmost pod is what you pick
		end

	else
		-- low mound with berries dotted over it
		for i = 1, 3 do
			local a = (i / 3) * math.pi * 2
			add((i % 2 == 0) and PAL.CROP_LEAF or PAL.CROP_LEAF2,
				Vector3.new(1.15 * s, 0.85 * s, 1.15 * s),
				rootCF * CFrame.new(math.cos(a) * 0.30 * s, 0.42 * s, math.sin(a) * 0.30 * s),
				Enum.PartType.Ball)
		end
		for i = 1, 5 do
			local a = (i / 5) * math.pi * 2 + 0.5
			local berry = add(accent, Vector3.new(0.30 * s, 0.30 * s, 0.30 * s),
				rootCF * CFrame.new(math.cos(a) * 0.52 * s, 0.78 * s, math.sin(a) * 0.52 * s),
				Enum.PartType.Ball)
			if i == 1 then fruit = berry end
		end
	end
	-- `fruit` is the pickable piece: the accent-coloured part the harvest prompt goes on
	return parts, fruit
end

-- Shrink a crop part toward the crop's ROOT, not toward its own centre, so the whole plant
-- collapses to a seedling as one object and grows back as one. Shrinking each part about
-- itself would make the leaves sink into the stem instead.
local function registerCrop(p, rootCF, patch)
	local o = { Color = p.Color, Material = p.Material, Size = p.Size, CFrame = p.CFrame }
	orig[p] = o
	local rel = rootCF:ToObjectSpace(o.CFrame)
	p.Size   = o.Size * PLANT_SHRINK
	p.CFrame = rootCF * (CFrame.new(rel.Position * PLANT_SHRINK) * (rel - rel.Position))
	patch.seen[p] = true
end

-- A crop marker can be a single Part or a whole Model. Either way we want its frame.
local function markerFrame(inst)
	if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
	return inst:GetBoundingBox()
end

-- Take a marker over completely: undo the shrink/recolour wilt already applied to it, take it
-- out of the growth set for good, and hide it.
--
-- Hiding is more than Transparency: a Decal or Texture child keeps drawing on a fully
-- transparent part, and a SurfaceAppearance overrides the part's transparency outright. Those
-- have to be dealt with too or the marker stays visible under the crops.
local function claimMarker(inst, patch)
	local function take(d)
		local o = orig[d]
		if o then
			d.Size, d.CFrame    = o.Size, o.CFrame
			d.Color, d.Material = o.Color, o.Material
			orig[d] = nil
		end
		if patch then patch.seen[d] = nil end
		skipParts[d]   = true
		d.Transparency = 1
		d.CanCollide   = false
		d.CanQuery     = false
		d.CastShadow   = false
		for _, c in ipairs(d:GetChildren()) do
			if c:IsA("Decal") or c:IsA("Texture") then c.Transparency = 1
			elseif c:IsA("SurfaceAppearance") then c:Destroy() end
		end
	end

	if inst:IsA("BasePart") then
		take(inst)
	else
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then take(d) end
		end
	end
end

-- A low bank of soil for a row of crops to be planted in. Built from a handful of overlapping
-- blocks with size and angle jitter rather than one long box, so the ridge reads as heaped
-- earth instead of a kerb.
--
-- It joins the growth set with its ORIGINAL colour recorded as rich wet soil while its current
-- colour is set to parched, so the flood darkens the bank as the water reaches it -- the same
-- mechanism that brings back the rest of the planting, no special case needed.
local function buildSoilBank(mcf, msz, alongX, len, wid, folder, patch)
	local bankW = math.clamp(wid * 0.95, 2.5, 9)
	local bankH = math.clamp(bankW * 0.24, 0.45, 1.4)
	local baseY = msz.Y * 0.5
	local made  = {}

	local function shade(c, d)
		return Color3.new(math.clamp(c.R + d, 0, 1), math.clamp(c.G + d, 0, 1), math.clamp(c.B + d, 0, 1))
	end

	local function soil(size, cf, rich, dry, sh, shape)
		local p = mk({ Material = Enum.Material.SmoothPlastic, Color = shade(dry, sh), Size = size, CFrame = cf })
		if shape then p.Shape = shape end
		p.Parent = folder
		if patch then
			orig[p] = { Color = shade(rich, sh), Material = p.Material, Size = p.Size, CFrame = p.CFrame }
			patch.seen[p] = true
		end
		table.insert(made, p)
		return p
	end

	-- The centreline MEANDERS. Two sine waves at different rates with random phase give a
	-- smooth wander; per-block random jitter just reads as noise, not as a row someone dug.
	local ph1, ph2 = math.random() * 6.28, math.random() * 6.28
	local amp = math.min(wid * 0.12, bankW * 0.20)
	local function drift(t)
		return (math.sin(t * 6.28 + ph1) * 0.62 + math.sin(t * 15.7 + ph2) * 0.38) * amp
	end

	-- ...and it TAPERS away at both ends rather than stopping at full height
	local function taper(t)
		return 0.42 + 0.58 * math.clamp(math.min(t, 1 - t) / 0.16, 0, 1)
	end

	local function place(size, along, lat, y, rich, dry, sh, shape)
		local cf = mcf * CFrame.new(alongX and along or lat, y, alongX and lat or along)
			* CFrame.Angles(math.rad(math.random(-5, 5)), math.rad(math.random(-9, 9)),
			                math.rad(math.random(-5, 5)))
		return soil(size, cf, rich, dry, sh, shape)
	end

	local n   = math.max(3, math.floor(len / 3.2))
	local seg = len / n
	for i = 1, n do
		local t     = (i - 0.5) / n
		local tp    = taper(t)
		local along = (t - 0.5) * len
		local lat   = drift(t)
		local w     = bankW * tp * (0.88 + math.random() * 0.24)
		local h     = bankH * tp * (0.85 + math.random() * 0.32)
		local sh    = (math.random() - 0.5) * 0.06

		-- Two tiers: a wide dark base with a narrower crown sat on it. That domes the
		-- cross-section, where a single block per segment leaves a flat-topped kerb.
		place(Vector3.new(alongX and seg * 1.12 or w * 1.15, h * 0.55, alongX and w * 1.15 or seg * 1.12),
			along, lat, baseY + h * 0.26, PAL.SOIL_DARK, PAL.SOIL_DARK_DRY, sh)
		place(Vector3.new(alongX and seg * 1.04 or w * 0.68, h * 0.62, alongX and w * 0.68 or seg * 1.04),
			along, lat + (math.random() - 0.5) * bankW * 0.10, baseY + h * 0.68, PAL.SOIL, PAL.SOIL_DRY, sh)
	end

	-- Loose clods spilled down the sides, half sunk into the ground. ANGULAR BLOCKS tipped on
	-- random axes, never spheres -- a smooth ball is the one thing here that would break the
	-- flat-shaded look. Tipped hard enough that you read corners rather than little boxes.
	for _ = 1, math.max(2, math.floor(len / 4)) do
		local t   = math.random()
		local sgn = (math.random() < 0.5) and -1 or 1
		local d   = math.random(16, 34) / 100 * bankW
		local lat = drift(t) + sgn * bankW * (0.45 + math.random() * 0.30)
		local cf  = mcf * CFrame.new(alongX and (t - 0.5) * len or lat, baseY + d * 0.24,
		                             alongX and lat or (t - 0.5) * len)
			* CFrame.Angles(math.rad(math.random(-32, 32)), math.rad(math.random(0, 90)),
			                math.rad(math.random(-32, 32)))
		soil(Vector3.new(d, d * 0.74, d * 0.88), cf, PAL.SOIL, PAL.SOIL_DRY, (math.random() - 0.5) * 0.05)
	end

	return bankH, made, drift
end

-- The crop marker itself becomes the SOIL BED the row is planted in: recoloured brown and left
-- VISIBLE rather than hidden, then dressed with scattered tilled patches and loose clods. The
-- dressing matters -- a bare recoloured block is still a rectangle, and some of the patches
-- deliberately overhang the edge so the outline is broken up.
--
-- Everything here joins the growth set the same way the bank does: original colour recorded as
-- rich wet soil, current colour parched, so the flood darkens it along with the rest.
local function soilifyMarker(inst, patch, folder)
	local made = {}
	local function shade(c, d)
		return Color3.new(math.clamp(c.R + d, 0, 1), math.clamp(c.G + d, 0, 1), math.clamp(c.B + d, 0, 1))
	end
	local function adopt(d, rich, dry)
		orig[d] = { Color = rich, Material = d.Material, Size = d.Size, CFrame = d.CFrame }
		if patch then patch.seen[d] = true end
		skipParts[d] = true          -- the wilt sweep must not reclaim or re-shrink it
		d.Color = dry
	end

	local function take(d)
		local o = orig[d]
		if o then d.Size, d.CFrame = o.Size, o.CFrame end     -- undo the wilt shrink first
		local cf, sz = d.CFrame, d.Size                       -- capture BEFORE hiding it

		-- The marker is a placement block and nothing else: hide it outright and drop it from
		-- the growth set. Decals, Textures and SurfaceAppearance all keep drawing on a fully
		-- transparent part, so those have to go too.
		if patch then patch.seen[d] = nil end
		orig[d]        = nil
		skipParts[d]   = true
		d.Transparency = 1
		d.CanCollide   = false
		d.CanQuery     = false
		d.CastShadow   = false
		for _, c in ipairs(d:GetChildren()) do
			if c:IsA("Decal") or c:IsA("Texture") then c.Transparency = 1
			elseif c:IsA("SurfaceAppearance") then c:Destroy() end
		end

		-- ...and the soil bed is built IN ITS PLACE, on the marker's own footprint and CFrame,
		-- so the planting lands exactly where you put the part.
		-- Give the bed real DEPTH, with its top left exactly on the marker's top face so the
		-- planting height doesn't move. A thin marker would otherwise give a wafer that only
		-- ever shows its top surface.
		local H    = math.max(1.1, sz.Y)
		local topY = sz.Y * 0.5                          -- the marker's top, in its own space
		local slab = mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.SOIL_DRY,
		                  Size = Vector3.new(sz.X, H, sz.Z),
		                  CFrame = cf * CFrame.new(0, topY - H * 0.5, 0), Parent = folder })
		adopt(slab, PAL.SOIL, PAL.SOIL_DRY)
		table.insert(made, slab)

		-- THE SIDES. A bare slab shows four clean cut faces, which reads as a box sunk in the
		-- lawn rather than heaped earth. Each edge gets its own course of soil blocks, tipped
		-- outward like the wall of a raised bed, with the usual size and tone jitter.
		local function sideWall(sgnX, sgnZ)
			local alongZ = sgnX ~= 0                     -- a wall on an X face runs along Z
			local len    = alongZ and sz.Z or sz.X

			-- TWO COURSES. A dense upper one right on the edge, and a lower one pushed further
			-- out and tipped harder, so the side steps down and spills outward instead of being
			-- one flat face of identical bricks.
			--
			-- STAYING LOW POLY: everything varies in DISCRETE STEPS, never continuously. Three
			-- flat tones, three block heights, three yaw angles. Continuous random shading and
			-- micro-rotation is what turns a flat-shaded bank into visual noise -- you stop
			-- reading facets and start reading fuzz.
			local TONE = { 0, -0.05, 0.05 }
			local YAW  = { -8, 0, 8 }
			local HI   = { 0.86, 1.00, 1.14 }
			local LO   = { 0.50, 0.62, 0.74 }

			for course = 1, 2 do
				local step  = (course == 1) and SOIL_SIDE_STEP or SOIL_SIDE_STEP * 1.75
				local m     = math.max(2, math.floor(len / step))
				local outer = (course == 1) and 0.5 or 0.66
				local drop  = (course == 1) and 0 or H * 0.36
				local tilt  = (course == 1) and 13 or 27
				local thick = (course == 1) and 0.62 or 0.74
				local steps = (course == 1) and HI or LO
				for i = 1, m do
					local t  = ((i - 0.5) / m - 0.5) * len
					local sh = TONE[(i + course) % 3 + 1]
					local h  = H * steps[(i * 2 + course) % 3 + 1]
					local yaw = math.rad(YAW[(i + 2 * course) % 3 + 1])
					local w  = (len / m) * 1.12
					local p = mk({
						Material = Enum.Material.SmoothPlastic, Color = shade(PAL.SOIL_DRY, sh),
						Size = alongZ and Vector3.new(thick, h, w) or Vector3.new(w, h, thick),
						CFrame = cf
							* CFrame.new(alongZ and (sgnX * sz.X * outer) or t,
							             topY - h * 0.5 + 0.06 - drop,
							             alongZ and t or (sgnZ * sz.Z * outer))
							* (alongZ and CFrame.Angles(0, yaw, math.rad(-sgnX * tilt))
							           or CFrame.Angles(math.rad(sgnZ * tilt), yaw, 0)),
						Parent = folder })
					adopt(p, shade(PAL.SOIL, sh), shade(PAL.SOIL_DRY, sh))
					table.insert(made, p)
				end
			end
		end
		sideWall(1, 0); sideWall(-1, 0); sideWall(0, 1); sideWall(0, -1)

		local n = math.clamp(math.floor((sz.X * sz.Z) / 40), 3, 9)
		for _ = 1, n do                                       -- tilled patches
			local sh = (math.random() - 0.5) * 0.07
			local w  = math.min(sz.X, sz.Z) * (0.22 + math.random() * 0.30)
			local p = mk({ Material = Enum.Material.SmoothPlastic, Color = shade(PAL.SOIL_DRY, sh),
			               Size = Vector3.new(w, sz.Y * 0.5 + 0.12, w * (0.6 + math.random() * 0.7)),
			               CFrame = cf * CFrame.new((math.random() - 0.5) * sz.X * 1.06,
			                        sz.Y * 0.5, (math.random() - 0.5) * sz.Z * 1.06)
			                   * CFrame.Angles(0, math.random() * 6.28, 0), Parent = folder })
			adopt(p, shade(PAL.SOIL, sh), shade(PAL.SOIL_DRY, sh))
			table.insert(made, p)
		end
		-- a few flat stones turned up in the bed, in three fixed tones
		local PEB = { PAL.STONE_D, PAL.STONE, PAL.SOIL_DARK }
		for i = 1, math.max(2, math.floor(n / 2)) do
			local c = math.min(sz.X, sz.Z) * (0.05 + math.random() * 0.05)
			local p = mk({ Material = Enum.Material.SmoothPlastic, Color = PEB[i % 3 + 1],
			               Size = Vector3.new(c * 1.6, c * 0.45, c * 1.2),
			               CFrame = cf * CFrame.new((math.random() - 0.5) * sz.X * 0.94,
			                        sz.Y * 0.5 + 0.04, (math.random() - 0.5) * sz.Z * 0.94)
			                   * CFrame.Angles(0, math.random() * 6.28, 0), Parent = folder })
			adopt(p, PEB[i % 3 + 1], PEB[i % 3 + 1])
			table.insert(made, p)
		end
		for _ = 1, math.max(2, math.floor(n / 3)) do          -- loose clods, tipped on their corners
			local sh = (math.random() - 0.5) * 0.06
			local c  = math.min(sz.X, sz.Z) * (0.07 + math.random() * 0.08)
			local p = mk({ Material = Enum.Material.SmoothPlastic,
			               Color = shade(PAL.SOIL_DARK_DRY, sh),
			               Size = Vector3.new(c, c * 0.8, c * 0.9),
			               CFrame = cf * CFrame.new((math.random() - 0.5) * sz.X * 1.1,
			                        sz.Y * 0.5 + c * 0.25, (math.random() - 0.5) * sz.Z * 1.1)
			                   * CFrame.Angles(math.rad(math.random(-30, 30)), math.random() * 6.28,
			                                   math.rad(math.random(-30, 30))), Parent = folder })
			adopt(p, shade(PAL.SOIL_DARK, sh), shade(PAL.SOIL_DARK_DRY, sh))
			table.insert(made, p)
		end
	end

	if inst:IsA("BasePart") then
		take(inst)
	else
		for _, d in ipairs(inst:GetDescendants()) do if d:IsA("BasePart") then take(d) end end
	end
	return made
end

local function isCropMarker(inst, key)
	return (inst:IsA("BasePart") or inst:IsA("Model"))
		and string.find(norm(inst.Name), key, 1, true) ~= nil
end

-- Claim one marker and build a ROW of plants along its longest side. Returns the plant count,
-- or 0 if this marker was already handled or sits inside one that was.
local function plantCropMarker(g, m)
	g.cropDone = g.cropDone or {}
	if g.cropDone[m] then return 0 end
	-- skip anything inside a marker already taken, so a Model called BubbleCrop2 whose parts
	-- are also called BubbleCrop doesn't get planted twice over
	local cur = m.Parent
	while cur and cur ~= g.mark do
		if g.cropDone[cur] then return 0 end
		cur = cur.Parent
	end
	g.cropDone[m] = true

	g.crops, g.planted = g.crops or {}, g.planted or 0
	if g.planted >= CROP_MAX then return 0 end

	local mcf, msz = markerFrame(m)
	-- the marker becomes the visible soil bed rather than being hidden
	local bedParts = soilifyMarker(m, g.patch, g.folder)
	if g.bloomed then
		for _, bp in ipairs(bedParts) do restorePart(bp, 0) end
	end

	-- Plants spread along the marker's LONGEST horizontal side, so a long bed gets a row
	-- rather than one lonely plant in the middle. Spacing is fixed, so the count follows the
	-- marker's real length.
	local alongX = msz.X >= msz.Z
	local len    = alongX and msz.X or msz.Z
	local wid    = alongX and msz.Z or msz.X
	local n      = math.clamp(math.floor(len / CROP_SPACING), 1, 12)
	local s      = math.clamp(math.max(1.2, math.min(wid, len / n)) / 1.7, 0.8, 3.0) * CROP_SCALE

	-- heap the soil first; the crops are then planted standing IN it rather than on bare grass
	local bankH, bankParts, bankDrift = buildSoilBank(mcf, msz, alongX, len, wid, g.folder, g.patch)
	if g.bloomed then
		for _, bp in ipairs(bankParts) do restorePart(bp, 0) end
	end

	local made = 0
	for k = 1, n do
		if g.planted >= CROP_MAX then break end
		local t     = (k - 0.5) / n
		local along = (t - 0.5) * len + (math.random() - 0.5) * (len / n) * 0.3
		-- follow the bank's OWN meander, then scatter only slightly around it. Scattering
		-- across the marker's full width would leave crops stranded off the ridge wherever
		-- the bank wanders away from the centreline.
		local side  = bankDrift(t) + (math.random() - 0.5) * math.min(wid * 0.18, bankH * 1.6)
		local root  = mcf
			* CFrame.new(alongX and along or side, msz.Y * 0.5 + bankH * 0.78, alongX and side or along)
			* CFrame.Angles(0, math.random() * 6.28, 0)
		local cparts, cfruit = buildCrop(root, s * (0.85 + math.random() * 0.3), g.folder)
		if cfruit then
			-- keep the WHOLE plant, not just its fruit: when this one ripens the entire plant
			-- pulses, and that needs every part plus the root they're all measured against
			g.cropPlants = g.cropPlants or {}
			table.insert(g.cropPlants, { fruit = cfruit, parts = cparts, root = root })
		end
		for _, part in ipairs(cparts) do
			registerCrop(part, root, g.patch)
			-- a marker that only streamed in AFTER this garden was watered would otherwise sit
			-- there as a permanent seedling, so it grows straight away instead
			if g.bloomed then restorePart(part, 0.6) end
			table.insert(g.crops, part)
		end
		g.planted += 1
		made += 1
	end
	return made
end

local function prepGarden(g, idx)
	g.groundY = groundYAt(g.pos)

	local parts = 0
	if g.mark then
		for _, d in ipairs(g.mark:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
				if parts >= 4 then break end
			end
		end
	end

	if parts >= 4 then
		g.folder = Instance.new("Folder"); g.folder.Name = "Garden" .. idx; g.folder.Parent = park
		g.patch  = wilt(g.mark, gardenColour, "garden " .. idx, true)   -- true = shrink the planting

		-- Measure the REAL planted area from the parts themselves. The model's bounding box is
		-- far larger than the planting and overlaps its neighbours and the fountain, so it's
		-- useless for deciding where to put water.
		local minX, maxX, minZ, maxZ, n = math.huge, -math.huge, math.huge, -math.huge, 0
		for p in pairs(g.patch.seen) do
			local q = p.Position
			minX = math.min(minX, q.X); maxX = math.max(maxX, q.X)
			minZ = math.min(minZ, q.Z); maxZ = math.max(maxZ, q.Z)
			n += 1
		end
		if n > 0 and maxX > minX and maxZ > minZ then
			g.bounds = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ, y = g.groundY }
			print(("[Park] garden %d planting spans %.0f x %.0f studs"):format(idx, maxX - minX, maxZ - minZ))
		end

		-- The garden's OWN part named "water" is the bed the water fills. It's pulled out of
		-- the wilt set and handled separately: it must never shrink, and it turns blue on its
		-- own slow timing rather than snapping back with the planting.
		--
		-- Transparency and Reflectance are captured HERE rather than in recolourPart, which
		-- only ever touches Colour and Material -- so the values still read as the originals.
		g.waterParts = {}
		for _, d in ipairs(g.mark:GetDescendants()) do
			if d:IsA("BasePart") and string.sub(norm(d.Name), 1, 5) == "water" then
				table.insert(g.waterParts, d)
				g.patch.seen[d] = nil
				skipParts[d]    = true
				local o = orig[d]
				if o then
					o.Transparency = d.Transparency
					o.Reflectance  = d.Reflectance
				end
				d.Color       = PAL.DRY_BED                -- an empty, cracked bed
				d.Material    = Enum.Material.Slate
				d.Reflectance = 0
			end
		end
		if #g.waterParts > 0 then
			print(("[Park] garden %d has %d 'water' part(s) -- those fill instead of laid pools"):format(idx, #g.waterParts))
		end

		-- --- CROP SPOTS. Markers can be Parts or Models; each gets a row of plants and is hidden.
		local key
		for _, pass in ipairs({ CROP_NAME, CROP_FALLBACK }) do
			for _, d in ipairs(g.mark:GetDescendants()) do
				if isCropMarker(d, pass) then key = pass; break end
			end
			if key then break end               -- only fall back if the real name found nothing
		end

		g.crops, g.planted, g.cropDone, g.cropKey = {}, 0, {}, key
		if key then
			-- GetDescendants lists parents before children, so a matching Model is always
			-- claimed before its matching parts and they get skipped as nested.
			local markers = 0
			for _, d in ipairs(g.mark:GetDescendants()) do
				if isCropMarker(d, key) and plantCropMarker(g, d) > 0 then markers += 1 end
			end
			print(("[Park] garden %d -- %d crop marker(s) -> %d plant(s), %d part(s)")
				:format(idx, markers, g.planted, #g.crops))
			if g.planted >= CROP_MAX then
				warn(("[Park] garden %d hit the %d-plant cap -- raise CROP_MAX for more"):format(idx, CROP_MAX))
			end

			-- StreamingEnabled hands the far side of a big plot over as you walk into it, so
			-- crop markers KEEP ARRIVING after this first pass. Without watching for them, the
			-- ones at the far end are never claimed and sit there visible -- which is exactly
			-- what was left showing in garden 3, the largest of the three.
			g.mark.DescendantAdded:Connect(function(d)
				if isCropMarker(d, key) then task.defer(plantCropMarker, g, d) end
			end)
			task.spawn(function()
				for _ = 1, 60 do                -- keep checking for ~3 minutes
					task.wait(3)
					if not g.mark.Parent then break end
					local late = 0
					for _, d in ipairs(g.mark:GetDescendants()) do
						if isCropMarker(d, key) and plantCropMarker(g, d) > 0 then late += 1 end
					end
					if late > 0 then
						print(("[Park] garden %d -- %d crop marker(s) streamed in late, planted"):format(idx, late))
					end
				end
			end)
		else
			warn(("[Park] garden %d has no '%s' parts -- no crops planted"):format(idx, CROP_NAME))
		end
	elseif g.mark then
		-- NO PROCEDURAL BED any more. Every garden is your own art, so a plot that looks empty
		-- here has simply not streamed in yet -- wait for it rather than dropping a stand-in
		-- rectangle that would never match the other two.
		warn(("[Park] garden %d hasn't streamed in yet -- waiting for its parts"):format(idx))
		task.spawn(function()
			for _ = 1, 60 do
				task.wait(2)
				if not g.mark.Parent then return end
				local n = 0
				for _, d in ipairs(g.mark:GetDescendants()) do
					if d:IsA("BasePart") then n += 1; if n >= 4 then break end end
				end
				if n >= 4 then
					print(("[Park] garden %d streamed in -- preparing it now"):format(idx))
					prepGarden(g, idx)
					return
				end
			end
			warn(("[Park] garden %d never streamed in"):format(idx))
		end)
	else
		warn(("[Park] garden %d has no marker at all -- nothing to prepare"):format(idx))
	end
end

local function spawnButterflies(g, count)
	for i = 1, count do
		local body = mk({ Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(60, 48, 40),
		                  Size = Vector3.new(0.18, 0.18, 0.6), Parent = g.folder })
		local col = PETALS[math.random(1, #PETALS)]
		local wl = mk({ Material = Enum.Material.Neon, Color = col, Size = Vector3.new(0.7, 0.06, 0.5), Parent = g.folder })
		local wr = mk({ Material = Enum.Material.Neon, Color = col, Size = Vector3.new(0.7, 0.06, 0.5), Parent = g.folder })
		table.insert(butterflies, {
			body = body, wl = wl, wr = wr,
			center = g.pos, radius = g.size * (0.22 + math.random() * 0.28),
			height = g.groundY + 2.5 + math.random() * 3.5,
			phase = math.random() * 6.28, speed = 0.5 + math.random() * 0.5,
			bob = 0.8 + math.random() * 0.8,
		})
	end
end

-- a puff of pollen over the whole plot
local function pollenBurst(g)
	local host = mk({ Transparency = 1, Size = Vector3.new(1, 1, 1),
	                  CFrame = CFrame.new(g.pos.X, (g.groundY or g.pos.Y) + 3, g.pos.Z), Parent = g.folder })
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(Color3.fromRGB(252, 232, 150), Color3.fromRGB(190, 246, 170))
	em.Lifetime = NumberRange.new(1.2, 2.2); em.Rate = 0
	em.Speed = NumberRange.new(6, 20); em.SpreadAngle = Vector2.new(180, 180)
	em.Size = NumberSequence.new(math.max(0.8, g.size * 0.06))
	em.Acceleration = Vector3.new(0, -2, 0); em.LightEmission = 0.5
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	em.Parent = host; em:Emit(120)
	Debris:AddItem(host, 3)
end

-- A crop marker does NOT have to be parented inside a garden model. Anything named like a
-- crop that sits loose on the island is adopted by whichever garden it stands nearest, so a
-- marker dropped beside a plot rather than into it still gets planted and hidden.
local function adoptStrayCrops()
	local key
	for _, g in ipairs(gardens) do if g.cropKey then key = g.cropKey; break end end
	key = key or CROP_NAME

	local found = 0
	for _, d in ipairs((island or Workspace):GetDescendants()) do
		if isCropMarker(d, key) then
			local taken = false
			for _, g in ipairs(gardens) do
				if g.cropDone and g.cropDone[d] then taken = true; break end
			end
			if not taken then
				local at = d:IsA("BasePart") and d.Position or d:GetPivot().Position
				local best, bestD
				for _, g in ipairs(gardens) do
					-- only gardens that actually have a planting patch to add to
					if g.patch and g.folder then
						local m = ((at - g.pos) * Vector3.new(1, 0, 1)).Magnitude
						if not bestD or m < bestD then bestD, best = m, g end
					end
				end
				if best and plantCropMarker(best, d) > 0 then found += 1 end
			end
		end
	end
	if found > 0 then
		print(("[Park] adopted %d loose crop marker(s) into the nearest garden"):format(found))
	end
	return found
end

-- ============================================================================
-- FLOODING A GARDEN
-- ============================================================================
-- The water leaves the GATE and spreads out across the garden as a WAVEFRONT: the near corner
-- fills first, the far ones last, and every plant grows the moment the water reaches it. After
-- it has stood a while it drains away in the same order it arrived, leaving the bed its own
-- natural dirt colour again.
--
-- The bed is covered in TILES rather than filled along one axis. A single stretching part can
-- only ever run in a straight line, so it can never reach into a corner or follow a bed that
-- bends; tiles let the water spread in whatever shape the bed actually is.

local WATER_TILES = 260        -- hard cap on tiles per bed

-- Lay tiles over one water bed. THE BED IS THE BOUNDARY: water may never appear anywhere the
-- bed isn't, so every cell is tested against the bed itself with an INCLUDE raycast.
--
-- Each cell is probed at its CENTRE AND FOUR CORNERS, not just the centre. A cell that only
-- partly covers the bed is placed at the average of the corners that actually hit and shrunk,
-- so it is pulled inside the edge instead of hanging over it. Centre-only testing plus the
-- old 5% oversize was exactly how water ended up spilling past the lip.
local function tilesFor(p)
	local out  = {}
	local sz   = p.Size
	local cell = math.clamp(math.max(sz.X, sz.Z) / 14, 2, 8)   -- finer cells = a tighter edge
	local cols = math.max(1, math.floor(sz.X / cell))
	local rows = math.max(1, math.floor(sz.Z / cell))
	while cols * rows > WATER_TILES and (cols > 1 or rows > 1) do
		if cols >= rows then cols -= 1 else rows -= 1 end
	end
	local cx, cz = sz.X / cols, sz.Z / rows

	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { p }

	local up   = p.CFrame.UpVector
	local rot  = p.CFrame - p.CFrame.Position     -- rotation only, so tiles lie with the bed
	local topY = sz.Y * 0.5 + 6
	local drop = -up * (sz.Y + 14)
	local probes = { {0, 0}, {-0.5, -0.5}, {0.5, -0.5}, {-0.5, 0.5}, {0.5, 0.5} }

	local done = 0
	for i = 1, cols do
		for j = 1, rows do
			local ox, oz = -sz.X * 0.5 + (i - 0.5) * cx, -sz.Z * 0.5 + (j - 0.5) * cz
			local hits, sum = 0, Vector3.zero
			for _, q in ipairs(probes) do
				local from = p.CFrame * Vector3.new(ox + q[1] * cx * 0.94, topY, oz + q[2] * cz * 0.94)
				local h = Workspace:Raycast(from, drop, rp)
				if h then hits += 1; sum += h.Position end
			end
			if hits > 0 then
				local k = (hits == #probes) and 1.0 or 0.55   -- partly covered -> pull it in
				table.insert(out, {
					cf   = CFrame.new((sum / hits) + up * 0.07) * rot,
					size = Vector3.new(cx * k, 0.12, cz * k),
				})
			end
			done += 1
			if done % 140 == 0 then task.wait() end     -- spread the ray work over a few frames
		end
	end
	return out
end

local function floodGarden(g)
	local patch = g.patch
	if not patch then return end
	patch.dead = false

	-- everything is measured from the GATE: that is where the water comes from, so that is
	-- what decides the order the garden fills in
	local src = g.gatePos or g.channelFrom or center
	local function distFrom(v)
		return (Vector3.new(v.X, 0, v.Z) - Vector3.new(src.X, 0, src.Z)).Magnitude
	end

	-- plants, nearest the gate first
	local plants = {}
	for q in pairs(patch.seen) do
		if q.Parent then table.insert(plants, { p = q, d = distFrom(q.Position) }) end
	end
	table.sort(plants, function(a, b) return a.d < b.d end)

	-- water tiles: over the garden's own beds if it has any, otherwise over the ground
	local tiles = {}
	if g.waterParts and #g.waterParts > 0 then
		for _, bed in ipairs(g.waterParts) do
			for _, t in ipairs(tilesFor(bed)) do
				table.insert(tiles, t)
			end
		end
	elseif g.bounds then
		local b = g.bounds
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { park, g.mark, player.Character }
		local cx = (b.maxX - b.minX) / FLOOD_GRID
		local cz = (b.maxZ - b.minZ) / FLOOD_GRID
		for i = 1, FLOOD_GRID do
			for j = 1, FLOOD_GRID do
				local x   = b.minX + (i - 0.5) * cx
				local z   = b.minZ + (j - 0.5) * cz
				local hit = Workspace:Raycast(Vector3.new(x, b.y + 50, z), Vector3.new(0, -140, 0), rp)
				table.insert(tiles, {
					cf   = CFrame.new(x, (hit and hit.Position.Y or b.y) + 0.12, z),
					size = Vector3.new(cx * 1.05, 0.12, cz * 1.05),
				})
			end
		end
	end

	-- A little NOISE on each tile's arrival distance. Without it the advancing edge is a
	-- perfect circle, which reads as a screen wipe; roughened, it reads as water finding its way.
	for _, t in ipairs(tiles) do
		t.d = distFrom(t.cf.Position) + (math.random() - 0.5) * math.max(t.size.X, t.size.Z) * 1.5
	end
	table.sort(tiles, function(a, b) return a.d < b.d end)

	local far = 1
	for _, t in ipairs(tiles)  do far = math.max(far, t.d) end
	for _, q in ipairs(plants) do far = math.max(far, q.d) end

	-- water bubbling out of the gate the whole time it is running
	local mouth = splashAt(src + Vector3.new(0, 1.2, 0), g.folder)
	mouth.Rate = 20

	local live, flowing = {}, true

	local function wet(t)
		local w = mk({
			Material = Enum.Material.SmoothPlastic, Color = PAL.WATER_G, Reflectance = 0.26,
			Transparency = 1, Size = t.size, CFrame = t.cf, Parent = g.folder })
		-- arrives BRIGHT and settles to the still colour a moment later, so the advancing
		-- edge glows and the water behind it calms down
		tween(w, 0.55, { Transparency = 0.16 })
		tween(w, 1.6, { Color = PAL.WATER_L })
		local entry = { part = w, ready = false }
		table.insert(live, entry)
		task.delay(0.7, function() entry.ready = true end)
	end

	task.spawn(function()
		local STEPS, ti, pi = 90, 1, 1
		for s = 1, STEPS do
			local r = (s / STEPS) * far * 1.04
			while ti <= #tiles  and tiles[ti].d  <= r do wet(tiles[ti]); ti += 1 end
			while pi <= #plants and plants[pi].d <= r do restorePart(plants[pi].p, 1.1); pi += 1 end
			task.wait(FLOOD_TIME / STEPS)
		end
		while ti <= #tiles  do wet(tiles[ti]); ti += 1 end
		while pi <= #plants do restorePart(plants[pi].p, 1.1); pi += 1 end
		print(("[Park] garden %d watered -- %d tile(s), %d plant(s) grown"):format(g.index, #tiles, #plants))

		-- ---- THE WATER STAYS. Once a gate is open its garden is irrigated for good: the flow
		-- settles from a gush to a steady trickle rather than draining away, so a restored plot
		-- still looks alive when you walk back to it later. `flowing` is never cleared, which
		-- keeps the surface shimmer below running for the rest of the session.
		task.wait(HOLD_TIME)
		mouth.Rate = 7
		print(("[Park] garden %d is irrigated for good"):format(g.index))
	end)

	-- ripples travelling across whatever water is currently down. The phase runs off the tile
	-- index, so the shimmer crosses the surface instead of every tile pulsing together.
	task.spawn(function()
		local t = 0
		while flowing do
			t += 0.06
			for i, e in ipairs(live) do
				if e.ready and e.part.Parent then
					e.part.Transparency = 0.16 + 0.06 * math.sin(t * 2.4 + i * 0.55)
				end
			end
			task.wait(0.06)
		end
	end)
end


local function bloomGarden(g)
	if g.bloomed then return end
	g.bloomed = true
	playSound(SOUND_BLOOM, 0.6)

	-- The water surfaces in the plot and grows the planting as it spreads.
	if not g.patch then
		warn(("[Park] garden %d has nothing to bloom"):format(g.index))
		return
	end
	floodGarden(g)
	task.delay(FLOOD_TIME * 0.45, function() pollenBurst(g) end)
	task.delay(FLOOD_TIME * 0.7,  function() spawnButterflies(g, 6) end)
	-- ripen AFTER the flood has finished growing everything: a crop still mid-growth would have
	-- its growth tween fighting the ripening swell
	task.delay(FLOOD_TIME + 1.0, function() ripenGarden(g) end)
end

-- ============================================================================
-- HARVEST -- picking ripe crops and offering them to the tree
-- ============================================================================
-- Once a garden has been watered, a handful of its crops RIPEN. You pick those, carry an
-- armful, and lay them at the Ancient Tree's roots. The tree only wakes once it has been given
-- produce from all three gardens -- so the finale is something you did, not a counter hitting 3.
--
-- Only the ripe ones get a ProximityPrompt. A garden holds ~1000 crop parts; prompting every
-- one would put hundreds of prompts in competition for the same keypress.

local ripeBits = {}          -- ripe fruit, all pulsing on one shared loop
local carried  = {}          -- held: { model =, garden =, colour =, size =, shape = }
local pileAt                 -- where offerings stack
local offerPrompt

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for i = #ripeBits, 1, -1 do
		local r = ripeBits[i]
		if not r.part.Parent then
			-- picked: take the arrow with it, and settle the rest of that plant back to its
			-- resting size and position -- otherwise it's left frozen at whatever point of the
			-- pulse it happened to be caught at
			if r.arrow and r.arrow.Parent then r.arrow:Destroy() end
			if r.parts then
				for _, e in ipairs(r.parts) do
					if e.p.Parent then
						e.p.Size   = e.size
						e.p.CFrame = r.root * (CFrame.new(e.pos) * e.rot)
					end
				end
			end
			table.remove(ripeBits, i)
		else
			-- The WHOLE PLANT is the signal: every part swells and shrinks together about the
			-- plant's base, the plant sways, the glow rides the same pulse, and an arrow bobs
			-- and turns overhead.
			local pulse = math.sin(t * 3.0 + r.phase)
			if r.parts then
				local k    = 1 + pulse * 0.20                 -- a real swell, not a shimmer
				local sway = CFrame.Angles(0, math.sin(t * 0.9 + r.phase) * 0.12, 0)
				for _, e in ipairs(r.parts) do
					if e.p.Parent then
						e.p.Size   = e.size * k
						e.p.CFrame = r.root * sway * (CFrame.new(e.pos * k) * e.rot)
					end
				end
			end
			if r.glow and r.glow.Parent then
				r.glow.Brightness = 1.9 + pulse * 1.9
			end
			if r.arrow and r.arrow.PrimaryPart then
				r.arrow:PivotTo(r.root
					* CFrame.new(0, r.arrowY + math.sin(t * 2.2 + r.phase) * 0.22, 0)
					* CFrame.Angles(0, t * 1.3 + r.phase, 0))
			end
		end
	end

	-- the armful rides in front of you
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		for i, c in ipairs(carried) do
			local off = (i - (#carried + 1) * 0.5) * 0.95
			if c.model.PrimaryPart then
				c.model:PivotTo(hrp.CFrame * CFrame.new(off, 0.55 + (i % 2) * 0.34, -1.8)
					* CFrame.Angles(math.rad(14), off * 0.7, math.rad(off * 8)))
			end
		end
	end
end)

local function offeredTotal()
	local n = 0
	for _, g in ipairs(gardens) do n += math.min(g.offered or 0, OFFER_PER_GARDEN) end
	return n
end

local function allOffered()
	for _, g in ipairs(gardens) do
		if (g.offered or 0) < OFFER_PER_GARDEN then return false end
	end
	return true
end

-- A picked crop as an actual piece of produce rather than one bare sphere: the fruit itself,
-- a cut stalk, and a pair of leaves. Used for BOTH what you carry and what ends up in the
-- Keeper's basket, so the two always match.
local function buildProduce(colour, size, shape, parent)
	local m = Instance.new("Model"); m.Name = "Produce"; m.Parent = parent
	-- deliberately small: this sits in your hands and three of them ride side by side, so a
	-- big one blocks the view of the garden you're walking through
	local d = math.clamp(math.max(size.X, size.Y, size.Z) * 0.8, 0.55, 1.15)

	local body = mk({ Material = Enum.Material.SmoothPlastic, Color = colour,
	                  Size = Vector3.new(d, d * 0.9, d), CFrame = CFrame.new(), Parent = m })
	if shape then body.Shape = shape end

	-- a darker collar where the stalk meets the fruit, so the two don't just abut
	mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.CROP_LEAF2,
	     Size = Vector3.new(d * 0.42, d * 0.13, d * 0.42),
	     CFrame = CFrame.new(0, d * 0.44, 0), Parent = m })
	-- short cut stalk, leaning slightly: a dead-straight one looks manufactured
	mk({ Material = Enum.Material.SmoothPlastic, Color = PAL.WOOD_D,
	     Size = Vector3.new(d * 0.12, d * 0.34, d * 0.12),
	     CFrame = CFrame.new(0, d * 0.63, 0) * CFrame.Angles(0, 0, math.rad(9)), Parent = m })
	-- two leaves, different greens and different angles
	for _, sgn in ipairs({ -1, 1 }) do
		mk({ Material = Enum.Material.SmoothPlastic,
		     Color = (sgn == 1) and PAL.CROP_LEAF or PAL.CROP_LEAF2,
		     Size = Vector3.new(d * 0.5, d * 0.08, d * 0.24),
		     CFrame = CFrame.new(sgn * d * 0.24, d * 0.7, 0)
		         * CFrame.Angles(0, sgn * 0.35, math.rad(sgn * -30)), Parent = m })
	end

	m.PrimaryPart = body
	m.WorldPivot  = CFrame.new()
	return m
end

local function pickFruit(g, fruit)
	if #carried >= CARRY_MAX then return false end
	local col, sz, shp = fruit.Color, fruit.Size, fruit.Shape
	fruit:Destroy()                                  -- taken off the plant for good

	local m = buildProduce(col, sz, shp, park)
	table.insert(carried, { model = m, garden = g.index, colour = col, size = sz, shape = shp })
	if offerPrompt then offerPrompt.Enabled = true end
	if refreshBanner then refreshBanner() end
	return true
end

function ripenGarden(g)
	if g.ripened then return end
	g.ripened = true
	g.offered = g.offered or 0

	local pool = g.cropPlants or {}
	if #pool == 0 then
		-- nothing pickable here, so credit the quota rather than letting the quest dead-end
		g.offered = OFFER_PER_GARDEN
		warn(("[Park] garden %d has no pickable crops -- its offerings are credited automatically"):format(g.index))
		if refreshBanner then refreshBanner() end
		return
	end

	-- shuffle, then take the first RIPE_PER_GARDEN that are still standing
	for i = #pool, 2, -1 do
		local j = math.random(i)
		pool[i], pool[j] = pool[j], pool[i]
	end

	local ripe = 0
	for _, plant in ipairs(pool) do
		if ripe >= RIPE_PER_GARDEN then break end
		local fruit = plant.fruit
		if fruit and fruit.Parent then
			ripe += 1
			local o = orig[fruit]
			local full = (o and o.Size or fruit.Size) * 1.45
			skipParts[fruit] = true            -- the wilt sweep must not reclaim a ripe fruit
			tween(fruit, 0.8, { Size = full }, Enum.EasingStyle.Back)

			local glow = Instance.new("PointLight")
			glow.Color = fruit.Color; glow.Brightness = 1.6; glow.Range = 9; glow.Parent = fruit

			local bit = { part = fruit, phase = math.random() * 6.28, glow = glow }
			table.insert(ripeBits, bit)

			-- Capture the pulse baseline only AFTER the ripening swell has finished, so the
			-- recorded sizes already include it and the two never fight. Each part is stored
			-- relative to the plant's ROOT, so the whole thing can be scaled about its base --
			-- scaling each part about its own centre would pull the plant apart.
			task.delay(0.9, function()
				local list, topY = {}, 0
				for _, q in ipairs(plant.parts) do
					if q.Parent then
						local rel = plant.root:ToObjectSpace(q.CFrame)
						table.insert(list, { p = q, size = q.Size,
						                     pos = rel.Position, rot = rel - rel.Position })
						topY = math.max(topY, rel.Position.Y + q.Size.Y * 0.5)
					end
				end
				bit.root, bit.parts = plant.root, list

				-- A small arrow hanging over the plant, pointing down at it. Built as a shaft
				-- and two chevron arms -- all blocks, so it stays flat-shaded -- with its point
				-- at the model's origin, which is what PivotTo aims each frame.
				local as    = math.clamp(topY * 0.55, 0.5, 1.5)
				local arrow = Instance.new("Model"); arrow.Name = "PickArrow"; arrow.Parent = park
				local gold  = Color3.fromRGB(255, 214, 92)
				local shaft = mk({ Material = Enum.Material.Neon, Color = gold,
				                   Size = Vector3.new(0.22, 0.85, 0.22) * as,
				                   CFrame = CFrame.new(0, 0.78 * as, 0), Parent = arrow })
				for _, sgn in ipairs({ -1, 1 }) do
					mk({ Material = Enum.Material.Neon, Color = gold,
					     Size = Vector3.new(0.22, 0.62, 0.22) * as,
					     CFrame = CFrame.new(sgn * 0.17 * as, 0.25 * as, 0)
					         * CFrame.Angles(0, 0, math.rad(-sgn * 36)), Parent = arrow })
				end
				arrow.PrimaryPart = shaft
				arrow.WorldPivot  = CFrame.new()
				bit.arrow  = arrow
				bit.arrowY = topY + 0.9 * as
			end)

			fruit.CanQuery = true
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "PickPrompt"
			prompt.ActionText = "Pick"
			prompt.ObjectText = "Ripe Crop"
			prompt.HoldDuration = 0.25
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = fruit
			prompt.Triggered:Connect(function(plr)
				if plr ~= player then return end
				if #carried >= CARRY_MAX then
					if refreshBanner then refreshBanner() end
					return
				end
				prompt.Enabled = false
				-- ONE TAP, WIDE BAND. You do this a dozen times a garden, so it has to stay a
				-- beat rather than a task -- the couplings are the hard version of this widget.
				if playWrench({ strokes = 1, speed = 1.15, zone = 0.3,
					title = "PICK IT CLEAN", hint = "Tap on the green to take it without bruising" })
				then
					pickFruit(g, fruit)
				else
					prompt.Enabled = true
				end
			end)
		end
	end
	print(("[Park] garden %d -- %d crop(s) ripened, needs %d offering(s)")
		:format(g.index, ripe, OFFER_PER_GARDEN))
	if refreshBanner then refreshBanner() end
end

-- The GROVE KEEPER: the person you hand the harvest to. They stand on the part you named
-- "offering" (that part is only a placement block, so it gets hidden), facing back toward the
-- fountain so you walk up to them head-on. If no marker exists they fall back to the tree's roots.
local altarBusy = false
local function buildOfferAltar()
	if pileAt or altarBusy then return end
	altarBusy = true

	task.spawn(function()
		-- the marker streams in like everything else, so poll rather than deciding on one look
		local mark = pollFor(function() return findMarker(OFFER_NAME, island) end, 30)
		local at

		if mark then
			local mcf, msz = markerFrame(mark)
			at = Vector3.new(mcf.Position.X, mcf.Position.Y + msz.Y * 0.5, mcf.Position.Z)
			-- claimMarker rather than hideMarker: it also blanks any Decal/Texture and drops a
			-- SurfaceAppearance, which keep drawing on a fully transparent part
			claimMarker(mark, nil)
			print(("[Park] Grove Keeper standing on your 'offering' marker (%.0f, %.0f, %.0f)")
				:format(at.X, at.Y, at.Z))
		elseif tree then
			local bcf, bsz = tree:GetBoundingBox()
			local out = (Vector3.new(center.X, 0, center.Z) - Vector3.new(bcf.Position.X, 0, bcf.Position.Z))
			out = (out.Magnitude > 1) and out.Unit or Vector3.new(0, 0, 1)
			at = Vector3.new(bcf.Position.X, groundYAt(bcf.Position), bcf.Position.Z)
				+ out * (math.max(bsz.X, bsz.Z) * 0.16 + 7)
			warn("[Park] no part named 'offering' -- the Keeper stands at the tree's roots instead")
		else
			altarBusy = false
			return
		end

		local toF  = (Vector3.new(center.X, 0, center.Z) - Vector3.new(at.X, 0, at.Z))
		local dir  = (toF.Magnitude > 1) and toF.Unit or Vector3.new(0, 0, 1)
		local base = CFrame.new(at, at + dir)
		pileAt = at

		local folder = Instance.new("Folder"); folder.Name = "GroveKeeper"; folder.Parent = park
		local function piece(col, size, cf)
			return mk({ Material = Enum.Material.SmoothPlastic, Color = col, Size = size,
			            CFrame = cf, CastShadow = true, Parent = folder })
		end

		local SKIN  = Color3.fromRGB(226, 178, 132)
		local SMOCK = Color3.fromRGB(104, 150, 92)
		local TROUS = Color3.fromRGB(96, 82, 64)
		local STRAW = Color3.fromRGB(228, 194, 114)
		local DARK  = Color3.fromRGB(74, 60, 48)

		local APRON = Color3.fromRGB(198, 178, 142)
		local KERCH = Color3.fromRGB(206, 96, 88)
		local LEATH = Color3.fromRGB(150, 116, 74)

		-- blocky low-poly gardener, built standing ON the marker (feet at y = 0)
		local arms = {}
		for _, s in ipairs({ -1, 1 }) do
			piece(TROUS, Vector3.new(0.52, 1.42, 0.60), base * CFrame.new(s * 0.32, 0.78, 0))
			piece(DARK,  Vector3.new(0.60, 0.30, 0.92), base * CFrame.new(s * 0.32, 0.15, -0.14))
			piece(LEATH, Vector3.new(0.62, 0.12, 0.66), base * CFrame.new(s * 0.32, 0.30, -0.02))
			-- sleeve, then a bare forearm, so the arm isn't one flat colour end to end
			piece(SMOCK, Vector3.new(0.42, 0.66, 0.46),
				base * CFrame.new(s * 0.88, 2.38, 0) * CFrame.Angles(0, 0, math.rad(s * 7)))
			local fore = piece(SKIN, Vector3.new(0.36, 0.72, 0.40),
				base * CFrame.new(s * 0.94, 1.74, 0) * CFrame.Angles(0, 0, math.rad(s * 4)))
			piece(SKIN,  Vector3.new(0.42, 0.36, 0.46), base * CFrame.new(s * 0.97, 1.33, 0))
			table.insert(arms, { part = fore, side = s, home = fore.CFrame })
		end

		piece(SMOCK, Vector3.new(1.42, 1.62, 0.78), base * CFrame.new(0, 2.30, 0))
		piece(APRON, Vector3.new(1.10, 1.30, 0.16), base * CFrame.new(0, 2.02, -0.44))   -- apron
		piece(LEATH, Vector3.new(1.16, 0.14, 0.20), base * CFrame.new(0, 2.70, -0.44))   -- apron strap
		piece(LEATH, Vector3.new(1.48, 0.24, 0.84), base * CFrame.new(0, 1.60, 0))       -- belt
		piece(Color3.fromRGB(120, 90, 56), Vector3.new(0.30, 0.30, 0.90),
			base * CFrame.new(0, 1.60, 0))                                              -- buckle
		piece(KERCH, Vector3.new(1.00, 0.30, 0.86), base * CFrame.new(0, 3.06, 0))       -- neckerchief

		local head = piece(SKIN, Vector3.new(0.94, 0.88, 0.90), base * CFrame.new(0, 3.58, 0))
		piece(SKIN, Vector3.new(0.20, 0.20, 0.16), base * CFrame.new(0, 3.54, -0.50))    -- nose
		for _, s in ipairs({ -1, 1 }) do
			piece(Color3.fromRGB(48, 38, 32), Vector3.new(0.13, 0.17, 0.09),
				base * CFrame.new(s * 0.24, 3.70, -0.46))
			piece(Color3.fromRGB(140, 106, 70), Vector3.new(0.26, 0.07, 0.10),
				base * CFrame.new(s * 0.24, 3.86, -0.45))                               -- brows
		end
		piece(Color3.fromRGB(150, 96, 84), Vector3.new(0.30, 0.07, 0.08),
			base * CFrame.new(0, 3.34, -0.47))                                          -- mouth
		piece(Color3.fromRGB(226, 222, 214), Vector3.new(0.88, 0.34, 0.70),
			base * CFrame.new(0, 3.22, 0.08))                                           -- beard

		piece(STRAW, Vector3.new(2.20, 0.13, 2.20), base * CFrame.new(0, 4.08, 0))       -- brim
		piece(STRAW, Vector3.new(1.86, 0.10, 1.86), base * CFrame.new(0, 4.17, 0))       -- brim step
		piece(STRAW, Vector3.new(1.00, 0.46, 1.00), base * CFrame.new(0, 4.36, 0))       -- crown
		piece(KERCH, Vector3.new(1.05, 0.12, 1.05), base * CFrame.new(0, 4.20, 0))       -- hat band

		-- the basket at their feet, where what you give piles up
		for i = 1, 8 do
			local a = (i / 8) * math.pi * 2
			local e = 2 * 1.35 * math.tan(math.pi / 8) + 0.30
			piece(PAL.WOOD, Vector3.new(0.24, 0.74, e),
				base * CFrame.new(math.cos(a) * 1.35, 0.37 + i * 0.002, -2.0 + math.sin(a) * 1.35)
					* CFrame.Angles(0, -a, 0))
		end
		piece(PAL.WOOD_D, Vector3.new(2.7, 0.16, 2.7), base * CFrame.new(0, 0.08, -2.0))
		local basketAt = (base * CFrame.new(0, 0.55, -2.0)).Position

		-- a slow breath and a bit of arm sway, so they don't read as a statue
		task.spawn(function()
			local hb = head.CFrame
			while head.Parent do
				local t = os.clock()
				head.CFrame = hb * CFrame.new(0, math.sin(t * 1.4) * 0.05, 0)
					* CFrame.Angles(0, math.sin(t * 0.45) * 0.10, 0)
				for _, a in ipairs(arms) do
					if a.part.Parent then
						a.part.CFrame = a.home * CFrame.Angles(math.sin(t * 1.1 + a.side) * 0.07, 0, 0)
					end
				end
				task.wait(0.06)
			end
		end)

		local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(6, 8, 7),
		                 CFrame = base * CFrame.new(0, 3, -0.9), Parent = folder })
		offerPrompt = Instance.new("ProximityPrompt")
		offerPrompt.Name = "OfferPrompt"
		offerPrompt.ActionText = "Give Offering"
		offerPrompt.ObjectText = "Grove Keeper"
		offerPrompt.HoldDuration = 0.4
		offerPrompt.MaxActivationDistance = 14
		offerPrompt.RequiresLineOfSight = false
		offerPrompt.Enabled = #carried > 0
		offerPrompt.Parent = hit

		local laid = 0
		offerPrompt.Triggered:Connect(function(plr)
			if plr ~= player or #carried == 0 then return end
			for _, c in ipairs(carried) do
				local g = gardens[c.garden]
				if g then g.offered = (g.offered or 0) + 1 end

				local a = (laid % 7) / 7 * math.pi * 2
				local r = 0.5 + (laid % 3) * 0.3
				local q = buildProduce(c.colour, c.size, c.shape, folder)
				q:PivotTo(CFrame.new(basketAt + Vector3.new(math.cos(a) * r,
					math.floor(laid / 7) * 0.42, math.sin(a) * r))
					* CFrame.Angles(0, math.random() * 6.28, math.rad(math.random(-18, 18))))
				laid += 1
				c.model:Destroy()
			end
			carried = {}
			offerPrompt.Enabled = false
			playSound(SOUND_BLOOM, 0.5)

			local em = Instance.new("ParticleEmitter")
			em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			em.Color = ColorSequence.new(Color3.fromRGB(210, 255, 220))
			em.Lifetime = NumberRange.new(0.8, 1.4); em.Rate = 0
			em.Speed = NumberRange.new(4, 10); em.SpreadAngle = Vector2.new(120, 120)
			em.Size = NumberSequence.new(1.1); em.LightEmission = 0.8
			em.Acceleration = Vector3.new(0, -6, 0)
			em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			em.Parent = hit; em:Emit(40)
			Debris:AddItem(em, 2)

			if refreshBanner then refreshBanner() end
			if allOffered() then
				if showBubble then showBubble(head, "That's all of it. Watch the tree.", false) end
				print("[Park] every offering delivered -- the tree stirs")
				task.delay(1.6, function() if awakenTree then awakenTree() end end)
			elseif showBubble then
				showBubble(head, ("Good. Still short: %s."):format(offeringsText()), false)
			end
		end)
	end)
end


-- one loop drives every butterfly in the park
RunService.RenderStepped:Connect(function()
	if #butterflies == 0 then return end
	local t = os.clock()
	for _, b in ipairs(butterflies) do
		if b.body.Parent then
			local a = t * b.speed + b.phase
			local pos = b.center + Vector3.new(math.cos(a) * b.radius, 0, math.sin(a) * b.radius)
			pos = Vector3.new(pos.X, b.height + math.sin(t * 2.4 + b.phase) * b.bob, pos.Z)
			local cf = CFrame.new(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
			b.body.CFrame = cf
			local flap = math.sin(t * 18 + b.phase) * 0.9
			b.wl.CFrame = cf * CFrame.new(-0.35, 0.08, 0) * CFrame.Angles(0, 0, flap)
			b.wr.CFrame = cf * CFrame.new(0.35, 0.08, 0) * CFrame.Angles(0, 0, -flap)
		end
	end
end)

-- ============================================================================
-- OPENING A GATE
-- ============================================================================
-- ============================================================================
-- STEP 3 -- THE AWAKENING
-- ============================================================================
-- Fires by itself once the third garden is back: roots glow, the orbs light bottom to top,
-- blossoms break out along the branches, motes spiral the trunk, butterflies circle it, the
-- fountain runs enchanted and confetti goes up.
function awakenTree()
	if step >= 3 then return end
	step = 3
	_G.parkQuestStep = 3
	if refreshBanner then refreshBanner() end

	-- ---- where the tree actually is (bounding box, not pivot -- the pivot on this model
	-- sits well above the ground)
	local bcf, bsz = Vector3.new(), Vector3.new(20, 40, 20)
	if tree then bcf, bsz = tree:GetBoundingBox() end
	local treeXZ  = tree and Vector3.new(bcf.Position.X, 0, bcf.Position.Z) or center
	local baseY   = tree and groundYAt(bcf.Position) or groundY
	local treeH   = math.max(20, bsz.Y)
	local treeRad = math.max(10, math.max(bsz.X, bsz.Z) * 0.5)
	local rootPos = Vector3.new(treeXZ.X, baseY, treeXZ.Z)

	-- ---- 1. the roots begin to glow
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2
		local host = mk({ Transparency = 1, Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(rootPos + Vector3.new(math.cos(a) * treeRad * 0.32, 1.5, math.sin(a) * treeRad * 0.32)),
			Parent = park })
		local lt = Instance.new("PointLight")
		lt.Color = Color3.fromRGB(140, 255, 170); lt.Brightness = 0; lt.Range = treeRad * 0.7
		lt.Parent = host
		tween(lt, 1.6, { Brightness = 2.4 })
	end

	-- ---- 2. the orbs relight, bottom to top
	task.delay(0.8, reviveTree)

	-- ---- 3. blossoms breaking out along the branches: a short sparkle on parts in the
	-- upper half of the model, spread over the same window as the colour sweep
	if tree then
		task.delay(1.2, function()
			local high = {}
			for _, d in ipairs(tree:GetDescendants()) do
				if d:IsA("BasePart") and d.Position.Y > baseY + treeH * 0.45 then
					table.insert(high, d)
				end
			end
			for i = 1, math.min(28, #high) do
				local p = high[math.random(1, #high)]
				task.delay(math.random() * 2.6, function()
					if not p.Parent then return end
					local em = Instance.new("ParticleEmitter")
					em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
					em.Color = ColorSequence.new(Color3.fromRGB(255, 190, 225), Color3.fromRGB(255, 246, 190))
					em.Lifetime = NumberRange.new(1.0, 1.8); em.Rate = 0
					em.Speed = NumberRange.new(2, 6); em.SpreadAngle = Vector2.new(180, 180)
					em.Size = NumberSequence.new(1.5); em.LightEmission = 0.6
					em.Acceleration = Vector3.new(0, -3, 0)
					em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
					em.Parent = p; em:Emit(26)
					Debris:AddItem(em, 2.5)
				end)
			end
		end)
	end

	-- ---- 4. magical motes spiralling up the trunk. Hand-animated rather than an emitter:
	-- a particle emitter can rise but it can't wind around anything.
	do
		local motes = {}
		for i = 1, 14 do
			motes[i] = mk({
				Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
				Color = Color3.fromRGB(180, 255, 210), Size = Vector3.new(1.1, 1.1, 1.1),
				Transparency = 0.25, Parent = park,
			})
		end
		local t0, conn = os.clock(), nil
		conn = RunService.RenderStepped:Connect(function()
			local age = os.clock() - t0
			for i, m in ipairs(motes) do
				if m.Parent then
					local f = ((age * 0.28) + (i / #motes)) % 1          -- 0..1 up the trunk
					local a = f * math.pi * 6 + i                         -- three turns on the way
					local r = treeRad * (0.30 - 0.16 * f)                 -- tightens as it climbs
					m.CFrame = CFrame.new(rootPos
						+ Vector3.new(math.cos(a) * r, treeH * 0.92 * f, math.sin(a) * r))
					m.Transparency = 0.25 + f * 0.6
				end
			end
			if age > 16 then
				conn:Disconnect()
				for _, m in ipairs(motes) do if m.Parent then m:Destroy() end end
			end
		end)
	end

	-- ---- 5. butterflies circling the tree (same driver as the garden ones)
	task.delay(1.6, function()
		spawnButterflies({ pos = Vector3.new(treeXZ.X, 0, treeXZ.Z), size = treeRad * 1.5,
		                   groundY = baseY + treeH * 0.35, folder = park }, 10)
	end)

	-- ---- 6. the fountain turns enchanted
	if F.light then tween(F.light, 2.0, { Brightness = 3.2, Color = Color3.fromRGB(180, 235, 255) }) end
	if F.jet then F.jet.Rate = 150 end
	for _, em in ipairs(F.crownJets or {}) do em.Rate = 44 end
	if F.mist then F.mist.Rate = 14 end
	if F.sparkles then F.sparkles.Rate = 40 end
	if F.glow then tween(F.glow, 2.0, { Transparency = 0.55 }) end
	for _, w in ipairs({ F.water, F.upperWater, F.topWater }) do
		if w then tween(w, 2.0, { Color = Color3.fromRGB(150, 225, 255), Reflectance = 0.3 }) end
	end
	if F.finial then
		local fg = Instance.new("PointLight")
		fg.Color = Color3.fromRGB(200, 255, 235); fg.Brightness = 0; fg.Range = 26; fg.Parent = F.finial
		tween(fg, 2.0, { Brightness = 3 })
		-- Material is an enum, so TweenService can't interpolate it -- set it, tween the rest
		F.finial.Material = Enum.Material.Neon
		tween(F.finial, 2.0, { Color = Color3.fromRGB(226, 255, 244) })
	end

	-- ---- 7. confetti
	task.delay(2.2, function()
		for i = 1, 5 do
			local a = (i / 5) * math.pi * 2
			local host = mk({ Transparency = 1, Size = Vector3.new(1, 1, 1),
				CFrame = CFrame.new(rootPos + Vector3.new(math.cos(a) * treeRad * 0.7, 4, math.sin(a) * treeRad * 0.7)),
				Parent = park })
			local em = Instance.new("ParticleEmitter")
			em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			em.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 160)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 230, 120)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 200, 255)) })
			em.Lifetime = NumberRange.new(2.4, 4.0); em.Rate = 0
			em.Speed = NumberRange.new(38, 62); em.SpreadAngle = Vector2.new(38, 38)
			em.Size = NumberSequence.new(1.3); em.LightEmission = 0.4
			em.Acceleration = Vector3.new(0, -28, 0); em.RotSpeed = NumberRange.new(-240, 240)
			em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
			em.Parent = host; em:Emit(140)
			Debris:AddItem(host, 6)
		end
	end)

	-- ---- the payout
	local coinEvent = ReplicatedStorage:FindFirstChild("CoinEvent")
	if coinEvent then pcall(function() coinEvent:FireServer(COIN_REWARD) end) end
	_G.parkQuestComplete = true

	task.delay(3.0, function()
		if refreshBanner then refreshBanner() end
		print(("[Park] QUEST COMPLETE -- the Ancient Tree has awakened. +%d coins"):format(COIN_REWARD))
	end)
end

-- ============================================================================
-- PAL.WATER POURING OUT OF A GATE
-- ============================================================================
-- Once a gate is open it actually runs: a sheet down the chute with crests riding it, a
-- splash where it lands, a pool on the apron, and patches of ground going dark and damp
-- downstream as the water soaks in. It runs for as long as that garden is being watered and
-- then dries up in step with it.
local function startGateFlow(g)
	if not (g.chute and g.gatePool and g.gateBase) then return end
	local base, cf, len = g.gateBase, g.chuteCF, g.chuteLen

	tween(g.chute,    0.5, { Transparency = 0.14 })
	tween(g.gatePool, 0.9, { Transparency = 0.18 })
	if g.foamTop  then tween(g.foamTop,  0.5, { Transparency = 0.22 }) end
	if g.foamBase then tween(g.foamBase, 0.9, { Transparency = 0.28 }) end

	g.flowing = true

	-- crests riding down the chute. One RenderStepped for the gate, stepped on the real frame
	-- delta so it runs smoothly rather than at the resolution of a wait().
	local riders = {}
	for k = 1, 4 do
		riders[k] = {
			part = mk({ Material = Enum.Material.Neon, Color = PAL.WATER_G, Transparency = 1,
			            Size = Vector3.new(CHANNEL_W - 1.1, 0.06, len * 0.16), Parent = park }),
			t = (k - 1) / 4,
			speed = 0.75 + (k % 2) * 0.25,
		}
	end
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not g.flowing then
			for _, r in ipairs(riders) do if r.part.Parent then r.part:Destroy() end end
			conn:Disconnect()
			return
		end
		for _, r in ipairs(riders) do
			r.t = (r.t + r.speed * dt) % 1
			r.part.CFrame = cf * CFrame.new(0, 0.17, (r.t - 0.5) * len)
			local edge = math.min(r.t, 1 - r.t) / 0.2
			r.part.Transparency = 1 - math.clamp(edge, 0, 1) * 0.55
		end
		-- the white water churns rather than sitting still
		local churn = os.clock()
		if g.foamTop and g.foamTop.Parent then
			g.foamTop.Transparency = 0.22 + math.sin(churn * 7.5) * 0.10
		end
		if g.foamBase and g.foamBase.Parent then
			g.foamBase.Transparency = 0.28 + math.sin(churn * 5.3 + 1.1) * 0.12
		end
	end)

	-- splash where the sheet hits the apron
	local hit = splashAt(g.splashPos, g.gateFolder)
	hit.Rate = 26
	hit.Speed = NumberRange.new(4, 11)

	-- --- SOAKING IN. Patches of ground downstream of the apron darken as they take the water
	-- and then dry back out, each on its own cycle, so the ground never looks like one flat
	-- decal switching on.
	task.spawn(function()
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { park, player.Character }
		local t0 = os.clock()
		while g.flowing do
			local ox   = (math.random() - 0.5) * (CHANNEL_W + 3.5)
			local oz   = 5.2 + math.random() * 5.5
			local from = base * Vector3.new(ox, 6, oz)
			local hitG = Workspace:Raycast(from, Vector3.new(0, -30, 0), rp)
			if hitG then
				local w = math.random(18, 34) / 10
				local patch = mk({
					Material = Enum.Material.SmoothPlastic, Color = PAL.DAMP, Transparency = 1,
					Size = Vector3.new(w, 0.06, w * (0.7 + math.random() * 0.6)),
					CFrame = CFrame.new(hitG.Position + Vector3.new(0, 0.05, 0)), Parent = park })
				-- a bead of water sitting on it, which shrinks away as the ground takes it
				local bead = mk({
					Material = Enum.Material.SmoothPlastic, Color = PAL.WATER_L, Reflectance = 0.26,
					Transparency = 1, Size = Vector3.new(w * 0.7, 0.1, w * 0.5),
					CFrame = CFrame.new(hitG.Position + Vector3.new(0, 0.11, 0)), Parent = park })
				tween(patch, 0.6, { Transparency = 0.35 })
				tween(bead,  0.5, { Transparency = 0.2 })
				task.delay(1.1, function()
					tween(bead, 1.5, { Transparency = 1, Size = Vector3.new(w * 0.2, 0.02, w * 0.15) })
					tween(patch, 2.6, { Transparency = 1 })
				end)
				Debris:AddItem(bead, 2.8)
				Debris:AddItem(patch, 3.9)
			end
			-- the gate now runs for the rest of the session, so ease off after the first burst
			-- rather than spawning patches at full rate forever
			local fast = (os.clock() - t0) < 25
			task.wait((fast and 0.22 or 0.9) + math.random() * 0.25)
		end
	end)
end

local function stopGateFlow(g)
	if not g.flowing then return end
	g.flowing = false                       -- the RenderStepped tears its own crests down
	if g.chute    then tween(g.chute,    1.6, { Transparency = 1 }) end
	if g.gatePool then tween(g.gatePool, 2.4, { Transparency = 1 }) end
end

local function openGate(g)
	g.open = true
	gatesOpen += 1
	playSound(SOUND_CLUNK, 0.8)
	if g.flakes then g.flakes.Rate = 0 end
	if g.prompt then g.prompt.Enabled = false end

	-- the whole sluice board -- planks and straps together -- winds up out of the channel
	for _, p in ipairs(g.plateParts or { g.plate }) do
		if p and p.Parent then
			tween(p, 0.9, { CFrame = p.CFrame + Vector3.new(0, 2.7, 0) }, Enum.EasingStyle.Back)
		end
	end

	-- the gate itself starts running the moment the board is clear of the opening
	task.delay(0.65, function() startGateFlow(g) end)

	-- water runs underground to the garden, then surfaces there and spreads
	task.delay(0.45, function()
		deliverWater(g, function()
			bloomGarden(g)
			-- the gate keeps running too -- an open gate stays open
			-- NOTE: opening the third gate does NOT wake the tree. It wakes when the Grove
			-- Keeper has been given every offering -- see the harvest section.
		end)
	end)

	if gatesOpen >= 3 then
		step = 2
		_G.parkQuestStep = 2
	end
	if refreshBanner then refreshBanner() end
end

-- ============================================================================
-- THE CRANK CONSOLE
-- ============================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "IrrigationCrank"; gui.ResetOnSpawn = false; gui.DisplayOrder = 60; gui.Enabled = false
gui.Parent = PlayerGui

local console = Instance.new("Frame")
console.AnchorPoint = Vector2.new(0.5, 1); console.Position = UDim2.new(0.5, 0, 1, -18)
console.Size = UDim2.new(0, 640, 0, 234); console.BackgroundColor3 = PAL.PANEL; console.BorderSizePixel = 0
console.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = console
	local s = Instance.new("UIStroke"); s.Color = PAL.BRASS_D; s.Thickness = 3; s.Parent = console
end

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 30); header.BackgroundColor3 = PAL.BRASS; header.BorderSizePixel = 0
header.Parent = console
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = header end

local hdrLbl = Instance.new("TextLabel")
hdrLbl.BackgroundTransparency = 1; hdrLbl.Position = UDim2.new(0, 16, 0, 0); hdrLbl.Size = UDim2.new(1, -32, 1, 0)
hdrLbl.Font = Enum.Font.FredokaOne; hdrLbl.TextSize = 15; hdrLbl.TextColor3 = Color3.fromRGB(46, 34, 12)
hdrLbl.TextXAlignment = Enum.TextXAlignment.Left; hdrLbl.Text = "IRRIGATION GATE"; hdrLbl.Parent = header

-- --- the wheel dial, drawn as spokes we rotate
local dial = Instance.new("Frame")
dial.AnchorPoint = Vector2.new(0.5, 0.5); dial.Position = UDim2.new(0, 92, 0, 130)
dial.Size = UDim2.new(0, 128, 0, 128); dial.BackgroundColor3 = PAL.PANEL_2; dial.BorderSizePixel = 0
dial.Parent = console
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = dial
	local s = Instance.new("UIStroke"); s.Color = PAL.BRASS; s.Thickness = 5; s.Parent = dial
end
local spokes = Instance.new("Frame")
spokes.AnchorPoint = Vector2.new(0.5, 0.5); spokes.Position = UDim2.fromScale(0.5, 0.5)
spokes.Size = UDim2.fromScale(1, 1); spokes.BackgroundTransparency = 1; spokes.Parent = dial
for i = 1, 3 do
	local sp = Instance.new("Frame")
	sp.AnchorPoint = Vector2.new(0.5, 0.5); sp.Position = UDim2.fromScale(0.5, 0.5)
	sp.Size = UDim2.new(0, 104, 0, 9); sp.BackgroundColor3 = PAL.BRASS; sp.BorderSizePixel = 0
	sp.Rotation = (i - 1) * 60; sp.Parent = spokes
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = sp
end

local function mkText(parent, txt, x, y, w, h, col, size, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1; l.Position = UDim2.new(0, x, 0, y); l.Size = UDim2.new(0, w, 0, h)
	l.Font = Enum.Font.FredokaOne; l.Text = txt; l.TextColor3 = col or PAL.CREAM; l.TextSize = size or 15
	l.TextXAlignment = align or Enum.TextXAlignment.Left; l.TextWrapped = true; l.Parent = parent
	return l
end

local hintLbl = mkText(console, "", 176, 44, 448, 52, Color3.fromRGB(255, 232, 172), 20)
hintLbl.TextYAlignment = Enum.TextYAlignment.Center

-- progress track
local track = Instance.new("Frame")
track.Position = UDim2.new(0, 176, 0, 104); track.Size = UDim2.new(0, 448, 0, 26)
track.BackgroundColor3 = Color3.fromRGB(22, 19, 15); track.BorderSizePixel = 0; track.Parent = console
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = track end
local fill = Instance.new("Frame")
fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = PAL.WATER; fill.BorderSizePixel = 0; fill.Parent = track
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = fill end
-- the seize marks, so you can see the jams coming
for _, frac in ipairs(SEIZE_POINTS) do
	local m = Instance.new("Frame")
	m.Position = UDim2.new(frac, -2, 0, 0); m.Size = UDim2.new(0, 4, 1, 0)
	m.BackgroundColor3 = PAL.RUST; m.BorderSizePixel = 0; m.ZIndex = 3; m.Parent = track
end

local function mkButton(text, x, y, w, h, tint)
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(0, x, 0, y); b.Size = UDim2.new(0, w, 0, h)
	b.BackgroundColor3 = tint or PAL.PANEL_2; b.BorderSizePixel = 0; b.AutoButtonColor = false
	b.Font = Enum.Font.FredokaOne; b.Text = text; b.TextColor3 = PAL.CREAM; b.TextScaled = true
	b.Parent = console
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = b
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 24; sz.Parent = b
	return b
end

local btnCrank = mkButton("HOLD TO CRANK", 176, 142, 300, 74, Color3.fromRGB(52, 96, 122))
local btnExit  = mkButton("LET GO", 488, 142, 136, 74, Color3.fromRGB(96, 52, 46))

-- --- crank state
local holding, wasReleased = false, true
local savedWalk, savedJump

local function setCranking(g)
	local prev = cranking
	if prev and prev ~= g and prev.flakes then prev.flakes.Rate = 0 end
	cranking = g
	gui.Enabled = g ~= nil
	holding = false; wasReleased = true

	local char = player.Character
	local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
	local cam  = Workspace.CurrentCamera

	if g then
		if hum then
			savedWalk, savedJump = hum.WalkSpeed, hum.JumpPower
			hum.WalkSpeed, hum.JumpPower = 0, 0
		end
		hdrLbl.Text = ("IRRIGATION GATE %d  //  SEIZED"):format(g.index)
		if cam and g.wheelCF then
			cam.CameraType = Enum.CameraType.Scriptable
			local eye = g.wheelCF.Position + g.gateFacing * 11 + Vector3.new(0, 4.5, 0)
			cam.CFrame = CFrame.new(eye, g.wheelCF.Position)
		end
	else
		if hum then
			hum.WalkSpeed = savedWalk or 16
			hum.JumpPower = savedJump or 50
		end
		if cam then
			cam.CameraType = Enum.CameraType.Custom
			if hum then cam.CameraSubject = hum end
		end
	end
end

takeCrank = function(g)
	if cranking or g.open or step < 1 then return end
	setCranking(g)
end

btnExit.MouseButton1Click:Connect(function() setCranking(nil) end)
btnCrank.MouseButton1Down:Connect(function() holding = true end)
btnCrank.MouseButton1Up:Connect(function() holding = false end)
btnCrank.MouseLeave:Connect(function() holding = false end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not cranking then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.E or k == Enum.KeyCode.Space or k == Enum.KeyCode.D or k == Enum.KeyCode.Right then
		holding = true
	elseif k == Enum.KeyCode.Q or k == Enum.KeyCode.Escape then
		setCranking(nil)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	local k = input.KeyCode
	if k == Enum.KeyCode.E or k == Enum.KeyCode.Space or k == Enum.KeyCode.D or k == Enum.KeyCode.Right then
		holding = false
	end
end)

-- dying mid-crank shouldn't leave you frozen in the console
player.CharacterAdded:Connect(function()
	savedWalk, savedJump = nil, nil
	if cranking then setCranking(nil) end
end)

-- the crank loop
RunService.RenderStepped:Connect(function(dt)
	local g = cranking
	if not g then return end

	local total = CRANK_TURNS * 360
	local sp    = SEIZE_POINTS[g.seizeIdx]

	-- Reaching a seize point LATCHES the jam. It stays latched until you let go and take a
	-- fresh grip -- keeping the button held just holds a dead wheel, which is the whole point.
	if sp and not g.stuck and g.progress >= sp then
		g.stuck = true
		if g.flakes then g.flakes:Emit(18) end
	end

	if not holding then wasReleased = true end

	if g.stuck then
		g.angle    = sp * total          -- pinned; it can't creep or slip while jammed
		g.progress = sp
		if g.flakes then g.flakes.Rate = 0 end
		if holding and wasReleased then  -- a fresh heave breaks it free
			g.stuck = false
			g.seizeIdx += 1
			wasReleased = false
			if g.flakes then g.flakes:Emit(30) end
			playSound(SOUND_CLUNK, 0.4)
		end
	elseif holding then
		g.angle    += CRANK_SPEED * dt
		g.progress  = math.min(1, g.angle / total)
		wasReleased = false
		if g.flakes then g.flakes.Rate = 22 end
	else
		g.angle    = math.max(0, g.angle - CRANK_DECAY * dt)
		g.progress = math.max(0, g.angle / total)
		if g.flakes then g.flakes.Rate = 0 end
	end

	-- drive the real wheel and the dial together
	if g.wheel and g.wheelCF then
		g.wheel:PivotTo(g.wheelCF * CFrame.Angles(0, 0, math.rad(-g.angle)))
	end
	spokes.Rotation = -g.angle

	fill.Size = UDim2.new(g.progress, 0, 1, 0)
	if g.stuck then
		hintLbl.Text = "IT'S SEIZED!  Let go, then HEAVE again!"
		fill.BackgroundColor3 = PAL.RUST
	elseif holding then
		hintLbl.Text = ("Keep cranking!   %d%%"):format(math.floor(g.progress * 100))
		fill.BackgroundColor3 = PAL.WATER
	else
		hintLbl.Text = "Hold the button (or E) to crank the wheel round."
		fill.BackgroundColor3 = PAL.WATER_D
	end

	if g.progress >= 1 then
		local done = g
		setCranking(nil)
		openGate(done)
	end
end)

-- ============================================================================
-- OBJECTIVE BANNER
-- ============================================================================
local objGui = Instance.new("ScreenGui")
objGui.Name = "ParkObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7; objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5, 0); objFrame.Position = UDim2.new(0.5, 0, 0, 12)
objFrame.Size = UDim2.new(0, 560, 0, 52); objFrame.BackgroundColor3 = PAL.PANEL; objFrame.Visible = false
objFrame.Parent = objGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = objFrame
	local s = Instance.new("UIStroke"); s.Color = PAL.LEAF; s.Thickness = 3; s.Parent = objFrame
end
local objLabel = Instance.new("TextLabel")
objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1, 1); objLabel.Font = Enum.Font.FredokaOne
objLabel.TextColor3 = Color3.fromRGB(206, 246, 196); objLabel.TextScaled = true; objLabel.Parent = objFrame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 20; sz.Parent = objLabel
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14); pad.Parent = objLabel
end

-- how many gardens have ripe crops waiting / offerings outstanding
local function harvestActive()
	for _, g in ipairs(gardens) do if g.ripened then return true end end
	return false
end

function offeringsText()
	local a = {}
	for _, g in ipairs(gardens) do
		a[#a + 1] = ("%d/%d"):format(math.min(g.offered or 0, OFFER_PER_GARDEN), OFFER_PER_GARDEN)
	end
	return table.concat(a, " \xC2\xB7 ")
end

refreshBanner = function()
	local txt
	if not questAccepted and npcHead then
		objLabel.Text = "\xF0\x9F\x8C\xB3 The park is dying -- talk to the Candy Npc."
		return
	end
	if FOUNTAIN_ONLY then
		txt = (step >= 1) and "\xF0\x9F\x92\xA7 The fountain is flowing again!"
			or "\xF0\x9F\x92\xA7 The fountain has dried up -- turn the valve to restore it!"
	elseif step >= 3 then
		txt = "\xF0\x9F\x8C\xB3 The Ancient Tree has awakened! The park is flourishing once again."
	elseif harvestActive() then
		-- once anything is ripe, the harvest is what the player is actually doing
		if #carried > 0 then
			txt = ("\xF0\x9F\xA7\xBA Carrying %d/%d -- lay them at the Ancient Tree  (%s)")
				:format(#carried, CARRY_MAX, offeringsText())
		else
			txt = ("\xF0\x9F\x8C\xBE Pick ripe crops for the tree:  %s"):format(offeringsText())
		end
	elseif step >= 1 then
		txt = ("\xF0\x9F\x9A\xB0 Turn the irrigation gates:  %d/3 gardens restored"):format(gatesOpen)
	elseif #pipes > 0 and pipesFixed < PIPE_COUNT then
		txt = ("\xF0\x9F\x94\xA7 Seal the burst water mains:  %d/%d")
			:format(pipesFixed, PIPE_COUNT)
	else
		txt = "\xF0\x9F\x92\xA7 The mains hold -- turn the fountain valve!"
	end
	objLabel.Text = txt
end

-- only show the banner while you're actually in the park
task.spawn(function()
	while true do
		local vis = false
		if park then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			vis = hrp ~= nil and (hrp.Position - center).Magnitude <= 340
		end
		objFrame.Visible = vis and (cranking == nil)
		task.wait(0.4)
	end
end)

-- ============================================================================
-- THE CANDY NPC -- quest giver, same pattern as island 1's gumball quest
-- ============================================================================
-- Paged speech bubble on a "Talk" prompt, reading past page 1 accepts the quest. Copied from
-- CandyGumballQuest so the park doesn't feel like a different game to the rest of the island.
--
-- The SAME name exists on several islands, so the NPC is matched by distance to THIS park's
-- fountain -- otherwise island 9's Candy Npc could be picked up from here.
-- compared with norm(), so spaces/underscores/case don't matter: "Candy Npc", "candy_npc"
-- and "CandyNPC " all land on "candynpc"
local NPC_NAMES    = { "candynpc", "questnpc", "parknpc" }
local NPC_MAX_DIST = 600


local function npcHeadOf(d)
	return (d:IsA("Model") and (d:FindFirstChild("Head") or d.PrimaryPart
		or d:FindFirstChildWhichIsA("BasePart", true)))
		or (d:IsA("BasePart") and d) or nil
end

-- THIS ISLAND'S NPC, not a neighbour's.
--
-- Distance alone is NOT enough here. Island 13's fountain and island 14's campfire are only
-- about 550 studs apart, so a Workspace-wide "nearest within range" search wired island 14's
-- Candy Npc to the park quest -- it logged 551 studs and then accepted the park quest when
-- talked to. So: look INSIDE island13 first and take that unconditionally; only fall back to
-- a proximity search if the island genuinely has none of its own.
local function npcScan(scope, needDist)
	local best, bestD
	for _, d in ipairs(scope:GetDescendants()) do
		-- norm() rather than a plain lowercase compare: names in this place routinely carry a
		-- trailing space ('gas vents ', 'chunk ', 'snow '), and "Candy Npc " would never match
		local match = false
		for _, want in ipairs(NPC_NAMES) do if norm(d.Name) == want then match = true; break end end
		if match then
			local head = npcHeadOf(d)
			if head then
				local dist = (head.Position - center).Magnitude
				if (not needDist or dist <= NPC_MAX_DIST) and (not bestD or dist < bestD) then
					best, bestD = head, dist
				end
			end
		end
	end
	return best
end

local function findNPCHead()
	if island then
		local mine = npcScan(island, false)
		if mine then return mine end
	end
	return npcScan(Workspace, true)
end

local function hideBubble(adornee)
	local prev = adornee:FindFirstChild("SpeechBubble"); if prev then prev:Destroy() end
end

function showBubble(adornee, text, persist, footer)
	hideBubble(adornee)
	local bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"; bb.Adornee = adornee; bb.Size = UDim2.new(0, 320, 0, 150)
	bb.StudsOffset = Vector3.new(0, 5.5, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local frame = Instance.new("Frame"); frame.Size = UDim2.fromScale(1, 1); frame.BackgroundColor3 = PAL.BUB_FILL
	frame.BackgroundTransparency = 0.05; frame.BorderSizePixel = 0; frame.Parent = bb
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 18)
	local st = Instance.new("UIStroke"); st.Color = PAL.BUB_STROKE; st.Thickness = 2; st.Transparency = 0.4; st.Parent = frame
	local pd = Instance.new("UIPadding")
	pd.PaddingTop = UDim.new(0, 12); pd.PaddingBottom = UDim.new(0, 12)
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = frame
	local lbl = Instance.new("TextLabel")
	lbl.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.FredokaOne; lbl.Text = text
	lbl.TextColor3 = PAL.BUB_TEXT; lbl.TextScaled = true; lbl.TextWrapped = true; lbl.Parent = frame
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = lbl
	if footer then
		local h = Instance.new("TextLabel")
		h.Size = UDim2.fromScale(1, 0.2); h.Position = UDim2.fromScale(0, 0.8)
		h.BackgroundTransparency = 1; h.Font = Enum.Font.FredokaOne; h.Text = footer
		h.TextColor3 = PAL.BUB_HINT; h.TextScaled = true; h.Parent = frame
		local hs = Instance.new("UITextSizeConstraint"); hs.MaxTextSize = 14; hs.Parent = h
	end
	bb.Parent = adornee
	if not persist then
		task.delay(9, function()
			if bb and bb.Parent == adornee and bb.Name == "SpeechBubble" then bb:Destroy() end
		end)
	end
	return bb
end

local function questPages()
	if step >= 3 then
		return { "The Ancient Tree is awake.", "Look at it. You did that. \xF0\x9F\x8C\xB3" }
	end
	if harvestActive() then
		return {
			"Now the tree. It has slept a long time.",
			("Bring it %d crops from every garden -- lay them at the roots."):format(OFFER_PER_GARDEN),
			("So far: %s."):format(offeringsText()),
		}
	end
	if step >= 1 then
		return {
			"The water's back! Listen to it.",
			("Now the gates -- %d of 3 open."):format(gatesOpen),
			"Crank each one and the water will find its garden.",
		}
	end
	if questAccepted then
		if #pipes > 0 and pipesFixed < PIPE_COUNT then
			return { "The mains under the lawn have burst.",
				("Seal all %d of them -- there is a wrench on every one."):format(PIPE_COUNT),
				("%d sealed so far."):format(pipesFixed) }
		end
		return { "Mains are holding.", "Now turn the valve and let it fill." }
	end
	return {
		"You came. Nobody comes to the park any more.",
		"The fountain ran dry, and everything downstream died with it.",
		"Turn the valve, then open the three irrigation gates.",
		"Then bring the Ancient Tree an offering from every garden. It will remember.",
	}
end

local function acceptQuest()
	if questAccepted then return end
	questAccepted = true
	-- the pits come first now; the valve stays shut until every main holds pressure
	if #pipes > 0 then
		for _, p in ipairs(pipes) do if p.prompt and not p.fixed then p.prompt.Enabled = true end end
	elseif valvePrompt then
		valvePrompt.Enabled = true
	end
	if refreshBanner then refreshBanner() end
	print("[Park] quest accepted from the Candy Npc")
end

local function wireNPC(head)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = "Candy Npc"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false; prompt.Parent = head

	local pages, index, watching = nil, 0, false
	local function closeDialogue()
		hideBubble(head); prompt.ActionText = "Talk"; index = 0; pages = nil
	end

	-- close the bubble the moment you walk off, not just when the prompt hides
	local function startWatcher()
		if watching then return end
		watching = true
		task.spawn(function()
			while index ~= 0 do
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not hrp or (hrp.Position - head.Position).Magnitude > 14 then
					closeDialogue(); break
				end
				task.wait(0.25)
			end
			watching = false
		end)
	end

	prompt.Triggered:Connect(function(plr)
		if plr ~= player then return end
		if index == 0 then pages = questPages() end
		index += 1
		if not pages or index > #pages then closeDialogue(); return end
		if index == 2 then acceptQuest() end        -- reading past page 1 accepts it
		local last = index >= #pages
		local footer = last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages)
		showBubble(head, pages[index], true, footer)
		prompt.ActionText = last and "Close" or "Continue"
		startWatcher()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then closeDialogue() end end)
end

-- ============================================================================
-- THE WRENCH HUD
-- ============================================================================
-- Every widget hangs off ONE table and is built inside a do-block. Luau caps a function at 200
-- registers, this file's main chunk already sits at 176, and sixteen named widgets would have
-- cost sixteen of the twenty-four left. In a block they are released the moment it closes.
local MG = {}
local mgBusy = false

do
	local gui = Instance.new("ScreenGui")
	gui.Name = "ParkWrench"; gui.ResetOnSpawn = false; gui.DisplayOrder = 9
	gui.IgnoreGuiInset = true; gui.Enabled = false; gui.Parent = PlayerGui
	MG.gui = gui

	-- input goes through a full-screen button, so a tap for the HUD is not also a tap on the world
	local catch = Instance.new("TextButton")
	catch.Size = UDim2.fromScale(1, 1); catch.BackgroundTransparency = 1
	catch.Text = ""; catch.AutoButtonColor = false; catch.ZIndex = 1; catch.Parent = gui
	MG.catch = catch

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 540, 0, 152)
	panel.Position = UDim2.new(0.5, -270, 0.74, 0)
	panel.BackgroundColor3 = PAL.PANEL; panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0; panel.ZIndex = 2; panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
	MG.panel = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = PAL.BRASS; stroke.Thickness = 3; stroke.Transparency = 0.15
	stroke.Parent = panel
	MG.stroke = stroke

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0, 32); title.Position = UDim2.new(0, 12, 0, 10)
	title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBlack
	title.TextSize = 22; title.TextColor3 = Color3.fromRGB(255, 246, 232)
	title.TextXAlignment = Enum.TextXAlignment.Left; title.ZIndex = 3
	title.Text = ""; title.Parent = panel
	MG.title = title

	local count = Instance.new("TextLabel")
	count.Size = UDim2.new(0, 140, 0, 32); count.Position = UDim2.new(1, -152, 0, 10)
	count.BackgroundTransparency = 1; count.Font = Enum.Font.GothamBlack
	count.TextSize = 22; count.TextColor3 = PAL.BRASS
	count.TextXAlignment = Enum.TextXAlignment.Right; count.ZIndex = 3
	count.Text = ""; count.Parent = panel
	MG.count = count

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -32, 0, 44); track.Position = UDim2.new(0, 16, 0, 52)
	track.BackgroundColor3 = Color3.fromRGB(20, 24, 26); track.BorderSizePixel = 0
	track.ClipsDescendants = true; track.ZIndex = 3; track.Parent = panel
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, 10)

	-- pressure ticks down the gauge, so the needle has something to read against
	for i = 1, 9 do
		local tick = Instance.new("Frame")
		tick.Size = UDim2.new(0, 2, (i % 2 == 0) and 0.5 or 0.28, 0)
		tick.Position = UDim2.new(i / 10, 0, (i % 2 == 0) and 0.25 or 0.36, 0)
		tick.BackgroundColor3 = Color3.fromRGB(70, 78, 82); tick.BorderSizePixel = 0
		tick.ZIndex = 4; tick.Parent = track
	end

	local zone = Instance.new("Frame")
	zone.Size = UDim2.new(0.24, 0, 1, 0); zone.Position = UDim2.new(0.38, 0, 0, 0)
	zone.BackgroundColor3 = Color3.fromRGB(92, 196, 96); zone.BackgroundTransparency = 0.25
	zone.BorderSizePixel = 0; zone.ZIndex = 5; zone.Parent = track
	Instance.new("UICorner", zone).CornerRadius = UDim.new(0, 8)
	MG.zone = zone

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 0, 5); fill.Position = UDim2.new(0, 0, 1, -5)
	fill.BackgroundColor3 = PAL.WATER_L; fill.BorderSizePixel = 0
	fill.ZIndex = 6; fill.Parent = track
	MG.fill = fill

	local needle = Instance.new("Frame")
	needle.Size = UDim2.new(0, 6, 1, 0)
	needle.BackgroundColor3 = Color3.fromRGB(255, 250, 240); needle.BorderSizePixel = 0
	needle.ZIndex = 7; needle.Parent = track
	MG.needle = needle

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -32, 0, 26); hint.Position = UDim2.new(0, 16, 0, 106)
	hint.BackgroundTransparency = 1; hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 16; hint.TextColor3 = Color3.fromRGB(206, 198, 186)
	hint.TextXAlignment = Enum.TextXAlignment.Left; hint.ZIndex = 3
	hint.Text = ""; hint.Parent = panel
	MG.hint = hint
end

-- ONE WIDGET, TWO JOBS. A coupling is a long grind -- four taps, the band closing and the
-- needle winding up each time, so the last turn is the hard one. A crop is a single snap-tap on
-- a wide band. Same code, different numbers: two of these would have been two sets of tuning to
-- keep in step, and this file has no registers to spare for a second one anyway.
--
--   o.strokes  taps needed        o.speed   how fast the needle starts
--   o.zone     band width         o.gain    speed added per landed tap
--   o.shrink   band lost per tap  o.floor   narrowest the band may get
playWrench = function(o)
	if mgBusy then return false end
	mgBusy = true

	local strokes  = o.strokes or 1
	local onStroke = o.onStroke
	MG.title.Text = o.title or "TIGHTEN THE COUPLING"
	MG.hint.Text  = o.hint or "Tap when the needle is in the green"
	MG.count.Text = ("0 / %d"):format(strokes)
	MG.fill.Size = UDim2.new(0, 0, 0, 5)
	MG.gui.Enabled = true
	MG.panel.Position = UDim2.new(0.5, -270, 0.82, 0)
	tween(MG.panel, 0.22, { Position = UDim2.new(0.5, -270, 0.74, 0) }, Enum.EasingStyle.Back)

	local hit, pos, dir, speed = 0, 0, 1, o.speed or 0.78
	local zc, zw = 0.5, o.zone or 0.19
	local tapped = false
	local conn = MG.catch.MouseButton1Down:Connect(function() tapped = true end)

	local function drawZone()
		MG.zone.Position = UDim2.new(zc - zw * 0.5, 0, 0, 0)
		MG.zone.Size     = UDim2.new(zw, 0, 1, 0)
	end
	drawZone()

	while hit < strokes do
		local dt = math.min(task.wait(), 0.05)
		pos += dir * speed * dt
		if pos >= 1 then pos, dir = 1, -1 elseif pos <= 0 then pos, dir = 0, 1 end
		MG.needle.Position = UDim2.new(pos, -3, 0, 0)

		if tapped then
			tapped = false
			if math.abs(pos - zc) <= zw * 0.5 then
				hit += 1
				speed = math.min(2.0, speed + (o.gain or 0.2))
				zw    = math.max(o.floor or 0.085, zw - (o.shrink or 0.032))
				zc    = 0.14 + math.random() * 0.72
				MG.stroke.Color = Color3.fromRGB(120, 220, 120)
				if onStroke then onStroke(hit) end
			else
				speed = math.max(0.45, speed - 0.08)     -- a miss costs time, not progress
				MG.stroke.Color = Color3.fromRGB(224, 76, 60)
			end
			task.delay(0.18, function() MG.stroke.Color = PAL.BRASS end)
			drawZone()
			MG.count.Text = ("%d / %d"):format(hit, strokes)
			tween(MG.fill, 0.15, { Size = UDim2.new(hit / strokes, 0, 0, 5) })
		end
	end

	conn:Disconnect()
	task.wait(0.25)
	tween(MG.panel, 0.18, { Position = UDim2.new(0.5, -270, 0.84, 0) })
	task.delay(0.2, function() MG.gui.Enabled = false end)
	mgBusy = false
	return true
end

-- ============================================================================
-- STEP 0 -- the burst mains
-- ============================================================================
-- The fountain used to be one 1.4-second hold, which is not a job -- it is a button. The mains
-- that feed it are buried, so PIPE_COUNT of them are dug open around the basin: a pit with its
-- spoil heaped beside it, the pipe exposed and split at the coupling, water going everywhere.
-- Each one is a round of the wrench mini-game, and you walk between them, which is where the
-- time comes from -- about half a minute all in before the valve is worth touching.
--
-- Built from about fifteen blocks apiece. You stand over one of these for eight seconds, so
-- flanges, rust blooms and peeled metal were detail nobody was ever going to look at.
local function buildPipes()
	for i = 1, PIPE_COUNT do
		local a   = (i / PIPE_COUNT) * math.pi * 2 + 0.6
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local at  = center + out * (basinR + 11)
		local y   = groundYAt(at) or groundY
		at = Vector3.new(at.X, y, at.Z)
		local face = CFrame.lookAt(at, at + out)          -- +Z points away from the fountain

		local f = Instance.new("Folder"); f.Name = "Main" .. i; f.Parent = park
		local function bit(props, cf)
			props.Parent = f
			local p = mk(props); p.CFrame = cf; return p
		end

		-- ---- THE PIT. A hole is a floor plus walls, not a dark slab: without the four sides
		-- it reads as a stain painted on the grass.
		bit({ Color = PAL.SOIL_DARK, Size = Vector3.new(6.4, 0.5, 4.6), CanCollide = true },
			face * CFrame.new(0, -1.05, 0))
		for _, sx in ipairs({ -1, 1 }) do
			bit({ Color = PAL.SOIL, Size = Vector3.new(0.6, 1.3, 4.6) }, face * CFrame.new(sx * 2.9, -0.5, 0))
			bit({ Color = PAL.SOIL, Size = Vector3.new(6.4, 1.3, 0.6) }, face * CFrame.new(0, -0.5, sx * 2.0))
		end
		-- one heap of spoil, on one side only -- a ring of it round the hole is the kind of
		-- symmetry nothing in a real dig has
		bit({ Color = PAL.SOIL_DARK, Size = Vector3.new(2.6, 0.8, 2.0) },
			face * CFrame.new(-1.4, 0.3, -3.0) * CFrame.Angles(0, 0.6, 0))

		-- ---- THE MAIN, exposed across the pit and split at the middle. The two halves are
		-- deliberately offset: a clean butt joint does not look burst, it looks unfinished.
		for _, sz in ipairs({ -1, 1 }) do
			bit({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON,
			      Size = Vector3.new(2.9, 1.4, 1.4) },
				face * CFrame.new(0, -0.35, sz * 1.9) * CFrame.Angles(0, math.rad(90), math.rad(sz * 2)))
		end

		local collar = bit({ Shape = Enum.PartType.Cylinder, Color = PAL.RUST,
			Size = Vector3.new(1.2, 2.05, 2.05) },
			face * CFrame.new(0, -0.35, 0) * CFrame.Angles(0, math.rad(90), 0))
		for b = 1, 3 do                                    -- three bolts read as a bolted collar
			bit({ Color = PAL.IRON_D, Size = Vector3.new(1.35, 0.34, 0.34) },
				face * CFrame.new(0, -0.35, 0) * CFrame.Angles(0, math.rad(90), 0)
					* CFrame.Angles((b / 3) * math.pi, 0, 0) * CFrame.new(0, 0.98, 0))
		end
		-- the split is kept, because it is the thing that closes: every landed turn squeezes it
		-- shut, so the pipe reports its own progress without you having to read the HUD
		local split = bit({ Color = Color3.fromRGB(24, 22, 20), Size = Vector3.new(0.4, 1.0, 2.3) },
			face * CFrame.new(0, 0.28, 0))
		local splitCF = split.CFrame

		-- A PRESSURE GAUGE on the pipe, facing the way you walk in from. The HUD tells you how
		-- the tap went; this tells you how the MAIN is doing, which is the thing you are
		-- actually fixing -- and it is still readable from outside the cordon.
		local dial = bit({ Shape = Enum.PartType.Cylinder, Color = PAL.CREAM,
			Size = Vector3.new(0.18, 1.5, 1.5) },
			face * CFrame.new(1.5, 0.55, -1.5) * CFrame.Angles(0, 0, math.rad(90))
				* CFrame.Angles(0, math.rad(90), 0))
		bit({ Color = PAL.BRASS_D, Size = Vector3.new(0.3, 0.9, 0.3) },
			face * CFrame.new(1.5, 0.0, -1.5))
		local gaugeCF = dial.CFrame * CFrame.new(0.12, 0, 0)
		local needle  = Instance.new("Model"); needle.Name = "Needle"; needle.Parent = f
		local nbar = mk({ Color = PAL.RUST, Size = Vector3.new(0.06, 0.12, 1.05),
			CFrame = gaugeCF * CFrame.new(0, 0, 0.42), Parent = needle })
		needle.PrimaryPart = nbar
		needle.WorldPivot  = gaugeCF
		needle:PivotTo(gaugeCF * CFrame.Angles(math.rad(-68), 0, 0))

		-- ---- the puddle it has made, and a cordon so the pit reads from a distance
		local pool = bit({ Color = PAL.WATER_D, Material = Enum.Material.SmoothPlastic,
			Transparency = 0.3, Reflectance = 0.2, Size = Vector3.new(5.4, 0.12, 3.8) },
			face * CFrame.new(0, -0.74, 0))
		for _, sx in ipairs({ -1, 1 }) do
			bit({ Color = PAL.WOOD_D, Size = Vector3.new(0.26, 2.4, 0.26), CanCollide = true },
				face * CFrame.new(sx * 3.4, 1.0, -2.6))
		end
		bit({ Color = PAL.CREAM, Size = Vector3.new(6.8, 0.14, 0.14) },
			face * CFrame.new(0, 1.9, -2.6))

		-- ---- the wrench on the coupling. This is the thing that turns as you work.
		local wrenchCF = face * CFrame.new(0, 1.3, 0)
		local wr = Instance.new("Model"); wr.Name = "Wrench"; wr.Parent = f
		local bar = mk({ Color = PAL.BRASS, Size = Vector3.new(3.6, 0.4, 0.4),
			CFrame = wrenchCF, Parent = wr })
		mk({ Shape = Enum.PartType.Cylinder, Color = PAL.BRASS_D, Size = Vector3.new(0.85, 1.2, 1.2),
			CFrame = wrenchCF * CFrame.Angles(0, 0, math.rad(90)), Parent = wr })
		wr.PrimaryPart = bar
		wr.WorldPivot  = wrenchCF

		-- ---- the leak: a jet out of the split, plus spray settling around the pit
		local host = mk({ Transparency = 1, Size = Vector3.new(1, 1, 1),
			CFrame = face * CFrame.new(0, 0.6, 0), Parent = f })
		local em = Instance.new("ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/smoke_main.dds"
		em.Color = ColorSequence.new(PAL.WATER_G, PAL.WATER_L)
		em.Lifetime = NumberRange.new(0.6, 1.2); em.Rate = 34
		em.Speed = NumberRange.new(18, 30); em.SpreadAngle = Vector2.new(9, 9)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 2.6) })
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1) })
		em.Acceleration = Vector3.new(0, -26, 0)
		em.EmissionDirection = Enum.NormalId.Top
		em.Parent = host

		local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(8, 9, 8),
			CFrame = face * CFrame.new(0, 1.6, 0), Parent = f })
		local pr = Instance.new("ProximityPrompt")
		pr.Name = "PipePrompt"; pr.ActionText = "Repair"
		pr.ObjectText = "Burst Water Main"
		pr.HoldDuration = PIPE_HOLD
		pr.MaxActivationDistance = 13
		pr.RequiresLineOfSight = false
		pr.Enabled = questAccepted
		pr.Parent = hit

		local rec = { turns = 0, prompt = pr, em = em, collar = collar, split = split,
		              scf = splitCF, needle = needle, gcf = gaugeCF,
		              wrench = wr, wcf = wrenchCF, fixed = false }
		pipes[i] = rec

		pr.Triggered:Connect(function(plr)
			if plr ~= player or rec.fixed or mgBusy then return end
			pr.Enabled = false

			-- ONE ROUND OF THE HUD PER PIPE. Each landed stroke turns the wrench a quarter and
			-- takes a third off the leak, so the world keeps pace with the bar rather than
			-- everything happening at the end.
			playWrench({ strokes = PIPE_TURNS, title = "TIGHTEN THE COUPLING",
			             hint = "Tap when the needle is in the green -- it gets tighter",
			             onStroke = function(n)
				playSound(SOUND_VALVE, 0.6)
				local target = rec.wcf * CFrame.Angles(0, math.rad(90) * n, 0)
				task.spawn(function()
					local from = rec.wrench:GetPivot()
					for k = 1, 8 do
						rec.wrench:PivotTo(from:Lerp(target, k / 8))
						task.wait(0.02)
					end
					rec.wrench:PivotTo(target)
				end)
				rec.turns = n
				local p = n / PIPE_TURNS

				-- THE PIPE KICKS. A coupling under pressure does not accept a turn quietly, and
				-- without the jolt the wrench looked like it was turning in air.
				em:Emit(20)
				task.spawn(function()
					for k = 1, 6 do
						local j = math.sin(k / 6 * math.pi) * 0.09
						rec.collar.CFrame = collar.CFrame:Lerp(
							collar.CFrame * CFrame.new(0, j, 0), 0.6)
						task.wait(0.02)
					end
				end)

				-- the split squeezes shut and the gauge comes up off the stop
				tween(rec.split, 0.5, { Size = Vector3.new(0.4, 1.0 - 0.85 * p, 2.3 - 1.5 * p),
				                        CFrame = rec.scf })
				task.spawn(function()
					local from = rec.needle:GetPivot()
					local to   = rec.gcf * CFrame.Angles(math.rad(-68 + 136 * p), 0, 0)
					for k = 1, 12 do
						rec.needle:PivotTo(from:Lerp(to, k / 12))
						task.wait(0.02)
					end
					rec.needle:PivotTo(to)
				end)

				em.Rate = 34 * (1 - p)
				tween(pool, 0.8, { Transparency = 0.3 + 0.7 * p })
			end })

			rec.fixed = true
			em.Rate = 0
			tween(collar, 0.7, { Color = PAL.BRASS })
			tween(rec.split, 0.4, { Transparency = 1 })

			-- a fresh gasket over the join, and the last of the water steams off the hot metal
			local gasket = mk({ Shape = Enum.PartType.Cylinder, Color = PAL.WATER_D,
				Size = Vector3.new(1.45, 2.15, 2.15), Transparency = 1,
				CFrame = collar.CFrame, Parent = f })
			tween(gasket, 0.6, { Transparency = 0.15 })
			local steam = Instance.new("ParticleEmitter")
			steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
			steam.Color = ColorSequence.new(PAL.WATER_G)
			steam.Lifetime = NumberRange.new(0.9, 1.8); steam.Rate = 0
			steam.Speed = NumberRange.new(2, 5); steam.SpreadAngle = Vector2.new(45, 45)
			steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(1, 2.6) })
			steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(1, 1) })
			steam.Acceleration = Vector3.new(0, 3.5, 0)
			steam.Parent = collar
			steam:Emit(26)
			Debris:AddItem(steam, 3)
			pipesFixed += 1
			print(("[Park] main %d sealed (%d/%d)"):format(i, pipesFixed, PIPE_COUNT))

			if pipesFixed >= PIPE_COUNT then
				-- the mains hold pressure, so the valve is finally worth turning
				if valvePrompt then valvePrompt.Enabled = true end
				if npcHead and showBubble then
					showBubble(npcHead, "Mains are holding! Get to the valve!", false)
				end
			end
			if refreshBanner then refreshBanner() end
		end)
	end
	print(("[Park] %d burst mains dug open around the fountain"):format(PIPE_COUNT))
end

-- ============================================================================
-- STEP 1 -- the valve on the fountain
-- ============================================================================
local function restoreFountain()
	if step >= 1 then return end
	step = 1
	_G.parkQuestStep = 1

	startFountain()

	if FOUNTAIN_ONLY then
		-- With steps 2-3 switched off, the fountain IS the whole quest, so the tree wakes here.
		-- When FOUNTAIN_ONLY goes false this moves to the step 3 finale.
		task.delay(2.2, reviveTree)
		refreshBanner()
		return
	end

	-- with the fountain running, the buried mains are live and every gate becomes crankable
	task.delay(2.2, function()
		for _, g in ipairs(gardens) do
			if g.prompt then g.prompt.Enabled = true end
		end
		refreshBanner()
	end)
	refreshBanner()
end

local function wireValvePrompt()
	-- the hit box tracks the fountain's size, but never shrinks below something a player can
	-- comfortably walk up to and trigger
	local w = math.max(7, basinR * 1.6)
	local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(w, math.max(9, basinR * 2), w),
	                 CFrame = CFrame.new(center + Vector3.new(0, basinR * 0.45, 0)), Parent = park })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FountainValvePrompt"
	prompt.ActionText = "Restore the Fountain"
	prompt.ObjectText = "Dried-up Fountain"
	prompt.HoldDuration = 1.4
	prompt.MaxActivationDistance = basinR + 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = hit
	valvePrompt = prompt
	-- Shut until the NPC asks you to turn it. The NPC is looked for asynchronously, so this
	-- can't test npcHead here -- it would always still be nil. The lookup below opens the
	-- valve itself if no quest giver turns up.
	prompt.Enabled = questAccepted and (#pipes == 0 or pipesFixed >= PIPE_COUNT)
	prompt.Triggered:Connect(function(plr)
		if plr ~= player then return end
		prompt.Enabled = false
		restoreFountain()
	end)
end

-- both fallbacks below start the job, and the job now begins at the pits
local function openStep0()
	if #pipes > 0 then
		for _, q in ipairs(pipes) do if q.prompt and not q.fixed then q.prompt.Enabled = true end end
	elseif valvePrompt then
		valvePrompt.Enabled = true
	end
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	park = Instance.new("Folder"); park.Name = "AncientTreePark"; park.Parent = Workspace
	refreshGroundFilter()

	-- StreamingEnabled: 'fountain' is a real PART, so it does NOT reach the client until someone
	-- gets near island 13 -- unlike the empty Models (garden1..3, ancienttree), which replicate
	-- straight away. So we keep looking rather than deciding it's missing on the first sweep.
	-- The island is re-resolved every pass too, because it streams in on the same terms.
	island = findIsland()
	local waited = false
	fountainMark = pollFor(function()
		if not island then island = findIsland() end
		local m = findMarker(FOUNTAIN_NAME, island)
		if not m and not waited then
			waited = true
			print("[Park] waiting for 'fountain' to stream in (fly to island 13 if you're nowhere near it)...")
		end
		return m
	end, 600)

	if not fountainMark then
		warn("[Park] never saw a part named 'fountain'" .. (island and (" in " .. island.Name) or "") ..
		     " -- check the spelling in Studio. (ParkScan lists what the client can actually see.)")
		return
	end

	-- read the marker: position always, width only if FOUNTAIN_RADIUS is switched off
	local fpos, ffoot = readMarker(fountainMark, 28)
	center  = fpos
	groundY = fpos.Y
	basinR  = (FOUNTAIN_RADIUS > 0) and FOUNTAIN_RADIUS or math.max(3, ffoot * 0.5)
	hideMarker(fountainMark)

	print(("[Park] fountain at (%.0f, %.0f, %.0f), basin radius %.1f, island=%s")
		:format(center.X, center.Y, center.Z, basinR, island and island.Name or "?"))

	buildFountain()
	if PIPE_COUNT > 0 then buildPipes() end
	killTree()
	buildOfferAltar()

	if FOUNTAIN_ONLY then
		wireValvePrompt()
		refreshBanner()
		print(("[Park] FOUNTAIN ONLY -- low-poly octagon, basin radius %.1f, about %.1f studs wide and %.1f tall.")
			:format(basinR, basinR * 1.22 * 2, basinR * 2.14))
		print("[Park] change FOUNTAIN_RADIUS at the top of the file to resize it; set FOUNTAIN_ONLY = false for the rest of the quest.")
		return
	end

	-- resolve the three gardens: real markers if you placed them, a triangle around the
	-- fountain if you haven't yet
	for i = 1, 3 do
		local mark = findMarker(GARDEN_NAMES[i], island)
		local g = { index = i, mark = mark }
		if mark then
			-- Take the PIVOT for X/Z and a ray for the ground -- NOT readMarker's top-face
			-- rule. These are real models: garden2's bounding box is 121 studs tall, so its
			-- "top face" would put the plot 60 studs in the air.
			local p = pivotOf(mark).Position
			g.pos  = Vector3.new(p.X, groundYAt(p), p.Z)
			-- the footprint only drives effect sizes (butterfly spread, pollen), and a 200-stud
			-- box would blow those up, so it's clamped to something a player can take in
			local msz = sizeOf(mark)
			g.size = math.clamp(math.min(msz.X, msz.Z), 20, 60)
			-- NOTE: real art is never hidden. hideMarker() is only for bare position markers.
		else
			local a = math.rad(90 + (i - 1) * 120)
			g.pos  = center + Vector3.new(math.cos(a) * GARDEN_DIST, 0, math.sin(a) * GARDEN_DIST)
			g.size = GARDEN_SIZE
		end
		gardens[i] = g
	end

	-- All three gate parts share the name "gate", so they come back as a list and each one is
	-- paired with the garden it stands nearest. Greedy nearest-first: whichever gate/garden
	-- pair is closest anywhere on the board gets matched, then that pair drops out. Assigning
	-- them in index order instead would let the first garden steal a gate that plainly belongs
	-- to another one.
	do
		local gates = findAllMarkers(GATE_NAME, island)
		print(("[Park] found %d part(s) named 'gate'"):format(#gates))
		local taken = {}
		for _ = 1, math.min(#gates, #gardens) do
			local bestG, bestGate, bestD
			for gi, g in ipairs(gardens) do
				if not g.gateMark then
					for ki, k in ipairs(gates) do
						if not taken[ki] then
							local d = ((pivotOf(k).Position - g.pos) * Vector3.new(1, 0, 1)).Magnitude
							if not bestD or d < bestD then bestD, bestG, bestGate = d, gi, ki end
						end
					end
				end
			end
			if not bestG then break end
			gardens[bestG].gateMark = gates[bestGate]
			taken[bestGate] = true
			print(("[Park] gate at %d studs -> garden %d"):format(bestD, bestG))
		end
		for _, g in ipairs(gardens) do
			if not g.gateMark then
				warn(("[Park] garden %d has no 'gate' part -- its gate is auto-placed"):format(g.index))
			end
		end
	end

	for i, g in ipairs(gardens) do
		planRoute(g)                  -- first: it sets channelDir, which the other two need
		prepGarden(g, i)
		buildGate(g, i)
	end

	-- catch crop markers that aren't parented into a garden, now and as they stream in
	adoptStrayCrops()
	task.spawn(function()
		for _ = 1, 60 do
			task.wait(3)
			adoptStrayCrops()
		end
	end)

	wireValvePrompt()
	refreshBanner()

	-- POLL for the NPC rather than looking once. It's a real model on island 13, so with
	-- StreamingEnabled it often hasn't replicated yet at the moment the fountain triggers this
	-- build -- a single look would miss it every time. Same as CandyGumballQuest does.
	task.spawn(function()
		-- Never leave the player standing at a dead fountain while we wait. If no NPC has shown
		-- up within a few seconds the valve opens anyway, and the search carries on in the
		-- background so a late arrival still gets its dialogue wired.
		task.delay(8, function()
			if not npcHead and not questAccepted then
				questAccepted = true
				openStep0()
				print("[Park] no Candy Npc yet -- opening the job so the quest isn't blocked")
				refreshBanner()
			end
		end)

		npcHead = pollFor(findNPCHead, 45)
		if npcHead then
			wireNPC(npcHead)
			print(("[Park] Candy Npc wired -- '%s', %.0f studs from the fountain")
				:format(npcHead.Parent and npcHead.Parent.Name or npcHead.Name,
				        (npcHead.Position - center).Magnitude))
		else
			-- Say WHY. A mis-named or far-off NPC should be obvious in Output, not silent.
			local seen = 0
			for _, d in ipairs(Workspace:GetDescendants()) do
				if (d:IsA("Model") or d:IsA("BasePart")) and string.find(norm(d.Name), "npc", 1, true) then
					seen += 1
					if seen <= 8 then
						local h = npcHeadOf(d)
						print(("[Park]   saw '%s' at %s studs (needs <= %d)"):format(
							d.Name,
							h and ("%.0f"):format((h.Position - center).Magnitude) or "?",
							NPC_MAX_DIST))
					end
				end
			end
			warn(("[Park] no Candy Npc found near the park -- valve opens without one (%d npc-ish name(s) in Workspace)")
				:format(seen))
			questAccepted = true                      -- never lock the player out
			openStep0()
		end
		refreshBanner()
	end)

	local placed = 0
	for _, g in ipairs(gardens) do if g.mark then placed += 1 end end
	print(("[Park] built: fountain + 3 gates, gardens=%d (%d from markers, %d auto-placed); irrigation is underground")
		:format(#gardens, placed, #gardens - placed))
	if placed < 3 then
		print("[Park] name parts garden1/garden2/garden3 in the island to place the plots yourself.")
	end
	print("[Park] all 3 steps live -- valve -> 3 gates -> the tree wakes on its own.")
end)
