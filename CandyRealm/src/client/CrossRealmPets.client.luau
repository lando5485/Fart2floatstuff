--======================================================================
-- CrossRealmPets.client.luau  (StarterPlayerScripts)  -- CandyRealm
--======================================================================
-- THE FOOD REALM AND DINO REALM PET COLLECTIONS, shown read-only on their own tabs in Candy's pet hub.
--
-- Ported from the Dino Realm's PetHub.client.luau FOOD tab (buildFoodOwnedCard / buildFoodLockedCard /
-- rebuildFoodPets, around line 960) -- same card geometry, same colours, same wording, same two-column
-- 264px grid. Generalised to drive TWO catalogs instead of one, because Candy sits downstream of both
-- realms and a player can arrive owning pets from either.
--
-- ===== THE WHOLE POINT: EVERY PET IS ALWAYS SHOWN =====
-- Un-owned pets get the SAME card and the SAME full-colour picture as owned ones. The only differences
-- are a padlock badge, a gold border and a gold LOCKED line naming where it lives. Greying them out or
-- hiding them would be easier and much worse: seeing the actual prize is what makes a player want it, and
-- a hidden pet cannot advertise the realm it belongs to.
--
-- Every locked card says, in as many words, GO BACK TO THAT REALM:
--     🔒 LOCKED  •  Bean Farm
--     Food Realm   ·   Pet 1 of 11
--     Return to the Food Realm to complete this pet's quest
--     [ 🔒 RETURN TO FOOD REALM TO COMPLETE ]
-- ...and the dino tab says the same with "Dino Realm" throughout.
--
-- ===== READ-ONLY BY CONSTRUCTION =====
-- Nothing here can equip, level or trade -- those pets' systems do not exist in this place, and pretending
-- otherwise would be a button that lies. Owned cards carry an informational "EQUIP & LEVEL IN THE …
-- REALM" strip instead, which is a statement, not a teleport.
--
-- ===== WHY IT LIVES IN ITS OWN FILE =====
-- PetHub_AllInOne is already 880 lines and owns Candy's own pets, crates, trade and quests. This attaches
-- through the small seam that file exposes (_G.PetHub.registerPage) so neither script has to know how the
-- other builds its UI.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer

local PetsEvent = ReplicatedStorage:WaitForChild("CrossRealmPetsEvent", 30)
local PetsFunc  = ReplicatedStorage:WaitForChild("CrossRealmPetsFunc", 30)
if not (PetsEvent and PetsFunc) then
	warn("[CrossRealmPets] remotes missing -> the Food/Dino pet tabs will not build")
	return
end

--======================================================================
-- THE CATALOGS
--======================================================================
-- `where` is the island the pet is earned on, and it is what the locked line names. It is deliberately
-- the ISLAND and not the realm: "LOCKED • Bean Farm" tells a player something they can act on, where
-- "LOCKED • Food Realm" only repeats the tab they are already looking at. The realm is named on the two
-- lines underneath.
-- ⚠ `tmpl` IS NOT DERIVABLE FROM `key`, WHICH IS WHY IT IS WRITTEN OUT.
--
-- The obvious `key .. "Template"` is wrong for a third of these: the inventory key is BroccoliPet but the
-- model is BroccoliBunnyTemplate; the key is StegoPet but the model is StegosaurusTemplate. Those pairs
-- were named years apart by different systems and never reconciled. Guessing produces a name that simply
-- is not in ReplicatedStorage, and the card silently falls back to its emoji -- a failure that looks like
-- "the render didn't load" rather than "the lookup was wrong". Naming each one makes it checkable.
local FOOD_CATALOG = {
	{ key = "BeanBuddy",        tmpl = "BeanBuddyTemplate",        displayName = "Bean Buddy",        where = "Bean Farm",                        emoji = "\xF0\x9F\x8C\xB1" },
	{ key = "BroccoliPet",      tmpl = "BroccoliBunnyTemplate",    displayName = "Broccoli Bunny",    where = "Broccoli Bluff",                   emoji = "\xF0\x9F\xA5\xA6" },
	{ key = "CoconutCrab",      tmpl = "CoconutCrabTemplate",      displayName = "Coconut Crab",      where = "Coconut Cove",                     emoji = "\xF0\x9F\xA6\x80" },
	{ key = "PopcornSheep",     tmpl = "PopcornSheepTemplate",     displayName = "Popcorn Sheep",     where = "Popcorn Pinnacle",                 emoji = "\xF0\x9F\x8D\xBF" },
	{ key = "ButterDuck",       tmpl = "ButterDuckTemplate",       displayName = "Butter Duck",       where = "Butter Swamp",                     emoji = "\xF0\x9F\xA6\x86" },
	{ key = "BurritoArmadillo", tmpl = "BurritoArmadilloTemplate", displayName = "Burrito Armadillo", where = "Burrito Barrens",                  emoji = "\xF0\x9F\x8C\xAF" },
	{ key = "SunflowerBee",     tmpl = "SunflowerBeeTemplate",     displayName = "Sunflower Bee",     where = "Community Garden \xC2\xB7 Summer", emoji = "\xF0\x9F\x8C\xBB" },
	{ key = "MapleFox",         tmpl = "MapleFoxTemplate",         displayName = "Maple Fox",         where = "Community Garden \xC2\xB7 Autumn", emoji = "\xF0\x9F\x8D\x81" },
	{ key = "FrostPenguin",     tmpl = "FrostPenguinTemplate",     displayName = "Frost Penguin",     where = "Community Garden \xC2\xB7 Winter", emoji = "\xF0\x9F\x90\xA7" },
	{ key = "BlossomBunny",     tmpl = "BlossomBunnyTemplate",     displayName = "Blossom Bunny",     where = "Community Garden \xC2\xB7 Spring", emoji = "\xF0\x9F\x8C\xB8" },
	{ key = "PizzaDragon",      tmpl = "PizzaDragonTemplate",      displayName = "Pizza Dragon",      where = "Secret Pet",                       emoji = "\xF0\x9F\x8D\x95", secret = true },
}

-- Ordered by the Dino tower's climb slots, matching that realm's own hub. Template names are the ones the
-- Dino Realm's per-pet server scripts publish (StegosaurusTemplate, VelociraptorTemplate, ...), NOT the
-- inventory keys.
local DINO_CATALOG = {
	{ key = "StegoPet",         tmpl = "StegosaurusTemplate",   displayName = "Stegosaurus",  where = "Nesting Nook",     emoji = "\xF0\x9F\xA6\x95" },
	{ key = "SpinosaurusPet",   tmpl = "SpinosaurusTemplate",   displayName = "Spinosaurus",  where = "Misty Mire",       emoji = "\xF0\x9F\x90\x8A" },
	{ key = "RaptorPet",        tmpl = "VelociraptorTemplate",  displayName = "Velociraptor", where = "Fossil Frontier",  emoji = "\xF0\x9F\xA6\x96" },
	{ key = "SharkPet",         tmpl = "SharkTemplate",         displayName = "Megalodon",    where = "Coastal Crossing", emoji = "\xF0\x9F\xA6\x88" },
	{ key = "TriceratopsPet",   tmpl = "TriceratopsTemplate",   displayName = "Triceratops",  where = "Fern Frontier",    emoji = "\xF0\x9F\xA6\x8F" },
	{ key = "TyrannosaurusPet", tmpl = "TyrannosaurusTemplate", displayName = "T-Rex",        where = "Volcanic Vista",   emoji = "\xF0\x9F\xA6\x96" },
}

-- Rare variants ("#R") get their own name rather than a suffix, so the two realms' pets read as one
-- collection. Straight from the Dino hub's FOOD_RARE_NAMES.
local FOOD_RARE_NAMES = {
	BroccoliPet = "Emerald Bunny", CoconutCrab = "Golden Crab", PopcornSheep = "Cloud Sheep",
	BurritoArmadillo = "Crystal Armadillo", ButterDuck = "Cosmic Duck",
}
local DINO_RARE_NAMES = {
	StegoPet = "Crystal Stegosaurus", TriceratopsPet = "Obsidian Triceratops",
	RaptorPet = "Phantom Velociraptor", SharkPet = "Abyssal Megalodon",
	SpinosaurusPet = "Storm Spinosaurus", TyrannosaurusPet = "Molten T-Rex",
}

-- The two realms label levels differently and BOTH are preserved, because a word that means one thing in
-- one realm and another somewhere else is worse than no word. Food uses AGE words (rarity belongs to skin
-- crates over there); Dino uses the same four rarity words its crates use.
local function foodAge(level, isRare, petId)
	if isRare then
		if petId == "ButterDuck" then return "Mythical", Color3.fromRGB(255, 70, 230) end
		return "Exotic", Color3.fromRGB(40, 235, 225)
	end
	if level <= 5      then return "Baby",  Color3.fromRGB(175, 180, 190)
	elseif level <= 10 then return "Kid",   Color3.fromRGB(90, 210, 90)
	elseif level <= 15 then return "Teen",  Color3.fromRGB(255, 70, 171)
	elseif level <= 20 then return "Adult", Color3.fromRGB(180, 90, 235)
	else                    return "Elder", Color3.fromRGB(255, 170, 40) end
end
local function dinoAge(level, isRare)
	if isRare then return "Exotic", Color3.fromRGB(40, 235, 225) end
	if level <= 5      then return "Hatchling", Color3.fromRGB(175, 180, 190)
	elseif level <= 10 then return "Juvenile",  Color3.fromRGB(90, 210, 90)
	elseif level <= 15 then return "Adult",     Color3.fromRGB(255, 70, 171)
	elseif level <= 20 then return "Alpha",     Color3.fromRGB(180, 90, 235)
	else                    return "Apex",      Color3.fromRGB(255, 170, 40) end
end

-- The food realm's XP curve, so the bar on an owned card reads the same number it does at home.
local function xpNeeded(level)
	return 50 + (level - 1) * 25
end

--======================================================================
-- THE TWO REALMS, as data
--======================================================================
local REALMS = {
	food = {
		tabId     = "food",
		realmName = "Food Realm", headerName = "FOOD REALM", -- header names the realm; the tab bar already has a PETS tab
		icon      = "\xF0\x9F\x8D\x94",
		catalog   = FOOD_CATALOG,
		rareNames = FOOD_RARE_NAMES,
		ageOf     = foodAge,
		-- Template names the Food Realm publishes into ReplicatedStorage. Where one is present the card
		-- shows the REAL fused render; where it is not, the emoji placeholder stands in. Same
		-- single-source-of-truth idea as the Dino hub's foodTemplateIcon.
	},
	dino = {
		tabId     = "dino",
		realmName = "Dino Realm", headerName = "DINO REALM",
		icon      = "\xF0\x9F\xA6\x95",
		catalog   = DINO_CATALOG,
		rareNames = DINO_RARE_NAMES,
		ageOf     = function(level, isRare) return dinoAge(level, isRare) end,
		-- MYSTERY TAB. A locked dino shows a dinosaur silhouette with a question mark instead of the pet
		-- itself -- same reasoning as the wormhole's "? ? ?": naming and rendering every dinosaur from the
		-- first minute spends the surprise before the player has been there. The Food tab deliberately does
		-- NOT do this: those pets are the collection you are actively working on in the realm you came from,
		-- so seeing the prize is the point. Owned dinos still render normally -- you have met them.
		--
		-- It also fixes a real duplication: Velociraptor and T-Rex were both authored with the same
		-- placeholder emoji, so two cards on this tab were visibly the same picture.
		mystery   = true,
	},
}

--======================================================================
-- UI HELPERS (match the hub's own look)
--======================================================================
local function uicorner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function uistroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = o; return s end

local CARD_BLUE  = Color3.fromRGB(160, 20, 93)
local CARD_EDGE  = Color3.fromRGB(110, 12, 60)
local GOLD_EDGE  = Color3.fromRGB(255, 190, 60)
local GOLD_TEXT  = Color3.fromRGB(255, 205, 90)
local SOFT_BLUE  = Color3.fromRGB(250, 175, 217)
local PALE_BLUE  = Color3.fromRGB(255, 205, 230)

--======================================================================
-- THE PET PICTURE -- realm 1's viewport, verbatim in behaviour.
--======================================================================
-- A ViewportFrame showing the realm's real fused template, the emoji only while the template has not yet
-- replicated -- never a grey silhouette, on locked cards least of all.
--
-- ===== WHY THE SPIN ORBITS THE CAMERA (the lag fix) =====
-- The first pass rotated the MODEL: one RenderStepped connection per card calling PivotTo every frame.
-- PivotTo rewrites the CFrame of every part, so seventeen cards x 15-30 parts each was hundreds of part
-- transforms per frame -- exactly the mistake realm 1 already made and documented in PetFollow.client.lua:
-- "Pivoting rewrote the CFrame of every part of every pet ... which is what made the little pictures
-- stutter. Orbiting is ONE CFrame write per icon per frame and is perfectly smooth."
--
-- So this is realm 1's design wholesale: ONE shared loop for every icon, the model never moves after being
-- framed, the camera orbits it, and icons that cannot be seen (hub closed, page hidden, scrolled out of the
-- band) are skipped entirely.
--
-- ===== DRAG TO ROTATE (realm 1's grab, verbatim pattern) =====
-- Grab a pet and it turns with your finger/mouse; let go and the idle orbit picks up from where you left
-- it. Only the GRAB is hit-tested on the icon -- the movement and release are tracked on UserInputService,
-- because realm 1 learned the hard way that listening on the viewport's own InputChanged drops the drag the
-- moment the pointer leaves a ~50px icon: "It read as 'the pet barely turns, then lets go by itself'."
-- State rides on attributes (SpinDrag / SpinAuto / SpinHeld / SpinTilt), same names as realm 1.
local iconSpins = {} -- { vp, cam, page, center, radius, height, a0 }

local function makeIcon(card, realm, entry, page, mystery)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Icon3D"
	-- REALM 1's GRID-CARD GEOMETRY, exactly: 55% of a 322x252 card, 6px down, centred. This is the
	-- "little screen" size the first realm shows its pets in -- noticeably taller than the 132px strip the
	-- first pass used.
	vp.AnchorPoint = Vector2.new(0.5, 0)
	vp.Size = UDim2.new(1, -12, 0.55, 0)
	vp.Position = UDim2.new(0.5, 0, 0, 6)
	vp.BackgroundColor3 = Color3.fromRGB(78, 12, 45); vp.BackgroundTransparency = 0.15
	vp.ZIndex = 6; vp.Parent = card
	uicorner(vp, 8)
	-- OUTLINE THE MINI-HUD. Each pet's little screen gets its own frame, same weight as the card carries
	-- and in the same colour family, so the picture reads as a framed window rather than a hole in the
	-- card. Locked/mystery slots take the gold lock edge; owned ones the card's own edge.
	uistroke(vp, mystery and GOLD_EDGE or CARD_EDGE, mystery and 2 or 1)
	-- realm 1's lighting, so the same model reads the same in both hubs
	vp.Ambient = Color3.fromRGB(185, 185, 195); vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.5)

	local cam = Instance.new("Camera"); cam.FieldOfView = 50; cam.Parent = vp; vp.CurrentCamera = cam

	-- ===== THE MYSTERY PICTURE =====
	-- Not an emoji pair. "🦕❓" side by side is placeholder art -- two glyphs at whatever size TextScaled
	-- picks, fighting for the same box. A proper unknown is COMPOSED: a big dark silhouette of the thing
	-- you cannot see yet, a bold question mark over it, and a slow pulse so the card reads as WITHHELD
	-- rather than broken.
	--
	-- Deliberately the SAME picture on every locked dino card: they are all equally unknown, and a
	-- distinct silhouette each would leak how many kinds there are and roughly what each looks like.
	if mystery then
		-- DINO-THEMED, and specifically an UNHATCHED EGG. Every pet in that realm is earned by hatching one
		-- ("Hatch the egg by the nest", "Dig up the buried egg", "Fish the egg out of the lake"), so an egg
		-- you have not opened is that realm's own word for "not yours yet" -- far more on-theme than a
		-- generic dinosaur shadow, and it says WHY it is locked rather than just that it is.
		--
		-- Palette is the Dino Realm's title card, not Space's navy: volcanic amber over jungle green.
		local plate = Instance.new("Frame")
		plate.Name = "MysteryPlate"
		plate.Size = UDim2.new(1, 0, 1, 0); plate.BackgroundColor3 = Color3.fromRGB(28, 44, 30) -- deep jungle
		plate.BackgroundTransparency = 0.15; plate.BorderSizePixel = 0; plate.ZIndex = 6; plate.Parent = vp
		uicorner(plate, 8)
		-- a warm volcanic wash down the plate, so it reads prehistoric rather than "dark box"
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(74, 58, 34), Color3.fromRGB(24, 40, 28))
		g.Parent = plate

		-- THE EGG: a speckled dino egg, drawn rather than an emoji so it is a shape and not a picture of a
		-- shape. An ellipse via a fully-rounded frame, amber-cream, sitting slightly low like it is nested.
		local egg = Instance.new("Frame")
		egg.Name = "Egg"
		egg.AnchorPoint = Vector2.new(0.5, 0.5); egg.Position = UDim2.fromScale(0.5, 0.54)
		egg.Size = UDim2.new(0, 66, 0, 84)
		egg.BackgroundColor3 = Color3.fromRGB(226, 206, 160)
		egg.BackgroundTransparency = 0.12; egg.BorderSizePixel = 0; egg.ZIndex = 6; egg.Parent = plate
		do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.5, 0); c.Parent = egg end
		do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(120, 92, 44); s.Thickness = 2; s.Parent = egg end
		-- speckles: three small dark ovals, fixed positions -- random ones would differ per card and imply
		-- the eggs are different from each other, which is exactly what a mystery must not say.
		for _, sp in ipairs({ {0.32, 0.30, 11}, {0.62, 0.46, 8}, {0.42, 0.68, 9} }) do
			local d = Instance.new("Frame")
			d.AnchorPoint = Vector2.new(0.5, 0.5); d.Position = UDim2.fromScale(sp[1], sp[2])
			d.Size = UDim2.fromOffset(sp[3], sp[3] - 2)
			d.BackgroundColor3 = Color3.fromRGB(150, 118, 66); d.BackgroundTransparency = 0.35
			d.BorderSizePixel = 0; d.ZIndex = 6; d.Parent = egg -- same layer as the '?': both are egg children, so tree order puts the ? on top
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.5, 0); c.Parent = d
		end

		-- the "?" sits ON the egg -- what is inside is the unknown, not the egg
		local q = Instance.new("TextLabel")
		q.Name = "Question"
		q.AnchorPoint = Vector2.new(0.5, 0.5); q.Position = UDim2.fromScale(0.5, 0.5)
		q.Size = UDim2.fromScale(0.72, 0.66); q.BackgroundTransparency = 1
		q.Font = Enum.Font.FredokaOne; q.TextScaled = true
		q.TextColor3 = Color3.fromRGB(96, 62, 26)
		q.Text = "?"
		q.ZIndex = 6; q.Parent = egg
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 46; c.Parent = q end
		local qs = Instance.new("UIStroke"); qs.Color = Color3.fromRGB(246, 232, 196); qs.Thickness = 2; qs.Parent = q

		-- Breathing, not blinking: the egg rocks a few degrees, like something inside it moved. Loops with
		-- the card and dies with it (Roblox cancels tweens on a destroyed instance) -- nothing to clean up.
		local TweenService = game:GetService("TweenService")
		egg.Rotation = -4
		TweenService:Create(egg, TweenInfo.new(1.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Rotation = 4 }):Play()

		-- STOPS HERE. No template lookup, no model: cloning the real dinosaur in behind this would ship the
		-- answer to anyone who opened the instance tree.
		return
	end

	local emoji = Instance.new("TextLabel")
	emoji.Name = "IconPlaceholder"
	emoji.Size = UDim2.new(1, 0, 1, 0); emoji.BackgroundTransparency = 1
	emoji.Font = Enum.Font.FredokaOne; emoji.TextScaled = true
	emoji.Text = entry.emoji or "\xF0\x9F\x90\xBE"
	emoji.ZIndex = 6; emoji.Parent = vp
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 74; c.Parent = emoji end

	-- drag-to-rotate (realm 1's exact grab/track/release shape)
	vp.Active = true
	vp:SetAttribute("SpinDrag", 0); vp:SetAttribute("SpinAuto", 0); vp:SetAttribute("SpinHeld", false)
	vp:SetAttribute("SpinTilt", 0)
	do
		local uis = game:GetService("UserInputService")
		local lastX, lastY, moveConn, endConn
		local function release()
			lastX, lastY = nil, nil
			if moveConn then moveConn:Disconnect(); moveConn = nil end
			if endConn then endConn:Disconnect(); endConn = nil end
			vp:SetAttribute("SpinHeld", false) -- the idle orbit picks up from here
		end
		vp.InputBegan:Connect(function(io)
			if io.UserInputType ~= Enum.UserInputType.MouseButton1
				and io.UserInputType ~= Enum.UserInputType.Touch then return end
			release() -- never stack two grabs on one icon
			lastX, lastY = io.Position.X, io.Position.Y
			vp:SetAttribute("SpinHeld", true) -- pauses the auto-spin for THIS pet only
			moveConn = uis.InputChanged:Connect(function(m)
				if not lastX then return end
				if m.UserInputType ~= Enum.UserInputType.MouseMovement
					and m.UserInputType ~= Enum.UserInputType.Touch then return end
				local dx, dy = m.Position.X - lastX, m.Position.Y - lastY
				lastX, lastY = m.Position.X, m.Position.Y
				-- 0.011 rad/px sideways: a drag the width of the panel is roughly one full turn.
				vp:SetAttribute("SpinDrag", (vp:GetAttribute("SpinDrag") or 0) + dx * 0.011)
				-- Up/down raises and lowers the camera. Clamped so it can never swing over the top and
				-- render the pet upside down.
				vp:SetAttribute("SpinTilt",
					math.clamp((vp:GetAttribute("SpinTilt") or 0) + dy * 0.02, -1.6, 2.2))
			end)
			endConn = uis.InputEnded:Connect(function(e)
				if e.UserInputType == Enum.UserInputType.MouseButton1
					or e.UserInputType == Enum.UserInputType.Touch then release() end
			end)
		end)
		-- A rebuild destroys the icon mid-drag; without this its two UserInputService connections would
		-- outlive it, one pair per rebuild.
		vp.Destroying:Connect(release)
	end

	-- (a mystery card already returned above, before the drag handlers -- it has nothing to spin)

	local tmpl = entry.tmpl and ReplicatedStorage:FindFirstChild(entry.tmpl)
	if not tmpl then return end -- emoji stands in until the template replicates (the watcher rebuilds then)

	local okClone, model = pcall(function() return tmpl:Clone() end)
	if not (okClone and model) then return end

	local okFrame = pcall(function()
		model:PivotTo(CFrame.new()) -- root at origin, ONCE -- the model never moves again
		model.Parent = vp
		local cf, size = model:GetBoundingBox()
		local maxe = math.max(size.X, size.Y, size.Z, 1)
		local center = cf.Position
		-- Realm 1's framing numbers verbatim: 3/4 front view, slightly above, distance 1.45x the largest
		-- extent. Aimed at the BOUNDING-BOX CENTRE with clearance on every side, which is what keeps the
		-- top half of a tall pet inside the frame at every angle of the orbit -- the first pass framed
		-- tighter and taller pets clipped through the top of the card as they turned.
		local dir = Vector3.new(0.8, 0.5, 0.55).Unit
		local off = dir * (maxe * 1.45 + 1)
		cam.CFrame = CFrame.lookAt(center + off, center)
		iconSpins[#iconSpins + 1] = {
			vp = vp, cam = cam, page = page, center = center,
			radius = math.sqrt(off.X * off.X + off.Z * off.Z),
			height = off.Y,
			a0     = math.atan2(off.Z, off.X),
		}
	end)
	if okFrame then emoji.Visible = false end
end

-- ONE slow auto-rotate loop for ALL icons -- realm 1's loop, with its culls. Runs no per-icon work at all
-- while the hub is closed or the icon's page is hidden, and skips icons scrolled out of the visible band.
RunService.RenderStepped:Connect(function(dt)
	if #iconSpins == 0 then return end
	local panel = _G.PetHub and _G.PetHub.panel
	if not (panel and panel.Visible) then return end
	local step = dt * 0.6 -- slow + smooth; dt-based so it is frame-rate independent
	local pTop = panel.AbsolutePosition.Y
	local pBot = pTop + panel.AbsoluteSize.Y
	for i = #iconSpins, 1, -1 do
		local ic = iconSpins[i]
		local vp = ic.vp
		if not (vp and vp.Parent and ic.cam and ic.cam.Parent) then
			table.remove(iconSpins, i) -- its card was destroyed by a rebuild -- drop it
		elseif ic.page and not ic.page.overlay.Visible then
			-- this collection's tab is not the one showing -- costs nothing
		elseif vp.AbsolutePosition.Y + vp.AbsoluteSize.Y >= pTop and vp.AbsolutePosition.Y <= pBot then
			-- ORBIT THE CAMERA around the stationary pet: one CFrame write, no part-by-part transform.
			-- Each icon carries its OWN orbit total, so a pet the player turned by hand keeps its heading
			-- instead of snapping back to a shared angle when they let go.
			if not vp:GetAttribute("SpinHeld") then
				vp:SetAttribute("SpinAuto", ((vp:GetAttribute("SpinAuto") or 0) + step) % (2 * math.pi))
			end
			local a = ic.a0 + (vp:GetAttribute("SpinAuto") or 0) + (vp:GetAttribute("SpinDrag") or 0)
			-- SpinTilt scaled by this icon's own radius, so the same finger movement reads the same on
			-- every card regardless of the pet's size.
			local h = ic.height + (vp:GetAttribute("SpinTilt") or 0) * ic.radius * 0.5
			ic.cam.CFrame = CFrame.lookAt(
				ic.center + Vector3.new(math.cos(a) * ic.radius, h, math.sin(a) * ic.radius),
				ic.center)
		end
		-- else: scrolled out of the visible band -- it spins again when scrolled back in
	end
end)

-- ONE OWNED CARD. Age word + level + the realm's XP bar, and an informational strip saying where it can
-- actually be equipped and levelled.
local function buildOwnedCard(page, realm, entry, p, isRare, order)
	local level = math.clamp(tonumber(p.level) or 1, 1, 25)
	local card = Instance.new("Frame")
	card.Name = realm.tabId .. "_" .. entry.key .. (isRare and "_R" or "")
	card.LayoutOrder = order; card.Size = UDim2.new(0, 322, 0, 252) -- realm 1's grid-card size
	card.BackgroundColor3 = isRare and Color3.fromRGB(46, 28, 86) or CARD_BLUE
	card.ClipsDescendants = true
	card.ZIndex = 5 -- ABOVE the page (3) and its scroll (4): at the default 1 the whole card hid behind them
	card.ClipsDescendants = true -- nothing inside may paint past the card rect, whatever layer it lands on
	card.Parent = page.scroll
	uicorner(card, 12)

	local ageName, ageColor = realm.ageOf(level, isRare, entry.key)
	uistroke(card, isRare and ageColor or CARD_EDGE, isRare and 3 or 1)

	makeIcon(card, realm, entry, page)

	if isRare then
		local tag = Instance.new("TextLabel")
		tag.AutomaticSize = Enum.AutomaticSize.X; tag.Size = UDim2.new(0, 0, 0, 18)
		tag.Position = UDim2.new(1, -6, 0, 8); tag.AnchorPoint = Vector2.new(1, 0)
		tag.BackgroundColor3 = ageColor; tag.Font = Enum.Font.GothamBold; tag.TextSize = 11
		tag.TextColor3 = Color3.new(1, 1, 1); tag.Text = ageName; tag.ZIndex = 3; tag.Parent = card
		local pad = Instance.new("UIPadding", tag); pad.PaddingLeft = UDim.new(0, 5); pad.PaddingRight = UDim.new(0, 5)
		uicorner(tag, 5)
		local ts = Instance.new("UIStroke"); ts.Color = Color3.new(1, 1, 1); ts.Thickness = 1; ts.Transparency = 0.2; ts.Parent = tag
	end

	if (tonumber(p.count) or 1) > 1 then
		local cnt = Instance.new("TextLabel")
		cnt.AutomaticSize = Enum.AutomaticSize.X; cnt.Size = UDim2.new(0, 0, 0, 18); cnt.Position = UDim2.new(0, 6, 0, 8)
		cnt.BackgroundColor3 = Color3.fromRGB(255, 170, 40); cnt.Font = Enum.Font.GothamBold; cnt.TextSize = 12
		cnt.TextColor3 = Color3.new(1, 1, 1); cnt.Text = "x" .. p.count; cnt.ZIndex = 3; cnt.Parent = card
		local cpad = Instance.new("UIPadding", cnt); cpad.PaddingLeft = UDim.new(0, 5); cpad.PaddingRight = UDim.new(0, 5)
		uicorner(cnt, 5); uistroke(cnt, Color3.new(0, 0, 0), 1)
	end

	local nm = Instance.new("TextLabel")
	nm.Size = UDim2.new(1, -16, 0, 18); nm.Position = UDim2.new(0, 8, 0, 150)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 16
	nm.TextColor3 = isRare and ageColor or Color3.new(1, 1, 1)
	nm.Text = isRare and (realm.rareNames[entry.key] or entry.displayName) or entry.displayName
	nm.ZIndex = 6; nm.Parent = card

	local lv = Instance.new("TextLabel")
	lv.Size = UDim2.new(1, -16, 0, 16); lv.Position = UDim2.new(0, 8, 0, 170)
	lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold; lv.TextSize = 13
	lv.TextColor3 = ageColor; lv.Text = isRare and ageName or (ageName .. "  Lv " .. level)
	lv.ZIndex = 6; lv.Parent = card

	local maxed = (level >= 25)
	local barBG = Instance.new("Frame")
	barBG.Size = UDim2.new(1, -16, 0, 14); barBG.Position = UDim2.new(0, 8, 0, 188)
	barBG.BackgroundColor3 = Color3.fromRGB(80, 10, 44); barBG.BorderSizePixel = 0; barBG.ZIndex = 6; barBG.Parent = card
	uicorner(barBG, 7); uistroke(barBG, Color3.fromRGB(60, 8, 33), 1)
	local need = xpNeeded(level)
	local frac = maxed and 1 or math.clamp((tonumber(p.xp) or 0) / math.max(1, need), 0, 1)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(frac, 0, 1, 0); fill.BorderSizePixel = 0
	fill.BackgroundColor3 = maxed and Color3.fromRGB(255, 200, 40) or Color3.fromRGB(80, 220, 120)
	fill.Parent = barBG; uicorner(fill, 7)
	local xpTxt = Instance.new("TextLabel")
	xpTxt.Size = UDim2.new(1, 0, 1, 0); xpTxt.BackgroundTransparency = 1
	xpTxt.Font = Enum.Font.GothamBold; xpTxt.TextSize = 10; xpTxt.TextColor3 = Color3.new(1, 1, 1); xpTxt.Parent = barBG
	xpTxt.Text = maxed and "MAX" or (math.floor(tonumber(p.xp) or 0) .. " / " .. need .. " XP")

	-- INFORMATIONAL, NOT A TELEPORT. It states a fact; it is not a button that quietly moves you between
	-- places. A card that offered to teleport you out of Candy mid-session would be a trap, not a feature.
	local home = Instance.new("TextLabel")
	home.Size = UDim2.new(1, -16, 0, 26); home.Position = UDim2.new(0, 8, 0, 208)
	home.BackgroundColor3 = Color3.fromRGB(210, 38, 139); home.BorderSizePixel = 0
	home.Font = Enum.Font.GothamBold; home.TextSize = 12; home.TextColor3 = Color3.new(1, 1, 1)
	home.Text = realm.icon .. " EQUIP & LEVEL IN THE " .. string.upper(realm.realmName)
	home.ZIndex = 6; home.Parent = card
	uicorner(home, 8); uistroke(home, Color3.fromRGB(96, 10, 54), 1)

	local ms = Instance.new("TextLabel")
	ms.Size = UDim2.new(1, -16, 0, 14); ms.Position = UDim2.new(0, 8, 0, 236)
	ms.BackgroundTransparency = 1; ms.Font = Enum.Font.Gotham; ms.TextSize = 11
	ms.TextColor3 = Color3.fromRGB(255, 185, 224)
	ms.Text = "\xE2\x9C\xA8 " .. (entry.where or realm.realmName); ms.ZIndex = 6; ms.Parent = card
end

-- ONE LOCKED CARD. Full-colour picture, padlock badge, gold border, gold LOCKED line -- and every line of
-- text points back at the realm that owns the pet.
local function buildLockedCard(page, realm, entry, order, catalogIndex, total)
	local card = Instance.new("Frame")
	-- On a MYSTERY tab the instance name is numbered, not named: "dinoLocked_TyrannosaurusPet" in the
	-- Explorer hands over the whole answer and makes the egg on the front decoration rather than a secret.
	-- The Food tab keeps real keys -- those cards show the pet anyway, so there is nothing to protect.
	card.Name = realm.tabId .. "Locked_" .. (realm.mystery and tostring(catalogIndex) or entry.key)
	card.LayoutOrder = order; card.Size = UDim2.new(0, 322, 0, 252) -- realm 1's grid-card size
	card.BackgroundColor3 = CARD_BLUE; card.Parent = page.scroll -- SAME blue as an owned card, deliberately
	uicorner(card, 12); uistroke(card, GOLD_EDGE, 2)        -- gold "locked" border is the only frame change

	-- On a MYSTERY realm a locked card shows a dinosaur-and-question-mark, not the pet: see realm.mystery.
	local mystery = realm.mystery and true or false
	makeIcon(card, realm, entry, page, mystery) -- full colour, never greyed: the prize is the advertisement

	-- THE PADLOCK IS A BADGE, not a loose glyph. The other corner markers on these cards -- the duplicate
	-- count and the rarity tag -- are proper chips: a filled rounded rect with its own 1px outline. The
	-- padlock was a bare emoji floating on the card, which is why it read as pasted on rather than part of
	-- the set. Same chip treatment here, in the lock's own gold so it still says "locked" at a glance.
	local lock = Instance.new("TextLabel")
	lock.Size = UDim2.new(0, 30, 0, 30); lock.Position = UDim2.new(1, -10, 0, 10); lock.AnchorPoint = Vector2.new(1, 0)
	lock.BackgroundColor3 = Color3.fromRGB(46, 34, 14)
	lock.BackgroundTransparency = 0.1
	lock.Font = Enum.Font.FredokaOne; lock.TextScaled = true
	lock.Text = "\xF0\x9F\x94\x92"; lock.ZIndex = 7; lock.Parent = card
	uicorner(lock, 8)              -- same corner the other badges use
	uistroke(lock, GOLD_EDGE, 1)   -- the individual outline every badge carries
	do local p = Instance.new("UIPadding"); p.PaddingTop = UDim.new(0, 4); p.PaddingBottom = UDim.new(0, 4)
	   p.PaddingLeft = UDim.new(0, 4); p.PaddingRight = UDim.new(0, 4); p.Parent = lock end

	local nm = Instance.new("TextLabel")
	nm.Size = UDim2.new(1, -16, 0, 18); nm.Position = UDim2.new(0, 8, 0, 150)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 16
	-- name withheld on a mystery tab -- same treatment the wormhole gives islands you have not reached
	nm.TextColor3 = Color3.new(1, 1, 1); nm.Text = mystery and "? ? ?" or entry.displayName; nm.ZIndex = 6; nm.Parent = card

	local st = Instance.new("TextLabel")
	st.Size = UDim2.new(1, -16, 0, 16); st.Position = UDim2.new(0, 8, 0, 170)
	st.BackgroundTransparency = 1; st.Font = Enum.Font.GothamBold; st.TextSize = 13
	st.TextColor3 = GOLD_TEXT
	-- the ISLAND name is a spoiler too on a mystery tab: it says exactly where this one lives
	st.Text = "\xF0\x9F\x94\x92 LOCKED  \xE2\x80\xA2  " ..
		(mystery and "Unknown" or (entry.where or realm.realmName)); st.ZIndex = 6; st.Parent = card

	local rs = Instance.new("TextLabel")
	rs.Size = UDim2.new(1, -20, 0, 14); rs.Position = UDim2.new(0, 10, 0, 188)
	rs.BackgroundTransparency = 1; rs.Font = Enum.Font.Gotham; rs.TextSize = 12
	rs.TextColor3 = SOFT_BLUE; rs.TextXAlignment = Enum.TextXAlignment.Left
	rs.TextTruncate = Enum.TextTruncate.AtEnd; rs.ZIndex = 6; rs.Parent = card
	rs.Text = realm.realmName .. "   \xC2\xB7   Pet " .. tostring(catalogIndex) .. " of " .. tostring(total)

	local how = Instance.new("TextLabel")
	how.Size = UDim2.new(1, -20, 0, 26); how.Position = UDim2.new(0, 10, 0, 204)
	how.BackgroundTransparency = 1; how.Font = Enum.Font.Gotham; how.TextSize = 12; how.TextWrapped = true
	how.TextColor3 = PALE_BLUE; how.TextYAlignment = Enum.TextYAlignment.Top; how.ZIndex = 6; how.Parent = card
	how.Text = entry.secret
		and ("Return to the " .. realm.realmName .. " and collect every pet to unlock this secret pet")
		or  ("Return to the " .. realm.realmName .. " to complete this pet's quest")

	local more = Instance.new("TextLabel")
	more.Size = UDim2.new(1, -16, 0, 20); more.Position = UDim2.new(0, 8, 0, 230)
	more.BackgroundColor3 = Color3.fromRGB(150, 110, 30); more.BorderSizePixel = 0
	more.Font = Enum.Font.GothamBold; more.TextSize = 12; more.TextColor3 = Color3.new(1, 1, 1)
	more.Text = "\xF0\x9F\x94\x92 RETURN TO " .. string.upper(realm.realmName) .. " TO COMPLETE"
	more.ZIndex = 6; more.Parent = card
	uicorner(more, 6); uistroke(more, Color3.fromRGB(90, 66, 16), 1)
end

--======================================================================
-- THE PAGES
--======================================================================
local pages = {} -- [tabId] = { overlay, scroll, title, realm }

local function buildPage(realm)
	local panel = _G.PetHub and _G.PetHub.panel
	if not panel then return nil end
	local inset = (_G.PetHub and _G.PetHub.contentInset) or { x = 10, y = 108, w = -20, h = -118 }

	local overlay = Instance.new("Frame")
	overlay.Name = realm.tabId .. "PetsPage"
	overlay.Size = UDim2.new(1, inset.w, 1, inset.h)
	overlay.Position = UDim2.new(0, inset.x, 0, inset.y)
	overlay.BackgroundColor3 = Color3.fromRGB(150, 18, 88); overlay.BackgroundTransparency = 0.25
	overlay.BorderSizePixel = 0; overlay.Visible = false; overlay.Parent = panel
	uicorner(overlay, 12)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, 26); title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1; title.Font = Enum.Font.FredokaOne; title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(255, 215, 0); title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = realm.icon .. " " .. (realm.headerName or "PETS"); title.Parent = overlay

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.Size = UDim2.new(1, -20, 0, 16); sub.Position = UDim2.new(0, 10, 0, 32)
	sub.BackgroundTransparency = 1; sub.Font = Enum.Font.Gotham; sub.TextSize = 12
	sub.TextColor3 = SOFT_BLUE; sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = realm.realmName .. " collection \xE2\x80\x94 return there to hatch & level"; sub.Parent = overlay

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -62); scroll.Position = UDim2.new(0, 10, 0, 54)
	scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 215, 0); scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = overlay
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 322, 0, 252); grid.CellPadding = UDim2.new(0, 8, 0, 8) -- realm 1's cell
	grid.SortOrder = Enum.SortOrder.LayoutOrder; grid.Parent = scroll

	return { overlay = overlay, scroll = scroll, title = title, sub = sub, realm = realm }
end

local carried = { food = {}, dino = {} }

local function rebuild(tabId)
	local page = pages[tabId]
	if not page then return end
	local realm = page.realm
	local owned = carried[tabId] or {}

	for _, c in ipairs(page.scroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end

	-- Split normal vs rare. Both can be owned at once and each gets its own card, exactly as the source
	-- realms' own hubs do -- a rare is a separate trophy, not a badge on the normal one.
	local ownedNormal, ownedRare = {}, {}
	for key, v in pairs(owned) do
		if type(key) == "string" and type(v) == "table" then
			if key:sub(-2) == "#R" then ownedRare[key:sub(1, -3)] = v else ownedNormal[key] = v end
		end
	end

	local order, cards, ownedSpecies = 0, 0, 0
	local total = #realm.catalog
	for i, entry in ipairs(realm.catalog) do
		local n, r = ownedNormal[entry.key], ownedRare[entry.key]
		if n or r then ownedSpecies += 1 end
		if r then order += 1; cards += 1; pcall(buildOwnedCard, page, realm, entry, r, true, order) end
		if n then order += 1; cards += 1; pcall(buildOwnedCard, page, realm, entry, n, false, order) end
		if not n and not r then
			order += 1; cards += 1
			pcall(buildLockedCard, page, realm, entry, order, i, total)
		end
	end

	page.scroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(cards / 2) * 260 + 20)
	page.title.Text = ("%s %s   %d / %d"):format(realm.icon, realm.headerName or "PETS", ownedSpecies, total)
	page.sub.Text = ("%s collection  %d / %d \xE2\x80\x94 return there to hatch & level")
		:format(realm.realmName, ownedSpecies, total)
	print(("[CrossRealmPets] %s tab: %d/%d species owned (%d cards)")
		:format(realm.realmName, ownedSpecies, total, cards))
end

--======================================================================
-- ATTACH
--======================================================================
task.spawn(function()
	-- The hub builds its panel and publishes the seam near the top of its own script; wait it out rather
	-- than assuming load order. Without the panel there is nowhere to parent, and silently doing nothing
	-- would be indistinguishable from the feature being broken -- so it says so.
	local deadline = os.clock() + 30
	while os.clock() < deadline do
		if _G.PetHub and _G.PetHub.panel and _G.PetHub.registerPage then break end
		task.wait(0.25)
	end
	if not (_G.PetHub and _G.PetHub.panel and _G.PetHub.registerPage) then
		warn("[CrossRealmPets] the pet hub never published a panel -> Food/Dino tabs not built")
		return
	end

	for tabId, realm in pairs(REALMS) do
		local page = buildPage(realm)
		if page then
			pages[tabId] = page
			_G.PetHub.registerPage(tabId, function(on)
				page.overlay.Visible = on
			end)
			-- Adopt the hub's CURRENT page immediately. Registration normally happens before the hub is
			-- ever opened, but if the router ran first (it paints "dino" as the landing page at boot),
			-- waiting for the NEXT showPage call would leave the landing tab lit over an empty band.
			page.overlay.Visible = (_G.PetHub.activePage == tabId)
		end
	end

	-- Ask for the data directly as well as listening. The server pushes on join and repeats a few times,
	-- but this client may have finished loading after every one of those -- and a hub that shows an empty
	-- collection to a player who owns pets is worse than one that shows nothing at all.
	local ok, got = pcall(function() return PetsFunc:InvokeServer() end)
	if ok and type(got) == "table" then
		carried.food = got.food or {}
		carried.dino = got.dino or {}
	end
	for tabId in pairs(REALMS) do rebuild(tabId) end

	print("[CrossRealmPets] Food + Dino pet tabs attached to the hub")
end)

PetsEvent.OnClientEvent:Connect(function(got)
	if type(got) ~= "table" then return end
	carried.food = got.food or {}
	carried.dino = got.dino or {}
	for tabId in pairs(REALMS) do
		if pages[tabId] then rebuild(tabId) end
	end
end)

-- REBUILD WHEN A TEMPLATE LANDS LATE. This is why only SOME pets rendered on the first pass.
--
-- The template publishers (FoodPetTemplates / DinoPetTemplates, server-side) run CSG UnionAsync per pet,
-- which takes real time, and the results replicate to this client one by one -- while the cards here are
-- built the moment the hub seam appears. A card checks FindFirstChild for its template exactly once, at
-- build time: every template that had not yet arrived left its card stuck on the emoji placeholder
-- forever, so the tab showed a mix of real renders (early templates) and emoji (late ones), which looks
-- like half the pets "didn't load".
--
-- Watching ReplicatedStorage.ChildAdded closes the gap: any "*Template" arriving triggers one debounced
-- rebuild of both tabs, so cards upgrade from placeholder to render as the builds complete. Debounced
-- because seventeen templates land in a burst at boot and seventeen full rebuilds would be pure waste.
local rebuildQueued = false
ReplicatedStorage.ChildAdded:Connect(function(inst)
	if not inst.Name:match("Template$") then return end
	if rebuildQueued then return end
	rebuildQueued = true
	task.delay(0.5, function() -- let the burst finish; one rebuild covers all of it
		rebuildQueued = false
		for tabId in pairs(REALMS) do
			if pages[tabId] then rebuild(tabId) end
		end
	end)
end)
