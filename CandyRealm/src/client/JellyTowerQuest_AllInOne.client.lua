--======================================================================
-- JellyTowerQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- ISLAND-4 QUEST: "Jelly Tower Ascent" -- bounce up 3 jelly tiers, reach the top,
-- capture the flag.
--
-- WHAT THE WORLD PROVIDES (name these in Studio, on island4):
--   * 3 union tiers named JellyLevel1 / JellyLevel2 / JellyLevel3 (bottom -> top)
--   * a flag part named JellyFlag at the very top (touch it to win)
--   * a "Candy Npc" (island4's) -- disambiguated as the one NEAREST the flag/tower
--   * (optional) a JellyStart pad at the bottom
--
-- WHAT THIS SCRIPT DOES (per-player, client-side):
--   * Styles each tier as translucent jiggly jelly + makes it BOUNCY (land on it ->
--     you're flung up). Level 1 launches hardest, level 2 gently bobs, level 3 pulses
--     like it's fading. Tiers never move away/vanish, so the staircase stays climbable.
--   * Each tier is a CHECKPOINT: fall off -> respawn on the highest tier you reached.
--   * Candy Npc gives the quest; touch JellyFlag (after accepting) -> firework +
--     "You conquered the Jelly Tower!" banner. /complete finishes it instantly.
--======================================================================

local Players         = game:GetService("Players")
local Workspace       = game:GetService("Workspace")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local Debris          = game:GetService("Debris")
local TextChatService = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- CONFIG
-- ============================================================================
local LEVEL_PREFIX  = "jellylevel"   -- JellyLevel1..3 (case-insensitive)
local LEVELS        = 3
local FLAG_NAME     = "jellyflag"
local START_NAME    = "jellystart"
local NPC_NAMES     = { "candy npc", "candynpc" }
local TALK_DISTANCE = 12
local BANNER_RANGE  = 320
local BOUNCE_MARGIN = 9 -- studs to clear ABOVE the next tier's top; launch is auto-computed from the real tier heights

-- jelly palette (translucent), one per tier
local JELLY = {
	Color3.fromRGB(255, 95, 160),   -- L1 pink
	Color3.fromRGB(120, 235, 140),  -- L2 green
	Color3.fromRGB(170, 130, 255),  -- L3 purple
}
local FILL   = Color3.fromRGB(255, 240, 248)
local STROKE = Color3.fromRGB(150, 90, 220)
local TEXTC  = Color3.fromRGB(60, 30, 80)
local HINTC  = Color3.fromRGB(150, 120, 160)

-- ============================================================================
-- HELPERS
-- ============================================================================
local function firstBasePart(inst)
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end
local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat local r = fn(); if r then return r end; task.wait(0.5) until os.clock() - t0 > (timeout or 45)
	return fn()
end
local function findFlag()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and string.lower(d.Name) == FLAG_NAME then return d end
	end
	return nil
end
local function findStart()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and string.lower(d.Name) == START_NAME then return d end
	end
	return nil
end
-- the tiers: BaseParts (unions are BaseParts) named jellylevel1..3
local function findLevels()
	local out = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = tonumber(string.match(string.lower(d.Name), "^" .. LEVEL_PREFIX .. "_?(%d+)$"))
			if n then out[n] = d end
		end
	end
	return out
end
local function npcHeadOf(inst)
	if not inst then return nil end
	return (inst:IsA("Model") and (inst:FindFirstChild("Head") or inst.PrimaryPart or firstBasePart(inst)))
		or (inst:IsA("BasePart") and inst) or firstBasePart(inst)
end
-- there may be a Candy Npc on several islands; pick the one NEAREST the flag/tower
local function findNPCNear(refPos)
	if not refPos then return nil end
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		local nm = string.lower(d.Name)
		local match = false
		for _, want in ipairs(NPC_NAMES) do if nm == want then match = true; break end end
		if match then
			local head = npcHeadOf(d)
			if head then
				local dist = (head.Position - refPos).Magnitude
				if dist <= 400 and (not bestD or dist < bestD) then best, bestD = head, dist end
			end
		end
	end
	return best
end

-- ============================================================================
-- SPEECH BUBBLE + OBJECTIVE BANNER (same look/behaviour as the other quests)
-- ============================================================================
local function hideBubble(a) local p = a:FindFirstChild("SpeechBubble"); if p then p:Destroy() end end
local function showBubble(a, text, persist, footer)
	hideBubble(a)
	local bb = Instance.new("BillboardGui"); bb.Name = "SpeechBubble"; bb.Adornee = a
	bb.Size = UDim2.new(0,320,0,150); bb.StudsOffset = Vector3.new(0,5.5,0); bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1,1); f.BackgroundColor3 = FILL; f.BackgroundTransparency = 0.05; f.BorderSizePixel = 0; f.Parent = bb
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,18)
	local st = Instance.new("UIStroke"); st.Color = STROKE; st.Thickness = 2; st.Transparency = 0.3; st.Parent = f
	local pd = Instance.new("UIPadding"); pd.PaddingTop=UDim.new(0,12); pd.PaddingBottom=UDim.new(0,12); pd.PaddingLeft=UDim.new(0,14); pd.PaddingRight=UDim.new(0,14); pd.Parent = f
	local l = Instance.new("TextLabel"); l.Size = footer and UDim2.fromScale(1,0.78) or UDim2.fromScale(1,1); l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne; l.Text = text; l.TextColor3 = TEXTC; l.TextScaled = true; l.TextWrapped = true; l.Parent = f
	Instance.new("UITextSizeConstraint", l).MaxTextSize = 22
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1,0.2); h.Position = UDim2.fromScale(0,0.8); h.BackgroundTransparency = 1
		h.Font = Enum.Font.FredokaOne; h.Text = footer; h.TextColor3 = HINTC; h.TextScaled = true; h.Parent = f
		Instance.new("UITextSizeConstraint", h).MaxTextSize = 14
	end
	bb.Parent = a
	if not persist then task.delay(9, function() if bb and bb.Parent == a and bb.Name == "SpeechBubble" then bb:Destroy() end end) end
end

local questAccepted = false
local won           = false
local reached       = 0    -- highest tier touched (for the banner + checkpoints)
local npcHead

local objGui = Instance.new("ScreenGui"); objGui.Name = "JellyQuestObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7; objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame"); objFrame.AnchorPoint = Vector2.new(0.5,0); objFrame.Position = UDim2.new(0.5,0,0,12); objFrame.Size = UDim2.new(0,520,0,52)
objFrame.BackgroundColor3 = FILL; objFrame.Visible = false; objFrame.Parent = objGui
Instance.new("UICorner", objFrame).CornerRadius = UDim.new(0,16)
do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 3; s.Parent = objFrame end
local objLabel = Instance.new("TextLabel"); objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1,1); objLabel.Font = Enum.Font.FredokaOne
objLabel.TextColor3 = TEXTC; objLabel.TextScaled = true; objLabel.Parent = objFrame
do local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = objLabel
   local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,14); pad.PaddingRight = UDim.new(0,14); pad.Parent = objLabel end

local function baseText()
	if won then return "\xF0\x9F\x9A\xA9 You conquered the Jelly Tower!" end
	if not questAccepted then return "\xF0\x9F\x9F\xA3 Go talk to the Candy NPC!" end
	return ("\xF0\x9F\x9F\xA3 Bounce up the Jelly Tower!  Floor %d/%d"):format(math.min(reached, LEVELS), LEVELS)
end
local flashTok = 0
local wantVisible = false
local function refreshBanner() objLabel.Text = baseText() end
local function flashBanner(text, secs)
	flashTok += 1; local t = flashTok; objLabel.Text = text
	task.delay(secs or 2.5, function() if t == flashTok then refreshBanner() end end)
end
task.spawn(function()
	while true do
		local vis = false
		if wantVisible and npcHead and npcHead.Parent then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			vis = hrp ~= nil and (hrp.Position - npcHead.Position).Magnitude <= BANNER_RANGE
		end
		objFrame.Visible = vis
		task.wait(0.4)
	end
end)

-- ============================================================================
-- CHECKPOINTS -- respawn on the highest tier reached, not the bottom
-- ============================================================================
local checkpointPos = nil
local towerBaseY    = nil

local function setCheckpoint(pos) checkpointPos = pos end

-- ============================================================================
-- JELLY TIER SETUP -- style + bounce + jiggle + checkpoint
-- ============================================================================
local function charOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model) == player and model or nil
end

local function setupTier(tier, level, bounceVel)
	tier.Color = JELLY[level] or JELLY[1]
	tier.Material = Enum.Material.Glass
	tier.Transparency = 0.25
	tier.Reflectance = 0.08
	-- a bouncy, low-friction surface for the "too slippery" jelly feel
	pcall(function() tier.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.25, 0.9) end) -- density, friction, elasticity

	local top = tier.Position + Vector3.new(0, tier.Size.Y * 0.5 + 4, 0)
	if not towerBaseY or (tier.Position.Y - tier.Size.Y * 0.5) < towerBaseY then
		towerBaseY = tier.Position.Y - tier.Size.Y * 0.5
	end

	-- BOUNCE + checkpoint on touch
	local lastBounce = 0
	tier.Touched:Connect(function(hit)
		if not charOf(hit) then return end
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		reached = math.max(reached, level)
		setCheckpoint(tier.Position + Vector3.new(0, tier.Size.Y * 0.5 + 4, 0))
		refreshBanner()
		if os.clock() - lastBounce > 0.35 then
			lastBounce = os.clock()
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, bounceVel, v.Z)
		end
	end)

	-- JIGGLE: subtle vertical bob (L2) + transparency pulse (L3 "fading")
	local base = tier.CFrame
	task.spawn(function()
		local t = level * 1.3
		while tier.Parent do
			t += 0.05
			if level == 2 then tier.CFrame = base * CFrame.new(0, math.sin(t) * 0.5, 0) end
			if level == 3 then tier.Transparency = 0.25 + (math.sin(t * 1.6) * 0.5 + 0.5) * 0.45 end
			task.wait(0.05)
		end
	end)
end

-- fall watcher: only once you're actually climbing (touched a tier) and NOT won, and
-- only if you fell NEAR the tower (so walking around island4 below it never yanks you).
task.spawn(function()
	while true do
		task.wait(0.2)
		if checkpointPos and towerBaseY and reached >= 1 and not won then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local d = hrp.Position - checkpointPos
				local horiz = math.sqrt(d.X * d.X + d.Z * d.Z)
				if hrp.Position.Y < towerBaseY - 25 and horiz < 120 then
					hrp.CFrame = CFrame.new(checkpointPos)
					hrp.AssemblyLinearVelocity = Vector3.zero
				end
			end
		end
	end
end)

-- ============================================================================
-- WIN (capture the flag) -- firework + banner
-- ============================================================================
local FW = { Color3.fromRGB(255,92,138), Color3.fromRGB(120,200,255), Color3.fromRGB(150,235,130), Color3.fromRGB(255,205,90), Color3.fromRGB(190,130,255) }
local function mkPart(props)
	local p = Instance.new("Part"); p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	for k,v in pairs(props) do p[k] = v end; return p
end
local function burst(at, color)
	for i = 1, 26 do
		local s = mkPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.5,0.5,0.5), Color = color, Material = Enum.Material.Neon })
		s.CFrame = CFrame.new(at); s.Parent = Workspace
		local dest = at + Vector3.new((i % 7) - 3, (i % 5), ((i * 3) % 7) - 3).Unit * 14
		TweenService:Create(s, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(dest), Transparency = 1, Size = Vector3.new(0.1,0.1,0.1) }):Play()
		Debris:AddItem(s, 1)
	end
end
local function fireworks(from)
	for i = 1, 3 do
		task.delay(i * 0.35, function()
			local r = mkPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.6,0.6,0.6), Color = Color3.fromRGB(255,240,200), Material = Enum.Material.Neon })
			local start = from + Vector3.new((i - 2) * 6, 3, 0)
			r.CFrame = CFrame.new(start); r.Parent = Workspace
			local up = TweenService:Create(r, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(start + Vector3.new(0, 45 + i * 6, 0)) })
			up.Completed:Connect(function() burst(r.Position, FW[((i - 1) % #FW) + 1]); r:Destroy() end)
			up:Play()
		end)
	end
end
local function winBanner()
	local g = Instance.new("ScreenGui"); g.Name = "JellyWin"; g.ResetOnSpawn = false; g.DisplayOrder = 20; g.IgnoreGuiInset = true; g.Parent = PlayerGui
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5,0.5); f.Position = UDim2.new(0.5,0,0.42,0); f.Size = UDim2.new(0,0,0,90); f.BackgroundColor3 = FILL; f.Parent = g
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,18)
	do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 4; s.Parent = f end
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Size = UDim2.fromScale(1,1); l.Font = Enum.Font.FredokaOne; l.TextColor3 = TEXTC; l.TextScaled = true
	l.Text = "\xF0\x9F\x9A\xA9 You conquered the Jelly Tower!"; l.Parent = f
	Instance.new("UIPadding", l).PaddingLeft = UDim.new(0,24); l:FindFirstChildOfClass("UIPadding").PaddingRight = UDim.new(0,24)
	Instance.new("UITextSizeConstraint", l).MaxTextSize = 32
	TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0,640,0,90) }):Play()
	task.delay(5, function() TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play(); TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play(); task.delay(0.5, function() g:Destroy() end) end)
end

local flagPart, flagPos
local function winQuest()
	if won then return end
	won = true
	_G.jellyQuestComplete = true
	reached = LEVELS
	refreshBanner()
	local at = (flagPos or (player.Character and player.Character:GetPivot().Position)) + Vector3.new(0, 8, 0)
	fireworks(at); winBanner()
	if _G.NotifyCenter then pcall(function() _G.NotifyCenter.push({ text = "\xF0\x9F\x9A\xA9 You conquered the Jelly Tower!", color = STROKE }) end) end
	print("[JellyTower] complete -- flag captured")
end

-- ============================================================================
-- NPC DIALOGUE
-- ============================================================================
local function questPages()
	if won then return { "You made it to the top! Amazing! \xF0\x9F\x9A\xA9" } end
	if questAccepted then return { "The Jelly Tower is slippery -- keep bouncing!", ("You've reached floor %d of %d."):format(math.min(reached, LEVELS), LEVELS) } end
	return {
		"That Jelly Tower is far too slippery to climb!",
		"Bounce your way up all 3 jelly floors.",
		"Reach the top and capture the flag!",
	}
end
local function wireNPC(head)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = "Candy Npc"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = TALK_DISTANCE; prompt.RequiresLineOfSight = false; prompt.Parent = head
	local pages, index, watching = nil, 0, false
	local function close() hideBubble(head); prompt.ActionText = "Talk"; index = 0; pages = nil end
	local function watch()
		if watching then return end; watching = true
		task.spawn(function()
			while index ~= 0 do
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if not hrp or (hrp.Position - head.Position).Magnitude > TALK_DISTANCE then close(); break end
				task.wait(0.25)
			end
			watching = false
		end)
	end
	prompt.Triggered:Connect(function()
		if index == 0 then pages = questPages() end
		index += 1
		if not pages or index > #pages then close(); return end
		if index == 2 and not questAccepted then questAccepted = true; refreshBanner() end
		local last = index >= #pages
		showBubble(head, pages[index], true, last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages))
		prompt.ActionText = last and "Close" or "Continue"
		watch()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then close() end end)
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	local levels = pollFor(function()
		local L = findLevels()
		local n = 0; for i = 1, LEVELS do if L[i] then n += 1 end end
		return (n > 0) and L or nil
	end, 45) or {}
	-- auto-compute each tier's launch from the REAL height gap to the tier above it,
	-- so a bounce always clears the next level (+ BOUNCE_MARGIN studs of headroom).
	local gravity = Workspace.Gravity
	local function bounceFor(i)
		local tier = levels[i]; if not tier then return 80 end
		local myTop  = tier.Position.Y + tier.Size.Y * 0.5
		local above  = levels[i + 1]
		local target = above and (above.Position.Y + above.Size.Y * 0.5) or (myTop + 18) -- top tier: a satisfying pop
		local rise   = math.max(6, (target - myTop) + BOUNCE_MARGIN)
		return math.sqrt(2 * gravity * rise)
	end
	local count = 0
	for i = 1, LEVELS do
		if levels[i] then
			local bv = bounceFor(i)
			setupTier(levels[i], i, bv)
			print(("[JellyTower] tier %d -> bounce %.0f (top y=%.0f)"):format(i, bv, levels[i].Position.Y + levels[i].Size.Y * 0.5))
			count += 1
		end
	end
	if count == 0 then warn(("[JellyTower] no tiers named %s1..%d found"):format(LEVEL_PREFIX, LEVELS)) end

	flagPart = pollFor(findFlag, 45)
	if flagPart then
		flagPos = flagPart:IsA("BasePart") and flagPart.Position or (select(1, flagPart:GetBoundingBox())).Position
		-- connect Touched on the flag's part(s) (works whether JellyFlag is a Part or a Model).
		-- Touching the flag ALWAYS wins (auto-accepts), so it can't be blocked by "not talked to NPC yet".
		local fparts = {}
		if flagPart:IsA("BasePart") then fparts[1] = flagPart
		else for _, p in ipairs(flagPart:GetDescendants()) do if p:IsA("BasePart") then fparts[#fparts + 1] = p end end end
		for _, p in ipairs(fparts) do
			p.Touched:Connect(function(hit)
				if won then return end
				if charOf(hit) then questAccepted = true; winQuest() end
			end)
		end
		-- backstop: also win by PROXIMITY, so a fast bounce past a thin flag still counts
		task.spawn(function()
			while not won do
				if flagPos then
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if hrp and (hrp.Position - flagPos).Magnitude <= 9 then questAccepted = true; winQuest(); break end
				end
				task.wait(0.2)
			end
		end)
		print(("[JellyTower] flag '%s' wired (%d part(s))"):format(flagPart.Name, #fparts))
	else warn("[JellyTower] no 'JellyFlag' found") end

	-- reference for NPC disambiguation: the flag, else the tower's top tier
	local ref = flagPos or (levels[LEVELS] and levels[LEVELS].Position) or (levels[1] and levels[1].Position)
	npcHead = pollFor(function() return findNPCNear(ref) end, 45)
	if npcHead then wireNPC(npcHead); wantVisible = true else warn("[JellyTower] no 'Candy Npc' found near the tower") end

	-- start pad = the part named JellyStart -> bounce you up onto tier 1 (+ first checkpoint)
	local startPart = pollFor(findStart, 20)
	if startPart then
		local myTop  = startPart.Position.Y + startPart.Size.Y * 0.5
		local target = levels[1] and (levels[1].Position.Y + levels[1].Size.Y * 0.5) or (myTop + 18)
		local rise   = math.max(6, (target - myTop) + BOUNCE_MARGIN)
		local bv     = math.sqrt(2 * Workspace.Gravity * rise)
		setupTier(startPart, 0, bv) -- level 0: jelly + bounce + checkpoint, doesn't count as a floor
		print(("[JellyTower] JellyStart -> bounce %.0f"):format(bv))
	else
		print("[JellyTower] no 'JellyStart' found -- name your starting block JellyStart")
	end
	local cpPart = startPart or levels[1]
	if cpPart then setCheckpoint(cpPart.Position + Vector3.new(0, cpPart.Size.Y * 0.5 + 4, 0)) end

	refreshBanner()
	print(("[JellyTower] ready -- %d/%d tiers, flag %s, NPC %s"):format(count, LEVELS, flagPart and "found" or "MISSING", npcHead and "wired" or "MISSING"))
end)

-- ============================================================================
-- /complete -- test command: instantly win (near the tower)
-- ============================================================================
local function onCommand(msg)
	if tostring(msg or ""):lower():sub(1, 9) ~= "/complete" then return end
	-- only completes when you're standing on island4 (near ITS NPC). If that NPC isn't found
	-- yet, do nothing -- never complete on a "maybe", or /complete on another island fires this.
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (npcHead and npcHead.Parent and hrp) then return end
	if (hrp.Position - npcHead.Position).Magnitude > BANNER_RANGE then return end
	questAccepted = true; winQuest()
	print("[JellyTower][TEST] /complete -- flag captured")
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m) if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
