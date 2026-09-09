--!strict
--======================================================================
-- StomachTiers.luau  (ReplicatedStorage.Shared.StomachTiers)  -- CandyRealm
-- SPACE-REALM PORT: 12 guts for 12 islands.
--======================================================================
-- This is the Space Realm's StomachTiers with candy names and four more rungs.
-- Every rule below is the space rule; nothing here is a candy invention.
--
-- ===== WHAT A TIER IS =====
-- "Gut tier" == how much power the player can hold (maxPower), which gates how far
-- they can fly. TWELVE tiers, one per island:
--   * Tier 1 is the STARTING tier. maxPower = 0 ON PURPOSE -- a grounded gate. You
--     cannot fly, and so cannot farm flight coins, until the first island's quest
--     grants you tier 2. (Space does exactly this with Astro Stomach 1.)
--   * Tiers 2..12 are BOUGHT with coins from the GUT panel. Completing an island's
--     QUEST pays out exactly that tier's `cost` (see the task-completion grant), so
--     you buy your own gut -- but the buy is QUEST-GATED, so you must actually play
--     the minigame that funds it. Flight coins alone can never skip a rung.
--
-- Which island's quest funds+gates each tier lives in IslandConfig.gutUnlock.unlocksTier
-- (slot 1 -> tier 2, ... slot 11 -> the capstone tier 12).
--
-- ===== HOW THE CAPACITIES WERE DERIVED (do not hand-edit) =====
-- A full tank climbs maxPower x STUDS_PER_POWER (2.16, measured on the space flight
-- model), and each tier exists to make ONE hop across IslandOrder.GAPS[i]. The space
-- rule is that EVERY TANK CLEARS ITS GAP BY THE SAME ~18% MARGIN:
--
--       maxPower = ceil10( gap * 1.18 / 2.16 )
--
-- That formula reproduces the Space Realm's eight capacities EXACTLY
-- (770/1100/1530/2080/2740/3500/4380) and generates the four new ones. A uniform
-- margin is the point: the old space numbers cleared their gaps by anywhere from
-- 2.6% to 48%, which meant tier 3 was a trap (any gas spent steering left you short
-- of the island you had just bought the correct gut for) while tier 8's surplus
-- bought nothing at all.
--
-- ===== THE WALL IS THE CEILING, NOT THE REACH =====
-- This is the biggest difference from the OLD candy/dino solve. There, guts were
-- mandatory because no tank could physically reach the gap above its own -- a
-- constraint that forced gaps to grow by MORE than 8% and made the whole band solve
-- fragile. Here, reach is deliberately generous (+18% on every rung) and the gate is
-- getMaxHeight(): a hard ceiling at YOUR island + 400 studs. The next island sits a
-- full gap beyond that, so it is unreachable no matter how much power you carry --
-- bubbles, 2x Power, a mid-air refuel, none of it matters. The only way up is the
-- next gut, and the only thing that pays for the next gut is the next quest.
--======================================================================

local StomachTiers = {}

export type Tier = {
	name: string,
	maxPower: number,
	cost: number,
	tankSeconds: number,
}

-- Ordered list; array index == tier number. Tier 1 = the grounded start.
--   maxPower    = tank capacity (raw fuel cap), from the formula above.
--   cost        = coin price, and ALSO exactly what that island's quest pays out.
--   tankSeconds = how long a full tank lasts. The per-second 0-100 meter drain is
--                 100/tankSeconds, so higher tiers burn LONGER and climb FARTHER.
--
-- Tiers 1-8 are the Space Realm's numbers VERBATIM. Tiers 9-12 continue every curve:
--   * maxPower  by the ceil10(gap * 1.18 / 2.16) formula
--   * cost      by continuing cost/maxPower (0.902 -> 0.943, +0.01 per rung)
--   * tankSecs  by continuing the +2-seconds-every-two-rungs cadence
StomachTiers.CANDY_GUTS = {
	{ name = "Gumdrop Belly",      maxPower = 0,    cost = 0,    tankSeconds = 28 }, -- START: max=0 is the grounded gate (no flight until slot 1's quest grants tier 2)
	{ name = "Taffy Tummy",        maxPower = 770,  cost = 450,  tankSeconds = 28 }, -- clears the 1400 gap (reach 1663). cost = what slot 1's quest pays.
	{ name = "Cookie Gut",         maxPower = 1100, cost = 750,  tankSeconds = 30 }, -- 2000 gap
	{ name = "Jelly Belly",        maxPower = 1530, cost = 1200, tankSeconds = 34 }, -- 2800 gap
	{ name = "Gummy Gut",          maxPower = 2080, cost = 1750, tankSeconds = 38 }, -- 3800 gap
	{ name = "Choco Stomach",      maxPower = 2740, cost = 2400, tankSeconds = 44 }, -- 5000 gap
	{ name = "Caramel Core",       maxPower = 3500, cost = 3100, tankSeconds = 50 }, -- 6400 gap
	{ name = "Marshmallow Middle", maxPower = 4380, cost = 3950, tankSeconds = 58 }, -- 8000 gap (last space rung)
	{ name = "Fudge Furnace",      maxPower = 5360, cost = 4900, tankSeconds = 66 }, -- 9800 gap   (NEW)
	{ name = "Licorice Loop",      maxPower = 6450, cost = 5950, tankSeconds = 76 }, -- 11800 gap  (NEW)
	{ name = "Peppermint Pit",     maxPower = 7650, cost = 7150, tankSeconds = 86 }, -- 14000 gap  (NEW)
	{ name = "Nougat Nova",        maxPower = 8960, cost = 8450, tankSeconds = 98 }, -- capstone: 16400 gap to the summit (slot 11's quest funds it)
} :: { Tier }

-- The SUGAR RUSH tier -- candy's Infinite Gut. Not part of the normal chain; granted only
-- when the player arrives from FtF with the flag set, or buys the Robux pass. Locked at
-- infinite power so the meter effectively never caps.
StomachTiers.SUGAR_RUSH = { name = "Sugar Rush Gut", maxPower = math.huge, cost = 0, tankSeconds = math.huge } :: Tier

-- Number of normal (non-infinite) tiers.
StomachTiers.MAX_TIER = #StomachTiers.CANDY_GUTS

-- Back-compat aliases so anything still calling the old candy API keeps working.
StomachTiers.LIST = StomachTiers.CANDY_GUTS
StomachTiers.BY_NAME = {}
StomachTiers.NAME_BY_MAX = {}
for _, tier in ipairs(StomachTiers.CANDY_GUTS) do
	StomachTiers.BY_NAME[tier.name] = tier
	StomachTiers.NAME_BY_MAX[tier.maxPower] = tier.name
end
StomachTiers.BY_NAME[StomachTiers.SUGAR_RUSH.name] = StomachTiers.SUGAR_RUSH

--[[ Return the Tier definition for a given tier index, clamped to range. ]]
function StomachTiers.getTier(index: number): Tier
	local i = math.clamp(index, 1, StomachTiers.MAX_TIER)
	return StomachTiers.CANDY_GUTS[i]
end

--[[ Look a tier up by tank size -- the server reads the PRICE off its own table, so a
     client-sent cost can never change what it pays. ]]
function StomachTiers.byMaxPower(maxPower: number): Tier?
	local target = tonumber(maxPower)
	if not target then
		return nil
	end
	for _, tier in ipairs(StomachTiers.CANDY_GUTS) do
		if tier.maxPower == target then
			return tier
		end
	end
	return nil
end

--[[
	Resolve the effective tier for a player-state-like table.
	Honors sugarRush (candy's Infinite Gut): if set, returns SUGAR_RUSH regardless of the
	stored index. The Unlimited Gut gamepass (unlimitedGut) forces the HIGHEST normal tier
	WITHOUT touching the stored tier -- a pure runtime override re-derived each join, so a
	refund self-corrects and nothing persists.
]]
function StomachTiers.resolveForState(state: { sugarRush: boolean?, unlimitedGut: boolean?, stomachTier: number }): Tier
	if state.sugarRush then
		return StomachTiers.SUGAR_RUSH
	end
	if state.unlimitedGut then
		return StomachTiers.CANDY_GUTS[StomachTiers.MAX_TIER]
	end
	return StomachTiers.getTier(state.stomachTier)
end

--[[ Convenience: the power cap for a state, respecting both overrides. ]]
function StomachTiers.getMaxPower(state: { sugarRush: boolean?, unlimitedGut: boolean?, stomachTier: number }): number
	return StomachTiers.resolveForState(state).maxPower
end

-- ===== THE LADDER: ONE TANK PER ISLAND =====
-- Surface Y of every island, in climb order. MUST MATCH IslandOrder.SLOT_POS -- that table
-- does the actual moving, and this one is checked against it at boot.
--
-- Tier i is THE TANK FOR SLOT i: tier 1 is where you start, tier 2 is what gets you to
-- slot 2, ... tier 12 is what gets you to the summit. Every island's quest unlocks the next
-- tank, so the ladder is quest -> tank -> island -> quest.
StomachTiers.ISLAND_LADDER = {
	{ name = "Candy Cane Court",    y = 220 },
	{ name = "Gumdrop Grove",       y = 1620 },
	{ name = "Cookie Crumble",      y = 3620 },
	{ name = "Gumtree Park",        y = 6420 },
	{ name = "Taffy Town",          y = 10220 },
	{ name = "Crystal Candy Caves", y = 15220 },
	{ name = "Chocolate Chasm",     y = 21620 },
	{ name = "Sherbet Shelf",       y = 29620 },
	{ name = "Licorice Tunnels",    y = 39420 },
	{ name = "Frostbell Peak",      y = 51220 },
	{ name = "Marshmallow Camp",    y = 65220 },
	{ name = "Bakery Summit",       y = 81620 },
}

-- Headroom above your island's surface: enough to fly around it and land comfortably, far
-- less than the 1400-stud smallest gap, so headroom can never become a free ride upward.
local CEILING_MARGIN = 400
-- The next island always stays at least this far out of reach, even with a ceiling-raising event.
local LID_CLEARANCE = 250

-- Which island this state is cleared for. The tier INDEX is the ladder index -- the two
-- tables are the same length on purpose (12 tanks, 12 islands).
local function ladderIndexFor(state): number
	if state.sugarRush or state.unlimitedGut then
		return #StomachTiers.ISLAND_LADDER -- both passes fly the whole tower
	end
	local tier = tonumber(state.stomachTier) or 1
	return math.clamp(math.floor(tier), 1, #StomachTiers.ISLAND_LADDER)
end

--[[
	HARD CEILING -- the real flight gate, and the thing that makes each tank REQUIRED.

	The ceiling is the island you are cleared for: your tier's island + CEILING_MARGIN. The
	next island sits at least a full gap beyond that, so it is unreachable no matter how much
	power you carry -- the only way up is the next tank, which is the only thing the next
	island's quest can give you.
]]
function StomachTiers.getMaxHeight(state: { sugarRush: boolean?, unlimitedGut: boolean?, stomachTier: number }): number
	return StomachTiers.ISLAND_LADDER[ladderIndexFor(state)].y + CEILING_MARGIN
end

--[[
	The NEVER-EXCEED lid for this tier, whatever else is going on. A SUGAR RUSH event
	multiplies the ceiling, and "fly higher than ever" must not quietly mean "skip a gut" --
	a x1.5 on Taffy Town's ceiling would clear Crystal Candy Caves. Callers that scale the
	ceiling clamp the result to this. The top tier has no lid.
]]
function StomachTiers.getCeilingLid(state: { sugarRush: boolean?, unlimitedGut: boolean?, stomachTier: number }): number
	local i = ladderIndexFor(state)
	local nextIsland = StomachTiers.ISLAND_LADDER[i + 1]
	if not nextIsland then
		return math.huge
	end
	return nextIsland.y - LID_CLEARANCE
end

--[[ Has this player climbed far enough to be allowed to buy this tier? Gating on REACH
     (highest slot), not on owning the previous tier, means the ladder cannot be skipped but
     can still be back-filled. ]]
function StomachTiers.isUnlocked(tier: Tier?, highestSlot: number?): boolean
	if not tier then
		return false
	end
	if tier == StomachTiers.SUGAR_RUSH then
		return true
	end
	local index = table.find(StomachTiers.CANDY_GUTS, tier)
	if not index then
		return false
	end
	-- Tier k is bought while standing on slot k-1 (its quest is the one that funds it).
	return math.floor(tonumber(highestSlot) or 1) >= (index - 1)
end

-- ===== BOOT AUDITS (server only -- no client spam) =====
-- Empirical flight reach: a full tank of `maxPower` climbs ~STUDS_PER_POWER studs per power.
-- TIER_GAP[i] is the gap INTO the island whose quest unlocks tier i -- i.e. the gap a full
-- tier-i tank must clear. Tier 1 = the start (no inbound gap).
local STUDS_PER_POWER = 2.16
local TIER_GAP = { 0, 1400, 2000, 2800, 3800, 5000, 6400, 8000, 9800, 11800, 14000, 16400 }

if game:GetService("RunService"):IsServer() then
	for _, tier in ipairs(StomachTiers.CANDY_GUTS) do
		print(("[Gut] %s: max=%d cost=%d tankSec=%d drain=%.2f/s")
			:format(tier.name, tier.maxPower, tier.cost, tier.tankSeconds, 100 / tier.tankSeconds))
	end
	print("[Gut] tier 1 max=0 (grounded gate -- no flight until tier 2 is earned from the first quest)")

	-- REACH-vs-GAP: does a full tank physically clear the gap it is meant to? The MARGIN is
	-- the number to watch, not just pass/fail -- a tank that clears by 2% is one fumbled
	-- takeoff away from stranding a player who bought exactly the right upgrade.
	for i, tier in ipairs(StomachTiers.CANDY_GUTS) do
		local reach = tier.maxPower * STUDS_PER_POWER
		local gap = TIER_GAP[i] or 0
		local verdict = (gap == 0) and "start (no gap)" or (reach >= gap and "CLEARS" or "SHORT")
		local margin = (gap > 0) and ((reach / gap - 1) * 100) or 0
		print(("[Gut] %s reach=%.0f (max %d x %.2f) vs gap=%d -> %s%s")
			:format(tier.name, reach, tier.maxPower, STUDS_PER_POWER, gap, verdict,
				(gap > 0) and (" (+%.0f%% margin)"):format(margin) or ""))
		if gap > 0 and margin < 10 then
			warn(("[Gut] %s only clears its gap by %.0f%% -- too tight to survive a sloppy takeoff")
				:format(tier.name, margin))
		end
	end

	-- CEILING-vs-LADDER: every tank must reach ITS island and NO further. This is the audit
	-- that catches a ceiling formula handing tier 2 a height three islands up.
	for i, island in ipairs(StomachTiers.ISLAND_LADDER) do
		local state = { stomachTier = i }
		local ceiling = StomachTiers.getMaxHeight(state)
		local nextIsland = StomachTiers.ISLAND_LADDER[i + 1]
		local reachesOwn = ceiling >= island.y
		local reachesNext = nextIsland ~= nil and ceiling >= nextIsland.y
		print(("[Gut] tier %d ceiling=%d -> %s(%d) %s%s")
			:format(i, ceiling, island.name, island.y,
				reachesOwn and "OK" or "SHORT OF ITS OWN ISLAND",
				reachesNext and (" -- WARNING: also reaches " .. nextIsland.name) or ""))
		if (not reachesOwn) or reachesNext then
			warn(("[Gut] tier %d's ceiling is wrong: it must reach %s and stop short of the next island")
				:format(i, island.name))
		end
	end

	-- LADDER-vs-ISLANDORDER: the two Y tables must agree or the ceiling gates the wrong place.
	local ok, IslandOrder = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("IslandOrder"))
	end)
	if ok and IslandOrder and IslandOrder.SLOT_POS then
		for i, island in ipairs(StomachTiers.ISLAND_LADDER) do
			local pos = IslandOrder.SLOT_POS[i]
			if not pos or pos.Y ~= island.y then
				warn(("[Gut] HEIGHT DRIFT: slot %d is %s in IslandOrder but %d in ISLAND_LADDER -- "
					.. "the flight ceiling is derived from this table, so fix one of them")
					:format(i, pos and tostring(pos.Y) or "missing", island.y))
			end
		end
	end
end

return StomachTiers
