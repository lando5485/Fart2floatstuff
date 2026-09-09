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
	["ReplicatedFirst.LoadingScreen"] = { lines = 2307, chars = 112921, first = "-- ===== FART TO FLOAT \226\128\148 STARTUP LOADING SCREEN =====", last = "end)" },
	["ReplicatedStorage.PhoneHUD"] = { lines = 93, chars = 5119, first = "--[[", last = "return PhoneHUD" },
	["ReplicatedStorage.Shared.BubbleWords"] = { lines = 89, chars = 3775, first = "--======================================================================", last = "return BubbleWords" },
	["ReplicatedStorage.Shared.Constants"] = { lines = 45, chars = 1714, first = "--!nonstrict", last = "return Constants" },
	["ReplicatedStorage.Shared.CosmeticConfig"] = { lines = 161, chars = 10983, first = "--!nonstrict", last = "return CosmeticConfig" },
	["ReplicatedStorage.Shared.CosmeticIcon"] = { lines = 117, chars = 3627, first = "--!nonstrict", last = "return CosmeticIcon" },
	["ReplicatedStorage.Shared.CrateTokens"] = { lines = 178, chars = 10712, first = "--!nonstrict", last = "return CrateTokens" },
	["ReplicatedStorage.Shared.FlightTuning"] = { lines = 200, chars = 9590, first = "--======================================================================", last = "return FlightTuning" },
	["ReplicatedStorage.Shared.Gamepasses"] = { lines = 258, chars = 13643, first = "--!nonstrict", last = "return Gamepasses" },
	["ReplicatedStorage.Shared.GutSkins"] = { lines = 89, chars = 4242, first = "--!strict", last = "return GutSkins" },
	["ReplicatedStorage.Shared.IslandOrder"] = { lines = 80, chars = 3809, first = "--======================================================================", last = "return IslandOrder" },
	["ReplicatedStorage.Shared.PetCollection"] = { lines = 150, chars = 8443, first = "--!nonstrict", last = "return PetCollection" },
	["ReplicatedStorage.Shared.PetRarity"] = { lines = 98, chars = 5315, first = "--!strict", last = "return PetRarity" },
	["ReplicatedStorage.Shared.PetSkins"] = { lines = 172, chars = 11184, first = "--!nonstrict", last = "return PetSkins" },
	["ReplicatedStorage.Shared.PetTraits"] = { lines = 151, chars = 7516, first = "--!nonstrict", last = "return PetTraits" },
	["ReplicatedStorage.Shared.RealmTransfer"] = { lines = 165, chars = 9310, first = "--!nonstrict", last = "return RealmTransfer" },
	["ReplicatedStorage.Shared.Remotes"] = { lines = 61, chars = 1830, first = "--!nonstrict", last = "return Remotes" },
	["ReplicatedStorage.Shared.Sfx"] = { lines = 168, chars = 8418, first = "--======================================================================", last = "return Sfx" },
	["ReplicatedStorage.Shared.SkinCrates"] = { lines = 564, chars = 30081, first = "--!nonstrict", last = "return SkinCrates" },
	["ServerScriptService.AFKTokenFarm"] = { lines = 1467, chars = 86928, first = "--======================================================================", last = "end)" },
	["ServerScriptService.BadgeAwards"] = { lines = 197, chars = 9658, first = "--======================================================================", last = "end" },
	["ServerScriptService.BeamCollision"] = { lines = 101, chars = 4224, first = "--======================================================================", last = "return BeamCollision" },
	["ServerScriptService.BeamEffects"] = { lines = 162, chars = 7248, first = "--======================================================================", last = "return BeamEffects" },
	["ServerScriptService.BeamGeneration"] = { lines = 192, chars = 7921, first = "--======================================================================", last = "return BeamGeneration" },
	["ServerScriptService.BeamKnockback"] = { lines = 80, chars = 3248, first = "--======================================================================", last = "return BeamKnockback" },
	["ServerScriptService.BeamPattern"] = { lines = 106, chars = 4886, first = "--======================================================================", last = "return BeamPattern" },
	["ServerScriptService.BellySystem"] = { lines = 288, chars = 14384, first = "-- ============================================================================", last = "end" },
	["ServerScriptService.BigEventScheduler"] = { lines = 90, chars = 4168, first = "--======================================================================", last = "\9\"s, only one at a time, never the same twice in a row.\")" },
	["ServerScriptService.BlackHoleTeleport"] = { lines = 92, chars = 5996, first = "--======================================================================", last = "\9\", testersOnly=\" .. tostring(SPACE_REALM_TESTERS_ONLY) .. \")\")" },
	["ServerScriptService.BlimpService"] = { lines = 1114, chars = 55407, first = "-- BlimpService.server.lua  (Script)  -- the PLS DONATE-style airship that laps Bean Farm.", last = "\9island.Name, LAP_RADIUS, flyY, LAP_SECONDS, tostring(blimp.ModelStreamingMode)))" },
	["ServerScriptService.BootCheck"] = { lines = 116, chars = 5865, first = "--======================================================================", last = "_G.bootCheckServer = report   -- re-run from the command bar in SERVER context: _G.bootCheckServer()" },
	["ServerScriptService.Campfire"] = { lines = 1104, chars = 59150, first = "--======================================================================", last = "end)" },
	["ServerScriptService.ComebackNudge"] = { lines = 455, chars = 24478, first = "-- ============================================================================================================", last = "end" },
	["ServerScriptService.CommunityGarden"] = { lines = 3260, chars = 211204, first = "--======================================================================", last = "Players.PlayerAdded:Connect(hookGardenChat)" },
	["ServerScriptService.CrateService"] = { lines = 255, chars = 11841, first = "--!nonstrict", last = "end)" },
	["ServerScriptService.DailyTasks"] = { lines = 276, chars = 12993, first = "-- DailyTasks.server.lua  (Script)  -- the daily chore list, and the reason to log in tomorrow.", last = "end" },
	["ServerScriptService.DevArrival"] = { lines = 722, chars = 30660, first = "--[[", last = "end" },
	["ServerScriptService.DevCommands"] = { lines = 243, chars = 13995, first = "--!nonstrict", last = "end" },
	["ServerScriptService.EasterEggManager"] = { lines = 770, chars = 41887, first = "--======================================================================", last = "print(\"[EasterEgg] manager ready (\" .. #EGGS .. \" easter egg(s))\")" },
	["ServerScriptService.FarmerSpawner"] = { lines = 309, chars = 16540, first = "-- ===== FARMER TUTORIAL NPC (spawner) =====", last = "end)" },
	["ServerScriptService.GardenBird"] = { lines = 1018, chars = 60715, first = "--======================================================================", last = "end" },
	["ServerScriptService.GardenFeeding"] = { lines = 306, chars = 16128, first = "-- ============================================================================", last = "print(\"[Feeding] garden feeding ready (cow + pig: grab food box -> feed -> +1 coin)\")" },
	["ServerScriptService.GardenGnomes"] = { lines = 197, chars = 9601, first = "-- ============================================================================================================", last = "end)" },
	["ServerScriptService.GardenerWave"] = { lines = 234, chars = 10917, first = "-- ============================================================================================================", last = "end" },
	["ServerScriptService.Gifting"] = { lines = 265, chars = 13287, first = "--======================================================================", last = "\9MIN_GIFT, MAX_GIFT, COOLDOWN, MAX_PER_SESSION, MAX_MAILBOX))" },
	["ServerScriptService.GutSkinService"] = { lines = 118, chars = 6301, first = "-- ============================================================================", last = "print(\"[GutSkins] service ready (playtime unlocks; EquipGutSkin / GetGutSkins / GutSkinState / GutSkinUnlocked)\")" },
	["ServerScriptService.HeldItemSync"] = { lines = 96, chars = 4903, first = "--======================================================================", last = "\9\"' player attribute, cleared on death/respawn\")" },
	["ServerScriptService.IslandNPCs"] = { lines = 844, chars = 40932, first = "-- ============================================================================================", last = "end)" },
	["ServerScriptService.IslandStreaming"] = { lines = 299, chars = 16250, first = "-- ============================================================================", last = "end)" },
	["ServerScriptService.LateJoinEventSync"] = { lines = 93, chars = 5773, first = "--======================================================================", last = "print(\"[LateJoinEventSync] ready -- late-joiners will be caught up on any in-progress big event\")" },
	["ServerScriptService.LeaderboardService"] = { lines = 1115, chars = 65677, first = "-- ============================================================================================", last = "\9.. \"scrollable; submit on join + autosave + leave\"):format(OG_LIMIT, TOP_N))" },
	["ServerScriptService.MeatballShooter"] = { lines = 131, chars = 6935, first = "-- ============================================================================", last = "end)" },
	["ServerScriptService.MeteorImpact"] = { lines = 457, chars = 19312, first = "--======================================================================", last = "return MeteorImpact" },
	["ServerScriptService.MeteorManager"] = { lines = 380, chars = 19342, first = "--======================================================================", last = "for _, p in ipairs(Players:GetPlayers()) do hookMeteorCmd(p) end" },
	["ServerScriptService.MeteorReward"] = { lines = 179, chars = 6969, first = "--======================================================================", last = "return MeteorReward" },
	["ServerScriptService.MeteorSpawn"] = { lines = 409, chars = 16038, first = "--======================================================================", last = "return MeteorSpawn" },
	["ServerScriptService.MilkCap"] = { lines = 130, chars = 6455, first = "-- ============================================================================", last = "end)" },
	["ServerScriptService.MusicManager"] = { lines = 75, chars = 4328, first = "--======================================================================", last = "print(\"[MusicManager] ducking infrastructure ready (BackgroundMusic group + BigEventActive flag); playback runs client-side in MusicClient\")" },
	["ServerScriptService.PetBarn"] = { lines = 1121, chars = 64939, first = "--======================================================================", last = "end)" },
	["ServerScriptService.PetSystem"] = { lines = 3180, chars = 197340, first = "-- ============================================================================================", last = "print(\"[Pet] PetSystem ready (cosmetic-only)\")" },
	["ServerScriptService.PlanetSelectService"] = { lines = 133, chars = 6554, first = "--======================================================================", last = "print((\"[PlanetSelect] service online (Space Realm place id %d)\"):format(SPACE_REALM_PLACE_ID))" },
	["ServerScriptService.PlayerState"] = { lines = 296, chars = 10085, first = "--!nonstrict", last = "return PlayerState" },
	["ServerScriptService.PlayerStats"] = { lines = 2757, chars = 176463, first = "-- Enable Studio access to DataStores: go to Game Settings > Security >", last = "print(\"DONE\")" },
	["ServerScriptService.PopcornTrees"] = { lines = 186, chars = 10275, first = "-- ============================================================================", last = "end)" },
	["ServerScriptService.RainbowBeamManager"] = { lines = 228, chars = 11172, first = "--======================================================================", last = "-- and the collision loop routes touches to the launch-snapshot rewind.)" },
	["ServerScriptService.RealmPortalsHub"] = { lines = 537, chars = 27431, first = "--======================================================================", last = "\9:format(REALMS.space.placeId, REALMS.dino.placeId, REALMS.candy.placeId))" },
	["ServerScriptService.RealmReturnReceiver"] = { lines = 342, chars = 17045, first = "--======================================================================", last = "print(\"[RealmReturn] ready -- merging state carried home from the other realms\")" },
	["ServerScriptService.RebirthSystem"] = { lines = 245, chars = 12449, first = "--======================================================================", last = "print(\"[Rebirth] system ready -- finish islands + Space + Dino -> rebirth for +coins/speed/luck (REBIRTH side button)\")" },
	["ServerScriptService.RewardsService"] = { lines = 154, chars = 8635, first = "-- ============================================================================", last = "\9Gamepasses.isConfigured(\"VIP\") and \"\" or \" -- VIP id NOT SET, perk inert\"))" },
	["ServerScriptService.RocketEffects"] = { lines = 522, chars = 20387, first = "--======================================================================", last = "return RocketEffects" },
	["ServerScriptService.RocketEventManager"] = { lines = 276, chars = 14752, first = "--======================================================================", last = "-- test hook, it is a way for any other script to launch a rocket by accident.)" },
	["ServerScriptService.RocketLogic"] = { lines = 569, chars = 26019, first = "--======================================================================", last = "return RocketLogic" },
	["ServerScriptService.RocketNPCs"] = { lines = 1388, chars = 70989, first = "--======================================================================", last = "return RocketNPCs" },
	["ServerScriptService.RocketRide"] = { lines = 797, chars = 39831, first = "--!nonstrict", last = "return RocketRide" },
	["ServerScriptService.SeasonPass"] = { lines = 209, chars = 9444, first = "--======================================================================", last = "\9:format(SEASON_ID, #TIERS, TIER_XP, PREMIUM_GAMEPASS_ID))" },
	["ServerScriptService.SecretTrader"] = { lines = 471, chars = 23224, first = "--======================================================================", last = "\9.. \"server-side and never read from the client.\"):format(#PERMANENT, ROTATING_SLOTS, #POOL, RESTOCK_SECONDS))" },
	["ServerScriptService.SecretTreeDoor"] = { lines = 427, chars = 26747, first = "-- ============================================================================", last = "end)" },
	["ServerScriptService.SecurityGuard"] = { lines = 138, chars = 6641, first = "-- ============================================================================", last = "print(\"[SecurityGuard] active (insertion guard + signature sweep; arms in \" .. CONFIG.graceSeconds .. \"s).\")" },
	["ServerScriptService.SecurityWatchdog"] = { lines = 382, chars = 18786, first = "--======================================================================", last = "--======================================================================" },
	["ServerScriptService.SkinCrateService"] = { lines = 1315, chars = 67752, first = "-- ============================================================================================================", last = "\9(SkinCrates.TEST_MODE and \"  [TEST_MODE: token packs credit without Robux]\" or \"\"))" },
	["ServerScriptService.SocialRewards"] = { lines = 106, chars = 4862, first = "--======================================================================", last = "print((\"[Social] rewards ready -- like / favourite / group, +%d pet levels each, one-time\"):format(LEVELS))" },
	["ServerScriptService.SocialStats"] = { lines = 155, chars = 7578, first = "--======================================================================", last = "\9TOTAL_SPECIES, totalSkins))" },
	["ServerScriptService.SquirrelEasterEgg"] = { lines = 566, chars = 33192, first = "--======================================================================", last = "end)" },
	["ServerScriptService.ToasterEasterEgg"] = { lines = 435, chars = 22860, first = "--======================================================================", last = "end)" },
	["ServerScriptService.TradeRequests"] = { lines = 411, chars = 18786, first = "--!nonstrict", last = "print(\"[TradeReq] ready -- offline trade requests by name or friends list (messages only; no item ever moves)\")" },
	["ServerScriptService.VipService"] = { lines = 120, chars = 6308, first = "-- ============================================================================================================", last = "\9Gamepasses.isConfigured(\"VIP\") and \"\" or \" -- VIP id NOT SET, nobody can own it yet\"))" },
	["ServerScriptService.WormholeService"] = { lines = 28, chars = 1644, first = "--======================================================================", last = "print(\"[Wormhole] service ready -- island fast-travel via WormholeWarp (delegates to PlayerStats _G.wormholeWarp)\")" },
	["StarterPlayer.StarterPlayerScripts.AFKFarmClient"] = { lines = 113, chars = 5140, first = "--======================================================================", last = "print(\"[AFKFarm][client] ready -- hook-up, token and unplug banners routed through NotifyCenter\")" },
	["StarterPlayer.StarterPlayerScripts.Achievements"] = { lines = 137, chars = 7118, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.AmbientSmoke"] = { lines = 488, chars = 25394, first = "-- ============================================================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.AmbientWildlife"] = { lines = 753, chars = 42073, first = "-- ============================================================================================================", last = "print(\"[Wildlife] ready -- bugs over the garden AND scattered across Bean Farm, birds circling above it (client-side, no replication)\")" },
	["StarterPlayer.StarterPlayerScripts.AntiIdle"] = { lines = 79, chars = 4360, first = "--======================================================================", last = "\9:format(ONLY_WHILE_FARMING and \" plugged into an AFK farm\" or \"\"))" },
	["StarterPlayer.StarterPlayerScripts.BellyPuff"] = { lines = 105, chars = 4343, first = "-- ============================================================================", last = "print(\"[Belly] client puff active (inflates with gas charge, deflates on release)\")" },
	["StarterPlayer.StarterPlayerScripts.BlackBarKiller"] = { lines = 62, chars = 2832, first = "--======================================================================", last = "print(\"[BlackBarKiller] active -- keeps empty SocialRewards toasts hidden (kills the black bar)\")" },
	["StarterPlayer.StarterPlayerScripts.BlimpRide"] = { lines = 84, chars = 4316, first = "--!nonstrict", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.BootCheck"] = { lines = 170, chars = 9884, first = "--======================================================================", last = "_G.bootCheck = report" },
	["StarterPlayer.StarterPlayerScripts.ButtonTextStyle"] = { lines = 226, chars = 11156, first = "--======================================================================", last = "print(\"[BtnText] label legibility pass active -- cream text, 2px tinted stroke, darkened fills, no twin shadows\")" },
	["StarterPlayer.StarterPlayerScripts.Campfire"] = { lines = 382, chars = 21878, first = "--======================================================================", last = "print(\"[Campfire] client ready -- roasting buttons wired\")" },
	["StarterPlayer.StarterPlayerScripts.CoinMagnet"] = { lines = 124, chars = 6155, first = "-- ============================================================================================================", last = "\9Gamepasses.isConfigured(\"CoinMagnet\") and \"\" or \" -- CoinMagnet id NOT SET, nobody can own it yet\"))" },
	["StarterPlayer.StarterPlayerScripts.CoinPulse"] = { lines = 166, chars = 7850, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.CommunityGarden"] = { lines = 434, chars = 24208, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.CoreClient"] = { lines = 4164, chars = 263319, first = "-- ############################################################################", last = "print(\"FIXED\")" },
	["StarterPlayer.StarterPlayerScripts.CrateClient"] = { lines = 1440, chars = 73269, first = "--!nonstrict", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.DailyTasks"] = { lines = 600, chars = 26275, first = "-- DailyTasks.client.luau  (LocalScript)  -- the daily chore checklist panel.", last = "print(\"[DailyTasks] panel ready -- opens from More+ > Daily Tasks (700x520, same frame as the Shop)\")" },
	["StarterPlayer.StarterPlayerScripts.DevArrivalBanner"] = { lines = 124, chars = 5091, first = "--[[", last = "print(\"[DevArrival] banner client ready -- listening for developer arrivals\")" },
	["StarterPlayer.StarterPlayerScripts.DevAuraFX"] = { lines = 139, chars = 4725, first = "--[[", last = "print(\"[DevAuraFX] ready -- orbit rings render locally for any player tagged \" .. ATTR)" },
	["StarterPlayer.StarterPlayerScripts.EventClient"] = { lines = 2235, chars = 133283, first = "print(\"EVENTCLIENT STARTED\")", last = "print(\"CHUNK 2 DONE\")" },
	["StarterPlayer.StarterPlayerScripts.EventSoundPreload"] = { lines = 51, chars = 2542, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.FarmerTutorial"] = { lines = 109, chars = 5361, first = "-- ===== FARMER TUTORIAL DIALOG (client) =====", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.FirstBuy"] = { lines = 159, chars = 8064, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.FirstPersonMenuMouse"] = { lines = 90, chars = 4419, first = "--======================================================================", last = "print(\"[FirstPersonMenuMouse] loaded -- shops are clickable in first person\")" },
	["StarterPlayer.StarterPlayerScripts.FlightFeedback"] = { lines = 317, chars = 15015, first = "-- ============================================================================================================", last = "print(\"[FlightFeedback] ready -- 'passed another player' callout in the hero banner lane (/passed)\")" },
	["StarterPlayer.StarterPlayerScripts.FoodRealmHud"] = { lines = 735, chars = 38604, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.GardenChestClient"] = { lines = 228, chars = 15213, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.GardenDonationClient"] = { lines = 630, chars = 38473, first = "--======================================================================", last = "print(\"GARDEN DONATE GUI UPDATED\")" },
	["StarterPlayer.StarterPlayerScripts.GardenGuideTrail"] = { lines = 323, chars = 17435, first = "--======================================================================", last = "\9.. \" (island-NPC trail removed; the \\xE2\\x96\\xBC over their head is the only NPC pointer)\")" },
	["StarterPlayer.StarterPlayerScripts.GardenIntro"] = { lines = 1014, chars = 52146, first = "-- ============================================================================", last = "end" },
	["StarterPlayer.StarterPlayerScripts.GardenerChat"] = { lines = 276, chars = 15731, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.GardenerLife"] = { lines = 82, chars = 3906, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.Gifting"] = { lines = 636, chars = 27451, first = "--======================================================================", last = "print(\"[Gifting] ready -- opens from the MORE+ menu (Send a Gift)\")" },
	["StarterPlayer.StarterPlayerScripts.GroupBannerClient"] = { lines = 346, chars = 15456, first = "--[[", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.GutSkinClient"] = { lines = 441, chars = 25010, first = "-- ============================================================================", last = "print(\"[GutSkinClient] ready (Skins tab in Stomach menu, equip + rainbow animation)\")" },
	["StarterPlayer.StarterPlayerScripts.Haptics"] = { lines = 544, chars = 24730, first = "--======================================================================", last = "\9.. \"_G.hapticPulse / hapticLoop / hapticLoopStop / hapticEnabled. Type /haptic on a phone to test.\")" },
	["StarterPlayer.StarterPlayerScripts.HeldItemSync"] = { lines = 120, chars = 5787, first = "--======================================================================", last = "print(\"[HeldItem] client ready -- other players' quest props render on their hands (fishing rod)\")" },
	["StarterPlayer.StarterPlayerScripts.IslandNameTag"] = { lines = 132, chars = 6079, first = "--======================================================================", last = "print(\"[IslandNameTag] ready -- player names tinted by highest island (6 bands, replaces the default plate)\")" },
	["StarterPlayer.StarterPlayerScripts.IslandTaskReward"] = { lines = 405, chars = 17586, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.LandingImpact"] = { lines = 316, chars = 15493, first = "-- ============================================================================================================", last = "\9:format(MIN_SPEED, MAX_SPEED, STEP_DIST, FOOT_FADE, MAX_PRINTS))" },
	["StarterPlayer.StarterPlayerScripts.MenuBackButton"] = { lines = 361, chars = 16736, first = "--======================================================================", last = "print(\"[MenuBack] ready -- BACK on Rebirth / Rewards / Wormhole / Gift -> MORE+, Daily / Free -> Rewards\")" },
	["StarterPlayer.StarterPlayerScripts.MenuBackdropGuard"] = { lines = 332, chars = 18763, first = "--!nonstrict", last = "\9.. \" camera; HUD GUIs are never touched, and anything hidden by mistake is restored\")" },
	["StarterPlayer.StarterPlayerScripts.MeteorImpactSound"] = { lines = 43, chars = 2087, first = "--======================================================================", last = "end" },
	["StarterPlayer.StarterPlayerScripts.MeteorUI"] = { lines = 452, chars = 19588, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.MobileTextFit"] = { lines = 67, chars = 3708, first = "-- ===== MOBILE TEXT FIT =====", last = "\9:format(initial, SKIP_ATTR))" },
	["StarterPlayer.StarterPlayerScripts.MusicClient"] = { lines = 211, chars = 10479, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.MusicDucking"] = { lines = 90, chars = 4176, first = "--======================================================================", last = "applyDuck()" },
	["StarterPlayer.StarterPlayerScripts.NotifyCenter"] = { lines = 803, chars = 37584, first = "--======================================================================", last = "\9\"equal fires queue in order -- never overlapping, never stacked.\")" },
	["StarterPlayer.StarterPlayerScripts.NotifyOptIn"] = { lines = 145, chars = 7171, first = "-- ============================================================================================================", last = "\9:format(MIN_PETS, MIN_MINUTES))" },
	["StarterPlayer.StarterPlayerScripts.NpcGuideArrow"] = { lines = 290, chars = 14693, first = "--======================================================================", last = "print((\"[NpcGuide] ready -- \\xE2\\x96\\xBC over each island's NPC on landing (no ground trail), gone after %ds or on takeoff\"):format(SHOW_SECONDS))" },
	["StarterPlayer.StarterPlayerScripts.NpcLife"] = { lines = 219, chars = 9675, first = "--======================================================================", last = "print((\"[NpcLife] ready -- quest givers turn, breathe, and say hello once (%s to check)\"):format(DEBUG_CMD))" },
	["StarterPlayer.StarterPlayerScripts.NpcWaypointArrow"] = { lines = 190, chars = 9790, first = "--======================================================================", last = "\9\"(hidden for the duration of a thunderstorm, restored when it ends)\")" },
	["StarterPlayer.StarterPlayerScripts.ObjectiveHUD"] = { lines = 365, chars = 20398, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.OfflineEarnings"] = { lines = 188, chars = 9431, first = "-- ============================================================================================", last = "end" },
	["StarterPlayer.StarterPlayerScripts.PetBarn"] = { lines = 1463, chars = 75766, first = "--======================================================================", last = "print(\"[PetBarn] client ready\")" },
	["StarterPlayer.StarterPlayerScripts.PetFollow"] = { lines = 7327, chars = 498521, first = "-- ============================================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.PetRenderGuard"] = { lines = 175, chars = 9224, first = "--!nonstrict", last = "print(\"[PetGuard] watching pet models for stuck reveals and fallback bodies\")" },
	["StarterPlayer.StarterPlayerScripts.PetSkinLook"] = { lines = 505, chars = 23260, first = "-- ============================================================================================================", last = "print(\"[PetSkinLook] renderer ready (\" .. #PetSkins.Order .. \" skins, \" .. #PetTraits.TRAITS .. \" traits)\")" },
	["StarterPlayer.StarterPlayerScripts.RailGuard"] = { lines = 930, chars = 41412, first = "--======================================================================", last = "print(\"[RailGuard] ready -- rail locked to 4 buttons, MORE+ polished 2x2 grid\")" },
	["StarterPlayer.StarterPlayerScripts.RainbowBeamUI"] = { lines = 76, chars = 3377, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.RareAnnounce"] = { lines = 93, chars = 4260, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.RealmPortalsHub"] = { lines = 1616, chars = 83028, first = "--======================================================================", last = "print(\"[RealmPortals] client ready -- hub build, watching for Portal marker blocks\")" },
	["StarterPlayer.StarterPlayerScripts.RebirthClient"] = { lines = 615, chars = 43595, first = "--======================================================================", last = "print(\"[Rebirth] client ready -- panel opens from the REBIRTH side button (_G.toggleRebirth)\")" },
	["StarterPlayer.StarterPlayerScripts.RebirthTag"] = { lines = 55, chars = 2966, first = "-- ============================================================================================", last = "print(\"[RebirthTag] ready -- rebirth level renders above every player's head (attribute-driven)\")" },
	["StarterPlayer.StarterPlayerScripts.RemotePets"] = { lines = 811, chars = 50636, first = "--======================================================================", last = "print(\"[RemotePets] online -- rendering other players' equipped pets (listening on PetEquipBroadcast)\")" },
	["StarterPlayer.StarterPlayerScripts.RewardsClient"] = { lines = 404, chars = 26793, first = "-- ============================================================================", last = "print(\"[RewardsClient] ready (codes, group banner, wormhole reminder 3min-then-10min, shared banner scheduler, /friends, /group)\")" },
	["StarterPlayer.StarterPlayerScripts.RewardsHub"] = { lines = 251, chars = 12645, first = "--======================================================================", last = "print(\"[RewardsHub] ready -- one Rewards door, DAILY + FREE inside (_G.toggleRewardsHub)\")" },
	["StarterPlayer.StarterPlayerScripts.RivalCallout"] = { lines = 141, chars = 6805, first = "--======================================================================", last = "print(\"[RivalCallout] ready -- callouts when you pass another player's best height (friends called out by name)\")" },
	["StarterPlayer.StarterPlayerScripts.RocketBuildPreload"] = { lines = 73, chars = 3701, first = "--======================================================================", last = "preloadBuildContent()" },
	["StarterPlayer.StarterPlayerScripts.RocketRideClient"] = { lines = 1359, chars = 67921, first = "--!nonstrict", last = "print(\"[RocketRide] flight deck ready\")" },
	["StarterPlayer.StarterPlayerScripts.RocketSounds"] = { lines = 98, chars = 4501, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.RocketUI"] = { lines = 450, chars = 21259, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.SeasonPass"] = { lines = 400, chars = 24621, first = "--======================================================================", last = "print(\"[SeasonPass] client ready -- light-theme track UI (opens from More+)\")" },
	["StarterPlayer.StarterPlayerScripts.SeasonalPetsChest"] = { lines = 112, chars = 5056, first = "--======================================================================", last = "print(\"[SeasonalChest] box retired -- Seasonal Pets now opens from the Support the Garden chest (tab)\")" },
	["StarterPlayer.StarterPlayerScripts.SecretCave"] = { lines = 3532, chars = 190185, first = "--======================================================================", last = "print(\"[SecretCave] ready -- watching for the 'secretcave' Part; hidden switch opens it, trader waits inside\")" },
	["StarterPlayer.StarterPlayerScripts.SettingsMenu"] = { lines = 716, chars = 35528, first = "--======================================================================", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.SfxWiring"] = { lines = 159, chars = 7901, first = "--======================================================================", last = "end" },
	["StarterPlayer.StarterPlayerScripts.ShopClient"] = { lines = 1718, chars = 120202, first = "print(\"SHOPCLIENT STARTED\")", last = "end" },
	["StarterPlayer.StarterPlayerScripts.SkinCrateClient"] = { lines = 2878, chars = 155314, first = "-- ============================================================================================================", last = "\9#SkinCrates.TOKEN_PACKS .. \" token packs. Open with _G.toggleSkinCrates()\")" },
	["StarterPlayer.StarterPlayerScripts.SkyByAltitude"] = { lines = 417, chars = 21189, first = "-- SkyByAltitude.client.luau  (LocalScript)  -- the sky thins and darkens as you climb.", last = "\9:format(KEYS[1].y, KEYS[#KEYS].y, #FLEET))" },
	["StarterPlayer.StarterPlayerScripts.SocialRewards"] = { lines = 195, chars = 10967, first = "--======================================================================", last = "print(\"[Social] client ready -- Free Rewards panel (opens from More+)\")" },
	["StarterPlayer.StarterPlayerScripts.TitleTags"] = { lines = 121, chars = 5661, first = "-- ============================================================================================", last = "print(\"[TitleTags] ready -- titles render above every player's head (attribute-driven, no remotes)\")" },
	["StarterPlayer.StarterPlayerScripts.TokenHud"] = { lines = 677, chars = 32907, first = "--======================================================================", last = "\9.. \"right-aligned to the STATS panel (tap the token pill = Skin Crates, tap the coin pill = Coin Shop)\")" },
	["StarterPlayer.StarterPlayerScripts.TopCenterStack"] = { lines = 114, chars = 5335, first = "-- ============================================================================================================", last = "\9.. #ORDER .. \" lanes, priority: \" .. table.concat(ORDER, \" > \") .. \")\")" },
	["StarterPlayer.StarterPlayerScripts.TradeRequests"] = { lines = 820, chars = 37357, first = "--!nonstrict", last = "end)" },
	["StarterPlayer.StarterPlayerScripts.UiHaptics"] = { lines = 71, chars = 3801, first = "--======================================================================", last = "print(\"[UiHaptics] ready -- every GuiButton under PlayerGui ticks on press (backdrops and NoHaptic skipped)\")" },
	["StarterPlayer.StarterPlayerScripts.VipClient"] = { lines = 51, chars = 2571, first = "-- ============================================================================================================", last = "print(\"[VipClient] ready -- VIP daily stipend banner\")" },
	["StarterPlayer.StarterPlayerScripts.WarpEffect"] = { lines = 358, chars = 13761, first = "--!nonstrict", last = "return WarpEffect" },
	["StarterPlayer.StarterPlayerScripts.WorldClient"] = { lines = 1124, chars = 62393, first = "print(\"WORLDCLIENT STARTED\")", last = "print(\"WORLDCLIENT READY\")" },
	["StarterPlayer.StarterPlayerScripts.WormholeClient"] = { lines = 385, chars = 23189, first = "--[[", last = "print(\"[Wormhole][client] online -- island travel menu + shared WarpEffect cinematic (opens from the WORMHOLE side button)\")" },
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
