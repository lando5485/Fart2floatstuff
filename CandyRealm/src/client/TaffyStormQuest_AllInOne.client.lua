--======================================================================
-- TaffyStormQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- ISLAND-5 QUEST: "THE TAFFY STORM"
--
-- A sugar storm sits over island5, and THREE ANCHORS are holding it there -- one on each of
-- the little islands. Cap all three and the storm comes down; then grab a basket and catch the
-- last of it before it splats.
--
-- Island 5 is three small islands and the first place you can properly fly, so the quest is
-- built across all three: a taffy vent to cap, a kite to reel in, and a lightning rod that only
-- wakes once the other two are down. Three DIFFERENT jobs, because three of the same thing in
-- three places is one job you do three times.
--
-- WHAT THE WORLD PROVIDES:
--   * a "Candy Npc" on island5 -- she starts it (nearest to island5)
--   * (optional) THREE parts named  anchor1 / anchor2 / anchor3  -- one per little island.
--     Name them and the anchors sit exactly where you put them; leave them out and they are
--     placed on a triangle around the island instead, which works but ignores your layout.
--   * (optional) a part named  stormspot  -- centres the falling candy somewhere specific
--
-- HOW IT PLAYS:
--   Talk to her -> you're handed a Catching Basket (a real Tool, held in hand)
--   -> the sky darkens, candy rains down over the island
--   -> stand under a falling piece to catch it; miss it and it splats
--   -> catch the target across 3 waves -> storm clears -> quest complete
--
-- Catching is deliberately forgiving (a generous radius, candy falls slowly) --
-- little kids play this.
--======================================================================

local Players         = game:GetService("Players")
local Workspace       = game:GetService("Workspace")
local Lighting        = game:GetService("Lighting")
local TweenService    = game:GetService("TweenService")
local Debris          = game:GetService("Debris")
local RunService      = game:GetService("RunService")
local SoundService    = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_NAME   = "island5"
local NPC_NAMES     = { "candynpc" }
local STORM_SPOT    = "stormspot"    -- optional part to centre the storm on

local WAVES = {                       -- three waves, each heavier + faster
	{ drops = 10, gap = 1.10, fall = 3.4, name = "First gust" },
	{ drops = 14, gap = 0.80, fall = 2.9, name = "Getting heavy" },
	{ drops = 18, gap = 0.55, fall = 2.4, name = "FULL STORM" },
}
local TARGET        = 10              -- pieces you must catch overall
local CATCH_RADIUS  = 9               -- generous on purpose
local SPREAD        = 78              -- how wide the storm falls around the centre
local DROP_HEIGHT   = 70              -- how far above you it starts
local GOLDEN_CHANCE = 8               -- 1-in-N drops is a golden taffy (worth 3)

local SOUND_STORM   = ""              -- your own ids; "" = silent
local SOUND_CATCH   = ""

-- palette
local FILL   = Color3.fromRGB(255, 240, 248)
local STROKE = Color3.fromRGB(200, 60, 120)
local TEXTC  = Color3.fromRGB(80, 30, 60)
local HINTC  = Color3.fromRGB(150, 120, 160)
local GOLD   = Color3.fromRGB(255, 208, 92)
local CANDY  = {
	Color3.fromRGB(255, 120, 150), Color3.fromRGB(120, 160, 255), Color3.fromRGB(185, 120, 230),
	Color3.fromRGB(150, 235, 150), Color3.fromRGB(255, 180, 110),
}

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s) return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", "")) end

local function firstBasePart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat
		local r = fn(); if r then return r end
		task.wait(0.5)
	until os.clock() - t0 > (timeout or 45)
	return fn()
end

local function mk(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function playSound(id, vol)
	if not id or id == "" then return end
	local s = Instance.new("Sound"); s.SoundId = id; s.Volume = vol or 0.6
	s.Parent = SoundService; s:Play(); Debris:AddItem(s, 5)
end

local function hrpOf()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- ============================================================================
-- STATE
-- ============================================================================
local npcHead, islandPos, stormCentre
local anchorsDone = 0        -- declared up here because the banner reads it and the banner is
                             -- built long before the anchors are
local accepted, storming, done = false, false, false
local caught, missed = 0, 0
local waveNum = 0
local hasBasket = false
_G.stormQuestComplete = false

-- ============================================================================
-- BANNER
-- ============================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "StormObjective"; gui.ResetOnSpawn = false; gui.DisplayOrder = 8; gui.Parent = PlayerGui
local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0); frame.Position = UDim2.new(0.5, 0, 0, 12)
frame.Size = UDim2.new(0, 560, 0, 52); frame.BackgroundColor3 = FILL; frame.Visible = false
frame.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = frame
	local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 3; s.Parent = frame
end
local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1; label.Size = UDim2.fromScale(1, 1); label.Font = Enum.Font.FredokaOne
label.TextColor3 = TEXTC; label.TextScaled = true; label.Parent = frame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = label
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14); pad.Parent = label
end

local function bannerText()
	if done then return "\xF0\x9F\x8D\xAC You weathered the Taffy Storm!" end
	if not accepted then return "\xF0\x9F\x8C\xA7 A taffy storm is coming -- talk to the Candy Npc!" end
	if anchorsDone < 3 then
		return ("\xE2\x9A\x93 Cut the storm loose:  %d/3 anchors  (one on each island)")
			:format(anchorsDone)
	end
	if storming then
		return ("\xF0\x9F\x8D\xAC Catch the falling taffy!  %d/%d   (wave %d/%d)")
			:format(caught, TARGET, waveNum, #WAVES)
	end
	return ("\xF0\x9F\x8C\xA7 Storm incoming...  %d/%d caught"):format(caught, TARGET)
end
local function refreshBanner() label.Text = bannerText() end

local flashTok = 0
local function flash(t, secs)
	flashTok += 1; local mine = flashTok
	label.Text = t; frame.Visible = true
	task.delay(secs or 2, function() if mine == flashTok then refreshBanner() end end)
end

task.spawn(function()
	while true do
		local hrp = hrpOf()
		frame.Visible = (hrp ~= nil) and islandPos ~= nil
			and (hrp.Position - islandPos).Magnitude <= 420
		if frame.Visible then refreshBanner() end
		task.wait(0.4)
	end
end)

-- ============================================================================
-- THE BASKET -- a real Tool, held in hand
-- ============================================================================
local function giveBasket()
	if hasBasket then return end
	local bp = player:FindFirstChildOfClass("Backpack")
	if not bp then return end
	if bp:FindFirstChild("Catching Basket") then hasBasket = true; return end

	local tool = Instance.new("Tool")
	tool.Name = "Catching Basket"; tool.ToolTip = "Catch the falling taffy!"
	tool.RequiresHandle = true; tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, -0.4, 0)

	local handle = mk({ Name = "Handle", Size = Vector3.new(3.2, 0.4, 3.2),
		Color = Color3.fromRGB(186, 138, 84), Material = Enum.Material.Wood,
		Anchored = false, CanCollide = false })
	handle.Massless = true
	handle.Parent = tool

	local function weld(name, size, off, col)
		local p = mk({ Name = name, Size = size, Color = col, Material = Enum.Material.Wood,
			Anchored = false, CanCollide = false })
		p.Massless = true
		p.CFrame = handle.CFrame * off
		p.Parent = tool
		local w = Instance.new("WeldConstraint"); w.Part0 = handle; w.Part1 = p; w.Parent = p
	end
	-- four woven sides
	weld("SideF", Vector3.new(3.2, 1.5, 0.25), CFrame.new(0, 0.75, -1.5), Color3.fromRGB(206, 158, 100))
	weld("SideB", Vector3.new(3.2, 1.5, 0.25), CFrame.new(0, 0.75, 1.5), Color3.fromRGB(206, 158, 100))
	weld("SideL", Vector3.new(0.25, 1.5, 3.2), CFrame.new(-1.5, 0.75, 0), Color3.fromRGB(206, 158, 100))
	weld("SideR", Vector3.new(0.25, 1.5, 3.2), CFrame.new(1.5, 0.75, 0), Color3.fromRGB(206, 158, 100))
	weld("Rim",   Vector3.new(3.5, 0.2, 3.5),  CFrame.new(0, 1.5, 0), Color3.fromRGB(166, 118, 68))

	tool.Parent = bp
	local hum = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	if hum then pcall(function() hum:EquipTool(tool) end) end
	hasBasket = true
end

player.CharacterAdded:Connect(function()
	task.wait(0.6)
	if accepted and not done then hasBasket = false; giveBasket() end
end)

-- ============================================================================
-- STORM WEATHER -- sky darkens while it blows, restored when it clears
-- ============================================================================
local skySaved = nil
local function setStormSky(on)
	if on then
		if not skySaved then
			skySaved = { bright = Lighting.Brightness, amb = Lighting.OutdoorAmbient, fogEnd = Lighting.FogEnd }
		end
		TweenService:Create(Lighting, TweenInfo.new(2), {
			Brightness = math.max(0.6, (skySaved.bright or 2) * 0.45),
			OutdoorAmbient = Color3.fromRGB(96, 84, 104),
			FogEnd = 900 }):Play()
	elseif skySaved then
		TweenService:Create(Lighting, TweenInfo.new(2.5), {
			Brightness = skySaved.bright, OutdoorAmbient = skySaved.amb, FogEnd = skySaved.fogEnd }):Play()
	end
end

-- ============================================================================
-- FALLING CANDY
-- ============================================================================
local function splat(at, colour)
	local s = mk({ Name = "Splat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 3, 3),
		Color = colour, Material = Enum.Material.SmoothPlastic, Transparency = 0.25 })
	s.CFrame = CFrame.new(at + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	s.Parent = Workspace
	TweenService:Create(s, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 1, Size = Vector3.new(0.2, 5, 5) }):Play()
	Debris:AddItem(s, 2.4)
end

local function catchBurst(at, colour)
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local p = mk({ Name = "CatchSpark", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35),
			Color = colour, Material = Enum.Material.Neon })
		p.CFrame = CFrame.new(at); p.Parent = Workspace
		TweenService:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(at + Vector3.new(math.cos(a) * 3, 2, math.sin(a) * 3)),
			Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
		Debris:AddItem(p, 0.6)
	end
end

local function dropOne(fallTime)
	local hrp = hrpOf(); if not hrp then return end
	local centre = stormCentre or hrp.Position

	local golden = (math.random(1, GOLDEN_CHANCE) == 1)
	local colour = golden and GOLD or CANDY[math.random(1, #CANDY)]
	local worth  = golden and 3 or 1

	-- fall somewhere around the storm centre, biased toward the player so it's catchable
	local mixX = (centre.X + hrp.Position.X) * 0.5
	local mixZ = (centre.Z + hrp.Position.Z) * 0.5
	local from = Vector3.new(
		mixX + (math.random() - 0.5) * SPREAD,
		hrp.Position.Y + DROP_HEIGHT,
		mixZ + (math.random() - 0.5) * SPREAD)

	-- a wrapped taffy: body + two twist ends
	local m = Instance.new("Model"); m.Name = "FallingTaffy"
	local body = mk({ Name = "Body", Size = Vector3.new(1.5, 1.0, 1.0), Color = colour,
		Material = golden and Enum.Material.Neon or Enum.Material.SmoothPlastic, Reflectance = 0.12 })
	body.CFrame = CFrame.new(from); body.Parent = m; m.PrimaryPart = body
	for _, sx in ipairs({ -1, 1 }) do
		local tw = mk({ Name = "Twist", Size = Vector3.new(0.6, 0.55, 0.55), Color = Color3.fromRGB(255, 255, 255),
			Material = Enum.Material.SmoothPlastic, Transparency = 0.15 })
		tw.CFrame = body.CFrame * CFrame.new(sx * 1.0, 0, 0); tw.Parent = m
	end
	if golden then
		local li = Instance.new("PointLight"); li.Color = GOLD; li.Brightness = 2; li.Range = 12; li.Parent = body
	end
	m.Parent = Workspace

	-- a shadow on the ground so you can line yourself up under it
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { player.Character, m }
	local hit = Workspace:Raycast(from, Vector3.new(0, -400, 0), rp)
	local landY = hit and hit.Position.Y or (from.Y - DROP_HEIGHT)
	local marker = mk({ Name = "DropShadow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 3.4, 3.4),
		Color = colour, Material = Enum.Material.Neon, Transparency = 0.6 })
	marker.CFrame = CFrame.new(from.X, landY + 0.2, from.Z) * CFrame.Angles(0, 0, math.rad(90))
	marker.Parent = Workspace

	-- FALL, DRIFTING TOWARD YOU. A piece that drops dead straight is only catchable if you
	-- guessed its landing spot before it left the cloud, and there is no reading a dot 70 studs
	-- up. Each one leans toward wherever you are as it comes down -- weakly at first, harder the
	-- lower it gets -- so running at one WORKS. The drift is capped well under running speed, so
	-- you still have to move to it; it just stops punishing you for being half a step out.
	task.spawn(function()
		local t0 = os.clock()
		local start = from
		local drift = Vector3.new()                    -- how far it has leaned toward you so far
		local landY0 = landY
		local gotIt = false
		while os.clock() - t0 < fallTime do
			if done then break end
			local a = (os.clock() - t0) / fallTime
			local h = hrpOf()

			if h then
				-- steer the landing point toward your feet, strongest late in the fall
				local want = Vector3.new(h.Position.X - (start.X + drift.X), 0,
				                         h.Position.Z - (start.Z + drift.Z))
				local pull = math.min(1, want.Magnitude) * (0.25 + a * 1.15)
				if want.Magnitude > 0.1 then
					drift += want.Unit * pull
				end
			end

			local target = Vector3.new(start.X + drift.X, landY0 + 0.6, start.Z + drift.Z)
			local pos = start:Lerp(target, a * a)       -- accelerate like gravity
			pos = Vector3.new(start.X + drift.X * a * a, pos.Y, start.Z + drift.Z * a * a)
			m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, a * 8, a * 3))
			-- the shadow follows, so the thing you are lining up with is still the truth
			marker.CFrame = CFrame.new(pos.X, landY0 + 0.2, pos.Z) * CFrame.Angles(0, 0, math.rad(90))

			if h and (h.Position - pos).Magnitude <= CATCH_RADIUS then
				gotIt = true
				break
			end
			RunService.RenderStepped:Wait()
		end

		marker:Destroy()
		if done then m:Destroy(); return end

		if gotIt then
			caught += worth
			catchBurst(m:GetPivot().Position, colour)
			playSound(SOUND_CATCH, 0.45)
			if golden then flash("\xE2\xAD\x90 GOLDEN TAFFY! +3", 1.4) end
			refreshBanner()
		else
			missed += 1
			local at = m:GetPivot().Position
			splat(Vector3.new(at.X, landY, at.Z), colour)
		end
		m:Destroy()
	end)
end

-- ============================================================================
-- THE STORM
-- ============================================================================
local function winStorm()
	if done then return end
	done = true
	storming = false
	_G.stormQuestComplete = true
	setStormSky(false)
	refreshBanner()

	-- confetti over the island
	local at = (hrpOf() and hrpOf().Position) or stormCentre or Vector3.new()
	for i = 1, 50 do
		local c = mk({ Name = "Confetti", Size = Vector3.new(0.5, 0.5, 0.12),
			Color = CANDY[((i - 1) % #CANDY) + 1], Material = Enum.Material.Neon })
		c.CFrame = CFrame.new(at + Vector3.new(0, 6, 0)); c.Parent = Workspace
		local a = (i / 50) * math.pi * 2
		TweenService:Create(c, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(at + Vector3.new(math.cos(a) * 16, 16 + math.random() * 10, math.sin(a) * 16))
				* CFrame.Angles(math.random() * 6, math.random() * 6, 0) }):Play()
		task.delay(1.2, function()
			if c.Parent then
				TweenService:Create(c, TweenInfo.new(1.8), { CFrame = c.CFrame - Vector3.new(0, 26, 0), Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(c, 3)
	end

	local g = Instance.new("ScreenGui"); g.Name = "StormWin"; g.ResetOnSpawn = false
	g.DisplayOrder = 20; g.IgnoreGuiInset = true; g.Parent = PlayerGui
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5, 0.5); f.Position = UDim2.new(0.5, 0, 0.42, 0)
	f.Size = UDim2.new(0, 0, 0, 92); f.BackgroundColor3 = FILL; f.Parent = g
	local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0, 18); c2.Parent = f
	local s2 = Instance.new("UIStroke"); s2.Color = STROKE; s2.Thickness = 4; s2.Parent = f
	local l2 = Instance.new("TextLabel"); l2.BackgroundTransparency = 1; l2.Size = UDim2.fromScale(1, 1)
	l2.Font = Enum.Font.FredokaOne; l2.TextColor3 = TEXTC; l2.TextScaled = true
	l2.Text = ("\xF0\x9F\x8D\xAC STORM WEATHERED!  %d caught"):format(caught); l2.Parent = f
	local pd = Instance.new("UIPadding"); pd.PaddingLeft = UDim.new(0, 24); pd.PaddingRight = UDim.new(0, 24); pd.Parent = l2
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 32; sz.Parent = l2
	TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 640, 0, 92) }):Play()
	task.delay(5, function()
		TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(l2, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.delay(0.5, function() g:Destroy() end)
	end)

	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({ text = "\xF0\x9F\x8D\xAC Taffy Storm weathered!", color = STROKE }) end)
	end
	print(("[Storm] complete -- %d caught, %d missed"):format(caught, missed))
end

local function runStorm()
	if storming or done then return end
	storming = true
	setStormSky(true)
	playSound(SOUND_STORM, 0.5)

	for w, wave in ipairs(WAVES) do
		if done or caught >= TARGET then break end
		waveNum = w
		flash(("\xF0\x9F\x8C\xA7 Wave %d/%d -- %s!"):format(w, #WAVES, wave.name), 2.2)
		task.wait(1.6)
		for _ = 1, wave.drops do
			if done or caught >= TARGET then break end
			dropOne(wave.fall)
			task.wait(wave.gap)
		end
		if caught >= TARGET then break end
		task.wait(1.5)
	end

	-- IT RAINS UNTIL YOU HAVE THEM. The three waves are the shape of the storm, not a budget:
	-- running out of candy and being told "only 7/10, go and ask her again" is a punishment for
	-- being slightly off, and the whole point of this island is that it is forgiving. So the
	-- last wave simply keeps going -- you cannot fail it, only take longer over it.
	local last = WAVES[#WAVES]
	while not done and caught < TARGET do
		waveNum = #WAVES
		dropOne(last.fall)
		task.wait(last.gap)
	end

	-- let the last few land before judging
	task.wait(2.5)
	storming = false

	if caught >= TARGET then
		winStorm()
	else
		setStormSky(false)
		refreshBanner()
	end
end

-- ============================================================================
-- THE THREE ANCHORS
-- ============================================================================
-- Island 5 is three small islands, and the old quest was one circle of falling candy around one
-- point -- so the layout did nothing and half the candy fell in the sea. This is the storm with
-- three things HOLDING it up, one per islet, and it does not stop until all three are down.
--
-- Each islet is a DIFFERENT job on purpose. Three of the same thing in three places is one job
-- you do three times; three different ones is a reason to go to each island.
--
--   VENT     a taffy geyser. Cap it in the gap between eruptions -- a timing game.
--   UPDRAFT  a kite dragging in the wind. Reel it in -- hold, but let go on the gusts.
--   ROD      only once the other two are down. Crank it up and the storm discharges into it.
--
-- Island 5 is also the first place you can properly FLY, so making the quest span three islets
-- turns flight into the way you play it rather than a way to skip the walk.
-- WHERE EACH ONE GOES. Name a part after the thing you want there and it is built on that
-- part -- 'guyser' is spelt the way you spelt it in Studio, and 'geyser' works too, because a
-- quest that silently ignores your marker over one letter is a quest you cannot place.
-- Numbered variants match as well, so guyser1 / rod2 are fine.
local ANCHOR_KINDS = {
	vent = { "guyser", "geyser", "vent" },
	kite = { "kite", "updraft" },
	rod  = { "rod", "lightningrod", "beacon" },
}
local ANCHOR_NAME = "anchor"     -- the fallback: anchor1 / anchor2 / anchor3
local ANCHOR_SPREAD = 150        -- fallback triangle radius when you have not placed any

local anchors = {}               -- { pos =, kind =, done =, model =, prompt = }
local rodReady = false

-- ---- the shared mini-game HUD ----------------------------------------------
-- One widget, three modes. A track with a needle, a band to hit, and a fill for progress
-- covers timing, tug-of-war and cranking between them; three separate HUDs would have been
-- three sets of tuning to keep in step for no gain the player can see.
local MG = {}
local mgBusy = false
do
	local g = Instance.new("ScreenGui")
	g.Name = "StormMini"; g.ResetOnSpawn = false; g.DisplayOrder = 9
	g.IgnoreGuiInset = true; g.Enabled = false; g.Parent = PlayerGui
	MG.gui = g

	local catch = Instance.new("TextButton")
	catch.Size = UDim2.fromScale(1, 1); catch.BackgroundTransparency = 1
	catch.Text = ""; catch.AutoButtonColor = false; catch.ZIndex = 1; catch.Parent = g
	MG.catch = catch

	MG.home = UDim2.new(0.5, -280, 0.72, 0)
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 560, 0, 158); panel.Position = MG.home
	panel.BackgroundColor3 = FILL; panel.BackgroundTransparency = 0.04
	panel.BorderSizePixel = 0; panel.ZIndex = 2; panel.Parent = g
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
	MG.panel = panel
	local st = Instance.new("UIStroke"); st.Color = STROKE; st.Thickness = 3; st.Parent = panel
	MG.stroke = st

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -180, 0, 32); title.Position = UDim2.new(0, 16, 0, 12)
	title.BackgroundTransparency = 1; title.Font = Enum.Font.FredokaOne
	title.TextSize = 24; title.TextColor3 = TEXTC
	title.TextXAlignment = Enum.TextXAlignment.Left; title.ZIndex = 3
	title.Text = ""; title.Parent = panel
	MG.title = title

	local count = Instance.new("TextLabel")
	count.Size = UDim2.new(0, 150, 0, 32); count.Position = UDim2.new(1, -166, 0, 12)
	count.BackgroundTransparency = 1; count.Font = Enum.Font.FredokaOne
	count.TextSize = 24; count.TextColor3 = STROKE
	count.TextXAlignment = Enum.TextXAlignment.Right; count.ZIndex = 3
	count.Text = ""; count.Parent = panel
	MG.count = count

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -32, 0, 46); track.Position = UDim2.new(0, 16, 0, 54)
	track.BackgroundColor3 = Color3.fromRGB(238, 226, 236); track.BorderSizePixel = 0
	track.ClipsDescendants = true; track.ZIndex = 3; track.Parent = panel
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, 10)

	local zone = Instance.new("Frame")
	zone.Size = UDim2.new(0.22, 0, 1, 0); zone.Position = UDim2.new(0.39, 0, 0, 0)
	zone.BackgroundColor3 = Color3.fromRGB(120, 214, 130); zone.BorderSizePixel = 0
	zone.ZIndex = 4; zone.Parent = track
	Instance.new("UICorner", zone).CornerRadius = UDim.new(0, 8)
	MG.zone = zone

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 0, 6); fill.Position = UDim2.new(0, 0, 1, -6)
	fill.BackgroundColor3 = STROKE; fill.BorderSizePixel = 0
	fill.ZIndex = 6; fill.Parent = track
	MG.fill = fill

	local needle = Instance.new("Frame")
	needle.Size = UDim2.new(0, 6, 1, 0); needle.BackgroundColor3 = TEXTC
	needle.BorderSizePixel = 0; needle.ZIndex = 7; needle.Parent = track
	MG.needle = needle

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -32, 0, 26); hint.Position = UDim2.new(0, 16, 0, 110)
	hint.BackgroundTransparency = 1; hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 16; hint.TextColor3 = HINTC
	hint.TextXAlignment = Enum.TextXAlignment.Left; hint.ZIndex = 3
	hint.Text = ""; hint.Parent = panel
	MG.hint = hint
end

local function mgOpen(title, hint, showZone)
	MG.title.Text = title; MG.hint.Text = hint; MG.count.Text = ""
	MG.zone.Visible = showZone
	MG.fill.Size = UDim2.new(0, 0, 0, 6)
	MG.gui.Enabled = true
	MG.panel.Position = MG.home + UDim2.new(0, 0, 0.08, 0)
	TweenService:Create(MG.panel, TweenInfo.new(0.22, Enum.EasingStyle.Back),
		{ Position = MG.home }):Play()
end

local function mgClose()
	TweenService:Create(MG.panel, TweenInfo.new(0.18),
		{ Position = MG.home + UDim2.new(0, 0, 0.1, 0) }):Play()
	task.delay(0.2, function() MG.gui.Enabled = false end)
end

local function mgFlash(good)
	MG.stroke.Color = good and Color3.fromRGB(96, 200, 110) or Color3.fromRGB(226, 76, 70)
	task.delay(0.18, function() MG.stroke.Color = STROKE end)
end

-- ---- ISLET A: THE VENT -- cap it in the gap between eruptions ---------------
-- The needle runs the track and the safe band is the lull. Hit it three times and the cap is
-- seated; hit an eruption and it blows straight back off, so you lose a seat rather than time.
local function playVent(onSeat)
	if mgBusy then return false end
	mgBusy = true
	mgOpen("CAP THE VENT", "Tap in the green -- outside it the geyser blows the cap off", true)

	local seated, pos, dir, speed = 0, 0, 1, 0.85
	local zc, zw = 0.5, 0.22
	local tapped = false
	local conn = MG.catch.MouseButton1Down:Connect(function() tapped = true end)
	local function drawZone()
		MG.zone.Position = UDim2.new(zc - zw * 0.5, 0, 0, 0)
		MG.zone.Size = UDim2.new(zw, 0, 1, 0)
	end
	drawZone()

	while seated < 3 do
		local dt = math.min(task.wait(), 0.05)
		pos += dir * speed * dt
		if pos >= 1 then pos, dir = 1, -1 elseif pos <= 0 then pos, dir = 0, 1 end
		MG.needle.Position = UDim2.new(pos, -3, 0, 0)
		MG.count.Text = ("%d / 3"):format(seated)
		if tapped then
			tapped = false
			if math.abs(pos - zc) <= zw * 0.5 then
				seated += 1
				speed = math.min(1.9, speed + 0.22)
				zw = math.max(0.12, zw - 0.035)
				zc = 0.16 + math.random() * 0.68
				mgFlash(true)
				if onSeat then onSeat(seated) end
			else
				seated = math.max(0, seated - 1)      -- it blows the cap back off
				mgFlash(false)
				if onSeat then onSeat(seated, true) end
			end
			drawZone()
			TweenService:Create(MG.fill, TweenInfo.new(0.15),
				{ Size = UDim2.new(seated / 3, 0, 0, 6) }):Play()
		end
	end

	MG.count.Text = "3 / 3"
	conn:Disconnect()
	task.wait(0.25); mgClose()
	mgBusy = false
	return true
end

-- ---- ISLET B: THE UPDRAFT -- reel the kite in, but ride the gusts -----------
-- Hold to reel. Every few seconds a gust comes: the band turns red and holding through it tears
-- line off you. So it is hold, watch, release, hold again -- the opposite instinct to the vent.
local function playKite(onPull)
	if mgBusy then return false end
	mgBusy = true
	mgOpen("REEL THE KITE IN", "Hold to reel -- LET GO when the bar turns red", false)

	local down, line, gust, nextGust = false, 0, 0, 1.6
	local c1 = MG.catch.MouseButton1Down:Connect(function() down = true end)
	local c2 = MG.catch.MouseButton1Up:Connect(function() down = false end)
	local c3 = MG.catch.MouseLeave:Connect(function() down = false end)
	local t0 = os.clock()

	while line < 1 do
		local dt = math.min(task.wait(), 0.05)
		local now = os.clock() - t0
		if gust > 0 then
			gust -= dt
			if gust <= 0 then nextGust = now + 1.4 + math.random() * 1.6 end
		elseif now >= nextGust then
			gust = 0.9 + math.random() * 0.5
		end

		if gust > 0 then
			MG.needle.BackgroundColor3 = Color3.fromRGB(226, 76, 70)
			MG.fill.BackgroundColor3 = Color3.fromRGB(226, 76, 70)
			MG.title.Text = "GUST -- LET GO!"
			if down then line = math.max(0, line - dt * 0.55) end   -- it tears line back off
		else
			MG.needle.BackgroundColor3 = TEXTC
			MG.fill.BackgroundColor3 = STROKE
			MG.title.Text = "REEL THE KITE IN"
			if down then line = math.min(1, line + dt * 0.32) end
		end

		MG.fill.Size = UDim2.new(line, 0, 0, 6)
		MG.needle.Position = UDim2.new(line, -3, 0, 0)
		MG.count.Text = ("%d%%"):format(math.floor(line * 100))
		if onPull then onPull(line) end
	end

	mgFlash(true)
	c1:Disconnect(); c2:Disconnect(); c3:Disconnect()
	MG.needle.BackgroundColor3 = TEXTC; MG.fill.BackgroundColor3 = STROKE
	task.wait(0.2); mgClose()
	mgBusy = false
	return true
end

-- ---- ISLET C: THE ROD -- crank it up ---------------------------------------
-- Alternate taps: the needle sweeps and you tap at each END of the track, like working a
-- two-handed crank. Tapping in the middle does nothing, so it has a rhythm to it.
local function playRod(onTurn)
	if mgBusy then return false end
	mgBusy = true
	mgOpen("RAISE THE ROD", "Tap at each END of the bar -- left, right, left...", true)
	MG.zone.Size = UDim2.new(0.18, 0, 1, 0)

	local turns, pos, dir, want = 0, 0, 1, 1
	local tapped = false
	local conn = MG.catch.MouseButton1Down:Connect(function() tapped = true end)

	while turns < 8 do
		local dt = math.min(task.wait(), 0.05)
		pos = math.clamp(pos + dir * 0.95 * dt, 0, 1)
		if pos >= 1 then dir = -1 elseif pos <= 0 then dir = 1 end
		MG.needle.Position = UDim2.new(pos, -3, 0, 0)
		MG.zone.Position = (want == 1) and UDim2.new(0.82, 0, 0, 0) or UDim2.new(0, 0, 0, 0)
		MG.count.Text = ("%d / 8"):format(turns)
		if tapped then
			tapped = false
			local atEnd = (want == 1 and pos > 0.82) or (want == -1 and pos < 0.18)
			if atEnd then
				turns += 1
				want = -want
				mgFlash(true)
				if onTurn then onTurn(turns) end
				TweenService:Create(MG.fill, TweenInfo.new(0.15),
					{ Size = UDim2.new(turns / 8, 0, 0, 6) }):Play()
			else
				mgFlash(false)
			end
		end
	end

	MG.count.Text = "8 / 8"
	conn:Disconnect()
	task.wait(0.25); mgClose()
	mgBusy = false
	return true
end

-- ---- what the anchors LOOK like -------------------------------------------
-- All three are built from flat blocks on a few stepped tones, like the rest of the realm.
-- Each one changes visibly as you work it, because the mini-game is on screen and the thing
-- you are fixing is in the world -- if the world does not move with the bar, the bar is a
-- puzzle you happen to be playing near a prop.
local function groundAt(pos)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { player.Character }
	local hit = Workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -400, 0), rp)
	return hit and hit.Position.Y or pos.Y
end

local function buildVent(a)
	local m = Instance.new("Model"); m.Name = "TaffyVent"; m.Parent = Workspace
	local at = CFrame.new(a.pos)
	local function bit(props, cf) props.Parent = m; local p = mk(props); p.CFrame = cf; return p end

	for i = 1, 8 do                                    -- a ring of rock around the throat
		local ang = (i / 8) * math.pi * 2
		bit({ Color = Color3.fromRGB(122, 112, 104), Size = Vector3.new(2.2, 1.4 + (i % 3) * 0.5, 1.8) },
			at * CFrame.new(math.cos(ang) * 3.4, 0.6, math.sin(ang) * 3.4) * CFrame.Angles(0, -ang, 0))
	end
	bit({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(86, 78, 72),
		Size = Vector3.new(2.6, 3.6, 3.6) }, at * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local throat = bit({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(255, 150, 190),
		Material = Enum.Material.Neon, Size = Vector3.new(0.4, 2.6, 2.6) },
		at * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.rad(90)))

	-- the cap, waiting beside it -- it drops on as you seat it
	local cap = bit({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(198, 132, 66),
		Size = Vector3.new(0.7, 3.2, 3.2) },
		at * CFrame.new(4.6, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)))

	local host = bit({ Transparency = 1, Size = Vector3.new(1, 1, 1) }, at * CFrame.new(0, 2.8, 0))
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/smoke_main.dds"
	em.Color = ColorSequence.new(Color3.fromRGB(255, 170, 205), Color3.fromRGB(255, 226, 240))
	em.Lifetime = NumberRange.new(1.2, 2.2); em.Rate = 18
	em.Speed = NumberRange.new(22, 40); em.SpreadAngle = Vector2.new(10, 10)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	em.Acceleration = Vector3.new(0, -12, 0); em.EmissionDirection = Enum.NormalId.Top
	em.Parent = host

	-- it erupts on a beat, so the lull you are timing is a thing you can SEE, not just a bar
	task.spawn(function()
		while m.Parent and not a.done do
			em:Emit(40); throat.Transparency = 0
			task.wait(0.55)
			throat.Transparency = 0.5
			task.wait(2.0)
		end
	end)

	a.model, a.cap, a.capHome, a.throat, a.em = m, cap, cap.CFrame, throat, em
	a.seatCF = at * CFrame.new(0, 2.9, 0) * CFrame.Angles(0, 0, math.rad(90))
	return m
end

local function buildKite(a)
	local m = Instance.new("Model"); m.Name = "StormKite"; m.Parent = Workspace
	local at = CFrame.new(a.pos)
	local function bit(props, cf) props.Parent = m; local p = mk(props); p.CFrame = cf; return p end

	bit({ Color = Color3.fromRGB(122, 112, 104), Size = Vector3.new(5, 1, 5) }, at * CFrame.new(0, 0.4, 0))
	bit({ Color = Color3.fromRGB(150, 104, 58), Size = Vector3.new(0.9, 5.5, 0.9) }, at * CFrame.new(0, 3, 0))
	bit({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(104, 70, 38),
		Size = Vector3.new(1.2, 2.4, 2.4) }, at * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, math.rad(90), 0))

	-- the kite itself, high up and yanking about
	local kite = Instance.new("Model"); kite.Name = "Kite"; kite.Parent = m
	local kroot
	for i, q in ipairs({
		{ Color3.fromRGB(255, 120, 150), Vector3.new(4.4, 0.3, 4.4), CFrame.Angles(0, 0, math.rad(45)) },
		{ Color3.fromRGB(255, 226, 240), Vector3.new(4.6, 0.34, 0.7), CFrame.Angles(0, 0, math.rad(45)) },
		{ Color3.fromRGB(255, 226, 240), Vector3.new(0.7, 0.34, 4.6), CFrame.Angles(0, 0, math.rad(45)) },
	}) do
		local p = mk({ Color = q[1], Size = q[2], Parent = kite })
		p.CFrame = at * CFrame.new(0, 46, 0) * q[3]
		if i == 1 then kroot = p end
	end
	for i = 1, 3 do                                   -- a tail, so the yanking reads
		local t = mk({ Color = Color3.fromRGB(255, 180, 110), Size = Vector3.new(0.9, 0.3, 0.9), Parent = kite })
		t.CFrame = at * CFrame.new(0, 46 - i * 1.6, i * 0.5)
	end
	kite.PrimaryPart = kroot

	local line = bit({ Color = Color3.fromRGB(240, 235, 230), Size = Vector3.new(0.12, 40, 0.12) },
		at * CFrame.new(0, 25, 0))

	a.model, a.kite, a.line, a.base = m, kite, line, at
	a.kiteHigh = 46
	task.spawn(function()                              -- it never sits still until it is down
		local t = 0
		while m.Parent and not a.done do
			t += 0.06
			local h = a.kiteHigh
			kite:PivotTo(at * CFrame.new(math.sin(t * 1.7) * 4, h, math.cos(t * 1.3) * 4)
				* CFrame.Angles(math.sin(t * 2) * 0.3, t * 0.4, math.cos(t * 1.6) * 0.3))
			line.Size = Vector3.new(0.12, h - 5, 0.12)
			line.CFrame = at * CFrame.new(0, 5 + (h - 5) * 0.5, 0)
			task.wait(0.06)
		end
	end)
	return m
end

local function buildRod(a)
	local m = Instance.new("Model"); m.Name = "LightningRod"; m.Parent = Workspace
	local at = CFrame.new(a.pos)
	local function bit(props, cf) props.Parent = m; local p = mk(props); p.CFrame = cf; return p end

	bit({ Color = Color3.fromRGB(96, 100, 108), Size = Vector3.new(6, 1.2, 6) }, at * CFrame.new(0, 0.5, 0))
	for _, s in ipairs({ -1, 1 }) do
		bit({ Color = Color3.fromRGB(122, 112, 104), Size = Vector3.new(1.2, 2.6, 1.2) },
			at * CFrame.new(s * 2.2, 1.6, 0))
	end
	bit({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(150, 156, 166),
		Size = Vector3.new(1.4, 2.2, 2.2) }, at * CFrame.new(0, 2.4, 0) * CFrame.Angles(0, math.rad(90), 0))

	-- the mast, which grows out of the housing one turn at a time
	local mast = bit({ Color = Color3.fromRGB(180, 186, 196), Size = Vector3.new(0.7, 3, 0.7) },
		at * CFrame.new(0, 3.2, 0))
	local tip = bit({ Color = Color3.fromRGB(255, 240, 170), Material = Enum.Material.Neon,
		Size = Vector3.new(1.1, 1.1, 1.1) }, at * CFrame.new(0, 4.7, 0))
	tip.Transparency = 0.4

	a.model, a.mast, a.tip, a.base = m, mast, tip, at
	return m
end

-- ---- capping one --------------------------------------------------------------
-- Forward-declared: wireAnchor calls the collapse, and the collapse is written below it
-- because it reads better after the thing that triggers it.
local stormCollapse

local function wireAnchor(a)
	local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(12, 12, 12) })
	hit.CFrame = CFrame.new(a.pos + Vector3.new(0, 4, 0))
	hit.Parent = a.model
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "AnchorPrompt"
	pr.ActionText = (a.kind == "vent" and "Cap it") or (a.kind == "kite" and "Reel it in") or "Raise it"
	pr.ObjectText = (a.kind == "vent" and "Taffy Vent") or (a.kind == "kite" and "Storm Kite") or "Lightning Rod"
	pr.HoldDuration = 0.25; pr.MaxActivationDistance = 14
	pr.RequiresLineOfSight = false
	-- visible from the start, but not workable until she has told you what they are
	pr.Enabled = accepted and (a.kind ~= "rod")
	pr.Parent = hit
	a.prompt = pr

	pr.Triggered:Connect(function(plr)
		if plr ~= player or a.done or mgBusy or not accepted then return end
		if a.kind == "rod" and not rodReady then return end
		pr.Enabled = false

		local ok
		if a.kind == "vent" then
			ok = playVent(function(n, blown)
				-- the cap creeps onto the throat as it seats, and jumps back off if it blows
				local t = n / 3
				a.cap.CFrame = a.capHome:Lerp(a.seatCF, t)
				if blown then
					a.em:Emit(60)
					a.throat.Transparency = 0
				end
			end)
			if ok then
				a.cap.CFrame = a.seatCF
				a.em.Rate = 0
				a.throat.Transparency = 1
			end
		elseif a.kind == "kite" then
			ok = playKite(function(v) a.kiteHigh = 46 - v * 38 end)
			if ok then a.kiteHigh = 8 end
		else
			ok = playRod(function(n)
				local h = 3 + n * 2.6
				a.mast.Size = Vector3.new(0.7, h, 0.7)
				a.mast.CFrame = a.base * CFrame.new(0, 1.7 + h * 0.5, 0)
				a.tip.CFrame = a.base * CFrame.new(0, 1.7 + h + 0.6, 0)
				a.tip.Transparency = math.max(0, 0.4 - n * 0.05)
			end)
		end

		if not ok then pr.Enabled = true; return end

		a.done = true
		anchorsDone += 1
		playSound(SOUND_CATCH, 0.6)
		flash(("\xE2\x9A\x93 %s down!  %d/3 anchors"):format(pr.ObjectText, anchorsDone), 2.4)
		refreshBanner()
		print(("[Storm] anchor '%s' capped (%d/3)"):format(a.kind, anchorsDone))

		if anchorsDone == 2 then
			rodReady = true
			for _, o in ipairs(anchors) do
				if o.kind == "rod" and o.prompt then o.prompt.Enabled = true end
			end
			flash("\xE2\x9A\xA1 The rod on the third island just woke up!", 3)
		elseif anchorsDone >= 3 then
			task.delay(0.8, stormCollapse)
		end
	end)
end

-- ---- the storm comes down -------------------------------------------------
-- Two and a half seconds of the sky letting go, then the last of the candy falls and you catch
-- it. The rumble builds and decays rather than banging once: a single jolt reads as an
-- explosion, a long roll reads as weather breaking.
stormCollapse = function()
	local cam = Workspace.CurrentCamera
	local hrp = hrpOf()
	local base = (hrp and hrp.Position) or stormCentre
	local fov0 = cam and cam.FieldOfView or 70
	flash("\xE2\x9A\xA1 THE STORM IS COMING DOWN!", 3)

	if cam then
		TweenService:Create(cam, TweenInfo.new(0.3, Enum.EasingStyle.Back),
			{ FieldOfView = fov0 + 12 }):Play()
	end
	task.spawn(function()
		local t0, secs = os.clock(), 2.6
		while os.clock() - t0 < secs do
			local u = (os.clock() - t0) / secs
			local m = ((u < 0.18) and (u / 0.18) or (1 - (u - 0.18) / 0.82) ^ 1.3) * 3.4
			if cam then
				cam.CFrame = cam.CFrame
					* CFrame.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
					* CFrame.Angles(0, 0, (math.random() - 0.5) * m * 0.026)
			end
			RunService.RenderStepped:Wait()
		end
		if cam then TweenService:Create(cam, TweenInfo.new(0.5), { FieldOfView = fov0 }):Play() end
	end)

	-- taffy hail: big soft lumps raining across the cove, bursting where they land
	task.spawn(function()
		for i = 1, 30 do
			task.delay(math.random() * 2.2, function()
				local ang, r = math.random() * math.pi * 2, 20 + math.random() * 120
				local gx, gz = base.X + math.cos(ang) * r, base.Z + math.sin(ang) * r
				local col = CANDY[math.random(#CANDY)]
				local sz = 1.6 + math.random() * 2.2
				local lump = mk({ Size = Vector3.new(sz, sz * 0.8, sz), Color = col,
					Material = Enum.Material.SmoothPlastic })
				lump.CFrame = CFrame.new(gx, base.Y + 80 + math.random() * 40, gz)
				lump.Parent = Workspace
				TweenService:Create(lump, TweenInfo.new(0.9, Enum.EasingStyle.Quad,
					Enum.EasingDirection.In), { CFrame = CFrame.new(gx, base.Y - 1, gz)
						* CFrame.Angles(math.random() * 6, math.random() * 6, 0) }):Play()
				task.delay(0.9, function() splat(Vector3.new(gx, base.Y, gz), col) end)
				Debris:AddItem(lump, 1.4)
			end)
		end
	end)

	-- the anchors give up: the kite drops, the rod discharges, the vent goes cold
	for _, a in ipairs(anchors) do
		if a.kind == "rod" and a.tip then
			task.spawn(function()
				for _ = 1, 6 do
					a.tip.Transparency = 0
					task.wait(0.08)
					a.tip.Transparency = 0.6
					task.wait(0.12)
				end
				a.tip.Transparency = 0
			end)
		end
	end

	task.delay(3.0, function()
		flash("\xF0\x9F\x8D\xAC Last of it is falling -- CATCH IT!", 2.6)
		task.delay(1.4, runStorm)
	end)
end

-- ---- finding them ---------------------------------------------------------
-- Parts you named win. Failing that, a triangle around the island -- the quest still plays,
-- it just will not sit on your three islets, and the log says so rather than leaving you to
-- wonder why the anchors are in the sea.
-- HIDING A MARKER TAKES MORE THAN TRANSPARENCY. A Decal or Texture on it keeps drawing at
-- full opacity, and a SurfaceAppearance overrides transparency outright -- so a part that looks
-- "hidden" in code is still sat there in game. Blank the lot.
local function hideMarker(inst)
	local function one(b)
		b.Transparency = 1
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
	end
	if inst:IsA("BasePart") then one(inst) end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then one(d)
		elseif d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1
		elseif d:IsA("SurfaceAppearance") then d:Destroy() end
	end
end

-- name matches the marker exactly, or the marker with a number after it (rod, rod1, rod02)
local function markerIs(part, hints)
	local n = norm(part.Name)
	for _, h in ipairs(hints) do
		if n == h or n:match("^" .. h .. "%d+$") then return true end
	end
	return false
end

-- A MARKER MAY BE A MODEL. Half the markers in this place are empty Models -- garden1,
-- ancienttree, Candy Npc are all Models, not parts -- so a search that only accepted BaseParts
-- would walk straight past a Model you named 'guyser' and quietly auto-place instead.
-- Returns the TOP of whatever it is, which is where a thing standing on it belongs.
local function markerSpot(d)
	if d:IsA("BasePart") then
		return d.Position + Vector3.new(0, d.Size.Y * 0.5, 0)
	end
	local ok, cf, size = pcall(function() return d:GetBoundingBox() end)
	if ok and cf then
		if size and size.Y > 0.05 then
			return cf.Position + Vector3.new(0, size.Y * 0.5, 0)
		end
		return cf.Position                      -- an EMPTY model: the pivot is all there is
	end
	return nil
end

local function placeAnchors()
	-- 1. things named after the anchor itself, 2. generic anchor markers, 3. a triangle
	local byKind, spare = {}, {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and not d:IsA("Tool") then
			local spot = markerSpot(d)
			if spot and (spot - islandPos).Magnitude <= 900 then
				local claimed = false
				for kind, hints in pairs(ANCHOR_KINDS) do
					if not byKind[kind] and markerIs(d, hints) then
						byKind[kind] = d; claimed = true; break
					end
				end
				if not claimed and string.find(norm(d.Name), ANCHOR_NAME, 1, true) then
					spare[#spare + 1] = d
				end
			end
		end
	end
	table.sort(spare, function(x, y) return x.Name < y.Name end)

	local KINDS = { "vent", "kite", "rod" }
	local named, si = 0, 0
	for i = 1, 3 do
		local kind = KINDS[i]
		local mark = byKind[kind]
		if not mark then si += 1; mark = spare[si] end
		local pos
		if mark then
			named += 1
			-- ON TOP of the marker, never through the middle of it
			pos = markerSpot(mark) or mark:GetPivot().Position
			hideMarker(mark)
			print(("[Storm] %s -> your '%s' (%s) at (%.0f, %.0f, %.0f)")
				:format(kind, mark.Name, mark.ClassName, pos.X, pos.Y, pos.Z))
		else
			local ang = (i / 3) * math.pi * 2
			local p = islandPos + Vector3.new(math.cos(ang) * ANCHOR_SPREAD, 0,
			                                  math.sin(ang) * ANCHOR_SPREAD)
			pos = Vector3.new(p.X, groundAt(p), p.Z)
		end
		local a = { pos = pos, kind = kind, done = false }
		anchors[i] = a
		if a.kind == "vent" then buildVent(a)
		elseif a.kind == "kite" then buildKite(a)
		else buildRod(a) end
		wireAnchor(a)
	end
	print(("[Storm] 3 anchors placed -- %d on your parts, %d auto-placed"):format(named, 3 - named))
end

-- ============================================================================
-- NPC
-- ============================================================================
local function hideBubble(a) local p = a and a:FindFirstChild("SpeechBubble"); if p then p:Destroy() end end
local function showBubble(a, text, persist, footer)
	hideBubble(a)
	local bb = Instance.new("BillboardGui"); bb.Name = "SpeechBubble"; bb.Adornee = a
	bb.Size = UDim2.new(0, 330, 0, 150); bb.StudsOffset = Vector3.new(0, 5.5, 0)
	bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = FILL
	f.BackgroundTransparency = 0.05; f.BorderSizePixel = 0; f.Parent = bb
	local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0, 16); cr.Parent = f
	local st = Instance.new("UIStroke"); st.Color = STROKE; st.Thickness = 2; st.Parent = f
	local pd = Instance.new("UIPadding")
	pd.PaddingTop = UDim.new(0, 12); pd.PaddingBottom = UDim.new(0, 12)
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = f
	local l = Instance.new("TextLabel"); l.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1; l.Font = Enum.Font.FredokaOne; l.Text = text
	l.TextColor3 = TEXTC; l.TextScaled = true; l.TextWrapped = true; l.Parent = f
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 21; sz.Parent = l
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1, 0.2); h.Position = UDim2.fromScale(0, 0.8)
		h.BackgroundTransparency = 1; h.Font = Enum.Font.FredokaOne; h.Text = footer
		h.TextColor3 = HINTC; h.TextScaled = true; h.Parent = f
		local hs = Instance.new("UITextSizeConstraint"); hs.MaxTextSize = 14; hs.Parent = h
	end
	bb.Parent = a
	if not persist then
		task.delay(9, function() if bb and bb.Parent == a and bb.Name == "SpeechBubble" then bb:Destroy() end end)
	end
end

local function questPages()
	if done then
		return { "You caught the lot! \xF0\x9F\x8D\xAC", "That storm's been ruining my harvest for years." }
	end
	if storming then
		return { ("Don't talk to me -- CATCH! %d of %d!"):format(caught, TARGET) }
	end
	if accepted then
		return {
			("Ready for another go? You've caught %d of %d."):format(caught, TARGET),
			"Stand under the shadows -- that's where it'll land.",
		}
	end
	return {
		"See those clouds? That's a TAFFY STORM rolling in.",
		"Three waves of it, and every piece that hits the ground is wasted.",
		("Take this basket and catch me %d of them."):format(TARGET),
		"Watch the shadows on the ground -- stand in one and it drops right to you.",
	}
end

local function wireNPC(head)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = "Candy Npc"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false; prompt.Parent = head

	local pages, index, watching = nil, 0, false
	local function closeDialogue() hideBubble(head); prompt.ActionText = "Talk"; index = 0; pages = nil end
	local function startWatcher()
		if watching then return end
		watching = true
		task.spawn(function()
			while index ~= 0 do
				local h = hrpOf()
				if not h or (h.Position - head.Position).Magnitude > 12 then closeDialogue(); break end
				task.wait(0.25)
			end
			watching = false
		end)
	end

	prompt.Triggered:Connect(function()
		if index == 0 then pages = questPages() end
		index += 1
		if not pages or index > #pages then
			closeDialogue()
			-- closing the intro (or a retry) kicks the storm off
			if accepted and not storming and not done then task.spawn(runStorm) end
			return
		end
		if index == 2 and not accepted then
			accepted = true
			giveBasket()
			-- the anchors are already standing; taking the job is what makes them workable
			for _, a in ipairs(anchors) do
				if a.prompt and not a.done and a.kind ~= "rod" then a.prompt.Enabled = true end
			end
			refreshBanner()
		end
		local last = index >= #pages
		showBubble(head, pages[index], true, last and "[E] go cut it loose" or ("[E] more  (%d/%d)"):format(index, #pages))
		prompt.ActionText = last and "START" or "Continue"
		startWatcher()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then closeDialogue() end end)
end

local function findNPCNear(ref)
	if not ref then return nil end
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		local n = norm(d.Name)
		local match = false
		for _, want in ipairs(NPC_NAMES) do if n == want then match = true; break end end
		if match then
			local head = (d:IsA("Model") and (d:FindFirstChild("Head") or d.PrimaryPart or firstBasePart(d)))
				or (d:IsA("BasePart") and d) or firstBasePart(d)
			if head then
				local dist = (head.Position - ref).Magnitude
				if dist <= 450 and (not bestD or dist < bestD) then best, bestD = head, dist end
			end
		end
	end
	return best
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	local isle = pollFor(function()
		local x = Workspace:FindFirstChild(ISLAND_NAME)
		if x then return x end
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("Model") and string.lower(d.Name):match("^island_?5$") then return d end
		end
		return nil
	end, 45)

	if isle then
		local ok, cf = pcall(function() return (select(1, isle:GetBoundingBox())) end)
		islandPos = (ok and cf) and cf.Position or nil
	end
	if not islandPos then
		warn("[Storm] island5 not found -- quest inactive")
		return
	end
	stormCentre = islandPos

	-- optional: centre the storm on a part you placed
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and norm(d.Name) == STORM_SPOT then
			d.Transparency = 1; d.CanCollide = false; d.CanQuery = false
			stormCentre = d.Position
			break
		end
	end

	npcHead = pollFor(function() return findNPCNear(islandPos) end, 30)
	if npcHead then
		wireNPC(npcHead)
		task.spawn(function()
			while not accepted and npcHead and npcHead.Parent do
				local h = hrpOf()
				if h and (h.Position - islandPos).Magnitude <= 420 then
					if _G.guideTrailTo then pcall(function() _G.guideTrailTo(npcHead.Position) end) end
				end
				task.wait(2)
			end
		end)
		print("[Storm] island5 Candy Npc wired")
	else
		warn("[Storm] no 'Candy Npc' near island5 -- nobody to start the storm")
	end

	placeAnchors()
	refreshBanner()
	print(("[Storm] ready -- centre %.0f,%.0f,%.0f, target %d, %d wave(s)"):format(
		stormCentre.X, stormCentre.Y, stormCentre.Z, TARGET, #WAVES))
end)

-- ============================================================================
-- /storm -- what the anchors are and where they went
-- ============================================================================
local function stormDiag(msg)
	if tostring(msg or ""):lower():sub(1, 6) ~= "/storm" then return end
	print("[Storm] ---- anchors ----")
	if #anchors == 0 then
		print("  none built yet -- island5 may not have streamed in")
	end
	for i, a in ipairs(anchors) do
		print(("  %d  %-5s  at (%.0f, %.0f, %.0f)  done=%s  prompt=%s")
			:format(i, a.kind, a.pos.X, a.pos.Y, a.pos.Z, tostring(a.done),
				a.prompt and tostring(a.prompt.Enabled) or "none"))
	end
	print(("  accepted=%s  rodReady=%s  %d/3 down"):format(tostring(accepted), tostring(rodReady), anchorsDone))
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then stormDiag(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(stormDiag) end)

-- ============================================================================
-- /complete
-- ============================================================================
local function onCommand(msg)
	if tostring(msg or ""):lower():sub(1, 9) ~= "/complete" then return end
	local h = hrpOf()
	if not (islandPos and h) then return end
	if (h.Position - islandPos).Magnitude > 420 then return end
	accepted = true; caught = TARGET
	anchorsDone = 3
	for _, a in ipairs(anchors) do a.done = true; if a.prompt then a.prompt.Enabled = false end end
	winStorm()
	print("[Storm][TEST] /complete -- storm weathered")
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
