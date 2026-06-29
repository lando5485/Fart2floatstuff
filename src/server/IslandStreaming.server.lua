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

-- Robustly locate island N: exact display name -> any top-level "Island_<n>_" Model -> any nested one.
-- (Mirrors the finder in PlayerStats so a renamed/nested/typo'd model is still found.) nil if absent.
local function findIslandModel(islandNum)
	local name = ISLAND_NAMES[islandNum]
	local key  = "Island_" .. islandNum .. "_"
	local exact = Workspace:FindFirstChild(name)
	if exact and exact:IsA("Model") then return exact end
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child.Name:find(key, 1, true) then return child end
	end
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("Model") and desc.Name:find(key, 1, true) then return desc end
	end
	return nil
end

local persisted = {} -- [islandNum] = true once its model is marked Persistent

-- Mark one island Persistent (idempotent). Returns true if it is now persistent.
local function persistIsland(islandNum)
	if persisted[islandNum] then return true end
	local model = findIslandModel(islandNum)
	if not model then return false end
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
		print(string.format("[IslandStreaming] poll finished after %ds -> %d/14 persisted%s",
			waited, 14 - stillMissing, stillMissing > 0 and " (" .. stillMissing .. " still missing — check island names in Studio)" or " (ALL loaded)"))
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
		local model = findIslandModel(i)
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
