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
local OVERLAY_MIN_PX  = 200    -- a sheet laid over a panel is at least this big; no caption or icon ever is
local PANEL_OPAQUE    = 0.95   -- a real panel has a visible fill
local MIN_VIEWPORT    = 200    -- below this the viewport is not real yet -- see viewport() below

-- HUD, NOT MENUS. These ScreenGuis hold the controls the player actually plays with, and NONE of them
-- contains a backdrop -- there is nothing here for this guard to ever legitimately hide.
--
-- Skipping them is not tidiness, it is the whole bug. Every one of these holds a full-size invisible
-- TextButton (mkSideBtn's click area fills its tile; the fart button fills its row), and when the
-- viewport read wrong (below) those buttons measured as "full-screen" and got hidden -- so the rail,
-- the fart button, the coin pill and the gear all went dead and the game looked frozen. On a phone
-- that is total: the fart button IS the game, and an invisible sunk button over the thumbstick area
-- eats movement touches too.
local HUD_GUIS = {
	SidebarGui = true, BottomStackGui = true, GasMeterGui = true, FartButtonGui = true,
	StomachGui = true, CoinGui = true, RightPanelGui = true, SettingsGui = true,
	ReturnIslandGui = true, ObjectiveHUD = true, NavGui = true, LoadingScreen = true,
	CampfireHud = true, PetQuestUI = true, HudNoticeGui = true,
}

-- THE VIEWPORT MUST BE REAL BEFORE ANY OF THIS MEANS ANYTHING.
--
-- Returns nil when it is not. The old fallback of Vector2.new(1, 1) was catastrophic rather than safe:
-- with a 1x1 viewport, "covers >=90% of the screen" is true of literally every button on screen, and
-- "is smaller than 90% of the screen" -- the open-panel test -- is true of nothing. So one sweep at the
-- wrong moment classified the entire UI as orphaned backdrops with no panel behind them, and hid all of it.
--
-- It happens for real: CurrentCamera is briefly nil at join, and on mobile the viewport reports garbage
-- for a frame when the app resumes from the background or the device rotates -- which is exactly when
-- players report the controls dying mid-session.
local function viewport()
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local vp = cam.ViewportSize
	if vp.X < MIN_VIEWPORT or vp.Y < MIN_VIEWPORT then return nil end
	return vp
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

-- Does this element FILL its parent? Size in pure scale (1,1) is how every backdrop, dim, catcher and full-panel
-- overlay in this game is authored -- and no caption or real panel ever is (the Shop's is 0.9 x 0.85, the rest
-- are offset boxes). It is the structural tell that separates "a sheet laid over something" from "a piece of the
-- menu", and both passes below turn on it.
local function fillsParent(d)
	local s = d.Size
	return s.X.Scale >= 1 and s.Y.Scale >= 1
end

-- Does this ScreenGui have an actually-open menu PANEL? A panel is: rendered, has a real fill, is big enough to
-- be a panel, and is NOT itself full-screen. Unlike before, `Active` panels COUNT -- several panels in this game
-- set Active = true on purpose (the Pet Wheel's does, so that clicks on the panel don't fall through to the dim
-- underneath), and excluding them made their legitimate dim look orphaned.
local function hasOpenPanel(sg, vp)
	for _, d in ipairs(sg:GetDescendants()) do
		-- `not fillsParent` is new: a 700x520 dim stretched over a 700x520 panel is not evidence that a menu is
		-- open -- it is the thing this file exists to catch. Counting it as a panel is what let a stuck overlay
		-- vouch for itself and skip the sweep entirely.
		if d:IsA("GuiObject") and d.Visible and d.BackgroundTransparency < PANEL_OPAQUE and not fillsParent(d) then
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
local hiddenByUs = {} -- [GuiObject] = true, everything this guard has hidden -- see restoreFalsePositives

-- UNDO A BAD CALL.
--
-- Hiding was one-way before: nothing ever set Visible back, so a single mis-fire killed a control for
-- the rest of the session and the only cure was rejoining. Anything hidden is now re-checked against a
-- VALID viewport, and if it no longer looks like a full-screen input sink it goes straight back.
--
-- A genuine stuck backdrop still measures full-screen, so it stays hidden -- this only ever reverses the
-- ordinary HUD buttons that were mismeasured, never the thing the guard exists to catch.
local function restoreFalsePositives(vp)
	for obj in pairs(hiddenByUs) do
		if not obj.Parent then
			hiddenByUs[obj] = nil
		else
			local s = obj.AbsoluteSize
			if s.X < vp.X * FULLSCREEN_FRAC or s.Y < vp.Y * FULLSCREEN_FRAC then
				obj.Visible = true
				hiddenByUs[obj] = nil
				reported[obj:GetFullName()] = nil
				warn("[MenuBackdropGuard] RESTORED " .. obj:GetFullName()
					.. " -- it is not full-screen, so hiding it was wrong (the viewport was misread).")
			end
		end
	end
end

-- ============================================================================================================
-- THE GREY SHEET OVER THE MIDDLE OF THE SCREEN
--
-- Separate bug from the orphaned backdrops above, same visible result. Menus hide their sub-overlays with
-- Visible = false at build time -- Rebirth's PETS overlay (700x520 @ 25% black, ZIndex 25), the Season Pass
-- "how it works" overlay (700x520 @ 20%), and every "are you sure" sheet. Then CoreClient's reposition pass
-- does this to EVERY TextLabel and TextButton under PlayerGui:
--
--     v.TextScaled = true; v.Visible = true
--
-- and switches all of them back on. The tell is in the Output dump: inside ONE panel, the overlay authored as a
-- TextButton comes back `vis=true` while the identical sheet authored as a Frame stays `vis=false`. The sweep
-- only touches text classes.
--
-- A force-shown overlay draws as a big translucent rectangle over the middle of the screen, dimming everything
-- behind it, with no way to dismiss it during normal play.
--
-- ===== TWO THINGS, AND ONLY WHILE THE MENU IS CLOSED =====
--   1. Put it back to Visible = false.
--   2. Stamp NoTextSweep ON THE OVERLAY ITSELF so the sweep skips it from now on. That attribute is the sweep's
--      own documented opt-out and _G.hudTextSweepSkip walks ancestors, so marking the one element is exact --
--      it does not opt the whole menu out of text scaling, which would restyle panels that rely on it.
--
-- Gated on the menu being closed so this can never yank an overlay out from under a player who just opened it:
-- while the menu is shut, nothing inside it is supposed to be on screen, so hiding is always right. By the time
-- they open the menu the overlay is already back to its authored state, and step 2 keeps it there.
-- ============================================================================================================
local overlayFixed = {}   -- [GuiObject] = true, so each one is logged once, not twice a second

local function tidyClosedMenu(sg)
	for _, d in ipairs(sg:GetDescendants()) do
		if (d:IsA("TextButton") or d:IsA("TextLabel"))
			and d.Visible
			and fillsParent(d)
			and d.BackgroundTransparency < PANEL_OPAQUE   -- it actually tints what is behind it
			and d.Parent ~= sg                            -- direct children are the menu's own backdrop: isBackdrop owns those
			-- Overlay-scale, not label-scale. A (1,1) TextLabel does exist inside small tiles (the MORE+ icon
			-- glyphs are one), and they must never be touched -- but none of them is 200px square. Roblox keeps
			-- AbsoluteSize up to date for hidden and disabled objects, so this reads correctly on a closed menu.
			and d.AbsoluteSize.X >= OVERLAY_MIN_PX and d.AbsoluteSize.Y >= OVERLAY_MIN_PX
		then
			d.Visible = false
			d:SetAttribute("NoTextSweep", true)
			if not overlayFixed[d] then
				overlayFixed[d] = true
				warn("[MenuBackdropGuard] re-hid a force-shown overlay: " .. d:GetFullName()
					.. "  (transparency=" .. tostring(d.BackgroundTransparency) .. ")"
					.. " -- it was built hidden, and the CoreClient text sweep (v.Visible = true on every"
					.. " TextLabel/TextButton) switched it back on, so it drew as a grey sheet over the screen."
					.. " Marked NoTextSweep so the sweep leaves it alone.")
			end
		end
	end
end

local function sweep()
	local vp = viewport()
	if not vp then return end -- viewport not trustworthy yet: measuring anything against it is worse than waiting
	restoreFalsePositives(vp)

	-- Force-shown overlays are put back FIRST, and on every ScreenGui -- including the disabled ones, which is
	-- most closed menus. Waiting until a menu is enabled would mean repairing it only once it is already on
	-- screen, i.e. after the player has seen the grey sheet.
	for _, sg in ipairs(pg:GetDescendants()) do
		if sg:IsA("ScreenGui") and not HUD_GUIS[sg.Name] then
			if not (sg.Enabled and hasOpenPanel(sg, vp)) then pcall(tidyClosedMenu, sg) end
		end
	end

	for _, sg in ipairs(pg:GetDescendants()) do          -- Descendants, not Children: a duplicate can be nested
		if sg:IsA("ScreenGui") and sg.Enabled and not HUD_GUIS[sg.Name] then
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
					hiddenByUs[b] = true
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
	if not vp then return end -- same rule as sweep: never decide anything from a viewport we do not trust
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

print("[MenuBackdropGuard] active -- hides orphaned full-screen backdrops (ANY transparency) that block clicks +"
	.. " camera; HUD GUIs are never touched, and anything hidden by mistake is restored")
