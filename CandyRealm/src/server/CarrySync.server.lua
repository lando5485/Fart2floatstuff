--======================================================================
-- CarrySync.server.lua
--======================================================================
-- LETS OTHER PLAYERS SEE WHAT YOU ARE HOLDING, AND WHAT YOU ARE SITTING ON.
--
-- Every quest in this place is a LocalScript. That is deliberate -- it means five kids on one
-- island each get the whole quest instead of racing for one tractor -- but it has one ugly
-- side effect: the bale stack you are hauling to the farm house exists on exactly ONE screen.
-- To your friends you are a kid walking across a field holding nothing, and when you drive,
-- gliding along seated on thin air. That reads as a broken game, not as a personal quest.
--
-- THIS IS A RELAY, NOT A BUILDER, and it is deliberately the dumbest one in the place. A client
-- says "I am holding KIND" (or "nothing"); every other client renders that on the sender's own
-- character. Same shape as HayFactoryFxSync / BakeryFxSync / MonsterEatSync -- if you are
-- changing one, read the others.
--
-- WHY THERE IS NO POSITION IN THE PAYLOAD. A held prop hangs off the holder's HumanoidRootPart,
-- and that already replicates -- so the viewer knows where to draw it without being told. One
-- message per pickup and one per drop is the entire network cost, no matter how far anyone
-- walks. Anything that sent a position every frame would cost hundreds of times more and be
-- wrong more often, because it would be racing the character replication it has to agree with.
--
-- It cannot affect anyone's quest: the payload is one short word, the receiver only ever uses
-- it to look up a shape in a fixed table, and nothing here grants, moves or unlocks anything.
-- The whitelist and the rate limit are the entire security model, and that is right for a
-- message whose worst case is a hay bale appearing on somebody's shoulder.
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local EVENT_NAME = "CarryFxEvent"
local ev = ReplicatedStorage:FindFirstChild(EVENT_NAME)
if not ev then
	ev = Instance.new("RemoteEvent")
	ev.Name = EVENT_NAME
	ev.Parent = ReplicatedStorage
end

-- THE WHITELIST IS THE SECURITY MODEL. An unknown kind is dropped here rather than forwarded,
-- so a modified client cannot make every screen in the server try to build something. Adding a
-- carryable anywhere in the game means adding its id here AND in CarryView's KINDS table -- the
-- two lists have to agree or the prop silently never appears.
local KINDS = {
	balestack   = true,   -- island19: the finished five-bale stack, hauled to the farm house
	part_wheel  = true,   -- island19: the five tractor repair parts
	part_plug   = true,
	part_piston = true,
	part_rad    = true,
	part_steer  = true,
	tractor     = true,   -- island19: you are DRIVING -- draw a tractor under the driver
	axe         = true,   -- island4  (Camp S'mores): the chopping axe, welded to the hand
	pickaxe     = true,   -- island11 (Tunnel Blast): the mining pickaxe, same
	dynamite    = true,   -- island11: a crate of dynamite being walked to the X
}

-- Pickups are a human action: a player mashing E on a part they cannot reach is the fast case,
-- and that is still only a few a second. This is high enough never to clip real play and low
-- enough that a spamming client cannot make everyone else rebuild props in a loop.
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

-- LAST STATE PER PLAYER, so somebody who joins mid-game does not walk into a room full of
-- people holding invisible things. Without this, a player who picked up a bale stack before
-- you joined stays empty-handed on your screen until they happen to drop it.
local held = {}          -- [player] = kind

ev.OnServerEvent:Connect(function(plr, kind)
	-- nil is the "I am holding nothing" message and is always legal; anything else must be a
	-- known kind. Note the typeof check comes FIRST: a table or an Instance used as a key would
	-- be a perfectly valid lookup that simply misses, and this way it can never reach the table.
	if kind ~= nil then
		if typeof(kind) ~= "string" then return end
		if not KINDS[kind] then return end
	end
	if not allowed(plr) then return end
	if held[plr] == kind then return end     -- a repeat is not news; do not wake every client for it
	held[plr] = kind

	-- FireAllClients, not per-player: the sender's own copy skips its own messages (it already
	-- has the real prop on screen, built by the quest itself, and a second one would sit inside
	-- the first) and doing that filtering there keeps this relay free of any idea of who is where.
	ev:FireAllClients(plr, kind)
end)

-- A JOINER GETS THE ROOM AS IT ALREADY IS. Fired at the new player only, one message per player
-- who is actually holding something -- normally zero or one.
Players.PlayerAdded:Connect(function(plr)
	task.wait(2)                                   -- let their client's CarryView come up first
	if not plr.Parent then return end
	for other, kind in pairs(held) do
		if other ~= plr and other.Parent and kind then
			ev:FireClient(plr, other, kind)
		end
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	seen[plr] = nil
	held[plr] = nil
end)

print("[CarrySync] ready -- carried props and driven vehicles are visible to everyone (" .. EVENT_NAME .. ")")
