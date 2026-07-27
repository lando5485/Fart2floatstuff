--======================================================================
-- GardenChestClient.client.lua  (LocalScript)  -- the RewardChest E-prompt -> Garden Reward HUD.
--======================================================================
-- Holding E on the RewardChest's "RewardChestPrompt" (server-created) opens a native-styled blue reward panel
-- (same frame/corner/stroke/header/close styling + fonts as the Shop panels). The panel asks the server for the
-- player's reward state and shows the global-goal pet with a state-driven body: Collect (ready) / Already collected
-- / No reward yet / Reward expired. Collecting calls the server claim (server-authoritative grant). Cosmetic UI only.
--======================================================================

local Players              = game:GetService("Players")
local RS                   = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace            = game:GetService("Workspace")
local Debris               = game:GetService("Debris")
local TweenService         = game:GetService("TweenService")   -- panel pop-in

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local GardenChestState = RS:WaitForChild("GardenChestState", 30)
local GardenChestClaim = RS:WaitForChild("GardenChestClaim", 30)
if not (GardenChestState and GardenChestClaim) then return end

-- ===== UI helpers (same ones the shop panels use) =====
local function mkCorner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p; return c end
local function mkStroke(p, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = p; return s end
local function mkLabel(p, props) local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; for k, v in pairs(props) do l[k] = v end; l.Parent = p; return l end
local function mkFrame(p, props) local f = Instance.new("Frame"); for k, v in pairs(props) do f[k] = v end; f.Parent = p; return f end
local function mkButton(p, props) local b = Instance.new("TextButton"); for k, v in pairs(props) do b[k] = v end; b.Parent = p; return b end

-- forward-declared UI handles + functions
local gui, panel, petNameLbl, stateLbl, daysLbl, collectBtn
local renderState, onCollect

-- Same chrome as the donation chest panel next door, so the two chests feel like one pair: fixed 700x520 at the
-- shops' centre, the shared adaptive UIScale (min(vp.X/1280, vp.Y/720, 1)), a navy drop shadow and a thick
-- white cartoon border. It used to be sized in SCALE (0.62 x 0.66), so it was a different shape on every screen.
local function hudScale(frame)
	local s = Instance.new("UIScale"); s.Parent = frame
	local function apply()
		local cam = Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		s.Scale = math.min(vp.X / 1280, vp.Y / 720, 1)
	end
	apply()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
	end
	return s
end

local function dropShadow(frame, radius)
	for i, sp in ipairs({ 54, 30 }) do
		local sh = mkFrame(frame.Parent, {
			AnchorPoint = frame.AnchorPoint,
			Position = UDim2.new(frame.Position.X.Scale, frame.Position.X.Offset, frame.Position.Y.Scale, frame.Position.Y.Offset + 6),
			Size = UDim2.new(0, frame.Size.X.Offset + sp, 0, frame.Size.Y.Offset + sp),
			BackgroundColor3 = Color3.fromRGB(6, 26, 80), BackgroundTransparency = ({ 0.8, 0.62 })[i],
			BorderSizePixel = 0, ZIndex = 0,
		})
		mkCorner(sh, radius + sp)
	end
end

local petGlow, collectScale -- animated bits renderState/openHUD drive

local function buildHUD()
	gui = Instance.new("ScreenGui")
	gui.Name = "GardenRewardGui"; gui.ResetOnSpawn = false; gui.DisplayOrder = 100; gui.Enabled = false; gui.Parent = PlayerGui

	-- dim click-catcher backdrop: it swallows clicks that land off the panel, but does NOT close it
	local backdrop = mkButton(gui, { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(6, 26, 80), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, Active = true })
	-- NOTE: there is deliberately NO click-outside-to-close handler (matching the Pet Hub). The backdrop spans
	-- the whole screen, so a click anywhere off the panel used to slam it shut, which made menus feel like they
	-- closed at random. This panel now closes ONLY on its X button.

	-- PANEL
	panel = mkFrame(gui, {
		Size = UDim2.new(0, 700, 0, 520), Position = UDim2.new(0.5, 0, 0.5, -45), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(26, 79, 214), ClipsDescendants = true, Active = true, ZIndex = 2,
	})
	mkCorner(panel, 24); mkStroke(panel, Color3.new(1, 1, 1), 4)
	do local g = Instance.new("UIGradient", panel); g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(46, 122, 226), Color3.fromRGB(14, 59, 176)) end
	dropShadow(panel, 24)
	hudScale(panel)

	-- HEADER -- gold, matching the donation chest
	local header = mkFrame(panel, { Size = UDim2.new(1, -28, 0, 66), Position = UDim2.new(0, 14, 0, 14), BackgroundColor3 = Color3.fromRGB(255, 200, 60), ZIndex = 3 })
	mkCorner(header, 16); mkStroke(header, Color3.new(1, 1, 1), 2)
	do local g = Instance.new("UIGradient", header); g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(255, 226, 140), Color3.fromRGB(232, 172, 36)) end
	local badge = mkFrame(header, { Size = UDim2.new(0, 46, 0, 46), Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.fromRGB(255, 248, 224), ZIndex = 4 })
	mkCorner(badge, 12); mkStroke(badge, Color3.fromRGB(180, 120, 20), 2)
	mkLabel(badge, { Text = "\xF0\x9F\x8E\x81", Font = Enum.Font.FredokaOne, TextSize = 26, Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 })
	mkLabel(header, { Text = "GARDEN REWARD", Font = Enum.Font.FredokaOne, TextSize = 30, TextColor3 = Color3.fromRGB(84, 48, 4), Size = UDim2.new(1, -190, 1, 0), Position = UDim2.new(0, 70, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	local closeBtn = mkButton(header, { AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(1, -10, 0.5, 0), BackgroundColor3 = Color3.fromRGB(232, 72, 84), Text = "X", Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), ZIndex = 5 })
	mkCorner(closeBtn, 12); mkStroke(closeBtn, Color3.new(1, 1, 1), 2)
	do local cp = Instance.new("UIPadding", closeBtn); for _, s in ipairs({"PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"}) do cp[s] = UDim.new(0, 9) end end
	closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false end)

	-- PET CARD -- the pet is the whole point of this panel, so it gets a big lit tile instead of a small emoji
	local card = mkFrame(panel, { Size = UDim2.new(0, 620, 0, 176), Position = UDim2.new(0.5, 0, 0, 96), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(30, 96, 210), ZIndex = 3 })
	mkCorner(card, 18); mkStroke(card, Color3.new(1, 1, 1), 2.5)
	do local g = Instance.new("UIGradient", card); g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(58, 132, 244), Color3.fromRGB(24, 82, 190)) end

	local tile = mkFrame(card, { Size = UDim2.new(0, 132, 0, 132), Position = UDim2.new(0, 20, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.fromRGB(70, 150, 250), ZIndex = 4 })
	mkCorner(tile, 20); mkStroke(tile, Color3.new(1, 1, 1), 3)
	do local g = Instance.new("UIGradient", tile); g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(120, 196, 255), Color3.fromRGB(36, 104, 214)) end
	-- soft glow disc behind the paw; renderState brightens it when the reward is actually claimable
	petGlow = mkFrame(tile, { Size = UDim2.new(0.84, 0, 0.84, 0), Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(200, 232, 255), BackgroundTransparency = 0.62, BorderSizePixel = 0, ZIndex = 4 })
	mkCorner(petGlow, 999)
	mkLabel(tile, { Text = "\xF0\x9F\x90\xBE", Font = Enum.Font.FredokaOne, TextSize = 74, Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 })
	for _, sp in ipairs({ { 0.12, 0.16 }, { 0.88, 0.22 }, { 0.18, 0.86 }, { 0.86, 0.82 } }) do
		local dot = mkFrame(tile, { Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(sp[1], 0, sp[2], 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 6 })
		mkCorner(dot, 999)
	end

	petNameLbl = mkLabel(card, { Text = "Garden Pet", Font = Enum.Font.FredokaOne, TextSize = 34, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -186, 0, 42), Position = UDim2.new(0, 172, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	do local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(10, 44, 110); ts.Thickness = 2.5
		ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; ts.LineJoinMode = Enum.LineJoinMode.Round; ts.Parent = petNameLbl end
	local sub = mkFrame(card, { Size = UDim2.new(0, 216, 0, 30), Position = UDim2.new(0, 172, 0, 90), BackgroundColor3 = Color3.fromRGB(255, 210, 74), ZIndex = 4 })
	mkCorner(sub, 15); mkStroke(sub, Color3.new(1, 1, 1), 1.5)
	mkLabel(sub, { Text = "\xE2\xAD\x90 THE GLOBAL-GOAL PET", Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = Color3.fromRGB(96, 58, 4), Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 })

	-- STATE BODY
	stateLbl = mkLabel(panel, { Text = "", Font = Enum.Font.FredokaOne, TextSize = 22, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0, 600, 0, 72), Position = UDim2.new(0.5, 0, 0, 290), AnchorPoint = Vector2.new(0.5, 0), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	daysLbl = mkLabel(panel, { Text = "", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.fromRGB(206, 232, 255), Size = UDim2.new(0, 600, 0, 24), Position = UDim2.new(0.5, 0, 0, 366), AnchorPoint = Vector2.new(0.5, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })

	-- COLLECT BUTTON -- big, lime, white-bordered: the one thing to press
	collectBtn = mkButton(panel, { Size = UDim2.new(0, 320, 0, 64), Position = UDim2.new(0.5, 0, 1, -28), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Color3.fromRGB(126, 217, 87), Text = "COLLECT", Font = Enum.Font.FredokaOne, TextSize = 28, TextColor3 = Color3.new(1, 1, 1), ZIndex = 4 })
	mkCorner(collectBtn, 16); mkStroke(collectBtn, Color3.new(1, 1, 1), 3)
	do local g = Instance.new("UIGradient", collectBtn); g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(182, 244, 130), Color3.fromRGB(74, 168, 42)) end
	collectScale = Instance.new("UIScale"); collectScale.Parent = collectBtn
	collectBtn.MouseButton1Click:Connect(function() onCollect() end)

	-- a slow heartbeat on the button + glow while the reward is claimable (renderState flips `claimable`)
	task.spawn(function()
		while collectBtn and collectBtn.Parent do
			if gui.Enabled and collectBtn:GetAttribute("Claimable") then
				collectScale.Scale = 1 + 0.035 * math.sin(os.clock() * 3.2)
				petGlow.BackgroundTransparency = 0.42 + 0.12 * math.sin(os.clock() * 2.4)
			else
				collectScale.Scale = 1
				petGlow.BackgroundTransparency = 0.62
			end
			task.wait(0.05)
		end
	end)
end

-- Recolour the collect button. It carries a UIGradient now, which MULTIPLIES the fill -- so setting only
-- BackgroundColor3 (as this used to) would leave a claimed button still tinted lime.
local function paintCollect(top, bottom)
	local g = collectBtn:FindFirstChildOfClass("UIGradient")
	collectBtn.BackgroundColor3 = bottom
	if g then g.Color = ColorSequence.new(top, bottom) end
end

function renderState(s)
	s = (type(s) == "table") and s or { state = "none" }
	petNameLbl.Text = s.petName or "Garden Pet"
	if s.state == "ready" then
		stateLbl.Text = "\xF0\x9F\x8E\x89 Your garden reward is ready \xE2\x80\x94 collect your pet!"
		collectBtn.Visible = true; collectBtn.Active = true; collectBtn.AutoButtonColor = true
		collectBtn.Text = "COLLECT"
		paintCollect(Color3.fromRGB(182, 244, 130), Color3.fromRGB(74, 168, 42))
		collectBtn:SetAttribute("Claimable", true)   -- drives the pulse + the pet glow
		local secs = tonumber(s.secsLeft) or 0
		if secs > 0 then daysLbl.Text = string.format("\xE2\x8F\xB3 Claimable for %dd %dh", math.floor(secs / 86400), math.floor((secs % 86400) / 3600)) else daysLbl.Text = "" end
	elseif s.state == "claimed" then
		stateLbl.Text = "\xE2\x9C\x85 Already collected! Come back when the garden reaches its next goal."
		collectBtn.Visible = true; collectBtn.Active = false; collectBtn.AutoButtonColor = false
		collectBtn.Text = "COLLECTED"
		paintCollect(Color3.fromRGB(146, 178, 220), Color3.fromRGB(84, 118, 168))
		collectBtn:SetAttribute("Claimable", false)
		daysLbl.Text = ""
	elseif s.state == "expired" then
		stateLbl.Text = "\xE2\x8C\x9B Reward expired. Come back when the garden reaches its next goal!"
		collectBtn.Visible = false; collectBtn:SetAttribute("Claimable", false); daysLbl.Text = ""
	else -- "none"
		stateLbl.Text = "No reward ready yet \xE2\x80\x94 keep growing the garden! \xF0\x9F\x8C\xBB"
		collectBtn.Visible = false; collectBtn:SetAttribute("Claimable", false); daysLbl.Text = ""
	end
end

local busy = false
function onCollect()
	if busy or not (collectBtn.Active) then return end
	busy = true
	collectBtn.Text = "..."; collectBtn.Active = false; collectBtn.AutoButtonColor = false
	local ok, res = pcall(function() return GardenChestClaim:InvokeServer() end)
	busy = false
	renderState(ok and res or { state = "none" })
end

-- a quick gold sparkle at the chest when it's opened (cosmetic)
local function sparkle(pos)
	local host = Instance.new("Part")
	host.Anchored = true; host.CanCollide = false; host.CanQuery = false; host.Transparency = 1
	host.Size = Vector3.new(1, 1, 1); host.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0)); host.Parent = Workspace
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(Color3.fromRGB(255, 225, 90), Color3.fromRGB(255, 180, 40))
	em.Lifetime = NumberRange.new(0.5, 0.95); em.Speed = NumberRange.new(5, 11); em.SpreadAngle = Vector2.new(70, 70)
	em.Rate = 0; em.Size = NumberSequence.new(0.6); em.LightEmission = 0.6; em.Parent = host
	em:Emit(36)
	Debris:AddItem(host, 1.3)
end

local function openHUD(promptPart)
	if not gui then buildHUD() end
	gui.Enabled = true
	-- pop in, like every other menu
	panel.Size = UDim2.new(0, 660, 0, 490)
	TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 700, 0, 520) }):Play()
	renderState({ state = "none", petName = "Garden Pet" }) -- placeholder while the request is in flight
	if promptPart then pcall(function() sparkle(promptPart.Position) end) end
	task.spawn(function()
		local ok, s = pcall(function() return GardenChestState:InvokeServer() end)
		if gui.Enabled and ok then renderState(s) end
	end)
end

-- PromptTriggered fires on THIS client for the local player's triggers -> open the reward HUD for our chest prompt.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt and prompt.Name == "RewardChestPrompt" then
		openHUD(prompt.Parent and prompt.Parent:IsA("BasePart") and prompt.Parent or nil)
	end
end)
