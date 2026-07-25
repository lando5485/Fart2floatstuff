-- ============================================================================================
-- OFFLINE PET EARNINGS -- the "welcome back" card, where the player PICKS their reward.
--
-- The server (PlayerStats) computes BOTH options and grants NOTHING until the player chooses. This file
-- renders the offer and sends back a single word -- "coins" or "levels". It never sends an amount, so
-- there is nothing here a client could tamper with to pay itself more.
--
-- Deliberately its OWN script rather than another block inside PetFollow: PetFollow sits at 198 of Luau's
-- hard 200-locals-per-scope limit, and going over makes the WHOLE script fail to compile (which is exactly
-- how the Pet Hub buttons silently died once already). New UI goes in new files.
--
-- Fired by: OfflineEarningsEvent (on join after being away, and by the /offline test command).
-- ============================================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer
local OfflineEarningsEvent = ReplicatedStorage:WaitForChild("OfflineEarningsEvent", 30)
local OfflineClaimEvent    = ReplicatedStorage:WaitForChild("OfflineClaimEvent", 30)

local function comma(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = ""
	while #s > 3 do out = "," .. s:sub(-3) .. out; s = s:sub(1, -4) end
	return s .. out
end

local function hoursText(h)
	local mins = math.floor((tonumber(h) or 0) * 60 + 0.5)
	local hh, mm = math.floor(mins / 60), mins % 60
	if hh > 0 and mm > 0 then return string.format("%dh %dm", hh, mm) end
	if hh > 0 then return string.format("%dh", hh) end
	return string.format("%dm", mm)
end

local function showCard(r)
	if type(r) ~= "table" then return end
	local coins  = tonumber(r.coins) or 0
	local levels = tonumber(r.levels) or 0
	if coins <= 0 and levels <= 0 then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "OfflineEarningsCard"; gui.ResetOnSpawn = false
	gui.DisplayOrder = 70; gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Modal, and NOT click-outside-to-dismiss: this is a choice, and a stray click must not silently forfeit it.
	local dim = Instance.new("Frame")
	dim.Size = UDim2.new(1, 0, 1, 0); dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1; dim.Active = true; dim.Parent = gui

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5); card.Position = UDim2.new(0.5, 0, 0.45, 0)
	card.Size = UDim2.new(0, 480, 0, 300); card.BackgroundColor3 = Color3.fromRGB(20, 40, 28)
	card.BackgroundTransparency = 1; card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 20)
	local stroke = Instance.new("UIStroke", card)
	stroke.Color = Color3.fromRGB(255, 200, 60); stroke.Thickness = 3; stroke.Transparency = 1

	local eyebrow = Instance.new("TextLabel")
	eyebrow.BackgroundTransparency = 1; eyebrow.Position = UDim2.new(0, 0, 0, 14)
	eyebrow.Size = UDim2.new(1, 0, 0, 18); eyebrow.Font = Enum.Font.GothamBold; eyebrow.TextSize = 13
	eyebrow.TextColor3 = Color3.fromRGB(150, 200, 165); eyebrow.TextTransparency = 1
	eyebrow.Text = r.test and "WELCOME BACK  \xE2\x80\xA2  [/offline TEST]" or "WELCOME BACK"
	eyebrow.Parent = card

	local head = Instance.new("TextLabel")
	head.BackgroundTransparency = 1; head.Position = UDim2.new(0, 14, 0, 36)
	head.Size = UDim2.new(1, -28, 0, 46); head.Font = Enum.Font.FredokaOne; head.TextScaled = true
	head.TextColor3 = Color3.fromRGB(235, 250, 238); head.TextTransparency = 1
	head.Text = ("Your %d pet%s kept working"):format(r.pets or 0, (r.pets == 1) and "" or "s")
	head.Parent = card

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1; sub.Position = UDim2.new(0, 14, 0, 84)
	sub.Size = UDim2.new(1, -28, 0, 20); sub.Font = Enum.Font.Gotham; sub.TextSize = 13
	sub.TextColor3 = Color3.fromRGB(160, 195, 175); sub.TextTransparency = 1
	sub.Text = ("Away %s%s  \xE2\x80\xA2  pick ONE reward")
		:format(hoursText(r.hours), r.capped and " (capped)" or "")
	sub.Parent = card

	-- ===== the two options, side by side. Picking one forfeits the other -- say so plainly. =====
	local claimed = false
	local function makeOption(x, width, titleTxt, valueTxt, noteTxt, col, choice, enabled)
		local b = Instance.new("TextButton")
		b.Position = UDim2.new(0, x, 0, 116); b.Size = UDim2.new(0, width, 0, 116)
		b.BackgroundColor3 = enabled and col or Color3.fromRGB(58, 62, 70)
		b.BackgroundTransparency = 0.15; b.Text = ""; b.AutoButtonColor = enabled; b.Parent = card
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 14)
		local bs = Instance.new("UIStroke", b)
		bs.Color = enabled and col or Color3.fromRGB(80, 86, 96); bs.Thickness = 2

		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -12, 0, 18); t.Position = UDim2.new(0, 6, 0, 10)
		t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold; t.TextSize = 12
		t.TextColor3 = Color3.fromRGB(255, 255, 255); t.Text = titleTxt; t.Parent = b

		local v = Instance.new("TextLabel")
		v.Size = UDim2.new(1, -12, 0, 44); v.Position = UDim2.new(0, 6, 0, 32)
		v.BackgroundTransparency = 1; v.Font = Enum.Font.FredokaOne; v.TextScaled = true
		v.TextColor3 = Color3.new(1, 1, 1); v.Text = valueTxt; v.Parent = b
		local vs = Instance.new("UIStroke", v); vs.Color = Color3.new(0, 0, 0); vs.Thickness = 2

		local n = Instance.new("TextLabel")
		n.Size = UDim2.new(1, -12, 0, 30); n.Position = UDim2.new(0, 6, 0, 80)
		n.BackgroundTransparency = 1; n.Font = Enum.Font.Gotham; n.TextSize = 11; n.TextWrapped = true
		n.TextColor3 = Color3.fromRGB(225, 235, 240); n.Text = noteTxt; n.Parent = b

		if enabled then
			b.MouseButton1Click:Connect(function()
				if claimed then return end -- guard: two fast clicks must not fire the remote twice
				claimed = true
				pcall(function() OfflineClaimEvent:FireServer(choice) end)
				print("[OfflineEarnings] claimed: " .. choice)

				-- collapse to a confirmation, then close
				for _, c in ipairs(card:GetChildren()) do
					if c:IsA("TextButton") or c:IsA("TextLabel") then c.Visible = false end
				end
				local done = Instance.new("TextLabel")
				done.Size = UDim2.new(1, -24, 1, -24); done.Position = UDim2.new(0, 12, 0, 12)
				done.BackgroundTransparency = 1; done.Font = Enum.Font.FredokaOne; done.TextScaled = true
				done.TextColor3 = Color3.fromRGB(120, 255, 150)
				done.Text = (choice == "coins") and ("+" .. comma(coins) .. " Coins")
					or ("+" .. levels .. " Pet Level" .. ((levels == 1) and "" or "s"))
				done.Parent = card
				task.delay(1.6, function()
					local OUT = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					TweenService:Create(dim, OUT, {BackgroundTransparency = 1}):Play()
					TweenService:Create(card, OUT, {BackgroundTransparency = 1}):Play()
					TweenService:Create(stroke, OUT, {Transparency = 1}):Play()
					TweenService:Create(done, OUT, {TextTransparency = 1}):Play()
					task.delay(0.4, function() gui:Destroy() end)
				end)
			end)
		end
		return b
	end

	makeOption(14, 222, "\xF0\x9F\x92\xB0 TAKE COINS", comma(coins) .. " Coins",
		("your pets' rate: %s/hour"):format(comma(r.perHour or 0)),
		Color3.fromRGB(196, 150, 30), "coins", coins > 0)

	local lvlEnabled = levels > 0
	makeOption(244, 222, "\xE2\xAD\x90 TAKE PET LEVELS",
		lvlEnabled and ("+" .. levels .. " Level" .. ((levels == 1) and "" or "s")) or "\xE2\x80\x94",
		lvlEnabled and ("on your equipped pet (Lv %d)"):format(r.eqLevel or 0)
			or "needs an un-maxed equipped pet",
		Color3.fromRGB(86, 120, 200), "levels", lvlEnabled)

	local foot = Instance.new("TextLabel")
	foot.BackgroundTransparency = 1; foot.Position = UDim2.new(0, 14, 0, 244)
	foot.Size = UDim2.new(1, -28, 0, 42); foot.Font = Enum.Font.Gotham; foot.TextSize = 12
	foot.TextWrapped = true; foot.TextColor3 = Color3.fromRGB(140, 170, 152); foot.TextTransparency = 1
	foot.Text = "Pick one - the other is forfeited."
	foot.Parent = card

	local IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(dim,    TweenInfo.new(0.3), {BackgroundTransparency = 0.45}):Play()
	TweenService:Create(card,   IN, {BackgroundTransparency = 0.02}):Play()
	TweenService:Create(stroke, IN, {Transparency = 0}):Play()
	for _, l in ipairs({ eyebrow, head, sub, foot }) do
		TweenService:Create(l, IN, {TextTransparency = 0}):Play()
	end

	-- SAFETY NET: if the player never picks (AFK, tabbed out), auto-take the coins after 60s rather than let the
	-- reward evaporate. The server clears the pending offer on claim, so this can never double-pay.
	task.delay(60, function()
		if not claimed and gui.Parent then
			claimed = true
			pcall(function() OfflineClaimEvent:FireServer("coins") end)
			print("[OfflineEarnings] no choice made in 60s -> auto-took coins")
			gui:Destroy()
		end
	end)

	print(string.format("[OfflineEarnings] offer shown: %d coins OR %d level(s) (%d pets, away %s%s)",
		coins, levels, r.pets or 0, hoursText(r.hours), r.capped and ", capped" or ""))
end

if OfflineEarningsEvent then
	OfflineEarningsEvent.OnClientEvent:Connect(function(r) pcall(showCard, r) end)
	print("[OfflineEarnings] ready -- waiting for a welcome-back offer")
else
	warn("[OfflineEarnings] OfflineEarningsEvent missing -- welcome-back card will never show")
end
