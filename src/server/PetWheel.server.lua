--!nonstrict
-- PetWheel (ServerScriptService/PetWheel)
-- ============================================================================================================
-- SERVER-AUTHORITATIVE "Pet Wheel" spin system. Players buy spins with Robux (Developer Products), then spend a
-- spin to roll the wheel. EVERYTHING that matters happens here: the roll, the level/coin/mythical grants, the
-- level cap, the spin-credit accounting, and persistence. The client (PetWheel.client.lua) only animates the
-- wheel to the result the server sends and displays the odds -- it can never decide an outcome or a credit count.
--
-- ODDS HONESTY: the roll uses PetWheelConfig.roll(), and the client's Odds panel prints the SAME
-- PetWheelConfig.SEGMENTS weights. One table, two readers -> the shown odds and the rolled odds cannot drift.
-- No pity, no re-rolls, no rigging (Roblox requires truthful odds on paid random items).
--
-- PROTOCOL over the single RemoteEvent "PetWheelEvent" (verb-multiplexed, mirrors SeasonPass/Rebirth style):
--   client -> server:  "requestState"                     ask for a fresh {spins, pending}
--                      "spin"                             spend 1 credit, roll, grant
--                      "buy", productId                   TEST_MODE ONLY: credit a spin pack with no Robux
--                      "assign", petId                    assign held pet-levels to an owned pet (pet-picker)
--   server -> client:  "state",   { spins, pending }       current credits + held (unassigned) pet levels
--                      "result",  { segIndex, segId, reward, spins, pending }   the rolled outcome to animate to
--                      "purchased",{ productId, spins, total, test }  a spin pack landed (test purchase)
--                      "assigned",{ petId, added, pending } result of assigning held levels
--                      "toast",   message                  a short info line (e.g. out of spins)
--
-- LEVEL REWARDS route through a "pending" pool: a level win adds to pending; the client opens the pet-picker and
-- fires "assign" with the chosen pet. If the player owns ZERO pets, the levels simply stay in pending (NOT wasted,
-- NOT converted) until they unlock a pet and assign them -- see the header note in the client.
-- ============================================================================================================

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local DataStoreService   = game:GetService("DataStoreService")
local RunService         = game:GetService("RunService")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local Config  = require(Shared:WaitForChild("PetWheelConfig"))

-- ---- remote (create on server; client waits for it) --------------------------------------------------------
local function getOrCreate(cls, name)
	local o = ReplicatedStorage:FindFirstChild(name)
	if not o then o = Instance.new(cls); o.Name = name; o.Parent = ReplicatedStorage end
	return o
end
local remote = getOrCreate("RemoteEvent", "PetWheelEvent")

-- ---- persistence -------------------------------------------------------------------------------------------
-- Own versioned store, keyed Player_<uid>, mirroring the SeasonPass/Rebirth house style. Holds ONLY the two
-- wheel-specific numbers; pet levels + mythical pets are persisted by PlayerStats via _G.playerOwnedPets.
local STORE_NAME  = "PetWheel_v1"
local KEY_PREFIX  = "Player_"
local AUTOSAVE_SECONDS = 60

local store = nil
pcall(function() store = DataStoreService:GetDataStore(STORE_NAME) end)
local function keyFor(uid) return KEY_PREFIX .. tostring(uid) end

-- ---- in-memory state ---------------------------------------------------------------------------------------
local state        = {}  -- [player] = { spins = int, pending = int }   pending = pet-levels won but not yet assigned
local dirty        = {}  -- [player] = true when state changed since last save
local forceMythical = {} -- [player] = true  DEV ONLY: next spin is forced to the MYTHICAL wedge (/forcemythical)

local rng = Random.new()

local saveState -- forward-declared (referenced by _G.wheelHandleReceipt below; defined near the bottom)

-- Locate the MYTHICAL wedge (used by the /forcemythical dev path). Scans the shared table so it stays correct
-- if segments are reordered.
local function mythicalSegment()
	for i, seg in ipairs(Config.SEGMENTS) do
		if seg.kind == "mythical" then return seg, i end
	end
	return nil, nil
end

-- ---- helpers ---------------------------------------------------------------------------------------------
local function pushState(player)
	local st = state[player]
	if not st then return end
	pcall(function() remote:FireClient(player, "state", { spins = st.spins, pending = st.pending }) end)
end

local function toast(player, msg)
	pcall(function() remote:FireClient(player, "toast", msg) end)
end

-- Flat coin grant for the two "Coins" wedges. Mirrors PlayerStats' offline-claim grant (NOT the flight CoinEvent,
-- which would scale the amount by boost multipliers). Also bumps TotalCoinsEarned so it counts on the coins board.
local function grantCoins(player, amount)
	local ls = player:FindFirstChild("leaderstats")
	local coins = ls and ls:FindFirstChild("Coins")
	local total = ls and ls:FindFirstChild("TotalCoinsEarned")
	if coins then
		coins.Value = coins.Value + amount
		if total then total.Value = total.Value + amount end
	end
end

local function addSpins(player, n)
	local st = state[player]
	if not st then st = { spins = 0, pending = 0 }; state[player] = st end
	st.spins = st.spins + math.max(0, math.floor(n))
	dirty[player] = true
	pushState(player)
end

-- ============================================================================================================
-- PURCHASE RECEIPT: PlayerStats owns the game's single MarketplaceService.ProcessReceipt and delegates to this
-- global (exactly like _G.petsHandleReceipt / _G.gardenHandleDonationReceipt). Return true ONLY when we granted
-- spins for a confirmed receipt -> PlayerStats then returns PurchaseGranted. Spins are credited AFTER the receipt.
-- ============================================================================================================
_G.wheelHandleReceipt = function(player, productId)
	local product = Config.productByProductId(productId)
	if not product then return false end -- not one of our products; let other handlers try
	addSpins(player, product.spins)
	-- persist immediately: real money changed hands, so don't wait for the autosave tick
	pcall(function() saveState(player) end)
	print(string.format("[PetWheel] %s bought %s (+%d spins), now %d",
		player.Name, product.label or product.id, product.spins, state[player] and state[player].spins or 0))
	return true
end

-- ============================================================================================================
-- TEST-MODE PURCHASE (Config.TEST_MODE only) -- the buy cards have no real Developer Product behind them yet,
-- so the client fires "buy" <productId> and we credit the spins HERE, through the same addSpins() the real
-- receipt handler above uses. That is the whole point: the client never touches its own spin count, so the
-- flow being tested (button -> server grant -> state push -> SPIN enabled -> roll) is the shipping flow.
--
-- Two guards, because this is a "free spins" endpoint:
--   * Config.TEST_MODE -- flip it false and this returns immediately, so a live build can't be farmed.
--   * a 0.4s per-player cooldown -- a spammed/auto-clicked card can't stack hundreds of credits in a frame.
-- ============================================================================================================
local lastBuy = {}   -- [player] = os.clock() of their last accepted test purchase

local function doTestBuy(player, productKey)
	if not Config.TEST_MODE then
		toast(player, "Purchases aren't available right now.")
		return
	end
	local product = Config.productById(productKey)
	if not product then return end
	local now = os.clock()
	if lastBuy[player] and (now - lastBuy[player]) < 0.4 then return end
	lastBuy[player] = now

	addSpins(player, product.spins)               -- same grant path as _G.wheelHandleReceipt
	pcall(function() saveState(player) end)       -- and the same immediate save
	local st = state[player]
	print(string.format("[PetWheel][TEST] %s bought %s (+%d spins), now %d",
		player.Name, product.label or product.id, product.spins, st and st.spins or 0))
	pcall(function()
		remote:FireClient(player, "purchased", {
			productId = product.id, spins = product.spins, total = st and st.spins or 0, test = true,
		})
	end)
end

-- ============================================================================================================
-- DEV HOOKS (REMOVE BEFORE LAUNCH) -- called from DevCommands.server.luau for /givespins and /forcemythical.
-- ============================================================================================================
_G.wheelGiveSpins = function(player, n)
	if not player then return end
	addSpins(player, tonumber(n) or 0)
	print(string.format("[PetWheel][DEV] granted %s spins to %s (now %d)", tostring(n), player.Name, state[player].spins))
end
_G.wheelForceMythical = function(player)
	if not player then return end
	forceMythical[player] = true
	print("[PetWheel][DEV] next spin FORCED to MYTHICAL for " .. player.Name)
end

-- ============================================================================================================
-- SPIN: the authoritative roll. Spend 1 credit, roll on the shared weights (or the forced mythical), grant.
-- ============================================================================================================
local function doSpin(player)
	local st = state[player]
	if not st then return end
	if st.spins < 1 then
		toast(player, "You're out of spins!")
		pushState(player)
		return
	end
	st.spins = st.spins - 1

	-- roll (server-owned RNG). Dev override forces the mythical wedge for testing the jackpot path.
	local seg, idx
	if forceMythical[player] then
		forceMythical[player] = nil
		seg, idx = mythicalSegment()
	end
	if not seg then
		seg, idx = Config.roll(rng)
	end

	-- grant by kind
	local reward = { kind = seg.kind, label = seg.label }
	if seg.kind == "levels" then
		st.pending = st.pending + seg.amount           -- held until the player picks a pet (see "assign")
		reward.amount = seg.amount
	elseif seg.kind == "coins" then
		grantCoins(player, seg.amount)
		reward.amount = seg.amount
	elseif seg.kind == "mythical" then
		-- pick a random species from the mythical list (auto-includes any future additions), grant its rare variant
		local list = Config.MYTHICAL_PETS
		local petId = list[rng:NextInteger(1, #list)]
		local name = _G.petGrantMythicalVariant and _G.petGrantMythicalVariant(player, petId) or nil
		reward.petId = petId
		reward.name  = name or petId
	end

	dirty[player] = true
	print(string.format("[PetWheel] %s spun -> %s (seg #%d), spins left %d, pending %d",
		player.Name, seg.id, idx, st.spins, st.pending))
	pcall(function()
		remote:FireClient(player, "result", {
			segIndex = idx, segId = seg.id, reward = reward, spins = st.spins, pending = st.pending,
		})
	end)
end

-- ============================================================================================================
-- ASSIGN: route held pet-levels onto a pet the player picked (the pet-picker on the client). Grants as many as
-- fit under the level-25 cap (leftover stays in pending for another pet); _G.petGrantLevels does the clamp.
-- ============================================================================================================
local function doAssign(player, petId)
	local st = state[player]
	if not st or st.pending <= 0 then return end
	if type(petId) ~= "string" then return end
	if not _G.petGrantLevels then return end
	-- petGrantLevels(player, petId, n) -> oldLevel, newLevel, levelsAdded  (nil if the player doesn't own petId)
	local oldLevel, newLevel, added = _G.petGrantLevels(player, petId, st.pending)
	if oldLevel == nil then
		-- player doesn't own that pet -> ignore (the client only offers owned pets, so this is a stale/forged pick)
		toast(player, "You don't own that pet.")
		return
	end
	added = added or 0
	st.pending = math.max(0, st.pending - added)
	dirty[player] = true
	print(string.format("[PetWheel] %s assigned %d levels to %s (%s->%s), pending now %d",
		player.Name, added, petId, tostring(oldLevel), tostring(newLevel), st.pending))
	pcall(function() remote:FireClient(player, "assigned", { petId = petId, added = added, pending = st.pending }) end)
	pushState(player)
end

-- ---- remote dispatch ---------------------------------------------------------------------------------------
remote.OnServerEvent:Connect(function(player, verb, arg)
	if verb == "requestState" then
		pushState(player)
	elseif verb == "spin" then
		doSpin(player)
	elseif verb == "buy" then
		doTestBuy(player, arg)   -- no-op unless Config.TEST_MODE (see doTestBuy)
	elseif verb == "assign" then
		doAssign(player, arg)
	end
end)

-- ---- load / save -------------------------------------------------------------------------------------------
saveState = function(player) -- assigns the forward-declared local; called from _G.wheelHandleReceipt + on leave
	local st = state[player]
	if not st or not store then return end
	if not dirty[player] then return end
	local ok = pcall(function()
		store:SetAsync(keyFor(player.UserId), { spins = st.spins, pending = st.pending })
	end)
	if ok then dirty[player] = false end
end

local function loadPlayer(player)
	local saved = nil
	if store then
		pcall(function() saved = store:GetAsync(keyFor(player.UserId)) end)
	end
	saved = saved or {}
	state[player] = {
		spins   = tonumber(saved.spins)   or 0,
		pending = tonumber(saved.pending) or 0,
	}
	dirty[player] = false
	pushState(player)
end

Players.PlayerAdded:Connect(loadPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(loadPlayer, p) end -- players already present (script late-load)

Players.PlayerRemoving:Connect(function(player)
	dirty[player] = dirty[player] or false
	-- always try a final save (mark dirty so a load-then-leave with no change still no-ops cheaply)
	saveState(player)
	state[player] = nil; dirty[player] = nil; forceMythical[player] = nil; lastBuy[player] = nil
end)

-- periodic autosave for held credits/pending (paid content -> don't lose it on a crash)
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for _, p in ipairs(Players:GetPlayers()) do
			saveState(p)
		end
	end
end)

game:BindToClose(function()
	if RunService:IsStudio() then return end
	for _, p in ipairs(Players:GetPlayers()) do
		saveState(p)
	end
end)

print("[PetWheel] server ready (" .. STORE_NAME .. ")")
