--======================================================================
-- GardenDonationClient.client.lua  (LocalScript)  -- the DonationChest E-prompt -> "Support the Garden" HUD.
--======================================================================
-- Holding E on the DonationChest's "DonationChestPrompt" (server-created) HINGES the lid open (per-client, purely
-- visual) and opens a native-styled blue panel offering Robux DONATION tiers. Layout: title bar + 2 subtitle lines +
-- a 2x2 grid of green preset cards (25 / 100 / 500 / 1000 R$, each a heart + amount + Donate button) + a thank-you footer.
--
-- PURCHASES: each preset Donate button prompts its matching Robux Developer Product. Robux is granted by the game's
-- SINGLE ProcessReceipt (PlayerStats -> CommunityGarden._G.gardenHandleDonationReceipt), which counts the donor
-- (recordDonor -> unique-donor sign) and broadcasts GardenDonationEvent { name, robux } -> a thank-you banner for
-- everyone. PURE tip jar: no gameplay effect at all. The treasure-box HUD link (the E-prompt) is unchanged.
--======================================================================

local Players              = game:GetService("Players")
local RS                   = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local MarketplaceService   = game:GetService("MarketplaceService")
local TweenService         = game:GetService("TweenService")
local Workspace            = game:GetService("Workspace")
local Debris               = game:GetService("Debris")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== CONSTANTS (product IDs) ========================================================================
-- \xE2\x9A\xA0 REPLACE the 0s with your Robux Developer Product IDs (one per tier). These MUST match the productId
--    values in DONATION_TIERS inside CommunityGarden.server.lua (the server validates the receipt by product id).
local GAMEPASS_IDS = {} -- (donations use no gamepasses; kept for parity / future use)
local PRODUCT_IDS  = { Donate25 = 3608150932, Donate100 = 3608151059, Donate500 = 3608151160, Donate1000 = 3608151576 }

-- the 4 preset tiers, in grid order (source of truth for both the cards and the custom-amount rounding)
local PRESETS = {
	{ amount = 25,   productId = PRODUCT_IDS.Donate25 },
	{ amount = 100,  productId = PRODUCT_IDS.Donate100 },
	{ amount = 500,  productId = PRODUCT_IDS.Donate500 },
	{ amount = 1000, productId = PRODUCT_IDS.Donate1000 },
}

local GardenDonationEvent = RS:WaitForChild("GardenDonationEvent", 30)
if not GardenDonationEvent then return end

-- ===== palette =====
local BLUE_PANEL  = Color3.fromRGB(25, 90, 185)
local BLUE_HEADER = Color3.fromRGB(15, 60, 140)
local CARD_GREEN  = Color3.fromRGB(46, 160, 74)
local BTN_GREEN   = Color3.fromRGB(70, 200, 92)
local BTN_GREEN2  = Color3.fromRGB(38, 150, 66)
local CAN_GREEN   = Color3.fromRGB(74, 196, 100)
local WATER_BLUE  = Color3.fromRGB(150, 210, 255)

-- ===== UI helpers (same ones the shop / reward panels use) =====
local function mkCorner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p; return c end
local function mkStroke(p, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = p; return s end
local function mkLabel(p, props) local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; for k, v in pairs(props) do l[k] = v end; l.Parent = p; return l end
local function mkFrame(p, props) local f = Instance.new("Frame"); for k, v in pairs(props) do f[k] = v end; f.Parent = p; return f end
local function mkButton(p, props) local b = Instance.new("TextButton"); for k, v in pairs(props) do b[k] = v end; b.Parent = p; return b end
-- top-lit bevels (a UIGradient that MULTIPLIES the element colour -> subtle 3D depth without darkening it much)
local function juice(p) local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.new(1,1,1), Color3.fromRGB(170,170,170)); g.Rotation = 90; g.Parent = p; return g end  -- chunky (buttons)
local function soft(p)  local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.new(1,1,1), Color3.fromRGB(222,222,222)); g.Rotation = 90; g.Parent = p; return g end  -- gentle (panels/cards)

-- A small GREEN WATERING-CAN icon built from frames (body + angled spout + rose + handle loop + water droplets).
-- Purely decorative; parented into whatever `parent` frame the caller gives it.
local function makeWateringCan(parent, holderProps)
	local holder = mkFrame(parent, holderProps or { Size = UDim2.new(0, 56, 0, 56), BackgroundTransparency = 1 })
	local body   = mkFrame(holder, { Size = UDim2.new(0, 30, 0, 26), Position = UDim2.new(0.58, 0, 1, -3), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = CAN_GREEN }); mkCorner(body, 7)
	local spout  = mkFrame(holder, { Size = UDim2.new(0, 24, 0, 8),  Position = UDim2.new(0.20, 0, 0.44, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = CAN_GREEN, Rotation = -32 }); mkCorner(spout, 4)
	local rose   = mkFrame(holder, { Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(0.04, 0, 0.30, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = CAN_GREEN }); mkCorner(rose, 6)
	local handle = mkFrame(holder, { Size = UDim2.new(0, 22, 0, 16), Position = UDim2.new(0.70, 0, 0.28, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1 }); mkCorner(handle, 8); mkStroke(handle, CAN_GREEN, 4)
	for _, off in ipairs({ { 0.00, 0.06 }, { 0.09, 0.18 }, { -0.05, 0.22 } }) do
		local d = mkFrame(holder, { Size = UDim2.new(0, 5, 0, 5), Position = UDim2.new(0.04 + off[1], 0, 0.42 + off[2], 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WATER_BLUE }); mkCorner(d, 3)
	end
	return holder
end

-- forward-declared UI handles + functions
local gui, panel, noticeLbl
local buildHUD, openHUD, promptDonate, setNotice, showThanks

--======================================================================
-- LID HINGE (per-client, purely visual): swing the DonationChest's "Lid" model open about its "LidHinge" attachment,
-- then closed. Anchored server parts are moved locally (renders for us only) and RESTORED to their captured CFrames on
-- close, so nothing is left displaced. Fully pcall-guarded; if the lid/hinge is missing it silently no-ops.
--======================================================================
local lidState = nil
local OPEN_ANGLE = math.rad(-74) -- negative -> the front (latch/-X) rises

local function closeLid()
	if not lidState then return end
	for part, orig in pairs(lidState.parts) do
		if part and part.Parent then
			pcall(function() TweenService:Create(part, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = orig }):Play() end)
		end
	end
	lidState = nil
end

local function openLid(chestModel)
	closeLid()
	local lid = chestModel and chestModel:FindFirstChild("Lid")
	local body = chestModel and chestModel:FindFirstChild("ChestBody")
	local hinge = body and body:FindFirstChild("LidHinge")
	if not (lid and hinge) then return end
	local pivot = hinge.WorldCFrame
	lidState = { parts = {} }
	for _, part in ipairs(lid:GetChildren()) do
		if part:IsA("BasePart") then
			lidState.parts[part] = part.CFrame
			local target = pivot * CFrame.Angles(0, 0, OPEN_ANGLE) * pivot:Inverse() * part.CFrame
			pcall(function() TweenService:Create(part, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = target }):Play() end)
		end
	end
end

-- a gold sparkle burst at the chest (cosmetic)
local function sparkle(pos)
	local host = Instance.new("Part")
	host.Anchored = true; host.CanCollide = false; host.CanQuery = false; host.Transparency = 1
	host.Size = Vector3.new(1, 1, 1); host.CFrame = CFrame.new(pos + Vector3.new(0, 2.5, 0)); host.Parent = Workspace
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(Color3.fromRGB(255, 225, 90), Color3.fromRGB(255, 180, 40))
	em.Lifetime = NumberRange.new(0.5, 0.95); em.Speed = NumberRange.new(5, 11); em.SpreadAngle = Vector2.new(70, 70)
	em.Rate = 0; em.Size = NumberSequence.new(0.6); em.LightEmission = 0.6; em.Parent = host
	em:Emit(40)
	Debris:AddItem(host, 1.3)
end

--======================================================================
-- PURCHASE HELPERS
--======================================================================
-- Prompt the Robux Developer Product for a tier. Guards the placeholder 0 id so it can't fire a broken prompt.
function promptDonate(productId, amount)
	if productId and productId > 0 then
		pcall(function() MarketplaceService:PromptProductPurchase(player, productId) end)
	else
		setNotice(string.format("The %d R$ tier isn't set up yet.", amount or 0))
	end
end

--======================================================================
-- HUD
--======================================================================
local activeChest

local function closePanel()
	if gui then gui.Enabled = false end
	closeLid()
end

function setNotice(text)
	if noticeLbl then noticeLbl.Text = text or "" end
end

function buildHUD()
	gui = Instance.new("ScreenGui")
	gui.Name = "GardenDonationGui"; gui.ResetOnSpawn = false; gui.DisplayOrder = 100; gui.Enabled = false; gui.Parent = PlayerGui

	-- dim click-catcher backdrop (click outside closes)
	local backdrop = mkButton(gui, { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, Active = true })
	backdrop.MouseButton1Click:Connect(closePanel)

	-- PANEL (blue modal -- same style as the Garden Reward / shop panels)
	panel = mkFrame(gui, { Size = UDim2.new(0.6, 0, 0.62, 0), Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = BLUE_PANEL, ClipsDescendants = true, Active = true })
	mkCorner(panel, 24); mkStroke(panel, Color3.fromRGB(10, 40, 90), 3); soft(panel)

	-- TITLE BAR (no corner/filler needed -- the panel's ClipsDescendants rounds the header's top for us)
	local header = mkFrame(panel, { Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = BLUE_HEADER }); soft(header)
	mkLabel(header, { Text = "\xF0\x9F\x92\x9B Support the Garden", Font = Enum.Font.FredokaOne, TextSize = 27, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -120, 1, 0), Position = UDim2.new(0, 20, 0, 0), TextXAlignment = Enum.TextXAlignment.Left })
	local closeBtn = mkButton(header, { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.new(0, 42, 0, 42), Position = UDim2.new(1, -52, 0.5, 0), BackgroundColor3 = Color3.fromRGB(230, 96, 82), Text = "X", Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.new(1, 1, 1) }); mkCorner(closeBtn, 11); mkStroke(closeBtn, Color3.fromRGB(150, 40, 32), 2); juice(closeBtn)
	do local cp = Instance.new("UIPadding", closeBtn); for _, s in ipairs({"PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"}) do cp[s] = UDim.new(0, 9) end end
	closeBtn.MouseButton1Click:Connect(closePanel)

	-- SUBTITLE (two lines)
	mkLabel(panel, { Text = "Love the garden? Chip in to help keep it growing! \xF0\x9F\x8C\xBB", Font = Enum.Font.GothamMedium, TextSize = 17, TextColor3 = Color3.fromRGB(205, 228, 255), Size = UDim2.new(0.92, 0, 0, 22), Position = UDim2.new(0.5, 0, 0, 66), AnchorPoint = Vector2.new(0.5, 0), TextXAlignment = Enum.TextXAlignment.Center })
	mkLabel(panel, { Text = "Donations are pure support \xE2\x80\x94 no boosts, just our thanks. \xF0\x9F\x92\x9B", Font = Enum.Font.GothamMedium, TextSize = 17, TextColor3 = Color3.fromRGB(205, 228, 255), Size = UDim2.new(0.92, 0, 0, 22), Position = UDim2.new(0.5, 0, 0, 88), AnchorPoint = Vector2.new(0.5, 0), TextXAlignment = Enum.TextXAlignment.Center })

	-- 2x2 PRESET GRID
	local gridFrame = mkFrame(panel, { Size = UDim2.new(0.88, 0, 0, 232), Position = UDim2.new(0.5, 0, 0, 120), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -9, 0.5, -9); grid.CellPadding = UDim2.new(0, 14, 0, 14)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center; grid.VerticalAlignment = Enum.VerticalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder; grid.Parent = gridFrame

	for i, p in ipairs(PRESETS) do
		local card = mkFrame(gridFrame, { BackgroundColor3 = CARD_GREEN, LayoutOrder = i }); mkCorner(card, 16); mkStroke(card, Color3.fromRGB(28, 108, 50), 1.5); soft(card)
		do -- soft shine across the top of the card
			local sh = mkFrame(card, { Size = UDim2.new(1, -16, 0, 9), Position = UDim2.new(0, 8, 0, 5), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.78, BorderSizePixel = 0 }); mkCorner(sh, 5)
			local sg = Instance.new("UIGradient", sh); sg.Rotation = 90; sg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		end
		makeWateringCan(card, { Size = UDim2.new(0, 34, 0, 34), Position = UDim2.new(0, 8, 0, 10), BackgroundTransparency = 1 }) -- green watering-can card motif
		mkLabel(card, { Text = "\xF0\x9F\x92\x9B " .. string.format("%d R$", p.amount), Font = Enum.Font.FredokaOne, TextSize = 28, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0.5, 0, 0, 16), AnchorPoint = Vector2.new(0.5, 0), TextXAlignment = Enum.TextXAlignment.Center }) -- a heart + the amount
		local donateBtn = mkButton(card, { Size = UDim2.new(0.82, 0, 0, 38), Position = UDim2.new(0.5, 0, 1, -12), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = BTN_GREEN, Text = "\xF0\x9F\x92\x96 Donate", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = Color3.new(1, 1, 1) }); mkCorner(donateBtn, 12); mkStroke(donateBtn, BTN_GREEN2, 2); juice(donateBtn)
		local ds = Instance.new("UIScale"); ds.Parent = donateBtn -- hover pop
		donateBtn.MouseEnter:Connect(function() TweenService:Create(ds, TweenInfo.new(0.1), { Scale = 1.05 }):Play() end)
		donateBtn.MouseLeave:Connect(function() TweenService:Create(ds, TweenInfo.new(0.1), { Scale = 1 }):Play() end)
		donateBtn.MouseButton1Click:Connect(function() promptDonate(p.productId, p.amount) end)
	end

	-- NOTICE line (setup / personal thank-you) + FOOTER
	noticeLbl = mkLabel(panel, { Text = "", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.fromRGB(255, 235, 140), Size = UDim2.new(0.92, 0, 0, 22), Position = UDim2.new(0.5, 0, 1, -46), AnchorPoint = Vector2.new(0.5, 1), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })
	mkLabel(panel, { Text = "\xF0\x9F\x92\x9B Thank you for helping our garden grow! \xF0\x9F\x92\x9B", Font = Enum.Font.FredokaOne, TextSize = 19, TextColor3 = Color3.fromRGB(255, 245, 200), Size = UDim2.new(0.96, 0, 0, 28), Position = UDim2.new(0.5, 0, 1, -14), AnchorPoint = Vector2.new(0.5, 1), TextXAlignment = Enum.TextXAlignment.Center })
end

function showThanks(donorName, robux)
	if not (gui and gui.Enabled) then return end
	if donorName == player.Name then
		setNotice(string.format("\xF0\x9F\x8E\x89 Thank you for donating %d R$! \xF0\x9F\x92\x9B", robux))
	end
end

function openHUD(promptPart, chestModel)
	if not gui then buildHUD() end
	activeChest = chestModel
	gui.Enabled = true
	setNotice("")
	if chestModel then pcall(function() openLid(chestModel) end) end
	if promptPart then pcall(function() sparkle(promptPart.Position) end) end
end

--======================================================================
-- SERVER-WIDE THANK-YOU BANNER: shown to EVERYONE when any player donates (a gold-trimmed toast that slides in + fades).
--======================================================================
-- Goes through NotifyCenter's HERO lane at PURCHASE priority (a donation IS a real-money purchase).
-- It used to build a fresh toast at UDim2.new(0.5,0,0,16) on a DisplayOrder-95 ScreenGui with no gate
-- of any kind, so it drew ON TOP of the arrival/announce/reward banners -- and two simultaneous
-- donations stacked two toasts on the identical pixel.
local function showBanner(text)
	local NC = _G.NotifyCenter
	if not NC then return end
	NC.push({
		top      = "\xF0\x9F\x92\x9A DONATION",
		text     = text,
		color    = Color3.fromRGB(35, 120, 60),
		priority = NC.PRIORITY.PURCHASE,
		duration = 3.6,
	})
end

GardenDonationEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	local name  = tostring(data.name or "Someone")
	local robux = tonumber(data.robux) or 0
	showBanner(string.format("\xF0\x9F\x92\x9B %s donated %d R$ to the garden!", name, robux))
	showThanks(name, robux)
end)

-- PromptTriggered fires on THIS client for the local player's triggers -> open the donation HUD for OUR chest prompt.
-- (Keeps the treasure-box HUD link intact: the DonationChest's "DonationChestPrompt" is what opens this panel.)
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt and prompt.Name == "DonationChestPrompt" then
		local promptPart = (prompt.Parent and prompt.Parent:IsA("BasePart")) and prompt.Parent or nil
		local chestModel = prompt:FindFirstAncestorOfClass("Model")
		openHUD(promptPart, chestModel)
	end
end)

print("GARDEN DONATE GUI UPDATED")
