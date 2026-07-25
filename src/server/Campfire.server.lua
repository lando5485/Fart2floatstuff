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

-- client -> server actions for the roasting buttons ("roast" / "stop" / "eat"). getOrCreate so a missing
-- project.json entry can't break it; the client WaitForChild's this same name.
local stickRemote = ReplicatedStorage:FindFirstChild("CampfireStick")
if not stickRemote then
	stickRemote = Instance.new("RemoteEvent"); stickRemote.Name = "CampfireStick"; stickRemote.Parent = ReplicatedStorage
end

--------------------------------------------------------------------------------
-- tuning -- keep the coins SMALL
--------------------------------------------------------------------------------
local SCALE        = 1.02   -- overall size of the campfire + seats (1 = original). Everything scales off this.
local SEATS        = 6      -- default stump seats ringed around a fire (a numbered brick like "Fire 2" overrides)
local REST_RADIUS  = 24     -- studs from the fire you must be within to count as resting (widened for the bigger ring)
local TICK         = 3      -- seconds between payouts
local BASE_COINS   = 1      -- coins per tick to start
local BONUS_PER_MIN = 1     -- +1 per full minute you stay, so genuine idling feels a touch cozier...
local MAX_COINS    = 3      -- ...but it's capped low. 3 coins / 3s is the ceiling.
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
	pp.Name = "TakeMarshmallowStick"; pp.ActionText = "Take a Marshmallow Stick"; pp.ObjectText = "Campfire"
	pp.HoldDuration = 0.4; pp.MaxActivationDistance = 12; pp.RequiresLineOfSight = false
	pp.Parent = promptAnchor
	pp.Triggered:Connect(function(plr) if plr then giveStick(plr) end end)

	-- remember this fire so the weather can douse/relight it and swap its sign text
	CAMPFIRES[#CAMPFIRES + 1] = { flame = flame, fire = fire, light = light, smoke = smoke, sign = lbl }

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
	for _, c in ipairs(CAMPFIRES) do
		if c.fire  then c.fire.Enabled  = lit end
		if c.smoke then c.smoke.Enabled = lit end -- (the flame part is driven by the flicker loop)
		if c.sign  then c.sign.Text = lit and SIGN_LIT or SIGN_RAIN end
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
local function roastResult(r)
	if r < 18     then return "Still raw! Hold it over the fire.", 1, Color3.fromRGB(240, 240, 240)
	elseif r < 42 then return "\xF0\x9F\x98\x8B Lightly toasted!",  3, Color3.fromRGB(240, 214, 150)
	elseif r < 72 then return "\xF0\x9F\x94\xA5 Perfectly golden!", 8, Color3.fromRGB(255, 190, 90)  -- best
	elseif r < 92 then return "Crispy and gooey!",                 4, Color3.fromRGB(170, 110, 60)
	else               return "\xF0\x9F\x98\x85 Burnt to a crisp!", 1, Color3.fromRGB(90, 60, 40)
	end
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

-- EAT: bank the result for how done it is, then the stick + marshmallow are gone. Only the Eat BUTTON
-- calls this (never a screen tap). Clearing heldStick first makes a double-eat impossible.
local function eatStick(player)
	local tool = heldStick[player]
	if not tool then return end
	heldStick[player] = nil
	roasting[player]  = nil
	local r = tool:GetAttribute("Roast") or 0
	local msg, coins, tint = roastResult(r)
	creditCoins(player, coins)
	flashOverhead(player, msg .. " +" .. coins, tint)
	task.delay(0.35, function() if tool then tool:Destroy() end end)
end

function giveStick(player) -- assigns the forward-declared local above
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local bp   = player:FindFirstChildOfClass("Backpack")
	if not (char and hum and bp) then return end
	if char:FindFirstChild("Marshmallow Stick") or bp:FindFirstChild("Marshmallow Stick") then return end -- already has one

	local tool = getStickTemplate():Clone()

	-- NOTE: deliberately NO Tool.Activated -> eat. Tapping/clicking the screen activates a held tool, and we
	-- do NOT want a stray tap to eat the marshmallow (and pop the HUD back). Only the Eat BUTTON eats.

	tool.AncestryChanged:Connect(function(_, parent)
		if not parent and heldStick[player] == tool then heldStick[player] = nil; roasting[player] = nil end
	end)

	tool.Parent = bp
	heldStick[player] = tool
	roasting[player]  = nil -- starts NOT cooking; you press Go to begin
	-- AUTO-EQUIP: the Backpack CoreGui is disabled game-wide (no hotbar), so a tool in the pack is unreachable.
	pcall(function() hum:EquipTool(tool) end)
end

-- Go / Stop / Eat / Remove, from the on-screen buttons.
stickRemote.OnServerEvent:Connect(function(player, action)
	local tool = heldStick[player]
	if not tool then return end -- not holding a stick -> ignore
	if action == "roast"   then roasting[player] = true
	elseif action == "stop" then roasting[player] = nil
	elseif action == "eat"  then eatStick(player)
	elseif action == "remove" then -- throw it away, no eat, no reward
		heldStick[player] = nil; roasting[player] = nil
		tool:Destroy()
	end
end)

-- distance from a point to the NEAREST flame (or math.huge if there are none)
local function nearestFlameDist(pos)
	local best = math.huge
	for _, flame in ipairs(FLAMES) do
		if flame.Parent then best = math.min(best, (pos - flame.Position).Magnitude) end
	end
	return best
end

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
				tool:Destroy()
			elseif marsh and firesLit and roasting[player] and hrp and nearestFlameDist(hrp.Position) <= REST_RADIUS then
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
	setFiresLit(Workspace:GetAttribute("ActiveServerEvent") ~= "THUNDERSTORM") -- correct state if we spawned mid-storm
	task.spawn(runWeather)
	task.spawn(runRoasting)
	runPayout()
end)
