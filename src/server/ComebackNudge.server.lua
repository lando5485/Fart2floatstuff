-- ============================================================================================================
-- COMEBACK NUDGE -- "your pets have been busy, come collect your coins" as a real push notification the day after
-- a player leaves. The message itself is a STATIC template (no numbers in it) -- see the NOTIFICATION STRING note.
--
-- ===== WHY IT IS BUILT AS A QUEUE, NOT A TIMER =====
-- The obvious design is "when the player leaves, wait 20 hours, then send". That cannot work: the server the
-- player left is shut down within minutes of the last person leaving, taking any task.delay with it. And Roblox's
-- notification API has no "send later" -- it delivers immediately.
--
-- So the nudge is a QUEUE that any live server drains:
--   1. On LEAVE  -> write the player into a queue, stamped with WHEN they should be pinged (now + NUDGE_AFTER).
--   2. On JOIN   -> remove them from the queue. They came back on their own; pinging them now would be absurd.
--   3. Every 60s -> every server checks the queue for anyone whose time has come, and sends their notification.
-- Because the queue is an OrderedDataStore keyed on the wake-up time, "who is due?" is one cheap sorted read of
-- the earliest few entries -- we never scan the whole player base.
--
-- ===== THE DOUBLE-SEND PROBLEM =====
-- Every server runs the drain loop, so two of them can spot the same due player in the same minute. The fix is
-- RemoveAsync: it returns the value it removed, and of two concurrent removes on one key, exactly ONE gets the
-- value back and the other gets nil. So the server that gets a value has ATOMICALLY claimed that player, and it
-- is the only one that sends. No locks, no leader election.
--
-- ===== WHAT YOU MUST SET UP (3 things, all on the Creator Dashboard) =====
-- Nothing below sends anything until these exist. Missing config = loud log + no-op; it can never break the game.
--
--   1. NOTIFICATION STRING. Roblox does NOT let you send arbitrary text -- the message must be a pre-registered
--      template. Creator Dashboard -> your experience -> Engagement -> Notifications. Write it as a PLAIN,
--      STATIC sentence with NO {placeholder} in it:
--          "Your pets have been busy! Come back and collect your coins."
--      Register all SIX (see the MSG table below) and put each asset ID in it.
--
--      A placeholder would let the message name the actual figure ("...earned 240 coins..."), which is a much
--      stronger hook -- but it is a MATCHED PAIR with the code: the template's placeholders and the parameters
--      buildBody() sends must agree exactly, or Roblox rejects the send with a 400. This build sends none, so the
--      template must declare none. See the note above buildBody() if you ever want to add one back.
--
--   2. UNIVERSE ID. Creator Dashboard -> your experience -> the number in the URL. Put it in UNIVERSE_ID.
--
--   3. AN OPEN CLOUD API KEY with the notification write permission, scoped to this universe.
--      Create the key at Creator Dashboard -> Open Cloud -> API Keys. Set "Accepted IP Addresses" to 0.0.0.0/0 --
--      Roblox game servers have rotating IPs, and a narrower allowlist makes every send fail with a 403 that
--      looks exactly like an opt-in problem.
--
--      Then store it AS A SECRET -- NOT in this file, NOT in a StringValue, NOT anywhere in the place:
--          Creator Dashboard -> your experience -> Configure -> Secrets -> Add Secret
--          name:  notification_api_key      (must match SECRET_NAME below)
--          value: the key
--      Roblox REQUIRES this. It rejects a plain-string auth header sent to a roblox.com endpoint outright:
--          Header "x-api-key" must have its value be a secret for Roblox resources!
--      HttpService:GetSecret() returns an opaque Secret that can go in a header but can never be read back as
--      text -- so the key cannot leak into the repo, the place file, or a log, even by accident.
--
--   Also: Game Settings -> Security -> "Allow HTTP Requests" must be ON.
--
-- ===== NONE OF THIS WORKS IN STUDIO =====
-- Secrets do not resolve in Studio, so this always reports NOT ACTIVE there however correctly it is configured.
-- And the client-side opt-in prompt does not render in Studio either. Test in the PUBLISHED game.
--
-- ===== HONESTY ABOUT THE ENDPOINT =====
-- The Open Cloud notifications API has changed shape more than once. The request below is built against the v2
-- user-notifications endpoint. If sends fail with a 400, the field names are the thing to check first -- they are
-- all in buildBody() and nowhere else, precisely so a fix is a one-function edit.
-- ============================================================================================================

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The server tells the client when to raise the opt-in menu. Only the client can show it, but only the SERVER can
-- reliably hear a chat command (see the /optin handler) -- so the two halves have to talk.
local promptOptIn = ReplicatedStorage:FindFirstChild("PromptNotifyOptIn")
if not promptOptIn then
	promptOptIn = Instance.new("RemoteEvent")
	promptOptIn.Name = "PromptNotifyOptIn"
	promptOptIn.Parent = ReplicatedStorage
end

-- ===== CONFIG =====
local NUDGE_COOLDOWN_D  = 3      -- never nudge the same person more than once every 3 days, whatever they do
local MIN_COINS         = 25     -- do not send "your pets earned 4 coins". A worthless nudge teaches them to ignore
                                 -- the next one, which is the only thing that can actually kill this channel.
local DRAIN_EVERY       = 60     -- seconds between queue checks
local DRAIN_BATCH       = 20     -- how many due players one server handles per pass

local UNIVERSE_ID = 10236070926

-- ===== THE SIX MESSAGES =====
-- All STATIC -- no {placeholder} in any of them, so we send NO parameters. Those two facts are a MATCHED PAIR:
-- Roblox checks the parameters you send against the ones the template declares, and a mismatch in EITHER direction
-- is a 400. Put a placeholder back in a dashboard message and you must restore the `parameters` block in
-- buildBody() as well.
--
-- Six messages, not one, because "why did this person stop playing" has six different answers and a single generic
-- ping wastes five of them. The picker below chooses the most SPECIFIC one that fits.
local MSG = {
	DEFAULT   = "b041d446-f69a-8540-a932-4bf3c5451eb2", -- 1. "Your pets have been busy!"          (fallback)
	LAPSED    = "fb9d05ba-ebb7-8144-9d6c-7fa905cd94ea", -- 2. "It's been a while!"                 (stage 2 only)
	STUCK     = "2b42c0b2-8855-0c41-b26a-0aecaf5591b8", -- 3. "So close to the next island"        (island 1-2)
	NEARLY    = "1dc9b8e9-64e8-1e48-829d-674ad62dc494", -- 4. "Collection nearly complete"         (7-9 pets)
	FINISHED  = "1eea370c-ea61-4f46-b50f-5769d7550ce1", -- 5. "Your Pizza Dragon is waiting"       (10 pets)
	LONELY    = "3807685a-cdcf-e848-bd38-8a16b1404b82", -- 6. "Your Bean Buddy is lonely"          (starter only)
}

-- ===== TWO STAGES =====
-- Message 2 ("it's been a while") cannot possibly fire on the 20-hour nudge -- nobody is 7 days absent 20 hours
-- after leaving. It only makes sense as a SECOND nudge to someone who ignored the first one. So:
--
--   STAGE 1, at +20h : the state-aware message (stuck / nearly / finished / lonely / default).
--   STAGE 2, at +7d  : "it's been a while" -- but ONLY for someone who got stage 1 and STILL did not come back.
--
-- Rejoining at any point cancels whatever is queued, so a player who returns never receives either.
local STAGE1_HOURS = 20      -- 20h, not 24h: 24 drifts an hour later every day until it lands at 4am unseen
local STAGE2_HOURS = 24 * 7  -- measured from when they LEFT, so it is genuinely "a week since you played"

-- ===== THE API KEY -- IT MUST BE A ROBLOX *SECRET*, NOT A STRING =====
-- Roblox REFUSES to let you put a plain string in an auth header aimed at a roblox.com endpoint:
--     Header "x-api-key" must have its value be a secret for Roblox resources!
-- So the key cannot live in a StringValue, cannot live in this script, and cannot live in the place file. It has
-- to come from Roblox's own secret store via HttpService:GetSecret(), which hands back an opaque Secret object
-- that can be placed in a header but never read back out as text.
--
-- This is strictly better than what I first built: the key never touches the repo, never touches the .rbxl, and
-- cannot be printed by any script -- not even accidentally, into a log.
--
-- SET IT UP: Creator Dashboard -> your experience -> Configure -> Secrets -> Add Secret
--     name:   notification_api_key      (must match SECRET_NAME below, exactly)
--     value:  your Open Cloud API key
--
-- NOTE: secrets only resolve on a REAL server. GetSecret throws in Studio, by design -- so this will always report
-- NOT ACTIVE in Studio no matter how correctly it is set up. Test in the published game.
local SECRET_NAME = "notification_api_key"

local API_KEY = nil -- a Secret object, NOT a string
do
	local ok, res = pcall(function() return HttpService:GetSecret(SECRET_NAME) end)
	if ok and res then
		API_KEY = res
	else
		warn(("[Nudge] GetSecret('%s') failed: %s"):format(SECRET_NAME, tostring(res)))
		warn("[Nudge] ^ in Studio this is EXPECTED (secrets are live-server only). On a live server it means the"
			.. " secret does not exist -- add it under Configure -> Secrets with exactly that name.")
	end
end

local function messagesOk()
	for _, id in pairs(MSG) do
		if type(id) ~= "string" or id == "" then return false end
	end
	return true
end
local ACTIVE = (API_KEY ~= nil) and (UNIVERSE_ID > 0) and messagesOk()

-- Report the config state EVERY boot, whether it is good or bad. Deliberately NOT an early `return` any more: the
-- /nudge test command below stays alive even when nothing is configured, so it can tell you exactly WHICH of the
-- three pieces is missing instead of the script simply not existing.
local function configReport()
	if ACTIVE then
		print(("[Nudge] config OK -- universe %d, 6 messages registered, API key present"):format(UNIVERSE_ID))
		return
	end
	warn("[Nudge] NOT ACTIVE -- comeback push notifications cannot send. Missing:")
	if not API_KEY then
		warn(("[Nudge]   * the secret '%s' did not resolve."):format(SECRET_NAME))
		warn("[Nudge]     In STUDIO this is normal and unavoidable -- secrets are live-server only. Publish and"
			.. " test in the real game.")
		warn("[Nudge]     On a LIVE server it means the secret does not exist: Creator Dashboard -> your"
			.. " experience -> Configure -> Secrets -> Add Secret, named exactly '" .. SECRET_NAME .. "'.")
	end
	if UNIVERSE_ID <= 0 then warn("[Nudge]   * UNIVERSE_ID is not set (top of ComebackNudge.server.lua).") end
	if not messagesOk() then
		warn("[Nudge]   * One or more of the six notification string IDs in MSG is blank."
			.. " Every message must be registered on the Creator Dashboard (Engagement -> Notifications).")
	end
	warn("[Nudge] The game is unaffected. Type /nudge in-game to re-print this.")
end
configReport()

-- ===== STORES =====
-- queue  : ORDERED, so "who is due?" is a sorted read of the earliest entries, not a scan. value = wake-up time.
-- detail : the coin figure to put in the message (an OrderedDataStore can only hold the one sortable integer).
-- cooldown: last time we nudged each person, so we cannot pester someone who leaves and rejoins all day.
local queue, detail, cooldown
local okStores = pcall(function()
	queue    = DataStoreService:GetOrderedDataStore("NudgeQueue_v1")
	detail   = DataStoreService:GetDataStore("NudgeDetail_v1")
	cooldown = DataStoreService:GetDataStore("NudgeCooldown_v1")
end)
if not okStores then
	warn("[Nudge] DataStores unavailable (Studio API access off?) -- nudges disabled this session")
	return
end

-- ===== SEND =====
-- Every field Roblox cares about is in here. If a send starts failing after a Roblox API change, this is the
-- only function to correct.
local function buildBody(messageId)
	return HttpService:JSONEncode({
		source = { universe = "universes/" .. tostring(UNIVERSE_ID) },
		payload = {
			type = "MOMENT",
			messageId = messageId,
			-- No `parameters` -- the messages are static. See the note by the MSG table: if you add a
			-- {placeholder} to the dashboard template, you must add the matching parameters back HERE too.
		},
	})
end

-- ===== WHICH MESSAGE =====
-- Reads the SNAPSHOT taken when the player left, never the live player -- by the time this runs they are offline
-- and there is no character, no attributes, no _G.petsCollectedCount to ask. Anything the picker needs must have
-- been captured on the way out.
--
-- Most SPECIFIC first. The order is the design:
--   * finishers and near-finishers get their own message -- they are the easiest people to bring back and a
--     generic "collect your coins" is wasted on them.
--   * "stuck on island 1-2" is checked BEFORE "only has the starter pet", even though a stuck player usually IS
--     on one pet. Island progress is the bigger leak by far: people quit because they stalled climbing, not
--     because their Bean Buddy was lonely. The pet message is for someone who got past the early islands and
--     simply never engaged with hatching.
local function pickMessage(d)
	if d.stage == 2 then return MSG.LAPSED, "LAPSED (7d, ignored the first nudge)" end
	local collected = tonumber(d.collected) or 0
	local island    = tonumber(d.island) or 1
	if collected >= 10 then return MSG.FINISHED, "FINISHED (all 10 pets)" end
	if collected >= 7  then return MSG.NEARLY,   "NEARLY (7-9 pets)" end
	if island <= 2     then return MSG.STUCK,    "STUCK (island " .. island .. ")" end
	if collected <= 1  then return MSG.LONELY,   "LONELY (starter pet only)" end
	return MSG.DEFAULT, "DEFAULT"
end

-- `coins` no longer goes INTO the message (it is static now) -- it is kept purely so the log says how much the
-- player was owed when we pinged them, which is what makes a bad MIN_COINS setting visible.
local function sendNudge(userId, messageId, why, coins)
	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = ("https://apis.roblox.com/cloud/v2/users/%d/notifications"):format(userId),
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = API_KEY },
			Body = buildBody(messageId),
		})
	end)
	if not ok then
		warn(("[Nudge] send to %d threw: %s"):format(userId, tostring(res)))
		return false
	end
	if not res.Success then
		-- 403 here almost always means the player never opted in (see NotifyOptIn.client.luau) -- that is normal
		-- and not an error on our side, so it is logged quietly rather than as a failure to chase.
		warn(("[Nudge] send to %d rejected: HTTP %d %s"):format(userId, res.StatusCode, tostring(res.Body)))
		return false
	end
	print(("[Nudge] SENT to %d -- message %s (owed %d coins)"):format(userId, why, coins))
	return true
end

-- ===== SCHEDULE (on leave) / CANCEL (on join) =====
local function cancelNudge(player)
	local key = tostring(player.UserId)
	pcall(function() queue:RemoveAsync(key) end)
	pcall(function() detail:RemoveAsync(key) end)
end

-- Snapshot EVERYTHING the picker will need, because when the nudge actually fires the player is OFFLINE: no
-- character, no attributes, no _G.petsCollectedCount to ask. Whatever is not captured here is gone forever.
local function snapshot(player, coins, stage, leftAt)
	local collected = 0
	if type(_G.petsCollectedCount) == "function" then
		local ok, n = pcall(_G.petsCollectedCount, player)
		if ok and type(n) == "number" then collected = n end
	end
	return {
		coins     = coins,
		collected = collected,
		island    = math.floor(player:GetAttribute("HighestIsland") or 1),
		stage     = stage,
		leftAt    = leftAt,
	}
end

local function scheduleNudge(player)
	local key = tostring(player.UserId)

	-- respect the cooldown BEFORE we bother computing anything
	local okCd, last = pcall(function() return cooldown:GetAsync(key) end)
	if okCd and type(last) == "number" and (os.time() - last) < NUDGE_COOLDOWN_D * 86400 then
		return
	end

	-- What will they ACTUALLY be owed when they come back? Ask the same function that does the paying, so the
	-- nudge cannot claim their pets were busy when the welcome-back card then hands them nothing.
	if type(_G.offlinePreview) ~= "function" then return end
	local okP, r = pcall(_G.offlinePreview, player, STAGE1_HOURS * 3600)
	if not (okP and type(r) == "table") then return end

	local coins = math.floor(tonumber(r.coins) or 0)
	if coins < MIN_COINS then return end -- not worth a notification; sending it would just train them to ignore us

	local leftAt = os.time()
	local d = snapshot(player, coins, 1, leftAt)
	local _, why = pickMessage(d)
	pcall(function() detail:SetAsync(key, d) end)
	pcall(function() queue:SetAsync(key, leftAt + STAGE1_HOURS * 3600) end)
	print(("[Nudge] queued %s -- stage 1 in %dh, message %s (%d coins, %d pets, island %d)")
		:format(player.Name, STAGE1_HOURS, why, coins, d.collected, d.island))
end

if ACTIVE then
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(scheduleNudge, player)
	end)
end

-- ===== /nudge -- THE TEST COMMAND =====
-- You cannot test this the normal way: the real path is "leave, wait 20 hours, get pinged", and Studio cannot send
-- at all. /nudge does the whole thing to YOU right now -- picks the message your CURRENT state would earn, fires
-- the real Open Cloud request, and prints the raw HTTP status.
--
--   /nudge     -> the message your state picks (stuck / nearly / finished / lonely / default)
--   /nudge 2   -> force message 2, the 7-day "it's been a while" (otherwise unreachable in a test)
--
-- It bypasses the queue, the wait, the coin floor and the cooldown -- everything EXCEPT the two gates that really
-- bite and that cannot be faked: your account must have OPTED IN (see NotifyOptIn), and the config must be
-- complete. A 403 back means "this account never opted in" far more often than it means anything else.
Players.PlayerAdded:Connect(function(player)
	if ACTIVE then
		task.spawn(cancelNudge, player) -- they are HERE; whatever was queued is now pointless
	end

	player.Chatted:Connect(function(msg)
		local low = msg:lower()

		-- /optin -- ask the CLIENT to show the opt-in menu.
		--
		-- This is routed through the server on purpose. Player.Chatted is only dependable on the SERVER: with
		-- TextChatService (Roblox's current default) the client-side Chatted event frequently never fires, so a
		-- /optin listener living in the LocalScript silently does nothing -- which is exactly what it looked like.
		-- The server always hears the chat, so it hears the command and pokes the client, which is the only side
		-- that can actually raise the prompt.
		if low:sub(1, 6) == "/optin" then
			if type(_G.isAllowedTestUser) == "function" and not _G.isAllowedTestUser(player) then return end
			print("[Nudge] /optin from " .. player.Name .. " -> telling their client to show the opt-in menu")
			promptOptIn:FireClient(player)
			return
		end

		if low:sub(1, 6) ~= "/nudge" then return end
		if type(_G.isAllowedTestUser) == "function" and not _G.isAllowedTestUser(player) then return end

		print("[Nudge][TEST] ---- /nudge from " .. player.Name .. " ----")
		configReport()
		if not ACTIVE then
			print("[Nudge][TEST] aborted: not configured (see above). Nothing was sent.")
			return
		end

		local coins = 0
		if type(_G.offlinePreview) == "function" then
			local ok, r = pcall(_G.offlinePreview, player, STAGE1_HOURS * 3600)
			if ok and type(r) == "table" then coins = math.floor(tonumber(r.coins) or 0) end
		end
		if coins <= 0 then
			coins = 100 -- the real nudge would skip you; a test that silently sends nothing teaches you nothing
			print("[Nudge][TEST] you would earn 0 coins, using a dummy 100 -- the point is to prove the pipe works")
		end

		local forceStage2 = msg:find("2") ~= nil
		local d = snapshot(player, coins, forceStage2 and 2 or 1, os.time())
		local id, why = pickMessage(d)
		print(("[Nudge][TEST] your state: %d pets, island %d, owed %d coins -> message %s")
			:format(d.collected, d.island, coins, why))

		if sendNudge(player.UserId, id, why, coins) then
			print("[Nudge][TEST] ACCEPTED by Roblox. Check the bell icon in the Roblox app / roblox.com.")
			print("[Nudge][TEST] If nothing shows up, that account never opted in -- Roblox accepted the call and"
				.. " then delivered it to nobody. Type /optin and accept the prompt.")
		else
			-- READ THE BODY, not just the code. A 403 has three completely different causes and they are only
			-- distinguishable from the message Roblox sends back:
			--   "scope <user.notification:write> is missing"  -> the API KEY lacks the write permission
			--   (an IP complaint)                             -> the key's allowlist is not 0.0.0.0/0
			--   (neither, just denied)                        -> the PLAYER never opted in
			-- The first two are your setup; only the third is the player. Guessing "probably opt-in" wasted a
			-- round trip once already.
			print("[Nudge][TEST] REJECTED -- read the JSON body above, not just the code:")
			print("[Nudge][TEST]   403 + 'scope ... missing'  -> tick 'write' on the API key's notification system")
			print("[Nudge][TEST]   403 + IP complaint         -> set the key's Accepted IPs to 0.0.0.0/0")
			print("[Nudge][TEST]   403 + nothing else         -> this account never opted in (run /optin)")
			print("[Nudge][TEST]   401 = bad key | 400 = bad message id/body | 404 = wrong universe id")
		end
	end)
end)

-- ===== DRAIN =====
-- Ascending sort -> the earliest wake-up times come first, so we only ever look at the front of the queue.
task.spawn(function()
	while ACTIVE do
		task.wait(DRAIN_EVERY)

		local okPage, page = pcall(function() return queue:GetSortedAsync(true, DRAIN_BATCH) end)
		if okPage then
			local okRows, rows = pcall(function() return page:GetCurrentPage() end)
			if okRows and type(rows) == "table" then
				local now = os.time()
				for _, row in ipairs(rows) do
					if type(row.value) ~= "number" or row.value > now then
						break -- sorted ascending: the first not-yet-due entry means nothing after it is due either
					end

					-- CLAIM. Of two servers removing the same key at once, exactly one gets a value back. Only that
					-- server sends, so the player cannot be notified twice.
					local okClaim, claimed = pcall(function() return queue:RemoveAsync(row.key) end)
					if okClaim and claimed ~= nil then
						local userId = tonumber(row.key)
						local okD, d = pcall(function() return detail:GetAsync(row.key) end)
						d = (okD and type(d) == "table") and d or nil

						if userId and d and (tonumber(d.coins) or 0) >= MIN_COINS then
							local id, why = pickMessage(d)
							if sendNudge(userId, id, why, tonumber(d.coins) or 0) then
								pcall(function() cooldown:SetAsync(row.key, os.time()) end)
							end

							-- STAGE 1 -> STAGE 2. They ignored the first nudge, so queue the 7-day "it's been a
							-- while" for them. It is scheduled off leftAt (NOT off now), so it lands 7 days after
							-- they LEFT rather than 7 days after we happened to ping them.
							--
							-- Rejoining cancels it, so it only ever reaches someone who is still gone. And there is
							-- no stage 3 -- two unanswered notifications is the point where continuing to send stops
							-- being a nudge and starts being spam.
							if (tonumber(d.stage) or 1) == 1 then
								local leftAt = tonumber(d.leftAt) or now
								d.stage = 2
								pcall(function() detail:SetAsync(row.key, d) end)
								pcall(function() queue:SetAsync(row.key, leftAt + STAGE2_HOURS * 3600) end)
								print(("[Nudge] %d -> queued stage 2 (lapsed) for 7 days after they left")
									:format(userId))
							else
								pcall(function() detail:RemoveAsync(row.key) end) -- stage 2 done: no stage 3
							end
						else
							pcall(function() detail:RemoveAsync(row.key) end)
						end
					end
				end
			end
		end
	end
end)

if ACTIVE then
	print(("[Nudge] active -- stage 1 at +%dh (state-aware), stage 2 at +%dh (lapsed); min %d coins,"
		.. " %dd cooldown, universe %d")
		:format(STAGE1_HOURS, STAGE2_HOURS, MIN_COINS, NUDGE_COOLDOWN_D, UNIVERSE_ID))
end
