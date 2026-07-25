--======================================================================
-- TaffyStormQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- ISLAND-5 QUEST: "THE TAFFY STORM"
--
-- A sugar storm blows in over island5 and it starts RAINING CANDY. Grab a basket
-- and catch it before it splats -- three waves, each one heavier than the last.
--
-- WHAT THE WORLD PROVIDES:
--   * a "Candy Npc" on island5 -- she starts the storm (nearest to island5)
--   * nothing else is required; the storm builds itself over the island
--   * (optional) a part named  stormspot  -- centres the storm somewhere specific
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
local TARGET        = 26              -- pieces you must catch overall
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

	-- fall + spin, and check for a catch every frame
	task.spawn(function()
		local t0 = os.clock()
		local start = from
		local target = Vector3.new(from.X, landY + 0.6, from.Z)
		local gotIt = false
		while os.clock() - t0 < fallTime do
			if done then break end
			local a = (os.clock() - t0) / fallTime
			local pos = start:Lerp(target, a * a)      -- accelerate like gravity
			m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, a * 8, a * 3))

			local h = hrpOf()
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
			splat(Vector3.new(from.X, landY, from.Z), colour)
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
		if done then break end
		waveNum = w
		flash(("\xF0\x9F\x8C\xA7 Wave %d/%d -- %s!"):format(w, #WAVES, wave.name), 2.2)
		task.wait(1.6)
		for _ = 1, wave.drops do
			if done then break end
			dropOne(wave.fall)
			task.wait(wave.gap)
			if caught >= TARGET then break end
		end
		if caught >= TARGET then break end
		task.wait(1.5)
	end

	-- let the last few land before judging
	task.wait(2.5)
	storming = false

	if caught >= TARGET then
		winStorm()
	else
		setStormSky(false)
		flash(("\xF0\x9F\x8C\xA7 Storm passed -- only %d/%d caught. Talk to her to try again!"):format(caught, TARGET), 4)
		refreshBanner()
	end
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
			refreshBanner()
		end
		local last = index >= #pages
		showBubble(head, pages[index], true, last and "[E] start the storm" or ("[E] more  (%d/%d)"):format(index, #pages))
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

	refreshBanner()
	print(("[Storm] ready -- centre %.0f,%.0f,%.0f, target %d, %d wave(s)"):format(
		stormCentre.X, stormCentre.Y, stormCentre.Z, TARGET, #WAVES))
end)

-- ============================================================================
-- /complete
-- ============================================================================
local function onCommand(msg)
	if tostring(msg or ""):lower():sub(1, 9) ~= "/complete" then return end
	local h = hrpOf()
	if not (islandPos and h) then return end
	if (h.Position - islandPos).Magnitude > 420 then return end
	accepted = true; caught = TARGET
	winStorm()
	print("[Storm][TEST] /complete -- storm weathered")
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
