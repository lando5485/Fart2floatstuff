--======================================================================
-- BootCheck.server.luau   (ServerScriptService, Script)
--======================================================================
-- The server half of the boot check. Same job, same four failure modes -- see the long header in
-- BootCheck.client.luau for the reasoning; this file only notes what differs on the server.
--
-- WHY BOTH HALVES MATTER: a client script that builds a GUI fails visibly (the GUI is missing). A SERVER
-- script that fails is worse, because the symptom shows up somewhere else entirely -- PetSystem dying means
-- no pets for anyone, and it looks like the pet CLIENT is broken. Checking the server first tells you which
-- side to actually look at.
--
-- Diagnostic only. It never fixes, restarts or rebuilds anything.
--======================================================================

-- ===== HOOK ERRORS FIRST. Nothing above this line. =====
local errors = {}
do
	local ok = pcall(function()
		game:GetService("ScriptContext").Error:Connect(function(message, trace, sourceScript)
			local name = sourceScript and sourceScript.Name or (trace or "?"):match("([^%.\n]+):%d+") or "unknown"
			local e = errors[name]
			if e then e.count = e.count + 1
			else errors[name] = { count = 1, first = tostring(message):sub(1, 160) } end
		end)
	end)
	if not ok then warn("[BootCheck] ScriptContext.Error unavailable -- load errors will not be listed") end
end

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Workspace           = game:GetService("Workspace")

local REPORT_AFTER = 20

-- Generated from default.project.json. Regenerate when you add or remove a server script.
local EXPECTED = {
	"BeamCollision", "BeamEffects", "BeamGeneration", "BeamKnockback", "BeamPattern", "BellySystem",
	"BigEventScheduler", "BlackHoleTeleport", "BlimpService", "Campfire", "ComebackNudge",
	"CommunityGarden", "CrateService", "DailyTasks", "DevCommands", "EasterEggManager", "FarmerNPC",
	"GardenBird", "GardenFeeding", "GardenGnomes", "GardenerWave", "GutSkinService", "HeldItemSync",
	"IslandNPCs", "IslandStreaming", "LateJoinEventSync", "LeaderboardService", "MeatballShooter",
	"MeteorImpact", "MeteorManager", "MeteorReward", "MeteorSpawn", "MilkCap", "MusicManager",
	"PetSystem", "PlanetSelectService", "PlayerState", "PlayerStats", "PopcornTrees",
	"RainbowBeamManager", "RealmPortals", "RealmReturnReceiver", "RebirthSystem", "RewardsService",
	"RocketEffects", "RocketEventManager", "RocketLogic", "RocketNPCs", "SeasonPass",
	"SecretTrader", "SecretTreeDoor", "SecurityGuard", "SkinCrateService", "SocialRewards",
	"SquirrelEasterEgg", "ToasterEasterEgg", "WormholeService",
}

-- The remotes the client WaitForChild's. A missing one is not a cosmetic problem: the client sits on a
-- WaitForChild until it times out, and whatever came after that line in the client script never runs --
-- so one dead server script here shows up as several unrelated-looking client failures.
local REMOTES = {
	{ "CoinEvent",           "flight earns no coins" },
	{ "BuyFoodEvent",        "the food shop cannot buy" },
	{ "IslandUnlockEvent",   "islands never unlock" },
	{ "PetEquipBroadcast",   "nobody sees anybody else's pet" },
	{ "StarterPetEvent",     "no free Bean Buddy welcome on a first join" },
	{ "RealmPortalEvent",    "the realm portals cannot teleport" },
	{ "ReturnToIslandEvent", "the Return-to-Island button does nothing" },
	{ "AnnouncementEvent",   "no landing announcements" },
}

local function report()
	local found, dupes, disabled = {}, {}, {}
	for _, d in ipairs(ServerScriptService:GetDescendants()) do
		if d:IsA("Script") or d:IsA("ModuleScript") then
			if found[d.Name] then dupes[d.Name] = (dupes[d.Name] or 1) + 1 else found[d.Name] = true end
			if d:IsA("Script") and d.Disabled then disabled[#disabled + 1] = d.Name end
		end
	end

	local missing = {}
	for _, name in ipairs(EXPECTED) do
		if not found[name] then missing[#missing + 1] = name end
	end

	local badRemotes = {}
	for _, r in ipairs(REMOTES) do
		if not ReplicatedStorage:FindFirstChild(r[1]) then
			badRemotes[#badRemotes + 1] = ("%s -- %s"):format(r[1], r[2])
		end
	end

	local errCount = 0
	for _ in pairs(errors) do errCount = errCount + 1 end

	print("========================= [BootCheck] SERVER =========================")
	print(("scripts: %d of %d expected present   |   players: %d")
		:format(#EXPECTED - #missing, #EXPECTED, #game:GetService("Players"):GetPlayers()))

	if errCount > 0 then
		print(("-- ERRORED (%d) -- stopped dead; everything below the error line never ran"):format(errCount))
		for name, e in pairs(errors) do print(("   %-22s x%d  %s"):format(name, e.count, e.first)) end
	end
	if next(dupes) then
		print("-- DUPLICATES -- a stale copy is baked into the place and BOTH are running:")
		for name, n in pairs(dupes) do print(("   %-22s %d copies"):format(name, n)) end
	end
	if #disabled > 0 then print("-- DISABLED: " .. table.concat(disabled, ", ")) end
	if #missing > 0 then
		print(("-- NEVER ARRIVED (%d):"):format(#missing))
		print("   " .. table.concat(missing, ", "))
	end
	if #badRemotes > 0 then
		print(("-- MISSING REMOTES (%d) -- the client will hang on WaitForChild for each of these:"):format(#badRemotes))
		for _, s in ipairs(badRemotes) do print("   " .. s) end
	end
	if errCount == 0 and not next(dupes) and #disabled == 0 and #missing == 0 and #badRemotes == 0 then
		print("ALL CLEAR -- every expected script is present, none errored, every remote exists.")
	end
	print("======================================================================")
end

task.spawn(function() task.wait(REPORT_AFTER); report() end)
_G.bootCheckServer = report   -- re-run from the command bar in SERVER context: _G.bootCheckServer()
