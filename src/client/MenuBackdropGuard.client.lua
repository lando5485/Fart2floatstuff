--!nonstrict
-- MenuBackdropGuard (StarterPlayer/StarterPlayerScripts/MenuBackdropGuard)
-- ============================================================================================================
-- FIXES: "I join, I can walk, but I can't turn the camera and none of the buttons work."
--
-- CAUSE: a FULL-SCREEN, input-sinking backdrop left VISIBLE over the world. Menu panels (Season Pass, Free
-- Rewards, Rebirth, Wormhole, Pet Wheel, the Group window, More+) each put a full-screen TextButton behind
-- themselves to catch stray taps. That is correct while the menu is OPEN. The problem is STALE DUPLICATE copies
-- of those menu scripts baked into the place file -- the Output prints the same "client ready" line twice from
-- two different line numbers (RebirthClient, WormholeClient, DailyTasks, RewardsClient, GardenDonationClient,
-- Campfire, NotifyCenter, TitleTags... all doubled). The duplicate builds a SECOND copy of the GUI and leaves
-- its backdrop up with no panel behind it. That button then swallows every click AND every right-drag meant for
-- the camera, so the game looks frozen except for walking.
--
-- WHAT CHANGED: the old version only treated a backdrop as orphaned if it was essentially INVISIBLE
-- (BackgroundTransparency >= 0.99). The two blockers actually seen in the wild are a 0.45 dim (WormholeMenu's
-- Backdrop) and a 0.5 dim (GroupPerkGui's catcher) -- both sailed straight past that test. Transparency is the
-- wrong question. The right question is: is this thing FULL-SCREEN, does it SINK INPUT, and is there any actual
-- panel open in the same ScreenGui? If there is no panel, the backdrop has nothing to be behind, so it is an
-- orphan whatever its transparency.
--
-- It also now checks EFFECTIVE visibility (every ancestor Visible + the ScreenGui Enabled), because a backdrop
-- inside a disabled ScreenGui renders nothing and must never be touched -- that is every correctly-closed menu
-- in the game.
--
-- It PRINTS what it hides. If this fires repeatedly, the name it prints is the stale duplicate to delete in
-- Studio -- that is the real fix; this guard only keeps the game playable until then.
-- ============================================================================================================

local Players     = game:GetService("Players")
local UserInput   = game:GetService("UserInputService")
local GuiService  = game:GetService("GuiService")

local plr = Players.LocalPlayer
local pg  = plr:WaitForChild("PlayerGui")

local FULLSCREEN_FRAC = 0.9    -- covers >=90% of the viewport in BOTH dims = a full-screen backdrop
local PANEL_MIN_PX    = 40     -- anything smaller than this isn't a panel, it's decoration
local PANEL_OPAQUE    = 0.95   -- a real panel has a visible fill

local function viewport()
	local cam = workspace.CurrentCamera
	return (cam and cam.ViewportSize) or Vector2.new(1, 1)
end

-- Is this element actually being RENDERED? Visible is per-object, so a visible child inside a hidden parent (or
-- a disabled ScreenGui) still reports Visible = true while drawing nothing and catching nothing.
local function effectivelyVisible(d)
	local node = d
	while node and not node:IsA("ScreenGui") do
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end
	return (node ~= nil) and node.Enabled
end

-- A full-screen element that SINKS INPUT (a GuiButton, or an Active frame) -- i.e. a click-catcher backdrop.
-- Transparency is deliberately NOT considered: a 0.45 dim blocks input exactly as hard as an invisible one.
local function isBackdrop(d, vp)
	if not d:IsA("GuiObject") then return false end
	if not (d:IsA("GuiButton") or d.Active) then return false end   -- doesn't sink input -> can't be the blocker
	if not effectivelyVisible(d) then return false end              -- not rendered -> not blocking anything
	local s = d.AbsoluteSize
	return s.X >= vp.X * FULLSCREEN_FRAC and s.Y >= vp.Y * FULLSCREEN_FRAC
end

-- Does this ScreenGui have an actually-open menu PANEL? A panel is: rendered, has a real fill, is big enough to
-- be a panel, and is NOT itself full-screen. Unlike before, `Active` panels COUNT -- several panels in this game
-- set Active = true on purpose (the Pet Wheel's does, so that clicks on the panel don't fall through to the dim
-- underneath), and excluding them made their legitimate dim look orphaned.
local function hasOpenPanel(sg, vp)
	for _, d in ipairs(sg:GetDescendants()) do
		if d:IsA("GuiObject") and d.Visible and d.BackgroundTransparency < PANEL_OPAQUE then
			local s = d.AbsoluteSize
			if s.X > PANEL_MIN_PX and s.Y > PANEL_MIN_PX
				and (s.X < vp.X * FULLSCREEN_FRAC or s.Y < vp.Y * FULLSCREEN_FRAC)
				and effectivelyVisible(d) then
				return true
			end
		end
	end
	return false
end

local reported = {}   -- [full path] = true, so a stuck backdrop is named ONCE instead of twice a second

local function sweep()
	local vp = viewport()
	for _, sg in ipairs(pg:GetDescendants()) do          -- Descendants, not Children: a duplicate can be nested
		if sg:IsA("ScreenGui") and sg.Enabled then
			local backdrops
			for _, d in ipairs(sg:GetDescendants()) do
				if isBackdrop(d, vp) then
					backdrops = backdrops or {}
					backdrops[#backdrops + 1] = d
				end
			end
			-- backdrop(s) up but NO open panel -> orphaned catcher over the world. Hide it so clicks + the
			-- camera work again. A live menu simply re-shows its own backdrop through its own setOpen.
			if backdrops and not hasOpenPanel(sg, vp) then
				for _, b in ipairs(backdrops) do
					b.Visible = false
					local path = b:GetFullName()
					if not reported[path] then
						reported[path] = true
						warn("[MenuBackdropGuard] hid an ORPHANED full-screen backdrop: " .. path
							.. "  (transparency=" .. tostring(b.BackgroundTransparency) .. ")"
							.. " -- it was blocking clicks + camera rotation. If this keeps coming back, a STALE"
							.. " DUPLICATE of that menu's LocalScript is baked into the place -- delete it in Studio.")
					end
				end
			end
		end
	end
end

-- INPUT-CAPTURE SANITY. Two non-GUI ways the camera/buttons get stuck, both cheap to clear and both harmless to
-- set when nothing is wrong:
--   * ModalEnabled -- a Modal GuiButton (the garden intro's SKIP button is one) force-unlocks the mouse; if the
--     intro is interrupted at the wrong moment the flag can outlive the button.
--   * GuiService.SelectedObject -- a leftover gamepad/GUI selection keeps input focused on a dead element.
-- Only ever cleared while NO menu panel is open, so an open menu that legitimately wants modal input is safe.
local function clearStuckInputCapture()
	local vp = viewport()
	for _, sg in ipairs(pg:GetDescendants()) do
		if sg:IsA("ScreenGui") and sg.Enabled and hasOpenPanel(sg, vp) then return end -- a menu is genuinely open
	end
	if UserInput.ModalEnabled then
		UserInput.ModalEnabled = false
		warn("[MenuBackdropGuard] cleared a stuck UserInputService.ModalEnabled (it blocks mouse-look).")
	end
	if GuiService.SelectedObject then GuiService.SelectedObject = nil end
end

-- ============================================================================================================
-- DUPLICATE REPORT (diagnostic). The orphaned backdrops come FROM duplicates, so name them out loud once, ~12s
-- after join (by then every script has built its UI). Two lists, because they mean different things:
--   * duplicate LocalScripts  -> two copies of the same system are both running (double GUIs, double remotes).
--   * duplicate ScreenGui names -> the visible symptom: two menus stacked, one of them stale with a live backdrop.
-- Delete the non-Rojo copy in Studio; this guard only papers over it.
-- ============================================================================================================
task.delay(12, function()
	local function report(container, className, label)
		if not container then return end
		local seen, dupes = {}, {}
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA(className) then
				seen[d.Name] = (seen[d.Name] or 0) + 1
				if seen[d.Name] == 2 then dupes[#dupes + 1] = d.Name end
			end
		end
		if #dupes > 0 then
			table.sort(dupes)
			warn(("[MenuBackdropGuard] %d DUPLICATE %s: %s  -- two copies are running; delete the stale one in Studio.")
				:format(#dupes, label, table.concat(dupes, ", ")))
		end
	end
	pcall(function() report(plr:FindFirstChild("PlayerScripts"), "LocalScript", "LocalScript(s)") end)
	pcall(function() report(pg, "ScreenGui", "ScreenGui name(s)") end)
end)

task.spawn(function()
	-- Fast for the first 20s (join is exactly when the stale duplicates finish building and strand a backdrop),
	-- then settle into the cheap 0.5s heartbeat for the rest of the session.
	local t0 = os.clock()
	while true do
		pcall(sweep)
		pcall(clearStuckInputCapture)
		task.wait((os.clock() - t0) < 20 and 0.2 or 0.5)
	end
end)

print("[MenuBackdropGuard] active -- hides orphaned full-screen backdrops (ANY transparency) that block clicks + camera")
