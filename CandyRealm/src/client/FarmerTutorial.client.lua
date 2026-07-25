-- ===== FARMER TUTORIAL DIALOG (client) =====
-- Shows the Farmer's tutorial lines in a readable, dismissible on-screen dialog when the LOCAL player
-- triggers his ProximityPrompt (created server-side in FarmerNPC.server.lua). Per-player + client-only,
-- sized with Scale + TextScaled so it reads well on mobile and PC. Cycles the lines with a Next button.
-- Pure UI — changes nothing about flight, balance, islands, costs, food, earn rate, or test flags.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local LINES = {
	"\xC2\xA1Hola, amigo! Welcome to Fart to Float!",
	"Buy food from the stand to fill your GAS METER.",
	"Then hit the FART button to blast off and fly up!",
	"Land on the next island to unlock it and keep climbing.",
	"Earn coins by flying high \xE2\x80\x94 save up for a BIGGER STOMACH to fly even higher!",
	"Good luck, partner! See you at the top!",
}

-- ===== dialog UI (built once, hidden until triggered) =====
local gui = Instance.new("ScreenGui")
gui.Name = "FarmerTutorialGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 60 -- above the HUD, below the shop popups
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.3) -- upper-centre: clear of the bottom controls and the NPC in view
panel.Size = UDim2.fromScale(0.62, 0.26)
panel.BackgroundColor3 = Color3.fromRGB(255, 244, 214)
panel.Visible = false
panel.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 18); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(120, 80, 30); s.Thickness = 4; s.Parent = panel
	local a = Instance.new("UIAspectRatioConstraint"); a.AspectRatio = 2.6; a.DominantAxis = Enum.DominantAxis.Width; a.Parent = panel
end

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0); title.Position = UDim2.fromScale(0.5, 0.06); title.Size = UDim2.fromScale(0.9, 0.2)
title.BackgroundTransparency = 1; title.Font = Enum.Font.FredokaOne; title.Text = "\xF0\x9F\x8C\xBE Farmer"
title.TextColor3 = Color3.fromRGB(90, 55, 20); title.TextScaled = true; title.Parent = panel

local body = Instance.new("TextLabel")
body.Name = "Body"
body.AnchorPoint = Vector2.new(0.5, 0.5); body.Position = UDim2.fromScale(0.5, 0.46); body.Size = UDim2.fromScale(0.88, 0.42)
body.BackgroundTransparency = 1; body.Font = Enum.Font.FredokaOne; body.Text = ""
body.TextColor3 = Color3.fromRGB(50, 35, 15); body.TextScaled = true; body.TextWrapped = true; body.Parent = panel

local nextBtn = Instance.new("TextButton")
nextBtn.Name = "Next"
nextBtn.AnchorPoint = Vector2.new(1, 1); nextBtn.Position = UDim2.fromScale(0.95, 0.92); nextBtn.Size = UDim2.fromScale(0.34, 0.24)
nextBtn.BackgroundColor3 = Color3.fromRGB(80, 200, 90); nextBtn.Font = Enum.Font.FredokaOne; nextBtn.Text = "Next \xE2\x96\xB6"
nextBtn.TextColor3 = Color3.fromRGB(255, 255, 255); nextBtn.TextScaled = true; nextBtn.AutoButtonColor = true; nextBtn.Parent = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = nextBtn
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(0, 0, 0); s.Thickness = 2; s.Parent = nextBtn
end

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0); closeBtn.Position = UDim2.fromScale(0.98, 0.02); closeBtn.Size = UDim2.fromScale(0.12, 0.16)
closeBtn.BackgroundColor3 = Color3.fromRGB(230, 80, 80); closeBtn.Font = Enum.Font.FredokaOne; closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(0, 0, 0); closeBtn.TextScaled = true; closeBtn.AutoButtonColor = true; closeBtn.Parent = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = closeBtn
end

-- ===== behaviour =====
local index = 0
local function showLine(i)
	index = math.clamp(i, 1, #LINES)
	body.Text = LINES[index]
	nextBtn.Text = (index >= #LINES) and "Got it! \xF0\x9F\x91\x8D" or "Next \xE2\x96\xB6"
	panel.Visible = true
end
local function closeDialog() panel.Visible = false end

nextBtn.Activated:Connect(function()
	if _G.playUIClick then pcall(_G.playUIClick) end
	if index >= #LINES then closeDialog() else showLine(index + 1) end
end)
closeBtn.Activated:Connect(function()
	if _G.playUIClick then pcall(_G.playUIClick) end
	closeDialog()
end)

-- Opening: fires locally when THIS player triggers the Farmer's prompt -> start at line 1.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt and prompt.Name == "FarmerTutorialPrompt" then
		showLine(1)
	end
end)
