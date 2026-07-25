--!nonstrict
--======================================================================
-- SpawnOnIsland1.server.luau  (Server Script)  -- CandyRealm
--======================================================================
-- Forces players to a chosen landmark on EVERY spawn (join + respawn), overriding
-- the default SpawnLocation / teleport arrival. Flip SPAWN_TARGET to move where
-- players spawn -- handy for testing a specific island.
--
--   SPAWN_TARGET = "island1"  -> on top of island1 (the real start island)
--   SPAWN_TARGET = "cookie"   -> on the GiantCookie (island3, for testing that quest)
--======================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local SPAWN_TARGET = "island8"  -- "island1" | "cookie" (island3) | "jelly" (island4) | "island5" (delivery) | "island8" (crystal mine)

-- ============================================================================
local function findFirst(pred)
	for _, d in ipairs(Workspace:GetDescendants()) do if pred(d) then return d end end
	return nil
end
local function findFirstIn(container, pred)
	for _, d in ipairs(container:GetDescendants()) do if pred(d) then return d end end
	return nil
end
local function firstBasePartOf(inst)
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end
local function findIsland1()
	return Workspace:FindFirstChild("island1")
		or findFirst(function(o) return o:IsA("Model") and string.lower(o.Name):match("^island_?1$") ~= nil end)
end
local function findCookie()
	-- ignore spaces/underscores so "Giant Cookie" (the actual Studio name) matches too
	return findFirst(function(o)
		return (o:IsA("Model") or o:IsA("BasePart"))
			and (string.gsub(string.lower(o.Name), "[%s_%-]", "")) == "giantcookie"
	end)
end
local function findJelly()
	-- 1) spawn ON the JellyStart pad if it exists (so its bounce fires on spawn)
	local start = findFirst(function(o) return o:IsA("BasePart") and string.lower(o.Name) == "jellystart" end)
	if start then return start end

	-- locate the tower (tier / flag) as a reference point
	local ref
	for _, want in ipairs({ "jellylevel1", "jellylevel_1", "jellyflag" }) do
		local p = findFirst(function(o) return o:IsA("BasePart") and string.lower(o.Name) == want end)
		if p then ref = p; break end
	end
	if not ref then ref = findFirst(function(o) return o:IsA("BasePart") and string.lower(o.Name):match("^jellylevel") ~= nil end) end
	if not ref then return nil end

	-- 2) no JellyStart -> spawn on your spawn brick (SpawnLocation / "spawn"-named part) near the tower
	local best, bestD
	for _, o in ipairs(Workspace:GetDescendants()) do
		if o:IsA("BasePart") and (o:IsA("SpawnLocation") or string.lower(o.Name):find("spawn", 1, true)) then
			local d = (o.Position - ref.Position).Magnitude
			if d < 300 and (not bestD or d < bestD) then best, bestD = o, d end
		end
	end
	return best or ref -- 3) last resort: the tower tier itself
end

local function findIsland5()
	return Workspace:FindFirstChild("island5")
		or findFirst(function(o) return o:IsA("Model") and string.lower(o.Name):match("^island_?5$") ~= nil end)
end
local function findIsland5Spawn()
	-- prefer the spawn brick ON / near island5, else the island itself
	local isle = findIsland5()
	local ref = isle and (isle:IsA("Model") and (isle.PrimaryPart or firstBasePartOf(isle)) or isle)
	-- 1) a SpawnLocation / "spawn"-named part inside island5
	if isle then
		local inside = findFirstIn(isle, function(o) return o:IsA("BasePart") and (o:IsA("SpawnLocation") or string.lower(o.Name):find("spawn", 1, true)) end)
		if inside then return inside end
	end
	-- 2) the nearest SpawnLocation / "spawn" part in the world
	if ref then
		local best, bestD
		for _, o in ipairs(Workspace:GetDescendants()) do
			if o:IsA("BasePart") and (o:IsA("SpawnLocation") or string.lower(o.Name):find("spawn", 1, true)) then
				local d = (o.Position - ref.Position).Magnitude
				if d < 400 and (not bestD or d < bestD) then best, bestD = o, d end
			end
		end
		if best then return best end
	end
	return isle -- 3) fall back to the island top
end

local function findIsland8()
	return Workspace:FindFirstChild("island8")
		or findFirst(function(o)
			if not o:IsA("Model") then return false end
			local num = string.lower(o.Name):match("^island[ _]?(%d+)")
			return num ~= nil and tonumber(num) == 8
		end)
end
local function findIsland8Spawn()
	local isle = findIsland8()
	if not isle then
		-- no island8 model found -> spawn right by the crystals instead
		local crystal = findFirst(function(o) return (o:IsA("BasePart") or o:IsA("Model")) and string.lower(o.Name):match("^crystal") ~= nil end)
		if crystal then return crystal end
	end
	local ref = isle and (isle:IsA("Model") and (isle.PrimaryPart or firstBasePartOf(isle)) or isle)
	if isle then
		local inside = findFirstIn(isle, function(o) return o:IsA("BasePart") and (o:IsA("SpawnLocation") or string.lower(o.Name):find("spawn", 1, true)) end)
		if inside then return inside end
	end
	if ref then
		local best, bestD
		for _, o in ipairs(Workspace:GetDescendants()) do
			if o:IsA("BasePart") and (o:IsA("SpawnLocation") or string.lower(o.Name):find("spawn", 1, true)) then
				local d = (o.Position - ref.Position).Magnitude
				if d < 400 and (not bestD or d < bestD) then best, bestD = o, d end
			end
		end
		if best then return best end
	end
	return isle
end

-- world position just above a landmark's top surface (raycast down onto it, else bbox top)
local function landmarkTop(inst)
	if not inst then return nil end
	local cf, sz
	if inst:IsA("BasePart") then cf, sz = inst.CFrame, inst.Size else cf, sz = inst:GetBoundingBox() end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { inst }
	local hit = Workspace:Raycast(cf.Position + Vector3.new(0, sz.Y, 0), Vector3.new(0, -sz.Y * 2.5, 0), rp)
	local base = (hit and hit.Position) or (cf.Position + Vector3.new(0, sz.Y * 0.5, 0))
	return base + Vector3.new(0, 5, 0)
end

local function targetTop()
	if SPAWN_TARGET == "island8" then return landmarkTop(findIsland8Spawn()) end
	if SPAWN_TARGET == "island5" then return landmarkTop(findIsland5Spawn()) end
	if SPAWN_TARGET == "jelly" then return landmarkTop(findJelly()) end
	if SPAWN_TARGET == "cookie" then return landmarkTop(findCookie()) end
	return landmarkTop(findIsland1())
end

local function place(char)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end
	task.wait(0.1) -- let the default spawn settle a frame, then move
	local top
	for _ = 1, 20 do top = targetTop(); if top then break end; task.wait(0.25) end
	if top then char:PivotTo(CFrame.new(top)) end
end

local function onPlayer(plr)
	plr.CharacterAdded:Connect(place)
	if plr.Character then task.spawn(place, plr.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end -- Studio Play Solo / live reload

print("[SpawnIsland1] active -- spawning players on: " .. SPAWN_TARGET)
