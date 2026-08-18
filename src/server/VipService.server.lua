-- ============================================================================================================
-- VIP SERVICE (server) -- the VIP gamepass's own perks.
-- ============================================================================================================
-- VIP has three effects and they live in three different places on purpose:
--
--   1) +25% COINS  -- NOT here. It is folded into RewardsService's pushState alongside the friend and group
--                     boosts, because _G.coinBonusMult is a SUM of perks and exactly one script may write it.
--                     A second writer here would silently stomp the friend/group boosts.
--   2) DAILY COINS -- here. A stipend, once per UTC day, persisted in its own DataStore.
--   3) THE TAG     -- NOT here. TitleTags.client draws it straight off the replicated HasVIP attribute, so it
--                     needs no remote and works for late joiners and other players' screens for free.
--
-- Ownership itself is decided in PlayerStats (the single UserOwnsGamePassAsync loop + the purchase handler),
-- which sets the HasVIP attribute. This file only ever READS that attribute -- it never asks Roblox anything,
-- so it costs no web calls and cannot disagree with the rest of the game about who is a VIP.
--
-- If the VIP pass has no id yet (Gamepasses.IDS.VIP == 0) nobody can own it, HasVIP is never set, and every
-- path below is inert. The service still loads and says so once in the log.
-- ============================================================================================================

local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local Gamepasses = require(RS:WaitForChild("Shared"):WaitForChild("Gamepasses"))

local STIPEND      = Gamepasses.VIP_DAILY_COINS
local DAILY_STORE  = DataStoreService:GetDataStore("VipDaily_v1")

-- Server -> client: the stipend landed. The client forwards it to NotifyCenter (VipClient.client) rather than
-- this file trying to build UI, which it cannot do anyway.
local function getOrCreate(parent, className, name)
	local inst = parent:FindFirstChild(name)
	if not inst then inst = Instance.new(className); inst.Name = name; inst.Parent = parent end
	return inst
end
local VipStipendEvent = getOrCreate(RS, "RemoteEvent", "VipStipendEvent") -- s->c: { amount = n }

-- UTC day number. Deliberately UTC and not the player's local midnight: a per-player timezone would let
-- someone claim twice by changing their clock, and os.time() on the server is the only clock we control.
local function today()
	return math.floor(os.time() / 86400)
end

-- Studio never persists the claim. Without this a dev testing VIP would get the stipend on their first Studio
-- run and then nothing for the rest of the day, which makes the feature look broken while you are building it.
-- (PlayerStats' DISABLE_SAVE_FOR_TESTING does the equivalent for the main save.)
local PERSIST = not RunService:IsStudio()

local claimedDay = {} -- [player] = day number already paid this session (guards a double-fire before the load returns)

local function grantStipend(player)
	if not Gamepasses.owns(player, "VIP") then return end

	local day = today()
	if claimedDay[player] == day then return end
	claimedDay[player] = day -- claim the slot BEFORE the async read, so two rapid triggers can't both pay out

	if PERSIST then
		local ok, last = pcall(function() return DAILY_STORE:GetAsync(tostring(player.UserId)) end)
		if not ok then
			-- A failed READ must not pay: assuming "not claimed" on a DataStore outage would hand every VIP in
			-- the server a free stipend every join until it recovered. Silently skip; they get it tomorrow, or
			-- on their next join once the store is healthy.
			claimedDay[player] = nil
			warn("[VIP] daily-store read FAILED for " .. player.Name .. " -- stipend skipped (never paid on a failed read)")
			return
		end
		if tonumber(last) == day then
			print("[VIP] " .. player.Name .. " already claimed today's stipend")
			return
		end
	end

	local ls = player:FindFirstChild("leaderstats")
	if not ls then ls = player:WaitForChild("leaderstats", 20) end
	local coins = ls and ls:FindFirstChild("Coins")
	local tce   = ls and ls:FindFirstChild("TotalCoinsEarned")
	if not coins then
		claimedDay[player] = nil -- never loaded -> let a later trigger retry rather than burning the day
		warn("[VIP] no leaderstats for " .. player.Name .. " -- stipend deferred")
		return
	end

	-- Same grant path the redeem-a-code reward uses (RewardsService): bump Coins, and TotalCoinsEarned so the
	-- stipend counts toward lifetime earnings and the leaderboards that read it.
	coins.Value = coins.Value + STIPEND
	if tce then tce.Value = tce.Value + STIPEND end

	if PERSIST then
		pcall(function() DAILY_STORE:SetAsync(tostring(player.UserId), day) end)
	end

	pcall(function() VipStipendEvent:FireClient(player, { amount = STIPEND }) end)
	print(("[VIP] paid %s the daily stipend: +%d coins (day %d)"):format(player.Name, STIPEND, day))
end

local function onPlayerAdded(player)
	-- Ownership is resolved ASYNCHRONOUSLY in PlayerStats (a UserOwnsGamePassAsync round trip), so HasVIP is
	-- usually NOT set yet at this instant. Two triggers cover it:
	--   * the attribute signal -- fires the moment ownership lands, and again on a mid-session purchase
	--   * a delayed sweep      -- covers a player who was ALREADY flagged before this connected
	player:GetAttributeChangedSignal(Gamepasses.ATTR.VIP):Connect(function()
		if player.Parent then task.spawn(grantStipend, player) end
	end)
	task.delay(8, function()
		if player.Parent then grantStipend(player) end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end -- Studio / hot reload

Players.PlayerRemoving:Connect(function(p) claimedDay[p] = nil end)

print(("[VIP] service ready -- +%d%% coins (via RewardsService), %d coins/day%s%s"):format(
	Gamepasses.VIP_COIN_PERK * 100, STIPEND,
	PERSIST and "" or " [STUDIO: stipend not persisted, pays every run]",
	Gamepasses.isConfigured("VIP") and "" or " -- VIP id NOT SET, nobody can own it yet"))
