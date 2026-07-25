--======================================================================
-- IslandTeleport.client.lua  (LocalScript)  -- testing utility
--======================================================================
-- Chat command  /island<N>  (e.g. /island1, /island8) teleports you onto that
-- island. Prefers a SpawnLocation / "spawn"-named brick on the island, else the
-- island's top surface. Client-side (you own your character, so it replicates).
--======================================================================

local Players         = game:GetService("Players")
local Workspace       = game:GetService("Workspace")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer

local function firstBasePart(inst)
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end
local function findIsland(n)
	local exact = Workspace:FindFirstChild("island" .. n)
	if exact then return exact end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") then
			local num = string.lower(d.Name):match("^island[ _]?(%d+)") -- "island8", "island_8", "island 8", "island8 crystal"
			if num and tonumber(num) == n then return d end
		end
	end
	return nil
end
-- world position just above an instance's top surface (raycast down onto it)
local function topOf(inst)
	local cf, sz
	if inst:IsA("Model") then cf, sz = inst:GetBoundingBox() else cf, sz = inst.CFrame, inst.Size end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { inst }
	local hit = Workspace:Raycast(cf.Position + Vector3.new(0, sz.Y, 0), Vector3.new(0, -sz.Y * 2.5, 0), rp)
	local base = (hit and hit.Position) or (cf.Position + Vector3.new(0, sz.Y * 0.5, 0))
	return base + Vector3.new(0, 5, 0)
end
local function spawnPointOf(isle)
	for _, d in ipairs(isle:GetDescendants()) do
		if d:IsA("BasePart") and (d:IsA("SpawnLocation") or string.lower(d.Name):find("spawn", 1, true)) then
			return topOf(d)
		end
	end
	return topOf(isle)
end

local function teleportToIsland(n)
	local isle = findIsland(n)
	if not isle then print(("[IslandTP] island%d not found"):format(n)); return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then print("[IslandTP] no character"); return end

	-- StreamingEnabled: a far island's Model replicates but its PARTS don't, so there's
	-- nothing to stand on yet. Ask the server to stream that region in, then wait for it.
	-- Model.WorldPivot survives streaming, so it gives us somewhere to point the request.
	if not firstBasePart(isle) then
		local target = isle:GetPivot().Position
		if target.Magnitude < 1 then
			print(("[IslandTP] island%d has no parts loaded and no usable pivot -- fly closer"):format(n))
			return
		end
		print(("[IslandTP] island%d not streamed in -- requesting it (this takes a moment)..."):format(n))
		local ok, err = pcall(function() player:RequestStreamAroundAsync(target, 15) end)
		if not ok then print(("[IslandTP] stream request failed: %s"):format(tostring(err))) end

		local t0 = os.clock()
		repeat task.wait(0.2) until firstBasePart(isle) or os.clock() - t0 > 12
		if not firstBasePart(isle) then
			-- last resort: drop the character at the pivot; being there forces the stream in
			char:PivotTo(CFrame.new(target + Vector3.new(0, 12, 0)))
			print(("[IslandTP] island%d still streaming -- moved you to its pivot; it'll pop in around you"):format(n))
			return
		end
	end

	local pos = spawnPointOf(isle)
	char:PivotTo(CFrame.new(pos))
	print(("[IslandTP] teleported to island%d"):format(n))
end

local function onCommand(msg)
	local n = tostring(msg or ""):lower():match("^/island_?(%d+)")
	if n then teleportToIsland(tonumber(n)) end
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m) if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)

print("[IslandTP] ready -- type /island<N> (e.g. /island8) to teleport to that island")
