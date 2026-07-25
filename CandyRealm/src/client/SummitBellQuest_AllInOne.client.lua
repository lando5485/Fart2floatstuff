--======================================================================
-- SummitBellQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- "RING THE SUMMIT BELL" -- a 2-3 minute climb up the mountain, built as an
-- obstacle course rather than a ladder grind.
--
-- RUNS ON ISLAND 4 ONLY.
--
-- WHAT THE WORLD PROVIDES (name these in Studio, on island4):
--   * parts named  Stairs  -- every flight of the climb. Sorted by height, and
--                             EVERY OTHER ONE starts BROKEN: it sags, goes
--                             non-solid, and has to be repaired before you can
--                             climb it. That's the core mechanic.
--   * a part named  bell   -- the Victory Bell at the summit. Ring it to win.
--   * (optional) parts named  cover / windbreak / snowwall -- guaranteed shelter
--   * (optional) parts named  rockroll   -- candy rocks roll down from these
--
-- THE BLIZZARD CYCLE (the heart of it):
--   CALM 12-15s  -> light snow, climb freely
--   WARNING 3s   -> whistle, fog thickens, "BLIZZARD INCOMING 3..2..1"
--   BLIZZARD 5-8s-> heavy snow, low visibility, wind shoves you DOWNHILL
--   CLEAR 10-15s -> "Storm passed!", everything back to normal
--   ...repeat
--
-- The push scales with height: ~15 studs/s low, 25 mid, 35 near the summit -- a
-- slide, never a ragdoll. Get anything solid between you and the wind (a rock, a
-- corner, a cabin, a "cover" part) and it stops dead, so the real decision is
-- "push on, or duck in and lose eight seconds?"
--
-- Client-side and per-player, like the island's other quests.
--======================================================================

local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local TweenService     = game:GetService("TweenService")
local Debris           = game:GetService("Debris")
local RunService       = game:GetService("RunService")
local SoundService     = game:GetService("SoundService")
local TextChatService  = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_NAME    = "island4"     -- the mountain lives here
local ISLAND_NUM     = 4
local ISLAND_RANGE   = 900           -- parts further than this from the mountain aren't ours
local STAIR_NAME     = "stairs"      -- loose match: "Stairs", "stairs 3", "Stairs_B"
local BELL_NAME      = "bell"
local WINDZONE_NAME  = "windzone"
local ROCKROLL_NAME  = "rockroll"
local NPC_NAMES      = { "candynpc" }

local BREAK_EVERY    = 2             -- break every Nth flight (2 = every other one)
local REPAIR_TIME    = 1.6           -- seconds of holding E to fix a flight
local REPAIR_RANGE   = 14

-- ---------------------------------------------------------------------------
-- THE BLIZZARD CYCLE
--   CALM (12-15s) -> WARNING (3s) -> BLIZZARD (5-8s) -> CLEAR (10-15s) -> repeat
-- The point is the decision: push on through, or duck behind cover and wait.
-- ---------------------------------------------------------------------------
local WIND_START     = 0.25          -- fraction of the climb where the weather starts biting
-- roughly one blizzard a minute: long calm + clear either side of a short storm
local CALM_MIN, CALM_MAX       = 40, 50
local WARNING_TIME             = 3
local BLIZZARD_MIN, BLIZZARD_MAX = 5, 8
local CLEAR_MIN, CLEAR_MAX     = 8, 12

-- Wind DRIFT speed (studs/sec) it slides you at, by height. Default walkspeed is ~16, so:
-- low is easily out-walked, mid is a slow forward fight, high edges close to walkspeed so
-- near the summit you can just hold ground -- but stand still anywhere and it carries you off.
local PUSH_LOW       = 6
local PUSH_MID       = 11
local PUSH_HIGH      = 15

-- cover: anything solid between you and the wind shelters you. Parts named "cover"
-- (or rock/cabin/windbreak) always count, whatever their shape.
local COVER_NAMES    = { "cover", "windbreak", "snowwall" }
local COVER_REACH    = 12            -- how far upwind we look for something to hide behind

-- rolling candy rocks (middle third)
local ROCK_START     = 0.3
local ROCK_EVERY     = 5

-- audio -- YOUR OWN ids. "" = silent, nothing is created for an empty id.
local SOUND_WIND     = ""
local SOUND_BELL     = ""
local SOUND_FIX      = ""

-- palette
local PANEL   = Color3.fromRGB(28, 32, 40)
local SNOW    = Color3.fromRGB(240, 248, 255)
local SKYBLUE = Color3.fromRGB(150, 208, 255)
local GOLD    = Color3.fromRGB(255, 206, 92)
local CHOC    = Color3.fromRGB(122, 78, 46)
local WARN    = Color3.fromRGB(255, 138, 96)

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s) return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", "")) end
local function nameHas(n, key) return string.find(norm(n), key, 1, true) ~= nil end

local function firstBasePart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat
		local r = fn()
		if r then return r end
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
	s.Parent = SoundService; s:Play(); Debris:AddItem(s, 6)
end

local function hrpOf()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- the mountain island.s centre, so this quest never grabs a "Stairs" or "bell" from another island
local islandRef
local function findIslandRef()
	local isl = Workspace:FindFirstChild(ISLAND_NAME)
	if not isl then
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("Model") and string.lower(d.Name):match("^island_?" .. ISLAND_NUM .. "$") then isl = d; break end
		end
	end
	if not isl then return nil end
	if isl:IsA("BasePart") then return isl.Position end
	local ok, cf = pcall(function() return (select(1, isl:GetBoundingBox())) end)
	return (ok and cf) and cf.Position or nil
end
local function onMountain(pos)
	if not islandRef then return true end   -- island not loaded: don.t filter anything out
	return (pos - islandRef).Magnitude <= ISLAND_RANGE
end

-- ============================================================================
-- STATE
-- ============================================================================
local bell, bellPart
local flights   = {}     -- { part=, rest=CFrame, broken=bool, fixed=bool }
local windZones = {}
local rollSpots = {}
local accepted  = false
local rung      = false
local baseY, topY = 0, 100
-- the blizzard lives further down, but the objective banner (above it) reports on it
local phase        = "calm"   -- calm | warning | blizzard | clear
local sheltered    = false
local forceBlizzard = false   -- /blizzard sets this to trigger one immediately
local blizzGustMul  = 1       -- wind surges above 1 in bursts during a blizzard
_G.summitQuestComplete = false
-- other island4 scripts (the Campfire freeze quest) read the live weather from here
_G.summitBlizzardPhase = "calm"
task.spawn(function()
	while true do _G.summitBlizzardPhase = phase; task.wait(0.15) end
end)

-- how far up the climb you are, 0 (bottom flight) .. 1 (the bell)
local function climbFrac()
	local hrp = hrpOf()
	if not hrp then return 0 end
	-- No bell yet -> no real summit height to measure against. Return a MODERATE fraction
	-- so the wind is fightable everywhere, instead of pinning to 1 (= max, unfightable).
	if not bellPart or topY - baseY < 20 then return 0.45 end
	return math.clamp((hrp.Position.Y - baseY) / (topY - baseY), 0, 1)
end

-- ============================================================================
-- OBJECTIVE BANNER
-- ============================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "SummitObjective"; gui.ResetOnSpawn = false; gui.DisplayOrder = 8; gui.Parent = PlayerGui

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0); frame.Position = UDim2.new(0.5, 0, 0, 12)
frame.Size = UDim2.new(0, 560, 0, 52); frame.BackgroundColor3 = PANEL; frame.Visible = false
frame.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = frame
	local s = Instance.new("UIStroke"); s.Color = SKYBLUE; s.Thickness = 3; s.Parent = frame
end
local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1; label.Size = UDim2.fromScale(1, 1); label.Font = Enum.Font.FredokaOne
label.TextColor3 = SNOW; label.TextScaled = true; label.Parent = frame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 21; sz.Parent = label
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14); pad.Parent = label
end

local function brokenLeft()
	local n = 0
	for _, f in ipairs(flights) do if f.broken and not f.fixed then n += 1 end end
	return n
end

local function bannerText()
	if rung then return "\xF0\x9F\x8F\x94 You rang the Summit Bell!" end
	if not accepted then return "\xF0\x9F\x8F\x94 Climb the mountain and ring the Victory Bell!" end
	local frac = climbFrac()
	if frac >= 0.95 then return "\xF0\x9F\x94\x94 The bell is right there -- RING IT!" end
	if phase == "blizzard" then
		return sheltered
			and ("\xF0\x9F\x8F\x94 Sheltered -- wait it out.  %d%% up"):format(math.floor(frac * 100))
			or  ("\xF0\x9F\x8C\xA8 BLIZZARD! Find cover!  %d%% up"):format(math.floor(frac * 100))
	end
	if phase == "warning" then
		return ("\xE2\x9A\xA0 Blizzard incoming -- get behind something!  %d%% up"):format(math.floor(frac * 100))
	end
	local bl = brokenLeft()
	if bl > 0 then
		return ("\xF0\x9F\x94\xA8 Fix the broken stairs to climb!  %d%% up"):format(math.floor(frac * 100))
	end
	return ("\xF0\x9F\x8F\x94 Keep climbing!  %d%% up"):format(math.floor(frac * 100))
end
local function refreshBanner() label.Text = bannerText() end

local flashTok = 0
local function flash(text, secs)
	flashTok += 1; local mine = flashTok
	label.Text = text; frame.Visible = true
	task.delay(secs or 2.5, function() if mine == flashTok then refreshBanner() end end)
end

task.spawn(function()
	while true do
		local hrp = hrpOf()
		frame.Visible = (hrp ~= nil) and bellPart ~= nil
			and (hrp.Position - bellPart.Position).Magnitude <= 700
		if frame.Visible then refreshBanner() end
		task.wait(0.5)
	end
end)

-- ============================================================================
-- THE FLIGHTS -- every other one starts broken and must be repaired
-- ============================================================================
local function breakFlight(f)
	local p = f.part
	f.broken = true
	f.fixed = false

	-- sag it: dropped, tilted, and NOT solid, so it can't be climbed as-is
	p.CanCollide = false
	p.CFrame = f.rest * CFrame.new(0, -1.1, 0) * CFrame.Angles(math.rad(9), 0, math.rad(-13))
	p.Transparency = math.max(p.Transparency, 0.35)

	-- splintered boards lying around it, cleared on repair
	f.debris = {}
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2
		local d = mk({ Name = "Splinter", Size = Vector3.new(2.4, 0.25, 0.5), Color = CHOC,
			Material = Enum.Material.Wood })
		d.CFrame = f.rest * CFrame.new(math.cos(a) * 3, -1.6, math.sin(a) * 3)
			* CFrame.Angles(0, a, math.rad(80))
		d.Parent = Workspace
		f.debris[#f.debris + 1] = d
	end

	-- a glowing marker so a broken flight is obvious from below
	local hl = Instance.new("Highlight")
	hl.FillColor = WARN; hl.FillTransparency = 0.72
	hl.OutlineColor = WARN; hl.OutlineTransparency = 0.1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = p; hl.Parent = p
	f.hl = hl
	TweenService:Create(hl, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ FillTransparency = 0.94, OutlineTransparency = 0.6 }):Play()

	local sign = Instance.new("BillboardGui")
	sign.Name = "FixSign"; sign.Adornee = p; sign.Size = UDim2.new(0, 190, 0, 46)
	sign.StudsOffset = Vector3.new(0, 4, 0); sign.AlwaysOnTop = true; sign.MaxDistance = 140
	sign.Parent = p
	local sf = Instance.new("Frame"); sf.Size = UDim2.fromScale(1, 1); sf.BackgroundColor3 = PANEL
	sf.BackgroundTransparency = 0.1; sf.BorderSizePixel = 0; sf.Parent = sign
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 8); sc.Parent = sf
	local ss = Instance.new("UIStroke"); ss.Color = WARN; ss.Thickness = 2; ss.Parent = sf
	local st = Instance.new("TextLabel"); st.BackgroundTransparency = 1; st.Size = UDim2.fromScale(1, 1)
	st.Font = Enum.Font.FredokaOne; st.Text = "BROKEN\nhold E to fix"; st.TextColor3 = WARN
	st.TextScaled = true; st.Parent = sf
	f.sign = sign

	p.CanQuery = true
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Fix the stairs"; prompt.ObjectText = "Broken Stairs"
	prompt.HoldDuration = REPAIR_TIME; prompt.MaxActivationDistance = REPAIR_RANGE
	prompt.RequiresLineOfSight = false; prompt.Parent = p
	f.prompt = prompt

	prompt.Triggered:Connect(function()
		if f.fixed or not accepted then
			if not accepted then flash("\xF0\x9F\x8F\x94 Talk to the Candy Npc to start the climb!", 2.5) end
			return
		end
		f.fixed = true
		prompt.Enabled = false
		if f.sign then f.sign:Destroy() end
		if f.hl then f.hl:Destroy() end

		-- snap back into place, solid again
		TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = f.rest, Transparency = f.restTransparency or 0 }):Play()
		task.delay(0.36, function() p.CanCollide = true end)

		for _, d in ipairs(f.debris or {}) do
			TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1, Size = d.Size * 0.3 }):Play()
			Debris:AddItem(d, 0.4)
		end
		f.debris = nil

		-- sparkle of repaired candy-wood
		for i = 1, 10 do
			local a = (i / 10) * math.pi * 2
			local s = mk({ Name = "FixSpark", Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4),
				Color = GOLD, Material = Enum.Material.Neon })
			s.CFrame = f.rest
			s.Parent = Workspace
			TweenService:Create(s, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = f.rest * CFrame.new(math.cos(a) * 5, 2.5, math.sin(a) * 5),
				Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
			Debris:AddItem(s, 0.7)
		end

		playSound(SOUND_FIX, 0.5)
		flash(("\xF0\x9F\x94\xA8 Stairs repaired!  %d left"):format(brokenLeft()), 2)
		refreshBanner()
	end)
end

local function wireFlights()
	local found = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and nameHas(d.Name, STAIR_NAME) and onMountain(d.Position) then
			found[#found + 1] = d
		end
	end
	if #found == 0 then
		warn("[Summit] no parts named 'Stairs' found -- nothing to climb")
		return
	end
	-- bottom to top, so "every other one" walks up the mountain in order
	table.sort(found, function(a, b) return a.Position.Y < b.Position.Y end)

	for i, p in ipairs(found) do
		local f = { part = p, rest = p.CFrame, restTransparency = p.Transparency, broken = false, fixed = false }
		flights[#flights + 1] = f
		-- the FIRST flight is always solid (nobody should be stuck at the bottom),
		-- then every BREAK_EVERY-th one after that is broken
		if i > 1 and (i % BREAK_EVERY == 0) then breakFlight(f) end
	end

	baseY = found[1].Position.Y
	print(("[Summit] %d flight(s) of stairs, %d broken"):format(#flights, brokenLeft()))
end

-- ============================================================================
-- THE BLIZZARD CYCLE
--   CALM -> WARNING -> BLIZZARD -> CLEAR -> repeat, forever, while you climb.
--   The whole point is the choice it forces: push on and get shoved back down,
--   or duck behind something and lose 8 seconds waiting it out.
-- ============================================================================
local Lighting = game:GetService("Lighting")

-- (phase is declared up in STATE, so the banner can read it)
local blizzWind   = Vector3.new(0, 0, 1)
local skySaved    = nil

-- ---- snow: two emitters, one always on, one only during the storm ---------
-- The snow FALLS FROM a part you named "snow" inside island4 -- the emitters live on
-- that part, so it rains across its whole footprint from a fixed height. If there's no
-- such part, they fall back to a hidden anchor that follows the player.
local lightSnow, heavySnow
local snowSource            -- the "snow" part; snow ONLY comes from here
local snowBaseRate = 300    -- light-snow rate at calm; warning bumps it, buildSnow sets it
local function buildSnow()
	if not (snowSource and snowSource.Parent) then
		warn("[Summit] no part named 'snow' in island4 -- no snow will fall")
		return
	end
	local host = snowSource

	-- the snow part is only an emitter volume -- make it invisible and non-solid
	host.Transparency = 1
	host.CanCollide = false
	host.CanQuery = false
	host.CastShadow = false

	-- Rate is TOTAL particles/sec spread over the WHOLE part, so a big part needs a big
	-- rate or the snow looks empty. Scale the rate to the part's footprint -- and keep the
	-- CALM/normal snow thick (not just the blizzard).
	local area   = math.max(1, host.Size.X * host.Size.Z)
	-- ALWAYS-THICK steady snowfall: high floor + denser area scale so the moment a player
	-- lands on island4 it already looks like heavy snow, not a light flurry. (The blizzard
	-- phase still stacks on top for the storm peak.)
	local baseRate = math.clamp(area / 8, 2600, 16000)

	snowBaseRate = baseRate

	-- Texture left empty: an unset ParticleEmitter renders Roblox's built-in white
	-- sprite, which reads fine as snow and can't hit the asset-auth failures.
	lightSnow = Instance.new("ParticleEmitter")
	lightSnow.Name = "LightSnow"; lightSnow.Color = ColorSequence.new(SNOW)
	lightSnow.Size = NumberSequence.new(2.3)                  -- big, obvious flakes (thick look)
	lightSnow.Transparency = NumberSequence.new(0.0)         -- fully opaque -- can't miss them
	lightSnow.Lifetime = NumberRange.new(8, 13)               -- long fall from a high part
	lightSnow.Rate = baseRate
	lightSnow.Speed = NumberRange.new(14, 22)                 -- head downward straight away
	lightSnow.SpreadAngle = Vector2.new(35, 35)              -- mostly down, slight drift
	lightSnow.EmissionDirection = Enum.NormalId.Bottom        -- fall DOWN out of the part
	lightSnow.Acceleration = Vector3.new(0, -18, 0)
	lightSnow.Drag = 1.5                                      -- flutter, don't rocket
	lightSnow.LightEmission = 0.7                             -- glows against dark sky
	lightSnow.LightInfluence = 0                             -- always bright, ignores shadows
	lightSnow.Parent = host

	heavySnow = Instance.new("ParticleEmitter")
	heavySnow.Name = "BlizzardSnow"; heavySnow.Color = ColorSequence.new(SNOW)
	heavySnow.Size = NumberSequence.new(1.85)
	heavySnow.Transparency = NumberSequence.new(0.08)         -- near-solid: whiteout
	heavySnow.Lifetime = NumberRange.new(6, 10)
	heavySnow.Rate = baseRate * 5                             -- 5x heavier in the storm
	heavySnow.Speed = NumberRange.new(90, 140)
	heavySnow.SpreadAngle = Vector2.new(40, 40)
	heavySnow.EmissionDirection = Enum.NormalId.Bottom
	heavySnow.Acceleration = Vector3.new(0, -45, 0)
	heavySnow.LightEmission = 0.5
	heavySnow.Enabled = false
	heavySnow.Parent = host

	print(("[Summit] snow emitter on '%s' (%.0f x %.0f) -- rate %d/%d"):format(
		host.Name, host.Size.X, host.Size.Z, math.floor(baseRate), math.floor(baseRate * 5)))
end

-- SNOW IS INDEPENDENT OF THE REST OF THE QUEST. It builds the moment a part named
-- "snow" exists -- it does NOT wait on the bell, the NPC or anything else, so missing
-- one of those never stops the snow from falling.
task.spawn(function()
	local part = pollFor(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("BasePart") and norm(d.Name) == "snow" then return d end
		end
		return nil
	end, 120)
	if not part then
		warn("[Summit] no part named 'snow' found anywhere -- no snow will fall")
		return
	end
	snowSource = part
	buildSnow()
end)

-- The "snow" part stays exactly where you placed it. During a storm the flakes are
-- driven sideways by setting the emitters' Acceleration to the wind direction (done in
-- the cycle below), so nothing needs to move or follow the player.

-- ---- how hard does it push you HERE? -------------------------------------
local function pushStrength()
	local f = climbFrac()
	if f < 0.4 then
		return PUSH_LOW + (PUSH_MID - PUSH_LOW) * (f / 0.4)
	end
	return PUSH_MID + (PUSH_HIGH - PUSH_MID) * math.clamp((f - 0.4) / 0.6, 0, 1)
end

-- ---- are you sheltered? --------------------------------------------------
-- Anything solid between you and the oncoming wind counts: a rock, a corner, a
-- cabin wall, or a part you named "cover". Stairs don't count as cover.
local function isSheltered()
	local hrp = hrpOf(); if not hrp then return false end

	-- explicit cover parts win regardless of angle
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") then
			for _, want in ipairs(COVER_NAMES) do
				if nameHas(d.Name, want) then
					local reach = math.max(d.Size.X, d.Size.Z) * 0.5 + 6
					if (hrp.Position - d.Position).Magnitude <= reach then return true end
					break
				end
			end
		end
	end

	-- otherwise: is something between you and where the wind is coming from?
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { player.Character }
	rp.FilterDescendantsInstances = filter
	local hit = Workspace:Raycast(hrp.Position + Vector3.new(0, 1.5, 0), -blizzWind * COVER_REACH, rp)
	if hit and hit.Instance then
		-- a flight of stairs is not shelter
		if nameHas(hit.Instance.Name, STAIR_NAME) then return false end
		return true
	end
	return false
end

-- ---- the big centre-screen storm card ------------------------------------
local stormGui = Instance.new("ScreenGui")
stormGui.Name = "BlizzardCard"; stormGui.ResetOnSpawn = false; stormGui.DisplayOrder = 15
stormGui.IgnoreGuiInset = true; stormGui.Enabled = false; stormGui.Parent = PlayerGui
local card = Instance.new("TextLabel")
card.AnchorPoint = Vector2.new(0.5, 0.5); card.Position = UDim2.new(0.5, 0, 0.26, 0)
card.Size = UDim2.new(0, 620, 0, 96); card.BackgroundTransparency = 1
card.Font = Enum.Font.FredokaOne; card.TextColor3 = SNOW; card.TextScaled = true
card.TextStrokeColor3 = Color3.fromRGB(20, 30, 48); card.TextStrokeTransparency = 0.15
card.Text = ""; card.Parent = stormGui
local function showCard(txt, secs)
	card.Text = txt
	stormGui.Enabled = true
	if secs then
		task.delay(secs, function() if card.Text == txt then stormGui.Enabled = false end end)
	end
end

-- ---- weather visuals -----------------------------------------------------
local function setWeather(level)   -- 0 calm .. 1 full blizzard
	if not skySaved then
		skySaved = { fogStart = Lighting.FogStart, fogEnd = Lighting.FogEnd, fogColor = Lighting.FogColor,
			bright = Lighting.Brightness, amb = Lighting.OutdoorAmbient }
	end
	local fogEnd = (skySaved.fogEnd or 100000)
	TweenService:Create(Lighting, TweenInfo.new(1.2), {
		FogStart   = level > 0 and (18 - 14 * level) or 0,        -- fog closes right in
		FogEnd     = level > 0 and (150 - 118 * level) or fogEnd, -- full blizzard ~= 32 stud whiteout
		FogColor   = Color3.fromRGB(212, 224, 236):Lerp(Color3.fromRGB(244, 250, 255), level),
		Brightness = (skySaved.bright or 2) * (1 - 0.55 * level),
		OutdoorAmbient = (skySaved.amb or Color3.fromRGB(128, 128, 128)):Lerp(Color3.fromRGB(196, 208, 224), level),
	}):Play()
end
local function clearWeather()
	if not skySaved then return end
	TweenService:Create(Lighting, TweenInfo.new(2), {
		FogStart = skySaved.fogStart, FogEnd = skySaved.fogEnd, FogColor = skySaved.fogColor,
		Brightness = skySaved.bright, OutdoorAmbient = skySaved.amb }):Play()
end

-- ---- the ONSET: the moment the blizzard hits, everything goes crazy -------
local function blizzardOnset()
	local hrp = hrpOf(); if not hrp then return end
	local here = hrp.Position

	-- 1) a big camera KICK + hard shake for ~1s
	local cam = Workspace.CurrentCamera
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 1.1 do
			if cam and cam.CameraType ~= Enum.CameraType.Scriptable then
				local m = (1 - (os.clock() - t0) / 1.1) * 3.5
				cam.CFrame = cam.CFrame
					* CFrame.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
					* CFrame.Angles(0, 0, (math.random() - 0.5) * m * 0.02)
			end
			RunService.RenderStepped:Wait()
		end
	end)

	-- 2) a shove in the wind direction the instant it lands
	hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + blizzWind * 30 + Vector3.new(0, 6, 0)

	-- 3) a wall of snow BLASTS past you horizontally, right at eye level
	for i = 1, 60 do
		local off = Vector3.new((math.random() - 0.5) * 60, (math.random() - 0.5) * 30, (math.random() - 0.5) * 60)
		local streak = mk({ Name = "Gust", Size = Vector3.new(0.3, 0.3, 10 + math.random() * 14),
			Color = SNOW, Material = Enum.Material.Neon, Transparency = 0.3 })
		local start = here + off - blizzWind * 40
		streak.CFrame = CFrame.lookAt(start, start + blizzWind)
		streak.Parent = Workspace
		TweenService:Create(streak, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = streak.CFrame + blizzWind * 130, Transparency = 1 }):Play()
		Debris:AddItem(streak, 0.7)
	end

	-- 4) a quick white flash-in over the screen (a snow gust in your face)
	local fg = Instance.new("ScreenGui"); fg.Name = "GustFlash"; fg.ResetOnSpawn = false
	fg.DisplayOrder = 25; fg.IgnoreGuiInset = true; fg.Parent = PlayerGui
	local wf = Instance.new("Frame"); wf.Size = UDim2.fromScale(1, 1)
	wf.BackgroundColor3 = Color3.fromRGB(235, 244, 255); wf.BackgroundTransparency = 0.25
	wf.BorderSizePixel = 0; wf.Parent = fg
	TweenService:Create(wf, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }):Play()
	task.delay(0.9, function() fg:Destroy() end)
end

-- ---- the push, applied every frame while it's blowing --------------------
-- (sheltered is declared up in STATE alongside phase)
RunService.RenderStepped:Connect(function(dt)
	if phase ~= "blizzard" or rung then return end
	local hrp = hrpOf(); if not hrp then return end
	-- must be ON island4, and above the height where the weather starts biting. climbFrac
	-- falls back to a sane range when there's no bell/stairs, so this still works bare.
	if not (islandRef and (hrp.Position - islandRef).Magnitude <= ISLAND_RANGE) then return end
	if climbFrac() < WIND_START then return end
	if sheltered then return end

	-- A DRIFT you can fight, not an override: nudge the character along the wind by
	-- driftSpeed*dt. Your own walking still applies normally on top -- walk into it and
	-- you can win (low/mid), stand still and the drift carries you off. Position nudge
	-- (not velocity) so the Humanoid's movement controller never erases your input.
	local drift = pushStrength() * blizzGustMul * dt
	hrp.CFrame = hrp.CFrame + blizzWind * drift

	local cam = Workspace.CurrentCamera
	if cam and cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.35, 0)
	end
end)

-- shelter is checked a few times a second, not every frame (it walks Workspace)
task.spawn(function()
	while true do
		task.wait(0.25)
		sheltered = (phase == "blizzard") and isSheltered() or false
	end
end)

-- ---- the cycle -----------------------------------------------------------
-- Ambient weather: the blizzard runs whenever you're ON island4, exactly like the
-- island9 hazard cycle -- it does NOT wait on the NPC, the bell or accepting the quest.
-- It resolves island4's position itself so a stuck bell-poll can't block it.
task.spawn(function()
	if not islandRef then islandRef = pollFor(findIslandRef, 120) end

	-- true only while the player is standing on island4 -- so the storm (and its global
	-- lighting change) never runs on any other island
	local function onMountainNow()
		if rung then return false end
		local hrp = hrpOf()
		return hrp ~= nil and islandRef ~= nil
			and (hrp.Position - islandRef).Magnitude <= ISLAND_RANGE
	end
	while true do
		if not onMountainNow() then
			if skySaved then clearWeather() end   -- left the island mid-storm: hand lighting back
			if heavySnow then heavySnow.Enabled = false end
			phase = "calm"
			task.wait(1)
			continue
		end

		-- CALM ---------------------------------------------------------------
		phase = "calm"
		if heavySnow then heavySnow.Enabled = false end
		if lightSnow then lightSnow.Rate = snowBaseRate end
		setWeather(0)
		-- interruptible wait: /blizzard sets forceBlizzard and we cut calm short
		local calmT0 = os.clock()
		while os.clock() - calmT0 < math.random(CALM_MIN, CALM_MAX) do
			if forceBlizzard or rung then break end
			task.wait(0.2)
		end
		forceBlizzard = false
		if rung then continue end

		-- WARNING ------------------------------------------------------------
		phase = "warning"
		-- wind blows DOWNHILL: away from the bell if there is one, else away from the
		-- island centre (so it still shoves you off the mountain)
		local hrp = hrpOf()
		local from = (bellPart and bellPart.Position) or islandRef
		if hrp and from then
			local away = (hrp.Position - from) * Vector3.new(1, 0, 1)
			blizzWind = (away.Magnitude > 1) and away.Unit or Vector3.new(0, 0, 1)
		end
		if lightSnow then lightSnow.Rate = snowBaseRate * 2.5 end
		setWeather(0.45)
		playSound(SOUND_WIND, 0.4)

		for i = WARNING_TIME, 1, -1 do
			showCard(("\xE2\x9A\xA0 BLIZZARD INCOMING\n%d"):format(i))
			task.wait(1)
			if rung then break end
		end
		if rung then continue end

		-- BLIZZARD -----------------------------------------------------------
		phase = "blizzard"
		if heavySnow then
			heavySnow.Enabled = true
			heavySnow.Rate = snowBaseRate * 12          -- a wall of snow
			heavySnow.Acceleration = blizzWind * 140 + Vector3.new(0, -40, 0)   -- driven near-horizontal
		end
		if lightSnow then
			lightSnow.Rate = snowBaseRate * 4
			lightSnow.Acceleration = blizzWind * 70 + Vector3.new(0, -12, 0)
		end
		setWeather(1)
		blizzardOnset()                                 -- the "everything goes crazy" hit
		showCard("\xF0\x9F\x8C\xA8 SURVIVE THE BLIZZARD", 2.5)
		playSound(SOUND_WIND, 1)

		local dur = math.random(BLIZZARD_MIN, BLIZZARD_MAX)
		local t0 = os.clock()
		local gustT = 0
		while os.clock() - t0 < dur do
			if rung then break end
			-- the wind isn't steady: it SURGES. The SNOW pulses hard for drama, but the
			-- PUSH only surges a little (max ~1.35x) so a gust nudges you back without
			-- ever becoming unfightable.
			gustT += 0.2
			local s = math.abs(math.sin(gustT * 1.3))
			if heavySnow then heavySnow.Rate = snowBaseRate * 12 * (1 + s * 0.8) end
			blizzGustMul = 1 + s * 0.35
			task.wait(0.2)
		end
		blizzGustMul = 1

		-- CLEAR --------------------------------------------------------------
		phase = "clear"
		if heavySnow then heavySnow.Enabled = false; heavySnow.Rate = snowBaseRate * 5 end  -- reset for next time
		if lightSnow then lightSnow.Rate = snowBaseRate; lightSnow.Acceleration = Vector3.new(0, -18, 0) end  -- gentle, straight down
		clearWeather()
		showCard("\xF0\x9F\x8C\xA4 Storm passed!", 2.2)
		task.wait(math.random(CLEAR_MIN, CLEAR_MAX))
	end
end)

-- ============================================================================
-- ROLLING CANDY ROCKS -- the middle third of the climb
-- ============================================================================
local function rollRock(from)
	local rock = mk({ Name = "CandyRock", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3),
		Color = Color3.fromRGB(214, 118, 168), Material = Enum.Material.Sand, CanCollide = false })
	rock.CFrame = CFrame.new(from)
	rock.Parent = Workspace

	local dropTo = from - Vector3.new((math.random() - 0.5) * 20, 60, (math.random() - 0.5) * 20)
	local tw = TweenService:Create(rock, TweenInfo.new(2.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = CFrame.new(dropTo) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6) })
	tw:Play()
	Debris:AddItem(rock, 2.6)

	-- shove the player if it passes close (never kills)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 2.4 and rock.Parent do
			local hrp = hrpOf()
			if hrp and (hrp.Position - rock.Position).Magnitude < 5 then
				local push = (hrp.Position - rock.Position) * Vector3.new(1, 0, 1)
				push = (push.Magnitude > 0.1) and push.Unit or Vector3.new(1, 0, 0)
				hrp.AssemblyLinearVelocity = push * 30 + Vector3.new(0, 12, 0)
				flash("\xE2\x9A\xA0 Rolling candy rock!", 1.6)
				break
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(ROCK_EVERY)
		if accepted and not rung then
			local frac = climbFrac()
			if frac >= ROCK_START and frac < WIND_START then
				local hrp = hrpOf()
				if hrp then
					local from = hrp.Position + Vector3.new((math.random() - 0.5) * 26, 42, (math.random() - 0.5) * 26)
					if #rollSpots > 0 then
						from = rollSpots[math.random(1, #rollSpots)].Position
					end
					rollRock(from)
				end
			end
		end
	end
end)

-- ============================================================================
-- THE BELL
-- ============================================================================
local function confetti(at)
	local COLS = { Color3.fromRGB(255, 92, 138), Color3.fromRGB(120, 200, 255), Color3.fromRGB(150, 235, 130),
	               GOLD, Color3.fromRGB(190, 130, 255) }
	for i = 1, 60 do
		local c = mk({ Name = "Confetti", Size = Vector3.new(0.5, 0.5, 0.1),
			Color = COLS[((i - 1) % #COLS) + 1], Material = Enum.Material.Neon })
		c.CFrame = CFrame.new(at)
		c.Parent = Workspace
		local a = (i / 60) * math.pi * 2
		local out = Vector3.new(math.cos(a) * (10 + math.random() * 18), 12 + math.random() * 16, math.sin(a) * (10 + math.random() * 18))
		TweenService:Create(c, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(at + out) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6) }):Play()
		task.delay(1.1, function()
			if c.Parent then
				TweenService:Create(c, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = c.CFrame - Vector3.new(0, 30, 0), Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(c, 2.8)
	end
end

local function winBanner()
	local g = Instance.new("ScreenGui"); g.Name = "SummitWin"; g.ResetOnSpawn = false
	g.DisplayOrder = 20; g.IgnoreGuiInset = true; g.Parent = PlayerGui
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5, 0.5); f.Position = UDim2.new(0.5, 0, 0.42, 0)
	f.Size = UDim2.new(0, 0, 0, 92); f.BackgroundColor3 = PANEL; f.Parent = g
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 18); c.Parent = f
	local s = Instance.new("UIStroke"); s.Color = GOLD; s.Thickness = 4; s.Parent = f
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.FredokaOne; l.TextColor3 = GOLD; l.TextScaled = true
	l.Text = "\xF0\x9F\x94\x94 YOU RANG THE SUMMIT BELL! \xF0\x9F\x8F\x86"; l.Parent = f
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 24); pad.PaddingRight = UDim.new(0, 24); pad.Parent = l
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 32; sz.Parent = l
	TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 660, 0, 92) }):Play()
	task.delay(5, function()
		TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.delay(0.5, function() g:Destroy() end)
	end)
end

local function ringBell()
	if rung then return end
	rung = true
	_G.summitQuestComplete = true
	refreshBanner()
	playSound(SOUND_BELL, 0.9)

	-- swing it
	local rest = bellPart.CFrame
	task.spawn(function()
		for i = 1, 10 do
			local ang = math.rad(18 * math.sin(i * 0.9) * (1 - i / 12))
			bellPart.CFrame = rest * CFrame.Angles(0, 0, ang)
			task.wait(0.09)
		end
		bellPart.CFrame = rest
	end)

	confetti(bellPart.Position + Vector3.new(0, 4, 0))
	task.delay(0.4, function() confetti(bellPart.Position + Vector3.new(0, 8, 0)) end)
	winBanner()

	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({ text = "\xF0\x9F\x94\x94 You rang the Summit Bell!", color = GOLD }) end)
	end
	print("[Summit] complete -- bell rung")
end

local function wireBell()
	bellPart.CanQuery = true
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "RING IT"; prompt.ObjectText = "Victory Bell"
	prompt.HoldDuration = 0; prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false; prompt.Parent = bellPart
	prompt.Triggered:Connect(function()
		if not accepted then
			accepted = true      -- reaching the summit counts as taking the job
		end
		ringBell()
	end)

	-- a glow so you can see the goal from lower down
	local hl = Instance.new("Highlight")
	hl.FillColor = GOLD; hl.FillTransparency = 0.8
	hl.OutlineColor = GOLD; hl.OutlineTransparency = 0.15
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = bellPart; hl.Parent = bellPart
	TweenService:Create(hl, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ FillTransparency = 0.95, OutlineTransparency = 0.65 }):Play()
end

-- ============================================================================
-- ISLAND-2 CANDY NPC -- same paged-bubble pattern as the other islands. Picked
-- as the one nearest the bell, so island1's/island3's is never grabbed.
-- ============================================================================
local npcHead

local function hideBubble(a) local p = a and a:FindFirstChild("SpeechBubble"); if p then p:Destroy() end end
local function showBubble(a, text, persist, footer)
	hideBubble(a)
	local bb = Instance.new("BillboardGui"); bb.Name = "SpeechBubble"; bb.Adornee = a
	bb.Size = UDim2.new(0, 330, 0, 150); bb.StudsOffset = Vector3.new(0, 5.5, 0)
	bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.05; f.BorderSizePixel = 0; f.Parent = bb
	local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0, 14); cr.Parent = f
	local st = Instance.new("UIStroke"); st.Color = SKYBLUE; st.Thickness = 2; st.Parent = f
	local pd = Instance.new("UIPadding")
	pd.PaddingTop = UDim.new(0, 12); pd.PaddingBottom = UDim.new(0, 12)
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = f
	local l = Instance.new("TextLabel"); l.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1; l.Font = Enum.Font.FredokaOne; l.Text = text
	l.TextColor3 = SNOW; l.TextScaled = true; l.TextWrapped = true; l.Parent = f
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 20; sz.Parent = l
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1, 0.2); h.Position = UDim2.fromScale(0, 0.8)
		h.BackgroundTransparency = 1; h.Font = Enum.Font.FredokaOne; h.Text = footer
		h.TextColor3 = SKYBLUE; h.TextScaled = true; h.Parent = f
		local hs = Instance.new("UITextSizeConstraint"); hs.MaxTextSize = 13; hs.Parent = h
	end
	bb.Parent = a
	if not persist then
		task.delay(9, function() if bb and bb.Parent == a and bb.Name == "SpeechBubble" then bb:Destroy() end end)
	end
end

local function questPages()
	if rung then
		return { "You rang it! The whole island heard that. \xF0\x9F\x94\x94", "Nobody's climbed that fast in years." }
	end
	if accepted then
		local bl = brokenLeft()
		local pages = { ("You're %d%% of the way up!"):format(math.floor(climbFrac() * 100)) }
		if bl > 0 then pages[#pages + 1] = ("%d flight(s) of stairs still need fixing."):format(bl) end
		pages[#pages + 1] = "Mind the wind once you're above the clouds."
		return pages
	end
	return {
		"See that bell at the top? Nobody's rung it in years.",
		"Half the stairs have rotted through -- you'll have to fix them as you climb.",
		"Higher up there's wind that'll knock you clean off. Wait it out on the ledges.",
		"Get to the summit and RING IT.",
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
				local hrp = hrpOf()
				if not hrp or (hrp.Position - head.Position).Magnitude > 12 then closeDialogue(); break end
				task.wait(0.25)
			end
			watching = false
		end)
	end

	prompt.Triggered:Connect(function()
		if index == 0 then pages = questPages() end
		index += 1
		if not pages or index > #pages then closeDialogue(); return end
		if index == 2 and not accepted then
			accepted = true
			refreshBanner()
			-- point the tutorial arrows at the bottom of the climb
			if flights[1] and _G.guideTrailTo then
				pcall(function() _G.guideTrailTo(flights[1].part.Position) end)
			end
		end
		local last = index >= #pages
		showBubble(head, pages[index], true, last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages))
		prompt.ActionText = last and "Close" or "Continue"
		startWatcher()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then closeDialogue() end end)
end

local function findNPCNear(refPos)
	if not refPos then return nil end
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		local n = norm(d.Name)
		local match = false
		for _, want in ipairs(NPC_NAMES) do if n == want then match = true; break end end
		if match then
			local head = (d:IsA("Model") and (d:FindFirstChild("Head") or d.PrimaryPart or firstBasePart(d)))
				or (d:IsA("BasePart") and d) or firstBasePart(d)
			if head then
				local dist = (head.Position - refPos).Magnitude
				if dist <= 500 and (not bestD or dist < bestD) then best, bestD = head, dist end
			end
		end
	end
	return best
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	islandRef = pollFor(findIslandRef, 45)
	if not islandRef then
		warn("[Summit] island4 not found yet -- searching the whole Workspace for the bell")
	end

	bell = pollFor(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("Model")) and norm(d.Name) == BELL_NAME then
				local bp = firstBasePart(d)
				if bp and onMountain(bp.Position) then return d end
			end
		end
		return nil
	end, 60)

	if not bell then
		warn("[Summit] no part named 'bell' found -- quest inactive")
		return
	end
	bellPart = firstBasePart(bell)
	if not bellPart then warn("[Summit] the 'bell' has no BasePart"); return end
	topY = bellPart.Position.Y

	wireFlights()
	-- with no stairs found, baseY would still be 0 and every climb-percentage would be
	-- nonsense -- fall back to a sane 120 studs below the bell
	if #flights == 0 then baseY = topY - 120 end
	wireBell()

	-- (snow is built by its OWN task below -- it must not depend on the bell existing)

	-- optional world markers
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") then
			if nameHas(d.Name, WINDZONE_NAME) then
				d.Transparency = 1; d.CanCollide = false; d.CanQuery = false
				windZones[#windZones + 1] = d
			elseif nameHas(d.Name, ROCKROLL_NAME) then
				d.Transparency = 1; d.CanCollide = false; d.CanQuery = false
				rollSpots[#rollSpots + 1] = d
			end
		end
	end

	-- island4.s Candy Npc gives the job; with no NPC the climb is simply open
	npcHead = pollFor(function() return findNPCNear(bellPart.Position) end, 25)
	if npcHead then
		wireNPC(npcHead)
		print("[Summit] island4 Candy Npc wired")
		-- arrows point at her until the job's taken
		task.spawn(function()
			while not accepted and npcHead and npcHead.Parent do
				local hrp = hrpOf()
				if hrp and islandRef and (hrp.Position - islandRef).Magnitude <= ISLAND_RANGE then
					if _G.guideTrailTo then pcall(function() _G.guideTrailTo(npcHead.Position) end) end
				end
				task.wait(2)
			end
		end)
	else
		warn("[Summit] no 'Candy Npc' near the bell -- climb unlocked without her")
		accepted = true
	end

	refreshBanner()
	print(("[Summit] ready -- bell at Y=%.0f, base Y=%.0f, %d flight(s), %d wind zone(s), %d roll spot(s)"):format(
		topY, baseY, #flights, #windZones, #rollSpots))
end)

-- ============================================================================
-- /complete -- test command (only near the bell)
-- ============================================================================
local function onCommand(msg)
	local text = tostring(msg or ""):lower()

	-- /blizzard -- kick off a storm right now (only if you're on the mountain, quest live)
	if text:sub(1, 9) == "/blizzard" then
		if phase == "calm" or phase == "clear" then
			forceBlizzard = true
			print("[Summit][TEST] /blizzard -- storm forced")
		else
			flash("\xF0\x9F\x8C\xA8 A storm's already blowing!", 2)
		end
		return
	end

	if text:sub(1, 9) ~= "/complete" then return end
	local hrp = hrpOf()
	if not (bellPart and hrp) then return end
	if (hrp.Position - bellPart.Position).Magnitude > 700 then return end
	accepted = true
	for _, f in ipairs(flights) do
		if f.broken and not f.fixed then
			f.fixed = true
			if f.prompt then f.prompt.Enabled = false end
			if f.sign then f.sign:Destroy() end
			if f.hl then f.hl:Destroy() end
			f.part.CFrame = f.rest; f.part.CanCollide = true; f.part.Transparency = f.restTransparency or 0
		end
	end
	ringBell()
	print("[Summit][TEST] /complete -- bell rung")
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
