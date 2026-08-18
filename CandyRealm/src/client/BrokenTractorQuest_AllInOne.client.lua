--======================================================================
-- BrokenTractorQuest_AllInOne.client.lua  (LocalScript)  -- CandyRealm
--======================================================================
-- ISLAND 19 -- "BROKEN TRACTOR"
--
--   1. FIND     five missing tractor parts scattered around the island
--   2. FIT      carry each one back and drop it into its socket on the tractor
--   3. REPAIR   turn the key -- the engine catches on the third try, not the first
--   4. HARVEST  drive it through the wheat field and cut a section
--   5. DELIVER  drive the loaded trailer to the barn and tip it
--
--   Reward: coins (CoinEvent) plus crate tokens and a fart-power top-up, both once ever
--   through IslandTaskTokens' ledger.
--
-- ===== BUILT ON THE ISLAND 18 PATTERN, DELIBERATELY =====
-- Same placement-block convention (a block gives POSITION and SIZE, then hides itself), same
-- boundary handling, same collision-checked scatter, same "...Objective" banner name that
-- ObjectiveBannerBridge mirrors, same big custom E prompts sized off the model's far edge, and
-- the same hard rule that EVERYTHING IS ANCHORED -- including what you carry and the tractor
-- you drive. Nothing in this quest is ever simulated by physics.
--
-- ⚠ ISLAND 19 IS OFF THE LADDER, like 16 and 18: not in IslandOrder.SLOT_TO_ISLAND, so no
-- crossing leads to it and IslandLayout leaves it where Studio has it. It is in
-- IslandStreaming's EXTRA_PERSIST so its parts still replicate at distance.
--
-- ===== BLOCKS IT LOOKS FOR (all optional except the island itself) =====
--   "Tractor"      -- where the tractor sits. A MODEL is adopted as-is; a PART is a placement
--                     block and a tractor is built on it. No block -> built near the field.
--   "WheatField"   -- the area the wheat grows in. No block -> a patch beside the tractor.
--   "Farm House"   -- where the harvest is delivered ("Barn" also works). A part or a model,
--                     adopted exactly as it stands. NOTHING IS GENERATED any more: with no such
--                     building the quest says so in the log and cannot be finished.
--   The harvest is a TWO-STOP journey: cut straw goes to the HAY BALE FACTORY (its own script,
--   HayBaleFactory.client.lua, which publishes _G.hayFactory), is pressed into bales at the
--   console there, and the bales come back on the trailer for the farm house.
--   ONE MARKER PER MISSING PART, and there is NO auto-placement any more -- a part with no
--   marker is a warning in the log and does not spawn at all. Name a small part after the part
--   it stands for (case, spaces, underscores and hyphens are ignored):
--       "BackWheel"      (or Wheel / RearWheel / TractorWheel)
--       "SparkPlug"      (or Plug / Engine / Spark)
--       "Piston"         (or ConRod)
--       "Radiator"       (or Rad)
--       "SteeringWheel"  (or Steering / SteerWheel)
--   "TractorPart"  -- the old generic spot. Still works: unclaimed ones are handed out, left to
--                     right, to any part that has no marker of its own.
--   Markers keep their ROTATION: turn one in Studio and the part lies the way you turned it. All
--   of them are hidden at runtime (invisible, no collision) and never destroyed.
--   "FixTractor"   -- the REPAIR BAYS you carry each part to, matched left to right (X, then Z).
--                     Five are used, spares are hidden, none -> the sockets ride on the machine.
--   "placement boundaires" / "placement boundaries" -- where props may be scattered.
--   any *Npc* model -- the quest giver. None -> the tractor gives the quest itself.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")
local UserInputService  = game:GetService("UserInputService")
local PromptService     = game:GetService("ProximityPromptService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

print("[Tractor] >>> Broken Tractor (island19) -- v6: broken-down look (smoke/sparks/missing wheel), barn HUD + E prompt, hop-off no longer launches you, your WheatPlant parts are the crop. <<<")

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_NAME   = "island19"
local TRACTOR_NAME  = "tractor"
local FIELD_NAME    = "wheatfield"
local BARN_NAME     = "barn"
local PART_NAME     = "tractorpart"
local CROP_NAME     = "wheatplant"   -- YOUR crop: any part named this is what the tractor cuts
local BOUND_NAMES   = { placementboundaires = true, placementboundaries = true, placementboundary = true }

local PART_COUNT    = 5
local WHEAT_TARGET  = 40         -- stalks that count as "a section". Lowered automatically
                                 -- if the field could not fit that many (see buildField).
local PICKUP_RANGE  = 12
local TALK_DISTANCE = 12
local BANNER_RANGE  = 420
local IGNITION_TRIES = 3         -- turns of the key before it catches

-- driving. AUTO-FORWARD: the tractor always rolls, you only ever steer. One axis of control
-- behaves identically on a keyboard, a phone and a controller, and a player can never strand
-- themselves nose-first into a fence with no idea which key backs up.
local DRIVE_SPEED   = 22         -- studs/sec

-- ===== CHASE CAMERA -- tune these three =====
-- CAM_OFFSET is in the tractor's own space: +Y is up, +Z is BEHIND it (Roblox faces -Z), so
-- this sits 22 up and 26 back. Together with CAM_LOOK_HEIGHT that puts the machine slightly
-- below screen centre filling roughly a quarter of the height, looking down at about 30 degrees.
-- Raise Y or drop CAM_LOOK_HEIGHT to angle further down; increase Z to pull further back.
local CAM_OFFSET      = CFrame.new(0, 22, 26)
local CAM_LOOK_HEIGHT = 3        -- aims at the tractor's position + this, not at its feet
local CAM_ALPHA       = 0.15     -- per-frame lerp: lower trails more, 1 snaps

-- How high the tractor's root rides above whatever ground is under it. Used BOTH when it is
-- built and every frame while it drives -- they must be the same number or it jumps the moment
-- the engine starts.
local SEAT_HEIGHT     = 3.2
-- ...but an ADOPTED model keeps the height YOU built it at, measured once on adoption. Forcing
-- a hand-made tractor to the script's 3.2 would drop it into the ground or lift it off the
-- grass the instant the engine started.
local tractorSeatH    = SEAT_HEIGHT

-- ===== WHICH WAY IS THE FRONT? =====
-- Roblox has no idea which end of your model is the nose, and everything here has to agree on
-- one answer: the chase camera, the direction it drives, which wheels steer, and which side you
-- get out on. Rather than guess, they all read this ONE number -- how far the model's front is
-- rotated from its own -Z, counter-clockwise seen from above.
--
--     0     the front faces -Z          (the script's own built tractor)
--    90     rotated a quarter turn CCW  <-- your model
--   180     it drives backwards
--   270     a quarter turn the other way
--
-- Change this rather than rotating anything by hand: rotating the model in Studio moves the
-- wheels' recorded offsets with it, so the two stay consistent either way, but this is one edit.
local TRACTOR_YAW = math.rad(90)


-- ===== AUDIO =====
-- "" means silent and nothing is created, which is the house rule in every quest here.
local SOUND_BOARD = "rbxassetid://87077584566641"   -- climbing into the cab
-- The cutting bar going through the crop. LOOPED and volume-faded rather than fired per stalk:
-- a full field is 121 plants and a one-shot each would be 121 overlapping copies of the same
-- noise in about four seconds. It rides the tractor, so it is positional -- somebody else cutting
-- across the field sounds like it is coming from over there.
local SOUND_CUT   = "rbxassetid://136646841190295"
local TURN_RATE     = 1.5        -- radians/sec at full lock
local CUT_RADIUS    = 7          -- how wide the cutting bar reaches
local WHEEL_ADOPT_RANGE = 60     -- how far from the Tractor block a part named "wheel" counts
local MAX_STEER_ANGLE = math.rad(26)   -- how far the front pair actually turn

-- palette -- farmyard: tractor green, barn red, wheat gold
local FILL    = Color3.fromRGB(255, 250, 236)
local STROKE  = Color3.fromRGB(150, 106, 46)
local TEXTC   = Color3.fromRGB( 66,  48,  20)
local HINTC   = Color3.fromRGB(160, 142, 112)
local GREEN_T = Color3.fromRGB( 78, 142,  56)   -- tractor bodywork
local GREEN_D = Color3.fromRGB( 54, 102,  40)
local YELLOW  = Color3.fromRGB(246, 202,  62)   -- wheels, trim
local RED_B   = Color3.fromRGB(178,  54,  46)   -- barn
local WHITE_B = Color3.fromRGB(248, 244, 236)
local WHEAT   = Color3.fromRGB(226, 186,  86)
local WHEAT_D = Color3.fromRGB(190, 148,  60)
local IRON    = Color3.fromRGB( 84,  80,  84)
local IRON_D  = Color3.fromRGB( 58,  55,  60)
local GOLD    = Color3.fromRGB(255, 205,  90)
local GREEN   = Color3.fromRGB(110, 210, 120)

local COIN_REWARD = 2600
local QUEST_ID    = "tractor"

local E_TRACTOR, E_WRENCH, E_WHEAT, E_BARN = "\xF0\x9F\x9A\x9C", "\xF0\x9F\x94\xA7", "\xF0\x9F\x8C\xBE", "\xF0\x9F\x8F\x9A"
local E_SPARK, E_KEY = "\xE2\x9C\xA8", "\xF0\x9F\x94\x91"

-- THE FIVE PARTS. Each has its own prop and its own socket on the tractor, because "five
-- identical crates" is a fetch quest and "the steering wheel is missing" is a story.
-- `markers` is every name a hand-placed marker for this part may carry, normalised (lower case,
-- no spaces / underscores / hyphens -- see norm()). They are matched WHOLE, never as substrings,
-- which is the only reason "wheel" and "steeringwheel" can sit on the same island without either
-- one stealing the other's spot. The first name in each list is the one the warnings suggest.
local PARTS = {
	-- ⚠ "wheel" ON ITS OWN IS NOT IN THIS LIST, and must not go back in. Half the models on a farm
	-- island have a part called Wheel -- the tractor itself has four -- so it matches things that
	-- are not markers and never will be. Every alias here has to be a name somebody would only
	-- ever type when they mean "the missing back wheel goes here".
	{ id = "wheel",  label = "Back Wheel",    emoji = "\xE2\x9A\xAB",
		markers = { "backwheel", "rearwheel", "tractorwheel", "wheelmarker" } },
	{ id = "plug",   label = "Spark Plug",    emoji = "\xE2\x9A\xA1",
		markers = { "sparkplug", "plug", "engine", "spark" } },
	{ id = "piston", label = "Piston",        emoji = "\xF0\x9F\x94\xA9",
		markers = { "piston", "conrod" } },
	{ id = "rad",    label = "Radiator",      emoji = "\xF0\x9F\x92\xA7",
		markers = { "radiator", "rad" } },
	{ id = "steer",  label = "Steering Wheel", emoji = "\xF0\x9F\x8E\xA1",
		markers = { "steeringwheel", "steering", "steerwheel" } },
}
-- The geometry's build tag, stamped on every prop and read by the stale-copy sweep. It hangs off
-- PARTS rather than being its own local because this file has two registers of headroom left
-- before Luau refuses to compile it. Bump it when the part models change shape.
PARTS.BUILD = "parts-detailed-v3"
-- how much bigger than life the pickups stand. They are hand props sitting in a field and have to
-- read from across it, but a wheel taller than the tractor stops looking like the tractor's wheel.
PARTS.SCALE = 1.3

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s) return (tostring(s or ""):lower():gsub("[%s_%-]", "")) end

local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat local r = fn(); if r then return r end; task.wait(0.5) until os.clock() - t0 > (timeout or 45)
	return fn()
end

local function hrpOf()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function humOf()
	local c = player.Character
	return c and c:FindFirstChildWhichIsA("Humanoid")
end

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

-- PLAYED FROM THE MACHINE, not from your head. playSound() parents to SoundService, which is
-- 2D and correct for UI beeps; a tractor door is a thing in the world, so it hangs on the part
-- and gets distance falloff -- another player standing nearby hears it from the tractor.
-- ============================================================================
-- THE CAB SOUND -- looped for as long as you are sitting in it
-- ============================================================================
-- (!) NOT A ONE-SHOT AND NOT ON A DEBRIS TIMER. Both of those were wrong for an engine: a
-- one-shot stops after a couple of seconds and leaves you driving a silent machine, and a Debris
-- sweep would delete the loop out from under you mid-drive. It is created on boarding, lives on
-- the tractor, and is destroyed on dismount -- so its lifetime is exactly the time you are aboard.
--
-- (!) PLAYED AGAIN ON .Loaded. A Sound whose asset has not finished downloading answers Play()
-- with silence, so the first boarding of a session would be quiet and every one after it fine.
-- Re-playing when it loads costs nothing and removes the race.
--
-- It hangs on the tractor rather than on you, so it has distance falloff: another player standing
-- nearby hears the machine, and it fades as you drive away from them.
local cabSnd

-- FREE LOOK -- state AND tuning in one table. This file sits close to Luau's 200-register
-- ceiling for a main chunk (going over is a COMPILE failure that silently kills the whole
-- script), and a table costs one register no matter how many fields it holds. Six names for
-- the price of one.
local look = {
	yaw = 0, pitch = 0, on = false,
	sens = 0.006,             -- radians per pixel of mouse movement
	minPitch = -0.55,         -- how far down you can crane
	maxPitch = 0.95,          -- ...and up
	recentre = 3.5,           -- how fast the view eases back once you let go, per second
}

local function setCabSound(on)
	if cabSnd then
		if cabSnd.Parent then cabSnd:Stop(); cabSnd:Destroy() end
		cabSnd = nil
	end
	if not on or SOUND_BOARD == "" then return end
	-- (!) NO TRACTOR CHECK. There used to be a "tractorRoot and tractorRoot.Parent" guard here,
	-- left over from when the Sound hung ON the tractor. It became a silent early-return: the
	-- log showed "boarded -- starting cab sound" and then NEITHER of the two reports below,
	-- which is only possible if the function returned before reaching them. The sound is 2D and
	-- parented to this script now -- it does not need the tractor to exist at all.
	-- (!!) 2D, PARENTED TO SoundService -- NOT to the tractor. This is the third attempt and the
	-- reason the first two were inaudible: a Sound parented to a BasePart is positional, and
	-- Roblox measures positional audio from the CAMERA, not from your character. The chase camera
	-- sits 22 up and 26 back -- ~34 studs -- and inverse rolloff had already cut it to a fifth of
	-- its volume before anything else happened. Raising RollOffMinDistance helped but still left
	-- the level at the mercy of wherever the camera happened to be.
	--
	-- A Sound with no BasePart ancestor plays FLAT: no distance, no listener, no rolloff, no
	-- camera. For the person sitting in the cab that is not a compromise, it is what an engine
	-- should sound like -- you are inside it. The cost is that other players do not hear it from
	-- the tractor, which is worth paying for a driver who can actually hear the machine.
	local snd = Instance.new("Sound")
	snd.Name = "TractorCab"
	snd.SoundId = SOUND_BOARD
	-- 20% down from full: clearly there in the cab, never drowning the rest of the realm
	snd.Volume = 0.8
	snd.Looped = true
	-- (!!) PARENTED TO THIS SCRIPT, NOT SoundService. SoundService is shared ground -- this place
	-- has MusicClient, SfxWiring and CrateClient all putting Sounds there, and the boarding
	-- diagnostic proved something was removing ours within a second of creating it (the log
	-- printed "boarded" and then the one-second report never arrived, which only happens if the
	-- Sound is gone). Parented to the script itself it is out of everyone else's way, and it is
	-- STILL 2D: what makes a Sound positional is having a BasePart or Attachment ancestor, which
	-- a LocalScript in PlayerScripts is not.
	snd.Parent = script
	snd:Play()
	if not snd.IsLoaded then
		local conn
		conn = snd.Loaded:Connect(function()
			if conn then conn:Disconnect() end
			if snd.Parent and not snd.IsPlaying then snd:Play() end
		end)
	end

	-- and say what actually happened, a beat later, so "no sound" is never a guess again
	-- the report covers BOTH outcomes. The previous version only spoke when the Sound still
	-- existed, so the one case that was actually happening -- it being destroyed -- looked
	-- exactly like the check never running.
	task.delay(1, function()
		if not snd.Parent then
			warn("[Tractor] cab sound was DESTROYED within a second of starting -- something else "
				.. "removed it. It is parented to this script now, so this should not recur.")
			return
		end
		print(("[Tractor] cab sound: IsLoaded=%s IsPlaying=%s TimePosition=%.2f Volume=%.2f parent=%s")
			:format(tostring(snd.IsLoaded), tostring(snd.IsPlaying), snd.TimePosition, snd.Volume,
				snd.Parent:GetFullName()))
		if not snd.IsPlaying then
			warn("[Tractor] cab sound loaded but is NOT playing -- retrying once")
			snd:Play()
		end
	end)

	-- ...and if anything ever does take it away mid-drive, say so at the moment it happens
	snd.AncestryChanged:Connect(function(_, parent)
		if parent == nil and driving then
			warn("[Tractor] cab sound was removed while still driving -- rebuilding it")
			task.defer(function() if driving then setCabSound(true) end end)
		end
	end)
	-- ===== THE DECIDING MEASUREMENT =====
	-- PlaybackLoudness is the level the audio engine is actually OUTPUTTING for this Sound,
	-- right now, after every volume and group is applied. It separates the three remaining
	-- possibilities that "I hear nothing" cannot:
	--   loudness > 0  and you hear nothing  -> your OUTPUT is muted (Studio's playtest mute
	--                                          button, master volume, or the OS mixer)
	--   loudness == 0 and IsPlaying=true    -> the ASSET is a silent/near-silent clip; no code
	--                                          change can ever make it audible -- swap the id
	--   never IsPlaying                     -> the parenting spot cannot play audio
	task.spawn(function()
		local maxLoud, played, t0 = 0, false, os.clock()
		while os.clock() - t0 < 2.5 and snd.Parent do
			maxLoud = math.max(maxLoud, snd.PlaybackLoudness)
			played = played or snd.IsPlaying
			task.wait(0.1)
		end
		local master = -1
		pcall(function() master = UserSettings():GetService("UserGameSettings").MasterVolume end)
		print(("[Tractor] cab sound over 2.5s: everPlaying=%s peakLoudness=%.1f MasterVolume=%.2f")
			:format(tostring(played), maxLoud, master))
		if played and maxLoud < 1 then
			warn("[Tractor] the engine Sound IS playing but produces NO signal -- the asset "
				.. SOUND_BOARD .. " is a silent or near-silent clip. Swap the id; code cannot fix this.")
		elseif not played then
			warn("[Tractor] the Sound never entered IsPlaying while parented to the script -- "
				.. "moving it is the next step, say so and I will.")
		elseif master == 0 then
			warn("[Tractor] MasterVolume is 0 -- the game itself is muted on this client.")
		end
	end)
	cabSnd = snd
end

-- SAY OUT LOUD WHETHER THE CAB SOUND IS USABLE. Several ids in this place already fail with
-- "Asset type does not match requested type" or "Asset is not approved for the requester", and
-- a silent sound is indistinguishable from a sound that was never wired up. This answers that
-- question once, at boot, by name.
task.spawn(function()
	if SOUND_BOARD == "" then return end
	local probe = Instance.new("Sound"); probe.SoundId = SOUND_BOARD
	local ok, err = pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ probe }, function(_, status)
			if status == Enum.AssetFetchStatus.Success then
				print("[Tractor] cab sound " .. SOUND_BOARD .. " loaded OK -- it loops while you are aboard")
			else
				warn(("[Tractor] cab sound %s FAILED to load (%s). It will be SILENT. Check the id "
					.. "is an Audio asset and that this experience is permitted to use it.")
					:format(SOUND_BOARD, tostring(status)))
			end
		end)
	end)
	if not ok then warn("[Tractor] sound preload check failed: " .. tostring(err)) end
	probe:Destroy()
end)

local function tween(o, t, props, style, dir)
	local ti = TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local tw = TweenService:Create(o, ti, props); tw:Play(); return tw
end

-- ============================================================================
-- PLACEMENT BLOCKS
-- ============================================================================
-- A block gives POSITION and SIZE and then gets out of the way. Build on its BASE, because
-- that is where it visibly rests on the ground -- a prop placed at the block's centre floats
-- half a block-height up.
--
-- A MARKER CAN BE A MODEL, and that is not an edge case -- it is what somebody laying out an
-- island actually builds. You drop a rough stand-in where the part should go, group it, and name
-- the group. Everything here takes the model's bounding box instead of a part's Size, so a
-- hand-built stand-in and a plain block mean exactly the same thing to this script.
-- Returns TWO things: the base frame, and the marker's footprint. They come from the same
-- measurement and every caller that wants the size also wants the frame, so a second helper for
-- it would be a second top-level name -- and this file has one register of headroom left before
-- Luau refuses to compile it at all. Callers written as `baseFrameOf(x).Position` are unaffected;
-- a spare return value is simply dropped.
local function baseFrameOf(inst)
	local cf, sz
	if inst:IsA("Model") then
		local ok, c, s = pcall(inst.GetBoundingBox, inst)
		if not (ok and c) then return inst:GetPivot(), Vector3.new(4, 4, 4) end
		cf, sz = c, s
	else
		cf, sz = inst.CFrame, inst.Size
	end
	return CFrame.new(Vector3.new(cf.Position.X, cf.Position.Y - sz.Y * 0.5, cf.Position.Z))
		* (cf - cf.Position), sz
end

-- ⚠ SIZE IS THE SAFETY CATCH, NOT THE NAME. This has gone wrong twice on other islands:
-- island15's "chicken zone" was the island's whole floor and island18's "placement boundaires"
-- was a large visible area block, and hiding either made a chunk of the island disappear. A
-- name cannot be trusted to say whether hiding is safe; a size can. A block that says "put a
-- thing here" is about the size of the thing. Anything bigger is read and left completely alone.
local MARKER_MAX = 40

local function hideMarker(inst)
	if not inst then return end
	if not (inst:IsA("BasePart") or inst:IsA("Model")) then return end
	local _, sz = baseFrameOf(inst)
	if sz.X > MARKER_MAX or sz.Z > MARKER_MAX then
		warn(("[Tractor] REFUSING to hide '%s' (%.0f x %.0f studs) -- too big to be a marker. Its "
			.. "position and size are still used; set it invisible in Studio if you want it gone.")
			:format(inst:GetFullName(), sz.X, sz.Z))
		return
	end
	-- HIDDEN, NEVER DELETED. A stand-in you built is yours: it goes invisible and stops answering
	-- rays and touches for this session, and a rejoin brings it back exactly as you left it.
	local function hide(p)
		p.Transparency = 1; p.CanCollide = false; p.CanQuery = false
		p.CanTouch = false; p.Anchored = true
	end
	if inst:IsA("BasePart") then
		hide(inst)
	else
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then hide(d)
			elseif d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1
			elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("ParticleEmitter")
				or d:IsA("Light") then d.Enabled = false end
		end
	end
end

-- ============================================================================
-- BIG E PROMPTS -- readable across the farm, reachable from a model's far edge
-- ============================================================================
-- Roblox's prompt is sized for an adult on a monitor, and its activation distance is measured
-- from the PART it hangs on -- which on a tractor means the trigger sits at the middle of the
-- machine and you have to walk into the engine block to press E. Reach is therefore computed
-- as half the model's bounding diagonal (the far edge, not the near face) plus a walk-up
-- margin, and size comes from Style = Custom plus the renderer below, because there is no
-- property for "make the default prompt bigger".
local BIG_PROMPT = "TractorBigPrompt"

local function reachOf(inst, margin)
	local size
	if inst:IsA("Model") then
		local ok, _, s = pcall(inst.GetBoundingBox, inst)
		if ok then size = s end
	elseif inst:IsA("BasePart") then
		size = inst.Size
	end
	size = size or Vector3.new(6, 6, 6)
	return math.sqrt(size.X * size.X + size.Z * size.Z) * 0.5 + (margin or 14)
end

local function bigPrompt(prompt, reachFrom, margin)
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute(BIG_PROMPT, true)
	if reachFrom then prompt.MaxActivationDistance = reachOf(reachFrom, margin) end
	return prompt
end

do
	local live = {}
	local function build(prompt)
		local host = prompt.Parent
		if not (host and host:IsA("BasePart")) then return end
		local bb = Instance.new("BillboardGui")
		bb.Name = "TractorPrompt"; bb.Adornee = host
		bb.Size = UDim2.fromOffset(300, 96); bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.AlwaysOnTop = true; bb.MaxDistance = 400
		bb.Parent = PlayerGui       -- PlayerGui, not the part: a BillboardGui under questFolder
		                            -- would be walked by the anchorAll sweep for no reason
		local pill = Instance.new("Frame")
		pill.Size = UDim2.fromScale(1, 1); pill.BackgroundColor3 = FILL
		pill.BackgroundTransparency = 0.05; pill.BorderSizePixel = 0; pill.Parent = bb
		Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 22)
		local st = Instance.new("UIStroke"); st.Color = STROKE; st.Thickness = 4; st.Parent = pill

		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = GOLD
		fill.BackgroundTransparency = 0.55; fill.BorderSizePixel = 0; fill.Parent = pill
		Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 22)

		local key = Instance.new("TextLabel")
		key.AnchorPoint = Vector2.new(0, 0.5); key.Position = UDim2.new(0, 14, 0.5, 0)
		key.Size = UDim2.fromOffset(64, 64); key.BackgroundColor3 = STROKE
		key.Font = Enum.Font.FredokaOne; key.TextSize = 34; key.TextColor3 = Color3.new(1, 1, 1)
		key.Text = "E"; key.Parent = pill
		Instance.new("UICorner", key).CornerRadius = UDim.new(0, 16)

		local act = Instance.new("TextLabel")
		act.BackgroundTransparency = 1
		act.Position = UDim2.new(0, 88, 0, 14); act.Size = UDim2.new(1, -102, 0, 40)
		act.Font = Enum.Font.FredokaOne; act.TextSize = 30; act.TextColor3 = TEXTC
		act.TextXAlignment = Enum.TextXAlignment.Left; act.Text = prompt.ActionText; act.Parent = pill

		local obj = Instance.new("TextLabel")
		obj.BackgroundTransparency = 1
		obj.Position = UDim2.new(0, 88, 0, 52); obj.Size = UDim2.new(1, -102, 0, 26)
		obj.Font = Enum.Font.GothamBold; obj.TextSize = 16; obj.TextColor3 = HINTC
		obj.TextXAlignment = Enum.TextXAlignment.Left; obj.Text = prompt.ObjectText; obj.Parent = pill

		-- ActionText changes as the quest runs, so track it rather than snapshot it
		local conn = prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			act.Text = prompt.ActionText
		end)
		bb.Size = UDim2.fromOffset(240, 78)
		tween(bb, 0.16, { Size = UDim2.fromOffset(300, 96) }, Enum.EasingStyle.Back)
		live[prompt] = { gui = bb, fill = fill, conn = conn }
	end
	local function drop(prompt)
		local e = live[prompt]; if not e then return end
		live[prompt] = nil
		if e.conn then e.conn:Disconnect() end
		if e.gui then e.gui:Destroy() end
	end
	PromptService.PromptShown:Connect(function(p) if p:GetAttribute(BIG_PROMPT) then build(p) end end)
	PromptService.PromptHidden:Connect(drop)
	PromptService.PromptButtonHoldBegan:Connect(function(p)
		local e = live[p]
		if e and p.HoldDuration > 0 then
			tween(e.fill, p.HoldDuration, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
		end
	end)
	PromptService.PromptButtonHoldEnded:Connect(function(p)
		local e = live[p]
		if e then tween(e.fill, 0.12, { Size = UDim2.new(0, 0, 1, 0) }, Enum.EasingStyle.Linear) end
	end)
end

-- ============================================================================
-- STATE
-- ============================================================================
-- step: 0 not accepted | 1 find parts | 2 fit them | 3 repair (key) | 4 harvest
--       5 deliver to barn | 6 done
local step        = 0
local island
local boundPart, boundCF, boundHalf, boundIsVolume
local tractorModel, tractorRoot, tractorCF        -- the machine, its main part, its live frame

-- (!) DEFINED HERE, NOT UP WITH TRACTOR_YAW, AND THE ORDER MATTERS. It reads tractorRoot, and a
-- Lua local is only visible to code written after it -- declared in the config block above, the
-- name inside would resolve to a nil GLOBAL and every call would error on the first frame of
-- driving. The constant stays at the top where it is easy to find; the function lives with the
-- state it touches.
--
-- What it returns: the tractor's frame with its REAL nose pointing down -Z. "Forward", "behind",
-- "left" and "right" all mean what they should for this machine, whichever way the model was
-- built. Every direction-aware thing below reads this, never tractorRoot.CFrame directly.
local function driveFrame()
	return tractorRoot.CFrame * CFrame.Angles(0, TRACTOR_YAW, 0)
end
local barnModel, barnPoint
-- THE HARVEST IS A TWO-STOP JOURNEY: cut straw goes to the HAY BALE FACTORY, is pressed into
-- bales there, and the BALES go to the farm house. One table holds that leg's whole state so it
-- costs one register: kind = "straw" (loose, factory-bound) | "pressing" (delivered, waiting on
-- the baler) | "bales" (pressed, farm-house-bound); owed = bales still to come out of the press.
local HAY = { kind = "straw", owed = 0, prompt = nil }
local fieldCF, fieldHalf
local sockets     = {}     -- [id] = { hole=, tag=, prompt=, filled=, def=, at= OR off= }
-- ⚠ THESE TWO ARE DECLARED UP HERE ON PURPOSE, and moving them back down breaks the quest
-- silently. buildSockets (far below, but still ABOVE the panels) wires each repair bay's prompt
-- to fitPart, and fitPart hands the job to FH -- a Lua local is only visible to code written
-- after it, so declared next to their definitions both names would resolve to nil GLOBALS inside
-- those closures and every bay prompt would error on the first press.
local FH          = {}     -- the repair panels: the per-part fitting job, and the ignition
local fitPart              -- forward: assigned where the fitting logic lives
-- ...and the same reason for this one: fitting the WHEEL puts the wheel back on and stands her
-- level again, and that call is written above where brokenFx's functions are defined.
-- the machine's effects, broken AND running: smoke/soot/sparks/flash and the missing wheel are the
-- dead-engine look (cleared when she catches), exhaust is the live one (only while she runs).
local brokenFx    = { smoke = nil, soot = nil, spark = nil, spark2 = nil, flash = nil,
	wheel = nil, wheelCF = nil, levelCF = nil, exhaust = nil, exhaustTried = false }
local partRecs    = {}     -- scattered part props
local carrying    = nil
local fitted      = 0
local stalks      = {}     -- every wheat stalk still standing
local harvested   = 0
local driving     = false
local loadTipped  = false
local npcHead
local refreshBanner, refreshPrompts

-- ===== THE ISLAND-19 FOOD STAND IS LOCKED BEHIND THIS QUEST =====
-- Same contract five other islands already use (see Shop_AllInOne's _G.OpenFoodShop): the stand
-- refuses to open while the flag is false and calls the nudge instead, so the refusal explains
-- itself rather than reading as a broken prompt. tipTheLoad flips the flag when the bales reach
-- the farm house, which is the moment the island's job is actually done.
_G.tractorQuestComplete = false
_G.tractorQuestStep     = nil
_G.tractorQuestNudge = function()
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(function() _G.NotifyCenter.push({
			text = "\xF0\x9F\x9A\x9C Bring the harvest in to unlock this stand!",
			color = Color3.fromRGB(226, 186, 86),
			priority = (_G.NotifyCenter.PRIORITY and _G.NotifyCenter.PRIORITY.EVENT) or 80,
			duration = 3 }) end)
	elseif _G.showHudBanner then
		pcall(_G.showHudBanner, "\xF0\x9F\x9A\x9C Bring the harvest in to unlock this stand!",
			Color3.fromRGB(226, 186, 86), 3)
	end
end

-- ============================================================================
-- FOLDERS -- quest props and scenery are kept apart on purpose
-- ============================================================================
-- spotClear() has to exclude questFolder from its overlap query (the first part placed would
-- otherwise block every spot near it), so anything in there is invisible to placement. Scenery
-- that should BLOCK placement -- the tractor, the barn -- lives in its own folder, which is
-- excluded from ground rays but not from the overlap query.
local questFolder = Instance.new("Folder")
questFolder.Name = "TractorQuestLocal"; questFolder.Parent = Workspace
local sceneryFolder = Instance.new("Folder")
sceneryFolder.Name = "TractorScenery"; sceneryFolder.Parent = Workspace

local function homeToIsland()
	if island then
		if questFolder.Parent ~= island then questFolder.Parent = island end
		if sceneryFolder.Parent ~= island then sceneryFolder.Parent = island end
	end
end

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
		if loose > 0 then warn(("[Tractor] re-anchored %d loose part(s)"):format(loose)) end
	end
end)

-- ============================================================================
-- THE GROUND
-- ============================================================================
local floorPart, floorCF, floorHalf, floorTopY

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
	print(("[Tractor] floor of record: %s (%.0f x %.0f studs, top Y=%.0f)")
		:format(best:GetFullName(), best.Size.X, best.Size.Z, floorTopY))
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshRayFilter()
	local ex = { questFolder, sceneryFolder }
	-- (!!) THE TRACTOR MUST NEVER BE IN ITS OWN GROUND RAY. The built one is safe because it
	-- lives in sceneryFolder, but an ADOPTED model sits inside the island where the ray can see
	-- it -- so the ray hits its own roof, the root is re-seated to roof + ride height, and next
	-- frame the roof is higher again. It climbs into the sky forever, carrying the driver. This
	-- one line is the whole fix.
	if tractorModel then ex[#ex + 1] = tractorModel end
	-- the boundary joins them only if it is a tall VOLUME. A flat plate lying on the ground IS
	-- ground, and excluding it punches the ray through to whatever is under the island.
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

local function groundY(pos)
	local g = groundAt(pos.X, pos.Z, pos.Y)
	return g and g.Y or (floorTopY or pos.Y)
end

local function clampToIsland(pos, inset)
	if not floorCF then return pos end
	local o = floorCF:PointToObjectSpace(pos)
	local m = inset or 6
	local hx, hz = math.max(1, floorHalf.X - m), math.max(1, floorHalf.Z - m)
	return (floorCF * CFrame.new(math.clamp(o.X, -hx, hx), o.Y, math.clamp(o.Z, -hz, hz))).Position
end

local function clampToBounds(pos, inset)
	if not boundCF then return clampToIsland(pos, inset) end
	local o = boundCF:PointToObjectSpace(pos)
	local m = inset or 8
	local hx, hz = math.max(1, boundHalf.X - m), math.max(1, boundHalf.Z - m)
	return (boundCF * CFrame.new(math.clamp(o.X, -hx, hx), o.Y, math.clamp(o.Z, -hz, hz))).Position
end

local function seatOn(x, z, refY, inset)
	local p = clampToBounds(Vector3.new(x, refY, z), inset or 10)
	local g = groundAt(p.X, p.Z, refY)
	if g and math.abs(g.Y - refY) <= 90 then return g end
	if floorTopY then return Vector3.new(p.X, floorTopY, p.Z) end
	return g
end

-- R2 low-discrepancy sequence: the 2D cousin of the golden angle. Spreads points evenly over a
-- RECTANGLE, which a spiral cannot -- a spiral is a circle, and forcing one into a long thin
-- boundary either overflows the short axis or wastes the long one. Deterministic, so the farm
-- looks the same every respawn.
local R2_A1, R2_A2 = 0.7548776662466927, 0.5698402909980532
local function boundCandidate(n, inset)
	local m = inset or 8
	local u, v = (0.5 + R2_A1 * n) % 1, (0.5 + R2_A2 * n) % 1
	if boundCF then
		local hx, hz = math.max(1, boundHalf.X - m), math.max(1, boundHalf.Z - m)
		return (boundCF * CFrame.new((u * 2 - 1) * hx, 0, (v * 2 - 1) * hz)).Position
	end
	local c = tractorCF and tractorCF.Position or (floorCF and floorCF.Position) or Vector3.zero
	local ang = n * 2.39996
	local rad = 70 + ((n * 37) % 120)
	return c + Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)
end

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
local function spotClear(groundPos, size, taken, minGap)
	for _, p in ipairs(taken or {}) do
		if (Vector3.new(p.X, 0, p.Z) - Vector3.new(groundPos.X, 0, groundPos.Z)).Magnitude < (minGap or 16) then
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
	-- lifted so the ground the prop stands on is not itself counted as a collision
	local box = CFrame.new(groundPos + Vector3.new(0, 0.6 + size.Y * 0.5, 0))
	return #Workspace:GetPartBoundsInBox(box, size, overlapParams) == 0
end

-- KEEP-OUTS. The tractor, the barn and the field are all places a scattered part must not land
-- in -- the tractor and barn because you would never see a part inside them, the field because
-- a part hidden in waist-high wheat is not findable.
local function inKeepout(pos)
	local flat = Vector3.new(pos.X, 0, pos.Z)
	if tractorCF and (flat - Vector3.new(tractorCF.Position.X, 0, tractorCF.Position.Z)).Magnitude < 26 then return true end
	if barnPoint and (flat - Vector3.new(barnPoint.X, 0, barnPoint.Z)).Magnitude < 30 then return true end
	if fieldCF then
		local o = fieldCF:PointToObjectSpace(pos)
		if math.abs(o.X) < fieldHalf.X + 6 and math.abs(o.Z) < fieldHalf.Z + 6 then return true end
	end
	return false
end

local function placeInBounds(startIndex, clearance, taken, minGap, tries)
	local last
	for k = 0, (tries or 70) do
		local c = boundCandidate(startIndex + k * 3, 8)
		local g = seatOn(c.X, c.Z, (tractorCF and tractorCF.Position.Y) or c.Y, 8)
		if g and not inKeepout(g) then
			last = g
			if spotClear(g, clearance, taken, minGap) then return g, true end
		end
	end
	return last, false
end

-- ============================================================================
-- SPEECH BUBBLE + OBJECTIVE BANNER
-- ============================================================================
local function hideBubble(a) local p = a and a:FindFirstChild("SpeechBubble"); if p then p:Destroy() end end

local function showBubble(a, text, persist, footer)
	if not a then return end
	hideBubble(a)
	local bb = Instance.new("BillboardGui"); bb.Name = "SpeechBubble"; bb.Adornee = a
	bb.Size = UDim2.new(0, 320, 0, 150); bb.StudsOffset = Vector3.new(0, 5.5, 0)
	bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = FILL
	f.BackgroundTransparency = 0.05; f.BorderSizePixel = 0; f.Parent = bb
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 18)
	local st = Instance.new("UIStroke"); st.Color = STROKE; st.Thickness = 2; st.Transparency = 0.3; st.Parent = f
	local pd = Instance.new("UIPadding")
	pd.PaddingTop = UDim.new(0, 12); pd.PaddingBottom = UDim.new(0, 12)
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = f
	local l = Instance.new("TextLabel")
	l.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1); l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne; l.Text = text; l.TextColor3 = TEXTC
	l.TextScaled = true; l.TextWrapped = true; l.Parent = f
	Instance.new("UITextSizeConstraint", l).MaxTextSize = 22
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1, 0.2)
		h.Position = UDim2.fromScale(0, 0.8); h.BackgroundTransparency = 1
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

-- "...Objective": ObjectiveBannerBridge disables this ScreenGui and mirrors the frame's text
-- onto the realm banner. Visible is still ours to drive; the bridge only reads it.
local objGui = Instance.new("ScreenGui")
objGui.Name = "BrokenTractorObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7
objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5, 0); objFrame.Position = UDim2.new(0.5, 0, 0, 12)
objFrame.Size = UDim2.new(0, 560, 0, 52); objFrame.BackgroundColor3 = FILL
objFrame.Visible = false; objFrame.Parent = objGui
Instance.new("UICorner", objFrame).CornerRadius = UDim.new(0, 16)
do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 3; s.Parent = objFrame end
local objLabel = Instance.new("TextLabel")
objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1, 1)
objLabel.Font = Enum.Font.FredokaOne; objLabel.TextColor3 = TEXTC; objLabel.TextScaled = true
objLabel.Parent = objFrame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = objLabel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14); pad.Parent = objLabel
end

-- Progress is in the text at EVERY stage: the banner should always answer "what now, and how
-- far in am I". A counter with no instruction, or an instruction with no counter, is half a banner.
local function baseText()
	if step >= 6 then _G.tractorQuestStep = nil; return E_TRACTOR .. " The harvest is in. Nice driving!" end
	if step == 0 then _G.tractorQuestStep = nil; return E_TRACTOR .. " Go talk to the Candy NPC!" end
	if step == 5 then
		-- the delivery is two legs now, and the banner says which one you are on
		if HAY.kind == "straw" then
			_G.tractorQuestStep = "Straw to the factory"
			return E_WHEAT .. " Full load! Take the straw to the HAY BALE FACTORY!"
		elseif HAY.kind == "pressing" then
			_G.tractorQuestStep = ("Press %d bale(s)"):format(HAY.owed)
			return ("%s Work the baler's console -- %d bale(s) to press!"):format(E_WRENCH, HAY.owed)
		end
		if HAY.stack and not HAY.carrying then
			_G.tractorQuestStep = "Fetch the bales"
			return E_BARN .. " Five bales stacked outside the factory -- pick them up!"
		end
		_G.tractorQuestStep = "Bales to the farm house"
		return E_BARN .. " Bales on your back! Carry them to the FARM HOUSE!"
	end
	if step == 4 then
		_G.tractorQuestStep = ("Wheat %d/%d"):format(harvested, WHEAT_TARGET)
		return ("%s Drive through the wheat and cut a section:  %d/%d")
			:format(E_WHEAT, harvested, WHEAT_TARGET)
	end
	if step == 3 then _G.tractorQuestStep = "Start the engine"; return E_KEY .. " All fixed -- TURN THE KEY!" end
	if carrying then
		_G.tractorQuestStep = ("Parts %d/%d"):format(fitted, PART_COUNT)
		-- each bay says which part it wants on its own sign, so the banner names the PART you are
		-- holding rather than repeating "the tractor" five times
		return ("%s Take the %s to its bay!  %d/%d")
			:format(carrying.def.emoji, carrying.def.label, fitted, PART_COUNT)
	end
	_G.tractorQuestStep = ("Parts %d/%d"):format(fitted, PART_COUNT)
	return ("%s Find the missing tractor parts:  %d/%d"):format(E_WRENCH, fitted, PART_COUNT)
end

refreshBanner = function() objLabel.Text = baseText() end

-- ============================================================================
-- THE BANNER IS A REMINDER, NOT A FIXTURE
-- ============================================================================
-- It used to be pinned to the top of the screen for the entire quest, every frame you were within
-- 420 studs of the tractor. Fine for the first ten seconds and wallpaper after that -- and with a
-- flash banner landing on top of it every time anything happened, the top of the screen was a
-- stream of text nobody was reading any more.
--
-- Now it behaves like something that is trying to tell you one thing:
--   * something HAPPENED (a part picked up, a counter moving, a flash banner) -> straight up, 5s,
--   * otherwise it reminds you what you are doing for 5 seconds once every 20,
--   * out of range it is gone, and walking back in shows it again immediately.
-- The text changing is the whole event test: every route that has news already writes it here.
task.spawn(function()
	local shownUntil, nextAt, lastText = 0, 0, nil
	while true do
		task.wait(0.25)
		local now = os.clock()
		local near = false
		if step > 0 and step < 6 and island then
			local hrp = hrpOf()
			local ref = tractorCF and tractorCF.Position
			if hrp and ref then near = (hrp.Position - ref).Magnitude <= BANNER_RANGE end
		end
		if not near then
			objFrame.Visible = false
			lastText = objLabel.Text
			nextAt = 0                      -- back in range -> it speaks up straight away
		else
			if objLabel.Text ~= lastText then
				lastText = objLabel.Text
				shownUntil = now + 5
				nextAt = now + 20
			elseif now >= nextAt then
				shownUntil = now + 5
				nextAt = now + 20
			end
			objFrame.Visible = now < shownUntil
		end
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
	n = n or 10
	for i = 1, n do
		local a = (i / n) * math.pi * 2
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
			cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * amount * k,
				(math.random() - 0.5) * amount * k, 0)
			RunService.RenderStepped:Wait()
		end
	end)
end

-- ============================================================================
-- CARRIED PARTS -- anchored, and re-placed on your back every frame
-- ============================================================================
-- The usual way to put something in a player's hands is a weld, and a welded part cannot be
-- anchored. Since everything here is anchored, carried props are driven instead: one
-- RenderStepped pass CFrames them onto your back. There is not one unanchored part in the quest.
--
-- (!) EVERY CARRY GOES THROUGH HERE, AND SO DOES EVERY BROADCAST OF ONE. What you are holding
-- exists on your screen only -- this whole file is a LocalScript -- so to the other kids on the
-- island you are walking to the farm house holding nothing at all. `kind` is the id CarryView
-- draws for them (see CarryView.client.luau's KINDS); passing nil, or dropping, tells everyone
-- your hands are empty. _G.CarrySay is used instead of a require because this file has two
-- registers left before Luau refuses to compile it, and a local for the module costs one.
local carriedProps = {}
local function carryProp(model, off, kind)
	carriedProps[#carriedProps + 1] = { model = model, off = off, kind = kind }
	if kind then pcall(_G.CarrySay, kind) end
end
-- what everyone else should see now that the top of the stack is gone: whatever is still in
-- your hands, or nothing
local function sayTopCarry()
	for i = #carriedProps, 1, -1 do
		if carriedProps[i].kind then return pcall(_G.CarrySay, carriedProps[i].kind) end
	end
	pcall(_G.CarrySay, nil)
end
local function dropCarried(model)
	for i = #carriedProps, 1, -1 do
		if carriedProps[i].model == model then table.remove(carriedProps, i) end
	end
	sayTopCarry()
end
local function clearCarried()
	for _, c in ipairs(carriedProps) do if c.model.Parent then c.model:Destroy() end end
	carriedProps = {}
	pcall(_G.CarrySay, nil)
end
RunService.RenderStepped:Connect(function()
	local hrp = hrpOf()
	if not hrp then return end
	for _, c in ipairs(carriedProps) do
		if c.model.Parent then c.model:PivotTo(hrp.CFrame * c.off) end
	end
end)

-- (!) DECLARED HERE, ABOVE buildTractor, AND THAT ORDER IS LOAD-BEARING.
-- buildTractor adopts your parts named "wheel" through findAllNamed. A Lua local is only
-- visible to code written AFTER it, so leaving these down by the boot section -- where they
-- were first written -- made the call inside buildTractor resolve to a GLOBAL instead: nil,
-- and "attempt to call a nil value" the moment the tractor was built. Nothing warns about
-- this at edit time; it simply is not the same name.
-- ============================================================================
-- FINDING YOUR BLOCKS -- inside the island, AND loose in Workspace beside it
-- ============================================================================
-- Searching only isle:GetDescendants() quietly misses a whole class of block. IslandStreaming's
-- boot audit routinely reports a hundred-plus BaseParts sitting a few hundred studs from an
-- island but parented DIRECTLY to Workspace -- which is what happens the moment a part is
-- dragged into place in Studio without being re-parented into the Model. The symptom is
-- indistinguishable from never having drawn it: the quest reports it missing forever and builds
-- a fallback instead. That cost a whole debugging session on island18.
--
-- So: the island first, then Workspace's own children, bounded by distance. The bound stops
-- another island's identically-named block being grabbed; it is generous rather than tight
-- because a loose part is by definition not where the model thinks it is. Anything found loose
-- is REPORTED, because the real fix is a Studio one -- a loose part cannot inherit Persistent
-- streaming and will vanish at distance.
local LOOSE_RADIUS = 600

local function findByName(isle, wanted)
	for _, d in ipairs(isle:GetDescendants()) do
		if norm(d.Name) == wanted and (d:IsA("BasePart") or d:IsA("Model"))
			and not d:IsDescendantOf(questFolder) and not d:IsDescendantOf(sceneryFolder) then
			return d
		end
	end
	local c = isle:GetPivot().Position
	for _, d in ipairs(Workspace:GetChildren()) do
		if d ~= isle and norm(d.Name) == wanted and (d:IsA("BasePart") or d:IsA("Model"))
			and not d:IsDescendantOf(questFolder) and not d:IsDescendantOf(sceneryFolder) then
			local pos = d:IsA("Model") and d:GetPivot().Position or d.Position
			if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude <= LOOSE_RADIUS then
				warn(("[Tractor] '%s' is parented to Workspace, not inside island19. Used anyway, "
					.. "but drag it into the island's Model in Studio or it will stream out at "
					.. "distance."):format(d:GetFullName()))
				return d
			end
		end
	end
	return nil
end

-- the same rule, for the many-of-a-kind blocks (TractorPart)
-- ⚠ MODELS COUNT, AND THIS IS THE BUG THAT MADE THE PARTS WANDER OFF. This used to look at
-- BaseParts only. A marker drawn as a MODEL -- a little hand-built stand-in for the part, grouped
-- and named, which is the natural way to lay one out -- was invisible to it: five markers read as
-- zero, every part auto-placed somewhere else on the island, and the stand-ins sat there looking
-- like the real thing while the real thing was off in a field. Models are matched first, and any
-- BasePart INSIDE a matched model is skipped so one marker is never counted twice.
local function findAllNamed(isle, wanted)
	local out, models = {}, {}
	local function usable(d)
		return norm(d.Name) == wanted
			and not d:IsDescendantOf(questFolder) and not d:IsDescendantOf(sceneryFolder)
	end
	local function insideMatched(d)
		for _, m in ipairs(models) do if d:IsDescendantOf(m) then return true end end
		return false
	end
	for _, d in ipairs(isle:GetDescendants()) do
		if d:IsA("Model") and usable(d) then models[#models + 1] = d; out[#out + 1] = d end
	end
	local function ok(d)
		return (d:IsA("BasePart") and usable(d) and not insideMatched(d))
	end
	for _, d in ipairs(isle:GetDescendants()) do
		if ok(d) then out[#out + 1] = d end
	end
	local c = isle:GetPivot().Position
	local loose = 0
	for _, d in ipairs(Workspace:GetChildren()) do
		local isLoose = (d:IsA("Model") and usable(d)) or ok(d)
		if isLoose and (function()
				local p = baseFrameOf(d).Position
				return (Vector3.new(p.X, 0, p.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude <= LOOSE_RADIUS
			end)() then
			out[#out + 1] = d
			loose += 1
		end
	end
	if loose > 0 then
		warn(("[Tractor] %d '%s' block(s) are parented to Workspace, not inside island19. Used "
			.. "anyway -- drag them into the island's Model in Studio."):format(loose, wanted))
	end
	return out
end

-- ============================================================================
-- THE TRACTOR
-- ============================================================================
local function sceneryPart(props, parent)
	local p = mk(props)
	p.CanCollide = true; p.CanQuery = true
	p.CastShadow = true
	p.Parent = parent
	return p
end

local tractorParts = {}    -- { part=, off= } -- everything glued to tractorRoot each frame
local wheelParts   = {}    -- the ones that spin while driving
-- (socketMarks used to live here. It was declared, never written and never read -- and on a file
-- with two registers of headroom before Luau refuses to compile it, a dead name is not free.)

local function tAttach(name, size, off, colour, shape, material)
	local p = sceneryPart({ Name = name, Size = size, Color = colour or GREEN_T,
		Material = material or Enum.Material.SmoothPlastic }, tractorModel)
	if shape then p.Shape = shape end
	tractorParts[#tractorParts + 1] = { part = p, off = off }
	return p
end

local function buildTractor(at)
	tractorModel = Instance.new("Model"); tractorModel.Name = "BrokenTractor"
	tractorModel:SetAttribute("QuestProp", true)

	-- the root is an invisible box at seat height: everything else is an offset from it, so the
	-- whole machine moves as one PivotTo when it drives.
	tractorRoot = sceneryPart({ Name = "Root", Size = Vector3.new(4, 1, 8), Transparency = 1 }, tractorModel)
	tractorRoot.CanCollide = false; tractorRoot.CanQuery = false
	-- (!) BUILT AT EXACTLY THE HEIGHT IT WILL DRIVE AT. The drive loop re-seats the tractor onto
	-- the ground every frame as `groundY(here) + SEAT_HEIGHT`. If it is BUILT from the marker
	-- block's own base instead, the two disagree the moment the engine starts -- the machine
	-- snaps to the ray height and takes the driver up with it. That is exactly what made /fix
	-- appear to teleport you upward: /fix does not move anything, it starts the engine, and the
	-- engine is what re-seats the tractor. Same formula in both places, no jump.
	local gy = groundY(at.Position)
	tractorRoot.CFrame = CFrame.new(at.Position.X, gy + SEAT_HEIGHT, at.Position.Z)
		* (at - at.Position)
	tractorModel.PrimaryPart = tractorRoot

	tAttach("Chassis", Vector3.new(4.6, 1.6, 9.5), CFrame.new(0, -0.6, 0), GREEN_D)
	tAttach("Bonnet",  Vector3.new(4.0, 2.6, 5.0), CFrame.new(0, 0.9, -2.4), GREEN_T)
	tAttach("Grille",  Vector3.new(3.4, 1.8, 0.4), CFrame.new(0, 0.9, -4.9), IRON, nil, Enum.Material.DiamondPlate)
	tAttach("Exhaust", Vector3.new(0.6, 3.4, 0.6), CFrame.new(-1.3, 3.0, -3.6), IRON_D, nil, Enum.Material.Metal)
	tAttach("ExhaustCap", Vector3.new(0.9, 0.4, 0.9), CFrame.new(-1.3, 4.8, -3.6), IRON_D, Enum.PartType.Cylinder, Enum.Material.Metal)
	tAttach("Cab",     Vector3.new(4.2, 0.6, 3.4), CFrame.new(0, 1.6, 1.4), GREEN_D)
	tAttach("SeatBack", Vector3.new(2.4, 2.2, 0.5), CFrame.new(0, 2.6, 2.6), Color3.fromRGB(60, 48, 40))
	tAttach("SeatBase", Vector3.new(2.4, 0.6, 2.0), CFrame.new(0, 1.6, 1.6), Color3.fromRGB(60, 48, 40))
	for _, sx in ipairs({ -1, 1 }) do
		tAttach("Fender" .. sx, Vector3.new(0.4, 2.6, 4.4), CFrame.new(sx * 2.5, 0.9, 1.8), YELLOW)
		tAttach("Step" .. sx, Vector3.new(1.0, 0.3, 1.4), CFrame.new(sx * 2.6, -0.9, 1.4), IRON)
	end

	-- the wheels: big at the back, small at the front. Each carries its own RADIUS, because a
	-- wheel's spin rate is not a style choice -- it is the distance rolled divided by the radius,
	-- and a big rear wheel must visibly turn slower than a small front one at the same speed.
	-- `steers` marks the pair that also swing with the steering input.
	local function wheel(name, off, r, w)
		local p = tAttach(name, Vector3.new(w, r * 2, r * 2), off, Color3.fromRGB(38, 36, 38),
			Enum.PartType.Cylinder, Enum.Material.SmoothPlastic)
		local hub = tAttach(name .. "Hub", Vector3.new(w + 0.2, r * 0.9, r * 0.9), off, YELLOW,
			Enum.PartType.Cylinder, Enum.Material.SmoothPlastic)
		hub.CanCollide = false
		local steers = off.Position:Dot(CFrame.Angles(0, TRACTOR_YAW, 0).LookVector) > 0
		-- axis = "x": these are Cylinders, whose length (and therefore axle) is their local X.
		wheelParts[#wheelParts + 1] = { part = p, off = off, radius = r, steers = steers, axis = "x" }
		wheelParts[#wheelParts + 1] = { part = hub, off = off, radius = r, steers = steers, axis = "x" }
		return p
	end
	-- ===== YOUR WHEELS FIRST =====
	-- Four parts you named "wheel" near the tractor block are adopted as the real wheels: their
	-- offset from the rig is measured WHERE YOU PUT THEM, so they stay exactly where you placed
	-- them and simply start turning. Each one's radius is read off its own size, which is what
	-- lets a big rear wheel and a small front wheel roll at correspondingly different rates.
	--
	-- Adopted wheels REPLACE the built ones rather than joining them -- otherwise the script's
	-- four would sit inside yours, turning at a slightly different rate and reading as a
	-- flickering mess.
	local adopted = 0
	for _, w in ipairs(findAllNamed(island, "wheel")) do
		if (w.Position - at.Position).Magnitude <= WHEEL_ADOPT_RANGE and adopted < 8 then
			adopted += 1
			w.Anchored = true
			local off = tractorRoot.CFrame:ToObjectSpace(w.CFrame)
			-- WHICH WAY IS THE AXLE? Read it off the part instead of assuming, because a wheel
			-- can be built on any axis and guessing wrong makes it spin like a coin on a table
			-- rather than roll. A wheel is a disc: its THINNEST dimension is the axle, and the
			-- other two are the rolling circle. That holds for a Cylinder, a Block or a MeshPart,
			-- however it happened to be oriented in Studio.
			local sz = w.Size
			local axis, r
			if sz.X <= sz.Y and sz.X <= sz.Z then
				axis, r = "x", (sz.Y + sz.Z) * 0.25
			elseif sz.Y <= sz.X and sz.Y <= sz.Z then
				axis, r = "y", (sz.X + sz.Z) * 0.25
			else
				axis, r = "z", (sz.X + sz.Y) * 0.25
			end
			tractorParts[#tractorParts + 1] = { part = w, off = off }
			-- FRONT is measured along the nose direction, not along -Z. On a model whose front
			-- is a quarter turn round, the steering pair sit on the X axis and an off.Z test
			-- would pick the left and right wheels instead.
			wheelParts[#wheelParts + 1] = { part = w, off = off, radius = math.max(0.5, r),
				steers = off.Position:Dot(CFrame.Angles(0, TRACTOR_YAW, 0).LookVector) > 0,
				adopted = true, axis = axis }
		end
	end

	if adopted > 0 then
		print(("[Tractor] adopted %d part(s) named 'wheel' -- rolling them at their own radius")
			:format(adopted))
	else
		-- ⚠ a Cylinder's length runs along its LOCAL X, so a wheel's axle is X: the offsets carry
		-- a 90-degree roll to stand each one up on its rim. Without it they lie flat like plates.
		local AX = CFrame.Angles(0, 0, math.rad(90))
		wheel("WheelBL", CFrame.new(-2.4, -0.4, 2.8) * AX, 2.6, 1.3)
		wheel("WheelBR", CFrame.new( 2.4, -0.4, 2.8) * AX, 2.6, 1.3)
		wheel("WheelFL", CFrame.new(-2.1, -1.2, -3.6) * AX, 1.6, 0.9)
		wheel("WheelFR", CFrame.new( 2.1, -1.2, -3.6) * AX, 1.6, 0.9)
	end

	-- the trailer: an open box on the back that visibly fills with cut wheat
	tAttach("TrailerBed", Vector3.new(5.0, 0.5, 5.0), CFrame.new(0, 0.4, 7.4), Color3.fromRGB(150, 106, 62), nil, Enum.Material.WoodPlanks)
	tAttach("TrailerL", Vector3.new(0.4, 2.0, 5.0), CFrame.new(-2.3, 1.4, 7.4), Color3.fromRGB(150, 106, 62), nil, Enum.Material.WoodPlanks)
	tAttach("TrailerR", Vector3.new(0.4, 2.0, 5.0), CFrame.new( 2.3, 1.4, 7.4), Color3.fromRGB(150, 106, 62), nil, Enum.Material.WoodPlanks)
	tAttach("TrailerB", Vector3.new(5.0, 2.0, 0.4), CFrame.new(0, 1.4, 9.7), Color3.fromRGB(150, 106, 62), nil, Enum.Material.WoodPlanks)
	tAttach("Hitch", Vector3.new(0.5, 0.5, 2.4), CFrame.new(0, -0.4, 5.2), IRON, nil, Enum.Material.Metal)

	tractorModel.Parent = sceneryFolder
	tractorCF = at * CFrame.new(0, 3.2, 0)
	return tractorModel
end

-- keep every attached part glued to the root at its offset
local function poseTractor()
	if not (tractorRoot and tractorRoot.Parent) then return end
	for _, e in ipairs(tractorParts) do
		if e.part.Parent then e.part.CFrame = tractorRoot.CFrame * e.off end
	end
end

-- THE SOCKETS -- one glowing hole per missing part, positioned where that part belongs
local SOCKET_AT = {
	wheel  = CFrame.new(-2.4, -0.4, 2.8),
	plug   = CFrame.new(1.2, 1.6, -2.4),
	piston = CFrame.new(0, 1.9, -2.4),
	rad    = CFrame.new(0, 0.9, -4.4),
	steer  = CFrame.new(0, 2.4, 0.2),
}

local function buildSockets()
	-- ========================================================================
	-- WHERE THE PARTS GO: YOUR "FixTractor" BLOCKS
	-- ========================================================================
	-- Any BasePart named FixTractor inside island19 is a REPAIR BAY. The glowing socket is built
	-- standing at it, on the ground where you drew it, with its own name tag and its own E prompt
	-- -- so "where does the radiator go" is answered by looking, not by guessing which corner of
	-- the machine to stand in.
	--
	-- Bays are matched to parts LEFT TO RIGHT (X, then Z), which is the one ordering that does not
	-- move when the island streams in: the same bay always wants the same part, every join. Six
	-- bays and five parts is fine -- the spare is left exactly as you drew it, untouched.
	--
	-- WITH NO BLOCKS AT ALL the sockets fall back to riding ON the tractor at the SOCKET_AT
	-- offsets, which is how this quest worked before the bays existed and still how it works on an
	-- island that has none. Everything downstream reads sock.at (a world CFrame) or sock.off (a
	-- frame relative to the machine), so neither route is a special case anywhere else.
	-- FOUR NAMES, ONE MEANING. "FixTractor", "FixPlacement", "FixSpot", "RepairBay" -- whichever
	-- you called them, they are the same thing, and a bay that does nothing because it was named
	-- the other obvious word is the kind of bug you find by rebuilding the island twice.
	local spots = {}
	do
		local seen = {}
		for _, alias in ipairs({ "fixtractor", "fixplacement", "fixspot", "repairbay" }) do
			for _, d in ipairs(findAllNamed(island, alias)) do
				if not seen[d] then seen[d] = true; spots[#spots + 1] = d end
			end
		end
	end

	-- ========================================================================
	-- (!) IF THOSE BLOCKS ARE THE ONLY MARKERS ON THE ISLAND, THEY ARE NOT BAYS
	-- ========================================================================
	-- A bay is where you BRING a part to. That only means anything if the parts are somewhere
	-- else to begin with -- and an island laid out with six "FixTractor" blocks and nothing named
	-- after a part has, in plain terms, marked out where the five parts go. Read as bays it
	-- produced the worst possible result: five bays lit up, five parts skipped for want of a
	-- marker, and a quest with nothing in it to pick up.
	--
	-- So the blocks change meaning with the island. With part markers present they are bays; with
	-- none they ARE the part spots, placeParts spawns the pickups on them (PARTS.baysUsed tells it
	-- which), and fitting happens at the tractor -- which has always accepted a part, from the
	-- first one to the fifth.
	do
		-- (!) THE TRACTOR'S OWN PARTS ARE NOT MARKERS, and forgetting that broke this outright.
		-- The machine has four parts named "Wheel" -- which is one of the Back Wheel's marker
		-- aliases -- so a bare name search answered "yes, there are part markers", the blocks
		-- stayed bays, and placeParts (which correctly refuses to build on anything inside the
		-- tractor) then found nothing at all: five bays lit, five parts skipped, 0/5 spawned.
		-- This test now uses the SAME filter placeParts does, and the two agree by construction.
		local function haveMarker(name)
			for _, d in ipairs(findAllNamed(island, name)) do
				if not (tractorModel and d:IsDescendantOf(tractorModel)) then return true end
			end
			return false
		end
		local any = haveMarker(PART_NAME)
		if not any then
			for _, def in ipairs(PARTS) do
				for _, alias in ipairs(def.markers) do
					if haveMarker(alias) then any = true; break end
				end
				if any then break end
			end
		end
		PARTS.baysUsed = any
		if not any then
			print(("[Tractor] %d repair-bay block(s) found and NO part markers -- reading them as "
				.. "the PART SPOTS instead. The parts spawn on them and are fitted at the tractor. "
				.. "Name a block after a part (e.g. 'Radiator') to turn the bays back on.")
				:format(#spots))
			spots = {}          -- no bays: buildSockets falls back to sockets on the machine
		end
	end
	-- sorted off baseFrameOf, not off .Position: a bay drawn as a MODEL has no .Position at all,
	-- and reading one would error out the whole build
	table.sort(spots, function(a, b)
		local pa, pb = baseFrameOf(a).Position, baseFrameOf(b).Position
		if math.abs(pa.X - pb.X) > 0.5 then return pa.X < pb.X end
		return pa.Z < pb.Z
	end)

	for i, def in ipairs(PARTS) do
		local marker = spots[i]
		local hole = sceneryPart({ Name = "Socket_" .. def.id, Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.8, 1.8, 1.8), Color = GOLD, Material = Enum.Material.Neon,
			Transparency = 0.45 }, marker and questFolder or tractorModel)
		hole.CanCollide = false

		local sock = { hole = hole, filled = false, def = def }
		if marker then
			local cf, msz = baseFrameOf(marker)
			sock.at = cf * CFrame.new(0, 2.6, 0)
			hole.CFrame = sock.at
			-- a pad under it, so the bay still reads as a PLACE once your block is hidden
			local pad = sceneryPart({ Name = "FixPad_" .. def.id, Color = IRON_D,
				Material = Enum.Material.Metal, Transparency = 0.1,
				Size = Vector3.new(math.clamp(msz.X, 4, 12), 0.4,
					math.clamp(msz.Z, 4, 12)) }, questFolder)
			pad.CFrame = cf * CFrame.new(0, 0.2, 0)
			pad.CanCollide = false
			hideMarker(marker)
		else
			sock.off = SOCKET_AT[def.id]
			tractorParts[#tractorParts + 1] = { part = hole, off = sock.off }
		end

		-- ===== A NAME LABEL ONLY WHERE IT IS A DESTINATION =====
		-- (!) NEVER ON THE MACHINE. A bay standing in the yard deserves a sign saying which part
		-- it wants -- that is the whole point of it. A socket riding on the TRACTOR does not: the
		-- five of them are inches apart on one machine, so all five labels stacked into an
		-- unreadable pile of overlapping text hanging over the bonnet, and stayed there whether a
		-- part had been fitted or not. The tractor carries no part names at all now.
		-- (and no name label on a bay either -- same reasoning as the pickups, see buildPartProp.
		-- A bay says what it wants with the grey casting of the part standing in it and with its
		-- own E prompt, "Fit The Radiator", which is a sentence rather than a floating word.)

		if marker then
			-- one prompt per bay, and it only ever answers for the part it is waiting for
			-- (refreshPrompts owns that gate), so carrying the piston past the radiator bay does
			-- nothing at all rather than fitting the wrong thing in the wrong hole.
			local pr = Instance.new("ProximityPrompt")
			pr.ActionText = "Fit The " .. def.label
			pr.ObjectText = "Repair Bay"
			pr.HoldDuration = 0.2
			pr.KeyboardKeyCode = Enum.KeyCode.E
			pr.MaxActivationDistance = 14
			pr.RequiresLineOfSight = false
			pr.Enabled = false
			pr.Parent = hole          -- stock prompt: the custom card is the TRACTOR's alone
			pr.Triggered:Connect(function() if fitPart then fitPart() end end)
			sock.prompt = pr
			print(("[Tractor] repair bay for the %s -> DEFAULT prompt (14 studs)"):format(def.label))
		end

		sockets[def.id] = sock
	end
	-- A SPARE BAY IS STILL HIDDEN. Drawing six blocks for five parts is the normal thing to do,
	-- and the sixth left standing in the field looks like a bug rather than a spare. Hidden, not
	-- touched: it stays exactly where you drew it and becomes a bay the moment a sixth part exists.
	for k = PART_COUNT + 1, #spots do hideMarker(spots[k]) end
	if #spots > 0 then
		print(("[Tractor] %d 'FixTractor' bay(s) found -- the %d part(s) drop into the first %d, "
			.. "left to right%s"):format(#spots, PART_COUNT, math.min(#spots, PART_COUNT),
			#spots > PART_COUNT and (", " .. (#spots - PART_COUNT) .. " spare hidden") or ""))
		if #spots < PART_COUNT then
			warn(("[Tractor] only %d bay(s) for %d part(s) -- the rest ride on the machine as before. "
				.. "Add %d more 'FixTractor' block(s) to give every part its own spot.")
				:format(#spots, PART_COUNT, PART_COUNT - #spots))
		end
	elseif PARTS.baysUsed == false then
		-- not "no blocks" -- there are blocks, they are just being read as the part spots (above)
		print("[Tractor] repair bays OFF -- the FixTractor blocks are the part spots this run, so "
			.. "the sockets ride on the machine and fitting happens at the tractor")
	else
		print("[Tractor] no 'FixTractor' blocks -- sockets ride on the machine (the old way)")
	end
	-- the empty sockets pulse, so what is still missing is never a guess
	task.spawn(function()
		while tractorRoot and tractorRoot.Parent do
			task.wait(0.1)
			local k = 0.25 + math.abs(math.sin(os.clock() * 2)) * 0.35
			for _, s in pairs(sockets) do
				if s.hole.Parent then s.hole.Transparency = s.filled and 1 or k end
			end
		end
	end)
end

-- ============================================================================
-- THE FIVE MISSING PARTS
-- ============================================================================
-- ============================================================================
-- WHAT THE FIVE PARTS ACTUALLY LOOK LIKE
-- ============================================================================
-- These used to be two primitives each -- a cylinder for "wheel", a box with a tip for "plug" --
-- which is enough to tell them apart on a name tag and not enough for any of them to read as a
-- real object when you are standing over it. Every one is now built the way the thing is built:
-- a tyre has a tread and a rim and lug nuts, a plug has a threaded shank and a ribbed ceramic and
-- a bent ground strap, a radiator has a finned core between two tanks with a filler neck and a
-- hose stub. Nothing here is a mesh -- it is all the same anchored primitives, just arranged
-- like the part instead of standing in for it.
--
-- The three helpers are LOCAL TO THIS FUNCTION on purpose: this file sits at 198 of Luau's 200
-- registers for a main chunk and going over is a COMPILE failure, so a helper only this builder
-- uses does not get to be another top-level name.
--
-- `at` is a CFrame -- the marker's base frame, already flattened to YAW ONLY by placeParts (see
-- the note there: a marker lying on its face would otherwise tip the whole prop into the ground,
-- which is what "flat placeholder" actually looks like). Everything below is written in that
-- frame's own space, so turning a marker in Studio turns the part standing on it. It also accepts
-- a bare Vector3 for any older call site: those get no rotation, which is what they meant.
--
-- EVERY PROP IS BUILT SITTING ON y = 0 OF THAT FRAME, which is the marker's BASE -- the height it
-- visibly rests at. Nothing here may dip below it or the part looks half-buried.
local function buildPartProp(def, at)
	if typeof(at) == "Vector3" then at = CFrame.new(at) end
	local m = Instance.new("Model"); m.Name = "TractorPart_" .. def.id
	m:SetAttribute("QuestProp", true)
	-- WHICH BUILD MADE IT. The sweep that clears leftovers from a stale duplicate copy of this
	-- file keys off this: a prop with a different tag (or none at all) came from an older version
	-- of this script and is removed, while two copies of the SAME build never delete each other's
	-- work. Bump it whenever the geometry below changes shape.
	m:SetAttribute("Build", PARTS.BUILD)

	-- Worn farm-machinery palette, with ONE PAINTED ACCENT PER PART. Five grey mechanical objects
	-- on grass are five grey smudges; give each one a colour it owns -- yellow rim, white ceramic,
	-- polished crown, green shroud, green hub -- and you can tell which is which from the far side
	-- of the field, before any name tag is readable.
	local TYRE   = Color3.fromRGB( 28,  27,  29)
	local TYRE_L = Color3.fromRGB( 44,  43,  46)
	local RIM    = Color3.fromRGB(214, 178,  48)
	local STEEL  = Color3.fromRGB(186, 190, 198)
	local STEEL_D= Color3.fromRGB(118, 120, 126)
	local CAST   = Color3.fromRGB(132, 130, 128)
	local RUST   = Color3.fromRGB(146,  86,  52)
	local CERAM  = Color3.fromRGB(246, 242, 232)
	local COPPER = Color3.fromRGB(198, 126,  70)
	local PAINT  = Color3.fromRGB( 74, 132,  56)   -- tractor green: the accent that ties them together
	local PLANK  = Color3.fromRGB(156, 112,  68)
	local PLANK_D= Color3.fromRGB(118,  84,  50)

	-- THE PROP STANDS ON A PALLET, so `base` is a little above the marker: the pallet occupies the
	-- ground and the part sits on its deck. Everything in the branches below is written against
	-- `base` and needs no adjusting for it.
	local ground = at
	local base = at * CFrame.new(0, 0.42, 0)

	local function p(props, cf)
		local q = mk(props)
		q.CFrame = cf
		q.Parent = m
		return q
	end
	-- TWO CYLINDER HELPERS, AND WHICH ONE YOU WANT IS THE WHOLE QUESTION. A Roblox cylinder's axis
	-- is its local X; remembering that at forty call sites is how a wheel ends up lying flat on
	-- the ground like a dinner plate. So:
	--   cyl()  -- axis is the frame's +Y. Anything standing up: a plug, a filler neck, a piston.
	--   cylX() -- axis is the frame's +X. Anything on an axle: the wheel, a wrist pin, a hub.
	-- In both, size.X is the LENGTH along the axis and size.Y/Z are the diameter.
	local function cyl(size, colour, cf, mat, refl)
		return p({ Shape = Enum.PartType.Cylinder, Size = size, Color = colour,
			Material = mat or Enum.Material.Metal, Reflectance = refl or 0 },
			cf * CFrame.Angles(0, 0, math.rad(90)))
	end
	local function cylX(size, colour, cf, mat, refl)
		return p({ Shape = Enum.PartType.Cylinder, Size = size, Color = colour,
			Material = mat or Enum.Material.Metal, Reflectance = refl or 0 }, cf)
	end
	local main

	if def.id == "wheel" then
		-- ===== REAR TRACTOR WHEEL, STOOD UP AND LEANING =====
		-- Lying flat it reads as a manhole cover; stood up and turned off-square it reads as a
		-- wheel somebody rolled off the machine and left there.
		-- W's +X is the axle and its YZ plane is the wheel, so everything round here is cylX()
		local W = base * CFrame.new(0, 2.78, 0) * CFrame.Angles(0, math.rad(26), math.rad(5))
		main = cylX(Vector3.new(1.25, 5.5, 5.5), TYRE, W, Enum.Material.SmoothPlastic)
		-- sidewalls: a slightly proud, slightly lighter ring each side is what stops the tyre
		-- reading as one solid puck
		for _, sx in ipairs({ -1, 1 }) do
			cylX(Vector3.new(0.16, 4.8, 4.8), TYRE_L, W * CFrame.new(sx * 0.6, 0, 0),
				Enum.Material.SmoothPlastic)
		end
		-- the tread: 15 chevron bars, alternating lean, standing proud of the carcass
		for i = 1, 15 do
			local a = (i / 15) * math.pi * 2
			local sgn = (i % 2 == 0) and 1 or -1
			p({ Size = Vector3.new(1.15, 0.55, 1.15), Color = TYRE_L,
				Material = Enum.Material.SmoothPlastic },
				W * CFrame.Angles(a, 0, 0) * CFrame.new(0, 2.6, 0)
					* CFrame.Angles(0, math.rad(sgn * 28), 0))
		end
		-- the rim: dish, hub, six nuts and a valve stem
		cylX(Vector3.new(0.55, 3.3, 3.3), RIM, W, Enum.Material.Metal, 0.05)
		cylX(Vector3.new(0.75, 2.2, 2.2), RIM, W * CFrame.new(0.1, 0, 0), Enum.Material.Metal, 0.05)
		cylX(Vector3.new(0.9, 1.15, 1.15), STEEL_D, W * CFrame.new(0.15, 0, 0), Enum.Material.Metal, 0.1)
		-- five dish holes punched through the rim: the detail that turns a yellow disc into a WHEEL
		for i = 1, 5 do
			cylX(Vector3.new(0.62, 0.86, 0.86), Color3.fromRGB(26, 25, 27),
				W * CFrame.Angles((i / 5) * math.pi * 2 + 0.4, 0, 0) * CFrame.new(0.32, 1.55, 0),
				Enum.Material.SmoothPlastic)
		end
		for i = 1, 6 do
			-- 0.5 out along the axle, 0.82 out radially at this angle: Rx spins the +Y offset
			-- round the wheel and leaves the axle offset alone
			cylX(Vector3.new(0.28, 0.36, 0.36), STEEL,
				W * CFrame.Angles((i / 6) * math.pi * 2, 0, 0) * CFrame.new(0.5, 0.82, 0))
		end
		cylX(Vector3.new(0.34, 0.22, 0.22), COPPER,
			W * CFrame.Angles(math.rad(200), 0, 0) * CFrame.new(0.62, 1.5, 0))
		-- a scuff of dried mud in the tread, because this one came off a field and not a shelf
		for i = 1, 3 do
			p({ Size = Vector3.new(0.8, 0.3, 0.5), Color = Color3.fromRGB(96, 74, 52),
				Material = Enum.Material.Sand },
				W * CFrame.Angles(math.rad(40 + i * 47), 0, 0) * CFrame.new(0.2, 2.45, 0))
		end

	elseif def.id == "plug" then
		-- ===== SPARK PLUG, STOOD ON ITS THREAD =====
		local S = base * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, math.rad(15), 0)
		-- the threaded shank, as actual turns of thread rather than a smooth stub
		for i = 0, 6 do
			cyl(Vector3.new(0.09, 0.64, 0.64), STEEL_D, S * CFrame.new(0, 0.3 + i * 0.1, 0))
		end
		cyl(Vector3.new(0.62, 0.5, 0.5), STEEL_D, S * CFrame.new(0, 0.28, 0))
		-- centre electrode and the ground strap bent over it -- the detail that says "spark plug"
		p({ Size = Vector3.new(0.08, 0.34, 0.08), Color = COPPER, Material = Enum.Material.Metal },
			S * CFrame.new(0, 0.14, 0))
		p({ Size = Vector3.new(0.14, 0.42, 0.14), Color = STEEL, Material = Enum.Material.Metal },
			S * CFrame.new(0, 0.26, 0.24))
		p({ Size = Vector3.new(0.14, 0.12, 0.3), Color = STEEL, Material = Enum.Material.Metal },
			S * CFrame.new(0, 0.06, 0.13))
		-- hex body: a disc with six flats laid round it reads as a nut at any distance you can
		-- see this prop from
		cyl(Vector3.new(0.4, 0.8, 0.8), STEEL, S * CFrame.new(0, 1.15, 0))
		for i = 1, 6 do
			p({ Size = Vector3.new(0.42, 0.4, 0.1), Color = STEEL, Material = Enum.Material.Metal },
				S * CFrame.new(0, 1.15, 0) * CFrame.Angles(0, (i / 6) * math.pi * 2, 0)
					* CFrame.new(0, 0, 0.4))
		end
		cyl(Vector3.new(0.18, 0.86, 0.86), STEEL_D, S * CFrame.new(0, 1.42, 0))
		-- ribbed ceramic insulator, stepping in as it goes up
		main = cyl(Vector3.new(0.62, 0.72, 0.72), CERAM, S * CFrame.new(0, 1.85, 0),
			Enum.Material.SmoothPlastic, 0.12)      -- glazed, not chalky: ceramic has a sheen
		-- the maker's colour band round the insulator. It is one thin ring and it is the only
		-- saturated colour on the part -- which is exactly why the plug reads at a distance now.
		cyl(Vector3.new(0.16, 0.78, 0.78), Color3.fromRGB(196, 62, 54),
			S * CFrame.new(0, 2.08, 0), Enum.Material.SmoothPlastic)
		for i = 1, 4 do
			cyl(Vector3.new(0.1, 0.82 - i * 0.04, 0.82 - i * 0.04), CERAM,
				S * CFrame.new(0, 1.62 + i * 0.24, 0), Enum.Material.SmoothPlastic, 0.04)
		end
		cyl(Vector3.new(0.5, 0.58, 0.58), CERAM, S * CFrame.new(0, 2.45, 0),
			Enum.Material.SmoothPlastic, 0.04)
		cyl(Vector3.new(0.26, 0.34, 0.34), STEEL, S * CFrame.new(0, 2.82, 0))
		-- sooted tip: it came out of a dead engine
		cyl(Vector3.new(0.06, 0.66, 0.66), Color3.fromRGB(52, 46, 42),
			S * CFrame.new(0, 0.62, 0), Enum.Material.SmoothPlastic)

	elseif def.id == "piston" then
		-- ===== PISTON AND CONNECTING ROD =====
		-- lifted 0.95 so the BIG END (which hangs at -0.72 in this frame) clears the ground: it
		-- was the one piece in the set that sat half-buried in the grass
		local S = base * CFrame.new(0, 0.95, 0) * CFrame.Angles(0, math.rad(-18), 0)
		main = cyl(Vector3.new(1.0, 1.9, 1.9), STEEL, S * CFrame.new(0, 1.35, 0),
			Enum.Material.Metal, 0.22)                                   -- crown, polished bright
		-- three oil-return holes round the skirt: tiny, and they are what makes the cylinder read
		-- as machined aluminium rather than as a tin can
		for i = 1, 3 do
			p({ Size = Vector3.new(0.22, 0.22, 0.22), Color = Color3.fromRGB(40, 38, 38),
				Material = Enum.Material.SmoothPlastic },
				S * CFrame.new(0, 1.0, 0) * CFrame.Angles(0, (i / 3) * math.pi * 2, 0)
					* CFrame.new(0, 0, 0.92))
		end
		cyl(Vector3.new(0.12, 1.95, 1.95), Color3.fromRGB(60, 58, 60),
			S * CFrame.new(0, 1.72, 0))                                  -- three ring grooves
		cyl(Vector3.new(0.12, 1.95, 1.95), Color3.fromRGB(60, 58, 60), S * CFrame.new(0, 1.55, 0))
		cyl(Vector3.new(0.12, 1.95, 1.95), Color3.fromRGB(60, 58, 60), S * CFrame.new(0, 1.38, 0))
		cyl(Vector3.new(0.8, 1.82, 1.82), STEEL_D, S * CFrame.new(0, 0.72, 0))   -- skirt
		cyl(Vector3.new(0.06, 1.86, 1.86), Color3.fromRGB(48, 44, 42),
			S * CFrame.new(0, 1.86, 0), Enum.Material.SmoothPlastic)     -- carbon on the crown
		-- wrist pin, straight through the skirt, and the rod hanging off it
		cylX(Vector3.new(2.0, 0.44, 0.44), STEEL, S * CFrame.new(0, 0.72, 0), Enum.Material.Metal, 0.1)
		p({ Size = Vector3.new(0.5, 1.5, 0.26), Color = CAST, Material = Enum.Material.Metal },
			S * CFrame.new(0, 0.0, 0) * CFrame.Angles(math.rad(9), 0, 0) * CFrame.new(0, 0.05, 0))
		p({ Size = Vector3.new(0.34, 1.5, 0.4), Color = CAST, Material = Enum.Material.Metal },
			S * CFrame.new(0, 0.0, 0) * CFrame.Angles(math.rad(9), 0, 0) * CFrame.new(0, 0.05, 0))
		-- big end: a split bearing with two cap bolts, the reason a rod looks like a rod. Its bore
		-- runs across the rod, so it is on the +X axis like the wrist pin above it.
		cylX(Vector3.new(0.62, 1.35, 1.35), CAST, S * CFrame.new(0, -0.72, 0.12))
		cylX(Vector3.new(0.66, 0.8, 0.8), Color3.fromRGB(74, 70, 68), S * CFrame.new(0, -0.72, 0.12))
		for _, sx in ipairs({ -1, 1 }) do
			cylX(Vector3.new(0.3, 0.3, 0.3), STEEL, S * CFrame.new(sx * 0.62, -0.72, 0.12))
		end
		p({ Size = Vector3.new(1.5, 0.12, 0.5), Color = RUST, Material = Enum.Material.CorrodedMetal },
			S * CFrame.new(0, -0.72, 0.12))

	elseif def.id == "rad" then
		-- ===== RADIATOR: A FINNED CORE BETWEEN TWO TANKS =====
		local S = base * CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(22), math.rad(-3))
		main = p({ Size = Vector3.new(3.0, 1.9, 0.5), Color = Color3.fromRGB(52, 50, 52),
			Material = Enum.Material.Metal }, S * CFrame.new(0, 1.55, 0))          -- core backing
		-- the fins. Sixteen thin slats is the whole trick: from a step away it is a radiator, and
		-- from across the field it is still a rectangle, which is all it needs to be.
		for i = 0, 15 do
			local bent = (i == 9) and math.rad(7) or 0        -- one fin knocked out of true
			p({ Size = Vector3.new(0.07, 1.86, 0.62), Color = STEEL_D, Material = Enum.Material.Metal },
				S * CFrame.new(-1.42 + i * 0.19, 1.55, 0) * CFrame.Angles(0, 0, bent))
		end
		for _, sy in ipairs({ -1, 1 }) do
			p({ Size = Vector3.new(3.3, 0.46, 0.78), Color = COPPER, Material = Enum.Material.Metal,
				Reflectance = 0.06 }, S * CFrame.new(0, 1.55 + sy * 1.16, 0))      -- top/bottom tanks
		end
		-- ===== THE PAINTED SHROUD =====
		-- A radiator is brass and steel, which on grass is a grey rectangle. The shroud around the
		-- core is painted the machine's own green on every real tractor -- so it is here, and the
		-- part goes from "grey rectangle" to "the green one" at fifty studs.
		for _, sx in ipairs({ -1, 1 }) do
			p({ Size = Vector3.new(0.34, 3.0, 0.9), Color = PAINT, Material = Enum.Material.Metal },
				S * CFrame.new(sx * 1.72, 1.55, 0))
		end
		for _, sy in ipairs({ -1, 1 }) do
			p({ Size = Vector3.new(3.8, 0.34, 0.9), Color = PAINT, Material = Enum.Material.Metal },
				S * CFrame.new(0, 1.55 + sy * 1.5, 0))
		end
		for _, sx in ipairs({ -1, 1 }) do
			p({ Size = Vector3.new(0.22, 2.4, 0.72), Color = STEEL_D, Material = Enum.Material.Metal },
				S * CFrame.new(sx * 1.6, 1.55, 0))                                 -- side channels
		end
		-- filler neck and cap, sat on the top tank
		cyl(Vector3.new(0.34, 0.62, 0.62), STEEL_D, S * CFrame.new(-0.9, 2.9, 0))
		cyl(Vector3.new(0.24, 0.8, 0.8), Color3.fromRGB(52, 50, 52), S * CFrame.new(-0.9, 3.14, 0))
		p({ Size = Vector3.new(0.86, 0.1, 0.2), Color = STEEL, Material = Enum.Material.Metal },
			S * CFrame.new(-0.9, 3.22, 0))                                         -- the cap's wing
		-- bottom hose stub, in perished black rubber, poking out the side of the bottom tank
		cylX(Vector3.new(0.7, 0.56, 0.56), Color3.fromRGB(38, 36, 38),
			S * CFrame.new(1.5, 0.39, 0), Enum.Material.SmoothPlastic)
		-- mounting feet, and rust where water has been sitting in one corner
		for _, sx in ipairs({ -1, 1 }) do
			p({ Size = Vector3.new(0.5, 0.24, 0.9), Color = STEEL_D, Material = Enum.Material.Metal },
				S * CFrame.new(sx * 1.5, 0.28, 0))
		end
		p({ Size = Vector3.new(0.8, 0.5, 0.8), Color = RUST, Material = Enum.Material.CorrodedMetal,
			Transparency = 0.25 }, S * CFrame.new(-1.25, 0.5, 0))

	else -- steer
		-- ===== STEERING WHEEL: A REAL RIM, NOT A DISC =====
		-- Eighteen short bars round a circle, each turned tangentially. A single flat cylinder was
		-- a plate with spokes drawn on it; this one you can see through, which is what a steering
		-- wheel mostly is.
		local S = base * CFrame.new(0, 1.95, 0) * CFrame.Angles(0, math.rad(-24), math.rad(-16))
		for i = 1, 18 do
			-- each bar's long side (its Z) already points along the tangent once Rx has swung it
			-- round the rim, so no extra turn: the ring closes on itself with a little overlap
			p({ Size = Vector3.new(0.32, 0.32, 0.66), Color = (i % 6 == 0) and TYRE_L or TYRE,
				Material = Enum.Material.SmoothPlastic },
				S * CFrame.Angles((i / 18) * math.pi * 2, 0, 0) * CFrame.new(0, 1.62, 0))
		end
		-- three spokes, dished back toward the hub like the real thing
		for i = 1, 3 do
			p({ Size = Vector3.new(0.2, 1.5, 0.26), Color = Color3.fromRGB(56, 52, 54),
				Material = Enum.Material.Metal },
				S * CFrame.Angles((i / 3) * math.pi * 2 + 0.5, 0, 0) * CFrame.new(-0.12, 0.85, 0)
					* CFrame.Angles(0, 0, math.rad(4)))
		end
		-- hub, cap and boss all sit on the column, so they are +X parts like the wheel's rim
		main = cylX(Vector3.new(0.62, 1.05, 1.05), Color3.fromRGB(56, 52, 54),
			S * CFrame.new(-0.18, 0, 0))
		-- a painted centre cap, so the steering wheel is "the green-and-black one" rather than the
		-- second black ring in the set
		cylX(Vector3.new(0.34, 0.9, 0.9), PAINT, S * CFrame.new(-0.42, 0, 0), Enum.Material.Metal)
		cylX(Vector3.new(0.3, 0.66, 0.66), RIM, S * CFrame.new(-0.5, 0, 0), Enum.Material.Metal, 0.06)
		cylX(Vector3.new(0.16, 0.3, 0.3), STEEL, S * CFrame.new(-0.66, 0, 0))
		-- the column stub it was pulled off, still on the back
		cylX(Vector3.new(1.1, 0.42, 0.42), STEEL_D, S * CFrame.new(0.5, 0, 0))
	end
	m.PrimaryPart = main

	-- ========================================================================
	-- THE PALLET IT WAS PUT DOWN ON
	-- ========================================================================
	-- A machine part lying loose in grass reads as litter. The same part on a pallet reads as a
	-- part somebody PUT there -- which is what these are, five components taken off a tractor and
	-- set aside. It costs six flat boards and it does more for how deliberate the pickups look
	-- than any amount of extra detail on the parts themselves.
	--
	-- Sized off the finished model's own footprint, so the wheel gets a big one and the plug a
	-- small one with nothing hand-tuned, and the whole thing sits UNDER base (see `ground`).
	--
	-- (!) IT IS ITS OWN MODEL, not part of this one, and that is three behaviours in one decision:
	--   * the idle bob and spin move the PART and leave the pallet standing still (a pallet
	--     hovering and turning in mid-air was the alternative),
	--   * picking the part up carries the part, not a pallet under your arm,
	--   * and the empty pallet stays behind where the part was, which is a nicer thing to leave
	--     than a bare patch of grass.
	-- It is built at the FINAL size (the part is scaled by PARTS.SCALE after this returns, so the
	-- footprint it has to match is the scaled one) and carries the same attributes, so the
	-- stale-build sweep treats a pallet exactly like the part it belongs to.
	local pal
	do
		local ok, _, bsz = pcall(m.GetBoundingBox, m)
		local w = math.clamp((ok and math.max(bsz.X, bsz.Z) or 5) * PARTS.SCALE * 0.95, 3.2, 9)
		pal = Instance.new("Model")
		pal.Name = "TractorPart_" .. def.id .. "_Pallet"
		pal:SetAttribute("QuestProp", true)
		pal:SetAttribute("Build", PARTS.BUILD)
		local function q(props, cf)
			local part = mk(props); part.CFrame = cf; part.Parent = pal; return part
		end
		for k = -1, 1 do
			q({ Name = "PalletDeck", Size = Vector3.new(w, 0.3, w * 0.27), Color = PLANK,
				Material = Enum.Material.WoodPlanks },
				ground * CFrame.new(0, 0.27, k * w * 0.34))
		end
		for _, sgn in ipairs({ -1, 1 }) do
			q({ Name = "PalletBearer", Size = Vector3.new(w * 0.92, 0.26, 0.6), Color = PLANK_D,
				Material = Enum.Material.Wood }, ground * CFrame.new(0, 0.1, sgn * w * 0.32))
		end
		-- loose straw across the boards: the one thing that stops a pallet reading as a crate lid
		for k = 1, 3 do
			q({ Name = "PalletStraw", Size = Vector3.new(w * 0.7, 0.12, 0.3), Color = WHEAT,
				Material = Enum.Material.Grass },
				ground * CFrame.new((k - 2) * w * 0.16, 0.44, (k % 2 - 0.5) * w * 0.3)
					* CFrame.Angles(0, k * 0.7, 0))
		end
		pal.Parent = questFolder
	end

	-- ========================================================================
	-- SOLID. NOT NEGOTIABLE.
	-- ========================================================================
	-- A collectible you can see the wall through is a collectible that looks broken, and there are
	-- four separate ways one of these ends up see-through:
	--   * Transparency copied from a template or set by an earlier pass,
	--   * LocalTransparencyModifier, which the engine's own camera code writes when something is
	--     between you and the camera -- it does not replicate and it is not Transparency, so it
	--     survives every check that only looks at the latter,
	--   * a Highlight with any FillTransparency below 1, which washes the model,
	--   * Glass / ForceField / Neon, which are see-through NO MATTER what Transparency says.
	-- All four are shut off here, on every part, every time -- and the pass runs LAST so nothing
	-- built above can quietly leave one on.
	--
	-- ...and NOTHING HERE IS SOLID TO WALK INTO. A 7-stud wheel with collision on is a wall in the
	-- middle of a field: you shove it, you climb it, you get wedged between it and the tractor, and
	-- on a prop that is bobbing and turning on the spot the shoving is constant. Every piece is
	-- CanCollide = false, forced here rather than trusted from the builder, so one props table with
	-- `CanCollide = true` in it cannot quietly put a bollard on the island. You walk through them
	-- and pick them up with E, which is the only interaction they have.
	local clear = 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = 0
			d.LocalTransparencyModifier = 0
			d.CanCollide = false
			if d.Material == Enum.Material.Glass or d.Material == Enum.Material.ForceField
				or d.Material == Enum.Material.Neon then
				d.Material = Enum.Material.SmoothPlastic
			end
			if d.Transparency > 0 then clear += 1 end
		elseif d:IsA("SelectionBox") or d:IsA("SelectionSphere") then
			d:Destroy()
		end
	end
	if clear > 0 then
		warn(("[Tractor] %s: %d part(s) refused to go opaque"):format(def.label, clear))
	end

	-- THE HIGHLIGHT IS AN OUTLINE ONLY. FillTransparency 1 -- not 0.6, not 0.92, ONE. Any fill at
	-- all tints the model and reads as a part that is fading out; the outline says "pick this up"
	-- perfectly well on its own and cannot make anything look see-through.
	local hl = Instance.new("Highlight")
	hl.FillColor = GOLD; hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(255, 236, 170); hl.OutlineTransparency = 0.05
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = m; hl.Parent = m

	-- ========================================================================
	-- NO FLOATING NAME LABEL. NOT ON THE PART, NOT ANYWHERE.
	-- ========================================================================
	-- There used to be a BillboardGui over every pickup reading "🔧 RADIATOR", visible for 280
	-- studs. Five of them turned the island into a wall of text you could read from the next
	-- island up, they stacked into an unreadable pile wherever two parts were near each other,
	-- and they rode along on your back once you picked one up.
	--
	-- Nothing is lost by deleting them: the part is a recognisable radiator, the gold outline says
	-- it is a pickup, and the E prompt names it in its ObjectText the moment you are close enough
	-- to take it. That is the same way every other island labels a collectible.
	m.Parent = questFolder
	-- the pallet comes back as a THIRD value so whoever built the part can clean up both together
	return m, main, pal
end

-- ============================================================================
-- A BROKEN TRACTOR SHOULD LOOK BROKEN
-- ============================================================================
-- Before this it was a perfectly clean machine that simply refused to start, so "broken" was a
-- fact the banner asserted rather than something you could see from across the field. Three
-- signs, all switched off the instant she catches:
--
--   SMOKE   -- a dirty rolling column off the stack, with a darker, slower core inside it. Two
--              layers, because one flat sheet of sprites is a decal and never reads as smoke.
--              Still a smoulder and not a fire: it drifts and thins rather than roaring.
--   SPARKS  -- big electrical bursts at irregular intervals from TWO points (the stack and the
--              loom behind the front wheel), each with a stutter of light on the machine. A
--              steady sparkle reads as decoration; uneven arcs in two places read as a fault.
--   A MISSING WHEEL, AND THE LEAN ONTO IT -- the silhouette does the work at any distance the
--              particles are too small to see, and she sits DOWN on the empty corner, because a
--              machine missing a wheel standing perfectly level says nothing is really wrong.
--              Wheel back on, engine running, and she picks herself up again.
-- make() and clear() hang off this table rather than being two more locals: this file runs at
-- 198 of Luau's 200 registers for a main chunk, and going over is a COMPILE failure -- the whole
-- script silently does not run. A table costs one register however many fields it carries.
-- (The table itself is declared up in the state block -- see the note there.)

function brokenFx.make()
	if not (tractorRoot and tractorRoot.Parent) then return end

	local a = Instance.new("Attachment")
	a.Name = "BrokenFx"
	a.Position = Vector3.new(-1.3, 4.6, -3.6)      -- the exhaust stack, same spot the ignition puffs
	a.Parent = tractorRoot

	-- ===== THE PLUME, IN TWO LAYERS =====
	-- One emitter was a thin grey thread you had to be looking for. The body is now a real,
	-- rolling, dirty column -- and a second, darker, slower layer sits inside it, which is what
	-- gives smoke depth instead of one flat sheet of sprites. Still a smoulder rather than a
	-- fire: it drifts and thins, it does not roar.
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "DeadEngineSmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(86, 82, 78)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(112, 108, 102)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(148, 146, 142)) })
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(0.35, 4.2),
		NumberSequenceKeypoint.new(1, 9.5) })
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 0.35), NumberSequenceKeypoint.new(0.25, 0.45),
		NumberSequenceKeypoint.new(1.00, 1) })
	smoke.Rate = 22
	smoke.Lifetime = NumberRange.new(2.4, 4.2)
	smoke.Speed = NumberRange.new(4, 7)
	smoke.SpreadAngle = Vector2.new(16, 16)
	smoke.Acceleration = Vector3.new(1.4, 3.2, 0.6)  -- climbs and leans off with the wind
	smoke.RotSpeed = NumberRange.new(-28, 28)        -- the roll is what stops it reading as decals
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.LightEmission = 0
	smoke.LightInfluence = 1
	smoke.Parent = a
	brokenFx.smoke = smoke

	local soot = smoke:Clone()                       -- the dark core, slower and tighter
	soot.Name = "DeadEngineSoot"
	soot.Color = ColorSequence.new(Color3.fromRGB(44, 42, 40), Color3.fromRGB(72, 70, 68))
	soot.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 4.0) })
	soot.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 0.15), NumberSequenceKeypoint.new(1.00, 1) })
	soot.Rate = 9
	soot.Lifetime = NumberRange.new(1.2, 2.0)
	soot.Speed = NumberRange.new(5, 8)
	soot.SpreadAngle = Vector2.new(7, 7)
	soot.Parent = a
	brokenFx.soot = soot

	-- ===== THE ELECTRICS ARE WORSE THAN THEY WERE =====
	-- Bigger, brighter bursts, more of them, and now with a light that flashes on the machine and
	-- a crackle of loose-wire sparks at a SECOND spot -- a fault you see once every few seconds
	-- from one point is a decoration; a fault arcing in two places is a machine in trouble.
	local spark = Instance.new("ParticleEmitter")
	spark.Name = "DeadEngineSparks"
	spark.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spark.Color = ColorSequence.new(Color3.fromRGB(255, 246, 200), Color3.fromRGB(255, 150, 40))
	spark.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 0) })
	spark.Transparency = NumberSequence.new(0.05)
	spark.Lifetime = NumberRange.new(0.3, 0.7)
	spark.Speed = NumberRange.new(9, 17)
	spark.SpreadAngle = Vector2.new(180, 180)
	spark.Acceleration = Vector3.new(0, -38, 0)     -- they fall, like real sparks off a loose wire
	spark.LightEmission = 1
	spark.Rate = 0                                  -- ALWAYS burst-fired, never a steady stream
	spark.Parent = a
	brokenFx.spark = spark

	-- the second arc point: down at the loom behind the front wheel
	local b = Instance.new("Attachment")
	b.Name = "BrokenFx2"
	b.Position = Vector3.new(1.4, 2.2, -2.6)
	b.Parent = tractorRoot
	local spark2 = spark:Clone()
	spark2.Name = "DeadEngineSparks2"
	spark2.Parent = b
	brokenFx.spark2 = spark2

	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 214, 150)
	flash.Range = 16; flash.Brightness = 0; flash.Enabled = true
	flash.Parent = tractorRoot
	brokenFx.flash = flash

	-- irregular on purpose: an evenly-timed spark is a decoration, an uneven one is a short.
	-- Gaps are shorter than they were and every burst is bigger, so the fault is something you
	-- notice from across the field rather than something you catch if you happen to be looking.
	task.spawn(function()
		while brokenFx.spark and brokenFx.spark.Parent and not engineRunning do
			task.wait(0.25 + math.random() * 1.1)
			if engineRunning then break end
			local s = (math.random() < 0.45 and brokenFx.spark2) or brokenFx.spark
			if s and s.Parent then
				s:Emit(math.random(10, 22))
				-- a stutter of light with it: two or three quick flickers, then dark
				if brokenFx.flash then
					task.spawn(function()
						for _ = 1, math.random(2, 4) do
							if not brokenFx.flash then return end
							brokenFx.flash.Brightness = 2.2 + math.random() * 1.6
							task.wait(0.04 + math.random() * 0.05)
							if not brokenFx.flash then return end
							brokenFx.flash.Brightness = 0
							task.wait(0.05)
						end
					end)
				end
			end
		end
	end)

	-- ===== THE MISSING WHEEL, AND THE LEAN ONTO IT =====
	-- Hidden, never destroyed: it is one of YOUR parts on an adopted model, and it has to come
	-- back. Collision goes off with it so nothing catches on an invisible wheel.
	for _, w in ipairs(wheelParts) do
		if w.part and w.part.Parent and w.part.Transparency < 1 then
			brokenFx.wheel = w.part
			brokenFx.wheelCF = w.off
			w.part.Transparency = 1
			w.part.CanCollide = false
			w.part.CanQuery = false
			break
		end
	end

	-- ...AND SHE SITS DOWN ON THAT CORNER. A machine missing a wheel standing perfectly level is
	-- the one thing in this scene that says "nothing is actually wrong". The lean is rolled toward
	-- whichever side the wheel came off (its offset's X tells us which) and dropped a little, so
	-- the empty hub is the low corner. tractorCF is the level frame, kept for clear() to restore.
	if brokenFx.wheelCF and tractorCF and not brokenFx.levelCF then
		local side = (brokenFx.wheelCF.Position.X >= 0) and 1 or -1
		local nose = (brokenFx.wheelCF.Position.Z >= 0) and 1 or -1
		brokenFx.levelCF = tractorRoot.CFrame
		tractorRoot.CFrame = brokenFx.levelCF
			* CFrame.Angles(0, 0, math.rad(side * 7))    -- roll onto the empty corner
			* CFrame.Angles(math.rad(nose * -2.5), 0, 0) -- and a touch of pitch with it
			* CFrame.new(0, -0.9, 0)
		poseTractor()                                    -- bring every bolted-on part with her
	end
end

-- ===== THE WHEEL GOES BACK ON THE MOMENT YOU FIT IT =====
-- Not when the engine catches -- when the WHEEL is fitted. Carrying a wheel across the island,
-- pressing E and watching the hub stay empty until four other parts and three turns of a key had
-- happened was the one moment in this quest where doing the right thing looked like nothing.
-- She stands up out of her lean at the same time, because the lean IS the missing wheel.
function brokenFx.wheelBack()
	if brokenFx.levelCF and tractorRoot and tractorRoot.Parent then
		tween(tractorRoot, 0.45, { CFrame = brokenFx.levelCF })   -- she settles, not snaps
		brokenFx.levelCF = nil
		task.delay(0.5, function()
			if tractorRoot and tractorRoot.Parent then poseTractor() end
		end)
	end
	if brokenFx.wheel and brokenFx.wheel.Parent then
		local w = brokenFx.wheel
		w.Transparency = 0
		w.CanCollide = true
		w.CanQuery = true
		poofAt(w.Position, YELLOW, 10)          -- it lands back on with a bit of ceremony
		shakeCamera(0.6, 0.25)
		brokenFx.wheel = nil
	end
end

-- ============================================================================
-- THE EXHAUST -- YOUR "smoke" PART, ONCE SHE IS RUNNING
-- ============================================================================
-- The broken plume above is a DEAD engine smouldering, and it stops the moment she catches. This
-- is the opposite: a running engine's exhaust, off the top of the part you named "smoke" in your
-- own model. Idling puffs; pulling away thickens it; parked-but-running settles back to a puff.
--
-- (!) THE ATTACHMENT GOES ON YOUR PART, NOT ON tractorRoot. The broken-engine plume hangs off the
-- root at a hardcoded (-1.3, 4.6, -3.6), which is a guess about where a stack is on a model this
-- script did not build. Parenting to your part means the plume is wherever you put the stack, at
-- whatever angle you set it, and it rides the machine without anything having to move it.
--
-- Built once, on the first frame the engine is running, and remembered either way: a model with no
-- "smoke" part must not re-walk its descendants sixty times a second looking for one.
function brokenFx.makeExhaust()
	if brokenFx.exhaustTried then return end
	brokenFx.exhaustTried = true
	if not (tractorModel and tractorModel.Parent) then
		brokenFx.exhaustTried = false      -- the model is not up yet; try again next frame
		return
	end
	local stack
	for _, d in ipairs(tractorModel:GetDescendants()) do
		if d:IsA("BasePart") and norm(d.Name) == "smoke" then stack = d; break end
	end
	if not stack then
		warn("[Tractor] no part named 'smoke' inside the tractor -- no exhaust plume. Name the "
			.. "stack's part 'smoke' in Studio and rejoin.")
		return
	end

	local a = Instance.new("Attachment")
	a.Name = "ExhaustAt"
	a.Parent = stack
	a.Position = Vector3.new(0, stack.Size.Y * 0.5 + 0.1, 0)   -- the TOP face, in the part's space

	local ex = Instance.new("ParticleEmitter")
	ex.Name = "Exhaust"
	ex.Texture = "rbxasset://textures/particles/smoke_main.dds"
	ex.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB( 78,  76,  74)),
		ColorSequenceKeypoint.new(0.40, Color3.fromRGB(122, 120, 116)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(168, 166, 162)) })
	ex.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 4.2) })
	ex.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 0.4), NumberSequenceKeypoint.new(0.25, 0.5),
		NumberSequenceKeypoint.new(1.00, 1) })
	ex.Lifetime = NumberRange.new(1.1, 1.9)
	ex.Speed = NumberRange.new(7, 11)
	ex.SpreadAngle = Vector2.new(9, 9)
	ex.Acceleration = Vector3.new(0.8, 7, 0.4)     -- climbs, and drifts off one shoulder
	ex.EmissionDirection = Enum.NormalId.Top       -- straight up out of the stack
	ex.Rotation = NumberRange.new(0, 360)
	ex.RotSpeed = NumberRange.new(-30, 30)
	ex.LightInfluence = 1
	ex.Rate = 0                                    -- the drive loop owns this
	ex.Parent = a

	brokenFx.exhaust = ex
	print(("[Tractor] exhaust plume on your '%s' part (top face, %.1f studs up)")
		:format(stack.Name, stack.Size.Y * 0.5))
end

function brokenFx.clear()
	-- fade the plume out rather than cutting it: a stack that stops dead mid-puff looks like
	-- a bug, and the last wisps clearing as she catches is exactly the right beat.
	for _, key in ipairs({ "smoke", "soot" }) do
		local sm = brokenFx[key]
		if sm then
			sm.Rate = 0
			task.delay(4, function() if sm and sm.Parent then sm:Destroy() end end)
			brokenFx[key] = nil
		end
	end
	for _, key in ipairs({ "spark", "spark2" }) do
		if brokenFx[key] then brokenFx[key]:Destroy(); brokenFx[key] = nil end
	end
	if brokenFx.flash then brokenFx.flash:Destroy(); brokenFx.flash = nil end
	-- ...and the wheel/lean half, in case the engine was started without the wheel ever being
	-- fitted -- /fix does exactly that. Fitted normally this has already run and does nothing.
	brokenFx.wheelBack()
end

local function pickUpPart(rec)
	if rec.taken then return end
	-- THE PROMPT ALWAYS ANSWERS. Pressed too early or with your hands full it SAYS which, instead
	-- of being a dead E that reads as a bug.
	if step < 1 then
		-- ON THE REALM BANNER, not in this quest's own strip. "You have not taken this job yet" is
		-- the same sentence on every island, and it belongs in the one place a player already
		-- watches for news -- _G.questLocked (DoneCommand.client.luau) puts it through NotifyCenter
		-- at EVENT priority, above the standing objective. The strip is the fallback for a server
		-- where that script has not loaded.
		local msg = ("%s That's off the tractor -- talk to the farmer before you go hauling it about!")
			:format(rec.def.emoji)
		if _G.questLocked then pcall(_G.questLocked, "the Broken Tractor", msg)
		else flashBanner(msg, 2.5) end
		return
	end
	if step > 2 then return end                 -- she is already fixed; nothing left to fit
	if carrying then
		flashBanner(("%s Hands full -- fit the %s first!"):format(E_WRENCH, carrying.def.label), 2.5)
		return
	end
	rec.taken = true
	carrying = rec
	if rec.prompt then rec.prompt.Enabled = false end
	-- BELT AND BRACES: these props are built with no BillboardGui at all now, so this normally
	-- finds nothing. It stays because a stale copy of this script builds props that DO have one,
	-- and a label riding on your back and then hanging over the tractor is the exact symptom that
	-- took three passes to track down. Destroyed, never hidden and never reparented.
	for _, d in ipairs(rec.model:GetDescendants()) do
		if d:IsA("BillboardGui") then d:Destroy() end
	end
	-- IN FRONT, like the bale stack: a root part looks down its NEGATIVE Z, so -1.9 is out ahead of
	-- you and +1.9 is the small of your back. Carrying a radiator where you cannot see it told you
	-- nothing about what you were holding; out front it is the answer to "which one did I pick up".
	-- the "part_" ids are the contract with CarryView / CarrySync: five parts, five shapes, so a
	-- friend can tell across the field whether you went and got the radiator or the wheel again
	carryProp(rec.model, CFrame.new(0, 1.3, -1.9) * CFrame.Angles(math.rad(14), 0, math.rad(-8)),
		"part_" .. rec.def.id)
	flashBanner(("%s Got the %s! Take it to its bay."):format(rec.def.emoji, rec.def.label), 2.5)
	refreshBanner(); refreshPrompts()
end

-- ============================================================================
-- WHERE THE PARTS SPAWN: YOUR MARKERS, AND NOWHERE ELSE
-- ============================================================================
-- ⚠ THERE IS NO FALLBACK, ON PURPOSE, AND PUTTING ONE BACK WOULD UNDO THE POINT OF THIS.
-- This used to invent positions for any part you had not placed: first an island-wide scatter,
-- later a ring around the markers you had drawn. Both had the same failure -- half the parts
-- stood where you put them and half stood somewhere the script chose, in the open, sometimes off
-- the deck, and the two were indistinguishable to a player. A part with no marker is now a
-- WARNING AND NOTHING ELSE. An island that is missing a marker should look obviously unfinished
-- in the log, not quietly finished in the wrong place.
--
-- Each part takes its OWN marker, matched by name (case, spaces, underscores and hyphens are all
-- ignored -- "Back Wheel", "backwheel" and "BACK_WHEEL" are one name). Every alias any of these
-- has plausibly been called is listed on the def, so whichever you used is the one that works:
--   Back Wheel      BackWheel / Wheel / RearWheel / TractorWheel
--   Spark Plug      SparkPlug / Plug / Engine / Spark
--   Piston          Piston / ConRod
--   Radiator        Radiator / Rad
--   Steering Wheel  SteeringWheel / Steering / SteerWheel
-- "Wheel" belongs to the back wheel and "SteeringWheel" to the steering wheel: names are matched
-- WHOLE, never as substrings, so those two can never take each other's marker.
--
-- A generic "TractorPart" block still counts -- it is hand-placed too, which is the only thing
-- this function cares about -- and unclaimed ones are handed out in a fixed left-to-right order
-- to whichever parts have no marker of their own. That is the old workflow, still working.
--
-- POSITION AND ROTATION BOTH COME FROM THE MARKER. Turn a marker in Studio and the part lies the
-- way you turned it.
local function placeParts()
	-- ===== ANY EARLIER COPY GOES FIRST =====
	-- Called twice (a re-run, a rebuild, a second boot path) this would otherwise leave the first
	-- set standing in the world with dead prompts, which is exactly the "duplicate floating in the
	-- open" this is meant to end.
	for _, rec in ipairs(partRecs) do
		if rec.model and rec.model.Parent then rec.model:Destroy() end
		if rec.pallet and rec.pallet.Parent then rec.pallet:Destroy() end
	end
	table.clear(partRecs)

	-- (!) A MARKER THE TRACTOR HAS ALREADY EATEN IS NOT A MARKER. The machine adopts loose parts
	-- named "wheel" within WHEEL_ADOPT_RANGE of its block and bolts them on as its own wheels
	-- (see buildTractor) -- and that runs before this does. Without this check, a "Wheel" marker
	-- drawn near the tractor would be adopted as a wheel AND then hidden and built on as the
	-- back-wheel pickup: one prop, two owners, and a wheel that vanishes off the machine.
	local claimed, generic = {}, {}
	local function usable(d)
		return not (tractorModel and d:IsDescendantOf(tractorModel)) and not claimed[d]
	end
	for _, d in ipairs(findAllNamed(island, PART_NAME)) do
		if usable(d) then generic[#generic + 1] = d end
	end
	-- ...AND THE REPAIR-BAY BLOCKS, WHEN THEY ARE NOT BEING USED AS BAYS. buildSockets decides
	-- that (see the long note there): an island whose only markers are "FixTractor" blocks has
	-- marked out where the PARTS go, not where they get delivered. They join the generic pool, so
	-- the parts land on them left to right exactly as a set of "TractorPart" blocks would.
	if PARTS.baysUsed == false then
		for _, alias in ipairs({ "fixtractor", "fixplacement", "fixspot", "repairbay" }) do
			for _, d in ipairs(findAllNamed(island, alias)) do
				if usable(d) then generic[#generic + 1] = d end
			end
		end
	end
	table.sort(generic, function(a, b)
		local pa, pb = baseFrameOf(a).Position, baseFrameOf(b).Position
		if math.abs(pa.X - pb.X) > 0.5 then return pa.X < pb.X end
		return pa.Z < pb.Z
	end)
	local nextGeneric = 1

	local placed, missing = 0, {}
	for _, def in ipairs(PARTS) do
		-- its own named marker first...
		local marker, how
		for _, alias in ipairs(def.markers) do
			for _, d in ipairs(findAllNamed(island, alias)) do
				if usable(d) then marker, how = d, alias; break end
			end
			if marker then break end
		end
		-- ...then the next unclaimed generic block, if there is one
		while not marker and nextGeneric <= #generic do
			local d = generic[nextGeneric]
			nextGeneric += 1
			if usable(d) then marker, how = d, PART_NAME end
		end

		if not marker then
			missing[#missing + 1] = def.label
			warn(("[Tractor] NO MARKER for the %s -- it was NOT spawned. Draw a small part named "
				.. "'%s' (or any of: %s) inside %s and rejoin.")
				:format(def.label, def.markers[1], table.concat(def.markers, ", "), ISLAND_NAME))
		else
			claimed[marker] = true
			-- ===== THE FRAME THE PART IS BUILT IN =====
			-- Position straight off the marker's base. Rotation is the marker's YAW ONLY:
			--
			-- (!) A MARKER'S PITCH AND ROLL ARE NOT AN INSTRUCTION. These are small blocks dropped
			-- to say "here" -- flat plates, thin slabs, a stand-in laid on its side -- and taking
			-- their full orientation tipped the whole prop with them. A radiator built in a frame
			-- rolled 90 degrees lies on its face half-buried in the grass, which reads as a flat
			-- placeholder rather than as a radiator. Yaw survives (turn a marker and the part
			-- turns with it); pitch and roll are dropped so the part always stands up.
			local mcf, msz = baseFrameOf(marker)
			local _, yaw = mcf:ToEulerAnglesYXZ()
			local at = CFrame.new(mcf.Position) * CFrame.Angles(0, yaw, 0)
			-- hidden BEFORE the seating ray below, so the block cannot be its own answer
			hideMarker(marker)

			local m, main, pal = buildPartProp(def, at)
			-- PIVOT AT THE MARKER'S BASE, then scale. ScaleTo grows a model about its pivot, so
			-- with the pivot on the ground the part grows UPWARD out of the spot you chose instead
			-- of sinking half its new height into it. It is also what lets the idle bob below be
			-- written as "the home frame, plus a little" rather than as a guess about the pivot.
			m.WorldPivot = at
			if math.abs(PARTS.SCALE - 1) > 0.01 then m:ScaleTo(PARTS.SCALE) end

			-- ========================================================================
			-- SEATED ON THE SURFACE -- MEASURED, PER PART, AFTER IT IS BUILT
			-- ========================================================================
			-- ⚠ baseFrameOf gives the marker's BASE, and that is only ground level if the block is
			-- sitting ON the ground. Sink a 6-stud block three studs into the field to mark a spot
			-- -- which is what everybody does -- and everything built on it starts three studs
			-- underground. The back wheel came out as a dome poking through the grass.
			--
			-- So the height is not assumed, it is MEASURED: build the part, take the assembled
			-- bounding box, and lift the whole thing until its lowest face rests on the surface.
			-- No hardcoded offsets -- the wheel is 7 studs tall and the plug is 3, and neither
			-- number appears anywhere here.
			--
			-- ========================================================================
			-- THE SURFACE IS THE GROUND. NOT THE BLOCK.
			-- ========================================================================
			-- (!) THIS ORDER IS THE FIX, AND IT USED TO BE THE OTHER WAY ROUND. Seating on the
			-- marker's own faces sounds right and is wrong in both directions, because THE MARKER
			-- IS HIDDEN by the time anyone sees the part:
			--   * a block sunk into the field puts its top face underground, so the part is buried
			--     to the shoulders -- which is what you were still seeing,
			--   * a block standing proud of the field puts its top face in the air, so the part
			--     balances on an invisible pillar.
			-- Neither is a surface a player can see. The GROUND is, so the ground wins: a ray from
			-- 120 studs up (the marker already hidden, so it cannot answer its own question), then
			-- the island's floor of record if the ray finds nothing at all, and only as a last
			-- resort the block itself. X, Z and yaw are never touched -- only the height.
			local surfaceY
			do
				refreshRayFilter()
				local hit = Workspace:Raycast(at.Position + Vector3.new(0, 120, 0),
					Vector3.new(0, -500, 0), rayParams)
				surfaceY = (hit and hit.Position.Y)
					or floorTopY
					or (at.Position.Y + msz.Y)
				-- ...and never below the deck, whatever the ray came back with. A part cannot be
				-- under the island it is standing on.
				if floorTopY and surfaceY < floorTopY - 2 then surfaceY = floorTopY end
			end
			-- the lowest face of everything that stands here: the part AND the pallet under it
			local function bottomOf(mdl)
				if not mdl then return nil end
				local ok, c, s = pcall(mdl.GetBoundingBox, mdl)
				if not (ok and c) then return nil end
				return c.Position.Y - s.Y * 0.5
			end
			-- the assembly's lowest face, whichever piece owns it. On a leaning wheel that is the
			-- TYRE, not the pallet -- which is why the gap below is measured the same way rather
			-- than off the pallet alone: measuring the pallet on a part that hangs past it reported
			-- "0.64 studs above the surface" for something already touching the ground.
			local function assemblyBottom()
				local a, b = bottomOf(m), bottomOf(pal)
				if a and b then return math.min(a, b) end
				return a or b
			end
			local lowest = assemblyBottom()
			if lowest then
				local dy = surfaceY - lowest
				if math.abs(dy) > 0.001 then
					m:PivotTo(m:GetPivot() + Vector3.new(0, dy, 0))
					if pal then pal:PivotTo(pal:GetPivot() + Vector3.new(0, dy, 0)) end
					at = at + Vector3.new(0, dy, 0)      -- the idle loop poses from here
				end
			end
			local gap = (assemblyBottom() or surfaceY) - surfaceY
			-- ===== THE OPACITY RECEIPT =====
			-- buildPartProp forces every piece opaque; this reports what actually stuck, per part,
			-- as the HIGHEST transparency anywhere in the model. Anything but 0.00 here is a real
			-- fault worth chasing, and printing it per part is how you tell "they all look faded"
			-- (a camera or highlight effect) from "one model is wrong" (this number).
			local worst, pieces = 0, 0
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					pieces += 1
					if d.Transparency > worst then worst = d.Transparency end
				end
			end
			print(("[Tractor] %s spawned on marker '%s' (%s) at %.1f, %.1f, %.1f "
				.. "| seated: surface Y=%.1f, gap %.2f | yaw %.0f deg, x%.2f, %d parts, "
				.. "max transparency %.2f")
				:format(def.label, marker.Name, how, at.Position.X, at.Position.Y, at.Position.Z,
					surfaceY, gap, math.deg(yaw), PARTS.SCALE, pieces, worst))
			if math.abs(gap) > 0.15 then
				warn(("[Tractor] %s is NOT sitting flush -- %.2f studs %s the surface.")
					:format(def.label, math.abs(gap), gap > 0 and "above" or "below"))
			end
			if worst > 0 then
				warn(("[Tractor] %s is NOT fully opaque (max transparency %.2f) -- something is "
					.. "setting it after the build."):format(def.label, worst))
			end
			placed += 1
			local rec = { def = def, model = m, main = main, pallet = pal, taken = false, home = at }
			-- ===== ONE E PROMPT PER PART, AND IT IS THE ORDINARY ONE =====
			-- (!) NOT bigPrompt. The big custom card -- rounded panel, giant E badge, subtitle --
			-- belongs to the TRACTOR and nothing else: it is the one object in this quest you
			-- mount and repair, and the card is what makes it read as a machine you operate rather
			-- than a thing you touch. On five pickups and an NPC it was just loud, and it looked
			-- nothing like the pickups on every other island.
			--
			-- These are stock ProximityPrompts with the settings the rest of the realm uses --
			-- HoldDuration 0, PICKUP_RANGE, no line-of-sight requirement -- so a part here feels
			-- exactly like a syrup bottle on island18 or a gumball on island1.
			--
			-- The prompt is never disabled until the part is taken (see refreshPrompts): a thing
			-- you can see and cannot press is indistinguishable from a thing that is broken, so it
			-- answers at every step and says why when the answer is no.
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Pick Up"; prompt.ObjectText = def.label
			prompt.HoldDuration = 0
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.MaxActivationDistance = PICKUP_RANGE
			prompt.RequiresLineOfSight = false
			prompt.Parent = main
			prompt.Triggered:Connect(function() pickUpPart(rec) end)
			rec.prompt = prompt
			print(("[Tractor] %s -> DEFAULT prompt ('Pick Up' / '%s', %d studs, hold %.1f)")
				:format(def.label, def.label, PICKUP_RANGE, prompt.HoldDuration))
			partRecs[#partRecs + 1] = rec
		end
	end

	if #missing > 0 then
		warn(("[Tractor] %d of %d parts have no marker and were skipped: %s. The quest CANNOT be "
			.. "finished until every one has a marker -- nothing is auto-placed any more.")
			:format(#missing, PART_COUNT, table.concat(missing, ", ")))
	end
	print(("[Tractor] %d/%d part(s) spawned on hand-placed markers, build '%s' at x%.2f -- no "
		.. "auto-placement exists"):format(placed, PART_COUNT, PARTS.BUILD, PARTS.SCALE))

	-- ========================================================================
	-- AND THE REPAIR BAYS GET THE REAL PART TOO -- SOLID, BUT UNPAINTED
	-- ========================================================================
	-- A bay used to be a gold marble with a name tag over it: it tells you a part goes here, not
	-- WHICH, and it never looks like anything. Each bay now holds a full copy of the actual part.
	--
	-- (!) IT IS SOLID, NOT SEE-THROUGH. This was a 40%-transparent ghost and that was a mistake:
	-- from a few studs away a translucent radiator standing in a bay is indistinguishable from a
	-- COLLECTIBLE radiator that has gone wrong, and "why can I see the wall through the parts" is
	-- exactly the bug report it produced. Nothing in this quest is ever transparent now.
	--
	-- "Not fitted yet" is said with COLOUR instead: the bay copy is a bare grey casting, and
	-- fitting the real part paints it -- every piece snaps back to its true colour at once (each
	-- part carries its own colour in a TrueColor attribute, set below). Same shape, same place,
	-- and the moment of fitting is the model going from a foundry blank to a finished component.
	--
	-- It lives HERE rather than in buildSockets because buildPartProp is written below that
	-- function: called from up there the name would resolve to a nil global and every bay would
	-- error. placeParts runs after both, which makes this the first place that can see all three.
	for _, def in ipairs(PARTS) do
		local sock = sockets[def.id]
		if sock and sock.at and not sock.ghost then
			-- sock.at floats 2.6 above the bay's base; back it off to get the base frame, then
			-- keep the yaw and drop the tilt, exactly as the pickups do
			local baseAt = sock.at * CFrame.new(0, -2.6, 0)
			local _, yaw = baseAt:ToEulerAnglesYXZ()
			local at = CFrame.new(baseAt.Position) * CFrame.Angles(0, yaw, 0)
			local ghost = buildPartProp(def, at)
			ghost.Name = "BayGhost_" .. def.id
			ghost:SetAttribute("QuestProp", nil)     -- not a pickup: keep it out of the prop sweeps
			ghost.WorldPivot = at
			if math.abs(PARTS.SCALE - 1) > 0.01 then ghost:ScaleTo(PARTS.SCALE) end
			for _, d in ipairs(ghost:GetDescendants()) do
				if d:IsA("BasePart") then
					d:SetAttribute("TrueColor", d.Color)   -- what it becomes when the part is fitted
					d.Color = Color3.fromRGB(122, 124, 128) -- bare casting: unpainted, not unreal
					-- (materials are LEFT ALONE: they are already right, and restoring a second
					-- property on fit is a second thing to get wrong for no visible gain)
					d.Transparency = 0                      -- SOLID. See the note above.
					d.LocalTransparencyModifier = 0
					d.CanCollide = false
					d.CanQuery = false               -- the bay's own E prompt must win every time
				elseif d:IsA("Highlight") or d:IsA("BillboardGui") then
					d:Destroy()                      -- the bay already has a sign; two is noise
				end
			end
			sock.ghost = ghost
			-- the gold marble shrinks to a glow at the ghost's feet: the pulse still says "empty",
			-- it just no longer stands in for the part it was never shaped like
			if sock.hole then
				sock.hole.Size = Vector3.new(1.1, 1.1, 1.1)
				sock.hole.CFrame = CFrame.new(at.Position) * CFrame.new(0, 0.6, 0)
			end
		end
	end

	-- ========================================================================
	-- THEY TURN AND BREATHE WHERE THEY STAND
	-- ========================================================================
	-- A quest item lying dead still in long grass is scenery. A slow turn plus a shallow bob is
	-- the oldest pickup idiom there is, and it costs one loop for the whole set.
	--
	-- Driven off rec.home (the marker frame) rather than off wherever the model currently is, so
	-- the motion can never drift: every frame is an absolute pose, not an increment. Anything
	-- taken or carried is skipped -- the carry loop owns those, and two writers to one PivotTo is
	-- a part that flickers between your hands and the field.
	-- (!) AND THE PROMPTS ARE RE-ASSERTED HERE, half a second at a time. refreshPrompts sets them
	-- when the quest state changes, which is correct and not enough: a prompt can be switched off
	-- by a stale duplicate of this script, by a refresh that ran while a record was half-built, or
	-- by anything else on the island that walks PlayerGui and the workspace. "The E prompt is not
	-- always showing" is unanswerable without this, because there is no way to tell a prompt that
	-- was never enabled from one that something else turned off afterwards. Now the answer is the
	-- same either way: it comes back within half a second, forever.
	pcall(function() PromptService.MaxPromptsVisible = 8 end)   -- five was not many, with bays about
	task.spawn(function()
		local reassert = 0
		while true do
			local t = os.clock()
			if t - reassert > 0.5 then
				reassert = t
				for _, rec in ipairs(partRecs) do
					if rec.prompt and rec.prompt.Parent then
						rec.prompt.Enabled = not rec.taken
					end
				end
			end
			for i, rec in ipairs(partRecs) do
				if rec.home and not rec.taken and rec.model and rec.model.Parent then
					-- staggered by index, so five props do not rise and fall as one block.
					-- (!) THE BOB STARTS AT ZERO. It used to sit 0.2..0.9 studs up, which was fine
					-- when home was a guess and is wrong now that home is measured: the part is
					-- seated exactly on the surface, so anything with a floor above 0 leaves it
					-- permanently hovering. It lifts a third of a stud and settles back down.
					local phase = t * 0.9 + i * 1.3
					rec.model:PivotTo(rec.home
						* CFrame.new(0, 0.16 + math.sin(phase) * 0.16, 0)
						* CFrame.Angles(0, t * 0.55 + i, 0))
				end
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

-- ============================================================================
-- FITTING A PART, AND THE IGNITION
-- ============================================================================
local openFixHUD, closeFixHUD, updateFixHUD    -- forward: the HUD is built below
local ignitionTries = 0

-- THE PART IS ONLY SEATED WHEN THE REPAIR PANEL SAYS THE JOB IS DONE. This half is the old
-- fitPart body, unchanged apart from reading sock.at (a repair bay standing on the ground) as
-- well as sock.off (a socket riding on the machine) -- see buildSockets for which is which.
FH.seat = function(rec)
	if carrying ~= rec then return end          -- dropped, respawned or /fixed while it was open
	local sock = sockets[rec.def.id]
	carrying = nil
	dropCarried(rec.model)

	local goal = sock.at or (tractorRoot and tractorRoot.CFrame * sock.off)
	-- the part flies to its socket and disappears into the machine
	if rec.model.Parent and goal then
		rec.model:PivotTo(goal)
		for _, d in ipairs(rec.model:GetDescendants()) do
			if d:IsA("Highlight") or d:IsA("BillboardGui") then d.Enabled = false end
		end
		task.delay(0.25, function() if rec.model.Parent then rec.model:Destroy() end end)
	end
	sock.filled = true
	if sock.tag then sock.tag.Enabled = false end   -- only bays have one; the machine never does
	if sock.prompt then sock.prompt.Enabled = false end
	-- THE BAY COPY GETS PAINTED. It has been standing there as a bare grey casting of this exact
	-- part; fitting it is that casting becoming the finished component -- every piece back to the
	-- colour it was built with, in one frame. Same model, same place, so there is no swap to see:
	-- the thing you were aiming at simply becomes real. (Transparency is never touched: nothing in
	-- this quest is see-through, before or after.)
	if sock.ghost then
		for _, d in ipairs(sock.ghost:GetDescendants()) do
			if d:IsA("BasePart") then
				local trueColour = d:GetAttribute("TrueColor")
				if typeof(trueColour) == "Color3" then d.Color = trueColour end
				d.Transparency = 0
				d.LocalTransparencyModifier = 0
			end
		end
		poofAt(sock.at.Position, GOLD, 8)
	end
	fitted += 1
	-- THE WHEEL IS THE ONE PART YOU CAN SEE FROM OUTSIDE. Fit it and it goes straight back on the
	-- hub and she stands up out of her lean -- the other four are internal and show nothing until
	-- she runs, but this one has to answer immediately or fitting it looks like it did nothing.
	if rec.def.id == "wheel" and brokenFx.wheelBack then brokenFx.wheelBack() end
	if goal then poofAt(goal.Position, GOLD, 12) end
	shakeCamera(0.5, 0.2)
	refreshBanner(); refreshPrompts()

	if fitted >= PART_COUNT then
		step = 3
		refreshBanner()
		flashBanner(E_KEY .. " That's the lot -- TURN THE KEY!", 3.5)
		if openFixHUD then openFixHUD() end
	else
		flashBanner(("%s %s fitted!  %d/%d"):format(E_WRENCH, rec.def.label, fitted, PART_COUNT), 2.5)
	end
end

-- BOTH WAYS IN LAND HERE: a repair bay's own prompt, and the tractor's "Fit The Part" on an
-- island with no bays drawn. So the little repair job happens exactly once per part however you
-- got to it, and there is one place to change what fitting a part means.
fitPart = function()
	if not carrying then return end
	local rec = carrying
	if FH.openPart then
		FH.openPart(rec, function(ok) if ok then FH.seat(rec) end end)
	else
		FH.seat(rec)                            -- no panel built (cannot happen) -> never strand
	end
end

local engineRunning = false
local startDriving  -- forward

local function turnTheKey()
	if step ~= 3 then return end
	ignitionTries += 1
	shakeCamera(1.0, 0.4)
	poofAt(tractorRoot.CFrame.Position + Vector3.new(-1.3, 4.8, -3.6), Color3.fromRGB(80, 78, 76), 8)
	if updateFixHUD then updateFixHUD() end
	if ignitionTries < IGNITION_TRIES then
		flashBanner(E_KEY .. " ...cough... splutter... try again!", 2)
		return
	end
	-- ===== IT CATCHES =====
	engineRunning = true
	brokenFx.clear()                 -- smoke dies, sparks stop, the wheel goes back on
	step = 4
	if closeFixHUD then closeFixHUD() end
	shakeCamera(2.2, 1.0)
	poofAt(tractorRoot.CFrame.Position + Vector3.new(-1.3, 5.2, -3.6), Color3.fromRGB(80, 78, 76), 20)
	flashBanner(E_TRACTOR .. " IT RUNS! Hop on and cut that wheat!", 3.5)
	refreshBanner(); refreshPrompts()
	if npcHead then showBubble(npcHead, "LISTEN to her purr! Get harvesting!", false) end
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(function() _G.NotifyCenter.push({ text = E_TRACTOR .. " The tractor is fixed!", color = GREEN_T }) end)
	end
end

-- ---- the repair HUDs: one job per part, then the ignition -------------------
-- (FH itself is declared way up in the state block -- see the note there. Only its contents are
-- built here, next to the code that drives them.)
do
	-- THE GAME'S OWN BOTTOM HUD DUCKS OUT while either repair panel is up: the fart meter and its
	-- button sit right under the panel's own buttons. Remember what was Enabled, switch it off,
	-- put it back EXACTLY as it was -- and refcount it, because the ignition panel opens the
	-- instant the fifth part's panel finishes and one closing under the other would hand the HUD
	-- back with a panel still on screen.
	local held, prev = {}, nil
	function FH.setHud(tag, hidden)
		held[tag] = hidden or nil
		local any = next(held) ~= nil
		if any and not prev then
			prev = {}
			for _, n in ipairs({ "BottomStackGui", "GasMeterGui", "FartButtonGui", "StomachGui" }) do
				local sg = PlayerGui:FindFirstChild(n)
				if sg and sg:IsA("ScreenGui") then prev[n] = sg.Enabled; sg.Enabled = false end
			end
		elseif not any and prev then
			for n, was in pairs(prev) do
				local sg = PlayerGui:FindFirstChild(n)
				if sg and sg:IsA("ScreenGui") then sg.Enabled = was end
			end
			prev = nil
		end
	end
end

do
	local g = Instance.new("ScreenGui")
	g.Name = "TractorFixHUD"; g.ResetOnSpawn = false; g.DisplayOrder = 12
	g.Enabled = false; g.Parent = PlayerGui
	FH.gui = g

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 1); panel.Position = UDim2.new(0.5, 0, 1, -30)
	panel.Size = UDim2.new(0, 560, 0, 240); panel.BackgroundColor3 = FILL
	panel.BorderSizePixel = 0; panel.Parent = g
	-- HOUSE PANEL: the Pet Hub's 700x520 card at (0.5,0),(0.5,-45), and the bottom
	-- buttons hide while it is up. One call does both -- see HousePanel.client.luau.
	-- The panel keeps its own size and every child keeps its own pixel coordinates;
	-- it is centred in the house shell and scaled to fit, so nothing inside moves.
	pcall(_G.housePanel, panel)   -- island19 part repair
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 3; s.Parent = panel end

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1; title.Position = UDim2.new(0, 20, 0, 12)
	title.Size = UDim2.new(1, -90, 0, 32); title.Font = Enum.Font.FredokaOne
	title.TextSize = 24; title.TextColor3 = TEXTC; title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Starting the engine"; title.Parent = panel

	-- X only. A stray tap on the backdrop must never shut a panel in this realm.
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0); close.Position = UDim2.new(1, -14, 0, 12)
	close.Size = UDim2.fromOffset(38, 38); close.BackgroundColor3 = STROKE
	close.Text = "X"; close.Font = Enum.Font.FredokaOne; close.TextSize = 20
	close.TextColor3 = Color3.new(1, 1, 1); close.BorderSizePixel = 0; close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 12)
	-- through closeFixHUD, not straight at .Enabled: the bottom HUD has to come back with it
	close.Activated:Connect(function() if closeFixHUD then closeFixHUD() end end)

	local lab = Instance.new("TextLabel")
	lab.BackgroundTransparency = 1; lab.Position = UDim2.new(0, 20, 0, 54)
	lab.Size = UDim2.new(1, -40, 0, 18); lab.Font = Enum.Font.GothamBold
	lab.TextSize = 14; lab.TextColor3 = HINTC; lab.TextXAlignment = Enum.TextXAlignment.Left
	lab.Text = "IGNITION"; lab.Parent = panel
	FH.label = lab

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 20, 0, 76); track.Size = UDim2.new(1, -40, 0, 24)
	track.BackgroundColor3 = Color3.fromRGB(238, 228, 210); track.BorderSizePixel = 0; track.Parent = panel
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = GREEN_T
	fill.BorderSizePixel = 0; fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	FH.fill = fill

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1; hint.Position = UDim2.new(0, 20, 0, 106)
	hint.Size = UDim2.new(1, -40, 0, 20); hint.Font = Enum.Font.GothamBold
	hint.TextSize = 15; hint.TextColor3 = HINTC; hint.Text = ""; hint.Parent = panel
	FH.hint = hint

	local key = Instance.new("TextButton")
	key.AnchorPoint = Vector2.new(0.5, 1); key.Position = UDim2.new(0.5, 0, 1, -16)
	key.Size = UDim2.new(0, 300, 0, 76); key.BackgroundColor3 = GOLD
	key.Font = Enum.Font.FredokaOne; key.TextSize = 26; key.TextColor3 = TEXTC
	key.BorderSizePixel = 0; key.AutoButtonColor = false
	key.Text = E_KEY .. " TURN THE KEY"; key.Parent = panel
	Instance.new("UICorner", key).CornerRadius = UDim.new(0, 16)
	-- Activated, not MouseButton1Click: it fires for touch and controller too
	key.Activated:Connect(function()
		key.Size = UDim2.new(0, 288, 0, 70)
		tween(key, 0.18, { Size = UDim2.new(0, 300, 0, 76) }, Enum.EasingStyle.Back)
		turnTheKey()
	end)
end

-- ============================================================================
-- THE PART REPAIR PANEL -- one small job per part
-- ============================================================================
-- Carrying a part to its bay and pressing E used to fit it outright: five prompts, five puffs of
-- smoke, no repair. This is the repair. It is deliberately EASY -- four bolts, tighten the one
-- that is lit, in a random order so it is a look-and-tap rather than a rhythm you can do blind --
-- because the JOB of this quest is finding the five parts, and this is the moment of fitting one,
-- not a second quest bolted onto the first.
--
-- 700x520, the Pet Hub's dimensions, and pushed through _G.applyHudScaling on open like every
-- other full panel in this realm, so it lands at exactly the size players already know.
do
	local g = Instance.new("ScreenGui")
	g.Name = "TractorPartFixHUD"; g.ResetOnSpawn = false; g.DisplayOrder = 14
	g.IgnoreGuiInset = true; g.Enabled = false; g.Parent = PlayerGui
	g:SetAttribute("NoTextSweep", true)      -- this panel sizes its own type; keep the sweep off it
	FH.partGui = g

	-- a dim behind it so the panel reads as modal. It is NOT a click target: X only, house rule.
	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1); dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45; dim.BorderSizePixel = 0; dim.Active = false; dim.Parent = g

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.new(0.5, 0, 0.5, -45)
	panel.Size = UDim2.fromOffset(700, 520); panel.BackgroundColor3 = FILL
	panel.BorderSizePixel = 0; panel.Active = true; panel.Parent = g
	-- Already the house size and spot by hand, so the resize is a no-op -- adopted anyway for the
	-- OTHER half of what housePanel does: holding the bottom HUD down while it is up, and doing it
	-- by watching the panel rather than trusting this file to remember on every exit path.
	pcall(_G.housePanel, panel)   -- island19 barn HUD
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	do local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 3; s.Parent = panel end

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 60); header.BackgroundColor3 = STROKE
	header.BorderSizePixel = 0; header.Parent = panel
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 18)
	do  -- square the header's bottom corners so it sits INTO the card
		local patch = Instance.new("Frame")
		patch.AnchorPoint = Vector2.new(0.5, 1); patch.Position = UDim2.new(0.5, 0, 1, 0)
		patch.Size = UDim2.new(1, 0, 0, 20); patch.BackgroundColor3 = STROKE
		patch.BorderSizePixel = 0; patch.Parent = header
	end

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1; title.Position = UDim2.fromOffset(18, 6)
	title.Size = UDim2.new(1, -80, 0, 34); title.Font = Enum.Font.FredokaOne
	title.TextSize = 26; title.TextColor3 = Color3.new(1, 1, 1)
	title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = "FITTING THE PART"; title.Parent = header
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1; sub.Position = UDim2.fromOffset(18, 38)
	sub.Size = UDim2.new(1, -80, 0, 18); sub.Font = Enum.Font.GothamBold
	sub.TextSize = 13; sub.TextColor3 = Color3.fromRGB(246, 232, 210)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = "Tighten the bolt that's lit up"; sub.Parent = header

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0.5); close.Position = UDim2.new(1, -14, 0.5, 0)
	close.Size = UDim2.fromOffset(40, 40); close.BackgroundColor3 = Color3.fromRGB(214, 84, 72)
	close.Text = "X"; close.Font = Enum.Font.FredokaOne; close.TextSize = 22
	close.TextColor3 = Color3.new(1, 1, 1); close.BorderSizePixel = 0
	close.AutoButtonColor = false; close.Parent = header
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 12)

	-- how many bolts are in
	local lab = Instance.new("TextLabel")
	lab.BackgroundTransparency = 1; lab.Position = UDim2.fromOffset(24, 72)
	lab.Size = UDim2.new(1, -48, 0, 18); lab.Font = Enum.Font.GothamBold
	lab.TextSize = 14; lab.TextColor3 = HINTC; lab.TextXAlignment = Enum.TextXAlignment.Left
	lab.Text = "BOLTS  0/4"; lab.Parent = panel
	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(24, 94); track.Size = UDim2.new(1, -48, 0, 22)
	track.BackgroundColor3 = Color3.fromRGB(238, 228, 210); track.BorderSizePixel = 0
	track.Parent = panel
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = GREEN_T
	fill.BorderSizePixel = 0; fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	-- the plate: the part in the middle, four bolts round it
	local plate = Instance.new("Frame")
	plate.AnchorPoint = Vector2.new(0.5, 0); plate.Position = UDim2.new(0.5, 0, 0, 134)
	plate.Size = UDim2.fromOffset(300, 300); plate.BackgroundColor3 = Color3.fromRGB(232, 222, 206)
	plate.BorderSizePixel = 0; plate.Parent = panel
	Instance.new("UICorner", plate).CornerRadius = UDim.new(1, 0)
	do local s = Instance.new("UIStroke"); s.Color = IRON; s.Thickness = 4; s.Parent = plate end

	local face = Instance.new("TextLabel")
	face.AnchorPoint = Vector2.new(0.5, 0.5); face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromOffset(150, 150); face.BackgroundTransparency = 1
	face.Font = Enum.Font.FredokaOne; face.TextSize = 96; face.TextColor3 = TEXTC
	face.Text = "\xF0\x9F\x94\xA7"; face.Parent = plate

	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 1); hint.Position = UDim2.new(0.5, 0, 1, -18)
	hint.Size = UDim2.new(1, -48, 0, 26); hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.FredokaOne; hint.TextSize = 20; hint.TextColor3 = HINTC
	hint.Text = ""; hint.Parent = panel

	-- ===== STATE FOR ONE OPEN =====
	local order, at, onDone, live = {}, 1, nil, false
	local bolts = {}

	local function paint()
		for i, b in ipairs(bolts) do
			local done = false
			for k = 1, at - 1 do if order[k] == i then done = true end end
			local isNext = live and order[at] == i
			b.BackgroundColor3 = done and GREEN_T or (isNext and GOLD or Color3.fromRGB(150, 146, 140))
			b.Text = done and "\xE2\x9C\x93" or "\xE2\x9A\xAB"
			b.TextColor3 = isNext and TEXTC or Color3.new(1, 1, 1)
		end
		lab.Text = ("BOLTS  %d/%d"):format(at - 1, #bolts)
		fill.Size = UDim2.new((at - 1) / #bolts, 0, 1, 0)
	end

	local function finish(ok)
		if not live then return end
		live = false
		g.Enabled = false
		-- THE CALLBACK RUNS BEFORE THE HUD HOLD IS DROPPED, and the order is deliberate: seating
		-- the fifth part opens the ignition panel from inside that callback, and releasing first
		-- would flash the bottom HUD back on for the frame between the two panels.
		local cb = onDone; onDone = nil
		if cb then cb(ok) end
		FH.setHud("PartFix", false)
	end
	FH.closePart = function() finish(false) end

	local function tap(i)
		if not live or at > #bolts then return end   -- the last bolt is in; the panel is closing
		if order[at] ~= i then
			-- the wrong bolt costs nothing but a wobble: this is the easy job, not the quest
			hint.Text = "Not that one -- the lit one!"
			hint.TextColor3 = Color3.fromRGB(196, 96, 84)
			local b = bolts[i]
			b.Rotation = -8
			tween(b, 0.2, { Rotation = 0 }, Enum.EasingStyle.Elastic)
			return
		end
		local b = bolts[i]
		b.Rotation = 0
		tween(b, 0.25, { Rotation = 360 }, Enum.EasingStyle.Quad)   -- it spins home
		task.delay(0.26, function() if b.Parent then b.Rotation = 0 end end)
		at += 1
		paint()
		if at > #bolts then
			hint.Text = E_SPARK .. "  THAT'S IT -- FITTED!"
			hint.TextColor3 = Color3.fromRGB(72, 150, 60)
			face.Text = "\xE2\x9C\x85"
			task.delay(0.55, function() finish(true) end)
		else
			hint.Text = ("Nice! %d to go."):format(#bolts - (at - 1))
			hint.TextColor3 = HINTC
		end
	end

	for i = 1, 4 do
		local b = Instance.new("TextButton")
		b.Name = "Bolt" .. i
		b.Size = UDim2.fromOffset(66, 66); b.BackgroundColor3 = Color3.fromRGB(150, 146, 140)
		b.Font = Enum.Font.FredokaOne; b.TextSize = 30; b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = "\xE2\x9A\xAB"; b.BorderSizePixel = 0; b.AutoButtonColor = false
		-- N, E, S, W round the plate
		if i == 1 then b.AnchorPoint = Vector2.new(0.5, 0); b.Position = UDim2.new(0.5, 0, 0, 16)
		elseif i == 2 then b.AnchorPoint = Vector2.new(1, 0.5); b.Position = UDim2.new(1, -16, 0.5, 0)
		elseif i == 3 then b.AnchorPoint = Vector2.new(0.5, 1); b.Position = UDim2.new(0.5, 0, 1, -16)
		else b.AnchorPoint = Vector2.new(0, 0.5); b.Position = UDim2.new(0, 16, 0.5, 0) end
		b.Parent = plate
		Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
		do local s = Instance.new("UIStroke"); s.Color = IRON_D; s.Thickness = 3; s.Parent = b end
		b.Activated:Connect(function() tap(i) end)
		bolts[i] = b
	end

	close.Activated:Connect(function() finish(false) end)

	-- rec is the carried part's record; done(true) means "it is fitted", done(false) means the
	-- player shut the panel and is still holding it.
	FH.openPart = function(rec, done)
		if live then return end
		live = true
		onDone = done
		at = 1
		order = { 1, 2, 3, 4 }
		for k = #order, 2, -1 do          -- shuffle: a fixed order would be tappable blind
			local j = math.random(k)
			order[k], order[j] = order[j], order[k]
		end
		title.Text = (rec.def.emoji .. "  FITTING THE " .. string.upper(rec.def.label))
		face.Text = rec.def.emoji
		hint.Text = "Tap the bolt that's lit up"
		hint.TextColor3 = HINTC
		paint()
		g.Enabled = true
		FH.setHud("PartFix", true)
		if _G.applyHudScaling then pcall(_G.applyHudScaling) end
	end
end

openFixHUD = function()
	FH.gui.Enabled = true
	FH.setHud("Ignition", true)
	updateFixHUD()
end
closeFixHUD = function()
	FH.gui.Enabled = false
	FH.setHud("Ignition", false)
end
updateFixHUD = function()
	if not FH.gui.Enabled then return end
	FH.label.Text = ("IGNITION  %d/%d"):format(math.min(ignitionTries, IGNITION_TRIES), IGNITION_TRIES)
	FH.fill.Size = UDim2.new(math.min(1, ignitionTries / IGNITION_TRIES), 0, 1, 0)
	FH.hint.Text = (ignitionTries == 0) and "She's been sitting a while. Give it a turn."
		or "Nearly... keep turning!"
end

-- ============================================================================
-- THE WHEAT FIELD
-- ============================================================================
-- ============================================================================
-- NOTHING GROWS THROUGH A BUILDING
-- ============================================================================
-- With no "WheatField" block the field is dropped 60 studs in front of the tractor, sight
-- unseen -- which is exactly how 400 stalks ended up sprouting through the farm house. Two
-- guards, and they matter for a hand-placed field too, because a rectangle drawn over a farm
-- will always clip a wall or a fence somewhere.
--
--   1. ANYTHING SOLID IN THE WAY. A box query per stalk, wider than the stalk itself so wheat
--      does not grow flush against a wall either. Quest props and scenery are excluded (the
--      tractor and barn are ours), everything of yours blocks.
--   2. BUILDINGS GET A WIDE BERTH. A house is mostly hollow, so an occupancy test alone would
--      happily plant a crop in the living room. Any model whose name reads as a building is
--      taken as a whole bounding box plus a margin, and nothing grows inside it.
-- (!) EVERYTHING BELOW LIVES INSIDE buildField, not at file scope. This chunk is within a
-- handful of Luau's 200-register ceiling, and a helper used by exactly one function has no
-- business costing a register for the life of the script -- nested, it costs none.
local function buildField()
	if not fieldCF then return end

	local BUILDING_WORDS = { house = true, farmhouse = true, barn = true, shed = true,
		silo = true, coop = true, stable = true }
	local BUILDING_MARGIN = 8

	local function buildingBoxes()
		local out = {}
		if not island then return out end
		for _, d in ipairs(island:GetDescendants()) do
			if d:IsA("Model") and not d:IsDescendantOf(questFolder) and not d:IsDescendantOf(sceneryFolder) then
				local n = norm(d.Name)
				local hit = false
				for word in pairs(BUILDING_WORDS) do
					if string.find(n, word, 1, true) then hit = true break end
				end
				if hit then
					local ok, cf, size = pcall(function() return d:GetBoundingBox() end)
					if ok and cf and size then
						out[#out + 1] = { cf = cf, half = size * 0.5 }
						print(("[Tractor] wheat will keep clear of '%s' (%.0f x %.0f studs)")
							:format(d:GetFullName(), size.X, size.Z))
					end
				end
			end
		end
		return out
	end

	local wheatParams = OverlapParams.new()
	wheatParams.FilterType = Enum.RaycastFilterType.Exclude

	-- a grid, not a scatter: a field is PLANTED, and rows are what make driving through it
	-- read as harvesting rather than as walking over grass.
	local SPACING = 4.5
	local nx = math.floor((fieldHalf.X * 2 - 4) / SPACING)
	local nz = math.floor((fieldHalf.Z * 2 - 4) / SPACING)
	nx = math.clamp(nx, 4, 30)
	nz = math.clamp(nz, 4, 30)

	-- ===== YOUR "WheatPlant" PARTS WIN OUTRIGHT =====
	-- Anything you named WheatPlant becomes the crop, and the procedural grid is not planted at
	-- all -- growing a second field through yours would double every row and make the count
	-- meaningless. Models count as one plant each, so a multi-part stalk falls as one thing.
	local mine = {}
	local seen = {}
	local function claim(inst, base)
		if seen[inst] then return end
		seen[inst] = true
		mine[#mine + 1] = { inst = inst, base = base }
	end
	if island then
		for _, d in ipairs(island:GetDescendants()) do
			if norm(d.Name) == CROP_NAME and not d:IsDescendantOf(questFolder)
				and not d:IsDescendantOf(sceneryFolder) then
				if d:IsA("Model") then
					local ok, cf = pcall(function() return d:GetPivot() end)
					if ok then claim(d, cf.Position) end
				elseif d:IsA("BasePart") and not (d.Parent and d.Parent:IsA("Model")
					and norm(d.Parent.Name) == CROP_NAME) then
					claim(d, d.Position - Vector3.new(0, d.Size.Y * 0.5, 0))
				end
			end
		end
	end

	if #mine > 0 then
		for _, m in ipairs(mine) do
			local inst, base = m.inst, m.base
			-- (!) UNQUERYABLE, BUT NOT MOVED OR DELETED. The tractor finds the ground with a
			-- downward raycast every frame; crops that answer that ray make it climb its own
			-- field like a staircase. CanQuery off fixes that and keeps them out of the prop
			-- placement queries too. Collision and position are left exactly as you built them.
			if inst:IsA("BasePart") then
				inst.CanQuery = false
			else
				for _, d in ipairs(inst:GetDescendants()) do
					if d:IsA("BasePart") then d.CanQuery = false end
				end
			end

			stalks[#stalks + 1] = {
				pos = base, cut = false,
				fell = function()
					-- CUT IS INSTANT. Driving over a plant clears it on the same frame the bar
					-- reaches it. The old topple-and-fade left every stalk lying there for five
					-- seconds, so a mown strip still read as standing wheat and players drove the
					-- same row twice looking for progress that had already been counted.
					--
					-- YOURS ARE HIDDEN, NEVER DESTROYED. Nothing you built is permanently removed
					-- from the place by a client script -- it is gone for this session only, and a
					-- rejoin restores the field exactly as you made it.
					if inst:IsA("BasePart") then
						inst.Transparency = 1
						inst.CanCollide = false
					else
						for _, d in ipairs(inst:GetDescendants()) do
							if d:IsA("BasePart") then
								d.Transparency = 1
								d.CanCollide = false
							end
						end
					end
				end,
			}
		end
		print(("[Tractor] harvesting YOUR crop: %d part(s)/model(s) named '%s' -- the generated "
			.. "field was NOT planted"):format(#stalks, CROP_NAME))
		-- THE WHOLE FIELD, NOT A QUOTA. The target is however many plants actually exist, so the
		-- job finishes when the field is bare and not a moment before. A partial quota left rows
		-- standing at "done", which reads as a bug in the counter rather than a finished job.
		WHEAT_TARGET = math.max(1, #stalks)
		print(("[Tractor] harvest target: ALL %d plant(s)"):format(WHEAT_TARGET))
		return
	end

	local boxes = buildingBoxes()
	local ex = { questFolder, sceneryFolder }
	if tractorModel then ex[#ex + 1] = tractorModel end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then ex[#ex + 1] = pl.Character end
	end
	wheatParams.FilterDescendantsInstances = ex
	wheatParams.MaxParts = 1

	local skipped = 0
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local lx = -fieldHalf.X + 2 + ix * SPACING
			local lz = -fieldHalf.Z + 2 + iz * SPACING
			local world = (fieldCF * CFrame.new(lx, 0, lz)).Position
			local gy = groundY(world)
			local at = Vector3.new(world.X, gy, world.Z)

			-- inside a building's footprint?
			local blocked = false
			for _, b in ipairs(boxes) do
				local o = b.cf:PointToObjectSpace(at)
				if math.abs(o.X) <= b.half.X + BUILDING_MARGIN
					and math.abs(o.Z) <= b.half.Z + BUILDING_MARGIN then
					blocked = true
					break
				end
			end
			-- ...or something solid standing on the spot? Lifted clear of the ground so the
			-- field itself is not what blocks it.
			if not blocked then
				local box = CFrame.new(at + Vector3.new(0, 3, 0))
				blocked = #Workspace:GetPartBoundsInBox(box, Vector3.new(4, 5, 4), wheatParams) > 0
			end

			if blocked then
				skipped += 1
			else
				local stalk = mk({ Name = "Wheat", Size = Vector3.new(0.35, 4.2, 0.35), Color = WHEAT_D,
					Parent = questFolder })
				stalk.CFrame = CFrame.new(at.X, gy + 2.1, at.Z)
					* CFrame.Angles(math.rad((ix % 3) - 1), (ix * 0.7 + iz * 1.3) % 6.28, math.rad((iz % 3) - 1))
				local head = mk({ Name = "Ear", Size = Vector3.new(0.75, 1.5, 0.75), Color = WHEAT,
					Parent = questFolder })
				head.CFrame = stalk.CFrame * CFrame.new(0, 2.4, 0)
				stalks[#stalks + 1] = { pos = at, cut = false, fell = function()
					-- this script grew these two parts, so it may destroy them -- and it does so on
					-- the spot. Same reason as the note on your own crop above: a cut row has to
					-- LOOK cut the instant the tractor is through it.
					stalk:Destroy()
					head:Destroy()
				end }
			end
		end
	end

	print(("[Tractor] wheat field planted: %d stalks (%d spot(s) skipped -- building or something "
		.. "already there)"):format(#stalks, skipped))
	-- THE WHOLE FIELD, NOT A QUOTA -- and it can never exceed what actually grew, which is what
	-- would make the quest unfinishable.
	if #stalks < WHEAT_TARGET then
		warn(("[Tractor] only %d stalks fit (wanted %d). Draw a 'WheatField' block over clear "
			.. "ground to choose where the crop goes."):format(#stalks, WHEAT_TARGET))
	end
	WHEAT_TARGET = math.max(1, #stalks)
	print(("[Tractor] harvest target: ALL %d stalk(s)"):format(WHEAT_TARGET))
end

-- ============================================================================
-- (THE GENERATED BARN LIVED HERE AND IS GONE)
-- ============================================================================
-- buildBarn() raised a whole red barn -- body, gable roof, cross-braced doors, hayloft -- whenever
-- it could not find one on the island. That is how island19 ended up with a script's farm building
-- standing next to the farm house you built, and it is deleted rather than merely unused: a dead
-- builder is one bad merge away from being called again, and it still costs a register on a file
-- with two to spare.
--
-- The delivery point is now whatever YOU named "Farm House" (or "Barn"), adopted exactly as it
-- stands. No building, no delivery point, and the log says so -- see the setup below.

-- ============================================================================
-- DRIVING
-- ============================================================================
-- AUTO-FORWARD, YOU STEER. The tractor always rolls; steering is the only input. One axis
-- behaves identically on a keyboard, a phone and a controller, and nobody can strand
-- themselves nose-first into a fence wondering which key reverses.
--
-- ⚠ NO PHYSICS, ANYWHERE. The tractor is an anchored model moved by PivotTo, and the driver's
-- HumanoidRootPart is ANCHORED to the seat and re-CFramed every frame. That is the whole trick:
-- a VehicleSeat would need unanchored parts, and this file's rule is that nothing it makes is
-- ever simulated. Dismounting un-anchors and sets the player down beside the machine.
local steer = 0             -- -1 .. 1
local driveHUD = {}
local wheelSpin = 0
local seatedHum, seatedHrp
local gas      = 0          -- 0..1, how far down the pedal is right now
local speed    = 0          -- studs/sec, what the tractor is ACTUALLY doing
local camConn               -- the RenderStepped connection that owns the camera while seated

local function setSteer(v) steer = v end

-- ============================================================================
-- THE DRIVER DISAPPEARS -- LOCALLY, and only for you
-- ============================================================================
-- (!) LocalTransparencyModifier, NOT Transparency. Transparency replicates: setting it would
-- hide the driver from EVERY player, so from the outside the tractor would trundle around the
-- field empty while its owner sat invisible in the seat. LocalTransparencyModifier is a purely
-- client-side render override -- you stop seeing yourself, everyone else still sees you driving.
--
-- (!) AND IT HAS TO BE RE-APPLIED EVERY FRAME. Roblox's own camera module writes
-- LocalTransparencyModifier continuously to fade your character in and out as the camera zooms,
-- so anything set once is silently overwritten within a frame or two. This is not a workaround;
-- it is how first-person hiding is done in the engine's own scripts.
--
-- CastShadow is a real property and does not reset, so it is remembered per-part and restored.
local shadowWas = {}      -- [BasePart] = its CastShadow before we turned it off

local function applyDriverHidden()
	local char = player.Character
	if not char then return end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			if shadowWas[d] == nil then
				shadowWas[d] = d.CastShadow
				d.CastShadow = false
			end
		end
	end
end

local function showDriver()
	local char = player.Character
	if char then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 end
		end
	end
	for part, was in pairs(shadowWas) do
		if part.Parent then part.CastShadow = was end
	end
	shadowWas = {}
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		hum.NameDisplayDistance = 100
		hum.HealthDisplayDistance = 100
	end
end

local function hideDriver()
	applyDriverHidden()
	local hum = humOf()
	if hum then
		-- the name tag has no part to hide -- it is drawn by the Humanoid itself
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.NameDisplayDistance = 0
		hum.HealthDisplayDistance = 0
	end
end

-- ============================================================================
-- THE CHASE CAMERA
-- ============================================================================
-- (!) YAW ONLY. The camera follows the tractor's heading but NOT its pitch or roll. The tractor
-- is re-seated onto the ground every frame, so it tips as it crosses bumps and ridges -- and a
-- camera that copied that would roll the horizon with it and make the whole screen seasick.
-- Taking just the Y rotation keeps the world level however the machine is sitting.
local function camGoal()
	local cf = driveFrame()                      -- the NOSE's frame, not the root's
	local _, yaw = cf:ToEulerAnglesYXZ()
	-- the free-look angles ORBIT THE EYE around the tractor rather than turning the tractor:
	-- the machine keeps driving where its nose points while you look wherever you like.
	local flat = CFrame.new(tractorRoot.Position)
		* CFrame.Angles(0, yaw + look.yaw, 0)
		* CFrame.Angles(look.pitch, 0, 0)
	local eye = (flat * CAM_OFFSET).Position
	local aim = tractorRoot.Position + Vector3.new(0, CAM_LOOK_HEIGHT, 0)
	return CFrame.lookAt(eye, aim)
end

local function startCamera()
	local cam = Workspace.CurrentCamera
	if not (cam and tractorRoot) then return end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = camGoal()          -- snap on mount, then trail: swinging in from wherever you
	                                -- were looking hides the first second of the drive
	if camConn then camConn:Disconnect() end
	camConn = RunService.RenderStepped:Connect(function(dt)
		if not (tractorRoot and tractorRoot.Parent and Workspace.CurrentCamera) then return end
		-- let go of the right button and the view eases back to over the bonnet. Easing rather
		-- than snapping, and only while NOT held, so a slow deliberate look is never fought.
		if not look.on then
			local k = math.min(1, look.recentre * dt)
			look.yaw = look.yaw + (0 - look.yaw) * k
			look.pitch = look.pitch + (0 - look.pitch) * k
		end
		-- lerped, so it trails the machine slightly instead of being welded to it
		Workspace.CurrentCamera.CFrame =
			Workspace.CurrentCamera.CFrame:Lerp(camGoal(), CAM_ALPHA)
		applyDriverHidden()         -- re-asserted here: see the note above
	end)
end

local function stopCamera()
	if camConn then camConn:Disconnect(); camConn = nil end
	-- free look never survives the ride: the angles reset and the cursor is handed back
	look.yaw, look.pitch, look.on = 0, 0, false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local cam = Workspace.CurrentCamera
	if not cam then return end
	cam.CameraType = Enum.CameraType.Custom
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if hum then cam.CameraSubject = hum end
end

local function makeDriveHUD()
	local g = Instance.new("ScreenGui")
	g.Name = "TractorDriveHUD"; g.ResetOnSpawn = false; g.DisplayOrder = 12
	g.IgnoreGuiInset = true
	g.Enabled = false; g.Parent = PlayerGui
	driveHUD.gui = g

	-- ========================================================================
	-- THE GAME'S OWN BOTTOM HUD GETS OUT OF THE WAY WHILE YOU DRIVE
	-- ========================================================================
	-- The fart meter and its "TAP TO FART!" button sit exactly where the pedals go, and neither
	-- does anything useful from a tractor seat. Same shape every menu in this realm uses (see
	-- Campfire / CrateClient / MainMenuManager.setHud): remember what was Enabled, switch it off,
	-- and put it back EXACTLY as it was. Never blanket-enable on the way out -- hopping off would
	-- then light up a HUD that something else had deliberately hidden.
	local hudPrev
	function driveHUD.setHud(hidden)
		if hidden then
			if hudPrev then return end          -- already down: do NOT re-capture the hidden state
			hudPrev = {}
			for _, name in ipairs({ "BottomStackGui", "GasMeterGui", "FartButtonGui", "StomachGui" }) do
				local sg = PlayerGui:FindFirstChild(name)
				if sg and sg:IsA("ScreenGui") then hudPrev[name] = sg.Enabled; sg.Enabled = false end
			end
		elseif hudPrev then
			for name, was in pairs(hudPrev) do
				local sg = PlayerGui:FindFirstChild(name)
				if sg and sg:IsA("ScreenGui") then sg.Enabled = was end
			end
			hudPrev = nil
		end
	end

	-- ===== ONE PAINT PASS FOR EVERY CONTROL =====
	-- Corner radius, border weight and type treatment live here instead of on each button. The
	-- old set was five controls with five slightly different treatments (radius 14 / 16 / 18, no
	-- border on the pads, a border on the pill), which read as five unrelated widgets.
	local function skin(o, colour, radius, textSize)
		o.BackgroundColor3 = colour
		o.BorderSizePixel = 0
		-- the pill is a plain Frame: Font / TextColor3 / TextSize do not exist on one, and writing
		-- them would throw rather than being ignored
		if o:IsA("TextButton") then
			o.AutoButtonColor = false
			o.Font = Enum.Font.FredokaOne
			o.TextColor3 = Color3.new(1, 1, 1)
			if textSize then o.TextSize = textSize end
		end
		Instance.new("UICorner", o).CornerRadius = UDim.new(0, radius)
		local s = Instance.new("UIStroke")
		s.Color = STROKE; s.Thickness = 3
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border   -- border ONLY: the default would also
		s.Parent = o                                      -- outline the glyph on a TextButton
		return o
	end

	-- ===== NO STATUS PILL HERE, ON PURPOSE =====
	-- There used to be a pill at the top of this HUD reading "She's still in pieces -- 2/5 parts
	-- fitted", with a speedometer bar under it. It was the SECOND thing on screen saying the same
	-- sentence: the quest's own objective frame already carries that progress, and
	-- ObjectiveBannerBridge mirrors it onto the realm's hero banner. Two copies of one message,
	-- one of them a slab of chrome floating over the middle of the screen while you drive.
	--
	-- The pill, its label and the bar are all gone -- not hidden, not emptied, not built at all --
	-- and so is every write to them (see updateDriveHUD and the drive loop). The banner path is
	-- untouched: same text, same timing, same priority. If you want a speed readout back, it
	-- belongs on the pedals, not in a second banner.

	-- ===== HOP OFF, WELL AWAY FROM THE PEDALS =====
	-- It used to sit directly under the BACK pedal, one thumb-width from the throttle, so the
	-- commonest misfire on a phone was ejecting yourself in the middle of a row. Up in the corner
	-- it is nowhere near anything you hold down.
	local off = Instance.new("TextButton")
	off.Name = "HopOff"
	off.AnchorPoint = Vector2.new(1, 0); off.Position = UDim2.new(1, -18, 0, 78)
	off.Size = UDim2.new(0, 132, 0, 46); off.Text = "HOP OFF"; off.Parent = g
	skin(off, STROKE, 14, 20)
	driveHUD.off = off

	-- ========================================================================
	-- THE CONTROL CLUSTER
	-- ========================================================================
	-- All four driving controls in ONE frame, so they move, scale and stay grouped as a unit.
	-- They used to be four absolute offsets measured from the screen edges (x = +/-230, y = -30 /
	-- -96 / -166): on a narrow phone the steering pads walked off the sides while the pedals sat
	-- alone in the middle of the view.
	local pad = Instance.new("Frame")
	pad.Name = "Controls"
	pad.AnchorPoint = Vector2.new(0.5, 1); pad.Position = UDim2.new(0.5, 0, 1, -24)
	pad.Size = UDim2.fromOffset(640, 172); pad.BackgroundTransparency = 1; pad.Parent = g

	-- one UIScale, re-measured on resize/rotate, so the cluster shrinks to fit rather than clips
	local scale = Instance.new("UIScale"); scale.Parent = pad
	local function fit()
		local cam = Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize
		if not (vp and vp.X > 1) then return end
		scale.Scale = math.clamp(math.min(vp.X / 780, vp.Y / 620), 0.55, 1)
	end
	fit()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end

	-- Every pointer path is wired on all four: MouseButton1Down/Up covers mouse and touch, and
	-- MouseLeave covers the case that actually bites -- dragging a finger off a button while
	-- still holding it fires no Up event at all, and would otherwise leave the tractor pinned at
	-- full throttle, or locked in a turn, with nothing pressed.
	local function steerPad(name, text, side)
		local b = Instance.new("TextButton")
		b.Name = name
		b.AnchorPoint = Vector2.new(side, 1); b.Position = UDim2.new(side, 0, 1, 0)
		b.Size = UDim2.fromOffset(148, 148); b.Text = text; b.Parent = pad
		skin(b, GREEN_D, 26, 54)
		local dir = (side == 0) and -1 or 1
		local function hold(down)
			-- held, not tapped: steering is a thing you lean on, so press/release drive it
			-- directly. Releasing one pad must not cancel a turn the OTHER one is asking for.
			if down then setSteer(dir) elseif steer == dir then setSteer(0) end
			b.BackgroundColor3 = down and GREEN_T or GREEN_D
		end
		b.MouseButton1Down:Connect(function() hold(true) end)
		b.MouseButton1Up:Connect(function() hold(false) end)
		b.MouseLeave:Connect(function() hold(false) end)
		return b
	end
	steerPad("Left", "<", 0)
	steerPad("Right", ">", 1)

	-- FORWARD and BACK, both HELD rather than toggled -- a throttle is something you keep your
	-- foot on, and holding is what makes pulling away and rolling to a stop legible. Centred
	-- between the two steering pads, which is where a thumb already is on a phone.
	local function pedal(name, text, y, height, value, colour)
		local b = Instance.new("TextButton")
		b.Name = name
		b.AnchorPoint = Vector2.new(0.5, 1); b.Position = UDim2.new(0.5, 0, 1, y)
		b.Size = UDim2.fromOffset(250, height); b.Text = text; b.Parent = pad
		skin(b, colour, 20, height >= 80 and 30 or 24)
		local function press(down)
			if down and not engineRunning then
				flashBanner(E_WRENCH .. " She needs all five parts first!", 2)
				return
			end
			-- releasing THIS pedal must not cancel the other one: only zero the throttle if what
			-- is being let go is the direction currently being asked for.
			if down then
				gas = value
			elseif (gas > 0) == (value > 0) then
				gas = 0
			end
			-- ...and the RESTING colour is whatever the machine's current state says it is.
			-- Restoring the plain green unconditionally used to repaint a "NEEDS FIXING" pedal as
			-- a working one the first time a finger slid off it.
			b.BackgroundColor3 = (down and Color3.fromRGB(120, 190, 90))
				or (engineRunning and colour or Color3.fromRGB(170, 164, 156))
		end
		b.MouseButton1Down:Connect(function() press(true) end)
		b.MouseButton1Up:Connect(function() press(false) end)
		b.MouseLeave:Connect(function() press(false) end)
		return b
	end
	driveHUD.drive = pedal("Forward", "FORWARD", 0, 92, 1, GREEN_T)
	driveHUD.back  = pedal("Back", "BACK", -100, 56, -0.55, Color3.fromRGB(150, 106, 46))
end
makeDriveHUD()
print("[Tractor] drive HUD built WITHOUT the status pill -- the \"still in pieces N/5\" progress "
	.. "line now has exactly one home: this quest's objective frame, which ObjectiveBannerBridge "
	.. "mirrors onto the realm banner. No pill GUI, no progress bar, and no writes to either.")

local stopDriving   -- forward
driveHUD.off.Activated:Connect(function() if stopDriving then stopDriving() end end)

UserInputService.InputChanged:Connect(function(input, gp)
	if gp or not (look.on and driving) then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	look.yaw = look.yaw - input.Delta.X * look.sens
	look.pitch = math.clamp(look.pitch - input.Delta.Y * look.sens, look.minPitch, look.maxPitch)
end)

-- ===== RIGHT MOUSE = LOOK AROUND =====
-- Held, like every other control here. The cursor is pinned while you hold it so the view can
-- keep turning past the edge of the window, and it is ALWAYS released again -- on button up and
-- on dismount -- because a locked mouse that outlives the thing that locked it is a soft lock.
UserInputService.InputBegan:Connect(function(input, gp)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and driving and not gp then
		look.on = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		return
	end
	if gp or not driving then return end
	local k = input.KeyCode
	-- SPACE GETS YOU OUT. Jump is the reflex for "let me off this thing", and while seated the
	-- Humanoid is PlatformStand so the key does nothing at all otherwise. Routed through the same
	-- stopDriving the HOP OFF button calls, so there is exactly one dismount path to get wrong.
	if k == Enum.KeyCode.Space then
		if stopDriving then stopDriving() end
		return
	end
	if k == Enum.KeyCode.A or k == Enum.KeyCode.Left then setSteer(-1)
	elseif k == Enum.KeyCode.D or k == Enum.KeyCode.Right then setSteer(1)
	elseif k == Enum.KeyCode.W or k == Enum.KeyCode.Up then
		if engineRunning then gas = 1 else flashBanner(E_WRENCH .. " She needs all five parts first!", 2) end
	elseif k == Enum.KeyCode.S or k == Enum.KeyCode.Down then
		gas = -0.55                     -- reverse, deliberately slower than forward
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		look.on = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		return
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.A or k == Enum.KeyCode.Left then
		if steer < 0 then setSteer(0) end
	elseif k == Enum.KeyCode.D or k == Enum.KeyCode.Right then
		if steer > 0 then setSteer(0) end
	elseif k == Enum.KeyCode.W or k == Enum.KeyCode.Up or k == Enum.KeyCode.S or k == Enum.KeyCode.Down then
		gas = 0
	end
end)

local function updateDriveHUD()
	-- THE BUTTONS ARE THE WHOLE HUD NOW. This used to also write a status line into a pill at the
	-- top of the screen -- "She's still in pieces -- 2/5 parts fitted", "HARVEST 12/40" -- which
	-- was the same progress the objective frame already shows and the hero banner already mirrors.
	-- The pill is gone (see makeDriveHUD); those sentences still reach the player, by the one route
	-- that was always going to be the survivor.
	--
	-- The DRIVE button still reflects what the machine can actually do right now, so the answer to
	-- "why won't it move" is on the button itself rather than in a log line.
	local canRun = engineRunning
	if driveHUD.drive then
		driveHUD.drive.BackgroundColor3 = canRun and GREEN_T or Color3.fromRGB(170, 164, 156)
		driveHUD.drive.Text = canRun and "FORWARD" or "NEEDS FIXING"
	end
	if driveHUD.back then
		driveHUD.back.BackgroundColor3 = canRun and Color3.fromRGB(150, 106, 46)
			or Color3.fromRGB(170, 164, 156)
		driveHUD.back.Visible = canRun
	end
end

-- the cut wheat piling up in the trailer
local loadParts = {}
local function addToLoad()
	if #loadParts >= 14 then return end
	local i = #loadParts + 1
	local sheaf = mk({ Name = "Load" .. i, Size = Vector3.new(1.5, 1.1, 1.5), Color = WHEAT,
		Parent = sceneryFolder })
	local off = CFrame.new(((i % 3) - 1) * 1.5, 1.0 + math.floor((i - 1) / 3) * 0.9, 7.4 + ((i % 2) - 0.5) * 1.4)
		* CFrame.Angles(0, i * 0.6, 0)
	tractorParts[#tractorParts + 1] = { part = sheaf, off = off }
	loadParts[#loadParts + 1] = sheaf
end

local function cutNear(pos)
	for _, s in ipairs(stalks) do
		if not s.cut and (Vector3.new(s.pos.X, 0, s.pos.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= CUT_RADIUS then
			s.cut = true
			harvested += 1
			-- ===== THE CUTTER =====
			-- Built on the first stalk rather than at boot, so an island that never gets driven
			-- never loads the asset. It loops from then on and the drive loop rides its volume:
			-- all this has to record is that the bar bit something THIS instant.
			if not HAY.cutSound and tractorRoot and SOUND_CUT ~= "" then
				local snd = Instance.new("Sound")
				snd.Name = "WheatCutter"
				snd.SoundId = SOUND_CUT
				snd.Looped = true
				snd.Volume = 0                        -- faded up by the drive loop, never snapped
				-- (!) MIN DISTANCE 60, AND THAT NUMBER IS THE WHOLE POINT. Positional audio in
				-- Roblox is measured from the CAMERA, not from your character -- the same trap
				-- documented at length in setCabSound, which is why the cab idle ended up 2D. The
				-- chase camera sits 22 up and 26 back, about 34 studs from the machine, so at the
				-- 14 this started with the rolloff had already eaten most of the level before the
				-- driver heard it: setting Volume to "20% above the idle" would have been a number
				-- that meant nothing. A 60-stud floor puts the camera comfortably inside the
				-- no-attenuation zone, so the driver hears it at exactly the volume set, and it
				-- still fades out properly for anyone else on the island.
				snd.RollOffMinDistance = 60
				snd.RollOffMaxDistance = 240
				snd.RollOffMode = Enum.RollOffMode.InverseTapered
				snd.Parent = tractorRoot
				pcall(function() snd:Play() end)
				HAY.cutSound = snd
			end
			HAY.lastCut = os.clock()
			-- HOW A PLANT FALLS IS DECIDED WHERE IT IS CREATED, not here. A grown stalk is two
			-- parts this script made and may freely destroy; one of YOUR WheatPlant parts might
			-- be a mesh, a model, or something you want left standing in the world. Each crop
			-- carries its own fell() so this loop never has to know which it is dealing with.
			if s.fell then s.fell() end
			if harvested % 3 == 0 then addToLoad() end
			if harvested % 4 == 0 then poofAt(s.pos + Vector3.new(0, 2, 0), WHEAT, 5) end
			-- (!) CUTTING WHEAT WITH A WORKING TRACTOR *IS* THE HARVEST STEP. Without this the
			-- counter climbed but the quest never moved: the completion test below required
			-- step == 4, and step only reached 4 by turning the key on an ACCEPTED quest. Anyone
			-- who used /fix, or simply found the tractor before the NPC, could mow the entire
			-- field forever with no banner, no progress and no way to finish. Driving a repaired
			-- tractor through a crop is unambiguous enough to count as starting the job.
			if step < 4 and engineRunning then
				step = 4
				refreshBanner(); refreshPrompts()
			end
			updateDriveHUD()
			refreshBanner()
			if harvested >= WHEAT_TARGET and step == 4 then
				step = 5
				refreshBanner(); refreshPrompts(); updateDriveHUD()
				flashBanner(E_WHEAT .. " That's the field cut! Take the straw to the FACTORY!", 3.5)
				-- the realm already owns a guide trail; a full trailer and no idea which way the
				-- first stop is was the one moment this quest sent you looking rather than driving.
				-- It points at the FACTORY now, because loose straw is not a delivery -- the farm
				-- house leg gets its own trail once the bales are aboard (see _G.tractorBaleMade).
				local aim = (_G.hayFactory and _G.hayFactory.point) or barnPoint
				if _G.guideTrailTo and aim then
					pcall(_G.guideTrailTo, aim)
				end
				if _G.NotifyCenter and _G.NotifyCenter.push then
					pcall(function() _G.NotifyCenter.push({
						text = E_WHEAT .. " Straw cut -- bale it at the factory!", color = WHEAT }) end)
				end
			end
		end
	end
end

-- BOARDING IS NOT GATED ON THE REPAIR. You can climb into a broken tractor and sit in it --
-- that is what a broken tractor is for -- and the DRIVE button is what refuses to move until
-- all five parts are in. Gating the seat itself would mean the machine cannot be examined,
-- tried, or tested until the quest says so.
startDriving = function()
	if driving then return end
	local hrp, hum = hrpOf(), humOf()
	if not (hrp and hum and tractorRoot) then return end
	driving = true
	gas, speed = 0, 0
	-- THE TRACTOR IS YOURS ALONE -- it moves on your screen and nobody else's -- so without this
	-- your friends watch you glide across the field sitting on thin air. CarryView draws a
	-- tractor under any player who says "tractor", and its offset is the exact inverse of the
	-- seat pose below. Move the seat, move that.
	pcall(_G.CarrySay, "tractor")
	seatedHrp, seatedHum = hrp, hum
	hum.PlatformStand = true        -- stops the walk animation fighting the seat pose
	hrp.Anchored = true
	hideDriver()
	startCamera()
	print("[Tractor] boarded -- starting cab sound")
	setCabSound(true)
	driveHUD.gui.Enabled = true
	driveHUD.setHud(true)           -- the fart meter / gut bar sit exactly where the pedals go
	updateDriveHUD()
	steer = 0
	refreshPrompts()
	flashBanner(engineRunning
		and (E_TRACTOR .. " Hold FORWARD (or W) and steer with A / D!")
		or  (E_WRENCH .. " You're in -- but she needs all five parts before she'll run."), 3.5)
end

stopDriving = function()
	if not driving then return end
	driving = false
	gas, speed = 0, 0
	sayTopCarry()                   -- off the tractor: back to whatever is in your hands, if anything
	driveHUD.gui.Enabled = false
	driveHUD.setHud(false)          -- ...and it comes straight back, exactly as it was
	-- camera and character come back FIRST and unconditionally. A dismount that errors halfway
	-- leaves an invisible player staring through a scriptable camera at nothing, which is not a
	-- state anyone can get out of without rejoining.
	stopCamera()
	showDriver()
	setCabSound(false)
	if seatedHum then seatedHum.PlatformStand = false end
	if seatedHrp then
		-- ================================================================================
		-- GETTING OFF MUST NOT LAUNCH YOU. THE ORDER OF THESE FOUR LINES IS THE WHOLE FIX.
		-- ================================================================================
		-- It used to unanchor FIRST and place the character SECOND. In that one-line gap the
		-- solver takes the assembly back, measures how far it moved on the last frame the
		-- tractor dragged it, divides by the frame time and calls that its velocity. While
		-- driving, the root is teleported every frame, so a single hitched frame reads as a
		-- colossal speed -- the log recorded a hop-off at vy=5744 that carried the player from
		-- y=117 to y=28031, straight through eight islands' worth of sky.
		--
		-- So: place it while it is STILL ANCHORED (an anchored part cannot accumulate momentum),
		-- kill both velocities, and only then hand it back to physics.
		local side = driveFrame() * CFrame.new(-6, -1, 0)   -- out of the LEFT side, not the back
		-- set down BESIDE the machine, not inside it: dropped on the seat you would be standing
		-- in the bodywork, and the first thing the character does is get pushed out sideways.
		seatedHrp.CFrame = CFrame.new(side.Position.X, groundY(side.Position) + 3.5, side.Position.Z)
		seatedHrp.AssemblyLinearVelocity = Vector3.zero
		seatedHrp.AssemblyAngularVelocity = Vector3.zero
		seatedHrp.Anchored = false

		-- ...and again on the next few frames. Unanchoring is not the end of it: the solver can
		-- re-derive a velocity on the step right after, and PlatformStand coming off adds its own
		-- nudge. Three frames of holding it at zero costs nothing and covers every one of those.
		local hrpRef, humRef = seatedHrp, seatedHum
		task.spawn(function()
			for _ = 1, 3 do
				RunService.RenderStepped:Wait()
				if not (hrpRef and hrpRef.Parent) then return end
				hrpRef.AssemblyLinearVelocity = Vector3.zero
				hrpRef.AssemblyAngularVelocity = Vector3.zero
			end
			-- land cleanly rather than falling out of a seated pose
			if humRef and humRef.Parent then
				pcall(function() humRef:ChangeState(Enum.HumanoidStateType.Landed) end)
			end
		end)
	end
	seatedHrp, seatedHum = nil, nil
	refreshPrompts()
end

RunService.RenderStepped:Connect(function(dt)
	if not (tractorRoot and tractorRoot.Parent) then return end
	if driving and engineRunning then
		-- ===== THE GAS =====
		-- Speed chases the throttle instead of snapping to it: a tractor that reaches full pace
		-- in one frame and stops dead in the next feels like a slide, not a machine. Pulling away
		-- is slower than slowing down, which is what makes it read as heavy.
		local want = gas * DRIVE_SPEED
		local rate = (math.abs(want) > math.abs(speed)) and 9 or 16      -- accelerate / coast
		speed += (want - speed) * math.min(1, rate * dt)
		if math.abs(speed) < 0.05 then speed = 0 end

		-- STEERING NEEDS ROLLING. Yaw is scaled by how fast you are actually going, so a parked
		-- tractor cannot pirouette on the spot -- you have to be moving to turn, like a vehicle.
		local grip = math.clamp(math.abs(speed) / DRIVE_SPEED, 0, 1)
		local yaw = -steer * TURN_RATE * grip * dt * (speed < 0 and -1 or 1)
		-- turn the root, then take the NOSE's direction from the turned frame
		tractorRoot.CFrame = tractorRoot.CFrame * CFrame.Angles(0, yaw, 0)
		local fwd = driveFrame().LookVector
		local ahead = tractorRoot.Position + fwd * speed * dt
		-- pinned to the island, and always sitting on whatever ground is under it
		local flat = clampToIsland(ahead, 10)
		local gy = groundY(flat)
		local at = Vector3.new(flat.X, gy + tractorSeatH, flat.Z)
		-- (!) lookAt points -Z at `fwd`, so the yaw offset is UNDONE to leave the model itself
		-- sitting the way it was built. Skip this and the tractor snaps a quarter turn on the
		-- first frame it moves.
		tractorRoot.CFrame = CFrame.lookAt(at, at + fwd) * CFrame.Angles(0, -TRACTOR_YAW, 0)
		tractorCF = tractorRoot.CFrame

		-- ROLLED, NOT SPUN. wheelSpin is the distance the tractor has actually travelled, in
		-- studs; each wheel converts that to an angle with its own radius below. A fixed
		-- radians-per-second would make every wheel turn at the same rate regardless of size and
		-- keep turning at the same rate however fast you were going, which is the thing that
		-- reads as fake.
		wheelSpin += speed * dt
		-- (the speedometer bar that used to be driven from here went with the status pill)
		-- the cutting bar only bites while she is actually moving
		if math.abs(speed) > 0.5 then
			cutNear(tractorRoot.Position + driveFrame().LookVector * 4)
		end

	end
	-- the driver rides the seat WHENEVER seated, moving or not -- otherwise a parked driver
	-- slowly drifts out of the cab as the tractor settles onto the ground under it.
	if driving and seatedHrp and seatedHrp.Parent then
		seatedHrp.CFrame = driveFrame() * CFrame.new(0, 1.9, 1.4)
	end

	-- ===== THE CUTTING NOISE RIDES THE CROP, NOT THE THROTTLE =====
	-- It is up while the bar is actually taking stalks and down within a fraction of a second of
	-- the last one -- so driving out of the crop, or stopping in it, goes quiet, and driving back
	-- in picks straight back up. Faded rather than switched: a looped sound snapping to full
	-- volume clicks, and you cross the edge of a field a dozen times in one harvest.
	if HAY.cutSound then
		-- 0.96 = the cab idle's 0.8 plus 20%, which is the level asked for. See the rolloff note
		-- where this Sound is built: the number only means anything because the driver sits
		-- inside the no-attenuation zone.
		local want = (os.clock() - (HAY.lastCut or 0) < 0.3) and 0.96 or 0
		HAY.cutSound.Volume += (want - HAY.cutSound.Volume) * math.min(1, dt * 9)
	end

	-- ===== THE EXHAUST BREATHES WITH THE THROTTLE =====
	-- Running at all = a steady idle puff; the harder she is pulling, the thicker it gets. Driven
	-- off actual SPEED rather than off the pedal, so coasting to a stop thins out as she slows
	-- instead of cutting the instant a finger comes off the button. Engine off = nothing at all,
	-- which is the whole difference between this and the dead-engine smoulder.
	if engineRunning then
		if not brokenFx.exhaust then brokenFx.makeExhaust() end
		if brokenFx.exhaust then
			local pull = math.clamp(math.abs(speed) / DRIVE_SPEED, 0, 1)
			brokenFx.exhaust.Rate = 7 + pull * 26
		end
	elseif brokenFx.exhaust then
		brokenFx.exhaust.Rate = 0
	end
	poseTractor()
	-- THE WHEELS. Angle = distance rolled / radius, so size decides speed by itself. The front
	-- pair also yaw with the steering input, and the yaw is applied BEFORE the roll so a turned
	-- wheel still spins about its own axle rather than about the tractor's.
	for _, w in ipairs(wheelParts) do
		if w.part.Parent then
			local roll = wheelSpin / (w.radius or 1)
			local cf = tractorRoot.CFrame * w.off
			if w.steers then
				-- steer about the wheel's own upright centre, then roll: doing it the other way
				-- round swings a spinning wheel around the tractor instead of turning it.
				cf = tractorRoot.CFrame * CFrame.new(w.off.Position)
					* CFrame.Angles(0, -steer * MAX_STEER_ANGLE, 0)
					* (w.off - w.off.Position)
			end
			local spin
			if w.axis == "y" then spin = CFrame.Angles(0, roll, 0)
			elseif w.axis == "z" then spin = CFrame.Angles(0, 0, roll)
			else spin = CFrame.Angles(roll, 0, 0) end
			w.part.CFrame = cf * spin
		end
	end
end)

-- ============================================================================
-- THE PAYOUT
-- ============================================================================
local function payCoins(n)
	local ce = ReplicatedStorage:FindFirstChild("CoinEvent") or _G.CoinEvent
	if not ce then warn("[Tractor] CoinEvent missing -- reward not paid") return end
	local ok = pcall(function() ce:FireServer(n) end)
	if not ok then warn("[Tractor] CoinEvent:FireServer failed -- reward not paid") end
end

local function firework(from, colour)
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2
		local spark = mk({ Size = Vector3.new(0.7, 0.7, 0.7), Shape = Enum.PartType.Ball,
			Color = colour, Material = Enum.Material.Neon, Parent = questFolder })
		spark.CFrame = CFrame.new(from)
		tween(spark, 1.1, { CFrame = CFrame.new(from + Vector3.new(math.cos(a) * 24, 15 + math.sin(a) * 11, math.sin(a) * 24)),
			Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 })
		Debris:AddItem(spark, 1.2)
	end
end

-- ============================================================================
-- LEG ONE: THE STRAW GOES TO THE FACTORY
-- ============================================================================
-- Loose straw is not a delivery, it is a job half done -- and there is a hay bale factory on this
-- island whose entire purpose is turning straw into bales. So the trailer goes there first, the
-- straw goes in, you work the baler's own console, and the bales come back out onto the trailer.
-- Only then is there something worth driving to the farm house.
--
-- The factory is a SEPARATE SCRIPT (HayBaleFactory.client.lua) and neither file may reach into
-- the other's internals: it publishes _G.hayFactory (a point and a take()), this publishes
-- _G.tractorBaleMade, and that pair of globals is the entire contract between them.
HAY.deliver = function()
	if step ~= 5 or HAY.kind ~= "straw" or loadTipped then return end
	local n = #loadParts
	if n == 0 then
		flashBanner(E_WHEAT .. " Nothing in the trailer to tip!", 2)
		return
	end
	local fac = _G.hayFactory
	if not (fac and fac.point) then
		flashBanner(E_WRENCH .. " The factory isn't running -- try again in a moment.", 3)
		return
	end
	stopDriving()

	-- the sheaves tumble off the trailer onto the intake
	for i, sheaf in ipairs(loadParts) do
		if sheaf.Parent then
			local goal = fac.point + Vector3.new(((i % 3) - 1) * 2.2, 3 + (i % 2) * 1.4, ((i % 2) - 0.5) * 2.2)
			tween(sheaf, 0.5 + i * 0.05, { CFrame = CFrame.new(goal) * CFrame.Angles(0, i * 0.7, 0) },
				Enum.EasingStyle.Quad)
			tween(sheaf, 1.6, { Transparency = 1 }, Enum.EasingStyle.Linear)
			Debris:AddItem(sheaf, 1.8)
		end
	end
	-- they stop being glued to the tractor the moment they leave it
	for i = #tractorParts, 1, -1 do
		for _, sheaf in ipairs(loadParts) do
			if tractorParts[i].part == sheaf then table.remove(tractorParts, i) break end
		end
	end
	table.clear(loadParts)

	-- ===== FIVE BALES IS THE JOB =====
	-- One per three sheaves, never none, and NEVER MORE THAN FIVE. A full trailer is thirteen or
	-- fourteen sheaves, so a proper harvest comes out at exactly five presses -- long enough to be
	-- a task at the console, short enough that nobody is standing there pressing a button eight
	-- times. Bring less and you owe less; bring more and it is still five.
	HAY.owed = math.clamp(math.ceil(n / 3), 1, 5)
	HAY.kind = "pressing"
	poofAt(fac.point + Vector3.new(0, 3, 0), WHEAT, 16)
	pcall(fac.take, n, HAY.owed)
	flashBanner(("%s Straw's in! Work the baler -- %d bale(s) to press."):format(E_WHEAT, HAY.owed), 4)
	refreshBanner(); refreshPrompts()
	print(("[Tractor] %d sheaf/sheaves delivered to the factory, %d bale(s) owed"):format(n, HAY.owed))
end

-- ...and the factory's side of the contract: one call per bale that comes off the press. The five
-- do NOT go on the trailer -- they stack up outside the factory door, and you SHOULDER the stack
-- and walk it to the farm house. Driving a tractor thirty studs to a building you are standing
-- next to was the least interesting version of this, and it meant hopping back in the cab for the
-- last leg of a job you had just finished doing on foot at a console.
_G.tractorBaleMade = function()
	if HAY.kind ~= "pressing" or HAY.owed <= 0 then return end
	HAY.owed -= 1
	HAY.pressed = (HAY.pressed or 0) + 1
	if HAY.owed > 0 then
		flashBanner(("%s Bale pressed! %d to go."):format(E_WHEAT, HAY.owed), 2)
		refreshBanner(); refreshPrompts()
		return
	end

	-- ===== THE LAST ONE: BUILD THE STACK =====
	HAY.kind = "bales"
	local fac = _G.hayFactory
	local at = (fac and fac.point) or (tractorCF and tractorCF.Position) or Vector3.zero
	local gy = groundY(at)
	local stack = Instance.new("Model")
	stack.Name = "BaleStack"
	stack:SetAttribute("QuestProp", true)
	-- three down, two up: the way bales are actually stacked, and it reads as "five" at a glance
	-- without anybody counting
	local BALE = Vector3.new(3.4, 2.2, 2.2)
	local main
	for i = 1, 5 do
		local row, col = (i <= 3) and 0 or 1, (i <= 3) and (i - 2) or (i - 4.5)
		local b = mk({ Name = "Bale" .. i, Size = BALE, Color = WHEAT,
			Material = Enum.Material.Grass, Parent = stack })
		b.CFrame = CFrame.new(at.X, gy + BALE.Y * (0.5 + row), at.Z)
			* CFrame.new(col * (BALE.X + 0.2), 0, (i % 2 - 0.5) * 0.3)
			* CFrame.Angles(0, i * 0.12, 0)
		main = main or b
		for _, sgn in ipairs({ -0.9, 0.9 }) do        -- twine, so a bale reads as a bale
			local t = mk({ Name = "Twine", Size = Vector3.new(0.22, BALE.Y + 0.1, BALE.Z + 0.1),
				Color = Color3.fromRGB(140, 108, 52), Material = Enum.Material.Fabric,
				Parent = stack })
			t.CFrame = b.CFrame * CFrame.new(sgn, 0, 0)
		end
	end
	stack.PrimaryPart = main
	stack.WorldPivot = CFrame.new(at.X, gy, at.Z)
	stack.Parent = questFolder
	HAY.stack = stack

	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = "Carry The Bales"
	pr.ObjectText = "5 Hay Bales"
	pr.HoldDuration = 0.3
	pr.KeyboardKeyCode = Enum.KeyCode.E
	pr.MaxActivationDistance = 16
	pr.RequiresLineOfSight = false
	pr.Parent = main
	pr.Triggered:Connect(function()
		if HAY.carrying or not (stack and stack.Parent) then return end
		HAY.carrying = true
		pr.Enabled = false
		-- the same carry rig the repair parts use: anchored, re-CFramed onto you every frame.
		--
		-- (!) IN FRONT, so -Z. A root part looks down its NEGATIVE Z, which is why the repair
		-- parts' +1.8 puts them on your back -- get the sign wrong here and the stack rides behind
		-- you where you cannot see it. Chest height and tipped back a few degrees, like something
		-- heavy held against you, and low enough that it does not fill the chase camera.
		carryProp(stack, CFrame.new(0, 1.5, -3.2) * CFrame.Angles(math.rad(7), 0, math.rad(2)), "balestack")
		flashBanner(E_BARN .. " Bales in your arms -- get them to the FARM HOUSE!", 4)
		if _G.guideTrailTo and barnPoint then pcall(_G.guideTrailTo, barnPoint) end
		refreshBanner(); refreshPrompts()
	end)
	HAY.stackPrompt = pr

	poofAt(Vector3.new(at.X, gy + 2, at.Z), WHEAT, 14)
	flashBanner(E_BARN .. " That's all five -- pick the stack up outside!", 4)
	if _G.guideTrailTo then pcall(_G.guideTrailTo, Vector3.new(at.X, gy + 2, at.Z)) end
	refreshBanner(); refreshPrompts()
end

-- ============================================================================
-- LEG TWO: THE BALES GO TO THE FARM HOUSE
-- ============================================================================
local function tipTheLoad()
	if step ~= 5 or loadTipped then return end
	-- bales only. Arriving with loose straw (or with the trailer still at the factory) says so
	-- rather than quietly finishing the quest a stop early.
	if HAY.kind ~= "bales" then
		flashBanner(HAY.kind == "pressing"
			and (E_WHEAT .. " The bales aren't pressed yet -- back to the factory console!")
			or  (E_WHEAT .. " That's loose straw -- it goes to the HAY BALE FACTORY first!"), 3)
		return
	end
	-- ...and they have to be ON YOU. Standing at the farm house empty-handed while five bales sit
	-- outside the factory is not a delivery, and saying so is better than silently doing nothing.
	if HAY.stack and not HAY.carrying then
		flashBanner(E_BARN .. " Fetch the bales first -- they're stacked outside the factory!", 3)
		return
	end
	loadTipped = true
	step = 6
	stopDriving()

	-- the stack comes off your back and lands at the door
	if HAY.stack and HAY.stack.Parent then
		dropCarried(HAY.stack)
		local drop = barnPoint + Vector3.new(0, 0, -5)
		local gy = groundY(drop)
		HAY.stack:PivotTo(CFrame.new(drop.X, gy + 1.2, drop.Z))
		HAY.carrying = false
	end

	-- the load tips out into the barn doorway
	for i, sheaf in ipairs(loadParts) do
		if sheaf.Parent then
			local goal = barnPoint + Vector3.new(((i % 3) - 1) * 3, 1 + math.floor(i / 3) * 1.2, -4 + (i % 2) * 2)
			tween(sheaf, 0.6 + i * 0.05, { CFrame = CFrame.new(goal) * CFrame.Angles(0, i * 0.7, 0) },
				Enum.EasingStyle.Quad)
		end
	end
	-- they stop being glued to the tractor the moment they leave it
	for i = #tractorParts, 1, -1 do
		for _, sheaf in ipairs(loadParts) do
			if tractorParts[i].part == sheaf then table.remove(tractorParts, i) break end
		end
	end

	poofAt(barnPoint + Vector3.new(0, 3, 0), WHEAT, 20)
	firework(barnPoint + Vector3.new(0, 14, 0), GOLD)
	task.delay(0.5, function() firework(barnPoint + Vector3.new(12, 12, -8), WHEAT) end)

	_G.tractorQuestComplete = true    -- IslandTaskWatcher claims the crate tokens off this
	_G.tractorQuestStep = nil
	payCoins(COIN_REWARD)
	refreshBanner(); refreshPrompts()
	if npcHead then showBubble(npcHead, "A full barn and a running tractor. You're hired!", false) end
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(function() _G.NotifyCenter.push({
			text = ("%s Harvest delivered! +%d coins"):format(E_SPARK, COIN_REWARD), color = GOLD }) end)
	end
	flashBanner(("%s Harvest delivered!  +%d coins -- the FOOD STAND is open! %s")
		:format(E_SPARK, COIN_REWARD, E_SPARK), 6)
	print(("[Tractor] quest complete -- +%d coins, island19 food stand UNLOCKED "
		.. "(_G.tractorQuestComplete = true)"):format(COIN_REWARD))
end

-- ============================================================================
-- PROMPTS
-- ============================================================================
local fitPrompt, drivePrompt, tipPrompt, barnPrompt

refreshPrompts = function()
	for _, rec in ipairs(partRecs) do
		-- lit until it is taken, at every step: pickUpPart owns the "not yet" and "hands full"
		-- answers, and a prompt that quietly vanishes teaches nothing
		if rec.prompt then rec.prompt.Enabled = not rec.taken end
	end
	-- ===== THE REPAIR BAYS =====
	-- A bay answers ONLY for the part it is waiting for, so walking the piston past the radiator
	-- bay does nothing at all instead of fitting the wrong thing in the wrong hole -- and the one
	-- that DOES want what you are carrying is the only lit prompt on the island, which is the
	-- whole navigation aid.
	for id, sock in pairs(sockets) do
		if sock.prompt then
			sock.prompt.Enabled = (step == 1) and not sock.filled
				and carrying ~= nil and carrying.def.id == id
		end
	end
	-- ...AND THE TRACTOR HERSELF TAKES A PART TOO, however many you have found so far. The bays
	-- are the signposted way to do it, not a gate: walking up to the machine holding one part or
	-- the fifth and pressing E starts the repair either way. They are far apart, so there is never
	-- a choice of two E prompts in one place.
	if fitPrompt then fitPrompt.Enabled = (step == 1) and carrying ~= nil end
	-- "Hop On" is live whenever you are not already aboard, at ANY step: see the note on
	-- startDriving. The GAS pedal, not the seat, is what the repair gates.
	--
	-- (!) BUT NEVER AT THE SAME TIME AS "Fit The Part". Both prompts hang on the SAME hit box and
	-- both are bound to E, and Roblox fires the nearest prompt for a key -- with two on one part
	-- there is no nearest, so which one you got was luck. Carrying a part means E fits it;
	-- empty-handed means E boards.
	if drivePrompt then drivePrompt.Enabled = (not driving) and carrying == nil end
	-- ONE DESTINATION IS LIT AT A TIME. Loose straw lights the factory; pressed bales light the
	-- farm house; mid-press nothing out here is lit at all, because the job is at the console.
	-- the farm house only answers once the bales are ACTUALLY on your back, so the prompt is never
	-- lit for a delivery you cannot make
	local canTip = (step == 5) and not loadTipped
	local haveBales = HAY.kind == "bales" and (HAY.carrying or not HAY.stack)
	if HAY.prompt then HAY.prompt.Enabled = canTip and HAY.kind == "straw" end
	if tipPrompt then tipPrompt.Enabled = canTip and haveBales end
	if barnPrompt then barnPrompt.Enabled = canTip and haveBales end
end

-- ============================================================================
-- THE NPC
-- ============================================================================
local function questPages()
	if step >= 6 then
		return { "Barn's full and she's running sweet.", "Come back any time, farmhand." }
	elseif step == 5 then
		return { "Now get that load down to the barn!" }
	elseif step == 4 then
		return { ("Drive her through the wheat! %d of %d cut."):format(harvested, WHEAT_TARGET) }
	elseif step == 3 then
		return { "She's whole again -- go on, turn the key!" }
	elseif step == 1 then
		if carrying then return { "That's one of them! Get it back on the tractor." } end
		return {
			("Still %d part%s missing."):format(PART_COUNT - fitted, (PART_COUNT - fitted) == 1 and "" or "s"),
			"They'll have rolled off across the whole island. Have a good look round.",
		}
	end
	return {
		"My tractor's died on me, right in the middle of harvest.",
		"Worse than that -- five bits of her have gone missing.",
		"Find them, fit them, and get her running again.",
		"Then cut me a section of that wheat and run it to the barn.",
		("Do all that and there's %d coins in it. Deal?"):format(COIN_REWARD),
	}
end

local function wireNPC(head)
	if not head then return end
	-- THE STOCK PROMPT, exactly as every other island's quest giver has it: Talk / the NPC's name,
	-- no hold, TALK_DISTANCE, no line-of-sight requirement. It was the big custom card, which made
	-- this one NPC look like a different kind of object from the ten identical NPCs elsewhere in
	-- the realm -- and the card is the tractor's, not everything's.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	-- the OWNER's name, unless the owner is the machine. With no NPC on the island the tractor
	-- gives the quest itself, and reading the parent verbatim put "Talk / tractor" on screen --
	-- which reads as a bug rather than as a farmer standing there.
	local owner = head.Parent and head.Parent.Name
	prompt.ObjectText = (owner and not string.find(norm(owner), "tractor", 1, true) and owner)
		or "The Farmer"
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = TALK_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = head
	print(("[Tractor] quest giver '%s' -> DEFAULT prompt ('Talk' / '%s', %d studs)")
		:format(head:GetFullName(), prompt.ObjectText, TALK_DISTANCE))

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
				flashBanner(E_WRENCH .. " Find the five missing tractor parts!", 3.5)
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
-- GO -- the streaming-safe boot
-- ============================================================================
task.spawn(function()
	island = pollFor(function()
		for _, m in ipairs(Workspace:GetChildren()) do
			if m:IsA("Model") and norm(m.Name) == ISLAND_NAME then return m end
		end
		return nil
	end, 300)
	if not island then
		warn(("[Tractor] no Workspace model named '%s' after 5 minutes -- the Broken Tractor quest is "
			.. "INACTIVE. Build the island and name it '%s'."):format(ISLAND_NAME, ISLAND_NAME))
		return
	end
	homeToIsland()
	pollFor(function() return island:FindFirstChildWhichIsA("BasePart", true) end, 120)
	findFloor(island)
	if not floorPart then
		warn("[Tractor] island19 has no BaseParts -- nothing to stand anything on, quest inactive")
		return
	end

	-- ===== the boundary: READ AND NEVER WRITTEN =====
	-- Not hidden, not made non-solid, not touched. It is normally a large area part that is
	-- visibly part of the island, and hiding one of those is what made island18's boundary and
	-- island15's floor disappear. Two numbers are taken off it and nothing else.
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") and BOUND_NAMES[norm(d.Name)] then boundPart = d break end
	end
	if boundPart then
		boundCF, boundHalf = boundPart.CFrame, boundPart.Size * 0.5
		-- a tall VOLUME must be ignored by ground rays or props land on its lid; a flat PLATE
		-- lying on the ground IS ground and must not be.
		boundIsVolume = boundPart.Size.Y > 8
		print(("[Tractor] placement boundary: %s (%s) -- read only, untouched")
			:format(boundPart:GetFullName(), boundIsVolume and "volume" or "plate"))
	end

	-- ===== the field =====
	local fieldBlock = findByName(island, FIELD_NAME)
	if fieldBlock and fieldBlock:IsA("BasePart") then
		fieldCF = CFrame.new(fieldBlock.Position.X, fieldBlock.Position.Y, fieldBlock.Position.Z)
			* (fieldBlock.CFrame - fieldBlock.CFrame.Position)
		fieldHalf = fieldBlock.Size * 0.5
		hideMarker(fieldBlock)     -- refuses on its own if the block is too big to be a marker
		print(("[Tractor] wheat field: %s (%.0f x %.0f studs)")
			:format(fieldBlock:GetFullName(), fieldBlock.Size.X, fieldBlock.Size.Z))
	end

	-- ===== the tractor: a MODEL is adopted, a PART is a placement block =====
	local tBlock = findByName(island, TRACTOR_NAME)
	if tBlock and tBlock:IsA("Model") then
		-- ===== YOUR MODEL, DRIVEN =====
		-- A hand-built tractor has no offset table, which is the only thing the driving half
		-- actually needs -- so one is MEASURED off the model as it stands. Every part records
		-- where it sits relative to a chosen root, and from then on the model is driven exactly
		-- like the built one: move the root, re-pose everything from its offsets.
		tractorModel = tBlock

		-- the root: your PrimaryPart if you set one, otherwise the single biggest part, which on
		-- a vehicle is reliably the chassis or body rather than a mirror or an exhaust pipe.
		local root = tBlock.PrimaryPart
		if not root then
			local bestVol
			for _, d in ipairs(tBlock:GetDescendants()) do
				if d:IsA("BasePart") then
					local v = d.Size.X * d.Size.Y * d.Size.Z
					if not bestVol or v > bestVol then root, bestVol = d, v end
				end
			end
			if root then tBlock.PrimaryPart = root end
		end

		if not root then
			warn("[Tractor] the 'tractor' Model has no BaseParts -- nothing to drive")
		else
			tractorRoot = root
			local n = 0
			for _, d in ipairs(tBlock:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true          -- driven by CFrame, never by physics
					if d ~= root then
						tractorParts[#tractorParts + 1] =
							{ part = d, off = root.CFrame:ToObjectSpace(d.CFrame) }
						n += 1
					end
				end
			end

			-- YOUR "wheel" PARTS, from inside the model. Same rule as the built rig: the axle is
			-- the thinnest dimension, the radius comes from the other two, and the front pair
			-- (whatever sits ahead of the root) also steers.
			local wheels = 0
			for _, w in ipairs(tBlock:GetDescendants()) do
				if w:IsA("BasePart") and norm(w.Name) == "wheel" then
					local off = root.CFrame:ToObjectSpace(w.CFrame)
					local sz = w.Size
					local axis, r
					if sz.X <= sz.Y and sz.X <= sz.Z then axis, r = "x", (sz.Y + sz.Z) * 0.25
					elseif sz.Y <= sz.X and sz.Y <= sz.Z then axis, r = "y", (sz.X + sz.Z) * 0.25
					else axis, r = "z", (sz.X + sz.Y) * 0.25 end
					wheelParts[#wheelParts + 1] = { part = w, off = off, radius = math.max(0.5, r),
						steers = off.Position:Dot(CFrame.Angles(0, TRACTOR_YAW, 0).LookVector) > 0,
						adopted = true, axis = axis }
					wheels += 1
				end
			end

			-- RIDE HEIGHT IS MEASURED, NOT IMPOSED. Whatever gap you left between the root and
			-- the ground is the gap it keeps while driving, so starting the engine cannot shift
			-- it up or down by a single stud.
			tractorSeatH = math.max(0.5, root.Position.Y - groundY(root.Position))
			tractorCF = root.CFrame

			print(("[Tractor] adopted your tractor model '%s' -- %d part(s) rigged, %d wheel(s), "
				.. "ride height %.1f. Forward is the model's -Z: if it drives backwards, rotate "
				.. "the model 180 degrees in Studio.")
				:format(tBlock:GetFullName(), n, wheels, tractorSeatH))
			if wheels == 0 then
				warn("[Tractor] no parts named 'wheel' inside the model -- it will slide rather "
					.. "than roll. Name the four wheels 'wheel' and they turn on their own.")
			end
			buildSockets()      -- the five glowing holes the missing parts drop into
		end
	else
		local at
		if tBlock then
			at = baseFrameOf(tBlock)
			hideMarker(tBlock)
			-- (!) AND UNQUERYABLE EVEN IF hideMarker REFUSED IT. buildTractor now raycasts down
			-- at this spot to find the ground, and a marker block still answering rays would BE
			-- the thing the ray hits -- seating the tractor on top of its own marker, a whole
			-- block-height too high. hideMarker declines to touch anything over 40 studs (that
			-- guard exists because hiding big parts has wrecked two islands), so CanQuery is set
			-- here explicitly. It stops the block answering rays without making it vanish, which
			-- is the property that was actually dangerous.
			tBlock.CanQuery = false
		elseif fieldCF then
			local p = (fieldCF * CFrame.new(0, 0, fieldHalf.Z + 18)).Position
			at = CFrame.new(p.X, groundY(p), p.Z)
		else
			local c = floorCF.Position
			at = CFrame.new(c.X, floorTopY or c.Y, c.Z)
		end
		buildTractor(at)
		tractorSeatH = SEAT_HEIGHT
		buildSockets()
		print(("[Tractor] tractor built at (%.0f, %.0f, %.0f)")
			:format(tractorCF.Position.X, tractorCF.Position.Y, tractorCF.Position.Z))
	end

	-- no field block: plant one beside the tractor rather than leaving the quest unfinishable
	if not fieldCF and tractorCF then
		local p = (tractorCF * CFrame.new(0, 0, -60)).Position
		fieldCF = CFrame.new(p.X, groundY(p), p.Z)
		fieldHalf = Vector3.new(48, 1, 48)
		warn("[Tractor] no 'WheatField' block -- planted a 96 x 96 field in front of the tractor")
	end
	buildField()

	-- ===== WHERE THE HARVEST GOES: YOUR BUILDING, NEVER A GENERATED ONE =====
	-- (!) NOTHING IS BUILT HERE ANY MORE. This used to raise a whole barn 70 studs east of the
	-- field when it could not find one, which is how island19 ended up with a script's farm house
	-- standing next to the farm house you built. The destination is now whatever YOU put there:
	-- a part or a model named "Farm House" (or "Barn" -- both work, spaces and case ignored). It
	-- is adopted exactly as it stands: never hidden, never moved, never rebuilt.
	--
	-- No building, no delivery point, and the quest says so instead of inventing one.
	local bBlock = findByName(island, "farmhouse") or findByName(island, BARN_NAME)
	if bBlock then
		barnModel = bBlock:IsA("Model") and bBlock or nil
		barnPoint = baseFrameOf(bBlock).Position
		print(("[Tractor] delivery point adopted: %s at %.0f, %.0f, %.0f -- nothing generated")
			:format(bBlock:GetFullName(), barnPoint.X, barnPoint.Y, barnPoint.Z))
	else
		warn("[Tractor] NO 'Farm House' (or 'Barn') on " .. ISLAND_NAME .. " -- there is nowhere to "
			.. "deliver the harvest and the quest cannot be finished. Name the building's part "
			.. "'Farm House' and rejoin. Nothing was generated in its place.")
	end

	-- ===== the tip point at the farm house =====
	if barnPoint then
		local pad = mk({ Name = "TipPad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.45, 16, 16),
			Color = WHEAT_D, Transparency = 0.2, CanQuery = true, Parent = questFolder })
		local p = barnPoint + Vector3.new(0, 0, -14)
		pad.CFrame = CFrame.new(p.X, groundY(p) + 0.22, p.Z) * CFrame.Angles(0, 0, math.rad(90))
		tipPrompt = Instance.new("ProximityPrompt")
		tipPrompt.ActionText = "Tip The Bales"; tipPrompt.ObjectText = "Farm House"
		tipPrompt.HoldDuration = 0.4; tipPrompt.Enabled = false
		tipPrompt.KeyboardKeyCode = Enum.KeyCode.E
		tipPrompt.MaxActivationDistance = 18   -- a pad you drive a tractor onto, so a little wider
		tipPrompt.RequiresLineOfSight = false
		tipPrompt.Parent = pad
		tipPrompt.Triggered:Connect(tipTheLoad)
		print("[Tractor] farm house tip pad -> DEFAULT prompt (18 studs)")

		-- ===== THE SAME E PROMPT, ON THE BUILDING ITSELF =====
		-- The pad is a 16-stud disc on the ground; the farm house is the thing you actually drive
		-- at and the thing the banner tells you to find. Prompting only on the disc meant lining
		-- up with a spot rather than arriving at a building. Both carry the prompt now, they
		-- enable and disable together, and whichever you are nearer to is the one Roblox shows --
		-- so it reads as one prompt on one destination however you approach it.
		local face                                 -- the biggest part of it = its broadside
		if barnModel then
			local best = 0
			for _, d in ipairs(barnModel:GetDescendants()) do
				if d:IsA("BasePart") then
					local vol = d.Size.X * d.Size.Y * d.Size.Z
					if vol > best then best, face = vol, d end
				end
			end
		end
		if face then
			barnPrompt = Instance.new("ProximityPrompt")
			barnPrompt.ActionText = "Tip The Bales"; barnPrompt.ObjectText = "Farm House"
			barnPrompt.HoldDuration = 0.4; barnPrompt.Enabled = false
			barnPrompt.KeyboardKeyCode = Enum.KeyCode.E
			barnPrompt.RequiresLineOfSight = false   -- a barn wall must not hide its own prompt
			-- reach still measured off the BUILDING (it is enormous compared to a prompt's default
			-- 10 studs) -- but with the stock prompt look, not the tractor's card
			barnPrompt.MaxActivationDistance = reachOf(face, 14)
			barnPrompt.Parent = face
			barnPrompt.Triggered:Connect(tipTheLoad)
			print(("[Tractor] farm house building -> DEFAULT prompt (%.0f studs off '%s')")
				:format(barnPrompt.MaxActivationDistance, face.Name))
		end

		-- ================================================================================
		-- THE BARN'S OWN LITTLE HUD -- same idea as the tractor's socket tags
		-- ================================================================================
		-- A prompt only announces itself once you are already standing on the thing. The delivery
		-- leg is a drive across the farm, so the barn has to say what it is from across the
		-- field. It rides ABOVE THE BARN rather than on the ground disc, because the barn is what
		-- you can actually see from the far end of the crop.
		--
		-- It only lights up on the leg where it matters. A barn glowing through the whole quest
		-- is scenery you stop seeing, and then it is useless on the one leg it was built for.
		local anchor = face or pad
		local tag = Instance.new("BillboardGui")
		tag.Name = "BarnHud"; tag.Adornee = anchor; tag.Size = UDim2.fromOffset(250, 92)
		tag.StudsOffset = Vector3.new(0, face and (face.Size.Y * 0.5 + 9) or 12, 0)
		tag.AlwaysOnTop = true; tag.MaxDistance = 600; tag.Enabled = false; tag.Parent = anchor

		local card = Instance.new("Frame")
		card.Size = UDim2.fromScale(1, 1); card.BackgroundColor3 = FILL
		card.BackgroundTransparency = 0.06; card.BorderSizePixel = 0; card.Parent = tag
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
		local stroke = Instance.new("UIStroke")
		stroke.Color = GOLD; stroke.Thickness = 3; stroke.Parent = card

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1; title.Position = UDim2.new(0, 8, 0, 6)
		title.Size = UDim2.new(1, -16, 0, 40); title.Font = Enum.Font.FredokaOne
		title.TextColor3 = TEXTC; title.TextScaled = true
		title.Text = E_BARN .. " THE FARM HOUSE"; title.Parent = card

		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1; sub.Position = UDim2.new(0, 8, 0, 46)
		sub.Size = UDim2.new(1, -16, 0, 38); sub.Font = Enum.Font.GothamBold
		sub.TextColor3 = GREEN_D; sub.TextScaled = true
		sub.Text = "Press E to tip the load"; sub.Parent = card

		-- and the barn itself glows, so it reads as the destination from a distance the text
		-- would be unreadable at
		local glow
		if barnModel then
			glow = Instance.new("Highlight")
			glow.FillColor = GOLD; glow.FillTransparency = 0.85
			glow.OutlineColor = Color3.fromRGB(255, 240, 200); glow.OutlineTransparency = 0.15
			glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			glow.Enabled = false; glow.Adornee = barnModel; glow.Parent = barnModel
		end

		task.spawn(function()
			while pad.Parent do
				task.wait(0.12)
				-- lit only on the leg that ends HERE. Loose straw is the factory's business, and
				-- a farm house glowing while you are meant to be at the baler is a wrong signpost.
				local live = (step == 5) and HAY.kind == "bales" and not loadTipped
				tag.Enabled = live
				if glow then glow.Enabled = live end
				pad.Transparency = live and (0.15 + math.abs(math.sin(os.clock() * 2)) * 0.3) or 0.85
				if live then
					-- the card breathes with the pad, so the two read as one destination
					stroke.Thickness = 2 + math.abs(math.sin(os.clock() * 2)) * 2.5
					-- the bales ride on your BACK now, not in the trailer, so #loadParts (which
					-- counts cut straw) is the wrong thing to report on this leg
					sub.Text = HAY.carrying and ("Press E -- %d bales on your back")
						:format(HAY.pressed or 5) or "Press E to drop them off"
				end
			end
		end)
	end

	-- ===== THE FIRST STOP: THE HAY BALE FACTORY =====
	-- The factory is its own script and may boot after this one, so its tip point is built when it
	-- announces itself (_G.hayFactory) rather than assumed to be standing there. Bounded, because
	-- a wait with no end is how an island with no factory hangs one thread forever.
	task.spawn(function()
		local t0 = os.clock()
		while not (_G.hayFactory and _G.hayFactory.point) and os.clock() - t0 < 60 do
			task.wait(1)
		end
		local fac = _G.hayFactory
		if not (fac and fac.point) then
			warn("[Tractor] the hay bale factory never announced itself in 60s -- the straw has "
				.. "nowhere to go. Is HayBaleFactory.client.lua running on " .. ISLAND_NAME .. "?")
			return
		end
		local pad = mk({ Name = "FactoryTipPad", Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.45, 16, 16), Color = WHEAT, Transparency = 0.2,
			CanQuery = true, Parent = questFolder })
		local p = fac.point
		pad.CFrame = CFrame.new(p.X, groundY(p) + 0.22, p.Z) * CFrame.Angles(0, 0, math.rad(90))
		HAY.prompt = Instance.new("ProximityPrompt")
		HAY.prompt.ActionText = "Tip The Straw In"; HAY.prompt.ObjectText = "Hay Bale Factory"
		HAY.prompt.HoldDuration = 0.4; HAY.prompt.Enabled = false
		HAY.prompt.KeyboardKeyCode = Enum.KeyCode.E
		HAY.prompt.MaxActivationDistance = 18    -- same as the farm house pad: you arrive driving
		HAY.prompt.RequiresLineOfSight = false
		HAY.prompt.Parent = pad                  -- stock prompt; the card belongs to the tractor
		HAY.prompt.Triggered:Connect(HAY.deliver)
		print("[Tractor] factory tip pad -> DEFAULT prompt (18 studs)")
		refreshPrompts()
		-- the pad breathes on the leg it matters for, like the farm house's does
		task.spawn(function()
			while pad.Parent do
				task.wait(0.12)
				local live = (step == 5) and HAY.kind == "straw" and not loadTipped
				pad.Transparency = live and (0.15 + math.abs(math.sin(os.clock() * 2)) * 0.3) or 0.85
			end
		end)
		print(("[Tractor] factory tip point ready at %.0f, %.0f, %.0f"):format(p.X, p.Y, p.Z))
	end)

	-- ===== the fit + drive prompts on the tractor =====
	if tractorRoot then
		local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(14, 10, 16),
			CFrame = tractorRoot.CFrame * CFrame.new(0, 1, 0), Parent = questFolder })
		-- the hit box rides with the machine, so the prompts stay reachable once it is moving
		tractorParts[#tractorParts + 1] = { part = hit, off = CFrame.new(0, 1, 0) }

		fitPrompt = Instance.new("ProximityPrompt")
		fitPrompt.ActionText = "Fit The Part"; fitPrompt.ObjectText = "Broken Tractor"
		fitPrompt.HoldDuration = 0.3; fitPrompt.Enabled = false; fitPrompt.Parent = hit
		-- (!) MEASURED OFF THE MODEL, THEN CLAMPED, and the clamp is doing real work: an adopted
		-- tractor with one stray part welded into it -- a rogue baseplate, a decal frame, anything
		-- far from the body -- blows its bounding box up, and the boot log caught this one asking
		-- for 614 STUDS. That is a "Fit The Part" card floating over half the island. Whatever the
		-- model measures, you have to be within 26 studs of the machine to fit anything to it.
		bigPrompt(fitPrompt, tractorModel, 16)
		fitPrompt.MaxActivationDistance = math.clamp(fitPrompt.MaxActivationDistance, 18, 26)
		fitPrompt.Triggered:Connect(fitPart)

		drivePrompt = Instance.new("ProximityPrompt")
		drivePrompt.ActionText = "Hop On"; drivePrompt.ObjectText = "Tractor"
		drivePrompt.HoldDuration = 0; drivePrompt.Enabled = false; drivePrompt.Parent = hit
		-- (!) A FLAT 20 STUDS, not a reach measured off the model. bigPrompt is called WITHOUT a
		-- reachFrom here on purpose: given one it sizes the range to the tractor's own bounding
		-- box, and on a big machine that put the card on screen from most of the way across the
		-- yard -- a full-size overlay hanging there while you were doing something else entirely.
		-- Twenty studs is close enough that it only appears when you have walked up to her.
		bigPrompt(drivePrompt)
		drivePrompt.MaxActivationDistance = 20
		drivePrompt.Triggered:Connect(startDriving)
		-- ===== THE ONLY TWO CUSTOM PROMPTS IN THE QUEST =====
		-- The big card is the tractor's, and the tractor's alone. It earns it: this is the object
		-- you mount, repair and drive, and the card is what makes it read as a machine you operate
		-- rather than one more thing to touch. Everything else -- the five pickups, the repair
		-- bays, both tip points and the quest giver -- is a stock ProximityPrompt with the same
		-- settings the other islands use.
		print(("[Tractor] CUSTOM big prompt: the tractor only -- 'Fit The Part' (%.0f studs, off the "
			.. "machine's own size) + 'Hop On' (%.0f studs, fixed). Everything else in this quest "
			.. "uses the default Roblox prompt.")
			:format(fitPrompt.MaxActivationDistance, drivePrompt.MaxActivationDistance))

		-- ===== AND NO PART NAMES ON THE MACHINE, EVER =====
		-- Ours are not built there any more (see buildSockets) and a picked-up part's label is
		-- destroyed with the pickup (see pickUpPart), so this is the receipt rather than the fix.
		-- It sweeps any "SocketTag" a stale copy of this script may have left on the tractor --
		-- those are ours by name and safe to remove -- and REPORTS anything else it finds without
		-- touching it, because a BillboardGui on your own model is yours, not this script's.
		task.delay(1, function()
			if not (tractorModel and tractorModel.Parent) then return end
			local ours, theirs = 0, {}
			for _, d in ipairs(tractorModel:GetDescendants()) do
				if d:IsA("BillboardGui") then
					if d.Name == "SocketTag" then d:Destroy(); ours += 1
					else theirs[#theirs + 1] = d.Name end
				end
			end
			print(("[Tractor] tractor label check: %d part-name label(s) on the machine%s")
				:format(ours, ours == 0 and " -- clean, none are created there any more"
					or " swept (left by an older build)"))
			if #theirs > 0 then
				print(("[Tractor] (%d other BillboardGui(s) on your model, left alone: %s)")
					:format(#theirs, table.concat(theirs, ", ")))
			end
		end)
	end

	-- ===== OLD-BUILD PROPS GO, AND KEEP GOING =====
	-- Rojo only ADDS: a stale copy of this file baked into the place runs alongside the synced one
	-- and builds its own set of five parts. That is how you end up with a flat old-style prop
	-- standing in the same spot as a good one -- and why the parts looked like placeholders even
	-- after the models were rebuilt: what you were looking at was the OLD script's set.
	--
	-- (!) THE BUILD TAG IS WHAT MAKES THIS SAFE. Removing "every prop that is not mine" would mean
	-- two copies of the SAME build deleting each other's work, and the worst case is a field with
	-- no parts in it at all. A prop is only removed if its Build attribute is missing or different
	-- from PARTS.BUILD -- so an older version's props die and a same-version twin's are left alone.
	--
	-- It runs on a short repeat rather than once, because a stale copy may not have built its set
	-- yet at the moment we boot -- a single sweep at startup misses everything that arrives late.
	do
		local function sweep()
			local stale = 0
			local function scan(parent)
				for _, d in ipairs(parent:GetChildren()) do
					if d:IsA("Model") and string.sub(d.Name, 1, 12) == "TractorPart_"
						and d:GetAttribute("QuestProp")
						and d:GetAttribute("Build") ~= PARTS.BUILD
						and not d:IsDescendantOf(questFolder) then
						d:Destroy()
						stale += 1
					end
				end
			end
			-- two levels, not a full Workspace walk: every prop is a direct child of some copy's
			-- own quest folder, and those folders are direct children of Workspace
			scan(Workspace)
			for _, d in ipairs(Workspace:GetChildren()) do
				if (d:IsA("Folder") or d:IsA("Model")) and d ~= questFolder then scan(d) end
			end
			return stale
		end
		local total = sweep()
		task.spawn(function()
			for _ = 1, 12 do            -- ~30s of cover for a late-booting stale copy
				task.wait(2.5)
				local n = sweep()
				if n > 0 then
					total += n
					warn(("[Tractor] removed %d more old-build part prop(s) -- a stale copy of this "
						.. "script is still running and building its own set."):format(n))
				end
			end
		end)
		if total > 0 then
			warn(("[Tractor] removed %d leftover part prop(s) from an older build. Check the boot "
				.. "log's [BootCheck]/NOT-IN-MANIFEST list and delete the stale BrokenTractorQuest "
				.. "baked into the place file -- this only papers over it."):format(total))
		end
	end

	-- every part on its own hand-placed marker, and nothing anywhere else (see placeParts)
	placeParts()

	-- she sits there smouldering, sparking and a wheel down until someone fixes her. Guarded on
	-- engineRunning so a /fix issued before this point does not resurrect the broken look.
	if not engineRunning then brokenFx.make() end

	-- ===== the quest giver =====
	local function findNpc()
		local function headOf(d)
			return d:FindFirstChild("Head") or d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart", true)
		end
		for _, d in ipairs(island:GetDescendants()) do
			if d:IsA("Model") and string.find(norm(d.Name), "npc", 1, true) then
				local h = headOf(d)
				if h then return d, h end
			end
		end
		-- ...and one standing LOOSE IN WORKSPACE beside the island, which is how an NPC dragged
		-- into place without being re-parented ends up. This realm genuinely does that -- there
		-- is a 'Candy Npc' sitting at the Workspace root right now -- and inside-the-island-only
		-- searching would report it missing and leave the quest on the tractor forever.
		local c = island:GetPivot().Position
		for _, d in ipairs(Workspace:GetChildren()) do
			if d:IsA("Model") and d ~= island and string.find(norm(d.Name), "npc", 1, true) then
				local h = headOf(d)
				if h and (Vector3.new(h.Position.X, 0, h.Position.Z)
					- Vector3.new(c.X, 0, c.Z)).Magnitude <= LOOSE_RADIUS then
					warn(("[Tractor] quest giver '%s' is parented to Workspace, not inside island19. "
						.. "Used anyway -- drag it into the island Model in Studio or it will stream "
						.. "out at distance."):format(d:GetFullName()))
					return d, h
				end
			end
		end
		return nil
	end
	local npcModel, head = findNpc()
	if head then
		npcHead = head
		wireNPC(head)
		print("[Tractor] quest giver: " .. npcModel:GetFullName())
	else
		-- the tractor gives the quest itself, so a bare island still plays through. The NPC can
		-- still turn up late -- its model is one more thing to replicate -- and takes over when
		-- it does, with the stand-in prompt switched off so there are never two givers.
		local standIn = tractorRoot and wireNPC(tractorRoot)
		warn("[Tractor] no NPC on island19 yet -- the tractor is giving the quest for now")
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 120 do
				task.wait(2)
				local m2, h2 = findNpc()
				if h2 then
					npcHead = h2; wireNPC(h2)
					if standIn then standIn.Enabled = false end
					print("[Tractor] Candy Npc arrived late -- quest giver handed over to " .. m2:GetFullName())
					return
				end
			end
		end)
	end

	anchorAll()
	refreshBanner(); refreshPrompts()
	print("[Tractor] ready on " .. island:GetFullName())
	-- RETAINER SIGNAL: the quest reached the end of its build with its world objects up. QuestRetainer
	-- watches this flag; anything still false once its island has streamed in gets force-streamed and
	-- re-run. It is set HERE, at the ready print, not at the top of the file -- a quest that bailed
	-- early on a missing marker must NOT look built. See QuestRetainer.client.luau.
	_G.questBuilt_tractor = true
end)

-- DYING OR RESPAWNING WHILE SEATED. The character that was hidden and anchored is gone, and the
-- new one inherits none of it -- but `driving` would still be true, the camera would still be
-- scriptable and the HUD would still be up, with nothing to control. Reset the whole state.
player.CharacterAdded:Connect(function()
	if driving then
		driving = false
		gas, speed = 0, 0
		shadowWas = {}            -- belonged to the old character; nothing to restore
		seatedHrp, seatedHum = nil, nil
		driveHUD.gui.Enabled = false
		driveHUD.setHud(false)    -- respawning in the seat must not leave the bottom HUD hidden
		if FH.closePart then FH.closePart() end    -- ...nor a repair panel with no player behind it
		stopCamera()
		-- the NEW character inherits none of the hiding, but its Humanoid still needs its name
		-- tag switching back on -- and the looped cab sound would otherwise run with nobody in
		-- the seat for the rest of the session.
		showDriver()
		setCabSound(false)
		refreshPrompts()
	end
end)

-- ============================================================================
-- TWO TRACTORS AT ONCE -- and why the parked one dims
-- ============================================================================
-- The tractor is ONE hand-placed model that every client sees standing in the field, but driving
-- it is local: your client moves it, nobody else's does. So when another kid drives past you on
-- theirs -- CarryView draws a tractor under any player who says "tractor" -- the parked one is
-- still sitting there behind them, and the field has two tractors in it. That reads as a bug.
--
-- WHILE SOMEBODY ELSE IS DRIVING, THE PARKED ONE FADES OUT. When they stop, it comes back.
--
--   * LocalTransparencyModifier, NOT Transparency. This is a model you placed by hand, and its
--     real Transparency is yours -- something else may be reading it, and a script that half
--     finished a fade would leave your tractor permanently see-through in Studio. The modifier
--     is a purely local, render-time override that touches no replicated property at all.
--   * NOT WHILE *YOU* ARE DRIVING. Then the parked model IS the one under you.
--   * THE PROMPT STAYS ON. Fading it is cosmetic and must never cost anyone a turn: you can
--     still walk up and press E while it is invisible, and it snaps back the instant you board.
--   * PARTICLES GO QUIET TOO -- otherwise the exhaust puffs from an empty patch of field. Only
--     the emitters this actually switched off get switched back on, so an emitter that was
--     already idle for its own reasons stays that way.
--
-- Wrapped in a task.spawn with everything local to the closure, because the main chunk of this
-- file is one register short of the Luau ceiling and locals inside a function do not count.
task.spawn(function()
	local FADE = 0.4                 -- seconds for the whole dip, either direction
	local FADE_NEAR = 60             -- inside this many studs it stays solid, so E always has a target
	local level, applied, quieted = 0, -1, {}
	while true do
		local dt = task.wait(0.05)
		local live = tractorModel and tractorModel.Parent
		local want = 0
		if live and not driving then
			local ok, n = pcall(_G.CarryCount, "tractor")
			if ok and (n or 0) > 0 then
				-- SOMEBODY ELSE IS DRIVING. Hide ours -- but only once we are far enough away
				-- that it is scenery rather than the thing we are walking up to. Close in it
				-- stays solid so the prompt you are reaching for has a tractor under it; from
				-- across the field it goes, so the only tractor in view is the one being
				-- driven and nobody sees two at once.
				local hrp = hrpOf()
				local d = (hrp and tractorRoot) and (hrp.Position - tractorRoot.Position).Magnitude or 1e9
				if d > FADE_NEAR then want = 1 end
			end
		end
		-- step toward the target rather than snapping, so a tractor going by does not make the
		-- parked one blink
		if level ~= want then
			local d = math.clamp(want - level, -dt / FADE, dt / FADE)
			level = math.clamp(level + d, 0, 1)
		end
		if live and math.abs(level - applied) > 0.01 then
			applied = level
			for _, d in ipairs(tractorModel:GetDescendants()) do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = level
				elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Fire")
					or d:IsA("Smoke") or d:IsA("Sparkles") then
					if level > 0.5 then
						if d.Enabled then quieted[d] = true; d.Enabled = false end
					elseif quieted[d] then
						quieted[d] = nil
						if d.Parent then d.Enabled = true end
					end
				end
			end
		elseif not live then
			applied = -1             -- rebuilt or streamed out: re-apply from scratch next time
		end
	end
end)

-- ============================================================================
-- TEST COMMANDS -- all require standing near the farm, so none fire elsewhere
--   /fix         -- repair it and start the engine RIGHT NOW: no parts, no key, just drivable
--   /complete    -- fit every part and turn the key (the quest route, minus the fetching)
--   /tractordone -- finish the whole quest
-- ============================================================================

-- ===== /fix =====
-- Bolts every part in and has the engine running in one line. Deliberately different from
-- /complete in two ways:
--
--   * IT SKIPS THE KEY. /complete leaves one turn of the ignition so the start-up sequence
--     still plays; /fix is for when you want to be moving, not watching.
--   * IT DOES NOT TOUCH THE QUEST STEP unless the quest has already been accepted. Repairing
--     a tractor and accepting a job are different things, and forcing step 4 on someone who has
--     not talked to the NPC would skip the dialogue and leave the journal claiming a quest
--     they never took. The seat has never been gated on the step, so the tractor is drivable
--     either way -- that is the whole point of the command.
local function fixTractor()
	clearCarried(); carrying = nil
	for _, rec in ipairs(partRecs) do
		if rec.model.Parent then rec.model:Destroy() end
		rec.taken = true
	end
	for _, s in pairs(sockets) do
		s.filled = true
		if s.tag then s.tag.Enabled = false end
		if s.prompt then s.prompt.Enabled = false end
	end
	fitted = PART_COUNT
	ignitionTries = IGNITION_TRIES
	engineRunning = true
	if closeFixHUD then closeFixHUD() end
	if FH.closePart then FH.closePart() end          -- a bolt panel open over a /fix is a dead end
	if step >= 1 and step < 4 then step = 4 end     -- mid-quest: jump to the harvest
	if driving then updateDriveHUD() end
	-- a puff out of the exhaust stack. Guarded rather than assumed: fixTractor is a command
	-- handler today but is exactly the kind of thing that gets called from somewhere else later,
	-- and an unguarded hrpOf().Position is a nil index on a dead character.
	if tractorRoot and tractorRoot.Parent then
		poofAt((tractorRoot.CFrame * CFrame.new(-1.3, 3.0, -3.6)).Position,
			Color3.fromRGB(80, 78, 76), 14)
		shakeCamera(1.4, 0.5)
	end
	refreshBanner(); refreshPrompts()
	flashBanner(E_TRACTOR .. " FIXED -- hop on and hold FORWARD!", 3.5)
	brokenFx.clear()
	print("[Tractor][TEST] /fix -- all parts fitted, engine running, ready to drive")
end

player.Chatted:Connect(function(msg)
	local text = tostring(msg or ""):lower()
	local hrp = hrpOf()
	if not (tractorCF and hrp) then return end
	if (hrp.Position - tractorCF.Position).Magnitude > 400 then return end
	if text == "/fix" then
		fixTractor()
	elseif text == "/complete" and step < 4 then
		if step == 0 then step = 1 end
		clearCarried(); carrying = nil
		for _, rec in ipairs(partRecs) do
			if rec.model.Parent then rec.model:Destroy() end
			rec.taken = true
		end
		for _, s in pairs(sockets) do
			s.filled = true
			if s.tag then s.tag.Enabled = false end
			if s.prompt then s.prompt.Enabled = false end
		end
		if FH.closePart then FH.closePart() end
		fitted = PART_COUNT
		ignitionTries = IGNITION_TRIES - 1
		step = 3
		print("[Tractor][TEST] /complete -- parts fitted, one turn of the key left")
		turnTheKey()
	elseif text == "/tractordone" and step < 6 then
		-- the engine has to be running for the ending to make sense (the payout dialogue talks
		-- about a repaired tractor), so this skips the repair too rather than half-finishing.
		engineRunning = true
		brokenFx.clear()
		harvested = WHEAT_TARGET
		step = 5
		-- skips BOTH delivery legs: the straw is treated as already baled so the farm-house tip
		-- runs. Without this the command would bounce off tipTheLoad's "that's loose straw" guard
		-- and quietly do nothing, which is the worst possible behaviour for a test command.
		HAY.kind, HAY.owed = "bales", 0
		print("[Tractor][TEST] /tractordone -- skipping the factory leg, tipping the bales")
		tipTheLoad()
	end
end)
