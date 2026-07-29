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
	PetInventoryUI   = MORE,
	SkinCrateGui     = MORE,
	-- These two are opened FROM the Rewards hub, so back means the hub, not the menu.
	DailyTasksGui    = REWARDS,
	SocialRewardsGui = REWARDS,
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
	SkinCrateGui     = function() if _G.toggleSkinCrates    then _G.toggleSkinCrates();    return true end end,
	DailyTasksGui    = function() if _G.toggleDailyTasks    then _G.toggleDailyTasks();    return true end end,
	SocialRewardsGui = function() if _G.toggleSocialRewards then _G.toggleSocialRewards(); return true end end,
	PetInventoryUI   = function()
		local ev = PlayerGui:FindFirstChild("PetInvToggle")
		if not ev then return false end
		ev:Fire()
		return true
	end,
}

-- The panel frame, by shape. Declared here because both closeGui and the injector need it.
local function bigFrame(gui)
	for _, ch in ipairs(gui:GetChildren()) do
		if ch:IsA("GuiObject") and ch.Size.X.Offset >= 400 and ch.Size.Y.Offset >= 200 then return ch end
	end
	for _, ch in ipairs(gui:GetChildren()) do
		if ch:IsA("Frame") and ch.Size.X.Scale >= 0.5 then return ch end
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
	local header
	for _, ch in ipairs(panel:GetChildren()) do
		if ch.ClassName == "Frame" and ch.Size.X.Scale >= 1
			and ch.Size.Y.Offset >= 44 and ch.Size.Y.Offset <= 90
			and ch.Position.Y.Offset <= 4 then
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

local function inject(gui, target)
	local panel, header = findPanelAndHeader(gui)
	if not panel then return false end
	local host = header or panel
	if host:FindFirstChild("RG_Back") then return true end -- already done

	local b = Instance.new("TextButton")
	b.Name = "RG_Back"
	b.Size = UDim2.new(0, BACK_W, 0, BACK_H)
	b.AnchorPoint = Vector2.new(0, 0.5)
	-- Vertically centred in the header so it lines up with the title, not the band's edge.
	b.Position = header
		and UDim2.new(0, 14, 0, math.floor(header.Size.Y.Offset / 2))
		or  UDim2.new(0, 14, 0, 22)
	b.BackgroundColor3 = Color3.fromRGB(58, 62, 92)
	b.Text = "\xE2\x9D\xAE  BACK"          -- ❮ BACK
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.AutoButtonColor = false
	b.ZIndex = 50                            -- above headers, gloss and dividers
	b.Parent = host
	corner(b, 10); stroke(b, Color3.fromRGB(255, 255, 255), 1.5)
	clearRoom(host, b)

	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = b
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	b.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.05 }):Play()
		TweenService:Create(b, ti, { BackgroundColor3 = Color3.fromRGB(78, 84, 122) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1 }):Play()
		TweenService:Create(b, ti, { BackgroundColor3 = Color3.fromRGB(58, 62, 92) }):Play()
	end)

	b.MouseButton1Click:Connect(function()
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
