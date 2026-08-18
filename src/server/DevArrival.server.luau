--[[
	DevArrival.server.luau  (ServerScriptService.DevArrival)

	A DEV JOINS -> the whole server gets a moment. Four things fire together, all four of which you picked:

	  1. BANNER   -- gold HERO banner to every player, via DevArrivalEvent -> DevArrivalBanner.client.
	  2. SPECTACLE-- gold shockwave ring, confetti burst and a light pillar at the dev's spawn, plus a gold
	                 outline on them for 30s so players can find them.
	  3. BUFF     -- "DEV ONLINE" double coins for 45s for EVERYONE, run through the existing COIN_RUSH event.
	  4. CRATE    -- a Premium crate lands next to the dev. Any player can open it, ONCE each, for 90s.

	=== HOW THE BUFF WORKS (and why it reuses COIN_RUSH) ===
	PlayerStats owns a random-event loop that broadcasts ServerEventNotify(name, dispName, dur, msg, colour)
	and a matching "END" when the event expires. EventClient already implements COIN_RUSH as
	`_G.serverEventCoinMult = 2` plus floating coin emojis, and it honours whatever duration the server sends
	(`_G.serverEventEndTime = os.time() + dur`) rather than hardcoding COIN_RUSH's usual 7s.

	So this fires the real COIN_RUSH key with a custom display name and a 45s duration. Every mechanic, the
	countdown pill, the glow pulse and the cleanup are the existing, tested ones -- there is no second buff
	system to keep in sync. It is the same trick the codebase already uses to show LOW_GRAVITY as
	"HIGH GRAVITY", and the same path /thunderstorm uses to fire an event on demand.

	IT YIELDS TO THE SCHEDULER. If a random event is already running (workspace.ActiveServerEvent is set), the
	buff is SKIPPED for that join. Two overlapping events would fight: ours would cancel theirs on every
	client, then their END -- scheduled before ours -- would kill our buff early and leave the pill wrong.
	The banner, spectacle and crate still fire; only the buff stands down. This is logged when it happens.

	=== ONCE PER DEV PER SERVER ===
	Keyed on UserId in `announced`, so hopping in and out does not re-trigger it, and three devs joining gets
	three moments rather than an endless loop of buffs and crates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

-- ============================ PAUSED ============================
-- OFF FOR NOW, AT YOUR REQUEST: devs join as ordinary players. No banner, no shockwave or light pillar, no
-- gold outline, no 45s double-coin buff, no dev crate, and no aura on respawn -- nothing marks the account
-- out at all.
--
-- PAUSED, NOT DELETED. Every piece below is intact and wired; this is a single gate on `hook`, which is the
-- one place both `celebrate` and `auraFor` are reached from. That is deliberate -- ripping the feature out
-- would mean unpicking the crate remote, the COIN_RUSH reuse and the banner client, and putting it back
-- later would be a rebuild rather than a switch.
--
-- TO BRING IT BACK: set this to true. Nothing else needs touching.
local ENABLED = false

-- ============================ WHO COUNTS AS A DEV ============================
-- Same list as the credits line in SettingsMenu. USER IDS ARE THE RELIABLE ONE -- a username can be changed
-- by its owner, at which point the name check silently stops matching, and the freed name could later be
-- taken by a stranger who would then trigger a server-wide buff and crate on every join. Fill these in.
local DEV_USER_IDS = {
	-- [123456789] = true, -- lando5485
	-- [123456789] = true, -- Broskie310111
	-- [123456789] = true, -- itsmaddmax2
}
local DEV_USERNAMES = {
	["lando5485"] = true,
	["broskie310111"] = true,
	["itsmaddmax2"] = true,
}

-- ============================ TUNING ============================
local BUFF_SECONDS  = 45   -- how long DEV ONLINE double-coins runs
local GLOW_SECONDS  = 30   -- gold outline on the dev
local CRATE_SECONDS = 90   -- how long the dropped crate stays claimable
local CRATE_ID      = "Premium" -- the same crate the daily free spin uses (CrateService.DAILY_CRATE_ID)

local GOLD = Color3.fromRGB(255, 210, 74)
local LIME = Color3.fromRGB(126, 217, 87)
local NAVY = Color3.fromRGB(6, 26, 80)

-- ============================ PLUMBING ============================
local function getOrCreate(parent, class, name)
	local found = parent:FindFirstChild(name)
	if found then return found end
	local inst = Instance.new(class)
	inst.Name = name
	inst.Parent = parent
	return inst
end

local DevArrivalEvent = getOrCreate(ReplicatedStorage, "RemoteEvent", "DevArrivalEvent")
local ServerEventNotify = getOrCreate(ReplicatedStorage, "RemoteEvent", "ServerEventNotify")
-- Carries (crateId, result) to the opener so their client can play the normal crate reel. Created at boot,
-- not on first use, so the client is already connected before anyone can trigger a crate.
local DevCrateReveal = getOrCreate(ReplicatedStorage, "RemoteEvent", "DevCrateReveal")

local function isDev(player)
	if DEV_USER_IDS[player.UserId] then return true end
	if DEV_USERNAMES[string.lower(player.Name)] then return true end
	return false
end

-- Display names, not the Workspace model names. PlayerStats' own ISLAND_NAMES holds the MODEL spellings
-- ("Island_1_BeanFarm") which are not something to show a player; these are the same 14 in the same order,
-- written the way the HUD writes them.
local ISLAND_DISPLAY = {
	"Bean Farm", "Broccoli Bluff", "Cabbage Cliffs", "Turnip Tranquil", "Coconut Cove", "Bread Board",
	"Pasta Peak", "Popcorn Pinnacle", "Milk Marsh", "Butter Swamp", "Ice Cream Isle", "Burger Bluff",
	"Burrito Barrens", "Pizza Palms",
}

-- Which island the dev is standing on, so the announcement tells everyone where to find them.
-- Read from the Island leaderstat PlayerStats maintains (an IntValue, 1-14).
local function islandNameOf(player)
	local ls = player:FindFirstChild("leaderstats")
	local island = ls and ls:FindFirstChild("Island")
	local n = island and tonumber(island.Value)
	if n and ISLAND_DISPLAY[n] then
		return ISLAND_DISPLAY[n], n
	end
	return nil, nil
end

local announced = {} -- [userId] = true, once per dev per server

-- ============================ 2. SPECTACLE ============================
local function spectacle(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local origin = hrp.Position

	-- Shockwave: a flat disc that expands outward and fades. Anchored + non-colliding so it cannot shove
	-- anyone standing nearby (a solid expanding part would launch them).
	local ring = Instance.new("Part")
	ring.Name = "DevShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 4, 4)
	ring.CFrame = CFrame.new(origin - Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = GOLD
	ring.Transparency = 0.15
	ring.Parent = Workspace
	TweenService:Create(ring, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, 46, 46),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 1.4)

	-- Light pillar straight up.
	local beam = Instance.new("Part")
	beam.Name = "DevBeam"
	beam.Size = Vector3.new(5, 90, 5)
	beam.CFrame = CFrame.new(origin + Vector3.new(0, 42, 0))
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = GOLD
	beam.Transparency = 0.55
	beam.Parent = Workspace
	TweenService:Create(beam, TweenInfo.new(1.6, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
	Debris:AddItem(beam, 2)

	-- Confetti burst. One-shot Emit rather than a rate, so it is a pop and not a fountain.
	local anchor = Instance.new("Part")
	anchor.Name = "DevConfetti"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(origin + Vector3.new(0, 2, 0))
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = Workspace

	local att = Instance.new("Attachment")
	att.Parent = anchor

	local pe = Instance.new("ParticleEmitter")
	pe.Enabled = false
	pe.Lifetime = NumberRange.new(1.4, 2.6)
	pe.Speed = NumberRange.new(22, 40)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-220, 220)
	pe.Size = NumberSequence.new(0.5)
	pe.Acceleration = Vector3.new(0, -38, 0)
	pe.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, GOLD),
		ColorSequenceKeypoint.new(0.5, LIME),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.75, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Parent = att
	pe:Emit(140)
	Debris:AddItem(anchor, 4)

	-- (the aura is applied separately by applyAura, on every spawn rather than just this one)
end

-- ============================ THE DEV AURA ============================
-- Worn permanently, re-applied on every respawn -- not a 30-second arrival effect. Five layers:
--
--   1. a PULSING gold outline          -- reads at any distance, through walls
--   2. a ground halo that breathes     -- anchors them to the floor instead of floating in space
--   3. rising spiral sparkles          -- movement, so it never looks like a static decal
--   4. a crown of embers over the head -- the "this player is different" tell at a glance
--   5. a warm gold light               -- they actually light the world around them
--
-- NO PER-FRAME CODE. Everything animates via ParticleEmitters (self-animating) or looping TweenService
-- tweens on a single property. The naive way to do an aura is a Heartbeat loop rewriting CFrames, which for
-- a server-side effect means replicating a property change every frame to every client, forever. Tweening
-- one number and letting particles do the rest costs effectively nothing and looks better.
local function applyAura(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	if not hrp then return end

	local old = char:FindFirstChild("DevAura")
	if old then old:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "DevAura"
	folder.Parent = char

	-- 1. PULSING OUTLINE. Outline only -- FillTransparency 0 would flatten the whole avatar, clothing and
	-- all, into one flat gold silhouette.
	local hl = Instance.new("Highlight")
	hl.Name = "AuraOutline"
	hl.FillTransparency = 1
	hl.OutlineColor = GOLD
	hl.OutlineTransparency = 0.15
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = char
	hl.Parent = folder
	TweenService:Create(hl, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ OutlineTransparency = 0.55 }):Play()

	-- 2. GROUND HALO. A flat neon disc at the feet that breathes in and out.
	local halo = Instance.new("Part")
	halo.Name = "AuraHalo"
	halo.Shape = Enum.PartType.Cylinder
	halo.Size = Vector3.new(0.15, 7, 7)
	halo.Color = GOLD
	halo.Material = Enum.Material.Neon
	halo.Transparency = 0.55
	halo.Massless = true
	halo.CanCollide = false
	halo.CanQuery = false
	halo.CanTouch = false
	halo.CastShadow = false
	halo.Parent = folder
	-- FEET LEVEL, measured -- not the hardcoded -2.9 this used to be. HipHeight + half the root part is
	-- exactly where Roblox puts the soles of a standing character, so this lands the disc on the floor for
	-- R6, R15 and any scaled avatar instead of floating or sinking on some of them.
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local footDrop
	if humanoid and humanoid.HipHeight and humanoid.HipHeight > 0 then
		footDrop = humanoid.HipHeight + hrp.Size.Y * 0.5
	else
		-- R6 reports HipHeight 0, so fall back to the character's own bounding box.
		local ok, cf, size = pcall(function()
			local c, s = char:GetBoundingBox()
			return c, s
		end)
		footDrop = (ok and cf and size) and (hrp.Position.Y - (cf.Position.Y - size.Y * 0.5)) or 3
	end

	local hw = Instance.new("Weld")
	hw.Part0 = hrp
	hw.Part1 = halo
	-- 0.05 up off the floor so the disc does not z-fight with the ground it is sitting on.
	hw.C0 = CFrame.new(0, -(footDrop - 0.05), 0) * CFrame.Angles(0, 0, math.rad(90)) -- lay the cylinder flat
	hw.Parent = halo

	local haloBreath = TweenService:Create(halo,
		TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = Vector3.new(0.15, 9.5, 9.5), Transparency = 0.82 })
	haloBreath:Play()

	-- GROUNDED ONLY. A ground halo hanging in the air under a flying player looks like a bug, so it hides
	-- the moment you leave the floor and comes back when you land.
	--
	-- The breathing tween has to be PAUSED, not just overridden: it animates Transparency itself, so setting
	-- Transparency = 1 while it runs would be stomped on the very next frame.
	if humanoid then
		local function updateHalo()
			local grounded = (humanoid.FloorMaterial ~= Enum.Material.Air)
			if grounded then
				halo.Transparency = 0.55
				haloBreath:Play()
			else
				haloBreath:Pause()
				halo.Transparency = 1
			end
		end
		-- Event-driven, not polled: FloorMaterial fires only on the takeoff/landing edges.
		humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(updateHalo)
		updateHalo()
	end

	-- 3. RISING SPIRAL SPARKLES, from the feet upward past the body.
	local footAtt = Instance.new("Attachment")
	footAtt.Name = "AuraFoot"
	footAtt.Position = Vector3.new(0, -2.6, 0)
	footAtt.Parent = hrp

	local rise = Instance.new("ParticleEmitter")
	rise.Name = "AuraRise"
	rise.Rate = 26
	rise.Lifetime = NumberRange.new(1.1, 1.8)
	rise.Speed = NumberRange.new(4, 7)
	rise.EmissionDirection = Enum.NormalId.Top
	rise.SpreadAngle = Vector2.new(18, 18)
	rise.Drag = 1.5
	rise.Acceleration = Vector3.new(0, 3, 0)
	rise.LightEmission = 0.75
	rise.Rotation = NumberRange.new(0, 360)
	rise.RotSpeed = NumberRange.new(-90, 90)
	rise.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, 0.55),
		NumberSequenceKeypoint.new(1, 0),
	})
	rise.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	rise.Color = ColorSequence.new(GOLD, LIME)
	rise.Parent = footAtt
	folder:SetAttribute("FootAttachment", true) -- marker; the attachment lives on the HRP, cleaned below

	-- 4. CROWN OF EMBERS above the head. Emitted from a ring-ish spread so it circles rather than plumes.
	if head then
		local crownAtt = Instance.new("Attachment")
		crownAtt.Name = "AuraCrown"
		crownAtt.Position = Vector3.new(0, 1.9, 0)
		crownAtt.Parent = head

		local crown = Instance.new("ParticleEmitter")
		crown.Name = "AuraCrown"
		crown.Rate = 14
		crown.Lifetime = NumberRange.new(0.9, 1.4)
		crown.Speed = NumberRange.new(1.4, 2.4)
		crown.EmissionDirection = Enum.NormalId.Top
		crown.SpreadAngle = Vector2.new(180, 180)
		crown.Acceleration = Vector3.new(0, -1.5, 0)
		crown.LightEmission = 1
		crown.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.32),
			NumberSequenceKeypoint.new(1, 0),
		})
		crown.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 1),
		})
		crown.Color = ColorSequence.new(GOLD, Color3.fromRGB(255, 255, 255))
		crown.Parent = crownAtt
	end

	-- 5. WARM LIGHT. Range kept modest -- a big bright PointLight on a moving player is one of the more
	-- expensive things you can hand a low-end phone.
	local light = Instance.new("PointLight")
	light.Name = "AuraLight"
	light.Color = GOLD
	light.Brightness = 1.6
	light.Range = 14
	light.Shadows = false
	light.Parent = halo
	TweenService:Create(light, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Brightness = 2.6 }):Play()

	-- 6. GOLDEN FART TRAIL. Engine-driven, so it costs nothing and only draws when you actually move.
	--
	-- NOTE ON WHY IT LIVES HERE: this realm's FartTrails catalogue in CosmeticConfig is data only -- nothing
	-- in Fart to Float reads it (the code that turns those entries into real trails is Space's
	-- CosmeticService). Adding a "trail_golden" row there would have rendered precisely nothing, so the
	-- golden trail is built directly, here, where it is guaranteed to show up.
	local trailA = Instance.new("Attachment")
	trailA.Name = "AuraTrailA"
	trailA.Position = Vector3.new(-0.9, 0.6, 0)
	trailA.Parent = hrp
	local trailB = Instance.new("Attachment")
	trailB.Name = "AuraTrailB"
	trailB.Position = Vector3.new(0.9, -0.6, 0)
	trailB.Parent = hrp

	local trail = Instance.new("Trail")
	trail.Name = "AuraTrail"
	trail.Attachment0 = trailA
	trail.Attachment1 = trailB
	trail.Lifetime = 0.9
	trail.MinLength = 0.1
	trail.LightEmission = 0.9
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.15), -- tapers to a point behind you instead of ending in a flat edge
	})
	trail.FaceCamera = true
	-- Pure gold, hot core to pale tail. No lime/cyan in here -- this is the GOLD trail; the aura does its
	-- colour cycling on the outline and light instead, so the two never fight for the same read.
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 170)),
		ColorSequenceKeypoint.new(0.4, GOLD),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 130, 20)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = folder

	-- THE FART ITSELF. A gold burst out of the feet, on ONLY while airborne -- so on the ground you get a
	-- clean gold streak as you run, and the moment you take off it turns into a proper golden exhaust plume.
	local jet = Instance.new("ParticleEmitter")
	jet.Name = "GoldFartJet"
	jet.Enabled = false
	jet.Rate = 90
	jet.Lifetime = NumberRange.new(0.5, 0.95)
	jet.Speed = NumberRange.new(14, 24)
	jet.EmissionDirection = Enum.NormalId.Bottom
	jet.SpreadAngle = Vector2.new(26, 26)
	jet.Acceleration = Vector3.new(0, -22, 0)
	jet.LightEmission = 0.85
	jet.Rotation = NumberRange.new(0, 360)
	jet.RotSpeed = NumberRange.new(-140, 140)
	jet.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.4, 1.5),
		NumberSequenceKeypoint.new(1, 2.4),
	})
	jet.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	jet.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 200)),
		ColorSequenceKeypoint.new(0.5, GOLD),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 110, 20)),
	})
	jet.Parent = footAtt

	-- Same airborne signal the halo uses, on its own connection so neither has to know about the other.
	if humanoid then
		local function updateJet()
			jet.Enabled = (humanoid.FloorMaterial == Enum.Material.Air)
		end
		humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(updateJet)
		updateJet()
	end

	-- 7. SPARKLES. The stock instance -- one object, engine-animated, and it reads differently from the
	-- ParticleEmitters above because it clusters tight to the body instead of streaming off it.
	local sparkles = Instance.new("Sparkles")
	sparkles.Name = "AuraSparkles"
	sparkles.SparkleColor = GOLD
	sparkles.Parent = hrp

	-- 8. COLOUR CYCLE. Gold -> lime -> cyan -> back, on the outline and the light together so the whole
	-- aura shifts as one. Three chained tweens rather than one: a looping tween can only ping-pong between
	-- two values, which would miss the middle colour entirely.
	local CYCLE = { GOLD, LIME, Color3.fromRGB(120, 220, 255) }
	task.spawn(function()
		local i = 1
		while folder.Parent do
			i = (i % #CYCLE) + 1
			local info = TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			pcall(function()
				TweenService:Create(hl, info, { OutlineColor = CYCLE[i] }):Play()
				TweenService:Create(halo, info, { Color = CYCLE[i] }):Play()
				TweenService:Create(light, info, { Color = CYCLE[i] }):Play()
			end)
			task.wait(2.2)
		end
	end)

	-- 9. ORBITERS -> handed to the client. The orbs and counter-rotating rings need a new CFrame every
	-- frame, and doing that on the server would replicate a property change per part per frame to every
	-- client, forever. Instead the player is TAGGED, and DevAuraFX.client renders the moving pieces locally
	-- on each machine. Everyone still sees them -- every client runs that script for every tagged player --
	-- but nothing crosses the network except this one attribute.
	local owner = Players:GetPlayerFromCharacter(char)
	if owner then
		owner:SetAttribute("DevAura", true)
	end

	-- The attachments and Sparkles hang off the character's own parts, not the folder, so clear them with it.
	folder.Destroying:Connect(function()
		for _, name in ipairs({ "AuraFoot", "AuraTrailA", "AuraTrailB", "AuraSparkles" }) do
			local inst = hrp:FindFirstChild(name)
			if inst then inst:Destroy() end
		end
		if head then
			local ca = head:FindFirstChild("AuraCrown")
			if ca then ca:Destroy() end
		end
	end)
end

-- ============================ 3. BUFF ============================
local function devBuff(devName)
	local active = Workspace:GetAttribute("ActiveServerEvent")
	if active and active ~= "" then
		print(("[DevArrival] buff SKIPPED -- '%s' is already running. Two events would cancel each other on"
			.. " the clients and its END would cut ours short. Banner/spectacle/crate still fired."):format(active))
		return
	end

	local msg = ("\xF0\x9F\x91\x91 %s IS ONLINE! Double coins for %d seconds!"):format(string.upper(devName), BUFF_SECONDS)
	pcall(function()
		-- Real COIN_RUSH key = real, already-tested mechanics. Only the label and duration are ours.
		ServerEventNotify:FireAllClients("COIN_RUSH", "\xF0\x9F\x91\x91 DEV ONLINE", BUFF_SECONDS, msg, GOLD)
	end)
	Workspace:SetAttribute("ActiveServerEvent", "COIN_RUSH")

	task.delay(BUFF_SECONDS + 2, function()
		-- Only clear if nothing else has claimed the slot in the meantime.
		if Workspace:GetAttribute("ActiveServerEvent") == "COIN_RUSH" then
			pcall(function() ServerEventNotify:FireAllClients("END", "", 0, "", Color3.new(1, 1, 1)) end)
			Workspace:SetAttribute("ActiveServerEvent", "")
		end
	end)
	print(("[DevArrival] DEV ONLINE buff: double coins for %ds (via COIN_RUSH)"):format(BUFF_SECONDS))
end

-- ============================ 4. CRATE DROP ============================
local function dropCrate(char, devName)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Sit it on the ground beside the dev rather than wherever their torso happens to be, so it is reachable
	-- and not buried or floating over a drop.
	local spot = hrp.Position + (hrp.CFrame.RightVector * 6)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local hit = Workspace:Raycast(spot + Vector3.new(0, 12, 0), Vector3.new(0, -60, 0), params)
	local restY = hit and (hit.Position.Y + 2.4) or (hrp.Position.Y + 1)

	local crate = Instance.new("Part")
	crate.Name = "DevCrate"
	crate.Size = Vector3.new(3.2, 3.2, 3.2)
	crate.CFrame = CFrame.new(Vector3.new(spot.X, restY, spot.Z))
	crate.Anchored = true
	crate.CanCollide = false
	crate.CanQuery = true -- the prompt needs it hittable
	crate.Material = Enum.Material.SmoothPlastic
	crate.Color = GOLD
	crate.Parent = Workspace
	do
		local s = Instance.new("SelectionBox")
		s.Adornee = crate
		s.Color3 = NAVY
		s.LineThickness = 0.08
		s.Parent = crate
	end

	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1
	hl.OutlineColor = LIME
	hl.OutlineTransparency = 0.2
	hl.Adornee = crate
	hl.Parent = crate

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 220, 0, 46)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 300
	bb.Parent = crate
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.Font = Enum.Font.FredokaOne
	lbl.Text = "DEV CRATE"
	lbl.TextColor3 = GOLD
	lbl.TextScaled = true
	lbl.Parent = bb
	do local st = Instance.new("UIStroke"); st.Color = NAVY; st.Thickness = 3; st.Parent = lbl end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DevCratePrompt"
	prompt.ObjectText = devName .. "'s Dev Crate"
	prompt.ActionText = "Open"
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.4
	prompt.Parent = crate

	-- Spin + bob so it reads as a pickup rather than scenery.
	local baseCF = crate.CFrame
	local spinning = true
	task.spawn(function()
		local t = 0
		while spinning and crate.Parent do
			t += task.wait()
			crate.CFrame = baseCF
				* CFrame.new(0, math.sin(t * 2) * 0.35, 0)
				* CFrame.Angles(0, t * 1.2, 0)
		end
	end)

	local claimed = {} -- [userId] = true; one open each, so it is a server-wide gift, not a race
	prompt.Triggered:Connect(function(player)
		if claimed[player.UserId] then return end
		if type(_G.skinCrateFreeOpen) ~= "function" then
			warn("[DevArrival] _G.skinCrateFreeOpen missing -- SkinCrateService has not loaded; crate not opened")
			return
		end
		claimed[player.UserId] = true
		local ok, res = pcall(_G.skinCrateFreeOpen, player, CRATE_ID)
		if ok and type(res) == "table" and res.ok then
			-- SHOW THE REAL SPIN. skinCrateFreeOpen only GRANTS -- it is the server half of the flow, so on
			-- its own the item lands in the Collection Book with no UI at all (which is what happened the
			-- first time: the log said "opened Premium -> Sand PopcornSheep" and the player saw nothing).
			-- Handing the same result to the client's _G.skinCrateShowReveal plays the identical reel a paid
			-- open plays, and its own teardown drops the player on the crate list afterwards.
			DevCrateReveal:FireClient(player, CRATE_ID, res)
			print(("[DevArrival] %s opened the dev crate -> reveal sent"):format(player.Name))
		else
			claimed[player.UserId] = nil -- the open failed, so don't burn their one shot
			warn(("[DevArrival] crate open failed for %s: %s"):format(player.Name,
				(type(res) == "table" and tostring(res.reason)) or tostring(res)))
		end
	end)

	task.delay(CRATE_SECONDS, function()
		spinning = false
		if crate.Parent then
			TweenService:Create(crate, TweenInfo.new(0.6), { Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2) }):Play()
			Debris:AddItem(crate, 0.8)
		end
	end)

	print(("[DevArrival] dev crate dropped at (%d, %d, %d) -- claimable for %ds, once per player")
		:format(crate.Position.X, crate.Position.Y, crate.Position.Z, CRATE_SECONDS))
end

-- ============================ THE MOMENT ============================
local function celebrate(player, char)
	if announced[player.UserId] then return end
	announced[player.UserId] = true

	-- Let them finish loading in before the ground erupts under them.
	task.wait(2.5)
	if not (player.Parent and char.Parent) then return end

	-- Read the island AFTER the 2.5s settle above: the leaderstat is written during the join/load, and asking
	-- for it the instant the character appears can catch it still at its default.
	local islandName, islandNum = islandNameOf(player)
	print(("[DevArrival] === %s (dev) has arrived on %s ==="):format(player.Name, islandName or "an unknown island"))

	pcall(function() DevArrivalEvent:FireAllClients(player.Name, islandName, islandNum) end) -- 1. banner
	pcall(spectacle, char)                                                                   -- 2. spectacle
	pcall(devBuff, player.Name)                                                              -- 3. buff
	pcall(dropCrate, char, player.Name)                                                      -- 4. crate
end

-- THE AURA IS SEPARATE FROM THE ARRIVAL, on purpose.
--
-- `celebrate` is once-per-server (banner, spectacle, buff, crate -- things that would be obnoxious on every
-- respawn). The aura is the opposite: it should be on the WHOLE time a dev is online, so it re-applies on
-- every single spawn. Hanging it off `celebrate` would have meant losing it the first time you died.
local function auraFor(player, char)
	-- The torso/head can lag the character model by a frame or two; applyAura needs the HumanoidRootPart.
	local t0 = os.clock()
	while not char:FindFirstChild("HumanoidRootPart") and (os.clock() - t0) < 10 and char.Parent do
		task.wait(0.1)
	end
	if not char.Parent then return end
	char:WaitForChild("Head", 5)
	local ok, err = pcall(applyAura, char)
	if not ok then
		warn(("[DevArrival] aura failed for %s: %s"):format(player.Name, tostring(err)))
	end
end

local function hook(player)
	-- THE PAUSE. Before isDev on purpose: while this is off nobody is treated as a dev at all, so there is no
	-- path to the banner, the buff, the crate or the aura, and no per-join logging singling an account out.
	if not ENABLED then return end
	if not isDev(player) then return end
	print(("[DevArrival] %s recognised as a dev -- aura on every spawn"):format(player.Name))
	if player.Character then
		task.spawn(celebrate, player, player.Character)
		task.spawn(auraFor, player, player.Character)
	end
	player.CharacterAdded:Connect(function(char)
		task.spawn(celebrate, player, char)  -- once per server (guarded inside)
		task.spawn(auraFor, player, char)    -- EVERY spawn
	end)
end

Players.PlayerAdded:Connect(hook)
for _, player in ipairs(Players:GetPlayers()) do hook(player) end -- Studio: already in-game before this ran

Players.PlayerRemoving:Connect(function(player)
	-- Deliberately NOT clearing `announced`: leaving and rejoining the same server must not re-trigger it.
	-- The table is per-server and dies with the server, so a genuinely new session gets the moment again.
end)

local idCount = 0
for _ in pairs(DEV_USER_IDS) do idCount += 1 end
if not ENABLED then
	-- Say so plainly. A boot line still reading "online -- dev join = banner + spectacle..." while nothing
	-- fires is exactly how an intentional pause gets mistaken for a broken feature later.
	print("[DevArrival] PAUSED -- devs join as normal players (no banner, spectacle, buff, crate or aura). "
		.. "Set ENABLED = true at the top of DevArrival.server.luau to bring it back.")
else
	print(("[DevArrival] online -- dev join = banner + spectacle + %ds double coins + a %ds dev crate."
		.. " Once per dev per server. Matching on %d user id(s) + 3 username(s)%s")
		:format(BUFF_SECONDS, CRATE_SECONDS, idCount,
			idCount == 0 and " -- ADD THE USER IDS to DEV_USER_IDS; usernames break the moment anyone renames." or ""))
end
