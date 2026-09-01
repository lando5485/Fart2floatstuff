--======================================================================
-- SecurityWatchdog.server.luau  --  CandyRealm
--======================================================================
-- GENERATED alongside tools/BackdoorScan.studio.luau. Regenerate both together:
-- they share the MANIFEST, and a stale one here reports your own new scripts as
-- intruders every boot until you notice.
--
-- WHAT THIS CAN AND CANNOT DO -- READ THIS BEFORE TRUSTING IT
--
-- It CANNOT read code. `.Source` requires plugin security; a script running
-- inside a live game is forbidden from reading another script's source, and
-- there is no workaround. So every "does this code call require(assetId)"
-- question belongs to the Studio scanner, not here.
--
-- It also CANNOT reliably stop a backdoor that is already in the place. Scripts
-- start in no guaranteed order, so a hostile Script in Workspace may well have
-- already run by the time this executes. Setting Disabled = true afterwards does
-- not kill a thread that is running -- Disabled stops a script from STARTING.
--
-- So what is it for? Two things it genuinely does well:
--
--   1. A BOOT AUDIT. It lists every script in the live place and compares that
--      to the manifest. Anything unexpected gets printed loudly at every server
--      start, so an injected script cannot sit there quietly for weeks. This is
--      the same check as the Studio scanner's strongest rule, running where you
--      will actually see it -- in server logs, on the live game, after publish.
--
--   2. INJECTION AT RUNTIME. This is the part the Studio scan structurally
--      cannot cover. A require(assetId) backdoor's whole point is that its
--      payload arrives from the internet AFTER you last looked, and the usual
--      next move is to create new scripts, or a new RemoteEvent to take orders
--      through. Those appear after boot, and this sees them appear.
--
-- TREAT ITS OUTPUT AS AN ALARM, NOT A FIX. When it fires, go and clean the place
-- in Studio and republish. DESTROY_UNKNOWN below is a containment measure, not a
-- defence -- see the comment on it.
--======================================================================

-- Log only (false), or also remove what it finds (true).
--
-- Default is FALSE, deliberately. Destroying scripts on a live server based on a
-- name-and-location guess can break your own game if the manifest is stale or a
-- legitimate model ships a script -- and it destroys the evidence you would use
-- to work out what happened. Turn it on once the log has been quiet for a while
-- and you trust the manifest.
local DESTROY_UNKNOWN = false

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local SSS     = game:GetService("ServerScriptService")
local SP      = game:GetService("StarterPlayer")
local SG      = game:GetService("StarterGui")
local RF      = game:GetService("ReplicatedFirst")

local IGNORED_ROOTS = {
	"CoreGui", "CorePackages", "Chat", "TextChatService",
	"StarterPlayer.StarterCharacterScripts",
	-- ROBLOX'S OWN PLAYER SCRIPTS. The engine injects the whole PlayerModule tree (camera + control
	-- modules, ~45 ModuleScripts) into StarterPlayerScripts. No Rojo project produces them, so every one
	-- was a NOT-IN-MANIFEST alert on every boot -- a quarter of the audit, all of it Roblox's own code.
	"StarterPlayer.StarterPlayerScripts.PlayerModule",
	"StarterPlayer.StarterPlayerScripts.RbxCharacterSounds",
}

-- Reviewed and accepted. Same idea as the scanner's ALLOWLIST; keep them in step.
-- Remotes this realm creates ON DEMAND rather than at boot, so REMOTE-ADDED-LATE is expected for them
-- and the alert is noise. StateRemotes is Shared/Remotes.luau's own folder (its FOLDER_NAME), built
-- lazily the first time PlayerState streams a snapshot -- which is always after the boot audit ran.
-- Matched by ANCESTRY, so every remote inside the folder is covered without listing each one.
local LATE_REMOTE_OK = {
	["StateRemotes"] = true,
}
local function lateRemoteExpected(d)
	local n = d
	while n and n ~= game do
		if LATE_REMOTE_OK[n.Name] then return true end
		n = n.Parent
	end
	return false
end

local ALLOWLIST = {
	["StarterPlayer.StarterPlayerScripts.PlayerScriptsLoader"] = true, -- Roblox stock, injected by the engine
}

-- ============================ KNOWN FREE-MODEL JUNK ============================
-- Scripts that ship INSIDE toolbox models sitting in Workspace/Lighting: procedural-generation kits, texture
-- and light configurators, weld scripts. They are not produced by this project and never will be, so they are
-- real NOT-IN-MANIFEST hits -- but they are the SAME hits every boot, ~90 of them, and drowning a genuine
-- injection in 90 lines of known noise is precisely how a backdoor gets scrolled past.
--
-- So they are COUNTED AND SUMMARISED rather than listed. Matched on the script's own NAME, not its path, so
-- moving or duplicating the model does not resurrect the spam. Anything not on this list is still printed in
-- full, which is the whole point: the audit is quiet until something genuinely new turns up.
--
-- ⚠ THIS IS NOT AN ENDORSEMENT. These are unread free-model scripts and several of them are the ones throwing
-- "cannot require using asset ID (lacking capability LoadUnownedAsset)" at every boot -- they are trying to
-- pull code off the marketplace and failing only because the place lacks that capability. Deleting them in
-- Studio is strictly better than muting them; this list only stops them hiding a NEW intruder in the meantime.
local FREE_MODEL_NAMES = {
	ProceduralGeneration = true, SmartObject = true, GeometryPrimitives = true,
	MathUtils = true, ConstructiveSolidGeometry = true,
	Package = true, TextureConfiguration = true, CoreViewSystem = true, PoseTexture = true,
	LightConfig = true, EasyConfiguration = true, Type = true,
	qPerfectionWeld = true, Animate = true,
}

-- ============================ GENERATED MANIFEST ============================
-- 194 script instances, from CandyRealm/default.project.json + src/ on disk.
local MANIFEST = {
	["ReplicatedStorage.Shared.CandyData"] = true,
	["ReplicatedStorage.Shared.Constants"] = true,
	["ReplicatedStorage.Shared.CosmeticConfig"] = true,
	["ReplicatedStorage.Shared.CosmeticIcon"] = true,
	["ReplicatedStorage.Shared.CrateTokens"] = true,
	["ReplicatedStorage.Shared.GutSkins"] = true,
	["ReplicatedStorage.Shared.PetCollection"] = true,
	["ReplicatedStorage.Shared.PetSkins"] = true,
	["ReplicatedStorage.Shared.PetTraits"] = true,
	["ReplicatedStorage.Shared.PhoneHUD"] = true,
	["ReplicatedStorage.Shared.Remotes"] = true,
	["ReplicatedStorage.Shared.SkinCrates"] = true,
	["ServerScriptService.AnchorIslands"] = true,
	["ServerScriptService.BuyFood"] = true,
	-- the effect/state relays. Each one is a dumb FireAllClients rebroadcaster that lets a
	-- client-side quest be visible to the rest of the server; MonsterEatSync is listed further
	-- down with the originals.
	["ServerScriptService.BakeryFxSync"] = true,     -- island15 oven lights, egg drops, mixing
	["ServerScriptService.HayFactoryFxSync"] = true, -- island19 bale presses
	["ServerScriptService.CarrySync"] = true,        -- what every player is holding
	["ServerScriptService.MonsterSync"] = true,      -- island18 + island3 monster positions
	["ServerScriptService.CrateService"] = true,
	["ServerScriptService.DailyTasks"] = true,
	["ServerScriptService.InvisibleBarrierSweep"] = true,
	["ServerScriptService.MonsterEatSync"] = true,
	["ServerScriptService.PlayerState"] = true,
	["ServerScriptService.RealmServer"] = true,
	["ServerScriptService.RealmTravel"] = true,   -- wormhole -> Food/Space/Dino realm rows
	["ServerScriptService.RebirthSystem"] = true,
	["ServerScriptService.ReturnIsland"] = true,
	["ServerScriptService.RewardsService"] = true,
	["ServerScriptService.ServerEvents"] = true,   -- mini-event driver (new: this realm never had one)
	["ServerScriptService.PassOwnership"] = true,  -- gamepass ownership -> attributes
	["StarterPlayer.StarterPlayerScripts.BubbleWords"] = true,   -- 8-word NPC bubble cap
	["ReplicatedFirst.IntroCover"] = true,   -- black-from-frame-one cover the intro adopts
	["ServerScriptService.BigEvents"] = true,   -- meteor / rocket / rainbow / weather set pieces
	["ServerScriptService.SourRain"] = true,
	["ServerScriptService.VipService"] = true,     -- VIP daily stipend
	["ServerScriptService.SeasonPass"] = true,
	["ServerScriptService.SecurityWatchdog"] = true,
	["ServerScriptService.SkinCrateService"] = true,
	["ServerScriptService.SpawnOnIsland1"] = true,
	["ServerScriptService.StomachUpgrade"] = true,
	["StarterPlayer.StarterPlayerScripts.AmbientSmoke"] = true,
	["StarterPlayer.StarterPlayerScripts.AmbientWildlife"] = true,
	["StarterPlayer.StarterPlayerScripts.AncientTreeQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.BakeryQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.BellyPuff"] = true,
	["StarterPlayer.StarterPlayerScripts.BlackBarKiller"] = true,
	["StarterPlayer.StarterPlayerScripts.BlackHole"] = true,
	["StarterPlayer.StarterPlayerScripts.BottomMeterPanel"] = true,
	["StarterPlayer.StarterPlayerScripts.CampSmoresQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.Campfire"] = true,
	["StarterPlayer.StarterPlayerScripts.CampfireFreezeQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.CandyDeliveryQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.CandyGumballQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.CandyMineExplosionQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.ChocolateMonster_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.ColdIsland"] = true,
	["StarterPlayer.StarterPlayerScripts.CommunityGarden"] = true,
	["StarterPlayer.StarterPlayerScripts.CookieRepairQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.CrateClient"] = true,
	["StarterPlayer.StarterPlayerScripts.CrystalMineQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.CurrencyCapsule"] = true,
	["StarterPlayer.StarterPlayerScripts.DailyTasks"] = true,
	["StarterPlayer.StarterPlayerScripts.DoneCommand"] = true,
	["StarterPlayer.StarterPlayerScripts.DinoPortal"] = true,
	["StarterPlayer.StarterPlayerScripts.EconomyBootstrap"] = true,
	["StarterPlayer.StarterPlayerScripts.EggSystem_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.EventClient"] = true,
	["StarterPlayer.StarterPlayerScripts.EventSoundPreload"] = true,
	["StarterPlayer.StarterPlayerScripts.FarmerTutorial"] = true,
	["StarterPlayer.StarterPlayerScripts.FartSounds_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.FishingQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.FlightFeedback"] = true,
	["StarterPlayer.StarterPlayerScripts.GardenChestClient"] = true,
	["StarterPlayer.StarterPlayerScripts.GardenDonationClient"] = true,
	["StarterPlayer.StarterPlayerScripts.GardenGuideTrail"] = true,
	["StarterPlayer.StarterPlayerScripts.GardenerChat"] = true,
	["StarterPlayer.StarterPlayerScripts.GardenerLife"] = true,
	["StarterPlayer.StarterPlayerScripts.GutSkinClient"] = true,
	["StarterPlayer.StarterPlayerScripts.GutGrowCinematic"] = true,
	["StarterPlayer.StarterPlayerScripts.IslandCard"] = true,
	["StarterPlayer.StarterPlayerScripts.IslandTeleport"] = true,
	["StarterPlayer.StarterPlayerScripts.JellyTowerQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.JustButtons_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.LandingImpact"] = true,
	["StarterPlayer.StarterPlayerScripts.MeteorImpactSound"] = true,
	["StarterPlayer.StarterPlayerScripts.MeteorUI"] = true,
	["StarterPlayer.StarterPlayerScripts.MorePopup_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.MusicClient"] = true,
	["StarterPlayer.StarterPlayerScripts.MusicDucking"] = true,
	["StarterPlayer.StarterPlayerScripts.CarryView"] = true,         -- draws other players' held props
	["StarterPlayer.StarterPlayerScripts.FirstPersonMenuMouse"] = true,   -- first-person soft-lock guard for every panel
	["StarterPlayer.StarterPlayerScripts.HayBaleFactory"] = true,    -- island19 bale line
	["StarterPlayer.StarterPlayerScripts.HousePanel"] = true,        -- one size/spot for every task HUD
	["StarterPlayer.StarterPlayerScripts.NotifyCenter"] = true,      -- the banner MODULE
	["StarterPlayer.StarterPlayerScripts.NotifyCenterBoot"] = true,  -- starts it + publishes _G.NotifyCenter
	["StarterPlayer.StarterPlayerScripts.CandyTheme"] = true,  -- palette + panel helpers for the banner module
	["StarterPlayer.StarterPlayerScripts.QuestRetainer"] = true,
	["StarterPlayer.StarterPlayerScripts.QuestDevGate"] = true,   -- gates every quest /skip command
	["StarterPlayer.StarterPlayerScripts.RealmOutro"] = true,     -- ported realm-crossing cinematic
	["StarterPlayer.StarterPlayerScripts.RevealCommand"] = true,   -- /reveal cinematic payoff shot
	["StarterPlayer.StarterPlayerScripts.Sinkhole"] = true,   -- sinkhole set piece: hole, drop, treasure cave
	["StarterPlayer.StarterPlayerScripts.SourRain"] = true,
	["StarterPlayer.StarterPlayerScripts.VipClient"] = true,
	["StarterPlayer.StarterPlayerScripts.NotifyOptIn"] = true,
	["StarterPlayer.StarterPlayerScripts.NpcGuideArrow"] = true,
	["StarterPlayer.StarterPlayerScripts.NpcLife"] = true,
	["StarterPlayer.StarterPlayerScripts.ObjectiveHUD"] = true,
	["StarterPlayer.StarterPlayerScripts.OfflineEarnings"] = true,
	["StarterPlayer.StarterPlayerScripts.ParkScan"] = true,
	["StarterPlayer.StarterPlayerScripts.BrokenTractorQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.PancakeMonsterQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.PetFollow"] = true,
	["StarterPlayer.StarterPlayerScripts.PetHub_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.PetSkinLook"] = true,
	["StarterPlayer.StarterPlayerScripts.PropelSystem_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.QuestJournal"] = true,
	["StarterPlayer.StarterPlayerScripts.RadioactiveCleanupQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.RainbowBeamUI"] = true,
	["StarterPlayer.StarterPlayerScripts.RealmClient"] = true,
	["StarterPlayer.StarterPlayerScripts.RealmPortals"] = true,
	["StarterPlayer.StarterPlayerScripts.RebirthClient"] = true,
	["StarterPlayer.StarterPlayerScripts.RebirthTag"] = true,
	["StarterPlayer.StarterPlayerScripts.RemotePets"] = true,
	["StarterPlayer.StarterPlayerScripts.ResponsiveUI"] = true,
	["StarterPlayer.StarterPlayerScripts.ReturnIsland"] = true,
	["StarterPlayer.StarterPlayerScripts.RewardsClient"] = true,
	["StarterPlayer.StarterPlayerScripts.RocketBuildPreload"] = true,
	["StarterPlayer.StarterPlayerScripts.RocketSounds"] = true,
	["StarterPlayer.StarterPlayerScripts.RocketUI"] = true,
	["StarterPlayer.StarterPlayerScripts.SeasonPass"] = true,
	["StarterPlayer.StarterPlayerScripts.SettingsMenu"] = true,
	["StarterPlayer.StarterPlayerScripts.ShopKit_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.Shop_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.SkinCrateClient"] = true,
	["StarterPlayer.StarterPlayerScripts.SkyByAltitude"] = true,
	["StarterPlayer.StarterPlayerScripts.SocialRewards"] = true,
	["StarterPlayer.StarterPlayerScripts.StatsPanelKit_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.StomachShop_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.SummitBellQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.TaffyStormQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.TitleTags"] = true,
	["StarterPlayer.StarterPlayerScripts.TopCenterStack"] = true,
	["StarterPlayer.StarterPlayerScripts.TunnelBlastQuest_AllInOne"] = true,
	["StarterPlayer.StarterPlayerScripts.WarpEffect"] = true,
	["StarterPlayer.StarterPlayerScripts.WorldClient"] = true,
	["StarterPlayer.StarterPlayerScripts.WormholeClient"] = true,

	-- ---- IN THE PROJECT BUT NEVER ADDED HERE ---------------------------------------------------------------
	-- 41 scripts that default.project.json really does sync, flagged NOT-IN-MANIFEST on every single boot purely
	-- because this table was never updated alongside the project file. That is most of a 194-alert boot audit
	-- reporting the realm's own code as intruders -- which is exactly how a real backdoor gets scrolled past,
	-- the one job this file has. Verified by diffing default.project.json against this table; everything still
	-- flagged after this is genuine free-model junk in Workspace (LightConfig / ProceduralGeneration / Package /
	-- CoreViewSystem / PoseTexture chains) or Roblox's own PlayerModule, none of which this project produces.
	-- IslandConfig (per-island quest data) is a shared module and GutProgression the server
	-- script that publishes the quest-ledger UnlockedSlot attribute. (FlightPayout was the
	-- space port's income model and is gone with it.)
	["ReplicatedStorage.Shared.FlightTuning"] = true,
	["ReplicatedStorage.Shared.Gamepasses"] = true,
	["ReplicatedStorage.Shared.IslandConfig"] = true,
	["ReplicatedStorage.Shared.IslandOrder"] = true,
	["ReplicatedStorage.Shared.NpcWave"] = true,
	["ReplicatedStorage.Shared.PetRarity"] = true,
	["ReplicatedStorage.Shared.Sfx"] = true,
	["ReplicatedStorage.Shared.StomachTiers"] = true,
	["ServerScriptService.BadgeAwards"] = true,
	["ServerScriptService.CrossRealmPets"] = true,
	["ServerScriptService.DinoPetTemplates"] = true,
	["ServerScriptService.DinoRealmTeleport"] = true,
	["ServerScriptService.FlightEconomy"] = true,
	["ServerScriptService.FoodPetTemplates"] = true,
	["ServerScriptService.Gifting"] = true,
	["ServerScriptService.GutProgression"] = true,
	["ServerScriptService.HideSpawnPads"] = true,
	["ServerScriptService.Intro"] = true,
	["ServerScriptService.Island15Npc"] = true,
	["ServerScriptService.IslandLayout"] = true,
	["ServerScriptService.IslandStreaming"] = true,
	["ServerScriptService.IslandTaskTokens"] = true,
	["ServerScriptService.PetRarityGrants"] = true,
	["ServerScriptService.PetTrade"] = true,
	["ServerScriptService.Receipts"] = true,
	["ServerScriptService.ShowBridges"] = true,
	["ServerScriptService.SkinPersistence"] = true,
	["ServerScriptService.SocialStats"] = true,
	["ServerScriptService.TradeRequests"] = true,
	["StarterPlayer.StarterPlayerScripts.ArrivalCinematic"] = true,
	["StarterPlayer.StarterPlayerScripts.BackButtonKit"] = true,
	["StarterPlayer.StarterPlayerScripts.CrossRealmPets"] = true,
	["StarterPlayer.StarterPlayerScripts.Gifting"] = true,
	["StarterPlayer.StarterPlayerScripts.GroupBannerClient"] = true,
	["StarterPlayer.StarterPlayerScripts.HideMarkers"] = true,
	["StarterPlayer.StarterPlayerScripts.Intro"] = true,
	["StarterPlayer.StarterPlayerScripts.IslandTaskReward"] = true,
	["StarterPlayer.StarterPlayerScripts.IslandTaskWatcher"] = true,
	["StarterPlayer.StarterPlayerScripts.NpcChatRange"] = true,
	["StarterPlayer.StarterPlayerScripts.ObjectiveBannerBridge"] = true,
	["StarterPlayer.StarterPlayerScripts.PetModelBridge"] = true,
	["StarterPlayer.StarterPlayerScripts.PetTradeClient"] = true,
	["StarterPlayer.StarterPlayerScripts.RivalCallout"] = true,
	["StarterPlayer.StarterPlayerScripts.SfxWiring"] = true,
	["StarterPlayer.StarterPlayerScripts.TradeRequests"] = true,
}
-- ============================================================================

local function fullPath(inst)
	local parts, cur = {}, inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(parts, ".")
end

local function underAny(path, list)
	for _, prefix in ipairs(list) do
		if path == prefix or path:sub(1, #prefix + 1) == prefix .. "." then return true end
	end
	return false
end

-- See the long note in the Studio scanner: non-ASCII in a script NAME is a
-- homoglyph disguise, and nothing legitimate here uses it.
local function nonAscii(s)
	for i = 1, #s do
		if s:byte(i) > 127 then return true end
	end
	return false
end

local alerts = 0
local function alert(kind, inst, note)
	alerts = alerts + 1
	local path = (typeof(inst) == "Instance") and fullPath(inst) or tostring(inst)
	warn(("[SECURITY] %s | %s | %s | %s"):format(kind, path,
		(typeof(inst) == "Instance") and inst.ClassName or "?", note or ""))
end

--======================================================================
-- 1. BOOT AUDIT
--======================================================================
local freeModelHits = 0
local function auditScript(inst, when)
	local path = fullPath(inst)
	if underAny(path, IGNORED_ROOTS) or ALLOWLIST[path] then return end

	if nonAscii(inst.Name) then
		alert("HOMOGLYPH-NAME", inst, when .. " -- name is not ASCII, deliberate disguise")
	elseif FREE_MODEL_NAMES[inst.Name] and not MANIFEST[path] then
		-- Known toolbox chain: counted, not printed. A homoglyph name is still checked ABOVE this, so a
		-- lookalike "Раckage" cannot ride in on the summary.
		freeModelHits += 1
		return
	elseif not MANIFEST[path] then
		alert("NOT-IN-MANIFEST", inst, when .. " -- not produced by this realm's Rojo project")
	else
		return -- known good
	end

	if DESTROY_UNKNOWN then
		pcall(function() inst.Disabled = true end) -- stops it STARTING; does not kill a running thread
		pcall(function() inst:Destroy() end)
		warn("[SECURITY]   ^ destroyed (DESTROY_UNKNOWN is on)")
	end
end

do
	local n = 0
	for _, inst in ipairs(game:GetDescendants()) do
		if inst:IsA("LuaSourceContainer") then
			n = n + 1
			auditScript(inst, "at boot")
		end
	end
	-- The manifest size is COUNTED, not hardcoded. It used to say "against a 116-entry manifest" in a line
	-- printed next to a table that had grown well past that -- a stale number in the one message you would
	-- use to notice the table was stale.
	local manifestSize = 0
	for _ in pairs(MANIFEST) do manifestSize += 1 end
	print(("[SECURITY] CandyRealm boot audit: %d scripts against a %d-entry manifest, %d alert(s)%s")
		:format(n, manifestSize, alerts,
			freeModelHits > 0 and (", plus %d known free-model script(s) muted"):format(freeModelHits) or ""))
	if freeModelHits > 0 then
		print(("[SECURITY] %d toolbox script(s) (ProceduralGeneration / Package / LightConfig / CoreViewSystem"
			.. " chains) were counted, not listed. Delete those models' scripts in Studio -- several of them are"
			.. " what throws 'lacking capability LoadUnownedAsset' every boot."):format(freeModelHits))
	end
	if alerts > 0 then
		warn("[SECURITY] Clean these in Studio with tools/BackdoorScan.studio.luau, then REPUBLISH.")
	end
end

--======================================================================
-- 2. RUNTIME INJECTION
--
-- The part the Studio scan cannot cover: a require(assetId) payload arrives from
-- the internet after you last looked, then creates scripts or opens a remote to
-- take orders through. Both show up as descendants appearing after boot.
--
-- Watched narrowly, on the containers that matter, rather than on game itself --
-- a global DescendantAdded fires for every part, effect and character limb the
-- game creates, which is thousands per minute and would bury the signal.
--======================================================================
local WATCH = {RS, SSS, SP, SG, RF, workspace}

-- Remotes legitimately created after boot by your own code are common, so the
-- first pass is a snapshot: anything present shortly after start is baseline,
-- and only LATER arrivals are reported.
local baselineRemotes = {}
task.delay(10, function()
	for _, svc in ipairs({RS, RF}) do
		for _, d in ipairs(svc:GetDescendants()) do
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent") then
				baselineRemotes[d] = true
			end
		end
	end

	-- (!) ROBLOX'S OWN CHARACTER SCRIPTS ARE NOT INJECTIONS. Every spawn parents Animate (and on
	-- some rigs Health, Sound, and the CharacterSoundEvent bindables) into the character model
	-- under Workspace, so a watcher on Workspace flags two "SCRIPT-ADDED-AT-RUNTIME" alerts per
	-- respawn, forever. That is not a warning anybody can act on -- it is the engine doing its job
	-- -- and a security log that cries wolf on every death is a security log people stop reading.
	--
	-- Matched by NAME AND by living inside a player's character: a script called Animate anywhere
	-- else is still reported, which is where a real one would hide.
	local ENGINE_CHAR_SCRIPTS = { Animate = true, Health = true, Sound = true }
	local function isEngineCharacterScript(d)
		if not ENGINE_CHAR_SCRIPTS[d.Name] then return false end
		for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
			if plr.Character and d:IsDescendantOf(plr.Character) then return true end
		end
		return false
	end

	for _, svc in ipairs(WATCH) do
		svc.DescendantAdded:Connect(function(d)
			if d:IsA("LuaSourceContainer") then
				if isEngineCharacterScript(d) then return end
				alert("SCRIPT-ADDED-AT-RUNTIME", d,
					"a script appeared after the server started -- nothing in this realm does that")
				if DESTROY_UNKNOWN then
					pcall(function() d.Disabled = true end)
					pcall(function() d:Destroy() end)
				end
			elseif (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and not baselineRemotes[d]
				and not lateRemoteExpected(d) then
				alert("REMOTE-ADDED-LATE", d,
					"a new remote appeared long after boot -- a common backdoor control channel")
			end
		end)
	end
	print("[SECURITY] runtime injection watch armed")
end)

--======================================================================
-- 3. WHAT IS NOT COVERED HERE, SAID OUT LOUD
--
-- * Exploiters on the CLIENT. Nothing above touches that. Client-side exploits
--   are stopped by the server not trusting client input, remote by remote --
--   a different job from backdoors, and not one a watchdog can do generically.
-- * A hostile edit INSIDE a manifested file. The path is on the list, so this
--   passes it. Your defence there is git: `git status` and `git diff` before you
--   publish will show it, and this file cannot.
-- * Plugins. A malicious Studio plugin edits the place at edit time, before any
--   of this runs. Install plugins as carefully as you install models.
--======================================================================
