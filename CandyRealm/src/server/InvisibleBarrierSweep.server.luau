--======================================================================
-- InvisibleBarrierSweep.server.luau  (Server Script)  -- CandyRealm
--======================================================================
-- Strips collision from INVISIBLE parts/unions sitting on the islands so
-- players stop bumping into walls they can't see. Runs on every island
-- (island1..island14), not just island1.
--
-- What counts as an invisible barrier:
--   * BasePart or UnionOperation with Transparency >= 0.98 and CanCollide on.
--
-- What is DELIBERATELY skipped (turning these off would break things):
--   * SpawnLocations / anything named like "spawn" -- players spawn on these.
--   * Parts inside models with a Humanoid (NPCs -- their HumanoidRootPart is
--     invisible + collidable by design).
--   * HumanoidRootPart by name, Tools, Accessories, Seats.
--   * Big FLAT horizontal invisible parts -- those are usually intentional
--     walk floors under decorative meshes. Removing them drops players
--     through the island. They get logged as "SKIP floor?" so you can review.
--
-- Parts are NOT destroyed -- only CanCollide is turned off. CanTouch is left
-- alone so any invisible touch-triggers keep working.
--
-- NOTE: this cannot fix a VISIBLE union whose collision hull is a chunky box
-- (CollisionFidelity) -- that property is locked at runtime. Use the Studio
-- command-bar snippet in CandyRealm/studio/FixUnionCollision.lua for those.
--======================================================================

local Workspace = game:GetService("Workspace")

local TRANSPARENCY_MIN = 0.98

-- Same island matching as AnchorIslands: "island1".."island14" or "Island_1_...".
local function isIslandName(name: string): boolean
	return string.lower(name):match("^island_?%d+") ~= nil
end

local function islandAncestor(inst: Instance): Model?
	local node = inst.Parent
	while node and node ~= Workspace do
		if node:IsA("Model") and isIslandName(node.Name) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function insideHumanoidModel(part: BasePart): boolean
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildWhichIsA("Humanoid") then return true end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return false
end

-- A big, flat, roughly-horizontal invisible part is probably an intentional
-- walk floor under a mesh -- leave it alone, just report it.
local function looksLikeFloor(part: BasePart): boolean
	local up = part.CFrame.UpVector
	if math.abs(up.Y) < 0.9 then return false end -- tilted/vertical -> wall-ish
	local s = part.Size
	return s.Y <= 4 and (s.X * s.Z) >= 64
end

local function isProtected(part: BasePart): boolean
	if part:IsA("SpawnLocation") then return true end
	if part:IsA("Seat") or part:IsA("VehicleSeat") then return true end
	if part.Name == "HumanoidRootPart" then return true end
	if part.Name:lower():find("spawn") then return true end
	if part:FindFirstAncestorWhichIsA("Tool") then return true end
	if part:FindFirstAncestorWhichIsA("Accessory") then return true end
	if insideHumanoidModel(part) then return true end
	return false
end

-- Returns "cleared" | "floor" | nil (not a barrier / protected).
local function handlePart(part: BasePart): string?
	if part.Transparency < TRANSPARENCY_MIN then return nil end
	if not part.CanCollide then return nil end
	if isProtected(part) then return nil end
	if looksLikeFloor(part) then
		return "floor"
	end
	part.CanCollide = false
	return "cleared"
end

local function sweep(label: string)
	local cleared, floors = 0, 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and islandAncestor(d) then
			local result = handlePart(d)
			if result == "cleared" then
				cleared += 1
				print(("[BarrierSweep][%s] cleared %s"):format(label, d:GetFullName()))
			elseif result == "floor" then
				floors += 1
				print(("[BarrierSweep][%s] SKIP floor? %s (flat horizontal -- review in Studio)"):format(label, d:GetFullName()))
			end
		end
	end
	print(("[BarrierSweep][%s] done -- %d barrier(s) cleared, %d flat floor-like part(s) left alone"):format(label, cleared, floors))
end

-- Pass 1 now, pass 2 after startup props/quests finish spawning.
sweep("pass1")
task.spawn(function()
	task.wait(8)
	sweep("pass2")
end)

-- Anything added to an island later (events, rebuilds) gets the same treatment.
Workspace.DescendantAdded:Connect(function(d)
	if not d:IsA("BasePart") then return end
	task.defer(function() -- let its properties/ancestry settle first
		if d.Parent and islandAncestor(d) then
			if handlePart(d) == "cleared" then
				print(("[BarrierSweep][live] cleared %s"):format(d:GetFullName()))
			end
		end
	end)
end)
