print("EVENTCLIENT STARTED")
repeat task.wait() until _G.CoreClientReady

local Players = game.Players
local player = Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local PlayerGui = player.PlayerGui

local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end

-- Storm GUI
local stormSg=Instance.new("ScreenGui"); stormSg.Name="StormGui"; stormSg.ResetOnSpawn=false; stormSg.ZIndexBehavior=Enum.ZIndexBehavior.Global; stormSg.Parent=PlayerGui
local stormOverlay=mkFrame(stormSg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.fromRGB(20,20,40),BackgroundTransparency=1,ZIndex=5})
local lightningFlash=mkFrame(stormSg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ZIndex=6})

-- Windstorm GUI
local windSg=Instance.new("ScreenGui"); windSg.Name="WindStormGui"; windSg.ResetOnSpawn=false; windSg.Parent=PlayerGui
local windStormFrame=mkFrame(windSg,{Size=UDim2.new(0,200,0,50),Position=UDim2.new(0.5,0,0.5,-25),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(100,150,200),BackgroundTransparency=1,Visible=false}); mkCorner(windStormFrame,12); mkStroke(windStormFrame,Color3.fromRGB(80,120,180),2)
local windStormLabel=mkLabel(windStormFrame,{Text="\xF0\x9F\x92\xA8 WIND STORM!",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,1,0),Position=UDim2.new(0,5,0,0),TextXAlignment=Enum.TextXAlignment.Center}); mkStroke(windStormLabel,Color3.new(0,0,0),1.5)

local birdSpawnTimer=0
local birdSpawnInterval=math.random(20,40)

local function createBird()
	if #_G.activeBirds>=3 then return end
	local char=player.Character; local hrpTarget=char and char:FindFirstChild("HumanoidRootPart"); if not hrpTarget then return end
	local angle=math.random()*math.pi*2
	local spawnPos=hrpTarget.Position+Vector3.new(math.cos(angle)*50,0,math.sin(angle)*50)
	local birdModel=Instance.new("Model"); birdModel.Name="Bird"; birdModel.Parent=workspace
	local body=Instance.new("Part"); body.Name="Body"; body.Size=Vector3.new(2,0.5,1)
	body.Color=Color3.fromRGB(50,50,50); body.Material=Enum.Material.SmoothPlastic; body.CanCollide=false; body.Anchored=false; body.Position=spawnPos; body.Parent=birdModel
	birdModel.PrimaryPart=body
	local birdVel=Instance.new("BodyVelocity"); birdVel.MaxForce=Vector3.new(1e6,1e6,1e6); birdVel.Velocity=Vector3.new(0,0,0); birdVel.Parent=body
	local function makeWing(name,ox)
		local w=Instance.new("Part"); w.Name=name; w.Size=Vector3.new(1.5,0.1,0.5)
		w.Color=Color3.fromRGB(50,50,50); w.Material=Enum.Material.SmoothPlastic; w.CanCollide=false; w.Parent=birdModel
		local weld=Instance.new("Weld"); weld.Part0=body; weld.Part1=w; weld.C0=CFrame.new(ox,0,0); weld.Parent=body
		return weld
	end
	local weld1=makeWing("Wing1",-1.5); local weld2=makeWing("Wing2",1.5)
	local entry={model=birdModel,body=body}
	table.insert(_G.activeBirds,entry)
	task.spawn(function()
		local flapUp=true
		while birdModel.Parent do
			local a=flapUp and 0.5 or -0.3
			pcall(function() weld1.C0=CFrame.new(-1.5,0,0)*CFrame.Angles(0,0,a) end)
			pcall(function() weld2.C0=CFrame.new(1.5,0,0)*CFrame.Angles(0,0,-a) end)
			flapUp=not flapUp; task.wait(0.3)
		end
	end)
	task.spawn(function()
		while birdModel.Parent do
			local c=player.Character; local hrpNow=c and c:FindFirstChild("HumanoidRootPart")
			if not hrpNow then birdModel:Destroy(); break end
			local diff=hrpNow.Position-body.Position
			if diff.Magnitude<4 then
				birdModel:Destroy()
				_G.cosmeticGas=math.max(0,_G.cosmeticGas*0.75)
				if _G.updateMeter then _G.updateMeter() end
				if _G.showFloatingText then _G.showFloatingText("\xF0\x9F\x90\xA6 BIRD ATTACK! -25% gas!",Color3.fromRGB(255,80,0)) end
				pcall(function()
					local eff=_G.effectFlashFrame
					if eff then eff.BackgroundColor3=Color3.fromRGB(255,80,0); eff.BackgroundTransparency=0.6; TweenService:Create(eff,TweenInfo.new(0.2),{BackgroundTransparency=0.97}):Play() end
				end)
				pcall(function()
					local px=math.random(1,2)==1 and math.random(-20,-8) or math.random(8,20)
					local pz=math.random(1,2)==1 and math.random(-20,-8) or math.random(8,20)
					local pushBV=Instance.new("BodyVelocity"); pushBV.MaxForce=Vector3.new(1e6,0,1e6); pushBV.Velocity=Vector3.new(px,0,pz); pushBV.Parent=hrpNow
					task.delay(0.3,function() pcall(function() pushBV:Destroy() end) end)
				end)
				break
			elseif diff.Magnitude>150 then birdModel:Destroy(); break
			else pcall(function() birdVel.Velocity=diff.Unit*40 end) end
			task.wait(0.05)
		end
		for i=#_G.activeBirds,1,-1 do if _G.activeBirds[i].model==birdModel then table.remove(_G.activeBirds,i); break end end
	end)
end

task.spawn(function()
	while true do
		task.wait(1)
		if _G.isFlying then
			birdSpawnTimer=birdSpawnTimer+1
			if birdSpawnTimer>=birdSpawnInterval then birdSpawnTimer=0; birdSpawnInterval=math.random(20,40); createBird() end
		else birdSpawnTimer=0 end
	end
end)

local function spawnRainDrop()
	local char=player.Character; local hrpNow=char and char:FindFirstChild("HumanoidRootPart"); if not hrpNow then return end
	local drop=Instance.new("Part"); drop.Size=Vector3.new(0.05,1,0.05); drop.Color=Color3.new(1,1,1)
	drop.Material=Enum.Material.Neon; drop.Transparency=0.5; drop.CanCollide=false; drop.CastShadow=false; drop.Anchored=false
	drop.Position=hrpNow.Position+Vector3.new(math.random(-30,30),math.random(5,20),math.random(-30,30)); drop.Parent=workspace
	local bv=Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(0,1e6,0); bv.Velocity=Vector3.new(0,-80,0); bv.Parent=drop
	task.delay(2,function() pcall(function() if drop.Parent then drop:Destroy() end end) end)
end

local function spawnWindLine()
	local char=player.Character; local hrpNow=char and char:FindFirstChild("HumanoidRootPart"); if not hrpNow then return end
	local line=Instance.new("Part"); line.Size=Vector3.new(0.05,0.05,3); line.Color=Color3.new(1,1,1)
	line.Material=Enum.Material.Neon; line.Transparency=0.5; line.CanCollide=false; line.CastShadow=false; line.Anchored=false
	line.Position=hrpNow.Position+Vector3.new(math.random(-20,20),math.random(-5,5),math.random(-20,20)); line.Parent=workspace
	local bv=Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(1e6,1e6,1e6); bv.Velocity=_G.windstormDir*40; bv.Parent=line
	task.delay(1,function() pcall(function() if line.Parent then line:Destroy() end end) end)
end

local function startThunderstorm()
	TweenService:Create(stormOverlay,TweenInfo.new(0.5),{BackgroundTransparency=0.6}):Play()
	local endT=tick()+10
	task.spawn(function()
		while tick()<endT and _G.thunderstormActive do
			for _=1,3 do pcall(spawnRainDrop) end
			if math.random()<0.4 then
				lightningFlash.BackgroundTransparency=0; task.wait(0.05)
				if not _G.thunderstormActive then break end
				lightningFlash.BackgroundTransparency=1
			end
			TweenService:Create(stormOverlay,TweenInfo.new(0.2),{BackgroundTransparency=0.5+math.random()*0.2}):Play()
			task.wait(0.5+math.random()*1.5)
		end
		_G.thunderstormActive=false; lightningFlash.BackgroundTransparency=1
		TweenService:Create(stormOverlay,TweenInfo.new(0.5),{BackgroundTransparency=1}):Play()
	end)
end

local function startWindstorm()
	local rx=math.random(1,2)==1 and math.random(-10,-3) or math.random(3,10)
	local rz=math.random(1,2)==1 and math.random(-10,-3) or math.random(3,10)
	_G.windstormDir=Vector3.new(rx,0,rz).Unit
	local dirArrow
	if math.abs(_G.windstormDir.X)>=math.abs(_G.windstormDir.Z) then dirArrow=_G.windstormDir.X>0 and "\xe2\x86\x92" or "\xe2\x86\x90"
	else dirArrow=_G.windstormDir.Z>0 and "\xe2\x86\x93" or "\xe2\x86\x91" end
	windStormLabel.Text="\xF0\x9F\x92\xA8 "..dirArrow.." WIND STORM!"
	windStormFrame.BackgroundTransparency=1; windStormFrame.Visible=true
	TweenService:Create(windStormFrame,TweenInfo.new(0.5),{BackgroundTransparency=0.2}):Play()
	local endT=tick()+10
	task.spawn(function()
		while tick()<endT and _G.windstormActive do for _=1,3 do pcall(spawnWindLine) end; task.wait(0.3) end
		_G.windstormActive=false
		TweenService:Create(windStormFrame,TweenInfo.new(0.5),{BackgroundTransparency=1}):Play()
		task.delay(0.5,function() windStormFrame.Visible=false end)
	end)
end

local function showMilestonePills(milestones)
	for i,m in ipairs(milestones) do
		task.delay((i-1)*0.35,function()
			local mSg=Instance.new("ScreenGui"); mSg.ResetOnSpawn=false; mSg.Parent=PlayerGui
			local pill=Instance.new("Frame"); pill.Size=UDim2.new(0,280,0,42); pill.Position=UDim2.new(0.5,-140,0.45,(i-1)*52); pill.BackgroundColor3=Color3.fromRGB(40,190,40); pill.Parent=mSg
			local co=Instance.new("UICorner"); co.CornerRadius=UDim.new(0,21); co.Parent=pill
			local st=Instance.new("UIStroke"); st.Color=Color3.fromRGB(0,140,0); st.Thickness=2; st.Parent=pill
			local lbl=Instance.new("TextLabel"); lbl.Text=m; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=16; lbl.TextColor3=Color3.new(1,1,1); lbl.Size=UDim2.new(1,-10,1,0); lbl.Position=UDim2.new(0,5,0,0); lbl.BackgroundTransparency=1; lbl.TextXAlignment=Enum.TextXAlignment.Center; lbl.Parent=pill
			pill.BackgroundTransparency=1; pill.Position=UDim2.new(0.5,-140,0.42,(i-1)*52)
			TweenService:Create(pill,TweenInfo.new(0.3,Enum.EasingStyle.Back),{BackgroundTransparency=0,Position=UDim2.new(0.5,-140,0.45,(i-1)*52)}):Play()
			task.delay(2.5,function()
				TweenService:Create(pill,TweenInfo.new(0.4),{BackgroundTransparency=1}):Play()
				task.delay(0.4,function() mSg:Destroy() end)
			end)
		end)
	end
end

local function checkMilestones()
	local peak=_G.peakHeight; local rings=_G.ringsCollectedFlight
	local heightBonus,heightMsg=0,nil
	if peak>5000 then heightBonus,heightMsg=500,"+500 \xF0\x9F\xAA\x99 LEGENDARY!"
	elseif peak>2000 then heightBonus,heightMsg=100,"+100 \xF0\x9F\xAA\x99 Amazing flight!"
	elseif peak>500 then heightBonus,heightMsg=20,"+20 \xF0\x9F\xAA\x99 Nice flight!" end
	local ringBonus,ringMsg=0,nil
	if rings>=6 then ringBonus,ringMsg=200,"+200 \xF0\x9F\xAA\x99 Ring KING!"
	elseif rings>=3 then ringBonus,ringMsg=50,"+50 \xF0\x9F\xAA\x99 Ring Master!" end
	local total=heightBonus+ringBonus
	if total>0 and _G.CoinEvent then pcall(function() _G.CoinEvent:FireServer(total) end) end
	local pills={}
	if heightMsg then table.insert(pills,heightMsg) end
	if ringMsg then table.insert(pills,ringMsg) end
	if #pills>0 then showMilestonePills(pills) end
end
_G.checkMilestones=checkMilestones

-- Server event handler
local ServerEventNotify=_G.ServerEventNotify
if ServerEventNotify then
	ServerEventNotify.OnClientEvent:Connect(function(eventName,dispName,duration,msg,color)
		if eventName=="THUNDERSTORM" then
			_G.thunderstormActive=true; pcall(startThunderstorm); return
		elseif eventName=="WINDSTORM" then
			_G.windstormActive=true; pcall(startWindstorm); return
		end
		_G.serverEventSpeedMult=1; _G.serverEventCoinMult=1; _G.serverEventGasDrainMult=1; _G.serverEventHeightMult=1; _G.serverEventRingMult=1
		if eventName=="END" then
			_G.serverEventActive=false; _G.serverEventDisplayName=""
			if _G.seCountFrame then _G.seCountFrame.Visible=false end
		else
			_G.serverEventActive=true
			_G.serverEventEndTime=os.time()+(tonumber(duration) or 0)
			_G.serverEventDisplayName=tostring(dispName)
			if eventName=="FART_STORM" then _G.serverEventSpeedMult=2
			elseif eventName=="COIN_RUSH" then _G.serverEventCoinMult=3
			elseif eventName=="LOW_GRAVITY" then _G.serverEventSpeedMult=0.5; _G.serverEventGasDrainMult=0.3
			elseif eventName=="POWER_SURGE" then _G.serverEventHeightMult=1.8
			elseif eventName=="RING_FEVER" then _G.serverEventRingMult=5 end
			if _G.seCountFrame then _G.seCountFrame.Visible=true end
			if _G.showServerEventBanner then _G.showServerEventBanner(tostring(msg),color or Color3.new(1,1,1)) end
		end
	end)
end

print("EVENTCLIENT READY")
