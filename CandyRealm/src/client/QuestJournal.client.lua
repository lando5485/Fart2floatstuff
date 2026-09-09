--======================================================================
-- QuestJournal.client.lua   (LocalScript, per-player)
--======================================================================
-- ONE PLACE THAT SAYS WHAT IS LEFT TO DO.
--
-- Fourteen islands, a quest on most of them, and the only way to find out where you stand is to
-- fly to an island and walk up to its NPC. A player who cannot see their own progress has no
-- reason to believe there is any.
--
-- IT INVENTS NOTHING. Every quest already publishes its own state as a _G flag when it finishes
-- -- smoresQuestComplete, tunnelQuestComplete, parkQuestStep and the rest -- so the journal
-- just reads them. No remotes, no saving, no second source of truth to drift out of step with
-- the quests themselves. If a row says done, the quest itself said so.
--
-- Opens with J, or from MORE+ (it registers _G.toggleJournal, which MorePopup calls if you add
-- a row for it).
--======================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local player           = Players.LocalPlayer
local PlayerGui        = player:WaitForChild("PlayerGui")

-- island, name, quest, and how to read its progress. The `state` function returns
-- (done, detail) -- detail is the small grey text on the right.
--
-- ===== THREE THINGS THIS TABLE USED TO GET WRONG =====
--   1. THE ISLAND NAMES WERE THE FOOD REALM'S. Every row read "Bean Farm", "Broccoli Bluff",
--      "Popcorn Pinnacle" and so on -- the fourteen islands of the OTHER game, copied across with
--      the file. Candy's islands are named in IslandOrder.NAMES and none of them match, so a player
--      opening the journal was told to go somewhere that does not exist in this realm. The names
--      below now come from IslandOrder.NAMES, indexed by the island model number.
--   2. TWO ISLAND NUMBERS WERE SWAPPED. Summit Bell was listed on island8 and Crystal Mine on
--      island11. The quests themselves say otherwise -- SummitBellQuest is ISLAND_NAME = "island4"
--      and CrystalMineQuest is ISLAND_NAME = "island8" -- which is the same swap DoneCommand
--      documents and works around. Nothing keys off this column, so it broke nothing internally; it
--      simply sent players to the wrong island, which is the whole job of this panel.
--   3. IT CLAIMED TO READ AS THE CLIMB AND DID NOT. The rows were in island-NUMBER order, but
--      SLOT_TO_ISLAND is a deliberate scramble ({1,9,3,13,5,8,2,11,4,14,15}), so island9 is the
--      SECOND island you reach and island2 the seventh. Ordered below by climb slot, which is what
--      a player actually walks, with the three off-ladder islands after the summit.
--
-- Still deliberately hand-written rather than derived from IslandOrder: the off-ladder islands
-- (16/18/19) are not in it at all, and a journal that silently dropped three quests to stay
-- derivable would be worse than one that has to be kept in step.
local ROWS = {
	-- ---- THE LADDER, in climb order (slot 1 -> 11) --------------------------------------
	{ 1,  "Candy Cane Court",     "Gumball Hunt",    function() return _G.candyQuestComplete end },
	{ 9,  "Cocoa Reactor",        "Reactor Cleanup", function() return _G.cleanupQuestComplete end },
	{ 3,  "Cookie Crumble",       "Cookie Repair",   function() return _G.cookieQuestComplete end },
	{ 13, "Gumtree Park",         "Ancient Tree",    function()
		if _G.parkQuestComplete then return true end
		local st = tonumber(_G.parkQuestStep) or 0
		return false, (st > 0) and ("step %d of 3"):format(math.min(st, 3)) or nil
	end },
	{ 5,  "Taffy Town",           "Taffy Storm",     function() return _G.stormQuestComplete end },
	{ 8,  "Crystal Candy Caves",  "Crystal Mine",    function() return _G.crystalQuestComplete end },
	-- Jelly Tower (island2) REMOVED from the journal: the quest is retired and the island was
	-- never built -- a row that can never tick reads as the player's failure, not the game's
	{ 11, "Licorice Tunnels",     "Tunnel Blast",    function() return _G.tunnelQuestComplete end },
	-- island4 is the one slot with TWO quests on it
	{ 4,  "Frostbell Peak",       "Campfire Freeze", function() return _G.campfireQuestComplete end },
	{ 4,  "Frostbell Peak",       "Summit Bell",     function() return _G.summitQuestComplete end },
	{ 14, "Marshmallow Camp",     "Camp S'mores",    function() return _G.smoresQuestComplete end },
	{ 15, "Bakery Summit",        "The Great Bake-Off", function()
		return _G.bakeryQuestComplete == true, _G.bakeryQuestStep
	end },
	-- ---- PROMOTED RUNGS (slots 8/7/12) -- their island names must match IslandOrder.NAMES,
	-- or the journal, the wormhole and the HUD call the same island three different things.
	{ 16, "Pop Rock Quarry",      "Candy Mine Explosion", function() return _G.candyMineQuestComplete end },
	{ 18, "Pancake Arena",        "Wake the Pancake Monster", function()
		return _G.pancakeQuestComplete == true, _G.pancakeQuestStep
	end },
	{ 19, "Sugarbeet Farm",       "Broken Tractor", function()
		return _G.tractorQuestComplete == true, _G.tractorQuestStep
	end },
}

local FILL   = Color3.fromRGB(255, 245, 250)
local STROKE = Color3.fromRGB(214, 92, 158)
local TEXTC  = Color3.fromRGB(74, 30, 58)
local HINTC  = Color3.fromRGB(158, 132, 150)
local DONE   = Color3.fromRGB(72, 168, 92)

-- ---- the panel -------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "QuestJournal"; gui.ResetOnSpawn = false; gui.DisplayOrder = 11
gui.IgnoreGuiInset = true; gui.Enabled = false; gui.Parent = PlayerGui

local shade = Instance.new("TextButton")
shade.Size = UDim2.fromScale(1, 1); shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 0.5; shade.Text = ""; shade.AutoButtonColor = false
shade.ZIndex = 1; shade.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0, 700, 0, 520)
panel.BackgroundColor3 = FILL; panel.BorderSizePixel = 0; panel.ZIndex = 2
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
do
	local st = Instance.new("UIStroke"); st.Color = STROKE; st.Thickness = 3; st.Parent = panel
end

local head = Instance.new("TextLabel")
head.BackgroundTransparency = 1; head.Position = UDim2.new(0, 24, 0, 16)
head.Size = UDim2.new(1, -120, 0, 44)
head.Font = Enum.Font.FredokaOne; head.TextSize = 30; head.TextColor3 = TEXTC
head.TextXAlignment = Enum.TextXAlignment.Left; head.ZIndex = 3
head.Text = "Quest Journal"; head.Parent = panel

local tally = Instance.new("TextLabel")
tally.BackgroundTransparency = 1; tally.Position = UDim2.new(0, 24, 0, 56)
tally.Size = UDim2.new(1, -120, 0, 24)
tally.Font = Enum.Font.GothamMedium; tally.TextSize = 16; tally.TextColor3 = HINTC
tally.TextXAlignment = Enum.TextXAlignment.Left; tally.ZIndex = 3
tally.Text = ""; tally.Parent = panel

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0); close.Position = UDim2.new(1, -18, 0, 18)
close.Size = UDim2.fromOffset(44, 44); close.BackgroundColor3 = STROKE
close.Text = "X"; close.Font = Enum.Font.FredokaOne; close.TextSize = 22
close.TextColor3 = Color3.new(1, 1, 1); close.AutoButtonColor = true
close.BorderSizePixel = 0; close.ZIndex = 4; close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 12)

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.new(0, 18, 0, 92); list.Size = UDim2.new(1, -36, 1, -110)
list.BackgroundTransparency = 1; list.BorderSizePixel = 0
list.ScrollBarThickness = 6; list.ScrollBarImageColor3 = STROKE
list.CanvasSize = UDim2.new(0, 0, 0, 0); list.ZIndex = 3; list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8); layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local rowUI = {}
for i, r in ipairs(ROWS) do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 54); row.BackgroundColor3 = Color3.fromRGB(248, 236, 244)
	row.BorderSizePixel = 0; row.LayoutOrder = i; row.ZIndex = 3; row.Parent = list
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)

	local pip = Instance.new("Frame")
	pip.Position = UDim2.new(0, 12, 0.5, -11); pip.Size = UDim2.fromOffset(22, 22)
	pip.BackgroundColor3 = Color3.fromRGB(226, 214, 222); pip.BorderSizePixel = 0
	pip.ZIndex = 4; pip.Parent = row
	Instance.new("UICorner", pip).CornerRadius = UDim.new(1, 0)

	local isle = Instance.new("TextLabel")
	isle.BackgroundTransparency = 1; isle.Position = UDim2.new(0, 46, 0, 0)
	isle.Size = UDim2.new(0, 46, 1, 0)
	isle.Font = Enum.Font.FredokaOne; isle.TextSize = 20; isle.TextColor3 = STROKE
	isle.TextXAlignment = Enum.TextXAlignment.Left; isle.ZIndex = 4
	isle.Text = tostring(r[1]); isle.Parent = row

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1; name.Position = UDim2.new(0, 96, 0, 8)
	name.Size = UDim2.new(1, -280, 0, 22)
	name.Font = Enum.Font.GothamBold; name.TextSize = 17; name.TextColor3 = TEXTC
	name.TextXAlignment = Enum.TextXAlignment.Left; name.ZIndex = 4
	name.Text = r[3]; name.Parent = row

	local where = Instance.new("TextLabel")
	where.BackgroundTransparency = 1; where.Position = UDim2.new(0, 96, 0, 28)
	where.Size = UDim2.new(1, -280, 0, 18)
	where.Font = Enum.Font.GothamMedium; where.TextSize = 13; where.TextColor3 = HINTC
	where.TextXAlignment = Enum.TextXAlignment.Left; where.ZIndex = 4
	where.Text = r[2]; where.Parent = row

	local status = Instance.new("TextLabel")
	status.AnchorPoint = Vector2.new(1, 0.5)
	status.Position = UDim2.new(1, -16, 0.5, 0); status.Size = UDim2.new(0, 170, 1, 0)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold; status.TextSize = 15
	status.TextXAlignment = Enum.TextXAlignment.Right; status.ZIndex = 4
	status.Text = ""; status.Parent = row

	rowUI[i] = { row = row, pip = pip, status = status }
end

local function refresh()
	local done = 0
	for i, r in ipairs(ROWS) do
		local ok, detail = false, nil
		local fine, res, res2 = pcall(r[4])
		if fine then ok, detail = res == true, res2 end
		local u = rowUI[i]
		if ok then
			done += 1
			u.pip.BackgroundColor3 = DONE
			u.status.Text = "Complete"
			u.status.TextColor3 = DONE
			u.row.BackgroundColor3 = Color3.fromRGB(240, 248, 240)
		else
			u.pip.BackgroundColor3 = Color3.fromRGB(226, 214, 222)
			u.status.Text = detail or "Not started"
			u.status.TextColor3 = detail and STROKE or HINTC
			u.row.BackgroundColor3 = Color3.fromRGB(248, 236, 244)
		end
	end
	tally.Text = ("%d of %d complete"):format(done, #ROWS)
	list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
end

local function setOpen(on)
	if on then
		refresh()                    -- read the flags at the moment it opens, never cached
		gui.Enabled = true
		panel.Size = UDim2.new(0, 660, 0, 490)
		TweenService:Create(panel, TweenInfo.new(0.22, Enum.EasingStyle.Back),
			{ Size = UDim2.new(0, 700, 0, 520) }):Play()
	else
		gui.Enabled = false
	end
end

close.MouseButton1Click:Connect(function() setOpen(false) end)
-- THE BACKDROP DELIBERATELY DOES NOT CLOSE THIS. It is a TextButton only so that clicks land on it
-- instead of falling through to the world behind the panel; swallowing the click is the whole job.
-- Closing on it is this realm's one banned menu behaviour -- a kid tapping to scroll a list of
-- fifteen quests loses the panel, with no idea what they did. The X button is the only way out.
shade.MouseButton1Click:Connect(function() end)

_G.toggleJournal = function() setOpen(not gui.Enabled) end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.J then _G.toggleJournal() end
end)

print("[Journal] ready -- press J, or call _G.toggleJournal() (e.g. from MORE+)")
