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

-- Narrow means narrow -- measured, not guessed from TouchEnabled, which is true in a Studio emulator and on
-- any laptop with a touchscreen.
local function isNarrow()
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
	return vp ~= nil and vp.X < 900
end

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

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
-- UPDATE
--======================================================================
-- Twice a second is enough for a bar this size -- a marker moves less than a pixel per frame at climbing
-- speed -- and the position is tweened between updates so it glides instead of stepping.
local TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function refresh()
	local me = { p = player, t = progressOf(player) or 0, mine = true }
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
	local width = math.max(1, root.AbsoluteSize.X)
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
			local at = UDim2.new(0, math.floor(row.x + 0.5), 0.5, 0)   -- pixels: the declutter pass works in them
			if not s.holder.Visible then
				s.holder.Visible = true
				s.holder.Position = at              -- appear in place, do not fly in from the left end
			else
				TweenService:Create(s.holder, TWEEN, { Position = at }):Play()
			end
		else
			s.holder.Visible = false
		end
	end

	TweenService:Create(fill, TWEEN, { Size = UDim2.new(me.t, 0, 1, 0) }):Play()
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
end

layout()
do
	local cam = Workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() pcall(layout) end) end
end

task.spawn(function()
	while true do
		-- layout() rides the same clock as refresh: NotifyHero is built by a different LocalScript and can
		-- arrive after this one, ResponsiveUI re-applies its insets on rotation, and both change where the
		-- banner's midpoint is. Re-measuring twice a second costs a handful of property reads and means the
		-- two can never drift apart for longer than that.
		pcall(layout)
		pcall(refresh)
		task.wait(0.5)
	end
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

print(("[ClimbRace] ready -- line x %d..%d of %dpx (stops clear of the gear + currency capsule), up to %d faces, YOU in gold, always on")
	:format(root.AbsolutePosition.X, root.AbsolutePosition.X + root.AbsoluteSize.X,
	         (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X) or 0, MAX_MARKERS))
