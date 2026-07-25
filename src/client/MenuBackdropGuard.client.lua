--!nonstrict
-- MenuBackdropGuard (StarterPlayer/StarterPlayerScripts/MenuBackdropGuard)
-- ============================================================================================================
-- FIXES: "I can't rotate the camera until I click on some GUI."
--
-- Several menu panels (Season Pass, Free Rewards / Social, Rebirth, More+) use a FULL-SCREEN, fully-transparent
-- "tap-outside-to-close" backdrop button. That's fine while the menu is OPEN. The problem: STALE DUPLICATE copies
-- of those menu GUIs (baked into the place file from old LocalScripts -- the panel scripts themselves warn about
-- this: "a stale LocalScript builds its own ...Gui") sit there with their backdrop left VISIBLE while the menu is
-- closed. An invisible full-screen button over the world SWALLOWS every click / right-drag meant for the camera,
-- so the player can't rotate until they click a real HUD button instead.
--
-- This guard neutralises any such ORPHANED backdrop: a full-screen, fully-transparent, input-sinking element that
-- is Visible while NO actual menu panel in the same ScreenGui is open. A legitimately-open menu always shows a
-- real (opaque, non-full-screen) panel, so those are never touched -- and semi-transparent dims (e.g. the Pet
-- Wheel / Wormhole backdrops at 45% opacity) are ignored too, since they're only up while their menu is open.
--
-- The true ROOT fix is deleting the stale duplicate LocalScripts in Studio; this makes the game robust even if a
-- duplicate slips through.
-- ============================================================================================================

local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local pg  = plr:WaitForChild("PlayerGui")

local FULLSCREEN_FRAC = 0.9   -- covers >=90% of the viewport in BOTH dims = a full-screen backdrop
local INVISIBLE_BG    = 0.99  -- background essentially fully transparent = a pure click-catcher, not real UI

local function viewport()
	local cam = workspace.CurrentCamera
	return (cam and cam.ViewportSize) or Vector2.new(1, 1)
end

-- A full-screen, invisible, input-SINKING element (a backdrop click-catcher)?
local function isBackdrop(d, vp)
	if not d:IsA("GuiObject") or not d.Visible then return false end
	if not (d:IsA("GuiButton") or d.Active) then return false end          -- must sink input
	if d.BackgroundTransparency < INVISIBLE_BG then return false end        -- has a visible tint (a real dim) -> leave it
	local s = d.AbsoluteSize
	return s.X >= vp.X * FULLSCREEN_FRAC and s.Y >= vp.Y * FULLSCREEN_FRAC
end

-- Does this ScreenGui have an actually-open menu PANEL? (a Visible, opaque-ish, NON-full-screen Frame/label).
-- If yes, the menu is genuinely open and its backdrop is legitimate -> we leave everything alone.
local function hasOpenPanel(sg, vp)
	for _, d in ipairs(sg:GetDescendants()) do
		if d:IsA("GuiObject") and d.Visible and not (d:IsA("GuiButton") or d.Active) then
			local s = d.AbsoluteSize
			if d.BackgroundTransparency < 0.95 and s.X > 40 and s.Y > 40
				and (s.X < vp.X * FULLSCREEN_FRAC or s.Y < vp.Y * FULLSCREEN_FRAC) then
				return true
			end
		end
	end
	return false
end

local function sweep()
	local vp = viewport()
	for _, sg in ipairs(pg:GetChildren()) do
		if sg:IsA("ScreenGui") and sg.Enabled then
			local backdrops
			for _, d in ipairs(sg:GetDescendants()) do
				if isBackdrop(d, vp) then
					backdrops = backdrops or {}
					backdrops[#backdrops + 1] = d
				end
			end
			-- backdrop(s) up but NO open panel -> orphaned catcher blocking the world. Hide it so the camera works.
			if backdrops and not hasOpenPanel(sg, vp) then
				for _, b in ipairs(backdrops) do
					b.Visible = false -- a live menu will simply re-show it via its own setOpen when actually opened
				end
			end
		end
	end
end

task.spawn(function()
	while true do
		pcall(sweep)
		task.wait(0.5) -- cheap: only acts when a stuck backdrop is actually present
	end
end)

print("[MenuBackdropGuard] active -- hides orphaned full-screen menu backdrops that block camera rotation")
