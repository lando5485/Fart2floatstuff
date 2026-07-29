--======================================================================
-- RailGuard.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- TWO JOBS, one cause.
--
--   1. THE LEFT RAIL IS EXACTLY FOUR BUTTONS: SHOP / WORMHOLE / Stomach / MORE.
--      Anything else there is hidden, and the survivors are re-spaced evenly.
--
--   2. THE MORE+ MENU: four rows in a centred 2x2 grid, in a panel sized to its own
--      content, with the gradient / shadows / hover / press / open animation polish.
--
-- WHY THIS EXISTS. CoreClient already builds four rail buttons and lists the MORE+
-- entries -- but the CoreClient RUNNING in the place is an older copy that Rojo does not
-- overwrite (its menu shows the old row set and its line numbers do not match the file).
-- A NEW script always syncs, so the fix lives here. Delete this file once the stale
-- CoreClient is gone.
--
-- THE PANEL IS NOT OURS, SO WE ADJUST IT RATHER THAN REBUILD IT. CoreClient owns
-- MoreMenuGui, its header and its close button; this re-sizes and re-styles them in
-- place. Everything added is named "RG_*" so a second pass can find its own work and
-- never double up.
--======================================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player       = Players.LocalPlayer
local PlayerGui    = player:WaitForChild("PlayerGui")
local RSx          = game:GetService("ReplicatedStorage")

--======================================================================
-- RAIL CONFIG
--======================================================================
local KEEP = { shop = true, wormhole = true, stomach = true, more = true }
local NEVER_TOUCH = {
	SidebarGui = true, ReturnIslandGui = true, MoreMenuGui = true,
	BottomStackGui = true, GasMeterGui = true, FartButtonGui = true, StomachGui = true,
	CoinGui = true, RightPanelGui = true, SettingsGui = true,
}
local STRAY_GUIS = { PetHubButton = true }
local MIN_SIDE, MAX_SIDE, MAX_LEFT_OFFSET = 55, 115, 150

--======================================================================
-- MORE+ GEOMETRY
--
-- The panel is sized to its CONTENT rather than to the old fixed 520. Four cards in two
-- rows need 252px; a 520-tall panel left ~170px of empty pink under them, which read as
-- a menu that had lost half its items.
--
--   grid   2 x 324 + 20 gutter = 668 wide  |  2 x 116 + 20 gutter = 252 tall
--   panel  72 header + 14 + 252 + 14 pad + a little breathing room = 372
--======================================================================
local PANEL_W, PANEL_H = 700, 372
local CARD_W, CARD_H, GAP = 324, 116, 20
local LIST_X, LIST_Y = 16, 86            -- content box inset inside the panel
local LIST_W = PANEL_W - LIST_X * 2      -- 668
local LIST_H = PANEL_H - LIST_Y - 14     -- 272

-- Grid centred in the content box. Width matches exactly, so only Y needs an offset.
local GRID_W = CARD_W * 2 + GAP
local GRID_H = CARD_H * 2 + GAP
local OFF_X  = math.floor((LIST_W - GRID_W) / 2)
local OFF_Y  = math.floor((LIST_H - GRID_H) / 2)

-- ---- palette ----
local PANEL_TOP    = Color3.fromRGB(238, 108, 192) -- lighter magenta, top of the gradient
local PANEL_BOTTOM = Color3.fromRGB(182,  44, 136) -- deeper magenta, bottom
local HEADER_FILL  = Color3.fromRGB(158,  34, 116)
local CARD_FILL    = Color3.fromRGB(186,  44, 138)
local CARD_HOVER   = Color3.fromRGB(206,  62, 158) -- the brighten-on-hover target
local CARD_BORDER  = Color3.fromRGB(240, 132, 200) -- thin LIGHTER border, lifts the card
local DESC_COLOR   = Color3.fromRGB(255, 205, 238)
local ARROW_COLOR  = Color3.fromRGB(255, 190, 232)
local GLOW_IMAGE   = "rbxassetid://1316045217"     -- soft radial, already used for glows in this game

local HOVER_TI = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_TI = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--======================================================================
-- THE FOUR ROWS
--======================================================================
-- `gui` on each row is the ScreenGui that MUST be on screen a moment after the card is
-- clicked. It is what the verify pass below checks -- see openedOk / forceOpen.
local ENTRIES = {
	{ key = "rebirth", label = "Rebirth", desc = "Reset your progress for permanent multipliers.",
	  tint = Color3.fromRGB(90, 200, 255), emoji = "\xF0\x9F\x94\x84", gui = "RebirthGui",
	  action = function() if _G.toggleRebirth then _G.toggleRebirth() end end },

	-- ONE "Rewards" row. Daily and Free were two rows for the same idea -- things you claim
	-- for free -- and a player had to already know which menu held which. RewardsHub is the
	-- single door; DAILY and FREE are sections inside it. ONE badge carries the COUNT of
	-- whatever is waiting, instead of two dots the player has to decode.
	{ key = "rewards", label = "Rewards", desc = "Daily login rewards and free playtime rewards.",
	  tint = Color3.fromRGB(255, 175, 45), emoji = "\xF0\x9F\x8E\x81", badge = true, gui = "RewardsHubGui",
	  action = function()
		-- OPEN, not toggle. A card in this menu always means "show me this" -- if the hub's
		-- Enabled flag were left true by anything else, a toggle would close it and the card
		-- would read as dead.
		if _G.openRewardsHub then
			_G.openRewardsHub()
		elseif _G.toggleRewardsHub then
			_G.toggleRewardsHub()
		elseif _G.dailyTasksAvailable and _G.dailyTasksAvailable() then
			if _G.toggleDailyTasks then _G.toggleDailyTasks() end
		else
			local ev = RSx:FindFirstChild("OpenMeteorCrate")
			if not ev then ev = Instance.new("BindableEvent"); ev.Name = "OpenMeteorCrate"; ev.Parent = RSx end
			ev:Fire()
		end
	  end },

	-- ONE door into the pet hub, crates included.
	--
	-- ===== WHY "SKIN CRATES" IS NO LONGER ITS OWN ROW =====
	-- The Pet Hub and the crate panel are not two menus. They are ONE interface of five pages --
	-- PETS / CRATES / TOKENS / TRADE / QUESTS -- split across two ScreenGuis that render the same
	-- tab bar pixel-for-pixel and hand off to each other (SkinCrateClient's TABS table says so in
	-- as many words). Listing two of those five pages as separate menu rows is what made pressing
	-- two different buttons land you on "the same GUI, different tab": correct behaviour, wrong menu.
	--
	-- CRATES DID NOT GET DEMOTED. It is still its own full-screen page with its own roll, reveal and
	-- token shop -- it is simply reached the same way the other four pages are, from the tab bar that
	-- is the first thing you see when the hub opens. And it now ADVERTISES itself: the badge below
	-- carries your unspent crate tokens, so "you have crates to open" is on the menu tile itself
	-- rather than behind a row a player might never press.
	{ key = "pets", label = "Pets & Crates", desc = "Pets, skins, crates, tokens and trading.",
	  tint = Color3.fromRGB(120, 225, 120), emoji = "\xF0\x9F\x90\xBE", badge = true, gui = "PetInventoryUI",
	  action = function()
		local ev = PlayerGui:FindFirstChild("PetInvToggle")
		if ev then ev:Fire() end
	  end },

	-- SEASONAL PETS moved to the treasure box beside the Global Garden (SeasonalPetsChest).
	-- SEASON PASS was removed from this menu entirely.
	-- SKIN CRATES is the CRATES page of the row above (_G.toggleSkinCrates still exists for /crates
	-- and for the hub's own tab bar -- only the duplicate menu row went away).
}

--======================================================================
local seen = {}
local badgeRefs = {}   -- [entry key] = { frame, label }; one per badged card, see the poll at the end

--======================================================================
-- WHO OWNS "IS THE MENU OPEN?"
--
-- THE BUG THIS FIXES: a card used to close the menu by hiding the panel itself. CoreClient
-- was never told, so its own moreOpenState stayed TRUE -- and the next tap on the rail
-- button toggled it to false, which changed nothing on screen. Every OTHER tap did
-- nothing, which reads as "after a bit the buttons stop opening it".
--
-- ===== THE STATE IS THE PANEL, NOT A BOOLEAN =====
-- The first version of this fix cached its own `moreState` bool -- which recreated the
-- disease it was curing, just with a new owner: anything that hid the panel from outside
-- (the menu manager's hider, a stale script, the catcher below) left the bool stale and
-- the next tap dead. There is exactly one fact -- "is the panel on screen" -- and the
-- panel itself already stores it. Everything here READS panel.Visible and never caches
-- it, so an outside close self-heals on the very next tap instead of eating it.
--
-- ===== THE CATCHER STAYS DEAD =====
-- MoreMenuGui has TWO children: the panel Frame and a full-screen transparent TextButton
-- ("catcher") that the STALE CoreClient wired to close the menu on any tap
-- (catcher.MouseButton1Click -> its own setMoreOpen(false), CoreClient:1298). Showing all
-- children on open -- what this used to do -- re-armed that: one stray tap anywhere on
-- screen closed the panel through the stale script's state, and the rail button went back
-- to needing two taps. It also breaks the standing rule that menus close on the X ONLY,
-- never on a stray screen tap. So: the panel is the only child that ever becomes visible.
--======================================================================
local function moreGui() return PlayerGui:FindFirstChild("MoreMenuGui") end

local function morePanel()
	local gui = moreGui()
	if not gui then return nil, nil end
	for _, ch in ipairs(gui:GetChildren()) do
		if ch.ClassName == "Frame" then return ch, gui end
	end
	return nil, gui
end

local function isMoreOpen()
	local panel = morePanel()
	return panel ~= nil and panel.Visible
end

-- Raw hide, NO manager notify. This is what gets registered as the manager's own hider
-- for "More": notifyOpened(other) calls it while it is mid-switch, and notifying back
-- into the manager from inside its own hider would clear `current` out from under it.
local function hideMoreRaw()
	local _, gui = morePanel()
	if not gui then return end
	for _, ch in ipairs(gui:GetChildren()) do
		if ch:IsA("GuiObject") then ch.Visible = false end
	end
end

local function setMoreOpen(open)
	local panel, gui = morePanel()
	if not (panel and gui) then return end
	open = open and true or false
	for _, ch in ipairs(gui:GetChildren()) do
		if ch:IsA("GuiObject") then
			-- panel shows/hides; the catcher (and anything else) is forced OFF either way
			ch.Visible = open and (ch == panel)
		end
	end
	-- Tell the menu manager, so opening MORE+ closes whatever else was up (and the other
	-- panels' own registrations keep working).
	if _G.MainMenuManager then
		local fn = open and _G.MainMenuManager.notifyOpened or _G.MainMenuManager.notifyClosed
		if fn then pcall(fn, "More") end
	end
end

-- WITHOUT THIS, MENUS STACK. notifyOpened(other) closes the previous menu through
-- mgr.hiders[current] -- and nothing anywhere registered a hider for "More" (the stale
-- CoreClient's registrations don't include it). So MORE+ open + a tap on SHOP left the
-- MORE panel sitting there underneath the Shop: two menus on screen at once.
if _G.MainMenuManager and _G.MainMenuManager.register then
	pcall(_G.MainMenuManager.register, "More", hideMoreRaw)
end

_G.setMoreOpen      = setMoreOpen
_G.toggleMorePopup  = function() setMoreOpen(not isMoreOpen()) end
_G.railGuardOpenMore = function() setMoreOpen(true) end

-- Take the rail's MORE button. CoreClient's click area is a full-size transparent
-- TextButton inside the tile; hiding it stops it firing, and ours goes on top.
local function claimMoreButton(frame)
	if frame:FindFirstChild("RG_MoreClick") then return end
	for _, ch in ipairs(frame:GetChildren()) do
		if ch:IsA("TextButton") then ch.Visible = false end
	end
	local b = Instance.new("TextButton")
	b.Name = "RG_MoreClick"
	b.Size = UDim2.new(1, 0, 1, 0)
	b.BackgroundTransparency = 1
	b.Text = ""
	b.ZIndex = 20
	b.Parent = frame
	b.MouseButton1Click:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		setMoreOpen(not isMoreOpen())
	end)
end

local function norm(s) return (tostring(s):lower():gsub("[%s_%-%+]", "")) end
local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function stroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = o; return s end

local function hide(obj, why)
	if obj:IsA("GuiObject") and obj.Visible == false then return end
	if obj:IsA("ScreenGui") and obj.Enabled == false then return end
	if not seen[obj] then
		seen[obj] = true
		warn(("[RailGuard] hid %s (%s)"):format(obj:GetFullName(), why))
	end
	pcall(function()
		if obj:IsA("ScreenGui") then obj.Enabled = false else obj.Visible = false end
	end)
end

--======================================================================
-- DID IT ACTUALLY OPEN?
--
-- A card firing its action is not proof the panel appeared. Every one of these panels is
-- owned by a different script, and each is driven by ONE of two flags:
--
--     ScreenGui.Enabled          (Skin Crates, Daily Tasks, the Rewards hub)
--     the panel frame's Visible  (Rebirth, Pet Hub, Free Rewards)
--
-- Anything that clears the flag a panel does NOT drive leaves it unable to show itself:
-- its own toggle flips the flag it knows about, the other one stays off, and the card
-- reads as dead with nothing in the log. (That is precisely what BACK used to do -- fixed
-- in MenuBackButton -- but the same shape of bug can come back from any stale duplicate
-- script in the place, and there are 19 of those.)
--
-- So the card checks, and repairs. This is a NET, not the mechanism: if it ever fires it
-- prints who needed rescuing, so the real cause is findable rather than papered over.
--======================================================================
-- STRICTLY a Frame, never "any big GuiObject".
--
-- RebirthGui's children are, in order: `dim` (TextButton), `shadow` (ImageLabel, fromOffset(720, 546)) and
-- THEN `panel`. Matching on size alone returned the SHADOW -- which RebirthClient keeps hidden forever
-- ("shadow.Visible = false" runs on open AND close, line 281). So this read the panel as closed even with
-- Rebirth on screen, and the repair below then switched the shadow ON: a 720x546 black radial at 0.62
-- transparency, i.e. a faded sheet over the middle of the screen that nothing ever turns off again.
--
-- Every panel in this game is a Frame; the decoration around them is not.
local function panelFrame(gui)
	for _, ch in ipairs(gui:GetChildren()) do
		if ch.ClassName == "Frame" and ch.Size.X.Offset >= 400 and ch.Size.Y.Offset >= 200 then return ch end
	end
	for _, ch in ipairs(gui:GetChildren()) do
		if ch.ClassName == "Frame" and ch.Size.X.Scale >= 0.5 then return ch end
	end
	return nil
end

-- Several of these names exist TWICE in PlayerGui (the log lists 8 duplicate ScreenGuis).
-- The real one is whichever the owning script actually built out, so prefer the copy with
-- the most descendants -- a stale shell has almost none.
local function bestGui(name)
	local best
	for _, g in ipairs(PlayerGui:GetChildren()) do
		if g.Name == name and g:IsA("ScreenGui") then
			if not best or #g:GetDescendants() > #best:GetDescendants() then best = g end
		end
	end
	return best
end

local function openedOk(name)
	for _, g in ipairs(PlayerGui:GetChildren()) do
		if g.Name == name and g:IsA("ScreenGui") and g.Enabled then
			local p = panelFrame(g)
			if p == nil or p.Visible then return true end
		end
	end
	return false
end

local function forceOpen(name)
	local g = bestGui(name)
	if not g then return false end
	g.Enabled = true
	local p = panelFrame(g)
	if p then p.Visible = true end
	return true
end

--======================================================================
-- ONE CARD
--======================================================================
local function mkCard(parent, e, index)
	-- Two per row -- except a row that ends up with ONE card, which is centred instead of left-hanging.
	-- With three entries the old formula parked the last card in the left column with a card-shaped hole
	-- beside it, which reads as a row that failed to load rather than as a deliberate layout.
	local col      = (index - 1) % 2
	local rowStart = index - col
	local inRow    = math.min(2, #ENTRIES - rowStart + 1)
	local cx = (inRow == 1)
		and (LIST_W / 2)
		or  (OFF_X + col * (CARD_W + GAP) + CARD_W / 2)
	local cy = OFF_Y + math.floor((index - 1) / 2) * (CARD_H + GAP) + CARD_H / 2

	-- DROP SHADOW: a soft radial image, NOT a plain offset frame. A frame needs its own
	-- UICorner or its four square corners stick out past the card's rounded ones and read
	-- as dark tabs -- which is exactly why the original shadow here was deleted rather
	-- than fixed. A radial image has no corners to leak.
	local shadow = Instance.new("ImageLabel")
	shadow.Name = "RG_Shadow"
	shadow.BackgroundTransparency = 1
	shadow.Image = GLOW_IMAGE
	shadow.ImageColor3 = Color3.fromRGB(70, 8, 50)
	shadow.ImageTransparency = 0.62
	shadow.Size = UDim2.new(0, CARD_W + 26, 0, CARD_H + 26)
	shadow.Position = UDim2.new(0, cx, 0, cy + 4) -- a touch low, so the light reads as overhead
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.ZIndex = 2
	shadow.Parent = parent

	local row = Instance.new("TextButton")
	row.Name = "RailGuard_" .. e.key
	row.Size = UDim2.new(0, CARD_W, 0, CARD_H)
	row.Position = UDim2.new(0, cx, 0, cy)
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.BackgroundColor3 = CARD_FILL
	row.Text = ""
	row.AutoButtonColor = false   -- we drive hover/press ourselves; the built-in tint fights the tween
	row.ClipsDescendants = false  -- the badge deliberately overlaps the corner
	row.ZIndex = 3
	row.Parent = parent
	corner(row, 18)
	stroke(row, CARD_BORDER, 1.5)

	-- gloss over the top half: what makes the tile read as a panel, not a flat rectangle
	do
		local gl = Instance.new("Frame")
		gl.Size = UDim2.new(1, 0, 0.5, 0); gl.BackgroundColor3 = Color3.new(1, 1, 1)
		gl.BorderSizePixel = 0; gl.ZIndex = 4; gl.Parent = row
		corner(gl, 18)
		local gg = Instance.new("UIGradient"); gg.Rotation = 90
		gg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(1, 1) })
		gg.Parent = gl
	end

	-- ICON: a rounder tinted square, a soft glow behind it in its own colour, and a
	-- semi-transparent sheen INSIDE it.
	--
	-- ===== THE SHEEN IS INSET AND CONCENTRIC =====
	-- It sits 4px in on every side and is rounded to 16, not 20. A rounded box inset
	-- inside another only looks concentric if its radius drops by the SAME amount as the
	-- inset -- keeping 20 would leave the sheen's corners bulging past the square's, which
	-- is the exact artefact this is fixing. So: outer 62 @ r20, inner 54 @ r16.
	do
		local ICON  = 62   -- the square
		local INSET = 4    -- per side
		local R_OUT = 20
		local R_IN  = R_OUT - INSET

		-- BACKING SQUARE behind the icon. The glow asset fills its whole box, so at 108px it
		-- was drawing a hard-edged 90-degree square behind a 20-radius icon -- two different
		-- shapes stacked. UICorner clips an ImageLabel exactly as it clips a Frame, so the
		-- backing takes the SAME radius as the square in front of it and the two now agree.
		--
		-- Kept smaller than it started (108 -> 96 -> 86) as well: at 108 the corners of the
		-- backing sat so far out that rounding them still left it reading as its own
		-- separate tile rather than as a halo belonging to the icon.
		--
		-- Anchored from its CENTRE at the icon square's centre, so every size change stays
		-- concentric on its own -- there is no offset to re-derive when BACKING changes.
		local BACKING = math.floor(96 * 0.9 + 0.5)   -- 86
		local glow = Instance.new("ImageLabel")
		glow.Name = "IconGlow"
		glow.BackgroundTransparency = 1; glow.Image = GLOW_IMAGE
		glow.ImageColor3 = e.tint; glow.ImageTransparency = 0.55
		glow.Size = UDim2.new(0, BACKING, 0, BACKING)
		glow.Position = UDim2.new(0, 16 + ICON / 2, 0.5, 0)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.ZIndex = 5; glow.Parent = row
		corner(glow, R_OUT)   -- same radius as the icon square, so both shapes match

		local sq = Instance.new("Frame")
		sq.Name = "IconSquare"
		sq.Size = UDim2.new(0, ICON, 0, ICON); sq.Position = UDim2.new(0, 16, 0.5, 0)
		sq.AnchorPoint = Vector2.new(0, 0.5); sq.BackgroundColor3 = e.tint
		sq.ClipsDescendants = true   -- belt and braces: nothing inside can spill past the radius
		sq.ZIndex = 6; sq.Parent = row
		corner(sq, R_OUT)
		stroke(sq, Color3.fromRGB(255, 255, 255), 1.5)

		local sheen = Instance.new("Frame")
		sheen.Name = "IconSheen"
		sheen.Size = UDim2.new(1, -INSET * 2, 1, -INSET * 2)
		sheen.Position = UDim2.new(0.5, 0, 0.5, 0)
		sheen.AnchorPoint = Vector2.new(0.5, 0.5)
		sheen.BackgroundColor3 = Color3.new(1, 1, 1)
		sheen.BackgroundTransparency = 0.78
		sheen.BorderSizePixel = 0
		sheen.ZIndex = 7; sheen.Parent = sq
		corner(sheen, R_IN)

		local ic = Instance.new("TextLabel")
		ic.BackgroundTransparency = 1; ic.Size = UDim2.new(1, 0, 1, 0)
		ic.Text = e.emoji; ic.Font = Enum.Font.Gotham; ic.TextSize = 32
		ic.TextXAlignment = Enum.TextXAlignment.Center
		ic.ZIndex = 8; ic.Parent = sq   -- above the sheen, or the glyph goes milky
	end

	-- TITLE + DESCRIPTION. More internal padding than before: the text block starts at 96
	-- and the title sits 22 down instead of 18, so nothing crowds the card's edge.
	local title = Instance.new("TextLabel")
	title.Name = "Title"; title.BackgroundTransparency = 1
	title.Text = e.label; title.Font = Enum.Font.GothamBold; title.TextSize = 21
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Size = UDim2.new(0, CARD_W - 136, 0, 24)
	title.Position = UDim2.new(0, 96, 0, 22)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 6; title.Parent = row

	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Text = e.desc; desc.Font = Enum.Font.Gotham; desc.TextSize = 13
	desc.TextColor3 = DESC_COLOR
	desc.Size = UDim2.new(0, CARD_W - 136, 0, 44)
	desc.Position = UDim2.new(0, 96, 0, 50)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.ZIndex = 6; desc.Parent = row

	local arrow = Instance.new("TextLabel")
	arrow.BackgroundTransparency = 1
	arrow.Text = "\xE2\x9D\xAF"; arrow.Font = Enum.Font.FredokaOne; arrow.TextSize = 20
	arrow.TextColor3 = ARROW_COLOR
	arrow.Size = UDim2.new(0, 24, 1, 0); arrow.Position = UDim2.new(1, -34, 0, 0)
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.ZIndex = 6; arrow.Parent = row

	-- ONE BADGE WITH A COUNT, overlapping the top-right corner. Two separate dots meant a
	-- player had to know which was which; a number just says how many things are waiting.
	if e.badge then
		local b = Instance.new("Frame")
		b.Name = "RG_Badge"
		b.Size = UDim2.fromOffset(30, 30)
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.new(1, -2, 0, 2)   -- hangs over the corner rather than sitting inside it
		b.BackgroundColor3 = Color3.fromRGB(228, 46, 46)
		b.ZIndex = 10; b.Visible = false; b.Parent = row
		corner(b, 999); stroke(b, Color3.new(1, 1, 1), 2)

		local n = Instance.new("TextLabel")
		n.Name = "Count"; n.BackgroundTransparency = 1; n.Size = UDim2.fromScale(1, 1)
		n.Font = Enum.Font.GothamBlack; n.Text = "1"; n.TextSize = 16
		n.TextColor3 = Color3.new(1, 1, 1); n.ZIndex = 11; n.Parent = b

		-- gentle pulse, driven by a UIScale so the stroke and the number breathe with it
		local bs = Instance.new("UIScale"); bs.Scale = 1; bs.Parent = b
		TweenService:Create(bs,
			TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.14 }):Play()

		badgeRefs[e.key] = { frame = b, label = n }
	end

	-- HOVER + PRESS. UIScale (not a Size tween) so the card grows from its centre and every
	-- child scales with it; the shadow scales in step so it never detaches from the card.
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = row
	local shSc = Instance.new("UIScale"); shSc.Scale = 1; shSc.Parent = shadow
	local function to(scale, fill, ti)
		TweenService:Create(sc, ti, { Scale = scale }):Play()
		TweenService:Create(shSc, ti, { Scale = scale }):Play()
		if fill then TweenService:Create(row, ti, { BackgroundColor3 = fill }):Play() end
	end
	local hovering = false
	row.MouseEnter:Connect(function() hovering = true;  to(1.03, CARD_HOVER, HOVER_TI) end)
	row.MouseLeave:Connect(function() hovering = false; to(1.00, CARD_FILL,  HOVER_TI) end)
	row.MouseButton1Down:Connect(function() to(0.97, nil, PRESS_TI) end)
	row.MouseButton1Up:Connect(function() to(hovering and 1.03 or 1.00, nil, PRESS_TI) end)

	-- DEBOUNCED. Every action behind these cards is a TOGGLE (PetInvToggle, _G.toggleRebirth,
	-- ...), so a fast double-tap -- routine on a phone -- fired open-then-close: the player
	-- saw a flicker and nothing else, and the verify net below then "repaired" a panel they
	-- never saw. 0.35s swallows the double-tap; a deliberate second press still works.
	local lastClick = 0
	row.MouseButton1Click:Connect(function()
		local now = os.clock()
		if now - lastClick < 0.35 then return end
		lastClick = now
		if _G.playUIClick then pcall(_G.playUIClick) end
		if _G.setMoreOpen then _G.setMoreOpen(false) end
		pcall(e.action)
		if not e.gui then return end
		-- POLLED, not sampled twice. Two widely-spaced samples can both miss a panel that opened
		-- and was closed again in between -- and then the repair "fixes" a panel the player has
		-- already shut. Checking every 0.1s means any open at all is seen, so the repair only ever
		-- runs for a panel that never appeared once.
		--
		-- Deferred rather than immediate because several of these notify MainMenuManager on open,
		-- which closes the others in the same frame; and it runs for ~1s because the Pet Hub builds
		-- its 3D icons on open and can land a few frames after the rest.
		task.spawn(function()
			for _ = 1, 10 do
				task.wait(0.1)
				if openedOk(e.gui) then return end
			end
			if forceOpen(e.gui) then
				warn(("[RailGuard] %q did not open on its own -- forced %s on screen. "
					.. "Something cleared the flag that panel does not drive; check for a stale "
					.. "duplicate of its LocalScript in Studio."):format(e.label, e.gui))
			else
				warn(("[RailGuard] %q opened nothing -- no %s in PlayerGui at all."):format(e.label, e.gui))
			end
		end)
	end)

	return row
end

--======================================================================
-- PANEL POLISH  — resize, gradient, header, close button, open animation
--======================================================================
local function polishPanel(gui)
	local panel = gui:FindFirstChild("Frame")
	if not (panel and panel:IsA("GuiObject")) then return nil end

	-- SIZE TO CONTENT. Keeps whatever position the build chose.
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)

	-- GRADIENT: lighter at the top, deeper at the bottom. UIGradient MULTIPLIES the
	-- background colour, so the fill is set to the TOP colour and the gradient darkens
	-- toward the bottom by the exact per-channel ratio -- which lands on PANEL_BOTTOM
	-- precisely instead of by eye.
	if not panel:FindFirstChild("RG_Gradient") then
		panel.BackgroundColor3 = PANEL_TOP
		local g = Instance.new("UIGradient")
		g.Name = "RG_Gradient"; g.Rotation = 90
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.new(
				PANEL_BOTTOM.R / math.max(PANEL_TOP.R, 0.001),
				PANEL_BOTTOM.G / math.max(PANEL_TOP.G, 0.001),
				PANEL_BOTTOM.B / math.max(PANEL_TOP.B, 0.001))),
		})
		g.Parent = panel
	end

	-- HEADER: find it by shape (a full-width band 60-80 tall pinned to the top).
	local header, title, closeBtn
	for _, ch in ipairs(panel:GetChildren()) do
		if ch:IsA("Frame") and ch.Size.X.Scale >= 1 and ch.Size.Y.Offset >= 60 and ch.Size.Y.Offset <= 80 then
			header = ch; break
		end
	end

	-- THE UNDERLINE ARTIFACT: CoreClient parks a 2px hairline just under the header, and
	-- with a darker header bar it reads as a stray line under the subtitle rather than as
	-- a divider. Remove every hairline in the panel, then draw one clean divider on the
	-- header's own bottom edge where it belongs.
	for _, ch in ipairs(panel:GetChildren()) do
		if ch:IsA("Frame") and ch.Size.Y.Offset > 0 and ch.Size.Y.Offset <= 3 and ch.Name ~= "RG_Divider" then
			ch:Destroy()
		end
	end

	if header then
		header.BackgroundColor3 = HEADER_FILL
		for _, ch in ipairs(header:GetChildren()) do
			if ch:IsA("TextLabel") and ch.TextSize >= 28 then title = ch end
			if ch:IsA("TextButton") and ch.Size.X.Offset >= 30 and ch.Size.X.Offset <= 56 then closeBtn = ch end
			-- the patch frame CoreClient uses to square off the header's bottom corners
			if ch:IsA("Frame") and ch.Size.Y.Offset > 0 and ch.Size.Y.Offset <= 24 then
				ch.BackgroundColor3 = HEADER_FILL
			end
		end

		if not header:FindFirstChild("RG_Divider") then
			local d = Instance.new("Frame")
			d.Name = "RG_Divider"
			d.Size = UDim2.new(1, 0, 0, 2)
			d.Position = UDim2.new(0, 0, 1, -2)
			d.BackgroundColor3 = Color3.fromRGB(255, 190, 232)
			d.BackgroundTransparency = 0.55
			d.BorderSizePixel = 0; d.ZIndex = 4; d.Parent = header
		end

		-- CLOSE BUTTON aligned to the TITLE's vertical centre, not the header's. The title
		-- sits above the subtitle, so header-centre put the X visibly below the word it
		-- belongs to.
		if closeBtn then
			local titleMid = title
				and (title.Position.Y.Offset + title.Size.Y.Offset / 2)
				or (header.Size.Y.Offset / 2)
			closeBtn.AnchorPoint = Vector2.new(1, 0.5)
			closeBtn.Position = UDim2.new(1, -20, 0, titleMid)
		end
	end

	return panel
end

--======================================================================
-- OPEN / CLOSE MOTION
--
-- Scale + fade, driven off the panel's own Visible flag so it works no matter which
-- script opens the menu. A CanvasGroup would fade children too, but the panel is
-- CoreClient's and re-parenting its whole subtree to convert it is a far bigger risk
-- than this is worth -- scaling from 0.9 with the background fading in reads as a pop.
--======================================================================
local motionHooked = false
local function hookMotion(panel)
	if motionHooked or not panel then return end
	motionHooked = true

	local sc = panel:FindFirstChild("RG_Motion")
	if not sc then
		sc = Instance.new("UIScale"); sc.Name = "RG_Motion"; sc.Parent = panel
	end

	local IN  = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if panel.Visible then
			sc.Scale = 0.90
			panel.BackgroundTransparency = 0.35
			TweenService:Create(sc, IN, { Scale = 1 }):Play()
			TweenService:Create(panel, IN, { BackgroundTransparency = 0 }):Play()
		else
			-- Visible is already false, so this plays on the way back IN next time rather
			-- than being seen now. Reset instead of animating out -- animating a hidden
			-- frame is invisible work, and holding it visible to play an exit would fight
			-- whichever script just closed it.
			sc.Scale = 0.90
			panel.BackgroundTransparency = 0.35
		end
	end)
end

--======================================================================
-- BUILD THE GRID
--======================================================================
local function entryList()
	local gui = PlayerGui:FindFirstChild("MoreMenuGui")
	if not gui then return nil, nil end
	local frame = gui:FindFirstChild("Frame")
	if not frame then return nil, nil end
	return (frame:FindFirstChild("EntryList") or frame:FindFirstChildWhichIsA("ScrollingFrame")), gui
end

local gridBuilt = false

local function buildGrid()
	if gridBuilt then return true end
	local list, gui = entryList()
	if not (list and gui) then return false end

	local panel = polishPanel(gui)
	hookMotion(panel)

	-- Retire whatever the running build put here. HIDDEN, not destroyed: that build keeps
	-- references to its own rows and wires dots and tweens to them afterwards, and
	-- destroying them can throw inside it and take the rest of that script down.
	local retired = 0
	for _, ch in ipairs(list:GetChildren()) do
		if ch:IsA("GuiObject") and ch.Name:sub(1, 4) ~= "RG_S" and ch.Name:sub(1, 10) ~= "RailGuard_" then
			ch.Visible = false
			retired += 1
		end
	end
	-- A layout would fight the hand-placed positions: the grid is centred by computed
	-- offsets, which a UIListLayout would immediately overwrite.
	for _, ch in ipairs(list:GetChildren()) do
		if ch:IsA("UIGridStyleLayout") then ch:Destroy() end
	end

	list.Position = UDim2.new(0, LIST_X, 0, LIST_Y)
	list.Size     = UDim2.new(0, LIST_W, 0, LIST_H)
	list.CanvasSize = UDim2.new(0, 0, 0, 0)          -- content fits exactly: nothing to scroll
	list.AutomaticCanvasSize = Enum.AutomaticSize.None
	list.ClipsDescendants = false                    -- so a hovered card's shadow is not cut off

	for i, e in ipairs(ENTRIES) do mkCard(list, e, i) end

	gridBuilt = true
	print(("[RailGuard] MORE+ rebuilt: %d cards centred in a %dx%d panel, %d stale row(s) retired")
		:format(#ENTRIES, PANEL_W, PANEL_H, retired))
	return true
end

--======================================================================
-- THE RAIL
--======================================================================
local function labelOf(btn)
	local l = btn:FindFirstChild("Label")
	if l and l:IsA("TextLabel") then return norm(l.Text) end
	return nil
end

local function isRailShaped(obj)
	if not obj:IsA("GuiObject") then return false end
	local sz, pos = obj.Size, obj.Position
	if sz.X.Scale ~= 0 or sz.Y.Scale ~= 0 then return false end
	local w, h = sz.X.Offset, sz.Y.Offset
	if w < MIN_SIDE or w > MAX_SIDE or h < MIN_SIDE or h > MAX_SIDE then return false end
	if math.abs(w - h) > math.max(w, h) * 0.2 then return false end
	if pos.X.Scale ~= 0 or pos.X.Offset > MAX_LEFT_OFFSET then return false end
	return true
end

local function sweepRail(sidebar)
	for _, child in ipairs(sidebar:GetChildren()) do
		if child:IsA("GuiObject") then
			local lbl = labelOf(child)
			if lbl then
				if not KEEP[lbl] then
					hide(child, ("rail button %q -> MORE+"):format(lbl))
				elseif lbl == "more" then
					claimMoreButton(child)
				end
			elseif isRailShaped(child) then
				hide(child, "unlabelled rail-shaped button in SidebarGui")
			end
		end
	end
end

local function respace(sidebar)
	local btns = {}
	for _, c in ipairs(sidebar:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible and labelOf(c) then btns[#btns + 1] = c end
	end
	if #btns < 3 then return end
	table.sort(btns, function(a, b) return a.AbsolutePosition.Y < b.AbsolutePosition.Y end)
	local pitch = btns[2].AbsolutePosition.Y - btns[1].AbsolutePosition.Y
	if pitch <= 1 then return end
	local topY = btns[1].AbsolutePosition.Y
	for i = 3, #btns do
		local delta = (topY + pitch * (i - 1)) - btns[i].AbsolutePosition.Y
		if math.abs(delta) > 1 then
			local p = btns[i].Position
			btns[i].Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + delta)
		end
	end
end

--======================================================================
-- RUN
--======================================================================
local function pass()
	for _, gui in ipairs(PlayerGui:GetChildren()) do
		if gui:IsA("ScreenGui") and not NEVER_TOUCH[gui.Name] then
			if STRAY_GUIS[gui.Name] then
				hide(gui, "known stray launcher")
			else
				for _, child in ipairs(gui:GetChildren()) do
					if isRailShaped(child) then
						hide(child, ("square left-edge button in %s"):format(gui.Name))
					end
				end
			end
		end
	end
	pcall(buildGrid)
	local sidebar = PlayerGui:FindFirstChild("SidebarGui")
	if sidebar then pcall(sweepRail, sidebar); pcall(respace, sidebar) end
end

pass()

PlayerGui.ChildAdded:Connect(function()
	task.defer(pass)
	task.delay(0.5, pass)
end)

task.spawn(function()
	local sidebar = PlayerGui:WaitForChild("SidebarGui", 30)
	if sidebar then sidebar.ChildAdded:Connect(function() task.defer(pass) end) end
end)

task.spawn(function()
	while true do
		task.wait(1)
		pcall(buildGrid)
		local sidebar = PlayerGui:FindFirstChild("SidebarGui")
		if sidebar then pcall(sweepRail, sidebar); pcall(respace, sidebar) end
		-- Re-assert the "More" hider: the one-shot register above can run before CoreClient
		-- has created MainMenuManager (script start order is not guaranteed). Overwriting the
		-- same key with the same function is free, so this is pure insurance.
		if _G.MainMenuManager and _G.MainMenuManager.register then
			pcall(_G.MainMenuManager.register, "More", hideMoreRaw)
		end
	end
end)

-- BADGES. A count, not a dot: "2" says how much is waiting, where a dot only says "something".
--
--   Rewards      -- how many of the two free sources have something (daily crate, daily tasks).
--                   Counting BOTH means claiming one does not hide the other.
--   Pets&Crates  -- unspent crate tokens, i.e. how many crates you can open right now. This is what
--                   keeps crates visible now that they are a page inside the hub instead of a menu row.
local function setBadge(key, n)
	local r = badgeRefs[key]
	if not (r and r.frame and r.frame.Parent) then return end
	r.frame.Visible = n > 0
	if n > 0 then r.label.Text = (n > 99) and "99+" or tostring(n) end
end

task.spawn(function()
	while true do
		local rewards = 0
		if (_G.crateIsClaimable  and _G.crateIsClaimable())  == true then rewards += 1 end
		if (_G.dailyTasksPending and _G.dailyTasksPending()) == true then rewards += 1 end
		setBadge("rewards", rewards)
		setBadge("pets", tonumber(_G.crateTokenBalance) or 0)
		task.wait(1)
	end
end)

print("[RailGuard] ready -- rail locked to 4 buttons, MORE+ polished 2x2 grid")
