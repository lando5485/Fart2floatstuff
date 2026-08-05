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
local topDonors  = {}   -- [{name=, robux=}] refreshed every BOARD_REFRESH
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
		fresh[#fresh + 1] = { name = userName(tonumber(entry.key)), robux = entry.value }
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
	p.CanCollide   = false  -- players fly THROUGH this airspace; a solid blimp would swat them out of the sky
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

	return rows, accent, htxt -- htxt so a rotating board can retitle itself per page
end

-- One row on a board: an optional coloured rank badge, a name, and a right-aligned value.
local function addRow(rows, order, badgeText, badgeColor, leftText, rightText)
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
local flyY   = centre.Y + islandSize.Y / 2 + LAP_ALTITUDE

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
local boardRows, _, boardTitle = board(blimp, "MainBoard", CFrame.new(13, -2, -4), "MLR STUDIOS",
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

blimp.Parent = Workspace

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

-- ===== SHORT PAGES ONLY. NOTHING THAT NEEDS READING TWICE. =====
-- The board previously ran four-line gameplay TIPS in sentence form. From 150 studus below, moving, at an
-- angle, a sentence is a grey smear -- by the time you have parsed one the blimp has turned. Every page
-- here is now a HEADLINE plus at most three short rows, sized big (48px on a 1120px canvas).
--
-- Page 1  MLR STUDIOS      the studio card -- who made this. The default face of the ship.
-- Page 2  TOP DONATORS     the podium, three names, cross-server.
-- Page 3  ANNOUNCEMENTS    whatever the server currently wants to say (see _G.blimpAnnounce below).
--
-- MOST PURCHASES is retired as a page: two near-identical leaderboards on one screen is the sort of thing
-- that reads as noise from the ground. The buyer store is still banked (it costs nothing and the data
-- keeps accruing), so the page can come back by adding one branch here.
local ANNOUNCE_DEFAULT = {
	{ "Fly higher, earn more", "" },
	{ "New realms in the More menu", "" },
	{ "Thanks for playing!", "" },
}
-- Other scripts can put a short message on the ship: _G.blimpAnnounce("Double coins!", "next 10 min").
-- Kept deliberately tiny -- two short strings, no formatting, no queue. Cleared by calling with nil.
local announceLines = nil
_G.blimpAnnounce = function(line1, line2)
	if line1 == nil then announceLines = nil; return end
	announceLines = { { tostring(line1), tostring(line2 or "") } }
end

local page = 1 -- 1 = MLR STUDIOS, 2 = TOP DONATORS, 3 = ANNOUNCEMENTS
local renderBoard

local function renderStudio()
	clearRows(boardRows)
	local n = #Players:GetPlayers()
	addRow(boardRows, 1, nil, nil, "FART TO FLOAT", "")
	addRow(boardRows, 2, nil, nil, "Players online", tostring(n))
	local evt = Workspace:GetAttribute("ActiveServerEvent") -- PlayerStats publishes this, "" when idle
	if type(evt) == "string" and evt ~= "" then
		addRow(boardRows, 3, nil, nil, "EVENT LIVE", evt)
	end
end

local function renderDonors()
	clearRows(boardRows)
	if #topDonors == 0 then
		emptyNote(boardRows, "Be the first on the board!")
		return
	end
	for i = 1, math.min(3, #topDonors) do -- THREE only: a podium reads from the ground, a top-8 list does not
		local d = topDonors[i]
		addRow(boardRows, i, tostring(i), MEDALS[i] or Color3.fromRGB(96, 104, 122),
			d.name, shortNum(d.robux) .. " R$")
	end
end

local function renderAnnounce()
	clearRows(boardRows)
	local lines = announceLines or ANNOUNCE_DEFAULT
	for i, l in ipairs(lines) do
		if i > 3 then break end
		addRow(boardRows, i, nil, nil, l[1], l[2])
	end
end

renderBoard = function()
	if page == 1 then
		boardTitle.Text = "MLR STUDIOS"
		renderStudio()
	elseif page == 2 then
		boardTitle.Text = "TOP DONATORS"
		renderDonors()
	else
		boardTitle.Text = "ANNOUNCEMENTS"
		renderAnnounce()
	end
end

task.spawn(function()
	while true do
		task.wait(PAGE_SECONDS)
		page = page % 3 + 1
		renderBoard()
	end
end)

renderBoard()

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
	end)
	local info = PRODUCTS[productId]
	if info and info.robux then
		task.spawn(function()
			bankDonation(player, info.robux)
			refreshTopDonors() -- a donation should climb the board immediately, not on the next 60s tick
			renderBoard()      -- through the pager, so it can only repaint the page actually on screen
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
	end)
end)

-- =====================  FLY  =====================

task.spawn(function()
	while true do
		refreshTopDonors()
		refreshTopBuyers()
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
