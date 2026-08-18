--======================================================================
-- HideSpawnPads.server.luau  (ServerScriptService.HideSpawnPads)  -- CandyRealm
--======================================================================
-- Makes every SpawnLocation in the world INVISIBLE and NON-COLLIDABLE, at the owner's request: the pads
-- work, they just should not be seen or bumped into. Spawning is untouched -- `Enabled` is never written,
-- and Roblox places characters ABOVE a SpawnLocation, so collision plays no part in spawning itself.
--
-- ===== EXACTLY SpawnLocation, NOT "spawn"-NAMED PARTS =====
-- SpawnOnIsland1 / ReturnIsland also treat parts merely NAMED "spawn" as spawn markers, but this sweep
-- deliberately does not: those names catch things that are not pads at all ("monsterspawn" is the
-- chocolate monster's home marker, and several islands use spawn-named bricks as walk floors). Stripping
-- collision from a walk floor drops players through the island. SpawnLocation is an unambiguous class;
-- names are guesses. The finders keep working either way -- they match by class/name, not by visibility.
--
-- ===== WHY THE DECAL SWEEP TOO =====
-- Transparency = 1 hides the brick, but a SpawnLocation frequently carries its circular spawn Decal (or a
-- Texture) as a CHILD instance with its own Transparency -- so a "hidden" pad would still show a floating
-- spawn disc. Both are cleared.
--
-- ===== WHY THE WATCHER =====
-- Everything baked into the place is caught by the boot sweep (the server sees the whole Workspace at
-- once -- streaming only staggers CLIENTS). The DescendantAdded watcher is for pads created at RUNTIME by
-- a script or inserted live in Studio: they get the same treatment the moment they appear, deferred one
-- step because an instance is usually parented before its properties are set.
--======================================================================

local Workspace = game:GetService("Workspace")

local hidden = 0

local function hidePad(pad)
	if not pad:IsA("SpawnLocation") then return end
	local ok = pcall(function()
		pad.Transparency = 1
		pad.CanCollide = false
		-- the spawn disc rides on child Decals/Textures; the part's own Transparency does not touch them
		for _, d in ipairs(pad:GetDescendants()) do
			if d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = 1
			end
		end
	end)
	if ok then hidden += 1 end
end

for _, d in ipairs(Workspace:GetDescendants()) do
	hidePad(d)
end

Workspace.DescendantAdded:Connect(function(d)
	task.defer(function()
		if d.Parent then hidePad(d) end
	end)
end)

print(("[HideSpawnPads] %d spawn pad(s) made invisible + non-collidable (Enabled untouched -- spawning still works)")
	:format(hidden))
