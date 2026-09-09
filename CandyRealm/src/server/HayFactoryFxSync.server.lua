--======================================================================
-- HayFactoryFxSync.server.lua
--======================================================================
-- MAKES THE HAY BALE FACTORY A PLACE WHERE YOU CAN SEE OTHER PEOPLE WORKING.
--
-- The factory on island19 is a LocalScript: every player builds their own copy of the building,
-- the belt and the press on the same marker block, and a bale one player presses exists on
-- exactly one screen. The yard used to be pre-filled with decorative bales, which hid that --
-- now the yard starts empty and only fills with bales somebody actually made, so without this
-- relay a busy factory would look abandoned to everyone but the person at the console.
--
-- THIS IS A RELAY, NOT A BUILDER. It creates no parts. A client says "I pressed a bale"; every
-- other client drops one in its own yard. Same shape as BakeryFxSync / MonsterEatSync -- if you
-- are changing one, read the others.
--
-- It cannot affect anyone's quest: the payload is one word and a position, the position is only
-- used to pick which yard the bale belongs to, and nothing here grants, moves or unlocks
-- anything. The whitelist and the rate limit are the entire security model, and that is
-- appropriate for a message whose worst case is a hay bale appearing on somebody's screen.
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local EVENT_NAME = "HayFactoryFxEvent"
local ev = ReplicatedStorage:FindFirstChild(EVENT_NAME)
if not ev then
	ev = Instance.new("RemoteEvent")
	ev.Name = EVENT_NAME
	ev.Parent = ReplicatedStorage
end

-- "tip" joined "bale": a trailer of straw being handed to the intake is the other visible thing
-- that happens at this building, and without it a delivery is a bale appearing from nowhere a
-- few seconds later. Same worst case as ever: some chaff puffs on somebody's screen.
local KINDS = { bale = true, tip = true }

-- a press cycle is over a second long, so this is several times faster than anyone can bale
local MAX_PER_SEC = 4
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
	-- NaN would poison every receiver's distance comparison, and a position out at 1e9 would drag
	-- a bale to the edge of the world. Neither is a thing an honest client sends.
	if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then return end
	if pos.Magnitude > 1e6 then return end
	if not allowed(plr) then return end

	-- FireAllClients, not per-player: the sender's own copy skips its own messages (it already
	-- has that bale on screen), and doing the filtering there keeps this relay free of any idea
	-- of who is standing where.
	ev:FireAllClients(plr, kind, pos)
end)

Players.PlayerRemoving:Connect(function(plr) seen[plr] = nil end)

print("[HayFactoryFxSync] ready -- island19 bale presses are shared (" .. EVENT_NAME .. ")")
