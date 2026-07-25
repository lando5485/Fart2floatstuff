--======================================================================
-- WormholeService.server.luau   (Script -> ServerScriptService)
--======================================================================
-- ISLAND FAST-TRAVEL. The client's Wormhole menu asks to warp to an island via the WormholeWarp RemoteFunction;
-- we delegate to PlayerStats' _G.wormholeWarp, which is SERVER-AUTHORITATIVE: it validates the island against the
-- player's SAVED highestIslandReached (only islands you've actually reached), refuses while airborne, and places
-- the character on that island's stand (reusing the exact spawn/respawn placement). TRAVEL ONLY -- it never
-- unlocks an island or grants any progression.
--======================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function getOrCreate(cls, name)
	local o = ReplicatedStorage:FindFirstChild(name)
	if not o then o = Instance.new(cls); o.Name = name; o.Parent = ReplicatedStorage end
	return o
end

local WormholeWarp = getOrCreate("RemoteFunction", "WormholeWarp") -- client->server: (islandNum) -> { ok, reason? }

WormholeWarp.OnServerInvoke = function(player, islandNum)
	if type(_G.wormholeWarp) ~= "function" then
		return { ok = false, reason = "not_ready" } -- PlayerStats hasn't published the warp hook yet
	end
	local ok, reason = _G.wormholeWarp(player, islandNum) -- validates (reached-island gate + grounded) + places
	return { ok = ok and true or false, reason = reason }
end

print("[Wormhole] service ready -- island fast-travel via WormholeWarp (delegates to PlayerStats _G.wormholeWarp)")
