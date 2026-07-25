--======================================================================
-- RebirthButton.client.luau  (LocalScript -> StarterPlayer > StarterPlayerScripts)
--======================================================================
-- Standalone on-screen REBIRTH button for the SPACE REALM place.
-- In the MAIN place this button is baked into CoreClient's side-button bar; the Space Realm has no such bar,
-- so this script draws its own button that opens the Rebirth HUD (RebirthClient defines _G.toggleRebirth).
-- Move btn.Position below if it clashes with the Space Realm's own UI.
--======================================================================
local Players = game:GetService("Players")
local player  = Players.LocalPlayer
local gui     = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "RebirthButtonGui"; screen.ResetOnSpawn = false; screen.DisplayOrder = 40; screen.Parent = gui

local btn = Instance.new("TextButton")
btn.Name = "RebirthButton"
btn.AnchorPoint = Vector2.new(0, 0.5)
btn.Position = UDim2.new(0, 16, 0.5, 0)   -- left-middle of the screen; move if it clashes with Space Realm UI
btn.Size = UDim2.fromOffset(74, 74)
btn.BackgroundColor3 = Color3.fromRGB(170, 90, 240)
btn.AutoButtonColor = true
btn.Text = ""
btn.Parent = screen
do local c = Instance.new("UICorner", btn); c.CornerRadius = UDim.new(0, 16) end
do local s = Instance.new("UIStroke", btn); s.Color = Color3.fromRGB(46, 20, 80); s.Thickness = 3 end
do local g = Instance.new("UIGradient", btn); g.Rotation = 90; g.Color = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(168,168,168)) end -- juicy bevel

local icon = Instance.new("TextLabel")
icon.BackgroundTransparency = 1; icon.Position = UDim2.new(0, 0, 0, 6); icon.Size = UDim2.new(1, 0, 0, 40)
icon.Font = Enum.Font.GothamBold; icon.TextScaled = true; icon.Text = "\xF0\x9F\x94\x84"; icon.TextColor3 = Color3.new(1,1,1)
icon.Parent = btn

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1; label.Position = UDim2.new(0, 0, 1, -22); label.Size = UDim2.new(1, 0, 0, 18)
label.Font = Enum.Font.FredokaOne; label.TextScaled = true; label.Text = "REBIRTH"; label.TextColor3 = Color3.new(1,1,1)
label.Parent = btn
do local s = Instance.new("UIStroke", label); s.Color = Color3.new(0,0,0); s.Thickness = 1.5 end

btn.Activated:Connect(function()
	if type(_G.toggleRebirth) == "function" then
		_G.toggleRebirth()
	else
		warn("[RebirthButton] _G.toggleRebirth not ready -- is RebirthClient.client.luau present in StarterPlayerScripts?")
	end
end)

print("[RebirthButton] ready -- opens the Rebirth HUD (_G.toggleRebirth)")
