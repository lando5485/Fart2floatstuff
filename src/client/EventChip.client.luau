--!nonstrict
-- =================================================================================================
-- EVENT PILL -- the "what is happening right now" chip beside the objective banner.
-- =================================================================================================
--        +-------------------------------------------+  +-------+
--        |  BUY BEANS AT THE FOOD STAND              |  | \xE2\x9B\x88 35s |
--        |  Talk to the farmer                       |  | STORM |
--        +-------------------------------------------+  +-------+
--
-- =================================================================================================
-- BUILD STAMP -- MUST BE FIRST
-- =================================================================================================
-- Rojo only ADDS. A copy of this script baked into the place file runs ALONGSIDE the synced one, and two
-- copies of a HUD element fight: each builds its own GUI, each answers the same broadcast, and whichever
-- one drew last wins the frame. The visible result is a chip that flickers, sits in two places, or never
-- appears at all -- and editing the file changes nothing, because the copy you are editing is not
-- necessarily the copy that drew.
--
-- Same pattern as Campfire / RealmPortals / TopCenterStack: every copy claims a build number on load, and
-- the highest number is the only live one. An older copy sees a newer build and stands down -- it destroys
-- its GUI and every loop and connection it owns returns early forever after. Nothing needs to find the old
-- copy or unload it; it retires itself.
-- ===== VERSION, NOT JUST ORDER =====
-- A plain "last one to load wins" stamp has a failure mode that bit this exact file: if the STALE baked
-- copy happens to load SECOND, it claims the stamp and the good copy stands itself down -- so the newer
-- code is present, running, and deliberately doing nothing. Bump VERSION whenever this file changes in a
-- way that must beat whatever is baked into the place, and the newest code wins regardless of load order.
local VERSION = 4
local BUILD = (_G.EventPillBuild or 0) + 1

-- THE FIRST LINE OF OUTPUT, BEFORE ANYTHING THAT CAN YIELD -- not even PlayerGui is waited on yet. If this
-- line is absent from the client log then this file is not executing at all, which is a place/Rojo problem
-- and not something any amount of code in here can fix. If it appears TWICE with different builds, there
-- are two copies and the duplicate has to be deleted in Studio.
print(("[EventChip] build %d v%d LOADING"):format(BUILD, VERSION))

local prev = _G.EventPillStamp
if prev and type(prev) == "table" and (prev.version or 0) > VERSION then
	-- Something newer is already here. Stand down completely and say so, rather than fighting it.
	print(("[EventChip] build %d v%d STANDING DOWN -- v%d is already live")
		:format(BUILD, VERSION, prev.version))
	return
end
_G.EventPillStamp = { version = VERSION, build = BUILD }
_G.EventPillBuild = BUILD   -- kept for older copies that only understand this one

local function current()
	local st = _G.EventPillStamp
	if type(st) ~= "table" then return false end
	-- Ours only while nothing of an equal-or-higher version has taken over since.
	return st.build == BUILD
end

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Any GUI left behind by an earlier build, destroyed BEFORE this one builds its own -- otherwise the sweep
-- runs after construction and the new build deletes itself.
for _, g in ipairs(PlayerGui:GetChildren()) do
	if g:IsA("ScreenGui") and g.Name == "EventChipGui" then g:Destroy() end
end

--======================================================================
-- SHORT NAMES
--======================================================================
-- The server's display names are written for a full-width banner -- "\xE2\x9B\x88 THUNDERSTORM", "\xF0\x9F\x8E\xAF RING FEVER"
-- -- and none of them fit in a chip an eighth of that width. TextScaled would technically make them fit, by
-- shrinking "THUNDERSTORM" to about four pixels tall. So each event gets an emoji over ONE word.
--
-- Keyed on the INTERNAL name, never the display name: LOW_GRAVITY is shown to players as "HIGH GRAVITY",
-- so a display-name key would silently stop matching if another were renamed the same way.
--
-- The third column is the colour, for the LATE JOINER: a player who joins forty seconds into a storm never
-- received the broadcast that carries it, and the replicated attributes carry the name and nothing else.
local SHORT = {
	FART_STORM   = { "\xF0\x9F\x92\xA8", "FART",  Color3.fromRGB(100, 200, 255) },
	COIN_RUSH    = { "\xF0\x9F\x92\xB0", "COINS", Color3.fromRGB(255, 200,   0) },
	LOW_GRAVITY  = { "\xF0\x9F\x8C\x99", "GRAV",  Color3.fromRGB(150, 100, 255) },  -- shown as "HIGH GRAVITY"
	POWER_SURGE  = { "\xE2\x9A\xA1",     "SURGE", Color3.fromRGB(255, 255,   0) },
	RING_FEVER   = { "\xF0\x9F\x8E\xAF", "RINGS", Color3.fromRGB(255, 100, 200) },
	THUNDERSTORM = { "\xE2\x9B\x88",     "STORM", Color3.fromRGB( 50,  50,  80) },
	WINDSTORM    = { "\xF0\x9F\x92\xA8", "WIND",  Color3.fromRGB(100, 150, 200) },
	DEV_ONLINE   = { "\xF0\x9F\x91\x91", "DEV",   Color3.fromRGB(255, 215,   0) },
}

-- A NEW EVENT MUST NEVER PRODUCE A BLANK CHIP: anything not in SHORT derives an icon and a word from
-- whatever the server sent, so an event added to the pool later still gets a reasonable chip.
local function derive(key, dispName)
	local icon, word = nil, nil
	local text = tostring(dispName or "")
	local lead, rest = text:match("^([^%a]*)(.*)$")
	if lead and lead:gsub("%s", "") ~= "" then icon = lead:gsub("%s", "") end
	for w in tostring(rest ~= "" and rest or key):gmatch("[%a]+") do
		if not word or #w > #word then word = w end
	end
	word = (word or "EVENT"):upper()
	if #word > 6 then word = word:sub(1, 5) end
	return icon or "\xE2\x9C\xA8", word
end

local function shortFor(key, dispName)
	local row = SHORT[tostring(key)]
	if row then return row[1], row[2], row[3] end
	local icon, word = derive(key, dispName)
	return icon, word, nil
end

--======================================================================
-- THE CHIP
--======================================================================
local PILL_FRACTION = 0.125   -- an eighth of the banner's live width
local PILL_GAP      = 8       -- px of clear air between the banner's right edge and the chip

-- Where the banner sits when there is no banner. NotifyCenter's HERO_SHOWN is (0.5, 0, 0, 10) on desktop and
-- (0.5, 0, 0, 21) on a narrow screen -- it drops 11px there to clear the climb race bar's markers -- with
-- AnchorPoint (0.5, 0) and base size 500x65. Mirrored, including that phone offset, so the chip has
-- somewhere sensible to be before the first banner ever plays. Once one does, heroRect reads the banner's
-- real AbsolutePosition and this constant stops mattering.
local HERO_W, HERO_H = 500, 65
local HERO_Y = 10
do
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if vp and vp.X < 900 then HERO_Y = 21 end
end

-- ===== ITS OWN ScreenGui, AND WHY IT CANNOT LIVE INSIDE NotifyHero =====
-- Parenting the chip into NotifyHero looks right -- same DisplayOrder for free, moves with the lane -- and
-- it would destroy the objective banner within two seconds.
--
-- TopCenterStack adopts these lanes. Its adopt() takes the FIRST Frame child of the ScreenGui that is not
-- named "StackBox", and before re-parenting it, it DESTROYS the StackBox it currently holds -- along with
-- the Hero banner inside. Once Hero has been adopted (it lives at NotifyHero.StackBox.Hero from then on),
-- a loose Frame named "EventPill" sitting under NotifyHero IS that first non-StackBox frame. So the next
-- adopt pass would delete the box containing the real banner and adopt the chip in its place, permanently.
--
-- Its own ScreenGui avoids the collision entirely. DisplayOrder is MIRRORED from NotifyHero live rather
-- than hardcoded, which is what "the same DisplayOrder" actually needs to mean -- a copied constant would
-- silently drift the first time NotifyCenter retuned its own.
local gui = Instance.new("ScreenGui")
gui.Name = "EventChipGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true          -- same as NotifyHero, so AbsolutePosition is directly comparable
gui.DisplayOrder = 96
gui.Parent = PlayerGui

local pill = Instance.new("Frame")
pill.Name = "EventPill"
pill.AnchorPoint = Vector2.new(0, 0)
pill.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
pill.BorderSizePixel = 0
pill.Visible = false
pill.Parent = gui
do
	-- The hero banner's own radius (12) and stroke (black, 2), so the two read as one object.
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = pill
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(0, 0, 0); s.Thickness = 2; s.Parent = pill
end

local pillText = Instance.new("TextLabel")
pillText.Name = "Label"
pillText.BackgroundTransparency = 1
pillText.Size = UDim2.new(1, -8, 1, -8)
pillText.Position = UDim2.new(0.5, 0, 0.5, 0)
pillText.AnchorPoint = Vector2.new(0.5, 0.5)
pillText.Font = Enum.Font.GothamBlack
pillText.TextScaled = true
pillText.TextWrapped = true
pillText.Text = ""
pillText.TextColor3 = Color3.fromRGB(255, 255, 255)
pillText.Parent = pill

-- Readable on whatever colour the server picked: the palette runs from THUNDERSTORM's near-black navy
-- (50,50,80) to COIN_RUSH's gold (255,200,0). Rec. 601 luma, the standard weighting for this decision.
local function inkFor(c)
	local luma = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	if luma > 0.6 then return Color3.fromRGB(25, 25, 35) end
	return Color3.fromRGB(255, 255, 255)
end

--======================================================================
-- FINDING THE HERO BANNER
--======================================================================
-- ===== BY DESCENDANT SEARCH, NOT BY A FIXED PATH =====
-- The banner is at NotifyHero.Hero when NotifyCenter builds it, and at NotifyHero.StackBox.Hero after
-- TopCenterStack adopts it -- and the move happens at some point after boot, on a poll. Hardcoding either
-- path is wrong half the time; hardcoding the post-adoption one is wrong until adoption happens, and wrong
-- again if TopCenterStack is ever disabled. Searching for the descendant named "Hero" is right in every
-- one of those states, and costs one small traversal on a cache miss.
local heroRef = nil
local heroConns = {}

local function dropHeroConns()
	for _, c in ipairs(heroConns) do pcall(function() c:Disconnect() end) end
	heroConns = {}
end

local layout   -- forward: bound below, referenced by the connections resolveHero installs

local function resolveHero()
	if not current() then return nil end
	if heroRef and heroRef.Parent then return heroRef end

	dropHeroConns()
	heroRef = nil

	local heroGui = PlayerGui:FindFirstChild("NotifyHero")
	if not heroGui then return nil end

	-- Mirror the lane's DisplayOrder every time we re-resolve, so a retune over there follows here.
	gui.DisplayOrder = heroGui.DisplayOrder + 1

	for _, d in ipairs(heroGui:GetDescendants()) do
		if d:IsA("GuiObject") and d.Name == "Hero" then heroRef = d; break end
	end
	if not heroRef then return nil end

	-- Re-lay-out the instant the banner moves or resizes, rather than only on the next frame -- this is
	-- what keeps the chip glued to the right edge through the slide-in and through a banner growing to fit
	-- a subtitle or a progress bar.
	heroConns[#heroConns + 1] = heroRef:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if current() and pill.Visible then layout() end
	end)
	heroConns[#heroConns + 1] = heroRef:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		if current() and pill.Visible then layout() end
	end)
	return heroRef
end

-- A rebuilt or re-adopted banner is a NEW instance, so the cached one goes stale. DescendantAdded (not
-- ChildAdded) because adoption re-parents Hero one level deeper into a StackBox, which is a descendant
-- event and not a child event of the ScreenGui.
task.spawn(function()
	local heroGui = PlayerGui:WaitForChild("NotifyHero", 30)
	if not (heroGui and current()) then return end
	heroGui.DescendantAdded:Connect(function(d)
		if not current() then return end
		if d:IsA("GuiObject") and d.Name == "Hero" and d ~= heroRef then
			heroRef = nil            -- force a re-resolve, which re-installs the property signals
			resolveHero()
			if pill.Visible then layout() end
		end
	end)
end)

-- The banner's rect in absolute pixels, plus whether that was the live banner or the fallback.
local function heroRect()
	local hero = resolveHero()
	if hero and hero.Visible and hero.AbsoluteSize.X > 1 then
		return hero.AbsolutePosition, hero.AbsoluteSize, true
	end
	local cam = Workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
	return Vector2.new(vp.X / 2 - HERO_W / 2, HERO_Y), Vector2.new(HERO_W, HERO_H), false
end

layout = function()
	local pos, size = heroRect()
	pill.Position = UDim2.fromOffset(math.floor(pos.X + size.X + PILL_GAP), math.floor(pos.Y))
	pill.Size = UDim2.fromOffset(math.floor(size.X * PILL_FRACTION), math.floor(size.Y))
end

--======================================================================
-- THE COUNTDOWN
--======================================================================
-- THREE SOURCES, in priority order, because no single one covers every case:
--   1. EventPillShow's own duration  -- an explicit local deadline, the most authoritative thing there is.
--   2. EventClient's per-second push -- its tickers already compute `rem`; they are what used to write the
--                                       full-width countdown banner.
--   3. ActiveServerEventEndsAt       -- replicates, so a LATE JOINER has a countdown from their first
--                                       frame, before any broadcast or push can possibly reach them.
--
-- The push EXPIRES. Without a TTL a pushed value would sit frozen on the chip if its ticker stopped,
-- showing "8s" for the rest of the event -- a stale countdown reads as a broken timer, which is worse than
-- no timer at all.
local PUSH_TTL = 3
local deadline = nil          -- os.clock() value from EventPillShow's duration
local pushedSecs, pushedAt = nil, 0
local curIcon, curWord = nil, nil
local activeKey = nil

local function remainingSeconds()
	if deadline then
		local left = deadline - os.clock()
		if left >= 0 then return math.floor(left + 0.5) end
		return 0
	end
	if pushedSecs and (os.clock() - pushedAt) < PUSH_TTL then return pushedSecs end
	local endsAt = Workspace:GetAttribute("ActiveServerEventEndsAt")
	if type(endsAt) == "number" and endsAt > 0 then
		local left = endsAt - os.time()
		if left >= 0 then return math.floor(left) end
	end
	return nil
end

-- Two lines: icon + countdown on top, the short name under it. The chip is close to square, so a single
-- line of "\xE2\x9B\x88 35s STORM" would be scaled down until the height was mostly empty air. An event with no
-- countdown available shows the icon alone rather than a placeholder, so the chip never displays a number
-- it cannot stand behind.
local function paintText()
	if not curIcon then return end
	local secs = remainingSeconds()
	pillText.Text = (secs and (curIcon .. " " .. secs .. "s") or curIcon) .. "\n" .. (curWord or "")
end

--======================================================================
-- SHOW / HIDE
--======================================================================
local function hidePill()
	if not activeKey and not pill.Visible then return end   -- idempotent: never logs a hide that did nothing
	activeKey = nil
	curIcon, curWord = nil, nil
	pushedSecs, pushedAt, deadline = nil, 0, nil
	pill.Visible = false
	print("[EventChip] hide")
end

-- icon/word may be given explicitly (EventPillShow) or looked up from the key (the broadcast path).
local function showPill(key, icon, word, color, seconds)
	if not current() then return end
	-- ===== THE COUNTDOWN BANNER OUTRANKS THE CHIP =====
	-- EventClient shows the event countdown as a full-size top-centre banner again, and while an event is
	-- running that banner is supposed to be the only thing saying how long is left. Without this the two
	-- would both be driven by the same broadcast and the player would read the same number twice, in two
	-- different shapes. The flag is EVENT-LIFETIME ownership, not visibility: the banner briefly yields
	-- its lane to a hero notification (an island unlock) and the chip must not fill that gap.
	if _G.eventCountBannerActive then
		if pill.Visible then hidePill() end
		return
	end
	local wasVisible = pill.Visible

	activeKey = tostring(key)
	curIcon, curWord = icon, word
	deadline = (type(seconds) == "number" and seconds > 0) and (os.clock() + seconds) or nil
	local col = (typeof(color) == "Color3") and color or Color3.fromRGB(100, 200, 100)
	pillText.TextColor3 = inkFor(col)
	pill.BackgroundColor3 = col
	paintText()

	-- POSITIONED BEFORE IT IS SHOWN. A chip made visible at its previous (or zero) rect flashes in the
	-- wrong place for one frame; one that has never been laid out flashes at 0,0.
	pill.Visible = true
	layout()

	if not wasVisible then
		-- A short pop: it arrives beside a banner that is itself sliding in, and something that blinks into
		-- existence next to that reads as a rendering glitch.
		local target = pill.Size
		pill.Size = UDim2.fromOffset(math.floor(target.X.Offset * 0.6), target.Y.Offset)
		TweenService:Create(pill, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = target }):Play()
	end

	local secs = remainingSeconds()
	print(("[EventChip] show %s %s"):format(tostring(word or key), secs and (secs .. "s") or "(no timer)"))
end

--======================================================================
-- THE TICK
--======================================================================
-- Heartbeat with an accumulator rather than a task.wait loop: one connection, no coroutine left running
-- after this build retires, and it stops dead the moment a newer build claims the stamp.
--
-- HALF A SECOND, NOT ONE. A countdown repainted on a 1s cycle that is not phase-locked to the source's own
-- 1s cycle visibly skips numbers -- 35, 33, 32, 30. Repainting twice as often removes the beat frequency.
do
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if not current() then return end
		if not pill.Visible then return end
		layout()                       -- also covers the fallback rect following a viewport resize
		acc += dt
		if acc >= 0.5 then
			acc = 0
			paintText()
			-- A duration-driven chip retires itself. Nothing else has to remember to call hide for an event
			-- whose end broadcast is lost or never sent.
			if deadline and os.clock() >= deadline then hidePill() end
		end
	end)
end

--======================================================================
-- PUBLIC API
--======================================================================
-- The two the event code calls directly:
--     _G.EventPillShow("\xE2\x9B\x88", "STORM", 40)
--     _G.EventPillHide()
-- Logged rather than silent when a retired build is called: "the storm fired and nothing happened" is
-- indistinguishable from "the hook was never called" unless one of them says so.
_G.EventPillShow = function(icon, label, seconds, color)
	if not current() then
		warn(("[EventChip] build %d ignored EventPillShow -- a newer build owns the chip"):format(BUILD))
		return
	end
	local key = tostring(label or icon or "EVENT")
	local known = SHORT[key:upper()]
	showPill(key, icon or "\xE2\x9C\xA8", tostring(label or ""):upper(),
		color or (known and known[3]) or nil, seconds)
end
_G.EventPillHide = function()
	if not current() then return end
	hidePill()
end

-- WHO ACTUALLY OWNS THE CHIP. Printed once a few seconds in, by which time every copy has loaded and the
-- stamp has settled -- so this single line names the winner instead of leaving it to be inferred.
task.delay(5, function()
	local st = _G.EventPillStamp
	print(("[EventChip] build %d v%d -- owner is build %s (%s)"):format(
		BUILD, VERSION, tostring(st and st.build), current() and "THIS ONE" or "not this one"))
end)

-- Older names kept working: EventClient's per-second tickers call eventPillSeconds, and the big-event
-- managers were told about eventPillPush/Clear. Renaming them would have been a silent breakage in files
-- this change is not otherwise touching.
_G.eventPillSeconds = function(n)
	if not current() or type(n) ~= "number" then return end
	pushedSecs = math.max(0, math.floor(n))
	pushedAt = os.clock()
	paintText()
end
_G.eventPillPush = function(key, dispName, color)
	if not current() then return end
	local icon, word, known = shortFor(key, dispName)
	showPill(key, icon, word, color or known, nil)
end
_G.eventPillClear = function()
	if not current() then return end
	hidePill()
end

-- NOTE: _G.eventPillHold in EventClient is a DIFFERENT, older system -- it tells the quest tracker to
-- stand down while something owns the top-centre lane. Same word, unrelated mechanism; do not merge them.

--======================================================================
-- THE BROADCAST DRIVE
--======================================================================
-- This is what covers the five pool events nobody hand-wired, AND the late joiner. It is kept alongside
-- the explicit EventPillShow calls rather than replaced by them: both routes end in showPill, so they
-- agree, and an event that nobody remembers to hook still gets a chip.
local lastKey, lastName, lastColor = nil, nil, nil

local function attrKey()
	local k = Workspace:GetAttribute("ActiveServerEvent")
	if type(k) ~= "string" or k == "" then return nil end
	return k
end

local function refresh()
	if not current() then return end
	local key = attrKey()
	if not key then
		if activeKey then hidePill() end
		return
	end
	local name, color
	if lastKey == key then
		name, color = lastName, lastColor
	else
		local n = Workspace:GetAttribute("ActiveServerEventName")
		name = (type(n) == "string" and n ~= "") and n or key
	end
	local icon, word, known = shortFor(key, name)
	showPill(key, icon, word, color or known, nil)
end

-- ===== WIRED IN A task.spawn, NOT AT TOP LEVEL =====
-- WaitForChild YIELDS THE WHOLE SCRIPT. Sitting at top level it can hold up to 30 seconds, and everything
-- below it -- the attribute listeners, the boot catch-up, the "ACTIVE" log line -- simply does not exist
-- until it returns. A remote that is slow to replicate would therefore look exactly like a dead script.
task.spawn(function()
	local notify = ReplicatedStorage:FindFirstChild("ServerEventNotify")
		or ReplicatedStorage:WaitForChild("ServerEventNotify", 30)
	if notify then
		notify.OnClientEvent:Connect(function(eventName, dispName, duration, _msg, color)
			if not current() then return end
			if eventName == "END" or eventName == nil or eventName == "" then
				lastKey, lastName, lastColor = nil, nil, nil
				hidePill()
				return
			end
			lastKey, lastName, lastColor = tostring(eventName), dispName, color
			local icon, word, known = shortFor(lastKey, dispName)
			-- Shown straight away rather than waiting for refresh(): the server sets the attribute on the
			-- line AFTER the broadcast and replication of the two is not ordered.
			showPill(lastKey, icon, word, color or known, type(duration) == "number" and duration or nil)
		end)
	else
		warn("[EventChip] no ServerEventNotify remote -- workspace attributes only.")
	end
end)

Workspace:GetAttributeChangedSignal("ActiveServerEvent"):Connect(refresh)
Workspace:GetAttributeChangedSignal("ActiveServerEventName"):Connect(refresh)

-- CATCH-UP AT BOOT, which is the whole late-joiner story on the client side: LateJoinEventSync replays the
-- event's phases to a joining player through the same remotes, but the workspace attributes were set
-- before that player existed, so neither changed-signal above will ever fire for them. This reads the
-- current state once, and ActiveServerEventEndsAt supplies the remaining time.
task.defer(refresh)

do
	local hero = resolveHero()
	print(("[EventChip] build %d ACTIVE anchored to %s")
		:format(BUILD, hero and hero:GetFullName() or "NotifyHero.StackBox.Hero (not built yet -- will attach)"))
end
