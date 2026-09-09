--======================================================================
-- CampSmoresQuest_AllInOne.client.lua  (LocalScript, per-player)
--======================================================================
-- "CAMP S'MORES" -- ISLAND 14. Build the campsite AT NIGHT; every step shows.
--
--   *  NIGHT     Accepting the quest brings night down on the camp. The campfire area
--                and the mill's lanterns are the safe light; the pines are out in the
--                dark, and THE WATCHER (island 4's, shared on purpose -- the two camping
--                islands are siblings) creeps out of the treeline while you linger there.
--   1  CUT       3 PineTrees -- one per roasting stick, no padding trees. You are handed a
--                CHAINSAW: it cuts on a timer just by being held to the trunk, but TAPPING
--                revs it and bites deeper -- a lively cutter drops a pine in ~3s, ignoring
--                the throttle still works in 7.
--   2  MILL      Carry the logs to the block named "mill". A cutting station is built
--                there; the logs run through the saw, the blade spins, chips fly, and
--                they come out as giant roasting sticks -- which then fly to the
--                campfire and plant themselves one at a time.
--   3  DELIVER   Back to the Candy Npc: the mallows go on, one stick each.
--   *  IGNITE    Fire, smoke, embers, ambience, DAWN -- and the marshmallows toast.
--
-- (The old GATHER step -- 6 mushroom caps at 15 held seconds each -- is gone for good:
--  it was a whole extra fetch lap. The MallowMushroom models stay as scenery.)
--
-- WHAT THE WORLD PROVIDES (names ignore case/spaces/underscores):
--   PineTree        x3+  your tree models. They topple where they stand.
--   mill            x1   a plain block. The cutting station is BUILT on it; it's hidden.
--   campfire        x1   the woodpile that lights at the end.
--   Marshmallowbig  x3   the giant marshmallows. HIDDEN until each stick is loaded.
--   Candy Npc       x1   quest giver, on island14.
--   chainsaw        x1   OPTIONAL. Yours if you place one (a model still called 'axe' is
--                        accepted); otherwise one is built. Name its parts Grip / Bar /
--                        Tooth / Body / Exhaust and it gets the moving chain, the engine
--                        note and the exhaust smoke for free.
--
-- Everything is client-side and per-player, like the island's other quests.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local SoundService      = game:GetService("SoundService")
local UserInputService  = game:GetService("UserInputService")
local TextChatService   = game:GetService("TextChatService")

-- DECLARED FALSE AT BOOT, not left nil. Every reader today uses `not _G.smoresQuestComplete`,
-- and nil is falsy, so this changes no behaviour -- but a later `== false` test would
-- silently never match on a flag that was never declared, and this states up front that
-- island14 Camp S'mores owns it.
_G.smoresQuestComplete = false

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

print("[Smores] >>> VERSION camp-v1 loaded <<<")

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_PREFIX = "island14"
local TREE_NAME     = "pinetree"
local MILL_NAME     = "mill"
local FIRE_NAME     = "campfire"
-- ⚠ THE TOOL IS A CHAINSAW NOW, not an axe. The world lookup still accepts a model called
-- 'axe' (SAW_LEGACY) so an island that already has one hand-placed keeps working -- but a model
-- named 'chainsaw' wins, and with neither one present the fallback built further down is a saw.
local SAW_NAME      = "chainsaw"
local SAW_LEGACY    = "axe"
local MARSH_NAME    = "marshmallowbig"
-- ⚠ RESTORED. Your plants are named this, and they have been standing unpickable since the
-- gather step's wiring was deleted -- the models were never the problem, the missing wireShroom
-- was. Recovered from the pre-deletion revision (66d465c) rather than guessed at.
local SHROOM_NAME   = "mallowmushroom"
local STICK_NAME    = "stickthatgoesup"   -- your 3 roasting sticks by the fire
local STAND_NAME    = "stand"             -- the operator's deck at the mill
local NPC_NAMES     = { "candynpc", "questnpc" }
local NPC_MAX_DIST  = 700

-- HOW MANY TREES YOU FELL, AND HOW MANY LOGS YOU MILL -- they are the same number, because one
-- tree gives one log and one log is one cut at the mill.
--
-- SEVEN TREES, SEVEN LOGS, SEVEN CUTS AT THE MILL.
--
-- ⚠ THE WORLD ONLY HAS 3 PARTS NAMED 'stickthatgoesup', so cuts 4..7 raise no stick by the
-- fire -- raiseStick() no-ops on a missing index by design, and the boot log prints a warning
-- naming the shortfall. Nothing breaks (the delivery step counts #sticks, not this), but the
-- last four cuts have no visible payoff until more stick parts exist. Add four more named
-- 'stickthatgoesup' near the campfire and they are picked up automatically.
--
-- This was briefly cut to 3 to kill the padding, but that was aimed at the OLD chop: seven
-- zero-input trees at 7 seconds each was 49 seconds of standing still. Chopping is interactive
-- now -- tapping on the swing bites CHOP_BONUS off the timer, so a lively chopper drops a pine
-- in about 3 seconds and seven of them is a job rather than a wait.
local LOGS_NEEDED   = 7      -- trees to fell / logs to mill
local SHROOMS_NEEDED = 6     -- mallow credit granted when milling finishes (see the mill step --
                             -- the old gather lap is deleted; this just feeds the delivery math)
local CARRY_MAX     = 8      -- backpack capacity
-- ONE DIAL FOR THE HAT. Sizes AND offsets are both multiplied by it, so it never ends up a
-- bigger dome sitting at the old height with its brim through your eyebrows.
local HAT_SCALE     = 0.95
local MILL_STROKES  = 12     -- taps to shove ONE log through the blade (~4s of honest mashing;
                             -- was 8 timing-game strokes at ~12s -- a mash cadence needs more
                             -- beats per log or the cut is over before it registers as a cut)
-- (SHROOM_PULL and REGROW_TIME are gone with the gather step: 6 caps x 15 held seconds was
--  90 seconds of holding E on top of the cutting and the milling, for a step the mill skips.)
local FIRE_DROP     = 10     -- studs to sink the fire below the top of the campfire model
local FLAME_SCALE   = 4.0    -- flame HEIGHT (not the coals or the glow)
local FLAME_WIDTH   = 0.62   -- flame SPREAD, on top of the scale -- narrower without shrinking
-- (SWINGS_PER_TREE is gone: felling is on a seven-second timer now, not a hit count. See the
--  auto-chop block -- swings are the animation played over the timer, never the thing measured.)
-- how the chainsaw sits in your hand. Tweak these if it reads wrong for your model:
-- ⚠ -12, NOT THE AXE'S -70. These are degrees about the HAND's own X, and the hand's -Y runs
-- down the arm while its -Z runs forward -- so pitch is the dial that swings the tool from
-- "hanging down the leg" (-90) to "pointing straight out in front" (0). An axe hangs: -70 put
-- the head down and ahead of the thigh, which is how you carry one between swings. A CHAINSAW
-- IS NEVER CARRIED THAT WAY -- the bar is held out in front of you, level, or it is buried in
-- your own shin. -12 is level with a few degrees of droop on the nose.
local SAW_PITCH     = -12    -- degrees the bar tips at rest (0 = dead level, out in front)
local SAW_ROLL      = -8     -- degrees the saw rolls, so it is not perfectly square
local SAW_GRIP      = 0.44   -- fallback only: how far along a hand-placed model the fist sits
local SAW_FLIP      = false  -- fallback only: true if it grabs the wrong end
local CHOP_REACH    = 15     -- studs the bar reaches
-- IDLE VS CUTTING. A chainsaw is never still: even at rest it shakes in your hands, and that
-- buzz is most of what says "running engine" rather than "prop shaped like a saw".
--
-- ⚠ ONE TABLE, NOT FOUR LOCALS. This file is already near the top of tools/registers.py's
-- list, and a Luau function -- a script's main chunk included -- silently never runs once it
-- needs a 201st live local. Four related tuning numbers cost one register this way and four
-- as separate constants.
--
-- ⚠ cutChain IS CAPPED BY THE FRAME RATE, NOT BY TASTE. Every third tooth is a bright
-- cutter, so the pattern the eye tracks repeats about every stud; move the chain more than
-- half of that per frame and it reverses on screen (the wagon-wheel effect) instead of
-- running. 22 studs/sec is ~0.37 studs a frame at 60fps -- clearly moving, unambiguously
-- forwards. A real saw runs an order of magnitude faster and would just strobe.
local SAW_FEEL = {
	idleBuzz  = 0.5,   -- degrees of shake at idle
	cutBuzz   = 2.6,   -- degrees of shake while the bar is in the wood
	idleChain = 6,     -- studs/sec the chain crawls at idle
	cutChain  = 22,    -- studs/sec while cutting
}

local COIN_REWARD   = 1500

-- Audio: your OWN asset ids. "" = silent, and nothing is created for an empty id --
-- given how many ids in this place fail auth, silence is the safe default.
local SOUND_CHOP  = ""
-- THE MILL'S SAW -- the same id the tractor's cutting bar and the hay baler use, and driven the
-- same way: a LOOPED sound on the blade whose volume is faded up for exactly as long as a log is
-- going through it. It was a one-shot fired once per log, which is a noise at the start of a job
-- rather than the sound of the job. Empty string still means silent, as everywhere else here.
local SOUND_SAW   = "rbxassetid://136646841190295"
local SOUND_POP   = ""
-- LOOPING campfire crackle -- the same asset realm 1's Campfire.server.lua uses (its CRACKLE_SOUND_ID).
-- Only created once the fire is actually LIT, and destroyed with the Fire folder, so a camp that has not
-- been built yet is silent. Realm 1's note applies here too: a fire that still crackles after it has been
-- put out is worse than one that never crackled.
local SOUND_FIRE  = "rbxassetid://158853971"
-- Realm 1's tuning, carried over: volume 0.55, full out to 10 studs, silent by 45. Its FADE_DIST was cut
-- from 90 to 45 because four garden fires sit ~95 studs apart and at 90 every fire was still audible almost
-- all the way to its neighbour -- stand in the middle and you were inside two or three overlapping crackles,
-- one flat wash of fire noise. Island 14 has ONE campfire, so that particular collision cannot happen here,
-- but the short fade is also what makes it read as "sat at the fire" rather than "somewhere on this island",
-- which is the half worth keeping. 110 studs was audible from most of the camp.
local FIRE_VOLUME = 0.55
local FIRE_RANGE  = 45       -- studs to silence
local FIRE_FULL   = 10       -- studs of FULL volume -- roughly the log-seat ring

-- Palette in ONE table: Luau caps a function at 200 local registers and a file like this
-- sits close to it. Forty colours as forty locals cost forty registers; as a table, one.
local PAL = {
	BARK    = Color3.fromRGB(104, 74, 50),
	BARK_D  = Color3.fromRGB(74, 52, 36),
	WOOD    = Color3.fromRGB(178, 126, 78),
	WOOD_D  = Color3.fromRGB(134, 92, 56),
	WOOD_L  = Color3.fromRGB(210, 160, 108),
	PINE    = Color3.fromRGB(58, 120, 74),
	PINE_D  = Color3.fromRGB(40, 92, 58),
	IRON    = Color3.fromRGB(98, 102, 110),
	IRON_D  = Color3.fromRGB(62, 66, 72),
	STONE   = Color3.fromRGB(150, 146, 138),
	STONE_D = Color3.fromRGB(108, 104, 98),
	MALLOW  = Color3.fromRGB(250, 246, 238),
	TOAST   = Color3.fromRGB(198, 132, 66),
	FLAME   = Color3.fromRGB(255, 156, 56),
	FLAME_H = Color3.fromRGB(255, 232, 156),
	EMBER   = Color3.fromRGB(255, 96, 40),
	SMOKE   = Color3.fromRGB(90, 84, 78),
	CHIP    = Color3.fromRGB(226, 196, 144),
	CANVAS  = Color3.fromRGB(168, 142, 96),
	CANVAS_D = Color3.fromRGB(130, 108, 72),
	PANEL   = Color3.fromRGB(34, 30, 24),
	BUB_F   = Color3.fromRGB(255, 240, 248),
	BUB_S   = Color3.fromRGB(214, 92, 158),
	BUB_T   = Color3.fromRGB(74, 30, 58),
	BUB_H   = Color3.fromRGB(170, 130, 150),
}

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s) return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", "")) end

local function mk(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function tween(inst, t, goal, style)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad), goal)
	tw:Play(); return tw
end

local function playSound(id, vol)
	if not id or id == "" then return end
	local s = Instance.new("Sound"); s.SoundId = id; s.Volume = vol or 0.6
	s.Parent = SoundService; s:Play(); Debris:AddItem(s, 6)
end

local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat
		local r = fn()
		if r then return r end
		task.wait(0.5)
	until os.clock() - t0 > (timeout or 60)
	return fn()
end

local function findIsland()
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.sub(norm(m.Name), 1, #ISLAND_PREFIX) == ISLAND_PREFIX then
			return m
		end
	end
	return nil
end

-- every instance whose normalised name matches, inside the island if we have it
local function findAll(key, island)
	local out = {}
	for _, d in ipairs((island or Workspace):GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and norm(d.Name) == key then
			table.insert(out, d)
		end
	end
	return out
end

local function findOne(key, island)
	local a = findAll(key, island)
	return a[1]
end

local function frameOf(inst)
	if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
	return inst:GetBoundingBox()
end

local function topPartOf(model)     -- the highest BasePart -- a mushroom's cap
	local best
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and (not best or d.Position.Y > best.Position.Y) then best = d end
	end
	return best
end

-- Transparency alone does not hide a part: a Decal/Texture keeps drawing on it and a
-- SurfaceAppearance overrides it outright. Both have to go.
local function hidePart(d, on)
	d.Transparency = on and 1 or (d:GetAttribute("SmoresT") or 0)
	d.CanCollide   = not on and (d:GetAttribute("SmoresC") ~= false)
	d.CanQuery     = not on
	for _, c in ipairs(d:GetChildren()) do
		if c:IsA("Decal") or c:IsA("Texture") then c.Transparency = on and 1 or 0
		elseif on and c:IsA("SurfaceAppearance") then c:Destroy() end
	end
end

local function hideThing(inst, on)
	if inst:IsA("BasePart") then
		if inst:GetAttribute("SmoresT") == nil then
			inst:SetAttribute("SmoresT", inst.Transparency)
			inst:SetAttribute("SmoresC", inst.CanCollide)
		end
		hidePart(inst, on)
	else
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				if d:GetAttribute("SmoresT") == nil then
					d:SetAttribute("SmoresT", d.Transparency)
					d:SetAttribute("SmoresC", d.CanCollide)
				end
				hidePart(d, on)
			end
		end
	end
end

-- ============================================================================
-- STATE
-- ============================================================================
local camp                  -- Folder for everything we build
local island, millPart, firePart, npcHead, fireModel
local step        = 0       -- 0 talk, 1 chop, 2 mill, 3 gather, 4 deliver, 5 done
local questAccepted = false
local logsHeld    = 0       -- logs carried right now
local logsMilled  = 0
local shroomsHeld = 0
local loaded      = 0       -- roasting sticks with a marshmallow on
local carried     = {}      -- { kind = "log" | "cap" } -- lives in the backpack
local millLeft    = 0       -- saw strokes left on the cut in progress
local sticks      = {}      -- { part =, home =, marsh =, up =, done = }
local marshParts  = {}
local refreshBanner
local showBubble
local milling     = false
local sawTemplate, sawHeld, sawHold, sawCutUntil
-- The live saw's moving parts: { bar =, teeth = {}, snd =, smoke =, L =, H =, phase = }.
-- nil whenever nothing is held, or when the world handed us a model that has no chain.
local sawChain

-- ---- THE CHAINSAW --------------------------------------------------------
-- Your 'chainsaw' model is copied ONCE at startup and the original is hidden, so there is never
-- a spare saw lying around and taking it back is just destroying the copy. A model still named
-- 'axe' is accepted too -- see SAW_LEGACY -- and if the island has neither, one is built.
--
-- IT IS WELDED TO THE HAND, not anchored and re-positioned every frame. Anchoring it and
-- driving its CFrame each frame fights the character's own animation -- the arm swings, the
-- saw does not, and it reads as floating near the hand rather than held in it. A weld makes
-- the hand carry it, and the cut is then just an animation of the weld's C0.
--
-- (!) THE CHAIN IS THE ONE THING THAT IS *NOT* WELDED. Its teeth are driven round the bar every
-- frame from the bar's own live CFrame (see the RenderStepped block below), because a chainsaw
-- whose chain does not move is a painted prop -- and that motion is most of what makes this a
-- chainsaw rather than an axe with a new name.
local function gripFor(model)
	-- (!) A NAMED GRIP WINS, AND THAT IS WHY IT IS THE FIRST THING THIS FUNCTION DOES.
	-- The heuristic below puts the fist at the end FURTHEST FROM THE MASS -- exactly right for
	-- an axe, whose mass is the head and whose far end is the butt of the handle, and exactly
	-- backwards for a chainsaw, whose mass IS the handle end: it would hand you the saw by the
	-- tip of the bar. The saw built further down carries a part called 'Grip' whose own -Z runs
	-- out along the bar, so it is taken verbatim and no guessing happens at all.
	if not model:IsA("BasePart") then
		local g = model:FindFirstChild("Grip", true) or model:FindFirstChild("Handle", true)
		if g and g:IsA("BasePart") then
			print("[Smores] saw grip: taken from the model's own '" .. g.Name .. "' part")
			return g.CFrame
		end
	end
	local bcf, bsz = frameOf(model)
	local axes = { { Vector3.new(1, 0, 0), bsz.X }, { Vector3.new(0, 1, 0), bsz.Y },
	               { Vector3.new(0, 0, 1), bsz.Z } }
	table.sort(axes, function(a, b) return a[2] > b[2] end)
	local ax, len = axes[1][1], axes[1][2]

	local sum, tot = 0, 0
	local parts = model:IsA("BasePart") and { model } or model:GetDescendants()
	for _, d in ipairs(parts) do
		if d:IsA("BasePart") then
			local v = math.max(0.001, d.Size.X * d.Size.Y * d.Size.Z)
			sum += bcf:PointToObjectSpace(d.Position):Dot(ax) * v
			tot += v
		end
	end
	local headSide = ((tot > 0 and sum / tot or 0) >= 0) and 1 or -1
	if SAW_FLIP then headSide = -headSide end
	local gripPos = (bcf * CFrame.new(ax * (-headSide * len * SAW_GRIP))).Position
	local headDir = (bcf - bcf.Position) * (ax * headSide)
	if headDir.Magnitude < 0.01 then headDir = Vector3.new(0, 1, 0) end
	print(("[Smores] saw grip: derived -- longest axis %.1f studs, business end toward %s")
		:format(len, tostring(headDir)))
	-- -Z of this frame runs up the shaft toward the head
	return CFrame.lookAt(gripPos, gripPos + headDir)
end

local function biggestPart(inst)
	if inst:IsA("BasePart") then return inst end
	local best, bv
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if not bv or v > bv then best, bv = d, v end
		end
	end
	return best
end

-- (!) THE SAW EXISTS ON YOUR SCREEN ONLY -- this is a LocalScript and the copy is made here, so
-- to everyone else on the island you are miming a cut bare-handed. _G.CarrySay tells CarryView
-- to put a simple chainsaw in your hand on their screens; see CarryView.client.luau. Called
-- through _G so this file needs no extra local, and pcall'd so a missing CarryView is silent,
-- not fatal.
local function takeSaw()
	if sawHeld then
		sawHeld:Destroy(); sawHeld = nil; sawHold = nil
		print("[Smores] chainsaw taken back")
	end
	-- (!) CLEARED WITH THE MODEL. The chain loop below reads sawChain.bar every frame; leaving a
	-- table full of destroyed parts behind is one branch away from writing CFrames to nothing.
	sawChain = nil
	pcall(_G.CarrySay, nil)
end

local function giveSaw()
	if sawHeld or not sawTemplate then return end
	local char = player.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	if not hand then return end                       -- retried by the watcher below

	local c = sawTemplate:Clone()
	c.Name = "ChainsawHeld"
	local root = biggestPart(c)
	if not root then c:Destroy(); return end
	if c:IsA("Model") then c.PrimaryPart = root end

	local grip = gripFor(c)
	local C1   = root.CFrame:ToObjectSpace(grip)      -- the grip, in the root part's own space

	local teeth, bar = {}, nil
	for _, d in ipairs(c:IsA("BasePart") and { c } or c:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false; d.CanQuery = false; d.Massless = true
			if d.Name == "Bar" then bar = d end
			if d.Name == "Tooth" then
				-- (!) A TOOTH IS NEVER WELDED AND STAYS ANCHORED. It is written from the bar's
				-- live CFrame every frame; welding it would nail it to the bar (a chain that
				-- never moves) and un-anchoring it without a weld would drop it on the floor.
				teeth[#teeth + 1] = d
			else
				d.Anchored = false
				if d ~= root then
					local wc = Instance.new("WeldConstraint")
					wc.Part0 = root; wc.Part1 = d; wc.Parent = root
				end
			end
		end
	end

	c.Parent = char
	sawHold = Instance.new("Weld")
	sawHold.Name = "SawHold"
	sawHold.Part0 = hand
	sawHold.Part1 = root
	sawHold.C1 = C1
	-- the small -Z pushes the grip just ahead of the palm and the -0.42 drops it under the
	-- fist, so the housing sits in the hand rather than through the wrist
	sawHold.C0 = CFrame.new(0, -0.42, -0.12) * CFrame.Angles(math.rad(SAW_PITCH), 0, math.rad(SAW_ROLL))
	sawHold.Parent = root
	sawHeld = c

	-- ---- what makes it a RUNNING saw rather than a saw-shaped object --------------------
	-- All three are optional and all three are found BY NAME, so a chainsaw you place in Studio
	-- gets the chain, the engine note and the exhaust for free the moment its parts are called
	-- Bar / Tooth / Body / Exhaust -- and one whose parts are named none of those is simply
	-- held, silently, exactly as the axe used to be.
	sawChain = nil
	if bar and #teeth > 0 then
		-- THE RACETRACK THE TEETH RUN: the straight top and bottom of the bar plus a half-circle
		-- round each end. L is the half-length of the straight run and H the half-height, both
		-- MEASURED OFF THE BAR you actually handed us rather than assumed, so a longer bar just
		-- works. L is shortened by H because the straights stop where the nose curve starts.
		local H = bar.Size.Y * 0.5
		sawChain = { bar = bar, teeth = teeth, H = H,
			L = math.max(0.1, bar.Size.Z * 0.5 - H), phase = 0 }
	end
	local body = c:FindFirstChild("Body", true) or root
	if SOUND_SAW ~= "" and body then
		-- THE ENGINE. The mill blade's id -- a known-good asset in this place -- looped and
		-- pitched DOWN to an idle. Volume and pitch both ride the cut in the loop below, so
		-- burying the bar in a trunk sounds nothing like standing there holding it.
		local snd = Instance.new("Sound")
		snd.Name = "SawEngine"; snd.SoundId = SOUND_SAW; snd.Looped = true
		snd.Volume = 0.16; snd.PlaybackSpeed = 0.7
		snd.RollOffMinDistance = 8; snd.RollOffMaxDistance = 70
		snd.Parent = body; snd:Play()
		if sawChain then sawChain.snd = snd end
	end
	local ex = c:FindFirstChild("Exhaust", true)
	if ex and ex:IsA("BasePart") then
		local sm = Instance.new("ParticleEmitter")
		sm.Texture = "rbxasset://textures/particles/smoke_main.dds"
		sm.Color = ColorSequence.new(Color3.fromRGB(200, 198, 194))
		sm.Size = NumberSequence.new(0.35); sm.Lifetime = NumberRange.new(0.4, 0.8)
		sm.Rate = 0; sm.Speed = NumberRange.new(1.5, 3); sm.SpreadAngle = Vector2.new(24, 24)
		sm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1) })
		sm.Parent = ex
		if sawChain then sawChain.smoke = sm end
	end

	pcall(_G.CarrySay, "chainsaw")
	print(("[Smores] chainsaw handed over -- welded into the hand by the grip, %d chain teeth "
		.. "running (shared to other players)"):format(#teeth))
end

-- ============================================================================
-- THE SAW, EVERY FRAME: buzz, bite, chain, engine note, exhaust
-- ============================================================================
-- ⚠ THE AXE'S 120-DEGREE SWING IS GONE, AND IT HAD TO GO. An axe is WOUND UP overhead and
-- dropped through the cut, which is why the old animation subtracted 120 degrees from the rest
-- pitch. Doing that with a chainsaw throws a running two-stroke back over your own shoulder
-- twice a second. A saw does the opposite: it is held STILL and LEANED INTO the wood, and all
-- the movement you can see is the engine shaking it and the chain going round.
--
--   buzz   always on while it is held, harder in the cut -- a running engine is never still,
--          and that shake is most of what says "running" rather than "prop shaped like a saw"
--   bite   the cut pushes the bar forward and noses it down, and it EASES OFF between bites,
--          so chopping reads as repeated bites into the trunk rather than one long shove
--   chain  the teeth run the racetrack round the bar, forward along the UNDERSIDE, which is
--          the direction a real saw throws its chips away from the person holding it
RunService.RenderStepped:Connect(function(dt)
	if not (sawHold and sawHold.Parent) then return end

	-- 0..1, full the instant a bite lands and easing out over 0.35s. Chopping re-stamps
	-- sawCutUntil about twice a second, so this pulses rather than sitting pinned at 1.
	local cut = math.clamp(((sawCutUntil or 0) - os.clock()) / 0.35, 0, 1)

	-- THREE INCOMMENSURATE SINES. One sine is a wobble; three that do not divide into each
	-- other are a vibration, and the difference is obvious the moment you hold the thing.
	local buzz = math.rad(SAW_FEEL.idleBuzz + (SAW_FEEL.cutBuzz - SAW_FEEL.idleBuzz) * cut)
	local n = os.clock() * 57
	sawHold.C0 = CFrame.new(0, -0.42, -0.12 - 0.42 * cut)
		* CFrame.Angles(math.rad(SAW_PITCH - 8 * cut) + math.sin(n) * buzz,
			math.sin(n * 0.71) * buzz,
			math.rad(SAW_ROLL) + math.sin(n * 1.33) * buzz)

	local ch = sawChain
	if not (ch and ch.bar and ch.bar.Parent) then return end

	-- ---- THE CHAIN ------------------------------------------------------------------
	-- The teeth ride one closed loop: the straight top run, a half-circle round the nose, the
	-- straight underside, a half-circle round the back. Everything is measured in the BAR's own
	-- frame and multiplied by its live CFrame, so the chain follows the bar through the buzz,
	-- the bite, the arm animation and your own camera without any of them being accounted for.
	local L, H = ch.L, ch.H
	local run  = 4 * L + 2 * math.pi * H            -- total length of the loop
	-- MINUS, not plus. Advancing the phase the other way runs the cutters backwards along the
	-- underside, which looks like a saw trying to climb out of the cut at you.
	ch.phase = (ch.phase
		- (SAW_FEEL.idleChain + (SAW_FEEL.cutChain - SAW_FEEL.idleChain) * cut) * dt) % run
	local cf, count = ch.bar.CFrame, #ch.teeth
	for i, tooth in ipairs(ch.teeth) do
		local d = (ch.phase + (i - 1) / count * run) % run
		local y, z
		if d < 2 * L then                            -- top run, back to front
			y, z = H, L - d
		elseif d < 2 * L + math.pi * H then          -- round the nose
			local a = (d - 2 * L) / H
			y, z = H * math.cos(a), -L - H * math.sin(a)
		elseif d < 4 * L + math.pi * H then          -- underside, front to back
			y, z = -H, -L + (d - 2 * L - math.pi * H)
		else                                         -- round the back
			local a = (d - 4 * L - math.pi * H) / H
			y, z = -H * math.cos(a), L + H * math.sin(a)
		end
		tooth.CFrame = cf * CFrame.new(0, y, z)
	end

	-- ---- ENGINE NOTE AND EXHAUST ----------------------------------------------------
	-- Pitch AND volume, because either one on its own reads as a radio being turned up. A saw
	-- under load drops in pitch and gets louder; free-running it thins out to a whine.
	if ch.snd then
		ch.snd.PlaybackSpeed = 0.7 + 0.55 * cut
		ch.snd.Volume = 0.16 + 0.34 * cut
	end
	if ch.smoke then ch.smoke.Rate = 3 + 22 * cut end
end)

-- a respawn drops the weld with the old character, so hand it back
player.CharacterAdded:Connect(function()
	-- sawChain goes with them: its teeth and its sound belonged to the OLD character and are
	-- already gone, and the frame loop must not be left holding a table of destroyed parts.
	sawHeld, sawHold, sawChain = nil, nil, nil
	task.delay(1.5, function() if step == 1 then giveSaw() end end)
end)

-- ============================================================================
-- THE BACKPACK -- everything you gather goes in it
-- ============================================================================
-- The NPC hands this over with the chainsaw. Carrying things in your arms capped you at what you
-- could physically hold, which is why six mushrooms would not fit; the pack is the inventory,
-- and what is in it shows as items poking out of the top.
--
-- It is WELDED to the torso rather than positioned each frame, for the same reason as the saw:
-- an anchored prop driven by CFrame fights the character's animation and reads as floating.
-- FIT THE HAT TO THE HEAD THAT IS WEARING IT.
--
-- A fixed-size hat is wrong on almost everybody: hair, horns and hoods are accessories with
-- their own sizes, so the same dome that sits neatly on a bald head has a fringe growing
-- through it on the next player. This measures the head AND every accessory attached to it, in
-- the head's own frame, and returns how wide and how tall the hat has to be to swallow them.
--
-- Distance-gated to 6 studs so it measures headwear and not a back accessory or a tool.
local function headExtent(char, head)
	local rad = math.max(head.Size.X, head.Size.Z) * 0.5
	local top = head.Size.Y * 0.5
	for _, a in ipairs(char:GetChildren()) do
		if a:IsA("Accessory") then
			local h = a:FindFirstChild("Handle")
			if h and h:IsA("BasePart") and (h.Position - head.Position).Magnitude < 6 then
				local o, s = head.CFrame:PointToObjectSpace(h.Position), h.Size * 0.5
				rad = math.max(rad, math.abs(o.X) + s.X, math.abs(o.Z) + s.Z)
				top = math.max(top, o.Y + s.Y)
			end
		end
	end
	return rad, top
end

-- Grow the hat until it covers that, then RAISE it until its crown clears the tallest thing on
-- the head -- growing alone would leave a tall hairstyle poking straight out of the top.
--
-- FIT ON THE BRIM, NOT THE DOME. The brim is 1.66 wide at scale 1 against the dome's 1.30, so
-- it is the brim that does the covering -- and sizing off the narrower dome grew the whole hat
-- about a quarter larger than it needed to be to cover the same hair. Radii at scale 1: brim
-- 0.83, dome 0.65, dome half-height 0.54.
local function fitHat(char, head, base)
	local rad, top = headExtent(char, head)
	local H    = math.clamp(math.max(base, (rad + 0.03) / 0.83), base, 1.55)
	local seat = math.max(0.52 * H, top + 0.05 - 0.54 * H)
	return H, seat
end

-- Anything still standing proud of the crown after all that is taller than a hat can sensibly
-- be -- some hair pieces are half a metre of spikes. Those get hidden while the hat is on
-- rather than growing the hat into something comical, and put back when it comes off.
local function tuckHair(char, head, seat, H, store)
	local crown = seat + 0.54 * H
	for _, a in ipairs(char:GetChildren()) do
		if a:IsA("Accessory") then
			local h = a:FindFirstChild("Handle")
			if h and h:IsA("BasePart") and (h.Position - head.Position).Magnitude < 6 then
				local o, s = head.CFrame:PointToObjectSpace(h.Position), h.Size * 0.5
				if o.Y + s.Y > crown then
					store[h] = h.Transparency
					h.Transparency = 1
				end
			end
		end
	end
end

local pack, packSlots = nil, {}
local hidHair = {}

-- ⚠ WHAT YOU CARRY IS NOT DRAWN. Every gathered log and mushroom used to pop out of the rolled
-- top of the pack, one prop per slot. It was legible from behind and it was also six lumps of
-- geometry rotating with your back through every chop, every prompt and every camera angle --
-- and the same complaint applies as on island11's diamonds: the count belongs on the objective
-- line, not welded to the player.
--
-- The slots are still BUILT (buildBackpack makes them and this is still the one place they are
-- cleared), so re-showing them is a one-line change here rather than a rebuild -- but nothing is
-- ever made visible. The pack itself stays: it is worn gear, not cargo, and it is what makes
-- "it went in your bag" read at all.
--
-- The count is not lost: the objective banner already carries "logs n/6" and the mill/campfire
-- steps read `carried` directly, exactly as before.
local function refreshPack()
	for _, sl in ipairs(packSlots) do
		sl.log.Transparency  = 1
		sl.face.Transparency = 1
		sl.cap.Transparency  = 1
		sl.stem.Transparency = 1
	end
end

-- A wood-framed canvas packboard, and deliberately little else: two uprights, a tapered sack,
-- a rolled top under a buckled flap, a bedroll underneath, straps over the shoulders. Every
-- extra thing hung off it -- lantern, hatchet, canteen, pouches -- competed with the one part
-- that has to be legible from behind, which is what you are carrying in the top.
local function buildBackpack()
	if pack then return end
	local char  = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
	if not torso then return end

	pack = Instance.new("Model"); pack.Name = "CampPack"; pack.Parent = char
	local function bit(props, cf)
		props.Anchored = false; props.CanCollide = false; props.CanQuery = false
		props.Massless = true; props.Parent = pack
		local p = mk(props); p.CFrame = torso.CFrame * cf; return p
	end

	local BODY_CF = CFrame.new(0, 0.25, 0.92)
	local body = bit({ Color = PAL.CANVAS, Size = Vector3.new(1.85, 1.75, 0.95) }, BODY_CF)

	-- ---- the frame: two uprights and two crossbars, standing proud of the canvas.
	-- THEY END AT THE PACK. At 3.0 studs from a low centre they ran out under the sack and past
	-- the bedroll, reading as two poles growing out of your back rather than as a frame.
	for _, sx in ipairs({ -1, 1 }) do
		bit({ Color = PAL.WOOD_D, Size = Vector3.new(0.2, 2.4, 0.2) }, CFrame.new(sx * 0.88, 0.34, 1.46))
	end
	for _, hy in ipairs({ 1.4, -0.78 }) do
		bit({ Color = PAL.WOOD, Size = Vector3.new(2.0, 0.18, 0.18) }, CFrame.new(0, hy, 1.46))
	end
	-- rounded pads where the straps cross your shoulders: the one place a pack touches you
	for _, sx in ipairs({ -1, 1 }) do
		bit({ Shape = Enum.PartType.Cylinder, Color = PAL.BARK, Size = Vector3.new(0.92, 0.44, 0.44) },
			CFrame.new(sx * 0.6, 1.02, 0.16) * CFrame.Angles(0, 0, math.rad(90)))
	end

	-- ---- the sack: tapers in toward the bottom in two steps rather than one, with a rolled
	-- closure on top, compression straps round it and a pad on the base it stands on
	bit({ Color = PAL.CANVAS,   Size = Vector3.new(1.68, 0.5, 0.88) }, CFrame.new(0, -0.66, 0.90))
	bit({ Color = PAL.CANVAS_D, Size = Vector3.new(1.46, 0.6, 0.78) }, CFrame.new(0, -1.02, 0.88))
	bit({ Color = PAL.CANVAS_D, Size = Vector3.new(1.9, 0.16, 0.99) }, CFrame.new(0, -0.16, 0.92))
	bit({ Color = PAL.BARK_D,   Size = Vector3.new(1.9, 0.13, 0.99) }, CFrame.new(0, 0.62, 0.92))
	bit({ Color = PAL.BARK_D,   Size = Vector3.new(1.9, 0.13, 0.99) }, CFrame.new(0, -0.44, 0.92))
	bit({ Color = PAL.WOOD_D,   Size = Vector3.new(1.6, 0.18, 0.86) }, CFrame.new(0, -1.34, 0.88))
	bit({ Shape = Enum.PartType.Cylinder, Color = PAL.CANVAS_D, Size = Vector3.new(1.86, 0.5, 0.5) },
		CFrame.new(0, 1.26, 0.9) * CFrame.Angles(0, 0, math.rad(90)))

	-- ---- the flap, two leather straps and their buckles
	bit({ Color = PAL.CANVAS, Size = Vector3.new(1.92, 0.66, 1.02) },
		CFrame.new(0, 1.0, 0.94) * CFrame.Angles(math.rad(6), 0, 0))
	for _, sx in ipairs({ -1, 1 }) do
		bit({ Color = PAL.BARK_D, Size = Vector3.new(0.3, 1.5, 0.1) }, CFrame.new(sx * 0.48, 0.72, 1.44))
		bit({ Color = PAL.IRON,   Size = Vector3.new(0.36, 0.3, 0.16) }, CFrame.new(sx * 0.48, 0.2, 1.46))
		bit({ Color = PAL.IRON_D, Size = Vector3.new(0.2, 0.14, 0.2) },  CFrame.new(sx * 0.48, 0.2, 1.5))
	end

	-- ---- a haul loop on top, and lash loops down the side. Both are what your eye reads as
	-- "pack" before it reads any of the panels: it is the bits you would grab hold of that make
	-- a bag look carried rather than modelled.
	bit({ Color = PAL.BARK_D, Size = Vector3.new(0.5, 0.16, 0.16) }, CFrame.new(0, 1.62, 0.60))
	bit({ Color = PAL.BARK_D, Size = Vector3.new(0.16, 0.30, 0.16) }, CFrame.new(-0.22, 1.50, 0.60))
	bit({ Color = PAL.BARK_D, Size = Vector3.new(0.16, 0.30, 0.16) }, CFrame.new(0.22, 1.50, 0.60))
	for _, sy in ipairs({ 0.26, -0.34 }) do
		bit({ Color = PAL.BARK_D, Size = Vector3.new(0.14, 0.26, 0.30) }, CFrame.new(-0.96, sy, 1.30))
		bit({ Color = PAL.BARK_D, Size = Vector3.new(0.14, 0.26, 0.30) }, CFrame.new(0.96, sy, 1.30))
	end
	-- the buckle tongue, hanging below its keeper so the strap reads as done up
	bit({ Color = PAL.WOOD_L, Size = Vector3.new(0.22, 0.34, 0.1) }, CFrame.new(0, 0.02, 1.46))

	-- ---- bedroll slung under the frame, lashed on
	bit({ Shape = Enum.PartType.Cylinder, Color = PAL.CHIP, Size = Vector3.new(2.05, 0.66, 0.66) },
		CFrame.new(0, -1.3, 0.98) * CFrame.Angles(0, 0, math.rad(90)))
	for _, sx in ipairs({ -0.62, 0.62 }) do
		bit({ Color = PAL.BARK_D, Size = Vector3.new(0.14, 0.72, 0.72) }, CFrame.new(sx, -1.3, 0.98))
	end
	-- end caps: a bare cylinder reads as pipe, capped it reads as a rolled blanket
	for _, sx in ipairs({ -1.02, 1.02 }) do
		bit({ Shape = Enum.PartType.Cylinder, Color = PAL.CANVAS_D, Size = Vector3.new(0.1, 0.7, 0.7) },
			CFrame.new(sx, -1.3, 0.98) * CFrame.Angles(0, 0, math.rad(90)))
	end

	-- ---- shoulder straps: over the shoulder and down the chest, not flat on the back
	for _, sx in ipairs({ -1, 1 }) do
		bit({ Color = PAL.BARK, Size = Vector3.new(0.34, 0.26, 1.5) },
			CFrame.new(sx * 0.6, 0.98, 0.34) * CFrame.Angles(math.rad(18), 0, 0))
		bit({ Color = PAL.BARK, Size = Vector3.new(0.34, 1.5, 0.24) },
			CFrame.new(sx * 0.62, 0.16, -0.52) * CFrame.Angles(math.rad(-9), 0, 0))
		bit({ Color = PAL.IRON, Size = Vector3.new(0.38, 0.2, 0.18) }, CFrame.new(sx * 0.62, -0.5, -0.58))
	end
	bit({ Color = PAL.BARK_D, Size = Vector3.new(1.3, 0.2, 0.16) }, CFrame.new(0, 0.3, -0.62))

	-- ---- what you are carrying, poking out of the rolled top. Each slot holds a log and a
	-- mushroom pre-built and shows whichever one that slot is holding, so nothing has to move.
	packSlots = {}
	for i = 1, 6 do
		local x    = -0.72 + (i - 1) * 0.29
		local lean = CFrame.Angles(math.rad(14), 0, math.rad((i - 3.5) * 4))
		local at   = CFrame.new(x, 1.55, 0.94) * lean
		packSlots[i] = {
			log  = bit({ Color = PAL.BARK,   Size = Vector3.new(0.36, 1.4, 0.36), Transparency = 1 },
				at * CFrame.new(0, 0.55, 0)),
			face = bit({ Color = PAL.WOOD_L, Size = Vector3.new(0.38, 0.12, 0.38), Transparency = 1 },
				at * CFrame.new(0, 1.29, 0)),
			cap  = bit({ Color = PAL.MALLOW, Size = Vector3.new(0.6, 0.5, 0.6), Transparency = 1 },
				at * CFrame.new(0, 0.72, 0)),
			stem = bit({ Color = PAL.CHIP,   Size = Vector3.new(0.24, 0.5, 0.24), Transparency = 1 },
				at * CFrame.new(0, 0.35, 0)),
		}
	end

	for _, d in ipairs(pack:GetDescendants()) do
		if d:IsA("BasePart") and d ~= body then
			local wc = Instance.new("WeldConstraint"); wc.Part0 = body; wc.Part1 = d; wc.Parent = body
		end
	end
	local w = Instance.new("Weld")
	w.Part0 = torso; w.Part1 = body
	w.C0 = BODY_CF
	w.Parent = body
	pack.PrimaryPart = body

	-- ---- THE CAMP HAT, matching the miner's on island 11: same rounded build, soft wide brim
	-- instead of a shell. Round because a hat has no flat faces on it -- the dome is a ball
	-- squashed on Y with its lower half hidden inside the head, brim and band are cylinders.
	local head = char:FindFirstChild("Head")
	if head then
		local hat = Instance.new("Model"); hat.Name = "CampHat"; hat.Parent = char
		local H, seat = fitHat(char, head, HAT_SCALE)
		tuckHair(char, head, seat, H, hidHair)
		local HAT_CF, hroot = CFrame.new(0, seat, 0), nil
		for i, q in ipairs({
			{ { Shape = Enum.PartType.Ball, Color = PAL.WOOD_D,
				Size = Vector3.new(1.32, 1.00, 1.32) * H }, CFrame.new() },
			{ { Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_D,
				Size = Vector3.new(0.10, 2.00, 2.00) * H },
				CFrame.new(0, -0.30 * H, 0) * CFrame.Angles(0, 0, math.rad(90)) },
			{ { Shape = Enum.PartType.Cylinder, Color = PAL.BARK_D,
				Size = Vector3.new(0.24, 1.36, 1.36) * H },
				CFrame.new(0, -0.18 * H, 0) * CFrame.Angles(0, 0, math.rad(90)) },
			{ { Color = PAL.CANVAS, Size = Vector3.new(0.28, 0.15, 0.15) * H },
				CFrame.new(0.60 * H, -0.16 * H, 0.12 * H) },
		}) do
			local props = q[1]
			props.Anchored = false; props.CanCollide = false; props.CanQuery = false
			props.Massless = true; props.Parent = hat
			local pt = mk(props)
			pt.CFrame = head.CFrame * HAT_CF * q[2]
			if i == 1 then hroot = pt end
		end
		for _, d in ipairs(hat:GetChildren()) do
			if d:IsA("BasePart") and d ~= hroot then
				local wc = Instance.new("WeldConstraint"); wc.Part0 = hroot; wc.Part1 = d; wc.Parent = hroot
			end
		end
		local hw = Instance.new("Weld")
		hw.Part0 = head; hw.Part1 = hroot; hw.C0 = HAT_CF; hw.Parent = hroot
		hat.PrimaryPart = hroot
	end

	refreshPack()
	print(("[Smores] backpack + camp hat on -- hat fitted at %.2f scale"):format(HAT_SCALE))
end

--[[ HALF a log: the cut half-round the mill produces. `side` is -1 (the piece nearer the
     operator) or 1. The full log is simply two of these sitting flush, which is what lets the
     blade genuinely SPLIT it -- before this the log rode through the blade whole and then
     vanished, so the one thing the machine is for never happened on screen. ]]
local function buildLogHalf(side)
	local m = Instance.new("Model"); m.Name = "PineHalf"; m.Parent = camp
	-- a half-round: the bark shell, flattened on the cut face
	local body = mk({ Shape = Enum.PartType.Cylinder, Color = PAL.BARK,
	                  Size = Vector3.new(3.0, 0.9, 0.46),
	                  CFrame = CFrame.new(0, 0, side * 0.23), Parent = m })
	-- the SAWN FACE, pale and flat -- this is the surface that tells you it has been cut
	mk({ Color = PAL.WOOD_L, Size = Vector3.new(3.0, 0.88, 0.06),
	     CFrame = CFrame.new(0, 0, side * 0.02), Parent = m })
	for _, e in ipairs({ -1, 1 }) do
		mk({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_L,
		     Size = Vector3.new(0.1, 0.9, 0.44),
		     CFrame = CFrame.new(e * 1.5, 0, side * 0.23), Parent = m })
	end
	m.PrimaryPart = body; m.WorldPivot = CFrame.new()
	return m
end

local function buildLogProp()
	local m = Instance.new("Model"); m.Name = "PineLog"; m.Parent = camp
	local body = mk({ Shape = Enum.PartType.Cylinder, Color = PAL.BARK,
	                  Size = Vector3.new(3.0, 0.9, 0.9), CFrame = CFrame.new(), Parent = m })
	for _, e in ipairs({ -1, 1 }) do
		mk({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_L,
		     Size = Vector3.new(0.12, 0.92, 0.92),
		     CFrame = CFrame.new(e * 1.5, 0, 0), Parent = m })
	end
	m.PrimaryPart = body; m.WorldPivot = CFrame.new()
	return m
end

local function pickUp(kind)
	if #carried >= CARRY_MAX then return false end
	table.insert(carried, { kind = kind })
	if kind == "log" then logsHeld += 1 else shroomsHeld += 1 end
	refreshPack()
	if refreshBanner then refreshBanner() end
	return true
end

local function dropOne(kind)
	for i = 1, #carried do
		if carried[i].kind == kind then
			table.remove(carried, i)
			refreshPack()
			return true
		end
	end
	return false
end

local function dropAll(kind)
	for i = #carried, 1, -1 do
		if carried[i].kind == kind then table.remove(carried, i) end
	end
	refreshPack()
end

-- a respawn drops the weld with the old character, so put it back on
player.CharacterAdded:Connect(function()
	pack = nil; packSlots = {}
	task.delay(1.6, function() if step >= 1 then buildBackpack() end end)
end)

-- ============================================================================
-- OBJECTIVE BANNER
-- ============================================================================
local objGui = Instance.new("ScreenGui")
objGui.Name = "SmoresObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7
objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5, 0); objFrame.Position = UDim2.new(0.5, 0, 0, 12)
objFrame.Size = UDim2.new(0, 560, 0, 52); objFrame.BackgroundColor3 = PAL.PANEL
objFrame.Visible = false; objFrame.Parent = objGui
do
	Instance.new("UICorner", objFrame).CornerRadius = UDim.new(0, 14)
	local s = Instance.new("UIStroke"); s.Color = PAL.FLAME; s.Thickness = 3; s.Parent = objFrame
end
local objLabel = Instance.new("TextLabel")
objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1, 1)
objLabel.Font = Enum.Font.FredokaOne; objLabel.TextColor3 = Color3.fromRGB(255, 226, 180)
objLabel.TextScaled = true; objLabel.Parent = objFrame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 20; sz.Parent = objLabel
	local pd = Instance.new("UIPadding")
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = objLabel
end

--[[ A progress bar the banner CAN show.

     WARNING -- THIS QUEST'S GUI IS NEVER SEEN. objGui is named "SmoresObjective", and
     ObjectiveBannerBridge hides every "*Objective" ScreenGui and mirrors only the LABEL TEXT
     onto the realm banner. A Frame-and-fill progress bar built here would be invisible to
     every player, however good it looked in Studio. Block characters live inside the string,
     so they survive the mirror and arrive on the banner intact.

     Ten cells: filled, then hollow, then the raw count for anyone who wants the number. ]]
local function bar(done, total)
	local n = 10
	local f = (total > 0) and math.clamp(done / total, 0, 1) or 0
	local full = math.floor(f * n + 0.5)
	return ("%s%s  %d/%d"):format(string.rep("\u{25AE}", full),
		string.rep("\u{25AF}", n - full), done, total)
end

refreshBanner = function()
	local txt
	if milling then
		-- the saw gets a bar too: "3 taps to go" is a number you have to hold in your head,
		-- where a bar filling toward the end of the cut is just visible progress
		objLabel.Text = ("\xF0\x9F\xAA\x9A SAWING   %s")
			:format(bar(MILL_STROKES - millLeft, MILL_STROKES))
		return
	end
	if step >= 5 then
		txt = "\xF0\x9F\x8F\x95 The campsite is complete. Enjoy the fire!"
	elseif step == 4 then
		txt = ("\xF0\x9F\x94\xA5 STEP 5/5  Take the mallows to the Candy NPC   %s")
			:format(bar(loaded, #sticks))
	elseif step == 3 then
		txt = ("\xF0\x9F\x8D\xA1 STEP 4/5  Pick marshmallows around the camp   %s")
			:format(bar(shroomsHeld, SHROOMS_NEEDED))
	elseif step == 2 then
		txt = ("\xF0\x9F\xAA\x93 STEP 3/5  Mill the logs   %s")
			:format(bar(logsMilled, LOGS_NEEDED))
	elseif step == 1 then
		txt = ("\xF0\x9F\x8C\xB2 STEP 2/5  Saw down pines -- TAP to rev the chainsaw   %s")
			:format(bar(logsMilled + logsHeld, LOGS_NEEDED))
	else
		txt = "\xF0\x9F\x8F\x95 STEP 1/5  Talk to the Candy NPC -- follow the arrow"
	end
	objLabel.Text = txt
end

task.spawn(function()
	while true do
		local vis = false
		if firePart then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			vis = hrp ~= nil and (hrp.Position - firePart.Position).Magnitude <= 420
		end
		objFrame.Visible = vis
		task.wait(0.4)
	end
end)

-- ============================================================================
-- THE CUTTING STATION -- built on the block named "mill"
-- ============================================================================
-- Kept deliberately plain: a bench, a blade, a cradle and an out-rack. A saw shed is a
-- handful of shapes doing an obvious job -- piling on detail is what makes a built prop
-- look generated rather than made.
local millBlade, millBladeCF, millAng, millCradle, millOut
local millCarriage, millCarryCF, millLever, millLeverCF, millDust
local millDrive, millDriveCF
local millSawdust                  -- the heap under the blade; grows one cut at a time
local millBelt = {}                -- the cleats on the drive belt; they travel while it runs
local millLoad = 0                 -- 0 free-running .. 1 biting; drives blade speed + pitch
local millSnd                      -- the looped saw; built with the station, faded while cutting

-- Blade and flywheel sit on the SAME SHAFT, so one call turns both. They're Models rather than
-- bare parts because the teeth and spokes have to travel with them -- a smooth disc spinning
-- inside a static ring of teeth reads as broken.
local function spinMill(d)
	-- ⚠ THE BLADE BOGS DOWN IN THE CUT. A saw that holds a constant speed whether it is in
	-- fresh air or halfway through a pine reads as a spinning decoration. millLoad rises the
	-- moment a stroke lands and bleeds off after, so the disc visibly labours and recovers --
	-- and the loop that owns the sound drops its pitch on the same value.
	millLoad = math.max(0, millLoad - 0.02)
	d = d * (1 - millLoad * 0.55)
	millAng = (millAng or 0) + d
	-- the belt cleats travel with the shaft, so the drive reads as connected
	for _, c in ipairs(millBelt) do
		local f = (c.f + (millAng * 0.06) * (c.up and 1 or -1)) % 1
		c.part.CFrame = c.at * CFrame.new(0, (c.up and 6.05 or 3.45), -c.span * f)
	end
	if millBlade and millBladeCF then millBlade:PivotTo(millBladeCF * CFrame.Angles(millAng, 0, 0)) end
	if millDrive and millDriveCF then millDrive:PivotTo(millDriveCF * CFrame.Angles(millAng * 0.28, 0, 0)) end
end

-- Where the finished halves live. Filled by stackCut as each cut completes.
local millStack = {}

--[[ Lay one cut log's two halves on the out-rack. `n` is how many cuts were already done, so
     they tier up in rows of two -- a stack that grows sideways then upward, the way a sawyer
     would actually pile them. ]]
local function stackCut(a, b, n)
	if not millOut then a:Destroy(); b:Destroy(); return end
	local row  = n % 3          -- three pairs to a layer
	local tier = math.floor(n / 3)
	local base = millOut * CFrame.new(-1.2 - row * 1.05, -1.5 + tier * 0.95, 0)
	a:PivotTo(base * CFrame.Angles(0, math.rad(90), 0) * CFrame.new(0, 0, -0.3))
	b:PivotTo(base * CFrame.Angles(0, math.rad(90), 0) * CFrame.new(0, 0, 0.3))
	millStack[#millStack + 1] = a
	millStack[#millStack + 1] = b
end

local function buildMill(part)
	local cf, sz = frameOf(part)
	local top = cf.Position.Y + sz.Y * 0.5
	local at  = CFrame.new(Vector3.new(cf.Position.X, top, cf.Position.Z))
		* (cf - cf.Position)                      -- keep the block's heading
	hideThing(part, true)
	local f = Instance.new("Folder"); f.Name = "Mill"; f.Parent = camp
	local function piece(props, where, parent)
		props.Parent = parent or f
		local p = mk(props); p.CFrame = where; return p
	end

	-- ---- BENCH: long enough for a log to ride the whole way through
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(17, 0.7, 4.6), CanCollide = true, CastShadow = true },
		at * CFrame.new(0, 2.55, 0))
	piece({ Color = PAL.WOOD, Size = Vector3.new(16.4, 0.14, 4.2) }, at * CFrame.new(0, 2.92, 0))
	for _, s in ipairs({ -1, 1 }) do
		for _, e in ipairs({ -1, 1 }) do
			piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.6, 2.2, 0.6), CanCollide = true },
				at * CFrame.new(s * 7.4, 1.1, e * 1.8))
		end
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.4, 0.4, 3.6) },   -- cross brace
			at * CFrame.new(s * 7.4, 0.6, 0))
	end
	piece({ Color = PAL.IRON, Size = Vector3.new(15.6, 0.2, 0.8) }, at * CFrame.new(0, 3.05, 0))

	-- ---- THE BLADE, on a shaft with a flywheel behind it
	millBlade   = Instance.new("Model"); millBlade.Name = "Blade"; millBlade.Parent = f
	millBladeCF = at * CFrame.new(0, 5.1, 0) * CFrame.Angles(0, math.rad(90), 0)
	local disc = piece({ Shape = Enum.PartType.Cylinder, Color = PAL.STONE,
		Size = Vector3.new(0.24, 6.4, 6.4), Reflectance = 0.2 }, millBladeCF, millBlade)
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON_D, Size = Vector3.new(0.34, 1.3, 1.3) },
		millBladeCF, millBlade)
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2
		piece({ Color = PAL.STONE_D, Size = Vector3.new(0.26, 0.62, 0.5) },
			millBladeCF * CFrame.new(0, math.cos(a) * 3.3, math.sin(a) * 3.3) * CFrame.Angles(a, 0, 0),
			millBlade)
	end
	millBlade.PrimaryPart = disc
	millBlade.WorldPivot  = millBladeCF

	-- shaft back from the blade to a pulley, and from there the belt runs to the drive wheel.
	-- Two wheels one behind the other, plus brackets and a motor box, was most of why this end
	-- looked cluttered -- and only one of them was ever visible from where you stand.
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON_D, Size = Vector3.new(3.4, 0.42, 0.42) },
		at * CFrame.new(0, 5.1, -1.15) * CFrame.Angles(0, math.rad(90), 0))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON, Size = Vector3.new(0.6, 1.9, 1.9) },
		at * CFrame.new(0, 5.1, -2.3) * CFrame.Angles(0, math.rad(90), 0))

	-- blade guard: one hood over the top, not an arc of plates
	piece({ Color = PAL.IRON, Size = Vector3.new(1.1, 0.5, 6.2) },
		millBladeCF * CFrame.new(0, 3.55, 0))

	-- ---- SHELTER. The roof is laid as PLANK COURSES rather than one slab per side -- a single
	-- flat pitch is the thing that makes a built shelter look like a placeholder.
	for _, s in ipairs({ -1, 1 }) do
		for _, e in ipairs({ -1, 1 }) do
			piece({ Color = PAL.STONE_D, Size = Vector3.new(1.4, 0.7, 1.4), CanCollide = true },
				at * CFrame.new(s * 8.2, 0.35, e * 3.4))                    -- stone footing
			piece({ Color = PAL.WOOD, Size = Vector3.new(0.7, 9.0, 0.7), CanCollide = true, CastShadow = true },
				at * CFrame.new(s * 8.2, 5.0, e * 3.4))
		end
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.5, 0.5, 7.4) }, at * CFrame.new(s * 8.2, 9.4, 0))

		for i = 1, 2 do                                                     -- two courses a side
			local t = 0.25 + (i - 1) * 0.5
			piece({ Color = (i % 2 == 0) and PAL.WOOD or PAL.WOOD_D,
				Size = Vector3.new(5.6, 0.32, 5.0), CastShadow = true },
				at * CFrame.new(s * 8.8 * t, 11.6 - 2.2 * t, 0) * CFrame.Angles(0, 0, math.rad(-s * 14)))
		end
	end
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(18.4, 0.55, 1.0) }, at * CFrame.new(0, 11.85, 0))

	-- a lantern on the ridge, so the shed reads at night
	piece({ Color = PAL.IRON_D, Size = Vector3.new(0.14, 0.9, 0.14) }, at * CFrame.new(4.6, 11.2, 0))
	local lamp = piece({ Color = PAL.FLAME, Material = Enum.Material.Neon,
		Size = Vector3.new(0.6, 0.8, 0.6) }, at * CFrame.new(4.6, 10.5, 0))
	local lp = Instance.new("PointLight")
	lp.Color = PAL.FLAME; lp.Brightness = 1.6; lp.Range = 22; lp.Parent = lamp

	-- The cradle and out-rack frames are worked out HERE, before anything uses them: the
	-- carriage below is built around millCradle, and defining it further down left it nil.
	millCradle = at * CFrame.new(6.6, 3.6, 0)
	millOut    = at * CFrame.new(-6.6, 3.6, 0)

	-- ---- WHAT HOLDS THE BLADE UP -------------------------------------------------------
	-- The blade, its flywheel and the belt all sat 2.2 studs ABOVE the bench with nothing
	-- between: a shaft assembly floating in mid-air. Two posts up from the bench top into
	-- bearing blocks at the shaft ends is what carries the load in a real bench saw, and it is
	-- the piece your eye looks for without knowing it.
	--
	-- ⚠ AT Z +/- 2.1, NOT NEARER. The log rides through lying along Z and spans +/- 1.5, so a
	-- post at 1.7 would have its inner face at 1.35 -- inside the log's path, and every cut
	-- would drive the log straight through the machine's own frame.
	for _, pz in ipairs({ -2.1, 2.1 }) do
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.75, 2.5, 0.75), CanCollide = true },
			at * CFrame.new(0, 4.05, pz))
		piece({ Color = PAL.IRON_D, Size = Vector3.new(1.15, 1.0, 1.15) },
			at * CFrame.new(0, 5.1, pz * 0.93))                       -- bearing block
		piece({ Color = PAL.IRON, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 0.55, 0.55) },
			at * CFrame.new(0, 5.1, pz * 0.93) * CFrame.Angles(0, math.rad(90), 0))
		-- a diagonal brace back to the bench, so the posts are not two bare sticks
		piece({ Color = PAL.WOOD, Size = Vector3.new(0.4, 2.2, 0.4) },
			at * CFrame.new(0, 3.9, pz * 1.5) * CFrame.Angles(math.rad(pz > 0 and -26 or 26), 0, 0))
	end

	-- ---- THE SAWDUST CHUTE -------------------------------------------------------------
	-- The heap on the floor had nothing above it explaining how it got there. A slot under the
	-- blade and a board angled down to the pile closes that loop: dust falls through the bench,
	-- runs down the chute, lands where the heap is growing. Kept BELOW y 2.2 -- the log rides
	-- at 3.6, so nothing here can foul its run.
	piece({ Color = Color3.fromRGB(28, 24, 20), Size = Vector3.new(1.6, 0.16, 3.4) },
		at * CFrame.new(0, 2.93, 0))                                  -- the slot the dust drops through
	piece({ Color = PAL.WOOD, Size = Vector3.new(2.4, 0.2, 3.6) },
		at * CFrame.new(0, 1.5, 0.55) * CFrame.Angles(math.rad(34), 0, 0))
	for _, cz in ipairs({ -1.7, 1.7 }) do
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(2.4, 0.5, 0.16) },
			at * CFrame.new(0, 1.62, 0.55 + cz * 0.02) * CFrame.Angles(math.rad(34), 0, 0)
				* CFrame.new(0, 0.2, cz))                             -- side walls of the chute
	end

	-- ---- THE LOG DECK ------------------------------------------------------------------
	-- Where logs wait before they are fed. It is the one part of a sawmill that says what the
	-- machine is FOR at a glance, and it gives the in-feed end something to be.
	for _, dz in ipairs({ -1.5, 1.5 }) do
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(4.0, 0.5, 0.6), CanCollide = true },
			at * CFrame.new(10.2, 2.2, dz))
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.55, 2.0, 0.55), CanCollide = true },
			at * CFrame.new(10.2, 1.2, dz))
	end
	for i = 1, 3 do
		piece({ Shape = Enum.PartType.Cylinder, Color = PAL.BARK,
			Size = Vector3.new(3.2, 1.0, 1.0), CastShadow = true },
			at * CFrame.new(9.6 + (i % 2) * 1.1, 2.95 + math.floor((i - 1) / 2) * 0.95, 0)
				* CFrame.Angles(0, math.rad(90), 0))
		piece({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_L,
			Size = Vector3.new(0.12, 1.02, 1.02) },
			at * CFrame.new(9.6 + (i % 2) * 1.1, 2.95 + math.floor((i - 1) / 2) * 0.95, -1.55)
				* CFrame.Angles(0, math.rad(90), 0))
	end

	-- ---- BLADE GUARD, ROLLERS AND A SAWDUST PILE ---------------------------------------
	-- An exposed disc on a bench reads as a wheel. A hood over the top half of it is what says
	-- SAW: it is the shape every real bench saw has, and it hides the blade exactly where the
	-- log is not, so it never blocks the cut you want to watch.
	for k = 0, 6 do
		local a = math.rad(20 + k * 23)
		piece({ Color = PAL.IRON_D, Size = Vector3.new(0.7, 0.34, 0.42) },
			at * CFrame.new(0, 3.9 + math.sin(a) * 2.3, math.cos(a) * 2.3)
				* CFrame.Angles(-a, 0, 0))
	end
	piece({ Color = PAL.IRON, Size = Vector3.new(0.9, 0.28, 0.28) }, at * CFrame.new(0, 6.35, 0))

	-- IN-FEED ROLLERS either side of the blade: they explain how the log is held straight
	-- while it is pushed through, and they break up the long bare rail.
	for _, rx in ipairs({ 2.4, -2.4 }) do
		piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON,
			Size = Vector3.new(2.8, 0.5, 0.5) },
			at * CFrame.new(rx, 3.15, 0) * CFrame.Angles(0, 0, math.rad(90)))
	end

	-- THE SAWDUST PILE under the blade. It starts flat and is grown by growSawdust() on every
	-- cut, so the mess accumulates over the seven logs -- the same "the pile is the progress
	-- bar" idea as the out-rack stack.
	millSawdust = piece({ Color = PAL.WOOD_L, Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 0.3, 1.6) }, at * CFrame.new(0, 0.16, 0))

	-- ---- THE CARRIAGE. A log riding a bare rail looks like it is floating; a wheeled carriage
	-- underneath it explains the motion and gives the cut something to travel on.
	millCarryCF  = millCradle
	millCarriage = Instance.new("Model"); millCarriage.Name = "Carriage"; millCarriage.Parent = f
	local cbed = piece({ Color = PAL.WOOD_D, Size = Vector3.new(4.6, 0.42, 3.0) },
		millCradle * CFrame.new(0, -0.6, 0), millCarriage)
	for _, e in ipairs({ -1, 1 }) do
		piece({ Color = PAL.IRON, Size = Vector3.new(4.8, 0.2, 0.32) },
			millCradle * CFrame.new(0, -0.36, e * 1.35), millCarriage)
		for _, sx in ipairs({ -1, 1 }) do
			piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON_D,
				Size = Vector3.new(0.26, 0.9, 0.9) },
				millCradle * CFrame.new(sx * 1.8, -0.95, e * 1.3) * CFrame.Angles(0, math.rad(90), 0),
				millCarriage)
		end
	end
	millCarriage.PrimaryPart = cbed
	millCarriage.WorldPivot  = millCradle

	-- ---- the start lever, by the in-feed where you would stand
	millLeverCF = at * CFrame.new(7.4, 3.3, -2.6)
	millLever   = Instance.new("Model"); millLever.Name = "Lever"; millLever.Parent = f
	local lshaft = piece({ Color = PAL.IRON, Size = Vector3.new(0.26, 2.4, 0.26) },
		millLeverCF * CFrame.new(0, 1.2, 0), millLever)
	piece({ Color = PAL.WOOD_L, Size = Vector3.new(0.46, 0.55, 0.46) },
		millLeverCF * CFrame.new(0, 2.4, 0), millLever)
	millLever.PrimaryPart = lshaft
	millLever.WorldPivot  = millLeverCF
	millLever:PivotTo(millLeverCF * CFrame.Angles(0, 0, math.rad(16)))
	piece({ Color = PAL.IRON_D, Size = Vector3.new(0.8, 0.5, 0.8) }, millLeverCF)

	piece({ Color = PAL.WOOD, Size = Vector3.new(3.0, 1.6, 2.4), CanCollide = true },
		at * CFrame.new(0, 0.8, 3.9))
	piece({ Color = PAL.CHIP, Size = Vector3.new(2.6, 0.4, 2.0) }, at * CFrame.new(0, 1.65, 3.9))
	do
		local dh = piece({ Transparency = 1, Size = Vector3.new(1, 1, 1) }, at * CFrame.new(0, 3.4, 1.4))
		millDust = Instance.new("ParticleEmitter")
		millDust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		millDust.Color = ColorSequence.new(PAL.CHIP)
		millDust.Lifetime = NumberRange.new(0.5, 1.0); millDust.Rate = 0
		millDust.Speed = NumberRange.new(2, 6); millDust.SpreadAngle = Vector2.new(30, 30)
		millDust.Size = NumberSequence.new(0.3); millDust.Acceleration = Vector3.new(0, -26, 0)
		millDust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1) })
		millDust.Parent = dh
	end

	-- ---- the in-cradle, the out-rack, a stack of logs and a heap of sawdust
	for _, s in ipairs({ -1, 1 }) do
		piece({ Color = PAL.WOOD, Size = Vector3.new(0.5, 1.3, 0.5) },
			at * CFrame.new(6.6, 3.4, s * 1.5) * CFrame.Angles(math.rad(s * 20), 0, 0))
	end
	piece({ Color = PAL.WOOD, Size = Vector3.new(3.6, 0.4, 4.0) }, at * CFrame.new(-6.6, 3.2, 0))
	for i = 1, 2 do
		piece({ Shape = Enum.PartType.Cylinder, Color = PAL.BARK, Size = Vector3.new(4.4, 1.2, 1.2) },
			at * CFrame.new(9.6, 0.65 + (i - 1) * 1.05, ((i % 2) - 0.5) * 1.1)
				* CFrame.Angles(0, math.rad(90), 0))
	end
	piece({ Color = PAL.CHIP, Size = Vector3.new(3.4, 0.5, 3.0) },
		at * CFrame.new(-7.4, 0.25, 1.6) * CFrame.Angles(0, 0.5, 0))

	-- ---- THE DRIVE. A big spoked wheel outside the frame with a belt down to the shaft. The
	-- flywheel on its own never explained where the power was coming from; this does, and it
	-- gives the whole station something large and slow turning behind the fast little blade.
	millDrive   = Instance.new("Model"); millDrive.Name = "DriveWheel"; millDrive.Parent = f
	millDriveCF = at * CFrame.new(0, 4.4, -6.4) * CFrame.Angles(0, math.rad(90), 0)

	-- ---- THE DRIVE BELT ------------------------------------------------------------------
	-- A flywheel and a blade turning in sympathy with nothing between them is two spinning
	-- discs; a belt is what makes one DRIVE the other. Two straight runs (the taut top and the
	-- slack-ish bottom) between the blade shaft at (0, 5.1, 0) and the flywheel at (0, 4.4,
	-- -6.4), plus cleats that travel along them while the saw is running.
	local bA, bB = Vector3.new(0, 5.1, 0), Vector3.new(0, 4.4, -6.4)
	local span = (bB - bA).Magnitude
	for _, off in ipairs({ 0.95, -0.95 }) do
		local mid = at * CFrame.new((bA + bB) * 0.5 + Vector3.new(0, off, 0))
		piece({ Color = PAL.IRON_D, Size = Vector3.new(0.16, 0.22, span) },
			mid * CFrame.Angles(math.rad(off > 0 and -3 or 3), 0, 0))
	end
	-- eight cleats, spaced along the belt loop; the run loop below slides them
	for i = 1, 8 do
		local up = (i <= 4)
		local f = ((i - 1) % 4) / 4
		local cl = piece({ Color = PAL.IRON, Size = Vector3.new(0.24, 0.3, 0.34) },
			at * CFrame.new(0, (up and 6.05 or 3.45), -span * f))
		millBelt[#millBelt + 1] = { part = cl, up = up, f = f, at = at, span = span }
	end
	local dhub = piece({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_D,
		Size = Vector3.new(0.7, 1.6, 1.6) }, millDriveCF, millDrive)
	for i = 1, 6 do                                        -- rim laid as 6 flat segments
		local a = (i / 6) * math.pi * 2
		piece({ Color = PAL.WOOD, Size = Vector3.new(0.62, 0.6, 3.5) },
			millDriveCF * CFrame.new(0, math.cos(a) * 3.4, math.sin(a) * 3.4)
				* CFrame.Angles(a, 0, 0), millDrive)
	end
	for i = 1, 4 do                                        -- four spokes, not eight
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.42, 6.6, 0.34) },
			millDriveCF * CFrame.Angles((i / 4) * math.pi, 0, 0), millDrive)
	end
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON_D, Size = Vector3.new(0.9, 0.9, 0.9) },
		millDriveCF, millDrive)
	millDrive.PrimaryPart = dhub
	millDrive.WorldPivot  = millDriveCF

	for _, s in ipairs({ -1, 1 }) do                       -- the belt down to the shaft
		piece({ Color = PAL.BARK_D, Size = Vector3.new(0.2, 4.3, 0.34) },
			at * CFrame.new(s * 0.9, 4.75, -4.35) * CFrame.Angles(math.rad(9), 0, 0))
	end
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.55, 5.4, 0.55), CanCollide = true },
		at * CFrame.new(0, 2.2, -6.4))

	-- the drop-off prompt
	local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(11, 11, 9),
	                 CFrame = at * CFrame.new(0, 4.5, 0), Parent = f })

	-- ===== THE SAW, LOOPED AND SILENT UNTIL A LOG GOES IN =====
	-- On the station's own hit box, so it is positional -- the noise is at the mill, and it stops
	-- being audible as you walk back to the fire. Rolloff min 40 for the reason the tractor's
	-- cutter documents: positional audio is measured from the CAMERA, and a third-person camera
	-- sits far enough back that a small min-distance eats the level before you ever hear it.
	if SOUND_SAW ~= "" then
		millSnd = Instance.new("Sound")
		millSnd.Name = "MillSaw"
		millSnd.SoundId = SOUND_SAW
		millSnd.Looped = true
		millSnd.Volume = 0                    -- the cutting loop owns this; never snapped on
		millSnd.RollOffMinDistance = 40
		millSnd.RollOffMaxDistance = 200
		millSnd.RollOffMode = Enum.RollOffMode.InverseTapered
		millSnd.Parent = hit
		pcall(function() millSnd:Play() end)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MillPrompt"; prompt.ActionText = "Load the Mill"
	prompt.ObjectText = "Lumber Mill"; prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 14; prompt.RequiresLineOfSight = false
	prompt.Enabled = false; prompt.Parent = hit
	return prompt, at
end

-- The 'stand' part is the operator's deck -- where you stand to work the mill. It gets a
-- planked platform, a rail on three sides so you are not just on a floating board, steps up
-- to it, and a rack for the tools you are not holding.
local function buildStand(part)
	local cf, sz = frameOf(part)
	local at = CFrame.new(Vector3.new(cf.Position.X, cf.Position.Y + sz.Y * 0.5, cf.Position.Z))
		* (cf - cf.Position)
	hideThing(part, true)
	local f = Instance.new("Folder"); f.Name = "MillStand"; f.Parent = camp
	local function piece(props, where)
		props.Parent = f
		local p = mk(props); p.CFrame = where; return p
	end

	-- planked deck, laid as separate boards on two stepped tones
	for i = 1, 7 do
		piece({ Color = (i % 2 == 0) and PAL.WOOD or PAL.WOOD_D,
			Size = Vector3.new(6.4, 0.28, 0.82), CanCollide = true, CastShadow = true },
			at * CFrame.new(0, 1.7, -2.6 + (i - 1) * 0.88))
	end
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(6.6, 0.22, 6.4) }, at * CFrame.new(0, 1.5, 0))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz2 in ipairs({ -1, 1 }) do
			piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.5, 1.6, 0.5), CanCollide = true },
				at * CFrame.new(sx * 2.9, 0.8, sz2 * 2.8))
			piece({ Color = PAL.STONE_D, Size = Vector3.new(0.9, 0.36, 0.9), CanCollide = true },
				at * CFrame.new(sx * 2.9, 0.18, sz2 * 2.8))
		end
	end

	-- rail on three sides, open at the front where you step up
	local posts = { { -2.9, -2.8 }, { 2.9, -2.8 }, { -2.9, 2.8 }, { 2.9, 2.8 }, { 0, 2.8 } }
	for _, q in ipairs(posts) do
		piece({ Color = PAL.WOOD, Size = Vector3.new(0.32, 2.2, 0.32), CanCollide = true },
			at * CFrame.new(q[1], 2.9, q[2]))
	end
	piece({ Color = PAL.WOOD_L, Size = Vector3.new(6.2, 0.24, 0.24) }, at * CFrame.new(0, 3.9, 2.8))
	piece({ Color = PAL.WOOD_L, Size = Vector3.new(6.2, 0.18, 0.18) }, at * CFrame.new(0, 3.2, 2.8))
	for _, sx in ipairs({ -1, 1 }) do
		piece({ Color = PAL.WOOD_L, Size = Vector3.new(0.24, 0.24, 5.8) },
			at * CFrame.new(sx * 2.9, 3.9, 0))
		piece({ Color = PAL.WOOD_L, Size = Vector3.new(0.18, 0.18, 5.8) },
			at * CFrame.new(sx * 2.9, 3.2, 0))
	end

	-- steps up the front
	for i = 1, 3 do
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(3.0, 0.3, 0.9), CanCollide = true },
			at * CFrame.new(0, 0.42 + (i - 1) * 0.44, -3.1 - (i - 1) * 0.85))
	end

	-- a rack on the back rail: spare handles, a mug, a lantern on a hook
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(2.6, 0.3, 0.5) }, at * CFrame.new(-1.4, 4.2, 2.9))
	for i = 1, 3 do
		piece({ Color = PAL.WOOD_L, Size = Vector3.new(0.16, 1.2, 0.16) },
			at * CFrame.new(-2.2 + (i - 1) * 0.5, 4.9, 2.9) * CFrame.Angles(0, 0, math.rad((i - 2) * 7)))
	end
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON, Size = Vector3.new(0.4, 0.6, 0.6) },
		at * CFrame.new(-0.4, 4.5, 2.9) * CFrame.Angles(0, math.rad(90), 0))
	piece({ Color = PAL.IRON_D, Size = Vector3.new(0.16, 0.7, 0.16) }, at * CFrame.new(2.3, 4.6, 2.9))
	local ln = piece({ Color = PAL.FLAME, Material = Enum.Material.Neon,
		Size = Vector3.new(0.46, 0.62, 0.46) }, at * CFrame.new(2.3, 4.05, 2.9))
	local lp = Instance.new("PointLight")
	lp.Color = PAL.FLAME; lp.Brightness = 1.4; lp.Range = 20; lp.Parent = ln

	print("[Smores] operator's stand built")
end

local function sawChips(at)
	local host = mk({ Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = at, Parent = camp })
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(PAL.CHIP, PAL.WOOD)
	em.Lifetime = NumberRange.new(0.35, 0.8); em.Rate = 0
	em.Speed = NumberRange.new(9, 20); em.SpreadAngle = Vector2.new(38, 38)
	em.Size = NumberSequence.new(0.35); em.Acceleration = Vector3.new(0, -42, 0)
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1),
	                                       NumberSequenceKeypoint.new(1, 1) })
	em.Parent = host
	return em, host
end

-- ============================================================================
-- MINI-GAMES -- the bit you actually play
-- ============================================================================
-- One HUD serves both jobs, because they are the same widget underneath: a track, a needle
-- running along it, a target band and a fill showing how far through you are. Sawing asks you
-- to tap the needle inside the band; pulling a mushroom asks you to hold. Building it twice
-- would have meant two sets of tuning to keep in step.
--
-- Input goes through a full-screen invisible button rather than UserInputService, so a tap
-- meant for the mini-game cannot also rev the saw, and it works on touch without a second
-- code path.
local mgGui = Instance.new("ScreenGui")
mgGui.Name = "SmoresMiniGame"; mgGui.ResetOnSpawn = false; mgGui.DisplayOrder = 9
mgGui.IgnoreGuiInset = true; mgGui.Enabled = false; mgGui.Parent = PlayerGui

local mgCatch = Instance.new("TextButton")
mgCatch.Size = UDim2.fromScale(1, 1); mgCatch.BackgroundTransparency = 1
mgCatch.Text = ""; mgCatch.AutoButtonColor = false; mgCatch.ZIndex = 1
mgCatch.Parent = mgGui

local mgPanel = Instance.new("Frame")
mgPanel.Size = UDim2.new(0, 540, 0, 152)
mgPanel.Position = UDim2.new(0.5, -270, 0.74, 0)
-- ⚠ BRIGHT, NOT DARK. This was PAL.PANEL (34,30,24) -- a near-black slab, which is the one
-- thing this realm's HUD palette rules out: every other card here is the house blue/white/
-- lime/gold, and a black panel in the middle of them reads as a different game's UI.
-- Only COLOUR and CHILDREN are touched below. Size and Position belong to _G.housePanel,
-- which re-asserts them and names anyone who writes them after adoption.
mgPanel.BackgroundColor3 = Color3.fromRGB(255, 252, 246); mgPanel.BackgroundTransparency = 0
mgPanel.BorderSizePixel = 0; mgPanel.ZIndex = 2; mgPanel.Parent = mgGui
do
	-- a whisper of vertical gradient: a flat fill reads as printed, a graded one as lit
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(240, 232, 250))
	g.Rotation = 90; g.Parent = mgPanel
end
-- HOUSE PANEL: the house 700x260 task card, centred in the free band, and the bottom
-- buttons hide while it is up. One call does both -- see HousePanel.client.luau.
-- The panel keeps its own size and every child keeps its own pixel coordinates;
-- it is centred in the house shell and scaled to fit, so nothing inside moves.
mgPanel:SetAttribute("WantsHousePanel", true)   -- adopted by attribute, so load order cannot lose it
pcall(_G.housePanel, mgPanel)   -- island14 mill minigame
Instance.new("UICorner", mgPanel).CornerRadius = UDim.new(0, 16)
local mgStroke = Instance.new("UIStroke")
mgStroke.Color = Color3.fromRGB(255, 122, 190); mgStroke.Thickness = 4
mgStroke.Transparency = 0; mgStroke.Parent = mgPanel

local mgTitle = Instance.new("TextLabel")
-- ⚠ LAID OUT IN SCALE, NOT IN PIXELS FROM A 540x152 STRIP.
-- _G.housePanel RESIZES this panel to the house card (700x260). These children were authored
-- for the 540x152 panel it used to be, in fixed pixel offsets -- so after adoption they all
-- huddled in the top-left corner and well over half the card was dead space. Anchoring the
-- rows in SCALE means the layout fills whatever the house card is today, and keeps filling it
-- if that card is ever resized again.
mgTitle.Size = UDim2.new(1, -200, 0, 46); mgTitle.Position = UDim2.new(0, 26, 0, 18)
mgTitle.BackgroundTransparency = 1; mgTitle.Font = Enum.Font.GothamBlack
mgTitle.TextSize = 30; mgTitle.TextColor3 = Color3.fromRGB(74, 38, 66)
mgTitle.TextXAlignment = Enum.TextXAlignment.Left; mgTitle.ZIndex = 3
mgTitle.Text = ""; mgTitle.Parent = mgPanel

local mgCount = Instance.new("TextLabel")
mgCount.Size = UDim2.new(0, 160, 0, 46); mgCount.Position = UDim2.new(1, -186, 0, 18)
mgCount.BackgroundTransparency = 1; mgCount.Font = Enum.Font.GothamBlack
mgCount.TextSize = 32; mgCount.TextColor3 = Color3.fromRGB(226, 142, 30)
mgCount.TextXAlignment = Enum.TextXAlignment.Right; mgCount.ZIndex = 3
mgCount.Text = ""; mgCount.Parent = mgPanel

local mgTrack = Instance.new("Frame")
-- the track IS the mini-game, so it gets the whole middle band of the card rather than a
-- 44px sliver near the top -- a wider, taller groove is also a fairer target to hit
mgTrack.Size = UDim2.new(1, -52, 0.3, 0); mgTrack.Position = UDim2.new(0, 26, 0.3, 0)
mgTrack.BackgroundColor3 = Color3.fromRGB(232, 226, 242); mgTrack.BorderSizePixel = 0
mgTrack.ClipsDescendants = true; mgTrack.ZIndex = 3; mgTrack.Parent = mgPanel
Instance.new("UICorner", mgTrack).CornerRadius = UDim.new(0, 12)
do
	-- an inset rim, so the track reads as a groove the needle runs IN rather than a bar
	-- painted on top of the card
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(206, 196, 222); st.Thickness = 2; st.Parent = mgTrack
end

local mgZone = Instance.new("Frame")
mgZone.Size = UDim2.new(0.2, 0, 1, 0); mgZone.Position = UDim2.new(0.4, 0, 0, 0)
mgZone.BackgroundColor3 = Color3.fromRGB(150, 226, 96); mgZone.BackgroundTransparency = 0.1
mgZone.BorderSizePixel = 0; mgZone.ZIndex = 4; mgZone.Parent = mgTrack
Instance.new("UICorner", mgZone).CornerRadius = UDim.new(0, 10)
do
	-- THE ZONE IS THE WHOLE GAME -- it is the thing you are aiming at, and at 0.25
	-- transparency on a black track it was the quietest element on the card. Solid lime with
	-- a darker rim, so where to hit is the first thing your eye finds.
	local zs = Instance.new("UIStroke")
	zs.Color = Color3.fromRGB(92, 168, 52); zs.Thickness = 2; zs.Parent = mgZone
	local zg = Instance.new("UIGradient")
	zg.Color = ColorSequence.new(Color3.fromRGB(196, 242, 140), Color3.fromRGB(132, 208, 84))
	zg.Rotation = 90; zg.Parent = mgZone
end

local mgFill = Instance.new("Frame")
mgFill.Size = UDim2.new(0, 0, 1, 0); mgFill.BackgroundColor3 = Color3.fromRGB(255, 186, 74)
mgFill.BackgroundTransparency = 0.18; mgFill.BorderSizePixel = 0
mgFill.ZIndex = 5; mgFill.Parent = mgTrack
Instance.new("UICorner", mgFill).CornerRadius = UDim.new(0, 12)
do
	local fg = Instance.new("UIGradient")
	fg.Color = ColorSequence.new(Color3.fromRGB(255, 214, 130), Color3.fromRGB(246, 146, 60))
	fg.Parent = mgFill
end

local mgNeedle = Instance.new("Frame")
mgNeedle.Size = UDim2.new(0, 12, 1, 10); mgNeedle.Position = UDim2.new(0, 0, 0, -5)
mgNeedle.BackgroundColor3 = Color3.fromRGB(74, 38, 66)
mgNeedle.BorderSizePixel = 0; mgNeedle.ZIndex = 6; mgNeedle.Parent = mgTrack
do
	-- taller than the track and rounded, so it reads as a marker sitting ACROSS the groove.
	-- A 6px white sliver on a white-ish track would vanish exactly when it matters.
	Instance.new("UICorner", mgNeedle).CornerRadius = UDim.new(0, 5)
	local ns = Instance.new("UIStroke")
	ns.Color = Color3.fromRGB(255, 255, 255); ns.Thickness = 2; ns.Parent = mgNeedle
end

-- ---- STROKE TICKS -------------------------------------------------------------------
-- MILL_STROKES notches across the groove, so the bar is COUNTABLE. A smooth fill tells you
-- roughly how far along you are; notches tell you "three more" -- and knowing there are three
-- more is the difference between mashing hopefully and mashing to a finish line.
for i = 1, MILL_STROKES - 1 do
	local tick = Instance.new("Frame")
	tick.Size = UDim2.new(0, 2, 0.55, 0)
	tick.Position = UDim2.new(i / MILL_STROKES, -1, 0.225, 0)
	tick.BackgroundColor3 = Color3.fromRGB(198, 188, 216)
	tick.BackgroundTransparency = 0.35
	tick.BorderSizePixel = 0; tick.ZIndex = 6; tick.Parent = mgTrack
end

local mgHint = Instance.new("TextLabel")
mgHint.Size = UDim2.new(1, -52, 0.16, 0); mgHint.Position = UDim2.new(0, 26, 0.7, 0)
mgHint.BackgroundTransparency = 1; mgHint.Font = Enum.Font.GothamMedium
mgHint.TextSize = 20; mgHint.TextColor3 = Color3.fromRGB(132, 106, 128)
mgHint.TextXAlignment = Enum.TextXAlignment.Left; mgHint.ZIndex = 3
mgHint.Text = ""; mgHint.Parent = mgPanel

-- One reused pop label. Creating a fresh TextLabel per tap would churn a dozen Instances
-- through a four-second mash; one label that restarts its own tween does the same job.
local mgPop = Instance.new("TextLabel")
mgPop.Size = UDim2.new(0, 160, 0, 40); mgPop.BackgroundTransparency = 1
mgPop.Font = Enum.Font.GothamBlack; mgPop.TextSize = 30
mgPop.TextColor3 = Color3.fromRGB(226, 142, 30)
mgPop.TextStrokeTransparency = 0.6
mgPop.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
mgPop.ZIndex = 9; mgPop.Visible = false; mgPop.Parent = mgPanel

local mgBusy = false

local function mgFlash(good)
	mgStroke.Color = good and Color3.fromRGB(86, 190, 72) or Color3.fromRGB(226, 62, 84)
	-- THE POP IS A SCALE, NOT A RESIZE. It used to punch Size to 552x156 and tween back to
	-- 540x152 -- fine when the panel owned its own size, but _G.housePanel now sets every task
	-- HUD to the house card (now 700x260), and this was the one place that wrote Size AFTER
	-- adoption. The first correct answer in the mini-game would have shrunk it to a 540x152 strip
	-- and left it there, permanently out of step with every other HUD.
	--
	-- Scaling gets the identical punch without touching the geometry the house card depends on.
	-- housePanel sets this UIScale once at adopt and never writes it again, so it is ours to move.
	local us = mgPanel:FindFirstChildOfClass("UIScale")
	if us then
		us.Scale = 1.022
		tween(us, 0.16, { Scale = 1 })
	end
	task.delay(0.18, function() mgStroke.Color = Color3.fromRGB(255, 122, 190) end)
end

local function mgOpen(title, hint, showZone)
	mgZone.Visible = showZone
	mgTitle.Text = title; mgHint.Text = hint; mgCount.Text = ""
	mgFill.Size = UDim2.new(0, 0, 1, 0)
	mgGui.Enabled = true
	-- ===== SCALE POP, NOT A SLIDE (same fix the island 13 wrench needed) =====
	-- This wrote Position AFTER adoption: (0.5,-270, 0.82) -> (0.5,-270, 0.74). Those are SCREEN
	-- coordinates from before _G.housePanel adopted this panel. Inside the 700x260 shell the same
	-- UDim2 resolves to x = 0.5*700 - 270 = 80, y = 0.74*260 = 192 -- low and left of centre, with
	-- half the card outside the house frame, while every other task HUD sat dead centre.
	-- The Size punch in mgFlash was already converted to a UIScale for exactly this reason; the
	-- open/close slide was missed. housePanel writes this UIScale once at adopt and never again.
	do
		local us = mgPanel:FindFirstChildOfClass("UIScale")
		if us then
			us.Scale = 0.92
			tween(us, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
end

local function mgClose()
	-- close: shrink away rather than slide, for the same reason as mgOpen above
	do
		local us = mgPanel:FindFirstChildOfClass("UIScale")
		if us then tween(us, 0.18, { Scale = 0.92 }) end
	end
	task.delay(0.2, function() mgGui.Enabled = false end)
end

-- SAWING -- A MASH, NOT A TIMING TEST (picked from the options). It used to be a needle sweeping
-- a track that you tapped inside a shrinking green band -- a skill game, but an abstract one, and
-- the wrong kind of pressure for the age this realm is built for. Now EVERY TAP SHOVES THE LOG
-- ONE NOTCH INTO THE BLADE: no aiming, no window, just speed. The fill bar is the log's travel,
-- the carriage out in the world lurches forward on the same beat (onStroke drives it, exactly as
-- before), and every tap lands a flash, the saw bite, and a haptic tick.
--
-- IT CANNOT BE FAILED, only sawed slowly: nothing decays, no tap is ever "wrong". The one guard
-- is a 0.09s cooldown per tap, so a turbo-clicker saws fast rather than instantly. The needle
-- and the green zone from the old game stay hidden for the duration.
local function playSaw(strokes, onStroke)
	if mgBusy then return false end
	mgBusy = true
	mgOpen("SAW THE LOG", "TAP FAST -- every tap shoves the log into the blade!", false)
	mgNeedle.Visible = false
	mgCount.Text = ("0 / %d"):format(strokes)

	local hit, lastTap, streak = 0, 0, 0
	local conn = mgCatch.MouseButton1Down:Connect(function()
		if hit >= strokes or os.clock() - lastTap < 0.09 then return end
		local gap = os.clock() - lastTap
		lastTap = os.clock()
		hit += 1

		-- STREAK: taps landed inside a third of a second keep the run going. It changes no
		-- rules -- the log still needs the same twelve strokes -- it just tells you that the
		-- rhythm you have found is the right one, which is the only feedback a mash can give.
		if gap < 0.34 then streak += 1 else streak = 0 end

		mgCount.Text = ("%d / %d"):format(hit, strokes)
		mgHint.Text = (streak >= 3)
			and ("\xF0\x9F\x94\xA5 KEEP GOING -- STREAK x%d"):format(streak)
			or "TAP FAST -- every tap shoves the log into the blade!"

		-- the pop rides the LEADING EDGE of the fill, so the number appears exactly where the
		-- progress just moved rather than floating in the middle of the card
		mgPop.Text = (streak >= 3) and ("x%d!"):format(streak) or "+1"
		mgPop.TextColor3 = (streak >= 3) and Color3.fromRGB(86, 190, 72)
			or Color3.fromRGB(226, 142, 30)
		mgPop.Position = UDim2.new(math.clamp(hit / strokes, 0.04, 0.86), 0, 0.28, 0)
		mgPop.TextTransparency = 0
		mgPop.Visible = true
		tween(mgPop, 0.42, { Position = UDim2.new(mgPop.Position.X.Scale, 0, 0.06, 0),
			TextTransparency = 1 })

		mgFlash(true)
		playSound(SOUND_SAW, 0.5)
		if _G.hapticPulse then pcall(_G.hapticPulse, "tick") end
		tween(mgFill, 0.12, { Size = UDim2.new(hit / strokes, 0, 1, 0) })
		if onStroke then onStroke(hit / strokes) end
	end)

	while hit < strokes do task.wait(0.03) end

	conn:Disconnect()
	mgPop.Visible = false
	task.wait(0.25)
	mgClose()
	mgNeedle.Visible = true
	mgBusy = false
	return true
end

-- (playPull is deleted with the mushroom step -- the hold-to-pull widget's only caller.)

-- ============================================================================
-- NIGHT + THE WATCHER -- island 4's campfire-night design, shared on purpose:
-- the two camping islands are siblings. Accepting the quest brings night down;
-- the finished fire brings dawn. While it is dark, straying from the camp (or
-- the mill's lantern light) draws THE WATCHER out of the treeline -- glowing
-- amber eyes that creep closer and, if they reach you, pounce: a shove back
-- toward camp, never a kill. The pines stand out in that dark, which is the
-- point -- chopping is a venture, the camp is home.
-- ============================================================================
local night = {}    -- .tint (ColorCorrection), .watcher (Model), .on (bool)

local function nightSet(on)
	if on and not night.tint then
		local t = Instance.new("ColorCorrectionEffect")
		t.Name = "SmoresNight"
		t.TintColor = Color3.fromRGB(150, 165, 215)
		t.Brightness = -0.18; t.Saturation = -0.2; t.Contrast = 0.03
		t.Parent = game:GetService("Lighting")
		night.tint = t
	end
	if night.tint then night.tint.Enabled = on end
	night.on = on
	if not on and night.watcher then night.watcher:Destroy(); night.watcher = nil end
end

task.spawn(function()
	while true do
		task.wait(0.25)
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local dark = night.on and step >= 1 and step < 5 and hrp ~= nil and firePart ~= nil
		local safe = true
		if dark then
			safe = mgBusy
				or (hrp.Position - firePart.Position).Magnitude < 45
				or (millPart ~= nil and (hrp.Position - millPart.Position).Magnitude < 34)
		end
		if not dark or safe then
			if night.watcher then night.watcher:Destroy(); night.watcher = nil end
		elseif not night.watcher then
			-- it appears on your dark side -- directly away from the camp
			local away = hrp.Position - firePart.Position
			away = Vector3.new(away.X, 0, away.Z)
			local dir = (away.Magnitude > 1) and away.Unit or Vector3.new(0, 0, 1)
			local at = hrp.Position + dir * 32 + Vector3.new(0, 1.5, 0)
			local m = Instance.new("Model"); m.Name = "TheWatcher"
			local body = mk({ Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4),
				Color = Color3.fromRGB(22, 16, 12), Transparency = 0.35, CFrame = CFrame.new(at) })
			body.Parent = m
			for _, s in ipairs({ -1, 1 }) do
				local eye = mk({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.55, 0.7, 0.4),
					Color = Color3.fromRGB(255, 190, 70), Material = Enum.Material.Neon,
					CFrame = CFrame.new(at + Vector3.new(s * 0.55, 0.5, -1.35)) })
				eye.Parent = m
			end
			m.PrimaryPart = body
			m.Parent = Workspace
			night.watcher = m
		else
			local wp = night.watcher:GetPivot().Position
			local to = hrp.Position - wp
			local d = to.Magnitude
			if d > 0.1 then
				night.watcher:PivotTo(CFrame.lookAt(wp + to.Unit * math.min(0.85, d), hrp.Position))
			end
			if d <= 7 then
				-- pounce: a shove back toward the firelight, then it's gone
				local push = firePart.Position - hrp.Position
				push = Vector3.new(push.X, 0, push.Z)
				if push.Magnitude > 1 then
					hrp.AssemblyLinearVelocity = push.Unit * 44 + Vector3.new(0, 22, 0)
				end
				if _G.NotifyCenter then pcall(function() _G.NotifyCenter.push({
					text = "\xF0\x9F\x91\x80 Something in the trees! Stay near the light!",
					color = PAL.FLAME }) end) end
				night.watcher:Destroy(); night.watcher = nil
			end
		end
	end
end)

-- ============================================================================
-- ROASTING STICKS -- your three 'Stickthatgoesup' parts
-- ============================================================================
-- These are YOUR parts, placed where you want them. The quest does not build sticks any more;
-- it hides the ones you placed and raises them out of the ground one per cut at the mill.
local function wireStick(p)
	for _, s in ipairs(sticks) do if s.part == p then return end end
	local home = p:IsA("Model") and p:GetPivot() or p.CFrame
	hideThing(p, true)
	sticks[#sticks + 1] = { part = p, home = home }
	print(("[Smores] stick %d wired and hidden"):format(#sticks))
end

-- Each stick owns the marshmallow nearest it, one to one. Done as a pass rather than at wire
-- time because sticks and marshmallows stream in independently -- whichever arrives second
-- would otherwise find nothing to pair with.
local function pairSticks()
	local used = {}
	for _, st in ipairs(sticks) do if st.marsh then used[st.marsh] = true end end
	for _, st in ipairs(sticks) do
		if not st.marsh then
			local best, bd
			for _, mm in ipairs(marshParts) do
				if not used[mm] then
					local d = (select(1, frameOf(mm)).Position - st.home.Position).Magnitude
					if not bd or d < bd then best, bd = mm, d end
				end
			end
			if best then st.marsh = best; used[best] = true end
		end
	end
end

local function raiseStick(i)
	local st = sticks[i]
	if not st or st.up then return end
	st.up = true
	local function put(cf)
		if st.part:IsA("Model") then st.part:PivotTo(cf) else st.part.CFrame = cf end
	end
	put(st.home * CFrame.new(0, -7, 0))
	hideThing(st.part, false)
	playSound(SOUND_POP, 0.6)
	task.spawn(function()
		for k = 1, 22 do
			put(st.home * CFrame.new(0, -7 * (1 - k / 22), 0))
			task.wait(0.03)
		end
		for k = 1, 7 do                                  -- a small settle as it plants
			put(st.home * CFrame.new(0, math.sin(k / 7 * math.pi) * 0.22, 0))
			task.wait(0.03)
		end
		put(st.home)
	end)
end

-- ============================================================================
-- THE FIRE
-- ============================================================================
-- A flame is not one shape that scales -- it is a lot of tongues of different heights, each
-- leaning and twisting on its own clock, over a bed of coals that outlives them. So this is
-- built as three tiers: a pale core, an orange middle, and short red tongues around the rim,
-- fifteen in all, each made of three stacked blocks that narrow as they rise. Animating the
-- stack from a common spine is what makes them taper and curl rather than just wobble.
local fireBits, fireCoals, fireLogs = {}, {}, {}
local fireLight, fireGlow, fireEmber, fireSmoke
local fireO, fireTop, fireHS
local fireCore, fireLight2
local fireLicks = {}
local fireLevel = 0                    -- 0..1, how established the fire is
local fireLit   = false

local function igniteFire()
	if fireLit then return end
	fireLit = true
	nightSet(false)                          -- DAWN: the finished fire ends the night

	local cf, sz = frameOf(fireModel or firePart)
	local O   = cf.Position
	-- The flame sits FIRE_DROP below the top of the model bounding box. The box is the whole
	-- campfire, and its top is wherever the tallest log ends -- which is well above the wood
	-- the fire actually burns on, so unshifted the flame floats over the pile.
	local top = O.Y + sz.Y * 0.5 - FIRE_DROP
	-- everything below is sized off the pile: a fire built to fixed numbers either floats in
	-- the middle of a big campfire or swallows a small one
	local R  = math.clamp(math.max(sz.X, sz.Z) * 0.34, 1.4, 5.0)
	local HS = math.clamp(R / 1.5, 0.9, 2.4) * FLAME_SCALE
	local FR = R * FLAME_SCALE * FLAME_WIDTH   -- spread is its own dial, so the fire can be
	                                           -- tall and narrow rather than tall and fanned
	local f = Instance.new("Folder"); f.Name = "Fire"; f.Parent = camp

	-- ---- the bed of coals. These light BEFORE the flames and stay lit after, which is what
	-- sells it as a fire that was built rather than one that was switched on.
	for i = 1, 11 do
		local a = (i / 11) * math.pi * 2 + (i % 3) * 0.4
		local r = (0.3 + (i % 4) * 0.23) * R
		local c = mk({ Color = PAL.BARK_D, Material = Enum.Material.SmoothPlastic,
			Size = Vector3.new((0.55 + (i % 3) * 0.18) * HS, 0.28 * HS, (0.5 + (i % 2) * 0.2) * HS),
			CFrame = CFrame.new(O.X + math.cos(a) * r, top - 0.1, O.Z + math.sin(a) * r)
				* CFrame.Angles(0, a + 0.3, 0),
			Parent = f })
		table.insert(fireCoals, { p = c, phase = math.random() * 6.28 })
	end

	-- ---- THE WOODPILE ITSELF. Coals sitting next to untouched brown logs is what gave the
	-- old fire away. Every part of your campfire model chars as it burns, and how red it goes
	-- is set by how close it is to the core -- so the middle of the pile runs hot and the ends
	-- of the logs stay wood, which is what a real fire looks like.
	do
		local host = fireModel or firePart
		local list = {}
		if host:IsA("BasePart") then
			list = { host }
		else
			for _, d in ipairs(host:GetDescendants()) do
				if d:IsA("BasePart") then table.insert(list, d) end
			end
		end
		local reach = math.max(2.6, math.max(sz.X, sz.Z) * 0.62)
		for _, p in ipairs(list) do
			local dv   = Vector3.new(p.Position.X - O.X, 0, p.Position.Z - O.Z).Magnitude
			local fall = math.clamp(1 - dv / reach, 0, 1)
			-- EVERY log runs hot -- this is the fire, not something stood near it. The falloff
			-- decides how hot, not whether: the core goes incandescent, the ends stay dull red.
			table.insert(fireLogs, { p = p, base = p.Color, phase = math.random() * 6.28,
				glow = 0.42 + 0.58 * fall ^ 1.15 })
		end
		print(("[Smores] %d log part(s) in the fire will char and glow"):format(#fireLogs))

		-- WISPS OFF THE WOOD. The tall column of smoke rises from above the flames, which is
		-- right, but nothing was coming off the wood itself -- and smoke curling straight off
		-- a glowing log is most of what makes it look like it is actually burning.
		table.sort(fireLogs, function(a, b) return a.glow > b.glow end)
		for i = 1, math.min(5, #fireLogs) do
			local l = fireLogs[i]
			if l.glow > 0.12 then
				local w = Instance.new("ParticleEmitter")
				w.Texture = "rbxasset://textures/particles/smoke_main.dds"
				w.Color = ColorSequence.new(PAL.SMOKE, Color3.fromRGB(168, 164, 158))
				w.Lifetime = NumberRange.new(1.4, 2.8)
				w.Rate = 2 + l.glow * 4
				w.Speed = NumberRange.new(1.2, 3.4)
				w.SpreadAngle = Vector2.new(26, 26)
				w.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35),
					NumberSequenceKeypoint.new(0.4, 1.5), NumberSequenceKeypoint.new(1, 3.2) })
				w.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.15, 0.74), NumberSequenceKeypoint.new(1, 1) })
				w.Acceleration = Vector3.new(0.5 + i * 0.15, 3.4, -0.2)
				w.RotSpeed = NumberRange.new(-30, 30)
				w.EmissionDirection = Enum.NormalId.Top
				w.Parent = l.p
			end
		end
	end

	-- ---- ground glow: a wide, dim neon slab that throws the fire's colour onto the dirt
	fireGlow = mk({ Color = PAL.EMBER, Material = Enum.Material.Neon, Transparency = 1,
		Size = Vector3.new(R * 4.6, 0.08, R * 4.6),
		CFrame = CFrame.new(O.X, top - 0.28, O.Z), Parent = f })

	-- ---- the tongues, three tiers
	local WS = math.min(1.7 * FLAME_SCALE, HS) * FLAME_WIDTH
	local TIERS = {
		{ n = 5, r0 = 0.00 * FR, r1 = 0.30 * FR, h = 3.1 * HS, w = 0.60 * WS, col = PAL.FLAME_H },
		{ n = 7, r0 = 0.30 * FR, r1 = 0.66 * FR, h = 2.3 * HS, w = 0.72 * WS, col = PAL.FLAME },
		{ n = 6, r0 = 0.66 * FR, r1 = 1.00 * FR, h = 1.5 * HS, w = 0.80 * WS, col = PAL.EMBER },
	}
	fireO, fireTop, fireHS = O, top, HS

	-- THE BASE IS THE BRIGHTEST PART OF A FIRE and it was missing entirely: right where the
	-- flame meets the wood there is a pool of white heat the individual tongues never make,
	-- because each one is thin there. One wide, flat, very bright disc supplies it.
	fireCore = mk({ Shape = Enum.PartType.Cylinder, Color = PAL.FLAME_H,
		Material = Enum.Material.Neon, Transparency = 1,
		Size = Vector3.new(0.5 * HS, FR * 1.9, FR * 1.9),
		CFrame = CFrame.new(O.X, top + 0.25 * HS, O.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = f })

	-- LICKS: shards that break off a tip, rise on their own and burn out. A fire is not a
	-- closed shape -- bits of it detach constantly, and nothing else here does that.
	for _ = 1, 9 do
		local p = mk({ Color = PAL.FLAME, Material = Enum.Material.Neon, Transparency = 1,
			Size = Vector3.new(0.3, 0.5, 0.3), CFrame = CFrame.new(O.X, top, O.Z), Parent = f })
		table.insert(fireLicks, { p = p, life = math.random(), rate = 0.65 + math.random() * 0.7 })
	end
	for ti, T in ipairs(TIERS) do
		for i = 1, T.n do
			local a = (i / T.n) * math.pi * 2 + ti * 0.7
			local r = T.r0 + ((i % 3) / 2) * (T.r1 - T.r0)
			local b = { segs = {}, h = T.h * (0.82 + (i % 3) * 0.12), w = T.w,
			            phase = math.random() * 6.28, surge = 0, tier = ti,
			            ang = a, rad = r,
			            life = math.random(), rate = 0.42 + math.random() * 0.36 }
			b.base = CFrame.new(O.X + math.cos(a) * r, top, O.Z + math.sin(a) * r)
			b.out  = Vector3.new(math.cos(a), 0, math.sin(a))
			-- COLOUR RUNS UP THE TONGUE, not across the tier: white-hot at the wood, orange
			-- through the middle, dull red at the tip, fading out as it goes. A tongue that is
			-- one flat colour top to bottom is the single biggest tell in a stylised fire.
			for k = 1, 3 do
				b.segs[k] = mk({ Material = Enum.Material.Neon,
					Color = (k == 1) and PAL.FLAME_H or ((k == 2) and T.col or PAL.EMBER),
					Transparency = 0.04 + (k - 1) * 0.19 + ti * 0.03,
					Size = Vector3.new(0.1, 0.1, 0.1), CFrame = b.base, Parent = f })
			end
			table.insert(fireBits, b)
		end
	end

	-- ---- light. Range and brightness both flicker, because a light that only dims reads as
	-- a lamp on a dimmer rather than a fire.
	fireLight = Instance.new("PointLight")
	fireLight.Color = PAL.FLAME; fireLight.Brightness = 0; fireLight.Range = 12
	fireLight.Shadows = true
	fireLight.Parent = fireGlow

	-- a second light, low and red, so the ground stays lit between flares. One light doing
	-- both jobs has to choose, and it always chose the flames.
	fireLight2 = Instance.new("PointLight")
	fireLight2.Color = PAL.EMBER; fireLight2.Brightness = 0; fireLight2.Range = 16
	fireLight2.Parent = fireGlow

	-- ---- smoke and embers
	local sh = mk({ Transparency = 1, Size = Vector3.new(1, 1, 1),
	                CFrame = CFrame.new(O.X, top + 1.8 * HS, O.Z), Parent = f })
	local sm = Instance.new("ParticleEmitter")
	sm.Texture = "rbxasset://textures/particles/smoke_main.dds"
	sm.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, PAL.SMOKE),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 148, 144)) })
	sm.Lifetime = NumberRange.new(3.4, 6.0); sm.Rate = 7
	sm.Speed = NumberRange.new(5, 11); sm.SpreadAngle = Vector2.new(18, 18)
	-- it keeps opening out the whole way up: smoke that stops growing reads as a column of
	-- fixed blobs rather than a plume
	sm.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2),
		NumberSequenceKeypoint.new(0.35, 8), NumberSequenceKeypoint.new(1, 17) })
	sm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.68), NumberSequenceKeypoint.new(1, 1) })
	sm.Acceleration = Vector3.new(0.7, 5, 0.2)
	sm.RotSpeed = NumberRange.new(-24, 24); sm.Parent = sh

	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(PAL.FLAME_H, PAL.EMBER)
	em.Lifetime = NumberRange.new(1.4, 3.0); em.Rate = 0
	em.Speed = NumberRange.new(5, 13); em.SpreadAngle = Vector2.new(46, 46)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.34),
		NumberSequenceKeypoint.new(1, 0.08) })
	em.LightEmission = 1; em.Acceleration = Vector3.new(0.8, 3.2, 0)
	em.Drag = 1.4
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.7, 0.3), NumberSequenceKeypoint.new(1, 1) })
	em.Parent = sh

	-- ash: dark flakes lifting off the pile, slower and heavier than the sparks. They read as
	-- the fire consuming something rather than just emitting light.
	local ash = Instance.new("ParticleEmitter")
	ash.Texture = "rbxasset://textures/particles/smoke_main.dds"
	ash.Color = ColorSequence.new(Color3.fromRGB(56, 50, 46), Color3.fromRGB(120, 114, 108))
	ash.Lifetime = NumberRange.new(2.2, 4.0); ash.Rate = 5
	ash.Speed = NumberRange.new(3, 7); ash.SpreadAngle = Vector2.new(55, 55)
	ash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22),
		NumberSequenceKeypoint.new(1, 0.1) })
	ash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.75, 0.45), NumberSequenceKeypoint.new(1, 1) })
	ash.Acceleration = Vector3.new(0.4, 2.2, 0); ash.Drag = 2.5
	ash.RotSpeed = NumberRange.new(-90, 90); ash.Parent = sh

	fireEmber, fireSmoke = em, sm

	if SOUND_FIRE ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = SOUND_FIRE; s.Looped = true; s.Volume = 0
		-- BOTH distances set. Only Max was being set before, leaving Min on the engine default -- fine by
		-- luck at 10, but silently wrong the moment FIRE_RANGE is retuned. Stating both keeps the "full
		-- volume at the seats, gone by 45 studs" shape explicit.
		s.RollOffMinDistance = FIRE_FULL
		s.RollOffMaxDistance = FIRE_RANGE; s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.Parent = sh
		pcall(function() s:Play() end)
		tween(s, 3, { Volume = FIRE_VOLUME })
	end

	-- ---- LIGHTING IT. Kindling smoulders and smokes, the coals come up, then it catches with
	-- a flare that overshoots and settles back. Everything arriving at once is the giveaway.
	task.spawn(function()
		sm.Rate = 24                                   -- damp smoke off the kindling first
		task.wait(1.1)

		for _, c in ipairs(fireCoals) do               -- the coals take
			tween(c.p, 1.6, { Color = PAL.EMBER })
			c.p.Material = Enum.Material.Neon
		end
		tween(fireGlow, 1.6, { Transparency = 0.86 })
		task.wait(0.7)

		-- THE CATCH. This used to fall back to SOUND_FIRE when SOUND_POP was empty, which made sense while
		-- SOUND_FIRE was unset. It does not now: SOUND_FIRE is a LOOPING CRACKLE that is already fading in
		-- on the fire itself, so reusing it here played a second, flat 2D copy of the same clip over the top
		-- of the positional one. A one-shot "whumph" belongs here or nothing does.
		playSound(SOUND_POP, 0.5)
		em:Emit(70)                                    -- the catch
		sm.Rate = 14
		em.Rate = 14

		local t0 = os.clock()
		while true do
			local e = os.clock() - t0
			if e >= 3.4 then break end
			local u = e / 3.4
			-- overshoot then settle: it flares as it catches, then finds its level
			fireLevel = math.min(1.35, (1 - (1 - u) ^ 3) * 1.35) - math.max(0, (u - 0.55)) * 0.78
			task.wait()
		end
		fireLevel = 1
	end)

	-- ---- the marshmallows toast: white -> golden, slowly, once the fire is properly going
	task.delay(4.0, function()
		for i, st in ipairs(sticks) do
			task.delay(i * 1.1, function()
				if not st.marsh then return end
				local parts = {}
				if st.marsh:IsA("BasePart") then parts = { st.marsh }
				else
					for _, d in ipairs(st.marsh:GetDescendants()) do
						if d:IsA("BasePart") then table.insert(parts, d) end
					end
				end
				for _, p in ipairs(parts) do tween(p, 11, { Color = PAL.TOAST }) end
				local mp = parts[1]
				if mp then                              -- a little sizzle as it browns
					local sz = Instance.new("ParticleEmitter")
					sz.Texture = "rbxasset://textures/particles/smoke_main.dds"
					sz.Color = ColorSequence.new(Color3.fromRGB(220, 216, 210))
					sz.Lifetime = NumberRange.new(0.9, 1.8); sz.Rate = 3
					sz.Speed = NumberRange.new(1.4, 3); sz.SpreadAngle = Vector2.new(24, 24)
					sz.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3),
						NumberSequenceKeypoint.new(1, 1.5) })
					sz.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8),
						NumberSequenceKeypoint.new(1, 1) })
					sz.Acceleration = Vector3.new(0.3, 2.5, 0); sz.Parent = mp
				end
			end)
		end
	end)
end

-- Each tongue is animated off a spine: the three blocks ride up it, drifting further out and
-- narrowing as they go, while the whole tongue leans and twists. Randomly one surges -- a
-- flame licking up higher than the rest -- which is most of what stops it looking like a loop.
RunService.RenderStepped:Connect(function(dt)
	if #fireBits == 0 then return end
	dt = math.min(dt or 0.016, 0.05)
	local t  = os.clock()
	local lv = fireLevel
	local gust = 1 + math.sin(t * 0.7) * 0.1 + math.sin(t * 1.9 + 2) * 0.06
	-- one wind vector for the whole fire, turning slowly. Flames, smoke and embers all lean
	-- with it, which is what ties them together as one fire instead of three effects.
	local wind = Vector3.new(math.sin(t * 0.23) + math.sin(t * 0.61) * 0.4, 0,
	                         math.cos(t * 0.17) + math.cos(t * 0.53) * 0.4) * 0.3

	for _, b in ipairs(fireBits) do
		-- A TONGUE IS BORN, RISES AND PINCHES OUT, then starts again somewhere slightly else.
		-- Flames that only sway read as ribbons on a fan; the turnover is what makes it burn.
		b.life += dt * b.rate
		if b.life >= 1 then
			b.life -= 1
			b.phase = math.random() * 6.28
			b.rate  = 0.42 + math.random() * 0.36
			local a = b.ang + (math.random() - 0.5) * 0.9
			local r = b.rad * (0.7 + math.random() * 0.6)
			b.base  = CFrame.new(fireO.X + math.cos(a) * r, fireTop, fireO.Z + math.sin(a) * r)
			b.out   = Vector3.new(math.cos(a), 0, math.sin(a))
		end
		local env = math.sin(b.life * math.pi) ^ 0.55        -- quick to rise, slow to die

		if b.surge > 0 then
			b.surge = math.max(0, b.surge - 0.028)
		elseif math.random() < 0.004 then
			b.surge = 1
		end
		local H = b.h * lv * gust * env
			* (1 + math.sin(t * 5.2 + b.phase) * 0.1 + b.surge * 0.55)
		local twist = t * (0.9 + b.tier * 0.25) + b.phase

		for k = 1, 3 do
			local p  = b.segs[k]
			if p.Parent then
				local up = (k - 0.5) / 3 * H
				local dr = (k / 3) ^ 1.6                     -- drift grows toward the tip
				-- convection draws the tips INWARD over the core while the wind pushes them
				-- along: that inward pull is why a real fire tapers to a point
				local pull = (b.out * -0.44 + wind) * dr * (0.6 + b.surge * 0.4)
				local wob  = Vector3.new(math.sin(t * 3.4 + b.phase + k) * 0.14 * dr, up,
				                         math.cos(t * 2.8 + b.phase + k * 0.8) * 0.14 * dr)
				p.CFrame = b.base * CFrame.new(wob + pull) * CFrame.Angles(0, twist, 0)
				local w = b.w * lv * env * (1 - (k - 1) * 0.34)
				p.Size = Vector3.new(math.max(0.05, w), math.max(0.05, H / 3 * 1.12),
				                     math.max(0.05, w))
			end
		end
	end

	-- every so often the fire spits: a crack, a scatter of embers and a kick in the light
	if fireEmber and lv > 0.6 and math.random() < 0.008 then
		fireEmber:Emit(12 + math.random(14))
		if fireLight then fireLight.Brightness = fireLight.Brightness + 1.6 end
	end
	if fireSmoke then
		fireSmoke.Acceleration = Vector3.new(wind.X * 7 + 0.6, 5, wind.Z * 7)
	end

	-- licks break off a random tongue's base, rise, and burn out on their own clock
	for _, k in ipairs(fireLicks) do
		k.life += dt * k.rate
		if k.life >= 1 then
			k.life -= 1
			local b = fireBits[math.random(#fireBits)]
			k.from = b and b.base.Position or Vector3.new(fireO.X, fireTop, fireO.Z)
			k.h    = (2.0 + math.random() * 2.2) * (fireHS or 1)
			k.sw   = (math.random() - 0.5) * 1.5
		end
		if k.from and lv > 0.3 then
			local u  = k.life
			local sc = math.sin(u * math.pi) ^ 0.8
			k.p.Transparency = 1 - 0.86 * sc * math.min(1, lv)
			k.p.Size   = Vector3.new(0.32 * sc + 0.04, (0.5 + u * 0.8) * sc + 0.04, 0.32 * sc + 0.04)
			k.p.Color  = PAL.FLAME_H:Lerp(PAL.EMBER, u)
			k.p.CFrame = CFrame.new(k.from + Vector3.new(
				k.sw * u + wind.X * u * 2.4, u * k.h, k.sw * 0.6 * u + wind.Z * u * 2.4))
				* CFrame.Angles(0, u * 6, 0)
		else
			k.p.Transparency = 1
		end
	end

	-- the white-hot base holds steady: it comes up with the fire and then stays put
	if fireCore then
		fireCore.Transparency = math.clamp(1 - 0.72 * math.min(1, lv), 0.28, 1)
	end

	-- the woodpile: charred underneath, sitting at a steady red heat. Wood this hot does not
	-- flicker -- the flames above it do, and reading a pulse into the logs as well made the
	-- whole pile look like it was being switched on and off.
	for _, l in ipairs(fireLogs) do
		if l.p.Parent then
			-- the core logs go NEON once the fire is properly alight, which is the difference
			-- between a log painted red and a log that is actually glowing
			if not l.hot and lv > 0.5 and l.glow > 0.78 then
				l.hot = true
				l.p.Material = Enum.Material.Neon
			end
			local char = l.base:Lerp(Color3.fromRGB(32, 24, 20), 0.72 * math.min(1, lv))
			l.p.Color  = char:Lerp(l.hot and PAL.FLAME or PAL.EMBER,
				l.glow * 0.92 * math.min(1, lv))
		end
	end

	-- the coals hold a steady heat too; only how far they have come up varies, with the fire
	for _, c in ipairs(fireCoals) do
		if c.p.Parent then
			c.p.Color = PAL.BARK_D:Lerp(PAL.EMBER, 0.35 + 0.65 * math.min(1, lv))
		end
	end

	if fireLight then
		local fl = math.sin(t * 11) * 0.5 + math.sin(t * 4.3 + 1.7) * 0.8 + math.sin(t * 23) * 0.22
		fireLight.Brightness = math.max(0, (2.9 + fl) * lv)
		fireLight.Range      = 26 + fl * 3.5
		fireLight.Color      = PAL.EMBER:Lerp(PAL.FLAME_H, 0.45 + fl * 0.18)
	end
	if fireLight2 then
		fireLight2.Brightness = math.max(0, (1.9 + math.sin(t * 2.7) * 0.5) * lv)
		fireLight2.Range      = 15 + math.sin(t * 1.6) * 2
	end
	if fireGlow and fireGlow.Parent and lv > 0 then
		fireGlow.Transparency = math.clamp(0.84 - math.min(1, lv) * 0.12, 0.6, 0.95)
	end
end)

-- ============================================================================
-- THE NPC -- paged bubble on a Talk prompt, same pattern as island 1
-- ============================================================================
local function npcHeadOf(d)
	return (d:IsA("Model") and (d:FindFirstChild("Head") or d.PrimaryPart
		or d:FindFirstChildWhichIsA("BasePart", true)))
		or (d:IsA("BasePart") and d) or nil
end

local function findNPCHead()
	if not firePart then return nil end
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		local match = false
		for _, w in ipairs(NPC_NAMES) do if norm(d.Name) == w then match = true; break end end
		if match then
			local h = npcHeadOf(d)
			if h then
				local dist = (h.Position - firePart.Position).Magnitude
				if dist <= NPC_MAX_DIST and (not bestD or dist < bestD) then best, bestD = h, dist end
			end
		end
	end
	return best
end

local function hideBubble(a)
	local prev = a:FindFirstChild("SpeechBubble"); if prev then prev:Destroy() end
end

function showBubble(a, text, persist, footer)
	hideBubble(a)
	local bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"; bb.Adornee = a; bb.Size = UDim2.new(0, 320, 0, 150)
	bb.StudsOffset = Vector3.new(0, 5.5, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local fr = Instance.new("Frame"); fr.Size = UDim2.fromScale(1, 1)
	fr.BackgroundColor3 = PAL.BUB_F; fr.BackgroundTransparency = 0.05; fr.BorderSizePixel = 0
	fr.Parent = bb
	Instance.new("UICorner", fr).CornerRadius = UDim.new(0, 18)
	local st = Instance.new("UIStroke"); st.Color = PAL.BUB_S; st.Thickness = 2
	st.Transparency = 0.4; st.Parent = fr
	local pd = Instance.new("UIPadding")
	pd.PaddingTop = UDim.new(0, 12); pd.PaddingBottom = UDim.new(0, 12)
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = fr
	local lb = Instance.new("TextLabel")
	lb.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	lb.BackgroundTransparency = 1; lb.Font = Enum.Font.FredokaOne; lb.Text = text
	lb.TextColor3 = PAL.BUB_T; lb.TextScaled = true; lb.TextWrapped = true; lb.Parent = fr
	local c1 = Instance.new("UITextSizeConstraint"); c1.MaxTextSize = 22; c1.Parent = lb
	if footer then
		local h = Instance.new("TextLabel")
		h.Size = UDim2.fromScale(1, 0.2); h.Position = UDim2.fromScale(0, 0.8)
		h.BackgroundTransparency = 1; h.Font = Enum.Font.FredokaOne; h.Text = footer
		h.TextColor3 = PAL.BUB_H; h.TextScaled = true; h.Parent = fr
		local c2 = Instance.new("UITextSizeConstraint"); c2.MaxTextSize = 14; c2.Parent = h
	end
	bb.Parent = a
	if not persist then
		task.delay(9, function()
			if bb and bb.Parent == a and bb.Name == "SpeechBubble" then bb:Destroy() end
		end)
	end
end

-- ============================================================================
-- GO
-- ============================================================================
-- WIRING -- prompts go on trees and mushrooms as they turn up
-- ============================================================================
local millPrompt
local treeList = {}

local function wireTree(tr)
	if tr:GetAttribute("SmoresWired") then return end
	local anchor = tr:IsA("BasePart") and tr or tr:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then return end                 -- still an empty shell; the sweep retries
	tr:SetAttribute("SmoresWired", true)
	-- NO PROMPT. Trees are registered and then cut by standing at them with the saw running.
	table.insert(treeList, { model = tr, anchor = anchor, hits = 0, down = false })
end

-- THE CHOP POINT. Not shown -- there is no target to aim at, you just swing. It is worked out
-- once per tree and kept because two things still need it: the chips have to fly from somewhere,
-- the tree has to know which way to go over. Chosen on the side you are stood on, so both come
-- out right without you having to think about it.
local function trunkR(t, bs)
	return math.clamp(math.min(bs.X, bs.Z) * 0.13, 0.5, 2.2)
end

local function chopPoint(t)
	if t.markCF or t.down then return end
	local base = t.model:IsA("Model") and t.model:GetPivot() or t.anchor.CFrame
	local _, bs = frameOf(t.model)
	local footY = base.Position.Y - bs.Y * 0.5

	-- on the side you are stood on, at about chest height -- where you would actually cut
	local hrp  = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local face = Vector3.new(0, 0, 1)
	if hrp then
		local v = Vector3.new(hrp.Position.X - base.Position.X, 0, hrp.Position.Z - base.Position.Z)
		if v.Magnitude > 0.5 then face = v.Unit end
	end
	local rad = trunkR(t, bs)
	local mid = Vector3.new(base.Position.X, footY + 2.6, base.Position.Z)
	t.markCF = CFrame.lookAt(mid + face * rad, mid + face * 40)
	t.markF  = face
	t.rad    = rad
end

-- A hit throws chips off the trunk at the chop point. Nothing is drawn ON the tree -- an
-- earlier version cut a dark wedge in there and it just read as a black smudge stuck to the
-- bark, so the hit is all particles now.
local function chipHit(t)
	chopPoint(t)
	if not t.markCF then return end
	local em, host = sawChips(t.markCF * CFrame.new(0, 0, 0.4))
	em:Emit(22); Debris:AddItem(host, 2)
end

-- Fell one tree. The fall is INTEGRATED like a real pendulum rather than played back off a
-- fixed curve: angular acceleration is proportional to sin(angle), so it creaks over slowly,
-- accelerates through the middle and slams down -- which is what a falling tree actually does.
-- A linear or eased tween always reads as an object being rotated.
--
-- On top of that it does the three things a rotation alone cannot: the hinge SPLINTERS, the
-- trunk SLIPS off its stump as it goes over, and it TWISTS on the way down.
local function fellTree(t)
	if t.down then return end
	t.down = true

	local pivot = t.model:IsA("Model") and t.model:GetPivot() or t.anchor.CFrame
	local _, bs = frameOf(t.model)
	local rad   = t.rad or trunkR(t, bs)
	-- hinge at the STUMP, not the centre, or the crown swings through the ground
	local hinge = CFrame.new(pivot.Position.X, pivot.Position.Y - bs.Y * 0.5, pivot.Position.Z)

	-- IT FALLS AWAY FROM THE CHOP POINT, which was fixed on the side you were stood on when
	-- you started swinging -- so the tree always goes away from you, for the right reason.
	local away = t.markF
	if not away then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		away = Vector3.new(0, 0, 1)
		if hrp then
			local v = Vector3.new(pivot.Position.X - hrp.Position.X, 0, pivot.Position.Z - hrp.Position.Z)
			if v.Magnitude > 0.5 then away = v.Unit end
		end
	else
		away = -away                                   -- it faces you, so the tree goes the other way
	end
	local axis = Vector3.new(0, 1, 0):Cross(away)
	if axis.Magnitude < 0.01 then axis = Vector3.new(1, 0, 0) end
	axis = axis.Unit

	local FULL = math.rad(85)
	local function place(th)
		local k    = math.clamp(th / FULL, 0, 1)
		-- the butt SLIPS off the stump as it goes over, and the trunk twists as it falls
		local slip = CFrame.new(away * (k * k * 1.4) + Vector3.new(0, -k * 0.5, 0))
		local newCF = slip * hinge * CFrame.fromAxisAngle(axis, th) * hinge:Inverse() * pivot
			* CFrame.Angles(0, k * 0.22, 0)
		if t.model:IsA("Model") then t.model:PivotTo(newCF) else t.anchor.CFrame = newCF end
	end

	task.spawn(function()
		-- 1. the creak: it leans, hangs there a moment, and only then goes
		for i = 1, 14 do
			place(math.rad(3.5) * (i / 14) + math.rad(0.5) * math.sin(i * 1.5))
			task.wait(0.03)
		end
		task.wait(0.25)

		-- 2. THE HINGE SPLINTERS. Wood does not pivot cleanly; it tears, and the torn fibres
		-- stay stood on the stump after the trunk has gone.
		local hs = t.markCF or (hinge * CFrame.new(0, 2.6, 0))
		for i = 1, 6 do
			local sp = mk({ Color = PAL.WOOD_L,
				Size = Vector3.new(0.16 + (i % 3) * 0.08, 0.7 + (i % 4) * 0.5, 0.16),
				CFrame = hs * CFrame.new((i - 3.5) * rad * 0.36, -0.3, -rad * 0.35)
					* CFrame.Angles(math.rad(-8 - i * 4), 0, math.rad((i - 3.5) * 7)),
				Parent = camp })
			sp.Material = Enum.Material.WoodPlanks
		end
		local em0, h0 = sawChips(hs)
		em0:Emit(26); Debris:AddItem(h0, 2)

		-- 3. the fall
		local th, w = math.rad(4), 0
		while th < FULL do
			local dt = math.min(task.wait(), 0.05)
			w  += 2.3 * math.sin(th) * dt          -- torque falls off as it nears flat
			th += w * dt
			place(math.min(th, FULL))
		end

		-- 4. the impact: chips along the whole length, a dust burst under the crown, and a
		-- kick through the camera if you are stood close enough to feel it
		local em, host = sawChips(CFrame.new(pivot.Position))
		em:Emit(30); Debris:AddItem(host, 2)
		for i = 1, 3 do
			local d = mk({ Transparency = 1, Size = Vector3.new(1, 1, 1),
				CFrame = CFrame.new(hinge.Position + away * (bs.Y * 0.3 * i)), Parent = camp })
			local de = Instance.new("ParticleEmitter")
			de.Texture = "rbxasset://textures/particles/smoke_main.dds"
			de.Color = ColorSequence.new(PAL.CHIP)
			de.Lifetime = NumberRange.new(0.8, 1.8); de.Rate = 0
			de.Speed = NumberRange.new(7, 18); de.SpreadAngle = Vector2.new(80, 80)
			de.Size = NumberSequence.new(4.5); de.Acceleration = Vector3.new(0, -8, 0)
			de.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45),
				NumberSequenceKeypoint.new(1, 1) })
			de.Parent = d; de:Emit(20)
			Debris:AddItem(d, 3)
		end

		local char = player.Character
		local hum  = char and char:FindFirstChildOfClass("Humanoid")
		local hrp2 = char and char:FindFirstChild("HumanoidRootPart")
		if hum and hrp2 and (hrp2.Position - hinge.Position).Magnitude < 90 then
			task.spawn(function()
				for i = 1, 12 do
					local k = 0.75 * (1 - i / 12)
					hum.CameraOffset = Vector3.new((math.random() - 0.5) * k,
					                               (math.random() - 0.5) * k, 0)
					task.wait(0.03)
				end
				hum.CameraOffset = Vector3.new()
			end)
		end

		for i = 1, 10 do
			place(FULL - math.rad(5) * math.sin(i / 10 * math.pi) * (1 - i / 12))
			task.wait(0.03)
		end
		place(FULL)

		-- 5. leave a stump where it stood -- A CUT TREE, NOT A PUCK. The old stump was one bark
		-- cylinder with a flat lid: it read as a coaster dropped on the grass. A real stump has
		-- root flares where it grips the ground, a pale cut face with GROWTH RINGS, and a rim
		-- torn ragged where the hinge fibres gave -- and the standing splinters from step 2 now
		-- read as part of it instead of floating beside a puck.
		local sr = math.max(0.9, rad)
		local sy = math.random() * math.pi          -- each stump turned its own way
		local sCF = CFrame.new(hinge.Position) * CFrame.Angles(0, sy, 0)
		-- the bark drum, slightly taller and very slightly tipped, like the tree tore off it
		mk({ Shape = Enum.PartType.Cylinder, Color = PAL.BARK_D, CanCollide = true,
			Size = Vector3.new(1.9, sr * 2, sr * 2),
			CFrame = sCF * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90 + 2)),
			Parent = camp })
		-- root flares: four flattened bark lumps around the base, gripping the ground
		for i = 1, 4 do
			local a = (i / 4) * math.pi * 2 + sy
			mk({ Color = PAL.BARK_D, CanCollide = true,
				Size = Vector3.new(sr * 0.7, 0.55, sr * 0.9),
				CFrame = sCF * CFrame.new(math.cos(a) * sr * 0.95, 0.22, math.sin(a) * sr * 0.95)
					* CFrame.Angles(math.rad(-14), -a, 0),
				Parent = camp })
		end
		-- the cut face: pale wood with two darker growth rings, staggered a hair so they never
		-- z-fight, and set a touch off-level like a hand-sawn cut
		local faceCF = sCF * CFrame.new(0, 1.66, 0) * CFrame.Angles(math.rad(2.5), 0, 0)
		mk({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_L,
			Size = Vector3.new(0.16, sr * 1.9, sr * 1.9),
			CFrame = faceCF * CFrame.Angles(0, 0, math.rad(90)), Parent = camp })
		mk({ Shape = Enum.PartType.Cylinder, Color = PAL.BARK_D,
			Size = Vector3.new(0.06, sr * 1.3, sr * 1.3),
			CFrame = faceCF * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)), Parent = camp })
		mk({ Shape = Enum.PartType.Cylinder, Color = PAL.BARK_D,
			Size = Vector3.new(0.06, sr * 0.6, sr * 0.6),
			CFrame = faceCF * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.rad(90)), Parent = camp })
		-- the ragged rim: bark shards standing proud where the trunk tore away
		for i = 1, 4 do
			local a = (i / 4) * math.pi * 2 + sy + 0.4
			mk({ Color = (i % 2 == 0) and PAL.BARK_D or PAL.WOOD_L,
				Size = Vector3.new(0.22, 0.5 + (i % 3) * 0.35, 0.3),
				CFrame = sCF * CFrame.new(math.cos(a) * sr * 0.88, 1.75, math.sin(a) * sr * 0.88)
					* CFrame.Angles(math.rad(6), -a, math.rad((i - 2.5) * 6)),
				Parent = camp })
		end

		-- 6. and it goes, Rust-style. Sink and fade together -- fading alone leaves a ghost
		-- lying there, sinking alone pops out of view at the last frame.
		task.wait(0.9)
		local parts = {}
		if t.model:IsA("BasePart") then parts = { t.model }
		else
			for _, d in ipairs(t.model:GetDescendants()) do
				if d:IsA("BasePart") then table.insert(parts, d) end
			end
		end
		for _, p in ipairs(parts) do tween(p, 1.3, { Transparency = 1 }) end
		local from = t.model:IsA("Model") and t.model:GetPivot() or t.anchor.CFrame
		for i = 1, 26 do
			local cf = from * CFrame.new(0, -(i / 26) * 3.2, 0)
			if t.model:IsA("Model") then t.model:PivotTo(cf) else t.anchor.CFrame = cf end
			task.wait(0.05)
		end
		hideThing(t.model, true)
	end)

	pickUp("log")
	if logsMilled + logsHeld >= LOGS_NEEDED then
		step = 2
		takeSaw()                                             -- chopping is done
		if millPrompt then millPrompt.Enabled = true end
	end
	refreshBanner()
end

-- the tree a swing would connect with: nearest, in reach, and roughly in front of you
local function targetTree()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local best, bestD
	for _, t in ipairs(treeList) do
		if not t.down and t.anchor.Parent then
			local to = t.anchor.Position - hrp.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			local d = flat.Magnitude
			if d <= CHOP_REACH and (d < 3 or flat.Unit:Dot(hrp.CFrame.LookVector) > 0.35) then
				if not bestD or d < bestD then best, bestD = t, d end
			end
		end
	end
	return best
end

-- ============================================================================
-- THE SAW CUTS BY ITSELF -- BUT TAPPING REVS IT AND BITES DEEPER
-- ============================================================================
-- It used to be click-to-swing (42 taps for the step), then a pure 7-second timer you stood and
-- watched -- 7 trees x 7s was 49 seconds of literally no input, the most boring block on the
-- island. The middle ground: standing in reach with the saw out still starts the cut and the
-- CHOP_SECONDS timer still guarantees the tree comes down with zero input -- but EVERY TAP lands
-- an extra swing that bites CHOP_BONUS seconds off the cut. A lively chopper drops a pine in
-- about 3 seconds; ignoring it entirely still works in 7. Skill makes it shorter, never longer.
--
-- THE TIMER IS THE TRUTH, not the swing count. Swings are the animation over the top of it, so a
-- dropped frame or a slow phone cannot make a tree take LONGER than seven seconds.
--
-- WALKING AWAY PAUSES IT, IT DOES NOT RESET IT. Losing five seconds of cutting because you
-- side-stepped a rock is the kind of punishment nobody reads as a rule; the progress stays on the
-- tree and picks up where it left off when you come back.
local CHOP_SECONDS = 7
local CHOP_BONUS   = 0.9     -- seconds of cut credited per tap (rate-limited to ~2 taps/s)

do
	local chopping, chopBar, chopFill, chopHost   -- block-scoped: the loop below owns all of it

	-- THE TAP. Any click/touch while a tree is being chopped lands an extra swing worth
	-- CHOP_BONUS seconds of cut. Rate-limited so a turbo-clicker chops fast, not instantly;
	-- gameProcessed taps (UI presses) and minigame time are ignored.
	local lastBonus = 0
	UserInputService.InputBegan:Connect(function(io, gp)
		if gp or mgBusy or step ~= 1 then return end
		if io.UserInputType ~= Enum.UserInputType.MouseButton1
			and io.UserInputType ~= Enum.UserInputType.Touch then return end
		local t = chopHost
		if not t or t.down then return end
		if os.clock() - lastBonus < 0.45 then return end
		lastBonus = os.clock()
		t.cut = (t.cut or 0) + CHOP_BONUS
		sawCutUntil = os.clock() + 0.4          -- a sharper, deeper bite on the rev
		playSound(SOUND_CHOP, 0.8)
		if _G.hapticPulse then pcall(_G.hapticPulse, "tick") end
		chipHit(t)
		if chopFill then                          -- the bar pops green so the tap visibly lands
			chopFill.BackgroundColor3 = Color3.fromRGB(140, 230, 110)
			task.delay(0.15, function()
				if chopFill then chopFill.BackgroundColor3 = Color3.fromRGB(226, 186, 86) end
			end)
		end
	end)

	-- the progress collar, drawn on the tree being cut. It is the only feedback that the seven
	-- seconds are going somewhere, and without it an auto-cut reads as a saw that is not biting.
	local function bar(t)
		if chopHost == t then return end
		if chopBar then chopBar:Destroy(); chopBar = nil end
		chopHost = t
		if not t then return end
		chopBar = Instance.new("BillboardGui")
		chopBar.Name = "ChopProgress"
		chopBar.Size = UDim2.new(0, 130, 0, 16)
		chopBar.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
		chopBar.AlwaysOnTop = true
		chopBar.Adornee = t.anchor
		chopBar.Parent = t.anchor
		local back = Instance.new("Frame")
		back.Size = UDim2.fromScale(1, 1); back.BackgroundColor3 = Color3.fromRGB(28, 24, 20)
		back.BackgroundTransparency = 0.25; back.BorderSizePixel = 0; back.Parent = chopBar
		Instance.new("UICorner").Parent = back
		chopFill = Instance.new("Frame")
		chopFill.Size = UDim2.new(0, 0, 1, 0)
		chopFill.BackgroundColor3 = Color3.fromRGB(226, 186, 86)
		chopFill.BorderSizePixel = 0; chopFill.Parent = back
		Instance.new("UICorner").Parent = chopFill
	end

	task.spawn(function()
		while true do
			local dt = task.wait(0.1)
			local t = (step == 1 and sawHeld and not mgBusy) and targetTree() or nil
			if not t then
				chopping = false
				if chopHost then bar(nil) end
			else
				bar(t)
				chopping = true
				t.cut = (t.cut or 0) + dt
				chopPoint(t)                              -- fixes the cut side on the first tick
				if chopFill then
					chopFill.Size = UDim2.new(math.clamp(t.cut / CHOP_SECONDS, 0, 1), 0, 1, 0)
				end

				-- a bite roughly every 0.55s, with the chips landing mid-bite so the bar
				-- visibly digs in before the trunk reacts. Purely the show; see the note above.
				if not t.nextSwing or os.clock() >= t.nextSwing then
					t.nextSwing = os.clock() + 0.55
					sawCutUntil = os.clock() + 0.55
					playSound(SOUND_CHOP, 0.7)
					if _G.hapticPulse then pcall(_G.hapticPulse, "tick") end
					task.delay(0.26, function()
						if t.down or not t.anchor.Parent then return end
						local em, host = sawChips(t.anchor.CFrame * CFrame.new(0, 1, 0))
						em:Emit(14); Debris:AddItem(host, 2)
						chipHit(t)
						-- the shudder up the trunk, on every swing that is not the felling one
						if (t.cut or 0) < CHOP_SECONDS then
							local base = t.model:IsA("Model") and t.model:GetPivot() or t.anchor.CFrame
							task.spawn(function()
								for i = 1, 6 do
									local k = math.sin(i / 6 * math.pi) * math.rad(1.6)
									local j = base * CFrame.Angles(k, 0, k * 0.5)
									if t.model:IsA("Model") then t.model:PivotTo(j) else t.anchor.CFrame = j end
									task.wait(0.03)
								end
								if t.model:IsA("Model") then t.model:PivotTo(base) else t.anchor.CFrame = base end
							end)
						end
					end)
				end

				if t.cut >= CHOP_SECONDS then
					bar(nil)
					chopping = false
					fellTree(t)
				end
			end
		end
	end)
end

-- ============================================================================
-- THE MALLOW PATCH -- picked after the last log is milled
-- ============================================================================
-- ⚠ YOUR PLANTS FIRST. There ARE hand-placed marshmallow plants on island14 -- the gather
-- step that used to wire them was deleted along with its 90-second hold-to-pull minigame, and
-- deleting the wiring orphaned the plants: they have been standing there unpickable ever
-- since. This scans for them by every plausible name before growing anything, so the step
-- runs on YOUR models and the built patch is only ever a fallback for a world without them.
--
-- 'marshmallowbig' is deliberately EXCLUDED: those three are the roasting mallows that go ON
-- the sticks, and letting this pick them would eat the props the finale needs.
--
-- Whatever it finds is named in the log, so if your plants are called something this misses,
-- that line says exactly what to add here.
local mallowPicks = {}

local function isMallowPlant(d)
	if not (d:IsA("Model") or d:IsA("BasePart")) then return false end
	local n = tostring(d.Name):lower():gsub("[%s_%-]", "")
	if n:find("big") then return false end                    -- the roasting mallows: hands off
	return n:find("mallowmushroom") ~= nil or n:find("mallowplant") ~= nil
		or n:find("marshmallowplant") ~= nil or n == "mallow" or n == "marshmallow"
		or (n:find("mallow") ~= nil and n:find("plant") ~= nil)
		or (n:find("mallow") ~= nil and n:find("shroom") ~= nil)
end

local function pickablePart(d)
	if d:IsA("BasePart") then return d end
	return topPartOf(d) or d:FindFirstChildWhichIsA("BasePart", true)
end

local function wireMallow(cap, owner)
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = "Pick"; pr.ObjectText = "Marshmallow"
	pr.HoldDuration = 0; pr.MaxActivationDistance = 12
	pr.RequiresLineOfSight = false; pr.Enabled = false; pr.Parent = cap
	pr.Triggered:Connect(function(plr)
		if plr ~= player or step ~= 3 then return end
		if shroomsHeld >= SHROOMS_NEEDED then return end
		pr.Enabled = false
		pickUp("cap")
		playSound(SOUND_POP, 0.6)
		if _G.hapticPulse then pcall(_G.hapticPulse, "tick") end
		-- ⚠ IT GOES THE INSTANT YOU PICK IT, and the POP is a separate throwaway part.
		--
		-- Two bugs lived in the old order (tween the real cap, hide it 0.32s later):
		--   1. hideThing SAVES the current Transparency in a SmoresT attribute so it can put
		--      the plant back. Running it AFTER the fade saved Transparency = 1, so any later
		--      restore would have returned the plant permanently invisible -- a plant that
		--      "comes back" as nothing.
		--   2. A BasePart plant (owner == nil) only had its Transparency set, so you could
		--      still walk into a marshmallow that was no longer there.
		-- Hiding first fixes both: the real values are captured while they are still real, and
		-- hideThing turns collision off with the visibility.
		hideThing(owner or cap, true)

		-- the pop is a copy, so nothing that animates can leave the real plant mid-tween
		local puff = mk({ Color = PAL.MALLOW, Size = cap.Size,
			CFrame = cap.CFrame, Parent = camp })
		pcall(function() Instance.new("SpecialMesh", puff).MeshType = Enum.MeshType.Sphere end)
		tween(puff, 0.3, { CFrame = puff.CFrame * CFrame.new(0, 3, 0), Transparency = 1 })
		Debris:AddItem(puff, 0.45)
		if shroomsHeld >= SHROOMS_NEEDED then
			step = 4
			-- quota met: put every remaining prompt away in one pass. Leaving a hundred live
			-- "Pick" prompts around a camp you have finished with is clutter you cannot act on.
			for _, other in ipairs(mallowPicks) do
				if other.Parent then other.Enabled = false end
			end
			refreshBanner()
			if npcHead then
				showBubble(npcHead, "That's the lot! Bring them here and I'll load the sticks.", false)
			end
		else
			refreshBanner()
		end
	end)
	mallowPicks[#mallowPicks + 1] = pr
end

local function buildMallowPatch()
	if #mallowPicks > 0 or not firePart then return end

	-- ---- 1. YOUR PLANTS -------------------------------------------------------------
	-- findAll(SHROOM_NAME) is the exact lookup the deleted gather step used, so this finds the
	-- same models it always did. The looser isMallowPlant sweep runs only as a second pass, for
	-- any plant named off-pattern.
	local found, seen = {}, {}
	for _, sh in ipairs(findAll(SHROOM_NAME, island)) do
		local cap = pickablePart(sh)
		if cap and not seen[cap] then
			seen[cap] = true
			found[#found + 1] = { cap = cap, owner = sh:IsA("Model") and sh or nil }
		end
	end
	for _, d in ipairs((island or Workspace):GetDescendants()) do
		if isMallowPlant(d) then
			local cap = pickablePart(d)
			if cap and not seen[cap] then
				seen[cap] = true
				found[#found + 1] = { cap = cap, owner = d:IsA("Model") and d or nil }
			end
		end
	end
	if #found > 0 then
		table.sort(found, function(a, b)
			return (a.cap.Position - firePart.Position).Magnitude
				< (b.cap.Position - firePart.Position).Magnitude
		end)
		-- ⚠ EVERY PLANT IS PICKABLE, not the first six. You only need SHROOMS_NEEDED, but
		-- WHICH ones you take is your choice -- capping the wiring at six meant the plants you
		-- happened to walk to were dead props with no prompt, which reads as broken scenery
		-- rather than as a quota already met. The quota is enforced in the handler; the world
		-- is simply all live.
		for _, f in ipairs(found) do wireMallow(f.cap, f.owner) end
		for _, pr in ipairs(mallowPicks) do pr.Enabled = true end
		print(("[Smores] %d '%s' plant(s) on the island -- ALL wired to pick; you need %d")
			:format(#mallowPicks, SHROOM_NAME, SHROOMS_NEEDED))
		return
	end

	-- ---- 2. FALLBACK: grow a patch, so a world without plants can still finish -------
	warn("[Smores] no marshmallow plants found on island14 -- growing a patch instead. "
		.. "Name your plants 'MallowPlant' (or 'MallowMushroom') and yours will be used.")
	local centre = firePart.Position
	for i = 1, SHROOMS_NEEDED do
		local a  = (i / SHROOMS_NEEDED) * math.pi * 2 + 0.6
		local r  = 26 + (i % 3) * 9
		local at = centre + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { player.Character, camp }
		local hit = Workspace:Raycast(at + Vector3.new(0, 90, 0), Vector3.new(0, -260, 0), rp)
		if hit then
			local base = hit.Position
			local m = Instance.new("Model"); m.Name = "MallowPick"; m.Parent = camp
			-- a stubby stem under a fat cap, so it reads as something growing rather than a
			-- marshmallow dropped on the grass
			mk({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_L,
			     Size = Vector3.new(1.1, 0.34, 0.34),
			     CFrame = CFrame.new(base + Vector3.new(0, 0.55, 0))
			         * CFrame.Angles(0, 0, math.rad(90)), Parent = m })
			local cap = mk({ Color = PAL.MALLOW, Size = Vector3.new(1.5, 1.5, 1.5),
			     CFrame = CFrame.new(base + Vector3.new(0, 1.55, 0))
			         * CFrame.Angles(0, a, 0), Parent = m })
			pcall(function() Instance.new("SpecialMesh", cap).MeshType = Enum.MeshType.Sphere end)
			mk({ Color = PAL.MALLOW, Size = Vector3.new(1.15, 1.15, 1.15),
			     CFrame = CFrame.new(base + Vector3.new(0, 2.45, 0))
			         * CFrame.Angles(0, a * 1.4, 0), Parent = m })
			m.PrimaryPart = cap

			wireMallow(cap, m)
		end
	end
	for _, pr in ipairs(mallowPicks) do pr.Enabled = true end
	print(("[Smores] mallow patch grown -- %d marshmallow(s) to pick around the camp")
		:format(#mallowPicks))
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	island = pollFor(findIsland, 90)

	-- Poll for a REAL PART, not just the name. island14 models replicate as empty shells
	-- before their parts arrive, so finding "campfire" proves nothing. The first version of
	-- this asked the shell for a BasePart, got nil, and the whole setup thread died on the
	-- spot -- which is why the mill, the marshmallows and the NPC all silently never happened.
	firePart = pollFor(function()
		local f = findOne(FIRE_NAME, island)
		if not f then return nil end
		if f:IsA("BasePart") then return f end
		return f:FindFirstChildWhichIsA("BasePart", true)
	end, 300)
	if not firePart then
		warn("[Smores] no usable part named 'campfire' -- quest inactive")
		return
	end
	-- KEEP THE WHOLE MODEL. firePart is just the first BasePart that happened to stream in,
	-- so sizing the fire off it gave a flame scaled to one log instead of to the woodpile.
	fireModel = findOne(FIRE_NAME, island) or firePart

	camp = Instance.new("Folder"); camp.Name = "CampSmores"; camp.Parent = Workspace
	print(("[Smores] campfire at (%.0f, %.0f, %.0f), island=%s")
		:format(firePart.Position.X, firePart.Position.Y, firePart.Position.Z,
		        island and island.Name or "?"))

	-- wait for a named thing to turn up AND actually have geometry
	local function pollSolid(key, secs)
		return pollFor(function()
			local o = findOne(key, island)
			if not o then return nil end
			if o:IsA("BasePart") then return o end
			return o:FindFirstChildWhichIsA("BasePart", true) and o or nil
		end, secs or 45)
	end
	-- ...and for a whole set of them, giving late arrivals a chance to show up
	local function pollMany(key, want, secs)
		local best = {}
		pollFor(function()
			local all = findAll(key, island)
			if #all > #best then best = all end
			return (#best >= want) or nil
		end, secs or 40)
		return best
	end

	-- ---- the chainsaw: COPY IT FIRST, while it still looks right, then hide the world one.
	-- Cloning after hiding would copy a transparent saw. A model called 'axe' is still accepted
	-- (SAW_LEGACY) so an island that has one placed keeps working -- 'chainsaw' simply wins, and
	-- the 40-second budget is split between the two rather than doubled.
	local sawSource = pollSolid(SAW_NAME, 20) or pollSolid(SAW_LEGACY, 20)
	if sawSource then
		sawTemplate = sawSource:Clone()
		hideThing(sawSource, true)
		print(("[Smores] chainsaw found ('%s') -- original hidden, copy kept for the player. Name "
			.. "its parts Grip/Bar/Tooth/Body/Exhaust to get the moving chain and the engine.")
			:format(sawSource.Name))
	else
		-- ⚠ NO HAND-PLACED SAW ON ISLAND14 -- BUILD ONE. This used to warn and carry on empty-
		-- handed ("chopping still works, you just will not hold one"), which is the one outcome
		-- nobody wants from a quest whose first instruction is "take the chainsaw": you walk up
		-- to a tree, pull the trigger, and the wood comes off with nothing in your hands.
		--
		-- Every other prop on this island already has a fallback if the world does not provide
		-- one. Same shape CarryView draws for OTHER players (see buildChainsaw there), so what
		-- you hold and what they see match.
		sawTemplate = Instance.new("Model")
		sawTemplate.Name = "Chainsaw"
		local function ap(nm, size, cf, colour, material)
			local p = Instance.new("Part")
			p.Name = nm; p.Size = size; p.CFrame = cf; p.Color = colour
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
			p.Material = material or Enum.Material.SmoothPlastic
			p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
			p.Parent = sawTemplate
			return p
		end
		-- ⚠ THE ORIGIN IS THE FIST. 'Grip' sits at 0,0,0 with its own -Z running out along the
		-- bar, gripFor() returns it verbatim, and every offset below therefore reads directly as
		-- "how far in front of your hand" (-Z) and "how far above it" (+Y). Do not re-centre this
		-- model on its bounding box: the whole point of a named grip is that nothing is guessed.
		local grip = ap("Grip", Vector3.new(0.34, 0.42, 0.85), CFrame.new(0, 0, 0.1),
			Color3.fromRGB(44, 44, 50))
		-- the engine block, ORANGE, because an orange body is the silhouette everybody already
		-- reads as "chainsaw" -- it does the job here that red does on a stop sign
		ap("Body",    Vector3.new(0.92, 1.02, 1.5), CFrame.new(0, 0.16, 1.0), PAL.FLAME)
		ap("Cover",   Vector3.new(0.96, 0.5, 0.9),  CFrame.new(0, 0.5, 0.75),
			Color3.fromRGB(232, 236, 240))
		ap("Exhaust", Vector3.new(0.3, 0.34, 0.34), CFrame.new(0.5, 0.5, 1.62), PAL.IRON_D,
			Enum.Material.Metal)
		ap("Pull",    Vector3.new(0.2, 0.2, 0.5),   CFrame.new(-0.5, 0.35, 1.72), PAL.MALLOW)
		ap("Trigger", Vector3.new(0.14, 0.24, 0.2), CFrame.new(0, -0.1, 0.42),
			Color3.fromRGB(28, 28, 32))
		-- the TOP HANDLE, the loop your other hand would be on. Three bits, because a single bar
		-- floating over the engine reads as a spare part rather than as a handle.
		ap("HandleT", Vector3.new(0.7, 0.16, 0.16),  CFrame.new(0, 0.95, 0.55),
			Color3.fromRGB(44, 44, 50))
		ap("HandleF", Vector3.new(0.16, 0.5, 0.16),  CFrame.new(0, 0.75, 0.05),
			Color3.fromRGB(44, 44, 50))
		ap("HandleB", Vector3.new(0.16, 0.42, 0.16), CFrame.new(0, 0.8, 1.05),
			Color3.fromRGB(44, 44, 50))
		-- HAND GUARD / CHAIN BRAKE. It is the piece that stops the saw reading as a hairdryer
		-- with a blade on it: a bare bar coming straight out of a box has nothing between it
		-- and the hand holding it.
		ap("Guard",   Vector3.new(0.9, 0.6, 0.14),  CFrame.new(0, 0.55, -0.22),
			Color3.fromRGB(232, 236, 240))
		-- ⚠ THE BAR IS FLAT AND ITS LONG AXIS IS Z. The chain loop reads Size.Y as the bar's
		-- height and Size.Z as its length to lay out the racetrack, so turning the bar in here
		-- takes the teeth off it.
		local bar = ap("Bar", Vector3.new(0.14, 0.5, 3.4), CFrame.new(0, 0.08, -1.6),
			PAL.IRON, Enum.Material.Metal)
		ap("BarStripe", Vector3.new(0.16, 0.16, 3.0), CFrame.new(0, 0.08, -1.6),
			Color3.fromRGB(238, 240, 244), Enum.Material.Metal)
		-- THE CHAIN. 22 teeth on a ~7-stud loop is one every third of a stud: close enough to
		-- read as a continuous chain at arm's length, few enough that driving them by hand every
		-- frame costs nothing. They are ANCHORED and unwelded on purpose -- see giveSaw. Every
		-- third one is a bright CUTTER, which is what makes the motion legible: 22 identical
		-- dark blocks going round look like a dark stripe that is not moving at all.
		for i = 1, 22 do
			local t = ap("Tooth", Vector3.new(0.2, 0.16, 0.22), bar.CFrame, PAL.IRON_D,
				Enum.Material.Metal)
			if i % 3 == 0 then t.Color = Color3.fromRGB(226, 230, 236) end
		end
		sawTemplate.PrimaryPart = grip
		print("[Smores] no 'chainsaw' or 'axe' in the world -- built one, so the quest still hands "
			.. "you a tool. Name a model 'chainsaw' on island14 to use your own instead.")
	end

	-- ---- the giant marshmallows: hidden until their stick is loaded
	marshParts = pollMany(MARSH_NAME, 3, 40)
	for _, m in ipairs(marshParts) do hideThing(m, true) end
	print(("[Smores] %d '%s' found and hidden"):format(#marshParts, MARSH_NAME))

	-- ---- the mill
	millPart = pollSolid(MILL_NAME, 40)
	if millPart then
		millPrompt = buildMill(millPart)
		print("[Smores] cutting station built on the 'mill' block -- logs split at the blade "
		.. "and stack on the out-rack")
	else
		warn("[Smores] no block named 'mill' found -- no cutting station")
	end

	-- ---- trees and mushrooms
	for _, tr in ipairs(pollMany(TREE_NAME, LOGS_NEEDED, 40)) do wireTree(tr) end
	-- say it once, at boot, rather than leaving you to notice mid-quest that cuts 4..7 raise
	-- nothing by the fire
	task.delay(6, function()
		if #sticks > 0 and #sticks < LOGS_NEEDED then
			warn(("[Smores] %d log(s) to mill but only %d '%s' part(s) in the world -- cuts %d..%d "
				.. "will raise no stick. Add %d more by the fire for one stick per log.")
				:format(LOGS_NEEDED, #sticks, STICK_NAME, #sticks + 1, LOGS_NEEDED,
					LOGS_NEEDED - #sticks))
		end
	end)
	print(("[Smores] %d tree(s) wired"):format(#treeList))

	-- ---- your roasting sticks, hidden until the mill cuts them
	for _, sp in ipairs(pollMany(STICK_NAME, 3, 40)) do wireStick(sp) end
	pairSticks()
	print(("[Smores] %d '%s' found and hidden"):format(#sticks, STICK_NAME))

	-- ---- KEEP LOOKING. island14 hands the rest of itself over as you walk around it, so
	-- anything arriving late still gets hidden and wired instead of being missed.
	task.spawn(function()
		for _ = 1, 60 do
			task.wait(3)
			for _, tr in ipairs(findAll(TREE_NAME, island))   do wireTree(tr) end
			for _, mm in ipairs(findAll(MARSH_NAME, island)) do
				local known = false
				for _, k in ipairs(marshParts) do if k == mm then known = true; break end end
				if not known then
					table.insert(marshParts, mm)
					hideThing(mm, true)
					print("[Smores] a marshmallow streamed in late -- hidden")
				end
			end
			for _, sp in ipairs(findAll(STICK_NAME, island)) do wireStick(sp) end
			pairSticks()
		end
	end)

	-- ---- the operator's stand
	task.spawn(function()
		local sp = pollFor(function()
			local d = findOne(STAND_NAME, island)
			if not d then return nil end
			if d:IsA("BasePart") then return d end
			return d:FindFirstChildWhichIsA("BasePart", true)
		end, 90)
		if sp then buildStand(sp) else print("[Smores] no part named 'stand' -- skipped") end
	end)

	-- ---- mill delivery -> saw -> sticks fly to the fire
	if millPrompt then
		-- ONE LOG AT A TIME. You pull the lever, saw that log through the blade yourself, and
		-- one stick comes up by the fire. Then you feed the next one in.
		millPrompt.Triggered:Connect(function(plr)
			if plr ~= player or milling or logsHeld == 0 then return end
			milling = true
			millPrompt.Enabled = false
			dropOne("log")
			logsHeld -= 1
			millLeft = MILL_STROKES
			refreshBanner()

			task.spawn(function()
				-- millBlade is a MODEL now, so it has no .CFrame -- use the stored shaft frame
				local em, host = sawChips(millBladeCF or CFrame.new())
				if millLever then                          -- throw the lever to start it
					millLever:PivotTo(millLeverCF * CFrame.Angles(0, 0, math.rad(-52)))
				end
				-- THE CARRIAGE ONLY MOVES WHEN YOU LAND A STROKE. It chases the target rather
				-- than snapping to it, so each stroke reads as a shove of the log into the blade.
				-- TWO HALVES, flush to start with. They part company at the blade.
				local lgA, lgB = buildLogHalf(-1), buildLogHalf(1)
				local spawnCF = millCradle * CFrame.Angles(0, math.rad(90), 0)
				lgA:PivotTo(spawnCF); lgB:PivotTo(spawnCF)
				local target, shown, running = 0, 0, true
				task.spawn(function()
					while running do
						spinMill(0.22)                    -- blade and flywheel on the one shaft
						shown += (target - shown) * 0.11
						local ride = millCradle:Lerp(millOut, math.clamp(shown, 0, 1))
						local rideCF = ride * CFrame.Angles(0, math.rad(90), 0)
						-- ⚠ THE SPLIT. The blade sits at the middle of the run, so anything past
						-- shown = 0.5 has been through it: the two halves ease apart from there,
						-- and their pale sawn faces come into view as they separate. That is the
						-- whole point of the machine, and it was the one thing not shown.
						local past = math.clamp((shown - 0.5) / 0.5, 0, 1)
						local gap = past * 0.55
						lgA:PivotTo(rideCF * CFrame.new(0, past * 0.06, -gap))
						lgB:PivotTo(rideCF * CFrame.new(0, past * 0.06, gap))
						if millCarriage then millCarriage:PivotTo(ride) end
						-- the saw rises with the blade rather than firing once at the top of the
						-- job: this loop already runs every frame the log is in the machine, so it
						-- is the honest place to own the volume
						if millSnd then
							millSnd.Volume += (0.96 - millSnd.Volume) * 0.12
							-- pitch sags with the same load the blade slows on: a saw biting
							-- into wood drops in tone, and hearing that is half of why a cut
							-- feels like effort rather than a timer
							local wantP = 1 - millLoad * 0.3
							millSnd.PlaybackSpeed += (wantP - millSnd.PlaybackSpeed) * 0.15
						end
						task.wait()
					end
					-- ...and spins down after the last stroke instead of stopping dead
					if millSnd then
						for _ = 1, 30 do
							if millSnd.Volume <= 0.01 then break end
							millSnd.Volume = math.max(0, millSnd.Volume - 0.05)
							task.wait(0.03)
						end
						millSnd.Volume = 0
					end
				end)

				playSaw(MILL_STROKES, function(p)
					target   = p
					millLeft = math.max(0, MILL_STROKES - math.floor(p * MILL_STROKES + 0.5))
					refreshBanner()
					millLoad = 1                     -- this stroke is biting: bog the blade down
					em:Emit(16)
					if millDust then millDust:Emit(12) end
				end)

				task.wait(0.5)                            -- let the carriage finish its run out
				running = false
				-- ⚠ THE HALVES STAY, ON THE OUT-RACK. They used to be destroyed the instant the
				-- cut finished, so the rack was permanently empty and seven cuts left no trace
				-- anywhere -- the machine ate logs. Stacking them means the pile IS the progress
				-- bar: you can see how many you have done without reading the banner.
				stackCut(lgA, lgB, logsMilled)
				-- the heap under the blade gets a little wider and taller with every log
				if millSawdust then
					local g = math.min(logsMilled + 1, LOGS_NEEDED)
					millSawdust.Size = Vector3.new(1.6 + g * 0.34, 0.3 + g * 0.12, 1.6 + g * 0.3)
					millSawdust.CFrame = CFrame.new(millSawdust.Position.X,
						millSawdust.Position.Y, millSawdust.Position.Z)
						* (millSawdust.CFrame - millSawdust.Position)
				end
				if millCarriage then millCarriage:PivotTo(millCradle) end
				Debris:AddItem(host, 2)
				if millLever then millLever:PivotTo(millLeverCF * CFrame.Angles(0, 0, math.rad(16))) end

				logsMilled += 1
				milling = false
				pairSticks()
				raiseStick(logsMilled)                    -- one cut, one stick up by the fire
				refreshBanner()

				if logsMilled >= LOGS_NEEDED then
					-- ===== LAST STICK CUT -> STRAIGHT OUT TO PICK THE MALLOWS =====
					-- shroomsHeld used to be credited in full here, so the mallows appeared in
					-- your pack having never been touched. The patch is grown instead and the
					-- picking is the step: sticks up, now go and fill them.
					step = 3
					shroomsHeld = 0
					if millPrompt then millPrompt.Enabled = false end
					buildMallowPatch()
					refreshBanner()
					if npcHead then
						showBubble(npcHead, "Sticks are up! Now pick me some mallows -- they grow round the camp.", false)
					end
				else
					millPrompt.Enabled = (logsHeld > 0)
					if npcHead and logsHeld == 0 then
						showBubble(npcHead, "That is one. Fetch me another log.", false)
					end
				end
			end)
		end)
	end

	-- ---- the NPC
	local function startQuest()
		if questAccepted then return end
		questAccepted = true; step = 1
		nightSet(true)                       -- NIGHT FALLS with the quest
		giveSaw()
		buildBackpack()
		refreshBanner()
		if _G.NotifyCenter then pcall(function() _G.NotifyCenter.push({
			text = "\xF0\x9F\x8C\x99 Night's falling on the camp -- the firelight is safe, the treeline isn't!",
			color = PAL.FLAME }) end) end
	end

	-- THIS ISLAND'S NPC, not somebody else's. There are several models called "Candy Npc" in
	-- this place -- island 13 has one, and there is another parented straight to Workspace --
	-- so a plain Workspace-wide search could easily wire the wrong quest giver.
	--
	-- Look INSIDE island14 first and take that unconditionally. Only if the island has none of
	-- its own do we fall back to a proximity search, and even then it has to be within
	-- NPC_MAX_DIST of this campfire.
	local function npcIn(scope, needDist)
		local best, bestD
		for _, d in ipairs(scope:GetDescendants()) do
			local match = false
			for _, w in ipairs(NPC_NAMES) do if norm(d.Name) == w then match = true; break end end
			if match then
				local h = npcHeadOf(d)
				if h then
					local dist = (h.Position - firePart.Position).Magnitude
					if (not needDist or dist <= NPC_MAX_DIST) and (not bestD or dist < bestD) then
						best, bestD = h, dist
					end
				end
			end
		end
		return best
	end

	npcHead = pollFor(function()
		if island then
			local mine = npcIn(island, false)
			if mine then return mine end
		end
		return npcIn(Workspace, true)
	end, 45)

	if not npcHead then
		warn(("[Smores] no 'Candy Npc' within %d studs of the campfire -- starting anyway")
			:format(NPC_MAX_DIST))
		startQuest()
	else
		print(("[Smores] Candy Npc wired -- %.0f studs from the campfire")
			:format((npcHead.Position - firePart.Position).Magnitude))

		local pages, index = nil, 0
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Talk"; prompt.ObjectText = "Candy Npc"; prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false
		prompt.Parent = npcHead

		local function pagesFor()
			if step >= 5 then
				return { "Best night this camp has had in years.", "Sit. Have one. \xF0\x9F\x8D\xA1" }
			elseif step == 4 then
				if shroomsHeld > 0 then return { "Hand them over, I will load the sticks." } end
				return { ("%d of %d sticks loaded. Keep going!"):format(loaded, #sticks) }
			elseif step == 2 then
				return { "Good chopping!",
				         "At the Lumber Mill, hold Load the Mill." }
			elseif step == 1 then
				return { ("%d pines needed. %d down so far."):format(LOGS_NEEDED, logsMilled + logsHeld),
				         "Stand at a pine and TAP to rev!",
				         "Watch the treeline. Something's out there..." }
			end
			-- the amounts come from the constants so the camper can never ask for the wrong job
			return {
				"Good night for it. And I mean NIGHT.",
				("Take my chainsaw. Fell %d pine trees."):format(LOGS_NEEDED),
				"Hold Load the Mill on each log.",
				"Then come back. Stay near the light!",
			}
		end

		local function closeIt()
			hideBubble(npcHead); prompt.ActionText = "Talk"; index = 0; pages = nil
		end

		prompt.Triggered:Connect(function(plr)
			if plr ~= player then return end

			-- handing the mallows over is this SAME prompt, so there is no second one to hunt for
			if step == 4 and shroomsHeld > 0 then
				local give = shroomsHeld
				dropAll("cap")
				shroomsHeld = 0
				local per = math.max(1, math.floor(SHROOMS_NEEDED / math.max(1, #sticks)))
				task.spawn(function()
					for _ = 1, math.floor(give / per) do
						local st = sticks[loaded + 1]
						if st and st.marsh and not st.done then
							st.done = true
							loaded += 1
							hideThing(st.marsh, false)
							local mp = st.marsh:IsA("BasePart") and st.marsh or topPartOf(st.marsh)
							if mp then
								local pe = Instance.new("ParticleEmitter")
								pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
								pe.Color = ColorSequence.new(PAL.MALLOW)
								pe.Lifetime = NumberRange.new(0.5, 1); pe.Rate = 0
								pe.Speed = NumberRange.new(3, 8); pe.SpreadAngle = Vector2.new(180, 180)
								pe.Size = NumberSequence.new(0.6); pe.LightEmission = 0.6
								pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1),
									NumberSequenceKeypoint.new(1, 1) })
								pe.Parent = mp; pe:Emit(30); Debris:AddItem(pe, 2)
							end
							playSound(SOUND_POP, 0.6)
						end
						refreshBanner()
						task.wait(0.8)
					end

					local all = (#sticks > 0)
					for _, st in ipairs(sticks) do if not st.done then all = false end end
					if all and step < 5 then
						step = 5
						refreshBanner()
						showBubble(npcHead, "That is the lot. Stand back!", false)
						task.delay(1.4, function()
							igniteFire()
							local ce = ReplicatedStorage:FindFirstChild("CoinEvent")
							if ce then pcall(function() ce:FireServer(COIN_REWARD) end) end
							_G.smoresQuestComplete = true
							-- PAYOFF SHOT. The same camera move island 3's cookie gets, from the shared RevealCommand:
							-- it resolves island 14's subject from that file's TARGETS table, so the framing lives in ONE
							-- place and re-aiming this island later is an edit there, not here.
							--
							-- Delayed, because the thing worth looking at does not exist yet at this line -- the world
							-- changes on completion (island 11's MineShaft is CREATED by the blast) and a camera that
							-- arrives first frames the before shot. playReveal is also silent when the target is missing
							-- and refuses to run on top of itself, so a quest that reaches this twice cannot double up.
							task.delay(0.9, function()
								if _G.revealIsland then pcall(_G.revealIsland, 14) end
							end)
							print(("[Smores] QUEST COMPLETE -- +%d coins"):format(COIN_REWARD))
						end)
					end
				end)
				return
			end

			if index == 0 then pages = (_G.capBubble and _G.capBubble(pagesFor())) or pagesFor() end
			index += 1
			if not pages or index > #pages then closeIt(); return end
			if index == 3 and step == 0 then startQuest() end   -- the page where he hands the saw over
			local last = index >= #pages
			-- no "[E] ..." badge in the bubble: the ProximityPrompt IS the E prompt, and the
			-- page count rides its ActionText instead of a second floating HUD
			showBubble(npcHead, pages[index], true, nil)
			prompt.ActionText = last and "Close" or ("Continue  (%d/%d)"):format(index, #pages)
		end)
		prompt.PromptHidden:Connect(function() if index ~= 0 then closeIt() end end)
	end

	refreshBanner()
	print("[Smores] ready -- night -> chop -> mill -> deliver -> ignite -> dawn")
	-- RETAINER SIGNAL: the quest reached the end of its build with its world objects up. QuestRetainer
	-- watches this flag; anything still false once its island has streamed in gets force-streamed and
	-- re-run. It is set HERE, at the ready print, not at the top of the file -- a quest that bailed
	-- early on a missing marker must NOT look built. See QuestRetainer.client.luau.
	_G.questBuilt_smores = true
end)

-- ============================================================================
-- /complete -- test command: finish the campsite instantly
-- ============================================================================
-- Island-scoped, the same as the other quests: typed anywhere else it does nothing, so it
-- can never light island 14's fire from across the map.
local function onCommand(msg)
	-- DEV ONLY. QuestDevGate publishes this; read at command time so load order cannot matter,
	-- and nil (gate not up yet) refuses. Without it any player could type their way to the whole realm.
	if not _G.questDevOK then return end
	local cmd = tostring(msg or ""):lower()

	-- ---- /wood : skip the CHOP, keep the MILL ------------------------------------------
	-- Deliberately NOT a second /complete. Felling seven pines is the long repetitive half of
	-- this quest and the part you do not want to redo every time you test the mill -- but the
	-- mill is the half worth watching, so this hands over the logs and stops. It leaves you at
	-- step 2 with a full pack, exactly as if you had just felled the last tree yourself.
	if cmd:sub(1, 5) == "/wood" then
		local hrpW = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not (firePart and firePart.Parent and hrpW) then return end
		if (hrpW.Position - firePart.Position).Magnitude > 420 then return end
		if step >= 3 or logsMilled >= LOGS_NEEDED then
			print("[Smores][TEST] /wood -- the chopping step is already behind you")
			return
		end
		questAccepted = true
		takeSaw()
		-- Fell every pine that is still standing, so the WORLD matches the inventory. Logs in
		-- hand beside a forest of untouched trees is a state the quest can never reach on its
		-- own, and inconsistent world state is exactly what makes a later bug hard to read.
		-- fellTree already no-ops on an already-down tree, so this needs no guard of its own.
		local felled = 0
		for _, t in ipairs(treeList) do
			if not t.down then
				felled += 1
				pcall(fellTree, t)
			end
		end
		-- pickUp(), not `logsHeld = N`: it is what keeps the carried list, the backpack display
		-- and the banner in step with each other. CARRY_MAX is 8 and LOGS_NEEDED is 7, so a
		-- full load fits -- but it is capped on the pack's own answer rather than that
		-- assumption, so raising LOGS_NEEDED past the backpack cannot silently lose logs here.
		local got = 0
		while logsHeld + logsMilled < LOGS_NEEDED do
			if not pickUp("log") then break end
			got += 1
		end
		step = 2
		if millPrompt then millPrompt.Enabled = true end
		refreshBanner()
		print(("[Smores][TEST] /wood -- %d tree(s) felled, %d log(s) in hand. Mill them at the "
			.. "cutting station."):format(felled, got))
		return
	end

	if cmd:sub(1, 9) ~= "/complete" then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (firePart and firePart.Parent and hrp) then return end
	if (hrp.Position - firePart.Position).Magnitude > 420 then return end
	if step >= 5 then return end

	questAccepted = true
	takeSaw()
	dropAll("log"); dropAll("cap")
	logsHeld, shroomsHeld = 0, 0
	logsMilled = LOGS_NEEDED
	if millPrompt then millPrompt.Enabled = false end
	step = 5
	refreshBanner()

	-- run it as the sequence, not as a snap to the end state: the sticks come up, the
	-- marshmallows land on them, and only then does it light. Skipping straight to a lit fire
	-- would hide exactly the bits worth checking.
	task.spawn(function()
		pairSticks()
		for i = 1, #sticks do
			raiseStick(i)
			task.wait(0.35)
		end
		task.wait(0.5)
		for _, st in ipairs(sticks) do
			if st.marsh and not st.done then
				st.done = true
				loaded += 1
				hideThing(st.marsh, false)
				playSound(SOUND_POP, 0.6)
				task.wait(0.35)
			end
		end
		refreshBanner()
		task.wait(0.6)
		igniteFire()
		local ce = ReplicatedStorage:FindFirstChild("CoinEvent")
		if ce then pcall(function() ce:FireServer(COIN_REWARD) end) end
		_G.smoresQuestComplete = true
		-- PAYOFF SHOT. The same camera move island 3's cookie gets, from the shared RevealCommand:
		-- it resolves island 14's subject from that file's TARGETS table, so the framing lives in ONE
		-- place and re-aiming this island later is an edit there, not here.
		--
		-- Delayed, because the thing worth looking at does not exist yet at this line -- the world
		-- changes on completion (island 11's MineShaft is CREATED by the blast) and a camera that
		-- arrives first frames the before shot. playReveal is also silent when the target is missing
		-- and refuses to run on top of itself, so a quest that reaches this twice cannot double up.
		task.delay(0.9, function()
			if _G.revealIsland then pcall(_G.revealIsland, 14) end
		end)
		print(("[Smores][TEST] /complete -- campsite finished, +%d coins"):format(COIN_REWARD))
	end)
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
