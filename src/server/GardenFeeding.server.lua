-- ============================================================================
-- GARDEN FEEDING MINI-FEATURE (server-authoritative) — feed the Community Garden Cow & Pig.
--   * A FOOD BOX near each animal: ProximityPrompt "Grab ..." gives the player that animal's food (a Tool they
--     visibly carry). Short per-box cooldown so it can't be spammed.
--   * A "Feed" ProximityPrompt on each animal: only rewards if the player is holding THAT animal's food.
--   * On feed: consume the food, the animal speaks a happy line in ITS existing bubble, a little heart/particle
--     burst plays, and the player gets a coin. Per-player + per-animal feed cooldown prevents farming.
--
-- ALL validation (granting food, holding the right food, feeding, cooldowns, reward) happens HERE on the server.
-- The Cow (EasterEggManager) and Pig (SquirrelEasterEgg) register themselves in _G.gardenAnimals on spawn so this
-- script can find their body + speak through their own bubble (no duplicate bubble system).
-- ============================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")

-- ============================ EASY-EDIT CONFIG ==============================
local REWARD_COINS  = 1    -- coins per feed (exactly 1)
local BOX_COOLDOWN  = 4    -- seconds between grabs from a food box
local FEED_COOLDOWN = 45   -- seconds between feeds, PER PLAYER PER ANIMAL (anti-farm)
local PROMPT_DIST   = 9    -- ProximityPrompt activation distance (studs)
local BOX_OFFSET    = 7    -- how far from the animal's spawn to drop its food box (studs)
local DAILY_FOOD_LIMIT = 4 -- max FOOD PICKUPS per player PER DAY (across BOTH animals). Each piece feeds an animal
                          -- once, so this caps feeding at 4/day. After 4 grabs the bins give no more food until the
                          -- next day (UTC midnight). Persisted via DataStore so it survives rejoins.
local LIMIT_MESSAGE = "That's plenty for today! Come back tomorrow"  -- shown at the bin when they're out for the day

local ANIMALS = {
	cow = {
		foodName    = "Hay",                          -- the Tool the player carries
		grabText    = "Grab Hay",
		feedText    = "Feed the Cow",
		handleColor = Color3.fromRGB(225, 196, 96), handleMaterial = Enum.Material.Grass,
		boxColor    = Color3.fromRGB(150, 110, 60),  boxLabel = "\xF0\x9F\x90\xAE Hay",
		thanks      = { "Moo! Thank you!", "Moo! So tasty, thank you!", "Mooo \xE2\x9D\xA4 yum!" },
		hungry      = "Moo? Got any hay for me?",
	},
	pig = {
		foodName    = "Slop Bucket",
		grabText    = "Grab Slop",
		feedText    = "Feed the Pig",
		handleColor = Color3.fromRGB(120, 150, 95), handleMaterial = Enum.Material.SmoothPlastic,
		boxColor    = Color3.fromRGB(110, 90, 70),   boxLabel = "\xF0\x9F\x90\xB7 Slop",
		thanks      = { "Oink! Yummy, thanks!", "Oink oink! Delicious!", "Snort \xE2\x9D\xA4 more please!" },
		hungry      = "Oink? I'm hungry...",
	},
}
-- ============================================================================

-- ---- holding food = a Tool with attribute FoodFor == animal (server-authoritative state the player carries) ----
local function findFood(player, animal)
	local char = player.Character
	local bp   = player:FindFirstChildOfClass("Backpack")
	for _, container in ipairs({ char, bp }) do
		if container then
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("FoodFor") == animal then return t end
			end
		end
	end
	return nil
end

local function giveFood(player, animal)
	local cfg = ANIMALS[animal]
	local tool = Instance.new("Tool")
	tool.Name = cfg.foodName
	tool.RequiresHandle = true; tool.CanBeDropped = false
	tool:SetAttribute("FoodFor", animal)
	local handle = Instance.new("Part")
	handle.Name = "Handle"; handle.Size = Vector3.new(1.4, 1.4, 1.4)
	handle.Color = cfg.handleColor; handle.Material = cfg.handleMaterial
	handle.TopSurface = Enum.SurfaceType.Smooth; handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool
	tool.Parent = player.Backpack
	-- auto-equip so it's visibly carried (and acts as the on-screen "holding food" indicator in the hotbar)
	local hum = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	if hum then pcall(function() hum:EquipTool(tool) end) end
end

-- ---- reward (server-validated) ----
local function grantCoins(player, amt)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins"); local tce = ls:FindFirstChild("TotalCoinsEarned")
	if coins then coins.Value = coins.Value + amt end
	if tce then tce.Value = tce.Value + amt end
end

-- ---- a little heart/particle burst on the animal ----
local function heartBurst(body)
	if not (body and body.Parent) then return end
	local att = Instance.new("Attachment"); att.Position = Vector3.new(0, 1.5, 0); att.Parent = body
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 110, 140))
	pe.Lifetime = NumberRange.new(0.6, 1.1); pe.Speed = NumberRange.new(2, 4); pe.Rate = 0
	pe.SpreadAngle = Vector2.new(45, 45); pe.Size = NumberSequence.new(0.7); pe.LightEmission = 0.5
	pe.Parent = att
	pe:Emit(14)
	task.delay(1.6, function() if att then att:Destroy() end end)
end

-- ---- ground-place a part: raycast down from above `pos` so the box rests on the garden floor ----
local function dropToFloor(pos, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local hit = Workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -60, 0), params)
	return hit and (hit.Position.Y) or (pos.Y - 2.5)
end

-- ---- DAILY FOOD-PICKUP LIMIT (per player, per UTC day, persisted) ----
-- A player may grab at most DAILY_FOOD_LIMIT pieces of food from the bins per day (across BOTH animals). It
-- counts PICKUPS; since each piece feeds once, feeding is capped at 4/day. Auto-resets at UTC midnight.
local FEED_STORE = DataStoreService:GetDataStore("GardenFeedDaily_v1")
local function utcDay() return os.date("!%Y-%m-%d") end
local foodState = {} -- [player] = { day = "YYYY-MM-DD", count = N }
local function freshState() return { day = utcDay(), count = 0 } end
local function rollover(s) if s.day ~= utcDay() then s.day = utcDay(); s.count = 0 end return s end -- new day -> reset
local function loadFood(p)
	local ok, v = pcall(function() return FEED_STORE:GetAsync(tostring(p.UserId)) end)
	foodState[p] = rollover((ok and type(v) == "table" and v.day and type(v.count) == "number") and v or freshState())
end
local function saveFood(p)
	local s = foodState[p]; if not s then return end
	pcall(function() FEED_STORE:SetAsync(tostring(p.UserId), { day = s.day, count = s.count }) end)
end
local function grabsToday(p)
	local s = foodState[p]; if not s then s = freshState(); foodState[p] = s end
	return rollover(s).count
end
local function atFoodLimit(p) return grabsToday(p) >= DAILY_FOOD_LIMIT end
local function addFoodGrab(p)
	local s = foodState[p]; if not s then s = freshState(); foodState[p] = s end
	rollover(s); s.count = s.count + 1
	task.spawn(saveFood, p)
end
Players.PlayerAdded:Connect(function(p) task.spawn(loadFood, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(loadFood, p) end

-- ===================== build the food box for an animal ====================
local function buildBox(animal, body)
	local cfg = ANIMALS[animal]
	local bp = body.Position
	-- offset to the side of the animal's spawn, then drop onto the floor
	local floorY = dropToFloor(bp + Vector3.new(BOX_OFFSET, 0, 0), { body.Parent })
	local box = Instance.new("Part")
	box.Name = "FoodBox_" .. animal
	box.Anchored = true; box.CanCollide = true
	box.Size = Vector3.new(2.4, 2.4, 2.4)
	box.Color = cfg.boxColor; box.Material = Enum.Material.WoodPlanks
	box.Position = Vector3.new(bp.X + BOX_OFFSET, floorY + 1.2, bp.Z)
	box.Parent = Workspace
	-- a little label sign so players know what it is
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(150, 36); sign.StudsOffset = Vector3.new(0, 2.4, 0); sign.AlwaysOnTop = true
	sign.MaxDistance = 40; sign.Parent = box
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true; lbl.TextColor3 = Color3.fromRGB(255, 247, 230); lbl.Text = cfg.boxLabel
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(40, 30, 20); s.Thickness = 2; s.Parent = lbl
	lbl.Parent = sign
	-- grab prompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = cfg.grabText; prompt.ObjectText = cfg.foodName
	prompt.KeyboardKeyCode = Enum.KeyCode.E; prompt.MaxActivationDistance = PROMPT_DIST
	prompt.RequiresLineOfSight = false; prompt.Parent = box

	-- flash a short message above the bin (e.g. when they're out of food for the day); debounced
	local msgUntil = 0
	local function flashMsg(text)
		local now = os.clock(); if now < msgUntil then return end; msgUntil = now + 3.5
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(260, 56); bb.StudsOffset = Vector3.new(0, 3.8, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 45; bb.Parent = box
		local fr = Instance.new("Frame"); fr.Size = UDim2.fromScale(1, 1); fr.BackgroundColor3 = Color3.fromRGB(255, 255, 255); fr.BackgroundTransparency = 0.05; fr.Parent = bb
		Instance.new("UICorner").Parent = fr
		local ml = Instance.new("TextLabel"); ml.BackgroundTransparency = 1; ml.Size = UDim2.new(1, -14, 1, -10); ml.Position = UDim2.fromOffset(7, 5)
		ml.Font = Enum.Font.FredokaOne; ml.TextScaled = true; ml.TextColor3 = Color3.fromRGB(60, 40, 25); ml.Text = text; ml.Parent = fr
		game:GetService("Debris"):AddItem(bb, 3)
	end

	local boxCooldownUntil = 0
	prompt.Triggered:Connect(function(player)
		if atFoodLimit(player) then flashMsg(LIMIT_MESSAGE); return end -- out of food for the day -> message, no food
		local now = os.clock()
		if now < boxCooldownUntil then return end                 -- box on cooldown (anti-spam)
		boxCooldownUntil = now + BOX_COOLDOWN
		if findFood(player, animal) then return end               -- already holding this food
		giveFood(player, animal)
		addFoodGrab(player)                                       -- count this pickup toward the daily cap
		print(("[Feeding] %s grabbed %s (%d/%d today)"):format(player.Name, cfg.foodName, grabsToday(player), DAILY_FOOD_LIMIT))
	end)
	print(("[Feeding] %s food box placed near (%.0f, %.0f, %.0f)"):format(animal, box.Position.X, box.Position.Y, box.Position.Z))
end

-- ===================== the "Feed" prompt on the animal =====================
local feedCooldown = {} -- [player] = { cow=clock, pig=clock }

local function buildFeedPrompt(animal, body)
	local cfg = ANIMALS[animal]
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FeedPrompt"
	prompt.ActionText = cfg.feedText; prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E; prompt.MaxActivationDistance = PROMPT_DIST
	prompt.RequiresLineOfSight = false; prompt.Parent = body

	prompt.Triggered:Connect(function(player)
		local entry = _G.gardenAnimals and _G.gardenAnimals[animal]
		if not entry then return end
		-- VALIDATE (server): the player must be holding THIS animal's food
		local tool = findFood(player, animal)
		if not tool then
			if entry.say then entry.say(cfg.hungry) end           -- no food -> hungry line, no reward
			return
		end
		-- VALIDATE (server): per-player per-animal cooldown so feeding can't be farmed
		local now = os.clock()
		feedCooldown[player] = feedCooldown[player] or {}
		if now - (feedCooldown[player][animal] or -1e9) < FEED_COOLDOWN then return end
		feedCooldown[player][animal] = now
		-- consume + reward + react (the daily cap is enforced at the bin, on pickup)
		tool:Destroy()
		grantCoins(player, REWARD_COINS)
		if entry.say then entry.say(cfg.thanks[math.random(1, #cfg.thanks)]) end
		heartBurst(entry.body)
		print(("[Feeding] %s fed the %s -> +%d coin"):format(player.Name, animal, REWARD_COINS))
	end)
end

Players.PlayerRemoving:Connect(function(p) saveFood(p); feedCooldown[p] = nil; foodState[p] = nil end)

-- ===================== watch the animals, wire boxes + feed prompts =========
-- The Cow/Pig respawn (abduction / falls), so each spawn re-registers a NEW body in _G.gardenAnimals. We place
-- the box ONCE (first time we see an animal) and (re)attach a Feed prompt whenever the body changes.
local boxBuilt, feedBody = {}, {}
task.spawn(function()
	while true do
		local reg = _G.gardenAnimals
		if reg then
			for animal in pairs(ANIMALS) do
				local entry = reg[animal]
				local body = entry and entry.body
				if body and body.Parent then
					if not boxBuilt[animal] then boxBuilt[animal] = true; pcall(buildBox, animal, body) end
					if feedBody[animal] ~= body then feedBody[animal] = body; pcall(buildFeedPrompt, animal, body) end
				end
			end
		end
		task.wait(0.5)
	end
end)

print("[Feeding] garden feeding ready (cow + pig: grab food box -> feed -> +1 coin)")
