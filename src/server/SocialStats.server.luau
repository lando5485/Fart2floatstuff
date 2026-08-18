--======================================================================
-- SocialStats.server.luau  (Script, ServerScriptService)
--======================================================================
-- Publishes each player's COLLECTION PROGRESS and BEST HEIGHT as replicated player attributes, so any client
-- can read them for ANY player without a single remote call.
--
-- ===== WHY ATTRIBUTES AND NOT A REMOTE =====
-- This is the same trick RebirthTag and IslandNameTag already use in this game: a replicated attribute is
-- readable by every client the instant the server sets it, for every player, forever. That is exactly the
-- shape a social feature needs -- "how far along is THAT kid" is a question every client asks about every
-- other player continuously, and answering it with remotes would mean N-squared traffic for data that never
-- needed to be private.
--
-- Three separate features read what this publishes and none of them need a server script of their own:
--   * the collection meter in the Pet Hub          -> SpeciesOwned / SkinsOwned / CollectionPct
--   * the rival callout during flight              -> BestHeight
--   * the badge awarder                            -> CollectionPct, SpeciesOwned
--
-- ===== BEST HEIGHT IS SAMPLED ON THE SERVER, ON PURPOSE =====
-- LeaderboardService's own header explains why it refuses to run a height board: peak height is computed on
-- the CLIENT (_G.peakHeight in CoreClient) and sent up, so a global board built on it would be trivially
-- faked. That reasoning applies here too, so this does NOT trust the client -- it reads HumanoidRootPart.Y
-- off the character on the server. Nobody can inflate it without actually flying there.
--
-- It is a SESSION best, and the callout that reads it says so. Persisting it would mean writing to
-- PlayerStats' DataStore, and BootCheck reports PlayerStats running as TWO copies -- the one file in this
-- codebase most worth not touching.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if _G.__SocialStatsServer then
	warn("[SocialStats] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__SocialStatsServer = true

--======================================================================
-- TOTALS
--======================================================================
-- Derived from the shared modules wherever they expose a count, so retuning the roster does not silently
-- leave this reporting a percentage of the wrong denominator.
local totalSkins = 20
pcall(function()
	local PetCollection = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PetCollection"))
	local n = PetCollection.totalSkins and PetCollection.totalSkins()
	if type(n) == "number" and n > 0 then totalSkins = n end
end)

-- The collectible-species count. PetSystem owns the roster and does not export its size, so this is the one
-- number here that is written down rather than derived -- it must match the "N/10 species collected" line
-- PetFollow already prints. If you add a collectible pet, change this too.
local TOTAL_SPECIES = 10

local RARE_SUFFIX = "#R"   -- PetSystem's variantKey suffix: "BroccoliPet#R" is the rare slot of the same species

--======================================================================
-- COUNTING
--======================================================================
-- A species counts ONCE whether you own the normal, the rare, or both -- otherwise a lucky player shows 12/10
-- collected, which is the kind of number that makes the whole meter look broken.
local function speciesOwned(player)
	local owned = _G.playerOwnedPets and _G.playerOwnedPets[player]
	if not owned then return 0 end
	local seen, n = {}, 0
	for key in pairs(owned) do
		local species = tostring(key):gsub(RARE_SUFFIX .. "$", "")
		if not seen[species] then seen[species] = true; n = n + 1 end
	end
	return n
end

-- Distinct SKIN ids, not distinct inventory entries. _G.playerPetSkins is keyed "Pet|Skin|Trait" and a player
-- can hold the same skin on six pets with nine traits -- counting entries would report hundreds out of twenty.
local function skinsOwned(player)
	local held = _G.playerPetSkins and _G.playerPetSkins[player]
	if not held then return 0 end
	local seen, n = {}, 0
	for key, count in pairs(held) do
		if (tonumber(count) or 0) > 0 then
			local skin = tostring(key):match("^[^|]*|([^|]*)")
			if skin and skin ~= "" and not seen[skin] then seen[skin] = true; n = n + 1 end
		end
	end
	return n
end

local function publishCollection(player)
	if not player.Parent then return end
	local sp, sk = speciesOwned(player), skinsOwned(player)
	player:SetAttribute("SpeciesOwned", sp)
	player:SetAttribute("SpeciesTotal", TOTAL_SPECIES)
	player:SetAttribute("SkinsOwned", sk)
	player:SetAttribute("SkinsTotal", totalSkins)
	-- One headline number. Species and skins weighted equally: they are the two halves of "collecting" in this
	-- game and a kid should be able to make the bar move from either side.
	local pct = 0
	if TOTAL_SPECIES > 0 and totalSkins > 0 then
		pct = math.floor(((sp / TOTAL_SPECIES) * 0.5 + (sk / totalSkins) * 0.5) * 100 + 0.5)
	end
	player:SetAttribute("CollectionPct", math.clamp(pct, 0, 100))
end

--======================================================================
-- BEST HEIGHT
--======================================================================
local function sampleHeight(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local y = hrp.Position.Y
	local best = tonumber(player:GetAttribute("BestHeight")) or 0
	if y > best then player:SetAttribute("BestHeight", math.floor(y)) end
end

--======================================================================
-- LIFECYCLE
--======================================================================
local function onJoin(player)
	-- Seed immediately so nothing reads nil, then again once the save has had time to land -- pets and skins
	-- are restored asynchronously and a meter that shows 0% for the first ten seconds of every session reads
	-- as data loss to the player.
	player:SetAttribute("BestHeight", 0)
	publishCollection(player)
	task.delay(6, function() if player.Parent then publishCollection(player) end end)
end

for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end
Players.PlayerAdded:Connect(onJoin)

-- One loop for everyone rather than a coroutine per player. Height is sampled often because it is a live
-- number that a rival callout reacts to; collection is recomputed rarely because it only changes on a hatch,
-- a crate open or a trade -- all rare, none worth polling hard for.
task.spawn(function()
	local tick = 0
	while true do
		task.wait(0.5)
		tick = tick + 1
		local recount = (tick % 8 == 0) -- collection every ~4s
		for _, p in ipairs(Players:GetPlayers()) do
			sampleHeight(p)
			if recount then publishCollection(p) end
		end
	end
end)

-- Published so anything that just changed a player's collection can push the meter immediately instead of
-- waiting up to four seconds -- a crate reveal that ends with a stale percentage undercuts the reveal.
_G.socialStatsRefresh = function(player)
	if typeof(player) == "Instance" and player:IsA("Player") then publishCollection(player) end
end

print(string.format("[SocialStats] ready -- publishing SpeciesOwned/%d, SkinsOwned/%d, CollectionPct and BestHeight as player attributes",
	TOTAL_SPECIES, totalSkins))
