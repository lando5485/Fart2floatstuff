-- ============================================================================================
-- GLOBAL LEADERBOARDS (server) -- physical boards in the world, backed by OrderedDataStore.
--
-- Three boards stand on Bean Farm (island 1), so EVERY player walks past them, including brand-new
-- ones -- a leaderboard nobody sees motivates nobody:
--     1. FASTEST CLIMB   -> highest island reached, ranked by HOW LONG it took you to get there
--     2. OG FARTERS      -> the first 100 people ever to play the game. Permanent, and unwinnable once it fills.
--     3. MOST PLAYTIME   -> total hours played across every session
--
-- The three are deliberately different KINDS of achievement, so they are not the same race three times over:
-- FASTEST CLIMB rewards skill, OG FARTERS rewards being early (and can never be taken from you), MOST PLAYTIME
-- rewards loyalty. A player who is hopeless at the game can still top the last two.
--
-- Each board holds the top 100 and SCROLLS -- walk up to it and drag.
--
-- WHY THESE THREE AND NOT "HIGHEST FLIGHT": every stat here is SERVER-OWNED. Peak flight height is
-- computed on the CLIENT (_G.peakHeight in CoreClient) and sent up, so putting it on a global board
-- would publish a number a cheater can simply lie about, and the #1 slot would be a fabricated one
-- within a day. Coins/island/pets are all written by the server, so they can't be spoofed.
--
-- Data flow: PlayerStats calls _G.leaderboardSubmit(player) from savePlayerData (autosave + on leave),
-- so a player's entry is only ever written from data the server already trusted enough to persist.
-- Boards re-read the top 10 every REFRESH_SECONDS and redraw.
--
-- Everything is pcall'd: no DataStore (e.g. Studio with API access off) simply means the boards render
-- an empty "no scores yet" state and submissions no-op. It can never break the join/save path.
-- ============================================================================================

local Players    = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Workspace  = game:GetService("Workspace")

local REFRESH_SECONDS = 60   -- how often the boards re-read the rankings
local TOP_N           = 100  -- rows per board. The boards SCROLL, so this is not limited to what fits on screen.
                             -- 100 is also GetSortedAsync's hard page-size ceiling -- asking for more throws.

-- ===== TIME FORMATTING ======================================================================================
local function hms(sec)
	sec = math.max(0, math.floor(tonumber(sec) or 0))
	local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
	if h > 0 then return string.format("%dh %02dm", h, m) end
	if m > 0 then return string.format("%dm %02ds", m, sec % 60) end
	return sec .. "s"
end

-- ===== THE FASTEST-CLIMB SCORE ==============================================================================
-- An OrderedDataStore sorts on ONE integer, but this board ranks on TWO things: island first, then how quickly you
-- got there. So both are packed into a single number:
--
--     score = island * 10,000,000  +  (9,999,999 - secondsTaken)
--             \__ dominant ______/     \__ tie-break, INVERTED so faster = bigger __/
--
-- Island always wins: someone on island 12 outranks someone on island 11 no matter how fast the 11 was. Within the
-- SAME island, a smaller time gives a bigger score, so the fastest climber floats to the top. The time term is
-- inverted rather than negated because OrderedDataStore only sorts descending-or-ascending on the raw value, and
-- the ranking wants "highest island, then lowest time" -- two directions at once, which only works if you flip one.
--
-- 9,999,999 seconds is ~115 days of playtime; past that the tie-break saturates and slower climbs simply tie. The
-- top score (island 14, instant) is 1.4e8, comfortably inside the integer range OrderedDataStore accepts.
local ISLAND_MULT = 10000000
local TIME_MAX    = 9999999

-- Each board: its OrderedDataStore, its title, how to read a player's value, and how to render it.
-- `ascending = true` means LOWEST value ranks first (the OG board -- OG #1 is the top of the list).
local BOARDS = {
	{
		key   = "climb",
		store = "LB_FastestClimb_v1",
		title = "\xE2\x9B\xB0 FASTEST CLIMB",
		color = Color3.fromRGB(120, 220, 255),
		-- Island 1 is where everyone STARTS -- it is not a climb, so it never scores. Only island 2+ ranks,
		-- which also keeps the board from filling up with brand-new players who have not done anything yet.
		read  = function(player)
			local island = math.floor(player:GetAttribute("HighestIsland") or 1)
			if island < 2 then return 0 end
			local secs = math.floor(tonumber(_G.playerIslandTimeSec and _G.playerIslandTimeSec[player]) or 0)
			return island * ISLAND_MULT + math.max(0, TIME_MAX - math.min(secs, TIME_MAX))
		end,
		fmt = function(score)
			local island = math.floor(score / ISLAND_MULT)
			local secs   = TIME_MAX - (score % ISLAND_MULT)
			return ("Island %d  \xC2\xB7  %s"):format(island, hms(secs))
		end,
	},
	{
		key   = "og",
		store = "LB_OGFarters_v1",
		title = "\xF0\x9F\x92\xA8 OG FARTERS",
		color = Color3.fromRGB(255, 170, 90),
		ascending = true, -- OG #1 is the FIRST person ever to play, so LOW numbers rank highest
		read  = function(player)
			local n = _G.playerOGNumber and _G.playerOGNumber[player]
			return (type(n) == "number" and n > 0) and n or 0
		end,
		fmt = function(n) return "OG #" .. n end,
	},
	{
		key   = "playtime",
		store = "LB_Playtime_v1",
		title = "\xE2\x8F\xB1 MOST PLAYTIME",
		color = Color3.fromRGB(180, 160, 255),
		-- Total seconds played across ALL sessions. PlayerStats owns this number (saved playtime + live session)
		-- and exposes it, so the board and the gut-skin unlocks can never disagree about how long someone has played.
		read  = function(player)
			if type(_G.playerTotalPlaytime) ~= "function" then return 0 end
			local ok, n = pcall(_G.playerTotalPlaytime, player)
			return (ok and type(n) == "number") and math.floor(n) or 0
		end,
		fmt = hms,
	},
	{
		key   = "rebirths",
		store = "LB_MostRebirths_v1",
		title = "\xF0\x9F\x94\x84 MOST REBIRTHS",
		color = Color3.fromRGB(190, 130, 255),
		-- Rebirth count = the "Rebirths" leaderstat (RebirthSystem owns it). 0 is never submitted, so only
		-- players who have actually rebirthed appear on this board.
		read  = function(player)
			local ls = player:FindFirstChild("leaderstats")
			local rb = ls and ls:FindFirstChild("Rebirths")
			return (rb and math.floor(rb.Value)) or 0
		end,
		fmt = function(n) return n .. (n == 1 and " rebirth" or " rebirths") end,
	},
}

-- open the stores (guarded: Studio with API access off leaves these nil and everything below no-ops)
for _, b in ipairs(BOARDS) do
	pcall(function() b.ods = DataStoreService:GetOrderedDataStore(b.store) end)
end

-- ===== OG FARTERS: the first 100 people ever to play ========================================================
-- A player's OG number is permanent and is handed out ONCE, on their first ever join. Two plain DataStores back
-- it, deliberately kept HERE rather than in the player's save file: the number is a GLOBAL fact about the game
-- ("you were the 7th person ever"), not a per-player stat, and it must be impossible to re-roll by wiping a save.
--
-- IncrementAsync is ATOMIC. That matters: without it, two players joining different servers in the same second
-- could both read "6" and both write "7". With it, the DataStore itself serialises them and they get 7 and 8.
--
-- DO NOT RENAME THESE TWO DATASTORE KEYS AFTER LAUNCH. The board's title is just text and can be changed freely,
-- but these strings ARE the saved data -- rename them and every OG number ever issued is orphaned, and the first
-- 100 people to rejoin would silently be handed brand-new ones.
local OG_LIMIT = 100
local ogStore, ogCounter
pcall(function()
	ogStore   = DataStoreService:GetDataStore("OGFarters_v1")    -- [userId] = OG number
	ogCounter = DataStoreService:GetDataStore("OGCounter_v1")    -- "count"  = how many have been handed out
end)
_G.playerOGNumber = _G.playerOGNumber or {}

local function claimOGNumber(player)
	if not (ogStore and ogCounter) then return end
	local key = tostring(player.UserId)

	local okRead, existing = pcall(function() return ogStore:GetAsync(key) end)
	if okRead and type(existing) == "number" and existing > 0 then
		_G.playerOGNumber[player] = existing
		print(("[Leaderboard] %s is OG #%d"):format(player.Name, existing))
		return existing
	end
	if not okRead then return end -- read failed: do NOT hand out a number, or a blip could issue a duplicate

	-- Not an OG yet. Take the next number -- atomically, so concurrent servers cannot collide.
	local okInc, n = pcall(function() return ogCounter:IncrementAsync("count", 1) end)
	if not (okInc and type(n) == "number") then return end
	if n > OG_LIMIT then return end -- the first 100 are gone; everyone after simply has no OG number

	pcall(function() ogStore:SetAsync(key, n) end)
	_G.playerOGNumber[player] = n
	print(("[Leaderboard] %s CLAIMED OG #%d of %d"):format(player.Name, n, OG_LIMIT))
	return n
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		claimOGNumber(player)
		if _G.leaderboardSubmit then pcall(_G.leaderboardSubmit, player) end -- get them onto the board immediately
	end)
end)
Players.PlayerRemoving:Connect(function(player) _G.playerOGNumber[player] = nil end)

-- ===== SUBMIT ===============================================================================
-- Called by PlayerStats from savePlayerData (autosave + leave). SetAsync (not Increment) because
-- every value here is an absolute lifetime total, so re-submitting the same number is harmless and
-- a re-submit after a rollback corrects the board rather than double-counting.
_G.leaderboardSubmit = function(player)
	if not (player and player.UserId) then return end
	local key = tostring(player.UserId)
	for _, b in ipairs(BOARDS) do
		if b.ods then
			local ok, err = pcall(function()
				local v = b.read(player)
				if type(v) == "number" and v > 0 then b.ods:SetAsync(key, math.floor(v)) end
			end)
			if not ok then warn("[Leaderboard] submit failed (" .. b.key .. "): " .. tostring(err)) end
		end
	end
end

-- ===== PLACEMENT + GEOMETRY =================================================================
-- Vertical maths, spelled out so it is checkable rather than guessed:
--   panel is PANEL_H tall, centred on the anchor  -> its bottom sits PANEL_H/2 BELOW the anchor
--   post is POST_H tall, hanging under the panel  -> its base sits PANEL_H/2 + POST_H below the anchor
-- So to stand a board ON the ground, the anchor must be raised by exactly (PANEL_H/2 + POST_H).
-- The board post/step was removed entirely -- the panel now rises STRAIGHT from the plaza floor. ANCHOR_LIFT
-- is set so the panel's bottom edge sinks 0.4 studs into the floor: no gap under it (which would look like it
-- floats), no step in front of it.
local PANEL_W, PANEL_H, POST_H = 13, 14, 1.5
local ANCHOR_LIFT = PANEL_H / 2 - 0.4

-- ===== THE LAYOUT, AND WHICH WAY EVERYTHING FACES =========================================================
-- The marker's FRONT (-Z, the blue arrow in Studio) points AT THE VIEWER -- i.e. back down the path you walk in
-- from. Everything is laid out around that one convention:
--
--        -Z  (toward the viewer / the way in)
--         ^
--         |   [ ARCH: "HALL OF FAME" gateway, at the FRONT ]   <- you walk THROUGH this
--         |
--         O   marker / plaza centre
--         |
--         |   [ board ] [ board ] [ board ]   <- in an arc at the BACK, all angled in to face you
--        +Z  (behind)
--
-- This was inverted before: the arch was built at +Z (behind, so its sign faced away) and the boards were pushed
-- 34 studs out along -Z (in FRONT of the marker, and outside the plaza entirely). Both are fixed below.
--
-- The boards must also FIT: each panel is PANEL_W wide, so the gap between neighbours on the arc is
-- chord = 2 * ARC_RADIUS * sin(ARC_SPREAD/2). At 20 studs and 50 degrees that is ~16.9 studs, comfortably clear
-- of the 13-stud panel width. And a board's far corner sits sqrt(20^2 + 6.5^2) ~= 21 studs out, well inside the
-- 28-stud plaza. Change any one of these three and re-check that arithmetic.
local ARC_SPREAD  = 50   -- degrees between neighbouring boards
local ARC_RADIUS  = 20   -- studs from the plaza centre BACK to each board
local PLAZA_R     = 28   -- radius of the stone plaza everything stands on
local ARCH_Z      = -20  -- the gateway sits this far FORWARD of centre (negative = toward the viewer)

-- ===== AIMING THE WHOLE MONUMENT ==========================================================================
-- These two turn/shift the ENTIRE thing -- plaza, arch, sign and all three boards -- because every piece above is
-- built off the anchor CFrame, and these are applied to that anchor BEFORE anything is built. So the monument
-- always moves as one solid object and nothing can drift out of alignment with anything else.
--
-- The marker part in Studio is planted at an arbitrary rotation, so rather than ask you to re-aim the part, the
-- correction lives here as two numbers:
--   MONUMENT_SPIN -- degrees about Y. 180 turns the whole thing to face the other way, which is what puts the
--                    "HALL OF FAME" sign where you can READ it instead of staring at the back of the lintel.
--   FORWARD_NUDGE -- studs along the direction the sign now faces (positive = toward you, negative = away).
local MONUMENT_SPIN = 180  -- degrees about Y: turn the monument to face you
local FORWARD_NUDGE = 8    -- studs toward the viewer, along the way the sign faces

-- WHERE THE PLAZA GOES.
-- A Part placed in Studio wins outright -- its position AND its facing are used exactly as-is, so the whole
-- monument can be moved/turned without touching code. Several names are accepted because it is not worth a
-- silent no-op if the part ends up called something slightly different; the log says which one was found.
--   * Position: the plaza centre + the point the boards' arc curves around.
--   * Facing:   the part's FRONT (-Z, the blue arrow in Studio's Move tool) should point AT the viewer --
--               i.e. back down the path a player walks in from. The boards turn to face that way.
-- The part is hidden at runtime, so it can be any size/colour and left visible while you position it.
-- MATCHING IS LOOSE ON PURPOSE. The first version did an exact, case-sensitive FindFirstChild against a fixed
-- list of names, silently found nothing, and dumped the plaza in the fallback spot. Now ANY Part or Model whose
-- name CONTAINS "leaderboard" (in any case, anywhere in the name) is accepted -- "LeaderboardPlacement",
-- "leaderboard spot", "MyLeaderboardHere" all work. Every candidate is logged, so if it still misses you can see
-- exactly what the search did see.
local MARKER_MATCH = "leaderboard"

local function findAnchor()
	local candidates = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and string.find(d.Name:lower(), MARKER_MATCH, 1, true) then
			-- never match the plaza WE build (defensive: the folder does not exist yet at this point, but a
			-- re-run or a leftover from a previous session must not be mistaken for the marker)
			if not (d.Name == "Leaderboards" or string.find(d.Name, "Leaderboard_", 1, true)
				or d.Name == "LeaderboardPlaza") then
				candidates[#candidates + 1] = d
			end
		end
	end

	if #candidates > 0 then
		print(("[Leaderboard] found %d marker candidate(s):"):format(#candidates))
		for _, d in ipairs(candidates) do
			print(("    '%s' (%s) at %s"):format(d.Name, d.ClassName,
				tostring(d:IsA("BasePart") and d.Position or d:GetPivot().Position)))
		end
		-- prefer a BasePart (it carries a facing); fall back to a Model's pivot
		local pick
		for _, d in ipairs(candidates) do if d:IsA("BasePart") then pick = d; break end end
		pick = pick or candidates[1]

		local cf = pick:IsA("BasePart") and pick.CFrame or pick:GetPivot()
		if pick:IsA("BasePart") then
			-- hide it: it is a marker, not scenery. Left in place so its CFrame stays authoritative.
			pick.Transparency = 1; pick.CanCollide = false; pick.CanQuery = false; pick.CanTouch = false
		end
		print(("[Leaderboard] USING marker '%s' at %s (its front/-Z faces %s -- the boards face that way)")
			:format(pick.Name, tostring(cf.Position), tostring(cf.LookVector)))
		return cf
	end

	-- Fallback only: nothing matched. Build across the island from the spawn.
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.find(m.Name, "Island_1_", 1, true) then
			local sl = m:FindFirstChildWhichIsA("SpawnLocation", true)
			local base = (sl and sl.CFrame) or m:GetPivot()
			local ground = base.Position
			local pos = ground + Vector3.new(58, 0, 44)
			local flatTarget = Vector3.new(ground.X, pos.Y, ground.Z) -- face back at spawn, kept upright
			warn("[Leaderboard] NO part or model with 'leaderboard' in its name found ANYWHERE in Workspace -- "
				.. "using a fallback spot. Add a Part whose name contains 'Leaderboard' and it will be used.")
			return CFrame.lookAt(pos, flatTarget)
		end
	end
	return nil
end

local function newPart(parent, name, size, color, cf, material)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.Color = color; p.CFrame = cf
	p.Anchored = true; p.CanCollide = true; p.CanQuery = false
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- ===== THE LIGHTING BUDGET ==================================================================================
-- There are FOURTEEN lights on one 56-stud plaza: 4 lanterns, 4 braziers, 3 boards, 2 trophies, 1 gateway wash.
-- Roblox ADDS overlapping PointLights together. At the brightness the first pass used (lanterns 1.8/range 20,
-- braziers 2.4/range 26) they all piled on top of each other and at night the middle of the plaza blew out to flat
-- white -- every shadow gone, the stone reading as grey cardboard, and the boards' own coloured glow lost in it.
--
-- So the budget is deliberately LOW and the ranges are SHORT. Each light is meant to pick out the thing it is
-- attached to and fall off before it reaches its neighbour, which is what actually makes a night scene look good:
-- pools of light with darkness between them, not a uniform floodlit box. The two you walk between on the way in
-- are the DIMMEST of the lot -- they are there to lead your eye up the road, not to light the road.
local LIGHT = {
	lantern = { b = 0.55, r = 13, c = Color3.fromRGB(255, 214, 150) }, -- the approach: a soft glow, nothing more
	brazier = { b = 1.10, r = 17, c = Color3.fromRGB(255, 170, 90)  }, -- fire is allowed to be the brightest thing
	board   = { b = 0.85, r = 15                                     }, -- coloured, per board
	gate    = { b = 0.70, r = 20, c = Color3.fromRGB(190, 205, 255) }, -- one cool wash under the arch, for contrast
}

-- ===== FLICKER ==============================================================================================
-- Anything with a flame gets a gentle, never-repeating wobble. A perfectly steady "fire" is the single biggest
-- tell that a torch is fake, and a lantern that breathes very slightly feels lit rather than switched on.
--
-- ONE loop drives every light rather than one loop per light -- 8 coroutines all waking each other up 12 times a
-- second is real cost for a decorative effect. The phase offset per index means no two ever pulse in lockstep, and
-- the two sine waves have incommensurate periods so the pattern never visibly loops.
local flickers = {}
local function flicker(light, base, depth)
	flickers[#flickers + 1] = { light = light, base = base, depth = depth or 0.18 }
end
task.spawn(function()
	while true do
		local t = os.clock()
		for i, f in ipairs(flickers) do
			local phase = i * 1.7
			local wobble = math.sin(t * 2.7 + phase) * 0.6 + math.sin(t * 6.3 + phase * 2.1) * 0.4
			f.light.Brightness = f.base * (1 - f.depth + f.depth * (0.5 + 0.5 * wobble))
		end
		task.wait(0.08)
	end
end)

-- ===== THE MONUMENT ======================================================================================
-- The plaza is built in POLAR coordinates around the marker, because every piece of it is a ring or an arc.
-- One helper does all of it: `ring(a, r, y)` gives the CFrame `a` degrees around the plaza at radius `r`, height
-- `y`, ALREADY TURNED so its local +X runs tangentially (along the ring) and its local -Z faces back through the
-- centre. That is why the columns, the architrave beams that span between them, and the boards themselves can all
-- be placed with the same one-liner and still line up: they share one coordinate system.
--
-- Angle convention (matches the board arc exactly, so nothing can drift):
--     0 deg  = straight BACK (+Z), where the middle board stands
--   180 deg  = the FRONT (-Z), the gateway you walk in through
--
-- COLLISION BUDGET -- checked, not eyeballed. Change a number here and re-check these four:
--   * board far corner        sqrt(20^2 + 6.5^2)  = 21.0 studs out
--   * colonnade inner face    26 - 1.3            = 24.7 studs out   -> 3.7 studs clear of the boards
--   * arch pillar             sqrt(16^2 + 20^2)   = 25.6 studs out   -> inside the 28-stud plaza
--   * beam chord (30 deg gap) 2 * 26 * sin(15)    = 13.5 studs long
local COL_R      = PLAZA_R - 2  -- colonnade radius: a backdrop BEHIND the boards, hard against the rim
local COL_H      = 17           -- shorter than the 19-stud boards and the arch, so it frames rather than competes
local COL_STEP   = 30           -- degrees between columns
-- half-width (deg) of the gap in the colonnade at the gateway. Must clear THREE column slots (150/180/210), not
-- just the one dead ahead: at 30 deg the 150 and 210 columns land 3.2 studs from the arch pillars and their bases
-- overlap. 45 drops all three and leaves the doorway properly open.
local GATE_GAP   = 45

-- ===== HOW PARTS JOIN =====================================================================================
-- EVERY stacked piece OVERLAPS the one below it by EMBED studs. It does not merely touch it.
--
-- Two parts whose faces land on exactly the same plane do not read as joined -- they read as a hairline seam, and
-- if the faces are coplanar they Z-FIGHT (flicker as the camera moves). "Base top = 1.0, shaft bottom = 1.0" is
-- the bug, not the fix. So every join below is written as an explicit overlap, and the startup audit prints the
-- measured overlap of each one: any number <= 0 means a floating or seam-only part and is a bug.
local EMBED = 0.3  -- studs each piece sinks into the one under it

-- A Cylinder's length runs along its LOCAL X, NOT its Y. So a vertical cylinder is size (LENGTH, dia, dia) and
-- then rotated 90 deg about Z to stand it up. Writing (dia, LENGTH, dia) -- the intuitive order -- silently builds
-- a stubby cylinder lying on its side, which is exactly what the first pass of the columns and brazier bowls did.
local function pillarCyl(parent, name, cf, height, dia, color, mat)
	local p = newPart(parent, name, Vector3.new(height, dia, dia), color,
		cf * CFrame.Angles(0, 0, math.rad(90)), mat)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- a point on the plaza ring: `deg` around, `r` out, `y` up -- turned to face the centre
local function ring(cf, deg, r, y)
	return cf * CFrame.Angles(0, math.rad(deg), 0) * CFrame.new(0, y or 0, r)
end

-- the same point as plain plaza-local X,Z (for props that are placed by hand rather than on the ring)
local function polar(deg, r)
	local a = math.rad(deg)
	return math.sin(a) * r, math.cos(a) * r
end

-- ===== THE WALKWAY ========================================================================================
-- The straight line a player actually WALKS: in through the arch at (0, ARCH_Z) and on to the plaza centre.
-- NOTHING solid may stand inside it. The first pass put two lit braziers at x = +/-8, which is INSIDE the
-- 18-stud-wide paving -- you would have walked face-first into a torch on the way in. Every prop placed near the
-- entrance is now checked against this and the startup audit warns if any of them intrudes.
local WALK_HALF = 10  -- half-width of the clear corridor along x = 0

-- how far a prop at (x, z) intrudes into the walkway: positive = BLOCKING it. `half` is the prop's own half-width.
-- Props behind the plaza centre (z > 0) are not on the entry path at all, so they are exempt.
local function walkwayIntrusion(x, z, half)
	if z > 0 then return -math.huge end
	return WALK_HALF - (math.abs(x) - half)
end

-- A beam spanning two points given in plaza-local XZ. Used for the architrave AND for the two struts that tie the
-- colonnade into the arch, so the stone ring is genuinely CLOSED rather than two pieces that stop near each other.
-- It is grown by 2*EMBED and centred on the span, so each end buries itself in whatever it lands on.
-- A part rotated by CFrame.Angles(0, a, 0) has its local +X pointing at (cos a, 0, -sin a) -- hence the atan2.
local function beam(plaza, cf, name, x1, z1, x2, z2, y, h, d, color)
	local dx, dz = x2 - x1, z2 - z1
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.01 then return end
	newPart(plaza, name, Vector3.new(len + EMBED * 2, h, d), color,
		cf * CFrame.new((x1 + x2) / 2, y, (z1 + z2) / 2) * CFrame.Angles(0, math.atan2(-dz, dx), 0),
		Enum.Material.Plastic)
	return len
end

-- A torch: stone bowl, glowing coals, real fire, real light. Placed by plain X/Z (not on the ring) precisely so
-- the entrance pair can be pushed OUT of the walkway rather than being stuck wherever an arc angle happens to land.
local function brazier(plaza, cf, x, z)
	-- Built to the same standard as the lanterns: a grounded FOOTING, a post, a COLLAR that bridges the post
	-- up to the wider bowl, then the bowl + coals. Every piece overlaps the next (see the y ranges), so it
	-- reads as one solid torch instead of a bowl balanced on a stick.
	-- Garden STONE2. The Hall of Fame stonework was Slate in greys (104,94,80 / 150,140,122 / 168,156,136);
	-- it now uses the Community Garden's material (Plastic) and its three tan tones, so the monument reads
	-- as the same stone as the garden rather than as grey concrete dropped next to it.
	local STONE = Color3.fromRGB(168, 142, 104)
	newPart(plaza, "BrazierBase",   Vector3.new(1.7, 0.6, 1.7), STONE, cf * CFrame.new(x, 0.3, z), Enum.Material.Plastic) -- 0.0 .. 0.6
	newPart(plaza, "BrazierPost",   Vector3.new(0.95, 3.4, 0.95), STONE, cf * CFrame.new(x, 1.9, z), Enum.Material.Plastic) -- 0.2 .. 3.6
	newPart(plaza, "BrazierCollar", Vector3.new(1.4, 0.45, 1.4), STONE, cf * CFrame.new(x, 3.55, z), Enum.Material.Plastic) -- 3.325 .. 3.775
	pillarCyl(plaza, "BrazierBowl", cf * CFrame.new(x, 3.95, z), 1.1, 3,
		Color3.fromRGB(196, 170, 130), Enum.Material.Plastic)          -- 3.4 .. 4.5, seated on the collar
	-- the glowing coals: a ROUND disc (matches the round bowl), not a square block, sunk into the bowl
	local coals = pillarCyl(plaza, "BrazierCoals", cf * CFrame.new(x, 4.55, z), 0.5, 2.2,
		Color3.fromRGB(255, 140, 40), Enum.Material.Neon)
	coals.CanCollide = false

	-- FLAME ANCHOR: an invisible, AXIS-ALIGNED part the fire/embers/light hang off. The coals disc is a
	-- rotated cylinder, and a ParticleEmitter fires from its part's "top" face -- on a rotated part that
	-- points SIDEWAYS, so the embers shot out horizontally. This anchor isn't rotated, so Top = straight up
	-- and the flame + embers flow upward as they should.
	local flameAnchor = newPart(plaza, "BrazierFlame", Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(255, 140, 40),
		cf * CFrame.new(x, 4.7, z), Enum.Material.Neon)
	flameAnchor.Transparency = 1; flameAnchor.CanCollide = false

	local fire = Instance.new("Fire")
	fire.Heat = 7; fire.Size = 4                    -- a bowl of coals, not a bonfire
	fire.Color = Color3.fromRGB(255, 190, 90); fire.SecondaryColor = Color3.fromRGB(255, 100, 20)
	fire.Parent = flameAnchor

	-- EMBERS: a slow drift of sparks climbing out of the bowl. This is the cheapest thing on the whole plaza and
	-- does more for it than any of the lights -- a still flame reads as a texture, a flame shedding embers reads
	-- as alive. Rate is deliberately tiny; a fountain of sparks would look like a bug.
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Rate = 6
	em.Lifetime = NumberRange.new(1.4, 2.6)
	em.Speed = NumberRange.new(1.5, 3)
	em.SpreadAngle = Vector2.new(14, 14)
	em.Acceleration = Vector3.new(0, 2.5, 0)         -- embers RISE -- heat, not gravity
	em.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0),
	})
	em.Transparency = NumberSequence.new({           -- fade in fast, fade out slowly as they cool
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	em.Color = ColorSequence.new(Color3.fromRGB(255, 190, 110), Color3.fromRGB(200, 70, 20))
	em.LightEmission = 0.8
	em.EmissionDirection = Enum.NormalId.Top -- straight up off the axis-aligned anchor
	em.Parent = flameAnchor

	local lt = Instance.new("PointLight")
	lt.Color = LIGHT.brazier.c; lt.Brightness = LIGHT.brazier.b; lt.Range = LIGHT.brazier.r; lt.Parent = flameAnchor
	flicker(lt, LIGHT.brazier.b, 0.22)               -- fire wobbles the most
end

-- (The gold trophy-on-a-plinth builder lived here. Both trophies were removed -- they stood just inside the
-- gateway and crowded the arrival. The whole builder is deleted rather than left behind unused: dead code that
-- still looks callable is the kind of thing that gets switched back on by accident six months later.)

-- The stone plaza + colonnade + "HALL OF FAME" gateway, so the three boards read as ONE deliberate monument
-- instead of three signposts that happen to be standing near each other.
local function buildPlaza(parent, cf)
	local plaza = Instance.new("Model"); plaza.Name = "LeaderboardPlaza"; plaza.Parent = parent

	-- FLOOR: a Cylinder part's circular faces point along its LOCAL X, so lay it flat by rotating 90 deg about Z.
	-- Its top sits at exactly y=0 (the marker's own height), which is the SAME plane the board posts stand on --
	-- that is what stops the boards floating or sinking, so do not raise it without raising ANCHOR_LIFT too.
	local floor = newPart(plaza, "PlazaFloor", Vector3.new(1, PLAZA_R * 2, PLAZA_R * 2),
		Color3.fromRGB(196, 170, 130), cf * CFrame.new(0, -0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Enum.Material.Plastic)
	floor.Shape = Enum.PartType.Cylinder

	local rim = newPart(plaza, "PlazaRim", Vector3.new(0.8, PLAZA_R * 2 + 1.6, PLAZA_R * 2 + 1.6),
		Color3.fromRGB(196, 170, 96), cf * CFrame.new(0, -0.9, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Enum.Material.Metal)
	rim.Shape = Enum.PartType.Cylinder

	-- BRICK COURSING around the plaza edge -- the same skin the Community Garden wraps its stone in.
	--
	-- Matching the garden's MATERIAL (Plastic) and COLOUR still left this reading as flat cast stone next to
	-- it, because the garden's stone texture is not a Material at all: it is GEOMETRY. brickRing() in
	-- CommunityGarden lays individual brick blocks in stacked rows, shifts every other row by half a brick
	-- (running bond) and alternates two tones so each brick catches the light separately. A Material swap can
	-- never reproduce that, which is why the colour matched and the texture did not.
	--
	-- Same numbers as the garden's: 2.4-stud bricks, 0.5 proud of the face, 0.86/0.9 of the cell so the mortar
	-- gaps show. Sits just outside the metal rim so the course bands the plaza rather than fighting it.
	do
		local BW, ROWS, ROW_H = 2.4, 2, 0.7
		local bR   = PLAZA_R + 1.0
		local n    = math.max(8, math.floor((2 * math.pi * bR) / BW))
		local step = 2 * math.pi / n
		for r = 0, ROWS - 1 do
			local y   = -1.4 + ROW_H * (r + 0.5)
			local off = (r % 2 == 0) and 0 or (step * 0.5) -- running bond: alternate rows shift half a brick
			for i = 0, n - 1 do
				local a = i * step + off
				-- X = radial (what makes the brick stand proud), Y = height, Z = tangent (its width)
				newPart(plaza, "Brick", Vector3.new(0.5, ROW_H * 0.86, BW * 0.9),
					((i + r) % 2 == 0) and Color3.fromRGB(196, 170, 130) or Color3.fromRGB(178, 150, 110),
					cf * CFrame.new(math.cos(a) * bR, y, math.sin(a) * bR) * CFrame.Angles(0, -a, 0),
					Enum.Material.Plastic)
			end
		end
		print(string.format("[HallOfFame] brick course: %d bricks x %d rows around r=%.1f (garden coursing)", n, ROWS, bR))
	end

	-- INLAY: a gold ring with a dark disc inside it, both stood PROUD of the floor rather than flush with it.
	-- Flush would z-fight (two coplanar surfaces flickering as the camera moves), so each layer clears the one
	-- below by a visible margin: floor top 0.00 -> glow top 0.15 -> gold top 0.20 -> disc top 0.30.
	--
	-- The glow ring is a hair WIDER than the gold one and sits just under it, so it reads as light bleeding out
	-- from beneath the metal rather than as a neon hoop lying on the ground.
	local ember = newPart(plaza, "InlayGlow", Vector3.new(0.3, 45.4, 45.4), Color3.fromRGB(255, 176, 80),
		cf * CFrame.new(0, 0.0, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Neon)
	ember.Shape = Enum.PartType.Cylinder; ember.CanCollide = false; ember.Transparency = 0.55
	local gold = newPart(plaza, "InlayRing", Vector3.new(0.3, 44, 44), Color3.fromRGB(214, 180, 96),
		cf * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Metal)
	gold.Shape = Enum.PartType.Cylinder; gold.CanCollide = false
	local disc = newPart(plaza, "InlayDisc", Vector3.new(0.4, 40, 40), Color3.fromRGB(96, 92, 86),
		cf * CFrame.new(0, 0.10, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Plastic)
	disc.Shape = Enum.PartType.Cylinder; disc.CanCollide = false

	-- ATMOSPHERE: gold motes drifting across the whole plaza, emitted from an invisible volume overhead. This is
	-- the one thing that makes the space feel like somewhere rather than like a pile of parts -- still air reads as
	-- empty, moving air reads as a place. Rate is low and the motes are near-transparent: it should be something
	-- you notice only once you stop and look, never a snowstorm.
	local air = newPart(plaza, "PlazaAir", Vector3.new(PLAZA_R * 1.6, 14, PLAZA_R * 1.6),
		Color3.new(1, 1, 1), cf * CFrame.new(0, 9, 0), Enum.Material.SmoothPlastic)
	air.Transparency = 1; air.CanCollide = false; air.CastShadow = false
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	dust.Rate = 14
	dust.Lifetime = NumberRange.new(4, 8)
	dust.Speed = NumberRange.new(0.3, 1.2)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Acceleration = Vector3.new(0.4, 0.25, 0)   -- a slow lazy updraft, not a fountain
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-20, 20)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.1) })
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.72),
		NumberSequenceKeypoint.new(0.7, 0.72), NumberSequenceKeypoint.new(1, 1),
	})
	dust.Color = ColorSequence.new(Color3.fromRGB(255, 220, 150), Color3.fromRGB(255, 180, 100))
	dust.LightEmission = 0.6
	dust.Parent = air

	-- ===== THE ENTRANCE ==================================================================================
	-- A kerbed road, not three loose slabs. Three things make it read as a way IN rather than as scenery:
	--   * the paving is ONE unbroken run  -- each slab is SLAB_D deep and stepped back by exactly SLAB_D, so they
	--     butt up. Stepping them by anything else (the first pass used 8 for a 7-deep slab) leaves strips of bare
	--     ground showing between them.
	--   * kerbs down both sides         -- they physically define the corridor, so the walkway is a thing you can
	--     see rather than an invisible rule the props are supposed to respect.
	--   * lanterns ON the kerbs         -- light down the sides, never in the middle.
	-- Everything here stands 0.25+ PROUD of the ground. A slab whose top face is exactly LEVEL with the ground (or
	-- with the plaza floor it laps under) is coplanar with it and z-fights.
	local SLAB_D    = 7
	local ROAD_HALF = WALK_HALF + 0.5    -- paving runs a touch WIDER than the clear corridor, so the kerb can grip it
	local ROAD_MID  = -(PLAZA_R + 1.5 + SLAB_D)  -- centre of the 3-slab run
	local ROAD_LEN  = SLAB_D * 3
	for i = 1, 3 do
		local slab = newPart(plaza, "Approach", Vector3.new(ROAD_HALF * 2, 0.4, SLAB_D),
			Color3.fromRGB(196, 170, 130),
			cf * CFrame.new(0, 0.05, -(PLAZA_R + 1.5 + (i - 1) * SLAB_D)), Enum.Material.Plastic)
		slab.CanCollide = false
	end

	-- KERBS. Their position is driven by the WIDEST piece of them (the cap, 1.5 wide), not by the kerb block --
	-- placing them so the 1.2-wide kerb just cleared the corridor left the cap overhanging it by 0.2 studs, which
	-- the audit caught. At |x| = WALK_HALF + 1 the cap's inner face lands at 10.25, clear, and the kerb still
	-- overlaps the (slightly wider) road so there is no strip of bare ground between them.
	for _, sx in ipairs({ -1, 1 }) do
		local kx = sx * (WALK_HALF + 1.0)
		newPart(plaza, "Kerb", Vector3.new(1.2, 1, ROAD_LEN), Color3.fromRGB(196, 170, 130),
			cf * CFrame.new(kx, 0.3, ROAD_MID), Enum.Material.Plastic)          -- -0.2 .. 0.8
		newPart(plaza, "KerbCap", Vector3.new(1.5, 0.3, ROAD_LEN), Color3.fromRGB(196, 170, 96),
			cf * CFrame.new(kx, 0.8, ROAD_MID), Enum.Material.Metal)          -- 0.65 .. 0.95
		-- LANTERNS standing ON the kerb, well outside the corridor.
		--
		-- The first pass was a bare neon ball on a stick: it read as a floating dot, and because a Neon part is
		-- fully self-lit it looked like a light bulb with nothing around it. A real lantern is a DIM source inside
		-- a HOUSING -- the glass catches the glow, the metal frame throws a shape, and the light itself can then be
		-- turned right down because the housing is what you actually see. That is why these are the dimmest lights
		-- on the plaza yet read as the most "lit".
		for _, lz in ipairs({ ROAD_MID + ROAD_LEN / 2 - 3, ROAD_MID - ROAD_LEN / 2 + 3 }) do
			-- ONE connected lantern. Every piece OVERLAPS its neighbour (the y ranges in the comments touch),
			-- so nothing floats: footing -> shaft -> collar -> glass base -> glass housing (in a metal cage) ->
			-- cap -> roof -> finial. The old version stacked a wide glass box on a thin post with a visible gap;
			-- the collar + glass base now bridge that width jump so it reads as a single object.
			local METAL = Color3.fromRGB(88, 80, 68)
			local GOLD  = Color3.fromRGB(196, 170, 96)
			local CAGE  = Color3.fromRGB(58, 52, 44)
			newPart(plaza, "LampBase",  Vector3.new(1.5, 0.7, 1.5), METAL, cf * CFrame.new(kx, 0.35, lz), Enum.Material.Metal) -- 0.0 .. 0.7
			newPart(plaza, "LampPost",  Vector3.new(0.6, 4.1, 0.6), METAL, cf * CFrame.new(kx, 2.35, lz), Enum.Material.Metal) -- 0.3 .. 4.4
			newPart(plaza, "LampCollar",Vector3.new(1.1, 0.5, 1.1), METAL, cf * CFrame.new(kx, 4.4,  lz), Enum.Material.Metal) -- 4.15 .. 4.65

			-- glass housing seated on a base plate; the flame lives inside it
			newPart(plaza, "LanternBase", Vector3.new(1.9, 0.3, 1.9), GOLD, cf * CFrame.new(kx, 4.75, lz), Enum.Material.Metal) -- 4.6 .. 4.9
			local glass = newPart(plaza, "LanternGlass", Vector3.new(1.6, 1.7, 1.6), Color3.fromRGB(255, 236, 190),
				cf * CFrame.new(kx, 5.75, lz), Enum.Material.Glass)            -- 4.9 .. 6.6, sits on the base plate
			glass.Transparency = 0.6; glass.CanCollide = false
			-- four thin cage bars on the glass edges -> reads as a real lantern frame, not a floating cube
			for _, corner in ipairs({ {0.73, 0.73}, {0.73, -0.73}, {-0.73, 0.73}, {-0.73, -0.73} }) do
				newPart(plaza, "LanternBar", Vector3.new(0.14, 1.7, 0.14), CAGE,
					cf * CFrame.new(kx + corner[1], 5.75, lz + corner[2]), Enum.Material.Metal).CanCollide = false
			end
			local core = newPart(plaza, "LanternFlame", Vector3.new(0.75, 0.9, 0.75), Color3.fromRGB(255, 214, 150),
				cf * CFrame.new(kx, 5.75, lz), Enum.Material.Neon)             -- inside the glass
			core.CanCollide = false

			newPart(plaza, "LanternCap",  Vector3.new(2.0, 0.35, 2.0), GOLD, cf * CFrame.new(kx, 6.75, lz), Enum.Material.Metal) -- 6.575 .. 6.925, caps the glass (top 6.6)
			newPart(plaza, "LanternRoof", Vector3.new(1.3, 0.5, 1.3),  METAL, cf * CFrame.new(kx, 7.05, lz), Enum.Material.Metal) -- 6.8 .. 7.3, overlaps the cap
			local finial = newPart(plaza, "LanternFinial", Vector3.new(0.55, 0.55, 0.55),
				Color3.fromRGB(214, 180, 96), cf * CFrame.new(kx, 7.5, lz), Enum.Material.Metal)
			finial.Shape = Enum.PartType.Ball; finial.CanCollide = false     -- 7.225 .. 7.775, sits on the roof

			local ll = Instance.new("PointLight")
			ll.Color = LIGHT.lantern.c; ll.Brightness = LIGHT.lantern.b; ll.Range = LIGHT.lantern.r
			ll.Parent = core
			flicker(ll, LIGHT.lantern.b, 0.10)  -- barely breathing -- a candle behind glass, not an open flame
		end
	end

	-- THRESHOLD: a gold strip laid across the gateway line. It is the moment you cross INTO the Hall of Fame, and
	-- it is deliberately the only thing allowed on the walkway -- flat, 0.4 studs proud, you walk straight over it.
	newPart(plaza, "Threshold", Vector3.new(30, 0.5, 1.6), Color3.fromRGB(214, 180, 96),
		cf * CFrame.new(0, 0.15, ARCH_Z), Enum.Material.Metal).CanCollide = false

	-- COLONNADE: columns around the rim with an architrave beam spanning each pair -- a real back wall for the
	-- boards to stand against. The gateway span is deliberately LEFT OPEN (no column in the doorway), and no beam
	-- is drawn across that gap, so the arch is the only way through and reads as the entrance.
	--
	-- The vertical stack, each piece biting EMBED into the one below:
	--   base -0.3..1.3  |  shaft 1.0..18.0  |  cap 17.75..18.65  |  architrave 18.35..19.65
	local COL_TOP  = 1 + COL_H            -- 18: top of the shaft
	local CAP_Y    = COL_TOP - 0.25       -- cap centre: sunk a quarter-stud onto the shaft
	local BEAM_Y   = COL_TOP + 1.0        -- architrave centre: bites down into the caps
	local cols = {}
	for a = 0, 359, COL_STEP do
		local inGate = math.abs(a - 180) < GATE_GAP -- 180 deg is the front/gateway
		if not inGate then
			cols[#cols + 1] = a
			newPart(plaza, "ColumnBase", Vector3.new(2.8, 1.6, 2.8), Color3.fromRGB(196, 170, 130),
				ring(cf, a, COL_R, 0.5), Enum.Material.Plastic) -- -0.3..1.3: sunk into the floor
			pillarCyl(plaza, "Column", ring(cf, a, COL_R, 1 + COL_H / 2), COL_H, 2,
				Color3.fromRGB(178, 150, 110), Enum.Material.Plastic)
			newPart(plaza, "ColumnCap", Vector3.new(2.6, 0.9, 2.6), Color3.fromRGB(212, 184, 108),
				ring(cf, a, COL_R, CAP_Y), Enum.Material.Metal)
		end
	end

	-- ARCHITRAVE: a beam between each ADJACENT pair of columns (one COL_STEP apart). The pair that straddles the
	-- gateway is more than one step apart, so this test skips it without needing a special case.
	local function colXZ(a)
		local r = math.rad(a)
		return math.sin(r) * COL_R, math.cos(r) * COL_R
	end
	for i = 1, #cols do
		local a1, a2 = cols[i], cols[(i % #cols) + 1]
		if math.abs(((a2 - a1) % 360) - COL_STEP) < 0.5 then
			local x1, z1 = colXZ(a1)
			local x2, z2 = colXZ(a2)
			beam(plaza, cf, "Architrave", x1, z1, x2, z2, BEAM_Y, 1.3, 1.6, Color3.fromRGB(178, 166, 144))
		end
	end

	-- ARCH: the gateway, at the FRONT of the plaza (ARCH_Z is negative = toward the viewer), so you walk THROUGH
	-- it to reach the boards. Its sign renders on the lintel's Front face (-Z), which -- because the whole model
	-- inherits the marker's rotation -- is the face pointing back at whoever is approaching.
	--   base -0.3..1.3 | pillar 1.0..17.0 | cap 16.8..17.8 | lintel 17.6..21.0 | lintel cap 20.85..21.55
	for _, sx in ipairs({ -16, 16 }) do
		newPart(plaza, "PillarBase", Vector3.new(3.6, 1.6, 3.6), Color3.fromRGB(196, 170, 130),
			cf * CFrame.new(sx, 0.5, ARCH_Z), Enum.Material.Plastic)
		newPart(plaza, "Pillar", Vector3.new(2.2, 16, 2.2), Color3.fromRGB(178, 150, 110),
			cf * CFrame.new(sx, 9, ARCH_Z), Enum.Material.Plastic)
		newPart(plaza, "PillarCap", Vector3.new(3, 1, 3), Color3.fromRGB(212, 184, 108),
			cf * CFrame.new(sx, 17.3, ARCH_Z), Enum.Material.Metal)
	end
	local lintel = newPart(plaza, "Lintel", Vector3.new(36, 3.4, 2.4), Color3.fromRGB(178, 166, 144),
		cf * CFrame.new(0, 19.3, ARCH_Z), Enum.Material.Plastic)
	newPart(plaza, "LintelCap", Vector3.new(37.5, 0.7, 3), Color3.fromRGB(212, 184, 108),
		cf * CFrame.new(0, 21.2, ARCH_Z), Enum.Material.Metal)

	-- STRUTS: tie the two ends of the colonnade into the arch, so the stonework is ONE CLOSED RING rather than a
	-- colonnade and an arch that merely stand near each other with a 9.6-stud hole between them. Each strut runs at
	-- the architrave's own height, from the last column before the gateway to the top of the nearest arch pillar --
	-- and since the lintel spans x -18..18 at that height, the strut's end lands INSIDE it and is captured.
	local nearL, nearR
	for _, a in ipairs(cols) do
		if a < 180 and (not nearR or a > nearR) then nearR = a end -- +X side (sin > 0)
		if a > 180 and (not nearL or a < nearL) then nearL = a end -- -X side
	end
	for _, s in ipairs({ { a = nearR, px = 16 }, { a = nearL, px = -16 } }) do
		if s.a then
			local cx, cz = colXZ(s.a)
			beam(plaza, cf, "ArchStrut", cx, cz, s.px, ARCH_Z, BEAM_Y, 1.3, 1.6, Color3.fromRGB(178, 166, 144))
		end
	end

	local sign = Instance.new("SurfaceGui")
	sign.Name = "ArchSign"; sign.Face = Enum.NormalId.Front -- -Z: the face turned toward the viewer
	sign.CanvasSize = Vector2.new(760, 68); sign.LightInfluence = 0; sign.MaxDistance = 320
	sign.Parent = lintel
	local st = Instance.new("TextLabel")
	st.Size = UDim2.new(1, 0, 1, 0); st.BackgroundTransparency = 1
	st.Font = Enum.Font.FredokaOne; st.TextScaled = true
	st.TextColor3 = Color3.fromRGB(255, 214, 92); st.Text = "\xF0\x9F\x8F\x86  HALL OF FAME"
	st.Parent = sign
	local ss = Instance.new("UIStroke"); ss.Color = Color3.fromRGB(70, 50, 10); ss.Thickness = 3; ss.Parent = st

	-- One COOL light under the arch, against all the warm firelight everywhere else. A scene lit in a single colour
	-- goes flat no matter how well you balance the brightness; one contrasting source is what gives the warm lights
	-- something to be warm AGAINST, and it makes the gateway read as a threshold between outside and inside.
	local gl = Instance.new("PointLight")
	gl.Color = LIGHT.gate.c; gl.Brightness = LIGHT.gate.b; gl.Range = LIGHT.gate.r
	gl.Parent = lintel

	-- BANNERS hanging off the lintel. They must be CAUGHT by it in BOTH axes, which the first pass got wrong twice:
	--   * vertically -- a 7.5-tall banner centred at 14 topped out at 17.75, just under the lintel's 17.8 underside,
	--     so it hung in mid-air by a 0.05-stud hair. It now tops out at 17.8, biting EMBED into the lintel.
	--   * in Z -- at ARCH_Z + 1.5 it sat 0.3 studs BEHIND the lintel's back face (ARCH_Z + 1.2) and so missed it
	--     entirely. It now hangs at ARCH_Z + 1.0, inside the lintel's own depth.
	for _, bx in ipairs({ -12, 12 }) do
		newPart(plaza, "Banner", Vector3.new(3.6, 7.8, 0.25), Color3.fromRGB(128, 34, 44),
			cf * CFrame.new(bx, 13.9, ARCH_Z + 1.0), Enum.Material.Fabric).CanCollide = false -- 10.0..17.8
		newPart(plaza, "BannerTrim", Vector3.new(3.6, 0.6, 0.35), Color3.fromRGB(212, 184, 108),
			cf * CFrame.new(bx, 10.2, ARCH_Z + 1.0), Enum.Material.Metal).CanCollide = false  -- 9.9..10.5
	end

	-- ===== PROPS -- ALL OF THEM OFF THE WALKWAY ==========================================================
	-- Everything near the entrance is pushed out to |x| = 13, which -- given a brazier bowl is 3 wide -- leaves its
	-- inner face at 11.5, clear of the 10-stud corridor edge.
	--
	-- The door braziers used to sit at x = +/-8. That is INSIDE the road. They now flank the gateway just inside
	-- the pillars, where a torch belongs. The audit below re-checks this rather than trusting the comment.
	-- The two gold trophy plinths that used to stand just inside the gateway are GONE. They crowded the one part of
	-- the plaza that should feel open -- the moment you step through the arch -- and having walked past a pair of
	-- torches you then had to walk past a second pair of pillars, which made the entrance a corridor instead of an
	-- arrival. The braziers stay because they light the threshold; the walk in is now clear all the way to the
	-- boards.
	local PROP_X = 13
	brazier(plaza, cf, -PROP_X, ARCH_Z + 3)   -- flanking the gateway, just inside the arch pillars
	brazier(plaza, cf,  PROP_X, ARCH_Z + 3)
	local ax, az = polar(78, 23)
	brazier(plaza, cf,  ax, az)               -- right end of the board arc (behind you -- never on the path)
	brazier(plaza, cf, -ax, az)               -- left end

	-- WALKWAY CLEARANCE: measured, not assumed. Half-widths are the widest part of each prop.
	local PROPS = {
		{ "brazier (left)",  -PROP_X, ARCH_Z + 3,  1.5 },
		{ "brazier (right)",  PROP_X, ARCH_Z + 3,  1.5 },
		{ "arch pillar (L)", -16,     ARCH_Z,      1.8 },
		{ "arch pillar (R)",  16,     ARCH_Z,      1.8 },
		{ "kerb (left)",     -(WALK_HALF + 1.0), ARCH_Z - 10, 0.75 },  -- half = the CAP's half-width, the widest bit
		{ "kerb (right)",     (WALK_HALF + 1.0), ARCH_Z - 10, 0.75 },
	}
	local blocked = 0
	for _, p in ipairs(PROPS) do
		local intrusion = walkwayIntrusion(p[2], p[3], p[4])
		if intrusion > 0 then
			blocked = blocked + 1
			warn(("[Leaderboard] WALKWAY BLOCKED: %s juts %.1f studs into the %d-wide corridor")
				:format(p[1], intrusion, WALK_HALF * 2))
		end
	end
	if blocked == 0 then
		print(("[Leaderboard] entrance: %d-stud corridor from the gate to the boards is CLEAR (%d props checked)")
			:format(WALK_HALF * 2, #PROPS))
	end

	return plaza
end

-- ===== JOINT AUDIT ========================================================================================
-- Every stacked pair, as (lower top, upper bottom). The overlap is (lowerTop - upperBottom): POSITIVE means the
-- upper piece bites into the lower one and the two read as joined stone. ZERO means they only kiss -- a hairline
-- seam that also z-fights. NEGATIVE means the upper piece is FLOATING.
--
-- This runs at startup and WARNS on anything <= 0, so a future tweak to any height cannot quietly leave a part
-- hanging in the air the way the banners and the board's gold cap both did.
local JOINTS = {
	{ "plaza floor -> column base",   0.0,  -0.30 },
	{ "column base -> column shaft",  1.30,  1.00 },
	{ "column shaft -> column cap",  18.00, 17.75 },
	{ "column cap -> architrave",    18.65, 18.35 },
	{ "plaza floor -> pillar base",   0.0,  -0.30 },
	{ "pillar base -> pillar",        1.30,  1.00 },
	{ "pillar -> pillar cap",        17.00, 16.80 },
	{ "pillar cap -> lintel",        17.80, 17.60 },
	{ "lintel -> lintel cap",        21.00, 20.85 },
	{ "lintel -> banner",            17.80, 17.80 - 0.30 },
	{ "banner -> banner trim",       10.50, 10.00 },
	{ "plaza floor -> brazier post",  0.0,  -0.30 },
	{ "brazier post -> bowl",         3.50,  3.15 },
	{ "bowl -> coals",                4.25,  4.05 },
	{ "ground -> kerb",               0.0,  -0.20 },
	{ "kerb -> kerb cap",             0.80,  0.65 },
	{ "kerb -> lamp post",            0.80,  0.00 },
	{ "lamp post -> lantern glass",   5.00,  4.90 },
	{ "lantern glass -> cap",         6.50,  6.275 },
	{ "lantern cap -> finial",        6.625, 6.45 },
	-- (the podium + post joints were removed with those parts)
	{ "board panel -> gold cap",       7.00 + ANCHOR_LIFT,   6.90 + ANCHOR_LIFT },
}

local function auditJoints()
	local worst, worstName, bad = math.huge, "", 0
	for _, j in ipairs(JOINTS) do
		local overlap = j[2] - j[3]
		if overlap <= 0 then
			bad = bad + 1
			warn(("[Leaderboard] JOINT BROKEN: %s -- overlap %.2f studs (%s)")
				:format(j[1], overlap, (overlap < 0) and "FLOATING" or "seam only, will z-fight"))
		end
		if overlap < worst then worst, worstName = overlap, j[1] end
	end
	if bad == 0 then
		print(("[Leaderboard] joints: all %d connected, tightest is '%s' at %.2f studs of overlap")
			:format(#JOINTS, worstName, worst))
	end
end

-- Build one physical board: a stepped stone podium, a post, a glowing framed panel, and a spotlight.
-- Returns the Frame the refresh loop writes rows into.
local function buildBoard(parent, board, cf)
	local model = Instance.new("Model"); model.Name = "Leaderboard_" .. board.key; model.Parent = parent

	-- (the podium AND the post were removed by request -- the panel rises straight from the plaza floor)

	local panel = newPart(model, "Panel", Vector3.new(PANEL_W, PANEL_H, 0.6), Color3.fromRGB(16, 20, 32),
		cf, Enum.Material.SmoothPlastic)
	-- glowing frame sits BEHIND the panel (+Z) so it haloes the board without covering the SurfaceGui,
	-- which renders on the panel's Front face (-Z).
	newPart(model, "Glow", Vector3.new(PANEL_W + 0.8, PANEL_H + 0.8, 0.35), board.color,
		cf * CFrame.new(0, 0, 0.25), Enum.Material.Neon)
	-- Gold cap along the top edge, tying the three boards together as a set. At +0.6 its underside sat at 7.2 --
	-- a fifth of a stud ABOVE the panel's 7.0 top edge, so it floated. At +0.3 it grips the panel by 0.1.
	newPart(model, "Cap", Vector3.new(PANEL_W + 1.4, 0.8, 1.4), Color3.fromRGB(212, 184, 108),
		cf * CFrame.new(0, PANEL_H / 2 + 0.3, 0.1), Enum.Material.Metal)  -- 6.9 .. 7.7
	model.PrimaryPart = panel

	-- a soft light in the board's OWN colour, so each board owns a pool of coloured light instead of all three
	-- drowning in the same warm wash. Dim and short-range on purpose -- it should tint the stone right around the
	-- board, not reach across the plaza and mix with the other two into mud.
	local lamp = Instance.new("PointLight")
	lamp.Color = board.color; lamp.Brightness = LIGHT.board.b; lamp.Range = LIGHT.board.r; lamp.Parent = panel

	local sg = Instance.new("SurfaceGui")
	sg.Name = "Board"
	sg.Face = Enum.NormalId.Front -- -Z, i.e. the face CFrame.lookAt turned toward the player
	sg.CanvasSize = Vector2.new(500, 560)
	sg.LightInfluence = 0
	sg.AlwaysOnTop = false
	sg.MaxDistance = 300 -- readable across the island, not rendered from orbit
	sg.Active = true     -- REQUIRED for the scroll list below: without it the SurfaceGui ignores all input and
	                     -- the board renders but refuses to scroll, which reads as "it's broken"
	sg.Parent = panel

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0); bg.BackgroundColor3 = Color3.fromRGB(20, 25, 40)
	bg.BorderSizePixel = 0; bg.Parent = sg
	-- subtle vertical gradient: lighter at the top where the header is, darker toward the bottom
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(34, 42, 64), Color3.fromRGB(14, 18, 28))
	grad.Parent = bg
	-- FRAMED LOOK: rounded corners + a border in the board's colour, so the face reads as a finished panel
	-- rather than a flat rectangle of text.
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 16)
	local bgBorder = Instance.new("UIStroke"); bgBorder.Color = board.color
	bgBorder.Thickness = 3; bgBorder.Transparency = 0.3; bgBorder.Parent = bg

	-- HEADER BAR: a solid band in the board's colour, with the title knocked out on top of it
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 74); header.BorderSizePixel = 0
	header.BackgroundColor3 = board.color; header.BackgroundTransparency = 0.82; header.Parent = bg
	local hline = Instance.new("Frame")
	hline.Size = UDim2.new(1, 0, 0, 4); hline.Position = UDim2.new(0, 0, 1, -4)
	hline.BorderSizePixel = 0; hline.BackgroundColor3 = board.color; hline.Parent = header

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 52); title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1; title.Font = Enum.Font.FredokaOne; title.TextScaled = true
	title.TextColor3 = board.color; title.Text = board.title; title.Parent = header
	local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(8, 10, 16); ts.Thickness = 3; ts.Parent = title

	-- SCROLLING list. A board only shows ~9 rows at a time but holds up to TOP_N (100), so walk up and scroll it.
	-- The canvas is driven off the layout's measured content height rather than a guessed number, so it always
	-- scrolls exactly as far as there are rows -- no dead space under a short board, no rows cut off a full one.
	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.Size = UDim2.new(1, -20, 1, -102); list.Position = UDim2.new(0, 10, 0, 84)
	list.BackgroundTransparency = 1; list.BorderSizePixel = 0
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = board.color
	list.ScrollBarImageTransparency = 0.35
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Active = true
	list.Parent = bg
	local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0, 4)
	ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = list
	ll:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		list.CanvasSize = UDim2.new(0, 0, 0, ll.AbsoluteContentSize.Y + 8)
	end)

	-- footer: says how fresh the numbers are, so a stale-looking board doesn't read as broken
	local foot = Instance.new("TextLabel")
	foot.Size = UDim2.new(1, -20, 0, 16); foot.Position = UDim2.new(0, 10, 1, -18)
	foot.BackgroundTransparency = 1; foot.Font = Enum.Font.Gotham; foot.TextSize = 12
	foot.TextColor3 = Color3.fromRGB(110, 126, 155)
	foot.Text = ("scroll for the full top %d  \xC2\xB7  updates every %ds"):format(TOP_N, REFRESH_SECONDS)
	foot.Parent = bg

	return list
end

-- ===== REFRESH ==============================================================================
-- Names are resolved with GetNameFromUserIdAsync and CACHED -- without the cache this would fire ~30
-- web calls a minute (10 rows x 3 boards) forever, which would get rate-limited and stall the loop.
local nameCache = {}
local function nameOf(userId)
	local cached = nameCache[userId]
	if cached then return cached end
	local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	n = (ok and type(n) == "string" and n) or ("Player " .. userId)
	nameCache[userId] = n
	return n
end

local function refreshBoard(board, list)
	if not (board.ods and list and list.Parent) then return end
	-- ascending = true only for OG FARTERS, where the LOWEST number (OG #1) is the top of the board.
	local ok, pages = pcall(function() return board.ods:GetSortedAsync(board.ascending == true, TOP_N) end)
	if not ok then warn("[Leaderboard] read failed (" .. board.key .. "): " .. tostring(pages)); return end
	local okPage, rows = pcall(function() return pages:GetCurrentPage() end)
	if not okPage then return end

	for _, c in ipairs(list:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end

	if #rows == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 40); empty.BackgroundTransparency = 1
		empty.Font = Enum.Font.Gotham; empty.TextSize = 22; empty.TextColor3 = Color3.fromRGB(150, 165, 195)
		empty.Text = "No scores yet - be the first!"; empty.Parent = list
		return
	end

	-- 🥇🥈🥉 for the podium, a plain number for everyone else
	local MEDAL = { "\xF0\x9F\xA5\x87", "\xF0\x9F\xA5\x88", "\xF0\x9F\xA5\x89" }
	local MEDAL_COLOR = {
		Color3.fromRGB(255, 215, 0),   -- gold
		Color3.fromRGB(205, 214, 224), -- silver
		Color3.fromRGB(214, 145, 82),  -- bronze
	}

	for i, entry in ipairs(rows) do
		local top = (i <= 3)
		local accent = MEDAL_COLOR[i] or Color3.fromRGB(140, 158, 190)

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, top and 54 or 44); row.LayoutOrder = i; row.BorderSizePixel = 0
		row.BackgroundColor3 = top and Color3.fromRGB(44, 52, 76) or Color3.fromRGB(26, 32, 48)
		row.BackgroundTransparency = top and 0.05 or 0.25; row.Parent = list
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
		if top then -- the podium rows get an outline in their medal colour
			local rs = Instance.new("UIStroke"); rs.Color = accent; rs.Thickness = 2
			rs.Transparency = 0.25; rs.Parent = row
		end
		-- a colour flash down the left edge, so rank reads instantly even at a distance
		local edge = Instance.new("Frame")
		edge.Size = UDim2.new(0, 5, 1, -10); edge.Position = UDim2.new(0, 4, 0, 5)
		edge.BackgroundColor3 = accent; edge.BorderSizePixel = 0; edge.Parent = row
		Instance.new("UICorner", edge).CornerRadius = UDim.new(0, 3)

		local rank = Instance.new("TextLabel")
		rank.Size = UDim2.new(0, 46, 1, 0); rank.Position = UDim2.new(0, 12, 0, 0)
		rank.BackgroundTransparency = 1; rank.Font = Enum.Font.FredokaOne
		rank.TextSize = top and 32 or 24; rank.TextColor3 = accent
		rank.Text = MEDAL[i] or ("#" .. i); rank.Parent = row

		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(1, -240, 1, 0); nm.Position = UDim2.new(0, 62, 0, 0)
		nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold
		nm.TextSize = top and 25 or 21; nm.TextColor3 = Color3.new(1, 1, 1)
		nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextTruncate = Enum.TextTruncate.AtEnd
		nm.Text = nameOf(tonumber(entry.key) or 0); nm.Parent = row

		-- wider than it used to be: "Island 12 · 4h 07m" does not fit in the 130px the old coin counts needed
		local val = Instance.new("TextLabel")
		val.Size = UDim2.new(0, 172, 1, 0); val.Position = UDim2.new(1, -180, 0, 0)
		val.BackgroundTransparency = 1; val.Font = Enum.Font.GothamBold
		val.TextSize = top and 21 or 18; val.TextColor3 = board.color
		val.TextXAlignment = Enum.TextXAlignment.Right
		val.Text = board.fmt(entry.value); val.Parent = row
	end
end

-- ===== STARTUP ==============================================================================
task.spawn(function()
	-- wait for the islands to be POSITIONED before anchoring to them: PlayerStats moves Island_1 to its
	-- final Y after startup, so building against its pre-move pivot would leave the boards floating in
	-- the sky. StandsReady is the same flag PetSystem waits on for its markers.
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 40 do
		task.wait(0.5); waited = waited + 0.5
	end

	local anchor = findAnchor()
	if not anchor then
		warn("[Leaderboard] could not find Island_1 or a LeaderboardSpot -- boards NOT built")
		return
	end

	-- Spin and shift the anchor BEFORE building. Order matters: spin first, THEN step forward, so "forward" means
	-- "the way the sign now faces" and not "the way the marker part happened to be pointing".
	local marked = anchor.Position
	anchor = anchor * CFrame.Angles(0, math.rad(MONUMENT_SPIN), 0) -- turn the sign toward the viewer
	anchor = anchor * CFrame.new(0, 0, -FORWARD_NUDGE)             -- -Z is forward: step toward the viewer
	print(("[Leaderboard] aimed: spun %ddeg about Y, nudged %d studs forward -> centre moved %s -> %s")
		:format(MONUMENT_SPIN, FORWARD_NUDGE, tostring(marked), tostring(anchor.Position)))

	local folder = Instance.new("Folder"); folder.Name = "Leaderboards"; folder.Parent = Workspace
	pcall(buildPlaza, folder, anchor)
	pcall(auditJoints) -- shouts if any stacked piece ends up floating or merely kissing the one below it

	-- KEEP-OUT ZONE: publish the hall-of-fame footprint (plaza in front + board arc behind) so wandering
	-- creatures (the Cow easter egg) route AROUND it instead of walking through the boards/plaza.
	_G.hallOfFameZone = { center = anchor.Position, radius = PLAZA_R + 6 }

	-- ARC LAYOUT. Board i is swung around the plaza centre by (i - middle) * ARC_SPREAD degrees, then pushed
	-- BACKWARD (+Z, away from the viewer) by ARC_RADIUS. Because the board inherits that swung rotation, its own
	-- front face (-Z) ends up pointing back through the plaza centre -- so every board automatically angles inward
	-- at whoever is standing at the gateway. No extra flip is needed, and adding one is what broke it before.
	local lists = {}
	local middle = (#BOARDS + 1) / 2
	for i, board in ipairs(BOARDS) do
		local angle = math.rad((i - middle) * ARC_SPREAD)
		local cf = anchor
			* CFrame.Angles(0, angle, 0)             -- swing around the plaza centre
			* CFrame.new(0, ANCHOR_LIFT, ARC_RADIUS) -- push BACK along the arc, lifted to stand on the ground
		local okB, list = pcall(buildBoard, folder, board, cf)
		if okB then lists[board.key] = list
		else warn("[Leaderboard] board build failed (" .. board.key .. "): " .. tostring(list)) end
	end
	local chord = 2 * ARC_RADIUS * math.sin(math.rad(ARC_SPREAD) / 2)
	print(("[Leaderboard] %d board(s) + plaza at %s | arc %ddeg / %d studs -> %.1f stud gap between %d-wide boards"
		.. " (must exceed panel width), plaza radius %d")
		:format(#BOARDS, tostring(anchor.Position), ARC_SPREAD, ARC_RADIUS, chord, PANEL_W, PLAZA_R))

	-- refresh forever. Each board is pcall'd separately so one failing store can't stall the others.
	while true do
		for _, board in ipairs(BOARDS) do
			pcall(refreshBoard, board, lists[board.key])
		end
		task.wait(REFRESH_SECONDS)
	end
end)

print(("[Leaderboard] service ready -- FASTEST CLIMB / OG FARTERS (first %d ever) / MOST PLAYTIME; top %d each, "
	.. "scrollable; submit on join + autosave + leave"):format(OG_LIMIT, TOP_N))
