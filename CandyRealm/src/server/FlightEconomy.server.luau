--!nonstrict
--======================================================================
-- FlightEconomy.server.luau  (Server Script)  -- CandyRealm
-- FOOD-REALM PORT: the first realm's coin system, server half.
--======================================================================
-- Four jobs:
--
--   1. COINS EARNED WHILE FLYING -- paid PER STUD TRAVELLED (FlightTuning.COIN_PER_STUD = 3.52).
--      A landing pays the climb; a failed flight pays the climb x3 (the 2x descent bonus).
--      PropelSystem does the per-stud accounting (prepay, coin ticks, descent settle) and
--      fires CoinEvent with the amount, exactly as the food realm's CoreClient does. The
--      server VALIDATES rather than recomputes: NaN/inf/<=0 rejected, a single grant capped
--      at 8,000, calls rate-limited, and every 5-second window budgeted at "one full failed
--      flight on THIS player's gut during a 2x coin event" plus a flat allowance -- computed
--      from the server's own StomachMax, so the client cannot inflate it. It is a BOUND,
--      not authority; the food realm accepts the same trade.
--
--   2. FUEL BURNED WHILE FLYING -- the flight loop drains gas client-side, so the server's
--      CurrentPower would only ever RISE (BuyFood). The client reports remaining fuel through
--      BurnFuelEvent and the server adopts it ONLY DOWNWARD. No coins ride on this report
--      any more (they did under the space model); it is purely the tank sync.
--
--   3. THE ANTI-STRAND -- land dry and unable to afford ANY food you have unlocked, and the
--      shop grants exactly enough for ONE serving of the food on the island you have reached.
--      Once per landing. The free meal peaks at 34% of a crossing; it must never hand one over
--      (an earlier design priced it on powerShortfall() and did).
--
--   4. CLIMB PROGRESS -- sets HighestIsland / HighestSlot (and leaderstats.Island) when a
--      player STANDS on a new island. Food unlocks, gut unlocks and the wormhole all gate on
--      these. Grounded + full-3D nearness, because the tower is stacked vertically and an
--      XZ-only check reports random islands. Physical landing is the ONLY thing that banks an
--      island -- flying past one does not count, and neither does a quest.
--
-- Also owns leaderstats creation and zeroes CurrentPower on respawn (the tank does not
-- survive death). STARTING STATE is the food realm's: 2,000 coins, a 120 tank, slot 1.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Shared        = ReplicatedStorage:WaitForChild("Shared")
local CandyData     = require(Shared:WaitForChild("CandyData"))
local IslandOrder   = require(Shared:WaitForChild("IslandOrder"))
local StomachTiers  = require(Shared:WaitForChild("StomachTiers"))
local FlightTuning  = require(Shared:WaitForChild("FlightTuning"))
local Constants     = require(Shared:WaitForChild("Constants"))

local foods = CandyData.FOODS

-- ===== remotes (created if missing; EconomyBootstrap binds them to _G on clients) =====
local function ev(name)
	local e = ReplicatedStorage:FindFirstChild(name)
	if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = ReplicatedStorage end
	return e
end
local CoinEvent        = ev("CoinEvent")        -- c->s: (amount) coins earned (flight ticks AND quest rewards)
local BurnFuelEvent    = ev("BurnFuelEvent")    -- c->s: (remainingPower) flight drained the tank -- no coins
local HazardDrainEvent = ev("HazardDrainEvent") -- c->s: (lost) a hazard DESTROYED fuel
local RegenEvent       = ev("RegenEvent")       -- s->c: (powerAdded, currentPower, stomachMax)
ev("StomachFullEvent")                          -- s->c: buy-rejection reasons (fired by BuyFood/StomachUpgrade)

-- ============================================================================
-- LEADERSTATS -- created only if absent, so any future save system that builds
-- them first keeps ownership. StomachUpgrade's ensureStats uses the SAME defaults.
-- ============================================================================
local function ensureStats(player)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player end
	local function num(name, v, numberValue)
		local n = ls:FindFirstChild(name)
		if not n then
			n = Instance.new(numberValue and "NumberValue" or "IntValue")
			n.Name = name; n.Value = v; n.Parent = ls
		end
		return n
	end
	num("Coins", Constants.STARTING_COINS)              -- 2000
	num("CurrentPower", Constants.STARTING_POWER, true) -- 0
	num("StomachMax",
		StomachTiers.getTier(Constants.STARTING_STOMACH_TIER).maxPower) -- 120: the Gumdrop Belly
	num("TotalFartPower", 0)
	num("TotalCoinsEarned", 0)
	num("Island", Constants.STARTING_ISLAND)
	return ls
end

-- ============================================================================
-- GRANTING COINS -- the one place coins are ever added, so no other route can dodge
-- the perk multipliers or the whole-coin accumulator.
-- ============================================================================
-- PERK MULTIPLIERS -- friend / group / VIP (_G.coinBonusMult, RewardsService) and rebirth
-- (_G.rebirthMult, RebirthSystem), in that order -- the food realm's order.
--
-- Amounts are fractional (a 0.23s slice of a flight is worth a fraction of a coin), so
-- accumulate and only move WHOLE coins into stats; otherwise every sub-1.0 payout floors
-- to 0 and a whole flight pays nothing.
local playerCoinAccum = {}

local function grantCoins(player, amount)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local tce   = ls:FindFirstChild("TotalCoinsEarned")
	if not coins or not tce then return end
	local amt = tonumber(amount) or 0
	if amt <= 0 or amt ~= amt then return end       -- reject non-numbers, negatives and NaN

	amt = amt * ((_G.coinBonusMult and _G.coinBonusMult[player]) or 1)
	amt = amt * ((_G.rebirthMult   and _G.rebirthMult[player])   or 1)

	playerCoinAccum[player] = (playerCoinAccum[player] or 0) + amt
	local toAdd = math.floor(playerCoinAccum[player])
	if toAdd > 0 then
		playerCoinAccum[player] = playerCoinAccum[player] - toAdd
		coins.Value = coins.Value + toAdd
		tce.Value   = tce.Value + toAdd
	end
	-- PET XP (cosmetic-only): flight coin ticks feed the equipped pet. Guarded no-op if absent.
	if type(_G.petOnCoins) == "function" then pcall(_G.petOnCoins, player, amt) end
end
_G.grantCoins = grantCoins

-- ============================================================================
-- CoinEvent -- flight ticks AND quest rewards, VALIDATED (food realm's PlayerStats bound)
-- ============================================================================
-- CoinEvent:FireServer(1e9) used to bank a billion coins. The honest fix is a server-side
-- recompute of the per-stud payout, which lives in PropelSystem's flight loop (prepay,
-- ticks, descent settle); this bounds the hole hard without touching balance.
--
-- THE NUMBERS ARE SIZED OFF REAL WORST CASES, NOT GUESSED:
--   * FLIGHT TICKS, every COIN_TICK (0.23s): studs travelled x 3.52 -- x3 on a failed flight --
--     x serverEventCoinMult (peaks at 2). The biggest honest tick is a Caramel Core falling
--     at terminal speed during a 2x event: ~5.4k.
--   * QUEST REWARDS: one call of 750..3,000 coins from the quest client. Under the 8,000 cap.
local coinWindow       = {}
local COIN_WINDOW      = 5      -- seconds per budget window
local COIN_MAX_CALLS   = 60     -- calls per window. Legit is ~4.3/s (COIN_TICK 0.23) + quest bursts.
local COIN_MAX_SINGLE  = 8000   -- no single grant may exceed this
local COIN_FLAT_BUDGET = 5000   -- coins per window allowed for ANY gut (quest rewards ride on this)
local COIN_EVENT_PEAK  = 2      -- the biggest coin multiplier an event can apply

CoinEvent.OnServerEvent:Connect(function(player, amount)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local amt = tonumber(amount) or 0
	if amt ~= amt or amt == math.huge or amt == -math.huge then return end -- NaN / inf
	if amt <= 0 then return end
	if amt > COIN_MAX_SINGLE then
		warn(("[SECURITY] %s sent a single coin grant of %.0f (cap %d) -- rejected")
			:format(player.Name, amt, COIN_MAX_SINGLE))
		return
	end
	local now = os.clock()
	local w = coinWindow[player]
	if not w or (now - w.t) >= COIN_WINDOW then
		w = { t = now, spent = 0, calls = 0 }
		coinWindow[player] = w
	end
	w.calls = w.calls + 1
	if w.calls > COIN_MAX_CALLS then
		if w.calls == COIN_MAX_CALLS + 1 then
			warn(("[SECURITY] %s is calling CoinEvent %d times in %ds -- throttling")
				:format(player.Name, w.calls, COIN_WINDOW))
		end
		return
	end
	-- BUDGET. The gut is the one input the server owns outright, so the ceiling is "one full
	-- flight on this gut, failed, during a 2x event" -- the most any honest window can carry.
	local sm = ls:FindFirstChild("StomachMax")
	local gutMax = (sm and sm.Value) or 120
	local oneFlight = FlightTuning.fullTankClimb(gutMax) * FlightTuning.COIN_PER_STUD
		* (1 + FlightTuning.DESCENT_PAY_MULT) * COIN_EVENT_PEAK
	local budget = COIN_FLAT_BUDGET + oneFlight
	if (w.spent + amt) > budget then
		warn(("[SECURITY] %s exceeded the coin budget (%.0f + %.0f > %.0f on a %d gut) -- rejected")
			:format(player.Name, w.spent, amt, budget, gutMax))
		return
	end
	w.spent = w.spent + amt
	grantCoins(player, amt)
end)

-- ============================================================================
-- ANTI-STRAND -- a dry landing is never a dead end (food realm's BuyFoodEvent rule).
-- ============================================================================
-- Fires when the tank hits zero. If the player cannot afford ANY food they have unlocked,
-- grant exactly enough for ONE serving of the food on the island they have reached. Once per
-- dry spell: the flag clears when the tank is refilled, so it cannot be farmed by hopping.
-- One serving is at most 34% of a crossing (the tutorial) and under 20% everywhere else.
local strandGranted = {}   -- [player] = true once granted while dry; cleared when CurrentPower > 0

local function ensureCanRefuel(player)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local cp    = ls:FindFirstChild("CurrentPower")
	local sm    = ls:FindFirstChild("StomachMax")
	if not (coins and cp and sm) or sm.Value <= 0 then return end
	if cp.Value > 0 then return end                                -- not actually dry
	if strandGranted[player] then return end                       -- already helped this dry spell

	local reached = math.clamp(math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1), 1, #foods)
	local cheapest = math.huge
	for slot, f in ipairs(foods) do
		if slot <= reached and f.price < cheapest then cheapest = f.price end
	end
	if coins.Value >= cheapest then return end                     -- they can afford SOMETHING

	local food = foods[reached]
	if not food or food.power <= 0 or food.power > sm.Value then return end
	local had = coins.Value
	local grant = food.price - had
	if grant <= 0 then return end
	strandGranted[player] = true
	coins.Value = had + grant
	print(("[ANTI-STRAND] %s landed dry on slot %d with %d coins -> +%d for one %s (%d)")
		:format(player.Name, reached, had, grant, food.name, food.price))
end

-- ============================================================================
-- FUEL BURNED WHILE FLYING -- the tank sync. NO COINS RIDE ON THIS.
-- ============================================================================
BurnFuelEvent.OnServerEvent:Connect(function(player, remaining)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local cp = ls:FindFirstChild("CurrentPower"); if not cp then return end
	local r = tonumber(remaining)
	if not r or r ~= r then return end               -- reject non-numbers and NaN
	r = math.clamp(r, 0, cp.Value)                   -- fuel only ever burns DOWN
	if r < cp.Value then cp.Value = r end
	if r <= 0 then ensureCanRefuel(player) end       -- landed dry -> make sure they can buy back up
end)

-- FUEL DESTROYED BY A HAZARD. Same downward-only adoption; kept as its own remote so the
-- client's hazard handlers do not have to know how the tank sync works.
HazardDrainEvent.OnServerEvent:Connect(function(player, lost)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local cp = ls:FindFirstChild("CurrentPower"); if not cp then return end
	local n = tonumber(lost)
	if not n or n ~= n or n <= 0 then return end
	cp.Value = math.max(0, cp.Value - math.min(n, cp.Value))
	if cp.Value <= 0 then ensureCanRefuel(player) end
end)

-- ============================================================================
-- CLIMB PROGRESS -- which island is the player standing on?
-- Grounded + full-3D nearness (the tower is vertical: 31k studs of Y across +/-360 of
-- X/Z, so an XZ-only nearest check is arbitrary). Between islands the honest answer is
-- nil: you have not reached anywhere yet.
-- ============================================================================
local TICK = 0.5
local NEAR_RADIUS = 700
local NEAR_RADIUS_SQ = NEAR_RADIUS * NEAR_RADIUS

local topSlot = {}

-- Iterate the MODELS THAT ARE IN THE TOWER, not 1..N. The slot order is scrambled
-- against model number, so a numeric loop would also pick up islands that were never
-- placed on the ladder.
local function currentIsland(hrp, grounded)
	local pos = hrp.Position
	local best, bestD = nil, math.huge
	for _, i in ipairs(IslandOrder.SLOT_TO_ISLAND) do
		local isl = Workspace:FindFirstChild("island" .. i)
		if isl then
			local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
			if ok and cf and size and size.Magnitude > 1 then
				local dx, dz = pos.X - cf.Position.X, pos.Z - cf.Position.Z
				local dy = pos.Y - cf.Position.Y
				-- STANDING inside the island's footprint -> definitely this one. `grounded` is
				-- required: merely PASSING THROUGH a bounding box must not count as arriving (the
				-- join/intro flythrough carries the character up the whole tower).
				if grounded and math.abs(dx) <= size.X / 2 and math.abs(dz) <= size.Z / 2
					and math.abs(dy) <= size.Y / 2 + 120 then
					return i
				end
				local d = dx * dx + dy * dy + dz * dz
				if d < bestD then bestD, best = d, i end
			end
		end
	end
	if best and bestD <= NEAR_RADIUS_SQ and grounded then return best end
	return nil
end

local function onJoin(player)
	local ls = ensureStats(player)
	-- PROGRESS IS A SLOT, NOT A MODEL NUMBER. The tower scrambles the two, so "higher
	-- island number" does not mean "further up". Seed from any saved HighestSlot, falling
	-- back to the slot of a saved HighestIsland for older saves.
	local savedSlot = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 0)
	if savedSlot < 1 then
		local savedIsland = math.floor(tonumber(player:GetAttribute("HighestIsland")) or 1)
		savedSlot = IslandOrder.ISLAND_TO_SLOT[savedIsland] or 1
	end
	topSlot[player] = math.clamp(savedSlot, 1, IslandOrder.COUNT)
	player:SetAttribute("HighestSlot", topSlot[player])
	player:SetAttribute("HighestIsland", IslandOrder.SLOT_TO_ISLAND[topSlot[player]] or 1)

	-- the anti-strand flag clears the moment the tank holds anything again
	local cp = ls:FindFirstChild("CurrentPower")
	if cp then
		cp.Changed:Connect(function(v) if v > 0 then strandGranted[player] = nil end end)
	end

	player.CharacterAdded:Connect(function()
		-- the tank does not survive death/respawn
		local cpNow = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("CurrentPower")
		if cpNow then cpNow.Value = 0 end
	end)
end

Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onJoin, p) end

Players.PlayerRemoving:Connect(function(player)
	playerCoinAccum[player] = nil
	coinWindow[player] = nil
	strandGranted[player] = nil
	topSlot[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(TICK)
		for _, player in ipairs(Players:GetPlayers()) do
			-- cinematics that carry the character up the tower must not count as progress
			if not player:GetAttribute("IntroPlaying") then
				local char = player.Character
				local hrp  = char and char:FindFirstChild("HumanoidRootPart")
				local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
				if hrp and hum and hum.Health > 0 then
					local grounded = hum.FloorMaterial ~= Enum.Material.Air
					local isl = currentIsland(hrp, grounded)
					local slot = isl and IslandOrder.ISLAND_TO_SLOT[isl]
					-- COMPARE SLOTS. Model numbers are scrambled against climb order.
					-- PHYSICALLY STANDING ON A HIGHER ISLAND IS THE WHOLE GATE. Under the food model
					-- the wall is the tank's reach -- you cannot be here without the gut that makes
					-- the crossing -- so arrival is earned by the flight and nothing else is checked.
					if slot and slot > (topSlot[player] or 1) then
						topSlot[player] = slot
						player:SetAttribute("HighestSlot", slot)
						player:SetAttribute("HighestIsland", isl)
						local ls = player:FindFirstChild("leaderstats")
						local islv = ls and ls:FindFirstChild("Island")
						if islv then islv.Value = slot end   -- the Island stat is the CLIMB position
						print(("[FlightEconomy] %s reached slot %d (island%d, %s) -- new best")
							:format(player.Name, slot, isl, IslandOrder.NAMES[slot] or "?"))
					end
				end
			end
		end
	end
end)

print(("[FlightEconomy] live -- FOOD MODEL: coins per stud (%.2f, x3 on a failure) paid by the client "
	.. "and BOUNDED here (cap %d/grant, %d calls + flat %d per %ds window + one failed flight on the gut); "
	.. "one-serving anti-strand; progress tracker over %d slots; start %d coins / %d tank")
	:format(FlightTuning.COIN_PER_STUD, COIN_MAX_SINGLE, COIN_MAX_CALLS, COIN_FLAT_BUDGET, COIN_WINDOW,
		IslandOrder.COUNT, Constants.STARTING_COINS,
		StomachTiers.getTier(Constants.STARTING_STOMACH_TIER).maxPower))
