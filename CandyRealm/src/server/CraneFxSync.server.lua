--======================================================================
-- CraneFxSync.server.lua
--======================================================================
-- MAKES THE BEANLIFT CRANE A MACHINE OTHER PEOPLE CAN WATCH YOU DRIVE.
--
-- The cleanup quest on the Cocoa Reactor is a LocalScript, and it poses the crane by writing
-- CFrames onto BeanLiftCrane's own parts. A client CFraming a Workspace part changes nothing
-- for anybody else -- so the operator saw a boom swinging, a hook paying out and a crate hauling
-- sludge to the bin, and every other player on the island saw a crane standing perfectly still
-- with somebody frozen on the boarding pad next to it.
--
-- THIS IS A RELAY, NOT A DRIVER. It creates and moves nothing. The operator says "my boom is at
-- 143 degrees, hook down 12, rolled 4, carrying"; every other client puts ITS copy of the crane
-- in that pose. Same shape as HayFactoryFxSync / BakeryFxSync -- if you are changing one, read
-- the others.
--
-- It cannot affect anyone's quest. The payload is three numbers and two flags, receivers apply
-- it to scenery only, and nothing here grants, unlocks, moves a player or touches a pile's
-- collected state. Every viewer's own progress is still driven entirely by their own client.
-- The whitelist, the number validation and the rate limit are the whole security model, and the
-- worst case they are guarding is a crane pointing the wrong way on somebody's screen.
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local EVENT_NAME = "CraneFxEvent"
local ev = ReplicatedStorage:FindFirstChild(EVENT_NAME)
if not ev then
	ev = Instance.new("RemoteEvent")
	ev.Name = EVENT_NAME
	ev.Parent = ReplicatedStorage
end

-- "pose" is the machine's attitude; "board"/"exit" bracket it so a viewer knows whether anyone
-- is actually at the controls. "claim"/"release" are the seats.
local KINDS = { pose = true, board = true, exit = true, claim = true, release = true }

-- ===== THE SEATS =====
-- One crane, one lab terminal, one person at each. The arbitration has to live here: two clients
-- both seeing "free" on the same frame is exactly the race a client-side check cannot settle.
local STATIONS = { crane = true, terminal = true }
local held = {}          -- [station] = { plr = Player, at = os.clock() }

-- A client that crashes, or is teleported out mid-scan, never sends its release. Without an
-- expiry the desk would be locked for the rest of the server's life by somebody who isn't there:
-- every held station is therefore refreshed by its owner's own traffic and let go after a lull.
local STALE_AFTER = 25

local function holderOf(station)
	local rec = held[station]
	if not rec then return nil end
	if rec.plr.Parent ~= Players or os.clock() - rec.at > STALE_AFTER then
		held[station] = nil
		return nil
	end
	return rec.plr
end

local function announce(station)
	local who = holderOf(station)
	ev:FireAllClients(nil, "busy", station, who and who.Name or nil)
end

-- The operator sends at most ~12 poses a second (the client throttles on its side); 20 leaves
-- headroom for a frame burst without letting a modified client stream at RenderStepped.
local MAX_PER_SEC = 20
local seen = {}          -- [player] = { n = count in this window, t = window start }

local function allowed(plr)
	local now = os.clock()
	local rec = seen[plr]
	if not rec or now - rec.t >= 1 then
		seen[plr] = { n = 1, t = now }
		return true
	end
	rec.n += 1
	return rec.n <= MAX_PER_SEC
end

-- NaN fails every comparison, so it would sail through a naive range check and then poison the
-- receiver's CFrame maths. Test it explicitly, then clamp: these are the crane's own limits with
-- room to spare, and a value outside them is not something an honest client sends.
local function num(v, lo, hi)
	if typeof(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
	return math.clamp(v, lo, hi)
end

ev.OnServerEvent:Connect(function(plr, kind, slew, drop, drive, carrying)
	if not KINDS[kind] then return end
	if not allowed(plr) then return end

	if kind == "claim" or kind == "release" then
		local station = slew                    -- the second argument is the station name here
		if not STATIONS[station] then return end
		local who = holderOf(station)
		if kind == "release" then
			if who == plr then held[station] = nil; announce(station) end
			return
		end
		if who and who ~= plr then
			-- somebody got there first: tell the asker, and re-state who holds it so their copy
			-- of `busy` is right even if they missed the original broadcast
			ev:FireClient(plr, "grant", station, false, who.Name)
			return
		end
		held[station] = { plr = plr, at = os.clock() }
		ev:FireClient(plr, "grant", station, true, plr.Name)
		announce(station)
		return
	end

	if kind ~= "pose" then
		ev:FireAllClients(plr, kind)
		return
	end

	-- an operator's own poses are what keep their crane claim alive (see STALE_AFTER)
	local rec = held.crane
	if rec and rec.plr == plr then rec.at = os.clock() end

	local s = num(slew, -100000, 100000)     -- the slew angle accumulates in degrees, unwrapped
	local d = num(drop, 0, 500)              -- hoist pay-out, studs below rest
	local r = num(drive, -200, 200)          -- roller travel along the boom axis
	if not (s and d and r) then return end

	-- FireAllClients, not per-player: the sender's own copy ignores its own messages (it is the
	-- one driving), and doing that filtering on the client keeps this relay free of any idea of
	-- who is standing where.
	ev:FireAllClients(plr, "pose", s, d, r, carrying and true or false)
end)

Players.PlayerRemoving:Connect(function(plr)
	seen[plr] = nil
	-- an operator who leaves mid-swing never sends its own "exit", and without this every other
	-- client would hold their crane in that player's last pose forever -- and the seat they were
	-- sitting in would stay locked until it went stale
	ev:FireAllClients(plr, "exit")
	for station, rec in pairs(held) do
		if rec.plr == plr then held[station] = nil; announce(station) end
	end
end)

-- A player who joins after somebody has already sat down has an empty `busy` table, so their
-- client would happily let them open a terminal that is in use. Tell every arrival what is
-- currently taken -- once, on join, and only about stations somebody is actually holding.
Players.PlayerAdded:Connect(function()
	task.delay(4, function()
		for station in pairs(STATIONS) do
			if holderOf(station) then announce(station) end
		end
	end)
end)

print("[CraneFxSync] ready -- BeanLiftCrane operation is shared (" .. EVENT_NAME .. ")")
