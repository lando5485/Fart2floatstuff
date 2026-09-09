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

-- ✅ CURRENTLY "island1" -- THE REAL START, which is where this should stay.
-- island1 (Candy Cane Court) is slot 1: the tutorial, the community garden and the gumball hunt are all
-- built on it. Every other value here is a testing shortcut that skips those, and the off-ladder ones
-- (16, 18, 19) drop you somewhere with no crossing back down -- you would need the wormhole to leave.
-- Now that the wormhole lists all fourteen islands, warping is the better way to test one island, and
-- this can just stay pointed at the start.
local SPAWN_TARGET = "island1" -- "island1" | "cookie" (island3) | "jelly" (island4) | "island5" (delivery) | "island8" (crystal mine) | "island16" (candy mine) | "island18" (pancake monster) | "island19" (broken tractor)

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

-- THE SPAWN BRICK, not the top of the island.
--
-- island1 used to resolve to the MODEL, and targetTop() raycasts down onto whatever the highest surface
-- of that model happens to be -- a shop roof, a candy cane, the tutorial sign. So players spawned on top
-- of scenery instead of on the pad the island was built around.
--
-- island5 and island8 already did this correctly (look for a SpawnLocation or a "spawn"-named part INSIDE
-- the island first, then the nearest one outside it, then give up and use the island). This is that same
-- ladder, so all three targets now behave the same way.
local function findIsland1Spawn()
	local isle = findIsland1()
	if isle then
		local inside = findFirstIn(isle, function(o)
			return o:IsA("BasePart") and (o:IsA("SpawnLocation") or string.lower(o.Name):find("spawn", 1, true))
		end)
		if inside then return inside end
	end
	-- Not parented under the island (a SpawnLocation sitting loose in Workspace is common) -> take the
	-- closest one to the island, bounded so we can never grab another island's pad.
	local ref = isle and (isle:IsA("Model") and (isle.PrimaryPart or firstBasePartOf(isle)) or isle)
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
	return isle -- no pad anywhere -> the old behaviour, rather than not spawning them at all
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

-- ===== THE OFF-LADDER ISLANDS (island16 Candy Mine, island18 Pancake Monster) =====
-- Same shape as island5/island8: prefer a spawn brick INSIDE the island, and only fall back to the island
-- itself. These islands are OFF THE LADDER (not in IslandOrder), so nothing else in the realm places
-- anything on them -- which is why this resolver also BUILDS the pad if there isn't one.
--
-- TAKES THE ISLAND NAME rather than hard-coding one: there are two of these now and there will be more,
-- and a copy-pasted second resolver is how the two drift apart.
local function offLadderSpawn(islandName)
	local isle = Workspace:FindFirstChild(islandName)
	if not isle then return nil end

	-- 1) YOUR brick wins. A SpawnLocation, or any part with "spawn" in the name, placed inside the island
	-- in Studio -- exactly the convention island1, island5 and island8 already use.
	local inside = findFirstIn(isle, function(o)
		return o:IsA("BasePart") and (o:IsA("SpawnLocation") or string.lower(o.Name):find("spawn", 1, true))
	end)
	if inside then return inside end

	-- 2) None there -> build one, once, on the island's top surface.
	--
	-- Enabled = FALSE on purpose. This is a MARKER for place() to aim at, not a competing Roblox spawn
	-- point: an enabled SpawnLocation would join the engine's random spawn rotation and could drop players
	-- who are meant to start on island1 onto an off-ladder island before place() had a chance to move them.
	-- place() below does the actual positioning, so the pad only has to exist and be in the right spot.
	local top = landmarkTop(isle)
	if not top then return nil end
	local pad = Instance.new("SpawnLocation")
	pad.Name = islandName .. "spawn"
	pad.Size = Vector3.new(12, 1, 12)
	pad.CFrame = CFrame.new(top - Vector3.new(0, 4, 0))  -- landmarkTop adds 5; sit the pad on the surface
	pad.Anchored = true
	pad.CanCollide = true
	pad.Enabled = false
	pad.Neutral = true
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(255, 95, 160)
	pad.Transparency = 0.35
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.Parent = isle
	print(("[SpawnIsland1] %s had no spawn brick -- built '%sspawn' at (%d, %d, %d)")
		:format(islandName, islandName, pad.Position.X, pad.Position.Y, pad.Position.Z))
	return pad
end

local function targetTop()
	if SPAWN_TARGET == "island19" then return landmarkTop(offLadderSpawn("island19")) end
	if SPAWN_TARGET == "island18" then return landmarkTop(offLadderSpawn("island18")) end
	if SPAWN_TARGET == "island16" then return landmarkTop(offLadderSpawn("island16")) end
	if SPAWN_TARGET == "island8" then return landmarkTop(findIsland8Spawn()) end
	if SPAWN_TARGET == "island5" then return landmarkTop(findIsland5Spawn()) end
	if SPAWN_TARGET == "jelly" then return landmarkTop(findJelly()) end
	if SPAWN_TARGET == "cookie" then return landmarkTop(findCookie()) end
	return landmarkTop(findIsland1Spawn())
end

-- WHICH WAY YOU ARE FACING WHEN YOU ARRIVE.
--
-- place() used to position with CFrame.new(top), which carries IDENTITY rotation -- so every
-- player spawned facing +Z no matter what was actually in front of them, and on island1 that is
-- the wrong way round: you land looking away from the island you are meant to walk into.
--
-- 180 is the flip that fixes it. It is a named constant rather than an inline CFrame.Angles
-- because "which way does the spawn face" is a thing you re-tune by eye after moving the pad, and
-- it should be one number to change, in one place, with its own name.
local SPAWN_YAW = 180

-- ===== RESPAWNS GO TO YOUR HIGHEST ISLAND, NOT THE BOTTOM OF THE TOWER =====
-- The FIRST placement of a session is island1 as always (the tutorial and the intro live
-- there). Every death after that puts you back on the highest island you have reached --
-- HighestSlot is the server's own attribute (FlightEconomy / GutProgression write it), so a
-- client cannot spoof its way up. Slot 1, a missing island model, or any resolve failure all
-- fall back to the island1 pad, so nobody can respawn into nothing.
local IslandOrder = require(game:GetService("ReplicatedStorage")
	:WaitForChild("Shared"):WaitForChild("IslandOrder"))
local placedOnce = {}   -- [player] = true after their first placement this session
Players.PlayerRemoving:Connect(function(plr) placedOnce[plr] = nil end)

local function highestTop(plr)
	local slot = math.floor(tonumber(plr:GetAttribute("HighestSlot")) or 1)
	if slot <= 1 then return nil end
	local n = IslandOrder.SLOT_TO_ISLAND[slot]
	local m = n and Workspace:FindFirstChild("island" .. n)
	if not (m and m:IsA("Model")) then return nil end
	local ok, cf, size = pcall(function()
		local c, s = m:GetBoundingBox()
		return c, s
	end)
	if not (ok and cf and size) then return nil end
	-- stand on whatever the island's own centre column actually holds: a ray through the model
	-- finds the deck (or a roof, which is also fine to stand on); the bounding-box top is the
	-- last resort
	local topY = cf.Position.Y + size.Y * 0.5
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { m }
	local hit = Workspace:Raycast(Vector3.new(cf.Position.X, topY + 40, cf.Position.Z),
		Vector3.new(0, -(size.Y + 80), 0), rp)
	local at = hit and hit.Position or Vector3.new(cf.Position.X, topY, cf.Position.Z)
	return at + Vector3.new(0, 4, 0)
end

local function place(char)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end
	task.wait(0.1) -- let the default spawn settle a frame, then move
	local plr = Players:GetPlayerFromCharacter(char)
	local top
	if plr and placedOnce[plr] then top = highestTop(plr) end   -- respawn: highest island reached
	if not top then
		for _ = 1, 20 do top = targetTop(); if top then break end; task.wait(0.25) end
	end
	if top then
		-- position AND facing. PivotTo takes the whole CFrame, so the yaw rides along with it -- and
		-- the intro records this same CFrame as its "home", so the facing survives the cinematic
		-- putting the player back down at the end.
		char:PivotTo(CFrame.new(top) * CFrame.Angles(0, math.rad(SPAWN_YAW), 0))
		-- PUBLISH IT, as a replicated ATTRIBUTE (not _G -- this is a server script and the reader is a
		-- LocalScript, and _G does not cross that boundary).
		--
		-- The intro cinematic carries the character up the whole tower and puts it back at the end; it
		-- records "home" when it starts, which can be BEFORE this function has finished resolving the pad
		-- (the loop above waits up to 5s for the island to stream in, and the intro fires at ~1s). Without
		-- this the cinematic would faithfully restore the player to wherever the DEFAULT spawn dropped
		-- them, quietly undoing the placement above. Intro.client prefers this over its own snapshot.
		-- (plr resolved at the top of place() now, for the respawn routing)
		if plr then
			plr:SetAttribute("CandySpawnTop", top)
			placedOnce[plr] = true   -- from here on, deaths respawn at the highest island reached
		end
	end
end

local function onPlayer(plr)
	plr.CharacterAdded:Connect(place)
	if plr.Character then task.spawn(place, plr.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end -- Studio Play Solo / live reload

print("[SpawnIsland1] active -- first spawn on: " .. SPAWN_TARGET
	.. "; respawns land on the player's highest island reached (HighestSlot)")
