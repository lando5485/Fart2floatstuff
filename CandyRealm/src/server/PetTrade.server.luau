--!nonstrict
--======================================================================
-- PetTrade.server.luau  (Script, ServerScriptService)  -- CandyRealm, PORTED FROM THE FOOD REALM
-- (via the Space Realm's working copy -- identical protocol; only realm-specific names differ)
--======================================================================
-- LIVE PLAYER-TO-PLAYER TRADING. Two players, both online, both looking at the same offer, both confirming.
--
-- The Food realm has this inside PetSystem; this realm never did, which is why its hub had a TRADE tab that
-- only ever meant the trade-up contract. Same remotes, same payload shape and the same anti-scam stages as
-- Food, so the behaviour a player learned there is the behaviour they get here.
--
-- ===== WHAT MAKES A TRADE SAFE =====
-- The classic scam is swapping your offer in the instant before the other person's click lands, so they
-- confirm something different from what they read. Three things stop it:
--
--   1. ANY change to EITHER offer -- items or tokens -- clears BOTH readies.
--   2. Once both sides are READY the offers FREEZE and a countdown runs. Nothing can be added or removed
--      during it, so the last thing you saw is the thing that trades.
--   3. After the countdown BOTH sides press CONFIRM one more time, on an offer that can no longer change.
--
-- Cancel is available at every stage right up to the swap, and cancelling costs nothing -- no item moves
-- until both final confirmations are in.
--
-- ===== AND WHAT MAKES IT NOT DUPLICATE =====
-- executeTrade runs start to finish with NO YIELDS. Ownership of every offered item is re-validated at
-- execution rather than trusted from when it was added, the removes happen before the adds, and both players
-- are saved immediately afterwards. A yield anywhere in that block is a duplication window, and a duplicated
-- rare is not a bug you can quietly patch -- it is permanently in the economy.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if _G.__CandyPetTrade then
	warn("[Trade] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__CandyPetTrade = true

_G.playerOwnedPets   = _G.playerOwnedPets   or {}
_G.playerEquippedPet = _G.playerEquippedPet or {}

local function remote(name, class)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(class or "RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local PetTradeRequest = remote("PetTradeRequestEvent")        -- c->s: (targetUserId)
local PetTradeRespond = remote("PetTradeRespondEvent")        -- c->s: (accept:bool)
local PetTradePrompt  = remote("PetTradeRequestPromptEvent")  -- s->c: (fromUserId, fromName)
local PetTradeOffer   = remote("PetTradeOfferEvent")          -- c->s: (key, add:bool)
local PetTradeTokens  = remote("PetTradeTokensEvent")         -- c->s: (amount)
local PetTradeConfirm = remote("PetTradeConfirmEvent")        -- c->s: () ready / final-confirm
local PetTradeCancel  = remote("PetTradeCancelEvent")         -- c->s: ()
local PetTradeState   = remote("PetTradeStateEvent")          -- s->c: (perspective state)
-- Space serves its pet list through a RemoteFunction the client PULLS (GetSpaceRealmPets), with nothing to
-- tell it the list changed. A trade changes it from the outside, so this is the nudge to re-fetch.
local PetsChanged     = remote("CandyPetsChangedEvent")       -- s->c: ()

--======================================================================
-- STATE
--======================================================================
local tradeOf     = {}   -- [player] = session. One trade per player, so an item can never be in two at once.
local incomingReq = {}   -- [targetPlayer] = requesterPlayer, one pending incoming request

local TRADE_STAGE_OFFER     = "offer"
local TRADE_STAGE_COUNTDOWN = "countdown"
local TRADE_STAGE_FINAL     = "final"
local TRADE_COUNTDOWN_SEC   = 5

--======================================================================
-- ITEMS
--======================================================================
-- Skins ride the SAME session as pets, arriving as "SKIN:<pet>|<skin>|<trait>" over the same offer remote.
-- That is how skins became tradable without a second trade system, a second window, or any change to the
-- handshake. Every path is guarded: with the skin service absent, isSkinKey is never true and the whole file
-- behaves as if only pets existed.
local SKIN_PREFIX = "SKIN:"
local function isSkinKey(k) return type(k) == "string" and k:sub(1, #SKIN_PREFIX) == SKIN_PREFIX end
local function skinKeyOf(k) return k:sub(#SKIN_PREFIX + 1) end

local function ownsPet(player, key)
	local owned = _G.playerOwnedPets[player]
	return (type(owned) == "table" and owned[key] ~= nil)
end

local function prettyName(key)
	local base = tostring(key):gsub("#R$", "")
	return (base:gsub("(%l)(%u)", "%1 %2"))
end

local function petBrief(owner, skey)
	if isSkinKey(skey) then
		if not _G.skinTradeBrief then return nil end
		local ok, brief = pcall(_G.skinTradeBrief, owner, skinKeyOf(skey))
		return ok and brief or nil
	end
	local d = _G.playerOwnedPets[owner] and _G.playerOwnedPets[owner][skey]
	if not d then return nil end
	if type(d) ~= "table" then d = {} end
	return {
		key   = skey,
		petId = tostring(skey):gsub("#R$", ""),
		name  = prettyName(skey),
		level = tonumber(d.level) or 1,
		rare  = (d.rare == true) or (tostring(skey):match("#R$") ~= nil),
	}
end

local function offerList(owner, offerSet)
	local list = {}
	for skey in pairs(offerSet) do
		local b = petBrief(owner, skey)
		if b then list[#list + 1] = b end
	end
	return list
end

local function keyList(set)
	local t = {}
	for k in pairs(set) do t[#t + 1] = k end
	return table.concat(t, ",")
end

-- Crate Tokens live in SkinCrateService. Guarded: if that service failed to load, trading reports a zero
-- balance and the token half is simply unusable, rather than erroring out the whole window.
local function tokenBalance(player)
	if not _G.crateTokensBalance then return 0 end
	local ok, n = pcall(_G.crateTokensBalance, player)
	return (ok and tonumber(n)) or 0
end

--======================================================================
-- STATE PUSH
--======================================================================
local function tradeStatus(myC, theirC)
	if myC and theirC then return "trading"
	elseif myC then return "waiting_them"
	elseif theirC then return "waiting_you"
	else return "open" end
end

-- Back to a live, editable offer. Used whenever anything about the deal changes.
local function resetTradeStage(session)
	session.stage = TRADE_STAGE_OFFER
	session.confirmA, session.confirmB = false, false
	session.finalA, session.finalB = false, false
	session.countdownEnds = nil
	-- Invalidates any in-flight countdown thread, so an edited (or cancelled, or re-opened) trade can never
	-- be pushed into the final stage by a stale timer.
	session.countdownToken = (session.countdownToken or 0) + 1
end

local function sendTradeState(session)
	local A, B = session.a, session.b
	local stage = session.stage or TRADE_STAGE_OFFER
	-- Seconds left, recomputed per push rather than counted down on the client, so a laggy client can never
	-- show a longer window than the server is actually enforcing.
	local left = 0
	if session.countdownEnds then left = math.max(0, math.ceil(session.countdownEnds - tick())) end

	local function payload(me, them, myOffer, theirOffer, myC, theirC, myF, theirF, myTok, theirTok)
		return {
			active = true, withName = them.Name,
			mine = offerList(me, myOffer), theirs = offerList(them, theirOffer),
			myConfirm = myC, theirConfirm = theirC,
			status = tradeStatus(myC, theirC),
			myTokens = myTok, theirTokens = theirTok,
			myTokenBalance = tokenBalance(me),
			stage = stage, countdown = left,
			myFinal = myF, theirFinal = theirF,
			locked = (stage ~= TRADE_STAGE_OFFER),   -- client greys out add/remove while true
		}
	end

	pcall(function() if A.Parent then PetTradeState:FireClient(A,
		payload(A, B, session.offerA, session.offerB, session.confirmA, session.confirmB,
			session.finalA, session.finalB, session.tokensA or 0, session.tokensB or 0)) end end)
	pcall(function() if B.Parent then PetTradeState:FireClient(B,
		payload(B, A, session.offerB, session.offerA, session.confirmB, session.confirmA,
			session.finalB, session.finalA, session.tokensB or 0, session.tokensA or 0)) end end)
end

local function closeTrade(session, reason, doneFlag)
	if not tradeOf[session.a] and not tradeOf[session.b] then return end   -- already closed
	tradeOf[session.a] = nil; tradeOf[session.b] = nil
	pcall(function() if session.a.Parent then PetTradeState:FireClient(session.a, { active = false, reason = reason }) end end)
	pcall(function() if session.b.Parent then PetTradeState:FireClient(session.b, { active = false, reason = reason }) end end)
	if not doneFlag then print("[Trade] CANCELLED (" .. tostring(reason) .. ")") end
end

--======================================================================
-- THE SWAP
--======================================================================
-- ATOMIC and server-validated. Runs synchronously -- no yields -> no duplication window.
local function executeTrade(session)
	local A, B = session.a, session.b
	if not (A.Parent and B.Parent) then closeTrade(session, "a player left"); return end

	-- RE-CHECKED AT EXECUTION, not trusted from when the item was added. Between offering and confirming a
	-- player can open a crate, equip, fuse or trade elsewhere.
	local function stillOwns(who, key)
		if isSkinKey(key) then
			if not _G.skinTradeOwns then return false end
			local ok, owns = pcall(_G.skinTradeOwns, who, skinKeyOf(key))
			return ok and owns == true
		end
		return ownsPet(who, key)
	end
	for k in pairs(session.offerA) do
		if not stillOwns(A, k) then closeTrade(session, A.Name .. " no longer owns " .. k); return end
	end
	for k in pairs(session.offerB) do
		if not stillOwns(B, k) then closeTrade(session, B.Name .. " no longer owns " .. k); return end
	end

	-- Same rule for tokens: promising tokens you no longer hold must FAIL the trade, never quietly transfer
	-- less than the other side agreed to.
	local tokA = math.max(0, math.floor(session.tokensA or 0))
	local tokB = math.max(0, math.floor(session.tokensB or 0))
	if tokA > 0 and not (_G.crateTokensCanAfford and _G.crateTokensCanAfford(A, tokA)) then
		closeTrade(session, A.Name .. " no longer has " .. tokA .. " tokens"); return
	end
	if tokB > 0 and not (_G.crateTokensCanAfford and _G.crateTokensCanAfford(B, tokB)) then
		closeTrade(session, B.Name .. " no longer has " .. tokB .. " tokens"); return
	end

	local op = _G.playerOwnedPets
	print(("[Trade] EXECUTING %s[%s] <-> %s[%s]"):format(A.Name, keyList(session.offerA), B.Name, keyList(session.offerB)))

	-- Snapshot the UNIT each side gives, remove ONE from each giver, then add ONE to each receiver. Offers are
	-- STORAGE KEYS (petId or petId#R), so a normal and a rare of one species are independent units and cannot
	-- overwrite each other.
	local function snapshot(owner, skey)
		if isSkinKey(skey) then
			if not _G.skinTradeUnit then return nil end
			local ok, unit = pcall(_G.skinTradeUnit, owner, skinKeyOf(skey))
			return ok and unit or nil
		end
		local d = op[owner] and op[owner][skey]
		if type(d) ~= "table" then return nil end
		return { level = d.level, xp = d.xp, rare = d.rare }
	end

	local function removeOne(owner, skey)
		if isSkinKey(skey) then
			if _G.skinTradeRemoveOne then pcall(_G.skinTradeRemoveOne, owner, skinKeyOf(skey)) end
			return
		end
		local d = op[owner] and op[owner][skey]
		if not d then return end
		local c = (tonumber(d.count) or 1) - 1
		if c <= 0 then op[owner][skey] = nil else d.count = c end
	end

	local function addOne(owner, skey, unit)
		if not unit then return end
		if isSkinKey(skey) then
			if _G.skinTradeAddOne then pcall(_G.skinTradeAddOne, owner, unit) end
			return
		end
		op[owner] = op[owner] or {}
		local d = op[owner][skey]
		if d then
			-- Same exact key -> stack, keeping the HIGHER level so no progress is lost either way.
			d.count = (tonumber(d.count) or 1) + 1
			if (unit.level or 1) > (tonumber(d.level) or 1) then d.level = unit.level; d.xp = unit.xp or 0 end
		else
			op[owner][skey] = { level = unit.level or 1, xp = unit.xp or 0, rare = unit.rare or nil, count = 1 }
		end
	end

	local giveA, giveB = {}, {}
	for k in pairs(session.offerA) do giveA[k] = snapshot(A, k) end
	for k in pairs(session.offerB) do giveB[k] = snapshot(B, k) end

	for k in pairs(session.offerA) do removeOne(A, k) end
	for k in pairs(session.offerB) do removeOne(B, k) end

	-- Tokens move inside the same no-yield window as the items. Validated ten lines above, so a false here
	-- means the balance changed between two lines of straight-line code -- it is logged rather than unwound
	-- because nothing could have consumed it.
	if tokA > 0 and _G.crateTokensTrade and not _G.crateTokensTrade(A, B, tokA) then
		warn("[Trade] token transfer A->B failed unexpectedly (" .. tokA .. ")")
	end
	if tokB > 0 and _G.crateTokensTrade and not _G.crateTokensTrade(B, A, tokB) then
		warn("[Trade] token transfer B->A failed unexpectedly (" .. tokB .. ")")
	end

	for k, unit in pairs(giveA) do addOne(B, k, unit) end
	for k, unit in pairs(giveB) do addOne(A, k, unit) end

	-- Keep equip state sane if the followed pet was traded away.
	for _, who in ipairs({ A, B }) do
		local eq = _G.playerEquippedPet[who]
		if eq and not ownsPet(who, eq) then _G.playerEquippedPet[who] = nil end
	end

	tradeOf[A] = nil; tradeOf[B] = nil
	print(("[Trade] DONE - %s <-> %s"):format(A.Name, B.Name))

	-- Refresh both clients FIRST (the swap is already done in memory), THEN persist -- saving yields.
	pcall(function() PetsChanged:FireClient(A) end)
	pcall(function() PetsChanged:FireClient(B) end)
	if _G.skinTradeAfter then pcall(_G.skinTradeAfter, A); pcall(_G.skinTradeAfter, B) end
	pcall(function() if A.Parent then PetTradeState:FireClient(A, { active = false, reason = "completed" }) end end)
	pcall(function() if B.Parent then PetTradeState:FireClient(B, { active = false, reason = "completed" }) end end)

	-- Persist BOTH immediately. The window between the swap and the next autosave is the one place a server
	-- crash could hand one side both halves of the deal.
	if _G.savePlayerData then
		pcall(function() _G.savePlayerData(A, "trade") end)
		pcall(function() _G.savePlayerData(B, "trade") end)
	end
end

--======================================================================
-- HANDSHAKE
--======================================================================
PetTradeRequest.OnServerEvent:Connect(function(player, targetUserId)
	if tradeOf[player] then return end
	local target = Players:GetPlayerByUserId(tonumber(targetUserId) or 0)
	if not target or target == player or tradeOf[target] then return end
	incomingReq[target] = player
	print(("[Trade] %s requested trade with %s"):format(player.Name, target.Name))
	pcall(function() PetTradePrompt:FireClient(target, player.UserId, player.Name) end)
end)

PetTradeRespond.OnServerEvent:Connect(function(player, accept)
	local requester = incomingReq[player]; incomingReq[player] = nil
	if not (requester and requester.Parent) then return end
	if accept == true and not tradeOf[player] and not tradeOf[requester] then
		local session = {
			a = requester, b = player,
			offerA = {}, offerB = {},
			confirmA = false, confirmB = false,
			tokensA = 0, tokensB = 0,
			finalA = false, finalB = false,
			stage = TRADE_STAGE_OFFER, countdownToken = 0,
		}
		tradeOf[requester] = session; tradeOf[player] = session
		print(("[Trade] %s accepted trade with %s"):format(player.Name, requester.Name))
		sendTradeState(session)
	else
		print(("[Trade] %s declined trade from %s"):format(player.Name, requester.Name))
		pcall(function()
			if requester.Parent then PetTradeState:FireClient(requester, { active = false, reason = "declined" }) end
		end)
	end
end)

PetTradeOffer.OnServerEvent:Connect(function(player, key, add)
	local session = tradeOf[player]
	if not session or type(key) ~= "string" then return end
	-- FROZEN once both sides are ready. A late add is REFUSED outright rather than silently resetting
	-- everyone to the offer stage -- the whole point of the countdown is that what you read is what you get.
	if (session.stage or TRADE_STAGE_OFFER) ~= TRADE_STAGE_OFFER then return end

	local mine = (session.a == player) and session.offerA or session.offerB
	if add == true then
		if isSkinKey(key) then
			local owns = false
			if _G.skinTradeOwns then
				local ok, r = pcall(_G.skinTradeOwns, player, skinKeyOf(key))
				owns = ok and r == true
			end
			if not owns then return end
			mine[key] = true
		else
			if not ownsPet(player, key) then return end   -- can only offer what you actually own
			if _G.playerEquippedPet[player] == key then
				-- Auto-unequip: offering the pet that is following you should not leave a follower attached
				-- to something you are about to give away.
				_G.playerEquippedPet[player] = nil
				pcall(function() PetsChanged:FireClient(player) end)
			end
			mine[key] = true
		end
	else
		mine[key] = nil
	end

	resetTradeStage(session)   -- ANY offer change clears BOTH readies
	sendTradeState(session)
end)

PetTradeTokens.OnServerEvent:Connect(function(player, amount)
	local session = tradeOf[player]; if not session then return end
	if (session.stage or TRADE_STAGE_OFFER) ~= TRADE_STAGE_OFFER then return end
	local n = math.floor(tonumber(amount) or 0)
	if n < 0 then n = 0 end
	n = math.min(n, tokenBalance(player))   -- clamped to what they actually hold, re-checked at execution
	if session.a == player then
		if session.tokensA == n then return end
		session.tokensA = n
	else
		if session.tokensB == n then return end
		session.tokensB = n
	end
	resetTradeStage(session)
	sendTradeState(session)
end)

-- ONE button, three meanings by stage: READY while building, inert during the countdown, CONFIRM once it is
-- done. Keeping it on a single remote means the window needs no second verb -- the button relabels itself.
PetTradeConfirm.OnServerEvent:Connect(function(player)
	local session = tradeOf[player]; if not session then return end
	local isA = (session.a == player)
	local stage = session.stage or TRADE_STAGE_OFFER

	if stage == TRADE_STAGE_COUNTDOWN then return end   -- the timer has to finish first

	if stage == TRADE_STAGE_FINAL then
		if isA then session.finalA = true else session.finalB = true end
		print(("[Trade] %s gave FINAL confirmation"):format(player.Name))
		if session.finalA and session.finalB then executeTrade(session) else sendTradeState(session) end
		return
	end

	if isA then session.confirmA = true else session.confirmB = true end
	if not (session.confirmA and session.confirmB) then
		sendTradeState(session)
		return
	end

	session.stage = TRADE_STAGE_COUNTDOWN
	session.countdownEnds = tick() + TRADE_COUNTDOWN_SEC
	local myToken = session.countdownToken or 0
	print(("[Trade] both ready -> %ds countdown"):format(TRADE_COUNTDOWN_SEC))
	sendTradeState(session)

	task.spawn(function()
		-- Ticks once a second so the window can show the number falling, re-checking validity each time.
		for _ = 1, TRADE_COUNTDOWN_SEC do
			task.wait(1)
			if session.countdownToken ~= myToken then return end                 -- edited or cancelled
			if not tradeOf[session.a] or not tradeOf[session.b] then return end   -- closed
			sendTradeState(session)
		end
		if session.countdownToken ~= myToken then return end
		if not tradeOf[session.a] or not tradeOf[session.b] then return end
		session.stage = TRADE_STAGE_FINAL
		session.countdownEnds = nil
		print("[Trade] countdown done -> FINAL confirmation required from both sides")
		sendTradeState(session)
	end)
end)

PetTradeCancel.OnServerEvent:Connect(function(player)
	local session = tradeOf[player]
	if session then closeTrade(session, "cancelled by " .. player.Name) end
end)

Players.PlayerRemoving:Connect(function(player)
	-- No item loss and no dupe: nothing swaps until both final confirmations are in, so an abandoned trade
	-- simply ends.
	local session = tradeOf[player]
	if session then closeTrade(session, player.Name .. " left") end
	incomingReq[player] = nil
	for tgt, req in pairs(incomingReq) do
		if req == player then incomingReq[tgt] = nil end
	end
end)

print("[Trade] live skin/token trading ready (Candy Realm -- realm 1's protocol; pets side inert until Candy grows a pet server)")
