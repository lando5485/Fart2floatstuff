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

-- Space Realm palette + procedural starfield helper, so the panel matches the rest of the HUD.
local SpaceTheme = require(script.Parent:WaitForChild("SpaceTheme"))

local screen = Instance.new("ScreenGui")
screen.Name = "RebirthGui"; screen.ResetOnSpawn = false; screen.DisplayOrder = 58; screen.Parent = gui

local S = { rebirths = 0, coinMult = 1, speedMult = 1, luckMult = 1, nextCoin = 1.25, nextSpeed = 1.03, nextLuck = 1.15,
	reqs = { islands = false, space = false, dino = false }, reqIsland = 14, canRebirth = false }

--------------------------------------------------------------------------------
-- style helpers
--------------------------------------------------------------------------------
local function corner(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = i; return c end
local function stroke(i, col, t, tr) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 2; s.Transparency = tr or 0; s.Parent = i; return s end
local function grad(i, a, b, rot) local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(a, b); g.Rotation = rot or 90; g.Parent = i; return g end
-- viral pet-sim "juicy" bevel: a top-bright -> bottom-dark gradient that MULTIPLIES the element's colour, so it
-- reads as a rounded 3D button in ANY state colour. Pair with a thick outline for the chunky look.
local function juice(i) local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(168,168,168)); g.Rotation = 90; g.Parent = i; return g end

-- SPACE theme (deep navy panels + neon-blue accents + gold), matching the Space Realm HUD (SpaceTheme.luau).
-- Names kept from the old palette so every downstream reference re-skins with no structural change.
local COL_BG     = Color3.fromRGB(18, 24, 52)    -- deep space-navy panel (SpaceTheme.Panel)
local COL_BG2    = Color3.fromRGB(30, 42, 86)    -- lighter navy for the panel gradient top
local COL_CARD   = Color3.fromRGB(12, 16, 40)    -- dark navy cards (starfield base)
local COL_PURP   = Color3.fromRGB(70, 130, 240)  -- neon-blue header / primary accent (was burnt orange)
local COL_PURP_D = Color3.fromRGB(40, 92, 214)   -- deeper neon blue
local COL_GOLD   = Color3.fromRGB(255, 214, 92)  -- coin gold (SpaceTheme.CoinGold)
local COL_GREEN  = Color3.fromRGB(96, 220, 130)  -- cool green, only for "go"/complete
local COL_RED    = Color3.fromRGB(230, 96, 82)
local COL_TXT    = Color3.fromRGB(230, 238, 255) -- near-white blue text (SpaceTheme.TextPrimary)
local COL_EDGE   = Color3.fromRGB(64, 110, 220)  -- glowing blue edge (SpaceTheme.PanelStroke)

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
corner(panel, 26); grad(panel, COL_BG2, COL_BG, 90); stroke(panel, Color3.fromRGB(6, 10, 26), 4) -- rounder + thick near-black-navy outline
SpaceTheme.addStarfield(panel, 46, 7024) -- scattered stars behind the content, like the other Space Realm panels

local header = Instance.new("Frame")
header.Position = UDim2.fromOffset(16, 14); header.Size = UDim2.new(1, -64, 0, 58); header.BackgroundColor3 = COL_PURP_D
header.Parent = panel; corner(header, 14); grad(header, Color3.fromRGB(120, 190, 255), COL_PURP_D, 20); stroke(header, Color3.fromRGB(190, 225, 255), 1.5, 0.3)
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1; title.Position = UDim2.fromOffset(20, 0); title.Size = UDim2.new(1, -28, 1, 0)
title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.new(1, 1, 1)
title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = "\xF0\x9F\x94\x84  REBIRTH"; title.ZIndex = 3; title.Parent = header
do local c = Instance.new("UITextSizeConstraint", title); c.MaxTextSize = 33 end
stroke(title, Color3.fromRGB(6, 10, 26), 2)
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
SpaceTheme.addStarfield(statCard, 20, 4242) -- faint stars inside the stats card too

local countLbl = Instance.new("TextLabel")
countLbl.BackgroundTransparency = 1; countLbl.Position = UDim2.fromOffset(0, 8); countLbl.Size = UDim2.new(1, 0, 0, 30)
countLbl.Font = Enum.Font.FredokaOne; countLbl.TextScaled = true; countLbl.TextColor3 = COL_GOLD
countLbl.TextXAlignment = Enum.TextXAlignment.Center; countLbl.Text = "\xE2\xAD\x90 Rebirths: 0"; countLbl.Parent = statCard
stroke(countLbl, Color3.fromRGB(6, 10, 26), 1.5)
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
local curCoin  = mkStatBadge(statCard, BX[1], 44, BW, "\xF0\x9F\xAA\x99", "Coins x1.00", true)
local curSpeed = mkStatBadge(statCard, BX[2], 44, BW, "\xE2\x9A\xA1", "Speed x1.00", true)
local curLuck  = mkStatBadge(statCard, BX[3], 44, BW, "\xF0\x9F\x8D\x80", "Luck x1.00", true)

local nextHdr = Instance.new("TextLabel")
nextHdr.BackgroundTransparency = 1; nextHdr.Position = UDim2.fromOffset(0, 82); nextHdr.Size = UDim2.new(1, 0, 0, 18)
nextHdr.Font = Enum.Font.GothamBold; nextHdr.TextScaled = true; nextHdr.TextColor3 = COL_GREEN
nextHdr.TextXAlignment = Enum.TextXAlignment.Center; nextHdr.Text = "Next Rebirth Rewards"; nextHdr.Parent = statCard
do local c = Instance.new("UITextSizeConstraint", nextHdr); c.MaxTextSize = 15 end
local nxtCoin  = mkStatBadge(statCard, BX[1], 104, BW, "\xF0\x9F\xAA\x99", "Coins x1.25")
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
	row.Position = UDim2.fromOffset(16, 272 + (order - 1) * 56); row.Size = UDim2.new(1, -32, 0, 50)
	row.BackgroundColor3 = COL_CARD; row.Parent = panel; corner(row, 12); stroke(row, COL_EDGE, 1, 0.4); juice(row)
	local badge = Instance.new("TextLabel")
	badge.AnchorPoint = Vector2.new(0, 0.5); badge.Position = UDim2.fromOffset(10, 25); badge.Size = UDim2.fromOffset(34, 34)
	badge.BackgroundColor3 = COL_RED; badge.Font = Enum.Font.FredokaOne; badge.TextScaled = true; badge.TextColor3 = Color3.new(1, 1, 1)
	badge.Text = "\xE2\x9C\x95"; badge.ZIndex = 2; badge.Parent = row; corner(badge, 10); stroke(badge, Color3.fromRGB(150, 40, 32), 1.5)
	do local p = Instance.new("UIPadding", badge); for _, s in ipairs({"PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"}) do p[s] = UDim.new(0, 6) end end
	local ttl = Instance.new("TextLabel")
	ttl.BackgroundTransparency = 1; ttl.Position = UDim2.fromOffset(56, 6); ttl.Size = UDim2.new(1, -68, 0, 22)
	ttl.Font = Enum.Font.FredokaOne; ttl.TextScaled = true; ttl.TextColor3 = Color3.new(1, 1, 1)
	ttl.TextXAlignment = Enum.TextXAlignment.Left; ttl.Text = titleText; ttl.ZIndex = 2; ttl.Parent = row
	do local c = Instance.new("UITextSizeConstraint", ttl); c.MaxTextSize = 17 end
	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1; desc.Position = UDim2.fromOffset(56, 27); desc.Size = UDim2.new(1, -68, 0, 16)
	desc.Font = Enum.Font.Gotham; desc.TextScaled = true; desc.TextColor3 = Color3.fromRGB(150, 168, 210)
	desc.TextXAlignment = Enum.TextXAlignment.Left; desc.Text = descText; desc.ZIndex = 2; desc.Parent = row
	do local c = Instance.new("UITextSizeConstraint", desc); c.MaxTextSize = 13 end
	local sc = Instance.new("UIScale"); sc.Parent = row -- hover lift
	row.MouseEnter:Connect(function() TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.02 }):Play() end)
	row.MouseLeave:Connect(function() TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1 }):Play() end)
	return { badge = badge, ttl = ttl }
end
reqRows.islands = mkReqRow(1, "Reach Island 14", "Finish the climb")
reqRows.space   = mkReqRow(2, "Complete the Space Realm", "Reach the final planet")
reqRows.dino    = mkReqRow(3, "Complete the Dino Realm", "Beat the dino realm")

-- big REBIRTH button (premium: beveled gradient, soft shadow, hover + press)
local btnShadow = Instance.new("ImageLabel")
btnShadow.AnchorPoint = Vector2.new(0.5, 1); btnShadow.Position = UDim2.new(0.5, 0, 1, -8); btnShadow.Size = UDim2.new(1, -20, 0, 68)
btnShadow.BackgroundTransparency = 1; btnShadow.Image = "rbxassetid://1316045217"; btnShadow.ImageColor3 = Color3.new(0, 0, 0); btnShadow.ImageTransparency = 0.62
btnShadow.ScaleType = Enum.ScaleType.Slice; btnShadow.SliceCenter = Rect.new(10, 10, 118, 118); btnShadow.ZIndex = 2; btnShadow.Parent = panel
local doBtn = Instance.new("TextButton")
doBtn.AnchorPoint = Vector2.new(0.5, 1); doBtn.Position = UDim2.new(0.5, 0, 1, -14); doBtn.Size = UDim2.new(1, -32, 0, 58)
doBtn.Font = Enum.Font.FredokaOne; doBtn.TextScaled = true; doBtn.TextColor3 = Color3.new(1, 1, 1); doBtn.Text = "\xF0\x9F\x94\x92 Complete all requirements to Rebirth"
doBtn.BackgroundColor3 = Color3.fromRGB(40, 52, 90); doBtn.ZIndex = 3; doBtn.Parent = panel; corner(doBtn, 16); stroke(doBtn, Color3.fromRGB(10, 16, 36), 2.5); juice(doBtn)
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
confirm.Size = UDim2.fromScale(1, 1); confirm.BackgroundColor3 = Color3.fromRGB(8, 12, 30); confirm.BackgroundTransparency = 0.12
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
cNo.BackgroundColor3 = Color3.fromRGB(48, 60, 100); cNo.ZIndex = 21; cNo.Parent = confirm; corner(cNo, 12); stroke(cNo, Color3.fromRGB(16, 22, 44), 3); juice(cNo)
do local p = Instance.new("UIPadding", cNo); p.PaddingTop = UDim.new(0, 8); p.PaddingBottom = UDim.new(0, 8) end

--------------------------------------------------------------------------------
-- render
--------------------------------------------------------------------------------
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
	setRow(reqRows.islands, r.islands); setRow(reqRows.space, r.space); setRow(reqRows.dino, r.dino)
	if S.canRebirth then
		doBtn.Text = "\xE2\xAD\x90 REBIRTH NOW"; doBtn.BackgroundColor3 = COL_PURP; doBtn.Active = true; doBtn.AutoButtonColor = true
	else
		doBtn.Text = "\xF0\x9F\x94\x92 Complete all requirements to Rebirth"; doBtn.BackgroundColor3 = Color3.fromRGB(40, 52, 90); doBtn.Active = false; doBtn.AutoButtonColor = false
	end
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
dim.MouseButton1Click:Connect(function() setOpen(false) end)

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

remote.OnClientEvent:Connect(function(kind, a, b)
	if kind == "state" and type(a) == "table" then
		S = a; S.reqs = S.reqs or {}
		if panel.Visible then redraw() end
	elseif kind == "result" then
		local ok, msg = a, b
		if _G.showHudBanner and msg then _G.showHudBanner(msg, ok and COL_GOLD or COL_RED, 3) end
		if ok then setOpen(false) end -- the run just reset -> close the panel
	end
end)

print("[Rebirth] client ready -- panel opens from the REBIRTH side button (_G.toggleRebirth)")
