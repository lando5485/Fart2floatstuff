-- BlimpService.server.lua  (Script)  -- the PLS DONATE-style airship that laps Bean Farm.
--
-- A blimp circles the spawn island carrying two live billboards:
--   PORT  side -> TOP DONATORS  (all-time, cross-server, from an OrderedDataStore)
--   STARBOARD -> RECENT PURCHASES (this server's session: every Robux gamepass + Developer Product)
--
-- WHY A NEW DONOR STORE: the garden already tracks donations, but only as a UNIQUE-DONOR FLAG ("donor_<uid>")
-- so it can print "N players contributed". It never summed how much each person gave, so there was no
-- top-donator data to rank. This owns that: an OrderedDataStore of userId -> lifetime Robux donated.
--
-- RECEIPTS: PlayerStats owns the place's SINGLE MarketplaceService.ProcessReceipt. This does NOT assign it --
-- it exposes _G.blimpRecordPurchase(player, productId), which PlayerStats calls. Gamepasses need no hook at
-- all: PromptGamePassPurchaseFinished is a SIGNAL, so we just connect our own listener alongside theirs.

local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService    = game:GetService("DataStoreService")
local RunService          = game:GetService("RunService")
local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

--======================================================================
-- ONE BLIMP ONLY. A stale copy of this script is baked into the place, so BOTH run and BOTH build an
-- airship -- the Output shows two "[Blimp] airborne" lines from two different line numbers, at two
-- different heights, and you see two blimps lapping the island slightly apart.
--
-- Killing the duplicate SCRIPT is not enough on its own: by the time we get here it may already be
-- mid-build, and a Script that has started keeps running for a while after it's destroyed. So this does
-- both -- retire the rival script, then repeatedly sweep Workspace for any DonationBlimp that isn't the
-- one WE built (ours carries the BuiltByLiveScript attribute). The sweep repeats because the stale copy
-- waits ~6s for the islands to settle before parenting its blimp, so a single pass at startup misses it.
--======================================================================
do
	local removed = 0
	for _, inst in ipairs(ServerScriptService:GetDescendants()) do
		if inst ~= script and inst:IsA("Script") and inst.Name == script.Name then
			pcall(function() inst.Disabled = true; inst:Destroy() end)
			removed += 1
		end
	end
	if removed > 0 then
		warn(("[Blimp] retired %d STALE duplicate BlimpService script(s) -- they were flying a SECOND blimp. "
			.. "Delete them in Studio for good."):format(removed))
	end
end

-- ============================================================================
-- CONFIG
-- ============================================================================

local LAP_RADIUS    = 150    -- studs from the island centre
local LAP_ALTITUDE  = -5     -- studs above the island's top surface (110 -> ... -> 3 -> -5; it orbits OFF the island's
                             -- edge at radius 150, so sitting below the island's top line is safe and much easier to notice)
local LAP_SECONDS   = 75     -- one full circuit
local BLIMP_SCALE   = 1.35   -- whole-ship scale-up (applied via Model:ScaleTo after the build): bigger hull,
                             -- bigger boards, bigger sign text on screen -- readable from the ground
local PAGE_SECONDS  = 18     -- how long the starboard board holds each page before rotating to the next
local BOB_HEIGHT    = 4      -- gentle vertical bob, studs
local BOB_SECONDS   = 9
local TOP_BUYERS_N  = 8      -- players listed on the MOST PURCHASES board
local BOARD_REFRESH = 60     -- seconds between top-donator re-reads (DataStore budget)
local TOP_N         = 8      -- donators listed

-- Everything the player can spend Robux on -> how it reads on the feed. `robux` is set ONLY for donations
-- (their price IS the donation), and is what gets banked into the top-donator store.
local PRODUCTS = {
	-- Developer Products
	[3600302990] = { verb = "bought",   label = "2x Fart Power (1hr)" },
	[3600303163] = { verb = "bought",   label = "Mid-Air Recharge" },
	[3600303265] = { verb = "bought",   label = "Skip Island" },
	[3600303082] = { verb = "bought",   label = "Bird Nuke" },
	-- Garden donations (these bank into the donor leaderboard)
	[3608150932] = { verb = "donated",  label = "25 R$",   robux = 25 },
	[3608151059] = { verb = "donated",  label = "100 R$",  robux = 100 },
	[3608151160] = { verb = "donated",  label = "500 R$",  robux = 500 },
	[3608151576] = { verb = "donated",  label = "1000 R$", robux = 1000 },
}

local GAMEPASSES = {
	[1862015450] = "2x Fart Power Forever",
	[1859714979] = "Glitter Fart Trail",
	[1860686821] = "Infinite Gut",
}

-- ============================================================================

local donorStore = DataStoreService:GetOrderedDataStore("TopDonors_v1")
-- MOST PURCHASES is a COUNT, not a total spend -- one key per player, +1 per purchase. Deliberately a
-- separate store from TopDonors_v1: that one ranks by Robux, this one by how many times you have bought
-- anything, so a player who buys a lot of cheap things can top this board without out-spending a whale.
local buyerStore = DataStoreService:GetOrderedDataStore("TopBuyers_v1")

local topBuyers  = {}   -- [{name=, count=}] refreshed every BOARD_REFRESH
local topDonors  = {}   -- [{userId=, name=, robux=}] refreshed every BOARD_REFRESH
local nameCache  = {}   -- [userId] = username (GetNameFromUserIdAsync is a web call; don't repeat it)

-- =====================  DATA  =====================

local function userName(userId)
	if nameCache[userId] then return nameCache[userId] end
	local nm
	local ok = pcall(function() nm = Players:GetNameFromUserIdAsync(userId) end)
	nm = (ok and nm) or ("User " .. userId)
	nameCache[userId] = nm
	return nm
end

-- Bank a donation. IncrementAsync (not Set) so simultaneous donations on different servers can't clobber
-- each other -- the store does the add server-side.
local function bankDonation(player, robux)
	nameCache[player.UserId] = player.Name -- free: we already know who they are
	local ok, err = pcall(function()
		donorStore:IncrementAsync(tostring(player.UserId), robux)
	end)
	if not ok then
		warn("[Blimp] failed to bank " .. robux .. " R$ for " .. player.Name .. ": " .. tostring(err))
	end
end

local function refreshTopDonors()
	local ok, pages = pcall(function()
		return donorStore:GetSortedAsync(false, TOP_N) -- false = descending, biggest donors first
	end)
	if not ok then
		warn("[Blimp] top-donator read failed -- keeping the last good board")
		return -- DELIBERATE: keep showing the previous list rather than blanking the board on a blip
	end
	local fresh = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		-- The userId is carried, not just the name: the board draws each donor's AVATAR, and rbxthumb needs
		-- the id. entry.key is the string form of the UserId -- it is the only place it exists on this path.
		local uid = tonumber(entry.key)
		fresh[#fresh + 1] = { userId = uid, name = userName(uid), robux = entry.value }
	end
	topDonors = fresh
end

-- +1 purchase for this player. IncrementAsync for the same reason bankDonation uses it: two servers can
-- process a receipt for the same player at once, and the store does the add itself so neither is lost.
local function bankPurchase(player)
	nameCache[player.UserId] = player.Name
	local ok, err = pcall(function()
		buyerStore:IncrementAsync(tostring(player.UserId), 1)
	end)
	if not ok then
		warn("[Blimp] failed to count a purchase for " .. player.Name .. ": " .. tostring(err))
	end
end

local function refreshTopBuyers()
	local ok, pages = pcall(function()
		return buyerStore:GetSortedAsync(false, TOP_BUYERS_N) -- false = descending, most purchases first
	end)
	if not ok then
		warn("[Blimp] top-buyer read failed -- keeping the last good board")
		return -- same rule as the donor board: keep the last good list rather than blanking on a blip
	end
	local fresh = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		fresh[#fresh + 1] = { name = userName(tonumber(entry.key)), count = entry.value }
	end
	topBuyers = fresh
end

-- =====================  THE BLIMP  =====================

local function part(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part")
	p.Name         = name
	p.Shape        = shape
	p.Size         = size
	p.Color        = color
	p.CFrame       = cf
	p.Material     = material or Enum.Material.SmoothPlastic
	p.Anchored     = true   -- the whole blimp is CFrame-driven; physics would fight the flight path
	-- SOLID, so you can land on it and ride. It used to be CanCollide=false so a flying player couldn't be
	-- swatted out of the sky by it; that trade is now the other way round -- a blimp you can stand on is worth
	-- the occasional bump, and it laps at 150 studs out where nobody is climbing anyway.
	--
	-- CARRYING passengers takes two things on top of this, because an anchored CFrame-driven part moves THROUGH
	-- the world instead of pushing what rests on it: the DECK SEATS below (a Seat welds its rider to the hull,
	-- so sitting is carried perfectly and for free), and BlimpRide.client.luau, which walks the local player
	-- along with the ship each frame while they stand on the deck.
	p.CanCollide   = true
	p.CanQuery     = false
	p.TopSurface   = Enum.SurfaceType.Smooth
	p.BottomSurface= Enum.SurfaceType.Smooth
	p.Parent       = parent
	return p
end

-- ===== ONE BIG SCREEN, FACING INWARD, TILTED DOWN AT THE GROUND =====
-- The blimp used to carry TWO boards, one on each flank. From the island you always saw the far one edge-on
-- (or its blank back) behind the near one, which is the "old display behind the new one" -- and both hung
-- dead vertical, so from directly below you were reading a sign side-on at 60+ studs.
--
-- WHICH SIDE FACES INWARD: the flight loop does CFrame.lookAt(pos, pos + tangent) with tangent =
-- (-sin a, 0, cos a) and pos = (cos a, y, sin a) * R. Working the basis through, the CFrame's X axis comes
-- out as (-cos a, 0, -sin a) -- pointing straight at the island centre. So +X (STARBOARD) is the inward
-- side, and that is the only side that gets a screen now.
--
-- TILT: rotating about the blimp's forward (Z) axis by a negative angle swings that +X face downward, so
-- the screen leans out over the island like a stadium scoreboard instead of standing vertical.
local BOARD_TILT = math.rad(-28)
-- THE STUDIO SLIDE IS A PICTURE. Page 1 used to be a text card (FART TO FLOAT / players online / event
-- live) under an "MLR STUDIOS" header; it is now this uploaded image, full-bleed, with the header and rows
-- hidden while it is up. Pages 2 and 3 are untouched.
--
-- It must be an IMAGE asset id (Studio's Asset Manager -> Images), not a Decal id -- a decal id renders as
-- a blank board with no error. If the slide ever comes up empty, check that first, then check moderation.
local BOARD_PICTURE_ID = "rbxassetid://137427044738819"
local function board(model, name, offsetCF, title, accent)
	-- everything is built in a TILTED frame, so the bezel, arms and panel all lean together
	local cf = offsetCF * CFrame.Angles(0, 0, BOARD_TILT)

	-- Bezel: a slightly larger, darker slab behind the screen so the panel has a visible frame + depth.
	part(model, name .. "Bezel", Enum.PartType.Block, Vector3.new(0.5, 27.4, 57.4),
		Color3.fromRGB(24, 26, 33), cf * CFrame.new(-0.35, 0, 0))
	-- Standoff arms, so the sign reads as MOUNTED to the hull rather than floating beside it.
	for _, dz in ipairs({ -18, 18 }) do
		part(model, "BoardArm", Enum.PartType.Cylinder, Vector3.new(3.4, 0.6, 0.6),
			Color3.fromRGB(38, 41, 50), cf * CFrame.new(-2.2, 7.5, dz))
	end

	-- MUCH BIGGER: 26 x 56 studs, up from 16 x 34 -- roughly 2.7x the area, which is what actually decides
	-- whether any of this is legible from the ground.
	local panel = part(model, name, Enum.PartType.Block, Vector3.new(0.5, 26, 56),
		Color3.fromRGB(16, 18, 24), cf)

	local gui = Instance.new("SurfaceGui")
	gui.Name           = "Board"
	gui.Face           = Enum.NormalId.Right    -- +X: the inward face (see the note above)
	gui.CanvasSize     = Vector2.new(1120, 520)
	gui.LightInfluence = 0                      -- the sign is lit, not shaded by the world -- keeps it readable at dusk
	gui.AlwaysOnTop    = false
	gui.MaxDistance    = 1200                   -- it is bigger now; let it stay readable from further out
	gui.Parent         = panel

	local bg = Instance.new("Frame")
	bg.Size             = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(17, 19, 26)
	bg.BorderSizePixel  = 0
	bg.Parent           = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent       = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color     = accent
	stroke.Thickness = 4
	stroke.Transparency = 0.35
	stroke.Parent    = bg

	-- Header bar. Taller and heavier than before -- from the ground the header is often the ONLY thing a
	-- player actually resolves, so it carries the studio name and the page title.
	local head = Instance.new("Frame")
	head.Size             = UDim2.new(1, 0, 0, 132)
	head.BackgroundColor3 = accent
	head.BorderSizePixel  = 0
	head.Parent           = bg
	local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 18); hc.Parent = head
	-- Square off the header's bottom corners so it butts flush against the body instead of floating.
	local hfill = Instance.new("Frame")
	hfill.Size             = UDim2.new(1, 0, 0, 20)
	hfill.Position         = UDim2.new(0, 0, 1, -20)
	hfill.BackgroundColor3 = accent
	hfill.BorderSizePixel  = 0
	hfill.Parent           = head

	local htxt = Instance.new("TextLabel")
	htxt.Size                   = UDim2.fromScale(1, 1)
	htxt.BackgroundTransparency = 1
	htxt.Font                   = Enum.Font.GothamBlack
	htxt.Text                   = title
	htxt.TextColor3             = Color3.fromRGB(14, 16, 22) -- dark ink on the bright bar: max contrast
	htxt.TextSize               = 96                          -- ground-legible, not desk-legible
	htxt.ZIndex                 = 2
	htxt.Parent                 = head

	-- Row container
	local rows = Instance.new("Frame")
	rows.Name                   = "Rows"
	rows.Position               = UDim2.new(0, 26, 0, 150)
	rows.Size                   = UDim2.new(1, -52, 1, -176)
	rows.BackgroundTransparency = 1
	rows.Parent                 = bg

	local layout = Instance.new("UIListLayout")
	layout.Padding   = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent    = rows

	-- ===== THE PICTURE LAYER =====
	-- A full-bleed ImageLabel sitting OVER the header and the rows, hidden by default. The studio page
	-- draws it instead of text (see renderStudio), so page 1 is the artwork edge to edge and pages 2-3 are
	-- the leaderboard exactly as they were.
	--
	-- ScaleType = Fit, not Stretch, ON PURPOSE. The board is 2.154:1 (56 x 26 studs, 1120 x 520 canvas) and
	-- an image that is even slightly off that would be silently squashed by Stretch -- which on a logo is
	-- the kind of wrong you stop noticing after ten minutes and ship. Fit letterboxes instead, against the
	-- board's own dark background, so a mismatch reads as a deliberate border rather than as bad art.
	local pic = Instance.new("ImageLabel")
	pic.Name                   = "Picture"
	pic.Size                   = UDim2.fromScale(1, 1)
	pic.BackgroundColor3       = Color3.fromRGB(17, 19, 26) -- the letterbox bars, same ink as the board
	pic.BorderSizePixel        = 0
	pic.ScaleType              = Enum.ScaleType.Fit
	pic.Image                  = BOARD_PICTURE_ID
	pic.Visible                = false
	pic.ZIndex                 = 5                          -- over the header bar and the rows
	pic.Parent                 = bg
	local pcorner = Instance.new("UICorner"); pcorner.CornerRadius = UDim.new(0, 18); pcorner.Parent = pic

	return rows, accent, htxt, pic -- htxt so a rotating board can retitle itself per page; pic = the artwork page
end

-- One row on a board: an optional coloured rank badge, an optional AVATAR HEADSHOT, a name, and a
-- right-aligned value.
--
-- ===== WHY THE FACE IS BIG =====
-- This is a sign on the side of an airship doing laps two hundred studs up. A player reads it from the
-- ground, at a glance, while flying -- which is why the rows are 74px and the name is 48pt. A face has to
-- obey the same rule: at row height it is unmistakable, at "list avatar" size it is a smudge. So the
-- portrait fills the row (64 of 74px), circular, ringed in the rank's own medal colour so first place still
-- reads as first place from a distance where you cannot make out the number.
--
-- rbxthumb:// rather than GetUserThumbnailAsync -- the async call yields and throws on a deleted account, and
-- this runs on the SERVER inside a board refresh. The content URL is a plain string Roblox resolves per
-- client; a dead id renders blank. 150x150 because the sign is huge: asking for 48px art and scaling it up
-- is how you get a blurry face on a billboard.
local function addRow(rows, order, badgeText, badgeColor, leftText, rightText, faceUid, faceRing)
	local row = Instance.new("Frame")
	row.LayoutOrder            = order
	row.Size                   = UDim2.new(1, 0, 0, 74) -- taller rows: fewer, bigger lines beat more, smaller ones
	row.BackgroundColor3       = Color3.fromRGB(28, 31, 41)
	row.BackgroundTransparency = (order % 2 == 0) and 0.45 or 0.15 -- zebra striping: much easier to scan
	row.BorderSizePixel        = 0
	row.Parent                 = rows
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = row

	local x = 14
	if badgeText then
		local badge = Instance.new("TextLabel")
		badge.Position         = UDim2.new(0, x, 0.5, -26)
		badge.Size             = UDim2.new(0, 52, 0, 52)
		badge.BackgroundColor3 = badgeColor
		badge.Font             = Enum.Font.GothamBlack
		badge.Text             = badgeText
		badge.TextColor3       = Color3.fromRGB(16, 18, 24)
		badge.TextSize         = 34
		badge.BorderSizePixel  = 0
		badge.Parent           = row
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(1, 0); bc.Parent = badge
		x = x + 68
	end

	if faceUid then
		local FACE = 64
		local face = Instance.new("ImageLabel")
		face.Name             = "Face"
		face.Position         = UDim2.new(0, x, 0.5, -FACE / 2)
		face.Size             = UDim2.fromOffset(FACE, FACE)
		face.BackgroundColor3 = Color3.fromRGB(18, 20, 28)   -- shows while the thumbnail loads
		face.BorderSizePixel  = 0
		face.Image            = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(faceUid)
		face.Parent           = row
		Instance.new("UICorner", face).CornerRadius = UDim.new(1, 0)
		local fr = Instance.new("UIStroke")
		fr.Color     = faceRing or Color3.fromRGB(238, 241, 248)
		fr.Thickness = 3
		fr.Parent    = face
		x = x + FACE + 14
	end

	local nm = Instance.new("TextLabel")
	nm.Position               = UDim2.new(0, x, 0, 0)
	-- Reserve the value column only when there IS one, else let the text run the full width.
	nm.Size                   = UDim2.new(1, -x - (rightText and 240 or 14), 1, 0)
	nm.BackgroundTransparency = 1
	nm.Font                   = Enum.Font.GothamBold
	nm.Text                   = leftText
	nm.TextColor3             = Color3.fromRGB(238, 241, 248)
	nm.TextSize               = 48
	nm.TextXAlignment         = Enum.TextXAlignment.Left
	nm.TextTruncate           = Enum.TextTruncate.AtEnd -- long usernames must not shove the value off the sign
	nm.Parent                 = row

	if rightText then
		local val = Instance.new("TextLabel")
		val.Position               = UDim2.new(1, -230, 0, 0)
		val.Size                   = UDim2.new(0, 216, 1, 0)
		val.BackgroundTransparency = 1
		val.Font                   = Enum.Font.GothamBlack
		val.Text                   = rightText
		val.TextColor3             = Color3.fromRGB(255, 214, 92)
		val.TextSize               = 48
		val.TextXAlignment         = Enum.TextXAlignment.Right
		val.Parent                 = row
	end
end

local function clearRows(rows)
	for _, c in ipairs(rows:GetChildren()) do
		-- Everything EXCEPT the layout: rows are Frames but the empty-state note is a TextLabel, and if we only
		-- swept Frames the "no donations yet" note would survive under the first real entry forever.
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
end

local function emptyNote(rows, text)
	local lbl = Instance.new("TextLabel")
	lbl.Name                   = "Empty"
	lbl.LayoutOrder            = 1
	lbl.Size                   = UDim2.new(1, 0, 0, 90)
	lbl.BackgroundTransparency = 1
	lbl.Font                   = Enum.Font.GothamMedium
	lbl.Text                   = text
	lbl.TextColor3             = Color3.fromRGB(120, 128, 145)
	lbl.TextSize               = 32
	lbl.TextWrapped            = true
	lbl.Parent                 = rows
end

-- Find Bean Farm and get its centre + top. Both names are in play across the codebase.
local function findIsland1()
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and (m.Name == "Bean Farm" or m.Name:match("^Island_1_")) then return m end
	end
	return nil
end

local island = nil
for _ = 1, 60 do -- PlayerStats repositions the islands a few seconds into the server's life; wait it out
	island = findIsland1()
	if island then break end
	task.wait(0.5)
end
if not island then
	warn("[Blimp] ABORT: Bean Farm / Island_1_* not found in Workspace")
	return
end
task.wait(6) -- let PlayerStats finish its "Positioned Island_1_BeanFarm at Y=..." pass before we read the centre

local originCF, islandSize = island:GetBoundingBox()
local centre = originCF.Position
-- HEIGHT_SCALE brings the whole lap down by a percentage of how high it rides above the island's centre.
-- Scaling the computed height rather than LAP_ALTITUDE is deliberate: LAP_ALTITUDE is a small offset from the
-- island's top line (-5), so taking 10% off THAT would move the blimp half a stud. The number that actually
-- decides how high it looks is (islandSize.Y / 2 + LAP_ALTITUDE) -- about 132 studs over Bean Farm -- so that
-- is what gets scaled: 0.90 drops the lap ~13 studs, Y 373 -> ~360.
local HEIGHT_SCALE = 0.90
local flyY   = centre.Y + (islandSize.Y / 2 + LAP_ALTITUDE) * HEIGHT_SCALE

local blimp = Instance.new("Model")
blimp.Name = "DonationBlimp"

-- ===== ENVELOPE =====
-- A real airship is a STREAMLINED BODY OF REVOLUTION: a blunt nose, maximum girth about a third of the way
-- back, then a long taper to a point. Stacked spheres can't do that -- they read as a caterpillar. Instead we
-- slice the hull into thin discs (cylinders) along its axis and set each disc's diameter from the classic
-- streamline profile r(s) = s^0.5 * (1-s)^0.8, s = 0 at the nose, 1 at the tail. The sqrt term gives the fat
-- rounded nose; the (1-s)^0.8 term gives the long tail. Peaks at s = 0.385 -- which is where a real airship
-- carries its widest frame. Enough slices and the facets disappear.
-- LOW-POLY, NOT LOW-EFFORT: the silhouette is smooth (many slices, so no lumps or banding), but the SHADING
-- stays flat -- solid colours, SmoothPlastic, zero reflectance. Gloss and glass fight the Roblox look; a clean
-- form with bold flat paint IS the low-poly aesthetic.
local HULL      = Color3.fromRGB(214, 78, 92)   -- envelope
local HULL_DARK = Color3.fromRGB(176, 58, 72)   -- painted belly band
local HULL_TRIM = Color3.fromRGB(248, 216, 96)  -- gold accent stripe
local LENGTH    = 78
local MAX_R     = 8.6
local SLICES    = 120
local OVERLAP   = 2.6   -- each disc is 2.6x its own spacing long, so it buries itself in its neighbours
local PROFILE_K = 2.376 -- normalises the profile's peak to exactly 1.0 (see the maths above)

local function hullRadius(s)
	if s <= 0 or s >= 1 then return 0 end
	return MAX_R * PROFILE_K * (s ^ 0.5) * ((1 - s) ^ 0.8)
end

-- COSINE (Chebyshev) SPACING -- this is what actually makes it smooth, more than raw slice count.
-- With EVENLY spaced slices, the nose still steps visibly: r(s) = sqrt(s) near s=0, so the radius changes
-- almost vertically there, and each equal-width disc has to jump a big radius gap. Mapping the slice index
-- through 0.5 - 0.5*cos(pi*u) clusters slices tightly at the nose and tail (where curvature is extreme) and
-- spreads them out through the middle (where the hull is nearly a tube and nobody needs the detail). Same
-- part budget, dramatically smoother silhouette.
local function station(u) return 0.5 - 0.5 * math.cos(math.pi * u) end

for i = 1, SLICES do
	local s0, s1 = station((i - 1) / SLICES), station(i / SLICES)
	local sMid   = (s0 + s1) * 0.5
	local r      = hullRadius(sMid)
	local z0, z1 = -LENGTH / 2 + s0 * LENGTH, -LENGTH / 2 + s1 * LENGTH
	local len    = (z1 - z0) * OVERLAP -- per-slice length, since spacing is no longer uniform
	if r > 0.25 and len > 0.05 then
		-- A Roblox cylinder's flat faces sit on +/-X, so yaw it 90deg to lie along the blimp's Z axis.
		local d = r * 2
		-- Flat colour blocking: a wide painted band around the widest third, with a thin gold pinstripe at each
		-- edge of it. Blocks of solid colour, no gradients -- that's what sells the stylised look.
		local col = HULL
		if sMid > 0.315 and sMid < 0.605 then col = HULL_DARK end
		if (sMid > 0.300 and sMid <= 0.315) or (sMid >= 0.605 and sMid < 0.620) then col = HULL_TRIM end
		part(blimp, "Hull" .. i, Enum.PartType.Cylinder,
			Vector3.new(len, d, d), col,
			CFrame.new(0, 0, (z0 + z1) * 0.5) * CFrame.Angles(0, math.rad(90), 0))
	end
end
-- Rounded caps so the nose and tail terminate in a curve, not a flat disc.
part(blimp, "NoseCap", Enum.PartType.Ball, Vector3.new(4.0, 4.0, 4.0), HULL_TRIM, CFrame.new(0, 0, -LENGTH / 2 + 1.5))
part(blimp, "TailCap", Enum.PartType.Ball, Vector3.new(1.8, 1.8, 1.8), HULL,      CFrame.new(0, 0,  LENGTH / 2 - 0.7))

-- ===== TAIL =====
-- Cruciform: four fins at 90deg, each a tapered blade + a darker trailing control surface. Real airships put
-- these right at the stern where the hull has narrowed, so they sit close to the axis.
local FIN      = Color3.fromRGB(238, 240, 244)
local FIN_TRIM = Color3.fromRGB(206, 74, 88)
local tailZ    = LENGTH / 2 - 9
for i = 0, 3 do
	local a   = math.rad(45 + i * 90) -- X pattern, so the bottom fins straddle the gondola instead of hitting it
	local dir = CFrame.Angles(0, 0, a)
	part(blimp, "Fin" .. i, Enum.PartType.Block, Vector3.new(0.5, 9.5, 8.5), FIN,
		CFrame.new(0, 0, tailZ) * dir * CFrame.new(0, 6.2, 0))
	part(blimp, "FinTrim" .. i, Enum.PartType.Block, Vector3.new(0.56, 9.5, 2.2), FIN_TRIM,
		CFrame.new(0, 0, tailZ + 3.4) * dir * CFrame.new(0, 6.2, 0)) -- trailing-edge control surface
end

-- ===== GONDOLA =====
-- Layered, tapered, and windowed rather than one slab.
local SHELL  = Color3.fromRGB(58, 62, 74)
local TRIM   = Color3.fromRGB(232, 234, 240)
local GLASS  = Color3.fromRGB(126, 186, 214)
local gY     = -MAX_R - 3.2

part(blimp, "GondolaHull",  Enum.PartType.Block, Vector3.new(5.2, 3.2, 16), SHELL, CFrame.new(0, gY, 1))
part(blimp, "GondolaBelly", Enum.PartType.Cylinder, Vector3.new(15, 4.6, 4.6), SHELL,
	CFrame.new(0, gY - 0.9, 1) * CFrame.Angles(0, math.rad(90), 0))     -- rounded underside
part(blimp, "GondolaNose",  Enum.PartType.Ball, Vector3.new(4.6, 4.0, 4.6), SHELL, CFrame.new(0, gY, -6.6))
part(blimp, "GondolaRoof",  Enum.PartType.Block, Vector3.new(5.4, 0.5, 16), TRIM,  CFrame.new(0, gY + 1.7, 1))

--======================================================================
-- PASSENGER DECK: the gondola roof, with a rail so you don't walk straight off it, and four seats.
--======================================================================
-- SEATS ARE THE RELIABLE HALF OF "carry me". A Seat welds its occupant to itself, and a character welded to
-- an anchored part becomes part of that anchored assembly -- so it follows the blimp EXACTLY, with no
-- per-frame work, no network-ownership fight, and no drift. Standing passengers are handled separately by
-- BlimpRide.client.luau; sitting works on its own the moment you touch a seat.
do
	local RAIL = Color3.fromRGB(214, 218, 228)
	local deckY = gY + 1.95   -- just above the roof's top face
	-- Rails down both long sides + one across the tail. The nose end is left open as the way on.
	part(blimp, "DeckRailL", Enum.PartType.Block, Vector3.new(0.25, 1.6, 16), RAIL, CFrame.new(-2.6, deckY + 0.8, 1))
	part(blimp, "DeckRailR", Enum.PartType.Block, Vector3.new(0.25, 1.6, 16), RAIL, CFrame.new( 2.6, deckY + 0.8, 1))
	part(blimp, "DeckRailB", Enum.PartType.Block, Vector3.new(5.4, 1.6, 0.25), RAIL, CFrame.new(0, deckY + 0.8, 9))

	for i, z in ipairs({ -4.5, -1.0, 2.5, 6.0 }) do
		local s = Instance.new("Seat")
		s.Name = "DeckSeat" .. i
		s.Size = Vector3.new(2.2, 0.4, 2.2)
		s.CFrame = CFrame.new(0, deckY + 0.2, z)
		s.Color = Color3.fromRGB(96, 104, 122)
		s.Material = Enum.Material.SmoothPlastic
		s.Anchored = true
		s.CanCollide = true
		s.CanTouch = true    -- a Seat seats you on TOUCH, so unlike the hull this one must stay touchable
		s.CanQuery = false
		s.TopSurface = Enum.SurfaceType.Smooth
		s.BottomSurface = Enum.SurfaceType.Smooth
		s.Parent = blimp
	end
end

-- Cockpit + cabin windows. FLAT bright colour, NOT Material.Glass: real glass with reflectance reads as a
-- glossy sim asset and clashes with everything else here. A solid pale-blue block is the low-poly convention
-- for a window, and it stays readable from 60 studs up, which actual glass would not.
part(blimp, "Windshield", Enum.PartType.Block, Vector3.new(4.2, 1.9, 2.0), GLASS,
	CFrame.new(0, gY + 0.4, -6.0) * CFrame.Angles(math.rad(-16), 0, 0))
for i = 0, 4 do
	for _, sx in ipairs({ -1, 1 }) do
		part(blimp, "Window", Enum.PartType.Block, Vector3.new(0.3, 1.1, 1.4), GLASS,
			CFrame.new(sx * 2.65, gY + 0.35, -2.6 + i * 2.5))
	end
end

-- ===== ENGINES =====
-- A nacelle on each flank with a prop that actually spins (driven in the flight loop below).
local props = {} -- [{part=, offset=}] -- local offsets, re-applied every frame on top of the blimp's CFrame
for _, sx in ipairs({ -1, 1 }) do
	local nx = sx * 5.6
	part(blimp, "Pylon", Enum.PartType.Block, Vector3.new(2.6, 0.5, 0.9), SHELL, CFrame.new(sx * 3.9, gY + 0.6, 5.2))
	part(blimp, "Nacelle", Enum.PartType.Cylinder, Vector3.new(4.6, 2.5, 2.5), Color3.fromRGB(44, 47, 56),
		CFrame.new(nx, gY + 0.6, 5.2) * CFrame.Angles(0, math.rad(90), 0))
	part(blimp, "Spinner", Enum.PartType.Ball, Vector3.new(1.2, 1.2, 1.2), HULL_TRIM,
		CFrame.new(nx, gY + 0.6, 7.7))

	-- Two crossed blades. They spin about the blimp's forward (Z) axis, so the local CFrame is a Z rotation.
	for b = 0, 1 do
		local blade = part(blimp, "Blade", Enum.PartType.Block, Vector3.new(0.22, 5.6, 0.7),
			Color3.fromRGB(36, 38, 45), CFrame.new(nx, gY + 0.6, 7.9))
		props[#props + 1] = {
			part   = blade,
			origin = Vector3.new(nx, gY + 0.6, 7.9),
			phase  = b * math.pi / 2, -- 90deg apart -> a 2-blade cross
			dir    = sx,              -- counter-rotating pair, like the real thing
		}
	end
end

-- ===== RIGGING + BEACON =====
for _, sx in ipairs({ -1, 1 }) do
	for _, dz in ipairs({ -5.5, 7.5 }) do
		local cable = part(blimp, "Cable", Enum.PartType.Cylinder, Vector3.new(4.4, 0.16, 0.16),
			Color3.fromRGB(30, 32, 38), CFrame.new())
		local top    = Vector3.new(sx * 2.4, gY + 3.9, dz)
		local bottom = Vector3.new(sx * 2.4, gY + 1.7, dz)
		cable.CFrame = CFrame.lookAt((top + bottom) / 2, top) * CFrame.Angles(0, math.rad(90), 0)
		cable.Size   = Vector3.new((top - bottom).Magnitude, 0.16, 0.16)
	end
end
local beacon = part(blimp, "Beacon", Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9),
	Color3.fromRGB(255, 70, 70), CFrame.new(0, gY - 2.2, 1))
beacon.Material = Enum.Material.Neon
local beaconLight = Instance.new("PointLight")
beaconLight.Color      = Color3.fromRGB(255, 70, 70)
beaconLight.Range      = 26
beaconLight.Brightness  = 2
beaconLight.Parent     = beacon

-- The two billboards, hung off the flanks. They MUST sit outside MAX_R (8.6) or they'd be buried inside the
-- envelope and invisible; 9.5 clears the widest frame with a little daylight, like a real banner on standoffs.
-- ONE SCREEN. The port-side board is gone entirely -- it was the display you saw edge-on (or blank-backed)
-- behind the near one from the ground. This single board hangs off the STARBOARD flank, which is the side
-- that faces the island (see the note on board()), pushed out to 13 so the 26-stud panel clears the hull's
-- widest frame once tilted, and dropped slightly so the tilt aims it down the outside of the envelope.
local boardRows, _, boardTitle, boardPic = board(blimp, "MainBoard", CFrame.new(13, -2, -4), "MLR STUDIOS",
	Color3.fromRGB(120, 200, 255))

-- An explicit invisible root, rather than borrowing a hull slice -- the slice list is generated, so which
-- parts exist depends on the profile maths, and PrimaryPart must not be able to come back nil.
local root = part(blimp, "Root", Enum.PartType.Block, Vector3.new(1, 1, 1), HULL, CFrame.new())
root.Transparency = 1
blimp.PrimaryPart = root


-- ===== SCALE-UP =====
-- The whole ship grows through ONE Model:ScaleTo rather than by editing forty hand-tuned offsets: every
-- part, board and standoff scales together around the origin the ship was built at. The prop blades are
-- the one thing re-placed from STORED local offsets each frame (see the flight loop), so those stored
-- origins are scaled by the same factor -- without this the blades would spin in the old, smaller spots.
local okScale = pcall(function() blimp:ScaleTo(BLIMP_SCALE) end)
if okScale then
	for _, p in ipairs(props) do p.origin = p.origin * BLIMP_SCALE end
else
	warn("[Blimp] ScaleTo failed -- flying at 1x size")
end

-- ===== ENGINE DRONE =====
-- A looped 3D sound on the root, so it rides the ship around its whole circuit and every player hears it
-- from the blimp's actual position (built server-side like the rest of the model). It runs forever -- the
-- blimp never lands or stops -- so there is no start/stop wiring, just the one Play() below.
--
-- ADDED AFTER ScaleTo ON PURPOSE. Model:ScaleTo rescales the size-ish properties of what is already inside
-- the model; creating the sound afterwards means these distances are exactly the studs written here rather
-- than the same numbers multiplied by BLIMP_SCALE.
--
-- CLOSE-RANGE ONLY. The drone is audible within 40 studs of the ship and silent past it -- Roblox's own
-- 3D attenuation does the gating per listener, so each player hears it only when THEY are near, which a
-- server-side Play()/Stop() could never do (one Sound, one state, shared by everyone).
--
-- KNOW WHAT 40 STUDS MEANS HERE. The blimp laps at Y=343, roughly 100 studs above the Bean Farm spawn, so
-- standing in the garden you are outside this radius for the entire circuit and will hear nothing. In
-- practice the drone is now "you are on the deck, or you flew up alongside it". Raise BLIMP_FADE_DIST to
-- ~150 if you want it audible from the ground as it passes over.
local BLIMP_SOUND_ID  = "rbxassetid://84217751658202"
local BLIMP_VOLUME    = 0.825 -- 0.5 -> 0.825 (+65%)
local BLIMP_FULL_DIST = 15   -- studs of full volume -- right on top of the gondola
local BLIMP_FADE_DIST = 40   -- studs to silence -- the "only when you get close" cutoff
do
	local drone = Instance.new("Sound")
	drone.Name = "BlimpEngine"
	drone.SoundId = BLIMP_SOUND_ID
	drone.Looped = true
	drone.Volume = BLIMP_VOLUME
	drone.RollOffMode = Enum.RollOffMode.InverseTapered
	drone.RollOffMinDistance = BLIMP_FULL_DIST
	drone.RollOffMaxDistance = BLIMP_FADE_DIST
	drone.Parent = root
	drone:Play()
end

blimp:SetAttribute("BuiltByLiveScript", true) -- the stamp the duplicate-blimp sweep below recognises as OURS
blimp.Parent = Workspace

-- SWEEP AWAY ANY RIVAL BLIMP. The stale baked-in copy parents its own DonationBlimp a few seconds after the
-- islands settle, which is AFTER this line runs -- so one pass here would miss it. Sweep repeatedly through
-- the window where it can appear, then keep a slow watch in case a copy is re-inserted later.
task.spawn(function()
	local function sweep()
		local killed = 0
		for _, m in ipairs(Workspace:GetChildren()) do
			if m ~= blimp and m:IsA("Model") and m.Name == "DonationBlimp" and not m:GetAttribute("BuiltByLiveScript") then
				pcall(function() m:Destroy() end)
				killed += 1
			end
		end
		if killed > 0 then
			warn(("[Blimp] destroyed %d rival DonationBlimp(s) built by a stale duplicate script -- "
				.. "there is now ONE blimp. Delete the duplicate BlimpService in Studio for good."):format(killed))
		end
	end
	for _ = 1, 20 do sweep(); task.wait(1) end   -- first 20s: the window the stale copy builds in
	while true do task.wait(15); sweep() end     -- then a slow watch, in case one shows up later
end)

-- Workspace.StreamingEnabled is ON in this place (see IslandStreaming), so anything far from the player gets
-- streamed OUT and never reaches their client. The blimp orbits high and wide, which puts it right in the
-- stream-out zone -- without this it builds fine on the server and is simply INVISIBLE to everyone. Same fix
-- the islands use: mark it Persistent so it is always loaded, everywhere.
local okStream = pcall(function()
	blimp.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
end)
if not okStream or blimp.ModelStreamingMode ~= Enum.ModelStreamingMode.Persistent then
	warn("[Blimp] FAILED to set ModelStreamingMode=Persistent -- the blimp may be invisible to clients")
end

-- =====================  RENDER THE BOARDS  =====================

-- Gold / silver / bronze for the podium, plain slate for everyone below it.
local MEDALS = {
	Color3.fromRGB(255, 205, 70),
	Color3.fromRGB(206, 212, 224),
	Color3.fromRGB(214, 148, 88),
}

-- 1200 -> "1.2K": long Robux totals would otherwise blow past the value column on the sign.
local function shortNum(n)
	if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
	if n >= 1000    then return string.format("%.1fK", n / 1000) end
	return tostring(n)
end

-- FORWARD DECLARATION. The rare-pull writer below repaints the sign the moment a Gold lands, and the
-- pager assigns this further down -- so it has to be ONE local declared before either of them, not a
-- second `local renderBoard` in the page section shadowing this one.
local renderBoard
-- Same reason: the rare-pull writer nudges the OTHER servers' blimps, and the broadcaster is set up much
-- further down (it needs the refreshers AND renderBoard). One local, declared once, assigned later.
local blimpBroadcast

-- =====================  RAREST PULLS OF THE DAY (cross-server, resets midnight Eastern)  ===============
-- Every server writes its rare crate pulls into ONE datastore key per day, and every server reads the same
-- key back. So the board is not "what happened on this server" -- it is the rarest thing anybody in the
-- whole game pulled today, which is the only version of this worth putting on a blimp.
--
-- ===== WHY A PLAIN DATASTORE AND NOT AN OrderedDataStore =====
-- The donor and buyer boards are OrderedDataStores because they rank ONE integer per player. This board
-- has to carry a name, a prize and a rarity together, and an OrderedDataStore can only hold a number. So
-- it is one JSON list under one key, merged with UpdateAsync -- which is atomic across servers, so two
-- servers landing a Gold in the same second cannot overwrite each other's entry.
--
-- ===== THE DAY KEY IS THE RESET =====
-- The key is "RarestPulls_<YYYY-MM-DD in Eastern>". At midnight Eastern the key changes, the read comes
-- back empty, and the board is clean -- no cron, no wipe, no "clear the store" job that could fail. The
-- previous day's key just stops being read (and expires with the DataStore's own retention).
local pullStore = DataStoreService:GetDataStore("RarestPulls_v1")

-- Rank order, LOW to HIGH. This mirrors SkinCrates.RARITY_ORDER (src/shared/SkinCrates.luau) -- it is
-- duplicated rather than required because this is a display board and must not be able to break a crate
-- open if the shared module moves. If a tier is ever added there, add it here; an unknown rarity is
-- ignored rather than guessed at.
local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Gold = 6 }
local RARITY_ABBR = { [3] = "R", [4] = "E", [5] = "L", [6] = "G" }
local RARITY_TINT = {
	[3] = Color3.fromRGB( 90, 170, 255),  -- Rare      blue
	[4] = Color3.fromRGB(180, 120, 255),  -- Epic      purple
	[5] = Color3.fromRGB(255, 170,  60),  -- Legendary orange
	[6] = Color3.fromRGB(255, 215,  80),  -- Gold      gold
}
local RARE_MIN_RANK = 3   -- Rare and up. Common/Uncommon are most of every crate; they are not news.
local RARE_KEEP     = 6   -- entries banked per day (3 shown; the spares cover a name that fails to resolve)

-- ===== MIDNIGHT EASTERN, INCLUDING DAYLIGHT SAVING =====
-- os.time() is UTC. "Midnight EST" in practice means midnight Eastern, and Eastern is UTC-5 in winter and
-- UTC-4 under daylight saving -- so a fixed -5 would roll the board over at 1am local for eight months of
-- the year. The US rule is deterministic and needs no external data: DST runs from 2am local on the SECOND
-- Sunday of March to 2am local on the FIRST Sunday of November.
--
-- The test below works entirely in UTC fields. `day - (wday - 1)` is the date of this week's Sunday (it can
-- go <= 0, which correctly means "that Sunday was last month"), so:
--   March    -- we are on/after the second Sunday once that Sunday's date is >= 8
--   November -- we are on/after the first Sunday once that Sunday's date is >= 1
-- The switch happens at 07:00 UTC (March) and 06:00 UTC (November), which is 2am local on each side.
-- Set FORCE_STANDARD_TIME = true to pin the board to true EST all year instead.
local FORCE_STANDARD_TIME = false
local function easternOffsetHours(t)
	if FORCE_STANDARD_TIME then return -5 end
	local u = os.date("!*t", t)
	if u.month > 3 and u.month < 11 then return -4 end
	if u.month < 3 or u.month > 11 then return -5 end
	local weekSunday = u.day - (u.wday - 1)
	if u.month == 3 then
		if weekSunday > 8 then return -4 end                       -- past the second Sunday
		if weekSunday < 8 then return -5 end                       -- before it
		return (u.hour >= 7) and -4 or -5                          -- on it: flips at 07:00 UTC
	end
	if weekSunday > 1 then return -5 end                           -- past the first Sunday of November
	if weekSunday < 1 then return -4 end                           -- before it
	return (u.hour >= 6) and -5 or -4                              -- on it: flips at 06:00 UTC
end
local function easternDayKey()
	local t = os.time()
	return os.date("!%Y-%m-%d", t + easternOffsetHours(t) * 3600)
end

local topPulls   = {}   -- [{ name=, what=, rank= }] -- what the board draws, refreshed every BOARD_REFRESH
local pendingPulls = {} -- pulls this server has seen but not yet written (see the flusher)

local function refreshTopPulls()
	local key = easternDayKey()
	local ok, list = pcall(function() return pullStore:GetAsync(key) end)
	if not ok then
		warn("[Blimp] rare-pull read failed -- keeping the last good board")
		return -- same rule as the other boards: a blip must not blank the sign
	end
	local fresh = {}
	if type(list) == "table" then
		for _, e in ipairs(list) do
			if type(e) == "table" and e.n and e.w then
				fresh[#fresh + 1] = { name = tostring(e.n), what = tostring(e.w), rank = tonumber(e.r) or RARE_MIN_RANK }
			end
		end
	end
	topPulls = fresh
end

-- THE WRITE IS BATCHED, ON PURPOSE. Roblox throttles repeated writes to the SAME key, and on a busy day
-- every server in the game is writing to this one key. A pull is queued locally and the flusher folds
-- everything waiting into a SINGLE UpdateAsync every FLUSH_SECONDS, so a run of lucky opens costs one write
-- rather than five. A dropped entry is a missing line on a sign -- never worth retrying into a throttle.
local FLUSH_SECONDS = 10
local function flushPulls()
	if #pendingPulls == 0 then return end
	local batch = pendingPulls
	pendingPulls = {}
	local key = easternDayKey()
	local ok, err = pcall(function()
		pullStore:UpdateAsync(key, function(old)
			local list = (type(old) == "table") and old or {}
			for _, e in ipairs(batch) do list[#list + 1] = e end
			-- Rarest first; among equals the EARLIEST wins, so the board is "who got there first today"
			-- rather than a feed that a late pull of the same tier can bump you off.
			table.sort(list, function(a, b)
				local ra, rb = tonumber(a.r) or 0, tonumber(b.r) or 0
				if ra ~= rb then return ra > rb end
				return (tonumber(a.t) or 0) < (tonumber(b.t) or 0)
			end)
			while #list > RARE_KEEP do table.remove(list) end
			return list
		end)
	end)
	if not ok then
		warn("[Blimp] rare-pull write failed (" .. tostring(err) .. ") -- " .. #batch .. " entr(ies) dropped")
		return
	end
	refreshTopPulls()
	if renderBoard then renderBoard() end -- a Gold should hit the sign now, not on the next 60s tick
	if blimpBroadcast then blimpBroadcast("pull") end -- and every other server's sign, not just this one
end

-- Called by SkinCrateService after every crate open. Display-only: it can never fail an open, never yields
-- in the caller (the write is queued), and silently ignores anything below Rare or any rarity it does not
-- recognise.
--
-- `what` is the prize as a player would say it -- "Cosmic Duck" for a skin pull, the species for a pet
-- crate. Trade-ups deliberately do NOT come through here: a trade-up is CRAFTED rarity, ten skins fed into
-- a machine, and letting it onto a board about luck would make the board farmable.
_G.blimpRecordPull = function(player, rarity, what)
	if type(player) ~= "userdata" or type(what) ~= "string" or what == "" then return end
	local rank = RARITY_RANK[rarity]
	if not rank or rank < RARE_MIN_RANK then return end
	pendingPulls[#pendingPulls + 1] = { n = player.Name, w = what, r = rank, t = os.time() }
	print(string.format("[Blimp] rare pull queued: %s got %s [%s]", player.Name, what, tostring(rarity)))
end

task.spawn(function()
	while true do
		task.wait(FLUSH_SECONDS)
		pcall(flushPulls)
	end
end)

-- ===== SHORT PAGES ONLY. NOTHING THAT NEEDS READING TWICE. =====
-- The board previously ran four-line gameplay TIPS in sentence form. From 150 studs below, moving, at an
-- angle, a sentence is a grey smear -- by the time you have parsed one the blimp has turned. Every page
-- here is now a HEADLINE plus at most three short rows, sized big (48px on a 1120px canvas).
--
-- Page 1  (artwork)        the uploaded studio picture, full bleed -- no header, no rows.
-- Page 2  TOP DONATORS     the podium, three names, cross-server.
-- Page 3  RAREST TODAY     the rarest crate pulls anybody in the game has had since midnight Eastern.
-- Page 4  WHAT'S ON        the live event, its countdown, or when the next one is due.
--
-- ANNOUNCEMENTS IS GONE AS A PAGE. It was a slot for live news that nothing ever wrote to -- _G.blimpAnnounce
-- existed and no caller in the codebase has ever called it -- so in practice it was three hardcoded lines a
-- player had already read on their first lap. The hook survives as an OVERRIDE on WHAT'S ON (below), which
-- is where a "double coins for 10 minutes" line belongs anyway.
--
-- MOST PURCHASES is retired as a page too: two near-identical leaderboards on one screen reads as noise from
-- the ground. The buyer store is still banked (it costs nothing and the data keeps accruing), so the page
-- can come back by adding one branch here.
local PAGE_PICTURE, PAGE_DONORS, PAGE_PULLS, PAGE_EVENT = 1, 2, 3, 4
local PAGE_COUNT = 4

-- Other scripts can put a short message on the ship: _G.blimpAnnounce("Double coins!", "next 10 min").
-- Kept deliberately tiny -- two short strings, no formatting, no queue. Cleared by calling with nil. While
-- one is set it TAKES OVER the WHAT'S ON page, because an announcement worth making outranks a countdown.
local announceLines = nil
_G.blimpAnnounce = function(line1, line2)
	if line1 == nil then announceLines = nil; return end
	announceLines = { { tostring(line1), tostring(line2 or "") } }
end

local page = PAGE_PICTURE

-- PAGE 1 IS THE PICTURE. The rows are still cleared rather than merely covered: they sit behind the
-- artwork, and leaving last page's leaderboard parked under it is how a stale name shows through the one
-- time the image fails to load.
local function renderStudio()
	clearRows(boardRows)
end

local function renderDonors()
	clearRows(boardRows)
	if #topDonors == 0 then
		emptyNote(boardRows, "Be the first on the board!")
		return
	end
	for i = 1, math.min(3, #topDonors) do -- THREE only: a podium reads from the ground, a top-8 list does not
		local d = topDonors[i]
		local medal = MEDALS[i] or Color3.fromRGB(96, 104, 122)
		-- The face goes on the donor board and nowhere else on the blimp: these three are PEOPLE the server is
		-- thanking by name, and a face is what makes that read as a person rather than a row of text. The
		-- rarest-pet and event pages are about things, and a portrait there would just be noise.
		addRow(boardRows, i, tostring(i), medal, d.name, shortNum(d.robux) .. " R$", d.userId, medal)
	end
end

-- RAREST TODAY. Badge = the rarity as one big coloured letter (G/L/E/R) -- the row is 52px of circle and a
-- single character is all that resolves from the ground anyway, and the COLOUR does most of the telling.
--
-- The prize goes on the LEFT and the player's name after it, both in the one truncating label: if something
-- has to be cut off at the end of a long line it should be the name, not the thing everybody is looking at.
-- No right-hand value column -- "Cosmic Duck" does not fit in 216px at this text size, and squeezing it
-- there would shrink the whole board's value font for every other page.
local function renderPulls()
	clearRows(boardRows)
	if #topPulls == 0 then
		emptyNote(boardRows, "No rare pulls yet today -- be the first!")
		return
	end
	for i = 1, math.min(3, #topPulls) do
		local p = topPulls[i]
		addRow(boardRows, i, RARITY_ABBR[p.rank] or "R", RARITY_TINT[p.rank] or Color3.fromRGB(90, 170, 255),
			p.what .. "  \xC2\xB7  " .. p.name, nil)
	end
end

-- WHAT'S ON. Three sources, in order of how much they matter to somebody standing on the island:
--   1. a BIG event actually running   -- read live from _G.BigEvents[key].isRunning(), the same registry
--      the scheduler and MusicDucking read, so this can never disagree with what is happening
--   2. a MEDIUM event running         -- the workspace attributes PlayerStats publishes, with a countdown
--   3. neither                        -- roughly when the next big one is due (NextBigEventAt)
-- An announcement, if one is set, outranks all three.
local BIG_EVENT_NAMES = { meteor = "\xE2\x98\x84 METEOR SHOWER", rocket = "\xF0\x9F\x9A\x80 ROCKET LAUNCH" }
local function runningBigEvent()
	local reg = _G.BigEvents
	if type(reg) ~= "table" then return nil end
	for key, label in pairs(BIG_EVENT_NAMES) do
		local e = reg[key]
		if type(e) == "table" and type(e.isRunning) == "function" then
			local ok, running = pcall(e.isRunning)
			if ok and running then return label end
		end
	end
	return nil
end

local function mmss(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function renderEvent()
	clearRows(boardRows)

	if announceLines then
		for i, l in ipairs(announceLines) do
			if i > 3 then break end
			addRow(boardRows, i, nil, nil, l[1], (l[2] ~= "" and l[2]) or nil)
		end
		return
	end

	local big = runningBigEvent()
	if big then
		addRow(boardRows, 1, nil, nil, big, "NOW")
		addRow(boardRows, 2, nil, nil, "Look up!", nil)
		return
	end

	local ev = Workspace:GetAttribute("ActiveServerEvent")
	if type(ev) == "string" and ev ~= "" then
		local label  = Workspace:GetAttribute("ActiveServerEventName")
		local endsAt = tonumber(Workspace:GetAttribute("ActiveServerEventEndsAt"))
		local left   = endsAt and (endsAt - os.time()) or nil
		addRow(boardRows, 1, nil, nil, (type(label) == "string" and label ~= "" and label) or ev,
			(left and left > 0) and mmss(left) or "NOW")
		return
	end

	local nextAt = tonumber(Workspace:GetAttribute("NextBigEventAt"))
	if nextAt and nextAt > os.time() then
		addRow(boardRows, 1, nil, nil, "No event right now", nil)
		addRow(boardRows, 2, nil, nil, "Next one in", "~" .. math.max(1, math.ceil((nextAt - os.time()) / 60)) .. " min")
		return
	end
	emptyNote(boardRows, "No event right now -- keep climbing!")
end

renderBoard = function()
	-- Page 1 is artwork, the rest are text: the header bar and the row area come off for the picture and go
	-- back on for the boards. Driven from ONE place so the two can never disagree -- a picture with a
	-- leaderboard header still sitting on top of it is the failure mode here.
	local picturePage = (page == PAGE_PICTURE)
	if boardPic then boardPic.Visible = picturePage end
	if boardRows then boardRows.Visible = not picturePage end
	if boardTitle and boardTitle.Parent then boardTitle.Parent.Visible = not picturePage end

	if page == PAGE_PICTURE then
		boardTitle.Text = "MLR STUDIOS"
		renderStudio()
	elseif page == PAGE_DONORS then
		boardTitle.Text = "TOP DONATORS"
		renderDonors()
	elseif page == PAGE_PULLS then
		boardTitle.Text = "RAREST TODAY"
		renderPulls()
	else
		boardTitle.Text = "WHAT'S ON"
		renderEvent()
	end
end

-- THE PAGER, plus a live tick for the countdown. Every page holds PAGE_SECONDS; the difference is that
-- WHAT'S ON repaints every couple of seconds WHILE IT IS UP, because a countdown that only redraws when the
-- page arrives would sit frozen on the number it happened to be showing 18 seconds ago. Nothing else
-- repaints on the tick -- the other pages have nothing that changes second to second.
--
-- 4 pages x 18s = 72s against a 75s lap, so a player who watches the blimp go round once sees all four.
task.spawn(function()
	local held = 0
	while true do
		task.wait(2)
		held = held + 2
		if page == PAGE_EVENT then renderBoard() end
		if held >= PAGE_SECONDS then
			held = 0
			page = page % PAGE_COUNT + 1
			renderBoard()
		end
	end
end)

renderBoard()

-- =====================  ONE BOARD, EVERY SERVER  =====================
-- ===== WHY THIS IS ALREADY GLOBAL =====
-- Every page on this sign is fed by a store that lives OUTSIDE this server: TopDonors_v1 and TopBuyers_v1 are
-- OrderedDataStores and the rare-pull board is one shared daily key. Nothing on the blimp is a tally of who
-- happens to be in THIS server -- a donation on any server in the game counts on every blimp in the game, and
-- always has. The 60s loop is what pulls each server's copy back into line.
--
-- ===== WHAT THIS ADDS =====
-- Sixty seconds is a long time to stand in front of a sign that has not noticed you yet. When a server banks
-- something board-worthy it now says so on a MessagingService topic and every other server re-reads and
-- repaints AT ONCE -- so a kid who donates while a friend watches the blimp on another server sees their name
-- go up on both, not a minute apart.
--
-- The message is a NUDGE, never data: it carries which board moved and nothing else, and the receiver goes to
-- the DataStore for the actual numbers. That is deliberate -- the store stays the single authority, so a
-- dropped, duplicated or out-of-order message can only ever cost a few seconds of freshness. MessagingService
-- is rate-limited per topic, so publishing is confined to the moments that actually change a board and capped
-- at one a second; and every call is wrapped, because a messaging outage must leave a working blimp on the old
-- refresh cadence rather than a broken one.
local MessagingService = game:GetService("MessagingService")
local BOARD_TOPIC = "BlimpBoards_v1"

do
	local lastSent = 0
	blimpBroadcast = function(what)
		if os.clock() - lastSent < 1 then return end -- a crate spree only needs to be announced once
		lastSent = os.clock()
		task.spawn(function()
			pcall(function() MessagingService:PublishAsync(BOARD_TOPIC, what) end)
		end)
	end

	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(BOARD_TOPIC, function(msg)
			local what = msg and msg.Data
			task.spawn(function()
				if what == "donor" then
					refreshTopDonors()
					refreshTopBuyers() -- a donation is a purchase too; both boards moved
				elseif what == "buyer" then
					refreshTopBuyers()
				elseif what == "pull" then
					refreshTopPulls()
				else
					refreshTopDonors(); refreshTopBuyers(); refreshTopPulls()
				end
				renderBoard() -- through the pager, so it only repaints the page actually on screen
			end)
		end)
	end)
	if ok then
		print("[Blimp] boards are CROSS-SERVER: shared DataStores, re-read every " .. BOARD_REFRESH ..
			"s and immediately whenever any server in the game reports a change")
	else
		warn("[Blimp] cross-server nudges unavailable (" .. tostring(err) .. ") -- the boards are still global "
			.. "(shared DataStores); they just refresh on the " .. BOARD_REFRESH .. "s tick instead of at once")
	end
end

-- =====================  PURCHASE HOOKS  =====================

-- Called by PlayerStats' SINGLE ProcessReceipt for EVERY Developer Product. Always returns nothing and never
-- errors the caller -- this is a display-only observer and must never be able to fail a real purchase.
_G.blimpRecordPurchase = function(player, productId)
	-- COUNTED WHETHER OR NOT THE PRODUCT IS MAPPED. The old feed bailed out here on an unknown productId
	-- because it needed a LABEL to print; this board only needs to know that a purchase happened, so token
	-- packs and anything added later count too instead of being silently dropped.
	task.spawn(function()
		bankPurchase(player) -- still banked (the data keeps accruing); no longer has its own board page
		refreshTopBuyers()
		blimpBroadcast("buyer") -- every other server's blimp re-reads now instead of on its next tick
	end)
	local info = PRODUCTS[productId]
	if info and info.robux then
		task.spawn(function()
			bankDonation(player, info.robux)
			refreshTopDonors() -- a donation should climb the board immediately, not on the next 60s tick
			renderBoard()      -- through the pager, so it can only repaint the page actually on screen
			blimpBroadcast("donor") -- ...and on every OTHER server's blimp, at the same moment
		end)
	end
end

-- Gamepasses need no hook in PlayerStats: this is a signal, so our listener runs alongside theirs.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if not wasPurchased then return end
	-- Same as above: an unmapped pass still counts as a purchase.
	task.spawn(function()
		bankPurchase(player)
		refreshTopBuyers()
		blimpBroadcast("buyer")
	end)
end)

-- =====================  FLY  =====================

task.spawn(function()
	while true do
		refreshTopDonors()
		refreshTopBuyers()
		refreshTopPulls() -- also what rolls the board over at midnight Eastern: the day key changes and the
		                  -- read comes back empty, so no wipe job is needed
		renderBoard() -- repaint whichever page is currently up, with the freshly-read data
		task.wait(BOARD_REFRESH)
	end
end)

local PROP_RPS   = 3.2  -- prop revolutions/sec
local BANK_DEG   = 7    -- roll INTO the turn; a real airship leans, it doesn't slide flat around a circle

local t = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt
	local angle = (t / LAP_SECONDS) * math.pi * 2
	local bob   = math.sin((t / BOB_SECONDS) * math.pi * 2) * BOB_HEIGHT
	-- A slow pitch oscillation out of phase with the bob: the nose rides up as it rises. Tiny, but it's the
	-- difference between "flying" and "sliding along an invisible rail".
	local pitch = math.cos((t / BOB_SECONDS) * math.pi * 2) * math.rad(1.6)
	local pos   = Vector3.new(
		centre.X + math.cos(angle) * LAP_RADIUS,
		flyY + bob,
		centre.Z + math.sin(angle) * LAP_RADIUS
	)
	-- Nose along the tangent of the circle so it banks into the turn instead of crabbing sideways.
	local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
	local cf = CFrame.lookAt(pos, pos + tangent) * CFrame.Angles(pitch, 0, math.rad(BANK_DEG))
	blimp:PivotTo(cf)

	-- Spin the props. PivotTo has already carried them around with the hull, so we re-place each blade from
	-- the blimp's CFrame + its stored local offset + its own spin. Counter-rotating (dir) per side.
	local spin = t * PROP_RPS * math.pi * 2
	for _, p in ipairs(props) do
		p.part.CFrame = cf * CFrame.new(p.origin) * CFrame.Angles(0, 0, spin * p.dir + p.phase)
	end

	-- Beacon: a slow double-blink, the way aircraft anti-collision lights actually pulse.
	local blink = (math.sin(t * 3.4) > 0.72) or (math.sin(t * 3.4 - 0.5) > 0.86)
	beacon.Transparency  = blink and 0 or 0.75
	beaconLight.Enabled  = blink
end)

print(string.format("[Blimp] airborne over '%s' -- lap r=%d at Y=%d, %ds/circuit, streaming=%s",
	island.Name, LAP_RADIUS, flyY, LAP_SECONDS, tostring(blimp.ModelStreamingMode)))
