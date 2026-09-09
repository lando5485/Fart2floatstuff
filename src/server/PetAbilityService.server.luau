-- ==============================================================================================================
-- PET ABILITY SERVICE -- turns "who is equipped, at what level, how many copies" into a set of plain numbers.
--
-- WHY A SERVICE AND NOT A FUNCTION CALL: the systems that need these numbers are scattered (the coin chain in
-- PlayerStats, crate luck in SkinCrateService, the AFK farm, the XP award in PetSystem, and two client-side
-- pickup paths). Having each of them reach into PetSystem's private tables would be six copies of the same
-- resolution logic, drifting apart the first time a rule changed. Instead this resolves once and publishes the
-- answer two ways:
--   * `_G.petAbility(player, lever)` for server code
--   * a `PetAbil_<lever>` ATTRIBUTE on the player for client code
-- Attributes replicate for free and are server-written/client-read-only, so the client can price a bubble
-- without a remote round-trip and without being trusted -- every coin it then claims still goes through
-- CoinEvent's existing validation and 8,000 cap.
--
-- RECOMPUTED, NEVER INCREMENTED. Equipping, levelling, fusing, trading and buying all change the answer, and
-- half of those live in scripts that have no idea this file exists. So rather than hunting every mutation site
-- and hoping none is ever missed, this recomputes the whole set from scratch on a cheap timer and on demand.
-- The work is a loop over one player's pets -- microseconds -- and it can never drift out of sync.
-- ==============================================================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30)
if not Shared then warn("[PetAbil] no Shared folder -- abilities disabled"); return end
local modOk, PetAbilities = pcall(function() return require(Shared:WaitForChild("PetAbilities", 20)) end)
if not modOk or not PetAbilities then
	warn("[PetAbil] PetAbilities module missing from ReplicatedStorage.Shared -- is it in default.project.json? Abilities disabled.")
	return
end

-- How strongly a pet you OWN but have not EQUIPPED counts. Zero for everyone except through Prism Fox, whose
-- whole ability is to switch this on. Kept as a named constant because it is the one number that decides
-- whether the collection is a loadout or a shelf.
local UNEQUIPPED_WEIGHT = 0

-- ===== READING PETSYSTEM =====
-- PetSystem owns the data; this only reads it. Everything is pcall-guarded and falls back to "no pets", so a
-- PetSystem that has not finished booting yields neutral multipliers rather than an error in a coin path.
local function speciesOf(key)
	if type(key) ~= "string" then return key end
	local cut = key:find("#")
	return cut and key:sub(1, cut - 1) or key
end

-- Which storage keys are currently equipped. Today that is exactly one (PetSystem keeps a single
-- `playerEquippedPet`), but the design calls for 2 slots rising to 5, so this returns a LIST from the start --
-- when slots land, only this function changes and every consumer below already handles the plural.
local function equippedKeys(player)
	local out = {}
	local multi = _G.playerEquippedPets                     -- future: [player] = { key, key, ... }
	if type(multi) == "table" and type(multi[player]) == "table" then
		for _, k in ipairs(multi[player]) do if type(k) == "string" then table.insert(out, k) end end
		if #out > 0 then return out end
	end
	local single = _G.playerEquippedPet and _G.playerEquippedPet[player]
	if type(single) == "string" then table.insert(out, single) end
	return out
end

-- Every (species -> { level, copies }) the player owns, folded across rarity variants. A Gold Popcorn Sheep and
-- a Common one are the same ABILITY, two copies deep -- rarity is a look and a trade value, not a second power.
local function ownedBySpecies(player)
	local byS = {}
	local op = _G.playerOwnedPets and _G.playerOwnedPets[player]
	if type(op) ~= "table" then return byS end
	for key, v in pairs(op) do
		if type(v) == "table" then
			local sp = speciesOf(key)
			local lv = math.clamp(tonumber(v.level) or 1, 1, PetAbilities.MAX_LEVEL)
			local n  = math.max(1, math.floor(tonumber(v.count) or 1))
			local e  = byS[sp]
			if not e then
				byS[sp] = { best = lv, copies = n }
			else
				e.best   = math.max(e.best, lv)   -- the strongest copy leads; the rest fall off behind it
				e.copies = e.copies + n
			end
		end
	end
	return byS
end

-- ===== THE RESOLVER =====
-- Returns { [lever] = finalNumber }. Deltas are SUMMED then finalised once, never compounded -- five pets at
-- "+8% each" must land on +40%, not the 1.08^5 = +47% a product would silently give.
local function resolve(player)
	local acc = {}
	for lever in pairs(PetAbilities.LEVERS) do acc[lever] = 0 end

	local owned    = ownedBySpecies(player)
	local equipped = equippedKeys(player)

	-- Which species are actually in a slot (deduped -- two slots holding the same species is still one species,
	-- and its depth is already counted by the duplicate curve below).
	local equippedSpecies = {}
	for _, key in ipairs(equipped) do equippedSpecies[speciesOf(key)] = true end

	-- PRISM FOX: its own lever is a marker, not a number. Owning it (equipped) switches on every OTHER passive
	-- in the collection at a fraction of strength. Resolved first so the weight is known before the main pass.
	local prismWeight = UNEQUIPPED_WEIGHT
	if equippedSpecies.PrismFox and owned.PrismFox then
		prismWeight = math.max(prismWeight, PetAbilities.valueAt("PrismFox", owned.PrismFox.best))
	end

	for species, info in pairs(owned) do
		local def = PetAbilities.DEFS[species]
		if def and def.lever ~= "_prism" then
			-- An equipped pet contributes fully; an unequipped one only through Prism Fox.
			local weight = equippedSpecies[species] and 1 or prismWeight
			if weight > 0 then
				local per = PetAbilities.valueAt(species, info.best)
				-- DUPLICATE STACKING. Copy 1 is worth 100%, copy 2 is 60%, then 38 / 27.5 / 20, tail 12.
				-- Applied to the same per-copy value rather than each copy's own level, because PetSystem
				-- stacks duplicates into one entry and does not track a level per physical copy.
				local total = 0
				for i = 1, math.min(info.copies, 12) do total = total + per * PetAbilities.falloff(i) end
				acc[def.lever] = PetAbilities.accumulate(acc[def.lever] or 0, def.lever, total * weight)
			end
		end
	end

	local out = {}
	for lever, sum in pairs(acc) do out[lever] = PetAbilities.finalise(lever, sum) end

	-- THE TRICK. Only the LEAD equipped pet's trick is bound to the button -- five passives at once is a
	-- loadout, five tricks at once is noise. Published as a plain string attribute so PetTricks can look up
	-- what to play without a remote and without knowing anything about pet storage keys.
	out._trick = ""
	local lead = equipped[1]
	if lead then
		local d = PetAbilities.DEFS[speciesOf(lead)]
		if d and d.trick then out._trick = d.trick end
	end
	return out
end

-- ===== PUBLISH =====
local cache = {}   -- [player] = resolved table, so a coin path never pays for a re-resolve

local function refresh(player)
	if not player or not player.Parent then return end
	local ok, vals = pcall(resolve, player)
	if not ok or type(vals) ~= "table" then return end
	cache[player] = vals
	for lever, v in pairs(vals) do
		if lever ~= "_trick" then
			pcall(function() player:SetAttribute(PetAbilities.attrName(lever), v) end)
		end
	end
	pcall(function() player:SetAttribute("PetTrick", tostring(vals._trick or "")) end)
end

-- THE SERVER-SIDE ACCESSOR. Never yields, never errors, always returns a usable number -- it is called from
-- inside coin grants and crate rolls, where a nil would be a live bug rather than a missing bonus.
_G.petAbility = function(player, lever)
	local neutral = PetAbilities.neutral(lever)
	if not player then return neutral end
	local c = cache[player]
	if not c then return neutral end
	local v = c[lever]
	if type(v) ~= "number" or v ~= v then return neutral end   -- v ~= v catches NaN
	return v
end
_G.petAbilityRefresh = refresh
_G.petAbilityAll = function(player) return cache[player] end

Players.PlayerAdded:Connect(function(p)
	-- Pets load asynchronously, so the first resolve would find an empty inventory. Settle first, then publish.
	task.delay(4, refresh, p)
end)
Players.PlayerRemoving:Connect(function(p) cache[p] = nil end)

-- The recompute timer. 3s is well under the time it takes a player to notice a new pet is doing nothing, and
-- the cost is a handful of table walks per player.
task.spawn(function()
	while true do
		task.wait(3)
		for _, p in ipairs(Players:GetPlayers()) do refresh(p) end
	end
end)

for _, p in ipairs(Players:GetPlayers()) do task.delay(4, refresh, p) end

print("[PetAbil] ready -- pets 7-14 have live abilities; levers published as PetAbil_* player attributes")
