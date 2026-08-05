--======================================================================
-- RebirthClient.client.luau  (LocalScript)
--======================================================================
-- The REBIRTH panel. Opens from the REBIRTH side button (repurposed INVITE button in CoreClient) via
-- _G.toggleRebirth. All authority is the server's (RebirthSystem.server.lua) -- this only draws state and
-- fires "rebirth"/"state". Shows your rebirth count, current + next boosts, the requirement checklist, and a
-- gated REBIRTH button with a confirm step.
--======================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui    = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("RebirthEvent", 30)
if not remote then return end

local screen = Instance.new("ScreenGui")
screen.Name = "RebirthGui"; screen.ResetOnSpawn = false; screen.DisplayOrder = 58; screen.Parent = gui

local S = { rebirths = 0, coinMult = 1, speedMult = 1, luckMult = 1, nextCoin = 1.25, nextSpeed = 1.03, nextLuck = 1.15,
	reqs = { islands = false, space = false, dino = false, candy = false }, reqIsland = 14, canRebirth = false, petMilestones = {} }

--------------------------------------------------------------------------------
-- style helpers
--------------------------------------------------------------------------------
local function corner(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = i; return c end
local function stroke(i, col, t, tr) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 2; s.Transparency = tr or 0; s.Parent = i; return s end
local function grad(i, a, b, rot) local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(a, b); g.Rotation = rot or 90; g.Parent = i; return g end
-- viral pet-sim "juicy" bevel: a top-bright -> bottom-dark gradient that MULTIPLIES the element's colour, so it
-- reads as a rounded 3D button in ANY state colour. Pair with a thick outline for the chunky look.
local function juice(i) local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(168,168,168)); g.Rotation = 90; g.Parent = i; return g end

-- WARM theme (cozy browns + orange + gold, like the shop) -- names kept from the old palette so nothing else changes.
local COL_BG     = Color3.fromRGB(74, 40, 72)   -- warm plum panel
local COL_BG2    = Color3.fromRGB(110, 58, 104)
local COL_CARD   = Color3.fromRGB(52, 28, 52)   -- deep plum cards
local COL_PURP   = Color3.fromRGB(214, 96, 180) -- warm magenta header / accent
local COL_PURP_D = Color3.fromRGB(176, 68, 146)
local COL_GOLD   = Color3.fromRGB(255, 196, 82)
local COL_GREEN  = Color3.fromRGB(120, 200, 88) -- warm-leaning green, only for "go"/complete
local COL_RED    = Color3.fromRGB(230, 96, 82)
local COL_TXT    = Color3.fromRGB(252, 234, 224) -- warm cream text
local COL_EDGE   = Color3.fromRGB(158, 84, 138)

--------------------------------------------------------------------------------
-- shell
--------------------------------------------------------------------------------
local dim = Instance.new("TextButton")
dim.Size = UDim2.fromScale(1, 1); dim.BackgroundTransparency = 1; dim.Text = ""; dim.AutoButtonColor = false
dim.Visible = false; dim.Parent = screen

-- drop shadow behind the panel (the soft lift the popular pet games have)
local shadow = Instance.new("ImageLabel")
shadow.AnchorPoint = Vector2.new(0.5, 0.5); shadow.Position = UDim2.new(0.5, 0, 0.5, -38); shadow.Size = UDim2.fromOffset(720, 546)
shadow.BackgroundTransparency = 1; shadow.Image = "rbxassetid://1316045217"; shadow.ImageColor3 = Color3.new(0, 0, 0)
shadow.ImageTransparency = 0.62; shadow.ScaleType = Enum.ScaleType.Slice; shadow.SliceCenter = Rect.new(10, 10, 118, 118)
shadow.Visible = false; shadow.ZIndex = 0; shadow.Parent = screen

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.new(0.5, 0, 0.5, -45) -- same 700x520 + up-nudge as the Shop
panel.Size = UDim2.fromOffset(700, 520); panel.BackgroundColor3 = COL_BG; panel.Visible = false; panel.Parent = screen
corner(panel, 26); grad(panel, COL_BG2, COL_BG, 90); stroke(panel, Color3.fromRGB(30, 14, 30), 4) -- rounder + thick warm-dark outline

local header = Instance.new("Frame")
header.Position = UDim2.fromOffset(16, 14); header.Size = UDim2.new(1, -64, 0, 58); header.BackgroundColor3 = COL_PURP_D
header.Parent = panel; corner(header, 14); grad(header, Color3.fromRGB(228, 118, 198), COL_PURP_D, 20); stroke(header, Color3.fromRGB(255, 216, 240), 1.5, 0.3)
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1; title.Position = UDim2.fromOffset(20, 0); title.Size = UDim2.new(1, -28, 1, 0)
title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.new(1, 1, 1)
title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = "\xF0\x9F\x94\x84  REBIRTH"; title.ZIndex = 3; title.Parent = header
do local c = Instance.new("UITextSizeConstraint", title); c.MaxTextSize = 33 end
stroke(title, Color3.fromRGB(96, 44, 12), 2)
-- subtle shine sweep across the header every few seconds
header.ClipsDescendants = true
do
	local shn = Instance.new("Frame"); shn.BackgroundColor3 = Color3.new(1,1,1); shn.BackgroundTransparency = 0.62; shn.BorderSizePixel = 0
	shn.Size = UDim2.new(0, 50, 1, 0); shn.Rotation = 10; shn.ZIndex = 4; shn.Parent = header
	local sg = Instance.new("UIGradient", shn); sg.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.5,0),NumberSequenceKeypoint.new(1,1)})
	task.spawn(function()
		while shn.Parent do
			shn.Position = UDim2.new(-0.25, 0, 0, 0)
			TweenService:Create(shn, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Position = UDim2.new(1.25, 0, 0, 0) }):Play()
			task.wait(4)
		end
	end)
end

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0); closeBtn.Position = UDim2.new(1, -12, 0, 13); closeBtn.Size = UDim2.fromOffset(40, 40)
closeBtn.BackgroundColor3 = COL_RED; closeBtn.Font = Enum.Font.FredokaOne; closeBtn.Text = "X"; closeBtn.TextScaled = true
closeBtn.TextColor3 = Color3.new(1, 1, 1); closeBtn.ZIndex = 5; closeBtn.Parent = panel; corner(closeBtn, 11); stroke(closeBtn, Color3.fromRGB(150, 40, 32), 3); juice(closeBtn)
do local p = Instance.new("UIPadding", closeBtn); for _, s in ipairs({"PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"}) do p[s] = UDim.new(0, 9) end end

-- ===== rebirth count + current/next boosts card =====
local statCard = Instance.new("Frame")
statCard.Position = UDim2.fromOffset(16, 78); statCard.Size = UDim2.new(1, -32, 0, 158); statCard.BackgroundColor3 = COL_CARD
statCard.Parent = panel; corner(statCard, 16); stroke(statCard, COL_GOLD, 1.5); juice(statCard)

local countLbl = Instance.new("TextLabel")
countLbl.BackgroundTransparency = 1; countLbl.Position = UDim2.fromOffset(0, 8); countLbl.Size = UDim2.new(1, 0, 0, 30)
countLbl.Font = Enum.Font.FredokaOne; countLbl.TextScaled = true; countLbl.TextColor3 = COL_GOLD
countLbl.TextXAlignment = Enum.TextXAlignment.Center; countLbl.Text = "\xE2\xAD\x90 Rebirths: 0"; countLbl.Parent = statCard
stroke(countLbl, Color3.fromRGB(96, 44, 12), 1.5)
do local c = Instance.new("UITextSizeConstraint", countLbl); c.MaxTextSize = 26 end

-- premium stat badge: rounded, soft bevel, icon + value, identical sizing/spacing
local function mkStatBadge(parent, x, y, w, icon, txt, pulse)
	local f = Instance.new("Frame"); f.Position = UDim2.fromOffset(x, y); f.Size = UDim2.fromOffset(w, 32); f.BackgroundColor3 = COL_BG2
	f.Parent = parent; corner(f, 10); stroke(f, COL_GOLD, 1.2, 0.25); juice(f)
	local ic = Instance.new("TextLabel"); ic.BackgroundTransparency = 1; ic.Position = UDim2.fromOffset(8, 0); ic.Size = UDim2.fromOffset(24, 32)
	ic.Font = Enum.Font.GothamBold; ic.TextScaled = true; ic.Text = icon; ic.Parent = f
	local tx = Instance.new("TextLabel"); tx.BackgroundTransparency = 1; tx.Position = UDim2.fromOffset(34, 0); tx.Size = UDim2.new(1, -40, 1, 0)
	tx.Font = Enum.Font.FredokaOne; tx.TextScaled = true; tx.TextColor3 = COL_TXT; tx.TextXAlignment = Enum.TextXAlignment.Left; tx.Text = txt; tx.Parent = f
	do local c = Instance.new("UITextSizeConstraint", tx); c.MaxTextSize = 14 end
	local _ = pulse -- badges are held still (no idle pulse)
	return tx
end
local BW, BX = 208, { 12, 230, 448 }
local curCoin  = mkStatBadge(statCard, BX[1], 44, BW, "\xF0\x9F\x92\xB0", "Coins x1.00", true)
local curSpeed = mkStatBadge(statCard, BX[2], 44, BW, "\xE2\x9A\xA1", "Speed x1.00", true)
local curLuck  = mkStatBadge(statCard, BX[3], 44, BW, "\xF0\x9F\x8D\x80", "Luck x1.00", true)

local nextHdr = Instance.new("TextLabel")
nextHdr.BackgroundTransparency = 1; nextHdr.Position = UDim2.fromOffset(0, 82); nextHdr.Size = UDim2.new(1, 0, 0, 18)
nextHdr.Font = Enum.Font.GothamBold; nextHdr.TextScaled = true; nextHdr.TextColor3 = COL_GREEN
nextHdr.TextXAlignment = Enum.TextXAlignment.Center; nextHdr.Text = "Next Rebirth Rewards"; nextHdr.Parent = statCard
do local c = Instance.new("UITextSizeConstraint", nextHdr); c.MaxTextSize = 15 end
local nxtCoin  = mkStatBadge(statCard, BX[1], 104, BW, "\xF0\x9F\x92\xB0", "Coins x1.25")
local nxtSpeed = mkStatBadge(statCard, BX[2], 104, BW, "\xE2\x9A\xA1", "Speed x1.03")
local nxtLuck  = mkStatBadge(statCard, BX[3], 104, BW, "\xF0\x9F\x8D\x80", "Luck x1.15")

-- ===== requirements =====
local reqTitle = Instance.new("TextLabel")
reqTitle.BackgroundTransparency = 1; reqTitle.Position = UDim2.fromOffset(20, 244); reqTitle.Size = UDim2.new(1, -40, 0, 22)
reqTitle.Font = Enum.Font.FredokaOne; reqTitle.TextScaled = true; reqTitle.TextColor3 = Color3.new(1, 1, 1)
reqTitle.TextXAlignment = Enum.TextXAlignment.Left; reqTitle.Text = "Requirements"; reqTitle.Parent = panel
do local c = Instance.new("UITextSizeConstraint", reqTitle); c.MaxTextSize = 18 end

local reqRows = {}
local function mkReqRow(order, titleText, descText)
	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(16, 268 + (order - 1) * 44); row.Size = UDim2.new(1, -32, 0, 40)
	row.BackgroundColor3 = COL_CARD; row.Parent = panel; corner(row, 12); stroke(row, COL_EDGE, 1, 0.4); juice(row)
	local badge = Instance.new("TextLabel")
	badge.AnchorPoint = Vector2.new(0, 0.5); badge.Position = UDim2.fromOffset(10, 20); badge.Size = UDim2.fromOffset(32, 32)
	badge.BackgroundColor3 = COL_RED; badge.Font = Enum.Font.FredokaOne; badge.TextScaled = true; badge.TextColor3 = Color3.new(1, 1, 1)
	badge.Text = "\xE2\x9C\x95"; badge.ZIndex = 2; badge.Parent = row; corner(badge, 10); stroke(badge, Color3.fromRGB(150, 40, 32), 1.5)
	do local p = Instance.new("UIPadding", badge); for _, s in ipairs({"PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"}) do p[s] = UDim.new(0, 6) end end
	local ttl = Instance.new("TextLabel")
	ttl.BackgroundTransparency = 1; ttl.Position = UDim2.fromOffset(54, 4); ttl.Size = UDim2.new(1, -66, 0, 18)
	ttl.Font = Enum.Font.FredokaOne; ttl.TextScaled = true; ttl.TextColor3 = Color3.new(1, 1, 1)
	ttl.TextXAlignment = Enum.TextXAlignment.Left; ttl.Text = titleText; ttl.ZIndex = 2; ttl.Parent = row
	do local c = Instance.new("UITextSizeConstraint", ttl); c.MaxTextSize = 17 end
	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1; desc.Position = UDim2.fromOffset(54, 21); desc.Size = UDim2.new(1, -66, 0, 13)
	desc.Font = Enum.Font.Gotham; desc.TextScaled = true; desc.TextColor3 = Color3.fromRGB(206, 188, 170)
	desc.TextXAlignment = Enum.TextXAlignment.Left; desc.Text = descText; desc.ZIndex = 2; desc.Parent = row
	do local c = Instance.new("UITextSizeConstraint", desc); c.MaxTextSize = 13 end
	local sc = Instance.new("UIScale"); sc.Parent = row -- hover lift
	row.MouseEnter:Connect(function() TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.02 }):Play() end)
	row.MouseLeave:Connect(function() TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1 }):Play() end)
	return { badge = badge, ttl = ttl }
end
reqRows.islands = mkReqRow(1, "Complete the Earth Realm", "Reach island 14 (finish the climb)")
reqRows.space   = mkReqRow(2, "Complete the Space Realm", "Reach the final planet")
reqRows.dino    = mkReqRow(3, "Complete the Dino Realm", "Beat the dino realm")
reqRows.candy   = mkReqRow(4, "Complete the Candy Realm", "Beat the candy realm")

-- big REBIRTH button (premium: beveled gradient, soft shadow, hover + press)
local btnShadow = Instance.new("ImageLabel")
btnShadow.AnchorPoint = Vector2.new(0.5, 1); btnShadow.Position = UDim2.new(0.5, 0, 1, -8); btnShadow.Size = UDim2.new(1, -20, 0, 68)
btnShadow.BackgroundTransparency = 1; btnShadow.Image = "rbxassetid://1316045217"; btnShadow.ImageColor3 = Color3.new(0, 0, 0); btnShadow.ImageTransparency = 0.62
btnShadow.ScaleType = Enum.ScaleType.Slice; btnShadow.SliceCenter = Rect.new(10, 10, 118, 118); btnShadow.ZIndex = 2; btnShadow.Parent = panel
local doBtn = Instance.new("TextButton")
doBtn.AnchorPoint = Vector2.new(0.5, 1); doBtn.Position = UDim2.new(0.5, 0, 1, -14); doBtn.Size = UDim2.new(1, -32, 0, 58)
doBtn.Font = Enum.Font.FredokaOne; doBtn.TextScaled = true; doBtn.TextColor3 = Color3.new(1, 1, 1); doBtn.Text = "\xF0\x9F\x94\x92 Complete all requirements to Rebirth"
doBtn.BackgroundColor3 = Color3.fromRGB(76, 50, 74); doBtn.ZIndex = 3; doBtn.Parent = panel; corner(doBtn, 16); stroke(doBtn, Color3.fromRGB(28, 14, 28), 2.5); juice(doBtn)
do local p = Instance.new("UIPadding", doBtn); p.PaddingTop = UDim.new(0, 8); p.PaddingBottom = UDim.new(0, 8); p.PaddingLeft = UDim.new(0, 12); p.PaddingRight = UDim.new(0, 12) end
do local c = Instance.new("UITextSizeConstraint", doBtn); c.MaxTextSize = 24 end
local doBtnScale = Instance.new("UIScale"); doBtnScale.Parent = doBtn
doBtn.MouseEnter:Connect(function() if doBtn.Active then TweenService:Create(doBtnScale, TweenInfo.new(0.1), { Scale = 1.03 }):Play() end end)
doBtn.MouseLeave:Connect(function() TweenService:Create(doBtnScale, TweenInfo.new(0.1), { Scale = 1 }):Play() end)
doBtn.MouseButton1Down:Connect(function() if doBtn.Active then doBtnScale.Scale = 0.96; TweenService:Create(doBtnScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play() end end)

--------------------------------------------------------------------------------
-- confirm overlay (inside the panel)
--------------------------------------------------------------------------------
local confirm = Instance.new("Frame")
confirm.Size = UDim2.fromScale(1, 1); confirm.BackgroundColor3 = Color3.fromRGB(28, 14, 8); confirm.BackgroundTransparency = 0.12
confirm.Visible = false; confirm.ZIndex = 20; confirm.Parent = panel; corner(confirm, 20)
local cText = Instance.new("TextLabel")
cText.AnchorPoint = Vector2.new(0.5, 0); cText.Position = UDim2.fromScale(0.5, 0.22); cText.Size = UDim2.new(0.86, 0, 0, 150)
cText.BackgroundTransparency = 1; cText.Font = Enum.Font.FredokaOne; cText.TextScaled = true; cText.TextColor3 = Color3.new(1, 1, 1)
cText.TextWrapped = true; cText.ZIndex = 21; cText.Text = ""; cText.Parent = confirm
do local c = Instance.new("UITextSizeConstraint", cText); c.MaxTextSize = 24 end
local cYes = Instance.new("TextButton")
cYes.AnchorPoint = Vector2.new(0.5, 1); cYes.Position = UDim2.new(0.31, 0, 0.82, 0); cYes.Size = UDim2.fromOffset(200, 54)
cYes.Font = Enum.Font.FredokaOne; cYes.TextScaled = true; cYes.TextColor3 = Color3.new(1, 1, 1); cYes.Text = "YES, REBIRTH"
cYes.BackgroundColor3 = COL_GREEN; cYes.ZIndex = 21; cYes.Parent = confirm; corner(cYes, 12); stroke(cYes, Color3.fromRGB(28, 84, 44), 3); juice(cYes)
do local p = Instance.new("UIPadding", cYes); p.PaddingTop = UDim.new(0, 8); p.PaddingBottom = UDim.new(0, 8); p.PaddingLeft = UDim.new(0, 10); p.PaddingRight = UDim.new(0, 10) end
local cNo = Instance.new("TextButton")
cNo.AnchorPoint = Vector2.new(0.5, 1); cNo.Position = UDim2.new(0.69, 0, 0.82, 0); cNo.Size = UDim2.fromOffset(200, 54)
cNo.Font = Enum.Font.FredokaOne; cNo.TextScaled = true; cNo.TextColor3 = Color3.new(1, 1, 1); cNo.Text = "Cancel"
cNo.BackgroundColor3 = Color3.fromRGB(110, 78, 60); cNo.ZIndex = 21; cNo.Parent = confirm; corner(cNo, 12); stroke(cNo, Color3.fromRGB(64, 42, 28), 3); juice(cNo)
do local p = Instance.new("UIPadding", cNo); p.PaddingTop = UDim.new(0, 8); p.PaddingBottom = UDim.new(0, 8) end

--------------------------------------------------------------------------------
-- render
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- MILESTONE PETS -- a paw button opens an overlay listing which rebirth count unlocks which pet
--------------------------------------------------------------------------------
local petsBtn = Instance.new("TextButton")
petsBtn.AnchorPoint = Vector2.new(1, 0); petsBtn.Position = UDim2.new(1, -60, 0, 20); petsBtn.Size = UDim2.fromOffset(34, 34)
petsBtn.BackgroundColor3 = COL_PURP; petsBtn.Font = Enum.Font.FredokaOne; petsBtn.Text = "\xF0\x9F\x90\xBE"; petsBtn.TextScaled = true; petsBtn.TextColor3 = Color3.new(1, 1, 1); petsBtn.ZIndex = 6; petsBtn.Parent = panel
corner(petsBtn, 10); stroke(petsBtn, Color3.fromRGB(80, 44, 74), 2); juice(petsBtn)
do local p = Instance.new("UIPadding", petsBtn); for _, s in ipairs({ "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" }) do p[s] = UDim.new(0, 6) end end

local petOverlay = Instance.new("TextButton")
petOverlay.Size = UDim2.fromScale(1, 1); petOverlay.AutoButtonColor = false; petOverlay.Text = ""; petOverlay.BackgroundColor3 = Color3.fromRGB(20, 10, 4); petOverlay.BackgroundTransparency = 0.25; petOverlay.Visible = false; petOverlay.ZIndex = 25; petOverlay.Parent = panel; corner(petOverlay, 26)
local petCard = Instance.new("Frame"); petCard.AnchorPoint = Vector2.new(0.5, 0.5); petCard.Position = UDim2.fromScale(0.5, 0.5); petCard.Size = UDim2.fromOffset(470, 300); petCard.BackgroundColor3 = COL_BG; petCard.Active = true; petCard.ZIndex = 26; petCard.Parent = petOverlay
corner(petCard, 20); stroke(petCard, COL_GOLD, 3); juice(petCard)
do local h = Instance.new("TextLabel"); h.BackgroundTransparency = 1; h.Position = UDim2.fromOffset(20, 14); h.Size = UDim2.new(1, -40, 0, 34); h.Font = Enum.Font.FredokaOne; h.TextScaled = true; h.TextColor3 = COL_GOLD; h.TextXAlignment = Enum.TextXAlignment.Left; h.Text = "\xF0\x9F\x90\xBE Milestone Pets"; h.ZIndex = 27; h.Parent = petCard; local c = Instance.new("UITextSizeConstraint", h); c.MaxTextSize = 26 end
do local s = Instance.new("TextLabel"); s.BackgroundTransparency = 1; s.Position = UDim2.fromOffset(20, 48); s.Size = UDim2.new(1, -40, 0, 18); s.Font = Enum.Font.Gotham; s.TextScaled = true; s.TextColor3 = COL_TXT; s.TextXAlignment = Enum.TextXAlignment.Left; s.Text = "Exclusive pets you earn as you rebirth:"; s.ZIndex = 27; s.Parent = petCard; local c = Instance.new("UITextSizeConstraint", s); c.MaxTextSize = 14 end
local petRows = {}
for i = 1, 3 do
	local row = Instance.new("Frame"); row.Position = UDim2.fromOffset(20, 74 + (i - 1) * 56); row.Size = UDim2.new(1, -40, 0, 48); row.BackgroundColor3 = COL_CARD; row.ZIndex = 27; row.Visible = false; row.Parent = petCard
	corner(row, 12); stroke(row, COL_EDGE, 1, 0.4); juice(row)
	local nm = Instance.new("TextLabel"); nm.BackgroundTransparency = 1; nm.Position = UDim2.fromOffset(14, 0); nm.Size = UDim2.new(1, -150, 1, 0); nm.Font = Enum.Font.FredokaOne; nm.TextScaled = true; nm.TextColor3 = Color3.new(1, 1, 1); nm.TextXAlignment = Enum.TextXAlignment.Left; nm.ZIndex = 28; nm.Parent = row
	do local c = Instance.new("UITextSizeConstraint", nm); c.MaxTextSize = 17 end
	local st = Instance.new("TextLabel"); st.AnchorPoint = Vector2.new(1, 0.5); st.Position = UDim2.new(1, -12, 0.5, 0); st.Size = UDim2.fromOffset(120, 26); st.BackgroundTransparency = 1; st.Font = Enum.Font.FredokaOne; st.TextScaled = true; st.TextXAlignment = Enum.TextXAlignment.Right; st.ZIndex = 28; st.Parent = row
	do local c = Instance.new("UITextSizeConstraint", st); c.MaxTextSize = 15 end
	petRows[i] = { frame = row, name = nm, status = st }
end
do local ok = Instance.new("TextButton"); ok.AnchorPoint = Vector2.new(0.5, 1); ok.Position = UDim2.new(0.5, 0, 1, -14); ok.Size = UDim2.fromOffset(180, 42); ok.Font = Enum.Font.FredokaOne; ok.TextScaled = true; ok.TextColor3 = Color3.new(1, 1, 1); ok.Text = "GOT IT"; ok.BackgroundColor3 = COL_PURP; ok.ZIndex = 27; ok.Parent = petCard; corner(ok, 12); stroke(ok, Color3.fromRGB(80, 44, 74), 2); juice(ok); ok.Activated:Connect(function() petOverlay.Visible = false end) end
petsBtn.Activated:Connect(function() petOverlay.Visible = true end)
petOverlay.MouseButton1Click:Connect(function() petOverlay.Visible = false end)

local function refreshPetMilestones()
	local pm = S.petMilestones or {}
	for i, row in ipairs(petRows) do
		local m = pm[i]
		if m then
			row.name.Text = "\xF0\x9F\x94\x84 Rebirth " .. m.req .. "  \xE2\x86\x92  " .. tostring(m.name)
			row.status.Text = m.owned and "\xE2\x9C\x93 OWNED" or "\xF0\x9F\x94\x92 LOCKED"
			row.status.TextColor3 = m.owned and COL_GREEN or COL_RED
			row.frame.Visible = true
		else
			row.frame.Visible = false
		end
	end
end

local function pct(mult) return ("x%.2f"):format(mult) end
local function redraw()
	countLbl.Text = "\xE2\xAD\x90 Rebirths: " .. S.rebirths
	curCoin.Text = "Coins " .. pct(S.coinMult); curSpeed.Text = "Speed " .. pct(S.speedMult); curLuck.Text = "Luck " .. pct(S.luckMult)
	nxtCoin.Text = "Coins " .. pct(S.nextCoin); nxtSpeed.Text = "Speed " .. pct(S.nextSpeed); nxtLuck.Text = "Luck " .. pct(S.nextLuck)
	local r = S.reqs or {}
	local function setRow(row, ok)
		row.badge.Text = ok and "\xE2\x9C\x93" or "\xE2\x9C\x95"
		row.badge.BackgroundColor3 = ok and COL_GREEN or COL_RED
		local st = row.badge:FindFirstChildOfClass("UIStroke"); if st then st.Color = ok and Color3.fromRGB(46, 120, 60) or Color3.fromRGB(150, 40, 32) end
		row.ttl.TextColor3 = ok and COL_GREEN or Color3.new(1, 1, 1)
	end
	setRow(reqRows.islands, r.islands); setRow(reqRows.space, r.space); setRow(reqRows.dino, r.dino); setRow(reqRows.candy, r.candy)
	if S.canRebirth then
		doBtn.Text = "\xE2\xAD\x90 REBIRTH NOW"; doBtn.BackgroundColor3 = COL_PURP; doBtn.Active = true; doBtn.AutoButtonColor = true
	else
		doBtn.Text = "\xF0\x9F\x94\x92 Complete all requirements to Rebirth"; doBtn.BackgroundColor3 = Color3.fromRGB(76, 50, 74); doBtn.Active = false; doBtn.AutoButtonColor = false
	end
	refreshPetMilestones()
end

--------------------------------------------------------------------------------
-- open/close (MainMenuManager -> hides bottom HUD + closes other menus)
--------------------------------------------------------------------------------
local MENU_NAME = "Rebirth"
local function setOpen(o)
	dim.Visible = o; shadow.Visible = false; confirm.Visible = false -- no drop shadow behind the panel
	if o then
		if _G.MainMenuManager then _G.MainMenuManager.notifyOpened(MENU_NAME) end
		panel.Visible = true
		panel.Size = UDim2.fromOffset(660, 490)
		TweenService:Create(panel, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(700, 520) }):Play()
		redraw()
		pcall(function() remote:FireServer("state") end) -- ask for fresh state on open
	else
		panel.Visible = false
		if _G.MainMenuManager then _G.MainMenuManager.notifyClosed(MENU_NAME) end
	end
end
_G.toggleRebirth = function() setOpen(not panel.Visible) end
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
-- NOTE: there is deliberately NO click-outside-to-close handler (matching the Pet Hub). The backdrop spans
-- the whole screen, so a click anywhere off the panel used to slam it shut, which made menus feel like they
-- closed at random. This panel now closes ONLY on an explicit action: its X button, its own toggle, or
-- MainMenuManager closing it because another menu opened.

doBtn.Activated:Connect(function()
	if not S.canRebirth then return end
	cText.Text = "Reset your whole run for a permanent " .. pct(S.nextCoin) .. " coins boost?\n\nYou keep your pets, gamepasses and rebirths."
	confirm.Visible = true
end)
cNo.Activated:Connect(function() confirm.Visible = false end)
cYes.Activated:Connect(function() confirm.Visible = false; pcall(function() remote:FireServer("rebirth") end) end)

task.spawn(function()
	for _ = 1, 100 do
		if _G.MainMenuManager then _G.MainMenuManager.register(MENU_NAME, function() panel.Visible = false; dim.Visible = false; shadow.Visible = false end); return end
		task.wait(0.1)
	end
end)

--------------------------------------------------------------------------------
-- REBIRTH CELEBRATION -- a staged cinematic: BLAST -> trophy-card reveal -> party
--------------------------------------------------------------------------------
local Debris = game:GetService("Debris")
local CARD_Y = 0.43

local fx = Instance.new("ScreenGui")
fx.Name = "RebirthFX"; fx.ResetOnSpawn = false; fx.DisplayOrder = 200; fx.IgnoreGuiInset = true; fx.Enabled = false; fx.Parent = gui

local fxFlash = Instance.new("Frame")
fxFlash.Size = UDim2.fromScale(1, 1); fxFlash.BackgroundColor3 = Color3.fromRGB(255, 245, 220); fxFlash.BackgroundTransparency = 1; fxFlash.BorderSizePixel = 0; fxFlash.ZIndex = 1; fxFlash.Parent = fx

-- everything but the flash lives in fxRoot so the whole scene can SHAKE as one
local fxRoot = Instance.new("Frame")
fxRoot.Size = UDim2.fromScale(1, 1); fxRoot.AnchorPoint = Vector2.new(0.5, 0.5); fxRoot.Position = UDim2.fromScale(0.5, 0.5); fxRoot.BackgroundTransparency = 1; fxRoot.Parent = fx

local function bigImg(img, col, z)
	local o = Instance.new("ImageLabel"); o.AnchorPoint = Vector2.new(0.5, 0.5); o.Position = UDim2.fromScale(0.5, CARD_Y); o.Size = UDim2.fromOffset(200, 200)
	o.BackgroundTransparency = 1; o.Image = img; o.ImageColor3 = col; o.ImageTransparency = 1
	o.ScaleType = Enum.ScaleType.Slice; o.SliceCenter = Rect.new(10, 10, 118, 118); o.ZIndex = z; o.Parent = fxRoot; return o
end
local fxRays   = bigImg("rbxassetid://1316045217", Color3.fromRGB(255, 208, 120), 2)
local fxGlow   = bigImg("rbxassetid://1316045217", COL_GOLD, 3)
local fxShadow = bigImg("rbxassetid://1316045217", Color3.new(0, 0, 0), 4); fxShadow.Size = UDim2.fromOffset(600, 300)

-- THE TROPHY CARD
local fxCard = Instance.new("Frame")
fxCard.AnchorPoint = Vector2.new(0.5, 0.5); fxCard.Position = UDim2.fromScale(0.5, CARD_Y); fxCard.Size = UDim2.fromOffset(540, 250)
fxCard.BackgroundColor3 = COL_BG; fxCard.ClipsDescendants = true; fxCard.ZIndex = 5; fxCard.Parent = fxRoot
corner(fxCard, 26); stroke(fxCard, COL_GOLD, 4); juice(fxCard)
local fxCardScale = Instance.new("UIScale"); fxCardScale.Scale = 0; fxCardScale.Parent = fxCard
do local sh = Instance.new("Frame"); sh.Size = UDim2.new(1, -26, 0, 12); sh.Position = UDim2.new(0, 13, 0, 8); sh.BackgroundColor3 = Color3.new(1, 1, 1); sh.BackgroundTransparency = 0.8; sh.BorderSizePixel = 0; sh.ZIndex = 6; sh.Parent = fxCard; corner(sh, 6); local g = Instance.new("UIGradient", sh); g.Rotation = 90; g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }) end

local fxIcon = Instance.new("TextLabel")
fxIcon.AnchorPoint = Vector2.new(0.5, 0); fxIcon.Position = UDim2.new(0.5, 0, 0, 14); fxIcon.Size = UDim2.fromOffset(66, 66)
fxIcon.BackgroundTransparency = 1; fxIcon.Font = Enum.Font.GothamBold; fxIcon.TextScaled = true; fxIcon.Text = "\xF0\x9F\x94\x84"; fxIcon.ZIndex = 7; fxIcon.Parent = fxCard

local fxTitle = Instance.new("TextLabel")
fxTitle.AnchorPoint = Vector2.new(0.5, 0); fxTitle.Position = UDim2.new(0.5, 0, 0, 82); fxTitle.Size = UDim2.new(1, -30, 0, 52)
fxTitle.BackgroundTransparency = 1; fxTitle.Font = Enum.Font.FredokaOne; fxTitle.TextScaled = true; fxTitle.TextColor3 = COL_GOLD
fxTitle.Text = "REBIRTH!"; fxTitle.ZIndex = 7; fxTitle.Parent = fxCard
stroke(fxTitle, Color3.fromRGB(70, 32, 6), 3)
do local c = Instance.new("UITextSizeConstraint", fxTitle); c.MaxTextSize = 46 end

local fxSub = Instance.new("TextLabel")
fxSub.AnchorPoint = Vector2.new(0.5, 0); fxSub.Position = UDim2.new(0.5, 0, 0, 136); fxSub.Size = UDim2.new(1, -30, 0, 22)
fxSub.BackgroundTransparency = 1; fxSub.Font = Enum.Font.GothamBold; fxSub.TextScaled = true; fxSub.TextColor3 = COL_TXT
fxSub.Text = "Everything's stronger now!"; fxSub.ZIndex = 7; fxSub.Parent = fxCard
do local c = Instance.new("UITextSizeConstraint", fxSub); c.MaxTextSize = 18 end

-- three stat chips (Coins / Speed / Luck) that pop in one by one
local chipRow = Instance.new("Frame")
chipRow.AnchorPoint = Vector2.new(0.5, 1); chipRow.Position = UDim2.new(0.5, 0, 1, -16); chipRow.Size = UDim2.new(1, -26, 0, 40)
chipRow.BackgroundTransparency = 1; chipRow.ZIndex = 7; chipRow.Parent = fxCard
do local l = Instance.new("UIListLayout", chipRow); l.FillDirection = Enum.FillDirection.Horizontal; l.HorizontalAlignment = Enum.HorizontalAlignment.Center; l.VerticalAlignment = Enum.VerticalAlignment.Center; l.Padding = UDim.new(0, 10) end
local function mkChip(order, icon, col)
	local chip = Instance.new("Frame"); chip.Size = UDim2.fromOffset(150, 38); chip.BackgroundColor3 = col; chip.LayoutOrder = order; chip.ZIndex = 7; chip.Parent = chipRow
	corner(chip, 12); stroke(chip, Color3.fromRGB(0, 0, 0), 1.5, 0.35); juice(chip)
	local ic = Instance.new("TextLabel"); ic.BackgroundTransparency = 1; ic.Position = UDim2.fromOffset(8, 0); ic.Size = UDim2.fromOffset(26, 38); ic.Font = Enum.Font.GothamBold; ic.TextScaled = true; ic.Text = icon; ic.ZIndex = 8; ic.Parent = chip
	local tx = Instance.new("TextLabel"); tx.BackgroundTransparency = 1; tx.Position = UDim2.fromOffset(34, 0); tx.Size = UDim2.new(1, -40, 1, 0); tx.Font = Enum.Font.FredokaOne; tx.TextScaled = true; tx.TextColor3 = Color3.new(1, 1, 1); tx.TextXAlignment = Enum.TextXAlignment.Left; tx.Text = "x1.00"; tx.ZIndex = 8; tx.Parent = chip
	stroke(tx, Color3.fromRGB(0, 0, 0), 1.5); do local c = Instance.new("UITextSizeConstraint", tx); c.MaxTextSize = 17 end
	local sc = Instance.new("UIScale"); sc.Scale = 0; sc.Parent = chip
	return { val = tx, sc = sc }
end
local chipCoins = mkChip(1, "\xF0\x9F\x92\xB0", COL_GOLD)
local chipSpeed = mkChip(2, "\xE2\x9A\xA1", Color3.fromRGB(90, 150, 240))
local chipLuck  = mkChip(3, "\xF0\x9F\x8D\x80", COL_GREEN)

local CONFETTI     = { "\xE2\x9C\xA6", "\xF0\x9F\x92\xB0", "\xE2\xAD\x90", "\xF0\x9F\x8E\x89" }
local CONFETTI_COL = { Color3.fromRGB(255,214,90), Color3.fromRGB(255,120,220), Color3.fromRGB(120,200,255), Color3.fromRGB(140,255,150), Color3.fromRGB(255,255,255) }

local function playSound(id, vol, speed)
	local s = Instance.new("Sound"); s.SoundId = "rbxassetid://" .. id; s.Volume = vol or 1; s.PlaybackSpeed = speed or 1; s.Parent = fx
	pcall(function() s:Play() end); Debris:AddItem(s, 5)
end

local function countUp(label, target, dur)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < dur do
			local a = (os.clock() - t0) / dur
			label.Text = ("x%.2f"):format(1 + (target - 1) * a); task.wait()
		end
		label.Text = ("x%.2f"):format(target)
	end)
end

local function playRebirthAnim(n)
	n = (n and n > 0) and n or 1
	fx.Enabled = true

	-- ===== reset state (so /rebirth can replay it cleanly) =====
	fxTitle.Text = "REBIRTH #" .. n .. "!"; fxTitle.TextColor3 = COL_GOLD
	chipCoins.val.Text = "x1.00"; chipSpeed.val.Text = "x1.00"; chipLuck.val.Text = "x1.00"
	local chipTargets = { 1 + 0.25 * n, 1 + 0.03 * n, 1 + 0.15 * n }
	fxCardScale.Scale = 0.2; fxCard.Rotation = -6; fxShadow.ImageTransparency = 1
	chipCoins.sc.Scale = 0; chipSpeed.sc.Scale = 0; chipLuck.sc.Scale = 0

	-- ===== SOUND =====
	playSound(4612378086, 1, 1.0); task.delay(0.08, function() playSound(4612378086, 0.7, 1.5) end)

	-- ===== SCREEN SHAKE =====
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.55 and fx.Enabled do
			local k = (1 - (os.clock() - t0) / 0.55) * 14
			fxRoot.Position = UDim2.new(0.5, (math.random() - 0.5) * k, 0.5, (math.random() - 0.5) * k)
			task.wait()
		end
		fxRoot.Position = UDim2.fromScale(0.5, 0.5)
	end)

	-- ===== FOV PUNCH + STROBE FLASH =====
	do local cam = workspace.CurrentCamera; if cam then local base = cam.FieldOfView; cam.FieldOfView = base + 18; TweenService:Create(cam, TweenInfo.new(0.65, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { FieldOfView = base }):Play() end end
	task.spawn(function()
		for _, c in ipairs({ Color3.fromRGB(255, 255, 255), COL_GOLD, Color3.fromRGB(200, 150, 255) }) do
			fxFlash.BackgroundColor3 = c; fxFlash.BackgroundTransparency = 0.1
			TweenService:Create(fxFlash, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play(); task.wait(0.15)
		end
	end)

	-- ===== SUNBURST BEAMS =====
	for b = 1, 16 do
		local beam = Instance.new("Frame")
		beam.AnchorPoint = Vector2.new(0.5, 1); beam.Position = UDim2.fromScale(0.5, CARD_Y); beam.Size = UDim2.fromOffset(14, 0)
		beam.BackgroundColor3 = (b % 2 == 0) and COL_GOLD or Color3.fromRGB(255, 236, 176); beam.BorderSizePixel = 0
		beam.Rotation = (b / 16) * 360; beam.ZIndex = 2; beam.Parent = fxRoot
		local bgr = Instance.new("UIGradient", beam); bgr.Rotation = 90; bgr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
		TweenService:Create(beam, TweenInfo.new(0.75, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(14, 720), BackgroundTransparency = 1 }):Play()
		Debris:AddItem(beam, 1.0)
	end

	-- ===== SPINNING RAYS + GLOW BURST =====
	fxRays.ImageTransparency = 0.4; fxRays.Rotation = 0; fxRays.Size = UDim2.fromOffset(520, 520)
	TweenService:Create(fxRays, TweenInfo.new(2.6, Enum.EasingStyle.Linear), { Rotation = 240 }):Play()
	TweenService:Create(fxRays, TweenInfo.new(2.6, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(1150, 1150), ImageTransparency = 1 }):Play()
	fxGlow.Size = UDim2.fromOffset(160, 160); fxGlow.ImageTransparency = 0.05
	TweenService:Create(fxGlow, TweenInfo.new(0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(900, 900), ImageTransparency = 1 }):Play()

	-- ===== SHOCKWAVE RINGS =====
	for r = 1, 3 do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5); ring.Position = UDim2.fromScale(0.5, CARD_Y); ring.Size = UDim2.fromOffset(70, 70)
		ring.BackgroundTransparency = 1; ring.ZIndex = 2; ring.Parent = fxRoot
		local rcorn = Instance.new("UICorner", ring); rcorn.CornerRadius = UDim.new(1, 0)
		local rstk = Instance.new("UIStroke", ring); rstk.Color = (r % 2 == 0) and COL_GOLD or Color3.fromRGB(190, 130, 255); rstk.Thickness = 12
		task.delay((r - 1) * 0.13, function()
			TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(1000, 1000) }):Play()
			TweenService:Create(rstk, TweenInfo.new(0.7), { Transparency = 1, Thickness = 1 }):Play()
			task.delay(0.75, function() ring:Destroy() end)
		end)
	end

	-- ===== TROPHY CARD SLAMS IN + shadow + icon spin =====
	TweenService:Create(fxShadow, TweenInfo.new(0.5), { ImageTransparency = 0.55 }):Play()
	TweenService:Create(fxCardScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(fxCard, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	fxIcon.Rotation = 0; TweenService:Create(fxIcon, TweenInfo.new(0.85, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 360 }):Play()
	task.delay(0.5, function() TweenService:Create(fxCardScale, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 2, true), { Scale = 1.04 }):Play() end)

	-- ===== stat chips pop in one by one =====
	for idx, ch in ipairs({ chipCoins, chipSpeed, chipLuck }) do
		task.delay(0.62 + (idx - 1) * 0.13, function()
			TweenService:Create(ch.sc, TweenInfo.new(0.36, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			countUp(ch.val, chipTargets[idx], 0.55) -- roll the number up from x1.00 to the real boost
		end)
	end

	-- ===== CONFETTI EXPLOSION =====
	for i = 1, 50 do
		local sp = Instance.new("TextLabel")
		sp.AnchorPoint = Vector2.new(0.5, 0.5); sp.Position = UDim2.fromScale(0.5, CARD_Y); sp.Size = UDim2.fromOffset(30, 30)
		sp.BackgroundTransparency = 1; sp.Font = Enum.Font.GothamBold; sp.Text = CONFETTI[(i % #CONFETTI) + 1]
		sp.TextColor3 = CONFETTI_COL[(i % #CONFETTI_COL) + 1]; sp.TextScaled = true; sp.ZIndex = 4; sp.Parent = fx
		local ang = math.random() * math.pi * 2; local dist = 200 + math.random() * 280
		TweenService:Create(sp, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, math.cos(ang) * dist, CARD_Y, math.sin(ang) * dist * 0.7 - 40) }):Play()
		task.delay(0.52, function()
			TweenService:Create(sp, TweenInfo.new(0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = sp.Position + UDim2.fromOffset((math.random() - 0.5) * 80, 340), TextTransparency = 1, Rotation = (math.random() - 0.5) * 460 }):Play()
		end)
		Debris:AddItem(sp, 1.8)
	end

	-- ===== FIREWORKS during the hold =====
	task.spawn(function()
		for _ = 1, 6 do
			task.wait(0.3); if not fx.Enabled then return end
			local px, py = 0.18 + math.random() * 0.64, 0.2 + math.random() * 0.52
			for _ = 1, 10 do
				local sp = Instance.new("TextLabel")
				sp.AnchorPoint = Vector2.new(0.5, 0.5); sp.Position = UDim2.fromScale(px, py); sp.Size = UDim2.fromOffset(22, 22)
				sp.BackgroundTransparency = 1; sp.Font = Enum.Font.GothamBold; sp.Text = "\xE2\x9C\xA6"
				sp.TextColor3 = CONFETTI_COL[math.random(#CONFETTI_COL)]; sp.TextScaled = true; sp.ZIndex = 4; sp.Parent = fx
				local a = math.random() * math.pi * 2; local d = 70 + math.random() * 100
				TweenService:Create(sp, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(px, math.cos(a) * d, py, math.sin(a) * d), TextTransparency = 1 }):Play()
				Debris:AddItem(sp, 0.9)
			end
		end
	end)

	-- ===== OUTRO: card shrinks + shadow fade =====
	task.delay(2.7, function()
		TweenService:Create(fxCardScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		TweenService:Create(fxShadow, TweenInfo.new(0.4), { ImageTransparency = 1 }):Play()
		task.delay(0.45, function() fx.Enabled = false end)
	end)
end

remote.OnClientEvent:Connect(function(kind, a, b)
	if kind == "state" and type(a) == "table" then
		S = a; S.reqs = S.reqs or {}
		if panel.Visible then redraw() end
	elseif kind == "result" then
		local ok, msg = a, b
		if ok then
			local n = 0
			local ls = player:FindFirstChild("leaderstats"); local rb = ls and ls:FindFirstChild("Rebirths")
			if rb then n = rb.Value end
			setOpen(false)      -- the run just reset -> close the panel
			playRebirthAnim(n)  -- ...and celebrate on screen with the burst + banner
		elseif _G.showHudBanner and msg then
			_G.showHudBanner(msg, COL_RED, 3) -- failure note only
		end
	elseif kind == "announce" then
		-- server-wide "X rebirthed!" banner. The rebirther gets the full-screen celebration instead, and we
		-- DEFER to any big-event / storm banner (don't stack the rebirth banner over it).
		local name, n = tostring(a), tonumber(b) or 0
		if name == player.Name then return end
		if _G.serverEventActive or _G.thunderstormActive or _G.windstormActive then return end
		local NC = _G.NotifyCenter
		if NC then
			NC.push({ top = "\xF0\x9F\x94\x84 REBIRTH", text = name .. " just rebirthed!" .. (n > 0 and ("  #" .. n) or ""), color = Color3.fromRGB(170, 90, 240), priority = NC.PRIORITY.PURCHASE, duration = 3.5 })
		elseif _G.showHudBanner then
			_G.showHudBanner(name .. " just rebirthed!", Color3.fromRGB(170, 90, 240), 3)
		end
	end
end)

-- /rebirth (or /rb): client-side TEST command -> plays the rebirth celebration WITHOUT actually rebirthing.
do
	local TextChatService = game:GetService("TextChatService")
	task.spawn(function()
		local cmds = TextChatService:FindFirstChild("TextChatCommands") or TextChatService:WaitForChild("TextChatCommands", 15)
		if not cmds then return end
		local old = cmds:FindFirstChild("RebirthTestCmd"); if old then old:Destroy() end
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "RebirthTestCmd"; cmd.PrimaryAlias = "/rebirth"; cmd.SecondaryAlias = "/rb"; cmd.Parent = cmds
		cmd.Triggered:Connect(function()
			local n = math.random(1, 12)
			pcall(function() player:SetAttribute("Rebirths", n) end) -- local-only: makes the overhead tag show on YOUR head too
			playRebirthAnim(n)
		end)
	end)
	_G.testRebirthAnim = function(n) -- command-bar fallback
		n = tonumber(n) or math.random(1, 12)
		pcall(function() player:SetAttribute("Rebirths", n) end)
		playRebirthAnim(n)
	end
end

print("[Rebirth] client ready -- panel opens from the REBIRTH side button (_G.toggleRebirth)")
