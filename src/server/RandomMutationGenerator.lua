--======================================================================
-- RandomMutationGenerator.lua  (ModuleScript)
--======================================================================
-- PURE LOGIC, NO SIDE EFFECTS. The shared weighted random picker for the
-- global "MutationEvent". Given the CONFIG mutation tables (the COSMETIC
-- list, the GUARDED list, their weights + durations) it returns picks that
-- the server uses to drive NPC chaos + storm strength and that it forwards
-- to clients (which actually APPLY player mutations).
--
-- This module:
--   * NEVER touches Instances, the DataModel, RemoteEvents, _G, the fart
--     meter, power, flight, coins, NPCs, or the world. It only reads the
--     CONFIG tables it is given and returns plain Lua tables describing a
--     pick. All application/timing/replication lives elsewhere.
--   * Is deterministic-ish only through math.random; callers seed if needed.
--
-- A "pick" returned by this module looks like:
--   { id = "giant_arms", group = "cosmetic"|"guarded", duration = <sec>,
--     magnitude = <number or nil>, strong = <bool> }
-- where `magnitude` comes straight from the CONFIG entry (already gentle +
-- capped by the manager's CONFIG), and `strong` marks a storm-boosted pick.
--======================================================================

local RandomMutationGenerator = {}

-- CONFIG is injected by init(); we keep a reference so the pure pickers can
-- read the COSMETIC_MUTATIONS / GUARDED_MUTATIONS lists + ULTIMATE settings.
local CONFIG = nil

--------------------------------------------------------------------
-- init(config): store the CONFIG reference. No other side effects.
--------------------------------------------------------------------
function RandomMutationGenerator.init(config)
	CONFIG = config
end

--------------------------------------------------------------------
-- weightedPick(list): given a list of entries each with a numeric `weight`
-- (default 1), return ONE entry chosen proportionally to its weight. Pure.
-- Returns nil if the list is empty.
--------------------------------------------------------------------
local function weightedPick(list)
	if not list or #list == 0 then return nil end
	local total = 0
	for _, entry in ipairs(list) do
		total = total + (entry.weight or 1)
	end
	if total <= 0 then return list[math.random(1, #list)] end
	local roll = math.random() * total
	local acc = 0
	for _, entry in ipairs(list) do
		acc = acc + (entry.weight or 1)
		if roll <= acc then
			return entry
		end
	end
	return list[#list] -- numerical safety fallback
end

--------------------------------------------------------------------
-- toPick(entry, group, strong): shape a CONFIG entry into a normalized pick
-- table. If `strong` (storm-boosted) we lengthen the duration a touch and
-- flag it; the CLIENT still enforces ALL guarded safety rules + the height
-- cap regardless of `strong`, so this only changes flavour/intensity.
--------------------------------------------------------------------
local function toPick(entry, group, strong)
	if not entry then return nil end
	local dur = entry.duration or 6
	if strong then
		dur = dur * (CONFIG and CONFIG.STORM_DURATION_MULT or 1.4)
	end
	return {
		id = entry.id,
		group = group,
		duration = dur,
		magnitude = entry.magnitude, -- already gentle/capped in CONFIG; may be nil
		strong = strong == true,
	}
end

--------------------------------------------------------------------
-- rollCosmetic(): pick one COSMETIC mutation (safe, may apply anytime, may
-- stack). Returns a normalized pick or nil.
--------------------------------------------------------------------
function RandomMutationGenerator.rollCosmetic(strong)
	if not CONFIG then return nil end
	local entry = weightedPick(CONFIG.COSMETIC_MUTATIONS)
	return toPick(entry, "cosmetic", strong)
end

--------------------------------------------------------------------
-- rollGuarded(): pick one GUARDED mutation (movement/fart-altering). The
-- client applies these ONLY while grounded + not flying, height-capped.
-- Returns a normalized pick or nil.
--------------------------------------------------------------------
function RandomMutationGenerator.rollGuarded(strong)
	if not CONFIG then return nil end
	local entry = weightedPick(CONFIG.GUARDED_MUTATIONS)
	return toPick(entry, "guarded", strong)
end

--------------------------------------------------------------------
-- rollPlayerMutation(strong): the main per-player roll. First rolls the rare
-- ULTIMATE (capped by CONFIG.ULTIMATE_CHANCE); otherwise rolls cosmetic-vs-
-- guarded by CONFIG.GUARDED_PICK_CHANCE. Returns ONE normalized pick.
-- NOTE: the ULTIMATE pick is flagged group="ultimate" but the CLIENT still
-- treats its boosted fart/jump as GUARDED (grounded-only + height-capped).
--------------------------------------------------------------------
function RandomMutationGenerator.rollPlayerMutation(strong)
	if not CONFIG then return nil end

	-- Rare ULTIMATE roll.
	if math.random() < (CONFIG.ULTIMATE_CHANCE or 0) then
		return {
			id = "ultimate",
			group = "ultimate",
			duration = CONFIG.ULTIMATE_DURATION or 10,
			magnitude = CONFIG.ULTIMATE_GIANT_SCALE or 3,
			strong = strong == true,
		}
	end

	-- Otherwise choose which group to roll from.
	local chance = CONFIG.GUARDED_PICK_CHANCE or 0.4
	if math.random() < chance then
		return RandomMutationGenerator.rollGuarded(strong)
	end
	return RandomMutationGenerator.rollCosmetic(strong)
end

--------------------------------------------------------------------
-- rollNPCMutation(): NPC chaos picker. NPCs are server-side cosmetic/movement
-- mutations (grow/shrink/speed/bounce/glow/scream/combine). Returns one of a
-- fixed set of ids with a duration. Pure logic; NPCMutationSystem maps ids
-- onto actual NPC tweaks (and CAPTURES/restores originals).
--------------------------------------------------------------------
function RandomMutationGenerator.rollNPCMutation()
	local kinds = (CONFIG and CONFIG.NPC_MUTATIONS) or {}
	if #kinds == 0 then
		-- Safe built-in default set if CONFIG didn't provide one.
		kinds = {
			{ id = "grow",   weight = 1, duration = 8 },
			{ id = "shrink", weight = 1, duration = 8 },
			{ id = "speed",  weight = 1, duration = 8 },
			{ id = "bounce", weight = 1, duration = 8 },
			{ id = "glow",   weight = 1, duration = 8 },
			{ id = "scream", weight = 1, duration = 6 },
		}
	end
	local entry = weightedPick(kinds)
	if not entry then return nil end
	return { id = entry.id, duration = entry.duration or 8, magnitude = entry.magnitude }
end

--------------------------------------------------------------------
-- rollStormStrength(): returns true if a storm-struck target should get the
-- STRONGER mutation, per CONFIG.STORM_STRONG_CHANCE. Pure.
--------------------------------------------------------------------
function RandomMutationGenerator.rollStormStrength()
	return math.random() < (CONFIG and CONFIG.STORM_STRONG_CHANCE or 1)
end

return RandomMutationGenerator
