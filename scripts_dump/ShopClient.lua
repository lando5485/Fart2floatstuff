print("SHOPCLIENT STARTED")
repeat task.wait() until _G.CoreClientReady

local Players = game.Players
local player = Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService")
local PlayerGui = player.PlayerGui

local midAirRechargeCount = 0
local skipIslandCount = 0
local shopOpen = false
local playerClosedShop = false
local nearIslandNumber = 1

local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

local foodEmojis = {
	Beans="\xF0\x9F\xAB\x98", Broccoli="\xF0\x9F\xA5\xA6", Cabbage="\xF0\x9F\xA5\xAC",
	Turnips="\xF0\x9F\x8C\xBF", Coconuts="\xF0\x9F\xA5\xA5", Bread="\xF0\x9F\x8D\x9E",
	Pasta="\xF0\x9F\x8D\x9D", Popcorn="\xF0\x9F\x8D\xBF", Milk="\xF0\x9F\xA5\x9B",
	Butter="\xF0\x9F\xA7\x88", IceCream="\xF0\x9F\x8D\xA6", Burger="\xF0\x9F\x8D\x94",
	Burrito="\xF0\x9F\x8C\xAF", Pizza="\xF0\x9F\x8D\x95"
}

local sg

-- Sidebar
sg=Instance.new("ScreenGui"); sg.Name="SidebarGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local shopBtn=mkButton(sg,{Size=UDim2.new(0,70,0,70),Position=UDim2.new(0,10,0.5,-90),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.fromRGB(255,140,0),Text=""})
mkCorner(shopBtn,14); mkStroke(shopBtn,Color3.fromRGB(200,100,0),3)
mkLabel(shopBtn,{Text="\xF0\x9F\x9B\x92",Font=Enum.Font.Gotham,TextSize=32,Size=UDim2.new(1,0,0.65,0),RichText=true})
mkLabel(shopBtn,{Text="Shop",Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0.35,0),Position=UDim2.new(0,0,0.65,0)})
local inviteBtn=mkButton(sg,{Size=UDim2.new(0,70,0,70),Position=UDim2.new(0,10,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.fromRGB(140,80,220),Text=""})
mkCorner(inviteBtn,14); mkStroke(inviteBtn,Color3.fromRGB(100,50,180),3)
mkLabel(inviteBtn,{Text="\xF0\x9F\x91\xA5",Font=Enum.Font.Gotham,TextSize=32,Size=UDim2.new(1,0,0.65,0),RichText=true})
mkLabel(inviteBtn,{Text="Invite",Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0.35,0),Position=UDim2.new(0,0,0.65,0)})

-- Food Shop
sg=Instance.new("ScreenGui"); sg.Name="FoodShopGui"; sg.ResetOnSpawn=false; sg.Enabled=false; sg.Parent=PlayerGui
local FoodShopGui=sg
mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0.4})
local foodPanel=mkFrame(sg,{Size=UDim2.new(0,680,0,480),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(240,248,255)})
mkCorner(foodPanel,16); mkStroke(foodPanel,Color3.fromRGB(100,180,255),4)
local foodHeader=mkFrame(foodPanel,{Size=UDim2.new(1,0,0,55),BackgroundColor3=Color3.fromRGB(80,160,255)}); mkCorner(foodHeader,16)
local foodTitle=mkLabel(foodHeader,{Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F ISLAND 1 FOOD STAND",Font=Enum.Font.Gotham,TextSize=24,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-60,1,0),RichText=true})
mkStroke(foodTitle,Color3.new(0,0,0),2)
local foodCloseBtn=mkButton(foodHeader,{Size=UDim2.new(0,40,0,40),Position=UDim2.new(1,-45,0,7),BackgroundColor3=Color3.fromRGB(255,60,60),Text="X",Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.new(1,1,1)}); mkCorner(foodCloseBtn,8)
local foodLeftPanel=mkFrame(foodPanel,{Size=UDim2.new(0,280,1,-65),Position=UDim2.new(0,10,0,65),BackgroundColor3=Color3.new(1,1,1)}); mkCorner(foodLeftPanel,12)
local foodEmoji=mkLabel(foodLeftPanel,{Text="\xF0\x9F\xAB\x98",Font=Enum.Font.Gotham,TextSize=80,Size=UDim2.new(0,120,0,120),Position=UDim2.new(0.5,-60,0,10),RichText=true})
local foodName=mkLabel(foodLeftPanel,{Text="Beans",Font=Enum.Font.GothamBold,TextSize=26,TextColor3=Color3.fromRGB(30,30,30),Size=UDim2.new(1,-10,0,35),Position=UDim2.new(0,5,0,135),TextXAlignment=Enum.TextXAlignment.Center})
local foodPrice=mkLabel(foodLeftPanel,{Text="\xF0\x9F\xAA\x99 10 coins",Font=Enum.Font.Gotham,TextSize=20,TextColor3=Color3.fromRGB(200,140,0),Size=UDim2.new(1,-10,0,28),Position=UDim2.new(0,5,0,174),RichText=true,TextXAlignment=Enum.TextXAlignment.Center})
local foodPower=mkLabel(foodLeftPanel,{Text="+3 power",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=Color3.fromRGB(0,160,60),Size=UDim2.new(1,-10,0,26),Position=UDim2.new(0,5,0,206),TextXAlignment=Enum.TextXAlignment.Center})
local foodBuyBtn=mkButton(foodLeftPanel,{Size=UDim2.new(0.85,0,0,55),Position=UDim2.new(0.075,0,1,-65),BackgroundColor3=Color3.fromRGB(50,200,50),Text="BUY FOOD",Font=Enum.Font.GothamBold,TextSize=22,TextColor3=Color3.new(1,1,1)}); mkCorner(foodBuyBtn,12)
local foodLockedFrame=mkFrame(foodLeftPanel,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.fromRGB(240,240,240),Visible=false}); mkCorner(foodLockedFrame,12)
mkLabel(foodLockedFrame,{Text="\xF0\x9F\x94\x92",Font=Enum.Font.Gotham,TextSize=64,Size=UDim2.new(0,100,0,100),Position=UDim2.new(0.5,-50,0,40),RichText=true})
mkLabel(foodLockedFrame,{Text="Fly here to unlock!",Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.fromRGB(200,0,0),Size=UDim2.new(1,-20,0,60),Position=UDim2.new(0,10,0,155),TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center})
local foodRight=mkFrame(foodPanel,{Size=UDim2.new(1,-300,1,-65),Position=UDim2.new(0,300,0,65),BackgroundColor3=Color3.fromRGB(248,248,248)}); mkCorner(foodRight,12)
mkLabel(foodRight,{Text="ALL FOODS",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=Color3.fromRGB(50,50,50),Size=UDim2.new(1,-10,0,25),Position=UDim2.new(0,5,0,5)})
local foodScroll=Instance.new("ScrollingFrame"); foodScroll.Size=UDim2.new(1,-10,1,-35); foodScroll.Position=UDim2.new(0,5,0,30); foodScroll.BackgroundTransparency=1; foodScroll.ScrollBarThickness=6; foodScroll.CanvasSize=UDim2.new(0,0,0,0); foodScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; foodScroll.Parent=foodRight
local foodGrid=Instance.new("UIGridLayout"); foodGrid.CellSize=UDim2.new(0,155,0,70); foodGrid.CellPadding=UDim2.new(0,6,0,6); foodGrid.Parent=foodScroll
local foodCells={}
for _,f in ipairs(_G.foods) do
	local cell=mkFrame(foodScroll,{Name=f.name,BackgroundColor3=Color3.fromRGB(200,240,200)}); mkCorner(cell,8); mkStroke(cell,Color3.fromRGB(150,200,150),2)
	mkLabel(cell,{Text=foodEmojis[f.name] or "?",Font=Enum.Font.Gotham,TextSize=28,Size=UDim2.new(0,40,1,0),Position=UDim2.new(0,2,0,0),RichText=true})
	mkLabel(cell,{Text=f.name,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.fromRGB(30,30,30),Size=UDim2.new(1,-46,0,30),Position=UDim2.new(0,44,0,5),TextXAlignment=Enum.TextXAlignment.Left})
	mkLabel(cell,{Text="\xF0\x9F\xAA\x99 "..f.price,Font=Enum.Font.Gotham,TextSize=12,TextColor3=Color3.fromRGB(120,80,0),Size=UDim2.new(1,-46,0,20),Position=UDim2.new(0,44,0,38),TextXAlignment=Enum.TextXAlignment.Left,RichText=true})
	foodCells[f.name]=cell
end

-- Premium Shop
sg=Instance.new("ScreenGui"); sg.Name="PremiumShopGui"; sg.ResetOnSpawn=false; sg.Enabled=false; sg.Parent=PlayerGui
local PremiumShopGui=sg
mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0.5})
local premPanel=mkFrame(sg,{Size=UDim2.new(0,700,0,600),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(255,248,200)}); mkCorner(premPanel,16); mkStroke(premPanel,Color3.fromRGB(255,200,0),4)
local premHeader=mkFrame(premPanel,{Size=UDim2.new(1,0,0,60),BackgroundColor3=Color3.fromRGB(255,200,0)}); mkCorner(premHeader,16)
local premTitle=mkLabel(premHeader,{Text="SHOP",Font=Enum.Font.GothamBold,TextSize=28,TextColor3=Color3.fromRGB(100,50,0),Size=UDim2.new(1,-60,1,0)}); mkStroke(premTitle,Color3.new(1,1,1),2)
local premClose=mkButton(premHeader,{Size=UDim2.new(0,40,0,40),Position=UDim2.new(1,-45,0,10),BackgroundColor3=Color3.fromRGB(255,60,60),Text="X",Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.new(1,1,1)}); mkCorner(premClose,8)
mkLabel(premPanel,{Text="GAMEPASSES",Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.fromRGB(80,80,80),Size=UDim2.new(1,-20,0,24),Position=UDim2.new(0,10,0,68),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
local function mkCard(parent,xPos,yPos,icon,title,desc,price,btnCol,btnTxt,onClick)
	local card=mkFrame(parent,{Size=UDim2.new(0,200,0,200),Position=UDim2.new(0,xPos,0,yPos),BackgroundColor3=Color3.new(1,1,1)}); mkCorner(card,12); mkStroke(card,Color3.fromRGB(220,220,220),2)
	mkLabel(card,{Text=icon,Font=Enum.Font.Gotham,TextSize=36,Size=UDim2.new(1,0,0,50),Position=UDim2.new(0,0,0,5),RichText=true})
	mkLabel(card,{Text=title,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.fromRGB(30,30,30),Size=UDim2.new(1,-10,0,35),Position=UDim2.new(0,5,0,55),TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	mkLabel(card,{Text=desc,Font=Enum.Font.Gotham,TextSize=12,TextColor3=Color3.fromRGB(120,120,120),Size=UDim2.new(1,-10,0,40),Position=UDim2.new(0,5,0,90),TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	mkLabel(card,{Text=price,Font=Enum.Font.GothamBold,TextSize=14,TextColor3=Color3.fromRGB(0,150,0),Size=UDim2.new(1,-10,0,18),Position=UDim2.new(0,5,0,132),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	local btn=mkButton(card,{Size=UDim2.new(0.85,0,0,28),Position=UDim2.new(0.075,0,1,-35),BackgroundColor3=btnCol,Text=btnTxt,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.new(1,1,1)}); mkCorner(btn,8); btn.MouseButton1Click:Connect(onClick)
end
mkCard(premPanel,25,98,"PWR","2x Power FOREVER","Double fart power!","249 R$",Color3.fromRGB(255,180,0),"BUY",function() pcall(function() MarketplaceService:PromptGamePassPurchase(player,0) end) end)
mkCard(premPanel,250,98,"GLTR","Glitter Trail","Sparkling trail!","49 R$",Color3.fromRGB(220,80,180),"BUY",function() pcall(function() MarketplaceService:PromptGamePassPurchase(player,0) end) end)
mkCard(premPanel,475,98,"CLR","Custom Color","Your own colour!","89 R$",Color3.fromRGB(140,80,220),"BUY",function() pcall(function() MarketplaceService:PromptGamePassPurchase(player,0) end) end)
mkLabel(premPanel,{Text="ONE-TIME ITEMS",Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.fromRGB(80,80,80),Size=UDim2.new(1,-20,0,24),Position=UDim2.new(0,10,0,308),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
mkCard(premPanel,25,335,"2XHR","2x Power 1 Hour","Double power 60 min!","59 R$",Color3.fromRGB(50,120,255),"BUY",function() pcall(function() MarketplaceService:PromptProductPurchase(player,0) end) end)
mkCard(premPanel,250,335,"RCHG","Mid-Air Recharge","Refill gas instantly!","39 R$",Color3.fromRGB(50,200,50),"BUY",function() pcall(function() MarketplaceService:PromptProductPurchase(player,0) end) end)
mkCard(premPanel,475,335,"SKIP","Skip Island","Unlock next island!","69 R$",Color3.fromRGB(255,140,0),"BUY",function() pcall(function() MarketplaceService:PromptProductPurchase(player,0) end) end)

-- Hotbar
sg=Instance.new("ScreenGui"); sg.Name="HotbarGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local hotbarFrame=mkFrame(sg,{Position=UDim2.new(1,-10,1,-80),Size=UDim2.new(0,140,0,60),AnchorPoint=Vector2.new(1,1),BackgroundTransparency=1,Visible=false})
local hbLayout=Instance.new("UIListLayout"); hbLayout.FillDirection=Enum.FillDirection.Horizontal; hbLayout.Padding=UDim.new(0,5); hbLayout.Parent=hotbarFrame
local rechargeSlot=mkButton(hotbarFrame,{Size=UDim2.new(0,60,0,60),BackgroundColor3=Color3.fromRGB(50,50,50),BackgroundTransparency=0.3,Text="RCHRG",TextSize=11,Font=Enum.Font.GothamBold,TextColor3=Color3.new(1,1,1)}); mkCorner(rechargeSlot,10); mkStroke(rechargeSlot,Color3.fromRGB(100,100,100),2)
local rechargeBadge=mkLabel(rechargeSlot,{Text="0",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=Color3.new(1,1,1),Size=UDim2.new(0,20,0,20),Position=UDim2.new(1,-20,1,-20),BackgroundColor3=Color3.fromRGB(255,60,60)}); mkCorner(rechargeBadge,10)
local skipSlot=mkButton(hotbarFrame,{Size=UDim2.new(0,60,0,60),BackgroundColor3=Color3.fromRGB(50,50,50),BackgroundTransparency=0.3,Text="SKIP",TextSize=13,Font=Enum.Font.GothamBold,TextColor3=Color3.new(1,1,1)}); mkCorner(skipSlot,10); mkStroke(skipSlot,Color3.fromRGB(100,100,100),2)
local skipBadge=mkLabel(skipSlot,{Text="0",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=Color3.new(1,1,1),Size=UDim2.new(0,20,0,20),Position=UDim2.new(1,-20,1,-20),BackgroundColor3=Color3.fromRGB(255,60,60)}); mkCorner(skipBadge,10)

local function updateHotbar()
	hotbarFrame.Visible=midAirRechargeCount>0 or skipIslandCount>0
	rechargeBadge.Text=tostring(midAirRechargeCount)
	skipBadge.Text=tostring(skipIslandCount)
end

local function updateFoodShop(islandNum)
	nearIslandNumber=islandNum
	foodTitle.Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F ISLAND "..islandNum.." FOOD STAND"
	local pIsland=1
	pcall(function() if _G.leaderstats then local i=_G.leaderstats:FindFirstChild("Island"); if i then pIsland=i.Value end end end)
	local locked=islandNum>pIsland
	foodLockedFrame.Visible=locked; foodEmoji.Visible=not locked; foodName.Visible=not locked
	foodPrice.Visible=not locked; foodPower.Visible=not locked; foodBuyBtn.Visible=not locked
	if locked then return end
	local f=_G.foods[islandNum]; if not f then return end
	foodEmoji.Text=foodEmojis[f.name] or "?"
	foodName.Text=f.name
	foodPrice.Text="\xF0\x9F\xAA\x99 "..f.price.." coins"
	foodPower.Text="+"..f.power.." power"
	local coins=0
	pcall(function() if _G.leaderstats then local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end end end)
	if coins>=f.price then foodBuyBtn.BackgroundColor3=Color3.fromRGB(50,200,50); foodBuyBtn.Text="BUY FOOD"; foodBuyBtn.TextSize=22
	else foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text="NOT ENOUGH COINS"; foodBuyBtn.TextSize=16 end
	for _,fd in ipairs(_G.foods) do
		local cell=foodCells[fd.name]; if cell then
			local st=cell:FindFirstChildWhichIsA("UIStroke")
			if fd.island<=pIsland then cell.BackgroundColor3=Color3.fromRGB(200,240,200); if st then st.Color=Color3.fromRGB(150,200,150) end
			else cell.BackgroundColor3=Color3.fromRGB(210,210,210); if st then st.Color=Color3.fromRGB(160,160,160) end end
		end
	end
end

shopBtn.MouseButton1Click:Connect(function() PremiumShopGui.Enabled=not PremiumShopGui.Enabled end)
inviteBtn.MouseButton1Click:Connect(function() pcall(function() SocialService:PromptGameInvite(player) end) end)
premClose.MouseButton1Click:Connect(function() PremiumShopGui.Enabled=false end)
foodCloseBtn.MouseButton1Click:Connect(function() FoodShopGui.Enabled=false; shopOpen=false; playerClosedShop=true end)

foodBuyBtn.MouseButton1Click:Connect(function()
	local f=_G.foods[nearIslandNumber]; if not f then return end
	local coins=0
	pcall(function() if _G.leaderstats then local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end end end)
	if coins<f.price then return end
	pcall(function() if _G.BuyFoodEvent then _G.BuyFoodEvent:FireServer(f.name) end end)
	local fl=Instance.new("TextLabel"); fl.Text="+"..f.power.." power!"; fl.Font=Enum.Font.GothamBold; fl.TextSize=20; fl.TextColor3=Color3.fromRGB(0,200,50); fl.BackgroundTransparency=1; fl.Size=UDim2.new(0,200,0,40); fl.Position=UDim2.new(0.3,0,0.6,0); fl.ZIndex=10; fl.Parent=FoodShopGui
	TweenService:Create(fl,TweenInfo.new(1.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(0.3,0,0.4,0),TextTransparency=1}):Play()
	task.delay(1.5,function() fl:Destroy() end)
end)

rechargeSlot.MouseButton1Click:Connect(function()
	if midAirRechargeCount>0 then
		midAirRechargeCount=midAirRechargeCount-1
		_G.cosmeticGas=100; if _G.updateMeter then _G.updateMeter() end; if _G.updateFartBtn then _G.updateFartBtn() end; updateHotbar()
	end
end)
skipSlot.MouseButton1Click:Connect(function()
	if skipIslandCount>0 then
		skipIslandCount=skipIslandCount-1
		pcall(function() if _G.SkipIslandEvent then _G.SkipIslandEvent:FireServer() end end)
		updateHotbar()
	end
end)

pcall(function()
	if _G.leaderstats then
		local c=_G.leaderstats:FindFirstChild("Coins")
		if c then c.Changed:Connect(function() if _G.updateCoins then _G.updateCoins() end; if shopOpen then updateFoodShop(nearIslandNumber) end end) end
	end
end)

task.spawn(function()
	local STAND_DIST=20
	while true do
		task.wait(0.2)
		pcall(function()
			local char=player.Character; if not char then return end
			local root=char:FindFirstChild("HumanoidRootPart"); if not root then return end
			local rpos=root.Position
			local nearStand,nearIsland=false,1
			for _,obj in ipairs(workspace:GetDescendants()) do
				if obj:IsA("ProximityPrompt") and obj.ObjectText=="Stand" then
					local part=obj.Parent
					if part and not part:IsA("BasePart") then
						part=part:FindFirstChildWhichIsA("BasePart") or (part.Parent and part.Parent:IsA("BasePart") and part.Parent or nil)
					end
					if part and (rpos-part.Position).Magnitude<STAND_DIST then
						nearStand=true; nearIsland=obj:GetAttribute("IslandNumber") or 1; break
					end
				end
			end
			if nearStand and not shopOpen and not playerClosedShop then
				updateFoodShop(nearIsland); FoodShopGui.Enabled=true; shopOpen=true
			elseif not nearStand then
				if shopOpen then FoodShopGui.Enabled=false; shopOpen=false end
				playerClosedShop=false
			end
		end)
	end
end)

print("SHOPCLIENT READY")
