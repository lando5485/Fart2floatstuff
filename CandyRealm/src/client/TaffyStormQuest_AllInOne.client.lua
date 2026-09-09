--======================================================================
-- TaffyStormQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- ISLAND-5 QUEST: "THE TAFFY STORM"
--
-- A taffy storm is rolling in over island5. You cannot catch it bare-handed -- so you gather
-- sugar reed off all three islets, weave your own basket, and then catch the storm with it.
--
-- Island 5 is three small islands and the first place you can properly fly, so the reed is
-- scattered across all three: flying between them IS the middle of the quest.
--
-- WHAT THE WORLD PROVIDES:
--   * a "Candy Npc" on island5 -- she starts it (nearest to island5)
--   * (optional) parts named  reed / cane / sugarcane / anchor1..n  -- each becomes a reed.
--     Name them and the reeds stand exactly where you put them; leave them out and they are
--     scattered on a ring around the island instead, which plays but ignores your layout.
--   * (optional) a part named  stormspot  -- centres the falling candy somewhere specific
--
-- HOW IT PLAYS:
--   Talk to her -> she tells you to make a basket
--   -> find 6 sugar reeds across the three islands (they glow gold and are labelled)
--   -> hold E at the weaving stand by her to weave YOUR basket
--   -> the storm breaks; candy rains down over the island
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
local islandModel   -- the island5 Model itself: the reed ring tests candidate ground against it
-- the island's vertical EXTENT, not just its centre -- groundAt() needs somewhere above the
-- island to start a downward cast from, and islandPos is nowhere near the top of it.
local islandTopY, islandBotY
local accepted, storming, done = false, false, false
local STORM_RANGE = 900   -- how far from the storm's centre still counts as "under it"

-- ARE YOU UNDER THE STORM? The three islets are one weather system, so this is a single radius
-- around the storm centre rather than a per-islet test.
--
-- WHY IT EXISTS. runStorm's tail loop is deliberately unbounded -- "it rains until you have them",
-- so the quest cannot be failed -- but nothing checked that you were still there to catch any. Fly
-- off island5 mid-storm and candy kept falling on an empty island for the rest of the session, and
-- worse, the storm SKY stayed on: setStormSky writes global Lighting, so every island in the realm
-- sat under island5's weather until you came back and caught ten pieces. Pausing is the fix, not
-- stopping: the storm is still yours when you return, at the count you left it on.
local function underStorm()
	local ref = stormCentre or islandPos
	if not ref then return true end
	local hrp = hrpOf()
	if not hrp then return true end        -- mid-respawn: hold, do not judge
	return (hrp.Position - ref).Magnitude <= STORM_RANGE
end
local caught, missed = 0, 0
local waveNum = 0
local hasBasket = false
_G.stormQuestComplete = false

-- ⚠ DECLARED HERE, WITH THE REST OF THE STATE, AND NOT BESIDE THE CODE THAT BUILDS REEDS.
-- bannerText() below reads reedsHeld and REED_COUNT, and it sits ~340 lines ABOVE where these
-- used to live -- so the names in the banner resolved to GLOBALS instead, both nil, and every
-- refresh threw "attempt to compare nil < nil". A Lua local is invisible above its own
-- declaration; anything the banner touches has to be declared before the banner.
-- ⚠ CUT FROM 6 REEDS ON A 165-STUD SPREAD. Cutting a reed is an INSTANT E-tap (HoldDuration 0,
-- no minigame, no variation) -- so six of them on a 91-181 stud scatter across three islets was
-- ~90% travel time bracketed by a zero-duration interaction, and reed 6 played exactly like
-- reed 1. The storm-catching finale is the good half of this quest and it was gated behind the
-- dull half. Three reeds on a tighter spread keeps "you gathered the basket from all three
-- islands" while cutting the walking roughly in half.
local REED_COUNT   = 3           -- how many reeds the basket takes
local REED_SPREAD  = 120         -- how far from the island centre they scatter
-- names you can give parts in Studio to place reeds by hand. Anything matching becomes a reed
-- spot; leftover spots are auto-placed on a ring so the quest never depends on you naming them.
-- ⚠ THE OLD ANCHOR NAMES ARE IN HERE ON PURPOSE. island5 was built for the three-anchor version
-- of this quest, so the parts already standing on it are called guyser / kite / rod / anchor1..3.
-- Dropping those names would have silently ignored every marker on the island and auto-placed
-- all six reeds on a ring -- which is exactly what the boot log showed ("0 on your parts").
-- Anything matching becomes a reed spot; the ring only fills what your parts do not.
local REED_HINTS   = { "reed", "cane", "sugarcane", "sugarreed", "anchor",
	"guyser", "geyser", "vent", "kite", "updraft", "rod", "lightningrod", "beacon" }

local reeds = {}                 -- { model =, pos =, taken = }
local reedsHeld = 0
local weaveStand                 -- the weaving spot at the NPC, built once she gives the job
local stormCollapse              -- forward: weaving the basket brings the storm down

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
	if not accepted then
		return "\xF0\x9F\x8C\xA7 A taffy storm is coming! Talk to the Candy NPC -- follow the green arrows."
	end
	if not hasBasket then
		if reedsHeld < REED_COUNT then
			return ("\xF0\x9F\x8C\xBE Press Cut on the tall pink Sugar Reed:  %d/%d  (it grows on all 3 islands)")
				:format(reedsHeld, REED_COUNT)
		end
		return "\xF0\x9F\xA7\xBA Take the reed back to the Candy NPC and hold Weave on the loom!"
	end
	if storming then
		return ("\xF0\x9F\x8D\xAC Stand in a shadow on the ground to catch the taffy!  %d/%d   (wave %d/%d)")
			:format(caught, TARGET, waveNum, #WAVES)
	end
	return ("\xF0\x9F\x8C\xA7 Storm incoming -- get ready to catch!  %d/%d caught"):format(caught, TARGET)
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
	-- only re-issue a basket you EARNED: before weaving there is nothing to give back
	if accepted and not done and hasBasket then hasBasket = false; giveBasket() end
end)

-- ============================================================================
-- STORM WEATHER -- sky darkens while it blows, restored when it clears
-- ============================================================================
local skySaved = nil
local function setStormSky(on)
	-- Tell SkyByAltitude to stand down while the storm is up: it rewrites Brightness and OutdoorAmbient
	-- every frame otherwise, and this dim is the storm's whole look. Released the moment it clears, and
	-- also whenever you leave the island (waitUntilBack calls setStormSky(false)).
	local claims = _G.questSkyClaims; if not claims then claims = {}; _G.questSkyClaims = claims end
	claims.storm = on or nil
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
	-- PAYOFF SHOT, the same one every other island now gets. TARGETS[5] resolves the subject.
	task.delay(1.0, function() if _G.revealIsland then pcall(_G.revealIsland, 5) end end)
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

	-- ⚠ ANNOUNCEMENTS GO THROUGH THE ONE REALM BANNER -- NEVER A ScreenGui OF THEIR OWN.
	-- This is realm 1's rule (see NotifyCenter.luau: push/pin is the whole API). This quest was
	-- the clearest case for it: it built its OWN "STORM WEATHERED!" card in the middle of the
	-- screen AND pushed a banner saying the same thing, so finishing announced itself twice, in
	-- two places, at two different sizes. One push now, and the catch count -- the only thing
	-- the card said that the banner did not -- comes with it.
	--
	-- The confetti above stays: that is a world effect, not an announcement.
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(function() _G.NotifyCenter.push({
			top      = "\xE2\x9C\xA8 QUEST COMPLETE",
			text     = ("\xF0\x9F\x8D\xAC Taffy Storm weathered!  %d caught"):format(caught),
			color    = STROKE,
			priority = _G.NotifyCenter.PRIORITY and _G.NotifyCenter.PRIORITY.EVENT or nil,
			duration = 5,
		}) end)
	end
	print(("[Storm] complete -- %d caught, %d missed"):format(caught, missed))
end

local function runStorm()
	if storming or done then return end
	storming = true
	setStormSky(true)
	playSound(SOUND_STORM, 0.5)

	-- Holds here for as long as you are away, putting the sky back while you are gone and pulling it
	-- over again when you return. Returns false only if the quest ended while you were off the island,
	-- which lets every loop below break cleanly instead of raining into an empty sky.
	local function waitUntilBack()
		if done then return false end
		if underStorm() then return true end
		setStormSky(false)
		repeat task.wait(0.5) until done or underStorm()
		if done then return false end
		setStormSky(true)
		return true
	end

	for w, wave in ipairs(WAVES) do
		if done or caught >= TARGET then break end
		if not waitUntilBack() then break end
		waveNum = w
		flash(("\xF0\x9F\x8C\xA7 Wave %d/%d -- %s!"):format(w, #WAVES, wave.name), 2.2)
		task.wait(1.6)
		for _ = 1, wave.drops do
			if done or caught >= TARGET then break end
			if not waitUntilBack() then break end
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
		if not waitUntilBack() then break end
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

-- things a ground cast must not mistake for ground: reeds already planted, the loom. Appended
-- as they are built, so reed 4 can never come to rest on top of reed 3.
local groundIgnore = {}

-- WHERE THE GROUND IS UNDER A POINT.
--
-- ⚠ THIS USED TO START THE CAST 60 STUDS ABOVE `pos`, AND `pos` COMES FROM islandPos, WHICH IS
-- THE BOUNDING-BOX **CENTRE** OF THE ISLAND MODEL -- not its surface. On a model whose box is
-- stretched upward by anything tall (a tree, a spire, the storm rig), the walkable top sits far
-- more than 60 studs above that centre, so the cast began UNDERGROUND, travelled down, and hit
-- nothing. The old fallback then returned `pos.Y` -- the centre again -- and the reed was built
-- at the island's mid-height: inside the rock, which is exactly the "not on the surface" you saw.
--
-- So: start above the island's actual TOP, and stop below its BOTTOM.
--
-- ⚠ AND SKIP NON-COLLIDABLE HITS. The first thing under a high start point is often a cloud, a
-- canopy or a glow part. Taking the first hit blindly plants reeds in the air on top of scenery;
-- stepping under each non-collidable hit and carrying on down finds the surface you stand on.
-- The honest half of groundAt: (Y, instance) for a REAL CanCollide hit, or nil for open air.
-- The reed ring needs the distinction -- "the island top is a safe guess" is fine for a marker
-- somebody placed, and exactly wrong for deciding whether a ring spot has ground at all.
local function solidGroundAt(pos)
	local ignore = {}
	if player.Character then ignore[#ignore + 1] = player.Character end
	for _, m in ipairs(groundIgnore) do
		if m and m.Parent then ignore[#ignore + 1] = m end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	rp.IgnoreWater = true

	local botY = (islandBotY or (pos.Y - 300)) - 40
	local from = Vector3.new(pos.X, (islandTopY or pos.Y) + 120, pos.Z)
	for _ = 1, 8 do
		if from.Y <= botY then break end
		local hit = Workspace:Raycast(from, Vector3.new(0, botY - from.Y, 0), rp)
		if not hit then break end
		if hit.Instance.CanCollide then return hit.Position.Y, hit.Instance end
		from = Vector3.new(pos.X, hit.Position.Y - 0.25, pos.Z)
	end
	return nil
end

local function groundAt(pos)
	local y = solidGroundAt(pos)
	if y then return y end
	-- nothing solid under this point at all. The island TOP is the safe guess -- a reed stood a
	-- little high is findable; the old fallback buried it.
	return islandTopY or pos.Y
end

-- ============================================================================
-- THE BASKET IS SOMETHING YOU MAKE
-- ============================================================================
-- ⚠ WHAT THIS REPLACED, AND WHY. Island 5 used to be three "storm anchors", one per islet,
-- each a different bar-and-needle mini-game: tap-in-the-green on a sweeping needle, hold-and-
-- release a reeling bar through random gusts, and alternate-tap the two ends of a crank. Three
-- HUD puzzles wearing island hats. None of them was about the storm, none was about island 5,
-- and the gusts and green-zone positions were randomised, so the honest way to play was to
-- guess and eat the failures.
--
-- What was GOOD about the island was the catching -- standing under falling candy with a basket
-- -- and the fact that it is the first place you can properly fly. So the middle is now the
-- thing that earns the catching: the basket is not handed to you, you BUILD it. Sugar reeds are
-- scattered across all three islets, you fly around gathering them, and then you weave them at
-- the NPC. Same three-island layout, same reason to fly, no bars and no guessing -- and the
-- basket you catch with is one you made.

-- ---- finding your markers -------------------------------------------------
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

-- ⚠ THE THREE HELPERS ABOVE ARE HOISTED ON PURPOSE. scatterReeds() calls markerSpot,
-- markerIs and hideMarker; they used to be defined ~150 lines BELOW it (they had sat under the
-- old anchor-placing code, which ran late). Being locals, they were simply nil where the reeds
-- needed them -- "attempt to call a nil value" on the first sweep, so no reed was ever built
-- and the quest never reached its ready flag. Helpers before callers.

-- A SUGAR REED: a tall striped cane with a tuft, standing on the ground. Deliberately tall and
-- brightly banded -- these are scattered over three islets and half the job is SPOTTING one
-- from the air, so a small tasteful prop would be a worse prop.
local function buildReed(pos, index)
	local m = Instance.new("Model"); m.Name = "SugarReed" .. index; m.Parent = Workspace
	local at = CFrame.new(pos)
	local function bit(props, cf) props.Parent = m; local p = mk(props); p.CFrame = cf; return p end

	-- the cane: stacked segments, alternating pink and cream, leaning slightly
	local lean = CFrame.Angles(math.rad((index % 3) * 4 - 4), 0, math.rad((index % 5) * 3 - 6))
	local root
	for i = 1, 7 do
		local p = bit({ Shape = Enum.PartType.Cylinder,
			Color = (i % 2 == 0) and Color3.fromRGB(255, 138, 186) or Color3.fromRGB(255, 240, 232),
			Size = Vector3.new(1.35, 0.62, 0.62) },
			at * lean * CFrame.new(0, 0.9 + (i - 1) * 1.3, 0) * CFrame.Angles(0, 0, math.rad(90)))
		root = root or p
	end
	-- the tuft on top, so it reads from a distance and from above
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		bit({ Color = Color3.fromRGB(180, 232, 150), Size = Vector3.new(0.22, 1.9, 0.5) },
			at * lean * CFrame.new(math.cos(a) * 0.45, 9.9, math.sin(a) * 0.45)
				* CFrame.Angles(math.rad(26), -a, 0))
	end
	m.PrimaryPart = root

	-- FINISHED THE WAY THE TRACTOR ISLAND FINISHES ITS PICKUPS.
	--
	-- ⚠ OUTLINE ONLY, NEVER A FILL. A Highlight with any FillTransparency below 1 washes the
	-- whole model in gold, which reads as a part fading OUT rather than one you can take. The
	-- outline alone says "pick this up", and because it is AlwaysOnTop it draws through terrain
	-- -- which is exactly what makes six reeds findable across three islets from the air.
	--
	-- ⚠ AND NO FLOATING NAME LABEL, for the reason the tractor file argues at length: names
	-- over pickups stack into an unreadable pile wherever two are close and stay legible from
	-- the next island up. The E prompt names it the moment you are near enough to cut it, which
	-- is where the name is worth anything.
	local hl = Instance.new("Highlight")
	hl.FillColor = GOLD; hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(255, 236, 170); hl.OutlineTransparency = 0.05
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = m; hl.Parent = m
	return m, root
end

-- forward: weaving needs the basket, and giveBasket is defined far above
local function reedTaken(rec)
	if rec.taken or not accepted then return end
	rec.taken = true
	reedsHeld += 1
	playSound(SOUND_CATCH, 0.5)
	catchBurst(rec.pos + Vector3.new(0, 5, 0), GOLD)
	if rec.model.Parent then rec.model:Destroy() end
	refreshBanner()
	if reedsHeld >= REED_COUNT then
		flash("\xF0\x9F\xA7\xBA That is enough reed -- go and hold Weave on the Reed Loom!", 3.4)
		-- the stand only lights up once you can actually use it, so a player who wanders past
		-- it early is never told to press something that would refuse them
		if weaveStand and weaveStand.prompt then weaveStand.prompt.Enabled = true end
		if _G.guideTrailTo and weaveStand then
			pcall(function() _G.guideTrailTo(weaveStand.pos) end)
		end
	else
		flash(("\xF0\x9F\x8C\xBE Reed %d/%d"):format(reedsHeld, REED_COUNT), 1.6)
	end
end

local function wireReed(rec, root)
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = "Cut"; pr.ObjectText = "Sugar Reed"
	pr.HoldDuration = 0; pr.MaxActivationDistance = 14
	pr.RequiresLineOfSight = false; pr.Parent = root
	root.CanQuery = true
	pr.Triggered:Connect(function(plr) if plr == player then reedTaken(rec) end end)
	rec.prompt = pr
end

-- WHERE THE REEDS GO. Parts you named win; the rest ring the island so the quest still plays
-- on a world where nobody has placed anything. Spread wide on purpose -- the point is that they
-- are on all three islets and you fly between them.
local function scatterReeds()
	local marks = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and not d:IsA("Tool") and #marks < REED_COUNT then
			local spot = markerSpot(d)
			if spot and (spot - islandPos).Magnitude <= 900 and markerIs(d, REED_HINTS) then
				marks[#marks + 1] = { part = d, pos = spot }
			end
		end
	end
	table.sort(marks, function(x, y) return x.part.Name < y.part.Name end)

	local named = 0
	for i = 1, REED_COUNT do
		local pos
		if marks[i] then
			named += 1
			-- HIDE FIRST, THEN CAST: hideMarker() clears CanCollide, so after it has run the marker
			-- can no longer be mistaken for the ground beneath itself. Your part decides WHERE the
			-- reed goes in X/Z; the surface under it decides how high, so a marker you left floating
			-- (or buried) still yields a reed stood properly on the island.
			hideMarker(marks[i].part)
			local mp = marks[i].pos
			pos = Vector3.new(mp.X, groundAt(mp), mp.Z)
		else
			-- ===== THE RING IS A CANDIDATE, NOT AN ANSWER =====
			-- island5 is three islets with open air between them, and the old ring dropped each
			-- reed wherever its circle happened to say -- over a gap, past a rim -- and groundAt
			-- then seated it on whatever lay far below, or floated it at the island-top guess
			-- (the boot log showed reeds 200+ studs under the top). A spot only counts now if a
			-- ray HITS something solid that belongs to island5's own model, within a sane band
			-- of its top: inside the island's bounds AND touching a real object, which is the
			-- whole ask. The search keeps the golden-angle spread but spirals inward until it
			-- finds such ground; the island's own centre qualifies, so it cannot come up empty.
			pos = nil
			for try = 0, 11 do
				local ang = (i + try * REED_COUNT) * 2.39996
				local rad = REED_SPREAD * (0.55 + ((i * 0.37) % 1) * 0.55) * (1 - try * 0.085)
				local p = islandPos + Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)
				local gy, inst = solidGroundAt(p)
				if gy and inst
					and (islandModel == nil or inst:IsDescendantOf(islandModel))
					and (not islandTopY or math.abs(gy - islandTopY) <= 90) then
					pos = Vector3.new(p.X, gy, p.Z)
					break
				end
			end
			if not pos then   -- every candidate refused: stand it at the centre, on real ground
				pos = Vector3.new(islandPos.X, groundAt(islandPos), islandPos.Z)
			end
		end
		local rec = { pos = pos, taken = false }
		local m, root = buildReed(pos, i)
		groundIgnore[#groundIgnore + 1] = m     -- so the next reed does not land on this one
		rec.model = m
		reeds[i] = rec
		wireReed(rec, root)
	end
	if named == 0 then
		warn(("[Storm] none of your parts matched a reed name -- all %d reed(s) were auto-placed "
			.. "on a ring. Name parts any of: %s (numbered variants like reed2 count too).")
			:format(REED_COUNT, table.concat(REED_HINTS, ", ")))
	else
		print(("[Storm] %d sugar reed(s) -- %d on your parts, %d auto-placed on the ring "
			.. "(island top Y %.1f, reed Y %s)"):format(REED_COUNT, named, REED_COUNT - named,
			islandTopY or -1, table.concat((function()
				local t = {} for _, r in ipairs(reeds) do t[#t + 1] = ("%.1f"):format(r.pos.Y) end
				return t
			end)(), ", ")))
	end
end

-- THE WEAVING STAND, built beside the NPC. Weaving is a HOLD, not a tap: three seconds of
-- holding E reads as making something, and it is the one moment in the quest where you are
-- standing still, which makes the storm arriving on top of it land properly.
local function buildWeaveStand(nearPos)
	local p = nearPos + Vector3.new(6, 0, 6)
	local pos = Vector3.new(p.X, groundAt(p), p.Z)
	-- ⚠ NOT NAMED "...Stand", AND TAGGED QuestProp. Shop_AllInOne sweeps Workspace for anything
	-- whose name CONTAINS "stand" or "shop" and bolts a buy-food prompt onto it -- so the first
	-- build of this called "WeavingStand" was adopted as a food stand on island5 (the boot log
	-- literally read: prompt added on 'WeavingStand' -> island 5). Two independent guards: a name
	-- with no "stand" in it, and the QuestProp attribute that sweep already honours.
	local m = Instance.new("Model"); m.Name = "ReedLoom"; m.Parent = Workspace
	m:SetAttribute("QuestProp", true)
	local at = CFrame.new(pos)
	local function bit(props, cf) props.Parent = m; local p2 = mk(props); p2.CFrame = cf; return p2 end

	local top = bit({ Color = Color3.fromRGB(186, 138, 84), Material = Enum.Material.WoodPlanks,
		Size = Vector3.new(5.0, 0.45, 3.6), CanCollide = true }, at * CFrame.new(0, 3.0, 0))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			bit({ Color = Color3.fromRGB(146, 102, 60), Material = Enum.Material.Wood,
				Size = Vector3.new(0.42, 3.0, 0.42), CanCollide = true },
				at * CFrame.new(sx * 2.1, 1.5, sz * 1.4))
		end
	end
	-- a half-woven basket sitting on it, so the stand says what it is without a sign
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		bit({ Color = Color3.fromRGB(206, 158, 100), Material = Enum.Material.Wood,
			Size = Vector3.new(0.28, 1.2, 0.28) },
			at * CFrame.new(math.cos(a) * 1.0, 3.85, math.sin(a) * 1.0) * CFrame.Angles(math.rad(9), -a, 0))
	end
	bit({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(166, 118, 68),
		Material = Enum.Material.Wood, Size = Vector3.new(0.24, 2.3, 2.3) },
		at * CFrame.new(0, 3.3, 0) * CFrame.Angles(0, 0, math.rad(90)))

	local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(9, 9, 9), Parent = m })
	hit.CFrame = at * CFrame.new(0, 3, 0)
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = "Weave"; pr.ObjectText = "Reed Loom"
	pr.HoldDuration = 3          -- a hold, not a tap: you are MAKING something
	pr.MaxActivationDistance = 14; pr.RequiresLineOfSight = false
	pr.Enabled = false           -- lit only once you have every reed
	pr.Parent = hit

	weaveStand = { model = m, pos = pos, prompt = pr }

	pr.Triggered:Connect(function(plr)
		if plr ~= player or hasBasket or reedsHeld < REED_COUNT then return end
		pr.Enabled = false
		catchBurst(pos + Vector3.new(0, 4, 0), GOLD)
		giveBasket()
		flash("\xF0\x9F\xA7\xBA You wove your own catching basket!", 3)
		refreshBanner()
		task.delay(1.2, stormCollapse)
	end)
	return weaveStand
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

	task.delay(3.0, function()
		flash("\xF0\x9F\x8D\xAC Last of it is falling -- CATCH IT!", 2.6)
		task.delay(1.4, runStorm)
	end)
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
		return { ("No talking. CATCH! %d of %d!"):format(caught, TARGET),
			"Stand in the shadows. That's where they land!" }
	end
	if accepted and not hasBasket then
		if reedsHeld >= REED_COUNT then
			return { "That's the lot! Hold Weave on my loom." }
		end
		return {
			("%d of %d reed. Try all 3 islands."):format(reedsHeld, REED_COUNT),
			"Find tall pink-and-white canes, then press Cut.",
		}
	end
	if accepted then
		return {
			("Another go? You've caught %d of %d."):format(caught, TARGET),
			"Shadows show where pieces fall. Stand in them!",
		}
	end
	return {
		"A TAFFY STORM! You need a basket.",
		("1) Press Cut on %d pink SUGAR REED."):format(REED_COUNT),
		"2) Hold Weave on my reed loom.",
		("3) Catch %d pieces in the shadows!"):format(TARGET),
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
		if index == 0 then pages = (_G.capBubble and _G.capBubble(questPages())) or questPages() end
		index += 1
		if not pages or index > #pages then
			closeDialogue()
			-- ⚠ WEAVING starts the storm now, not closing the dialogue. A retry (you have the
			-- basket, the storm is over, you did not hit the target) still restarts it here.
			if accepted and hasBasket and not storming and not done then task.spawn(runStorm) end
			return
		end
		if index == 2 and not accepted then
			accepted = true
			-- ⚠ NO BASKET HERE ANY MORE. It used to be handed over on this line; the whole
			-- middle of the quest is now earning it, so taking the job only unlocks the reeds.
			refreshBanner()
		end
		local last = index >= #pages
		showBubble(head, pages[index], true,
			last and (hasBasket and "[E] bring on the storm" or "[E] go find the reed")
			or ("[E] more  (%d/%d)"):format(index, #pages))
		prompt.ActionText = last and (hasBasket and "START" or "GO") or "Continue"
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
		islandModel = isle
		local ok, cf, size = pcall(function() return isle:GetBoundingBox() end)
		if ok and cf then
			islandPos = cf.Position
			if size then
				islandTopY = cf.Position.Y + size.Y * 0.5
				islandBotY = cf.Position.Y - size.Y * 0.5
			end
		end
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

	scatterReeds()
	if npcHead then buildWeaveStand(npcHead.Position) end
	refreshBanner()
	print(("[Storm] ready -- centre %.0f,%.0f,%.0f, target %d, %d wave(s)"):format(
		stormCentre.X, stormCentre.Y, stormCentre.Z, TARGET, #WAVES))
	-- RETAINER SIGNAL: the quest reached the end of its build with its world objects up. QuestRetainer
	-- watches this flag; anything still false once its island has streamed in gets force-streamed and
	-- re-run. It is set HERE, at the ready print, not at the top of the file -- a quest that bailed
	-- early on a missing marker must NOT look built. See QuestRetainer.client.luau.
	_G.questBuilt_storm = true
end)

-- ============================================================================
-- /storm -- where the reeds are and how far in you are
-- ============================================================================
local function stormDiag(msg)
	if tostring(msg or ""):lower():sub(1, 6) ~= "/storm" then return end
	print("[Storm] ---- sugar reeds ----")
	if #reeds == 0 then
		print("  none built yet -- island5 may not have streamed in")
	end
	for i, r in ipairs(reeds) do
		print(("  %d  at (%.0f, %.0f, %.0f)  taken=%s"):format(i, r.pos.X, r.pos.Y, r.pos.Z, tostring(r.taken)))
	end
	print(("  weave stand=%s (prompt %s)"):format(
		weaveStand and "built" or "none",
		weaveStand and weaveStand.prompt and tostring(weaveStand.prompt.Enabled) or "n/a"))
	print(("  accepted=%s  basket=%s  reed %d/%d"):format(tostring(accepted), tostring(hasBasket),
		reedsHeld, REED_COUNT))
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
	-- DEV ONLY. QuestDevGate publishes this; read at command time so load order cannot matter,
	-- and nil (gate not up yet) refuses. Without it any player could type their way to the whole realm.
	if not _G.questDevOK then return end
	if tostring(msg or ""):lower():sub(1, 9) ~= "/complete" then return end
	local h = hrpOf()
	if not (islandPos and h) then return end
	if (h.Position - islandPos).Magnitude > 420 then return end
	accepted = true; caught = TARGET
	reedsHeld = REED_COUNT
	if not hasBasket then giveBasket() end
	-- clear the field so the cheat does not leave six glowing reeds standing on a finished quest
	for _, r in ipairs(reeds) do
		r.taken = true
		if r.model and r.model.Parent then r.model:Destroy() end
	end
	if weaveStand and weaveStand.prompt then weaveStand.prompt.Enabled = false end
	winStorm()
	print("[Storm][TEST] /complete -- storm weathered")
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
