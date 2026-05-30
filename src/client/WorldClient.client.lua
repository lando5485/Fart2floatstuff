print("WORLDCLIENT STARTED")
repeat task.wait() until _G.CoreClientReady

local Players = game.Players
local player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local IslandUnlockEvent = game:GetService("ReplicatedStorage"):FindFirstChild("IslandUnlockEvent")

local currentKnownIsland = 0
local playerBillboards = {}

local function makeBillboard(parent, text, textColor, textSize)
	local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,120,0,30); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=false; bb.Parent=parent
	local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=textSize or 13; lbl.TextColor3=textColor or Color3.new(1,1,1); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent=lbl
	return bb, lbl
end

local function spawnRing(pos, color, dataIndex, dirVec)
	local ring=Instance.new("Part"); ring.Shape=Enum.PartType.Cylinder; ring.Size=Vector3.new(1,30,30)
	local dir=(dirVec and dirVec.Magnitude>0) and dirVec.Unit or Vector3.new(0,1,0)
	local worldUp=math.abs(dir.Y)<0.9 and Vector3.new(0,1,0) or Vector3.new(1,0,0)
	local yAxis=worldUp-dir*dir:Dot(worldUp); yAxis=yAxis.Magnitude>0.001 and yAxis.Unit or Vector3.new(0,0,1)
	local zAxis=dir:Cross(yAxis).Unit
	ring.CFrame=CFrame.fromMatrix(pos,dir,yAxis,zAxis)
	ring.Material=Enum.Material.Neon; ring.Color=color; ring.CanCollide=false; ring.Anchored=true; ring.Transparency=0.2; ring.CastShadow=false; ring.Parent=workspace
	makeBillboard(ring,"\xF0\x9F\xAA\x99 +BONUS",Color3.new(1,1,1),14)
	local entry={part=ring,pos=pos,color=color,idx=dataIndex,dir=dirVec}
	table.insert(_G.activeRings,entry)
end
_G.spawnRing=spawnRing

local function findIsland(num)
	for _,obj in ipairs(workspace:GetChildren()) do
		if obj.Name:match("^Island_"..num.."_") then return obj end
	end
	return nil
end

local function findStandOnIsland(islandNum)
	local island = findIsland(islandNum)
	if not island then return nil end
	for _, obj in ipairs(island:GetDescendants()) do
		if obj.Name == "Stand_"..islandNum or obj.Name:match("^Stand") then
			if obj:IsA("Model") then
				local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
				if part then return part end
			end
		end
	end
	return island.PrimaryPart or island:FindFirstChildWhichIsA("BasePart")
end

-- spawnLandingPad REMOVED: these were the "Land Here First!" target markers for
-- the (now removed) perfect-landing reward. With the reward gone there is nothing
-- to aim for, so the markers are no longer spawned. _G.landingPads stays an empty
-- table; nothing reads it anymore.

local function startGasPocketPulse(part)
	local function doPulse()
		if not part.Parent then return end
		local t1=TweenService:Create(part,TweenInfo.new(1,Enum.EasingStyle.Sine),{Size=Vector3.new(17,17,17)}); t1:Play()
		t1.Completed:Connect(function()
			if not part.Parent then return end
			local t2=TweenService:Create(part,TweenInfo.new(1,Enum.EasingStyle.Sine),{Size=Vector3.new(13,13,13)}); t2:Play()
			t2.Completed:Connect(function() doPulse() end)
		end)
	end
	doPulse()
end

local function spawnGasPocket(pos)
	local p=Instance.new("Part"); p.Shape=Enum.PartType.Ball; p.Size=Vector3.new(20,20,20)
	p.Material=Enum.Material.Neon; p.Color=Color3.fromRGB(0,255,100); p.Transparency=0.4; p.CanCollide=false; p.Anchored=true; p.CastShadow=false; p.Position=pos; p.Parent=workspace
	local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,80,0,30); bb.StudsOffset=Vector3.new(0,12,0); bb.AlwaysOnTop=false; bb.Parent=p
	local bl=Instance.new("TextLabel"); bl.Size=UDim2.new(1,0,1,0); bl.BackgroundTransparency=1; bl.Font=Enum.Font.GothamBold; bl.TextSize=16; bl.TextColor3=Color3.fromRGB(0,255,100); bl.Text="\xF0\x9F\x92\xA8 GAS!"; bl.Parent=bb; Instance.new("UIStroke").Parent=bl
	task.spawn(function() local angle=0; while p.Parent do angle=angle+math.rad(60); pcall(function() p.CFrame=CFrame.new(p.Position)*CFrame.Angles(0,angle,0) end); task.wait(0.1) end end)
	table.insert(_G.activeGasPockets,p); startGasPocketPulse(p)
end
_G.spawnGasPocket=spawnGasPocket

-- popGasPocket(part): PURELY VISUAL pop when the player touches a fart/gas bubble.
-- A quick expand + fade, a green particle burst, and a pop sound, then it's destroyed.
-- Gives NO gas/power and NO coins -- the caller (CoreClient) handles only this visual.
local function popGasPocket(part)
	if not part or not part.Parent then return end
	-- hide the "GAS!" label immediately so only the pop shows
	local bb = part:FindFirstChildOfClass("BillboardGui"); if bb then bb.Enabled = false end
	-- green sparkle burst (matches the bubble colour)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(0,255,100))
	emitter.Lifetime = NumberRange.new(0.3,0.6)
	emitter.Speed = NumberRange.new(12,22)
	emitter.SpreadAngle = Vector2.new(180,180)
	emitter.Size = NumberSequence.new(1.3)
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(26)
	-- pop sound (PLACEHOLDER id -- swap to your preferred bubble-pop sfx)
	local s = Instance.new("Sound"); s.SoundId = "rbxassetid://9114402399"; s.Volume = 0.5; s.Parent = part; s:Play()
	-- quick expand + fade, then destroy
	local t = TweenService:Create(part, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(30,30,30), Transparency = 1 })
	t:Play()
	t.Completed:Connect(function() if part.Parent then part:Destroy() end end)
	game:GetService("Debris"):AddItem(part, 1.2)  -- backup cleanup
end
_G.popGasPocket = popGasPocket

-- PERFECT/FIRST-LANDING SYSTEM REMOVED: the perfect-landing reward, its
-- "First Landing!" popup/flash/pad-hide effect, and the target pad markers are
-- all gone. There is no longer any bonus or notification for landing precisely
-- on a stand. Normal landing (power refill from the stand, flight counting) is
-- unaffected — it lives entirely in CoreClient's onLand and is untouched.
-- (Previously: islandsLanded guard + showPerfectLanding(pad) + _G.showPerfectLanding.)

local function getStandPosition(islandNum)
	local standPart = findStandOnIsland(islandNum)
	if standPart then return standPart.Position + Vector3.new(0, 25, 0) end
	local p = _G.ISLAND_POS[islandNum]
	return Vector3.new(p.x, p.y+20, p.z)
end

-- Navigation GUI
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end

local navSg=Instance.new("ScreenGui"); navSg.Name="NavGui"; navSg.ResetOnSpawn=false; navSg.Parent=player.PlayerGui
local navFrame=mkFrame(navSg,{Size=UDim2.new(0,44,0,44),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(255,200,0),BackgroundTransparency=0.2,Visible=false}); mkCorner(navFrame,22); mkStroke(navFrame,Color3.fromRGB(200,140,0),2)
local navArrow=mkLabel(navFrame,{Text="\xe2\x86\x91",Font=Enum.Font.GothamBold,TextSize=26,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,1,0),TextXAlignment=Enum.TextXAlignment.Center}); mkStroke(navArrow,Color3.new(0,0,0),1.5)
local navName=mkLabel(navSg,{Text="",Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.new(1,1,1),Size=UDim2.new(0,120,0,16),AnchorPoint=Vector2.new(0.5,0),TextXAlignment=Enum.TextXAlignment.Center,Visible=false}); mkStroke(navName,Color3.new(0,0,0),1)

-- Spawn world objects
task.spawn(function()
	task.wait(3)
	local rng=Random.new(); local ridx=0
	local RINGS_PER_GAP = 2  -- rings per island gap. FEWER = MORE distance between rings. Was 6 (spacing = gap/7); 2 => spacing = gap/3 (~2.3x farther apart).
	-- Horizontal spread of rings OFF the straight-up climb line (was a tiny +/-15 jitter).
	-- Each ring sits a random direction out at MIN..MAX studs, so collecting is a real choice.
	local RING_SPREAD_MIN = 55   -- min studs off the centerline
	local RING_SPREAD_MAX = 110  -- max studs off the centerline
	for i=1,13 do
		local startPos=getStandPosition(i); local endPos=getStandPosition(i+1)
		local safeStart=startPos+Vector3.new(0,120,0)
		local safeEnd=endPos-Vector3.new(0,200,0)
		if safeEnd.Y > endPos.Y-200 then safeEnd=Vector3.new(safeEnd.X,endPos.Y-200,safeEnd.Z) end
		local dVec=safeEnd-safeStart; local dUnit=dVec.Magnitude>0 and dVec.Unit or Vector3.new(0,1,0)
		for j=1,RINGS_PER_GAP do
			local ang=math.random()*2*math.pi
				local rad=RING_SPREAD_MIN+math.random()*(RING_SPREAD_MAX-RING_SPREAD_MIN)
				-- Push the ring FAR off the straight-up climb line so collecting it is a real
				-- CHOICE (players deviate sideways), not something they fly through on a normal ascent.
				local pos=safeStart:Lerp(safeEnd,j/(RINGS_PER_GAP+1))+Vector3.new(math.cos(ang)*rad,0,math.sin(ang)*rad)
			ridx=ridx+1; spawnRing(pos,_G.RING_COLORS[((j-1)%3)+1],ridx,dUnit)
		end
	end
	-- Landing-pad target markers removed alongside the perfect-landing reward (see above).
	for i=1,13 do
		local startPos=getStandPosition(i); local endPos=getStandPosition(i+1)
		local safeStart=startPos+Vector3.new(0,120,0)
		local safeEnd=endPos-Vector3.new(0,200,0)
		if safeEnd.Y > endPos.Y-200 then safeEnd=Vector3.new(safeEnd.X,endPos.Y-200,safeEnd.Z) end
		local function lerpPocket(t)
			return Vector3.new(
				safeStart.X+(safeEnd.X-safeStart.X)*t+(rng:NextNumber()*60-30),
				safeStart.Y+(safeEnd.Y-safeStart.Y)*t,
				safeStart.Z+(safeEnd.Z-safeStart.Z)*t+(rng:NextNumber()*60-30))
		end
		spawnGasPocket(lerpPocket(0.35)); spawnGasPocket(lerpPocket(0.65))
	end
	print("WORLD OBJECTS SPAWNED")
end)

-- OWNER overhead tags: these 3 usernames (lando5485 also matched by UserId for safety) show a single
-- green "Owner" tag instead of the normal island/name billboard. Every OTHER player is unchanged.
local OWNER_NAMES = { ["Broskie310111"] = true, ["itsmaddmax2"] = true, ["lando5485"] = true }
local OWNER_USERIDS = { [1086836724] = true } -- lando5485 (extra safety; the username above also matches)
local function isOwner(p)
	return OWNER_NAMES[p.Name] == true or OWNER_USERIDS[p.UserId] == true
end

-- Ghost trail + flying count loop
task.spawn(function()
	while true do
		task.wait(1)
		local flyingCount=0
		for _,p in ipairs(Players:GetPlayers()) do
			if p~=player then
				local char2=p.Character
				if char2 then local hrp2=char2:FindFirstChild("HumanoidRootPart"); if hrp2 and hrp2:FindFirstChild("FartVelocity") then flyingCount=flyingCount+1 end end
			end
		end
		if _G.isFlying then flyingCount=flyingCount+1 end
		if _G.flyingLabel then _G.flyingLabel.Text=flyingCount>0 and (flyingCount.." player"..(flyingCount==1 and "" or "s").." flying now") or "" end
		for _,p in ipairs(Players:GetPlayers()) do
			if p~=player then
				pcall(function()
					local char2=p.Character; if not char2 then playerBillboards[p]=nil; return end
					local head2=char2:FindFirstChild("Head"); if not head2 then return end
					local bb=playerBillboards[p]
					if not bb or not bb.Parent then
						bb=Instance.new("BillboardGui"); bb.Name="GhostTrailBB"; bb.Size=UDim2.new(0,120,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=false; bb.Parent=head2; playerBillboards[p]=bb
						local dot=Instance.new("Frame"); dot.Name="Dot"; dot.Size=UDim2.new(0,10,0,10); dot.Position=UDim2.new(0,2,0.5,-5); dot.BorderSizePixel=0; dot.ZIndex=2; dot.Parent=bb; local dc=Instance.new("UICorner"); dc.CornerRadius=UDim.new(1,0); dc.Parent=dot
						local lbl=Instance.new("TextLabel"); lbl.Name="Info"; lbl.Size=UDim2.new(1,-14,1,0); lbl.Position=UDim2.new(0,14,0,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=13; lbl.TextColor3=Color3.new(1,1,1); lbl.TextWrapped=true; lbl.LineHeight=1.1; lbl.Parent=bb
						local st=Instance.new("UIStroke"); st.Color=Color3.new(0,0,0); st.Thickness=1.5; st.Parent=lbl
					end
					if isOwner(p) then
						-- OWNER: a single green "Owner" tag — no dot, no username, no island. Also hide the
						-- default Roblox name/health overhead so NOTHING else shows over their head.
						local hum2=char2:FindFirstChildOfClass("Humanoid")
						if hum2 then hum2.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None end
						local dot2=bb:FindFirstChild("Dot"); if dot2 then dot2.Visible=false end
						local lbl2=bb:FindFirstChild("Info")
						if lbl2 then
							lbl2.Text="Owner"; lbl2.TextColor3=Color3.fromRGB(0,255,0)
							lbl2.Position=UDim2.new(0,0,0,0); lbl2.Size=UDim2.new(1,0,1,0)
							lbl2.TextXAlignment=Enum.TextXAlignment.Center
						end
					else
						-- Everyone else: unchanged normal overhead (island-colored dot + Username + Island name).
						local pIsland=1
						pcall(function() local pls2=p:FindFirstChild("leaderstats"); if pls2 then local i2=pls2:FindFirstChild("Island"); if i2 then pIsland=i2.Value end end end)
						local ic=_G.ISLAND_COLORS[pIsland] or Color3.fromRGB(100,200,100)
						local iname2=_G.ISLAND_DISPLAY_NAMES[pIsland] or ("Island "..pIsland)
						local dot2=bb:FindFirstChild("Dot"); if dot2 then dot2.BackgroundColor3=ic end
						local lbl2=bb:FindFirstChild("Info"); if lbl2 then lbl2.Text=p.Name.."\n"..iname2 end
					end
				end)
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(p) playerBillboards[p]=nil end)

-- Island arrival: only triggers when player physically lands on an island surface
RunService.Heartbeat:Connect(function()
	pcall(function()
		local character = player.Character; if not character then return end
		local hum = character:FindFirstChild("Humanoid"); if not hum then return end
		local hrp = character:FindFirstChild("HumanoidRootPart"); if not hrp then return end
		if hum.FloorMaterial == Enum.Material.Air then return end
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {character}
		local result = workspace:Raycast(hrp.Position, Vector3.new(0,-4,0), rayParams)
		if result and result.Instance then
			local testObj = result.Instance
			while testObj and testObj ~= workspace do
				local islandNum = testObj.Name:match("^Island_(%d+)_")
				if islandNum then
					islandNum = tonumber(islandNum)
					if islandNum and islandNum > currentKnownIsland then
						currentKnownIsland = islandNum
						-- NOTE: no welcome here. The "You reached [Island]!" welcome is fired by the
						-- server's authoritative physical-landing detection (WelcomeEvent), not client-side.
						_G.unlockedIslands = _G.unlockedIslands or {}
						for i = 1, islandNum do _G.unlockedIslands[i] = true end
						if IslandUnlockEvent then
							print("ISLAND LANDING DETECTED:", islandNum)
							IslandUnlockEvent:FireServer(islandNum)
						end
					end
					break
				end
				testObj = testObj.Parent
			end
		end
	end)
end)

-- Navigation arrow loop
task.spawn(function()
	local Camera=workspace.CurrentCamera
	while true do
		task.wait(0.1)
		pcall(function()
			local ls=_G.leaderstats; if not ls then navFrame.Visible=false; navName.Visible=false; return end
			local islVal=ls:FindFirstChild("Island"); if not islVal then navFrame.Visible=false; navName.Visible=false; return end
			local nextIsland=islVal.Value+1; if nextIsland>14 then navFrame.Visible=false; navName.Visible=false; return end
			local tp=_G.ISLAND_POS[nextIsland]; local target3D=Vector3.new(tp.x,tp.y,tp.z)
			local vp=Camera.ViewportSize; local cx,cy=vp.X/2,vp.Y/2
			local screenPos,onScreen=Camera:WorldToScreenPoint(target3D)
			local dx,dy=screenPos.X-cx,screenPos.Y-cy
			local margin=60; local maxX=cx-margin; local maxY=cy-margin
			local ex,ey
			if onScreen and screenPos.Z>0 and math.abs(dx)<maxX and math.abs(dy)<maxY then
				ex=screenPos.X; ey=screenPos.Y
			else
				if math.abs(dx)*maxY>=math.abs(dy)*maxX then
					local sign=dx>=0 and 1 or -1; ex=cx+sign*maxX; ey=cy+dy*(maxX/math.max(math.abs(dx),0.001))
				else
					local sign=dy>=0 and 1 or -1; ey=cy+sign*maxY; ex=cx+dx*(maxY/math.max(math.abs(dy),0.001))
				end
			end
			navFrame.Position=UDim2.new(0,ex,0,ey); navName.Position=UDim2.new(0,ex,0,ey+26)
			navArrow.Rotation=math.deg(math.atan2(dy,dx))+90; navFrame.Visible=true
			-- ISLAND-NAME REVEAL: only show the real name once THIS player has REACHED the island.
			-- "HighestIsland" is a per-player, server-authoritative attribute (replicated to the owning
			-- client and updated the instant the player reaches/skips to a new island). We read it via
			-- the LocalPlayer, so each player sees names based on THEIR OWN progress only. This loop
			-- polls every 0.1s, so the label flips from "???" to the real name live the moment their
			-- HighestIsland increases — no respawn or rejoin needed.
			local highest = player:GetAttribute("HighestIsland") or 0
			if nextIsland <= highest then
				-- Visited (island number <= highest reached): show the real island name.
				navName.Text=_G.ISLAND_DISPLAY_NAMES[nextIsland] or ("Island "..nextIsland)
			else
				-- Not yet visited (island number > highest reached): hide the name.
				navName.Text="???"
			end
			navName.Visible=true
		end)
	end
end)

print("WORLDCLIENT READY")
