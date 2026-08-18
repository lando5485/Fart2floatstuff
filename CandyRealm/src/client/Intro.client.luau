--======================================================================
-- Intro.client.luau  (StarterPlayerScripts.Intro)  -- CandyRealm
--======================================================================
-- THE OPENING CINEMATIC: a fast, cut-driven descent of the candy tower, ending on a
-- full-screen title card. Ported from the Dino Realm's Intro.client.luau.
--
-- Not one long glide -- a SHOT LIST. Each island gets a different move (punch-in, whip-by,
-- orbit, crane-down), each with its own field-of-view move, and we CUT hard between them.
-- The cuts and the FOV are what make it read as an edited trailer instead of a drone flight.
--
-- NOTHING but the islands is on screen: every ScreenGui in the game is hidden for the
-- duration, plus the Roblox CoreGui. No buttons, no HUD, no chat.
--
--======================================================================
-- WHY THE CHARACTER FLIES TOO (this is the important bit)
--======================================================================
-- The place has StreamingEnabled, and Roblox streams geometry around the CHARACTER, not the
-- camera. Park the camera on Bakery Summit while the body sits on Candy Cane Court and you
-- film 59,000 studs of EMPTY SKY -- the islands aren't on this client at all.
--
-- So the intro carries the character up the tower with the camera:
--   * the body is made INVISIBLE and ANCHORED (it must not fall, or be seen),
--   * RequestStreamAroundAsync yields until each island is genuinely loaded,
--   * and the body is put back on the spawn at the end -- ALWAYS, even on skip or error.
--
-- The server guards the side effect: FlightEconomy skips its climb tick while the
-- "IntroPlaying" attribute is set, or this joyride would set HighestSlot = 11 and hand a
-- brand new player the entire progression bar before they'd moved.
--
--======================================================================
-- SLOTS, NOT MODEL NUMBERS
--======================================================================
-- Candy's island MODELS are numbered 1,2,3,4,5,8,9,11,13,14,15 and their climb order is a
-- fixed SCRAMBLE of that (IslandOrder.SLOT_TO_ISLAND). The Dino version hard-coded model
-- numbers in its shot list, which here would film the tower in a jumbled order and name the
-- islands wrong. So every shot below names a SLOT and resolves through IslandOrder -- the
-- same module the layout pass, the wormhole and the HUD read, so the descent can never
-- disagree with the tower it is filming.
--======================================================================

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")
local Lighting          = game:GetService("Lighting")
local SoundService      = game:GetService("SoundService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer

local IslandOrder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IslandOrder"))

local IntroPlay  = ReplicatedStorage:WaitForChild("IntroPlay", 30)
local IntroDone  = ReplicatedStorage:WaitForChild("IntroDone", 30)
local IntroFocus = ReplicatedStorage:WaitForChild("IntroFocus", 30) -- c->s: move the streaming centre
local IntroArm   = ReplicatedStorage:WaitForChild("IntroArm", 30)   -- s->c: hold/release the pre-roll cover
if not (IntroPlay and IntroDone and IntroFocus) then
	warn("[Intro] remotes missing -> intro disabled")
	return
end

--======================================================================
-- THE PRE-ROLL COVER: never let the player watch themselves spawn in.
--======================================================================
-- The server cannot fire IntroPlay the instant someone joins -- the character has to replicate,
-- SpawnOnIsland1 has to find and place them on the pad, and a direct join costs a DataStore read on top.
-- Measured in Studio that was ~3.4 SECONDS of the player standing on island 1, looking around at the
-- game, before the camera was taken away for a cinematic. The game appeared to start, then start again.
--
-- So a plain black frame goes up on the FIRST frame this script runs -- before any of that -- and comes
-- down only when the cinematic's camera is genuinely moving. The player's first sight of the world is the
-- opening slam onto Bakery Summit, which is the whole point of having an opening.
--
-- THREE WAYS IT COMES DOWN, so it can never trap anyone on black:
--   1. the intro starts driving the camera  -> handed off (cut, no fade -- the slam wants a cut)
--   2. the server says no intro is coming   -> quick fade out
--   3. nothing happens within COVER_TIMEOUT -> quick fade out anyway
--
-- ⚠ NOT ON PORTAL ARRIVALS. ArrivalCinematic already owns a black screen for those (DisplayOrder 10000,
-- carrying its card across the place boundary) and tears it down on its own handoff. A second cover here
-- would still be up after it finished, and nothing would remove it.
local COVER_TIMEOUT = 8
local coverGui, coverDone = nil, false

do
	local arrivedByPortal = false
	local okTd, td = pcall(function()
		return game:GetService("TeleportService"):GetLocalPlayerTeleportData()
	end)
	if okTd and type(td) == "table" then arrivedByPortal = true end

	if not arrivedByPortal then
		coverGui = Instance.new("ScreenGui")
		coverGui.Name = "IntroPreRoll"
		coverGui.ResetOnSpawn = false
		coverGui.IgnoreGuiInset = true
		coverGui.DisplayOrder = 9000 -- under ArrivalCinematic's 10000, over everything else
		coverGui.Parent = player:WaitForChild("PlayerGui")

		local black = Instance.new("Frame")
		black.Name = "Black"
		black.Size = UDim2.new(1, 0, 1, 0)
		black.BackgroundColor3 = Color3.new(0, 0, 0)
		black.BackgroundTransparency = 0 -- opaque from frame one
		black.BorderSizePixel = 0
		black.Parent = coverGui
	end
end

-- Hand the screen to the cinematic: CUT, do not fade. The next thing on screen is the opening slam, and
-- fading into a slam is the one thing that would rob it of its impact.
local function coverCut()
	if coverDone then return end
	coverDone = true
	if coverGui then pcall(function() coverGui:Destroy() end) end
	coverGui = nil
end

-- Let the player into the world without a cinematic: a short fade, so it reads as a load screen ending
-- rather than a light being switched on.
local function coverFade()
	if coverDone then return end
	coverDone = true
	local gui = coverGui
	coverGui = nil
	if not gui then return end
	local black = gui:FindFirstChild("Black")
	if black then
		pcall(function()
			TweenService:Create(black, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end)
	end
	task.delay(0.45, function() pcall(function() gui:Destroy() end) end)
end

if IntroArm then
	IntroArm.OnClientEvent:Connect(function(hold)
		if hold == false then coverFade() end -- "no intro coming" -> let them in
	end)
end

-- Backstop: if the server never speaks at all (it errored, the remote was stripped), do not sit on black.
task.delay(COVER_TIMEOUT, function()
	if not _G.introPlaying then coverFade() end
end)

--======================================================================
-- THE SHOT LIST. Fast. Varied. Cut, don't glide.
--======================================================================
-- `slot` is the CLIMB position (1 = bottom, 11 = summit); the model number and the display
-- name are both looked up from IslandOrder, so renaming or re-slotting an island updates the
-- cinematic for free and cannot desync the label from the island on screen.
--
-- fov0/fov1 = the camera's field of view across the shot. Widening on a whip-by and
-- narrowing on a punch-in is a cheap, very effective way to sell speed and weight.
-- TIMING: +5.0s over the first cut of this table (8.9s -> 13.9s of descent), at the owner's request --
-- but placed where length HELPS rather than scaled uniformly. The slow moves absorb almost all of it
-- (the opening punch, both orbits, the crane landing -- shots built to be looked at), while the whips
-- take only +0.3s each: a whip-by exists to rip past, and stretching one to 1.6s kills the very speed
-- it is there to sell.
local SHOTS = {
	{ slot = 11, move = "punch", t = 3.0, fov0 = 95, fov1 = 55 }, -- Bakery Summit      (was 1.8)
	{ slot = 9,  move = "whip",  t = 1.3, fov0 = 90, fov1 = 95 }, -- Frostbell Peak     (was 1.0)
	{ slot = 7,  move = "orbit", t = 2.4, fov0 = 70, fov1 = 62 }, -- Chocolate Chasm    (was 1.4)
	{ slot = 5,  move = "whip",  t = 1.3, fov0 = 92, fov1 = 98 }, -- Taffy Town         (was 1.0)
	{ slot = 3,  move = "orbit", t = 2.3, fov0 = 72, fov1 = 60 }, -- Cookie Crumble     (was 1.3)
	{ slot = 1,  move = "crane", t = 3.6, fov0 = 80, fov1 = 70 }, -- Candy Cane Court   (was 2.4)
}

local DEFAULT_FOV = 70

-- Touch device = phone/tablet, which is where the frame budget is tightest. Used to drop the one
-- optional post-process effect (see addGrade). Keyboard+touch is a laptop with a touchscreen, not a
-- phone, so it keeps the full grade.
local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local USE_DOF  = not IS_TOUCH

local st = {
	running  = false,
	skipped  = false,
	homeCF   = nil,   -- where the character started (restored no matter what)
	hidden   = {},    -- [BasePart|Decal] = original Transparency
	guis     = {},    -- [ScreenGui] = original Enabled
	world    = {},    -- [BillboardGui] = original Enabled (world-anchored UI: counters, nametags, markers)
	worldConn = nil,  -- Workspace.DescendantAdded watcher: billboards born DURING the cinematic
	pguiConn = nil,   -- PlayerGui.DescendantAdded watcher: mid-intro ScreenGuis + PlayerGui-parented billboards
	enforce  = nil,   -- RenderStepped loop that re-asserts the hide against per-frame Enabled writers
	exclude  = nil,   -- the cinema's own ScreenGui (the ONE gui allowed to stay up)
	ours     = {},    -- [ScreenGui] = true for every gui the cinematic itself builds; never hidden
	prompts  = nil,   -- ProximityPromptService.Enabled before we turned it off
	fx       = {},    -- Lighting post-process effects we added (removed on restore)
	shake    = 0,     -- current impact-shake amplitude (decays every frame)
	blur     = nil,   -- BlurEffect, punched on every cut
	dof      = nil,   -- DepthOfFieldEffect, refocused per shot
	streamed = {},    -- [slot] = true once RequestStreamAroundAsync has been fired for it
}

--======================================================================
-- CINEMATIC GRADE: post-processing, added to Lighting for the intro only.
--======================================================================
-- The single biggest visual upgrade available for nearly free. Punching contrast and
-- saturation, blooming the highlights, and adding a shallow blur makes the same geometry
-- read as a trailer instead of a gameplay screenshot.
--
-- All of it is torn down in restore(), including on skip and on error -- leaving a
-- ColorCorrection clamped over someone's whole session would be a nasty thing to ship.
-- Every post-process effect this file creates carries this prefix, so leftovers can always be found by
-- name rather than only through the tracked table -- which is what makes the sweep below possible.
local FX_PREFIX = "Intro"
local FX_NAMES = { IntroGrade = true, IntroBloom = true, IntroBlur = true, IntroDOF = true }

-- DESTROY ANY LEFTOVER EFFECTS BEFORE ADDING NEW ONES.
--
-- Post-process effects STACK: two BloomEffects in Lighting is double the bloom, two ColorCorrections is
-- double the contrast and saturation. So a single orphan from a run that died between addGrade() and
-- removeGrade() -- an error, a Studio stop mid-cinematic, a client hiccup -- does not just linger, it
-- makes the NEXT playthrough visibly brighter, and the one after that brighter still.
--
-- Sweeping by name on the way IN means the grade is idempotent: whatever state Lighting was left in, the
-- cinematic starts from exactly one of each effect.
local function sweepGrade()
	for _, e in ipairs(Lighting:GetChildren()) do
		if FX_NAMES[e.Name] or (e.Name:sub(1, #FX_PREFIX) == FX_PREFIX and e:IsA("PostEffect")) then
			pcall(function() e:Destroy() end)
		end
	end
end

local function addGrade()
	sweepGrade()
	-- ⚠ GRADED FOR A BRIGHT WORLD. These numbers are NOT the Dino ones, and copying those back will blow
	-- the islands out again.
	--
	-- Dino's grade (+0.03 brightness, +0.22 contrast, +0.20 saturation, bloom threshold 0.82) is built for
	-- a DARK palette: volcanic rock, jungle shade, night sky. Candy is the exact opposite -- pastel pinks,
	-- creams and mints that already sit near white.
	--
	-- The bloom threshold is the main offender. It is a LUMINANCE cutoff: everything brighter than it
	-- glows. Candy surfaces like (255,240,248) are ~0.95 luminance, so at 0.82 literally every island
	-- surface bloomed at once and the whole tower went white. Pushed above 1.0 so only genuine highlights
	-- -- neon, emissive candy, the sun -- bloom, which is what bloom is for.
	--
	-- Saturation and contrast are backed right off for the same reason: adding either to an already
	-- saturated pastel just clips it. The grade is now a light touch, not a filter.
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "IntroGrade"
	cc.Brightness = -0.01                         -- a shade DOWN; the world is bright enough on its own
	cc.Contrast = 0.08
	cc.Saturation = 0.05
	cc.TintColor = Color3.fromRGB(255, 250, 253)  -- barely pink; anything stronger tints the whites
	cc.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "IntroBloom"
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.15   -- ABOVE pastel white: only real highlights bloom, not every sugar surface
	bloom.Parent = Lighting

	local blur = Instance.new("BlurEffect")
	blur.Name = "IntroBlur"
	blur.Size = 0            -- punched up on each cut, decays back to 0
	blur.Parent = Lighting

	st.fx = { cc, bloom, blur }
	st.blur = blur

	-- DEPTH OF FIELD -- the biggest look upgrade available here, and the only one with a real cost.
	--
	-- The islands are discrete objects floating in open sky with nothing between them, so a far-focus
	-- blur separates the island being filmed from the tower stacked behind it: without it every shot is
	-- uniformly sharp and the tower reads as a flat backdrop.
	--
	-- ⚠ IT IS SKIPPED ON TOUCH DEVICES. DOF is the most expensive of the four post-process effects, and
	-- on a phone it would be the FOURTH running at once, over a camera that is already moving every frame
	-- and streaming a new island in the background -- which is exactly the moment a device has no
	-- headroom left. The cinematic looks slightly flatter on mobile and runs at frame rate, which is the
	-- right trade: nobody notices a missing far-blur, everybody notices a stutter.
	if not USE_DOF then
		st.dof = nil
		return
	end
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "IntroDOF"
	dof.FarIntensity = 0.35
	dof.NearIntensity = 0
	dof.FocusDistance = 260   -- retuned per frame to the island's actual distance (see playShot)
	dof.InFocusRadius = 340
	dof.Parent = Lighting

	st.fx[#st.fx + 1] = dof
	st.dof = dof
end

local function removeGrade()
	for _, e in ipairs(st.fx) do
		pcall(function() e:Destroy() end)
	end
	-- ...and sweep by name as well. The tracked list only knows about effects THIS run created; if an
	-- earlier run left one behind, the loop above would walk straight past it and the player would keep a
	-- stray ColorCorrection clamped over their whole session. Belt and braces, because a leaked grade is
	-- both very visible and very hard for a player to explain.
	sweepGrade()
	st.fx = {}
	st.blur = nil
	st.dof = nil -- destroyed above; clearing it stops a replay writing to a dead instance
end

--======================================================================
-- AUDIO
--======================================================================
-- ⚠ SWAP THESE FOR YOUR OWN IDs IF YOU HAVE THEM -- this table is the only place to edit.
--
-- Each cue is a LIST and the FIRST id is one already proven to load IN THIS PLACE (both are
-- used by EggSystem/PetFollow here). If the first fails we fall through to the next, so one
-- dead asset can't silence a whole cue. That ordering is deliberate: the Dino Realm's
-- signature hit (128842283247970) is not used anywhere in Candy, so it is listed as a
-- fallback rather than the lead -- promote it once you've confirmed it loads here.
local SFX = {
	-- ⭐ THE SIGNATURE HIT. Used exactly TWICE, deliberately:
	--      1. the opening slam onto Bakery Summit
	--      2. the title card landing
	-- Bookending the piece with the same sound is what makes it feel composed. Firing it on
	-- all six cuts would burn it out by the third -- the ear stops hearing a sound it's heard
	-- five times, and then the title has nothing left to land on.
	hit  = { "92880640988467", "128842283247970" },

	-- ⚠ EMPTY ON PURPOSE. This used to be a small tick under each of the middle cuts
	-- (126450028713974) -- it read as a random crackle rather than punctuation, so it was cut.
	-- The cuts are now silent; the signature hit still bookends the piece.
	cut  = {},

	-- layered under the title for body
	-- 112825313814792 was here as a fallback and is REMOVED: this place is not authorised to use it
	--   Failed to load sound rbxassetid://112825313814792: User is not authorized to access Asset
	-- It only ever ran as a fallback so nothing sounded wrong, but it printed that line (plus a "click to
	-- share access" nag) on every intro. A fallback that cannot load is not a fallback.
	boom = { "92880640988467" },

	-- ⚠ EMPTY ON PURPOSE. There is no wind/drone asset in this project. Paste one here and
	-- the intro gains its best layer: a bed that rises in volume and drops in pitch as you
	-- fall, gluing six hard cuts into one piece.
	bed  = {},
}

local loaded: { [string]: boolean } = {}

-- Preload up front so the FIRST cut isn't silent while the asset streams in.
local function preloadSfx()
	local probes = {}
	for _, ids in pairs(SFX) do
		for _, id in ipairs(ids) do
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. id
			s.Parent = SoundService
			probes[#probes + 1] = s
		end
	end
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(probes)
	end)
	for _, s in ipairs(probes) do
		local id = s.SoundId:match("(%d+)")
		if id then loaded[id] = s.IsLoaded end
		s:Destroy()
	end
end

-- Play the first id in a cue that actually loaded. Never errors; warns once if a whole cue is
-- dead, so a silent intro is diagnosable instead of mysterious.
local function sfx(cue: string, vol: number, speed: number?)
	local ids = SFX[cue]
	if not ids then return nil end
	if #ids == 0 then return nil end -- deliberately silent cue -- not a missing asset, don't warn
	for _, id in ipairs(ids) do
		if loaded[id] ~= false then -- unknown (not preloaded yet) is worth a try
			local ok, snd = pcall(function()
				local s = Instance.new("Sound")
				s.SoundId = "rbxassetid://" .. id
				s.Volume = vol
				s.PlaybackSpeed = speed or 1
				s.Parent = SoundService
				s:Play()
				game:GetService("Debris"):AddItem(s, 8)
				return s
			end)
			if ok and snd then return snd end
		end
	end
	warn(("[Intro] sound cue '%s' has no loadable asset -- playing silent. Put a working id in SFX.%s")
		:format(cue, cue))
	return nil
end

-- The ambient bed: a loop that RISES through the descent. Starts thin and distant at the
-- summit, thickens and drops in pitch as you fall. This is what glues six hard cuts into one
-- continuous piece instead of six disconnected clips.
local function startBed(totalTime: number)
	local ids = SFX.bed
	if #ids == 0 then
		print("[Intro] no ambience id configured (SFX.bed is empty) -> playing without the wind bed")
		return function() end
	end
	local s
	for _, id in ipairs(ids) do
		if loaded[id] ~= false then
			local ok, snd = pcall(function()
				local x = Instance.new("Sound")
				x.SoundId = "rbxassetid://" .. id
				x.Looped = true
				x.Volume = 0
				x.PlaybackSpeed = 1.35 -- thin + high up at the summit
				x.Parent = SoundService
				x:Play()
				return x
			end)
			if ok and snd then s = snd; break end
		end
	end
	if not s then return function() end end

	task.spawn(function()
		local t0 = os.clock()
		while s.Parent and not st.skipped do
			local a = math.clamp((os.clock() - t0) / totalTime, 0, 1)
			s.Volume = 0.15 + 0.45 * a          -- swells as you descend
			s.PlaybackSpeed = 1.35 - 0.55 * a   -- drops in pitch = falling
			RunService.RenderStepped:Wait()
		end
	end)

	-- returns a stopper that fades it out rather than cutting it dead
	return function()
		pcall(function()
			TweenService:Create(s, TweenInfo.new(1.2), { Volume = 0 }):Play()
			game:GetService("Debris"):AddItem(s, 1.5)
		end)
	end
end

--======================================================================
-- helpers
--======================================================================

local function hrp(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Hide the player's own body -- the camera flies right past it.
local function setBodyHidden(hide: boolean)
	local char = player.Character
	if not char then return end
	if hide then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then
				st.hidden[d] = d.Transparency
				d.Transparency = 1
			end
		end
	else
		for d, t in pairs(st.hidden) do
			if d.Parent then pcall(function() d.Transparency = t end) end
		end
		st.hidden = {}
	end
end

local function freezeBody(freeze: boolean)
	local h = hrp()
	if h then h.Anchored = freeze end -- an unanchored body 59,000 studs up simply falls
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum.WalkSpeed = freeze and 0 or 16
		hum.JumpPower = freeze and 0 or 50
	end
end

-- HIDE THE WORLD'S OWN UI TOO. ScreenGuis live in PlayerGui, but a BillboardGui is anchored
-- to a PART -- it is not in PlayerGui and the sweep below never touched it. Same principle as
-- the ScreenGui sweep: hide the CLASS, never a hand-written list of names, so it can't rot
-- when a new billboard is added.
--
-- Two things make this more than a one-shot sweep:
--   * StreamingEnabled. Islands stream in WHILE the cinematic plays and their scripts build
--     billboards on arrival (Candy's *_AllInOne quest scripts each build their own HUD when
--     their island loads). A single pass at the start would miss every one of those -- hence
--     the DescendantAdded watcher.
--   * ProximityPrompts render their own world-space label. The body is frozen so nothing can
--     be interacted with anyway; disabling the service is the only way to keep them off screen.
-- SurfaceGuis are deliberately left alone: those are painted onto the scenery (signs, shop
-- boards) and read as part of the world, not as UI over it.
local function setWorldUiHidden(hide: boolean)
	if hide then
		if st.worldConn then return end -- already hidden
		local pgui = player:FindFirstChildOfClass("PlayerGui")
		-- the cinema's gui is the ONE gui allowed to stay up. st.exclude is set by setAllGuis
		-- once it exists; the name check covers the window before that.
		-- ⚠ THIS MUST COVER EVERY GUI THE CINEMATIC BUILDS, NOT JUST THE ONE NAMED "IntroCinema".
		--
		-- THE BUG THIS FIXES (inherited from the Dino version, where it is still live): the TITLE CARD is a
		-- SECOND ScreenGui, named "IntroTitle", created at the very end by showTitleCard(). The old test
		-- only exempted the name "IntroCinema" plus descendants of st.exclude -- and st.exclude points at
		-- the cinema gui, which cinema.destroy() has already destroyed by the time the card appears.
		--
		-- So the card failed BOTH checks. The PlayerGui.DescendantAdded watcher below grabbed it the instant
		-- it was parented, set Enabled = false, and the RenderStepped enforcer held it there. The card then
		-- ran its whole 4.7s sequence -- gradient, title punch, shimmer, fade -- perfectly, and completely
		-- invisibly, before destroying itself. The log said "[Intro] done" with nothing ever on screen.
		--
		-- st.ours is an explicit ownership set, so a third gui added later is one registration away from
		-- being safe instead of silently vanishing the same way.
		local function isCinema(inst: Instance)
			if st.ours[inst] then return true end
			if inst.Name == "IntroCinema" or inst.Name == "IntroTitle" then return true end
			for owned in pairs(st.ours) do
				if owned.Parent and inst:IsDescendantOf(owned) then return true end
			end
			return st.exclude ~= nil and (inst == st.exclude or inst:IsDescendantOf(st.exclude))
		end
		local function grab(d: Instance)
			if isCinema(d) then return end
			if d:IsA("BillboardGui") then
				-- wherever it lives: parts in Workspace, OR PlayerGui with an Adornee --
				-- Candy's NpcGuideArrow parents its arrow to PlayerGui, which a Workspace-only
				-- sweep walks straight past.
				if st.world[d] == nil then st.world[d] = d.Enabled; d.Enabled = false end
			elseif d:IsA("ScreenGui") then
				-- ScreenGuis born DURING the cinematic. StreamingEnabled means island quest
				-- scripts build their HUDs when their island streams in, well after the
				-- one-shot setAllGuis sweep has run.
				if st.guis[d] == nil then st.guis[d] = d.Enabled; d.Enabled = false end
			end
		end
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("BillboardGui") then grab(d) end
		end
		if pgui then -- PlayerGui-parented billboards (ScreenGuis here are setAllGuis's job)
			for _, d in ipairs(pgui:GetDescendants()) do
				if d:IsA("BillboardGui") then grab(d) end
			end
		end
		-- watchers: UI born mid-cinematic, on either side
		-- (defer: a gui is usually parented before its Enabled/adornee are set)
		st.worldConn = Workspace.DescendantAdded:Connect(function(d)
			task.defer(function() if d.Parent then pcall(grab, d) end end)
		end)
		if pgui then
			st.pguiConn = pgui.DescendantAdded:Connect(function(d)
				task.defer(function() if d.Parent then pcall(grab, d) end end)
			end)
		end
		pcall(function()
			st.prompts = ProximityPromptService.Enabled
			ProximityPromptService.Enabled = false
		end)

		-- RE-ASSERT THE HIDE EVERY FRAME. Setting Enabled once is not enough: several scripts
		-- DRIVE Enabled from their own loops and simply set it back -- Candy's NpcGuideArrow
		-- rewrites its arrow's Enabled on a heartbeat, and the ObjectiveHUD/quest HUDs
		-- re-enable themselves on their own proximity loops. Chasing each writer with an
		-- `if _G.introPlaying` guard would mean editing every script that ever drives a GUI
		-- and would rot the moment someone adds another.
		--
		-- RenderStepped is the fix: it is the LAST thing to run before the frame is drawn, so
		-- whatever those loops set earlier in the frame is overwritten before it reaches the screen.
		st.enforce = RunService.RenderStepped:Connect(function()
			for d in pairs(st.world) do
				if d.Parent and d.Enabled then d.Enabled = false end
			end
			for g in pairs(st.guis) do
				if g.Parent and g.Enabled and not isCinema(g) then g.Enabled = false end
			end
		end)
	else
		-- Kill the enforcer FIRST -- restoring while it still runs would just re-hide.
		if st.enforce then st.enforce:Disconnect(); st.enforce = nil end
		if st.worldConn then st.worldConn:Disconnect(); st.worldConn = nil end
		if st.pguiConn then st.pguiConn:Disconnect(); st.pguiConn = nil end
		for d, wasEnabled in pairs(st.world) do
			if d.Parent then pcall(function() d.Enabled = wasEnabled end) end
		end
		st.world = {}
		if st.prompts ~= nil then
			pcall(function() ProximityPromptService.Enabled = st.prompts end)
			st.prompts = nil
		end
	end
end

-- HIDE EVERYTHING. Every ScreenGui in the game, not a hand-written list of names -- a generic
-- sweep can't rot when a GUI is renamed or a new one is added.
local function setAllGuis(on: boolean, exclude: ScreenGui?)
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, on) end)
	if not on then st.exclude = exclude end -- tell the watchers/enforcer which gui is the cinema's
	-- FIRST, both directions. Hiding: the world sweep must not be gated behind the PlayerGui
	-- check below. Restoring: this stops the enforcer before the loop below puts the ScreenGuis
	-- back, so it can't immediately re-hide them.
	setWorldUiHidden(not on)
	if on then st.exclude = nil end
	local pgui = player:FindFirstChildOfClass("PlayerGui")
	if not pgui then return end

	if not on then
		for _, g in ipairs(pgui:GetDescendants()) do
			if g:IsA("ScreenGui") and g ~= exclude then
				st.guis[g] = g.Enabled
				g.Enabled = false
			end
		end
	else
		for g, wasEnabled in pairs(st.guis) do
			if g.Parent then pcall(function() g.Enabled = wasEnabled end) end
		end
		st.guis = {}
	end
end

-- Slot -> the island MODEL's centre and size.
--
-- THE POSITION COMES FROM IslandOrder.SLOT_POS, NOT FROM THE MODEL. With StreamingEnabled a
-- distant island's Model replicates but its PARTS do not, so GetBoundingBox() on it returns
-- the ORIGIN -- which is exactly the state every island is in when the cinematic starts. The
-- Dino version got away with reading the bbox first because it re-read after streaming; here
-- the module already holds the authoritative ladder (it is what IslandLayout moved them to),
-- so we use it for the position and the bbox only for SIZE, which is all it's needed for.
local function slotInfo(slot: number)
	local islandNum = IslandOrder.SLOT_TO_ISLAND[slot]
	local pos = IslandOrder.SLOT_POS[slot]
	if not (islandNum and pos) then return nil, nil end

	local size
	local isl = Workspace:FindFirstChild("island" .. islandNum)
	if isl then
		local ok, _, sz = pcall(function()
			local cf, s = isl:GetBoundingBox()
			return cf, s
		end)
		if ok and sz and sz.Magnitude > 1 then size = sz end
	end
	return pos, size
end

-- PREFETCH. Ask the server to stream an island in WITHOUT moving anything or waiting.
--
-- This is the single biggest pacing fix over the Dino version. There, every shot began with a blocking
-- RequestStreamAroundAsync that could burn up to 3 seconds -- so a "fast, cut-driven" edit actually
-- played as: slam, freeze, whip, freeze, orbit, freeze. The stalls land exactly on the cuts, which is
-- the worst possible place for them, because a cut is a promise that something is about to happen.
--
-- Roblox will happily stream around a point you are not standing on, so the next island can load DURING
-- the current shot -- 1.3-3.6s of cover, which is more than the request usually needs. By the time
-- travelTo() gets there the geometry is already on the client and its wait returns instantly.
local function prefetch(slot: number?)
	if not slot or st.streamed[slot] then return end
	local pos = IslandOrder.SLOT_POS[slot]
	if not pos then return end
	st.streamed[slot] = true
	task.spawn(function()
		pcall(function() player:RequestStreamAroundAsync(pos) end)
	end)
end

-- POINT STREAMING AT AN ISLAND and wait for it to arrive.
--
-- ⚠ THE CHARACTER DOES NOT MOVE. This used to teleport the body up the tower, because StreamingEnabled
-- centres streaming on the character. That is what caused the two things that made the intro unusable:
--
--   * "GAMEPLAY PAUSED" -- Roblox shows that overlay whenever the character is moved outside the region
--     currently streamed in. Six shots meant six teleports, so it kept reappearing over the cinematic.
--   * The stutter -- every teleport forced a synchronous scramble to load an entire island around the
--     body, with physics re-solving the character at its new position, on the frame of a hard cut.
--
-- Instead the SERVER moves the player's ReplicationFocus to an invisible proxy part at the island (see
-- Intro.server.luau). Streaming follows the proxy, the body stays on the spawn brick the whole time, and
-- neither the pause overlay nor the physics churn can happen at all. It also deletes a whole class of
-- failure: there is no longer any way for the cinematic to leave the player stranded up the tower.
local function travelTo(slot: number)
	local pos, size = slotInfo(slot)
	if not pos then return nil, nil end

	pcall(function() IntroFocus:FireServer(pos) end)

	-- Belt and braces: the focus change is what actually loads the island, but this also asks directly and
	-- gives us something to wait ON. Prefetch has usually already satisfied it, so it returns immediately.
	local done = false
	task.spawn(function()
		pcall(function() player:RequestStreamAroundAsync(pos) end)
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 3 do task.wait() end
	st.streamed[slot] = true

	-- WAIT FOR PARTS, not just for the request to return. The request resolving means the server has
	-- sent the region; the model can still be empty for a frame or two after that, and filming an island
	-- that has not finished assembling is the one artefact prefetching alone would not fix. Bounded hard
	-- so a genuinely missing island costs a beat, not the cinematic.
	--
	-- ⚠ THE CHEAP CHECK, DELIBERATELY. The obvious way to write this is to call slotInfo() in the loop
	-- and stop when it returns a size -- but slotInfo() calls Model:GetBoundingBox(), which walks EVERY
	-- descendant of the island and builds a fresh bbox each time. Polling that every frame for a second,
	-- on a model with hundreds of parts, is a visible hitch landing exactly on the cut it was meant to
	-- smooth out. FindFirstChildWhichIsA short-circuits on the first part it finds, and the poll is
	-- throttled to 20Hz besides -- geometry does not arrive fast enough for per-frame checking to see
	-- anything a 50ms poll misses. The one real bbox call happens once, after the wait.
	local isl = Workspace:FindFirstChild("island" .. (IslandOrder.SLOT_TO_ISLAND[slot] or -1))
	if isl and not isl:FindFirstChildWhichIsA("BasePart", true) then
		local t1 = os.clock()
		repeat
			task.wait(0.05)
		until isl:FindFirstChildWhichIsA("BasePart", true) or os.clock() - t1 > 1.0
	end

	-- re-read the SIZE now the parts have arrived (the position was never in doubt)
	local _, size2 = slotInfo(slot)
	return pos, size2 or size
end

--======================================================================
-- HANDHELD + IMPACT SHAKE
--======================================================================
-- A camera on a perfect mathematical path looks like a CAD render. A little continuous drift
-- (as if a human were holding it) plus a sharp decaying jolt on each cut is what makes it feel
-- shot rather than computed.
--
-- Applied as an OFFSET to the composed CFrame, so it never fights the shot's own motion.
local function handheld(cf: CFrame, a: number): CFrame
	local t = os.clock()
	-- slow, low-amplitude drift -- two out-of-phase sines so it never visibly loops
	local dx = math.sin(t * 1.7) * 0.35 + math.sin(t * 0.6) * 0.20
	local dy = math.cos(t * 1.3) * 0.28 + math.sin(t * 0.9) * 0.15
	local roll = math.sin(t * 0.8) * math.rad(0.5)

	-- impact shake: sharp, random, decays fast
	local s = st.shake
	if s > 0.01 then
		dx += (math.random() - 0.5) * s * 3.0
		dy += (math.random() - 0.5) * s * 3.0
		roll += (math.random() - 0.5) * s * math.rad(2.5)
		st.shake = s * 0.86 -- decay
	else
		st.shake = 0
	end

	return cf * CFrame.new(dx, dy, 0) * CFrame.Angles(0, 0, roll)
end

local function playShot(shot, cinema, nextSlot)
	local pos, size = travelTo(shot.slot)
	if not pos or st.skipped then return end

	local cam = Workspace.CurrentCamera
	if not cam then return end

	-- Start the NEXT island loading under this shot, so its travelTo() does not stall on the cut.
	prefetch(nextSlot)

	-- NOTE: the cinematic deliberately does NOT tell SkyByAltitude the height it is filming. An earlier
	-- pass did (so the summit shots rendered under the dark high-altitude sky), and the owner's verdict
	-- was clear: the intro should stay BRIGHT. The character is standing on island 1 throughout, so the
	-- sky sampler keeps reading ground level and every shot plays in full candy daylight.

	local r = math.max(90, (size and math.max(size.X, size.Z) or 200) * 0.75)
	cinema.setLabel(IslandOrder.NAMES[shot.slot] or "", shot.slot)

	-- THE FRONT OF THE ISLAND. The first cut aimed the punch at a fixed world angle and started the
	-- orbits and whips at math.random(0,360) -- so roughly half of all runs filmed the BACKS of islands.
	-- No island carries an authored front vector, but they all share one by construction: the tower
	-- zig-zags around a central axis, and each island's content faces INWARD toward it -- that is the
	-- side you fly up along, arrive at, and land on. So "front" = the horizontal direction from the
	-- island toward the tower axis, and every shot now frames from that side. (Slot 1 sits ON the axis;
	-- its shot is the crane, which aims at the spawn and never uses this.)
	local front
	do
		local h = Vector3.new(-pos.X, 0, -pos.Z)
		front = (h.Magnitude > 1) and h.Unit or Vector3.new(0, 0, -1)
	end
	local frontAng = math.atan2(front.Z, front.X) -- the same direction, as an orbit angle

	-- THE HANDOFF POINT. travelTo has returned, so the island is streamed in and the very next thing that
	-- happens is the shot loop driving the camera. Dropping the pre-roll cover here -- and not a moment
	-- earlier -- means the black lifts straight onto a composed frame, never onto a half-loaded island or
	-- the parked spawn view. A cut, not a fade: the opening beat is a slam.
	coverCut()

	local t0 = os.clock()
	local last = t0
	local function frame(): number?
		if st.skipped then return nil end
		local now = os.clock()
		local dt = now - last
		last = now
		local a = (now - t0) / shot.t
		if a >= 1 then return nil end
		cam.FieldOfView = shot.fov0 + (shot.fov1 - shot.fov0) * a
		-- the cut's blur punch decays away across the opening beat of every shot.
		-- NOTE: dt from the clock, NOT RenderStepped:Wait() -- the shot loops already wait once
		-- per frame, and waiting again in here would halve their framerate.
		if st.blur and st.blur.Size > 0 then
			st.blur.Size = math.max(0, st.blur.Size - 90 * dt)
		end
		-- Keep the subject in focus as the camera closes on it. Driven off the LIVE distance rather
		-- than a per-shot constant, because a punch-in halves its own distance across the shot -- a
		-- fixed focus would drift out of focus exactly as it arrives.
		if st.dof then
			local d = (cam.CFrame.Position - pos).Magnitude
			st.dof.FocusDistance = d
			st.dof.InFocusRadius = math.max(220, r * 2.0)
		end
		return a
	end

	if shot.move == "punch" then
		-- punch in along the FRONT, not a fixed world angle that faced whatever it happened to face
		local from = pos + front * (r * 2.2) + Vector3.new(0, r * 1.2, 0)
		local to   = pos + front * (r * 0.7) + Vector3.new(0, r * 0.30, 0)
		while true do
			local a = frame(); if not a then break end
			local k = TweenService:GetValue(a, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
			cam.CFrame = handheld(CFrame.lookAt(from:Lerp(to, k), pos), a)
			RunService.RenderStepped:Wait()
		end

	elseif shot.move == "orbit" then
		-- the 80° sweep is CENTRED on the front: it starts 40° to one side of it and ends 40° past,
		-- so the middle of the shot -- where the eye settles -- is the island's face, dead on
		local a0, sweep = frontAng - math.rad(40), math.rad(80)
		while true do
			local a = frame(); if not a then break end
			local e = TweenService:GetValue(a, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local ang = a0 + sweep * e
			local p = pos + Vector3.new(math.cos(ang) * r * 1.15, r * (0.60 - 0.20 * e), math.sin(ang) * r * 1.15)
			cam.CFrame = handheld(CFrame.lookAt(p, pos), a)
			RunService.RenderStepped:Wait()
		end

	elseif shot.move == "whip" then
		-- rip across the FRONT face: the path runs perpendicular to the front direction, pushed out
		-- toward the front so the island's face (not its back) is what streaks past the lens
		local perp = Vector3.new(-front.Z, 0, front.X) * r * 1.6
		local out  = front * (r * 0.9)
		local from = pos + out + perp + Vector3.new(0, r * 0.18, 0)
		local to   = pos + out - perp + Vector3.new(0, r * 0.26, 0)
		while true do
			local a = frame(); if not a then break end
			cam.CFrame = handheld(CFrame.lookAt(from:Lerp(to, a), pos), a) -- linear = it really rips past
			RunService.RenderStepped:Wait()
		end

	elseif shot.move == "crane" then
		-- The landing: fall out of the sky and settle exactly where the normal camera sits.
		--
		-- The character is the truth here, read LIVE. It never moved during the cinematic, and by the time
		-- this last shot runs (~7s in) SpawnOnIsland1 has long finished placing it on the pad -- so its
		-- current position is exactly where the player is about to be handed control. st.homeCF is a
		-- snapshot from before that placement may have happened, so it is only the fallback.
		local liveH = hrp()
		local land = (liveH and liveH.Position)
			or (st.homeCF and st.homeCF.Position)
			or (pos + Vector3.new(0, 10, 0))
		local look = st.homeCF and st.homeCF.LookVector or Vector3.new(0, 0, -1)
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = (flat.Magnitude > 0.05) and flat.Unit or Vector3.new(0, 0, -1)
		local from = land + Vector3.new(0, r * 1.5, 0) - flat * r * 1.1
		local to   = land - flat * 16 + Vector3.new(0, 6, 0)
		while true do
			local a = frame(); if not a then break end
			local k = TweenService:GetValue(a, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
			local focus = land + Vector3.new(0, 2 - 0.5 * k, 0)
			cam.CFrame = handheld(CFrame.lookAt(from:Lerp(to, k), focus), a)
			RunService.RenderStepped:Wait()
		end
	end
end

--======================================================================
-- CINEMA UI: island chip + skip hint + the CUT flash.
-- (No buttons, no HUD -- this is the ONLY thing on screen besides the islands.)
--
-- NO LETTERBOX, deliberately: on a phone two black bars eat a fifth of the screen, and the
-- shot is the point. The chip and the skip hint are anchored to the screen edges.
--======================================================================
local function buildCinemaUI()
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "IntroCinema"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 900
	st.ours[g] = true -- claim it BEFORE parenting: DescendantAdded fires the moment the line below runs
	g.Parent = pgui

	local chip = Instance.new("TextLabel")
	chip.AnchorPoint = Vector2.new(0, 1)
	chip.Position = UDim2.new(0, 42, 1, -66)
	chip.Size = UDim2.fromOffset(460, 38)
	chip.BackgroundTransparency = 1
	chip.Font = Enum.Font.FredokaOne
	chip.TextScaled = true
	chip.TextColor3 = Color3.fromRGB(255, 255, 255)
	chip.TextStrokeColor3 = Color3.new(0, 0, 0)
	chip.TextStrokeTransparency = 0.15
	chip.TextXAlignment = Enum.TextXAlignment.Left
	chip.Text = ""
	chip.TextTransparency = 1
	chip.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 30; c.Parent = chip end

	-- THE ALTITUDE READOUT, under the island name.
	--
	-- This game is ABOUT height -- the whole loop is buying enough gas to climb one more gap -- and the
	-- cinematic has the tower's real numbers sitting right there in IslandOrder. Counting them down as
	-- the camera falls, 59,388 studs to 150, tells the player how far the climb goes in a way no amount
	-- of pretty camera work can. It also silently answers "how big is this game?" in the first ten
	-- seconds, which is the question a title screen exists to answer.
	--
	-- It EASES toward the target rather than snapping, so the number visibly tumbles on every cut
	-- instead of just changing -- a rolling counter reads as descent; a static one reads as a caption.
	local alt = Instance.new("TextLabel")
	alt.AnchorPoint = Vector2.new(0, 1)
	alt.Position = UDim2.new(0, 44, 1, -40)
	alt.Size = UDim2.fromOffset(300, 24)
	alt.BackgroundTransparency = 1
	alt.Font = Enum.Font.GothamBold
	alt.TextScaled = true
	alt.TextColor3 = Color3.fromRGB(255, 214, 236)
	alt.TextStrokeColor3 = Color3.new(0, 0, 0)
	alt.TextStrokeTransparency = 0.35
	alt.TextXAlignment = Enum.TextXAlignment.Left
	alt.Text = ""
	alt.TextTransparency = 1
	alt.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 19; c.Parent = alt end

	local skip = Instance.new("TextLabel")
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -42, 1, -66)
	skip.Size = UDim2.fromOffset(260, 26)
	skip.BackgroundTransparency = 1
	skip.Font = Enum.Font.GothamBold
	skip.TextScaled = true
	skip.TextColor3 = Color3.fromRGB(215, 215, 215)
	skip.TextTransparency = 0.3
	skip.TextXAlignment = Enum.TextXAlignment.Right
	skip.Text = "press any key / tap to skip"
	skip.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = skip end

	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1); flash.BorderSizePixel = 0
	flash.BackgroundColor3 = Color3.new(0, 0, 0); flash.BackgroundTransparency = 1
	flash.ZIndex = 5; flash.Parent = g

	-- the rolling altitude number: `shown` chases `target` every frame
	local shown, target, altLive = nil, nil, false
	local function commas(n: number): string
		local s = tostring(math.floor(n + 0.5))
		local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		return (out:gsub("^,", ""))
	end
	-- THE ROLLING COUNTER, written only when the DISPLAYED NUMBER ACTUALLY CHANGES.
	--
	-- Setting .Text on a TextScaled label makes Roblox re-fit the string to the box, and doing that every
	-- frame for the whole cinematic is real work for no visual gain -- the digits can only change so fast
	-- before they are unreadable anyway. So the ease still runs per frame (it has to, or the motion
	-- stutters) but the label is only touched when the rounded value moves, and the loop goes fully idle
	-- once the number has settled on its target -- which is most of every shot.
	local lastWritten = nil
	task.spawn(function()
		while g.Parent do
			RunService.RenderStepped:Wait()
			if altLive and target and shown and shown ~= target then
				-- exponential ease: fast at first, settles just as the next cut lands
				shown += (target - shown) * 0.12
				if math.abs(target - shown) < 1 then shown = target end
				local rounded = math.floor(shown + 0.5)
				if rounded ~= lastWritten then
					lastWritten = rounded
					alt.Text = commas(rounded) .. " STUDS UP"
				end
			end
		end
	end)

	local api = {}
	function api.setLabel(text: string, slot: number?)
		chip.Text = text
		chip.TextTransparency = 1
		TweenService:Create(chip, TweenInfo.new(0.22), { TextTransparency = 0 }):Play()

		local pos = slot and IslandOrder.SLOT_POS[slot]
		if pos then
			target = pos.Y
			if not altLive then
				-- first shot: start the counter AT the summit rather than rolling up to it from zero
				shown = pos.Y
				altLive = true
				lastWritten = math.floor(pos.Y + 0.5) -- so the loop doesn't rewrite the same string next frame
				alt.Text = commas(pos.Y) .. " STUDS UP"
				TweenService:Create(alt, TweenInfo.new(0.5), { TextTransparency = 0.1 }):Play()
			end
		end
	end
	-- THE CUT: a black snap + a blur punch + a jolt of camera shake, all on the same frame.
	-- One black frame alone reads as a glitch; the three together read as an EDIT. The blur
	-- decays away over the opening beat of the next shot (see playShot's frame()), so every
	-- cut lands like an impact instead of a fade.
	-- The cuts are silent now -- the per-cut tick read as a random crackle, so it was removed
	-- (see SFX.cut). `n` is kept in the signature because the shot list passes it.
	function api.cut(_n: number)
		flash.BackgroundTransparency = 0
		TweenService:Create(flash, TweenInfo.new(0.16), { BackgroundTransparency = 1 }):Play()
		if st.blur then st.blur.Size = 22 end
		st.shake = 1.0
	end
	function api.destroy() pcall(function() g:Destroy() end) end
	api.gui = g
	return api
end

--======================================================================
-- THE TITLE CARD -- full-screen gradient wash, big FredokaOne title punched in over it,
-- subtitle beneath, hold, fade away. Bubblegum palette instead of the Dino jungle/amber.
--======================================================================
local function showTitleCard()
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "IntroTitle"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 950
	st.ours[g] = true -- claim it BEFORE parenting, or the hide-sweep disables the card on the next frame
	g.Parent = pgui

	-- KEEP THE CAMERA ALIVE UNDER THE CARD.
	-- The shot loops have finished, so nothing is driving cam.CFrame any more -- without this
	-- the world behind the title is a dead, frozen frame (and the title's impact shake would do
	-- literally nothing, since shake is applied inside handheld()). A slow drift + gentle
	-- push-in keeps it breathing.
	task.spawn(function()
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local base = cam.CFrame
		local t0, last = os.clock(), os.clock()
		while g.Parent and not st.skipped do
			local now = os.clock()
			local dt = now - last
			last = now
			local a = math.min(1, (now - t0) / 5)
			-- creep forward very slightly -- a static frame reads as a screenshot
			local push = base * CFrame.new(0, 0, -3 * a)
			cam.CFrame = handheld(push, a)
			-- decay the title's blur punch. The shot loops did this, but they've finished by
			-- now -- without it the blur from the title hit would just stay on screen.
			if st.blur and st.blur.Size > 0 then
				st.blur.Size = math.max(0, st.blur.Size - 40 * dt)
			end
			RunService.RenderStepped:Wait()
		end
	end)

	-- CUT TO THE CARD. It arrives OPAQUE on its first frame.
	--
	-- This used to fade up from transparent over 0.7s, which meant the last thing before the title was
	-- three quarters of a second of the crane shot sitting still at the spawn -- indistinguishable from
	-- ordinary gameplay, and read as the game starting before the card interrupted it again. Worse, it was
	-- 0.7s of dead time on the end of a cinematic that is otherwise built entirely out of hard cuts.
	--
	-- Cutting fixes both: the descent ends and the title is simply THERE, which is what every one of the
	-- five cuts before it has trained the player to expect.
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1); bg.BorderSizePixel = 0
	bg.BackgroundColor3 = Color3.fromRGB(14, 8, 14); bg.BackgroundTransparency = 0
	bg.Parent = g

	-- bubblegum gradient wash: raspberry at the summit down to mint at the ground
	bg.BackgroundColor3 = Color3.fromRGB(255, 240, 248)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 122, 176)), -- raspberry (the summit)
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 214, 232)), -- cotton-candy haze
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(150, 230, 210)), -- mint (the ground)
	})
	grad.Parent = bg

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.44)
	title.Size = UDim2.fromOffset(980, 120)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(150, 30, 88)
	title.TextTransparency = 1
	title.Text = "\xF0\x9F\x8D\xAC  FART TO FLOAT"
	title.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 88; c.Parent = title end
	local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(255, 255, 255); ts.Thickness = 5; ts.Parent = title

	local sub = Instance.new("TextLabel")
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.Position = UDim2.fromScale(0.5, 0.57)
	sub.Size = UDim2.fromOffset(700, 52)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.FredokaOne
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(40, 120, 104)
	sub.TextTransparency = 1
	sub.Text = "CANDY REALM"
	sub.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 40; c.Parent = sub end
	local ss = Instance.new("UIStroke"); ss.Color = Color3.fromRGB(255, 255, 255); ss.Thickness = 3; ss.Parent = sub

	-- tagline, under the subtitle. Island count comes from IslandOrder so it can't go stale if
	-- the tower gains or loses an island.
	local tag = Instance.new("TextLabel")
	tag.AnchorPoint = Vector2.new(0.5, 0.5)
	tag.Position = UDim2.fromScale(0.5, 0.655)
	tag.Size = UDim2.fromOffset(640, 32)
	tag.BackgroundTransparency = 1
	tag.Font = Enum.Font.GothamBold
	tag.TextScaled = true
	tag.TextColor3 = Color3.fromRGB(120, 60, 92)
	tag.TextTransparency = 1
	tag.Text = ("%d ISLANDS.  ONE CLIMB."):format(IslandOrder.COUNT or 11)
	tag.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 22; c.Parent = tag end

	--======================================================================
	-- ⭐ THE TITLE LANDING -- the signature hit's second and last appearance.
	--======================================================================
	-- LAYERED, not a single copy. Three passes of the same asset at different pitches and
	-- offsets is how you make one sound feel like a wall:
	--   * a deep pass (0.72) for weight -- it's what you feel
	--   * the hit at full pitch for the attack -- it's what you hear
	--   * a bright pass a beat later for shine -- it's what makes it sparkle
	-- One thin copy just goes "tick".
	title.Size = UDim2.fromOffset(1240, 152)
	sfx("hit", 1.0, 0.72)                                     -- weight
	sfx("hit", 0.75, 1.0)                                     -- attack
	sfx("boom", 0.6, 0.9)                                     -- tail / body
	task.delay(0.12, function() sfx("hit", 0.4, 1.5) end)     -- shine, a beat behind
	st.shake = 1.8          -- the card lands HARD
	if st.blur then st.blur.Size = 26 end
	TweenService:Create(title, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextTransparency = 0, Size = UDim2.fromOffset(980, 120) }):Play()
	task.wait(0.28)
	TweenService:Create(sub, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	task.wait(0.22)
	TweenService:Create(tag, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()

	-- SHIMMER: a bright band swept across the title. A UIGradient's Offset animates for free
	-- and gives the logo that "gloss" flick real title cards have. Applied to the STROKE so the
	-- letterforms keep their solid fill.
	task.spawn(function()
		local shim = Instance.new("UIGradient")
		shim.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.42, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 236, 246)), -- the highlight band
			ColorSequenceKeypoint.new(0.58, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255, 255, 255)),
		})
		shim.Parent = ts
		for _ = 1, 2 do
			shim.Offset = Vector2.new(-1, 0)
			local t0 = os.clock()
			while os.clock() - t0 < 0.85 do
				local a = (os.clock() - t0) / 0.85
				shim.Offset = Vector2.new(-1 + 2 * a, 0)
				RunService.RenderStepped:Wait()
			end
			task.wait(0.5)
		end
		pcall(function() shim:Destroy() end)
	end)

	task.wait(2.4)
	TweenService:Create(tag, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()

	-- fade the whole card away to reveal the game
	TweenService:Create(title, TweenInfo.new(0.7), { TextTransparency = 1 }):Play()
	TweenService:Create(sub,   TweenInfo.new(0.7), { TextTransparency = 1 }):Play()
	TweenService:Create(ts,    TweenInfo.new(0.7), { Transparency = 1 }):Play()
	TweenService:Create(ss,    TweenInfo.new(0.7), { Transparency = 1 }):Play()
	TweenService:Create(bg,    TweenInfo.new(1.0), { BackgroundTransparency = 1 }):Play()
	task.wait(1.1)
	pcall(function() g:Destroy() end)
end

--======================================================================
-- MAIN
--======================================================================
local function restore()
	-- ALWAYS runs -- on finish, on skip, on error. A player left invisible and anchored 59,000
	-- studs in the air is the worst possible failure here, so this cannot be skipped by any path.
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = DEFAULT_FOV
	end
	-- ⚠ DELIBERATELY DOES NOT MOVE THE CHARACTER ANY MORE.
	--
	-- The cinematic no longer carries the body up the tower (travelTo moves the streaming focus instead),
	-- so the player has been standing on the spawn brick throughout and there is nothing to put back.
	-- Re-asserting a stored CFrame here would be actively harmful now: it would snap them back to wherever
	-- they happened to be when the intro STARTED, undoing anything that legitimately moved them since --
	-- SpawnOnIsland1 finishing its pad placement, most obviously.
	--
	-- Hand streaming back to the character. The server clears this on IntroDone too, plus a 90s timer and
	-- PlayerRemoving; this is just the fastest of the three.
	pcall(function() IntroFocus:FireServer(nil) end)
	freezeBody(false)
	setBodyHidden(false)
	setAllGuis(true)
	removeGrade() -- never leave a ColorCorrection/Bloom/Blur clamped over the session
	st.shake = 0
	_G.introPlaying = false
	-- LAST-RESORT COVER RELEASE. coverCut() normally fires the moment shot one starts, but if the
	-- cinematic errored or was skipped BEFORE it got there, nothing has released it and the player would
	-- sit on black until the 8s backstop. restore() runs on every exit path, so this cannot be missed.
	-- It is idempotent -- after a normal run the cover is already gone and this does nothing.
	coverFade()
	-- the server clears its own "IntroPlaying" attribute when it receives IntroDone
end

local function playIntro()
	if st.running then return end
	st.running = true
	st.skipped = false
	-- Fresh prefetch bookkeeping per run. Streaming is not permanent -- an island loaded during the first
	-- play can be unloaded again long before a replay, so remembering "already streamed" across runs would
	-- skip the request for geometry that is no longer there and film empty sky.
	st.streamed = {}
	st.ours = {} -- last run's guis are destroyed; holding references would leak and slow isCinema's scan

	local h = hrp()
	if not h then st.running = false; return end
	st.homeCF = h.CFrame

	-- NOTE the "IntroPlaying" ATTRIBUTE is deliberately NOT set here -- a client-set attribute
	-- does not replicate to the server, so FlightEconomy would never see it. The SERVER sets it
	-- (Intro.server.luau) before firing IntroPlay and clears it on IntroDone. Setting it here
	-- too would just be a lie that looks like a guard.
	_G.introPlaying = true

	-- HIDE THE WORLD'S UI IMMEDIATELY -- before the cinema is even built. The full setAllGuis()
	-- sweep has to wait for cinema.gui (it needs it as the exclusion), but the world billboards
	-- and prompts have no such dependency, and they are the ones the camera flies straight past.
	-- Idempotent, so the setAllGuis call below is a no-op for this half.
	setWorldUiHidden(true)

	local cinema = buildCinemaUI()

	-- SKIP -- but not for the first moment.
	--
	-- Without the grace window the intro skips ITSELF instantly: the listener arms before the
	-- first frame and catches the very click that focuses the game window (in Studio, the click
	-- into the viewport; in a browser, the click that gives the canvas focus). Every player
	-- would have "skipped" an intro they never saw. Arm it only once the cinematic is up.
	local SKIP_GRACE = 1.25
	local armAt = os.clock() + SKIP_GRACE

	local skipConn
	skipConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if os.clock() < armAt then return end
		-- only real intent: a key, a click, or a tap
		local t = input.UserInputType
		if t == Enum.UserInputType.Keyboard
			or t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.MouseButton2
			or t == Enum.UserInputType.Touch
			or t == Enum.UserInputType.Gamepad1 then
			st.skipped = true
		end
	end)

	-- how long the descent runs, so the wind bed can ramp across exactly that
	local totalTime = 0
	for _, s in ipairs(SHOTS) do totalTime += s.t end

	local stopBed = function() end

	local ok, err = pcall(function()
		-- START THE SUMMIT LOADING FIRST, BEFORE ANY SETUP WORK.
		--
		-- Every other shot is covered by the 1.0-2.4s shot before it, but shot ONE had nothing in front of
		-- it -- so the only remaining stall in the cinematic sat at the very start, which is the worst
		-- possible place: a frozen screen in the silence right before the opening slam.
		--
		-- Everything below this line (hiding the GUI, building the post-process grade, and especially
		-- preloadSfx, which yields on PreloadAsync) is setup that takes real time and needs no geometry.
		-- Running it AFTER the request turns dead waiting into free cover.
		prefetch(SHOTS[1] and SHOTS[1].slot)

		setAllGuis(false, cinema.gui) -- hide EVERY other ScreenGui + the CoreGui
		setBodyHidden(true)
		freezeBody(true)
		addGrade()                    -- contrast / saturation / bloom / blur
		preloadSfx()                  -- so the FIRST cut isn't silent while it streams
		stopBed = startBed(totalTime) -- rising bed under the whole descent

		local cam = Workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable

		for i, shot in ipairs(SHOTS) do
			if st.skipped then break end
			if i == 1 then
				-- ⭐ THE OPENING SLAM. The signature hit, full weight, landing on the summit as
				-- the camera punches in. This is the first thing the player ever hears.
				sfx("hit", 1.0, 1.0)
				st.shake = 1.6
				if st.blur then st.blur.Size = 30 end
			else
				cinema.cut(i - 1) -- HARD CUT between beats, pitch rising each time
			end
			local nxt = SHOTS[i + 1]
			playShot(shot, cinema, nxt and nxt.slot or nil)
		end

		if not st.skipped then
			cinema.destroy()
			showTitleCard()
		end
	end)

	if skipConn then skipConn:Disconnect() end
	pcall(stopBed) -- fade the bed out rather than cutting it dead
	cinema.destroy()
	restore()

	if not ok then
		warn("[Intro] cinematic errored (player restored safely): " .. tostring(err))
	end

	pcall(function() IntroDone:FireServer() end)
	st.running = false
	print("[Intro] done" .. (st.skipped and " (skipped)" or ""))
end

IntroPlay.OnClientEvent:Connect(function()
	task.spawn(playIntro)
end)

print("[Intro] client ready -- waiting for the first-join cinematic")
