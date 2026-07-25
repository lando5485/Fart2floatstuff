--======================================================================
-- MonsterEatSync.server.lua
--======================================================================
-- Lets the client-side Chocolate Monster hide a swallowed player from
-- EVERYONE. A LocalScript can only change transparency on its own screen
-- (property changes don't replicate client -> others), so when a player is
-- eaten the client fires this remote and the SERVER sets their character's
-- transparency -- which replicates to every client. Restored when spat out.
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local ev = ReplicatedStorage:FindFirstChild("MonsterEatEvent")
if not ev then
	ev = Instance.new("RemoteEvent")
	ev.Name = "MonsterEatEvent"
	ev.Parent = ReplicatedStorage
end

-- [player] = { [instance] = originalTransparency, ... }
local hidden = {}

local function restore(plr)
	local store = hidden[plr]
	if store then
		for inst, t in pairs(store) do
			if inst and inst.Parent then inst.Transparency = t end
		end
	end
	hidden[plr] = nil
end

local function hide(plr)
	local char = plr.Character
	if not char then return end
	restore(plr)               -- clear any stale record first
	local store = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			store[d] = d.Transparency; d.Transparency = 1
		elseif d:IsA("Decal") or d:IsA("Texture") then
			store[d] = d.Transparency; d.Transparency = 1
		end
	end
	hidden[plr] = store
end

ev.OnServerEvent:Connect(function(plr, eaten)
	if eaten then hide(plr) else restore(plr) end
	-- tell EVERY client who's trapped, so their monster shows a struggling belly bulge
	ev:FireAllClients(plr, eaten and true or false)
end)

-- never leave a player stuck invisible if they respawn or leave mid-gulp
Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function() hidden[plr] = nil end)
end)
Players.PlayerRemoving:Connect(function(plr) hidden[plr] = nil end)

print("[MonsterEatSync] ready -- hides swallowed players for everyone (MonsterEatEvent)")
