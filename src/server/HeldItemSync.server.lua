--======================================================================
-- HELD QUEST ITEM SYNC  (Script, server)
--======================================================================
-- MAKES HAND-HELD QUEST PROPS VISIBLE TO EVERYONE, AND TAKES THEM AWAY WHEN YOU LEAVE THEIR ISLAND.
--
-- The quest props in this game (the fishing rod on Butter Swamp, and anything built the same way later) are
-- CLIENT-BUILT: PetFollow spawns an anchored Model into the holder's own Workspace and CFrames it onto their
-- hand every frame. That is cheap and smooth, and it has one consequence -- the prop exists for exactly one
-- person. To everyone else you are stood at the lake miming a cast with empty hands.
--
-- The fix is NOT to move the prop to the server. Server-owned parts welded to a character replicate every
-- frame for every viewer, and this rod is redrawn on Heartbeat; that is a lot of network for decoration.
-- Instead the server replicates the ONE FACT that matters -- "this player is holding a FishingRod" -- and each
-- client draws its own local copy. This is the same shape as RemotePets, which renders other players' pets
-- from a broadcast rather than from replicated models, and it costs one string per player.
--
-- ===== WHY A PLAYER ATTRIBUTE AND NOT A REMOTE BROADCAST =====
-- Attributes set on a Player instance replicate to every client automatically and, crucially, are ALREADY SET
-- for someone who joins later. A FireAllClients broadcast is a one-shot: a player who joins after you picked
-- up the rod never hears it, and you look empty-handed to them for the rest of the session. The same reason
-- the island quest gate uses Island<N>QuestAccepted attributes instead of a remote.
--
-- ===== THE SERVER IS THE ONE THAT SAYS WHEN IT GOES AWAY =====
-- The holder's own client drops the prop when it leaves the item's leash (see PetFollow). That handles the
-- normal case. It does NOT handle dying, respawning, resetting, or leaving mid-cast -- in all of those the
-- client-side loop is gone before it can tidy up, and the attribute would be left set forever, so every OTHER
-- player would keep drawing a rod on a character who is not holding one. So the server clears it on death and
-- on respawn, which are the two events the client cannot be trusted to survive.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===== THE ITEM REGISTRY =====
-- Only names in here are accepted. A client can send any string it likes, and an unchecked attribute is a
-- free "draw arbitrary text above my head" for every other player's screen -- so the set is closed.
local KNOWN_ITEMS = {
	FishingRod = true, -- Butter Swamp (island 10), from the rod barrel
}

local ATTR = "HeldQuestItem"

local remote = ReplicatedStorage:FindFirstChild("HeldItemEvent")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "HeldItemEvent"
	remote.Parent = ReplicatedStorage
end

remote.OnServerEvent:Connect(function(player, itemId)
	if itemId == nil then
		player:SetAttribute(ATTR, nil) -- put it away
		return
	end
	if type(itemId) ~= "string" or not KNOWN_ITEMS[itemId] then
		warn("[HeldItem] " .. player.Name .. " sent unknown item '" .. tostring(itemId) .. "' -- ignored")
		return
	end
	player:SetAttribute(ATTR, itemId)
end)

-- ===== TOOLS GO HOME TOO =====
-- Anything handed out as a real Tool (the campfire's Marshmallow Stick, the gardener's watering can) is a
-- server object, so the server can take it back directly. A Tool opts in by carrying a QuestIsland attribute;
-- without one it is left alone, because plenty of tools are meant to travel with you.
--
-- Death is the trigger rather than a distance poll: respawning is what actually moves you off an island, and
-- Roblox already destroys the character. Anything that survived into the Backpack is what we clean up.
local function stripIslandTools(player)
	local bp = player:FindFirstChildOfClass("Backpack")
	if not bp then return end
	for _, t in ipairs(bp:GetChildren()) do
		if t:IsA("Tool") and t:GetAttribute("QuestIsland") then
			t:Destroy()
		end
	end
end

local function hook(player)
	player.CharacterRemoving:Connect(function()
		-- The holder's client cannot clear this itself -- its rod loop dies with the character. If we did not
		-- do it here, everyone else would keep drawing a rod on the respawned, empty-handed player.
		player:SetAttribute(ATTR, nil)
	end)
	player.CharacterAdded:Connect(function()
		player:SetAttribute(ATTR, nil)
		task.defer(stripIslandTools, player)
	end)
	player:SetAttribute(ATTR, nil)
end

for _, p in ipairs(Players:GetPlayers()) do hook(p) end
Players.PlayerAdded:Connect(hook)

print("[HeldItem] sync ready -- held quest props replicate as the '" .. ATTR ..
	"' player attribute, cleared on death/respawn")
