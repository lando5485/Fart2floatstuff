--======================================================================
-- Intro.server.luau  (ServerScriptService.Intro)  -- CandyRealm
--======================================================================
-- Owns "should this player get the intro?" and tells the client when to play it.
-- Ported from the Dino Realm's Intro.server.luau, with ONE deliberate difference (below).
--======================================================================
-- TWO WAYS IN, GATED DIFFERENTLY.
--======================================================================
--
-- DIRECT JOIN (opened the Candy Realm from the Roblox site)
--   FIRST JOIN ONLY -- the "seen it" flag is persisted in a DataStore, so a returning player doesn't sit
--   through the cinematic every single time. Wait for the character, let the HUD settle, fire IntroPlay.
--
--   ⚠ ALWAYS_REPLAY (below) is currently TRUE, which ignores that flag and replays the intro on every join
--   for everyone -- you are testing. Set it back to false before launch.
--
-- PORTAL ARRIVAL (teleported in from another realm)
--   ALWAYS PLAYS. No DataStore gate at all -- and that is deliberate, for the reason the Dino Realm learned
--   the hard way: in Studio DataStores are blocked, hasSeen() always fails and the intro always plays, so
--   a gate looks fine in testing and then silently swallows the intro in the published game for anyone
--   flagged as seen in an earlier session. Coming through a portal is a STORY BEAT, not onboarding.
--
--   It also can't just fire on a timer, because a portal arrival lands on a BLACK screen holding the
--   "SOMEWHERE SWEETER" card (ArrivalCinematic.client.luau). Starting the tower descent underneath that
--   black means two cinematics fighting -- they both hide every ScreenGui, both seize the CoreGui, and both
--   anchor the HumanoidRootPart. So we WAIT, and the arrival hands off (IntroRequest) the moment its card
--   is done. The intro's opening slam onto Bakery Summit becomes the cut out of the black.
--======================================================================

-- The altitude that counts as "back down at the spawn island" -- halfway between slot 1 and
-- slot 2, so it can never drift above an island as the tower is re-spaced.
local BOTTOM_Y do
	local ok, IslandOrder = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("IslandOrder"))
	end)
	if ok and IslandOrder and IslandOrder.SLOT_POS[1] and IslandOrder.SLOT_POS[2] then
		BOTTOM_Y = (IslandOrder.SLOT_POS[1].Y + IslandOrder.SLOT_POS[2].Y) / 2
	else
		BOTTOM_Y = 465 -- the midpoint for the shipped ladder (150 / 780)
	end
end

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local STORE_NAME = "CandyRealmIntro_v1"

-- ⚠ TESTING: play the intro on EVERY join, for everyone, as if they were a brand new player.
--
-- FLIP THIS TO false BEFORE LAUNCH. With it true, a returning player sits through the full cinematic every
-- single time they join -- exactly what you want while iterating, exactly what you don't want shipped.
--
-- It only affects DIRECT joins. Portal arrivals ignore it and always play the intro regardless.
local ALWAYS_REPLAY = true

local store
pcall(function() store = DataStoreService:GetDataStore(STORE_NAME) end)

local function ev(name: string): RemoteEvent
	local e = ReplicatedStorage:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = ReplicatedStorage
	end
	return e
end

local IntroPlay    = ev("IntroPlay")    -- s->c: play the intro now
local IntroDone    = ev("IntroDone")    -- c->s: the player finished (or skipped) it
local IntroRequest = ev("IntroRequest") -- c->s: the arrival cinematic is done with its card -> hand off
local IntroFocus   = ev("IntroFocus")   -- c->s: (Vector3|nil) point streaming at this island, or restore
local IntroArm     = ev("IntroArm")     -- s->c: (bool) "an intro IS coming, hold your black" / "it is not, let them in"

-- ============================================================================================================
-- STREAMING FOCUS -- why the cinematic no longer teleports the character
-- ============================================================================================================
-- StreamingEnabled loads geometry around the CHARACTER, so to film an island 59,000 studs up, the first
-- version carried the body there. That is what produced BOTH of the symptoms:
--
--   * "GAMEPLAY PAUSED" -- Roblox puts that overlay up whenever the character is moved outside the region
--     that is currently streamed in. Six shots meant six teleports, so it appeared over and over.
--   * The stutter -- each teleport forced a synchronous scramble to load a whole island around the body,
--     while physics re-solved the character at its new position.
--
-- ReplicationFocus fixes it at the root: the streaming CENTRE is moved to an invisible anchored proxy part
-- while the character never leaves the spawn. No teleport means no pause overlay, no physics churn, and the
-- character cannot be left stranded up the tower if anything goes wrong. (This is the same approach the
-- Space Realm's intro uses; Candy was carrying the body only because the Dino version it was ported from
-- does.) It also makes the whole "put them back on the spawn brick afterwards" problem disappear -- they
-- were standing on it the entire time.
local focusParts  = {} -- [player] = Part (the streaming-centre proxy)
local focusTimers = {} -- [player] = thread (auto-restore backstop)

local function clearFocus(player)
	pcall(function() player.ReplicationFocus = nil end)
	local fp = focusParts[player]
	if fp then
		pcall(function() fp:Destroy() end)
		focusParts[player] = nil
	end
	local t = focusTimers[player]
	if t then
		pcall(function() task.cancel(t) end)
		focusTimers[player] = nil
	end
end

IntroFocus.OnServerEvent:Connect(function(player, pos)
	if typeof(pos) ~= "Vector3" then
		clearFocus(player)
		return
	end
	local fp = focusParts[player]
	if not (fp and fp.Parent) then
		fp = Instance.new("Part")
		fp.Name = "IntroFocus_" .. player.Name
		fp.Size = Vector3.new(2, 2, 2)
		fp.Anchored = true
		fp.CanCollide = false
		fp.CanQuery = false
		fp.CanTouch = false
		fp.Transparency = 1
		fp.Parent = Workspace
		focusParts[player] = fp
	end
	fp.Position = pos
	pcall(function() player.ReplicationFocus = fp end)

	-- THREE backstops guarantee normal streaming comes back: the client's own clear at the end of the
	-- cinematic, this timer (for a crash or disconnect mid-intro), and PlayerRemoving. A player left with
	-- streaming pinned to the summit would see an empty world around themselves for the rest of the session,
	-- so it is worth all three. Each new focus resets the timer.
	if focusTimers[player] then
		pcall(function() task.cancel(focusTimers[player]) end)
	end
	focusTimers[player] = task.delay(90, function()
		focusTimers[player] = nil
		clearFocus(player)
		warn(("[Intro] streaming focus auto-restored for %s (client never cleared)"):format(player.Name))
	end)
end)

-- The handoff lives on the CLIENT, so it can fail in ways we don't control (the script errored, an
-- exploiter stripped it). If the arrival never hands off, start the intro anyway rather than leaving the
-- player stranded on a black screen with no opening at all.
local PORTAL_HANDOFF_TIMEOUT = 20

-- A load FAILURE is treated as "not seen". Better to occasionally replay the intro than to silently swallow
-- it for someone whose data didn't load. (Only the DIRECT JOIN path consults this.)
local function hasSeen(player: Player): boolean
	if not store then return false end
	local ok, seen = pcall(function()
		return store:GetAsync("u_" .. player.UserId)
	end)
	if not ok then return false end
	return seen == true
end

local function markSeen(player: Player)
	if not store then return end
	pcall(function()
		store:SetAsync("u_" .. player.UserId, true)
	end)
end

-- Any TeleportData at all means they came from inside the universe -- the same test RealmServer uses for its
-- entry guard, and for the same reason: TeleportData can only be set by a sending SERVER, so a pasted link
-- cannot fake it. Keying on a specific flag would break the moment another realm starts sending players here.
local function arrivedViaPortal(player: Player): boolean
	local ok, jd = pcall(function() return player:GetJoinData() end)
	if not ok then return false end
	return type(jd and jd.TeleportData) == "table"
end

local playing         = {} -- [player] = true once fired, so a duplicate request can't double-fire it
local awaitingHandoff = {} -- [player] = true while a portal arrival's client decides when to start
local requested       = {} -- [player] = true if IntroRequest arrived (possibly BEFORE we armed -- see below)

local function fireIntro(player: Player)
	if playing[player] or not player.Parent then return end
	playing[player] = true

	-- THE SERVER OWNS THIS FLAG. It must be set here, not on the client.
	--
	-- A client-set player attribute DOES NOT REPLICATE TO THE SERVER. FlightEconomy's climb tracker
	-- (which polls every tick and skips while IntroPlaying is set) is server-side, so a client-set flag
	-- would be invisible to it and the intro's flight up the tower would register as real progress --
	-- handing a brand-new player HighestSlot 11 and the whole progression bar during the cinematic.
	player:SetAttribute("IntroPlaying", true)

	print(("[Intro] playing the intro for %s"):format(player.Name))
	IntroPlay:FireClient(player)

	-- Safety net: never leave the flag stuck on. If the client dies, disconnects, or errors mid-cinematic
	-- without sending IntroDone, climb progress would be frozen for the rest of their session.
	task.delay(60, function()
		if player.Parent and player:GetAttribute("IntroPlaying") then
			warn(("[Intro] %s never reported the intro finishing -> clearing IntroPlaying"):format(player.Name))
			player:SetAttribute("IntroPlaying", false)
		end
	end)
end

-- The arrival cinematic has finished its card and is ready to be cut out of. Go.
--
-- REMEMBER THE REQUEST EVEN IF WE AREN'T ARMED YET. The client can genuinely beat us here: it fires a few
-- seconds after its character exists, while this script is still waiting on CharacterAdded / WaitForChild.
-- Dropping an early request (which is what an `if not awaitingHandoff then return end` alone would do)
-- means the intro doesn't start on the handoff -- it ambushes the player 20 seconds later off the fallback
-- timer, long after they've been let into the world.
IntroRequest.OnServerEvent:Connect(function(player)
	requested[player] = true
	if not awaitingHandoff[player] then return end -- not armed yet (or not a portal arrival) -- handled below
	awaitingHandoff[player] = nil
	fireIntro(player)
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		-- wait for the character, so the client has something to point the camera at
		local char = player.Character or player.CharacterAdded:Wait()
		if not char then return end
		char:WaitForChild("HumanoidRootPart", 15)
		if not player.Parent then return end

		-- ARM THE CLIENT'S BLACK COVER IMMEDIATELY, BEFORE ANY OF THE WORK BELOW.
		--
		-- There is a real gap between a player's world appearing and this script firing IntroPlay -- the
		-- character has to replicate, SpawnOnIsland1 has to place them, and on a direct join hasSeen() is a
		-- DataStore round trip that can take seconds under live load. Measured in Studio it was ~3.4s of the
		-- player simply standing on island 1 looking around, and then the camera was yanked away for a
		-- cinematic. That reads as a bug, not an opening.
		--
		-- So we say "hold" the moment we know there is a character, and only release it if we later decide
		-- not to play. Saying HOLD first and retracting is the right way round: the cost of holding a black
		-- screen we did not need is a fraction of a second, and the cost of NOT holding one we did need is
		-- the player watching the game start twice.
		pcall(function() IntroArm:FireClient(player, true) end)

		local function releaseCover()
			pcall(function() IntroArm:FireClient(player, false) end)
		end

		-- CHECK THE PORTAL FIRST -- before hasSeen(). GetJoinData is instant; hasSeen() is a DataStore round
		-- trip that can take seconds under live load, and an arriving player is sitting on a black screen
		-- waiting for us -- that latency must not go in front of them.
		if arrivedViaPortal(player) then
			print(("[Intro] %s arrived through a portal -> holding the intro for the handoff"):format(player.Name))
			awaitingHandoff[player] = true

			if requested[player] then -- the client already asked while we were still waiting on its character
				awaitingHandoff[player] = nil
				fireIntro(player)
				return
			end

			task.delay(PORTAL_HANDOFF_TIMEOUT, function()
				if awaitingHandoff[player] and player.Parent then
					warn(("[Intro] %s never handed off from the arrival cinematic -> starting the intro anyway")
						:format(player.Name))
					awaitingHandoff[player] = nil
					fireIntro(player)
				end
			end)
			return
		end

		-- ---- direct join: first time only, unless we're replaying for everyone ----
		if not ALWAYS_REPLAY and hasSeen(player) then
			print(("[Intro] %s has already seen the intro -> skipping"):format(player.Name))
			releaseCover() -- no cinematic is coming; let them straight into the world
			return
		end

		-- Let the HUD, the island layout pass and SpawnOnIsland1 settle before hijacking the camera.
		-- SpawnOnIsland1 moves the character on EVERY spawn and waits for island1 to stream in first, so
		-- it can still be mid-placement here -- which is exactly why the client restores to the published
		-- CandySpawnTop attribute rather than to its own snapshot.
		task.wait(1)
		if not player.Parent then return end
		fireIntro(player)
	end)
end)

IntroDone.OnServerEvent:Connect(function(player)
	clearFocus(player) -- streaming goes back to following the character, immediately
	markSeen(player)
	print(("[Intro] %s finished the intro -> flagged as seen%s")
		:format(player.Name, RunService:IsStudio() and " (NOT saved -- DataStores are blocked in Studio)" or ""))

	-- Clear IntroPlaying only once the character is actually back down at the spawn.
	--
	-- The cinematic carries the BODY up the whole tower (StreamingEnabled loads geometry around the
	-- character, not the camera) and the CLIENT restores its position at the end -- so for a few frames
	-- after "done" arrives the server still sees the character at the summit. FlightEconomy polls on a
	-- timer and only skips while IntroPlaying is set, so clearing the flag immediately would bank the
	-- entire tower as "reached" on a brand-new join.
	--
	-- "Back at the bottom" is the MIDPOINT between slot 1 and slot 2, derived from IslandOrder rather
	-- than written down. It used to be a hard-coded 2000, which was fine when slot 1 sat at Y 150 and
	-- slot 2 at Y 3525 -- but the space-economy port moved them to 220 and 1620, putting that line
	-- ABOVE slot 2, so the flag would clear while the player was still on the second island and bank it
	-- as reached on a brand-new join. Deriving it means the next re-spacing cannot reintroduce that.
	-- The 5s cap means a player who somehow never lands still gets progression back rather than being
	-- stuck with it disabled forever.
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 5 do
			local char = player.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp.Position.Y < BOTTOM_Y then break end
			task.wait(0.1)
		end
		if player.Parent then
			player:SetAttribute("IntroPlaying", false) -- climb progress resumes
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	clearFocus(player) -- also destroys their proxy part, so it can't leak into Workspace
	playing[player]         = nil
	awaitingHandoff[player] = nil
	requested[player]       = nil
end)

print(("[Intro] server ready -- portal arrivals ALWAYS get the intro; direct joins: %s")
	:format(ALWAYS_REPLAY and "REPLAYING FOR EVERYONE (⚠ testing -- set ALWAYS_REPLAY = false before launch)"
	                       or ("first join only, gated on " .. STORE_NAME)))
