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

-- WAIT FOR THE TOWER TO BE BUILT FIRST.
-- IslandLayout's header says "RUNS FIRST", but Roblox does not guarantee server
-- Script start order -- and "AnchorIslands" sorts before "IslandLayout", so the
-- opposite is the likely case. Anchoring an island at its Studio CFrame and then
-- moving it is not itself harmful (PivotTo carries anchored parts), but anything
-- this pass touches BETWEEN the two is being anchored against coordinates that
-- are about to become wrong. Waiting removes the ambiguity entirely.
--
-- Bounded, not infinite: if IslandLayout is missing or errored, anchoring islands
-- in place is still much better than never anchoring them at all.
do
	local t0 = os.clock()
	while not _G.islandsPositioned and os.clock() - t0 < 15 do
		task.wait(0.1)
	end
	if not _G.islandsPositioned then
		warn("[Anchor] IslandLayout never set _G.islandsPositioned (15s) -- anchoring at current positions")
	end
end

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

-- ============================================================================
-- FORCE-ANCHOR WHOLE ISLANDS -- pass1's skip rules do not apply here
-- ============================================================================
-- pass1 anchored 254 parts on island16 and left the rest alone, because the rest are the DRIVEN
-- side of welds -- and pass1 treats "welded" as "something animates this, leave it". On a built
-- island that assumption is simply wrong: a welded staircase, a welded shopfront and a welded
-- rock arch are scenery, and leaving them loose is what lets them sag, drift and fall.
--
-- Islands listed here get EVERY BasePart anchored, welded or not. Add an island number when the
-- island is finished scenery rather than a set of moving props.
local FORCE_ANCHOR_ISLANDS = { 16 }

do
	local want = {}
	for _, n in ipairs(FORCE_ANCHOR_ISLANDS) do want["island" .. n] = true end

	for _, isl in ipairs(getIslands()) do
		if want[isl.Name:lower()] then
			local anchored, skippedTool, skippedNpc = 0, 0, 0
			for _, d in ipairs(isl:GetDescendants()) do
				if d:IsA("BasePart") and not d.Anchored then
					-- ⚠ TWO THINGS STAY LOOSE EVEN HERE, because anchoring them does not freeze
					-- them, it BREAKS them:
					--   * Tools / Accessories -- they have to weld themselves to the player's
					--     hand. An anchored tool cannot be picked up at all.
					--   * A Humanoid rig -- island16's Candy Npc waves through a shoulder Motor6D.
					--     A motor moves the CHILD, and an anchored child ignores it, so the arm
					--     would lock solid. NpcLife already anchors the NPC's ROOT, which is what
					--     actually stops it wandering off.
					if d:FindFirstAncestorWhichIsA("Tool") or d:FindFirstAncestorWhichIsA("Accessory") then
						skippedTool += 1
					elseif d:FindFirstAncestorWhichIsA("Model")
						and d:FindFirstAncestorWhichIsA("Model"):FindFirstChildWhichIsA("Humanoid") then
						skippedNpc += 1
					else
						d.Anchored = true
						anchored += 1
					end
				end
			end
			print(("[Anchor][force] %s -> anchored %d more part(s) INCLUDING welded ones"
				.. " (left loose: %d tool/accessory, %d humanoid-rig)")
				:format(isl.Name, anchored, skippedTool, skippedNpc))
		end
	end
end

-- PASS 2: catch props spawned AFTER pass 1 (garden props, gardeners, geysers).
task.spawn(function()
	task.wait(8)
	local n = anchorPass("pass2")
	print(("[Anchor] pass2 done -- %d late-spawned part(s) anchored"):format(n))
end)

-- ============================================================================
-- ALWAYS-ANCHOR BY NAME -- the override for things pass1 deliberately skips
-- ============================================================================
-- pass1 will not touch a part that is the driven side of a WELD, because that is how animated
-- rigs work and anchoring one freezes it. That rule is right in general and wrong for a couple
-- of specific things people build in Studio:
--
--   * "Stand"  -- the food stands. Welded assemblies that must never sag or fall apart.
--   * "Stairs" -- island16's four stair parts. Same story: a welded staircase counts as
--                "driven by something else", so pass1 skipped all four and they were free to
--                drift or fall the moment anything touched them. Stairs you walk up are
--                scenery, never animation.
--
-- Matched on NAME, realm-wide, and applied to the part AND its descendants, so it works whether
-- you named a single Part or a Model full of them. Trailing digits are allowed, so "Stairs",
-- "stairs" and "Stairs3" all match -- but nothing longer, so a "StairsRailingAnimated" is safe.
do
	local ALWAYS_ANCHOR = { "^stand%d*$", "^stairs%d*$" }
	local counts = {}
	local function anchorNamed(inst)
		local n = 0
		if inst:IsA("BasePart") then inst.Anchored = true; n += 1 end
		for _, p in ipairs(inst:GetDescendants()) do
			if p:IsA("BasePart") then p.Anchored = true; n += 1 end
		end
		return n
	end
	for _, d in ipairs(Workspace:GetDescendants()) do
		local nm = d.Name:lower()
		for _, pat in ipairs(ALWAYS_ANCHOR) do
			if nm:match(pat) then
				local key = d.Name
				counts[key] = (counts[key] or 0) + anchorNamed(d)
				break
			end
		end
	end
	for name, n in pairs(counts) do
		print(("[Anchor] anchored %d part(s) named '%s' (always-anchor list -- overrides the weld skip)")
			:format(n, name))
	end
end

-- ============================================================================
-- LOOSE PARTS BESIDE AN ISLAND -- the hole in "anchor everything"
-- ============================================================================
-- anchorPass() walks island MODELS, so a part that sits next to an island but is parented
-- directly to Workspace is never touched by it. That is not a rare mistake: it is what happens
-- every time something is dragged into place in Studio and not re-parented, and IslandStreaming's
-- own boot audit routinely counts a hundred-plus of them. Unanchored, they fall the moment
-- physics wakes up; the island looks fine and the props are gone.
--
-- WHY THIS IS BOUNDED BY DISTANCE rather than just anchoring every loose part in Workspace:
-- Workspace's root also holds things that are SUPPOSED to move, and "anchor everything in the
-- game" is a much bigger claim than "anchor the scenery someone dropped next to an island".
-- 600 studs is comfortably wider than any island and far narrower than the gaps between them
-- (the tower's rungs are thousands of studs apart), so a part can only ever be claimed by the
-- island it is actually sitting on.
--
-- isStatic still applies, so welded rigs, Tools, Accessories and anything under a Humanoid are
-- left alone -- a dropped hat or a loose NPC must stay dynamic.
local LOOSE_RADIUS = 600

local function anchorLoose(label: string): number
	local islands = getIslands()
	if #islands == 0 then return 0 end
	local welded = buildWeldedSet()

	local centres = {}
	for _, isl in ipairs(islands) do
		local ok, cf = pcall(function() return isl:GetPivot() end)
		if ok then centres[#centres + 1] = cf.Position end
	end

	local function nearAnIsland(pos: Vector3): boolean
		for _, c in ipairs(centres) do
			if (pos - c).Magnitude <= LOOSE_RADIUS then return true end
		end
		return false
	end

	local n, sample = 0, nil
	local function consider(p: BasePart)
		if p.Anchored or not isStatic(p, welded) then return end
		if not nearAnIsland(p.Position) then return end
		p.Anchored = true; n += 1
		sample = sample or p.Name
	end

	for _, d in ipairs(Workspace:GetChildren()) do
		if d:IsA("BasePart") then
			consider(d)
		elseif d:IsA("Model") and not isIslandName(d.Name) then
			-- a loose Model (a prop kit, a bit of scenery) counts too, but only if it is not a
			-- character: isStatic rejects anything under a Humanoid, so those cost one check.
			for _, p in ipairs(d:GetDescendants()) do
				if p:IsA("BasePart") then consider(p) end
			end
		end
	end

	if n > 0 then
		print(("[Anchor][%s] %d loose part(s) beside an island anchored (e.g. '%s'). These are "
			.. "parented to Workspace, NOT into an island Model -- they are held now, but they "
			.. "still cannot inherit Persistent streaming, so drag them into the island in Studio.")
			:format(label, n, tostring(sample)))
	end
	return n
end

anchorLoose("loose1")
task.spawn(function()
	task.wait(8)                    -- same beat as pass2: catch anything that arrived late
	anchorLoose("loose2")
end)
