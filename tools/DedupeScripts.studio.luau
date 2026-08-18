--!nocheck
-- ============================================================================================================
-- DEDUPE SCRIPTS (Studio tool) -- deletes the STALE baked-in copies that shadow the Rojo-synced scripts.
-- ============================================================================================================
-- WHY THIS EXISTS
-- Rojo only ADDS, it never overwrites. A copy of a script baked into the place file keeps running ALONGSIDE
-- the synced one, so two copies of PlayerStats, RebirthSystem, SkyByAltitude and ~24 others execute every
-- boot. That is not cosmetic -- the symptoms are already in the boot log:
--     [Sky] ready ... SkyByAltitude:416   <- the Rojo copy
--     [Sky] ready ... SkyByAltitude:397   <- a STALE copy, still writing the old grey atmosphere every frame
--     [Campfire] removed 2 STALE duplicate server script(s) -- they were tripling every button press
--     [Blimp] retired 1 STALE duplicate BlimpService script(s) -- they were flying a SECOND blimp
-- Several scripts already hand-roll their own de-duplication at runtime. This removes the cause instead.
--
-- HOW IT DECIDES WHICH COPY TO KEEP -- the hard part, since both copies share a name AND a parent
-- EXPECTED below was GENERATED FROM THE FILES ON DISK. For every Rojo-managed script it stores four things:
-- line count, character count, the first line, and the last non-empty line. Each candidate in the place is
-- scored 0-4 against that signature. The copy that matches is the current Rojo one. The stale copy is an older
-- version of the same file and will differ in at least its length.
--
-- SAFETY -- it refuses rather than guesses:
--   * DRY_RUN is TRUE by default. Nothing is deleted until you set it false and run it again.
--   * A group is only touched when exactly ONE candidate has the highest score AND that score >= MIN_SCORE.
--     A tie, or a best score below MIN_SCORE, is reported and SKIPPED -- never a coin flip.
--   * Only paths in EXPECTED are considered. Scripts that exist ONLY in the place file -- PetWheel,
--     DailyStreak, CampfirePromptWindow, PlayerModule -- are NOT duplicates. They are place-only features and
--     are never looked at, let alone deleted.
--   * Deleting is the ONLY mutation. Nothing is renamed, reparented, edited or disabled.
--
-- HOW TO RUN  (read this bit -- it will not work from a normal Script)
--   Script.Source is readable only from a PLUGIN or the COMMAND BAR. A Script running in Play mode cannot
--   read it, so this cannot be dropped into ServerScriptService and run in a playtest.
--     1. Have Rojo connected and synced, so the current files are definitely in the place.
--     2. STOP the game -- be in edit mode, not a playtest, or the deletions vanish when you stop.
--     3. Studio > View > Command Bar. Paste this whole file in and press Enter.
--     4. Read the report in the Output window.
--     5. Set DRY_RUN = false at the top, paste and run again.
--     6. File > Save, then republish.
-- ============================================================================================================

local DRY_RUN   = true   -- <<< set to false to actually delete
local MIN_SCORE = 3      -- of 4: lines / chars / first line / last non-empty line

-- ---- signatures of the real files on disk (generated; regenerate if the project layout changes) ------------
local EXPECTED = {
	["ReplicatedFirst.LoadingScreen"] = { lines = 1574, chars = 79219, first = "-- ===== FART TO FLOAT \226\128\148 STARTUP LOADING SCREEN =====", last = "end)" },
	["ReplicatedStorage.PhoneHUD"] = { lines = 93, chars = 5118, first = "--[[", last = "return PhoneHUD" },
	["ReplicatedStorage.Shared.Constants"] = { lines = 45, chars = 1713, first = "--!nonstrict", last = "return Constants" },
	["ReplicatedStorage.Shared.CosmeticConfig"] = { lines = 161, chars = 10982, first = "--!nonstrict", last = "return CosmeticConfig" },
	["ReplicatedStorage.Shared.CosmeticIcon"] = { lines = 117, chars = 3626, first = "--!nonstrict", last = "return CosmeticIcon" },
	["ReplicatedStorage.Shared.CrateTokens"] = { lines = 178, chars = 10711, first = "--!nonstrict", last = "return CrateTokens" },
	["ReplicatedStorage.Shared.Gamepasses"] = { lines = 212, chars = 10926, first = "--!nonstrict", last = "return Gamepasses" },
	["ReplicatedStorage.Shared.GutSkins"] = { lines = 89, chars = 4241, first = "--!strict", last = "return GutSkins" },
	["ReplicatedStorage.Shared.PetCollection"] = { lines = 150, chars = 8442, first = "--!nonstrict", last = "return PetCollection" },
	["ReplicatedStorage.Shared.PetRarity"] = { lines = 98, chars = 5314, first = "--!strict", last = "return PetRarity" },
	["ReplicatedStorage.Shared.PetSkins"] = { lines = 172, chars = 11183, first = "--!nonstrict", last = "return PetSkins" },
	["ReplicatedStorage.Shared.PetTraits"] = { lines = 151, chars = 7515, first = "--!nonstrict", last = "return PetTraits" },
	["ReplicatedStorage.Shared.RealmTransfer"] = { lines = 165, chars = 9309, first = "--!nonstrict", last = "return RealmTransfer" },
	["ReplicatedStorage.Shared.Remotes"] = { lines = 61, chars = 1829, first = "--!nonstrict", last = "return Remotes" },
	["ReplicatedStorage.Shared.Sfx"] = { lines = 168, chars = 8417, first = "--======================================================================", last = "return Sfx" },
	["ReplicatedStorage.Shared.SkinCrates"] = { lines = 564, chars = 30080, first = "--!nonstrict", last = "return SkinCrates" },
	["ServerScriptService.BadgeAwards"] = { lines = 189, chars = 8981, first = "--======================================================================", last = "end" },
	["ServerScriptService.BeamCollision"] = { lines = 101, chars = 4223, first = "--======================================================================", last = "return BeamCollision" },
	["ServerScriptService.BeamEffects"] = { lines = 162, chars = 7247, first = "--======================================================================", last = "return BeamEffects" },
	["ServerScriptService.BeamGeneration"] = { lines = 192, chars = 7920, first = "--======================================================================", last = "return BeamGeneration" },
	["ServerScriptService.BeamKnockback"] = { lines = 80, chars = 3247, first = "--======================================================================", last = "return BeamKnockback" },
	["ServerScriptService.BeamPattern"] = { lines = 106, chars = 4885, first = "--======================================================================", last = "return BeamPattern" },
	["ServerScriptService.BellySystem"] = { lines = 288, chars = 14308, first = "-- ============================================================================", last = "end" },
	["ServerScriptService.BigEventScheduler"] = { lines = 86, chars = 3764, first = "--======================================================================", last = "\"s, only one at a time, never the same twice in a row.\")" },
	["ServerScriptService.BlackHoleTeleport"] = { lines = 92, chars = 5995, first = "--======================================================================", last = "\", testersOnly=\" .. tostring(SPACE_REALM_TESTERS_ONLY) .. \")\")" },
	["ServerScriptService.BlimpService"] = { lines = 842, chars = 40783, first = "-- BlimpService.server.lua  (Script)  -- the PLS DONATE-style airship that laps Bean Farm.", last = "island.Name, LAP_RADIUS, flyY, LAP_SECONDS, tostring(blimp.ModelStreamingMode)))" },
	["ServerScriptService.BootCheck"] = { lines = 116, chars = 5848, first = "--======================================================================", last = "_G.bootCheckServer = report   -- re-run from the command bar in SERVER context: _G.bootCheckServer()" },
	["ServerScriptService.Campfire"] = { lines = 1104, chars = 59149, first = "--======================================================================", last = "end)" },
	["ServerScriptService.ComebackNudge"] = { lines = 455, chars = 24477, first = "-- ============================================================================================================", last = "end" },
	["ServerScriptService.CommunityGarden"] = { lines = 3213, chars = 208314, first = "--======================================================================", last = "Players.PlayerAdded:Connect(hookGardenChat)" },
	["ServerScriptService.CrateService"] = { lines = 255, chars = 11840, first = "--!nonstrict", last = "end)" },
	["ServerScriptService.DailyTasks"] = { lines = 276, chars = 12992, first = "-- DailyTasks.server.lua  (Script)  -- the daily chore list, and the reason to log in tomorrow.", last = "end" },
	["ServerScriptService.DevArrival"] = { lines = 722, chars = 30659, first = "--[[", last = "end" },
	["ServerScriptService.DevCommands"] = { lines = 243, chars = 13994, first = "--!nonstrict", last = "end" },
	["ServerScriptService.EasterEggManager"] = { lines = 770, chars = 41886, first = "--======================================================================", last = "print(\"[EasterEgg] manager ready (\" .. #EGGS .. \" easter egg(s))\")" },
	["ServerScriptService.FarmerSpawner"] = { lines = 295, chars = 15953, first = "-- ===== FARMER TUTORIAL NPC (spawner) =====", last = "end)" },
	["ServerScriptService.GardenBird"] = { lines = 1018, chars = 60714, first = "--======================================================================", last = "end" },
	["ServerScriptService.GardenFeeding"] = { lines = 306, chars = 16127, first = "-- ============================================================================", last = "print(\"[Feeding] garden feeding ready (cow + pig: grab food box -> feed -> +1 coin)\")" },
	["ServerScriptService.GardenGnomes"] = { lines = 197, chars = 9600, first = "-- ============================================================================================================", last = "end)" },
	["ServerScriptService.GardenerWave"] = { lines = 234, chars = 10916, first = "-- ============================================================================================================", last = "end" },
	["ServerScriptService.Gifting"] = { lines = 265, chars = 13286, first = "--======================================================================", last = "MIN_GIFT, MAX_GIFT, COOLDOWN, MAX_PER_SESSION, MAX_MAILBOX))" },
	["ServerScriptService.GutSkinService"] = { lines = 118, chars = 6300, first = "-- ============================================================================", last = "print(\"[GutSkins] service ready (playtime unlocks; EquipGutSkin / GetGutSkins / GutSkinState / GutSkinUnlocked)\")" },
	["ServerScriptService.HeldItemSync"] = { lines = 96, chars = 4902, first = "--======================================================================", last = "\"' player attribute, cleared on death/respawn\")" },
	["ServerScriptService.IslandNPCs"] = { lines = 676, chars = 31448, first = "-- ============================================================================================", last = "end)" },
	["ServerScriptService.IslandStreaming"] = { lines = 299, chars = 16249, first = "-- ============================================================================", last = "end)" },
	["ServerScriptService.LateJoinEventSync"] = { lines = 89, chars = 5368, first = "--======================================================================", last = "print(\"[LateJoinEventSync] ready -- late-joiners will be caught up on any in-progress big event\")" },
	["ServerScriptService.LeaderboardService"] = { lines = 1115, chars = 65435, first = "-- ============================================================================================", last = ".. \"scrollable; submit on join + autosave + leave\"):format(OG_LIMIT, TOP_N))" },
	["ServerScriptService.MeatballShooter"] = { lines = 131, chars = 6934, first = "-- ============================================================================", last = "end)" },
	["ServerScriptService.MeteorImpact"] = { lines = 457, chars = 19311, first = "--======================================================================", last = "return MeteorImpact" },
	["ServerScriptService.MeteorManager"] = { lines = 420, chars = 20701, first = "--======================================================================", last = "for _, p in ipairs(Players:GetPlayers()) do hookMeteorCmd(p) end" },
	["ServerScriptService.MeteorReward"] = { lines = 179, chars = 6968, first = "--======================================================================", last = "return MeteorReward" },
	["ServerScriptService.MeteorSpawn"] = { lines = 409, chars = 16037, first = "--======================================================================", last = "return MeteorSpawn" },
	["ServerScriptService.MilkCap"] = { lines = 130, chars = 6454, first = "-- ============================================================================", last = "end)" },
	["ServerScriptService.MusicManager"] = { lines = 75, chars = 4327, first = "--======================================================================", last = "print(\"[MusicManager] ducking infrastructure ready (BackgroundMusic group + BigEventActive flag); playback runs client-side in MusicClient\")" },
	["ServerScriptService.PetBarn"] = { lines = 1099, chars = 63464, first = "--======================================================================", last = "end)" },
	["ServerScriptService.PetSystem"] = { lines = 3180, chars = 197339, first = "-- ============================================================================================", last = "print(\"[Pet] PetSystem ready (cosmetic-only)\")" },
	["ServerScriptService.PlanetSelectService"] = { lines = 133, chars = 6553, first = "--======================================================================", last = "print((\"[PlanetSelect] service online (Space Realm place id %d)\"):format(SPACE_REALM_PLACE_ID))" },
	["ServerScriptService.PlayerState"] = { lines = 296, chars = 10084, first = "--!nonstrict", last = "return PlayerState" },
	["ServerScriptService.PlayerStats"] = { lines = 2700, chars = 172692, first = "-- Enable Studio access to DataStores: go to Game Settings > Security >", last = "print(\"DONE\")" },
	["ServerScriptService.PopcornTrees"] = { lines = 186, chars = 10274, first = "-- ============================================================================", last = "end)" },
	["ServerScriptService.RainbowBeamManager"] = { lines = 228, chars = 11171, first = "--======================================================================", last = "-- and the collision loop routes touches to the launch-snapshot rewind.)" },
	["ServerScriptService.RealmPortalsHub"] = { lines = 537, chars = 27430, first = "--======================================================================", last = ":format(REALMS.space.placeId, REALMS.dino.placeId, REALMS.candy.placeId))" },
	["ServerScriptService.RealmReturnReceiver"] = { lines = 342, chars = 17044, first = "--======================================================================", last = "print(\"[RealmReturn] ready -- merging state carried home from the other realms\")" },
	["ServerScriptService.RebirthSystem"] = { lines = 245, chars = 12448, first = "--======================================================================", last = "print(\"[Rebirth] system ready -- finish islands + Space + Dino -> rebirth for +coins/speed/luck (REBIRTH side button)\")" },
	["ServerScriptService.RewardsService"] = { lines = 154, chars = 8634, first = "-- ============================================================================", last = "Gamepasses.isConfigured(\"VIP\") and \"\" or \" -- VIP id NOT SET, perk inert\"))" },
	["ServerScriptService.RocketEffects"] = { lines = 522, chars = 20386, first = "--======================================================================", last = "return RocketEffects" },
	["ServerScriptService.RocketEventManager"] = { lines = 276, chars = 14751, first = "--======================================================================", last = "-- test hook, it is a way for any other script to launch a rocket by accident.)" },
	["ServerScriptService.RocketLogic"] = { lines = 569, chars = 26018, first = "--======================================================================", last = "return RocketLogic" },
	["ServerScriptService.RocketNPCs"] = { lines = 1271, chars = 64386, first = "--======================================================================", last = "return RocketNPCs" },
	["ServerScriptService.RocketRide"] = { lines = 797, chars = 39830, first = "--!nonstrict", last = "return RocketRide" },
	["ServerScriptService.SeasonPass"] = { lines = 209, chars = 9443, first = "--======================================================================", last = ":format(SEASON_ID, #TIERS, TIER_XP, PREMIUM_GAMEPASS_ID))" },
	["ServerScriptService.SecretTrader"] = { lines = 471, chars = 23223, first = "--======================================================================", last = ".. \"server-side and never read from the client.\"):format(#PERMANENT, ROTATING_SLOTS, #POOL, RESTOCK_SECONDS))" },
	["ServerScriptService.SecretTreeDoor"] = { lines = 427, chars = 26746, first = "-- ============================================================================", last = "end)" },
	["ServerScriptService.SecurityGuard"] = { lines = 138, chars = 6640, first = "-- ============================================================================", last = "print(\"[SecurityGuard] active (insertion guard + signature sweep; arms in \" .. CONFIG.graceSeconds .. \"s).\")" },
	["ServerScriptService.SecurityWatchdog"] = { lines = 361, chars = 17233, first = "--======================================================================", last = "--======================================================================" },
	["ServerScriptService.SkinCrateService"] = { lines = 1305, chars = 67051, first = "-- ============================================================================================================", last = "(SkinCrates.TEST_MODE and \"  [TEST_MODE: token packs credit without Robux]\" or \"\"))" },
	["ServerScriptService.SocialRewards"] = { lines = 106, chars = 4861, first = "--======================================================================", last = "print((\"[Social] rewards ready -- like / favourite / group, +%d pet levels each, one-time\"):format(LEVELS))" },
	["ServerScriptService.SocialStats"] = { lines = 155, chars = 7577, first = "--======================================================================", last = "TOTAL_SPECIES, totalSkins))" },
	["ServerScriptService.SquirrelEasterEgg"] = { lines = 566, chars = 33191, first = "--======================================================================", last = "end)" },
	["ServerScriptService.ToasterEasterEgg"] = { lines = 433, chars = 22603, first = "--======================================================================", last = "end)" },
	["ServerScriptService.TradeRequests"] = { lines = 411, chars = 18785, first = "--!nonstrict", last = "print(\"[TradeReq] ready -- offline trade requests by name or friends list (messages only; no item ever moves)\")" },
	["ServerScriptService.VipService"] = { lines = 120, chars = 6307, first = "-- ============================================================================================================", last = "Gamepasses.isConfigured(\"VIP\") and \"\" or \" -- VIP id NOT SET, nobody can own it yet\"))" },
	["ServerScriptService.WormholeService"] = { lines = 28, chars = 1643, first = "--======================================================================", last = "print(\"[Wormhole] service ready -- island fast-travel via WormholeWarp (delegates to PlayerStats _G.wormholeWarp)\")" },
	["StarterPlayer.StarterPlayerScripts.Achievements"] = { lines = 107, chars = 5357, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.AmbientSmoke"] = { lines = 488, chars = 25393, first = "-- ============================================================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.AmbientWildlife"] = { lines = 368, chars = 19217, first = "-- ============================================================================================================", last = "print(\"[Wildlife] ready -- butterflies + bees over the garden, birds circling Bean Farm (client-side, no replication)\")" },
	["StarterPlayer.StarterPlayerScripts.BellyPuff"] = { lines = 105, chars = 4301, first = "-- ============================================================================", last = "print(\"[Belly] client puff active (inflates with gas charge, deflates on release)\")" },
	["StarterPlayer.StarterPlayerScripts.BlackBarKiller"] = { lines = 62, chars = 2831, first = "--======================================================================", last = "print(\"[BlackBarKiller] active -- keeps empty SocialRewards toasts hidden (kills the black bar)\")" },
	["StarterPlayer.StarterPlayerScripts.BlimpRide"] = { lines = 84, chars = 4315, first = "--!nonstrict", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.BootCheck"] = { lines = 161, chars = 8976, first = "--======================================================================", last = "_G.bootCheck = report" },
	["StarterPlayer.StarterPlayerScripts.ButtonTextStyle"] = { lines = 226, chars = 11155, first = "--======================================================================", last = "print(\"[BtnText] label legibility pass active -- cream text, 2px tinted stroke, darkened fills, no twin shadows\")" },
	["StarterPlayer.StarterPlayerScripts.Campfire"] = { lines = 382, chars = 21877, first = "--======================================================================", last = "print(\"[Campfire] client ready -- roasting buttons wired\")" },
	["StarterPlayer.StarterPlayerScripts.CoinMagnet"] = { lines = 124, chars = 6154, first = "-- ============================================================================================================", last = "Gamepasses.isConfigured(\"CoinMagnet\") and \"\" or \" -- CoinMagnet id NOT SET, nobody can own it yet\"))" },
	["StarterPlayer.StarterPlayerScripts.CoinPulse"] = { lines = 166, chars = 7849, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.CommunityGarden"] = { lines = 382, chars = 21821, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.CoreClient"] = { lines = 3994, chars = 252168, first = "-- ############################################################################", last = "print(\"FIXED\")" },
	["StarterPlayer.StarterPlayerScripts.CrateClient"] = { lines = 1522, chars = 76292, first = "--!nonstrict", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.DailyTasks"] = { lines = 600, chars = 26274, first = "-- DailyTasks.client.luau  (LocalScript)  -- the daily chore checklist panel.", last = "print(\"[DailyTasks] panel ready -- opens from More+ > Daily Tasks (700x520, same frame as the Shop)\")" },
	["StarterPlayer.StarterPlayerScripts.DevArrivalBanner"] = { lines = 124, chars = 5090, first = "--[[", last = "print(\"[DevArrival] banner client ready -- listening for developer arrivals\")" },
	["StarterPlayer.StarterPlayerScripts.DevAuraFX"] = { lines = 139, chars = 4724, first = "--[[", last = "print(\"[DevAuraFX] ready -- orbit rings render locally for any player tagged \" .. ATTR)" },
	["StarterPlayer.StarterPlayerScripts.EventClient"] = { lines = 2050, chars = 122388, first = "print(\"EVENTCLIENT STARTED\")", last = "print(\"CHUNK 2 DONE\")" },
	["StarterPlayer.StarterPlayerScripts.EventSoundPreload"] = { lines = 51, chars = 2541, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.FarmerTutorial"] = { lines = 97, chars = 4754, first = "-- ===== FARMER TUTORIAL DIALOG (client) =====", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.FirstBuy"] = { lines = 147, chars = 7334, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.FirstPersonMenuMouse"] = { lines = 90, chars = 4418, first = "--======================================================================", last = "print(\"[FirstPersonMenuMouse] loaded -- shops are clickable in first person\")" },
	["StarterPlayer.StarterPlayerScripts.FlightFeedback"] = { lines = 290, chars = 13397, first = "-- ============================================================================================================", last = "print(\"[FlightFeedback] ready -- 'passed another player' callout under the stats panel (/passed)\")" },
	["StarterPlayer.StarterPlayerScripts.FoodRealmHud"] = { lines = 735, chars = 38603, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.GardenChestClient"] = { lines = 228, chars = 15212, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.GardenDonationClient"] = { lines = 618, chars = 37503, first = "--======================================================================", last = "print(\"GARDEN DONATE GUI UPDATED\")" },
	["StarterPlayer.StarterPlayerScripts.GardenGuideTrail"] = { lines = 323, chars = 17434, first = "--======================================================================", last = ".. \" (island-NPC trail removed; the \\xE2\\x96\\xBC over their head is the only NPC pointer)\")" },
	["StarterPlayer.StarterPlayerScripts.GardenIntro"] = { lines = 1014, chars = 52145, first = "-- ============================================================================", last = "end" },
	["StarterPlayer.StarterPlayerScripts.GardenerChat"] = { lines = 276, chars = 15730, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.GardenerLife"] = { lines = 82, chars = 3905, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.Gifting"] = { lines = 634, chars = 27299, first = "--======================================================================", last = "print(\"[Gifting] ready -- opens from the MORE+ menu (Send a Gift)\")" },
	["StarterPlayer.StarterPlayerScripts.GroupBannerClient"] = { lines = 298, chars = 12592, first = "--[[", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.GutSkinClient"] = { lines = 441, chars = 25009, first = "-- ============================================================================", last = "print(\"[GutSkinClient] ready (Skins tab in Stomach menu, equip + rainbow animation)\")" },
	["StarterPlayer.StarterPlayerScripts.HeldItemSync"] = { lines = 120, chars = 5786, first = "--======================================================================", last = "print(\"[HeldItem] client ready -- other players' quest props render on their hands (fishing rod)\")" },
	["StarterPlayer.StarterPlayerScripts.IslandNameTag"] = { lines = 132, chars = 6078, first = "--======================================================================", last = "print(\"[IslandNameTag] ready -- player names tinted by highest island (6 bands, replaces the default plate)\")" },
	["StarterPlayer.StarterPlayerScripts.IslandTaskReward"] = { lines = 405, chars = 17585, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.LandingImpact"] = { lines = 313, chars = 15198, first = "-- ============================================================================================================", last = ":format(MIN_SPEED, MAX_SPEED, STEP_DIST, FOOT_FADE, MAX_PRINTS))" },
	["StarterPlayer.StarterPlayerScripts.MenuBackButton"] = { lines = 361, chars = 16735, first = "--======================================================================", last = "print(\"[MenuBack] ready -- BACK on Rebirth / Rewards / Wormhole / Gift -> MORE+, Daily / Free -> Rewards\")" },
	["StarterPlayer.StarterPlayerScripts.MenuBackdropGuard"] = { lines = 312, chars = 17166, first = "--!nonstrict", last = ".. \" camera; HUD GUIs are never touched, and anything hidden by mistake is restored\")" },
	["StarterPlayer.StarterPlayerScripts.MeteorImpactSound"] = { lines = 43, chars = 2086, first = "--======================================================================", last = "end" },
	["StarterPlayer.StarterPlayerScripts.MeteorUI"] = { lines = 416, chars = 16992, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.MobileTextFit"] = { lines = 67, chars = 3707, first = "-- ===== MOBILE TEXT FIT =====", last = ":format(initial, SKIP_ATTR))" },
	["StarterPlayer.StarterPlayerScripts.MusicClient"] = { lines = 173, chars = 8270, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.MusicDucking"] = { lines = 90, chars = 4175, first = "--======================================================================", last = "applyDuck()" },
	["StarterPlayer.StarterPlayerScripts.NotifyCenter"] = { lines = 445, chars = 19145, first = "--======================================================================", last = "print(\"[NotifyCenter] ready -- HERO lane (top-centre, priority queue + pinned instructions) + SOCIAL lane (top-left)\")" },
	["StarterPlayer.StarterPlayerScripts.NotifyOptIn"] = { lines = 145, chars = 7170, first = "-- ============================================================================================================", last = ":format(MIN_PETS, MIN_MINUTES))" },
	["StarterPlayer.StarterPlayerScripts.NpcGuideArrow"] = { lines = 274, chars = 13627, first = "--======================================================================", last = "print((\"[NpcGuide] ready -- \\xE2\\x96\\xBC over each island's NPC on landing (no ground trail), gone after %ds or on takeoff\"):format(SHOW_SECONDS))" },
	["StarterPlayer.StarterPlayerScripts.NpcLife"] = { lines = 219, chars = 9674, first = "--======================================================================", last = "print((\"[NpcLife] ready -- quest givers turn, breathe, and say hello once (%s to check)\"):format(DEBUG_CMD))" },
	["StarterPlayer.StarterPlayerScripts.NpcWaypointArrow"] = { lines = 153, chars = 7179, first = "--======================================================================", last = "print(\"[NpcArrow] ready -- bouncing marker over the quest giver, on the same rules as the ground trail\")" },
	["StarterPlayer.StarterPlayerScripts.ObjectiveHUD"] = { lines = 366, chars = 18334, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.OfflineEarnings"] = { lines = 188, chars = 9430, first = "-- ============================================================================================", last = "end" },
	["StarterPlayer.StarterPlayerScripts.PetBarn"] = { lines = 1463, chars = 75765, first = "--======================================================================", last = "print(\"[PetBarn] client ready\")" },
	["StarterPlayer.StarterPlayerScripts.PetFollow"] = { lines = 7044, chars = 478394, first = "-- ============================================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.PetRenderGuard"] = { lines = 175, chars = 9223, first = "--!nonstrict", last = "print(\"[PetGuard] watching pet models for stuck reveals and fallback bodies\")" },
	["StarterPlayer.StarterPlayerScripts.PetSkinLook"] = { lines = 505, chars = 23156, first = "-- ============================================================================================================", last = "print(\"[PetSkinLook] renderer ready (\" .. #PetSkins.Order .. \" skins, \" .. #PetTraits.TRAITS .. \" traits)\")" },
	["StarterPlayer.StarterPlayerScripts.RailGuard"] = { lines = 930, chars = 41411, first = "--======================================================================", last = "print(\"[RailGuard] ready -- rail locked to 4 buttons, MORE+ polished 2x2 grid\")" },
	["StarterPlayer.StarterPlayerScripts.RainbowBeamUI"] = { lines = 75, chars = 3298, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.RareAnnounce"] = { lines = 93, chars = 4259, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.RealmPortalsHub"] = { lines = 1523, chars = 77082, first = "--======================================================================", last = "print(\"[RealmPortals] client ready -- hub build, watching for Portal marker blocks\")" },
	["StarterPlayer.StarterPlayerScripts.RebirthClient"] = { lines = 587, chars = 41886, first = "--======================================================================", last = "print(\"[Rebirth] client ready -- panel opens from the REBIRTH side button (_G.toggleRebirth)\")" },
	["StarterPlayer.StarterPlayerScripts.RebirthTag"] = { lines = 55, chars = 2965, first = "-- ============================================================================================", last = "print(\"[RebirthTag] ready -- rebirth level renders above every player's head (attribute-driven)\")" },
	["StarterPlayer.StarterPlayerScripts.RemotePets"] = { lines = 811, chars = 50618, first = "--======================================================================", last = "print(\"[RemotePets] online -- rendering other players' equipped pets (listening on PetEquipBroadcast)\")" },
	["StarterPlayer.StarterPlayerScripts.RewardsClient"] = { lines = 363, chars = 24209, first = "-- ============================================================================", last = "print(\"[RewardsClient] ready (codes, group banner, shared banner scheduler, /friends, /group)\")" },
	["StarterPlayer.StarterPlayerScripts.RewardsHub"] = { lines = 251, chars = 12644, first = "--======================================================================", last = "print(\"[RewardsHub] ready -- one Rewards door, DAILY + FREE inside (_G.toggleRewardsHub)\")" },
	["StarterPlayer.StarterPlayerScripts.RivalCallout"] = { lines = 134, chars = 6313, first = "--======================================================================", last = "print(\"[RivalCallout] ready -- callouts when you pass another player's best height (friends called out by name)\")" },
	["StarterPlayer.StarterPlayerScripts.RocketBuildPreload"] = { lines = 73, chars = 3700, first = "--======================================================================", last = "preloadBuildContent()" },
	["StarterPlayer.StarterPlayerScripts.RocketRideClient"] = { lines = 1359, chars = 67920, first = "--!nonstrict", last = "print(\"[RocketRide] flight deck ready\")" },
	["StarterPlayer.StarterPlayerScripts.RocketSounds"] = { lines = 98, chars = 4500, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.RocketUI"] = { lines = 437, chars = 20267, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.SeasonPass"] = { lines = 400, chars = 24620, first = "--======================================================================", last = "print(\"[SeasonPass] client ready -- light-theme track UI (opens from More+)\")" },
	["StarterPlayer.StarterPlayerScripts.SeasonalPetsChest"] = { lines = 112, chars = 5055, first = "--======================================================================", last = "print(\"[SeasonalChest] box retired -- Seasonal Pets now opens from the Support the Garden chest (tab)\")" },
	["StarterPlayer.StarterPlayerScripts.SecretCave"] = { lines = 3001, chars = 160514, first = "--======================================================================", last = "print(\"[SecretCave] ready -- watching for the 'secretcave' Part; hidden switch opens it, trader waits inside\")" },
	["StarterPlayer.StarterPlayerScripts.SettingsMenu"] = { lines = 698, chars = 34570, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.SfxWiring"] = { lines = 159, chars = 7900, first = "--======================================================================", last = "end" },
	["StarterPlayer.StarterPlayerScripts.ShopClient"] = { lines = 1679, chars = 117772, first = "print(\"SHOPCLIENT STARTED\")", last = "end" },
	["StarterPlayer.StarterPlayerScripts.SkinCrateClient"] = { lines = 2812, chars = 150994, first = "-- ============================================================================================================", last = "#SkinCrates.TOKEN_PACKS .. \" token packs. Open with _G.toggleSkinCrates()\")" },
	["StarterPlayer.StarterPlayerScripts.SkyByAltitude"] = { lines = 417, chars = 21188, first = "-- SkyByAltitude.client.luau  (LocalScript)  -- the sky thins and darkens as you climb.", last = ":format(KEYS[1].y, KEYS[#KEYS].y, #FLEET))" },
	["StarterPlayer.StarterPlayerScripts.SocialRewards"] = { lines = 195, chars = 10966, first = "--======================================================================", last = "print(\"[Social] client ready -- Free Rewards panel (opens from More+)\")" },
	["StarterPlayer.StarterPlayerScripts.TitleTags"] = { lines = 121, chars = 5660, first = "-- ============================================================================================", last = "print(\"[TitleTags] ready -- titles render above every player's head (attribute-driven, no remotes)\")" },
	["StarterPlayer.StarterPlayerScripts.TokenHud"] = { lines = 662, chars = 31952, first = "--======================================================================", last = ".. \"right-aligned to the STATS panel (tap the token pill = Skin Crates)\")" },
	["StarterPlayer.StarterPlayerScripts.TopCenterStack"] = { lines = 114, chars = 5334, first = "-- ============================================================================================================", last = ".. #ORDER .. \" lanes, priority: \" .. table.concat(ORDER, \" > \") .. \")\")" },
	["StarterPlayer.StarterPlayerScripts.TradeRequests"] = { lines = 818, chars = 37214, first = "--!nonstrict", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.VipClient"] = { lines = 51, chars = 2570, first = "-- ============================================================================================================", last = "print(\"[VipClient] ready -- VIP daily stipend banner\")" },
	["StarterPlayer.StarterPlayerScripts.WarpEffect"] = { lines = 358, chars = 13760, first = "--!nonstrict", last = "return WarpEffect" },
	["StarterPlayer.StarterPlayerScripts.WorldClient"] = { lines = 1073, chars = 59870, first = "print(\"WORLDCLIENT STARTED\")", last = "print(\"WORLDCLIENT READY\")" },
	["StarterPlayer.StarterPlayerScripts.WormholeClient"] = { lines = 295, chars = 18909, first = "--[[", last = "print(\"[Wormhole][client] online -- island travel menu + shared WarpEffect cinematic (opens from the WORMHOLE side button)\")" },
}

-- ---- helpers ------------------------------------------------------------------------------------------------

-- Match the normalisation the signatures were built with: CRLF -> LF, then strip trailing blank space.
-- Without this, a trailing newline that Rojo did or did not keep would shift every char count by one.
local function norm(src)
	src = src:gsub("\r\n", "\n"):gsub("\r", "\n")
	return (src:gsub("[\n \t]+$", ""))
end

local function trim(s) return (s:match("^%s*(.-)%s*$")) end

local function sigOf(src)
	src = norm(src)
	local lines = {}
	for line in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
	local first = trim(lines[1] or "")
	local last = ""
	for i = #lines, 1, -1 do
		local t = trim(lines[i])
		if t ~= "" then last = t; break end
	end
	return #lines, #src, first, last
end

local function fullPath(inst)
	local parts, cur = {}, inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(parts, ".")
end

-- ---- collect ------------------------------------------------------------------------------------------------

local groups = {}
for _, inst in ipairs(game:GetDescendants()) do
	if inst:IsA("LuaSourceContainer") then
		local p = fullPath(inst)
		if EXPECTED[p] then
			groups[p] = groups[p] or {}
			table.insert(groups[p], inst)
		end
	end
end

-- ---- report + act -------------------------------------------------------------------------------------------

print("========== DEDUPE SCRIPTS " .. (DRY_RUN and "(DRY RUN -- nothing will be deleted)" or "(LIVE -- DELETING)") .. " ==========")

local dupGroups, deleted, skipped, missing, singles = 0, 0, 0, 0, 0
local sortedPaths = {}
for p in pairs(EXPECTED) do table.insert(sortedPaths, p) end
table.sort(sortedPaths)

for _, path in ipairs(sortedPaths) do
	local list = groups[path]
	local exp = EXPECTED[path]

	if not list then
		missing = missing + 1
		warn(("  MISSING   %s  -- in the project but not in the place (sync it, or it never arrived)"):format(path))
	elseif #list == 1 then
		singles = singles + 1
	else
		dupGroups = dupGroups + 1
		-- score every candidate
		local best, bestScore, tie = nil, -1, false
		local scores = {}
		for _, inst in ipairs(list) do
			local ok, src = pcall(function() return inst.Source end)
			local score = -1
			if ok and type(src) == "string" then
				local nl, nc, f, l = sigOf(src)
				score = 0
				if nl == exp.lines then score = score + 1 end
				if nc == exp.chars then score = score + 1 end
				if f  == exp.first then score = score + 1 end
				if l  == exp.last  then score = score + 1 end
			end
			scores[inst] = score
			if score > bestScore then best, bestScore, tie = inst, score, false
			elseif score == bestScore then tie = true end
		end

		local detail = {}
		for _, inst in ipairs(list) do table.insert(detail, tostring(scores[inst]) .. "/4") end
		print(("  %d copies  %s   scores: %s"):format(#list, path, table.concat(detail, ", ")))

		if bestScore < 0 then
			skipped = skipped + 1
			warn("     SKIPPED -- could not read .Source. Run this from the COMMAND BAR or a plugin, not a Script.")
		elseif tie then
			skipped = skipped + 1
			warn(("     SKIPPED -- %d copies tie at %d/4, so there is no way to tell which is current. Compare them by hand.")
				:format(#list, bestScore))
		elseif bestScore < MIN_SCORE then
			skipped = skipped + 1
			warn(("     SKIPPED -- best match is only %d/4 (need %d). The place may be out of sync with disk; re-sync and retry.")
				:format(bestScore, MIN_SCORE))
		else
			for _, inst in ipairs(list) do
				if inst ~= best then
					if DRY_RUN then
						print(("     would delete the %d/4 copy (keeping the %d/4 one)"):format(scores[inst], bestScore))
					else
						local ok = pcall(function() inst:Destroy() end)
						if ok then
							deleted = deleted + 1
							print(("     DELETED the %d/4 copy (kept the %d/4 one)"):format(scores[inst], bestScore))
						else
							warn("     could not delete a copy (locked?)")
						end
					end
				end
			end
		end
	end
end

print("----------------------------------------------------------------------")
print(("  %d managed script(s): %d clean, %d duplicated, %d missing"):format(#sortedPaths, singles, dupGroups, missing))
if DRY_RUN then
	print(("  DRY RUN -- nothing was deleted. Set DRY_RUN = false and run again."))
else
	print(("  DELETED %d stale copy/copies. Now File > Save, then republish."):format(deleted))
end
if skipped > 0 then
	warn(("  %d group(s) SKIPPED -- see the warnings above; those need a manual look."):format(skipped))
end
print("======================================================================")
