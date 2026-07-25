--======================================================================
-- CandyDeliveryQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- ISLAND-5 QUEST: "Candy Delivery Route"
--
-- FLOW: talk to the Candy NPC -> go to the CANDY FACTORY (production spot) ->
-- MAKE a specific taffy through a 3-step conveyor mini-game -> carry it out and
-- DELIVER it to the island that wants that flavour. Repeat for all 3 stations.
-- (Making + delivering uses every rainbow bridge in both directions.)
--
-- WHAT THE WORLD PROVIDES (name these in Studio, on island5):
--   * 3 floating mini-islands ALL named  islanddelivery  (Part or Model) -- the
--     delivery stations, reached over the rainbow bridges.
--   * one factory object named  production spot  (Part or Model) -- the factory.
--   * a "Candy Npc" (island5's) -- picked as the one NEAREST the production spot.
--
-- WHAT THIS SCRIPT BUILDS (per-player, client-side):
--   * A real conveyor-belt candy factory on the production spot, with 3 interactive
--     steps -- MIX (tap-mash), COOK (stop the gauge in the green), WRAP (time the
--     shrinking ring) -- each with its own HUD. A taffy blob rides the belt.
--   * On each islanddelivery: a delivery pad + package sized to fit INSIDE that
--     island (reads its bounding box, never spills over) showing the flavour it wants.
--   * island1-style NPC speech bubbles + "talk to the NPC" objective banner.
--   * /complete finishes it instantly (near the factory).
--======================================================================

-- DISABLED: island 5 now runs TaffyStormQuest_AllInOne instead of the delivery route.
-- Flip this to false to bring the whole delivery quest (and the orchard) back.
local QUEST_DISABLED = true
if QUEST_DISABLED then
	print("[Delivery] disabled -- island5 is running the Taffy Storm quest instead")
	return
end

local Players         = game:GetService("Players")
local Workspace       = game:GetService("Workspace")
local TweenService    = game:GetService("TweenService")
local Debris          = game:GetService("Debris")
local TextChatService = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_NAME      = "islanddelivery"
local PRODUCTION_NAMES = { "production spot", "productionspot" }
local NPC_NAMES        = { "candy npc", "candynpc" }

-- ORCHARD MODE: the factory is gone. Taffy grows on trees dotted around island5 --
-- walk up, shake one, and the fruit for that order drops. Set USE_ORCHARD = false to
-- put the old 3-step conveyor factory back.
local USE_ORCHARD      = true
local TREE_NAMES       = { "taffytree", "candytree" }  -- optional: place your own trees
local TREES_PER_FLAVOR = 2       -- trees grown per flavour if you haven't placed any
local SHAKE_TIME       = 1.1     -- hold-E to shake a tree
local ORCHARD_RADIUS   = 62      -- how far from the production spot trees get scattered

local EXPECTED_STATIONS = 3      -- how many islanddelivery you placed (auto-raises if more are found)
local BANNER_RANGE      = 320    -- before you accept, the banner shows within this range of the NPC (like island1)
local TALK_DISTANCE     = 12
local DELIVER_DISTANCE  = 10

-- one taffy flavour per station (index == station number)
local TAFFY = {
	{ name = "Strawberry Taffy", color = Color3.fromRGB(255, 120, 150) },
	{ name = "Blueberry Taffy",  color = Color3.fromRGB(120, 160, 255) },
	{ name = "Grape Taffy",      color = Color3.fromRGB(185, 120, 230) },
}

-- candy palette
local FILL   = Color3.fromRGB(255, 240, 248)
local STROKE = Color3.fromRGB(200, 60, 120)
local TEXTC  = Color3.fromRGB(80, 30, 60)
local HINTC  = Color3.fromRGB(150, 120, 160)
local PINK   = Color3.fromRGB(255, 95, 160)
local GREEN  = Color3.fromRGB(110, 210, 120)
local GOLD   = Color3.fromRGB(255, 205, 90)

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
local function boundsOf(inst)
	if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
	return inst:GetBoundingBox()
end
local function topOf(inst)
	local cf, sz = boundsOf(inst)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { inst }
	local hit = Workspace:Raycast(cf.Position + Vector3.new(0, sz.Y, 0), Vector3.new(0, -sz.Y * 2.5, 0), rp)
	local topY = (hit and hit.Position.Y) or (cf.Position.Y + sz.Y * 0.5)
	return Vector3.new(cf.Position.X, topY, cf.Position.Z), sz
end
local function findProduction()
	-- exact name first, then a loose "has 'production' in the name" fallback (e.g. "Production Plant")
	local loose
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Model") then
			local nm = string.lower(d.Name)
			for _, want in ipairs(PRODUCTION_NAMES) do if nm == want then return d end end
			if not loose and (nm:find("production", 1, true) or nm:find("factory", 1, true)) then loose = d end
		end
	end
	return loose
end
local function npcHeadOf(inst)
	if not inst then return nil end
	return (inst:IsA("Model") and (inst:FindFirstChild("Head") or inst.PrimaryPart or firstBasePart(inst)))
		or (inst:IsA("BasePart") and inst) or firstBasePart(inst)
end
local function findNPCNear(refPos)
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		local nm = string.lower(d.Name)
		local match = false
		for _, want in ipairs(NPC_NAMES) do if nm == want then match = true; break end end
		if match then
			local head = npcHeadOf(d)
			if head then
				if not refPos then return head end -- no reference yet -> take any Candy Npc
				local dist = (head.Position - refPos).Magnitude
				if not bestD or dist < bestD then best, bestD = head, dist end
			end
		end
	end
	return best
end
local function pointTo(pos)
	if pos and _G.guideTrailTo then pcall(function() _G.guideTrailTo(pos) end) end
end
local function fxPart(props)
	local p = Instance.new("Part"); p.Anchored = true; p.CanCollide = false; p.CastShadow = false
	for k, v in pairs(props) do p[k] = v end
	return p
end
local function billboardOn(part, text, color)
	local bb = Instance.new("BillboardGui"); bb.Name = "CandyTag"; bb.Adornee = part; bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0,210,0,48); bb.StudsOffset = Vector3.new(0, 6, 0); bb.MaxDistance = 600
	local l = Instance.new("TextLabel"); l.Size = UDim2.fromScale(1,1); l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne; l.Text = text; l.TextColor3 = color; l.TextScaled = true; l.TextStrokeTransparency = 0.4; l.Parent = bb
	Instance.new("UITextSizeConstraint", l).MaxTextSize = 26
	bb.Parent = part
	return l
end

-- ============================================================================
-- STATE  (FactoryRun / makeTaffy declared early so everything can see them)
-- ============================================================================
local accepted         = false
local producing        = false
local done             = false
local deliveredCount   = 0
local requiredStations = EXPECTED_STATIONS
local stations         = {}     -- [idx] = { inst, pad, pkg, prompt, tag, pos, flavor, delivered }
local carrying         = nil    -- station index whose taffy you're holding, or nil
local readyFlavor, readyIdx     -- a finished candy waiting in the basket to be taken
local npcHead
local productionPos
-- both live further down the file, but the objective banner (above them) and the GO
-- block need to reach them
local nextNeeded
local buildOrchard
local FactoryRun       = nil    -- set by buildFactory(): function(flavor) -> true

-- ============================================================================
-- SPEECH BUBBLE + OBJECTIVE BANNER  (island1 behaviour)
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

local objGui = Instance.new("ScreenGui"); objGui.Name = "DeliveryQuestObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7; objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame"); objFrame.AnchorPoint = Vector2.new(0.5,0); objFrame.Position = UDim2.new(0.5,0,0,12); objFrame.Size = UDim2.new(0,520,0,52)
objFrame.BackgroundColor3 = FILL; objFrame.Visible = false; objFrame.Parent = objGui
Instance.new("UICorner", objFrame).CornerRadius = UDim.new(0,16)
do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 3; s.Parent = objFrame end
local objLabel = Instance.new("TextLabel"); objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1,1); objLabel.Font = Enum.Font.FredokaOne
objLabel.TextColor3 = TEXTC; objLabel.TextScaled = true; objLabel.Parent = objFrame
do local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = objLabel
   local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,14); pad.PaddingRight = UDim.new(0,14); pad.Parent = objLabel end

local function baseText()
	if done      then return "\xF0\x9F\x8D\xAC Every order filled -- the factory is buzzing!" end
	if not accepted then return "\xF0\x9F\x92\xAC Go talk to the Candy NPC!" end
	if producing then return "\xF0\x9F\x8F\xAD Making taffy at the factory..." end
	if readyFlavor then return "\xF0\x9F\x8D\xAC Take your candy from the basket!" end
	if carrying and stations[carrying] then return ("\xF0\x9F\x93\xA6 Deliver %s to Station %d"):format(stations[carrying].flavor.name, carrying) end
	if deliveredCount >= requiredStations then return "\xF0\x9F\x8D\xAC All taffy delivered!" end
	if USE_ORCHARD then
		local want = nextNeeded and nextNeeded()
		if want then
			return ("\xF0\x9F\x8C\xB3 Pick %s from the orchard:  %d/%d"):format(
				want.flavor.name, deliveredCount, requiredStations)
		end
	end
	return ("\xF0\x9F\x8F\xAD Make taffy at the factory:  %d/%d"):format(deliveredCount, requiredStations)
end
local flashTok = 0
local function refreshBanner() objLabel.Text = baseText() end
local function flashBanner(text, secs)
	flashTok += 1; local t = flashTok; objLabel.Text = text
	task.delay(secs or 2.5, function() if t == flashTok then refreshBanner() end end)
end
-- before accept: show near the NPC (island1). after accept: always show while active.
task.spawn(function()
	while true do
		local vis = false
		if done then vis = false
		elseif accepted then vis = true
		elseif npcHead and npcHead.Parent then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			vis = hrp ~= nil and (hrp.Position - npcHead.Position).Magnitude <= BANNER_RANGE
		end
		objFrame.Visible = vis
		task.wait(0.4)
	end
end)

-- ============================================================================
-- CARRY TAG -- floats over your head while you carry a taffy
-- ============================================================================
local function setCarry(flavor)
	local char = player.Character; if not char then return end
	-- clear any existing hand candy + head tag
	for _, d in ipairs(char:GetDescendants()) do if d.Name == "HandCandy" then d:Destroy() end end
	local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	if head then local ex = head:FindFirstChild("CarryTaffyTag"); if ex then ex:Destroy() end end
	if not flavor then return end
	-- head tag
	if head then
		local bb = Instance.new("BillboardGui"); bb.Name = "CarryTaffyTag"; bb.Adornee = head; bb.AlwaysOnTop = true
		bb.Size = UDim2.new(0,240,0,42); bb.StudsOffset = Vector3.new(0, 3.2, 0); bb.Parent = head
		local l = Instance.new("TextLabel"); l.Size = UDim2.fromScale(1,1); l.BackgroundTransparency = 1
		l.Font = Enum.Font.FredokaOne; l.Text = "\xF0\x9F\x8D\xAC " .. flavor.name; l.TextColor3 = flavor.color; l.TextScaled = true; l.TextStrokeTransparency = 0.3; l.Parent = bb
		Instance.new("UITextSizeConstraint", l).MaxTextSize = 24
	end
	-- the candy itself, welded into your hand (a wrapped taffy: body + two white twist ends)
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if hand then
		local grip = CFrame.new(0, -0.7, 0) * CFrame.Angles(0, 0, math.rad(90)) -- roughly in the palm
		local body = Instance.new("Part"); body.Name = "HandCandy"; body.Shape = Enum.PartType.Cylinder
		body.Size = Vector3.new(1.5,0.7,0.7); body.Color = flavor.color; body.Material = Enum.Material.SmoothPlastic
		body.CanCollide = false; body.Massless = true; body.Parent = char
		local w = Instance.new("Weld"); w.Part0 = hand; w.Part1 = body; w.C0 = grip; w.Parent = body
		for _, s in ipairs({1,-1}) do
			local e = Instance.new("Part"); e.Name = "HandCandy"; e.Shape = Enum.PartType.Ball
			e.Size = Vector3.new(0.5,0.5,0.5); e.Color = Color3.fromRGB(255,248,252); e.Material = Enum.Material.SmoothPlastic
			e.CanCollide = false; e.Massless = true; e.Parent = char
			local we = Instance.new("Weld"); we.Part0 = hand; we.Part1 = e; we.C0 = grip * CFrame.new(0.9*s, 0, 0); we.Parent = e
		end
	end
end
player.CharacterAdded:Connect(function()
	task.wait(0.4)
	if carrying and stations[carrying] then setCarry(stations[carrying].flavor) end
end)

-- ============================================================================
-- FIREWORKS + WIN BANNER
-- ============================================================================
local FW = { Color3.fromRGB(255,92,138), Color3.fromRGB(120,200,255), Color3.fromRGB(150,235,130), Color3.fromRGB(255,205,90), Color3.fromRGB(190,130,255) }
local function mkNeon(props)
	local p = Instance.new("Part"); p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false; p.Material = Enum.Material.Neon
	for k,v in pairs(props) do p[k] = v end; return p
end
local function burst(at, color)
	for i = 1, 26 do
		local s = mkNeon({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.5,0.5,0.5), Color = color })
		s.CFrame = CFrame.new(at); s.Parent = Workspace
		local dest = at + Vector3.new((i % 7) - 3, (i % 5), ((i * 3) % 7) - 3).Unit * 14
		TweenService:Create(s, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(dest), Transparency = 1, Size = Vector3.new(0.1,0.1,0.1) }):Play()
		Debris:AddItem(s, 1)
	end
end
local function fireworks(from)
	for i = 1, 3 do
		task.delay(i * 0.35, function()
			local r = mkNeon({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.6,0.6,0.6), Color = Color3.fromRGB(255,240,200) })
			local start = from + Vector3.new((i - 2) * 6, 3, 0)
			r.CFrame = CFrame.new(start); r.Parent = Workspace
			local up = TweenService:Create(r, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(start + Vector3.new(0, 45 + i * 6, 0)) })
			up.Completed:Connect(function() burst(r.Position, FW[((i - 1) % #FW) + 1]); r:Destroy() end)
			up:Play()
		end)
	end
end
local function winBanner()
	local g = Instance.new("ScreenGui"); g.Name = "DeliveryWin"; g.ResetOnSpawn = false; g.DisplayOrder = 20; g.IgnoreGuiInset = true; g.Parent = PlayerGui
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5,0.5); f.Position = UDim2.new(0.5,0,0.42,0); f.Size = UDim2.new(0,0,0,90); f.BackgroundColor3 = FILL; f.Parent = g
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,18)
	do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 4; s.Parent = f end
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Size = UDim2.fromScale(1,1); l.Font = Enum.Font.FredokaOne; l.TextColor3 = TEXTC; l.TextScaled = true
	l.Text = "\xF0\x9F\x8D\xAC Candy delivery complete!"; l.Parent = f
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,24); pad.PaddingRight = UDim.new(0,24); pad.Parent = l
	Instance.new("UITextSizeConstraint", l).MaxTextSize = 32
	TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0,660,0,90) }):Play()
	task.delay(5, function() TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play(); TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play(); task.delay(0.5, function() g:Destroy() end) end)
end
local function winQuest()
	if done then return end
	done = true; producing = false; carrying = nil; readyFlavor, readyIdx = nil, nil; setCarry(nil)
	if _G.__candyBasket then _G.__candyBasket.hideReady() end
	_G.deliveryQuestComplete = true
	refreshBanner()
	local at = (productionPos or (player.Character and player.Character:GetPivot().Position)) + Vector3.new(0, 8, 0)
	fireworks(at); winBanner()
	if _G.NotifyCenter then pcall(function() _G.NotifyCenter.push({ text = "\xF0\x9F\x8D\xAC Candy delivery complete!", color = STROKE }) end) end
	print("[Delivery] complete -- all taffy made + delivered")
end

-- ============================================================================
-- THE CONVEYOR-BELT CANDY FACTORY  (built on the production spot)
-- returns runProduction(flavor) -> true   (a 3-step interactive mini-game)
-- ============================================================================
local function buildFactory(prod)
	local fx = Instance.new("Folder"); fx.Name = "CandyFactoryBuild"; fx.Parent = Workspace

	local base   = firstBasePart(prod)
	local pivot  = base and base.CFrame or CFrame.new(productionPos)
	local ax = pivot.LookVector; ax = Vector3.new(ax.X, 0, ax.Z)
	if ax.Magnitude < 0.05 then ax = Vector3.new(1,0,0) else ax = ax.Unit end
	ax = CFrame.fromAxisAngle(Vector3.yAxis, -math.pi/2) * ax   -- flip the whole machine 90° clockwise
	local beltLen, beltWid, beltThk = 40, 6, 1.0
	local center = Vector3.new(productionPos.X, productionPos.Y + 3.0, productionPos.Z)
	local beltCF = CFrame.lookAt(center, center + ax)
	local function point(t)
		local from = center - ax * (beltLen / 2 - 2)
		local to   = center + ax * (beltLen / 2 - 2)
		return from:Lerp(to, t)
	end
	local function blobPos(t) return point(t) + Vector3.new(0, beltThk / 2 + 1.4, 0) end

	-- ======================= PREMIUM CANDY-FACTORY BUILD =======================
	-- Chunky rounded candy frame, animated rollers/gears/pistons/wheels, ingredient
	-- hopper, wrapping output, blinking lights + layered candy details. One shared
	-- animation loop drives everything (optimised, low-poly, readable from afar).
	local up   = Vector3.yAxis
	local side = ax:Cross(up); if side.Magnitude < 0.05 then side = Vector3.new(0,0,1) else side = side.Unit end
	local rot   = beltCF.Rotation
	local halfL = beltLen / 2

	-- palette: pink / purple / white / gold + dark belt
	local C_PINK, C_PURPLE, C_WHITE, C_GOLD = Color3.fromRGB(255,120,185), Color3.fromRGB(170,120,235), Color3.fromRGB(255,248,252), Color3.fromRGB(255,205,90)
	local C_BELT, C_STRIPE = Color3.fromRGB(34,28,44), Color3.fromRGB(120,108,150)
	local C_RED, C_MINT, C_CHOC = Color3.fromRGB(255,95,120), Color3.fromRGB(150,235,190), Color3.fromRGB(110,72,52)

	-- animation registries
	local spinners, pistons, lights, glows, risers, flow = {}, {}, {}, {}, {}, {}
	local orbiters, sliders, rods, swings, confetti, belts = {}, {}, {}, {}, {}, {}
	local function spin(part, pivot, axis, speed) spinners[#spinners+1] = { part = part, part0 = part.CFrame, pivot = pivot, axis = axis, speed = speed } end

	-- placement + primitive helpers
	local function alongPos(d, u, s) return center + ax * d + up * (u or 0) + side * (s or 0) end
	local function P(props) local p = fxPart(props); p.Parent = fx; return p end
	local function boxAt(pos, size, color, mat, collide)
		return P({ Size = size, CFrame = CFrame.new(pos) * rot, Color = color, Material = mat or Enum.Material.SmoothPlastic, CanCollide = collide or false })
	end
	local function cyl(pos, len, rad, color, mat, aimAxis) -- length runs along aimAxis (world unit; use side/ax only)
		return P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, rad*2, rad*2), CFrame = CFrame.new(pos, pos + aimAxis) * CFrame.Angles(0,0,math.rad(90)), Color = color, Material = mat or Enum.Material.SmoothPlastic })
	end
	local function upCyl(pos, len, rad, color, mat) -- upright cylinder (length vertical)
		return P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, rad*2, rad*2), CFrame = CFrame.new(pos) * CFrame.Angles(0,0,math.rad(90)), Color = color, Material = mat or Enum.Material.SmoothPlastic })
	end
	local function ball(pos, rad, color, mat)
		return P({ Shape = Enum.PartType.Ball, Size = Vector3.new(rad*2,rad*2,rad*2), Position = pos, Color = color, Material = mat or Enum.Material.SmoothPlastic })
	end

	-- ---- CHUNKY CHASSIS + candy-cane leg supports + overhead pipes ----
	boxAt(alongPos(0,-2.6,0), Vector3.new(beltWid+3.2, 4.6, beltLen+1.6), C_PINK, Enum.Material.SmoothPlastic, true)  -- tall main body
	boxAt(alongPos(0,-0.3,0), Vector3.new(beltWid+3.6, 1.1, beltLen+1.0), C_PURPLE)                                    -- accent band around belt line
	for _, sgn in ipairs({1,-1}) do
		boxAt(alongPos(0,-1.2,(beltWid/2+1.5)*sgn), Vector3.new(0.7, 3.2, beltLen*0.86), C_PURPLE)                     -- chunky side panels
	end
	local ug = boxAt(alongPos(0,-4.1,0), Vector3.new(beltWid+1.4, 0.35, beltLen), C_PINK, Enum.Material.Neon); ug.Transparency = 0.2 -- under-glow
	-- 4 clean support legs with gold feet
	for _, sgn in ipairs({1,-1}) do
		for _, d in ipairs({ -(halfL-1.5), (halfL-1.5) }) do
			boxAt(alongPos(d, -5.0, (beltWid/2+1.1)*sgn), Vector3.new(1.0, 5.6, 1.0), C_PURPLE)
			boxAt(alongPos(d, -7.7, (beltWid/2+1.1)*sgn), Vector3.new(1.3, 0.5, 1.3), C_GOLD)
		end
	end
	-- one clean central column (hides the mount below)
	do
		boxAt(alongPos(0, -5.4, 0), Vector3.new(2.6, 6.2, 2.6), C_PURPLE)
		boxAt(alongPos(0, -8.5, 0), Vector3.new(3.4, 0.6, 3.4), C_GOLD)
	end

	-- ---- DARK BELT + moving conveyor stripes (candy stands out) ----
	local belt = boxAt(center, Vector3.new(beltWid, beltThk, beltLen), C_BELT, Enum.Material.SmoothPlastic, true); belt.Name = "ConveyorBelt"
	local sg = Instance.new("SurfaceGui"); sg.Adornee = belt; sg.Face = Enum.NormalId.Top; sg.CanvasSize = Vector2.new(160, 560); sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize; sg.Parent = belt
	local sbg = Instance.new("Frame"); sbg.Size = UDim2.fromScale(1,1); sbg.BackgroundColor3 = C_BELT; sbg.BorderSizePixel = 0; sbg.Parent = sg
	local stripes = {}
	for i = 1, 16 do local s = Instance.new("Frame"); s.Size = UDim2.new(1,0,0.05,0); s.BackgroundColor3 = C_STRIPE; s.BorderSizePixel = 0; s.Parent = sbg; stripes[i] = s end

	-- ---- FROSTING TRIM (rounded top edges) + END CAPS ----
	for _, sgn in ipairs({1,-1}) do cyl(alongPos(0, beltThk/2 + 0.1, (beltWid/2 + 0.9)*sgn), beltLen + 1.0, 0.55, C_WHITE, Enum.Material.SmoothPlastic, ax) end
	for _, tt in ipairs({ -(halfL+0.4), (halfL+0.4) }) do cyl(alongPos(tt, beltThk/2 + 0.1, 0), beltWid + 2.2, 0.6, C_WHITE, Enum.Material.SmoothPlastic, side) end

	-- ---- CANDY GEAR helper (used to power rollers, paddles, the crank, etc.) ----
	local function candyGear(cc, R, teeth, base, accent, speed)
		local rim = cyl(cc, 0.75, R, base, Enum.Material.Metal, side); rim.Reflectance = 0.12; spin(rim, cc, side, speed) -- painted-metal rim
		spin(cyl(cc + side*0.12, 0.85, R*0.32, Color3.fromRGB(90,90,105), Enum.Material.Metal, side), cc, side, speed)     -- steel hub/axle boss
		local tw = math.clamp(R*0.4, 0.34, 0.7)
		for i = 1, teeth do
			local a = (i/teeth) * math.pi * 2
			local tp = cc + (math.cos(a)*ax + math.sin(a)*up) * (R + tw*0.4)
			spin(P({ Size = Vector3.new(tw, tw, 0.82), CFrame = CFrame.new(tp) * rot, Color = base, Material = Enum.Material.Metal }), cc, side, speed)
		end
	end

	-- =================== SIMPLE CONVEYOR LINE (only the belt moves) ===================
	local V = 3.0                     -- belt speed (studs/sec); the belt is the ONLY moving part
	_G.__candyFactoryV = V

	-- static rollers at each end of the belt
	for _, tt in ipairs({ -(halfL-0.6), (halfL-0.6) }) do
		local rc = alongPos(tt, 0, 0)
		cyl(rc, beltWid+1.4, 1.1, C_WHITE, Enum.Material.SmoothPlastic, side)
		for _, s in ipairs({1,-1}) do cyl(rc + side*(beltWid/2+0.7)*s, 0.4, 1.2, C_GOLD, Enum.Material.SmoothPlastic, side) end -- end caps
	end

	local function stationSign(d, topY, tx) end

	-- PORTAL: a clean tycoon-style arch the candy passes through (static, with a glowing membrane)
	local function portal(d, color, height)
		local w = beltWid + 3.2
		for _, s in ipairs({1,-1}) do
			boxAt(alongPos(d, height/2 - 1, (w/2)*s), Vector3.new(1.2, height, 1.6), C_PURPLE)   -- pillar
			boxAt(alongPos(d, -0.4, (w/2)*s), Vector3.new(1.7, 0.7, 2.1), C_GOLD)                -- base block
		end
		boxAt(alongPos(d, height - 1, 0), Vector3.new(w+1.4, 1.4, 1.6), color)                   -- top bar
		boxAt(alongPos(d, height - 0.2, 0), Vector3.new(w+1.9, 0.4, 1.9), C_GOLD)                -- gold crown
		local mem = boxAt(alongPos(d, (height-1)/2 + 0.3, 0), Vector3.new(w-1.2, height-2.2, 0.35), color, Enum.Material.Neon) -- glowing membrane
		mem.Transparency = 0.5; mem.CanCollide = false
	end

	-- the 5 portals along the line (the candy transforms as it passes through each)
	portal(-12, C_PINK,   6.5)  -- mixer
	portal(-4,  C_RED,    5.5)  -- cooker
	portal(3,   C_PURPLE, 5.0)  -- roller
	portal(8,   C_MINT,   5.0)  -- cutter
	portal(13,  C_GOLD,   6.5)  -- wrapper

	-- (elaborate spinning stations replaced by the static portals above)

	-- ============ FINISHED-CANDY BASKET (woven crate) + growing pile ============
	local basketPos = alongPos(halfL+4.2, -0.2, 0)
	local basketFloor
	do
		local bc = alongPos(halfL+4.2, -1.3, 0)
		local W, Lg, H = 4.4, 4.2, 2.8
		local WOOD = Color3.fromRGB(206,158,100)
		basketFloor = boxAt(bc + up*-1.4, Vector3.new(W, 0.45, Lg), WOOD, Enum.Material.SmoothPlastic, true)  -- floor (candy lands here)
		for _, s in ipairs({1,-1}) do
			boxAt(bc + side*(Lg/2)*s, Vector3.new(W, H, 0.4), WOOD)                                           -- long walls
			boxAt(bc + ax*(W/2)*s, Vector3.new(0.4, H, Lg), WOOD)                                             -- end walls
		end
		for _, s in ipairs({1,-1}) do                                                                         -- gold top rim only
			boxAt(bc + up*(H/2) + side*(Lg/2)*s, Vector3.new(W+0.5, 0.4, 0.55), C_GOLD)
			boxAt(bc + up*(H/2) + ax*(W/2)*s, Vector3.new(0.55, 0.4, Lg+0.5), C_GOLD)
		end
	end
	do local m = P({ Size = Vector3.new(0.2,0.2,0.2), Transparency = 1, Position = alongPos(halfL+4.2, 3.0, 0) }); billboardOn(m, "\xF0\x9F\x8D\xAC FINISHED CANDY", C_PINK) end

	-- ready-candy icon + "Take Candy" prompt -- shown when a finished candy is waiting to be taken
	local readyC = P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.7,0.85,0.85), Color = C_PINK, Material = Enum.Material.SmoothPlastic })
	readyC.CFrame = CFrame.new(basketPos + up*1.9)
	local readyEnds = {}
	for _, s in ipairs({1,-1}) do readyEnds[#readyEnds+1] = ball(basketPos + up*1.9 + ax*0.95*s, 0.42, C_WHITE) end
	local readyGui = billboardOn(readyC, "\xF0\x9F\x8D\xAC Take your candy!", C_PINK).Parent
	local function setReadyVisible(v, col)
		readyC.Transparency = v and 0 or 1; readyGui.Enabled = v
		if col then readyC.Color = col end
		for _, e in ipairs(readyEnds) do e.Transparency = v and 0 or 1 end
	end
	setReadyVisible(false)
	local takePrompt = Instance.new("ProximityPrompt")
	takePrompt.ActionText = "Take Candy"; takePrompt.ObjectText = "Finished Candy"; takePrompt.HoldDuration = 0
	takePrompt.MaxActivationDistance = 12; takePrompt.RequiresLineOfSight = false; takePrompt.Enabled = false; takePrompt.Parent = basketFloor
	takePrompt.Triggered:Connect(function() if _G.__takeCandy then _G.__takeCandy() end end)
	_G.__candyBasket = {
		pos = basketPos,
		showReady = function(f) setReadyVisible(true, f and f.color); takePrompt.Enabled = true end,
		hideReady = function() setReadyVisible(false); takePrompt.Enabled = false end,
	}

	-- pile candies -- revealed one-by-one as production runs, then resets (watch the pile grow)
	local pile = {}
	local pcol = { C_PINK, C_MINT, C_GOLD, C_RED, C_PURPLE }
	for i = 1, 12 do
		local layer = math.floor((i-1)/4)
		local a = (i * 2.35)
		local pos = alongPos(halfL+4.2, -2.2 + layer*0.55, 0) + (math.cos(a)*ax + math.sin(a)*side) * (1.1 - layer*0.2)
		local c = P({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.62,0.62,0.62), Position = pos, Color = pcol[((i-1)%5)+1], Material = Enum.Material.Neon })
		c.Transparency = 1; pile[i] = c
	end

	-- ---- AMBIENT CANDY FLOW: blob -> flattened strip -> wrapped candy -> drops in basket ----
	local beltStart = alongPos(-halfL + 2.0, beltThk/2 + 1.1, 0)
	local beltEnd   = alongPos(halfL - 2.0, beltThk/2 + 1.1, 0)
	local rollerP   = (3 + halfL) / beltLen    -- flatten after the roller
	local cutterP   = (8 + halfL) / beltLen    -- cut into pieces after the cutter
	local wrapperP  = (13 + halfL) / beltLen   -- wrap after the wrapper
	local fcol = { C_PINK, C_MINT, C_GOLD, C_RED, C_PURPLE, C_PINK, C_MINT }
	for i = 1, 7 do
		local pc = P({ Shape = Enum.PartType.Ball, Size = Vector3.new(1.3,1.3,1.3), Color = fcol[i], Material = Enum.Material.SmoothPlastic })
		flow[#flow+1] = { part = pc, p0 = (i-1)/7, speed = V / beltLen }  -- product travels at the belt speed
	end

	-- (scattered gumdrop/chocolate details removed to keep it clean)

	-- ---- SOFT CANDY LIGHTING: pink glow orbs, white string lights, blinking LEDs ----
	-- (floating glow orbs removed; the under-glow strip is enough)
	-- (string lights + LED rows removed to keep the machine clean)

	-- ======================= ONE SHARED ANIMATION LOOP =======================
	task.spawn(function()
		local t = 0
		while fx.Parent do
			t += 0.05
			local so = (t * (V / beltLen)) % (1 / #stripes)   -- candy belt scrolls at the roller surface speed
			for i, s in ipairs(stripes) do s.Position = UDim2.new(0, 0, ((i / #stripes) + so) % 1, 0) end
			for _, e in ipairs(flow) do
				local p = (t * e.speed + e.p0) % 1.22
				local part = e.part
				if p <= 1 then
					local pos = beltStart:Lerp(beltEnd, p)
					if p < rollerP then
						part.Shape = Enum.PartType.Ball; part.Size = Vector3.new(1.3,1.3,1.3); part.CFrame = CFrame.new(pos)                    -- blob
					elseif p < cutterP then
						part.Shape = Enum.PartType.Block; part.Size = Vector3.new(2.0,0.32,1.1); part.CFrame = CFrame.new(pos) * rot            -- flattened strip
					elseif p < wrapperP then
						part.Shape = Enum.PartType.Block; part.Size = Vector3.new(0.95,0.34,1.0); part.CFrame = CFrame.new(pos) * rot           -- cut piece
					else
						part.Shape = Enum.PartType.Cylinder; part.Size = Vector3.new(1.4,0.6,0.6); part.CFrame = CFrame.new(pos, pos + side) * CFrame.Angles(0,0,math.rad(90)) -- wrapped
					end
				else
					local q = (p - 1) / 0.22
					local pos = beltEnd:Lerp(basketPos, q) + up * (math.sin(q * math.pi) * 1.5)
					part.Shape = Enum.PartType.Cylinder; part.Size = Vector3.new(1.4,0.6,0.6); part.CFrame = CFrame.new(pos) * CFrame.Angles(t * 4, 0, 0)
				end
			end
			do -- finished candy piles up in the basket, then resets
				local reveal = math.floor((t * 0.25) % (#pile + 4))
				for i = 1, #pile do pile[i].Transparency = (i <= reveal) and 0 or 1 end
			end
			task.wait(0.05)
		end
	end)

	-- the taffy blob that rides the belt
	local blob = fxPart({ Name = "TaffyBlob", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4,2.4,2.4), Material = Enum.Material.SmoothPlastic })
	local function blobPulse()
		if not blob or not blob.Parent then return end
		TweenService:Create(blob, TweenInfo.new(0.08), { Size = Vector3.new(2.9,2.9,2.9) }):Play()
		task.delay(0.09, function() if blob and blob.Parent then TweenService:Create(blob, TweenInfo.new(0.12), { Size = Vector3.new(2.4,2.4,2.4) }):Play() end end)
	end
	local function moveBlobTo(t)
		local goal = CFrame.new(blobPos(t)) * blob.CFrame.Rotation -- keep the current morph orientation
		local tw = TweenService:Create(blob, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { CFrame = goal })
		tw:Play(); tw.Completed:Wait()
	end

	-- ---- FACTORY HUD ----
	local hud = Instance.new("ScreenGui"); hud.Name = "CandyFactoryHUD"; hud.ResetOnSpawn = false; hud.DisplayOrder = 18; hud.Enabled = false; hud.Parent = PlayerGui
	local shadow = Instance.new("Frame"); shadow.AnchorPoint = Vector2.new(0.5,0.5); shadow.Position = UDim2.new(0.5,0,0.5,6); shadow.Size = UDim2.new(0,484,0,416); shadow.BackgroundColor3 = Color3.fromRGB(70,25,52); shadow.BackgroundTransparency = 0.5; shadow.Parent = hud
	Instance.new("UICorner", shadow).CornerRadius = UDim.new(0,28)
	local panel = Instance.new("Frame"); panel.AnchorPoint = Vector2.new(0.5,0.5); panel.Position = UDim2.new(0.5,0,0.5,0); panel.Size = UDim2.new(0,468,0,400)
	panel.BackgroundColor3 = FILL; panel.Parent = hud
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,24)
	do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 3; s.Parent = panel end
	do local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(Color3.new(1,1,1), Color3.fromRGB(255,236,246)); g.Parent = panel end
	-- coloured header (tinted to the candy flavour) carries the title
	local header = Instance.new("Frame"); header.Size = UDim2.new(1,0,0,56); header.BackgroundColor3 = PINK; header.Parent = panel
	Instance.new("UICorner", header).CornerRadius = UDim.new(0,24)
	local headerFix = Instance.new("Frame"); headerFix.Position = UDim2.new(0,0,1,-16); headerFix.Size = UDim2.new(1,0,0,16); headerFix.BackgroundColor3 = PINK; headerFix.BorderSizePixel = 0; headerFix.Parent = header
	local titleLbl = Instance.new("TextLabel"); titleLbl.BackgroundTransparency = 1; titleLbl.Position = UDim2.new(0,14,0,8); titleLbl.Size = UDim2.new(1,-28,0,40); titleLbl.Font = Enum.Font.FredokaOne; titleLbl.TextColor3 = Color3.new(1,1,1); titleLbl.TextStrokeTransparency = 0.55; titleLbl.TextScaled = true; titleLbl.Parent = header
	Instance.new("UITextSizeConstraint", titleLbl).MaxTextSize = 28
	-- 4 step pills that fill in as you progress
	local stepDots = {}
	local dotRow = Instance.new("Frame"); dotRow.AnchorPoint = Vector2.new(0.5,0); dotRow.Position = UDim2.new(0.5,0,0,62); dotRow.Size = UDim2.new(0,320,0,12); dotRow.BackgroundTransparency = 1; dotRow.Parent = panel
	for i = 1, 4 do
		local dot = Instance.new("Frame"); dot.AnchorPoint = Vector2.new(0.5,0.5); dot.Position = UDim2.new((i-0.5)/4,0,0.5,0); dot.Size = UDim2.new(0,66,0,10); dot.BackgroundColor3 = Color3.fromRGB(236,216,229); dot.Parent = dotRow
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1,0); stepDots[i] = dot
	end
	local function setStepDots(cur) for i, dot in ipairs(stepDots) do dot.BackgroundColor3 = (i <= cur) and GREEN or Color3.fromRGB(236,216,229) end end
	local stepLbl = Instance.new("TextLabel"); stepLbl.BackgroundTransparency = 1; stepLbl.Position = UDim2.new(0,0,0,80); stepLbl.Size = UDim2.new(1,0,0,18); stepLbl.Font = Enum.Font.FredokaOne; stepLbl.TextColor3 = HINTC; stepLbl.TextScaled = true; stepLbl.Parent = panel
	Instance.new("UITextSizeConstraint", stepLbl).MaxTextSize = 15
	local instrLbl = Instance.new("TextLabel"); instrLbl.BackgroundTransparency = 1; instrLbl.Position = UDim2.new(0,12,0,100); instrLbl.Size = UDim2.new(1,-24,0,26); instrLbl.Font = Enum.Font.FredokaOne; instrLbl.TextColor3 = TEXTC; instrLbl.TextScaled = true; instrLbl.TextWrapped = true; instrLbl.Parent = panel
	Instance.new("UITextSizeConstraint", instrLbl).MaxTextSize = 18
	local content = Instance.new("Frame"); content.AnchorPoint = Vector2.new(0.5,0); content.Position = UDim2.new(0.5,0,0,128); content.Size = UDim2.new(0,424,0,236); content.BackgroundTransparency = 1; content.Parent = panel
	local msgLbl = Instance.new("TextLabel"); msgLbl.BackgroundTransparency = 1; msgLbl.Position = UDim2.new(0,0,1,-28); msgLbl.Size = UDim2.new(1,0,0,24); msgLbl.Font = Enum.Font.FredokaOne; msgLbl.TextColor3 = STROKE; msgLbl.TextScaled = true; msgLbl.Text = ""; msgLbl.Parent = panel
	Instance.new("UITextSizeConstraint", msgLbl).MaxTextSize = 20

	local function clearContent() for _, c in ipairs(content:GetChildren()) do c:Destroy() end end
	local msgTok = 0
	local function flashHud(text, secs) msgTok += 1; local t = msgTok; msgLbl.Text = text; task.delay(secs or 1.2, function() if t == msgTok then msgLbl.Text = "" end end) end

	local function bigButton(text, y)
		local b = Instance.new("TextButton"); b.AnchorPoint = Vector2.new(0.5,0); b.Position = UDim2.new(0.5,0,0,y); b.Size = UDim2.new(0,240,0,84)
		b.BackgroundColor3 = PINK; b.Text = text; b.TextColor3 = Color3.new(1,1,1); b.Font = Enum.Font.FredokaOne; b.TextScaled = true; b.AutoButtonColor = true; b.Parent = content
		Instance.new("UICorner", b).CornerRadius = UDim.new(0,16)
		Instance.new("UITextSizeConstraint", b).MaxTextSize = 30
		do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 2; s.Parent = b end
		return b
	end

	-- STEP 1: MIX -- mash the button to fill the bar (it slowly drains)
	local function stepMix()
		instrLbl.Text = "Mash the button to mix the taffy!"
		local track = Instance.new("Frame"); track.AnchorPoint = Vector2.new(0.5,0); track.Position = UDim2.new(0.5,0,0,8); track.Size = UDim2.new(0,340,0,22); track.BackgroundColor3 = Color3.fromRGB(240,220,232); track.Parent = content
		Instance.new("UICorner", track).CornerRadius = UDim.new(1,0)
		do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 2; s.Transparency = 0.4; s.Parent = track end
		local fill = Instance.new("Frame"); fill.Size = UDim2.new(0,0,1,0); fill.BackgroundColor3 = PINK; fill.Parent = track; Instance.new("UICorner", fill).CornerRadius = UDim.new(1,0)
		local btn = bigButton("TAP TO MIX \xF0\x9F\x8C\x80", 52)
		local prog = 0
		local conn = btn.Activated:Connect(function() prog = math.min(1, prog + 0.13); blobPulse() end)
		while prog < 1 do
			prog = math.max(0, prog - 0.012)
			fill.Size = UDim2.new(prog, 0, 1, 0)
			task.wait(0.06)
		end
		fill.Size = UDim2.new(1,0,1,0)
		conn:Disconnect()
	end

	-- STEP 2: COOK -- stop the sweeping needle inside the green zone
	local function stepCook()
		instrLbl.Text = "Press STOP when the arrow hits the green zone!"
		local track = Instance.new("Frame"); track.AnchorPoint = Vector2.new(0.5,0); track.Position = UDim2.new(0.5,0,0,18); track.Size = UDim2.new(0,360,0,30); track.BackgroundColor3 = Color3.fromRGB(240,220,232); track.Parent = content
		Instance.new("UICorner", track).CornerRadius = UDim.new(0,8)
		do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 2; s.Parent = track end
		local c = math.random(35, 65) / 100; local half = 0.10; local lo = math.max(0, c - half); local hi = math.min(1, c + half)
		local green = Instance.new("Frame"); green.Position = UDim2.new(lo,0,0,0); green.Size = UDim2.new(hi - lo, 0, 1, 0); green.BackgroundColor3 = GREEN; green.Parent = track
		Instance.new("UICorner", green).CornerRadius = UDim.new(0,8)
		local needle = Instance.new("Frame"); needle.AnchorPoint = Vector2.new(0.5,0); needle.Size = UDim2.new(0,6,1,0); needle.BackgroundColor3 = Color3.fromRGB(40,30,50); needle.Parent = track
		local btn = bigButton("STOP! \xF0\x9F\x94\xA5", 66)
		local pos, dir, success = 0, 1, false
		local conn = btn.Activated:Connect(function()
			if pos >= lo and pos <= hi then success = true else flashHud("Too hot -- try again!", 1.1) end
		end)
		while not success do
			pos = pos + dir * 0.02
			if pos >= 1 then pos = 1; dir = -1 elseif pos <= 0 then pos = 0; dir = 1 end
			needle.Position = UDim2.new(pos, 0, 0, 0)
			task.wait(0.03)
		end
		conn:Disconnect()
	end

	-- STEP 3: WRAP -- press WRAP when the shrinking ring lines up with the target
	local function stepWrap()
		instrLbl.Text = "Press WRAP when the ring matches the target!"
		local target = Instance.new("Frame"); target.AnchorPoint = Vector2.new(0.5,0.5); target.Position = UDim2.new(0.5,0,0,78); target.Size = UDim2.fromOffset(120,120); target.BackgroundTransparency = 1; target.Parent = content
		Instance.new("UICorner", target).CornerRadius = UDim.new(1,0)
		do local s = Instance.new("UIStroke"); s.Color = GREEN; s.Thickness = 4; s.Parent = target end
		local ring = Instance.new("Frame"); ring.AnchorPoint = Vector2.new(0.5,0.5); ring.Position = UDim2.new(0.5,0,0,78); ring.BackgroundTransparency = 1; ring.Parent = content
		Instance.new("UICorner", ring).CornerRadius = UDim.new(1,0)
		do local s = Instance.new("UIStroke"); s.Color = PINK; s.Thickness = 5; s.Parent = ring end
		local btn = bigButton("WRAP! \xF0\x9F\x8E\x80", 150)
		local px, lo, hi, success = 210, 102, 138, false
		local conn = btn.Activated:Connect(function()
			if px >= lo and px <= hi then success = true else flashHud("Missed -- try again!", 1.1) end
		end)
		while not success do
			px = px - 3
			if px <= 40 then px = 210 end
			ring.Size = UDim2.fromOffset(px, px)
			task.wait(0.03)
		end
		conn:Disconnect()
	end

	-- STEP 3: ROLL -- alternate LEFT/RIGHT to run it through the rollers and flatten it
	local function stepRoll()
		instrLbl.Text = "Alternate LEFT / RIGHT to roll it flat!"
		local track = Instance.new("Frame"); track.AnchorPoint = Vector2.new(0.5,0); track.Position = UDim2.new(0.5,0,0,8); track.Size = UDim2.new(0,340,0,22); track.BackgroundColor3 = Color3.fromRGB(240,220,232); track.Parent = content
		Instance.new("UICorner", track).CornerRadius = UDim.new(1,0)
		do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 2; s.Transparency = 0.4; s.Parent = track end
		local fill = Instance.new("Frame"); fill.Size = UDim2.new(0,0,1,0); fill.BackgroundColor3 = PINK; fill.Parent = track; Instance.new("UICorner", fill).CornerRadius = UDim.new(1,0)
		local function sideBtn(txt, xoff)
			local b = Instance.new("TextButton"); b.AnchorPoint = Vector2.new(0.5,0); b.Position = UDim2.new(0.5,xoff,0,52); b.Size = UDim2.new(0,178,0,96)
			b.BackgroundColor3 = PINK; b.Text = txt; b.TextColor3 = Color3.new(1,1,1); b.Font = Enum.Font.FredokaOne; b.TextScaled = true; b.AutoButtonColor = true; b.Parent = content
			Instance.new("UICorner", b).CornerRadius = UDim.new(0,16); Instance.new("UITextSizeConstraint", b).MaxTextSize = 28
			do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 2; s.Parent = b end
			return b
		end
		local lb, rb = sideBtn("\xE2\x97\x80 ROLL", -110), sideBtn("ROLL \xE2\x96\xB6", 110)
		local prog, expect = 0, nil
		local function press(sd)
			if expect and sd ~= expect then flashHud("Alternate sides!", 0.6); return end
			prog = math.min(1, prog + 0.11); expect = (sd == "L") and "R" or "L"; blobPulse()
		end
		lb.Activated:Connect(function() press("L") end)
		rb.Activated:Connect(function() press("R") end)
		while prog < 1 do prog = math.max(0, prog - 0.01); fill.Size = UDim2.new(prog, 0, 1, 0); task.wait(0.06) end
		fill.Size = UDim2.new(1,0,1,0)
	end

	-- run one taffy through the whole line -- Mixer -> Cooker -> Roller -> Wrapper -> basket.
	-- the blob morphs as it advances: blob -> flattened strip -> wrapped candy -> drops in basket.
	local function runProduction(flavor)
		hud.Enabled = true
		blob.Shape = Enum.PartType.Ball
		blob.Color = flavor.color; blob.Size = Vector3.new(2.4,2.4,2.4); blob.CFrame = CFrame.new(blobPos(0)); blob.Parent = fx
		header.BackgroundColor3 = flavor.color; headerFix.BackgroundColor3 = flavor.color; setStepDots(0)
		local steps = {
			{ emoji = "\xF0\x9F\xA5\xA3", name = "MIXER",   d = -12, fn = stepMix },
			{ emoji = "\xF0\x9F\x94\xA5", name = "COOKER",  d =  -4, fn = stepCook },
			{ emoji = "\xF0\x9F\x93\x8F", name = "ROLLER",  d =   3, fn = stepRoll },
			{ emoji = "\xF0\x9F\x8E\x80", name = "WRAPPER", d =  13, fn = stepWrap },
		}
		for i, s in ipairs(steps) do
			titleLbl.Text = ("%s %s  --  %s"):format(s.emoji, s.name, flavor.name)
			stepLbl.Text = ("Step %d / %d"):format(i, #steps)
			clearContent(); msgLbl.Text = ""
			moveBlobTo((s.d + halfL) / beltLen)
			s.fn()
			if s.name == "ROLLER" then       -- flatten it
				blob.Shape = Enum.PartType.Block; blob.Size = Vector3.new(2.8,0.5,1.6); blob.CFrame = CFrame.new(blob.Position) * rot
			elseif s.name == "WRAPPER" then  -- wrap it
				blob.Shape = Enum.PartType.Cylinder; blob.Size = Vector3.new(2.2,0.9,0.9); blob.CFrame = CFrame.new(blob.Position, blob.Position + side) * CFrame.Angles(0,0,math.rad(90))
			end
			flashHud("\xE2\x9C\x85 " .. s.name .. " done!", 0.9); setStepDots(i)
			task.wait(0.45)
		end
		moveBlobTo(1)
		titleLbl.Text = "\xE2\x9C\x85 " .. flavor.name .. " ready!"
		stepLbl.Text = ""; instrLbl.Text = "Finished candy drops in the basket!"
		clearContent()
		local drop = TweenService:Create(blob, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(basketPos) * blob.CFrame.Rotation })
		drop:Play(); drop.Completed:Wait()
		task.wait(0.7)
		hud.Enabled = false
		blob.Parent = nil
		return true
	end

	print(("[Delivery] factory built on '%s' (belt %d studs)"):format(prod.Name, beltLen))
	return runProduction
end

-- ============================================================================
-- DELIVERY PADS -- built on each islanddelivery, sized to fit inside it
-- ============================================================================
local function deliverStation(st)
	if st.delivered or done then return end
	if not accepted then accepted = true; refreshBanner() end
	if carrying ~= st.idx then
		if not carrying then
			flashBanner("\xF0\x9F\x8F\xAD Make taffy at the factory first!")
			pointTo(productionPos)
		else
			flashBanner(("\xF0\x9F\x93\xA6 This station wants %s!"):format(st.flavor.name))
		end
		return
	end
	st.delivered = true; deliveredCount += 1; carrying = nil; setCarry(nil)
	if st.prompt then st.prompt.Enabled = false end
	if st.pad then st.pad.Color = GREEN end
	if st.pkg then st.pkg.Color = GOLD; st.pkg.Material = Enum.Material.Neon end
	if st.tag then st.tag.Text = "\xE2\x9C\x85 DELIVERED"; st.tag.TextColor3 = GREEN end
	flashBanner("\xF0\x9F\x93\xA6 " .. st.flavor.name .. " delivered!")
	refreshBanner()
	if _G.NotifyCenter then pcall(function() _G.NotifyCenter.push({ text = ("\xF0\x9F\x93\xA6 Order filled (%d/%d)"):format(deliveredCount, requiredStations), color = STROKE }) end) end
	if deliveredCount >= requiredStations then winQuest() else pointTo(productionPos) end
	print(("[Delivery] station %d delivered (%d/%d)"):format(st.idx, deliveredCount, requiredStations))
end

local function buildStation(inst, idx)
	local topPos, sz = topOf(inst)
	local flavor = TAFFY[((idx - 1) % #TAFFY) + 1]
	local horiz = math.min(sz.X, sz.Z)
	local diameter = math.clamp(horiz * 0.5, 6, 40)

	local pad = Instance.new("Part")
	pad.Name = "CandyDeliveryPad"; pad.Anchored = true; pad.CanCollide = false
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.6, diameter, diameter)
	pad.CFrame = CFrame.new(topPos + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Color = flavor.color; pad.Material = Enum.Material.SmoothPlastic
	pad.Parent = inst:IsA("Model") and inst or Workspace

	local box = math.clamp(diameter * 0.32, 2.5, 8)
	local pkg = Instance.new("Part")
	pkg.Name = "CandyOrderBox"; pkg.Anchored = true; pkg.CanCollide = false
	pkg.Size = Vector3.new(box, box, box)
	pkg.CFrame = CFrame.new(topPos + Vector3.new(0, box * 0.5 + 0.7, 0))
	pkg.Color = Color3.fromRGB(190, 130, 90); pkg.Material = Enum.Material.SmoothPlastic
	pkg.Parent = pad
	local ribbon = Instance.new("Part"); ribbon.Anchored = true; ribbon.CanCollide = false
	ribbon.Size = Vector3.new(box * 1.04, box * 0.16, box * 1.04); ribbon.CFrame = pkg.CFrame
	ribbon.Color = flavor.color; ribbon.Material = Enum.Material.Neon; ribbon.Parent = pad

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Deliver"; prompt.ObjectText = "Wants " .. flavor.name; prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = DELIVER_DISTANCE; prompt.RequiresLineOfSight = false; prompt.Parent = pad

	local tag = billboardOn(pkg, "\xF0\x9F\x8D\xAC Wants " .. flavor.name, flavor.color)

	local st = { inst = inst, idx = idx, pad = pad, pkg = pkg, prompt = prompt, tag = tag, pos = topPos, flavor = flavor, delivered = false }
	stations[idx] = st

	task.spawn(function()
		local basecf = pkg.CFrame; local t = idx
		while pkg.Parent and not st.delivered do
			t += 0.05; pkg.CFrame = basecf * CFrame.new(0, math.sin(t) * 0.25, 0) * CFrame.Angles(0, t * 0.5, 0)
			ribbon.CFrame = pkg.CFrame
			task.wait(0.05)
		end
	end)

	prompt.Triggered:Connect(function() deliverStation(st) end)
	print(("[Delivery] station %d built on '%s' wants %s (pad %.0f)"):format(idx, inst.Name, flavor.name, diameter))
end

-- pick the lowest-numbered station you still owe (that's wired in)
nextNeeded = function()
	for i = 1, requiredStations do
		local s = stations[i]
		if s and not s.delivered then return s end
	end
	return nil
end

-- go to the factory and make the next needed taffy
local function makeTaffy()
	if not FactoryRun or done or producing then return end
	if carrying then
		flashBanner("\xF0\x9F\x93\xA6 Deliver your taffy first!")
		if stations[carrying] then pointTo(stations[carrying].pos) end
		return
	end
	if readyFlavor then
		flashBanner("\xF0\x9F\x8D\xAC Take your candy from the basket first!")
		if _G.__candyBasket then pointTo(_G.__candyBasket.pos) end
		return
	end
	local target = nextNeeded()
	if not target then flashBanner("\xF0\x9F\x8D\xAC All taffy delivered!"); return end
	if not accepted then accepted = true end
	producing = true; refreshBanner()
	local ok = FactoryRun(target.flavor)
	producing = false
	if ok and not done then
		readyIdx, readyFlavor = target.idx, target.flavor
		if _G.__candyBasket then _G.__candyBasket.showReady(target.flavor) end
		refreshBanner()
		flashBanner("\xF0\x9F\x8D\xAC Candy ready -- take it from the basket!")
		if _G.__candyBasket then pointTo(_G.__candyBasket.pos) end
	end
end

-- take the finished candy out of the basket -> into your hand
local function takeCandy()
	if not readyFlavor or carrying or done then return end
	local f, idx = readyFlavor, readyIdx
	readyFlavor, readyIdx = nil, nil
	carrying = idx
	setCarry(f)
	if _G.__candyBasket then _G.__candyBasket.hideReady() end
	refreshBanner()
	flashBanner(("\xF0\x9F\x93\xA6 Carry %s to its island!"):format(f.name))
	if stations[carrying] then pointTo(stations[carrying].pos) end
end
_G.__takeCandy = takeCandy

-- ============================================================================
-- NPC DIALOGUE
-- ============================================================================
local function questPages()
	if done then return { "Every order filled -- you're a master candymaker! \xF0\x9F\x8D\xAC" } end
	if accepted then
		if readyFlavor then return { "Your candy is ready -- grab it from the basket!" } end
		if carrying and stations[carrying] then return { ("You're carrying %s -- take it to the island that wants it!"):format(stations[carrying].flavor.name) } end
		if USE_ORCHARD then
			local want = nextNeeded and nextNeeded()
			return {
				("You've filled %d of %d orders."):format(deliveredCount, requiredStations),
				want and ("Next up: shake a %s tree."):format(want.flavor.name) or "Keep going!",
			}
		end
		return { ("You've filled %d of %d orders."):format(deliveredCount, requiredStations), "Make the next taffy at the factory!" }
	end
	if USE_ORCHARD then
		return {
			("The orchard's ripe and we've got %d orders to fill!"):format(requiredStations),
			"Taffy grows on the trees round here -- each tree grows one flavour.",
			"Shake the right tree, catch the taffy, then carry it over the bridges.",
			"Check each island's sign to see which taffy it's waiting for!",
		}
	end
	return {
		("Our candy factory has %d orders to fill!"):format(requiredStations),
		"Make each taffy at the factory, then carry it to the island that wants that flavour.",
		"Check each island's sign to see which taffy it's waiting for!",
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
		if index == 2 and not accepted then
			accepted = true; refreshBanner()
			pointTo(productionPos) -- guide straight to the factory
		end
		local last = index >= #pages
		showBubble(head, pages[index], true, last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages))
		prompt.ActionText = last and "Close" or "Continue"
		watch()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then close() end end)
end

-- ============================================================================
-- THE TAFFY ORCHARD  (replaces the conveyor factory)
-- Trees grow the flavours. Walk up, hold E to shake one, and if it's carrying the
-- flavour your next order needs, the taffy drops straight into your hands.
-- ============================================================================
local orchard = {}   -- { model=, pos=, flavor=, idx=, ripe=bool }

local function groundAt(pos)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local filter = {}
	if player.Character then filter[#filter + 1] = player.Character end
	rp.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(pos + Vector3.new(0, 40, 0), Vector3.new(0, -220, 0), rp)
	return hit and hit.Position or pos
end

local function mkPart(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

-- a candy tree: trunk, canopy, and taffy fruit hanging in this flavour's colour
local function growTree(at, flavor, idx)
	local m = Instance.new("Model"); m.Name = "TaffyTree"
	m:SetAttribute("QuestProp", true)

	local trunk = mkPart({ Name = "Trunk", Size = Vector3.new(1.5, 8, 1.5),
		Color = Color3.fromRGB(120, 78, 46), Material = Enum.Material.Wood, CanCollide = true })
	trunk.CFrame = CFrame.new(at + Vector3.new(0, 4, 0))
	trunk.Parent = m; m.PrimaryPart = trunk

	-- canopy: three overlapping blobs so it isn't one flat sphere
	for i, o in ipairs({ Vector3.new(0, 9.2, 0), Vector3.new(-2.2, 8.2, 1.1), Vector3.new(2.1, 8.4, -1.2) }) do
		local leaf = mkPart({ Name = "Canopy" .. i, Shape = Enum.PartType.Ball,
			Size = Vector3.new(7 - i, 5.4 - i * 0.4, 7 - i),
			Color = Color3.fromRGB(126, 200, 128), Material = Enum.Material.Grass })
		leaf.CFrame = CFrame.new(at + o)
		leaf.Parent = m
	end

	-- the fruit -- coloured to the flavour, so you can tell trees apart at a glance
	local fruits = {}
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2
		local f = mkPart({ Name = "Taffy", Shape = Enum.PartType.Ball, Size = Vector3.new(1.25, 1.25, 1.25),
			Color = flavor.color, Material = Enum.Material.SmoothPlastic, Reflectance = 0.15 })
		f.CFrame = CFrame.new(at + Vector3.new(math.cos(a) * 2.6, 7.4 + (i % 3) * 0.7, math.sin(a) * 2.6))
		f.Parent = m
		fruits[#fruits + 1] = f
	end

	local sign = Instance.new("BillboardGui")
	sign.Name = "TreeSign"; sign.Adornee = trunk; sign.Size = UDim2.new(0, 180, 0, 40)
	sign.StudsOffset = Vector3.new(0, 8.5, 0); sign.AlwaysOnTop = false; sign.MaxDistance = 90
	sign.Parent = trunk
	local sf = Instance.new("Frame"); sf.Size = UDim2.fromScale(1, 1); sf.BackgroundColor3 = FILL
	sf.BackgroundTransparency = 0.1; sf.BorderSizePixel = 0; sf.Parent = sign
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 8); sc.Parent = sf
	local sst = Instance.new("UIStroke"); sst.Color = flavor.color; sst.Thickness = 2; sst.Parent = sf
	local stx = Instance.new("TextLabel"); stx.BackgroundTransparency = 1; stx.Size = UDim2.fromScale(1, 1)
	stx.Font = Enum.Font.FredokaOne; stx.Text = flavor.name; stx.TextColor3 = TEXTC
	stx.TextScaled = true; stx.Parent = sf

	m.Parent = workspace

	local entry = { model = m, pos = at, flavor = flavor, idx = idx, fruits = fruits, ripe = true }

	-- gentle sway so the orchard isn't static
	task.spawn(function()
		local t = idx * 0.8
		local home = m:GetPivot()
		while m.Parent do
			t += 0.03
			m:PivotTo(home * CFrame.Angles(0, 0, math.sin(t) * 0.014))
			task.wait(0.06)
		end
	end)

	trunk.CanQuery = true
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Shake the tree"; prompt.ObjectText = flavor.name
	prompt.HoldDuration = SHAKE_TIME; prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false; prompt.Parent = trunk
	entry.prompt = prompt

	prompt.Triggered:Connect(function()
		if done then return end
		if not accepted then
			flashBanner("\xF0\x9F\x8D\xAC Talk to the Candy Npc first!")
			return
		end
		if carrying then
			flashBanner("\xF0\x9F\x93\xA6 Deliver the taffy you're holding first!")
			if stations[carrying] then pointTo(stations[carrying].pos) end
			return
		end
		if not entry.ripe then
			flashBanner("\xF0\x9F\x8C\xB3 That tree's bare -- give it a minute.")
			return
		end

		-- is this the flavour the next order actually wants?
		local target = nextNeeded()
		if not target then flashBanner("\xF0\x9F\x8D\xAC All taffy delivered!"); return end
		if target.flavor.name ~= flavor.name then
			flashBanner(("\xF0\x9F\x8D\xAC They want %s -- find that tree!"):format(target.flavor.name))
			-- point at a tree of the right flavour
			for _, t in ipairs(orchard) do
				if t.flavor.name == target.flavor.name and t.ripe then pointTo(t.pos); break end
			end
			return
		end

		-- SHAKE: the tree wobbles, fruit falls, and you catch one
		entry.ripe = false
		prompt.Enabled = false
		local home = m:GetPivot()
		task.spawn(function()
			for i = 1, 14 do
				m:PivotTo(home * CFrame.Angles(0, 0, math.sin(i * 1.6) * 0.07 * (1 - i / 16)))
				task.wait(0.04)
			end
			m:PivotTo(home)
		end)

		for i, f in ipairs(fruits) do
			task.delay(i * 0.05, function()
				if not f.Parent then return end
				local land = groundAt(f.Position)
				f.CanCollide = false
				TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = CFrame.new(Vector3.new(f.Position.X, land.Y + 0.7, f.Position.Z)) }):Play()
				task.delay(0.55, function()
					TweenService:Create(f, TweenInfo.new(0.35), { Transparency = 1, Size = f.Size * 0.3 }):Play()
				end)
			end)
		end

		task.delay(0.75, function()
			if done or carrying then return end
			carrying = target.idx
			setCarry(target.flavor)
			refreshBanner()
			flashBanner(("\xF0\x9F\x93\xA6 Picked %s -- carry it to its island!"):format(target.flavor.name))
			if stations[carrying] then pointTo(stations[carrying].pos) end
		end)

		-- the tree regrows so you can never run out
		task.delay(9, function()
			entry.ripe = true
			if prompt then prompt.Enabled = true end
			for _, f in ipairs(fruits) do
				if f.Parent then
					f.Transparency = 0
					f.Size = Vector3.new(1.25, 1.25, 1.25)
				end
			end
			-- put them back on the branches
			for i, f in ipairs(fruits) do
				if f.Parent then
					local a = (i / #fruits) * math.pi * 2
					f.CFrame = CFrame.new(at + Vector3.new(math.cos(a) * 2.6, 7.4 + (i % 3) * 0.7, math.sin(a) * 2.6))
				end
			end
		end)
	end)

	orchard[#orchard + 1] = entry
	return entry
end

buildOrchard = function(prod)
	-- prefer trees you placed yourself
	local placed = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) then
			local n = string.lower(d.Name):gsub("[%s_%-]", "")
			for _, want in ipairs(TREE_NAMES) do
				if string.find(n, want, 1, true) then
					local bp = firstBasePart(d)
					if bp then
						placed[#placed + 1] = bp.Position
						-- the marker is a POSITION ANCHOR, not scenery: hide it, or you just
						-- see your block sitting where the tree should be
						for _, q in ipairs(d:IsA("Model") and d:GetDescendants() or { d }) do
							if q:IsA("BasePart") then
								q.Transparency = 1; q.CanCollide = false; q.CanQuery = false
							end
						end
					end
					break
				end
			end
		end
	end

	local centre = productionPos or (firstBasePart(prod) and firstBasePart(prod).Position)
	if not centre then warn("[Delivery] no production spot position -- orchard not grown"); return end

	local grown, haveFlavor = 0, {}
	for i, pos in ipairs(placed) do
		local flavor = TAFFY[((i - 1) % #TAFFY) + 1]
		growTree(groundAt(pos), flavor, i)
		haveFlavor[flavor.name] = true
		grown += 1
	end

	-- EVERY flavour needs at least one tree, or that order can never be filled. With
	-- fewer markers than flavours (or none at all) the rest get grown around the
	-- production spot automatically.
	local missing = {}
	for _, f in ipairs(TAFFY) do
		if not haveFlavor[f.name] then missing[#missing + 1] = f end
	end
	if #missing > 0 then
		local perFlavor = (#placed > 0) and 1 or TREES_PER_FLAVOR
		local total, idx = #missing * perFlavor, 0
		for _, f in ipairs(missing) do
			for _ = 1, perFlavor do
				idx += 1
				local a = (idx / total) * math.pi * 2
				local r = ORCHARD_RADIUS * (0.6 + ((idx % 3) * 0.2))
				growTree(groundAt(centre + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)), f, grown + idx)
				grown += 0   -- counted below
			end
		end
		grown += idx
		print(("[Delivery] orchard: %d marker tree(s) + %d auto-grown (flavours with no marker)"):format(#placed, idx))
	else
		print(("[Delivery] orchard: %d tree(s) grown on your markers"):format(#placed))
	end

	-- the old factory pad becomes a simple orchard sign
	local base = firstBasePart(prod)
	if base then billboardOn(base, "\xF0\x9F\x8C\xB3 TAFFY ORCHARD", STROKE) end
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	local prod = pollFor(findProduction, 30)
	if prod then
		productionPos = topOf(prod)
		if USE_ORCHARD then
			-- NO FACTORY: the taffy grows on trees around the island instead
			local okO, err = pcall(buildOrchard, prod)
			if not okO then warn("[Delivery] orchard build failed: " .. tostring(err)) end
		else
			local okF, run = pcall(buildFactory, prod)   -- never let a build hiccup kill the NPC wiring below
			if okF then FactoryRun = run else warn("[Delivery] factory build failed: " .. tostring(run)) end
			local base = firstBasePart(prod)
			if base then
				local prompt = Instance.new("ProximityPrompt")
				prompt.ActionText = "Make Taffy"; prompt.ObjectText = "Candy Factory"; prompt.HoldDuration = 0.3
				prompt.MaxActivationDistance = 16; prompt.RequiresLineOfSight = false; prompt.Parent = base
				prompt.Triggered:Connect(function() task.spawn(makeTaffy) end)
				billboardOn(base, "\xF0\x9F\x8F\xAD CANDY FACTORY", STROKE)
			end
			print(("[Delivery] production spot '%s' wired (factory %s)"):format(prod.Name, FactoryRun and "built" or "FAILED"))
		end
	else
		warn("[Delivery] no object named 'production spot' (or containing 'production'/'factory') found in Workspace")
	end

	-- NPC: nearest the factory, or nearest a delivery island if the factory wasn't located
	npcHead = pollFor(function()
		local ref = productionPos
		if not ref then for _, s in ipairs(stations) do if s.pos then ref = s.pos; break end end end
		return findNPCNear(ref)
	end, 30)
	if npcHead then wireNPC(npcHead); print("[Delivery] Candy Npc wired") else warn("[Delivery] no 'Candy Npc' found in Workspace") end

	refreshBanner()
end)

-- STREAMING-SAFE: keep scanning for islanddelivery islands and wire each new one
task.spawn(function()
	local wired = {}
	local nextIdx = 0
	while true do
		for _, d in ipairs(Workspace:GetDescendants()) do
			if not wired[d] and (d:IsA("Model") or d:IsA("BasePart")) and string.lower(d.Name) == ISLAND_NAME then
				wired[d] = true
				nextIdx += 1
				if nextIdx > requiredStations then requiredStations = nextIdx end
				local ok = pcall(buildStation, d, nextIdx)
				if not ok then nextIdx -= 1; wired[d] = nil end
				refreshBanner()
			end
		end
		task.wait(1)
	end
end)

-- ============================================================================
-- /complete -- test command: instantly finish (near the factory)
-- ============================================================================
local function onCommand(msg)
	if tostring(msg or ""):lower():sub(1, 9) ~= "/complete" then return end
	-- only completes when you're actually ON island5 (near its NPC), so /complete typed on
	-- another island never fires this quest's banner/win. No NPC found yet -> stay silent.
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (npcHead and npcHead.Parent and hrp) then return end
	if (hrp.Position - npcHead.Position).Magnitude > BANNER_RANGE then return end
	accepted = true
	for _, s in ipairs(stations) do s.delivered = true; if s.prompt then s.prompt.Enabled = false end end
	deliveredCount = requiredStations
	winQuest()
	print("[Delivery][TEST] /complete -- factory + route skipped")
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m) if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
