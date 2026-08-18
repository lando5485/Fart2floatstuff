--======================================================================
-- SECRET CAVE TRADER  (Script, server)
--======================================================================
-- The hooded trader who lives in the cave behind the 'secretcave' door. He sells things sold nowhere else,
-- for coins and for crate tokens.
--
-- ===== WHY THE SHOP LIVES ON THE SERVER WHEN THE CAVE DOES NOT =====
-- The cave itself is built entirely client-side (see SecretCave.client.lua) -- it is decoration, it costs the
-- server nothing, and if a player somehow forged their way in they would gain nothing but scenery.
--
-- MONEY IS DIFFERENT. A shop that deducted coins on the client would be a coin printer: the client could
-- simply not deduct, or grant itself the goods without paying. So the client's shop UI sends nothing but an
-- item id, and every question that matters -- does that item exist, IS IT IN STOCK RIGHT NOW, is there a unit
-- left, can this player afford it -- is answered here.
--
-- The client is never trusted for price. The price lives in the item tables below, on the server, and the
-- client's copy is only for drawing the panel.
--
--======================================================================
-- ===== THE RESTOCK (this is the part that makes people come back) =====
--======================================================================
-- Sal's stall used to show the same five items forever, which meant that once you had seen it there was no
-- reason to ever walk back into the cave. Now it RESTOCKS every 20 minutes:
--
--   * A couple of items are PERMANENT -- they are Sal's staples and always on the shelf.
--   * The rest of the shelf is ROTATING: three items drawn from a bigger pool, re-drawn every window.
--   * Rotating items have LIMITED UNITS. When they're gone they're gone until the next restock, and the
--     panel says SOLD OUT. Scarcity is the whole point: an item you can always buy is a menu, an item that
--     might be gone in ten minutes is an appointment.
--
-- ===== WHY THE WINDOW COMES FROM os.time() AND NOT FROM A TIMER =====
-- The window index is math.floor(os.time() / 1200) -- real UTC wall-clock, not "20 minutes since this server
-- booted". Two consequences, both deliberate:
--
--   1. EVERY SERVER ROTATES TOGETHER, to the same items, at the same moment. That is what makes the stock
--      shareable ("Sal has Jet Fuel right now") instead of a private per-server accident. The item choice is
--      drawn from Random.new(windowIndex), so the same window always deals the same hand on every server
--      without any cross-server messaging.
--   2. A SERVER THAT BOOTS MID-WINDOW JOINS THE ROTATION ALREADY IN PROGRESS and gets the correct partial
--      countdown, rather than starting a fresh 20 minutes and drifting out of step with everywhere else.
--
-- UNIT COUNTS ARE PER-SERVER, on purpose. They are the local drama -- you are racing the other people in
-- YOUR server for the last Fat Sack. Making them global would need cross-server state for no added fun.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function getOrCreate(className, name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local inst = Instance.new(className); inst.Name = name; inst.Parent = ReplicatedStorage
	return inst
end

local remote = getOrCreate("RemoteEvent", "SecretTraderBuy")
-- server -> client: purchase result, so the panel can say what happened rather than just going quiet
local reply  = getOrCreate("RemoteEvent", "SecretTraderResult")
-- server -> client: the shelf itself. Changes once per restock window -> the panel rebuilds its rows.
local menu   = getOrCreate("StringValue", "SecretTraderStock")
-- server -> client: live remaining units, "id<US>remaining" pairs. Changes on every purchase, so it is kept
-- SEPARATE from the stock string above: a sale updates one label instead of tearing down and rebuilding the
-- whole list under a player who is mid-scroll.
local counts = getOrCreate("StringValue", "SecretTraderCounts")
-- server -> client: when the current window ends, expressed on the SERVER CLOCK (workspace:GetServerTimeNow),
-- which Roblox keeps synchronised on both ends. Publishing a raw os.time() deadline instead would be read
-- against the player's own device clock, and a phone that is two minutes fast would show a two-minute-wrong
-- countdown.
local endsAt = getOrCreate("NumberValue", "SecretTraderRestockAt")
-- server -> ALL: a restock just happened, here are the headline items. Drives the server-wide banner.
local restockEvent = getOrCreate("RemoteEvent", "SecretTraderRestockEvent")

local RESTOCK_SECONDS = 1200   -- 20 minutes. One edit changes the cadence everywhere (window, countdown, banner).
local ROTATING_SLOTS  = 3      -- how many pool items are on the shelf at once, alongside the permanent ones.

local function coinsOf(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Coins")
end

--======================================================================
-- THE STOCK
--======================================================================
-- `grant` returns true on success. A grant that CANNOT be completed must return false and take no money --
-- the deduction below only happens after the grant reports success, so a missing dependency costs the player
-- nothing instead of silently eating their coins.
--
-- `street` is what the item would SUPPOSEDLY cost above ground. It is pure theatre -- nothing charges it --
-- but showing it struck through next to Sal's number is what makes every row read as a deal too good to be
-- legal, which is the entire sales pitch of a black market.
--
-- `units` is how many exist THIS WINDOW on THIS server. nil = unlimited (the permanent staples). A rotating
-- item without units would defeat the restock: the scarcity is what gets people into the cave.
--
-- ===== SAL DEALS IN TOKENS =====
-- Most items price in Crate Tokens rather than coins, with deliberate exceptions marked below. The prices
-- are struck at roughly 1 token to 20 coins. Retune by editing `price` on the row; `currency` is what decides
-- which wallet is charged, so a single word moves an item back onto coins.

-- Hot Coins would be an infinite money printer without a cooldown: net positive per click, clicked forever.
-- One shipment per player per 5 minutes keeps it a treat rather than an exploit. This is a PER-PLAYER guard
-- and is separate from unit counts, which are per-server.
local hotCoinsAt = {}
Players.PlayerRemoving:Connect(function(p) hotCoinsAt[p] = nil end)

-- ===== PERMANENT: always on the shelf, every window =====
-- These two are the reason the cave is never a wasted trip. Both carry their own per-player limit (a cooldown
-- and a once-ever flag), which is why neither needs unit counts on top.
local PERMANENT = {
	{
		id     = "hotcoins",
		name   = "Hot Coins",
		desc   = "A thousand coins for forty tokens. They fell off a blimp. Don't ask which blimp.",
		price  = 40,
		currency = "tokens",
		street = 1000,
		grant  = function(player)
			local now = os.clock()
			if hotCoinsAt[player] and now - hotCoinsAt[player] < 300 then
				return false, "Next shipment hasn't fallen off the blimp yet. Come back in a few minutes."
			end
			local coins = coinsOf(player)
			if not coins then return false end
			hotCoinsAt[player] = now
			coins.Value = coins.Value + 1000
			return true
		end,
	},
	{
		-- \xE2\x9A\xA0 PRICED IN COINS ON PURPOSE. This row SELLS 250 tokens. Pricing it in tokens makes it
		-- pay-tokens-to-get-tokens: either a straight loss or an infinite printer depending on the number, and
		-- its whole pitch ("no Robux asked") is that it's the one way to get tokens WITHOUT premium currency.
		-- The once-ever flag is what keeps it from being a faucet.
		id     = "basiccrate",
		name   = "Starter Crate, Paid in Coins",
		desc   = "250 tokens -- exactly one Starter Crate, no Robux asked. ONE per customer, ever. Sal's rules.",
		price  = 2000,
		currency = "coins",
		street = 0,   -- up top these tokens are Robux-only; there IS no coin price, which is the whole appeal
		grant  = function(player)
			if player:GetAttribute("BoughtSalBasicCrate") then
				return false, "One per customer. Sal remembers faces."
			end
			if type(_G.addSkinTokens) ~= "function" then return false, "Sal's crate supplier got caught." end
			if _G.addSkinTokens(player, 250, "secret trader basic crate") == false then return false end
			player:SetAttribute("BoughtSalBasicCrate", true)
			return true, "250 tokens, straight off the truck. Go open that crate."
		end,
	},
}

-- ===== THE ROTATING POOL =====
-- Three of these are on the shelf at any moment. Adding a row here widens the rotation and needs nothing else
-- changed -- the draw, the publish, the counts and the panel all read the pool as it stands.
--
-- The two BOOST grants both refuse while a boost of the same kind is still burning, which is what stops a
-- player buying six and stacking a half-hour of double coins out of one restock.
local function grantTimedBoost(attr, seconds, busyMsg, okMsg)
	return function(player)
		local now = workspace:GetServerTimeNow()
		if (player:GetAttribute(attr) or 0) - now > 30 then
			return false, busyMsg
		end
		player:SetAttribute(attr, now + seconds)
		return true, okMsg
	end
end

local POOL = {
	{
		id     = "boost2x",
		name   = "2x Coins (5 min)",
		desc   = "Sal greases the right palms and your flights pay DOUBLE for five minutes.",
		price  = 30, currency = "tokens", street = 1500, units = 8,
		grant  = grantTimedBoost("SalCoinBoostUntil", 300,
			"Your last batch is still burning. Use it up first.",
			"Deal. Five minutes of DOUBLE coins -- fly, now!"),
	},
	{
		id     = "boostspeed",
		name   = "Rocket Gas (5 min)",
		desc   = "Off-the-books fuel additive. Fly 35% faster for five minutes. Probably safe.",
		price  = 25, currency = "tokens", street = 1200, units = 8,
		grant  = grantTimedBoost("SalSpeedBoostUntil", 300,
			"Your tank's still fizzing from the last dose.",
			"Topped up. Five minutes of rocket gas -- try to land gently."),
	},
	{
		id     = "mystery",
		name   = "Mystery Sack",
		desc   = "Sal won't open it, you can't open it until it's yours. Somewhere between 150 and 1,200 coins.",
		price  = 20, currency = "tokens",
		street = 0,   -- 0 = no street price: the client shows '???' -- nobody knows what an unopened sack is worth
		units  = 10,
		grant  = function(player)
			local coins = coinsOf(player)
			if not coins then return false end
			local found = math.random(150, 1200)
			coins.Value = coins.Value + found
			return true, "You shake out the sack\xE2\x80\xA6 " .. found .. " coins!"
		end,
	},
	{
		id     = "boost2xlong",
		name   = "The Long Con (2x Coins, 15 min)",
		desc   = "Same trick, three times the run. Fifteen minutes of double coins. Sal is not doing this again today.",
		price  = 75, currency = "tokens", street = 5000, units = 4,
		grant  = grantTimedBoost("SalCoinBoostUntil", 900,
			"You've already got a batch burning. Sal doesn't double-dip.",
			"Fifteen minutes. Don't waste them standing in a cave."),
	},
	{
		id     = "jetfuel",
		name   = "Jet Fuel (15 min)",
		desc   = "Not fuel. Sal won't say what it is. Fly 35% faster for a quarter of an hour.",
		price  = 65, currency = "tokens", street = 4000, units = 4,
		grant  = grantTimedBoost("SalSpeedBoostUntil", 900,
			"Still fizzing. Let the last dose wear off.",
			"That's the good stuff. Fifteen minutes -- go."),
	},
	{
		id     = "fatsack",
		name   = "The Fat Sack",
		desc   = "Four times the sack, four times the mystery. Between 1,500 and 6,000 coins. Sal has three.",
		price  = 70, currency = "tokens", street = 0, units = 3,
		grant  = function(player)
			local coins = coinsOf(player)
			if not coins then return false end
			local found = math.random(1500, 6000)
			coins.Value = coins.Value + found
			return true, "The sack splits open\xE2\x80\xA6 " .. found .. " coins!"
		end,
	},
	{
		id     = "doubledip",
		name   = "The Full Package",
		desc   = "Double coins AND rocket gas, five minutes of both. Sal's own blend. Three only.",
		price  = 50, currency = "tokens", street = 2700, units = 3,
		grant  = function(player)
			local now = workspace:GetServerTimeNow()
			-- Both halves must be free, and both are checked BEFORE either is set: granting the speed half and
			-- then refusing on the coin half would charge full price for half the package.
			if (player:GetAttribute("SalCoinBoostUntil") or 0) - now > 30
				or (player:GetAttribute("SalSpeedBoostUntil") or 0) - now > 30 then
				return false, "You've still got something burning. Sal sells the whole package or nothing."
			end
			player:SetAttribute("SalCoinBoostUntil",  now + 300)
			player:SetAttribute("SalSpeedBoostUntil", now + 300)
			return true, "Double coins AND rocket gas. Five minutes. Fly like you stole it."
		end,
	},
	{
		-- \xE2\x9A\xA0 ECONOMY CALL -- THIS ROW IS THE ONE TO DELETE IF TOKEN SALES DIP.
		-- It is a COINS -> TOKENS faucet, the only repeatable one in the game (basiccrate above is once-ever).
		-- It is deliberately the scarcest thing Sal stocks: ONE unit, per server, per 20-minute window, and only
		-- in the windows the draw happens to deal it. That bound is what keeps it from competing with Robux --
		-- but it IS a bound and not a wall, so if token revenue moves, this is the row that moved it. Deleting
		-- these lines needs no other change anywhere.
		id     = "tokenpouch",
		name   = "Pouch of Tokens",
		desc   = "Sixty crate tokens for cold coins. Sal has exactly one and he's already regretting it.",
		price  = 12000, currency = "coins", street = 0, units = 1,
		grant  = function(player)
			if type(_G.addSkinTokens) ~= "function" then return false, "Sal's token counter is busted." end
			if _G.addSkinTokens(player, 60, "secret trader token pouch") == false then return false end
			return true, "Sixty tokens. Sal is already looking like he wants them back."
		end,
	},
}

--======================================================================
-- THE DRAW
--======================================================================
-- Which window are we in? Real UTC seconds / RESTOCK_SECONDS, so every server on the game agrees without
-- talking to each other.
local function windowIndex() return math.floor(os.time() / RESTOCK_SECONDS) end

-- Deal this window's hand. Seeded from the window index alone, so it is the SAME hand everywhere, and a
-- server that reboots mid-window re-deals the identical shelf rather than surprising everyone with a
-- different one halfway through.
--
-- Fisher-Yates over a copy of the pool -- a plain "pick 3 random" would deal duplicates.
local function rollWindow(win)
	local order = {}
	for i = 1, #POOL do order[i] = i end
	local rng = Random.new(win)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local picked = {}
	for i = 1, math.min(ROTATING_SLOTS, #POOL) do picked[#picked + 1] = POOL[order[i]] end
	return picked
end

-- ===== LIVE WINDOW STATE =====
-- `active` is the ONLY list a purchase is allowed to match against. Checking the full pool instead would let
-- a client buy a rotated-out item by sending its id from memory -- the whole restock would be cosmetic.
local activeById = {}    -- [id] = item, for THIS window only
local remaining  = {}    -- [id] = units left this window (nil for unlimited)
local currentWin = nil

local FIELD, RECORD = "\30", "\31"   -- unit/record separators, matching the client's parser

local function publishCounts()
	local parts = {}
	for id, n in pairs(remaining) do
		parts[#parts + 1] = id .. FIELD .. tostring(n)
	end
	counts.Value = table.concat(parts, RECORD)
end

-- Publish the shelf. Field order: id, name, Sal's price, street price (0 = unknown), description, CURRENCY,
-- MAX UNITS (-1 = unlimited). Currency and units are published rather than assumed, for the same reason the
-- price is: the panel must show what the server will actually do. An older client that reads only the first
-- five or six fields still works and simply loses the units badge.
local function publishStock(items)
	local parts = {}
	for _, item in ipairs(items) do
		parts[#parts + 1] = table.concat({
			item.id, item.name, tostring(item.price), tostring(item.street or 0), item.desc,
			item.currency or "coins", tostring(item.units or -1),
		}, FIELD)
	end
	menu.Value = table.concat(parts, RECORD)
end

-- Move the shop to `win`: re-deal the rotating slots, reset every unit count, republish all three values.
-- `announce` is false for the very first apply at server start -- a player who joins a server that has been
-- up for nineteen minutes should not be told the stall just restocked when it did not.
local function applyWindow(win, announce)
	currentWin = win

	local rotating = rollWindow(win)
	local shelf = {}
	for _, item in ipairs(PERMANENT) do shelf[#shelf + 1] = item end
	for _, item in ipairs(rotating) do shelf[#shelf + 1] = item end

	activeById = {}
	remaining  = {}
	for _, item in ipairs(shelf) do
		activeById[item.id] = item
		if item.units then remaining[item.id] = item.units end
	end

	-- The deadline, converted onto the SERVER CLOCK the client also reads. os.time() decides WHEN the window
	-- ends (so all servers agree); GetServerTimeNow is the clock both ends can compare against without
	-- trusting the player's device.
	local secondsLeft = ((win + 1) * RESTOCK_SECONDS) - os.time()
	endsAt.Value = workspace:GetServerTimeNow() + secondsLeft

	publishStock(shelf)
	publishCounts()

	local names = {}
	for _, item in ipairs(rotating) do names[#names + 1] = item.name end
	local headline = table.concat(names, ", ")

	if announce then
		-- Everyone hears it, cave or not -- the banner's entire job is to send people TO the cave.
		restockEvent:FireAllClients(headline)
	end
	print(("[SecretTrader] window %d -- shelf restocked: %s (%ds left)"):format(win, headline, math.max(0, secondsLeft)))
end

--======================================================================
-- THE RESTOCK CLOCK
--======================================================================
-- Polls once a second rather than sleeping until the deadline: a task.wait of twenty minutes is a single
-- point of failure that silently ends the rotation for the life of the server if it is ever interrupted, and
-- the poll costs nothing. Comparing window INDEXES (not elapsed time) also means a long hitch or a suspended
-- server catches up to the correct window on the next tick instead of drifting one restock behind forever.
applyWindow(windowIndex(), false)
task.spawn(function()
	while true do
		task.wait(1)
		local win = windowIndex()
		if win ~= currentWin then
			applyWindow(win, true)
		end
	end
end)

--======================================================================
-- THE PURCHASE
--======================================================================
remote.OnServerEvent:Connect(function(player, id)
	-- MATCHED AGAINST THE ACTIVE SHELF ONLY. An id that exists in the pool but is not stocked this window is
	-- refused exactly like a made-up one -- otherwise the rotation would be a UI suggestion rather than a rule.
	local item = type(id) == "string" and activeById[id]
	if not item then
		reply:FireClient(player, false, "Sal doesn't have that today. Check the shelf.")
		return
	end

	-- ===== SOLD OUT =====
	-- Checked BEFORE the wallet, so a player who is both broke and too late is told the useful thing (it's
	-- gone) instead of the thing they could have fixed (they're short).
	local left = remaining[item.id]
	if left ~= nil and left <= 0 then
		reply:FireClient(player, false, "Sold out. Somebody beat you to the last one -- Sal restocks soon.")
		return
	end

	-- ===== WHICH WALLET =====
	-- Read the balance and prepare a charge for THIS item's currency. Tokens live in SkinCrateService, which
	-- owns clamping and persistence, so we never touch _G.playerCrateTokens directly -- we ask it to spend.
	local usingTokens = (item.currency == "tokens")
	local balance, charge

	if usingTokens then
		if type(_G.getSkinTokens) ~= "function" or type(_G.spendSkinTokens) ~= "function" then
			reply:FireClient(player, false, "Sal's token counter is busted. Try again in a minute.")
			warn("[SecretTrader] token hooks missing -- is SkinCrateService running?")
			return
		end
		balance = _G.getSkinTokens(player)
		charge  = function() return _G.spendSkinTokens(player, item.price) end
	else
		local coins = coinsOf(player)
		if not coins then return end
		balance = coins.Value
		charge  = function() coins.Value = coins.Value - item.price; return true end
	end

	local unit = usingTokens and "tokens" or "coins"
	if balance < item.price then
		reply:FireClient(player, false, ("Not enough %s -- you need %d."):format(unit, item.price))
		return
	end

	-- ===== HOLD THE UNIT BEFORE GRANTING =====
	-- item.grant can yield, and two players tapping the last Fat Sack in the same frame would BOTH pass the
	-- sold-out check above and both be served. Decrementing here -- before anything that can yield -- makes
	-- the second one lose the race properly. If the grant then fails, the unit is handed straight back below.
	if left ~= nil then
		remaining[item.id] = left - 1
		publishCounts()
	end

	-- GRANT FIRST, THEN CHARGE. If the grant fails (a service is down, they already own it) the player keeps
	-- their money. Charging first and refunding on failure is the same thing with an extra way to go wrong.
	-- On success, a grant may return its own message (the Mystery Sack announces what was inside).
	local ok, why = item.grant(player)
	if not ok then
		if left ~= nil then
			-- Put it back on the shelf. A refused grant must not consume stock, or a player repeatedly tapping
			-- a boost they already have would quietly empty the shelf for everybody else.
			remaining[item.id] = math.min(item.units, (remaining[item.id] or 0) + 1)
			publishCounts()
		end
		reply:FireClient(player, false, why or "Sal shakes his head.")
		return
	end

	-- The balance check above can go stale: grants yield, and a token spend elsewhere in that window would
	-- leave this one short. spendSkinTokens re-checks and refuses rather than going negative, so honour it.
	-- The player keeps the goods -- Sal ate the loss, and that is the right way round for a rounding error.
	if not charge() then
		warn(("[SecretTrader] %s: %s granted but the %s charge failed (balance moved mid-purchase)")
			:format(player.Name, item.id, unit))
	end

	reply:FireClient(player, true, why or ("Bought " .. item.name .. ". Pleasure doing business."))
	print(("[SecretTrader] %s bought %s for %d %s (%s left)")
		:format(player.Name, item.id, item.price, unit,
			remaining[item.id] and tostring(remaining[item.id]) or "unlimited"))
end)

print(("[SecretTrader] ready -- %d permanent + %d of %d rotating, restocking every %ds. Prices and stock are "
	.. "server-side and never read from the client."):format(#PERMANENT, ROTATING_SLOTS, #POOL, RESTOCK_SECONDS))
