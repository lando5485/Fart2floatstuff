--======================================================================
-- ObjectiveBannerBridge.client.luau  (StarterPlayerScripts)  -- CandyRealm
--======================================================================
-- REPLACES the eleven home-made quest objective banners with the ONE realm banner, ranked.
--
-- This file used to be ObjectiveBannerYield, whose whole job was damage control: eleven quest scripts each
-- built their own ScreenGui at Position (0.5, 0, 0, 12) -- squarely inside the hero band -- and it hid them
-- while the hero lane was busy so the two would not draw through each other. It papered over the collision.
-- Now the collision is removed at the source: those banners never show at all, and their text goes through
-- NotifyCenter like everything else.
--
-- ===== THE ELEVEN =====
--     CandyQuestObjective ("Go talk to the Candy NPC!")   CookieQuestObjective    ParkObjective
--     BakeryObjective     SmoresObjective                 CleanupObjective        SummitObjective
--     StormObjective      JellyQuestObjective             CrystalQuestObjective   DeliveryQuestObjective
--
-- Matched by the "Objective" name suffix, which is a real convention here -- so a twelfth quest banner is
-- picked up for free the day someone adds one. Deliberately NOT matched:
--   * ObjectiveHUD -- ends in "HUD", sits at y=85, below the band. (In Candy it is a stub anyway.)
--   * FreezeHUD    -- GONE ENTIRELY as of 16 Aug. It used to be excluded here because the ScreenGui also
--                     held the FREEZING progress bar, so hiding it would have taken the bar too. Both the
--                     bar and the objective pill are now one pinned banner that CampfireFreezeQuest drives
--                     itself, at QUEST priority -- there is no ScreenGui left to exclude.
--   * TunnelBlastHUD -- its objective pill is gone the same way (pinned, QUEST priority). The ScreenGui
--                     survives because it hosts the "Back to Surface" BUTTON, which is a control, not an
--                     announcement. It never matched the "Objective" suffix anyway.
--
-- ===== WHY Enabled = false AND NOT Visible = false =====
-- Every one of those quests DRIVES its banner frame's `Visible` from its own repeating proximity loop
-- (`objFrame.Visible = vis`). Writing Visible from here would be a tug-of-war with eleven loops and would need
-- a per-frame enforcer to win. None of them ever touches the ScreenGui's `Enabled`, so that property is a free
-- lever: the owner's loop keeps updating Visible underneath, exactly as before, and this script reads it to
-- know what the quest currently wants to say. No enforcer, no per-frame work, no state of our own to desync.
--
-- ===== HOW IT USES THE RANKING SYSTEM =====
-- The objective is pushed at PRIORITY.REWARD (40) -- the "nudge, not news" rung. That is the whole point:
--
--     ISLAND   100  landing on a new island        -> PREEMPTS the objective instantly
--     PURCHASE  90  a real Robux purchase          -> preempts
--     EVENT     80  COIN RUSH / HIGH GRAVITY ...   -> preempts
--     REWARD    40  the quest objective            <- here
--
-- so "Go talk to the Candy NPC" can never sit on top of an island arrival, a purchase or a live event -- and
-- when the bigger banner finishes, the objective comes straight back on the next tick. The demoted card is
-- re-queued by NotifyCenter rather than dropped, so nothing is ever lost.
--
-- ⚠ IT DELIBERATELY DOES NOT USE NotifyCenter.pin(). A pin is a STANDING instruction and it OWNS the hero
-- slot: `if pinned or heroBlocked() then enqueue(spec)` -- everything else, island arrivals included, waits
-- behind it. An objective that is up for the entire length of a quest would starve the hero lane for minutes.
-- Re-pushing at REWARD gets the same always-on feel while staying rankable.
--
-- The re-push interval is under NotifyCenter's own 2s exact-repeat drop, so the card is refreshed before it
-- expires and reads as continuous rather than blinking.
--======================================================================

local Players = game:GetService("Players")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local POLL      = 1.0   -- seconds between checks
local SHOW_FOR  = 3.5   -- how long each push holds; longer than POLL so the card never gaps

local function isObjectiveBanner(inst)
	return inst:IsA("ScreenGui") and inst.Name:sub(-9) == "Objective"
end

-- Hide one for good. Recorded so the ChildAdded handler does not re-do work, and so a banner that was already
-- disabled for its own reasons is left exactly as it was.
local silenced = {}
local function silence(g)
	if silenced[g] then return end
	silenced[g] = true
	pcall(function() g.Enabled = false end)
end

for _, g in ipairs(PlayerGui:GetChildren()) do
	if isObjectiveBanner(g) then silence(g) end
end

-- Quest HUDs are built when their island streams in, which under StreamingEnabled happens at arbitrary times.
-- A banner born later must be silenced too, or it pops up in the hero band the first time you fly to it.
PlayerGui.ChildAdded:Connect(function(inst)
	if isObjectiveBanner(inst) then task.defer(silence, inst) end
end)
PlayerGui.ChildRemoved:Connect(function(inst) silenced[inst] = nil end)

-- The text a quest currently wants shown, or nil. Reads the frame the quest is still driving underneath the
-- disabled ScreenGui: a visible frame with a non-empty label is an active objective.
local function currentObjectiveText()
	for _, g in ipairs(PlayerGui:GetChildren()) do
		if isObjectiveBanner(g) then
			for _, frame in ipairs(g:GetChildren()) do
				if frame:IsA("GuiObject") and frame.Visible then
					for _, d in ipairs(frame:GetDescendants()) do
						if d:IsA("TextLabel") and d.Visible and d.Text and d.Text:gsub("%s", "") ~= "" then
							return d.Text
						end
					end
				end
			end
		end
	end
	return nil
end

task.spawn(function()
	-- Wait for the banner rather than assuming load order; if it never arrives there is nothing to bridge to
	-- and this script correctly does nothing except keep the old banners hidden.
	local deadline = os.clock() + 30
	while os.clock() < deadline do
		if _G.NotifyCenter and _G.NotifyCenter.push then break end
		task.wait(0.25)
	end
	if not (_G.NotifyCenter and _G.NotifyCenter.push) then
		warn("[ObjectiveBridge] NotifyCenter never published push() -- objectives will not be shown at all. "
			.. "The old banners stay hidden regardless; fix NotifyCenter rather than re-enabling them.")
		return
	end

	local N = _G.NotifyCenter
	local PRIORITY = N.PRIORITY or {}
	local MINE = PRIORITY.REWARD or 40
	local PIN_ID = "questObjective"
	local pinnedByUs = false

	-- ===== IT SITS THERE. IT DOES NOT BLINK. =====
	-- This used to re-PUSH the objective every second as a 3.5s card, so the directions were a banner being
	-- constantly re-served rather than one that was simply up. Any hiccup -- a dropped exact-repeat, a tick
	-- landing late, the text changing as progress ticked -- showed as the banner vanishing and sliding back.
	-- Directions you are still following should not do that.
	--
	-- So it PINS instead. A pin is NotifyCenter's standing instruction: it holds the slot until released, and
	-- re-pinning the same id repaints the text IN PLACE with no re-slide (see pin()), which is exactly what a
	-- progress counter ticking 2/5 -> 3/5 needs.
	--
	-- ===== ...UNLESS SOMETHING BIGGER ARRIVES =====
	-- The catch with pinning, and the reason this file originally refused to: a pin outranks EVERYTHING,
	-- island arrivals and events included, and they queue behind it. A permanent pin would starve the lane
	-- forever. queuedTop() is the way out -- it reports the highest priority currently WAITING. The moment
	-- anything above the objective is queued, the pin is released so that card can play; once the lane is
	-- clear again the objective takes the slot back on the next tick. Nothing is lost either way, because a
	-- released pin re-queues rather than being dropped.
	while true do
		local text = currentObjectiveText()

		if not text then
			-- No active objective (finished, or you walked out of its range) -- let go of the slot.
			if pinnedByUs then
				pcall(function() N.unpin(PIN_ID) end)
				pinnedByUs = false
			end
		else
			-- ⚠ laneTop, NOT queuedTop -- ASK ABOUT THE WHOLE LANE, INCLUDING WHAT IS ON SCREEN.
			-- queuedTop only reports what is WAITING, and a banner that is currently playing is not
			-- waiting. Pinning on "the queue looks empty" therefore pinned straight over a live event
			-- card, which re-queued it, which made the queue non-empty, which made this step aside and
			-- play it again -- once a second, for the whole event. COIN RUSH and POWER SURGE flickered
			-- in and out instead of announcing themselves once and leaving.
			local waiting = 0
			local top = (type(N.laneTop) == "function") and N.laneTop or N.queuedTop
			if type(top) == "function" then
				local ok, v = pcall(top)
				waiting = (ok and type(v) == "number") and v or 0
			end

			if waiting > MINE then
				-- Something more important is on screen or stuck behind us. Step aside and let it finish.
				if pinnedByUs then
					pcall(function() N.unpin(PIN_ID) end)
					pinnedByUs = false
				end
			else
				-- Free lane: hold it. Re-pinning the same id is a live text repaint, not a new banner, so
				-- this is safe to call every tick and is how the progress counter stays current.
				local ok = pcall(function()
					N.pin(PIN_ID, {
						text     = text,
						color    = Color3.fromRGB(255, 122, 190), -- candy pink, matching CandyTheme's accent
						priority = MINE,
					})
				end)
				if ok then pinnedByUs = true end
			end
		end

		task.wait(POLL)
	end
end)

print("[ObjectiveBridge] ready -- the 11 quest objective banners are hidden for good; their text now rides the "
	.. "realm banner at PRIORITY.REWARD, so island arrivals, purchases and events outrank it.")
