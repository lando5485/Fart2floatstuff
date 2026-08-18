--======================================================================
-- FixStreaming.studio.luau  --  PASTE INTO STUDIO'S COMMAND BAR (edit mode, not playing)
--======================================================================
-- WHY THIS EXISTS. Scenery on island16 was vanishing on a camera turn. The usual fix is to raise
-- Workspace.StreamingMinRadius from its 64-stud default -- but that property is NotScriptable, so
-- neither a game script nor the command bar can touch it. It can only be typed into the Properties
-- panel by hand.
--
-- THIS DOES THE OTHER HALF, AND IT IS THE HALF THAT ACTUALLY MATTERS. A model marked
-- ModelStreamingMode = Persistent is replicated to every client and NEVER streams out, whatever the
-- radius is. That property IS scriptable, so it can be fixed from here -- permanently, in the saved
-- place, rather than at runtime after the server has already booted.
--
-- It fixes three things, in order:
--
--   1. EVERY island<N> Model -> Persistent. IslandStreaming already does this at runtime, but only
--      after the server starts; doing it in the file means it is true before a single script runs.
--
--   2. LOOSE PARTS -> INTO THE ISLAND. A BasePart parented straight to Workspace cannot inherit
--      Persistent from anything, so it streams by distance no matter what else you set. This is the
--      one that bites: your boot log has been listing them for days ("loose part(s) beside an
--      island... they still cannot inherit Persistent streaming, so drag them into the island in
--      Studio"). This does the dragging.
--
--   3. ANCHORS them, so nothing that just changed parents can fall.
--
-- SAFE TO RUN TWICE. Everything it does is idempotent, and it moves a part only when that part sits
-- inside an island's own bounding box -- never something merely nearby.
--
-- ⚠ RUN IT IN EDIT MODE AND THEN PUBLISH. Run during a playtest and every change dies with the
-- session, which is the same trap the radius has.
--======================================================================

local Workspace = game:GetService("Workspace")

local PERSIST = Enum.ModelStreamingMode.Persistent
local PAD = 8  -- studs of slack around an island's box, so a part on the very rim still counts

local function isIslandName(n)
	return string.lower(n):match("^island_?%d+") ~= nil
end

-- every island model, outermost first (islands here are often nested island16 > island16)
local islands = {}
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("Model") and isIslandName(d.Name) and not d:FindFirstAncestorOfClass("Model") then
		islands[#islands + 1] = d
	end
end

if #islands == 0 then
	warn("[FixStreaming] no island<N> models found -- is this the CandyRealm place?")
	return
end

-- ---- 1. persist every island ------------------------------------------------
local persisted = 0
for _, isl in ipairs(islands) do
	if isl.ModelStreamingMode ~= PERSIST then
		isl.ModelStreamingMode = PERSIST
		persisted += 1
		print(("[FixStreaming] %s -> Persistent"):format(isl.Name))
	end
end

-- ---- 2. adopt loose parts ---------------------------------------------------
-- box test, not distance: a part is "on" an island when it is inside that island's bounding box.
-- Distance to a pivot would drag in anything hovering above or below the tower.
local boxes = {}
for _, isl in ipairs(islands) do
	local ok, cf, size = pcall(function()
		local c, s = isl:GetBoundingBox()
		return c, s
	end)
	if ok and cf and size then
		boxes[#boxes + 1] = { isl = isl, cf = cf, half = size / 2 }
	end
end

local function islandContaining(pos)
	for _, b in ipairs(boxes) do
		local local_ = b.cf:PointToObjectSpace(pos)
		if math.abs(local_.X) <= b.half.X + PAD
			and math.abs(local_.Y) <= b.half.Y + PAD
			and math.abs(local_.Z) <= b.half.Z + PAD then
			return b.isl
		end
	end
	return nil
end

local adopted, anchored = 0, 0
for _, child in ipairs(Workspace:GetChildren()) do
	-- direct children of Workspace only: anything deeper already has a parent that can carry the flag
	if child:IsA("BasePart") and not child:IsA("Terrain") then
		local isl = islandContaining(child.Position)
		if isl then
			child.Parent = isl
			adopted += 1
			if not child.Anchored then child.Anchored = true; anchored += 1 end
			print(("[FixStreaming] adopted loose '%s' -> %s"):format(child.Name, isl.Name))
		end
	end
end

-- ---- report -----------------------------------------------------------------
print("")
print("========================================================")
print(("[FixStreaming] %d island(s) set Persistent, %d loose part(s) adopted, %d anchored")
	:format(persisted, adopted, anchored))
local minR = "?"
pcall(function() minR = tostring(Workspace.StreamingMinRadius) end)
print(("[FixStreaming] StreamingMinRadius reads as: %s   (NotScriptable -- if that is not a number,"
	.. " type 768 into it in Workspace's Properties panel by hand)"):format(minR))
print("[FixStreaming] NOW PUBLISH (File > Publish to Roblox), or none of this is saved.")
print("========================================================")
