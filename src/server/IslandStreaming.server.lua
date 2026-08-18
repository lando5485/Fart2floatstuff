-- ============================================================================
-- ISLAND STREAMING PERSISTENCE
-- ============================================================================
-- Workspace.StreamingEnabled is ON, so distant islands get streamed OUT for a
-- player who isn't near them. During the one-time Community Garden cinematic the
-- camera flies up the WHOLE island stack (Island 1 -> 14) far faster than streaming
-- can load each island, so islands 2-14 would otherwise appear empty/unrendered.
--
-- FIX: mark every island Model's ModelStreamingMode = Persistent on the SERVER. A
-- persistent model (and all its descendants) is ALWAYS replicated + rendered for
-- every client, regardless of distance -- so the islands show up during the fast
-- flyover AND during normal play, and never stream out.
--
-- This runs as one of the FIRST server scripts and persists the islands IMMEDIATELY
-- (islands ship in the place file, so they exist in Workspace before scripts run),
-- with a short poll for any that build late, plus a per-player re-ensure on join.
-- So by the time a player reaches the island-select menu / the intro can trigger,
-- islands 2-14 are already guaranteed persistent + loaded. Missing islands are
-- skipped gracefully (never errors).
-- ============================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ISLAND_NAMES = {
	"Bean Farm","Broccoli Bluff","Cabbage Cliffs","Turnip Tranquil","Coconut Cove","Bread Board",
	"Pasta Peak","Popcorn Pinnacle","Milk Marsh","Butter Swamp","Ice Cream Isle","Burger Bluff",
	"Burrito Barrens","Pizza Palms",
}

-- MATCH THE NAME NORMALISED, NEVER RAW.
--
-- This finder only ever looked for the exact display name ("Broccoli Bluff") or the literal substring
-- "Island_<n>_". The models in this place are not all named that way -- an island called "island13",
-- "Island 13", "Island-13" or "island13 " matches NONE of those, so it was never found, never marked
-- Persistent, and therefore streamed out and did not appear at distance. IslandNPCs and PetSystem already
-- solved this with a normalised compare; this file was the last one still matching raw, which is why islands
-- kept going missing here specifically.
--
-- normName lowercases and strips spaces/underscores/dashes/dots, so every spelling above collapses to
-- "island13". The DIGIT GUARD after the number is essential: without it "island1" also matches island 10-14,
-- and island 1 would claim island 14's model.
local function normName(s) return (tostring(s):lower():gsub("[%s_%-%.]", "")) end

local function findIslandModel(islandNum)
	local name  = ISLAND_NAMES[islandNum]
	local key   = "Island_" .. islandNum .. "_"
	local wantN = "island" .. islandNum          -- "island13"
	local wantD = normName(name)                 -- "burritobarrens"

	local exact = Workspace:FindFirstChild(name)
	if exact and exact:IsA("Model") then return exact end

	local function match(m)
		if not m:IsA("Model") then return false end
		if m.Name:find(key, 1, true) then return true end -- original raw form, still valid
		local n = normName(m.Name)
		if n == wantD then return true end                -- display name in any spelling
		-- "island<n>" prefix, but ONLY when the next character is not another digit
		return n:sub(1, #wantN) == wantN and not tonumber(n:sub(#wantN + 1, #wantN + 1))
	end

	for _, child in ipairs(Workspace:GetChildren()) do
		if match(child) then return child end
	end
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if match(desc) then return desc end
	end
	return nil
end

local persisted = {}    -- [islandNum] = true once its model is marked Persistent
local islandModel = {}  -- [islandNum] = the resolved Model. findIslandModel can fall through to a FULL
                        -- Workspace:GetDescendants() scan, and the join verify below asks for all 14 -- without
                        -- this cache that is 14 whole-Workspace walks per player join.

-- Mark one island Persistent (idempotent). Returns true if it is now persistent.
local function persistIsland(islandNum)
	if persisted[islandNum] then return true end
	local model = findIslandModel(islandNum)
	if not model then return false end
	islandModel[islandNum] = model
	local ok = pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	if ok and model.ModelStreamingMode == Enum.ModelStreamingMode.Persistent then
		persisted[islandNum] = true
		print(string.format("[IslandStreaming] PERSISTED island %d ('%s') -> ModelStreamingMode=Persistent (always loaded)", islandNum, model.Name))
		return true
	end
	if not ok then
		warn("[IslandStreaming] FAILED to set ModelStreamingMode on island " .. islandNum)
	end
	return false
end

-- Sweep all 14 islands; returns how many are still missing (not yet persisted).
local function persistAll(tag)
	local missing = 0
	for i = 1, 14 do
		if not persistIsland(i) then
			missing = missing + 1
			print(string.format("[IslandStreaming] (%s) island %d ('%s') not found yet -> will retry", tag, i, ISLAND_NAMES[i]))
		end
	end
	return missing
end

-- 1) IMMEDIATE pass at server start (islands ship in the place file, so most/all are present right away).
print("[IslandStreaming] server start -> persisting islands 1-14 EARLY (before any join/menu/intro)")
local stillMissing = persistAll("startup")

-- 2) Short poll for any island that builds late, until all are persistent (or a safety timeout).
if stillMissing > 0 then
	task.spawn(function()
		local waited = 0
		while stillMissing > 0 and waited < 30 do
			task.wait(1); waited = waited + 1
			stillMissing = persistAll("poll")
		end
		if stillMissing > 0 then
			-- NAME THEM. "3 still missing" tells you nothing you can act on; the island numbers + the names
			-- being searched for are what let you find the mis-named model in Studio.
			local names = {}
			for i = 1, 14 do
				if not persisted[i] then names[#names + 1] = i .. " ('" .. ISLAND_NAMES[i] .. "')" end
			end
			warn(string.format("[IslandStreaming] poll finished after %ds -> %d/14 persisted. NOT FOUND: %s."
				.. " These islands will STREAM OUT and not appear at distance. Rename the Workspace Model to the"
				.. " island name, or to 'Island_<n>_...' / 'island<n>...'.", waited, 14 - stillMissing, table.concat(names, ", ")))
		else
			print(string.format("[IslandStreaming] poll finished after %ds -> 14/14 persisted (ALL loaded)", waited))
		end
	end)
else
	print("[IslandStreaming] ALL 14 islands persisted at startup (none missing)")
end

-- 3) Per-player re-ensure on join: ModelStreamingMode is global (set once covers everyone), but this is a
-- cheap belt-and-suspenders so a player who joins before the poll completes still gets every island
-- persisted as early as possible in THEIR join flow (well before the island menu / cinematic).
Players.PlayerAdded:Connect(function(player)
	persistAll("join:" .. player.Name)
	-- VERIFY (per-island confirmation EARLY in this player's join flow, before the menu/intro):
	-- print each island's name and confirm its ModelStreamingMode is Persistent (i.e. it will render).
	local ready = 0
	for i = 1, 14 do
		local model = islandModel[i] or findIslandModel(i) -- cached from persistIsland; only re-scans if unresolved
		local mode  = model and model.ModelStreamingMode
		local isPersistent = (mode == Enum.ModelStreamingMode.Persistent)
		if isPersistent then ready = ready + 1 end
		print(string.format("[IslandStreaming] JOIN VERIFY (%s): island %d '%s' -> %s",
			player.Name, i, ISLAND_NAMES[i],
			model and (isPersistent and "Persistent (loaded/rendered)" or ("NOT persistent (mode=" .. tostring(mode) .. ")")) or "MISSING (skipped)"))
	end
	print(string.format("[IslandStreaming] %s joined -> %d/14 islands persistent + ready%s",
		player.Name, ready, ready == 14 and " (ALL ready for the cinematic flyover)" or " (" .. (14 - ready) .. " not ready)"))
end)

-- ============================================================================
-- 4) STREAMING RADII  --  the "parts vanish when I turn the camera" fix
-- ============================================================================
-- Symptom: standing on Bean Farm, scenery that is plainly rendered pops OUT when you swing the camera, then
-- comes back. That is not distance streaming in the usual sense -- Bean Farm is the spawn island, you are
-- standing on it -- and no client script in this place culls world geometry, so it is the engine.
--
-- Cause: the streaming radii were never configured anywhere in this project, so the place runs on the
-- defaults -- StreamingMinRadius = 64. Only that 64-stud sphere is GUARANTEED resident; everything past it is
-- "target" content the engine is free to stream out again whenever it feels the pressure. Crucially the
-- streaming origin follows the CAMERA, not the character, and the default over-the-shoulder camera orbits
-- around you at several studs of zoom -- so simply turning swings the origin far enough to push props in and
-- out of that small guaranteed sphere. Turn one way, they unload; turn back, they reload.
--
-- Fix: make the guaranteed radius big enough to hold the island you are standing on. Inside MinRadius the
-- engine may not stream anything out, so the popping stops outright rather than being made rarer.
--
-- Cost is memory: a bigger resident set. 768 studs comfortably covers one island (Bean Farm's props sit well
-- inside a few hundred studs of its centre) without trying to hold the whole 45,000-stud stack -- the islands
-- themselves are already Persistent from the passes above, so this is only about the loose scenery on them.
local MIN_RADIUS = 768
local TARGET_RADIUS = 2048 -- must stay comfortably above MIN_RADIUS or the engine has nothing to stream

do
	-- ⚠ THESE PROPERTIES ARE STUDIO-ONLY. A script cannot even READ them: the first attempt threw
	-- "StreamingMinRadius is not a valid member of Workspace", which killed this whole script at that line --
	-- taking the loose-part audit below down with it (BootCheck reported it as ERRORED). Every access is now
	-- inside a pcall, so the worst case is a printed instruction instead of a dead script.
	--
	-- The fix is therefore a STUDIO one, printed below rather than applied here.
	-- Indexed by string rather than with a type cast, so there is no Luau type syntax to trip over in a
	-- .lua file, and the pcall is the only thing standing between us and the error above.
	local function readRadius(name)
		local ok, value = pcall(function() return Workspace[name] end)
		if ok and type(value) == "number" then return value end
		return nil
	end
	local function writeRadius(name, value)
		return (pcall(function() Workspace[name] = value end))
	end

	local beforeMin = readRadius("StreamingMinRadius")
	local beforeTarget = readRadius("StreamingTargetRadius")

	-- Raise the target FIRST if we're allowed to at all. Min is clamped by the engine to stay under the
	-- target, so setting min while the target is still 1024 would silently cap it.
	if beforeTarget and beforeTarget < TARGET_RADIUS then writeRadius("StreamingTargetRadius", TARGET_RADIUS) end
	if beforeMin and beforeMin < MIN_RADIUS then writeRadius("StreamingMinRadius", MIN_RADIUS) end

	local nowMin = readRadius("StreamingMinRadius")
	local okMin = (nowMin ~= nil) and nowMin >= MIN_RADIUS

	if nowMin == nil then
		warn(("[IslandStreaming] streaming radii are NOT scriptable in this engine version -- cannot read or set"
			.. " them. SET THEM BY HAND: in Studio select Workspace, and in Properties set StreamingMinRadius=%d"
			.. " and StreamingTargetRadius=%d, then republish. Until then the guaranteed-resident radius stays"
			.. " at the 64-stud default, which is what lets Bean Farm's scenery pop out when you turn the camera.")
			:format(MIN_RADIUS, TARGET_RADIUS))
	else
		print(string.format("[IslandStreaming] streaming radii: min %d -> %d (want %d), target %s -> %s (want %d)",
			beforeMin or -1, nowMin, MIN_RADIUS,
			tostring(beforeTarget), tostring(readRadius("StreamingTargetRadius")), TARGET_RADIUS))
	end
	if okMin then
		print("[IslandStreaming] guaranteed-resident radius now covers a whole island -- scenery can no longer"
			.. " stream out from a camera turn. (Was 64 studs, the engine default, which is why it did.)")
	elseif nowMin ~= nil then
		-- Readable but the write was refused. (When nowMin is nil the not-scriptable warning above already
		-- said everything, and reading Workspace.StreamingMinRadius here would throw all over again.)
		warn(string.format("[IslandStreaming] StreamingMinRadius stuck at %d (wanted %d) -- camera-turn pop-out"
			.. " will CONTINUE. Set it on Workspace in Studio instead.", nowMin, MIN_RADIUS))
	end
end

-- ============================================================================
-- 5) LOOSE-PART AUDIT (report only)
-- ============================================================================
-- The radius fix above covers scenery near the player. The other half of the problem is scenery that is NOT
-- inside an island Model at all: the passes above set ModelStreamingMode on the island MODELS, and that flag
-- only protects a Model and its descendants. A BasePart parented straight to the Workspace has no Model to
-- inherit from and cannot be marked persistent on its own -- it streams purely by distance, forever.
--
-- So this names them. If Bean Farm still pops after the radius change, the offenders will be in this list,
-- and the fix is a Studio one: drag them into the island's Model so they inherit its Persistent flag.
-- Deliberately REPORT-ONLY -- reparenting Studio-placed parts at runtime would change paths that other
-- scripts look parts up by (SecretCave, the quest markers, the gumball spots), which is not a trade worth
-- making automatically.
task.spawn(function()
	task.wait(8) -- let the persist passes and any late island builds settle first

	local m1 = islandModel[1] or findIslandModel(1)
	if not m1 then
		warn("[IslandStreaming] loose-part audit skipped: island 1's Model was never found (see the poll warning above)")
		return
	end

	local ok, cf, size = pcall(function()
		local c, s = m1:GetBoundingBox()
		return c, s
	end)
	if not ok then return end
	local centre = cf.Position
	-- Generous: the island's own footprint plus 150 studs of apron, so props sitting just off the edge count.
	local reach = math.max(size.X, size.Z) * 0.5 + 150

	local loose = {}
	for _, child in ipairs(Workspace:GetChildren()) do
		-- TERRAIN IS NOT A LOOSE PART. It inherits BasePart, so the plain IsA test below matches it, and it
		-- is ALWAYS a direct child of Workspace -- there is no arrangement of the place in which it is not.
		-- The audit was therefore reporting it on every single boot, with advice ("drag it into the island
		-- Model") that is impossible to follow: Terrain cannot be reparented at all.
		--
		-- Worth fixing rather than ignoring, because an audit that always fires is an audit nobody reads --
		-- and the day a genuinely loose prop appears, it arrives as the second line of a warning everyone
		-- has already learned to scroll past.
		if child:IsA("BasePart") and not child:IsA("Terrain") then
			local d = (child.Position - centre).Magnitude
			if d <= reach then
				loose[#loose + 1] = string.format("'%s' (%s) at %d studs", child.Name, child.ClassName, math.floor(d))
			end
		end
	end

	if #loose == 0 then
		print("[IslandStreaming] loose-part audit: island 1 clean -- every BasePart near Bean Farm lives inside"
			.. " a Model, so all of it inherits a streaming mode. Nothing here can pop on its own.")
		return
	end

	warn(string.format("[IslandStreaming] loose-part audit: %d BasePart(s) sit near Bean Farm but are parented"
		.. " DIRECTLY to Workspace, not inside island 1's Model ('%s'). These cannot be marked Persistent and"
		.. " stream by distance alone -- they are the parts most likely to keep popping. Fix in Studio: drag"
		.. " them into the island Model.", #loose, m1.Name))
	for i = 1, math.min(#loose, 25) do
		warn("[IslandStreaming]   loose: " .. loose[i])
	end
	if #loose > 25 then
		warn(string.format("[IslandStreaming]   ...and %d more (list capped at 25).", #loose - 25))
	end
end)
