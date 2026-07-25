--!nonstrict
-- PetWheel (StarterPlayer/StarterPlayerScripts/PetWheel)
-- ============================================================================================================
-- CLIENT for the Robux "Pet Wheel". This script ONLY draws the panel, prompts the Robux purchases, and animates
-- the wheel to the result the SERVER sends. It never decides an outcome, never rolls, and never grants anything
-- (PetWheel.server.lua is the authority). It is a self-contained script (per the "new client logic in its own
-- script" rule) -- it touches no other client module's state.
--
-- HONEST ODDS: the Odds panel lists every segment and its % straight from the SHARED PetWheelConfig.SEGMENTS
-- table -- the exact same table the server rolls on -- so the shown odds can never differ from the real odds.
--
-- ENTRY POINT: exposes _G.togglePetWheel(); the Pet menu (PetHub_AllInOne) calls it to open the panel.
-- ============================================================================================================

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player  = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local Config  = require(Shared:WaitForChild("PetWheelConfig"))
local remote  = ReplicatedStorage:WaitForChild("PetWheelEvent")

-- Canonical "give me my owned pets" fetch, the SAME RemoteFunction the existing crate pet-picker uses. Returns
-- a list of { petId, displayName, level, maxed, xpPct }. Fetched lazily so we don't hard-depend on load order.
local function fetchOwnedPets()
	local crateRemotes = ReplicatedStorage:FindFirstChild("CrateRemotes")
	local rf = crateRemotes and crateRemotes:FindFirstChild("GetOwnedPets")
	if not rf then return {} end
	local ok, list = pcall(function() return rf:InvokeServer() end)
	if ok and type(list) == "table" then return list end
	return {}
end

-- ---- small UI helpers -------------------------------------------------------------------------------------
local function corner(inst, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = inst; return c end
local function stroke(inst, col, th) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th or 2; s.Parent = inst; return s end
local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- ---- state ------------------------------------------------------------------------------------------------
local spinsOwned = 0
local pendingLevels = 0
local spinning = false

-- ============================================================================================================
-- BUILD THE UI
-- ============================================================================================================
local gui = mk("ScreenGui", {
	Name = "PetWheelGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 100, Enabled = false,
}, playerGui)

local dim = mk("TextButton", {
	Name = "Dim", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 1,
}, gui)

local panel = mk("Frame", {
	Name = "Panel", BackgroundColor3 = Color3.fromRGB(36, 24, 44),
	Size = UDim2.fromOffset(700, 520), Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	ZIndex = 2,
}, gui)
corner(panel, 18); stroke(panel, Color3.fromRGB(255, 210, 90), 3)

mk("TextLabel", {
	Text = "PET WHEEL", Font = Enum.Font.GothamBlack, TextSize = 30, TextColor3 = Color3.fromRGB(255, 225, 130),
	BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 48), Position = UDim2.fromOffset(20, 12),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
}, panel)

local closeBtn = mk("TextButton", {
	Text = "X", Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = Color3.new(1, 1, 1),
	BackgroundColor3 = Color3.fromRGB(200, 60, 70), Size = UDim2.fromOffset(38, 38),
	Position = UDim2.new(1, -50, 0, 14), ZIndex = 3,
}, panel)
corner(closeBtn, 10)

-- ---- the wheel (a ring of colored segment pills that spins; a fixed pointer at top marks the result) --------
local WHEEL_D = 300
local wheelHolder = mk("Frame", {
	Name = "WheelHolder", BackgroundTransparency = 1, Size = UDim2.fromOffset(WHEEL_D, WHEEL_D),
	Position = UDim2.fromOffset(28, 74), ZIndex = 3,
}, panel)

-- pointer (▼) fixed above the wheel top
mk("TextLabel", {
	Text = "\xE2\x96\xBC", Font = Enum.Font.GothamBlack, TextSize = 34, TextColor3 = Color3.fromRGB(255, 235, 150),
	BackgroundTransparency = 1, Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0.5, -20, 0, -30), ZIndex = 5,
}, wheelHolder)

-- the spinning disc
local disc = mk("Frame", {
	Name = "Disc", BackgroundColor3 = Color3.fromRGB(24, 16, 30), Size = UDim2.fromScale(1, 1), ZIndex = 3,
	Rotation = 0,
}, wheelHolder)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, disc)
stroke(disc, Color3.fromRGB(255, 210, 90), 3)

-- hub
local hub = mk("Frame", {
	BackgroundColor3 = Color3.fromRGB(255, 210, 90), Size = UDim2.fromOffset(46, 46),
	Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4,
}, disc)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, hub)

-- one pill per segment, arranged around the ring at its angle. Angle 0 = top (under the pointer), clockwise.
local N = #Config.SEGMENTS
local STEP = 360 / N
for i, seg in ipairs(Config.SEGMENTS) do
	local ang = (i - 1) * STEP                        -- degrees clockwise from top
	local rad = math.rad(ang)
	local rFrac = 0.33                                -- distance from center as a fraction of the disc
	local px = 0.5 + rFrac * math.sin(rad)
	local py = 0.5 - rFrac * math.cos(rad)
	local pill = mk("Frame", {
		BackgroundColor3 = seg.color or Color3.fromRGB(200, 200, 200),
		Size = UDim2.fromOffset(96, 34), Position = UDim2.fromScale(px, py), AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = ang, ZIndex = 4,
	}, disc)
	corner(pill, 8); stroke(pill, Color3.fromRGB(20, 14, 26), 1.5)
	mk("TextLabel", {
		Text = seg.label, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.fromRGB(25, 18, 30),
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), TextWrapped = true, ZIndex = 5,
	}, pill)
end

-- ---- right column: spins owned, spin button, buy buttons, odds button --------------------------------------
local right = mk("Frame", {
	BackgroundTransparency = 1, Size = UDim2.fromOffset(320, 430), Position = UDim2.fromOffset(360, 74), ZIndex = 3,
}, panel)

local spinsLabel = mk("TextLabel", {
	Text = "Spins: 0", Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = Color3.fromRGB(255, 235, 150),
	BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, right)

local spinBtn = mk("TextButton", {
	Text = "SPIN", Font = Enum.Font.GothamBlack, TextSize = 26, TextColor3 = Color3.new(1, 1, 1),
	BackgroundColor3 = Color3.fromRGB(80, 200, 110), Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 42), ZIndex = 4,
}, right)
corner(spinBtn, 12)

-- pending-levels banner (shown when the player has unassigned pet levels waiting)
local pendingBtn = mk("TextButton", {
	Text = "", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.fromRGB(30, 20, 10),
	BackgroundColor3 = Color3.fromRGB(255, 205, 90), Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 108),
	Visible = false, TextWrapped = true, ZIndex = 4,
}, right)
corner(pendingBtn, 10)

-- buy buttons (one per product), each showing R$ and the savings on the packs
local buyHeader = mk("TextLabel", {
	Text = "Buy Spins", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.fromRGB(220, 200, 230),
	BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 156),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
}, right)

local function makeBuyButton(product, yOff)
	local btn = mk("TextButton", {
		Text = "", AutoButtonColor = true, BackgroundColor3 = Color3.fromRGB(70, 55, 90),
		Size = UDim2.new(1, 0, 0, 58), Position = UDim2.fromOffset(0, yOff), ZIndex = 4,
	}, right)
	corner(btn, 10)
	if product.tag then
		local tag = mk("TextLabel", {
			Text = product.tag, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.fromRGB(30, 20, 10),
			BackgroundColor3 = Color3.fromRGB(255, 215, 100), Size = UDim2.fromOffset(96, 20),
			Position = UDim2.new(1, -104, 0, -8), ZIndex = 6, TextXAlignment = Enum.TextXAlignment.Center,
		}, btn)
		corner(tag, 6)
	end
	mk("TextLabel", {
		Text = product.label, Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1, Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 5,
	}, btn)
	-- price + savings (savings only for the packs, where it's positive)
	local saved = Config.savingsFor(product)
	local priceText = string.format("R$ %d", product.robux)
	if saved > 0 then
		priceText = priceText .. string.format("\n(save R$ %d)", saved)
	end
	mk("TextLabel", {
		Text = priceText, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.fromRGB(150, 240, 160),
		BackgroundTransparency = 1, Size = UDim2.new(0.4, -12, 1, 0), Position = UDim2.new(0.6, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 5,
	}, btn)
	btn.Activated:Connect(function()
		pcall(function() MarketplaceService:PromptProductPurchase(player, product.productId) end)
	end)
	return btn
end

local y = 186
for _, product in ipairs(Config.PRODUCTS) do
	makeBuyButton(product, y)
	y = y + 66
end

local oddsBtn = mk("TextButton", {
	Text = "Odds", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.new(1, 1, 1),
	BackgroundColor3 = Color3.fromRGB(90, 90, 120), Size = UDim2.fromOffset(120, 32),
	Position = UDim2.fromOffset(28, 388), ZIndex = 3,
}, panel)
corner(oddsBtn, 8)

-- ============================================================================================================
-- ODDS PANEL -- lists every segment + its exact % straight from PetWheelConfig.SEGMENTS (same table the server
-- rolls on), plus the real-odds disclosure note.
-- ============================================================================================================
local oddsOverlay = mk("Frame", {
	Name = "OddsOverlay", BackgroundColor3 = Color3.fromRGB(28, 20, 34), Size = UDim2.fromOffset(360, 440),
	Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 20,
}, panel)
corner(oddsOverlay, 14); stroke(oddsOverlay, Color3.fromRGB(255, 210, 90), 2)

mk("TextLabel", {
	Text = "Drop Chances", Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = Color3.fromRGB(255, 225, 130),
	BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(14, 10),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21,
}, oddsOverlay)

local oddsClose = mk("TextButton", {
	Text = "X", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.new(1, 1, 1),
	BackgroundColor3 = Color3.fromRGB(200, 60, 70), Size = UDim2.fromOffset(30, 30),
	Position = UDim2.new(1, -40, 0, 12), ZIndex = 22,
}, oddsOverlay)
corner(oddsClose, 8)

local oddsList = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -28, 1, -110), Position = UDim2.fromOffset(14, 52), ZIndex = 21 }, oddsOverlay)
local oddsLayout = mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, oddsList)
for i, seg in ipairs(Config.SEGMENTS) do
	local row = mk("Frame", { BackgroundColor3 = Color3.fromRGB(44, 32, 52), Size = UDim2.new(1, 0, 0, 34), LayoutOrder = i, ZIndex = 21 }, oddsList)
	corner(row, 8)
	mk("Frame", { BackgroundColor3 = seg.color or Color3.fromRGB(200,200,200), Size = UDim2.fromOffset(16,16), Position = UDim2.fromOffset(10, 9), ZIndex = 22 }, row)
	mk("TextLabel", {
		Text = seg.label, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1, Size = UDim2.new(0.65, 0, 1, 0), Position = UDim2.fromOffset(34, 0),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22,
	}, row)
	-- print the weight exactly as configured (e.g. 45, 0.9, 0.1) with a trailing % -- no rounding, no drift
	local pctText = string.format("%s%%", tostring(seg.weight))
	mk("TextLabel", {
		Text = pctText, Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = Color3.fromRGB(150, 240, 160),
		BackgroundTransparency = 1, Size = UDim2.new(0.35, -10, 1, 0), Position = UDim2.new(0.65, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 22,
	}, row)
end

mk("TextLabel", {
	Text = Config.ODDS_NOTE, Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = Color3.fromRGB(255, 225, 130),
	BackgroundTransparency = 1, Size = UDim2.new(1, -28, 0, 40), Position = UDim2.new(0, 14, 1, -46),
	TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21,
}, oddsOverlay)

-- ============================================================================================================
-- PET PICKER -- reuses the canonical GetOwnedPets fetch. Lists the player's OWNED pets; maxed pets are greyed
-- and not selectable (they can't take levels). Picking one fires "assign" to the server, which grants the held
-- pet-levels (clamped to 25) onto that pet. If the player owns ZERO pets, shows the "unlock a pet" message.
-- ============================================================================================================
local pickerOverlay = mk("Frame", {
	Name = "PickerOverlay", BackgroundColor3 = Color3.fromRGB(28, 20, 34), Size = UDim2.fromOffset(420, 460),
	Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 30,
}, panel)
corner(pickerOverlay, 14); stroke(pickerOverlay, Color3.fromRGB(255, 210, 90), 2)

local pickerTitle = mk("TextLabel", {
	Text = "Choose a Pet to Level Up", Font = Enum.Font.GothamBlack, TextSize = 20, TextColor3 = Color3.fromRGB(255, 225, 130),
	BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(14, 10),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31,
}, pickerOverlay)

local pickerClose = mk("TextButton", {
	Text = "X", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.new(1, 1, 1),
	BackgroundColor3 = Color3.fromRGB(200, 60, 70), Size = UDim2.fromOffset(30, 30),
	Position = UDim2.new(1, -40, 0, 12), ZIndex = 32,
}, pickerOverlay)
corner(pickerClose, 8)

local pickerMsg = mk("TextLabel", {
	Text = "", Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = Color3.fromRGB(255, 220, 170),
	BackgroundTransparency = 1, Size = UDim2.new(1, -28, 0, 60), Position = UDim2.fromOffset(14, 52),
	TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 31,
}, pickerOverlay)

local pickerScroll = mk("ScrollingFrame", {
	BackgroundTransparency = 1, Size = UDim2.new(1, -28, 1, -70), Position = UDim2.fromOffset(14, 56),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ZIndex = 31,
}, pickerOverlay)
mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, pickerScroll)

local function clearPicker()
	for _, ch in ipairs(pickerScroll:GetChildren()) do
		if ch:IsA("GuiButton") or ch:IsA("Frame") then ch:Destroy() end
	end
end

local function closePicker() pickerOverlay.Visible = false end

local function openPicker()
	clearPicker()
	pickerMsg.Visible = false
	pickerScroll.Visible = true
	pickerTitle.Text = string.format("Choose a Pet (+%d levels)", pendingLevels)
	local owned = fetchOwnedPets()
	if #owned == 0 then
		-- ZERO pets: hold the reward (it's already banked in `pending` server-side) and tell the player.
		pickerScroll.Visible = false
		pickerMsg.Visible = true
		pickerMsg.Text = "Unlock a pet to receive these levels.\nYour +" .. pendingLevels .. " levels are saved and waiting."
		pickerOverlay.Visible = true
		return
	end
	for i, p in ipairs(owned) do
		local maxed = p.maxed == true
		local row = mk("TextButton", {
			Text = "", AutoButtonColor = not maxed,
			BackgroundColor3 = maxed and Color3.fromRGB(50, 44, 56) or Color3.fromRGB(60, 48, 74),
			Size = UDim2.new(1, -6, 0, 44), LayoutOrder = i, ZIndex = 32,
		}, pickerScroll)
		corner(row, 8)
		mk("TextLabel", {
			Text = (p.displayName or p.petId or "Pet"), Font = Enum.Font.GothamBold, TextSize = 15,
			TextColor3 = maxed and Color3.fromRGB(150, 150, 150) or Color3.new(1, 1, 1),
			BackgroundTransparency = 1, Size = UDim2.new(0.68, 0, 1, 0), Position = UDim2.fromOffset(12, 0),
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33,
		}, row)
		mk("TextLabel", {
			Text = maxed and "MAX" or ("Lv " .. tostring(p.level or 1)),
			Font = Enum.Font.GothamBlack, TextSize = 15,
			TextColor3 = maxed and Color3.fromRGB(255, 170, 90) or Color3.fromRGB(150, 240, 160),
			BackgroundTransparency = 1, Size = UDim2.new(0.3, -10, 1, 0), Position = UDim2.new(0.7, 0, 0, 0),
			TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 33,
		}, row)
		if not maxed then
			row.Activated:Connect(function()
				remote:FireServer("assign", p.petId)   -- server grants + clamps; we get "assigned" + "state" back
				closePicker()
			end)
		end
	end
	pickerOverlay.Visible = true
end

-- ============================================================================================================
-- RESULT ANIMATION + TOASTS
-- ============================================================================================================
local resultLabel = mk("TextLabel", {
	Text = "", Font = Enum.Font.GothamBlack, TextSize = 20, TextColor3 = Color3.fromRGB(255, 235, 150),
	BackgroundTransparency = 1, Size = UDim2.new(0, WHEEL_D, 0, 40), Position = UDim2.fromOffset(28, 384),
	TextWrapped = true, ZIndex = 6,
}, panel)

local function showToast(msg)
	resultLabel.Text = msg
end

-- Spin the disc so segment `idx` (1-based, matching PetWheelConfig.SEGMENTS) lands under the top pointer.
-- Segment i sits at angle (i-1)*STEP clockwise from top; to bring it to the top we rotate to a multiple of 360
-- minus that angle, plus several full turns for the spin feel. Honest: idx is exactly what the server rolled.
local function animateTo(idx, onDone)
	local target = (5 * 360) - ((idx - 1) * STEP)   -- 5 full spins then land on the segment
	-- normalise current rotation so repeated spins keep accelerating from wherever it stopped
	disc.Rotation = disc.Rotation % 360
	local tween = TweenService:Create(disc, TweenInfo.new(4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Rotation = target })
	tween:Play()
	tween.Completed:Connect(function()
		disc.Rotation = disc.Rotation % 360
		if onDone then onDone() end
	end)
end

local function describeReward(reward)
	if reward.kind == "levels" then
		return string.format("You won +%d Pet Levels! Pick a pet...", reward.amount or 0)
	elseif reward.kind == "coins" then
		return string.format("You won %d Coins!", reward.amount or 0)
	elseif reward.kind == "mythical" then
		return string.format("JACKPOT! Mythical pet: %s!", reward.name or reward.petId or "Mythical")
	end
	return "You won a prize!"
end

-- ---- server -> client ---------------------------------------------------------------------------------------
local function refreshSpinButton()
	spinsLabel.Text = "Spins: " .. tostring(spinsOwned)
	if spinning then
		spinBtn.Text = "SPINNING..."
		spinBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	elseif spinsOwned > 0 then
		spinBtn.Text = "SPIN"
		spinBtn.BackgroundColor3 = Color3.fromRGB(80, 200, 110)
	else
		spinBtn.Text = "BUY SPINS"
		spinBtn.BackgroundColor3 = Color3.fromRGB(150, 130, 90)
	end
	if pendingLevels > 0 then
		pendingBtn.Visible = true
		pendingBtn.Text = string.format("Assign +%d pet levels  \xE2\x86\x92", pendingLevels)
	else
		pendingBtn.Visible = false
	end
end

remote.OnClientEvent:Connect(function(verb, data)
	if verb == "state" then
		spinsOwned = data.spins or 0
		pendingLevels = data.pending or 0
		refreshSpinButton()
	elseif verb == "result" then
		spinsOwned = data.spins or spinsOwned
		pendingLevels = data.pending or pendingLevels
		refreshSpinButton()
		local reward = data.reward or {}
		showToast("")
		animateTo(data.segIndex or 1, function()
			spinning = false
			refreshSpinButton()
			showToast(describeReward(reward))
			if reward.kind == "levels" then
				-- route the win through the pet-picker (assigns from the pending pool)
				task.wait(0.4)
				openPicker()
			end
		end)
	elseif verb == "assigned" then
		pendingLevels = data.pending or 0
		refreshSpinButton()
		if (data.added or 0) > 0 then
			showToast(string.format("+%d levels added!", data.added))
			-- leftover levels (pet hit the 25 cap) -> let them pick another pet
			if pendingLevels > 0 then task.wait(0.5); openPicker() end
		else
			showToast("That pet is already max level.")
		end
	elseif verb == "toast" then
		-- a server toast is only sent on a rejection (out of spins / not your pet); make sure a spin that was
		-- refused can't leave the button stuck on "SPINNING..." (it never got a "result" to clear the flag).
		if spinning then spinning = false; refreshSpinButton() end
		showToast(tostring(data))
	end
end)

-- ---- client -> server / buttons -----------------------------------------------------------------------------
spinBtn.Activated:Connect(function()
	if spinning then return end
	if spinsOwned < 1 then
		showToast("Buy spins to play!")
		return
	end
	spinning = true
	refreshSpinButton()
	remote:FireServer("spin")
end)

pendingBtn.Activated:Connect(function() openPicker() end)
oddsBtn.Activated:Connect(function() oddsOverlay.Visible = true end)
oddsClose.Activated:Connect(function() oddsOverlay.Visible = false end)
pickerClose.Activated:Connect(closePicker)

-- ---- open / close -------------------------------------------------------------------------------------------
local function setOpen(open)
	gui.Enabled = open
	if open then
		remote:FireServer("requestState") -- get fresh credits/pending on open
		showToast("")
	else
		oddsOverlay.Visible = false
		pickerOverlay.Visible = false
	end
end

closeBtn.Activated:Connect(function() setOpen(false) end)
dim.Activated:Connect(function() setOpen(false) end)

-- ENTRY POINT for the Pet menu (PetHub_AllInOne calls this).
_G.togglePetWheel = function() setOpen(not gui.Enabled) end

remote:FireServer("requestState") -- prime state at load so the button label is correct before first open
print("[PetWheel] client ready")
