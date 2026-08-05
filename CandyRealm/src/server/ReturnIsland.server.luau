--======================================================================
-- ReturnIsland.server.luau   (ServerScriptService, Script)
--======================================================================
-- "RETURN TO <HIGHEST PLACE YOU REACHED>" -- the fall-catch safety button.
--
-- CANDYREALM COPY of the portable kit (ReturnIslandKit), from Fart to Float's CoreClient
-- ReturnIslandGui + PlayerStats ReturnToIslandEvent / ReturnPromptIsland driver.
--
-- ===== WHAT CHANGED FOR THIS REALM: THE ANCHORS =====
-- The kit finds anchors by a `ReturnAnchor` number attribute you tag onto one part per island,
-- and falls back to BaseParts named "Island1".. inside a folder. NEITHER matches CandyRealm:
-- nothing here is tagged, and this realm's islands are MODELS named `island1`..`island14`
-- sitting directly under Workspace, lowercase. So the fallback is replaced by this realm's own
-- convention -- the exact `^island[ _]?(%d+)` match that IslandTeleport.client.lua and
-- SpawnOnIsland1.server.luau already use, so all three agree on what "island 7" means.
-- The attribute is still checked FIRST, so tagging a part still overrides everything.
--
-- ===== AND THE LANDING POINT =====
-- The kit assumed an anchor is a flat BasePart, so "the top" was Position.Y + Size.Y/2. On an
-- island MODEL that is the top of the tallest TREE -- it would drop you from the canopy, and the
-- below-margin test would think you were falling while you stood on the ground. So each anchor
-- resolves the same way SpawnOnIsland1's landmarkTop() does: prefer a SpawnLocation / "spawn"-
-- named part inside the island, else raycast DOWN onto the island for its real walking surface.
-- That also means the button puts you exactly where /island<N> and the spawn script put you.
--
-- Both are resolved ONCE per anchor rebuild and cached as plain numbers, so the 5Hz driver below
-- does no raycasting at all -- it only compares heights.
--
-- WHAT IT DOES
--   * Watches every player's height against the highest anchor they have reached.
--   * The moment they are below it by more than CONFIG.CATCH_MARGIN studs, it sets an attribute on them
--     (ReturnPromptIsland = that anchor's index). The client script shows the button off that attribute.
--   * Tapping asks the server to put them back. THE SERVER DOES THE TELEPORT -- see below.
--   * There is NO auto-teleport. Falling is part of the game; the player chooses to give up on the fall.
--
-- ===== WHY THE SERVER OWNS THE TELEPORT =====
-- A client that can move its own character to an arbitrary point is a client that can move it to the top
-- of the map. The button therefore sends an empty "I tapped it" and nothing else -- no position, no index,
-- no target. The server recomputes which anchor the player has actually reached and teleports them there
-- itself. A hacked client can spam the remote and the worst it achieves is being put back somewhere it had
-- already earned. Never accept a destination from the client here, however convenient it looks.
--
-- ===== WHAT COUNTS AS "HOME" =====
-- THE ISLAND YOU WERE LAST STANDING ON -- not the highest one you have reached, which is what the kit
-- did and what does not work here. The kit ranked anchors by INDEX on the assumption that a higher
-- index sits higher in the air. That is true of the food realm (islands climb Y 50 -> Y 45000) and
-- FALSE of CandyRealm, which is a flat archipelago: island5 sits at ~Y 176 and islands 9/11/13/15 all
-- sit at ~Y 222, spread across X/Z instead of stacked. Under the kit's rule, standing anywhere put you
-- at or above every island at once, so "highest reached" jumped straight to the top index and "how far
-- below home" measured ~0 against an island at your own altitude -- the button could never appear.
--
-- Home is therefore found by raycasting down and asking WHICH ISLAND OWNS THE GROUND you are on, kept
-- from the last time you were on one. In a flat world that is also simply the better answer: fall off
-- island 8 and you want island 8 back, not whichever island happens to be numbered highest. It gives up
-- nothing on the security side either -- the only place it can ever send you is one you just left.
--
-- The consequence to know: this is session state, and it starts empty. A player who has not yet stood
-- on any island gets no button. In practice SpawnOnIsland1 puts everyone on one at spawn, so the first
-- driver tick fills it in.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

--======================================================================
-- CONFIG
--======================================================================
local CONFIG = {
	-- ---- WHERE THE ANCHORS ARE ------------------------------------------------------
	-- A part is an anchor if it carries this attribute, whose value is the anchor's INDEX (1, 2, 3...).
	-- Tag one part per island/platform in Studio: Attributes -> add a number named ReturnAnchor.
	--
	-- Prefer this to naming conventions. A name match ("Island3") breaks the first time somebody renames a
	-- model; an attribute is attached to the thing itself and survives being moved, renamed or reparented.
	ANCHOR_ATTRIBUTE = "ReturnAnchor",

	-- THIS REALM'S CONVENTION, used when nothing is tagged: Models under Workspace whose name
	-- matches `island<N>` -- island1, island_7, "island 8", even "island8 crystal". Same pattern
	-- IslandTeleport and SpawnOnIsland1 match on, deliberately.
	ISLAND_MODEL_PATTERN = "^island[ _]?(%d+)",
	-- 32, not 14. The world is NOT a contiguous 1..14: the boot log shows islands
	-- 1,2,3,4,5,8,9,11,13,14 AND an island15 (the Bakery), with 6,7,10,12 absent. A cap of 14
	-- silently dropped island15 -- the scan reported "10 anchor(s)" and the Bakery could never
	-- be returned to. The scan only ever finds what exists, so a generous cap costs nothing.
	MAX_ISLAND           = 32,

	-- ---- WHEN THE BUTTON APPEARS ----------------------------------------------------
	-- ALWAYS_SHOW = the rule this realm actually wants: the button is up whenever you are NOT
	-- farting upward. Standing on an island, walking, drifting, falling -- all of it. It is a
	-- convenience door back to solid ground, not a fall-catch that has to judge whether you are
	-- in enough trouble to deserve it. Everything below ALWAYS_SHOW is the kit's original
	-- fall-catch behaviour, kept intact and reachable by flipping this to false.
	ALWAYS_SHOW = true,

	CATCH_MARGIN = 60,   -- studs BELOW the anchor before the prompt appears. Too small and the button
	                     -- flickers on every hop; too large and a falling player waits to be offered help.

	-- ---- FLYING vs FALLING ----------------------------------------------------------
	-- Read off the character's vertical velocity, which the client replicates to the server as
	-- part of owning its own character. There is no other way to know: PropelSystem's flying flag
	-- is a CLIENT global (_G.isFlying) and its BodyVelocity is created client-side, so neither
	-- exists on this side of the wire. Velocity does, it needs no new remote, and at 5Hz it is
	-- plenty accurate for showing a button.
	RISING_SPEED = 8,    -- +studs/sec above which they are under fart thrust -> HIDE the button.
	                     -- Flight speeds start at 40, so 8 clears walking, jumping and stray
	                     -- physics jitter without ever catching a real climb.
	FALL_SPEED   = -35,  -- studs/sec below which this counts as a DECENT fall (not a hop or a
	                     -- step off a kerb) -> offer the button early, see FALL_MARGIN.
	FALL_MARGIN  = 15,   -- studs below the anchor needed during a decent fall. Much smaller than
	                     -- CATCH_MARGIN on purpose: a real plummet is unambiguous, so there is no
	                     -- reason to make someone drop a further 45 studs before offering help.

	-- ---- STANDING ON SOMETHING -------------------------------------------------------
	-- Grounded ON a known island -> hidden, and that island becomes home. Grounded on something
	-- that is NOT part of any island (a stray platform, a prop, debris below the archipelago)
	-- while lower than home -> shown, because you are stuck down there and not going to fall any
	-- further. Read off Humanoid.FloorMaterial, which replicates and which PropelSystem's own
	-- auto-fuel check already uses.
	--
	-- There is no "am I on my own island" stud margin any more, and there should not be: the
	-- raycast tells us the ground's OWNER outright, so a dip or a low ledge on your own island is
	-- recognised as your own island however far it drops. The 100-stud version of this was
	-- actively wrong here -- larger than the whole vertical spread of the world.
	GROUND_MARGIN = 25,  -- studs below home before non-island ground counts as "stuck"

	-- ---- WHERE THEY LAND ------------------------------------------------------------
	DROP_HEIGHT  = 6,    -- studs above the anchor's top face, so they land ON it rather than inside it
	FACE_CENTRE  = true, -- turn them to face the anchor's centre, so "back" doesn't also mean "disoriented"

	-- ---- PROGRESS -------------------------------------------------------------------
	-- ---- WHICH ISLAND IS "HOME" ------------------------------------------------------
	-- NOT the highest one you have reached. The kit ranked anchors by INDEX and assumed a higher
	-- index sits higher in the air -- true in the food realm, where islands climb from Y 50 to
	-- Y 45000. CANDYREALM IS FLAT: its islands are an archipelago spread across X/Z at roughly
	-- ONE altitude (island5 ~Y 176, islands 9/11/13/15 ~Y 222). Under the kit's rule, standing
	-- anywhere put you at or above every island at once, so "highest reached" instantly became
	-- the top index, "how far below home are you" computed as ~0 against an island at your own
	-- height, and the button could never appear. That is the bug -- not a threshold, the premise.
	--
	-- So home is THE ISLAND YOU WERE LAST STANDING ON, found by raycasting down and asking which
	-- island model owns what you are standing on. In a flat world that is also the more useful
	-- answer: falling off island 8 should offer island 8, not whichever island is numbered
	-- highest. It cannot be exploited either -- you can only be sent somewhere you just were.
	GROUND_LOOKDOWN = 25,  -- studs to raycast below the character to identify the ground's owner

	-- ---- RATE ------------------------------------------------------------------------
	CHECK_HZ = 5,   -- how often the height check runs. 5/sec is plenty and costs nothing; per-frame is waste.
	DEBUG    = true, -- one line per show/hide TRANSITION (never per tick). Set false once happy.
}

--======================================================================
-- REMOTE
--======================================================================
local function getOrCreate(parent, class, name)
	local e = parent:FindFirstChild(name)
	if not e then e = Instance.new(class); e.Name = name; e.Parent = parent end
	return e
end
local ReturnToIslandEvent = getOrCreate(ReplicatedStorage, "RemoteEvent", "ReturnToIslandEvent")

--======================================================================
-- THE ANCHORS
--======================================================================
-- Rebuilt on demand rather than cached once at startup: with StreamingEnabled, and in any realm that builds
-- its world from a script, the parts do not all exist on the first frame. A stale cache here means the
-- button silently does nothing for the islands that loaded late -- which looks exactly like a broken button.
-- Each entry is { inst = <the island>, surfaceY = <number>, landing = <Vector3>, centre = <Vector3> }.
-- surfaceY and landing are resolved HERE, once per rebuild, so the 5Hz driver never raycasts.
local anchorCache, anchorCacheAt = {}, 0

-- The walking surface of a landmark, verbatim in spirit from SpawnOnIsland1's landmarkTop():
-- raycast straight down onto it and take what we hit, else settle for the bounding-box top.
-- Bounding box ALONE is wrong for an island Model -- that is the top of its tallest tree.
local function surfaceOf(inst)
	local cf, sz
	if inst:IsA("BasePart") then cf, sz = inst.CFrame, inst.Size else cf, sz = inst:GetBoundingBox() end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { inst }
	local hit = Workspace:Raycast(cf.Position + Vector3.new(0, sz.Y, 0), Vector3.new(0, -sz.Y * 2.5, 0), rp)
	local pos = (hit and hit.Position) or (cf.Position + Vector3.new(0, sz.Y * 0.5, 0))
	return pos, cf.Position
end

-- Prefer a spawn brick inside the island, so the button drops you where /island<N> and the spawn
-- script drop you rather than at whatever the raycast happens to strike (a roof, a tree trunk).
local function spawnPartIn(inst)
	if inst:IsA("BasePart") then return nil end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") and (d:IsA("SpawnLocation") or string.lower(d.Name):find("spawn", 1, true)) then
			return d
		end
	end
	return nil
end

local function describe(inst)
	local target = spawnPartIn(inst) or inst
	local surface, centre = surfaceOf(target)
	return {
		inst     = inst,
		surfaceY = surface.Y,
		landing  = surface + Vector3.new(0, CONFIG.DROP_HEIGHT, 0),
		centre   = centre,
	}
end

local function rebuildAnchors()
	local raw = {}
	-- 1) TAGGED PARTS WIN. Kept from the kit so tagging a specific pad still overrides the
	--    name scan below -- useful for a platform that is not an island model at all.
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") then
			local idx = tonumber(d:GetAttribute(CONFIG.ANCHOR_ATTRIBUTE))
			if idx and idx > 0 then raw[idx] = d end
		end
	end
	-- 2) THIS REALM'S island<N> MODELS, for every index the attributes did not claim. Direct
	--    children first (island1..island14 sit right under Workspace), then a lenient descendant
	--    sweep for anything renamed or reparented.
	for i = 1, CONFIG.MAX_ISLAND do
		if not raw[i] then
			local exact = Workspace:FindFirstChild("island" .. i)
			if exact then raw[i] = exact end
		end
	end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") then
			local num = tonumber(string.lower(d.Name):match(CONFIG.ISLAND_MODEL_PATTERN) or "")
			if num and num >= 1 and num <= CONFIG.MAX_ISLAND and not raw[num] then raw[num] = d end
		end
	end

	local found = {}
	for idx, inst in pairs(raw) do
		-- An island whose parts have not replicated yet has no bounding box worth using; skip it
		-- and let the next rebuild pick it up, rather than caching a bogus surface height.
		if inst:IsA("BasePart") or inst:FindFirstChildWhichIsA("BasePart", true) then
			found[idx] = describe(inst)
		end
	end
	anchorCache, anchorCacheAt = found, os.clock()
	return found
end

local function anchors()
	if os.clock() - anchorCacheAt > 5 then return rebuildAnchors() end
	return anchorCache
end

--======================================================================
-- HOW FAR HAVE THEY GOT
--======================================================================
local lastIsland    = {} -- [player] = index of the island they were last STANDING on -- see CONFIG
local promptLatched = {} -- [player] = is the button currently up? (the hysteresis state, see the driver)

-- WHICH ISLAND IS UNDERFOOT. Raycast down from the character and ask which anchor owns whatever we
-- hit. Ancestry, not proximity: it gets props right for free -- stand on a crate, a food stand or an
-- NPC that lives inside island8 and the hit part is still a descendant of island8, so you are on
-- island8. Nearest-by-distance would have to guess at exactly those cases, and this realm's islands
-- are nested two and three deep (Workspace.island13.island13.island13), which distance handles badly.
-- Returns nil when the ground belongs to no island at all -- that is a real answer, not a failure.
local function islandUnderfoot(a, char, hrp)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char }
	local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -CONFIG.GROUND_LOOKDOWN, 0), rp)
	if not (hit and hit.Instance) then return nil end
	for idx, entry in pairs(a) do
		if hit.Instance == entry.inst or hit.Instance:IsDescendantOf(entry.inst) then return idx end
	end
	return nil
end

-- THE SEED. islandUnderfoot() is exact but it can legitimately answer "no island" -- you are on a
-- prop parented straight to Workspace, on a stand, on terrain, in the air on the very first tick.
-- Without a fallback, home stays nil and the button is simply never offered, which is the failure
-- that is hardest to tell apart from a broken script. So: nearest anchor by HORIZONTAL distance,
-- used ONLY to seed an empty home. It is a guess, and it is immediately overwritten by the exact
-- answer the moment the player stands on a real island -- but it means there is always a door back.
local function nearestAnchor(a, pos)
	local bestIdx, bestD
	for idx, entry in pairs(a) do
		local d = (Vector2.new(entry.landing.X, entry.landing.Z) - Vector2.new(pos.X, pos.Z)).Magnitude
		if not bestD or d < bestD then bestIdx, bestD = idx, d end
	end
	return bestIdx
end

--======================================================================
-- THE TELEPORT
--======================================================================
local function putOnAnchor(char, entry)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and entry) then return false end
	local target = entry.landing
	-- YAW ONLY, unlike the kit. Its version stepped the player BACK from the target by half the
	-- anchor's depth before looking at it -- fine for a small pad, but on an island model half the
	-- depth is off the edge, so it would have dropped them into the void beside the island. Here
	-- the landing point is exactly where surfaceOf() found ground, and only the facing is turned.
	local look = Vector3.new(entry.centre.X, target.Y, entry.centre.Z)
	if CONFIG.FACE_CENTRE and (look - target).Magnitude > 1 then
		char:PivotTo(CFrame.lookAt(target, look))
	else
		char:PivotTo(CFrame.new(target))
	end
	-- Kill the fall. Without this they arrive carrying whatever downward velocity they had and drop
	-- straight back off, which reads as the button not working.
	hrp.AssemblyLinearVelocity = Vector3.zero
	return true
end

ReturnToIslandEvent.OnServerEvent:Connect(function(player)
	-- The client sends NOTHING. Everything below is recomputed here; see the header.
	local n = lastIsland[player]
	if not n then return end                       -- they have not stood on an island yet
	local entry = anchors()[n]
	if not entry then
		warn(("[Return] %s tapped but anchor %d is not loaded yet"):format(player.Name, n))
		return
	end
	local char = player.Character
	if not (char and char:FindFirstChild("HumanoidRootPart")) then return end

	-- ALWAYS honour the tap. It deliberately does NOT re-check the below-margin condition: the button is
	-- only ever shown while the player is below home, and re-testing here meant a player who tapped just as
	-- they crossed back over the line got a silent no-op -- a button that sometimes does nothing is worse
	-- than one that occasionally repositions you three studs. It cannot skip progress either way: the only
	-- destination it can ever produce is somewhere the player already reached.
	if putOnAnchor(char, entry) then
		promptLatched[player] = false   -- drop the hysteresis with it, or the next tick re-shows it
		player:SetAttribute("ReturnPromptIsland", 0)
		print(("[Return] %s returned to anchor %d"):format(player.Name, n))
	end
end)

--======================================================================
-- THE PROMPT DRIVER
--======================================================================
-- Sets ReturnPromptIsland on every player: the anchor index to offer, or 0 for "hide the button".
--
-- ===== WHEN IT SHOWS =====
-- With CONFIG.ALWAYS_SHOW (this realm's setting) there are exactly two states, and that is the
-- whole point -- nothing to reason about when it is missing:
--
--   RISING under thrust (vy > RISING_SPEED)  -> HIDDEN. You are already going up.
--   ANYTHING ELSE                            -> SHOWN. Standing on an island, walking, drifting,
--                                               falling. It is a door back to solid ground, not a
--                                               rescue that has to judge whether you deserve one.
--
-- Set ALWAYS_SHOW = false and the kit's original fall-catch rules take over instead (below home
-- by CATCH_MARGIN, or a decent fall past the smaller FALL_MARGIN, with hysteresis between them).
-- They are left intact below rather than deleted, because they are the right behaviour for a
-- VERTICAL realm -- which is what this kit came from and what CandyRealm is not.
task.spawn(function()
	local period = 1 / math.max(1, CONFIG.CHECK_HZ)
	while true do
		task.wait(period)
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local a   = anchors()
				local y   = hrp.Position.Y
				local hum = char:FindFirstChildOfClass("Humanoid")
				local onLand = hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air

				-- HOME = the last island they stood on. Only ever updated while grounded ON an
				-- island, so it survives the whole fall -- which is the entire point of it.
				local standingOn = onLand and islandUnderfoot(a, char, hrp) or nil
				if standingOn then
					lastIsland[plr] = standingOn
				elseif lastIsland[plr] == nil then
					lastIsland[plr] = nearestAnchor(a, hrp.Position)   -- seed only; see nearestAnchor
				end

				local home  = lastIsland[plr]
				local entry = home and a[home]
				local want  = 0
				if entry then
					local vy      = hrp.AssemblyLinearVelocity.Y
					local below   = entry.surfaceY - y        -- how far under home they are
					local rising  = vy > CONFIG.RISING_SPEED  -- under fart thrust: climbing out
					local falling = vy < CONFIG.FALL_SPEED    -- a real drop, not a hop

					if rising then
						want = 0                                  -- climbing out under your own gas
					elseif CONFIG.ALWAYS_SHOW then
						-- NOT FLYING = SHOWN. No margin, no fall test, no "are you on an island
						-- already" check. Standing on island 8 offers island 8 and tapping it just
						-- re-seats you there -- harmless, and far better than a button whose
						-- absence you have to reason about.
						want = home
					elseif standingOn then
						want = 0                                  -- feet on a real island: nothing to offer
					elseif onLand then
						-- Grounded on something no island owns -- a stray platform, a prop, debris
						-- under the archipelago. You are not going to fall any further, so do not
						-- make anyone wait out a drop that will never come.
						want = (below > CONFIG.GROUND_MARGIN) and home or 0
					elseif below <= CONFIG.FALL_MARGIN then
						want = 0                                  -- airborne, but level with home
					-- IN THE AIR: hysteresis, a high bar to APPEAR and a low one to DISAPPEAR,
					-- holding its state in between. Without it, falling 90 studs and landing on a
					-- ledge 30 below home would show the button all the way down and snatch it away
					-- the instant you touched something. One threshold cannot do both jobs: 60
					-- alone hides it on that ledge, 15 alone blinks on every hop.
					elseif below > CONFIG.CATCH_MARGIN
						or (falling and below > CONFIG.FALL_MARGIN)
						or promptLatched[plr] then
						want = home
					end
				end
				promptLatched[plr] = want > 0
				if (plr:GetAttribute("ReturnPromptIsland") or 0) ~= want then
					plr:SetAttribute("ReturnPromptIsland", want)
					-- Only ever fires on a CHANGE, so it cannot spam. Worth keeping: every value
					-- that decides this button lives on the server, so without it a button that
					-- does not appear is indistinguishable from a button that is broken.
					if CONFIG.DEBUG then
						print(("[Return] %s -> %s | home=%s standingOn=%s onLand=%s y=%.0f below=%.0f vy=%.0f")
							:format(plr.Name, want > 0 and ("SHOW island " .. want) or "hide",
								tostring(home), tostring(standingOn), tostring(onLand), y,
								entry and (entry.surfaceY - y) or 0, hrp.AssemblyLinearVelocity.Y))
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p) lastIsland[p] = nil; promptLatched[p] = nil end)

do
	local list = {}
	for idx, e in pairs(rebuildAnchors()) do list[#list + 1] = ("%d@Y%.0f"):format(idx, e.surfaceY) end
	table.sort(list)
	local n = #list
	-- The indices AND their surface heights, because both have already been wrong once: a cap of
	-- 14 dropped island15 silently, and the heights are what reveal that this world is flat.
	print(("[Return] ready -- %d anchor(s): %s | home = last island you stood on, %d-stud catch margin")
		:format(n, table.concat(list, " "), CONFIG.CATCH_MARGIN))
	if n == 0 then
		warn("[Return] NO anchors found yet -- if this realm's islands are named something other than "
			.. "island1..island14, tag one part per island with a number attribute named '"
			.. CONFIG.ANCHOR_ATTRIBUTE .. "'. The scan re-runs every 5s, so late-built islands self-heal.")
	end
end
