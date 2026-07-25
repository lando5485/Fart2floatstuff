--======================================================================
-- AnchorIslands.server.luau  (Server Script)  -- CandyRealm
--======================================================================
-- Anchors EVERY static BasePart on each island so islands never fall/drift,
-- WHILE NPCs (gardeners), tools, and weld-driven rigs still animate.
--
-- Ported from the DinoRealm island-anchoring system (see ISLAND_ANCHORING.md).
-- Adapted for CandyRealm: islands are models named "island1".."island13"
-- (lowercase; also accepts the "Island_1_<Name>" style), auto-discovered rather
-- than a hard-coded list. Islands are anchored IN PLACE (CandyRealm does not
-- reposition islands, so there's no IslandLayout here).
--
-- WHAT IS DELIBERATELY *NOT* ANCHORED (anchoring these BREAKS them):
--   * WELDED rig parts -- a rig is an anchored root with unanchored children
--     welded to it; the anim moves the root's CFrame and the welds carry the
--     children. Anchor a welded child and it stops following -> anim freezes.
--   * Any model with a Humanoid (the quest/garden NPCs) -- anchoring freezes them.
--   * Tools + Accessories -- must stay loose to weld to the player.
--
-- TWO PASSES:
--   Pass 1 runs immediately (static island geometry).
--   Pass 2 runs after a short delay, to catch props spawned after startup
--     (community garden, gardeners, geysers, quest props). Same skip rules.
--======================================================================

local Workspace = game:GetService("Workspace")

-- All island models. CandyRealm names them "island1".."island13" (lowercase, no
-- suffix); we also accept the "Island_1_<Name>" style. Match "^island_?%d+"
-- case-insensitively so both work.
local function isIslandName(name: string): boolean
	return string.lower(name):match("^island_?%d+") ~= nil
end
local function getIslands(): { Model }
	local out = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and isIslandName(d.Name) then
			out[#out + 1] = d
		end
	end
	return out
end

-- Every part that is the DRIVEN side of a weld (Part1) is held by that weld --
-- anchoring it would break the rig. Build this set ONCE per pass; checking it
-- per-part by rescanning Workspace would be O(parts x descendants) and stall
-- startup on the bigger islands.
local function buildWeldedSet(): { [BasePart]: boolean }
	local welded = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") then
			if d.Part1 then welded[d.Part1] = true end
		end
	end
	return welded
end

-- A part is "static" only if nothing else is driving it: not welded to another
-- part, not inside a Tool/Accessory, and not inside a model with a Humanoid (NPC).
local function isStatic(part: BasePart, welded: { [BasePart]: boolean }): boolean
	if welded[part] then return false end
	if part:FindFirstAncestorWhichIsA("Tool") then return false end
	if part:FindFirstAncestorWhichIsA("Accessory") then return false end

	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildWhichIsA("Humanoid") then return false end
		model = model:FindFirstAncestorWhichIsA("Model")
	end

	return true
end

-- Anchor every static BasePart under all discovered islands. Returns count changed.
local function anchorPass(label: string): number
	local welded = buildWeldedSet()
	local islands = getIslands()
	if #islands == 0 then
		warn(("[Anchor][%s] no island<N> models found in Workspace yet"):format(label))
		return 0
	end
	local total = 0
	for _, isl in ipairs(islands) do
		local n = 0
		for _, d in ipairs(isl:GetDescendants()) do
			if d:IsA("BasePart") and not d.Anchored and isStatic(d, welded) then
				d.Anchored = true; n += 1
			end
		end
		total += n
		if n > 0 then
			print(("[Anchor][%s] %s -> anchored %d part(s)"):format(label, isl.Name, n))
		end
	end
	return total
end

-- PASS 1: static island geometry, right now.
local total = anchorPass("pass1")
print(("[Anchor] pass1 done -- %d part(s) anchored (welds/NPCs/tools skipped)"):format(total))

-- PASS 2: catch props spawned AFTER pass 1 (garden props, gardeners, geysers).
task.spawn(function()
	task.wait(8)
	local n = anchorPass("pass2")
	print(("[Anchor] pass2 done -- %d late-spawned part(s) anchored"):format(n))
end)

-- Anchor any food "Stand" models so they never fall apart (matches "Stand", "stand", "Stand8", ...).
do
	local n = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d.Name:lower():match("^stand%d*$") then
			if d:IsA("BasePart") then d.Anchored = true; n += 1 end
			for _, p in ipairs(d:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true; n += 1 end end
		end
	end
	if n > 0 then print(("[Anchor] anchored %d 'Stand' part(s)"):format(n)) end
end
