--======================================================================
-- Achievements.client.lua  (LocalScript)
--======================================================================
-- Milestone toasts: "10,000 COINS EARNED", "HALFWAY UP", "ALL 14 ISLANDS".
--
-- The game already tracks everything these need -- lifetime coins and highest island are both live, both
-- saved, and both already on screen somewhere. What is missing is anyone ever telling the player they did
-- something. A milestone that passes in silence did not happen as far as the player is concerned.
--
-- ===== ONCE EVER, WITHOUT ANY NEW SAVE DATA =====
-- The obvious implementation is a saved "claimed" table, which means touching PlayerStats' DataStore -- and
-- BootCheck reports PlayerStats running as TWO copies, so that is the one file worth not editing.
--
-- The trick instead: every milestone below is defined against a stat that NEVER GOES DOWN. TotalCoinsEarned
-- is lifetime. HighestIsland only rises (except on rebirth, which is a deliberate reset the player chose).
-- So at join we SNAPSHOT: anything already past its threshold is marked as long-since-earned and can never
-- fire. Only a genuine crossing, watched live, produces a toast. That is once-ever semantics for free.
--
-- The one thing this cannot do is re-congratulate you after a rebirth resets your island back to 1. That is
-- correct: you have already seen "ALL 14 ISLANDS" once, and showing it again on every rebirth would make it
-- worth nothing.
--======================================================================

local Players = game:GetService("Players")
local player  = Players.LocalPlayer

if _G.__AchievementsClient then
	warn("[Achievements] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__AchievementsClient = true

--======================================================================
-- THE LADDER
--======================================================================
-- kind = "coins"  -> read from leaderstats.TotalCoinsEarned (lifetime, never falls)
-- kind = "island" -> read from the HighestIsland player attribute
local GOLD   = Color3.fromRGB(255, 206, 92)
local GREEN  = Color3.fromRGB(126, 224, 110)
local BLUE   = Color3.fromRGB(120, 186, 255)
local PURPLE = Color3.fromRGB(196, 150, 240)

local MILESTONES = {
	{ kind = "coins",  at = 1000,     text = "\xF0\x9F\xAA\x99  1,000 COINS EARNED",      colour = GREEN  },
	{ kind = "coins",  at = 10000,    text = "\xF0\x9F\xAA\x99  10,000 COINS EARNED",     colour = GREEN  },
	{ kind = "coins",  at = 100000,   text = "\xF0\x9F\xAA\x99  100,000 COINS EARNED",    colour = BLUE   },
	{ kind = "coins",  at = 1000000,  text = "\xF0\x9F\x92\x8E  A MILLION COINS EARNED",  colour = PURPLE },
	{ kind = "island", at = 3,        text = "\xF0\x9F\x8F\x9D  THREE ISLANDS CLIMBED",   colour = GREEN  },
	{ kind = "island", at = 7,        text = "\xE2\x9B\xB0  HALFWAY UP \xE2\x80\x94 PASTA PEAK", colour = BLUE   },
	{ kind = "island", at = 11,       text = "\xF0\x9F\x8D\xA8  ICE CREAM ISLE REACHED",  colour = PURPLE },
	{ kind = "island", at = 14,       text = "\xF0\x9F\x8D\x95  ALL 14 ISLANDS \xE2\x80\x94 TOP OF THE WORLD", colour = GOLD },
}

local function toast(m)
	local NC = _G.NotifyCenter
	if not (NC and NC.push) then return end
	-- ===== EXCLUSIVE, AT THE TUTORIAL TIER =====
	-- An achievement unlock is a milestone moment, and the realm's rule is that a milestone takes the hero
	-- lane ALONE: while it is up, nothing else displays or queues through.
	--
	-- These used to ride at REWARD -- deliberately, so an island milestone would queue BEHIND the island
	-- landing banner that fires at the same instant rather than racing it. That ordering still holds and is
	-- now stronger, not weaker: an exclusive banner cannot be preempted, so whichever of the two starts
	-- first plays to the end and the other follows it. They never overlap and never stack, which was the
	-- whole point of picking the lower tier before. The one thing that can cut a milestone short is the
	-- garden watering quest, which sits a tier above by design.
	local spec = {
		text = m.text,
		color = m.colour,
		exclusive = true,
		priority = (NC.PRIORITY and NC.PRIORITY.TUTORIAL) or 150,
	}
	if NC.tutorial then pcall(NC.tutorial, spec) else pcall(NC.push, spec) end
	print("[Achievements] " .. m.text .. "  (exclusive hero banner)")
end

--======================================================================
-- WATCH
--======================================================================
task.spawn(function()
	local ls
	for _ = 1, 60 do
		ls = _G.leaderstats or player:FindFirstChild("leaderstats")
		if ls and ls:FindFirstChild("TotalCoinsEarned") then break end
		task.wait(0.5)
	end
	local total = ls and ls:FindFirstChild("TotalCoinsEarned")
	if not total then warn("[Achievements] TotalCoinsEarned never arrived -- inactive"); return end

	-- HighestIsland is set during the load handshake; give it a moment rather than snapshotting a nil as 1
	-- and then immediately "awarding" island 3 to someone who loaded in on island 13.
	local waited = 0
	while player:GetAttribute("HighestIsland") == nil and waited < 15 do task.wait(0.5); waited = waited + 0.5 end

	local function readValue(kind)
		if kind == "coins" then return total.Value end
		return math.floor(tonumber(player:GetAttribute("HighestIsland")) or 1)
	end

	-- SNAPSHOT. Everything already passed is retired here and can never fire.
	local retired, armed = 0, 0
	for _, m in ipairs(MILESTONES) do
		if readValue(m.kind) >= m.at then m.done = true; retired = retired + 1 else armed = armed + 1 end
	end
	print(string.format("[Achievements] %d already earned, %d armed", retired, armed))

	local function check(kind)
		for _, m in ipairs(MILESTONES) do
			if not m.done and m.kind == kind and readValue(kind) >= m.at then
				m.done = true
				toast(m)
			end
		end
	end

	total:GetPropertyChangedSignal("Value"):Connect(function() check("coins") end)
	player:GetAttributeChangedSignal("HighestIsland"):Connect(function() check("island") end)
end)
