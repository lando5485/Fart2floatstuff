--======================================================================
-- MenuBackButton.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- A BACK button on every panel you can reach through MORE+.
--
-- Opening Rebirth / Rewards / Pets / Skin Crates from MORE+ used to be a one-way trip:
-- the X closed the panel and dropped you on the world, so getting to the next item meant
-- re-opening the rail button and the menu again. BACK returns you to where you came from.
--
--   Rebirth / Rewards / Pets / Skin Crates   ->  back to MORE+
--   Daily / Free (opened from Rewards)       ->  back to the Rewards hub
--
-- ===== ONE SCRIPT, NOT FIVE EDITS =====
-- Each of those panels is owned by a different script (RebirthClient, PetFollow,
-- SkinCrateClient, DailyTasks, SocialRewards). Editing all five to add the same button
-- means five chances to break a panel that currently works, and five places to keep in
-- sync. This injects the button from outside instead: it watches for a panel becoming
-- visible, adds a button if one is not already there, and touches nothing else.
--
-- Everything it adds is named "RG_Back", so a re-run finds its own work and never
-- doubles up.
--======================================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player       = Players.LocalPlayer
local PlayerGui    = player:WaitForChild("PlayerGui")

--======================================================================
-- WHERE EACH PANEL GOES BACK TO
--======================================================================
local MORE, REWARDS = "more", "rewards"

local PANELS = {
	RebirthGui       = MORE,
	RewardsHubGui    = MORE,
	WormholeMenu     = MORE,  -- moved into MORE+ when Pets took its rail slot
	-- These two are opened FROM the Rewards hub, so back means the hub, not the menu.
	DailyTasksGui    = REWARDS,
	SocialRewardsGui = REWARDS,
	-- PetInventoryUI is NOT here: Pets opens from the rail now, and rail menus (Shop,
	-- Stomach) have no BACK -- there is nothing to go back TO.
	-- SkinCrateGui is NOT here either: crates are a page of the pet hub, opened from its
	-- tab bar, and the crate panel's own BACK button already returns to the hub.
}

local BACK_W, BACK_H = 92, 36

--======================================================================
local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function stroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = o; return s end

--======================================================================
-- CLOSE THROUGH THE PANEL'S OWN CODE PATH
--
-- ===== THE BUG THIS REPLACES =====
-- The first version closed by hand: ScreenGui.Enabled = false PLUS Visible = false on every
-- wide child, on the theory that clearing both works whichever flag the panel uses.
-- It does close it. It also breaks it permanently, because each panel's toggle only ever
-- flips ONE of those flags:
--
--     RebirthGui / PetInventoryUI / SocialRewardsGui  ->  panel.Visible
--     RewardsHubGui / SkinCrateGui / DailyTasksGui    ->  ScreenGui.Enabled
--
-- Clearing both leaves the OTHER flag off with nothing left to turn it back on. Press BACK
-- once in the Pet Hub and PetInventoryUI.Enabled is false forever -- PetInvToggle then
-- flips panel.Visible on a disabled ScreenGui, so the MORE+ Pets card silently does
-- nothing from that point on. Rebirth and Free Rewards died the same way; the
-- Enabled-driven three came back with their panel frame stranded invisible.
--
-- So: close it the way its own X does. The owner flips its own flag and updates its own
-- state, and nothing is left stranded.
--======================================================================
-- Each returns TRUE only if the owner was actually there to do the closing. A closer that
-- quietly did nothing must fall through to the manual path below, or BACK leaves the panel
-- open on screen.
local CLOSERS = {
	RebirthGui       = function() if _G.toggleRebirth       then _G.toggleRebirth();       return true end end,
	RewardsHubGui    = function() if _G.toggleRewardsHub    then _G.toggleRewardsHub();    return true end end,
	DailyTasksGui    = function() if _G.toggleDailyTasks    then _G.toggleDailyTasks();    return true end end,
	SocialRewardsGui = function() if _G.toggleSocialRewards then _G.toggleSocialRewards(); return true end end,
	WormholeMenu     = function() if _G.toggleWormhole      then _G.toggleWormhole();      return true end end,
}

-- The panel frame, by shape. Declared here because both closeGui and the injector need it.
--
-- STRICTLY a Frame. "Any big GuiObject" matched RebirthGui's drop SHADOW -- an ImageLabel sized
-- fromOffset(720, 546) that sits before `panel` in the child list and is kept hidden forever. That put BACK
-- on the shadow (the Output showed `RebirthGui.ImageLabel.RG_Back`) and made closeGui read the wrong Visible
-- flag. Every panel in this game is a Frame; the decoration around them is not.
local function bigFrame(gui)
	for _, ch in ipairs(gui:GetChildren()) do
		if ch.ClassName == "Frame" and ch.Size.X.Offset >= 400 and ch.Size.Y.Offset >= 200 then return ch end
	end
	for _, ch in ipairs(gui:GetChildren()) do
		if ch.ClassName == "Frame" and ch.Size.X.Scale >= 0.5 then return ch end
	end
	return nil
end

local function closeGui(gui)
	-- Every one of these is a TOGGLE, so only call it while the panel is actually up --
	-- otherwise BACK would re-open the thing it just left.
	local panel = bigFrame(gui)
	local showing = (not gui:IsA("ScreenGui") or gui.Enabled) and (panel == nil or panel.Visible)
	local fn = CLOSERS[gui.Name]
	if fn and showing then
		local ok, closed = pcall(fn)
		if ok and closed then return end
	end

	-- Unknown panel: hide ONE flag, never both. Preferring Enabled leaves a Visible-driven
	-- panel's own state untouched, and vice versa.
	if gui:IsA("ScreenGui") and gui.Enabled and panel and panel.Visible then
		gui.Enabled = false
	elseif panel then
		panel.Visible = false
	end
	if _G.MainMenuManager and _G.MainMenuManager.notifyClosed then
		pcall(_G.MainMenuManager.notifyClosed, gui.Name)
	end
end

local function openMore()
	-- RailGuard owns whether MORE+ is open (see the note in that file). Going through it
	-- keeps ONE owner of that state -- toggling the panel here as well is what made the
	-- rail button need two taps.
	if _G.railGuardOpenMore then pcall(_G.railGuardOpenMore); return true end
	if _G.setMoreOpen then pcall(_G.setMoreOpen, true); return true end
	local gui = PlayerGui:FindFirstChild("MoreMenuGui")
	if not gui then return false end
	gui.Enabled = true
	for _, ch in ipairs(gui:GetChildren()) do
		if ch:IsA("GuiObject") then ch.Visible = true end
	end
	return true
end

local function openRewards()
	if _G.toggleRewardsHub then pcall(_G.toggleRewardsHub); return true end
	return openMore() -- hub not loaded: MORE+ is the next best place to land
end

--======================================================================
-- WHERE TO PUT IT
--
-- Mirrors the close button: same height, same inset, on the LEFT of the header band. If
-- no header is found (a panel that draws its own title), it falls back to the top-left of
-- the panel itself, which is still where a player looks for Back.
--======================================================================
local function findPanelAndHeader(gui)
	-- Same shape test closeGui uses (offset-sized first, then scale-sized panels like the
	-- Shop's 0.9 x 0.85, which have no useful Offset to match on) -- shared so the button
	-- can never land on a different frame than the one BACK closes.
	local panel = bigFrame(gui)
	if not panel then return nil, nil end

	-- STRICTLY a Frame. An earlier version accepted any GuiObject and landed the button on
	-- RebirthGui's 680x68 shadow ImageLabel -- which is not the header, sits at its own
	-- offset, and put BACK in the wrong place entirely.
	-- Position tolerance is 20, not 4: Rebirth's header band sits at y=14 (it is inset inside
	-- the panel). With the tight bound it was missed, BACK fell back to the panel's top-left --
	-- x=14, exactly where that header band starts -- and landed ON TOP of the title. Finding
	-- the header instead puts the button inside it and clearRoom shifts the title over.
	local header
	for _, ch in ipairs(panel:GetChildren()) do
		if ch.ClassName == "Frame" and ch.Size.X.Scale >= 1
			and ch.Size.Y.Offset >= 44 and ch.Size.Y.Offset <= 90
			and ch.Position.Y.Offset <= 20 then
			header = ch; break
		end
	end
	return panel, header
end

-- MAKE ROOM. Every one of these panels puts its title at the far left, which is exactly
-- where BACK goes -- so the two overlapped on all six. Anything left-anchored that would
-- sit under the button is pushed right and narrowed by the same amount, so it keeps its
-- right edge and simply starts after the button.
--
-- Only LEFT-anchored children move: the close X is anchored to the right (X.Scale == 1)
-- and must not be touched.
local function clearRoom(host, btn)
	local rightEdge = btn.Position.X.Offset + BACK_W + 12
	for _, ch in ipairs(host:GetChildren()) do
		if ch ~= btn and (ch:IsA("TextLabel") or ch:IsA("TextButton") or ch:IsA("ImageLabel")) then
			local p, s = ch.Position, ch.Size
			local isLeft = (p.X.Scale == 0 and math.abs(p.Y.Scale) < 0.01)
			if isLeft and p.X.Offset < rightEdge and s.X.Offset > 60 then
				local shift = rightEdge - p.X.Offset
				ch.Position = UDim2.new(0, rightEdge, p.Y.Scale, p.Y.Offset)
				if s.X.Scale == 0 then
					ch.Size = UDim2.new(0, math.max(60, s.X.Offset - shift), s.Y.Scale, s.Y.Offset)
				end
			end
		end
	end
end

-- FIND THE CLOSE X. The small square button reading "X" nearest the top of the panel. Size
-- capped so a wide button that merely contains an X in its label can't be mistaken for it.
local function findCloseX(panel)
	local best
	for _, ch in ipairs(panel:GetDescendants()) do
		if ch:IsA("TextButton") then
			local t = ch.Text
			if (t == "X" or t == "x" or t == "\xE2\x9C\x95" or t == "\xE2\x9C\x96")
				and ch.AbsoluteSize.X > 0 and ch.AbsoluteSize.X <= 60
				and (not best or ch.AbsolutePosition.Y < best.AbsolutePosition.Y)
			then
				best = ch
			end
		end
	end
	return best
end

local function inject(gui, target)
	local panel, header = findPanelAndHeader(gui)
	if not panel then return false end
	local host = header or panel
	if panel:FindFirstChild("RG_Back", true) then return true end -- already done

	-- SAME BUTTON AS THE SEASONAL PETS HUB'S. That one is warm brown with a cream glyph and no
	-- outline; this was navy-grey with a white stroke, which read as a dead grey square sitting
	-- next to a bright red X. One back button, one look, everywhere.
	local b = Instance.new("TextButton")
	b.Name = "RG_Back"
	b.BackgroundColor3 = Color3.fromRGB(120, 78, 40)
	b.Font = Enum.Font.FredokaOne
	b.TextColor3 = Color3.fromRGB(255, 244, 214)
	b.AutoButtonColor = false
	b.ZIndex = 50                            -- above headers, gloss and dividers

	-- ===== IT SITS NEXT TO THE X, NOT ON TOP OF THE TITLE =====
	-- This used to park BACK at the panel's top-LEFT and then shove the title label to the
	-- right to make room (clearRoom, below). On every panel whose title starts near the left
	-- edge that meant the button landed ON the words -- and on the ones where clearRoom did
	-- fire, it left the title visibly off-centre from its own header.
	--
	-- The top-right already has a button and a convention: the close X. BACK is mirrored off
	-- it -- same size, same anchor, same corner radius, same baseline -- and placed one gap to
	-- its left, so the two read as a matched pair and nothing else on the panel has to move.
	--
	-- The FILL stays navy rather than the X's red. Two red buttons side by side both say
	-- "leave" and you could not tell which one goes back: matched in shape, distinct in colour.
	local x = findCloseX(panel)
	if x then
		-- The gap is measured off the X's RENDERED width, and 14 rather than 8: a close button with
		-- its own UIStroke or padding draws wider than its Size says, which is what let the two
		-- touch. A couple of pixels of daylight costs nothing and cannot overlap.
		local w = (x.AbsoluteSize.X > 0) and x.AbsoluteSize.X or BACK_H
		local radius = 10
		local xc = x:FindFirstChildOfClass("UICorner")
		if xc then radius = xc.CornerRadius.Offset end
		b.Size = x.Size
		b.AnchorPoint = x.AnchorPoint
		b.Position = UDim2.new(x.Position.X.Scale, x.Position.X.Offset - w - 14,
			x.Position.Y.Scale, x.Position.Y.Offset)
		b.Text = "\xE2\x97\x80"              -- ◀, the same glyph the Seasonal Pets back button uses
		b.TextSize = 20
		b.Parent = x.Parent                  -- the X's own header, whatever that turned out to be
		corner(b, radius)                    -- no stroke: the seasonal one has none either
	else
		-- No close button found -- fall back to the old left-hand placement, title shove and all.
		b.Size = UDim2.new(0, BACK_W, 0, BACK_H)
		b.AnchorPoint = Vector2.new(0, 0.5)
		b.Position = header
			and UDim2.new(0, 14, 0, math.floor(header.Size.Y.Offset / 2))
			or  UDim2.new(0, 14, 0, 22)
		b.Text = "\xE2\x9D\xAE  BACK"        -- ❮ BACK
		b.TextSize = 15
		b.Parent = host
		corner(b, 10); stroke(b, Color3.fromRGB(255, 255, 255), 1.5)
		clearRoom(host, b)
	end

	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = b
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	b.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.05 }):Play()
		TweenService:Create(b, ti, { BackgroundColor3 = Color3.fromRGB(152, 102, 56) }):Play()  -- lit brown
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1 }):Play()
		TweenService:Create(b, ti, { BackgroundColor3 = Color3.fromRGB(120, 78, 40) }):Play()  -- back to rest
	end)

	-- DEBOUNCED: closeGui goes through the panel's own TOGGLE, so a double-tap would close
	-- and immediately re-open the panel the player is trying to leave.
	local lastBack = 0
	b.MouseButton1Click:Connect(function()
		local now = os.clock()
		if now - lastBack < 0.35 then return end
		lastBack = now
		if _G.playUIClick then pcall(_G.playUIClick) end
		closeGui(gui)
		-- Deferred: the panel we just closed may notify the menu manager, which can close
		-- other menus in the same frame -- including the one we are about to open.
		task.defer(function()
			if target == REWARDS then openRewards() else openMore() end
		end)
	end)
	return true
end

--======================================================================
-- WATCH
--
-- A panel is often built after this script runs, and several are rebuilt on respawn, so
-- this watches for them rather than looking once. Injection is also retried whenever a
-- panel is shown: a script that rebuilds its own header would drop our button, and the
-- next open puts it straight back.
--======================================================================
local hooked = {}

local function watch(gui)
	local target = PANELS[gui.Name]
	if not target or hooked[gui] then return end
	hooked[gui] = true

	local function tryInject()
		task.defer(function() pcall(inject, gui, target) end)
	end

	if gui:IsA("ScreenGui") then
		gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if gui.Enabled then tryInject() end
		end)
		if gui.Enabled then tryInject() end
	end
	-- Enabled-driven panels are the common case, but a couple toggle a frame's Visible
	-- instead, so watch the panel frame too.
	task.delay(0.5, function()
		local panel = select(1, findPanelAndHeader(gui))
		if panel then
			panel:GetPropertyChangedSignal("Visible"):Connect(function()
				if panel.Visible then tryInject() end
			end)
			if panel.Visible then tryInject() end
		end
	end)
	tryInject()
end

for _, gui in ipairs(PlayerGui:GetChildren()) do watch(gui) end
PlayerGui.ChildAdded:Connect(function(gui) task.defer(watch, gui) end)

-- Catch-all sweep: some panels finish building several seconds in.
for _, t in ipairs({ 2, 5, 10, 20 }) do
	task.delay(t, function()
		for _, gui in ipairs(PlayerGui:GetChildren()) do
			local target = PANELS[gui.Name]
			if target and gui:IsA("ScreenGui") and gui.Enabled then pcall(inject, gui, target) end
		end
	end)
end

print("[MenuBack] ready -- BACK on Rebirth / Rewards / Pets / Skin Crates -> MORE+, Daily / Free -> Rewards")
