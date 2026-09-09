--======================================================================
-- CandyMineExplosionQuest_AllInOne.client.lua  (LocalScript)  -- CandyRealm
--======================================================================
-- ISLAND 16 -- "CANDY MINE EXPLOSION"
--
--   1. FIND     four unstable candy crystals around the cliffs (your parts named "unstable")
--   2. CARRY    each one back to the centre, to the giant candy
--   3. THE LIVE ONE  the FINAL crystal wakes up the moment you grab it: it is armed in your
--                hands, the fuse HUD becomes its clock, and you have ARM_SECONDS to sprint it
--                onto a pad. Too slow -> it fizzles and flies home; grab it and go again.
--                No death, no lost progress -- just a finale with a finale mechanic in it.
--   4. THE FUSE  seating the LAST charge arms the shot: a 10s countdown runs (no prompt to
--                press), the island's light DIES second by second, and the HUD reads your
--                actual distance -- "SAFE -- KEEP GOING!" vs "TOO CLOSE -- RUN!!". Standing
--                inside LAUNCH_RANGE at zero gets you comedically flung (harmless), because
--                a countdown someone can ignore point-blank was a countdown about nothing.
--
-- ⚠ ISLAND 16 IS OFF THE LADDER, ON PURPOSE (your call). It is NOT in IslandOrder.SLOT_TO_ISLAND, so
-- IslandLayout leaves it wherever Studio has it and no crossing leads to it -- reach it with /island16 or
-- the wormhole. The ONE thing it still needs from the tower plumbing is streaming persistence, which is
-- why IslandStreaming.server.luau now carries an EXTRA_PERSIST list with island16 in it. Without that its
-- parts do not replicate at distance and the five "unstable" markers read as missing -- exactly the bug
-- that left island 9 empty.
--
-- CONVENTIONS COPIED FROM THE OTHER ISLANDS, deliberately, so this reads as one realm:
--   * the Candy Npc speech bubble, paging and prompt are CrystalMineQuest's verbatim (320x150 bubble,
--     FredokaOne, "[E] more (n/m)" footer, walk-away close at TALK_DISTANCE)
--   * the objective ScreenGui is named "...Objective", which is the suffix ObjectiveBannerBridge matches
--     on -- so this quest's banner rides the realm banner at PRIORITY.REWARD for free, and its own frame
--     stays hidden. A twelfth quest needs no change to that bridge.
--   * markers are matched with norm() (lowercase, spaces/underscores/hyphens stripped), because names in
--     this place carry stray spaces and casing ("Candy Npc", "gas vents ").
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")  -- CoinEvent lives here (finale payout)
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local Lighting          = game:GetService("Lighting")           -- the storm recolours the sky
local Debris            = game:GetService("Debris")

-- DECLARED FALSE AT BOOT, not left nil. Every reader today uses `not _G.candyMineQuestComplete`,
-- and nil is falsy, so this changes no behaviour -- but a later `== false` test would
-- silently never match on a flag that was never declared, and this states up front that
-- island16 Candy Mine owns it.
_G.candyMineQuestComplete = false

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_NAME    = "island16"
local CRYSTAL_NAME   = "unstable"     -- YOUR five parts. Matched with norm(), so "Unstable 1" counts.
-- The blast target, IN PRIORITY ORDER -- yours is "giantcandy", which is why it is first.
--
-- ⚠ SEARCHED ONE NAME AT A TIME, ALL THE WAY THROUGH THE ISLAND, before trying the next. The obvious
-- way round -- walk the descendants once and take the first that matches ANY of these -- is wrong here,
-- because "candy" is a substring of "Candy Npc": whichever of the two GetDescendants happened to reach
-- first would win, and on a bad ordering the quest would ring five explosive charges around the woman
-- giving you the quest. Order of the LIST must beat order of the WORKSPACE.
local CANDY_NAMES    = { "giantcandy", "candy" }
local NPC_HINT       = "candynpc"
local TALK_DISTANCE  = 12
local BANNER_RANGE   = 320
local PICKUP_RANGE   = 12             -- how close to grab a crystal
-- How close to a CHARGE PAD you must be to seat a charge -- not to the candy. Generous enough that you do
-- not have to hit the disc exactly, tight enough that walking the ring does not fill sockets you did not
-- mean to. Also reused as the BLOW IT prompt's range on the candy itself, where it is measured from the
-- candy and so is the "standing at the ring" distance -- which is what you want for the detonator.
local PLACE_RANGE    = 26
local CHARGES        = 4              -- one per crystal; the ring around the candy has this many sockets.
                                      -- 4, not 5: island16 only has four crystals you can actually pick
                                      -- up, and a fifth socket meant a ring with a permanently empty hole
                                      -- and a counter that could never reach its own target. This ONE
                                      -- number drives the socket ring, the crystal cap, every "x of y"
                                      -- line and the BLOW IT gate, so they cannot drift apart.
local RING_GAP       = 8              -- studs out from the candy's edge that the sockets sit
local ARM_SECONDS    = 15             -- how long the LIVE final crystal gives you to reach a pad
                                      -- before it fizzles and flies home (retry, never a fail)
local LAUNCH_RANGE   = 60             -- inside this at detonation = comedically flung (harmless);
                                      -- also what the fuse HUD's SAFE / TOO CLOSE line reads

-- Audio: "" = silent and nothing is created. Same rule as every other quest here.
local SOUND_PICKUP   = ""
local SOUND_PLACE    = ""
local SOUND_BOOM     = ""

-- palette -- CrystalMineQuest's, so the two mine quests match
local FILL   = Color3.fromRGB(255, 240, 248)
local STROKE = Color3.fromRGB(200, 60, 120)
local TEXTC  = Color3.fromRGB(80, 30, 60)
local HINTC  = Color3.fromRGB(150, 120, 160)
local PINK   = Color3.fromRGB(255, 95, 160)
local GOLD   = Color3.fromRGB(255, 205, 90)
local GREEN  = Color3.fromRGB(110, 210, 120)
local DANGER = Color3.fromRGB(255, 110, 70)

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s) return (tostring(s or ""):lower():gsub("[%s_%-]", "")) end

local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat local r = fn(); if r then return r end; task.wait(0.5) until os.clock() - t0 > (timeout or 45)
	return fn()
end

local function firstBasePart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function hrpOf()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function playSound(id, vol)
	if not id or id == "" then return end
	local s = Instance.new("Sound"); s.SoundId = id; s.Volume = vol or 0.6
	s.Parent = SoundService; s:Play(); Debris:AddItem(s, 6)
end

local function tween(o, t, props, style)
	local ti = TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tw = TweenService:Create(o, ti, props); tw:Play(); return tw
end

local island

-- ============================================================================
-- STATE
-- ============================================================================
local accepted   = false
local finished   = false
local carrying   = nil    -- the crystal record currently in hand
local placedCount = 0
-- THE FUSE. Seating the LAST charge arms the shot; nothing is pressed. fuseLeft is the second
-- currently on the clock (nil when it is not running) and it is what the banner reads, so the
-- countdown has ONE source and the on-screen number can never disagree with the objective line.
local FUSE_SECONDS = 10
local fuseLeft   = nil
local armLeft    = nil    -- seconds left on the LIVE final crystal in your hands (nil = not armed)
local startFuse            -- assigned after crackOpen, which it calls at zero
-- THE LIGHTS DIE WITH THE FUSE: a gloom wash that deepens every second of the countdown, so the
-- escape run happens into gathering dark. Ours alone to enable/disable -- no sky system fought.
local gloom = Instance.new("ColorCorrectionEffect")
gloom.Name = "CandyMineFuseGloom"; gloom.Enabled = false; gloom.Parent = Lighting
local crystals   = {}     -- { part=, home=CFrame, taken=bool, placed=bool, aura=Folder, prompt= }
local sockets    = {}     -- ring positions around the giant candy
local candyPart           -- the giant candy's BasePart (or the model's biggest part)
local candyModel
local npcHead
local refreshBanner       -- forward -- the banner block defines it

-- ============================================================================
-- THE AURA -- "so players know which pieces matter"
-- ============================================================================
-- A crystal you are meant to find has to read as findable from across a cliff face. Four layers, all
-- engine-animated or one looping tween -- NO per-frame code, because five of these run forever and a
-- Heartbeat loop per crystal is five loops for decoration.
--
--   1. a pulsing Highlight   -- visible THROUGH the cliffs, which is what makes them findable at all
--   2. a neon glow shell     -- shape at distance, once the highlight's outline is too thin to read
--   3. rising sparkles       -- movement, so it never reads as a flat decal
--   4. a coloured PointLight -- it lights the rock around it, so it looks placed rather than pasted
--
-- The whole lot lives in ONE folder per crystal, so clearing it is one Destroy.
local function addAura(part, colour)
	local old = part:FindFirstChild("UnstableAura")
	if old then old:Destroy() end

	local f = Instance.new("Folder"); f.Name = "UnstableAura"; f.Parent = part

	local hl = Instance.new("Highlight")
	hl.Name = "AuraOutline"
	hl.FillColor = colour; hl.FillTransparency = 0.72
	hl.OutlineColor = Color3.new(1, 1, 1); hl.OutlineTransparency = 0.1
	-- AlwaysOnTop: the point of the aura is finding these THROUGH the cliffs they are tucked into.
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = part; hl.Parent = f
	TweenService:Create(hl, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ FillTransparency = 0.92, OutlineTransparency = 0.5 }):Play()

	-- glow shell: a slightly larger neon copy of the part's bounding box, breathing
	local shell = Instance.new("Part")
	shell.Name = "AuraShell"
	shell.Size = part.Size * 1.35
	shell.CFrame = part.CFrame
	shell.Anchored = true; shell.CanCollide = false; shell.CanQuery = false; shell.CanTouch = false
	shell.CastShadow = false
	shell.Material = Enum.Material.Neon; shell.Color = colour; shell.Transparency = 0.82
	shell.Shape = Enum.PartType.Ball
	shell.Parent = f
	TweenService:Create(shell, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = part.Size * 1.75, Transparency = 0.93 }):Play()

	local att = Instance.new("Attachment"); att.Parent = shell

	local sp = Instance.new("ParticleEmitter")
	sp.Name = "AuraSparkle"
	sp.Rate = 14
	sp.Lifetime = NumberRange.new(0.9, 1.6)
	sp.Speed = NumberRange.new(2, 4)
	sp.EmissionDirection = Enum.NormalId.Top
	sp.SpreadAngle = Vector2.new(28, 28)
	sp.Acceleration = Vector3.new(0, 2.5, 0)
	sp.LightEmission = 0.9
	sp.Rotation = NumberRange.new(0, 360)
	sp.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	sp.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sp.Color = ColorSequence.new(colour, Color3.new(1, 1, 1))
	sp.Parent = att

	local lt = Instance.new("PointLight")
	lt.Name = "AuraLight"
	lt.Color = colour; lt.Brightness = 1.5; lt.Range = 16; lt.Shadows = false
	lt.Parent = shell
	TweenService:Create(lt, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Brightness = 2.6 }):Play()

	return f
end

-- The shell is anchored, so it does NOT follow a part that moves. Crystals only move while carried, and
-- the aura is cleared on pickup, so this never needs a follow loop -- it is re-added at the socket.
local function clearAura(part)
	local f = part and part:FindFirstChild("UnstableAura")
	if f then f:Destroy() end
end

-- ============================================================================
-- FINDING THINGS
-- ============================================================================
local function findIsland()
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and norm(m.Name) == ISLAND_NAME then return m end
	end
	return nil
end

-- Scoped to the island, never a Workspace-wide sweep: "candy" is a common word in this place and a
-- realm-wide search would happily wire island 1's gumball machine as the blast target.
local function findInIsland(scope, matchFn)
	if not scope then return nil end
	for _, d in ipairs(scope:GetDescendants()) do
		if matchFn(d) then return d end
	end
	return nil
end

local function isCrystal(d)
	return (d:IsA("BasePart") or d:IsA("Model")) and norm(d.Name):find(CRYSTAL_NAME, 1, true) ~= nil
end

local function scanCrystals()
	if not island then return 0 end
	local n = 0
	for _, d in ipairs(island:GetDescendants()) do
		if isCrystal(d) then
			local p = firstBasePart(d)
			-- Skip anything already registered, and skip the aura shells we ourselves created (they live
			-- inside a registered part, and matching them would register decoration as objectives).
			if p and not p:FindFirstAncestorOfClass("Tool") and p.Name ~= "AuraShell" then
				local known = false
				for _, c in ipairs(crystals) do if c.part == p then known = true; break end end
				if not known and #crystals < CHARGES then
					crystals[#crystals + 1] = { part = p, home = p.CFrame, taken = false, placed = false }
					n += 1
				end
			end
		end
	end
	return n
end

-- ============================================================================
-- SPEECH BUBBLE + OBJECTIVE BANNER  (CrystalMineQuest's, verbatim in style)
-- ============================================================================
local function hideBubble(a) local p = a:FindFirstChild("SpeechBubble"); if p then p:Destroy() end end

local function showBubble(a, text, persist, footer)
	hideBubble(a)
	local bb = Instance.new("BillboardGui"); bb.Name = "SpeechBubble"; bb.Adornee = a
	bb.Size = UDim2.new(0,320,0,150); bb.StudsOffset = Vector3.new(0,5.5,0); bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1,1); f.BackgroundColor3 = FILL
	f.BackgroundTransparency = 0.05; f.BorderSizePixel = 0; f.Parent = bb
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,18)
	local st = Instance.new("UIStroke"); st.Color = STROKE; st.Thickness = 2; st.Transparency = 0.3; st.Parent = f
	local pd = Instance.new("UIPadding")
	pd.PaddingTop=UDim.new(0,12); pd.PaddingBottom=UDim.new(0,12)
	pd.PaddingLeft=UDim.new(0,14); pd.PaddingRight=UDim.new(0,14); pd.Parent = f
	local l = Instance.new("TextLabel")
	l.Size = footer and UDim2.fromScale(1,0.78) or UDim2.fromScale(1,1); l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne; l.Text = text; l.TextColor3 = TEXTC; l.TextScaled = true; l.TextWrapped = true; l.Parent = f
	Instance.new("UITextSizeConstraint", l).MaxTextSize = 22
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1,0.2); h.Position = UDim2.fromScale(0,0.8)
		h.BackgroundTransparency = 1
		h.Font = Enum.Font.FredokaOne; h.Text = footer; h.TextColor3 = HINTC; h.TextScaled = true; h.Parent = f
		Instance.new("UITextSizeConstraint", h).MaxTextSize = 14
	end
	bb.Parent = a
	if not persist then
		task.delay(9, function()
			if bb and bb.Parent == a and bb.Name == "SpeechBubble" then bb:Destroy() end
		end)
	end
end

-- "...Objective" suffix: ObjectiveBannerBridge disables this ScreenGui and mirrors the frame's text onto
-- the realm banner. The frame's Visible is still ours to drive; the bridge only reads it.
local objGui = Instance.new("ScreenGui")
objGui.Name = "CandyMineObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7; objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5,0); objFrame.Position = UDim2.new(0.5,0,0,12)
objFrame.Size = UDim2.new(0,520,0,52); objFrame.BackgroundColor3 = FILL; objFrame.Visible = false; objFrame.Parent = objGui
Instance.new("UICorner", objFrame).CornerRadius = UDim.new(0,16)
do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 3; s.Parent = objFrame end
local objLabel = Instance.new("TextLabel")
objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1,1); objLabel.Font = Enum.Font.FredokaOne
objLabel.TextColor3 = TEXTC; objLabel.TextScaled = true; objLabel.Parent = objFrame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = objLabel
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,14); pad.PaddingRight = UDim.new(0,14); pad.Parent = objLabel
end

--======================================================================
-- THE COUNTDOWN
--======================================================================
-- Its OWN ScreenGui, deliberately, and not the objective banner: the objective banner hides itself
-- past BANNER_RANGE, and the whole point of a fuse is that you are running AWAY from the candy
-- while it burns. A countdown that vanishes the moment you get clear is a countdown that is not
-- doing its job.
local fuseGui = Instance.new("ScreenGui")
fuseGui.Name = "CandyMineFuse"; fuseGui.ResetOnSpawn = false
fuseGui.IgnoreGuiInset = true; fuseGui.DisplayOrder = 30; fuseGui.Enabled = false
fuseGui.Parent = player:WaitForChild("PlayerGui")

local fuseCap = Instance.new("TextLabel")
fuseCap.AnchorPoint = Vector2.new(0.5, 0)
fuseCap.Position = UDim2.new(0.5, 0, 0.16, 0); fuseCap.Size = UDim2.new(0, 560, 0, 34)
fuseCap.BackgroundTransparency = 1; fuseCap.Font = Enum.Font.FredokaOne; fuseCap.TextSize = 30
fuseCap.TextColor3 = DANGER; fuseCap.Text = "GET CLEAR!"; fuseCap.Parent = fuseGui
do local t = Instance.new("UIStroke", fuseCap); t.Color = Color3.new(0, 0, 0); t.Thickness = 3
   t.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual end

local fuseNum = Instance.new("TextLabel")
fuseNum.AnchorPoint = Vector2.new(0.5, 0)
fuseNum.Position = UDim2.new(0.5, 0, 0.20, 0); fuseNum.Size = UDim2.new(0, 300, 0, 150)
fuseNum.BackgroundTransparency = 1; fuseNum.Font = Enum.Font.FredokaOne; fuseNum.TextScaled = true
fuseNum.TextColor3 = GOLD; fuseNum.Text = "10"; fuseNum.Parent = fuseGui
do local t = Instance.new("UIStroke", fuseNum); t.Color = Color3.new(0, 0, 0); t.Thickness = 5
   t.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual end

-- PROGRESS IS IN THE TEXT AT EVERY STAGE. The banner should always answer "what now, and how far in am I".
local function baseText()
	if finished then return "\xF0\x9F\x92\xA5 The giant candy is cracked open -- nice blast!" end
	if not accepted then
		return "\xF0\x9F\x92\xA5 Talk to the Candy NPC to start -- follow the green arrows!"
	end
	-- Names the actual target: a GLOWING PAD, not "the giant candy". The pads are what you walk to.
	if carrying and armLeft then
		return ("\xE2\x9A\xA0 IT'S LIVE -- stand on a gold pad NOW!  %ds before it fizzles!"):format(armLeft)
	end
	if carrying then
		return ("\xF0\x9F\x92\xA5 Carry it to a glowing GOLD PAD by the giant candy and stand on it!  %d/%d")
			:format(placedCount, CHARGES)
	end
	local found = 0
	for _, c in ipairs(crystals) do if c.taken or c.placed then found += 1 end end
	if fuseLeft then
		return ("\xE2\x9A\xA0 ALL CHARGES ARMED -- BLOWING IN %d! GET CLEAR OF THE CANDY!"):format(fuseLeft)
	end
	if placedCount >= CHARGES then
		return "\xE2\x9A\xA0 All charges armed -- GET CLEAR!"
	end
	if found >= #crystals and #crystals > 0 and placedCount < CHARGES then
		return ("\xF0\x9F\x92\xA5 Carry each crystal to a glowing GOLD PAD by the giant candy:  %d/%d")
			:format(placedCount, CHARGES)
	end
	return ("\xF0\x9F\x92\xA5 Search the cliffs for glowing crystals -- press Take on each:  %d/%d")
		:format(placedCount, CHARGES)
end

refreshBanner = function() objLabel.Text = baseText() end

-- Only near island16, so it never talks over another island's objective.
task.spawn(function()
	while true do
		local vis = false
		if accepted and not finished and island then
			local hrp = hrpOf()
			local ref = candyPart and candyPart.Position
			if hrp and ref then vis = (hrp.Position - ref).Magnitude <= BANNER_RANGE end
		end
		objFrame.Visible = vis
		task.wait(0.4)
	end
end)

-- ============================================================================
-- THE SOCKET RING around the giant candy
-- ============================================================================
-- Computed, not marked. You named five parts "unstable" for the crystals; the ring is derived from the
-- candy's own footprint so it fits whatever size that model is, instead of needing five more markers that
-- would have to be re-placed every time the candy is resized.
local function buildSockets()
	if not candyPart then return end
	local cf, size
	if candyModel and candyModel:IsA("Model") then
		local ok, c, s = pcall(function() local a, b = candyModel:GetBoundingBox(); return a, b end)
		if ok and c then cf, size = c, s end
	end
	cf = cf or candyPart.CFrame
	size = size or candyPart.Size
	local R = math.max(size.X, size.Z) * 0.5 + RING_GAP
	local baseY = cf.Position.Y - size.Y * 0.5

	for i = 1, CHARGES do
		local a = (i - 1) / CHARGES * math.pi * 2
		local x, z = cf.Position.X + math.cos(a) * R, cf.Position.Z + math.sin(a) * R

		-- GROUND IT PROPERLY. baseY is the bottom of the candy's BOUNDING BOX, which on a model sunk into
		-- the island (or one with a stalk) is nowhere near the floor a player walks on -- the pads ended up
		-- buried or hovering. Raycast down from well above and take the real surface, ignoring the candy
		-- itself and anything this quest built, so a pad never lands on another pad.
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { candyModel, player.Character }
		local hit = Workspace:Raycast(Vector3.new(x, baseY + 60, z), Vector3.new(0, -260, 0), rp)
		local y = (hit and hit.Position.Y or baseY) + 0.4
		local pos = Vector3.new(x, y, z)

		local pad = Instance.new("Part")
		pad.Name = "ChargeSocket"
		pad.Shape = Enum.PartType.Cylinder
		pad.Size = Vector3.new(0.3, 6, 6)          -- 3.4 -> 6: a pad you can see you are stood on
		pad.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
		pad.Anchored = true; pad.CanCollide = false; pad.CanQuery = false; pad.CastShadow = false
		pad.Material = Enum.Material.Neon; pad.Color = GOLD; pad.Transparency = 0.35
		pad.Parent = Workspace
		TweenService:Create(pad, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.75 }):Play()

		-- A PILLAR OF LIGHT. A disc on the floor is invisible from more than a few studs away and from any
		-- angle above it -- which is exactly how you approach, carrying a crystal. The column is what makes
		-- the ring readable from across the island, and it is what answers "where do I put this".
		local beam = Instance.new("Part")
		beam.Name = "ChargeBeam"
		beam.Size = Vector3.new(2.4, 30, 2.4)
		beam.CFrame = CFrame.new(pos + Vector3.new(0, 15, 0))
		beam.Anchored = true; beam.CanCollide = false; beam.CanQuery = false; beam.CastShadow = false
		beam.Material = Enum.Material.Neon; beam.Color = GOLD; beam.Transparency = 0.72
		beam.Parent = Workspace
		TweenService:Create(beam, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.9 }):Play()

		-- ...and a label, so it says what it wants rather than just glowing.
		local bb = Instance.new("BillboardGui")
		bb.Name = "ChargeTag"
		bb.Size = UDim2.new(0, 190, 0, 46)
		bb.StudsOffset = Vector3.new(0, 5, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 260
		bb.Adornee = pad
		bb.Parent = pad
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.FredokaOne; lbl.TextScaled = true
		lbl.TextColor3 = Color3.new(1, 1, 1); lbl.Text = "PLACE HERE"
		lbl.Parent = bb
		local ls = Instance.new("UIStroke"); ls.Color = Color3.new(0, 0, 0); ls.Thickness = 3; ls.Parent = lbl
		Instance.new("UITextSizeConstraint", lbl).MaxTextSize = 20

		sockets[i] = { pos = pos, pad = pad, beam = beam, tag = bb, label = lbl, filled = false }
	end
	print(("[CandyMine] %d charge socket(s) ringed around '%s' (radius %.0f)"):format(CHARGES, candyPart.Name, R))
end

local function nextFreeSocket()
	for _, s in ipairs(sockets) do if not s.filled then return s end end
	return nil
end

-- The free socket NEAREST the player, and how far away it is.
--
-- ⚠ THIS REPLACED A CHECK AGAINST THE CANDY'S CENTRE, WHICH COULD NOT BE SATISFIED.
-- Placing used to fire when you got within PLACE_RANGE of candyPart.Position -- but the sockets ring the
-- candy at (its own radius + RING_GAP). On a genuinely giant candy the ring sits FURTHER OUT than the
-- range, so standing on a pad you were still "too far" and the charge never seated: the bigger the candy,
-- the more broken it got. Distance to the SOCKET is scale-independent -- stand on the pad, it goes in.
local function nearestFreeSocket(from)
	local best, bestD
	for _, s in ipairs(sockets) do
		if not s.filled then
			local d = (from - s.pos).Magnitude
			if not bestD or d < bestD then best, bestD = s, d end
		end
	end
	return best, bestD
end

-- ============================================================================
-- CARRY / PLACE
-- ============================================================================
-- THE LIVE ONE. Picking up the FINAL charge (three already seated) wakes it: red aura, the
-- fuse HUD becomes its clock, and ARM_SECONDS to sprint it onto a pad. Run out of clock and
-- it FIZZLES -- flies back to where it was found, relights pink, and the prompt re-arms.
-- A retry, never a fail: the finale gets a sprint without ever getting a death.
local function armCarry(c)
	if armLeft then return end
	task.spawn(function()
		-- NOT addAura: its glow shell is anchored and does not follow a moving part (its own
		-- comment says so) -- an armed aura would be left floating at the pickup spot while the
		-- crystal rides overhead. A Highlight and a light PARENTED to the part follow it anywhere.
		local live = Instance.new("Folder"); live.Name = "LiveGlow"; live.Parent = c.part
		local hl = Instance.new("Highlight")
		hl.FillColor = DANGER; hl.FillTransparency = 0.55
		hl.OutlineColor = Color3.new(1, 1, 1); hl.OutlineTransparency = 0.1
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = c.part; hl.Parent = live
		TweenService:Create(hl, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ FillTransparency = 0.85 }):Play()
		local lt = Instance.new("PointLight")
		lt.Color = DANGER; lt.Brightness = 2.4; lt.Range = 18; lt.Shadows = false
		lt.Parent = c.part; lt.Name = "LiveLight"
		fuseGui.Enabled = true
		if _G.NotifyCenter then pcall(function() _G.NotifyCenter.push({
			text = "\xE2\x9A\xA0 The last one's LIVE! Sprint it to a gold pad!", color = DANGER }) end) end
		for t = ARM_SECONDS, 1, -1 do
			if c.placed or finished or carrying ~= c then break end
			armLeft = t
			fuseNum.Text = tostring(t)
			fuseNum.TextColor3 = (t <= 5) and DANGER or GOLD
			fuseCap.Text = "IT'S LIVE -- GET IT TO A GOLD PAD!"
			fuseNum.Size = UDim2.new(0, 340, 0, 170)
			tween(fuseNum, 0.22, { Size = UDim2.new(0, 300, 0, 150) })
			refreshBanner()
			task.wait(1)
		end
		armLeft = nil
		live:Destroy()                                        -- the live glow ends with the sprint
		local ll = c.part:FindFirstChild("LiveLight"); if ll then ll:Destroy() end
		if c.placed or finished or carrying ~= c then refreshBanner(); return end   -- it made it (or /done took over)

		-- FIZZLE: back it goes. carrying is cleared FIRST so the carry loop stops pinning the
		-- part overhead and the fly-home tween owns it.
		fuseGui.Enabled = false
		carrying = nil
		clearAura(c.part)
		c.part.Anchored = true
		tween(c.part, 0.7, { CFrame = c.home }, Enum.EasingStyle.Quad)
		task.delay(0.75, function()
			if c.placed or finished then return end
			c.taken = false
			addAura(c.part, PINK)
			if c.prompt then c.prompt.Enabled = true end
		end)
		if _G.NotifyCenter then pcall(function() _G.NotifyCenter.push({
			text = "\xF0\x9F\x92\xA8 It fizzled and flew home! Grab it and RUN this time!", color = DANGER }) end) end
		refreshBanner()
	end)
end

local function pickUp(c)
	-- SAY WHY, don't just refuse. Grabbing a crystal before taking the job used to return silently, and an
	-- inert prompt is indistinguishable from a broken one -- especially on this island, where the crystals
	-- are glowing at you the whole time. _G.questLocked is DoneCommand's shared banner (rate-limited, so a
	-- held prompt key cannot stack it), and it degrades to nothing if that script is missing.
	if not accepted and not finished then
		if _G.questLocked then pcall(_G.questLocked, "the Candy Mine job") end
		return
	end
	if carrying or c.taken or c.placed or finished then return end
	c.taken = true
	carrying = c
	clearAura(c.part)
	if c.prompt then c.prompt.Enabled = false end
	c.part.CanCollide = false
	playSound(SOUND_PICKUP, 0.6)
	refreshBanner()
	-- Point at the PAD, not the candy. "Carry it to the giant candy" is not an instruction you can follow
	-- when the candy is the size of a building and the thing you actually need is a specific spot beside it.
	local hrp = hrpOf()
	local s = hrp and select(1, nearestFreeSocket(hrp.Position)) or nextFreeSocket()
	local aim = (s and s.pos) or (candyPart and candyPart.Position)
	if _G.guideTrailTo and aim then pcall(function() _G.guideTrailTo(aim) end) end
	-- three seated + this one in hand = the last charge. It wakes up.
	if placedCount >= CHARGES - 1 then armCarry(c) end
end

-- `c` defaults to whatever is in your hands. It is an explicit parameter so /done can seat a crystal
-- WITHOUT routing it through `carrying` -- the carry loop below pins the carried part above the player
-- every frame, so a scripted placement that went via `carrying` would yank the crystal to your head first
-- and then fly it to the socket. `animate` flies it in over 0.4s instead of snapping, which is what makes
-- /done read as the charges being set rather than five crystals teleporting.
local function placeCharge(s, c, animate)
	c = c or carrying
	if not c then return end
	s = s or nextFreeSocket()
	if not s or s.filled then return end

	if carrying == c then carrying = nil end
	c.placed = true
	s.filled = true
	placedCount += 1
	-- a LIVE charge that made it: its sprint clock stops here (startFuse takes the HUD next)
	if armLeft then armLeft = nil; fuseGui.Enabled = false end

	c.part.Anchored = true
	local seated = CFrame.new(s.pos + Vector3.new(0, 1.6, 0))
	if animate then
		tween(c.part, 0.4, { CFrame = seated }, Enum.EasingStyle.Quad)
	else
		c.part.CFrame = seated
	end
	addAura(c.part, DANGER)          -- re-lit at the socket: an armed charge, not a lost one

	-- The socket stops advertising itself. Leaving five "PLACE HERE" columns up while three are already
	-- armed is the same failure as the banner that keeps telling you to go talk to the NPC.
	if s.pad then s.pad.Color = DANGER end
	if s.beam then s.beam:Destroy(); s.beam = nil end
	if s.label then s.label.Text = "ARMED"; s.label.TextColor3 = DANGER end

	playSound(SOUND_PLACE, 0.7)
	refreshBanner()
	print(("[CandyMine] charge %d/%d placed"):format(placedCount, CHARGES))

	-- ARMING IS THE TRIGGER. There is no detonator to walk back to and press -- the moment the last
	-- charge is seated the shot is live and the clock starts. task.defer so the fuse begins on the
	-- next step rather than inside the placement that caused it (/done seats all four in a row, and
	-- starting mid-loop would run the countdown while charges were still flying to their sockets).
	if placedCount >= CHARGES and startFuse then task.defer(startFuse) end
end

-- The carried crystal rides above the player -- no welds, no physics, so it cannot shove anyone.
RunService.Heartbeat:Connect(function()
	local c = carrying
	if not c or not c.part or not c.part.Parent then return end
	local hrp = hrpOf()
	if not hrp then return end
	c.part.Anchored = true
	c.part.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 4.2, 0))
		* CFrame.Angles(0, os.clock() * 1.6, 0)

	-- Stand on (or near) any free pad and the charge seats itself. Measured to the SOCKET, so it works the
	-- same whether the candy is 10 studs across or 200.
	local s, d = nearestFreeSocket(hrp.Position)
	if s and d and d <= PLACE_RANGE then placeCharge(s, c) end
end)

-- ============================================================================
-- THE BLAST
-- ============================================================================
-- ============================================================================
-- THE BLAST
-- ============================================================================
-- Built as a SEQUENCE, because that is the whole difference between an explosion and a puff. Nothing here
-- lands at the same instant as anything else:
--
--   FUSE      the pads flash faster and faster, the ground trembles harder -- you know it is coming
--   FLASH     one frame of white, before any geometry moves. The eye reads this as the detonation
--   CORE      a fireball that overshoots and collapses
--   WAVES     three shockwave rings at different speeds, so it does not read as one flat disc
--   SHELL     the candy splits, hinges outward and reveals a lit core
--   DEBRIS    chunks on real arcs -- up fast, over, then down past the floor
--   SETTLE    smoke and embers hang, the shake decays, the light fades
--
-- ALL COSMETIC AND ALL ANCHORED. Not one part here collides or is query-able, so a player stood on a pad
-- at the moment it goes cannot be launched, trapped or killed by any of it.
local function shakeCamera(amount, seconds)
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if not hum then return end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < seconds do
			local k = 1 - (os.clock() - t0) / seconds        -- decays to nothing
			local a = amount * k * k                          -- squared: a hard hit that falls away fast
			hum.CameraOffset = Vector3.new(
				(math.random() - 0.5) * 2 * a,
				(math.random() - 0.5) * 2 * a,
				(math.random() - 0.5) * a)
			RunService.RenderStepped:Wait()
		end
		hum.CameraOffset = Vector3.zero
	end)
end

-- One full-screen flash. Its own ScreenGui at a high DisplayOrder so no HUD element draws over it.
local function screenFlash(colour, hold, fade)
	local g = Instance.new("ScreenGui")
	g.Name = "BlastFlash"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 200
	g.Parent = PlayerGui
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = colour; f.BackgroundTransparency = 0
	f.BorderSizePixel = 0; f.Parent = g
	task.delay(hold, function()
		tween(f, fade, { BackgroundTransparency = 1 })
		Debris:AddItem(g, fade + 0.2)
	end)
end

local function mkFx(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do p[k] = v end
	p.Parent = Workspace
	return p
end

-- ============================================================================
-- WHAT IS INSIDE: THE CANDY CORE
-- ============================================================================
-- The payoff. Cracking something open is only worth doing if there is something in it -- without this the
-- finale is a giant candy that got slightly further away from itself.
--
-- A faceted geode heart, two counter-rotating rings of candy gems, and four light shafts. It is built
-- AFTER the shell has begun to open, rises out of the wreckage, and then STAYS -- lit, turning, visible
-- from across the island. The island keeps a landmark that says "this one is done".
--
-- ONE RenderStepped drives the whole thing (spin + both orbits). Per-object loops would be sixteen loops
-- for one ornament, and it self-cancels the moment the model is gone.
local function buildCandyCore(origin)
	local folder = Instance.new("Folder")
	folder.Name = "CandyCore"
	folder.Parent = Workspace

	local function piece(props)
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		p.Material = Enum.Material.Neon
		for k, v in pairs(props) do p[k] = v end
		p.Parent = folder
		return p
	end

	local centre = origin + Vector3.new(0, 9, 0)

	-- ⚠ THE SHELL IS GLASS, NOT NEON, AND IT IS THE POINT.
	-- The first version made this a bright neon sphere with a second neon sphere inside it and a
	-- brightness-8 light in the middle. At that intensity there is nothing to look AT -- a glowing ball is
	-- a light source, and the eye reads it as one flat bloom. You cannot see a prize inside a lamp.
	--
	-- So the outer shell is CLEAR: Glass, barely tinted, no emission of its own. It reads as a case, and
	-- because you can see through it the thing inside is what your eye lands on. Everything that used to
	-- be doing the work by being bright is now doing it by being SEEN.
	local outer = piece({ Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1),
		Material = Enum.Material.Glass, Color = Color3.fromRGB(255, 225, 240),
		Transparency = 0.86, Reflectance = 0.25, CFrame = CFrame.new(centre) })

	-- THE PRIZE ITSELF: a wrapped candy, turning slowly inside the case. A shape you can name beats a
	-- glow you cannot -- "there's a sweet in there" is the reveal; "there's a light in there" is not.
	local prize = Instance.new("Model"); prize.Name = "Prize"; prize.Parent = folder

	local body = Instance.new("Part")
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(3.4, 2.6, 2.6)
	body.Color = PINK
	body.Material = Enum.Material.SmoothPlastic   -- lit BY the scene, not self-lit
	body.Anchored = true; body.CanCollide = false; body.CanQuery = false; body.CastShadow = false
	body.Parent = prize
	prize.PrimaryPart = body
	do -- a candy stripe, so it is obviously a sweet and not a pill
		local stripe = Instance.new("Part")
		stripe.Shape = Enum.PartType.Cylinder
		stripe.Size = Vector3.new(3.5, 2.7, 1.0)
		stripe.Color = Color3.fromRGB(255, 250, 245)
		stripe.Material = Enum.Material.SmoothPlastic
		stripe.Anchored = true; stripe.CanCollide = false; stripe.CanQuery = false; stripe.CastShadow = false
		stripe.Parent = prize
	end
	-- the two wrapper twists
	local twists = {}
	for i = -1, 1, 2 do
		local w = Instance.new("Part")
		w.Shape = Enum.PartType.Ball
		w.Size = Vector3.new(1.5, 1.9, 1.9)
		w.Color = GOLD
		w.Material = Enum.Material.SmoothPlastic
		w.Anchored = true; w.CanCollide = false; w.CanQuery = false; w.CastShadow = false
		w.Parent = prize
		twists[#twists + 1] = { part = w, side = i }
	end

	-- A SOFT light, well down from the old brightness-8/range-70 floodlight. Enough to pick the prize out
	-- of the wreckage; not enough to become the thing you are looking at.
	local lt = Instance.new("PointLight")
	lt.Color = Color3.fromRGB(255, 220, 235); lt.Brightness = 0; lt.Range = 34; lt.Shadows = false
	lt.Parent = body

	-- TWO thin shafts, not four fat ones, and much fainter -- a hint of light leaking from the case so it
	-- still reads from across the island, without washing out the case it is leaking from.
	local shafts = {}
	for i = 1, 2 do
		local a = (i / 2) * math.pi * 2
		shafts[i] = piece({ Size = Vector3.new(0.8, 1, 0.8), Color = PINK, Transparency = 0.88,
			CFrame = CFrame.new(centre) * CFrame.Angles(math.rad(10) * math.cos(a), a, math.rad(10) * math.sin(a)) })
	end

	-- TWO COUNTER-ROTATING RINGS of candy gems. Counter-rotation is what stops it reading as one rigid
	-- object that is simply spinning.
	local gems = {}
	for ring = 1, 2 do
		local count = (ring == 1) and 9 or 6
		for i = 1, count do
			local g = piece({
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.5, 1.5, 1.5) * ((ring == 1) and 1 or 0.75),
				Color = (i % 2 == 0) and PINK or GOLD,
				Transparency = 0.1,
				CFrame = CFrame.new(centre),
			})
			gems[#gems + 1] = {
				part = g, ring = ring,
				phase = (i - 1) / count * math.pi * 2,
				radius = (ring == 1) and 11 or 7.5,
				tilt = (ring == 1) and math.rad(14) or math.rad(72),
				speed = (ring == 1) and 0.85 or -1.25,
			}
		end
	end

	-- RISE out of the wreckage, rather than appearing finished. The case opens up around the prize.
	tween(outer, 1.3, { Size = Vector3.new(11, 11, 11) }, Enum.EasingStyle.Back)
	tween(lt, 1.3, { Brightness = 1.6 })
	for _, s in ipairs(shafts) do
		tween(s, 1.4, { Size = Vector3.new(0.8, 34, 0.8) }, Enum.EasingStyle.Quint)
	end

	-- breathing, forever -- on the GLASS only, and gently. The old version pulsed the light to brightness
	-- 8, which is what made the whole thing strobe white and hid the prize on every up-beat.
	task.delay(1.4, function()
		if not outer.Parent then return end
		TweenService:Create(outer, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.93, Reflectance = 0.4 }):Play()
		TweenService:Create(lt, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Brightness = 2.4 }):Play()
	end)

	-- sparkle shed off the case, so the air around it is not dead. Rate well down from 22 -- dense sparkle
	-- in front of a glass case is just a second thing obscuring the prize.
	local att = Instance.new("Attachment"); att.Parent = outer
	local sp = Instance.new("ParticleEmitter")
	sp.Rate = 9
	sp.Lifetime = NumberRange.new(1.2, 2.2)
	sp.Speed = NumberRange.new(3, 7)
	sp.SpreadAngle = Vector2.new(180, 180)
	sp.Acceleration = Vector3.new(0, 4, 0)
	sp.Drag = 1.4
	sp.LightEmission = 1
	sp.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(1, 0) })
	sp.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.05), NumberSequenceKeypoint.new(1, 1) })
	sp.Color = ColorSequence.new(GOLD, PINK)
	sp.Parent = att

	-- the one loop
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not folder.Parent or not body.Parent then conn:Disconnect(); return end
		local now = os.clock()

		-- THE PRIZE turns and bobs inside the case -- slowly, so it can be read rather than watched go by.
		local bob = math.sin(now * 1.1) * 0.5
		local prizeCF = CFrame.new(centre + Vector3.new(0, bob, 0))
			* CFrame.Angles(math.rad(14), now * 0.55, 0)
		body.CFrame = prizeCF
		-- the stripe rides the body; the twists sit on its ends
		for _, d in ipairs(prize:GetChildren()) do
			if d ~= body and d:IsA("BasePart") and d.Shape == Enum.PartType.Cylinder then
				d.CFrame = prizeCF
			end
		end
		for _, t in ipairs(twists) do
			t.part.CFrame = prizeCF * CFrame.new(t.side * 2.3, 0, 0)
		end

		outer.CFrame = CFrame.new(centre) * CFrame.Angles(now * 0.12, now * -0.18, 0)
		for i, s in ipairs(shafts) do
			local a = (i / 2) * math.pi * 2 + now * 0.3
			s.CFrame = CFrame.new(centre + Vector3.new(0, 16, 0))
				* CFrame.Angles(math.rad(10) * math.cos(a), a, math.rad(10) * math.sin(a))
		end
		for _, g in ipairs(gems) do
			local a = g.phase + now * g.speed
			local flat = Vector3.new(math.cos(a) * g.radius, 0, math.sin(a) * g.radius)
			local tilted = CFrame.Angles(g.tilt, 0, 0):VectorToWorldSpace(flat)
			g.part.CFrame = CFrame.new(centre + tilted) * CFrame.Angles(now * 1.4, now * 1.1, 0)
		end
	end)

	print("[CandyMine] candy core revealed")
	return folder
end

-- ============================================================================
-- THE END OF THE REALM
-- ============================================================================
-- Island 16 is the last thing in Candy Realm, so cracking the giant candy is not "a quest finished", it is
-- the credits. It gets a sequence of its own after the core has risen.
--
-- ⚠ IT PAYS OUTSIDE THE ISLAND-TASK LADDER, ON PURPOSE.
-- The obvious move was to add `candymine` to CrateTokens.ISLAND_TASK alongside the other twelve. That
-- table's header spends a paragraph explaining that its total is EXACTLY 750 -- "5 spins on the 100
-- Starter crate plus 1 on the 250 Premium" -- and that it must stay in step with the Food realm's copy.
-- Dropping a thirteenth rung in would silently break a number three files and another realm are built
-- around, to save writing four lines here. So the finale pays its own one-off coin reward through
-- CoinEvent, which is how every other Candy quest pays coins, and the 750 ladder is left alone.
local FINALE_COINS = 2500

local function payCoins(n)
	local ce = ReplicatedStorage:FindFirstChild("CoinEvent") or _G.CoinEvent
	if not ce then
		warn("[CandyMine] CoinEvent missing -- finale reward not paid")
		return false
	end
	local ok = pcall(function() ce:FireServer(n) end)
	if not ok then warn("[CandyMine] CoinEvent:FireServer failed -- finale reward not paid") end
	return ok
end

-- A firework over the island: shell rises, bursts into a coloured sphere of trails, fades.
local function firework(from, colour)
	local shell = Instance.new("Part")
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(2, 2, 2)
	shell.CFrame = CFrame.new(from)
	shell.Anchored = true; shell.CanCollide = false; shell.CanQuery = false; shell.CastShadow = false
	shell.Material = Enum.Material.Neon; shell.Color = colour
	shell.Parent = Workspace

	local rise = 70 + math.random() * 50
	tween(shell, 1.0, { CFrame = CFrame.new(from + Vector3.new(
		(math.random() - 0.5) * 40, rise, (math.random() - 0.5) * 40)) }, Enum.EasingStyle.Quad)

	task.delay(1.0, function()
		local at = shell.CFrame.Position
		shell:Destroy()
		-- the burst: trails on radial arcs, not a puff of particles -- the streaks are what read as a firework
		for i = 1, 18 do
			local a = (i / 18) * math.pi * 2
			local tilt = (math.random() - 0.5) * 1.2
			local sp = Instance.new("Part")
			sp.Shape = Enum.PartType.Ball
			sp.Size = Vector3.new(1.1, 1.1, 1.1)
			sp.CFrame = CFrame.new(at)
			sp.Anchored = true; sp.CanCollide = false; sp.CanQuery = false; sp.CastShadow = false
			sp.Material = Enum.Material.Neon; sp.Color = colour
			sp.Parent = Workspace
			local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.4, 0); a0.Parent = sp
			local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.4, 0); a1.Parent = sp
			local tr = Instance.new("Trail")
			tr.Attachment0 = a0; tr.Attachment1 = a1
			tr.Lifetime = 0.6; tr.LightEmission = 1; tr.FaceCamera = true
			tr.Color = ColorSequence.new(colour, Color3.new(1, 1, 1))
			tr.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			tr.Parent = sp
			tween(sp, 1.3, {
				CFrame = CFrame.new(at + Vector3.new(
					math.cos(a) * 34, math.sin(tilt) * 30 - 14, math.sin(a) * 34)),
				Transparency = 1,
			}, Enum.EasingStyle.Quad)
			Debris:AddItem(sp, 1.6)
		end
	end)
end

-- ============================================================================
-- THE CANDY STORM -- and out through it into the next realm
-- ============================================================================
-- The realm does not end on a banner, it ends by coming apart. The candy you cracked open takes the whole
-- island with it: the sky goes sugar-pink, the air fills with candy tearing past, and it lifts you off the
-- ground and carries you out.
--
-- ⚠ THIS TELEPORTS THE PLAYER, which is the one genuinely irreversible thing this quest does. Three guards
-- around that:
--   * it only ever runs from crackOpen, which is the end of the realm's last quest;
--   * every change it makes to Lighting is SNAPSHOTTED first and restored if the teleport fails, so a
--     failed exit leaves a playable island rather than a pink one you cannot see through;
--   * a 12s watchdog gives the player back their controls if the teleport neither succeeds nor errors.
--     A cinematic that locks you in place forever because a remote did not answer is worse than no
--     cinematic at all.
local STORM_BUILD   = 4.0    -- seconds of the storm gathering before it takes you
local STORM_LIFT    = 2.4    -- seconds being carried up and spun
local EXIT_TIMEOUT  = 12     -- seconds before we assume the teleport is not coming and hand back control

local function candyStorm(origin, onExit)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildWhichIsA("Humanoid")

	-- SNAPSHOT what we are about to change, so a failed exit is recoverable.
	local snap = {
		amb  = Lighting.Ambient,
		out  = Lighting.OutdoorAmbient,
		fogC = Lighting.FogColor,
		fogE = Lighting.FogEnd,
		fogS = Lighting.FogStart,
		bri  = Lighting.Brightness,
		walk = hum and hum.WalkSpeed or 16,
		jump = hum and hum.JumpPower or 50,
		auto = hrp and hrp.Anchored or false,
	}
	-- claim the sky for the finale (SkyByAltitude pins Brightness and OutdoorAmbient every frame)
	do
		local claims = _G.questSkyClaims; if not claims then claims = {}; _G.questSkyClaims = claims end
		claims.candymine = true
	end

	local restored = false
	local function restore()
		if restored then return end
		restored = true
		if _G.questSkyClaims then _G.questSkyClaims.candymine = nil end
		pcall(function()
			Lighting.Ambient = snap.amb; Lighting.OutdoorAmbient = snap.out
			Lighting.FogColor = snap.fogC; Lighting.FogEnd = snap.fogE; Lighting.FogStart = snap.fogS
			Lighting.Brightness = snap.bri
		end)
		if hum then hum.WalkSpeed = snap.walk; hum.JumpPower = snap.jump end
		if hrp then hrp.Anchored = snap.auto end
	end

	task.spawn(function()
		-- ---- 1) THE SKY TURNS ----------------------------------------------------------------------
		tween(Lighting, STORM_BUILD, {
			Ambient        = Color3.fromRGB(120, 60, 95),
			OutdoorAmbient = Color3.fromRGB(190, 110, 155),
			FogColor       = Color3.fromRGB(255, 170, 215),
			FogEnd         = 220,
			FogStart       = 20,
			Brightness     = 0.8,
		})

		-- ---- 2) CANDY IN THE AIR -------------------------------------------------------------------
		-- Spawned around the PLAYER, not the candy: the storm is happening to you. Each piece screams
		-- past on a straight line and is recycled by Debris -- no pooling, because this lasts six seconds
		-- and then the place stops existing for you.
		local blowing = true
		task.spawn(function()
			while blowing do
				local h = hrpOf()
				if h then
					for _ = 1, 3 do
						local a = math.random() * math.pi * 2
						local r = 70 + math.random() * 40
						local from = h.Position + Vector3.new(math.cos(a) * r,
							(math.random() - 0.3) * 50, math.sin(a) * r)
						local sz = 0.8 + math.random() * 2.4
						local p = Instance.new("Part")
						p.Size = Vector3.new(sz, sz * 1.6, sz)
						p.CFrame = CFrame.new(from)
						p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
						p.Material = Enum.Material.SmoothPlastic
						p.Color = ({ PINK, GOLD, Color3.fromRGB(255, 250, 245),
							Color3.fromRGB(150, 230, 255) })[math.random(1, 4)]
						p.Parent = Workspace
						-- straight THROUGH the player's column, not toward them -- debris in a wind does
						-- not home in, and anything that homes in reads as an attack instead of weather
						local through = h.Position + Vector3.new(math.cos(a + math.pi) * r * 1.2,
							(math.random() - 0.5) * 30, math.sin(a + math.pi) * r * 1.2)
						tween(p, 0.5 + math.random() * 0.35, {
							CFrame = CFrame.new(through) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
						}, Enum.EasingStyle.Linear)
						Debris:AddItem(p, 1.0)
					end
				end
				task.wait(0.06)
			end
		end)

		-- the shake ramps the whole time it is gathering
		for i = 1, 8 do
			shakeCamera(0.2 + i * 0.12, 0.55)
			task.wait(STORM_BUILD / 8)
		end

		-- ---- 3) IT TAKES YOU -----------------------------------------------------------------------
		hrp = hrpOf()
		if hum then hum.WalkSpeed = 0; hum.JumpPower = 0 end
		if hrp then
			hrp.Anchored = true      -- anchored, so nothing about this is a real fall the physics can fight
			local start = hrp.CFrame
			local t0 = os.clock()
			task.spawn(function()
				while os.clock() - t0 < STORM_LIFT and hrp and hrp.Parent do
					local k = (os.clock() - t0) / STORM_LIFT
					hrp.CFrame = start
						* CFrame.new(0, k * k * 90, 0)                    -- accelerating upward
						* CFrame.Angles(0, k * 14, math.rad(k * 25))      -- spun, and tipped as it goes
					RunService.RenderStepped:Wait()
				end
			end)
		end
		shakeCamera(3.0, STORM_LIFT)

		task.wait(STORM_LIFT * 0.55)
		-- the white-out is what "dying into the next realm" actually looks like: it takes the screen
		-- BEFORE the teleport, so the loading screen arrives behind a wash rather than a hard cut
		screenFlash(Color3.fromRGB(255, 235, 245), STORM_LIFT * 0.45 + 1.5, 0.8)

		task.wait(STORM_LIFT * 0.45)
		blowing = false

		-- ---- 4) OUT ---------------------------------------------------------------------------------
		if onExit then onExit(restore) end

		-- WATCHDOG. If the teleport neither fires nor errors, give the player their island back.
		task.delay(EXIT_TIMEOUT, function()
			if restored then return end
			warn("[CandyMine] exit did not happen within " .. EXIT_TIMEOUT .. "s -- restoring control")
			restore()
		end)
	end)
end

local function realmFinale(origin)
	task.spawn(function()
		-- 1) PAY FIRST. Everything below is decoration; the reward must not depend on it surviving.
		local paid = payCoins(FINALE_COINS)

		-- 2) The card. HERO priority so it outranks the objective and any event -- this is the one banner in
		-- the realm that has earned the right to interrupt.
		local NC = _G.NotifyCenter
		if NC and NC.push then
			pcall(function()
				NC.push({
					top      = "\xF0\x9F\x8D\xAC CANDY REALM COMPLETE",
					text     = paid and ("You cracked the Giant Candy!  +%d coins"):format(FINALE_COINS)
						or "You cracked the Giant Candy!",
					color    = GOLD,
					priority = (NC.PRIORITY and NC.PRIORITY.ISLAND) or 100,
					duration = 8,
				})
			end)
		end

		-- 3) Fireworks over the island, in waves rather than all at once -- a volley reads as a celebration,
		-- a single burst reads as a bug. THREE waves, not six: this is the triumph beat, and it has to give
		-- way to the storm while it still feels like a high point rather than outstaying it.
		local cols = { GOLD, PINK, Color3.fromRGB(120, 220, 255), Color3.fromRGB(150, 255, 170) }
		for _ = 1, 3 do
			for _ = 1, 3 do
				firework(origin + Vector3.new(
					(math.random() - 0.5) * 90, 10, (math.random() - 0.5) * 90),
					cols[math.random(1, #cols)])
			end
			task.wait(0.75)
		end

		print(("[CandyMine] REALM FINALE -- %s"):format(paid and ("paid " .. FINALE_COINS .. " coins") or "coin payout FAILED"))

		-- 4) ...and then it turns. The celebration is the last calm moment; the storm takes it from there.
		if NC and NC.push then
			pcall(function()
				NC.push({
					top      = "\xE2\x9A\xA0 THE CANDY STORM",
					text     = "The island is coming apart -- hold on!",
					color    = PINK,
					priority = (NC.PRIORITY and NC.PRIORITY.ISLAND) or 100,
					duration = 6,
				})
			end)
		end

		candyStorm(origin, function(restore)
			-- OUT INTO THE NEXT REALM. DinoRealmTeleport.server.lua listens on this remote and takes it
			-- from here (it handles the friend-instance lookup, the TeleportOptions and the failure path).
			-- Fired with NO arguments -- intent only -- which is exactly the contract DinoPortal.client uses,
			-- so this exit is the same one the portal has always taken and needs no new server code.
			local ev = ReplicatedStorage:FindFirstChild("DinoRealmEnterEvent")
			if not ev then
				warn("[CandyMine] DinoRealmEnterEvent missing -- cannot leave the realm."
					.. " Is DinoRealmTeleport.server.lua running? Restoring control.")
				restore()
				return
			end
			local ok = pcall(function() ev:FireServer() end)
			if not ok then
				warn("[CandyMine] the realm exit failed to fire -- restoring control")
				restore()
				return
			end
			print("[CandyMine] realm exit fired -> Dino Realm")
		end)
	end)
end

local function crackOpen()
	if finished then return end
	finished = true

	task.spawn(function()
		local origin = candyPart and candyPart.Position or Vector3.new()

		-- ---- FUSE -------------------------------------------------------------------------------------
		-- Accelerating: 0.26s between flashes down to 0.08s, with the tremble growing to match. An even
		-- rhythm reads as a countdown; an accelerating one reads as something about to fail.
		for round = 1, 3 do
			for _, s in ipairs(sockets) do
				if s.pad then
					s.pad.Color = Color3.new(1, 1, 1)
					s.pad.Transparency = 0
					tween(s.pad, 0.14, { Transparency = 0.55 })
				end
			end
			shakeCamera(0.25 * round, 0.3)
			task.wait(0.30 - round * 0.07)
		end
		task.wait(0.12)

		playSound(SOUND_BOOM, 1)

		-- ---- FLASH ------------------------------------------------------------------------------------
		-- BEFORE anything moves. The white frame is what the eye reads as the detonation; the geometry
		-- underneath is then already mid-flight when vision comes back, which is why it feels instant.
		gloom.Enabled = false                       -- the blast IS the light coming back
		screenFlash(Color3.new(1, 1, 1), 0.05, 0.5)
		shakeCamera(2.2, 1.5)

		-- THE BLAST CAN TOSS YOU -- harmlessly, and only if you ignored ten seconds of a HUD reading
		-- TOO CLOSE. Comedy, not damage: a big up-and-away fling with a tumble, nothing solid touches
		-- you (the blast geometry stays CanCollide=false as documented below), and Roblox has no fall
		-- damage. The countdown finally means something at point-blank.
		do
			local lhrp = hrpOf()
			if lhrp and (lhrp.Position - origin).Magnitude <= LAUNCH_RANGE then
				local fling = Vector3.new(lhrp.Position.X - origin.X, 0, lhrp.Position.Z - origin.Z)
				local dir = (fling.Magnitude > 1) and fling.Unit or Vector3.new(0, 0, 1)
				lhrp.AssemblyLinearVelocity = dir * 70 + Vector3.new(0, 95, 0)
				lhrp.AssemblyAngularVelocity = Vector3.new(8, 12, 6)
				if _G.NotifyCenter then pcall(function() _G.NotifyCenter.push({
					text = "\xF0\x9F\x92\xA5 THAT'S why we said get clear!", color = GOLD }) end) end
			end
		end

		local flashLight = Instance.new("PointLight")
		flashLight.Color = GOLD; flashLight.Brightness = 14; flashLight.Range = 150; flashLight.Shadows = false
		local lightHost = mkFx({ Size = Vector3.new(1, 1, 1), Transparency = 1, CFrame = CFrame.new(origin) })
		flashLight.Parent = lightHost
		tween(flashLight, 1.4, { Brightness = 0, Range = 30 })
		Debris:AddItem(lightHost, 1.8)

		-- ---- CORE -------------------------------------------------------------------------------------
		-- Overshoots then collapses, rather than growing to a size and stopping. Fireballs do not stop.
		local core = mkFx({ Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4),
			Color = Color3.fromRGB(255, 255, 235), Transparency = 0, CFrame = CFrame.new(origin) })
		tween(core, 0.22, { Size = Vector3.new(46, 46, 46), Color = GOLD }, Enum.EasingStyle.Quint)
		task.delay(0.22, function()
			tween(core, 0.7, { Size = Vector3.new(26, 26, 26), Transparency = 1, Color = DANGER })
		end)
		Debris:AddItem(core, 1.2)

		-- a second, slower shell of colour behind it, so the fireball has depth instead of one flat edge
		local halo = mkFx({ Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6),
			Color = PINK, Transparency = 0.35, CFrame = CFrame.new(origin) })
		tween(halo, 0.9, { Size = Vector3.new(78, 78, 78), Transparency = 1 })
		Debris:AddItem(halo, 1.2)

		-- ---- WAVES ------------------------------------------------------------------------------------
		-- Three rings, staggered and at different speeds. One ring reads as a decal; three read as a
		-- pressure front, because the gaps between them are what sell the speed.
		for i = 1, 3 do
			task.delay((i - 1) * 0.11, function()
				local ring = mkFx({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 8, 8),
					Color = (i == 2) and PINK or GOLD, Transparency = 0.05,
					CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90)) })
				tween(ring, 0.9 + i * 0.25, {
					Size = Vector3.new(0.6, 150 + i * 45, 150 + i * 45), Transparency = 1,
				}, Enum.EasingStyle.Quint)
				Debris:AddItem(ring, 1.8)
			end)
		end

		-- a vertical column punching up out of the crater -- the read from a distance
		local column = mkFx({ Size = Vector3.new(14, 8, 14), Color = GOLD, Transparency = 0.25,
			CFrame = CFrame.new(origin + Vector3.new(0, 4, 0)) })
		tween(column, 1.1, { Size = Vector3.new(22, 130, 22),
			CFrame = CFrame.new(origin + Vector3.new(0, 65, 0)), Transparency = 1 })
		Debris:AddItem(column, 1.4)

		-- ---- SMOKE + EMBERS ---------------------------------------------------------------------------
		-- Emitters, not parts: they self-animate, so the settle costs nothing per frame.
		local plume = mkFx({ Size = Vector3.new(2, 2, 2), Transparency = 1, CFrame = CFrame.new(origin) })
		local att = Instance.new("Attachment"); att.Parent = plume

		local smoke = Instance.new("ParticleEmitter")
		smoke.Lifetime = NumberRange.new(2.2, 4.0)
		smoke.Rate = 0
		smoke.Speed = NumberRange.new(18, 40)
		smoke.SpreadAngle = Vector2.new(180, 180)
		smoke.Acceleration = Vector3.new(0, 6, 0)
		smoke.Drag = 2.2
		smoke.Rotation = NumberRange.new(0, 360)
		smoke.RotSpeed = NumberRange.new(-60, 60)
		smoke.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 26) })
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		smoke.Color = ColorSequence.new(Color3.fromRGB(90, 70, 80), Color3.fromRGB(180, 160, 170))
		smoke.Parent = att
		smoke:Emit(60)

		local sparks = Instance.new("ParticleEmitter")
		sparks.Lifetime = NumberRange.new(1.0, 2.2)
		sparks.Rate = 0
		sparks.Speed = NumberRange.new(45, 95)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Acceleration = Vector3.new(0, -60, 0)      -- they arc and fall, they do not drift
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
		sparks.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.2),
			NumberSequenceKeypoint.new(1, 1) })
		sparks.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 210)),
			ColorSequenceKeypoint.new(0.5, GOLD),
			ColorSequenceKeypoint.new(1, PINK) })
		sparks.Parent = att
		sparks:Emit(150)
		Debris:AddItem(plume, 6)

		-- ---- DEBRIS -----------------------------------------------------------------------------------
		-- Two tweens per chunk, not one: UP-AND-OUT fast, then DOWN past the floor under a slower fall.
		-- A single tween to the end point draws a straight line, and a straight line does not read as
		-- thrown. The arc is the whole trick.
		for i = 1, 40 do
			local a = math.random() * math.pi * 2
			local out = 16 + math.random() * 34
			local up = 14 + math.random() * 26
			local sz = 0.7 + math.random() * 2.2
			local sh = mkFx({
				Size = Vector3.new(sz, sz * (0.6 + math.random() * 0.8), sz),
				Material = Enum.Material.SmoothPlastic,
				Color = (i % 3 == 0) and GOLD or ((i % 3 == 1) and PINK or Color3.fromRGB(255, 245, 235)),
				Transparency = 0,
				CFrame = CFrame.new(origin + Vector3.new(math.cos(a) * 2, 2, math.sin(a) * 2)),
			})
			local apex = origin + Vector3.new(math.cos(a) * out * 0.6, up, math.sin(a) * out * 0.6)
			local land = origin + Vector3.new(math.cos(a) * out, -26, math.sin(a) * out)
			local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
			tween(sh, 0.45, { CFrame = CFrame.new(apex) * spin }, Enum.EasingStyle.Quad)
			task.delay(0.45, function()
				if sh.Parent then
					tween(sh, 1.0, { CFrame = CFrame.new(land) * spin * spin, Transparency = 1 },
						Enum.EasingStyle.Quad)
				end
			end)
			Debris:AddItem(sh, 1.8)
		end

		-- ---- SHELL: THE CANDY ACTUALLY OPENS ----------------------------------------------------------
		-- Each part hinges AWAY from the centre and tips over as it goes, instead of sliding out flat --
		-- a shell breaking apart rather than a model being scaled up. Staggered by distance from the
		-- core, so the break travels outward through it.
		local host = candyModel or candyPart
		local parts = {}
		if host:IsA("BasePart") then parts[1] = host
		else for _, d in ipairs(host:GetDescendants()) do if d:IsA("BasePart") then parts[#parts + 1] = d end end end
		for _, p in ipairs(parts) do
			if p.Name ~= "ChargeSocket" and p.Name ~= "ChargeBeam" and not p:FindFirstAncestorOfClass("Tool") then
				local away = (p.Position - origin)
				local dist = away.Magnitude
				away = (dist > 0.1) and away.Unit or Vector3.new(0, 1, 0)
				p.Anchored = true
				p.CanCollide = false            -- nothing that just exploded should still be solid
				task.delay(math.min(dist, 30) * 0.006, function()
					if not p.Parent then return end
					tween(p, 1.6, {
						CFrame = p.CFrame + away * (9 + math.random() * 5) + Vector3.new(0, 2.5, 0)
							* CFrame.Angles((math.random() - 0.5) * 1.2, (math.random() - 0.5) * 1.2,
								(math.random() - 0.5) * 1.2),
						Transparency = 0.6,
					}, Enum.EasingStyle.Quint)
				end)
			end
		end

		-- THE INSIDE, revealed. Timed to 0.55s -- after the shell has started hinging apart, so the core is
		-- uncovered rather than clipping through a candy that is still shut, and while the smoke is still
		-- up, so it emerges out of it.
		task.delay(0.55, function() buildCandyCore(origin) end)

		-- ...and then the realm ends. Held back to 2.2s so the blast, the smoke and the core rising all get
		-- to land on their own before the celebration starts talking over them.
		task.delay(2.2, function() realmFinale(origin) end)

		-- ---- SETTLE -----------------------------------------------------------------------------------
		for _, s in ipairs(sockets) do
			if s.beam then s.beam:Destroy(); s.beam = nil end
			if s.pad then tween(s.pad, 0.8, { Transparency = 1 }); Debris:AddItem(s.pad, 1) end
		end
		for _, c in ipairs(crystals) do
			clearAura(c.part)
			if c.part then tween(c.part, 0.5, { Transparency = 1 }) end
		end

		task.delay(0.9, function() shakeCamera(0.35, 2.0) end)   -- the rumble after the bang

		refreshBanner()
		if _G.NotifyCenter and _G.NotifyCenter.push then
			pcall(function()
				_G.NotifyCenter.push({ text = "\xF0\x9F\x92\xA5 The giant candy is cracked open!", color = GOLD })
			end)
		end
		-- IslandTaskWatcher looks for _G.<name>QuestComplete -- this is how the island task pays out.
		_G.candyMineQuestComplete = true
		-- CINEMATIC PAYOFF. RevealCommand resolves island16's subject itself and plays the shot, so this
		-- is one line and re-aiming it later is an edit to TARGETS there, not here. Delayed so the
		-- completion banner and the world change land FIRST -- the camera is going there to show you
		-- the result, and cutting away before it happens shows you the before.
		task.delay(0.8, function() pcall(_G.revealIsland, 16) end)
		print("[CandyMine] complete -- giant candy cracked open")
	end)
end

-- ============================================================================
-- /done -- RUN THE REAL FINALE
-- ============================================================================
-- DoneCommand calls `_G.<id>ForceComplete` if a quest publishes one, and only falls back to flipping the
-- completion flag when it does not. Flipping the flag alone would pay the tokens and tick the journal
-- while leaving a giant candy sitting there intact with five crystals still out in the cliffs -- the
-- island would say "done" and plainly not be. So this does the actual thing:
--
--     every remaining crystal flies into a socket, one after another, and then it goes up.
--
-- Written to be safe to call at ANY point: mid-carry, half-placed, never accepted, or already finished.
-- A test command that only works from a clean start is a test command you cannot trust.
_G.candymineForceComplete = function()
	if finished then return end
	accepted = true                 -- calling /done IS accepting it
	refreshBanner()

	task.spawn(function()
		-- Whatever is in your hands goes in like the rest -- clearing `carrying` first stops the carry
		-- loop below fighting the tween for that one crystal.
		carrying = nil

		local pending = {}
		for _, c in ipairs(crystals) do
			if not c.placed then pending[#pending + 1] = c end
		end

		for _, c in ipairs(pending) do
			local s = nextFreeSocket()
			if not s then break end     -- fewer sockets than crystals: seat what fits, blow the rest anyway
			c.taken = true
			if c.prompt then c.prompt.Enabled = false end
			clearAura(c.part)
			c.part.CanCollide = false
			placeCharge(s, c, true)     -- animate: fly it in
			task.wait(0.16)             -- staggered, so they land in sequence rather than all at once
		end

		task.wait(0.55)                 -- let the last one settle into its socket before the charge sequence
		crackOpen()
	end)
end

-- ============================================================================
-- NPC  (the other islands' wiring, unchanged)
-- ============================================================================
-- ===== DIALOGUE: DINO-REALM HOUSE STYLE =====
-- Measured off farttofloatdinosaurealm/NPC_DIALOGUE.md, which sets the standard by example rather than by
-- a written rule: 6 words a line on average, 10 at the outside, 3 lines a page, ~30 words a page.
-- Short declarative lines, ONE IDEA EACH, ending on the instruction.
--
-- This is not house style for its own sake -- the bubble is 320x150 with TextScaled and MaxTextSize 22, so
-- a long page does not overflow, it SHRINKS. Every extra word makes every word smaller, and on a phone
-- (~667x375 logical px, which is what these bubbles are sized against) it stops being readable well before
-- it stops fitting. The first draft of page 2 here was a 31-word run-on and would have rendered as fine
-- print on the device most players are on.
local function questPages()
	if finished then
		return { "The candy's open!\nGo see what's inside. \xF0\x9F\x92\x9B" }
	end
	if placedCount >= CHARGES then
		return { ("%d charges armed!\nRUN! Blows in %d seconds!")
			:format(CHARGES, FUSE_SECONDS) }
	end
	if accepted then
		local lines = { ("Keep going!\nCharges set: %d of %d."):format(placedCount, CHARGES),
			"Press Take on a crystal in the cliffs, then stand on a gold pad with it." }
		if placedCount >= CHARGES - 1 then
			lines[#lines + 1] = ("Careful now -- the LAST one wakes up LIVE.\nYou'll have %d seconds. RUN it in!")
				:format(ARM_SECONDS)
		end
		return lines
	end
	-- CHARGES rather than a hard-coded "five", so the count on screen and the count the
	-- foreman asks for can never drift apart
	return {
		"That giant candy won't crack.\nNothing we've tried works.",
		("%d crystals hide in the cliffs.\nPress Take."):format(CHARGES),
		"Carry them to the glowing GOLD PADS.",
		"The last one wakes ANGRY. Then RUN.",
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
				local hrp = hrpOf()
				if not hrp or (hrp.Position - head.Position).Magnitude > TALK_DISTANCE then close(); break end
				task.wait(0.25)
			end
			watching = false
		end)
	end
	prompt.Triggered:Connect(function()
		if index == 0 then pages = (_G.capBubble and _G.capBubble(questPages())) or questPages() end
		index += 1
		if not pages or index > #pages then close(); return end
		-- page 2 is the handoff, same as every other island: you have to read a bit first
		if index == 2 and not accepted then
			accepted = true
			refreshBanner()
			for _, c in ipairs(crystals) do
				if not c.taken and not c.placed then
					if _G.guideTrailTo then pcall(function() _G.guideTrailTo(c.part.Position) end) end
					break
				end
			end
		end
		local last = index >= #pages
		-- no "[E] ..." badge in the bubble: the ProximityPrompt IS the E prompt, and the page
		-- count rides its ActionText instead of a second floating HUD over the NPC's head
		showBubble(head, pages[index], true, nil)
		prompt.ActionText = last and "Close" or ("Continue  (%d/%d)"):format(index, #pages)
		watch()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then close() end end)
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	island = pollFor(findIsland, 60)
	if not island then
		warn(("[CandyMine] no Model named '%s' in Workspace -- quest inactive. (It is off the ladder, so"
			.. " IslandLayout does not place it; it must exist in Studio under that name.)"):format(ISLAND_NAME))
		return
	end

	-- THE BLAST TARGET. One full pass per name, in CANDY_NAMES order, so the exact "giantcandy" always
	-- beats the loose "candy" fallback no matter where either sits in the tree.
	--
	-- The two exclusions are not paranoia. Both the quest giver ("Candy Npc" -> "candynpc") and the five
	-- charges are on this island and both contain a listed substring, so without them the loose pass could
	-- return either -- and a blast target that is really the NPC, or really one of the crystals, fails in a
	-- way no log line would explain.
	for _, want in ipairs(CANDY_NAMES) do
		local w = norm(want)
		candyModel = findInIsland(island, function(d)
			if not (d:IsA("BasePart") or d:IsA("Model")) then return false end
			local n = norm(d.Name)
			if n:find(NPC_HINT, 1, true) then return false end        -- never the quest giver
			if n:find(CRYSTAL_NAME, 1, true) then return false end    -- never one of the charges
			if d.Name == "AuraShell" or d.Name == "ChargeSocket" then return false end -- never our own props
			return n:find(w, 1, true) ~= nil
		end)
		if candyModel then break end
	end

	candyPart = firstBasePart(candyModel)
	if not candyPart then
		warn("[CandyMine] no 'giantcandy' found on island16 -- name the blast target 'giantcandy' in Studio."
			.. " Nothing to ring with charges, so the quest stays inactive.")
		return
	end
	print(("[CandyMine] blast target '%s' found"):format(candyModel.Name))

	--======================================================================
	-- ALL FOUR CHARGES EXIST, GLOW, AND CAN BE PICKED UP. ALWAYS.
	--======================================================================
	-- TWO BUGS LIVED HERE, and a good run hid both of them.
	--
	--   1. THE WIRING LOOP RAN ONCE, IMMEDIATELY. The comment right above it says the crystals
	--      "stream in, so keep scanning rather than taking one look" -- and the rescan loop does
	--      exactly that, appending late arrivals to `crystals`. But the loop that gives each one its
	--      glow and its Take prompt had already run, over whatever the FIRST synchronous scan
	--      happened to catch. Anything that streamed in afterwards was registered and then left
	--      dark and promptless: a crystal you can see but cannot take, or cannot see at all. Whether
	--      you got 4 or 1 was down to how fast island16 replicated.
	--
	--   2. TOO FEW CRYSTALS SOFT-LOCKED THE ISLAND. The old warning said "the quest asks for what
	--      exists" -- it does not. CHARGES stays 4, buildSockets rings 4 sockets, and the BLOW IT
	--      prompt gates on placedCount >= CHARGES. Three crystals and four sockets is a quest that
	--      can never be finished, announced as a warning nobody sees in a shipped game.
	--
	-- So wiring is now per-crystal and idempotent, applied after EVERY scan, and any shortfall left
	-- when the world stops producing them is BUILT. Four cubes, four sockets, every time.
	local function wireCrystal(c)
		if c.prompt then return end          -- already wired; re-scans must not stack prompts
		c.aura = addAura(c.part, PINK)
		local p = Instance.new("ProximityPrompt")
		p.Name = "UnstablePrompt"
		p.ActionText = "Take"; p.ObjectText = "Unstable Crystal"
		p.HoldDuration = 0.3
		p.MaxActivationDistance = PICKUP_RANGE
		p.RequiresLineOfSight = false
		p.Parent = c.part
		p.Triggered:Connect(function() pickUp(c) end)
		c.prompt = p
	end
	local function wireAll()
		for _, c in ipairs(crystals) do wireCrystal(c) end
	end

	-- A stand-in charge, for when the world did not supply enough. Sat on the ground inside the
	-- socket ring so it reads as part of the set rather than a prop dropped from orbit.
	local function buildCrystal(i)
		local ang = (i - 1) / CHARGES * math.pi * 2 + 0.6
		local at  = candyPart.Position + Vector3.new(math.cos(ang) * 26, 0, math.sin(ang) * 26)
		local rp  = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { player.Character }
		local hit = Workspace:Raycast(at + Vector3.new(0, 120, 0), Vector3.new(0, -400, 0), rp)
		local y = hit and (hit.Position.Y + 2.2) or (candyPart.Position.Y + 2.2)

		local part = Instance.new("Part")
		part.Name = CRYSTAL_NAME .. "Built" .. i
		part.Size = Vector3.new(4.2, 4.2, 4.2)
		part.Color = PINK; part.Material = Enum.Material.Neon
		part.Anchored = true; part.CanCollide = false
		part.CFrame = CFrame.new(at.X, y, at.Z) * CFrame.Angles(math.rad(18), ang, math.rad(12))
		part.Parent = island
		return { part = part, home = part.CFrame, taken = false, placed = false, built = true }
	end

	scanCrystals()
	wireAll()
	task.spawn(function()
		local tries = 0
		while #crystals < CHARGES and tries < 40 do
			task.wait(1); scanCrystals(); wireAll(); tries += 1
		end
		-- the world has had 40 seconds; make up whatever is still missing rather than shipping an
		-- island that cannot be completed
		local built = 0
		while #crystals < CHARGES do
			built += 1
			local c = buildCrystal(#crystals + 1)
			crystals[#crystals + 1] = c
			wireCrystal(c)
		end
		if built > 0 then
			warn(("[CandyMine] only %d part(s) named '%s' on island16 -- BUILT %d more so all %d "
				.. "charges exist. Name %d parts '%s' in Studio to use your own."):format(
				CHARGES - built, CRYSTAL_NAME, built, CHARGES, CHARGES, CRYSTAL_NAME))
		end
		print(("[CandyMine] %d/%d unstable crystal(s) wired and glowing (%d built)")
			:format(#crystals, CHARGES, built))
	end)

	buildSockets()

	-- NO "BLOW IT" PROMPT ANY MORE. It used to sit on the candy and go live once every charge was
	-- seated, so the last thing the quest asked of you was to walk BACK to the thing you had just
	-- rigged and hold a key on it. Arming is the trigger now: seat the fourth charge and the fuse
	-- lights itself, which is both what a charge is for and the only version that gives the ten
	-- seconds a reason to exist -- you spend them getting clear.
	--
	-- startFuse is assigned HERE, not defined above, because it calls crackOpen(). It is forward-
	-- declared with the state at the top so placeCharge can reach it.
	startFuse = function()
		if finished or fuseLeft then return end          -- already burning, or already blown
		if placedCount < CHARGES then return end
		task.spawn(function()
			fuseGui.Enabled = true
			for t = FUSE_SECONDS, 1, -1 do
				fuseLeft = t
				fuseNum.Text = tostring(t)
				fuseNum.TextColor3 = (t <= 3) and DANGER or GOLD
				-- THE HUD READS YOUR ACTUAL DISTANCE. "GET CLEAR" with no ruler is a vibe; this is
				-- an instruction you can finish following. Green when you have made it, red until.
				local ehrp = hrpOf()
				local isClear = ehrp and candyPart
					and ((ehrp.Position - candyPart.Position).Magnitude >= LAUNCH_RANGE)
				fuseCap.Text = isClear and "SAFE -- KEEP GOING!" or ((t <= 3) and "TOO CLOSE -- RUN!!" or "GET CLEAR!")
				fuseCap.TextColor3 = isClear and GREEN or DANGER
				-- ...and the island's light dies with the clock: each second is visibly darker, so
				-- the escape run happens into gathering dark and the blast lands out of it.
				gloom.Enabled = true
				gloom.Brightness = -0.032 * (FUSE_SECONDS - t + 1)
				gloom.Saturation = -0.05 * (FUSE_SECONDS - t + 1)
				-- a beat of pop on each second, so the number reads as a tick and not a redraw
				fuseNum.Size = UDim2.new(0, 340, 0, 170)
				tween(fuseNum, 0.22, { Size = UDim2.new(0, 300, 0, 150) })
				-- every armed socket blinks white on the same beat
				for _, sk in ipairs(sockets) do
					if sk.pad then
						sk.pad.Color = Color3.new(1, 1, 1)
						task.delay(0.18, function() if sk.pad then sk.pad.Color = DANGER end end)
					end
				end
				playSound(SOUND_PLACE, (t <= 3) and 0.9 or 0.55)
				refreshBanner()
				task.wait(1)
			end
			fuseLeft = nil
			fuseGui.Enabled = false
			refreshBanner()
			crackOpen()
		end)
	end

	-- Seating the fourth charge normally starts it, but a charge can also be seated before this
	-- block has run (streaming, or /done firing early). Catch that case rather than leaving an
	-- armed shot that never goes off.
	if placedCount >= CHARGES then task.defer(startFuse) end

	-- The NPC is OPTIONAL and must never gate the world -- the same mistake that left island 9 empty for
	-- 30 seconds. Everything above is already built; she is found in the background.
	task.spawn(function()
		npcHead = pollFor(function()
			local n = findInIsland(island, function(d)
				return d:IsA("Model") and norm(d.Name):find(NPC_HINT, 1, true) ~= nil
			end)
			return n and (n:FindFirstChild("Head") or firstBasePart(n)) or nil
		end, 30)
		if npcHead then
			wireNPC(npcHead)
			print("[CandyMine] island16 Candy Npc wired")
		else
			-- no giver: don't lock the player out of the quest on their own island
			accepted = true
			refreshBanner()
			warn("[CandyMine] no 'Candy Npc' on island16 -- quest self-started without a giver")
		end
	end)

	refreshBanner()
	print(("[CandyMine] ready -- %d crystal(s), %d socket(s), target '%s'")
		:format(#crystals, #sockets, candyModel.Name))
	-- RETAINER SIGNAL: the quest reached the end of its build with its world objects up. QuestRetainer
	-- watches this flag; anything still false once its island has streamed in gets force-streamed and
	-- re-run. It is set HERE, at the ready print, not at the top of the file -- every bail above this
	-- point (no island16, no BaseParts, no 'giantcandy') returns without setting it, which is exactly
	-- the state the retainer exists to notice. See QuestRetainer.client.luau.
	_G.questBuilt_candymine = true
end)
