--======================================================================
-- FirstPersonMenuMouse.client.luau  (StarterPlayerScripts)  -- CandyRealm
--======================================================================
-- OPEN ANY MENU, SCROLL ALL THE WAY IN, AND YOU WERE STUCK.
--
-- In first person Roblox locks the mouse to the centre of the screen and hides the cursor --
-- that is what makes look-around work. Opening a panel does nothing about it, so the card
-- appears with no pointer to click it with. You cannot press anything on it, and you cannot
-- press its X to leave either. For a player who does not know to scroll back out, that is a
-- soft-lock with their own menu sitting on top of it.
--
-- ===== WHY THIS IS ONE SCRIPT AND NOT A FIX PER MENU =====
-- This realm has upwards of twenty panels -- SHOP, PETS, MORE+, Stomach Shop, Skin Crates,
-- Rebirth, Season Pass, Daily Tasks, Settings, Fast Travel, Gifting, Quest Journal, the trade
-- window, plus a task HUD on nearly every island. Patching them one at a time is the same
-- twenty lines copied twenty times and forgotten on the twenty-first.
--
-- It was first written into HousePanel, which was worse than it looked: HousePanel only owns
-- the panels that call _G.housePanel(), i.e. the island task HUDs. Every main menu is already
-- 700x520 natively and never goes through it -- so the SHOP, the Pet Hub and the MORE+ menu,
-- the three panels players open most, were the exact ones NOT covered.
--
-- ===== SO IT DETECTS MENUS BY SHAPE, NOT BY REGISTRATION =====
-- A menu is "a solid rectangle, big enough to matter, currently on screen". Nothing has to
-- opt in, nothing has to be listed, and a panel added next month is covered the day it is
-- written. The thresholds below are what separate a panel from the HUD, and each one is
-- chosen against something real on this screen (see PANEL_MIN_W / PANEL_MIN_H).
--
-- ===== THREE LAYERS, LEAST INTRUSIVE FIRST =====
--   1. FREE THE CURSOR. Roblox's PlayerModule releases the mouse whenever a VISIBLE GuiButton
--      with Modal = true exists. One 1x1 transparent Modal button, shown only while a menu is
--      up, gives every panel in the game a working pointer in first person. It does not touch
--      the camera: you stay exactly where you were looking and simply get a cursor back.
--   2. LET THEM ZOOM OUT. A cursor is no use if the camera is pinned by CameraMode =
--      LockFirstPerson or by a zoom range with nowhere to go. Both are relaxed while a menu is
--      up and restored EXACTLY as they were when it closes, so a quest that deliberately locks
--      the camera gets its lock back.
--   3. PUSH THE CAMERA OUT. If the camera is STILL at the head after a grace period, the zoom
--      floor is raised so the view pops back to third person on its own. The menu is never
--      touched: it stays open, exactly where it was, and you can now see and click it.
--
-- ⚠ IT USED TO CLOSE THE MENU HERE, AND THAT WAS WRONG. Hiding someone's panel out from under
-- them is a worse answer than moving their camera, and it left the menu's OWNER believing it was
-- still open -- so the next press of PETS or SHOP read as toggle-closed and did nothing, and the
-- panel only came back on the second press. "It disappeared and would not come back" is exactly
-- the bug that trade produced. Moving the camera fixes the stuck state without lying to anybody
-- about what is open.
--
-- ⚠ THIS IS NOT A BACKDROP CATCHER, and must never become one. Panels in this game close on
-- their X and nothing else -- a stray tap must never shut one. This fires on a measured camera
-- state that means the player CANNOT REACH that X, which is the opposite case and the only
-- thing that outranks the rule.
--======================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

if _G.__FirstPersonMenuMouse then
	warn("[FirstPerson] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__FirstPersonMenuMouse = true

-- ============================================================================
-- WHAT COUNTS AS A MENU
-- ============================================================================
-- Both thresholds sit ABOVE the biggest thing on the HUD and BELOW the smallest real panel,
-- measured against what this realm actually draws:
--   HUD, must NOT count -- bottom meter card 470x144, stats panel 230x500, coin pill 200x52,
--                          rail buttons 95x95, banners ~470x56.
--   PANELS, must count  -- the house card 700x520, and the smallest task HUD inside it.
-- 320 clears the stats panel's 230 width; 220 clears the bottom card's 144 height. The stats
-- panel is 500 tall but only 230 wide, and the bottom card is 470 wide but only 144 tall, so
-- requiring BOTH is what excludes them while a 700x520 card passes on either measure.
local PANEL_MIN_W, PANEL_MIN_H = 320, 220
local SOLID_ENOUGH = 0.7     -- BackgroundTransparency below this = a real card, not a dim/vignette
local COVER_FRAC   = 0.9     -- >= this much of the viewport in BOTH axes = a full-screen cover, not a panel
local GRACE        = 1.5     -- seconds in first person before the camera is pushed out
local PUSH_OUT_TO  = 8       -- studs. Far enough that the panel is clearly in front of you,
                             -- close enough that it is not a jarring jump backwards.
local POLL         = 0.2

-- ScreenGuis that are big and solid but are NOT menus. Matched as lowercase substrings.
-- Cinematics and full-screen effects run their OWN camera; yanking the zoom out from under one
-- would fight it mid-shot, and freeing the cursor during them is pointless.
local NOT_A_MENU = {
	"loadingscreen", "intro", "arrival", "cinematic",
	"notify", "banner", "toast", "announce", "objective",
	"frost", "splat", "gust", "fade", "vignette", "rain", "flash", "blur",
	"housepanelfirstperson", "firstpersonmenumouse",
}
local function excluded(name)
	local n = string.lower(name)
	for _, bad in ipairs(NOT_A_MENU) do
		if string.find(n, bad, 1, true) then return true end
	end
	return false
end

local function onScreen(o)
	local n = o
	while n and n ~= PlayerGui do
		if n:IsA("GuiObject") and not n.Visible then return false end
		if n:IsA("ScreenGui") and not n.Enabled then return false end
		n = n.Parent
	end
	return n == PlayerGui
end

-- Returns the largest panel currently on screen, or nil. Largest, because a menu with a nested
-- sub-sheet should be judged (and if it comes to it, closed) by its outermost card.
local function findOpenPanel()
	local cam = Workspace.CurrentCamera
	local vp  = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local best, bestArea
	for _, sg in ipairs(PlayerGui:GetChildren()) do
		if sg:IsA("ScreenGui") and sg.Enabled and not excluded(sg.Name) then
			for _, d in ipairs(sg:GetDescendants()) do
				if d:IsA("GuiObject") and d.Visible and d.BackgroundTransparency < SOLID_ENOUGH then
					local sz = d.AbsoluteSize
					if sz.X >= PANEL_MIN_W and sz.Y >= PANEL_MIN_H
						and not (sz.X >= vp.X * COVER_FRAC and sz.Y >= vp.Y * COVER_FRAC)
						and onScreen(d)
					then
						local area = sz.X * sz.Y
						if not bestArea or area > bestArea then best, bestArea = d, area end
					end
				end
			end
		end
	end
	return best
end

-- ============================================================================
-- LAYER 1 -- THE MODAL BUTTON
-- ============================================================================
-- ResetOnSpawn = false: dying with a menu open must not destroy the thing holding the cursor
-- free. 1x1 in the very corner so it can never swallow a click meant for the menu, and it does
-- nothing when pressed -- it exists only for the property.
local modalBtn
do
	local g = Instance.new("ScreenGui")
	g.Name = "FirstPersonMenuMouse"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true
	g.DisplayOrder = -1000
	g.Parent = PlayerGui

	modalBtn = Instance.new("TextButton")
	modalBtn.Name = "MouseFreer"
	modalBtn.Size = UDim2.fromOffset(1, 1); modalBtn.Position = UDim2.fromOffset(0, 0)
	modalBtn.BackgroundTransparency = 1; modalBtn.Text = ""; modalBtn.AutoButtonColor = false
	modalBtn.Active = true
	modalBtn.Visible = false
	modalBtn.Modal = true      -- THE WHOLE POINT: releases the first-person mouse lock
	modalBtn.Parent = g
end

-- ============================================================================
-- THE WATCH
-- ============================================================================
task.spawn(function()
	local saved, firstPersonSince, lastPanel = nil, nil, nil

	-- First person is a MEASUREMENT, not a setting: the camera sitting essentially on the head.
	-- Reading CameraMode alone would miss a player who simply scrolled all the way in, which is
	-- the common case and the one that gets reported.
	local function inFirstPerson()
		local cam  = Workspace.CurrentCamera
		local char = player.Character
		local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
		if not (cam and head) then return false end
		return (cam.CFrame.Position - head.Position).Magnitude < 1.5
	end

	while true do
		task.wait(POLL)
		local panel = findOpenPanel()

		if panel and not saved then
			modalBtn.Visible = true
			saved = {
				mode    = player.CameraMode,
				minZoom = player.CameraMinZoomDistance,
				maxZoom = player.CameraMaxZoomDistance,
			}
			if player.CameraMode == Enum.CameraMode.LockFirstPerson then
				player.CameraMode = Enum.CameraMode.Classic
			end
			-- a min >= max leaves the zoom nowhere to travel; open it enough to get back out
			if player.CameraMaxZoomDistance <= player.CameraMinZoomDistance then
				player.CameraMaxZoomDistance = math.max(player.CameraMinZoomDistance + 12, 16)
			end
			if player.CameraMinZoomDistance >= player.CameraMaxZoomDistance then
				player.CameraMinZoomDistance = 0.5
			end
			firstPersonSince, lastPanel = nil, panel

		elseif not panel and saved then
			-- hand the camera back EXACTLY as its owner left it
			modalBtn.Visible = false
			player.CameraMode            = saved.mode
			player.CameraMinZoomDistance = saved.minZoom
			player.CameraMaxZoomDistance = saved.maxZoom
			saved, firstPersonSince, lastPanel = nil, nil, nil
		end

		if panel then
			if panel ~= lastPanel then firstPersonSince, lastPanel = nil, panel end
			if inFirstPerson() then
				firstPersonSince = firstPersonSince or os.clock()
				-- the grace window is what lets layers 1 and 2 win first: with the cursor free and
				-- the zoom unpinned, a player who scrolls out in that time never sees this fire
				if os.clock() - firstPersonSince > GRACE then
					-- Raise the FLOOR, not the camera. Roblox slides the view out to satisfy a
					-- minimum zoom distance, so this eases them into third person instead of
					-- snapping the CFrame -- and it stays out for as long as the menu is up.
					-- Restored with the rest of the camera state the moment it closes.
					if player.CameraMinZoomDistance < PUSH_OUT_TO then
						player.CameraMinZoomDistance = PUSH_OUT_TO
						if player.CameraMaxZoomDistance < PUSH_OUT_TO then
							player.CameraMaxZoomDistance = PUSH_OUT_TO + 4
						end
						print(("[FirstPerson] first person with '%s' open -- pushed the camera out to %d studs "
							.. "so the panel is visible and clickable. The menu is untouched and stays open.")
							:format(panel:GetFullName(), PUSH_OUT_TO))
					end
					firstPersonSince = nil
				end
			else
				firstPersonSince = nil
			end
		end
	end
end)

print(("[FirstPerson] ready -- EVERY panel is clickable in first person (menus detected by shape: "
	.. ">=%dx%d, solid, on screen -- no registration needed). Cursor freed, zoom unpinned, and a "
	.. "view still stuck after %.1fs is pushed out to %d studs."):format(PANEL_MIN_W, PANEL_MIN_H, GRACE, PUSH_OUT_TO))
