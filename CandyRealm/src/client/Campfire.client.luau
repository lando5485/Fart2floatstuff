--======================================================================
-- Campfire.client.luau  (LocalScript)   [Bean Island]
--======================================================================
-- Purely feedback for the AFK campfire. The server (Campfire.server.lua) does ALL the work -- builds the
-- fire, decides who's resting, and credits the coins. Here we just show a cozy "warming up" pill while the
-- server says this player is resting, so idling by the fire feels like it's doing something. If this script
-- never runs, the campfire still works; you just don't get the pill.
--
-- Driven entirely by two attributes the server sets on the player: CampfireResting (bool) and CampfireRate
-- (coins per tick). No remotes, no polling of the world.
--======================================================================
local Players = game:GetService("Players")
local player  = Players.LocalPlayer
local gui     = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "CampfireHud"; screen.ResetOnSpawn = false; screen.IgnoreGuiInset = true
screen.DisplayOrder = 40; screen.Parent = gui

-- (the "Warming up +1" resting pill was removed -- resting still quietly credits coins server-side)

--======================================================================
-- ROASTING BUTTONS: Go / Stop / Eat, shown only while you're holding the Marshmallow Stick.
-- The buttons just fire the server; it owns the cooking + eating.
--======================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local stickRemote = ReplicatedStorage:WaitForChild("CampfireStick", 30)

if stickRemote then
	local bar = Instance.new("Frame")
	bar.Name = "RoastBar"; bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 0.86, 0)
	bar.Size = UDim2.fromOffset(330, 60)
	bar.BackgroundTransparency = 1
	bar.Visible = false
	bar.Parent = screen
	local row = Instance.new("UIListLayout", bar)
	row.FillDirection = Enum.FillDirection.Horizontal; row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center; row.Padding = UDim.new(0, 10)

	local function mkBtn(text, color)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(100, 54); b.AutoButtonColor = true
		b.BackgroundColor3 = color; b.Text = text
		b.Font = Enum.Font.FredokaOne; b.TextScaled = true; b.TextColor3 = Color3.new(1, 1, 1)
		b.Parent = bar
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 12)
		local s = Instance.new("UIStroke", b); s.Color = Color3.new(0, 0, 0); s.Transparency = 0.4; s.Thickness = 2
		local pad = Instance.new("UIPadding", b); pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6)
		return b
	end

	local goBtn   = mkBtn("\xF0\x9F\x94\xA5 Roast", Color3.fromRGB(214, 108, 44))
	local stopBtn = mkBtn("\xE2\x9C\x8B Stop",     Color3.fromRGB(90, 96, 110))
	local eatBtn  = mkBtn("\xF0\x9F\x98\x8B Eat",  Color3.fromRGB(86, 170, 78))
	goBtn.LayoutOrder = 1; stopBtn.LayoutOrder = 2; eatBtn.LayoutOrder = 3

	goBtn.Activated:Connect(function()   stickRemote:FireServer("roast") end)
	stopBtn.Activated:Connect(function() stickRemote:FireServer("stop")  end)
	eatBtn.Activated:Connect(function()  stickRemote:FireServer("eat")   end)

	-- a little red Remove button, centred UNDER the middle (Stop) button -- throws the marshmallow away
	local removeBtn = Instance.new("TextButton")
	removeBtn.AnchorPoint = Vector2.new(0.5, 0)
	removeBtn.Position = UDim2.new(0.5, 0, 0.865, 6) -- just below the bar, centred (under the middle button)
	removeBtn.Size = UDim2.fromOffset(120, 28)
	removeBtn.BackgroundColor3 = Color3.fromRGB(200, 58, 58)
	removeBtn.Text = "\xF0\x9F\x97\x91 Remove"; removeBtn.AutoButtonColor = true
	removeBtn.Font = Enum.Font.FredokaOne; removeBtn.TextScaled = true; removeBtn.TextColor3 = Color3.new(1, 1, 1)
	removeBtn.Visible = false
	removeBtn.Parent = screen
	Instance.new("UICorner", removeBtn).CornerRadius = UDim.new(0, 10)
	local rs = Instance.new("UIStroke", removeBtn); rs.Color = Color3.new(0, 0, 0); rs.Transparency = 0.4; rs.Thickness = 2
	local rpad = Instance.new("UIPadding", removeBtn); rpad.PaddingLeft = UDim.new(0, 6); rpad.PaddingRight = UDim.new(0, 6)
	removeBtn.Activated:Connect(function() stickRemote:FireServer("remove") end)

	-- HIDE JUST THE BOTTOM BAR WHILE ROASTING. BottomStackGui is the little fart/gut meter + the "TAP TO
	-- FART! / BUY FOOD FIRST!" button; everything else (coins, side buttons, etc.) stays visible. We
	-- remember its Enabled state and restore it after, so we never fight other menus.
	local HUD_GUIS = { "BottomStackGui" }
	local hudPrev = nil
	local function setHudHidden(hidden)
		if hidden then
			if hudPrev then return end
			hudPrev = {}
			for _, name in ipairs(HUD_GUIS) do
				local g = gui:FindFirstChild(name)
				if g and g:IsA("ScreenGui") then hudPrev[name] = g.Enabled; g.Enabled = false end
			end
		elseif hudPrev then
			for _, name in ipairs(HUD_GUIS) do
				local g = gui:FindFirstChild(name)
				if g and g:IsA("ScreenGui") and hudPrev[name] ~= nil then g.Enabled = hudPrev[name] end
			end
			hudPrev = nil
		end
	end

	-- show the bar (and hide the HUD) only while a "Marshmallow Stick" tool is in the character (equipped)
	local function holdingStick()
		local char = player.Character
		return char and char:FindFirstChild("Marshmallow Stick") ~= nil
	end
	local function updateBar()
		local holding = holdingStick()
		bar.Visible = holding
		removeBtn.Visible = holding
		setHudHidden(holding)
	end

	local function hookChar(char)
		char.ChildAdded:Connect(updateBar)
		char.ChildRemoved:Connect(updateBar)
		updateBar()
	end
	if player.Character then hookChar(player.Character) end
	player.CharacterAdded:Connect(hookChar)
end

print("[Campfire] client ready -- roasting buttons wired")
