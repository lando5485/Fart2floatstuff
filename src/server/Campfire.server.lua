--======================================================================
-- Campfire.server.lua  (Script -> ServerScriptService)   [Bean Island]
--======================================================================
-- A cozy AFK campfire for players who don't feel like climbing -- somewhere to just stand around with
-- friends. Sit near the fire and it trickles a FEW coins, slowly. It is deliberately tiny: this is a
-- nice-to-have for hanging out, never a reason to stop playing (active flight out-earns it many times over).
--
-- SECURITY: the coins are credited HERE, on the server, off the player's real HumanoidRootPart position --
-- the client is never asked and never trusted. A player also has to be roughly still ("resting"), so you
-- can't fly through the zone and farm it.
--
-- PLACEMENT: drop a Part named "CampfireSpot" anywhere on Bean Island in Studio and the fire builds on it.
-- No marker? It falls back to a spot a little way off the Island 1 SpawnLocation, so it still works out of
-- the box. Move the marker and the fire moves.
--======================================================================
local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local ServerStorage    = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- DUPLICATE GUARD ---------------------------------------------------------------------------------------
-- THREE copies of this script were running: the Rojo one plus two stale copies baked into the place file.
-- Every one of them built its own set of 4 campfires on the same spots, and every one of them connected its
-- own handler to the CampfireStick remote -- so one press of Roast/Stop/Eat/Remove ran three times, against
-- three separate heldStick tables that disagreed about what you were holding. Eat paid out three times and
-- three handlers raced to destroy the tool; Remove sometimes hit a copy that had already dropped it. That is
-- why the buttons felt broken.
--
-- Same treatment RealmPortals already uses: first loader wins, later copies bail, and same-named sibling
-- Scripts are destroyed. Repeated on a short timer because load ORDER is not ours to choose -- a stale copy
-- that starts before us is only reachable after we exist.
if _G.__CampfireServer then
	warn("[Campfire] a SECOND copy of Campfire.server is running -- this one is bailing out. " ..
		"Delete the stale Script in Studio (Explorer > search 'Campfire') and re-sync Rojo.")
	return
end
_G.__CampfireServer = true

local STALE_SCAN = { "ServerScriptService", "ServerStorage", "ReplicatedStorage", "ReplicatedFirst", "Workspace" }
local function nukeStaleServerCopies()
	local removed = 0
	for _, svcName in ipairs(STALE_SCAN) do
		local ok, svc = pcall(function() return game:GetService(svcName) end)
		if ok and svc then
			for _, inst in ipairs(svc:GetDescendants()) do
				if inst ~= script and inst:IsA("Script") and inst.Name == script.Name then
					pcall(function() inst.Disabled = true; inst:Destroy() end)
					removed = removed + 1
				end
			end
		end
	end
	if removed > 0 then
		warn("[Campfire] removed " .. removed .. " STALE duplicate server script(s) -- they were tripling every " ..
			"Roast/Stop/Eat/Remove press. Delete them in Studio for good.")
	end
end
nukeStaleServerCopies()
task.delay(1, nukeStaleServerCopies); task.delay(4, nukeStaleServerCopies); task.delay(9, nukeStaleServerCopies)

-- ===== THE REMOTE, AND WHY IT IS STAMPED RATHER THAN JUST NAMED =====
-- THIS IS WHY ALL FOUR BUTTONS WERE DEAD, and the press logging is what proved it: the client printed
-- "[Campfire][press] Roast -- allowed=true", so the click landed and FireServer ran -- and the server's
-- receipt line never printed. The press was arriving at a RemoteEvent with nobody listening on it.
--
-- There was MORE THAN ONE RemoteEvent named "CampfireStick" in ReplicatedStorage. A stale duplicate server
-- script (the log removes 2 of them every join) creates its own on startup. We remove those scripts at line
-- 58, but destroying a Script does NOT stop code that is already running or queued, so a stale copy that
-- gets there after us still adds a second remote. From then on it is a coin toss: the server listens on one,
-- the client's WaitForChild("CampfireStick") resolves whichever replicated first, and if they differ every
-- press vanishes into an object with no handler. Silently. Which is exactly what we saw.
--
-- Matching on NAME cannot fix that -- both are named the same. So ours is STAMPED, every same-named sibling
-- is destroyed, and the client picks by stamp (see Campfire.client.luau). Re-swept on the same schedule as
-- the script sweep above, because a stale copy can create its remote seconds after we start.
local REMOTE_STAMP = "CampfireRemoteLive"

local stickRemote
do
	-- adopt an already-stamped one if a previous pass made it, else the first same-named one, else build it
	for _, d in ipairs(ReplicatedStorage:GetChildren()) do
		if d:IsA("RemoteEvent") and d.Name == "CampfireStick" and d:GetAttribute(REMOTE_STAMP) then
			stickRemote = d; break
		end
	end
	if not stickRemote then stickRemote = ReplicatedStorage:FindFirstChild("CampfireStick") end
	if not stickRemote then
		stickRemote = Instance.new("RemoteEvent"); stickRemote.Name = "CampfireStick"
	end
	stickRemote:SetAttribute(REMOTE_STAMP, true) -- stamped BEFORE parenting, so the client never sees it unstamped
	stickRemote.Parent = ReplicatedStorage
end

-- Exactly one "CampfireStick" may exist. Any other is a stale copy's, and a press that lands on it is lost.
local function nukeRivalRemotes()
	local killed = 0
	for _, d in ipairs(ReplicatedStorage:GetChildren()) do
		if d ~= stickRemote and d.Name == "CampfireStick" then
			pcall(function() d:Destroy() end); killed += 1
		end
	end
	if killed > 0 then
		warn("[Campfire] destroyed " .. killed .. " RIVAL 'CampfireStick' remote(s) made by a stale duplicate " ..
			"script. Button presses were landing on one of those and vanishing -- nobody was listening on it.")
	end
end
nukeRivalRemotes()
task.delay(1, nukeRivalRemotes); task.delay(4, nukeRivalRemotes); task.delay(9, nukeRivalRemotes)

--------------------------------------------------------------------------------
-- tuning -- keep the coins SMALL
--------------------------------------------------------------------------------
local SCALE        = 1.02   -- overall size of the campfire + seats (1 = original). Everything scales off this.
local SEATS        = 6      -- default stump seats ringed around a fire (a numbered brick like "Fire 2" overrides)
-- CRACKLE: a looped 3D sound parented to each fire's flame part. Distances matter more than volume here --
-- four campfires sit within ~200 studs of each other in the garden, so the fade has to finish before you are
-- close enough to hear the next one, or the whole area turns into one flat wash of fire noise.
local CRACKLE_SOUND_ID  = "rbxassetid://158853971"
-- ===== IT WAS AUDIBLE FROM MOST OF THE ISLAND =====
-- The four garden fires actually sit at roughly (-87, 78), (-88, -69), (80, 25) and (29, 105) -- the two
-- closest are about 95 studs apart. With the old FADE_DIST of 90 every fire was still audible almost all
-- the way to its neighbour, so standing anywhere in the middle put you inside two or three overlapping
-- crackles at once. That is the "flat wash of fire noise" the note above was trying to avoid, and the
-- numbers were just too generous to achieve it.
--
-- ===== WHY THE DISTANCES MOVED AND NOT JUST THE VOLUME =====
-- Dropping Volume alone would have made the fire quieter when you are SAT AT IT too, which is the one
-- place it should sound good. What was wrong was the SHAPE of the falloff, not its peak: the sound needs
-- to be a thing you walk up to, so the honest fix is to pull the fade in so it dies inside its own
-- clearing. Volume comes down a little as well, but the distances are doing the real work.
--
-- FULL_DIST 10 is about the bench ring -- full strength only once you are actually at the fire.
-- FADE_DIST 45 is a shade under twice REST_RADIUS (24): still clearly there while you are resting, gone
-- by the time you are halfway to the next fire. Nothing overlaps any more.
local CRACKLE_VOLUME    = 0.55 -- was 0.75
local CRACKLE_FULL_DIST = 10   -- was 18 -- studs of full volume, roughly the bench ring
local CRACKLE_FADE_DIST = 45   -- was 90 -- studs to silence; REST_RADIUS is 24, nearest fire is ~95 away
local REST_RADIUS  = 24     -- studs from the fire you must be within to count as resting (widened for the bigger ring)
-- ===== RESTING PAY IS 40% LOWER, AND IT IS THE INTERVAL THAT CHANGED =====
-- 3 -> 5 seconds between payouts, which is 3 / 0.6, so a minute at the fire now pays exactly 60% of what it
-- used to. The per-tick AMOUNTS below are deliberately untouched: they are small integers (1 and 3), and
-- scaling those by 0.6 gives 0.6 and 1.8, which floor to 0 and 1 -- the first would pay nothing at all and
-- the second is a 67% cut, not 40%. Stretching the interval lands the cut exactly and keeps every payout a
-- whole coin, so the ramp (1/tick, rising to the 3 cap after two minutes) still reads the same on screen.
--
--   before: 1 coin/3s = 20/min, ramping to 3/3s = 60/min at the cap
--   after:  1 coin/5s = 12/min, ramping to 3/5s = 36/min at the cap
local TICK         = 5      -- seconds between payouts (was 3; see the note above -- this is the 40% cut)
local BASE_COINS   = 1      -- coins per tick to start
local BONUS_PER_MIN = 1     -- +1 per full minute you stay, so genuine idling feels a touch cozier...
local MAX_COINS    = 3      -- ...but it's capped low. 3 coins / 5s is the ceiling (36 a minute).
local STILL_SPEED  = 14     -- studs/s: move faster than this and you're not "resting", you're passing through

-- marshmallow roasting
local ROAST_RANGE  = 8      -- studs: how close the MARSHMALLOW (stick tip) must be to a flame to cook
local ROAST_DT     = 0.35   -- seconds between roast updates (smooth colour change)
local ROAST_STEP   = 2.4    -- roast points added per update while over the fire (0..100 = raw..burnt)

--------------------------------------------------------------------------------
-- build helpers (game art style: matte plastic, smooth, anchored, no collide)
--------------------------------------------------------------------------------
local SMOOTH = Enum.SurfaceType.Smooth
local function part(parent, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.CFrame = cf; p.Color = color
	p.Material = material or Enum.Material.Plastic
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH
	p.Parent = parent
	return p
end
local function cyl(parent, name, len, dia, cf, color, material)
	-- a Cylinder's axis runs along its own X
	local p = part(parent, name, Vector3.new(len, dia, dia), cf, color, material, Enum.PartType.Cylinder)
	return p
end

--------------------------------------------------------------------------------
-- find where to put it
--------------------------------------------------------------------------------
local function findIsland()
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.find(m.Name, "Island_1", 1, true) then return m end
	end
	return nil
end

-- A marker is any BRICK named "fire" / "campfire" / "campfirespot", optionally with a trailing number
-- ("Fire 2", "campfire3"). The pattern is strict on purpose: it must NOT catch our own build parts like
-- "Firewood". A trailing NUMBER sets that fire's seat count -- so a brick named "Fire 2" builds a campfire
-- with 2 seats, while a plain "Fire" gets the default. (A `Seats` attribute on the brick overrides this.)
local function markerSeats(marker)
	local attr = tonumber(marker:GetAttribute("Seats"))
	if attr then return math.clamp(math.floor(attr), 0, 16) end
	local n = tonumber(marker.Name:match("(%d+)%s*$")) -- the number at the end of the name, if any
	if n then return math.clamp(n, 0, 16) end
	return SEATS
end

local function isFireMarker(inst)
	if not inst:IsA("BasePart") then return false end -- a real brick, never the Fire EFFECT class
	local n = inst.Name:lower():gsub("%s+", "") -- "Fire 2" -> "fire2"
	return n:match("^fire%d*$") ~= nil or n:match("^campfire%d*$") ~= nil or n == "campfirespot"
end

-- GROUND PLANE for the build. The whole campfire is laid out relative to y = 0 of the CFrame we return,
-- and it must be the FLOOR -- otherwise the fire (and the chairs) float at the height of the marker brick.
-- Raycast straight down from the marker to the island surface and build on THAT. Falls back to the brick's
-- underside if the ray hits nothing. Player characters are excluded so nobody standing on the spot skews it.
local function groundCF(pos, fallbackBottomY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local chars = {}
	for _, pl in ipairs(Players:GetPlayers()) do if pl.Character then chars[#chars + 1] = pl.Character end end
	params.FilterDescendantsInstances = chars -- the markers are already CanQuery=false, so the ray skips them
	local hit = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -400, 0), params)
	local groundY = hit and hit.Position.Y or fallbackBottomY
	return CFrame.new(pos.X, groundY, pos.Z)
end

-- EVERY fire brick becomes its own campfire. Returns a list of { cf =, seats = }.
local function findMarkers()
	local spots = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if isFireMarker(d) then
			d.Transparency = 1; d.CanCollide = false; d.CanQuery = false
			local bottomY = d.Position.Y - d.Size.Y * 0.5
			spots[#spots + 1] = { cf = groundCF(d.Position, bottomY), seats = markerSeats(d), name = d.Name }
		end
	end
	if #spots == 0 then
		-- no markers at all -> one default campfire, a little way off the Island 1 spawn pad
		local island = findIsland()
		local spawn = island and island:FindFirstChildWhichIsA("SpawnLocation", true)
		if spawn then
			local base = spawn.CFrame * CFrame.new(0, -spawn.Size.Y * 0.5, -22)
			spots[1] = { cf = groundCF(base.Position, base.Position.Y), seats = SEATS, name = "(default)" }
		end
	end
	return spots
end

--------------------------------------------------------------------------------
-- build the campfire
--------------------------------------------------------------------------------
local STONE  = Color3.fromRGB(150, 148, 146)
local STONE2 = Color3.fromRGB(126, 124, 122)
local BARK   = Color3.fromRGB(110, 78, 52)
local BARK2  = Color3.fromRGB(134, 98, 66)
local EMBER  = Color3.fromRGB(90, 40, 24)

local giveStick        -- forward declarations; the real functions are defined lower, near the stick logic
local plantDisplayStick -- clones the ACTUAL held stick as a static prop for the pickup holder

-- weather state: fires are DOUSED during a THUNDERSTORM (and for a 10s dry-out afterwards). While not lit,
-- nothing roasts or earns, and the sign says why.
local firesLit  = true
local CAMPFIRES = {} -- per-fire records: { flame =, fire =, light =, smoke =, sign = (TextLabel) }

local function buildCampfire(baseCF, seats)
	local S = SCALE
	seats = seats or SEATS
	local model = Instance.new("Model"); model.Name = "Campfire"; model.Parent = Workspace
	model:SetAttribute("CampfireSpot", true)
	model:SetAttribute("BuiltByLiveScript", true) -- stamp: lets us tell OUR fires from a stale copy's (see pruneDuplicateFires)

	-- a SOLID stone rim around the pit: chunky blocks laid tangent to the circle and overlapped so there are
	-- no gaps -- one continuous low-poly ring, not scattered pebbles.
	local RIM_N   = 22
	local RIM_R   = 3.6 * S
	local rimH    = 1.1 * S
	local segLen  = (2 * math.pi * RIM_R / RIM_N) * 1.45 -- >1 so neighbours overlap into a solid ring
	for i = 1, RIM_N do
		local a = (i / RIM_N) * math.pi * 2
		local pos     = (baseCF * CFrame.new(math.cos(a) * RIM_R, rimH * 0.42, math.sin(a) * RIM_R)).Position
		local tangent = baseCF:VectorToWorldSpace(Vector3.new(-math.sin(a), 0, math.cos(a)))
		local cf      = CFrame.fromMatrix(pos, tangent, baseCF.UpVector) -- X runs along the tangent
		part(model, "RimStone", Vector3.new(segLen, rimH, 1.5 * S), cf,
			(i % 2 == 0) and STONE or STONE2, Enum.Material.Plastic)
	end

	-- a charred base under the logs
	cyl(model, "Ashes", 0.4 * S, 6.0 * S, baseCF * CFrame.new(0, 0.2 * S, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(58, 52, 50), Enum.Material.Plastic)

	-- 4 wood beams leaning into each other -- a teepee/pyramid, bottoms splayed on the ground, tops meeting
	-- at one apex over the flame.
	local apex   = (baseCF * CFrame.new(0, 3.6 * S, 0)).Position -- where the four tops meet
	local baseR  = 1.9 * S                                       -- how far out the bottoms splay
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + math.rad(45)
		local foot = (baseCF * CFrame.new(math.cos(a) * baseR, 0.25 * S, math.sin(a) * baseR)).Position
		local dir  = (apex - foot)
		local len  = dir.Magnitude
		dir = dir.Unit
		-- a level "up" to build the beam's frame off (any vector not parallel to dir works)
		local up   = (math.abs(dir.Y) > 0.99) and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		local side = dir:Cross(up).Unit
		local upv  = side:Cross(dir).Unit
		-- a Cylinder's length runs along its local X, so build a CFrame whose X axis IS the beam direction
		local cf = CFrame.fromMatrix((apex + foot) * 0.5, dir, upv)
		cyl(model, "Log", len, 0.8 * S, cf, (i % 2 == 0) and BARK or BARK2, Enum.Material.Wood)
	end

	-- a couple of glowing embers nestled at the base of the teepee
	for i = 1, 3 do
		local a = (i / 3) * math.pi * 2
		part(model, "Ember", Vector3.new(0.55 * S, 0.4 * S, 0.55 * S),
			baseCF * CFrame.new(math.cos(a) * 0.9 * S, 0.35 * S, math.sin(a) * 0.9 * S),
			Color3.fromRGB(255, 130, 40), Enum.Material.Neon, Enum.PartType.Ball)
	end

	-- the flame core: a neon body the Fire + light + smoke all hang off
	local flame = part(model, "Flame", Vector3.new(2.2 * S, 3.2 * S, 2.2 * S), baseCF * CFrame.new(0, 2.3 * S, 0),
		Color3.fromRGB(255, 150, 40), Enum.Material.Neon, Enum.PartType.Ball)
	flame.Transparency = 0.35
	model.PrimaryPart = flame

	local fire = Instance.new("Fire")
	fire.Size = 8 * S; fire.Heat = 6; fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 120); fire.Parent = flame

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90); light.Brightness = 1.68; light.Range = 26 * S; light.Parent = flame

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxassetid://243098098" -- soft round puff
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 116, 112))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.55), NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(2.4, 3.6)
	smoke.Rate = 7; smoke.Speed = NumberRange.new(4, 6); smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Acceleration = Vector3.new(0, 3, 0)
	smoke.Parent = flame

	-- CRACKLE: a looped 3D sound on the flame itself, so it pans and fades with distance and every player in
	-- the server hears it (built server-side, like the fire/light/smoke it sits beside). It is tied to the LIT
	-- state below -- a rained-out campfire that still crackles is worse than one that never did.
	local crackle = Instance.new("Sound")
	crackle.Name = "CampfireCrackle"
	crackle.SoundId = CRACKLE_SOUND_ID
	crackle.Looped = true
	crackle.Volume = CRACKLE_VOLUME
	crackle.RollOffMode = Enum.RollOffMode.InverseTapered
	crackle.RollOffMinDistance = CRACKLE_FULL_DIST -- full volume when you are sat at the fire
	crackle.RollOffMaxDistance = CRACKLE_FADE_DIST -- silent well before the next campfire's crackle starts
	-- Fires are built a few studs apart around the garden; a small random pitch per fire stops the overlap
	-- between two of them from phasing into one weird doubled tone.
	crackle.PlaybackSpeed = 0.94 + math.random() * 0.12
	crackle.Parent = flame
	if firesLit then crackle:Play() end

	-- log-bench seats ringed around the fire -- you can actually sit on these
	local benchR = 8.5 * S
	-- seats: one plain wood cylinder each, and nothing else. Kept Y-up (so sitting works) and aimed at the
	-- fire with lookAt, so a seated player faces the flames.
	local fireXZ = baseCF.Position
	for i = 1, seats do
		local a = (i / seats) * math.pi * 2
		-- y = 0.85*S == the cylinder's radius, so the stool rests exactly on the ground (baseCF is the floor)
		local pos = (baseCF * CFrame.new(math.cos(a) * benchR, 0.85 * S, math.sin(a) * benchR)).Position
		local seat = Instance.new("Seat")
		seat.Name = "CampfireSeat"
		seat.Shape = Enum.PartType.Cylinder
		seat.Size = Vector3.new(2.4 * S, 1.7 * S, 1.7 * S) -- a short round wood stool
		seat.CFrame = CFrame.lookAt(pos, Vector3.new(fireXZ.X, pos.Y, fireXZ.Z))
		seat.Color = BARK; seat.Material = Enum.Material.Wood
		seat.Anchored = true
		seat.Parent = model
	end

	-- a friendly floating sign so people find it
	local sign = part(model, "SignAnchor", Vector3.new(0.2, 0.2, 0.2), baseCF * CFrame.new(0, 6.6 * S, 0),
		Color3.fromRGB(255, 170, 90), Enum.Material.Neon, Enum.PartType.Ball)
	sign.Transparency = 1
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(210, 56); bb.AlwaysOnTop = true; bb.MaxDistance = 45; bb.Adornee = sign; bb.Parent = sign
	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(1, 1); card.BackgroundColor3 = Color3.fromRGB(28, 18, 12)
	card.BackgroundTransparency = 0.25; card.BorderSizePixel = 0; card.Parent = bb
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
	local st = Instance.new("UIStroke", card); st.Color = Color3.fromRGB(255, 180, 110); st.Thickness = 1.5
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -10, 1, -6); lbl.Position = UDim2.fromOffset(5, 3); lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne; lbl.TextScaled = true; lbl.TextColor3 = Color3.fromRGB(255, 226, 180)
	lbl.Text = "\xF0\x9F\x94\xA5 Cozy Campfire\nrest & warm up"; lbl.Parent = card
	local ls = Instance.new("UIStroke", lbl); ls.Color = Color3.new(0, 0, 0); ls.Thickness = 2

	-- MARSHMALLOW-STICK STAND: a proper little pickup just outside the ring -- a rounded wooden bucket with
	-- iron hoops, and REAL roasting sticks (the exact model you receive) fanned out of the top. Grab one and
	-- it hands you that stick to cook.
	local standCF = baseCF * CFrame.new(benchR * 0.72, 0, benchR * 0.72)

	-- the bucket: a tapered barrel body, a darker rim, and two iron hoops
	local BUCKET = Color3.fromRGB(176, 132, 84)
	local RIM    = Color3.fromRGB(132, 94, 56)
	local IRON   = Color3.fromRGB(84, 84, 92)
	cyl(model, "BucketBody", 2.0 * S, 2.4 * S, standCF * CFrame.new(0, 1.0 * S, 0) * CFrame.Angles(0, 0, math.rad(90)),
		BUCKET, Enum.Material.WoodPlanks)
	cyl(model, "BucketBase", 1.0 * S, 2.7 * S, standCF * CFrame.new(0, 0.5 * S, 0) * CFrame.Angles(0, 0, math.rad(90)),
		BUCKET, Enum.Material.WoodPlanks)
	cyl(model, "BucketRim", 0.5 * S, 2.7 * S, standCF * CFrame.new(0, 2.0 * S, 0) * CFrame.Angles(0, 0, math.rad(90)),
		RIM, Enum.Material.Wood)
	for _, hy in ipairs({ 0.7, 1.6 }) do
		cyl(model, "BucketHoop", 0.22 * S, 2.62 * S, standCF * CFrame.new(0, hy * S, 0) * CFrame.Angles(0, 0, math.rad(90)),
			IRON, Enum.Material.Metal)
	end
	-- a couple of loose marshmallows resting on the rim, for flavour
	for j = 1, 2 do
		local a = math.rad(40 + j * 150)
		local m = part(model, "RimMarsh", Vector3.new(0.7 * S, 0.62 * S, 0.62 * S),
			standCF * CFrame.new(math.cos(a) * 0.85 * S, 2.35 * S, math.sin(a) * 0.85 * S) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(252, 246, 230), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end

	-- three REAL sticks (the model you actually hold) planted in the bucket, fanned out
	for j = 1, 3 do
		local lean = math.rad(20 * (j - 2))
		local plantCF = standCF * CFrame.new((j - 2) * 0.55 * S, 2.4 * S, 0)
			* CFrame.Angles(math.rad(-58), 0, lean) -- tip up and out of the bucket
		pcall(function() plantDisplayStick(model, plantCF) end)
	end

	local promptAnchor = part(model, "PromptAnchor", Vector3.new(0.4, 0.4, 0.4), standCF * CFrame.new(0, 3.0 * S, 0),
		Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	promptAnchor.Transparency = 1
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "TakeMarshmallowStick"; pp.ActionText = "Take a Marshmallow"; pp.ObjectText = "Campfire"
	pp.HoldDuration = 0.4; pp.MaxActivationDistance = 12; pp.RequiresLineOfSight = false
	pp.Parent = promptAnchor
	pp.Triggered:Connect(function(plr) if plr then giveStick(plr) end end)

	-- remember this fire so the weather can douse/relight it and swap its sign text
	CAMPFIRES[#CAMPFIRES + 1] = { flame = flame, fire = fire, light = light, smoke = smoke, sign = lbl, crackle = crackle }

	-- gentle flicker: the light and flame breathe while LIT; when doused, it goes dark and cold.
	task.spawn(function()
		while flame.Parent do
			if firesLit then
				local f = 0.75 + math.random() * 0.5
				light.Brightness = 1.68 * f
				flame.Transparency = 0.28 + math.random() * 0.2
			else
				light.Brightness = 0
				flame.Transparency = 1 -- the flame is out; only smoke/wet logs remain (smoke toggled elsewhere)
			end
			task.wait(0.12)
		end
	end)

	return flame
end

-- douse or relight every campfire, and set what its sign says.
local SIGN_LIT   = "\xF0\x9F\x94\xA5 Cozy Campfire\nrest & warm up"
local SIGN_RAIN  = "\xF0\x9F\x8C\xA7 Rained out!\nthe fire's out"
local function setFiresLit(lit)
	firesLit = lit
	-- Published so the CLIENT can grey the Roast button while the fire is out. Without it the button stays
	-- bright orange during a storm and pressing it just silently fails, which reads as a broken button.
	Workspace:SetAttribute("CampfireLit", lit and true or false)
	for _, c in ipairs(CAMPFIRES) do
		if c.fire  then c.fire.Enabled  = lit end
		if c.smoke then c.smoke.Enabled = lit end -- (the flame part is driven by the flicker loop)
		if c.sign  then c.sign.Text = lit and SIGN_LIT or SIGN_RAIN end
		-- the crackle follows the flame: doused by the storm, back when the logs dry out
		if c.crackle then
			if lit then c.crackle:Play() else c.crackle:Stop() end
		end
	end
end
local function setSignText(text)
	for _, c in ipairs(CAMPFIRES) do if c.sign then c.sign.Text = text end end
end

--------------------------------------------------------------------------------
-- the resting payout
--------------------------------------------------------------------------------
local restedSince = {} -- [player] = os.clock() when they arrived at the fire (nil = not resting)
local FLAMES = {}      -- every campfire's flame part (filled in init; shared by resting + roasting)

local function creditCoins(player, amount)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local tce   = ls:FindFirstChild("TotalCoinsEarned")
	if coins then coins.Value = coins.Value + amount end
	if tce   then tce.Value   = tce.Value   + amount end
end

--------------------------------------------------------------------------------
-- MARSHMALLOW ROASTING -- grab a stick, hold the marshmallow over the fire until it's the brown you like,
-- then click to eat it. Cooking + eating are server-side (Tool.Activated fires on the server), so it can't
-- be spoofed, and the marshmallow's colour replicates to everyone.
--------------------------------------------------------------------------------
-- roast 0..100 mapped to colour: raw white -> golden -> toasty brown -> burnt.
local ROAST_STOPS = {
	{ 0,   Color3.fromRGB(252, 246, 230) }, -- raw
	{ 30,  Color3.fromRGB(240, 214, 150) }, -- light golden
	{ 55,  Color3.fromRGB(196, 140, 70)  }, -- golden brown
	{ 78,  Color3.fromRGB(120, 74, 38)   }, -- toasty
	{ 100, Color3.fromRGB(40, 28, 20)    }, -- burnt
}
local function marshColor(r)
	r = math.clamp(r, 0, 100)
	for i = 1, #ROAST_STOPS - 1 do
		local a, b = ROAST_STOPS[i], ROAST_STOPS[i + 1]
		if r <= b[1] then
			local t = (r - a[1]) / (b[1] - a[1])
			return a[2]:Lerp(b[2], t)
		end
	end
	return ROAST_STOPS[#ROAST_STOPS][2]
end

-- what eating a marshmallow at this roast says + rewards. Golden is the sweet spot.
-- Below this the marshmallow is RAW: roastResult calls it "Still raw!", and the Eat action refuses it. One
-- constant so the refusal and the result text can never disagree about what raw means.
local RAW_UNTIL = 18
local function roastResult(r)
	if r < RAW_UNTIL then return "Still raw! Hold it over the fire.", 1, Color3.fromRGB(240, 240, 240)
	elseif r < 42 then return "\xF0\x9F\x98\x8B Lightly toasted!",  3, Color3.fromRGB(240, 214, 150)
	elseif r < 72 then return "\xF0\x9F\x94\xA5 Perfectly golden!", 8, Color3.fromRGB(255, 190, 90)  -- best
	elseif r < 92 then return "Crispy and gooey!",                 4, Color3.fromRGB(170, 110, 60)
	else               return "\xF0\x9F\x98\x85 Burnt to a crisp!", 1, Color3.fromRGB(90, 60, 40)
	end
end

-- MARSHMALLOW ON / OFF ----------------------------------------------------------------------------------
-- Eating no longer throws the stick away. You keep the stick and walk back to the bucket for another
-- marshmallow, so the marshmallow has to come OFF and go back ON again.
--
-- It is HIDDEN, not destroyed. The marshmallow is a welded part of the tool model, so destroying it means
-- rebuilding and re-welding a fresh one on every refill -- a lot of moving parts to get wrong on someone
-- else's imported model. Transparency is exact, reversible, and cannot desync the weld. The original
-- transparency is stashed on the part the first time we touch it, so a model that ships a slightly see-through
-- marshmallow comes back looking the way its author made it.
local function setMarsh(tool, on)
	local marsh = tool and tool:FindFirstChild("Marshmallow")
	if not marsh then return false end
	if marsh:GetAttribute("BaseTransparency") == nil then marsh:SetAttribute("BaseTransparency", marsh.Transparency) end
	marsh.Transparency = on and (marsh:GetAttribute("BaseTransparency") or 0) or 1
	marsh.CanCollide = false
	marsh.CanTouch   = on and true or false
	if on then marsh.Color = marshColor(0) end -- a fresh one is raw again, however burnt the last was
	tool:SetAttribute("Roast", 0)
	tool:SetAttribute("HasMarsh", on and true or false)
	return true
end

-- Is there something on the end of the stick to cook? Attribute missing (a stick handed out by an older copy
-- of this script) counts as YES, so nobody ends up holding a stick the buttons refuse to work on.
local function hasMarsh(tool)
	return tool ~= nil and tool:GetAttribute("HasMarsh") ~= false and tool:FindFirstChild("Marshmallow") ~= nil
end

-- a quick bubble over the player's head (server-built, so no client script + everyone sees it)
local function flashOverhead(player, text, color)
	local char = player.Character
	local head = char and (char:FindFirstChild("Head") or char:FindFirstChildWhichIsA("BasePart"))
	if not head then return end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(200, 44); bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = true; bb.MaxDistance = 60; bb.Adornee = head; bb.Parent = head
	local card = Instance.new("Frame"); card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(26, 18, 12); card.BackgroundTransparency = 0.2; card.BorderSizePixel = 0; card.Parent = bb
	Instance.new("UICorner", card).CornerRadius = UDim.new(1, 0)
	local st = Instance.new("UIStroke", card); st.Color = color; st.Thickness = 2
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -12, 1, -6); lbl.Position = UDim2.fromOffset(6, 3); lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne; lbl.TextScaled = true; lbl.TextColor3 = Color3.new(1, 1, 1); lbl.Text = text; lbl.Parent = card
	local ls = Instance.new("UIStroke", lbl); ls.Color = Color3.new(0, 0, 0); ls.Thickness = 2
	task.delay(2.6, function() bb:Destroy() end)
end

-- a welded, unanchored tool part (tool parts must NOT be anchored, or they won't follow the grip)
local function toolPart(tool, handle, name, size, localCF, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.Color = color; p.Material = material or Enum.Material.Wood
	p.Shape = shape or Enum.PartType.Block
	p.CanCollide = false; p.Massless = true; p.Anchored = false
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH
	p.CFrame = handle.CFrame * localCF
	p.Parent = tool
	if p ~= handle then
		local w = Instance.new("WeldConstraint"); w.Part0 = handle; w.Part1 = p; w.Parent = handle
	end
	return p
end

-- USE YOUR OWN MODEL IF YOU HAVE ONE. Anything named like "marshmallow on a stick" (spelling/spacing don't
-- matter -- it just has to contain "marsh" and "stick") in Workspace, ServerStorage or ReplicatedStorage is
-- picked up and used as the roasting tool. If it's already a Tool it's used as-is; if it's a Model/part it
-- gets wrapped into a Tool. If nothing's found, the code-built stick below is the fallback.
local function isStickSource(inst)
	if not (inst:IsA("Tool") or inst:IsA("Model") or inst:IsA("BasePart")) then return false end
	local n = inst.Name:lower():gsub("%A", "") -- strip spaces/punctuation -> "marshmellowonastick"
	return n:find("marsh", 1, true) ~= nil and n:find("stick", 1, true) ~= nil
end
local function findStickSource()
	for _, root in ipairs({ ServerStorage, ReplicatedStorage, Workspace }) do
		for _, d in ipairs(root:GetDescendants()) do
			if isStickSource(d) then return d end
		end
	end
	return nil
end

-- the marshmallow inside a tool: a part whose name says "marsh", else the lightest-coloured part (a raw
-- marshmallow is near-white). It gets renamed "Marshmallow" so the roast/eat code finds it unchanged.
local function normalizeMarsh(tool)
	local byName, lightest
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name:lower():find("marsh", 1, true) then byName = byName or d end
			local lum = d.Color.R + d.Color.G + d.Color.B
			if not lightest or lum > (lightest.Color.R + lightest.Color.G + lightest.Color.B) then lightest = d end
		end
	end
	local marsh = byName or lightest
	if marsh then marsh.Name = "Marshmallow" end
	return marsh
end

-- wrap an arbitrary Model / part into a holdable Tool: pick a Handle, weld the rest to it, unanchor all.
local function wrapAsTool(srcClone)
	local tool = Instance.new("Tool")
	local parts = {}
	if srcClone:IsA("BasePart") then parts = { srcClone }
	else for _, d in ipairs(srcClone:GetDescendants()) do if d:IsA("BasePart") then parts[#parts + 1] = d end end end
	if #parts == 0 then srcClone:Destroy(); tool:Destroy(); return nil end

	local handle
	for _, p in ipairs(parts) do if p.Name == "Handle" then handle = p; break end end
	if not handle and srcClone:IsA("Model") and srcClone.PrimaryPart then handle = srcClone.PrimaryPart end
	if not handle then -- no hint -> the biggest part is almost always the stick/body
		for _, p in ipairs(parts) do
			if not handle or p.Size.Magnitude > handle.Size.Magnitude then handle = p end
		end
	end
	handle.Name = "Handle"
	for _, p in ipairs(parts) do
		p.Anchored = false; p.CanCollide = false; p.Massless = true
		p.Parent = tool -- reparenting preserves world CFrame, so the weld captures the right offset
		if p ~= handle then
			local w = Instance.new("WeldConstraint"); w.Part0 = handle; w.Part1 = p; w.Parent = handle
		end
	end
	srcClone:Destroy() -- the now-empty wrapper model
	return tool
end

-- build ONE marshmallow-stick tool template (cloned per player). A proper roasting branch: a tapered
-- shaft with a knotty bend, a bark-wrapped grip, a two-prong fork at the tip, and the marshmallow skewered
-- on it -- not just a plain rod.
local BARK_A = Color3.fromRGB(120, 86, 54)
local BARK_B = Color3.fromRGB(96, 66, 40)
local function buildCodeStick()
	local tool = Instance.new("Tool")
	tool.Name = "Marshmallow Stick"; tool.CanBeDropped = false; tool.RequiresHandle = true
	tool.ToolTip = "Roast it over the fire, then click to eat"
	-- Belongs to Bean Farm's campfire and nowhere else. HeldItemSync reads this and takes the stick back on
	-- respawn, so you can't carry it up to Pizza Palms and stand there holding a marshmallow at nothing.
	tool:SetAttribute("QuestIsland", 1)

	-- Handle = the grip end (what your hand holds). Everything else welds to it.
	local handle = Instance.new("Part")
	handle.Name = "Handle"; handle.Size = Vector3.new(0.34, 0.34, 1.8)
	handle.Color = BARK_B; handle.Material = Enum.Material.Wood
	handle.CanCollide = false; handle.Massless = true; handle.Anchored = false
	handle.CFrame = CFrame.new(); handle.Parent = tool

	-- a couple of bark bands on the grip
	for _, z in ipairs({ 0.4, -0.4 }) do
		toolPart(tool, handle, "GripBand", Vector3.new(0.4, 0.4, 0.16),
			CFrame.new(0, 0, z), Color3.fromRGB(70, 48, 30), Enum.Material.Wood, Enum.PartType.Cylinder)
			.CFrame = handle.CFrame * CFrame.new(0, 0, z) * CFrame.Angles(0, math.rad(90), 0)
	end

	-- the shaft, in two slightly bent segments so it reads as a branch, not a dowel
	toolPart(tool, handle, "Shaft", Vector3.new(0.26, 0.26, 2.6),
		CFrame.new(0, 0.03, -2.1) * CFrame.Angles(math.rad(-2.5), 0, 0), BARK_A, Enum.Material.Wood, Enum.PartType.Cylinder)
	toolPart(tool, handle, "Shaft2", Vector3.new(0.2, 0.2, 2.2),
		CFrame.new(0, 0.14, -4.1) * CFrame.Angles(math.rad(-5.5), 0, 0), BARK_A, Enum.Material.Wood, Enum.PartType.Cylinder)
	-- a little side twig for character
	toolPart(tool, handle, "Twig", Vector3.new(0.12, 0.12, 0.9),
		CFrame.new(0.18, 0.1, -1.4) * CFrame.Angles(0, math.rad(40), 0), BARK_B, Enum.Material.Wood, Enum.PartType.Cylinder)

	-- two-prong fork at the tip that the marshmallow sits on
	for _, sx in ipairs({ -1, 1 }) do
		toolPart(tool, handle, "Prong", Vector3.new(0.12, 0.12, 0.9),
			CFrame.new(sx * 0.14, 0.22, -5.35) * CFrame.Angles(math.rad(-8), math.rad(sx * 10), 0),
			Color3.fromRGB(210, 188, 150), Enum.Material.Wood, Enum.PartType.Cylinder)
	end

	-- the marshmallow, skewered on the fork
	local marsh = toolPart(tool, handle, "Marshmallow", Vector3.new(1.05, 0.95, 0.95),
		CFrame.new(0, 0.28, -5.5), marshColor(0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	marsh.CFrame = handle.CFrame * CFrame.new(0, 0.28, -5.5) * CFrame.Angles(0, math.rad(90), 0) -- barrel down the stick

	tool:SetAttribute("Roast", 0)
	return tool
end

-- POINT IT FORWARD. Set the Tool.Grip so the stick extends out of the hand toward whatever the player is
-- looking at (the fire). A held tool's local -Z is its "forward"; we rotate the grip so the marshmallow's
-- direction lines up with that. Works for any model, since it's computed from where its marshmallow sits.
local function aimStick(tool)
	local handle = tool:FindFirstChild("Handle")
	local marsh  = tool:FindFirstChild("Marshmallow")
	if not (handle and marsh) then return end
	local dir = handle.CFrame:VectorToObjectSpace(marsh.Position - handle.Position) -- handle-local
	if dir.Magnitude < 0.05 then return end
	dir = dir.Unit
	local up = (math.abs(dir.Y) > 0.95) and Vector3.new(0, 0, 1) or Vector3.new(0, 1, 0)
	tool.Grip = CFrame.lookAt(Vector3.zero, dir, up) -- LookVector (-Z, "forward") ends up along the marshmallow
end

-- pick the template: YOUR model if one exists, otherwise the code-built stick above.
local function buildStickTemplate()
	local src = findStickSource()
	if src then
		local tmpl = src:IsA("Tool") and src:Clone() or wrapAsTool(src:Clone())
		if tmpl then
			tmpl.Name = "Marshmallow Stick"
			tmpl.CanBeDropped = false
			tmpl.RequiresHandle = tmpl:FindFirstChild("Handle") ~= nil
			tmpl.ToolTip = "Roast it over the fire"
			local marsh = normalizeMarsh(tmpl)
			tmpl:SetAttribute("Roast", 0)
			tmpl:SetAttribute("HasMarsh", true)
			aimStick(tmpl)
			print(("[Campfire] using your '%s' as the roasting stick (marshmallow part: %s)")
				:format(src.Name, marsh and marsh.Name or "NONE FOUND -- roasting won't recolour"))
			return tmpl
		end
	end
	local code = buildCodeStick() -- fallback
	aimStick(code)
	return code
end

-- built LAZILY on the first pickup, not at load -- so your model has definitely streamed/synced in by then.
local stickTemplate
local function getStickTemplate()
	if not stickTemplate then stickTemplate = buildStickTemplate() end
	return stickTemplate
end

-- a STATIC copy of the real stick, for the pickup holder to show (so the display matches what you get).
function plantDisplayStick(parentModel, cf) -- assigns the forward-declared local
	local clone = getStickTemplate():Clone()               -- a Tool
	local handle = clone:FindFirstChild("Handle", true)     -- recursive: Handle may be nested
	local holder = Instance.new("Model"); holder.Name = "DisplayStick"; holder.Parent = parentModel
	for _, d in ipairs(clone:GetDescendants()) do          -- snapshot; safe to reparent while iterating
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanTouch = false; d.CanQuery = false
			d.Parent = holder -- reparent preserves world CFrame; anchored parts stay put on their own
		end
	end
	clone:Destroy()
	if handle and handle.Parent == holder then
		holder.PrimaryPart = handle
		holder:PivotTo(cf) -- move the whole replica to the plant spot
	elseif holder.PrimaryPart == nil then
		local anyPart = holder:FindFirstChildWhichIsA("BasePart")
		if anyPart then holder.PrimaryPart = anyPart; holder:PivotTo(cf) end
	end
	return holder
end

-- who's holding a live stick, so the leash + buttons can find it; roasting = the Go button is engaged.
local heldStick = {} -- [player] = tool
local roasting  = {} -- [player] = true while cooking (Go pressed, Stop clears it)

-- EAT: bank the result for how done it is, take the marshmallow -- and KEEP THE STICK. Eating used to
-- destroy the whole tool, which meant one marshmallow per stick and a fresh trip to the bucket for a whole
-- new stick each time. Now the stick stays in your hand and you walk back for another marshmallow, which is
-- both what a real campfire does and what makes a second helping worth going and getting.
--
-- Only the Eat BUTTON calls this (never a screen tap -- the tool deliberately has no Activated handler).
-- Two guards against a double payout: no marshmallow means nothing to eat, and a short lock on the tool
-- absorbs a double-tap or a leftover duplicate script answering the same press.
local function eatStick(player)
	local tool = heldStick[player]
	if not tool then return end
	if not hasMarsh(tool) then
		flashOverhead(player, "\xF0\x9F\x8D\xA1 No marshmallow -- grab one from the bucket", Color3.fromRGB(255, 205, 130))
		return
	end
	local now = os.clock()
	if (tool:GetAttribute("EatAt") or -1) + 0.5 > now then return end -- same press answered twice
	tool:SetAttribute("EatAt", now)
	roasting[player] = nil
	local r = tool:GetAttribute("Roast") or 0
	local msg, coins, tint = roastResult(r)
	creditCoins(player, coins)
	flashOverhead(player, msg .. " +" .. coins, tint)

	-- ===== EASTER EGG: THE OTHER END -- get it PERFECT and there is a title for that too =====
	-- Burnt Offering rewards ignoring the game. This rewards the opposite: watching the marshmallow and
	-- pulling it off at the right moment. Together they cover both ways of caring about the roast, and the
	-- only way to earn neither is to eat it half-toasted without paying attention.
	--
	-- NARROWER THAN THE GOLDEN BAND ON PURPOSE. roastResult calls 42..72 golden, which is a 30-point window
	-- and about four seconds over the fire -- you land in it by accident. The title wants the MIDDLE of it,
	-- so it takes actually looking at the colour rather than counting. Widen PERFECT_LO/HI if it proves too
	-- fussy; they are the only two numbers involved.
	local PERFECT_LO, PERFECT_HI = 54, 64
	if r >= PERFECT_LO and r <= PERFECT_HI and not player:GetAttribute("GoldenTouch") then
		player:SetAttribute("GoldenTouch", true)
		-- NOT granted as a permanent title -- see the campfire-title loop further down. The attribute above
		-- is the whole record of having earned it; wearing it is handled by standing near a fire.
		task.delay(2.2, function()
			if player.Parent then
				flashOverhead(player, "ð TITLE UNLOCKED: Golden Touch", Color3.fromRGB(255, 214, 110))
			end
		end)
		print(("[Campfire] %s roasted a marshmallow to %d -- dead centre. Golden Touch unlocked"):format(player.Name, r))
	end

	-- ===== EASTER EGG: eat one BURNT TO A CRISP and you get a title for it =====
	-- Burning a marshmallow is the worst outcome the roast has -- it pays the same 1 coin as raw and the
	-- message tells you off for it. So it is the one result nobody reaches on purpose, which makes it a
	-- perfect thing to reward: you only find this by ignoring the game telling you to stop.
	--
	-- ONCE PER PLAYER, checked on the attribute rather than a table, so it survives a respawn and cannot be
	-- farmed by standing at the fire. Titles never touch flight, gas or coins -- it is pure brag.
	if r >= 92 and not player:GetAttribute("BurntOffering") then
		player:SetAttribute("BurntOffering", true)
		-- Recorded, not worn. The campfire-title loop below puts it over your head while you are at a fire.
		task.delay(2.2, function()   -- after the roast result has had its moment
			if player.Parent then
				flashOverhead(player, "ð TITLE UNLOCKED: Burnt Offering", Color3.fromRGB(255, 170, 60))
			end
		end)
		print("[Campfire] " .. player.Name .. " burnt a marshmallow to a crisp -- Burnt Offering unlocked")
	end
	setMarsh(tool, false) -- marshmallow gone, stick stays -- go get another from the bucket
end

function giveStick(player) -- assigns the forward-declared local above
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local bp   = player:FindFirstChildOfClass("Backpack")
	if not (char and hum and bp) then return end
	-- ALREADY HOLDING A STICK? Then this is a REFILL, not a new stick. Because eating keeps the stick, coming
	-- back to the bucket has to put a fresh marshmallow on the one you are already holding -- the old code
	-- just returned here, which made the stick a one-shot and the second trip do nothing at all.
	local existing = char:FindFirstChild("Marshmallow Stick") or bp:FindFirstChild("Marshmallow Stick")
	if existing then
		heldStick[player] = existing -- re-adopt: the table drifts after a respawn or a transient reparent
		roasting[player]  = nil
		if hasMarsh(existing) then
			flashOverhead(player, "\xF0\x9F\x8D\xA1 You already have a marshmallow", Color3.fromRGB(255, 225, 160))
		else
			setMarsh(existing, true)
			flashOverhead(player, "\xF0\x9F\x8D\xA1 Fresh marshmallow!", Color3.fromRGB(255, 245, 225))
		end
		pcall(function() hum:EquipTool(existing) end) -- no hotbar in this game, so put it back in hand
		return
	end

	local tool = getStickTemplate():Clone()

	-- NOTE: deliberately NO Tool.Activated -> eat. Tapping/clicking the screen activates a held tool, and we
	-- do NOT want a stray tap to eat the marshmallow (and pop the HUD back). Only the Eat BUTTON eats.

	tool.AncestryChanged:Connect(function(_, parent)
		if not parent and heldStick[player] == tool then heldStick[player] = nil; roasting[player] = nil end
	end)

	setMarsh(tool, true) -- explicit: a brand-new stick always arrives with a raw marshmallow on it
	tool.Parent = bp
	heldStick[player] = tool
	roasting[player]  = nil -- starts NOT cooking; you press Go to begin
	-- AUTO-EQUIP: the Backpack CoreGui is disabled game-wide (no hotbar), so a tool in the pack is unreachable.
	pcall(function() hum:EquipTool(tool) end)
end

-- Distance from a point to the NEAREST flame (or math.huge if there are none).
--
-- DECLARED HERE, ABOVE THE HANDLER THAT USES IT, AND THAT POSITION IS LOAD-BEARING. It used to live ~70
-- lines further down. A `local` is only visible to code written after it, so from inside the button handler
-- below the name resolved as a GLOBAL instead -- nil -- and the first press threw "attempt to call a nil
-- value", killing the handler before it reached any of the four actions. Every button went dead at once.
--
-- The roasting loop further down calls it too, and worked fine, because that loop IS written after the old
-- declaration. That is what made the break look like a UI problem rather than a scoping one.
local function nearestFlameDist(pos)
	local best = math.huge
	for _, flame in ipairs(FLAMES) do
		if flame.Parent then best = math.min(best, (pos - flame.Position).Magnitude) end
	end
	return best
end

-- Go / Stop / Eat / Remove, from the on-screen buttons.
stickRemote.OnServerEvent:Connect(function(player, action)
	local tool = heldStick[player]
	-- RESYNC FALLBACK: heldStick can drift out of sync with the ACTUAL stick you're holding -- a respawn or a
	-- transient reparent nil-fires AncestryChanged and clears it, and giveStick then early-returns because a
	-- stick already exists, so it never re-populates the table. That left the player unable to Stop/Eat/Remove
	-- even though the client still shows the buttons (the client keys off the real tool). If the tracked tool is
	-- gone, find the real "Marshmallow Stick" in the character/backpack and re-adopt it so the buttons work.
	if not tool or not tool.Parent then
		local char = player.Character
		local bp   = player:FindFirstChildOfClass("Backpack")
		tool = (char and char:FindFirstChild("Marshmallow Stick"))
			or (bp and bp:FindFirstChild("Marshmallow Stick"))
		heldStick[player] = tool -- re-adopt (or leave nil if a stick genuinely isn't held anymore)
	end
	-- NOT SILENT. This used to be a bare `return`, and that is the single worst failure mode a button can
	-- have: the press is received, rejected, and nothing whatsoever happens on screen. Every one of the four
	-- buttons dies at once and it looks identical to "the remote never arrived", which is what sent the last
	-- two rounds of debugging down the wrong hole. If we refuse, we say so, out loud, on the player's head
	-- AND in the log with the state that caused it.
	print(("[Campfire] press '%s' from %s -- tool=%s roasting=%s"):format(
		tostring(action), player.Name, tostring(tool and tool:GetFullName() or "NONE"),
		tostring(roasting[player] == true)))
	if not tool then
		flashOverhead(player, "\xF0\x9F\x8D\xA1 You aren't holding the marshmallow stick", Color3.fromRGB(255, 205, 130))
		warn("[Campfire] '" .. tostring(action) .. "' REFUSED for " .. player.Name ..
			" -- no 'Marshmallow Stick' tool in character or backpack. Take one from the campfire prompt first.")
		return
	end

	-- ===== EVERY ACTION IS VALIDATED HERE, ON THE SERVER =====
	-- The client greys the buttons it knows are illegal, but greying is a COURTESY, not a control: a crafted
	-- FireServer can send any action at any time from anywhere. So each one re-checks the two things that
	-- actually matter -- are you close enough to this fire, and is the action legal for the stick's state --
	-- and says WHY it refused rather than failing silently.
	local function inRange()
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		return hrp ~= nil and nearestFlameDist(hrp.Position) <= REST_RADIUS
	end
	local function refuse(msg)
		flashOverhead(player, msg, Color3.fromRGB(255, 205, 130))
	end

	if action == "roast" then
		if not hasMarsh(tool) then return refuse("\xF0\x9F\x8D\xA1 Nothing on the stick -- grab one from the bucket") end
		if roasting[player] then return refuse("Already roasting!") end
		if not firesLit then return refuse("\xF0\x9F\x8C\xA7 The fire is out") end
		if not inRange() then return refuse("Get closer to the fire") end
		roasting[player] = true
		tool:SetAttribute("Roasting", true) -- replicates: the client greys Roast and un-greys Stop off this

	elseif action == "stop" then
		if not roasting[player] then return refuse("You aren't roasting anything") end
		roasting[player] = nil
		tool:SetAttribute("Roasting", false)
		-- STOP FREEZES IT WHERE IT IS. Roast and the marshmallow's colour are deliberately left alone, so the
		-- browning you earned stays earned and you can eat it at exactly the shade you pulled it out at.
		--
		-- This USED to reset it to white, on the reasoning that keeping the colour makes Stop a free "bank my
		-- progress" button -- toast to perfect, stop, never risk burning. That is true, and it is the wrong
		-- trade for this game: a marshmallow is not a boss fight, and wiping ten seconds of a child's work for
		-- tapping the wrong button reads as the button being broken, not as a rule. Stop now means stop.
		--
		-- Nothing else has to change for this to work. The cook loop only advances Roast while roasting[player]
		-- is set, so freezing is just not-advancing; pressing Roast again resumes from the current shade rather
		-- than starting over; and Eat already gates on Roast >= RAW_UNTIL with no opinion about whether the
		-- stick is still over the fire.
		local shade = tool:GetAttribute("Roast") or 0
		if shade >= RAW_UNTIL then
			flashOverhead(player, "\xE2\x9C\x8B Stopped -- ready to eat!", Color3.fromRGB(180, 235, 170))
		else
			flashOverhead(player, "\xE2\x9C\x8B Stopped -- still raw, roast it more", Color3.fromRGB(200, 210, 225))
		end

	elseif action == "eat" then
		if not hasMarsh(tool) then return refuse("\xF0\x9F\x8D\xA1 No marshmallow -- grab one from the bucket") end
		if (tool:GetAttribute("Roast") or 0) < RAW_UNTIL then
			-- RAW IS NOT FOOD. roastResult already calls anything under this "Still raw!", so eating it was
			-- paying out a coin for doing nothing -- and it taught players that the fire is optional.
			return refuse("\xF0\x9F\x8D\xA1 Still raw -- hold it over the fire first")
		end
		if not inRange() then return refuse("Get closer to the fire") end
		eatStick(player)
		tool:SetAttribute("Roasting", false)

	elseif action == "remove" then
		-- Put the stick down: no eat, no reward. Destroying the tool is what hands the bottom buttons back --
		-- the HUD authority in CoreClient only hides them while you are holding a stick AT a fire, so the gut
		-- pill / gas meter / BUY FOOD return within a quarter-second, exactly as if you had walked away.
		heldStick[player] = nil; roasting[player] = nil
		tool:Destroy()
		flashOverhead(player, "\xF0\x9F\x97\x91 Put the stick back", Color3.fromRGB(255, 170, 150))

	else
		-- An action string this build does not know. That means the press came from a STALE DUPLICATE client
		-- baked into the place, firing an older vocabulary at the current server -- which lands here and does
		-- nothing, silently, forever. Name it so the duplicate can be found and deleted.
		warn("[Campfire] UNKNOWN action '" .. tostring(action) .. "' from " .. player.Name ..
			" -- this is almost certainly a stale duplicate Campfire client script. Delete it in Studio.")
	end
end)

-- Resting = fires lit, alive, roughly still, and within REST_RADIUS of ANY of the campfires.
local function restingAtAny(player)
	if not firesLit then return false end -- rained out -> no warming up
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum) or hum.Health <= 0 then return false end
	if hrp.AssemblyLinearVelocity.Magnitude > STILL_SPEED then return false end -- moving fast = passing through
	return nearestFlameDist(hrp.Position) <= REST_RADIUS
end


-- ============================================================================================================
-- CAMPFIRE TITLES ARE WORN AT THE CAMPFIRE, AND NOWHERE ELSE
-- ============================================================================================================
-- Burnt Offering and Golden Touch are earned by roasting, so they are shown while you are roasting. Carrying
-- a marshmallow title around Pizza Palms would say nothing to anyone up there; standing at the fire wearing
-- it says everything, because everyone else at that fire is doing the exact thing it is about. It is also
-- what keeps them out of the way of the pet-collection titles, which ARE meant to be worn everywhere.
--
-- BOTH AT ONCE if you have both. They are opposite ends of the same skill -- the person who has burnt one to
-- charcoal AND hit the dead centre has done the whole roast, and that pair is worth more than either half.
--
-- SAVE AND RESTORE, never overwrite. Whatever title a player was already wearing is stashed on arrival and
-- put back on the way out. The restore is guarded on the title still BEING ours: if something else changed it
-- while the player stood at the fire (a pet milestone landing, say) that new title is the current truth and
-- stamping the old one back over it would silently undo another system's work.
local cfSavedTitle = {}   -- [player] = the title they wore before reaching a fire (false = wore none)

local function campfireTitleFor(player)
	local burnt  = player:GetAttribute("BurntOffering")
	local golden = player:GetAttribute("GoldenTouch")
	-- Golden first: it is the harder of the two, and the eye reads the front of the string.
	if golden and burnt then return "Golden Touch / Burnt Offering" end
	if golden then return "Golden Touch" end
	if burnt  then return "Burnt Offering" end
	return nil
end

task.spawn(function()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			local mine = campfireTitleFor(player)
			local char = player.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			-- DISTANCE ONLY -- not restingAtAny(). That one also demands you be still and the fires lit, and
			-- neither should hide a title: you want it visible while you are walking round the fire choosing
			-- a seat, and still visible after a storm has doused the flames.
			local near = mine and hrp and nearestFlameDist(hrp.Position) <= REST_RADIUS

			if near and cfSavedTitle[player] == nil then
				cfSavedTitle[player] = player:GetAttribute("Title") or false
				player:SetAttribute("Title", mine)
			elseif near then
				-- Re-assert every pass, cheaply: earning the second title while stood at the fire has to
				-- upgrade the label there and then, not on the next visit.
				if player:GetAttribute("Title") ~= mine then player:SetAttribute("Title", mine) end
			elseif cfSavedTitle[player] ~= nil then
				local saved = cfSavedTitle[player]
				cfSavedTitle[player] = nil
				if player:GetAttribute("Title") == mine or mine == nil then
					player:SetAttribute("Title", saved or nil)
				end
			end
		end
		task.wait(0.5)   -- a title appearing within half a second of arriving is instant enough
	end
end)

Players.PlayerRemoving:Connect(function(player) cfSavedTitle[player] = nil end)

-- ONE payout loop for the whole set of campfires -- you earn at whichever one you're sitting by.
local function runPayout()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			if restingAtAny(player) then
				local since = restedSince[player]
				if not since then since = os.clock(); restedSince[player] = since end
				local minutes = math.floor((os.clock() - since) / 60)
				local coins = math.min(MAX_COINS, BASE_COINS + minutes * BONUS_PER_MIN)
				creditCoins(player, coins)
				-- (no "warming up" pill: the CampfireResting/CampfireRate attributes are intentionally NOT set,
				-- so even a stale client can't render the pill. Resting still credits coins silently.)
			elseif restedSince[player] then
				restedSince[player] = nil
			end
		end
		task.wait(TICK)
	end
end

-- how far from the campfire you may wander before the stick is taken away
local STICK_LEASH = 30

-- ROASTING loop: while the Go button is engaged AND you're at a campfire, brown the marshmallow. Also
-- takes the stick back if you wander more than STICK_LEASH studs off (no roaming the map with it).
local function runRoasting()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			local char  = player.Character
			local hrp   = char and char:FindFirstChild("HumanoidRootPart")
			local tool  = char and char:FindFirstChild("Marshmallow Stick")
			local marsh = tool and tool:FindFirstChild("Marshmallow")

			if tool and hrp and nearestFlameDist(hrp.Position) > STICK_LEASH then
				-- walked off -> drop the marshmallow, take the stick back
				heldStick[player] = nil; roasting[player] = nil
				flashOverhead(player, "\xF0\x9F\x8D\xA1 You left the campfire", Color3.fromRGB(255, 170, 90))
				tool:Destroy() -- the tool goes with it, so its Roasting attribute goes too
			elseif marsh and hasMarsh(tool) and firesLit and roasting[player] and hrp and nearestFlameDist(hrp.Position) <= REST_RADIUS then
				-- fires must be LIT to cook -- a rained-out fire won't roast anything
				local r = math.min(100, (tool:GetAttribute("Roast") or 0) + ROAST_STEP)
				tool:SetAttribute("Roast", r)
				marsh.Color = marshColor(r)
			end
		end
		task.wait(ROAST_DT)
	end
end

Players.PlayerRemoving:Connect(function(p) restedSince[p] = nil; heldStick[p] = nil; roasting[p] = nil end)

-- WEATHER: a THUNDERSTORM douses every campfire. When it ends, the logs take 10 seconds to DRY OUT (sign
-- counts it down) before the fire catches again. Reads the ActiveServerEvent attribute PlayerStats sets.
local DRY_SECS = 10
local function runWeather()
	local wasStorm = false
	while true do
		local storm = Workspace:GetAttribute("ActiveServerEvent") == "THUNDERSTORM"
		if storm and not wasStorm then
			setFiresLit(false) -- out you go
		elseif (not storm) and wasStorm then
			-- storm just ended -> dry-out countdown, then relight (unless the storm comes back mid-dry)
			task.spawn(function()
				for t = DRY_SECS, 1, -1 do
					if Workspace:GetAttribute("ActiveServerEvent") == "THUNDERSTORM" then return end -- storm restarted
					setSignText(("\xF0\x9F\x92\xA7 Drying out...\nready in %ds"):format(t))
					task.wait(1)
				end
				if Workspace:GetAttribute("ActiveServerEvent") ~= "THUNDERSTORM" then setFiresLit(true) end
			end)
		end
		wasStorm = storm
		task.wait(1)
	end
end

-- PRUNE DUPLICATE FIRES ---------------------------------------------------------------------------------
-- Destroying a stale script does not undo what it already built. Two stale copies each built their own set of
-- 4 campfires on the SAME spots before we could reach them -- 12 models stacked three deep, each with its own
-- "Take a Marshmallow" prompt, so one keypress hit three prompts and three leash loops fought over your stick.
--
-- Ours carry a BuiltByLiveScript stamp; anything named Campfire without one came from a copy that should not
-- be running. Refuses to do anything unless at least one of OUR fires exists, so a failed build can never
-- leave the island with no campfire at all.
local function pruneDuplicateFires()
	local mine = 0
	for _, m in ipairs(Workspace:GetChildren()) do
		if m.Name == "Campfire" and m:GetAttribute("BuiltByLiveScript") then mine = mine + 1 end
	end
	if mine == 0 then return end -- we have not built yet (or the build failed) -- leave every fire alone
	local removed = 0
	for _, m in ipairs(Workspace:GetChildren()) do
		if m.Name == "Campfire" and m:GetAttribute("CampfireSpot") and not m:GetAttribute("BuiltByLiveScript") then
			pcall(function() m:Destroy() end)
			removed = removed + 1
		end
	end
	if removed > 0 then
		warn(("[Campfire] removed %d duplicate campfire model(s) left behind by stale script copies (kept %d)")
			:format(removed, mine))
	end
end

--------------------------------------------------------------------------------
-- NIGHT ON BEAN FARM, AND THE STORIES THE ANIMALS TELL BY THE FIRE
--------------------------------------------------------------------------------
-- Every NIGHT_PERIOD seconds Bean Farm has a night: a SUNSET_SECS sunset that eases the sky down, DARK_SECS
-- of full dark, then a SUNRISE_SECS sunrise back to day. It runs on the WALL CLOCK (os.time), not server
-- uptime, so every server in the game has night at the same moment and a friend joining from another server
-- sees what you see. This file only PUBLISHES it -- as Workspace attributes:
--   NightFactor   0..1   how dark it is right now (0 day, 1 full night; ramps through sunset and sunrise)
--   BeanFarmNight bool   true from the first second of sunset to the last second of sunrise
--   NightSecondsLeft / NextNightIn   for anything that wants to show a countdown
-- SkyByAltitude (client) reads NightFactor and pulls the low sky to night; above island 2 the altitude curve
-- owns the darkness exactly as before. The pig and the cow read BeanFarmNight + StoryFirePos and walk to
-- the fire (their own scripts; nothing here moves them).
--
-- THE STORIES. When both animals are at the story fire and somebody is sitting by it, they tell each other
-- one of EIGHT long stories through the speech bubbles they already have, a line every LINE_SECONDS. They
-- run FORTY lines -- about two minutes each, three in a night -- because a six-line story is a joke, not a
-- story (see the note on STORIES below). One counts as HEARD for every player within REST_RADIUS of the fire
-- when its last line lands. Hear all eight and you wear "Fireside". Heard stories are saved per player (own store, honours
-- the fresh-player test flag), so they drip out over several nights instead of one long sit -- that is the
-- reason to come back after dark. The story picked is the one the fewest people present have heard, so a newcomer at
-- a busy fire still gets a new one.
local NIGHT_PERIOD = 25 * 60   -- one night every 25 minutes
local SUNSET_SECS  = 60        -- the sky eases down over a minute...
local DARK_SECS    = 390       -- ...stays fully dark for six and a half...
local SUNRISE_SECS = 60        -- ...and eases back up over a minute (8.5 min of "night" in all)
local NIGHT_TOTAL  = SUNSET_SECS + DARK_SECS + SUNRISE_SECS
local STORY_RANGE  = 18        -- both animals must be within this of the flame before a story starts
-- ===== HOW FAST THEY TALK =====
-- Retuned twice on 2026-09-06: 6s read as two animals waiting for each other, and 4s still did. 4s was a hard
-- floor only because the animals' speech bubble held every line for a fixed SEVEN seconds -- speakers alternate,
-- so an animal speaks again every 2 x LINE_SECONDS, and any faster meant the previous hide fired over the new
-- line and blanked it mid-sentence. So the hold is now OURS: `say` takes an optional duration and the stories
-- pass BUBBLE_HOLD. Ambient one-liners still get 7s by default.
--
-- KEEP BUBBLE_HOLD BELOW 2 x LINE_SECONDS. That is the whole constraint; 0.5s of margin is enough.
local LINE_SECONDS = 2.5       -- a line lands this long after the last -- a back-and-forth, not a recital
local BUBBLE_HOLD  = 4.5       -- < 2 x LINE_SECONDS (5.0), so a bubble always clears before its owner speaks again
local STORY_GAP    = 14        -- breath between stories. Longer now the stories are 40 lines: three of them
                               -- fill a 6-7 minute night with a real pause between, instead of five short ones
                               -- running into each other
local PUNCH_PAUSE  = 1.1       -- extra beat before the LAST line of a story. Every story ends on the other
                               -- animal's reaction, and a punchline delivered on the metronome is not a
                               -- punchline -- the pause is what makes it land

-- ===== /night: SHIFT THE CLOCK, DO NOT BYPASS IT =====
-- The test command works by moving the cycle's PHASE, not by setting a "forced" flag that the rest of the
-- file then has to check everywhere. `nightOffset` is added to the wall clock, so /night is "pretend it is
-- 25 minutes later" -- every reader (the sky, the animals, the stories, the countdown) sees one consistent
-- time, the sunset and sunrise still run in full, and night ends on its own the way it always would. A
-- forced flag would have skipped the ramps and left the sky snapping between day and dark.
--
-- SERVER-WIDE and not per-player, because the animals, the fire and the sky are one shared world -- there is
-- no coherent way for it to be night for one person at the same fire. Allow-list gated like every other test
-- command here.
--
-- ===== THE CYCLE IS ANCHORED TO SERVER START, NOT TO THE WALL CLOCK =====
-- It used to be `os.time() % NIGHT_PERIOD`, which meant the phase depended on what time of day the server
-- happened to boot -- and NIGHT_TOTAL/NIGHT_PERIOD of the time (about one boot in three) that landed inside
-- the night window, so a player pressed PLAY and Bean Farm was already dark. Joining into a pitch-black farm
-- is the worst possible first frame of this game: the first thing anyone should see is the bright farm.
--
-- So the clock counts from BOOT and starts at NIGHT_TOTAL, which is the first daylight second. Every server
-- therefore opens in DAY and the first sunset is a full daylight stretch away (NIGHT_PERIOD - NIGHT_TOTAL,
-- about 16 minutes), then it is every NIGHT_PERIOD after that, forever. A player who joins a server that has
-- been up a while still arrives mid-night if it is night -- that is correct, it is a shared world; what is
-- fixed is that night can no longer be waiting for the very first player.
local BOOT = os.time()
local nightOffset = 0
local function rawPhase() return (os.time() - BOOT) + NIGHT_TOTAL end
local function clock() return rawPhase() + nightOffset end

-- 0..1 darkness for the current wall-clock second, with the ramps.
local function nightFactor()
	local t = clock() % NIGHT_PERIOD
	if t < SUNSET_SECS then return t / SUNSET_SECS end
	if t < SUNSET_SECS + DARK_SECS then return 1 end
	if t < NIGHT_TOTAL then return 1 - (t - SUNSET_SECS - DARK_SECS) / SUNRISE_SECS end
	return 0
end
local function isNight() return (clock() % NIGHT_PERIOD) < NIGHT_TOTAL end
local function nightEndsIn() return math.max(0, NIGHT_TOTAL - (clock() % NIGHT_PERIOD)) end
local function nextNightIn() return NIGHT_PERIOD - (clock() % NIGHT_PERIOD) end

-- Jump the phase to a named moment. Each one lands a couple of seconds INTO its phase rather than exactly on
-- the boundary, so a one-second poll cannot miss it and report the phase before.
local NIGHT_MARKS = {
	night   = 1,                                  -- sunset starts now (the full ramp down, then dark)
	dark    = SUNSET_SECS + 1,                    -- straight to full dark, skipping the sunset
	sunrise = SUNSET_SECS + DARK_SECS + 1,        -- straight to the ramp back up
	day     = NIGHT_TOTAL + 1,                    -- daylight, next sunset a full period away
}
local function setNightPhase(target)
	local at = NIGHT_MARKS[target]
	if not at then return false end
	-- offset such that clock() % PERIOD == at -- measured off the BOOT-anchored phase, not the wall clock
	nightOffset = (at - (rawPhase() % NIGHT_PERIOD)) % NIGHT_PERIOD
	return true
end

local storyFlame = nil
local function pickStoryFire()
	if #FLAMES == 0 then return end
	local sd = _G.islandStandData and _G.islandStandData[1]
	local ref = sd and Vector3.new(sd.x, sd.y, sd.z)
	if not ref then
		local island = findIsland()
		local spawn = island and island:FindFirstChildWhichIsA("SpawnLocation", true)
		ref = spawn and spawn.Position
	end
	local best, bestD = FLAMES[1], math.huge
	if ref then
		for _, f in ipairs(FLAMES) do
			local d = (f.Position - ref).Magnitude
			if d < bestD then best, bestD = f, d end
		end
	end
	storyFlame = best
	Workspace:SetAttribute("StoryFirePos", best.Position)
	print(("[Fireside] story fire is the one at %s (%s) -- the pig and the cow gather here at night")
		:format(tostring(best.Position), ref and ("%.0f studs from island 1's stand"):format(bestD) or "stand not found: first fire"))
end

local function runNight()
	local was = nil
	while true do
		local on = isNight()
		if on ~= was then
			was = on
			Workspace:SetAttribute("BeanFarmNight", on)
			if on then
				print(("[Fireside] SUNSET on Bean Farm -- %d min of night ahead; the animals head for the fire"):format(math.floor(NIGHT_TOTAL / 60)))
			else
				print(("[Fireside] daylight on Bean Farm -- next sunset in %d min"):format(math.floor(nextNightIn() / 60)))
			end
		end
		Workspace:SetAttribute("NightFactor", nightFactor())
		Workspace:SetAttribute("NightSecondsLeft", on and nightEndsIn() or 0)
		Workspace:SetAttribute("NextNightIn", nextNightIn())
		task.wait(1)
	end
end

-- ===== EIGHT STORIES: THE HISTORY OF FART TO FLOAT =====
-- ===== THEY ARE LONG. THAT IS THE WHOLE POINT. =====
-- This started as forty stories of six lines and was rewritten three times before the real problem showed:
-- six lines of forty characters is under 300 characters, and 300 characters is a joke, not a story. A story
-- needs somebody to happen to, a thing that goes wrong, a middle where it gets worse, and a turn at the end
-- you did not see coming. That does not fit in six lines and no amount of better wording makes it fit.
--
-- So: EIGHT stories of FORTY LINES. About two minutes each at LINE_SECONDS, which with STORY_GAP is three in
-- a 6-7 minute night -- the pacing the fire was asked for. A player who sits down hears one whole thing.
--
-- THEY SHARE A WORLD. Bell eats the harvest nobody would buy and the hill lets go of him; his fourteen
-- resting places are the islands. The blimp's book has his line crossed out with one word after it. The girl
-- from Milk Marsh goes through the hole above Pizza Palms and comes home to the same buckets. The stranger
-- with seven stomachs sells the iron one to a man he knows will never come down, then leaves the money in
-- the garden box. Told in any order they still add up, which is what makes it a history and not trivia.
--
-- ONE POOL PER ANIMAL, and the TELLER owns its pool. The cow tells the deep history -- it has stood in this
-- field longer than anyone who climbs -- and the pig tells the recent, ground-level, gossipy half: Sal and
-- the unlabelled can, the churn nobody switched off, the fifth gnome, the board round the back of the plaza.
-- Tellers alternate, so neither holds the fire two stories running.
--
-- THE LISTENER ALWAYS CLOSES. The teller speaks on the odd lines, so the last line is the other animal
-- realising something -- that is where a story pays off. Line counts MUST be even or the teller closes its
-- own story, and the asserts in tools' generator are there for exactly that.
--
-- KEEP IT TRUE TO THE GAME. Fourteen islands, beans first and pizza last, seven guts, coins per stud, the
-- blimp, the OG board, the black hole, Milk Marsh, the Butter Swamp, the buried gnome and his waiting
-- brother, Sal's rocket gas, the secret MOST FARTS board. Invent freely INSIDE that -- never against it.
--
-- SPEAKERS ALTERNATE INSIDE A STORY TOO, and that is a hard rule, not a style: the bubble holds BUBBLE_HOLD
-- seconds and an animal speaks again every 2 x LINE_SECONDS, so two lines in a row would blank the first.
-- Keep every line under ~45 characters -- that is what fits the bubble in two rows.
local STORIES = {
	cow = {
		{ id = "cow_bell", lines = {
			{ "cow", "Sit down. This one is long." },
			{ "pig", "I am sitting. I am always sitting." },
			{ "cow", "I am going to tell you about Bell." },
			{ "pig", "You have never told me about Bell." },
			{ "cow", "You never asked at the right time of day." },
			{ "pig", "It is night. I am not going anywhere." },
			{ "cow", "Then. Bell had this field before us." },
			{ "pig", "Before the farm?" },
			{ "cow", "Before the tower. There was no tower." },
			{ "pig", "What was up there instead?" },
			{ "cow", "A hill. This hill. And a lot of sky." },
			{ "pig", "Nothing you could stand on?" },
			{ "cow", "Birds. Weather. Nothing that held still." },
			{ "pig", "And Bell farmed the hill." },
			{ "cow", "Beans. He was not good at it." },
			{ "pig", "How bad can a bean be?" },
			{ "cow", "Small. Grey. They rattled in the sack." },
			{ "pig", "Did anybody buy them?" },
			{ "cow", "One man once, and he came back angry." },
			{ "pig", "So what does he do with a whole harvest?" },
			{ "cow", "He sat down out here and began eating." },
			{ "pig", "Out of stubbornness?" },
			{ "cow", "Out of hunger. Nobody had paid him." },
			{ "pig", "How long did that take?" },
			{ "cow", "All evening. He finished after dark." },
			{ "pig", "And then?" },
			{ "cow", "And then the hill let go of him." },
			{ "pig", "The hill let GO?" },
			{ "cow", "He went up. Slowly, at first." },
			{ "pig", "Was he shouting?" },
			{ "cow", "Laughing. That is what they wrote down." },
			{ "pig", "Who is they?" },
			{ "cow", "Whoever was watching. There were four." },
			{ "pig", "Did he ever land?" },
			{ "cow", "Fourteen times. Each one is still there." },
			{ "pig", "The ISLANDS?" },
			{ "cow", "Each is where he stopped for breath." },
			{ "pig", "The whole tower is one man resting?" },
			{ "cow", "And everyone since is following him up." },
			{ "pig", "...I will never look at beans the same." } } },
		{ id = "cow_stranger", lines = {
			{ "cow", "A stranger came DOWN the road once." },
			{ "pig", "Down? Nobody ever comes down." },
			{ "cow", "He did. On foot. In the rain." },
			{ "pig", "Down from where?" },
			{ "cow", "He would not say. His boots were burnt." },
			{ "pig", "Burnt how?" },
			{ "cow", "Through. Both soles. He walked anyway." },
			{ "pig", "What did he want with us?" },
			{ "cow", "A fence to lay things out on. Ours." },
			{ "pig", "Lay WHAT out?" },
			{ "cow", "Seven stomachs. In a sack. By size." },
			{ "pig", "...Say that again." },
			{ "cow", "Tiny at one end. Iron at the other." },
			{ "pig", "Whose stomachs were they?" },
			{ "cow", "He never said that either." },
			{ "pig", "Did anybody actually buy one?" },
			{ "cow", "A queue formed before he had finished." },
			{ "pig", "For how much?" },
			{ "cow", "Coins. And one promise on top." },
			{ "pig", "What promise?" },
			{ "cow", "That the buyer would come back down." },
			{ "pig", "That is a strange thing to charge." },
			{ "cow", "He said it twice to every one of them." },
			{ "pig", "And did they come back?" },
			{ "cow", "Six did. Small through to double." },
			{ "pig", "And the seventh?" },
			{ "cow", "The iron one. He is still up there." },
			{ "pig", "Still climbing? After all this time?" },
			{ "cow", "There is nothing left for him to buy." },
			{ "pig", "Then what is he climbing FOR?" },
			{ "cow", "That is what the stranger asked him." },
			{ "pig", "He asked the buyer that? Out loud?" },
			{ "cow", "Before he sold it. The man laughed." },
			{ "pig", "And the stranger sold it to him anyway." },
			{ "cow", "He said the iron one finds its own man." },
			{ "pig", "That is a horrible thing to say." },
			{ "cow", "He left the money in the garden box." },
			{ "pig", "...All of it?" },
			{ "cow", "Every coin. Then he walked back up." },
			{ "pig", "...Then I do not know what he was." } } },
		{ id = "cow_ledger", lines = {
			{ "cow", "That blimp is not decoration." },
			{ "pig", "It has never landed in my lifetime." },
			{ "cow", "It lands. Never where you are looking." },
			{ "pig", "What is it up there for?" },
			{ "cow", "There is a book on it." },
			{ "pig", "A book." },
			{ "cow", "One line for everyone who ever climbed." },
			{ "pig", "Saying what?" },
			{ "cow", "A name. And how high they got." },
			{ "pig", "Who agreed to be written down?" },
			{ "cow", "The first one did. He asked for it." },
			{ "pig", "Bell ASKED?" },
			{ "cow", "He wanted one person to see him do it." },
			{ "pig", "That is not vanity. That is lonely." },
			{ "cow", "The keeper has kept it ever since." },
			{ "pig", "There is a keeper?" },
			{ "cow", "Somebody. The lamp moves at night." },
			{ "pig", "Have you ever seen this book?" },
			{ "cow", "Once. Part of it came down in a storm." },
			{ "pig", "It FELL?" },
			{ "cow", "One page. It landed in the beans." },
			{ "pig", "What was written on it?" },
			{ "cow", "Names. Hundreds. Very small writing." },
			{ "pig", "Anybody you knew?" },
			{ "cow", "All of them. Everyone who passed here." },
			{ "pig", "Even the ones who never came back?" },
			{ "cow", "Especially those. Those have a mark." },
			{ "pig", "What sort of mark?" },
			{ "cow", "A small circle. Nothing written after." },
			{ "pig", "...And the first line? Bell's line?" },
			{ "cow", "Crossed out. One straight line through." },
			{ "pig", "Crossed out by WHO?" },
			{ "cow", "The keeper. It is the same neat hand." },
			{ "pig", "Why erase the first man of all of them?" },
			{ "cow", "There is one word written after it." },
			{ "pig", "What word?" },
			{ "cow", "Returned." },
			{ "pig", "...He came back down?" },
			{ "cow", "The book only counts the ones still up." },
			{ "pig", "...Then Bell is somewhere on the ground." } } },
		{ id = "cow_girl", lines = {
			{ "cow", "There is a hole above the top island." },
			{ "pig", "Above Pizza Palms? Above everything?" },
			{ "cow", "A dark one. It turns very slowly." },
			{ "pig", "How would you see it in the dark?" },
			{ "cow", "It is darker than dark. You can tell." },
			{ "pig", "Who found it?" },
			{ "cow", "A girl who grew up on Milk Marsh." },
			{ "pig", "What was she doing that high?" },
			{ "cow", "Working. She carried buckets for a living." },
			{ "pig", "Up and down the whole tower?" },
			{ "cow", "Every day. She knew the gaps by heart." },
			{ "pig", "Then she was not up there by accident." },
			{ "cow", "No. She saved a year to go higher." },
			{ "pig", "To reach the hole on purpose." },
			{ "cow", "She told nobody. She told her mother." },
			{ "pig", "That is telling somebody." },
			{ "cow", "Her mother told me. That is how I know." },
			{ "pig", "What happened when she went in?" },
			{ "cow", "Nothing loud. She simply was not there." },
			{ "pig", "For how long?" },
			{ "cow", "One winter. She came back in spring." },
			{ "pig", "She CAME BACK?" },
			{ "cow", "Thinner. Taller. Very quiet." },
			{ "pig", "What is through it?" },
			{ "cow", "Stars. And more islands, she said." },
			{ "pig", "More islands? Another tower?" },
			{ "cow", "Several. Made of things we do not have." },
			{ "pig", "Then why is she not up there now?" },
			{ "cow", "I asked her that. She thought about it." },
			{ "pig", "And?" },
			{ "cow", "She said one sentence and went home." },
			{ "pig", "What was the sentence?" },
			{ "cow", "There is nobody up there to shout at." },
			{ "pig", "...That is all she said?" },
			{ "cow", "She meant it kindly. She was not sad." },
			{ "pig", "What does she do now?" },
			{ "cow", "Milk. The same buckets. The same route." },
			{ "pig", "After seeing all of that?" },
			{ "cow", "She says the climb was the good part." },
			{ "pig", "...I think I understand her." } } },
	},
	pig = {
		{ id = "pig_sal", lines = {
			{ "pig", "You know Sal lives in a cave." },
			{ "cow", "Everybody knows Sal lives in a cave." },
			{ "pig", "Do you know why?" },
			{ "cow", "Because he sells what he should not." },
			{ "pig", "That is what he WANTS you to think." },
			{ "cow", "Then tell me the real reason." },
			{ "pig", "Sal used to have a stand at the top." },
			{ "cow", "The top? Pizza Palms?" },
			{ "pig", "Best pitch on the whole tower." },
			{ "cow", "What was he selling up there?" },
			{ "pig", "Slices. Honestly. To tired people." },
			{ "cow", "That is not the Sal I have heard of." },
			{ "pig", "It was. Until the can." },
			{ "cow", "What can?" },
			{ "pig", "A can he found. Unlabelled. Heavy." },
			{ "cow", "Found where?" },
			{ "pig", "In the crates that arrive at night." },
			{ "cow", "Nobody ever sees those arrive." },
			{ "pig", "Sal did. Once. He will not say more." },
			{ "cow", "What was in it?" },
			{ "pig", "Rocket gas. Only nobody knew that yet." },
			{ "cow", "So he sold it." },
			{ "pig", "He sold it to a climber in a hurry." },
			{ "cow", "What did he tell him it was?" },
			{ "pig", "That it would save him an hour." },
			{ "cow", "And did it?" },
			{ "pig", "It saved him four. Then it kept saving." },
			{ "cow", "Meaning what, exactly?" },
			{ "pig", "He did not stop. He is still going up." },
			{ "cow", "...Still?" },
			{ "pig", "On a clear night he is a moving dot." },
			{ "cow", "Did Sal know it would do that?" },
			{ "pig", "No. That is the whole problem." },
			{ "cow", "Then it was an accident." },
			{ "pig", "Sal does not believe in accidents." },
			{ "cow", "So he hid." },
			{ "pig", "He packed the stand and came down." },
			{ "cow", "All the way down. To a hole in a rock." },
			{ "pig", "And every night he watches the sky." },
			{ "cow", "...In case his customer comes back." } } },
		{ id = "pig_churn", lines = {
			{ "pig", "The butter swamp is one man's lunch." },
			{ "cow", "A swamp is not a lunch break." },
			{ "pig", "This one is. Island ten. Years ago." },
			{ "cow", "Go on, then." },
			{ "pig", "There was a cook up there. One cook." },
			{ "cow", "Cooking for who?" },
			{ "pig", "Anybody passing. It is a long climb." },
			{ "cow", "Fair enough." },
			{ "pig", "He had a churn. A big one. Iron." },
			{ "cow", "For butter." },
			{ "pig", "For butter. He turned it on at noon." },
			{ "cow", "And went to eat." },
			{ "pig", "He went to eat. He was gone an hour." },
			{ "cow", "And then?" },
			{ "pig", "He came back and it was still going." },
			{ "cow", "So he left it going." },
			{ "pig", "He was pleased with it. He went home." },
			{ "cow", "For the night." },
			{ "pig", "For the night. Then for the week." },
			{ "cow", "...And then?" },
			{ "pig", "Then he retired. He forgot to mention it." },
			{ "cow", "He forgot to mention retiring?" },
			{ "pig", "People do. He was old and he was tired." },
			{ "cow", "So nobody switched the churn off." },
			{ "pig", "Nobody knew whose churn it was." },
			{ "cow", "How long has it been running?" },
			{ "pig", "They stopped counting the years." },
			{ "cow", "Can nobody reach it now?" },
			{ "pig", "Three have tried. It is deep under." },
			{ "cow", "Under the butter it made." },
			{ "pig", "Under all of it. You can hear it, though." },
			{ "cow", "You can HEAR it?" },
			{ "pig", "Stand still on island ten. It thumps." },
			{ "cow", "...That is not a nice thought." },
			{ "pig", "It is the oldest working thing up there." },
			{ "cow", "Older than the boards?" },
			{ "pig", "Older than all of it but the tower." },
			{ "cow", "...And it is making butter for nobody." } } },
		{ id = "pig_gnome", lines = {
			{ "pig", "Count the gnomes in the garden." },
			{ "cow", "Four. I count four every morning." },
			{ "pig", "There were five when I arrived." },
			{ "cow", "You have never mentioned a fifth." },
			{ "pig", "I am mentioning him now." },
			{ "cow", "Was he different from the others?" },
			{ "pig", "Smaller. Red hat. Always at the front." },
			{ "cow", "The front of what?" },
			{ "pig", "Whatever they were doing. He led." },
			{ "cow", "Gnomes do things?" },
			{ "pig", "They measure. That is their work." },
			{ "cow", "Measure what, exactly?" },
			{ "pig", "Every gap in the tower. To the stud." },
			{ "cow", "...The gaps between the islands." },
			{ "pig", "Somebody had to. He did the first four." },
			{ "cow", "So what happened to him?" },
			{ "pig", "Rain. A whole night of it." },
			{ "cow", "The flower bed?" },
			{ "pig", "The bed came down. He was standing in it." },
			{ "cow", "And he went under with it?" },
			{ "pig", "Hat first. Nobody heard a thing." },
			{ "cow", "The others were right there." },
			{ "pig", "Facing the other way. They always are." },
			{ "cow", "How long before anybody noticed?" },
			{ "pig", "A season. A whole season." },
			{ "cow", "Nobody counts the gnomes?" },
			{ "pig", "You do. You counted four this morning." },
			{ "cow", "...I did." },
			{ "pig", "They knew by autumn. Three said nothing." },
			{ "cow", "Why would they say nothing?" },
			{ "pig", "Shame. Or they could not dig him out." },
			{ "cow", "And the fourth one?" },
			{ "pig", "The fourth went and stood by the tree." },
			{ "cow", "The tree with the door in it." },
			{ "pig", "Their door. Their house is under it." },
			{ "cow", "He is waiting for his brother." },
			{ "pig", "Every night since. He does not knock." },
			{ "cow", "Why does he not knock?" },
			{ "pig", "Then he would have to go in alone." },
			{ "cow", "...Somebody has to dig that gnome out." } } },
		{ id = "pig_board", lines = {
			{ "pig", "The plaza has four boards of names." },
			{ "cow", "Fastest. Oldest. Longest. Most reborn." },
			{ "pig", "Have you been round the back of them?" },
			{ "cow", "Why would I go round the back?" },
			{ "pig", "Because there is a fifth one there." },
			{ "cow", "There is not." },
			{ "pig", "Turned to face the wall. Same stone." },
			{ "cow", "What does a fifth board count?" },
			{ "pig", "Farts. Every one anybody ever did." },
			{ "cow", "...Who builds that?" },
			{ "pig", "The same people who built the others." },
			{ "cow", "On purpose? At the same time?" },
			{ "pig", "The stone is cut the same. I checked." },
			{ "cow", "Then somebody thought it mattered." },
			{ "pig", "Somebody thought it mattered MOST." },
			{ "cow", "Is there a name on it?" },
			{ "pig", "One name at the top. For years." },
			{ "cow", "The same one all that time?" },
			{ "pig", "The same one. By a very long way." },
			{ "cow", "How long a way?" },
			{ "pig", "Double the next. It is not close." },
			{ "cow", "Does that person know it is back there?" },
			{ "pig", "They visit. I have watched them visit." },
			{ "cow", "What do they do when they get there?" },
			{ "pig", "Nothing. They stand and they read it." },
			{ "cow", "For how long?" },
			{ "pig", "Longer than anyone reads the front ones." },
			{ "cow", "...That is a little sad." },
			{ "pig", "I do not think it is sad at all." },
			{ "cow", "No?" },
			{ "pig", "Everyone reads the fastest board once." },
			{ "cow", "And?" },
			{ "pig", "Nobody goes back to it. That one they do." },
			{ "cow", "...Because it is theirs alone." },
			{ "pig", "Because it is the only one they wanted." },
			{ "cow", "...Fine. I will go round the back." } } },
	},
}

local STORY_TOTAL = #STORIES.cow + #STORIES.pig

-- ===== WHO HAS HEARD WHAT =====
local heard = {}   -- [player] = { [storyId] = true }
local storyStore
pcall(function() storyStore = game:GetService("DataStoreService"):GetDataStore("FiresideStories_v1") end)

local function heardCount(player)
	local n = 0
	for _ in pairs(heard[player] or {}) do n = n + 1 end
	return n
end

local function loadHeard(player)
	heard[player] = heard[player] or {}
	task.wait(2) -- PlayerStats publishes _G.FRESH_PLAYER_TESTING at boot; give it a beat before trusting it
	if _G.FRESH_PLAYER_TESTING or not storyStore then
		player:SetAttribute("FiresideHeard", heardCount(player))
		return
	end
	local ok, data = pcall(function() return storyStore:GetAsync(tostring(player.UserId)) end)
	if ok and type(data) == "table" then
		for _, id in ipairs(data) do heard[player][id] = true end
	end
	player:SetAttribute("FiresideHeard", heardCount(player))
end

local function saveHeard(player)
	if _G.FRESH_PLAYER_TESTING or not storyStore then return end
	local list = {}
	for id in pairs(heard[player] or {}) do list[#list + 1] = id end
	pcall(function() storyStore:SetAsync(tostring(player.UserId), list) end)
end

local function markHeard(player, id)
	heard[player] = heard[player] or {}
	if heard[player][id] then return end
	heard[player][id] = true
	local n = heardCount(player)
	player:SetAttribute("FiresideHeard", n)
	saveHeard(player)
	if n >= STORY_TOTAL then
		if _G.grantTitle then pcall(_G.grantTitle, player, "Fireside") end
		flashOverhead(player, "\xF0\x9F\x94\xA5 FIRESIDE -- you have heard them all", Color3.fromRGB(255, 200, 90))
		print(("[Fireside] %s has heard every story -- 'Fireside' title granted"):format(player.Name))
	else
		flashOverhead(player, ("\xF0\x9F\x93\x96 New story heard (%d/%d)"):format(n, STORY_TOTAL), Color3.fromRGB(255, 226, 150))
	end
end

Players.PlayerAdded:Connect(function(p) task.spawn(loadHeard, p) end)
Players.PlayerRemoving:Connect(function(p) heard[p] = nil end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(loadHeard, p) end

local function playersNear(pos, range)
	local out = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - pos).Magnitude <= range then out[#out + 1] = player end
	end
	return out
end

-- The story the fewest listeners have heard; ties broken at random so a fire full of veterans still varies.
-- The story the fewest listeners have heard, drawn from THIS teller's pool; ties broken at random so a fire
-- full of veterans still varies.
local function pickStory(audience, teller)
	local best, bestScore = {}, math.huge
	for _, story in ipairs(STORIES[teller]) do
		local score = 0
		for _, p in ipairs(audience) do
			if heard[p] and heard[p][story.id] then score = score + 1 end
		end
		if score < bestScore then best, bestScore = { story }, score
		elseif score == bestScore then best[#best + 1] = story end
	end
	return best[math.random(1, #best)]
end

local function animalAtFire(a)
	return a and a.body and a.body.Parent and storyFlame
		and (a.body.Position - storyFlame.Position).Magnitude <= STORY_RANGE
end

-- Said by whichever animal reached the fire first while it waits for the other. Same bubble, same length
-- rule as a story line (under ~45 characters, two rows).
local SOLO_LINES = {
	"Any minute now. He is on his way.",
	"I could have been asleep for this.",
	"The fire is perfect and nobody is here.",
	"I am not starting without him.",
	"He walks like the night is long.",
	"One of us is always early.",
	"Marshmallows do not roast themselves.",
	"I have a good one saved up tonight.",
	"Sit down, the pair of us have stories.",
	"He gets lost between here and there.",
}
local SOLO_GAP = 11        -- seconds between solo lines -- sparser than a story, so it reads as waiting
local soloAt   = 0         -- next allowed solo line (os.clock)
local lastTeller = "pig"   -- so the cow opens the night
local function runStories()
	while true do
		task.wait(1)
		if isNight() and firesLit and storyFlame and storyFlame.Parent then
			local ga = _G.gardenAnimals or {}
			local pig, cow = ga.pig, ga.cow
			-- NOBODY HAS TO BE THERE. The stories used to wait for a listener, which meant you always walked
			-- up to two silent animals and then waited for the next one to start. They talk to each other all
			-- night now, and whoever is standing at the fire when a story ENDS is credited with it -- so a
			-- story you only caught the last line of does not count, and one you sat through does.
			local audience = playersNear(storyFlame.Position, REST_RADIUS)
			if animalAtFire(pig) and animalAtFire(cow) then
				-- ALTERNATE THE TELLER. Whoever did not tell the last one tells this one, so the fire never
				-- becomes one animal monologuing while the other says "mm" six times.
				lastTeller = (lastTeller == "cow") and "pig" or "cow"
				local story = pickStory(audience, lastTeller)
				local cast = { cow = cow, pig = pig }
				print(("[Fireside] %s tells '%s' to %d listener(s)"):format(lastTeller, story.id, #audience))
				local finished = true
				for i, line in ipairs(story.lines) do
					-- Both of them have to still be here: one wandering off ends the story, because half an
					-- exchange is worse than none.
					local speaker = cast[line[1]]
					if not (isNight() and animalAtFire(pig) and animalAtFire(cow) and animalAtFire(speaker)) then
						finished = false; break
					end
					pcall(speaker.say, line[2], BUBBLE_HOLD)
					-- Hold a beat before the closing reaction -- see PUNCH_PAUSE.
					task.wait(LINE_SECONDS + ((i == #story.lines - 1) and PUNCH_PAUSE or 0))
				end
				if finished then
					for _, p in ipairs(playersNear(storyFlame.Position, REST_RADIUS)) do markHeard(p, story.id) end
				end
				task.wait(STORY_GAP)

			-- ===== WHOEVER GETS THERE FIRST TALKS ANYWAY =====
			-- The pig only has to cross its own field; the cow walks ~250 studs from the far side of the
			-- island, so for the first minute of every night there is a pig sitting at a fire saying nothing
			-- at all -- and its ambient chatter is switched off for the night, so it is properly silent. That
			-- reads as broken, and it is the exact minute a player who came for the banner arrives.
			--
			-- So the one who is there fills the wait: a solo line every SOLO_GAP seconds, about the other one
			-- being late. They are deliberately about waiting, so they set up the stories instead of competing
			-- with them, and the moment both animals are at the fire this branch stops firing on its own.
			elseif animalAtFire(pig) or animalAtFire(cow) then
				if os.clock() >= soloAt then
					soloAt = os.clock() + SOLO_GAP
					local here = animalAtFire(pig) and pig or cow
					pcall(here.say, SOLO_LINES[math.random(1, #SOLO_LINES)], BUBBLE_HOLD)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- /night  -- TEST COMMAND, REMOVE BEFORE LAUNCH
--------------------------------------------------------------------------------
--   /night          -> sunset starts now (watch the full ramp down)
--   /night dark     -> skip the sunset, full dark immediately
--   /night sunrise  -> skip to the ramp back up
--   /night day      -> back to daylight; next sunset a full 25 minutes away
--   /night status   -> print where the cycle currently is, and change nothing
-- Registered on BOTH paths for the same reason the garden commands are: Player.Chatted does not fire under
-- TextChatService, which is what this place uses, so a Chatted-only command silently does nothing.
local function handleNightChat(plr, msg)
	local lower = string.lower(msg)
	if string.sub(lower, 1, 6) ~= "/night" then return end
	if not (_G.isAllowedTestUser and _G.isAllowedTestUser(plr)) then
		print(("[Fireside] /night from %s -- refused (not on the test allow-list)"):format(plr.Name))
		return
	end
	local arg = string.match(lower, "^/night%s+(%a+)$")

	local function report(prefix)
		local f = nightFactor()
		local phase = (not isNight()) and "DAY"
			or (f >= 1 and "FULL DARK")
			or ((clock() % NIGHT_PERIOD) < SUNSET_SECS and "SUNSET" or "SUNRISE")
		print(("%s %s (darkness %.2f) -- %s")
			:format(prefix, phase, f,
				isNight() and ("day returns in %ds"):format(nightEndsIn())
				          or ("next sunset in %ds"):format(nextNightIn())))
	end

	if arg == nil or arg == "" then arg = "night" end   -- a bare /night means "sunset, now"
	if arg == "status" then report("[Fireside] /night status --"); return end
	if not setNightPhase(arg) then
		print(("[Fireside] /night: don't know %q. Use /night, /night dark, /night sunrise, /night day, /night status."):format(arg))
		return
	end
	report(("[Fireside] /night %s by %s ->"):format(arg, plr.Name))
end

local function hookNightChat(plr) plr.Chatted:Connect(function(msg) handleNightChat(plr, msg) end) end
for _, p in ipairs(Players:GetPlayers()) do hookNightChat(p) end
Players.PlayerAdded:Connect(hookNightChat)

do
	local ok, err = pcall(function()
		local TextChatService = game:GetService("TextChatService")
		-- A stale baked-in copy of this script would otherwise register a SECOND command on the same alias,
		-- and one /night would shift the phase twice.
		for _, existing in ipairs(TextChatService:GetChildren()) do
			if existing:IsA("TextChatCommand") and existing.PrimaryAlias == "/night" then return end
		end
		local c = Instance.new("TextChatCommand")
		c.Name = "NightCycleCommand"; c.PrimaryAlias = "/night"
		c.Parent = TextChatService
		c.Triggered:Connect(function(source, text)
			local plr = source and Players:GetPlayerByUserId(source.UserId)
			if plr then handleNightChat(plr, text) end
		end)
	end)
	if ok then print("[Fireside] /night registered (/night, /night dark, /night sunrise, /night day, /night status) -- TEST, REMOVE BEFORE LAUNCH")
	else warn("[Fireside] /night registration failed: " .. tostring(err)) end
end

--------------------------------------------------------------------------------
-- /nightbanner  -- fire the fireside reminder right now (TEST)
--------------------------------------------------------------------------------
-- The reminder banner itself is CLIENT-side (Campfire.client.luau) and runs on a timer, because everything it
-- needs -- how long until sunset, whether it is night, where the story fire is -- is already published as
-- Workspace attributes. So this command does not send the banner; it pokes a counter the clients watch, which
-- is the whole server side of it. No remote, and every player in the server sees the same poke.
local bannerPokes = 0
local function handleBannerChat(plr, msg)
	if string.lower(msg):match("^/nightbanner%s*$") == nil then return end
	if not (_G.isAllowedTestUser and _G.isAllowedTestUser(plr)) then
		print(("[Fireside] /nightbanner from %s -- refused (not on the test allow-list)"):format(plr.Name))
		return
	end
	bannerPokes += 1
	Workspace:SetAttribute("NightBannerPing", bannerPokes)
	print(("[Fireside] /nightbanner by %s -> poked every client (poke #%d)"):format(plr.Name, bannerPokes))
end

local function hookBannerChat(plr) plr.Chatted:Connect(function(msg) handleBannerChat(plr, msg) end) end
for _, p in ipairs(Players:GetPlayers()) do hookBannerChat(p) end
Players.PlayerAdded:Connect(hookBannerChat)

do
	local ok, err = pcall(function()
		local TextChatService = game:GetService("TextChatService")
		for _, existing in ipairs(TextChatService:GetChildren()) do
			if existing:IsA("TextChatCommand") and existing.PrimaryAlias == "/nightbanner" then return end
		end
		local c = Instance.new("TextChatCommand")
		c.Name = "NightBannerCommand"; c.PrimaryAlias = "/nightbanner"
		c.Parent = TextChatService
		c.Triggered:Connect(function(source, text)
			local plr = source and Players:GetPlayerByUserId(source.UserId)
			if plr then handleBannerChat(plr, text) end
		end)
	end)
	if ok then print("[Fireside] /nightbanner registered -- shows the fireside reminder now (TEST)")
	else warn("[Fireside] /nightbanner registration failed: " .. tostring(err)) end
end

--------------------------------------------------------------------------------
-- init
--------------------------------------------------------------------------------
task.spawn(function()
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end

	local spots
	for _ = 1, 30 do spots = findMarkers(); if #spots > 0 then break end; task.wait(1) end
	if not spots or #spots == 0 then
		warn("[Campfire] no fire markers and no Island 1 spawn found -- no campfires built")
		return
	end

	for _, s in ipairs(spots) do
		FLAMES[#FLAMES + 1] = buildCampfire(s.cf, s.seats)
		print(("[Campfire] built '%s' at %s (%d seats)"):format(s.name, tostring(s.cf.Position), s.seats))
	end
	print(("[Campfire] %d campfire(s) ready -- rest within %d studs, roast marshmallows over the flames")
		:format(#FLAMES, REST_RADIUS))
	pruneDuplicateFires() -- now that ours exist and are stamped, clear out any built by a stale copy
	task.delay(2, pruneDuplicateFires); task.delay(6, pruneDuplicateFires) -- again, for a stale copy that builds after us
	setFiresLit(Workspace:GetAttribute("ActiveServerEvent") ~= "THUNDERSTORM") -- correct state if we spawned mid-storm
	task.spawn(runWeather)
	task.spawn(runRoasting)
	pickStoryFire()          -- the fire nearest island 1's food stand; published as StoryFirePos
	task.spawn(runNight)     -- the 25-minute day/night clock, published as NightFactor / BeanFarmNight
	task.spawn(runStories)   -- the pig and the cow, once they are both at the fire after dark
	runPayout()
end)
