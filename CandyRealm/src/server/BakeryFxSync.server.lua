--======================================================================
-- BakeryFxSync.server.lua
--======================================================================
-- MAKES THE BAKE-OFF SOMETHING BYSTANDERS CAN SEE.
--
-- Island 15's Bake-Off is a LocalScript, like every quest in this realm: each player builds their
-- own ovens, their own hens and their own mixing station on the same marker blocks, and nothing
-- one player's script does exists on anybody else's screen. So a player standing next to you
-- could light both ovens, mix a bowl and collect a dozen eggs while, from where you were
-- standing, nothing whatsoever happened.
--
-- THIS IS A RELAY, NOT A BUILDER. It creates no parts. A client says "I just lit the oven at
-- roughly here" and the server passes that to everyone else, whose own local copy of that oven
-- lights up. Every player already has the props; what they were missing was the news.
--
-- Same shape as MonsterEatSync.server.lua, which does the identical job for the Chocolate
-- Monster -- if you are changing one, read the other.
--
-- WHAT IT DELIBERATELY DOES NOT DO: it never grants anything, never touches a quest's state and
-- never moves a player. Every payload is cosmetic, and the worst a forged one can do is make a
-- puff of smoke appear on somebody's screen -- which is why the whitelist below is the entire
-- security model, alongside a rate limit so it cannot be used as a spam channel.
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local EVENT_NAME = "BakeryFxEvent"
local ev = ReplicatedStorage:FindFirstChild(EVENT_NAME)
if not ev then
	ev = Instance.new("RemoteEvent")
	ev.Name = EVENT_NAME
	ev.Parent = ReplicatedStorage
end

-- the only four things a client may announce. Anything else is dropped without comment.
local KINDS = { ovenOn = true, ovenDone = true, egg = true, stir = true }

-- a generous ceiling that still stops a loop: a busy bake is a couple of these a second
local MAX_PER_SEC = 8
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

ev.OnServerEvent:Connect(function(plr, kind, pos)
	if not KINDS[kind] then return end
	if typeof(pos) ~= "Vector3" then return end
	-- a position from a client is only ever used to pick WHICH nearby prop to animate, so the
	-- only check it needs is that it is a real, finite number: NaN would poison every receiver's
	-- distance comparison and light up whichever oven happened to sort first.
	if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then return end
	if pos.Magnitude > 1e6 then return end
	if not allowed(plr) then return end

	-- FireAllClients, not FireClient-per-player: the sender's own script skips its own messages
	-- (it already played the effect locally), and doing that filtering on the client keeps this
	-- relay free of any idea of who is where.
	ev:FireAllClients(plr, kind, pos)
end)

Players.PlayerRemoving:Connect(function(plr) seen[plr] = nil end)

print("[BakeryFxSync] ready -- island15 bake-off effects are shared (" .. EVENT_NAME .. ")")
