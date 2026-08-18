--======================================================================
-- NotifyCenter.client.luau   (StarterPlayerScripts)
--======================================================================
-- ONE OWNER FOR EVERY TRANSIENT BANNER. Before this, five separate ScreenGuis
-- (ArrivalGui, AnnounceGui, HudNoticeGui, PurchaseBanner, EventBannerGui) all
-- rested at the SAME spot -- UDim2.new(0.5,0,0,10), 500x65 -- with nothing
-- coordinating them. Land on a new island while another player announces theirs
-- and the two banners drew straight through each other.
--
-- Two ideas fix it:
--   1) LANES. Notifications are placed by KIND, not all dumped top-centre.
--      HERO   = your own big moments (top-centre, the prime slot)
--      SOCIAL = other players' news (top-left, small, never blocks you)
--   2) PRIORITY. The HERO lane shows exactly ONE banner at a time. A more
--      important one PREEMPTS a less important one; equal-or-lower ones QUEUE.
--      So "ISLAND UNLOCKED!" is never buried under "Daily Reward Ready".
--
-- The screen's vertical budget for the top-centre column is fixed and shared:
--     y  10..85   HERO banner            (this file -- 65 tall normally, up to ~75 with a subtitle + bar)
--     y 175..     Event stack            (MeteorUI / RocketUI, slot-based)
-- The old y 85..163 ObjectiveHUD card is GONE: the new-player directions are a pinned HERO banner now, so
-- there is no second onboarding card and no second progress bar. Anything new that wants top-centre space
-- must go through a lane here, or it WILL land on top of one of the two above.
--
-- ===== THE ONBOARDING PRIORITY RULE LIVES HERE =====
--     garden watering directions  >  tutorial / achievement moments  >  everything else
-- See the PRIORITY table and settle() below. Tutorial moments are EXCLUSIVE: while one is up, arrival
-- cards, event titles, friend/group promos, reward toasts and purchase confirmations all wait their turn.
--
-- Callers use _G.NotifyCenter.push{...}. CoreClient's showArrival /
-- showHudBanner / showServerEventBanner / queueAnnouncement / purchase banner
-- all delegate here, so every existing call site keeps working unchanged.
--======================================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--======================================================================
-- STALE-DUPLICATE DEFENCE  (this file is the API every other script calls)
--======================================================================
-- A SECOND, OLDER COPY OF THIS SCRIPT IS BAKED INTO THE PLACE. BootCheck names it ("NotifyCenter 2 copies")
-- and MenuBackdropGuard names its leftovers ("DUPLICATE ScreenGui name(s): NotifyHero, NotifySocial").
--
-- ===== WHY THE ORDINARY GUARD IS NOT ENOUGH HERE =====
-- Every other script in this codebase opens with `if _G.__Foo then return end`. That works when YOUR copy
-- loads second. Here the boot log shows the opposite: the Rojo copy prints at 37.386 and the stale one at
-- 37.408 -- the stale copy loads LAST, and it has never heard of any guard, so it runs to completion and
-- its final line `_G.NotifyCenter = {push, PRIORITY, isBusy}` OVERWRITES this file's table.
--
-- The visible symptom is a feature that silently does nothing: callers still find _G.NotifyCenter, so no
-- error is thrown, but the table they find is the OLD one -- it has push and nothing else. Anything added
-- here (pin/unpin) is simply absent, and the caller's `if _G.NotifyCenter.pin then` check quietly fails.
--
-- ===== SO THIS COPY RE-CLAIMS INSTEAD OF BAILING OUT =====
-- Three defences, because the stale copy's timing is not ours to control:
--   1. STAMP + SWEEP -- our GUIs carry an attribute; any NotifyHero/NotifySocial without it is a stale
--      build and gets destroyed, so banners cannot render onto an orphaned card nobody can see.
--   2. KILL THE SCRIPT -- the stale LocalScript itself is disabled and destroyed once spotted.
--   3. RE-ASSERT _G -- for the first few seconds we put our table back on a loop, so whoever writes last,
--      ours is what callers end up holding. Same tactic CoreClient uses for the bottom HUD stack.
local STAMP = "NotifyCenterOwner"

local function sweepStale()
	local removed = 0
	for _, inst in ipairs(player:GetDescendants()) do
		if inst:IsA("ScreenGui") and (inst.Name == "NotifyHero" or inst.Name == "NotifySocial")
			and not inst:GetAttribute(STAMP) then
			pcall(function() inst:Destroy() end); removed += 1
		elseif inst ~= script and inst:IsA("LocalScript") and inst.Name == script.Name then
			pcall(function() inst.Disabled = true; inst:Destroy() end); removed += 1
		end
	end
	if removed > 0 then
		warn("[NotifyCenter] evicted " .. removed .. " STALE duplicate banner gui(s)/script(s) -- the old copy "
			.. "was overwriting _G.NotifyCenter and deleting pin/unpin. Delete them in Studio for good.")
	end
end

-- ===== PRIORITIES (higher wins the HERO slot) =====
-- Exported so callers name the moment instead of hard-coding a number.
--
-- THE TOP TWO TIERS ARE NEW AND THEY ARE THE WHOLE ONBOARDING RULE:
--   QUEST    -- the garden watering quest's step directions ("go to the valve", "TAP to pour"). While that
--               quest is live and unfinished it outranks EVERYTHING, including a tutorial banner that has
--               declared itself exclusive. The moment the quest finishes its pin is released and the tier
--               stops existing for that player -- there is nothing left holding the top slot.
--   TUTORIAL -- teaching moments and milestones: the standing directions card, the first meal, the first
--               full tank, achievement unlocks, quest-step completions. These are EXCLUSIVE (see push's
--               `exclusive` flag): one of them owns the lane alone and every other banner waits.
--
-- Read as one sentence: garden watering directions > tutorial/achievement > everything else.
local PRIORITY = {
	QUEST    = 200, -- garden watering step directions -- top of the world while that quest is unfinished.
	TUTORIAL = 150, -- tutorial / milestone / achievement moments. Exclusive: nothing plays over or beside one.
	ISLAND   = 100, -- "BROCCOLI BLUFF!" -- you physically landed on a new island. The biggest moment in the game.
	PURCHASE = 90,  -- a real Robux/gamepass purchase went through -- must never be swallowed.
	EVENT    = 80,  -- a server event started (2x coins, low gravity, ...).
	REWARD   = 40,  -- "Daily Reward Ready" / "Stomach Upgrade Available" -- a nudge, not news.
	SOCIAL   = 10,  -- another player reached an island. Routed to its own lane; never competes.
}

-- Pin ranks. A pin is a STANDING INSTRUCTION (see the pin block far below); two of them can now be up at
-- once and the higher rank is the one you see. The lower one is not cancelled -- it is covered, and it comes
-- straight back when the higher one releases. That is exactly the garden-watering-over-tutorial rule.
local RANK = {
	QUEST    = PRIORITY.QUEST,
	TUTORIAL = PRIORITY.TUTORIAL,
	-- STATUS -- an AMBIENT running commentary, not an instruction: the fishing HUD's "Waiting for a bite..."
	-- -> "Something's biting! TAP!" -> "Reel it in!". It wants the banner's look and the banner's lane, but it
	-- must never do what the other two pins do and hold the queue shut, because it can be up for minutes at a
	-- time while somebody fishes.
	--
	-- So it sits at 30 -- BELOW every push priority, REWARD (40) included. Anything at all preempts it, plays,
	-- and hands the lane back (see the yield rule in push). The player gets one consistent card in one place
	-- either way; the status simply steps aside whenever the game has something real to say.
	STATUS   = 30,
}

local HERO_SHOWN  = UDim2.new(0.5, 0, 0, 10)
local HERO_HIDDEN = UDim2.new(0.5, 0, 0, -100)

-- ===== HERO lane: top-centre, one at a time =====
local heroGui = Instance.new("ScreenGui")
heroGui.Name = "NotifyHero"
heroGui.ResetOnSpawn = false
heroGui.IgnoreGuiInset = true
heroGui.DisplayOrder = 95 -- above the HUD, below shops (100) and the crate reveal
-- Stamped BEFORE parenting: the delayed sweeps destroy any unstamped NotifyHero they find, and a gui
-- parented first and stamped a line later can be caught in that gap by its own cleanup.
heroGui:SetAttribute(STAMP, true)
heroGui.Parent = playerGui

local hero = Instance.new("Frame")
hero.Name = "Hero"
hero.AnchorPoint = Vector2.new(0.5, 0)
hero.Position = HERO_HIDDEN
hero.Size = UDim2.new(0, 500, 0, 65)
hero.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
hero.BorderSizePixel = 0
hero.Visible = false
hero.Parent = heroGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = hero
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(0, 0, 0); s.Thickness = 2; s.Parent = hero
end

local heroTop = Instance.new("TextLabel")
heroTop.AnchorPoint = Vector2.new(0.5, 0)
heroTop.Position = UDim2.new(0.5, 0, 0, 6)
heroTop.Size = UDim2.new(1, -12, 0, 22)
heroTop.BackgroundTransparency = 1
heroTop.Font = Enum.Font.GothamBold
heroTop.TextColor3 = Color3.new(1, 1, 1)
heroTop.TextScaled = true
heroTop.Text = ""
heroTop.Parent = hero
do local s = Instance.new("UIStroke"); s.Color = Color3.new(0, 0, 0); s.Thickness = 2; s.Parent = heroTop end

-- Some banners are tappable (RewardsClient's group/friend nags open a panel). One transparent button
-- covers the whole card; presentHero rebinds it per banner and clears it when nothing is showing.
local heroBtn = Instance.new("TextButton")
heroBtn.Size = UDim2.fromScale(1, 1)
heroBtn.BackgroundTransparency = 1
heroBtn.Text = ""
heroBtn.AutoButtonColor = false
heroBtn.Visible = false
heroBtn.Active = false
heroBtn.ZIndex = 5
heroBtn.Parent = hero

local heroOnClick = nil
heroBtn.Activated:Connect(function()
	local f = heroOnClick
	if f then pcall(f) end
end)

local heroMain = Instance.new("TextLabel")
heroMain.AnchorPoint = Vector2.new(0.5, 0)
heroMain.Position = UDim2.new(0.5, 0, 0, 29)
heroMain.Size = UDim2.new(1, -12, 0, 32)
heroMain.BackgroundTransparency = 1
heroMain.Font = Enum.Font.FredokaOne
heroMain.TextColor3 = Color3.new(1, 1, 1)
heroMain.TextScaled = true
heroMain.Text = ""
heroMain.Parent = hero
do local s = Instance.new("UIStroke"); s.Color = Color3.new(0, 0, 0); s.Thickness = 2; s.Parent = heroMain end

--======================================================================
-- SUBTITLE + PROGRESS FILL  (the two pieces the standalone tutorial card used to own)
--======================================================================
-- ObjectiveHUD used to be its own ScreenGui at y=85 with its own title, its own subtitle and its own coin
-- goal bar. It is a banner now, so the hero card grew the two parts it was missing rather than the tutorial
-- keeping a private card that happened to look similar. Every other banner is untouched: with no `sub` and
-- no `progress` in the spec these two are hidden and paintHero falls through to the exact 500x65 layout it
-- always had -- same size, same label positions, pixel for pixel.
local heroSub = Instance.new("TextLabel")
heroSub.Name = "Sub"
heroSub.AnchorPoint = Vector2.new(0.5, 0)
heroSub.Position = UDim2.new(0.5, 0, 0, 40)
heroSub.Size = UDim2.new(1, -18, 0, 18)
heroSub.BackgroundTransparency = 1
heroSub.Font = Enum.Font.GothamBold
heroSub.TextColor3 = Color3.fromRGB(242, 252, 244)
heroSub.TextScaled = true
heroSub.Visible = false
heroSub.Text = ""
heroSub.Parent = hero
do
	local s = Instance.new("UIStroke"); s.Color = Color3.new(0, 0, 0); s.Thickness = 1.5; s.Parent = heroSub
	local t = Instance.new("UITextSizeConstraint"); t.MaxTextSize = 17; t.Parent = heroSub
end

-- The live progress fill. A recessed well in a darkened cut of the card's OWN colour, so it belongs to
-- whatever banner is painted rather than being a fixed navy bar sitting on top of it.
local heroBar = Instance.new("Frame")
heroBar.Name = "Progress"
heroBar.AnchorPoint = Vector2.new(0.5, 0)
heroBar.Position = UDim2.new(0.5, 0, 0, 60)
heroBar.Size = UDim2.new(1, -24, 0, 9)
heroBar.BackgroundColor3 = Color3.fromRGB(24, 92, 32)
heroBar.BorderSizePixel = 0
heroBar.Visible = false
heroBar.Parent = hero
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = heroBar end

local heroFill = Instance.new("Frame")
heroFill.Name = "Fill"
heroFill.Size = UDim2.new(0, 0, 1, 0)
heroFill.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
heroFill.BorderSizePixel = 0
heroFill.Parent = heroBar
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = heroFill end

-- ===== SOCIAL lane: top-left, small, stacks, never competes with HERO =====
local socialGui = Instance.new("ScreenGui")
socialGui.Name = "NotifySocial"
socialGui.ResetOnSpawn = false
socialGui.IgnoreGuiInset = true
socialGui.DisplayOrder = 94
socialGui:SetAttribute(STAMP, true)   -- see heroGui above: stamped before parenting
socialGui.Parent = playerGui

local SOCIAL_MAX  = 3   -- most pills on screen at once; the oldest is evicted past this
local SOCIAL_H    = 34
local SOCIAL_GAP  = 6
local socialPills = {}  -- newest last

local function layoutSocial()
	for i, pill in ipairs(socialPills) do
		local y = 10 + (i - 1) * (SOCIAL_H + SOCIAL_GAP)
		TweenService:Create(pill, TweenInfo.new(0.2), { Position = UDim2.new(0, 10, 0, y) }):Play()
	end
end

local function popSocial(pill)
	for i, p in ipairs(socialPills) do
		if p == pill then table.remove(socialPills, i); break end
	end
	TweenService:Create(pill, TweenInfo.new(0.25), { Position = UDim2.new(0, -320, 0, pill.Position.Y.Offset) }):Play()
	task.delay(0.3, function() if pill.Parent then pill:Destroy() end end)
	layoutSocial()
end

local function showSocial(text, color)
	local pill = Instance.new("TextLabel")
	pill.AnchorPoint = Vector2.new(0, 0)
	pill.Position = UDim2.new(0, -320, 0, 10)
	pill.Size = UDim2.new(0, 300, 0, SOCIAL_H)
	pill.BackgroundColor3 = color or Color3.fromRGB(45, 55, 90)
	pill.BackgroundTransparency = 0.15
	pill.BorderSizePixel = 0
	pill.Font = Enum.Font.GothamBold
	pill.TextColor3 = Color3.fromRGB(235, 240, 255)
	pill.TextSize = 14
	pill.TextScaled = true
	pill.Text = "  " .. text
	pill.TextXAlignment = Enum.TextXAlignment.Left
	pill.Parent = socialGui
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = pill
		local s = Instance.new("UIStroke"); s.Color = Color3.new(0, 0, 0); s.Thickness = 1.5; s.Parent = pill
		local t = Instance.new("UITextSizeConstraint"); t.MaxTextSize = 15; t.Parent = pill
	end

	socialPills[#socialPills + 1] = pill
	if #socialPills > SOCIAL_MAX then popSocial(socialPills[1]) end
	layoutSocial()
	task.delay(4.5, function() if pill.Parent then popSocial(pill) end end)
end

-- ===== HERO scheduler: one at a time, priority-ordered, preemptable =====
local queue    = {}    -- pending specs, highest priority first (stable within a priority)
local showing  = nil   -- the TRANSIENT spec currently on screen (nil while a pin owns the slot)
local token    = 0     -- invalidates every in-flight timer whenever the slot's owner changes
local cardShown = false -- is the hero card currently up (pinned OR transient)? drives hide-vs-repaint
local lastText, lastAt = nil, 0

-- hideHero owns the token bump. Before, callers bumped it and the 0.32s callback still ran
-- `hero.Visible = false` unconditionally -- so a banner that arrived during the slide-out was blanked a
-- third of a second after it appeared. Now a newer owner invalidates the whole callback, Visible included.
local function hideHero(after)
	token = token + 1
	local mine = token
	TweenService:Create(hero, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Position = HERO_HIDDEN }):Play()
	task.delay(0.32, function()
		if token ~= mine then return end -- somebody took the slot mid-slide; it owns Visible now
		hero.Visible = false
		if after then after() end
	end)
end

local settle -- forward declaration: the single place that decides who owns the hero slot

-- Paint the card. Split out because a PINNED banner (below) repaints in place as its instruction changes,
-- and re-running the slide-in animation on every text change would make a standing instruction flap.
local function paintHero(spec)
	local hasTop = (spec.top ~= nil and spec.top ~= "")
	local hasSub = (spec.sub ~= nil and spec.sub ~= "")
	local pct    = tonumber(spec.progress)
	local hasBar = pct ~= nil

	heroTop.Text = spec.top or ""
	heroTop.Visible = hasTop
	heroMain.Text = spec.text or ""
	heroSub.Text = spec.sub or ""
	heroSub.Visible = hasSub
	heroBar.Visible = hasBar
	hero.BackgroundColor3 = spec.color or Color3.fromRGB(100, 200, 100)

	if not hasSub and not hasBar then
		-- THE LEGACY LAYOUT, UNCHANGED. Every banner that existed before the tutorial moved in takes this
		-- branch and renders exactly as it always did: 500x65, main label low under a top line or filling
		-- the card without one.
		hero.Size = UDim2.new(0, 500, 0, 65)
		-- Restated, not assumed: the tall branch below moves the top line to make room, and a banner that
		-- follows a tall one would otherwise inherit its 18px slot and sit a few pixels high.
		heroTop.Position  = UDim2.new(0.5, 0, 0, 6)
		heroTop.Size      = UDim2.new(1, -12, 0, 22)
		heroMain.Position = hasTop and UDim2.new(0.5, 0, 0, 29) or UDim2.new(0.5, 0, 0, 10)
		heroMain.Size     = hasTop and UDim2.new(1, -12, 0, 32) or UDim2.new(1, -12, 0, 45)
	else
		-- The taller shape: an optional top line, the title, the subtitle, then the progress fill, stacked
		-- from the top with a measured gap. The card is sized to whatever it actually needs rather than to a
		-- constant, so a banner with a subtitle and no bar is not left with a strip of empty green at its foot.
		local y = 6
		if hasTop then
			heroTop.Position = UDim2.new(0.5, 0, 0, y); heroTop.Size = UDim2.new(1, -14, 0, 18); y += 20
		end
		heroMain.Position = UDim2.new(0.5, 0, 0, y); heroMain.Size = UDim2.new(1, -14, 0, 32); y += 34
		if hasSub then
			heroSub.Position = UDim2.new(0.5, 0, 0, y); heroSub.Size = UDim2.new(1, -18, 0, 18); y += 20
		end
		if hasBar then
			heroBar.Position = UDim2.new(0.5, 0, 0, y); heroBar.Size = UDim2.new(1, -24, 0, 9); y += 11
		end
		hero.Size = UDim2.new(0, 500, 0, math.max(65, y + 4))
	end

	if hasBar then
		heroBar.BackgroundColor3 = spec.progressTrack or Color3.fromRGB(24, 92, 32)
		heroFill.BackgroundColor3 = spec.progressColor or Color3.fromRGB(255, 200, 0)
		TweenService:Create(heroFill, TweenInfo.new(0.25),
			{ Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0) }):Play()
	end

	heroOnClick = spec.onClick
	heroBtn.Visible = spec.onClick ~= nil
	heroBtn.Active  = spec.onClick ~= nil
end

local function slideHeroIn()
	hero.Position = HERO_HIDDEN
	hero.Visible = true
	TweenService:Create(hero, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = HERO_SHOWN }):Play()
end

local function presentHero(spec)
	showing = spec
	cardShown = true
	token = token + 1
	local mine = token

	paintHero(spec)
	slideHeroIn()

	if spec.sound then pcall(spec.sound) end

	task.delay(spec.duration or 3.5, function()
		if token ~= mine then return end -- preempted or replaced -> that path owns the hide
		showing = nil
		heroOnClick = nil
		heroBtn.Visible = false
		heroBtn.Active = false
		if spec.onDone then pcall(spec.onDone) end -- let the caller's own queue advance
		-- settle decides what happens to the card: a waiting pin repaints in place (no blink between a
		-- milestone banner and the standing instruction it interrupted), anything else slides out.
		settle()
	end)
end

--======================================================================
-- PINNED banner: ONE standing instruction that owns the slot until it's done
--======================================================================
-- Ordinary banners are NEWS -- they appear, they say a thing, they leave on a timer. A pinned banner is an
-- INSTRUCTION: it stays until the thing it is asking for has actually happened. The watering-can guidance is
-- the first user (see CommunityGarden.client.lua), where a timed banner is exactly wrong -- it would expire
-- while the player is still walking to the water spot, abandoning the one person who needed it most.
--
-- ===== IT OUTRANKS PUSHES, AND NOW PINS OUTRANK EACH OTHER =====
-- While a pin is up, no PUSH preempts it -- not even ISLAND. Other banners are not dropped, they QUEUE, and
-- they play in priority order the moment the pin releases. So nothing is lost; a standing instruction just
-- refuses to be talked over while it is still standing.
--
-- There are now TWO standing instructions in the game and they are not equal:
--   RANK.QUEST    -- the garden watering quest's step directions, while that quest is live and unfinished.
--   RANK.TUTORIAL -- the new-player directions card (ObjectiveHUD), which used to be its own ScreenGui.
-- Both can be pinned at once. The higher rank is the one on screen; the lower one is NOT cancelled, it is
-- covered, and it reappears the instant the higher releases. That is the garden-watering exception in one
-- mechanism: hand the player a watering can and the directions step aside; finish the watering and they are
-- back, mid-sentence, with nothing lost.
--
-- It reuses the SAME hero card as every other banner -- same position, same paint -- so a pinned
-- instruction is visually one of the family and not a second, competing kind of banner.
local pins    = {}     -- id -> { spec, rank, seq, yielding, autoRestore }
local pinSeq  = 0      -- monotonic, so equal ranks break the tie toward the most recent pin
local activePin = nil  -- the id currently painted on the card, or nil
local socialHold = {}  -- social pills parked while an exclusive teaching moment owns the screen

-- Is a tutorial / milestone moment on screen right now? True for an exclusive PUSH mid-play and for either
-- of the two pinned standing instructions. Everything that has to stay off the screen during one of those
-- -- other players' pills here, the pet quest tracker over in PetFollow -- asks this.
local function isExclusiveNow()
	if showing and showing.exclusive then return true end
	return activePin ~= nil and pins[activePin] ~= nil and pins[activePin].rank >= RANK.TUTORIAL
end

-- Let the parked pills out again. Polled rather than pushed: the lane can stop being exclusive from half a
-- dozen code paths (a banner timing out, a pin releasing, a pin yielding) and threading a flush through all
-- of them is how one of them gets forgotten and a player's pills are lost for the rest of the session.
task.spawn(function()
	while true do
		task.wait(0.25)
		if #socialHold > 0 and not isExclusiveNow() then
			local batch = socialHold
			socialHold = {}
			for _, s in ipairs(batch) do showSocial(s.text, s.color) end
		end
	end
end)

-- Insert by priority: strictly-greater priorities go ahead, equals keep arrival order (FIFO).
-- Defined HERE, above pin(), because pin() re-queues the banner it displaces -- and a `local function`
-- declared further down would not be in scope for it (it would silently resolve to a nil global).
local function enqueue(spec)
	local i = #queue + 1
	for k = 1, #queue do
		if spec.priority > queue[k].priority then i = k; break end
	end
	table.insert(queue, i, spec)
end

local function topPinId()
	local bestId, bestRank, bestSeq = nil, -1, -1
	for id, p in pairs(pins) do
		if not p.yielding and (p.rank > bestRank or (p.rank == bestRank and p.seq > bestSeq)) then
			bestId, bestRank, bestSeq = id, p.rank, p.seq
		end
	end
	return bestId
end

-- A pin that stepped aside for an exclusive tutorial moment comes back the moment the lane runs dry -- it
-- was never cancelled, and the player still has the job it was describing.
local function restoreYieldedPins()
	local any = false
	for _, p in pairs(pins) do
		if p.yielding and p.autoRestore then
			p.yielding, p.autoRestore = false, nil
			any = true
		end
	end
	return any
end

--======================================================================
-- settle() -- THE ONE PLACE THAT DECIDES WHO OWNS THE HERO SLOT
--======================================================================
-- Every path that changes the lane's state (a banner ending, a pin arriving, a pin releasing, a push
-- preempting) ends by calling this instead of driving the card itself. That is what makes "never overlap,
-- never stack" a property of the file rather than a rule five call sites have to remember: there is exactly
-- one owner at any instant, and it is whatever settle picked last.
--
-- The order it checks is the priority order, top down:
--   1. a transient banner already mid-run keeps the slot (it calls settle again when it ends)
--   2. the highest-ranked pin  -- garden watering, then the tutorial directions
--   3. the queue, in priority order
--   4. nothing -> slide the card away
function settle()
	if showing then return end

	local topId = topPinId()
	-- The lane is going idle: this is the moment a yielded pin is owed its slot back.
	if not topId and #queue == 0 and restoreYieldedPins() then topId = topPinId() end

	if topId then
		if activePin ~= topId then
			activePin = topId
			token = token + 1 -- orphan any in-flight hide from the owner we just displaced
			local sp = pins[topId].spec
			paintHero(sp)
			-- Repaint in place if a card is already up: swapping between the watering directions and the
			-- tutorial directions should read as the same banner changing its mind, not as two banners.
			if not cardShown then cardShown = true; slideHeroIn() end
			if sp.sound then pcall(sp.sound) end
		end
		return
	end

	activePin = nil

	if #queue > 0 then
		if cardShown then
			cardShown = false
			hideHero(settle) -- slide the outgoing card away first, then come back and present the next
		else
			presentHero(table.remove(queue, 1))
		end
		return
	end

	if cardShown then
		cardShown = false
		hideHero(function()
			heroOnClick = nil
			heroBtn.Visible = false
			heroBtn.Active = false
		end)
	end
end

--- Pin a standing instruction to the hero slot. Calling it again with the SAME id repaints in place (no
--- re-animation), which is how a pin changes its wording as the player's situation changes.
--- spec.rank picks the tier (RANK.QUEST default, RANK.TUTORIAL for the onboarding directions).
local function pin(id, spec)
	if type(spec) ~= "table" or not spec.text then return end
	local rank = tonumber(spec.rank) or RANK.QUEST

	local p = pins[id]
	if p then
		p.spec, p.rank = spec, rank
		if activePin == id then
			paintHero(spec) -- live update only: re-sliding on every text change would make it flap
		else
			settle()        -- it was covered or yielded; the rank change may have earned it the slot
		end
		return
	end

	pinSeq = pinSeq + 1
	pins[id] = { spec = spec, rank = rank, seq = pinSeq }

	-- THE GARDEN WATERING EXCEPTION. A QUEST-rank pin is the only thing in the game allowed to cut off a
	-- banner that has declared itself exclusive: its directions are what the player is being asked to do
	-- RIGHT NOW, and everything else can wait one beat. The displaced banner is queued, never dropped.
	if showing and rank >= RANK.QUEST then
		enqueue(showing)
		showing = nil
		token = token + 1
	end
	settle()
end

--- Release a pin. `id` must match, so a late unpin from a finished flow cannot tear down a newer one that
--- has since taken the slot. Releasing the top pin reveals the next one down rather than clearing the card.
local function unpin(id)
	if id == nil then
		if next(pins) == nil then return end
		pins = {}
	elseif pins[id] then
		pins[id] = nil
	else
		return
	end
	if activePin and not pins[activePin] then activePin = nil end
	settle()
end

--- Step a pin aside so everything queued behind it can play, then take the slot back once the lane is dry.
--- The tutorial directions call this when their STEP COMPLETES: that is the point at which the player has
--- done the thing, so the banners that were politely waiting are finally allowed through.
local function pinYield(id)
	local p = pins[id]
	if not p or p.yielding then return end
	p.yielding, p.autoRestore = true, true
	if activePin == id then activePin = nil end
	settle()
end

--- push a notification.
--- spec = { text, top?, sub?, color?, priority?, duration?, lane? ("hero"|"social"), sound? (fn),
---          progress? (0..1 -> shows the fill), progressColor?, progressTrack?, exclusive? }
local function push(spec)
	if type(spec) ~= "table" or not spec.text then return end
	-- EXCLUSIVE = a tutorial / milestone moment. It defaults into the TUTORIAL tier, which is what puts it
	-- above every ordinary banner and below the garden watering quest.
	if spec.exclusive and not spec.priority then spec.priority = PRIORITY.TUTORIAL end
	spec.priority = spec.priority or PRIORITY.REWARD

	if spec.lane == "social" or spec.priority <= PRIORITY.SOCIAL then
		-- Social pills live top-LEFT and normally never compete with the hero lane -- that is the whole
		-- point of giving them their own lane. But "exclusive" was asked for literally: while a tutorial or
		-- milestone moment is up, it is the only thing on screen, full stop. So other players' news waits in
		-- socialHold and flushes in arrival order the moment the moment ends. Nothing is dropped.
		if isExclusiveNow() then
			socialHold[#socialHold + 1] = spec
			return
		end
		showSocial(spec.text, spec.color)
		return
	end

	-- Drop an exact repeat within 2s (the reward reminder re-fires on a loop). onDone MUST still fire:
	-- callers like RewardsClient hold a `bannerShowing` flag that only clears on onDone, so silently
	-- swallowing the spec would wedge their queue permanently.
	local now = os.clock()
	if spec.text == lastText and (now - lastAt) < 2 then
		if spec.onDone then task.defer(function() pcall(spec.onDone) end) end
		return
	end
	lastText, lastAt = spec.text, now

	if activePin then
		local pinRank = pins[activePin].rank
		-- TWO WAYS TO STEP OVER A PIN, and neither can touch the garden watering quest:
		--   1. an EXCLUSIVE tutorial/milestone moment over the standing tutorial directions -- same tier, and
		--      the news is the thing that just happened;
		--   2. anything OUTRANKING the pin. That is what makes RANK.STATUS (30) work: the fishing commentary
		--      holds the card while nothing else needs it, and every real banner -- reward (40), event (80),
		--      island (100) -- simply preempts it and hands the lane back afterwards.
		-- Either way the pin YIELDS rather than being cancelled: it is restored the moment the lane runs dry,
		-- so a status that was mid-sentence comes back mid-sentence.
		if (spec.exclusive and pinRank < RANK.QUEST) or spec.priority > pinRank then
			enqueue(spec)
			pinYield(activePin)
			return
		end
		enqueue(spec) -- a pin outranks this push: wait behind it, in priority order. Nothing is dropped.
		return
	end

	if not showing then
		enqueue(spec)
		settle()
		return
	end

	-- EXCLUSIVE MEANS EXCLUSIVE. A tutorial or achievement moment on screen cannot be preempted by anything
	-- a push can carry, however important that push thinks it is -- arrival cards, event titles, friend and
	-- group promos, reward toasts and purchase confirmations all queue and play afterwards, in order.
	if showing.exclusive then
		enqueue(spec)
		return
	end

	if spec.priority > showing.priority then
		-- PREEMPT: the current banner is less important. Put it back at the head of the
		-- queue (it still deserves its moment) and swap the new one in immediately.
		local demoted = showing
		showing = nil
		enqueue(demoted)
		table.insert(queue, 1, spec) -- the preempting spec must lead the queue
		cardShown = false
		hideHero(settle)
		return
	end

	enqueue(spec) -- equal or lower -> wait your turn
end

--- Sugar for rule 3: "this is a teaching moment, it gets the lane to itself". One call so first-purchase,
--- first-full-tank, achievement unlocks and quest-step completions cannot each invent their own priority.
local function tutorial(spec)
	if type(spec) ~= "table" then return end
	spec.exclusive = true
	spec.priority = spec.priority or PRIORITY.TUTORIAL
	push(spec)
end

local API = {
	push     = push,
	tutorial = tutorial,
	-- pin(id, spec) / unpin(id) / pinYield(id): a STANDING INSTRUCTION that holds the hero slot until the
	-- job is done. Re-pinning the same id repaints in place; spec.rank picks the tier.
	pin      = pin,
	unpin    = unpin,
	pinYield = pinYield,
	PRIORITY = PRIORITY,
	RANK     = RANK,
	isBusy   = function() return showing ~= nil or activePin ~= nil end,
	isPinned = function() return activePin ~= nil end,
	-- True while a teaching moment owns the lane. Anything that draws in the top-centre strip WITHOUT going
	-- through this file (the pet quest tracker, the piece-found reveal) reads this and stays out of the way.
	isExclusive = isExclusiveNow,
	__owner  = STAMP,   -- how a caller (or the loop below) can tell OUR table from the stale copy's
}
_G.NotifyCenter = API

--======================================================================
-- HOLD THE CLAIM
--======================================================================
-- The stale copy loads AFTER us and its last statement replaces _G.NotifyCenter with a table that has no
-- pin/unpin. Load order is not ours to choose, so instead of trying to win the race we simply outlast it:
-- put our table back whenever something else has taken the global.
--
-- Fast for the first ten seconds (that is the whole window in which any duplicate could still be booting),
-- then a slow heartbeat as a backstop -- a stale script that somehow rebuilds later cannot strand callers
-- on an API without pin. The check is a plain identity test, so a tick where nothing changed costs nothing.
task.spawn(function()
	sweepStale()
	for i = 1, 100 do          -- 10s at 0.1s
		if _G.NotifyCenter ~= API then
			_G.NotifyCenter = API
			warn("[NotifyCenter] a stale copy replaced _G.NotifyCenter -- reclaimed it (pin/unpin restored)")
			sweepStale()
		end
		if i == 10 or i == 40 or i == 90 then sweepStale() end
		task.wait(0.1)
	end
	while true do
		task.wait(5)
		if _G.NotifyCenter ~= API then
			_G.NotifyCenter = API
			sweepStale()
		end
	end
end)

print("[NotifyCenter] ready -- HERO lane (top-centre, priority queue + ranked pinned instructions) + SOCIAL lane (top-left)")
print("[NotifyCenter] priority order ACTIVE: garden watering directions (QUEST 200) > tutorial/achievement " ..
	"exclusive banners (TUTORIAL 150) > island 100 / purchase 90 / event 80 / reward 40. One owner at a time; " ..
	"equal fires queue in order -- never overlapping, never stacked.")
