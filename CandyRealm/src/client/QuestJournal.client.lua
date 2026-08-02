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
local ROWS = {
	{ 1,  "Bean Farm",       "Gumball Hunt",    function() return _G.candyQuestComplete end },
	{ 2,  "Broccoli Bluff",  "Jelly Tower",     function() return _G.jellyQuestComplete end },
	{ 3,  "Cabbage Cliffs",  "Cookie Repair",   function() return _G.cookieQuestComplete end },
	{ 4,  "Turnip Tranquil", "Campfire Freeze", function() return _G.campfireQuestComplete end },
	{ 5,  "Coconut Cove",    "Taffy Storm",     function() return _G.stormQuestComplete end },
	{ 8,  "Popcorn Pinnacle","Summit Bell",     function() return _G.summitQuestComplete end },
	{ 9,  "Milk Marsh",      "Reactor Cleanup", function() return _G.cleanupQuestComplete end },
	{ 11, "Ice Cream Isle",  "Tunnel Blast",    function() return _G.tunnelQuestComplete end },
	{ 11, "Ice Cream Isle",  "Crystal Mine",    function() return _G.crystalQuestComplete end },
	{ 13, "Burrito Barrens", "Ancient Tree",    function()
		if _G.parkQuestComplete then return true end
		local st = tonumber(_G.parkQuestStep) or 0
		return false, (st > 0) and ("step %d of 3"):format(math.min(st, 3)) or nil
	end },
	{ 14, "Pizza Palms",     "Camp S'mores",    function() return _G.smoresQuestComplete end },
	{ 15, "Bakery Isle",     "The Great Bake-Off", function()
		return _G.bakeryQuestComplete == true, _G.bakeryQuestStep
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
shade.MouseButton1Click:Connect(function() setOpen(false) end)

_G.toggleJournal = function() setOpen(not gui.Enabled) end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.J then _G.toggleJournal() end
end)

print("[Journal] ready -- press J, or call _G.toggleJournal() (e.g. from MORE+)")
