--======================================================================
-- MonsterSync.server.lua
--======================================================================
-- MAKES THE ISLAND-18 PANCAKE MONSTER A THING EVERYONE ON THE SERVER CAN SEE.
--
-- The monster is built and driven by PancakeMonsterQuest_AllInOne, a LocalScript. Every client
-- on island18 already builds its own copy asleep under the stack -- that part was never the
-- problem -- but the moment one kid pours the fifth syrup, the monster stands up and hunts on
-- THEIR SCREEN ONLY. To everybody else it is still face-down in the arena, and their friend is
-- sprinting across the island screaming at nothing.
--
-- THIS IS A RELAY, NOT A BRAIN. The waking player's client is the authority: it runs the whole
-- chase -- targeting, steering, ground raycasts, smashes -- exactly as it always has, and simply
-- posts where the body ended up. Every other client drops its own sleeping monster into a
-- follow mode and puts its body there. Nobody re-simulates anything, so the monster cannot
-- disagree with itself, and moving the AI to the server (a rewrite of ~600 lines) buys nothing.
--
-- WHY A STREAM HERE WHEN CarrySync DELIBERATELY HAS NONE. A carried prop hangs off a character
-- that already replicates, so its position is free. The monster is attached to nothing -- no
-- player, no server-owned part -- so somebody has to send it. 12 Hz with the receivers
-- interpolating is enough for a thing that moves slower than a walking kid.
--
-- IT ALSO CARRIES THE AMBIENT WANDER. Once a player who has FINISHED the quest is standing on
-- island18, the monster gets up and strolls around as scenery -- harmless, ignoring everyone --
-- and goes back to sleep under the stack when the last such player leaves. That stroll is
-- streamed the same way, by the lowest-UserId finisher present, so every kid sees it in the
-- same place. A hunt outranks a stroll; the receivers enforce that.
--
-- KINDS
--   "mon" + CFrame + "hunt"  -- where the body is now, while somebody is being chased
--   "mon" + CFrame + "roam"  -- ...while it is just wandering the island
--   "melt"                   -- the hunt is over; followers hand their monster back to itself
--
-- It cannot affect anyone's quest. A follower never runs the wake cinematic, never gains a
-- step, never scatters butter and never finishes anything -- see REM in the client, which is
-- careful to drive the BODY and nothing else. The worst a forged message can do is walk a
-- pancake around somebody's screen.
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local EVENT_NAME = "MonsterSyncEvent"
local ev = ReplicatedStorage:FindFirstChild(EVENT_NAME)
if not ev then
	ev = Instance.new("RemoteEvent")
	ev.Name = EVENT_NAME
	ev.Parent = ReplicatedStorage
end

-- WHICH MONSTER. One relay serves both because they are the same problem twice over, and a
-- second RemoteEvent with the same body would just be one more thing to keep in step. A player
-- can only ever host one of them -- hosting requires standing on that monster's island.
local IDS = {
	cake = true,     -- island18's Pancake Monster (PancakeMonsterQuest_AllInOne)
	choc = true,     -- island3's  Chocolate Monster (ChocolateMonster_AllInOne)
}

-- the client streams at 12 Hz; this leaves room for a frame-rate spike without ever letting a
-- modified client turn one monster into a flood
local MAX_PER_SEC = 24
local seen = {}          -- [player] = { n = count in this window, t = window start }
local lastSent = {}      -- [player] = { t = clock, id = which } -- were they driving one?

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

ev.OnServerEvent:Connect(function(plr, kind, id, cf, mode)
	-- the id is checked before anything else: an unknown one is dropped here rather than
	-- forwarded, so a modified client cannot make every screen look up a monster that is not
	-- in the game
	if not IDS[id] then return end
	if kind == "melt" then
		if not allowed(plr) then return end
		ev:FireAllClients(plr, "melt", id)
		return
	end
	if kind ~= "mon" then return end
	if typeof(cf) ~= "CFrame" then return end
	-- "hunt" beats "roam" on the receivers, so it is the one thing in this payload worth lying
	-- about: anything that is not exactly "hunt" is forwarded as the harmless wander.
	mode = (mode == "hunt") and "hunt" or "roam"
	-- NaN would poison every receiver's lerp permanently -- once a CFrame goes NaN it never
	-- comes back -- and a position out at 1e9 would drag the monster to the edge of the world.
	local p = cf.Position
	if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z then return end
	if p.Magnitude > 1e6 then return end
	if not allowed(plr) then return end

	-- FireAllClients, not per-player: the sender's own copy skips its own messages (it is the
	-- one that computed that CFrame in the first place) and doing the filtering there keeps this
	-- relay free of any idea of who is standing where.
	lastSent[plr] = { t = os.clock(), id = id }
	ev:FireAllClients(plr, "mon", id, cf, mode)
end)

Players.PlayerRemoving:Connect(function(plr)
	seen[plr] = nil
	-- THE AUTHORITY LEAVING IS THE END OF THE HUNT. Without this, everyone who was following
	-- their monster is left with it frozen mid-stride in a field forever.
	--
	-- ONLY IF THEY WERE ACTUALLY DRIVING IT. Firing this for every departure would hand the
	-- monster back to local control on every screen each time anybody anywhere in the server
	-- quit -- a visible hitch on island18 caused by someone leaving from a different island.
	local rec = lastSent[plr]
	if rec and os.clock() - rec.t < 2 then
		ev:FireAllClients(plr, "melt", rec.id)
	end
	lastSent[plr] = nil
end)

print("[MonsterSync] ready -- the island18 pancake monster is visible to everyone (" .. EVENT_NAME .. ")")
