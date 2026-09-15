--!nonstrict
--======================================================================
-- CLIMB RACE BAR -- one thin line across the top, a few faces on it
--======================================================================
-- WHAT IT IS. A single hairline from START (Bean Farm) to FINISH (Pizza Palms) with a small circular avatar
-- for each player on it, placed at how far up the tower they are. Yours is bigger and outlined in gold. That
-- is the whole thing: no tick marks, no island numbers, no percentages, no segments, no labels.
--
-- WHY IT IS A NEW FILE. The old top-centre "PLANET RACE" board (the RaceBoard ScreenGui) was built by hand in
-- Studio and lives inside the place file -- no script in this repo builds it, styles it or feeds it, so there
-- was nothing to tidy. This replaces it and switches it off (see the RETIRE block at the bottom).
--
-- ===== WHY SO LITTLE OF IT =====
-- The top strip is the most expensive real estate on the screen: it is where the player is LOOKING while they
-- fly, because the next island is up. Anything drawn there is drawn over the game. So the bar is 3 pixels of
-- line and a row of 22-pixel circles, and it never grows: five markers maximum, no matter how full the server
-- is. A race you can read in a glance without moving your eyes off the climb is worth having; a leaderboard
-- pinned over the sky is not.
--
-- ===== IT IS ALWAYS ON SCREEN =====
-- This is a position tracker: it answers "where is everybody" at a glance, and a thing that answers that
-- only sometimes is worse than nothing, because you learn not to look. So it never hides -- not for banners,
-- not for pins, not on phones. It shares the top strip with NotifyCenter's banner card by geometry instead:
-- the card starts 10px down and its first line of text at 18, so the bar rides at y 11 with 16px faces and
-- draws ABOVE the card (DisplayOrder 96), which puts small circles over a few pixels of the card's padding
-- and nothing else. The one part that yields is the YOU caption under your face -- see ALWAYS VISIBLE below.
--
-- Every screen size gets it -- a three-pixel line costs a phone nothing, so narrow only means smaller faces
-- on a longer line (see BAR_W_FRAC).
--
-- ===== POSITION IS LIVE HEIGHT, NOT A SAVED STAT =====
-- Markers read each character's actual Y this second, so they move while people fly and slide back when they
-- fall. A player with no character yet (loading, between spawns) falls back to their BestHeight attribute so
-- their face still appears rather than popping in and out.
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")   -- per-frame drive for the YOU marker (live tracking)

-- Narrow means narrow -- measured, not guessed from TouchEnabled, which is true in a Studio emulator and on
-- any laptop with a touchscreen.
local function isNarrow()
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
	return vp ~= nil and vp.X < 900
end

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== ONE BAR ONLY: THE NEWEST BUILD WINS =====
-- Rojo only ADDS -- it never overwrites -- so a STALE copy of this script baked into the place file runs
-- ALONGSIDE the synced one, and its ScreenGui (old small circles, old tooltip) draws over/under this one.
-- That is exactly the "my change didn't take effect" symptom: the edit is in this file, but a second, older
-- copy of the file is what you are actually looking at. Every build stamps itself (CRBBuild/CRBGen); the
-- sweep below (killStaleClimbBars) DESTROYS any other ClimbRaceBar ScreenGui that is an older build, so only
-- the newest code is ever on screen. Bump CRB_BUILD on any visible-layout change so an older baked copy loses.
local CRB_BUILD = 4   -- 4 = 24px island circles + tooltip parented to root (inset-proof, below the marker)
_G.__CRB_gen = (_G.__CRB_gen or 0) + 1
local CRB_GEN = _G.__CRB_gen

-- ===== THE CLIMB, IN STUDS =====
-- Island 1's stand sits at Y=245 and Pizza Palms at Y=38,158 (IslandOrder.SLOT_POS). Hard-coded rather than
-- required from the shared module because this file must not care whether the module has replicated yet --
-- it is a HUD, and a HUD that waits is a HUD that is missing when you need it. If the tower is ever re-spaced,
-- these two numbers move with it.
local START_Y  = 245
local FINISH_Y = 38158

local MAX_MARKERS = 5      -- you + up to four others. A hard cap, not a "usually"
local LINE_H      = 3      -- the whole bar, in pixels
-- SMALL SCREENS GET A SMALLER BAR, NOT NO BAR. The first build HID this on phones, copying what ResponsiveUI
-- does to the old RaceBoard -- wrong twice over: that board was a full leaderboard panel which genuinely
-- fought the banner lane, and this is three pixels of line. It also meant the very first live test showed
-- nothing at all, because a narrow Studio viewport reads as a phone. A HUD element whose failure mode is
-- "silently invisible" is worse than one that is slightly too big. So it always shows; narrow just means
-- smaller faces on a proportionally longer line (46% of a phone is too short to place anybody on).
local showYouTag  = true   -- desktop only; layout() sets it (see the YOU caption note there)
local narrow      = isNarrow()
local DOT         = narrow and 18 or 20   -- other players -- big enough to read as a FACE, not a dot
local YOU_DOT     = narrow and 22 or 26   -- you, bigger -- the only emphasis on the bar
local MIN_GAP     = 4                     -- pixels of clear space between two faces (see the declutter pass)

-- ===== IT STOPS BEFORE THE CURRENCY CAPSULE =====
-- The top-right of the screen belongs to the gear button and the [tickets | coins] capsule. The bar used to
-- be a centred fraction of the width, which meant its right end -- and the FINISH pill hanging off it --
-- ran underneath them. Nothing was hidden (this draws on top) but two unrelated things overlapping in the
-- busiest corner of the HUD reads as broken.
--
-- So the line is measured from the EDGES instead: a small left margin, and on the right a reserve wide
-- enough for the gear + capsule + a gap. Fractions, because ResponsiveUI scales that cluster with the
-- screen; the floor is what keeps it honest on a small window where a fraction would be a few pixels.
-- Both margins are deliberately generous. A line that runs almost the full width reads as a divider across
-- the top of the screen rather than as a track someone is travelling along; pulled in at both ends it reads
-- as an object, and the START and FINISH pills get real air around them instead of hugging the corners.
local LEFT_PAD      = 0.105   -- fraction of the width before the START pill (clears the SHOP rail as well)
local RIGHT_RESERVE = 0.275   -- fraction the gear + ticket/coin capsule occupy, right-aligned, plus air
local RIGHT_MIN     = 200     -- ...but never less than this in pixels. NOT larger: ResponsiveUI shrinks the
                              -- gear and capsule on a phone, so a desktop-sized floor here would eat half a
                              -- phone's line to protect a cluster that is no longer that wide
local PILL_ROOM     = 62      -- the START / FINISH pills hang OUTSIDE the line -- leave them their space

-- Phone-only numbers. See the "PHONES GET THE DESKTOP'S PROPORTIONS" block in layout(); none of these are
-- read above 900px, so tuning them cannot move the desktop bar.
local LINE_FRAC          = 0.40   -- what the desktop layout settles on, as a fraction of the width
local RIGHT_RESERVE_SMALL = 0.22  -- the gear + capsule after ResponsiveUI has shrunk them
local PILL_ROOM_SMALL     = 42    -- ...and the FINISH pill's own space at phone size
local NUDGE_X       = 0       -- shift the whole bar sideways. Back to 0: the line is now centred on the
                              -- screen axis to match the banner above it, and any nudge here breaks exactly
                              -- the alignment that centring was asked for. Kept as the one place to bias it
-- 11 px down from the TRUE top of the screen (the inset is ignored below), which is the one band nothing
-- else uses: NotifyCenter's banner card starts at y 10 but its first text sits at y 18, so a 20px marker
-- centred here reaches y 21 and only ever overlaps the banner's top padding -- and this bar draws over it.
local BAR_Y       = 14

--======================================================================
-- BUILD
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "ClimbRaceBar"
gui.ResetOnSpawn = false
-- IGNORE THE INSET, AND DRAW OVER THE BANNER. Both of these exist so the bar is ALWAYS visible.
-- Inset: with it respected, "11 px down" meant 11 px below the Roblox topbar -- 47 px down the screen, which
-- is the middle of the banner card. Ignoring it puts the bar in the thin band above the banner's text.
-- DisplayOrder 96: one above NotifyCenter's hero lane (95), below the quest-minigame HUDs (97) and the
-- menus (100). A tracker that vanishes whenever something else happens is not a tracker -- and this is a
-- hairline with five small circles on it, so being on top costs the banner a few pixels of padding.
gui.IgnoreGuiInset = true
gui.DisplayOrder = 96
-- TopScreenAudit kills thin white bars across the top of the screen -- which is precisely what this is.
-- This attribute is its opt-out; without it the line is switched off a few seconds after every join.
gui:SetAttribute("TopAuditKeep", true)
-- ===== AND ResponsiveUI KEEPS ITS HANDS OFF =====
-- On a phone ResponsiveUI does two things to every HUD ScreenGui it has not been told to skip: it flips
-- ScreenInsets to DeviceSafeInsets, and it hangs a UIScale on each non-full-screen child. Both are wrong for
-- this bar and together they are exactly the "short and off-centre on mobile" bug:
--   * the UIScale lands on the Line, whose AnchorPoint is (0, 0.5) -- so scaling shrinks it toward its LEFT
--     edge. The line got shorter AND its midpoint slid left, which is the one thing this element must not do.
--   * the inset flip moves this GUI into the safe-area coordinate space, so the pixel positions layout()
--     computes from the real viewport width stop meaning what they say.
-- This bar is already responsive on its own terms: every number in layout() is a fraction of the live
-- viewport, re-measured on every change, and it centres itself on the banner's MEASURED position rather than
-- on a coordinate space it has to share.
gui:SetAttribute("NoResponsiveScale", true)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = PlayerGui
gui:SetAttribute("CRBBuild", CRB_BUILD)   -- identifies THIS copy so the sweep can tell it from a stale one
gui:SetAttribute("CRBGen", CRB_GEN)

local root = Instance.new("Frame")        -- the line itself IS the container
root.Name = "Line"
root.AnchorPoint = Vector2.new(0, 0.5)    -- measured from the LEFT edge; the right end is computed
root.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
-- SOLID WHITE. It started at 0.62, then 0.28, and both were the same mistake: this line is the one thing on
-- screen that says "here is the whole tower", and against a bright sky a translucent hairline is nothing at
-- all. At 0 it reads on cloud, on blue and on the dark sky above island 10.
root.BackgroundTransparency = 0
root.BorderSizePixel = 0
root.ZIndex = 2
root.Parent = gui
Instance.new("UICorner", root).CornerRadius = UDim.new(1, 0)
do
	-- A thin dark edge so the line reads on a white cloud as well as on blue sky.
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(15, 20, 35)
	edge.Thickness = 1
	edge.Transparency = 0.55
	edge.Parent = root
end

-- The travelled part of the line, up to YOUR marker. The one piece of colour on the whole thing, and the
-- reason the bar reads as progress rather than as a row of faces.
local fill = Instance.new("Frame")
fill.Name = "Done"
fill.Size = UDim2.new(0, 0, 1, 0)
fill.BackgroundColor3 = Color3.fromRGB(255, 196, 60)
fill.BackgroundTransparency = 0.15
fill.BorderSizePixel = 0
fill.ZIndex = 3
fill.Parent = root
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

-- ===== THE TWO END PILLS =====
-- The dots mark where the line stops; the pills name the ends. They sit OUTSIDE the line -- one left of
-- START, one right of FINISH -- because the bar rides in a 20-pixel band at the top of the screen and there
-- is no room above or below it. Beside it there is plenty.
--
-- BLUE, and the same blue as the rest of the HUD (the bottom stack, the stats panel, the currency capsule):
-- these two labels belong to the game's furniture, not to the race. Gold is the player's own colour on this
-- bar -- the travelled fill and the YOU ring -- and letting the end labels wear it too made three different
-- things shout in the same voice. A filled pill rather than a tinted one: at 16px tall a translucent chip
-- over a bright sky is mush, and these are the only words a new player has to go on.
local HUD_BLUE  = Color3.fromRGB(30, 118, 235)
local HUD_LIGHT = Color3.fromRGB(126, 186, 255)

for _, x in ipairs({ 0, 1 }) do
	local cap = Instance.new("Frame")
	cap.Name = (x == 0) and "Start" or "Finish"
	cap.AnchorPoint = Vector2.new(0.5, 0.5)
	cap.Position = UDim2.new(x, 0, 0.5, 0)
	cap.Size = UDim2.fromOffset(9, 9)
	cap.BackgroundColor3 = HUD_LIGHT
	cap.BorderSizePixel = 0
	cap.ZIndex = 4
	cap.Parent = root
	Instance.new("UICorner", cap).CornerRadius = UDim.new(1, 0)
	do
		local ring = Instance.new("UIStroke")
		ring.Color = Color3.fromRGB(255, 255, 255)
		ring.Thickness = 1.5
		ring.Transparency = 0.2
		ring.Parent = cap
	end

	local pill = Instance.new("Frame")
	pill.Name = cap.Name .. "Pill"
	pill.AnchorPoint = Vector2.new(x == 0 and 1 or 0, 0.5)
	pill.Position = UDim2.new(x, (x == 0) and -11 or 11, 0.5, 0)
	pill.Size = UDim2.fromOffset((x == 0) and 52 or 58, 18)
	pill.BackgroundColor3 = HUD_BLUE
	pill.BorderSizePixel = 0
	pill.ZIndex = 4
	pill.Parent = root
	Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

	-- A vertical lift on the fill and a pale rim: the same two-step every other button in this HUD wears,
	-- which is what makes a flat rectangle read as a moulded object rather than a coloured box.
	do
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(Color3.fromRGB(72, 152, 255), HUD_BLUE)
		grad.Parent = pill

		local edge = Instance.new("UIStroke")
		edge.Color = HUD_LIGHT
		edge.Thickness = 1.5
		edge.Transparency = 0.15
		edge.Parent = pill
	end

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = (x == 0) and "START" or "FINISH"
	label.TextSize = 11
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.55        -- holds the letters together at 11px on a bright sky
	label.TextStrokeColor3 = Color3.fromRGB(12, 40, 96)
	label.ZIndex = 5
	label.Parent = pill
end

--======================================================================
-- MARKERS
--======================================================================
-- One pooled marker per slot, reused. Rebuilding five ImageLabels every refresh would thrash the image cache
-- and make the avatars flicker; instead a marker keeps its instance and only its X, size and image change.
local slots = {}          -- [1..MAX_MARKERS] = { holder, img, ring }
local thumbs = {}         -- userId -> content string, so a thumbnail is fetched once per player per session

local function markerAt(i)
	if slots[i] then return slots[i] end
	local holder = Instance.new("Frame")
	holder.Name = "Marker" .. i
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0, 0, 0.5, 0)
	holder.Size = UDim2.fromOffset(DOT, DOT)
	holder.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
	holder.BorderSizePixel = 0
	holder.ZIndex = 5
	holder.Visible = false
	holder.Parent = root
	Instance.new("UICorner", holder).CornerRadius = UDim.new(1, 0)

	local ring = Instance.new("UIStroke")
	ring.Color = Color3.fromRGB(255, 255, 255)
	ring.Thickness = 2
	ring.Transparency = 0.25
	ring.Parent = holder

	local img = Instance.new("ImageLabel")
	img.Name = "Face"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = 6
	img.Parent = holder
	Instance.new("UICorner", img).CornerRadius = UDim.new(1, 0)

	-- The one word on the whole bar. It hangs UNDER the local player's face rather than over it, so it never
	-- covers the avatar it is labelling, and it is the only marker that gets a label at all -- naming the other
	-- four would put five names in a 3-pixel strip and undo the point of the bar. Hidden on every other marker
	-- (see refresh); it exists on all five only because the markers are pooled and reused.
	local tag = Instance.new("TextLabel")
	tag.Name = "You"
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.new(0.5, 0, 1, 4)     -- 4px of air, so the pointer below has somewhere to be
	tag.Size = UDim2.fromOffset(38, 15)
	tag.BackgroundColor3 = Color3.fromRGB(255, 196, 60)   -- gold: the player's own colour on this bar
	tag.BorderSizePixel = 0
	tag.Font = Enum.Font.GothamBold
	tag.Text = "YOU"
	tag.TextSize = 10
	tag.TextColor3 = Color3.fromRGB(38, 26, 0)  -- dark on gold reads at 10px; white on gold does not
	tag.ZIndex = 9
	tag.Visible = false
	tag.Parent = holder
	Instance.new("UICorner", tag).CornerRadius = UDim.new(1, 0)
	do
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.fromRGB(120, 78, 0)
		edge.Thickness = 1
		edge.Transparency = 0.35
		edge.Parent = tag

		-- The pointer. A rotated square poking out of the pill's top edge, half-buried behind it, which is
		-- the cheapest way to draw a triangle in Roblox UI -- no image, no polygon. It is what turns a label
		-- floating under a circle into a label that is clearly ABOUT that circle.
		local nib = Instance.new("Frame")
		nib.Name = "Nib"
		nib.AnchorPoint = Vector2.new(0.5, 0.5)
		nib.Position = UDim2.new(0.5, 0, 0, 1)
		nib.Size = UDim2.fromOffset(7, 7)
		nib.Rotation = 45
		nib.BackgroundColor3 = tag.BackgroundColor3
		nib.BorderSizePixel = 0
		nib.ZIndex = 8                       -- under the pill, so only the corner shows
		nib.Parent = tag
	end

	slots[i] = { holder = holder, img = img, ring = ring, tag = tag }
	return slots[i]
end

-- Thumbnails yield, so they are fetched off the update loop and cached. Until one arrives the marker is just
-- the dark circle with its ring, which is a perfectly good marker on its own.
local function thumbFor(userId)
	if thumbs[userId] ~= nil then return thumbs[userId] end
	thumbs[userId] = ""                              -- claim it so we only ask once
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId,
				Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok and content then thumbs[userId] = content end
	end)
	return ""
end

-- How far up the tower somebody is, 0..1.
local function progressOf(p)
	local y
	local char = p.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		y = hrp.Position.Y
	else
		y = p:GetAttribute("BestHeight")           -- published by SocialStats; covers loading/dead players
	end
	-- NO ONE IS EVER DROPPED. This used to return nil when a player had neither a character nor a BestHeight
	-- attribute -- which is every player for the first seconds after they join, and every player in a Studio
	-- test where SocialStats is not publishing. A nil meant no marker, so the bar collapsed to a single icon
	-- (yours) and looked broken. Somebody with no known height is at the START of the tower, which is both
	-- the truth and the harmless assumption: their face appears at 0 and slides up the moment they move.
	if type(y) ~= "number" then return 0 end
	return math.clamp((y - START_Y) / (FINISH_Y - START_Y), 0, 1)
end

--======================================================================
-- ISLAND MILESTONE CHECKPOINTS
--======================================================================
-- A small themed circle for EVERY island in the realm, evenly spaced across the same track the faces ride
-- on. This is a SECOND, INDEPENDENT layer from the player markers: island circles are FIXED progression
-- checkpoints (one per island, never move); the faces are LIVE positions. The circles are drawn UNDER the
-- faces (ZIndex 4/5 vs 5/8) and sit on the line, so a face never permanently hides a checkpoint -- a face
-- moves, a checkpoint does not.
--
-- ===== THE ORDER AND NAMES ARE THE GAME'S OWN, NOT GUESSED =====
-- IslandOrder.NAMES is the single source PlayerStats/CoreClient already use, in climb order. We read it if
-- it has replicated (it lives in ReplicatedStorage.Shared and is up long before a HUD script runs); the
-- inline list is a same-order fallback so the bar can never be blank, matching this file's "a HUD must not
-- wait" rule (same reason START_Y/FINISH_Y are inline). A different realm with a different NAMES table just
-- draws a different number of evenly-spaced circles -- nothing here is hard-coded to 14.
local ISLE_NAMES = {
	"Bean Farm","Broccoli Bluff","Cabbage Cliffs","Turnip Tranquil",
	"Coconut Cove","Bread Board","Pasta Peak","Popcorn Pinnacle",
	"Milk Marsh","Butter Swamp","Ice Cream Isle","Burger Bluff",
	"Burrito Barrens","Pizza Palms",
}
do
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	local mod = shared and shared:FindFirstChild("IslandOrder")
	if mod then
		local ok, io = pcall(require, mod)
		if ok and type(io) == "table" and type(io.NAMES) == "table" and #io.NAMES > 0 then
			ISLE_NAMES = io.NAMES
		end
	end
end
local ISLE_N = #ISLE_NAMES

-- ===== ACTUAL WORLD Y OF EACH ISLAND (for the YOU marker's per-segment progress) =====
-- The checkpoints are evenly spaced in the UI, but the tower is NOT evenly spaced in the world, so the YOU
-- marker has to convert the player's real height into progress between the CORRECT two islands. Same source
-- as the names (IslandOrder.SLOT_POS); an even spread between START_Y..FINISH_Y is the fallback only if the
-- module has not replicated. Island 1's stand sits ~95 studs above its model centre and the summit stand a
-- few below its, so the two ends are pinned to the stand heights this file already trusts (START_Y/FINISH_Y)
-- -- that way STANDING on the first/last island reads as exactly its checkpoint. Used ONLY by the YOU marker.
local ISLE_WORLD_Y = {}
do
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	local mod = shared and shared:FindFirstChild("IslandOrder")
	local ok, io = false, nil
	if mod then ok, io = pcall(require, mod) end
	local haveSlot = ok and type(io) == "table" and type(io.SLOT_POS) == "table"
	for i = 1, ISLE_N do
		local p = haveSlot and io.SLOT_POS[i]
		local yv = (type(p) == "table") and tonumber(p.y) or nil
		if yv == nil then
			yv = START_Y + (FINISH_Y - START_Y) * ((i - 1) / math.max(1, ISLE_N - 1))
		end
		ISLE_WORLD_Y[i] = yv
	end
	ISLE_WORLD_Y[1] = START_Y
	if ISLE_N >= 2 then ISLE_WORLD_Y[ISLE_N] = FINISH_Y end
end

-- ===== THEME EMOJI, MATCHED TO THE ISLAND'S FOOD =====
-- Keyed on a word in the island's own name so it stays tied to the real data rather than to a position: if
-- the order ever changes, the coconut island keeps 🥥. Unmatched themes fall back to an island glyph rather
-- than a wrong food. Keys are whole words that never collide (no key is a confusing substring of another).
local ISLAND_EMOJI = {
	bean = "🫘", broccoli = "🥦", cabbage = "🥬", turnip = "🌱",
	coconut = "🥥", bread = "🍞", pasta = "🍝", popcorn = "🍿",
	milk = "🥛", butter = "🧈", ["ice cream"] = "🍦", burger = "🍔",
	burrito = "🌯", pizza = "🍕",
}
local function emojiForName(name)
	local low = string.lower(name or "")
	for key, em in pairs(ISLAND_EMOJI) do
		if string.find(low, key, 1, true) then return em end
	end
	return "🏝️"
end

-- Sizing. Checkpoints are SMALLER than the faces (they are the scenery, the faces are the story) and shrink
-- further if the track is too short to hold ISLE_N of them with clear gaps -- so with 14 islands on a phone
-- they still never touch. The current island gets a small size bump, never a dramatic one.
local ISLE_MIN_GAP   = 4    -- guaranteed clear pixels between two neighbouring checkpoints
local ISLE_CUR_BONUS = 5    -- the current island is this many px larger than the rest
local ISLE_Y         = 0    -- centred on the line, like the diagram's ○-on-the-track

-- One shared tooltip (only one island can be hovered/tapped at a time). Named-per-island labels across the
-- whole bar would be 14 names in a 3px strip -- the exact clutter the bar exists to avoid -- so the name is
-- shown ON DEMAND: hover on PC, a brief tap on touch.
local isleTip = Instance.new("Frame")
isleTip.Name = "IsleTip"
isleTip.AnchorPoint = Vector2.new(0.5, 0)
isleTip.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
isleTip.BackgroundTransparency = 0.05
isleTip.BorderSizePixel = 0
isleTip.Size = UDim2.fromOffset(132, 36)
isleTip.Visible = false
isleTip.ZIndex = 20
-- Parented to ROOT (the line), the SAME frame the markers live under -- NOT to `gui`. This is the fix for
-- the tooltip landing above the bar: `gui` is IgnoreGuiInset while the markers are nested under root, so
-- reading a marker's AbsolutePosition.Y and writing it into a gui-child's Position.Offset.Y crossed the 36px
-- GuiInset boundary and threw the tooltip 36px up off the bar (X was unaffected -- the inset is vertical
-- only, which is why the audit showed it centred horizontally but floating above). Under root there is no
-- inset round-trip: the tooltip is positioned purely in root-local space below the marker (see showIsleTip).
isleTip.Parent = root
Instance.new("UICorner", isleTip).CornerRadius = UDim.new(0, 6)
do
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(126, 186, 255)
	edge.Thickness = 1.5
	edge.Transparency = 0.25
	edge.Parent = isleTip
end
local isleTipText = Instance.new("TextLabel")
isleTipText.Name = "Text"
isleTipText.BackgroundTransparency = 1
isleTipText.Size = UDim2.new(1, -8, 1, -6)
isleTipText.Position = UDim2.fromScale(0.5, 0.5)
isleTipText.AnchorPoint = Vector2.new(0.5, 0.5)
isleTipText.Font = Enum.Font.GothamBold
isleTipText.Text = ""
isleTipText.TextSize = 12
isleTipText.TextColor3 = Color3.fromRGB(255, 255, 255)
isleTipText.TextStrokeTransparency = 0.6
isleTipText.TextWrapped = true
isleTipText.ZIndex = 21
isleTipText.Parent = isleTip

local function showIsleTip(i, holder)
	local name = ISLE_NAMES[i] or ("Island " .. i)
	isleTipText.Text = ("%s Island %d\n%s"):format(emojiForName(name), i, name)

	-- ALL ROOT-LOCAL -- no AbsolutePosition.Y is read, so the GuiInset can never move the tooltip off the bar.
	-- isleTip's AnchorPoint is (0.5, 0) = top-centre.
	local GAP  = 6
	local EDGE = 6
	local trackW = math.max(1, root.AbsoluteSize.X)

	-- VERTICAL: the markers sit centred on the line (root's 0.5). Drop the tooltip's TOP to just past the
	-- marker's bottom edge = half the marker's height + a small gap, below the line centre. Always downward,
	-- so it can never be clipped by the top of the screen.
	local belowY = holder.AbsoluteSize.Y / 2 + GAP

	-- HORIZONTAL: centre on the marker (its own scale position within the track), then clamp so the whole card
	-- stays on-screen. The screen edges are converted into root-local pixels via root.AbsolutePosition.X (X has
	-- no inset, which the runtime audit confirmed round-trips correctly), so the first/last island's card
	-- shifts inward instead of spilling off the side.
	local w = isleTip.AbsoluteSize.X
	if w < 1 then w = isleTip.Size.X.Offset end
	local vpx  = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X) or 1280
	local rootX = root.AbsolutePosition.X
	local mcx = holder.Position.X.Scale * trackW + holder.Position.X.Offset   -- marker centre, root-local px
	local minX = -rootX + w / 2 + EDGE
	local maxX = vpx - rootX - w / 2 - EDGE
	mcx = math.clamp(mcx, minX, math.max(minX, maxX))

	isleTip.Position = UDim2.new(0, math.floor(mcx), 0.5, math.floor(belowY))
	isleTip.Visible = true
end
local function hideIsleTip()
	isleTip.Visible = false
end

-- Pooled builder, one circle per island, reused across updates (see markerAt for why pooling).
local isleSlots = {}
local function isleMarker(i)
	if isleSlots[i] then return isleSlots[i] end
	local holder = Instance.new("Frame")
	holder.Name = "Isle" .. i
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0, 0, 0.5, ISLE_Y)
	holder.Size = UDim2.fromOffset(14, 14)
	holder.BackgroundColor3 = Color3.fromRGB(28, 34, 54)
	holder.BorderSizePixel = 0
	holder.ZIndex = 4                     -- on the line, UNDER the faces (5/8) so YOU is never hidden
	holder.Parent = root
	Instance.new("UICorner", holder).CornerRadius = UDim.new(1, 0)

	local ring = Instance.new("UIStroke")
	ring.Name = "Ring"
	ring.Color = Color3.fromRGB(255, 255, 255)
	ring.Thickness = 1.5
	ring.Transparency = 0.2
	ring.Parent = holder

	local em = Instance.new("TextLabel")
	em.Name = "Emoji"
	em.BackgroundTransparency = 1
	em.AnchorPoint = Vector2.new(0.5, 0.5)
	em.Position = UDim2.fromScale(0.5, 0.5)
	em.Size = UDim2.fromScale(0.98, 0.98)   -- the icon fills more of the (now larger) circle
	em.Font = Enum.Font.GothamBold
	em.Text = emojiForName(ISLE_NAMES[i])
	em.TextScaled = true
	em.TextColor3 = Color3.fromRGB(255, 255, 255)
	em.ZIndex = 5
	em.Parent = holder

	-- A very small ✓ in the corner of a cleared island. Tiny on purpose, and only shown when the circle is
	-- big enough to carry it without turning into noise (see updateIslands).
	local check = Instance.new("TextLabel")
	check.Name = "Check"
	check.AnchorPoint = Vector2.new(1, 1)
	check.Position = UDim2.new(1, 2, 1, 2)
	check.Size = UDim2.fromOffset(9, 9)
	check.BackgroundColor3 = Color3.fromRGB(60, 190, 90)
	check.BorderSizePixel = 0
	check.Font = Enum.Font.GothamBlack
	check.Text = "✓"
	check.TextScaled = true
	check.TextColor3 = Color3.fromRGB(255, 255, 255)
	check.ZIndex = 7
	check.Visible = false
	check.Parent = holder
	Instance.new("UICorner", check).CornerRadius = UDim.new(1, 0)

	-- Hover (PC) and tap (touch) reveal the name. Frames raise MouseEnter/Leave, so no invisible button is
	-- needed; the touch branch auto-hides so a tap does not leave the tooltip stuck open.
	holder.MouseEnter:Connect(function() showIsleTip(i, holder) end)
	holder.MouseLeave:Connect(hideIsleTip)
	holder.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			showIsleTip(i, holder)
			task.delay(1.6, hideIsleTip)
		end
	end)

	isleSlots[i] = { holder = holder, ring = ring, emoji = em, check = check }
	return isleSlots[i]
end

-- ===== EVEN SPACING, COMPUTED -- NEVER EYEBALLED =====
-- Positions are pure maths off the live track width, so every gap is identical and the whole thing re-solves
-- on any resolution / aspect / device the moment the track changes size. State (done / current / future) is
-- read from HighestIsland -- the same server attribute the rest of the HUD uses -- so it updates itself the
-- instant a new island is reached, with no second progression system to keep in sync.
local function updateIslands()
	local n = ISLE_N
	if n < 1 then return end
	local trackW = math.max(1, root.AbsoluteSize.X)
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
	local small = (vp ~= nil and vp.X < 900)
	-- Larger again (~33% over the 18px pass -> 24) so the food icons read at a glance; the runtime audit showed
	-- ~65px between checkpoints on desktop, so 24px leaves a big clear gap. The shrink-to-fit below
	-- (size = min(base, spacing - gap)) still keeps all N seated without touching on a narrow screen.
	local base = small and 20 or 24

	-- padding after START and before FINISH so the first / last circle clears the end dots and pills
	local pad = base / 2 + 6
	local usable = math.max(1, trackW - 2 * pad)
	local spacing = (n > 1) and (usable / (n - 1)) or 0
	-- shrink the circles if the track is too tight to seat them all with a clear gap: never let neighbours touch
	local size = base
	if n > 1 then
		size = math.clamp(math.floor(math.min(base, spacing - ISLE_MIN_GAP)), 9, base)
	end

	local cur = math.clamp(math.floor(tonumber(player:GetAttribute("HighestIsland")) or 1), 1, n)

	for i = 1, n do
		local s = isleMarker(i)
		local xPx = (n > 1) and (pad + (i - 1) * spacing) or (trackW / 2)
		-- position in SCALE so it tracks the parent's width between solves, all on the one centreline
		s.holder.Position = UDim2.new(math.clamp(xPx / trackW, 0, 1), 0, 0.5, ISLE_Y)

		local isCur  = (i == cur)
		local isDone = (i < cur)
		local sz = isCur and (size + ISLE_CUR_BONUS) or size
		s.holder.Size = UDim2.fromOffset(sz, sz)
		s.holder.ZIndex = isCur and 5 or 4       -- current lifts just above its neighbours, still under YOU (8)
		s.emoji.ZIndex  = s.holder.ZIndex + 1
		s.check.ZIndex  = s.holder.ZIndex + 3

		if isCur then
			-- CURRENT: full colour, a gold highlight ring, slightly larger. Obvious at a glance, not shouty.
			s.emoji.TextTransparency = 0
			s.holder.BackgroundTransparency = 0
			s.ring.Color = Color3.fromRGB(255, 210, 70); s.ring.Thickness = 2.5; s.ring.Transparency = 0
			s.check.Visible = false
		elseif isDone then
			-- COMPLETED: bright / normal, with the tiny tick when there is room for it
			s.emoji.TextTransparency = 0
			s.holder.BackgroundTransparency = 0
			s.ring.Color = Color3.fromRGB(255, 255, 255); s.ring.Thickness = 1.5; s.ring.Transparency = 0.15
			s.check.Visible = (sz >= 12)
		else
			-- FUTURE: dimmed but still readable -- the theme stays recognisable
			s.emoji.TextTransparency = 0.35
			s.holder.BackgroundTransparency = 0.25
			s.ring.Color = Color3.fromRGB(180, 190, 210); s.ring.Thickness = 1; s.ring.Transparency = 0.5
			s.check.Visible = false
		end
	end
end

--======================================================================
-- THE YOU MARKER'S LIVE POSITION (the only thing this change touches)
--======================================================================
-- The player's height is turned into a pixel X on the track by PIECEWISE interpolation between the two
-- islands they are currently between, mapped onto the EVENLY-SPACED checkpoint positions. So standing on an
-- island puts YOU exactly on its circle, half-way between two islands puts YOU half-way between the two
-- circles, and a fall walks YOU back down -- regardless of how far apart those two islands are in the world.
-- The checkpoint geometry here MUST match updateIslands() so YOU lands dead-on a checkpoint.
local function youWorldY()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then return hrp.Position.Y end
	local bh = player:GetAttribute("BestHeight")            -- covers loading/dead: last known height
	if type(bh) == "number" then return bh end
	return nil
end

local function youTargetX()
	local trackW = math.max(1, root.AbsoluteSize.X)
	local n = ISLE_N
	if n < 1 then return 0 end
	-- checkpoint pixel of island i -- identical formula to updateIslands()
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
	local small = (vp ~= nil and vp.X < 900)
	local base = small and 20 or 24
	local pad = base / 2 + 6
	local usable = math.max(1, trackW - 2 * pad)
	local spacing = (n > 1) and (usable / (n - 1)) or 0
	local function cx(i) return (n > 1) and (pad + (i - 1) * spacing) or (trackW / 2) end

	local y = youWorldY()
	if type(y) ~= "number" or n < 2 then return cx(1) end   -- unknown height -> sit on the first checkpoint
	if y <= ISLE_WORLD_Y[1] then return cx(1) end            -- at/below island 1
	for i = 1, n - 1 do
		local lo, hi = ISLE_WORLD_Y[i], ISLE_WORLD_Y[i + 1]
		if lo and hi and y < hi then
			local p = (hi > lo) and math.clamp((y - lo) / (hi - lo), 0, 1) or 0   -- % of THIS crossing done
			return cx(i) + (cx(i + 1) - cx(i)) * p
		end
	end
	return cx(n)                                             -- at/above the summit -> final checkpoint
end

-- The pooled holder currently drawing the local player, its smoothed X, and which holder that was last frame
-- (so a slot reassignment snaps instead of sliding). Only the YOU marker is driven this way.
local youHolder = nil
local youDispX = nil
local youLastHolder = nil

--======================================================================
-- UPDATE
--======================================================================
-- Twice a second is enough for a bar this size -- a marker moves less than a pixel per frame at climbing
-- speed -- and the position is tweened between updates so it glides instead of stepping.
local TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function refresh()
	-- YOU's position is now the PIECEWISE checkpoint-space fraction (see youTargetX) instead of the old
	-- linear-world progressOf -- that is the whole fix. Other players still use progressOf (unchanged).
	local width = math.max(1, root.AbsoluteSize.X)
	local me = { p = player, t = math.clamp(youTargetX() / width, 0, 1), mine = true }
	local others = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			others[#others + 1] = { p = p, t = progressOf(p) or 0 }
		end
	end
	-- WHICH FOUR. The ones nearest YOU on the line, not the top four: the player two hundred studs above you
	-- is the one you can actually race. The leader is only interesting if the leader is near you.
	table.sort(others, function(a, b) return math.abs(a.t - me.t) < math.abs(b.t - me.t) end)

	local show = { me }
	for i = 1, math.min(MAX_MARKERS - 1, #others) do show[#show + 1] = others[i] end
	-- Draw left to right so overlapping faces stack in a sensible order.
	table.sort(show, function(a, b) return a.t < b.t end)

	-- ===== SPREAD THEM OUT =====
	-- Position is truth, but two players a hundred studs apart are two pixels apart on a 600-pixel line, and
	-- at the bottom of the tower EVERYBODY is within a few hundred studs of the start. Stacked faces read as
	-- one face, which is exactly the "single tiny icon in the corner" this bar is supposed to replace.
	--
	-- So each face is placed in PIXELS, then pushed apart until no two overlap: one pass left to right
	-- opening MIN_GAP between neighbours, one pass back right to left so the spreading cannot run off the
	-- end of the line. Nobody moves more than a face-width, so the order and the reading stay honest.
	for _, row in ipairs(show) do
		row.x = row.t * width
		row.half = ((row.mine and YOU_DOT or DOT) + MIN_GAP) / 2
	end
	for i = 2, #show do
		local need = show[i - 1].x + show[i - 1].half + show[i].half
		if show[i].x < need then show[i].x = need end
	end
	for i = #show - 1, 1, -1 do
		local cap = show[i + 1].x - show[i + 1].half - show[i].half
		if show[i].x > cap then show[i].x = cap end
	end
	for _, row in ipairs(show) do
		row.x = math.clamp(row.x, 0, width)
	end

	for i = 1, MAX_MARKERS do
		local s = markerAt(i)
		local row = show[i]
		if row then
			local size = row.mine and YOU_DOT or DOT
			s.holder.Size = UDim2.fromOffset(size, size)
			s.holder.ZIndex = row.mine and 8 or 5
			s.ring.Color = row.mine and Color3.fromRGB(255, 196, 60) or Color3.fromRGB(255, 255, 255)
			s.ring.Thickness = row.mine and 3 or 2
			s.ring.Transparency = row.mine and 0 or 0.25
			s.tag.Visible = (row.mine == true) and showYouTag
			s.img.Image = thumbs[row.p.UserId] ~= "" and thumbs[row.p.UserId] or thumbFor(row.p.UserId)
			if row.mine then
				-- YOU's X is driven every frame by the RenderStepped loop below (live piecewise position), so
				-- refresh must NOT tween/set it here -- a tween would fight the per-frame drive. It only keeps the
				-- holder visible and hands the loop the holder currently drawing you.
				s.holder.Visible = true
				youHolder = s.holder
			else
				local at = UDim2.new(0, math.floor(row.x + 0.5), 0.5, 0)   -- pixels: the declutter pass works in them
				if not s.holder.Visible then
					s.holder.Visible = true
					s.holder.Position = at              -- appear in place, do not fly in from the left end
				else
					TweenService:Create(s.holder, TWEEN, { Position = at }):Play()
				end
			end
		else
			s.holder.Visible = false
			if s.holder == youHolder then youHolder = nil end   -- our face left the screen; loop idles
		end
	end

	-- The gold fill trails YOU and is driven live by the RenderStepped loop below (not tweened here), so it
	-- stays glued to the marker as it flies up and walks back down.

	-- Re-solve the fixed island checkpoints on the same clock (cheap: ISLE_N holders, position + state only).
	updateIslands()
end

--======================================================================
-- LAYOUT -- re-measured, never assumed
--======================================================================
-- The viewport is NOT reliable at boot: on the first frames the camera can report a placeholder size, which
-- is how a 2554px-wide screen ended up drawing the narrow-screen layout ("narrow=true" in the log on a
-- desktop). So the geometry is a function, it runs once now and again whenever the viewport changes -- a
-- window resize, a device rotation, or simply the camera settling a frame after this script ran.
-- ===== WHERE THE BANNER ACTUALLY IS =====
-- "Centred" is not the same number for these two on a phone. ResponsiveUI sets ScreenInsets =
-- DeviceSafeInsets on the HUD ScreenGuis, which maps their coordinate space to the device SAFE AREA; this
-- bar ignores the inset entirely (that is what puts it in the strip above the banner). On a notched phone in
-- landscape the safe area is not symmetric -- the notch eats one side -- so the banner's 0.5 and this bar's
-- 0.5 are tens of pixels apart, and the two stacked elements visibly disagree.
--
-- So the centre is MEASURED off the banner rather than assumed: its frame is a fixed 500-wide card whose
-- AbsolutePosition is live even while it is parked off the top of the screen, and AbsolutePosition is in
-- real screen pixels for both of us whatever coordinate space each GUI was built in. On desktop this
-- resolves to exactly vw/2, so nothing there moves.
local function bannerCentreX(vw)
	local sg = PlayerGui:FindFirstChild("NotifyHero")
	local hero = sg and sg:FindFirstChild("Hero", true)
	if hero and hero:IsA("GuiObject") and hero.AbsoluteSize.X > 1 then
		return hero.AbsolutePosition.X + hero.AbsoluteSize.X / 2
	end
	return vw / 2
end

local function layout()
	-- ===== NOTHING MAY SCALE THIS BAR =====
	-- The NoResponsiveScale attribute above is the polite request; this is the enforcement, and on a phone it
	-- is the difference between a centred bar and a stub. A UIScale landing on the Line does two things at
	-- once: it shrinks the whole bar (the audit caught pills at 31x10 instead of 52x18, faces at 13 instead
	-- of 22 -- a clean 0.6x) AND, because the Line's AnchorPoint is (0, 0.5), it shrinks it toward its LEFT
	-- edge, so the midpoint slides left of the banner's. Every "still not centred" report has been this.
	--
	-- Rather than argue about who added it, the bar simply refuses to carry one: any UIScale under this GUI
	-- is flattened to 1 on every layout pass (twice a second). The bar is already responsive on its own
	-- terms -- every number below is a fraction of the live viewport -- so a second scaling system on top can
	-- only ever fight it. On desktop this loop finds nothing and costs one GetDescendants call.
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("UIScale") and d.Scale ~= 1 then d.Scale = 1 end
	end

	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	local vw = (vp and vp.X > 1 and vp.X) or 1280

	local small = vw < 900
	DOT, YOU_DOT = small and 18 or 20, small and 22 or 26

	-- ===== NO START / FINISH PILLS ON A PHONE =====
	-- They are two 52px labels bolted to the ends of a line that is only ~280px long on a phone -- more than a
	-- third of the whole element spent on words, in the strip where every pixel is already contested. The dots
	-- stay, so the ends are still marked; what goes is the labelling, which a phone player does not need
	-- twice (the gold fill already reads as "how far along"). Desktop keeps both: there the pills are a tenth
	-- of the line and the space beside it is empty anyway.
	for _, d in ipairs(root:GetChildren()) do
		if d.Name == "StartPill" or d.Name == "FinishPill" then d.Visible = not small end
	end

	-- The YOU caption goes with them, and for the same reason: on a phone your face is already the biggest
	-- marker on the line and the only one ringed in gold, so the word is spelling out what the highlight has
	-- said. refresh() owns whether the tag shows at all (only ever on YOUR marker); this decides whether the
	-- phone gets it, and refresh reads the flag rather than re-testing the viewport.
	showYouTag = not small
	for _, sl in pairs(slots) do
		if sl.tag then sl.tag.Visible = sl.tag.Visible and showYouTag end
	end

	-- ===== CENTRED ON THE SAME AXIS AS THE BANNER =====
	-- NotifyCenter's card is anchored at 0.5 of the width, so the bar's MIDPOINT has to land on vw/2 or the
	-- two stacked elements read as misaligned -- which is exactly what a line with a big right reserve and a
	-- small left margin does: its centre sits a couple of hundred pixels left of the banner's.
	--
	-- Centring it and keeping the right end clear of the gear + capsule are the same requirement once you
	-- state it properly: take the LARGER of the two margins and use it on BOTH sides. The line is then
	-- symmetric about the screen centre by construction, and its right end is no closer to the capsule than
	-- the reserve allowed. The cost is length -- the left side gives up the difference -- and that is the
	-- correct trade: a tracker that is visibly off-centre under a centred banner looks broken, a slightly
	-- shorter one does not.
	local margin = math.max(
		math.floor(vw * LEFT_PAD),
		math.max(RIGHT_MIN, math.floor(vw * RIGHT_RESERVE))
	) + PILL_ROOM

	local half = math.max(60, vw / 2 - margin)

	-- ===== PHONES GET THE DESKTOP'S PROPORTIONS, NOT THE DESKTOP'S PIXELS =====
	-- The margins above are a fraction PLUS two pixel constants: a 200px right floor and 62px of pill room.
	-- On a 2554px screen those are rounding errors and the line lands at ~40% of the width. On a 600px phone
	-- they are 44% of the whole screen between them, and the line collapsed to a stub -- the same shape
	-- complaint as the very first build, arrived at from the opposite direction.
	--
	-- So below 900px the line is sized by the PROPORTION the desktop settles on (LINE_FRAC), and the pixel
	-- constants are replaced by smaller ones that still clear the gear and capsule after ResponsiveUI has
	-- scaled that cluster down. Whichever of the two is tighter wins, so the line grows to desktop
	-- proportions but can never reach the capsule.
	--
	-- The desktop branch is untouched: nothing above 900px goes through this.
	if vw < 900 then
		local clearance = vw / 2 - (math.floor(vw * RIGHT_RESERVE_SMALL) + PILL_ROOM_SMALL)
		half = math.max(60, math.min(vw * LINE_FRAC / 2, clearance))
	end
	-- Centred on the BANNER's midpoint -- vw/2 everywhere except a phone with an asymmetric safe area.
	root.Position = UDim2.new(0, math.floor(bannerCentreX(vw) - half + NUDGE_X), 0, BAR_Y)
	root.Size = UDim2.new(0, math.floor(half * 2), 0, LINE_H)

	-- The track just changed width: re-space the island checkpoints against the new size so their gaps stay
	-- perfectly even on every resolution / aspect / rotation.
	updateIslands()
end

layout()
do
	local cam = Workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() pcall(layout) end) end
end
-- Reaching a new island flips completed/current/future the instant the server publishes it -- no polling lag.
player:GetAttributeChangedSignal("HighestIsland"):Connect(function() pcall(updateIslands) end)

-- Remove any OTHER ClimbRaceBar ScreenGui that is an older build (a stale copy baked into the place, or an
-- earlier instance of this same script). A build equal-to-or-newer than mine is left alone, so two live
-- copies can never destroy each other in a loop -- only the single newest one survives, and it is the one
-- with these edits. This is the authoritative fix for "the change didn't take effect": the override was a
-- duplicate GUI, and this deletes it at its source rather than fighting it.
local function killStaleClimbBars()
	for _, sg in ipairs(PlayerGui:GetChildren()) do
		if sg ~= gui and sg:IsA("ScreenGui") and sg.Name == "ClimbRaceBar" then
			local b = tonumber(sg:GetAttribute("CRBBuild")) or 0
			local g = tonumber(sg:GetAttribute("CRBGen")) or 0
			if b < CRB_BUILD or (b == CRB_BUILD and g < CRB_GEN) then
				sg:Destroy()
			end
		end
	end
end
pcall(killStaleClimbBars)   -- clear any duplicate that is already on screen at boot

task.spawn(function()
	while true do
		-- Kill stale duplicates first: a baked copy can build its ScreenGui a frame after this one, so the
		-- check has to keep running, not fire once.
		pcall(killStaleClimbBars)
		-- layout() rides the same clock as refresh: NotifyHero is built by a different LocalScript and can
		-- arrive after this one, ResponsiveUI re-applies its insets on rotation, and both change where the
		-- banner's midpoint is. Re-measuring twice a second costs a handful of property reads and means the
		-- two can never drift apart for longer than that.
		pcall(layout)
		pcall(refresh)
		task.wait(0.5)
	end
end)

-- ===== THE YOU MARKER, LIVE, EVERY FRAME =====
-- refresh() (twice a second) decides WHICH pooled face is yours and spreads the others; THIS drives that
-- face's X every frame straight from your real height (youTargetX -> piecewise between the correct two
-- islands, mapped onto the evenly-spaced checkpoints). So it tracks the climb smoothly and walks straight
-- back down the instant you fall -- no fixed-duration tween to the next checkpoint. Light exponential
-- smoothing removes jitter without noticeable lag; a slot hand-off snaps instead of sliding. The gold fill
-- trails it live. This is the only thing that positions the YOU marker.
RunService.RenderStepped:Connect(function(dt)
	local h = youHolder
	if not h or not h.Parent then return end
	local target = youTargetX()
	if h ~= youLastHolder or youDispX == nil then
		youDispX = target                       -- new/first holder: snap, don't slide from a stale spot
		youLastHolder = h
	else
		local a = 1 - math.exp(-dt / 0.05)      -- ~50ms time-constant: follows live, still smooth
		youDispX = youDispX + (target - youDispX) * a
	end
	h.Position = UDim2.new(0, math.floor(youDispX + 0.5), 0.5, 0)
	local w = math.max(1, root.AbsoluteSize.X)
	fill.Size = UDim2.new(math.clamp(youDispX / w, 0, 1), 0, 1, 0)
end)

-- ===== ALWAYS VISIBLE, WITH NOTHING THAT COLLAPSES =====
-- Three separate builds of this file each hid a part of it and each was wrong for the same reason: a
-- position tracker that answers "where is everybody" only sometimes teaches the player not to look.
--   1. It hid itself on phones (a narrow Studio window counted as a phone -- so it never appeared at all).
--   2. It switched off whenever NotifyCenter was busy -- and a PIN can hold that lane for minutes.
--   3. Its YOU caption faded while a banner was up, which is the one label on the bar.
-- All three are gone. The bar, the line, both end labels, every face and the YOU caption are up from boot
-- to leave. Coexistence with the banner card is geometry, not visibility: this sits in the 20-pixel band
-- above the card's text and draws over it (DisplayOrder 96).
--
-- The other half of "never collapses" is in progressOf: a player with no character and no BestHeight is
-- drawn at the START of the line rather than dropped, so the bar shows everyone in the server it can fit.

-- (There was an inset nudge here. It is gone with IgnoreGuiInset = true: the bar is now positioned from
-- the true top of the screen on every device, which is the whole point of BAR_Y being 11.)

--======================================================================
-- RETIRE THE OLD PLANET RACE BOARD
--======================================================================
-- It is a Studio-authored ScreenGui in the place file: this repo cannot delete it, and Rojo cannot overwrite
-- it (Rojo only ADDS). So it is switched off and held off -- exactly what ResponsiveUI already did on phones,
-- now everywhere, because this bar is its replacement. Deleting the RaceBoard object in Studio makes this
-- block a no-op; nothing here depends on it existing.
task.spawn(function()
	local rb = PlayerGui:FindFirstChild("RaceBoard") or PlayerGui:WaitForChild("RaceBoard", 20)
	if rb and rb:IsA("ScreenGui") then
		rb.Enabled = false
		rb:GetPropertyChangedSignal("Enabled"):Connect(function()
			if rb.Enabled then rb.Enabled = false end
		end)
		print("[ClimbRace] old RaceBoard switched off -- this bar replaces it")
	end
end)

do
	-- Count the ClimbRaceBar ScreenGuis after the boot sweep. If this prints more than 1 for more than a
	-- moment, a stale baked copy is present -- delete the duplicate ClimbRaceBar LocalScript in Studio and
	-- republish (this sweep hides its GUI meanwhile, but the extra script is still wasting a frame's work).
	local n = 0
	for _, sg in ipairs(PlayerGui:GetChildren()) do
		if sg:IsA("ScreenGui") and sg.Name == "ClimbRaceBar" then n += 1 end
	end
	print(("[ClimbRace] ready -- BUILD %d gen %d | %d ClimbRaceBar ScreenGui(s) live | line x %d..%d of %dpx, up to %d faces, YOU in gold, always on")
		:format(CRB_BUILD, CRB_GEN, n,
		         root.AbsolutePosition.X, root.AbsolutePosition.X + root.AbsoluteSize.X,
		         (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X) or 0, MAX_MARKERS))
end
