--======================================================================
-- RetentionService.server.luau  (Script, ServerScriptService)
--======================================================================
-- THE "DON'T GO YET" CRATE. When a player presses the Roblox button to leave, they are offered a FREE Daily
-- Rewards crate -- once every 24 hours. Ported from the Space Realm, which has run this for a while.
--
-- ===== IT MAKES A CRATE READY, IT DOES NOT GRANT ANYTHING =====
-- This never rolls a reward and never hands out an item. All it does is clear the Daily Rewards cooldown, so
-- the crate the game ALREADY has becomes claimable again -- the "!" dot lights up and the player opens it
-- through the normal flow, which does the roll and the reveal. No second reward system, no silent grant, and
-- nothing to keep in sync with the crate's own rules.
--
-- ===== WHY THE CLIENT CANNOT FARM IT =====
-- The client only says "I am trying to leave". Everything that matters is decided here:
--   * COOLDOWN -- a rolling 24h from the LAST grant, stored as an os.time() stamp in PlayerState
--     (lastStayReward) and PERSISTED. os.time(), not os.clock(), so it is comparable across sessions; a
--     per-session clock would reset every server start and pay out once per join.
--   * FORCED SAVE on grant. The player is on their way out the door, so the ordinary PlayerRemoving save is
--     not good enough -- the whole failure mode here is "leave, rejoin, dodge the cooldown".
--   * ALREADY-READY CHECK. If their daily crate is claimable anyway, this returns false WITHOUT stamping the
--     cooldown. Otherwise a player who was already owed a crate would burn their 24h on a crate they had.
--
-- ===== WHAT THIS DELIBERATELY LEAVES OUT =====
-- Space also has an IDLE half: no input for 60s pops a "still there?" offer sharing this same cooldown. That
-- needs an activity-ping remote and a client watching input, and it is a separate feature -- this is only the
-- leave-attempt half. If the idle half is added later it should call straight into requestStayReward() below
-- so the two keep sharing one cooldown and cannot both pay out.
--======================================================================

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService          = game:GetService("RunService")

if _G.__RetentionServer then
	warn("[Retention] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__RetentionServer = true

local PlayerState = require(ServerScriptService:WaitForChild("PlayerState"))
local Constants   = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

-- Rolling 24h between free crates, per player.
local STAY_COOLDOWN = 24 * 60 * 60

-- The Daily Rewards cooldown, so we can tell whether their crate is ALREADY claimable and skip the grant.
-- Read from the same Constants block CrateService and CrateClient use, so the three cannot disagree.
local CRATE_COOLDOWN = (Constants.CRATE and tonumber(Constants.CRATE.COOLDOWN_SECONDS)) or (8 * 60 * 60)

--======================================================================
-- REMOTE
--======================================================================
local RequestStayReward = ReplicatedStorage:FindFirstChild("RequestStayReward")
if not RequestStayReward then
	RequestStayReward = Instance.new("RemoteFunction")
	RequestStayReward.Name = "RequestStayReward"
	RequestStayReward.Parent = ReplicatedStorage
end

--======================================================================
-- THE DECISION
--======================================================================
-- Returns { ok = true } when a crate was made ready, or { ok = false, reason = "..." }. The client shows its
-- banner ONLY on ok, so an ineligible or forged request produces nothing at all -- no banner, no sound, no
-- crate -- and the player just leaves.
local function requestStayReward(player)
	if not PlayerState.isLoaded(player) then
		return { ok = false, reason = "no_profile" }   -- profile not in yet: never guess, never grant
	end

	local now = os.time()

	-- ALREADY OWED A CRATE? Then this is worth nothing to them, so do not spend their 24h on it.
	local lastCrate = PlayerState.getLastCrateClaim(player)
	if lastCrate == 0 or now >= lastCrate + CRATE_COOLDOWN then
		return { ok = false, reason = "already_ready" }
	end

	-- COOLDOWN. 0 means never given, so a brand-new player is eligible the first time they go to leave --
	-- which is exactly the moment this feature exists for.
	local lastStay = PlayerState.getLastStayReward(player)
	if lastStay ~= 0 and (now - lastStay) < STAY_COOLDOWN then
		return { ok = false, reason = "cooldown" }
	end

	-- STAMP FIRST, then make the crate ready. Two requests racing in (a double MenuOpened, a spammed client)
	-- would otherwise both pass the check above and clear the crate twice off one eligibility window.
	PlayerState.setLastStayReward(player, now)

	-- MAKE READY = clear the daily crate's cooldown. setLastCrateClaim(0) is exactly what "never claimed"
	-- looks like, and CrateClient's isClaimable() already treats 0 as ready -- so the "!" dot lights and the
	-- normal open flow does the rest. Nothing is rolled or granted here.
	PlayerState.setLastCrateClaim(player, 0)

	-- The player is walking out the door RIGHT NOW; the PlayerRemoving save may not land. This is the one
	-- write that must not be lost, because losing it means a free crate every time they rejoin.
	pcall(PlayerState.save, player, "stay_reward")

	print(("[Retention] %s went to leave -> free Daily Rewards crate made ready (24h cooldown stamped + saved)")
		:format(player.Name))
	return { ok = true }
end

RequestStayReward.OnServerInvoke = function(player)
	local ok, res = pcall(requestStayReward, player)
	if not ok then
		warn("[Retention] request failed for " .. player.Name .. ": " .. tostring(res))
		return { ok = false, reason = "error" }
	end
	return res
end

-- Published so a future idle-popup half can reuse the identical path (and therefore the identical cooldown)
-- rather than growing a second one that could pay out alongside this.
_G.retentionRequestStayReward = requestStayReward

--======================================================================
if RunService:IsStudio() then
	print("[Retention] NOTE: the 24h cooldown is persisted through PlayerState's DataStore. In Studio that "
		.. "needs Game Settings > Security > Enable Studio Access to API Services, or it resets every run.")
end
print(("[Retention] ready -- pressing the Roblox leave button offers a FREE daily crate, once per %dh. "
	.. "Server-validated; makes the existing crate READY rather than granting anything."):format(STAY_COOLDOWN / 3600))
