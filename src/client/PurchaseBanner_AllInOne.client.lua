--======================================================================
-- PurchaseBanner_AllInOne.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of the PURCHASE ANNOUNCEMENT BANNER -- the gold banner
-- that slides in for EVERY player when someone buys a gamepass or a developer
-- product. Lifted VERBATIM from CoreClient (showPurchaseBanner). The server
-- broadcasts via PurchaseAnnouncementEvent:FireAllClients(name, item, isGamepass);
-- every client shows this banner.
--
-- LOOK: a 500x60 gold banner that slides down from the top, "[player] bought
-- [item]!", a star (gamepass) or party-popper (product) icon, a confetti burst +
-- confetti sound, auto-dismiss after 4s.
--
-- Pair with PurchaseBanner_AllInOne.server.lua (fires the event on purchase).
-- Drop into StarterPlayer > StarterPlayerScripts. Includes a TEST button.
--======================================================================

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== the banner (VERBATIM from CoreClient: showPurchaseBanner) =====
local function showPurchaseBanner(playerName, itemName, isGamepass)
	local bannerGui = Instance.new("ScreenGui")
	bannerGui.Name = "PurchaseBanner"; bannerGui.ResetOnSpawn = false; bannerGui.IgnoreGuiInset = true; bannerGui.Parent = PlayerGui

	local banner = Instance.new("Frame")
	banner.Size = UDim2.new(0,500,0,60); banner.Position = UDim2.new(0.5,0,0,-70); banner.AnchorPoint = Vector2.new(0.5,0)
	banner.BackgroundColor3 = Color3.fromRGB(255,200,0); banner.ZIndex = 20; banner.Parent = bannerGui
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,12); bc.Parent = banner
	local bs = Instance.new("UIStroke"); bs.Color = Color3.fromRGB(200,150,0); bs.Thickness = 3; bs.Parent = banner

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(0,50,1,0); icon.Position = UDim2.new(0,8,0,0); icon.BackgroundTransparency = 1
	icon.Text = isGamepass and "\xe2\xad\x90" or "\xf0\x9f\x8e\x89" -- ⭐ gamepass / 🎉 product
	icon.TextSize = 28; icon.Font = Enum.Font.Gotham; icon.RichText = false; icon.ZIndex = 21; icon.Parent = banner

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1,-60,1,0); label.Position = UDim2.new(0,55,0,0); label.BackgroundTransparency = 1
	label.Text = playerName .. " bought " .. itemName .. "!"
	label.Font = Enum.Font.GothamBold; label.TextSize = 16; label.TextColor3 = Color3.fromRGB(80,40,0)
	label.TextXAlignment = Enum.TextXAlignment.Left; label.TextScaled = false; label.ZIndex = 21; label.Parent = banner

	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Position = UDim2.new(0.5,0,0,10)}):Play()

	local function playConfettiSound()
		local sound = Instance.new("Sound"); sound.SoundId = "rbxassetid://112825313814792"; sound.Volume = 0.8; sound.Parent = workspace
		sound:Play(); Debris:AddItem(sound, 5)
	end
	task.spawn(function()
		playConfettiSound()
		for i = 1, 30 do
			task.wait(0.05)
			local confetti = Instance.new("Frame")
			confetti.Size = UDim2.new(0, math.random(8,14), 0, math.random(8,14))
			confetti.Position = UDim2.new(math.random(20,80)/100, 0, 0, math.random(-10,0))
			confetti.BackgroundColor3 = Color3.fromHSV(math.random(0,100)/100, 1, 1)
			confetti.BorderSizePixel = 0; confetti.ZIndex = 22; confetti.Rotation = math.random(0,360); confetti.Parent = bannerGui
			local uic = Instance.new("UICorner"); uic.CornerRadius = UDim.new(0,2); uic.Parent = confetti
			TweenService:Create(confetti, TweenInfo.new(2), {
				Position = UDim2.new(confetti.Position.X.Scale, 0, 1, 50),
				Rotation = math.random(360), BackgroundTransparency = 1
			}):Play()
			Debris:AddItem(confetti, 2.1)
		end
	end)

	task.delay(4, function()
		TweenService:Create(banner, TweenInfo.new(0.3), {Position = UDim2.new(0.5,0,0,-70)}):Play()
		task.wait(0.4); bannerGui:Destroy()
	end)
end
_G.showPurchaseBanner = showPurchaseBanner

-- ===== wire the server broadcast: PurchaseAnnouncementEvent(name, item, isGamepass) =====
local PAE = RS:FindFirstChild("PurchaseAnnouncementEvent") or RS:WaitForChild("PurchaseAnnouncementEvent", 10)
if PAE then
	PAE.OnClientEvent:Connect(function(playerName, itemName, isGamepass)
		showPurchaseBanner(playerName, itemName, isGamepass)
	end)
end

-- ===== TEST button (remove in production) =====
local gui = Instance.new("ScreenGui"); gui.Name = "PurchaseBannerTest"; gui.ResetOnSpawn = false; gui.Parent = PlayerGui
local btn = Instance.new("TextButton"); btn.AnchorPoint = Vector2.new(0.5,1); btn.Position = UDim2.new(0.5,0,1,-150); btn.Size = UDim2.new(0,220,0,40)
btn.BackgroundColor3 = Color3.fromRGB(255,200,0); btn.Text = "TEST PURCHASE BANNER"; btn.Font = Enum.Font.GothamBold; btn.TextSize = 15; btn.TextColor3 = Color3.fromRGB(80,40,0); btn.Parent = gui
Instance.new("UICorner", btn).CornerRadius = UDim.new(0,10)
local toggle = true
btn.Activated:Connect(function() toggle = not toggle; showPurchaseBanner(player.Name, toggle and "2x Fart Power Forever" or "Bird Nuke", toggle) end)

print("[PurchaseBanner] ready -> _G.showPurchaseBanner(name, item, isGamepass)")
