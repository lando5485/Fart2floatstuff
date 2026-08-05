--======================================================================
-- CandyGumballQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- ISLAND-1 QUEST: "Collect 8 scattered gumballs for the Candy Npc."
--
-- The world already has: an NPC model named "Candy Npc" and 8 bricks named
-- "gumball" scattered around island 1. This script:
--   * HIDES each "gumball" brick (invisible position anchor) and spawns a bright
--     candy ORB at it as the collectible (per-player -- built client-side, so one
--     player collecting doesn't remove candies for anyone else).
--   * Wires the Candy Npc with a candy-palette paged speech bubble + "Talk" prompt.
--   * FLOW: on spawn -> "Go talk to the Candy NPC" banner + directional arrows to the
--     NPC. Candies are LOCKED until you accept the quest (talk past page 1). Trying to
--     collect early -> "Go accept the quest from Candy NPC first!". Then collect all 4.
--   * Each one takes a 15s CHUTE RATTLE minigame -- see openRattle(). No free pickups.
--   * At 4/4 -> completion dialogue + a "Quest Complete" banner.
--
-- Self-contained (matches EggSystem/BurritoDig _AllInOne). Drop into
-- StarterPlayerScripts (Rojo maps src/client). Streaming-safe: island 1 is at
-- spawn, and finders poll until the parts replicate in.
--======================================================================

local Players         = game:GetService("Players")
local Workspace       = game:GetService("Workspace")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local Debris          = game:GetService("Debris")
local SoundService    = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui  = player:WaitForChild("PlayerGui")

-- ============================================================================
-- CONFIG
-- ============================================================================
-- FOUR, not eight. Every gumball now costs a 15s minigame, so 8 of them was two solid
-- minutes of the same panel on the tutorial island -- well past the tedium line.
local TOTAL            = 4
local GUMBALL_NAME     = "gumball"                 -- brick name (case-insensitive)
local NPC_NAMES        = { "candy npc", "candynpc" } -- accepted NPC names (lowercased)
local COLLECT_DISTANCE = 12                          -- studs to collect an orb
-- CHUTE RATTLE: the per-gumball minigame. RATTLE_SECONDS is a HARD floor, not a target --
-- a rising ceiling clamps the bar every frame, so mashing cannot finish it early (and going
-- slower than the ceiling still costs you extra time on top).
local RATTLE_SECONDS   = 15
-- ~9 clean hits to fill. Worth doing the arithmetic: the knocker sweeps ~0.7 laps/sec at
-- mid-fill, so the green comes past roughly 1.4x/sec -- 9 hits is well inside 15s for a
-- player who waits for it, which is the point. The ceiling still holds the 15s floor for a
-- perfect run; sloppier players just take longer.
local RATTLE_HIT       = 0.11    -- bar per WELL-TIMED knock
local RATTLE_MISS      = 0.05    -- bar lost on a mistimed knock -- a setback, never a fail
local ORB_SIZE         = 2.6
local COLLECT_SOUND_ID = ""                          -- drop in an OWNED pickup sound id; "" = silent

-- candy palette (from NPC_DIALOGUE.md)
local FILL   = Color3.fromRGB(255, 240, 248)
local STROKE = Color3.fromRGB(214, 92, 158)
local TEXTC  = Color3.fromRGB(74, 30, 58)
local HINTC  = Color3.fromRGB(170, 130, 150)

-- gumball colors, cycled across the 8 orbs
local CANDY_COLORS = {
	Color3.fromRGB(255, 92, 138), Color3.fromRGB(120, 200, 255), Color3.fromRGB(150, 235, 130),
	Color3.fromRGB(255, 205, 90), Color3.fromRGB(190, 130, 255), Color3.fromRGB(255, 140, 80),
	Color3.fromRGB(120, 240, 210), Color3.fromRGB(255, 120, 220),
}

-- dialogue copy (candy version, from NPC_DIALOGUE.md §4)
-- `hint` is the NPC's nudge toward the nearest gumball (nil before the quest starts)
local function questPages(collected, hint)
	if collected >= TOTAL then
		return { "You gathered every gumball!", "Sweet -- the candy stand is saved! \xF0\x9F\x8D\xAC" }
	end
	if collected > 0 then
		local pages = { "Still a few rolling around out there!", ("Found: %d of %d."):format(collected, TOTAL) }
		if hint then pages[#pages + 1] = hint end
		return pages
	end
	return {
		"Catastrophe! I tipped my gumball machine over.",
		"Four gumballs went bouncing off across the island.",
		"They've wedged themselves into things -- you'll have to shake each one loose.",
		"Round them all up and I'll let you crank the machine yourself!",
	}
end

-- ============================================================================
-- HELPERS
-- ============================================================================
local function firstBasePart(inst)
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

-- streaming-safe finder: poll for up to `timeout` seconds
local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat
		local r = fn()
		if r then return r end
		task.wait(0.5)
	until os.clock() - t0 > (timeout or 30)
	return fn()
end

-- there may be a "Candy Npc" on island1 AND island3 (same name). Pick the one NEAREST
-- island1's center so this quest never grabs island3's NPC.
local function island1Center()
	local isl = Workspace:FindFirstChild("island1")
	if not isl then
		for _, o in ipairs(Workspace:GetDescendants()) do
			if o:IsA("Model") and string.lower(o.Name):match("^island_?1$") then isl = o; break end
		end
	end
	if not isl then return nil end
	local ok, cf = pcall(function() return (select(1, isl:GetBoundingBox())) end)
	return ok and cf and cf.Position or nil
end
local NPC_MAX_DIST = 400 -- an NPC must be within this of island1's center to count as island1's
local function findNPCHead()
	local ref = island1Center()
	if not ref then return nil end -- island1 not loaded -> DON'T grab a far NPC (e.g. island3's Candy Npc)
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		local nm = string.lower(d.Name)
		local match = false
		for _, want in ipairs(NPC_NAMES) do if nm == want then match = true; break end end
		if match then
			local head = (d:IsA("Model") and (d:FindFirstChild("Head") or d.PrimaryPart or firstBasePart(d))) or (d:IsA("BasePart") and d) or firstBasePart(d)
			if head then
				local dist = (head.Position - ref).Magnitude
				if dist <= NPC_MAX_DIST and (not bestD or dist < bestD) then best, bestD = head, dist end
			end
		end
	end
	return best
end

local function findGumballs()
	local out = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and string.lower(d.Name) == GUMBALL_NAME then
			out[#out + 1] = d
		end
	end
	return out
end

local collectSound
if COLLECT_SOUND_ID ~= "" then
	collectSound = Instance.new("Sound"); collectSound.SoundId = COLLECT_SOUND_ID; collectSound.Volume = 0.6; collectSound.Parent = SoundService
end
local function playCollect()
	if collectSound then local s = collectSound:Clone(); s.Parent = SoundService; s:Play(); Debris:AddItem(s, 3) end
end

-- ============================================================================
-- OBJECTIVE BANNER (top-center) -- ALWAYS visible once the quest exists. Before
-- accepting it says "Go talk to the Candy NPC"; after accepting it becomes the
-- quest tracker with the live gumball count. Replaces the old right-side 0/8 pill.
-- Same spot + dimensions as the removed coconut-crab banner: top-center, y=12, 520x52.
-- ============================================================================
local collected = 0
local questAccepted = false
_G.candyQuestComplete = false -- island-1 Candy Stand (Shop_AllInOne) stays LOCKED until this is true

local OBJ_TALK = "\xF0\x9F\x8D\xAD Go talk to the Candy NPC!"

local objGui = Instance.new("ScreenGui")
objGui.Name = "CandyQuestObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7; objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5, 0); objFrame.Position = UDim2.new(0.5, 0, 0, 12); objFrame.Size = UDim2.new(0, 520, 0, 52)
objFrame.BackgroundColor3 = FILL; objFrame.Visible = false; objFrame.Parent = objGui
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = objFrame
   local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 3; s.Parent = objFrame end
local objLabel = Instance.new("TextLabel")
objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1, 1); objLabel.Font = Enum.Font.FredokaOne
objLabel.TextColor3 = TEXTC; objLabel.TextScaled = true; objLabel.Parent = objFrame
do local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = objLabel
   local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14); pad.Parent = objLabel end

-- the banner's base text for the current quest state (also tells the player the
-- Candy Stand on island 1 stays LOCKED until the quest is finished).
local function baseObjectiveText()
	if not questAccepted then return OBJ_TALK end
	if collected >= TOTAL then return "\xF0\x9F\x8D\xAC Candy Stand unlocked! Quest complete." end
	return ("\xF0\x9F\x8D\xAC Collect gumballs to unlock the Candy Stand!  %d/%d"):format(collected, TOTAL)
end
local objFlashToken = 0
local bannerActive = false -- the banner only actually shows when near island1 (proximity loop below)
-- set the base text; a proximity loop shows it only near island1 (so it never overlaps island3's cookie banner).
local function updateObjective() objLabel.Text = baseObjectiveText(); bannerActive = true end
-- briefly show a message (e.g. the "accept first" warning), then revert to the base objective.
local function flashObjective(text, seconds)
	objFlashToken += 1; local myToken = objFlashToken
	objLabel.Text = text; bannerActive = true
	task.delay(seconds or 2.5, function()
		if myToken == objFlashToken then updateObjective() end
	end)
end

-- the food stand (Shop_AllInOne) calls this when you touch the LOCKED island-1 stand
_G.candyQuestNudge = function()
	flashObjective("\xF0\x9F\x8D\xAD Finish the gumball quest to unlock the Candy Stand!", 2.5)
end

local function acceptQuest()
	if questAccepted then return end
	questAccepted = true
	updateObjective() -- banner stays up, switches from "talk to NPC" to "Collect the gumballs! X/4"
	if _G.guideTrailClear then _G.guideTrailClear() end -- stop the arrows to the NPC once accepted
end

-- ============================================================================
-- SPEECH BUBBLE (candy palette; paged) -- adapted from NPC_DIALOGUE.md
-- ============================================================================
local function hideBubble(adornee)
	local prev = adornee:FindFirstChild("SpeechBubble"); if prev then prev:Destroy() end
end
local function showBubble(adornee, text, persist, footer)
	hideBubble(adornee)
	local bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"; bb.Adornee = adornee; bb.Size = UDim2.new(0, 320, 0, 150)
	bb.StudsOffset = Vector3.new(0, 5.5, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local frame = Instance.new("Frame"); frame.Size = UDim2.fromScale(1,1); frame.BackgroundColor3 = FILL
	frame.BackgroundTransparency = 0.05; frame.BorderSizePixel = 0; frame.Parent = bb
	local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0,18); cr.Parent = frame
	local st = Instance.new("UIStroke"); st.Color = STROKE; st.Thickness = 2; st.Transparency = 0.4; st.Parent = frame
	local pd = Instance.new("UIPadding"); pd.PaddingTop=UDim.new(0,12); pd.PaddingBottom=UDim.new(0,12); pd.PaddingLeft=UDim.new(0,14); pd.PaddingRight=UDim.new(0,14); pd.Parent = frame
	local lbl = Instance.new("TextLabel"); lbl.Size = footer and UDim2.fromScale(1,0.78) or UDim2.fromScale(1,1)
	lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.FredokaOne; lbl.Text = text; lbl.TextColor3 = TEXTC
	lbl.TextScaled = true; lbl.TextWrapped = true; lbl.Parent = frame
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = lbl
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1,0.2); h.Position = UDim2.fromScale(0,0.8)
		h.BackgroundTransparency = 1; h.Font = Enum.Font.FredokaOne; h.Text = footer; h.TextColor3 = HINTC; h.TextScaled = true; h.Parent = frame
		local hs = Instance.new("UITextSizeConstraint"); hs.MaxTextSize = 14; hs.Parent = h
	end
	bb.Parent = adornee
	if not persist then
		task.delay(9, function() if bb and bb.Parent == adornee and bb.Name == "SpeechBubble" then bb:Destroy() end end)
	end
	return bb
end

-- ============================================================================
-- BUILD -- find the world objects, hide bricks, spawn orbs
-- ============================================================================
local orbs = {}  -- { pos=Vector3, orb=Model, prompt=, done=bool }
-- every 'gumball' brick already turned into an orb. The brick keeps its name after we hide
-- it, so the late-arrival rescan would otherwise wire the same brick again and again.
local wiredBricks = {}

local npcHead  -- assigned below

-- banner shows ONLY when near island1 (so it never overlaps island3's cookie-quest banner)
task.spawn(function()
	while true do
		local vis = false
		if bannerActive and npcHead and npcHead.Parent then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			vis = hrp ~= nil and (hrp.Position - npcHead.Position).Magnitude <= 320
		end
		objFrame.Visible = vis
		task.wait(0.4)
	end
end)

-- ============================================================================
-- NPC PERSONALITY -- rotating pickup lines + a hint toward the next gumball
-- ============================================================================
local GUM_LINES = {
	"That one's a bouncer -- careful!",
	"Ooh, blue raspberry. My favourite.",
	"It's a bit fuzzy... give it a wipe.",
	"That one rolled the furthest, I swear.",
	"Nice catch! You're quick.",
	"Ha! I'd given up on that one.",
	"Still sticky. Don't ask.",
	"You're a natural at this!",
}
local lineOrder, linePos = {}, 0
local function nextLine()
	if linePos >= #lineOrder then    -- rotate the deck so consecutive runs differ
		lineOrder = {}
		for i = 1, #GUM_LINES do lineOrder[i] = GUM_LINES[((i + collected * 3) % #GUM_LINES) + 1] end
		linePos = 0
	end
	linePos += 1
	return lineOrder[linePos]
end

-- roughly where is the nearest gumball you haven't picked up yet?
local function nextHint()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local from, best, bestD = hrp.Position, nil, nil
	for _, o in ipairs(orbs) do
		if not o.done then
			local d = (o.pos - from).Magnitude
			if not bestD or d < bestD then best, bestD = o.pos, d end
		end
	end
	if not best then return nil end

	local delta = best - from
	local flat  = Vector3.new(delta.X, 0, delta.Z)
	local ns    = (delta.Z < 0) and "north" or "south"
	local ew    = (delta.X > 0) and "east"  or "west"
	local dir   = (math.abs(delta.X) > math.abs(delta.Z) * 1.6) and ew
		or (math.abs(delta.Z) > math.abs(delta.X) * 1.6) and ns
		or (ns .. "-" .. ew)

	if flat.Magnitude < 40 then
		if delta.Y > 15 then return "One's right above you -- look UP!" end
		if delta.Y < -15 then return "One's below you somewhere!" end
		return "There's one practically at your feet!"
	end
	if delta.Y > 20 then return ("Try the %s side -- and up high!"):format(dir) end
	return ("Try looking %s of here."):format(dir)
end

-- ============================================================================
-- THE GUMBALL MACHINE -- built client-side next to the NPC. It's scenery for the
-- whole quest, then the finale: the camera flies to it and you CRANK it for a prize.
-- ============================================================================
local machine, crankHandle, chuteMouth   -- Model + the parts the finale animates

local function mk(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

-- drop a point onto whatever solid is under it
local function groundAt(pos)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local filter = {}   -- built explicitly: a nil hole in this array errors
	if player.Character then filter[#filter + 1] = player.Character end
	if machine then filter[#filter + 1] = machine end
	rp.FilterDescendantsInstances = filter
	local hit = Workspace:Raycast(pos + Vector3.new(0, 14, 0), Vector3.new(0, -70, 0), rp)
	return hit and hit.Position or (pos - Vector3.new(0, 3, 0))
end

local RED   = Color3.fromRGB(198, 42, 74)     -- classic enamel red
local BRASS = Color3.fromRGB(238, 198, 106)
local IRON  = Color3.fromRGB(58, 52, 60)

local function buildMachine(head)
	if machine or not head then return end
	local foot = groundAt(head.Position + Vector3.new(7, 0, 0))
	local m = Instance.new("Model"); m.Name = "GumballMachine"
	m:SetAttribute("QuestProp", true)   -- keeps Shop_AllInOne's stand scanner off it

	-- a vertical cylinder (Part cylinders run along X, so they're stood up with a Z roll)
	local function cyl(name, height, dia, y, color, material, collide)
		local p = mk({ Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, dia, dia),
			Color = color, Material = material or Enum.Material.SmoothPlastic, CanCollide = collide or false })
		p.CFrame = CFrame.new(foot + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90))
		p.Parent = m
		return p
	end

	-- ---- cast-iron pedestal: wide foot -> tapered plinth -> column -------------
	local footPlate = cyl("Foot",   0.55, 5.4, 0.28, IRON, Enum.Material.Metal, true)
	m.PrimaryPart = footPlate
	cyl("Plinth", 0.70, 4.4, 0.90, IRON, Enum.Material.Metal, true)
	cyl("Column", 2.60, 3.2, 2.55, RED,  Enum.Material.SmoothPlastic, true)

	-- decorative brass rings top and bottom of the column
	cyl("RingLow",  0.22, 3.45, 1.40, BRASS, Enum.Material.Metal)
	cyl("RingHigh", 0.30, 3.70, 3.95, BRASS, Enum.Material.Metal)

	-- ---- the glass globe, full of candy ---------------------------------------
	local globeCenter = foot + Vector3.new(0, 6.9, 0)
	local globe = mk({ Name = "Globe", Shape = Enum.PartType.Ball, Size = Vector3.new(6.0, 6.0, 6.0),
		Color = Color3.fromRGB(232, 248, 255), Material = Enum.Material.Glass,
		Transparency = 0.72, Reflectance = 0.2 })
	globe.CFrame = CFrame.new(globeCenter); globe.Parent = m

	-- candy PILED in the bottom of the globe (three rings, tightest at the base)
	local RINGS = { { n = 9, r = 2.0, y = -1.95 }, { n = 7, r = 1.55, y = -1.05 }, { n = 5, r = 1.05, y = -0.25 }, { n = 2, r = 0.45, y = 0.4 } }
	local idx = 0
	for _, ring in ipairs(RINGS) do
		for i = 1, ring.n do
			idx += 1
			local a = (i / ring.n) * math.pi * 2 + idx * 0.4
			local ball = mk({ Name = "Inner", Shape = Enum.PartType.Ball, Size = Vector3.new(1.0, 1.0, 1.0),
				Color = CANDY_COLORS[((idx - 1) % #CANDY_COLORS) + 1],
				Material = Enum.Material.SmoothPlastic, Reflectance = 0.18 })
			ball.CFrame = CFrame.new(globeCenter + Vector3.new(math.cos(a) * ring.r, ring.y, math.sin(a) * ring.r))
			ball.Parent = m
		end
	end

	-- ---- brass lid + finial ----------------------------------------------------
	cyl("Collar", 0.35, 3.9, 3.65 + 0.0, BRASS, Enum.Material.Metal)          -- where globe meets column
	cyl("Lid",    0.55, 2.6, 9.85 - 0.1, RED,   Enum.Material.SmoothPlastic)
	cyl("LidRim", 0.22, 3.0, 9.55,       BRASS, Enum.Material.Metal)
	local finial = mk({ Name = "Finial", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9),
		Color = BRASS, Material = Enum.Material.Metal })
	finial.CFrame = CFrame.new(foot + Vector3.new(0, 10.4, 0)); finial.Parent = m

	-- ---- front face: coin slot, crank, chute ----------------------------------
	local FRONT = -1.62   -- machine faces -Z

	local facePlate = mk({ Name = "FacePlate", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.5, 2.5),
		Color = BRASS, Material = Enum.Material.Metal })
	-- yaw 90 deg so the cylinder's axis (local X) points along Z -- i.e. the disc faces front
	facePlate.CFrame = CFrame.new(foot + Vector3.new(0, 2.95, FRONT)) * CFrame.Angles(0, math.rad(90), 0)
	facePlate.Parent = m

	local slot = mk({ Name = "CoinSlot", Size = Vector3.new(0.16, 0.62, 0.22), Color = IRON, Material = Enum.Material.Metal })
	slot.CFrame = CFrame.new(foot + Vector3.new(0, 3.5, FRONT - 0.16)); slot.Parent = m

	crankHandle = mk({ Name = "CrankHandle", Size = Vector3.new(0.4, 1.8, 0.4),
		Color = BRASS, Material = Enum.Material.Metal, CanQuery = true })
	crankHandle.CFrame = CFrame.new(foot + Vector3.new(0, 2.95, FRONT - 0.45)) * CFrame.new(0, 0.65, 0)
	crankHandle.Parent = m
	local grip = mk({ Name = "CrankGrip", Shape = Enum.PartType.Ball, Size = Vector3.new(0.62, 0.62, 0.62),
		Color = Color3.fromRGB(250, 232, 170), Material = Enum.Material.Metal })
	grip.CFrame = crankHandle.CFrame * CFrame.new(0, 0.85, 0); grip.Parent = m

	-- chute: a dark recess with a little brass flap over it
	chuteMouth = mk({ Name = "Chute", Size = Vector3.new(1.8, 1.05, 0.55), Color = Color3.fromRGB(28, 22, 30),
		Material = Enum.Material.SmoothPlastic })
	chuteMouth.CFrame = CFrame.new(foot + Vector3.new(0, 1.55, FRONT + 0.35)); chuteMouth.Parent = m
	local flap = mk({ Name = "ChuteFlap", Size = Vector3.new(1.9, 0.75, 0.16), Color = BRASS, Material = Enum.Material.Metal })
	flap.CFrame = CFrame.new(foot + Vector3.new(0, 1.95, FRONT + 0.06)) * CFrame.Angles(math.rad(-18), 0, 0)
	flap.Parent = m

	-- a warm glow from inside the globe so it reads at a distance
	local lite = Instance.new("PointLight")
	lite.Color = Color3.fromRGB(255, 214, 236); lite.Brightness = 1.1; lite.Range = 16; lite.Parent = globe

	m.Parent = Workspace
	machine = m
	print("[CandyQuest] gumball machine built next to the NPC")
end

-- ============================================================================
-- FX -- sparkles, fireworks, win banner (same look as the island-3 cookie finale)
-- ============================================================================
local FW_COLORS = CANDY_COLORS

local function burst(atPos, color)
	for i = 1, 26 do
		local spark = mk({ Name = "Spark", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5),
			Color = color, Material = Enum.Material.Neon })
		spark.CFrame = CFrame.new(atPos); spark.Parent = Workspace
		local dest = atPos + (Vector3.new((i % 7) - 3, (i % 5), ((i * 3) % 7) - 3)).Unit * 14
		TweenService:Create(spark, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(dest), Transparency = 1, Size = Vector3.new(0.1, 0.1, 0.1) }):Play()
		Debris:AddItem(spark, 1)
	end
end

local function launchFireworks(fromPos)
	for i = 1, 3 do
		task.delay(i * 0.35, function()
			local rocket = mk({ Name = "Rocket", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6),
				Color = Color3.fromRGB(255, 240, 200), Material = Enum.Material.Neon })
			local start = fromPos + Vector3.new((i - 2) * 6, 3, 0)
			local apex  = start + Vector3.new(0, 45 + i * 6, 0)
			rocket.CFrame = CFrame.new(start); rocket.Parent = Workspace
			local up = TweenService:Create(rocket, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(apex) })
			up.Completed:Connect(function() burst(apex, FW_COLORS[((i - 1) % #FW_COLORS) + 1]); rocket:Destroy() end)
			up:Play()
		end)
	end
end

local function shockwave(center, delay, color)
	task.delay(delay, function()
		local ring = mk({ Name = "Shock", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 6, 6),
			Color = color, Material = Enum.Material.Neon, Transparency = 0.1 })
		ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = Workspace
		TweenService:Create(ring, TweenInfo.new(0.85, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.7, 70, 70), Transparency = 1 }):Play()
		Debris:AddItem(ring, 1.1)
	end)
end

local function winBanner(text)
	local g = Instance.new("ScreenGui"); g.Name = "CandyWin"; g.ResetOnSpawn = false; g.DisplayOrder = 20; g.IgnoreGuiInset = true; g.Parent = PlayerGui
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5, 0.5); f.Position = UDim2.new(0.5, 0, 0.42, 0)
	f.Size = UDim2.new(0, 0, 0, 90); f.BackgroundColor3 = FILL; f.Parent = g
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 18); c.Parent = f
	local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 4; s.Parent = f
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Size = UDim2.fromScale(1, 1); l.Font = Enum.Font.FredokaOne
	l.TextColor3 = TEXTC; l.TextScaled = true; l.Text = text; l.Parent = f
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 24); pad.PaddingRight = UDim.new(0, 24); pad.Parent = l
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 34; sz.Parent = l
	TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 640, 0, 90) }):Play()
	task.delay(5, function()
		TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.delay(0.5, function() g:Destroy() end)
	end)
end

-- ============================================================================
-- THE CRANK -- your prize gumball. Armed only after the quest is finished.
-- ============================================================================
local PRIZES = {
	{ name = "Bubblegum",       color = Color3.fromRGB(255, 92, 138) },
	{ name = "Blue Raspberry",  color = Color3.fromRGB(120, 200, 255) },
	{ name = "Apple Fizz",      color = Color3.fromRGB(150, 235, 130) },
	{ name = "Butterscotch",    color = Color3.fromRGB(255, 205, 90) },
	{ name = "Grape Nebula",    color = Color3.fromRGB(190, 130, 255) },
	{ name = "Cotton Candy",    color = Color3.fromRGB(255, 120, 220) },
}

-- The prize: a sparkling AURA in the flavour's colour. Orbiting neon motes + sparkles
-- that follow you around, survive respawns, and use no external assets (nothing to
-- fail to load). Built in Workspace and driven each frame off the character.
local auraOn = false
local function grantAura(color, name)
	if auraOn then return end
	auraOn = true

	local folder = Instance.new("Folder"); folder.Name = "PrizeAura"; folder.Parent = Workspace
	local motes = {}
	for i = 1, 6 do
		local o = mk({ Name = "AuraMote", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5),
			Color = color, Material = Enum.Material.Neon, Transparency = 1 })
		local sp = Instance.new("Sparkles"); sp.SparkleColor = color; sp.Parent = o
		if i <= 2 then   -- only a couple carry lights, so six of them don't blow out the scene
			local li = Instance.new("PointLight"); li.Color = color; li.Brightness = 1.3; li.Range = 9; li.Parent = o
		end
		o.Parent = folder
		motes[i] = o
	end

	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then   -- dead / respawning: park the motes until the character is back
			for _, o in ipairs(motes) do o.Transparency = 1 end
			return
		end
		t += dt
		for i, o in ipairs(motes) do
			local a = t * 1.7 + (i / #motes) * math.pi * 2
			o.Transparency = 0
			o.CFrame = CFrame.new(hrp.Position + Vector3.new(
				math.cos(a) * 2.9,
				math.sin(t * 2.2 + i * 1.3) * 1.1 + 0.4,
				math.sin(a) * 2.9))
		end
	end)

	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({ text = ("\xE2\x9C\xA8 You won the %s aura!"):format(name), color = color }) end)
	end
	print(("[CandyQuest] prize aura granted: %s"):format(name))
end

local crankPrompt
local cranked = false
local function armCrank()
	if not crankHandle or crankPrompt then return end
	crankPrompt = Instance.new("ProximityPrompt")
	crankPrompt.ActionText = "Crank"; crankPrompt.ObjectText = "Gumball Machine"
	crankPrompt.HoldDuration = 0.6; crankPrompt.MaxActivationDistance = 14
	crankPrompt.RequiresLineOfSight = false; crankPrompt.Parent = crankHandle

	-- glow so you can't miss it
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(255, 236, 170); hl.FillTransparency = 0.7
	hl.OutlineColor = Color3.fromRGB(255, 220, 120); hl.OutlineTransparency = 0.05
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = crankHandle; hl.Parent = crankHandle
	TweenService:Create(hl, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ FillTransparency = 0.95, OutlineTransparency = 0.6 }):Play()

	crankPrompt.Triggered:Connect(function()
		if cranked then return end
		cranked = true
		crankPrompt.Enabled = false
		hl:Destroy()

		-- the handle spins a full turn
		local pivot = crankHandle.CFrame * CFrame.new(0, -0.7, 0)
		task.spawn(function()
			for step = 1, 24 do
				crankHandle.CFrame = pivot * CFrame.Angles(0, 0, math.rad(step * 15)) * CFrame.new(0, 0.7, 0)
				task.wait(0.02)
			end
		end)

		-- the machine rattles
		if machine then
			local origin = machine:GetPivot()
			task.spawn(function()
				for step = 1, 18 do
					local j = (step % 2 == 0) and 0.09 or -0.09
					machine:PivotTo(origin * CFrame.new(j, 0, 0))
					task.wait(0.03)
				end
				machine:PivotTo(origin)
			end)
		end

		-- ...and the prize rolls out of the chute
		task.delay(0.55, function()
			local prize = PRIZES[((collected + os.time()) % #PRIZES) + 1]
			local from  = (chuteMouth and chuteMouth.Position or (machine and machine:GetPivot().Position)) + Vector3.new(0, 0, -1)
			local ball = mk({ Name = "PrizeBall", Shape = Enum.PartType.Ball, Size = Vector3.new(1.9, 1.9, 1.9),
				Color = prize.color, Material = Enum.Material.SmoothPlastic, Reflectance = 0.2 })
			ball.CFrame = CFrame.new(from); ball.Parent = Workspace
			burst(from, prize.color)

			-- hop out, then fly to the player and become a hat
			local hop = TweenService:Create(ball, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = CFrame.new(from + Vector3.new(0, 1.6, -2.2)) })
			hop.Completed:Connect(function()
				local char = player.Character
				local hrp  = char and char:FindFirstChild("HumanoidRootPart")
				if not hrp then ball:Destroy(); return end
				-- the gumball floats over to you and bursts into your new aura
				local fly = TweenService:Create(ball, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = hrp.CFrame * CFrame.new(0, 1.2, 0) })
				fly.Completed:Connect(function()
					local at = ball.Position
					ball:Destroy()
					burst(at, prize.color)
					grantAura(prize.color, prize.name)
					winBanner(("\xE2\x9C\xA8 %s aura!"):format(prize.name))
				end)
				fly:Play()
			end)
			hop:Play()
		end)
	end)
end

-- ============================================================================
-- CINEMATIC FINISH -- camera flies to the machine, shockwave + shake, fireworks
-- ============================================================================
local function cinematicFinish()
	local cam = Workspace.CurrentCamera
	local target = machine and machine:GetPivot().Position or (npcHead and npcHead.Position)
	if not (cam and target) then
		winBanner("\xF0\x9F\x8D\xAC You collected every gumball!")
		armCrank()
		return
	end

	local charPos = (player.Character and player.Character:GetPivot().Position) or (target + Vector3.new(0, 10, 30))
	local away = (charPos - target) * Vector3.new(1, 0, 1)
	away = (away.Magnitude > 1) and away.Unit or Vector3.new(0, 0, 1)
	local camCF = CFrame.lookAt(target + away * 22 + Vector3.new(0, 9, 0), target)

	local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	cam.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(cam, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = camCF }):Play()

	task.delay(1.05, function()
		shockwave(target, 0.00, Color3.fromRGB(255, 200, 235))
		shockwave(target, 0.12, Color3.fromRGB(255, 150, 200))
		local SHAKE, t0 = 0.6, os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local left = SHAKE - (os.clock() - t0)
			if left <= 0 or cam.CameraType ~= Enum.CameraType.Scriptable then
				conn:Disconnect()
				if cam.CameraType == Enum.CameraType.Scriptable then cam.CFrame = camCF end
				return
			end
			local mg = (left / SHAKE) ^ 2 * 2.4
			cam.CFrame = camCF * CFrame.new((math.random() - 0.5) * mg, (math.random() - 0.5) * mg, 0)
		end)
	end)

	task.delay(1.5, function() launchFireworks(target + Vector3.new(0, 6, 0)) end)
	task.delay(1.7, function() winBanner("\xF0\x9F\x8D\xAC You collected every gumball!") end)

	task.delay(4.2, function()
		cam.CameraType = Enum.CameraType.Custom
		if humanoid then cam.CameraSubject = humanoid end
		armCrank()   -- the crank only lights up once you have the camera back
		flashObjective("\xF0\x9F\x8D\xAD Crank the gumball machine for your prize!", 5)
	end)
end

local function completeQuest()
	_G.candyQuestComplete = true -- unlocks the island-1 Candy Stand
	updateObjective()            -- banner -> "Candy Stand unlocked!"
	if npcHead then task.delay(0.95, function() hideBubble(npcHead) end) end
	cinematicFinish()
	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({ text = ("\xF0\x9F\x8D\xAC Quest Complete! You collected all %d gumballs!"):format(TOTAL), color = STROKE }) end)
	end
	print(("[CandyQuest] complete -- %d/%d gumballs collected"):format(TOTAL, TOTAL))
end

local function collect(o)
	if o.done then return end
	if not questAccepted then
		flashObjective("\xF0\x9F\x8D\xAD Go accept the quest from Candy NPC first!", 2.5)
		return
	end
	o.done = true
	collected += 1
	updateObjective()
	playCollect()
	-- pop the orb: scale up + fade, then destroy
	local orb = o.orb
	if orb and orb.Parent then
		local pp = orb:FindFirstChildWhichIsA("ProximityPrompt", true); if pp then pp:Destroy() end
		for _, p in ipairs(orb:IsA("Model") and orb:GetDescendants() or {orb}) do
			if p:IsA("BasePart") then
				TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = p.Size * 1.6, Transparency = 1 }):Play()
			end
		end
		Debris:AddItem(orb, 0.4)
	end
	-- reactive NPC one-liner, heard anywhere on the island via the banner
	if collected < TOTAL then
		local line = nextLine()
		if npcHead then showBubble(npcHead, ("%s  (%d/%d)"):format(line, collected, TOTAL), false) end
		flashObjective(("\xF0\x9F\x8D\xAC %s  %d/%d"):format(line, collected, TOTAL), 3)
		-- ...then a beat later, a nudge toward the next one
		task.delay(3.2, function()
			if collected >= TOTAL then return end
			local hint = nextHint()
			if hint then flashObjective("\xF0\x9F\x8D\xAD " .. hint, 3) end
		end)
	end
	if collected >= TOTAL then
		completeQuest()
	end
end

-- ============================================================================
-- CHUTE RATTLE -- the per-gumball minigame.
-- ============================================================================
-- The gumball is wedged in the chute. A knocker sweeps the track; knock while it's over
-- the green patch and the gumball shifts. Every clean hit speeds the knocker up, narrows
-- the patch, and moves it somewhere new -- so the last knock is the hard one. It's a
-- TIMING game, not a tapping game: blind mashing lands about half its hits and the misses
-- cost 10% each, so it is strictly worse than waiting for the green.
--
-- THE FLOOR IS THE CEILING. `ceiling` climbs from 0 to 1 over exactly RATTLE_SECONDS
-- and the bar is clamped to it every frame AND on every tap, so no amount of mashing
-- finishes this early. Tapping slower than the ceiling just costs extra time. This is
-- the only enforcement that is exact and un-gameable -- tuning gain rates is not.
--
-- Closing: the X button only. A backdrop tap NEVER closes it (house rule) -- and the
-- backdrop deliberately has no input handler at all rather than a swallowed one.
local rattleOpen = false
local function openRattle(orbModel, onDone)
	if rattleOpen then return end          -- one panel at a time
	rattleOpen = true

	local candy = orbModel and orbModel:FindFirstChild("Candy")
	local light = candy and candy:FindFirstChildWhichIsA("PointLight")
	local baseSize = candy and candy.Size

	local gui = Instance.new("ScreenGui")
	gui.Name = "ChuteRattle"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90; gui.Parent = PlayerGui

	-- dim film: 0.5 so the real gumball stays visible reacting behind the panel
	local film = Instance.new("Frame")
	film.Size = UDim2.fromScale(1, 1); film.BackgroundColor3 = Color3.new(0, 0, 0)
	film.BackgroundTransparency = 0.5; film.BorderSizePixel = 0; film.Parent = gui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(420, 292); panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(25, 90, 185); panel.BorderSizePixel = 0; panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
	local ps = Instance.new("UIStroke", panel); ps.Color = Color3.new(1, 1, 1); ps.Thickness = 3

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -60, 0, 40); title.Position = UDim2.fromOffset(18, 12)
	title.Font = Enum.Font.GothamBold; title.TextSize = 22; title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 215, 0); title.Text = "Shake it loose!"; title.Parent = panel

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1; hint.Size = UDim2.new(1, -36, 0, 22); hint.Position = UDim2.fromOffset(18, 48)
	hint.Font = Enum.Font.Gotham; hint.TextSize = 14; hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = Color3.new(1, 1, 1); hint.Text = "Knock when the marker hits the green"; hint.Parent = panel

	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(34, 34); close.Position = UDim2.new(1, -44, 0, 12)
	close.BackgroundColor3 = Color3.fromRGB(220, 70, 70); close.Text = "X"; close.TextColor3 = Color3.new(1, 1, 1)
	close.Font = Enum.Font.GothamBold; close.TextSize = 18; close.AutoButtonColor = true; close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 8)

	-- progress bar
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -36, 0, 26); track.Position = UDim2.fromOffset(18, 92)
	track.BackgroundColor3 = Color3.fromRGB(12, 50, 110); track.BorderSizePixel = 0; track.Parent = panel
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, 8)
	local fillBar = Instance.new("Frame")
	fillBar.Size = UDim2.fromScale(0, 1); fillBar.BackgroundColor3 = Color3.fromRGB(150, 235, 130)
	fillBar.BorderSizePixel = 0; fillBar.Parent = track
	Instance.new("UICorner", fillBar).CornerRadius = UDim.new(0, 8)

	-- THE TIMING TRACK. A knocker slides back and forth; the green patch is where the
	-- gumball is jammed. Knock while the marker is ON the patch and it shifts down the
	-- chute. Every clean hit speeds the knocker up AND narrows the patch AND moves it
	-- somewhere new -- so the last knock is the hard one, and there is something to get
	-- better at instead of the same blind tap twelve times.
	local trackF = Instance.new("Frame")
	trackF.Size = UDim2.new(1, -36, 0, 46); trackF.Position = UDim2.fromOffset(18, 132)
	trackF.BackgroundColor3 = Color3.fromRGB(12, 50, 110); trackF.BorderSizePixel = 0; trackF.Parent = panel
	Instance.new("UICorner", trackF).CornerRadius = UDim.new(0, 8)

	local zone = Instance.new("Frame")
	zone.BackgroundColor3 = Color3.fromRGB(150, 235, 130); zone.BorderSizePixel = 0
	zone.Size = UDim2.new(0.26, 0, 1, 0); zone.Parent = trackF
	Instance.new("UICorner", zone).CornerRadius = UDim.new(0, 6)

	local needle = Instance.new("Frame")
	needle.BackgroundColor3 = Color3.new(1, 1, 1); needle.BorderSizePixel = 0
	needle.Size = UDim2.new(0, 6, 1, 0); needle.ZIndex = 3; needle.Parent = trackF
	Instance.new("UICorner", needle).CornerRadius = UDim.new(0, 3)

	local knock = Instance.new("TextButton")
	knock.Size = UDim2.new(1, -36, 0, 76); knock.Position = UDim2.fromOffset(18, 190)
	knock.BackgroundColor3 = Color3.fromRGB(214, 92, 158); knock.Text = "KNOCK"
	knock.TextColor3 = Color3.new(1, 1, 1); knock.Font = Enum.Font.GothamBold; knock.TextSize = 30
	knock.AutoButtonColor = false; knock.Parent = panel
	Instance.new("UICorner", knock).CornerRadius = UDim.new(0, 10)
	local kst = Instance.new("UIStroke", knock); kst.Color = Color3.new(1, 1, 1); kst.Thickness = 2

	local fill, ceiling = 0, 0
	local ceilRate = 1 / RATTLE_SECONDS
	local pos, dir = 0, 1
	local zc, zw = 0.5, 0.26          -- zone centre / width, both re-rolled on every hit
	local streak = 0
	local finished = false
	local conn

	local function drawZone()
		zone.Position = UDim2.new(math.clamp(zc - zw * 0.5, 0, 1 - zw), 0, 0, 0)
		zone.Size = UDim2.new(zw, 0, 1, 0)
	end
	drawZone()

	local function shut(success)
		if finished then return end
		finished = true; rattleOpen = false
		if conn then conn:Disconnect() end
		-- ALWAYS put the world prop back the way we found it, win or bail
		if candy and candy.Parent and baseSize then candy.Size = baseSize end
		if light and light.Parent then light.Brightness = 1.6 end
		gui:Destroy()
		onDone(success)
	end

	local function flash(good)
		kst.Color = good and Color3.fromRGB(150, 235, 130) or Color3.fromRGB(255, 120, 110)
		knock.BackgroundColor3 = good and Color3.fromRGB(120, 200, 255) or Color3.fromRGB(150, 60, 90)
		task.delay(0.14, function()
			if finished then return end
			kst.Color = Color3.new(1, 1, 1)
			knock.BackgroundColor3 = Color3.fromRGB(214, 92, 158)
		end)
	end

	knock.Activated:Connect(function()
		if finished then return end
		if math.abs(pos - zc) <= zw * 0.5 then
			streak += 1
			fill = math.min(fill + RATTLE_HIT, ceiling)   -- clamped on input as well as per-frame
			-- it gets harder as it loosens: faster knocker, tighter patch, new spot
			zw = math.max(0.12, zw - 0.012)
			zc = 0.16 + math.random() * 0.68
			drawZone()
			hint.Text = (streak >= 3) and ("Nice -- %d in a row!"):format(streak) or "Good knock!"
			flash(true)
		else
			streak = 0
			fill = math.max(0, fill - RATTLE_MISS)
			hint.Text = "Missed it -- wait for the green"
			flash(false)
		end
	end)
	close.Activated:Connect(function() shut(false) end)

	conn = RunService.RenderStepped:Connect(function(dt)
		if finished then return end
		ceiling = math.min(1, ceiling + ceilRate * dt)
		fill = math.min(fill, ceiling)
		fillBar.Size = UDim2.fromScale(fill, 1)

		-- knocker sweeps faster the looser the gumball gets
		pos += dir * (0.42 + fill * 0.55) * dt
		if pos >= 1 then pos, dir = 1, -1 elseif pos <= 0 then pos, dir = 0, 1 end
		needle.Position = UDim2.new(pos, -3, 0, 0)
		-- the marker turns green the instant it's over the patch, so the timing is READABLE
		local onZone = math.abs(pos - zc) <= zw * 0.5
		needle.BackgroundColor3 = onZone and Color3.fromRGB(150, 235, 130) or Color3.new(1, 1, 1)

		-- the real gumball rattles harder the closer it is to coming free
		if candy and candy.Parent and baseSize then
			candy.Size = baseSize * (1 + math.sin(os.clock() * 28) * 0.05 * fill)
		end
		if light and light.Parent then light.Brightness = 1.6 + fill * 2.4 end
		if fill >= 1 then shut(true) end
	end)
end

local function spawnOrb(brick, idx)
	if wiredBricks[brick] then return end
	wiredBricks[brick] = true
	local pos = brick.Position
	-- HIDE the source brick -> invisible anchor
	brick.Transparency = 1; brick.CanCollide = false; brick.CanQuery = false; brick.Anchored = true

	local color  = CANDY_COLORS[((idx - 1) % #CANDY_COLORS) + 1]
	local center = CFrame.new(pos + Vector3.new(0, 1.6, 0))

	local model = Instance.new("Model"); model.Name = "GumballOrb"

	-- glossy candy sphere
	local orb = Instance.new("Part")
	orb.Name = "Candy"; orb.Shape = Enum.PartType.Ball; orb.Material = Enum.Material.SmoothPlastic
	orb.Size = Vector3.new(ORB_SIZE, ORB_SIZE, ORB_SIZE); orb.Color = color; orb.Reflectance = 0.2
	orb.Anchored = true; orb.CanCollide = false; orb.CanQuery = true; orb.CastShadow = false
	orb.CFrame = center; orb.Parent = model
	model.PrimaryPart = orb

	-- white specular highlight dot (fakes a glossy candy shine)
	local shine = Instance.new("Part")
	shine.Name = "Shine"; shine.Shape = Enum.PartType.Ball; shine.Material = Enum.Material.Neon; shine.Color = Color3.new(1, 1, 1)
	shine.Size = Vector3.new(ORB_SIZE * 0.34, ORB_SIZE * 0.34, ORB_SIZE * 0.34); shine.Transparency = 0.3
	shine.Anchored = true; shine.CanCollide = false; shine.CanQuery = false; shine.CastShadow = false
	shine.CFrame = center * CFrame.new(-ORB_SIZE * 0.22, ORB_SIZE * 0.24, -ORB_SIZE * 0.22); shine.Parent = model

	-- candy rim glow + soft light + shimmer
	local hl = Instance.new("Highlight"); hl.FillTransparency = 1; hl.OutlineColor = color; hl.OutlineTransparency = 0.15
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = orb; hl.Parent = model
	local glow = Instance.new("PointLight"); glow.Color = color; glow.Brightness = 1.6; glow.Range = 9; glow.Parent = orb
	local spk = Instance.new("Sparkles"); spk.SparkleColor = color; spk.Parent = orb

	model.Parent = Workspace

	-- bob + spin (PivotTo moves the whole model together)
	task.spawn(function()
		local base = model:GetPivot()
		local t = idx * 0.7
		while model.Parent do
			t += 0.06
			model:PivotTo(base * CFrame.new(0, math.sin(t) * 0.4, 0) * CFrame.Angles(0, t * 0.5, 0))
			task.wait(0.03)
		end
	end)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Shake Loose"; prompt.ObjectText = "Gumball"; prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = COLLECT_DISTANCE; prompt.RequiresLineOfSight = false; prompt.Parent = orb

	local entry = { pos = pos, orb = model, prompt = prompt, done = false }
	prompt.Triggered:Connect(function()
		-- the "accept the quest first" nudge has to fire BEFORE the panel opens, not after
		-- 15 seconds of work -- so it stays on collect()'s guard, checked up front here.
		if entry.done then return end
		if not questAccepted then
			flashObjective("\xF0\x9F\x8D\xAD Go accept the quest from Candy NPC first!", 2.5)
			return
		end
		prompt.Enabled = false
		openRattle(model, function(success)
			if success then
				collect(entry)
			-- re-arm behind the SAME guard the trigger uses, or a finished orb re-arms itself
			elseif not entry.done and prompt.Parent then
				prompt.Enabled = true
			end
		end)
	end)
	orbs[#orbs + 1] = entry
end

-- ============================================================================
-- NPC DIALOGUE WIRING (paged prompt, refreshes progress each open)
-- ============================================================================
local function wireNPC(head)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = "Candy Npc"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = COLLECT_DISTANCE; prompt.RequiresLineOfSight = false; prompt.Parent = head -- 12 studs, same as the food stand

	local pages, index = nil, 0
	local watching = false
	local function closeDialogue() hideBubble(head); prompt.ActionText = "Talk"; index = 0; pages = nil end

	-- walk-away watcher: close the speech bubble the moment the player is farther than
	-- COLLECT_DISTANCE (same range as the food stand), not only when the prompt hides.
	local function startWatcher()
		if watching then return end
		watching = true
		task.spawn(function()
			while index ~= 0 do
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not hrp or (hrp.Position - head.Position).Magnitude > COLLECT_DISTANCE then
					closeDialogue(); break
				end
				task.wait(0.25)
			end
			watching = false
		end)
	end

	prompt.Triggered:Connect(function()
		if index == 0 then pages = questPages(collected, questAccepted and nextHint() or nil) end
		index += 1
		if not pages or index > #pages then closeDialogue(); return end
		if index == 2 then acceptQuest() end -- reading past page 1 = accepting the quest
		local last = index >= #pages
		local footer = last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages)
		showBubble(head, pages[index], true, footer)
		prompt.ActionText = last and "Close" or "Continue"
		startWatcher()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then closeDialogue() end end)
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	npcHead = pollFor(findNPCHead, 45)
	if not npcHead then
		warn("[CandyQuest] no NPC named 'Candy Npc' found in Workspace -- quest NPC not wired")
	else
		wireNPC(npcHead)
		buildMachine(npcHead)   -- her gumball machine, right beside her (the finale's stage)
		-- On spawn: show the "go talk to the Candy NPC" banner + directional arrows leading
		-- to the NPC. Both clear once the quest is accepted (acceptQuest / on talk page 2).
		updateObjective()
		task.spawn(function()
			while not questAccepted and npcHead and npcHead.Parent do
				if _G.guideTrailTo then _G.guideTrailTo(npcHead.Position) end -- re-assert (GardenGuideTrail may override)
				task.wait(2)
			end
			if _G.guideTrailClear then _G.guideTrailClear() end
		end)
	end

	-- STREAMING: the old version returned the moment ONE brick existed, so on island1 it
	-- routinely grabbed a partial set (3 of 4) and then TOTAL never moved -- an
	-- uncompletable 3/4 quest. Two fixes, both needed:
	--   1. keep polling until we have TOTAL of them, holding on to the BIGGEST set seen
	--   2. if we still time out short, TOTAL becomes what actually spawned, so whatever
	--      the world gives us is always finishable
	local bricks = {}
	do
		local t0 = os.clock()
		repeat
			local g = findGumballs()
			if #g > #bricks then bricks = g end
			if #bricks >= TOTAL then break end
			task.wait(0.5)
		until os.clock() - t0 > 45
	end

	if #bricks == 0 then
		warn("[CandyQuest] no bricks named 'gumball' found -- nothing to collect")
	else
		if #bricks < TOTAL then
			warn(("[CandyQuest] only %d of %d 'gumball' bricks streamed in -- the quest now asks for %d")
				:format(#bricks, TOTAL, #bricks))
			TOTAL = #bricks
		elseif #bricks > TOTAL then
			-- more bricks in the world than the quest asks for: take the first TOTAL and
			-- leave the rest hidden, so the count in the banner is the count you can find
			warn(("[CandyQuest] found %d 'gumball' bricks, only %d needed -- using the first %d")
				:format(#bricks, TOTAL, TOTAL))
			while #bricks > TOTAL do table.remove(bricks) end
		end
		for i, b in ipairs(bricks) do spawnOrb(b, i) end
	end

	-- LATE ARRIVALS: island1 hands the rest of itself over as you walk around it, so a brick
	-- that shows up after the window still becomes a real gumball (and raises the target).
	task.spawn(function()
		while #orbs > 0 and collected < TOTAL do
			task.wait(3)
			for _, b in ipairs(findGumballs()) do
				if not wiredBricks[b] then
					spawnOrb(b, #orbs + 1)
					TOTAL += 1
					print(("[CandyQuest] a late gumball streamed in -- target is now %d"):format(TOTAL))
					updateObjective()
				end
			end
		end
	end)

	updateObjective()
	print(("[CandyQuest] ready -- Candy Npc %s, %d gumball orb(s) spawned, target %d")
		:format(npcHead and "wired" or "MISSING", #orbs, TOTAL))
end)

-- ============================================================================
-- /complete -- test command: instantly finish the gumball quest (unlocks the stand)
-- ============================================================================
local function onCommand(msg)
	if tostring(msg or ""):lower():sub(1, 9) ~= "/complete" then return end
	-- only completes when you're standing on island1 (near ITS NPC). If that NPC isn't found
	-- yet, do nothing -- never complete on a "maybe", or /complete on another island fires this.
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (npcHead and npcHead.Parent and hrp) then return end
	if (hrp.Position - npcHead.Position).Magnitude > 320 then return end
	questAccepted = true; collected = TOTAL; updateObjective(); completeQuest()
	print("[CandyQuest][TEST] /complete -- gumball quest complete, Candy Stand unlocked")
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
