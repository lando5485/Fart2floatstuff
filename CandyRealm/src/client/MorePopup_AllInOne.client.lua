--======================================================================
-- MorePopup_AllInOne.client.lua  (LocalScript)  -- CandyRealm
--======================================================================
-- The CURRENT MORE+ menu, copied EXACTLY from the main game (CoreClient.client.lua,
-- "MORE+ POPUP MENU" region). This REPLACES the old 210px pop-out this file used
-- to build with the full-screen DASHBOARD design:
--
--   * 700x520 pink panel at (0.5,0,0.5,-45) -- the exact geometry the Shop,
--     Pet Hub and every other main menu opens to, so it lands in the same box.
--   * 72px darker-pink header band: gold "MORE" title, subtitle, red X.
--   * A 2-column grid of 327x100 feature CARDS (icon square, title, desc,
--     chevron), each with the gloss sheen, the hover shine sweep and the
--     UIScale hover lift -- all verbatim from the main game.
--   * THREE cards only: Rebirth / Fast Travel (the Wormhole) / Rewards.
--   * "!" ready dots (crate + tasks, independent) both sit on the Rewards
--     card, polled from _G.crateIsClaimable() / _G.dailyTasksPending() every 1s.
--
-- WIRING: JustButtons_AllInOne's MORE rail button calls _G.toggleMorePopup()
-- (or fires the OpenMorePopup BindableEvent in PlayerGui as a fallback); both
-- are defined here. The MORE rail button's own "!" dot + wiggle live in
-- JustButtons already, so this file only owns the dots on the cards.
--
-- ENTRIES are only things with a REAL hook in CandyRealm, and NOT already on
-- the left rail (SHOP/PETS/Stomach/MORE). The card code is the main
-- game's verbatim; MORE_ENTRIES is its data-driven part, pointed at this
-- realm's menus. Each row is GUARDED: if its hook isn't present when
-- clicked, it no-ops cleanly (with a print).
--
-- PROJECT RULE: menus never close on a backdrop tap -- X button only. The
-- full-screen catcher still swallows stray taps so they can't hit HUD buttons
-- behind the panel, but tapping it does NOT close the menu. (Same net
-- behavior as the main game, where MenuBackdropGuard neuters the close.)
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local RSx       = ReplicatedStorage

-- ===== helpers (verbatim from CoreClient) =====
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end
local function playUIClick() if _G.playUIClick then pcall(_G.playUIClick) end end

local setMoreOpen          -- forward: the popup toggler (assigned after the panel is built)
local moreOpenState = false

-- --- the MORE+ popup itself (verbatim from CoreClient) ---
local moreGui = Instance.new("ScreenGui"); moreGui.Name = "MoreMenuGui"; moreGui.ResetOnSpawn = false
-- DisplayOrder 9: wins outright over any stale baked-in copy (which used 8).
moreGui.DisplayOrder = 9; moreGui.Parent = PlayerGui
-- ============================================================================================
-- ONE MORE MENU, AND IT IS THIS ONE.
-- ============================================================================================
-- If an old copy of this script is baked into the place file, it builds a SECOND menu gui --
-- either "MorePopupGui" (this file's OLD 210px pop-out design) or another "MoreMenuGui" --
-- that renders behind/over this one. The live script evicts both: NOW for a copy built before
-- this line ran, ON ChildAdded for one built after, and on delayed passes (StarterGui copies
-- are re-cloned into PlayerGui on respawn). TARGETED BY NAME -- never sweeps PlayerGui broadly
-- (that's what once produced the black bar over the HUD).
do
	local function isStaleMoreMenu(g)
		return g ~= moreGui and g:IsA("ScreenGui") and (g.Name == "MoreMenuGui" or g.Name == "MorePopupGui")
	end
	local function evictStaleMoreMenus()
		for _, g in ipairs(PlayerGui:GetChildren()) do
			if isStaleMoreMenu(g) then
				print("[MOREMENU] evicted a stale duplicate " .. g.Name .. " (old pop-out design)")
				g:Destroy()
			end
		end
	end
	evictStaleMoreMenus()
	PlayerGui.ChildAdded:Connect(function(c)
		if isStaleMoreMenu(c) then
			-- deferred: let the other script finish parenting before it is taken away, so it
			-- cannot error mid-build and leave half a menu behind
			task.defer(function()
				if c and c.Parent and isStaleMoreMenu(c) then
					print("[MOREMENU] evicted a stale duplicate " .. c.Name .. " (added after ours)")
					c:Destroy()
				end
			end)
		end
	end)
	for _, d in ipairs({ 0.5, 2, 5, 10 }) do
		task.delay(d, function()
			evictStaleMoreMenus()
			-- re-assert the toggler too: a baked-in copy of the OLD MorePopup script also writes
			-- _G.toggleMorePopup, and if it loaded after us the MORE button would be toggling a
			-- panel this evictor just destroyed.
			_G.toggleMorePopup = function() setMoreOpen(not moreOpenState) end
		end)
	end
end
-- Full-screen catcher: swallows stray taps behind the panel. Does NOT close the menu (project
-- rule: X button only).
local catcher = mkButton(moreGui, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 1, Visible = false })
-- PANEL: 700 wide at (0.5,0,0.5,-45), the same centre the Shop, Pet Hub and Daily Tasks open
-- to. HEIGHT is shrink-to-fit (see the block after the card loop): with three cards the house
-- 520 left a dead pink band under the grid, so the panel hugs its rows instead (520 is the cap).
local panel = mkFrame(moreGui, { Size = UDim2.new(0, 700, 0, 520), Position = UDim2.new(0.5, 0, 0.5, -45),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(225, 70, 170), Visible = false, ZIndex = 2, Active = true })
mkCorner(panel, 20); mkStroke(panel, Color3.fromRGB(140, 20, 100), 3)
-- THE TEXT SWEEPS MUST NOT TOUCH THIS MENU. A dashboard is all precise type sizes -- a 21px
-- title beside a 13px description -- and a blanket TextScaled pass would blow them all up.
-- NoTextSweep is the sweep's documented opt-out (see _G.hudTextSweepSkip in the main game).
moreGui:SetAttribute("NoTextSweep", true)
-- 72px header band: title, subtitle, close. Squared off at the bottom because the 20px corner
-- is only wanted where it meets the panel's own top corners -- without this the band's lower
-- corners cut in and the pink shows through either side of the divider.
local hdr = mkFrame(panel, { Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = Color3.fromRGB(170, 40, 125), ZIndex = 2 })
mkCorner(hdr, 20)
mkFrame(hdr, { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -22), BackgroundColor3 = Color3.fromRGB(170, 40, 125), BorderSizePixel = 0, ZIndex = 2 })
mkLabel(hdr, { Text = "MORE", Font = Enum.Font.FredokaOne, TextSize = 34, TextColor3 = Color3.fromRGB(255, 220, 0), Size = UDim2.new(0, 300, 0, 38), Position = UDim2.new(0, 20, 0, 8), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
mkLabel(hdr, { Text = "Everything else lives here", Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.fromRGB(255, 205, 238), Size = UDim2.new(0, 300, 0, 16), Position = UDim2.new(0, 22, 0, 46), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
local moreX = mkButton(hdr, { Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(1, -52, 0, 16), BackgroundColor3 = Color3.fromRGB(210, 60, 55), Text = "X", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
mkCorner(moreX, 10); mkStroke(moreX, Color3.new(0, 0, 0), 2)
-- Hairline divider separating the header from the cards.
mkFrame(panel, { Size = UDim2.new(1, -40, 0, 2), Position = UDim2.new(0, 20, 0, 74), BackgroundColor3 = Color3.fromRGB(255, 190, 232), BackgroundTransparency = 0.62, BorderSizePixel = 0, ZIndex = 3 })

-- Entry-list scroll: a real ScrollingFrame whose canvas Roblox auto-measures from the children,
-- so the list scrolls if more entries are ever added than fit the 668x424 content box.
local entryScroll = Instance.new("ScrollingFrame")
entryScroll.Name = "EntryList"
entryScroll.BackgroundTransparency = 1 -- seamless: the panel's pink shows through
entryScroll.BorderSizePixel = 0
entryScroll.Position = UDim2.new(0, 16, 0, 82) -- below the 72px header band + its divider
entryScroll.Size = UDim2.new(1, -32, 1, -96)  -- 668 x 424, the exact area the cards are sized to fill
entryScroll.ScrollingEnabled = true
entryScroll.ScrollingDirection = Enum.ScrollingDirection.Y
entryScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
entryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y          -- Roblox measures the canvas from the children
entryScroll.ScrollBarThickness = 6                              -- match PetInventoryUI scroll
entryScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 215, 0)  -- gold, same as PetInventoryUI
entryScroll.ClipsDescendants = true
entryScroll.ZIndex = 2
entryScroll.Parent = panel
-- DASHBOARD GEOMETRY. Positioned by hand rather than by a UIGridLayout, because the Season
-- Pass card spans BOTH columns and a grid layout cannot make one cell double-width.
-- Built to fill the 668x424 content box EXACTLY, so there is no dead space and no scrollbar:
--   columns  327 + 14 gutter + 327 = 668
--   rows     3 x 100 + 2 x 14 gutter = 328, then a 14 gutter, then the 82 full-width card = 424
-- Cards are anchored from their CENTRE so the hover scale grows evenly on all four sides.
local MORE_UI = { CARD_W = 327, CARD_H = 100, GAP = 14, FULL_W = 668, FULL_H = 82, FULL_Y = 342 }

-- "!" ready-dot infrastructure: crate dots + daily-tasks dots are two INDEPENDENT groups, so a
-- done checklist can't clear the crate's dot and vice versa. `list` is which group the dot
-- belongs to.
local crateReadyDots = {}
local taskPendingDots = {}
local function mkCrateDot(parent, list)
	local dot = Instance.new("Frame")
	dot.Name = "CrateReadyDot"
	dot.Size = UDim2.fromOffset(18, 18)
	dot.AnchorPoint = Vector2.new(1, 0)
	dot.Position = UDim2.new(1, -2, 0, -2)
	dot.BackgroundColor3 = Color3.fromRGB(225, 50, 50)
	dot.ZIndex = 8
	dot.Visible = false
	dot.Parent = parent
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot
	local bang = Instance.new("TextLabel")
	bang.BackgroundTransparency = 1; bang.Size = UDim2.fromScale(1, 1)
	bang.Font = Enum.Font.GothamBlack; bang.Text = "!"; bang.TextSize = 13
	bang.TextColor3 = Color3.new(1, 1, 1); bang.ZIndex = 9; bang.Parent = dot
	local group = list or crateReadyDots
	group[#group + 1] = dot
	return dot
end

-- ===== ENTRIES (each: label + desc + tint + emoji + a GUARDED action) =====
-- THREE cards only: Rebirth / Fast Travel / Rewards. Everything else lost its MORE+ door on
-- purpose -- Daily Crate + Daily Tasks are folded INTO the one Rewards card (both "!" dots
-- included), Pets is a rail button, and Journal/Codes/Season Pass rows were cut to keep the
-- menu three tiles. `order` draws the reading order; `full = true` would make a card the
-- full-width bottom-band one (no entry uses it right now).
local MORE_ENTRIES = {
	{ label = "Rebirth", desc = "Reset your progress for permanent multipliers.", tint = Color3.fromRGB(90, 200, 255), order = 1,
	emoji = "\xF0\x9F\x94\x84", action = function()
		if _G.toggleRebirth then _G.toggleRebirth() else print("[MorePopup] _G.toggleRebirth missing") end
	end },
	-- The WORMHOLE, renamed: the card says what it DOES ("Fast Travel"), not what the sci-fi
	-- door is called. Same panel, same _G.toggleWormhole -- label only. It moved here FROM the
	-- rail when the PETS button took its always-visible slot.
	{ label = "Fast Travel", desc = "Warp to any island you've unlocked.", tint = Color3.fromRGB(140, 86, 226), order = 2,
	emoji = "\xF0\x9F\x8C\x80", action = function()
		if _G.toggleWormhole then
			_G.toggleWormhole()
		else
			local sig = RSx:FindFirstChild("OpenWormhole")
			if not sig then sig = Instance.new("BindableEvent"); sig.Name = "OpenWormhole"; sig.Parent = RSx end
			sig:Fire()
		end
	end },
	-- ONE rewards door (same consolidation the main game made): RewardsHub when this realm
	-- gains one; until then the daily CRATE when it's claimable, else the daily TASKS list --
	-- the door always opens whichever thing needs attention, which is also what the two "!"
	-- dots on this card are polling.
	{ label = "Rewards", desc = "Daily crate and today's task checklist.", tint = Color3.fromRGB(255, 175, 45), order = 3,
	emoji = "\xF0\x9F\x8E\x81", readyDot = true, tasksDot = true, action = function()
		if _G.toggleRewardsHub then
			_G.toggleRewardsHub()
		elseif (_G.crateIsClaimable and _G.crateIsClaimable()) or not _G.toggleDailyTasks then
			-- CrateClient has no button of its own; it opens ONLY when this event fires.
			local ev = RSx:FindFirstChild("OpenMeteorCrate")
			if not ev then ev = Instance.new("BindableEvent"); ev.Name = "OpenMeteorCrate"; ev.Parent = RSx end
			ev:Fire()
		else
			_G.toggleDailyTasks()
		end
	end },
}
-- Draw in the requested reading order, not the order the table happens to be written in.
-- `order` overrides; anything without one keeps its table position.
table.sort(MORE_ENTRIES, function(a, b) return (a.order or 99) < (b.order or 99) end)
for i, e in ipairs(MORE_ENTRIES) do
	-- WHERE THIS CARD GOES. The full-width card sits on its own band under the 3x2 grid.
	local w = e.full and MORE_UI.FULL_W or MORE_UI.CARD_W
	local h = e.full and MORE_UI.FULL_H or MORE_UI.CARD_H
	local cx = e.full and (MORE_UI.FULL_W / 2)
		or (((i - 1) % 2) * (MORE_UI.CARD_W + MORE_UI.GAP) + MORE_UI.CARD_W / 2)
	local cy = (e.full and MORE_UI.FULL_Y
		or (math.floor((i - 1) / 2) * (MORE_UI.CARD_H + MORE_UI.GAP))) + h / 2
	-- NO SHADOW FRAME (its square corners stick out past the card's 16px rounded ones and read
	-- as stray tabs -- the card's own dark stroke already separates it from the panel).
	local row = mkButton(entryScroll, { Size = UDim2.new(0, w, 0, h), Position = UDim2.new(0, cx, 0, cy),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(186, 44, 138),
		Text = "", AutoButtonColor = false, ClipsDescendants = true, ZIndex = 3, LayoutOrder = i })
	mkCorner(row, 16); mkStroke(row, Color3.fromRGB(140, 20, 100), 2)
	-- GLOSS: a fixed sheen over the top half. Always on -- this is what makes the tile read as a panel.
	do
		local gl = mkFrame(row, { Size = UDim2.new(1, 0, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 4 })
		mkCorner(gl, 16)
		local gg = Instance.new("UIGradient"); gg.Rotation = 90
		gg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.84), NumberSequenceKeypoint.new(1, 1) })
		gg.Parent = gl
	end
	-- SHINE: a narrow bright band that sweeps across on hover. Parked off the left edge until then.
	local shineG = Instance.new("UIGradient")
	do
		local sh = mkFrame(row, { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 5 })
		-- Rounded to the card's own radius: ClipsDescendants clips to RECTANGULAR bounds, not the
		-- UICorner, so a square shine would flash white over the card's rounded corners.
		mkCorner(sh, 16)
		shineG.Rotation = 18
		shineG.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.74), NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1) })
		shineG.Offset = Vector2.new(-1, 0); shineG.Parent = sh
	end
	-- ICON in its own coloured rounded square -- the one spot of per-feature colour on an
	-- otherwise uniform pink tile, which is what lets the eye find a row without reading any
	-- of the labels.
	do
		local sq = mkFrame(row, { Size = UDim2.new(0, 62, 0, 62), Position = UDim2.new(0, 16, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = e.tint or Color3.fromRGB(255, 175, 45), ZIndex = 6 })
		mkCorner(sq, 14); mkStroke(sq, Color3.fromRGB(140, 20, 100), 2)
		if e.image then
			local im = Instance.new("ImageLabel"); im.BackgroundTransparency = 1; im.Image = e.image; im.ScaleType = Enum.ScaleType.Fit
			im.Size = UDim2.new(1, -12, 1, -12); im.Position = UDim2.new(0, 6, 0, 6); im.ZIndex = 7; im.Parent = sq
		else
			mkLabel(sq, { Text = e.emoji or "", Font = Enum.Font.Gotham, TextSize = 32, Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
		end
	end
	-- TITLE + DESCRIPTION, both left-aligned to the same x so every card reads down one column.
	mkLabel(row, { Text = e.label, Font = Enum.Font.GothamBold, TextSize = 21, TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(0, w - 126, 0, 24), Position = UDim2.new(0, 92, 0, e.full and 14 or 18),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6 })
	mkLabel(row, { Text = e.desc or "", Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.fromRGB(255, 205, 238),
		Size = UDim2.new(0, w - 126, 0, e.full and 24 or 36), Position = UDim2.new(0, 92, 0, e.full and 42 or 44),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 6 })
	-- ARROW: this opens another menu rather than doing something on the spot.
	mkLabel(row, { Text = "\xE2\x9D\xAF", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = Color3.fromRGB(255, 190, 232),
		Size = UDim2.new(0, 24, 1, 0), Position = UDim2.new(0, w - 34, 0, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	-- BADGES, inside the card's own bounds (it clips) and side by side rather than stacked --
	-- the crate dot and the tasks dot are independent, and stacking them hid whichever drew second.
	if e.readyDot then mkCrateDot(row, crateReadyDots).Position = UDim2.new(1, -10, 0, 10) end
	if e.tasksDot then mkCrateDot(row, taskPendingDots).Position = UDim2.new(1, -32, 0, 10) end
	-- HOVER: lift the tile 3% and sweep the shine across it. UIScale (not a Size tween) so the
	-- card grows from its centre and every child scales with it -- icon square, type and arrow
	-- stay in proportion.
	do
		local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = row
		local qi = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		row.MouseEnter:Connect(function()
			TweenService:Create(sc, qi, { Scale = 1.03 }):Play()
			shineG.Offset = Vector2.new(-1, 0)
			TweenService:Create(shineG, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Offset = Vector2.new(1, 0) }):Play()
		end)
		row.MouseLeave:Connect(function() TweenService:Create(sc, qi, { Scale = 1 }):Play() end)
	end
	row.MouseButton1Click:Connect(function() playUIClick(); setMoreOpen(false); pcall(e.action) end)
end
-- SHRINK-TO-FIT: three cards don't need the full 520-tall house box -- the empty pink band
-- under the grid read as a broken menu. Height comes from the rows actually built (capped at
-- the house 520), so adding a card later re-grows the panel and nothing else has to change:
-- the header is scale-width, the scroll is inset-anchored (1,-96), and the panel stays centred.
do
	local gridN, hasFull = 0, false
	for _, e in ipairs(MORE_ENTRIES) do if e.full then hasFull = true else gridN = gridN + 1 end end
	local rows = math.ceil(gridN / 2)
	local contentH = rows * MORE_UI.CARD_H + math.max(rows - 1, 0) * MORE_UI.GAP
	if hasFull then contentH = contentH + MORE_UI.GAP + MORE_UI.FULL_H end
	panel.Size = UDim2.new(0, 700, 0, math.min(520, 82 + contentH + 14))
end
-- Poll every 1s: toggles the card dots. (The MORE rail button's own dot + wiggle are owned by
-- JustButtons_AllInOne -- adding a second dot there would double it up.)
task.spawn(function()
	while true do
		local ready   = (_G.crateIsClaimable and _G.crateIsClaimable()) == true
		local pending = (_G.dailyTasksPending and _G.dailyTasksPending()) == true
		-- Two INDEPENDENT dot groups: claiming the crate must not clear the daily-tasks dot,
		-- and finishing your tasks must not clear the crate's.
		for _, d in ipairs(crateReadyDots)  do d.Visible = ready   end
		for _, d in ipairs(taskPendingDots) do d.Visible = pending end
		task.wait(1)
	end
end)
task.spawn(function() -- print AFTER the layout has measured; scrolls when contentY > frameY
	task.wait(0.3)
	print(string.format("[MOREMENU] scroll: frameY=%d contentY=%d entries=%d (scrolls if contentY>frameY)",
		math.floor(entryScroll.AbsoluteSize.Y), math.floor(entryScroll.AbsoluteCanvasSize.Y), #MORE_ENTRIES))
end)

setMoreOpen = function(open)
	moreOpenState = open and true or false
	if moreOpenState then
		-- No repositioning: the panel is a centred 700x520 window like every other menu, so it
		-- opens in the same place regardless of where the rail button ended up on this device.
		panel.Visible = true; catcher.Visible = true
	else
		panel.Visible = false; catcher.Visible = false
	end
end
-- catcher: swallow the tap, do NOT close (project rule: menus close on the X only)
catcher.MouseButton1Click:Connect(function() end)
moreX.MouseButton1Click:Connect(function() playUIClick(); setMoreOpen(false) end)

-- ===== WIRING to the MORE rail button (JustButtons_AllInOne) =====
_G.toggleMorePopup = function() setMoreOpen(not moreOpenState) end
do -- fallback signal, in case JustButtons ran before _G.toggleMorePopup existed
	local sig = PlayerGui:FindFirstChild("OpenMorePopup")
	if not (sig and sig:IsA("BindableEvent")) then
		sig = Instance.new("BindableEvent"); sig.Name = "OpenMorePopup"; sig.Parent = PlayerGui
	end
	sig.Event:Connect(function() setMoreOpen(not moreOpenState) end)
end

print("[MorePopup] FULL dashboard MORE+ menu built (700x520, " .. #MORE_ENTRIES .. " cards) -- opens via _G.toggleMorePopup / OpenMorePopup")
