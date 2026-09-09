-- ============================================================================
-- REWARDS SERVICE (server) — three features, all reward-validated server-side:
--   1) CODES        : redeem text codes for coins (RemoteFunction "RedeemCode"); per-player redeemed
--                     set persisted in its own DataStore so a code can't be claimed twice.
--   2) FRIEND BOOST : +25% earned coins while a Roblox friend shares the server (recomputed on join/leave).
--   3) GROUP PERK   : +10% earned coins for MLR Studios group members (checked on join). STACKS with the
--                     friend boost. Both feed _G.coinBonusMult[player], which PlayerStats applies to flight coins.
--   4) VIP PERK     : +25% earned coins for VIP gamepass owners. Folded in HERE rather than multiplied on
--                     somewhere else, because _G.coinBonusMult is a SUM of perks and a second writer would
--                     stomp this one -- pushState is the only thing allowed to set it.
--
-- Client UI lives in RewardsClient.client.lua. All coin grants happen here on the server.
-- ============================================================================

local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

-- =========================== EASY-EDIT CONFIG ===============================
-- Valid codes -> coin reward. Add/edit freely (codes are matched case-insensitively, spaces ignored).
local CODES = {
	["RELEASE"] = 500,
	["FART100"] = 1000,
}
-- Group id + url now come from the SHARED module, which also owns the LIVE membership lookup. Both used to
-- be hand-copied here, in SocialRewards and in GroupBannerClient, and the "must rejoin to claim" bug had to
-- be fixed in each of them independently. Same move as Gamepasses.luau above.
local GroupMembership = require(RS:WaitForChild("Shared"):WaitForChild("GroupMembership"))
local GROUP_ID  = GroupMembership.GROUP_ID   -- MLR Studios
local GROUP_URL = GroupMembership.GROUP_URL  -- shown in-game so non-members can join
local FRIEND_BOOST = 0.25  -- +25% coins when at least one Roblox friend is in the server
local GROUP_PERK   = 0.10  -- +10% coins for group members (stacks with the friend boost)
-- VIP's share lives in the shared Gamepasses module with the rest of the pass tuning, so the pass's value is
-- described in one place rather than half here and half there.
local Gamepasses = require(RS:WaitForChild("Shared"):WaitForChild("Gamepasses"))
local VIP_PERK   = Gamepasses.VIP_COIN_PERK  -- +25% coins for VIP owners (stacks with friend + group)
-- ============================================================================

-- --- remotes (created at runtime so no project.json edit is needed) ---
local function getOrCreate(parent, className, name)
	local inst = parent:FindFirstChild(name)
	if not inst then inst = Instance.new(className); inst.Name = name; inst.Parent = parent end
	return inst
end
local RedeemCode     = getOrCreate(RS, "RemoteFunction", "RedeemCode")  -- client invoke -> {ok, msg, amount}
local CoinBoostState = getOrCreate(RS, "RemoteEvent", "CoinBoostState") -- server -> client: {friend, group, mult}
local GroupInfo      = getOrCreate(RS, "RemoteEvent", "GroupInfo")      -- server -> client: {isMember, groupId, url}
local CheckGroupNow  = getOrCreate(RS, "RemoteFunction", "CheckGroupNow") -- client invoke -> {isMember, status}; re-reads membership WITHOUT a rejoin
-- NOTE: the recurring reminder banners (friend / daily / group) are scheduled CLIENT-side by RewardsClient
-- through one shared no-overlap queue + "safe to show?" gate. The server only supplies the boost/group state above.

-- ===================== 1) CODES (per-player redeemed set) ===================
local CODE_STORE = DataStoreService:GetDataStore("RedeemedCodes_v1")
local redeemed = {} -- [player] = { CODE = true, ... }  (loaded from DataStore on join)

local function loadRedeemed(p)
	local ok, data = pcall(function() return CODE_STORE:GetAsync(tostring(p.UserId)) end)
	redeemed[p] = (ok and type(data) == "table") and data or {}
end
local function saveRedeemed(p)
	if not redeemed[p] then return end
	pcall(function() CODE_STORE:SetAsync(tostring(p.UserId), redeemed[p]) end)
end

RedeemCode.OnServerInvoke = function(player, codeText)
	-- NEVER trust the client: validate the code, the already-used flag, and grant coins here.
	if type(codeText) ~= "string" then return { ok = false, msg = "Invalid code" } end
	local code = string.upper((codeText:gsub("%s+", ""))) -- normalise: upper-case, strip whitespace
	if code == "" then return { ok = false, msg = "Enter a code" } end
	local reward = CODES[code]
	if not reward then return { ok = false, msg = "Invalid code" } end
	redeemed[player] = redeemed[player] or {}
	if redeemed[player][code] then return { ok = false, msg = "Already used" } end

	local ls = player:FindFirstChild("leaderstats")
	local coins = ls and ls:FindFirstChild("Coins")
	local tce   = ls and ls:FindFirstChild("TotalCoinsEarned")
	if not coins then return { ok = false, msg = "Try again in a moment" } end

	coins.Value = coins.Value + reward
	if tce then tce.Value = tce.Value + reward end
	redeemed[player][code] = true
	task.spawn(saveRedeemed, player)
	print(("[Rewards] %s redeemed '%s' -> +%d coins"):format(player.Name, code, reward))
	return { ok = true, msg = ("Code redeemed! +%d coins"):format(reward), amount = reward }
end

-- ============ 2) + 3) FRIEND BOOST + GROUP PERK (stackable multiplier) ======
_G.coinBonusMult = _G.coinBonusMult or {} -- [player] = multiplier (1 = none); read by PlayerStats CoinEvent
local friendActive = {} -- [player] = bool (a friend shares the server)
local groupMember  = {} -- [player] = bool (in the MLR group; refreshed live -- see recheckGroup)

local function pushState(p)
	if not p.Parent then return end
	local mult = 1
	if friendActive[p] then mult = mult + FRIEND_BOOST end
	if groupMember[p]  then mult = mult + GROUP_PERK  end
	-- VIP is read straight off the replicated attribute PlayerStats sets on join/purchase -- no cached table to
	-- go stale, so buying VIP mid-session takes effect on the next pushState with no rejoin.
	local vip = Gamepasses.owns(p, "VIP")
	if vip then mult = mult + VIP_PERK end
	_G.coinBonusMult[p] = mult
	pcall(function() CoinBoostState:FireClient(p, { friend = friendActive[p] == true, group = groupMember[p] == true, vip = vip, mult = mult }) end)
	pcall(function() GroupInfo:FireClient(p, { isMember = groupMember[p] == true, groupId = GROUP_ID, url = GROUP_URL }) end)
end

-- Recompute "has a friend in the server" for EVERYONE (a join/leave changes it for the others too).
local function refreshFriends()
	local list = Players:GetPlayers()
	for _, p in ipairs(list) do
		local has = false
		for _, o in ipairs(list) do
			if o ~= p then
				local ok, isFriend = pcall(function() return p:IsFriendsWith(o.UserId) end)
				if ok and isFriend then has = true; break end
			end
		end
		friendActive[p] = has
		pushState(p)
	end
end

-- LIVE group re-read. Returns true the moment the player is confirmed to be in the group, and flips the
-- perk on for them there and then. GroupMembership rate-limits the underlying web call, so this is safe to
-- call from a client poll; a "cooldown"/"failed" answer is NEVER allowed to turn an existing member back
-- into a non-member (see the module header).
local function recheckGroup(p)
	if groupMember[p] then return true end
	local isMember, status = GroupMembership.isMember(p)
	if isMember then
		groupMember[p] = true
		print(("[Rewards] %s is an MLR group member -> +%d%% coin perk (%s)"):format(p.Name, GROUP_PERK * 100, status))
		pushState(p)
		return true
	end
	return false, status
end

-- The client calls this after it sends the player to the group page (and then a few times while the panel is
-- open). The CLIENT IS NEVER TRUSTED with the answer -- it only asks; the lookup and the grant happen here.
CheckGroupNow.OnServerInvoke = function(player)
	if not player or not player.Parent then return { isMember = false, status = "failed" } end
	local ok, status = recheckGroup(player)
	return { isMember = ok == true, status = (ok == true) and "member" or (status or "not-a-member") }
end

local function onPlayerAdded(p)
	_G.coinBonusMult[p] = 1
	task.spawn(loadRedeemed, p)
	-- GROUP: checked here on join, and again on demand from CheckGroupNow whenever the player presses
	-- JOIN GROUP in-game -- so joining the group mid-session applies the perk immediately. No rejoin.
	task.spawn(function()
		recheckGroup(p)
		pushState(p)
	end)
	-- VIP can be bought mid-session. PlayerStats sets HasVIP the moment the purchase completes, so watch the
	-- attribute and recompute -- otherwise the perk would not apply until the player rejoined, which is a
	-- terrible first impression for something they just paid for.
	p:GetAttributeChangedSignal(Gamepasses.ATTR.VIP):Connect(function()
		if p.Parent then pushState(p) end
	end)
	refreshFriends() -- this player joining may now give OTHERS a friend in the server
	-- Re-send state a couple times so the client (whose handlers may connect slightly later) reliably receives it.
	task.delay(4,  function() if p.Parent then pushState(p) end end)
	task.delay(10, function() if p.Parent then pushState(p) end end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end -- handle players already present (Studio / hot reload)

Players.PlayerRemoving:Connect(function(p)
	saveRedeemed(p)
	friendActive[p] = nil; groupMember[p] = nil; redeemed[p] = nil
	GroupMembership.forget(p)
	if _G.coinBonusMult then _G.coinBonusMult[p] = nil end
	task.defer(refreshFriends) -- someone leaving may remove the last friend for others
end)

print(("[Rewards] service ready (codes=%d, GROUP_ID=%d, friend +%d%% / group +%d%% / VIP +%d%%%s)"):format(
	(function() local n = 0 for _ in pairs(CODES) do n = n + 1 end return n end)(), GROUP_ID,
	FRIEND_BOOST * 100, GROUP_PERK * 100, VIP_PERK * 100,
	Gamepasses.isConfigured("VIP") and "" or " -- VIP id NOT SET, perk inert"))
