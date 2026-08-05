--======================================================================
-- GardenGuideTrail.client.luau   (StarterPlayerScripts)
--======================================================================
-- A SLEEK GREEN CHEVRON TRAIL (the EXACT look from GreenChevronTrail): a flat,
-- striped "runway" of chevron arrows on the ground that leads the player —
--   1) first to the GARDENER (the global Community Garden NPC), then
--   2) once they arrive, re-routes to the Island 1 FOOD STAND.
-- The trail switches off once they reach the stand.
--
-- It only runs AFTER the Community Garden intro: GardenIntro calls
-- _G.startGardenGuide() the instant the intro finishes (or is skipped).
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local player     = Players.LocalPlayer

-- ===== look / motion tuning (EXACT from GreenChevronTrail) =====
local BRIGHT     = Color3.fromRGB(90, 200, 110) -- friendly green
local EDGE       = Color3.fromRGB(40, 120, 60)  -- darker green outline
local SPACING    = 6    -- studs between chevrons
local MAX_ARROWS = 18   -- most chevrons drawn at once
local STOP_DIST  = 7    -- stop the trail this many studs short of the target ("arrived")
local prefix     = "GardenGuide"

-- ============================================================================
-- TARGET FINDERS (gardener, then island-1 food stand) — return a world position.
-- ============================================================================
local function findGardener()
	local build = Workspace:FindFirstChild("CommunityGardenBuild", true)
	if build then
		local props = build:FindFirstChild("GardenProps")
		local g = props and props:FindFirstChild("Gardener")
		if g and g:IsA("Model") then return g end
		for _, d in ipairs(build:GetDescendants()) do
			if d:IsA("Model") and d:GetAttribute("GardenerNPC") then return d end
		end
	end
	local byName = Workspace:FindFirstChild("Gardener", true)
	if byName and byName:IsA("Model") then return byName end
	return nil
end

local function findIsland1()
	local exact = Workspace:FindFirstChild("Bean Farm")
	if exact and exact:IsA("Model") then return exact end
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") and obj.Name:match("^Island_1_") then return obj end
	end
	return nil
end
local function findStandPart()
	local island = findIsland1()
	if island then
		for _, obj in ipairs(island:GetDescendants()) do
			if obj:IsA("Model") and (obj.Name == "Stand_1" or obj.Name:match("^Stand")) then
				local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
				if part then return part end
			end
		end
	end
	return nil
end

-- cache once found (islands/garden are persistent), re-find only if it goes away
local cachedGardener, cachedStandPart
local function gardenerPos()
	if not (cachedGardener and cachedGardener.Parent) then cachedGardener = findGardener() end
	return cachedGardener and cachedGardener:GetPivot().Position or nil
end
local function standPos()
	if not (cachedStandPart and cachedStandPart.Parent) then cachedStandPart = findStandPart() end
	if cachedStandPart then return cachedStandPart.Position end
	local p = Workspace:GetAttribute("Stand1Pos") -- server-published fallback
	if typeof(p) == "Vector3" then return p end
	return nil
end

-- ============================================================================
-- SLEEK GREEN CHEVRON TRAIL — flat striped runway of chevron arrows (EXACT build).
-- ============================================================================
local rayParams = RaycastParams.new(); rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function part(model, name, sx, sy, sz, color, refl, cf)
	local p = Instance.new("Part"); p.Name = name; p.Size = Vector3.new(sx, sy, sz); p.Color = color
	p.Material = Enum.Material.SmoothPlastic; p.Reflectance = refl or 0
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.LeftSurface = Enum.SurfaceType.Smooth; p.RightSurface = Enum.SurfaceType.Smooth
	p.FrontSurface = Enum.SurfaceType.Smooth; p.BackSurface = Enum.SurfaceType.Smooth
	p.CFrame = cf; p.Parent = model; return p
end
-- one chevron ">" pointing -Z (forward), lying flat (thin in Y): darker edge base + glossy bright top
local function buildChevron()
	local m = Instance.new("Model"); m.Name = prefix .. "Chevron"
	local root = part(m, "Root", 0.2, 0.2, 0.2, BRIGHT, 0, CFrame.new()); root.Transparency = 1; m.PrimaryPart = root
	local L, W, T, ANG = 2.6, 0.72, 0.22, math.rad(42)
	local front = CFrame.new(0, 0, -0.9) -- the chevron POINT
	part(m, "EdgeR", W + 0.20, T * 0.65, L + 0.20, EDGE, 0, front * CFrame.Angles(0,  ANG, 0) * CFrame.new(0, -0.03, L / 2))
	part(m, "EdgeL", W + 0.20, T * 0.65, L + 0.20, EDGE, 0, front * CFrame.Angles(0, -ANG, 0) * CFrame.new(0, -0.03, L / 2))
	part(m, "ArmR",  W, T, L, BRIGHT, 0.14,                front * CFrame.Angles(0,  ANG, 0) * CFrame.new(0,  0.04, L / 2))
	part(m, "ArmL",  W, T, L, BRIGHT, 0.14,                front * CFrame.Angles(0, -ANG, 0) * CFrame.new(0,  0.04, L / 2))
	m.Parent = Workspace
	return m
end
local pool = {}
local function getNode(i) if not pool[i] then pool[i] = buildChevron() end; return pool[i] end
local function setShown(nd, on)
	for _, p in ipairs(nd:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Root" then p.Transparency = on and 0 or 1 end
	end
end
local function hideFrom(n) for i = n, #pool do if pool[i] then setShown(pool[i], false) end end end
local function destroyAll() for _, nd in ipairs(pool) do pcall(function() nd:Destroy() end) end; pool = {} end

-- ============================================================================
-- STATE
--
-- The trail has TWO jobs now:
--   1. The TUTORIAL route, started by the garden intro: gardener (stage 1) -> food stand (stage 2) -> done.
--   2. An OVERRIDE target any other script can set. PetFollow uses it to walk you to a hatchable egg the moment a
--      pet quest completes (3/3 broccoli pieces, 6/6 film reels, and so on). It takes PRIORITY over the tutorial:
--      "your egg is ready" always matters more than "here is the food stand".
--
-- TWO THINGS HAD TO CHANGE for job 2 to be possible, and both were perfectly correct for a tutorial-only trail:
--
--   * It used to DESTROY itself and disconnect FOREVER at stage 3. Fine for a one-shot tutorial, fatal for
--     anything later -- the eggs are on islands 2, 5, 8, 10 and 13, and by the time you reach any of them the
--     trail no longer existed. It now stays alive and simply idles (hidden) when it has nothing to point at.
--
--   * It used to kill itself permanently the moment you first fart-flew. Also fatal: every egg after the first is
--     REACHED by flying. Flying now merely HIDES it -- ground chevrons are meaningless mid-air anyway -- and it
--     comes back when you land.
-- ============================================================================
local started   = false
local stage     = 1
local airborneSince = nil -- os.clock() the player left the ground (nil while grounded); see the airborne gate
local override  = nil    -- Vector3 set by _G.guideTrailTo(); nil = fall back to the tutorial route
local npcTarget = nil    -- Vector3 set by _G.guideTrailNpc(); LOWER priority than override
local flownOnce = false  -- LATCH: true forever once the player first fart-flies. Ends the TUTORIAL route only.

-- ===== SAY WHICH LEG THE ARROWS ARE ON =====
-- The on-screen objective card (ObjectiveHUD) used to run its own opinion of what the player should do next,
-- and it opened on "BUY BEANS AT THE FOOD STAND" -- while these arrows were pointing at the GARDENER. The
-- words and the arrows disagreed on the very first instruction a new player is given, which is the one moment
-- they are least able to work out which to trust.
--
-- Rather than teach the card to recompute the route (two copies of the same logic, guaranteed to drift), the
-- trail publishes the leg it is ACTUALLY drawing and the card reads it. The trail owns the route; it is the
-- thing that knows whether the Gardener has been reached, and it is the thing the player can see.
--
--   "gardener" -> arrows point at the Gardener
--   "stand"    -> arrows point at the Island 1 food stand
--   nil        -> no tutorial arrows (not started, both legs done, or the player has flown)
local function publishStep()
	local s = nil
	if started and not flownOnce and stage < 3 then
		s = (stage == 1) and "gardener" or "stand"
	end
	if _G.gardenGuideStep ~= s then _G.gardenGuideStep = s end
end
publishStep()

-- ===== WATERING COMPLETES THE GARDENER LEG =====
-- The gardener leg used to end ONLY by proximity: step within STOP_DIST (7 studs) of the gardener's pivot.
-- But the actual interaction happens at prompt range and then over at the plots -- take the can, walk to the
-- field, water it -- so a player can finish the whole gardener step without ever tripping the 7-stud check
-- (and the arrival guard below deliberately refuses to advance while an NPC target is live). Result: they
-- watered the garden and the arrows still pointed back at the gardener.
--
-- The server publishes HasWateredGarden on the first successful water (CommunityGarden.server.lua) -- that IS
-- "the gardener interaction is complete", stated by the authority. The moment it lands, re-route to the stand.
-- Checked once on load too, for a player who watered before this script (or the trail) started.
local function gardenerLegDone()
	if stage == 1 then
		stage = 2
		publishStep()
		print("[GardenGuideTrail] garden watered -> gardener leg complete, re-routing to the FOOD STAND")
	end
end
if player:GetAttribute("HasWateredGarden") == true then gardenerLegDone() end
player:GetAttributeChangedSignal("HasWateredGarden"):Connect(function()
	if player:GetAttribute("HasWateredGarden") == true then gardenerLegDone() end
end)

-- ===== THE ARROWS WAIT FOR THE STARTER-PET CARD =====
-- GardenIntro calls this the instant the cinematic finishes or is skipped -- and that is the SAME moment
-- PetFollow's "YOUR FIRST PET!" welcome card is waiting for, because it is gated on the intro too. So both
-- landed together: the card announcing the free Bean Buddy, and a line of green chevrons already pulling
-- the player's eye across the floor toward the Gardener. The two instructions arrived at once and competed.
--
-- The arrows now hold until the card has gone. _G.starterWelcome is PetFollow's handshake -- "pending" from
-- the moment the grant lands, "showing" while the card is up, "done" once it has faded. This is the same
-- gate ObjectiveHUD's directions card uses, so the words and the arrows still appear together as a pair;
-- they just appear after the pet, not on top of it.
--
-- EVERY caller is a first-timer by construction (the intro only plays for a player who has not seen it), so
-- there is no returning-player branch to write here -- unlike ObjectiveHUD, which is built on every join.
-- The 8s grace covers a first-timer whose grant failed or never arrived; the 45s ceiling means a welcome
-- that never resolves delays the arrows rather than cancelling them.
local starting = false
_G.startGardenGuide = function()
	if started or starting then return end
	starting = true
	task.spawn(function()
		local waited = 0
		while _G.starterWelcome == nil and waited < 8 do task.wait(0.25); waited = waited + 0.25 end
		while (_G.starterWelcome == "pending" or _G.starterWelcome == "showing") and waited < 45 do
			task.wait(0.25); waited = waited + 0.25
		end
		if started then return end
		started = true; publishStep()
		print(("[GardenGuideTrail] started -> guiding to the Gardener (waited %.1fs for the starter-pet card: %s)")
			:format(waited, tostring(_G.starterWelcome)))
	end)
end

-- Point the trail at ANY world position. Meant to be called every frame by whoever owns the target: it is cheap,
-- and it is self-correcting -- stop calling it (or call _G.guideTrailClear) and the trail puts itself away.
_G.guideTrailTo = function(pos)
	override = (typeof(pos) == "Vector3") and pos or nil
end
_G.guideTrailClear = function()
	override = nil
end
-- SECOND, LOWER-PRIORITY SLOT: the island's quest NPC (owned by NpcGuideArrow).
--
-- Two slots rather than one because with a single slot whichever script wrote last would win each
-- frame, and the trail would FLICKER between a hatchable egg and an NPC instead of choosing one.
-- An egg always beats an NPC: it's the thing the player is mid-way through.
_G.guideTrailNpc = function(pos)
	npcTarget = (typeof(pos) == "Vector3") and pos or nil
end

local conn
conn = RunService.RenderStepped:Connect(function()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then hideFrom(1); return end

	-- THE FIRST FART ENDS THE TUTORIAL, PERMANENTLY.
	--
	-- The moment the player hits the fart button (_G.isFlying goes true in startFlying), the Bean Farm arrows have
	-- done their job and must never come back -- they are onboarding, and someone who has flown is not onboarding
	-- any more. A trail that reappears every time they walk past the food stand is nagging, not guidance.
	--
	-- This is a LATCH, not a check: flownOnce stays true for the rest of the session, so landing does not revive
	-- the tutorial. It kills ONLY the tutorial route -- the egg override below is untouched, and still lights up
	-- on every island for the rest of the game.
	if _G.isFlying and not flownOnce then
		flownOnce = true
		stage = 3 -- tutorial over: gardener + food-stand arrows are done for good
		publishStep() -- and the objective card drops back to its own advice, since there are no arrows to follow
		hideFrom(1)
		print("[GardenGuideTrail] player fart-flew -> Bean Farm tutorial arrows removed for good"
			.. " (egg trails still work)")
	end

	-- Mid-flight there is no ground to lay chevrons on. HIDE, do not destroy -- we want the egg trail back on landing.
	if _G.isFlying then hideFrom(1); return end

	-- AIRBORNE WITHOUT FLYING = ALSO NO GROUND ARROWS. Falling after a fart (isFlying already false),
	-- getting knocked off an edge, drifting down under glide -- in all of those the ground rays below
	-- find nothing and fell back to "chevron at body height", which drew a line of arrows FLOATING in
	-- open sky that followed the player down. Ground guidance only means anything when there is ground.
	-- The 0.35s grace keeps ordinary hops from blinking the trail off.
	local humA = char:FindFirstChildOfClass("Humanoid")
	if humA and humA.FloorMaterial == Enum.Material.Air then
		airborneSince = airborneSince or os.clock()
		if os.clock() - airborneSince > 0.35 then hideFrom(1); return end
	else
		airborneSince = nil
	end

	-- PRIORITY: a hatchable egg (override) > the tutorial route > the island's quest NPC.
	-- With none of them, the trail idles.
	local tpos
	if override then
		tpos = override
	elseif started and stage < 3 and not flownOnce then
		tpos = (stage == 1) and gardenerPos() or standPos()
	elseif npcTarget then
		tpos = npcTarget
	end
	if not tpos then hideFrom(1); return end -- nothing to point at, or the target is not in the world yet

	local d = tpos - hrp.Position
	local flat = Vector3.new(d.X, 0, d.Z)
	local dist = flat.Magnitude
	if dist <= STOP_DIST then
		hideFrom(1)
		-- Arriving at an EGG must not advance the tutorial stage -- the two routes are unrelated, and letting an
		-- egg tick the tutorial forward would silently skip the food stand for anyone who hatched a pet first.
		-- PetFollow stops calling guideTrailTo once the egg is hatched, so the trail clears itself.
		-- ...and neither must arriving at an NPC. Any third consumer added here MUST be in this
		-- guard too, or walking up to it silently advances the Bean Farm tutorial past the stand.
		if not override and not npcTarget then
			stage += 1
			publishStep() -- the card follows the arrows to the next leg on the same frame they re-route
			if stage == 2 then print("[GardenGuideTrail] reached the Gardener -> re-routing to the FOOD STAND")
			else print("[GardenGuideTrail] reached the food stand -> guidance complete") end
		end
		return
	end
	if dist > 400 then hideFrom(1); return end -- target far away (e.g. another island)
	local dir = flat.Unit

	-- exclude the player + every chevron so the ground ray doesn't hit them
	local excl = { char }; for _, nd in ipairs(pool) do excl[#excl + 1] = nd end
	rayParams.FilterDescendantsInstances = excl
	local maxAlong = dist - STOP_DIST
	local placed = 0
	for i = 1, MAX_ARROWS do
		local along = i * SPACING
		if along > maxAlong then break end
		placed += 1
		local px = hrp.Position.X + dir.X * along
		local pz = hrp.Position.Z + dir.Z * along
		local hit = Workspace:Raycast(Vector3.new(px, hrp.Position.Y + 14, pz), Vector3.new(0, -240, 0), rayParams)
		local gy = (hit and hit.Position.Y) or (hrp.Position.Y - 2.5)
		local nd = getNode(placed)
		-- FLAT on the ground (Y up), pointing toward the target (-Z = dir)
		local p0 = Vector3.new(px, gy + 0.12, pz)
		pcall(function() nd:PivotTo(CFrame.lookAt(p0, p0 + dir)) end)
		-- gentle pulse that FLOWS toward the target
		pcall(function() nd:ScaleTo(1 + 0.10 * math.sin(os.clock() * 5 - i * 0.8)) end)
		setShown(nd, true)
	end
	hideFrom(placed + 1)
end)

print("[GardenGuideTrail] loaded -- tutorial route after the intro, plus _G.guideTrailTo(pos) for eggs")
