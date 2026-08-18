--======================================================================
-- PancakeMonsterQuest_AllInOne.client.lua  (LocalScript)  -- CandyRealm
--======================================================================
-- ISLAND 18 -- "WAKE THE PANCAKE MONSTER"
--
--   1. FIND    five giant syrup bottles hidden around the island
--   2. POUR    each one onto the giant pancake in the arena at the centre
--   3. WAKE    the pancake shakes, RISES, and a huge Pancake Monster stands up under it
--   4. RUN     it hunts you across the island, smashing the ground as it comes
--   5. BUTTER  collect eight pieces of butter while it chases you
--   6. THROW   lob the lot at it -- it melts into a giant pile of pancakes
--
--   Reward: coins (CoinEvent), a fart-power top-up and crate tokens (both once ever,
--   through IslandTaskTokens' ledger), plus the quest's entry in the Quest Journal.
--
-- ===== WHAT THIS IS BUILT OUT OF =====
-- The MONSTER is ChocolateMonster_AllInOne's, rebuilt as a pancake: the same offset-table
-- rig (`monParts` = {part, off, anim}), the same `poseMonster()` that glues every limb to
-- the body's CFrame each frame, the same pivotSwing/jiggle/chomp animators, and the same
-- sleep -> hunt -> stunned -> strollhome state machine driven off RenderStepped with a
-- ground raycast under each step. Speeds stay UNDER a player's WalkSpeed of 16 on purpose,
-- exactly as the chocolate one does: you can always out-run it in a straight line, and it
-- only catches kids who stop, get cornered, or run into it. It never kills -- it shoves.
--
-- The QUEST SHELL is CandyMineExplosionQuest's, because that is the other off-ladder island
-- with the same shape (find five, bring them to the centre, big finale): the "...Objective"
-- ScreenGui name that ObjectiveBannerBridge mirrors onto the realm banner, the 320x150
-- FredokaOne speech bubble with the "[E] more (n/m)" footer, norm()'d marker matching, and
-- the CoinEvent payout.
--
-- ⚠ ISLAND 18 IS OFF THE LADDER, like island16. It is not in IslandOrder.SLOT_TO_ISLAND, so
-- IslandLayout leaves it wherever Studio has it and no crossing leads to it. The one thing it
-- still needs from the tower plumbing is STREAMING PERSISTENCE -- island18 has been added to
-- IslandStreaming's EXTRA_PERSIST for exactly that reason. Without it the island's parts do
-- not replicate at distance and every marker here reads as missing.
--
-- ===== NO MARKERS ARE REQUIRED =====
-- Name parts on island18 and this quest uses them; name nothing and it still runs:
--   * "PancakeArena" -- where the giant pancake sits. Falls back to the island's centre.
--   * "syrup"  x5    -- where the bottles hide.  Falls back to a spiral around the arena.
--   * "butter" x8    -- where the butter lies.   Falls back to a wider spiral.
--   * "Candy Npc"    -- the quest giver. Falls back to a prompt on the pancake itself.
-- Everything else (the pancake, the monster, the bottles, the butter) is built in code, so
-- there is nothing to place and nothing to keep in sync.
--
-- ===== EVERYTHING IS ANCHORED =====
-- Every part this script makes goes through mk(), which anchors. A sweep re-anchors anything
-- that arrives loose (see anchorAll), and it runs on a timer, not once. Even the items you
-- CARRY are anchored: they are re-CFramed onto your back every frame rather than welded into
-- the character, which is the usual way and the one that leaves unanchored parts in the world.
-- Nothing this quest creates is ever simulated by physics.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")  -- CoinEvent + the token claim
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_NAME    = "island18"
local ARENA_NAME     = "pancakearena"   -- optional: where the giant pancake sits
local SYRUP_NAME     = "syrup"          -- optional: up to five hiding spots
local BUTTER_NAME    = "butter"         -- optional: up to eight lying-about spots
local NPC_HINT       = "candynpc"

local SYRUP_COUNT    = 5
local BUTTER_COUNT   = 8

local TALK_DISTANCE  = 12
local BANNER_RANGE   = 400              -- island18 is a big arena; the banner stays up across it
local PICKUP_RANGE   = 12
local POUR_RANGE     = 26               -- how close to the pancake to pour a bottle
local THROW_RANGE    = 34               -- how close to the monster to let the butter fly

-- ===== THE MONSTER'S NUMBERS -- ChocolateMonster's, unchanged where they matter =====
-- Your WalkSpeed is 16. SPEED_MAX stays under it on purpose: a straight-line sprint always
-- gets away, so the chase is scary without ever being unfair. Do not raise it past 15.
local AGGRO_RANGE    = 95
local LEASH_RANGE    = 300
local CATCH_RANGE    = 7
local SPEED_MIN      = 9
local SPEED_MAX      = 14
local RAMP_TIME      = 16               -- seconds of chasing before it hits SPEED_MAX
local WANDER_SPEED   = 5
local KNOCK_BACK     = 62               -- how hard it shoves you (it never damages)
local KNOCK_UP       = 24
local SMASH_EVERY    = 3.4              -- seconds between ground smashes while hunting
local ISLAND_RANGE   = 800              -- how far off the arena it will follow before giving up

-- audio (owned ids only; "" = silent and nothing is created)
local SOUND_ROAR     = "rbxassetid://135109687089247"
local SOUND_POUR     = ""
local SOUND_PICKUP   = ""
local SOUND_SMASH    = ""

-- palette -- pancake breakfast: batter gold, syrup brown, butter yellow
local FILL    = Color3.fromRGB(255, 246, 232)
local STROKE  = Color3.fromRGB(176,  98,  40)
local TEXTC   = Color3.fromRGB( 82,  46,  20)
local HINTC   = Color3.fromRGB(168, 140, 116)
local CAKE    = Color3.fromRGB(232, 178,  96)   -- pancake body
local CAKE_HI = Color3.fromRGB(248, 208, 140)   -- the fluffy lit edge
local CAKE_LO = Color3.fromRGB(176, 118,  52)   -- the browned underside
local SYRUP   = Color3.fromRGB(122,  62,  22)
local BUTTER  = Color3.fromRGB(255, 214,  84)
local GOLD    = Color3.fromRGB(255, 205,  90)
local GREEN   = Color3.fromRGB(110, 210, 120)

-- rewards
local COIN_REWARD    = 3000
local QUEST_ID       = "pancake"        -- CrateTokens.ISLAND_TASK / IslandTaskWatcher id

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s) return (tostring(s or ""):lower():gsub("[%s_%-]", "")) end

local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat local r = fn(); if r then return r end; task.wait(0.5) until os.clock() - t0 > (timeout or 45)
	return fn()
end

local function firstBasePart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function hrpOf()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function hrpFor(plr)
	local c = plr.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- EVERY part this quest builds is born anchored, non-colliding and unqueryable. Callers turn
-- CanQuery back on for the handful that carry a ProximityPrompt.
local function mk(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function playSound(id, vol)
	if not id or id == "" then return end
	local s = Instance.new("Sound"); s.SoundId = id; s.Volume = vol or 0.6
	s.Parent = SoundService; s:Play(); Debris:AddItem(s, 6)
end

local function tween(o, t, props, style, dir)
	local ti = TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local tw = TweenService:Create(o, ti, props); tw:Play(); return tw
end

-- ============================================================================
-- PLACEMENT BLOCKS -- the Studio-drawn markers this quest builds on
-- ============================================================================
-- Same convention as island15's Bake-Off: a block you draw gives POSITION and SIZE, and then
-- gets out of the way. Two rules, both learned the hard way over there:
--
--   * BUILD ON THE BLOCK'S BASE, NOT ITS CENTRE. A prop placed at the block's Position sits
--     half a block-height in the air, which on a tall marker is very obviously wrong. The
--     block's underside is where it visibly rests on the ground, so that is the ground line.
--   * THE BLOCK IS SCENERY THAT SHOULD NOT EXIST. Invisible, non-collidable, and unqueryable --
--     the last one matters most: a queryable marker still answers ground raycasts, so props
--     would seat themselves on top of the very block that was only meant to say "here".
local function baseFrameOf(part)
	local cf, sz = part.CFrame, part.Size
	return CFrame.new(Vector3.new(cf.Position.X, cf.Position.Y - sz.Y * 0.5, cf.Position.Z))
		* (cf - cf.Position)
end

-- SIZE IS THE SAFETY CATCH, NOT THE NAME.
-- This has now gone wrong twice on two islands: island15's "chicken zone" turned out to be the
-- island's entire floor, and island18's "placement boundaires" turned out to be a large area
-- part you can see. Both times the NAME read like a marker and the PART was structural, and
-- both times the symptom was the same -- a chunk of the island vanishing the moment the quest
-- adopted it. A name cannot be trusted to tell the two apart, so the size is checked instead:
-- a block that says "put a thing here" is about the size of the thing. Anything bigger than a
-- prop is left completely alone and says so, loudly, instead of disappearing.
local MARKER_MAX = 40   -- studs on either horizontal axis

local function hideMarker(part)
	if not (part and part:IsA("BasePart")) then return end
	if part.Size.X > MARKER_MAX or part.Size.Z > MARKER_MAX then
		warn(("[Pancake] REFUSING to hide '%s' (%.0f x %.0f studs) -- too big to be a marker. "
			.. "Its position and size are still used; set it invisible in Studio if you want it "
			.. "gone."):format(part:GetFullName(), part.Size.X, part.Size.Z))
		return
	end
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
end

-- ============================================================================
-- STATE
-- ============================================================================
-- step: 0 not accepted | 1 gather syrup | 2 pour | 3 the wake-up cinematic
--       4 gather butter (hunted) | 5 throw | 6 done
local step        = 0
local island                       -- the island18 Model
local arenaCF                      -- where the giant pancake sits
local pancake                      -- the giant pancake's main part
local poured      = 0
local butterHeld  = 0
local carrying    = nil            -- the syrup-bottle record in hand, if any
local syrups      = {}             -- { model=, main=, home=CFrame, taken=bool, prompt= }
local butters     = {}             -- { model=, main=, taken=bool, prompt= }
local npcHead
local refreshBanner                -- forward -- the banner block defines it
local refreshPrompts               -- forward -- one place decides what is pressable

_G.pancakeQuestComplete = false
_G.pancakeQuestStep     = nil      -- the small grey detail line in the Quest Journal

-- ============================================================================
-- THE QUEST FOLDER -- one parent, so the ground raycast can ignore everything
-- this quest built in a single line (a bottle standing on the monster's foot
-- counts as ground otherwise, and the pile slowly climbs into the sky).
-- ============================================================================
local questFolder = Instance.new("Folder")
questFolder.Name = "PancakeQuestLocal"; questFolder.Parent = Workspace

-- ...AND A SECOND FOLDER FOR SCENERY, WHICH IS NOT THE SAME THING.
-- The set dressing (the syrup pump, the butter launcher) is deliberately NOT in questFolder,
-- and the difference matters in exactly one place: spotClear() excludes questFolder from its
-- overlap query, because the first bottle placed would otherwise block every spot near it.
-- Scenery in that folder would inherit the exemption and syrup bottles would spawn INSIDE the
-- machines. Kept separate, the machines block placement like any other prop on the island --
-- while still being excluded from GROUND rays, so nothing gets seated on their roofs either.
local sceneryFolder = Instance.new("Folder")
sceneryFolder.Name = "PancakeScenery"; sceneryFolder.Parent = Workspace

local function homeToIsland()
	if island and questFolder.Parent ~= island then
		questFolder.Parent = island
		print("[Pancake] quest folder re-homed under " .. island:GetFullName())
	end
	if island and sceneryFolder.Parent ~= island then sceneryFolder.Parent = island end
end

-- BELT TO THE BRACES ON "ANCHOR EVERYTHING". mk() anchors, so this only ever catches
-- something added later that forgot -- but it runs forever on a timer rather than once at
-- boot, because the thing it is guarding against is a part that arrives LATE.
local function anchorAll()
	local n = 0
	for _, folder in ipairs({ questFolder, sceneryFolder }) do
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("BasePart") and not d.Anchored then d.Anchored = true; n += 1 end
		end
	end
	return n
end
task.spawn(function()
	while true do
		task.wait(5)
		homeToIsland()
		local loose = anchorAll()
		if loose > 0 then warn(("[Pancake] re-anchored %d loose part(s)"):format(loose)) end
	end
end)

-- ============================================================================
-- THE GROUND, AND THE ISLAND'S FOOTPRINT
-- ============================================================================
-- ⚠ THE LESSON FROM ISLAND 15, APPLIED UP FRONT. That island's whole walkable top is ONE
-- part, and the Bake-Off used to adopt it like a marker and hide it -- which turned the
-- island's floor invisible, non-collidable and UNRAYCASTABLE, so every prop on it looked
-- like it was floating and every ground ray fell through to an island thousands of studs
-- below. Nothing here ever hides a part it did not build, and the island's biggest-footprint
-- part is remembered as the FLOOR OF RECORD: a ray that misses (one fired from inside
-- geometry returns nothing at all) falls back to its top Y instead of to the void.
local floorPart, floorTopY, floorCF, floorHalf

local function findFloor(isle)
	local best, bestArea
	for _, d in ipairs(isle:GetDescendants()) do
		if d:IsA("BasePart") then
			local area = d.Size.X * d.Size.Z
			if not bestArea or area > bestArea then best, bestArea = d, area end
		end
	end
	if not best then return end
	floorPart = best
	floorCF, floorHalf = best.CFrame, best.Size * 0.5
	floorTopY = best.Position.Y + best.Size.Y * 0.5
	print(("[Pancake] floor of record: %s (%.0f x %.0f studs, top Y=%.0f)")
		:format(best:GetFullName(), best.Size.X, best.Size.Z, floorTopY))
end

-- ============================================================================
-- THE PLACEMENT BOUNDARY -- your "placement boundaires" part
-- ============================================================================
-- A part you drew on island18 marking where quest props are allowed to go. Everything this
-- quest scatters is sampled inside its footprint, in the part's OWN object space, so a
-- rotated or oddly-proportioned box still works and there is no assumption it is axis-aligned.
--
-- MATCHED ON BOTH SPELLINGS. The part in the world is "placement boundaires"; the word is
-- "boundaries". Rather than depend on which one survives the next time someone renames it,
-- both are accepted -- and norm() already strips case, spaces, underscores and hyphens.
local BOUND_NAMES = { placementboundaires = true, placementboundaries = true, placementboundary = true }
local boundPart, boundCF, boundHalf
local boundIsVolume       -- tall enough that props must not be seated on its lid (see below)

local function findBounds(isle)
	local function scan(scope)
		for _, d in ipairs(scope:GetDescendants()) do
			if d:IsA("BasePart") and BOUND_NAMES[norm(d.Name)] then return d end
		end
		return nil
	end
	boundPart = scan(isle) or scan(Workspace)
	if not boundPart then return end
	boundCF, boundHalf = boundPart.CFrame, boundPart.Size * 0.5
	-- A TALL BOX AND A FLAT PLATE NEED OPPOSITE TREATMENT in the ground raycast, and the only
	-- thing that distinguishes them is thickness. A volume you drew to enclose an area must be
	-- ignored by the ray, or every prop lands on its lid instead of on the island. A plate lying
	-- on the ground IS ground, and ignoring it would send the ray straight through to whatever
	-- is beneath. 8 studs is comfortably above any reasonable plate and below any useful volume.
	boundIsVolume = boundPart.Size.Y > 8

	-- ⚠⚠ THIS PART IS READ AND NEVER WRITTEN. NOT ONE PROPERTY. ⚠⚠
	--
	-- It was briefly hidden along with the small marker blocks, and it made the boundary
	-- VANISH -- the same failure as island15, where a part adopted as a "marker" turned out to
	-- be the island's floor and hiding it dropped players through the world. The lesson did not
	-- transfer the first time because the name looked conclusive: something called "placement
	-- boundaries" sounds like it can only be a marker. It is not. It is a large area part that
	-- is visibly part of the island, and the quest wants exactly two numbers off it -- a CFrame
	-- and a Size.
	--
	-- THE RULE, GENERALLY: hiding is safe for a block you drew to say "put a thing here" and
	-- nothing else. It is never safe for a part big enough to stand on. If a marker is bigger
	-- than a prop, read it and leave it alone. Set it invisible in Studio if you want it gone --
	-- that is a decision for the person who can see the island, not for this script.
	print(("[Pancake] placement boundary: %s (%.0f x %.0f x %.0f studs, read as a %s) -- read only, untouched")
		:format(boundPart:GetFullName(), boundPart.Size.X, boundPart.Size.Y, boundPart.Size.Z,
			boundIsVolume and "VOLUME: ignored by ground rays" or "PLATE: still valid ground"))
end

-- ============================================================================
-- FINDING YOUR BLOCKS -- inside the island, AND loose in Workspace beside it
-- ============================================================================
-- Every lookup in this file used to be island:GetDescendants() alone, which quietly misses a
-- whole class of block: IslandStreaming's boot audit reports 103 BaseParts sitting within a few
-- hundred studs of island18 but parented DIRECTLY to Workspace rather than into its Model. That
-- happens the moment a part is dragged into place in Studio without being re-parented, and the
-- symptom is indistinguishable from never having drawn it -- the quest reports it missing
-- forever and builds a fallback instead.
--
-- So: the island is searched first, then Workspace's own children, bounded by distance to the
-- island. The bound is what stops another island's identically-named block being grabbed, and
-- it is generous rather than tight because a loose part is by definition not where the model
-- thinks it is. Anything found loose is REPORTED, because the real fix is a Studio one.
local LOOSE_RADIUS = 600
local function findBlocks(wantedName, wantModels)
	local out = {}
	if not island then return out end
	local function ok(d)
		return (d:IsA("BasePart") or (wantModels and d:IsA("Model"))) and norm(d.Name) == wantedName
			and not d:IsDescendantOf(questFolder) and not d:IsDescendantOf(sceneryFolder)
	end
	for _, d in ipairs(island:GetDescendants()) do
		if ok(d) then out[#out + 1] = d end
	end
	local c = island:GetPivot().Position
	local loose = 0
	for _, d in ipairs(Workspace:GetChildren()) do
		if ok(d) and d ~= island then
			local pos = d:IsA("Model") and d:GetPivot().Position or d.Position
			if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude <= LOOSE_RADIUS then
				out[#out + 1] = d
				loose += 1
			end
		end
	end
	if loose > 0 then
		warn(("[Pancake] found %d '%s' block(s) parented to Workspace instead of inside island18. "
			.. "Used anyway, but drag them into the island's Model in Studio -- loose parts cannot "
			.. "inherit Persistent streaming and will vanish at distance."):format(loose, wantedName))
	end
	return out
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshRayFilter()
	-- scenery is excluded from GROUND rays (nothing gets seated on a machine's roof) but NOT
	-- from the overlap query in spotClear (nothing gets seated inside one either).
	local ex = { questFolder, sceneryFolder }
	-- the boundary joins them ONLY if it is a tall volume (a ray would otherwise land on its
	-- lid and float every prop up there). A flat plate on the ground is left in: it IS ground,
	-- and excluding it would punch the ray through to whatever lies beneath the island.
	if boundPart and boundIsVolume then ex[#ex + 1] = boundPart end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then ex[#ex + 1] = pl.Character end
	end
	rayParams.FilterDescendantsInstances = ex
end

local function groundAt(x, z, refY)
	refreshRayFilter()
	local hit = Workspace:Raycast(Vector3.new(x, refY + 60, z), Vector3.new(0, -260, 0), rayParams)
	return hit and hit.Position or nil
end

-- pull a world position inside the island's footprint, in the FLOOR's own object space so a
-- rotated island still works. `inset` keeps props off the rim.
local function clampToIsland(pos, inset)
	if not floorCF then return pos end
	local o = floorCF:PointToObjectSpace(pos)
	local m = inset or 6
	local hx, hz = math.max(1, floorHalf.X - m), math.max(1, floorHalf.Z - m)
	local cx, cz = math.clamp(o.X, -hx, hx), math.clamp(o.Z, -hz, hz)
	if cx == o.X and cz == o.Z then return pos end
	return (floorCF * CFrame.new(cx, o.Y, cz)).Position
end

-- WHERE A PROP GOES. Real geometry wins when there is any -- a rock, a ledge, the island's
-- own decking all deserve to be stood on. The floor of record catches the rest: a ray that
-- hits nothing, or one that hits something absurdly far below (off the edge, or a different
-- island entirely). The XZ is pulled inside the footprint FIRST, so nothing is ever seated
-- out over the void.
local function seatOn(x, z, refY, inset)
	local p = clampToIsland(Vector3.new(x, refY, z), inset or 10)
	x, z = p.X, p.Z
	local g = groundAt(x, z, refY)
	if g and math.abs(g.Y - refY) <= 90 then return g end
	if floorTopY then return Vector3.new(x, floorTopY, z) end
	return g
end

-- ============================================================================
-- IT WALKS AROUND THINGS, IT DOES NOT WALK OVER THEM
-- ============================================================================
-- The monster's height is "whatever the ground ray finds, plus 12". Walk it into a tree and the
-- ray finds the TREE, so it rides up the trunk and steps over the canopy -- a two-storey pancake
-- vaulting the scenery. Two halves to the fix, and both are needed:
--
--   1. THE FLOOR IS THE FLOOR (in groundY below): anything more than a few studs above the
--      island's own deck is something it is standing ON, not ground, so the deck height is used
--      instead and it can never climb.
--   2. IT STEERS (here): a box swept just ahead of the next step reports what is in the way, and
--      the caller turns until the way is clear. Without this, part one alone would walk it
--      straight through the trunk instead of over it, which is not better.
--
-- Excluded from the check: our own quest props and scenery, the boundary volume, and players --
-- a monster that refuses to walk toward the person it is chasing is not chasing anybody.
local function blockedAhead(from, stepv)
	if stepv.Magnitude < 0.05 then return false end
	local ex = { questFolder, sceneryFolder }
	if boundPart then ex[#ex + 1] = boundPart end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then ex[#ex + 1] = pl.Character end
	end
	overlapParams.FilterDescendantsInstances = ex
	overlapParams.MaxParts = 1
	-- a body-sized box one step ahead, lifted clear of the deck so the ground it walks on is
	-- never itself the obstacle
	local ahead = from + stepv.Unit * 9
	local box = CFrame.new(ahead + Vector3.new(0, 7, 0))
	return #Workspace:GetPartBoundsInBox(box, Vector3.new(11, 12, 11), overlapParams) > 0
end

-- the ground under a moving thing (the monster's feet, a smash ring)
--
-- ⚠ THE FALL WAS SELF-FEEDING, AND THIS IS THE FIX. The ray used to start 60 studs above the
-- CALLER'S OWN Y. The moment the monster was below the deck for any reason -- the floor streamed
-- out under it, it stepped off a ledge, a smash put it a foot low -- the next ray started below
-- the floor too, hit nothing, and the fallback handed back the sunken Y it was given. Every frame
-- it started lower and every frame it found nothing: once it dipped, it never came back.
--
-- So: cast from above the FLOOR OF RECORD (the island's own deck, measured once at boot) as well
-- as from the caller, and never return a Y below that deck. A thing walking on this island cannot
-- end up under it.
local function groundY(pos)
	local from = math.max(pos.Y, floorTopY or pos.Y) + 8
	local g = groundAt(pos.X, pos.Z, from)
	local y = g and g.Y or floorTopY or pos.Y
	if floorTopY then
		-- never below the deck (the self-feeding fall, above)...
		if y < floorTopY - 2 then y = floorTopY end
		-- ...and never far ABOVE it either. A ray that comes back 12 studs high has hit a tree, a
		-- rock or a machine -- something the monster is standing ON, not ground it can walk on.
		-- Ignoring it is what stops the thing climbing the scenery; blockedAhead is what stops it
		-- walking into the scenery in the first place.
		if y > floorTopY + 4 then y = floorTopY end
	end
	return y
end

-- ============================================================================
-- PICKING A SPOT INSIDE THE BOUNDARY, WITH NOTHING ALREADY THERE
-- ============================================================================
-- pull a position inside the boundary box (object space, so rotation is handled)
local function clampToBounds(pos, inset)
	if not boundCF then return clampToIsland(pos, inset) end
	local o = boundCF:PointToObjectSpace(pos)
	local m = inset or 8
	local hx, hz = math.max(1, boundHalf.X - m), math.max(1, boundHalf.Z - m)
	return (boundCF * CFrame.new(math.clamp(o.X, -hx, hx), o.Y, math.clamp(o.Z, -hz, hz))).Position
end

-- CANDIDATE n INSIDE THE BOUNDARY, as a world XZ. This is the R2 low-discrepancy sequence
-- (the 2D cousin of the golden angle): successive points spread themselves evenly over a
-- RECTANGLE without ever repeating or lining up, which a golden-angle spiral does not do --
-- a spiral is a circle, and forcing one into a long thin boundary either overflows the short
-- axis or wastes the long one. Deterministic, no math.random: the same layout every respawn,
-- so a kid who remembers where a bottle was is right.
local R2_A1, R2_A2 = 0.7548776662466927, 0.5698402909980532   -- 1/g, 1/g^2 for the plastic number
local function boundCandidate(n, inset)
	local m = inset or 8
	local u = (0.5 + R2_A1 * n) % 1
	local v = (0.5 + R2_A2 * n) % 1
	if boundCF then
		local hx, hz = math.max(1, boundHalf.X - m), math.max(1, boundHalf.Z - m)
		return (boundCF * CFrame.new((u * 2 - 1) * hx, 0, (v * 2 - 1) * hz)).Position
	end
	-- no boundary drawn: fall back to the old spiral around the arena
	local ang = n * 2.39996
	local rad = 90 + ((n * 37) % 110)
	return arenaCF.Position + Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)
end

-- IS THIS SPOT EMPTY? A box query the size of the prop, lifted clear of the ground so the
-- floor it is standing on is not itself counted as an obstruction. Excludes what this quest
-- built, the players, and the boundary marker; everything else on the island -- rocks, fences,
-- trees, your own props -- blocks the spot.
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
local function spotClear(groundPos, size, taken, minGap)
	-- first: not on top of another bottle. Quest props are excluded from the box query (they
	-- have to be -- otherwise the first bottle placed would block every spot near it), so
	-- spacing between our OWN props is enforced here instead.
	for _, p in ipairs(taken or {}) do
		if (Vector3.new(p.X, 0, p.Z) - Vector3.new(groundPos.X, 0, groundPos.Z)).Magnitude < (minGap or 14) then
			return false
		end
	end
	local ex = { questFolder }
	if boundPart then ex[#ex + 1] = boundPart end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then ex[#ex + 1] = pl.Character end
	end
	overlapParams.FilterDescendantsInstances = ex
	overlapParams.MaxParts = 1
	-- lifted by 0.6 so a flush-seated prop does not report the ground under it as a collision
	local box = CFrame.new(groundPos + Vector3.new(0, 0.6 + size.Y * 0.5, 0))
	return #Workspace:GetPartBoundsInBox(box, size, overlapParams) == 0
end

-- KEEP OUT OF THE ARENA. The giant pancake is 46 studs across and the monster stands up on
-- the same spot -- but both live in questFolder, which the box query has to exclude (the first
-- prop placed would otherwise block every spot near it). So the arena is fenced off by
-- distance instead: nothing scatters inside this radius of its centre.
local ARENA_KEEPOUT = 42

-- the whole placement rule in one call: walk candidates until one is inside the boundary, out
-- of the arena, on the ground, and clear of everything already there.
local function placeInBounds(startIndex, clearance, taken, minGap, tries)
	local last
	for k = 0, (tries or 60) do
		local c = boundCandidate(startIndex + k * 3, 8)
		local g = seatOn(c.X, c.Z, arenaCF and arenaCF.Position.Y or c.Y, 8)
		if g then
			g = clampToBounds(g, 8)
			g = Vector3.new(g.X, (groundAt(g.X, g.Z, g.Y) or Vector3.new(0, g.Y, 0)).Y, g.Z)
			local flat = arenaCF and ((Vector3.new(g.X, 0, g.Z)
				- Vector3.new(arenaCF.Position.X, 0, arenaCF.Position.Z)).Magnitude) or math.huge
			if flat >= ARENA_KEEPOUT then
				last = g
				if spotClear(g, clearance, taken, minGap) then return g, true end
			end
		end
	end
	return last, false   -- nowhere clear: still inside the boundary, just crowded
end

-- ============================================================================
-- SPEECH BUBBLE + OBJECTIVE BANNER  (the house style, shared with the other quests)
-- ============================================================================
local function hideBubble(a) local p = a and a:FindFirstChild("SpeechBubble"); if p then p:Destroy() end end

local function showBubble(a, text, persist, footer)
	if not a then return end
	hideBubble(a)
	local bb = Instance.new("BillboardGui"); bb.Name = "SpeechBubble"; bb.Adornee = a
	bb.Size = UDim2.new(0,320,0,150); bb.StudsOffset = Vector3.new(0,5.5,0); bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1,1); f.BackgroundColor3 = FILL
	f.BackgroundTransparency = 0.05; f.BorderSizePixel = 0; f.Parent = bb
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,18)
	local st = Instance.new("UIStroke"); st.Color = STROKE; st.Thickness = 2; st.Transparency = 0.3; st.Parent = f
	local pd = Instance.new("UIPadding")
	pd.PaddingTop=UDim.new(0,12); pd.PaddingBottom=UDim.new(0,12)
	pd.PaddingLeft=UDim.new(0,14); pd.PaddingRight=UDim.new(0,14); pd.Parent = f
	local l = Instance.new("TextLabel")
	l.Size = footer and UDim2.fromScale(1,0.78) or UDim2.fromScale(1,1); l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne; l.Text = text; l.TextColor3 = TEXTC; l.TextScaled = true; l.TextWrapped = true; l.Parent = f
	Instance.new("UITextSizeConstraint", l).MaxTextSize = 22
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1,0.2); h.Position = UDim2.fromScale(0,0.8)
		h.BackgroundTransparency = 1
		h.Font = Enum.Font.FredokaOne; h.Text = footer; h.TextColor3 = HINTC; h.TextScaled = true; h.Parent = f
		Instance.new("UITextSizeConstraint", h).MaxTextSize = 14
	end
	bb.Parent = a
	if not persist then
		task.delay(9, function()
			if bb and bb.Parent == a and bb.Name == "SpeechBubble" then bb:Destroy() end
		end)
	end
end

-- "...Objective" suffix: ObjectiveBannerBridge disables this ScreenGui and mirrors the frame's
-- text onto the realm banner. The frame's Visible is still ours to drive; the bridge only reads it.
local objGui = Instance.new("ScreenGui")
objGui.Name = "PancakeMonsterObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7; objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5,0); objFrame.Position = UDim2.new(0.5,0,0,12)
objFrame.Size = UDim2.new(0,560,0,52); objFrame.BackgroundColor3 = FILL; objFrame.Visible = false; objFrame.Parent = objGui
Instance.new("UICorner", objFrame).CornerRadius = UDim.new(0,16)
do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 3; s.Parent = objFrame end
local objLabel = Instance.new("TextLabel")
objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1,1); objLabel.Font = Enum.Font.FredokaOne
objLabel.TextColor3 = TEXTC; objLabel.TextScaled = true; objLabel.Parent = objFrame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = objLabel
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,14); pad.PaddingRight = UDim.new(0,14); pad.Parent = objLabel
end

-- ONE TABLE, NOT FIVE LOCALS. See the register note further down: every name declared at
-- the top level of a file this size is a register held for the whole chunk, and the chunk
-- has 200 of them. Five emoji as five locals is five registers; as one table it is one.
local E = {
	CAKE   = "\xF0\x9F\xA5\x9E",
	DROP   = "\xF0\x9F\x8D\xAF",
	BUTTER = "\xF0\x9F\xA7\x88",
	RUN    = "\xF0\x9F\x8F\x83",
	SPARK  = "\xE2\x9C\xA8",
}

-- PROGRESS IS IN THE TEXT AT EVERY STAGE. The banner should always answer "what now, and how
-- far in am I" -- a counter with no instruction, or an instruction with no counter, is half a
-- banner. The Quest Journal's grey detail line is set from the same place, so the two agree.
local function baseText()
	if step >= 6 then _G.pancakeQuestStep = nil; return E.CAKE .. " The Pancake Monster is a pile of pancakes!" end
	if step == 0 then _G.pancakeQuestStep = nil; return E.CAKE .. " Go talk to the Candy NPC!" end
	if step == 5 then
		_G.pancakeQuestStep = "Throw the butter"
		return ("%s All 8 butter! Get close and THROW them at the monster!"):format(E.BUTTER)
	end
	if step == 4 then
		_G.pancakeQuestStep = ("Butter %d/%d"):format(butterHeld, BUTTER_COUNT)
		return ("%s Grab the butter while it chases you:  %d/%d"):format(E.BUTTER, butterHeld, BUTTER_COUNT)
	end
	if step == 3 then _G.pancakeQuestStep = "Something is waking up"; return E.RUN .. " RUN! Something is waking up!" end
	if carrying then
		_G.pancakeQuestStep = ("Syrup %d/%d"):format(poured, SYRUP_COUNT)
		-- names the PAD, not "the middle": the banner should always point at a thing you can
		-- see and walk to, which is the entire reason the pads exist.
		return ("%s Take it to a glowing pad by the giant pancake!  %d/%d")
			:format(E.DROP, poured, SYRUP_COUNT)
	end
	_G.pancakeQuestStep = ("Syrup %d/%d"):format(poured, SYRUP_COUNT)
	return ("%s Find the giant syrup bottles around the island:  %d/%d"):format(E.DROP, poured, SYRUP_COUNT)
end

refreshBanner = function() objLabel.Text = baseText() end

-- Only near island18, so it never talks over another island's objective.
task.spawn(function()
	while true do
		local vis = false
		if step > 0 and step < 6 and island then
			local hrp = hrpOf()
			local ref = pancake and pancake.Position or (arenaCF and arenaCF.Position)
			if hrp and ref then vis = (hrp.Position - ref).Magnitude <= BANNER_RANGE end
		end
		objFrame.Visible = vis
		task.wait(0.4)
	end
end)

local function flashBanner(text, seconds)
	objLabel.Text = text
	task.delay(seconds or 3, refreshBanner)
end

-- ============================================================================
-- SMALL EFFECTS
-- ============================================================================
local function poofAt(pos, colour, n)
	for i = 1, (n or 10) do
		local a = (i / (n or 10)) * math.pi * 2
		local bit = mk({ Size = Vector3.new(0.6, 0.6, 0.6), Color = colour, Shape = Enum.PartType.Ball,
			Transparency = 0.1, Parent = questFolder })
		bit.CFrame = CFrame.new(pos)
		tween(bit, 0.5, { CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 5, 3.5, math.sin(a) * 5)),
			Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 })
		Debris:AddItem(bit, 0.6)
	end
end

local function shakeCamera(amount, seconds)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < seconds do
			local k = 1 - (os.clock() - t0) / seconds
			cam.CFrame = cam.CFrame * CFrame.new(
				(math.random() - 0.5) * amount * k,
				(math.random() - 0.5) * amount * k, 0)
			RunService.RenderStepped:Wait()
		end
	end)
end

-- a flat shockwave ring bursting out of a heavy footfall or a smash
local function shockRing(pos, colour, size, seconds)
	local gy = groundY(pos)
	local ring = mk({ Name = "SmashRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 3, 3),
		Color = colour or CAKE_LO, Transparency = 0.3, Parent = questFolder })
	ring.CFrame = CFrame.new(pos.X, gy + 0.2, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	tween(ring, seconds or 0.55, { Size = Vector3.new(0.4, size or 24, size or 24), Transparency = 1 })
	Debris:AddItem(ring, (seconds or 0.55) + 0.1)
end

-- ============================================================================
-- CARRIED ITEMS -- anchored, and re-placed on your back every frame
-- ============================================================================
-- The usual way to put something in a player's hands is a weld into the character, and a
-- welded part CANNOT be anchored. Since everything here is anchored, carried props are
-- driven instead: one RenderStepped pass CFrames them onto your back. Costs a few lines,
-- and there is not one unanchored part in the whole quest as a result.
local carriedProps = {}   -- { model=, off=CFrame }

local function carryProp(model, off)
	carriedProps[#carriedProps + 1] = { model = model, off = off }
end
local function dropCarried(model)
	for i = #carriedProps, 1, -1 do
		if carriedProps[i].model == model then table.remove(carriedProps, i) end
	end
end
local function clearCarried()
	for _, c in ipairs(carriedProps) do if c.model.Parent then c.model:Destroy() end end
	carriedProps = {}
end

RunService.RenderStepped:Connect(function()
	local hrp = hrpOf()
	if not hrp then return end
	for _, c in ipairs(carriedProps) do
		if c.model.Parent then c.model:PivotTo(hrp.CFrame * c.off) end
	end
end)

-- ============================================================================
-- THE GIANT PANCAKE  (the arena centrepiece: the monster is under it)
-- ============================================================================
local pancakeModel, syrupPools = nil, {}
local wakeTheMonster   -- forward: the wake-up cinematic, defined once the monster rig exists

-- ⚠ THE STACK'S PIVOT IS ROLLED. Its PrimaryPart is a cylinder laid flat, so its CFrame carries
-- a 90-degree roll -- and PivotTo(CFrame.new(somewhere)) would stand the whole stack on its edge
-- like a wheel. Every move of the pancake below is therefore expressed as a world TRANSLATION
-- applied to this remembered frame, never as a fresh CFrame built from a position alone.
local pancakeHomeCF
local function movePancake(offset, extraRot)
	if not (pancakeModel and pancakeModel.PrimaryPart and pancakeHomeCF) then return end
	local cf = CFrame.new(offset) * pancakeHomeCF
	if extraRot then cf = cf * extraRot end
	pancakeModel:PivotTo(cf)
end

local function buildPancake(at)
	local m = Instance.new("Model"); m.Name = "GiantPancake"
	m:SetAttribute("QuestProp", true)

	-- a stack of three, biggest at the bottom, browned undersides showing
	local base = mk({ Name = "Cake1", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.2, 46, 46),
		Color = CAKE, Parent = m })
	base.CFrame = CFrame.new(at + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	m.PrimaryPart = base
	pancake = base

	local c2 = mk({ Name = "Cake2", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.8, 40, 40),
		Color = CAKE_HI, Parent = m })
	c2.CFrame = CFrame.new(at + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local c3 = mk({ Name = "Cake3", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 33, 33),
		Color = CAKE, Parent = m })
	c3.CFrame = CFrame.new(at + Vector3.new(0, 7.2, 0)) * CFrame.Angles(0, 0, math.rad(90))

	-- the browned rim of each one, a shade darker and a hair wider
	for i, src in ipairs({ base, c2, c3 }) do
		local rim = mk({ Name = "Rim" .. i, Shape = Enum.PartType.Cylinder,
			Size = src.Size - Vector3.new(0.4, 0, 0), Color = CAKE_LO, Transparency = 0.15, Parent = m })
		rim.Size = Vector3.new(src.Size.X - 0.5, src.Size.Y + 1.2, src.Size.Z + 1.2)
		rim.CFrame = src.CFrame
	end

	-- a pat of butter melting on top, because a stack without one is not a stack
	local pat = mk({ Name = "ButterPat", Size = Vector3.new(6, 2.4, 6), Color = BUTTER, Parent = m })
	pat.CFrame = CFrame.new(at + Vector3.new(0, 9.6, 0))

	m.Parent = questFolder
	pancakeModel = m
	pancakeHomeCF = m:GetPivot()   -- rolled: see movePancake

	-- the pancake carries the POUR prompt, and the quest's fallback TALK prompt
	base.CanQuery = true
	return m
end

-- a spreading pool of syrup, one per bottle poured
local function addSyrupPool(idx)
	if not pancake then return end
	local a = idx * 2.39996
	local r = 6 + (idx % 3) * 5
	local pool = mk({ Name = "SyrupPool" .. idx, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 2, 2), Color = SYRUP, Transparency = 0.05, Reflectance = 0.2,
		Parent = questFolder })
	local top = pancake.Position + Vector3.new(math.cos(a) * r, 9.4, math.sin(a) * r)
	pool.CFrame = CFrame.new(top) * CFrame.Angles(0, 0, math.rad(90))
	tween(pool, 0.9, { Size = Vector3.new(0.6, 15 + idx * 2, 15 + idx * 2) }, Enum.EasingStyle.Back)
	syrupPools[#syrupPools + 1] = pool
end

-- ============================================================================
-- THE SYRUP BOTTLES
-- ============================================================================
local function buildSyrupBottle(at)
	local m = Instance.new("Model"); m.Name = "SyrupBottle"
	m:SetAttribute("QuestProp", true)

	local body = mk({ Name = "Body", Size = Vector3.new(3.4, 6.4, 3.4), Color = SYRUP,
		Transparency = 0.08, Reflectance = 0.25, Parent = m })
	body.CFrame = CFrame.new(at + Vector3.new(0, 3.2, 0))
	m.PrimaryPart = body

	local neck = mk({ Name = "Neck", Size = Vector3.new(1.5, 2.0, 1.5), Color = SYRUP,
		Transparency = 0.08, Parent = m })
	neck.CFrame = body.CFrame * CFrame.new(0, 4.0, 0)
	local cap = mk({ Name = "Cap", Size = Vector3.new(2.1, 1.1, 2.1), Color = Color3.fromRGB(240, 90, 70), Parent = m })
	cap.CFrame = body.CFrame * CFrame.new(0, 5.4, 0)
	local label = mk({ Name = "Label", Size = Vector3.new(3.5, 2.4, 0.2), Color = CAKE_HI, Parent = m })
	label.CFrame = body.CFrame * CFrame.new(0, 0.2, -1.75)

	-- a glow so a bottle tucked behind a rock still reads from across the island
	local hl = Instance.new("Highlight")
	hl.FillColor = GOLD; hl.FillTransparency = 0.6
	hl.OutlineColor = Color3.fromRGB(255, 240, 200); hl.OutlineTransparency = 0.1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = m; hl.Parent = m

	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(160, 40); tag.StudsOffset = Vector3.new(0, 6.5, 0)
	tag.AlwaysOnTop = true; tag.MaxDistance = 260; tag.Adornee = body; tag.Parent = body
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1,1); tl.BackgroundTransparency = 1; tl.Font = Enum.Font.FredokaOne
	tl.TextColor3 = Color3.fromRGB(255,255,255); tl.TextStrokeColor3 = TEXTC; tl.TextStrokeTransparency = 0
	tl.TextScaled = true; tl.Text = E.DROP .. " SYRUP"; tl.Parent = tag

	m.Parent = questFolder
	body.CanQuery = true
	return m, body
end

-- WHERE THE BOTTLES HIDE. Your "syrup" markers win outright -- a spot you chose is never
-- second-guessed. The rest are sampled INSIDE the "placement boundaires" part and rejected
-- until they are clear of everything else on the island, so no bottle spawns half-inside a
-- rock, a fence or another bottle. The bottle is ~3.4 wide and ~6.5 tall; the clearance box
-- is deliberately bigger than that so they do not merely miss things, they stand clear of them.
local SYRUP_CLEARANCE = Vector3.new(7, 8, 7)
local SYRUP_MIN_GAP   = 26     -- studs between two bottles: they are meant to be a search

-- markers come in as records, auto-placed spots as bare positions; both end up as
-- { pos = , scale = } so scatterSyrup does not care which is which.
local function syrupSpots(markers)
	local spots, crowded = {}, 0
	for _, rec in ipairs(markers) do spots[#spots + 1] = rec end
	local n = 0
	while #spots < SYRUP_COUNT do
		n += 1
		local taken = {}
		for _, s in ipairs(spots) do taken[#taken + 1] = s.pos end
		local g, ok = placeInBounds(n * 11, SYRUP_CLEARANCE, taken, SYRUP_MIN_GAP)
		if not ok then crowded += 1 end
		spots[#spots + 1] = { pos = g or clampToBounds(arenaCF.Position + Vector3.new(40, 0, 40), 8), scale = 1 }
	end
	if crowded > 0 then
		warn(("[Pancake] %d syrup bottle(s) could not find a clear patch inside the boundary -- "
			.. "placed anyway. Widen 'placement boundaires' or clear some props."):format(crowded))
	end
	return spots
end

-- ============================================================================
-- THE POURING PADS -- where you bring each bottle
-- ============================================================================
-- Island16's charge sockets, in syrup. That quest rings its giant candy with five glowing
-- pads and makes you walk a crystal to each one, and it works for a reason worth copying:
-- "bring it to the middle" is a blurry target you can satisfy by wandering vaguely inward,
-- while five lit pads are five obvious places that visibly fill up. The banner can then
-- always name a THING to walk to instead of a direction.
--
-- COMPUTED, NOT MARKED. The ring is derived from the pancake's own footprint, so it fits
-- whatever size the stack ends up and there are no extra blocks to place in Studio. They sit
-- inside ARENA_KEEPOUT, so no bottle or butter is ever scattered on top of one.
local pads = {}          -- { part=, holder=, prompt=, glow=, filled=bool, angle= }
local pourAtPad          -- forward: buildPads wires it into every pad prompt, and it is
                         -- defined below because it needs the pad record buildPads makes
local PAD_GAP = 11       -- studs out from the stack's edge

local function padsFilled()
	local n = 0
	for _, p in ipairs(pads) do if p.filled then n += 1 end end
	return n
end

local function nearestFreePad(from)
	local best, bestD
	for _, p in ipairs(pads) do
		if not p.filled then
			local d = (p.part.Position - from).Magnitude
			if not bestD or d < bestD then best, bestD = p, d end
		end
	end
	return best, bestD
end

local function buildPads()
	if not pancake then return end
	local centre = pancake.Position
	local radius = pancake.Size.Y * 0.5 + PAD_GAP     -- the base cake is a laid-down cylinder:
	                                                  -- its DIAMETER is Size.Y, not Size.X
	for i = 1, SYRUP_COUNT do
		local a = (i - 1) * (math.pi * 2 / SYRUP_COUNT) + 0.35
		local x, z = centre.X + math.cos(a) * radius, centre.Z + math.sin(a) * radius
		local gy = groundY(Vector3.new(x, centre.Y, z))

		local pad = mk({ Name = "SyrupPad" .. i, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.45, 9, 9), Color = CAKE_LO, Material = Enum.Material.SmoothPlastic,
			Transparency = 0.15, CanQuery = true, Parent = questFolder })
		pad.CFrame = CFrame.new(x, gy + 0.22, z) * CFrame.Angles(0, 0, math.rad(90))

		local glow = mk({ Name = "PadGlow" .. i, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 7.4, 7.4), Color = GOLD, Material = Enum.Material.Neon,
			Transparency = 0.35, Parent = questFolder })
		glow.CFrame = pad.CFrame * CFrame.new(0.06, 0, 0)

		-- a little iron cradle, so an empty pad reads as "something goes here"
		local holder = Instance.new("Model"); holder.Name = "PadCradle" .. i
		for k = 0, 3 do
			local ang = k * (math.pi / 2)
			local prong = mk({ Size = Vector3.new(0.4, 2.2, 0.4), Color = Color3.fromRGB(84, 80, 84),
				Material = Enum.Material.Metal, Parent = holder })
			prong.CFrame = CFrame.new(x + math.cos(ang) * 2.1, gy + 1.1, z + math.sin(ang) * 2.1)
		end
		holder.Parent = questFolder

		local tag = Instance.new("BillboardGui")
		tag.Name = "PadTag"; tag.Size = UDim2.fromOffset(150, 40)
		tag.StudsOffset = Vector3.new(0, 4.5, 0); tag.AlwaysOnTop = true
		tag.MaxDistance = 260; tag.Adornee = pad; tag.Parent = pad
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1; tl.Font = Enum.Font.FredokaOne
		tl.TextColor3 = Color3.new(1, 1, 1); tl.TextStrokeColor3 = TEXTC; tl.TextStrokeTransparency = 0
		tl.TextScaled = true; tl.Text = E.DROP .. " POUR HERE"; tl.Parent = tag

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pour Syrup"; prompt.ObjectText = "Pouring Pad"
		prompt.HoldDuration = 0.3; prompt.MaxActivationDistance = POUR_RANGE
		prompt.RequiresLineOfSight = false; prompt.Enabled = false; prompt.Parent = pad

		local rec = { part = pad, glow = glow, holder = holder, prompt = prompt,
			tag = tag, label = tl, filled = false, angle = a, groundY = gy }
		pads[#pads + 1] = rec
		prompt.Triggered:Connect(function() pourAtPad(rec) end)
	end
	print(("[Pancake] %d pouring pad(s) ringed around the stack at %.0f studs"):format(#pads, radius))
end

-- pulse the free pads so the next place to go is never ambiguous
task.spawn(function()
	while true do
		task.wait(0.1)
		local k = 0.2 + math.abs(math.sin(os.clock() * 2)) * 0.35
		for _, p in ipairs(pads) do
			if p.glow.Parent then
				p.glow.Transparency = p.filled and 0.75 or k
			end
		end
	end
end)

pourAtPad = function(pad)
	if step ~= 1 or not carrying or pad.filled then return end
	local rec = carrying
	carrying = nil
	dropCarried(rec.model)

	-- THE BOTTLE STAYS. It is stood up in the pad's cradle, upended, still glugging -- the
	-- five filled pads ARE the progress bar, which is the whole point of having pads at all.
	pad.filled = true
	local m = rec.model
	if m.Parent then
		m:PivotTo(CFrame.new(pad.part.Position + Vector3.new(0, 3.4, 0))
			* CFrame.Angles(math.rad(155), pad.angle, 0))
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("Highlight") then d.Enabled = false end
			if d:IsA("BillboardGui") then d.Enabled = false end
		end
	end
	pad.label.Text = E.DROP .. " FILLED"
	pad.glow.Color = GREEN

	poured += 1
	addSyrupPool(poured)
	playSound(SOUND_POUR, 0.6)
	poofAt(pad.part.Position + Vector3.new(0, 3, 0), SYRUP, 14)
	-- a runnel of syrup from the pad in toward the stack, so the pads read as feeding it
	local runnel = mk({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2, 2),
		Color = SYRUP, Transparency = 0.1, Reflectance = 0.25, Parent = questFolder })
	local toward = (pancake.Position - pad.part.Position) * Vector3.new(1, 0, 1)
	runnel.CFrame = CFrame.new(pad.part.Position + toward * 0.5 + Vector3.new(0, -0.05, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	tween(runnel, 0.8, { Size = Vector3.new(0.3, 3.4, math.max(4, toward.Magnitude)) }, Enum.EasingStyle.Quad)

	refreshBanner(); refreshPrompts()

	if poured >= SYRUP_COUNT then
		step = 3
		refreshBanner()
		task.spawn(wakeTheMonster)
	else
		flashBanner(("%s %d/%d poured -- find the rest!"):format(E.DROP, poured, SYRUP_COUNT), 2.5)
	end
end

local function pickUpSyrup(rec)
	if step ~= 1 or carrying or rec.taken then return end
	rec.taken = true
	carrying = rec
	if rec.prompt then rec.prompt.Enabled = false end
	playSound(SOUND_PICKUP, 0.5)
	-- onto your back, tipped over like something too big to hold properly
	carryProp(rec.model, CFrame.new(0, 1.2, 1.9) * CFrame.Angles(math.rad(-25), 0, math.rad(14)))
	flashBanner(E.DROP .. " Got one! Take it to the giant pancake!", 2.5)
	refreshBanner(); refreshPrompts()
end

local function scatterSyrup(markers)
	local spots = syrupSpots(markers)
	for i = 1, SYRUP_COUNT do
		local at = spots[i]
		local m, main = buildSyrupBottle(at.pos)
		-- THE BLOCK'S FOOTPRINT SETS THE BOTTLE'S SIZE. Drawn a big "syrup" block? You get a
		-- big bottle. Grown about the ground line so it stays standing on the floor rather
		-- than sinking into it or hovering.
		if at.scale and math.abs(at.scale - 1) > 0.01 then
			m.WorldPivot = CFrame.new(at.pos)
			m:ScaleTo(at.scale)
		end
		local rec = { model = m, main = main, home = m:GetPivot(), taken = false }
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Take"; prompt.ObjectText = "Giant Syrup Bottle"
		prompt.HoldDuration = 0; prompt.MaxActivationDistance = PICKUP_RANGE
		prompt.RequiresLineOfSight = false; prompt.Parent = main
		prompt.Triggered:Connect(function() pickUpSyrup(rec) end)
		rec.prompt = prompt
		syrups[#syrups + 1] = rec
	end
	print(("[Pancake] %d syrup bottle(s) hidden around island18"):format(#syrups))
end

-- ============================================================================
-- THE PANCAKE MONSTER
-- ============================================================================
-- ChocolateMonster's rig, rebuilt in batter. Same contract: monParts holds every attached
-- part with its offset from the body and an optional per-frame animator, and poseMonster()
-- re-glues the lot each frame. Limbs that must move as ONE piece (arm+fist, leg+foot) share
-- a ph0 and an angle so they rotate about the identical world point.
local BODY_BASE = Vector3.new(11, 9, 11)
local monParts  = {}
local monster, monBody, monTag
local eyeL, eyeR, jaw
local steamMon
local monState  = "buried"     -- buried | rising | hunt | melting | melted | remote
local chaseT, poseSwing = 0, 0
-- ===== SHARING THE MONSTER (see MonsterSync.server.lua) =====
-- Every client already builds this monster asleep under the stack, so nothing has to be built
-- across the network -- only DRIVEN. Whoever pours the fifth syrup owns the chase and streams
-- the body's CFrame; everyone else drops into monState "remote" and puts their own sleeping
-- monster wherever the stream says. One table, because this file is five registers from Luau's
-- 200-local ceiling and a handful of separate locals is a compile failure waiting to happen.
--   on   -- true if OUR monster is being driven by somebody else's client
--   cf   -- the last body CFrame received; the render loop eases toward it
--   ev   -- the RemoteEvent, nil until it turns up
--   last -- clock of the last message, so a host that vanishes does not freeze a monster forever
local REM = { on = false, cf = nil, ev = nil, last = 0 }
local targetPlayer, retargetAt = nil, 0
local lastFootPos, lastSmash = nil, 0
local butterStuck = 0

local function pivotSwing(ph0, pivotY, maxAng)
	return function(phase, swing)
		local ang = math.sin(phase + ph0) * maxAng * swing
		return CFrame.new(0, pivotY, 0) * CFrame.Angles(ang, 0, 0) * CFrame.new(0, -pivotY, 0)
	end
end
local function bellyJiggle()
	return function(phase, swing)
		local amp = 0.3 + swing * 0.9
		return CFrame.new(0, math.sin(phase * 2) * 0.3 * amp, math.sin(phase * 2 + 1) * 0.24 * amp)
	end
end
local function jawChomp()
	return function(phase, swing)
		local open = (math.sin(phase * 2.2) * 0.5 + 0.5) * (0.3 + swing * 0.4)
		return CFrame.Angles(open, 0, 0) * CFrame.new(0, -open * 0.5, 0)
	end
end
-- the stack-of-pancakes torso wobbles like a stack of pancakes: each disc lags the one below
local function stackWobble(layer)
	return function(phase, swing)
		local amp = (0.10 + swing * 0.22) * layer
		return CFrame.Angles(math.sin(phase * 1.6 + layer) * amp * 0.12, 0,
			math.cos(phase * 1.4 + layer) * amp * 0.12)
	end
end

local function buildMonster(at)
	local m = Instance.new("Model"); m.Name = "PancakeMonster"
	m:SetAttribute("QuestProp", true)

	-- THE BODY IS A STACK. Where the chocolate one is a lumpy ball, this is what a pile of
	-- pancakes would look like if it stood up: wide flat discs, browned rims, syrup running
	-- down the sides. The body part itself is the middle disc, so the offsets read symmetric.
	local body = mk({ Name = "Body", Shape = Enum.PartType.Cylinder, Size = BODY_BASE,
		Color = CAKE, Reflectance = 0.05, Parent = m })
	body.CFrame = CFrame.new(at + Vector3.new(0, 9, 0)) * CFrame.Angles(0, 0, math.rad(90))
	m.PrimaryPart = body
	monBody = body

	-- ⚠ the body is a CYLINDER laid on its side, so its own frame is rolled 90 degrees. Every
	-- offset below is expressed in UPRIGHT space and converted here, once -- otherwise every
	-- limb would need the roll baked into it and the first person to add a horn gets it wrong.
	local ROLL = CFrame.Angles(0, 0, math.rad(-90))

	local function attach(name, size, off, colour, shape, anim)
		local p = mk({ Name = name, Size = size, Color = colour or CAKE, Parent = m })
		if shape then p.Shape = shape end
		monParts[#monParts + 1] = { part = p, off = ROLL * off, anim = anim }
		return p
	end

	-- the stack: discs above and below the body disc, each wobbling a little more than the last
	attach("Stack1", Vector3.new(2.6, 12.5, 12.5), CFrame.new(0, -4.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		CAKE_LO, Enum.PartType.Cylinder, stackWobble(1))
	attach("Stack2", Vector3.new(2.4, 11.5, 11.5), CFrame.new(0, -1.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		CAKE_HI, Enum.PartType.Cylinder, stackWobble(2))
	attach("Stack3", Vector3.new(2.4, 10.2, 10.2), CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		CAKE_HI, Enum.PartType.Cylinder, stackWobble(3))
	attach("Belly",  Vector3.new(9.5, 5.2, 8.5), CFrame.new(0, -2.6, -1.2), CAKE_HI, Enum.PartType.Ball, bellyJiggle())

	-- head: the top pancake of the stack, with a browned crown
	attach("Neck", Vector3.new(4.2, 2.2, 4.2), CFrame.new(0, 5.4, -0.2), CAKE_LO, Enum.PartType.Ball)
	attach("Head", Vector3.new(3.0, 11.0, 11.0), CFrame.new(0, 7.6, -0.4) * CFrame.Angles(0, 0, math.rad(90)),
		CAKE, Enum.PartType.Cylinder)
	attach("Crown", Vector3.new(2.4, 9.0, 9.0), CFrame.new(0, 9.0, -0.4) * CFrame.Angles(0, 0, math.rad(90)),
		CAKE_LO, Enum.PartType.Cylinder)

	-- hips bridging into the legs, so there is no gap when it walks
	attach("HipL", Vector3.new(3.4, 3.4, 3.4), CFrame.new(-2.6, -5.6, 0), CAKE_LO, Enum.PartType.Ball)
	attach("HipR", Vector3.new(3.4, 3.4, 3.4), CFrame.new( 2.6, -5.6, 0), CAKE_LO, Enum.PartType.Ball)

	-- arms + fists swing from the shoulder as one piece
	attach("ArmL",  Vector3.new(2.8, 6.0, 2.8), CFrame.new(-5.6, 0.4, 0), CAKE, nil, pivotSwing(math.pi, 3.0, 0.5))
	attach("ArmR",  Vector3.new(2.8, 6.0, 2.8), CFrame.new( 5.6, 0.4, 0), CAKE, nil, pivotSwing(0, 3.0, 0.5))
	attach("FistL", Vector3.new(4.0, 4.0, 4.0), CFrame.new(-5.6, -3.4, 0), CAKE_LO, Enum.PartType.Ball, pivotSwing(math.pi, 6.8, 0.5))
	attach("FistR", Vector3.new(4.0, 4.0, 4.0), CFrame.new( 5.6, -3.4, 0), CAKE_LO, Enum.PartType.Ball, pivotSwing(0, 6.8, 0.5))

	-- legs + feet swing from the hips as one piece
	attach("LegL",  Vector3.new(3.2, 5.0, 3.2), CFrame.new(-2.6, -7.4, 0), CAKE, nil, pivotSwing(0, 2.2, 0.45))
	attach("LegR",  Vector3.new(3.2, 5.0, 3.2), CFrame.new( 2.6, -7.4, 0), CAKE, nil, pivotSwing(math.pi, 2.2, 0.45))
	attach("FootL", Vector3.new(3.6, 2.2, 5.0), CFrame.new(-2.6, -9.8, -0.7), CAKE_LO, nil, pivotSwing(0, 4.6, 0.45))
	attach("FootR", Vector3.new(3.6, 2.2, 5.0), CFrame.new( 2.6, -9.8, -0.7), CAKE_LO, nil, pivotSwing(math.pi, 4.6, 0.45))

	-- face: hot syrup eyes, heavy brows, a gnashing browned jaw
	-- ⚠ THE HEAD IS A FLAT DISC, radius 5.5 about its own axis at local z = -0.4. Face parts
	-- therefore sit around z = -5.6, not the -2.5 the chocolate monster uses: its head is a
	-- BALL and anything a couple of studs forward pokes out of it. On a disc, the same offset
	-- is buried inside the pancake and the monster reads as faceless.
	eyeL = attach("EyeL", Vector3.new(1.6, 1.6, 0.8), CFrame.new(-1.7, 8.2, -5.6), Color3.fromRGB(255, 226, 130), Enum.PartType.Ball)
	eyeR = attach("EyeR", Vector3.new(1.6, 1.6, 0.8), CFrame.new( 1.7, 8.2, -5.6), Color3.fromRGB(255, 226, 130), Enum.PartType.Ball)
	eyeL.Material = Enum.Material.Neon; eyeR.Material = Enum.Material.Neon
	attach("PupL", Vector3.new(0.6, 0.65, 0.45), CFrame.new(-1.7, 8.1, -6.0), Color3.fromRGB(46, 22, 8), Enum.PartType.Ball)
	attach("PupR", Vector3.new(0.6, 0.65, 0.45), CFrame.new( 1.7, 8.1, -6.0), Color3.fromRGB(46, 22, 8), Enum.PartType.Ball)
	attach("BrowL", Vector3.new(2.2, 0.6, 0.6), CFrame.new(-1.7, 9.0, -5.7) * CFrame.Angles(0, 0, math.rad(-22)), CAKE_LO)
	attach("BrowR", Vector3.new(2.2, 0.6, 0.6), CFrame.new( 1.7, 9.0, -5.7) * CFrame.Angles(0, 0, math.rad(22)), CAKE_LO)
	attach("Maw", Vector3.new(3.4, 2.4, 1.8), CFrame.new(0, 6.4, -5.4), Color3.fromRGB(60, 28, 10), Enum.PartType.Ball)
	jaw = attach("Jaw", Vector3.new(4.4, 1.6, 2.2), CFrame.new(0, 5.6, -5.3), CAKE_LO, nil, jawChomp())
	for i = -2, 2 do
		attach("ToothU" .. i, Vector3.new(0.55, 1.1, 0.4), CFrame.new(i * 0.85, 6.9, -6.0), Color3.fromRGB(250, 246, 232))
	end

	-- the butter pat on its head, and syrup running down it
	attach("HeadPat", Vector3.new(5.0, 2.0, 5.0), CFrame.new(0, 10.4, -0.4), BUTTER)
	for i = 1, 7 do
		local a = i * (math.pi * 2 / 7)
		attach("Drip" .. i, Vector3.new(1.2, 3.4, 1.2), CFrame.new(math.cos(a) * 5.4, 1.2, math.sin(a) * 5.4),
			SYRUP, Enum.PartType.Ball)
	end

	-- glossy syrup sheen over the batter, but not over the eyes/teeth/brows
	for _, e in ipairs(monParts) do
		local nm = e.part.Name
		if not (nm:match("^Eye") or nm:match("^Pup") or nm:match("^Tooth") or nm:match("^Brow") or nm == "Maw") then
			e.part.Reflectance = 0.1
		end
	end

	-- syrup dripping off it as it moves
	local att = Instance.new("Attachment"); att.Position = Vector3.new(0, -4, 0); att.Parent = body
	local drip = Instance.new("ParticleEmitter")
	drip.Color = ColorSequence.new(SYRUP); drip.Size = NumberSequence.new(0.8)
	drip.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	drip.Lifetime = NumberRange.new(0.6, 1.1); drip.Rate = 9; drip.Speed = NumberRange.new(1, 3)
	drip.Acceleration = Vector3.new(0, -20, 0); drip.SpreadAngle = Vector2.new(20, 20); drip.Parent = att

	steamMon = Instance.new("Smoke")
	steamMon.Color = Color3.fromRGB(240, 226, 200); steamMon.Opacity = 0.25; steamMon.RiseVelocity = 7
	steamMon.Size = 7; steamMon.Enabled = false; steamMon.Parent = body

	local hl = Instance.new("Highlight")
	hl.FillColor = CAKE_HI; hl.FillTransparency = 0.75
	hl.OutlineColor = CAKE_LO; hl.OutlineTransparency = 0.25
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = body; hl.Parent = m

	local tag = Instance.new("BillboardGui")
	tag.Name = "MonTag"; tag.Size = UDim2.fromOffset(280, 56); tag.StudsOffset = Vector3.new(0, 13, 0)
	tag.AlwaysOnTop = true; tag.MaxDistance = 300; tag.Adornee = body; tag.Parent = body
	monTag = Instance.new("TextLabel")
	monTag.Size = UDim2.fromScale(1,1); monTag.BackgroundTransparency = 1
	monTag.Font = Enum.Font.GothamBlack; monTag.TextScaled = true
	monTag.TextColor3 = Color3.fromRGB(255,255,255)
	monTag.TextStrokeColor3 = TEXTC; monTag.TextStrokeTransparency = 0
	monTag.Text = E.CAKE .. " Pancake Monster"; monTag.Parent = tag

	m.Parent = questFolder
	monster = m
	return m
end

-- keep every attached part glued to the body at its offset, applying its walk-cycle delta so
-- limbs stomp and the jaw gnashes as the whole thing moves.
local function poseMonster()
	if not (monBody and monBody.Parent) then return end
	local phase = os.clock() * 9
	for _, e in ipairs(monParts) do
		if e.part.Parent then
			local base = monBody.CFrame * e.off
			e.part.CFrame = e.anim and (base * e.anim(phase, poseSwing)) or base
		end
	end
end

local function roar()
	playSound(SOUND_ROAR, 0.75)
	shakeCamera(1.6, 0.5)
end

-- who it chases: the nearest player with a character, on this island
-- ===== WHO IT IS ALLOWED TO CHASE =====
-- Only players who have woken it -- i.e. who are on the butter run. Someone still hunting
-- syrup bottles walks past it untouched, exactly the way island3's Chocolate Monster ignores
-- you until the Cookie quest is accepted.
--
-- ⚠ AND THAT CAN ONLY MEAN THE LOCAL PLAYER, which is a limit of the design rather than a
-- shortcut. Every quest in this realm is a per-player CLIENT script: this monster exists only
-- on your machine, and another player's quest step lives only on theirs -- a client cannot
-- read it and cannot be told without a remote this quest does not have. So each player is
-- chased by their OWN monster, on their own schedule, which produces exactly the behaviour
-- asked for from every player's point of view: it hunts you once you are on the next task and
-- leaves you alone before that. It just is not one shared monster picking between people.
local function huntAllowed()
	return step >= 4 and step < 6
end

local function pickTarget()
	if not huntAllowed() then return nil end
	local here = monBody and monBody.Position
	if not here then return nil end
	local hrp = hrpOf()
	if hrp and (hrp.Position - here).Magnitude <= LEASH_RANGE then return player end
	return nil
end
local function targetHRP() return targetPlayer and hrpFor(targetPlayer) or nil end

-- ============================================================================
-- THE SHOVE -- it never kills, it never damages. It knocks you back and shakes
-- the screen, and that is the whole of its threat.
-- ============================================================================
local shovedUntil = 0
local function shovePlayer(hrp)
	local now = os.clock()
	if now < shovedUntil then return end
	shovedUntil = now + 2.2
	local dir = (hrp.Position - monBody.Position) * Vector3.new(1, 0, 1)
	dir = (dir.Magnitude > 0.1) and dir.Unit or Vector3.new(0, 0, 1)
	local push = Instance.new("BodyVelocity")
	push.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	push.Velocity = dir * KNOCK_BACK + Vector3.new(0, KNOCK_UP, 0)
	push.Parent = hrp
	Debris:AddItem(push, 0.22)
	shakeCamera(2.4, 0.6)
	poofAt(hrp.Position, CAKE_HI, 12)
	-- DROPPED BUTTER IS THE PUNISHMENT, not damage: getting hit costs you one, so the chase
	-- has stakes without a single kid ever seeing a death screen.
	if step == 4 and butterHeld > 0 then
		butterHeld -= 1
		flashBanner(E.BUTTER .. " Ouch -- you dropped a butter!", 2)
		refreshBanner()
	end
end

-- the ground smash: a heavy two-fisted slam that rings out around it
local function groundSmash(at)
	playSound(SOUND_SMASH, 0.7)
	shockRing(at, CAKE_LO, 34, 0.6)
	shockRing(at, SYRUP, 22, 0.45)
	poofAt(Vector3.new(at.X, groundY(at) + 1, at.Z), CAKE_HI, 14)
	local hrp = hrpOf()
	if hrp and (hrp.Position - at).Magnitude <= 30 then
		shakeCamera(1.8 * (1 - (hrp.Position - at).Magnitude / 30), 0.45)
	end
end

-- melty batter footprints, fading over ~3s
local function dropFootprint(pos)
	if lastFootPos and (pos - lastFootPos).Magnitude < 7 then return end
	lastFootPos = pos
	local gy = groundY(pos)
	local pf = mk({ Name = "CakePrint", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 3.2, 3.2),
		Color = CAKE_LO, Transparency = 0.2, Parent = questFolder })
	pf.CFrame = CFrame.new(pos.X, gy + 0.12, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	tween(pf, 3, { Transparency = 1 }, Enum.EasingStyle.Linear)
	Debris:AddItem(pf, 3.1)
end

-- ============================================================================
-- IT IS ALWAYS THERE -- asleep under the stack from the moment you land
-- ============================================================================
-- The Chocolate Monster on island3 is on its island from the first second, dozing, and only
-- turns hostile once the quest reaches the right stage. This one works the same way, for the
-- same reason its comments give: a monster that materialises when a counter hits five reads
-- as a spawn, while one that has been snoring under the pancake the whole time reads as
-- something you WOKE. It also means the arena is never an empty field with a stack in it.
local scatterButter   -- forward: the butter is scattered as the monster stands up

-- built once, at boot, slumped and sunk into the ground under the stack
local function spawnSleepingMonster()
	if monster or not arenaCF then return end
	local at = arenaCF.Position
	buildMonster(at)
	monState = "asleep"
	poseSwing = 0
	-- SUNK, not hidden: its back is a mound under the pancake and its face is buried, which is
	-- why the stack sits so high in the first place. The head and shoulders read as scenery
	-- until the moment they stand up.
	monBody.CFrame = CFrame.new(at.X, groundY(at) + 2.5, at.Z) * CFrame.Angles(0, 0, math.rad(90))
	if eyeL then
		eyeL.Material = Enum.Material.SmoothPlastic; eyeR.Material = Enum.Material.SmoothPlastic
		eyeL.Color = CAKE_LO; eyeR.Color = CAKE_LO      -- eyes shut: no glow while it sleeps
	end
	if monTag then monTag.Text = E.CAKE .. " ...zzz..." end
	poseMonster()
	print("[Pancake] the monster is asleep under the stack -- it has been there all along")
end

wakeTheMonster = function()
	-- YOU POURED YOUR FIFTH WHILE WATCHING SOMEBODY ELSE'S MONSTER. Take it back: it is your
	-- quest now, and the cinematic runs from the arena as normal. Without this the guard below
	-- would bounce off "remote", and pouring the last syrup would silently do nothing --
	-- a dead end with no way out of it.
	-- ...or while it was wandering the island as scenery. Either way it has to end up under the
	-- stack before the cinematic runs, because that cinematic lifts the pancake off its head.
	-- It RUNS there rather than blinking there -- see the stampede in the shake phase below,
	-- which is why this only claims the monster and does not move it.
	if monState == "remote" or monState == "roam" then
		REM.on, REM.cf = false, nil
		monState = "asleep"
		if monBody and monBody.Parent then monBody.Size = BODY_BASE end
		print("[Pancake] taking the monster back -- our own pour woke it")
	end
	if monState ~= "asleep" then return end
	local at = arenaCF.Position
	monState = "rising"          -- claimed immediately: two pours on the same frame cannot
	                             -- both start the cinematic

	-- 1. THE SHAKE. Three seconds of the stack rattling harder and harder -- and, if the monster
	-- was out wandering the island when you poured, three seconds of it STAMPEDING BACK. It has
	-- to be under the stack for the lift to make sense, and the shake is exactly the window to
	-- cover the trip: it hears the pour and comes running. Snapping it back instead read as a
	-- teleport bug to anyone watching it happen.
	flashBanner(E.CAKE .. " ...the pancake is shaking...", 3)
	local t0 = os.clock()
	local fromP = monBody and monBody.Position or at
	local runHome = ((fromP - at) * Vector3.new(1, 0, 1)).Magnitude > 12
	local shakeConn
	shakeConn = RunService.RenderStepped:Connect(function()
		local k = math.min(1, (os.clock() - t0) / 3)
		movePancake(
			Vector3.new((math.random() - 0.5) * k * 3, 0, (math.random() - 0.5) * k * 3),
			CFrame.Angles(0, (math.random() - 0.5) * k * 0.2, 0))
		if runHome and monBody and monBody.Parent then
			-- eased so it arrives just as the shake ends, then sinks into the sleeping pose over
			-- the last stretch -- the rise below starts from wherever this leaves it
			local e = 1 - (1 - k) * (1 - k)
			local np = fromP:Lerp(at, e)
			local sink = math.max(0, (k - 0.75) / 0.25)
			local y = groundY(np) + 12 - 9.5 * sink
			monBody.CFrame = CFrame.lookAt(Vector3.new(np.X, y, np.Z), Vector3.new(at.X, y, at.Z))
				* CFrame.Angles(0, 0, math.rad(90))
			poseSwing = 0.9 * (1 - sink)
			dropFootprint(np)
			poseMonster()
		end
		if k >= 1 and shakeConn then shakeConn:Disconnect() end
	end)
	shakeCamera(1.0, 3)
	task.wait(3.1)
	if shakeConn then shakeConn:Disconnect() end

	-- 2. THE LIFT. It stands up out of the ground it was slumped in, and the whole stack
	-- rides up on its head. The eyes come back on partway through the climb.
	roar()
	shakeCamera(3.0, 1.4)
	if eyeL then
		eyeL.Material = Enum.Material.Neon; eyeR.Material = Enum.Material.Neon
		eyeL.Color = Color3.fromRGB(255, 226, 130); eyeR.Color = eyeL.Color
	end
	poseSwing = 0
	poseMonster()

	local riseT = os.clock()
	local riseConn
	local sunkY = groundY(at) + 2.5
	riseConn = RunService.RenderStepped:Connect(function()
		local k = math.min(1, (os.clock() - riseT) / 2.4)
		local y = sunkY + (groundY(at) + 13 - sunkY) * k
		monBody.CFrame = CFrame.new(at.X, y, at.Z) * CFrame.Angles(0, 0, math.rad(90))
		-- the stack rides up ON ITS HEAD, so it climbs faster than the monster does
		movePancake(Vector3.new(0, (y + 12 * k) - pancakeHomeCF.Position.Y, 0))
		poseMonster()
		if k >= 1 and riseConn then riseConn:Disconnect() end
	end)
	task.wait(2.5)
	if riseConn then riseConn:Disconnect() end

	-- 3. THE STACK SLIDES OFF. The pancake it was hiding under tumbles away and lands flat.
	-- Driven frame by frame rather than tweened: a Tween on the PrimaryPart would move ONE of
	-- the stack's eight parts and leave the other seven hanging in the air.
	if pancakeModel then
		local fromOff = Vector3.new(0, 24 - pancakeHomeCF.Position.Y + groundY(at) + 1, 0)
		local toOff   = Vector3.new(28, groundY(at) + 1.6 - pancakeHomeCF.Position.Y, -18)
		local slideT = os.clock()
		local slideConn
		slideConn = RunService.RenderStepped:Connect(function()
			local k = math.min(1, (os.clock() - slideT) / 1.1)
			local e = 1 - (1 - k) * (1 - k)          -- ease out
			movePancake(fromOff:Lerp(toOff, e), CFrame.Angles(0, e * 2.2, 0))
			if k >= 1 and slideConn then slideConn:Disconnect() end
		end)
	end
	-- NOTE: nothing here disables the stack's prompts. refreshPrompts() already turns the POUR
	-- prompt off for every step past 1, and the fallback TALK prompt lives on this same part --
	-- blanket-disabling the model's prompts would silently delete the quest giver on an island
	-- with no NPC, right before the dialogue that pays off the whole fight.
	roar()
	groundSmash(at)

	-- 4. THE HUNT BEGINS, and the butter appears around the island as it does.
	monState = "hunt"
	chaseT = os.clock()
	targetPlayer = pickTarget()
	step = 4
	scatterButter()
	refreshBanner(); refreshPrompts()
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(function() _G.NotifyCenter.push({
			text = E.CAKE .. " THE PANCAKE MONSTER IS AWAKE! Grab the butter!", color = CAKE_LO }) end)
	end
	print("[Pancake] the monster is up -- hunt begins")
end

-- ============================================================================
-- THE HUNT LOOP
-- ============================================================================
RunService.RenderStepped:Connect(function(dt)
	if not (monBody and monBody.Parent) then return end

	-- ===== SOMEBODY ELSE'S HUNT =====
	-- Their client did all the thinking; ours only has to put the body where they say and swing
	-- the limbs. Eased rather than snapped, because 12 messages a second against 60 frames would
	-- otherwise read as a stutter -- and the ease is on a TIME constant, not a fixed fraction,
	-- so it looks the same on a 30 fps tablet as on a 144 Hz monitor.
	if monState == "remote" then
		if REM.cf then
			local k = 1 - math.exp(-dt * 14)
			monBody.CFrame = monBody.CFrame:Lerp(REM.cf, k)
		end
		poseSwing = (poseSwing + dt * 3.2) % (math.pi * 2)
		poseMonster()
		-- IT CAN STILL SHOVE YOU. Being knocked flat is the whole threat of the thing, and a
		-- monster that walks straight through you is scenery. Each client decides this for its
		-- OWN player only -- which is exactly how the authority's copy already works.
		local hrp = hrpOf()
		if hrp and (hrp.Position - monBody.Position).Magnitude < 11 then shovePlayer(hrp) end
		-- THE HOST WENT AWAY: fell down a hole, closed the game, quest reset. Without this the
		-- monster stands in a field forever and the arena never gets it back. It is handed back
		-- to our own state machine rather than destroyed and rebuilt -- from "asleep" it either
		-- lies down under the stack or stands up and wanders, depending on who is still here,
		-- and that decision already has one home.
		if os.clock() - REM.last > 6 then
			REM.on, REM.cf = false, nil
			monState = "asleep"
			print("[Pancake] the shared monster's host went quiet -- ours is local again")
		end
		return
	end

	if monState == "rising" or monState == "melted" then return end
	local here = monBody.Position
	local now  = os.clock()

	if monState == "melting" then
		poseSwing = 0
		poseMonster()
		return
	end

	if monState == "asleep" then
		-- ===== SOMEBODY WHO HAS BEATEN IT IS HERE: IT GETS UP AND WANDERS =====
		-- The island is not a museum. Once a player who has finished the quest is standing on
		-- it, the monster is up and walking around as scenery -- harmless, ignoring everyone.
		-- Gated on HAVING COMPLETED IT on purpose: for a kid who has not, the thing under the
		-- stack is still a surprise, and a monster already strolling about when they arrive
		-- gives away the entire quest before they have poured a drop.
		if _G.pancakeQuestComplete and arenaCF then
			local hrp = hrpOf()
			if hrp and (hrp.Position - arenaCF.Position).Magnitude <= ISLAND_RANGE then
				monBody.Size = BODY_BASE          -- the sleep breath scales it; put it back
				monState = "roam"
				REM.roamAt, REM.roamTo = 0, nil
				if eyeL and eyeL.Parent then
					eyeL.Material = Enum.Material.Neon; eyeR.Material = Enum.Material.Neon
					eyeL.Color = Color3.fromRGB(255, 226, 130); eyeR.Color = eyeL.Color
				end
				if monTag then monTag.Text = E.CAKE .. " Pancake Monster" end
				print("[Pancake] up and wandering -- someone on the island has beaten it")
				return
			end
		end
		-- STRANDED? A monster handed back from the network -- host quit, host walked off the
		-- island, hunt ended somewhere else -- can be standing anywhere. "Asleep" means asleep
		-- UNDER THE STACK, so walk it home first. Without this it sinks into the ground wherever
		-- it happened to be left, half-buried in the middle of a field, with the arena empty.
		if arenaCF and ((here - arenaCF.Position) * Vector3.new(1, 0, 1)).Magnitude > 12 then
			local home = arenaCF.Position
			local dir = ((home - here) * Vector3.new(1, 0, 1)).Unit
			local np = clampToIsland(here + dir * WANDER_SPEED * dt, 6)
			local y = groundY(np) + 12
			monBody.CFrame = CFrame.lookAt(Vector3.new(np.X, y, np.Z), Vector3.new(home.X, y, home.Z))
				* CFrame.Angles(0, 0, math.rad(90))
			poseSwing = 0.4
			poseMonster()
			return
		end

		-- BREATHING, AND NOTHING ELSE. It does not stir, it does not notice you, and it will
		-- not wake on its own -- pouring the fifth syrup is the only thing that wakes it. A
		-- player on step 1 can walk right over it looking for bottles and be perfectly safe.
		local breathe = math.sin(now * 0.9) * 0.05
		monBody.Size = BODY_BASE * (1 + breathe)
		monBody.CFrame = CFrame.new(here.X, groundY(here) + 2.5 + breathe * 3, here.Z)
			* CFrame.Angles(0, 0, math.rad(90))
		poseSwing = 0
		poseMonster()
		return
	end

	-- ===== THE AMBIENT WANDER -- ALWAYS MOVING, NEVER ATTACKING =====
	-- This is not the hunt with the teeth filed off; it is a different behaviour. It picks a
	-- spot on the island, walks to it, picks another. It never looks up a player, never targets
	-- one and never shoves -- shovePlayer is not reachable from this branch at all, which is a
	-- stronger guarantee than a flag somebody can forget to check. Same steering and the same
	-- island clamp as the chase, because those solve problems the wander has too: not walking
	-- through trees, and not walking off the rim into open sky.
	if monState == "roam" then
		local hrp  = hrpOf()
		local home = arenaCF and arenaCF.Position or here
		local flat = Vector3.new(1, 0, 1)
		-- NOBODY LEFT WHO HAS BEATEN IT -> BACK TO BED. It walks home and lies down under the
		-- stack rather than blinking out: a monster that vanishes in front of a kid who is still
		-- collecting syrup is a bug they will tell their friends about.
		if not (_G.pancakeQuestComplete and hrp
			and (hrp.Position - home).Magnitude <= ISLAND_RANGE) then
			REM.roamTo = home
			if ((here - home) * flat).Magnitude < 12 then
				monState = "asleep"
				monBody.CFrame = CFrame.new(home.X, groundY(home) + 2.5, home.Z)
					* CFrame.Angles(0, 0, math.rad(90))
				if eyeL and eyeL.Parent then
					eyeL.Material = Enum.Material.SmoothPlastic; eyeR.Material = Enum.Material.SmoothPlastic
					eyeL.Color = CAKE_LO; eyeR.Color = CAKE_LO
				end
				if monTag then monTag.Text = E.CAKE .. " ...zzz..." end
				poseSwing = 0
				poseMonster()
				print("[Pancake] nobody here has beaten it -- back to sleep under the stack")
				return
			end
		elseif (not REM.roamTo) or now >= (REM.roamAt or 0)
			or ((here - REM.roamTo) * flat).Magnitude < 10 then
			-- somewhere else on the island, biased to a ring around the arena so it stays in
			-- sight of the quest rather than parking itself in a far corner for a minute
			REM.roamAt = now + 7 + math.random() * 9
			local ang, rad = math.random() * math.pi * 2, 45 + math.random() * 95
			REM.roamTo = home + Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)
		end

		local dir = (REM.roamTo - here) * flat
		if dir.Magnitude > 2 then
			dir = dir.Unit
			for _, turn in ipairs({ 0, 0.6, -0.6, 1.2, -1.2, 2.0, -2.0 }) do
				local try = (turn == 0) and dir or (CFrame.Angles(0, turn, 0) * dir)
				if not blockedAhead(here, try * WANDER_SPEED * dt) then dir = try; break end
			end
			local np = clampToIsland(here + dir * WANDER_SPEED * dt, 6)
			local y = groundY(np) + 12 + math.sin(now * 2.2) * 0.35
			-- FACING THE WAY IT WALKS, not at a player: the difference is the whole read of the
			-- thing. A monster that keeps turning to look at you is stalking you.
			monBody.CFrame = CFrame.lookAt(Vector3.new(np.X, y, np.Z),
				Vector3.new(np.X + dir.X, y, np.Z + dir.Z)) * CFrame.Angles(0, 0, math.rad(90))
			dropFootprint(np)
			poseSwing = 0.45
		else
			REM.roamAt = 0                -- arrived: somewhere new next frame
			poseSwing = 0.15
		end
		poseMonster()
		return
	end

	if monState == "hunt" then
		-- re-pick every few seconds so it switches to whoever is nearest now
		if now >= retargetAt then
			retargetAt = now + 5
			targetPlayer = pickTarget() or targetPlayer
		end
		local hrp = targetHRP()
		local nearIsland = hrp and arenaCF and (hrp.Position - arenaCF.Position).Magnitude <= ISLAND_RANGE
		local dist = hrp and (hrp.Position - here).Magnitude or math.huge

		-- lost everyone: amble back to the arena and wait
		if not hrp or not nearIsland or dist > LEASH_RANGE then
			poseSwing = 0.5
			local target = arenaCF and arenaCF.Position or here
			local dir = (target - here) * Vector3.new(1, 0, 1)
			if dir.Magnitude > 4 then
				dir = dir.Unit
				for _, turn in ipairs({ 0, 0.6, -0.6, 1.2, -1.2 }) do    -- same steering as the chase
					local try = (turn == 0) and dir or (CFrame.Angles(0, turn, 0) * dir)
					if not blockedAhead(here, try * WANDER_SPEED * dt) then dir = try; break end
				end
				-- clamped to the island's own footprint: a monster that walks off the rim is a
				-- monster with no ground under it, and no ground under it is how it fell through
				local np = clampToIsland(here + dir * WANDER_SPEED * dt, 6)
				local y = groundY(np) + 12 + math.sin(now * 3) * 0.3
				monBody.CFrame = CFrame.lookAt(Vector3.new(np.X, y, np.Z), Vector3.new(target.X, y, target.Z))
					* CFrame.Angles(0, 0, math.rad(90))
				dropFootprint(np)
			end
			poseMonster()
			return
		end

		local frac  = math.min(1, (now - chaseT) / RAMP_TIME)
		local speed = SPEED_MIN + (SPEED_MAX - SPEED_MIN) * frac
		poseSwing = 0.7 + frac * 0.4
		if eyeL and eyeL.Parent then
			local col = Color3.fromRGB(255, 226, 130):Lerp(Color3.fromRGB(255, 90, 40), frac)
			eyeL.Color = col; eyeR.Color = col
		end
		if steamMon then steamMon.Enabled = frac > 0.6 end

		local dir = (hrp.Position - here) * Vector3.new(1, 0, 1)
		if dir.Magnitude > 0.5 then
			dir = dir.Unit
			-- ===== STEER ROUND WHATEVER IS IN THE WAY =====
			-- Straight at you first; if something solid is in that step, try turning further and
			-- further off it, alternating sides, and take the first line that is clear. Sidling
			-- round a tree at 60 degrees still closes on you -- it just does not go through it --
			-- and if every line is blocked it holds position rather than shoving into the trunk.
			for _, turn in ipairs({ 0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6 }) do
				local try = (turn == 0) and dir
					or (CFrame.Angles(0, turn, 0) * dir)
				if not blockedAhead(here, try * speed * dt) then dir = try; break end
			end
			local np = clampToIsland(here + dir * speed * dt, 6)   -- see the note in the amble above
			local y  = groundY(np) + 12 + math.abs(math.sin(now * 9)) * 0.6
			-- ⚠ the trailing roll is the CYLINDER FIX, not styling: the body is a cylinder on
			-- its side, so its resting frame is rolled 90 degrees and lookAt would stand it up.
			monBody.CFrame = CFrame.lookAt(Vector3.new(np.X, y, np.Z), Vector3.new(hrp.Position.X, y, hrp.Position.Z))
				* CFrame.Angles(0, 0, math.rad(90) + math.sin(now * 9) * 0.14 * poseSwing)
			dropFootprint(np)
		end

		-- IT SMASHES THE GROUND as it comes, faster the angrier it is
		if now - lastSmash > SMASH_EVERY - frac * 1.4 then
			lastSmash = now
			groundSmash(here + dir * 6)
		end

		-- THE GRAB. Horizontal reach PLUS a vertical gate: its body is centred 12 up, so the
		-- grab tops out around its head and FLYING OVER IT IS SAFE. It has to actually reach
		-- you, not claim the airspace above.
		local horiz = ((hrp.Position - here) * Vector3.new(1, 0, 1)).Magnitude
		local dy = hrp.Position.Y - here.Y
		if horiz <= CATCH_RANGE and dy <= 9 and dy >= -14 and targetPlayer == player then
			shovePlayer(hrp)
		end
		poseMonster()
		return
	end
end)

-- the mood label reacts to what it is doing
task.spawn(function()
	while true do
		task.wait(0.3)
		if monTag then
			if monState == "melting" or monState == "melted" then
				monTag.Text = E.BUTTER .. " ...melting..."
			elseif monState == "hunt" and targetPlayer then
				monTag.Text = ("%s Pancake Monster  (%d/%d butter)"):format(E.CAKE, butterStuck, BUTTER_COUNT)
			else
				monTag.Text = E.CAKE .. " Pancake Monster"
			end
		end
	end
end)

-- ============================================================================
-- THE BUTTER
-- ============================================================================
local function buildButter(at)
	local m = Instance.new("Model"); m.Name = "ButterPiece"
	m:SetAttribute("QuestProp", true)
	local body = mk({ Name = "Body", Size = Vector3.new(3.6, 2.0, 2.2), Color = BUTTER,
		Material = Enum.Material.SmoothPlastic, Reflectance = 0.1, Parent = m })
	body.CFrame = CFrame.new(at + Vector3.new(0, 1.0, 0))
	m.PrimaryPart = body
	local wrap = mk({ Name = "Wrap", Size = Vector3.new(3.7, 2.1, 1.0), Color = Color3.fromRGB(250, 246, 232), Parent = m })
	wrap.CFrame = body.CFrame

	local hl = Instance.new("Highlight")
	hl.FillColor = BUTTER; hl.FillTransparency = 0.5
	hl.OutlineColor = Color3.fromRGB(255, 248, 200); hl.OutlineTransparency = 0.1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = m; hl.Parent = m

	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(130, 34); tag.StudsOffset = Vector3.new(0, 3.4, 0)
	tag.AlwaysOnTop = true; tag.MaxDistance = 220; tag.Adornee = body; tag.Parent = body
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1,1); tl.BackgroundTransparency = 1; tl.Font = Enum.Font.FredokaOne
	tl.TextColor3 = Color3.fromRGB(255,255,255); tl.TextStrokeColor3 = TEXTC; tl.TextStrokeTransparency = 0
	tl.TextScaled = true; tl.Text = E.BUTTER .. " BUTTER"; tl.Parent = tag

	m.Parent = questFolder
	body.CanQuery = true
	return m, body
end

local function takeButter(rec)
	if step ~= 4 or rec.taken then return end
	rec.taken = true
	if rec.prompt then rec.prompt.Enabled = false end
	if rec.model.Parent then
		poofAt(rec.model:GetPivot().Position, BUTTER, 8)
		rec.model:Destroy()
	end
	butterHeld += 1
	playSound(SOUND_PICKUP, 0.5)
	refreshBanner()

	if butterHeld >= BUTTER_COUNT then
		step = 5
		flashBanner(E.BUTTER .. " ALL 8! Get close and THROW them at it!", 3.5)
		refreshBanner(); refreshPrompts()
	else
		flashBanner(("%s Butter %d/%d -- keep running!"):format(E.BUTTER, butterHeld, BUTTER_COUNT), 1.6)
	end
end

-- WHERE THE BUTTER LIES. Same rule as the syrup: your "butter" markers win, a golden-angle
-- spiral fills the rest -- but on a WIDER radius, because this half of the quest is a chase
-- and butter clustered at the arena would mean never having to run anywhere.
scatterButter = function()
	-- "butter" blocks are read and hidden exactly like the "syrup" ones: the BASE is where the
	-- pat sits, then the block goes invisible and non-collidable.
	--
	-- Anything not hand-placed uses the same boundary and the same collision test as the syrup,
	-- on a different slice of the sequence so the butter never lands on a spot a bottle used.
	-- Butter is small, so the clearance box is smaller -- but it still has to be clear of the
	-- island own props.
	local spots = {}
	for _, d in ipairs(findBlocks(BUTTER_NAME)) do
		spots[#spots + 1] = baseFrameOf(d).Position
		hideMarker(d)
	end
	local n, crowded = 0, 0
	while #spots < BUTTER_COUNT do
		n += 1
		local g, ok = placeInBounds(500 + n * 7, Vector3.new(5, 4, 5), spots, 18)
		if not ok then crowded += 1 end
		spots[#spots + 1] = g or clampToBounds(arenaCF.Position + Vector3.new(-50, 0, 30), 8)
	end
	if crowded > 0 then
		warn(("[Pancake] %d butter could not find a clear patch inside the boundary -- placed anyway"):format(crowded))
	end
	for i = 1, BUTTER_COUNT do
		local m, main = buildButter(spots[i])
		local rec = { model = m, main = main, taken = false }
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Grab"; prompt.ObjectText = "Butter"
		prompt.HoldDuration = 0; prompt.MaxActivationDistance = PICKUP_RANGE
		prompt.RequiresLineOfSight = false; prompt.Parent = main
		prompt.Triggered:Connect(function() takeButter(rec) end)
		rec.prompt = prompt
		butters[#butters + 1] = rec
	end
	print(("[Pancake] %d butter scattered across island18"):format(#butters))
end

-- ============================================================================
-- THE THROW, AND THE MELT
-- ============================================================================
local finishQuest    -- forward

local function meltMonster()
	monState = "melting"
	-- tell the island it is over; followers hand their own copy back to their own state machine
	if REM.ev and not REM.on then pcall(function() REM.ev:FireServer("melt", "cake") end) end
	-- ...and book its return. Melting destroys the monster outright, so without this the player
	-- who just beat it -- the one player the wander is gated on -- is the only one who never
	-- sees it again. Long enough that it is not standing behind them during the payout.
	REM.backAt = os.clock() + 25
	if steamMon then steamMon.Enabled = true end
	roar()
	shakeCamera(3.2, 1.6)

	local at = monBody.Position
	-- everything sinks and spreads: the rig flattens toward the ground over two seconds
	for _, e in ipairs(monParts) do
		if e.part.Parent then
			tween(e.part, 2.0, {
				Size = Vector3.new(e.part.Size.X * 1.35, math.max(0.4, e.part.Size.Y * 0.15), e.part.Size.Z * 1.35),
				Transparency = 0.15,
			}, Enum.EasingStyle.Sine)
		end
	end
	tween(monBody, 2.0, { Size = Vector3.new(1.2, BODY_BASE.Y * 1.6, BODY_BASE.Z * 1.6) }, Enum.EasingStyle.Sine)

	local sinkT = os.clock()
	local sinkConn
	sinkConn = RunService.RenderStepped:Connect(function()
		local k = math.min(1, (os.clock() - sinkT) / 2.0)
		local y = groundY(at) + 12 * (1 - k) + 1
		monBody.CFrame = CFrame.new(at.X, y, at.Z) * CFrame.Angles(0, 0, math.rad(90))
		poseMonster()
		if k >= 1 and sinkConn then sinkConn:Disconnect() end
	end)
	task.wait(2.2)
	if sinkConn then sinkConn:Disconnect() end

	-- ...into a giant pile of pancakes
	if monster then monster:Destroy() end
	monster, monBody = nil, nil
	monState = "melted"

	local pile = Instance.new("Model"); pile.Name = "PancakePile"
	pile:SetAttribute("QuestProp", true)
	local gy = groundY(at)
	for i = 1, 9 do
		local w = 30 - i * 1.8
		local disc = mk({ Name = "Pile" .. i, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.4, w, w), Color = (i % 2 == 0) and CAKE_HI or CAKE, Parent = pile })
		disc.CFrame = CFrame.new(at.X + math.sin(i) * 1.2, gy + 1.2 + (i - 1) * 2.2, at.Z + math.cos(i) * 1.2)
			* CFrame.Angles(0, i * 0.4, math.rad(90))
	end
	local pat = mk({ Name = "TopButter", Size = Vector3.new(6, 2.4, 6), Color = BUTTER, Parent = pile })
	pat.CFrame = CFrame.new(at.X, gy + 1.2 + 9 * 2.2, at.Z)
	pile.Parent = questFolder
	poofAt(Vector3.new(at.X, gy + 6, at.Z), CAKE_HI, 22)
	shockRing(at, CAKE_HI, 40, 0.8)

	finishQuest()
end

local function throwButter()
	if step ~= 5 or butterHeld < BUTTER_COUNT then return end
	if not (monBody and monBody.Parent) then return end
	local hrp = hrpOf()
	if not hrp then return end
	if (hrp.Position - monBody.Position).Magnitude > THROW_RANGE then
		flashBanner(E.BUTTER .. " Too far -- get closer to throw!", 2)
		return
	end
	step = 6                      -- locked in: no second volley, no double payout
	butterHeld = 0
	refreshBanner(); refreshPrompts()

	-- the volley: eight pats arc out of your hands and stick to it, one every tenth of a second
	for i = 1, BUTTER_COUNT do
		task.spawn(function()
			task.wait(i * 0.12)
			if not (monBody and monBody.Parent) then return end
			local from = hrp.Position + Vector3.new(0, 3, 0)
			local pat = mk({ Name = "ThrownButter", Size = Vector3.new(3.2, 1.8, 2.0), Color = BUTTER,
				Parent = questFolder })
			pat.CFrame = CFrame.new(from)
			local a = i * (math.pi * 2 / BUTTER_COUNT)
			local land = monBody.Position + Vector3.new(math.cos(a) * 4.5, math.sin(a) * 5 - 1, math.sin(a) * 4.5)
			tween(pat, 0.45, { CFrame = CFrame.new(land) * CFrame.Angles(a, a, 0) }, Enum.EasingStyle.Quad)
			task.wait(0.5)
			butterStuck += 1
			poofAt(land, BUTTER, 8)
			shakeCamera(0.8, 0.2)
			if steamMon then steamMon.Enabled = true end
			-- it shrinks a little with every pat that lands
			if monBody and monBody.Parent then
				monBody.Size = BODY_BASE * (1 - 0.05 * butterStuck)
			end
			if butterStuck >= BUTTER_COUNT then
				task.wait(0.3)
				meltMonster()
			end
		end)
	end
	flashBanner(E.BUTTER .. " BUTTER AWAY!", 2.5)
end

-- ============================================================================
-- THE PAYOUT
-- ============================================================================
-- Coins go through CoinEvent, which is how every other Candy quest pays. The crate tokens
-- and the fart-power top-up go through IslandTaskTokens' ledger, which pays ONCE EVER per
-- quest per player -- so neither can be farmed by replaying the fight.
local function payCoins(n)
	local ce = ReplicatedStorage:FindFirstChild("CoinEvent") or _G.CoinEvent
	if not ce then
		warn("[Pancake] CoinEvent missing -- finale reward not paid")
		return
	end
	local ok = pcall(function() ce:FireServer(n) end)
	if not ok then warn("[Pancake] CoinEvent:FireServer failed -- finale reward not paid") end
end

local function firework(from, colour)
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2
		local spark = mk({ Size = Vector3.new(0.7, 0.7, 0.7), Shape = Enum.PartType.Ball,
			Color = colour, Material = Enum.Material.Neon, Parent = questFolder })
		spark.CFrame = CFrame.new(from)
		tween(spark, 1.1, {
			CFrame = CFrame.new(from + Vector3.new(math.cos(a) * 26, 16 + math.sin(a) * 12, math.sin(a) * 26)),
			Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 })
		Debris:AddItem(spark, 1.2)
	end
end

finishQuest = function()
	step = 6
	_G.pancakeQuestComplete = true      -- IslandTaskWatcher claims the crate tokens off this
	-- CINEMATIC PAYOFF. RevealCommand resolves island18's subject itself and plays the shot, so this
	-- is one line and re-aiming it later is an edit to TARGETS there, not here. Delayed so the
	-- completion banner and the world change land FIRST -- the camera is going there to show you
	-- the result, and cutting away before it happens shows you the before.
	task.delay(1.0, function() pcall(_G.revealIsland, 18) end)
	_G.pancakeQuestStep = nil
	refreshBanner(); refreshPrompts()
	payCoins(COIN_REWARD)

	local at = (arenaCF and arenaCF.Position) or (hrpOf() and hrpOf().Position)
	if at then
		firework(at + Vector3.new(0, 14, 0), GOLD)
		task.delay(0.4, function() firework(at + Vector3.new(18, 16, -12), CAKE_HI) end)
		task.delay(0.8, function() firework(at + Vector3.new(-20, 15, 14), BUTTER) end)
	end
	if npcHead then showBubble(npcHead, "You MELTED it! Look at that pile -- breakfast for a year!", false) end
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(function() _G.NotifyCenter.push({
			text = ("%s Pancake Monster melted! +%d coins"):format(E.SPARK, COIN_REWARD), color = GOLD }) end)
	end
	flashBanner(("%s You melted the Pancake Monster!  +%d coins %s"):format(E.SPARK, COIN_REWARD, E.SPARK), 6)
	print(("[Pancake] quest complete -- +%d coins, tokens + power claimed via IslandTaskTokens"):format(COIN_REWARD))
end

-- ============================================================================
-- PROMPT REFRESH -- one place that decides what is pressable right now
-- ============================================================================
local throwPrompt        -- the pads own the pouring prompts; only this one is file-level

refreshPrompts = function()
	for _, rec in ipairs(syrups) do
		if rec.prompt then rec.prompt.Enabled = (step == 1) and not rec.taken and not carrying end
	end
	for _, rec in ipairs(butters) do
		if rec.prompt then rec.prompt.Enabled = (step == 4) and not rec.taken end
	end
	-- a pad is pressable only while you are carrying a bottle AND it is still empty, so the
	-- five prompts can never compete with each other for the same E press.
	for _, pad in ipairs(pads) do
		if pad.prompt then pad.prompt.Enabled = (step == 1) and carrying ~= nil and not pad.filled end
	end
	if throwPrompt then throwPrompt.Enabled = (step == 5) and butterHeld >= BUTTER_COUNT end
end

-- ============================================================================
-- THE NPC
-- ============================================================================
local function questPages()
	if step >= 6 then
		return {
			"A PILE OF PANCAKES. That is the best possible outcome.",
			"You woke it, you ran from it, you buttered it. Legend.",
		}
	elseif step == 5 then
		return { "You've got all eight! Get close and let them FLY!" }
	elseif step == 4 then
		return { ("Butter! It hates butter! Get eight -- you have %d!"):format(butterHeld) }
	elseif step == 3 then
		return { "IT'S GETTING UP. RUN. RUN RUN RUN!" }
	elseif step == 1 then
		if carrying then return { "You're holding one! Onto the pancake with it!" } end
		return {
			("Still hunting? %d of %d poured."):format(poured, SYRUP_COUNT),
			"They're big -- look behind the rocks and round the edges.",
		}
	end
	return {
		"See that pancake in the middle? It's not a pancake.",
		"Well -- it IS a pancake. It's just also something ELSE.",
		"Five giant syrup bottles are hidden round this island.",
		"Pour every one onto the stack and we'll find out what.",
		("Wake it and melt it and there's %d coins in it for you. Deal?"):format(COIN_REWARD),
	}
end

local function wireNPC(head)
	if not head then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = "Candy NPC"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = TALK_DISTANCE; prompt.RequiresLineOfSight = false; prompt.Parent = head

	local pages, index = nil, 0
	local watching = false
	local function closeDialogue() hideBubble(head); prompt.ActionText = "Talk"; index = 0; pages = nil end
	local function startWatcher()
		if watching then return end
		watching = true
		task.spawn(function()
			while index ~= 0 do
				local hrp = hrpOf()
				if not hrp or (hrp.Position - head.Position).Magnitude > TALK_DISTANCE then
					closeDialogue(); break
				end
				task.wait(0.25)
			end
			watching = false
		end)
	end

	prompt.Triggered:Connect(function()
		if index == 0 then pages = questPages() end
		index += 1
		if not pages or index > #pages then
			closeDialogue()
			if step == 0 then
				step = 1
				refreshBanner(); refreshPrompts()
				flashBanner(E.DROP .. " Find the five giant syrup bottles!", 3.5)
			end
			return
		end
		local last = index >= #pages
		local footer = last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages)
		showBubble(head, pages[index], true, footer)
		prompt.ActionText = last and "Close" or "Continue"
		startWatcher()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then closeDialogue() end end)
	return prompt
end

-- ============================================================================
-- SET DRESSING -- "SyrupPump" and "ButterLauncher"
-- ============================================================================
-- Two machines built on your marker blocks, the same way island15's Bake-Off builds its
-- mixing station and ovens on "Mixer" and "Oven": the block gives POSITION and SIZE, gets
-- hidden, and a model is built on its BASE (not its top -- building on the top surface floats
-- everything a whole marker-height too high) and grown to fit its footprint.
--
-- PURELY DECORATIVE, ON PURPOSE. Neither one has a ProximityPrompt, neither is referenced by
-- a quest step, and neither can be interacted with. They exist so the arena reads as a place
-- where pancakes get made rather than an empty field with a stack in the middle. They DO block
-- prop placement, though -- see the sceneryFolder note above -- so a syrup bottle never spawns
-- inside one.
-- ============================================================================
-- (!!) THE 200-REGISTER CEILING -- READ THIS BEFORE ADDING TOP-LEVEL NAMES (!!)
-- ============================================================================
-- Luau allows 200 LOCAL REGISTERS PER FUNCTION, and a file's main chunk is a function. This
-- one hit the ceiling and the result was NOT a warning and NOT a runtime error: the script
-- failed to COMPILE, so nothing in the whole file ran and island18 came up completely empty --
-- no machines, no pancake, no monster, no pads. The message names whichever local happened to
-- tip it over ("Out of local registers when trying to allocate animateScenery"), which is
-- almost never the one actually at fault.
--
-- WHAT ACTUALLY BUYS HEADROOM: fewer live NAMES. A table costs one register no matter how many
-- fields it has, which is why the parts kit lives on MECH and the emoji live on E rather than
-- as twelve separate locals.
--
-- WHAT THIS do...end BLOCK DOES, precisely: locals inside it are freed at `end`, so they stop
-- counting for everything AFTER it. It does NOT lower the peak inside itself -- in here, the
-- chunk's locals and the block's are both live at once. It is worth having anyway, because the
-- boot section below is long and would otherwise inherit all twenty of these.
--
-- ADD NEW MACHINE CODE INSIDE THIS BLOCK, and prefer a field on an existing table to a new
-- top-level local.
local buildScenery              -- the only name this section exposes
do
local SCENERY_BASE = 8      -- the nominal footprint both machines are drawn at, before scaling

local function sceneryPart(props, parent)
	local p = mk(props)
	p.CanCollide = true; p.CanQuery = true     -- solid: you can lean on a machine
	p.CastShadow = true
	p.Parent = parent
	return p
end

-- a little wooden sign, the same idea as the Bake-Off's "THE BAKERY" board
local function signOn(model, at, text)
	local board = sceneryPart({ Size = Vector3.new(5.4, 1.6, 0.3), Color = Color3.fromRGB(178, 126, 78),
		Material = Enum.Material.WoodPlanks }, model)
	board.CFrame = at
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(540, 160)
	sg.AlwaysOnTop = false; sg.Parent = board
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1; l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.FredokaOne; l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(255, 246, 232); l.Text = text; l.Parent = sg
	return board
end

-- ---------------------------------------------------------------------------
-- MECHANICAL PARTS KIT -- how these machines stop looking like stacked boxes
-- ---------------------------------------------------------------------------
-- The blocky look does not come from using Parts; it comes from placing each Part at a
-- hand-typed offset and hoping the gaps do not show. Everything below is built from JOINTS
-- INSTEAD OF OFFSETS: you say where a pipe starts and ends and the kit spans it, caps both
-- ends with a rounded elbow, and bolts a flange over the seam. Two consequences, and they are
-- the whole point:
--
--   * NOTHING FLOATS APART. A span is defined by its two endpoints, so a pipe cannot end an
--     inch short of the tank it feeds -- move the tank and the pipe follows by construction.
--   * EVERY SEAM IS COVERED. Real machines are not smooth; they are pieces bolted together,
--     and the flange-and-rivet ring over each join is what reads as "assembled" rather than
--     "clipped". A visible bolt is worth more than a smoother curve.
--
-- Curves come from Cylinders and Balls doing the work Wedges cannot, plus deliberate overlap:
-- every elbow sphere is slightly FATTER than the pipe it joins, so the silhouette bulges at
-- the joint the way welded steel does instead of showing a hairline crack.

local MECH = {
	IRON   = Color3.fromRGB( 92,  88,  94),
	IRON_D = Color3.fromRGB( 54,  51,  58),
	IRON_L = Color3.fromRGB(132, 128, 134),
	BRASS  = Color3.fromRGB(206, 162,  74),
	BRASS_D = Color3.fromRGB(150, 112,  44),
	RUST   = Color3.fromRGB(136,  82,  52),
}

-- ---------------------------------------------------------------------------
-- THE LOW-POLY FINISH -- one knob and one sweep
-- ---------------------------------------------------------------------------
-- These machines have to read as real machinery AND stay low-poly, and those two goals fight
-- over exactly one thing: SURFACE NOISE. The joinery above -- struts, flanges, a visible bolt at
-- every seam -- is what makes them believable, so all of that stays. What goes is the busy
-- surface: DiamondPlate tread, brushed Metal speckle, Glass reflections. Every one of those is a
-- texture pretending to be geometry, and at low poly it only muddies the silhouette.
--
--   MECH.DENSITY -- how many of the small repeated pieces (bolts, rivets, taper steps) get made.
--                   Half as many, each a size chunkier, is the low-poly idiom: it reads as bolder
--                   rather than sparser, and it is a real part-count cut on two big models.
--   MECH.lowPoly -- the finishing sweep: flat SmoothPlastic, no reflectance, no surface style.
--                   Neon is left alone (it is a light, not a texture) and so is Transparency,
--                   which is glass on purpose.
MECH.DENSITY = 0.5

function MECH.lowPoly(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Material ~= Enum.Material.Neon then
				d.Material = Enum.Material.SmoothPlastic
			end
			d.Reflectance = 0
			d.TopSurface = Enum.SurfaceType.Smooth
			d.BottomSurface = Enum.SurfaceType.Smooth
		end
	end
end

-- a rounded elbow / weld bulge at a joint
function MECH.ball(model, at, r, colour, material)
	local p = sceneryPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(r * 2, r * 2, r * 2),
		Color = colour or MECH.IRON, Material = material or Enum.Material.Metal }, model)
	p.CFrame = CFrame.new(at)
	return p
end

-- a ring of bolt heads around a circular face: the cheapest, strongest "this is engineered"
-- signal there is. Real flanges have bolts; a smooth ring reads as plastic.
function MECH.bolts(model, cf, radius, n, colour)
	n = math.max(3, math.round((n or 8) * MECH.DENSITY))     -- fewer, chunkier: see MECH.DENSITY
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		local bolt = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.46, 0.46),
			Color = colour or MECH.BRASS, Material = Enum.Material.Metal }, model)
		bolt.CanCollide = false
		bolt.CFrame = cf * CFrame.new(0, math.cos(a) * radius, math.sin(a) * radius)
	end
end

-- a flange: the wide collar where two pipes meet, with its bolt ring
function MECH.flange(model, cf, radius, colour)
	local f = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, radius * 2, radius * 2),
		Color = colour or MECH.IRON_L, Material = Enum.Material.Metal }, model)
	f.CanCollide = false
	f.CFrame = cf
	MECH.bolts(model, cf, radius * 0.68, 8)
	return f
end

-- A PIPE FROM A TO B. The span is solved, not typed: lookAt between the endpoints, stretched
-- to the distance, with the cylinder's length axis (its local X) turned onto that line. Elbow
-- balls at both ends are FATTER than the pipe, so the joint bulges like a weld instead of
-- showing the seam where two cylinders meet at an angle.
function MECH.pipe(model, from, to, radius, colour, opts)
	opts = opts or {}
	local span = to - from
	local len = span.Magnitude
	if len < 0.05 then return nil end
	local mid = from + span * 0.5
	local p = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, radius * 2, radius * 2),
		Color = colour or MECH.IRON, Material = opts.material or Enum.Material.Metal }, model)
	-- lookAt points -Z down the span; the extra yaw turns the cylinder's X onto it
	p.CFrame = CFrame.lookAt(mid, to) * CFrame.Angles(0, math.rad(90), 0)
	if not opts.noElbows then
		MECH.ball(model, from, radius * 1.22, colour or MECH.IRON, opts.material)
		MECH.ball(model, to,   radius * 1.22, colour or MECH.IRON, opts.material)
	end
	if opts.flanges then
		local dir = span.Unit
		MECH.flange(model, CFrame.lookAt(from + dir * (radius * 1.4), from + dir * (radius * 1.4) + dir)
			* CFrame.Angles(0, math.rad(90), 0), radius * 1.75, MECH.IRON_L)
		MECH.flange(model, CFrame.lookAt(to - dir * (radius * 1.4), to - dir * (radius * 1.4) + dir)
			* CFrame.Angles(0, math.rad(90), 0), radius * 1.75, MECH.IRON_L)
	end
	return p
end

-- a diagonal brace between two points. Struts are what make a frame read as a FRAME rather
-- than as four separate legs -- the eye reads triangles as structure.
function MECH.strut(model, from, to, thick, colour)
	local span = to - from
	local len = span.Magnitude
	if len < 0.05 then return nil end
	local p = sceneryPart({ Size = Vector3.new(thick or 0.3, thick or 0.3, len),
		Color = colour or MECH.IRON_D, Material = Enum.Material.Metal }, model)
	p.CanCollide = false
	p.CFrame = CFrame.lookAt(from + span * 0.5, to)
	return p
end

-- a ring of rivets around a barrel/tank at a given height
function MECH.rivets(model, cf, radius, n, colour)
	n = math.max(4, math.round((n or 14) * MECH.DENSITY))    -- fewer, chunkier: see MECH.DENSITY
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		local r = sceneryPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.36, 0.36, 0.36),
			Color = colour or MECH.BRASS_D, Material = Enum.Material.Metal }, model)
		r.CanCollide = false
		r.CFrame = cf * CFrame.new(0, math.cos(a) * radius, math.sin(a) * radius)
	end
end

-- a tapered tube: stacked cylinders shrinking along a line. A cannon muzzle, a chimney, a
-- funnel -- anything that should not be a uniform pipe. Roblox has no cone, so the taper is
-- built out of enough steps that the steps stop reading as steps.
function MECH.taper(model, from, to, r0, r1, steps, colour, material)
	-- LOW POLY WANTS THE STEPS TO SHOW A LITTLE. Half as many, each 25% overlapped as before, is
	-- a faceted cone rather than a smooth one -- which is the look, not a compromise on it.
	steps = math.max(2, math.ceil((steps or 6) * MECH.DENSITY))
	local span = to - from
	for i = 0, steps - 1 do
		local t0, t1 = i / steps, (i + 1) / steps
		local a, b = from + span * t0, from + span * t1
		local r = r0 + (r1 - r0) * ((t0 + t1) * 0.5)
		local seg = b - a
		local p = sceneryPart({ Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(seg.Magnitude * 1.25, r * 2, r * 2),   -- 1.25: overlap, no seams
			Color = colour or MECH.IRON, Material = material or Enum.Material.Metal }, model)
		p.CanCollide = false
		p.CFrame = CFrame.lookAt(a + seg * 0.5, b) * CFrame.Angles(0, math.rad(90), 0)
	end
end

-- a spoked wheel: rim, tyre band, hub, cap and bolts. Returned as a list of {part, angle} so
-- the caller can spin the spokes with the wheel.
function MECH.wheel(model, cf, radius, width, colour)
	local out = {}
	local tyre = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(width, radius * 2, radius * 2),
		Color = colour or MECH.IRON_D, Material = Enum.Material.Metal }, model)
	tyre.CFrame = cf
	local rim = sceneryPart({ Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(width * 1.15, radius * 1.82, radius * 1.82),
		Color = MECH.BRASS, Material = Enum.Material.Metal }, model)
	rim.CanCollide = false; rim.CFrame = cf
	local hub = sceneryPart({ Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(width * 1.5, radius * 0.44, radius * 0.44),
		Color = MECH.IRON_L, Material = Enum.Material.Metal }, model)
	hub.CanCollide = false; hub.CFrame = cf
	MECH.bolts(model, cf * CFrame.new(width * 0.8, 0, 0), radius * 0.3, 6, MECH.BRASS)
	out.tyre, out.rim, out.hub = tyre, rim, hub
	out.spokes = {}
	for i = 1, 6 do
		local a = i * (math.pi / 3)
		local sp = sceneryPart({ Size = Vector3.new(width * 0.55, radius * 0.22, radius * 1.72),
			Color = MECH.IRON, Material = Enum.Material.Metal }, model)
		sp.CanCollide = false
		sp.CFrame = cf * CFrame.Angles(a, 0, 0)
		out.spokes[#out.spokes + 1] = { part = sp, base = a }
	end
	return out
end

-- ---------------------------------------------------------------------------
-- SCALING A MECHANISM
-- ---------------------------------------------------------------------------
-- ScaleTo() resizes every PART and pushes it outward from the model pivot -- but the frames a
-- linkage is animated against (a flywheel centre, a beam pivot, a turret origin) are plain
-- values captured while the model was still drawn at 1x. Left alone they would point at where
-- the machine used to be, and the moving half would detach from the still half at any block
-- size but the nominal one.
--
-- rescaler() returns the correction: it moves the named frames outward from the same pivot by
-- the same factor, scales the named lengths, and records the factor on the rig so the drive
-- loop can size its own literals. Per-part homes are read INSIDE the drive loop, which starts
-- after the scale, so those need no correction -- only these precomputed ones do.
local function rescaler(rig, frameKeys, lengthKeys)
	return function(pivot, S)
		local function fix(cf)
			return CFrame.new(pivot.Position + (cf.Position - pivot.Position) * S) * (cf - cf.Position)
		end
		for _, k in ipairs(frameKeys) do rig[k] = fix(rig[k]) end
		for _, k in ipairs(lengthKeys) do rig[k] = rig[k] * S end
		rig.s = S
	end
end

-- ---------------------------------------------------------------------------
-- THE SYRUP PUMP -- a beam engine, and it never stops running.
-- ---------------------------------------------------------------------------
-- A flywheel turns, a crank pin on its rim drives a connecting rod, the rod works a rocking
-- beam, the beam drives a piston in its cylinder, and syrup runs out of the spout. ONE clock
-- drives all of it -- parts of a machine that each keep their own time look like separate
-- props, not one mechanism.
--
-- The bodywork is built with the joint kit above rather than as hand-typed offsets: a riveted
-- frame with diagonal braces, pipework solved span by span with elbows and bolted flanges at
-- every seam, a banded and riveted tank. That is what stops it reading as stacked boxes --
-- not smoother shapes, but visible joinery.
local function buildSyrupPump(at)
	local m = Instance.new("Model"); m.Name = "SyrupPump"
	m:SetAttribute("QuestProp", true)

	local IRON, IRON_D, IRON_L = MECH.IRON, MECH.IRON_D, MECH.IRON_L
	local BRASS = MECH.BRASS

	-- ===== the bed and its frame =====
	local plinth = sceneryPart({ Size = Vector3.new(9, 1.0, 7.4), Color = Color3.fromRGB(120, 84, 52),
		Material = Enum.Material.WoodPlanks }, m)
	plinth.CFrame = at * CFrame.new(0, 0.5, 0)
	m.PrimaryPart = plinth
	local bedPlate = sceneryPart({ Size = Vector3.new(8.4, 0.35, 6.8), Color = IRON_D,
		Material = Enum.Material.DiamondPlate }, m)
	bedPlate.CFrame = at * CFrame.new(0, 1.15, 0)
	MECH.rivets(m, at * CFrame.new(0, 1.34, 0) * CFrame.Angles(0, 0, math.rad(90)), 3.1, 16)

	-- four feet, cross-braced. The braces are the difference between "four legs" and "a frame":
	-- the eye reads triangles as structure and parallel posts as decoration.
	local footPts = {}
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = at * CFrame.new(sx * 3.6, 0.3, sz * 2.9)
			local foot = sceneryPart({ Size = Vector3.new(1.2, 0.6, 1.2), Color = IRON_D,
				Material = Enum.Material.Metal }, m)
			foot.CFrame = p
			footPts[#footPts + 1] = p.Position
		end
	end
	MECH.strut(m, footPts[1], footPts[4], 0.28, IRON_D)
	MECH.strut(m, footPts[2], footPts[3], 0.28, IRON_D)

	-- ===== the tank: hooped, riveted, strapped, with a bolted lid =====
	local tankCentre = at * CFrame.new(-1.4, 4.6, 0)
	local tank = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(6.6, 5.2, 5.2),
		Color = Color3.fromRGB(226, 236, 244), Material = Enum.Material.Glass,
		Transparency = 0.55, Reflectance = 0.15 }, m)
	tank.CFrame = tankCentre * CFrame.Angles(0, 0, math.rad(90))
	local level = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(4.5, 4.7, 4.7),
		Color = SYRUP, Reflectance = 0.25 }, m)
	level.CanCollide = false
	level.CFrame = at * CFrame.new(-1.4, 3.8, 0) * CFrame.Angles(0, 0, math.rad(90))
	for _, y in ipairs({ 1.9, 7.3 }) do
		local hoopCF = at * CFrame.new(-1.4, y, 0) * CFrame.Angles(0, 0, math.rad(90))
		local band = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.55, 5.5, 5.5),
			Color = IRON, Material = Enum.Material.Metal }, m)
		band.CFrame = hoopCF
		MECH.rivets(m, hoopCF, 2.72, 14)
	end
	for i = 1, 4 do            -- uprights strapping the two hoops together
		local a = i * (math.pi / 2) + math.pi / 4
		local top = (at * CFrame.new(-1.4, 7.3, 0)).Position + Vector3.new(math.cos(a) * 2.7, 0, math.sin(a) * 2.7)
		local bot = (at * CFrame.new(-1.4, 1.9, 0)).Position + Vector3.new(math.cos(a) * 2.7, 0, math.sin(a) * 2.7)
		MECH.strut(m, bot, top, 0.26, IRON)
	end
	local lidCF = at * CFrame.new(-1.4, 7.75, 0) * CFrame.Angles(0, 0, math.rad(90))
	local lid = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 5.8, 5.8),
		Color = IRON, Material = Enum.Material.Metal }, m)
	lid.CFrame = lidCF
	MECH.bolts(m, lidCF * CFrame.new(0.4, 0, 0), 2.5, 10, BRASS)
	MECH.taper(m, (at * CFrame.new(-1.4, 8.05, 0)).Position, (at * CFrame.new(-1.4, 9.4, 0)).Position,
		1.0, 0.5, 5, IRON, Enum.Material.Metal)

	-- ===== the flywheel, on a braced bearing housing =====
	local WHEEL_R = 2.2
	local wheelCentre = at * CFrame.new(3.4, 3.4, 1.7)
	local bearing = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 1.5, 1.5),
		Color = IRON_L, Material = Enum.Material.Metal }, m)
	bearing.CFrame = wheelCentre
	MECH.strut(m, (at * CFrame.new(3.4, 1.3, 1.7)).Position, wheelCentre.Position, 0.55, IRON)
	MECH.strut(m, (at * CFrame.new(2.2, 1.3, 1.7)).Position, wheelCentre.Position, 0.3, IRON_D)
	MECH.strut(m, (at * CFrame.new(4.6, 1.3, 1.7)).Position, wheelCentre.Position, 0.3, IRON_D)

	local wheel = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.55, WHEEL_R * 2, WHEEL_R * 2),
		Color = IRON_D, Material = Enum.Material.Metal }, m)
	wheel.CFrame = wheelCentre
	local rim = sceneryPart({ Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, WHEEL_R * 1.82, WHEEL_R * 1.82), Color = BRASS,
		Material = Enum.Material.Metal }, m)
	rim.CanCollide = false; rim.CFrame = wheelCentre
	local spokes = {}
	for i = 1, 6 do
		local base = i * (math.pi / 3)
		local sp = sceneryPart({ Size = Vector3.new(0.62, 0.26, WHEEL_R * 1.74), Color = IRON,
			Material = Enum.Material.Metal }, m)
		sp.CanCollide = false
		sp.CFrame = wheelCentre * CFrame.Angles(base, 0, 0)
		spokes[#spokes + 1] = { part = sp, base = base }
	end
	local crankPin = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 0.62, 0.62),
		Color = BRASS, Material = Enum.Material.Metal }, m)
	crankPin.CanCollide = false
	local rod = sceneryPart({ Size = Vector3.new(0.42, 4.6, 0.42), Color = BRASS,
		Material = Enum.Material.Metal }, m)
	rod.CanCollide = false

	-- ===== the A-frame carrying the beam, and its trunnion =====
	local beamPivot = at * CFrame.new(1.0, 8.6, 1.7)
	local apex = beamPivot.Position
	for _, sx in ipairs({ -1, 1 }) do
		MECH.strut(m, (at * CFrame.new(1.0 + sx * 1.9, 1.3, 1.7)).Position, apex, 0.5, IRON)
	end
	MECH.strut(m, (at * CFrame.new(1.0, 1.3, 3.1)).Position, apex, 0.36, IRON_D)
	local trunnion = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.9, 1.1, 1.1),
		Color = IRON_L, Material = Enum.Material.Metal }, m)
	trunnion.CFrame = beamPivot
	MECH.bolts(m, beamPivot * CFrame.new(1.0, 0, 0), 0.42, 6, BRASS)

	local beam = sceneryPart({ Size = Vector3.new(6.6, 0.62, 0.8), Color = Color3.fromRGB(178, 126, 78),
		Material = Enum.Material.Wood }, m)
	beam.CFrame = at * CFrame.new(1.0, 8.6, 1.7)
	for _, sx in ipairs({ -1, 1 }) do    -- iron straps: how a wooden beam engine was really made
		local strap = sceneryPart({ Size = Vector3.new(0.5, 0.72, 0.9), Color = IRON,
			Material = Enum.Material.Metal }, m)
		strap.CanCollide = false
		strap.CFrame = beam.CFrame * CFrame.new(sx * 2.4, 0, 0)
	end
	local beamKnob = sceneryPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(1.15, 1.15, 1.15),
		Color = Color3.fromRGB(226, 64, 58), Material = Enum.Material.Metal }, m)
	beamKnob.CanCollide = false
	beamKnob.CFrame = at * CFrame.new(-2.3, 8.6, 1.7)

	-- ===== the cylinder the piston works in =====
	local cylCF = at * CFrame.new(-2.3, 6.4, 1.7) * CFrame.Angles(0, 0, math.rad(90))
	local cylinder = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.6, 1.9, 1.9),
		Color = IRON, Material = Enum.Material.Metal }, m)
	cylinder.CFrame = cylCF
	MECH.flange(m, cylCF * CFrame.new(1.85, 0, 0), 1.2, IRON_L)
	MECH.flange(m, cylCF * CFrame.new(-1.85, 0, 0), 1.2, IRON_L)
	MECH.strut(m, (at * CFrame.new(-2.3, 4.6, 1.7)).Position, (at * CFrame.new(-2.3, 1.3, 1.7)).Position, 0.5, IRON)
	local piston = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 0.66, 0.66),
		Color = BRASS, Material = Enum.Material.Metal }, m)
	piston.CanCollide = false
	piston.CFrame = at * CFrame.new(-2.3, 7.8, 1.7) * CFrame.Angles(0, 0, math.rad(90))

	-- ===== the outlet, solved joint to joint =====
	-- Each run is a SPAN between two known points, so a pipe cannot end an inch short of the
	-- thing it feeds, and every seam carries a bolted flange instead of showing a crack.
	local tapPt   = (at * CFrame.new(-3.9, 3.6, 0)).Position
	local elbowPt = (at * CFrame.new(-6.2, 3.6, 0)).Position
	local spoutPt = (at * CFrame.new(-6.2, 1.6, 0)).Position
	MECH.pipe(m, (at * CFrame.new(-1.4, 3.6, 0)).Position, tapPt, 0.42, IRON, { flanges = true })
	MECH.pipe(m, tapPt, elbowPt, 0.42, IRON)
	MECH.pipe(m, elbowPt, spoutPt, 0.42, IRON, { flanges = true })
	local cockCF = CFrame.lookAt((tapPt + elbowPt) * 0.5, elbowPt) * CFrame.Angles(0, math.rad(90), 0)
	local cock = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 1.1, 1.1),
		Color = BRASS, Material = Enum.Material.Metal }, m)
	cock.CFrame = cockCF
	local cockHandle = sceneryPart({ Size = Vector3.new(0.18, 1.5, 0.18),
		Color = Color3.fromRGB(226, 64, 58), Material = Enum.Material.Metal }, m)
	cockHandle.CanCollide = false
	cockHandle.CFrame = cockCF * CFrame.new(0, 0.9, 0)

	local spout = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.0, 1.25, 1.25),
		Color = IRON_D, Material = Enum.Material.Metal }, m)
	spout.CFrame = at * CFrame.new(-6.2, 1.25, 0) * CFrame.Angles(0, 0, math.rad(90))
	MECH.taper(m, (at * CFrame.new(-6.2, 1.5, 0)).Position, (at * CFrame.new(-6.2, 0.85, 0)).Position,
		0.62, 0.42, 4, IRON_D, Enum.Material.Metal)

	-- THE STREAM is a real part, not a particle: a column from the spout to the puddle whose
	-- thickness pulses on each stroke. Particles alone read as a leak; a column reads as a pump
	-- that is moving something.
	local stream = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 0.5, 0.5),
		Color = SYRUP, Reflectance = 0.3, Transparency = 0.05 }, m)
	stream.CanCollide = false; stream.CanQuery = false
	stream.CFrame = at * CFrame.new(-6.2, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90))

	local puddle = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 4.2, 4.2),
		Color = SYRUP, Transparency = 0.1, Reflectance = 0.3 }, m)
	puddle.CanCollide = false; puddle.CanQuery = false
	puddle.CFrame = at * CFrame.new(-6.2, 0.12, 0) * CFrame.Angles(0, 0, math.rad(90))
	for i = -2, 2 do        -- a grate under it, so the puddle reads as drainage not a spill
		local bar = sceneryPart({ Size = Vector3.new(0.16, 0.12, 5.0), Color = IRON_D,
			Material = Enum.Material.Metal }, m)
		bar.CanCollide = false
		bar.CFrame = at * CFrame.new(-6.2 + i * 0.75, 0.06, 0)
	end

	local splashAtt = Instance.new("Attachment"); splashAtt.Position = Vector3.new(0, 0.2, 0)
	splashAtt.Parent = puddle
	local splash = Instance.new("ParticleEmitter")
	splash.Color = ColorSequence.new(SYRUP); splash.Size = NumberSequence.new(0.35)
	splash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	splash.Lifetime = NumberRange.new(0.3, 0.55); splash.Rate = 14
	splash.Speed = NumberRange.new(2, 5); splash.SpreadAngle = Vector2.new(55, 55)
	splash.Acceleration = Vector3.new(0, -40, 0)   -- gravity, not a dimension: never scaled
	splash.Parent = splashAtt

	-- ===== the relief valve, plumbed to the tank rather than stuck on it =====
	local valveBase = (at * CFrame.new(-1.4, 8.05, 1.0)).Position
	local valveTop  = (at * CFrame.new(-1.4, 9.0, 1.0)).Position
	MECH.pipe(m, valveBase, valveTop, 0.3, BRASS)
	local valve = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 0.95, 0.95),
		Color = BRASS, Material = Enum.Material.Metal }, m)
	valve.CFrame = CFrame.new(valveTop) * CFrame.Angles(0, 0, math.rad(90))
	local ventAtt = Instance.new("Attachment"); ventAtt.Position = Vector3.new(0.7, 0, 0); ventAtt.Parent = valve
	local vent = Instance.new("ParticleEmitter")
	vent.Color = ColorSequence.new(Color3.fromRGB(250, 246, 238))
	vent.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.2) })
	vent.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	vent.Lifetime = NumberRange.new(0.5, 0.9); vent.Rate = 0; vent.Speed = NumberRange.new(9, 14)
	vent.SpreadAngle = Vector2.new(14, 14); vent.Parent = ventAtt

	-- ===== the gauge, on a bracket piped off the tank =====
	local gaugeCF = at * CFrame.new(-1.4, 6.1, -3.0) * CFrame.Angles(math.rad(90), 0, math.rad(90))
	MECH.pipe(m, (at * CFrame.new(-1.4, 6.1, -2.0)).Position, (at * CFrame.new(-1.4, 6.1, -2.75)).Position,
		0.22, BRASS)
	local gaugeRing = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 2.9, 2.9),
		Color = BRASS, Material = Enum.Material.Metal }, m)
	gaugeRing.CanCollide = false; gaugeRing.CFrame = gaugeCF * CFrame.new(-0.12, 0, 0)
	local gauge = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2.4, 2.4),
		Color = Color3.fromRGB(250, 246, 232) }, m)
	gauge.CFrame = gaugeCF
	MECH.bolts(m, gaugeCF * CFrame.new(0.2, 0, 0), 1.28, 8, MECH.BRASS_D)
	for i = 1, 8 do        -- dial ticks, so the needle has something to point AT
		local a = (i / 8) * math.pi * 1.5 - 0.75
		local tick = sceneryPart({ Size = Vector3.new(0.08, 0.3, 0.08), Color = TEXTC }, m)
		tick.CanCollide = false
		tick.CFrame = gaugeCF * CFrame.new(0.22, math.cos(a) * 0.95, math.sin(a) * 0.95)
	end
	local needle = sceneryPart({ Size = Vector3.new(0.12, 0.95, 0.12), Color = Color3.fromRGB(226, 64, 58) }, m)
	needle.CanCollide = false
	needle.CFrame = gaugeCF * CFrame.new(0.3, 0, 0)

	signOn(m, at * CFrame.new(0, 2.0, 3.9), "SYRUP PUMP")
	MECH.lowPoly(m)                  -- flat faces, clean colour blocks: the shape does the work
	m.Parent = sceneryFolder

	local rig = {
		kind = "pump", s = 1,
		wheelCentre = wheelCentre, wheelR = WHEEL_R,
		wheel = wheel, rim = rim, spokes = spokes, crankPin = crankPin, rod = rod,
		beam = beam, beamKnob = beamKnob, beamPivot = beamPivot,
		piston = piston, level = level, stream = stream, puddle = puddle,
		needle = needle, vent = vent, splash = splash,
	}
	rig.rescale = rescaler(rig, { "wheelCentre", "beamPivot" }, { "wheelR" })
	return m, rig
end

-- ---------------------------------------------------------------------------
-- THE BUTTER LAUNCHER -- a field gun. Traverses, winds up, FIRES, every 20s.
-- ---------------------------------------------------------------------------
-- Built as a carriage, a turntable and a gun rather than as a tube on a box: spoked wheels
-- with iron tyres, a trail with a spade, a bolted turntable ring, trunnions the barrel really
-- pivots on, reinforcing bands that thin toward the muzzle, and a flared bell.
--
-- Everything above the turntable is rebuilt from one frame each tick, which is why `decor`
-- exists: the trunnions, cheeks, bands and hopper braces all have to swing with the barrel, so
-- they are stored as offsets rather than placed once. Anything placed once would stay pointing
-- where the gun used to aim.
local function buildButterLauncher(at)
	local m = Instance.new("Model"); m.Name = "ButterLauncher"
	m:SetAttribute("QuestProp", true)

	local IRON, IRON_D, IRON_L = MECH.IRON, MECH.IRON_D, MECH.IRON_L
	local BRASS = MECH.BRASS

	-- ===== the carriage =====
	local bed = sceneryPart({ Size = Vector3.new(7.4, 0.9, 4.8), Color = Color3.fromRGB(120, 84, 52),
		Material = Enum.Material.WoodPlanks }, m)
	bed.CFrame = at * CFrame.new(0, 1.6, 0)
	m.PrimaryPart = bed
	local bedIron = sceneryPart({ Size = Vector3.new(7.6, 0.25, 5.0), Color = IRON_D,
		Material = Enum.Material.DiamondPlate }, m)
	bedIron.CanCollide = false
	bedIron.CFrame = at * CFrame.new(0, 2.1, 0)

	-- the trail: the tail with a spade that digs in when the gun fires
	MECH.strut(m, (at * CFrame.new(0, 1.6, 2.2)).Position, (at * CFrame.new(0, 0.9, 7.4)).Position, 0.85,
		Color3.fromRGB(120, 84, 52))
	local spade = sceneryPart({ Size = Vector3.new(2.0, 1.4, 0.4), Color = IRON,
		Material = Enum.Material.Metal }, m)
	spade.CFrame = at * CFrame.new(0, 0.7, 7.6) * CFrame.Angles(math.rad(24), 0, 0)
	MECH.strut(m, (at * CFrame.new(-1.2, 1.5, 4.4)).Position, (at * CFrame.new(1.2, 1.5, 6.2)).Position, 0.24, IRON_D)
	MECH.strut(m, (at * CFrame.new(1.2, 1.5, 4.4)).Position, (at * CFrame.new(-1.2, 1.5, 6.2)).Position, 0.24, IRON_D)

	for _, sx in ipairs({ -1, 1 }) do
		MECH.wheel(m, at * CFrame.new(sx * 3.5, 1.7, 0), 1.75, 0.55)
		MECH.pipe(m, (at * CFrame.new(sx * 2.6, 1.7, 0)).Position, (at * CFrame.new(sx * 3.8, 1.7, 0)).Position,
			0.26, IRON_L, { noElbows = true })
	end

	-- ===== the turntable =====
	local ringCF = at * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.rad(90))
	local ring = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.45, 4.2, 4.2),
		Color = IRON_L, Material = Enum.Material.Metal }, m)
	ring.CFrame = ringCF
	MECH.bolts(m, ringCF * CFrame.new(0.3, 0, 0), 1.75, 12, BRASS)
	local pintle = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, 1.5, 1.5),
		Color = IRON_D, Material = Enum.Material.Metal }, m)
	pintle.CFrame = at * CFrame.new(0, 3.0, 0) * CFrame.Angles(0, 0, math.rad(90))

	local BARREL_TILT = math.rad(34)
	local turretHome = at * CFrame.new(0, 3.6, 0)

	-- ===== everything above the turntable, stored as offsets =====
	local decor = {}
	local function turretPart(props, off, along)
		local p = sceneryPart(props, m)
		p.CanCollide = false
		decor[#decor + 1] = { part = p, off = off, along = along }
		return p
	end

	local barrel = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(7.0, 2.5, 2.5),
		Color = IRON, Material = Enum.Material.Metal }, m)
	local muzzle = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 3.2, 3.2),
		Color = IRON_D, Material = Enum.Material.Metal }, m)
	local breech = sceneryPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(3.2, 3.2, 3.2),
		Color = IRON, Material = Enum.Material.Metal }, m)
	local sight = sceneryPart({ Size = Vector3.new(0.28, 1.3, 0.28), Color = BRASS,
		Material = Enum.Material.Metal }, m)
	sight.CanCollide = false
	local hopper = sceneryPart({ Size = Vector3.new(3.4, 2.7, 3.4), Color = Color3.fromRGB(178, 126, 78),
		Material = Enum.Material.WoodPlanks }, m)

	-- reinforcing bands ALONG the barrel, thinning toward the muzzle. `along` is a distance in
	-- barrel-space that poseTurret converts each frame -- a real gun is not a tube of constant
	-- thickness, and the taper is what says so at a glance.
	for i = 1, 4 do
		local r = 1.58 - (i - 1) * 0.10
		turretPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.42, r * 2, r * 2),
			Color = IRON_L, Material = Enum.Material.Metal }, nil, -2.4 + (i - 1) * 1.6)
	end
	-- a bolt ring on the breech band, and the trunnions the barrel pivots on
	for _, sx in ipairs({ -1, 1 }) do
		turretPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.3, 0.9, 0.9),
			Color = IRON_L, Material = Enum.Material.Metal }, CFrame.new(sx * 1.9, 0, -0.4))
		turretPart({ Size = Vector3.new(0.55, 3.2, 1.6), Color = IRON, Material = Enum.Material.Metal },
			CFrame.new(sx * 2.2, -1.2, -0.4))
	end
	-- the elevating screw under the breech, and the hopper's braces
	turretPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 0.5, 0.5), Color = BRASS,
		Material = Enum.Material.Metal }, CFrame.new(0, -1.5, 2.2) * CFrame.Angles(0, 0, math.rad(90)))
	for _, sx in ipairs({ -1, 1 }) do
		turretPart({ Size = Vector3.new(0.26, 2.2, 0.26), Color = IRON_D, Material = Enum.Material.Metal },
			CFrame.new(sx * 1.5, 1.2, 2.0))
	end

	local pats = {}
	for i = 1, 4 do
		local pat = sceneryPart({ Size = Vector3.new(1.15, 0.62, 0.95), Color = BUTTER }, m)
		pat.CanCollide = false
		pats[#pats + 1] = pat
	end

	-- ===== the crank, on the carriage so it does not swing with the gun =====
	local crank = sceneryPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.55, 2.1, 2.1),
		Color = IRON, Material = Enum.Material.Metal }, m)
	crank.CFrame = at * CFrame.new(3.5, 3.3, 1.4)
	MECH.strut(m, (at * CFrame.new(2.6, 2.2, 1.4)).Position, (at * CFrame.new(3.5, 3.3, 1.4)).Position, 0.34, IRON)
	local crankArm = sceneryPart({ Size = Vector3.new(0.38, 1.7, 0.38), Color = Color3.fromRGB(226, 64, 58),
		Material = Enum.Material.Metal }, m)
	crankArm.CanCollide = false
	crankArm.CFrame = crank.CFrame * CFrame.new(0.5, 0, 0)

	-- a status lamp on a bracket: green idling, blinking red on the wind-up
	MECH.pipe(m, (at * CFrame.new(-2.6, 2.2, 1.5)).Position, (at * CFrame.new(-3.4, 3.4, 1.5)).Position, 0.16, IRON_D)
	local lamp = sceneryPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.95, 0.95, 0.95),
		Color = Color3.fromRGB(90, 220, 110), Material = Enum.Material.Neon }, m)
	lamp.CanCollide = false
	lamp.CFrame = at * CFrame.new(-3.4, 3.6, 1.5)
	local lampLight = Instance.new("PointLight")
	lampLight.Color = lamp.Color; lampLight.Brightness = 2; lampLight.Range = 10; lampLight.Parent = lamp

	-- an ammo crate with the lid thrown open, strapped and stacked
	local crate = sceneryPart({ Size = Vector3.new(2.8, 2.3, 2.8), Color = Color3.fromRGB(150, 106, 62),
		Material = Enum.Material.WoodPlanks }, m)
	crate.CFrame = at * CFrame.new(-3.9, 1.15, -2.4)
	local crateLid = sceneryPart({ Size = Vector3.new(2.8, 0.25, 2.8), Color = Color3.fromRGB(128, 88, 50),
		Material = Enum.Material.WoodPlanks }, m)
	crateLid.CanCollide = false
	crateLid.CFrame = crate.CFrame * CFrame.new(0, 1.15, -1.3) * CFrame.Angles(math.rad(-72), 0, 0)
	for _, y in ipairs({ -0.6, 0.6 }) do
		local strap = sceneryPart({ Size = Vector3.new(2.95, 0.2, 2.95), Color = IRON_D,
			Material = Enum.Material.Metal }, m)
		strap.CanCollide = false
		strap.CFrame = crate.CFrame * CFrame.new(0, y, 0)
	end
	for i = 1, 3 do
		local spare = sceneryPart({ Size = Vector3.new(1.2, 0.7, 1.0), Color = BUTTER }, m)
		spare.CanCollide = false
		spare.CFrame = crate.CFrame * CFrame.new((i - 2) * 0.75, 1.35, 0) * CFrame.Angles(0, i * 0.5, 0)
	end

	signOn(m, at * CFrame.new(0, 1.3, -3.6), "BUTTER LAUNCHER")
	MECH.lowPoly(m)                  -- same finish as the pump: the two are one set of machinery
	m.Parent = sceneryFolder

	local rig = {
		kind = "launcher", s = 1,
		turretHome = turretHome, tilt = BARREL_TILT,
		barrel = barrel, muzzle = muzzle, breech = breech, sight = sight,
		hopper = hopper, pats = pats, decor = decor,
		crank = crank, crankArm = crankArm, lamp = lamp, lampLight = lampLight,
	}
	rig.rescale = rescaler(rig, { "turretHome" }, {})
	return m, rig
end

-- ---------------------------------------------------------------------------
-- THE DRIVE LOOPS. Anchored parts re-CFramed on a timer -- the same rule as
-- everything else in this file: nothing here is ever simulated by physics.
-- ---------------------------------------------------------------------------
local LAUNCH_EVERY = 20        -- seconds between shots
local WINDUP       = 3         -- seconds of lamp-blinking warning before each one

-- a butter pat on a real ballistic arc: launched with a velocity, pulled down by gravity, and
-- landed where the ground actually is rather than at a guessed distance. Splats on arrival.
local function flingButter(fromPos, dir, speed, sc)
	local pat = sceneryPart({ Size = Vector3.new(1.6, 0.9, 1.2) * sc, Color = BUTTER }, sceneryFolder)
	pat.CanCollide = false
	pat.CanQuery = false           -- a pat in mid-air can never block a placement query
	pat.CFrame = CFrame.new(fromPos)

	local trailAtt = Instance.new("Attachment"); trailAtt.Parent = pat
	local trail = Instance.new("ParticleEmitter")
	trail.Color = ColorSequence.new(BUTTER); trail.Size = NumberSequence.new(0.5 * sc)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = NumberRange.new(0.3, 0.5); trail.Rate = 26; trail.Speed = NumberRange.new(0, 1)
	trail.Parent = trailAtt

	task.spawn(function()
		local vel = dir * speed + Vector3.new(0, 26, 0)
		local pos = fromPos
		local spin = CFrame.new()
		local t = 0
		while t < 6 and pat.Parent do
			local dt = task.wait(0.03)
			t += dt
			vel = vel - Vector3.new(0, 60 * dt, 0)     -- gravity
			local nextPos = pos + vel * dt
			local gy = groundY(nextPos)
			if nextPos.Y <= gy + 0.5 then
				-- ===== SPLAT =====
				local landing = Vector3.new(nextPos.X, gy + 0.12, nextPos.Z)
				pat:Destroy()
				poofAt(landing + Vector3.new(0, 0.6, 0), BUTTER, 12)
				local splat = sceneryPart({ Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.22, 1.5, 1.5), Color = BUTTER, Transparency = 0.05 }, sceneryFolder)
				splat.CanCollide = false; splat.CanQuery = false
				splat.CFrame = CFrame.new(landing) * CFrame.Angles(0, 0, math.rad(90))
				tween(splat, 0.35, { Size = Vector3.new(0.22, 6.5, 6.5) }, Enum.EasingStyle.Back)
				tween(splat, 9, { Transparency = 1 }, Enum.EasingStyle.Linear)
				Debris:AddItem(splat, 9.2)
				local hrp = hrpOf()
				if hrp and (hrp.Position - landing).Magnitude < 26 then shakeCamera(0.6, 0.25) end
				return
			end
			spin = spin * CFrame.Angles(0.22, 0.13, 0.07)
			pos = nextPos
			pat.CFrame = CFrame.new(pos) * spin
		end
		if pat.Parent then pat:Destroy() end
	end)
end

local function animateScenery(rig)
	task.spawn(function()
		local sc = rig.s or 1

		if rig.kind == "pump" then
			-- ===== ALWAYS RUNNING =====
			-- One phase clock. `ang` is the flywheel's angle and every other moving part is a
			-- function of it -- that is what makes this read as one mechanism instead of a pile
			-- of props each wobbling to its own beat.
			local ang = 0
			local RPM = 1.9                          -- radians/sec: a steady working chug
			local strokes, lastRev = 0, -1
			local levelHome  = rig.level.CFrame
			local needleHome = rig.needle.CFrame
			local puddleX    = rig.puddle.Size.X
			local beamHome   = rig.beam.CFrame
			local knobHome   = rig.beamKnob.CFrame
			local pistonHome = rig.piston.CFrame
			local streamHome = rig.stream.CFrame

			while rig.wheel.Parent do
				local dt = task.wait(0.03)
				ang += RPM * dt
				local stroke = math.sin(ang)         -- +1 top, -1 bottom

				-- flywheel and spokes
				rig.wheel.CFrame = rig.wheelCentre * CFrame.Angles(ang, 0, 0)
				rig.rim.CFrame = rig.wheel.CFrame
				for _, sp in ipairs(rig.spokes) do
					sp.part.CFrame = rig.wheelCentre * CFrame.Angles(ang + sp.base, 0, 0)
				end

				-- The crank pin rides the rim; the rod spans pin to beam end. Both ends are
				-- KNOWN POINTS, so the rod is drawn by lookAt between them and stretched to fit.
				-- That is how you draw a linkage without hinges: solve the endpoints, then place
				-- the bar. Trying to rotate a fixed-length rod into place needs trigonometry that
				-- breaks the moment any offset changes.
				local pin = (rig.wheelCentre
					* CFrame.new(0, math.cos(ang) * rig.wheelR, math.sin(ang) * rig.wheelR)).Position
				rig.crankPin.CFrame = CFrame.new(pin) * CFrame.Angles(0, math.rad(90), 0)

				local tilt = stroke * 0.22
				local swing = rig.beamPivot * CFrame.Angles(0, 0, tilt)
				rig.beam.CFrame = swing * rig.beamPivot:ToObjectSpace(beamHome)
				rig.beamKnob.CFrame = swing * rig.beamPivot:ToObjectSpace(knobHome)

				local beamEnd = rig.beamKnob.Position
				local span = beamEnd - pin
				if span.Magnitude > 0.05 then
					rig.rod.Size = Vector3.new(0.45 * sc, span.Magnitude, 0.45 * sc)
					rig.rod.CFrame = CFrame.lookAt(pin + span * 0.5, beamEnd) * CFrame.Angles(math.rad(90), 0, 0)
				end

				-- the piston follows the beam's stroke
				rig.piston.CFrame = pistonHome * CFrame.new(0, 0, -stroke * 0.75 * sc)

				-- the stream thickens on the down-stroke -- that is when it is pushing
				local push = math.max(0, -stroke)
				local thick = (0.28 + push * 0.5) * sc
				rig.stream.Size = Vector3.new(1.1 * sc, thick, thick)
				rig.stream.CFrame = streamHome
				rig.splash.Rate = 6 + push * 26

				-- tank level and gauge both breathe with the stroke
				rig.level.CFrame = levelHome * CFrame.new(0, 0, stroke * 0.12 * sc)
				rig.needle.CFrame = needleHome * CFrame.Angles(0.7 + stroke * 0.75, 0, 0)

				-- the puddle swells while it runs, and never past a puddle-sized puddle
				local grow = (4.2 + math.sin(ang * 0.5) * 0.5) * sc
				rig.puddle.Size = Vector3.new(puddleX, grow, grow)

				-- VENT ON EVERY FOURTH REVOLUTION. Counted off the wheel's own turns rather than
				-- a separate timer, or the puff drifts out of step with the machine it comes from.
				local rev = math.floor(ang / (math.pi * 2))
				if rev ~= lastRev then
					lastRev = rev
					strokes += 1
					if strokes % 4 == 0 then
						rig.vent.Rate = 90
						task.delay(0.35, function() if rig.vent.Parent then rig.vent.Rate = 0 end end)
					end
				end
			end

		elseif rig.kind == "launcher" then
			-- ===== ONE SHOT EVERY LAUNCH_EVERY SECONDS =====
			local bearing, wantBearing = 0.6, 0.6
			local recoil = 0
			local crankSpin, crankRate = 0, 1.2
			local crankHome, armHome = rig.crank.CFrame, rig.crankArm.CFrame
			local nextShot = os.clock() + 8          -- a beat after spawning, not instantly
			local armed = false

			-- THE WHOLE TURRET IS REBUILT FROM ONE FRAME every tick. Barrel, muzzle, breech,
			-- sight and hopper are all offsets against `turret`, so a traverse swings the gun as
			-- one piece. Rotating the barrel alone -- the obvious version -- leaves the breech
			-- and the hopper behind, pointing the wrong way.
			local function poseTurret()
				local turret = rig.turretHome * CFrame.Angles(0, bearing, 0)
				local barrelCF = turret * CFrame.new(0, 0, (-0.6 + recoil) * sc) * CFrame.Angles(rig.tilt, 0, 0)
				-- a Cylinder's length is its local X, so the barrel is yawed onto the frame's
				-- LookVector; every offset after this is then simply "along the barrel".
				local BX = barrelCF * CFrame.Angles(0, math.rad(90), 0)
				rig.barrel.CFrame = BX
				rig.muzzle.CFrame = BX * CFrame.new(3.6 * sc, 0, 0)
				rig.breech.CFrame = BX * CFrame.new(-3.3 * sc, 0, 0)
				rig.sight.CFrame  = BX * CFrame.new(1.6 * sc, 0, 1.5 * sc)
				rig.hopper.CFrame = turret * CFrame.new(0, 2.2 * sc, 1.9 * sc)
				-- the bodywork bolted to the gun -- bands, trunnions, cheeks, braces. Anything
				-- placed once instead of posed here would stay pointing where the gun used to aim.
				for _, d in ipairs(rig.decor or {}) do
					if d.part.Parent then
						if d.along then
							d.part.CFrame = BX * CFrame.new(d.along * sc, 0, 0)   -- rides the barrel
						else
							d.part.CFrame = BX * d.off                             -- bolted to it
						end
					end
				end
				for i, pat in ipairs(rig.pats) do
					pat.CFrame = rig.hopper.CFrame
						* CFrame.new(((i % 2) - 0.5) * 1.0 * sc, 1.2 * sc, ((i > 2) and 0.6 or -0.6) * sc)
						* CFrame.Angles(0, i * 0.6, 0)
				end
				return barrelCF
			end
			local barrelCF = poseTurret()

			while rig.barrel.Parent do
				local dt = task.wait(0.03)
				local now = os.clock()
				local untilShot = nextShot - now

				if untilShot <= WINDUP and untilShot > 0 then
					-- WIND-UP: the lamp blinks red and the crank races, so the shot is
					-- telegraphed instead of arriving out of nowhere. The traverse happens here
					-- too, so you can see where it is about to fire.
					armed = true
					crankRate = 1.2 + (WINDUP - untilShot) * 5
					local blink = math.sin(untilShot * 22) > 0
					rig.lamp.Color = blink and Color3.fromRGB(255, 80, 60) or Color3.fromRGB(120, 40, 30)
					rig.lampLight.Color = rig.lamp.Color
					rig.lampLight.Brightness = blink and 5 or 1
					bearing += (wantBearing - bearing) * math.min(1, dt * 2.2)
				else
					crankRate = 1.2
					rig.lamp.Color = Color3.fromRGB(90, 220, 110)
					rig.lampLight.Color = rig.lamp.Color; rig.lampLight.Brightness = 2
				end

				if untilShot <= 0 and armed then
					armed = false
					nextShot = now + LAUNCH_EVERY
					-- ===== FIRE =====
					recoil = 1.8
					local dir = barrelCF.LookVector
					poofAt(rig.muzzle.Position + dir * 1.5, Color3.fromRGB(250, 246, 238), 14)
					poofAt(rig.muzzle.Position + dir * 3.0, BUTTER, 10)
					flingButter(rig.muzzle.Position + dir * 2, dir, 34, sc)
					local hrp = hrpOf()
					if hrp and (hrp.Position - rig.muzzle.Position).Magnitude < 60 then
						shakeCamera(1.1, 0.35)
					end
					-- aim somewhere else next time: a gun that always fires the same way is a
					-- prop, one that traverses is a machine doing a job.
					wantBearing = bearing + 1.1 + (now % 1.7)
				end

				if recoil > 0 then recoil = math.max(0, recoil - dt * 4.5) end

				crankSpin += crankRate * dt * 3.2
				rig.crankArm.CFrame = crankHome * CFrame.Angles(crankSpin, 0, 0)
					* crankHome:ToObjectSpace(armHome)

				barrelCF = poseTurret()
			end
		end
	end)
end

-- build whichever of the two markers exist. Scale comes from the BLOCK you drew: a wider
-- block makes a bigger machine, so the size is set in Studio and never in here.
buildScenery = function(isle)
	local wanted = { syruppump = buildSyrupPump, butterlauncher = buildButterLauncher }
	local built = {}
	-- findBlocks, not isle:GetDescendants(): a machine block left loose in Workspace beside the
	-- island is otherwise never found, and the log just says the machine is not built.
	local all = {}
	for key in pairs(wanted) do
		for _, d in ipairs(findBlocks(key)) do all[#all + 1] = d end
	end
	for _, d in ipairs(all) do
		local key = norm(d.Name)
		local make = wanted[key]
		if d:IsA("BasePart") and make and not built[key] then
			built[key] = true
			local at = baseFrameOf(d)
			local scale = math.max(0.35, math.min(d.Size.X, d.Size.Z) / SCENERY_BASE)
			hideMarker(d)
			local m, rig = make(at)
			-- grown about the ground line so the machine's feet stay planted, exactly the way
			-- the Bake-Off grows its stations. Then the LINKAGE FRAMES are corrected to match
			-- (see rescaler): ScaleTo moves parts but not the precomputed frames the drive loop
			-- animates against, and without this the moving half of the machine detaches from
			-- the still half at any block size but the nominal one. animateScenery runs last so
			-- its per-part homes are read from the finished, scaled machine.
			m.WorldPivot = at
			m:ScaleTo(scale)
			if rig.rescale then rig.rescale(at, scale) end
			animateScenery(rig)
			print(("[Pancake] built %s on '%s' (x%.2f from the block's %.0f x %.0f footprint)")
				:format(m.Name, d:GetFullName(), scale, d.Size.X, d.Size.Z))
		end
	end
	for key in pairs(wanted) do
		if not built[key] then
			print(("[Pancake] no '%s' block on island18 -- that machine is not built (it is scenery, "
				.. "nothing depends on it)"):format(key))
		end
	end
end
end   -- <- closes the scenery do-block above (the 200-register guard)

-- ============================================================================
-- GO -- the streaming-safe boot
-- ============================================================================
-- island18 is off the ladder and a long way from spawn, so its parts arrive late and only
-- when a player is near. Poll for the model rather than assuming it, and say so out loud if
-- it never comes: silence is the only symptom of an island that was never built, and a
-- missing island looks exactly like a broken script.
task.spawn(function()
	island = pollFor(function()
		for _, m in ipairs(Workspace:GetChildren()) do
			if m:IsA("Model") and norm(m.Name) == ISLAND_NAME then return m end
		end
		return nil
	end, 300)

	if not island then
		warn(("[Pancake] no Workspace model named '%s' after 5 minutes -- the Pancake Monster quest is "
			.. "INACTIVE. Build the island and name it '%s' (case/spaces/underscores are ignored).")
			:format(ISLAND_NAME, ISLAND_NAME))
		return
	end
	homeToIsland()

	-- the island's parts stream in after its model does; wait for a floor before placing anything
	pollFor(function() return island:FindFirstChildWhichIsA("BasePart", true) end, 120)
	findFloor(island)
	if not floorPart then
		warn("[Pancake] island18 has no BaseParts -- nothing to stand anything on, quest inactive")
		return
	end

	-- BEFORE ANYTHING IS PLACED: the boundary decides where props may go, and it is also
	-- excluded from the ground raycast, so finding it late would mean the arena and the
	-- bottles were already sited under the old rules.
	findBounds(island)
	if not boundPart then
		warn("[Pancake] no 'placement boundaires' part found on island18 -- falling back to a "
			.. "spiral around the arena clamped to the island's footprint")
	end

	-- THE ARENA. Your "PancakeArena" marker wins; the island's centre is the fallback, which is
	-- what "the arena in the centre" means when nobody has marked one.
	local arenaMarker = findBlocks(ARENA_NAME)[1]
	if arenaMarker then
		-- the arena is the one marker read from its TOP, not its base: the giant pancake is
		-- meant to sit ON the pad you drew, the way a plate sits on a table.
		local top = arenaMarker.Position.Y + arenaMarker.Size.Y * 0.5
		arenaCF = CFrame.new(arenaMarker.Position.X, top, arenaMarker.Position.Z)
		print("[Pancake] arena marker: " .. arenaMarker:GetFullName())
		hideMarker(arenaMarker)
	else
		local c = floorCF.Position
		local g = seatOn(c.X, c.Z, floorTopY or c.Y, 30)
		arenaCF = CFrame.new(g or Vector3.new(c.X, floorTopY or c.Y, c.Z))
		print("[Pancake] no 'PancakeArena' marker -- using the island's centre")
	end

	-- SCENERY BEFORE PLACEMENT. The machines are solid props that reject candidate spots, so
	-- they have to stand before a single syrup bottle is sited -- otherwise the bottles are
	-- placed on empty ground and a machine is built through one of them.
	buildScenery(island)

	buildPancake(arenaCF.Position)
	-- ...and the thing underneath it, asleep, from this moment on. Built AFTER the pancake so
	-- the stack is already sitting on top of it rather than dropping through it a frame later.
	spawnSleepingMonster()

	-- the pouring pads, ringed around the stack. The pancake itself carries no pour prompt any
	-- more -- the pads are where syrup goes, and one prompt on the stack competing with five on
	-- the pads would just mean the nearest one wins and the pads look decorative.
	buildPads()

	-- ===== YOUR FIVE "syrup" BLOCKS =====
	-- Read as placement blocks, exactly like the machines': the BASE is where the bottle
	-- stands (a bottle placed at the block's centre floats half a block up), the FOOTPRINT
	-- sets its size, and then the block is hidden. Every one you drew is used before a single
	-- spot is auto-picked -- a position you chose is never second-guessed or collision-tested.
	local syrupMarkers = {}
	for _, d in ipairs(findBlocks(SYRUP_NAME)) do
		syrupMarkers[#syrupMarkers + 1] = {
			pos = baseFrameOf(d).Position,
			scale = math.max(0.4, math.min(d.Size.X, d.Size.Z) / 4),   -- the bottle is ~4 wide
		}
		hideMarker(d)
	end
	if #syrupMarkers > 0 then
		print(("[Pancake] %d 'syrup' block(s) placed by hand -- %d more will be auto-placed")
			:format(#syrupMarkers, math.max(0, SYRUP_COUNT - #syrupMarkers)))
	end
	scatterSyrup(syrupMarkers)

	-- ===== THE QUEST GIVER =====
	-- The island's Candy Npc if there is one; the giant pancake itself if there is not, so a
	-- bare island still plays through instead of dead-ending on "go talk to the Candy NPC".
	--
	-- ⚠ THE NPC CAN ARRIVE AFTER THE ISLAND DOES. Its model is one more thing to replicate, and
	-- a single scan on the frame the island's first part shows up will miss it and fall back
	-- forever. So the pancake is wired IMMEDIATELY (the quest is playable the second you land)
	-- and a background scan keeps looking; the moment a real NPC turns up it takes over and the
	-- pancake's Talk prompt is switched off, so there are never two quest givers standing there.
	local function findNpc()
		for _, d in ipairs(island:GetDescendants()) do
			if d:IsA("Model") and string.find(norm(d.Name), "npc", 1, true) then
				local h = d:FindFirstChild("Head") or d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart", true)
				if h then return d, h end
			end
		end
		-- ...and a Candy Npc standing loose in Workspace beside the island, which is how one
		-- dragged into place without being re-parented ends up.
		local c = island:GetPivot().Position
		for _, d in ipairs(Workspace:GetChildren()) do
			if d:IsA("Model") and d ~= island and string.find(norm(d.Name), "npc", 1, true) then
				local h = d:FindFirstChild("Head") or d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart", true)
				if h and (Vector3.new(h.Position.X, 0, h.Position.Z)
					- Vector3.new(c.X, 0, c.Z)).Magnitude <= LOOSE_RADIUS then
					return d, h
				end
			end
		end
		return nil
	end

	local npcModel, foundHead = findNpc()
	if foundHead then
		npcHead = foundHead
		wireNPC(npcHead)
		print("[Pancake] quest giver: " .. npcModel:GetFullName())
	else
		local pancakePrompt = wireNPC(pancake)
		warn("[Pancake] no NPC on island18 yet -- the giant pancake is giving the quest for now")
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 120 do
				task.wait(2)
				local m, h = findNpc()
				if h then
					npcHead = h
					wireNPC(npcHead)
					if pancakePrompt then pancakePrompt.Enabled = false end
					print("[Pancake] Candy Npc arrived late -- quest giver handed over to " .. m:GetFullName())
					return
				end
			end
		end)
	end

	anchorAll()
	refreshBanner(); refreshPrompts()
	print(("[Pancake] ready on %s -- arena at (%.0f, %.0f, %.0f), %d syrup, %d butter to come")
		:format(island:GetFullName(), arenaCF.Position.X, arenaCF.Position.Y, arenaCF.Position.Z,
			SYRUP_COUNT, BUTTER_COUNT))
	-- RETAINER SIGNAL: the quest reached the end of its build with its world objects up. QuestRetainer
	-- watches this flag; anything still false once its island has streamed in gets force-streamed and
	-- re-run. It is set HERE, at the ready print, not at the top of the file -- a quest that bailed
	-- early on a missing marker must NOT look built. See QuestRetainer.client.luau.
	_G.questBuilt_pancake = true
end)

-- THE THROW PROMPT follows the monster: it only exists once the monster does, and it is the
-- monster's own body that carries it, so "get close and throw" means close to IT.
task.spawn(function()
	while true do
		task.wait(0.5)
		if monBody and monBody.Parent and not throwPrompt then
			monBody.CanQuery = true
			throwPrompt = Instance.new("ProximityPrompt")
			throwPrompt.ActionText = "THROW BUTTER"; throwPrompt.ObjectText = "Pancake Monster"
			throwPrompt.HoldDuration = 0; throwPrompt.MaxActivationDistance = THROW_RANGE
			throwPrompt.RequiresLineOfSight = false; throwPrompt.Enabled = false; throwPrompt.Parent = monBody
			throwPrompt.Triggered:Connect(throwButter)
			refreshPrompts()
		elseif throwPrompt and not (monBody and monBody.Parent) then
			throwPrompt = nil
		end
	end
end)

-- ============================================================================
-- TEST COMMANDS
--   /complete, /pancakewake -- wake the monster now and start the butter run
--   /pancakedone            -- melt it and pay out
-- All of them only work standing at the arena, so none can fire from another island.
-- ============================================================================
player.Chatted:Connect(function(msg)
	local text = tostring(msg or ""):lower()
	local hrp = hrpOf()
	if not (arenaCF and hrp) then return end
	if (hrp.Position - arenaCF.Position).Magnitude > 300 then return end
	-- "/complete" is the name every other island quest uses for its skip, so it is accepted
	-- here too. It wakes the monster rather than finishing the quest, because the monster IS
	-- the thing worth skipping to -- /pancakedone is there for the ending.
	if (text == "/pancakewake" or text == "/complete") and step < 3 then
		step = 3; poured = SYRUP_COUNT
		for _, rec in ipairs(syrups) do if rec.model.Parent then rec.model:Destroy() end end
		clearCarried(); carrying = nil
		refreshBanner(); refreshPrompts()
		print("[Pancake][TEST] " .. text .. " -- waking it now")
		task.spawn(wakeTheMonster)
	elseif text == "/pancakedone" and step < 6 then
		butterHeld = BUTTER_COUNT; butterStuck = BUTTER_COUNT
		print("[Pancake][TEST] /pancakedone -- melting it now")
		if monBody and monBody.Parent then meltMonster() else finishQuest() end
	end
end)

-- ============================================================================
-- SHARING THE MONSTER -- the network half (see MonsterSync.server.lua)
-- ============================================================================
-- Both halves live here because the monster this drives is this file's: the sender posts our
-- body's CFrame while WE own the hunt, and the receiver drives our body while somebody else
-- does. They are never both live -- REM.on decides which.
task.spawn(function()
	local ev = ReplicatedStorage:WaitForChild("MonsterSyncEvent", 30)
	if not ev then
		warn("[Pancake] no MonsterSyncEvent -- MonsterSync.server.lua is not running; the "
			.. "monster will only be visible to whoever woke it")
		return
	end
	REM.ev = ev

	ev.OnClientEvent:Connect(function(who, kind, id, cf, mode)
		-- OUR OWN MESSAGES COME BACK TO US and must be ignored: we are the client that computed
		-- that CFrame, and following it would be a feedback loop fighting our own state machine.
		if who == player then return end
		if id ~= "cake" then return end     -- the relay also carries island3's chocolate monster

		if kind == "melt" then
			-- only meaningful if we were watching THEIR monster; ours melting is our own business
			if not REM.on then return end
			REM.on, REM.cf = false, nil
			monState = "asleep"
			print("[Pancake] the shared hunt is over -- ours is local again")
			return
		end

		if kind ~= "mon" or typeof(cf) ~= "CFrame" then return end
		local now = os.clock()

		-- A HUNT OUTRANKS THE WANDER. Two different clients can legitimately be streaming at
		-- once: whoever is hosting the ambient stroll, and whoever just woke it and is being
		-- chased. The chase is the one that matters, so it claims the next three seconds and
		-- wander packets are dropped for that long -- otherwise the two would fight frame by
		-- frame and the monster would judder between two places.
		if mode == "hunt" then
			REM.huntUntil = now + 3
		elseif now < (REM.huntUntil or 0) then
			return
		end

		-- STICK WITH ONE HOST. Two kids can be chased at once -- each client streams its own
		-- hunt -- and a third watching would see it snap between the two of them twelve times
		-- a second. So the first host heard keeps it until it goes quiet for two seconds. The
		-- one exception is a hunt arriving while a WANDER host has it: being chased outranks
		-- wandering, so that one is allowed to take over immediately.
		local fresh = (now - REM.last) < 2
		if REM.host and REM.host ~= who and fresh
			and not (mode == "hunt" and REM.hostMode ~= "hunt") then
			return
		end
		REM.host, REM.hostMode = who, mode

		-- WE ONLY FOLLOW IF WE HAVE NOT WOKEN OUR OWN. Once this player pours their fifth syrup
		-- the monster is theirs, and another client's stream must not yank it off its target
		-- mid-chase. Asleep or wandering are the only states that can be taken over.
		if (monState == "asleep" or monState == "roam") and monster then
			monState = "remote"
			REM.on = true
			if monTag then monTag.Text = E.CAKE .. " Pancake Monster" end
			if monBody then monBody.Size = BODY_BASE end     -- the sleep breath scales it
			print("[Pancake] following " .. who.Name .. "'s monster -- ours is now network-driven")
		end
		if monState ~= "remote" then return end
		REM.cf, REM.last = cf, now
	end)

	-- WHO STREAMS THE WANDER. Nobody negotiates: every client works it out from the same facts
	-- and gets the same answer -- the lowest UserId among the players standing on island18. A
	-- player far from the island is never picked, because at that distance the island's own
	-- parts are streamed out for them, their ground raycasts miss, and they would broadcast a
	-- monster sinking through the floor. During a handover two clients may both send for a
	-- moment; the receivers simply take the newer packet, so it costs a frame, not a bug.
	local function iHostTheWander()
		if not (arenaCF and _G.pancakeQuestComplete) then return false end
		local best
		for _, pl in ipairs(Players:GetPlayers()) do
			local c = pl.Character
			local h = c and c:FindFirstChild("HumanoidRootPart")
			if h and (h.Position - arenaCF.Position).Magnitude <= ISLAND_RANGE then
				if not best or pl.UserId < best.UserId then best = pl end
			end
		end
		return best == player
	end

	-- THE STREAM. 12 a second, and only while the body is doing something worth watching.
	-- Asleep it has not moved since boot and every client already has it in the right place,
	-- so sending would be pure waste.
	while true do
		task.wait(1 / 12)
		-- IT COMES BACK AFTER YOU BEAT IT. The melt destroyed the model; this rebuilds it asleep
		-- under the stack, and the state machine stands it up and starts it wandering on the very
		-- next frame, because by now this player has finished the quest.
		if monState == "melted" and not monster and arenaCF and _G.pancakeQuestComplete
			and os.clock() >= (REM.backAt or math.huge) then
			REM.backAt = nil
			spawnSleepingMonster()
			print("[Pancake] the monster is back on its feet -- it lives here now")
		end
		if REM.ev and not REM.on and monBody and monBody.Parent then
			if monState == "rising" or monState == "hunt" or monState == "melting" then
				pcall(function() REM.ev:FireServer("mon", "cake", monBody.CFrame, "hunt") end)
			elseif monState == "roam" and iHostTheWander() then
				pcall(function() REM.ev:FireServer("mon", "cake", monBody.CFrame, "roam") end)
			end
		end
	end
end)

print("[Pancake] >>> Wake the Pancake Monster (island18) -- v3: beam-engine pump + field-gun "
	.. "launcher built from joints, pouring pads, monster asleep under the stack from boot <<<")
