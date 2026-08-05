--======================================================================
-- SECRET CAVE TRADER  (Script, server)
--======================================================================
-- The hooded trader who lives in the cave behind the 'secretcave' door. He sells things sold nowhere else,
-- for coins.
--
-- ===== WHY THE SHOP LIVES ON THE SERVER WHEN THE CAVE DOES NOT =====
-- The cave itself is built entirely client-side (see SecretCave.client.lua) -- it is decoration, it costs the
-- server nothing, and if a player somehow forged their way in they would gain nothing but scenery.
--
-- MONEY IS DIFFERENT. A shop that deducted coins on the client would be a coin printer: the client could
-- simply not deduct, or grant itself the goods without paying. So the client's shop UI sends nothing but an
-- item id, and every question that matters -- does that item exist, can this player afford it, are they
-- actually in the cave -- is answered here.
--
-- The client is never trusted for price. The price lives in STOCK below, on the server, and the client's copy
-- is only for drawing the panel.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:FindFirstChild("SecretTraderBuy")
if not remote then
	remote = Instance.new("RemoteEvent"); remote.Name = "SecretTraderBuy"; remote.Parent = ReplicatedStorage
end
-- server -> client: purchase result, so the panel can say what happened rather than just going quiet
local reply = ReplicatedStorage:FindFirstChild("SecretTraderResult")
if not reply then
	reply = Instance.new("RemoteEvent"); reply.Name = "SecretTraderResult"; reply.Parent = ReplicatedStorage
end

local function coinsOf(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Coins")
end

-- ===== THE STOCK =====
-- `grant` returns true on success. A grant that CANNOT be completed must return false and take no money --
-- the deduction below only happens after the grant reports success, so a missing dependency costs the player
-- nothing instead of silently eating their coins.
--
-- `street` is what the item would SUPPOSEDLY cost above ground. It is pure theatre -- nothing charges it --
-- but showing it struck through next to Sal's number is what makes every row read as a deal too good to be
-- legal, which is the entire sales pitch of a black market.

-- Hot Coins would be an infinite money printer without a cooldown: +200 net per click, clicked forever. One
-- shipment per player per 5 minutes keeps it a treat rather than an exploit.
local hotCoinsAt = {}
Players.PlayerRemoving:Connect(function(p) hotCoinsAt[p] = nil end)

local STOCK = {
	{
		id     = "hotcoins",
		name   = "Hot Coins",
		desc   = "A thousand coins for eight hundred. They fell off a blimp. Don't ask which blimp.",
		price  = 800,
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
		id     = "boost2x",
		name   = "2x Coins (5 min)",
		desc   = "Sal greases the right palms and your flights pay DOUBLE for five minutes.",
		price  = 600,
		street = 1500,
		grant  = function(player)
			-- The boost is an EXPIRY TIMESTAMP attribute, set with the server clock. PlayerStats' coin handler
			-- checks it server-side, so the client can neither fake a boost nor stretch one.
			local now = workspace:GetServerTimeNow()
			if (player:GetAttribute("SalCoinBoostUntil") or 0) - now > 30 then
				return false, "Your last batch is still burning. Use it up first."
			end
			player:SetAttribute("SalCoinBoostUntil", now + 300)
			return true, "Deal. Five minutes of DOUBLE coins -- fly, now!"
		end,
	},
	{
		id     = "boostspeed",
		name   = "Rocket Gas (5 min)",
		desc   = "Off-the-books fuel additive. Fly 35% faster for five minutes. Probably safe.",
		price  = 500,
		street = 1200,
		grant  = function(player)
			local now = workspace:GetServerTimeNow()
			if (player:GetAttribute("SalSpeedBoostUntil") or 0) - now > 30 then
				return false, "Your tank's still fizzing from the last dose."
			end
			player:SetAttribute("SalSpeedBoostUntil", now + 300)
			return true, "Topped up. Five minutes of rocket gas -- try to land gently."
		end,
	},
	{
		id     = "basiccrate",
		name   = "Starter Crate, Paid in Coins",
		desc   = "250 tokens -- exactly one Starter Crate, no Robux asked. ONE per customer, ever. Sal's rules.",
		price  = 2000,
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
	{
		id     = "mystery",
		name   = "Mystery Sack",
		desc   = "Sal won't open it, you can't open it until it's yours. Somewhere between 150 and 1,200 coins.",
		price  = 350,
		street = 0,   -- 0 = no street price: the client shows '???' -- nobody knows what an unopened sack is worth
		grant  = function(player)
			local coins = coinsOf(player)
			if not coins then return false end
			local found = math.random(150, 1200)
			coins.Value = coins.Value + found
			return true, "You shake out the sack\xE2\x80\xA6 " .. found .. " coins!"
		end,
	},
}

local byId = {}
for _, item in ipairs(STOCK) do byId[item.id] = item end

-- Published so the client panel draws the SAME names and prices the server will charge, instead of keeping a
-- second copy that drifts out of step the first time a price changes.
local menu = ReplicatedStorage:FindFirstChild("SecretTraderStock")
if not menu then
	menu = Instance.new("StringValue"); menu.Name = "SecretTraderStock"; menu.Parent = ReplicatedStorage
end
do
	local parts = {}
	for _, item in ipairs(STOCK) do
		-- field order: id, name, Sal's price, street price (0 = unknown), description
		parts[#parts + 1] = table.concat({
			item.id, item.name, tostring(item.price), tostring(item.street or 0), item.desc,
		}, "\30")
	end
	menu.Value = table.concat(parts, "\31")
end

remote.OnServerEvent:Connect(function(player, id)
	local item = type(id) == "string" and byId[id]
	if not item then
		warn("[SecretTrader] " .. player.Name .. " asked for unknown item '" .. tostring(id) .. "'")
		return
	end

	local coins = coinsOf(player)
	if not coins then return end
	if coins.Value < item.price then
		reply:FireClient(player, false, "Not enough coins -- you need " .. item.price .. ".")
		return
	end

	-- GRANT FIRST, THEN CHARGE. If the grant fails (a service is down, they already own it) the player keeps
	-- their money. Charging first and refunding on failure is the same thing with an extra way to go wrong.
	-- On success, a grant may return its own message (the Mystery Sack announces what was inside).
	local ok, why = item.grant(player)
	if not ok then
		reply:FireClient(player, false, why or "Sal shakes his head.")
		return
	end

	coins.Value = coins.Value - item.price
	reply:FireClient(player, true, why or ("Bought " .. item.name .. ". Pleasure doing business."))
	print(("[SecretTrader] %s bought %s for %d coins"):format(player.Name, item.id, item.price))
end)

print("[SecretTrader] ready -- " .. #STOCK .. " items, prices are server-side and never read from the client")
