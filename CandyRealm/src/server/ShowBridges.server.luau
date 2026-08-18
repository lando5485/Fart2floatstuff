--======================================================================
-- ShowBridges.server.luau  (ServerScriptService.ShowBridges)  -- CandyRealm
--======================================================================
-- Island 1 has two parts named "bridge" that are supposed to be VISIBLE, and are not. This makes them so
-- at boot, from the server, so every client sees them without a republish.
--
-- Only TRANSPARENCY is written. Collision, anchoring, material and colour are left exactly as authored --
-- if a bridge was already walkable while invisible, it stays walkable and merely becomes visible; nothing
-- here can knock a player off it. (InvisibleBarrierSweep is also no longer a threat to them: it strips
-- CanCollide from parts with Transparency >= 0.98, and after this runs the bridges aren't invisible.)
--
-- Matched by NAME ("bridge", case-insensitive, ignoring stray spaces -- this place has parts named
-- "snow " and "chunk ", so trailing-space names are a real local convention) INSIDE island1 only. A
-- Model named bridge counts through its BaseParts.
--======================================================================

local Workspace = game:GetService("Workspace")

local function isBridgeName(name)
	return tostring(name):lower():gsub("^%s+", ""):gsub("%s+$", "") == "bridge"
end

local function reveal(inst)
	local n = 0
	if inst:IsA("BasePart") then
		pcall(function() inst.Transparency = 0 end)
		n = 1
	elseif inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				pcall(function() d.Transparency = 0 end)
				n += 1
			end
		end
	end
	return n
end

task.spawn(function()
	-- island1 can be renamed/nested (this place has island1.island1.island1.island1); search from the
	-- outer model so a bridge at any depth is found.
	local island = Workspace:FindFirstChild("island1") or Workspace:WaitForChild("island1", 30)
	if not island then
		warn("[ShowBridges] island1 never appeared -- no bridges revealed")
		return
	end

	local found, parts = 0, 0
	for _, d in ipairs(island:GetDescendants()) do
		if isBridgeName(d.Name) and (d:IsA("BasePart") or d:IsA("Model")) then
			-- skip BaseParts inside an already-counted bridge Model (reveal() handles their descendants)
			local insideCounted = false
			local p = d.Parent
			while p and p ~= island do
				if isBridgeName(p.Name) then insideCounted = true; break end
				p = p.Parent
			end
			if not insideCounted then
				found += 1
				parts += reveal(d)
			end
		end
	end

	if found == 0 then
		warn("[ShowBridges] no part or model named 'bridge' found on island1 -- check the names in Studio (ParkScan-style: exact word, spaces ignored)")
	elseif found ~= 2 then
		warn(("[ShowBridges] expected 2 bridges on island1, found %d (%d part(s) revealed) -- revealed them all anyway"):format(found, parts))
	else
		print(("[ShowBridges] both island1 bridges visible (%d part(s) set Transparency 0)"):format(parts))
	end
end)
