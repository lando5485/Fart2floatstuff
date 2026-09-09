--!nonstrict
--======================================================================
-- ROCKET RIDE -- THE FLIGHT DECK  (LocalScript, per-player)
--======================================================================
-- Boarding at the launch command stand takes you INSIDE the rocket. Not "welded to a chair bolted to the
-- hull" -- inside, in a round capsule: a sealed pressure vessel with a curved console, a launch couch, and
-- no window.
--
-- THERE IS NO WINDOW, AND THAT IS THE DESIGN. One was tried. A window has to look at something, and the only
-- honest options were both bad: a painted star field that is obviously painted the moment you lean toward
-- it, or flying the whole room over Bean Farm so the view is real -- which works, and drags the altitude
-- coin exploit back in behind it the moment a rider stands up and takes off. A hull with no window has
-- neither problem and costs nothing to believe: capsules that are all instruments and no view are the
-- normal kind.
--
-- ===== THE TRICK, AND WHY IT COSTS THE SERVER NOTHING =====
-- The rocket has no inside. Its body tube is sixteen studs across and a character is five tall and four wide,
-- so anything built in there is a broom cupboard. The deck below is a sealed room THIS SCRIPT builds at
-- runtime, thousands of studs off to the side in empty space, and "boarding" is char:PivotTo() behind a black
-- fade. Exactly the trick the island 5 secret cave uses, for exactly the same reasons:
--
--   * A LocalScript builds it, so it does not replicate. Nobody else can see your deck, walk into it, or
--     stand in your couch. Every rider gets their own at their own offset, so two riders never collide.
--   * The room is not bound by the rocket's real geometry, so it can be an actual place -- round, tall
--     enough to stand up in, and furnished.
--
-- IT IS ROUND, AND IT IS SMALL. A capsule 22 studs across, walled with sixteen panels standing in a ring so
-- the eye reads a curve rather than corners, with a cylinder floor and ceiling closing it top and bottom.
-- Both facts do work: a box has corners and corners are what make an interior read as a ROOM, and a big
-- interior reads as a hall. The tightness is the point -- you are in a capsule, and it should feel like one.
--
-- ===== THE FOOD-REALM HAZARD: THE CAPSULE MUST BE LOW =====
-- Coins here are paid by ALTITUDE, every half second while flying:
--     coins = height * 0.008 + (height / 500) ^ 2        -- height = hrp.Position.Y
-- The rocket's flight ends at Y ~23,900. Put the deck at that altitude to "really" ride and you have built a
-- coin printer worth roughly 2,300 coins a second to a player strapped into a chair. So the capsule sits at
-- Y = 190, and the ride is sold by what you can SEE out of the viewport -- the star field, the shake, the
-- engine glow -- not by the number in the Y column. Nothing about the ride is worth reopening that hole.
--
-- ===== WHY EVERY EXIT PATH RESTORES EVERYTHING =====
-- Boarding changes Lighting and hides the HUD. If any exit path misses a restore, the player is left in a
-- dark world with no HUD and no way to fix it -- so `leave()` is the single exit, and the ending, the abort,
-- respawning and disconnecting all go through it.
--======================================================================

if _G.__RocketRideClient then return end
_G.__RocketRideClient = true

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RideEvent = ReplicatedStorage:WaitForChild("RocketRideEvent", 60)
if not RideEvent then
	warn("[RocketRide] RocketRideEvent never appeared -- the ride is inactive")
	return
end

--======================================================================
-- TUNING
--======================================================================
local DECK_R   = 11    -- capsule radius: 22 studs across. Two couches, a console, and not a lot else.
local DECK_H   = 15    -- floor to ceiling. Tall enough to stand under, low enough to feel like a hull.
local WALL_SEG = 16    -- panels in the wall ring. Sixteen is where the facets stop reading as facets.
local VOID_Y    = 190                        -- see the altitude note above -- do NOT raise this
local FADE_TIME = 0.4

-- Palette: instrument greys and neon, the same language the secret cave speaks. A white interior reads as the
-- inside of a fridge; this reads as somewhere you strap in.
local C_HULL   = Color3.fromRGB(52, 56, 68)
local C_HULL_D = Color3.fromRGB(34, 37, 46)
local C_RIB    = Color3.fromRGB(92, 98, 116)
local C_DECK   = Color3.fromRGB(40, 43, 52)
local C_SEAT   = Color3.fromRGB(198, 52, 46)
local C_SEAT_D = Color3.fromRGB(148, 33, 29)
local C_STRAP  = Color3.fromRGB(232, 226, 210)
local C_PANEL  = Color3.fromRGB(26, 28, 36)
local C_CYAN   = Color3.fromRGB(94, 198, 255)
local C_AMBER  = Color3.fromRGB(255, 190, 80)
local C_GREEN  = Color3.fromRGB(120, 255, 140)
local C_RED    = Color3.fromRGB(255, 96, 72)
local C_STRIPE = Color3.fromRGB(240, 196, 48)

local deck, origin, seatPart
local alertLights = {}     -- the red bulbs that pulse on liftoff
local gauges      = {}     -- instrument needles: idle drift on the pad, hard over under thrust
local floaters    = {}     -- loose gear that lifts off the console once we're flying (the zero-G payoff)
local cabinDust   = nil    -- the ambient mote emitter; speeds up under thrust
local floatT      = 0      -- 0..1 ramp: how far "gravity has left" -- see the zero-G block in the ride loop
local screens     = {}     -- console/overhead panels that flicker and scroll while the ride runs
local thrustGlow  = {}     -- the floor-line strips that come up under thrust
local steamJets   = {}     -- vent emitters, off on the pad and blowing on liftoff
local missionClock = nil   -- the T-minus readout on the capsule wall
-- os.clock() time the rocket leaves. Seeded from the server when you board and re-seeded by every
-- countdown broadcast, so the wall clock ticks continuously but can never drift from the one outside:
-- the broadcast is always the authority, this is only what fills the gaps between broadcasts.
local missionEndsAt = nil
local inside, busy = false, false
local flying = false       -- liftoff has happened: shake the deck, blaze the thrust line, blow the vents
local savedLighting, shakeConn
-- The player's own zoom limits, put back exactly as found. Never assume the default: somebody arriving with
-- a locked first-person setting from another system must leave with it still locked.
local savedCam = nil

-- WHERE THE REAL LAUNCH IS. Captured from the event's own broadcasts, because the whole point of the window
-- is that it shows the actual Bean Farm and the actual rocket, not a painted backdrop of them.

local hudWasHidden = false

--======================================================================
-- helpers
--======================================================================
local function part(name, size, cf, colour, mat)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.CFrame = cf
	p.Color = colour or C_HULL
	p.Material = mat or Enum.Material.Metal
	-- CanQuery stays ON for the shell: the floor has to answer a downward ray, or any ground check run
	-- while a rider is in here decides they are standing on nothing. prop() turns it off for decor, so a
	-- ray can never catch on a pipe or a console screen.
	p.Anchored = true; p.CanCollide = true; p.CanQuery = true; p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = deck
	return p
end

-- Decoration: seen, never bumped into. Everything that is not floor, wall or ceiling is one of these, so a
-- rider can never get wedged behind a console or stuck on a pipe in a sealed room they cannot leave.
local function prop(name, size, cf, colour, mat)
	local p = part(name, size, cf, colour, mat)
	p.CanCollide = false
	p.CanQuery = false
	return p
end

local function light(parent, colour, brightness, range)
	local l = Instance.new("PointLight")
	l.Color = colour; l.Brightness = brightness; l.Range = range
	l.Parent = parent
	return l
end

local function toast(msg, colour, secs)
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(_G.NotifyCenter.push, { text = msg, color = colour, duration = secs or 4 })
	elseif _G.showHudBanner then
		pcall(_G.showHudBanner, msg, colour, secs or 4)
	else
		print("[RocketRide] " .. msg)
	end
end

-- Black wipe. Every teleport hides behind one, because PivotTo is instant and without the cover you see the
-- world snap -- which reads as a glitch, not a door.
local function withFade(midpoint)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RocketRideFade"; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10000; gui.ResetOnSpawn = false; gui.Parent = playerGui
	local sheet = Instance.new("Frame")
	sheet.Size = UDim2.fromScale(1, 1); sheet.BackgroundColor3 = Color3.new(0, 0, 0)
	sheet.BackgroundTransparency = 1; sheet.BorderSizePixel = 0; sheet.Parent = gui

	TweenService:Create(sheet, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 0 }):Play()
	task.wait(FADE_TIME)
	pcall(midpoint)
	task.wait(0.12)
	TweenService:Create(sheet, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 1 }):Play()
	task.delay(FADE_TIME + 0.1, function() gui:Destroy() end)
end

--======================================================================
-- BUILD THE DECK
--======================================================================
-- Built ONCE, on the first boarding, and kept. Rebuilding it every launch would pay the whole construction
-- cost inside the fade the player is waiting on; keeping it costs a few hundred anchored parts nobody else
-- can see, parked in empty space.
local function buildDeck()
	if deck then return end

	-- Own quadrant, far from the secret cave's +X/+Z corner, so the two void rooms can never overlap even for
	-- a player whose UserId offsets them badly.
	local ox = -9000 - (player.UserId % 89) * 300
	local oz =  9000 + (player.UserId % 71) * 300
	origin = Vector3.new(ox, VOID_Y, oz)

	deck = Instance.new("Model")
	deck.Name = "RocketCapsule"
	deck.Parent = Workspace

	-- The viewport occupies the arc facing -Z, so that is "forward" for everything in here.
	local FWD = -math.pi / 2   -- panel angle whose outward normal points along -Z
	local segArc = (2 * math.pi) / WALL_SEG
	-- Chord width of one segment, plus a hair so neighbours overlap instead of leaving hairline gaps.
	local segW = 2 * DECK_R * math.sin(segArc / 2) + 0.25


	-- ---------- FLOOR + CEILING ----------
	-- Real cylinders, not squares hidden under the wall ring. The floor edge is visible where it meets the
	-- panels, and a square one would put four corners into a room whose whole job is not having any.
	local floorP = part("CapsuleFloor", Vector3.new(1.6, DECK_R * 2, DECK_R * 2),
		CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90)), C_DECK, Enum.Material.DiamondPlate)
	floorP.Shape = Enum.PartType.Cylinder
	-- NOSE DOME, not a flat lid. A disc overhead is a ceiling and reads as a room; a cone tapering to a cap
	-- reads as the inside of a nose, which is the strongest single cue in here that you are in a rocket.
	--
	-- IT HAS TO BE CONICAL BANDS, NOT STACKED DISCS. A stack of shrinking discs looks right from outside and
	-- is invisible from in here: the widest disc is opaque and sits directly overhead, so it hides every
	-- smaller one above it and all a rider sees is the same flat lid. These are rings of panels leaning
	-- inward, so you are looking UP THE INSIDE of the taper.
	--
	-- Still sealed: the bands are contiguous and the cap closes the top, so a player who fart-flies indoors
	-- cannot leave through the roof into empty void.
	for b, band in ipairs({ { 1.00, 0.78, 0.0, 1.9 }, { 0.78, 0.50, 1.9, 3.4 }, { 0.50, 0.22, 3.4, 4.7 } }) do
		local r0, r1 = DECK_R * band[1], DECK_R * band[2]
		local y0, y1 = DECK_H + band[3], DECK_H + band[4]
		local midR, midY = (r0 + r1) / 2, (y0 + y1) / 2
		local dr, dy = r0 - r1, y1 - y0
		local slant = math.sqrt(dr * dr + dy * dy) + 0.3   -- overlap the neighbouring band
		local tilt  = math.atan2(dr, dy)                   -- lean off vertical
		local segW2 = 2 * midR * math.sin(segArc / 2) + 0.35
		for i = 1, WALL_SEG do
			local a1 = (i - 1) * segArc
			-- Yaw puts local +Z outward (same convention as the wall ring), so the tilt is NEGATIVE to bring
			-- the top edge in toward the axis rather than flaring it out.
			part("NoseBand_" .. b .. "_" .. i, Vector3.new(segW2, slant, 0.9),
				CFrame.new(origin + Vector3.new(math.cos(a1) * midR, midY, math.sin(a1) * midR))
					* CFrame.Angles(0, -a1 + math.pi / 2, 0) * CFrame.Angles(-tilt, 0, 0),
				(b == 1) and C_HULL or C_HULL_D)
		end
	end
	local cap = part("NoseCap", Vector3.new(1, DECK_R * 0.62, DECK_R * 0.62),
		CFrame.new(origin + Vector3.new(0, DECK_H + 4.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), C_HULL_D)
	cap.Shape = Enum.PartType.Cylinder
	-- A lamp ring tucked up in the taper: light from the nose, which is where a capsule's light comes from.
	for i = 1, 4 do
		local a1 = (i - 1) * (math.pi / 2) + math.pi / 4
		local lamp = prop("NoseLamp_" .. i, Vector3.new(1.1, 0.35, 1.1),
			CFrame.new(origin + Vector3.new(math.cos(a1) * DECK_R * 0.55, DECK_H + 2.4, math.sin(a1) * DECK_R * 0.55)),
			Color3.fromRGB(226, 240, 255), Enum.Material.Neon)
		light(lamp, Color3.fromRGB(200, 226, 255), 1.1, 20)
	end

	-- ---------- WALL RING ----------
	-- Sixteen panels stood on the circle, each turned to face the middle, with a rib on every seam. The ribs
	-- are what sell the curve: they catch the light at sixteen different angles, so the eye reads a barrel
	-- instead of noticing sixteen flat faces.
	for i = 1, WALL_SEG do
		local ang = FWD + (i - 1 - 4) * segArc
		local px, pz = math.cos(ang) * DECK_R, math.sin(ang) * DECK_R
		local at = CFrame.new(origin + Vector3.new(px, DECK_H / 2, pz))
			* CFrame.Angles(0, -ang + math.pi / 2, 0)   -- face the axis

		do
			part("HullPanel_" .. i, Vector3.new(segW, DECK_H, 0.9), at, C_HULL)
			-- QUILTING. Real capsule walls are padded in a grid of squares, and a grid is what stops a flat
			-- panel reading as a flat panel -- it gives the light something to break on at every height, so
			-- the wall has texture from any angle instead of only where a rib happens to be.
			for row = 0, 3 do
				for col = -1, 1 do
					prop("Quilt_" .. i .. "_" .. row .. "_" .. col,
						Vector3.new(segW / 3.4, 2.1, 0.22),
						at * CFrame.new(col * (segW / 3.1), -4.2 + row * 2.7, -0.5), C_HULL_D)
				end
			end
		end

		-- Seam rib, on the join between this panel and the next.
		local rang = ang + segArc / 2
		prop("Rib_" .. i, Vector3.new(0.55, DECK_H - 1, 0.9),
			CFrame.new(origin + Vector3.new(math.cos(rang) * (DECK_R - 0.35), DECK_H / 2, math.sin(rang) * (DECK_R - 0.35)))
				* CFrame.Angles(0, -rang + math.pi / 2, 0), C_RIB)
	end

	-- Deck ring + hazard chevrons around the floor edge, and a centre plate where the couches point.
	-- A ring of short segments, NOT a Cylinder part: a Cylinder is a solid disc, which at this position
	-- would be a second floor laid over the first rather than a rim around its edge.
	for i = 1, WALL_SEG do
		local a1 = (i - 1) * segArc
		prop("DeckRim_" .. i, Vector3.new(segW, 0.35, 0.7),
			CFrame.new(origin + Vector3.new(math.cos(a1) * (DECK_R - 0.6), 0.9, math.sin(a1) * (DECK_R - 0.6)))
				* CFrame.Angles(0, -a1 + math.pi / 2, 0), C_RIB, Enum.Material.SmoothPlastic)
	end
	for i = 1, 12 do
		local a2 = (i - 1) * (2 * math.pi / 12)
		prop("Chevron_" .. i, Vector3.new(1.6, 0.1, 0.5),
			CFrame.new(origin + Vector3.new(math.cos(a2) * (DECK_R - 2), 0.86, math.sin(a2) * (DECK_R - 2)))
				* CFrame.Angles(0, -a2, 0), C_STRIPE, Enum.Material.SmoothPlastic)
	end

	-- ---------- CURVED CONSOLE ----------
	-- Follows the wall in five short segments, so the instrument bank bends with the hull instead of being a
	-- straight desk shoved against a round wall.
	for k = -2, 2 do
		local ang = FWD + k * segArc
		local cr = DECK_R - 2.6
		local at = CFrame.new(origin + Vector3.new(math.cos(ang) * cr, 2.3, math.sin(ang) * cr))
			* CFrame.Angles(0, -ang + math.pi / 2, 0)
		prop("ConsoleBody_" .. k, Vector3.new(4.2, 2.6, 2.2), at, C_PANEL)
		prop("ConsoleFace_" .. k, Vector3.new(4.2, 2, 0.4), at * CFrame.new(0, 1.15, -0.85) * CFrame.Angles(math.rad(32), 0, 0), C_HULL_D)
		local scr = prop("ConsoleScreen_" .. k, Vector3.new(2.6, 1, 0.16),
			at * CFrame.new(0, 1.3, -1.05) * CFrame.Angles(math.rad(32), 0, 0),
			({ C_CYAN, C_GREEN, C_AMBER })[((k + 2) % 3) + 1], Enum.Material.Neon)
		scr.Transparency = 0.15
		screens[#screens + 1] = scr
		for j = -1, 1 do
			prop("ConsoleSwitch_" .. k .. "_" .. j, Vector3.new(0.28, 0.28, 0.28),
				at * CFrame.new(j * 1.1, 0.35, -1.15) * CFrame.Angles(math.rad(32), 0, 0),
				({ C_RED, C_GREEN, C_AMBER })[j + 2], Enum.Material.Neon)
		end
	end
	-- Two throttles at the ends of the bank, so there is something in here that looks like it moves.
	for _, sk in ipairs({ -2.6, 2.6 }) do
		local ang = FWD + sk * segArc * 0.8
		local cr = DECK_R - 2.8
		prop("Throttle", Vector3.new(0.32, 1.9, 0.32),
			CFrame.new(origin + Vector3.new(math.cos(ang) * cr, 4.2, math.sin(ang) * cr)) * CFrame.Angles(math.rad(16), 0, 0), C_RIB)
		prop("ThrottleKnob", Vector3.new(0.7, 0.7, 0.7),
			CFrame.new(origin + Vector3.new(math.cos(ang) * cr, 5.1, math.sin(ang) * cr)), C_RED, Enum.Material.SmoothPlastic)
	end

	-- ---------- TWO LAUNCH COUCHES ----------
	-- Reclined, side by side, facing the window. A rocket seat lies you on your back with the thrust pushing
	-- you into it, and that reads instantly -- an upright chair facing a window is a waiting room.
	--
	-- Only the LEFT couch is a real Seat; the right is furniture. A rider is alone on their own capsule (it
	-- is client-built), so a second sittable chair would only be a way to end up in the wrong one.
	-- Thirty degrees rather than thirty-four. The couch has to be BOTH a believable launch seat and a thing
	-- you can reliably walk into and land on -- past about thirty the pad is steep enough that you slide off
	-- the front instead of sitting, which is most of why sitting felt unreliable.
	local RECLINE = math.rad(30)

	local function couch(px)
		local base = CFrame.new(origin + Vector3.new(px, 2.2, 3.2)) * CFrame.Angles(RECLINE, 0, 0)

		-- ONE couch. Not one usable couch beside a decorative one -- one, in the middle, on the centreline
		-- of the window and under the overhead panel. A single rider flies this capsule, so a matched pair
		-- was set dressing that made the room ask a question it had no reason to ask, and left the seat you
		-- actually use sitting off to one side of everything aimed at it.
		local pad = Instance.new("Seat")
		pad.Name = "RocketCouchSeat"
		pad.Size = Vector3.new(3.4, 0.8, 4.2)
		pad.Color = C_SEAT
		pad.Material = Enum.Material.SmoothPlastic
		pad.Anchored = true
		pad.CanCollide = true
		-- CanTouch MUST stay on. part() switches it off for everything in the shell, and a Seat that cannot
		-- be touched cannot seat anybody -- walking into it would simply do nothing.
		pad.CanTouch = true
		pad.CanQuery = false
		pad.TopSurface = Enum.SurfaceType.Smooth
		pad.BottomSurface = Enum.SurfaceType.Smooth
		pad.CFrame = base
		pad.Parent = deck
		seatPart = pad

		-- TOUCH IT AND YOU ARE IN IT.
		--
		-- A Seat does seat you on contact by itself, but only on a fairly exact hit: the character has to
		-- touch the pad specifically, and the pad is a reclined slab behind an arm rail, so brushing past
		-- the couch does nothing and it feels broken. This is a generous invisible volume around the whole
		-- couch that does the seating instead -- get near enough to be climbing into it and you are in it,
		-- which is what "walk over and sit down" should mean.
		local grab = Instance.new("Part")
		grab.Name = "SitTrigger"
		grab.Size = Vector3.new(4.6, 5.4, 5.6)
		grab.CFrame = base * CFrame.new(0, 1.1, 0)
		grab.Anchored = true
		grab.CanCollide = false       -- never block the approach it exists to reward
		grab.CanQuery = false
		grab.CanTouch = true
		grab.Transparency = 1
		grab.Parent = deck

		local sitting = false
		grab.Touched:Connect(function(hit)
			-- Touched fires many times a second while a character rests against it, and Sit() on an
			-- already-seated humanoid fights the weld it just made. One guard covers both.
			if sitting or not inside then return end
			local ch = hit and hit.Parent
			if not ch or ch ~= player.Character then return end
			local h = ch:FindFirstChildOfClass("Humanoid")
			if not (h and h.Health > 0) or h.Sit then return end
			sitting = true
			pcall(function() pad:Sit(h) end)
			task.delay(1, function() sitting = false end)
		end)

		-- WALKING BACK IN HAS TO WORK TOO.
		--
		-- Touched only fires on NEW contact. A rider who jumps out of the couch is left STANDING INSIDE this
		-- trigger volume, so no new touch is ever generated -- and the seat they are standing in the middle
		-- of quietly refuses to take them back. That is the "I can't sit down again" case, and the touch
		-- handler above structurally cannot fix it.
		--
		-- A slow poll covers it. The 2s of continuous standing is what keeps getting up a thing you can
		-- actually DO -- stand, stretch, read the breaker panel -- instead of being yanked back down the
		-- instant you release jump.
		local stoodSince = nil
		task.spawn(function()
			while true do
				task.wait(0.4)
				local ch  = player.Character
				local h   = ch and ch:FindFirstChildOfClass("Humanoid")
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				if not (inside and pad.Parent and h and hrp and h.Health > 0) or h.Sit then
					stoodSince = nil
				else
					stoodSince = stoodSince or os.clock()
					-- Range-gated: someone who walked to the far side of the capsule on purpose is left
					-- alone. This only rescues a player standing where the couch is.
					if (os.clock() - stoodSince) >= 2 and (hrp.Position - pad.Position).Magnitude <= 6 then
						pcall(function() pad:Sit(h) end)
						stoodSince = nil
					end
				end
			end
		end)

		-- Everything below hangs off the couch's OWN frame, so it stays glued at any recline angle instead
		-- of each piece needing its own trigonometry.

		-- CUSHIONING. Three quilted rows on the pad and four up the back. A single slab reads as a painted
		-- box; segmenting it is the cheapest possible way to say "this is upholstered".
		for i = -1, 1 do
			prop("PadQuilt", Vector3.new(2.9, 0.22, 1.15), base * CFrame.new(0, 0.5, i * 1.35),
				C_SEAT_D, Enum.Material.SmoothPlastic)
		end
		prop("CouchBack", Vector3.new(3.2, 4.2, 0.7), base * CFrame.new(0, 1.8, 1.9), C_SEAT_D,
			Enum.Material.SmoothPlastic)
		for i = 0, 3 do
			prop("BackQuilt", Vector3.new(2.8, 0.85, 0.22), base * CFrame.new(0, 0.5 + i * 0.95, 1.55),
				C_SEAT, Enum.Material.SmoothPlastic)
		end

		-- HEADREST with side wings -- the detail that makes it a crew couch and not an armchair.
		prop("CouchHead", Vector3.new(2, 1.3, 0.9), base * CFrame.new(0, 4, 1.8), C_SEAT_D,
			Enum.Material.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			prop("HeadWing", Vector3.new(0.45, 1.2, 1.15), base * CFrame.new(sx * 1.1, 3.9, 1.55), C_SEAT,
				Enum.Material.SmoothPlastic)
			prop("CouchArm", Vector3.new(0.45, 1.4, 3.4), base * CFrame.new(sx * 1.6, 0.95, 0.2), C_SEAT_D,
				Enum.Material.SmoothPlastic)
			prop("ArmPad", Vector3.new(0.5, 0.2, 2.6), base * CFrame.new(sx * 1.6, 1.68, 0.1), C_SEAT,
				Enum.Material.SmoothPlastic)
		end

		-- FIVE-POINT HARNESS: two shoulder straps, two lap straps, one crotch strap, all meeting at the
		-- buckle. Four-point is a fairground ride; five is what actually holds a person through 3g.
		for _, sx in ipairs({ -1, 1 }) do
			prop("ShoulderStrap", Vector3.new(0.34, 3.4, 0.24),
				base * CFrame.new(sx * 0.8, 2.1, 1.42) * CFrame.Angles(0, 0, math.rad(sx * 13)),
				C_STRAP, Enum.Material.SmoothPlastic)
			prop("LapStrap", Vector3.new(1.5, 0.3, 0.26),
				base * CFrame.new(sx * 0.95, 0.72, 0.55) * CFrame.Angles(0, 0, math.rad(sx * -8)),
				C_STRAP, Enum.Material.SmoothPlastic)
			prop("StrapAnchor", Vector3.new(0.3, 0.3, 0.3), base * CFrame.new(sx * 1.5, 0.62, 0.5),
				C_RIB, Enum.Material.Metal)
		end
		prop("CrotchStrap", Vector3.new(0.3, 0.28, 1.1), base * CFrame.new(0, 0.66, -0.1), C_STRAP,
			Enum.Material.SmoothPlastic)
		prop("CouchBuckle", Vector3.new(0.8, 0.7, 0.4), base * CFrame.new(0, 0.85, 0.62), C_STRIPE,
			Enum.Material.SmoothPlastic)

		-- FRAME. Rails under the pad and a strut behind the back, so the couch is mounted to the deck
		-- rather than hovering in front of it.
		for _, sx in ipairs({ -1, 1 }) do
			prop("SeatRail", Vector3.new(0.28, 0.28, 3.8), base * CFrame.new(sx * 1.4, -0.5, 0.1), C_RIB)
			prop("SeatLeg", Vector3.new(0.26, 2.1, 0.26),
				CFrame.new(origin + Vector3.new(px + sx * 1.4, 1.05, 3.9)), C_RIB)
			prop("ReclineStrut", Vector3.new(0.22, 2.6, 0.22),
				base * CFrame.new(sx * 1.5, 1.2, 2.35) * CFrame.Angles(math.rad(-18), 0, 0), C_RIB)
		end
		prop("Footrest", Vector3.new(3.0, 0.3, 1.2),
			base * CFrame.new(0, -0.1, -2.4) * CFrame.Angles(math.rad(-22), 0, 0), C_RIB)
	end
	couch(0)    -- dead centre, facing the window

	-- ---------- THE REST OF THE CAPSULE ----------
	-- A conduit hoop just under the ceiling. One part, and it traces the curve the whole way round -- the
	-- single cheapest thing in here for making the room read as round.
	for i = 1, WALL_SEG do
		local a1 = (i - 1) * segArc
		local hr = DECK_R - 1.2
		local at = CFrame.new(origin + Vector3.new(math.cos(a1) * hr, DECK_H - 2, math.sin(a1) * hr))
			* CFrame.Angles(0, -a1 + math.pi / 2, 0)
		prop("Conduit_" .. i, Vector3.new(segW, 0.7, 0.7), at, C_RIB)
		prop("ConduitB_" .. i, Vector3.new(segW, 0.4, 0.4), at * CFrame.new(0, -0.55, -0.1), C_AMBER, Enum.Material.SmoothPlastic)
	end

	-- Ceiling lamp cluster: the capsule's actual light, in the middle where a capsule's light would be.
	-- Size.X is the cylinder's THICKNESS and Size.Y/Z its diameter, so those two must match or the lamp
	-- comes out an ellipse. The Z rotation is what stands the axis upright.
	local dome = prop("CeilDome", Vector3.new(0.6, 3.4, 3.4),
		CFrame.new(origin + Vector3.new(0, DECK_H - 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(226, 240, 255), Enum.Material.Neon)
	dome.Shape = Enum.PartType.Cylinder
	light(dome, Color3.fromRGB(200, 226, 255), 1.8, 26)

	-- Lockers behind the couches, on the back arc. Gives the capsule a back as well as a front.
	for k = -1, 1 do
		local ang = (math.pi / 2) + k * segArc * 1.4
		local lr = DECK_R - 1.6
		prop("Locker_" .. k, Vector3.new(3, 4.4, 1.3),
			CFrame.new(origin + Vector3.new(math.cos(ang) * lr, 3.1, math.sin(ang) * lr))
				* CFrame.Angles(0, -ang + math.pi / 2, 0), C_HULL_D)
		prop("LockerHandle_" .. k, Vector3.new(1.4, 0.25, 0.25),
			CFrame.new(origin + Vector3.new(math.cos(ang) * (lr - 0.8), 3.1, math.sin(ang) * (lr - 0.8)))
				* CFrame.Angles(0, -ang + math.pi / 2, 0), C_RIB)
	end

	-- Alert bulbs either side of the window. Dark on the pad, pulsing red once the engines light -- the
	-- capsule's own way of saying the launch has started, without a line of text.
	for _, sk in ipairs({ -3.2, 3.2 }) do
		local ang = FWD + sk * segArc * 0.9
		local br = DECK_R - 1.4
		local bulb = prop("AlertLamp", Vector3.new(0.9, 0.9, 0.9),
			CFrame.new(origin + Vector3.new(math.cos(ang) * br, DECK_H - 4, math.sin(ang) * br)), C_RED, Enum.Material.Neon)
		bulb.Shape = Enum.PartType.Ball
		bulb.Transparency = 0.6
		alertLights[#alertLights + 1] = { part = bulb, light = light(bulb, C_RED, 0, 14) }
	end

	-- ---------- FLOOR GRATING ----------
	-- Radial bars over the deck plate. A capsule floor is a grate you can see the machinery through, and the
	-- radial run does double duty: it points at the middle of the room, which is where the couches face.
	for i = 1, WALL_SEG do
		local a1 = (i - 1) * segArc + segArc / 2
		prop("Grate_" .. i, Vector3.new(DECK_R - 1.4, 0.22, 0.45),
			CFrame.new(origin + Vector3.new(math.cos(a1) * (DECK_R - 1) / 2, 0.9, math.sin(a1) * (DECK_R - 1) / 2))
				* CFrame.Angles(0, -a1, 0), C_HULL_D, Enum.Material.DiamondPlate)
	end

	-- ---------- THRUST LINE ----------
	-- A strip of neon around the base of the wall, dim on the pad and blazing under thrust. It is the engine
	-- talking: light coming UP from the floor is what a rocket firing under you would actually look like, and
	-- it lights the couches from below, which no ceiling lamp can do.
	for i = 1, WALL_SEG do
		local a1 = (i - 1) * segArc
		local strip = prop("ThrustLine_" .. i, Vector3.new(segW, 0.4, 0.4),
			CFrame.new(origin + Vector3.new(math.cos(a1) * (DECK_R - 0.9), 1.35, math.sin(a1) * (DECK_R - 0.9)))
				* CFrame.Angles(0, -a1 + math.pi / 2, 0), Color3.fromRGB(255, 120, 40), Enum.Material.Neon)
		strip.Transparency = 0.55
		thrustGlow[#thrustGlow + 1] = { part = strip, light = (i % 4 == 1) and light(strip, Color3.fromRGB(255, 130, 50), 0, 14) or nil }
	end

	-- ---------- WHAT MAKES IT READ AS BUILT ----------
	-- Everything above is the SHAPE of a capsule. This block is the evidence that somebody assembled it:
	-- fasteners, labelling, plumbing and handholds. None of it is structural and none of it is expensive --
	-- but a hull with no rivets and no writing on it is a set, and a hull with both is a machine.

	-- RIVET SEAMS. Two rings of fasteners along the panel joins. Individually invisible; together they are
	-- the single strongest "this is sheet metal bolted to a frame" cue available.
	for i = 1, WALL_SEG do
		local a1 = (i - 1) * segArc
		for _, ry in ipairs({ 3.1, DECK_H - 3.1 }) do
			for k = -1, 1 do
				local aa = a1 + k * (segArc * 0.3)
				local rv = prop("Rivet", Vector3.new(0.22, 0.22, 0.22),
					CFrame.new(origin + Vector3.new(math.cos(aa) * (DECK_R - 0.52), ry, math.sin(aa) * (DECK_R - 0.52))),
					C_RIB, Enum.Material.Metal)
				rv.Shape = Enum.PartType.Ball
			end
		end
	end

	-- PLACARDS. Real spacecraft are covered in small printed labels, and reading one is what tells you the
	-- room was designed for a job rather than decorated for a look. Kept to five so they stay worth reading.
	local function placard(angle, y, title, sub, tint)
		local pos = origin + Vector3.new(math.cos(angle) * (DECK_R - 0.62), y, math.sin(angle) * (DECK_R - 0.62))
		local cf  = CFrame.lookAt(pos, Vector3.new(origin.X, y, origin.Z))
		local pl  = prop("Placard", Vector3.new(2.6, 1.1, 0.12), cf, C_PANEL, Enum.Material.SmoothPlastic)
		local sg  = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front          -- lookAt points -Z at the room, and Front IS -Z
		sg.CanvasSize = Vector2.new(260, 110)
		sg.LightInfluence = 0
		sg.Parent = pl
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, -8, 0, 58); t.Position = UDim2.new(0, 4, 0, 6)
		t.Font = Enum.Font.GothamBold; t.TextScaled = true
		t.TextColor3 = tint or C_STRIPE; t.Text = title
		t.Parent = sg
		local u = Instance.new("TextLabel")
		u.BackgroundTransparency = 1
		u.Size = UDim2.new(1, -8, 0, 38); u.Position = UDim2.new(0, 4, 0, 64)
		u.Font = Enum.Font.Gotham; u.TextScaled = true
		u.TextColor3 = Color3.fromRGB(168, 178, 196); u.Text = sub
		u.Parent = sg
	end
	placard(segArc * 3,  6.2, "O2 SUPPLY",  "MAIN / RESERVE")
	placard(segArc * 5,  5.4, "CAUTION",    "PRESSURIZED HULL", C_RED)
	placard(segArc * 11, 5.4, "EGRESS",     "PULL RED HANDLE",  C_RED)
	placard(segArc * 13, 6.2, "MAIN BUS A", "28V DC")
	placard(segArc * 8,  4.6, "COOLANT",    "LOOP 1 NOMINAL",   C_CYAN)

	-- PLUMBING. Two hose runs down the wall between the ribs, each with collars where it clamps. A wall
	-- with pipes on it has a behind; a bare wall is the edge of the world.
	for _, ha in ipairs({ segArc * 4.5, segArc * 12.5 }) do
		local hr = DECK_R - 0.9
		local hx, hz = math.cos(ha) * hr, math.sin(ha) * hr
		prop("Hose", Vector3.new(0.34, DECK_H - 5, 0.34),
			CFrame.new(origin + Vector3.new(hx, DECK_H / 2 - 0.6, hz)), Color3.fromRGB(64, 68, 80))
		for k = 0, 3 do
			prop("HoseCollar", Vector3.new(0.5, 0.24, 0.5),
				CFrame.new(origin + Vector3.new(hx, 2.4 + k * 2.8, hz)), C_RIB)
		end
	end

	-- HANDHOLDS either side of the viewport. Zero-g furniture, and the thing that tells you which way you
	-- are meant to face when you come through the room.
	for _, sx in ipairs({ -1, 1 }) do
		local hx = sx * 5.2
		prop("GrabRail", Vector3.new(0.28, 3.2, 0.28),
			CFrame.new(origin + Vector3.new(hx, 5.6, -(DECK_R - 1.5))), Color3.fromRGB(210, 178, 60))
		for _, gy in ipairs({ 4.2, 7 }) do
			prop("GrabMount", Vector3.new(0.24, 0.24, 0.9),
				CFrame.new(origin + Vector3.new(hx, gy, -(DECK_R - 1.05))), C_RIB)
		end
	end

	-- GAUGES on the console lip. Round dials among the flat screens -- the mix is what stops the panel
	-- looking like one texture repeated.
	for k = -2, 2 do
		local ga = math.rad(-90) + k * math.rad(11)
		local gr = DECK_R - 3.1
		local gx, gz = math.cos(ga) * gr, math.sin(ga) * gr
		local ring = prop("GaugeRing", Vector3.new(0.16, 0.78, 0.78),
			CFrame.new(origin + Vector3.new(gx, 3.55, gz)) * CFrame.Angles(0, -ga, 0)
				* CFrame.Angles(0, 0, math.rad(90)), C_RIB)
		ring.Shape = Enum.PartType.Cylinder
		local dial = prop("GaugeFace", Vector3.new(0.1, 0.6, 0.6),
			CFrame.new(origin + Vector3.new(gx * 0.985, 3.55, gz * 0.985)) * CFrame.Angles(0, -ga, 0)
				* CFrame.Angles(0, 0, math.rad(90)),
			({ C_GREEN, C_AMBER, C_CYAN, C_AMBER, C_GREEN })[k + 3], Enum.Material.Neon)
		dial.Shape = Enum.PartType.Cylinder

		-- ---------- NEEDLES ----------
		-- Five lit discs with nothing moving on them are five lamps, not five instruments. A needle is the
		-- difference: a dial only reads as MEASURING SOMETHING once there is a pointer that disagrees with
		-- where it was a second ago.
		--
		-- The needle is pushed a little further off the wall than the face (0.965 vs 0.985) so it stands
		-- proud of the disc instead of z-fighting it, and it pivots about the face's own normal -- the dial
		-- is a Cylinder, so its circular face is spanned by local Y/Z and rotating about local X sweeps the
		-- pointer around the dial exactly as if it were pinned at the centre.
		local nBase = CFrame.new(origin + Vector3.new(gx * 0.965, 3.55, gz * 0.965))
			* CFrame.Angles(0, -ga, 0) * CFrame.Angles(0, 0, math.rad(90))
		local needle = prop("GaugeNeedle", Vector3.new(0.05, 0.34, 0.05), nBase,
			Color3.fromRGB(28, 30, 38), Enum.Material.SmoothPlastic)
		gauges[#gauges + 1] = {
			part = needle,
			base = nBase,
			-- Each dial is measuring a DIFFERENT thing, so each gets its own idle drift rate, its own
			-- resting angle and its own travel. Five needles moving together is a windscreen wiper.
			rate = 0.7 + k * 0.31,
			restA = math.rad(-55 + k * 9),
			fullA = math.rad(48 + k * 13),
			phase = k * 1.7,
		}
	end

	-- ---------- THE HATCH ----------
	-- The room needs a WAY IN. Every other cue in here says "sealed vessel", and a sealed vessel with no
	-- door is a diorama -- the eye goes looking for the entrance and finds a blank wall behind the couches.
	-- It never opens and it never needs to; boarding is a fade. It just has to exist, and be the kind of
	-- door that could hold pressure: recessed, ringed with dogging lugs, and wearing its own warning.
	do
		local ha  = math.pi / 2                                  -- dead astern, behind the couches
		local hx, hz = math.cos(ha) * (DECK_R - 0.5), math.sin(ha) * (DECK_R - 0.5)
		local hpos = origin + Vector3.new(hx, 4.4, hz)
		local hcf  = CFrame.lookAt(hpos, Vector3.new(origin.X, 4.4, origin.Z))

		prop("HatchFrame", Vector3.new(7.2, 7.2, 0.5), hcf, C_HULL_D, Enum.Material.Metal)
		prop("HatchDoor",  Vector3.new(6.2, 6.2, 0.35), hcf * CFrame.new(0, 0, 0.2), C_HULL)
		-- Eight dogging lugs around the rim. Eight is the count that reads as "clamped shut" -- four looks
		-- like a picture frame, sixteen looks like a gear.
		for k = 0, 7 do
			local ang = k * (math.pi / 4)
			prop("HatchLug", Vector3.new(0.5, 0.9, 0.4),
				hcf * CFrame.new(math.cos(ang) * 2.9, math.sin(ang) * 2.9, 0.3) * CFrame.Angles(0, 0, ang),
				C_RIB, Enum.Material.Metal)
		end
		-- The wheel: a hub, four spokes, and a rim built from short chords. A ring is the one shape Roblox
		-- has no primitive for, so it gets faked the same way the capsule wall does -- from segments.
		prop("HatchHub", Vector3.new(0.9, 0.9, 0.45), hcf * CFrame.new(0, 0, 0.45), C_STRIPE)
		for k = 0, 3 do
			prop("HatchSpoke", Vector3.new(0.3, 3.0, 0.3),
				hcf * CFrame.new(0, 0, 0.45) * CFrame.Angles(0, 0, k * (math.pi / 4)), C_STRIPE)
		end
		for k = 0, 11 do
			local a0 = k * (math.pi / 6)
			prop("HatchRim", Vector3.new(0.85, 0.28, 0.3),
				hcf * CFrame.new(math.cos(a0) * 1.55, math.sin(a0) * 1.55, 0.45)
					* CFrame.Angles(0, 0, a0 + math.pi / 2), C_STRIPE)
		end
		-- A porthole in the door, so the hatch has a beyond instead of being a plate.
		local port = prop("HatchPort", Vector3.new(1.5, 1.5, 0.2), hcf * CFrame.new(0, 2.05, 0.4),
			Color3.fromRGB(12, 18, 30), Enum.Material.Glass)
		port.Shape = Enum.PartType.Cylinder
		port.Transparency = 0.35
		port.CFrame = hcf * CFrame.new(0, 2.05, 0.4) * CFrame.Angles(0, math.rad(90), 0)

		prop("HatchStripeL", Vector3.new(0.5, 6.4, 0.16), hcf * CFrame.new(-3.5, 0, 0.1), C_STRIPE,
			Enum.Material.SmoothPlastic)
		prop("HatchStripeR", Vector3.new(0.5, 6.4, 0.16), hcf * CFrame.new( 3.5, 0, 0.1), C_STRIPE,
			Enum.Material.SmoothPlastic)
	end

	-- ---------- CEILING STRUCTURE ----------
	-- Ribs run up the WALLS already, and they used to stop dead at the ceiling -- which is exactly where a
	-- real pressure vessel carries its load across. Eight spars close that gap, and the roof stops being a
	-- lid and becomes the top of a frame.
	for k = 0, 7 do
		local ang = k * (math.pi / 4)
		prop("CeilSpar", Vector3.new(0.4, 0.35, DECK_R - 1),
			CFrame.new(origin + Vector3.new(math.cos(ang) * (DECK_R - 1) / 2, DECK_H - 0.55,
				math.sin(ang) * (DECK_R - 1) / 2)) * CFrame.Angles(0, -ang, 0), C_RIB)
	end
	prop("CeilBoss", Vector3.new(2.2, 0.5, 2.2), CFrame.new(origin + Vector3.new(0, DECK_H - 0.6, 0)), C_HULL_D)
	-- Air ducting following the ceiling edge, with grilles blowing down over the couches.
	for k = 0, 5 do
		local ang = k * (math.pi / 3)
		prop("Duct", Vector3.new(1.6, 0.7, 0.7),
			CFrame.new(origin + Vector3.new(math.cos(ang) * (DECK_R - 2.6), DECK_H - 1.5,
				math.sin(ang) * (DECK_R - 2.6))) * CFrame.Angles(0, -ang + math.pi / 2, 0),
			Color3.fromRGB(70, 75, 88))
	end

	-- ---------- FLOOR ----------
	-- An inspection hatch dead centre with its bolt circle and a painted keep-clear ring. Floors read as
	-- floors when they have something in them you are meant to walk around.
	local insp = prop("InspectionHatch", Vector3.new(3.4, 0.12, 3.4),
		CFrame.new(origin + Vector3.new(0, 1.02, 0)), Color3.fromRGB(48, 52, 63), Enum.Material.DiamondPlate)
	insp.Shape = Enum.PartType.Cylinder
	insp.CFrame = CFrame.new(origin + Vector3.new(0, 1.02, 0)) * CFrame.Angles(0, 0, math.rad(90))
	for k = 0, 9 do
		local ang = k * (math.pi / 5)
		prop("InspBolt", Vector3.new(0.2, 0.16, 0.2),
			CFrame.new(origin + Vector3.new(math.cos(ang) * 1.5, 1.06, math.sin(ang) * 1.5)), C_RIB)
	end
	for k = 0, 23 do
		local ang = k * (math.pi / 12)
		prop("KeepClear", Vector3.new(0.55, 0.1, 0.3),
			CFrame.new(origin + Vector3.new(math.cos(ang) * 2.5, 1.01, math.sin(ang) * 2.5))
				* CFrame.Angles(0, -ang, 0),
			(k % 2 == 0) and C_STRIPE or C_HULL_D, Enum.Material.SmoothPlastic)
	end

	-- ---------- LIGHTING ----------
	-- The biggest single lever in here, and the one that was doing the least. One lamp in the middle of a
	-- ceiling flattens everything under it; what a cabin actually looks like is a few sources doing
	-- different jobs -- a cold wash from the floor, warm pools over the seats, and the window colder than
	-- both so the eye is pulled to it.
	--
	-- Deliberately few. Roblox culls past a handful of lights per area, so scattering a dozen means the
	-- ones that matter start switching themselves off at exactly the wrong moment.
	for k = 0, 5 do
		local ang = k * (math.pi / 3) + math.pi / 6
		local cove = prop("CoveStrip", Vector3.new(2.4, 0.18, 0.22),
			CFrame.new(origin + Vector3.new(math.cos(ang) * (DECK_R - 0.75), 1.55,
				math.sin(ang) * (DECK_R - 0.75))) * CFrame.Angles(0, -ang + math.pi / 2, 0),
			Color3.fromRGB(150, 200, 240), Enum.Material.Neon)
		cove.Transparency = 0.25
	end

	do
		local can = prop("CouchLamp", Vector3.new(1.8, 0.45, 1.8),
			CFrame.new(origin + Vector3.new(0, DECK_H - 1.35, 3.2)), C_HULL_D)
		prop("CouchLampLens", Vector3.new(1.45, 0.14, 1.45),
			CFrame.new(origin + Vector3.new(0, DECK_H - 1.62, 3.2)),
			Color3.fromRGB(255, 236, 200), Enum.Material.Neon)
		local sl = Instance.new("SpotLight")
		sl.Face = Enum.NormalId.Bottom      -- a SpotLight defaults to Front; pointed at the wall it lights nothing
		sl.Color = Color3.fromRGB(255, 226, 186)
		sl.Angle = 78; sl.Brightness = 2.4; sl.Range = 22
		sl.Parent = can
	end

	-- ---------- OVERHEAD SWITCH PANEL ----------
	-- Angled down over the couches, the way a real capsule puts its breakers where a strapped-in crew can
	-- still reach them. It is also the thing that closes the space above your head, so lying back looks at
	-- instruments rather than at nothing.
	do
		local at = CFrame.new(origin + Vector3.new(0, DECK_H - 3.4, 2.6)) * CFrame.Angles(math.rad(28), 0, 0)
		prop("OverheadPanel", Vector3.new(7.4, 0.5, 3.2), at, C_PANEL)
		prop("OverheadTrim", Vector3.new(7.8, 0.3, 0.4), at * CFrame.new(0, -0.1, -1.7), C_RIB)
		for row = -1, 1 do
			for col = -3, 3 do
				prop("Breaker_" .. row .. "_" .. col, Vector3.new(0.34, 0.2, 0.34),
					at * CFrame.new(col * 1, -0.32, row * 0.9),
					({ C_GREEN, C_AMBER, C_RED })[((col + row + 6) % 3) + 1], Enum.Material.Neon)
			end
		end
		local ohs = prop("OverheadScreen", Vector3.new(2.6, 0.16, 1),
			at * CFrame.new(0, -0.34, -1.05), C_CYAN, Enum.Material.Neon)
		screens[#screens + 1] = ohs
	end

	-- ---------- MISSION CLOCK ----------
	-- Over the middle of the console, reading the SAME countdown the whole island can hear. A rider who can
	-- see the number knows the launch is coming; without it, liftoff is something that just happens to them.
	do
		local post = prop("ClockPost", Vector3.new(0.3, 1.4, 0.3),
			CFrame.new(origin + Vector3.new(0, 4.6, -(DECK_R - 3.4))), C_RIB)
		local bb = Instance.new("BillboardGui")
		bb.Name = "MissionClock"
		bb.Size = UDim2.new(0, 150, 0, 46)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 1, 0)
		bb.AlwaysOnTop = false
		bb.Parent = post
		local card = Instance.new("Frame")
		card.Size = UDim2.fromScale(1, 1); card.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
		card.BorderSizePixel = 0; card.Parent = bb
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 6); cc.Parent = card
		local cs = Instance.new("UIStroke"); cs.Color = C_CYAN; cs.Thickness = 2; cs.Parent = card
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1, -8, 1, -6); lbl.Position = UDim2.new(0, 4, 0, 3)
		lbl.Font = Enum.Font.FredokaOne; lbl.TextScaled = true
		lbl.TextColor3 = C_CYAN; lbl.Text = "T-  --"
		lbl.Parent = card
		missionClock = lbl
	end

	-- ---------- HANDRAIL ----------
	-- Chest height, and now unbroken the whole way round. A rail is the prop that tells you a
	-- room is meant to be moved in -- it says "hold on", which is exactly what this room is for.
	for i = 1, WALL_SEG do
		local a1 = (i - 1 - 4) * segArc + FWD
		prop("Rail_" .. i, Vector3.new(segW - 0.6, 0.28, 0.28),
			CFrame.new(origin + Vector3.new(math.cos(a1) * (DECK_R - 1.1), 4.4, math.sin(a1) * (DECK_R - 1.1)))
				* CFrame.Angles(0, -a1 + math.pi / 2, 0), C_RIB)
	end

	-- ---------- VENTS ----------
	-- Four jets at the floor line that blow on liftoff. Nothing in a sealed room moves on its own, and a
	-- room where nothing moves reads as a diorama however well it is dressed -- this is the cheapest
	-- possible motion, and it happens exactly when the thrust does.
	for k = 1, 4 do
		local a1 = (k - 1) * (math.pi / 2) + math.pi / 4
		local vent = prop("Vent_" .. k, Vector3.new(1.2, 0.6, 0.6),
			CFrame.new(origin + Vector3.new(math.cos(a1) * (DECK_R - 1.6), 1.8, math.sin(a1) * (DECK_R - 1.6)))
				* CFrame.Angles(0, -a1 + math.pi / 2, 0), C_HULL_D)
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(226, 234, 246))
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new(1.6)
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Speed = NumberRange.new(6, 10)
		e.Rate = 0
		e.SpreadAngle = Vector2.new(18, 18)
		e.Parent = vent
		steamJets[#steamJets + 1] = e
	end

	-- ---------- DUST IN THE LAMPLIGHT ----------
	-- The one thing a sealed metal room cannot get from geometry is AIR. However well a box is dressed, if
	-- the space between the props is empty it reads as a diorama you are looking at rather than a volume you
	-- are inside. A slow drift of motes fixes that for the price of a single emitter: they cross in front of
	-- the couches and behind the console, and suddenly there is depth between the two.
	--
	-- Deliberately NOT parented to a lamp. Motes belong to the room, not to a fixture -- hanging them off a
	-- lamp makes a visible cone of glitter, which is a completely different (and much cheaper-looking) effect.
	-- This sits at head height in the middle of the cabin and fills the whole volume.
	do
		local air = prop("CabinAir", Vector3.new(0.2, 0.2, 0.2),
			CFrame.new(origin + Vector3.new(0, 5.5, 0)), C_HULL)
		air.Transparency = 1
		local m = Instance.new("ParticleEmitter")
		m.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		m.Color = ColorSequence.new(Color3.fromRGB(255, 246, 224))
		-- Never fully opaque at any point in life: a mote that reaches transparency 0 is a firefly. These
		-- have to sit just at the edge of visible, so you register the movement rather than the particles.
		m.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.82),
			NumberSequenceKeypoint.new(0.75, 0.86), NumberSequenceKeypoint.new(1, 1) })
		m.Size = NumberSequence.new(0.09)
		m.Lifetime = NumberRange.new(5, 9)
		m.Rate = 14
		m.Speed = NumberRange.new(0.15, 0.5)     -- barely moving: dust falls, it does not fly
		m.SpreadAngle = Vector2.new(180, 180)    -- fill the room, no directional jet
		m.Acceleration = Vector3.new(0, -0.08, 0) -- the faintest settle, so it drifts DOWN on the pad
		m.EmissionDirection = Enum.NormalId.Top
		m.Shape = Enum.ParticleEmitterShape.Box
		m.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		m.Size = NumberSequence.new(0.09)
		m.LightInfluence = 1                      -- lit BY the cabin lamps, so it goes where the light goes
		m.Parent = air
		cabinDust = m
	end

	-- ---------- LOOSE GEAR (the zero-G payoff) ----------
	-- THIS IS THE ANSWER TO HAVING NO WINDOW. The capsule is sealed on purpose (see the header), which means
	-- the rider has no way to see that they left the ground -- the shake and the noise say the engine is
	-- running, but a shaking room is also just a shaking room. Something FLOATING is the only unambiguous
	-- proof, and it needs no view of anything.
	--
	-- Three ordinary objects, resting on the console ledge on the pad, chosen because they are instantly
	-- readable in silhouette at small size: a clipboard, a pen, a mug. Nothing sci-fi. The joke -- and the
	-- reason a mug is in there -- is that somebody left their coffee out and is now regretting it.
	--
	-- They are NORMAL props, which means the shake loop captures them and rattles them on the pad exactly
	-- like everything else that is bolted down. The drift block in the ride loop then OVERWRITES their CFrame
	-- once flying is true -- it runs after the shake write in the same frame, so the float wins.
	do
		local ledgeY = 4.9                        -- roughly the console shelf height
		local gear = {
			{ n = "Clipboard", s = Vector3.new(0.9, 0.1, 1.2), c = Color3.fromRGB(214, 176, 110),
			  m = Enum.Material.WoodPlanks, o = Vector3.new(-1.9, ledgeY, -5.6) },
			{ n = "Pen",       s = Vector3.new(0.12, 0.12, 0.7), c = C_CYAN,
			  m = Enum.Material.SmoothPlastic, o = Vector3.new(-1.2, ledgeY, -5.9) },
			{ n = "Mug",       s = Vector3.new(0.55, 0.7, 0.55), c = Color3.fromRGB(238, 238, 244),
			  m = Enum.Material.SmoothPlastic, o = Vector3.new(2.1, ledgeY + 0.3, -5.5) },
		}
		for i, g in ipairs(gear) do
			local rest = CFrame.new(origin + g.o) * CFrame.Angles(0, math.rad(i * 37), 0)
			local p = prop(g.n, g.s, rest, g.c, g.m)
			floaters[#floaters + 1] = {
				part = p,
				rest = rest,
				-- Per-object tumble axis and phase. Three objects rotating on the same axis at the same rate
				-- is a turntable; three disagreeing with each other is weightlessness.
				spin = Vector3.new(0.6 + i * 0.35, 0.9 - i * 0.2, 0.4 + i * 0.5),
				phase = i * 2.1,
				rise = 1.1 + i * 0.45,          -- how high above the ledge this one ends up hovering
			}
		end
	end

	print(("[RocketRide] capsule built at (%d, %d, %d) -- r=%d h=%d, %d loose object(s)")
		:format(origin.X, origin.Y, origin.Z, DECK_R, DECK_H, #floaters))
end

--======================================================================
-- THE RIDE LOOP
--======================================================================
local function startShake()
	if shakeConn then return end
	if not shakeBase then
		shakeBase = {}
		for _, d in ipairs(deck:GetChildren()) do
			if d:IsA("BasePart") then shakeBase[d] = d.CFrame end
		end
	end
	local base = shakeBase
	local t0 = os.clock()
	-- dt is taken from RenderStepped rather than derived from t, because the zero-G ramp below is a rate and
	-- has to run at the same speed on a 30fps phone as on a 240Hz monitor.
	shakeConn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		local amp = flying and 0.16 or 0.03
		local off = Vector3.new(
			math.sin(t * 47) * amp, math.sin(t * 61 + 1.7) * amp, math.sin(t * 53 + 0.9) * amp)
		for p, cf in pairs(base) do
			if p.Parent then p.CFrame = cf + off end
		end
		-- The alert bulbs breathe on their own clock, slower than the shake, so the two do not lock into one
		-- strobe and start looking mechanical.
		local pulse = flying and (0.5 + 0.5 * math.sin(t * 5)) or 0
		for _, a in ipairs(alertLights) do
			a.light.Brightness = 3 * pulse
			a.part.Transparency = 0.6 - 0.45 * pulse
		end

		-- THRUST LINE. Comes up hard on liftoff and then simmers, so the engine reads as lit-and-running
		-- rather than switched-on. Each strip is offset by its index, so the ring ripples instead of the
		-- whole floor blinking at once.
		for i, g in ipairs(thrustGlow) do
			local base = flying and (0.72 + 0.28 * math.sin(t * 9 + i * 0.4)) or 0.06
			g.part.Transparency = 1 - base
			if g.light then g.light.Brightness = 5 * base end
		end

		-- Instruments. Each screen breathes on its OWN frequency -- a bank of screens all fading in step is
		-- a light show, whereas screens that disagree with each other look like they are computing.
		for i, sc in ipairs(screens) do
			local f = 2.3 + i * 0.7
			sc.Transparency = 0.15 + 0.12 * (0.5 + 0.5 * math.sin(t * f + i))
		end

		-- ===== THE NEEDLES =====
		-- On the pad they idle: a small nervous drift around rest, because a system that is powered up but
		-- not doing anything still has readings that twitch. Under thrust they swing hard over toward full
		-- scale and then JITTER there -- pegged needles vibrating is what a gauge looks like when whatever
		-- it measures has gone off the top of the dial, and it says "too much of everything" without a
		-- single word of UI.
		--
		-- Written after the shake block for the same reason as the gear below: the shake has already stamped
		-- these parts back onto their rest CFrame this frame, so the pointer angle has to be applied on top.
		for _, gg in ipairs(gauges) do
			if gg.part.Parent then
				local drift = math.sin(t * gg.rate + gg.phase) * math.rad(4)
				local a
				if flying then
					-- Ease onto the stop, then buzz against it.
					a = gg.restA + (gg.fullA - gg.restA) * math.min(floatT * 1.6, 1)
						+ math.sin(t * 31 + gg.phase) * math.rad(2.4)
				else
					a = gg.restA + drift
				end
				gg.part.CFrame = (gg.base + off) * CFrame.Angles(a, 0, 0) * CFrame.new(0, 0.17, 0)
			end
		end

		-- ===== ZERO-G: THE LOOSE GEAR COMES OFF THE LEDGE =====
		-- Runs AFTER the shake write above, deliberately: the shake loop has already stamped every deck part
		-- (these included) back onto its rest CFrame this frame, so writing here is what makes a floating
		-- object float instead of being dragged back down to the shelf sixty times a second.
		--
		-- floatT ramps 0->1 over ~2.5s from the moment thrust starts. Objects do NOT snap into the air: they
		-- come UNSTUCK, which is what actually reads as gravity leaving rather than as a prop being animated.
		-- It resets to 0 when flying goes false, so a second ride starts from the shelf again.
		if flying then
			floatT = math.min(floatT + (dt or 1 / 60) / 2.5, 1)
		else
			floatT = 0
		end
		if floatT > 0 then
			-- Ease-out: quick to let go, slow to settle into the hover. A linear ramp reads mechanical.
			local e = 1 - (1 - floatT) * (1 - floatT)
			for _, f in ipairs(floaters) do
				if f.part.Parent then
					local ph = t * 0.8 + f.phase
					-- Rise to the object's own hover height, then bob gently around it. The bob amplitude is
					-- scaled by e as well, so nothing wobbles while it is still nominally sitting down.
					local up = f.rise * e + math.sin(ph) * 0.22 * e
					-- A lazy lateral wander, different frequency from the bob so the path is not an ellipse.
					local drift = Vector3.new(math.sin(ph * 0.7) * 0.35 * e, up, math.cos(ph * 0.53) * 0.3 * e)
					f.part.CFrame = (f.rest + off + drift)
						* CFrame.Angles(f.spin.X * ph * e, f.spin.Y * ph * e, f.spin.Z * ph * e)
				end
			end
		end

		-- The dust goes with them. Under thrust the settle reverses (things drift UP toward the nose) and the
		-- motes speed up, so the air in the room agrees with the objects hanging in it. On the pad it is a
		-- slow downward fall again.
		if cabinDust then
			cabinDust.Acceleration = flying and Vector3.new(0, 0.55, 0) or Vector3.new(0, -0.08, 0)
			cabinDust.Rate = flying and 26 or 14
		end
	end)
end

local function stopLoops()
	if shakeConn then
		shakeConn:Disconnect(); shakeConn = nil
		if shakeBase then
			for p, cf in pairs(shakeBase) do
				if p.Parent then p.CFrame = cf end   -- put the room back on its true CFrames
			end
		end
	end
end

--======================================================================
-- ENTER / LEAVE
--======================================================================
local function hudHold(on)
	if type(_G.hudHold) == "function" then
		pcall(_G.hudHold, "RocketRide", on)
		hudWasHidden = on
	end
end

-- GET OUT. Until now the capsule had no exit at all: once you boarded you were in there until the rocket
-- blew up or the event aborted. That is fine for the ride itself and wrong for everything around it --
-- somebody who boards early, has a look, and wants to go back to farming had no way to say so.
--
-- Built once and reused. A button created on every boarding leaks a ScreenGui per ride, and ResetOnSpawn
-- would take it away on the respawn that leaving causes -- which is exactly when it needs to still exist.
local exitGui, exitBtn
local function buildExitButton()
	if exitGui then return end
	exitGui = Instance.new("ScreenGui")
	exitGui.Name = "RocketRideExit"
	exitGui.IgnoreGuiInset = true
	exitGui.ResetOnSpawn = false
	exitGui.DisplayOrder = 60
	exitGui.Enabled = false
	exitGui.Parent = playerGui

	exitBtn = Instance.new("TextButton")
	exitBtn.Name = "ExitBtn"
	exitBtn.Size = UDim2.fromOffset(180, 56)
	-- Bottom-centre, the same corner the secret cave puts its own leave button in. A player who has learned
	-- where "get me out of here" lives should not have to learn it twice.
	exitBtn.Position = UDim2.new(0.5, -90, 1, -96)
	exitBtn.BackgroundColor3 = Color3.fromRGB(122, 62, 24)
	exitBtn.AutoButtonColor = true
	exitBtn.Font = Enum.Font.FredokaOne
	exitBtn.TextSize = 22
	exitBtn.TextColor3 = Color3.fromRGB(255, 246, 232)
	exitBtn.Text = "LEAVE ROCKET"
	exitBtn.BorderSizePixel = 0
	exitBtn.Parent = exitGui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = exitBtn
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(255, 196, 120); st.Thickness = 2.5
	st.Parent = exitBtn

	exitBtn.Activated:Connect(function()
		if not inside then return end
		-- Ask, do not act. The server owns the roster, so it has to be the thing that frees the seat -- a
		-- client that tore its own capsule down first would leave a rider on the books who is not aboard.
		exitGui.Enabled = false
		if RideEvent then RideEvent:FireServer("leave") end
	end)
end

local function enter()
	if inside or busy then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.Health > 0) then return end
	busy = true

	buildDeck()

	withFade(function()
		-- Lighting is saved as a set and put back as a set. Restoring "the ones I remember changing" is how
		-- a player ends up permanently in someone else's sunset.
		savedLighting = {
			Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
			Brightness = Lighting.Brightness, FogEnd = Lighting.FogEnd, FogColor = Lighting.FogColor,
			ClockTime = Lighting.ClockTime,
		}
		-- A SEALED CABIN, LIT AS ONE.
		--
		-- There is no window any more, so there is no outside to reconcile with -- and that makes the
		-- lighting simple again. Darkness everywhere except the capsule's own lamps is what a windowless
		-- pressure vessel looks like from the inside, and it is the whole reason the room can be parked in
		-- empty space without anybody ever being able to tell.
		Lighting.Ambient = Color3.fromRGB(24, 26, 34)
		Lighting.OutdoorAmbient = Color3.fromRGB(16, 18, 26)
		Lighting.Brightness = 0.6
		Lighting.FogColor = Color3.fromRGB(4, 5, 12)
		Lighting.FogEnd = 200
		Lighting.ClockTime = 0

		-- ZOOM CLAMP. The capsule is a sealed room parked alone in open air thousands of studs off the map,
		-- so any camera that gets outside it sees the one thing the illusion cannot survive: nothing. Empty
		-- sky, and a small grey box hanging in it.
		--
		-- Occlusion alone is not enough to prevent that. It only pushes the camera in when its ray hits a
		-- queryable part, so it is defeated by any gap in the shell -- and it does not run at all in the
		-- moment the character is being teleported in. A hard zoom ceiling is the guarantee, and 10 studs is
		-- inside every wall of an 11-radius room from anywhere a rider can stand.
		savedCam = { min = player.CameraMinZoomDistance, max = player.CameraMaxZoomDistance }
		pcall(function()
			player.CameraMinZoomDistance = 0.5
			player.CameraMaxZoomDistance = 10
		end)

		if seatPart then
			pcall(function() char:PivotTo(seatPart.CFrame * CFrame.new(0, 3, 0)) end)
			task.defer(function()
				-- Sit on the NEXT step, not this one: PivotTo has not settled the character yet and Sit on
				-- the same frame regularly drops them through the couch.
				--
				-- ===== AND THEN CHECK THAT IT ACTUALLY TOOK =====
				-- Seat:Sit() is a request, not a guarantee. It silently does nothing if the character is
				-- still mid-teleport, if the Humanoid is in a state that refuses to sit (Freefall right
				-- after the PivotTo is the common one), or if a physics step lands between the pivot and
				-- the call. Firing it once and walking away is why "I boarded and I'm standing in the
				-- middle of the room" happens -- the old code had no idea whether it had worked.
				--
				-- So: try, verify against hum.Sit, and try again. Ten attempts over ~1.5s covers every
				-- settle case without ever fighting a player who has deliberately stood up later, because
				-- the loop is bounded and stops the moment it succeeds.
				for attempt = 1, 10 do
					if not inside or hum.Health <= 0 or not seatPart or not seatPart.Parent then return end
					if hum.Sit then
						if attempt > 1 then
							print(("[RocketRide] seated on attempt %d"):format(attempt))
						end
						return
					end
					-- Re-plant on top of the couch each retry. If the first Sit failed because the
					-- character had already fallen off the pad, re-calling Sit alone would keep failing
					-- for the same reason.
					pcall(function() char:PivotTo(seatPart.CFrame * CFrame.new(0, 3, 0)) end)
					pcall(function() seatPart:Sit(hum) end)
					task.wait(0.15)
				end
				if not hum.Sit then
					warn("[RocketRide] could not seat the rider after 10 attempts -- they are aboard but standing")
				end
			end)
		end
		inside = true
		flying = false
		hudHold(true)
		buildExitButton()
		if exitGui then exitGui.Enabled = true end

		-- The clock runs itself between broadcasts. Bounded by `inside`, so every exit path stops it
		-- without anyone having to remember to.
		task.spawn(function()
			while inside do
				if missionClock and missionClock.Parent and missionEndsAt then
					local left = math.max(0, missionEndsAt - os.clock())
					if left > 0 then
						missionClock.Text = ("T- %02d:%02d"):format(math.floor(left / 60), math.floor(left % 60))
						missionClock.TextColor3 = (left <= 10) and C_RED or C_CYAN
					else
						missionClock.Text = "LIFTOFF"
						missionClock.TextColor3 = C_AMBER
					end
				end
				task.wait(0.2)
			end
		end)
		startShake()
	end)

	toast("\xF0\x9F\x9A\x80 Strapped in! Watch the window...", C_AMBER, 5)
	busy = false
end

-- THE SINGLE EXIT. Every way out of the ride ends here, so there is exactly one place that has to be right.
local function leave(silent)
	if not inside then return end
	inside = false
	flying = false
	stopLoops()
	-- Hidden here rather than at each call site, because leave() is the one place every exit funnels
	-- through -- the ending, the abort, and stepping out all land on this line.
	if exitGui then exitGui.Enabled = false end

	-- Everything the ride drives goes back to its resting state here. The loops that were animating these
	-- have just been disconnected, so whatever value they happened to stop on is whatever the capsule would
	-- be wearing next time somebody boards.
	for _, a in ipairs(alertLights) do
		a.light.Brightness = 0
		a.part.Transparency = 0.6
	end
	for _, g in ipairs(thrustGlow) do
		g.part.Transparency = 0.94
		if g.light then g.light.Brightness = 0 end
	end
	for _, e in ipairs(steamJets) do e.Rate = 0 end
	for _, sc in ipairs(screens) do sc.Transparency = 0.15 end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then pcall(function() hum.Sit = false end) end

	if savedLighting then
		for k, v in pairs(savedLighting) do pcall(function() Lighting[k] = v end) end
		savedLighting = nil
	end
	-- Max before min: setting a min above the current max is the one ordering Roblox rejects, and a rider
	-- left permanently zoomed into their own face is a far worse bug than the one this whole clamp fixes.
	if savedCam then
		pcall(function()
			player.CameraMaxZoomDistance = savedCam.max
			player.CameraMinZoomDistance = savedCam.min
		end)
		savedCam = nil
	end
	if hudWasHidden then hudHold(false) end
	if not silent then
		-- Nothing to say on the normal ending -- the server's own banner covers that. This is the abort path.
		toast("The launch was scrubbed.", C_RED, 3)
	end
end

--======================================================================
-- SERVER EVENTS
--======================================================================
RideEvent.OnClientEvent:Connect(function(kind, payload)
	if kind == "boarded" then
		local secs = tonumber(payload)
		if secs then missionEndsAt = os.clock() + secs end
		task.spawn(enter)

	elseif kind == "full" then
		toast("The rocket is full!", C_RED, 3)

	elseif kind == "liftoff" then
		-- Engines lit: the capsule shakes hard, the alert lamps come up, the thrust line blazes and the
		-- vents blow. With no window, the shake and the noise ARE the launch -- so they carry all of it.
		flying = true
		for _, e in ipairs(steamJets) do e.Rate = 24 end

		toast("\xF0\x9F\x94\xA5 LIFTOFF!", C_AMBER, 3)

	elseif kind == "stars" then
		-- The end. White-out FIRST -- the server kills the character about half a second later, and the last
		-- thing a rider should see is their own deck going up, not a death cam they were cut to.
		local gui = Instance.new("ScreenGui")
		gui.Name = "RocketRideWhiteout"; gui.IgnoreGuiInset = true
		gui.DisplayOrder = 10000; gui.ResetOnSpawn = false; gui.Parent = playerGui
		local sheet = Instance.new("Frame")
		sheet.Size = UDim2.fromScale(1, 1); sheet.BackgroundColor3 = Color3.new(1, 1, 1)
		sheet.BackgroundTransparency = 1; sheet.BorderSizePixel = 0; sheet.Parent = gui
		TweenService:Create(sheet, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
		task.delay(1.2, function()
			TweenService:Create(sheet, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
			task.delay(0.7, function() gui:Destroy() end)
		end)
		toast(("\xF0\x9F\x9A\x80 THE STARS! +%d crate tickets \xE2\x80\x94 what a way to go"):format(tonumber(payload) or 0),
			C_AMBER, 6)
		leave(true)

	elseif kind == "left" then
		-- Stepped out on purpose. The server has already freed the seat and is respawning us on our own
		-- island, so all that is left is undoing the ride's lighting and HUD -- and saying the ride is
		-- still catchable, because the whole point of allowing this is that boarding again works.
		leave(true)
		toast("You hopped out \xE2\x80\x94 walk back to the console to board again.", C_AMBER, 4)

	elseif kind == "released" then
		-- The event aborted before the ending. Nobody rode anything, so nobody is killed -- but the rider is
		-- standing in a void room only this client knows about and cannot walk out of it, so the server
		-- respawns them straight after sending this. All that is left here is undoing the ride's own state.
		leave(false)
	end
end)

-- THE MISSION CLOCK reads the event's OWN countdown broadcast, not a timer of its own. Two clocks counting
-- the same launch will always drift apart by a second somewhere, and the one on the wall disagreeing with the
-- one the whole island can hear is worse than having no clock at all.
do
	local sync = ReplicatedStorage:FindFirstChild("RocketEventSync")
	if sync then
		sync.OnClientEvent:Connect(function(phase, payload)
			if not missionClock then return end
			if phase == "countdown" then
				-- The authority. Re-seeding here is what keeps the wall clock honest: however far the local
				-- tick has drifted, every second of the real countdown snaps it straight again.
				local n = tonumber(payload) or 0
				missionEndsAt = os.clock() + n
				missionClock.Text = ("T- 00:%02d"):format(n)
				missionClock.TextColor3 = (n <= 3) and C_RED or C_CYAN
			elseif phase == "launch" then
				missionEndsAt = os.clock()
				missionClock.Text = "LIFTOFF"
				missionClock.TextColor3 = C_AMBER
			end
		end)
	end
end

-- A respawn (the ending's death, or any other) ends the ride. Without this the Lighting override and the
-- hidden HUD would follow the player back onto their island.
player.CharacterAdded:Connect(function()
	if inside then leave(true) end
	stopLoops()
end)

print("[RocketRide] flight deck ready")
