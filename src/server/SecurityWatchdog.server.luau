--======================================================================
-- SecurityWatchdog.server.luau  --  FartToFloat
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
}

-- Reviewed and accepted. Same idea as the scanner's ALLOWLIST; keep them in step.
local ALLOWLIST = {
}

-- ============================ GENERATED MANIFEST ============================
-- 137 script instances, from FartToFloat/default.project.json + src/ on disk.
local MANIFEST = {
	["ReplicatedFirst.LoadingScreen"] = true,
	["ReplicatedStorage.PhoneHUD"] = true,
	["ReplicatedStorage.Shared.Constants"] = true,
	["ReplicatedStorage.Shared.CosmeticConfig"] = true,
	["ReplicatedStorage.Shared.CosmeticIcon"] = true,
	["ReplicatedStorage.Shared.CrateTokens"] = true,
	["ReplicatedStorage.Shared.GutSkins"] = true,
	["ReplicatedStorage.Shared.PetCollection"] = true,
	["ReplicatedStorage.Shared.PetSkins"] = true,
	["ReplicatedStorage.Shared.PetTraits"] = true,
	["ReplicatedStorage.Shared.RealmTransfer"] = true,
	["ReplicatedStorage.Shared.Remotes"] = true,
	["ReplicatedStorage.Shared.SkinCrates"] = true,
	["ServerScriptService.BeamCollision"] = true,
	["ServerScriptService.BeamEffects"] = true,
	["ServerScriptService.BeamGeneration"] = true,
	["ServerScriptService.BeamKnockback"] = true,
	["ServerScriptService.BeamPattern"] = true,
	["ServerScriptService.BellySystem"] = true,
	["ServerScriptService.BigEventScheduler"] = true,
	["ServerScriptService.BlackHoleTeleport"] = true,
	["ServerScriptService.BlimpService"] = true,
	["ServerScriptService.BootCheck"] = true,
	["ServerScriptService.Campfire"] = true,
	["ServerScriptService.ComebackNudge"] = true,
	["ServerScriptService.CommunityGarden"] = true,
	["ServerScriptService.CrateService"] = true,
	["ServerScriptService.DailyTasks"] = true,
	["ServerScriptService.DevCommands"] = true,
	["ServerScriptService.EasterEggManager"] = true,
	["ServerScriptService.FarmerSpawner"] = true,
	["ServerScriptService.GardenBird"] = true,
	["ServerScriptService.GardenFeeding"] = true,
	["ServerScriptService.GardenGnomes"] = true,
	["ServerScriptService.GardenerWave"] = true,
	["ServerScriptService.GutSkinService"] = true,
	["ServerScriptService.HeldItemSync"] = true,
	["ServerScriptService.IslandNPCs"] = true,
	["ServerScriptService.IslandStreaming"] = true,
	["ServerScriptService.LateJoinEventSync"] = true,
	["ServerScriptService.LeaderboardService"] = true,
	["ServerScriptService.MeatballShooter"] = true,
	["ServerScriptService.MeteorImpact"] = true,
	["ServerScriptService.MeteorManager"] = true,
	["ServerScriptService.MeteorReward"] = true,
	["ServerScriptService.MeteorSpawn"] = true,
	["ServerScriptService.MilkCap"] = true,
	["ServerScriptService.MusicManager"] = true,
	["ServerScriptService.PetSystem"] = true,
	["ServerScriptService.PlanetSelectService"] = true,
	["ServerScriptService.PlayerState"] = true,
	["ServerScriptService.PlayerStats"] = true,
	["ServerScriptService.PopcornTrees"] = true,
	["ServerScriptService.RainbowBeamManager"] = true,
	["ServerScriptService.RealmPortals"] = true,
	["ServerScriptService.RealmReturnReceiver"] = true,
	["ServerScriptService.RebirthSystem"] = true,
	["ServerScriptService.RewardsService"] = true,
	["ServerScriptService.RocketEffects"] = true,
	["ServerScriptService.RocketEventManager"] = true,
	["ServerScriptService.RocketLogic"] = true,
	["ServerScriptService.RocketNPCs"] = true,
	["ServerScriptService.SeasonPass"] = true,
	["ServerScriptService.SecretTrader"] = true,
	["ServerScriptService.SecretTreeDoor"] = true,
	["ServerScriptService.SecurityGuard"] = true,
	["ServerScriptService.SecurityWatchdog"] = true,
	["ServerScriptService.SkinCrateService"] = true,
	["ServerScriptService.SocialRewards"] = true,
	["ServerScriptService.SquirrelEasterEgg"] = true,
	["ServerScriptService.ToasterEasterEgg"] = true,
	["ServerScriptService.WormholeService"] = true,
	["StarterPlayer.StarterPlayerScripts.AmbientSmoke"] = true,
	["StarterPlayer.StarterPlayerScripts.AmbientWildlife"] = true,
	["StarterPlayer.StarterPlayerScripts.BellyPuff"] = true,
	["StarterPlayer.StarterPlayerScripts.BlackBarKiller"] = true,
	["StarterPlayer.StarterPlayerScripts.BootCheck"] = true,
	["StarterPlayer.StarterPlayerScripts.ButtonTextStyle"] = true,
	["StarterPlayer.StarterPlayerScripts.Campfire"] = true,
	["StarterPlayer.StarterPlayerScripts.CommunityGarden"] = true,
	["StarterPlayer.StarterPlayerScripts.CoreClient"] = true,
	["StarterPlayer.StarterPlayerScripts.CrateClient"] = true,
	["StarterPlayer.StarterPlayerScripts.DailyTasks"] = true,
	["StarterPlayer.StarterPlayerScripts.EventClient"] = true,
	["StarterPlayer.StarterPlayerScripts.EventSoundPreload"] = true,
	["StarterPlayer.StarterPlayerScripts.FarmerTutorial"] = true,
	["StarterPlayer.StarterPlayerScripts.FlightFeedback"] = true,
	["StarterPlayer.StarterPlayerScripts.FoodRealmHud"] = true,
	["StarterPlayer.StarterPlayerScripts.GardenChestClient"] = true,
	["StarterPlayer.StarterPlayerScripts.GardenDonationClient"] = true,
	["StarterPlayer.StarterPlayerScripts.GardenGuideTrail"] = true,
	["StarterPlayer.StarterPlayerScripts.GardenIntro"] = true,
	["StarterPlayer.StarterPlayerScripts.GardenerChat"] = true,
	["StarterPlayer.StarterPlayerScripts.GardenerLife"] = true,
	["StarterPlayer.StarterPlayerScripts.GutSkinClient"] = true,
	["StarterPlayer.StarterPlayerScripts.HeldItemSync"] = true,
	["StarterPlayer.StarterPlayerScripts.LandingImpact"] = true,
	["StarterPlayer.StarterPlayerScripts.MenuBackButton"] = true,
	["StarterPlayer.StarterPlayerScripts.MenuBackdropGuard"] = true,
	["StarterPlayer.StarterPlayerScripts.MeteorImpactSound"] = true,
	["StarterPlayer.StarterPlayerScripts.MeteorUI"] = true,
	["StarterPlayer.StarterPlayerScripts.MusicClient"] = true,
	["StarterPlayer.StarterPlayerScripts.MusicDucking"] = true,
	["StarterPlayer.StarterPlayerScripts.NotifyCenter"] = true,
	["StarterPlayer.StarterPlayerScripts.NotifyOptIn"] = true,
	["StarterPlayer.StarterPlayerScripts.NpcGuideArrow"] = true,
	["StarterPlayer.StarterPlayerScripts.NpcLife"] = true,
	["StarterPlayer.StarterPlayerScripts.NpcWaypointArrow"] = true,
	["StarterPlayer.StarterPlayerScripts.ObjectiveHUD"] = true,
	["StarterPlayer.StarterPlayerScripts.OfflineEarnings"] = true,
	["StarterPlayer.StarterPlayerScripts.PetFollow"] = true,
	["StarterPlayer.StarterPlayerScripts.PetSkinLook"] = true,
	["StarterPlayer.StarterPlayerScripts.RailGuard"] = true,
	["StarterPlayer.StarterPlayerScripts.RainbowBeamUI"] = true,
	["StarterPlayer.StarterPlayerScripts.RealmPortals"] = true,
	["StarterPlayer.StarterPlayerScripts.RebirthClient"] = true,
	["StarterPlayer.StarterPlayerScripts.RebirthTag"] = true,
	["StarterPlayer.StarterPlayerScripts.RemotePets"] = true,
	["StarterPlayer.StarterPlayerScripts.RewardsClient"] = true,
	["StarterPlayer.StarterPlayerScripts.RewardsHub"] = true,
	["StarterPlayer.StarterPlayerScripts.RocketBuildPreload"] = true,
	["StarterPlayer.StarterPlayerScripts.RocketSounds"] = true,
	["StarterPlayer.StarterPlayerScripts.RocketUI"] = true,
	["StarterPlayer.StarterPlayerScripts.SeasonPass"] = true,
	["StarterPlayer.StarterPlayerScripts.SeasonalPetsChest"] = true,
	["StarterPlayer.StarterPlayerScripts.SecretCave"] = true,
	["StarterPlayer.StarterPlayerScripts.SettingsMenu"] = true,
	["StarterPlayer.StarterPlayerScripts.ShopClient"] = true,
	["StarterPlayer.StarterPlayerScripts.SkinCrateClient"] = true,
	["StarterPlayer.StarterPlayerScripts.SkyByAltitude"] = true,
	["StarterPlayer.StarterPlayerScripts.SocialRewards"] = true,
	["StarterPlayer.StarterPlayerScripts.TitleTags"] = true,
	["StarterPlayer.StarterPlayerScripts.TokenHud"] = true,
	["StarterPlayer.StarterPlayerScripts.TopCenterStack"] = true,
	["StarterPlayer.StarterPlayerScripts.WarpEffect"] = true,
	["StarterPlayer.StarterPlayerScripts.WorldClient"] = true,
	["StarterPlayer.StarterPlayerScripts.WormholeClient"] = true,
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
local function auditScript(inst, when)
	local path = fullPath(inst)
	if underAny(path, IGNORED_ROOTS) or ALLOWLIST[path] then return end

	if nonAscii(inst.Name) then
		alert("HOMOGLYPH-NAME", inst, when .. " -- name is not ASCII, deliberate disguise")
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
	print(("[SECURITY] FartToFloat boot audit: %d scripts against a 137-entry manifest, %d alert(s)")
		:format(n, alerts))
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

	for _, svc in ipairs(WATCH) do
		svc.DescendantAdded:Connect(function(d)
			if d:IsA("LuaSourceContainer") then
				alert("SCRIPT-ADDED-AT-RUNTIME", d,
					"a script appeared after the server started -- nothing in this realm does that")
				if DESTROY_UNKNOWN then
					pcall(function() d.Disabled = true end)
					pcall(function() d:Destroy() end)
				end
			elseif (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and not baselineRemotes[d] then
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
