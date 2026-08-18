--======================================================================
-- StomachShop_AllInOne.client.lua  (LocalScript)
--======================================================================
-- Builds the STOMACH (gut-tier) upgrade shop that the left-rail "Stomach"
-- button opens. JustButtons already toggles a GUI named "StomachShopGui" via
-- _G.MainMenuManager (register/notifyOpened/notifyClosed) -- this script just
-- BUILDS that GUI, so the button lights up automatically.
--
-- STRUCTURE (kept exactly so GutSkinClient can inject its "Skins" tab):
--   StomachShopGui (ScreenGui, .Enabled toggled, DisplayOrder 100)
--     Panel (Frame)                -- GutSkinClient adds Stomachs/Skins tabs here
--       CurrentLabel (TextLabel)   -- "Current: <tier>"
--       TierList     (ScrollingFrame) -- the gut-tier rows
--
-- ECONOMY (this place's convention, mirrored from Shop_AllInOne):
--   state  = _G.leaderstats -> Coins / StomachMax (IntValues, server-owned)
--   buy    = _G.BuyStomachEvent:FireServer(tierName)  (guarded; server validates
--            coins + applies the upgrade, same pattern as _G.BuyFoodEvent)
-- If _G.BuyStomachEvent isn't present the shop still opens + reads state; buys
-- just no-op (and log a warning) until the backend remote exists.
--======================================================================

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local player        = Players.LocalPlayer
local PlayerGui     = player:WaitForChild("PlayerGui")

-- ===== helpers (verbatim shared style) =====
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end
local function click() if _G.playUIClick then pcall(_G.playUIClick) end end

-- thousands separator: 40000 -> "40,000"
local function comma(n)
	local s = tostring(math.floor(n)); local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- ===== the gut tiers -- read from the SHARED module (ReplicatedStorage.Shared.
-- StomachTiers), the same table the server prices from, so panel and server can
-- never drift. 12 coin tiers (one per crossing) + the Robux Sugar Rush Gut.
-- unlockSlot = the climb slot you must have REACHED before the tier can be bought
-- (the server enforces it; this panel just draws the lock).
local StomachTiersShared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("StomachTiers"))
local TIERS = {}
for _, t in ipairs(StomachTiersShared.LIST) do
	TIERS[#TIERS+1] = { name=t.name, max=t.maxPower, cost=t.cost, robux=t.robux, emoji=t.emoji, unlockSlot=t.unlockSlot }
end

-- ===== THE ROBUX GUT IS A GAMEPASS (Infinite Gut, id in Shared.Gamepasses) =====
-- Sugar Rush Gut used to fire BuyStomachEvent like every other row -- and the server drops Robux tiers on the
-- floor ("Robux tiers are not bought through this event"), so the button did nothing at all. It is a GAMEPASS,
-- so it prompts Roblox instead, and ownership is what grants the tank: PassOwnership publishes HasInfiniteGut
-- and StomachUpgrade raises StomachMax off that attribute. Nothing here grants anything.
local Gamepasses = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Gamepasses"))
local GUT_PASS = "InfiniteGut"
local function gutPassLive()  return Gamepasses.isConfigured(GUT_PASS) end
local function gutPassOwned() return Gamepasses.owns(player, GUT_PASS) end
-- Price comes from the pass, not the tier row, so the card and the Robux prompt can never disagree.
local function gutPassPrice() return Gamepasses.PRICE[GUT_PASS] or 0 end

-- highest climb slot reached (server-set attribute; gates the locked rows)
local function highestSlot()
	return math.max(1, math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1))
end

-- ===== read server-owned state (this place stores it in _G.leaderstats) =====
local function getLeaderstats()
	return _G.leaderstats or player:FindFirstChild("leaderstats")
end
local function readVal(name, default)
	local ls = getLeaderstats()
	local v = ls and ls:FindFirstChild(name)
	return (v and v.Value) or default
end
local function getCoins()      return readVal("Coins", 0) end
local function getStomachMax() return readVal("StomachMax", TIERS[1].max) end

-- ============================================================================
-- GUI
-- ============================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "StomachShopGui"; gui.ResetOnSpawn = false; gui.Enabled = false; gui.DisplayOrder = 100; gui.Parent = PlayerGui

-- invisible backdrop: Active=false so a click outside falls through to the rail
-- buttons (click-to-switch between menus), matching PremiumShopGui.
local backdrop = mkFrame(gui, { Size=UDim2.new(1,0,1,0), BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=1, Active=false })

-- centered rounded panel (Active=true blocks pass-through behind it)
local panel = mkFrame(backdrop, {
	Name="Panel", AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,-45),
	Size=UDim2.new(0,700,0,520), BackgroundColor3=Color3.fromRGB(25,90,185), Active=true,
})
mkCorner(panel,20); mkStroke(panel,Color3.new(1,1,1),3)

-- header bar
local header = mkFrame(panel, { Size=UDim2.new(1,0,0,65), BackgroundColor3=Color3.fromRGB(15,60,140) })
mkCorner(header,20)
mkFrame(header, { Size=UDim2.new(1,0,0,20), Position=UDim2.new(0,0,1,-20), BackgroundColor3=Color3.fromRGB(15,60,140), BorderSizePixel=0 }) -- square off the bottom corners
local title = mkLabel(header, { Text="\xF0\x9F\x8D\xBD\xEF\xB8\x8F STOMACH UPGRADES", Font=Enum.Font.FredokaOne, TextSize=26, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,-60,0,40), Position=UDim2.new(0,20,0,8), TextXAlignment=Enum.TextXAlignment.Left })
mkStroke(title,Color3.new(0,0,0),2)

-- Current: <tier>  (GutSkinClient repositions this on open; name matters)
local currentLabel = mkLabel(panel, {
	Name="CurrentLabel", Text="Current: "..TIERS[1].name, Font=Enum.Font.GothamBold, TextSize=18,
	TextColor3=Color3.fromRGB(255,235,120), Size=UDim2.new(1,-40,0,26), Position=UDim2.new(0,20,0,72),
	TextXAlignment=Enum.TextXAlignment.Left,
})
mkStroke(currentLabel,Color3.new(0,0,0),2)

-- coins readout (top-right of the panel body)
local coinsLabel = mkLabel(panel, {
	Text="\xF0\x9F\xAA\x99 0", Font=Enum.Font.GothamBold, TextSize=18, TextColor3=Color3.fromRGB(255,215,0),
	Size=UDim2.new(0,220,0,26), Position=UDim2.new(1,-240,0,72), TextXAlignment=Enum.TextXAlignment.Right,
})
mkStroke(coinsLabel,Color3.new(0,0,0),2)

-- close button
local closeBtn = mkButton(header, { Size=UDim2.new(0,40,0,40), Position=UDim2.new(1,-52,0,12), BackgroundColor3=Color3.fromRGB(210,60,60), Text="\xE2\x9C\x95", Font=Enum.Font.GothamBold, TextSize=22, TextColor3=Color3.new(1,1,1) })
mkCorner(closeBtn,10); mkStroke(closeBtn,Color3.fromRGB(120,20,20),2)

-- tier list (GutSkinClient repositions this on open; name matters)
local tierList = Instance.new("ScrollingFrame")
tierList.Name = "TierList"; tierList.BackgroundTransparency = 1; tierList.BorderSizePixel = 0
tierList.Size = UDim2.new(1,-40,1,-120); tierList.Position = UDim2.new(0,20,0,108)
tierList.CanvasSize = UDim2.new(0,0,0,0); tierList.AutomaticCanvasSize = Enum.AutomaticSize.Y
tierList.ScrollBarThickness = 8; tierList.Parent = panel
do local l=Instance.new("UIListLayout"); l.Padding=UDim.new(0,10); l.SortOrder=Enum.SortOrder.LayoutOrder; l.Parent=tierList end

-- ============================================================================
-- ROWS -- one card per tier, rebuilt to reflect owned / current / buyable state
-- ============================================================================
local rows = {}          -- [tierName] = { buyBtn=, statusLabel= }

local function buildRows()
	for i, t in ipairs(TIERS) do
		local row = mkFrame(tierList, { Size=UDim2.new(1,-8,0,72), BackgroundColor3=Color3.fromRGB(35,110,210), LayoutOrder=i })
		mkCorner(row,14); mkStroke(row,Color3.fromRGB(15,60,140),2)

		mkLabel(row, { Text=t.emoji, Font=Enum.Font.GothamBold, TextScaled=true, Size=UDim2.new(0,48,0,48), Position=UDim2.new(0,12,0.5,0), AnchorPoint=Vector2.new(0,0.5) })
		local nameLbl = mkLabel(row, { Text=t.name, Font=Enum.Font.FredokaOne, TextSize=20, TextColor3=Color3.new(1,1,1), Size=UDim2.new(0,260,0,26), Position=UDim2.new(0,70,0,10), TextXAlignment=Enum.TextXAlignment.Left })
		mkStroke(nameLbl,Color3.new(0,0,0),2)
		mkLabel(row, { Text="Max power: "..comma(t.max), Font=Enum.Font.Gotham, TextSize=15, TextColor3=Color3.fromRGB(200,225,255), Size=UDim2.new(0,260,0,22), Position=UDim2.new(0,70,0,38), TextXAlignment=Enum.TextXAlignment.Left })

		local buyBtn = mkButton(row, { Size=UDim2.new(0,150,0,46), Position=UDim2.new(1,-162,0.5,0), AnchorPoint=Vector2.new(0,0.5), BackgroundColor3=Color3.fromRGB(50,200,50), Text="BUY", Font=Enum.Font.GothamBold, TextSize=17, TextColor3=Color3.new(1,1,1) })
		mkCorner(buyBtn,10); mkStroke(buyBtn,Color3.fromRGB(20,120,20),2)
		buyBtn.MouseButton1Click:Connect(function()
			click()
			if getStomachMax() >= t.max then return end -- already owned/current
			if t.robux then
				-- GAMEPASS, not a coin purchase. prompt() is guarded on an unset id, so a pass with no Robux
				-- product yet opens nothing rather than a broken prompt.
				if gutPassOwned() then return end
				if not gutPassLive() then
					local old = buyBtn.Text; buyBtn.Text = "Coming Soon"
					task.delay(1.2, function() buyBtn.Text = old end)
					return
				end
				Gamepasses.prompt(player, GUT_PASS)
				print("[StomachShop] prompted gamepass:", GUT_PASS, Gamepasses.IDS[GUT_PASS])
				return
			end
			if (t.unlockSlot or 1) > highestSlot() then -- (robux already returned above)
				local old = buyBtn.Text; buyBtn.Text = "Locked"; buyBtn.BackgroundColor3 = Color3.fromRGB(150,150,150)
				task.delay(1, function() buyBtn.Text = old end)
				return
			end
			local coins = getCoins()
			if coins < t.cost then
				local old = buyBtn.Text; buyBtn.Text = "Not Enough"; buyBtn.BackgroundColor3 = Color3.fromRGB(150,150,150)
				task.delay(1, function() buyBtn.Text = old end)
				return
			end
			if _G.BuyStomachEvent then
				pcall(function() _G.BuyStomachEvent:FireServer(t.name) end)
				print("[StomachShop] FIRED BuyStomach:", t.name)
			else
				warn("[StomachShop] _G.BuyStomachEvent missing -- buy no-op. (server backend not present)")
			end
		end)

		rows[t.name] = { buyBtn = buyBtn }
	end
end

-- refresh every row against current coins + StomachMax
local function refresh()
	local coins = getCoins()
	local smax  = getStomachMax()
	coinsLabel.Text = "\xF0\x9F\xAA\x99 "..comma(coins)

	-- current tier = highest tier whose max <= StomachMax
	local currentName = TIERS[1].name
	for _, t in ipairs(TIERS) do if smax >= t.max then currentName = t.name end end
	currentLabel.Text = "Current: "..currentName

	for _, t in ipairs(TIERS) do
		local r = rows[t.name]; if not r then continue end
		local btn = r.buyBtn
		if t.robux then
			-- OWNED is read off the pass attribute, NOT off StomachMax: the grant is asynchronous (PassOwnership
			-- does a web round trip on join), so between joining and the grant landing the card would otherwise
			-- offer a pass the player already paid for.
			if gutPassOwned() or smax >= t.max then
				btn.Active = false; btn.AutoButtonColor = false
				btn.BackgroundColor3 = Color3.fromRGB(90,90,90)
				btn.Text = (smax >= t.max) and "EQUIPPED" or "OWNED"
			elseif not gutPassLive() then
				btn.Active = false; btn.AutoButtonColor = false
				btn.BackgroundColor3 = Color3.fromRGB(120,120,120)
				btn.Text = "COMING SOON"
			else
				btn.Active = true; btn.AutoButtonColor = true
				btn.BackgroundColor3 = Color3.fromRGB(230,60,140)
				btn.Text = comma(gutPassPrice()).." R$"
			end
		elseif smax >= t.max then
			-- owned / current
			btn.Active = false; btn.AutoButtonColor = false
			btn.BackgroundColor3 = Color3.fromRGB(90,90,90)
			btn.Text = (t.name == currentName) and "EQUIPPED" or "OWNED"
		elseif (t.unlockSlot or 1) > highestSlot() then
			-- not reached this tier's island yet -- the wall stays drawn
			btn.Active = false; btn.AutoButtonColor = false
			btn.BackgroundColor3 = Color3.fromRGB(120,120,120)
			btn.Text = "\xF0\x9F\x94\x92 Island "..(t.unlockSlot or 1)
		else
			btn.Active = true; btn.AutoButtonColor = true
			local afford = coins >= t.cost
			btn.BackgroundColor3 = afford and Color3.fromRGB(50,200,50) or Color3.fromRGB(150,150,150)
			btn.Text = comma(t.cost)
		end
	end
end

buildRows()
refresh()

-- ============================================================================
-- WIRING -- close via MainMenuManager; live refresh on coins/stomach changes.
-- (JustButtons registers the "Stomach" hide fn + toggles this GUI's .Enabled.)
-- ============================================================================
closeBtn.MouseButton1Click:Connect(function()
	click(); gui.Enabled = false
	if _G.MainMenuManager then _G.MainMenuManager.notifyClosed("Stomach") end
end)

-- re-register a hide fn so the manager can force-close us when another menu opens
if _G.MainMenuManager then
	_G.MainMenuManager.register("Stomach", function() gui.Enabled = false end)
end

-- refresh whenever the shop opens, and live while it's open
gui:GetPropertyChangedSignal("Enabled"):Connect(function() if gui.Enabled then refresh() end end)
player:GetAttributeChangedSignal("HighestSlot"):Connect(function() if gui.Enabled then refresh() end end)
-- The gut pass lands as an attribute -- on join (a web round trip, so AFTER this panel is built) and again the
-- instant a purchase completes. Refresh UNCONDITIONALLY, not just while open: the buyer is looking at the panel
-- when the prompt closes, and a gated refresh would leave the card still saying "499 R$" until they reopen it.
do
	local attr = Gamepasses.ATTR[GUT_PASS]
	if attr then player:GetAttributeChangedSignal(attr):Connect(refresh) end
end
task.spawn(function()
	-- bind to leaderstats value changes once they exist
	local bound = false
	while not bound do
		local ls = getLeaderstats()
		if ls then
			for _, n in ipairs({ "Coins", "StomachMax" }) do
				local v = ls:FindFirstChild(n)
				if v then v.Changed:Connect(function() if gui.Enabled then refresh() end end) end
			end
			bound = true
		else
			task.wait(1)
		end
	end
end)

print("[StomachShop] ready -- gut-tier upgrade shop built (opens from the Stomach rail button)")
