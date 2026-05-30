--======================================================================
-- MeteorReward.lua  (ModuleScript)
--======================================================================
-- Rewards for the "MeteorStorm" event. SERVER-AUTHORITATIVE and MODEST.
--
-- This is the ONLY reward path for the event. It awards by ADDING to the
-- player's Coins leaderstat (and TotalCoinsEarned if that stat exists).
-- It NEVER touches the fart meter, flight, food prices, gut stats, island
-- heights, the normal coin EARN rate, the falling junk, or the planes.
--
-- DESIGN: defaults are deliberately small so meteor coins do NOT dwarf
-- normal earning or let players skip the food/gut grind. EVERY amount and
-- chance is a CONFIG value, so any of them can be tuned or zeroed.
--
-- Reward model: when a meteor impacts, we roll METEOR_REWARD_CHANCE. If it
-- drops, we spawn a small collectible coin part at the impact. A player
-- TOUCHING it claims it (server-validated, one claimer per drop). This
-- keeps it server-authoritative and tied to actually being there. Rare
-- rolls give a bigger "boost"/"rare bean" style coin bundle; LEGENDARY
-- gives a big coin bundle + a brief, purely-cosmetic server-wide buff
-- notification (NO permanent balance change).
--======================================================================

local MeteorReward = {}

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

-- Wired by init().
local CONFIG = nil
local MeteorSync = nil

-- Folder for collectible parts so cleanup is one Destroy().
local rewardFolder = nil

--------------------------------------------------------------------
-- init(config, syncEvent): wire shared dependencies.
--------------------------------------------------------------------
function MeteorReward.init(config, syncEvent)
	CONFIG = config
	MeteorSync = syncEvent
end

--------------------------------------------------------------------
-- ensureFolder(): fresh folder for collectibles.
--------------------------------------------------------------------
local function ensureFolder()
	if not rewardFolder or not rewardFolder.Parent then
		rewardFolder = Instance.new("Folder")
		rewardFolder.Name = "MeteorStormRewards"
		rewardFolder.Parent = workspace
	end
	return rewardFolder
end

--------------------------------------------------------------------
-- awardCoins(player, amount): the ONLY way this module changes state.
-- Adds to Coins (and TotalCoinsEarned if present). No other stat touched.
--------------------------------------------------------------------
local function awardCoins(player, amount)
	if amount <= 0 then return end
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	if coins then
		coins.Value = coins.Value + amount
	end
	-- Mirror into TotalCoinsEarned ONLY if that stat exists (it does in this
	-- game). We never create it and never touch anything else.
	local tce = ls:FindFirstChild("TotalCoinsEarned")
	if tce then
		tce.Value = tce.Value + amount
	end
	-- Let the client show a small "+coins" popup (presentation only).
	MeteorSync:FireClient(player, "reward", { coins = amount })
end

--------------------------------------------------------------------
-- rollRewardAmount(legendary): decide the coin bundle for a drop.
-- Returns amount, tier ("normal" | "rare" | "legendary").
--------------------------------------------------------------------
local function rollRewardAmount(legendary)
	if legendary then
		return CONFIG.LEGENDARY_REWARD, "legendary"
	end
	local r = math.random()
	if r < CONFIG.BOOST_DROP_CHANCE then
		return CONFIG.BOOST_REWARD, "rare"        -- "boost" style bonus
	elseif r < CONFIG.BOOST_DROP_CHANCE + CONFIG.RARE_BEAN_CHANCE then
		return CONFIG.RARE_BEAN_REWARD, "rare"    -- "rare bean" style bonus
	end
	return CONFIG.METEOR_COIN_REWARD, "normal"
end

--======================================================================
-- maybeDrop(pos, radius, legendary): called by MeteorImpact on landing.
-- Rolls the drop chance; on success spawns ONE collectible coin part the
-- nearest players can touch to claim. Legendary always drops.
--======================================================================
function MeteorReward.maybeDrop(pos, radius, legendary)
	-- Legendary always drops; otherwise roll the configured chance.
	if not legendary and math.random() > CONFIG.METEOR_REWARD_CHANCE then
		return
	end

	local amount, tier = rollRewardAmount(legendary)
	if amount <= 0 then return end

	local folder = ensureFolder()

	-- The collectible coin part. CanCollide=false so it never blocks a
	-- player; it floats just above the impact so it is visible + reachable.
	local coin = Instance.new("Part")
	coin.Name = "MeteorReward_" .. tier
	coin.Shape = Enum.PartType.Cylinder
	coin.Material = Enum.Material.Neon
	coin.Color = (tier == "legendary") and Color3.fromRGB(255, 215, 60)
		or (tier == "rare") and Color3.fromRGB(120, 220, 255)
		or Color3.fromRGB(255, 220, 90)
	coin.Size = Vector3.new(0.4, 4, 4)
	coin.Anchored = true
	coin.CanCollide = false
	coin.CanTouch = true   -- we use Touched to claim
	coin.CanQuery = false
	-- Flat coin facing up, hovering above the impact center.
	coin.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	coin.Parent = folder

	-- A glow + slow spin so it reads as collectible.
	local light = Instance.new("PointLight")
	light.Color = coin.Color
	light.Brightness = 3
	light.Range = 18
	light.Parent = coin

	-- Server-validated single-claim. The first player to touch it wins it.
	local claimed = false
	local touchConn
	touchConn = coin.Touched:Connect(function(hit)
		if claimed then return end
		local char = hit:FindFirstAncestorOfClass("Model")
		if not char then return end
		local plr = Players:GetPlayerFromCharacter(char)
		if not plr then return end
		-- Validate the toucher is genuinely near (anti-spoof sanity check).
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp or (hrp.Position - coin.Position).Magnitude > 12 then return end

		claimed = true
		if touchConn then touchConn:Disconnect() end
		awardCoins(plr, amount)

		-- Announce legendary loudly to everyone (cosmetic); rare/normal is a
		-- quiet per-claimer popup handled by awardCoins.
		if tier == "legendary" then
			MeteorSync:FireAllClients("legendaryClaimed", {
				player = plr.Name,
				coins = amount,
			})
		end
		-- Pop the coin out.
		coin:Destroy()
	end)

	-- Auto-expire uncollected drops so they don't litter the islands.
	Debris:AddItem(coin, CONFIG.REWARD_LIFETIME)
end

--======================================================================
-- cleanup(): destroy all uncollected collectibles. No leaks.
--======================================================================
function MeteorReward.cleanup()
	if rewardFolder and rewardFolder.Parent then
		rewardFolder:Destroy()
	end
	rewardFolder = nil
end

return MeteorReward
