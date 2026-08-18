--!strict
-- ============================================================================================================
-- _G.grantPetAtRarity -- the ONLY way a pet above Common enters this realm.
-- ============================================================================================================
-- A pet has two INDEPENDENT axes (see Shared/PetRarity):
--
--   AGE     Baby -> Elder, derived from LEVEL, earned by playing. GROWN, never granted.
--   RARITY  Common -> Gold, fixed the moment the pet is obtained. FROZEN, never earned.
--
-- This grants the rarity axis. It is deliberately a small standalone script rather than surgery inside
-- whichever service happens to own pets in this realm: the pet table is assembled by several scripts whose
-- PlayerAdded order is not defined, and adding another writer to one of them is how those fights start. This
-- only ever writes a single key on demand, so it cannot race anyone.
--
-- STACKS, does not overwrite. Pulling a species you already own at a band you already own increments its
-- count -- duplicates are the fuel fusion runs on, so a repeat pull is progress rather than a wasted spin.
-- Different bands of the same species live in different slots and never clobber each other.
-- ============================================================================================================

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local PetRarity = require(RS:WaitForChild("Shared"):WaitForChild("PetRarity"))

_G.playerOwnedPets = _G.playerOwnedPets or {}

-- Same key scheme PetRarity documents: a Common pet is the bare species id -- which is byte-for-byte what
-- every pre-rarity save already wrote, so old saves load as Common with no migration.
local function variantKey(petId: string, band: string): string
	if band == PetRarity.DEFAULT then return petId end
	return petId .. "#" .. band
end

-- The realm's "your pets changed" remote, located by SUFFIX so this file needs no per-realm edit.
-- Cached once found; looked up lazily because the trade service that creates it may load after this script.
local changedRemote: RemoteEvent? = nil
local function petsChangedRemote(): RemoteEvent?
	if changedRemote and changedRemote.Parent then return changedRemote end
	for _, c in ipairs(RS:GetChildren()) do
		if c:IsA("RemoteEvent") and c.Name:sub(-#"PetsChangedEvent") == "PetsChangedEvent" then
			changedRemote = c
			return c
		end
	end
	return nil
end

-- Returns ok, newCount.
_G.grantPetAtRarity = function(player: Player?, petId: any, rarity: any): (boolean, number)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false, 0 end
	if type(petId) ~= "string" or petId == "" then return false, 0 end

	local band = PetRarity.normalise(rarity) -- unknown / forged band -> Common, never a junk key
	local key  = variantKey(petId, band)

	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	local owned = _G.playerOwnedPets[player]

	local existing = owned[key]
	local newCount
	if type(existing) == "table" then
		newCount = (tonumber(existing.count) or 1) + 1
		existing.count = newCount
	else
		-- Baby, level 1. A crate sells RARITY; it never sells a head start on growth.
		newCount = 1
		owned[key] = { level = 1, xp = 0, height = 0, time = 0, count = 1 }
	end

	print(string.format("[PetCrate] %s pulled %s %s (x%d)", player.Name, band, petId, newCount))

	-- Tell the client its pet list moved. Each realm names this remote for itself -- CandyPetsChangedEvent,
	-- SpacePetsChangedEvent -- so it is FOUND by suffix rather than hardcoded: one copy of this script then
	-- works in every realm, and a realm that renames its prefix does not silently stop refreshing.
	local changed = petsChangedRemote()
	if changed then pcall(function() changed:FireClient(player) end) end
	-- A crate pull creates a real item. That MUST hit the datastore now, not at the next autosave.
	if _G.savePlayerData   then pcall(_G.savePlayerData, player, "petcrate") end

	return true, newCount
end

--======================================================================================================
-- FUSION: N duplicates at one band -> ONE pet of the same species, one band up.
--======================================================================================================
-- The only route UP the rarity ladder that is not a crate pull. Costs come from PetRarity.FUSE_COST (5 at
-- the bottom, 10 at the top); the duplicates are consumed.
--
-- THE RESULT HATCHES AT BABY, LEVEL 1 -- deliberately, and it is the whole reason age and rarity are
-- separate axes. Age is grown by flying; carrying it across a fuse would turn "stockpile duplicates" into a
-- shortcut past the growth curve. You are buying a RARER pet, not an OLDER one.
--
-- FULLY SERVER-AUTHORITATIVE. The client sends a storage key and nothing else -- not a count, not a rarity,
-- not a destination band. All three are re-derived here from what the player actually owns, so a forged
-- "fuse my 1 Common into a Gold" is arithmetically impossible rather than merely rejected.
local function remote(name: string): RemoteEvent
	local e = RS:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = RS
	end
	return e :: RemoteEvent
end

local PetFuseEvent  = remote("PetFuseEvent")       -- c->s: (storageKey)
local PetFuseResult = remote("PetFuseResultEvent") -- s->c: (ok, info)

-- storage key -> species id. Strips any "#Band" suffix, matched against the KNOWN band list so a species id
-- that itself contained a '#' could never be truncated by accident.
local function speciesOf(key: string): string
	for _, band in ipairs(PetRarity.ORDER) do
		local suf = "#" .. band
		if key:sub(-#suf) == suf then return key:sub(1, -#suf - 1) end
	end
	return key
end

local function rarityOfKey(key: string): string
	for _, band in ipairs(PetRarity.ORDER) do
		local suf = "#" .. band
		if key:sub(-#suf) == suf then return band end
	end
	return PetRarity.DEFAULT
end

PetFuseEvent.OnServerEvent:Connect(function(player, storageKey)
	if type(storageKey) ~= "string" then return end
	local owned = _G.playerOwnedPets and _G.playerOwnedPets[player]
	local d = owned and owned[storageKey]
	if type(d) ~= "table" then return end -- you cannot fuse a stack you do not have

	local species = speciesOf(storageKey)
	local band    = rarityOfKey(storageKey) -- from the KEY, never from the client
	local have    = math.max(1, math.floor(tonumber(d.count) or 1))

	local ok, costOrReason = PetRarity.canFuse(band, have)
	if not ok then
		local why = (type(costOrReason) == "number")
			and string.format("Need %d more to fuse", costOrReason)
			or tostring(costOrReason)
		pcall(function() PetFuseResult:FireClient(player, false, { reason = why, key = storageKey }) end)
		return
	end

	local cost     = costOrReason
	local nextBand = PetRarity.nextOf(band)
	local destKey  = variantKey(species, nextBand :: string)

	-- consume, then create. In that order: if the destination write failed we would rather have taken nothing
	-- than have taken the duplicates and produced nothing.
	local left = have - cost
	if left <= 0 then
		owned[storageKey] = nil
	else
		d.count = left
	end

	local dest = owned[destKey]
	if type(dest) == "table" then
		dest.count = (tonumber(dest.count) or 1) + 1 -- already own this band -> stacks toward the NEXT fuse
	else
		owned[destKey] = { level = 1, xp = 0, height = 0, time = 0, count = 1 } -- Baby: grow it yourself
	end

	print(string.format("[PetFuse] %s fused %dx %s %s -> 1x %s %s (%d left)",
		player.Name, cost, band, species, tostring(nextBand), species, math.max(0, left)))

	pcall(function()
		PetFuseResult:FireClient(player, true, {
			petId = species, key = destKey,
			fromRarity = band, toRarity = nextBand, consumed = cost,
		})
	end)

	local changed = petsChangedRemote()
	if changed then pcall(function() changed:FireClient(player) end) end
	-- Fusion DESTROYS pets. That must hit the datastore now, not at the next autosave -- a rejoin after a
	-- crash that ate the duplicates but never wrote the upgrade is the one outcome players never forgive.
	if _G.savePlayerData then pcall(_G.savePlayerData, player, "petfuse") end
end)

Players.PlayerRemoving:Connect(function(p) if _G.playerOwnedPets then _G.playerOwnedPets[p] = nil end end)

print("[PetRarityGrants] ready -- _G.grantPetAtRarity(player, petId, rarity) is the only route to a non-Common pet")
