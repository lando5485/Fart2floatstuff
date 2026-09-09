print("SHOPCLIENT STARTED")
repeat task.wait() until _G.CoreClientReady

local Players = game.Players
local player = Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService")
local PlayerGui = player.PlayerGui
local MPS = MarketplaceService
-- The three NEWER passes (Lucky / VIP / Coin Magnet) read their ids, names and prices from the shared module
-- instead of a fourth hand-copied table. The two legacy ids below are left as-is deliberately -- rewriting the
-- working 2x/Glitter buttons was not worth the risk in the same change that adds three new ones.
local Gamepasses = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Gamepasses"))
local GAMEPASS_IDS = {TwoXForever=1862015450, GlitterTrail=1859714979}
local PRODUCT_IDS = {TwoXOneHour=3600302990, MidAirRecharge=3600303163, SkipIsland=3600303265, BirdNuke=3600303082}
-- Shared coin icon IMAGE: the SAME verified asset used by the coin counter and daily-rewards
-- icons (emoji glyphs like 💰 don't render in Roblox text). Literal here so it's correct
-- regardless of script load order. Shop prices show this image instead of the missing emoji.
local COIN_IMAGE = "rbxassetid://106760789458573"

local shopOpen = false
local playerClosedShop = false
local nearIslandNumber = 1
local unlockedIslands = {[1]=true}
local stands = {}
local lastAwayTime = 0
local STAND_TRIGGER_RADIUS = 12 -- studs: how close (horizontally) the player must walk to a stand before its shop opens (was 15 original -> 9 reduced -> 12 midpoint)

-- FOOD IS GATED BY HEIGHT REACHED: a food unlocks when you have reached ITS island. Pizza (island 14) is
-- unbuyable until you have actually stood on island 14; the same holds for every island above the one you
-- are on. Locked foods still SHOW in the grid -- greyed, 🔒, "???" instead of a price -- so the ladder ahead
-- is visible without being purchasable. All of that rendering already keys off this one function.
--
-- THIS IS NOT THE OLD STAND LOCK. Two different gates:
--   * the STAND lock (which stands would even open, and the pet-quest wall on 5 islands) is still GONE --
--     foodStandUnlocked() is a permanent `true`, every stand opens for everybody and sells the full menu;
--   * this one gates the individual FOOD by island reached.
-- So you can walk into the island-1 stand and buy anything you have climbed to, and nothing above it.
--
-- CANNOT SOFT-LOCK. Power ACCUMULATES across purchases (BuyFoodEvent adds to CurrentPower up to StomachMax),
-- so the food you already have unlocked can always fill the tank -- it just takes more buys. There is no
-- island that needs a food you cannot yet reach.
--
-- The SERVER enforces the same rule in PlayerStats.BuyFoodEvent ("food_locked"). Both halves must stay in
-- step: a cell that looks buyable while the server refuses it is worse than either gate alone.
local function isUnlocked(island)
	local n = tonumber(island)
	if not n then return true end          -- unknown island -> never hide it; the server is still authoritative
	return unlockedIslands[n] == true
end

-- ===== THERE IS NO FLOOR ANY MORE =====
-- An isTooLow() used to sit here refusing any food from an island BELOW the one you are standing on, to stop
-- island 13 being played on beans. It also stopped your coins turning into food: stood on island 4 with 150
-- coins, Turnips (94) were the only legal buy -- one of them, and the other 56 coins bought nothing. On
-- island 1 every coin becomes food, and that is how it should read on every island.
--
-- Removed on both halves at once (PlayerStats.BuyFoodEvent lost the matching "food_below_island" check): a
-- cell that looks buyable while the server refuses it is worse than either gate alone. The beans-at-altitude
-- problem it was covering for is a PRICE TABLE problem -- see CLAUDE.md's "food prices are not monotonic".

-- The one question every buy path should ask. One gate now (the ceiling: have you reached this food's
-- island) but still asked through here, so a future gate is added in one place and cannot be missed at
-- the other three call sites.

-- ============================================================================================================
-- THE 2x FART POWER PASS CHANGES THE SHOP MATH, AND THIS PANEL USED TO IGNORE IT
-- ============================================================================================================
-- With the pass the server does TWO things at once (PlayerStats' BuyFoodEvent handler):
--     powerGain    = floor(food.power  * POWER_PASS_MULT)   -- every food is worth double
--     effectiveMax = floor(StomachMax  * POWER_PASS_MULT)   -- and the tank is twice as deep
-- The StomachMax leaderstat still holds the RAW number, so a 2x player legitimately walks around with
-- CurrentPower well ABOVE it -- 800 power in a 520 gut is normal, and the server will happily sell more.
--
-- This panel read the raw StomachMax and treated it as the ceiling. So the moment CurrentPower passed it,
-- every stand said "Stomach Full", BUY went grey and BUY MAX refused outright -- with money in hand and
-- hundreds of power of real room left. That is the "I have coins but it says my stomach is full" bug, and it
-- looked random because whether you were over the raw max depended on what you had last eaten.
--
-- Mirroring the server's two lines here is the entire fix. Both attributes are set server-side and replicate,
-- so this is a read of authoritative state, not a client-side guess -- and the server still re-checks every
-- single purchase, so being wrong here can only ever mis-LABEL a button, never mis-sell food.
local POWER_PASS_MULT = 2.0 -- MUST match PlayerStats.server.lua
local function has2x()
	if player:GetAttribute("HasTwoXForever") then return true end
	local exp = player:GetAttribute("TwoXHourExpiry")
	return type(exp) == "number" and exp > os.time()
end
-- the real ceiling, and what one unit of a food actually costs against it
local function tankMax(stomMax) return has2x() and math.floor(stomMax * POWER_PASS_MULT) or stomMax end
local function foodGain(power) return has2x() and math.floor(power * POWER_PASS_MULT) or power end

local function canBuy(island)
	return isUnlocked(island)
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

-- REAL uploaded image icons (override the emoji placeholder). For any food NOT in this table the
-- emoji from foodEmojis above is used. The food icons were always emoji TEXT, not images -- Beans
-- showed the 🥜 PEANUT emoji as a stand-in because the bean emoji 🫘 doesn't render in Roblox's font.
-- A food listed here renders its image (ImageLabel.Image) instead of the emoji TextLabel.
local foodImages = {
	Beans = "rbxassetid://133231198126712", -- uploaded bean icon (replaces the 🥜 peanut placeholder)
}

-- Per-food image SCALE (fraction of the normal icon box). Image icons fill the box edge-to-edge, so
-- they read bigger than emoji glyphs (which have built-in whitespace). A value < 1 shrinks ONLY that
-- food's image within its slot (kept centered, so the reduction becomes even padding). Unlisted = 1.0.
local foodImageScale = {
	Beans = 0.8, -- bean icon: 20% smaller, centered in its slot
}

local sg


-- Food Shop
sg=Instance.new("ScreenGui"); sg.Name="FoodShopGui"; sg.ResetOnSpawn=false; sg.Enabled=false; sg.DisplayOrder=100; sg.Parent=PlayerGui -- DisplayOrder 100 = definitively above the HUD (<=5) so the shop covers it
local FoodShopGui=sg
mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,Active=false}) -- invisible + Active=FALSE so clicks OUTSIDE the panel fall through to the HUD MENU BUTTONS (enables direct click-to-switch). The panel itself is Active so panel clicks don't leak to the HUD.
local foodPanel=mkFrame(sg,{Size=UDim2.new(0.92,0,0.78,0),Position=UDim2.new(0.5,0,0.5,-45),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(240,248,255),Active=true}) -- nudged UP ~45px so its bottom clears the stomach/gut indicator below; Active=true blocks pass-through behind the panel
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
-- IMAGE-ICON overlay for foods that have a real uploaded image (e.g. Beans). Same box as foodEmoji;
-- updateFoodShop shows exactly ONE of them (this image if foodImages[name], else the emoji text).
local foodEmojiImg=Instance.new("ImageLabel"); foodEmojiImg.Name="FoodEmojiImg"
foodEmojiImg.AnchorPoint=Vector2.new(0.5,0.5); foodEmojiImg.Position=UDim2.new(0.5,0,0,70); foodEmojiImg.Size=UDim2.new(0,120,0,120) -- centered in the 120px icon box; updateFoodShop applies the per-food scale
foodEmojiImg.BackgroundTransparency=1; foodEmojiImg.ScaleType=Enum.ScaleType.Fit; foodEmojiImg.Visible=false; foodEmojiImg.Parent=foodLeftPanel
local foodName=mkLabel(foodLeftPanel,{Text="Beans",Font=Enum.Font.GothamBold,TextSize=26,TextColor3=Color3.fromRGB(255,255,255),Size=UDim2.new(1,-10,0,35),Position=UDim2.new(0,5,0,135),TextXAlignment=Enum.TextXAlignment.Center})
-- Price row: a centered [coin IMAGE][price text] pair (replaces the non-rendering 💰 emoji
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
-- (Gas-restored + Owned rows REMOVED from the featured display. Name/price/power remain above; the
-- buy buttons remain pinned to the bottom -- nothing else needs to shift, the rows were the lowest stats.)
local foodBuyBtn=mkButton(foodLeftPanel,{Size=UDim2.new(0.44,0,0,50),Position=UDim2.new(0.04,0,1,-58),BackgroundColor3=Color3.fromRGB(50,200,50),Text="BUY FOOD",Font=Enum.Font.GothamBold,TextSize=17,TextColor3=Color3.new(1,1,1)}); mkCorner(foodBuyBtn,12)
local foodBuyMaxBtn=mkButton(foodLeftPanel,{Size=UDim2.new(0.44,0,0,50),Position=UDim2.new(0.52,0,1,-58),BackgroundColor3=Color3.fromRGB(255,140,0),Text="BUY MAX",Font=Enum.Font.GothamBold,TextSize=15,TextColor3=Color3.new(1,1,1)}); mkCorner(foodBuyMaxBtn,12)
-- WHY YOU CAN'T BUY THIS, said in words, directly above the buy buttons.
-- Greying a button out tells you it is dead; it does not tell you WHY. One refusal is left for it to explain
-- (you have not reached this food's island yet) now that the island floor is gone, and it says which island
-- to climb to. Anchored to the BOTTOM of the panel (1,-96) rather than measured down from the stats,
-- because the panel is a fraction of screen height -- on a short screen a top-anchored banner would land on
-- top of the buy buttons instead of above them.
local NOT_HERE = Color3.fromRGB(226, 74, 48)   -- the same hot orange-red the stand refusal banner uses
local foodWhyBanner=mkFrame(foodLeftPanel,{Name="WhyBanner",Size=UDim2.new(0.92,0,0,32),Position=UDim2.new(0.04,0,1,-96),BackgroundColor3=NOT_HERE,Visible=false}); mkCorner(foodWhyBanner,8)
local foodWhyLabel=mkLabel(foodWhyBanner,{Name="WhyLabel",Text="",Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-12,1,-6),Position=UDim2.new(0,6,0,3),TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center})

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
	-- Image-icon overlay in the cell (used instead of the emoji for foods in foodImages, e.g. Beans).
	local iconImg=Instance.new("ImageLabel"); iconImg.Name="FoodIconImg"
	local iScale=foodImageScale[f.name] or 1
	iconImg.Size=UDim2.new(0,50*iScale,0,50*iScale); iconImg.Position=UDim2.new(0.5,0,0.5,0); iconImg.AnchorPoint=Vector2.new(0.5,0.5) -- per-food shrink, centered
	iconImg.BackgroundTransparency=1; iconImg.ScaleType=Enum.ScaleType.Fit
	iconImg.Image=foodImages[f.name] or ""; iconImg.Visible=(foodImages[f.name]~=nil); iconImg.Parent=emojiFrame
	if foodImages[f.name] then emojiLabel.Visible=false end
	mkLabel(cell,{Name="NameLabel",Text=f.name,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.fromRGB(255,255,255),Size=UDim2.new(1,-62,0,30),Position=UDim2.new(0,60,0,5),TextXAlignment=Enum.TextXAlignment.Left})
	-- Coin IMAGE for the cell's price row (replaces the 💰 emoji prefix). Toggled with the
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
mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,Active=false}) -- invisible + Active=FALSE so clicks OUTSIDE the panel fall through to the HUD MENU BUTTONS (direct click-to-switch)
local premPanel=mkFrame(sg,{Size=UDim2.new(0.9,0,0.85,0),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(25,90,185),ClipsDescendants=true,Active=true})
mkCorner(premPanel,28); mkStroke(premPanel,Color3.new(1,1,1),3)
-- INNER floating blue card: ALL content lives in here, inset ~20px so the darker outer frame shows a clean
-- margin all around. ClipsDescendants rounds the header + everything else to the card's corners.
local premCard=mkFrame(premPanel,{Size=UDim2.new(1,0,1,0),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(25,90,185),ClipsDescendants=true})
mkCorner(premCard,26)

local premHeader=mkFrame(premCard,{Size=UDim2.new(1,0,0,65),BackgroundColor3=Color3.fromRGB(15,60,140)})
local premTitleLbl=mkLabel(premHeader,{Text="\xF0\x9F\x9B\x92 SHOP",Font=Enum.Font.GothamBold,TextSize=35,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,-60,0,44),Position=UDim2.new(0,16,0,4),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
mkStroke(premTitleLbl,Color3.new(0,0,0),2)
mkLabel(premHeader,{Text="Power up your adventure!",Font=Enum.Font.Gotham,TextSize=13,TextColor3=Color3.fromRGB(215,228,255),Size=UDim2.new(1,-60,0,16),Position=UDim2.new(0,16,0,46),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
local premClose=mkButton(premHeader,{Size=UDim2.new(0,40,0,40),Position=UDim2.new(1,-48,0,12),BackgroundColor3=Color3.fromRGB(220,50,50),Text="\xe2\x9c\x95",Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.new(1,1,1)})
mkCorner(premClose,8)

-- ===== GAMEPASS SHOP CONTENTS -- proper LAYOUTS (no absolute positions): a vertical scroll holds two
-- sections; each section CENTERS its 3 cards with a horizontal UIListLayout; each card STACKS its content
-- with a vertical UIListLayout and pins the BUY button to the bottom. So every card is uniform, evenly
-- spaced, centered + aligned, comfortably sized, and the list scrolls so nothing is ever cut off. =====
local premScroll=Instance.new("ScrollingFrame")
premScroll.Name="PremiumScroll"; premScroll.BackgroundTransparency=1; premScroll.BorderSizePixel=0
-- y 86, not 162: the 60px currency banner that used to sit at y 74 is gone, so the gamepass list starts
-- straight under the header instead of below a hole where a banner used to be. The height grows by the
-- same 76px it gave up (-238 -> -162), which is what keeps the bottom edge where it was.
premScroll.Position=UDim2.new(0,3,0,86); premScroll.Size=UDim2.new(1,-8,1,-162) -- inset a few px so the scrollbar doesn't touch the card edge
premScroll.ScrollBarThickness=5; premScroll.ScrollBarImageColor3=Color3.fromRGB(255,224,90) -- thin, bright-gold rounded thumb
premScroll.TopImage="rbxasset://textures/ui/Scroll/scroll-top.png"; premScroll.MidImage="rbxasset://textures/ui/Scroll/scroll-middle.png"; premScroll.BottomImage="rbxasset://textures/ui/Scroll/scroll-bottom.png" -- rounded ends
premScroll.CanvasSize=UDim2.new(0,0,0,0); premScroll.ScrollingDirection=Enum.ScrollingDirection.Y
premScroll.AutomaticCanvasSize=Enum.AutomaticSize.None; premScroll.Parent=premCard -- canvas is driven explicitly by syncCanvas below
do
	local sll=Instance.new("UIListLayout"); sll.FillDirection=Enum.FillDirection.Vertical
	sll.HorizontalAlignment=Enum.HorizontalAlignment.Center; sll.Padding=UDim.new(0,18); sll.SortOrder=Enum.SortOrder.LayoutOrder; sll.Parent=premScroll
	local slp=Instance.new("UIPadding"); slp.PaddingTop=UDim.new(0,8); slp.PaddingBottom=UDim.new(0,10); slp.Parent=premScroll
	-- CANVAS = total content height so scrolling reaches every card. We drive CanvasSize EXPLICITLY from the
	-- layout's measured content size (self-updating) -- the reliable equivalent of AutomaticCanvasSize=Y, so the
	-- canvas always grows past the viewport and the scroll actually moves through ALL the items.
	local function syncCanvas() premScroll.CanvasSize=UDim2.new(0,0,0, sll.AbsoluteContentSize.Y + 18) end
	sll:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas); task.defer(syncCanvas)
end
local CARD_W, CARD_H = 208, 190
-- a gold section title + underline, sized to sit in the vertical scroll list
local function sectionHeader(text,order)
	local h=mkFrame(premScroll,{Size=UDim2.new(1,-16,0,52),BackgroundTransparency=1,LayoutOrder=order})
	mkLabel(h,{Text=text,Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,-8,0,26),Position=UDim2.new(0,8,0,4),TextXAlignment=Enum.TextXAlignment.Left})
	mkFrame(h,{Size=UDim2.new(1,-8,0,2),Position=UDim2.new(0,8,0,38),BackgroundColor3=Color3.fromRGB(255,215,0)})
	return h
end
-- a full-width row that evenly spaces + centers its cards
local function mkSectionRow(order)
	local row=mkFrame(premScroll,{Size=UDim2.new(1,-16,0,CARD_H),BackgroundTransparency=1,LayoutOrder=order})
	local ll=Instance.new("UIListLayout"); ll.FillDirection=Enum.FillDirection.Horizontal
	ll.HorizontalAlignment=Enum.HorizontalAlignment.Center; ll.VerticalAlignment=Enum.VerticalAlignment.Top
	ll.Padding=UDim.new(0,24); ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Parent=row
	return row
end
-- a uniform card whose ENTIRE content is one vertical UIListLayout: icon -> name -> price -> [desc] -> BUY,
-- top to bottom in that order. The BUY button is the LAST list item, so it ALWAYS sits below the icon/text --
-- it can never overlap them. UIPadding leaves room at the top for card 1's "BEST VALUE" badge overlay.
local function mkShopCard(parent,order)
	local c=mkFrame(parent,{Size=UDim2.new(0,CARD_W,0,CARD_H),LayoutOrder=order,BackgroundColor3=Color3.fromRGB(20,70,160)})
	mkCorner(c,16); mkStroke(c,Color3.new(1,1,1),2)
	local holder=mkFrame(c,{Name="Content",Size=UDim2.new(1,0,1,0),BackgroundTransparency=1})
	local hl=Instance.new("UIListLayout"); hl.FillDirection=Enum.FillDirection.Vertical
	hl.HorizontalAlignment=Enum.HorizontalAlignment.Center; hl.VerticalAlignment=Enum.VerticalAlignment.Top
	hl.Padding=UDim.new(0,3); hl.SortOrder=Enum.SortOrder.LayoutOrder; hl.Parent=holder
	local hp=Instance.new("UIPadding"); hp.PaddingTop=UDim.new(0,18); hp.PaddingBottom=UDim.new(0,6); hp.PaddingLeft=UDim.new(0,8); hp.PaddingRight=UDim.new(0,8); hp.Parent=holder
	return c
end
local function cH(card) return card:FindFirstChild("Content") or card end -- the content list holder
local function cardIcon(card,txt)
	mkLabel(cH(card),{Text=txt,Font=Enum.Font.Gotham,TextSize=40,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,42),LayoutOrder=1,RichText=false,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center})
end
local function cardTitles(card,main,sub,subCol)
	mkLabel(cH(card),{Text=main,Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,19),LayoutOrder=2,TextXAlignment=Enum.TextXAlignment.Center})
	mkLabel(cH(card),{Text=sub,Font=Enum.Font.GothamBold,TextSize=12,TextColor3=subCol,Size=UDim2.new(1,0,0,15),LayoutOrder=3,TextXAlignment=Enum.TextXAlignment.Center})
end
local function cardPrice(card,price)
	mkLabel(cH(card),{Text=price,Font=Enum.Font.GothamBold,TextSize=15,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,0,0,17),LayoutOrder=4,TextXAlignment=Enum.TextXAlignment.Center})
end
local function cardDesc(card,desc)
	mkLabel(cH(card),{Text=desc,Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.fromRGB(180,210,255),Size=UDim2.new(1,0,0,20),LayoutOrder=5,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Top})
end
-- BUY button: last list item (LayoutOrder 10) -> always rendered BELOW the icon/name/price, never overlapping
local function cardBuyBtn(card,col,txt,onClick)
	local btn=mkButton(cH(card),{Size=UDim2.new(1,0,0,32),LayoutOrder=10,BackgroundColor3=col,Text=txt,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.new(1,1,1)})
	mkCorner(btn,8); btn.MouseButton1Click:Connect(onClick); return btn
end
sectionHeader("\xe2\xad\x90 GAMEPASSES",1)
local gamepassRow=mkSectionRow(2)

-- Card 1: 2x Power Forever
local card1=mkShopCard(gamepassRow,1)
local gpBadge=mkLabel(card1,{Text="BEST VALUE \xe2\xad\x90",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=Color3.fromRGB(80,40,0),Size=UDim2.new(1,-16,0,16),Position=UDim2.new(0.5,0,0,3),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(255,180,0),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=3,Visible=false})
mkCorner(gpBadge,6)
cardIcon(card1,"\xe2\x9a\xa1"); cardTitles(card1,"2x Power","FOREVER",Color3.fromRGB(100,220,100)); cardPrice(card1,"249 R$")
local btn1=cardBuyBtn(card1,Color3.fromRGB(255,180,0),"BUY GAMEPASS",function()
	if _G.playerGamepasses and _G.playerGamepasses.twoXForever then return end -- already owned: do nothing
	pcall(function() MPS:PromptGamePassPurchase(player,GAMEPASS_IDS.TwoXForever) end)
end)
mkStroke(btn1,Color3.fromRGB(200,130,0),2)

-- Card 2: Glitter Trail
local card2=mkShopCard(gamepassRow,2)
cardIcon(card2,"\xe2\x9c\xa8"); cardTitles(card2,"Glitter Trail","PERMANENT",Color3.fromRGB(100,220,100)); cardPrice(card2,"49 R$")
local btn2=cardBuyBtn(card2,Color3.fromRGB(220,80,180),"BUY GAMEPASS",function()
	if _G.playerGamepasses and _G.playerGamepasses.glitterTrail then return end -- already owned: do nothing
	pcall(function() MPS:PromptGamePassPurchase(player,GAMEPASS_IDS.GlitterTrail) end)
end)

-- Card 3: 2x Power 1 Hour
local card3=mkShopCard(gamepassRow,3)
cardIcon(card3,"\xe2\x8f\xb0"); cardTitles(card3,"2x Power","1 HOUR",Color3.fromRGB(255,200,100)); cardPrice(card3,"59 R$")
local twoXShopTimer=mkLabel(cH(card3),{Text="",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=Color3.fromRGB(100,220,100),Size=UDim2.new(1,-8,0,14),LayoutOrder=6,TextXAlignment=Enum.TextXAlignment.Center,Visible=false})
cardBuyBtn(card3,Color3.fromRGB(50,150,255),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.TwoXOneHour) end) end)

-- ===== SECOND GAMEPASS ROW: Lucky / VIP / Coin Magnet ========================================================
-- A SECOND row rather than six cards in the first one: the row is a horizontal UIListLayout with no wrapping,
-- and six 208-wide cards plus padding is 1,368px inside a ~762px scroll -- three of them would simply be cut off
-- the right-hand edge with no way to reach them.
--
-- ⚠ EACH CARD IS INERT UNTIL ITS PASS EXISTS. These three ids are still 0 (see the 0 = UNSET rule in
-- Shared.Gamepasses): the card renders as COMING SOON with a dead grey button, and clicking does nothing.
-- Gamepasses.prompt refuses a 0 id too, so there are two independent guards -- a player can never be shown a
-- broken Robux prompt, which is exactly the failure the placeholder pet-skip products still have.
-- The moment a real id is pasted into Shared.Gamepasses, the card turns into a live BUY GAMEPASS button here
-- with no other edit anywhere.
local gamepassRow2=mkSectionRow(3)

-- One card for an attribute-driven forever pass. Handles all three states: not-created-yet, buyable, owned.
local function passCard(row,order,key,icon,main,sub,desc,btnColor)
	local card=mkShopCard(row,order)
	local live=Gamepasses.isConfigured(key)
	cardIcon(card,icon)
	cardTitles(card,main,live and sub or "COMING SOON",live and Color3.fromRGB(100,220,100) or Color3.fromRGB(190,190,190))
	cardPrice(card,live and ((Gamepasses.PRICE[key] or 0).." R$") or "--")
	cardDesc(card,desc)

	local btn=cardBuyBtn(card,live and btnColor or Color3.fromRGB(90,95,110),live and "BUY GAMEPASS" or "COMING SOON",function()
		if not live then return end                          -- unset id: no prompt, ever
		if Gamepasses.owns(player,key) then return end        -- already owned: do nothing (same rule as the 2x card)
		Gamepasses.prompt(player,key)                         -- guarded + pcall'd inside the shared module
	end)
	-- The polish pass at the bottom of this file repaints EVERY TextButton in a card into the same green "buy"
	-- pill with a hover bounce. A COMING SOON button must not get that treatment or it would look buyable and
	-- bounce under the cursor while doing nothing. This attribute is how that pass knows to leave it grey.
	if not live then btn:SetAttribute("ShopDisabled", true) end

	-- OWNED state. Ownership is the replicated attribute, so this also flips the moment the purchase lands
	-- mid-session -- no menu reopen, no rejoin.
	local function refresh()
		if live and Gamepasses.owns(player,key) then
			btn.Text="OWNED"; btn.BackgroundColor3=Color3.fromRGB(70,150,70)
		end
	end
	refresh()
	if live then player:GetAttributeChangedSignal(Gamepasses.ATTR[key]):Connect(refresh) end
	return card
end

local luckyCard  = passCard(gamepassRow2,1,"LuckyPass","\xF0\x9F\x8D\x80","Lucky Pass","FOREVER",
	"2x rare odds on every crate!",Color3.fromRGB(60,190,90))
local vipCard    = passCard(gamepassRow2,2,"VIP","\xE2\xAD\x90","VIP","FOREVER",
	"+25% coins, 500 coins a day, VIP tag!",Color3.fromRGB(255,180,0))
local magnetCard = passCard(gamepassRow2,3,"CoinMagnet","\xF0\x9F\xA7\xB2","Coin Magnet","FOREVER",
	"Gas bubbles and rings fly to you!",Color3.fromRGB(90,140,255))

-- Every later styling/layout pass in this file works off an explicit card list. Keeping the three new cards in
-- ONE named list means adding a fourth pass later is one more mention of `newPassCards`, not three more card
-- variables threaded through four different loops -- which is exactly how these cards ended up unstyled the
-- first time: they were built correctly and then simply missing from all of those lists.
local newPassCards = {luckyCard, vipCard, magnetCard}

sectionHeader("\xF0\x9F\x8E\xAF ONE-TIME ITEMS",4)
local productRow=mkSectionRow(5)

-- Card 4: Mid-Air Recharge
local card4=mkShopCard(productRow,1)
cardIcon(card4,"\xF0\x9F\x94\x8B"); cardTitles(card4,"Mid-Air","RECHARGE",Color3.fromRGB(100,220,100)); cardPrice(card4,"39 R$"); cardDesc(card4,"Refills gas to 100%!")
cardBuyBtn(card4,Color3.fromRGB(50,200,50),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.MidAirRecharge) end) end)

-- Card 5: Skip Island
local card5=mkShopCard(productRow,2)
cardIcon(card5,"\xF0\x9F\x8F\x9D\xEF\xB8\x8F"); cardTitles(card5,"Skip Island","ONE USE",Color3.fromRGB(255,200,100)); cardPrice(card5,"69 R$"); cardDesc(card5,"Jump to next island!")
cardBuyBtn(card5,Color3.fromRGB(255,140,0),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.SkipIsland) end) end)

-- Card 6: Bird Nuke
local card6=mkShopCard(productRow,3)
cardIcon(card6,"\xF0\x9F\x92\xA5"); cardTitles(card6,"Bird Nuke","CHAOS MODE",Color3.fromRGB(255,100,100)); cardPrice(card6,"79 R$"); cardDesc(card6,"Unleash 30 birds on everyone!")
cardBuyBtn(card6,Color3.fromRGB(220,50,50),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.BirdNuke) end) end)

-- (removed the bottom "Purchases support the game" line -- the footer already says it; less visual noise)

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

-- Hotbar REMOVED: the bottom-right consumable boxes (Mid-Air Recharge "RCHRG" + Skip Island "SKIP"
-- slots/badges, the HotbarGui ScreenGui, and updateHotbar) are gone. Those items are used IMMEDIATELY
-- on purchase by the server (ProcessReceipt -> triggerMidAirRecharge / triggerSkipIsland), so their
-- held-count was always 0 and the boxes were pointless clutter. The item EFFECTS are untouched.
-- (_G.updateHotbar is no longer defined; its one caller in CoreClient is `if _G.updateHotbar then ...`,
-- which now safely no-ops.)

-- The CURRENTLY FEATURED food shown in the big left display. Defaults to the island's MAIN food
-- (_G.foods[islandNum]) on shop open; clicking a grid cell swaps it. The BUY / BUY MAX buttons act on
-- THIS food. Persists across live refreshes (only reset on shop open / explicit grid selection).
local featuredFood

local function updateFoodShop(islandNum)
	nearIslandNumber=islandNum
	if not featuredFood then featuredFood = _G.foods[islandNum] end  -- safety net; shop OPEN resets to the main food
	foodTitle.Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F ISLAND "..islandNum.." FOOD STAND"

	-- ===== BIG FEATURED DISPLAY =====
	-- Shows the CURRENTLY FEATURED food (default = this island's main food; clicking a grid cell swaps
	-- it). Stats are ALWAYS shown, even when the featured food is LOCKED -- in that case it's greyed and
	-- the BUY buttons read "LOCKED" so the player sees what they'd get without being able to buy it.
	local f=featuredFood; if not f then return end
	local fLocked = not canBuy(f.island)
	-- ONE reason a food can't be bought now: you have never reached its island. There used to be a second --
	-- "too low", standing above the island that sells it -- with its own red NOT SOLD HERE state. The floor is
	-- gone, so that state went with it: every food you have unlocked is on sale at every stand.
	foodLockedFrame.Visible=false  -- locked is now shown inline (greyed stats + LOCKED buttons), not the full cover
	foodEmoji.Visible=true; foodName.Visible=true; foodPriceRow.Visible=true; foodPower.Visible=true
	foodBuyBtn.Visible=true; foodBuyMaxBtn.Visible=true
	-- Icon: a real uploaded IMAGE if this food has one (e.g. Beans), otherwise the emoji TextLabel.
	local fImg = foodImages[f.name]
	local fScale = foodImageScale[f.name] or 1
	foodEmojiImg.Size = UDim2.new(0, 120*fScale, 0, 120*fScale) -- per-food shrink, stays centered (anchor 0.5,0.5)
	foodEmojiImg.Image = fImg or ""; foodEmojiImg.Visible = (fImg ~= nil); foodEmojiImg.ImageTransparency = fLocked and 0.5 or 0
	foodEmoji.Visible = (fImg == nil)
	foodEmoji.Text=foodEmojis[f.name] or "?"; foodEmoji.TextTransparency = fLocked and 0.5 or 0
	foodName.Text = (fLocked and (f.name.."  \xF0\x9F\x94\x92 LOCKED") or f.name)
	foodName.TextColor3 = fLocked and Color3.fromRGB(150,150,150) or Color3.fromRGB(255,255,255) -- WHITE name (was black)
	foodPrice.Text=f.price.." coins"  -- coin shown by the CoinIcon ImageLabel in the row, not text
	foodPrice.TextColor3 = fLocked and Color3.fromRGB(150,150,150) or Color3.fromRGB(200,140,0)
	foodPower.Text="+"..f.power.." power"
	foodPower.TextColor3 = fLocked and Color3.fromRGB(150,150,150) or Color3.fromRGB(0,160,60)
	local coins, curPower, stomMax = 0, 0, 46
	pcall(function() if _G.leaderstats then
		local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end
		local cp=_G.leaderstats:FindFirstChild("CurrentPower"); if cp then curPower=cp.Value end
		local sm=_G.leaderstats:FindFirstChild("StomachMax"); if sm then stomMax=sm.Value end
	end end)
	-- (Gas + Owned stat rows removed from the featured display. coins/curPower/stomMax above are still
	-- read because the BUY/BUY MAX state below uses them.)
	-- How many of this food actually fit in the remaining stomach space, and can be afforded.
	-- tankMax/foodGain, not the raw numbers: with the 2x pass the tank is twice as deep and each food is
	-- worth twice as much, and reading the raw StomachMax here is what used to say "Stomach Full" to a 2x
	-- player with room to spare (see the note beside tankMax).
	local tank        = tankMax(stomMax)
	local fittable    = math.floor((tank - curPower) / foodGain(f.power))
	local affordable  = math.floor(coins / f.price)
	local fitAndAfford = math.min(fittable, affordable)
	if fLocked then
		-- NEVER REACHED: stats shown (greyed) above, but buying is disabled. Grey is right here -- this one
		-- really is "come back later", and the banner says how.
		foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text="LOCKED"; foodBuyBtn.TextSize=16
		foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyMaxBtn.Text="LOCKED"; foodBuyMaxBtn.TextSize=16
		foodWhyBanner.Visible=true; foodWhyBanner.BackgroundColor3=Color3.fromRGB(120,124,136)
		foodWhyLabel.Text=("\xF0\x9F\x94\x92 Reach Island %d to unlock %s."):format(f.island, f.name)
	else
		foodWhyBanner.Visible=false
		-- Single BUY: COINS checked FIRST (the common blocker) -> "Not Enough Coins"; then stomach
		-- capacity -> "Stomach Full"; only when both pass is it buyable.
		if coins < f.price then
			foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text="Not Enough Coins"; foodBuyBtn.TextSize=14
		elseif fittable < 1 then
			-- can't fit one: TRULY full (no room at all) vs HAS room but this food is too big
			foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text=((tank-curPower)<=0) and "Stomach Full" or "Not Enough Room"; foodBuyBtn.TextSize=14
		else
			foodBuyBtn.BackgroundColor3=Color3.fromRGB(50,200,50); foodBuyBtn.Text="BUY FOOD"; foodBuyBtn.TextSize=17
		end
		-- BUY MAX label shows the fit-and-afford quantity, never the wallet-only amount.
		if fitAndAfford >= 1 then
			foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(255,140,0); foodBuyMaxBtn.Text="MAX x"..fitAndAfford; foodBuyMaxBtn.TextSize=14
		elseif fittable < 1 then
			foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyMaxBtn.Text=((tank-curPower)<=0) and "FULL" or "NO ROOM"; foodBuyMaxBtn.TextSize=15
		else
			foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyMaxBtn.Text="BUY MAX"; foodBuyMaxBtn.TextSize=15
		end
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
			local iconImg=ef and ef:FindFirstChild("FoodIconImg")
			if not canBuy(fd.island) then
				-- ONE refusal left: NOT REACHED -- a mystery, no name, no price, nothing spoiled.
				-- (The other one, TOO LOW, went with the island floor: no food you have unlocked is
				--  refused at a stand any more, so a cell is either buyable or not yet climbed to.)
				cell.BackgroundColor3 = Color3.fromRGB(208,213,221)
				if st then st.Color = Color3.fromRGB(140,140,140) end
				if iconImg then iconImg.Visible=false end -- locked -> show the emoji, hide any image icon
				if icon then icon.Visible=true; icon.Text = "\xF0\x9F\x94\x92" end
				if ef then ef.Position=UDim2.new(0.5,0,0.5,0); ef.AnchorPoint=Vector2.new(0.5,0.5) end -- center the icon in the box
				-- Name and price blanked: an unreached food is a locked box, not a listing.
				if nm then
					nm.RichText = false
					nm.Text = ""
					nm.TextColor3 = Color3.fromRGB(96,72,68)
				end
				if pl then
					pl.Text = ""
					pl.Font = Enum.Font.GothamBold
					pl.TextColor3 = Color3.fromRGB(186,52,32)
				end
				local pic=cell:FindFirstChild("PriceIcon"); if pic then pic.Visible=false end  -- no price -> hide coin
					if st then if featuredFood and fd.name==featuredFood.name then st.Color=Color3.fromRGB(255,215,0); st.Thickness=4 else st.Thickness=2 end end -- gold border = the FEATURED cell (locked food still highlightable)
			else
				-- UNLOCKED: reveal the real icon + name + price (restores from the locked state, so it
				-- switches live the moment the player reaches the island).
				local cImg=foodImages[fd.name] -- real image icon for this food (e.g. Beans), else nil -> emoji
				if ef then ef.Position=UDim2.new(0,2,0.5,0); ef.AnchorPoint=Vector2.new(0,0.5) end -- restore the icon to the LEFT
				if iconImg then iconImg.Image=cImg or ""; iconImg.Visible=(cImg~=nil) end
				if icon then icon.Visible=(cImg==nil); icon.Text=foodEmojis[fd.name] or "\xF0\x9F\x8D\xBD\xEF\xB8\x8F" end
				-- Undo every part of the locked look. Cells are REUSED, so anything the branch above changes has
				-- to be changed back here or a food that unlocks keeps its strikethrough forever.
				if nm then nm.RichText=false; nm.Text=fd.name; nm.TextColor3=Color3.fromRGB(255,255,255) end
				if (stomMax - curPower) >= fd.power and coins2>=fd.price then  -- buyable: fits at least one of this food AND affordable
					cell.BackgroundColor3=Color3.fromRGB(50,200,50); if st then st.Color=Color3.fromRGB(30,150,30) end
				else
					cell.BackgroundColor3=Color3.fromRGB(180,50,50); if st then st.Color=Color3.fromRGB(120,30,30) end  -- RED: owned/maxed (stomach can't fit one) OR can't afford
				end
				if pl then pl.Text=tostring(fd.price); pl.Font=Enum.Font.Gotham; pl.TextColor3=Color3.fromRGB(120,80,0) end  -- coin shown by the PriceIcon ImageLabel, not text
				local pic=cell:FindFirstChild("PriceIcon"); if pic then pic.Visible=true end  -- priced -> show coin
					if st then if featuredFood and fd.name==featuredFood.name then st.Color=Color3.fromRGB(255,215,0); st.Thickness=4 else st.Thickness=2 end end -- gold border = the FEATURED cell
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
	-- 6-COLOUR VIRAL PET-SIM THEME (shared across the pop-ups). Fresh indigo/blurple base; gold/green/red reused
	-- from the Rebirth HUD. Style = thick outlines + drop shadow + "juicy" beveled buttons + chunky FredokaOne.
	local PANEL  = Color3.fromRGB(25, 90, 185)  -- 1 pets-HUD blue (main background)
	local PANEL2 = Color3.fromRGB(42, 122, 214) -- 2 lighter blue (gradient top)
	local ACCENT = Color3.fromRGB(120, 104, 240)-- 3 blurple (header / highlights)
	local GOLD   = Color3.fromRGB(255, 206, 92) -- 4 gold (title / prices)  [from Rebirth]
	local GREEN  = Color3.fromRGB(86, 205, 120) -- 5 green (buy)            [from Rebirth]
	local RED    = Color3.fromRGB(232, 96, 90)  -- 6 red (close)            [from Rebirth]
	local function dark(c, f) return c:Lerp(Color3.new(0, 0, 0), f or 0.5) end
	local function setStroke(i, col, th) local s = i:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke"); s.Color = col; s.Thickness = th; s.Parent = i; return s end
	local function juice(i) -- top-bright -> bottom-dark bevel (multiplies the bg colour), the pet-sim button look
		if i:FindFirstChildOfClass("UIGradient") then return end
		local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(170,170,170)); g.Rotation = 90; g.Parent = i
	end
	local function vgrad(i, top, bot) local g = i:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient"); g.Color = ColorSequence.new(top, bot); g.Rotation = 90; g.Parent = i; return g end

	-- chunky white FredokaOne text + black outline on everything
	for _, v in ipairs(premPanel:GetDescendants()) do
		if v:IsA("TextLabel") or v:IsA("TextButton") then
			v.Font = Enum.Font.FredokaOne; v.TextScaled = true; v.TextColor3 = Color3.fromRGB(255,255,255)
			setStroke(v, Color3.fromRGB(0,0,0), 2)
		end
	end

	-- subtle soft drop shadow -- just enough to lift the window off the game world (no big blurry glow)
	local sh = Instance.new("ImageLabel")
	sh.AnchorPoint = Vector2.new(0.5,0.5); sh.Position = UDim2.new(0.5,0,0.5,-40); sh.Size = UDim2.fromOffset(786,586)
	sh.BackgroundTransparency = 1; sh.Image = "rbxassetid://1316045217"; sh.ImageColor3 = Color3.new(0,0,0); sh.ImageTransparency = 0.9 -- very subtle, just lifts the card off the world
	sh.ScaleType = Enum.ScaleType.Slice; sh.SliceCenter = Rect.new(10,10,118,118); sh.ZIndex = 0; sh.Parent = premPanel.Parent

	-- ONE clean floating blue card -- no dark outer box, no inner shadow
	premPanel.BackgroundTransparency = 1 -- transparent container so nothing dark surrounds the card
	premPanel.ClipsDescendants = false -- let the card's own rounded corners + outline show fully
	local _ps = premPanel:FindFirstChildOfClass("UIStroke"); if _ps then _ps:Destroy() end
	premCard.BackgroundColor3 = PANEL; vgrad(premCard, PANEL2, Color3.fromRGB(96,60,178)); setStroke(premCard, Color3.new(0,0,0), 4) -- thick BLACK outline around the whole window
	premHeader.BackgroundTransparency = 1 -- transparent header -> the card's rounded TOP corners show (all four match)
	do -- gentle shine sweep across the SHOP header every few seconds
		premHeader.ClipsDescendants = true
		local shine = Instance.new("Frame"); shine.BackgroundColor3 = Color3.new(1,1,1); shine.BackgroundTransparency = 0.55
		shine.Size = UDim2.new(0,60,1,0); shine.Rotation = 8; shine.ZIndex = (premHeader.ZIndex or 1)+2; shine.Parent = premHeader
		local sg = Instance.new("UIGradient", shine); sg.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.5,0),NumberSequenceKeypoint.new(1,1)})
		task.spawn(function()
			while shine.Parent do
				shine.Position = UDim2.new(-0.2,0,0,0)
				TweenService:Create(shine, TweenInfo.new(0.9, Enum.EasingStyle.Sine), {Position = UDim2.new(1.2,0,0,0)}):Play()
				task.wait(4)
			end
		end)
	end
	-- close + title
	premClose.BackgroundColor3 = RED; setStroke(premClose, dark(RED, 0.45), 3); juice(premClose)
	premTitleLbl.TextColor3 = GOLD

	-- cards: lighter indigo + thick outline + bevel
	for _, card in ipairs({card1, card2, card3, card4, card5, card6,
	                       newPassCards[1], newPassCards[2], newPassCards[3]}) do
		card.BackgroundColor3 = PANEL2; setStroke(card, dark(PANEL, 0.35), 2.5); juice(card)
	end

	-- buy buttons (gamepass = gold, one-time = green) + gold prices/section titles
	for _, v in ipairs(premPanel:GetDescendants()) do
		if v:IsA("TextButton") then
			if v.Text:find("BUY GAMEPASS") then v.BackgroundColor3 = GOLD; setStroke(v, dark(GOLD, 0.5), 2.5); juice(v)
			elseif v.Text:find("BUY NOW") then v.BackgroundColor3 = GREEN; setStroke(v, dark(GREEN, 0.5), 2.5); juice(v) end
		end
		if v:IsA("TextLabel") then
			if v.Text:find("R%$") then v.TextColor3 = GOLD end
			if v.Text:find("GAMEPASSES") or v.Text:find("ONE%-TIME") then v.TextColor3 = GOLD end
		end
	end

	-- gpBadge: dark text on gold, no outline
	gpBadge.TextColor3 = dark(GOLD, 0.72); gpBadge.BackgroundColor3 = GOLD
	local gbS = gpBadge:FindFirstChildOfClass("UIStroke"); if gbS then gbS:Destroy() end
end)()

-- ===== PREMIUM SHOP LAYOUT =====
;(function()
	-- Panel taller to fit bigger cards
	premPanel.Size = UDim2.new(0,770,0,572) -- ~10% bigger than the food shop for more breathing room
	premPanel.Position = UDim2.new(0.5,0,0.5,-45) -- POSITION matched to the food shop (centered, nudged up 45px)
	premPanel.AnchorPoint = Vector2.new(0.5,0.5)

	-- Keep the cards in their ORIGINAL section rows (gamepassRow / productRow). Those rows live INSIDE premScroll,
	-- right under their section headers, so the headers AND the cards scroll TOGETHER. (The bug: these cards used to be
	-- re-parented onto the FIXED premPanel, so only the headers -- still in the scroll -- moved, sliding over the pinned
	-- cards.) Just resize the rows to the card heights, then size + order the cards inside them.
	gamepassRow.Size = UDim2.new(1,-16,0,190)
	-- The SECOND gamepass row is 220 like the product row, not 190 like the first. The three new passes each
	-- carry a description line ("2x rare odds on every crate!"), and 190 is the height for a card WITHOUT one --
	-- at 190 the desc and the buy button fight for the same 30px and the button clips off the bottom.
	gamepassRow2.Size = UDim2.new(1,-16,0,220)
	productRow.Size  = UDim2.new(1,-16,0,220)
	for i, c in ipairs({card1, card2, card3}) do
		c.Parent = gamepassRow; c.LayoutOrder = i; c.Size = UDim2.new(0.31,0,0,190)
	end
	for i, c in ipairs(newPassCards) do
		c.Parent = gamepassRow2; c.LayoutOrder = i; c.Size = UDim2.new(0.31,0,0,220)
	end
	for i, c in ipairs({card4, card5, card6}) do
		c.Parent = productRow; c.LayoutOrder = i; c.Size = UDim2.new(0.31,0,0,220)
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
		ll.Padding = UDim.new(0,8) -- more breathing room between icon/title/desc/price/button
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
		ll.VerticalAlignment = Enum.VerticalAlignment.Top
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Parent = cf

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0,10)
		pad.PaddingBottom = UDim.new(0,10)
		pad.PaddingLeft = UDim.new(0,8)
		pad.PaddingRight = UDim.new(0,8)
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
	-- ⚠ layoutCard IS DEAD CODE -- for these six too, not just the new cards, so nothing is being skipped here.
	-- It collects `card:GetChildren()` looking for the icon / labels / buy button, but mkShopCard puts all of
	-- those inside a child Frame named "Content" (every card* helper parents through cH()). So the loop finds
	-- one Frame, matches none of its branches, and the function just adds an empty "_Content" frame to the card.
	-- The layout you actually see comes from mkShopCard's own UIListLayout plus the polish pass at the bottom of
	-- this file, which walks GetDescendants() and therefore does reach inside "Content".
	-- The new cards are deliberately NOT passed through it: adding a dead call to match dead calls is not parity.
	-- (The row/size loop ABOVE is live and does matter -- that is why the new cards are in that one.)
end)()

-- Explicitly style the shop close button
premClose.Text = "X"
premClose.Font = Enum.Font.FredokaOne
premClose.TextScaled = true
premClose.TextColor3 = Color3.fromRGB(255,255,255)
local pcs = premClose:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
pcs.Color = Color3.fromRGB(0,0,0); pcs.Thickness = 2; pcs.Parent = premClose

-- ===== LOW-POLY BEAN / COIN / MASCOT BUILDERS (shared) =====
-- Built from Frames, NOT emoji: the 🫘 bean emoji renders as an empty box in Roblox's font -- that box was the
-- "empty square" in the banner + footer. These always render and fit the low-poly cartoon look.
local BEAN_IMG = "rbxassetid://133231198126712" -- the SAME uploaded bean icon the food stand uses (always renders)
local function _rc(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = i end
local function _rs(i, col, th) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th; s.Parent = i end
local function makeBeanImg(parent, sz, z) local b = Instance.new("ImageLabel"); b.BackgroundTransparency = 1; b.Image = BEAN_IMG; b.Size = UDim2.fromOffset(sz, sz); b.ZIndex = z; b.Parent = parent; return b end
local _coinPhase = 0
-- Premium low-poly coin: real depth (thickness edge), light-yellow->rich-gold gradient, glossy top shine,
-- beveled dark rim, embossed star, upper-left highlight, and a slow shine sweep. Returns a `holder` frame
-- (the caller positions the holder; the coin's thickness renders just below it).
local function makeCoin(parent, sz, z)
	local holder = Instance.new("Frame"); holder.BackgroundTransparency = 1; holder.Size = UDim2.fromOffset(sz, sz); holder.ZIndex = z; holder.Parent = parent
	local depth = math.max(2, math.floor(sz * 0.09))
	local edge = Instance.new("Frame"); edge.AnchorPoint = Vector2.new(0.5, 0); edge.Position = UDim2.new(0.5, 0, 0, depth); edge.Size = UDim2.fromOffset(sz, sz); edge.BackgroundColor3 = Color3.fromRGB(176, 112, 16); edge.ZIndex = z; edge.Parent = holder; _rc(edge, sz)
	local face = Instance.new("Frame"); face.Size = UDim2.fromOffset(sz, sz); face.BackgroundColor3 = Color3.fromRGB(255, 206, 92); face.ClipsDescendants = true; face.ZIndex = z + 1; face.Parent = holder; _rc(face, sz); _rs(face, Color3.fromRGB(150, 96, 12), math.max(1.5, sz * 0.06))
	local fg = Instance.new("UIGradient", face); fg.Rotation = 90; fg.Color = ColorSequence.new(Color3.fromRGB(255, 242, 158), Color3.fromRGB(232, 166, 38))
	local inner = Instance.new("Frame"); inner.AnchorPoint = Vector2.new(0.5, 0.5); inner.Position = UDim2.fromScale(0.5, 0.52); inner.Size = UDim2.fromScale(0.64, 0.64); inner.BackgroundColor3 = Color3.fromRGB(255, 226, 120); inner.ZIndex = z + 2; inner.Parent = face; _rc(inner, sz); _rs(inner, Color3.fromRGB(210, 146, 26), math.max(1, sz * 0.03))
	local ig = Instance.new("UIGradient", inner); ig.Rotation = 90; ig.Color = ColorSequence.new(Color3.fromRGB(255, 248, 196), Color3.fromRGB(240, 188, 66))
	local star = Instance.new("TextLabel"); star.BackgroundTransparency = 1; star.AnchorPoint = Vector2.new(0.5, 0.5); star.Position = UDim2.fromScale(0.5, 0.5); star.Size = UDim2.fromScale(0.74, 0.74); star.Font = Enum.Font.FredokaOne; star.TextScaled = true; star.Text = "\xE2\x98\x85"; star.TextColor3 = Color3.fromRGB(206, 144, 26); star.ZIndex = z + 3; star.Parent = inner
	local gloss = Instance.new("Frame"); gloss.AnchorPoint = Vector2.new(0.5, 0); gloss.Position = UDim2.new(0.5, 0, 0, math.max(2, sz * 0.08)); gloss.Size = UDim2.fromScale(0.64, 0.30); gloss.BackgroundColor3 = Color3.new(1, 1, 1); gloss.BackgroundTransparency = 0.35; gloss.ZIndex = z + 4; gloss.Parent = face; _rc(gloss, sz)
	local glg = Instance.new("UIGradient", gloss); glg.Rotation = 90; glg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	local hl = Instance.new("Frame"); hl.AnchorPoint = Vector2.new(0.5, 0.5); hl.Position = UDim2.fromScale(0.32, 0.3); hl.Size = UDim2.fromScale(0.13, 0.13); hl.BackgroundColor3 = Color3.new(1, 1, 1); hl.BackgroundTransparency = 0.1; hl.ZIndex = z + 5; hl.Parent = face; _rc(hl, sz)
	if sz >= 30 then -- slow shine sweep across the face (bigger coins only), staggered so they don't sync
		local streak = Instance.new("Frame"); streak.BackgroundColor3 = Color3.new(1, 1, 1); streak.BackgroundTransparency = 0.55; streak.BorderSizePixel = 0; streak.Rotation = 20; streak.Size = UDim2.new(0.3, 0, 1.6, 0); streak.Position = UDim2.new(-0.45, 0, -0.3, 0); streak.ZIndex = z + 6; streak.Parent = face
		local sgr = Instance.new("UIGradient", streak); sgr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 1) })
		_coinPhase = (_coinPhase + 1) % 5; local ph = _coinPhase * 0.6
		task.spawn(function()
			task.wait(ph)
			while streak.Parent do
				streak.Position = UDim2.new(-0.45, 0, -0.3, 0)
				TweenService:Create(streak, TweenInfo.new(0.85, Enum.EasingStyle.Sine), { Position = UDim2.new(1.15, 0, -0.3, 0) }):Play()
				task.wait(3.6)
			end
		end)
	end
	return holder
end
-- Unique coin pile per bundle {xScale, yScale, sizePx, rotDeg}. More/bigger coins = more value at a glance.
local COIN_PILES = {
	{{0.5,0.5,52,0}},
	{{0.33,0.6,38,-8},{0.67,0.6,38,8},{0.5,0.42,42,0}},
	{{0.26,0.62,34,-12},{0.74,0.62,34,12},{0.42,0.48,36,-4},{0.6,0.46,36,6}},
	{{0.22,0.64,32,-14},{0.5,0.66,38,0},{0.78,0.64,32,14},{0.36,0.46,34,-6},{0.62,0.46,34,6}},
	{{0.18,0.64,30,-16},{0.4,0.68,34,-4},{0.6,0.68,34,6},{0.82,0.64,30,16},{0.3,0.46,32,-8},{0.58,0.44,34,10},{0.5,0.3,30,0}},
	{{0.16,0.68,28,-18},{0.36,0.7,32,-6},{0.58,0.7,32,6},{0.8,0.68,28,18},{0.28,0.5,32,-10},{0.5,0.48,36,2},{0.7,0.5,32,12},{0.4,0.32,30,-6},{0.6,0.32,30,8}},
}
local function makeBean(parent, w, z, col, rot)
	local b = Instance.new("Frame"); b.Size = UDim2.fromOffset(w, math.floor(w * 1.3)); b.BackgroundColor3 = col; b.Rotation = rot or 0; b.ZIndex = z; b.Parent = parent; _rc(b, w); _rs(b, Color3.fromRGB(70, 150, 50), 2)
	return b
end
local function makeMascot(parent, w, z) -- a smiling bean: body + two eyes + a crescent smile (dark disc masked by a body-coloured disc)
	local BODY = Color3.fromRGB(128, 206, 96)
	local body = makeBean(parent, w, z, BODY, -8)
	for _, ex in ipairs({ -0.22, 0.22 }) do
		local eye = Instance.new("Frame"); eye.AnchorPoint = Vector2.new(0.5, 0.5); eye.Position = UDim2.fromScale(0.5 + ex, 0.34); eye.Size = UDim2.fromScale(0.15, 0.12); eye.BackgroundColor3 = Color3.fromRGB(30, 44, 26); eye.ZIndex = z + 2; eye.Parent = body; _rc(eye, 20)
	end
	local mouth = Instance.new("Frame"); mouth.AnchorPoint = Vector2.new(0.5, 0.5); mouth.Position = UDim2.fromScale(0.5, 0.64); mouth.Size = UDim2.fromScale(0.46, 0.28); mouth.BackgroundColor3 = Color3.fromRGB(30, 44, 26); mouth.ZIndex = z + 2; mouth.Parent = body; _rc(mouth, 20)
	local cover = Instance.new("Frame"); cover.AnchorPoint = Vector2.new(0.5, 0.5); cover.Position = UDim2.fromScale(0.5, 0.57); cover.Size = UDim2.fromScale(0.56, 0.22); cover.BackgroundColor3 = BODY; cover.ZIndex = z + 3; cover.Parent = body
	return body
end

-- ===== PREMIUM SHOP -- SIMULATOR-GRADE POLISH =====
-- rainbow card gradients + glowing borders, gold price capsules, pulsing icons, hover pop, footer banner +
-- bean mascot, drifting sparkles, and a slide-in-from-bottom. Runs deferred so the card layout is final first.
task.defer(function()
	local TS = game:GetService("TweenService")
	-- The three new passes are APPENDED, not interleaved in visual order, on purpose: CARD_COLS is indexed by
	-- position in this list, so slotting them in the middle would silently re-colour every existing card.
	local cards = {card1, card2, card3, card4, card5, card6,
	               newPassCards[1], newPassCards[2], newPassCards[3]}
	local CARD_COLS = { -- 9 unique gradients, no repeats: blue, purple, pink, green, cyan, orange, lime, gold, indigo
		Color3.fromRGB(64,120,245), Color3.fromRGB(150,96,240), Color3.fromRGB(240,96,180),
		Color3.fromRGB(72,200,120), Color3.fromRGB(64,200,224), Color3.fromRGB(248,150,56),
		-- 7-9 = Lucky (lime, matches the clover), VIP (gold, matches the tag), Coin Magnet (indigo).
		-- These MUST exist: the loop below does CARD_COLS[i]:Lerp(...), so a nil here is a hard error that
		-- takes the whole polish pass down and leaves every card unstyled -- not just the new ones.
		Color3.fromRGB(140,214,72), Color3.fromRGB(246,196,60), Color3.fromRGB(96,116,236),
	}
	local function light(c) return c:Lerp(Color3.new(1,1,1), 0.24) end
	local function dark(c, f) return c:Lerp(Color3.new(0,0,0), f or 0.45) end

	for i, card in ipairs(cards) do
		if card then
			local col = CARD_COLS[i]:Lerp(Color3.fromRGB(150,150,158), 0.14) -- slightly desaturated so text reads clearly
			card.BackgroundColor3 = col
			local g = card:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
			g.Color = ColorSequence.new(light(col), dark(col, 0.28)); g.Rotation = 90; g.Parent = card
			local s = card:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
			s.Color = light(col); s.Thickness = 2.5; s.Transparency = 0.06; s.Parent = card -- glowing border (thinner)
			local cc = card:FindFirstChildOfClass("UICorner") or Instance.new("UICorner"); cc.CornerRadius = UDim.new(0,18); cc.Parent = card

			do -- soft shine strip across the top of the card (static)
				local sheen = Instance.new("Frame"); sheen.BackgroundColor3 = Color3.new(1,1,1); sheen.BorderSizePixel = 0; sheen.BackgroundTransparency = 0.74
				sheen.Size = UDim2.new(1,-16,0,10); sheen.Position = UDim2.new(0,8,0,6); sheen.ZIndex = (card.ZIndex or 1)+4; sheen.Parent = card
				Instance.new("UICorner", sheen).CornerRadius = UDim.new(0,6)
				local shG = Instance.new("UIGradient", sheen); shG.Rotation = 90; shG.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.45),NumberSequenceKeypoint.new(1,1)})
			end
			-- icon stays still (no idle pulse)
			for _, d in ipairs(card:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text:find("R%$") then -- price -> compact gold capsule with a coin, BELOW the desc
					d.BackgroundColor3 = Color3.fromRGB(255,206,92); d.BackgroundTransparency = 0; d.TextColor3 = Color3.fromRGB(92,58,8)
					d.Size = UDim2.fromOffset(128,24); d.LayoutOrder = 9 -- gold price capsule (same width as the coin cards), centered above the button
					local pg = d:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient"); pg.Color = ColorSequence.new(Color3.fromRGB(255,238,176), Color3.fromRGB(240,190,60)); pg.Rotation = 90; pg.Parent = d -- glossy
					if not d.Text:find("\xF0\x9F\x92\xB0") then d.Text = "\xF0\x9F\x92\xB0 " .. d.Text end
					local pc = d:FindFirstChildOfClass("UICorner") or Instance.new("UICorner"); pc.CornerRadius = UDim.new(1,0); pc.Parent = d
					local ps = d:FindFirstChildOfClass("UIStroke"); if ps then ps.Color = Color3.fromRGB(180,122,20); ps.Thickness = 2 end
					break
				end
			end

			for _, d in ipairs(card:GetDescendants()) do
				if d:IsA("TextButton") then -- ONE short, centered green pill purchase button at the bottom
					-- A COMING SOON button (a pass whose Robux id has not been created yet) gets the same SHAPE
					-- and position as every other button -- so the row still reads as one tidy set of cards --
					-- but stays grey and does NOT get the hover/click bounce. Something that springs under the
					-- cursor is promising a purchase it cannot deliver.
					local disabled = d:GetAttribute("ShopDisabled") == true
					d.Size = UDim2.new(0.8,0,0,36); d.LayoutOrder = 20
					local bc = d:FindFirstChildOfClass("UICorner") or Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,18); bc.Parent = d
					if disabled then
						d.BackgroundColor3 = Color3.fromRGB(96,100,116)
						d.TextTransparency = 0.25
						local dg = d:FindFirstChildOfClass("UIGradient"); if dg then dg:Destroy() end -- flat, obviously inert
						local ds = d:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke"); ds.Color = Color3.fromRGB(58,62,74); ds.Thickness = 1.5; ds.Parent = d
						break
					end
					d.BackgroundColor3 = Color3.fromRGB(96,210,128)
					local bg2 = d:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient"); bg2.Color = ColorSequence.new(Color3.fromRGB(142,226,160), Color3.fromRGB(86,184,112)); bg2.Rotation = 90; bg2.Parent = d
					local bsr = d:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke"); bsr.Color = Color3.fromRGB(46,120,68); bsr.Thickness = 1.5; bsr.Parent = d
					local bScl = Instance.new("UIScale"); bScl.Parent = d -- hover glow + click bounce (interaction only)
					d.MouseEnter:Connect(function() TS:Create(bScl, TweenInfo.new(0.1), {Scale=1.05}):Play() end)
					d.MouseLeave:Connect(function() TS:Create(bScl, TweenInfo.new(0.1), {Scale=1}):Play() end)
					d.MouseButton1Down:Connect(function() bScl.Scale=0.92; TS:Create(bScl, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale=1}):Play() end)
					break
				end
			end

			local baseSize = card.Size -- hover pop (PC)
			card.MouseEnter:Connect(function() TS:Create(card, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = baseSize + UDim2.fromOffset(12,12) }):Play() end)
			card.MouseLeave:Connect(function() TS:Create(card, TweenInfo.new(0.12), { Size = baseSize }):Play() end)
		end
	end

	-- soft glow behind the SHOP title
	local glow = Instance.new("ImageLabel")
	glow.BackgroundTransparency = 1; glow.Image = "rbxassetid://1316045217"; glow.ImageColor3 = Color3.fromRGB(255,220,120); glow.ImageTransparency = 0.55
	glow.ScaleType = Enum.ScaleType.Slice; glow.SliceCenter = Rect.new(10,10,118,118)
	glow.Size = UDim2.fromOffset(250,72); glow.Position = premTitleLbl.Position - UDim2.fromOffset(16,10); glow.ZIndex = math.max(0, premTitleLbl.ZIndex - 1); glow.Parent = premTitleLbl.Parent

	do -- subtle sparkles around the SHOP title (twinkle in place, no movement)
		for k = 1, 3 do
			local tw = Instance.new("TextLabel"); tw.BackgroundTransparency = 1; tw.Font = Enum.Font.GothamBold; tw.Text = "\xE2\x9C\xA6"
			tw.TextColor3 = Color3.fromRGB(255,240,180); tw.TextSize = 10 + k*2; tw.Size = UDim2.fromOffset(16,16)
			tw.Position = UDim2.new(0, 130 + k*24, 0, (k % 2 == 0 and 8 or 32)); tw.ZIndex = (premTitleLbl.ZIndex or 1) + 1; tw.Parent = premTitleLbl.Parent
			TS:Create(tw, TweenInfo.new(0.8 + k*0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.85 }):Play()
		end
	end

	-- footer: full-width purple gradient banner + bean mascot
	local footer = Instance.new("Frame")
	footer.AnchorPoint = Vector2.new(0.5,1); footer.Position = UDim2.new(0.5,0,1,-10); footer.Size = UDim2.new(1,-16,0,60)
	footer.BackgroundColor3 = Color3.fromRGB(120,104,240); footer.ZIndex = 4; footer.Parent = premCard
	Instance.new("UICorner", footer).CornerRadius = UDim.new(0,16)
	local fg = Instance.new("UIGradient", footer); fg.Color = ColorSequence.new(Color3.fromRGB(150,108,244), Color3.fromRGB(96,68,202)); fg.Rotation = 90
	local ft = Instance.new("TextLabel")
	ft.BackgroundTransparency = 1; ft.Position = UDim2.fromOffset(22,0); ft.Size = UDim2.new(1,-92,1,0); ft.Font = Enum.Font.FredokaOne
	ft.TextScaled = true; ft.TextColor3 = Color3.new(1,1,1); ft.TextXAlignment = Enum.TextXAlignment.Left; ft.ZIndex = 5
	ft.Text = "\xE2\xAD\x90 Thanks for supporting Fart to Float!"; ft.Parent = footer
	local fts = Instance.new("UIStroke", ft); fts.Color = Color3.fromRGB(40,20,80); fts.Thickness = 2
	local ftc = Instance.new("UITextSizeConstraint", ft); ftc.MaxTextSize = 16
	local bean = Instance.new("ImageLabel") -- bean mascot (food-stand bean image), held still
	bean.AnchorPoint = Vector2.new(1,0.5); bean.Position = UDim2.new(1,-18,0.5,0); bean.Size = UDim2.fromOffset(54,54)
	bean.BackgroundTransparency = 1; bean.Image = BEAN_IMG; bean.ZIndex = 5; bean.Parent = footer
	for s = 1, 3 do -- subtle sparkles around the mascot -- twinkle in place, no movement
		local tw = Instance.new("TextLabel"); tw.BackgroundTransparency = 1; tw.Font = Enum.Font.GothamBold; tw.Text = "\xE2\x9C\xA6"
		tw.TextColor3 = Color3.fromRGB(255,240,190); tw.TextSize = 10 + s*2; tw.Size = UDim2.fromOffset(16,16); tw.ZIndex = 6
		tw.Position = UDim2.new(1, -54 - (s-1)*6, 0.5, (s==2 and -18 or 12)); tw.Parent = footer
		TS:Create(tw, TweenInfo.new(0.7 + s*0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.85 }):Play()
	end

	-- drifting background sparkles
	for i = 1, 10 do
		local sp = Instance.new("TextLabel")
		sp.BackgroundTransparency = 1; sp.Font = Enum.Font.GothamBold; sp.Text = "\xE2\x9C\xA6"; sp.TextColor3 = Color3.new(1,1,1); sp.TextTransparency = 0.72
		sp.TextSize = 12 + (i % 3) * 6; sp.Size = UDim2.fromOffset(22,22); sp.ZIndex = 0
		sp.Position = UDim2.fromScale(0.06 + (i * 0.09) % 0.88, 0.18 + (i * 0.13) % 0.66); sp.Parent = premCard
		TS:Create(sp, TweenInfo.new(2.6 + i * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.92 }):Play() -- twinkle in place, no drift
	end

	-- slide in from the bottom on open
	local shopGui = premPanel:FindFirstAncestorOfClass("ScreenGui")
	if shopGui then
		local home = premPanel.Position
		shopGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if shopGui.Enabled then
				premPanel.Position = home + UDim2.fromScale(0, 0.6)
				TS:Create(premPanel, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = home }):Play()
			end
		end)
	end
end)

-- ===== THE COIN SHOP IS GONE =====
-- A featured banner under the header used to open a full-card overlay selling six Robux coin packs
-- (1,000 up to 180,000 coins), and TokenHud's coin pill and its "+" opened it directly through
-- _G.openCoinShop. All of it is removed: the banner, the overlay, the six packs and the global.
--
-- What that changes elsewhere, and why nothing breaks:
--   * TokenHud reads `_G.openCoinShop or _G.togglePremiumShop`. With the first gone it falls through to
--     the second on its own -- the coin pill and its "+" now open the PREMIUM shop, which is a real page
--     that still exists. No dead button, no edit needed over there.
--   * ClickOutside lists CurrencyOverlay among the peelable overlays. A name that no longer exists costs
--     nothing there (it is a lookup, not an assertion), so that list is left alone.
--   * The product ids went with the packs. If they are ever wanted back, they are in git history along
--     with the layout -- but the server never had a ProcessReceipt branch granting these coins, so as
--     shipped the packs took Robux and gave nothing. That is the other half of why they are gone.
--
-- The gamepass list below now starts where the banner used to (see premScroll's Position/Size).

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
	foodPanel.Position = UDim2.new(0.5,0,0.5,-45) -- nudged UP ~45px so the panel's bottom clears the bottom-center stomach/gut indicator below it
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

-- ===== IN-SHOP GAS METER =====
-- The shop panel covers the HUD (DisplayOrder 100), so while you are choosing food you cannot see the
-- bottom-centre gas meter -- exactly when you most need to know how much room is left in the tank. This
-- is a READ-ONLY mirror of it, pinned to the panel's bottom strip beside the BUY buttons. It owns no
-- state: it re-derives fill + text from CurrentPower / StomachMax every frame the panel is open, the
-- same numbers CoreClient's updateMeter() uses, so it can never disagree with the HUD bar.
;(function()
	local RunService = game:GetService("RunService")

	-- Bottom strip: BUY (x 10..140) + BUY MAX (x 148..278) are already there, so the meter takes the rest.
	local gasTrack = mkFrame(foodPanel,{Name="ShopGasMeter",Size=UDim2.new(1,-298,0,48),Position=UDim2.new(0,288,1,-58),BackgroundColor3=Color3.fromRGB(20,20,60)})
	mkCorner(gasTrack,12); mkStroke(gasTrack,Color3.fromRGB(255,255,255),2)
	gasTrack.ClipsDescendants = true  -- the fill has its own 12px corner; clip so it can't poke out of the track
	local gasFill = mkFrame(gasTrack,{Name="Fill",Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.fromRGB(60,210,90),ZIndex=2})
	mkCorner(gasFill,12)
	local gasGrad = Instance.new("UIGradient")
	gasGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(130,240,120)),ColorSequenceKeypoint.new(1,Color3.fromRGB(45,190,70))})
	gasGrad.Rotation = 90; gasGrad.Parent = gasFill
	local gasText = mkLabel(gasTrack,{Name="GasText",Size=UDim2.new(1,-12,1,0),Position=UDim2.new(0,6,0,0),Text="GAS 0/0",Font=Enum.Font.FredokaOne,TextSize=20,TextColor3=Color3.fromRGB(255,255,255),ZIndex=3,TextXAlignment=Enum.TextXAlignment.Center})
	gasText.TextScaled = true
	mkStroke(gasText,Color3.fromRGB(0,0,0),2)
	local gtMax = Instance.new("UITextSizeConstraint"); gtMax.MaxTextSize = 22; gtMax.Parent = gasText

	local function refreshGas()
		-- Prefer CoreClient's live value (_G.cosmeticGas is written by updateMeter every time the real
		-- tank changes); fall back to the leaderstat if this script loaded first.
		local cur, max = 0, 0
		pcall(function() if _G.leaderstats then
			local cp=_G.leaderstats:FindFirstChild("CurrentPower"); if cp then cur=cp.Value end
			local sm=_G.leaderstats:FindFirstChild("StomachMax"); if sm then max=sm.Value end
		end end)
		if type(_G.cosmeticGas)=="number" then cur = _G.cosmeticGas end
		-- Clamped to the RAW StomachMax, byte for byte what CoreClient's updateMeter() does: with the 2x
		-- pass the real tank is deeper, and that extra fuel shows as flying higher, not as a bigger bar.
		local fill = (max > 0) and math.clamp(cur / max, 0, 1) or 0
		gasFill.Size = UDim2.new(fill,0,1,0)
		gasFill.Visible = fill > 0.001
		gasText.Text = ("GAS %d/%d"):format(math.floor(math.min(cur, max)), max)
	end
	refreshGas()
	RunService.RenderStepped:Connect(function()
		if FoodShopGui.Enabled then refreshGas() end  -- no work at all while the stand is closed
	end)
end)()

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY: shared manager (one instance across client scripts, via _G). Guarded
-- factory so whichever client script loads first creates it. Lets opening one main menu close the others. =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible)                                                -- hide/show the WHOLE bottom HUD (gut pill + gas meter + fart button all live in BottomStackGui)
		local lp = game:GetService("Players").LocalPlayer
		local pgx = lp and lp:FindFirstChildOfClass("PlayerGui")
		local g = pgx and pgx:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h = mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name
		mgr.setHud(false)                                                       -- a main menu is now open -> hide the bottom HUD (Shop/Pet Hub/Seasonal Pets all route through here)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end                         -- last menu closed -> restore the bottom HUD
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
-- the food-STAND menu fully hides here (also clears shopOpen so the proximity loop knows it's closed)
-- THE STAND HIDES THE BOTTOM HUD, like every other menu. It used to do the opposite: it re-enabled
-- BottomStackGui and pinned it to DisplayOrder 105 so it floated ABOVE the shop, on the reasoning that you
-- need the gut pill and the BUY FOOD button to use a food stand. But the stand IS the buy screen -- the bar
-- underneath was a second, smaller copy of what you were already looking at, and it needed a DisplayOrder
-- hack to sit on top of the thing it duplicated.
--
-- MainMenuManager.notifyOpened() already disables BottomStackGui, and CoreClient's HUD authority re-asserts
-- that 4x/sec. This exists so the bar goes on the SAME frame the shop opens rather than up to a quarter
-- second later, and to undo the DisplayOrder from any session that ran the old pinning build.
--
-- The stashed order is read off an ATTRIBUTE rather than a local, so the restore is still correct if the
-- stand closes by a path this function never saw -- a respawn, a teleport, another menu stealing focus.
local function standHudHide(on)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local g = pg and pg:FindFirstChild("BottomStackGui")
	if not g then return end
	if on then
		g.Enabled = false
	else
		local prev = g:GetAttribute("HudOrderBeforePin")   -- leftover from the old pin, if any
		if prev then
			g.DisplayOrder = prev
			g:SetAttribute("HudOrderBeforePin", nil)
		end
		g.Enabled = true
	end
end

-- Closing by ANY route -- another menu stealing focus, the X, a respawn -- must unpin too, or the HUD would
-- be left floating above whatever opened next.
_G.MainMenuManager.register("FoodShop", function() FoodShopGui.Enabled = false; shopOpen = false; standHudHide(false) end)

-- [UIFix] print the SHOP panel's REAL final layout + any size-controlling constraints (so the menus can copy them exactly),
-- then its RESOLVED on-screen size each time it opens (compare against the Pet Hub / Seasonal Pets prints).
print("[UIFix] SHOP size=" .. tostring(premPanel.Size) .. " pos=" .. tostring(premPanel.Position) .. " anchor=" .. tostring(premPanel.AnchorPoint))
for _, c in ipairs(premPanel:GetChildren()) do
	if c:IsA("UIScale") then print("[UIFix] SHOP UIScale=" .. tostring(c.Scale))
	elseif c:IsA("UISizeConstraint") then print("[UIFix] SHOP UISizeConstraint min=" .. tostring(c.MinSize) .. " max=" .. tostring(c.MaxSize))
	elseif c:IsA("UIAspectRatioConstraint") then print("[UIFix] SHOP UIAspectRatioConstraint ratio=" .. tostring(c.AspectRatio) .. " type=" .. tostring(c.AspectType)) end
end
PremiumShopGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if PremiumShopGui.Enabled then task.defer(function() print("[UIFix] SHOP AbsoluteSize=" .. tostring(premPanel.AbsoluteSize) .. " AbsolutePosition=" .. tostring(premPanel.AbsolutePosition)) end) end
end)
premClose.MouseButton1Click:Connect(function() if _G.playUIClick then _G.playUIClick() end; PremiumShopGui.Enabled=false; _G.MainMenuManager.notifyClosed("Premium") end)
foodCloseBtn.MouseButton1Click:Connect(function()
	FoodShopGui.Enabled = false
	shopOpen = false
	playerClosedShop = true
	_G.MainMenuManager.notifyClosed("FoodShop")
	task.delay(3, function() playerClosedShop = false end)
end)

-- ===== THE CRUNCH ONLY PLAYS WHEN YOU ACTUALLY ATE =====
-- This used to fire the moment the BUY button was clicked, BEFORE anything was checked. So you heard a big
-- satisfying chomp when you couldn't afford the food, when the food was locked, and -- worst of all -- when
-- your stomach was already full and the server threw the purchase away. A sound that says "yum" while the
-- meter doesn't move teaches players the meter is broken.
--
-- So the trigger moved off the button and onto the only thing that actually proves a bite happened: the
-- CurrentPower stat GOING UP. Nothing else in the game raises it -- flying drains it, and unlocking an island
-- or upgrading a gut RESETS it to zero (a decrease, so it stays silent). Every rejected purchase leaves it
-- untouched, and therefore silent, with no per-rejection special-casing to keep in sync with the server.
--
-- It also fixes BUY MAX for free: that fires one purchase per item and used to crunch once for the whole
-- batch regardless; now it crunches per bite, coalesced by the debounce below into one chomp per burst.
local function playEatSound()
	local sound=Instance.new("Sound"); sound.SoundId="rbxassetid://103794849233173"
	sound.Volume=0.8; sound.Parent=workspace; sound:Play()
	game:GetService("Debris"):AddItem(sound,3)
end

-- BUY MAX fires a dozen FireServer calls in a row and CurrentPower ticks up once per food. A dozen overlapping
-- copies of the same crunch is a mess, so collapse a burst into one.
local EAT_SOUND_GAP = 0.25
task.spawn(function()
	local cp
	repeat
		task.wait(0.5)
		cp = _G.leaderstats and _G.leaderstats:FindFirstChild("CurrentPower")
	until cp
	local last, lastAt = cp.Value, 0
	cp:GetPropertyChangedSignal("Value"):Connect(function()
		local now = cp.Value
		if now > last and os.clock() - lastAt >= EAT_SOUND_GAP then
			lastAt = os.clock()
			playEatSound()
		end
		last = now
	end)
	print("[Shop] crunch sound armed -- plays on CurrentPower RISING only (never on a refused purchase)")
end)

foodBuyBtn.MouseButton1Click:Connect(function()
	local f=featuredFood; if not f then return end          -- buy the CURRENTLY FEATURED food
	if not canBuy(f.island) then return end                  -- not reached this food's island yet
	-- (no playEatSound() here -- the crunch is driven by CurrentPower rising, so a refused buy stays silent)
	local coins=0
	pcall(function() if _G.leaderstats then local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end end end)
	if coins<f.price then
		foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text="Not Enough Coins"; foodBuyBtn.TextSize=14
		-- A refused buy used to be silent in the hand, which is why players press it again. `fail` is two
		-- flat low buzzes -- deliberately dull, so it never reads as a reward.
		if _G.hapticPulse then pcall(_G.hapticPulse, "fail") end
		task.delay(1,function() foodBuyBtn.BackgroundColor3=Color3.fromRGB(50,200,50); foodBuyBtn.Text="BUY FOOD"; foodBuyBtn.TextSize=17 end)
		return
	end
	pcall(function() _G.BuyFoodEvent:FireServer(f.name) end)
	print("FIRED BUYFOOD:", f.name)
	if _G.hapticPulse then pcall(_G.hapticPulse, "purchase") end
	local fl=Instance.new("TextLabel"); fl.Text="+"..f.power.." power!"; fl.Font=Enum.Font.GothamBold; fl.TextSize=20; fl.TextColor3=Color3.fromRGB(0,200,50); fl.BackgroundTransparency=1; fl.Size=UDim2.new(0,200,0,40); fl.Position=UDim2.new(0.3,0,0.6,0); fl.ZIndex=10; fl.Parent=FoodShopGui
	TweenService:Create(fl,TweenInfo.new(1.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(0.3,0,0.4,0),TextTransparency=1}):Play()
	task.delay(1.5,function() fl:Destroy() end)
end)

foodBuyMaxBtn.MouseButton1Click:Connect(function()
	-- (no playEatSound() here either -- BUY MAX often buys NOTHING, because the stomach is full or the coins
	-- don't stretch to a single item. It used to crunch anyway, before it had even worked out the quantity.)
	local feat=featuredFood; if not feat then return end     -- BUY MAX targets the FEATURED food
	if not canBuy(feat.island) then return end               -- not reached this food's island yet
	local coins, curPower, stomMax = 0, 0, 46
	pcall(function() if _G.leaderstats then
		local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end
		local cp=_G.leaderstats:FindFirstChild("CurrentPower"); if cp then curPower=cp.Value end
		local sm=_G.leaderstats:FindFirstChild("StomachMax"); if sm then stomMax=sm.Value end
	end end)
	-- FILL THE TANK AS FULL AS THE COINS ALLOW, MIXING FOODS. The old version bought as many of the featured
	-- food as fit and only then tried smaller ones into the leftover room -- and the leftover room is where it
	-- failed: six Cabbage in a 270 tank is 240, a seventh does not fit, and a Beans (32) does not fit in the
	-- 30 that is left, so BUY MAX stopped at 240 -- short of the ~263 a stretch crossing needs. Five Cabbage
	-- + two Beans is 264 and DOES fit. So this is a small knapsack over every unlocked food: the most power
	-- that fits in the room AND the wallet, and among equal-power fills the cheapest. Tanks are small
	-- (<= 2600) so the table is cheap.
	-- tankMax, not the raw StomachMax: the 2x pass doubles the tank AND doubles what each food is worth, so
	-- both sides of this sum have to use the same numbers the server does or the quantity comes out wrong.
	local remaining = tankMax(stomMax) - curPower
	local coinsLeft = coins
	local totalPower = 0
	local room = math.floor(remaining)
	if room > 0 then
		local menu = {}
		for i = feat.island, 1, -1 do
			local f = _G.foods[i]
			if f and canBuy(f.island) then table.insert(menu, f) end
		end
		local INF = math.huge
		local cost, from = table.create(room + 1, INF), table.create(room + 1, 0)
		cost[1] = 0 -- index p+1 holds power p
		for pwr = 1, room do
			for _, f in ipairs(menu) do
				local g = foodGain(f.power)
				if g <= pwr and cost[pwr - g + 1] + f.price < cost[pwr + 1] then
					cost[pwr + 1] = cost[pwr - g + 1] + f.price
					from[pwr + 1] = f
				end
			end
		end
		local best = 0
		for pwr = room, 1, -1 do
			if cost[pwr + 1] <= coins then best = pwr; break end
		end
		-- walk the choice back into purchases
		local pwr = best
		while pwr > 0 do
			local f = from[pwr + 1]
			pcall(function() _G.BuyFoodEvent:FireServer(f.name) end)
			local g = foodGain(f.power)
			remaining = remaining - g
			coinsLeft = coinsLeft - f.price
			totalPower = totalPower + g
			pwr = pwr - g
		end
	end
	if totalPower <= 0 then
		-- coins checked FIRST; then TRULY full (no room) vs HAS room but the cheapest food still won't fit
		local reason
		if coinsLeft < _G.foods[1].price then reason = "Not Enough Coins"
		elseif remaining <= 0 then reason = "Stomach Full"
		else reason = "Not Enough Room" end
		foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyMaxBtn.Text=reason; foodBuyMaxBtn.TextSize=13
		-- Same for BUY MAX, which refuses for three different reasons and was silent for all of them.
		if _G.hapticPulse then pcall(_G.hapticPulse, "fail") end
		task.delay(1,function() foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(255,140,0); foodBuyMaxBtn.Text="BUY MAX"; foodBuyMaxBtn.TextSize=15 end)
		return
	end
	print("BUY MAX: +"..totalPower.." power (coins left "..coinsLeft..", space left "..remaining..")")
	-- ONE pulse for the whole basket. BUY MAX fires BuyFoodEvent in a loop above; a pulse per item
	-- would be a solid buzz for the length of the purchase.
	if _G.hapticPulse then pcall(_G.hapticPulse, "purchase") end
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
			-- Clicking a grid food now FEATURES it in the big left display (instead of buying directly).
			-- Locked foods feature too (shown greyed + LOCKED). Buying happens via the big BUY / BUY MAX
			-- buttons, which target the featured food -- the purchase remote/server flow is unchanged.
			if _G.playUIClick then pcall(_G.playUIClick) end
			featuredFood = f
			updateFoodShop(nearIslandNumber)  -- re-render big display + re-highlight the grid (keeps featured)
		end)
	end
end

-- (Hotbar slot click handlers REMOVED with the hotbar. They were the OLD manual-use path that only
-- fired when the held count was > 0; since Mid-Air Recharge / Skip Island are now applied IMMEDIATELY
-- on purchase server-side, those counts stay 0 and these handlers never ran. The item effects are
-- driven by the server's ProcessReceipt -> triggerMidAirRecharge (client rechargeNow) / triggerSkipIsland.)

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

-- ===== FOOD-STAND PET-QUEST LOCK -- REMOVED =====
-- Quest islands (Broccoli Bluff 2, Coconut Cove 5, Popcorn 8, Butter Swamp 10, Burrito Barrens 13) used to
-- keep their stand shut until you owned that island's pet, enforced in THREE places: this one refused to open
-- the shop at all, isUnlocked() greyed the food cells, and PlayerStats.BuyFoodEvent refused the purchase.
-- All three are gone -- a half-removed gate is worse than the gate, because the cell looks buyable and the
-- server silently says no.
--
-- The pet quests themselves are untouched; they are simply optional now rather than a wall across the climb.

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
				-- EVERY STAND OPENS. The quest-island lock that used to sit here (walk up to Broccoli Bluff without the
				-- Broccoli Bunny and the shop simply refused to appear) is gone along with the other two stand gates.
				-- only auto-open if no OTHER main menu is open (proximity yields to a deliberately-opened menu)
				if not shopOpen and not playerClosedShop and not _G.MainMenuManager.isOtherOpen("FoodShop") then
					nearIslandNumber = foundIsland
					featuredFood = _G.foods[foundIsland]  -- big display defaults to the island's MAIN food on open
					updateFoodShop(foundIsland)
					_G.MainMenuManager.notifyOpened("FoodShop") -- becomes the one open main menu
					FoodShopGui.Enabled = true
					shopOpen = true
					standHudHide(true) -- shop open: the gas meter + BUY FOOD bar goes away
					print("SHOP OPEN ISLAND", foundIsland)
					if _G.hapticPulse then pcall(_G.hapticPulse, "tock") end
				end
			else
				if lastAwayTime == 0 then lastAwayTime = tick() end
				if tick() - lastAwayTime > 2 then playerClosedShop = false end
				if shopOpen then
					FoodShopGui.Enabled = false
					shopOpen = false
					standHudHide(false) -- walked away: the bar comes straight back
					_G.MainMenuManager.notifyClosed("FoodShop")
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
