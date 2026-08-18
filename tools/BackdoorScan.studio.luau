--[[
================================================================================
 BACKDOOR SCANNER  --  FartToFloat  --  RUN IN STUDIO'S COMMAND BAR
================================================================================
 GENERATED. Regenerate after adding or removing scripts, or the manifest below
 goes stale and your own new files start showing up as intruders.

 HOW TO RUN
   1. Open the FartToFloat place in Studio.
   2. View -> Command Bar.  (View -> Output too, that is where the report goes.)
   3. Open this file, select all, copy, paste into the command bar, Enter.

 Nothing is deleted. Set QUARANTINE = true and re-run to disable offenders and
 move them to ServerStorage.BACKDOOR_QUARANTINE, where you can read them before
 deciding. Each one is tagged with the path it came from so it can be put back.

 WHY THE COMMAND BAR AND NOT A SCRIPT INSIDE THE GAME
 Reading another script's code (.Source) requires PLUGIN security. The command
 bar has it; a Script running inside your running game does NOT -- at runtime a
 server script can see another script's name, class and location but is forbidden
 from reading a single character of its code. That is a Roblox restriction with
 no workaround. So the half that can actually read what a script DOES can only
 ever be an edit-time tool. The runtime half is SecurityWatchdog.server.luau,
 and it is deliberately limited to what it genuinely can see.

 WHAT THE MANIFEST IS, AND WHY IT IS THE STRONGEST RULE HERE
 This place is built by Rojo from FartToFloat's src/. The MANIFEST below is the exact
 list of script instances that produces -- 137 of them. So any script in the
 place that is NOT in that list did not come from the repo. It came attached to a
 free model, a toolbox asset, or a plugin.

 That rule does not care what the code looks like, which is the point: pattern
 matching only catches hostile code that resembles hostile code you have already
 seen. The manifest catches a backdoor written this morning in a style nobody has
 catalogued, because it is not on the list. The pattern rules below are the second
 line of defence, for hostile code that landed INSIDE your folders.

 EXPECT SOME LEGITIMATE HITS THE FIRST TIME. Animation scripts inside imported
 models, leftovers from an old kit, things you added by hand in Studio. Review
 each one, then put the ones you trust in ALLOWLIST so the next scan is quiet.
 Resist the urge to allowlist in bulk -- a quiet scan you stopped reading is
 worth nothing.
================================================================================
]]

local QUARANTINE = false -- true = disable + move offenders instead of only reporting

-- Paths you have reviewed and accepted. Exact full paths, e.g.
--     ["Workspace.island3.Model.AnimateSpin"] = true,
local ALLOWLIST = {
}

-- Where Roblox itself puts scripts. Kept SHORT: every entry is a hole in the manifest rule.
local IGNORED_ROOTS = {
	"CoreGui", "CorePackages", "Chat", "TextChatService",
	"StarterPlayer.StarterCharacterScripts", -- Animate, Health: Roblox defaults
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

--------------------------------------------------------------------------------
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

-- Any byte above 127 means the name is not plain ASCII, and that is the whole
-- homoglyph trick: Cyrillic "a" (U+0430) is pixel-identical to Latin "a" in the
-- Explorer, so a script called "Pockoge" spelled with Cyrillic letters reads as
-- "Package" to you and sorts next to the real thing, while being a completely
-- different string to Lua. Every legitimate script name in these projects is
-- ASCII, so there is no false positive to trade off against.
local function nonAscii(s)
	local bad = {}
	for i = 1, #s do
		local b = s:byte(i)
		if b > 127 then table.insert(bad, string.format("pos %d=0x%02X", i, b)) end
	end
	return (#bad > 0) and table.concat(bad, " ") or nil
end

--------------------------------------------------------------------------------
-- SOURCE RULES -- command bar only. Ordered by how damning.
--------------------------------------------------------------------------------
local RULES = {
	{ id = "require-asset-id", sev = "CRITICAL",
	  why = "Downloads and runs code from a Roblox asset you do not control. THE standard backdoor: its author can swap the payload at any time, after your review, without ever touching your place.",
	  test = function(s)
		local m = s:match("require%s*%(%s*%d%d%d%d+") or s:match("require%s*%(%s*tonumber")
			or s:match("require%s*%(%s*[%w_]+%s*%+%s*%d")
		return m and ("matched " .. m) or nil
	  end },
	{ id = "loadstring", sev = "CRITICAL",
	  why = "Compiles a string into runnable code. No legitimate use in these projects, and it is how a fetched payload gets executed.",
	  test = function(s) return s:find("loadstring") and "loadstring present" or nil end },
	{ id = "http-exfil", sev = "CRITICAL",
	  why = "Sends data out of the game or pulls code in. HttpService:JSONEncode is fine and is NOT flagged; DataStore:GetAsync is a different service and is NOT flagged.",
	  test = function(s)
		if not s:find("HttpService") then return nil end
		for _, c in ipairs({"GetAsync", "PostAsync", "RequestAsync"}) do
			if s:match("HttpService[^\n]-:%s*" .. c) then return "HttpService:" .. c end
		end
		return nil
	  end },
	{ id = "env-tampering", sev = "CRITICAL",
	  why = "getfenv/setfenv rewrite which globals a chunk sees -- used to hide behaviour from a reader and to defeat sandboxing. Not used anywhere in these codebases.",
	  test = function(s)
		local m = s:match("getfenv") or s:match("setfenv")
		return m and (m .. " present") or nil
	  end },
	{ id = "self-hiding", sev = "HIGH",
	  why = "A script that deletes or unparents itself on run is hiding from exactly this scan.",
	  test = function(s)
		local m = s:match("script%s*:%s*Destroy") or s:match("script%.Parent%s*=%s*nil")
		return m and "removes itself at runtime" or nil
	  end },
	{ id = "owner-targeting", sev = "HIGH",
	  why = "Code singling out one UserId is how a backdoor gives its author admin in your game while behaving normally for everyone else.",
	  test = function(s)
		local id = s:match("UserId%s*==%s*(%d%d%d+)")
		return id and ("hardcoded UserId " .. id) or nil
	  end },
	{ id = "base64-blob", sev = "HIGH",
	  why = "A long unbroken base64-ish literal is an encoded payload far more often than it is data.",
	  test = function(s)
		local b = s:match("[\"']([A-Za-z0-9+/=][A-Za-z0-9+/=][A-Za-z0-9+/=][A-Za-z0-9+/=]+)[\"']")
		return (b and #b >= 200) and ("encoded blob, " .. #b .. " chars") or nil
	  end },
	{ id = "escape-blob", sev = "HIGH",
	  why = "A long run of decimal \\ddd escapes smuggles a payload past a human reading the source. Threshold 40 is measured, not guessed: the worst legitimate file across all four realms is Bubbles.client.luau at 16 (emoji), so this leaves 2.5x headroom. Most emoji here use \\xNN hex, which is not counted at all.",
	  test = function(s)
		local n = 0
		for _ in s:gmatch("\\%d%d%d") do n = n + 1 end
		return (n >= 40) and (n .. " decimal escapes") or nil
	  end },
	{ id = "obfuscated-names", sev = "MEDIUM",
	  why = "Machine-mangled identifiers. Real code does not name things like this; obfuscators do.",
	  test = function(s)
		local n = 0
		for _ in s:gmatch("_0x%x%x%x+") do n = n + 1 end
		return (n >= 3) and (n .. " mangled identifiers") or nil
	  end },
}

--------------------------------------------------------------------------------
local findings, scanned = {}, 0
local function add(sev, rule, inst, path, detail, why)
	table.insert(findings, {sev = sev, rule = rule, inst = inst, path = path, detail = detail, why = why})
end

for _, inst in ipairs(game:GetDescendants()) do
	if inst:IsA("LuaSourceContainer") then
		local path = fullPath(inst)
		if not underAny(path, IGNORED_ROOTS) and not ALLOWLIST[path] then
			scanned = scanned + 1

			if not MANIFEST[path] then
				add("CRITICAL", "not-in-manifest", inst, path, inst.ClassName,
					"Not produced by this realm's Rojo project, so it is not from src/. It arrived with a model, a toolbox asset, or a plugin.")
			end

			local na = nonAscii(inst.Name)
			if na then
				add("CRITICAL", "homoglyph-name", inst, path, na,
					"Name contains non-ASCII characters that look like Latin letters in the Explorer. A deliberate disguise -- there is no innocent reason for it.")
			end

			local ok, src = pcall(function() return inst.Source end)
			if not ok or type(src) ~= "string" then
				add("HIGH", "source-unreadable", inst, path, tostring(src),
					"Could not read this script's code. From the command bar that should not happen -- treat it as hostile until explained.")
			else
				for _, r in ipairs(RULES) do
					local okr, d = pcall(r.test, src)
					if okr and d then add(r.sev, r.id, inst, path, d, r.why) end
				end
			end
		end
	end
end

local ORDER = {CRITICAL = 1, HIGH = 2, MEDIUM = 3}
table.sort(findings, function(a, b)
	if ORDER[a.sev] ~= ORDER[b.sev] then return ORDER[a.sev] < ORDER[b.sev] end
	return a.path < b.path
end)

print(("\n========== BACKDOOR SCAN -- FartToFloat ==========\n%d scripts scanned against a 137-entry manifest, %d findings")
	:format(scanned, #findings))

if #findings == 0 then
	print("\nNo findings.\n\nWhat that does and does not mean: every script in the place is one this realm's\n"
		.. "Rojo project creates, and none matched a known-hostile pattern. Novel code doing\n"
		.. "something bad in a way no rule here describes, sitting inside a manifested file,\n"
		.. "would still pass. This narrows the risk; it does not prove the place is clean.")
else
	local byPath, order = {}, {}
	for _, f in ipairs(findings) do
		if not byPath[f.path] then byPath[f.path] = {}; table.insert(order, f.path) end
		table.insert(byPath[f.path], f)
	end
	for _, path in ipairs(order) do
		print(("\n[%s] %s"):format(byPath[path][1].sev, path))
		for _, g in ipairs(byPath[path]) do
			print(("    %-18s %s"):format(g.rule, g.detail))
			print(("      -> %s"):format(g.why))
		end
	end

	if QUARANTINE then
		local ss = game:GetService("ServerStorage")
		local folder = ss:FindFirstChild("BACKDOOR_QUARANTINE")
		if not folder then
			folder = Instance.new("Folder"); folder.Name = "BACKDOOR_QUARANTINE"; folder.Parent = ss
		end
		local moved = 0
		for _, path in ipairs(order) do
			local inst = byPath[path][1].inst
			if inst and inst.Parent then
				local tag = Instance.new("StringValue")
				tag.Name = "OriginalPath"; tag.Value = path; tag.Parent = inst
				pcall(function() inst.Disabled = true end) -- Script/LocalScript only; ModuleScript has no Disabled
				inst.Parent = folder
				moved = moved + 1
			end
		end
		print(("\nQUARANTINED %d script(s) -> ServerStorage.BACKDOOR_QUARANTINE"):format(moved))
		print("Each carries an OriginalPath value, so a false positive can be put back.")
	else
		print("\nNothing was changed. Set QUARANTINE = true at the top and re-run to disable and\n"
			.. "move these into ServerStorage.BACKDOOR_QUARANTINE for inspection.")
	end
end

print("\nAFTER CLEANING: save the place, then REPUBLISH. Deleting a backdoor in Studio does\n"
	.. "nothing to the version your players are on until you publish over it.\n"
	.. "================================================\n")
