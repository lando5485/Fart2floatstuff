--!nonstrict
--======================================================================
-- FlightEconomy.server.luau  (Server Script)  -- CandyRealm
--======================================================================
-- The server half of the Dino-Realm-style flight economy, ported for the candy
-- tower. Three jobs:
--
--   1. COINS EARNED WHILE FLYING -- the client (PropelSystem_AllInOne) pays 0.14
--      coins per stud CLIMBED every 0.5s of thrust via CoinEvent. Amounts are
--      fractional; accumulate and only move WHOLE coins into stats, otherwise
--      every sub-1.0 payout would floor to 0.
--
--   2. FUEL BURNED WHILE FLYING -- the flight loop drains gas client-side, so the
--      server's CurrentPower would only ever RISE (BuyFood). The client reports
--      remaining fuel via BurnFuelEvent; the server adopts it ONLY DOWNWARD (a
--      burn can never refill a tank), so this is no more spoofable than the
--      client-side drain it mirrors. Landing dry triggers the ANTI-STRAND grant:
--      coins (never fuel) up to a QUARTER TANK of the local food -- the floor that
--      keeps the loop alive, not a free crossing. A quarter tank always compounds
--      back to full because R > 1 at every CandyData row.
--
--   3. CLIMB PROGRESS -- sets the HighestIsland / HighestSlot attributes (and the
--      leaderstats.Island value) when a player STANDS on a new island. Everything
--      gates on these: food unlocks, gut unlocks, the wormhole. Ported from the
--      dino realm's PetXPHooks tracker: grounded + full-3D nearness, because the
--      tower is stacked vertically and an XZ-only check reports random islands.
--
-- Also owns leaderstats creation (Coins START AT 120 -- at the old 0 you could not
-- afford enough food for a profitable first flight and the run dead-locked), and
-- zeroes CurrentPower on respawn (the tank does not survive death).
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local CandyData    = require(Shared:WaitForChild("CandyData"))
local IslandOrder  = require(Shared:WaitForChild("IslandOrder"))

local foods = CandyData.FOODS

-- ===== remotes (created if missing; EconomyBootstrap binds them to _G on clients) =====
local function ev(name)
	local e = ReplicatedStorage:FindFirstChild(name)
	if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = ReplicatedStorage end
	return e
end
local CoinEvent        = ev("CoinEvent")        -- c->s: (amount) coins earned during flight
local BurnFuelEvent    = ev("BurnFuelEvent")    -- c->s: (remainingPower) flight drained the tank
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
	num("Coins", 120)            -- starting coins: most of a first tank of Candy Canes
	num("CurrentPower", 0, true) -- current fart fuel in the tank
	num("StomachMax", 110)       -- tank size = Gumdrop Belly
	num("TotalFartPower", 0)
	num("TotalCoinsEarned", 0)
	num("Island", 1)
	return ls
end

-- ============================================================================
-- COINS EARNED WHILE FLYING
-- ============================================================================
local playerCoinAccum = {}
CoinEvent.OnServerEvent:Connect(function(player, amount)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local tce   = ls:FindFirstChild("TotalCoinsEarned")
	if not coins or not tce then return end
	local amt = tonumber(amount) or 0
	if amt <= 0 or amt ~= amt then return end       -- reject non-numbers, negatives and NaN

-- ===== PERK MULTIPLIERS -- friend / group / VIP, and rebirth =====
-- ⚠ THESE WERE BEING WRITTEN AND NEVER READ. RewardsService fills _G.coinBonusMult (friend boost +25%, group
-- perk +10%) and RebirthSystem fills _G.rebirthMult (+25% per rebirth); both files' comments say "read by
-- PlayerStats CoinEvent" -- but PlayerStats is a FOOD-realm script and does not exist in Candy. Nothing in this
-- realm ever read either table, so the friend boost, the group perk and every rebirth's coin bonus have all
-- been doing exactly nothing here, silently, while the UI advertised them.
--
-- They are applied HERE because this is the one place coins are granted (same reasoning as the dev hook above),
-- so no other route can earn them. A realm with none of these systems just multiplies by one.
-- VIP rides in through _G.coinBonusMult, which RewardsService sums alongside friend + group.
	amt = amt * ((_G.coinBonusMult and _G.coinBonusMult[player]) or 1)
	amt = amt * ((_G.rebirthMult   and _G.rebirthMult[player])   or 1)

	playerCoinAccum[player] = (playerCoinAccum[player] or 0) + amt
	local toAdd = math.floor(playerCoinAccum[player])
	if toAdd > 0 then
		playerCoinAccum[player] = playerCoinAccum[player] - toAdd
		coins.Value = coins.Value + toAdd
		tce.Value   = tce.Value + toAdd
	end
end)

-- ============================================================================
-- ANTI-STRAND TOP-UP -- run when a flight ends with the tank at zero. Prices a
-- QUARTER tank of the food on the slot the player has reached and grants only the
-- coin SHORTFALL. Servings are indivisible, so round UP -- being one candy cane
-- short of flying at all is the exact situation this exists to prevent.
-- ============================================================================
local function ensureCanRefuel(player)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local cp    = ls:FindFirstChild("CurrentPower")
	local sm    = ls:FindFirstChild("StomachMax")
	if not (coins and cp and sm) or sm.Value <= 0 then return end

	local slot = math.clamp(math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1), 1, #foods)
	local food = foods[slot]
	if not food or food.power <= 0 then return end

	local missing = (sm.Value * 0.25) - cp.Value
	if missing <= 0 then return end                  -- already holding a quarter tank
	local servings = math.max(1, math.ceil(missing / food.power))
	-- ...but never more than the tank can actually hold, or we would fund food that
	-- gets rejected as "not_enough_room".
	local roomServings = math.floor((sm.Value - cp.Value) / food.power)
	servings = math.min(servings, math.max(0, roomServings))
	if servings <= 0 then return end

	local needCoins = servings * food.price
	if coins.Value >= needCoins then return end      -- they can already afford it
	local grant = needCoins - coins.Value
	coins.Value = coins.Value + grant
	print(("[FlightEconomy] anti-strand: %s landed dry on slot %d, needs %d for %d x %s (quarter tank) -> granted %d")
		:format(player.Name, slot, needCoins, servings, food.name, grant))
end

BurnFuelEvent.OnServerEvent:Connect(function(player, remaining)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local cp = ls:FindFirstChild("CurrentPower"); if not cp then return end
	local r = tonumber(remaining)
	if not r or r ~= r then return end               -- reject non-numbers and NaN
	r = math.floor(math.clamp(r, 0, cp.Value))       -- fuel only ever burns DOWN
	if r < cp.Value then cp.Value = r end
	if r <= 0 then ensureCanRefuel(player) end       -- landed dry -> make sure they can buy back up
end)

-- ============================================================================
-- CLIMB PROGRESS -- which island is the player standing on?
-- Grounded + full-3D nearness (the tower is vertical: 81k studs of Y across
-- +/-360 of X/Z, so an XZ-only nearest check is arbitrary). Between islands the
-- honest answer is nil: you have not reached anywhere yet.
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
				-- standing inside the island's footprint -> definitely this one
				if math.abs(dx) <= size.X / 2 and math.abs(dz) <= size.Z / 2
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
	ensureStats(player)
	-- PROGRESS IS A SLOT, NOT A MODEL NUMBER. The tower scrambles the two, so "higher
	-- island number" does not mean "further up" -- island7 is slot 2. Seed from the saved
	-- HighestSlot, falling back to the slot of the saved HighestIsland for older saves.
	local savedSlot = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 0)
	if savedSlot < 1 then
		local savedIsland = math.floor(tonumber(player:GetAttribute("HighestIsland")) or 1)
		savedSlot = IslandOrder.ISLAND_TO_SLOT[savedIsland] or 1
	end
	topSlot[player] = math.clamp(savedSlot, 1, IslandOrder.COUNT)
	player:SetAttribute("HighestSlot", topSlot[player])
	player:SetAttribute("HighestIsland", IslandOrder.SLOT_TO_ISLAND[topSlot[player]] or 1)

	player.CharacterAdded:Connect(function()
		-- the tank does not survive death/respawn
		local ls = player:FindFirstChild("leaderstats")
		local cp = ls and ls:FindFirstChild("CurrentPower")
		if cp then cp.Value = 0 end
	end)
end

Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onJoin, p) end

Players.PlayerRemoving:Connect(function(player)
	playerCoinAccum[player] = nil
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
					-- COMPARE SLOTS. Model numbers are scrambled against climb order, so
					-- `isl > best` would let island7 (slot 2) block island3 (slot 3) from
					-- ever registering -- and the player's progress would stall silently.
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

print("[FlightEconomy] live -- climb coins (0.14/stud via CoinEvent), fuel burn + anti-strand, island progress tracker, starting coins 120")
