--!strict
--======================================================================
-- Constants.luau  (ReplicatedStorage.Shared.Constants)  -- CandyRealm
-- SPACE-REALM PORT: only the economy constants. Merge these into your existing
-- Constants file rather than replacing it -- everything else in there is untouched.
--======================================================================

local Constants = {}

-- ===== STARTING STATE =====
-- Tier 1 is the GROUNDED GATE: maxPower = 0, so a fresh player cannot fly at all until the
-- first island's quest grants them tier 2. This is deliberate and load-bearing -- it stops a
-- new player from farming flight coins before they have touched a minigame, which is the one
-- route that would let flight money buy a gut and collapse the two-purse design.
Constants.STARTING_STOMACH_TIER = 1 -- index into StomachTiers.CANDY_GUTS

-- Enough to buy ~1 slot-1 food (110) so the loop can start; no arrival grants beyond this.
Constants.STARTING_COINS = 150

-- Empty tank. You buy your first food with the starting coins.
Constants.STARTING_POWER = 0

-- ===== FLIGHT GATE =====
-- Headroom above your island's surface. Enough to fly around it and land comfortably, far
-- less than the 1,400-stud smallest gap, so headroom can never become a free ride upward.
Constants.CEILING_MARGIN = 400

-- The next island always stays at least this far out of reach, even with a ceiling-raising
-- event (Sugar Rush, a x1.5 buff). Callers that scale the ceiling clamp to the lid.
Constants.LID_CLEARANCE = 250

-- ===== SANITY =====
-- The smallest gap in the tower. CEILING_MARGIN + LID_CLEARANCE must stay well under this or
-- a ceiling-raising event can hand a player the next island for free.
Constants.SMALLEST_GAP = 1400

if game:GetService("RunService"):IsServer() then
	if Constants.CEILING_MARGIN + Constants.LID_CLEARANCE >= Constants.SMALLEST_GAP then
		warn(("[Constants] CEILING_MARGIN (%d) + LID_CLEARANCE (%d) >= smallest gap (%d) -- "
			.. "a buffed ceiling could reach the next island for free")
			:format(Constants.CEILING_MARGIN, Constants.LID_CLEARANCE, Constants.SMALLEST_GAP))
	end
	print(("[Constants] start: tier=%d coins=%d power=%d | ceiling margin=%d lid=%d")
		:format(Constants.STARTING_STOMACH_TIER, Constants.STARTING_COINS, Constants.STARTING_POWER,
			Constants.CEILING_MARGIN, Constants.LID_CLEARANCE))
end

return Constants
