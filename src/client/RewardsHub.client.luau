--======================================================================
-- RewardsHub.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- REWARDS IS ONE PAGE NOW: the DAILY / TIMED / COMMUNITY hub in DailyStreak.client.luau.
--
-- ===== WHAT THIS FILE USED TO BE, AND WHY IT ISN'T ANY MORE =====
-- It built a 700x520 panel of its own with two cards on it -- DAILY (which opened the Daily Tasks panel, or
-- fired the Mystery Meteor Crate directly for a player too new to have a task list) and FREE (which opened
-- the Social Rewards panel). It was a router: a menu whose only job was to send you to another menu.
--
-- That made sense when "rewards" really were two unrelated panels. It stopped making sense the moment the
-- three-tab hub shipped, because the hub IS the rewards page -- DAILY (the 7-day login ladder), TIMED (session
-- playtime milestones) and COMMUNITY (like / favourite / group) all live on one surface with their own badges.
-- Since then this file has always forwarded to it and its own panel was never shown... but it was still BUILT,
-- at boot, on every client: a RewardsHubGui sitting in PlayerGui with a DAILY card advertising a crate the
-- rewards page no longer offers. The screen audit found it there every run.
--
-- So the panel is gone and what is left is the forward, which is the only part that was ever used.
--
-- ===== THE BADGE WENT WITH IT, AND THAT WAS THE ACTUAL BUG =====
-- The old file also published `_G.rewardsPending` as "crate claimable OR daily tasks unfinished". The hub
-- publishes the same global as "the streak, the session ladder or the community tasks have something to
-- claim". Both were assigning it, so whichever LocalScript happened to load second won -- and when this one
-- won, the MORE+ Rewards badge lit up for a crate that is not on the Rewards page, and stayed lit all day
-- because "daily tasks unfinished" is true nearly always. One owner now: the hub, which is the page the badge
-- is pointing at.
--
-- ===== WHY THE FILE IS KEPT AT ALL =====
-- Two handles have to keep working, and both are called from files that should not have to know which build
-- of the hub is live: MenuBackButton routes DailyTasksGui and SocialRewardsGui "back" to REWARDS through
-- _G.toggleRewardsHub, and RailGuard's Rewards card falls through to _G.openRewardsHub if _G.openDailyStreak
-- is not up yet. Keeping the forwards here means the hub can be renamed, rebuilt or replaced without either
-- of those breaking.
--======================================================================

local Players   = game:GetService("Players")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

--======================================================================
-- SWEEP THE OLD PANEL
--======================================================================
-- Rojo only ADDS, so the RewardsHubGui built by a stale baked-in copy of this script -- or by the version of
-- this file that shipped before today -- would go on sitting in PlayerGui with its two cards, and MenuSkin,
-- ClickOutside and the screen audit would all keep treating it as a live menu. Swept at boot and twice more,
-- because a stale copy that loads AFTER us only becomes visible once it has built itself.
local function sweepOldPanel()
	local killed = 0
	for _, g in ipairs(PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Name == "RewardsHubGui" then
			pcall(function() g:Destroy() end)
			killed += 1
		end
	end
	if killed > 0 then
		warn("[RewardsHub] removed " .. killed .. " old two-card Rewards panel(s). REWARDS is the DAILY / "
			.. "TIMED / COMMUNITY hub; delete the duplicate RewardsHub LocalScripts in Studio for good.")
	end
end
sweepOldPanel()
task.delay(2, sweepOldPanel)
task.delay(6, sweepOldPanel)

--======================================================================
-- THE FORWARDS
--======================================================================
-- The hub is built by DailyStreak.client.luau and publishes _G.openDailyStreak / _G.toggleDailyStreak. It may
-- not exist the instant this runs (it waits on its own remote), so both handles resolve LATE -- at call time,
-- not at load time -- and a caller that arrives during that window is told plainly rather than silently doing
-- nothing. There is no fallback panel to open any more, and that is on purpose: a second Rewards page is what
-- this change removes.
local function openHub(toggle)
	local open = toggle and _G.toggleDailyStreak or _G.openDailyStreak
	if open then
		pcall(open)
		return true
	end
	warn("[RewardsHub] the REWARDS hub is not up yet (DailyStreak is still waiting on its remote) -- "
		.. "nothing opened. Try again in a moment.")
	return false
end

_G.toggleRewardsHub = function() openHub(true) end
-- A card in MORE+ means "show me this", never "toggle this": if something else left the hub's Enabled flag
-- true, a toggle would close it and the card would read as dead.
_G.openRewardsHub   = function() openHub(false) end

-- _G.rewardsPending is NOT set here (see the header). The hub owns it: it is the only thing that knows what
-- the three tabs have waiting, and it is the page the MORE+ badge points at.

print("[RewardsHub] ready -- REWARDS forwards to the DAILY / TIMED / COMMUNITY hub. The old two-card router "
	.. "(Daily Rewards / Free Rewards) and its crate card are gone, and the hub owns _G.rewardsPending.")
