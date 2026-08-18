--======================================================================
-- PetHub_AllInOne.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of the WHOLE pets feature from the main game, lifted
-- VERBATIM from PetFollow.client.lua + CoreClient.client.lua:
--
--   1. PET HUB TOGGLE-- opened via the PetInvToggle BindableEvent / _G.togglePetHub
--                       (fired by the More+ menu / PETS entry / server).
--   2. PET HUB       -- the 700x520 blue panel: header with the "X / Y pets
--                       unlocked" readout + gold TOKEN chip, and a grid of
--                       OWNED pet cards with 3D auto-rotating viewport icons,
--                       name, rarity tier, level, XP bar, next-milestone hint,
--                       EQUIP + tier-SKIP.
--   3. NAV BAR       -- the CURRENT four-tab bar under the header, verbatim
--                       from the main game: PETS / CRATES / TRADE / QUESTS.
--                       One page at a time via the _G.PetHub.showPage router
--                       (selected tab = dark-on-gold, others gold-on-blue).
--                       CRATES hands off to the crate panel (guarded).
--   4. QUESTS PAGE   -- the discovered-quests overlay (island / status / how-to).
--   5. TRADE PAGE    -- full trade UI: pick a player -> request -> trade window
--                       (your offer / their offer / add list / confirm+cancel)
--                       + the incoming-request ACCEPT/DECLINE popup.
--
-- It talks to the SAME server remotes (PetEquipEvent, PetInventoryEvent,
-- PetTrade*Event, ...) but every remote lookup is GUARDED -- if the server
-- isn't present the UI still builds and a built-in DEMO inventory is shown so
-- you can see exactly how it looks. The moment the real remotes exist + the
-- server fires PetInventoryEvent / PetTradeStateEvent, live data takes over.
--
-- The 3D card icons reuse the real low-poly pet builders (Coconut Crab /
-- Popcorn Sheep / Butter Duck / Broccoli) instead of the heavy server Union +
-- accessory pipeline, so it renders standalone. Drop into StarterPlayer >
-- StarterPlayerScripts (or sync via Rojo) and it runs.
--======================================================================

local Players           = game:GetService("Players")
local RS                = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local MarketplaceService= game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local pg     = player:WaitForChild("PlayerGui")

-- ============================================================================
-- REMOTES -- looked up if they exist (no WaitForChild block); nil-safe so the
-- whole file runs standalone. Live data flows in automatically once present.
-- ============================================================================
-- The PERMANENT rarity axis (Common..Gold) and the fusion cost ladder. Separate from the pet's AGE tier,
-- which petTier() derives from level -- a pet's rarity never moves, its age always does.
local PetRarity = require(RS:WaitForChild("Shared"):WaitForChild("PetRarity"))

local function remote(name) return RS:FindFirstChild(name) end
local PetEquipEvent      = remote("PetEquipEvent")
local PetFuseEvent       = remote("PetFuseEvent") -- c->s: (storageKey) burn N duplicates -> next rarity
local PetInventoryEvent  = remote("PetInventoryEvent")
local PetPendingUpgrade  = remote("PetPendingUpgradeEvent")
local PetProgressEvent   = remote("PetProgressEvent")
-- STAGE 3 TRADE remotes (client sends intents only)
local PetTradeRequest = remote("PetTradeRequestEvent")
local PetTradeRespond = remote("PetTradeRespondEvent")
local PetTradeOffer   = remote("PetTradeOfferEvent")
local PetTradeConfirm = remote("PetTradeConfirmEvent")
local PetTradeCancel  = remote("PetTradeCancelEvent")
local PetTradeState   = remote("PetTradeStateEvent")
local PetTradePrompt  = remote("PetTradeRequestPromptEvent")

-- ⚠ REPLACE BEFORE LAUNCH: placeholder TIER-SKIP Developer Product IDs (must match PET_SKIP_PRODUCTS in
-- PetSystem.server.lua -- these are the EXACT ids/prices/names the main game uses today). Each jumps the
-- pet to the FIRST level of the next AGE. (Ordered 1=Baby->Kid ... 4=Adult->Elder.)
local PET_SKIP_PRODUCTS = {
	{ to = "Kid",   price = 49,  id = 123456701 }, -- ⚠ placeholder product id -- REPLACE BEFORE LAUNCH
	{ to = "Teen",  price = 99,  id = 123456702 }, -- ⚠ REPLACE BEFORE LAUNCH
	{ to = "Adult", price = 299, id = 123456703 }, -- ⚠ REPLACE BEFORE LAUNCH
	{ to = "Elder", price = 599, id = 123456704 }, -- ⚠ REPLACE BEFORE LAUNCH
}

-- ============================================================================
-- RARITY TIER LABELS (VERBATIM from PetFollow.client.lua)
-- ============================================================================
local function petTier(level, isRare, petId)
	if isRare then
		if petId == "ButterDuck" then return "Mythical", Color3.fromRGB(255,70,230), true, true  -- top tier, flashiest (magenta glow)
		else return "Exotic", Color3.fromRGB(40,235,225), true, true end                          -- above everything (bright cyan/teal glow)
	end
	if level <= 5      then return "Baby",  Color3.fromRGB(175,180,190), false, false
	elseif level <= 10 then return "Kid",   Color3.fromRGB(90,210,90),   false, false
	elseif level <= 15 then return "Teen",  Color3.fromRGB(255, 70, 171),  false, false
	elseif level <= 20 then return "Adult", Color3.fromRGB(180,90,235),  false, false
	else                    return "Elder", Color3.fromRGB(255,170,40),  false, false end
end
local PET_DISPLAY = { BeanBuddy="Bean Buddy", PizzaDragon="Pizza Dragon", BroccoliPet="Broccoli Bunny", CoconutCrab="Coconut Crab", PopcornSheep="Popcorn Sheep", ButterDuck="Butter Duck", BurritoArmadillo="Burrito Armadillo",
	SunflowerBee="Sunflower Bee", MapleFox="Maple Fox", FrostPenguin="Frost Penguin", BlossomBunny="Blossom Bunny" }

-- ============================================================================
-- PET MODEL BUILDERS (for the 3D viewport icons) -- copied from PetFollow.
-- Replaces the heavy server-Union + accessory pipeline with the real low-poly
-- bodies so the cards render standalone. +X = front.
-- ============================================================================
local petAnims = setmetatable({}, { __mode = "k" }) -- builders write a temp entry here; icons are static so it's unused
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape
	p.Size = size; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end

local function buildCoconutCrab(scale)
	local s = scale or 1; local model = Instance.new("Model"); model.Name = "CoconutCrab"; local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z) local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s)); parts[#parts+1]={part=p}; return p end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0)); root.Transparency = 1; model.PrimaryPart = root
	local BROWN, DARK, CLAW = Color3.fromRGB(112,72,42), Color3.fromRGB(66,40,22), Color3.fromRGB(150,72,46)
	mk("Body", Enum.PartType.Ball, 2.1,1.8,2.1, BROWN, 0,0,0)
	mk("Spot", Enum.PartType.Ball, 0.34,0.34,0.22, DARK, 0.95,0.15,0); mk("Spot", Enum.PartType.Ball, 0.3,0.3,0.2, DARK, 0.9,-0.35,-0.4); mk("Spot", Enum.PartType.Ball, 0.3,0.3,0.2, DARK, 0.9,-0.35,0.4)
	for _, ez in ipairs({-0.45, 0.45}) do mk("Eye", Enum.PartType.Ball, 0.42,0.42,0.42, Color3.fromRGB(245,245,245), 0.55,1.0,ez); mk("Pupil", Enum.PartType.Ball, 0.22,0.22,0.22, Color3.fromRGB(18,18,18), 0.78,1.02,ez) end
	for _, cs in ipairs({-1, 1}) do mk("Claw", Enum.PartType.Ball, 0.78,0.66,0.6, CLAW, 0.7,-0.15,cs*1.2); mk("ClawTip", Enum.PartType.Ball, 0.46,0.34,0.34, CLAW, 1.05,-0.05,cs*1.45) end
	for _, ls in ipairs({-1, 1}) do for i = 1, 3 do mk("Leg", Enum.PartType.Ball, 0.26,0.62,0.26, DARK, -0.5+(i-1)*0.5, -0.9, ls*0.95) end end
	petAnims[model] = { s = s, parts = parts }; return model
end
local function buildPopcornSheep(scale)
	local s = scale or 1; local model = Instance.new("Model"); model.Name = "PopcornSheep"; local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z) local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s)); parts[#parts+1]={part=p}; return p end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0)); root.Transparency = 1; model.PrimaryPart = root
	local WOOL, FACE, LEG, DARK = Color3.fromRGB(252,248,228), Color3.fromRGB(58,46,40), Color3.fromRGB(70,56,46), Color3.fromRGB(24,24,24)
	mk("Body", Enum.PartType.Ball, 2.4,2.0,2.2, WOOL, 0,0,0)
	for _, b in ipairs({ {0.8,0.9,0.6},{0.6,1.0,-0.6},{-0.2,1.15,0.0},{-0.9,0.85,0.5},{-0.9,0.7,-0.5},{0.15,0.55,1.0},{0.15,0.5,-1.0},{-0.5,0.2,0.98},{-0.5,0.1,-0.98},{0.7,0.0,0.92},{0.7,-0.1,-0.92},{-1.05,0.05,0.0} }) do local r = 0.72 + math.abs(b[2])*0.04; mk("Wool", Enum.PartType.Ball, r,r,r, WOOL, b[1],b[2],b[3]) end
	mk("Head", Enum.PartType.Ball, 1.0,1.05,0.95, FACE, 1.25,0.35,0); mk("Tuft", Enum.PartType.Ball, 0.78,0.7,0.78, WOOL, 1.12,1.05,0)
	mk("Ear", Enum.PartType.Ball, 0.3,0.52,0.22, FACE, 1.0,0.7,0.62); mk("Ear", Enum.PartType.Ball, 0.3,0.52,0.22, FACE, 1.0,0.7,-0.62)
	for _, ez in ipairs({0.32, -0.32}) do mk("Eye", Enum.PartType.Ball, 0.3,0.38,0.26, Color3.fromRGB(245,245,245), 1.74,0.45,ez); mk("Pupil", Enum.PartType.Ball, 0.16,0.2,0.16, DARK, 1.9,0.42,ez) end
	mk("Snout", Enum.PartType.Ball, 0.52,0.4,0.56, Color3.fromRGB(80,66,56), 1.78,0.06,0)
	for _, lp in ipairs({ {0.8,0.7},{0.8,-0.7},{-0.7,0.7},{-0.7,-0.7} }) do mk("Leg", Enum.PartType.Ball, 0.42,1.0,0.42, LEG, lp[1],-1.4,lp[2]) end
	mk("Tail", Enum.PartType.Ball, 0.55,0.55,0.55, WOOL, -1.3,0.3,0)
	petAnims[model] = { s = s, parts = parts }; return model
end
local function buildButterDuck(scale)
	local s = scale or 1; local model = Instance.new("Model"); model.Name = "ButterDuck"; local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z) local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s)); parts[#parts+1]={part=p}; return p end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0)); root.Transparency = 1; model.PrimaryPart = root
	local BUTTER, DEEP, BILL, DARK = Color3.fromRGB(248,214,96), Color3.fromRGB(232,188,70), Color3.fromRGB(244,150,40), Color3.fromRGB(28,24,18)
	mk("Body", Enum.PartType.Ball, 2.5,2.0,2.1, BUTTER, 0,0,0); mk("Rump", Enum.PartType.Ball, 1.1,1.0,1.0, BUTTER, -1.25,0.35,0); mk("TailTip", Enum.PartType.Ball, 0.5,0.5,0.7, DEEP, -1.85,0.6,0)
	mk("Neck", Enum.PartType.Ball, 0.95,1.2,0.95, BUTTER, 1.05,0.85,0); mk("Head", Enum.PartType.Ball, 1.15,1.15,1.1, BUTTER, 1.5,1.6,0)
	mk("Bill", Enum.PartType.Ball, 0.95,0.35,0.8, BILL, 2.2,1.45,0); mk("BillTip", Enum.PartType.Ball, 0.55,0.28,0.66, BILL, 2.55,1.4,0)
	for _, ez in ipairs({0.42, -0.42}) do mk("Eye", Enum.PartType.Ball, 0.34,0.4,0.3, Color3.fromRGB(245,245,245), 1.92,1.78,ez); mk("Pupil", Enum.PartType.Ball, 0.18,0.22,0.18, DARK, 2.1,1.76,ez) end
	for _, ws in ipairs({1, -1}) do mk("Wing", Enum.PartType.Ball, 1.3,0.7,0.5, DEEP, -0.1,0.2,ws*1.15) end
	for _, ls in ipairs({0.55, -0.55}) do mk("Leg", Enum.PartType.Ball, 0.4,0.7,0.5, BILL, 0.2,-1.35,ls) end
	for _, e in ipairs(parts) do if e.part.Transparency < 1 then e.part.Reflectance = 0.08 end end
	petAnims[model] = { s = s, parts = parts }; return model
end
-- a simple broccoli "bunny" stand-in for BroccoliPet + the generic fallback icon
local function buildBroccoliBlob(scale)
	local model = Instance.new("Model"); model.Name = "BroccoliBlob"; local s = scale or 1
	local stalk = newPart(model, "Root", Enum.PartType.Block, Vector3.new(0.85*s, 1.3*s, 0.85*s), Color3.fromRGB(175, 200, 140), CFrame.new(0,0,0)); model.PrimaryPart = stalk
	local crownC = Color3.fromRGB(60, 160, 60)
	newPart(model, "Floret0", Enum.PartType.Ball, Vector3.new(1.5*s,1.5*s,1.5*s), crownC, CFrame.new(0, 1.1*s, 0))
	for i = 1, 5 do local a = (i-1) * (2*math.pi/5); newPart(model, "Floret"..i, Enum.PartType.Ball, Vector3.new(1.05*s,1.05*s,1.05*s), crownC, CFrame.new(math.cos(a)*0.85*s, 0.95*s, math.sin(a)*0.85*s)) end
	for _, sx in ipairs({-0.35, 0.35}) do
		newPart(model, "Eye", Enum.PartType.Ball, Vector3.new(0.42*s,0.42*s,0.42*s), Color3.fromRGB(255,255,255), CFrame.new(sx*s, 1.15*s, 0.62*s))
		newPart(model, "Pupil", Enum.PartType.Ball, Vector3.new(0.22*s,0.22*s,0.22*s), Color3.fromRGB(20,20,20), CFrame.new(sx*s, 1.15*s, 0.78*s))
	end
	petAnims[model] = { s = s, parts = {} }; return model
end
local PET_ICON_BUILDER = {
	CoconutCrab = buildCoconutCrab, PopcornSheep = buildPopcornSheep, ButterDuck = buildButterDuck,
	BroccoliPet = buildBroccoliBlob, BurritoArmadillo = buildBroccoliBlob, -- (armadillo builder omitted; broccoli stand-in)
}

-- ============================================================================
-- PET HUB PANEL -- VERBATIM from PetFollow.client.lua (Pet Hub region).
-- ============================================================================
local invGui = Instance.new("ScreenGui")
invGui.Name = "PetInventoryUI"; invGui.ResetOnSpawn = false; invGui.DisplayOrder = 100
-- HANDS OFF THE TEXT. Every label in this hub is authored with a deliberate TextSize -- 18pt
-- headings, 12pt captions -- and a blanket TextScaled sweep throws that away. NoTextSweep is
-- the sweep's own documented opt-out (same attribute the main game's hub sets).
invGui:SetAttribute("NoTextSweep", true)
invGui.Parent = pg
local function uicorner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function uistroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 2; s.Parent = o; return s end

local dim = Instance.new("Frame"); dim.Name = "Dim"; dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0)
dim.BackgroundTransparency = 1; dim.Visible = false; dim.Active = false; dim.Parent = invGui

local panel = Instance.new("Frame"); panel.Name = "Panel"
panel.Size = UDim2.new(0,700,0,520); panel.Position = UDim2.new(0.5,0,0.5,-45); panel.AnchorPoint = Vector2.new(0.5,0.5)
panel.BackgroundColor3 = Color3.fromRGB(185, 25, 117); panel.ClipsDescendants = true; panel.Visible = false; panel.Active = true; panel.Parent = invGui
uicorner(panel, 18); uistroke(panel, Color3.new(1,1,1), 3)

-- HEADER
local header = Instance.new("Frame"); header.Size = UDim2.new(1,0,0,60); header.BackgroundColor3 = Color3.fromRGB(140, 15, 81); header.Parent = panel
uicorner(header, 18)
local title = Instance.new("TextLabel"); title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBold; title.TextSize = 26
title.TextColor3 = Color3.fromRGB(255,215,0); title.Text = "\xF0\x9F\x90\xBE PET HUB"; title.TextXAlignment = Enum.TextXAlignment.Left
title.Size = UDim2.new(1,-60,0,34); title.Position = UDim2.new(0,14,0,5); title.Parent = header
uistroke(title, Color3.new(0,0,0), 2)
local subtitle = Instance.new("TextLabel"); subtitle.BackgroundTransparency = 1; subtitle.Font = Enum.Font.Gotham; subtitle.TextSize = 13
-- The subtitle is the PETS-UNLOCKED progress readout. Every page in the hub shows the same
-- header, so this and the token chip beside it are the two numbers always on screen.
subtitle.TextColor3 = Color3.new(1,1,1); subtitle.Text = "0 / 0 pets unlocked"; subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Size = UDim2.new(0,300,0,16); subtitle.Position = UDim2.new(0,14,0,40); subtitle.Parent = header
subtitle.Name = "HubProgress"

-- TOKEN COUNTER, sat left of the close button. Same chip treatment the crate panel uses for
-- its own token readout, so the two panels read as one interface when you tab between them.
do
	local tokChip = Instance.new("Frame"); tokChip.Name = "HubTokens"
	tokChip.Size = UDim2.new(0,126,0,28); tokChip.Position = UDim2.new(1,-182,0,16)
	tokChip.BackgroundColor3 = Color3.fromRGB(104, 12, 59); tokChip.Parent = header
	uicorner(tokChip, 8); uistroke(tokChip, Color3.fromRGB(255,215,0), 1.5)
	local tl = Instance.new("TextLabel"); tl.Name = "Value"; tl.BackgroundTransparency = 1
	tl.Size = UDim2.new(1,-10,1,0); tl.Position = UDim2.new(0,5,0,0)
	tl.Font = Enum.Font.GothamBold; tl.TextSize = 14; tl.TextColor3 = Color3.fromRGB(255,215,0)
	tl.Text = "\xF0\x9F\xAA\x99 0"; tl.Parent = tokChip
	-- cap the size so a long balance can't grow even if a TextScaled sweep touches it
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 14; c.Parent = tl; tl.TextScaled = true end
end
local closeBtn = Instance.new("TextButton"); closeBtn.Size = UDim2.new(0,40,0,40); closeBtn.Position = UDim2.new(1,-48,0,10)
closeBtn.BackgroundColor3 = Color3.fromRGB(220,50,50); closeBtn.Text = "X"; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.new(1,1,1); closeBtn.Parent = header
uicorner(closeBtn, 8); uistroke(closeBtn, Color3.new(0,0,0), 2)

-- ===== NAVIGATION: the pages of the hub (VERBATIM from the main game) =====
-- One horizontal bar directly under the header (bar at y=66, 38 tall). FOUR tabs: pets and
-- crates are ONE hub, entered through the PETS door. CRATES hands off to the crate panel via
-- showPage. 163 wide: four tabs + three 8px gaps fill 676px.
_G.PetHub = _G.PetHub or {}
do
	_G.PetHub.navButtons = {}
	-- Pages built by OTHER scripts, keyed by tab id -> setVisible(bool). CrossRealmPets registers
	-- "food" and "dino" here. Declared before the bar is built so a page script that loads first
	-- can register without racing this block.
	_G.PetHub.extraPages = _G.PetHub.extraPages or {}
	_G.PetHub.registerPage = function(id, setVisible)
		if type(id) == "string" and type(setVisible) == "function" then
			_G.PetHub.extraPages[id] = setVisible
		end
	end
	-- Where a registered page should parent itself, and the geometry it should match. Handing these
	-- out means the page scripts never hard-code the panel's name or its content band -- if the hub
	-- is re-laid-out, they follow it instead of silently sitting in the wrong place.
	_G.PetHub.panel = panel
	_G.PetHub.contentInset = { x = 10, y = 108, w = -20, h = -118 } -- below the 66+38 nav bar
	-- HEADER READOUTS, defined HERE and not down with the router: the pet grid calls
	-- setProgress while the script is still LOADING, long before the router block runs.
	_G.PetHub.setProgress = function(owned, total)
		local lbl = header:FindFirstChild("HubProgress")
		if lbl then lbl.Text = tostring(owned) .. " / " .. tostring(total) .. " pets unlocked" end
	end
	_G.PetHub.setTokens = function(n)
		local chip = header:FindFirstChild("HubTokens")
		local lbl = chip and chip:FindFirstChild("Value")
		if lbl then lbl.Text = "\xF0\x9F\xAA\x99 " .. tostring(math.floor(tonumber(n) or 0)) end
	end
	-- the crate panel calls this whenever the server pushes a new balance, so the hub header
	-- and the crate panel can never show two different token counts.
	_G.petHubTokensChanged = function(n) pcall(_G.PetHub.setTokens, n) end
	local bar = Instance.new("Frame"); bar.Name = "HubNav"
	bar.Size = UDim2.new(1,-20,0,38); bar.Position = UDim2.new(0,10,0,66)
	bar.BackgroundTransparency = 1; bar.Parent = panel
	local ll = Instance.new("UIListLayout"); ll.FillDirection = Enum.FillDirection.Horizontal
	ll.Padding = UDim.new(0,8); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = bar
	-- FIVE tabs: TWO pets tabs (Dino first, Food second -- both realm collections, rendered read-only
	-- by CrossRealmPets.client.luau from the pets your teleport carried in) plus crates/trade/quests.
	--
	-- THE OLD 🐾 CANDY PETS TAB IS GONE, on purpose. Candy has no pet server of its own -- that tab
	-- only ever showed the hub's hard-coded DEMO inventory ("[PetHub] no server remotes found ->
	-- showing DEMO inventory" on every boot), which is a page of fake pets pretending to be owned.
	-- Two real collections beat one real page and one lie. If Candy ever grows its own pets, put the
	-- tab back and re-run the width maths below.
	--
	-- WIDTH: (676 - 4 gaps x 8) / 5 = 128.8 -> 128. Change the tab count, change this, or the row
	-- stops filling the panel.
	for i, t in ipairs({
		-- NAMED BY REALM, not three tabs all reading "PETS". Told apart only by a small emoji they were a
		-- coin-flip for anyone not looking closely; the word does the work now and the emoji just decorates.
		{ id = "dino",   label = "\xF0\x9F\xA6\x95 DINO"   }, -- 🦕 Dino Realm collection  -- FIRST pets tab
		{ id = "food",   label = "\xF0\x9F\x8D\x94 FOOD"   }, -- 🍔 first-realm (Food) collection -- SECOND
		{ id = "crates", label = "\xF0\x9F\x93\xA6 CRATES" },
		{ id = "trade",  label = "\xF0\x9F\x94\x84 TRADE"  },
		{ id = "quests", label = "\xF0\x9F\x93\x9C QUESTS" },
	}) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0,128,1,0); b.LayoutOrder = i
		b.BackgroundColor3 = Color3.fromRGB(150, 18, 88); b.Text = t.label
		b.Font = Enum.Font.FredokaOne; b.TextSize = 15; b.TextScaled = true
		-- ⚠ ONE LINE, ALWAYS. TextWrapped defaults TRUE, so "🦕 PETS" breaks after the emoji and both lines
		-- are drawn into a 38px-tall button -- which reads as the glyphs colliding, not as a wrap. Off,
		-- TextScaled shrinks the FONT to fit the width instead, which is what should happen.
		b.TextWrapped = false
		b.TextColor3 = Color3.fromRGB(255,215,0); b.Parent = bar
		uicorner(b, 10); uistroke(b, Color3.new(1,1,1), 1.5)
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = b end
		_G.PetHub.navButtons[t.id] = b
		-- showPage is defined further down (it needs the trade + quest overlays to exist
		-- first). Looked up at CLICK time, not now, so the ordering is fine.
		b.MouseButton1Click:Connect(function()
			if _G.playUIClick then pcall(_G.playUIClick) end
			if _G.PetHub.showPage then _G.PetHub.showPage(t.id) end
		end)
	end
end

-- PETS section (fills the panel width: 2 big cards/row)
local function makeSection(x, w, titleText)
	local sec = Instance.new("Frame"); sec.Size = UDim2.new(0,w,1,-74); sec.Position = UDim2.new(0,x,0,68)
	sec.BackgroundColor3 = Color3.fromRGB(150, 18, 88); sec.BackgroundTransparency = 0.25; sec.Parent = panel
	uicorner(sec, 12); uistroke(sec, Color3.fromRGB(100, 10, 55), 2)
	local t = Instance.new("TextLabel"); t.Size = UDim2.new(1,-12,0,22); t.Position = UDim2.new(0,8,0,6)
	t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold; t.TextSize = 16; t.TextColor3 = Color3.fromRGB(255,215,0)
	t.TextXAlignment = Enum.TextXAlignment.Left; t.Text = titleText; t.Parent = sec
	local sc = Instance.new("ScrollingFrame"); sc.Size = UDim2.new(1,-12,1,-34); sc.Position = UDim2.new(0,6,0,30)
	sc.BackgroundTransparency = 1; sc.BorderSizePixel = 0; sc.ScrollBarThickness = 6; sc.ScrollBarImageColor3 = Color3.fromRGB(255,215,0)
	sc.CanvasSize = UDim2.new(0,0,0,0); sc.Parent = sec
	return sec, sc
end
local petsSection, petsScroll = makeSection(12, 676, "\xF0\x9F\x90\xBe PETS")
-- y=110, not 68: the nav bar owns 66..104 directly under the header.
petsSection.Size = UDim2.new(1, -24, 1, -116); petsSection.Position = UDim2.new(0, 12, 0, 110)
-- PERMANENTLY HIDDEN along with its tab: this grid only ever showed the DEMO inventory (Candy has no pet
-- server), and its tab is gone -- the Dino and Food collection pages own the content band now. The section
-- is built rather than deleted because the grid-refresh code below still writes into petsScroll; writing
-- into an invisible frame is free, deleting it would mean touching every one of those call sites.
petsSection.Visible = false
local petsGrid = Instance.new("UIGridLayout"); petsGrid.CellSize = UDim2.new(0,322,0,252); petsGrid.CellPadding = UDim2.new(0,10,0,12)
petsGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center; petsGrid.Parent = petsScroll
do
	local pad = Instance.new("UIPadding"); pad.Name = "PetsTopPad"
	pad.PaddingTop = UDim.new(0,10); pad.PaddingLeft = UDim.new(0,4); pad.PaddingRight = UDim.new(0,4)
	pad.Parent = petsScroll
end

-- QUESTS overlay
local questsOverlay = Instance.new("Frame"); questsOverlay.Name = "QuestsOverlay"; questsOverlay.Size = UDim2.new(1,-24,1,-116); questsOverlay.Position = UDim2.new(0,12,0,110)
questsOverlay.BackgroundColor3 = Color3.fromRGB(140, 16, 81); questsOverlay.Visible = false; questsOverlay.Parent = panel; uicorner(questsOverlay, 12); uistroke(questsOverlay, Color3.fromRGB(100, 10, 55), 2)
local qoTitle = Instance.new("TextLabel"); qoTitle.Size = UDim2.new(1,-120,0,28); qoTitle.Position = UDim2.new(0,12,0,8); qoTitle.BackgroundTransparency = 1
qoTitle.Font = Enum.Font.GothamBold; qoTitle.TextSize = 18; qoTitle.TextColor3 = Color3.fromRGB(255,215,0); qoTitle.TextXAlignment = Enum.TextXAlignment.Left; qoTitle.Text = "\xF0\x9F\x97\xBA Pet Quests"; qoTitle.Parent = questsOverlay
local qoBack = Instance.new("TextButton"); qoBack.Size = UDim2.new(0,100,0,28); qoBack.Position = UDim2.new(1,-108,0,8); qoBack.BackgroundColor3 = Color3.fromRGB(120,120,120)
qoBack.Font = Enum.Font.GothamBold; qoBack.TextSize = 13; qoBack.TextColor3 = Color3.new(1,1,1); qoBack.Text = "\xE2\x97\x80 Pets"; qoBack.Parent = questsOverlay; uicorner(qoBack, 8)
local questsScroll = Instance.new("ScrollingFrame"); questsScroll.Size = UDim2.new(1,-16,1,-46); questsScroll.Position = UDim2.new(0,8,0,42); questsScroll.BackgroundTransparency = 1; questsScroll.BorderSizePixel = 0
questsScroll.ScrollBarThickness = 6; questsScroll.ScrollBarImageColor3 = Color3.fromRGB(255,215,0); questsScroll.CanvasSize = UDim2.new(0,0,0,0); questsScroll.Parent = questsOverlay
local questsList = Instance.new("UIListLayout"); questsList.Padding = UDim.new(0,8); questsList.SortOrder = Enum.SortOrder.LayoutOrder; questsList.Parent = questsScroll
local questsEmpty = Instance.new("TextLabel"); questsEmpty.Size = UDim2.new(1,-24,0,70); questsEmpty.Position = UDim2.new(0,12,0,46)
questsEmpty.BackgroundTransparency = 1; questsEmpty.Font = Enum.Font.Gotham; questsEmpty.TextSize = 14; questsEmpty.TextWrapped = true
questsEmpty.TextColor3 = Color3.fromRGB(255, 200, 229); questsEmpty.Text = "Land on islands to discover pet quests!"; questsEmpty.Visible = false; questsEmpty.Parent = questsOverlay

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY (shared manager via _G) =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible)
		local lp = Players.LocalPlayer
		local pgx = lp and lp:FindFirstChildOfClass("PlayerGui")
		local g = pgx and pgx:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h = mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name; mgr.setHud(false)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
_G.MainMenuManager.register("PetInv", function() panel.Visible = false; dim.Visible = false end)

local latestInv = { owned = {}, quests = {}, totalPets = 0 }

local function openPanel(open)
	open = open and true or false
	local okShow = pcall(function() panel.Visible = open; dim.Visible = open end)
	if not okShow then warn("[PetInv] ERROR opening: panel reference invalid"); return end
	local ok, err = pcall(function()
		if open then
			-- a fresh open lands on the pet cards, not a stuck sub-tab
			pcall(function() questsOverlay.Visible = false end)
			pcall(function() local t = panel:FindFirstChild("TradeOverlay"); if t then t.Visible = false end end)
			-- A fresh open always lands on the FIRST pets tab (the Dino collection), and the nav
			-- has to SAY so. Without this the bar keeps whatever tab was lit when you last closed,
			-- while the panel shows something else -- the exact drift the router exists to prevent.
			-- Routed through showPage (which exists by click time) so the collection page actually
			-- SHOWS; setting activePage alone would light the tab over an empty content band.
			pcall(function()
				if _G.PetHub.showPage then _G.PetHub.showPage("dino")
				else _G.PetHub.activePage = "dino"; _G.PetHub.syncNav() end
			end)
			-- header token chip: show the balance the crate panel last had from the server
			pcall(function() _G.PetHub.setTokens(_G.crateTokenBalance or 0) end)
			_G.MainMenuManager.notifyOpened("PetInv")
			local nOwned = 0; for _ in pairs(latestInv.owned or {}) do nOwned = nOwned + 1 end
			print("[PetInv] inventory opened - owned: " .. nOwned)
			if _G.applyHudScaling then _G.applyHudScaling() end
		else
			_G.MainMenuManager.notifyClosed("PetInv")
			pcall(function() questsOverlay.Visible = false end)
			pcall(function() local t = panel:FindFirstChild("TradeOverlay"); if t then t.Visible = false end end)
		end
	end)
	if not ok then
		warn("[PetInv] ERROR opening/building: " .. tostring(err))
		pcall(function() if open then _G.MainMenuManager.current = "PetInv" else _G.MainMenuManager.notifyClosed("PetInv") end end)
	end
end
closeBtn.MouseButton1Click:Connect(function() openPanel(false) end)
-- NOTE: there is deliberately NO click-outside-to-close handler (same as the main game). `dim`
-- spans the whole screen, so a click anywhere off the panel used to slam the Hub shut, which
-- made the menu feel like it was closing at random. The Hub closes ONLY on an explicit action:
-- the X button, the toggle firing again, or MainMenuManager closing it for another menu.
-- this panel is toggled via the PetInvToggle event (fired by the More+ menu / server)
local toggleEvent = Instance.new("BindableEvent"); toggleEvent.Name = "PetInvToggle"; toggleEvent.Parent = pg
toggleEvent.Event:Connect(function()
	local isOpen = false; pcall(function() isOpen = panel.Visible == true end)
	openPanel(not isOpen)
end)
-- THE UNAMBIGUOUS DOOR (same as the main game). Buttons that can should call this instead of
-- firing a found event -- FindFirstChild("PetInvToggle") can return a stale baked-in impostor.
_G.togglePetHub = function()
	local isOpen = false; pcall(function() isOpen = panel.Visible == true end)
	openPanel(not isOpen)
end
-- ===== KILL THE IMPOSTOR (VERBATIM pattern from the main game, aimed the other way) =====
-- CandyRealm's PetFollow.client.lua is an older snapshot that, once its 30s remote timeouts
-- lapse, builds its OWN ScreenGui named PetInventoryUI and its OWN PetInvToggle BindableEvent
-- -- a complete second (tab-less) Pet Hub. Every opener that falls back to
-- FindFirstChild("PetInvToggle") would then race on load order, and its
-- MainMenuManager.register("PetInv") overwrites ours. So: any same-named event or hub gui that
-- is not OURS is destroyed/retired, at load AND whenever one appears later, and our
-- registration + _G.togglePetHub are re-asserted.
do
	local ownGui = invGui
	local function killImpostor(ch)
		if ch == toggleEvent or ch == ownGui then return end
		if ch:IsA("BindableEvent") and ch.Name == "PetInvToggle" then
			ch:Destroy()
			warn("[PetInv] destroyed a STALE duplicate PetInvToggle (second pet hub -- old PetFollow copy)")
			pcall(function() _G.MainMenuManager.register("PetInv", function() panel.Visible = false; dim.Visible = false end) end)
			_G.togglePetHub = function()
				local isOpen = false; pcall(function() isOpen = panel.Visible == true end)
				openPanel(not isOpen)
			end
		elseif ch:IsA("ScreenGui") and ch.Name == "PetInventoryUI" then
			ch.Enabled = false
			ch.Name = "PetInventoryUI_STALE" -- renamed so no finder can grab it
			warn("[PetInv] retired a STALE duplicate PetInventoryUI gui (second pet hub -- old PetFollow copy)")
			pcall(function() _G.MainMenuManager.register("PetInv", function() panel.Visible = false; dim.Visible = false end) end)
		end
	end
	for _, ch in ipairs(pg:GetChildren()) do killImpostor(ch) end
	pg.ChildAdded:Connect(function(ch) task.defer(killImpostor, ch) end)
end

-- ===== 3D VIEWPORT ICONS (auto-rotating clone of the pet) =====
local iconSpins = {}
-- LITE icon: build the real body from the builder table; rare = subtle tint. (No accessory/level pipeline.)
local function buildIconModel(petId, level, isRare)
	local builder = PET_ICON_BUILDER[petId] or buildBroccoliBlob
	local model = builder(0.9)
	model.Name = petId .. "Icon"
	if not model.PrimaryPart then model.PrimaryPart = model:FindFirstChild("Root") end
	if isRare then -- rare variant: a light tint pass so it reads as special in the icon
		local _, tcol = petTier(level, true, petId)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "Root" then
				d.Color = d.Color:Lerp(tcol, 0.35); d.Material = Enum.Material.Neon
			end
		end
	end
	petAnims[model] = nil
	return model
end
local iconQueue = {}
local iconWorkerActive = false
local function startIconWorker()
	if iconWorkerActive then return end
	iconWorkerActive = true
	task.spawn(function()
		while true do
			local req = table.remove(iconQueue, 1)
			if not req then break end
			if req.vp.Parent then
				local ok, model = pcall(buildIconModel, req.petId, req.level, req.isRare)
				if ok and model and req.vp.Parent then
					local okFrame = pcall(function()
						model:PivotTo(CFrame.new())
						model.Parent = req.vp
						local cf, size = model:GetBoundingBox()
						local maxe = math.max(size.X, size.Y, size.Z, 1)
						local center = cf.Position
						local dir = Vector3.new(0.8, 0.5, 0.55).Unit
						req.cam.CFrame = CFrame.lookAt(center + dir * (maxe * 1.45 + 1), center)
						iconSpins[#iconSpins+1] = { model = model, center = center }
					end)
					if okFrame then if req.ph then req.ph.Visible = false end
					else warn("[PetInv] icon frame failed for " .. tostring(req.petId)) end
				else
					if model then pcall(function() model:Destroy() end) end
					if not ok then warn("[PetInv] ERROR building icon for " .. tostring(req.petId) .. ": " .. tostring(model)) end
				end
			end
			task.wait()
		end
		iconWorkerActive = false
		if #iconQueue > 0 then startIconWorker() end
	end)
end
local function makeViewportIcon(card, petId, level, isRare, sizeU, posU, anchorV)
	local vp = Instance.new("ViewportFrame"); vp.Name = "Icon3D"
	vp.AnchorPoint = anchorV or Vector2.new(0.5,0); vp.Size = sizeU or UDim2.new(0,54,0,34); vp.Position = posU or UDim2.new(0.5,0,0,2)
	vp.BackgroundColor3 = Color3.fromRGB(78, 12, 45); vp.BackgroundTransparency = 0.15; vp.Parent = card
	uicorner(vp, 8)
	vp.Ambient = Color3.fromRGB(185,185,195); vp.LightColor = Color3.fromRGB(255,255,255); vp.LightDirection = Vector3.new(-0.4,-1,-0.5)
	local cam = Instance.new("Camera"); cam.FieldOfView = 50; cam.Parent = vp; vp.CurrentCamera = cam
	local ph = Instance.new("TextLabel"); ph.Name = "IconPlaceholder"; ph.Size = UDim2.new(1,0,1,0); ph.BackgroundTransparency = 1
	ph.Font = Enum.Font.FredokaOne; ph.TextScaled = true; ph.TextColor3 = Color3.fromRGB(235, 150, 194); ph.Text = "\xF0\x9F\x90\xBE"; ph.Parent = vp
	iconQueue[#iconQueue + 1] = { vp = vp, cam = cam, ph = ph, petId = petId, level = level, isRare = isRare }
	startIconWorker()
	return vp
end
do
	local angle = 0
	RunService.RenderStepped:Connect(function(dt)
		if not panel.Visible or #iconSpins == 0 then return end
		angle = (angle + dt * 0.6) % (2 * math.pi)
		for i = #iconSpins, 1, -1 do
			local ic = iconSpins[i]
			if ic.model and ic.model.Parent then
				ic.model:PivotTo(CFrame.new(ic.center) * CFrame.Angles(0, angle, 0) * CFrame.new(-ic.center))
			else table.remove(iconSpins, i) end
		end
	end)
end

-- one OWNED pet card (VERBATIM)
local function buildPetCard(key, p, order)
	local petId = p.petId or key
	local card = Instance.new("Frame"); card.Name = key; card.LayoutOrder = order
	card.BackgroundColor3 = p.rare and Color3.fromRGB(46,28,86) or Color3.fromRGB(160, 20, 93); card.Parent = petsScroll
	uicorner(card, 12)
	local tierName, tierColor, isVariant = petTier(p.level, p.rare, petId)
	uistroke(card, isVariant and tierColor or (p.equipped and Color3.fromRGB(255,215,0) or Color3.fromRGB(100, 10, 55)), (isVariant or p.equipped) and 3 or 1)
	makeViewportIcon(card, petId, p.level, p.rare, UDim2.new(0,310,0,140), UDim2.new(0.5,0,0,6), Vector2.new(0.5,0))
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-16,0,18); nm.Position = UDim2.new(0,8,0,150)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 16
	nm.TextColor3 = isVariant and tierColor or Color3.new(1,1,1)
	nm.Text = p.rare and (p.rareName or p.displayName) or p.displayName; nm.Parent = card
	if isVariant then
		local tag = Instance.new("TextLabel"); tag.AutomaticSize = Enum.AutomaticSize.X; tag.Size = UDim2.new(0,0,0,18); tag.Position = UDim2.new(1,-6,0,8); tag.AnchorPoint = Vector2.new(1,0)
		tag.BackgroundColor3 = tierColor; tag.Font = Enum.Font.GothamBold; tag.TextSize = 11; tag.TextColor3 = Color3.new(1,1,1); tag.Text = tierName; tag.Parent = card
		local pad = Instance.new("UIPadding", tag); pad.PaddingLeft = UDim.new(0,5); pad.PaddingRight = UDim.new(0,5)
		uicorner(tag, 5)
		local ts = Instance.new("UIStroke"); ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ts.Color = Color3.fromRGB(255,255,255); ts.Thickness = 1; ts.Transparency = 0.2; ts.Parent = tag
	end
	-- ---- RARITY PILL: the axis that never moves --------------------------------------------------------
	-- Bottom-left of the picture, deliberately away from the age tag (top-right) and the xN count (top-left):
	-- three badges that look alike in one corner is how a player learns to read none of them.
	-- Common gets no pill at all -- it is the default, and a badge on every card stops being a signal.
	local rarityBand = p.rarity or PetRarity.DEFAULT
	if rarityBand ~= PetRarity.DEFAULT then
		local rc = PetRarity.Color[rarityBand] or Color3.fromRGB(200,200,200)
		local rp = Instance.new("TextLabel"); rp.Name = "RarityPill"
		rp.AutomaticSize = Enum.AutomaticSize.X; rp.Size = UDim2.new(0,0,0,17)
		rp.AnchorPoint = Vector2.new(0,1); rp.Position = UDim2.new(0,8,0,142) -- art is 140 tall from y=6
		rp.BackgroundColor3 = rc; rp.Font = Enum.Font.GothamBold; rp.TextSize = 11
		rp.TextColor3 = Color3.new(1,1,1); rp.Text = rarityBand:upper(); rp.Parent = card
		local rpad = Instance.new("UIPadding", rp); rpad.PaddingLeft = UDim.new(0,6); rpad.PaddingRight = UDim.new(0,6)
		uicorner(rp, 5)
		local rs = Instance.new("UIStroke"); rs.Color = Color3.fromRGB(0,0,0); rs.Thickness = 1; rs.Transparency = 0.35; rs.Parent = rp
	end

	if (p.count or 1) > 1 then
		local cnt = Instance.new("TextLabel"); cnt.AutomaticSize = Enum.AutomaticSize.X; cnt.Size = UDim2.new(0,0,0,18); cnt.Position = UDim2.new(0,6,0,8)
		cnt.BackgroundColor3 = Color3.fromRGB(255,170,40); cnt.Font = Enum.Font.GothamBold; cnt.TextSize = 12; cnt.TextColor3 = Color3.new(1,1,1); cnt.Text = "x" .. (p.count or 1); cnt.Parent = card
		local cpad = Instance.new("UIPadding", cnt); cpad.PaddingLeft = UDim.new(0,5); cpad.PaddingRight = UDim.new(0,5)
		uicorner(cnt, 5)
		local cs = Instance.new("UIStroke"); cs.Color = Color3.fromRGB(0,0,0); cs.Thickness = 1; cs.Transparency = 0.2; cs.Parent = cnt
	end
	local cap = p.maxLevel or 25
	local maxed = (p.level >= cap)
	local lv = Instance.new("TextLabel"); lv.Size = UDim2.new(1,-16,0,16); lv.Position = UDim2.new(0,8,0,170)
	lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold; lv.TextSize = 13
	lv.Text = (isVariant and tierName or (tierName .. "  Lv " .. p.level)) .. (p.equipped and "  \xE2\x80\xA2 EQUIPPED" or ""); lv.Parent = card
	lv.TextColor3 = tierColor
	local barBG = Instance.new("Frame"); barBG.Size = UDim2.new(1,-16,0,14); barBG.Position = UDim2.new(0,8,0,188)
	barBG.BackgroundColor3 = Color3.fromRGB(90, 12, 53); barBG.BorderSizePixel = 0; barBG.Parent = card; uicorner(barBG, 7); uistroke(barBG, Color3.fromRGB(64, 8, 35), 1)
	local frac = maxed and 1 or math.clamp((p.xp or 0) / math.max(1, p.xpNeed or 1), 0, 1)
	local fill = Instance.new("Frame"); fill.Size = UDim2.new(frac, 0, 1, 0); fill.BorderSizePixel = 0
	fill.BackgroundColor3 = maxed and Color3.fromRGB(255,200,40) or Color3.fromRGB(80,220,120); fill.Parent = barBG; uicorner(fill, 7)
	local xpTxt = Instance.new("TextLabel"); xpTxt.Size = UDim2.new(1,0,1,0); xpTxt.BackgroundTransparency = 1
	xpTxt.Font = Enum.Font.GothamBold; xpTxt.TextSize = 10; xpTxt.TextColor3 = Color3.new(1,1,1); xpTxt.Parent = barBG
	xpTxt.Text = maxed and "MAX" or ((p.xp or 0) .. " / " .. (p.xpNeed or 0) .. " XP")
	local ms = Instance.new("TextLabel"); ms.Size = UDim2.new(1,-16,0,14); ms.Position = UDim2.new(0,8,0,236)
	ms.BackgroundTransparency = 1; ms.Font = Enum.Font.Gotham; ms.TextSize = 11; ms.TextColor3 = Color3.fromRGB(255, 185, 224)
	ms.Text = "\xE2\x9C\xA8 " .. (p.milestone or ""); ms.Parent = card
	-- ---- BUTTON ROW: two across, or three when this stack can fuse ---------------------------------------
	-- This card lays out in fixed pixels, so the widths are computed rather than left to a layout: 310 usable
	-- (8px margins on a ~326 card), minus two 6px gaps, split three ways = 99 each at x = 8 / 113 / 218.
	-- With no fuse slot the original two 149s at 8 / 165 are kept exactly, so a card with nothing to fuse
	-- looks untouched.
	-- The slot appears as soon as you hold a SECOND copy, not only once you can afford it -- seeing "FUSE 2/5"
	-- is how a player finds out duplicates are worth keeping. p.fuseCost is nil at Gold: nothing to fuse into.
	local dupes    = p.count or 1
	local showFuse = (p.fuseCost ~= nil) and dupes > 1
	local bw       = showFuse and 99 or 149
	local x2       = showFuse and 113 or 165

	local eq = Instance.new("TextButton"); eq.Size = UDim2.new(0,bw,0,26); eq.Position = UDim2.new(0,8,0,208)
	eq.Font = Enum.Font.GothamBold; eq.TextSize = 13; eq.TextColor3 = Color3.new(1,1,1)
	eq.BackgroundColor3 = p.equipped and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50)
	eq.Text = p.equipped and "UNEQUIP" or "EQUIP"; eq.Parent = card
	uicorner(eq, 8); uistroke(eq, Color3.new(0,0,0), 1)
	eq.MouseButton1Click:Connect(function()
		if PetEquipEvent then
			if p.equipped then pcall(function() PetEquipEvent:FireServer(false) end)
			else pcall(function() PetEquipEvent:FireServer(key) end) end
		end
	end)
	if showFuse then
		local canFuse = p.canFuse == true
		local into    = p.fuseInto or "?"
		local fz = Instance.new("TextButton"); fz.Name = "Fuse"
		fz.Size = UDim2.new(0,bw,0,26); fz.Position = UDim2.new(0,218,0,208)
		fz.Font = Enum.Font.GothamBold; fz.TextSize = 12; fz.TextColor3 = Color3.new(1,1,1); fz.Parent = card
		uicorner(fz, 8)
		if canFuse then
			-- tinted with the band you are fusing INTO, so the button previews its own reward
			fz.BackgroundColor3 = PetRarity.Color[into] or Color3.fromRGB(180,90,235)
			fz.Text = "FUSE \xE2\x86\x92 " .. into
			uistroke(fz, Color3.new(1,1,1), 2)
			fz.MouseButton1Click:Connect(function()
				if PetFuseEvent then pcall(function() PetFuseEvent:FireServer(key) end) end
			end)
		else
			-- Not enough yet: show the goal, not a dead button. AutoButtonColor off so it does not flash
			-- like something that should work.
			fz.BackgroundColor3 = Color3.fromRGB(90,90,90); fz.AutoButtonColor = false
			fz.Text = string.format("FUSE %d/%d", dupes, p.fuseCost)
			uistroke(fz, Color3.new(0,0,0), 1)
		end
	end

	local sk = Instance.new("TextButton"); sk.Size = UDim2.new(0,bw,0,26); sk.Position = UDim2.new(0,x2,0,208)
	sk.Font = Enum.Font.GothamBold; sk.TextSize = 12; sk.TextColor3 = Color3.new(1,1,1); sk.Parent = card; uicorner(sk, 8)
	local skipStep = (p.level <= 5 and PET_SKIP_PRODUCTS[1]) or (p.level <= 10 and PET_SKIP_PRODUCTS[2])
		or (p.level <= 15 and PET_SKIP_PRODUCTS[3]) or (p.level <= 20 and PET_SKIP_PRODUCTS[4]) or nil
	if maxed or not skipStep then
		sk.Text = maxed and "MAX LEVEL" or "MAX TIER"; sk.BackgroundColor3 = Color3.fromRGB(90,90,90); sk.AutoButtonColor = false
	else
		sk.Text = "Skip to " .. skipStep.to .. "  R$" .. skipStep.price; sk.BackgroundColor3 = Color3.fromRGB(50,170,90)
		sk.MouseButton1Click:Connect(function()
			if PetPendingUpgrade then pcall(function() PetPendingUpgrade:FireServer(key) end) end
			task.wait(0.15)
			pcall(function() MarketplaceService:PromptProductPurchase(player, skipStep.id) end)
		end)
	end
end

local function buildLockedSlot(order)
	local slot = Instance.new("Frame"); slot.Name = "Locked"; slot.LayoutOrder = order; slot.BackgroundColor3 = Color3.fromRGB(104, 14, 61); slot.Parent = petsScroll
	uicorner(slot, 10); uistroke(slot, Color3.fromRGB(80, 10, 42), 1)
	local q = Instance.new("TextLabel"); q.Size = UDim2.new(1,0,1,-22); q.BackgroundTransparency = 1; q.Font = Enum.Font.GothamBold; q.TextSize = 46; q.TextColor3 = Color3.fromRGB(170, 70, 117); q.Text = "?"; q.Parent = slot
	local lk = Instance.new("TextLabel"); lk.Size = UDim2.new(1,-8,0,18); lk.Position = UDim2.new(0,4,1,-22); lk.BackgroundTransparency = 1; lk.Font = Enum.Font.Gotham; lk.TextSize = 12; lk.TextColor3 = Color3.fromRGB(220, 130, 175); lk.Text = "\xF0\x9F\x94\x92 Locked"; lk.Parent = slot
end

local function buildQuestEntry(q, order)
	local qf = Instance.new("Frame"); qf.Name = "Quest"; qf.LayoutOrder = order; qf.Size = UDim2.new(1,-4,0,92); qf.BackgroundColor3 = Color3.fromRGB(160, 20, 93); qf.Parent = questsScroll
	uicorner(qf, 8); uistroke(qf, Color3.fromRGB(100, 10, 55), 1)
	local qn = Instance.new("TextLabel"); qn.Size = UDim2.new(1,-10,0,18); qn.Position = UDim2.new(0,6,0,4)
	qn.BackgroundTransparency = 1; qn.Font = Enum.Font.GothamBold; qn.TextSize = 14; qn.TextColor3 = Color3.new(1,1,1); qn.TextXAlignment = Enum.TextXAlignment.Left; qn.Text = q.islandName or "?"; qn.Parent = qf
	local statusCol = (q.status == "done") and Color3.fromRGB(120,255,120) or (q.status == "inprogress") and Color3.fromRGB(255,205,90) or Color3.fromRGB(255, 180, 232)
	local statusTxt = (q.status == "done") and "Done \xE2\x9C\x94"
		or (q.status == "inprogress") and ("In Progress  "..(q.found or 0).."/"..(q.total or 0).." "..(q.unit or ""))
		or "Available"
	local qs = Instance.new("TextLabel"); qs.Size = UDim2.new(1,-10,0,14); qs.Position = UDim2.new(0,6,0,22)
	qs.BackgroundTransparency = 1; qs.Font = Enum.Font.GothamBold; qs.TextSize = 11; qs.TextColor3 = statusCol; qs.TextXAlignment = Enum.TextXAlignment.Left; qs.Text = statusTxt; qs.Parent = qf
	local qd = Instance.new("TextLabel"); qd.Size = UDim2.new(1,-12,0,46); qd.Position = UDim2.new(0,6,0,38)
	qd.BackgroundTransparency = 1; qd.Font = Enum.Font.Gotham; qd.TextSize = 11; qd.TextColor3 = Color3.fromRGB(255, 205, 230); qd.TextWrapped = true
	qd.TextXAlignment = Enum.TextXAlignment.Left; qd.TextYAlignment = Enum.TextYAlignment.Top; qd.Text = q.desc or ""; qd.Parent = qf
end

local function rebuildInventory(payload)
	local ok, err = pcall(function()
		latestInv = payload or { owned = {}, quests = {}, totalPets = 0 }
		local owned, quests = latestInv.owned or {}, latestInv.quests or {}
		table.clear(iconSpins)
		for _, c in ipairs(petsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		local ownedCount, order = 0, 0
		local rank = { Mythical = 7, Exotic = 6, Elder = 5, Adult = 4, Teen = 3, Kid = 2, Baby = 1 } -- AGE tiers (matches the live petTier)
		local ids = {}
		for skey in pairs(owned) do ids[#ids + 1] = skey end
		table.sort(ids, function(a, b)
			local pa, pb = owned[a], owned[b]
			local ra = rank[petTier(pa.level or 1, pa.rare, pa.petId)] or 0
			local rb = rank[petTier(pb.level or 1, pb.rare, pb.petId)] or 0
			if ra ~= rb then return ra > rb end
			return (pa.level or 0) > (pb.level or 0)
		end)
		for _, skey in ipairs(ids) do
			ownedCount = ownedCount + 1; order = order + 1
			local okc, ec = pcall(buildPetCard, skey, owned[skey], order)
			if not okc then warn("[PetInv] card build failed for " .. tostring(skey) .. ": " .. tostring(ec)) end
		end
		if ownedCount == 0 then
			local em = Instance.new("Frame"); em.Name = "PetsEmpty"; em.Size = UDim2.new(1,-20,0,90); em.Position = UDim2.new(0,10,0,8); em.BackgroundTransparency = 1; em.Parent = petsScroll
			local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 20; lbl.TextWrapped = true; lbl.TextColor3 = Color3.fromRGB(255, 190, 221); lbl.Text = "No Pets Unlocked\nComplete pet quests on the islands to hatch your first pet!"; lbl.Parent = em
		end
		-- header readout: "X / Y pets unlocked" (Y = the catalog size the server reports)
		pcall(function() _G.PetHub.setProgress(ownedCount, latestInv.totalPets or 0) end)
		petsScroll.CanvasSize = UDim2.new(0,0,0, math.ceil(ownedCount / 2) * 264 + 20)
		for _, c in ipairs(questsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		local qCount = 0
		for _, q in pairs(quests) do qCount = qCount + 1; pcall(buildQuestEntry, q, qCount) end
		questsEmpty.Visible = (qCount == 0)
		questsScroll.CanvasSize = UDim2.new(0,0,0, qCount * 100 + 8)
	end)
	if not ok then warn("[PetInv] ERROR building inventory: " .. tostring(err)) end
end
if PetInventoryEvent then PetInventoryEvent.OnClientEvent:Connect(rebuildInventory) end

-- =====================================================================================================
-- TRADE UI (housed in the Pet Hub). The client sends INTENTS only; the server owns the trade. (VERBATIM)
-- =====================================================================================================
local tradeState = nil

local function makeOfferRow(parent, brief, order, onClick)
	local row = Instance.new(onClick and "TextButton" or "TextLabel"); row.Size = UDim2.new(1,-6,0,26); row.LayoutOrder = order
	row.BackgroundColor3 = Color3.fromRGB(160, 20, 93); row.Text = ""; row.Parent = parent; uicorner(row, 6)
	if onClick then row.AutoButtonColor = true end
	local tname, tcol = petTier(brief.level, brief.rare, brief.petId)
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-10,1,0); nm.Position = UDim2.new(0,6,0,0); nm.BackgroundTransparency = 1
	nm.Font = Enum.Font.GothamBold; nm.TextSize = 12; nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextColor3 = tcol
	nm.Text = brief.name .. "  (" .. tname .. (brief.rare and "" or ("  Lv" .. tostring(brief.level))) .. ")"; nm.Parent = row
	if onClick then row.MouseButton1Click:Connect(onClick) end
	return row
end

local function makeOfferCard(parent, brief, order, onClick)
	local card = Instance.new(onClick and "TextButton" or "TextLabel")
	card.Size = UDim2.new(1,-6,0,76); card.LayoutOrder = order
	card.BackgroundColor3 = brief.rare and Color3.fromRGB(46,28,86) or Color3.fromRGB(160, 20, 93)
	card.Text = ""; if onClick then card.AutoButtonColor = true end; card.Parent = parent; uicorner(card, 8)
	local tname, tcol, isVariant = petTier(brief.level, brief.rare, brief.petId)
	uistroke(card, isVariant and tcol or Color3.fromRGB(100, 10, 55), isVariant and 2 or 1)
	makeViewportIcon(card, brief.petId, brief.level, brief.rare, UDim2.new(0,96,0,68), UDim2.new(0,4,0,4), Vector2.new(0,0))
	local nm = Instance.new("TextLabel"); nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 14
	nm.TextColor3 = isVariant and tcol or Color3.new(1,1,1); nm.TextXAlignment = Enum.TextXAlignment.Left
	nm.Position = UDim2.new(0,108,0,8); nm.Size = UDim2.new(1,-114,0,20); nm.Text = brief.name; nm.Parent = card
	local lv = Instance.new("TextLabel"); lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold; lv.TextSize = 12
	lv.TextColor3 = tcol; lv.TextXAlignment = Enum.TextXAlignment.Left
	lv.Position = UDim2.new(0,108,0,32); lv.Size = UDim2.new(1,-114,0,18)
	lv.Text = isVariant and tname or (tname .. "  Lv " .. tostring(brief.level)); lv.Parent = card
	if onClick then
		local h = Instance.new("TextLabel"); h.BackgroundTransparency = 1; h.Font = Enum.Font.Gotham; h.TextSize = 11; h.TextColor3 = Color3.fromRGB(255,190,190)
		h.TextXAlignment = Enum.TextXAlignment.Left; h.Position = UDim2.new(0,108,0,52); h.Size = UDim2.new(1,-114,0,16); h.Text = "Click to remove \xE2\x9C\x95"; h.Parent = card
		card.MouseButton1Click:Connect(onClick)
	end
	return card
end

-- (the old header "TRADE" chip is gone -- TRADE is a tab in the HubNav bar now, exactly like
--  the main game; its open logic lives in the showPage router below)

-- ⚠ RENAMED "TradeOverlayLegacy": this built-in trade UI is RETIRED. PetTradeClient.client.luau (realm 1's
-- trade window, the same file Space runs) now owns the TRADE tab -- it creates the panel's one true
-- "TradeOverlay" and intercepts showPage("trade") before this file's router sees it. The rename matters
-- beyond tidiness: TradeRequests.client.luau attaches its FRIENDS tab to Panel:FindFirstChild("TradeOverlay"),
-- and two children with that name would make which one it finds a race.
local tradeOverlay = Instance.new("Frame"); tradeOverlay.Name = "TradeOverlayLegacy"; tradeOverlay.Size = UDim2.new(1,-24,1,-116); tradeOverlay.Position = UDim2.new(0,12,0,110)
tradeOverlay.BackgroundColor3 = Color3.fromRGB(140, 16, 81); tradeOverlay.Visible = false; tradeOverlay.Parent = panel; uicorner(tradeOverlay, 12); uistroke(tradeOverlay, Color3.fromRGB(100, 10, 55), 2)
local ovTitle = Instance.new("TextLabel"); ovTitle.Size = UDim2.new(1,-120,0,28); ovTitle.Position = UDim2.new(0,12,0,8); ovTitle.BackgroundTransparency = 1
ovTitle.Font = Enum.Font.GothamBold; ovTitle.TextSize = 18; ovTitle.TextColor3 = Color3.fromRGB(255,215,0); ovTitle.TextXAlignment = Enum.TextXAlignment.Left; ovTitle.Text = "Trade"; ovTitle.Parent = tradeOverlay
local ovBack = Instance.new("TextButton"); ovBack.Size = UDim2.new(0,100,0,28); ovBack.Position = UDim2.new(1,-108,0,8); ovBack.BackgroundColor3 = Color3.fromRGB(120,120,120)
ovBack.Font = Enum.Font.GothamBold; ovBack.TextSize = 13; ovBack.TextColor3 = Color3.new(1,1,1); ovBack.Text = "\xE2\x97\x80 Pets"; ovBack.Parent = tradeOverlay; uicorner(ovBack, 8)

local pickerView = Instance.new("Frame"); pickerView.Size = UDim2.new(1,-16,1,-46); pickerView.Position = UDim2.new(0,8,0,42); pickerView.BackgroundTransparency = 1; pickerView.Parent = tradeOverlay
local pickerScroll = Instance.new("ScrollingFrame"); pickerScroll.Size = UDim2.new(1,0,1,0); pickerScroll.BackgroundTransparency = 1; pickerScroll.BorderSizePixel = 0
pickerScroll.ScrollBarThickness = 6; pickerScroll.ScrollBarImageColor3 = Color3.fromRGB(255,215,0); pickerScroll.CanvasSize = UDim2.new(0,0,0,0); pickerScroll.Parent = pickerView
local pickerLayout = Instance.new("UIListLayout"); pickerLayout.Padding = UDim.new(0,6); pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder; pickerLayout.Parent = pickerScroll

local windowView = Instance.new("Frame"); windowView.Size = UDim2.new(1,-16,1,-46); windowView.Position = UDim2.new(0,8,0,42); windowView.BackgroundTransparency = 1; windowView.Visible = false; windowView.Parent = tradeOverlay
local function colTitle(text, x) local l = Instance.new("TextLabel"); l.Size = UDim2.new(0,310,0,18); l.Position = UDim2.new(0,x,0,0); l.BackgroundTransparency = 1; l.Font = Enum.Font.GothamBold; l.TextSize = 14; l.TextColor3 = Color3.fromRGB(255,215,0); l.TextXAlignment = Enum.TextXAlignment.Left; l.Text = text; l.Parent = windowView; return l end
local function colScroll(x, y, h) local s = Instance.new("ScrollingFrame"); s.Size = UDim2.new(0,310,0,h); s.Position = UDim2.new(0,x,0,y); s.BackgroundColor3 = Color3.fromRGB(104, 12, 59); s.BorderSizePixel = 0; s.ScrollBarThickness = 5; s.CanvasSize = UDim2.new(0,0,0,0); s.Parent = windowView; uicorner(s,8); local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0,4); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = s; return s end
colTitle("YOUR OFFER (click to remove)", 0)
local yourOfferScroll = colScroll(0, 20, 150)
local addTitleLbl = colTitle("YOUR PETS (click to add)", 0); addTitleLbl.Position = UDim2.new(0,0,0,176)
local addScroll = colScroll(0, 196, 160) -- 160, not 200: the overlay starts at y=110 now (nav bar), so 200 would run past the panel's bottom edge
colTitle("THEIR OFFER", 330)
local theirOfferScroll = colScroll(330, 20, 150)
local statusLbl = Instance.new("TextLabel"); statusLbl.Size = UDim2.new(0,310,0,108); statusLbl.Position = UDim2.new(0,330,0,178); statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.GothamBold; statusLbl.TextSize = 14; statusLbl.TextColor3 = Color3.new(1,1,1); statusLbl.TextWrapped = true; statusLbl.TextYAlignment = Enum.TextYAlignment.Top; statusLbl.Text = ""; statusLbl.Parent = windowView
local cancelBtn = Instance.new("TextButton"); cancelBtn.Size = UDim2.new(0,150,0,34); cancelBtn.Position = UDim2.new(0,330,0,300); cancelBtn.BackgroundColor3 = Color3.fromRGB(220,60,60)
cancelBtn.Font = Enum.Font.GothamBold; cancelBtn.TextSize = 15; cancelBtn.TextColor3 = Color3.new(1,1,1); cancelBtn.Text = "CANCEL"; cancelBtn.Parent = windowView; uicorner(cancelBtn,8); uistroke(cancelBtn, Color3.new(0,0,0),2)
local confirmBtn = Instance.new("TextButton"); confirmBtn.Size = UDim2.new(0,150,0,34); confirmBtn.Position = UDim2.new(0,490,0,300); confirmBtn.BackgroundColor3 = Color3.fromRGB(50,200,50)
confirmBtn.Font = Enum.Font.GothamBold; confirmBtn.TextSize = 15; confirmBtn.TextColor3 = Color3.new(1,1,1); confirmBtn.Text = "CONFIRM"; confirmBtn.Parent = windowView; uicorner(confirmBtn,8); uistroke(confirmBtn, Color3.new(0,0,0),2)

local function clearScroll(s) for _, c in ipairs(s:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end end
local function refreshPicker()
	clearScroll(pickerScroll)
	local order, n = 0, 0
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= player then
			n = n + 1; order = order + 1
			local row = Instance.new("Frame"); row.Size = UDim2.new(1,-6,0,30); row.LayoutOrder = order; row.BackgroundColor3 = Color3.fromRGB(160, 20, 93); row.Parent = pickerScroll; uicorner(row,6)
			local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-94,1,0); nm.Position = UDim2.new(0,8,0,0); nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 13; nm.TextColor3 = Color3.new(1,1,1); nm.TextXAlignment = Enum.TextXAlignment.Left; nm.Text = pl.DisplayName .. " (@" .. pl.Name .. ")"; nm.Parent = row
			local req = Instance.new("TextButton"); req.Size = UDim2.new(0,82,0,24); req.Position = UDim2.new(1,-86,0,3); req.BackgroundColor3 = Color3.fromRGB(50,200,50); req.Font = Enum.Font.GothamBold; req.TextSize = 12; req.TextColor3 = Color3.new(1,1,1); req.Text = "REQUEST"; req.Parent = row; uicorner(req,6)
			local uid = pl.UserId
			req.MouseButton1Click:Connect(function() if PetTradeRequest then pcall(function() PetTradeRequest:FireServer(uid) end) end; ovTitle.Text = "Request sent to " .. pl.DisplayName .. "..." end)
		end
	end
	if n == 0 then
		local e = Instance.new("TextLabel"); e.Size = UDim2.new(1,-6,0,40); e.BackgroundTransparency = 1; e.Font = Enum.Font.Gotham; e.TextSize = 13; e.TextColor3 = Color3.fromRGB(255, 200, 229); e.TextWrapped = true; e.Text = "No other players in the server to trade with."; e.Parent = pickerScroll
	end
	pickerScroll.CanvasSize = UDim2.new(0,0,0, n*36 + 8)
end
local function showPicker() pickerView.Visible = true; windowView.Visible = false; ovTitle.Text = "Trade \xE2\x80\x94 pick a player"; refreshPicker() end
local function renderTradeWindow(state)
	pickerView.Visible = false; windowView.Visible = true; ovTitle.Text = "Trading with " .. tostring(state.withName)
	clearScroll(yourOfferScroll); for i, b in ipairs(state.mine or {}) do makeOfferCard(yourOfferScroll, b, i, function() if PetTradeOffer then pcall(function() PetTradeOffer:FireServer(b.key or b.petId, false) end) end end) end
	yourOfferScroll.CanvasSize = UDim2.new(0,0,0, #(state.mine or {}) * 80 + 4)
	clearScroll(theirOfferScroll); for i, b in ipairs(state.theirs or {}) do makeOfferCard(theirOfferScroll, b, i, nil) end
	theirOfferScroll.CanvasSize = UDim2.new(0,0,0, #(state.theirs or {}) * 80 + 4)
	local offered = {}; for _, b in ipairs(state.mine or {}) do offered[b.key or b.petId] = true end
	clearScroll(addScroll); local idx = 0
	for skey, p in pairs(latestInv.owned or {}) do
		if not offered[skey] then idx = idx + 1
			local rowName = ((p.rare and p.rareName) or p.displayName) .. (((p.count or 1) > 1) and ("  x" .. p.count) or "")
			makeOfferRow(addScroll, { petId = p.petId, name = rowName, level = p.level, rare = p.rare }, idx, function() if PetTradeOffer then pcall(function() PetTradeOffer:FireServer(skey, true) end) end end)
		end
	end
	addScroll.CanvasSize = UDim2.new(0,0,0, idx * 30 + 4)
	local st = state.status
	statusLbl.Text = (st=="trading" and "\xE2\x9C\xA8 Both confirmed - trading!") or (st=="waiting_them" and ("You confirmed.\nWaiting for " .. state.withName .. "...")) or (st=="waiting_you" and (state.withName .. " confirmed.\nYour move!")) or "Add pets, then both CONFIRM.\n(changing an offer resets both confirms)"
	confirmBtn.Text = state.myConfirm and "\xE2\x9C\x94 CONFIRMED" or "CONFIRM"
	confirmBtn.BackgroundColor3 = state.myConfirm and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50)
end
ovBack.MouseButton1Click:Connect(function() if _G.PetHub.showPage then _G.PetHub.showPage("pets") end end)
cancelBtn.MouseButton1Click:Connect(function() if PetTradeCancel then pcall(function() PetTradeCancel:FireServer() end) end end)
confirmBtn.MouseButton1Click:Connect(function() if PetTradeConfirm then pcall(function() PetTradeConfirm:FireServer() end) end end)

-- ===== HUB ROUTER: one page at a time (VERBATIM from the main game) =====
-- Defined HERE, not up beside the nav bar, because it drives the real trade + quest overlays
-- and they do not exist yet at that point in the file. The nav buttons look showPage up at
-- CLICK time, so the order is fine.
--
-- Every page is mutually exclusive: the old header chips TOGGLED, which let you end up with
-- the pet grid showing while the nav claimed you were on Quests. A router that SETS state
-- instead of flipping it cannot drift out of step with the highlighted tab.
_G.PetHub.activePage = "dino" -- the first pets tab; "pets" itself no longer exists as a page

_G.PetHub.syncNav = function()
	local cur = _G.PetHub.activePage or "dino"
	for id, b in pairs(_G.PetHub.navButtons or {}) do
		local on = (id == cur)
		-- selected = dark-on-gold, unselected = gold-on-blue. Same two states the crate panel uses.
		b.BackgroundColor3 = on and Color3.fromRGB(255,215,0) or Color3.fromRGB(150, 18, 88)
		b.TextColor3 = on and Color3.fromRGB(92,58,8) or Color3.fromRGB(255,215,0)
		local st = b:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = on and Color3.fromRGB(180,122,20) or Color3.new(1,1,1)
			st.Thickness = on and 2.5 or 1.5
		end
	end
end

_G.PetHub.showPage = function(id)
	id = id or "pets"
	-- "pets" NO LONGER HAS A PAGE (the demo-inventory tab is removed) but plenty of callers still say it:
	-- the quests/trade Back buttons, the PetTradeState close path, and any external opener written before
	-- the change. Mapping it here, at the single entry point, retargets every one of them at once to the
	-- first pets tab -- the Dino collection -- instead of leaving them pointing at a hidden grid.
	if id == "pets" then id = "dino" end
	-- CRATES (and TOKENS, a page inside it) belong to the crate panel. Hand off rather than
	-- rebuild: that panel already owns the roll, the reveal and the token purchase, and a
	-- second copy of any of those is a second thing that can disagree with the server.
	if id == "crates" or id == "tokens" then
		openPanel(false) -- close the hub first: both panels are DisplayOrder 100, so they'd overlap
		if _G.toggleSkinCrates then
			-- `true` = opened from the hub, which makes the crate panel show its BACK button
			_G.toggleSkinCrates(true, id)
		else
			-- no skin-crate panel in this realm yet -> the daily crate panel is the crate door
			local ev = RS:FindFirstChild("OpenMeteorCrate")
			if ev and ev:IsA("BindableEvent") then ev:Fire()
			else
				print("[PetHub] no crate panel in this realm yet (_G.toggleSkinCrates / OpenMeteorCrate missing)")
				openPanel(true) -- reopen the hub (lands back on PETS) so the player isn't dropped to nothing
			end
		end
		return
	end
	questsOverlay.Visible = (id == "quests")
	-- NEVER shown any more: PetTradeClient intercepts "trade" before this line can run with that id, and
	-- pinning it false covers the boot window before its wrap installs -- a click in that window would
	-- otherwise show the retired UI once, talking to remotes with the same names as the real one.
	tradeOverlay.Visible  = false
	-- EXTRA PAGES owned by other scripts (the FOOD and DINO realm collections). Registered through
	-- _G.PetHub.registerPage so this file does not have to know how they are built -- it only has to
	-- tell every one of them whether it is the page being shown, which is what keeps the lit tab and
	-- the visible page from drifting apart the way independent toggles always eventually do.
	for pageId, page in pairs(_G.PetHub.extraPages) do
		if type(page) == "function" then pcall(page, id == pageId) end
	end
	if id == "trade" then
		-- a live session shows the trade window; otherwise the picker
		if tradeState and tradeState.active then renderTradeWindow(tradeState) else showPicker() end
	end
	_G.PetHub.activePage = id
	_G.PetHub.syncNav()
end
_G.PetHub.syncNav() -- paint the initial state (PETS lit)

qoBack.MouseButton1Click:Connect(function() if _G.PetHub.showPage then _G.PetHub.showPage("pets") end end)

if PetTradeState then PetTradeState.OnClientEvent:Connect(function(state)
	tradeState = state
	if state and state.active then
		openPanel(true) -- ensure the Hub is open so both players see the trade window
		if _G.PetHub.showPage then _G.PetHub.showPage("trade") else tradeOverlay.Visible = true; renderTradeWindow(state) end
	else
		local reason = state and state.reason
		print("[Trade] window closed (" .. tostring(reason) .. ")")
		tradeState = nil
		if tradeOverlay.Visible then ovTitle.Text = "Trade " .. (reason and ("\xE2\x80\x94 " .. reason) or "closed"); showPicker() end
	end
end) end

-- incoming-request popup (shows even if the Hub is closed)
local reqPopup = Instance.new("Frame"); reqPopup.Name = "TradeRequestPopup"; reqPopup.AnchorPoint = Vector2.new(0.5,0.5); reqPopup.Position = UDim2.new(0.5,0,0.4,0); reqPopup.Size = UDim2.new(0,320,0,130)
reqPopup.BackgroundColor3 = Color3.fromRGB(185, 25, 117); reqPopup.Visible = false; reqPopup.ZIndex = 50; reqPopup.Parent = invGui; uicorner(reqPopup, 12); uistroke(reqPopup, Color3.fromRGB(255,215,0), 3)
local reqLbl = Instance.new("TextLabel"); reqLbl.Size = UDim2.new(1,-20,0,60); reqLbl.Position = UDim2.new(0,10,0,10); reqLbl.BackgroundTransparency = 1; reqLbl.ZIndex = 51; reqLbl.Font = Enum.Font.GothamBold; reqLbl.TextSize = 16; reqLbl.TextColor3 = Color3.new(1,1,1); reqLbl.TextWrapped = true; reqLbl.Text = ""; reqLbl.Parent = reqPopup
local reqAccept = Instance.new("TextButton"); reqAccept.Size = UDim2.new(0,140,0,38); reqAccept.Position = UDim2.new(0,12,1,-46); reqAccept.BackgroundColor3 = Color3.fromRGB(50,200,50); reqAccept.ZIndex = 51; reqAccept.Font = Enum.Font.GothamBold; reqAccept.TextSize = 15; reqAccept.TextColor3 = Color3.new(1,1,1); reqAccept.Text = "ACCEPT"; reqAccept.Parent = reqPopup; uicorner(reqAccept,8)
local reqDecline = Instance.new("TextButton"); reqDecline.Size = UDim2.new(0,140,0,38); reqDecline.Position = UDim2.new(1,-152,1,-46); reqDecline.BackgroundColor3 = Color3.fromRGB(220,60,60); reqDecline.ZIndex = 51; reqDecline.Font = Enum.Font.GothamBold; reqDecline.TextSize = 15; reqDecline.TextColor3 = Color3.new(1,1,1); reqDecline.Text = "DECLINE"; reqDecline.Parent = reqPopup; uicorner(reqDecline,8)
reqAccept.MouseButton1Click:Connect(function() reqPopup.Visible = false; if PetTradeRespond then pcall(function() PetTradeRespond:FireServer(true) end) end end)
reqDecline.MouseButton1Click:Connect(function() reqPopup.Visible = false; if PetTradeRespond then pcall(function() PetTradeRespond:FireServer(false) end) end end)
if PetTradePrompt then PetTradePrompt.OnClientEvent:Connect(function(fromUserId, fromName)
	reqLbl.Text = "\xF0\x9F\x94\x81 " .. tostring(fromName) .. " wants to trade pets with you!"
	reqPopup.Visible = true
	task.delay(15, function() if reqPopup.Visible then reqPopup.Visible = false end end)
end) end

-- FLIGHT-ACHIEVEMENT progress (only if the server remote exists)
if PetProgressEvent then
	task.spawn(function()
		local TICK = 3
		while true do
			task.wait(TICK)
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if _G.equippedPetId and hrp then
				local peak = math.max(hrp.Position.Y, _G.peakHeight or 0)
				pcall(function() PetProgressEvent:FireServer(_G.equippedPetId, peak, TICK) end)
			end
		end
	end)
end

-- ============================================================================
-- (PETS HUD BUTTON removed) -- the Pet Hub is opened via the PetInvToggle
-- BindableEvent (e.g. from the More+ menu / server), not an on-screen button.
-- ============================================================================

-- ============================================================================
-- DEMO INVENTORY -- shown standalone so you can SEE the Hub populated. As soon
-- as the real server fires PetInventoryEvent, this is overwritten with live data.
-- ============================================================================
if not PetInventoryEvent then
	rebuildInventory({
		totalPets = 5,
		owned = {
			BroccoliPet  = { petId="BroccoliPet",  displayName="Broccoli Bunny", level=4,  xp=120, xpNeed=200, maxLevel=25, equipped=true,  milestone="Lv 6 -> Kid age" },
			CoconutCrab  = { petId="CoconutCrab",  displayName="Coconut Crab",   level=12, xp=80,  xpNeed=300, maxLevel=25, milestone="Lv 16 -> Adult age" },
			PopcornSheep = { petId="PopcornSheep", displayName="Popcorn Sheep",  level=22, xp=40,  xpNeed=400, maxLevel=25, count=2, milestone="Lv 25 -> MAX" },
			["ButterDuck#R"] = { petId="ButterDuck", displayName="Butter Duck", rareName="Cosmic Duck", rare=true, level=25, xp=0, xpNeed=0, maxLevel=25, milestone="Maxed Mythical" },
		},
		quests = {
			b = { islandName="Broccoli Bluff",  status="done",       desc="Find 3 hidden broccoli pieces, then hatch the egg." },
			c = { islandName="Coconut Cove",    status="inprogress", found=4, total=7, unit="coconuts", desc="Crack 7 coconuts to earn the Cave Key, open the chest." },
			p = { islandName="Popcorn Pinnacle",status="available",  desc="Find 6 film reels, load the projector, watch the show." },
		},
	})
	print("[PetHub] no server remotes found -> showing DEMO inventory. Open via the More+ menu's Pets card.")
end

print("[PetHub] ready -- 4-tab hub (PETS/CRATES/TRADE/QUESTS) opens via _G.togglePetHub / the PetInvToggle event")
