--======================================================================
-- GardenGuideTrail.client.luau   (StarterPlayerScripts)
--======================================================================
-- THE SPACE REALM'S GUIDE ARROW, driving this realm's guidance. The ground trail of up to
-- 26 green chevrons is gone; what points the way now is the single teal neon arrow that
-- floats at chest height in front of you, ported in Shared/GuideArrow.luau from the Space
-- Realm's Mercury/Venus arrow.
--
-- ⚠ ONLY THE RENDERING CHANGED. Every _G entry point is untouched -- guideTrailTo,
-- guideTrailClear, guideTrailNpc, startGardenGuide -- because nine quest scripts and
-- NpcGuideArrow call into them, and the whole priority scheme below (egg beats NPC beats
-- tutorial) is the part worth keeping. It leads the player —
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

local Shared     = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GuideArrow = require(Shared:WaitForChild("GuideArrow"))

local STOP_DIST  = 7    -- treat the player as ARRIVED this many studs from the target

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

-- ---- THE ARROW -----------------------------------------------------------------------
-- One arrow, owned here. `activeTarget` is written by the resolver at the bottom of this
-- file and read by the arrow every frame, so the priority logic stays in one place and the
-- module stays a dumb renderer.
--
-- reachDistance = 0 DISABLES the module's own proximity removal on purpose: this script
-- already has STOP_DIST, and arriving has side effects here (advancing the tutorial stage)
-- that the module knows nothing about. Two things deciding "arrived" would race.
local activeTarget = nil
local arrowHandle  = nil

local function showArrow()
	if arrowHandle then return end
	arrowHandle = GuideArrow.start({
		tag = "CandyGuide", targetName = "your objective", reachDistance = 0,
		getPosition = function() return activeTarget end,
	})
end

local function hideArrow()
	if arrowHandle then GuideArrow.stop(arrowHandle); arrowHandle = nil end
end

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
local override  = nil    -- Vector3 set by _G.guideTrailTo(); nil = fall back to the tutorial route
local npcTarget = nil    -- LOW PRIORITY slot, set by NpcGuideArrow: the island NPC you have not met
local flownOnce = false  -- LATCH: true forever once the player first fart-flies. Ends the TUTORIAL route only.

_G.startGardenGuide = function()
	if not started then started = true; print("[GardenGuideTrail] started -> guiding to the Gardener") end
end

-- Point the trail at ANY world position. Meant to be called every frame by whoever owns the target: it is cheap,
-- and it is self-correcting -- stop calling it (or call _G.guideTrailClear) and the trail puts itself away.
_G.guideTrailTo = function(pos)
	override = (typeof(pos) == "Vector3") and pos or nil
end
_G.guideTrailClear = function()
	override = nil
end

-- A SECOND, LOWER-PRIORITY SLOT. NpcGuideArrow points this at the quest giver on whichever
-- island you just landed on. It is deliberately not the same slot as the override: a hatchable
-- egg has to beat an NPC every time, and with one slot whichever script wrote last would win,
-- so the trail would flicker between the two rather than choosing.
_G.guideTrailNpc = function(pos)
	npcTarget = (typeof(pos) == "Vector3") and pos or nil
end

local conn
conn = RunService.RenderStepped:Connect(function()
	-- ⚠ NOT DURING THE INTRO. The cinematic hides every ScreenGui in the game (setAllGuis) --
	-- but this arrow is WORKSPACE PARTS, not GUI, so that sweep cannot touch it: a neon arrow
	-- would hang in front of the camera through the whole descent. The old ground chevrons were
	-- gated by accident (nothing set a target until the intro called _G.startGardenGuide); the
	-- arrow needs the guard stated outright. _G.introPlaying is the realm's existing flag for
	-- this -- ArrivalCinematic and GutGrowCinematic both already stand down on it.
	if _G.introPlaying then hideArrow(); return end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then hideArrow(); return end

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
		hideArrow()
		print("[GardenGuideTrail] player fart-flew -> Bean Farm tutorial arrows removed for good"
			.. " (egg trails still work)")
	end

	-- Mid-flight there is no ground to lay chevrons on. HIDE, do not destroy -- we want the trail
	-- back on landing.
	--
	-- BUT NOT ON THE FLAG ALONE. _G.isFlying belongs to the flight system and only has to be
	-- right for flight; if it lingers true after a landing or a teleport, this returns every
	-- frame and the trail is simply gone, with nothing anywhere saying why. So the flag hides
	-- the trail only when the player is ALSO off the ground. Standing on something, the trail
	-- draws regardless of what the flag currently says.
	if _G.isFlying then
		local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -14, 0), rayParams)
		if not hit then hideArrow(); return end
	end

	-- A hatchable egg (override) beats the tutorial route. With neither, the trail idles.
	local tpos
	if override then
		tpos = override
	elseif npcTarget then
		tpos = npcTarget
	elseif started and stage < 3 and not flownOnce then
		tpos = (stage == 1) and gardenerPos() or standPos()
	end
	if not tpos then hideArrow(); return end -- nothing to point at, or the target is not in the world yet

	local d = tpos - hrp.Position
	local flat = Vector3.new(d.X, 0, d.Z)
	local dist = flat.Magnitude
	if dist <= STOP_DIST then
		hideArrow()
		-- Arriving at an EGG or an ISLAND NPC must not advance the tutorial stage -- the routes are unrelated,
		-- and letting either tick the tutorial forward would silently skip the food stand for anyone who hatched
		-- a pet, or met a quest giver, first. Both owners stop calling in once they are done, so the trail clears
		-- itself either way. Only the tutorial route may move the tutorial on.
		if not override and not npcTarget then
			stage += 1
			if stage == 2 then print("[GardenGuideTrail] reached the Gardener -> re-routing to the FOOD STAND")
			else print("[GardenGuideTrail] reached the food stand -> guidance complete") end
		end
		return
	end
	-- RANGE CAP. 400 was chosen for the Bean Farm tutorial, where the gardener and the food
	-- stand are a short walk apart. An island NPC is easily twice that from where you land, and
	-- hitting this cap is SILENT -- the trail just draws nothing, which is indistinguishable
	-- from a broken script. So the NPC route gets a cap that matches the distances it actually
	-- deals with, and the tutorial keeps its tight one.
	local CAP = npcTarget and 900 or 400
	if dist > CAP then hideArrow(); return end

	-- point the arrow and make sure it is up. The arrow itself handles the hover, the bob and
	-- the aiming; all this loop owns is WHICH position it is aiming at.
	activeTarget = tpos
	showArrow()
end)

print("[GardenGuideTrail] loaded -- SPACE REALM guide arrow (Shared/GuideArrow, teal neon, "
	.. "chest height) replaces the ground chevrons; _G.guideTrailTo / guideTrailNpc unchanged")
