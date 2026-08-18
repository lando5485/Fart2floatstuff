--!nonstrict
-- ============================================================================================================
-- ROCKET RIDE (server module) -- the command stand, the roster, and the ending.
-- ============================================================================================================
-- The Big Rocket event was something you STOOD AND WATCHED. This makes it boardable: a launch command stand
-- appears beside the pad thirty seconds before liftoff, you hold E at it, and you ride the rocket to the stars.
--
-- WHAT THIS FILE DOES *NOT* DO: build the cabin.
--   The first version of this welded a cabin into the rocket's own body, and that was a dead end. The body
--   tube is sixteen studs across -- a character is five tall and four wide -- so "inside the rocket" was four
--   couches jammed shoulder to shoulder in a space smaller than a lift, and no amount of detailing was going
--   to fix a room that has no room in it.
--
--   So the interior moved to where it can actually be a place: RocketRideClient builds a round capsule in
--   empty space thousands of studs off the map and teleports the rider into it behind a black fade -- exactly
--   the trick the island 5 secret cave uses, for exactly the same reason. It is client-built, so it does not
--   replicate: every rider gets their own deck at their own offset, nobody can wander into anybody else's,
--   and the server carries none of it. What the server keeps is the part that has to be authoritative --
--   who is aboard, and what happens to them at the end.
--
-- HOW IT ENDS
--   You go up with it and you go out with it. The rocket reaches the stars, detonates, and every rider dies
--   in the blast -- that is the ride, and pulling people out one frame early to keep them tidy would be
--   throwing away the punchline. The game's normal death flow (PlayerStats' onCharacterAdded) respawns them
--   at their own highest island, so the cost is one respawn, and the bonus is banked BEFORE the kill so
--   dying never costs anyone the reward for riding.
--
--   The teardown path is the exception: an ABORTED event releases riders unharmed. Dying because the event
--   errored is not the joke, it is just a bug with a body count.
-- ============================================================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RocketRide = {}

-- How many PLAYERS may ride one launch. Not how many chairs are in the room -- the capsule has exactly one
-- couch, and every rider gets their own private copy of it, so this is a cap on the roster and nothing else.
-- Two people can ride the same launch and neither will ever see the other.
local RIDE_SEATS   = 2
-- Crate TOKENS for making the whole trip, not coins.
--
-- Coins are the flight economy: you earn them by altitude, every second you are in the air. Paying coins
-- for the rocket puts it in direct competition with the thing the whole game is about, and it loses --
-- 250 coins is a rounding error next to a good climb, so the reward reads as an insult while still being
-- one more coin faucet to balance. Tokens are the crate currency and nothing else in the loop hands them
-- out for free, so five of them is a real prize and it cannot inflate the climb.
local RIDE_BONUS   = 5
-- How close you must be for the E prompt to appear at all. Five studs is arm's reach: you have to walk up
-- and stand AT the console, not gesture at it from across the pad. A prompt with a wide radius pops up while
-- you are busy doing something else nearby, which trains people to ignore prompts.
local BOARD_RADIUS = 5

-- How far the overhead sign is readable. Matched to the campfire signs (MaxDistance 45) on purpose -- two
-- world signs that fade in at different ranges feel like a bug even when neither one is wrong, and 45 is
-- already the number this game has decided means "near enough to care about".
local SIGN_DISTANCE = 45

local stand      = nil   -- the ground command console (its own model, NOT welded to the rocket)
local standClock  = nil  -- the BillboardGui label counting down to liftoff
local standScreen = nil  -- the SurfaceGui readout on the console's own screen
local liftoffAt  = 0     -- os.clock() time the rocket lifts, so the sign can tick itself
local prompt     = nil
local riders   = {}    -- [player] = true, everyone who has boarded this launch
local riderN   = 0
local boarding = false

local RideEvent = ReplicatedStorage:FindFirstChild("RocketRideEvent")
if not RideEvent then
	RideEvent = Instance.new("RemoteEvent")
	RideEvent.Name = "RocketRideEvent"
	RideEvent.Parent = ReplicatedStorage
end

--------------------------------------------------------------------
-- Where the stand goes: a Studio part named "rocketplacement" (or the older "rocketstand").
--------------------------------------------------------------------
-- Placing it by hand in Studio beats any offset this script could compute. The auto position is a guess at
-- "somewhere clear beside the pad" and it has no idea what is actually there -- a path, a fence, the bean
-- stand, the slope of the island. A marker is the level designer saying exactly where it should stand.
--
-- Searched by lower-cased name across the whole Workspace, not FindFirstChild at the top level, because the
-- marker can be nested anywhere and its capitalisation should not matter.
--
-- A LIVE PART ALWAYS WINS; the stored offset is only a fallback.
--
-- Two facts from the logs drove this, and together they rule out every simpler approach:
--
--   1. The block IS there at boot. It is found and hidden ~0.05s after the server starts.
--   2. The block is GONE a few seconds later. A scan that retries every 2s for a full minute after
--      StandsReady never sees it again. Something in the island setup destroys or re-parents it.
--
-- So "look it up when we need it" can never work -- by launch time there is nothing to look up. The
-- position has to be taken at boot, while the block still exists.
--
-- But a boot-time WORLD position is also wrong: PlayerStats repositions all fourteen islands a couple of
-- seconds in, and a marker on island 1 moves with it. Reading the world CFrame at 0.05s gives the block's
-- pre-move location and the stand would be built somewhere out in the air.
--
-- The answer is to store the offset from the ISLAND, not from the world origin. An island-relative CFrame
-- survives both problems at once: it does not care that the block was later destroyed, and it does not care
-- that the island moved, because the island's own pivot supplies the correction afterwards.
local markerCF    = nil  -- resolved WORLD CFrame of the marker (filled in after the island move)
local markerFootY = nil  -- world Y of its LOWEST face -- where the stand's feet go
local markerRel   = nil  -- the marker's CFrame in the island's local space, captured at boot
local markerHalfY = nil  -- half its vertical extent, so the foot can be recomputed after the move
local markerIsland = nil -- the island Model it belongs to

-- Half the block's height measured in WORLD space, not down its own axis, so a marker that has been rotated
-- or tilted in Studio still resolves to its true lowest point.
local function worldHalfY(cf, sz)
	return 0.5 * (math.abs(cf.XVector.Y) * sz.X
		+ math.abs(cf.YVector.Y) * sz.Y
		+ math.abs(cf.ZVector.Y) * sz.Z)
end

-- The top-level Workspace Model the part lives under -- that is the thing PlayerStats moves.
local function islandOf(p)
	local node = p
	while node and node.Parent and node.Parent ~= workspace do
		node = node.Parent
	end
	if node and node ~= p and node:IsA("Model") then return node end
	return nil
end

local function hideMarker(p)
	-- ANCHOR FIRST. This is the line that keeps the marker alive.
	--
	-- An unanchored part falls. It crosses Workspace.FallenPartsDestroyHeight and Roblox deletes it, which
	-- is exactly the disappearance seen in the logs: the block is there at boot, and gone a few seconds
	-- later with its Y already hundreds of studs below the island it belongs to. Nothing in this game was
	-- destroying it -- it was simply dropping out of the world.
	--
	-- PetSystem already learned this and anchors its own markers before the island move, for the same
	-- reason and in the same words: "they can no longer fall away from their island". A marker is a
	-- coordinate, and a coordinate has no business obeying gravity.
	p.Anchored = true

	-- The rest is making it a coordinate rather than scenery: invisible, and inert to everything.
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

-- Accepted marker names, in priority order. "rocketplacement" is the current one; "rocketstand" still
-- works so an older place file does not silently lose its marker.
--
-- The order matters here and is not cosmetic. A part named "rocketstand" already exists in this place, down
-- in the realm-portal hub, and a scan that treated the two names as equals could return THAT one instead of
-- the real marker. Sweeping the whole Workspace for the preferred name BEFORE considering the legacy name
-- means the old part can never win while a correctly-named one exists.
local MARKER_NAMES = { "rocketplacement", "rocketstand" }

local function scanForMarker()
	for _, want in ipairs(MARKER_NAMES) do
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and string.lower(d.Name) == want then return d, want end
		end
	end
	return nil
end

-- Take everything we will ever need from the block, right now, while it exists.
local function captureMarker(p)
	markerHalfY = worldHalfY(p.CFrame, p.Size)
	markerIsland = islandOf(p)
	if markerIsland then
		local ok, pivot = pcall(function() return markerIsland:GetPivot() end)
		if ok then markerRel = pivot:Inverse() * p.CFrame end
	end
	-- World fallback, used verbatim if the part is not under an island (so nothing will move it).
	markerCF = p.CFrame
	markerFootY = p.CFrame.Position.Y - markerHalfY
end

-- Work out where the marker IS, right now.
--
-- A LIVE part always wins. If the block is still in the Workspace its own CFrame is the truth -- it has
-- already been through whatever moved it, so there is nothing left to correct for and any arithmetic on
-- top can only introduce error. Deriving a position for a part you can see is how you end up confidently
-- placing something 300 studs underground.
--
-- The island-relative derivation is strictly the fallback for when the block has been destroyed. Then
-- there is no live truth left and the stored offset, pushed through the island's current pivot, is the
-- best reconstruction available.
--
-- Returns the source so the caller can say which one it used -- when the two disagree, that is the single
-- most useful thing a log can tell you.
local function resolveMarker()
	local live = scanForMarker()
	if live then
		markerHalfY = worldHalfY(live.CFrame, live.Size)
		markerCF = live.CFrame
		markerFootY = live.CFrame.Position.Y - markerHalfY
		-- Refresh the offset too, so a later destroy falls back to the newest known-good relationship.
		markerIsland = islandOf(live)
		if markerIsland then
			local ok, pivot = pcall(function() return markerIsland:GetPivot() end)
			if ok then markerRel = pivot:Inverse() * live.CFrame end
		end
		return "live"
	end
	if markerRel and markerIsland and markerIsland.Parent then
		local ok, pivot = pcall(function() return markerIsland:GetPivot() end)
		if ok then
			markerCF = pivot * markerRel
			markerFootY = markerCF.Position.Y - (markerHalfY or 0)
			return "derived"
		end
	end
	return markerCF and "boot" or nil
end

-- JOB 1: capture + keep it invisible. Runs from the first frame; never blocks anything else.
task.spawn(function()
	local captured = false
	while true do
		local m, hitName = scanForMarker()
		if m then
			-- Re-apply if EITHER is wrong. Checking only Transparency would skip a block that is already
			-- invisible but still unanchored -- which is the one that falls out of the world.
			if m.Transparency < 1 or not m.Anchored then hideMarker(m) end
			if not captured then
				captured = true
				captureMarker(m)
				print(("[RocketRide] '%s' captured at (%.0f, %.0f, %.0f)%s")
					:format(hitName or "?", m.Position.X, m.Position.Y, m.Position.Z,
						markerIsland and (" under '" .. markerIsland.Name .. "'") or " (not on an island)"))
			else
				-- Still alive: its live position is the most accurate answer there is, so keep taking it.
				resolveMarker()
			end
		end
		task.wait(2)
	end
end)

-- JOB 2: once the islands have stopped moving, convert the captured offset into a world position.
task.spawn(function()
	local waited = 0
	while not workspace:GetAttribute("StandsReady") and waited < 90 do
		task.wait(0.5); waited = waited + 0.5
	end
	-- Give the capture a moment in case the block only streamed in very late.
	for _ = 1, 10 do
		if markerCF then break end
		task.wait(1)
	end
	if not markerCF then
		warn("[RocketRide] no BasePart named 'rocketplacement' (or 'rocketstand') was ever seen -- the "
			.. "command stand will place itself beside the pad. Check the part exists, is a Part (not a "
			.. "Model), and is spelled exactly 'rocketplacement'.")
		return
	end
	local bootCF = markerCF
	local src = resolveMarker()
	print(("[RocketRide] marker after the island move: %s -> stand goes at (%.0f, %.0f, %.0f)")
		:format(src == "live" and "the block is STILL THERE, using it directly"
			or src == "derived" and "the block is GONE, position reconstructed from the island"
			or "using the boot position unchanged",
			markerCF.Position.X, markerFootY, markerCF.Position.Z))
	if bootCF and (bootCF.Position - markerCF.Position).Magnitude > 1 then
		print(("[RocketRide]   (it moved during startup: (%.0f, %.0f, %.0f) -> (%.0f, %.0f, %.0f))")
			:format(bootCF.Position.X, bootCF.Position.Y, bootCF.Position.Z,
				markerCF.Position.X, markerCF.Position.Y, markerCF.Position.Z))
	end
end)

--------------------------------------------------------------------
-- install(site, leadSeconds): the LAUNCH COMMAND STAND beside the pad.
--------------------------------------------------------------------
-- Boarding is not a door on the rocket. A hatch forty studs up a fuselage is either unreachable or a lie
-- about where it is, and either way it makes the rocket a thing you climb rather than a thing you launch.
-- This is a little control console that wheels up next to the pad at T-30 with the launch clock running on
-- its own screen -- you walk over to it, it straps you in, it counts you down.
--
-- It is its OWN model on the ground, anchored, NOT welded to the rocket. That is the difference between a
-- console at the pad and a console bolted to a rocket that is about to leave with it.
function RocketRide.install(site, leadSeconds)
	if typeof(site) ~= "Vector3" then return end
	riders = {}
	riderN = 0
	liftoffAt = os.clock() + (tonumber(leadSeconds) or 30)

	stand = Instance.new("Model")
	stand.Name = "RocketCommandStand"
	-- StreamingEnabled is ON: a runtime model out on island 1 streams OUT for anyone stood elsewhere, and a
	-- boarding prompt nobody can see is a boarding prompt nobody uses. Same fix the rocket itself uses.
	pcall(function() stand.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)

	local function piece(name, size, cf, colour, mat, collide)
		local p = Instance.new("Part")
		p.Name = name; p.Size = size; p.CFrame = cf
		p.Color = colour; p.Material = mat or Enum.Material.Metal
		p.Anchored = true; p.CanCollide = (collide ~= false); p.CanTouch = false; p.CanQuery = true
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = stand
		return p
	end

	-- Stand on the MARKER'S captured position if the place has one, otherwise off to the side of the pad
	-- clear of the fin footprint. Either way it is TURNED TO FACE THE ROCKET, so walking up to it puts the
	-- rocket in front of you rather than behind your shoulder -- that is a fact about the launch, not about
	-- where the marker happens to be pointing, so the marker's own rotation is deliberately ignored.
	--
	-- Resolve fresh at every launch: prefers the live block, falls back to the reconstruction. Doing it
	-- here as well as at startup means a launch that fires before the resolve task ran -- or after
	-- something moved the island again -- still gets the current answer rather than a stale one.
	local src = resolveMarker()

	local footPos
	if markerCF and markerFootY then
		footPos = Vector3.new(markerCF.Position.X, markerFootY, markerCF.Position.Z)
		print(("[RocketRide] command stand ON THE MARKER (%s) -- feet at (%.0f, %.0f, %.0f), "
			.. "pad is at (%.0f, %.0f, %.0f)")
			:format(src or "?", footPos.X, footPos.Y, footPos.Z, site.X, site.Y, site.Z))
		-- A marker that ends up far under the pad is the signature of a block that travelled with its
		-- island. Say so plainly instead of silently burying the stand in the void.
		if footPos.Y < site.Y - 60 then
			warn(("[RocketRide] the marker is %.0f studs BELOW the launch pad -- the stand will be "
				.. "underground. The block is now anchored on sight, so if this persists it is not falling: "
				.. "check where 'rocketplacement' actually sits in Studio, and move it next to the pad at "
				.. "(%.0f, %.0f, %.0f).")
				:format(site.Y - footPos.Y, site.X, site.Y, site.Z))
		end
	else
		footPos = site + Vector3.new(24, 0, 16)
		warn("[RocketRide] no marker was ever found -- placing the command stand beside the pad")
	end
	-- lookAt needs a target that is not directly overhead; aiming at the rocket's mid-height keeps the stand
	-- upright even when the marker sits almost on top of the pad.
	local aim = Vector3.new(site.X, footPos.Y, site.Z)
	if (aim - footPos).Magnitude < 0.5 then aim = footPos + Vector3.new(0, 0, 1) end
	local base = CFrame.lookAt(footPos, aim)

	------------------------------------------------------------------
	-- THE CONSOLE
	------------------------------------------------------------------
	-- Built in bands -- deck, plinth, housing, controls, mast -- so it reads as equipment that was wheeled
	-- out and bolted down for the launch, rather than a box standing on a slab.
	--
	-- Everything is placed off `base`, whose LookVector points AT the rocket. So -Z is downrange and +Z is
	-- the side the player walks up to. Getting that backwards would put the screen against the rocket and
	-- the blank back of the console in the player's face.
	local STEEL  = Color3.fromRGB(58, 64, 78)
	local SHELL  = Color3.fromRGB(44, 48, 60)
	local DARK   = Color3.fromRGB(24, 26, 34)
	local TRIM   = Color3.fromRGB(94, 198, 255)
	local HAZARD = Color3.fromRGB(242, 188, 58)
	local RED    = Color3.fromRGB(255, 96, 72)
	local GREEN  = Color3.fromRGB(120, 255, 140)

	-- DECK -- a plated square with hazard diamonds along the downrange edge. The stripes cost seven small
	-- parts and do more than any amount of console detail: they read from across the pad and say "the
	-- interesting thing is here".
	piece("Deck", Vector3.new(9, 0.3, 7), base * CFrame.new(0, 0.15, 0.4),
		Color3.fromRGB(36, 39, 48), Enum.Material.DiamondPlate)
	for i = -3, 3 do
		piece("DeckChevron", Vector3.new(0.75, 0.34, 0.75),
			base * CFrame.new(i * 1.3, 0.17, -2.9) * CFrame.Angles(0, math.rad(45), 0),
			HAZARD, Enum.Material.SmoothPlastic, false)
	end

	-- PLINTH -- the console is bolted to a raised block with a painted cap, so it has a foot instead of
	-- growing straight out of the floor.
	piece("Plinth",    Vector3.new(5.2, 0.7, 3.6),  base * CFrame.new(0, 0.65, 0), SHELL)
	piece("PlinthCap", Vector3.new(5.7, 0.22, 4.1), base * CFrame.new(0, 1.11, 0), HAZARD,
		Enum.Material.SmoothPlastic)

	-- HOUSING -- two stacked blocks, the upper one narrower, so the body tapers rather than reading as one
	-- extruded rectangle.
	piece("Housing",    Vector3.new(4.2, 2.0, 2.6), base * CFrame.new(0, 2.22, 0), STEEL)
	piece("HousingTop", Vector3.new(3.4, 0.9, 2.1), base * CFrame.new(0, 3.67, -0.1), SHELL)
	-- Vent louvres down the downrange face, and angled cheek panels to break the slab silhouette side-on.
	for i = 0, 2 do
		piece("Louvre", Vector3.new(3.0, 0.16, 0.12), base * CFrame.new(0, 1.72 + i * 0.46, -1.33),
			DARK, Enum.Material.SmoothPlastic, false)
	end
	for _, sx in ipairs({ -1, 1 }) do
		piece("Cheek", Vector3.new(0.32, 1.9, 2.2),
			base * CFrame.new(sx * 2.2, 2.3, 0) * CFrame.Angles(0, 0, math.rad(sx * 7)), DARK)
	end

	-- CONTROLS LEDGE -- a shelf at hand height. A console you cannot picture anyone operating is a signpost
	-- with extra steps, so it gets a launch button under a guard, a row of toggles and a lamp bank.
	piece("Ledge",    Vector3.new(4.6, 0.3, 1.5),   base * CFrame.new(0, 3.35, 1.15), SHELL)
	piece("LedgeLip", Vector3.new(4.6, 0.14, 0.18), base * CFrame.new(0, 3.52, 1.85), HAZARD,
		Enum.Material.SmoothPlastic, false)

	local btn = piece("LaunchButton", Vector3.new(0.95, 0.95, 0.95), base * CFrame.new(1.35, 3.62, 1.15),
		RED, Enum.Material.Neon, false)
	btn.Shape = Enum.PartType.Ball
	-- The guard is the detail that makes it read as a launch button rather than a doorbell: you do not put
	-- a cage round something harmless.
	for _, sx in ipairs({ -1, 1 }) do
		piece("ButtonGuard", Vector3.new(0.14, 0.9, 0.14), base * CFrame.new(1.35 + sx * 0.72, 3.75, 1.15),
			Color3.fromRGB(150, 155, 170), nil, false)
	end
	piece("ButtonGuardTop", Vector3.new(1.6, 0.14, 0.14), base * CFrame.new(1.35, 4.18, 1.15),
		Color3.fromRGB(150, 155, 170), nil, false)

	for i = 0, 4 do
		piece("Toggle", Vector3.new(0.16, 0.4, 0.16),
			base * CFrame.new(-2.0 + i * 0.38, 3.62, 1.25),
			Color3.fromRGB(200, 205, 220), nil, false)
	end

	-- Lamp bank. Held so the tick loop can blink them through the final ten seconds.
	local lamps = {}
	for i, c in ipairs({ GREEN, HAZARD, RED }) do
		local l = piece("Lamp", Vector3.new(0.34, 0.34, 0.2),
			base * CFrame.new(-0.55 + (i - 1) * 0.45, 3.62, 1.72), c, Enum.Material.Neon, false)
		l.Shape = Enum.PartType.Ball
		lamps[#lamps + 1] = l
	end

	-- FACE -- the board stands STRAIGHT UP, square to whoever walks at it.
	--
	-- It was raked back thirty degrees, which is right for a desk panel you lean over and wrong for
	-- everything this actually is. A tilted board throws its text at the sky: you read it properly only
	-- from directly in front and close in, and from any normal approach angle it is a foreshortened sliver.
	-- Upright, the screen is legible from wherever you happen to be walking, which is the entire job of a
	-- countdown you are meant to notice.
	local fcf  = base * CFrame.new(0, 5.05, 0.75)
	local face = piece("StandFace", Vector3.new(4.9, 3.0, 0.45), fcf, DARK)
	-- Bezel trim: four thin bars framing the glass, in the same cyan as the sign's border so the console
	-- and its sign read as one object.
	piece("BezelTop",   Vector3.new(4.5, 0.14, 0.1), fcf * CFrame.new(0,  1.28, 0.26), TRIM, Enum.Material.Neon, false)
	piece("BezelLow",   Vector3.new(4.5, 0.14, 0.1), fcf * CFrame.new(0, -1.28, 0.26), TRIM, Enum.Material.Neon, false)
	piece("BezelLeft",  Vector3.new(0.14, 2.7, 0.1), fcf * CFrame.new(-2.18, 0, 0.26), TRIM, Enum.Material.Neon, false)
	piece("BezelRight", Vector3.new(0.14, 2.7, 0.1), fcf * CFrame.new( 2.18, 0, 0.26), TRIM, Enum.Material.Neon, false)

	-- The glass itself is dark, not neon. A neon slab is a bright blank rectangle -- making it dark and
	-- putting a lit SurfaceGui on top is what turns it into a screen with something written on it.
	local screen = piece("StandScreen", Vector3.new(4.2, 2.4, 0.16), fcf * CFrame.new(0, 0, 0.24),
		Color3.fromRGB(10, 14, 22), Enum.Material.SmoothPlastic, false)

	-- IN-WORLD READOUT. The billboard sign is for reading across the pad; this is what you see when you are
	-- actually stood at the console, and it is the difference between a prop and a working panel.
	local sg = Instance.new("SurfaceGui")
	sg.Name = "ScreenGui"
	sg.Face = Enum.NormalId.Back        -- +Z is the player's side; Front on a Part is -Z
	sg.CanvasSize = Vector2.new(420, 240)
	sg.LightInfluence = 0
	sg.AlwaysOnTop = false
	sg.Parent = screen

	local sgBg = Instance.new("Frame")
	sgBg.Size = UDim2.fromScale(1, 1); sgBg.BackgroundColor3 = Color3.fromRGB(8, 14, 24)
	sgBg.BorderSizePixel = 0; sgBg.Parent = sg

	local sgHead = Instance.new("TextLabel")
	sgHead.BackgroundTransparency = 1
	sgHead.Size = UDim2.new(1, -20, 0, 52); sgHead.Position = UDim2.new(0, 10, 0, 12)
	sgHead.Font = Enum.Font.FredokaOne; sgHead.TextScaled = true
	sgHead.TextColor3 = TRIM; sgHead.Text = "LAUNCH CONTROL"
	sgHead.Parent = sgBg

	local sgClock = Instance.new("TextLabel")
	sgClock.Name = "ScreenClock"
	sgClock.BackgroundTransparency = 1
	sgClock.Size = UDim2.new(1, -20, 0, 96); sgClock.Position = UDim2.new(0, 10, 0, 66)
	sgClock.Font = Enum.Font.FredokaOne; sgClock.TextScaled = true
	sgClock.TextColor3 = Color3.fromRGB(255, 255, 255); sgClock.Text = "T-30"
	sgClock.Parent = sgBg
	standScreen = sgClock

	local sgFoot = Instance.new("TextLabel")
	sgFoot.BackgroundTransparency = 1
	sgFoot.Size = UDim2.new(1, -20, 0, 46); sgFoot.Position = UDim2.new(0, 10, 0, 172)
	sgFoot.Font = Enum.Font.GothamBold; sgFoot.TextScaled = true
	sgFoot.TextColor3 = Color3.fromRGB(150, 170, 195); sgFoot.Text = "HOLD  E  TO BOARD"
	sgFoot.Parent = sgBg

	-- SIDE RAILS -- posts and a rail down each side, framing the approach without blocking it. They also
	-- stop the console looking like it is floating on the deck.
	for _, sx in ipairs({ -1, 1 }) do
		for _, pz in ipairs({ -1.4, 1.9 }) do
			piece("RailPost", Vector3.new(0.2, 2.1, 0.2), base * CFrame.new(sx * 3.3, 1.35, pz),
				Color3.fromRGB(150, 155, 170), nil, false)
		end
		piece("Rail", Vector3.new(0.16, 0.16, 3.5), base * CFrame.new(sx * 3.3, 2.3, 0.25),
			Color3.fromRGB(170, 176, 192), nil, false)
	end

	-- MAST -- carries the sign and the beacon up to eye height from across the pad, with a cross arm and a
	-- dish so the top is a silhouette rather than a bare pole.
	local mast = piece("StandMast", Vector3.new(0.36, 5.2, 0.36), base * CFrame.new(0, 6.7, -0.9),
		Color3.fromRGB(92, 98, 116), nil, false)
	piece("MastArm", Vector3.new(2.8, 0.2, 0.2), base * CFrame.new(0, 8.9, -0.9),
		Color3.fromRGB(92, 98, 116), nil, false)
	for _, sx in ipairs({ -1, 1 }) do
		piece("MastFloodlight", Vector3.new(0.45, 0.45, 0.45), base * CFrame.new(sx * 1.3, 8.66, -0.9),
			Color3.fromRGB(255, 244, 214), Enum.Material.Neon, false)
	end
	local dish = piece("MastDish", Vector3.new(1.1, 1.1, 0.25),
		base * CFrame.new(0.9, 8.2, -0.9) * CFrame.Angles(0, math.rad(-30), math.rad(20)),
		Color3.fromRGB(180, 186, 200), nil, false)
	dish.Shape = Enum.PartType.Cylinder

	-- BEACON -- the amber rotating light. Nothing says "a launch is imminent" like one of these turning.
	local beacon = piece("Beacon", Vector3.new(0.8, 0.8, 0.8), base * CFrame.new(0, 9.4, -0.9),
		HAZARD, Enum.Material.Neon, false)
	beacon.Shape = Enum.PartType.Ball
	-- A shade over half of it: as the beacon spins, the lit side sweeps, which is what sells the rotation.
	local shade = piece("BeaconShade", Vector3.new(0.5, 0.85, 0.85), base * CFrame.new(-0.3, 9.4, -0.9),
		Color3.fromRGB(70, 52, 16), Enum.Material.SmoothPlastic, false)

	local beaconLight = Instance.new("PointLight")
	beaconLight.Color = HAZARD; beaconLight.Brightness = 3; beaconLight.Range = 26
	beaconLight.Parent = beacon

	local glow = Instance.new("PointLight")
	glow.Color = TRIM; glow.Brightness = 2.6; glow.Range = 22
	glow.Parent = face

	-- THE SIGN. Two lines: what it is, and how long you have. The clock is the point -- a prompt reading
	-- "Ride the Rocket" tells you nothing about whether there is still time to run over.
	local bb = Instance.new("BillboardGui")
	bb.Name = "StandSign"
	bb.Size = UDim2.new(0, 260, 0, 78)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = SIGN_DISTANCE
	bb.Parent = mast

	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(1, 1); card.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	card.BackgroundTransparency = 0.15; card.BorderSizePixel = 0; card.Parent = bb
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = card
	local cs = Instance.new("UIStroke"); cs.Color = Color3.fromRGB(94, 198, 255); cs.Thickness = 2.5; cs.Parent = card

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -12, 0, 32); title.Position = UDim2.new(0, 6, 0, 5)
	title.Font = Enum.Font.FredokaOne; title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 206, 92)
	title.Text = "RIDE THE ROCKET"
	title.Parent = card

	local clock = Instance.new("TextLabel")
	clock.Name = "Clock"
	clock.BackgroundTransparency = 1
	clock.Size = UDim2.new(1, -12, 0, 32); clock.Position = UDim2.new(0, 6, 0, 40)
	clock.Font = Enum.Font.FredokaOne; clock.TextScaled = true
	clock.TextColor3 = Color3.fromRGB(255, 255, 255)
	clock.Text = "LIFTOFF IN 30s"
	clock.Parent = card
	standClock = clock

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RocketBoardPrompt"
	prompt.ActionText = "Board the Rocket"
	prompt.ObjectText = "Launch Command"
	prompt.HoldDuration = 0.4
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true          -- mobile/console: the prompt is tappable, not keyboard-only
	prompt.MaxActivationDistance = BOARD_RADIUS
	prompt.Enabled = false                 -- opened explicitly by openBoarding()
	prompt.Parent = face

	prompt.Triggered:Connect(function(player)
		RocketRide.board(player)
	end)

	stand.Parent = workspace

	-- The clock ticks itself. Its exit condition is "am I still the live stand", so tearing the stand down
	-- ends the loop -- there is no flag anyone has to remember to clear.
	local mine = stand
	task.spawn(function()
		while stand == mine and mine.Parent do
			local left = math.max(0, math.ceil(liftoffAt - os.clock()))
			-- Inside ten seconds everything turns red and the lamp bank blinks. The colour change is the
			-- only cue a player gets that running for it is now a bad idea.
			local urgent = (left <= 10)
			local hot    = urgent and Color3.fromRGB(255, 96, 72) or Color3.fromRGB(255, 255, 255)

			if standClock and standClock.Parent then
				standClock.Text = (left > 0) and ("LIFTOFF IN %ds"):format(left) or "LAUNCHING"
				standClock.TextColor3 = (left > 0) and hot or Color3.fromRGB(255, 96, 72)
			end
			if standScreen and standScreen.Parent then
				standScreen.Text = (left > 0) and ("T-%d"):format(left) or "LIFTOFF"
				standScreen.TextColor3 = (left > 0) and hot or Color3.fromRGB(255, 96, 72)
			end
			for i, l in ipairs(lamps) do
				if l.Parent then
					-- Steady while there is time; the red lamp alone strobes once it is nearly gone.
					l.Transparency = (urgent and i == 3 and (math.floor(os.clock() * 4) % 2 == 0)) and 0.75 or 0
				end
			end
			task.wait(0.25)
		end
	end)

	-- The beacon turns. Same exit condition as the clock -- it stops when this stand stops being the live
	-- one, so teardown ends it without anybody having to remember a flag.
	task.spawn(function()
		local t = 0
		while stand == mine and mine.Parent and shade.Parent do
			t = t + 0.06
			shade.CFrame = base * CFrame.new(0, 9.4, -0.9) * CFrame.Angles(0, t * 3.2, 0)
				* CFrame.new(-0.3, 0, 0)
			beaconLight.Brightness = 2.2 + 1.4 * (0.5 + 0.5 * math.sin(t * 3.2))
			task.wait(0.06)
		end
	end)

	print("[RocketRide] launch command stand up at T-" .. tostring(leadSeconds or 30))
end

--------------------------------------------------------------------
-- board(player): add them to the roster and tell their client to go in.
--------------------------------------------------------------------
function RocketRide.board(player)
	if not boarding then return false end
	if riders[player] then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.Health > 0) then return false end

	-- The cap is a roster count, not a seat count, because the seats live on each rider's own client and no
	-- two riders share a capsule. Two is what it is furnished for.
	if riderN >= RIDE_SEATS then
		RideEvent:FireClient(player, "full")
		return false
	end

	riders[player] = true
	riderN = riderN + 1
	-- Hand over the SECONDS LEFT, not just "you are in". The capsule's mission clock had nothing to count
	-- until the last ten seconds, because the event only broadcasts per-second ticks during the final
	-- countdown -- so for the whole boarding window the readout on the wall sat blank. The rider is the one
	-- person who cannot see the console outside, so a dead clock in here is the worst place to have one.
	RideEvent:FireClient(player, "boarded", math.max(0, liftoffAt - os.clock()))
	print(("[RocketRide] %s boarded (%d/%d)"):format(player.Name, riderN, RIDE_SEATS))
	return true
end

--------------------------------------------------------------------
-- disembark(player): get out, and be allowed back in.
--------------------------------------------------------------------
-- Boarding used to be one-way. Nothing freed a roster slot except the ending, the abort, or leaving the
-- game -- so a rider who got out was still counted aboard forever: board() bounced them on
-- `if riders[player] then return false end`, and their seat stayed spent for everyone else. With
-- RIDE_SEATS = 2 that is not a small leak; one player looking around and stepping out could take half the
-- rocket's capacity with them for the rest of the launch.
--
-- Undoing the boarding has to be the exact inverse of doing it: clear the roster entry, give the seat back,
-- and tell the client to tear its capsule down. Miss any one of those and you get a different bug -- a
-- ghost rider, a lost seat, or somebody stranded in a void room.
--
-- Respawning is the server's job. The rider is standing in a room their own client built and nobody can
-- walk out of, and LoadCharacter is server-only, so the client half genuinely cannot put them back on the
-- island by itself.
function RocketRide.disembark(player)
	if not riders[player] then return false end

	riders[player] = nil
	riderN = math.max(0, riderN - 1)

	RideEvent:FireClient(player, "left")
	pcall(function() player:LoadCharacter() end)

	print(("[RocketRide] %s got out (%d/%d aboard)"):format(player.Name, riderN, RIDE_SEATS))
	return true
end

-- The only thing a client is allowed to ask for. It carries no arguments worth trusting: whether this
-- player is aboard is a fact the server already holds, and disembark rejects anyone who is not.
RideEvent.OnServerEvent:Connect(function(player, action)
	if action == "leave" then
		RocketRide.disembark(player)
	end
end)

--------------------------------------------------------------------
-- openBoarding() / closeBoarding()
--------------------------------------------------------------------
-- Boarding stays open right through the countdown. Closing it early would mean the players who came
-- running when the countdown started -- which is exactly when the event is loudest and most visible -- are
-- the ones who miss it.
function RocketRide.openBoarding()
	boarding = true
	if prompt then prompt.Enabled = true end
	print("[RocketRide] boarding OPEN")
end

function RocketRide.closeBoarding()
	boarding = false
	if prompt then prompt.Enabled = false end
	for player in pairs(riders) do
		RideEvent:FireClient(player, "liftoff")   -- the deck starts shaking and the stars start moving
	end
	print(("[RocketRide] boarding CLOSED with %d rider(s) aboard"):format(riderN))
end

--------------------------------------------------------------------
-- detonate(): the ending.
--------------------------------------------------------------------
-- Called immediately after the explosion goes off, so the blast is already on screen when the rider dies.
--
-- PAY FIRST, THEN KILL. Both leaderstats values are written before Health is touched: a death that also ate
-- the reward would make riding a punishment, and the order is the only thing guaranteeing it cannot happen.
-- Respawning is PlayerStats' own death flow, which puts every player back on their highest island -- so a
-- rider lands where they would have landed dying any other way, and the ride grants no shortcut up the ladder.
function RocketRide.detonate()
	local n = 0
	for player in pairs(riders) do
		-- Paid through SkinCrateService's one exposed hook rather than by writing the balance here. That
		-- function is additive-only and carries the logging, clamping and persistence a token grant needs;
		-- a system that pokes _G.playerCrateTokens directly is a system that quietly stops saving the day
		-- someone changes how tokens persist.
		pcall(function()
			if type(_G.addSkinTokens) == "function" then
				_G.addSkinTokens(player, RIDE_BONUS, "rocketRide")
			end
		end)
		-- The client gets the white-out and the banner FIRST and the kill a beat later, so the last thing a
		-- rider sees is their own flight deck going up rather than a death cam they were cut to.
		RideEvent:FireClient(player, "stars", RIDE_BONUS)
		n = n + 1
	end

	local dying = {}
	for player in pairs(riders) do dying[#dying + 1] = player end
	riders = {}
	riderN = 0

	task.delay(0.55, function()
		for _, player in ipairs(dying) do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then pcall(function() hum.Health = 0 end) end
		end
	end)

	if n > 0 then
		print(("[RocketRide] %d rider(s) went up with it (+%d crate tokens each, respawning at their island)")
			:format(n, RIDE_BONUS))
	end
end

--------------------------------------------------------------------
-- cleanup(): teardown / abort path.
--------------------------------------------------------------------
-- Anyone still on the roster when the event tears down never got their ending, so they are put back rather
-- than killed -- and told to, since their character is sitting in a void room only their own client knows
-- about. Dying because the event errored is not the joke.
function RocketRide.cleanup()
	for player in pairs(riders) do
		RideEvent:FireClient(player, "released")
		-- Their character is standing in a client-built void room, which only that client can see and none
		-- of them can walk out of. LoadCharacter is server-only, so the respawn has to happen HERE -- the
		-- client half just undoes the lighting/HUD it changed.
		pcall(function() player:LoadCharacter() end)
	end
	riders = {}
	riderN = 0
	-- The stand is OUR model, standing on the ground -- RocketLogic.cleanup only owns the rocket, so if this
	-- does not destroy it the console is left behind on island 1 after the rocket has gone.
	if stand then stand:Destroy() end
	stand = nil
	standClock = nil
	prompt = nil
	boarding = false
end

-- A player who leaves mid-flight must not stay on the roster, and the seat they were holding must free up.
Players.PlayerRemoving:Connect(function(p)
	if riders[p] then
		riders[p] = nil
		riderN = math.max(0, riderN - 1)
	end
end)

-- Same leak by a different route: a rider who dies or resets mid-ride is no longer aboard anything, but
-- nothing was clearing them, so their seat stayed spent and they could never board again this launch.
--
-- detonate() empties the roster BEFORE it kills anyone, so the deaths it causes never reach this -- which
-- is what keeps the ending's own kills from being mistaken for someone bailing out.
Players.PlayerAdded:Connect(function(p)
	p.CharacterRemoving:Connect(function()
		if riders[p] then
			riders[p] = nil
			riderN = math.max(0, riderN - 1)
			print(("[RocketRide] %s died mid-ride -- seat freed (%d/%d aboard)"):format(p.Name, riderN, RIDE_SEATS))
		end
	end)
end)

return RocketRide
