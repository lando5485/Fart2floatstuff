--[[
	WormholeClient.client.luau  (StarterPlayerScripts.WormholeClient)

	The Wormhole travel menu for THIS realm (the island tower). The menu HUD is ported from the Space Realm's
	wormhole; the warp CINEMATIC + SOUND come from the shared WarpEffect module (WarpEffect.luau). The DATA is
	rewired to this place: destinations are the 11 tower islands PLUS the three off-ladder quest islands
	(16 Candy Mine, 18 Pancake Arena, 19 Sugarbeet Farm), the gate is the "HighestIsland" player attribute, and
	the teleport is our own server-authoritative WormholeWarp RemoteFunction (validates reached-island + grounded,
	then places you on that island's stand).

	Opens from MORE+ > "Fast Travel" (MorePopup_AllInOne): _G.toggleWormhole(), or the "OpenWormhole"
	BindableEvent as a fallback. It is NOT on the button rail -- the PETS button took that slot -- so the
	MORE+ card is the only door, and this script must be ready the moment MORE+ can be opened. That is why
	nothing at file scope is allowed to block (see WormholeWarp below).
	Travel only: it never unlocks an island or grants progression -- it just moves you to one you've reached.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- WARP CINEMATIC + SOUND -- the shared module (the new file). play(onPeak) does the ~1.9s tunnel; playSound() whooshes.
local WarpEffect = require(script.Parent:WaitForChild("WarpEffect"))
-- THE REALM CROSSING is a different shot, on purpose. WarpEffect's 1.9s tunnel is the right length for
-- hopping between two islands you can see from each other; leaving the realm entirely is the Food
-- realm's 4.2s portal cinematic, ported whole into RealmOutro.luau. Same shot the player already knows
-- from walking into a portal on Bean Island, so arriving and leaving bookend each other.
local RealmOutro = require(script.Parent:WaitForChild("RealmOutro"))

-- ===== destinations (this realm's 13 candy islands) =====
-- names come from the shared tower module (ReplicatedStorage.Shared.IslandOrder),
-- the same source IslandLayout positions the islands from -- 13 candy islands,
-- bottom (Candy Cane Court) to summit (Sundae Summit).
local IslandOrder = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("IslandOrder"))
-- ============================================================================
-- ⚠ TESTING SWITCH -- EVERY ISLAND UNLOCKED, NO CLIMB REQUIRED
-- ============================================================================
-- true  = every row in the menu is named, lit and warpable from the first second, whatever the
--         player has actually reached. This is for PLAYTESTING THE QUESTS: there are thirteen
--         islands with quests on them and climbing the whole tower to reach the top few is
--         minutes of flying before you can test a single one.
--
-- false = the shipping behaviour. Rows above your HighestSlot read "? ? ?" and refuse -- the
--         NAME is the spoiler, so a locked row does not show one, and each island stays a
--         reveal you fly to.
--
-- ⚠ SET THIS BACK TO false BEFORE PUBLISHING. It does not grant progression, break saves or
-- unlock anything you can buy -- it is travel only -- but it hands a new player the entire
-- tower, names and all, in their first minute, which is most of the game's pacing gone.
-- ⚠ ON, AND ON DELIBERATELY -- the name is legacy, this is not a leftover debug switch.
-- Fast travel is open: every island row is warpable from the start, whatever the quest ledger
-- says. The progression lock lives on the FOOD STANDS instead (Shop_AllInOne's STAND_GATE), so
-- warping to an island you have not earned gets you there and shows you the place -- it just
-- will not sell you anything until you finish that island's quest. Set false to make the warp
-- menu obey the ladder as well.
local UNLOCK_ALL_FOR_TESTING = true

local LADDER = IslandOrder.NAMES -- SLOT-indexed (1 = bottom of the climb): the tower, in climb order

-- ===== THE THREE ISLANDS THAT ARE NOT ON THE LADDER =====
-- island16, island18 and island19 are built, populated and have full quests on them -- the Candy
-- Mine explosion, the Pancake Monster and the Broken Tractor -- but they are NOT in
-- SLOT_TO_ISLAND. Nothing in the tower plumbing leads to them: no crossing arrives there, they
-- have no climb position, and until now the only way onto one was to already be standing on it.
-- That made the three biggest quests in the realm the three hardest to playtest.
--
-- They are listed after the tower and are NEVER LOCKED. The lock on a tower row means "you have
-- not climbed this far yet", and that sentence has no meaning for an island the climb does not
-- pass through -- there is no height to reach, so there is nothing to gate on. Their parts do
-- replicate at any distance (IslandStreaming's EXTRA_PERSIST lists exactly the same models for
-- the same reason their quests needed it), so arrivalPoint can always find a spawn brick.
--
-- ⚠ WHICH ISLANDS THOSE ARE HAS CHANGED. The space-economy port needed twelve rungs, each
-- hosting a quest that funds the next gut, and it took two of them from this list: island16
-- (Candy Mine) is now slot 8, island18 (Pancake Arena) is now slot 7. Both appear in LADDER
-- above like any other rung, and listing them here as well would put them in the menu twice --
-- once lockable, once not.
--
-- ⚠ THERE ARE NO OFF-LADDER ISLANDS ANY MORE. The space-economy port needed thirteen rungs,
-- each hosting a quest that funds the next gut, and the realm has exactly thirteen
-- quest-bearing islands -- so island16, island18 and island19 were all promoted onto the tower
-- (slots 8, 7 and 12). They appear in LADDER above like any other rung now, and listing them
-- here as well would put them in the menu twice, once lockable and once not.
--
-- island2 ("Chocolate Chasm") is not listed either. It was slot 7 until the Jelly Tower was
-- removed, but the deeper reason is that NO MODEL NAMED island2 WAS EVER BUILT -- see the
-- islandExists() refusal further down, which exists precisely because this row used to offer
-- the place, play the whole warp cinematic and then fail silently in arriveLocally. A menu row
-- that can only ever say "not built" is worse than no row.
--
-- Kept as an empty table rather than deleted: a future island that sits off the tower is one
-- line away, and the rendering below already handles the list being empty.
local OFF_LADDER = {}

-- ===== THE REALMS THAT CAME BEFORE THIS ONE =====
-- Food -> Space -> Dino -> Candy is the order a player actually arrives in, and until now the trip
-- was one-way: this realm has a Dino PORTAL on island 1 and nothing at all back to Food or Space,
-- so a player who climbed three realms to get here could not go and look at any of them again
-- without leaving the experience and rejoining from the game page.
--
-- They are rows in this menu because this menu is already "the place that moves you", and a realm
-- is just a further destination than an island. They are NEVER LOCKED: you cannot be standing in
-- the Candy realm without having come through the ones before it.
--
-- ⚠ THE CLIENT NEVER NAMES A PLACE ID. Each row sends a KEY to RealmTravelEvent and the server
-- looks it up (RealmTravel.server.lua). A client that can name its own destination is a client that
-- can teleport itself into any experience on the platform.
local REALM_ROWS = {
	{ realm = "food",  name = "Food Realm",      color = Color3.fromRGB(120, 200, 120) },
	{ realm = "space", name = "Space Realm",     color = Color3.fromRGB(130, 150, 250) },
	{ realm = "dino",  name = "Dinosaur Realm",  color = Color3.fromRGB(215, 150, 90)  },
}

-- one flat row list, so the loop below does not have to know which kind it is building.
-- `slot` is nil for the off-ladder three and for the realms; `realm` is set only on the last three,
-- and every gate in this file reads both that way.
local ROWS = {}
for slot, nm in ipairs(LADDER) do
	ROWS[#ROWS + 1] = { name = nm, model = IslandOrder.SLOT_TO_ISLAND[slot] or slot, slot = slot }
end
for _, e in ipairs(OFF_LADDER) do
	ROWS[#ROWS + 1] = { name = e.name, model = e.model, slot = nil, color = e.color }
end
for _, e in ipairs(REALM_ROWS) do
	ROWS[#ROWS + 1] = { name = e.name, realm = e.realm, slot = nil, color = e.color }
end

-- ===== SECTION HEADINGS =====
-- Tagged onto the FIRST row of each group rather than inserted as their own entries, so ROWS stays a
-- list of destinations and nothing that iterates it has to skip over dividers.
--
-- The three realms needed this. Warping to an island and leaving the realm entirely are not the same
-- kind of act -- one moves you a few thousand studs inside a place you are already in, the other ends
-- the session here and loads another game -- and as one unbroken list of seventeen identical rows the
-- only thing saying so was the wording of the status text on the right. A player scrolling past
-- "Sugarbeet Farm" straight into "Food Realm" has no reason to expect the next tap to do something
-- categorically bigger.
ROWS[1].section      = "\u{1F36D}  CANDY ISLANDS"
ROWS[1].sectionNote  = "warp around this realm"
ROWS[1].sectionColor = ACCENT                              -- the menu's own pink: chrome, not a place

do
	local firstRealm = ROWS[#LADDER + #OFF_LADDER + 1]
	firstRealm.section      = "\u{1FA90}  OTHER REALMS"
	firstRealm.sectionNote  = "leave the Candy realm entirely"
	-- A DIFFERENT COLOUR ON PURPOSE, and NOT the first realm's green. Taking `col` from the row below
	-- would have made this heading mean "Food Realm" rather than "everything under here is a realm" --
	-- and it would silently change the day the row order changes. Cold violet reads as ELSEWHERE
	-- against a menu that is otherwise entirely pink, which is the whole job of the break.
	firstRealm.sectionColor = Color3.fromRGB(158, 176, 255)
end
-- a colour per island (row icon disc + stroke), candy-bright up the tower
local ISLAND_COLORS = {
	Color3.fromRGB(240, 100, 110), Color3.fromRGB(170, 110, 220), Color3.fromRGB(210, 160, 90),
	Color3.fromRGB(120, 200, 120), Color3.fromRGB(250, 160, 190), Color3.fromRGB(110, 200, 90),
	Color3.fromRGB(150, 110, 80), Color3.fromRGB(180, 220, 240), Color3.fromRGB(245, 245, 250),
	Color3.fromRGB(220, 170, 90), Color3.fromRGB(140, 200, 250), Color3.fromRGB(90, 80, 90),
	Color3.fromRGB(250, 220, 120),
}

-- ===== Palette (CANDY) =====
-- Was the Space-Realm wormhole look (navy #121834 / violet accent). Rotated into the raspberry the rest
-- of this realm's menus now use -- the same +110 degree hue turn applied to the hub family, so the panel,
-- header and wells keep exactly the depth relationships they were designed with, just in candy.
--
-- ISLAND_COLORS above is deliberately NOT rotated: those are per-island IDENTITY (the icy islands are
-- meant to read icy), not chrome. Turning the two blue ones pink would say the wrong thing about them.
local PANEL      = Color3.fromRGB(52, 18, 30)
local PANEL_DEEP = Color3.fromRGB(32, 10, 18)
local ACCENT     = Color3.fromRGB(255, 120, 190) -- candy pink, replacing the violet
local TITLE_BAR  = Color3.fromRGB(68, 20, 46)
local WHITE      = Color3.fromRGB(255, 242, 248)
local LOCK_GREY  = Color3.fromRGB(66, 46, 53)
local MUTED      = Color3.fromRGB(195, 150, 168)

-- ===== gate + position state =====
-- Highest island the player has UNLOCKED (reached). Clamped to a minimum of 1 so Bean Farm (island 1) is ALWAYS
-- unlocked/warpable, even before the HighestIsland attribute has replicated. Islands above this stay locked.
local function highestIsland() return math.max(1, math.floor(tonumber(player:GetAttribute("HighestIsland")) or 1)) end
-- The gate the ROWS actually use. The menu is listed by CLIMB SLOT, and Candy's slots are a fixed
-- scramble of the island model numbers (slot 2 = island9...). Comparing a row's slot against the
-- HighestIsland MODEL number -- which is what this file shipped doing -- unlocks and locks the wrong
-- rows: reaching Gumdrop Grove (island9) read as "you may warp to rows 1..9". FlightEconomy publishes
-- HighestSlot for exactly this; the fallback converts the model attribute for a save from before it.
-- ⚠ THE LOCK IS THE QUEST LEDGER, NOT WHERE YOU HAVE BEEN.
-- UnlockedSlot (GutProgression) is the contiguous run of finished quests + 1, and it is what
-- BuyFood and FlightEconomy enforce -- so the menu has to draw its padlocks from the SAME number
-- or the rows lie. HighestSlot is kept only as the fallback for a save from before UnlockedSlot
-- existed, and the HighestIsland conversion below it for one older still.
local function highestSlot()
	local q = math.floor(tonumber(player:GetAttribute("UnlockedSlot")) or 0)
	if q >= 1 then return q end
	local s = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 0)
	if s >= 1 then return s end
	local isl = math.floor(tonumber(player:GetAttribute("HighestIsland")) or 1)
	return IslandOrder.ISLAND_TO_SLOT[isl] or 1
end
-- island MODEL number -> that island's Y height, which is how "Here" is worked out.
--
-- SEEDED FROM THE SHARED TOWER, not from StandsReadyEvent. That event is dead in this realm --
-- nothing on the server ever fires it (Shop_AllInOne says the same in its own comment) -- so this
-- table stayed EMPTY, currentIsland() always returned nil, and no row ever said "Here". You could
-- also warp to the island you were already standing on, since the guard that blocks that compares
-- against the same nil.
--
-- IslandOrder.SLOT_POS is the authority IslandLayout positions the islands from, so it is right by
-- construction and needs no server round trip. The stand sits a few studs above the model origin
-- and the gaps between islands are thousands of studs, so the 200-stud match below is unambiguous.
local islandY = {}
for slot, num in ipairs(IslandOrder.SLOT_TO_ISLAND) do
	local p = IslandOrder.SLOT_POS[slot]
	if p then islandY[num] = p.Y end
end
-- THE OFF-LADDER THREE HAVE NO SLOT_POS, so their height has to be measured off the world. They
-- are the one case where that works without help: IslandLayout never moves them (it iterates the
-- ladder), and EXTRA_PERSIST keeps their parts replicated at any distance, so the model's pivot is
-- real rather than the origin a partless model reports. Without this they are simply absent from
-- currentIsland(), and standing on island19 would show the nearest TOWER island as "Here" -- and
-- let you warp to the island you are already on.
task.spawn(function()
	for _ = 1, 30 do
		local missing = false
		for _, e in ipairs(OFF_LADDER) do
			if not islandY[e.model] then
				local m = workspace:FindFirstChild("island" .. e.model)
				if m and m:IsA("Model") and #m:GetChildren() > 0 then
					islandY[e.model] = m:GetPivot().Position.Y
				else
					missing = true
				end
			end
		end
		if not missing then break end
		task.wait(2)
	end
end)

-- ...and if a StandsReadyEvent ever does start firing, its measured heights win.
task.spawn(function()
	local sre = ReplicatedStorage:FindFirstChild("StandsReadyEvent") or ReplicatedStorage:WaitForChild("StandsReadyEvent", 30)
	if sre then
		sre.OnClientEvent:Connect(function(data)
			for num, pos in pairs(data) do islandY[tonumber(num)] = pos.y end
		end)
	end
end)
local function currentIsland()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not next(islandY) then return nil end
	local best, bestD = nil, math.huge
	for num, y in pairs(islandY) do
		local d = math.abs(hrp.Position.Y - y)
		if d < bestD then bestD, best = d, num end
	end
	return (bestD < 200) and best or nil
end
-- The realm remote, resolved in the BACKGROUND for the same reason WormholeWarp is below: this
-- script has to be ready the moment MORE+ can be opened, so nothing at file scope may block. A nil
-- here simply means the realm rows say so instead of pretending to travel.
local RealmTravel
task.spawn(function()
	RealmTravel = ReplicatedStorage:WaitForChild("RealmTravelEvent", 30)
	if not RealmTravel then
		warn("[Wormhole] RealmTravelEvent never arrived -- is RealmTravel.server.lua running? "
			.. "The three realm rows will refuse rather than teleport.")
	end
end)

local function isGrounded()
	if _G.isFlying then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
end

-- Our server-authoritative warp remote -- OPTIONAL here, and resolved in the BACKGROUND.
--
-- This was a blocking WaitForChild("WormholeWarp", 30), and this realm has no WormholeService to
-- create it (see arriveLocally below -- placing the player client-side is the intended path). So
-- the wait always ran its full thirty seconds, and it held THE ENTIRE SCRIPT: for the first 30
-- seconds of every session there was no menu, no _G.toggleWormhole, and no OpenWormhole listener.
-- Tapping MORE+ > Fast Travel in that window fired a BindableEvent nobody was connected to and
-- did nothing at all -- the door was dead exactly when a new player is most likely to try it.
-- (The boot log shows it: "[Wormhole][client] online" printed at +30s, dead last of every script.)
--
-- Resolved on its own thread, the menu is up immediately and the remote is simply used if a
-- WormholeService ever appears. warpTo reads this as an upvalue, so a late arrival is picked up.
local WormholeWarp = ReplicatedStorage:FindFirstChild("WormholeWarp")
task.spawn(function()
	WormholeWarp = ReplicatedStorage:WaitForChild("WormholeWarp", 30) or WormholeWarp
end)

-- ===== MENU GUI =====
local gui = Instance.new("ScreenGui")
gui.Name = "WormholeMenu"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 160; gui.Enabled = false
gui.Parent = PlayerGui

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"; backdrop.Size = UDim2.new(1, 0, 1, 0); backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.45; backdrop.AutoButtonColor = false; backdrop.Text = ""; backdrop.Active = true; backdrop.Parent = gui

local panel = Instance.new("Frame")
-- 700x520 at (0.5, 0.5, -45): the house panel frame every main menu in this realm uses (Pet Hub, Shop,
-- Daily Tasks, Settings...). This was the last menu on its own geometry -- a 460-capped narrow column.
panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.new(0.5, 0, 0.5, -45); panel.Size = UDim2.new(0, 700, 0, 520)
panel.BackgroundColor3 = PANEL; panel.BorderSizePixel = 0; panel.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 20); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = ACCENT; s.Thickness = 2; s.Transparency = 0.2; s.Parent = panel
end
local panelScale = Instance.new("UIScale"); panelScale.Scale = 0.7; panelScale.Parent = panel -- pop-in

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 56); titleBar.BackgroundColor3 = TITLE_BAR; titleBar.BorderSizePixel = 0; titleBar.Parent = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 20); c.Parent = titleBar
	local mask = Instance.new("Frame")
	mask.AnchorPoint = Vector2.new(0, 1); mask.Position = UDim2.new(0, 0, 1, 0); mask.Size = UDim2.new(1, 0, 0, 20)
	mask.BackgroundColor3 = TITLE_BAR; mask.BorderSizePixel = 0; mask.Parent = titleBar
end
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1; title.AnchorPoint = Vector2.new(0, 0.5); title.Position = UDim2.new(0, 16, 0.5, 0); title.Size = UDim2.new(1, -70, 1, -14)
title.Font = Enum.Font.FredokaOne; title.Text = "\u{1F300} WORMHOLE"; title.TextColor3 = WHITE; title.TextScaled = true; title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar
do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 26; cns.Parent = title
	local st = Instance.new("UIStroke"); st.Color = Color3.new(0, 0, 0); st.Thickness = 1.5; st.Transparency = 0.4; st.Parent = title end
local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5); closeBtn.Position = UDim2.new(1, -12, 0.5, 0); closeBtn.Size = UDim2.new(0, 36, 0, 36)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 70); closeBtn.Font = Enum.Font.FredokaOne; closeBtn.Text = "X"; closeBtn.TextColor3 = WHITE; closeBtn.TextScaled = true
closeBtn.Parent = titleBar
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = closeBtn end
-- BACK, left of the X -- realm 1's header pattern via the shared kit (BackButtonKit.client.luau).
-- Deferred: the kit is a sibling LocalScript and load order between them is not guaranteed.
task.defer(function()
	for _ = 1, 40 do
		if _G.addBackButton then _G.addBackButton(closeBtn); return end
		task.wait(0.1)
	end
end)


local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1; subtitle.AnchorPoint = Vector2.new(0.5, 0); subtitle.Position = UDim2.new(0.5, 0, 0, 62); subtitle.Size = UDim2.new(1, -32, 0, 22)
subtitle.Font = Enum.Font.GothamMedium; subtitle.TextColor3 = MUTED; subtitle.TextScaled = true
-- names BOTH halves: the list is no longer only islands, and a subtitle that says it is would be the
-- one line a player reads before deciding the realms at the bottom are not what they are looking for
subtitle.Text = "Warp to an island you've reached \u{2022} or travel back to another realm"
subtitle.Parent = panel
do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 16; cns.Parent = subtitle end

local scroll = Instance.new("ScrollingFrame")
scroll.AnchorPoint = Vector2.new(0.5, 0); scroll.Position = UDim2.new(0.5, 0, 0, 92); scroll.Size = UDim2.new(1, -24, 1, -104)
scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 6; scroll.ScrollBarImageColor3 = ACCENT
scroll.CanvasSize = UDim2.new(0, 0, 0, 0); scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; scroll.Parent = panel
do local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 8); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = scroll end

local warping = false
local closeMenu      -- fwd
local warpTo         -- fwd
local travelToRealm  -- fwd: the three realm rows (needs the remote + the toast, both below)
local showNotBuilt   -- fwd: the toast for an island that has no model in this place

-- IS THERE ACTUALLY AN ISLAND OF THIS NUMBER? Cheap enough to call on every refresh (one
-- FindFirstChild), and it has to be re-asked rather than cached: IslandLayout moves and renames
-- nothing at runtime, but a model can arrive late, and a row that locked itself out at boot for an
-- island that showed up a second later would stay wrong for the whole session.
local function islandExists(n)
	if not n then return false end
	if workspace:FindFirstChild("island" .. n) then return true end
	for _, d in ipairs(workspace:GetChildren()) do
		if d:IsA("Model") then
			local num = string.lower(d.Name):match("^island[ _]?(%d+)$")
			if num and tonumber(num) == n then return true end
		end
	end
	return false
end

-- ===== ONE SECTION HEADING =====
-- A label over a rule that fades out to the right, in the section's own colour. Deliberately NOT a
-- row: no background, no stroke, no button -- the whole job is to look like something you cannot tap,
-- so it never reads as a destination that has stopped working.
--
-- `gap` is what actually does the separating. The first heading sits tight under the subtitle; every
-- later one carries 18px of dead space above it, which is more than twice the 8px the list layout puts
-- between rows -- enough that the break is obvious while scrolling past at speed.
local function sectionHeader(text, note, order, colour, gap)
	local h = Instance.new("Frame")
	h.Name = "Section"; h.LayoutOrder = order
	h.Size = UDim2.new(1, -6, 0, gap and 52 or 34)
	h.BackgroundTransparency = 1; h.Parent = scroll

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1; lbl.AnchorPoint = Vector2.new(0, 1)
	lbl.Position = UDim2.new(0, 4, 1, note and -20 or -9)
	lbl.Size = UDim2.new(1, -8, 0, 18)
	lbl.Font = Enum.Font.FredokaOne; lbl.Text = text; lbl.TextColor3 = colour
	lbl.TextScaled = true; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = h
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 16; c.Parent = lbl end

	if note then
		local n = Instance.new("TextLabel")
		n.BackgroundTransparency = 1; n.AnchorPoint = Vector2.new(0, 1)
		n.Position = UDim2.new(0, 4, 1, -8); n.Size = UDim2.new(1, -8, 0, 13)
		n.Font = Enum.Font.GothamMedium; n.Text = note; n.TextColor3 = MUTED
		n.TextScaled = true; n.TextXAlignment = Enum.TextXAlignment.Left; n.Parent = h
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 12; c.Parent = n end
	end

	local rule = Instance.new("Frame")
	rule.AnchorPoint = Vector2.new(0, 1); rule.Position = UDim2.new(0, 4, 1, -2)
	rule.Size = UDim2.new(1, -8, 0, 2); rule.BackgroundColor3 = colour
	rule.BackgroundTransparency = 0.35; rule.BorderSizePixel = 0; rule.Parent = h
	do
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = rule
	end
end

-- Build one row per island; returns a refresher.
local rowRefreshers = {}
for i, entry in ipairs(ROWS) do
	-- `slot` is the CLIMB POSITION (what the tower is ordered and gated by); `modelNum` is the workspace
	-- model that row actually points at. Everything the player SEES keys off the row; everything that
	-- MOVES or LOCATES them keys off the model. Conflating the two -- which this file shipped doing --
	-- warped "Gumdrop Grove" (slot 2 = island9) to workspace.island2, a different island 27,000 studs
	-- up the tower. `slot` is nil on the three off-ladder rows: they have no climb position at all.
	local name     = entry.name
	local slot     = entry.slot
	local modelNum = entry.model
	local realmKey = entry.realm
	local col      = entry.color or ISLAND_COLORS[i] or ACCENT
	-- x10 so a heading can sit at (order - 5) between two rows. UIListLayout only compares these, so
	-- the gaps cost nothing and leave room to slot anything else in later without renumbering.
	if entry.section then
		sectionHeader(entry.section, entry.sectionNote, i * 10 - 5, entry.sectionColor or col, i > 1)
	end

	local row = Instance.new("TextButton")
	row.Name = "Island" .. i; row.LayoutOrder = i * 10; row.Size = UDim2.new(1, -6, 0, 50); row.AutoButtonColor = true; row.Text = ""
	row.BackgroundColor3 = PANEL_DEEP; row.Parent = scroll
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = row end
	local rowStroke = Instance.new("UIStroke"); rowStroke.Color = ACCENT; rowStroke.Thickness = 1.5; rowStroke.Transparency = 0.4; rowStroke.Parent = row

	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icon"; iconHolder.AnchorPoint = Vector2.new(0, 0.5); iconHolder.Position = UDim2.new(0, 11, 0.5, 0); iconHolder.Size = UDim2.new(0, 30, 0, 30)
	iconHolder.BackgroundTransparency = 1; iconHolder.Parent = row
	local disc = Instance.new("TextLabel")
	disc.AnchorPoint = Vector2.new(0.5, 0.5); disc.Position = UDim2.new(0.5, 0, 0.5, 0); disc.Size = UDim2.new(1, 0, 1, 0)
	disc.BackgroundColor3 = col; disc.Font = Enum.Font.FredokaOne; disc.Text = tostring(i); disc.TextColor3 = Color3.new(1, 1, 1); disc.TextScaled = true; disc.Parent = iconHolder
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = disc
		local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(10, 12, 24); s.Thickness = 1; s.Transparency = 0.2; s.Parent = disc
		local p = Instance.new("UIPadding"); p.PaddingTop = UDim.new(0, 4); p.PaddingBottom = UDim.new(0, 4); p.Parent = disc end
	local lockOverlay = Instance.new("Frame")
	lockOverlay.Name = "LockDim"; lockOverlay.AnchorPoint = Vector2.new(0.5, 0.5); lockOverlay.Position = UDim2.new(0.5, 0, 0.5, 0); lockOverlay.Size = UDim2.new(1, 0, 1, 0)
	lockOverlay.BackgroundColor3 = Color3.fromRGB(54, 58, 74); lockOverlay.BackgroundTransparency = 0.12; lockOverlay.BorderSizePixel = 0; lockOverlay.ZIndex = 6; lockOverlay.Visible = false; lockOverlay.Parent = iconHolder
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = lockOverlay end

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1; nameLbl.AnchorPoint = Vector2.new(0, 0.5); nameLbl.Position = UDim2.new(0, 50, 0.5, 0); nameLbl.Size = UDim2.new(0.5, 0, 1, -12)
	nameLbl.Font = Enum.Font.FredokaOne; nameLbl.Text = name; nameLbl.TextColor3 = WHITE; nameLbl.TextScaled = true; nameLbl.TextXAlignment = Enum.TextXAlignment.Left; nameLbl.Parent = row
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 22; cns.Parent = nameLbl end

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Name = "Status"; statusLbl.BackgroundTransparency = 1; statusLbl.AnchorPoint = Vector2.new(1, 0.5); statusLbl.Position = UDim2.new(1, -14, 0.5, 0); statusLbl.Size = UDim2.new(0.5, -10, 1, -14)
	statusLbl.Font = Enum.Font.GothamBold; statusLbl.Text = ""; statusLbl.TextColor3 = MUTED; statusLbl.TextScaled = true; statusLbl.TextXAlignment = Enum.TextXAlignment.Right; statusLbl.Parent = row
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 15; cns.Parent = statusLbl end

	row.Activated:Connect(function()
		if warping then return end
		if realmKey then
			if travelToRealm then travelToRealm(realmKey, name) end
			return
		end
		-- no slot means off the ladder, which means nothing to reach and nothing to gate
		if slot and slot > highestSlot() and not UNLOCK_ALL_FOR_TESTING then return end
		-- AN ISLAND THAT IS NOT IN THE WORKSPACE CANNOT BE TRAVELLED TO, whatever the gate says.
		-- island2 is exactly this today: IslandOrder has it at slot 7 but no model of that name was
		-- ever built, so the row offered "Chocolate Chasm", played the whole warp cinematic and then
		-- failed silently in arriveLocally. Refusing up front, with the reason on the row, is the
		-- honest version -- and the row lights up on its own the moment the model appears.
		if not islandExists(modelNum) then showNotBuilt(); return end
		if currentIsland() == modelNum then return end  -- model vs model
		if warpTo then warpTo(modelNum, name) end       -- the warp wants the workspace model
	end)

	rowRefreshers[i] = function()
		-- ---- a realm row: never locked, never "here", and it says where it goes ----
		if realmKey then
			row.BackgroundColor3 = PANEL_DEEP; rowStroke.Color = col; rowStroke.Transparency = 0.25
			lockOverlay.Visible = false; nameLbl.TextColor3 = WHITE; nameLbl.Text = name
			disc.Text = "\u{1FA90}"      -- a ringed planet, so the three realms read apart from the islands
			statusLbl.Text = "Travel \u{27A4}"; statusLbl.TextColor3 = col
			row.Active = true; row.AutoButtonColor = true
			return
		end
		local reached = UNLOCK_ALL_FOR_TESTING or (slot == nil) or slot <= highestSlot()
		local here = currentIsland() == modelNum
		-- ---- reached, but the model is not in this place ----
		if reached and not islandExists(modelNum) then
			row.BackgroundColor3 = LOCK_GREY; rowStroke.Color = Color3.fromRGB(70, 74, 92)
			rowStroke.Transparency = 0.5; lockOverlay.Visible = true; nameLbl.TextColor3 = MUTED
			nameLbl.Text = name
			statusLbl.Text = "Not built yet"; statusLbl.TextColor3 = MUTED
			row.Active = false; row.AutoButtonColor = false
			return
		end
		if reached then
			row.BackgroundColor3 = PANEL_DEEP; rowStroke.Color = col; rowStroke.Transparency = 0.25; lockOverlay.Visible = false; nameLbl.TextColor3 = WHITE
			nameLbl.Text = name
			statusLbl.Text = here and "Here" or "Warp \u{27A4}"
			statusLbl.TextColor3 = here and MUTED or col
			row.Active = true; row.AutoButtonColor = not here
		else
			-- THE NAME IS THE SPOILER, so a locked row doesn't show one. Naming "Bakery Summit" from the
			-- first minute gives the whole tower away; "? ? ?" makes each island a reveal you fly to. The
			-- slot NUMBER stays visible -- players still need to see how far up the ladder goes.
			row.BackgroundColor3 = LOCK_GREY; rowStroke.Color = Color3.fromRGB(70, 74, 92); rowStroke.Transparency = 0.5; lockOverlay.Visible = true; nameLbl.TextColor3 = MUTED
			nameLbl.Text = "? ? ?"
			statusLbl.Text = "\u{1F512} Reach it first"; statusLbl.TextColor3 = MUTED
			row.Active = false; row.AutoButtonColor = false
		end
	end
end

--======================================================================
-- OPEN / CLOSE / WARP
--======================================================================
local isOpen = false
local function refreshMenu() for _, fn in pairs(rowRefreshers) do fn() end end
local function openMenu()
	if warping or isOpen then return end
	isOpen = true
	refreshMenu()
	gui.Enabled = true
	panelScale.Scale = 0.7
	pcall(function() TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play() end)
	if _G.MainMenuManager and _G.MainMenuManager.notifyOpened then _G.MainMenuManager.notifyOpened("Wormhole") end
end
closeMenu = function()
	if not isOpen then return end
	isOpen = false
	gui.Enabled = false
	if _G.MainMenuManager and _G.MainMenuManager.notifyClosed then _G.MainMenuManager.notifyClosed("Wormhole") end
end
if _G.MainMenuManager and _G.MainMenuManager.register then _G.MainMenuManager.register("Wormhole", function() gui.Enabled = false; isOpen = false end) end
_G.toggleWormhole = function() if isOpen then closeMenu() else openMenu() end end

-- "land first" toast (own ScreenGui so it shows over the closed menu)
local landToastGui = Instance.new("ScreenGui"); landToastGui.Name = "WormholeLandFirst"; landToastGui.ResetOnSpawn = false; landToastGui.IgnoreGuiInset = true; landToastGui.DisplayOrder = 9500; landToastGui.Enabled = false; landToastGui.Parent = PlayerGui
local landToast = Instance.new("TextLabel"); landToast.AnchorPoint = Vector2.new(0.5, 0); landToast.Position = UDim2.new(0.5, 0, 0, 90); landToast.Size = UDim2.new(0, 470, 0, 52)
landToast.BackgroundColor3 = PANEL; landToast.BackgroundTransparency = 0.05; landToast.Font = Enum.Font.FredokaOne; landToast.Text = "\u{1FA90}  Land on an island to use the wormhole!"; landToast.TextColor3 = WHITE; landToast.TextScaled = true; landToast.Parent = landToastGui
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = landToast
	local s = Instance.new("UIStroke"); s.Color = ACCENT; s.Thickness = 2; s.Parent = landToast
	local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 22; cns.Parent = landToast end
local landTok = 0
-- One label, one token, three messages. A second ScreenGui for a second two-second toast would be a
-- second thing to keep on top of the closed menu and a second thing to hide on respawn.
local function toast(text, secs)
	landTok += 1; local mine = landTok
	landToast.Text = text
	landToastGui.Enabled = true
	task.delay(secs or 2.6, function() if landTok == mine then landToastGui.Enabled = false end end)
end
local function showLandFirst() toast("\u{1FA90}  Land on an island to use the wormhole!") end
showNotBuilt = function() toast("\u{1F6A7}  That island isn't built yet -- nothing to warp to!", 3) end

-- ===== ARRIVAL POINT =====================================================
-- Every island's waypoint is its SPAWN BRICK: a SpawnLocation, or any part with
-- "spawn" in the name, inside that island's model. Falls back to the island's top
-- surface if it hasn't got one.
local function findIslandModel(n)
	local exact = workspace:FindFirstChild("island" .. n)
	if exact then return exact end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") then
			local num = string.lower(d.Name):match("^island[ _]?(%d+)")
			if num and tonumber(num) == n then return d end
		end
	end
	return nil
end

local function topOf(inst)
	local cf, sz
	if inst:IsA("Model") then cf, sz = inst:GetBoundingBox() else cf, sz = inst.CFrame, inst.Size end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { inst }
	local hit = workspace:Raycast(cf.Position + Vector3.new(0, sz.Y, 0), Vector3.new(0, -sz.Y * 2.5, 0), rp)
	local base = (hit and hit.Position) or (cf.Position + Vector3.new(0, sz.Y * 0.5, 0))
	return base + Vector3.new(0, 5, 0)
end

-- WHERE THE SOLVED TOWER SAYS THIS ISLAND IS. IslandOrder.SLOT_POS is what IslandLayout positions
-- the islands FROM, so it is right by construction and needs no parts to be loaded -- which is the
-- whole point of having it here. The off-ladder three (16/18/19) have no slot and so no entry; they
-- are in IslandStreaming's EXTRA_PERSIST, so their parts are always replicated and the model route
-- below always works for them.
local function ladderPos(n)
	local slot = IslandOrder.ISLAND_TO_SLOT[n]
	local p = slot and IslandOrder.SLOT_POS[slot]
	if not p then return nil end
	return (typeof(p) == "Vector3") and p or Vector3.new(p[1], p[2], p[3])
end

local function arrivalPoint(n)
	local isle = findIslandModel(n)
	if isle then
		-- the spawn brick is the waypoint
		for _, d in ipairs(isle:GetDescendants()) do
			if d:IsA("BasePart") and (d:IsA("SpawnLocation") or string.lower(d.Name):find("spawn", 1, true)) then
				return topOf(d)
			end
		end
		-- A MODEL WITH NO PARTS IS NOT A POSITION. With StreamingEnabled a distant island replicates as
		-- an EMPTY Model: it exists, GetBoundingBox() reports a zero box at the ORIGIN, and topOf would
		-- cheerfully hand back a point near (0,0,0) -- which is under island 1, thousands of studs from
		-- where you asked to go. So the model is only trusted once it has real geometry.
		if isle:FindFirstChildWhichIsA("BasePart", true) then return topOf(isle) end
	end
	-- ...otherwise fall back to the solved ladder height, lifted clear of the island's own deck.
	local p = ladderPos(n)
	if p then return p + Vector3.new(0, 12, 0) end
	return nil
end

-- Place the player ourselves. CandyRealm has no WormholeService (it lives in the other
-- place), so InvokeServer was failing inside a pcall and quietly doing nothing -- the
-- cinematic played and you never moved. The client owns its own character, so this
-- replicates fine.
local function arriveLocally(islandNum)
	local char = player.Character
	if not char then return false end

	-- ===== STREAM THE DESTINATION IN FIRST =====
	-- This is what made the far half of the tower unreliable. Warping is the one moment a player
	-- crosses tens of thousands of studs instantly, so the island they are landing on is by
	-- definition the one furthest from anything the engine has bothered to replicate -- and the old
	-- code read the model, found it empty, and gave up. RequestStreamAroundAsync is the one
	-- client-side call that says "pull this region in NOW"; it is the same fix QuestRetainer uses on
	-- the quests, for the identical reason. Asked for at the solved ladder position, so it works
	-- even when the model is the empty shell we are trying to fill.
	local want = ladderPos(islandNum)
	if want then pcall(function() player:RequestStreamAroundAsync(want, 6) end) end

	local pos = arrivalPoint(islandNum)
	if not pos then
		-- one more look, a beat later: the request above may have landed just after we read.
		task.wait(0.6)
		pos = arrivalPoint(islandNum)
	end
	if not pos then
		warn(("[Wormhole] island%d could not be located -- no model in Workspace and no ladder "
			.. "position (it is off the ladder AND not built). Nothing to place you on.")
			:format(islandNum))
		return false
	end
	char:PivotTo(CFrame.new(pos))
	return true
end

-- ===== TRAVEL TO ANOTHER REALM =====
-- The island rows move you inside this place; these three move you out of it. Same cinematic, so a
-- realm reads as one more destination rather than a mode switch -- but the trip itself belongs to
-- the server (RealmTravel.server.lua), which owns the place ids and re-checks everything.
--
-- IT DOES NOT UNSET `warping`. Every other path through this file clears the flag when the warp is
-- done; here "done" means the player has left the experience, and clearing it would re-arm the menu
-- during the second or two the teleport takes to land -- which is exactly long enough to tap a
-- second realm and queue a second teleport. It clears itself if the trip fails (see the handler).
travelToRealm = function(realmKey, realmName)
	if warping then return end
	if not RealmTravel then
		toast("\u{1F6A7}  Realm travel isn't available on this server.", 3)
		return
	end
	if not isGrounded() then closeMenu(); showLandFirst(); return end
	warping = true
	closeMenu()

	-- NO TOAST HERE ANY MORE. The cinematic hides every ScreenGui in PlayerGui for its whole run and
	-- lands on a card that already says "entering the Food Realm" in that realm's own colours -- a
	-- banner underneath it would be the same sentence twice, and it would be hidden anyway.
	RealmOutro.playSound()
	RealmOutro.play(realmKey)

	-- THE TELEPORT FIRES UNDER THE CARD, not at the peak of the tunnel. The shot holds on the title
	-- card and never tears itself down on the success path -- the place swap is the cut -- so the
	-- request goes at the moment the card has landed and the screen is already full. Half a beat
	-- early, so a fast server does not swap the place while the card is still fading up.
	task.delay(math.max(0.2, RealmOutro.SECONDS - 0.4), function()
		pcall(function() RealmTravel:FireServer(realmKey) end)
	end)

	-- STILL HERE? THEN IT DIDN'T HAPPEN. `warping` is deliberately never cleared on the success path
	-- (see above), and the server answers "error" on every failure it KNOWS about -- but it also
	-- silently drops a request that arrives inside its 6s per-player cooldown, which is exactly what a
	-- double-tapped row produces. Without this that request gets no reply, nothing clears the flag, and
	-- the wormhole is dead for the rest of the session. If this fires we are provably still in the
	-- Candy realm, so the crossing did not happen and the menu has to work again.
	task.delay(RealmOutro.SECONDS + 3, function()
		if warping then
			RealmOutro.abort()
			warping = false
			warn("[Wormhole] realm travel to '" .. tostring(realmKey) .. "' never landed -- menu re-armed")
		end
	end)
end

-- The server answers "traveling" / "locked" / "error". Only the failures need saying: a successful
-- trip ends with the player in another place, where nothing here is running to say anything.
task.spawn(function()
	local ev = ReplicatedStorage:WaitForChild("RealmTravelEvent", 30)
	if not ev then return end
	ev.OnClientEvent:Connect(function(state, key)
		-- ABORT THE SHOT FIRST, THEN SPEAK. The cinematic has every other ScreenGui switched off while
		-- it runs, so a toast raised before the teardown would be raised into a hidden GUI and the
		-- player would sit on a title card for a realm they are not going to.
		if state == "locked" then
			RealmOutro.abort()
			warping = false
			toast("\u{1F6A7}  That realm isn't open yet -- coming soon!", 3)
		elseif state == "error" then
			RealmOutro.abort()
			warping = false
			toast("\u{26A0}\u{FE0F}  Couldn't travel right now -- try again in a moment.", 3)
			warn("[Wormhole] realm travel failed for '" .. tostring(key) .. "'")
		end
	end)
end)

warpTo = function(islandNum, islandName)
	if warping then return end
	-- gate in SLOT space: islandNum is a workspace MODEL number, and model numbers say nothing about
	-- climb order in this scrambled tower (island14 > island9 numerically, but sits higher too only by
	-- coincidence). Convert to the slot and compare like with like.
	--
	-- ⚠ A MISSING SLOT MEANS "OFF THE LADDER", NOT "INFINITELY HIGH". This read `or math.huge`, which
	-- was right when every island was on the ladder and an unknown number could only be a mistake --
	-- but islands 16, 18 and 19 legitimately have no slot, and math.huge would refuse all three
	-- forever while the row above happily offered them.
	local slot = IslandOrder.ISLAND_TO_SLOT[islandNum]
	if slot and slot > highestSlot() and not UNLOCK_ALL_FOR_TESTING then return end
	if not isGrounded() then closeMenu(); showLandFirst(); return end
	warping = true
	closeMenu()
	WarpEffect.playSound() -- warp whoosh (the new file's sound), fired as the warp begins
	WarpEffect.play(function()
		-- server first if it exists (it re-validates reached-island + grounded)...
		local placed = false
		if WormholeWarp then
			placed = pcall(function() WormholeWarp:InvokeServer(islandNum) end)
		end
		-- ...otherwise put them on that island's spawn brick ourselves
		if not placed then arriveLocally(islandNum) end
	end)
	warping = false
end

closeBtn.Activated:Connect(closeMenu)
-- BACKDROP TAPS CLOSE NOTHING. This is the realm's one banned menu behaviour: a panel must only
-- ever be shut by its X. The button stays (it swallows the click so it cannot reach the world or
-- the buttons behind the panel) -- it just does not act on it. Losing a full-screen menu to a
-- mis-aimed tap, mid-scroll or mid-read, is indistinguishable from the menu crashing.
backdrop.MouseButton1Click:Connect(function() end)
-- OpenWormhole BindableEvent (fired by the WORMHOLE side button in CoreClient)
do
	local sig = ReplicatedStorage:FindFirstChild("OpenWormhole")
	if not sig then sig = Instance.new("BindableEvent"); sig.Name = "OpenWormhole"; sig.Parent = ReplicatedStorage end
	sig.Event:Connect(openMenu)
end
player:GetAttributeChangedSignal("HighestIsland"):Connect(function() if isOpen then refreshMenu() end end)
player:GetAttributeChangedSignal("HighestSlot"):Connect(function() if isOpen then refreshMenu() end end) -- the gate the rows actually read

-- (the old text still named 16/18/19 as off-ladder islands: all three were promoted onto the
-- tower by the space-economy port, and island16 is the SUMMIT now -- the row counts always told
-- the truth, the prose did not)
print(("[Wormhole][client] online at boot -- %d rows (%d tower islands, Candy Cane Court up to "
	.. "the Pop Rock Quarry summit, + %d off-ladder + 3 realms: Food, Space, Dinosaur), "
	.. "opens from MORE+ > Fast Travel")
	:format(#ROWS, #LADDER, #OFF_LADDER))
if UNLOCK_ALL_FOR_TESTING then
	warn("[Wormhole] ⚠ UNLOCK_ALL_FOR_TESTING is ON -- every island is named and warpable "
		.. "regardless of progress. Set it to false in WormholeClient.client.luau before publishing.")
end
