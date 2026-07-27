--======================================================================
-- MorePopup_AllInOne.client.lua  (LocalScript)  -- CandyRealm
--======================================================================
-- Fixes the dead MORE (+) side button. JustButtons_AllInOne's MORE handler does:
--     if _G.toggleMorePopup then _G.toggleMorePopup()
--     else fire an "OpenMorePopup" BindableEvent ...
-- ...but NOTHING in CandyRealm defined the toggler OR listened for the event, so
-- the button did nothing. This script defines _G.toggleMorePopup AND listens for
-- OpenMorePopup, then builds a small data-driven popup near the rail.
--
-- ENTRIES are ONLY things with a REAL hook in CandyRealm, and NOT already on the
-- left rail (SHOP/WORMHOLE/Stomach/MORE), so nothing here is redundant or dead:
--     Pets        -> fire the PetInvToggle BindableEvent (PetHub/PetFollow listen)
--     Daily Crate -> fire ReplicatedStorage/OpenMeteorCrate (CrateClient; its ONLY
--                    opener) + red dot via _G.crateIsClaimable()
--     Daily Tasks -> _G.toggleDailyTasks()   (DailyTasks) + red dot via _G.dailyTasksPending()
--     Rebirth     -> _G.toggleRebirth()      (RebirthClient)
--     Season Pass -> _G.toggleSeasonPass()   (SeasonPass)
--     Codes       -> _G.openCodesGui()       (RewardsClient)
-- Each row is GUARDED: if its hook isn't present when clicked, it no-ops cleanly.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local scale    = isMobile and 0.7 or 1.0

local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end
local function playClick() if _G.playUIClick then _G.playUIClick() end end

-- ===== ENTRIES (label + emoji + guarded action + optional attention flag) =====
local function firePetInv()
	local ev = PlayerGui:FindFirstChild("PetInvToggle")
	if ev and ev:IsA("BindableEvent") then ev:Fire() else print("[MorePopup] PetInvToggle not present yet") end
end
local function fireCrate()
	-- CrateClient has no button of its own; it opens ONLY when this event fires (CrateClient:30).
	local ev = ReplicatedStorage:FindFirstChild("OpenMeteorCrate")
	if ev and ev:IsA("BindableEvent") then ev:Fire() else print("[MorePopup] OpenMeteorCrate not present yet") end
end
local MORE_ENTRIES = {
	{ label = "Pets",        emoji = "\xF0\x9F\x90\xBE", action = firePetInv },
	{ label = "Daily Crate", emoji = "\xF0\x9F\x8E\x81", action = fireCrate,
	  attention = function() return (_G.crateIsClaimable and _G.crateIsClaimable()) == true end },
	{ label = "Daily Tasks", emoji = "\xF0\x9F\x93\x8B", action = function() if _G.toggleDailyTasks then _G.toggleDailyTasks() else print("[MorePopup] _G.toggleDailyTasks missing") end end,
	  attention = function() return (_G.dailyTasksPending and _G.dailyTasksPending()) == true end },
	{ label = "Journal",     emoji = "\xF0\x9F\x93\x96",  action = function() if _G.toggleJournal then _G.toggleJournal() else print("[MorePopup] _G.toggleJournal missing") end end },
	{ label = "Rebirth",     emoji = "\xE2\x9C\xA8",     action = function() if _G.toggleRebirth then _G.toggleRebirth() else print("[MorePopup] _G.toggleRebirth missing") end end },
	{ label = "Season Pass", emoji = "\xF0\x9F\x8E\x9F", action = function() if _G.toggleSeasonPass then _G.toggleSeasonPass() else print("[MorePopup] _G.toggleSeasonPass missing") end end },
	{ label = "Codes",       emoji = "\xF0\x9F\x8E\xAB", action = function() if _G.openCodesGui then _G.openCodesGui() else print("[MorePopup] _G.openCodesGui missing") end end },
}

--======================================================================
-- BUILD THE POPUP (hidden until toggled). Anchored bottom-left, just RIGHT of
-- the 95px rail, growing upward -- robust without depending on rail internals.
--======================================================================
local popGui = Instance.new("ScreenGui")
popGui.Name = "MorePopupGui"; popGui.ResetOnSpawn = false; popGui.DisplayOrder = 50; popGui.Parent = PlayerGui

local rowH   = math.floor(46*scale)
local width  = math.floor(210*scale)
local header = math.floor(34*scale)
local pad    = 8
local panel = mkFrame(popGui, {
	Name = "Panel",
	Size = UDim2.new(0, width, 0, header + pad + (#MORE_ENTRIES*(rowH+6)) + pad),
	Position = UDim2.new(0, math.floor(115*scale), 1, -12),
	AnchorPoint = Vector2.new(0, 1),
	BackgroundColor3 = Color3.fromRGB(40, 32, 60),
	Visible = false,
})
mkCorner(panel, 14); mkStroke(panel, Color3.fromRGB(225,70,170), 3)

mkLabel(panel, { Text = "MORE", Font = Enum.Font.FredokaOne, TextSize = math.floor(18*scale), TextColor3 = Color3.new(1,1,1),
	Size = UDim2.new(1,-12,0,header), Position = UDim2.new(0,10,0,2), TextXAlignment = Enum.TextXAlignment.Left })

local list = mkFrame(panel, { Name = "List", BackgroundTransparency = 1,
	Size = UDim2.new(1,-16,1,-(header+pad)), Position = UDim2.new(0,8,0,header) })
do
	local ll = Instance.new("UIListLayout"); ll.FillDirection = Enum.FillDirection.Vertical
	ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Padding = UDim.new(0,6); ll.Parent = list
end

local attentionDots = {} -- rows that expose an attention() flag get a red dot polled below

for i, entry in ipairs(MORE_ENTRIES) do
	local row = mkButton(list, { LayoutOrder = i, Size = UDim2.new(1,0,0,rowH), BackgroundColor3 = Color3.fromRGB(60,50,86),
		Text = "", AutoButtonColor = true })
	mkCorner(row, 10); mkStroke(row, Color3.fromRGB(120,90,160), 1.5)
	mkLabel(row, { Text = entry.emoji, Font = Enum.Font.GothamBold, TextSize = math.floor(22*scale),
		Size = UDim2.fromOffset(rowH, rowH), Position = UDim2.new(0,6,0,0), TextXAlignment = Enum.TextXAlignment.Center })
	mkLabel(row, { Text = entry.label, Font = Enum.Font.GothamBold, TextSize = math.floor(16*scale), TextColor3 = Color3.new(1,1,1),
		Size = UDim2.new(1,-(rowH+16),1,0), Position = UDim2.new(0,rowH+8,0,0), TextXAlignment = Enum.TextXAlignment.Left })

	if entry.attention then
		local dot = mkFrame(row, { Name="Dot", Size = UDim2.fromOffset(16,16), AnchorPoint = Vector2.new(1,0.5),
			Position = UDim2.new(1,-10,0.5,0), BackgroundColor3 = Color3.fromRGB(225,50,50), Visible = false })
		mkCorner(dot, 8)
		attentionDots[#attentionDots+1] = { dot = dot, fn = entry.attention }
	end

	row.Activated:Connect(function()
		playClick()
		panel.Visible = false          -- close the popup, then run the entry's real toggler
		pcall(entry.action)
	end)
end

--======================================================================
-- TOGGLER + signal listener (what JustButtons' MORE button calls/fires)
--======================================================================
local function setOpen(v) panel.Visible = v end
_G.toggleMorePopup = function() setOpen(not panel.Visible) end

-- also honor the fallback BindableEvent path JustButtons uses if the global is unset
do
	local sig = PlayerGui:FindFirstChild("OpenMorePopup")
	if not sig then sig = Instance.new("BindableEvent"); sig.Name = "OpenMorePopup"; sig.Parent = PlayerGui end
	sig.Event:Connect(function() _G.toggleMorePopup() end)
end

-- NOTE: no "tap outside to close" here on purpose -- InputBegan would fire on the
-- SAME click as the MORE button's MouseButton1Click and fight the toggle
-- (close-then-reopen). The MORE button toggles; clicking an entry closes it.

-- poll attention flags (Daily Tasks / crate) -> red dot on the row
task.spawn(function()
	while true do
		for _, d in ipairs(attentionDots) do
			local ok, on = pcall(d.fn)
			d.dot.Visible = ok and on == true
		end
		task.wait(1)
	end
end)

print("[MorePopup] _G.toggleMorePopup defined -- MORE opens: Pets / Daily Crate / Daily Tasks / Rebirth / Season Pass / Codes")
