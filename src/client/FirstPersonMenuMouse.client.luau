--======================================================================
-- FirstPersonMenuMouse.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- OPEN A SHOP IN FIRST PERSON AND YOU WERE STUCK.
--
-- In first person Roblox locks the mouse to the centre of the screen and hides the cursor --
-- that is what makes look-around work. Opening a menu did nothing to change that, so the
-- panel appeared with no pointer to click it with: you could not buy, and you could not press
-- the X to leave either. The only way out was to scroll back to third person, which a player
-- who does not know that is a soft-lock.
--
-- ===== THE FIX: ONE MODAL BUTTON, NOT A PATCH PER SHOP =====
-- Roblox's own PlayerModule releases the mouse whenever a VISIBLE GuiButton with Modal = true
-- exists. So this keeps a single 1x1 transparent Modal button parked in the screen corner and
-- shows it while a menu is open. That is the same trick the intro's SKIP button uses to stay
-- clickable while controls are disabled.
--
-- It hooks _G.MainMenuManager.current -- the shared menu manager in CoreClient that the food
-- shop, food stand, pet hub, stomach shop, premium shop and the crate UIs ALL route through
-- via notifyOpened/notifyClosed. One hook therefore covers every shop in the realm, and any
-- shop added later gets the fix for free the moment it registers with the manager. Patching
-- each shop file instead would mean the same twenty lines copied six times and forgotten on
-- the seventh.
--
-- ===== WHY POLL, AND WHY IT IS CHEAP =====
-- Wrapping notifyOpened/notifyClosed would fire instantly but only catches callers that go
-- through those two functions; anything setting mgr.current directly would be missed. A 0.1s
-- poll of one table field catches every path including those, and the cost is a field read ten
-- times a second. The delay is well under the time it takes to move a hand to the mouse.
--
-- ===== WHAT IT DELIBERATELY DOES NOT DO =====
--   * It does not touch the camera. The player stays in first person -- they just get a cursor.
--     Yanking them to third person would move the view under someone mid-aim.
--   * The button does nothing when clicked. Menus in this game close on their X and nothing
--     else; a stray tap must never shut a panel, so this must not become a backdrop catcher.
--   * It is 1x1 in the very corner, so it cannot swallow a click meant for the menu.
--======================================================================

local Players = game:GetService("Players")
local player  = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local POLL = 0.1

-- The manager is created by whichever client script loads first, so it may not exist yet.
local mgr
while not mgr do
	mgr = _G.MainMenuManager
	if not mgr then task.wait(0.25) end
end

-- ResetOnSpawn = false: dying with a shop open must not destroy the thing holding the cursor free.
local gui = Instance.new("ScreenGui")
gui.Name = "FirstPersonMenuMouse"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = -1000 -- behind everything; it is never meant to be seen or hit
gui.Parent = playerGui

local modalBtn = Instance.new("TextButton")
modalBtn.Name = "MouseFreer"
modalBtn.Size = UDim2.fromOffset(1, 1)
modalBtn.Position = UDim2.fromOffset(0, 0)
modalBtn.BackgroundTransparency = 1
modalBtn.Text = ""
modalBtn.AutoButtonColor = false
modalBtn.Active = true
modalBtn.Visible = false     -- only while a menu is open
modalBtn.Modal = true        -- THE WHOLE POINT: frees the mouse from first-person lock
modalBtn.ZIndex = 1
modalBtn.Parent = gui

local wasOpen = false
task.spawn(function()
	while true do
		local open = (_G.MainMenuManager and _G.MainMenuManager.current) ~= nil
		if open ~= wasOpen then
			wasOpen = open
			-- Toggling Visible (not Modal) so the button is only a modal while it is on screen --
			-- an invisible Modal button is ignored by the PlayerModule anyway, but flipping the
			-- property the engine actually reads keeps the two from drifting apart.
			modalBtn.Visible = open
			print("[FirstPersonMenuMouse] menu " .. (open and ("OPEN (" .. tostring(_G.MainMenuManager.current) .. ") -> cursor freed")
				or "CLOSED -> mouse lock restored"))
		end
		task.wait(POLL)
	end
end)

print("[FirstPersonMenuMouse] loaded -- shops are clickable in first person")
