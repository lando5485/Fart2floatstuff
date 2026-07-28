--======================================================================
-- MoreMenuKit_AllInOne.client.lua  (LocalScript -- StarterPlayer > StarterPlayerScripts)
--======================================================================
-- EXACT COPY of everything behind Fart to Float's pink MORE+ button:
--
--   1. The MORE rail button          -- 95x95 pink, slot 4 of the left rail
--   2. The MORE+ popup (MoreMenuGui) -- 196x206 pink window that pops out to the
--      RIGHT of the button, with a scrolling list of 7 entry rows
--   3. The "!" ready-dot + wiggle    -- two INDEPENDENT dot groups (daily crate /
--      daily tasks) and a shared ±8° button wiggle
--   4. The Seasonal Pets LOCKER      -- the full 700x520 wood-and-garden panel that
--      the "Seasonal Pets" row opens (built in the same block in CoreClient, and
--      reachable from nowhere else)
--
-- Extracted verbatim from src/client/CoreClient.client.lua (the MORE+ POPUP MENU +
-- SEASONAL LOCKER block) and the rail button's final restyled values.
--
-- The other 6 rows open panels owned by OTHER scripts (Rebirth, Daily Tasks, Pet
-- Inventory, Pet Wheel, Free Rewards, Season Pass). Those panels are NOT in here --
-- this kit is the MENU, not every destination. Each row's action is guarded, and
-- CONFIG.hideMissingEntries controls what happens to a row whose target doesn't
-- exist in the realm you drop this into.
--
-- ┌─ WHAT TO CHANGE PER REALM ────────────────────────────────────────┐
-- │ 1. CONFIG.entries -- add/remove/reorder rows. It's data-driven:    │
-- │    { label, emoji OR image, action, readyDot, tasksDot, color }.   │
-- │ 2. CONFIG.hideMissingEntries -- true (default) hides rows whose     │
-- │    target isn't in this realm; false shows them with a banner.      │
-- │ 3. CONFIG.showSeasonalLocker -- false drops the whole locker panel.  │
-- │ 4. CONFIG.seasons -- the 4 season cards (pet ids, template names,    │
-- │    colours, blurbs).                                                │
-- │ 5. CONFIG.buildMoreButton = false if the realm's own sidebar has a  │
-- │    MORE button; call _G.toggleMorePopup() from it instead.          │
-- └────────────────────────────────────────────────────────────────────┘
--======================================================================

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local RSx       = ReplicatedStorage
local WHT       = Color3.new(1,1,1)

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

--======================================================================
-- CONFIG
--======================================================================
local CONFIG = {
	buildMoreButton = true,
	moreButtonY     = 417,  -- desktop rail slot 4 (grid 96 / 203 / 310 / 417, 107px pitch)

	-- The live game closes the popup on a tap outside. That contradicts the house rule for
	-- MENUS (X button only) -- but this is a small pop-out, not a panel, and it's what ships.
	-- Set false for X-only if you want the popup to follow the menu rule too.
	closeOnTapOutside = true,

	hideMissingEntries  = true,  -- a row whose _G hook doesn't exist in this realm is hidden
	showSeasonalLocker  = true,

	uiClickSound = "rbxassetid://101638558691673", -- volume 0.5

	-- ===== THE ROWS =====
	-- `needs` is the global/GUI the action depends on; used only by hideMissingEntries.
	entries = {
		{ label = "Rebirth",       emoji = "\xF0\x9F\x94\x84", needs = "toggleRebirth",
		  action = function() if _G.toggleRebirth then _G.toggleRebirth() end end },

		-- ONE daily entry. "Daily Rewards" and "Daily Tasks" used to be two rows for one habit, and a
		-- player had to already know they were different menus. The Daily Tasks panel now carries the
		-- crate as a DAILY REWARD button in its bottom row, so this opens the panel and BOTH dots ride
		-- on this single row.
		{ label = "Daily",         emoji = "\xF0\x9F\x8E\x81", readyDot = true, tasksDot = true, needs = "toggleDailyTasks",
		  action = function()
			-- Eligible -> open the panel (the crate button is in it). Not eligible yet (a brand-new
			-- player has no task list) -> the panel would refuse to open, so fire the crate directly.
			-- The daily reward is never unreachable either way.
			if _G.dailyTasksAvailable and _G.dailyTasksAvailable() then
				if _G.toggleDailyTasks then _G.toggleDailyTasks() end
			else
				local ev = RSx:FindFirstChild("OpenMeteorCrate")
				if not ev then ev = Instance.new("BindableEvent"); ev.Name = "OpenMeteorCrate"; ev.Parent = RSx end
				ev:Fire()
			end
		  end },

		{ label = "Pets",          emoji = "\xF0\x9F\x90\xBE", needs = "gui:PetInvToggle",
		  action = function() local ev = PlayerGui:FindFirstChild("PetInvToggle"); if ev then ev:Fire() end end },

		{ label = "Pet Wheel",     emoji = "\xF0\x9F\x8E\xA1", needs = "togglePetWheel",
		  action = function() if _G.togglePetWheel then _G.togglePetWheel() end end },

		{ label = "Seasonal Pets", emoji = "\xF0\x9F\x90\xBE", needs = "locker",
		  action = function() if _G.openSeasonalLocker then _G.openSeasonalLocker() end end },

		{ label = "Free Rewards",  emoji = "\xF0\x9F\x8E\x81", needs = "toggleSocialRewards",
		  action = function() if _G.toggleSocialRewards then _G.toggleSocialRewards() end end },

		{ label = "Season Pass",   emoji = "\xE2\xAD\x90",     needs = "toggleSeasonPass",
		  action = function() if _G.toggleSeasonPass then _G.toggleSeasonPass() end end },
	},

	-- ===== THE SEASONAL LOCKER =====
	locker = {
		title     = "Seasonal Pets",
		titleIcon = "\xF0\x9F\x8C\xBB",
		subtitle  = "Grow the Community Garden each season to unlock exclusive pets!",
		footer    = "New seasons, new rewards. Keep growing!",
		goalNoun  = "Flowers",
		defaultGoal = 2000,
	},
	seasons = {
		{ season="Summer", petId="SunflowerBee", petName="Sunflower Bee", tmpl="SunflowerBeeTemplate", icon="\xF0\x9F\x8C\xBB", card=Color3.fromRGB(250,243,205), accent=Color3.fromRGB(232,180,50), desc="A cheerful honeybee wrapped in sunflower petals -- the Summer harvest reward." },
		{ season="Autumn", petId="MapleFox",     petName="Maple Fox",     tmpl="MapleFoxTemplate",     icon="\xF0\x9F\x8D\x81", card=Color3.fromRGB(246,206,170), accent=Color3.fromRGB(214,118,46), desc="A cozy little fox in warm autumn colors -- the Autumn harvest reward." },
		{ season="Winter", petId="FrostPenguin", petName="Frost Penguin", tmpl="FrostPenguinTemplate", icon="\xE2\x9D\x84",     card=Color3.fromRGB(208,226,246), accent=Color3.fromRGB(86,148,206),  desc="A frosty penguin topped with little ice crystals -- the Winter harvest reward." },
		{ season="Spring", petId="BlossomBunny", petName="Blossom Bunny", tmpl="BlossomBunnyTemplate", icon="\xF0\x9F\x8C\xB8", card=Color3.fromRGB(248,216,228), accent=Color3.fromRGB(228,128,168), desc="A gentle bunny wearing a fresh flower crown -- the Spring harvest reward." },
	},
}

--======================================================================
-- GUI HELPERS (verbatim from CoreClient)
--======================================================================
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

-- ===== UI CLICK SOUND (self-contained, shared via _G) =====
local uiClickSound = Instance.new("Sound")
uiClickSound.Name="UIClickSound_MoreMenu"; uiClickSound.SoundId=CONFIG.uiClickSound; uiClickSound.Volume=0.5; uiClickSound.Parent=PlayerGui
local function playUIClick()
	local s=uiClickSound:Clone(); s.Parent=PlayerGui; s:Play(); Debris:AddItem(s,3)
end
_G.playUIClick = _G.playUIClick or playUIClick

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY (shared manager; reuse the game's if present) =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible)
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local g = pg and pg:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h=mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name; mgr.setHud(false)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
local function toggleMainMenu(name, guiName)
	local g = PlayerGui:FindFirstChild(guiName); if not g then return end
	if g.Enabled then
		g.Enabled = false; _G.MainMenuManager.notifyClosed(name)
	else
		_G.MainMenuManager.notifyOpened(name); g.Enabled = true
	end
end

--======================================================================
-- 1) THE MORE RAIL BUTTON
-- 95x95 at (0,12,0,417) -- slot 4. Pink 225,70,170, corner 14, WHITE stroke w2.
-- (The rail restyle pass touches SHOP / WORMHOLE / Stomach but NEVER MORE, so
-- MORE keeps the original corner 14 + white stroke while its neighbours get
-- corner 16 + coloured strokes. That asymmetry is the real look.)
--======================================================================
local moreSideFrame, moreSideClick
if CONFIG.buildMoreButton then
	local sidebarGui = PlayerGui:FindFirstChild("MoreMenuKitSidebarGui")
	if not sidebarGui then
		sidebarGui = Instance.new("ScreenGui")
		sidebarGui.Name = "MoreMenuKitSidebarGui"; sidebarGui.ResetOnSpawn = false
		sidebarGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- notch only (matches SidebarGui)
		sidebarGui.Parent = PlayerGui
	end
	moreSideFrame = mkFrame(sidebarGui,{
		Name="MoreButton", Size=UDim2.new(0,95,0,95), AnchorPoint=Vector2.new(0,0),
		Position=UDim2.new(0,12,0,CONFIG.moreButtonY), BackgroundColor3=Color3.fromRGB(225,70,170),
	})
	mkCorner(moreSideFrame,14); mkStroke(moreSideFrame,WHT,2)
	local iconL = mkLabel(moreSideFrame,{Text="+",Font=Enum.Font.Gotham,TextSize=30,Size=UDim2.new(1,0,0,56),Position=UDim2.new(0,0,0,0),RichText=true,TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(iconL,Color3.new(0,0,0),1)
	local textL = mkLabel(moreSideFrame,{Name="Label",Text="MORE",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=WHT,Size=UDim2.new(1,0,0,28),Position=UDim2.new(0,0,0,57),TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(textL,Color3.new(0,0,0),1)
	moreSideClick = mkButton(moreSideFrame,{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""})
end

--======================================================================
-- 2) THE SEASONAL PETS LOCKER
-- Built BEFORE the popup because the "Seasonal Pets" row opens it.
-- Expandable season cards + a big ViewportFrame pet preview, wired to the real
-- seasonal pets (equips through the SAME PetEquipEvent the pet inventory uses).
-- Ownership comes from PetStateEvent; live garden progress from the Workspace
-- GardenProgress / GardenGoal / GardenSeason attributes the server mirrors.
--======================================================================
local openLocker
if CONFIG.showSeasonalLocker then
	local PetEquipEvent = RSx:FindFirstChild("PetEquipEvent")
	local PetStateEvent = RSx:FindFirstChild("PetStateEvent")
	local PetReqState   = RSx:FindFirstChild("PetRequestStateEvent")
	local SEASONS = CONFIG.seasons
	local L = CONFIG.locker

	local seasonalOwned, seasonalEquipped = {}, nil
	local expanded = nil
	local cardRefreshers = {}
	local refreshLocker -- forward
	local lockerSpins = {} -- { {model, center}, ... } -- slow-spun while the locker is open

	local function gProgress() return tonumber(workspace:GetAttribute("GardenProgress")) or 0 end
	local function gGoal()     return tonumber(workspace:GetAttribute("GardenGoal")) or L.defaultGoal end
	local function gSeason()   return tostring(workspace:GetAttribute("GardenSeason") or SEASONS[1].season) end

	-- Render a pet template inside a ViewportFrame. LAZY-FILL because templates replicate a moment
	-- after join, so this is retried on every refresh until one lands. Built EXACTLY like the pet-
	-- inventory icons (root at origin, camera framed to the bounding box) so it spins the same way.
	local function fillViewport(vp, tmplName)
		if vp:FindFirstChildWhichIsA("Model") then return end
		local tmpl = RSx:FindFirstChild(tmplName); if not tmpl then return end
		local m = tmpl:Clone()
		for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end end
		pcall(function()
			m:PivotTo(CFrame.new()) -- root at origin (same as the inventory icons)
			m.Parent = vp
			local cam = Instance.new("Camera"); cam.FieldOfView = 50; cam.Parent = vp; vp.CurrentCamera = cam
			local cf, size = m:GetBoundingBox()
			local maxe = math.max(size.X, size.Y, size.Z, 1)
			local center = cf.Position
			local dir = Vector3.new(0.8, 0.5, 0.55).Unit -- 3/4 front view (pets face +X), slightly above
			cam.CFrame = CFrame.lookAt(center + dir * (maxe * 1.45 + 1), center)
			vp.Ambient = Color3.fromRGB(185,185,195); vp.LightColor = Color3.fromRGB(255,255,255); vp.LightDirection = Vector3.new(-0.4,-1,-0.5)
			lockerSpins[#lockerSpins+1] = { model = m, center = center } -- register for the shared spin loop
		end)
	end

	-- --- panel ---
	local lockerGui = Instance.new("ScreenGui"); lockerGui.Name = "LockerGui"; lockerGui.ResetOnSpawn = false
	-- EXACT same ScreenGui settings as the SHOP (PremiumShopGui): DisplayOrder 100, no IgnoreGuiInset
	lockerGui.DisplayOrder = 100; lockerGui.Enabled = false
	lockerGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	lockerGui.Parent = PlayerGui
	-- EXACT same Size + Position + AnchorPoint as the SHOP menu's final layout: 700x520 fixed,
	-- centered, nudged up 45px. No UIScale/UISizeConstraint/UIAspectRatioConstraint.
	local lockPanel = mkFrame(lockerGui, { Size = UDim2.new(0, 700, 0, 520), Position = UDim2.new(0.5, 0, 0.5, -45), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(245, 238, 214), ClipsDescendants = true })
	mkCorner(lockPanel, 18); mkStroke(lockPanel, Color3.fromRGB(120, 78, 40), 4)

	-- header (dark wood)
	local lockHead = mkFrame(lockPanel, { Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Color3.fromRGB(74, 48, 30), BorderSizePixel = 0 })
	mkLabel(lockHead, { Text = L.titleIcon, Font = Enum.Font.FredokaOne, TextSize = 20, Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(0, 16, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center })
	mkLabel(lockHead, { Text = L.title, Font = Enum.Font.FredokaOne, TextSize = 22, TextColor3 = WHT, Size = UDim2.new(1, -100, 1, 0), Position = UDim2.new(0, 50, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center })
	local lockX = mkButton(lockHead, { Size = UDim2.new(0, 34, 0, 34), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = Color3.fromRGB(210, 60, 55), Text = "X", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = WHT })
	mkCorner(lockX, 9)

	-- subtitle banner (dark-green pill with leaf accents)
	local sub = mkFrame(lockPanel, { Size = UDim2.new(1, -28, 0, 42), Position = UDim2.new(0, 14, 0, 60), BackgroundColor3 = Color3.fromRGB(58, 116, 52) })
	mkCorner(sub, 12)
	mkLabel(sub, { Text = "\xF0\x9F\x8C\xBF", Font = Enum.Font.FredokaOne, TextSize = 16, Size = UDim2.new(0, 24, 1, 0), Position = UDim2.new(0, 8, 0, 0), TextXAlignment = Enum.TextXAlignment.Center })
	mkLabel(sub, { Text = L.subtitle, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = WHT, TextWrapped = true, Size = UDim2.new(1, -64, 1, 0), Position = UDim2.new(0, 32, 0, 0), TextXAlignment = Enum.TextXAlignment.Center })
	mkLabel(sub, { Text = "\xF0\x9F\x8C\xBF", Font = Enum.Font.FredokaOne, TextSize = 16, Size = UDim2.new(0, 24, 1, 0), Position = UDim2.new(1, -32, 0, 0), TextXAlignment = Enum.TextXAlignment.Center })

	-- footer (small green strip)
	local lockFooter = mkFrame(lockPanel, { Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 1, -28), BackgroundColor3 = Color3.fromRGB(70, 130, 60), BorderSizePixel = 0 })
	mkLabel(lockFooter, { Text = L.footer, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = WHT, Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })

	-- scrolling list of season cards (between subtitle + footer)
	local scroll = Instance.new("ScrollingFrame"); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
	scroll.Position = UDim2.new(0, 12, 0, 110); scroll.Size = UDim2.new(1, -24, 1, -146); scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 78, 40); scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; scroll.Parent = lockPanel
	local slay = Instance.new("UIListLayout", scroll); slay.Padding = UDim.new(0, 10); slay.SortOrder = Enum.SortOrder.LayoutOrder; slay.HorizontalAlignment = Enum.HorizontalAlignment.Center

	for i, s in ipairs(SEASONS) do
		local card = mkFrame(scroll, { Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = s.card, LayoutOrder = i, ClipsDescendants = true })
		mkCorner(card, 14); mkStroke(card, s.accent, 2)
		local clay = Instance.new("UIListLayout", card); clay.SortOrder = Enum.SortOrder.LayoutOrder

		-- collapsed header row (the WHOLE row is the expand button)
		local hrow = mkButton(card, { Size = UDim2.new(1, 0, 0, 66), BackgroundTransparency = 1, Text = "", LayoutOrder = 1, AutoButtonColor = false })
		local mini = Instance.new("ViewportFrame"); mini.BackgroundColor3 = WHT; mini.BackgroundTransparency = 0.15
		mini.Size = UDim2.new(0, 52, 0, 52); mini.Position = UDim2.new(0, 8, 0.5, 0); mini.AnchorPoint = Vector2.new(0, 0.5); mini.Parent = hrow; mkCorner(mini, 10)
		mkLabel(hrow, { Text = s.icon, Font = Enum.Font.FredokaOne, TextSize = 18, Size = UDim2.new(0, 22, 0, 18), Position = UDim2.new(0, 70, 0, 10), BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left })
		mkLabel(hrow, { Text = s.season:upper(), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = s.accent, Size = UDim2.new(0, 150, 0, 18), Position = UDim2.new(0, 94, 0, 10), TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1 })
		mkLabel(hrow, { Text = s.petName, Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = Color3.fromRGB(60, 45, 30), Size = UDim2.new(0, 220, 0, 24), Position = UDim2.new(0, 70, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1 })
		local pill = mkLabel(hrow, { Text = "LOCKED", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHT, Size = UDim2.new(0, 84, 0, 26), Position = UDim2.new(1, -118, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.fromRGB(150, 120, 90), TextXAlignment = Enum.TextXAlignment.Center }); mkCorner(pill, 13)
		local chev = mkLabel(hrow, { Text = "v", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = s.accent, Size = UDim2.new(0, 24, 1, 0), Position = UDim2.new(1, -28, 0, 0), TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 1 })

		-- expanded content (hidden until this row is the open one)
		local exp = mkFrame(card, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2, Visible = false })
		local ep = Instance.new("UIPadding", exp); ep.PaddingLeft = UDim.new(0, 12); ep.PaddingRight = UDim.new(0, 12); ep.PaddingBottom = UDim.new(0, 12)
		local el = Instance.new("UIListLayout", exp); el.Padding = UDim.new(0, 8); el.SortOrder = Enum.SortOrder.LayoutOrder; el.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local big = Instance.new("ViewportFrame"); big.BackgroundColor3 = WHT; big.BackgroundTransparency = 0.05; big.Size = UDim2.new(1, 0, 0, 150); big.LayoutOrder = 1; big.Parent = exp; mkCorner(big, 12); mkStroke(big, s.accent, 2)
		mkLabel(exp, { Text = s.season:upper() .. " REWARD", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = s.accent, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 1 })
		mkLabel(exp, { Text = s.petName, Font = Enum.Font.FredokaOne, TextSize = 24, TextColor3 = Color3.fromRGB(60, 45, 30), Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 1 })
		local barBG = mkFrame(exp, { Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = Color3.fromRGB(225, 215, 190), LayoutOrder = 4 }); mkCorner(barBG, 11)
		local barFill = mkFrame(barBG, { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(90, 200, 80) }); mkCorner(barFill, 11)
		local barTxt = mkLabel(barBG, { Text = "0 / " .. L.defaultGoal .. " " .. L.goalNoun, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.fromRGB(60, 50, 40), Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3, BackgroundTransparency = 1 })
		mkLabel(exp, { Text = s.desc, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Color3.fromRGB(80, 65, 45), TextWrapped = true, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 5, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 1 })
		local equipBtn = mkButton(exp, { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.fromRGB(70, 150, 55), Text = "EQUIP", Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = WHT, LayoutOrder = 6 }); mkCorner(equipBtn, 12)

		-- ACCORDION: clicking a header opens that card and closes whichever was open (nil = all closed)
		hrow.MouseButton1Click:Connect(function() playUIClick(); expanded = (expanded == s.season) and nil or s.season; refreshLocker() end)
		equipBtn.MouseButton1Click:Connect(function()
			playUIClick()
			if not seasonalOwned[s.petId] or not PetEquipEvent then return end
			if seasonalEquipped == s.petId then pcall(function() PetEquipEvent:FireServer(false) end) -- toggle off (same as inventory)
			else pcall(function() PetEquipEvent:FireServer(s.petId) end) end
		end)

		cardRefreshers[i] = function()
			fillViewport(mini, s.tmpl); fillViewport(big, s.tmpl)
			local owns = seasonalOwned[s.petId] == true
			local isExp = (expanded == s.season)
			chev.Text = isExp and "^" or "v"; exp.Visible = isExp
			if owns then
				if seasonalEquipped == s.petId then pill.Text = "EQUIPPED"; pill.BackgroundColor3 = Color3.fromRGB(70, 150, 55)
				else pill.Text = "OWNED"; pill.BackgroundColor3 = Color3.fromRGB(90, 160, 210) end
			else pill.Text = "LOCKED"; pill.BackgroundColor3 = Color3.fromRGB(150, 120, 90) end
			-- Progress rule: owned -> full bar + "Earned ✓". The CURRENT season -> live garden progress.
			-- Any other season -> 0, because only the active season's garden counts toward it.
			local cur, p, g = gSeason(), gProgress(), gGoal()
			local frac, label
			if owns then frac, label = 1, "Earned \xE2\x9C\x93"
			elseif s.season == cur then frac, label = math.clamp(p / g, 0, 1), string.format("%d / %d " .. L.goalNoun, p, g)
			else frac, label = 0, "0 / " .. g .. " " .. L.goalNoun end
			barFill.Size = UDim2.new(frac, 0, 1, 0); barTxt.Text = label
			equipBtn.Visible = owns
			equipBtn.Text = (seasonalEquipped == s.petId) and "EQUIPPED \xE2\x9C\x93" or "EQUIP"
			equipBtn.BackgroundColor3 = (seasonalEquipped == s.petId) and Color3.fromRGB(120, 160, 110) or Color3.fromRGB(70, 150, 55)
		end
	end

	refreshLocker = function() for _, fn in ipairs(cardRefreshers) do pcall(fn) end end

	-- live ownership from the pet system (same source the inventory uses) + live garden progress
	if PetStateEvent then
		PetStateEvent.OnClientEvent:Connect(function(state)
			if type(state) ~= "table" then return end
			for _, s in ipairs(SEASONS) do
				local info = state[s.petId]
				if info then
					seasonalOwned[s.petId] = info.owns == true
					if info.equipped then seasonalEquipped = s.petId elseif seasonalEquipped == s.petId then seasonalEquipped = nil end
				end
			end
			if lockerGui.Enabled then refreshLocker() end
		end)
	end
	workspace:GetAttributeChangedSignal("GardenProgress"):Connect(function() if lockerGui.Enabled then refreshLocker() end end)
	workspace:GetAttributeChangedSignal("GardenSeason"):Connect(function() if lockerGui.Enabled then refreshLocker() end end)

	-- SLOW AUTO-ROTATE for every locker pet ViewportFrame (mini thumbnails + big preview) -- EXACT same
	-- approach as the pet inventory icons (Y-axis PivotTo about the bounding-box centre at dt*0.6, and
	-- ONLY while the menu is open so it costs nothing the rest of the time).
	do
		local angle = 0
		RunService.RenderStepped:Connect(function(dt)
			if not lockerGui.Enabled or #lockerSpins == 0 then return end
			angle = (angle + dt * 0.6) % (2 * math.pi)
			for i = #lockerSpins, 1, -1 do
				local ic = lockerSpins[i]
				if ic.model and ic.model.Parent then
					ic.model:PivotTo(CFrame.new(ic.center) * CFrame.Angles(0, angle, 0) * CFrame.new(-ic.center))
				else
					table.remove(lockerSpins, i)
				end
			end
		end)
	end

	_G.MainMenuManager.register("Locker", function() lockerGui.Enabled = false end) -- closed when another menu opens
	lockX.MouseButton1Click:Connect(function() playUIClick(); lockerGui.Enabled = false; _G.MainMenuManager.notifyClosed("Locker") end)

	openLocker = function()
		if PetReqState then pcall(function() PetReqState:FireServer() end) end -- refresh ownership from the server
		expanded = expanded or SEASONS[1].season -- default: first card open (matches the reference)
		refreshLocker()
		toggleMainMenu("Locker", "LockerGui")
		-- re-apply the SHOP's identical UIScale so this panel resolves to the same on-screen size
		if _G.applyHudScaling then _G.applyHudScaling() end
	end
	_G.openSeasonalLocker = openLocker
end

--======================================================================
-- 3) THE MORE+ POPUP ITSELF
-- A small pink rounded window that pops out to the RIGHT of the MORE button.
-- FIXED 196x206 (~3 entries tall) with an inner ScrollingFrame, so the 7 rows
-- overflow and scroll rather than the window growing off-screen.
--======================================================================
local setMoreOpen
local moreOpenState = false

do
	local moreGui = Instance.new("ScreenGui"); moreGui.Name = "MoreMenuGui"; moreGui.ResetOnSpawn = false
	moreGui.DisplayOrder = 8
	moreGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- topbar + notch (its buttons are children, so they shift with it)
	moreGui.Parent = PlayerGui

	-- tap-outside-to-close catcher (see CONFIG.closeOnTapOutside)
	local catcher = mkButton(moreGui, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 1, Visible = false })

	local panel = mkFrame(moreGui, { Size = UDim2.new(0, 196, 0, 206), BackgroundColor3 = Color3.fromRGB(225, 70, 170), Visible = false, ZIndex = 2 })
	mkCorner(panel, 14); mkStroke(panel, WHT, 2)
	local pad = Instance.new("UIPadding", panel); pad.PaddingTop = UDim.new(0, 8); pad.PaddingBottom = UDim.new(0, 8); pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)

	-- header pinned at the top. The panel deliberately does NOT use a UIListLayout (it mirrors the
	-- Locker's manual layout) -- that's what lets the inner scroll's canvas actually compute.
	local hdr = mkFrame(panel, { Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1, ZIndex = 2 })
	mkLabel(hdr, { Text = "MORE", Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = WHT, Size = UDim2.new(1, -32, 1, 0), Position = UDim2.new(0, 4, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	local moreX = mkButton(hdr, { Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -26, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.fromRGB(210, 60, 55), Text = "X", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = WHT, ZIndex = 3 })
	mkCorner(moreX, 8)

	-- Entry-list scroll: a real ScrollingFrame whose canvas Roblox auto-measures from the UIListLayout's
	-- children. The entry buttons are parented DIRECTLY into this ScrollingFrame (no intermediate Frame),
	-- so the layout + AutomaticCanvasSize can measure them and the list scrolls once the content is
	-- taller than the window.
	local entryScroll = Instance.new("ScrollingFrame")
	entryScroll.Name = "EntryList"
	entryScroll.BackgroundTransparency = 1 -- seamless: the panel's pink shows through
	entryScroll.BorderSizePixel = 0
	entryScroll.Position = UDim2.new(0, 0, 0, 36) -- below the 28px header + 8px gap (within the panel's 8px padding)
	entryScroll.Size = UDim2.new(1, 0, 1, -36)    -- SCALE height off the FIXED panel -> a real bounded window
	entryScroll.ScrollingEnabled = true
	entryScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	entryScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	entryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y -- Roblox measures the canvas from the children
	entryScroll.ScrollBarThickness = 6
	entryScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 215, 0) -- gold, same as the pet inventory
	entryScroll.ClipsDescendants = true
	entryScroll.ZIndex = 2
	entryScroll.Parent = panel
	local entryListLayout = Instance.new("UIListLayout"); entryListLayout.SortOrder = Enum.SortOrder.LayoutOrder; entryListLayout.Padding = UDim.new(0, 8); entryListLayout.Parent = entryScroll

	-- ===== READY "!" DOT INFRASTRUCTURE =====
	-- TWO INDEPENDENT groups on purpose: claiming the daily crate must not clear the daily-tasks dot,
	-- and finishing your tasks must not clear the crate's. They just happen to share one wiggle.
	local crateReadyDots = {}
	local taskPendingDots = {}
	local function mkCrateDot(parent, list)
		local dot = Instance.new("Frame")
		dot.Name = "CrateReadyDot"
		dot.Size = UDim2.fromOffset(18, 18)
		dot.AnchorPoint = Vector2.new(1, 0)
		dot.Position = UDim2.new(1, -2, 0, -2)
		dot.BackgroundColor3 = Color3.fromRGB(225, 50, 50)
		dot.ZIndex = 8
		dot.Visible = false
		dot.Parent = parent
		local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot
		local bang = Instance.new("TextLabel")
		bang.BackgroundTransparency = 1; bang.Size = UDim2.fromScale(1, 1)
		bang.Font = Enum.Font.GothamBlack; bang.Text = "!"; bang.TextSize = 13
		bang.TextColor3 = WHT; bang.ZIndex = 9; bang.Parent = dot
		local group = list or crateReadyDots
		group[#group + 1] = dot
		return dot
	end

	-- ===== THE ROWS =====
	-- 46 tall, full width, near-white 248,240,250 on the pink panel, corner 10; a 30px emoji/image
	-- icon at x8 and the label at x46 in dark plum 70,40,65. Clicking a row plays the click, CLOSES
	-- the popup, then runs the action.
	local function entryTargetExists(e)
		if not e.needs then return true end
		if e.needs == "locker" then return openLocker ~= nil end
		local guiName = e.needs:match("^gui:(.+)$")
		if guiName then return PlayerGui:FindFirstChild(guiName) ~= nil end
		return _G[e.needs] ~= nil
	end

	local shownCount = 0
	for i, e in ipairs(CONFIG.entries) do
		local row = mkButton(entryScroll, { Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = e.color or Color3.fromRGB(248, 240, 250), Text = "", ZIndex = 2, LayoutOrder = i })
		mkCorner(row, 10)
		if e.readyDot then mkCrateDot(row, crateReadyDots) end
		if e.tasksDot then mkCrateDot(row, taskPendingDots) end
		if e.image then
			local im = Instance.new("ImageLabel"); im.BackgroundTransparency = 1; im.Image = e.image; im.ScaleType = Enum.ScaleType.Fit
			im.Size = UDim2.new(0, 30, 0, 30); im.Position = UDim2.new(0, 8, 0.5, 0); im.AnchorPoint = Vector2.new(0, 0.5); im.ZIndex = 3; im.Parent = row
		else
			mkLabel(row, { Text = e.emoji or "", Font = Enum.Font.Gotham, TextSize = 22, Size = UDim2.new(0, 30, 1, 0), Position = UDim2.new(0, 8, 0, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		end
		mkLabel(row, { Text = e.label, Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.fromRGB(70, 40, 65), Size = UDim2.new(1, -50, 1, 0), Position = UDim2.new(0, 46, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
		row.MouseButton1Click:Connect(function()
			playUIClick(); setMoreOpen(false)
			if not entryTargetExists(e) and _G.showHudBanner then
				_G.showHudBanner(e.label .. " isn't set up in this realm yet!", Color3.fromRGB(255,150,90), 3)
				return
			end
			pcall(e.action)
		end)
		-- Rows whose target doesn't exist in this realm: hide them (the scroll re-measures itself, so
		-- the list just gets shorter -- no gap). Re-checked for a few seconds because the scripts that
		-- define those globals may still be loading.
		if CONFIG.hideMissingEntries then
			local function recheck() row.Visible = entryTargetExists(e) end
			recheck()
			task.spawn(function() for _ = 1, 10 do task.wait(1); recheck() end end)
		end
		shownCount += 1
	end

	-- ===== "!" DOT + WIGGLE ON THE MORE BUTTON ITSELF =====
	local moreWiggling, moreWiggleTween = false, nil
	if moreSideFrame then
		mkCrateDot(moreSideFrame, crateReadyDots)
		-- Wiggle the WHOLE MORE+ button whenever the daily crate is claimable OR the daily tasks are
		-- unfinished -- the same ±8° oscillation the gut button uses.
		local function stopMoreWiggle()
			if not moreWiggling then return end
			moreWiggling = false
			if moreWiggleTween then pcall(function() moreWiggleTween:Cancel() end); moreWiggleTween = nil end
			moreSideFrame.Rotation = 0
		end
		local function startMoreWiggle()
			if moreWiggling then return end
			moreWiggling = true
			moreSideFrame.Rotation = -8
			local info = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
			moreWiggleTween = TweenService:Create(moreSideFrame, info, { Rotation = 8 })
			moreWiggleTween:Play()
		end
		task.spawn(function() -- poll every 1s; toggles the row dots + MORE-button dot + wiggle
			while true do
				local ready   = (_G.crateIsClaimable and _G.crateIsClaimable()) == true
				local pending = (_G.dailyTasksPending and _G.dailyTasksPending()) == true
				for _, d in ipairs(crateReadyDots)  do d.Visible = ready   end
				for _, d in ipairs(taskPendingDots) do d.Visible = pending end
				if ready or pending then startMoreWiggle() else stopMoreWiggle() end
				task.wait(1)
			end
		end)
	end

	-- ===== OPEN / CLOSE =====
	-- The panel is positioned from the button's LIVE AbsolutePosition/AbsoluteSize each time it opens,
	-- so it lands correctly whatever the rail scale / device / layout is -- no hardcoded coordinates.
	setMoreOpen = function(open)
		moreOpenState = open and true or false
		if moreOpenState then
			if moreSideFrame then
				local ap, asz = moreSideFrame.AbsolutePosition, moreSideFrame.AbsoluteSize
				panel.Position = UDim2.fromOffset(ap.X + asz.X + 10, ap.Y) -- just to the RIGHT of the MORE+ button
			end
			panel.Visible = true; catcher.Visible = CONFIG.closeOnTapOutside
		else
			panel.Visible = false; catcher.Visible = false
		end
	end
	_G.toggleMorePopup = function() setMoreOpen(not moreOpenState) end

	catcher.MouseButton1Click:Connect(function() setMoreOpen(false) end)
	moreX.MouseButton1Click:Connect(function() playUIClick(); setMoreOpen(false) end)

	if moreSideClick then
		moreSideClick.MouseButton1Click:Connect(function() playUIClick(); setMoreOpen(not moreOpenState) end)
	end

	task.spawn(function() -- print AFTER the layout has measured; scrolls when contentY > frameY
		task.wait(0.3)
		print(string.format("[MOREMENU] scroll: frameY=%d contentY=%d canvasY=%d entries=%d (scrolls if contentY>frameY)",
			math.floor(entryScroll.AbsoluteSize.Y), math.floor(entryListLayout.AbsoluteContentSize.Y),
			math.floor(entryScroll.AbsoluteCanvasSize.Y), shownCount))
	end)
end

--======================================================================
-- MOBILE SCALING + POSITION (the game's exact pass, scoped to this kit)
-- Phone caps at 0.60, tablet/iPad scales up to 2.5, desktop is exactly 1.
-- The POPUP is deliberately NOT scaled -- it's positioned from the button's live
-- AbsolutePosition each open, so it follows the scaled rail on its own.
--======================================================================
local function getScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	if vp.X <= 1 or vp.Y <= 1 then return isMobile and 0.60 or 1 end -- boot: viewport not valid yet
	if isMobile then
		-- iPhone SE/8 landscape reference (1100x590), clamped by device CLASS (viewport short axis).
		local deviceMax = (math.min(vp.X, vp.Y) >= 800) and 2.5 or 0.60
		return math.clamp(math.min(vp.X / 1100, vp.Y / 590), 0.55, deviceMax)
	end
	return 1
end

local function repositionMoreButton()
	if not moreSideFrame then return end
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
	local phoneClass = isMobile and math.min(vp.X, vp.Y) < 800
	local s = getScale()
	-- Rail pitch is recomputed from the LIVE scale on mobile: the 4 buttons are separate fixed-offset
	-- frames, so a UIScale sizes each one but leaves the GAPS fixed -- which spreads them out when
	-- scaled down (phone) and OVERLAPS them when scaled up (iPad).
	--   PHONE-class: pitch 101*s, rail top y66 (clears the joystick)
	--   TABLET/iPad: pitch 107*s, authored top y96
	--   DESKTOP:     the exact authored grid, unchanged
	local slot = math.floor((CONFIG.moreButtonY - 96) / 107 + 0.5) -- which rail slot this y represents
	if isMobile then
		local pitch = math.floor((phoneClass and 101 or 107) * s + 0.5)
		local topY = phoneClass and 66 or 96
		moreSideFrame.Position = UDim2.new(0, 12, 0, topY + pitch * slot)
	else
		moreSideFrame.Position = UDim2.new(0, 12, 0, CONFIG.moreButtonY)
	end
	moreSideFrame.Size = UDim2.new(0,95,0,95); moreSideFrame.AnchorPoint = Vector2.new(0,0)
	local us = moreSideFrame:FindFirstChildWhichIsA("UIScale")
	if not us then us = Instance.new("UIScale"); us.Parent = moreSideFrame end
	us.Scale = s
end
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(repositionMoreButton)
end
repositionMoreButton()
task.delay(3, repositionMoreButton)

print("[MoreMenuKit] MORE button + MORE+ popup" .. (CONFIG.showSeasonalLocker and " + Seasonal Pets locker" or "") .. " built")
