--======================================================================
-- ObjectiveHUD.client.luau   (StarterPlayerScripts)
--======================================================================
-- NEW-PLAYER ONBOARDING: one always-visible objective instruction that teaches
-- the core loop by DOING it -- buy food -> tap fart -> pop a bubble -> reach island 2.
-- Before this, the only explanation of the loop lived behind the Farmer's optional
-- ProximityPrompt (FarmerTutorial), which a player could walk straight past.
--
-- ===== IT IS A BANNER NOW. THE STANDALONE CARD IS GONE. =====
-- This script used to build its OWN ScreenGui ("ObjectiveHUD") at y=85: its own frame, its own gold-rimmed
-- CTA-green paint, its own title label, its own subtitle label, its own coin goal bar and its own breathing
-- stroke pulse. All of it is deleted. Not hidden, not left as an empty frame -- deleted, and the sweep below
-- destroys any copy of it baked into the place so nothing survives from an older build either.
--
-- The words and the subtitle are now PINNED to NotifyCenter's hero lane -- the exact
-- lane arrival banners, event titles and reward nudges use. Three things fall out of that, and all three
-- were the reason to move:
--   1. NO MORE TWO-CARDS-AT-ONCE. The directions and a hero banner were separate ScreenGuis, so a player
--      could be told two things simultaneously and read neither. One lane, one owner, always.
--   2. IT INHERITS THE GLOBAL UISCALE. ResponsiveUI scales the hero frame like every other HUD element, so
--      the directions grow and shrink with the rest of the interface instead of carrying a private 0.7
--      mobile fudge factor that agreed with nothing.
--   3. IT IS EXCLUSIVE. See below.
--
-- ===== EXCLUSIVE, AND WHAT THAT MEANS =====
-- The directions are pinned at RANK.TUTORIAL. While they are up nothing else plays: arrival cards, event
-- titles, friend/group promos, reward toasts and purchase confirmations all QUEUE. They are not dropped --
-- the moment this step COMPLETES the pin yields, everything waiting drains in priority order, and the next
-- step's directions take the slot back.
--
-- ONE THING OUTRANKS IT: the garden watering quest. While that quest is live and unfinished its step
-- directions are pinned at RANK.QUEST and simply cover these -- the player has a watering can in their hand
-- and needs to be told where to point it. Finish the watering, its pin releases, and these come straight
-- back mid-sentence. Neither side has to know about the other; the ranks do it.
--
-- The step is DERIVED from live game state every tick -- there is no stored step counter, so it is
-- self-healing (a player who dies, rejoins, or buys food out of order always sees the right instruction)
-- and needs no persistence. It retires itself for good the moment Island >= 2: reaching Broccoli Bluff IS
-- the graduation, so anyone past island 1 never sees it again.
--
-- THE BUBBLE STEP IS LOAD-BEARING, not flavour. A fresh player has 25 coins -> 5 Beans -> 40 power -> a
-- ~600-stud flight that pays back ~27 coins. Island 2 is at Y=790. So the opening loop is almost exactly
-- BREAK-EVEN and cannot reach island 2 on height coins alone -- the bubbles are the only escape, and
-- nothing else in the game mentions they exist. Both kinds are named because both matter and they are the
-- same object to look at: the GOLD ones pay a coin bonus (+18 and up) that grows with a streak multiplier,
-- the GREEN ones refill the gas meter so the climb lasts longer. The FULL-TANK coin goal below makes the
-- target legible.

-- WHY IT SAYS "BUBBLES" AND NOT "RINGS". The coin pickup stopped being a ring a long time ago -- WorldClient
-- spawnRing builds a 24-stud neon BALL. The code still calls it a ring everywhere (activeRings, ringStreak,
-- ringMultiplier) and that is fine, but the player was being told to fly through a shape that is not on
-- screen. The words follow what they can see; the internals keep their names.
--======================================================================

local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- ===== DUPLICATE GUARD + THE DEMOLITION OF THE OLD CARD =====
-- A STALE COPY OF THIS SCRIPT IS BAKED INTO THE PLACE. MenuBackdropGuard names it in both of its warnings --
-- "18 DUPLICATE LocalScript(s): ... ObjectiveHUD ..." and "8 DUPLICATE ScreenGui name(s): ... ObjectiveHUD".
-- That mattered before because two copies each built a card and the old one landed on top of the new one.
--
-- It matters MORE now. This file no longer builds a card at all, so a stale copy is the only thing that
-- could still put one on screen -- and it would sit at y=85 under the banner, which is exactly the "leftover
-- standalone GUI" this change exists to remove. So the sweep is now unconditional: EVERY ScreenGui named
-- ObjectiveHUD is destroyed, whoever built it, plus the duplicate LocalScripts that would rebuild one.
--
-- Rojo cannot fix this by editing the file, because the stale copy is not this file -- it is a separate
-- Instance in the place that Rojo never touches. So the live copy evicts it at runtime, the same way
-- Campfire and DailyTasks already do.
--
-- THIS RUNS BEFORE THE GRADUATION EARLY-RETURN BELOW, deliberately. If the player is already past island 2
-- this script bails out -- but the stale copy might not, and an un-evicted stale card would then hang on
-- screen for a graduated player with nothing left to remove it.
if _G.__ObjectiveHUD then return end
_G.__ObjectiveHUD = true

local function nukeStandaloneCard()
	local removed, guis = 0, 0
	for _, inst in ipairs(player:GetDescendants()) do
		if inst:IsA("ScreenGui") and inst.Name == "ObjectiveHUD" then
			-- No stamp test any more: we build nothing, so every one of these is a leftover.
			pcall(function() inst:Destroy() end); removed += 1; guis += 1
		elseif inst ~= script and inst:IsA("LocalScript") and inst.Name == script.Name then
			-- the running copies live under the player (PlayerScripts / PlayerGui), not in StarterPlayer
			pcall(function() inst.Disabled = true; inst:Destroy() end); removed += 1
		end
	end
	if removed > 0 then
		print(("[Objective] REMOVED the standalone tutorial GUI: %d ObjectiveHUD ScreenGui(s) + %d duplicate " ..
			"script(s) destroyed -- card, subtitle and progress bar included. The directions are a NotifyCenter " ..
			"hero banner now."):format(guis, removed - guis))
	end
	return guis
end
local sweptAtBoot = nukeStandaloneCard()
-- Load order is not ours to choose: a stale copy that starts AFTER us is only reachable once it has built
-- itself, so sweep again a few times over the first few seconds.
task.delay(1, nukeStandaloneCard); task.delay(4, nukeStandaloneCard); task.delay(9, nukeStandaloneCard)

print(("[Objective] standalone tutorial GUI REMOVED (no card, no progress-bar frame, no empty leftover -- " ..
	"%d found and destroyed at boot). Directions now render in the shared NotifyCenter hero lane. " ..
	"PRIORITY ORDER ACTIVE: garden watering directions > tutorial/achievement (exclusive) > everything else.")
	:format(sweptAtBoot))

-- BEAN_PRICE / BEAN_POWER are GONE from this file. They existed to work out what a full tank of Beans cost
-- so the directions could show a savings goal; the directions do not show one any more (see refresh), so
-- there is nothing here to keep in step with CoreClient's `foods[1]` and PlayerStats' server table.

local GOAL_ISLAND      = 2
local GOAL_ISLAND_NAME = "Broccoli Bluff"

-- The banner's paint. Same CTA green the card wore and the same green the BUY FOOD / TAP TO FART button at
-- the bottom of the screen wears, MEASURED off the live button rather than copied from its declared
-- constants (FoodRealmHud declares (50,190,60); what actually renders after its gradient is (48,162,56)).
-- The card and the button are read together -- the words say "go to the food stand", the button IS the food
-- stand -- so matching them makes the pair read as one instruction.
local CTA_GREEN   = Color3.fromRGB( 48, 162,  56)
local BAR_TRACK   = Color3.fromRGB( 24,  92,  32) -- a recessed well in the banner's OWN green, not navy
local BAR_DONE    = Color3.fromRGB( 80, 220, 100) -- they can afford a full tank
local WIN_LIME    = Color3.fromRGB(126, 217,  87) -- the house lime, for the graduation moment

local PIN_ID = "Tutorial"   -- our pin id; unpin(PIN_ID) can only ever release OUR banner

-- ===== state =====
local ls = player:WaitForChild("leaderstats", 30)
if not ls then return end
local coinsVal   = ls:WaitForChild("Coins", 10)
local islandVal  = ls:WaitForChild("Island", 10)
local powerVal   = ls:WaitForChild("CurrentPower", 10)
local stomachVal = ls:WaitForChild("StomachMax", 10)
if not (coinsVal and islandVal and powerVal and stomachVal) then return end

-- Already past island 1 -> this player has graduated; never pin anything at all.
if islandVal.Value >= GOAL_ISLAND then return end

local poppedABubble = false -- sticky across flights: once they've popped one, stop nagging about bubbles
local retired      = false
local sawFullTank  = false -- once-ever latch for the FULL TANK milestone
local liveStep     = nil   -- the step key currently pinned, so a CHANGE can be detected

-- ===== TALKING TO A NOTIFYCENTER THAT MIGHT BE AN OLDER BUILD =====
-- A stale duplicate of NotifyCenter is baked into the place and, for the first few seconds of a session, it
-- can be the one holding _G.NotifyCenter (that file reclaims the global on a loop, but there is a boot
-- window). An older table has push and nothing else. So: pin() is the ONE thing we hard-require -- without
-- it there is no lane to write to -- and the two newer calls degrade rather than vanish. A new player must
-- never end up with no directions at all because of a load-order race.
local function NC()
	local nc = _G.NotifyCenter
	if nc and nc.pin then return nc end
	return nil
end

local function yieldPin(nc)
	if nc.pinYield then nc.pinYield(PIN_ID) end
end

--- An exclusive teaching moment. Falls back to a plain high-priority push on an older NotifyCenter: it can
--- then be preempted, which is worse, but the words still reach the player in the same place.
local function tutorialBanner(nc, spec)
	if nc.tutorial then nc.tutorial(spec); return end
	spec.priority = (nc.PRIORITY and nc.PRIORITY.ISLAND) or 100
	if nc.push then pcall(nc.push, spec) end
end

-- ===== THE PET COMES FIRST, THEN THE DIRECTIONS =====
-- A brand-new player is given a free Bean Buddy on their very first join, and PetFollow plays a welcome
-- card for it. That card and these directions both want the same first ten seconds of a new player's
-- attention, and two things at once is how somebody reads neither -- so this one waits its turn.
--
-- The handshake is _G.starterWelcome, set by PetFollow: "pending" the instant the grant lands, "showing"
-- while the card is up, "done" once it has faded. Claiming "pending" at the GRANT rather than at the card
-- matters, because that card deliberately waits out the loading screen and the whole Garden Intro before
-- appearing -- without the early claim these directions would win the race every single time.
--
-- RETURNING PLAYERS ARE NOT DELAYED AT ALL. SeenGardenIntro is a saved attribute, so anyone who has played
-- before has it true and skips this entirely; only a first-join can be waiting on a welcome card. The 45s
-- ceiling is a safety net for a welcome that never resolves (an intro that never reports back, a player who
-- sits on the PLAY button) -- the directions are the more important of the two, so if anything goes wrong
-- they show anyway rather than being suppressed.
local ready = false
task.spawn(function()
	local waited = 0
	if player:GetAttribute("SeenGardenIntro") ~= true then
		while _G.starterWelcome == nil and waited < 8 do task.wait(0.25); waited = waited + 0.25 end
		while (_G.starterWelcome == "pending" or _G.starterWelcome == "showing") and waited < 45 do
			task.wait(0.25); waited = waited + 0.25
		end
	end
	ready = true
	print(("[Objective] directions pinned to the hero lane (%s, waited %.1fs)"):format(
		_G.starterWelcome == "done" and "after the starter-pet welcome"
			or (_G.starterWelcome == nil and "no starter pet -- returning player" or "welcome timed out"), waited))
end)

-- ===== the step machine: pure derivation from live state =====
-- Returns a STEP KEY plus a title and a subtitle -- nothing else; no step carries a coin goal. The key is
-- what makes "the step completed" a thing this file can detect: when it changes, the previous instruction
-- has been satisfied, and that is the moment the pin yields so everything queued behind it can play.
local function describeStep()
	local flying = _G.isFlying == true
	local power  = powerVal.Value

	if flying then
		-- EITHER bubble counts. The green gas ones and the gold coin ones are both just "a bubble" to a new
		-- player, so popping either is proof the lesson landed. Counting only the gold ones left someone who
		-- had been diving through green bubbles the whole climb still being told to go and find one.
		if (_G.ringsCollectedFlight or 0) > 0 or (_G.gasBubblesPoppedFlight or 0) > 0 then poppedABubble = true end
		if not poppedABubble then
			return "bubble",
			       "\xF0\x9F\x92\xA8 POP THE BUBBLES!"  -- the wind puff, the same glyph the in-world GAS! labels wear
		end
		return "climb",
		       "\xF0\x9F\x9A\x80 CLIMB TO " .. string.upper(GOAL_ISLAND_NAME) .. "!"
	end

	-- ===== WALK THE PLAYER DOWN THE SAME ROUTE THE ARROWS DRAW =====
	-- GardenGuideTrail lays green chevrons to the Gardener first, then re-routes to the food stand. This
	-- used to open on "BUY BEANS AT THE FOOD STAND" regardless -- so the very first thing a new player was
	-- told pointed somewhere the arrows on the floor were not going. Now the arrows lead and the words follow.
	--
	-- Read, never recomputed: the trail owns the route and is the half the player can SEE, so it is the half
	-- that gets to be right. Working the route out a second time here is how the two drift apart again.
	--
	-- nil means there are no tutorial arrows -- not started, both legs walked, or they have already flown --
	-- and it falls through to its own advice below, which is correct with nothing on the ground to follow.
	local guideStep = _G.gardenGuideStep
	if guideStep == "gardener" then
		-- Nothing here costs money, and there is nothing to buy at the other end of these arrows either.
		return "gardener",
		       "\xF0\x9F\x8C\xBB  GO SEE THE GARDENER"
	end
	if guideStep == "stand" and power <= 0 then
		-- Same destination as the fallback step below, but phrased so it agrees with the arrows that just
		-- re-routed. No coin goal and no progress fill: the instruction is "walk over there and buy beans",
		-- and a savings bar under it turns a short errand into something that looks like a grind target.
		return "stand",
		       "\xF0\x9F\x9B\x92  GO BUY SOME BEANS"
	end

	if power > 0 then
		return "fart",
		       "\xF0\x9F\x92\xA8  TAP THE FART BUTTON!"
	end

	-- Grounded and empty -> buy. Same words as the arrow leg above, so walking the route and then arriving
	-- at the end of it never reads as two different instructions.
	return "buy",
	       "\xF0\x9F\x9B\x92  GO BUY SOME BEANS"
end

--======================================================================
-- FIRST FULL TANK -- an exclusive milestone, once ever
--======================================================================
-- Filling the meter to the brim is the moment the opening loop clicks: the player has understood that food
-- IS fuel and has bought enough of it to actually reach island 2. It gets the lane to itself like every
-- other teaching moment, and it is a push (news, it happened) rather than a pin (an instruction, do this).
local function checkFullTank()
	if sawFullTank or retired then return end
	local maxP = stomachVal.Value
	if maxP <= 0 or powerVal.Value < maxP then return end
	sawFullTank = true
	local nc = NC()
	if not nc then return end
	tutorialBanner(nc, {
		top   = "\xE2\x9C\xA8 FIRST FULL TANK",
		text  = "\xE2\x9B\xBD  TANK FULL \xE2\x80\x94 " .. maxP .. " GAS!",
		sub   = "That is enough to reach " .. GOAL_ISLAND_NAME .. " \xE2\x80\x94 hold the fart button and climb",
		color = Color3.fromRGB(255, 206, 92),
		progress = 1,
		progressColor = BAR_DONE,
		progressTrack = BAR_TRACK,
		duration = 4,
	})
	print("[Objective] milestone: first FULL TANK (exclusive hero banner)")
end

--======================================================================
-- REFRESH -- repaint the pin, and yield it when a step completes
--======================================================================
local function refresh()
	if retired or not ready then return end
	local nc = NC()
	if not nc then return end

	local key, title, sub = describeStep()

	-- ===== NO SAVINGS BAR ON THE DIRECTIONS =====
	-- These steps used to carry a coin goal: a "24 / 65 for a FULL tank" tail on the subtitle and a fill
	-- under the banner. It answered a question nobody had yet. A player being walked to the food stand for
	-- the first time needs one sentence -- go there, buy beans -- and a running total next to it reads as
	-- "you cannot go yet, save up first", which is the opposite of true (25 starting coins buy five Beans
	-- and a flight). The shop shows prices; the meter shows fuel; this line just says what to do next.
	-- The one place a fill still earns its keep is the FIRST FULL TANK banner above, where it is full and
	-- it is the news.

	-- ===== THE STEP COMPLETED -> LET EVERYONE ELSE THROUGH =====
	-- A changed key means the player DID the thing the last instruction asked for. That is the one moment
	-- the exclusive hold is supposed to break: pinYield steps the banner aside, everything that queued up
	-- behind it drains in priority order, and the pin takes the slot back the instant the lane runs dry.
	-- Nothing was dropped and nothing overlapped -- the queue simply waited for a sentence to finish.
	if liveStep ~= nil and key ~= liveStep then
		print(("[Objective] step complete (%s -> %s) -- yielding the hero lane so queued banners can play")
			:format(liveStep, key))
		yieldPin(nc)
	end
	liveStep = key

	nc.pin(PIN_ID, {
		rank  = (nc.RANK and nc.RANK.TUTORIAL) or 150, -- under the garden watering quest, over everything else
		text  = title,
		sub   = sub,
		color = CTA_GREEN,
	})
end

--======================================================================
-- GRADUATION: reaching island 2 retires the directions for good
--======================================================================
local function retire()
	if retired then return end
	retired = true

	local nc = NC()
	if nc then
		-- Release the standing instruction FIRST, then say the win as its own exclusive moment. Doing it in
		-- this order means the graduation banner is a push like every other milestone (it ends on a timer
		-- and hands the lane back), instead of a pin nobody would ever release.
		if nc.unpin then nc.unpin(PIN_ID) end
		tutorialBanner(nc, {
			top   = "\xF0\x9F\x8E\x89 ISLAND 2 UNLOCKED",
			text  = string.upper(GOAL_ISLAND_NAME) .. " UNLOCKED!",
			sub   = "Now buy the food HERE to climb even higher \xE2\x80\x94 good luck!",
			color = WIN_LIME,
			duration = 5,
		})
	end
	print("[Objective] graduated -- directions retired, hero lane handed back to the normal priority order")
end

islandVal.Changed:Connect(function(v)
	if v >= GOAL_ISLAND then retire() end
end)

-- Re-derive on the signals that change the step, plus a slow tick to catch _G.isFlying
-- (a plain global, so there's nothing to listen to).
coinsVal.Changed:Connect(refresh)
powerVal.Changed:Connect(function() checkFullTank(); refresh() end)
stomachVal.Changed:Connect(refresh)

task.spawn(function()
	while not retired do
		checkFullTank()
		refresh()
		task.wait(0.2)
	end
end)
