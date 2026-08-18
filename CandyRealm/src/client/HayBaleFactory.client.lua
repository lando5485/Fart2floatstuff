--======================================================================
-- HAY BALE FACTORY  (island19)
--======================================================================
-- Turns the blank block you named "factory" into a working-looking farm building:
--
--     GIANT WHEAT FIELD  ->  HAY BALE FACTORY  ->  HAY BALES
--
-- ⚠ WHY THIS IS ITS OWN SCRIPT AND NOT PART OF THE TRACTOR QUEST
-- BrokenTractorQuest_AllInOne sits at 196 of Luau's 200 registers for a main chunk. Going over
-- is a COMPILE failure -- the file silently never runs and island19 loses its entire quest. This
-- is scenery, it shares no state with the quest, so it gets its own file and its own 200.
--
-- WHAT IT READS AND WHAT IT NEVER TOUCHES
-- It reads ONE part -- yours, named "factory" -- for position, footprint and rotation, then
-- hides it. The wheat field, barn, paths, fences, apple trees and island layout are never
-- written to. Everything built lands in a single Folder that can be deleted in one click.
--======================================================================

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local Workspace     = game:GetService("Workspace")

local ISLAND_NAME = "island19"
local MARKER_NAME = "factory"

-- (!) SIZE GUARD. Names lie: an island's floor slab has been named things like "chicken zone"
-- and "placement boundaires" in this place, and hiding one of those deletes the ground people
-- are standing on. A factory block is a building footprint, so it has to be within these bounds
-- or we refuse to touch it and say why.
local MARKER_MIN =  14
local MARKER_MAX = 220

-- palette -- warm wood, cream trim, straw gold. The roof is deliberately NOT the barn's red:
-- two red farm buildings 70 studs apart read as one building seen twice.
local WOOD      = Color3.fromRGB(150, 104,  62)
local WOOD_D    = Color3.fromRGB(112,  76,  44)
local WOOD_L    = Color3.fromRGB(178, 130,  82)
local CREAM     = Color3.fromRGB(248, 240, 222)
local ROOF      = Color3.fromRGB( 78, 142,  56)
local ROOF_D    = Color3.fromRGB( 58, 108,  42)
local STRAW     = Color3.fromRGB(226, 186,  86)
local STRAW_D   = Color3.fromRGB(190, 148,  60)
local TWINE     = Color3.fromRGB(140, 108,  52)
local IRON      = Color3.fromRGB( 84,  80,  84)
local IRON_D    = Color3.fromRGB( 58,  55,  60)
local RUBBER    = Color3.fromRGB( 46,  44,  48)
local TEXTC     = Color3.fromRGB( 66,  48,  20)
local SIGN_BG   = Color3.fromRGB(196, 140,  74)

-- ⚠ NOTHING IS PRE-PLACED IN THE YARD ANY MORE. There used to be seven bales scattered out front
-- and a stack of six beside the building, put there at boot so the place looked like it had been
-- working. The trouble is that they are indistinguishable from bales somebody actually pressed:
-- the yard was full before anyone had done anything, so pressing one added nothing you could see
-- and the console's whole job became invisible. Every bale in the yard is now one that was made
-- -- by you, or by another player at the same console (see the shared-bale relay at the bottom).
local YARD_BALES  = 0      -- decorative bales at boot: none, on purpose. See the note above.
local STACK_BALES = 0      -- the stack beside the building: same reason
local MAX_MADE    = 14     -- pressed bales kept in the yard before the oldest is retired
local STRAW_EVERY = 0.9    -- seconds between straw clumps entering the belt
-- The machine's working noise -- the SAME id the tractor's cutting bar uses, and treated the same
-- way: one looped Sound whose VOLUME is faded up while the line is actually doing something. It is
-- the right sound twice over (a bar chewing straw, a press chewing straw) and it ties the two
-- halves of the harvest together by ear.
local SOUND_MACHINE = "rbxassetid://136646841190295"
local STRAW_NEED  = 3      -- straw wads in the hopper that one bale costs
local STRAW_CAP   = 9      -- the hopper holds this much and no more
local PANEL_RANGE = 26     -- walk further than this from the console and the panel closes

--======================================================================
-- SMALL HELPERS
--======================================================================
local function norm(s) return (tostring(s):lower():gsub("[%s_%-]", "")) end

local folder                       -- everything we build lives here
local function mk(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true               -- (!) every part, always: this island is CFrame-driven and a
	p.CanCollide = false            -- single unanchored prop falls through the world at boot
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent or folder
	return p
end

-- a low-poly wedge, for roof ends
local function wedge(props, parent)
	local p = Instance.new("WedgePart")
	p.Anchored = true; p.CanCollide = false; p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent or folder
	return p
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundY(pos, fallback)
	-- our own build is excluded or the first bale we drop becomes the "ground" for the next one
	local hit = Workspace:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -600, 0), rayParams)
	return hit and hit.Position.Y or fallback
end

local function poof(pos, colour, n)
	for i = 1, n do
		local bit = mk({ Size = Vector3.new(0.7, 0.7, 0.7), Color = colour,
			Material = Enum.Material.SmoothPlastic, Transparency = 0.2 })
		bit.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.9, math.random() - 0.5).Unit
		task.spawn(function()
			for k = 0, 1, 0.06 do
				if not bit.Parent then return end
				bit.CFrame = bit.CFrame + dir * 0.5
				bit.Transparency = 0.2 + k * 0.8
				task.wait(0.02)
			end
			bit:Destroy()
		end)
		if i > 12 then break end
	end
end

--======================================================================
-- FIND THE ISLAND AND YOUR BLOCK
--======================================================================
local function findFirst(root, wanted)
	for _, d in ipairs(root:GetDescendants()) do
		if norm(d.Name) == wanted and d:IsA("BasePart") then return d end
	end
	return nil
end

local island, marker
for _ = 1, 90 do                       -- bounded: never an indefinite block on streamed content
	island = Workspace:FindFirstChild(ISLAND_NAME)
	if island then
		marker = findFirst(island, MARKER_NAME)
		if marker then break end
	end
	task.wait(1)
end

if not marker then
	warn(("[Factory] no BasePart named '%s' found inside Workspace.%s after 90s -- nothing built. "
		.. "Name the blank block 'factory' and make sure it is INSIDE the island model.")
		:format(MARKER_NAME, ISLAND_NAME))
	return
end

local mSize = marker.Size
if mSize.X < MARKER_MIN or mSize.Z < MARKER_MIN or mSize.X > MARKER_MAX or mSize.Z > MARKER_MAX then
	warn(("[Factory] '%s' is %.0f x %.0f studs, outside the sane range %d..%d -- REFUSING to build "
		.. "on it or hide it. A part that big is usually an island floor or a boundary volume, and "
		.. "hiding one deletes ground people stand on.")
		:format(marker:GetFullName(), mSize.X, mSize.Z, MARKER_MIN, MARKER_MAX))
	return
end

folder = Instance.new("Folder")
folder.Name = "HayBaleFactory"
folder.Parent = island                 -- inside the island Model so it inherits Persistent streaming
rayParams.FilterDescendantsInstances = { folder, marker }

--======================================================================
-- FOOTPRINT AND ORIENTATION
--======================================================================
-- The building takes the block's exact centre, rotation and X/Z footprint. Height is derived
-- from the footprint rather than from the block, because these marker blocks are usually flat
-- slabs and a 2-stud-tall factory is not a factory.
--
-- BUILD_YAW turns the WHOLE factory about the block's centre, in degrees, positive =
-- counter-clockwise seen from above. Every part below -- shell, roof, sign, belt, press, output
-- line, yard and stack -- is placed off baseCF or off the FACES derived from it, so this single
-- number rotates the entire thing as one piece. The block itself is still never moved.
local BUILD_YAW = 90

local baseCF = marker.CFrame * CFrame.Angles(0, math.rad(BUILD_YAW), 0)
-- a quarter turn swaps which footprint axis lies along the rotated frame's X, so the shell keeps
-- covering the block instead of hanging off its long sides
if (BUILD_YAW % 180) ~= 0 then mSize = Vector3.new(mSize.Z, mSize.Y, mSize.X) end
local baseY  = marker.Position.Y - mSize.Y * 0.5    -- seated on the block's BASE, not its top
local halfX, halfZ = mSize.X * 0.5, mSize.Z * 0.5
local WALL_H = math.clamp(math.min(mSize.X, mSize.Z) * 0.62, 16, 38)
local ROOF_H = WALL_H * 0.45

-- where's the path, and where's the wheat?
local function nearestNamed(names, from)
	local best, bestD
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and not d:IsDescendantOf(folder) then
			local n = norm(d.Name)
			for _, want in ipairs(names) do
				if n == want or n:find(want, 1, true) then
					local dist = (d.Position - from).Magnitude
					if not bestD or dist < bestD then best, bestD = d, dist end
					break
				end
			end
		end
	end
	return best
end

local centre    = Vector3.new(baseCF.Position.X, baseY, baseCF.Position.Z)
local pathPart  = nearestNamed({ "path", "walkway", "road", "trail" }, centre)
local wheatPart = nearestNamed({ "wheatplant", "wheat" }, centre)

-- The four faces of the block, as outward directions with the half-extent along each.
local FACES = {
	{ dir =  baseCF.RightVector, ext = halfX, side = halfZ },
	{ dir = -baseCF.RightVector, ext = halfX, side = halfZ },
	{ dir =  baseCF.LookVector,  ext = halfZ, side = halfX },
	{ dir = -baseCF.LookVector,  ext = halfZ, side = halfX },
}

-- (!) BUILD_YAW has to reach the face CHOICE too, not just the shell. The four faces are picked by
-- world direction, so on a square block a rotated baseCF alone would re-pick the same world face
-- and the entrance, belt, press and yard would not move at all. Turning the target by the same
-- yaw picks the face that pointed there BEFORE the rotation, and that face is now a quarter turn
-- round -- which is what makes the whole assembly rotate rigidly instead of just the box.
local YAW_CF = CFrame.Angles(0, math.rad(BUILD_YAW), 0)

local function faceToward(target, exclude)
	if not target then return nil end
	local to = (Vector3.new(target.X, 0, target.Z) - Vector3.new(centre.X, 0, centre.Z))
	if to.Magnitude < 0.1 then return nil end
	to = YAW_CF:VectorToWorldSpace(to).Unit
	local best, bestDot
	for i, f in ipairs(FACES) do
		if i ~= exclude then
			local d = f.dir:Dot(to)
			if not bestDot or d > bestDot then best, bestDot = i, d end
		end
	end
	return best
end

-- THE ENTRANCE FACES THE PATH. That is the one thing a player uses to find the door, so it wins
-- outright; the wheat side is chosen afterwards from whatever is left.
local frontIdx = faceToward(pathPart and pathPart.Position or nil)
	or faceToward(wheatPart and wheatPart.Position or nil)
	or 1
-- ...and the intake faces the wheat, but never through the doorway -- straw pouring in through
-- the entrance the player walks in by would read as a blocked door, not a feed line.
local intakeIdx = faceToward(wheatPart and wheatPart.Position or nil, frontIdx)
	or (frontIdx % 4) + 1
if intakeIdx == frontIdx then intakeIdx = (frontIdx % 4) + 1 end

local FRONT, INTAKE = FACES[frontIdx], FACES[intakeIdx]
local outward   = FRONT.dir                       -- points out of the entrance
local sideward  = INTAKE.dir                      -- points out of the intake wall

-- a frame sitting at the middle of the doorway, facing out
local function at(x, y, z)                        -- block-local -> world
	return (baseCF * CFrame.new(x, 0, z)).Position + Vector3.new(0, baseY + y - baseCF.Position.Y, 0)
end

local doorW = math.clamp(FRONT.side * 0.9, 12, 34)
local doorH = WALL_H * 0.72

--======================================================================
-- THE SHELL
--======================================================================
local WALL_T = 1.6

local function faceCF(f, y, along)
	-- a CFrame on face f, `along` studs sideways from its middle, y studs up from the base
	local right = Vector3.new(-f.dir.Z, 0, f.dir.X)
	local pos = Vector3.new(centre.X, baseY + y, centre.Z) + f.dir * f.ext + right * along
	return CFrame.lookAt(pos, pos + f.dir)
end

-- floor
mk({ Name = "Floor", Size = Vector3.new(mSize.X, 1, mSize.Z), Color = WOOD_D,
	Material = Enum.Material.WoodPlanks, CanCollide = true,
	CFrame = baseCF * CFrame.new(0, baseY + 0.5 - baseCF.Position.Y, 0) })

-- three solid walls + the front wall as two piers and a lintel, which is what leaves a LARGE
-- OPEN ENTRANCE rather than a door-sized hole
for i, f in ipairs(FACES) do
	local w = f.side * 2
	if i ~= frontIdx then
		local wall = mk({ Name = "Wall", Size = Vector3.new(w, WALL_H, WALL_T), Color = WOOD,
			Material = Enum.Material.WoodPlanks, CanCollide = true })
		wall.CFrame = faceCF(f, WALL_H * 0.5, 0)
		-- rustic: THREE proud battens, not five, and wider. Five thin strips on every wall was
		-- busy from close up and invisible from far off -- the worst of both. Three broad ones
		-- give the wall a rhythm you can read from the yard.
		for k = -1, 1 do
			mk({ Name = "Batten", Size = Vector3.new(2.2, WALL_H * 0.94, 0.55),
				Color = (k == 0) and WOOD_L or WOOD_D, Material = Enum.Material.Wood,
				CFrame = faceCF(f, WALL_H * 0.5, k * (w / 3.4)) * CFrame.new(0, 0, -1.0) })
		end
	else
		local pierW = (w - doorW) * 0.5
		for _, sgn in ipairs({ -1, 1 }) do
			mk({ Name = "Pier", Size = Vector3.new(pierW, WALL_H, WALL_T), Color = WOOD,
				Material = Enum.Material.WoodPlanks, CanCollide = true,
				CFrame = faceCF(f, WALL_H * 0.5, sgn * (doorW + pierW) * 0.5) })
		end
		mk({ Name = "Lintel", Size = Vector3.new(doorW + 2, WALL_H - doorH, WALL_T + 0.4),
			Color = WOOD_D, Material = Enum.Material.WoodPlanks, CanCollide = true,
			CFrame = faceCF(f, doorH + (WALL_H - doorH) * 0.5, 0) })
		-- doorway posts, so the opening reads as a built entrance
		for _, sgn in ipairs({ -1, 1 }) do
			mk({ Name = "DoorPost", Size = Vector3.new(1.6, doorH, 2.2), Color = WOOD_D,
				Material = Enum.Material.Wood,
				CFrame = faceCF(f, doorH * 0.5, sgn * doorW * 0.5) })
		end
	end
end

-- corner posts
for _, sx in ipairs({ -1, 1 }) do
	for _, sz in ipairs({ -1, 1 }) do
		mk({ Name = "Post", Size = Vector3.new(2.2, WALL_H + 1, 2.2), Color = WOOD_D,
			Material = Enum.Material.Wood,
			CFrame = baseCF * CFrame.new(sx * halfX, baseY + (WALL_H + 1) * 0.5 - baseCF.Position.Y, sz * halfZ) })
	end
end

-- ===== THE CEILING =====
-- (!) THE BUILDING WAS OPEN AT THE TOP. There is a gable roof above this, but a gable is two
-- sloped slabs and a ridge -- it seals the SILHOUETTE, not the room. From above, and from any
-- camera that swung over the wall, you were looking straight down into the machinery through the
-- triangle at each end.
--
-- So: one flat deck across the whole wall footprint, sat on top of the walls, in the wall's own
-- timber so it reads as the underside of a floor above rather than as a lid. It is OVERSIZED by
-- the wall thickness on both axes, which is what closes the hairline at every edge and corner --
-- an exactly-sized slab leaves four seams you can see daylight through.
mk({ Name = "Ceiling", Size = Vector3.new(mSize.X + WALL_T * 2, 1.2, mSize.Z + WALL_T * 2),
	Color = WOOD, Material = Enum.Material.WoodPlanks, CanCollide = true,
	CFrame = baseCF * CFrame.new(0, baseY + WALL_H + 0.6 - baseCF.Position.Y, 0) })
-- two beams under it, across the shorter span: without them a 40-stud ceiling reads as a lid
for _, sgn in ipairs({ -1, 1 }) do
	local along = (mSize.X >= mSize.Z)
	mk({ Name = "CeilingBeam",
		Size = along and Vector3.new(mSize.X, 1.1, 1.6) or Vector3.new(1.6, 1.1, mSize.Z),
		Color = WOOD_D, Material = Enum.Material.Wood,
		CFrame = baseCF * CFrame.new(along and 0 or (sgn * halfX * 0.45),
			baseY + WALL_H - 0.6 - baseCF.Position.Y,
			along and (sgn * halfZ * 0.45) or 0) })
end

-- ===== GABLE ROOF =====
-- The ridge runs along the LONGER axis, which is what makes a rectangular building look built
-- rather than extruded. Two sloped slabs and two wedge ends: four parts, unmistakably a roof.
local ridgeAlongX = mSize.X >= mSize.Z
local ridgeLen    = (ridgeAlongX and mSize.X or mSize.Z) + 4
local slopeRun    = (ridgeAlongX and halfZ or halfX) + 2
local slopeLen    = math.sqrt(slopeRun * slopeRun + ROOF_H * ROOF_H)
local pitch       = math.atan2(ROOF_H, slopeRun)

for _, sgn in ipairs({ -1, 1 }) do
	local off = ridgeAlongX and CFrame.new(0, 0, sgn * slopeRun * 0.5)
		or CFrame.new(sgn * slopeRun * 0.5, 0, 0)
	local rot = ridgeAlongX and CFrame.Angles(-sgn * pitch, 0, 0)
		or CFrame.Angles(0, 0, sgn * pitch)
	local size = ridgeAlongX and Vector3.new(ridgeLen, 1.2, slopeLen)
		or Vector3.new(slopeLen, 1.2, ridgeLen)
	mk({ Name = "Roof", Size = size, Color = ROOF, Material = Enum.Material.Metal,
		CFrame = baseCF * CFrame.new(0, baseY + WALL_H + ROOF_H * 0.5 - baseCF.Position.Y, 0) * off * rot })
end
mk({ Name = "Ridge", Size = ridgeAlongX and Vector3.new(ridgeLen, 1.4, 1.8)
		or Vector3.new(1.8, 1.4, ridgeLen), Color = ROOF_D, Material = Enum.Material.Metal,
	CFrame = baseCF * CFrame.new(0, baseY + WALL_H + ROOF_H - baseCF.Position.Y, 0) })

-- gable triangles close the two ends
for _, sgn in ipairs({ -1, 1 }) do
	local endDist = (ridgeAlongX and halfX or halfZ)
	for _, half in ipairs({ -1, 1 }) do
		local w = wedge({ Name = "Gable", Size = Vector3.new(1.2, ROOF_H, slopeRun),
			Color = WOOD_L, Material = Enum.Material.WoodPlanks })
		local pos = ridgeAlongX and CFrame.new(sgn * endDist, 0, 0) or CFrame.new(0, 0, sgn * endDist)
		local spin = ridgeAlongX and CFrame.Angles(0, math.rad(half > 0 and 90 or -90), 0)
			or CFrame.Angles(0, half > 0 and 0 or math.rad(180), 0)
		w.CFrame = baseCF * CFrame.new(0, baseY + WALL_H - baseCF.Position.Y, 0) * pos * spin
			* CFrame.new(0, ROOF_H * 0.5, -slopeRun * 0.5)
	end
end

--======================================================================
-- WHAT MAKES IT A BUILDING RATHER THAN A BOX WITH A LID
--======================================================================
-- Everything below here is silhouette and surface: corrugation, a vented ridge cap, gable
-- windows, a barn lamp over the door and a bracing rail down each long wall. None of it changes
-- the shape -- it changes whether the shape reads as CORRUGATED IRON ON A TIMBER FRAME, which is
-- what a hay barn is, or as three grey slabs.

-- ===== STANDING SEAMS, NOT CORRUGATION =====
-- This started as a rib every 2.4 studs, which at any distance turns the roof into grey mush and
-- reads as "somebody had a loop handy". A real metal roof of this size has a seam every few feet
-- and they are BOLD -- so: a third as many, twice as wide. Fewer, bigger, and it still says metal
-- from the far side of the field, which corrugation never did.
do
	local ribs = math.clamp(math.floor(ridgeLen / 7), 3, 9)
	for _, sgn in ipairs({ -1, 1 }) do
		local off = ridgeAlongX and CFrame.new(0, 0, sgn * slopeRun * 0.5)
			or CFrame.new(sgn * slopeRun * 0.5, 0, 0)
		local rot = ridgeAlongX and CFrame.Angles(-sgn * pitch, 0, 0)
			or CFrame.Angles(0, 0, sgn * pitch)
		local slopeCF = baseCF * CFrame.new(0, baseY + WALL_H + ROOF_H * 0.5 - baseCF.Position.Y, 0)
			* off * rot
		for i = 0, ribs do
			local t = (i / ribs - 0.5) * (ridgeLen - 1)
			local size = ridgeAlongX and Vector3.new(1.1, 0.55, slopeLen - 0.4)
				or Vector3.new(slopeLen - 0.4, 0.55, 1.1)
			local at = ridgeAlongX and CFrame.new(t, 0.7, 0) or CFrame.new(0, 0.7, t)
			mk({ Name = "RoofRib", Size = size, Color = ROOF_D, Material = Enum.Material.Metal,
				CFrame = slopeCF * at })
		end
	end
end

-- a vented ridge cap: the hoods along the top of every hay barn, because stored hay has to
-- breathe or it cooks. TWO OR THREE, not eight -- a row of little boxes all the way along was
-- fussy at every distance and read as a texture rather than as a piece of the building.
do
	local vents = math.clamp(math.floor(ridgeLen / 16), 1, 3)
	for i = 1, vents do
		local t = (i / (vents + 1) - 0.5) * (ridgeLen - 4)
		local at = ridgeAlongX and CFrame.new(t, 0, 0) or CFrame.new(0, 0, t)
		local size = ridgeAlongX and Vector3.new(3.2, 1.4, 2.6) or Vector3.new(2.6, 1.4, 3.2)
		mk({ Name = "RidgeVent", Size = size, Color = ROOF_D, Material = Enum.Material.Metal,
			CFrame = baseCF * CFrame.new(0, baseY + WALL_H + ROOF_H + 0.9 - baseCF.Position.Y, 0) * at })
		mk({ Name = "RidgeVentSlot", Size = ridgeAlongX and Vector3.new(3.0, 0.4, 2.8)
				or Vector3.new(2.8, 0.4, 3.0), Color = Color3.fromRGB(30, 30, 32),
			CFrame = baseCF * CFrame.new(0, baseY + WALL_H + ROOF_H + 0.5 - baseCF.Position.Y, 0) * at })
	end
end

-- gable windows, one in each end, with a cross frame. Dark glass: a lit window would fight the
-- lamp over the door for attention and there is nobody in the loft.
for _, sgn in ipairs({ -1, 1 }) do
	local endDist = (ridgeAlongX and halfX or halfZ) - 0.4
	local at = ridgeAlongX and CFrame.new(sgn * endDist, 0, 0) or CFrame.new(0, 0, sgn * endDist)
	local pane = ridgeAlongX and Vector3.new(0.4, 3.2, 3.2) or Vector3.new(3.2, 3.2, 0.4)
	local barV = ridgeAlongX and Vector3.new(0.6, 3.4, 0.4) or Vector3.new(0.4, 3.4, 0.6)
	local barH = ridgeAlongX and Vector3.new(0.6, 0.4, 3.4) or Vector3.new(3.4, 0.4, 0.6)
	local origin = baseCF * CFrame.new(0, baseY + WALL_H + ROOF_H * 0.42 - baseCF.Position.Y, 0) * at
	mk({ Name = "LoftGlass", Size = pane, Color = Color3.fromRGB(58, 62, 70),
		Material = Enum.Material.Glass, Reflectance = 0.1, CFrame = origin })
	mk({ Name = "LoftFrameV", Size = barV, Color = WOOD_D, Material = Enum.Material.Wood,
		CFrame = origin })
	mk({ Name = "LoftFrameH", Size = barH, Color = WOOD_D, Material = Enum.Material.Wood,
		CFrame = origin })
end

--======================================================================
-- THE SIGN
--======================================================================
-- A physical board with a SurfaceGui, not a floating BillboardGui: it belongs to the building,
-- so it should scale and rotate with it and be readable from an angle like real signage.
local signW = math.min(doorW + 6, FRONT.side * 1.8)
local board = mk({ Name = "Sign", Size = Vector3.new(signW, signW * 0.24, 1),
	Color = SIGN_BG, Material = Enum.Material.WoodPlanks,
	CFrame = faceCF(FRONT, doorH + (WALL_H - doorH) * 0.5, 0) * CFrame.new(0, 0, -1.3) })
mk({ Name = "SignFrame", Size = Vector3.new(signW + 1.4, signW * 0.24 + 1.4, 0.6),
	Color = WOOD_D, Material = Enum.Material.Wood,
	CFrame = board.CFrame * CFrame.new(0, 0, 0.5) })

local sg = Instance.new("SurfaceGui")
sg.Name = "SignText"
sg.Face = Enum.NormalId.Front            -- a part's Front IS its -Z, which is its LookVector
sg.CanvasSize = Vector2.new(800, 200)
sg.LightInfluence = 0                    -- readable at dusk and under the roof's shadow
sg.AlwaysOnTop = false
sg.Parent = board

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Font = Enum.Font.FredokaOne
label.Text = "HAY BALE FACTORY"
label.TextColor3 = CREAM
label.TextStrokeColor3 = TEXTC
label.TextStrokeTransparency = 0
label.TextScaled = true
label.Parent = sg

--======================================================================
-- THE DOORWAY, DRESSED
--======================================================================
-- A gooseneck lamp on a bracket over the door, always on. It does three jobs at once: it lights
-- the sign, it makes the entrance the brightest thing on this side of the building at dusk, and
-- it is the one warm colour on a green-and-timber machine shed.
do
	local armCF = faceCF(FRONT, doorH + (WALL_H - doorH) * 0.82, 0) * CFrame.new(0, 0, -2.2)
	mk({ Name = "LampArm", Size = Vector3.new(0.4, 0.4, 3.0), Color = IRON_D,
		Material = Enum.Material.Metal, CFrame = armCF })
	local shade = mk({ Name = "LampShade", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.9, 2.4, 2.4), Color = Color3.fromRGB(196, 78, 62),
		Material = Enum.Material.Metal,
		CFrame = armCF * CFrame.new(0, -0.3, -1.4) * CFrame.Angles(0, 0, math.rad(90)) })
	local bulb = mk({ Name = "LampBulb", Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.9, 0.9, 0.9), Color = Color3.fromRGB(255, 236, 190),
		Material = Enum.Material.Neon, CFrame = shade.CFrame * CFrame.new(-0.5, 0, 0) })
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(255, 224, 168); pl.Brightness = 2.2; pl.Range = 26
	pl.Parent = bulb
end

-- a bracing rail down each long wall, at cart height. Every working shed has one, and it is what
-- stops a long blank wall reading as a single flat panel from the side.
for i, f in ipairs(FACES) do
	if i ~= frontIdx then
		mk({ Name = "WallRail", Size = Vector3.new(f.side * 2 - 1, 0.7, 0.6), Color = WOOD_D,
			Material = Enum.Material.Wood,
			CFrame = faceCF(f, WALL_H * 0.34, 0) * CFrame.new(0, 0, -1.1) })
	end
end

--======================================================================
-- A HAY BALE
--======================================================================
-- Four parts: the block, two twine bands and a cut end. Anything more is detail nobody reads at
-- the distance these are seen from, and there are twenty of them.
local BALE = Vector3.new(7, 5, 5)

local function makeBale(cf, parent)
	local m = Instance.new("Model")
	m.Name = "HayBale"
	m.Parent = parent or folder

	local body = mk({ Name = "Body", Size = BALE, Color = STRAW,
		Material = Enum.Material.Grass, CanCollide = true, CFrame = cf }, m)
	m.PrimaryPart = body
	for _, sgn in ipairs({ -0.22, 0.22 }) do
		mk({ Name = "Twine", Size = Vector3.new(0.4, BALE.Y + 0.25, BALE.Z + 0.25), Color = TWINE,
			Material = Enum.Material.Fabric, CFrame = cf * CFrame.new(sgn * BALE.X, 0, 0) }, m)
	end
	mk({ Name = "CutEnd", Size = Vector3.new(0.35, BALE.Y * 0.86, BALE.Z * 0.86), Color = STRAW_D,
		Material = Enum.Material.Grass, CFrame = cf * CFrame.new(BALE.X * 0.5, 0, 0) }, m)
	return m
end

--======================================================================
-- THE MACHINE: intake belt -> press -> output table
--======================================================================
-- ⚠ THE WHOLE LINE LIVES INSIDE THE BUILDING. It did not: the belt was 26 studs long and started
-- OUTSIDE the intake wall, so half the machine stood in the grass with a wall through the middle
-- of it, and the output table ran out the far side. A factory whose machinery is outdoors is not
-- a factory, it is a yard with a shed in it.
--
-- Everything below is now measured from the INTERIOR, which is the footprint minus the walls and
-- a stud of clearance. The line runs BACK-WALL -> PRESS -> DOORWAY along the same axis the door
-- faces, so from the entrance you look straight down it: straw comes in behind the press, the
-- press is in the middle, and finished bales roll out past your feet.
--
--   DEPTH  -- half the interior, along the door's axis (outward)
--   WIDTH  -- half the interior, across it
-- Both are floored at a few studs so a small marker block still produces a machine rather than
-- a pile of parts folded through each other.
local DEPTH = math.max(6, FRONT.ext - WALL_T - 1.5)
local WIDTH = math.max(5, FRONT.side - WALL_T - 1.5)
-- and the machine is sized to the room it is in, not to a constant that happened to fit one block
local MSC   = math.clamp(math.min(WIDTH, DEPTH) / 11, 0.5, 1.15)

local rightOfIntake = Vector3.new(-outward.Z, 0, outward.X)   -- across the line, inside the walls
local floorMid = Vector3.new(centre.X, baseY, centre.Z)

local BELT_H   = 4.2 * MSC
local beltDir  = outward                          -- straw travels from the back wall to the press
-- the belt ENDS AT THE PRESS'S MOUTH, and the length is solved rather than picked: the press sits
-- at DEPTH*0.06 with its mouth 6.2*MSC behind it, the belt starts a stud off the back wall, and
-- the gap between those two is exactly how long the belt has to be. Pick a number instead and it
-- either stops short of the machine or runs through it.
local BELT_LEN = math.max(6, DEPTH * 1.06 - 1 - 6.2 * MSC)
local beltStart = floorMid + outward * -(DEPTH - 1)           -- hard against the back wall, inside
local intakeMid = beltStart + outward * BELT_LEN              -- the mouth: where it feeds the press

-- legs and frame
for k = 0, 3 do
	local p = beltStart + beltDir * (BELT_LEN * k / 3)
	for _, sgn in ipairs({ -1, 1 }) do
		mk({ Name = "BeltLeg", Size = Vector3.new(0.9, BELT_H, 0.9) * MSC, Color = IRON_D,
			Material = Enum.Material.Metal,
			CFrame = CFrame.new(p + rightOfIntake * sgn * 2.6 * MSC + Vector3.new(0, BELT_H * 0.5, 0)) })
	end
end

local beltMid = beltStart + beltDir * (BELT_LEN * 0.5)
local beltCF  = CFrame.lookAt(beltMid + Vector3.new(0, BELT_H, 0), beltMid + Vector3.new(0, BELT_H, 0) + beltDir)
mk({ Name = "Belt", Size = Vector3.new(6 * MSC, 0.8, BELT_LEN), Color = RUBBER,
	Material = Enum.Material.SmoothPlastic, CFrame = beltCF })
for _, sgn in ipairs({ -1, 1 }) do
	mk({ Name = "BeltRail", Size = Vector3.new(0.6, 1.6 * MSC, BELT_LEN), Color = IRON,
		Material = Enum.Material.Metal, CFrame = beltCF * CFrame.new(sgn * 3.1 * MSC, 0.5, 0) })
end
-- rollers: the belt reads as moving because these turn, which is cheaper and clearer than
-- trying to scroll a texture
local rollers = {}
for k = 0, 6 do
	local r = mk({ Name = "Roller", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6.2 * MSC, 1.3 * MSC, 1.3 * MSC), Color = IRON,
		Material = Enum.Material.Metal,
		CFrame = beltCF * CFrame.new(0, 0.55, -BELT_LEN * 0.5 + 2 + k * ((BELT_LEN - 4) / 6))
			* CFrame.Angles(0, 0, math.rad(90)) })
	rollers[#rollers + 1] = r
end

-- ===== THE DRIVE END =====
-- A belt with nothing driving it is a ramp. This is the motor that turns it: a housing, a big
-- drive pulley on the head shaft (added to `rollers`, so it turns with everything else), a belt
-- guard over the vee-belt, and the vee-belt itself running down to the motor. Four parts, and
-- the line stops being scenery and starts being powered.
do
	local headCF = beltCF * CFrame.new(0, 0, BELT_LEN * 0.5 - 0.6)
	-- the motor stands off to the side of the belt head, and that side is clamped to the room:
	-- on a narrow footprint it tucks in tight rather than being planted through the wall
	local side = math.min(4.2 * MSC, math.max(2.6, WIDTH - 2.5))
	local pulley = mk({ Name = "DrivePulley", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6.6 * MSC, 2.6 * MSC, 2.6 * MSC), Color = IRON_D,
		Material = Enum.Material.Metal,
		CFrame = headCF * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)) })
	rollers[#rollers + 1] = pulley
	mk({ Name = "MotorBed", Size = Vector3.new(3.4, 0.5, 3.0) * MSC, Color = IRON_D,
		Material = Enum.Material.Metal, CFrame = headCF * CFrame.new(side, -BELT_H + 0.4, 0) })
	mk({ Name = "Motor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.0, 2.2, 2.2) * MSC,
		Color = ROOF_D, Material = Enum.Material.Metal,
		CFrame = headCF * CFrame.new(side, -BELT_H + 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)) })
	-- ONE vee-belt, and nothing else down here. There was also a cooling fan and a translucent
	-- guard: three small fiddly shapes stacked in the same 4 studs, which from any real viewing
	-- distance was a grey smudge beside the motor. The belt alone says "this is driven".
	mk({ Name = "VeeBelt", Size = Vector3.new(0.5, 4.6 * MSC, 1.2 * MSC), Color = RUBBER,
		Material = Enum.Material.SmoothPlastic,
		CFrame = headCF * CFrame.new(side * 0.72, -BELT_H * 0.5 + 1.0, 0)
			* CFrame.Angles(0, 0, math.rad(-24)) })
end

-- ===== THE PRESS =====
-- Stood in the middle of the floor, facing BACK down the belt, so its mouth meets the straw and
-- its output side faces the doorway. Sized to the room (MSC) and its height capped under the
-- wall, because a press taller than the shed it stands in used to punch out through the roof.
local pressPos = floorMid + outward * (DEPTH * 0.06)
local pressCF  = CFrame.lookAt(pressPos + Vector3.new(0, 7 * MSC, 0),
	pressPos + Vector3.new(0, 7 * MSC, 0) - outward)
local PRESS_H  = math.min(14 * MSC, WALL_H - 4)

local pressBody = mk({ Name = "PressBody", Size = Vector3.new(13 * MSC, PRESS_H, 12 * MSC),
	Color = IRON, Material = Enum.Material.Metal, CanCollide = true, CFrame = pressCF })
mk({ Name = "PressTrim", Size = Vector3.new(13.4 * MSC, 1.6, 12.4 * MSC), Color = ROOF_D,
	Material = Enum.Material.Metal, CFrame = pressCF * CFrame.new(0, PRESS_H * 0.44, 0) })
mk({ Name = "Hopper", Size = Vector3.new(8 * MSC, 3.4 * MSC, 8 * MSC), Color = IRON_D,
	Material = Enum.Material.Metal, CFrame = pressCF * CFrame.new(0, PRESS_H * 0.6, 0) })
-- the intake mouth the belt feeds
mk({ Name = "Mouth", Size = Vector3.new(6.4 * MSC, 4.2 * MSC, 1.2), Color = RUBBER,
	CFrame = pressCF * CFrame.new(0, -1.5 * MSC, -6.2 * MSC) })

local ram = mk({ Name = "Ram", Size = Vector3.new(7.5 * MSC, 2.4 * MSC, 7.5 * MSC), Color = ROOF,
	Material = Enum.Material.Metal, CFrame = pressCF * CFrame.new(0, PRESS_H * 0.385, 0) })
local ramHome = ram.CFrame
local rod = mk({ Name = "RamRod", Size = Vector3.new(1.5 * MSC, 6 * MSC, 1.5 * MSC), Color = CREAM,
	Material = Enum.Material.Metal, CFrame = pressCF * CFrame.new(0, PRESS_H * 0.64, 0) })

-- ===== THE PRESS, DRESSED =====
-- Four corner columns and a top yoke, so the ram visibly runs IN something instead of hovering
-- over a box; a hydraulic pipe down one side; and a chaff plume off the hopper, because a baler
-- that eats straw and makes no dust is a diagram, not a machine.
for _, sx in ipairs({ -1, 1 }) do
	for _, sz in ipairs({ -1, 1 }) do
		mk({ Name = "PressColumn", Size = Vector3.new(0.9, PRESS_H * 0.68, 0.9), Color = IRON_D,
			Material = Enum.Material.Metal,
			CFrame = pressCF * CFrame.new(sx * 4.4 * MSC, PRESS_H * 0.29, sz * 4.4 * MSC) })
	end
end
mk({ Name = "PressYoke", Size = Vector3.new(10.6 * MSC, 1.1, 10.6 * MSC), Color = IRON_D,
	Material = Enum.Material.Metal, CFrame = pressCF * CFrame.new(0, PRESS_H * 0.66, 0) })
-- (a hydraulic pipe and pump used to hang off the side here. They were 2-stud details on a
-- 13-stud machine standing inside a shed -- you could not see them from the doorway, and up close
-- they only crowded the columns. The press reads better as four columns, a yoke and a ram.)

-- ===== THE MACHINE'S VOICE =====
-- On the press body, so it is positional: the noise comes from the machine, and it is the loudest
-- thing in the building rather than a flat layer over the whole island.
--
-- (!) ROLLOFF MIN 40, for the reason spelled out on the tractor's cutter: positional audio is
-- measured from the CAMERA, not from your character, and a third-person camera sits far enough
-- back that a small min-distance has already eaten most of the level before you hear it. Forty
-- studs covers the room; past the yard it fades away properly.
local machineSnd
if SOUND_MACHINE ~= "" then
	machineSnd = Instance.new("Sound")
	machineSnd.Name = "BalerRunning"
	machineSnd.SoundId = SOUND_MACHINE
	machineSnd.Looped = true
	machineSnd.Volume = 0                    -- the Heartbeat owns this; never snapped on
	machineSnd.RollOffMinDistance = 40
	machineSnd.RollOffMaxDistance = 220
	machineSnd.RollOffMode = Enum.RollOffMode.InverseTapered
	machineSnd.Parent = pressBody
	pcall(function() machineSnd:Play() end)
end

local chaff = Instance.new("ParticleEmitter")
chaff.Name = "Chaff"
chaff.Texture = "rbxasset://textures/particles/smoke_main.dds"
chaff.Color = ColorSequence.new(STRAW, STRAW_D)
chaff.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.2) })
chaff.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
chaff.Rate = 5                                   -- a haze off the hopper, not a bonfire
chaff.Lifetime = NumberRange.new(1.2, 2.2)
chaff.Speed = NumberRange.new(1.5, 3)
chaff.SpreadAngle = Vector2.new(35, 35)
chaff.Acceleration = Vector3.new(0.4, 1.4, 0)
chaff.LightEmission = 0.2
chaff.Rotation = NumberRange.new(0, 360)
chaff.RotSpeed = NumberRange.new(-40, 40)
do
	local a = Instance.new("Attachment")
	a.Name = "ChaffAt"
	a.Parent = ram                                -- rides the ram, so the dust moves with the blow
	a.WorldCFrame = pressCF * CFrame.new(0, PRESS_H * 0.74, 0)   -- world frame AFTER parenting, or
	chaff.Parent = a                                   -- measured against nothing and lands at 0,0,0
end

-- ===== OUTPUT TABLE =====
-- Runs from the press to the DOORWAY and stops there -- it used to run 16 studs past the front
-- wall and stand in the yard. A bale rolls to the threshold and then travels out to the stack
-- under its own steam (see the Heartbeat), which is the same journey to watch and none of the
-- machine outdoors.
local outDir  = outward
local outStart = pressPos + outDir * (7 * MSC)
local OUT_LEN = math.max(4, (floorMid + outward * (DEPTH - 0.5) - outStart).Magnitude)
local outCF = CFrame.lookAt(outStart + outDir * (OUT_LEN * 0.5) + Vector3.new(0, 3.4 * MSC, 0),
	outStart + outDir * (OUT_LEN * 0.5) + Vector3.new(0, 3.4 * MSC, 0) + outDir)
mk({ Name = "OutTable", Size = Vector3.new(7.6 * MSC, 0.8, OUT_LEN), Color = IRON_D,
	Material = Enum.Material.Metal, CFrame = outCF })
for k = 0, 8 do
	mk({ Name = "OutRoller", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(7.8 * MSC, 1.1 * MSC, 1.1 * MSC),
		Color = IRON, Material = Enum.Material.Metal,
		CFrame = outCF * CFrame.new(0, 0.6, -OUT_LEN * 0.5 + 2 + k * ((OUT_LEN - 4) / 8))
			* CFrame.Angles(0, 0, math.rad(90)) })
end

--======================================================================
-- THE YARD -- EMPTY UNTIL SOMEBODY MAKES SOMETHING
--======================================================================
-- These two loops used to fill the yard at boot: seven bales scattered out front, a stack of six
-- beside the building, so the place looked like it had been working before you arrived. Both are
-- off (YARD_BALES / STACK_BALES = 0) and the loops are kept only so turning them back on is one
-- number, not a rewrite.
--
-- WHY THEY ARE OFF: a decorative bale and a pressed bale are the same object. With twenty already
-- lying there, pressing one added nothing you could see, and the console -- the only thing to DO
-- at this building -- became invisible. An empty yard makes the first bale mean something.
local yardCentre = Vector3.new(centre.X, baseY, centre.Z) + outward * (FRONT.ext + 24)
local rightOfOut = Vector3.new(-outward.Z, 0, outward.X)

for i = 1, YARD_BALES do
	-- a loose scatter, lightly rotated: bales dropped by a machine do not land in a grid
	local a = (i / YARD_BALES) * math.pi * 2
	local r = 9 + (i % 3) * 5
	local p = yardCentre + rightOfOut * math.cos(a) * r + outward * math.sin(a) * r * 0.55
	local gy = groundY(p, baseY)
	makeBale(CFrame.new(p.X, gy + BALE.Y * 0.5, p.Z)
		* CFrame.Angles(0, a * 1.7 + i, 0))
end

-- ===== THE STACK BESIDE THE BUILDING =====
-- Alternating courses, like real stacked bales, and each course is inset so it reads as stable.
local stackAt = Vector3.new(centre.X, baseY, centre.Z)
	+ sideward * -(INTAKE.ext + 12) + outward * (FRONT.ext * 0.35)
local stackGY = groundY(stackAt, baseY)
do
	local placed, col, level = 0, 0, 0
	while placed < STACK_BALES do
		local perRow = 2
		local turn = (level % 2 == 0) and 0 or math.rad(90)
		local off = (col - (perRow - 1) * 0.5)
		local p = stackAt
			+ rightOfOut * (math.cos(turn) * off * (BALE.X + 0.6))
			+ outward * (math.sin(turn) * off * (BALE.X + 0.6))
		makeBale(CFrame.new(p.X, stackGY + BALE.Y * 0.5 + level * (BALE.Y + 0.15), p.Z)
			* CFrame.Angles(0, turn, 0))
		placed += 1; col += 1
		if col >= perRow then col = 0; level += 1 end
	end
end

--======================================================================
-- THE CONTROLS -- YOU RUN THE BALER, IT DOES NOT RUN ITSELF
--======================================================================
-- The press used to cycle on a timer, which made the whole building scenery: bales appeared
-- whether anybody was there or not, and there was nothing to DO here. Now the belt still feeds
-- straw into the hopper on its own, but a bale only exists because a player walked up to the
-- console and pressed for one.
local player     = Players.LocalPlayer
local PlayerGui  = player:WaitForChild("PlayerGui")

local stock      = 0     -- straw wads in the hopper right now
local balesMade  = 0
local pressPhase = -1    -- -1 = idle; 0..1 = one press cycle running (see the Heartbeat)
local owed       = 0     -- bales the tractor quest is waiting on (see _G.hayFactory.take)
-- ⚠ THE LINE DOES NOT MAKE ITS OWN STRAW. It used to: a wad appeared on the belt every 0.9s
-- forever, so the hopper filled itself and you could press bales out of thin air before you had
-- cut a single stalk. `pending` is straw somebody actually DELIVERED and has not reached the
-- press yet -- the belt only runs while there is some, and with none the console says so.
local pending    = 0
local doneUntil  = 0     -- os.clock() until which the panel shows "that's the lot" (see below)

-- ===== THE CONSOLE =====
-- A post and a tilted panel, stood beside the press on the ENTRANCE side, so you meet it walking
-- in rather than having to find your way round the machine.
-- clamped into the room: on a narrow footprint it tucks alongside the press instead of standing
-- outside through the wall, which is where a flat +9 studs put it
local consoleAt = pressPos + outward * math.min(7, DEPTH * 0.45)
	+ rightOfOut * math.min(9, math.max(4.5, WIDTH - 2.5))
local consoleGY = groundY(consoleAt, baseY)
mk({ Name = "ConsolePost", Size = Vector3.new(1.4, 6, 1.4), Color = IRON_D,
	Material = Enum.Material.Metal, CanCollide = true,
	CFrame = CFrame.new(consoleAt.X, consoleGY + 3, consoleAt.Z) })
local consoleTop = mk({ Name = "Console", Size = Vector3.new(5.2, 3.4, 1), Color = IRON,
	Material = Enum.Material.Metal, CanCollide = true,
	CFrame = CFrame.lookAt(Vector3.new(consoleAt.X, consoleGY + 6.2, consoleAt.Z),
		Vector3.new(consoleAt.X, consoleGY + 6.2, consoleAt.Z) + outward)
		* CFrame.Angles(math.rad(-25), 0, 0) })
local consoleLamp = mk({ Name = "ConsoleLamp", Size = Vector3.new(0.9, 0.9, 0.5), Color = STRAW_D,
	Material = Enum.Material.Neon, CFrame = consoleTop.CFrame * CFrame.new(-1.8, 0.9, -0.62) })

local balerPrompt = Instance.new("ProximityPrompt")
balerPrompt.ActionText = "Run the Baler"
balerPrompt.ObjectText = "Hay Bale Factory"
balerPrompt.KeyboardKeyCode = Enum.KeyCode.E
balerPrompt.HoldDuration = 0
balerPrompt.MaxActivationDistance = 16
balerPrompt.RequiresLineOfSight = false
balerPrompt.Parent = consoleTop

--======================================================================
-- THE PANEL
--======================================================================
-- House style: white card, blue header, lime action button, gold accent. It closes on its X and
-- on walking away -- NEVER on a tap somewhere else on the screen, which is the one thing that
-- makes a panel feel like it shut itself.
local BLUE  = Color3.fromRGB( 56, 128, 232)
local LIME  = Color3.fromRGB(126, 214,  86)
local GREY  = Color3.fromRGB(176, 170, 162)

local gui = Instance.new("ScreenGui")
gui.Name = "HayBaleFactoryHUD"; gui.ResetOnSpawn = false; gui.DisplayOrder = 12
gui.IgnoreGuiInset = true; gui.Enabled = false; gui.Parent = PlayerGui

local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 0.5); card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.fromOffset(480, 302); card.BackgroundColor3 = CREAM
card.BorderSizePixel = 0; card.Parent = gui
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 20)
do local s = Instance.new("UIStroke"); s.Color = BLUE; s.Thickness = 4; s.Parent = card end
-- HOUSE PANEL: the Pet Hub's 700x520 card in the Pet Hub's spot, and the bottom buttons hide while
-- it is up. The card keeps its own 480x302 coordinates -- it is centred in the house shell and
-- scaled to fit, so nothing inside it moves. See HousePanel.client.luau.
--
-- This REPLACES the card's own fit() UIScale. housePanel reuses whatever UIScale the panel already
-- has, so a fit() still wired to ViewportSize would overwrite the shell's scale on the next resize
-- or rotate and snap the card back to its old size mid-session.
pcall(_G.housePanel, card)   -- island19 hay bale factory

local head = Instance.new("Frame")
head.Size = UDim2.new(1, 0, 0, 54); head.BackgroundColor3 = BLUE
head.BorderSizePixel = 0; head.Parent = card
Instance.new("UICorner", head).CornerRadius = UDim.new(0, 20)
do  -- square off the bottom two corners, so the header sits INTO the card
	local patch = Instance.new("Frame")
	patch.AnchorPoint = Vector2.new(0.5, 1); patch.Position = UDim2.new(0.5, 0, 1, 0)
	patch.Size = UDim2.new(1, 0, 0, 20); patch.BackgroundColor3 = BLUE
	patch.BorderSizePixel = 0; patch.Parent = head
end
do
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1; t.Size = UDim2.new(1, -70, 1, 0); t.Position = UDim2.fromOffset(18, 0)
	t.Font = Enum.Font.FredokaOne; t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = Color3.new(1, 1, 1); t.TextSize = 24; t.Text = "HAY BALE FACTORY"; t.Parent = head
end

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5); closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(38, 38); closeBtn.BackgroundColor3 = Color3.fromRGB(232, 84, 76)
closeBtn.BorderSizePixel = 0; closeBtn.AutoButtonColor = false
closeBtn.Font = Enum.Font.FredokaOne; closeBtn.TextSize = 22; closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Text = "X"; closeBtn.Parent = head
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 12)

local gaugeLabel = Instance.new("TextLabel")
gaugeLabel.BackgroundTransparency = 1; gaugeLabel.Position = UDim2.fromOffset(22, 70)
gaugeLabel.Size = UDim2.new(1, -44, 0, 26); gaugeLabel.Font = Enum.Font.FredokaOne
gaugeLabel.TextXAlignment = Enum.TextXAlignment.Left; gaugeLabel.TextColor3 = TEXTC
gaugeLabel.TextSize = 20; gaugeLabel.Text = "Straw in the hopper"; gaugeLabel.Parent = card

local gauge = Instance.new("Frame")
gauge.Position = UDim2.fromOffset(22, 100); gauge.Size = UDim2.new(1, -44, 0, 22)
gauge.BackgroundColor3 = Color3.fromRGB(238, 228, 210); gauge.BorderSizePixel = 0; gauge.Parent = card
Instance.new("UICorner", gauge).CornerRadius = UDim.new(1, 0)
local gaugeFill = Instance.new("Frame")
gaugeFill.Size = UDim2.new(0, 0, 1, 0); gaugeFill.BackgroundColor3 = STRAW
gaugeFill.BorderSizePixel = 0; gaugeFill.Parent = gauge
Instance.new("UICorner", gaugeFill).CornerRadius = UDim.new(1, 0)

local makeBtn = Instance.new("TextButton")
makeBtn.AnchorPoint = Vector2.new(0.5, 0); makeBtn.Position = UDim2.new(0.5, 0, 0, 142)
makeBtn.Size = UDim2.new(1, -44, 0, 76); makeBtn.BackgroundColor3 = LIME
makeBtn.BorderSizePixel = 0; makeBtn.AutoButtonColor = false
makeBtn.Font = Enum.Font.FredokaOne; makeBtn.TextSize = 28; makeBtn.TextColor3 = Color3.new(1, 1, 1)
makeBtn.Text = "PRESS A BALE!"; makeBtn.Parent = card
Instance.new("UICorner", makeBtn).CornerRadius = UDim.new(0, 18)
do local s = Instance.new("UIStroke"); s.Color = TEXTC; s.Thickness = 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Transparency = 0.55; s.Parent = makeBtn end

local tally = Instance.new("TextLabel")
tally.AnchorPoint = Vector2.new(0.5, 1); tally.Position = UDim2.new(0.5, 0, 1, -14)
tally.Size = UDim2.new(1, -44, 0, 26); tally.BackgroundTransparency = 1
tally.Font = Enum.Font.FredokaOne; tally.TextColor3 = TEXTC; tally.TextSize = 18
tally.Text = "Bales pressed: 0"; tally.Parent = card

-- the bottom HUD goes down while the panel is up -- same shape every menu in this realm uses:
-- remember what was Enabled, switch it off, put it back EXACTLY as it was.
local hudPrev
local function setHud(hidden)
	if hidden then
		if hudPrev then return end
		hudPrev = {}
		for _, n in ipairs({ "BottomStackGui", "GasMeterGui", "FartButtonGui", "StomachGui" }) do
			local sg = PlayerGui:FindFirstChild(n)
			if sg and sg:IsA("ScreenGui") then hudPrev[n] = sg.Enabled; sg.Enabled = false end
		end
	elseif hudPrev then
		for n, was in pairs(hudPrev) do
			local sg = PlayerGui:FindFirstChild(n)
			if sg and sg:IsA("ScreenGui") then sg.Enabled = was end
		end
		hudPrev = nil
	end
end

local function refreshPanel()
	local ready = stock >= STRAW_NEED and pressPhase < 0
	local empty = (stock <= 0 and pending <= 0)          -- nothing here and nothing on the way
	local justDone = os.clock() < doneUntil              -- the owed bales are all pressed
	gaugeFill.Size = UDim2.new(math.clamp(stock / STRAW_NEED, 0, 1), 0, 1, 0)
	gaugeLabel.Text = ("%s  Straw in the hopper   %d / %d"):format("\xF0\x9F\x8C\xBE", math.min(stock, STRAW_CAP), STRAW_NEED)
	makeBtn.BackgroundColor3 = (ready and not justDone) and LIME or GREY
	-- THE JOB ENDS WHEN THE JOB ENDS. Telling somebody to press another bale after they have
	-- pressed the five they came for is the panel arguing with the banner over their head -- and
	-- with no straw left it would have been a button that did nothing anyway. With no straw the
	-- text also says where straw comes from: "wait for straw" was a lie on an empty line, since
	-- nothing was coming and the answer was out in a field.
	makeBtn.Text = (justDone and "THAT'S THE LOT!")
		or (pressPhase >= 0 and "PRESSING...")
		or (ready and "PRESS A BALE!")
		or (empty and "NO STRAW -- CUT SOME AND BRING IT IN!")
		or "WAIT FOR STRAW..."
	tally.Text = (justDone and "Bales are outside -- carry them to the farm house")
		or (empty and "Tip a load of cut straw in to start baling")
		or ("Bales pressed: %d"):format(balesMade)
	consoleLamp.Color = (ready and not justDone) and ROOF or STRAW_D
end

local function openPanel()
	gui.Enabled = true
	setHud(true)
	refreshPanel()
end
local function closePanel()
	gui.Enabled = false
	setHud(false)
end
closeBtn.Activated:Connect(closePanel)
balerPrompt.Triggered:Connect(openPanel)

makeBtn.Activated:Connect(function()
	if pressPhase >= 0 then return end               -- one cycle at a time
	if stock < STRAW_NEED then
		makeBtn.Text = "NOT ENOUGH STRAW YET!"
		return
	end
	stock -= STRAW_NEED
	pressPhase = 0                                   -- the Heartbeat below drives the ram from here
	refreshPanel()
end)

--======================================================================
-- IT RUNS
--======================================================================
-- One Heartbeat drives everything. Separate task.wait loops per prop drift apart within a minute
-- and the machine stops looking like one mechanism.
local straws, made = {}, {}
local tStraw, panelT = 0, 0

local function spawnStraw()
	local m = Instance.new("Model"); m.Name = "Straw"; m.Parent = folder
	local root = mk({ Name = "Wad", Size = Vector3.new(3.4, 1.5, 2.6), Color = STRAW,
		Material = Enum.Material.Grass,
		CFrame = CFrame.new(beltStart + Vector3.new(0, BELT_H + 1.2, 0)) }, m)
	m.PrimaryPart = root
	-- loose ends sticking out: three thin slabs at angles is all "untidy straw" needs
	for k = 1, 3 do
		mk({ Name = "Wisp", Size = Vector3.new(4.2, 0.32, 0.32), Color = STRAW_D,
			Material = Enum.Material.Grass,
			CFrame = root.CFrame * CFrame.Angles(0, k * 1.1, k * 0.35) * CFrame.new(0, 0.5, 0) }, m)
	end
	straws[#straws + 1] = { model = m, t = 0 }
end

RunService.Heartbeat:Connect(function(dt)
	-- rollers turn whenever the line is running
	for i, r in ipairs(rollers) do
		r.CFrame = r.CFrame * CFrame.Angles(0, dt * (5 + i * 0.02), 0)
	end

	-- straw onto the belt -- only what was delivered, and only while there is some left to feed
	tStraw += dt
	if tStraw >= STRAW_EVERY and pending > 0 then
		tStraw = 0
		pending -= 1
		spawnStraw()
	end

	-- straw along the belt and into the mouth
	for i = #straws, 1, -1 do
		local s = straws[i]
		s.t += dt / 3.6                                   -- ~3.6s end to end
		if s.t >= 1 then
			-- swallowed: a puff at the mouth is what sells the machine eating it, and THIS is
			-- where the hopper actually fills -- the belt is the supply, the console is the trigger
			if s.model.PrimaryPart then poof(s.model.PrimaryPart.Position, STRAW_D, 6) end
			s.model:Destroy()
			table.remove(straws, i)
			stock = math.min(stock + 1, STRAW_CAP)
			if gui.Enabled then refreshPanel() end
		elseif s.model.PrimaryPart then
			local p = beltStart:Lerp(intakeMid + Vector3.new(0, 0, 0), s.t)
			s.model:PivotTo(CFrame.new(p + Vector3.new(0, BELT_H + 1.2, 0))
				* CFrame.Angles(0, s.t * 3, 0))
		end
	end

	-- ===== THE MACHINE'S VOICE, FADED TO WHAT IT IS DOING =====
	-- Full while the ram is actually in the stroke, half while the belt is carrying straw toward
	-- it, silent when the line is empty. Same fade the tractor's cutter uses, for the same reason:
	-- a looped sound snapped to full volume clicks, and this one starts and stops all day.
	if machineSnd then
		local want = (pressPhase >= 0 and 0.96)
			or ((#straws > 0 or pending > 0) and 0.5)
			or 0
		machineSnd.Volume += (want - machineSnd.Volume) * math.min(1, dt * 9)
	end

	-- the press cycle -- STARTED BY THE BUTTON, never by a timer
	if pressPhase >= 0 then
		pressPhase += dt * 2.2
		local k = math.min(1, pressPhase)
		-- down fast, back up slow: that asymmetry is what makes it read as a press rather than
		-- a bobbing block
		local drop = (k < 0.35) and (k / 0.35) or (1 - (k - 0.35) / 0.65)
		ram.CFrame = ramHome * CFrame.new(0, -drop * 4.6, 0)
		rod.CFrame = ramHome * CFrame.new(0, 3.6 - drop * 4.6, 0)
		if pressPhase >= 0.35 and not straws.thumped then
			straws.thumped = true
			poof(pressPos + Vector3.new(0, 6, 0), STRAW_D, 8)
			-- the blow blows the dust out: a burst off the hopper, then back to the idle haze
			chaff:Emit(14)
			-- ===== A BALE COMES OUT =====
			local b = makeBale(CFrame.new(outStart + Vector3.new(0, 3.4 + BALE.Y * 0.5, 0)))
			made[#made + 1] = { model = b, t = 0 }
			balesMade += 1
			-- ===== THE TRACTOR QUEST'S BALE =====
			-- If a load of straw was tipped in here (the harvest's first stop), this press is one
			-- of the bales it is owed: it goes onto the trailer rather than into the yard. The two
			-- scripts never touch each other's insides -- this global and _G.hayFactory below are
			-- the whole contract.
			if owed > 0 then
				owed -= 1
				if _G.tractorBaleMade then pcall(_G.tractorBaleMade) end
				-- ===== THAT WAS THE LAST ONE. STOP ASKING FOR MORE. =====
				-- The load the tractor tipped in was credited as exactly enough straw for the
				-- bales it was owed, so when the last one comes off the press the line is empty by
				-- definition -- and the console said "PRESS A BALE!" anyway, because there was
				-- rounding left in the hopper. Zeroing both is the truth of it, and it turns the
				-- panel over to the "that's the lot" message below instead of inviting a sixth.
				if owed <= 0 then
					pending, stock = 0, 0
					doneUntil = os.clock() + 25
				end
			end
			-- ...and everyone else at this factory sees a bale come off the press too
			if _G.hayFactory and _G.hayFactory.announce then pcall(_G.hayFactory.announce) end
			if #made > MAX_MADE then
				-- the yard does not grow forever: the oldest is retired quietly
				local old = table.remove(made, 1)
				if old.model.Parent then old.model:Destroy() end
			end
			if gui.Enabled then refreshPanel() end
		end
		if pressPhase >= 1 then
			pressPhase, straws.thumped = -1, nil
			ram.CFrame = ramHome
			rod.CFrame = ramHome * CFrame.new(0, 3.6, 0)
			if gui.Enabled then refreshPanel() end
		end
	end

	-- the panel is event-driven, but two of the things it shows are time-based (the "that's the
	-- lot" message expiring, straw arriving on the belt), so while it is open it also ticks
	if gui.Enabled then
		panelT += dt
		if panelT > 0.25 then panelT = 0; refreshPanel() end
	end

	-- WALKING AWAY CLOSES THE PANEL. Not a tap somewhere else on the screen -- just leaving the
	-- machine, which is the only "I'm done here" a player actually performs.
	if gui.Enabled then
		local ch = player.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if not hrp or (hrp.Position - consoleTop.Position).Magnitude > PANEL_RANGE then
			closePanel()
		end
	end

	-- finished bales roll out of the building and settle in the yard
	for _, b in ipairs(made) do
		if b.t < 1 and b.model.PrimaryPart then
			b.t = math.min(1, b.t + dt / 2.8)
			local from = outStart + Vector3.new(0, 3.4 + BALE.Y * 0.5, 0)
			local to   = yardCentre + outward * -6 + Vector3.new(0, 0, 0)
			local gy   = groundY(to, baseY)
			local p    = from:Lerp(Vector3.new(to.X, gy + BALE.Y * 0.5, to.Z), b.t)
			b.model:PivotTo(CFrame.new(p) * CFrame.Angles(0, b.t * 0.6, 0))
		end
	end
end)

--======================================================================
-- HIDE YOUR BLOCK
--======================================================================
-- Read-only until this point, and only ever made invisible -- never moved, resized or deleted,
-- so the block stays exactly where you drew it and the factory can be rebuilt from it.
marker.Transparency = 1
marker.CanCollide = false
marker.CanQuery = false

--======================================================================
-- THE TWO CONTRACTS THIS BUILDING HAS WITH THE REST OF THE ISLAND
--======================================================================
-- 1. THE TRACTOR QUEST. It drives a trailer of cut straw here as the first stop of the harvest,
--    tips it in, works this console, and drives the bales on to the farm house. All it needs
--    from us is somewhere to aim (point) and a way to hand the straw over (take) -- and all we
--    need from it is _G.tractorBaleMade, called once per bale it is owed. Neither script reads
--    a single one of the other's locals.
--
-- 2. EVERY OTHER PLAYER. This is a LocalScript, so a bale pressed here exists on one screen. The
--    relay (HayFactoryFxSync.server.lua) passes "somebody pressed one" to everybody else, whose
--    own copy of this factory drops a bale in its own yard. Cosmetic in both directions: nothing
--    it carries can change anyone's quest.
_G.hayFactory = {
	-- WHERE A TRAILER AIMS: the DOORWAY, not the belt head. The belt is inside now, and telling a
	-- tractor to drive to a point in the middle of a building is telling it to drive into a wall.
	point = floorMid + outward * (FRONT.ext + 7),

	-- the interior, for anything that needs to know what is inside this building: the floor's
	-- centre, the half-extents inside the walls, and the floor's top. Published rather than
	-- guessed, because every other script that has tried to guess it has got it wrong.
	-- (!) ALIGNED TO THE DOOR, NOT TO THE MARKER BLOCK. WIDTH is measured across the doorway and
	-- DEPTH along it, so the frame these are read in has to be the door's -- in the block's own
	-- frame they would be the right numbers on the wrong axes, which is a containment test that
	-- passes for parts sticking through a wall.
	interior = {
		cf = CFrame.lookAt(floorMid, floorMid + outward),
		half = Vector3.new(WIDTH, WALL_H, DEPTH),
		floorY = baseY + 1,
	},

	-- straw handed over. `bales` is how many the caller expects back out of the press; the hopper
	-- is topped up so the button is live immediately, and the panel opens on its own because the
	-- player has just driven across a field to use it.
	take = function(sheaves, bales)
		local n = math.max(0, tonumber(sheaves) or 0)
		local want = math.max(0, tonumber(bales) or 0)
		owed += want
		-- (!) THE LOAD IS CREDITED AS ENOUGH STRAW FOR THE BALES IT IS OWED, and that is not a
		-- fudge -- it is the only way the two halves can agree. A trailer holds fourteen sheaves,
		-- a press costs three straw, and five bales cost fifteen: taken literally, a full harvest
		-- is one straw short of the job it was sent to do, and the player is left at a console
		-- that will not press with nothing left to fetch. So whoever asks for N bales gets the
		-- straw for exactly N, and the sheaf count still decides how many they were owed.
		pending += math.max(n, want * STRAW_NEED)
		-- ...and a couple of wads go straight in, so the console is not dead for the first few
		-- seconds after you have plainly just delivered a trailer full
		stock = math.min(STRAW_CAP, stock + math.min(n, 2))
		openPanel()
		print(("[Factory] took %d sheaf/sheaves -> %d straw on the belt, %d bale(s) owed")
			:format(n, pending, owed))
	end,

	-- filled in by the relay block below, once the remote is there. Guarded everywhere it is
	-- called, so a factory running without the server script simply keeps its bales to itself.
	announce = nil,
}

--======================================================================
-- CONTAINMENT AUDIT -- does the machine actually fit in the building?
--======================================================================
-- Every piece of the LINE (belt, press, output table, console) is measured from the interior, so
-- in principle none of it can be outside. This checks that in practice and NAMES anything that
-- is, because "the machine is in the grass" was the bug and a silent layout is how it came back.
-- The shell itself is skipped: walls, roof and floor ARE the boundary, so testing them against it
-- is meaningless.
--
-- It also catches a part that has drifted at runtime -- streamed in wrong, moved by another
-- script, left behind by a stale copy -- which is exactly the "wall sitting apart from the
-- building" case, reported by name and position so it can be found in Studio.
do
	local LINE = { Belt = true, BeltLeg = true, BeltRail = true, Roller = true, DrivePulley = true,
		MotorBed = true, Motor = true, VeeBelt = true, PressBody = true, PressTrim = true,
		PressColumn = true, PressYoke = true, Hopper = true, Mouth = true, Ram = true,
		RamRod = true, OutTable = true, OutRoller = true, ConsolePost = true, Console = true,
		ConsoleLamp = true }
	local cf, half = _G.hayFactory.interior.cf, _G.hayFactory.interior.half
	local bad = {}
	for _, d in ipairs(folder:GetChildren()) do
		if d:IsA("BasePart") and LINE[d.Name] then
			local o = cf:PointToObjectSpace(d.Position)
			-- half a part's own size of tolerance on each axis: the output table is MEANT to reach
			-- the threshold, and the press body is meant to be wide
			if math.abs(o.X) > half.X + 1 or math.abs(o.Z) > half.Z + 1
				or d.Position.Y < _G.hayFactory.interior.floorY - 1 then
				bad[#bad + 1] = ("%s at %.0f, %.0f, %.0f"):format(d.Name,
					d.Position.X, d.Position.Y, d.Position.Z)
			end
		end
	end
	if #bad > 0 then
		warn(("[Factory] %d machine part(s) are OUTSIDE the building and need looking at: %s")
			:format(#bad, table.concat(bad, " | ")))
	else
		print(("[Factory] containment OK -- every piece of the line is inside the walls "
			.. "(interior %.0f x %.0f studs, machine scale x%.2f)"):format(WIDTH * 2, DEPTH * 2, MSC))
	end
end

-- ===== THE SHARED BALE =====
-- In a task, not inline: WaitForChild would otherwise stall the rest of this file's boot for up
-- to 20 seconds on a server where the relay has not replicated yet.
task.spawn(function()
	local RS = game:GetService("ReplicatedStorage")
	local ev = RS:FindFirstChild("HayFactoryFxEvent") or RS:WaitForChild("HayFactoryFxEvent", 20)
	if not ev then
		warn("[Factory] no HayFactoryFxEvent -- other players' bales will not appear here. Is "
			.. "HayFactoryFxSync.server.lua synced into ServerScriptService?")
		return
	end
	_G.hayFactory.announce = function()
		pcall(function() ev:FireServer("bale", outStart) end)
	end
	ev.OnClientEvent:Connect(function(who, kind, pos)
		if who == player or kind ~= "bale" then return end   -- our own press: already on screen
		if typeof(pos) ~= "Vector3" then return end
		-- somebody else's bale lands in OUR yard, in the same scatter ours use. It is theirs, so
		-- it is scenery here: it never enters `made` and never counts toward anything local.
		balesMade += 1                                   -- shared bales share the scatter counter
		local a = balesMade * 2.39996                    -- golden angle: never clumps, never lines up
		local r = 10 + (balesMade % 3) * 5
		local p = yardCentre + rightOfOut * math.cos(a) * r + outward * math.sin(a) * r * 0.55
		local gy = groundY(p, baseY)
		local b = makeBale(CFrame.new(p.X, gy + BALE.Y * 0.5, p.Z) * CFrame.Angles(0, a * 1.7, 0))
		poof(p + Vector3.new(0, 2, 0), STRAW_D, 6)
		task.delay(180, function() if b and b.Parent then b:Destroy() end end)
	end)
	print("[Factory] shared bales live -- presses by other players show up in this yard")
end)

print(("[Factory] Hay Bale Factory built on '%s' -- %.0f x %.0f footprint, %.0f tall, rotated "
	.. "%d deg. Entrance faces %s, intake faces %s. %d yard bale(s), %d stacked. Bales are made "
	.. "at the console (E) -- %d straw each, nothing presses on its own.")
	:format(marker:GetFullName(), mSize.X, mSize.Z, WALL_H + ROOF_H, BUILD_YAW,
		pathPart and ("the path ('" .. pathPart.Name .. "')") or "the wheat field",
		wheatPart and ("the wheat ('" .. wheatPart.Name .. "')") or "the opposite wall",
		YARD_BALES, STACK_BALES, STRAW_NEED))
