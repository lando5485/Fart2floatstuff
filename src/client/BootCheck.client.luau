--======================================================================
-- BootCheck.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- "SOME OF THE STUFF ISN'T RENDERING AND I DON'T KNOW WHY."
--
-- Almost everything in this game is BUILT BY A SCRIPT rather than placed in the world -- the HUD, the
-- portals, the NPCs, the pets, the cave. That is fine right up until one of those scripts fails to run, at
-- which point the thing it was supposed to build simply is not there. No error on screen, no gap, no clue:
-- just a world that is quietly missing a piece, differently on each join.
--
-- This finds out WHICH piece and WHY. It is a diagnostic only -- it never fixes, hides or rebuilds
-- anything, so it can be left in permanently and it cannot become a load-bearing part of the game.
--
-- ===== THE FOUR WAYS A SCRIPT GOES MISSING, AND HOW EACH IS CAUGHT =====
--
--   1. IT ERRORED ON LOAD. One runtime error stops that script dead; everything below the error line never
--      runs. The rest of the game carries on, which is what makes it so hard to spot. ScriptContext.Error
--      is hooked on the FIRST LINE of this file so the report can name the script and the line.
--
--   2. THERE ARE TWO OF IT. A stale copy baked into the place file sits beside the Rojo one and BOTH run.
--      They fight over the same GUI or model and you get whichever finished last -- which is why the bug
--      "moves" between joins. Duplicates are listed by name.
--
--   3. IT NEVER ARRIVED. In the project file but not in the container -- a sync that did not finish, or a
--      script deleted by hand in Studio. Checked against the manifest below.
--
--   4. IT IS DISABLED. Somebody ticked Disabled to test something and never un-ticked it.
--
-- ===== AND THE FIFTH, WHICH IS NOT A SCRIPT PROBLEM AT ALL =====
-- StreamingEnabled. A model built far from the player does not stream in unless its ModelStreamingMode is
-- Persistent. The script ran perfectly and the thing is still invisible. The ARTIFACTS section below checks
-- for the objects themselves, so "script ran but nothing appeared" is distinguishable from "script died".
--======================================================================

-- ===== HOOK ERRORS FIRST. Nothing above this line, or the errors it exists to catch escape. =====
local errors = {}   -- [scriptName] = { count = n, first = "message @ line" }
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

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local player            = Players.LocalPlayer

local REPORT_AFTER = 20   -- seconds. Long enough for the intro, the loading screen and late streaming.

--======================================================================
-- THE MANIFEST -- generated from default.project.json
--======================================================================
-- If this drifts from the project file the report says so rather than lying: a name here that is not in the
-- game reads as MISSING, and a script in the game that is not here is simply not checked. Regenerate it
-- whenever you add or remove a client script.
local EXPECTED = {
	"AmbientSmoke", "AmbientWildlife", "BellyPuff", "BlackBarKiller", "ButtonTextStyle", "Campfire",
	"CommunityGarden", "CoreClient", "CrateClient", "DailyTasks", "EventClient",
	"EventSoundPreload", "FarmerTutorial", "FlightFeedback", "FoodRealmHud", "GardenChestClient",
	"GardenDonationClient", "GardenGuideTrail", "GardenIntro", "GardenerChat", "GardenerLife",
	"GutSkinClient", "HeldItemSync", "LandingImpact", "MenuBackButton", "MenuBackdropGuard",
	"MeteorImpactSound", "MeteorUI", "MusicClient", "MusicDucking", "NotifyCenter", "NotifyOptIn",
	"NpcGuideArrow", "NpcLife", "NpcWaypointArrow", "ObjectiveHUD", "OfflineEarnings", "PetFollow",
	"PetSkinLook", "RailGuard", "RainbowBeamUI", "RealmPortals", "RebirthClient", "RebirthTag",
	"RemotePets", "RewardsClient", "RewardsHub", "RocketBuildPreload", "RocketSounds", "RocketUI",
	"SeasonPass", "SeasonalPetsChest", "SecretCave", "SettingsMenu", "ShopClient",
	"SkinCrateClient", "SkyByAltitude", "SocialRewards", "TitleTags", "TokenHud", "TopCenterStack",
	"WarpEffect", "WorldClient", "WormholeClient",
}

-- THE ARTIFACTS: things that must EXIST once the scripts have run. This is the half that catches a script
-- which ran fine but whose output never appeared -- streaming, a silent early `return`, a WaitForChild that
-- timed out. Each entry is { where, name, "what it means if this is missing" }.
local ARTIFACTS = {
	{ "gui", "BottomStackGui",  "the gas meter + fart button (CoreClient)" },
	{ "gui", "CoinGui",         "the coin counter (CoreClient)" },
	{ "gui", "PetQuestUI",      "quest tracker + starter-pet card (PetFollow)" },
	{ "gui", "ObjectiveHUD",    "the directions card" },
	{ "gui", "SettingsGui",     "the gear button" },
	{ "rem", "CoinEvent",       "coin payouts -- flight earns nothing without it" },
	{ "rem", "BuyFoodEvent",    "the food shop cannot buy" },
	{ "rem", "PetEquipBroadcast", "other players' pets will not render" },
	{ "rem", "RealmPortalEvent",  "the realm portals cannot teleport" },
	{ "rem", "ReturnToIslandEvent", "the Return-to-Island button does nothing" },
	{ "glo", "MainMenuManager",  "menus will not close each other / hide the HUD" },
	{ "glo", "NotifyCenter",     "announcement banners" },
	{ "glo", "applyHudScaling",  "nothing will be scaled for mobile" },
}

--======================================================================
-- THE REPORT
--======================================================================
local function report()
	local container = player:WaitForChild("PlayerScripts", 10) or player:FindFirstChild("PlayerScripts")
	local found, dupes, disabled = {}, {}, {}
	if container then
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("LocalScript") or d:IsA("Script") then
				if found[d.Name] then dupes[d.Name] = (dupes[d.Name] or 1) + 1 else found[d.Name] = true end
				if d.Disabled then disabled[#disabled + 1] = d.Name end
			end
		end
	end

	local missing = {}
	for _, name in ipairs(EXPECTED) do
		if not found[name] then missing[#missing + 1] = name end
	end

	local badArtifacts = {}
	for _, a in ipairs(ARTIFACTS) do
		local kind, name, why = a[1], a[2], a[3]
		local ok = false
		if kind == "gui" then ok = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild(name) ~= nil
		elseif kind == "rem" then ok = ReplicatedStorage:FindFirstChild(name) ~= nil
		elseif kind == "glo" then ok = _G[name] ~= nil end
		if not ok then badArtifacts[#badArtifacts + 1] = ("%s (%s) -- %s"):format(name, kind, why) end
	end

	local errCount = 0
	for _ in pairs(errors) do errCount = errCount + 1 end

	print("========================= [BootCheck] CLIENT =========================")
	print(("scripts: %d of %d expected present"):format(#EXPECTED - #missing, #EXPECTED))

	if errCount > 0 then
		print(("-- ERRORED (%d) -- these stopped dead; everything below the error line never ran"):format(errCount))
		for name, e in pairs(errors) do
			print(("   %-22s x%d  %s"):format(name, e.count, e.first))
		end
	end
	if next(dupes) then
		print("-- DUPLICATES -- a stale copy is baked into the place and BOTH are running:")
		for name, n in pairs(dupes) do print(("   %-22s %d copies"):format(name, n)) end
	end
	if #disabled > 0 then print("-- DISABLED: " .. table.concat(disabled, ", ")) end
	if #missing > 0 then
		print(("-- NEVER ARRIVED (%d) -- in the project file, not in the game:"):format(#missing))
		print("   " .. table.concat(missing, ", "))
	end
	if #badArtifacts > 0 then
		print(("-- BUILT NOTHING (%d) -- the script may have run; its output is not here:"):format(#badArtifacts))
		for _, s in ipairs(badArtifacts) do print("   " .. s) end
	end
	if errCount == 0 and not next(dupes) and #disabled == 0 and #missing == 0 and #badArtifacts == 0 then
		print("ALL CLEAR -- every expected script is present, none errored, every artifact built.")
	end
	print("======================================================================")
end

task.spawn(function() task.wait(REPORT_AFTER); report() end)

-- Re-run on demand from the command bar (Client context), no rejoin needed:  _G.bootCheck()
-- Useful after a hot reload, or to re-check once you have walked somewhere that streams more in.
_G.bootCheck = report
