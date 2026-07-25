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

local function buildHUD()
	gui = Instance.new("ScreenGui")
	gui.Name = "GardenRewardGui"; gui.ResetOnSpawn = false; gui.DisplayOrder = 100; gui.Enabled = false; gui.Parent = PlayerGui

	-- dim click-catcher backdrop (click outside closes)
	local backdrop = mkButton(gui, { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, Active = true })
	backdrop.MouseButton1Click:Connect(function() gui.Enabled = false end)

	-- PANEL (blue modal -- same style as the Premium / Stomach shop panels)
	panel = mkFrame(gui, { Size = UDim2.new(0.62, 0, 0.66, 0), Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(25, 90, 185), ClipsDescendants = true, Active = true })
	mkCorner(panel, 20); mkStroke(panel, Color3.new(1, 1, 1), 3)

	-- HEADER
	local header = mkFrame(panel, { Size = UDim2.new(1, 0, 0, 60), BackgroundColor3 = Color3.fromRGB(15, 60, 140) }); mkCorner(header, 20)
	mkFrame(header, { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -22), BackgroundColor3 = Color3.fromRGB(15, 60, 140) }) -- square the header's bottom edge
	mkLabel(header, { Text = "\xF0\x9F\x8E\x81 Garden Reward", Font = Enum.Font.FredokaOne, TextSize = 28, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -120, 1, 0), Position = UDim2.new(0, 20, 0, 0), TextXAlignment = Enum.TextXAlignment.Left })
	local closeBtn = mkButton(header, { Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(1, -48, 0, 10), BackgroundColor3 = Color3.fromRGB(220, 50, 50), Text = "\xe2\x9c\x95", Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = Color3.new(1, 1, 1) }); mkCorner(closeBtn, 8)
	closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false end)

	-- PET CARD (shows the offered pet)
	local card = mkFrame(panel, { Size = UDim2.new(0.74, 0, 0, 150), Position = UDim2.new(0.5, 0, 0, 86), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(20, 70, 160) }); mkCorner(card, 14); mkStroke(card, Color3.fromRGB(120, 180, 255), 2)
	mkLabel(card, { Text = "\xF0\x9F\x90\xBE", Font = Enum.Font.GothamBold, TextSize = 70, Size = UDim2.new(0, 110, 1, -16), Position = UDim2.new(0, 12, 0, 8), TextXAlignment = Enum.TextXAlignment.Center })
	petNameLbl = mkLabel(card, { Text = "Garden Pet", Font = Enum.Font.GothamBold, TextSize = 28, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -140, 0, 40), Position = UDim2.new(0, 132, 0, 34), TextXAlignment = Enum.TextXAlignment.Left })
	mkLabel(card, { Text = "The Global-Goal Pet", Font = Enum.Font.Gotham, TextSize = 17, TextColor3 = Color3.fromRGB(180, 210, 255), Size = UDim2.new(1, -140, 0, 26), Position = UDim2.new(0, 132, 0, 78), TextXAlignment = Enum.TextXAlignment.Left })

	-- STATE BODY
	stateLbl = mkLabel(panel, { Text = "", Font = Enum.Font.GothamBold, TextSize = 21, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0.86, 0, 0, 80), Position = UDim2.new(0.5, 0, 0, 252), AnchorPoint = Vector2.new(0.5, 0), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })
	daysLbl = mkLabel(panel, { Text = "", Font = Enum.Font.Gotham, TextSize = 16, TextColor3 = Color3.fromRGB(185, 215, 255), Size = UDim2.new(0.86, 0, 0, 24), Position = UDim2.new(0.5, 0, 0, 332), AnchorPoint = Vector2.new(0.5, 0), TextXAlignment = Enum.TextXAlignment.Center })

	-- COLLECT BUTTON
	collectBtn = mkButton(panel, { Size = UDim2.new(0, 280, 0, 58), Position = UDim2.new(0.5, 0, 1, -28), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Color3.fromRGB(50, 200, 50), Text = "Collect", Font = Enum.Font.GothamBold, TextSize = 23, TextColor3 = Color3.new(1, 1, 1) }); mkCorner(collectBtn, 12); mkStroke(collectBtn, Color3.fromRGB(30, 140, 30), 2)
	collectBtn.MouseButton1Click:Connect(function() onCollect() end)
end

function renderState(s)
	s = (type(s) == "table") and s or { state = "none" }
	petNameLbl.Text = s.petName or "Garden Pet"
	if s.state == "ready" then
		stateLbl.Text = "\xF0\x9F\x8E\x89 Your garden reward is ready \xE2\x80\x94 collect your pet!"
		collectBtn.Visible = true; collectBtn.Active = true; collectBtn.AutoButtonColor = true
		collectBtn.Text = "Collect"; collectBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
		local secs = tonumber(s.secsLeft) or 0
		if secs > 0 then daysLbl.Text = string.format("Claimable for %dd %dh", math.floor(secs / 86400), math.floor((secs % 86400) / 3600)) else daysLbl.Text = "" end
	elseif s.state == "claimed" then
		stateLbl.Text = "\xE2\x9C\x85 Already collected! Come back when the garden reaches its next goal."
		collectBtn.Visible = true; collectBtn.Active = false; collectBtn.AutoButtonColor = false
		collectBtn.Text = "Collected"; collectBtn.BackgroundColor3 = Color3.fromRGB(95, 115, 145)
		daysLbl.Text = ""
	elseif s.state == "expired" then
		stateLbl.Text = "\xE2\x8C\x9B Reward expired. Come back when the garden reaches its next goal!"
		collectBtn.Visible = false; daysLbl.Text = ""
	else -- "none"
		stateLbl.Text = "No reward ready yet \xE2\x80\x94 keep growing the garden! \xF0\x9F\x8C\xBB"
		collectBtn.Visible = false; daysLbl.Text = ""
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
