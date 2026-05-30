print("WORLDCLIENT STARTED")
repeat task.wait() until _G.CoreClientReady

local Players = game.Players
local player = Players.LocalPlayer
local TweenService = game:GetService("TweenService")

local currentKnownIsland = 0
local playerBillboards = {}

local function makeBillboard(parent, text, textColor, textSize)
	local bb=Instance.new("BillboardGui"); bb.Size=UDim2.new(0,120,0,30); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=false; bb.Parent=parent
	local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=textSize or 13; lbl.TextColor3=textColor or Color3.new(1,1,1); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent=lbl
	return bb, lbl
end

local function spawnRing(pos, color, dataIndex, dirVec)
	local ring=Instance.new("Part"); ring.Shape=Enum.PartType.Cylinder; ring.Size=Vector3.new(1,25,25)
	local dir=(dirVec and dirVec.Magnitude>0) and dirVec.Unit or Vector3.new(0,1,0)
	local worldUp=math.abs(dir.Y)<0.9 and Vector3.new(0,1,0) or Vector3.new(1,0,0)
	local yAxis=worldUp-dir*dir:Dot(worldUp); yAxis=yAxis.Magnitude>0.001 and yAxis.Unit or Vector3.new(0,0,1)
	local zAxis=dir:Cross(yAxis).Unit
	ring.CFrame=CFrame.fromMatrix(pos,dir,yAxis,zAxis)
	ring.Material=Enum.Material.Neon; ring.Color=color; ring.CanCollide=false; ring.Anchored=true; ring.Transparency=0.3; ring.CastShadow=false; ring.Parent=workspace
	makeBillboard(ring,"\xF0\x9F\xAA\x99 +BONUS",Color3.new(1,1,1),14)
	local entry={part=ring,pos=pos,color=color,idx=dataIndex,dir=dirVec}
	table.insert(_G.activeRings,entry)
end
_G.spawnRing=spawnRing

local function spawnLandingPad(i)
	local padPos=nil
	local iname=_G.ISLAND_NAMES[i]; local model=workspace:FindFirstChild(iname)
	if model then
		for _,obj in ipairs(model:GetDescendants()) do
			if obj:IsA("ProximityPrompt") and obj.ObjectText=="Stand" then
				local part=obj.Parent
				if part and not part:IsA("BasePart") then part=part:FindFirstChildWhichIsA("BasePart") or (part.Parent and part.Parent:IsA("BasePart") and part.Parent) end
				if part and part:IsA("BasePart") then padPos=part.Position+part.CFrame.LookVector*5+Vector3.new(0,-part.Size.Y/2+0.25,0) end
				break
			end
		end
		if not padPos then
			local bbCF,bbSize; local ok=pcall(function() bbCF,bbSize=model:GetBoundingBox() end)
			if ok and bbCF and bbSize then padPos=bbCF.Position+Vector3.new(0,-bbSize.Y/2+0.5,0) end
		end
	end
	if not padPos then local pos=_G.ISLAND_POS[i]; padPos=Vector3.new(pos.x,pos.y+1,pos.z) end
	local pad=Instance.new("Part"); pad.Size=Vector3.new(8,0.5,8); pad.Color=Color3.fromRGB(255,200,0)
	pad.Material=Enum.Material.Neon; pad.Transparency=0.3; pad.Anchored=true; pad.CanCollide=true; pad.CastShadow=false; pad.Position=padPos; pad.Parent=workspace
	makeBillboard(pad,"\xF0\x9F\x8E\xAF Land Here!",Color3.fromRGB(255,220,0),13)
	table.insert(_G.landingPads,pad)
end

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
	local p=Instance.new("Part"); p.Shape=Enum.PartType.Ball; p.Size=Vector3.new(15,15,15)
	p.Material=Enum.Material.Neon; p.Color=Color3.fromRGB(0,255,100); p.Transparency=0.6; p.CanCollide=false; p.Anchored=true; p.CastShadow=false; p.Position=pos; p.Parent=workspace
	table.insert(_G.activeGasPockets,p); startGasPocketPulse(p)
end
_G.spawnGasPocket=spawnGasPocket

local function showPerfectLanding(pad)
	if _G.CoinEvent then pcall(function() _G.CoinEvent:FireServer(25) end) end
	if _G.showFloatingText then _G.showFloatingText("\xF0\x9F\x8E\xAF Perfect Landing! +25 \xF0\x9F\xAA\x99",Color3.fromRGB(255,220,0)) end
	local orig=pad.Color
	TweenService:Create(pad,TweenInfo.new(0.1),{Color=Color3.new(1,1,1)}):Play()
	task.delay(0.25,function() pcall(function() TweenService:Create(pad,TweenInfo.new(0.25),{Color=orig}):Play() end) end)
end
_G.showPerfectLanding=showPerfectLanding

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
	for i=1,13 do
		local v1=Vector3.new(_G.ISLAND_POS[i].x,_G.ISLAND_POS[i].y,_G.ISLAND_POS[i].z)
		local v2=Vector3.new(_G.ISLAND_POS[i+1].x,_G.ISLAND_POS[i+1].y,_G.ISLAND_POS[i+1].z)
		local dir=(v2-v1).Unit; local dist=(v2-v1).Magnitude
		for j=1,3 do
			local pos=v1+dir*(dist*(j/4)); ridx=ridx+1
			spawnRing(pos,_G.RING_COLORS[((j-1)%3)+1],ridx,dir)
		end
	end
	for i=1,14 do spawnLandingPad(i) end
	for i=1,13 do
		local p1,p2=_G.ISLAND_POS[i],_G.ISLAND_POS[i+1]
		for _=1,2 do
			local t=0.25+rng:NextNumber()*0.5
			local pos=Vector3.new(p1.x+(p2.x-p1.x)*t+rng:NextNumber()*40-20,p1.y+(p2.y-p1.y)*t,p1.z+(p2.z-p1.z)*t+rng:NextNumber()*40-20)
			spawnGasPocket(pos)
		end
	end
	print("WORLD OBJECTS SPAWNED")
end)

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
					local pIsland=1
					pcall(function() local pls2=p:FindFirstChild("leaderstats"); if pls2 then local i2=pls2:FindFirstChild("Island"); if i2 then pIsland=i2.Value end end end)
					local ic=_G.ISLAND_COLORS[pIsland] or Color3.fromRGB(100,200,100)
					local iname2=_G.ISLAND_DISPLAY_NAMES[pIsland] or ("Island "..pIsland)
					local dot2=bb:FindFirstChild("Dot"); if dot2 then dot2.BackgroundColor3=ic end
					local lbl2=bb:FindFirstChild("Info"); if lbl2 then lbl2.Text=p.Name.."\n"..iname2 end
				end)
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(p) playerBillboards[p]=nil end)

-- Island arrival proximity loop
task.spawn(function()
	local ISLAND_DIST=40
	local islandCenters={}
	for i,pos in ipairs(_G.ISLAND_POS) do islandCenters[i]=Vector3.new(pos.x,pos.y,pos.z) end
	while true do
		task.wait(0.2)
		pcall(function()
			local char=player.Character; if not char then return end
			local root=char:FindFirstChild("HumanoidRootPart"); if not root then return end
			local rpos=root.Position
			for i,iname in ipairs(_G.ISLAND_NAMES) do
				local model=workspace:FindFirstChild(iname)
				if model then local ok2,cf=pcall(function() return model:GetBoundingBox() end); if ok2 and cf then islandCenters[i]=cf.Position end end
				local center=islandCenters[i]
				if center and (rpos-center).Magnitude<ISLAND_DIST then
					if i>currentKnownIsland then
						if _G.showArrival then _G.showArrival(i) end
						pcall(function() if _G.UnlockIslandEvent then _G.UnlockIslandEvent:FireServer(i) end end)
						currentKnownIsland=i
					end
				end
			end
		end)
	end
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
			navName.Text=_G.ISLAND_DISPLAY_NAMES[nextIsland] or ("Island "..nextIsland); navName.Visible=true
		end)
	end
end)

print("WORLDCLIENT READY")
