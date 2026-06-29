-- Enable Studio access to DataStores: go to Game Settings > Security >
-- Enable Studio Access to API Services to fix DataStore errors in Studio
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
-- (Daily Rewards removed: rewardStore / DAILY_REWARDS / claim logic deleted.)

-- HOLD players on join: no character auto-spawns, so nothing falls/moves while the loading screen +
-- island-select menu are up. The player is spawned manually onto their chosen island (SelectIslandEvent).
Players.CharacterAutoLoads = false

local function getOrCreate(parent, className, name)
	local obj = parent:FindFirstChild(name)
	if not obj then obj = Instance.new(className); obj.Name = name; obj.Parent = parent end
	return obj
end

local BuyFoodEvent      = getOrCreate(RS, "RemoteEvent", "BuyFoodEvent")
local RegenEvent        = getOrCreate(RS, "RemoteEvent", "RegenEvent")
local CoinEvent         = getOrCreate(RS, "RemoteEvent", "CoinEvent")
local SkipIslandEvent   = getOrCreate(RS, "RemoteEvent", "SkipIslandEvent")
local UnlockIslandEvent = getOrCreate(RS, "RemoteEvent", "IslandUnlockEvent")
local AnnouncementEvent = getOrCreate(RS, "RemoteEvent", "AnnouncementEvent")
local ServerEventNotify = getOrCreate(RS, "RemoteEvent", "ServerEventNotify")
local StomachFullEvent  = getOrCreate(RS, "RemoteEvent", "StomachFullEvent")
local BuyStomachEvent   = getOrCreate(RS, "RemoteEvent", "BuyStomachEvent")
local StomachUpdateEvent= getOrCreate(RS, "RemoteEvent", "StomachUpdateEvent")
local LandingEvent      = getOrCreate(RS, "RemoteEvent", "LandingEvent")
local ReturnToIslandEvent = getOrCreate(RS, "RemoteEvent", "ReturnToIslandEvent")
local WelcomeEvent      = getOrCreate(RS, "RemoteEvent", "WelcomeEvent") -- personal "You reached [Island]!" to the lander only
-- ON-JOIN STATE RESTORE: the client fires this AFTER its HUD + RemoteEvent handlers are built, asking
-- the server to (re)send its saved state (gut label + forever gamepasses). This handshake makes the
-- restore reliable on slow-loading mobile/console clients (no dependence on join-time push timing).
local RequestPlayerState = getOrCreate(RS, "RemoteEvent", "RequestPlayerState")
local SelectIslandEvent = getOrCreate(RS, "RemoteEvent", "SelectIslandEvent") -- client picks a spawn island from the loading-screen menu
local GoToIsland1Event  = getOrCreate(RS, "RemoteEvent", "GoToIsland1Event") -- rocket-event "Go to Island 1" teleport button
-- ONE-TIME GARDEN INTRO CINEMATIC: server tells the client to PLAY the cutscene (fired when a player who
-- hasn't SeenGardenIntro selects island 1); the client fires _Done back when it finishes so we set+save the flag.
local GardenIntroEvent     = getOrCreate(RS, "RemoteEvent", "GardenIntroEvent")     -- server -> client: play the cinematic now
local GardenIntroDoneEvent = getOrCreate(RS, "RemoteEvent", "GardenIntroDoneEvent") -- client -> server: cinematic finished, set the seen flag

local ISLAND_DISPLAY_NAMES = {
	"Bean Farm","Broccoli Bluff","Cabbage Cliffs","Turnip Tranquil",
	"Coconut Cove","Bread Board","Pasta Peak","Popcorn Pinnacle",
	"Milk Marsh","Butter Swamp","Ice Cream Isle","Burger Bluff",
	"Burrito Barrens","Pizza Palms"
}

-- price = round(power * (0.8 + (island - 1) / 13 * 2.2))  -- cheap early islands, expensive late
local foods = {
	{name="Beans",    price=5,    power=8,   island=1},
	{name="Broccoli", price=24,   power=25,  island=2},
	{name="Cabbage",  price=85,   power=45,  island=3},
	{name="Turnips",  price=94,   power=70,  island=4},
	{name="Coconuts", price=142,  power=100, island=5},
	{name="Bread",    price=138,  power=140, island=6},
	{name="Pasta",    price=202,  power=185, island=7},
	{name="Popcorn",  price=600,  power=240, island=8},
	{name="Milk",     price=500,  power=300, island=9},
	{name="Butter",   price=400,  power=370, island=10},
	{name="IceCream", price=560,  power=450, island=11},
	{name="Burger",   price=405,  power=540, island=12},
	{name="Burrito",  price=700,  power=640, island=13},
	{name="Pizza",    price=518,  power=750, island=14},
}

-- getMaxHeight(maxPower) = 50 + maxPower*14. Iron is the top of the free path and
-- reaches island 14; Infinite is a Robux-only premium gut that flies the whole map.
local stomachTiers = {
	{name="Tiny Gut",     maxPower=100,  cost=0,      robux=false},
	{name="Small Gut",    maxPower=182,  cost=1600,   robux=false},
	{name="Medium Gut",   maxPower=520,  cost=3000,   robux=false},
	{name="Large Gut",    maxPower=1075, cost=5200,   robux=false},
	{name="XL Gut",       maxPower=2146, cost=8000,   robux=false},
	{name="Iron Gut",     maxPower=3218, cost=11000,  robux=false},
	{name="Infinite Gut", maxPower=9999, cost=499,    robux=true},
}

local ISLAND_NAMES = {
	"Island_1_BeanFarm","Island_2_BroccoliBluff","Island_3_CabbageCliffs",
	"Island_4_TurnipTranquil","Island_5_CoconutCove","Island_6_BreadBoard",
	"Island_7_PastaPeak","Island_8_PopcornPinnacle","Island_9_MilkMarsh",
	"Island_10_ButterSwamp","Island_11_IceCreamIsle","Island_12_BurgerBluff",
	"Island_13_BurritoBarrens","Island_14_PizzaPalms"
}

local ISLAND_POSITIONS = {
	{x=0,    y=150,   z=0},   {x=120,  y=790,   z=60},   {x=-160, y=1680,  z=100},
	{x=180,  y=2480,  z=-120}, {x=-200, y=3580,  z=160},  {x=220,  y=4820,  z=-180},
	{x=-240, y=6460,  z=200},  {x=260,  y=8202,  z=-220}, {x=-280, y=9732,  z=240},
	{x=300,  y=11978, z=-260}, {x=-320, y=14194, z=280},  {x=340,  y=17138, z=-300},
	{x=-360, y=20206, z=320},  {x=380,  y=24017, z=-340},
}

-- PURE VISUAL Y-axis rotation per island (degrees), applied about the island's CENTER
-- AFTER it's positioned -- so the WHOLE model (stand, shop, paths, props, decorations,
-- any child NPCs) spins together and stays aligned, with NO change to height or position.
-- A Y rotation never changes any part's Y, so heights are untouched. Negative degrees =
-- CLOCKWISE viewed from above (Roblox +Y rotation is counter-clockwise from the top).
-- Stand detection runs AFTER this, so the stand/shop are found at their rotated spots and
-- still work. [3]=Cabbage Cliffs 180, [5]=Coconut Cove 180, [7]=Pasta Peak 90 clockwise.
local ISLAND_ROTATIONS = {
	[3] = 180,   -- Cabbage Cliffs: 180 around Y
	[5] = 180,   -- Coconut Cove: 180 around Y
	[7] = -90,   -- Pasta Peak: 90 CLOCKWISE around Y (top-down "3 -> 6 on a clock")
}

local GAMEPASS_IDS = {TwoXForever=1862015450, GlitterTrail=1859714979, InfiniteGut=1860686821}

-- [STOMACH RESET] \xE2\x9A\xA0 TEMPORARY: while TRUE, EVERY player is forced to the BASE starting gut -- ALL gut/stomach
-- upgrades read as UN-OWNED: Infinite Gut never auto-applies on join OR purchase (applyInfiniteGut no-ops), a stored
-- 9999 / any saved tier is forced back to the base StomachMax on load, and HasInfiniteGut stays false so the meter
-- never locks full. The real on-disk StomachMax is PRESERVED through save (the save writes back the loaded disk value,
-- NOT the forced base), so flipping this FALSE cleanly restores everyone's real gut (Infinite Gut owners also re-get
-- it live from UserOwnsGamePassAsync). Players can still buy coin tiers via BuyStomachEvent. Set FALSE to restore.
local FORCE_BASE_STOMACH = true
local loadedStomachMax = {} -- [player] = the StomachMax value read from disk on load (preserved through save while forced)

-- INFINITE / UNLIMITED GUT gamepass (1860686821): applies the Infinite Gut tier (StomachMax = 9999, the
-- top tier — no practical power cap, so the "stomach full" check effectively never fires). Used BOTH on
-- a fresh purchase (PromptGamePassPurchaseFinished) AND, since it's a forever pass, on every join when
-- UserOwnsGamePassAsync is true. Same mechanism a normal gut buy uses (set StomachMax, carry the power
-- already in the tank, notify the client) so the gut label + meter capacity stay correct. Idempotent:
-- if they're already at Infinite Gut it no-ops. Touches ONLY this player's stomach — no coins, no other
-- tiers, no other system.
local INFINITE_GUT_MAX = 9999
local function applyInfiniteGut(player)
	if not player then return end
	if FORCE_BASE_STOMACH then print("[STOMACH RESET] applyInfiniteGut SKIPPED for "..player.Name.." (FORCE_BASE_STOMACH on -- gut stays base)"); return end -- never grant the Infinite Gut tier while the reset is on (join or purchase)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local sm = ls:FindFirstChild("StomachMax"); if not sm then return end
	-- Flag ownership FIRST. The client reads HasInfiniteGut to lock the fart meter full (never drains), so
	-- every owner must be flagged on join/purchase regardless of their saved gut (a returning owner loads with
	-- StomachMax already at 9999). applyInfiniteGut is only ever called for actual owners (join
	-- UserOwnsGamePassAsync + purchase), so non-owners never get the flag and are entirely unaffected.
	player:SetAttribute("HasInfiniteGut", true)
	-- Promote the gut to the Infinite tier if it isn't already (only the MAX grows). Notify the client of the
	-- new gut label ONLY when it actually changes, so already-Infinite returning owners aren't re-notified.
	if sm.Value < INFINITE_GUT_MAX then
		sm.Value = INFINITE_GUT_MAX
		local nameStr = "Infinite Gut"
		for _, t in ipairs(stomachTiers) do if t.maxPower == INFINITE_GUT_MAX then nameStr = t.name; break end end
		pcall(function() StomachUpdateEvent:FireClient(player, INFINITE_GUT_MAX, nameStr) end)
	end
	-- INSTANT-FULL METER (on PURCHASE and on JOIN): Infinite Gut's tank is ALWAYS full, so jump CurrentPower
	-- straight to the gut max regardless of what it was — even from 0 power / 0 coins (no clamp to the old
	-- fill, no early-return). Setting the SERVER CurrentPower makes it AGREE with the client's full/never-drain
	-- meter and stick through the decrease-only landing sync (same lesson as the recharge / bird-nuke fixes).
	-- RegenEvent shows the client bar full IMMEDIATELY. Runs for returning owners too, so they top to full on spawn.
	local cp = ls:FindFirstChild("CurrentPower")
	if cp then cp.Value = sm.Value end -- full tank = StomachMax (= INFINITE_GUT_MAX)
	pcall(function() RegenEvent:FireClient(player, 0, sm.Value, sm.Value) end)
	print("INFINITE GUT applied to "..player.Name.." (StomachMax="..sm.Value..", CurrentPower=FULL)")
end
local PRODUCT_IDS  = {TwoXOneHour=3600302990, MidAirRecharge=3600303163, SkipIsland=3600303265, BirdNuke=3600303082}
-- 2x Fart Power pass/product: with it active, each food is worth this multiple of its power as
-- REAL flight fuel, and the effective stomach tank grows by the same multiple. (Client mirrors
-- this constant in CoreClient.client.lua for the gas-meter / flight math.)
local POWER_PASS_MULT = 1.4
-- [TESTING] Flip back to false to re-enable the 2x boost in Studio. When true AND running in Studio,
-- the has2x check is forced false so food gives normal 1x power (ignores HasTwoXForever / TwoXHourExpiry).
-- The LIVE game is unaffected (IsStudio() is false there).
local DISABLE_2X = true
-- ============================================================================================
-- [BALANCE TESTING] MASTER NO-PERKS SWITCH. While TRUE, the game ignores ALL gamepass/product
-- perks even if the player owns them, so the playthrough reflects a brand-new player with no perks:
--   • 2x Fart Power (TwoXForever gamepass AND the 2x 1-hour product) -> food gives NORMAL 1x power
--     (e.g. Beans = 8, not 11). Both the server power math and the client's gas/flight math follow.
--   • Glitter Trail -> off (client gets an all-false gamepass state).
--   • Skip Island -> the effect is ignored (no skipping).
--   • Mid-Air Recharge -> n/a (it has no active flight effect in the current code).
-- Works in Studio AND the live game. Flip to FALSE to restore all perks after the test.
-- (This supersedes DISABLE_2X above, which was Studio-only.)
-- ============================================================================================
local DISABLE_PERKS_FOR_BALANCE = false
-- [NOSAVE TEST] \xE2\x9A\xA0 TEMPORARY -- REMOVE BEFORE LAUNCH. While TRUE, the "2x Fart Power Forever" gamepass (TwoXForever)
-- reads as NOT owned for EVERY player regardless of saved data / actual ownership: the join ownership check is forced
-- false, HasTwoXForever is cleared, a fresh purchase won't grant it, and the has2x effect is forced off -- so NO player
-- gets the 2x power boost for now. (Targets ONLY the 2x pass; Glitter/Skip/Infinite Gut are untouched.) Set FALSE to restore.
local FORCE_NO_2X = true
if FORCE_NO_2X then print("[NOSAVE TEST] 2xFart forced un-owned.") end
-- [BALANCE TESTING] While TRUE, NO random server-wide events fire (FART_STORM, COIN_RUSH, LOW_GRAVITY,
-- POWER_SURGE, RING_FEVER, THUNDERSTORM, WINDSTORM). Set to false to re-enable random events later.
-- (Ambient bird swarms are gated by a matching DISABLE_EVENTS flag in EventClient.client.lua — keep
-- the two in sync. The Bird Nuke PRODUCT is unaffected and still works.)
local DISABLE_EVENTS = false
-- (Daily Rewards feature removed entirely -- reward tables, claim logic, and the DailyRewards_v1 store deleted.)
local playerCoinAccum = {}
local GamepassEvent = nil
task.spawn(function() GamepassEvent = RS:WaitForChild("GamepassEvent", 10) end)
local BirdNukeEvent = nil
task.spawn(function() BirdNukeEvent = RS:WaitForChild("BirdNukeEvent", 10) end)

-- DataStore init is after island task.spawns are queued so islands set up even if DataStore fails
local playerDataStore = nil
pcall(function()
	local DataStoreService = game:GetService("DataStoreService")
	playerDataStore = DataStoreService:GetDataStore("PlayerData_v1")
end)
print("NOTE: Enable Studio API Access in")
print("Game Settings > Security for")
print("DataStore to work in Studio")

-- ===== PLAYER DATA PERSISTENCE (DataStore "PlayerData_v1", keyed by UserId) =====
-- Persists coins, gut tier (StomachMax), island/unlock progression (Island) and home base
-- (highestIslandReached). Gamepass ownership is NOT saved — it's read live each join via
-- UserOwnsGamePassAsync. All DataStore calls are pcall'd, and a player is NEVER saved unless their
-- load succeeded (dataLoaded), so a failed load can't overwrite real progress with defaults.
local highestIslandReached = {}   -- [player] = highest island reached (home base). Declared here so save/load can use it.
-- Per-player forever-gamepass ownership, computed once on join (NEVER saved) so the on-ready handshake
-- can re-send it reliably. gamepassReady flips true once the (async) ownership check has finished.
local gamepassState = {}          -- [player] = { twoXForever=bool, glitterTrail=bool }
local gamepassReady = {}          -- [player] = true once the on-join ownership check completed
-- PERMANENT TEST ACCOUNT: this UserId never loads/saves (always a brand-new player every join).
local TEST_ACCOUNT_USERID = 1086836724  -- lando5485
-- \xE2\x9A\xA0 TEST: shared allow-list for ALL test/debug features (test chat commands AND the island-select
-- all-islands-unlock below). Matched by USERNAME (case-insensitive). Defined early so every handler can use
-- it. REMOVE BEFORE LAUNCH.
local ALLOWED_TEST_USERS = { ["lando5485"] = true, ["broskie310111"] = true, ["itsmaddmax2"] = true } -- \xE2\x9A\xA0 REMOVE BEFORE LAUNCH
local function isAllowedTestUser(player) -- \xE2\x9A\xA0 TEST: shared gate for all test/debug features. REMOVE BEFORE LAUNCH.
	return ALLOWED_TEST_USERS[string.lower(player.Name)] == true
end
_G.isAllowedTestUser = isAllowedTestUser -- \xE2\x9A\xA0 TEST: shared with PetSystem (pet-skip test path). REMOVE BEFORE LAUNCH.
-- =====================================================================================================
-- \xE2\x9A\xA0 FRESH PLAYER TEST OVERRIDE (Broskie310111) -- TEMPORARY. SET false / DELETE THIS BLOCK BEFORE LAUNCH.
-- When FRESH_PLAYER_TEST is true, the player whose UserId == FRESH_PLAYER_USERID loads as a BRAND-NEW
-- player (new-player DEFAULTS below), ALL their gamepasses are VOIDED for the session, and NOTHING is
-- saved for them -- so their REAL data on disk is left untouched and is restored simply by flipping this
-- flag back to false. (Hooks live in fetchPlayerData, savePlayerData, and the join gamepass loop.)
--
-- New-player DEFAULTS a fresh account gets (from DEFAULT_COINS/STOMACH/ISLAND + the load path below):
--   coins = 25, StomachMax = 100 (Tiny Gut), Island = 1, CurrentPower/fartMeter = 0,
--   TotalFartPower = 0, TotalCoinsEarned = 0, HighestIsland = 1, no gamepasses.
--
-- ===== BROSKIE RESTORE DATA (current saved state on disk, recorded BEFORE the override) =====
--   UserId / DataStore key (PlayerData_v1): 1418148401
--   From F9 save logs:  coins = 2,  highestIsland = 13,  stomachMax = 9999 (Infinite Gut tier),  saveVersion = 4
--   Owned gamepasses (inferred from stomachMax 9999): Infinite Gut; plus whatever else UserOwnsGamePassAsync reports live.
--   NOT captured in the logs (island, totalFartPower, totalCoinsEarned, fartMeter): these are UNCHANGED on
--   disk -- because saving is DISABLED for this user in fresh mode, the real save is never overwritten, so
--   the full record (including these fields) survives intact. RESTORE = just set FRESH_PLAYER_TEST = false.
-- =====================================================================================================
local FRESH_PLAYER_TEST = true          -- \xE2\x9A\xA0 TEST: forces Broskie310111 to load as a fresh new player + void gamepasses. SET false / REMOVE BEFORE LAUNCH.
local FRESH_PLAYER_USERID = 1418148401  -- Broskie310111 (DataStore PlayerData_v1 key)
-- \xE2\x9A\xA0 SPAWN-AT-PIZZA-PALMS TEST (Broskie310111) -- TEMPORARY. SET false / REMOVE BEFORE LAUNCH.
-- When true, this SUPERSEDES FRESH_PLAYER_TEST for Broskie's account: instead of loading island-1 fresh
-- defaults, they load with Island 14 (Pizza Palms) unlocked + huge test gas/stomach so they can fly up
-- to the black hole. Saving stays DISABLED for this user (real data preserved), exactly like fresh mode.
-- To revert: set this false (back to fresh mode) or set BOTH test flags false (back to real state).
local SPAWN_AT_PIZZA_PALMS_TEST = true  -- \xE2\x9A\xA0 TEST: spawns Broskie310111 on Island 14 to view the black hole. SET false / REMOVE BEFORE LAUNCH.
-- =====================================================================================================
-- \xE2\x9A\xA0 FRESH PLAYER 2 TEST OVERRIDE (itsmaddmax2) -- TEMPORARY, INDEPENDENT of Broskie's overrides above.
-- When FRESH_PLAYER_2_TEST is true AND the joining player is itsmaddmax2 (matched by userId OR name), they
-- load brand-new-player DEFAULTS every join, ALL their gamepasses are VOIDED for the session, and NOTHING
-- is saved for them -- so they always start over and their real data (if any) is preserved. Only affects
-- itsmaddmax2; Broskie's account is matched by its own userId, so the two never interfere.
local FRESH_PLAYER_2_TEST   = true            -- \xE2\x9A\xA0 TEST: itsmaddmax2 always loads as a fresh new player. REMOVE BEFORE LAUNCH.
local FRESH_PLAYER_2_USERID = 0               -- \xE2\x9A\xA0 REPLACE with itsmaddmax2's real userId (printed to F9 on their first join)
local FRESH_PLAYER_2_NAME   = "itsmaddmax2"   -- name fallback so it works before the userId is filled in
-- True if `player` is the itsmaddmax2 fresh-player test account (by userId OR name). Independent of Broskie.
local function isFreshPlayer2(player)
	return FRESH_PLAYER_2_TEST and (player.UserId == FRESH_PLAYER_2_USERID or player.Name == FRESH_PLAYER_2_NAME)
end
-- FART-METER PERSISTENCE: lastMeter = the player's last-known live meter (snapshotted on meter changes,
-- so a respawn/cleanup that zeros CurrentPower can't make us SAVE a stale 0). joinRestoreMeter = the
-- saved meter to re-apply AFTER the player's first spawn settles (the spawn's onLand zeros CurrentPower,
-- which is decrease-only, so the load must be re-applied server-side post-spawn).
local lastMeter = {}              -- [player] = last-known meter to SAVE
local joinRestoreMeter = {}       -- [player] = saved meter to RESTORE after first spawn
-- PET OWNERSHIP (cosmetic). Persisted in PlayerData_v1 under saved.ownedPets and shared with
-- PetSystem.server.lua (which reads/writes this table on claim); PlayerStats just persists it.
-- e.g. _G.playerOwnedPets[player] = { BroccoliPet = true }. Loaded into here on join, saved on save.
_G.playerOwnedPets = _G.playerOwnedPets or {}
-- Equipped-pet choice (cosmetic, additive). Persisted under saved.equippedPet; shared with PetSystem.
_G.playerEquippedPet = _G.playerEquippedPet or {}
-- GUT SKINS (cosmetic, additive). owned = { Default=true, ... }; equipped = skin id. Shared with GutSkinService;
-- PlayerStats just persists them (saved.ownedGutSkins / saved.equippedGutSkin).
_G.playerOwnedGutSkins = _G.playerOwnedGutSkins or {}
_G.playerEquippedGutSkin = _G.playerEquippedGutSkin or {}
-- TOTAL cumulative playtime in SECONDS (all sessions). GutSkinService increments + auto-grants playtime skins;
-- PlayerStats just persists it (saved.playtimeSeconds). Single source of truth lives on the server.
_G.playerPlaytimeSec = _G.playerPlaytimeSec or {}
-- Discovered pet QUESTS (cosmetic, additive). Persisted under saved.discoveredQuests; shared with PetSystem.
_G.playerDiscoveredQuests = _G.playerDiscoveredQuests or {}
-- PERMANENT "ever completed pet quest X" flags (additive). Persisted under saved.everCompletedQuests; shared
-- with PetSystem. Used ONLY to gate the first-time-only rare roll (separate from current ownership). Missing = never completed.
_G.playerEverCompletedQuests = _G.playerEverCompletedQuests or {}
local DEFAULT_COINS, DEFAULT_STOMACH, DEFAULT_ISLAND = 25, 100, 1 -- new player: 25 coins, Tiny gut (100, base StomachMax), island 1
print("[RESET] new-player defaults: coins=25, stomach=base, gamepasses=owned-only, islands=locked-to-1, test grants removed.")
-- SAVE RECORD VERSION. ONE-TIME WIPE: bumped to 4. On load, any record whose saveVersion ~= SAVE_VERSION
-- (old records have no saveVersion field at all -> nil; version-2 AND version-3 records from the prior
-- wipes also no longer match) is treated as a brand-new player (defaults: 25 coins, Tiny gut, island 1,
-- no saved meter), then re-saved at this version. After this, normal saving resumes — post-wipe records
-- load normally. This is a ONE-TIME action: the version stays at 4; we do NOT reset on every join.
local SAVE_VERSION = 4
local AUTOSAVE_INTERVAL = 90      -- seconds between autosaves
local dataLoaded = {}             -- [player] = true once load succeeded & applied; gates ALL saves
-- [NOSAVE TEST] \xE2\x9A\xA0 TEMPORARY -- REMOVE BEFORE LAUNCH. While TRUE, save/load is DISABLED for EVERY player: every
-- join starts as a brand-NEW player (forced 25 coins, island 1, Tiny Gut 100, fart power 0/100, highestIslandReached 1)
-- and NOTHING is ever written to the DataStore -- the join load is skipped, and the autosave / PlayerRemoving /
-- BindToClose saves are all skipped (they route through savePlayerData). Flip to false to restore normal save/load.
local DISABLE_SAVE_FOR_TESTING = true -- \xE2\x9A\xA0 NOSAVE TEST: forced fresh 25-coin start + no persistence. REMOVE BEFORE LAUNCH.
if DISABLE_SAVE_FOR_TESTING then print("[NOSAVE TEST] saving disabled, forced 25 coins on join — REMOVE BEFORE LAUNCH") end
-- [TEST — ONE-TIME FULL DATA CAPTURE] While TRUE: the player joins with ~unlimited coins (9,999,999)
-- and can buy/switch to ANY stomach tier (Tiny..Iron) from the shop for FREE (cost/coins ignored), so
-- every tier's full-tank reach can be sampled in a single run with no grinding. This ONLY removes the
-- coin constraint — flight physics, island positions, food costs, and earn rate are unchanged. Use
-- alongside DISABLE_SAVE (so the 9,999,999 never persists). Flip to false to restore normal economy.
local TEST_FULL_DATA = false
local TEST_FULL_DATA_COINS = 9999999
-- [BALANCE LOGGING] per-session attempt tracking (logging only, no gameplay effect).
local sessionFlights = {}         -- [player] = total flights this session (one per landing)
local flightsSinceNewIsland = {}  -- [player] = flights since the last NEW island was reached
local attemptsPerIsland = {}      -- [player] = { [islandNum] = attempts it took to reach that island }
-- [BALANCE LOGGING] additional per-session tracking (logging only, no gameplay effect).
local sessionStartTime = {}       -- [player] = os.clock() at join (for real playtime)
local islandReachTime = {}        -- [player] = { [islandNum] = playtime(s) when that island was reached }
local lastIslandReachClock = {}   -- [player] = os.clock() when the previous island was reached (for per-island time)
local coinsAtLastIsland = {}      -- [player] = TotalCoinsEarned snapshot at the previous island (for per-island earned)
local islandCoinsEarned = {}      -- [player] = { [islandNum] = coins earned on the way to that island }
local coinsSpentOnFood = {}       -- [player] = total coins spent on food
local coinsSpentOnGuts = {}       -- [player] = total coins spent on guts
local gutPurchases = {}           -- [player] = { {name, island, time, flight}, ... }
local gutBoughtSinceIsland = {}   -- [player] = true if a gut was bought since the previous island (per-island flag)
local saveGateFlights = {}        -- [player] = { [islandNum] = count of save-gate flights toward that island }
local reachFlights = {}           -- [player] = { [islandNum] = count of trying-to-reach flights toward that island }
local saveGateAccum = {}          -- [player] = save-gate flights accumulated since the last new island
local reachAccum = {}             -- [player] = trying-to-reach flights accumulated since the last new island
local gutAtIsland = {}            -- [player] = { [islandNum] = StomachMax when that island was reached }
local birdEncounters = {}         -- [player] = total bird hits this session (from LandingEvent 2nd arg)
local flightsOfSaving = {}        -- [player] = flights since the last gut purchase (for BOUGHT GUT log)
-- server-wide event tracking (the event loop fires events for everyone)
local eventsFiredCount = 0        -- total server events fired this server's lifetime
local eventsFiredTally = {}       -- { [eventName] = count }

-- Returns: "ok",<table|nil> (loaded data, or nil = brand-new player) | "nostore",nil (DataStore
-- unavailable, e.g. Studio API off — run on defaults, don't persist) | "fail",nil (GetAsync errored
-- every retry — caller must NOT hand out a fresh save that could overwrite real data).
local function fetchPlayerData(player)
	-- [RESET] All per-user TEST overrides removed (permanent-reset account, Spawn-at-Pizza-Palms island-14/99999
	-- stomach, Fresh-Player / Fresh-Player-2 forced new-player + gamepass void). Every player now loads their REAL
	-- save below, or new-player DEFAULTS (25 coins / Tiny Gut 100 / island 1, no gamepasses) if they have none.
	if DISABLE_SAVE_FOR_TESTING then
		print("LOAD: "..player.Name.." SKIPPED (DISABLE_SAVE_FOR_TESTING) — starting as a brand-new player (defaults)")
		return "ok", nil -- "ok" + nil = brand-new player -> defaults applied (25 coins, island 1, Tiny Gut)
	end
	local key = tostring(player.UserId)
	print("LOAD: "..player.Name.." attempting load (key="..key..", store=PlayerData_v1)")
	if not playerDataStore then
		print("LOAD: FAILED - playerDataStore is nil (DataStore service unavailable / API access off)")
		return "nostore", nil
	end
	local lastErr
	for attempt = 1, 4 do
		local ok, result = pcall(function() return playerDataStore:GetAsync(key) end)
		if ok then return "ok", result end
		lastErr = result
		print("LOAD: attempt "..attempt.."/4 errored - "..tostring(result))
		task.wait(2)
	end
	print("LOAD: FAILED - "..tostring(lastErr))
	return "fail", nil
end

-- Save current progress. No-ops unless the load succeeded (dataLoaded) and the store exists, so a
-- failed/never-loaded player can't wipe their save. pcall'd.
local function savePlayerData(player, trigger)
	trigger = trigger or "?"
	-- [RESET] per-user save-disable special-casing removed (lando5485 permanent reset, Broskie/itsmaddmax2 fresh-test
	-- skips) -- saving now works normally for EVERY player.
	if DISABLE_SAVE_FOR_TESTING then
		print("SAVE ("..trigger.."): "..player.Name.." SKIPPED (DISABLE_SAVE_FOR_TESTING) — test runs are not persisted")
		return
	end
	if not playerDataStore then
		print("SAVE ("..trigger.."): "..player.Name.." SKIPPED - no DataStore"); return
	end
	if not dataLoaded[player] then
		print("SAVE ("..trigger.."): "..player.Name.." SKIPPED - data never loaded (won't overwrite real save)"); return
	end
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		print("SAVE ("..trigger.."): "..player.Name.." SKIPPED - no leaderstats"); return
	end
	local function val(n, d) local s = ls:FindFirstChild(n); return (s and s.Value) or d end
	-- FART METER to save: use the snapshotted last-known meter (updated on meter changes) so a respawn/
	-- cleanup that just zeroed the live CurrentPower can't make us persist a stale 0. Fall back to the
	-- live leaderstat if no snapshot yet. Clamp defensively to the gut max.
	local gutMaxNow = val("StomachMax", DEFAULT_STOMACH)
	local meterToSave = math.clamp(math.floor(lastMeter[player] or val("CurrentPower", 0)), 0, gutMaxNow)
	-- Read LIVE current values straight off leaderstats / the runtime home-base table.
	local data = {
		saveVersion      = SAVE_VERSION,  -- stamp the current version so future joins load normally (post-wipe)
		coins            = val("Coins", DEFAULT_COINS),
		-- [STOMACH RESET] while the gut is forced to base, persist the HIGHER of the real on-disk gut (loadedStomachMax)
		-- and the live leaderstat -- so the reset is non-destructive (the saved tier survives) AND any coin-tier the player
		-- buys this session still persists, while the forced base (<= both) never overwrites real progress. Reversible.
		stomachMax       = FORCE_BASE_STOMACH and math.max(loadedStomachMax[player] or DEFAULT_STOMACH, val("StomachMax", DEFAULT_STOMACH)) or val("StomachMax", DEFAULT_STOMACH),
		island           = val("Island", DEFAULT_ISLAND),
		highestIsland    = highestIslandReached[player] or DEFAULT_ISLAND,
		totalFartPower   = val("TotalFartPower", 0),
		totalCoinsEarned = val("TotalCoinsEarned", 0),
		fartMeter        = meterToSave,  -- persist the player's CURRENT fart-meter (raw power), from the snapshot
		ownedPets        = _G.playerOwnedPets[player] or {},  -- cosmetic pet ownership + per-pet {level,height,time}
		equippedPet      = _G.playerEquippedPet[player],      -- cosmetic: which pet is currently equipped (additive)
		discoveredQuests = _G.playerDiscoveredQuests[player] or {}, -- cosmetic: which pet quests are discovered (additive)
		everCompletedQuests = _G.playerEverCompletedQuests[player] or {}, -- PERMANENT first-completion flags (gates the one-time rare roll; additive)
		seenGardenIntro  = player:GetAttribute("SeenGardenIntro") == true, -- one-time Community Garden cinematic: true once the player has watched it
		ownedGutSkins    = _G.playerOwnedGutSkins[player] or { Default = true },  -- cosmetic gut skins owned (always includes Default)
		equippedGutSkin  = _G.playerEquippedGutSkin[player] or "Default",         -- currently equipped gut skin id
		playtimeSeconds  = _G.playerPlaytimeSec[player] or 0,                     -- total cumulative playtime (drives skin unlocks)
	}
	print(string.format("[SAVE METER] player=%s meter=%d", player.Name, meterToSave))
	local key = tostring(player.UserId)
	print("SAVE ("..trigger.."): "..player.Name.." attempting (key="..key..") - coins="..data.coins.." island="..data.highestIsland.." stomach="..data.stomachMax)
	local ok, err = pcall(function() playerDataStore:SetAsync(key, data) end)
	if ok then
		print("SAVE ("..trigger.."): success")
	else
		print("SAVE ("..trigger.."): FAILED - "..tostring(err))
	end
end
_G.savePlayerData = savePlayerData -- exposed so PetSystem can persist BOTH players immediately after a trade (anti-dupe)

-- Autosave loop (~every AUTOSAVE_INTERVAL s).
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, p in ipairs(Players:GetPlayers()) do savePlayerData(p, "autosave") end
	end
end)

-- Save everyone on server shutdown so nothing is lost when the server closes.
game:BindToClose(function()
	print("SAVE (BindToClose): server shutting down, saving "..#Players:GetPlayers().." player(s)")
	for _, p in ipairs(Players:GetPlayers()) do savePlayerData(p, "BindToClose") end
	task.wait(2) -- give SetAsync a moment to flush before the server fully closes
end)

-- Tutorial-NPC guard: the Farmer rig must NEVER be mistaken for an island's stand. Returns true if
-- `obj` lives inside a Humanoid character or a Farmer model, so the stand-finder/prompt-tagger can
-- skip it. (Belt-and-suspenders: even a stray Farmer parented inside an island won't shadow the stand.)
local function isTutorialNpc(obj, stopAt)
	local cur = obj
	while cur and cur ~= stopAt and cur ~= workspace do
		if cur.Name == "FarmerNPC" or cur.Name == "Farmer" then return true end
		if cur:IsA("Model") and cur:FindFirstChildWhichIsA("Humanoid") then return true end
		cur = cur.Parent
	end
	return false
end

-- Find an island's model ROBUSTLY so a dragged/renamed/nested model can't break the lookup.
-- A model "is island N" if its name CONTAINS "Island_<n>_" (plain substring). This survives a
-- trailing/leading space, a stray hidden character, or a rename, and "Island_1_" can never match
-- "Island_10_..." / "Island_11_..." (the char after "Island_1" there is a digit, not "_").
-- Search order: exact top-level child -> any top-level Island_<n>_ Model -> any Island_<n>_ Model
-- nested ANYWHERE in Workspace (e.g. dragged into a folder or that stray unnamed Model).
-- NOTE: cannot recover a genuinely DELETED model — that must be restored in Studio.
local function findIslandModel(islandNum)
	local name = ISLAND_NAMES[islandNum]
	local key = "Island_" .. islandNum .. "_"
	local function looksLikeIsland(inst)
		return inst:IsA("Model") and inst.Name:find(key, 1, true) ~= nil
	end
	-- 1) normal case: exact name, top-level child.
	local exact = workspace:FindFirstChild(name)
	if exact then return exact end
	-- 2) top-level child whose name contains "Island_<n>_" (rename / hidden char / trailing space).
	for _, child in ipairs(workspace:GetChildren()) do
		if looksLikeIsland(child) then
			warn(("ISLAND %d: exact name '%s' not found; using top-level model '%s' (name has a typo/space/hidden char — fix it to '%s')."):format(islandNum, name, child.Name, name))
			return child
		end
	end
	-- 3) nested anywhere in Workspace (dragged into a folder / another model / the stray unnamed Model).
	for _, desc in ipairs(workspace:GetDescendants()) do
		if looksLikeIsland(desc) then
			warn(("ISLAND %d: model '%s' is NESTED under '%s' (not a top-level Workspace child). Using it; move it back to the top of Workspace and name it '%s'."):format(islandNum, desc.Name, tostring(desc.Parent), name))
			return desc
		end
	end
	-- Not found at all: dump top-level Workspace Models so the real problem (typo / deleted / nested) is visible.
	local names = {}
	for _, c in ipairs(workspace:GetChildren()) do if c:IsA("Model") then names[#names + 1] = "'" .. c.Name .. "'" end end
	warn(("ISLAND %d: NOT FOUND. No Model contains '%s'. Top-level Workspace Models: %s"):format(islandNum, key, table.concat(names, ", ")))
	return nil
end

task.spawn(function()
	task.wait(2)
	for i, iname in ipairs(ISLAND_NAMES) do
		local model = findIslandModel(i)
		local pos = ISLAND_POSITIONS[i]
		if model then
			pcall(function()
				if model:IsA("Model") then
					if model.PrimaryPart then
						model:SetPrimaryPartCFrame(CFrame.new(pos.x, pos.y, pos.z))
					else
						model:MoveTo(Vector3.new(pos.x, pos.y, pos.z))
					end
				end
			end)
			print("Positioned "..iname.." at Y="..pos.y)
			-- PURE VISUAL rotation about the island's CENTER (keeps height + position).
			local rotDeg = ISLAND_ROTATIONS[i]
			if rotDeg and rotDeg ~= 0 and model:IsA("Model") then
				pcall(function()
					local cf = model:GetBoundingBox()       -- center CFrame of the whole model
					local c = cf.Position
					-- Rotate the ENTIRE model about world point c (its center) on Y. PivotTo
					-- moves every descendant together, so stand/shop/paths/props stay aligned.
					local rot = CFrame.new(c) * CFrame.Angles(0, math.rad(rotDeg), 0) * CFrame.new(c):Inverse()
					model:PivotTo(rot * model:GetPivot())
					print("ROTATED island "..i.." ("..iname..") by "..rotDeg.." deg about Y (visual only)")
				end)
			end
			for _, obj in ipairs(model:GetDescendants()) do
				if obj:IsA("ProximityPrompt") and not isTutorialNpc(obj, model) and (obj.ObjectText == "Stand" or obj.ObjectText == "Buy Food" or obj.ObjectText == "") then
					obj:SetAttribute("IslandNumber", i)
					obj.Style = Enum.ProximityPromptStyle.Custom
					obj.Enabled = false
					print("TAGGED island "..i.." prompt: '"..obj.ObjectText.."'")
				end
			end
		else
			print("WARNING: "..iname.." not found in workspace")
		end
	end
end)

-- Largest flat BasePart in the island, IGNORING any tutorial-NPC parts (so the Farmer can never be
-- picked). Used as a robust fallback for the stand position when there's no Stand_N model/prompt.
local function getStandPart(model)
	local bestPart = nil
	local bestArea = 0
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") and not isTutorialNpc(obj, model) then
			local area = obj.Size.X * obj.Size.Z
			if area > bestArea then
				bestArea = area
				bestPart = obj
			end
		end
	end
	return bestPart
end

-- Real Stand part positions per island, [islandNum] = {x,y,z}. Module scope so the
-- home-base respawn/catch system below can read the authoritative positions.
local standData = {}
-- Optional per-island EXACT player-spawn override from a placed SpawnLocation (separate from standData so the
-- Farmer/rocket/return still use the real stand). placeOnStand prefers this when present.
local spawnData = {}
task.spawn(function()
	task.wait(8)
	standData = {}
	spawnData = {}
	for islandNum = 1, 14 do
		local island = findIslandModel(islandNum)
		local partPos = nil
		local standLook = nil -- the stand part's facing (LookVector), used to spawn the player in FRONT of the booth

		print("SEARCHING ISLAND", islandNum, "MODEL FOUND:", island ~= nil)

		if island then
			-- SPAWN-POINT OVERRIDE: if a SpawnLocation is placed in the island, remember it as the EXACT player
			-- spawn spot (stored SEPARATELY in spawnData so the stand below still drives the Farmer/rocket/return).
			-- placeOnStand prefers this for islands that have one — e.g. the Bean Farm / island-1 spawn.
			for _, obj in ipairs(island:GetDescendants()) do
				if obj:IsA("SpawnLocation") then
					local top = obj.Position + Vector3.new(0, obj.Size.Y / 2, 0) -- pad top surface
					local lk = obj.CFrame.LookVector
					local fx, fz = 0, 1
					local h = Vector3.new(lk.X, 0, lk.Z)
					if h.Magnitude > 0.05 then h = h.Unit; fx, fz = h.X, h.Z end
					spawnData[islandNum] = {x=top.X, y=top.Y, z=top.Z, fx=fx, fz=fz, exact=true}
					print("STAND["..islandNum.."]: SpawnLocation '"..obj.Name.."' -> exact player spawn at", top)
					break
				end
			end

			-- Method 1: search ALL descendants for Stand_N model (handles nested hierarchy)
			local standName = "Stand_"..islandNum
			local standModel = nil
			for _, obj in ipairs(island:GetDescendants()) do
				if obj:IsA("Model") and obj.Name == standName and not isTutorialNpc(obj, island) then
					standModel = obj
					break
				end
			end
			print("  "..standName.." found in descendants:", standModel ~= nil)
			if standModel then
				local part = standModel.PrimaryPart or standModel:FindFirstChildWhichIsA("BasePart")
				if part then
					partPos = part.Position
					standLook = part.CFrame.LookVector
						print("STAND["..islandNum.."]: Method1 on", part.Name, part.Position)
				end
			else
				-- dump all Model names so we can see what's actually inside
				for _, obj in ipairs(island:GetDescendants()) do
					if obj:IsA("Model") then print("  MODEL:", obj.Name) end
				end
			end

			-- Method 2: any ProximityPrompt — walk up ancestors to find a BasePart
			if not partPos then
				for _, obj in ipairs(island:GetDescendants()) do
					if obj:IsA("ProximityPrompt") and not isTutorialNpc(obj, island) then
						local cur = obj.Parent
						while cur and cur ~= island and cur ~= workspace do
							if cur:IsA("BasePart") then
								partPos = cur.Position
								print("STAND["..islandNum.."]: Method2 on", cur.Name)
								break
							end
							cur = cur.Parent
						end
						if partPos then break end
					end
				end
			end

			-- Method 3: island PrimaryPart
			if not partPos and island:IsA("Model") and island.PrimaryPart then
				partPos = island.PrimaryPart.Position
				print("STAND["..islandNum.."]: Method3 PrimaryPart")
			end

			-- Method 3.5: largest NON-NPC BasePart in the island (its stand/platform). Robust catch-all
			-- so a REAL on-island position is always used instead of the off-island ISLAND_POSITIONS
			-- fallback, with the Farmer's parts excluded so he can never become the stand.
			if not partPos then
				local part = getStandPart(island)
				if part then
					partPos = part.Position
					standLook = part.CFrame.LookVector
					print("STAND["..islandNum.."]: Method3.5 largest non-NPC part:", part.Name, part.Position)
				end
			end
		else
			print("STAND["..islandNum.."]: island not in workspace")
		end

		-- Method 4: guaranteed fallback to known island position
		if not partPos then
			local pos = ISLAND_POSITIONS[islandNum]
			partPos = Vector3.new(pos.x, pos.y, pos.z)
			print("STAND["..islandNum.."]: Method4 ISLAND_POSITIONS Y="..pos.y)
		end

		-- Horizontal facing of the booth (flattened LookVector). Used to drop the player a bit in
		-- FRONT of the stand, looking back at it. Defaults to +Z if the stand had no usable orientation.
		local sfx, sfz = 0, 1
		if standLook then
			local h = Vector3.new(standLook.X, 0, standLook.Z)
			if h.Magnitude > 0.05 then h = h.Unit; sfx, sfz = h.X, h.Z end
		end
		standData[islandNum] = {x=partPos.X, y=partPos.Y, z=partPos.Z, fx=sfx, fz=sfz}
		print("STAND["..islandNum.."]: READY Y="..partPos.Y..(spawnData[islandNum] and " (+SpawnLocation override)" or ""))
	end
	local count = 0; for _ in pairs(standData) do count = count + 1 end
	print("STAND DATA COUNT:", count)
	for k, v in pairs(standData) do
		print("STAND DATA ISLAND", k, v.x, v.y, v.z)
	end
	print("STANDS SETUP COMPLETE:", count, "/ 14")

	-- Publish island-1's REAL detected stand + a readiness flag so the tutorial-NPC spawner can place
	-- the Farmer at the actual stand AFTER detection is done. The Farmer lives in ServerStorage (never
	-- in Workspace during stand setup), so it can never interfere with island detection.
	local s1 = standData[1]
	if s1 then
		workspace:SetAttribute("Stand1Pos", Vector3.new(s1.x, s1.y, s1.z))
		workspace:SetAttribute("Stand1Face", Vector3.new(s1.fx, 0, s1.fz))
	end
	workspace:SetAttribute("StandsReady", true)

	local StandsReadyEvent = RS:WaitForChild("StandsReadyEvent", 10)
	if not StandsReadyEvent then
		print("STAND: StandsReadyEvent not found!")
		return
	end

	local function fireToAll()
		for _, p in ipairs(Players:GetPlayers()) do
			StandsReadyEvent:FireClient(p, standData)
		end
	end

	-- Fire now, then re-fire at +7s and +15s for clients that load after the character spawns
	fireToAll()
	task.delay(7,  fireToAll)
	task.delay(15, fireToAll)

	Players.PlayerAdded:Connect(function(p)
		task.wait(5)
		StandsReadyEvent:FireClient(p, standData)
	end)
end)

Players.PlayerAdded:Connect(function(player)
	-- Load saved data FIRST. If it fails, kick instead of letting them play on a fresh save that
	-- would overwrite their real progress.
	local status, saved = fetchPlayerData(player)
	if status == "fail" then
		player:Kick("Couldn't load your saved data. Please rejoin.")
		return
	end
	if not player.Parent then return end -- left during the load
	-- ONE-TIME WIPE: any record from an OLD save version (or with no saveVersion field, i.e. all
	-- pre-wipe records) is discarded and the player is treated as brand-new. The defaults path below
	-- then runs, and they get re-saved at SAVE_VERSION (autosave / leave), so future joins load normally.
	if status == "ok" and saved and saved.saveVersion ~= SAVE_VERSION then
		print("LOAD: "..player.Name.." save WIPED (saveVersion "..tostring(saved.saveVersion).." ~= "..SAVE_VERSION..") -> starting brand-new")
		saved = nil
	end
	if status == "ok" and saved then
		print("LOAD: success - coins="..tostring(saved.coins).." island="..tostring(saved.highestIsland).." stomach="..tostring(saved.stomachMax))
	elseif status == "ok" then
		print("LOAD: no save found, using defaults")
	else -- "nostore"
		print("LOAD: no DataStore available, using defaults (will NOT persist)")
	end
	saved = saved or {} -- new player ("ok" nil) or "nostore" -> defaults below

	local ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player
	local coins  = Instance.new("IntValue"); coins.Name  = "Coins";          coins.Value  = saved.coins or DEFAULT_COINS;        coins.Parent  = ls
	if DISABLE_SAVE_FOR_TESTING then coins.Value = DEFAULT_COINS end -- [NOSAVE TEST] \xE2\x9A\xA0 force a fresh 25-coin start, IGNORING any saved coin value. REMOVE BEFORE LAUNCH.
	if TEST_FULL_DATA then coins.Value = TEST_FULL_DATA_COINS end -- [TEST] unlimited coins to sample every tier's reach without grinding
	local island = Instance.new("IntValue"); island.Name = "Island";         island.Value = math.max(saved.island or DEFAULT_ISLAND, saved.highestIsland or DEFAULT_ISLAND); island.Parent = ls
	local tfp    = Instance.new("IntValue"); tfp.Name    = "TotalFartPower"; tfp.Value    = saved.totalFartPower or 0;           tfp.Parent    = ls
	local tce    = Instance.new("IntValue"); tce.Name    = "TotalCoinsEarned"; tce.Value  = saved.totalCoinsEarned or 0;         tce.Parent    = ls
	-- [STOMACH RESET] StomachMax: remember the REAL on-disk value (preserved through save), then force the live gut to
	-- the BASE starting value while FORCE_BASE_STOMACH is on (don't trust a stored 9999 / any saved upgrade). Clear the
	-- Infinite-Gut flag so the meter never locks full. When the reset is off, load the saved tier as normal.
	loadedStomachMax[player] = saved.stomachMax or DEFAULT_STOMACH
	local stomachStart = FORCE_BASE_STOMACH and DEFAULT_STOMACH or (saved.stomachMax or DEFAULT_STOMACH)
	local stomachMaxStat = Instance.new("IntValue"); stomachMaxStat.Name="StomachMax"; stomachMaxStat.Value=stomachStart; stomachMaxStat.Parent=ls
	if FORCE_BASE_STOMACH then player:SetAttribute("HasInfiniteGut", false) end
	-- RESTORE FART METER: clamp the saved meter to the (restored) gut max — never above; NO lower cap.
	-- [FART RESET] while the reset is on, the meter STARTS EMPTY (0) -- a fresh start is 0/StomachMax, never a full tank,
	-- so a high saved meter can't restore as a FULL base tank on spawn/load. (Reset off -> restore the saved meter as
	-- before.) (When DISABLE_SAVE_FOR_TESTING is on, `saved` is empty -> fartMeter nil -> 0, so it follows the save flag.)
	local restoredMeter = FORCE_BASE_STOMACH and 0 or math.max(0, math.min(math.floor(tonumber(saved.fartMeter) or 0), stomachMaxStat.Value))
	local currentPowerStat = Instance.new("IntValue"); currentPowerStat.Name="CurrentPower"; currentPowerStat.Value=restoredMeter; currentPowerStat.Parent=ls
	print(string.format("[FART RESET] start CurrentPower=%d StomachMax=%d (should be 0/100)", currentPowerStat.Value, stomachMaxStat.Value))
	-- [NOSAVE TEST] \xE2\x9A\xA0 TEMPORARY -- confirm the forced fresh start + that saving is off. REMOVE BEFORE LAUNCH.
	if DISABLE_SAVE_FOR_TESTING then
		print(string.format("[NOSAVE TEST] %s coins=%d power=%d/%d saveDisabled=yes", player.Name, coins.Value, currentPowerStat.Value, stomachMaxStat.Value))
	end
	-- [STOMACH RESET] confirm the starting gut + meter are base and ALL gut ownership reads false.
	print(string.format("[STOMACH RESET] ownsInfiniteGut=%s allGutsOwned=%d StomachMax=%d CurrentPower=%d (should be base, ownership all false)",
		FORCE_BASE_STOMACH and "n" or "?", FORCE_BASE_STOMACH and 0 or 0, stomachMaxStat.Value, currentPowerStat.Value))
	-- METER PERSISTENCE: remember the saved meter to RE-APPLY after the first spawn settles. We can't
	-- rely on the leaderstat value above surviving, because the spawn's onLand fires LandingEvent(0)
	-- which (decrease-only) zeros CurrentPower. The SelectIslandEvent spawn hook re-applies this value
	-- post-spawn and replicates it to the client's gas meter. lando5485 has saved=nil -> 0 -> no restore.
	joinRestoreMeter[player] = restoredMeter
	lastMeter[player] = restoredMeter
	print(string.format("[LOAD METER] player=%s saved=%d applied_to_live=%d", player.Name, math.floor(tonumber(saved.fartMeter) or 0), restoredMeter))
	-- Restore home base / highest island. Use the MAX of both saved fields so the home stand (where
	-- onCharacterAdded teleports), the HighestIsland attribute, and the Island leaderstat (food-shop
	-- unlocks) all reflect the furthest the player reached — they had diverged before.
	local restoredIsland = math.max(saved.highestIsland or DEFAULT_ISLAND, saved.island or DEFAULT_ISLAND)
	highestIslandReached[player] = restoredIsland
	player:SetAttribute("HighestIsland", restoredIsland)
	print("LOAD ISLAND: "..player.Name.." restored highestIsland="..restoredIsland..", teleporting to stand "..restoredIsland)
	dataLoaded[player] = true
	playerCoinAccum[player] = 0
	-- ONE-TIME GARDEN INTRO: restore the "has watched the cinematic" flag as a player attribute (replicates to
	-- the client; the SelectIslandEvent hook reads it to decide whether to play). \xE2\x9A\xA0 TEST: lando5485 is treated as a
	-- brand-new player every join -- force the flag FALSE so the intro replays for testing. REMOVE BEFORE LAUNCH.
	local isIntroTester = (player.UserId == TEST_ACCOUNT_USERID) or (string.lower(player.Name) == "lando5485")
	local seenIntro = (not isIntroTester) and (saved.seenGardenIntro == true)
	player:SetAttribute("SeenGardenIntro", seenIntro)
	print("LOAD GARDEN INTRO: "..player.Name.." SeenGardenIntro="..tostring(seenIntro)..(isIntroTester and " (TEST: forced replay)" or ""))
	-- PETS: restore cosmetic pet ownership from the save (fresh/test/synthetic saves have no ownedPets
	-- field -> {} -> no pet, which respects FRESH_PLAYER_TEST / SPAWN_AT_PIZZA_PALMS_TEST). Then let
	-- PetSystem react (spawn an owned pet + send the client its state). Guarded so load never depends on it.
	_G.playerOwnedPets[player] = saved.ownedPets or {}
	_G.playerEquippedPet[player] = saved.equippedPet -- cosmetic equipped choice (nil if none / legacy save)
	-- GUT SKINS: new players (and legacy saves) start owning ONLY Default, equipped Default. GutSkinService reads these.
	_G.playerOwnedGutSkins[player] = saved.ownedGutSkins or { Default = true }
	_G.playerOwnedGutSkins[player].Default = true -- safety: everyone always owns Default
	_G.playerEquippedGutSkin[player] = saved.equippedGutSkin or "Default"
	_G.playerPlaytimeSec[player] = tonumber(saved.playtimeSeconds) or 0 -- restore total playtime (new players = 0)
	_G.playerDiscoveredQuests[player] = saved.discoveredQuests or {} -- cosmetic discovered-quest set (empty / legacy save)
	_G.playerEverCompletedQuests[player] = saved.everCompletedQuests or {} -- PERMANENT first-completion flags (empty / legacy save -> never completed)
	if _G.petsApplyOnJoin then pcall(function() _G.petsApplyOnJoin(player) end) end
	-- Gamepass ownership is read LIVE each join (never saved).
	task.spawn(function()
		local gpData = {twoXForever=false, glitterTrail=false}
		for name, id in pairs(GAMEPASS_IDS) do
			if id ~= 0 then
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
				end)
				-- [RESET] gamepass-voiding test hooks removed: ownership is whatever Roblox reports (owned-only) for EVERY player.
				-- [STOMACH RESET] the GUT gamepass is forced un-owned while FORCE_BASE_STOMACH is on, so Infinite Gut never applies.
				if name == "InfiniteGut" and FORCE_BASE_STOMACH then owns = false end
				-- [NOSAVE TEST] the 2x FOREVER gamepass is forced un-owned while FORCE_NO_2X is on. REMOVE BEFORE LAUNCH.
				if name == "TwoXForever" and FORCE_NO_2X then owns = false; player:SetAttribute("HasTwoXForever", false) end
				if ok and owns then
					if name == "TwoXForever" then gpData.twoXForever = true; player:SetAttribute("HasTwoXForever", true)
					elseif name == "GlitterTrail" then gpData.glitterTrail = true; player:SetAttribute("HasGlitterTrail", true)
					elseif name == "InfiniteGut" then applyInfiniteGut(player) -- forever pass: re-apply the Infinite Gut tier on join (effect is the StomachMax, not a client gpData flag)
					end
				elseif name == "InfiniteGut" and (FORCE_BASE_STOMACH or ok) then
					-- [STOMACH RESET] forced un-owned, OR the ownership check SUCCEEDED as not-owned (never clamp on a failed
					-- check -> don't strip a real owner on a transient error): clamp a stored 9999 back to base + clear the flag.
					player:SetAttribute("HasInfiniteGut", false)
					local lsg = player:FindFirstChild("leaderstats"); local smg = lsg and lsg:FindFirstChild("StomachMax")
					if smg and smg.Value >= INFINITE_GUT_MAX then
						smg.Value = DEFAULT_STOMACH
						pcall(function() StomachUpdateEvent:FireClient(player, DEFAULT_STOMACH, "Tiny Gut") end)
						print("[STOMACH RESET] clamped stored Infinite Gut (9999) back to base for "..player.Name.." (not owned / forced)")
					end
				end
			end
		end
		-- Store the computed ownership so the on-ready handshake can re-send it (and mark it ready).
		gamepassState[player] = gpData
		gamepassReady[player] = true
		if GamepassEvent then
			-- [BALANCE] send an all-false perk state when disabled, so the client mirrors "no perks"
			-- (powerPassActive=false, no Glitter Trail, FLIGHT DEBUG has2x=false) even if the player owns them.
			pcall(function() GamepassEvent:FireClient(player, DISABLE_PERKS_FOR_BALANCE and {twoXForever=false, glitterTrail=false} or gpData) end)
		end
	end)
end)

-- ON-READY HANDSHAKE: the client fires RequestPlayerState once its HUD + handlers are built. We then
-- (re)send the saved state so the LABEL, forever gamepasses, capacity, and menu all agree on every
-- platform — independent of join-time push timing (fixes slow mobile/console clients).
RequestPlayerState.OnServerEvent:Connect(function(player)
	-- (1) GUT LABEL: re-send the saved gut (read from the already-restored StomachMax leaderstat) so the
	-- on-screen gut name matches the meter capacity. The client looks the name up from maxPower itself.
	local ls = player:FindFirstChild("leaderstats")
	local sm = ls and ls:FindFirstChild("StomachMax")
	if sm and StomachUpdateEvent then
		local gutName = "Tiny Gut"
		for _, t in ipairs(stomachTiers) do if t.maxPower == sm.Value then gutName = t.name; break end end
		pcall(function() StomachUpdateEvent:FireClient(player, sm.Value, gutName) end)
	end
	-- (1b) FART METER: restore the saved meter so the gas-meter BAR shows the correct fill on join. We
	-- send it AFTER the gut label so the client's gut max is set first. RegenEvent makes the client set
	-- currentPower + gasMeter and refresh the bar/button. Safety-clamp to the gut max (already clamped on
	-- load; re-clamped here defensively). Same cross-platform handshake as the gut label.
	local cp = ls and ls:FindFirstChild("CurrentPower")
	if cp and sm and RegenEvent then
		local restored = math.max(0, math.min(cp.Value, sm.Value))
		pcall(function() RegenEvent:FireClient(player, 0, restored, sm.Value) end)
	end
	-- (2) FOREVER GAMEPASSES: wait briefly for the on-join ownership check to finish, then re-send the
	-- active state (2X Power Forever / Glitter Trail) so client visuals/effects apply without manual action.
	local deadline = os.clock() + 8
	while not gamepassReady[player] and os.clock() < deadline do task.wait(0.15) end
	if GamepassEvent then
		local gp = gamepassState[player] or { twoXForever = false, glitterTrail = false }
		pcall(function() GamepassEvent:FireClient(player, DISABLE_PERKS_FOR_BALANCE and { twoXForever = false, glitterTrail = false } or gp) end)
	end
	-- (3) 2X Coins (1hr): consumable timer is NOT in the saved data table, so there is nothing to restore
	-- on join. (If/when a remaining-expiry is ever saved, re-send it here as {twoXHourExpiry=...}.)
end)

Players.PlayerRemoving:Connect(function(player)
	print("PlayerRemoving FIRED for "..player.Name)
	savePlayerData(player, "PlayerRemoving") -- gated by dataLoaded + pcall'd inside; saves coins/gut/island/home base (reads lastMeter)
	playerCoinAccum[player] = nil
	dataLoaded[player] = nil
	gamepassState[player] = nil
	gamepassReady[player] = nil
	lastMeter[player] = nil       -- cleared AFTER save (save reads it for the meter)
	joinRestoreMeter[player] = nil
	loadedStomachMax[player] = nil -- cleared AFTER save (save reads it to preserve the real on-disk gut while forced)
	_G.playerOwnedPets[player] = nil  -- cleared AFTER save (save reads it for ownedPets)
	_G.playerEquippedPet[player] = nil
	_G.playerDiscoveredQuests[player] = nil
	_G.playerEverCompletedQuests[player] = nil -- cleared AFTER save (save reads it for everCompletedQuests)
end)

-- (Daily Rewards join-handshake removed.)

BuyFoodEvent.OnServerEvent:Connect(function(player, foodName)
	print("SERVER RECEIVED BUY:", player.Name, foodName)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then return end
	local coins        = stats:FindFirstChild("Coins")
	local totalPower   = stats:FindFirstChild("TotalFartPower")
	local totalEarned  = stats:FindFirstChild("TotalCoinsEarned")
	local currentPower = stats:FindFirstChild("CurrentPower")
	local stomachMax   = stats:FindFirstChild("StomachMax")
	if not coins or not totalPower then return end
	local food = nil
	for _, f in ipairs(foods) do
		if f.name == foodName then food = f; break end
	end
	if not food then
		print("FOOD NOT FOUND:", foodName)
		return
	end
	-- FAILURE CHECK 1 (COINS FIRST — the common blocker): not enough coins -> "not_enough_coins".
	if coins.Value < food.price then
		print("NOT ENOUGH COINS:", player.Name, coins.Value, "<", food.price)
		pcall(function() StomachFullEvent:FireClient(player, "not_enough_coins") end) -- specific reason for the client
		return
	end
	if not currentPower or not stomachMax then return end
	-- 2x Fart Power pass (forever) OR an active 1-hour product both grant the real power boost.
	local has2x = player:GetAttribute("HasTwoXForever") or
		(player:GetAttribute("TwoXHourExpiry") and player:GetAttribute("TwoXHourExpiry") > os.time())
	if DISABLE_2X and game:GetService("RunService"):IsStudio() then has2x = false end -- [TESTING] no 2x boost in Studio
	if DISABLE_PERKS_FOR_BALANCE then has2x = false end -- [BALANCE] force normal 1x power (Studio AND live) -> Beans = 8
	if FORCE_NO_2X then has2x = false end -- [NOSAVE TEST] 2x forced un-owned for everyone -> no 2x power boost. REMOVE BEFORE LAUNCH.
	-- With the pass, food adds POWER_PASS_MULT x its power to ACTUAL flight fuel, and the
	-- effective tank grows to stomachMax * POWER_PASS_MULT (so the player flies higher).
	local powerGain   = has2x and math.floor(food.power * POWER_PASS_MULT) or food.power
	local effectiveMax = has2x and math.floor(stomachMax.Value * POWER_PASS_MULT) or stomachMax.Value
	local newPower = currentPower.Value + powerGain
	-- FAILURE CHECK 2 (only reached when coins are sufficient): does it fit the REMAINING stomach space?
	-- Distinguish TRULY FULL (no room at all -> "stomach_full") from HAS-ROOM-but-too-big ("not_enough_room").
	if newPower > effectiveMax then
		local remaining = effectiveMax - currentPower.Value
		if remaining <= 0 then
			print("STOMACH FULL:", player.Name, currentPower.Value, "/", effectiveMax, "(no room at all)")
			pcall(function() StomachFullEvent:FireClient(player, "stomach_full") end)    -- truly full
		else
			print("NOT ENOUGH ROOM:", player.Name, "+"..powerGain, ">", remaining, "remaining")
			pcall(function() StomachFullEvent:FireClient(player, "not_enough_room") end) -- has room, this food won't fit
		end
		return
	end
	coins.Value = coins.Value - food.price
	coinsSpentOnFood[player] = (coinsSpentOnFood[player] or 0) + food.price -- [BALANCE LOGGING] track food spend
	currentPower.Value = newPower
	-- Cosmetic TotalFartPower counter: unchanged — still doubles with the pass as before.
	local bonusPower = has2x and food.power or 0
	totalPower.Value = totalPower.Value + food.power + bonusPower
	if totalEarned then totalEarned.Value = totalEarned.Value + food.price end
	pcall(function() RegenEvent:FireClient(player, food.power, currentPower.Value, stomachMax.Value) end)
	print("BOUGHT:", player.Name, foodName, "+", food.power, "power, total:", currentPower.Value)
	-- PET XP (cosmetic-only): eating food = "collecting gas" -> XP for the equipped pet (proportional to the
	-- power/gas gained). Never affects gas/food/flight balance.
	if _G.petOnGas then _G.petOnGas(player, powerGain) end
end)

CoinEvent.OnServerEvent:Connect(function(player, amount)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local tce   = ls:FindFirstChild("TotalCoinsEarned")
	if not coins or not tce then return end
	local amt = tonumber(amount) or 0; if amt <= 0 then return end
	-- FRIEND/GROUP COIN BOOST: scale earned FLIGHT coins by this player's bonus multiplier (1 = none). Set by
	-- RewardsService (friend-in-server +25%, MLR group +10%, stackable). Flat rewards (codes) are granted directly, unaffected.
	amt = amt * ((_G.coinBonusMult and _G.coinBonusMult[player]) or 1)
	playerCoinAccum[player] = (playerCoinAccum[player] or 0) + amt
	local toAdd = math.floor(playerCoinAccum[player])
	if toAdd > 0 then
		playerCoinAccum[player] = playerCoinAccum[player] - toAdd
		coins.Value = coins.Value + toAdd
		tce.Value   = tce.Value + toAdd
	end
	-- PET XP (cosmetic-only): this coin tick fires every 0.5s DURING FLIGHT, so it feeds BOTH the "coins
	-- earned" and "distance flown" XP sources for the equipped pet. Never affects coins/flight balance.
	if _G.petOnCoins then _G.petOnCoins(player, amt) end
	if _G.petOnFlightTick then _G.petOnFlightTick(player) end
end)


UnlockIslandEvent.OnServerEvent:Connect(function(player, islandNum)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local island = ls:FindFirstChild("Island"); if not island then return end
	local n = tonumber(islandNum) or 0
	if n > island.Value and n <= 14 then
		island.Value = n
		print("ISLAND "..n.." UNLOCKED by "..player.Name)
		if _G.petOnIsland then _G.petOnIsland(player) end -- PET XP (cosmetic-only): reaching a NEW island -> XP chunk for the equipped pet

		-- NOTE: no arrival message here. The welcome + "[username] landed" broadcast fire ONLY
		-- from the physical-landing detection (Heartbeat above), never from this peak/unlock event.
		-- NOTE: do NOT zero CurrentPower / gas here. Reaching or landing on a new island must
		-- keep whatever fuel the player stopped flying with (after drain + any bird hits).
		-- Landing power-sync is handled by LandingEvent (decrease-only, preserves remaining).
	end
end)

-- Skip Island handler is connected later in this script (near the test hooks) via the shared
-- triggerSkipIsland(), so it can reuse teleportToHome / highestIslandReached / standData, which
-- are defined below this point. See triggerSkipIsland.

-- ===== HIGHEST ISLAND REACHED (home base): respawn + fall-below catch =====
-- Server-authoritative. highestIslandReached only ever increases this session. Physical
-- landings are detected with the server's own short downward raycast, so flying PAST an
-- island (without standing on it) does NOT count. There are NO mid-air parts/floors/clouds;
-- the only solid ground is the existing island Stand parts, and the only time we move the
-- player is the single teleport-to-home-Stand case when they drop below their home island.
local RunService = game:GetService("RunService")
-- highestIslandReached is declared up top (near the DataStore init) so the save/load code can use it.
local CATCH_MARGIN  = 50          -- studs below the home Stand before the Return prompt shows
local STAND_OFFSET_Y = 10         -- place the player this far above the Stand part center
local SPAWN_FRONT_DIST = 14       -- studs IN FRONT of the stand to drop the player (so the booth is ahead of them)
local EXACT_SPAWN_OFFSET_Y = 4    -- when spawning ON a SpawnLocation, lift the player this far above its top surface

-- Which island (if any) is the character physically standing on right now? Must work for
-- ALL 14 stands regardless of their geometry/parenting.
local LAND_RAY      = 14   -- studs to ray downward (start slightly above HRP) — covers thick/offset stands
local STAND_NEAR_XZ = 45   -- fallback: horizontal radius around a Stand position to count as "on it"
local STAND_NEAR_Y  = 30   -- fallback: vertical tolerance around a Stand position
local function islandUnderCharacter(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	-- Method A: ray down from just above the HRP and walk up to an Island_N_ ancestor. Starting
	-- a little above the HRP and using a longer ray catches stands whose surface sits lower.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {char}
	local res = workspace:Raycast(hrp.Position + Vector3.new(0, 2, 0), Vector3.new(0, -LAND_RAY, 0), params)
	if res and res.Instance then
		local obj = res.Instance
		while obj and obj ~= workspace do
			local n = obj.Name:match("^Island_(%d+)_")
			if n then return tonumber(n) end
			obj = obj.Parent
		end
	end
	-- Method B (fallback): proximity to a known Stand position. Robust to stands whose parts
	-- aren't named/parented under Island_N_. Caller only runs this while grounded, so being
	-- near a Stand means actually standing on that island. Pick the nearest within tolerance.
	local pos = hrp.Position
	local best, bestDist
	for islandNum, sd in pairs(standData) do
		local dx, dz = pos.X - sd.x, pos.Z - sd.z
		local d2 = dx*dx + dz*dz
		if d2 <= STAND_NEAR_XZ*STAND_NEAR_XZ and math.abs(pos.Y - sd.y) <= STAND_NEAR_Y then
			if not bestDist or d2 < bestDist then best, bestDist = islandNum, d2 end
		end
	end
	return best
end

-- Place the player a bit IN FRONT of the home island's Stand, FACING it — as if they just landed on
-- the path and are looking up at the shop. Same rule for all 14 stands. (The ONLY position clamp we do.)
local function teleportToHome(char, sd)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	-- EXACT SPAWN (SpawnLocation): place the player ON the pad at that precise spot, facing its orientation —
	-- NOT stepped out in front of a stand. sd.y is already the pad's top surface; lift by the character offset.
	if sd.exact then
		local front = Vector3.new(sd.fx or 0, 0, sd.fz or 1)
		if front.Magnitude < 0.05 then front = Vector3.new(0, 0, 1) end
		front = front.Unit
		local pos = Vector3.new(sd.x, sd.y + EXACT_SPAWN_OFFSET_Y, sd.z)
		hrp.CFrame = CFrame.lookAt(pos, pos + front)
		hrp.AssemblyLinearVelocity = Vector3.zero
		return
	end
	local standCenter = Vector3.new(sd.x, sd.y + STAND_OFFSET_Y, sd.z)
	-- Step out along the booth's front-facing direction, then look back at the booth. If a stand had
	-- no usable orientation, fx/fz default to +Z. (Flip SPAWN_FRONT_DIST's sign if a stand template
	-- ever faces the other way so the player lands behind it.)
	local front = Vector3.new(sd.fx or 0, 0, sd.fz or 1)
	if front.Magnitude < 0.05 then front = Vector3.new(0, 0, 1) end
	front = front.Unit
	local spawnPos = standCenter + front * SPAWN_FRONT_DIST
	-- Face the stand using ONLY the horizontal direction: the look target sits at the spawn's OWN
	-- height, so there is zero pitch and the character stays perfectly upright (no tipping). We set the
	-- HumanoidRootPart CFrame directly — the unambiguous way to orient a character (no model-pivot
	-- guesswork) — so the stand ends up straight ahead of them, not sideways.
	local lookTarget = Vector3.new(standCenter.X, spawnPos.Y, standCenter.Z)
	hrp.CFrame = CFrame.lookAt(spawnPos, lookTarget)
	hrp.AssemblyLinearVelocity = Vector3.zero
end

-- No character spawns on join (CharacterAutoLoads = false), so the player is simply held with no
-- character until they pick an island. SelectIslandEvent spawns them on the chosen island. After
-- that, respawns go to their home/highest island (we LoadCharacter manually since auto-spawn is off).
local hasChosenIsland = {} -- [player] = picked their spawn island this session
local spawnIsland = {}     -- [player] = island to place the NEXT character spawn on

-- Position of the Community Garden (the gardener if present, else the build's centre) — used to make the
-- island-1 spawn FACE the garden so the player's character + camera look at it.
local function findGardenPos()
	local build = workspace:FindFirstChild("CommunityGardenBuild", true)
	if not build then return nil end
	local props = build:FindFirstChild("GardenProps")
	local g = props and props:FindFirstChild("Gardener")
	if not g then
		for _, d in ipairs(build:GetDescendants()) do
			if d:IsA("Model") and d:GetAttribute("GardenerNPC") then g = d; break end
		end
	end
	local ok, p = pcall(function() return (g or build):GetPivot().Position end)
	return ok and p or nil
end

local function placeOnStand(char, islandNum)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end
	local sd = standData[islandNum]
	local tries = 0
	while not sd and tries < 50 do task.wait(0.2); sd = standData[islandNum]; tries = tries + 1 end
	-- prefer a placed SpawnLocation (exact spawn) over the stand-front spot, when one exists for this island
	local spot = spawnData[islandNum] or sd
	-- ISLAND 1: spawn FACING the Community Garden, so the on-spawn camera resets behind the player already
	-- looking at it (and the body faces it too). Override the facing with the direction toward the garden, in a
	-- FRESH copy so the saved spawn data is untouched. Brief poll in case the garden is still building.
	if spot and spot.exact and islandNum == 1 then -- only the exact SpawnLocation spawn (facing-only; never shifts position)
		local gp = findGardenPos()
		local pt = 0
		while not gp and pt < 2 do task.wait(0.25); pt = pt + 0.25; gp = findGardenPos() end
		if gp then
			local dx, dz = gp.X - spot.x, gp.Z - spot.z
			local mag = math.sqrt(dx * dx + dz * dz)
			if mag > 0.1 then
				spot = {x = spot.x, y = spot.y, z = spot.z, fx = dx / mag, fz = dz / mag, exact = true}
			end
		end
	end
	if spot then task.wait(0.05); teleportToHome(char, spot) end
end

local function onCharacterAdded(player, char)
	local target = spawnIsland[player] or highestIslandReached[player] or 1
	spawnIsland[player] = nil
	task.spawn(function()
		placeOnStand(char, target)
		print("SPAWN: placed "..player.Name.." on island "..target)
	end)
	-- Auto-spawn is off, so manually reload the character on death (respawn at the home island).
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		hum.Died:Connect(function()
			task.wait(Players.RespawnTime)
			if player.Parent then
				spawnIsland[player] = highestIslandReached[player] or 1
				player:LoadCharacter()
			end
		end)
	end
end

-- The loading-screen island menu picks a spawn island. Server-authoritative RE-VALIDATION: the
-- choice is checked against the SAVED highestIslandReached (never trust the client) and clamped to
-- the unlocked range, then the held player is SPAWNED onto that island's stand. This is what puts
-- the player into the world on join (replacing the old auto-teleport-to-highest).
SelectIslandEvent.OnServerEvent:Connect(function(player, islandNum)
	if hasChosenIsland[player] then return end -- one choice per session (the join menu)
	islandNum = tonumber(islandNum); if not islandNum then return end
	islandNum = math.floor(islandNum)
	-- [RESET] all-islands-unlock TEST bypass removed: EVERY player is validated against their REAL reached island
	-- (highestIslandReached), so new players are locked to island 1 and can only spawn on islands they've reached.
	local maxIsland = highestIslandReached[player] or 1
	if islandNum < 1 or islandNum > maxIsland then
		print("ISLAND SELECT: "..player.Name.." requested LOCKED island "..tostring(islandNum).." (max "..maxIsland.."), clamping")
		islandNum = math.clamp(islandNum, 1, maxIsland)
	end
	hasChosenIsland[player] = true
	spawnIsland[player] = islandNum
	player:LoadCharacter() -- spawn the held player; onCharacterAdded teleports to the chosen stand
	print("ISLAND SELECT: "..player.Name.." spawning on island "..islandNum)
	-- ONE-TIME GARDEN INTRO: a brand-new player (hasn't SeenGardenIntro) who picks island 1 gets the cinematic.
	-- Server-authoritative: gated on the saved/restored flag (attribute), so it never replays for returning players.
	-- The client runs the cutscene and fires GardenIntroDoneEvent back, which sets+saves the flag.
	if islandNum == 1 and player:GetAttribute("SeenGardenIntro") ~= true then
		print("GARDEN INTRO: "..player.Name.." selected island 1 for the first time -> playing cinematic")
		-- Fire immediately as the authoritative fallback. The client also self-starts on click (for the instant
		-- black overlay); GardenIntro's `playing` guard makes this a no-op if the client already began.
		pcall(function() GardenIntroEvent:FireClient(player) end)
	end
	-- FART METER RESTORE (after-spawn): the spawn's own onLand fires LandingEvent(0), which zeros the
	-- decrease-only CurrentPower — so we must re-apply the saved meter SERVER-SIDE once the spawn has
	-- settled, then replicate it to the client's gas meter via RegenEvent. This runs AFTER the
	-- character/gas system is up (handles mobile slow-load), so the value sticks instead of being
	-- overwritten by the default. (joinRestoreMeter is unset/0 for lando5485 and brand-new players.)
	task.spawn(function()
		local want = joinRestoreMeter[player]
		joinRestoreMeter[player] = nil
		-- INFINITE GUT owners: the tank is ALWAYS full, so this post-spawn restore must apply the gut MAX, not
		-- the saved meter (which could be 0/low) — otherwise it would overwrite the instant-full meter that
		-- applyInfiniteGut set on join, and the server value would disagree with the client's full/never-drain
		-- meter. Gated on ownership, so NON-owners restore their saved meter exactly as before.
		-- [STOMACH RESET] while the gut is forced to base, NEVER take the full-tank Infinite-Gut branch (so CurrentPower
		-- is the saved meter clamped to the base StomachMax, never the old 9999 full tank).
		local infiniteGut = (not FORCE_BASE_STOMACH) and (player:GetAttribute("HasInfiniteGut") == true)
		if not infiniteGut and (not want or want <= 0) then return end
		task.wait(2.5) -- let the character spawn, settle, and fire its onLand(0) FIRST
		if not player.Parent then return end
		local ls2 = player:FindFirstChild("leaderstats"); if not ls2 then return end
		local cp2 = ls2:FindFirstChild("CurrentPower"); local sm2 = ls2:FindFirstChild("StomachMax")
		if not cp2 then return end
		local gutMax = sm2 and sm2.Value or want or 0
		local applied = infiniteGut and gutMax or math.clamp(math.floor(want), 0, gutMax) -- Infinite Gut -> FULL; else clamp saved
		cp2.Value = applied
		lastMeter[player] = applied
		pcall(function() RegenEvent:FireClient(player, 0, applied, gutMax) end) -- replicate to the client's gas meter UI
		print(string.format("[LOAD METER] player=%s saved=%s applied_to_live=%d%s", player.Name, tostring(want), applied, infiniteGut and " (INFINITE GUT: full)" or ""))
	end)
end)

-- ONE-TIME GARDEN INTRO: the client fires this the moment the cinematic finishes. We mark the flag on the
-- player (so it persists in the next save) and save immediately so a leave right after watching still counts.
-- (lando5485 is force-reset to FALSE on each load, so the intro still replays for him next join despite this.)
GardenIntroDoneEvent.OnServerEvent:Connect(function(player)
	if player:GetAttribute("SeenGardenIntro") == true then return end
	player:SetAttribute("SeenGardenIntro", true)
	print("GARDEN INTRO: "..player.Name.." finished the cinematic -> SeenGardenIntro=true (saving)")
	task.spawn(function() savePlayerData(player, "garden-intro-seen") end)
end)

Players.PlayerAdded:Connect(function(player)
	-- [BALANCE LOGGING] start the session clock + per-island timing baseline.
	sessionStartTime[player] = os.clock()
	lastIslandReachClock[player] = os.clock()
	-- highestIslandReached + HighestIsland attribute are restored by the data-load handler above;
	-- onCharacterAdded waits for that load before placing the player on their home island.
	if player.Character then onCharacterAdded(player, player.Character) end
	player.CharacterAdded:Connect(function(char) onCharacterAdded(player, char) end)
end)

Players.PlayerRemoving:Connect(function(player)
	-- [BALANCE LOGGING] compact one-line session summary you can read the whole run from.
	pcall(function()
		local ls = player:FindFirstChild("leaderstats")
		local coins   = (ls and ls:FindFirstChild("Coins") and ls.Coins.Value) or 0
		local stomach = (ls and ls:FindFirstChild("StomachMax") and ls.StomachMax.Value) or 0
		local hi = highestIslandReached[player] or 1
		local flights = sessionFlights[player] or 0
		local api = attemptsPerIsland[player] or {}
		local parts = {}
		for i = 2, 14 do if api[i] then parts[#parts+1] = "i"..i..":"..api[i] end end
		-- [BALANCE LOGGING] expanded session summary.
		local playtime = sessionStartTime[player] and math.floor(os.clock() - sessionStartTime[player]) or 0
		local totalEarned = (ls and ls:FindFirstChild("TotalCoinsEarned") and ls.TotalCoinsEarned.Value) or 0
		local foodSpent = coinsSpentOnFood[player] or 0
		local gutSpent = coinsSpentOnGuts[player] or 0
		local encounters = birdEncounters[player] or 0
		-- gut purchases list (name @ islandN, t=Xs, flight#)
		local gp = gutPurchases[player] or {}
		local gpParts = {}
		for _, g in ipairs(gp) do gpParts[#gpParts+1] = string.format("%s@i%d(t=%ds,flight#%d)", g.name, g.island, g.time, g.flight) end
		-- server-wide events fired list
		local evParts = {}
		for name, c in pairs(eventsFiredTally) do evParts[#evParts+1] = name..":"..c end
		print("SESSION SUMMARY: highestIsland="..hi..", total playtime="..playtime.."s, total flights="..flights..", attempts per island=["..table.concat(parts, ", ").."], final coins="..coins..", totalCoinsEarned="..totalEarned..", spentOnFood="..foodSpent..", spentOnGuts="..gutSpent..", stomach="..stomach..", gutsBought=["..table.concat(gpParts, ", ").."], serverEventsFired="..eventsFiredCount.." ["..table.concat(evParts, ", ").."], birdEncounters="..encounters)
		-- [BALANCE LOGGING] clean per-island TABLE: island | attempts | time(s) | gut used | save-gate?
		print("SESSION TABLE | island | attempts | time(s) | gutMax | save-gate(save/reach)")
		local irt = islandReachTime[player] or {}
		local sgf = saveGateFlights[player] or {}
		local rff = reachFlights[player] or {}
		local gai = gutAtIsland[player] or {}
		for i = 2, 14 do
			if api[i] then
				print(string.format("  i%-2d | att=%-3d | t=%-7.1f | gutMax=%-5d | %d/%d",
					i, api[i] or 0, irt[i] or 0, gai[i] or 0, sgf[i] or 0, rff[i] or 0))
			end
		end
	end)
	highestIslandReached[player] = nil
	hasChosenIsland[player] = nil
	spawnIsland[player] = nil
	sessionFlights[player] = nil
	flightsSinceNewIsland[player] = nil
	attemptsPerIsland[player] = nil
	-- [BALANCE LOGGING] clean up the added tracking tables.
	sessionStartTime[player] = nil
	islandReachTime[player] = nil
	lastIslandReachClock[player] = nil
	coinsAtLastIsland[player] = nil
	islandCoinsEarned[player] = nil
	coinsSpentOnFood[player] = nil
	coinsSpentOnGuts[player] = nil
	gutPurchases[player] = nil
	gutBoughtSinceIsland[player] = nil
	saveGateFlights[player] = nil
	reachFlights[player] = nil
	saveGateAccum[player] = nil
	reachAccum[player] = nil
	gutAtIsland[player] = nil
	birdEncounters[player] = nil
	flightsOfSaving[player] = nil
end)

-- Player tapped the "Return to Island N" button. Server-authoritative: only teleport if they
-- really are below their home island, and only ever to that island's real Stand part.
ReturnToIslandEvent.OnServerEvent:Connect(function(player)
	local hi = highestIslandReached[player] or 1
	if hi <= 1 then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local sd = standData[hi]
	if not sd then print("RETURN: "..player.Name.." tapped but island "..hi.." stand not loaded yet") return end
	-- Safety button: ALWAYS honor the tap (the button is only shown while the player is below home,
	-- so this can't skip progress — it just returns them to the highest island they already reached).
	-- Previously this re-checked the below-margin condition and could silently no-op; removed so the
	-- tap reliably teleports. teleportToHome places them on the stand, on the ground, facing it.
	teleportToHome(char, sd)
	player:SetAttribute("ReturnPromptIsland", 0)
	print("RETURN: "..player.Name.." returned to home island "..hi.." stand")
end)

-- Rocket event "Go to Island 1" button: teleport the requester to island 1's
-- stand to watch the rocket. Uses the SAME teleportToHome as Return-to-Island
-- (just always island 1). Does NOT change unlocked islands / saved progress --
-- it only moves the character; the fall-catch "Return" prompt still works.
GoToIsland1Event.OnServerEvent:Connect(function(player)
	-- GUARD: this is the ROCKET EVENT's teleport button -- only honor it WHILE the rocket event is
	-- actually running. (Server-authoritative backstop so firing the remote outside an event -- e.g. an
	-- invisible-but-clickable button -- can never teleport.) Flag is set by RocketEventManager.
	local rk = _G.BigEvents and _G.BigEvents.rocket
	if not (rk and rk.isRunning and rk.isRunning()) then
		print("GOTO1: rejected -- no rocket event running ("..player.Name..")")
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local sd = standData[1]
	if not sd then print("GOTO1: island 1 stand not loaded yet") return end
	teleportToHome(char, sd)
	print("GOTO1: "..player.Name.." teleported to island 1 for the rocket event")
end)

local detectAccum = 0
RunService.Heartbeat:Connect(function(dt)
	detectAccum = detectAccum + dt
	local doDetect = detectAccum >= 0.1
	if doDetect then detectAccum = 0 end
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChild("Humanoid")
		if hrp and hum and hum.Health > 0 then
			local hi = highestIslandReached[plr] or 1
			-- Physical landing detection (throttled): raise home base when standing on a higher island.
			-- This is the ONE authoritative arrival trigger — the personal welcome and the others-only
			-- broadcast both fire from here, never from peak-height/unlock.
			if doDetect and hum.FloorMaterial ~= Enum.Material.Air then
				local n = islandUnderCharacter(char)
				if n and n > hi then
					highestIslandReached[plr] = n
					hi = n
					plr:SetAttribute("HighestIsland", n)
					-- [BALANCE LOGGING] attempts to reach this island = flights since the previous new island.
					local att = flightsSinceNewIsland[plr] or 0
					attemptsPerIsland[plr] = attemptsPerIsland[plr] or {}
					attemptsPerIsland[plr][n] = att
					flightsSinceNewIsland[plr] = 0
					-- [BALANCE LOGGING] per-island metrics: real time, coins earned, save-gate vs reach breakdown,
					-- the gut used, and whether a gut was purchased on the way to this island.
					local nowClock = os.clock()
					local secsToReach = lastIslandReachClock[plr] and (nowClock - lastIslandReachClock[plr]) or 0
					lastIslandReachClock[plr] = nowClock
					islandReachTime[plr] = islandReachTime[plr] or {}
					islandReachTime[plr][n] = sessionStartTime[plr] and (nowClock - sessionStartTime[plr]) or 0
					local lsR = plr:FindFirstChild("leaderstats")
					local tceVal = (lsR and lsR:FindFirstChild("TotalCoinsEarned") and lsR.TotalCoinsEarned.Value) or 0
					local prevTce = coinsAtLastIsland[plr] or 0
					local earnedThis = tceVal - prevTce
					coinsAtLastIsland[plr] = tceVal
					islandCoinsEarned[plr] = islandCoinsEarned[plr] or {}
					islandCoinsEarned[plr][n] = earnedThis
					local sg = saveGateAccum[plr] or 0
					local rf = reachAccum[plr] or 0
					saveGateFlights[plr] = saveGateFlights[plr] or {}; saveGateFlights[plr][n] = sg
					reachFlights[plr] = reachFlights[plr] or {}; reachFlights[plr][n] = rf
					saveGateAccum[plr] = 0; reachAccum[plr] = 0
					local gutMaxNow = (lsR and lsR:FindFirstChild("StomachMax") and lsR.StomachMax.Value) or 0
					gutAtIsland[plr] = gutAtIsland[plr] or {}; gutAtIsland[plr][n] = gutMaxNow
					local gutNameNow = "Gut"
					for _, t in ipairs(stomachTiers) do if t.maxPower == gutMaxNow then gutNameNow = t.name; break end end
					local gutBought = gutBoughtSinceIsland[plr] and true or false
					gutBoughtSinceIsland[plr] = false
					print(string.format("ISLAND REACHED: island %d reached after %d attempts (%d save-gate, %d trying-to-reach) | time=%.1fs | coinsEarnedToHere=%d | gutUsed=%s (maxPower=%d) | gutBoughtOnWay=%s",
						n, att, sg, rf, secsToReach, earnedThis, gutNameNow, gutMaxNow, tostring(gutBought)))
					print("HOME BASE: "..plr.Name.." landed on island "..n)
					local iname = ISLAND_DISPLAY_NAMES[n] or ("Island "..n)
					-- Personal "You reached [Island]!" welcome to the lander only.
					pcall(function() WelcomeEvent:FireClient(plr, n, iname) end)
					-- "[username] landed on [island]" broadcast to EVERYONE EXCEPT the lander.
					for _, other in ipairs(Players:GetPlayers()) do
						if other ~= plr then
							pcall(function() AnnouncementEvent:FireClient(other, plr.Name, n, iname) end)
						end
					end
				end
			end
			-- Below-home prompt (every frame): show the "Return to Island N" button WHENEVER the
			-- player is below their highest-reached island's Y — flying, falling, or standing.
			-- Hidden only when on/above that island. (Client reads the ReturnPromptIsland
			-- attribute.) No auto-teleport — the player chooses to tap the button.
			local want = 0
			if hi > 1 then
				local sd = standData[hi]
				if sd and hrp.Position.Y < sd.y - CATCH_MARGIN then
					want = hi
				end
			end
			if (plr:GetAttribute("ReturnPromptIsland") or 0) ~= want then
				plr:SetAttribute("ReturnPromptIsland", want)
			end
		end
	end
end)

local PAE_productNames = {
	[PRODUCT_IDS.TwoXOneHour]    = "2x Power 1 Hour",
	[PRODUCT_IDS.MidAirRecharge] = "Mid-Air Recharge",
	[PRODUCT_IDS.SkipIsland]     = "Skip Island",
	[PRODUCT_IDS.BirdNuke]       = "Bird Nuke",
}
local function fireProductAnnouncement(player, productId)
	local PAE = RS:FindFirstChild("PurchaseAnnouncementEvent")
	if PAE then pcall(function() PAE:FireAllClients(player.Name, PAE_productNames[productId] or "an item", false) end) end
end

-- The offensive Bird Nuke, called by ProcessReceipt / the test hooks on a real purchase. OFFENSIVE:
-- broadcast to EVERYONE; the BUYER is spared (their client returns early on the event). Each VICTIM's
-- client KILLS its own character (Humanoid.Health = 0) and, on the normal Roblox respawn, restores its
-- fart meter to THIS flight's LAUNCH amount (the launch-snapshot rule — _G.beamLaunchSnapshot.power —
-- the same data the planes/junk/beams hazards use). The server intentionally does NOT teleport anyone
-- or zero CurrentPower: the existing death->respawn flow (onCharacterAdded's Died handler) already
-- reloads each victim at their home island, and leaving CurrentPower at its mid-flight launch value
-- lets the client restore stick on BOTH sides via the decrease-only landing sync. Server-authoritative
-- on WHO is nuked: only the server fires this event, and the buyer is excluded client-side.
local function triggerBirdNuke(buyer)
	if not buyer then return end
	-- Fire to all clients NOW: boom sound + swarm + nuke visual play immediately; each VICTIM's client
	-- kills its own character on this same event (the buyer is spared client-side).
	if BirdNukeEvent then
		pcall(function() BirdNukeEvent:FireAllClients(buyer.Name) end)
	end
	-- Purchase banner ("[name] bought Bird Nuke!") — same as before.
	fireProductAnnouncement(buyer, PRODUCT_IDS.BirdNuke)
	-- The server does NOT teleport anyone or zero CurrentPower here. Each victim's client KILLS its own
	-- character on this event and the existing death->respawn flow (onCharacterAdded's Died handler)
	-- reloads them at their home island, so "everyone sent home" is preserved by the respawn itself.
	-- Leaving CurrentPower untouched (it still holds the launch value mid-flight) is what lets the
	-- client's launch-amount restore stick on BOTH sides via the decrease-only landing sync.
end

-- Skip Island effect, factored so the real product (SkipIslandEvent, fired by the hotbar) and the
-- test hooks share ONE path. Teleports the player to the next island ABOVE their current highest
-- (e.g. 6 -> 7), repeatable up to island 14, and moves their home base (highestIslandReached) +
-- Island stat to the new island so respawn/return and unlocks all follow. Server-authoritative.
local function triggerSkipIsland(player)
	if not player then return end
	if DISABLE_PERKS_FOR_BALANCE then print("SKIP: ignored — DISABLE_PERKS_FOR_BALANCE is on"); return end -- [BALANCE] no Skip Island during the no-perks test
	local current = highestIslandReached[player] or 1
	if current >= 14 then print("SKIP: "..player.Name.." already at top island 14"); return end
	local target = current + 1
	highestIslandReached[player] = target
	player:SetAttribute("HighestIsland", target)
	-- Keep the Island leaderstat (drives food-shop unlocks / UI) at least at the new island.
	local ls = player:FindFirstChild("leaderstats")
	local island = ls and ls:FindFirstChild("Island")
	if island and island.Value < target then island.Value = target end
	-- Teleport onto the new island's home Stand — same system as Return-to-Island / respawn.
	local sd = standData[target]
	local char = player.Character
	if sd and char then
		print("SKIP: "..player.Name.." -> island "..target)
		pcall(function() teleportToHome(char, sd) end)
	else
		print("SKIP: "..player.Name.." set to island "..target.." but no teleport (stand="..tostring(sd~=nil)..", char="..tostring(char~=nil)..")")
	end
end

-- TEST: jump straight to ANY island (chat "goisland<N>", N=1..14). Mirrors triggerSkipIsland's bookkeeping but
-- to an arbitrary island: raises home base (highestIslandReached) + HighestIsland attr + Island stat to at least N
-- so respawn/return/shop follow, then teleports onto that island's home stand. Server-authoritative; test users only.
local function goToIsland(player, n)
	if not player then return end
	n = math.clamp(math.floor(tonumber(n) or 0), 1, 14)
	if (highestIslandReached[player] or 1) < n then
		highestIslandReached[player] = n
		player:SetAttribute("HighestIsland", n)
	end
	local ls = player:FindFirstChild("leaderstats")
	local island = ls and ls:FindFirstChild("Island")
	if island and island.Value < n then island.Value = n end
	local sd = standData[n]
	local char = player.Character
	if sd and char then
		print("[GOISLAND] " .. player.Name .. " -> island " .. n)
		pcall(function() teleportToHome(char, sd) end)
	else
		print("[GOISLAND] " .. player.Name .. " island " .. n .. " not ready (stand=" .. tostring(sd ~= nil) .. ", char=" .. tostring(char ~= nil) .. ")")
	end
end

-- Real Skip Island product (hotbar): teleport to the next island + move home base.
SkipIslandEvent.OnServerEvent:Connect(function(player) triggerSkipIsland(player) end)

-- Mid-Air Recharge REFILL effect — factored so the REAL product (ProcessReceipt) and the TEST hook below
-- call ONE path (no duplicated logic). Sets the server CurrentPower to the full gut max (StomachMax) so
-- the 100% refill STICKS through the decrease-only LandingEvent sync, then fires the client `rechargeNow`
-- so the client refills its display (a mid-flight-paused player stays frozen with a full meter). isTest=true
-- also sets `rechargeTest` so the client refills its display even when NOT paused — letting the refill be
-- confirmed in Studio without a real purchase. (Real purchases never pass isTest.)
local function triggerMidAirRecharge(player, isTest)
	if not player then return end
	local cur = player:GetAttribute("MidAirRechargeCount") or 0
	player:SetAttribute("MidAirRechargeCount", cur + 1)
	local ls = player:FindFirstChild("leaderstats")
	local cp = ls and ls:FindFirstChild("CurrentPower")
	local sm = ls and ls:FindFirstChild("StomachMax")
	if cp and sm then cp.Value = sm.Value end -- server meter -> 100% (gut max); a PAID increase, like a food buy
	if GamepassEvent then
		pcall(function() GamepassEvent:FireClient(player, {midAirRecharge = cur + 1, rechargeNow = true, rechargeTest = isTest and true or nil}) end)
	end
	if isTest then
		print(string.format("[TEST RECHARGE] %s -> CurrentPower set to %d (gut max); client rechargeNow fired", player.Name, (cp and cp.Value) or -1))
	end
end

-- (Pre-launch cleanup: the [TESTING ONLY] Bird Nuke "/nuke" + _G.testBirdNuke and Mid-Air Recharge
-- "/recharge" + _G.testMidAirRecharge manual triggers were removed. triggerBirdNuke and
-- triggerMidAirRecharge remain — they are the REAL effects called by ProcessReceipt below.)

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	if info.ProductId == PRODUCT_IDS.TwoXOneHour then
		player:SetAttribute("TwoXHourExpiry", os.time() + 3600)
		if GamepassEvent then
			pcall(function() GamepassEvent:FireClient(player, {twoXHourExpiry=os.time()+3600}) end)
		end
		fireProductAnnouncement(player, info.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif info.ProductId == PRODUCT_IDS.MidAirRecharge then
		-- Refill via the shared path: bumps MidAirRechargeCount, sets the server CurrentPower to the gut
		-- max (so the 100% STICKS past the decrease-only landing sync), and fires the client rechargeNow
		-- refill. (No isTest -> real-purchase behavior: client refills only while mid-flight-paused.)
		triggerMidAirRecharge(player)
		fireProductAnnouncement(player, info.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif info.ProductId == PRODUCT_IDS.SkipIsland then
		-- AUTO-SKIP ON PURCHASE: perform the skip IMMEDIATELY here via the SAME triggerSkipIsland the SKIP
		-- hotbar button used to call — purchase now = instant skip, no second button press. We intentionally
		-- NO LONGER fire the {skipIsland=...} client flag, so no consumable "charge" is granted: the SKIP
		-- hotbar slot stays at 0 and is inert (its click guard needs skipIsland>0, and the hotbar only shows
		-- when a charge exists), so the second step is bypassed. The skip BEHAVIOR is unchanged.
		local cur = player:GetAttribute("SkipIslandCount") or 0
		player:SetAttribute("SkipIslandCount", cur + 1) -- lifetime purchase counter only; no longer a button charge
		triggerSkipIsland(player)
		fireProductAnnouncement(player, info.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif info.ProductId == PRODUCT_IDS.BirdNuke then
		-- Real purchase: run the offensive nuke (swarm + every other player dies & respawns home + banner).
		triggerBirdNuke(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- PET upgrade Developer Product (cosmetic-only): PetSystem handles it + levels up the player's pending pet.
	if _G.petsHandleReceipt then
		local granted = false
		pcall(function() granted = _G.petsHandleReceipt(player, info.ProductId) end)
		if granted then return Enum.ProductPurchaseDecision.PurchaseGranted end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if not wasPurchased then return end
	local gpData = {}
	if passId == GAMEPASS_IDS.TwoXForever and not FORCE_NO_2X then -- [NOSAVE TEST] don't grant 2x while forced un-owned. REMOVE BEFORE LAUNCH.
		player:SetAttribute("HasTwoXForever", true); gpData.twoXForever = true
	elseif passId == GAMEPASS_IDS.GlitterTrail then
		player:SetAttribute("HasGlitterTrail", true); gpData.glitterTrail = true
	elseif passId == GAMEPASS_IDS.InfiniteGut then
		applyInfiniteGut(player) -- gut becomes UNLIMITED immediately; effect is the StomachMax (+StomachUpdateEvent), so no gpData client flag is needed
	end
	if GamepassEvent and next(gpData) then
		pcall(function() GamepassEvent:FireClient(player, gpData) end)
	end
	local passNames = {[GAMEPASS_IDS.TwoXForever]="2x Fart Power Forever",[GAMEPASS_IDS.GlitterTrail]="Glitter Fart Trail",[GAMEPASS_IDS.InfiniteGut]="Infinite Gut"}
	local passName = passNames[passId] or "a gamepass"
	local PAE = RS:FindFirstChild("PurchaseAnnouncementEvent")
	if PAE then pcall(function() PAE:FireAllClients(player.Name, passName, true) end) end
end)

-- ===== SERVER-WIDE EVENT LOOP =====
local eventPool = {
	{name="FART_STORM",   dispName="\xF0\x9F\x92\xA8 FART STORM",   weight=15, dur=7, msg="\xF0\x9F\x92\xA8 FART STORM! Everyone flies faster for 7 seconds!",       r=100,g=200,b=255},
	{name="COIN_RUSH",    dispName="\xF0\x9F\xAA\x99 COIN RUSH",    weight=15, dur=7, msg="\xF0\x9F\xAA\x99 COIN RUSH! Double coins for 7 seconds!",                  r=255,g=200,b=0},
	-- DISPLAY-NAME-ONLY rename: shown to players as "HIGH GRAVITY". The internal key
	-- stays "LOW_GRAVITY" so the client handler (EventClient ~938) and all mechanics
	-- (speed/gas-drain multipliers, weight, 10s duration) are completely unchanged.
	{name="LOW_GRAVITY",  dispName="\xF0\x9F\x8C\x99 HIGH GRAVITY",  weight=15, dur=10, msg="\xF0\x9F\x8C\x99 HIGH GRAVITY! Float like a cloud for 10 seconds!",        r=150,g=100,b=255},
	{name="POWER_SURGE",  dispName="\xE2\x9A\xA1 POWER SURGE",      weight=15, dur=20, msg="\xE2\x9A\xA1 POWER SURGE! Fly higher than ever for 20 seconds!",          r=255,g=255,b=0},
	{name="RING_FEVER",   dispName="\xF0\x9F\x8E\xAF RING FEVER",   weight=15, dur=30, msg="\xF0\x9F\x8E\xAF RING FEVER! Massive ring bonuses for 30 seconds!",       r=255,g=100,b=200},
	{name="THUNDERSTORM", dispName="\xe2\x9b\x88 THUNDERSTORM",     weight=15, dur=20, msg="\xe2\x9b\x88\xef\xb8\x8f THUNDERSTORM! Hard to see!",                    r=50, g=50, b=80},
	{name="WINDSTORM",    dispName="\xF0\x9F\x92\xA8 WIND STORM",   weight=10, dur=20, msg="\xF0\x9F\x92\xA8 WIND STORM! Fighting the wind!",                        r=100,g=150,b=200},
}

local function pickRandomEvent()
	return eventPool[math.random(1, #eventPool)]
end

-- Single unified event loop: random event every 4 minutes
task.spawn(function()
	if DISABLE_EVENTS then print("EVENTS DISABLED (DISABLE_EVENTS) — no random server events will fire") return end
	task.wait(240)
	while true do
		local ev = pickRandomEvent()
		-- [BALANCE LOGGING] count server events fired (overall + per-name) for the session summary.
		eventsFiredCount = eventsFiredCount + 1
		eventsFiredTally[ev.name] = (eventsFiredTally[ev.name] or 0) + 1
		print("NEXT EVENT:", ev.name, "(server events fired so far:", eventsFiredCount..")")
		pcall(function()
			ServerEventNotify:FireAllClients(ev.name, ev.dispName, ev.dur, ev.msg, Color3.fromRGB(ev.r, ev.g, ev.b))
		end)
		task.wait(ev.dur + 2)
		pcall(function()
			ServerEventNotify:FireAllClients("END", "", 0, "", Color3.new(1,1,1))
		end)
		task.wait(240)
	end
end)

-- \xE2\x9A\xA0 TEST COMMAND: /thunderstorm triggers the storm on demand. REMOVE BEFORE LAUNCH.
-- Lets a test account fire the THUNDERSTORM big event instantly instead of waiting for the timer.
-- It uses the EXISTING event path -- the same ServerEventNotify FireAllClients + scheduled "END"
-- the random loop above uses -- so the storm runs EXACTLY like normal, just on command. This does
-- NOT change the storm or the scheduler's normal behavior (the loop above is untouched and keeps
-- running on its own timer). Gated to the test accounts so random players can't trigger it.
-- \xE2\x9A\xA0 TEST COMMANDS allowed for: lando5485, Broskie310111, itsmaddmax2. REMOVE BEFORE LAUNCH.
-- (The shared ALLOWED_TEST_USERS list + isAllowedTestUser() are defined near the top of this file so the
-- island-select all-unlock and these chat commands can both use them. /thunderstorm checks it below.)
local function fireThunderstormNow()
	local ev
	for _, e in ipairs(eventPool) do if e.name == "THUNDERSTORM" then ev = e break end end
	if not ev then return end
	pcall(function()
		ServerEventNotify:FireAllClients(ev.name, ev.dispName, ev.dur, ev.msg, Color3.fromRGB(ev.r, ev.g, ev.b))
	end)
	task.delay(ev.dur + 2, function() -- end it after its duration, exactly like the random loop does
		pcall(function() ServerEventNotify:FireAllClients("END", "", 0, "", Color3.new(1,1,1)) end)
	end)
end
-- \xE2\x9A\xA0 TEST: quick "get<tier>gut" chat commands to grab any gut tier instantly (for belly/flight testing).
-- REMOVE BEFORE LAUNCH. Example: type  gettinygut  (or /gettinygut) in chat.
local GUT_CMDS = {
	gettinygut = "Tiny Gut", getsmallgut = "Small Gut", getmediumgut = "Medium Gut",
	getlargegut = "Large Gut", getxlgut = "XL Gut", getirongut = "Iron Gut", getinfinitegut = "Infinite Gut",
}
local function giveGut(player, gutName)
	local tier; for _, t in ipairs(stomachTiers) do if t.name == gutName then tier = t; break end end
	if not tier then return end
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local sm = ls:FindFirstChild("StomachMax"); if not sm then return end
	sm.Value = tier.maxPower
	local cp = ls:FindFirstChild("CurrentPower")
	if cp then cp.Value = math.min(cp.Value, tier.maxPower) end -- carry/clamp current gas to the new tank
	if tier.maxPower >= INFINITE_GUT_MAX then player:SetAttribute("HasInfiniteGut", true) end
	pcall(function() StomachUpdateEvent:FireClient(player, tier.maxPower, tier.name) end)
	pcall(function() RegenEvent:FireClient(player, 0, cp and cp.Value or 0, tier.maxPower) end)
	print("[TEST] gave "..player.Name.." "..tier.name.." (maxPower "..tier.maxPower..")")
end

local function hookTestStormChat(player) -- \xE2\x9A\xA0 TEST: /thunderstorm chat trigger. REMOVE BEFORE LAUNCH.
	-- \xE2\x9A\xA0 TEST: on lando5485's join, print their userId so it can be hardcoded by id later. REMOVE BEFORE LAUNCH.
	if string.lower(player.Name) == "lando5485" then
		print("[TEST] lando5485 joined - userId = " .. player.UserId .. " (can hardcode this in the allowed list)")
	end
	player.Chatted:Connect(function(msg)
		local cmd = string.lower(tostring(msg or "")):match("^%s*(.-)%s*$") -- trim + lowercase
		if cmd == "/thunderstorm" then
			if not isAllowedTestUser(player) then return end -- shared test-user allow-list (lando5485 + the two test accounts)
			print("[TEST] /thunderstorm command used by " .. player.Name .. " - firing thunderstorm event. REMOVE BEFORE LAUNCH.")
			fireThunderstormNow()
		elseif cmd == "/allpets" then -- \xE2\x9A\xA0 TEST COMMAND /allpets - grants all pets to test accounts. REMOVE BEFORE LAUNCH.
			if not isAllowedTestUser(player) then return end -- same allow-list as the other test commands (non-test players: ignored)
			if _G.petsGrantAll then pcall(function() _G.petsGrantAll(player) end) end -- grant every pet (PetSystem owns the data); they appear owned + equippable instantly
			print("[TEST] /allpets used by " .. player.Name .. " - granted all pets. REMOVE BEFORE LAUNCH.")
		elseif cmd == "/rarepets" then -- \xE2\x9A\xA0 TEST COMMAND /rarepets - grants every pet as its RARE variant. REMOVE BEFORE LAUNCH.
			if not isAllowedTestUser(player) then return end
			if _G.petsGrantRare then pcall(function() _G.petsGrantRare(player) end) end -- grant all pets RARE + pre-maxed so all 5 rare looks are visible
			print("[TEST] /rarepets used by " .. player.Name .. " - granted all RARE pets. REMOVE BEFORE LAUNCH.")
		elseif cmd:match("^/?goisland%s*%d+$") then -- \xE2\x9A\xA0 TEST: "goisland1".."goisland14" -> teleport to that island (slash optional). REMOVE BEFORE LAUNCH.
			if not isAllowedTestUser(player) then return end
			goToIsland(player, cmd:match("(%d+)"))
		else -- \xE2\x9A\xA0 TEST: instant gut tiers — "gettinygut", "getsmallgut", ... (slash optional). REMOVE BEFORE LAUNCH.
			local gutName = GUT_CMDS[cmd] or GUT_CMDS[(cmd:gsub("^/", ""))]
			if gutName then
				if not isAllowedTestUser(player) then return end
				giveGut(player, gutName)
			end
		end
	end)
end
for _, p in ipairs(Players:GetPlayers()) do hookTestStormChat(p) end
Players.PlayerAdded:Connect(hookTestStormChat)

-- (Daily Rewards claim handler removed.)

LandingEvent.OnServerEvent:Connect(function(player, remainingPower, birdHit, realAttempt)
	-- [LOGGING ACCURACY] Count this landing as a flight ATTEMPT only when the client reports a REAL flight
	-- (genuine fart-launch + airtime > 3s). This excludes spawn falls, post-teleport settles, walk-offs, and
	-- aborted near-zero launches. ALL attempt counters (session, since-new-island, saving, save-gate/reach,
	-- bird) are gated together so they stay mutually consistent (attempts == saveGate + reach).
	if realAttempt then
		sessionFlights[player] = (sessionFlights[player] or 0) + 1
		flightsSinceNewIsland[player] = (flightsSinceNewIsland[player] or 0) + 1
		flightsOfSaving[player] = (flightsOfSaving[player] or 0) + 1
		-- [BALANCE LOGGING] bird encounter flag passed from the client (remainingPower stays the first arg).
		if birdHit then birdEncounters[player] = (birdEncounters[player] or 0) + 1 end
		-- [BALANCE LOGGING] classify this attempt as a SAVE-GATE flight (current gut physically can't reach the
		-- next island: 50 + gutMax*14 < nextIslandY) or a TRYING-TO-REACH flight. Tallied per next-island.
		pcall(function()
			local lsd = player:FindFirstChild("leaderstats")
			local smv = lsd and lsd:FindFirstChild("StomachMax") and lsd.StomachMax.Value or 0
			local hi = highestIslandReached[player] or 1
			local nextN = math.min(hi + 1, 14)
			local nextY = ISLAND_POSITIONS[nextN] and ISLAND_POSITIONS[nextN].y or math.huge
			local gutCeil = 50 + smv * 14
			if gutCeil < nextY then
				saveGateAccum[player] = (saveGateAccum[player] or 0) + 1
			else
				reachAccum[player] = (reachAccum[player] or 0) + 1
			end
		end)
	end
	-- Landing keeps whatever gas the player did NOT burn in flight. The client reports its
	-- actual remaining power; sync the server to it so the next purchase validates against the
	-- real remaining space. Only ever allow this to DECREASE CurrentPower (power is added solely
	-- by server-validated BuyFood), so it can't be exploited to inflate power. If the player
	-- drained the whole tank the reported value is naturally 0.
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local cp = ls:FindFirstChild("CurrentPower")
	local sm = ls:FindFirstChild("StomachMax")
	if not cp then return end
	local reported = math.floor(tonumber(remainingPower) or 0)
	local newVal = math.clamp(reported, 0, cp.Value)
	if newVal ~= cp.Value then
		cp.Value = newVal
		pcall(function() RegenEvent:FireClient(player, 0, newVal, sm and sm.Value or 100) end)
	end
	lastMeter[player] = cp.Value -- snapshot the last-known live meter for SAVE (so a later respawn-zero can't persist a stale 0)
end)

BuyStomachEvent.OnServerEvent:Connect(function(player, newMax, cost)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local stomachMaxStat = ls:FindFirstChild("StomachMax")
	if not coins or not stomachMaxStat then return end
	local newMaxN = tonumber(newMax) or 0
	local costN   = tonumber(cost)   or 0
	-- [TEST] TEST_FULL_DATA: free switch to ANY real tier (ignore cost + coins) so every tier's reach
	-- can be sampled in one run. Still validates the maxPower is a real tier; changes nothing about flight.
	if TEST_FULL_DATA then
		if newMaxN <= 0 then return end
		local ok = false
		for _, tier in ipairs(stomachTiers) do if tier.maxPower == newMaxN then ok = true; break end end
		if not ok then return end
		stomachMaxStat.Value = newMaxN
		local cp = ls:FindFirstChild("CurrentPower"); local carried = 0
		if cp then cp.Value = math.min(cp.Value, newMaxN); carried = cp.Value end -- carry over power (clamp to new max)
		pcall(function() RegenEvent:FireClient(player, 0, carried, newMaxN) end)
		local nameStr = "Gut"
		for _, t in ipairs(stomachTiers) do if t.maxPower == newMaxN then nameStr = t.name; break end end
		pcall(function() StomachUpdateEvent:FireClient(player, newMaxN, nameStr) end)
		print("TEST_FULL_DATA: "..player.Name.." switched to "..nameStr.." (maxPower "..newMaxN..") for FREE")
		return
	end
	if costN <= 0 or newMaxN <= 0 then return end
	local valid = false
	for _, tier in ipairs(stomachTiers) do
		if tier.maxPower == newMaxN and tier.cost == costN and not tier.robux then
			valid = true; break
		end
	end
	if not valid or coins.Value < costN then return end
	local coinsBeforeBuy = coins.Value -- [BALANCE LOGGING] snapshot before deducting
	coins.Value = coins.Value - costN
	coinsSpentOnGuts[player] = (coinsSpentOnGuts[player] or 0) + costN -- [BALANCE LOGGING] track gut spend
	stomachMaxStat.Value = newMaxN
	-- CARRY OVER the power already in the tank (don't reset). Only the tank's MAX grows; the current
	-- fill stays. Clamp to the new max as a safety (new max is always bigger, so this won't trigger).
	local cp = ls:FindFirstChild("CurrentPower")
	local carried = 0
	if cp then cp.Value = math.min(cp.Value, newMaxN); carried = cp.Value end
	pcall(function() RegenEvent:FireClient(player, 0, carried, newMaxN) end)
	local tierNameStr = "Gut"
	for _, t in ipairs(stomachTiers) do
		if t.maxPower == newMaxN then tierNameStr = t.name; break end
	end
	pcall(function() StomachUpdateEvent:FireClient(player, newMaxN, tierNameStr) end)
	-- [BALANCE LOGGING] record this gut purchase + print a labeled line.
	local lsIsland = ls:FindFirstChild("Island")
	local atIsland = (lsIsland and lsIsland.Value) or (highestIslandReached[player] or 1)
	local playtime = sessionStartTime[player] and math.floor(os.clock() - sessionStartTime[player]) or 0
	local savingFlights = flightsOfSaving[player] or 0
	local flightNum = sessionFlights[player] or 0
	gutPurchases[player] = gutPurchases[player] or {}
	table.insert(gutPurchases[player], {name=tierNameStr, island=atIsland, time=playtime, flight=flightNum})
	gutBoughtSinceIsland[player] = true -- per-island flag: a gut was bought on the way to the next island
	flightsOfSaving[player] = 0 -- reset flights-of-saving counter for the next gut
	print(string.format("BOUGHT GUT: %s for %d, at island %d, after %d flights of saving, coins before/after=%d/%d, total playtime=%ds",
		tierNameStr, costN, atIsland, savingFlights, coinsBeforeBuy, coins.Value, playtime))
end)

print("STANDS COMPLETE")
print("GAMEPASS FIXES DONE")
print("ERRORS FIXED")
print("REVERTED")
print("DONE")
