--======================================================================
-- CampfireFreezeQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- ISLAND-4 QUEST: "BUILD THE CAMPFIRE (before you freeze)"
--
-- A Freeze Meter fills the moment the quest starts -- slowly in calm weather, FAST
-- during a blizzard (read from the Summit quest's _G.summitBlizzardPhase). As it
-- climbs, frost creeps in from the screen edges, your view narrows, and you slow
-- down. Race to gather + place the campfire materials before it hits 100%.
--
--   * 5 Fire Logs, 8 Stones, 3 Kindling -- scattered around island4 (or auto-spawned).
--     Grab one, carry it to the CAMPFIRE spot, and it snaps into place.
--   * Every material placed builds the fire up piece by piece.
--   * Last piece -> the fire IGNITES: warm glow, frost melts, freeze meter gone.
--   * Freeze hits 100% -> "YOU DIDN'T SURVIVE THE COLD", fade, reset, try again.
--
-- WHAT THE WORLD PROVIDES (name in Studio, on island4):
--   * a part named  campfire        -- where the fire is built (the drop spot)
--   * (optional) parts named  firelog / stone / kindling  -- your own materials
--   * (optional) a part named  queststart  -- where you respawn on failure
--
-- TEST: type  /freeze  to start the cold with no setup, so you can watch it work.
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
local ISLAND_NAME   = "island4"
local ISLAND_RANGE  = 900
local CAMPFIRE_NAMES = { "fire", "campfire" }   -- the part the fire is built on
local START_NAME    = "queststart"
local NPC_NAMES     = { "candynpc" }

-- how many of each material the fire needs
local NEED = { firelog = 5, stone = 8, kindling = 3 }
local MAT_ORDER = { "firelog", "stone", "kindling" }
local MAT_LABEL = { firelog = "Fire Log", stone = "Stone", kindling = "Kindling" }
local MAT_ICON  = { firelog = "\xF0\x9F\xAA\xB5", stone = "\xF0\x9F\xAA\xA8", kindling = "\xF0\x9F\x8C\xB2" }

-- Freeze Meter: seconds to go 0 -> 100% at each weather.  Blizzard is MUCH faster.
local FREEZE_CALM_TIME     = 190     -- calm: ~3 min to freeze if you do nothing
local FREEZE_BLIZZARD_TIME = 52      -- blizzard: still much faster, but survivable
local WARM_RATE            = 0.20    -- how fast it DROPS per second near the lit fire

local BASE_WALKSPEED = 16
local DELIVER_RANGE  = 10

-- audio -- your own ids only; "" stays silent
local SOUND_WIND  = ""
local SOUND_HEART = ""
local SOUND_FIRE  = ""

-- palette
local FROST = Color3.fromRGB(206, 232, 255)
local ICE   = Color3.fromRGB(150, 205, 245)
local FIREC = Color3.fromRGB(255, 150, 60)

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s) return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", "")) end
local function nameHasAny(n, keys)
	local x = norm(n)
	for _, k in ipairs(keys) do if string.find(x, k, 1, true) then return k end end
	return nil
end
local function firstBasePart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end
local function pollFor(fn, t)
	local t0 = os.clock()
	repeat local r = fn(); if r then return r end; task.wait(0.5) until os.clock() - t0 > (t or 45)
	return fn()
end
local function mk(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end
local function playSound(id, vol, looped)
	if not id or id == "" then return nil end
	local s = Instance.new("Sound"); s.SoundId = id; s.Volume = vol or 0.6; s.Looped = looped or false
	s.Parent = SoundService; s:Play()
	if not looped then Debris:AddItem(s, 6) end
	return s
end
local function hrpOf()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- ============================================================================
-- STATE
-- ============================================================================
local islandPos, campfirePart, startPos, npcHead
local active   = false        -- is the freeze running?
local built    = false        -- is the fire lit (quest done)?
local freeze   = 0            -- 0..1
local placed   = { firelog = 0, stone = 0, kindling = 0 }
local carrying = nil          -- material key you're holding, or nil
local firePieces = {}         -- built-up bits of the campfire, cleared on reset
_G.campfireQuestComplete = false
-- Shop_AllInOne calls this when you touch the LOCKED island-4 stand
_G.campfireQuestNudge = function()
	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({
			text = "\xF0\x9F\x94\xA5 Build the campfire (beat the cold) to open this stand!", color = FIREC }) end)
	end
end

local function isBlizzard() return _G.summitBlizzardPhase == "blizzard" or _G.summitBlizzardPhase == "warning" end
local function totalNeeded() return NEED.firelog + NEED.stone + NEED.kindling end
local function totalPlaced() return placed.firelog + placed.stone + placed.kindling end

-- ============================================================================
-- THE FREEZE OVERLAY -- a vignette that closes in as you freeze
-- ============================================================================
local frostGui = Instance.new("ScreenGui")
frostGui.Name = "FreezeOverlay"; frostGui.ResetOnSpawn = false; frostGui.DisplayOrder = 18
frostGui.IgnoreGuiInset = true; frostGui.Enabled = false; frostGui.Parent = PlayerGui

-- four frost frames anchored to the screen edges; they grow inward as freeze rises
local edges = {}
for _, side in ipairs({ "Top", "Bottom", "Left", "Right" }) do
	local f = Instance.new("Frame")
	f.BackgroundColor3 = FROST; f.BorderSizePixel = 0; f.BackgroundTransparency = 0.25
	if side == "Top"    then f.AnchorPoint = Vector2.new(0.5, 0); f.Position = UDim2.new(0.5, 0, 0, 0); f.Size = UDim2.new(1, 0, 0, 0) end
	if side == "Bottom" then f.AnchorPoint = Vector2.new(0.5, 1); f.Position = UDim2.new(0.5, 0, 1, 0); f.Size = UDim2.new(1, 0, 0, 0) end
	if side == "Left"   then f.AnchorPoint = Vector2.new(0, 0.5); f.Position = UDim2.new(0, 0, 0.5, 0); f.Size = UDim2.new(0, 0, 1, 0) end
	if side == "Right"  then f.AnchorPoint = Vector2.new(1, 0.5); f.Position = UDim2.new(1, 0, 0.5, 0); f.Size = UDim2.new(0, 0, 1, 0) end
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Rotation = (side == "Top" and 90) or (side == "Bottom" and 270) or (side == "Left" and 0) or 180
	g.Parent = f
	f.Parent = frostGui
	edges[side] = f
end

-- a central "iris" ring that darkens the corners at high freeze (near-blackout)
local iris = Instance.new("ImageLabel")
iris.BackgroundTransparency = 1; iris.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
iris.Size = UDim2.fromScale(1, 1); iris.ImageColor3 = Color3.new(0, 0, 0)
iris.ImageTransparency = 1; iris.Parent = frostGui
-- (fallback: a plain vignette via four corner-darkening frames if the image is blank)
local vignette = Instance.new("Frame")
vignette.BackgroundColor3 = Color3.new(0, 0, 0); vignette.BackgroundTransparency = 1
vignette.BorderSizePixel = 0; vignette.Size = UDim2.fromScale(1, 1); vignette.Parent = frostGui
local vgrad = Instance.new("UIGradient")
vgrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1) })
vgrad.Parent = vignette

-- blue colour-wash that deepens with the cold
local coldTint = Instance.new("ColorCorrectionEffect")
coldTint.Name = "FreezeTint"; coldTint.Enabled = false; coldTint.Parent = Lighting
local coldBlur = Instance.new("BlurEffect")
coldBlur.Name = "FreezeBlur"; coldBlur.Size = 0; coldBlur.Parent = Lighting

-- drifting on-screen flakes
local flakeHolder = Instance.new("Frame")
flakeHolder.BackgroundTransparency = 1; flakeHolder.Size = UDim2.fromScale(1, 1); flakeHolder.Parent = frostGui
local flakes = {}
for i = 1, 24 do
	local d = Instance.new("Frame")
	d.BackgroundColor3 = Color3.new(1, 1, 1); d.BorderSizePixel = 0
	d.Size = UDim2.fromOffset(4 + (i % 3) * 2, 4 + (i % 3) * 2)
	d.Position = UDim2.fromScale(math.random(), math.random())
	d.BackgroundTransparency = 1; d.Parent = flakeHolder
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = d
	flakes[i] = { f = d, speed = 0.02 + (i % 5) * 0.01, x = math.random() }
end

-- render the freeze level onto all of the above
local function renderFreeze()
	frostGui.Enabled = active or freeze > 0.001
	local f = freeze

	-- edges creep in: at 100% they cover ~40% each toward the centre
	local reach = f * 0.42
	edges.Top.Size    = UDim2.new(1, 0, reach, 0)
	edges.Bottom.Size = UDim2.new(1, 0, reach, 0)
	edges.Left.Size   = UDim2.new(reach, 0, 1, 0)
	edges.Right.Size  = UDim2.new(reach, 0, 1, 0)
	for _, e in ipairs({ edges.Top, edges.Bottom, edges.Left, edges.Right }) do
		e.BackgroundTransparency = 0.35 - f * 0.2
	end

	-- corner blackout kicks in past 75% (the "only a small circle remains" stage)
	local dark = math.clamp((f - 0.6) / 0.4, 0, 1)
	vgrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(math.clamp(0.62 - dark * 0.5, 0.12, 0.62), 1),
		NumberSequenceKeypoint.new(1, 1 - dark * 0.92) })
	-- radial-ish: darken corners by rotating the gradient won't give a circle, so use a
	-- second overlay of black that fades in from the edges
	vignette.BackgroundTransparency = 1 - dark * 0.15

	-- cold blue wash + blur
	coldTint.Enabled = f > 0.01
	coldTint.TintColor = Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(150, 200, 255), f)
	coldTint.Saturation = -0.25 * f
	coldTint.Brightness = -0.05 * f
	coldBlur.Size = f * 8

	-- flakes fade in with the cold
	for _, fl in ipairs(flakes) do
		fl.f.BackgroundTransparency = 1 - math.clamp(f * 1.2, 0, 0.9)
	end
end

-- animate the flakes drifting
RunService.RenderStepped:Connect(function(dt)
	if not frostGui.Enabled then return end
	for _, fl in ipairs(flakes) do
		local p = fl.f.Position
		fl.f.Position = UDim2.fromScale((p.X.Scale + (isBlizzard() and 0.15 or 0.03) * dt) % 1,
			(p.Y.Scale + fl.speed * dt * (isBlizzard() and 3 or 1)) % 1)
	end
end)

-- ============================================================================
-- FREEZE METER (bar) + objective banner
-- ============================================================================
local hud = Instance.new("ScreenGui")
hud.Name = "FreezeHUD"; hud.ResetOnSpawn = false; hud.DisplayOrder = 9; hud.Parent = PlayerGui

local barBg = Instance.new("Frame")
barBg.AnchorPoint = Vector2.new(0.5, 0); barBg.Position = UDim2.new(0.5, 0, 0, 70)
barBg.Size = UDim2.new(0, 380, 0, 26); barBg.BackgroundColor3 = Color3.fromRGB(20, 28, 38)
barBg.Visible = false; barBg.Parent = hud
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 13); c.Parent = barBg
   local s = Instance.new("UIStroke"); s.Color = ICE; s.Thickness = 2; s.Parent = barBg end
local barFill = Instance.new("Frame")
barFill.AnchorPoint = Vector2.new(0, 0.5); barFill.Position = UDim2.new(0, 3, 0.5, 0)
barFill.Size = UDim2.new(0, 0, 1, -6); barFill.BackgroundColor3 = ICE; barFill.Parent = barBg
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 11); c.Parent = barFill end
local barLbl = Instance.new("TextLabel")
barLbl.BackgroundTransparency = 1; barLbl.Size = UDim2.fromScale(1, 1); barLbl.Font = Enum.Font.FredokaOne
barLbl.TextColor3 = Color3.new(1, 1, 1); barLbl.TextScaled = true; barLbl.Text = "FREEZING"; barLbl.Parent = barBg
do local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 15; sz.Parent = barLbl end

local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5, 0); objFrame.Position = UDim2.new(0.5, 0, 0, 104)
objFrame.Size = UDim2.new(0, 460, 0, 40); objFrame.BackgroundColor3 = Color3.fromRGB(20, 28, 38)
objFrame.Visible = false; objFrame.Parent = hud
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = objFrame
   local s = Instance.new("UIStroke"); s.Color = FIREC; s.Thickness = 2; s.Parent = objFrame end
local objLbl = Instance.new("TextLabel")
objLbl.BackgroundTransparency = 1; objLbl.Size = UDim2.fromScale(1, 1); objLbl.Font = Enum.Font.FredokaOne
objLbl.TextColor3 = Color3.fromRGB(255, 235, 210); objLbl.TextScaled = true; objLbl.Parent = objFrame
do local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 17; sz.Parent = objLbl
   local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 12); pad.Parent = objLbl end

local function refreshObjective()
	objFrame.Visible = active and not built
	if not objFrame.Visible then return end
	local parts = {}
	for _, k in ipairs(MAT_ORDER) do
		parts[#parts + 1] = ("%s %d/%d"):format(MAT_ICON[k], placed[k], NEED[k])
	end
	-- Directive banner: when empty-handed it tells the player to go GRAB materials; when carrying
	-- something it tells them to take it to the fire pit -- so the next step is always spelled out.
	if carrying then
		objLbl.Text = ("\xF0\x9F\x94\xA5 Take the %s to the fire pit!   "):format(MAT_LABEL[carrying]) .. table.concat(parts, "   ")
	else
		objLbl.Text = "\xF0\x9F\x94\xA5 Grab logs/stones/kindling from the snow:   " .. table.concat(parts, "   ")
	end
end

-- ============================================================================
-- FADE / DEATH SCREEN
-- ============================================================================
local fadeGui = Instance.new("ScreenGui")
fadeGui.Name = "FreezeFade"; fadeGui.ResetOnSpawn = false; fadeGui.DisplayOrder = 30
fadeGui.IgnoreGuiInset = true; fadeGui.Enabled = false; fadeGui.Parent = PlayerGui
local fadeFrame = Instance.new("Frame")
fadeFrame.Size = UDim2.fromScale(1, 1); fadeFrame.BackgroundColor3 = Color3.new(0, 0, 0)
fadeFrame.BackgroundTransparency = 1; fadeFrame.Parent = fadeGui
local fadeText = Instance.new("TextLabel")
fadeText.AnchorPoint = Vector2.new(0.5, 0.5); fadeText.Position = UDim2.fromScale(0.5, 0.5)
fadeText.Size = UDim2.new(0.8, 0, 0, 140); fadeText.BackgroundTransparency = 1
fadeText.Font = Enum.Font.FredokaOne; fadeText.TextColor3 = FROST; fadeText.TextScaled = true
fadeText.TextTransparency = 1; fadeText.Text = ""; fadeText.Parent = fadeFrame
do local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 40; sz.Parent = fadeText end

-- ============================================================================
-- BUILDING THE CAMPFIRE  (materials snap into place)
-- ============================================================================
local function firePieceCFrame(index)
	-- a ring of logs/stones building up around the campfire base
	local base = campfirePart and campfirePart.CFrame or CFrame.new(startPos or Vector3.new())
	local ang = (index / 8) * math.pi * 2
	return base * CFrame.new(math.cos(ang) * 2.2, 0.4 + (index % 3) * 0.2, math.sin(ang) * 2.2)
end

local function addFirePiece(kind)
	local n = #firePieces + 1
	local piece
	if kind == "firelog" then
		piece = mk({ Name = "BuiltLog", Size = Vector3.new(0.7, 0.7, 3.2), Color = Color3.fromRGB(120, 76, 44),
			Material = Enum.Material.Wood })
		piece.CFrame = firePieceCFrame(n) * CFrame.Angles(0, math.rad(n * 40), math.rad(90))
	elseif kind == "stone" then
		piece = mk({ Name = "BuiltStone", Size = Vector3.new(1.1, 0.8, 1.1), Color = Color3.fromRGB(120, 122, 130),
			Material = Enum.Material.Slate })
		local base = campfirePart and campfirePart.CFrame or CFrame.new(startPos or Vector3.new())
		local a = (n / 8) * math.pi * 2
		piece.CFrame = base * CFrame.new(math.cos(a) * 3.1, 0.3, math.sin(a) * 3.1)
	else
		piece = mk({ Name = "BuiltKindling", Size = Vector3.new(0.3, 0.3, 1.8), Color = Color3.fromRGB(150, 120, 70),
			Material = Enum.Material.Grass })
		piece.CFrame = firePieceCFrame(n) * CFrame.Angles(math.rad(60), math.rad(n * 55), 0)
	end
	piece.Parent = Workspace
	firePieces[#firePieces + 1] = piece
	-- snap-in pop
	local goal = piece.Size
	piece.Size = goal * 0.3
	TweenService:Create(piece, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = goal }):Play()
end

-- an UNLIT campfire that's already sitting at the spot: a ring of stones + a leaning
-- teepee of logs/kindling, no flame. It's the "half-built" fire you finish and light.
local starterBuilt = false
local campfireSign
function buildStarterPile(part)
	if starterBuilt or not part then return end
	starterBuilt = true
	local base = CFrame.new(part.Position)   -- flat, at the marker

	-- a ring of hearth stones
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local s = mk({ Name = "HearthStone", Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.9 + (i % 2) * 0.3, 0.7, 0.9 + (i % 2) * 0.3),
			Color = Color3.fromRGB(120, 122, 130), Material = Enum.Material.Slate, CanCollide = true })
		s.CFrame = base * CFrame.new(math.cos(a) * 2.6, 0.3, math.sin(a) * 2.6)
		s.Parent = part                    -- parent to the marker so it moves with it if needed
	end
	-- a small pile of ash/char in the middle
	local ash = mk({ Name = "Ash", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 3.4, 3.4),
		Color = Color3.fromRGB(60, 56, 54), Material = Enum.Material.Sand })
	ash.CFrame = base * CFrame.new(0, 0.16, 0) * CFrame.Angles(0, 0, math.rad(90))
	ash.Parent = part
	-- a leaning teepee of a few logs (unlit)
	local top
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		local log = mk({ Name = "TeepeeLog", Size = Vector3.new(0.5, 0.5, 3.4),
			Color = Color3.fromRGB(120, 78, 44), Material = Enum.Material.Wood })
		log.CFrame = base * CFrame.new(math.cos(a) * 0.9, 1.3, math.sin(a) * 0.9)
			* CFrame.Angles(math.rad(math.cos(a) * 55), math.rad(-a * 57.3), math.rad(math.sin(a) * 55))
		log.Parent = part
		top = log
	end

	-- a little bubble over it: "build me to stay warm"
	local sign = Instance.new("BillboardGui")
	sign.Name = "CampfireSign"; sign.Adornee = part; sign.Size = UDim2.new(0, 220, 0, 64)
	sign.StudsOffset = Vector3.new(0, part.Size.Y * 0.5 + 4, 0)
	sign.AlwaysOnTop = true; sign.MaxDistance = 120; sign.Parent = part
	local sf = Instance.new("Frame"); sf.Size = UDim2.fromScale(1, 1)
	sf.BackgroundColor3 = Color3.fromRGB(255, 246, 232); sf.BackgroundTransparency = 0.05
	sf.BorderSizePixel = 0; sf.Parent = sign
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 12); sc.Parent = sf
	local ss = Instance.new("UIStroke"); ss.Color = FIREC; ss.Thickness = 2; ss.Parent = sf
	local st = Instance.new("TextLabel"); st.BackgroundTransparency = 1; st.Size = UDim2.fromScale(1, 1)
	st.Font = Enum.Font.FredokaOne; st.Text = "\xF0\x9F\x94\xA5 Build me to stay warm!"
	st.TextColor3 = Color3.fromRGB(120, 60, 20); st.TextScaled = true; st.Parent = sf
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 18; sz.Parent = st
	campfireSign = sign
	-- gentle bob so it reads as interactive
	task.spawn(function()
		local t = 0
		while sign.Parent do t += 0.06; sign.StudsOffset = Vector3.new(0, part.Size.Y * 0.5 + 4 + math.sin(t) * 0.25, 0); task.wait(0.05) end
	end)
end

local fireGlow, fireLoop
local function igniteFire()
	if built then return end
	built = true
	active = false
	_G.campfireQuestComplete = true
	if campfireSign then campfireSign:Destroy(); campfireSign = nil end  -- no more "build me"

	local base = campfirePart and campfirePart.Position or (startPos or Vector3.new())

	-- a glowing ember bed at the bottom
	for i = 1, 7 do
		local a = (i / 7) * math.pi * 2
		local ember = mk({ Name = "Ember", Size = Vector3.new(0.6, 0.35, 0.6),
			Color = Color3.fromRGB(255, 120, 40), Material = Enum.Material.Neon, Transparency = 0.1 })
		ember.CFrame = CFrame.new(base + Vector3.new(math.cos(a) * (0.5 + (i % 3) * 0.35), 0.35, math.sin(a) * (0.5 + (i % 3) * 0.35)))
		ember.Parent = Workspace
		firePieces[#firePieces + 1] = ember
		task.spawn(function()
			local t = i
			while ember.Parent do t += 0.08; ember.Transparency = 0.15 + math.abs(math.sin(t)) * 0.35; task.wait(0.08) end
		end)
	end

	-- layered cone flames: a wide dim outer, a tighter orange mid, a bright yellow core.
	-- Cones taper to a point at the top, so they read as flames, not blobs.
	local layers = {
		{ w = 2.4, h = 3.4, y = 1.7, col = Color3.fromRGB(255, 92, 30),  tr = 0.55, spd = 3.0 },
		{ w = 1.7, h = 4.2, y = 2.1, col = Color3.fromRGB(255, 150, 45), tr = 0.30, spd = 4.2 },
		{ w = 1.0, h = 3.0, y = 1.6, col = Color3.fromRGB(255, 224, 120), tr = 0.10, spd = 5.6 },
	}
	for li, L in ipairs(layers) do
		local flame = Instance.new("Part")
		flame.Name = "Flame" .. li; flame.Anchored = true; flame.CanCollide = false; flame.CanQuery = false
		flame.CastShadow = false; flame.Material = Enum.Material.Neon; flame.Color = L.col
		flame.Transparency = L.tr
		-- a cone-shaped mesh (SpecialMesh cone) so the flame licks upward to a tip
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = "rbxasset://fonts/torch.mesh"     -- built-in torch-flame mesh (no asset auth)
		mesh.Scale = Vector3.new(L.w, L.h, L.w)
		mesh.Parent = flame
		flame.Size = Vector3.new(0.2, 0.2, 0.2)
		flame.CFrame = CFrame.new(base + Vector3.new(0, L.y, 0))
		flame.Parent = Workspace
		firePieces[#firePieces + 1] = flame
		task.spawn(function()
			local t = li * 1.3
			while flame.Parent do
				t += 0.06
				-- flicker: scale wobble + a little sway + colour shimmer
				local fh = L.h * (0.85 + math.abs(math.sin(t * L.spd)) * 0.35)
				local fw = L.w * (0.9 + math.sin(t * L.spd * 0.7) * 0.12)
				mesh.Scale = Vector3.new(fw, fh, fw)
				flame.CFrame = CFrame.new(base + Vector3.new(math.sin(t * 1.7) * 0.18, L.y, math.cos(t * 1.4) * 0.18))
					* CFrame.Angles(math.sin(t) * 0.06, t * 0.4, math.cos(t) * 0.06)
				task.wait(0.03)
			end
		end)
	end

	-- rising sparks
	local sparkPart = mk({ Name = "SparkSource", Size = Vector3.new(1.6, 0.4, 1.6), Transparency = 1 })
	sparkPart.CFrame = CFrame.new(base + Vector3.new(0, 1, 0)); sparkPart.Parent = Workspace
	firePieces[#firePieces + 1] = sparkPart
	do
		local att = Instance.new("Attachment"); att.Parent = sparkPart
		local sparks = Instance.new("ParticleEmitter")
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 210, 120), Color3.fromRGB(255, 90, 40))
		sparks.Size = NumberSequence.new(0.18)
		sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		sparks.Lifetime = NumberRange.new(1, 1.8); sparks.Rate = 26
		sparks.Speed = NumberRange.new(6, 11); sparks.SpreadAngle = Vector2.new(18, 18)
		sparks.Acceleration = Vector3.new(0, 6, 0); sparks.LightEmission = 1
		sparks.EmissionDirection = Enum.NormalId.Top
		sparks.Parent = att
		-- thin smoke above the flames
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(70, 62, 58); smoke.Opacity = 0.28; smoke.Size = 3; smoke.RiseVelocity = 9
		smoke.Parent = sparkPart
	end

	-- warm firelight that flickers
	fireGlow = Instance.new("PointLight")
	fireGlow.Color = Color3.fromRGB(255, 170, 90); fireGlow.Brightness = 3; fireGlow.Range = 42
	fireGlow.Shadows = true
	local anchor = mk({ Name = "FireGlow", Size = Vector3.new(1, 1, 1), Transparency = 1 })
	anchor.CFrame = CFrame.new(base + Vector3.new(0, 2.4, 0)); anchor.Parent = Workspace
	fireGlow.Parent = anchor
	firePieces[#firePieces + 1] = anchor
	task.spawn(function()
		local t = 0
		while anchor.Parent do t += 0.1; fireGlow.Brightness = 2.6 + math.abs(math.sin(t * 3.2)) * 1.2; task.wait(0.05) end
	end)
	fireLoop = playSound(SOUND_FIRE, 0.6, true)

	-- frost melts off the screen fast
	active = false
	task.spawn(function()
		while freeze > 0 do freeze = math.max(0, freeze - 0.06); renderFreeze(); task.wait(0.03) end
		frostGui.Enabled = false
		coldTint.Enabled = false; coldBlur.Size = 0
	end)
	barBg.Visible = false
	refreshObjective()

	objFrame.Visible = true
	objLbl.Text = "\xF0\x9F\x94\xA5 The campfire is lit -- you survived the cold!"
	task.delay(6, function() if built then objFrame.Visible = false end end)

	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({ text = "\xF0\x9F\x94\xA5 Campfire built -- you beat the cold!", color = FIREC }) end)
	end
	print("[Campfire] complete -- fire lit")
end

-- deliver whatever you're carrying to the campfire
local function tryDeliver()
	if not carrying or built then return end
	local hrp = hrpOf(); if not hrp then return end
	local spot = campfirePart and campfirePart.Position or startPos
	if not spot then return end
	if (hrp.Position - spot).Magnitude > DELIVER_RANGE then return end

	local k = carrying
	carrying = nil
	placed[k] = math.min(NEED[k], placed[k] + 1)
	addFirePiece(k)
	setCarryTag(nil)
	refreshObjective()

	if totalPlaced() >= totalNeeded() then
		igniteFire()
	end
end

-- ============================================================================
-- MATERIALS -- pick up, carry, deliver
-- ============================================================================
local carryTag
local carryModel               -- the item welded into your hand while carrying (removed on drop/deliver)
local buildHeldMaterial        -- forward decl (assigned below, after the geometry builders)
function setCarryTag(kind)
	if carryTag then carryTag:Destroy(); carryTag = nil end
	if carryModel then carryModel:Destroy(); carryModel = nil end
	if not kind then return end
	-- put the item straight into the player's hand (a welded copy), plus the head label below
	if buildHeldMaterial then carryModel = buildHeldMaterial(kind) end
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return end
	carryTag = Instance.new("BillboardGui")
	carryTag.Name = "CarryTag"; carryTag.Adornee = head; carryTag.Size = UDim2.new(0, 150, 0, 40)
	carryTag.StudsOffset = Vector3.new(0, 3, 0); carryTag.AlwaysOnTop = true; carryTag.Parent = head
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.FredokaOne; l.Text = MAT_ICON[kind] .. " " .. MAT_LABEL[kind]
	l.TextColor3 = Color3.new(1, 1, 1); l.TextStrokeTransparency = 0.3; l.TextScaled = true; l.Parent = carryTag
end

local function wirePickup(model, kind)
	local main = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not main then return end
	main.CanQuery = true
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"; prompt.ObjectText = MAT_LABEL[kind]
	prompt.HoldDuration = 0; prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false; prompt.Parent = main
	prompt.Triggered:Connect(function()
		if built then return end
		if not active then flash("\xE2\x9D\x84 Talk to the Candy Npc (or /freeze) to start!"); return end
		if carrying then flash("\xF0\x9F\x94\xA5 Take what you're carrying to the campfire first!"); return end
		carrying = kind
		setCarryTag(kind)          -- head label AND a welded copy in the player's hand
		refreshObjective()
		-- the WHOLE ground prop vanishes (every part + its outline, not just the main one) so nothing
		-- is left lying on the ground; another of its kind respawns after a few seconds so you never
		-- run dry. Original transparency is captured so the kindling's invisible spine stays invisible.
		local hl = model:FindFirstChildWhichIsA("Highlight")
		if hl then hl.Enabled = false end
		local hidden = {}
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				hidden[#hidden + 1] = { p, p.Transparency, p.CanCollide }
				p.Transparency = 1; p.CanCollide = false; p.CanQuery = false
			end
		end
		prompt.Enabled = false
		task.delay(6, function()
			for _, e in ipairs(hidden) do
				if e[1].Parent then e[1].Transparency = e[2]; e[1].CanCollide = e[3] end
			end
			if hl then hl.Enabled = true end
			main.CanQuery = true
			prompt.Enabled = true
		end)
		if campfirePart then pointTo(campfirePart.Position) end
	end)
end

function pointTo(pos) if pos and _G.guideTrailTo then pcall(function() _G.guideTrailTo(pos) end) end end

-- a chunky material prop -- each kind clearly DIFFERENT so you can tell them apart at a glance
-- buildMaterialModel(kind): build ONLY the geometry (at local origin), no prompt/highlight/parent.
-- Shared by the ground prop (buildMaterialProp) and the in-hand held copy (buildHeldMaterial).
local function buildMaterialModel(kind)
	local m = Instance.new("Model"); m.Name = "Mat_" .. kind
	m:SetAttribute("QuestProp", true)
	local base = CFrame.new()
	local main

	local function bit(name, size, cf, colour, material, shape)
		local p = mk({ Name = name, Size = size, Color = colour, Material = material or Enum.Material.SmoothPlastic })
		if shape then p.Shape = shape end
		p.CFrame = base * cf
		p.Parent = m
		return p
	end

	if kind == "firelog" then
		-- a THICK bark log: rich dark bark + pale sawn ends with a heart-grain centre, knots + a stub
		main = mk({ Name = "Log", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.6, 1.2, 1.2),
			Color = Color3.fromRGB(92, 57, 31), Material = Enum.Material.Wood, CanQuery = true })
		main.CFrame = base
		main.Parent = m
		for _, s in ipairs({ -1, 1 }) do
			bit("Cut", Vector3.new(0.14, 1.1, 1.1), CFrame.new(s * 1.75, 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(214, 180, 132), Enum.Material.Wood, Enum.PartType.Cylinder).Reflectance = 0.02
			bit("Ring", Vector3.new(0.16, 0.66, 0.66), CFrame.new(s * 1.73, 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(178, 138, 90), Enum.Material.Wood, Enum.PartType.Cylinder)
			bit("Heart", Vector3.new(0.18, 0.24, 0.24), CFrame.new(s * 1.74, 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(150, 108, 66), Enum.Material.Wood, Enum.PartType.Cylinder)
		end
		-- rough bark knots + a snapped branch stub so it clearly reads as real wood
		bit("Knot",  Vector3.new(0.42, 0.42, 0.5), CFrame.new(0.4, 0.5, 0.3), Color3.fromRGB(66, 40, 24), Enum.Material.Wood)
		bit("Knot2", Vector3.new(0.3, 0.3, 0.42), CFrame.new(-0.9, -0.35, 0.35), Color3.fromRGB(66, 40, 24), Enum.Material.Wood)
		bit("Stub",  Vector3.new(0.34, 0.34, 0.7), CFrame.new(-0.5, 0.45, -0.55) * CFrame.Angles(math.rad(30), 0, 0),
			Color3.fromRGB(84, 52, 30), Enum.Material.Wood, Enum.PartType.Cylinder)

	elseif kind == "stone" then
		-- a proper boulder: an angular cluster + mossy top patches + a couple of pebbles at its foot
		main = bit("StoneCore", Vector3.new(1.8, 1.5, 1.7), CFrame.Angles(0.3, 0.5, 0.2),
			Color3.fromRGB(122, 125, 133), Enum.Material.Slate)
		main.CanQuery = true; m.PrimaryPart = main
		for i = 1, 5 do
			local a = (i / 5) * math.pi * 2
			bit("Chunk" .. i, Vector3.new(0.7 + (i % 2) * 0.45, 0.6 + (i % 3) * 0.35, 0.7 + (i % 2) * 0.45),
				CFrame.new(math.cos(a) * 0.72, (i % 2) * 0.3 - 0.2, math.sin(a) * 0.72) * CFrame.Angles(i, i * 1.3, i * 0.7),
				(i % 2 == 0) and Color3.fromRGB(106, 108, 116) or Color3.fromRGB(146, 149, 158), Enum.Material.Rock)
		end
		bit("Moss",  Vector3.new(1.05, 0.22, 0.95), CFrame.new(-0.15, 0.72, 0.1), Color3.fromRGB(92, 146, 86), Enum.Material.Grass)
		bit("Moss2", Vector3.new(0.5, 0.2, 0.55), CFrame.new(0.55, 0.6, -0.35), Color3.fromRGB(78, 128, 74), Enum.Material.Grass)
		for _, o in ipairs({ Vector3.new(1.1, -0.55, 0.5), Vector3.new(-0.95, -0.6, -0.6) }) do
			bit("Pebble", Vector3.new(0.42, 0.34, 0.4), CFrame.new(o.X, o.Y, o.Z) * CFrame.Angles(0.4, 0.8, 0.2),
				Color3.fromRGB(134, 137, 145), Enum.Material.Rock)
		end

	else
		-- a BUNDLE of thin dry twigs tied together, with a few loose leaves poking out
		main = mk({ Name = "Kindling", Size = Vector3.new(0.2, 0.2, 2.4), Transparency = 1, CanQuery = true })
		main.CFrame = base
		main.Parent = m; m.PrimaryPart = main
		for i = 1, 7 do
			local a = (i / 7) * math.pi * 2
			bit("Twig" .. i, Vector3.new(0.15, 0.15, 2.2 + (i % 3) * 0.35),
				CFrame.new(math.cos(a) * 0.28, math.sin(a) * 0.28, (i % 2) * 0.15)
					* CFrame.Angles(math.rad((i % 3) * 4), math.rad((i % 4) * 3), 0),
				(i % 2 == 0) and Color3.fromRGB(176, 142, 90) or Color3.fromRGB(148, 114, 68), Enum.Material.Wood)
		end
		-- two twine ties around the bundle
		for _, z in ipairs({ -0.7, 0.7 }) do
			bit("Twine", Vector3.new(0.72, 0.12, 0.72), CFrame.new(0, 0, z) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(120, 90, 50), Enum.Material.Fabric, Enum.PartType.Cylinder)
		end
		for _, lf in ipairs({ { 0.32, 0.2, 1.0, Color3.fromRGB(150, 120, 60) }, { -0.3, 0.18, -0.9, Color3.fromRGB(120, 92, 48) } }) do
			bit("Leaf", Vector3.new(0.5, 0.06, 0.4), CFrame.new(lf[1], lf[2], lf[3]) * CFrame.Angles(math.rad(20), math.rad(30), 0),
				lf[4], Enum.Material.Grass)
		end
	end

	if not m.PrimaryPart then m.PrimaryPart = main end
	return m
end

-- the GROUND pickup: shared geometry + a frost outline + the "Pick up" prompt, dropped at `at`.
local function buildMaterialProp(kind, at)
	local m = buildMaterialModel(kind)
	local main = m.PrimaryPart
	m:PivotTo(CFrame.new(at + Vector3.new(0, 1, 0)))
	local hl = Instance.new("Highlight"); hl.FillTransparency = 1; hl.OutlineColor = FROST
	hl.OutlineTransparency = 0.2; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = main; hl.Parent = m
	m.Parent = Workspace
	wirePickup(m, kind)
	return m
end

-- the IN-HAND copy: shared geometry welded into the player's hand. Assigned to the forward-declared
-- upvalue so setCarryTag (defined earlier) can build it on pickup. Move the (still-anchored) model
-- into the palm, weld it up, THEN unanchor so it rides the hand cleanly.
buildHeldMaterial = function(kind)
	local char = player.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	if not (hand and hand:IsA("BasePart")) then return nil end
	local m = buildMaterialModel(kind)
	local prim = m.PrimaryPart
	if not prim then m:Destroy(); return nil end
	m:PivotTo(hand.CFrame * CFrame.new(0, -1.3, 0))
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p ~= prim then
			local w = Instance.new("WeldConstraint"); w.Part0 = prim; w.Part1 = p; w.Parent = p
		end
	end
	local hw = Instance.new("WeldConstraint"); hw.Part0 = hand; hw.Part1 = prim; hw.Parent = prim
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false; p.CanCollide = false; p.CanQuery = false; p.Massless = true end
	end
	m.Parent = char
	return m
end

-- ============================================================================
-- OBJECTIVE FLASH
-- ============================================================================
local flashTok = 0
function flash(text)
	flashTok += 1; local mine = flashTok
	objFrame.Visible = true
	objLbl.Text = text
	task.delay(2.4, function() if mine == flashTok then refreshObjective() end end)
end

-- ============================================================================
-- START / RESET / FAIL
-- ============================================================================
local windLoop, heartLoop

local function clearBuild()
	for _, p in ipairs(firePieces) do pcall(function() p:Destroy() end) end
	firePieces = {}
	placed = { firelog = 0, stone = 0, kindling = 0 }
	carrying = nil
	setCarryTag(nil)
end

local function stopSounds()
	if windLoop then windLoop:Stop(); windLoop:Destroy(); windLoop = nil end
	if heartLoop then heartLoop:Stop(); heartLoop:Destroy(); heartLoop = nil end
end

local function startFreeze()
	if active or built then return end
	active = true
	freeze = 0
	clearBuild()
	barBg.Visible = true
	frostGui.Enabled = true
	refreshObjective()
	renderFreeze()
	windLoop = playSound(SOUND_WIND, 0.4, true)
	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({ text = "\xE2\x9D\x84 You're freezing -- build the campfire!", color = ICE }) end)
	end
	print("[Campfire] freeze started")
end

local function failFreeze()
	active = false
	stopSounds()
	fadeGui.Enabled = true
	-- freeze the final circle, then fade to black
	TweenService:Create(fadeFrame, TweenInfo.new(1.2), { BackgroundTransparency = 0 }):Play()
	task.delay(0.6, function()
		fadeText.Text = "\xF0\x9F\xA5\xB6 YOU DIDN'T SURVIVE THE COLD\n\nRestarting Expedition..."
		TweenService:Create(fadeText, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
	end)

	task.delay(3.2, function()
		-- teleport back to the start and reset
		local char = player.Character
		if char and startPos then char:PivotTo(CFrame.new(startPos + Vector3.new(0, 4, 0))) end
		clearBuild()
		freeze = 0
		renderFreeze()
		coldTint.Enabled = false; coldBlur.Size = 0
		TweenService:Create(fadeText, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.wait(0.4)
		TweenService:Create(fadeFrame, TweenInfo.new(1), { BackgroundTransparency = 1 }):Play()
		task.delay(1, function()
			fadeGui.Enabled = false
			-- start the cold again for another attempt
			startFreeze()
		end)
	end)
	print("[Campfire] froze -- expedition reset")
end

-- ============================================================================
-- THE FREEZE TICK
-- ============================================================================
local heartOn = false
task.spawn(function()
	while true do
		local dt = task.wait(0.1)
		if active and not built then
			local hrp = hrpOf()
			local warm = false
			-- near a LIT fire you'd warm up -- but the fire only exists once built, so during
			-- the quest the only warmth is finishing it. (Kept for symmetry / future braziers.)
			local rate
			if isBlizzard() then rate = 1 / FREEZE_BLIZZARD_TIME else rate = 1 / FREEZE_CALM_TIME end
			freeze = math.clamp(freeze + rate * dt, 0, 1)

			-- speed penalty by stage
			local hum = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
			if hum then
				local slow = 1
				if     freeze >= 0.75 then slow = 0.45
				elseif freeze >= 0.50 then slow = 0.62
				elseif freeze >= 0.25 then slow = 0.82 end
				hum.WalkSpeed = BASE_WALKSPEED * slow
			end

			barFill.Size = UDim2.new(freeze, -6, 1, -6)
			barFill.BackgroundColor3 = Color3.fromRGB(150, 205, 245):Lerp(Color3.fromRGB(90, 150, 220), freeze)
			barLbl.Text = ("FREEZING  %d%%"):format(math.floor(freeze * 100))
			renderFreeze()

			-- heartbeat past 50%
			if freeze >= 0.5 and not heartOn then heartOn = true; heartLoop = playSound(SOUND_HEART, 0.5, true) end
			if freeze < 0.5 and heartOn then heartOn = false; if heartLoop then heartLoop:Stop(); heartLoop:Destroy(); heartLoop = nil end end

			if freeze >= 1 then failFreeze() end
		elseif not active then
			-- restore speed when not freezing
			local hum = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
			if hum and hum.WalkSpeed < BASE_WALKSPEED then hum.WalkSpeed = BASE_WALKSPEED end
		end
	end
end)

-- ============================================================================
-- NPC + GO
-- ============================================================================
local function findNPCNear(ref)
	if not ref then return nil end
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		if norm(d.Name) == "candynpc" then
			local head = (d:IsA("Model") and (d:FindFirstChild("Head") or d.PrimaryPart or firstBasePart(d))) or firstBasePart(d)
			if head then
				local dist = (head.Position - ref).Magnitude
				if dist <= ISLAND_RANGE and (not bestD or dist < bestD) then best, bestD = head, dist end
			end
		end
	end
	return best
end

task.spawn(function()
	local isle = pollFor(function()
		local x = Workspace:FindFirstChild(ISLAND_NAME)
		if x then return x end
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("Model") and string.lower(d.Name):match("^island_?4$") then return d end
		end
		return nil
	end, 45)
	if isle then
		local ok, cf = pcall(function() return (select(1, isle:GetBoundingBox())) end)
		islandPos = (ok and cf) and cf.Position or nil
	end

	-- everything this quest uses must be ON island4 -- "fire" is a common name, so a flame
	-- part on another island must never be mistaken for the campfire spot
	local function onIsland4(pos)
		if not islandPos then return true end
		return (pos - islandPos).Magnitude <= ISLAND_RANGE
	end

	-- the campfire spot: a part named exactly "fire" (or "campfire") on island4.
	-- POLL for it -- StreamingEnabled means island4's parts arrive only once you're near,
	-- so a one-shot scan (which is what missed it before) finds nothing.
	local function isCampfireName(nm)
		local n = norm(nm)
		for _, k in ipairs(CAMPFIRE_NAMES) do if n == k then return true end end
		return false
	end
	campfirePart = pollFor(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("Model")) and isCampfireName(d.Name) then
				local bp = firstBasePart(d)
				if bp and onIsland4(bp.Position) then return bp end
			end
		end
		return nil
	end, 90)

	-- hide the placement brick -- it's only a marker for WHERE the fire is built
	if campfirePart then
		campfirePart.Transparency = 1
		campfirePart.CanCollide = false
		campfirePart.CanQuery = false
		buildStarterPile(campfirePart)   -- an unlit teepee of sticks, ready to build up
	end

	-- the start / respawn point (on island4)
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and norm(d.Name) == START_NAME and onIsland4(d.Position) then
			startPos = d.Position; break
		end
	end
	if not startPos then startPos = campfirePart and campfirePart.Position or islandPos end

	local anchor = campfirePart and campfirePart.Position or islandPos

	-- MATERIALS: the parts you named "material"/"materials" on island4 are the SPAWN SPOTS.
	-- Poll for them (streaming), hide each block, and grow a pickup on top. Types are dealt
	-- out to match what the fire needs (5 logs, 8 stones, 3 kindling).
	local spots = pollFor(function()
		local found = {}
		for _, d in ipairs(Workspace:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("Model")) and not d:GetAttribute("QuestProp") then
				local n = norm(d.Name)
				if (n == "material" or n == "materials") then
					local bp = firstBasePart(d)
					if bp and onIsland4(bp.Position) then found[#found + 1] = { holder = d, pos = bp.Position } end
				end
			end
		end
		return (#found > 0) and found or nil
	end, 90)

	if spots then
		-- Deal a TYPE to each spot in proportion to what the fire needs (5/8/3), spread out
		-- evenly rather than clustered -- a weighted round-robin. Over 16 spots that lands
		-- exactly 5 logs / 8 stones / 3 kindling, interleaved; over more it scales up.
		local total = #spots
		local counts = { firelog = 0, stone = 0, kindling = 0 }
		local totalNeed = NEED.firelog + NEED.stone + NEED.kindling
		for i, s in ipairs(spots) do
			-- hide the placement block
			for _, q in ipairs(s.holder:IsA("Model") and s.holder:GetDescendants() or { s.holder }) do
				if q:IsA("BasePart") then q.Transparency = 1; q.CanCollide = false; q.CanQuery = false end
			end
			-- whichever type is most "owed" so far gets this spot
			local bestKind, bestOwed
			for _, kind in ipairs(MAT_ORDER) do
				local owed = (NEED[kind] / totalNeed) * i - counts[kind]
				if not bestOwed or owed > bestOwed then bestKind, bestOwed = kind, owed end
			end
			counts[bestKind] += 1
			buildMaterialProp(bestKind, s.pos)
		end
		print(("[Campfire] %d material spot(s) wired -- %d log / %d stone / %d kindling"):format(
			total, counts.firelog, counts.stone, counts.kindling))
	elseif anchor then
		-- no 'material' spots found -> scatter our own around the campfire
		local i = 0
		for _, kind in ipairs(MAT_ORDER) do
			for _ = 1, NEED[kind] + 2 do
				i += 1
				local a = (i / 22) * math.pi * 2
				local r = 24 + (i % 4) * 8
				buildMaterialProp(kind, anchor + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
			end
		end
		warn("[Campfire] no 'material' spots found -- scattered a fallback supply")
	end

	npcHead = pollFor(function() return findNPCNear(anchor or islandPos) end, 20)
	if npcHead then wireNPC(npcHead) end

	print(("[Campfire] ready -- campfire %s, start %s, NPC %s"):format(
		campfirePart and "found" or "MISSING", startPos and "set" or "MISSING", npcHead and "wired" or "none"))
end)

-- NPC -- paged speech bubble that gives the quest, same pattern as island1's Candy Npc
local function npcBubble(head, text, persist, footer)
	local prev = head:FindFirstChild("SpeechBubble"); if prev then prev:Destroy() end
	local bb = Instance.new("BillboardGui"); bb.Name = "SpeechBubble"; bb.Adornee = head
	bb.Size = UDim2.new(0, 330, 0, 150); bb.StudsOffset = Vector3.new(0, 5.5, 0)
	bb.AlwaysOnTop = true; bb.MaxDistance = 120; bb.Parent = head
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = Color3.fromRGB(240, 248, 255)
	f.BackgroundTransparency = 0.05; f.BorderSizePixel = 0; f.Parent = bb
	local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0, 14); cr.Parent = f
	local st = Instance.new("UIStroke"); st.Color = ICE; st.Thickness = 2; st.Parent = f
	local pd = Instance.new("UIPadding")
	pd.PaddingTop = UDim.new(0, 12); pd.PaddingBottom = UDim.new(0, 12)
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = f
	local l = Instance.new("TextLabel"); l.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1; l.Font = Enum.Font.FredokaOne; l.Text = text
	l.TextColor3 = Color3.fromRGB(40, 60, 90); l.TextScaled = true; l.TextWrapped = true; l.Parent = f
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 20; sz.Parent = l
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1, 0.2); h.Position = UDim2.fromScale(0, 0.8)
		h.BackgroundTransparency = 1; h.Font = Enum.Font.FredokaOne; h.Text = footer
		h.TextColor3 = Color3.fromRGB(120, 150, 190); h.TextScaled = true; h.Parent = f
		local hs = Instance.new("UITextSizeConstraint"); hs.MaxTextSize = 13; hs.Parent = h
	end
	return bb
end

local function questPages()
	if built then return { "Toasty! You built it just in time. \xF0\x9F\x94\xA5" } end
	if active then
		return {
			("Still need %d logs \xF0\x9F\xAA\xB5, %d stones \xF0\x9F\xAA\xA8 and %d kindling \xF0\x9F\x8C\xB2.")
				:format(NEED.firelog - placed.firelog, NEED.stone - placed.stone, NEED.kindling - placed.kindling),
			"Find them in the snow, walk up and GRAB each one,",
			"then carry it back to the fire pit to drop it in! \xF0\x9F\x94\xA5",
		}
	end
	return {
		"Brrr! You're turning blue -- this cold will freeze you solid. \xE2\x9D\x84\xEF\xB8\x8F",
		"Let's build a campfire! Here's how:",
		"1) Look around the snow for LOGS \xF0\x9F\xAA\xB5, STONES \xF0\x9F\xAA\xA8 and KINDLING \xF0\x9F\x8C\xB2.",
		"2) Walk up to each one and GRAB it, then carry it to the fire pit. \xF0\x9F\x94\xA5",
		"You need 5 logs, 8 stones and 3 kindling. The pit's right over there!",
		"Hurry -- the Freeze Meter starts the moment we stop talking. GO!",
	}
end

function wireNPC(head)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = "Candy Npc"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false; prompt.Parent = head

	local pages, index, watching = nil, 0, false
	local function closeDialogue()
		local b = head:FindFirstChild("SpeechBubble"); if b then b:Destroy() end
		prompt.ActionText = "Talk"; index = 0; pages = nil
	end
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
		-- reading past page 1 accepts the quest and starts the cold
		if index == 2 and not active and not built then
			startFreeze()
			if campfirePart and _G.guideTrailTo then pcall(function() _G.guideTrailTo(campfirePart.Position) end) end
		end
		local last = index >= #pages
		npcBubble(head, pages[index], true, last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages))
		prompt.ActionText = last and "Close" or "Continue"
		startWatcher()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then closeDialogue() end end)
end

-- ============================================================================
-- deliver-on-touch of the campfire, plus /freeze test command
-- ============================================================================
task.spawn(function()
	while true do
		task.wait(0.2)
		if active and carrying and not built then tryDeliver() end
	end
end)

local function onCommand(msg)
	local t = tostring(msg or ""):lower()
	if t:sub(1, 7) == "/freeze" then
		if built then return end
		startFreeze()
		print("[Campfire][TEST] /freeze -- cold started")
	elseif t:sub(1, 5) == "/warm" then
		-- convenience: stop the cold
		active = false; freeze = 0; renderFreeze()
		frostGui.Enabled = false; coldTint.Enabled = false; coldBlur.Size = 0
		stopSounds()
		local hum = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
		if hum then hum.WalkSpeed = BASE_WALKSPEED end
		print("[Campfire][TEST] /warm -- cold stopped")
	end
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
