--!strict
--======================================================================
-- FlightPayout.luau  (ReplicatedStorage.Shared.FlightPayout)  -- CandyRealm
-- SPACE-REALM PORT: the coins-earned model, verbatim.
--======================================================================
-- ===== THE INCOME MODEL =====
--
--     coins per flight = floor(powerBurned * payoutPerPower)
--
-- `powerBurned` is the FOOD POWER spent during the flight -- NOT how high you climbed.
-- This is the single most important difference from the old candy economy, which paid
-- COIN_PER_STUD = 0.14 per stud of altitude gained.
--
-- WHY POWER, NOT ALTITUDE. Paying per stud pays for FLYING WELL. Two players who buy the
-- same food and burn the same tank get different money because one steered straighter, and
-- a player who bounces off the ceiling burning fuel gets nothing at all. Paying per power
-- burned makes income a function of what you SPENT, so a clean flight and a clumsy one on
-- the same tank pay the same. Food is the input, coins are the output, and skill affects
-- whether you ARRIVE -- not whether you can afford the next tank.
--
-- It also makes the ceiling safe. Under the space model the hard ceiling stops you dead at
-- your island + 400 studs; under a per-stud model that ceiling would also cap your income,
-- so the last stretch of every island would pay nothing.
--
-- ===== THE RATE =====
-- payoutPerPower is chosen by the island the player is progressing FROM (highestSlot, 1..12).
-- Each rate is set so a flight nets SLIGHTLY POSITIVE -- you can never be stranded -- while
-- the food price curve means a gap-clearing tank fill costs nearly your whole banked total.
-- You arrive at the next island drained to near zero, which is what makes the next island's
-- quest money feel like money.
--
-- Slots 1-7 are the Space Realm's rates verbatim. Slots 8-11 continue its ~x1.27 per-rung
-- growth. Slot 12 is the summit: no flight onward is needed, so like Neptune it MIRRORS the
-- rate below rather than being zero, in case the player still flies there.
--
--     slot:    1     2     3     4     5     6     7      8      9     10     11     12
--     rate:  1.9   2.3   2.9   3.7   4.8   6.1   7.8    9.9   12.6   16.0   20.3   20.3
--                                                       ^^^^^^ new, x1.27 per rung ^^^^^
--
-- ===== R IS THE NUMBER TO PROTECT =====
--     R = (power * payoutPerPower) / price      -- what a serving earns / what it costs
-- R must stay above 1 at every slot or a flight costs more than it earns and the player
-- spirals down. CandyData's prices are SOLVED from this table to hold R on the space curve
-- (1.47 -> 1.35 -> 1.75, plateauing at 1.749 from slot 7 up). CHANGE A RATE HERE AND YOU
-- MUST RE-SOLVE CandyData.FOODS -- the boot audit below will tell you if you did not.
--======================================================================

local FlightPayout = {}

-- Indexed by climb slot (1..12).
FlightPayout.PER_POWER = { 1.9, 2.3, 2.9, 3.7, 4.8, 6.1, 7.8, 9.9, 12.6, 16.0, 20.3, 20.3 }

-- Per-flight cap, set high so it never binds in normal play -- it exists to bound an exploit,
-- not to shape the curve.
FlightPayout.FLIGHT_COIN_CAP = 250000

-- Seconds between airborne-state samples for the live "+N coins" readout.
FlightPayout.COIN_CHECK_INTERVAL = 0.2

-- The R the price curve is solved to hold from slot 7 upward.
FlightPayout.TARGET_R = 1.749

--[[ The rate for a player who has reached `highestSlot`, clamped into range. ]]
function FlightPayout.rateForSlot(highestSlot: number?): number
	local slot = math.clamp(math.floor(tonumber(highestSlot) or 1), 1, #FlightPayout.PER_POWER)
	return FlightPayout.PER_POWER[slot]
end

--[[ Base coins for a flight: floor(powerBurned * rate), capped. ]]
function FlightPayout.coinsFor(powerBurned: number, highestSlot: number?): number
	local burned = math.max(0, tonumber(powerBurned) or 0)
	local rate = FlightPayout.rateForSlot(highestSlot)
	return math.min(math.floor(burned * rate), FlightPayout.FLIGHT_COIN_CAP)
end

-- Boot audit: print the whole economy line by line and warn if R ever falls to 1.
if game:GetService("RunService"):IsServer() then
	local ok, CandyData = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CandyData"))
	end)
	print("[Econ] income model = coins per POWER BURNED (not per stud)")
	if ok and CandyData then
		for slot, food in ipairs(CandyData.FOODS) do
			local rate = FlightPayout.PER_POWER[slot] or FlightPayout.PER_POWER[#FlightPayout.PER_POWER]
			local r = (food.power * rate) / food.price
			print(("[Econ] slot %2d %-15s power=%d price=%d payout=%.1f R=%.3f")
				:format(slot, food.name, food.power, food.price, rate, r))
			if r <= 1.05 then
				warn(("[Econ] slot %d (%s) has R=%.3f -- a flight barely pays for its own fuel; "
					.. "players will spiral down here"):format(slot, food.name, r))
			end
		end
	end
	print(("[Econ] flightCoinCap=%d, targetR=%.3f"):format(FlightPayout.FLIGHT_COIN_CAP, FlightPayout.TARGET_R))
end

return FlightPayout
