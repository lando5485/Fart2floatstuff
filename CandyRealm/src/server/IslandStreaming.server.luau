--======================================================================
-- IslandStreaming.server.luau  (Server Script)  -- CandyRealm
--======================================================================
-- ISLAND STREAMING PERSISTENCE -- ported from the Food realm's IslandStreaming.server.lua,
-- re-pointed at Candy's ELEVEN non-contiguous islands.
--
-- THE PROBLEM THIS SOLVES
-- Workspace.StreamingEnabled is ON. With streaming, a distant island's MODEL replicates but its
-- PARTS do not -- so every quest that looks up a placement marker by name ("monsterspawn",
-- "BeanLiftCrane", "waste", "gumball", "fountain", "gate", "Candy Npc", "BlastZone",
-- "jellylevel1..3", "axe") finds an EMPTY MODEL and reports the marker as missing. It then either
-- bails or falls back to an auto-placed guess, and the props never appear on the blocks you put
-- down in Studio.
--
-- That is exactly what a boot log full of "no 'X' found" lines looks like, and it is why island 9
-- showed nothing until you flew to it: nothing in this realm had ever marked an island persistent.
-- The Food realm has had this file for a while; Candy never got it.
--
-- THE FIX
-- ModelStreamingMode = Persistent on each island MODEL. A persistent model AND ALL ITS DESCENDANTS
-- are always replicated to every client regardless of distance -- so the markers exist for the
-- quest scripts to find, from boot, everywhere. The islands here are nested inside themselves in
-- places (Workspace.island9.island9.BeanLiftCrane, Workspace.island13.island13.island13.barrel);
-- setting the flag on the OUTER model covers the whole chain, so the nesting does not matter.
--
-- ⚠ THIS IS A REPLICATION FIX, NOT A NAMING ONE. A marker that is genuinely missing or misspelled
-- in Studio is still missing after this -- it just stops being HIDDEN behind streaming, so the
-- boot log's "no 'X' found" lines become trustworthy instead of being half real and half timing.
--======================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local IslandOrder = require(game:GetService("ReplicatedStorage")
	:WaitForChild("Shared"):WaitForChild("IslandOrder"))

-- ITERATE SLOT_TO_ISLAND, NEVER `for i = 1, 11`. This world's models are numbered
-- 1,2,3,4,5,8,9,11,13,14,15 -- 6, 7, 10 and 12 were never built. A contiguous loop would miss the
-- top three islands and warn about three that do not exist. (Same trap IslandOrder's header calls out.)
-- OFF-LADDER ISLANDS. Not in the tower (IslandLayout leaves them at their Studio position, no crossing
-- reaches them, they are entered by /island<N> or the wormhole) -- but they still need persisting, because
-- persistence is what makes their quest markers replicate at distance. Without it, a quest on one of these
-- finds an empty Model and reports every marker missing, which is exactly what emptied island 9.
--
-- Kept SEPARATE from IslandOrder rather than added to it: SLOT_TO_ISLAND is the climb ladder and the
-- economy is solved against its length. Adding an island there is a re-solve of SLOT_POS, CandyData.FOODS,
-- FlightTuning.TIERS and StomachTiers; adding one here costs nothing and changes no gameplay numbers.
local EXTRA_PERSIST = { 16, 18, 19 }   -- island16 Candy Mine, island18 Pancake Monster, island19 Broken Tractor.
                                   -- Both are OFF THE LADDER (not in SLOT_TO_ISLAND), so nothing
                                   -- else in the tower plumbing touches them -- but their quests
                                   -- read marker parts at distance, and without Persistent those
                                   -- parts never replicate and every marker reads as missing.

local ISLANDS = {}
for _, n in ipairs(IslandOrder.SLOT_TO_ISLAND) do ISLANDS[#ISLANDS + 1] = n end
for _, n in ipairs(EXTRA_PERSIST) do ISLANDS[#ISLANDS + 1] = n end

local persisted  = {}  -- [islandNum] = true once its model is marked Persistent
local islandModel = {} -- [islandNum] = resolved Model, so the join verify does not re-scan Workspace

-- IslandLayout finds islands with exactly this call, so this file agrees with it by construction.
-- If one ever grows a fuzzy finder, the other must too or they will disagree about which model is
-- which -- and a "persisted" island that is not the one being MOVED is worse than neither.
local function findIsland(islandNum)
	local m = Workspace:FindFirstChild("island" .. islandNum)
	return (m and m:IsA("Model")) and m or nil
end

-- Idempotent. Returns true if the island is now persistent.
local function persistIsland(islandNum)
	if persisted[islandNum] then return true end
	local model = findIsland(islandNum)
	if not model then return false end
	islandModel[islandNum] = model

	local ok = pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	if ok and model.ModelStreamingMode == Enum.ModelStreamingMode.Persistent then
		persisted[islandNum] = true
		print(("[IslandStreaming] PERSISTED island%-2d '%s' -> always replicated (markers now findable at distance)")
			:format(islandNum, IslandOrder.NAME_BY_ISLAND[islandNum] or "?"))
		return true
	end
	if not ok then
		warn(("[IslandStreaming] FAILED to set ModelStreamingMode on island%d"):format(islandNum))
	end
	return false
end

local function persistAll(tag)
	local missing = 0
	for _, islandNum in ipairs(ISLANDS) do
		if not persistIsland(islandNum) then
			missing += 1
			if tag == "startup" then
				print(("[IslandStreaming] (%s) island%d not found yet -> will retry"):format(tag, islandNum))
			end
		end
	end
	return missing
end

-- 1) IMMEDIATE pass. The islands ship in the place file, so they exist in Workspace before any
-- script runs -- this normally catches all eleven on the first try.
print(("[IslandStreaming] server start -> persisting %d island(s) EARLY (before any join/quest builds)")
	:format(#ISLANDS))
local stillMissing = persistAll("startup")

-- 2) Short poll for anything that builds late.
if stillMissing > 0 then
	task.spawn(function()
		local waited = 0
		while stillMissing > 0 and waited < 30 do
			task.wait(1); waited += 1
			stillMissing = persistAll("poll")
		end
		if stillMissing > 0 then
			-- NAME THEM. "3 still missing" is not actionable; the island numbers are what let you find
			-- the mis-named model in Studio.
			local names = {}
			for _, islandNum in ipairs(ISLANDS) do
				if not persisted[islandNum] then
					names[#names + 1] = ("island%d ('%s')"):format(islandNum, IslandOrder.NAME_BY_ISLAND[islandNum] or "?")
				end
			end
			warn(("[IslandStreaming] poll finished after %ds -> %d/%d persisted. NOT FOUND: %s."
				.. " These islands WILL stream out, and every quest marker on them will read as missing"
				.. " until you are stood on it. Rename the Workspace Model to 'island<N>'.")
				:format(waited, #ISLANDS - stillMissing, #ISLANDS, table.concat(names, ", ")))
		else
			print(("[IslandStreaming] poll finished after %ds -> %d/%d persisted (ALL loaded)")
				:format(waited, #ISLANDS, #ISLANDS))
		end
	end)
else
	print(("[IslandStreaming] ALL %d islands persisted at startup"):format(#ISLANDS))
end

-- 3) Per-player re-ensure on join. ModelStreamingMode is global -- setting it once covers everyone --
-- so this is belt-and-braces for a player who joins mid-poll, plus a one-line verdict per join.
Players.PlayerAdded:Connect(function(player)
	persistAll("join")
	local ready = 0
	for _, islandNum in ipairs(ISLANDS) do
		local model = islandModel[islandNum] or findIsland(islandNum)
		if model and model.ModelStreamingMode == Enum.ModelStreamingMode.Persistent then ready += 1 end
	end
	print(("[IslandStreaming] %s joined -> %d/%d islands persistent%s")
		:format(player.Name, ready, #ISLANDS,
			ready == #ISLANDS and " (every island's markers are replicated)" or " -- SOME ISLANDS WILL STREAM OUT"))
end)

-- ============================================================================
-- 4) STREAMING RADII -- the "props vanish when I turn the camera" half
-- ============================================================================
-- Persistence covers the island MODELS. The other half is the guaranteed-resident radius: on the
-- engine default (StreamingMinRadius = 64) only a 64-stud sphere is protected, and the streaming
-- origin follows the CAMERA, not the character -- so on a default over-the-shoulder camera, simply
-- turning swings the origin far enough to push nearby scenery in and out of that sphere.
--
-- ⚠ THESE PROPERTIES ARE STUDIO-ONLY IN SOME ENGINE VERSIONS -- a script cannot even READ them, and
-- an unguarded read throws "StreamingMinRadius is not a valid member of Workspace", which would kill
-- this whole script at that line and take the audit below with it. Every access is pcall'd, so the
-- worst case is a printed instruction rather than a dead script.
local MIN_RADIUS    = 768   -- comfortably covers one Candy island
local TARGET_RADIUS = 2048  -- must stay above MIN_RADIUS or the engine has nothing left to stream

do
	local function readRadius(name)
		local ok, value = pcall(function() return Workspace[name] end)
		if ok and type(value) == "number" then return value end
		return nil
	end
	local function writeRadius(name, value)
		return (pcall(function() Workspace[name] = value end))
	end

	local beforeMin    = readRadius("StreamingMinRadius")
	local beforeTarget = readRadius("StreamingTargetRadius")

	-- ⚠ StreamingTargetRadius DOES NOT EXIST ON EVERY ENGINE VERSION and is gone from current ones
	-- ("StreamingTargetRadius is not a valid member of Workspace"). Reading it is pcall'd above, so a
	-- missing property reads as nil and this simply skips it -- MinRadius is the one that decides the
	-- guaranteed-resident bubble, and it is the one that fixes camera-turn pop-out. Target FIRST when
	-- it does exist, because the engine clamps min below target and raising min alone would be capped.
	if beforeTarget and beforeTarget < TARGET_RADIUS then writeRadius("StreamingTargetRadius", TARGET_RADIUS) end
	if beforeMin and beforeMin < MIN_RADIUS then writeRadius("StreamingMinRadius", MIN_RADIUS) end

	local nowMin = readRadius("StreamingMinRadius")
	if nowMin == nil then
		-- ⚠ THE PROPERTIES PANEL IS THE ONLY WAY. These are tagged NotScriptable, so Lua cannot read
		-- OR write them from anywhere -- not this script, and not Studio's command bar either. Trying
		-- it there gives "StreamingMinRadius is not a valid member of Workspace", which reads like the
		-- property is missing when it is simply closed to scripts. (Verified 16 Aug: both the command
		-- bar and this script get the same refusal.) Do not "fix" this warning by suggesting a command
		-- bar line again -- it cannot work.
		warn(("[IslandStreaming] StreamingMinRadius cannot be set by any script (it is NotScriptable)."
			.. " SET IT IN THE PROPERTIES PANEL: stop the playtest, click Workspace in Explorer, find the"
			.. " Streaming section (it only appears when StreamingEnabled is ticked), type %d into"
			.. " StreamingMinRadius, then File > Publish. Until then the guaranteed radius stays at the"
			.. " 64-stud default, which is what lets scenery vanish on a camera turn.")
			:format(MIN_RADIUS))
	elseif nowMin >= MIN_RADIUS then
		print(("[IslandStreaming] guaranteed-resident radius %d (was %s) -- scenery can no longer stream out from"
			.. " a camera turn."):format(nowMin, tostring(beforeMin)))
	else
		warn(("[IslandStreaming] StreamingMinRadius stuck at %d (wanted %d) -- scenery will KEEP vanishing on a"
			.. " camera turn. Set it in Workspace's PROPERTIES PANEL (it is NotScriptable, so no script and no"
			.. " command bar can do it), then Publish -- it is a place setting Rojo does not sync.")
			:format(nowMin, MIN_RADIUS))
	end
end

-- ============================================================================
-- 5) LOOSE-PART AUDIT (report only)
-- ============================================================================
-- ModelStreamingMode protects a Model and its descendants. A BasePart parented STRAIGHT to Workspace
-- has no Model to inherit from and cannot be marked persistent on its own -- it streams by distance,
-- forever. If a placement marker is loose like that, persisting the islands does not save it and the
-- quest that wants it will still intermittently not find it.
--
-- So this names them, per island, and stops. Deliberately REPORT-ONLY: reparenting Studio-placed parts
-- at runtime would change the very paths other scripts look them up by.
task.spawn(function()
	task.wait(8) -- let the persist passes and any late island builds settle

	-- Bounding boxes once, up front -- not per loose part.
	local boxes = {}
	for _, islandNum in ipairs(ISLANDS) do
		local m = islandModel[islandNum]
		if m then
			local ok, cf, size = pcall(function()
				local c, s = m:GetBoundingBox()
				return c, s
			end)
			if ok and cf and size then
				-- island footprint + 150 studs of apron, so props just off the edge still count as "on" it
				boxes[#boxes + 1] = { num = islandNum, centre = cf.Position,
					reach = math.max(size.X, size.Z) * 0.5 + 150 }
			end
		end
	end
	if #boxes == 0 then
		warn("[IslandStreaming] loose-part audit skipped: no island models resolved (see the poll warning above)")
		return
	end

	local loose = {}
	for _, child in ipairs(Workspace:GetChildren()) do
		-- TERRAIN IS NOT A LOOSE PART. It inherits BasePart and is always a direct child of Workspace, so a
		-- plain IsA test reports it on every boot with advice that cannot be followed (Terrain cannot be
		-- reparented). An audit that always fires is an audit nobody reads.
		if child:IsA("BasePart") and not child:IsA("Terrain") then
			for _, b in ipairs(boxes) do
				local d = (child.Position - b.centre).Magnitude
				if d <= b.reach then
					loose[#loose + 1] = ("'%s' (%s) %d studs from island%d")
						:format(child.Name, child.ClassName, math.floor(d), b.num)
					break
				end
			end
		end
	end

	if #loose == 0 then
		print("[IslandStreaming] loose-part audit: clean -- every BasePart near an island lives inside a Model,"
			.. " so all of it inherits the Persistent flag. Nothing can pop or go missing on its own.")
		return
	end

	warn(("[IslandStreaming] loose-part audit: %d BasePart(s) sit near an island but are parented DIRECTLY to"
		.. " Workspace, so they CANNOT inherit Persistent and stream by distance alone. If any of these is a quest"
		.. " marker, that quest will keep reporting it missing. Fix in Studio: drag them into the island's Model.")
		:format(#loose))
	for i = 1, math.min(#loose, 25) do
		warn("[IslandStreaming]   loose: " .. loose[i])
	end
	if #loose > 25 then
		warn(("[IslandStreaming]   ...and %d more (list capped at 25)."):format(#loose - 25))
	end
end)
