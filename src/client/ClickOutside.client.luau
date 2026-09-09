--!nonstrict
-- =================================================================================================
-- CLICK OUTSIDE TO CLOSE -- one helper, every panel, and never over a HUD button.
-- =================================================================================================
-- WHAT THIS REVERSES, ON PURPOSE.
-- Until now the house rule was "panels close on their X button and nothing else", because an earlier
-- build closed menus on any backdrop click and the UI felt like it was shutting at random -- the
-- worst case being a click that fell THROUGH a panel onto a HUD button behind it, which both pressed
-- the button and slammed the menu. Every panel had its `backdrop -> close` handler deleted and a NOTE
-- left in its place.
--
-- This file brings click-outside back deliberately, and fixes the thing that made it bad the first
-- time: THE CATCHER NEVER COVERS THE HUD. It is inset away from the side rail, the right-hand button
-- panel, the currency capsule and the bottom stack, so a click on any of those reaches the button it
-- was aimed at and does NOT close the panel. Only genuinely empty screen closes anything.
--
-- =================================================================================================
-- HOW IT WORKS (rebuilt 2026-09-06 -- the first build only ever worked on the Seasonal Pets panel)
-- =================================================================================================
-- An ADOPTER, like MenuSkin: the panels are owned by ~20 different scripts, two of which (CoreClient
-- at 199/200 and PetFollow at 195/200) cannot take a single further local without silently failing to
-- compile. So nothing is edited into them. This watches PlayerGui, and when a known panel is open it
-- puts a SHIELD around it and takes it away again on close.
--
-- WHY THE FIRST BUILD FAILED EVERYWHERE BUT ONE PANEL. It parented one invisible catcher BEHIND the
-- panel and called "the panel" the biggest visible child of the ScreenGui. Almost every hub in this
-- game (Pets, Shop, Daily Tasks, Wormhole, Settings, Rewards, Skin Crates, More+ ...) keeps an
-- invisible FULL-SCREEN backdrop as a sibling or parent of the real card. Two things then went wrong at
-- once: the backdrop was picked as "the panel", so every click on Earth measured as INSIDE it and the
-- guard refused to close; and the catcher sat under that backdrop in Z-order, so it never received a
-- click anyway. LockerGui (Seasonal Pets) is the one hub with no backdrop -- the only place it worked.
--
-- THE SHIELD. Four transparent strips -- above, below, left and right of the card -- in their own
-- ScreenGui one DisplayOrder ABOVE the panel's. They cover the empty screen and nothing else: not the
-- card (they stop at its edges), not the HUD (they are inset by the live HUD margins). Being on top,
-- no backdrop can shadow them; being strips, no Z trick is needed to keep them off the card. And the
-- card is found by looking THROUGH full-screen backdrops for the biggest thing that is not one.
--
-- CLOSING goes through MainMenuManager wherever possible -- it owns `current` and a full-hide fn per
-- menu, so a panel closed from here goes through exactly the same path as its own X button (HUD
-- restored, siblings notified). The direct hide is only a fallback for panels it does not know.
--
-- =================================================================================================
-- TURNING IT OFF
-- =================================================================================================
-- ENABLED = false below restores the old X-button-only behaviour game-wide, instantly.
-- To exempt ONE panel, add its ScreenGui name to NEVER (e.g. a crate reveal you would hate to lose to
-- a stray tap). To protect more HUD, add to HUD_GUIS.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local ENABLED = true

--======================================================================
-- WHICH SCREENGUIS ARE PANELS
--======================================================================
-- An explicit list, not a heuristic. A size/shape guess would eventually adopt a banner, a toast or a
-- full-screen effect sheet and start closing things nobody opened -- and a mis-fire here is invisible
-- until a player loses a menu mid-flight. Adding a new panel is one line.
local PANELS = {
	StomachShopGui = true, FoodShopGui = true, PremiumShopGui = true,
	PetInventoryUI = true, SkinCrateGui = true, SkinCrateRevealGui = true,
	PetLevelPickerGui = true, PetHouseGui = true, LockerGui = true,
	DailyStreakGui = true, RewardsHubGui = true, DailyTasksGui = true,
	SocialRewardsGui = true, SeasonPassGui = true, RebirthGui = true,
	WormholeMenu = true, GiftGui = true, CodesGui = true, GroupPerkGui = true,
	SettingsPanelGui = true, MoreMenuGui = true, GardenerChatGui = true,
	TestPetPreviewGui = true,
	-- Added 2026-09-06 after an audit found five real panels that were never on this list, so an outside
	-- click did nothing on them. GnomeHomeMenuGui was the worst of the five: it rolled its OWN full-screen
	-- catcher, which both dimmed the screen and covered the HUD -- exactly the fall-through this file exists
	-- to prevent. That catcher is gone; it is a normal panel now.
	GnomeHomeMenuGui = true, GardenDonationGui = true, GardenRewardGui = true,
	SecretTraderGui = true, FarmerTutorialGui = true, TrailSelectorGui = true,
}

-- Never armed, whatever else says. Kept as its own list so an exemption is a decision someone can
-- read, rather than a name quietly missing from PANELS above.
local NEVER = {}

--======================================================================
-- WHICH SCREENGUIS ARE HUD (the shield stays off these)
--======================================================================
-- BottomStackGui is listed even though MainMenuManager.setHud(false) hides it for registered menus --
-- panels that are NOT registered menus leave it up, and that is exactly the fall-through case that
-- caused the original complaint. The four at the end are the floating controls that live at a screen
-- edge while a menu is open (trick button, quest arrow, hero banner, event chip): the shield is on top
-- of everything now, so anything NOT listed here is unreachable for as long as a panel is up.
local HUD_GUIS = {
	BottomStackGui = true, SidebarGui = true, RightPanelGui = true,
	CoinGui = true, GasMeterGui = true, NavGui = true, CampfireHud = true,
	FoodRealmHud = true, ReturnIslandGui = true,
	PetTrickGui = true, QuestTrackerHud = true, NotifyHero = true, EventChipGui = true,
}

local SHIELD_PREFIX = "ClickOutsideShield_"

--======================================================================
-- COORDINATES
--======================================================================
-- Everything below is measured in AbsolutePosition space, and the screen's own rectangle in that space is
-- READ, not assumed: each shield carries a full-size inert frame (`Origin`) whose AbsolutePosition and
-- AbsoluteSize are the screen's top-left and size. That sidesteps the GUI-inset question (does
-- AbsolutePosition include the topbar or not) entirely -- whichever way the engine answers it, the frame
-- answers the same way, and the arithmetic stays right.
local function screenRect(shield)
	local o = shield and shield:FindFirstChild("Origin")
	if o then return o.AbsolutePosition, o.AbsoluteSize end
	local cam = workspace.CurrentCamera
	return Vector2.zero, (cam and cam.ViewportSize) or Vector2.new(1280, 720)
end

--======================================================================
-- THE HUD-SAFE MARGINS
--======================================================================
-- The shield is the screen inset away from whatever HUD is currently on it. Margins are measured from
-- the LIVE AbsolutePosition/AbsoluteSize of the visible HUD, not hardcoded, so a phone's UIScale and
-- the right panel appearing mid-session are both handled without a breakpoint.
--
-- Only edge-hugging HUD widens a margin: something floating in the middle of the screen would
-- otherwise eat the entire shield. `edge` decides which side each element belongs to by asking which
-- screen edge it is nearest. Big transparent CONTAINERS (a full-size StackBox, a wrapper frame) are
-- skipped -- they touch every edge at once and would otherwise claim the whole screen as "HUD".
local function hudMargins(O, S)
	local left, right, top, bottom = 0, 0, 0, 0
	for _, g in ipairs(PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and HUD_GUIS[g.Name] then
			for _, o in ipairs(g:GetDescendants()) do
				if o:IsA("GuiObject") and o.Visible and o.AbsoluteSize.X > 8 and o.AbsoluteSize.Y > 8 then
					local p, sz = o.AbsolutePosition, o.AbsoluteSize
					local container = sz.X >= S.X * 0.5 and sz.Y >= S.Y * 0.5
					local drawn = o.BackgroundTransparency < 0.99
						or o:IsA("TextLabel") or o:IsA("TextButton")
						or o:IsA("ImageLabel") or o:IsA("ImageButton")
					if not container and drawn then
						local l, r = p.X - O.X, p.X + sz.X - O.X
						local t, b = p.Y - O.Y, p.Y + sz.Y - O.Y
						-- distance from this element to each screen edge; the smallest wins
						local dl, dr, dt, db = l, S.X - r, t, S.Y - b
						local m = math.min(dl, dr, dt, db)
						if m == dl then left   = math.max(left,   r)
						elseif m == dr then right  = math.max(right,  S.X - l)
						elseif m == dt then top    = math.max(top,    b)
						else                 bottom = math.max(bottom, S.Y - t) end
					end
				end
			end
		end
	end
	return left, right, top, bottom
end

--======================================================================
-- FINDING THE CARD
--======================================================================
-- A backdrop is anything authored to fill the screen: pure-scale (1,1) size, or measuring at least 95% of
-- the screen both ways. 95% and not less, because in Studio's 800x600 emulator a 700x520 card is 87% of
-- the screen and must still count as a card.
local function isBackdrop(o, S)
	local sz = o.Size
	if sz.X.Scale >= 0.99 and sz.Y.Scale >= 0.99 and sz.X.Offset <= 0 and sz.Y.Offset <= 0 then return true end
	local a = o.AbsoluteSize
	return a.X >= S.X * 0.95 and a.Y >= S.Y * 0.95
end

-- The card the player is looking at: the biggest visible thing in the ScreenGui that is NOT a backdrop.
-- Backdrops are looked THROUGH (the card is usually inside one); a card's own children are never
-- visited, so a big overlay inside it cannot outrank it.
local function panelOf(gui, S)
	local best, bestArea = nil, 0
	local function visit(parent)
		for _, o in ipairs(parent:GetChildren()) do
			if o:IsA("GuiObject") and o.Visible then
				if isBackdrop(o, S) then
					visit(o)
				else
					local a = o.AbsoluteSize.X * o.AbsoluteSize.Y
					if a > bestArea then best, bestArea = o, a end
				end
			end
		end
	end
	visit(gui)
	return best
end

--======================================================================
-- TABS / OVERLAYS INSIDE A HUB
--======================================================================
-- A hub is not one surface. PetInventoryUI opens a TRADE overlay over itself; the Premium shop opens a
-- CURRENCY overlay; the trade overlay opens an OFFER PICKER over THAT. Before this, an outside click on
-- any of them closed the whole hub and threw you back to the world -- or, where the hub was not listed,
-- did nothing at all. Both are wrong: the click should peel ONE layer, the way it does everywhere else.
--
-- So the click now closes the deepest SHOWING overlay first and leaves the hub open; only when nothing is
-- layered on top does it close the hub itself. Second click backs out of the hub, same as before.
-- "Showing" means visible all the way up to the card: the trade overlay keeps its FRIENDS view flagged
-- Visible while the overlay itself is hidden, and hiding that by mistake would leave the tab blank the
-- next time Trade opens.
--
-- QUESTS ARE DELIBERATELY EXCLUDED. The user asked for this on the hubs and tabs and explicitly not on
-- quests, and quest views carry in-progress state (a tracked quest, a claim mid-flight) that a stray click
-- must not discard. QuestsOverlay is named in NEVER_OVERLAY rather than merely left out of OVERLAYS, so
-- the exemption is a decision someone can read instead of an absence they have to infer.
local OVERLAYS = {
	TradeOverlay = true, OfferPicker = true, CurrencyOverlay = true,
	OfflineReqView = true, SkinsList = false,
}
local NEVER_OVERLAY = { QuestsOverlay = true, QuestTracker = true, Tracker = true }

local function shownWithin(d, root)
	local n = d
	while n and n ~= root do
		if not (n:IsA("GuiObject") and n.Visible) then return false end
		n = n.Parent
	end
	return n == root
end

-- The deepest showing overlay under `panel`, or nil. Depth-ordered so OfferPicker (which sits on top of
-- TradeOverlay) is peeled before the overlay that opened it.
local function topOverlay(panel)
	if not panel then return nil end
	local best, bestDepth = nil, -1
	for _, d in ipairs(panel:GetDescendants()) do
		if d:IsA("GuiObject") and OVERLAYS[d.Name] == true and not NEVER_OVERLAY[d.Name] and shownWithin(d, panel) then
			local depth, node = 0, d
			while node and node ~= panel do depth = depth + 1; node = node.Parent end
			if depth > bestDepth then best, bestDepth = d, depth end
		end
	end
	return best
end

local function closeVia(gui, panel)
	-- ONE LAYER AT A TIME: peel the tab before the hub.
	local ov = topOverlay(panel)
	if ov then ov.Visible = false; return end
	local mgr = _G.MainMenuManager
	-- PREFERRED: the menu's own full-hide function. Closing a panel by poking its Visible flag skips
	-- whatever its owner does on close (restoring the bottom HUD, clearing `current`, releasing the
	-- mouse), and those omissions are how a panel ends up shut with the HUD still hidden.
	if mgr and mgr.current and mgr.hiders and mgr.hiders[mgr.current] then
		local ok = pcall(mgr.hiders[mgr.current])
		if ok then
			pcall(function() mgr.notifyClosed(mgr.current) end)
			return
		end
	end
	-- FALLBACK: no hider for whatever the manager thinks is open (or it errored), so close the panel we were
	-- actually pointed at. This is the path that used to strand the bottom HUD: the panel goes away, but
	-- `current` is left naming a menu, and CoreClient's HUD authority keeps the gut pill, gas meter and fart
	-- button switched off until the player happens to open and close something else. Tell the manager too --
	-- there is no menu on screen any more, whatever it still believes.
	--
	-- CoreClient re-checks this for itself (it looks for a real card on screen before trusting `current`), so
	-- a miss here is no longer fatal. It is still fixed at the source: the closer knows it closed something.
	if panel then panel.Visible = false end
	if gui:IsA("ScreenGui") then gui.Enabled = false end
	if mgr and mgr.current then pcall(function() mgr.notifyClosed(mgr.current) end) end
end

--======================================================================
-- NOTHING BUT EMPTY SCREEN CLOSES ANYTHING
--======================================================================
-- The strips are already inset away from the HUD, and that handles the four edges. It cannot handle two
-- other cases, and both of them lose the player a menu they were using:
--
--   * HUD THAT IS NOT AGAINST AN EDGE. hudMargins only widens a margin from the screen side an element is
--     NEAREST, because an element in the middle of the screen would otherwise claim the whole shield. So a
--     control sitting in open space -- the TRICK button, a roasting button, a quest arrow -- is inside the
--     shield, and a press on it read as "empty screen".
--   * A PANEL'S OWN FURNITURE OUTSIDE THE CARD. The card is the biggest non-backdrop thing in the GUI, and
--     several hubs hang tabs, a BACK button or a badge just outside its edges. Pressing a TAB then closed
--     the hub -- which is the worst version of this bug, because tabs are what you press most.
--
-- So the geometry decides where the shield IS, and this decides what a press on it MEANS. A click closes
-- only when there is genuinely nothing under it: no HUD, no button, no label, no panel furniture. The one
-- thing deliberately looked through is a full-screen BACKDROP -- that is what "outside the card" is made
-- of, and treating it as something would switch click-outside off entirely.
--
-- Its own rectangle test rather than PlayerGui:GetGuiObjectsAtPosition: the coordinates handed in here are
-- already in AbsolutePosition space (the Origin frame did that conversion), every rectangle it compares
-- against is read the same way, and that keeps one coordinate system for the whole file instead of two
-- with an inset question between them.
local function drawnControl(o, S)
	if not (o:IsA("GuiObject") and o.Visible) then return false end
	if o.AbsoluteSize.X <= 8 or o.AbsoluteSize.Y <= 8 then return false end
	if isBackdrop(o, S) then return false end          -- the empty screen itself
	return o.BackgroundTransparency < 0.99
		or o:IsA("GuiButton") or o:IsA("TextLabel") or o:IsA("ImageLabel")
end

local function somethingAt(mx, my, S)
	for _, g in ipairs(PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g.Name:sub(1, #SHIELD_PREFIX) ~= SHIELD_PREFIX then
			for _, o in ipairs(g:GetDescendants()) do
				if drawnControl(o, S) then
					local p, sz = o.AbsolutePosition, o.AbsoluteSize
					if mx >= p.X and mx <= p.X + sz.X and my >= p.Y and my <= p.Y + sz.Y
						and shownWithin(o, g) then
						return o
					end
				end
			end
		end
	end
	return nil
end

--======================================================================
-- ARM / DISARM
--======================================================================
local armed = {}   -- [ScreenGui] = { shield = ScreenGui, panel = GuiObject, strips = {TextButton x4}, margins = {l,r,t,b} }

local function strip(name, shield)
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundTransparency = 1     -- NO DIM ANYWHERE. Invisible, always.
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Active = true                  -- swallows the click so it cannot also hit what is behind
	b:SetAttribute("NoHaptic", true)         -- UiHaptics: tapping empty screen must not buzz
	b:SetAttribute("NoBackdropGuard", true)  -- MenuBackdropGuard: this input sink is deliberate
	b.Parent = shield
	return b
end

local function arm(gui)
	if armed[gui] then return end

	local shield = Instance.new("ScreenGui")
	shield.Name = SHIELD_PREFIX .. gui.Name
	shield.ResetOnSpawn = false
	shield.IgnoreGuiInset = true
	-- One above the panel's own ScreenGui: above its backdrop, still below anything that deliberately
	-- outranks the panel (a cutscene cover, a crate reveal, the transition cards).
	shield.DisplayOrder = (gui.DisplayOrder or 0) + 1

	-- The calibration frame (see COORDINATES). Not Active, so it sinks nothing.
	local origin = Instance.new("Frame")
	origin.Name = "Origin"
	origin.BackgroundTransparency = 1
	origin.Active = false
	origin.Size = UDim2.fromScale(1, 1)
	origin.Parent = shield

	local a = {
		shield = shield, panel = nil,
		strips = { strip("Top", shield), strip("Bottom", shield), strip("Left", shield), strip("Right", shield) },
		margins = { 0, 0, 0, 0 },
	}
	for _, s in ipairs(a.strips) do
		s.MouseButton1Click:Connect(function()
			local panel = a.panel
			if not (ENABLED and panel and panel.Parent) then return end
			-- GEOMETRIC GUARD, on top of the strip layout. Belt and braces: a card mid-tween can outrun a
			-- strip by a frame, and this refuses to close on an inside click rather than let the player lose
			-- a menu they were using. The mouse is read in screen space and shifted into AbsolutePosition
			-- space by the same Origin frame the strips are laid out from.
			local O, S = screenRect(shield)
			local m = UserInputService:GetMouseLocation()
			local mx, my = m.X + O.X, m.Y + O.Y
			local p, sz = panel.AbsolutePosition, panel.AbsoluteSize
			if mx >= p.X and mx <= p.X + sz.X and my >= p.Y and my <= p.Y + sz.Y then return end

			-- ...and refuse on anything else that is actually there (see the block above this function).
			local hit = somethingAt(mx, my, S)
			if hit then
				-- Named, because "my menu closed when I pressed X" is otherwise unreproducible from a
				-- description, and this line says exactly which control the press landed on.
				print("[ClickOutside] press landed on '" .. hit:GetFullName() .. "' -- not empty screen, "
					.. gui.Name .. " stays open")
				return
			end
			if _G.playUIClick then pcall(_G.playUIClick) end
			closeVia(gui, panel)
		end)
	end
	shield.Parent = PlayerGui
	armed[gui] = a
end

local function disarm(gui)
	local a = armed[gui]
	if not a then return end
	armed[gui] = nil
	if a.shield then a.shield:Destroy() end
end

-- Lay the four strips around the card. Runs every frame while anything is armed: it is four rectangles,
-- and a card that is still sliding open must not be left with a stale strip across it.
local function layout(a)
	local panel = a.panel
	if not (panel and panel.Parent) then
		for _, s in ipairs(a.strips) do s.Visible = false end
		return
	end
	local O, S = screenRect(a.shield)
	local l, r, t, b = a.margins[1], a.margins[2], a.margins[3], a.margins[4]
	-- the HUD-safe rectangle, in AbsolutePosition space
	local x0, x1 = O.X + l, O.X + S.X - r
	local y0, y1 = O.Y + t, O.Y + S.Y - b
	-- the card's rectangle
	local p, sz = panel.AbsolutePosition, panel.AbsoluteSize
	local px0, px1, py0, py1 = p.X, p.X + sz.X, p.Y, p.Y + sz.Y

	local function put(s, ax, ay, bx, by)
		local w, h = bx - ax, by - ay
		if w <= 0 or h <= 0 then s.Visible = false; return end
		s.Visible = true
		s.Position = UDim2.fromOffset(ax - O.X, ay - O.Y)
		s.Size = UDim2.fromOffset(w, h)
	end
	local cy0, cy1 = math.max(py0, y0), math.min(py1, y1)
	put(a.strips[1], x0, y0, x1, math.min(py0, y1))   -- above the card
	put(a.strips[2], x0, math.max(py1, y0), x1, y1)   -- below the card
	put(a.strips[3], x0, cy0, math.min(px0, x1), cy1) -- left of the card
	put(a.strips[4], math.max(px1, x0), cy0, x1, cy1) -- right of the card
end

--======================================================================
-- THE SWEEP
--======================================================================
-- Polled rather than event-driven: these panels are shown in every possible way (Enabled, Visible on
-- the ScreenGui's child, a tween, a rebuild), so there is no one signal to listen to. 8/sec is far
-- below anything a player can perceive as lag on a menu that is already open.
local function sweep()
	if not ENABLED then return end
	local anyShield
	for _, a in pairs(armed) do anyShield = a.shield; break end
	local O, S = screenRect(anyShield)
	local l, r, t, b = hudMargins(O, S)

	for _, gui in ipairs(PlayerGui:GetChildren()) do
		if gui:IsA("ScreenGui") and PANELS[gui.Name] and not NEVER[gui.Name] then
			local panel = gui.Enabled and panelOf(gui, S) or nil
			if panel then
				arm(gui)
				local a = armed[gui]
				-- Re-measured every sweep: the HUD comes and goes (setHud, the right panel, the rail)
				-- while a panel is open, and a shield sized once at open time would keep a stale hole in
				-- it -- or worse, keep covering a button that just appeared. The card can be rebuilt
				-- underneath us too; follow it rather than holding a dead one.
				a.panel = panel
				a.margins[1], a.margins[2], a.margins[3], a.margins[4] = l, r, t, b
				a.shield.DisplayOrder = (gui.DisplayOrder or 0) + 1
			else
				disarm(gui)
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.125)
		pcall(sweep)
	end
end)

RunService.RenderStepped:Connect(function()
	if not ENABLED then return end
	for _, a in pairs(armed) do pcall(layout, a) end
end)

-- Public switch, so a cutscene or a minigame can suspend this for its duration without editing here.
_G.clickOutsideSetEnabled = function(on)
	ENABLED = on and true or false
	if not ENABLED then
		for gui in pairs(armed) do disarm(gui) end
	end
end

print("[ClickOutside] ready -- click-outside closes " .. (function()
	local n = 0; for _ in pairs(PANELS) do n = n + 1 end; return n
end)() .. " panels. The shield is four invisible strips AROUND the card, on top of any backdrop, and is "
	.. "INSET away from the HUD (rail, right panel, currency capsule, bottom stack, banners), so a click on a "
	.. "HUD button presses it instead of closing the panel. _G.clickOutsideSetEnabled(false) turns it all off.")
