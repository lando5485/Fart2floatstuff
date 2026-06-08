print("SHOPCLIENT STARTED")
repeat task.wait() until _G.CoreClientReady

local Players = game.Players
local player = Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService")
local PlayerGui = player.PlayerGui
local MPS = MarketplaceService
local GAMEPASS_IDS = {TwoXForever=1862015450, GlitterTrail=1859714979}
local PRODUCT_IDS = {TwoXOneHour=3600302990, MidAirRecharge=3600303163, SkipIsland=3600303265, BirdNuke=3600303082}
-- Shared coin icon IMAGE: the SAME verified asset used by the coin counter and daily-rewards
-- icons (emoji glyphs like 🪙 don't render in Roblox text). Literal here so it's correct
-- regardless of script load order. Shop prices show this image instead of the missing emoji.
local COIN_IMAGE = "rbxassetid://106760789458573"

local shopOpen = false
local playerClosedShop = false
local nearIslandNumber = 1
local unlockedIslands = {[1]=true}
local stands = {}
local lastAwayTime = 0
local STAND_TRIGGER_RADIUS = 12 -- studs: how close (horizontally) the player must walk to a stand before its shop opens (was 15 original -> 9 reduced -> 12 midpoint)

local function isUnlocked(islandNum)
	if unlockedIslands[islandNum] then
		return true
	end
	if _G.unlockedIslands and _G.unlockedIslands[islandNum] then
		unlockedIslands[islandNum] = true
		return true
	end
	return false
end

local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

local foodEmojis = {
	Beans="\xF0\x9F\xA5\x9C", Broccoli="\xF0\x9F\xA5\xA6", Cabbage="\xF0\x9F\xA5\xAC",
	Turnips="\xF0\x9F\x8C\xBF", Coconuts="\xF0\x9F\xA5\xA5", Bread="\xF0\x9F\x8D\x9E",
	Pasta="\xF0\x9F\x8D\x9D", Popcorn="\xF0\x9F\x8D\xBF", Milk="\xF0\x9F\xA5\x9B",
	Butter="\xF0\x9F\xA7\x88", IceCream="\xF0\x9F\x8D\xA6", Burger="\xF0\x9F\x8D\x94",
	Burrito="\xF0\x9F\x8C\xAF", Pizza="\xF0\x9F\x8D\x95"
}

local sg


-- Food Shop
sg=Instance.new("ScreenGui"); sg.Name="FoodShopGui"; sg.ResetOnSpawn=false; sg.Enabled=false; sg.DisplayOrder=100; sg.Parent=PlayerGui -- DisplayOrder 100 = definitively above the HUD (<=5) so the shop covers it
local FoodShopGui=sg
mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,Active=true}) -- invisible (was 0.4 dark film); Active=true keeps it click-blocking so HUD stays visible but not interactable while shop is open
local foodPanel=mkFrame(sg,{Size=UDim2.new(0.92,0,0.78,0),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(240,248,255)})
mkCorner(foodPanel,16); mkStroke(foodPanel,Color3.fromRGB(100,180,255),4)
local foodHeader=mkFrame(foodPanel,{Size=UDim2.new(1,0,0,55),BackgroundColor3=Color3.fromRGB(80,160,255)}); mkCorner(foodHeader,16)
local foodTitle=mkLabel(foodHeader,{Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F ISLAND 1 FOOD STAND",Font=Enum.Font.Gotham,TextSize=24,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-60,1,0),RichText=true})
mkStroke(foodTitle,Color3.new(0,0,0),2)
local foodCloseBtn=mkButton(foodHeader,{Size=UDim2.new(0,40,0,40),Position=UDim2.new(1,-45,0,7),BackgroundColor3=Color3.fromRGB(255,60,60),Text="X",Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.new(1,1,1)}); mkCorner(foodCloseBtn,8)
local foodLeftPanel=mkFrame(foodPanel,{Size=UDim2.new(0,280,1,-65),Position=UDim2.new(0,10,0,65),BackgroundColor3=Color3.new(1,1,1)}); mkCorner(foodLeftPanel,12)
local foodEmoji=Instance.new("TextLabel")
foodEmoji.Name="FoodEmoji"; foodEmoji.Size=UDim2.new(0,120,0,120)
foodEmoji.Position=UDim2.new(0.5,-60,0,10); foodEmoji.BackgroundTransparency=1
foodEmoji.Text="\xF0\x9F\xA5\x9C"; foodEmoji.TextSize=80; foodEmoji.Font=Enum.Font.Gotham
foodEmoji.RichText=false; foodEmoji.TextScaled=false
foodEmoji.TextXAlignment=Enum.TextXAlignment.Center; foodEmoji.TextYAlignment=Enum.TextYAlignment.Center
foodEmoji.Parent=foodLeftPanel
local foodName=mkLabel(foodLeftPanel,{Text="Beans",Font=Enum.Font.GothamBold,TextSize=26,TextColor3=Color3.fromRGB(30,30,30),Size=UDim2.new(1,-10,0,35),Position=UDim2.new(0,5,0,135),TextXAlignment=Enum.TextXAlignment.Center})
-- Price row: a centered [coin IMAGE][price text] pair (replaces the non-rendering 🪙 emoji
-- prefix). foodPrice stays the price TextLabel so the live update below works unchanged.
local foodPriceRow=mkFrame(foodLeftPanel,{Name="PriceRow",Size=UDim2.new(1,-10,0,28),Position=UDim2.new(0,5,0,174),BackgroundTransparency=1})
local fprLayout=Instance.new("UIListLayout"); fprLayout.FillDirection=Enum.FillDirection.Horizontal
fprLayout.HorizontalAlignment=Enum.HorizontalAlignment.Center; fprLayout.VerticalAlignment=Enum.VerticalAlignment.Center
fprLayout.Padding=UDim.new(0,4); fprLayout.SortOrder=Enum.SortOrder.LayoutOrder; fprLayout.Parent=foodPriceRow
local foodPriceIcon=Instance.new("ImageLabel"); foodPriceIcon.Name="CoinIcon"; foodPriceIcon.LayoutOrder=1
foodPriceIcon.Size=UDim2.new(0,22,0,22); foodPriceIcon.BackgroundTransparency=1
foodPriceIcon.Image=COIN_IMAGE; foodPriceIcon.ScaleType=Enum.ScaleType.Fit; foodPriceIcon.Parent=foodPriceRow
local foodPrice=mkLabel(foodPriceRow,{Name="PriceText",Text="10 coins",Font=Enum.Font.Gotham,TextSize=20,TextColor3=Color3.fromRGB(200,140,0),Size=UDim2.new(0,150,1,0),TextXAlignment=Enum.TextXAlignment.Left,LayoutOrder=2})
local foodPower=mkLabel(foodLeftPanel,{Text="+3 power",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=Color3.fromRGB(0,160,60),Size=UDim2.new(1,-10,0,26),Position=UDim2.new(0,5,0,206),TextXAlignment=Enum.TextXAlignment.Center})
local foodBuyBtn=mkButton(foodLeftPanel,{Size=UDim2.new(0.44,0,0,50),Position=UDim2.new(0.04,0,1,-58),BackgroundColor3=Color3.fromRGB(50,200,50),Text="BUY FOOD",Font=Enum.Font.GothamBold,TextSize=17,TextColor3=Color3.new(1,1,1)}); mkCorner(foodBuyBtn,12)
local foodBuyMaxBtn=mkButton(foodLeftPanel,{Size=UDim2.new(0.44,0,0,50),Position=UDim2.new(0.52,0,1,-58),BackgroundColor3=Color3.fromRGB(255,140,0),Text="BUY MAX",Font=Enum.Font.GothamBold,TextSize=15,TextColor3=Color3.new(1,1,1)}); mkCorner(foodBuyMaxBtn,12)
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
	local emojiFrame=Instance.new("Frame"); emojiFrame.Name="EmojiFrame"
	emojiFrame.Size=UDim2.new(0,55,0,55); emojiFrame.Position=UDim2.new(0,2,0.5,0); emojiFrame.AnchorPoint=Vector2.new(0,0.5)
	emojiFrame.BackgroundTransparency=1; emojiFrame.ClipsDescendants=false; emojiFrame.Parent=cell
	local emojiLabel=Instance.new("TextLabel"); emojiLabel.Name="FoodEmoji"
	emojiLabel.Size=UDim2.new(0,50,0,50); emojiLabel.Position=UDim2.new(0.5,0,0.5,0); emojiLabel.AnchorPoint=Vector2.new(0.5,0.5)
	emojiLabel.BackgroundTransparency=1; emojiLabel.Text=foodEmojis[f.name] or "\xF0\x9F\x8D\xBD\xEF\xB8\x8F"
	emojiLabel.TextSize=34; emojiLabel.Font=Enum.Font.Gotham; emojiLabel.RichText=false
	emojiLabel.TextColor3=Color3.fromRGB(255,255,255)
	emojiLabel.TextXAlignment=Enum.TextXAlignment.Center; emojiLabel.TextYAlignment=Enum.TextYAlignment.Center
	emojiLabel.Parent=emojiFrame
	mkLabel(cell,{Name="NameLabel",Text=f.name,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.fromRGB(30,30,30),Size=UDim2.new(1,-62,0,30),Position=UDim2.new(0,60,0,5),TextXAlignment=Enum.TextXAlignment.Left})
	-- Coin IMAGE for the cell's price row (replaces the 🪙 emoji prefix). Toggled with the
	-- price text in updateFoodShop (hidden for locked cells, shown for unlocked/priced cells).
	local priceIcon=Instance.new("ImageLabel"); priceIcon.Name="PriceIcon"
	priceIcon.Size=UDim2.new(0,14,0,14); priceIcon.Position=UDim2.new(0,60,0,41); priceIcon.BackgroundTransparency=1
	priceIcon.Image=COIN_IMAGE; priceIcon.ScaleType=Enum.ScaleType.Fit; priceIcon.Parent=cell
	mkLabel(cell,{Name="PriceLabel",Text=tostring(f.price),Font=Enum.Font.Gotham,TextSize=12,TextColor3=Color3.fromRGB(120,80,0),Size=UDim2.new(1,-80,0,20),Position=UDim2.new(0,78,0,38),TextXAlignment=Enum.TextXAlignment.Left})
	foodCells[f.name]=cell
end
print("ICON FIX DONE")

-- Premium Shop
sg=Instance.new("ScreenGui"); sg.Name="PremiumShopGui"; sg.ResetOnSpawn=false; sg.Enabled=false; sg.DisplayOrder=100; sg.Parent=PlayerGui -- DisplayOrder 100 = definitively above the HUD (<=5) so the shop covers it
local PremiumShopGui=sg
mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,Active=true}) -- invisible (was 0.5 dark film); Active=true keeps it click-blocking so HUD stays visible but not interactable while shop is open
local premPanel=mkFrame(sg,{Size=UDim2.new(0.9,0,0.85,0),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(25,90,185),ClipsDescendants=true})
mkCorner(premPanel,20); mkStroke(premPanel,Color3.new(1,1,1),3)

local premHeader=mkFrame(premPanel,{Size=UDim2.new(1,0,0,65),BackgroundColor3=Color3.fromRGB(15,60,140)})
local premTitleLbl=mkLabel(premHeader,{Text="\xF0\x9F\x9B\x92 SHOP",Font=Enum.Font.GothamBold,TextSize=30,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,-60,0,40),Position=UDim2.new(0,14,0,5),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
mkStroke(premTitleLbl,Color3.new(0,0,0),2)
mkLabel(premHeader,{Text="Power up your farts!",Font=Enum.Font.Gotham,TextSize=14,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-60,0,18),Position=UDim2.new(0,14,0,45),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
local premClose=mkButton(premHeader,{Size=UDim2.new(0,40,0,40),Position=UDim2.new(1,-48,0,12),BackgroundColor3=Color3.fromRGB(220,50,50),Text="\xe2\x9c\x95",Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.new(1,1,1)})
mkCorner(premClose,8)

mkLabel(premPanel,{Text="\xe2\xad\x90 GAMEPASSES",Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,-20,0,22),Position=UDim2.new(0,12,0,74),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
mkFrame(premPanel,{Size=UDim2.new(1,-24,0,2),Position=UDim2.new(0,12,0,97),BackgroundColor3=Color3.fromRGB(255,215,0)})

local function mkShopCard(xPos,yPos)
	local c=mkFrame(premPanel,{Size=UDim2.new(0,175,0,200),Position=UDim2.new(0,xPos,0,yPos),BackgroundColor3=Color3.fromRGB(20,70,160)})
	mkCorner(c,16); mkStroke(c,Color3.new(1,1,1),2); return c
end
local function cardIcon(card,txt)
	local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,54); l.Position=UDim2.new(0,0,0,28)
	l.BackgroundTransparency=1; l.Text=txt; l.TextSize=48; l.Font=Enum.Font.Gotham
	l.RichText=false; l.TextXAlignment=Enum.TextXAlignment.Center; l.TextYAlignment=Enum.TextYAlignment.Center; l.Parent=card
end
local function cardTitles(card,main,sub,subCol)
	mkLabel(card,{Text=main,Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-8,0,20),Position=UDim2.new(0,4,0,87),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
	mkLabel(card,{Text=sub,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=subCol,Size=UDim2.new(1,-8,0,18),Position=UDim2.new(0,4,0,108),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
end
local function cardPrice(card,price)
	mkLabel(card,{Text=price,Font=Enum.Font.GothamBold,TextSize=15,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,-8,0,18),Position=UDim2.new(0,4,0,127),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
end
local function cardDesc(card,desc)
	mkLabel(card,{Text=desc,Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.fromRGB(180,210,255),Size=UDim2.new(1,-8,0,13),Position=UDim2.new(0,4,0,143),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})
end
local function cardBuyBtn(card,col,txt,onClick)
	local btn=mkButton(card,{Size=UDim2.new(1,-16,0,36),Position=UDim2.new(0,8,1,-44),BackgroundColor3=col,Text=txt,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.new(1,1,1)})
	mkCorner(btn,8); btn.MouseButton1Click:Connect(onClick); return btn
end

-- Card 1: 2x Power Forever
local card1=mkShopCard(12,104)
local gpBadge=mkLabel(card1,{Text="BEST VALUE \xe2\xad\x90",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=Color3.fromRGB(80,40,0),Size=UDim2.new(1,-8,0,18),Position=UDim2.new(0,4,0,4),BackgroundColor3=Color3.fromRGB(255,180,0),TextXAlignment=Enum.TextXAlignment.Center})
mkCorner(gpBadge,6)
cardIcon(card1,"\xe2\x9a\xa1"); cardTitles(card1,"2x Power","FOREVER",Color3.fromRGB(100,220,100)); cardPrice(card1,"249 R$")
local btn1=cardBuyBtn(card1,Color3.fromRGB(255,180,0),"BUY GAMEPASS",function()
	if _G.playerGamepasses and _G.playerGamepasses.twoXForever then return end -- already owned: do nothing
	pcall(function() MPS:PromptGamePassPurchase(player,GAMEPASS_IDS.TwoXForever) end)
end)
mkStroke(btn1,Color3.fromRGB(200,130,0),2)

-- Card 2: Glitter Trail
local card2=mkShopCard(222,104)
cardIcon(card2,"\xe2\x9c\xa8"); cardTitles(card2,"Glitter Trail","PERMANENT",Color3.fromRGB(100,220,100)); cardPrice(card2,"49 R$")
local btn2=cardBuyBtn(card2,Color3.fromRGB(220,80,180),"BUY GAMEPASS",function()
	if _G.playerGamepasses and _G.playerGamepasses.glitterTrail then return end -- already owned: do nothing
	pcall(function() MPS:PromptGamePassPurchase(player,GAMEPASS_IDS.GlitterTrail) end)
end)

-- Card 3: 2x Power 1 Hour
local card3=mkShopCard(432,104)
cardIcon(card3,"\xe2\x8f\xb0"); cardTitles(card3,"2x Power","1 HOUR",Color3.fromRGB(255,200,100)); cardPrice(card3,"59 R$")
local twoXShopTimer=mkLabel(card3,{Text="",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=Color3.fromRGB(100,220,100),Size=UDim2.new(1,-8,0,13),Position=UDim2.new(0,4,0,143),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1,Visible=false})
cardBuyBtn(card3,Color3.fromRGB(50,150,255),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.TwoXOneHour) end) end)

mkLabel(premPanel,{Text="\xF0\x9F\x8E\xAF ONE-TIME ITEMS",Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,-20,0,22),Position=UDim2.new(0,12,0,316),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
mkFrame(premPanel,{Size=UDim2.new(1,-24,0,2),Position=UDim2.new(0,12,0,339),BackgroundColor3=Color3.fromRGB(255,215,0)})

-- Card 4: Mid-Air Recharge
local card4=mkShopCard(12,346)
cardIcon(card4,"\xF0\x9F\x94\x8B"); cardTitles(card4,"Mid-Air","RECHARGE",Color3.fromRGB(100,220,100)); cardPrice(card4,"39 R$"); cardDesc(card4,"Refills gas to 100%!")
cardBuyBtn(card4,Color3.fromRGB(50,200,50),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.MidAirRecharge) end) end)

-- Card 5: Skip Island
local card5=mkShopCard(222,346)
cardIcon(card5,"\xF0\x9F\x8F\x9D\xEF\xB8\x8F"); cardTitles(card5,"Skip Island","ONE USE",Color3.fromRGB(255,200,100)); cardPrice(card5,"69 R$"); cardDesc(card5,"Jump to next island!")
cardBuyBtn(card5,Color3.fromRGB(255,140,0),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.SkipIsland) end) end)

-- Card 6: Bird Nuke
local card6=mkShopCard(432,346)
cardIcon(card6,"\xF0\x9F\x92\xA5"); cardTitles(card6,"Bird Nuke","CHAOS MODE",Color3.fromRGB(255,100,100)); cardPrice(card6,"79 R$"); cardDesc(card6,"Unleash 30 birds on everyone!")
cardBuyBtn(card6,Color3.fromRGB(220,50,50),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.BirdNuke) end) end)

mkLabel(premPanel,{Text="Purchases support the game! Thank you! \xF0\x9F\x99\x8F",Font=Enum.Font.Gotham,TextSize=12,TextColor3=Color3.fromRGB(150,180,255),Size=UDim2.new(1,-20,0,18),Position=UDim2.new(0,10,1,-22),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})

task.spawn(function()
	while true do
		task.wait(1)
		local gp=_G.playerGamepasses
		if gp and gp.twoXHourExpiry and gp.twoXHourExpiry>os.time() then
			local rem=gp.twoXHourExpiry-os.time()
			twoXShopTimer.Text="\xe2\x9a\xa1 Active: "..math.floor(rem/60).."m "..rem%60 .."s"
			twoXShopTimer.Visible=true
		else
			twoXShopTimer.Visible=false
		end
	end
end)
print("CHUNK 2 DONE")

-- Hotbar
sg=Instance.new("ScreenGui"); sg.Name="HotbarGui"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui
local hotbarFrame=mkFrame(sg,{Position=UDim2.new(1,-10,1,-80),Size=UDim2.new(0,140,0,60),AnchorPoint=Vector2.new(1,1),BackgroundTransparency=1,Visible=false})
local hbLayout=Instance.new("UIListLayout"); hbLayout.FillDirection=Enum.FillDirection.Horizontal; hbLayout.Padding=UDim.new(0,5); hbLayout.Parent=hotbarFrame
local rechargeSlot=mkButton(hotbarFrame,{Size=UDim2.new(0,60,0,60),BackgroundColor3=Color3.fromRGB(50,50,50),BackgroundTransparency=0.3,Text="RCHRG",TextSize=11,Font=Enum.Font.GothamBold,TextColor3=Color3.new(1,1,1)}); mkCorner(rechargeSlot,10); mkStroke(rechargeSlot,Color3.fromRGB(100,100,100),2)
local rechargeBadge=mkLabel(rechargeSlot,{Text="0",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=Color3.new(1,1,1),Size=UDim2.new(0,20,0,20),Position=UDim2.new(1,-20,1,-20),BackgroundColor3=Color3.fromRGB(255,60,60)}); mkCorner(rechargeBadge,10)
local skipSlot=mkButton(hotbarFrame,{Size=UDim2.new(0,60,0,60),BackgroundColor3=Color3.fromRGB(50,50,50),BackgroundTransparency=0.3,Text="SKIP",TextSize=13,Font=Enum.Font.GothamBold,TextColor3=Color3.new(1,1,1)}); mkCorner(skipSlot,10); mkStroke(skipSlot,Color3.fromRGB(100,100,100),2)
local skipBadge=mkLabel(skipSlot,{Text="0",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=Color3.new(1,1,1),Size=UDim2.new(0,20,0,20),Position=UDim2.new(1,-20,1,-20),BackgroundColor3=Color3.fromRGB(255,60,60)}); mkCorner(skipBadge,10)

local function updateHotbar()
	local gp=_G.playerGamepasses or {}
	local rc=gp.midAirRecharge or 0
	local sk=gp.skipIsland or 0
	hotbarFrame.Visible=rc>0 or sk>0
	rechargeBadge.Text=tostring(rc)
	skipBadge.Text=tostring(sk)
end
_G.updateHotbar=updateHotbar

-- Forward declaration: the embedded "live gas meter" mirror inside the food shop. Its UI is built
-- after the shop layout below; this lets updateFoodShop drive it. updateFoodShop already runs on shop
-- open and on every Coins / CurrentPower / StomachMax change, so the mirror stays in sync with the HUD.
local updateGasMirror

local function updateFoodShop(islandNum)
	nearIslandNumber=islandNum
	if updateGasMirror then updateGasMirror() end  -- refresh the embedded gas meter live (same source as the HUD meter)
	foodTitle.Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F ISLAND "..islandNum.." FOOD STAND"
	local locked=not isUnlocked(islandNum)
	foodLockedFrame.Visible=locked; foodEmoji.Visible=not locked; foodName.Visible=not locked
	foodPriceRow.Visible=not locked; foodPower.Visible=not locked; foodBuyBtn.Visible=not locked; foodBuyMaxBtn.Visible=not locked  -- hide the whole price row (coin icon + text) when locked
	if locked then return end
	local f=_G.foods[islandNum]; if not f then return end
	-- Every food (incl. Beans) shows its emoji from foodEmojis.
	foodEmoji.Visible=true; foodEmoji.Text=foodEmojis[f.name] or "?"
	foodName.Text=f.name
	foodPrice.Text=f.price.." coins"  -- coin shown by the CoinIcon ImageLabel in the row, not text
	foodPower.Text="+"..f.power.." power"
	local coins, curPower, stomMax = 0, 0, 46
	pcall(function() if _G.leaderstats then
		local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end
		local cp=_G.leaderstats:FindFirstChild("CurrentPower"); if cp then curPower=cp.Value end
		local sm=_G.leaderstats:FindFirstChild("StomachMax"); if sm then stomMax=sm.Value end
	end end)
	-- How many of this food actually fit in the remaining stomach space, and can be afforded.
	local fittable    = math.floor((stomMax - curPower) / f.power)
	local affordable  = math.floor(coins / f.price)
	local fitAndAfford = math.min(fittable, affordable)
	-- Single BUY: blocked if the stomach can't fit even one, then if you can't afford it.
	if fittable < 1 then
		foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text="STOMACH FULL"; foodBuyBtn.TextSize=14
	elseif coins>=f.price then
		foodBuyBtn.BackgroundColor3=Color3.fromRGB(50,200,50); foodBuyBtn.Text="BUY FOOD"; foodBuyBtn.TextSize=17
	else
		foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text="NOT ENOUGH"; foodBuyBtn.TextSize=14
	end
	-- BUY MAX label shows the fit-and-afford quantity, never the wallet-only amount.
	if fitAndAfford >= 1 then
		foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(255,140,0); foodBuyMaxBtn.Text="MAX x"..fitAndAfford; foodBuyMaxBtn.TextSize=14
	elseif fittable < 1 then
		foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyMaxBtn.Text="FULL"; foodBuyMaxBtn.TextSize=15
	else
		foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyMaxBtn.Text="BUY MAX"; foodBuyMaxBtn.TextSize=15
	end
	local coins2=0
	pcall(function() if _G.leaderstats then local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins2=c.Value end end end)
	for _,fd in ipairs(_G.foods) do
		local cell=foodCells[fd.name]; if cell then
			local st=cell:FindFirstChildWhichIsA("UIStroke")
			local pl=cell:FindFirstChild("PriceLabel")
			local nm=cell:FindFirstChild("NameLabel")
			local ef=cell:FindFirstChild("EmojiFrame")
			local icon=ef and ef:FindFirstChild("FoodEmoji")
			if not isUnlocked(fd.island) then
				-- LOCKED: keep it a mystery until the player reaches this food's island. 🔒 icon, "???"
				-- name, no price. Cell stays the same size/position, just greyed and not buyable.
				cell.BackgroundColor3=Color3.fromRGB(180,180,180); if st then st.Color=Color3.fromRGB(140,140,140) end
				if icon then icon.Text="\xF0\x9F\x94\x92" end
				if nm then nm.Text="???" end
				if pl then pl.Text="" end
				local pic=cell:FindFirstChild("PriceIcon"); if pic then pic.Visible=false end  -- no price -> hide coin
			else
				-- UNLOCKED: reveal the real icon + name + price (restores from the locked state, so it
				-- switches live the moment the player reaches the island).
				if icon then icon.Text=foodEmojis[fd.name] or "\xF0\x9F\x8D\xBD\xEF\xB8\x8F" end
				if nm then nm.Text=fd.name end
				if coins2>=fd.price then
					cell.BackgroundColor3=Color3.fromRGB(50,200,50); if st then st.Color=Color3.fromRGB(30,150,30) end
				else
					cell.BackgroundColor3=Color3.fromRGB(20,90,200); if st then st.Color=Color3.fromRGB(255,255,255) end
				end
				if pl then pl.Text=tostring(fd.price) end  -- coin shown by the PriceIcon ImageLabel, not text
				local pic=cell:FindFirstChild("PriceIcon"); if pic then pic.Visible=true end  -- priced -> show coin
			end
		end
	end
end

for _,v in ipairs(premPanel:GetDescendants()) do
	if v:IsA("TextLabel") or v:IsA("TextButton") then v.TextScaled=true end
end
for _,v in ipairs(foodPanel:GetDescendants()) do
	if v:IsA("TextLabel") or v:IsA("TextButton") then v.TextScaled=true end
end

-- ===== PREMIUM SHOP STYLE =====
;(function()
	-- FredokaOne + white text + black stroke on everything in premPanel
	for _, v in ipairs(premPanel:GetDescendants()) do
		if v:IsA("TextLabel") or v:IsA("TextButton") then
			v.Font = Enum.Font.FredokaOne
			v.TextScaled = true
			v.TextColor3 = Color3.fromRGB(255,255,255)
			local s = v:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
			s.Color = Color3.fromRGB(0,0,0); s.Thickness = 2; s.Parent = v
		end
	end

	-- Main panel
	premPanel.BackgroundColor3 = Color3.fromRGB(30,120,220)
	local panelS = premPanel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	panelS.Color = Color3.fromRGB(20,60,160); panelS.Thickness = 3; panelS.Parent = premPanel

	-- Close button + shop title gold
	premClose.BackgroundColor3 = Color3.fromRGB(255,60,60)
	premTitleLbl.TextColor3 = Color3.fromRGB(255,220,0)

	-- Cards: dark blue bg, white stroke
	for _, card in ipairs({card1, card2, card3, card4, card5, card6}) do
		card.BackgroundColor3 = Color3.fromRGB(20,90,200)
		local cs = card:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		cs.Color = Color3.fromRGB(255,255,255); cs.Thickness = 2; cs.Parent = card
	end

	-- Buy buttons + price labels + section headers by content
	for _, v in ipairs(premPanel:GetDescendants()) do
		if v:IsA("TextButton") then
			if v.Text:find("BUY GAMEPASS") then
				v.BackgroundColor3 = Color3.fromRGB(255,160,20)
				local bs = v:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
				bs.Color = Color3.fromRGB(180,80,0); bs.Thickness = 2; bs.Parent = v
			elseif v.Text:find("BUY NOW") then
				v.BackgroundColor3 = Color3.fromRGB(50,220,50)
				local bs = v:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
				bs.Color = Color3.fromRGB(30,130,30); bs.Thickness = 2; bs.Parent = v
			end
		end
		if v:IsA("TextLabel") then
			if v.Text:find("R%$") then
				v.TextColor3 = Color3.fromRGB(100,255,100)
			end
			if v.Text:find("GAMEPASSES") or v.Text:find("ONE%-TIME") then
				v.TextColor3 = Color3.fromRGB(255,220,0)
			end
		end
	end

	-- gpBadge: dark text on gold, no outline
	gpBadge.TextColor3 = Color3.fromRGB(80,40,0)
	gpBadge.BackgroundColor3 = Color3.fromRGB(255,200,0)
	local gbS = gpBadge:FindFirstChildOfClass("UIStroke")
	if gbS then gbS:Destroy() end
end)()

-- ===== PREMIUM SHOP LAYOUT =====
;(function()
	-- Panel taller to fit bigger cards
	premPanel.Size = UDim2.new(0,680,0,590)
	premPanel.Position = UDim2.new(0.5,0,0.5,0)
	premPanel.AnchorPoint = Vector2.new(0.5,0.5)

	-- Horizontal row container with UIListLayout
	local function mkRow(yPos, rowH)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1,-24,0,rowH)
		row.Position = UDim2.new(0,12,0,yPos)
		row.BackgroundTransparency = 1
		row.Parent = premPanel
		local ll = Instance.new("UIListLayout")
		ll.FillDirection = Enum.FillDirection.Horizontal
		ll.Padding = UDim.new(0,10)
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Left
		ll.VerticalAlignment = Enum.VerticalAlignment.Top
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Parent = row
		return row
	end

	local gpRow = mkRow(104, 190)
	local pdRow = mkRow(346, 220)

	for i, c in ipairs({card1, card2, card3}) do
		c.Parent = gpRow; c.LayoutOrder = i; c.Size = UDim2.new(0.31,0,0,190)
	end
	for i, c in ipairs({card4, card5, card6}) do
		c.Parent = pdRow; c.LayoutOrder = i; c.Size = UDim2.new(0.31,0,0,220)
	end

	-- Layout card content using UIListLayout inside a _Content sub-frame.
	-- Badge (card1 only) stays as an absolute overlay on the card itself.
	local function layoutCard(card, isProduct)
		-- Collect direct children BEFORE creating _Content frame
		local iconLbl, buyBtn, timer = nil, nil, nil
		local textLbls = {}
		for _, child in ipairs(card:GetChildren()) do
			if child == gpBadge then
				-- handled below as absolute overlay
			elseif child == twoXShopTimer then
				timer = child
			elseif child:IsA("TextButton") then
				buyBtn = child
			elseif child:IsA("TextLabel") then
				if child.TextSize >= 40 then
					iconLbl = child
				else
					table.insert(textLbls, child)
				end
			end
		end
		-- Preserve title→subtitle→price→desc order
		table.sort(textLbls, function(a, b)
			return a.Position.Y.Offset < b.Position.Y.Offset
		end)

		-- Content frame fills the card; UIListLayout stacks children vertically
		local cf = Instance.new("Frame")
		cf.Name = "_Content"
		cf.Size = UDim2.new(1,0,1,0)
		cf.BackgroundTransparency = 1
		cf.Parent = card

		local ll = Instance.new("UIListLayout")
		ll.FillDirection = Enum.FillDirection.Vertical
		ll.Padding = UDim.new(0,4)
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
		ll.VerticalAlignment = Enum.VerticalAlignment.Top
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Parent = cf

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0,4)
		pad.PaddingBottom = UDim.new(0,4)
		pad.PaddingLeft = UDim.new(0,4)
		pad.PaddingRight = UDim.new(0,4)
		pad.Parent = cf

		-- Icon
		if iconLbl then
			iconLbl.Size = UDim2.new(0, isProduct and 50 or 55, 0, isProduct and 50 or 55)
			iconLbl.LayoutOrder = 1
			iconLbl.TextScaled = true
			iconLbl.Parent = cf
		end

		-- Name / Type / Price / Desc labels
		local gpSz = {UDim2.new(1,-8,0,26), UDim2.new(1,-8,0,22), UDim2.new(1,-8,0,22)}
		local pdSz = {UDim2.new(1,-8,0,24), UDim2.new(1,-8,0,20), UDim2.new(1,-8,0,20), UDim2.new(1,-8,0,28)}
		local szList = isProduct and pdSz or gpSz
		for i, lbl in ipairs(textLbls) do
			lbl.Size = szList[i] or UDim2.new(1,-8,0,20)
			lbl.LayoutOrder = i + 1
			lbl.TextScaled = true
			lbl.Parent = cf
		end

		-- twoXShopTimer (card3): shows between price and buy when active
		if timer then
			timer.Size = UDim2.new(1,-8,0,18)
			timer.LayoutOrder = 5
			timer.TextScaled = true
			timer.Parent = cf
		end

		-- Buy button: last in stack
		if buyBtn then
			buyBtn.Size = UDim2.new(1,-12,0,40)
			buyBtn.LayoutOrder = 10
			buyBtn.TextScaled = true
			buyBtn.Parent = cf
		end

		-- Badge: absolute overlay on card (NOT inside _Content)
		if card == card1 then
			gpBadge.Size = UDim2.new(1,-8,0,18)
			gpBadge.Position = UDim2.new(0,4,0,2)
			gpBadge.ZIndex = 10
		end
	end

	layoutCard(card1, false)
	layoutCard(card2, false)
	layoutCard(card3, false)
	layoutCard(card4, true)
	layoutCard(card5, true)
	layoutCard(card6, true)
end)()

-- Explicitly style the shop close button
premClose.Text = "X"
premClose.Font = Enum.Font.FredokaOne
premClose.TextScaled = true
premClose.TextColor3 = Color3.fromRGB(255,255,255)
local pcs = premClose:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
pcs.Color = Color3.fromRGB(0,0,0); pcs.Thickness = 2; pcs.Parent = premClose

-- ===== FOOD SHOP STYLE & LAYOUT =====
;(function()
	-- FIX 1: Sort food grid cells by island order
	foodGrid.SortOrder = Enum.SortOrder.LayoutOrder
	if _G.foods then
		for _, f in ipairs(_G.foods) do
			local cell = foodCells[f.name]
			if cell then cell.LayoutOrder = f.island or 99 end
		end
	end

	-- FIX 2: Main panel
	foodPanel.Size = UDim2.new(0,700,0,520)
	foodPanel.Position = UDim2.new(0.5,0,0.5,0)
	foodPanel.AnchorPoint = Vector2.new(0.5,0.5)
	foodPanel.BackgroundColor3 = Color3.fromRGB(30,120,220)
	local fpC = foodPanel:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	fpC.CornerRadius = UDim.new(0,20); fpC.Parent = foodPanel
	local fpS = foodPanel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	fpS.Color = Color3.fromRGB(20,60,160); fpS.Thickness = 3; fpS.Parent = foodPanel

	-- FIX 3: Header + title
	foodHeader.BackgroundColor3 = Color3.fromRGB(15,60,140)
	local fhC = foodHeader:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	fhC.CornerRadius = UDim.new(0,20); fhC.Parent = foodHeader
	foodTitle.Size = UDim2.new(1,-55,0,55)
	foodTitle.Position = UDim2.new(0,0,0,0)
	foodTitle.Font = Enum.Font.FredokaOne
	foodTitle.TextColor3 = Color3.fromRGB(255,220,0)
	foodTitle.TextScaled = true
	foodTitle.TextXAlignment = Enum.TextXAlignment.Center
	local ftS = foodTitle:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	ftS.Color = Color3.fromRGB(0,0,0); ftS.Thickness = 2; ftS.Parent = foodTitle

	-- FIX 4: Food grid settings
	foodGrid.CellSize = UDim2.new(0,95,0,75)
	foodGrid.CellPadding = UDim2.new(0,6,0,6)

	-- Right panel adjusted for new left panel width
	foodRight.Size = UDim2.new(1,-190,1,-70)
	foodRight.Position = UDim2.new(0,180,0,60)
	foodRight.BackgroundColor3 = Color3.fromRGB(15,60,140)
	local frC = foodRight:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	frC.CornerRadius = UDim.new(0,12); frC.Parent = foodRight
	for _, v in ipairs(foodRight:GetChildren()) do
		if v:IsA("TextLabel") then
			v.Font = Enum.Font.FredokaOne
			v.TextColor3 = Color3.fromRGB(255,220,0)
			v.TextScaled = true
		end
	end

	-- Restyle each food cell
	for _, cell in pairs(foodCells) do
		cell.BackgroundColor3 = Color3.fromRGB(20,90,200)
		local cs = cell:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		cs.CornerRadius = UDim.new(0,10); cs.Parent = cell
		local css = cell:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		css.Color = Color3.fromRGB(255,255,255); css.Thickness = 1.5; css.Parent = cell
		local ef = cell:FindFirstChild("EmojiFrame")
		if ef then
			ef.Size = UDim2.new(0,36,0,36)
			ef.Position = UDim2.new(0,6,0.5,0)
			ef.AnchorPoint = Vector2.new(0,0.5)
			local el = ef:FindFirstChild("FoodEmoji")
			if el then
				el.Size = UDim2.new(1,0,1,0)
				el.Position = UDim2.new(0,0,0,0)
				el.AnchorPoint = Vector2.new(0,0)
				el.TextScaled = true
			end
		end
		for _, child in ipairs(cell:GetChildren()) do
			if child:IsA("TextLabel") and child.Name == "PriceLabel" then
				-- Narrow the price text to leave room for the coin icon, and align the icon to this row.
				child.Size = UDim2.new(1,-66,0,22)
				child.Position = UDim2.new(0,64,0,36)
				child.Font = Enum.Font.FredokaOne
				child.TextScaled = true
				child.TextColor3 = Color3.fromRGB(255,220,0)
				child.TextXAlignment = Enum.TextXAlignment.Left
				local pIcon = cell:FindFirstChild("PriceIcon")
				if pIcon then pIcon.Size = UDim2.new(0,18,0,18); pIcon.Position = UDim2.new(0,44,0,38) end
			elseif child:IsA("TextLabel") then
				child.Size = UDim2.new(1,-48,0,28)
				child.Position = UDim2.new(0,46,0,8)
				child.Font = Enum.Font.FredokaOne
				child.TextScaled = true
				child.TextColor3 = Color3.fromRGB(255,255,255)
				child.TextXAlignment = Enum.TextXAlignment.Left
				local ns = child:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
				ns.Color = Color3.fromRGB(0,0,0); ns.Thickness = 2; ns.Parent = child
			end
		end
	end

	-- FIX 5: Left preview panel
	foodLeftPanel.Size = UDim2.new(0,160,1,-80)
	foodLeftPanel.Position = UDim2.new(0,10,0,60)
	foodLeftPanel.BackgroundColor3 = Color3.fromRGB(20,90,200)
	local flpC = foodLeftPanel:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	flpC.CornerRadius = UDim.new(0,14); flpC.Parent = foodLeftPanel
	local flpS = foodLeftPanel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	flpS.Color = Color3.fromRGB(255,255,255); flpS.Thickness = 2; flpS.Parent = foodLeftPanel
	foodEmoji.Size = UDim2.new(0,80,0,80)
	foodEmoji.Position = UDim2.new(0.5,0,0,10)
	foodEmoji.AnchorPoint = Vector2.new(0.5,0)
	foodName.Size = UDim2.new(1,-8,0,32)
	foodName.Position = UDim2.new(0,4,0,98)
	foodName.Font = Enum.Font.FredokaOne
	foodName.TextScaled = true
	foodName.TextColor3 = Color3.fromRGB(255,255,255)
	local fnS = foodName:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	fnS.Color = Color3.fromRGB(0,0,0); fnS.Thickness = 2; fnS.Parent = foodName
	foodPriceRow.Size = UDim2.new(1,-8,0,26); foodPrice.Size = UDim2.new(0,110,1,0)  -- size the ROW (coin+text); text fixed width inside the centered list
	foodPriceRow.Position = UDim2.new(0,4,0,134)  -- position the ROW; UIListLayout handles the text inside
	foodPrice.Font = Enum.Font.FredokaOne
	foodPrice.TextScaled = true
	foodPrice.TextColor3 = Color3.fromRGB(255,220,0)
	foodPower.Size = UDim2.new(1,-8,0,26)
	foodPower.Position = UDim2.new(0,4,0,164)
	foodPower.Font = Enum.Font.FredokaOne
	foodPower.TextScaled = true
	foodPower.TextColor3 = Color3.fromRGB(100,255,100)

	-- FIX 6: Buy buttons — move to main panel, position at bottom-left
	foodBuyBtn.Parent = foodPanel
	foodBuyBtn.Size = UDim2.new(0,130,0,48)
	foodBuyBtn.Position = UDim2.new(0,10,1,-58)
	foodBuyBtn.BackgroundColor3 = Color3.fromRGB(50,220,50)
	foodBuyBtn.Font = Enum.Font.FredokaOne
	foodBuyBtn.TextScaled = true
	foodBuyBtn.TextColor3 = Color3.fromRGB(255,255,255)
	local fbC = foodBuyBtn:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	fbC.CornerRadius = UDim.new(0,12); fbC.Parent = foodBuyBtn
	local fbS = foodBuyBtn:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	fbS.Color = Color3.fromRGB(30,130,30); fbS.Thickness = 2; fbS.Parent = foodBuyBtn
	foodBuyMaxBtn.Parent = foodPanel
	foodBuyMaxBtn.Size = UDim2.new(0,130,0,48)
	foodBuyMaxBtn.Position = UDim2.new(0,148,1,-58)
	foodBuyMaxBtn.BackgroundColor3 = Color3.fromRGB(255,160,20)
	foodBuyMaxBtn.Font = Enum.Font.FredokaOne
	foodBuyMaxBtn.TextScaled = true
	foodBuyMaxBtn.TextColor3 = Color3.fromRGB(255,255,255)
	local fmC = foodBuyMaxBtn:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	fmC.CornerRadius = UDim.new(0,12); fmC.Parent = foodBuyMaxBtn
	local fmS = foodBuyMaxBtn:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	fmS.Color = Color3.fromRGB(180,80,0); fmS.Thickness = 2; fmS.Parent = foodBuyMaxBtn

	-- Close button
	foodCloseBtn.Text = "X"
	foodCloseBtn.Font = Enum.Font.FredokaOne
	foodCloseBtn.TextScaled = true
	local fclS = foodCloseBtn:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	fclS.Color = Color3.fromRGB(0,0,0); fclS.Thickness = 2; fclS.Parent = foodCloseBtn
end)()

-- ===== EMBEDDED LIVE GAS METER (mirror of the HUD gas meter) =====
-- A visible copy of the player's gas meter placed in the food shop's bottom strip, to the RIGHT of
-- the BUY / BUY MAX buttons (which end at x=278 on the 700-wide panel). It mirrors the HUD meter's
-- look (gold "GAS METER" title, dark track, green gradient fill, white "x/y" readout) and reads the
-- SAME source the HUD reads — the player's CurrentPower / StomachMax — so it fills in real time as
-- food is bought. This is purely additive: it does NOT touch the HUD meter, purchase logic, or any math.
local gasMirrorFill, gasMirrorGradient, gasMirrorText
do
	local panel = mkFrame(foodPanel,{Name="GasMirrorPanel",Position=UDim2.new(0,286,1,-58),Size=UDim2.new(0,404,0,48),BackgroundColor3=Color3.fromRGB(45,120,220)})
	mkCorner(panel,12); mkStroke(panel,Color3.fromRGB(20,65,165),3)
	-- Title (matches the HUD's gold "GAS METER" label)
	local title=mkLabel(panel,{Text="GAS METER",Font=Enum.Font.FredokaOne,TextSize=16,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(0,92,1,0),Position=UDim2.new(0,8,0,0),TextXAlignment=Enum.TextXAlignment.Left})
	mkStroke(title,Color3.fromRGB(0,0,0),2)
	-- Track + fill (same colors/gradient as the HUD gasBg/gasFill)
	local bg=mkFrame(panel,{Name="Track",Size=UDim2.new(1,-112,0,26),Position=UDim2.new(0,104,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.fromRGB(18,28,66)})
	mkCorner(bg,13)
	gasMirrorFill=mkFrame(bg,{Name="Fill",Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.fromRGB(60,210,90),ZIndex=2})
	mkCorner(gasMirrorFill,13)
	gasMirrorGradient=Instance.new("UIGradient")
	gasMirrorGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(130,240,120)),ColorSequenceKeypoint.new(1,Color3.fromRGB(45,190,70))})
	gasMirrorGradient.Rotation=90; gasMirrorGradient.Parent=gasMirrorFill
	gasMirrorText=mkLabel(bg,{Name="Readout",Size=UDim2.new(1,0,1,0),Text="0/0",Font=Enum.Font.FredokaOne,TextSize=16,TextColor3=Color3.fromRGB(255,255,255),ZIndex=3,TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(gasMirrorText,Color3.fromRGB(0,0,0),2)
end

-- Mirrors the HUD's updateMeter() exactly: fill = clamp(CurrentPower/StomachMax,0,1); readout =
-- floor(min(CurrentPower,StomachMax)).."/"..StomachMax. Reads leaderstats — the same values the
-- server replicates on every food purchase — so this copy and the HUD meter never diverge.
updateGasMirror=function()
	if not gasMirrorFill then return end
	local cp, sm = 0, 100
	pcall(function() if _G.leaderstats then
		local c=_G.leaderstats:FindFirstChild("CurrentPower"); if c then cp=c.Value end
		local m=_G.leaderstats:FindFirstChild("StomachMax"); if m then sm=m.Value end
	end end)
	local fill = sm>0 and math.clamp(cp/sm,0,1) or 0
	gasMirrorFill.Size=UDim2.new(fill,0,1,0)
	gasMirrorGradient.Offset=Vector2.new(-(1-fill),0)
	gasMirrorText.Text=math.floor(math.min(cp, sm)).."/"..sm
end
updateGasMirror() -- initial paint so it's correct the first time the shop opens

premClose.MouseButton1Click:Connect(function() if _G.playUIClick then _G.playUIClick() end; PremiumShopGui.Enabled=false end)
foodCloseBtn.MouseButton1Click:Connect(function()
	FoodShopGui.Enabled = false
	shopOpen = false
	playerClosedShop = true
	task.delay(3, function() playerClosedShop = false end)
end)

local function playEatSound()
	local sound=Instance.new("Sound"); sound.SoundId="rbxassetid://103794849233173"
	sound.Volume=0.8; sound.Parent=workspace; sound:Play()
	game:GetService("Debris"):AddItem(sound,3)
end

foodBuyBtn.MouseButton1Click:Connect(function()
	playEatSound()
	local f=_G.foods[nearIslandNumber]; if not f then return end
	local coins=0
	pcall(function() if _G.leaderstats then local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end end end)
	if coins<f.price then
		foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text="NOT ENOUGH COINS!"; foodBuyBtn.TextSize=14
		task.delay(1,function() foodBuyBtn.BackgroundColor3=Color3.fromRGB(50,200,50); foodBuyBtn.Text="BUY FOOD"; foodBuyBtn.TextSize=17 end)
		return
	end
	pcall(function() _G.BuyFoodEvent:FireServer(f.name) end)
	print("FIRED BUYFOOD:", f.name)
	local fl=Instance.new("TextLabel"); fl.Text="+"..f.power.." power!"; fl.Font=Enum.Font.GothamBold; fl.TextSize=20; fl.TextColor3=Color3.fromRGB(0,200,50); fl.BackgroundTransparency=1; fl.Size=UDim2.new(0,200,0,40); fl.Position=UDim2.new(0.3,0,0.6,0); fl.ZIndex=10; fl.Parent=FoodShopGui
	TweenService:Create(fl,TweenInfo.new(1.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(0.3,0,0.4,0),TextTransparency=1}):Play()
	task.delay(1.5,function() fl:Destroy() end)
end)

foodBuyMaxBtn.MouseButton1Click:Connect(function()
	playEatSound()
	if not _G.foods[nearIslandNumber] then return end
	local coins, curPower, stomMax = 0, 0, 46
	pcall(function() if _G.leaderstats then
		local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end
		local cp=_G.leaderstats:FindFirstChild("CurrentPower"); if cp then curPower=cp.Value end
		local sm=_G.leaderstats:FindFirstChild("StomachMax"); if sm then stomMax=sm.Value end
	end end)
	-- Fill as full as possible using current + lower UNLOCKED foods, biggest power first, capped
	-- by BOTH remaining stomach space AND money on hand. _G.foods is ordered by power ascending
	-- (island N == index N), so iterating nearIslandNumber -> 1 is largest -> smallest. We never
	-- spend more coins than we have and never exceed stomachMax (qty floored by remaining space).
	local remaining = stomMax - curPower
	local coinsLeft = coins
	local totalPower = 0
	for i = nearIslandNumber, 1, -1 do
		local f = _G.foods[i]
		if f and isUnlocked(f.island) then
			local qty = math.min(math.floor(remaining / f.power), math.floor(coinsLeft / f.price))
			if qty > 0 then
				for _=1,qty do pcall(function() _G.BuyFoodEvent:FireServer(f.name) end) end
				remaining = remaining - qty * f.power
				coinsLeft = coinsLeft - qty * f.price
				totalPower = totalPower + qty * f.power
			end
		end
		if remaining < _G.foods[1].power or coinsLeft < _G.foods[1].price then break end
	end
	if totalPower <= 0 then
		local reason = (remaining < _G.foods[1].power) and "STOMACH FULL!" or "NOT ENOUGH COINS!"
		foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyMaxBtn.Text=reason; foodBuyMaxBtn.TextSize=13
		task.delay(1,function() foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(255,140,0); foodBuyMaxBtn.Text="BUY MAX"; foodBuyMaxBtn.TextSize=15 end)
		return
	end
	print("BUY MAX: +"..totalPower.." power (coins left "..coinsLeft..", space left "..remaining..")")
	local fl=Instance.new("TextLabel"); fl.Text="MAX! +"..totalPower.." power!"; fl.Font=Enum.Font.GothamBold; fl.TextSize=18; fl.TextColor3=Color3.fromRGB(255,140,0); fl.BackgroundTransparency=1; fl.Size=UDim2.new(0,260,0,50); fl.Position=UDim2.new(0.3,0,0.6,0); fl.ZIndex=10; fl.Parent=FoodShopGui
	TweenService:Create(fl,TweenInfo.new(1.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(0.3,0,0.4,0),TextTransparency=1}):Play()
	task.delay(1.5,function() fl:Destroy() end)
end)

-- Every stand sells ALL unlocked foods: make each food cell in the grid a buy button (one
-- purchase per click). The native food stays the enlarged left preview with its own BUY/BUY MAX.
-- Server validates coins + stomach space, so foods too big for the current gut just won't buy.
-- Purely additive: no price/power changed (flat 0.5 coins/power), so no exploit.
for _, f in ipairs(_G.foods) do
	local cell = foodCells[f.name]
	if cell then
		local buyOverlay = mkButton(cell, {Name="BuyOverlay", Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="", ZIndex=5})
		buyOverlay.MouseButton1Click:Connect(function()
			if not isUnlocked(f.island) then return end -- only unlocked foods are buyable
			local coins=0
			pcall(function() if _G.leaderstats then local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end end end)
			if coins < f.price then return end -- server also validates; this avoids a no-op fire
			playEatSound()
			pcall(function() _G.BuyFoodEvent:FireServer(f.name) end)
			local fl2=Instance.new("TextLabel"); fl2.Text="+"..f.power.." "..f.name.."!"; fl2.Font=Enum.Font.GothamBold; fl2.TextSize=20; fl2.TextColor3=Color3.fromRGB(0,200,50); fl2.BackgroundTransparency=1; fl2.Size=UDim2.new(0,220,0,40); fl2.Position=UDim2.new(0.3,0,0.6,0); fl2.ZIndex=10; fl2.Parent=FoodShopGui
			TweenService:Create(fl2,TweenInfo.new(1.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(0.3,0,0.4,0),TextTransparency=1}):Play()
			task.delay(1.5,function() fl2:Destroy() end)
		end)
	end
end

rechargeSlot.MouseButton1Click:Connect(function()
	local gp=_G.playerGamepasses
	if gp and gp.midAirRecharge > 0 then
		gp.midAirRecharge = gp.midAirRecharge - 1
		_G.cosmeticGas=100; if _G.updateMeter then _G.updateMeter() end; if _G.updateFartBtn then _G.updateFartBtn() end; updateHotbar()
	end
end)
skipSlot.MouseButton1Click:Connect(function()
	local gp=_G.playerGamepasses
	if gp and gp.skipIsland > 0 then
		gp.skipIsland = gp.skipIsland - 1
		pcall(function() if _G.SkipIslandEvent then _G.SkipIslandEvent:FireServer() end end)
		updateHotbar()
	end
end)

pcall(function()
	if _G.leaderstats then
		local c=_G.leaderstats:FindFirstChild("Coins")
		if c then c.Changed:Connect(function() if _G.updateCoins then _G.updateCoins() end; if shopOpen then updateFoodShop(nearIslandNumber) end end) end
		-- Stomach fill changes (buying food, landing) must refresh the BUY MAX fit count live.
		local cpv=_G.leaderstats:FindFirstChild("CurrentPower")
		if cpv then cpv.Changed:Connect(function() if shopOpen then updateFoodShop(nearIslandNumber) end end) end
		local smv=_G.leaderstats:FindFirstChild("StomachMax")
		if smv then smv.Changed:Connect(function() if shopOpen then updateFoodShop(nearIslandNumber) end end) end
		local isl=_G.leaderstats:FindFirstChild("Island")
		if isl then isl.Changed:Connect(function(newVal)
			for n=1,newVal do unlockedIslands[n]=true end
			if shopOpen then updateFoodShop(nearIslandNumber) end
		end) end
	end
end)

-- Keep local unlockedIslands in sync with _G.unlockedIslands every second
task.spawn(function()
	while true do
		task.wait(1)
		if _G.unlockedIslands then
			for k, v in pairs(_G.unlockedIslands) do
				if v then unlockedIslands[k] = true end
			end
		end
		pcall(function()
			if _G.leaderstats then
				local isl = _G.leaderstats:FindFirstChild("Island")
				if isl then for n = 1, isl.Value do unlockedIslands[n] = true end end
			end
		end)
		-- LIVE: refresh the grid so a newly-reached island reveals its food cell (🔒 -> real icon/name/price)
		-- without needing another stat change.
		if shopOpen then pcall(function() updateFoodShop(nearIslandNumber) end) end
	end
end)

-- ===== STAND DETECTION =====
local RS = game:GetService("ReplicatedStorage")

-- Receive stand positions from server
local sre = RS:WaitForChild("StandsReadyEvent", 30)
if sre then
	sre.OnClientEvent:Connect(function(data)
		stands = {}
		for islandNum, pos in pairs(data) do
			table.insert(stands, {
				position = Vector3.new(pos.x, pos.y, pos.z),
				islandNum = tonumber(islandNum)
			})
		end
		table.sort(stands, function(a, b) return a.islandNum < b.islandNum end)
		print("STANDS RECEIVED:", #stands)
	end)
end

-- Proximity check every 0.1 seconds
task.spawn(function()
	while true do
		task.wait(0.1)
		pcall(function()
			local character = player.Character
			if not character then return end
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			if _G.unlockedIslands then
				for i, v in pairs(_G.unlockedIslands) do unlockedIslands[i] = v end
			end
			-- Stand only triggers while GROUNDED — never mid-flight / in the air (flying lifts the humanoid off
				-- the floor, so FloorMaterial becomes Air and _G.isFlying is set).
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local grounded = (not _G.isFlying) and humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
				local nearStand = false
			local foundIsland = 1
			for _, stand in ipairs(stands) do
				local diff = hrp.Position - stand.position
				local horizontalDist = math.sqrt(diff.X * diff.X + diff.Z * diff.Z)
				local verticalDist = math.abs(diff.Y)
				if grounded and horizontalDist < STAND_TRIGGER_RADIUS and verticalDist < 120 then
					nearStand = true
					foundIsland = stand.islandNum
					break
				end
			end
			if nearStand then
				lastAwayTime = 0
				if not shopOpen and not playerClosedShop then
					nearIslandNumber = foundIsland
					updateFoodShop(foundIsland)
					FoodShopGui.Enabled = true
					shopOpen = true
					print("SHOP OPEN ISLAND", foundIsland)
				end
			else
				if lastAwayTime == 0 then lastAwayTime = tick() end
				if tick() - lastAwayTime > 2 then playerClosedShop = false end
				if shopOpen then
					FoodShopGui.Enabled = false
					shopOpen = false
					print("SHOP CLOSED")
				end
			end
		end)
	end
end)

print("PERMANENTLY FIXED")
print("FIXES DONE")
print("REMOVED 2 OLD BUTTONS (orange Shop + purple Invite from ShopClient SidebarGui)")
print("OLD BUTTONS REMOVED")

-- ===== GAMEPASS "OWNED" STATE =====
-- For the two REAL permanent gamepasses only (2x Power Forever, Glitter Trail), show a non-clickable
-- "✓ OWNED" button instead of "BUY GAMEPASS" once the player owns it. Ownership comes from
-- _G.playerGamepasses (twoXForever / glitterTrail), which the server sets on join and on a live
-- purchase (PromptGamePassPurchaseFinished -> GamepassEvent). The developer products (Bird Nuke,
-- Skip Island, Mid-Air Recharge, 2x 1-Hour) are repeatable and intentionally NOT affected here.
do
	local function setOwned(btn, owned, buyColor)
		if not btn then return end
		if owned then
			btn.Text = "\xe2\x9c\x93 OWNED"            -- ✓ OWNED
			btn.BackgroundColor3 = Color3.fromRGB(70,70,70)
			btn.AutoButtonColor = false
			btn.Active = false                          -- not clickable (purchase is also guarded in onClick)
		else
			btn.Text = "BUY GAMEPASS"
			btn.BackgroundColor3 = buyColor
			btn.AutoButtonColor = true
			btn.Active = true
		end
	end
	local function refreshOwned()
		local gp = _G.playerGamepasses
		-- Both "BUY GAMEPASS" buttons are orange after the shop restyle, so restore to that when not owned.
		setOwned(btn1, gp and gp.twoXForever == true, Color3.fromRGB(255,160,20))
		setOwned(btn2, gp and gp.glitterTrail == true, Color3.fromRGB(255,160,20))
	end
	refreshOwned() -- initial (covers ownership already received on join)
	-- Live: CoreClient's GamepassEvent handler updates _G.playerGamepasses first; defer so we read the
	-- updated value, then flip the card to OWNED immediately (e.g. right after a purchase grant).
	local GamepassEvent = game:GetService("ReplicatedStorage"):FindFirstChild("GamepassEvent")
		or game:GetService("ReplicatedStorage"):WaitForChild("GamepassEvent", 10)
	if GamepassEvent then
		GamepassEvent.OnClientEvent:Connect(function() task.defer(refreshOwned) end)
	end
	-- Safety net: also re-check every second so the card stays correct regardless of event timing.
	task.spawn(function() while true do task.wait(1); refreshOwned() end end)
end
