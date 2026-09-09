--!nonstrict
--======================================================================
-- PetTradeClient.client.luau  (LocalScript, StarterPlayerScripts)
--======================================================================
-- THE TRADE PAGE, COPIED FROM THE FOOD REALM'S PET HUB.  (CandyRealm port of the Space copy: the only
-- edits are the hub's names -- PetInventoryUI/Dim instead of PetHubGui, panel.Visible instead of
-- gui.Enabled -- and the realm's page-frame names. Everything the player touches is realm 1's.)
--
-- This is Food's TradeOverlay (PetFollow.client.lua, buildTradeUI) rebuilt widget for widget inside the Space
-- hub's Panel: same overlay geometry, same two 300px offer columns with the exchange arrow between them, same
-- tap-to-add shelf, same TokenRow, same status/rule strip, same CANCEL + CONFIRM in the same places. The only
-- deliberate differences are where Space genuinely differs:
--
--   * the pet list comes from _G.spaceListPets (this realm's inventory source) instead of latestInv
--   * pet pictures come from _G.petBuildModel (the FtF bridge's template builder)
--   * "Age" tiers don't exist here -- pets show their level, rares show RARE
--
-- Server half: PetTrade.server.luau -- the same remotes and the same anti-scam stage machine as Food.
--
-- ===== THE CLIENT IS A VIEW =====
-- Every number on this page, including the countdown and the token balance, is drawn from the state payload
-- the server pushes. Nothing is predicted locally: a client that counts its own timer down can show a window
-- the server has already closed.
--======================================================================

if _G.__CandyPetTradeClient then return end
_G.__CandyPetTradeClient = true

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PetTradeRequest = ReplicatedStorage:WaitForChild("PetTradeRequestEvent", 30)
local PetTradeRespond = ReplicatedStorage:WaitForChild("PetTradeRespondEvent", 30)
local PetTradePrompt  = ReplicatedStorage:WaitForChild("PetTradeRequestPromptEvent", 30)
local PetTradeOffer   = ReplicatedStorage:WaitForChild("PetTradeOfferEvent", 30)
local PetTradeConfirm = ReplicatedStorage:WaitForChild("PetTradeConfirmEvent", 30)
local PetTradeCancel  = ReplicatedStorage:WaitForChild("PetTradeCancelEvent", 30)
local PetTradeState   = ReplicatedStorage:WaitForChild("PetTradeStateEvent", 30)
if not (PetTradeRequest and PetTradeRespond and PetTradePrompt and PetTradeOffer
	and PetTradeConfirm and PetTradeCancel and PetTradeState) then
	warn("[TradeUI] trade remotes never appeared -- is PetTrade.server.luau running?")
	return
end

local function uicorner(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = i end
local function uistroke(i, col, th) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th or 2; s.Parent = i; return s end

--======================================================================
-- WAIT FOR THE HUB
--======================================================================
-- The overlay is a child of the hub's Panel, so the hub has to exist first. Polled rather than WaitForChild'd
-- end to end because the Panel and its nav bar arrive a frame apart.
local hubGui, hubPanel
do
	local deadline = os.clock() + 60
	repeat
		hubGui = playerGui:FindFirstChild("PetInventoryUI")
		hubPanel = hubGui and hubGui:FindFirstChild("Panel")
		if hubPanel then break end
		task.wait(0.25)
	until os.clock() > deadline
end
if not hubPanel then
	warn("[TradeUI] PetInventoryUI.Panel never appeared -- no trade page built")
	return
end

--======================================================================
-- HELPERS THE FOOD LAYOUT LEANS ON
--======================================================================
local tradeState = nil   -- latest server trade state (active=true while trading)

-- Food's petTier names age bands this realm doesn't have; here a pet is either RARE (purple, like the rare
-- hatches) or shows its level. Same two-value contract (label, colour) so the row/card code stays identical.
local function petTier(level, rare)
	if rare then return "RARE", Color3.fromRGB(200, 140, 255), true end
	return "Lv" .. tostring(level or 1), Color3.new(1, 1, 1), false
end

-- The pet's real 3D picture, same idea as Food's makeViewportIcon but fed from this realm's template builder.
-- Best-effort: a species with no template just leaves the slot empty rather than erroring the card.
local function makeViewportIcon(parentGui, petId, size, pos)
	if not _G.petBuildModel then return end
	local ok, model = pcall(_G.petBuildModel, petId)
	if not ok or not model then return end

	local vp = Instance.new("ViewportFrame")
	vp.Size = size; vp.Position = pos; vp.BackgroundTransparency = 1
	vp.Parent = parentGui

	model.Parent = vp
	local cam = Instance.new("Camera"); cam.Parent = vp; vp.CurrentCamera = cam
	local okP, cf, sz = pcall(function() return model:GetBoundingBox() end)
	if okP and cf and sz then
		local dist = math.max(sz.X, sz.Y, sz.Z) * 1.4 + 1
		cam.CFrame = CFrame.new(cf.Position + Vector3.new(0.6, 0.45, 1).Unit * dist, cf.Position)
	end
end

-- My whole inventory, keyed by storage key -- the same shape Food's latestInv.owned has, built from this
-- realm's list call. Re-fetched every render, so a completed trade repaints from the server's truth.
local function ownedByKey()
	local out = {}
	if _G.spaceListPets then
		local ok, pets = pcall(_G.spaceListPets)
		if ok and type(pets) == "table" then
			for _, p in ipairs(pets) do
				out[p.key] = {
					petId = tostring(p.key):gsub("#R$", ""),
					displayName = p.name, level = p.level or 1,
					rare = p.rare and true or false, count = p.count or 1,
				}
			end
		end
	end
	return out
end

-- a compact offered-pet row (Food's makeOfferRow). `onClick` makes it a button (add/remove).
local function makeOfferRow(parent, brief, order, onClick)
	local row = Instance.new(onClick and "TextButton" or "TextLabel"); row.Size = UDim2.new(1, -6, 0, 26); row.LayoutOrder = order
	row.BackgroundColor3 = Color3.fromRGB(160, 20, 93); row.Text = ""; row.Parent = parent; uicorner(row, 6)
	if onClick then row.AutoButtonColor = true end
	local tname, tcol = petTier(brief.level, brief.rare)
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1, -10, 1, 0); nm.Position = UDim2.new(0, 6, 0, 0); nm.BackgroundTransparency = 1
	nm.Font = Enum.Font.GothamBold; nm.TextSize = 12; nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextColor3 = tcol
	nm.Text = brief.name .. "  (" .. tname .. ")"; nm.Parent = row
	if onClick then row.MouseButton1Click:Connect(onClick) end
	return row
end

-- an OFFERED-pet CARD with the pet's real 3D PICTURE + name + level (anti-scam: each player can SEE exactly
-- what's being offered). Food's makeOfferCard, verbatim geometry.
local function makeOfferCard(parent, brief, order, onClick)
	local card = Instance.new(onClick and "TextButton" or "TextLabel")
	card.Size = UDim2.new(1, -6, 0, 76); card.LayoutOrder = order
	card.BackgroundColor3 = brief.rare and Color3.fromRGB(46, 28, 86) or Color3.fromRGB(160, 20, 93)
	card.Text = ""; if onClick then card.AutoButtonColor = true end
	card.Parent = parent; uicorner(card, 8)
	local tname, tcol, isVariant = petTier(brief.level, brief.rare)
	uistroke(card, isVariant and tcol or Color3.fromRGB(100, 10, 55), isVariant and 2 or 1)
	if brief.petId then
		makeViewportIcon(card, brief.petId, UDim2.new(0, 96, 0, 68), UDim2.new(0, 4, 0, 4))
	end
	local nm = Instance.new("TextLabel"); nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 14
	nm.TextColor3 = isVariant and tcol or Color3.new(1, 1, 1); nm.TextXAlignment = Enum.TextXAlignment.Left
	nm.Position = UDim2.new(0, 108, 0, 8); nm.Size = UDim2.new(1, -114, 0, 20); nm.Text = brief.name or brief.key; nm.Parent = card
	local lv = Instance.new("TextLabel"); lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold; lv.TextSize = 12
	lv.TextColor3 = tcol; lv.TextXAlignment = Enum.TextXAlignment.Left
	lv.Position = UDim2.new(0, 108, 0, 32); lv.Size = UDim2.new(1, -114, 0, 18)
	lv.Text = tname; lv.Parent = card
	if onClick then
		local h = Instance.new("TextLabel"); h.BackgroundTransparency = 1; h.Font = Enum.Font.Gotham; h.TextSize = 11; h.TextColor3 = Color3.fromRGB(255, 190, 190)
		h.TextXAlignment = Enum.TextXAlignment.Left; h.Position = UDim2.new(0, 108, 0, 52); h.Size = UDim2.new(1, -114, 0, 16); h.Text = "Click to remove \xE2\x9C\x95"; h.Parent = card
		card.MouseButton1Click:Connect(onClick)
	end
	return card
end

--======================================================================
-- TRADE OVERLAY (covers the panel body) -- Food's geometry, line for line
--======================================================================
local tradeOverlay = Instance.new("Frame"); tradeOverlay.Name = "TradeOverlay"; tradeOverlay.Size = UDim2.new(1, -24, 1, -130); tradeOverlay.Position = UDim2.new(0, 12, 0, 110) -- -130: same band outline as the hub's pages, clear of the panel's rounded corner
tradeOverlay.BackgroundColor3 = Color3.fromRGB(140, 16, 81); tradeOverlay.Visible = false; tradeOverlay.ZIndex = 3; tradeOverlay.Parent = hubPanel; uicorner(tradeOverlay, 12); uistroke(tradeOverlay, Color3.fromRGB(100, 10, 55), 2)
tradeOverlay.ClipsDescendants = true -- same band-clip as the hub's other pages: nothing inside may cross the border stroke
local ovTitle = Instance.new("TextLabel"); ovTitle.Size = UDim2.new(1, -120, 0, 28); ovTitle.Position = UDim2.new(0, 12, 0, 8); ovTitle.BackgroundTransparency = 1; ovTitle.ZIndex = 4
ovTitle.Font = Enum.Font.GothamBold; ovTitle.TextSize = 18; ovTitle.TextColor3 = Color3.fromRGB(255, 215, 0); ovTitle.TextXAlignment = Enum.TextXAlignment.Left; ovTitle.Text = "Trade"; ovTitle.Parent = tradeOverlay
local ovBack = Instance.new("TextButton"); ovBack.Size = UDim2.new(0, 100, 0, 28); ovBack.Position = UDim2.new(1, -108, 0, 8); ovBack.BackgroundColor3 = Color3.fromRGB(120, 120, 120); ovBack.ZIndex = 4
ovBack.Font = Enum.Font.GothamBold; ovBack.TextSize = 13; ovBack.TextColor3 = Color3.new(1, 1, 1); ovBack.Text = "\xE2\x97\x80 Pets"; ovBack.Parent = tradeOverlay; uicorner(ovBack, 8)

-- VIEW 1: pick a player to request a trade
local pickerView = Instance.new("Frame"); pickerView.Size = UDim2.new(1, -16, 1, -46); pickerView.Position = UDim2.new(0, 8, 0, 42); pickerView.BackgroundTransparency = 1; pickerView.ZIndex = 4; pickerView.Parent = tradeOverlay
local pickerScroll = Instance.new("ScrollingFrame"); pickerScroll.Size = UDim2.new(1, 0, 1, 0); pickerScroll.BackgroundTransparency = 1; pickerScroll.BorderSizePixel = 0; pickerScroll.ZIndex = 4
pickerScroll.ScrollBarThickness = 6; pickerScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 215, 0); pickerScroll.CanvasSize = UDim2.new(0, 0, 0, 0); pickerScroll.Parent = pickerView
local pickerLayout = Instance.new("UIListLayout"); pickerLayout.Padding = UDim.new(0, 6); pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder; pickerLayout.Parent = pickerScroll

-- VIEW 2: the trade window (your side / their side / add list / confirm + cancel)
local windowView = Instance.new("Frame"); windowView.Size = UDim2.new(1, -16, 1, -46); windowView.Position = UDim2.new(0, 8, 0, 42); windowView.BackgroundTransparency = 1; windowView.Visible = false; windowView.ZIndex = 4; windowView.Parent = tradeOverlay
local function colTitle(text, x) local l = Instance.new("TextLabel"); l.Size = UDim2.new(0, 310, 0, 18); l.Position = UDim2.new(0, x, 0, 0); l.BackgroundTransparency = 1; l.ZIndex = 4; l.Font = Enum.Font.GothamBold; l.TextSize = 14; l.TextColor3 = Color3.fromRGB(255, 215, 0); l.TextXAlignment = Enum.TextXAlignment.Left; l.Text = text; l.Parent = windowView; return l end
local function colScroll(x, y, h, w) local s = Instance.new("ScrollingFrame"); s.Size = UDim2.new(0, w or 300, 0, h); s.Position = UDim2.new(0, x, 0, y); s.BackgroundColor3 = Color3.fromRGB(104, 12, 59); s.BorderSizePixel = 0; s.ScrollBarThickness = 5; s.CanvasSize = UDim2.new(0, 0, 0, 0); s.ZIndex = 4; s.Parent = windowView; uicorner(s, 8); local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0, 4); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = s; return s end

-- THE TRADE FLOOR: two identical panels, an exchange arrow between them, one READY underneath.
-- 300 + 48 + 300 = 648, so the two offers are the same width to the pixel and the arrow sits dead centre.
colTitle("YOUR OFFER", 0)
do
	local sb = colTitle("(click an item to remove)", 0)
	sb.Position = UDim2.new(0, 0, 0, 17); sb.Size = UDim2.new(0, 300, 0, 14)
	sb.Font = Enum.Font.Gotham; sb.TextSize = 11; sb.TextColor3 = Color3.fromRGB(250, 175, 217)
end
local yourOfferScroll = colScroll(0, 34, 140)

-- EXCHANGE ARROW, centred in the 48px gutter. Purely a sign that these two piles swap -- no state, no clicks.
do
	local sw = Instance.new("TextLabel"); sw.Size = UDim2.new(0, 48, 0, 48); sw.Position = UDim2.new(0, 300, 0, 80)
	sw.BackgroundTransparency = 1; sw.Font = Enum.Font.FredokaOne; sw.TextScaled = true; sw.ZIndex = 4
	sw.TextColor3 = Color3.fromRGB(255, 215, 0); sw.Text = "\xE2\x87\x84"; sw.Parent = windowView
	uistroke(sw, Color3.new(0, 0, 0), 2)
end

colTitle("THEIR OFFER", 348)
do
	local sb = colTitle("(what you will receive)", 348)
	sb.Position = UDim2.new(0, 348, 0, 17); sb.Size = UDim2.new(0, 300, 0, 14)
	sb.Font = Enum.Font.Gotham; sb.TextSize = 11; sb.TextColor3 = Color3.fromRGB(250, 175, 217)
end
local theirOfferScroll = colScroll(348, 34, 140)

-- TAP TO ADD, full width under both panels -- a permanently visible shelf, never a floating picker.
local addTitleLbl = colTitle("YOUR PETS & SKINS (click to add)", 0)
addTitleLbl.Position = UDim2.new(0, 0, 0, 178); addTitleLbl.Size = UDim2.new(0, 648, 0, 12)
addTitleLbl.Font = Enum.Font.Gotham; addTitleLbl.TextSize = 11; addTitleLbl.TextColor3 = Color3.fromRGB(250, 175, 217)
local addScroll = colScroll(0, 192, 40, 648)

local statusLbl = Instance.new("TextLabel"); statusLbl.Size = UDim2.new(0, 648, 0, 28); statusLbl.Position = UDim2.new(0, 0, 0, 264); statusLbl.BackgroundTransparency = 1; statusLbl.ZIndex = 4
statusLbl.Font = Enum.Font.GothamBold; statusLbl.TextSize = 12; statusLbl.TextColor3 = Color3.new(1, 1, 1); statusLbl.TextWrapped = true
statusLbl.TextXAlignment = Enum.TextXAlignment.Center; statusLbl.TextYAlignment = Enum.TextYAlignment.Top; statusLbl.Text = ""; statusLbl.Parent = windowView
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 12; c.Parent = statusLbl end
-- The rule, stated once and always on screen -- what stops "I pressed ready and nothing happened" from
-- reading as a broken button.
do
	local rule = Instance.new("TextLabel"); rule.Size = UDim2.new(0, 648, 0, 14); rule.Position = UDim2.new(0, 0, 0, 332)
	rule.BackgroundTransparency = 1; rule.Font = Enum.Font.Gotham; rule.TextSize = 11; rule.ZIndex = 4
	rule.TextColor3 = Color3.fromRGB(250, 175, 217); rule.TextXAlignment = Enum.TextXAlignment.Center
	rule.Text = "Both players must be ready to trade."; rule.Parent = windowView
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 11; c.Parent = rule end
end

-- CRATE TOKENS half of the deal. Coins are deliberately absent -- gameplay currency is not tradeable.
-- Widgets found by NAME in the render, exactly as Food does it.
do
	local row = Instance.new("Frame"); row.Name = "TokenRow"
	row.Size = UDim2.new(0, 648, 0, 26); row.Position = UDim2.new(0, 0, 0, 236); row.ZIndex = 4
	row.BackgroundColor3 = Color3.fromRGB(104, 12, 59); row.Parent = windowView; uicorner(row, 8)
	local lead = Instance.new("TextLabel"); lead.Name = "Lead"
	lead.Size = UDim2.new(0, 186, 1, 0); lead.Position = UDim2.new(0, 8, 0, 0); lead.ZIndex = 4
	lead.BackgroundTransparency = 1; lead.Font = Enum.Font.GothamBold; lead.TextSize = 12
	lead.TextColor3 = Color3.fromRGB(255, 215, 0); lead.TextXAlignment = Enum.TextXAlignment.Left
	lead.Text = "Tokens:"; lead.Parent = row
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 12; c.Parent = lead; lead.TextScaled = true end
	local box = Instance.new("TextBox"); box.Name = "Box"
	box.Size = UDim2.new(0, 92, 0, 22); box.Position = UDim2.new(0, 196, 0, 4); box.ZIndex = 4
	box.BackgroundColor3 = Color3.fromRGB(170, 24, 104); box.Font = Enum.Font.GothamBold; box.TextSize = 13
	box.TextColor3 = Color3.new(1, 1, 1); box.Text = "0"; box.ClearTextOnFocus = false
	box.PlaceholderText = "0"; box.Parent = row; uicorner(box, 6)
	local set = Instance.new("TextButton"); set.Name = "Set"
	set.Size = UDim2.new(0, 66, 0, 22); set.Position = UDim2.new(0, 294, 0, 4); set.ZIndex = 4
	set.BackgroundColor3 = Color3.fromRGB(50, 200, 50); set.Font = Enum.Font.GothamBold; set.TextSize = 12
	set.TextColor3 = Color3.new(1, 1, 1); set.Text = "OFFER"; set.Parent = row; uicorner(set, 6)
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 12; c.Parent = set; set.TextScaled = true end
	local function send()
		local n = math.floor(tonumber(box.Text) or 0)
		if n < 0 then n = 0 end
		box.Text = tostring(n)
		local ev = ReplicatedStorage:FindFirstChild("PetTradeTokensEvent")
		if ev then pcall(function() ev:FireServer(n) end) end
	end
	set.MouseButton1Click:Connect(send)
	box.FocusLost:Connect(function(enter) if enter then send() end end)
end

-- READY is CENTRED and the biggest control on the page. CANCEL beside it, smaller and red.
local cancelBtn = Instance.new("TextButton"); cancelBtn.Size = UDim2.new(0, 110, 0, 30); cancelBtn.Position = UDim2.new(0, 96, 0, 298); cancelBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60); cancelBtn.ZIndex = 4
cancelBtn.Font = Enum.Font.GothamBold; cancelBtn.TextSize = 15; cancelBtn.TextColor3 = Color3.new(1, 1, 1); cancelBtn.Text = "CANCEL"; cancelBtn.Parent = windowView; uicorner(cancelBtn, 8); uistroke(cancelBtn, Color3.new(0, 0, 0), 2)
local confirmBtn = Instance.new("TextButton"); confirmBtn.Size = UDim2.new(0, 200, 0, 34); confirmBtn.Position = UDim2.new(0, 224, 0, 296); confirmBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 50); confirmBtn.ZIndex = 4
confirmBtn.Font = Enum.Font.GothamBold; confirmBtn.TextSize = 15; confirmBtn.TextColor3 = Color3.new(1, 1, 1); confirmBtn.Text = "CONFIRM"; confirmBtn.Parent = windowView; uicorner(confirmBtn, 8); uistroke(confirmBtn, Color3.new(0, 0, 0), 2)

--======================================================================
-- THE TWO VIEWS
--======================================================================
local function clearScroll(s) for _, c in ipairs(s:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end end

local function refreshPicker()
	clearScroll(pickerScroll)
	local order, n = 0, 0
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= player then
			n = n + 1; order = order + 1
			local row = Instance.new("Frame"); row.Size = UDim2.new(1, -6, 0, 30); row.LayoutOrder = order; row.BackgroundColor3 = Color3.fromRGB(160, 20, 93); row.ZIndex = 4; row.Parent = pickerScroll; uicorner(row, 6)
			local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1, -94, 1, 0); nm.Position = UDim2.new(0, 8, 0, 0); nm.BackgroundTransparency = 1; nm.ZIndex = 4; nm.Font = Enum.Font.GothamBold; nm.TextSize = 13; nm.TextColor3 = Color3.new(1, 1, 1); nm.TextXAlignment = Enum.TextXAlignment.Left; nm.Text = pl.DisplayName .. " (@" .. pl.Name .. ")"; nm.Parent = row
			local req = Instance.new("TextButton"); req.Size = UDim2.new(0, 82, 0, 24); req.Position = UDim2.new(1, -86, 0, 3); req.BackgroundColor3 = Color3.fromRGB(50, 200, 50); req.ZIndex = 4; req.Font = Enum.Font.GothamBold; req.TextSize = 12; req.TextColor3 = Color3.new(1, 1, 1); req.Text = "REQUEST"; req.Parent = row; uicorner(req, 6)
			local uid = pl.UserId
			req.MouseButton1Click:Connect(function()
				pcall(function() PetTradeRequest:FireServer(uid) end)
				ovTitle.Text = "Request sent to " .. pl.DisplayName .. "..."
			end)
		end
	end
	if n == 0 then
		local e = Instance.new("TextLabel"); e.Size = UDim2.new(1, -6, 0, 40); e.BackgroundTransparency = 1; e.ZIndex = 4; e.Font = Enum.Font.Gotham; e.TextSize = 13; e.TextColor3 = Color3.fromRGB(255, 200, 229); e.TextWrapped = true; e.Text = "No other players in the server to trade with."; e.Parent = pickerScroll
	end
	pickerScroll.CanvasSize = UDim2.new(0, 0, 0, n * 36 + 8)
end

local function showPicker()
	pickerView.Visible = true; windowView.Visible = false
	ovTitle.Text = "Trade \xE2\x80\x94 pick a player"
	refreshPicker()
end

local function renderTradeWindow(state)
	pickerView.Visible = false; windowView.Visible = true; ovTitle.Text = "Trading with " .. tostring(state.withName)
	-- FROZEN once both sides are ready: the add/remove callbacks are dropped entirely so the buttons are
	-- inert, matching the server, which refuses offer changes outside the offer stage.
	local frozen = (state.locked == true)

	clearScroll(yourOfferScroll)
	for i, b in ipairs(state.mine or {}) do
		makeOfferCard(yourOfferScroll, b, i, (not frozen) and function()
			pcall(function() PetTradeOffer:FireServer(b.key or b.petId, false) end)
		end or nil)
	end
	yourOfferScroll.CanvasSize = UDim2.new(0, 0, 0, #(state.mine or {}) * 80 + 4)

	clearScroll(theirOfferScroll)
	for i, b in ipairs(state.theirs or {}) do makeOfferCard(theirOfferScroll, b, i, nil) end
	theirOfferScroll.CanvasSize = UDim2.new(0, 0, 0, #(state.theirs or {}) * 80 + 4)

	-- the tap-to-add shelf: everything owned that is not already offered
	local offered = {}
	for _, b in ipairs(state.mine or {}) do offered[b.key or b.petId] = true end
	clearScroll(addScroll)
	local idx = 0
	for skey, p in pairs(ownedByKey()) do
		if not offered[skey] then
			idx = idx + 1
			local rowName = p.displayName .. (((p.count or 1) > 1) and ("  x" .. p.count) or "")
			makeOfferRow(addScroll, { petId = p.petId, name = rowName, level = p.level, rare = p.rare }, idx,
				(not frozen) and function() pcall(function() PetTradeOffer:FireServer(skey, true) end) end or nil)
		end
	end
	-- SKINS in the same list, under the pets. Keys come back already "SKIN:"-prefixed -- exactly what
	-- PetTradeOfferEvent expects.
	if _G.skinTradeList then
		local okSkins, skins = pcall(_G.skinTradeList)
		if okSkins and type(skins) == "table" then
			for _, sk in ipairs(skins) do
				if not offered[sk.key] then
					idx = idx + 1
					local key = sk.key
					local canAdd = not frozen
					local srow = Instance.new(canAdd and "TextButton" or "TextLabel")
					srow.Size = UDim2.new(1, -6, 0, 26); srow.LayoutOrder = idx; srow.ZIndex = 4
					srow.BackgroundColor3 = Color3.fromRGB(160, 20, 93); srow.Text = ""; srow.Parent = addScroll; uicorner(srow, 6)
					if canAdd then srow.AutoButtonColor = true end
					local stripe = Instance.new("Frame"); stripe.Size = UDim2.new(0, 5, 1, -8); stripe.Position = UDim2.new(0, 4, 0, 4)
					stripe.BorderSizePixel = 0; stripe.BackgroundColor3 = sk.color or Color3.fromRGB(200, 200, 200); stripe.ZIndex = 4
					stripe.Parent = srow; uicorner(stripe, 3)
					local snm = Instance.new("TextLabel"); snm.Size = UDim2.new(1, -18, 1, 0); snm.Position = UDim2.new(0, 14, 0, 0); snm.ZIndex = 4
					snm.BackgroundTransparency = 1; snm.Font = Enum.Font.GothamBold; snm.TextSize = 12
					snm.TextXAlignment = Enum.TextXAlignment.Left; snm.TextColor3 = sk.color or Color3.new(1, 1, 1)
					snm.Text = sk.name .. "  (" .. tostring(sk.tier) .. (((sk.count or 1) > 1) and ("  x" .. sk.count) or "") .. ")"
					snm.Parent = srow
					if canAdd then srow.MouseButton1Click:Connect(function() pcall(function() PetTradeOffer:FireServer(key, true) end) end) end
				end
			end
		end
	end
	addScroll.CanvasSize = UDim2.new(0, 0, 0, idx * 30 + 4)

	-- TOKEN half of the deal. The box is only rewritten when it does NOT have focus, so a number being typed
	-- is never yanked out from under the player by an incoming push.
	local myTok, theirTok = state.myTokens or 0, state.theirTokens or 0
	local tokRow = windowView:FindFirstChild("TokenRow")
	if tokRow then
		local box, set, lead = tokRow:FindFirstChild("Box"), tokRow:FindFirstChild("Set"), tokRow:FindFirstChild("Lead")
		if box then
			if not box:IsFocused() then box.Text = tostring(myTok) end
			box.TextEditable = not frozen
		end
		if set then set.BackgroundColor3 = frozen and Color3.fromRGB(120, 120, 120) or Color3.fromRGB(50, 200, 50) end
		if lead then lead.Text = "Tokens:  (you have " .. tostring(state.myTokenBalance or 0) .. ")" end
	end

	-- STATUS + the one button whose meaning changes with the stage.
	local stage = state.stage or "offer"
	local st = state.status
	local tokenLine = ""
	if myTok > 0 or theirTok > 0 then
		tokenLine = "\nYou: " .. myTok .. " tokens   |   Them: " .. theirTok .. " tokens"
	end

	if stage == "countdown" then
		statusLbl.Text = "\xE2\x8F\xB3 Offers LOCKED. Check them carefully!\nFinal confirmation in "
			.. tostring(state.countdown or 0) .. "s" .. tokenLine
		statusLbl.TextColor3 = Color3.fromRGB(255, 205, 90)
		confirmBtn.Text = "LOCKED  " .. tostring(state.countdown or 0) .. "s"
		confirmBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	elseif stage == "final" then
		if state.myFinal then
			statusLbl.Text = "You confirmed.\nWaiting for " .. tostring(state.withName) .. " to confirm..." .. tokenLine
		else
			statusLbl.Text = "\xE2\x9A\xA0 LAST CHANCE - this is exactly what you get.\nPress CONFIRM TRADE to finish." .. tokenLine
		end
		statusLbl.TextColor3 = state.myFinal and Color3.new(1, 1, 1) or Color3.fromRGB(255, 235, 120)
		confirmBtn.Text = state.myFinal and "\xE2\x9C\x94 CONFIRMED" or "CONFIRM TRADE"
		confirmBtn.BackgroundColor3 = state.myFinal and Color3.fromRGB(120, 120, 120) or Color3.fromRGB(255, 170, 40)
	else
		statusLbl.Text = ((st == "waiting_them" and ("You are ready.\nWaiting for " .. tostring(state.withName) .. "..."))
			or (st == "waiting_you" and (tostring(state.withName) .. " is ready.\nYour move!"))
			or "Add pets, skins or tokens, then both press READY.\n(any change resets both)") .. tokenLine
		statusLbl.TextColor3 = Color3.new(1, 1, 1)
		confirmBtn.Text = state.myConfirm and "\xE2\x9C\x94 READY" or "READY"
		confirmBtn.BackgroundColor3 = state.myConfirm and Color3.fromRGB(120, 120, 120) or Color3.fromRGB(50, 200, 50)
	end
end

cancelBtn.MouseButton1Click:Connect(function() pcall(function() PetTradeCancel:FireServer() end) end)
confirmBtn.MouseButton1Click:Connect(function() pcall(function() PetTradeConfirm:FireServer() end) end)

--======================================================================
-- HUB WIRING -- the TRADE nav tab shows this overlay, like Food's router
--======================================================================
-- The hub's own pages, hidden by name while the overlay is up and restored on leave.
local HUB_PAGES = { QuestsOverlay = true, dinoPetsPage = true, foodPetsPage = true, TradeOverlayLegacy = true }
local hiddenPages = {}

local HUB_NAV_BG   = Color3.fromRGB(78, 30, 48)      -- the hub's unselected tab (Space's palette)
local HUB_LIT_TEXT = Color3.fromRGB(92, 58, 8)

local function syncNav(tradeOn)
	local nav = _G.PetHub and _G.PetHub.navButtons
	if type(nav) ~= "table" then return end
	-- Leaving the trade page always lands on the pet grid (ovBack and the state handler both route there), so
	-- "not trade" lights PETS rather than leaving the whole bar dark -- the hub's own router never re-lights.
	local litId = tradeOn and "trade" or "pets"
	for tid, b in pairs(nav) do
		local on = (tid == litId)
		pcall(function()
			b.BackgroundColor3 = on and Color3.fromRGB(255, 215, 0) or HUB_NAV_BG
			b.TextColor3 = on and HUB_LIT_TEXT or Color3.fromRGB(255, 215, 0)
			local st = b:FindFirstChildOfClass("UIStroke")
			if st then st.Thickness = on and 2.5 or 1.5 end
		end)
	end
end

local function setOverlay(on)
	if on then
		hiddenPages = {}
		for _, c in ipairs(hubPanel:GetChildren()) do
			if HUB_PAGES[c.Name] and c.Visible then
				hiddenPages[#hiddenPages + 1] = c
				c.Visible = false
			end
		end
		tradeOverlay.Visible = true
	else
		tradeOverlay.Visible = false
		for _, c in ipairs(hiddenPages) do
			if c.Parent then c.Visible = true end
		end
		hiddenPages = {}
	end
	syncNav(on)
end

local function openTradePage()
	-- One line per open, so a log settles "did TRADE reach the new page" without guessing.
	print("[TradeUI] TRADE tab -> in-panel trade page (" ..
		((tradeState and tradeState.active) and "live trade window" or "player picker") .. ")")
	-- The FRIENDS tab (TradeRequests) hides this overlay's views while its page is up. showPicker below
	-- re-shows them without knowing that -- so close the tab FIRST, or both pages render stacked and the
	-- higher ZIndex (ours) buries the friends page while its tab still claims it is open.
	if _G.tradeReqCloseTab then pcall(_G.tradeReqCloseTab) end
	if hubPanel then hubPanel.Visible = true end
	local dim = hubGui and hubGui:FindFirstChild("Dim"); if dim then dim.Visible = true end
	if _G.MainMenuManager then pcall(_G.MainMenuManager.notifyOpened, "PetInv") end
	setOverlay(true)
	-- a live session shows the trade window; otherwise the picker, exactly as Food's TRADE tab behaves
	if tradeState and tradeState.active then renderTradeWindow(tradeState) else showPicker() end
end

-- WRAPPED, not replaced. showPage already routes pets/quests to the grid and crates/tokens to the crate
-- panel; this claims "trade" and hands every other id straight back.
--
-- ===== WAIT FOR THE HUB'S ROUTER FIRST =====
-- The hub creates its Panel near the TOP of a 1400-line script and assigns _G.PetHub.showPage at the very
-- BOTTOM, unconditionally. This script wakes up the moment the Panel exists -- wrap then, and the hub's own
-- assignment lands a moment later and clobbers the wrapper, quietly routing TRADE back to the crate window.
-- So the wrap waits for the router to exist. The nav buttons look showPage up at CLICK time, so wrapping
-- late costs nothing.
local priorShowPage = nil
task.spawn(function()
	local deadline = os.clock() + 30
	while os.clock() < deadline do
		if _G.PetHub and _G.PetHub.showPage then break end
		task.wait(0.1)
	end
	priorShowPage = _G.PetHub and _G.PetHub.showPage
	_G.PetHub = _G.PetHub or {}
	_G.PetHub.showPage = function(page)
		if page == "trade" then return openTradePage() end
		if tradeOverlay.Visible then setOverlay(false) end
		if priorShowPage then return priorShowPage(page) end
	end
end)

-- ◀ Pets goes back to the grid, like Food's ovBack.
ovBack.MouseButton1Click:Connect(function()
	setOverlay(false)
	if priorShowPage then pcall(priorShowPage, "pets") end
end)

-- The hub's X hides the PANEL (openPanel(false)) without telling anyone; the overlay must reset with it.
hubPanel:GetPropertyChangedSignal("Visible"):Connect(function()
	if not hubPanel.Visible and tradeOverlay.Visible then setOverlay(false) end
end)

--======================================================================
-- SERVER STATE + THE INVITE POPUP
--======================================================================
PetTradeState.OnClientEvent:Connect(function(state)
	tradeState = state
	if state and state.active then
		-- ensure the hub is open so both players see the trade window
		if hubPanel then hubPanel.Visible = true end
		local dim = hubGui and hubGui:FindFirstChild("Dim"); if dim then dim.Visible = true end
		if _G.MainMenuManager then pcall(_G.MainMenuManager.notifyOpened, "PetInv") end
		if not tradeOverlay.Visible then setOverlay(true) end
		renderTradeWindow(state)
	else
		local reason = state and state.reason
		print("[Trade] window closed (" .. tostring(reason) .. ")")
		tradeState = nil
		if tradeOverlay.Visible then
			ovTitle.Text = "Trade " .. (reason and ("\xE2\x80\x94 " .. reason) or "closed")
			showPicker()
		end
		-- A completed trade changed the pet list; the hub re-fetches rather than patches.
		if reason == "completed" and _G.PetHub and _G.PetHub.refresh then pcall(_G.PetHub.refresh) end
	end
end)

-- incoming-request popup (shows even if the hub is closed) -- Food's, verbatim
local reqPopup = Instance.new("Frame"); reqPopup.Name = "TradeRequestPopup"; reqPopup.AnchorPoint = Vector2.new(0.5, 0.5); reqPopup.Position = UDim2.new(0.5, 0, 0.4, 0); reqPopup.Size = UDim2.new(0, 320, 0, 130)
reqPopup.BackgroundColor3 = Color3.fromRGB(185, 25, 117); reqPopup.Visible = false; reqPopup.ZIndex = 50; reqPopup.Parent = hubGui; uicorner(reqPopup, 12); uistroke(reqPopup, Color3.fromRGB(255, 215, 0), 3)
local reqLbl = Instance.new("TextLabel"); reqLbl.Size = UDim2.new(1, -20, 0, 60); reqLbl.Position = UDim2.new(0, 10, 0, 10); reqLbl.BackgroundTransparency = 1; reqLbl.ZIndex = 51; reqLbl.Font = Enum.Font.GothamBold; reqLbl.TextSize = 16; reqLbl.TextColor3 = Color3.new(1, 1, 1); reqLbl.TextWrapped = true; reqLbl.Text = ""; reqLbl.Parent = reqPopup
local reqAccept = Instance.new("TextButton"); reqAccept.Size = UDim2.new(0, 140, 0, 38); reqAccept.Position = UDim2.new(0, 12, 1, -46); reqAccept.BackgroundColor3 = Color3.fromRGB(50, 200, 50); reqAccept.ZIndex = 51; reqAccept.Font = Enum.Font.GothamBold; reqAccept.TextSize = 15; reqAccept.TextColor3 = Color3.new(1, 1, 1); reqAccept.Text = "ACCEPT"; reqAccept.Parent = reqPopup; uicorner(reqAccept, 8)
local reqDecline = Instance.new("TextButton"); reqDecline.Size = UDim2.new(0, 140, 0, 38); reqDecline.Position = UDim2.new(1, -152, 1, -46); reqDecline.BackgroundColor3 = Color3.fromRGB(220, 60, 60); reqDecline.ZIndex = 51; reqDecline.Font = Enum.Font.GothamBold; reqDecline.TextSize = 15; reqDecline.TextColor3 = Color3.new(1, 1, 1); reqDecline.Text = "DECLINE"; reqDecline.Parent = reqPopup; uicorner(reqDecline, 8)
reqAccept.MouseButton1Click:Connect(function() reqPopup.Visible = false; pcall(function() PetTradeRespond:FireServer(true) end) end)
reqDecline.MouseButton1Click:Connect(function() reqPopup.Visible = false; pcall(function() PetTradeRespond:FireServer(false) end) end)
PetTradePrompt.OnClientEvent:Connect(function(_fromUserId, fromName)
	reqLbl.Text = "\xF0\x9F\x94\x81 " .. tostring(fromName) .. " wants to trade pets with you!"
	-- The popup lives inside PetHubGui, which may be DISABLED (hub closed). It must show anyway -- an invite
	-- that can only be seen with the hub already open would look like the feature not working.
	if hubPanel and not hubPanel.Visible then hubPanel.Visible = true; local dim = hubGui and hubGui:FindFirstChild("Dim"); if dim then dim.Visible = true end; setOverlay(false) end
	reqPopup.Visible = true
	task.delay(15, function() if reqPopup.Visible then reqPopup.Visible = false end end)   -- auto-dismiss if ignored
end)

-- Refresh hooks: a completed trade changes the pet list under the hub.
local changed = ReplicatedStorage:FindFirstChild("CandyPetsChangedEvent")
if changed and changed:IsA("RemoteEvent") then
	changed.OnClientEvent:Connect(function()
		if _G.PetHub and _G.PetHub.refresh then pcall(_G.PetHub.refresh) end
		if tradeOverlay.Visible and tradeState and tradeState.active then renderTradeWindow(tradeState) end
	end)
end

-- Entry point for the FRIENDS tab's TRADE NOW button and anything else that wants to start a trade.
_G.spaceStartTrade = function(userId)
	if type(userId) == "number" and userId > 0 then PetTradeRequest:FireServer(userId) end
end

print("[TradeUI] Food-realm trade page ready inside the pet hub (picker + live window)")
