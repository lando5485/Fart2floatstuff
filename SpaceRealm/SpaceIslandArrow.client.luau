--======================================================================
-- SpaceIslandArrow.client.luau   — PUT THIS IN THE *SPACE REALM* PLACE
-- (StarterPlayer > StarterPlayerScripts, as a LocalScript).
--
-- The next-island guidance ARROW, copied from the main game (WorldClient's
-- NEXT-ISLAND POINTER): a big bold WHITE up-arrow with a thick black outline
-- that tracks a target in the world, rotating to point at it and clamping to
-- the screen edge when the target is off-screen / behind you. A small name
-- label sits under it.
--
-- TARGET (pick whichever fits your Space Realm — see CONFIG):
--   1. Tag the island part(s) with the CollectionService tag "SpaceIsland"
--      (Studio: select the part -> Tags -> add "SpaceIsland"). Arrow points to
--      the NEAREST tagged part. (recommended)
--   2. Or list fixed positions in CONFIG.TARGET_POSITIONS.
--   3. Or fall back to the nearest part whose Name contains CONFIG.NAME_CONTAINS.
-- Set a part's "IslandName" attribute (or it uses the part Name) for the label.
--======================================================================

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

--======================================================================
-- CONFIG
--======================================================================
local CONFIG = {
	TARGET_TAG      = "SpaceIsland", -- CollectionService tag on your island part(s)
	NAME_CONTAINS   = "island",      -- fallback: nearest Workspace part whose Name contains this (case-insensitive)
	TARGET_POSITIONS= {},            -- optional explicit targets, e.g. { Vector3.new(0,500,0), Vector3.new(120,900,60) }
	SHOW_NAME       = true,          -- show the island name label under the arrow
	EDGE_MARGIN     = 60,            -- px from screen centre the arrow is allowed to reach when clamped
	HIDE_WITHIN     = 40,            -- hide the arrow once you're this close (studs) to the target
	UPDATE_HZ       = 10,            -- refreshes per second
}

--======================================================================
-- HUD (identical build to the main game's pointer)
--======================================================================
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end

local navSg = Instance.new("ScreenGui"); navSg.Name="SpaceNavGui"; navSg.ResetOnSpawn=false; navSg.IgnoreGuiInset=true; navSg.Parent=player:WaitForChild("PlayerGui")
local navFrame = mkFrame(navSg, { Size=UDim2.new(0,54,0,54), Position=UDim2.new(0.5,0,0.5,0), AnchorPoint=Vector2.new(0.5,0.5), BackgroundTransparency=1, Visible=false })
local navArrow = mkLabel(navFrame, { Text="\xe2\x86\x91", Font=Enum.Font.GothamBold, TextSize=48, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,1,0), TextXAlignment=Enum.TextXAlignment.Center })
local navArrowStroke = mkStroke(navArrow, Color3.new(0,0,0), 5); navArrowStroke.LineJoinMode = Enum.LineJoinMode.Round -- thick black outline
local navName = mkLabel(navSg, { Text="", Font=Enum.Font.Gotham, TextSize=11, TextColor3=Color3.new(1,1,1), Size=UDim2.new(0,120,0,16), AnchorPoint=Vector2.new(0.5,0), TextXAlignment=Enum.TextXAlignment.Center, Visible=false }); mkStroke(navName, Color3.new(0,0,0), 1)

--======================================================================
-- TARGET RESOLUTION: nearest tagged part -> nearest configured position -> nearest name-match part
--======================================================================
local function partPos(p)
	if p:IsA("BasePart") then return p.Position elseif p:IsA("Model") and p.PrimaryPart then return p.PrimaryPart.Position elseif p:IsA("Model") then return p:GetPivot().Position end
	return nil
end
local function labelFor(inst)
	if not inst then return "" end
	local a = inst:GetAttribute("IslandName")
	if a then return tostring(a) end
	return inst.Name
end

local nameCache, nameCacheAt = {}, -1
local function scanNamed()
	nameCache = {}
	local needle = string.lower(CONFIG.NAME_CONTAINS or "")
	if needle == "" then return end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), needle, 1, true) then
			nameCache[#nameCache+1] = d
		end
	end
end

local function resolveTarget(fromPos, clock)
	-- 1) tagged parts
	local best, bestPos, bestD2 = nil, nil, math.huge
	if CONFIG.TARGET_TAG and CONFIG.TARGET_TAG ~= "" then
		for _, inst in ipairs(CollectionService:GetTagged(CONFIG.TARGET_TAG)) do
			if inst:IsDescendantOf(Workspace) then
				local p = partPos(inst)
				if p then local d2=(p-fromPos).Magnitude; if d2<bestD2 then best,bestPos,bestD2=inst,p,d2 end end
			end
		end
	end
	if bestPos then return bestPos, labelFor(best) end
	-- 2) explicit positions
	for _, v in ipairs(CONFIG.TARGET_POSITIONS) do
		local p = (typeof(v)=="Vector3") and v or Vector3.new(v.x or v[1], v.y or v[2], v.z or v[3])
		local d2=(p-fromPos).Magnitude; if d2<bestD2 then best,bestPos,bestD2=nil,p,d2 end
	end
	if bestPos then return bestPos, "" end
	-- 3) nearest name-match part (cached scan, refreshed every ~5s)
	if clock - nameCacheAt > 5 then nameCacheAt = clock; scanNamed() end
	for _, d in ipairs(nameCache) do
		if d.Parent then
			local p = d.Position; local d2=(p-fromPos).Magnitude; if d2<bestD2 then best,bestPos,bestD2=d,p,d2 end
		end
	end
	if bestPos then return bestPos, labelFor(best) end
	return nil, ""
end

--======================================================================
-- LOOP (projection + edge-clamp + rotation — copied from the main game)
--======================================================================
local acc = 0
RunService.RenderStepped:Connect(function(dt)
	acc = acc + dt
	if acc < (1 / CONFIG.UPDATE_HZ) then return end
	acc = 0
	pcall(function()
		local Camera = Workspace.CurrentCamera
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not (Camera and hrp) then navFrame.Visible=false; navName.Visible=false; return end

		local target3D, name = resolveTarget(hrp.Position, os.clock())
		if not target3D or (target3D - hrp.Position).Magnitude <= CONFIG.HIDE_WITHIN then
			navFrame.Visible=false; navName.Visible=false; return
		end

		local vp = Camera.ViewportSize; local cx,cy = vp.X/2, vp.Y/2
		local screenPos = Camera:WorldToScreenPoint(target3D)
		local dx,dy = screenPos.X-cx, screenPos.Y-cy
		local margin = CONFIG.EDGE_MARGIN; local maxX = cx-margin; local maxY = cy-margin
		local ex,ey
		if screenPos.Z>0 and math.abs(dx)<maxX and math.abs(dy)<maxY then
			ex,ey = screenPos.X, screenPos.Y
		else
			-- behind the camera flips the projection; mirror it so the edge math points the right way
			if screenPos.Z < 0 then dx,dy = -dx,-dy end
			if math.abs(dx)*maxY >= math.abs(dy)*maxX then
				local sign = dx>=0 and 1 or -1; ex = cx+sign*maxX; ey = cy+dy*(maxX/math.max(math.abs(dx),0.001))
			else
				local sign = dy>=0 and 1 or -1; ey = cy+sign*maxY; ex = cx+dx*(maxY/math.max(math.abs(dy),0.001))
			end
		end
		navFrame.Position = UDim2.new(0,ex,0,ey)
		navArrow.Rotation = math.deg(math.atan2(dy,dx))+90
		navFrame.Visible = true
		if CONFIG.SHOW_NAME and name ~= "" then
			navName.Position = UDim2.new(0,ex,0,ey+26); navName.Text = name; navName.Visible = true
		else
			navName.Visible = false
		end
	end)
end)

print("[SpaceArrow] Space Realm island pointer ready (tag your island part 'SpaceIsland').")
