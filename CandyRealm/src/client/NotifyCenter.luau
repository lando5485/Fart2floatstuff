--[[
	NotifyCenter.luau  (StarterPlayerScripts.NotifyCenter)

	THE ANNOUNCEMENTS BANNER — ported from Fart to Float's NotifyCenter, re-skinned to the space theme.

	ONE OWNER FOR EVERY TRANSIENT BANNER. In the first realm five separate ScreenGuis (arrival / announce /
	hud notice / purchase / event) all rested at the SAME top-centre pixel with nothing coordinating them —
	land on a new island while another player's news fires and the two banners drew straight through each
	other. Space Realm has the same shape of problem: PhoneHUD hands out ONE shared banner spot, and every
	banner client aims at it independently. This module is the coordinator that spot was always missing.

	Two ideas do the work (both lifted from FtF):
	  1) LANES. Notifications are placed by KIND, not all dumped top-centre.
	       HERO   = your own big moments (the shared PhoneHUD banner spot — the prime slot)
	       SOCIAL = other players' news (top-left, small pills, never blocks you)
	  2) PRIORITY. The HERO lane shows exactly ONE card at a time. A more important banner PREEMPTS a less
	     important one (the demoted one goes back on the queue, it is never eaten); equal-or-lower ones QUEUE.
	     So "WELCOME TO NEPTUNE" is never buried under "Daily Reward Ready".

	===== SIZING (FtF's hero card, measured and kept) =====
	FtF's card is 500 x 65 top-centre, corner 12, slides in over 0.4s (Back/Out) and out over 0.3s (Quad),
	default hold 3.5s; a small 22px top line at y6 over a 32px main line at y29, and with NO top line the main
	line takes the whole card (y10, h45). Those proportions are reproduced here in SCALE terms, so the same
	card also fits the phone banner spot (PhoneHUD.BANNER_SIZE, 300x80) without a second layout:
	    top  y 0.08 h 0.34   ->  at 500x65: y5.2 h22.1   (FtF: y6 h22)
	    main y 0.44 h 0.50   ->  at 500x65: y28.6 h32.5  (FtF: y29 h32)
	    main-only y 0.12 h 0.76 -> at 500x65: y7.8 h49.4 (FtF: y10 h45)
	Space Realm adds ONE slot FtF's card doesn't have: an optional third `sub` line for the planet-arrival
	taglines ("The closest world to the sun."). A card with a sub line grows to 92 (desktop) / 96 (phone) and
	the three lines re-flow; without one the geometry above is untouched.

	===== THEME =====
	FtF's card is a flat coloured rectangle with a black outline. This one is the Space Realm panel: deep navy
	starfield fill, top gloss, a neon gradient border + outer glow in the banner's ACCENT colour, FredokaOne
	headline over a Gotham kicker. The accent is per-banner (`spec.color`), so a Mercury arrival glows grey,
	Neptune blue, a purchase green — recoloured live on the one persistent card rather than rebuilt.

	===== PLACEMENT =====
	The hero card sits at the SHARED banner spot PhoneHUD owns (PhoneHUD.bannerOn/bannerOff), re-read at SHOW
	time so it always uses the live ResponsiveUI scale — the same spot the other banner clients already use.
	The SOCIAL lane is top-left (x12, from y10), capped at 2 pills so the stack always ends above the left
	rail (which starts at y96).

	===== USAGE =====
		local Notify = require(script.Parent:WaitForChild("NotifyCenter"))
		Notify.push({ top = "🚀 WELCOME TO", text = "NEPTUNE", sub = "…", color = …,
		              priority = Notify.PRIORITY.PLANET, duration = 4 })
		Notify.pin("watering", { text = "Fill the can at the water tank" })   -- standing instruction
		Notify.unpin("watering")

	It is a MODULE, not a client script, deliberately: FtF's copy published `_G.NotifyCenter` and then had to
	fight a load-order race to keep it (see its "HOLD THE CLAIM" block). A require has no such race — the
	first caller builds the GUI, everyone else gets the same table.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CandyTheme = require(script.Parent:WaitForChild("CandyTheme"))
-- ⚠ PhoneHUD LIVES SOMEWHERE DIFFERENT IN EVERY REALM. Space Realm maps `ReplicatedStorage -> src/shared`, so
-- there it is ReplicatedStorage.PhoneHUD. Candy maps `ReplicatedStorage.Shared -> src/shared`, so here it is
-- ReplicatedStorage.Shared.PhoneHUD. Copying Space's require verbatim made this line wait FOREVER on a path
-- that does not exist in this realm -- "Infinite yield possible on ReplicatedStorage:WaitForChild("PhoneHUD")"
-- -- which killed the whole module: the require never returned, NotifyCenterBoot never finished, and
-- _G.NotifyCenter was never published, so all ~75 call sites silently did nothing.
--
-- Resolved by LOOKING rather than assuming, so this file stays portable to a realm with either layout.
local function findPhoneHUD()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local direct = ReplicatedStorage:FindFirstChild("PhoneHUD")
		or (shared and shared:FindFirstChild("PhoneHUD"))
	if direct then return direct end
	-- Not there yet: wait on BOTH candidates rather than betting on one. Whichever appears first wins; if
	-- neither does we warn loudly instead of hanging silently, because a silent hang is what caused this bug.
	local found = nil
	task.spawn(function() local r = ReplicatedStorage:WaitForChild("PhoneHUD", 20); if r and not found then found = r end end)
	task.spawn(function()
		local s = ReplicatedStorage:WaitForChild("Shared", 20)
		local r = s and s:WaitForChild("PhoneHUD", 20)
		if r and not found then found = r end
	end)
	local deadline = os.clock() + 21
	while not found and os.clock() < deadline do task.wait(0.1) end
	if not found then
		error("[NotifyCenter] PhoneHUD not found at ReplicatedStorage.PhoneHUD OR ReplicatedStorage.Shared.PhoneHUD"
			.. " -- the banner cannot place itself without it.")
	end
	return found
end
local PhoneHUD = require(findPhoneHUD()) -- the single source of truth for the banner spot

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local NotifyCenter = {}

-- ===== PRIORITIES (higher wins the HERO slot) =====
-- Exported so callers name the moment instead of hard-coding a number. FtF's ladder, with ISLAND renamed.
-- THE LADDER, ported from realm 1 so both places rank the same things the same way.
--
-- ⚠ ISLAND WAS MISSING AND WAS ALREADY BEING USED. IslandCard pushes the arrival card at
-- `NC.PRIORITY.ISLAND` and CandyMineExplosion reads it too -- both were resolving to nil, which
-- meant the biggest moment in the game queued with NO priority and lost to everything. Defining
-- it is a fix, not a new feature. PLANET stays as an alias because this file's own docs use it.
local PRIORITY = {
	QUEST    = 200, -- live quest DIRECTIONS -- the freeze meter, "plant 2/3 crates", garden watering.
	                -- Top of the world while that quest is unfinished: these are pinned instructions
	                -- you are actively following, not news, and they come back after anything louder.
	TUTORIAL = 150, -- tutorial / milestone / achievement moments. Exclusive: nothing plays beside one.
	ISLAND   = 100, -- "COOKIE CRUMBLE!" — you physically landed on a new island.
	PLANET   = 100, -- alias for ISLAND (realm 1's space wording; same rung, kept for old call sites)
	PURCHASE = 90,  -- a real Robux/gamepass purchase went through — must never be swallowed.
	EVENT    = 80,  -- a server event started (meteor shower, 2x coins, …) or a quest was completed.
	REWARD   = 40,  -- "Daily Reward Ready" / "Stomach Upgrade Available" — a nudge, not news.
	SOCIAL   = 10,  -- another player's news. Routed to its own lane; never competes.
}
NotifyCenter.PRIORITY = PRIORITY

local ACCENT_DEFAULT = CandyTheme.NeonCyan
local SHOW_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)  -- FtF: 0.4 Back/Out
local SHOW_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad)                            -- FtF: 0.3 Quad
local DEFAULT_DURATION = 3.5                                                          -- FtF: 3.5s hold

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
	return c
end
local function textStroke(l, thickness)
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(0, 0, 0)
	s.Thickness = thickness or 2
	s.Parent = l
	return s
end
local function maxTextSize(l, size)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = size
	c.Parent = l
	return c
end

-- The card's footprint for THIS device. Desktop keeps FtF's 500x65; phone uses the shared banner size PhoneHUD
-- publishes, so the hero card is exactly as wide/tall as every other banner that lands in that spot.
local function cardSize(hasSub: boolean): UDim2
	if PhoneHUD.isPhone() then
		local w = PhoneHUD.BANNER_SIZE.X.Offset
		local h = PhoneHUD.BANNER_SIZE.Y.Offset
		return UDim2.fromOffset(w, hasSub and (h + 16) or h)
	end
	return UDim2.fromOffset(500, hasSub and 92 or 65)
end

-- ===== HERO lane: the shared banner spot, one card at a time =====
local heroGui = Instance.new("ScreenGui")
heroGui.Name = "NotifyHero"
heroGui.ResetOnSpawn = false
heroGui.IgnoreGuiInset = true
heroGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- so the glow/shadow siblings sit behind the card
heroGui.DisplayOrder = 95 -- above the HUD, below the shops (100) and the crate reveal
heroGui.Parent = playerGui

-- A transparent ROOT is what slides and resizes; the card fills it at scale (1,1). The glow/shadow that
-- CandyTheme.addPanelDepth parents alongside the card are sized in scale too, so they follow the root's height
-- when a card with a sub line grows — which they could not do if they were pinned to a fixed offset size.
local root = Instance.new("Frame")
root.Name = "Hero"
root.AnchorPoint = PhoneHUD.BANNER_ANCHOR
root.Position = PhoneHUD.bannerOff()
root.Size = cardSize(false)
root.BackgroundTransparency = 1
root.Visible = false
root.Parent = heroGui

local card = Instance.new("Frame")
card.Name = "Card"
card.Size = UDim2.fromScale(1, 1)
card.BackgroundColor3 = CandyTheme.StarfieldFill
card.BorderSizePixel = 0
card.ZIndex = 2
card.Parent = root
corner(card, 16)

local cardGlow = CandyTheme.addPanelDepth(card, {
	glowColor = ACCENT_DEFAULT, corner = 16, glowSpread = 8, shadowSpread = 5, shadowDrop = 5,
})
CandyTheme.addStarfield(card, 22, 9091) -- also sets ClipsDescendants, which keeps the gloss inside the corners
CandyTheme.addGloss(card, 16)
local edge = CandyTheme.addNeonBorder(card, ACCENT_DEFAULT, 2.5)
local edgeGradient = edge:FindFirstChildOfClass("UIGradient")

-- Recolour the one persistent card to the banner's accent (border gradient + outer glow + kicker text), rather
-- than rebuilding the card per banner.
local function setAccent(c: Color3)
	if edgeGradient then
		edgeGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, c:Lerp(Color3.new(1, 1, 1), 0.55)),
			ColorSequenceKeypoint.new(0.5, c),
			ColorSequenceKeypoint.new(1, c:Lerp(Color3.new(0, 0, 0), 0.4)),
		})
	end
	if cardGlow then
		cardGlow.BackgroundColor3 = c
	end
end

-- Some banners are tappable (a reward nag that opens a panel). ONE transparent button covers the card and is
-- rebound per banner, then cleared when nothing is showing.
local heroBtn = Instance.new("TextButton")
heroBtn.Name = "Hit"
heroBtn.Size = UDim2.fromScale(1, 1)
heroBtn.BackgroundTransparency = 1
heroBtn.Text = ""
heroBtn.AutoButtonColor = false
heroBtn.Visible = false
heroBtn.Active = false
heroBtn.ZIndex = 6
heroBtn.Parent = card

local heroOnClick = nil
heroBtn.Activated:Connect(function()
	local f = heroOnClick
	if f then
		pcall(f)
	end
end)

-- The kicker ("🚀 WELCOME TO"): small, Gotham, in the accent colour.
local topLbl = Instance.new("TextLabel")
topLbl.Name = "Kicker"
topLbl.AnchorPoint = Vector2.new(0.5, 0)
topLbl.BackgroundTransparency = 1
topLbl.Font = Enum.Font.GothamBold
topLbl.TextColor3 = ACCENT_DEFAULT
topLbl.TextScaled = true
topLbl.Text = ""
topLbl.ZIndex = 3
topLbl.Parent = card
textStroke(topLbl)
maxTextSize(topLbl, 20)

-- The headline ("NEPTUNE"): chunky FredokaOne with the theme's text gloss.
local mainLbl = Instance.new("TextLabel")
mainLbl.Name = "Headline"
mainLbl.AnchorPoint = Vector2.new(0.5, 0)
mainLbl.BackgroundTransparency = 1
mainLbl.Font = Enum.Font.FredokaOne
mainLbl.TextColor3 = CandyTheme.TextPrimary
mainLbl.TextScaled = true
mainLbl.Text = ""
mainLbl.ZIndex = 3
mainLbl.Parent = card
textStroke(mainLbl)
maxTextSize(mainLbl, 30)
CandyTheme.addTextGloss(mainLbl)

-- The tagline: the Space Realm addition, used by the planet arrival banner.
local subLbl = Instance.new("TextLabel")
subLbl.Name = "Tagline"
subLbl.AnchorPoint = Vector2.new(0.5, 0)
subLbl.BackgroundTransparency = 1
subLbl.Font = Enum.Font.Gotham
subLbl.TextColor3 = CandyTheme.TextMuted
subLbl.TextScaled = true
subLbl.Text = ""
subLbl.Visible = false
subLbl.ZIndex = 3
subLbl.Parent = card
textStroke(subLbl)
maxTextSize(subLbl, 16)

-- Re-flow the three slots. See the SIZING block up top: these fractions reproduce FtF's pixel layout at 500x65
-- and survive the phone card's different size because they are scale, not offset.
local function layout(hasTop: boolean, hasSub: boolean)
	if hasSub then
		topLbl.Position = UDim2.new(0.5, 0, 0.06, 0)
		topLbl.Size = UDim2.new(1, -18, 0.22, 0)
		subLbl.Position = UDim2.new(0.5, 0, 0.72, 0)
		subLbl.Size = UDim2.new(1, -24, 0.20, 0)
		if hasTop then
			mainLbl.Position = UDim2.new(0.5, 0, 0.30, 0)
			mainLbl.Size = UDim2.new(1, -18, 0.40, 0)
		else
			mainLbl.Position = UDim2.new(0.5, 0, 0.10, 0)
			mainLbl.Size = UDim2.new(1, -18, 0.56, 0)
		end
	elseif hasTop then
		topLbl.Position = UDim2.new(0.5, 0, 0.08, 0)
		topLbl.Size = UDim2.new(1, -18, 0.34, 0)
		mainLbl.Position = UDim2.new(0.5, 0, 0.44, 0)
		mainLbl.Size = UDim2.new(1, -18, 0.50, 0)
	else
		-- With no kicker the headline uses the whole card instead of sitting low.
		mainLbl.Position = UDim2.new(0.5, 0, 0.12, 0)
		mainLbl.Size = UDim2.new(1, -18, 0.76, 0)
	end
end

-- ===== SOCIAL lane: top-left, small, stacks, never competes with HERO =====
local socialGui = Instance.new("ScreenGui")
socialGui.Name = "NotifySocial"
socialGui.ResetOnSpawn = false
socialGui.IgnoreGuiInset = true
socialGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
socialGui.DisplayOrder = 94
socialGui.Parent = playerGui

local SOCIAL_MAX = 2   -- FtF allowed 3; two keeps the stack clear of the left rail, which starts at y96
local SOCIAL_H = 34
local SOCIAL_GAP = 6
local SOCIAL_W = 300
local socialPills = {} -- newest last

local function layoutSocial()
	for i, pill in ipairs(socialPills) do
		local y = 10 + (i - 1) * (SOCIAL_H + SOCIAL_GAP)
		TweenService:Create(pill, TweenInfo.new(0.2), { Position = UDim2.new(0, 12, 0, y) }):Play()
	end
end

local function popSocial(pill)
	for i, p in ipairs(socialPills) do
		if p == pill then
			table.remove(socialPills, i)
			break
		end
	end
	TweenService:Create(pill, TweenInfo.new(0.25), { Position = UDim2.new(0, -(SOCIAL_W + 20), 0, pill.Position.Y.Offset) }):Play()
	task.delay(0.3, function()
		if pill.Parent then
			pill:Destroy()
		end
	end)
	layoutSocial()
end

local function showSocial(text: string, color: Color3?)
	local accent = color or ACCENT_DEFAULT

	local pill = Instance.new("TextLabel")
	pill.Name = "SocialPill"
	pill.AnchorPoint = Vector2.new(0, 0)
	pill.Position = UDim2.new(0, -(SOCIAL_W + 20), 0, 10) -- slides in from off the left edge
	pill.Size = UDim2.new(0, SOCIAL_W, 0, SOCIAL_H)
	pill.BackgroundColor3 = CandyTheme.Panel
	pill.BorderSizePixel = 0
	pill.Font = Enum.Font.GothamBold
	pill.TextColor3 = CandyTheme.TextPrimary
	pill.TextScaled = true
	pill.Text = "  " .. text
	pill.TextXAlignment = Enum.TextXAlignment.Left
	pill.Parent = socialGui
	corner(pill, 10)
	CandyTheme.addNeonBorder(pill, accent, 1.5)
	textStroke(pill, 1.5)
	maxTextSize(pill, 15)

	socialPills[#socialPills + 1] = pill
	if #socialPills > SOCIAL_MAX then
		popSocial(socialPills[1])
	end
	layoutSocial()
	task.delay(4.5, function()
		if pill.Parent then
			popSocial(pill)
		end
	end)
end

-- ===== HERO scheduler: one at a time, priority-ordered, preemptable =====
local queue = {}   -- pending specs, highest priority first (stable within a priority)
local showing = nil -- the spec currently on screen
local token = 0     -- invalidates the in-flight hide timer when a banner is replaced
local lastText, lastAt = nil, 0

local function hideHero(after)
	TweenService:Create(root, SHOW_OUT, { Position = PhoneHUD.bannerOff() }):Play()
	task.delay(SHOW_OUT.Time + 0.02, function()
		root.Visible = false
		if after then
			after()
		end
	end)
end

local drain -- forward declaration (mutually recursive with presentHero)

-- Paint the card. Split out of presentHero because a PINNED banner repaints IN PLACE as its instruction changes,
-- and re-running the slide-in on every text change would make a standing instruction flap at the top of the screen.
local function paintHero(spec)
	local hasTop = spec.top ~= nil and spec.top ~= ""
	local hasSub = spec.sub ~= nil and spec.sub ~= ""
	local accent = spec.color or ACCENT_DEFAULT

	topLbl.Text = spec.top or ""
	topLbl.Visible = hasTop
	topLbl.TextColor3 = accent
	mainLbl.Text = spec.text or ""
	subLbl.Text = spec.sub or ""
	subLbl.Visible = hasSub

	layout(hasTop, hasSub)
	root.Size = cardSize(hasSub) -- a card with a tagline is taller; the depth layers follow it (scale-sized)
	setAccent(accent)

	heroOnClick = spec.onClick
	heroBtn.Visible = spec.onClick ~= nil
	heroBtn.Active = spec.onClick ~= nil
end

--======================================================================
-- HOLD: keep the lane shut while something else owns the screen
--======================================================================
-- The intro cinematic hides the whole HUD and takes the camera. A banner that fires during it is not delayed,
-- it is DESTROYED — it slides in behind an opaque backdrop, runs its timer and leaves, and the player never
-- sees it. That is exactly what happened to the very first "WELCOME TO MERCURY": the server fired the arrival
-- at 33.29s and the cinematic started at 34.49s, so the one banner that matters most played to a black screen.
--
-- A hold shuts the hero lane WITHOUT dropping anything: pushes queue as normal, and the queue drains the moment
-- the last holder releases. So the arrival banner needs no knowledge of the intro at all — it pushes when the
-- server says so, and it plays when the screen is actually free.
--
-- Holds are keyed and counted, so two systems holding at once (say an intro and a cutscene) both have to release.
-- Every hold carries an AUTO-RELEASE BACKSTOP: a holder that dies without releasing would otherwise silence every
-- banner for the rest of the session, which is a far worse failure than a banner arriving late.
local holds = {}
local holdCount = 0
local pinPending = false -- a pin was requested while held; it slides in when the hold lifts

local function heroBlocked(): boolean
	return holdCount > 0
end

local function slideHeroIn()
	-- Both endpoints are re-read HERE, not cached: PhoneHUD computes the spot from the LIVE ResponsiveUI scale,
	-- so a rotation or window resize between banners still lands this one in the right place.
	root.Position = PhoneHUD.bannerOff()
	root.Visible = true
	TweenService:Create(root, SHOW_IN, { Position = PhoneHUD.bannerOn() }):Play()
end

local function clearHeroClick()
	heroOnClick = nil
	heroBtn.Visible = false
	heroBtn.Active = false
end

local function presentHero(spec)
	showing = spec
	token += 1
	local mine = token

	paintHero(spec)
	slideHeroIn()

	if spec.sound then
		pcall(spec.sound)
	end

	task.delay(spec.duration or DEFAULT_DURATION, function()
		if token ~= mine then
			return -- preempted or replaced -> that path owns the hide
		end
		hideHero(function()
			if token ~= mine then
				return
			end
			showing = nil
			clearHeroClick()
			if spec.onDone then
				pcall(spec.onDone) -- let the caller's own queue advance
			end
			drain()
		end)
	end)
end

--======================================================================
-- PINNED banner: ONE standing instruction that owns the slot until it's done
--======================================================================
-- Ordinary banners are NEWS — they appear, they say a thing, they leave on a timer. A pinned banner is an
-- INSTRUCTION: it stays until the thing it asks for has actually happened, which is exactly what a timed banner
-- gets wrong (it expires while the player is still walking to the thing).
--
-- While a pin is up nothing preempts it — not even PLANET. Other banners are not dropped, they QUEUE, and they
-- play in priority order the moment the pin releases. Nothing is lost; a standing instruction just refuses to be
-- talked over while it is still standing. That is why pinning is a separate call and not "a very high priority".
local pinned = nil   -- the spec currently pinned, or nil
local pinnedId = nil -- the caller's id for it, so an unpin can't cancel somebody else's pin

-- Insert by priority: strictly-greater priorities go ahead, equals keep arrival order (FIFO). Declared HERE,
-- above pin(), because pin() re-queues the banner it displaces.
local function enqueue(spec)
	local i = #queue + 1
	for k = 1, #queue do
		if spec.priority > queue[k].priority then
			i = k
			break
		end
	end
	table.insert(queue, i, spec)
end

function drain()
	-- A pin holds the slot: queued banners wait for it, they do not play underneath or beside it.
	-- A hold shuts the lane entirely (see above) — the queue simply waits.
	if heroBlocked() or pinned or showing or #queue == 0 then
		return
	end
	presentHero(table.remove(queue, 1))
end

--- Shut the hero lane until `release(id)` is called. Pushes still queue; nothing is dropped.
--- `maxSeconds` is the auto-release backstop (default 90s) — a holder that never releases cannot silence
--- the lane forever.
function NotifyCenter.hold(id, maxSeconds)
	if holds[id] then
		return
	end
	holds[id] = true
	holdCount += 1
	local limit = tonumber(maxSeconds) or 90
	task.delay(limit, function()
		if holds[id] then
			warn(("[NotifyCenter] hold %q never released after %ds \u{2014} auto-releasing so banners aren't lost")
				:format(tostring(id), limit))
			NotifyCenter.release(id)
		end
	end)
end

--- Lift a hold. When the last one lifts, whatever queued up behind it plays immediately, in priority order.
function NotifyCenter.release(id)
	if not holds[id] then
		return
	end
	holds[id] = nil
	holdCount = math.max(0, holdCount - 1)
	if holdCount > 0 then
		return
	end
	if pinned and pinPending then
		pinPending = false
		slideHeroIn() -- the pin was painted when it was requested; only its entrance was deferred
		return
	end
	drain()
end

--- Pin a standing instruction to the hero slot. Calling it again with the SAME id repaints in place (no
--- re-animation), which is how a pin changes its wording as the player's situation changes.
function NotifyCenter.pin(id, spec)
	if type(spec) ~= "table" or not spec.text then
		return
	end
	spec.priority = spec.priority or PRIORITY.REWARD

	if pinned and pinnedId == id then
		pinned = spec
		paintHero(spec) -- live update only: re-sliding on every text change would make it flap
		return
	end

	-- ⚠ A PIN DOES NOT STEAL THE SLOT FROM A MORE IMPORTANT PIN.
	-- This used to replace whatever was pinned, unconditionally, so with two pinners running the
	-- LAST ONE TO CALL won -- and both of them call on a poll. Island 4's freeze meter (QUEST) and
	-- ObjectiveBannerBridge's quest directions (REWARD) would have traded the slot back and forth
	-- once a second, which is the flicker this whole lane exists to prevent. Lower or equal
	-- priority now simply does not displace a standing pin; the loser keeps polling and takes the
	-- slot the moment the winner releases, so nothing is lost and nothing overlaps.
	if pinned and (pinned.priority or 0) > (spec.priority or 0) then
		return
	end

	pinnedId, pinned = id, spec
	token += 1 -- orphan any in-flight hide timer from the banner we're displacing
	if showing then
		-- The displaced banner still deserves its moment: back on the queue, played once the pin releases.
		enqueue(showing)
		showing = nil
	end
	paintHero(spec)
	if heroBlocked() then
		-- Painted but not shown: the pin takes the slot the instant the hold lifts (see release).
		pinPending = true
		return
	end
	slideHeroIn()
	if spec.sound then
		pcall(spec.sound)
	end
end

--- Release the pin. `id` must match the pin that is up, so a late unpin from a finished flow cannot tear down a
--- newer one that has since taken the slot.
function NotifyCenter.unpin(id)
	if not pinned or (id ~= nil and pinnedId ~= id) then
		return
	end
	pinned, pinnedId = nil, nil
	token += 1
	hideHero(function()
		showing = nil
		clearHeroClick()
		drain() -- whatever queued up behind the pin now gets its turn
	end)
end

--- push a notification.
--- spec = { text, top?, sub?, color?, priority?, duration?, lane? ("hero"|"social"), sound? (fn),
---          onClick? (fn), onDone? (fn) }
function NotifyCenter.push(spec)
	if type(spec) ~= "table" or not spec.text then
		return
	end
	spec.priority = spec.priority or PRIORITY.REWARD

	if spec.lane == "social" or spec.priority <= PRIORITY.SOCIAL then
		showSocial(spec.text, spec.color)
		return
	end

	-- Drop an exact repeat within 2s (nag banners re-fire on a loop). onDone MUST still fire: callers hold a
	-- "banner showing" flag that only clears on onDone, so silently swallowing the spec would wedge their queue.
	local now = os.clock()
	if spec.text == lastText and (now - lastAt) < 2 then
		if spec.onDone then
			task.defer(function()
				pcall(spec.onDone)
			end)
		end
		return
	end
	lastText, lastAt = spec.text, now

	-- A pin owns the slot. Everything else waits its turn behind it, in priority order — nothing is dropped, it
	-- just does not get to talk over a standing instruction. A hold shuts the lane the same way.
	if pinned or heroBlocked() then
		enqueue(spec)
		return
	end

	if not showing then
		presentHero(spec)
		return
	end

	if spec.priority > showing.priority then
		-- PREEMPT: the current banner is less important. Put it back at the head of the queue (it still deserves
		-- its moment) and swap the new one in immediately.
		token += 1 -- orphan the outgoing banner's hide timer
		local demoted = showing
		showing = nil
		enqueue(demoted)
		hideHero(function()
			if not showing then
				drain()
			end
		end)
		table.insert(queue, 1, spec) -- the preempting spec must lead the queue
		return
	end

	enqueue(spec) -- equal or lower -> wait your turn
end

--======================================================================
-- THE STANDING-INFO SLOT: directly below the banner card
--======================================================================
-- Some things are not banners. A server event's "15s" countdown and the Cosmic Race's climb/leader/timer strip
-- are STANDING INFO: they belong on screen for as long as the event runs, and they have to stay readable while
-- banners come and go around them.
--
-- They cannot go through the hero lane. `pin` is the right shape (it holds the slot and repaints in place) but
-- the wrong DURATION: a pin outranks everything, so pinning a 6-minute race timer would silence every arrival
-- and purchase banner for six minutes. A banner delayed that long may as well have been dropped.
--
-- So they get their own slot, one row down. It is computed from the TALLEST card (the three-line arrival one),
-- not the card currently showing, so a standing pill never has to move when a taller banner slides in above it
-- — it is clear of every variant by construction.
local PILL_GAP = 10

function NotifyCenter.pillSpot(): UDim2
	local base = PhoneHUD.bannerOn()
	local tallest = cardSize(true).Y.Offset
	return UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset + tallest + PILL_GAP)
end

function NotifyCenter.isBusy(): boolean
	return showing ~= nil or pinned ~= nil
end

function NotifyCenter.isPinned(): boolean
	return pinned ~= nil
end

-- The highest priority currently WAITING in the queue, or 0 when nothing is waiting.
--
-- Added for the objective bridge. A pin owns the slot outright -- that is the whole point of pinning -- so
-- a standing instruction like the quest objective would otherwise sit on top of an island arrival or a live
-- event forever, with those queued behind it and never playing. From outside there was no way to even ask
-- whether anything was waiting: isBusy() answers "is something up", not "is something blocked".
--
-- With this, a long-lived pin can be a good citizen: hold the slot while it is free, step aside the moment
-- something more important arrives, and take it back when the lane clears. Read-only.
function NotifyCenter.queuedTop(): number
	local top = 0
	for _, spec in ipairs(queue) do
		if spec.priority and spec.priority > top then top = spec.priority end
	end
	return top
end

--- The highest priority currently OCCUPYING the hero lane or waiting for it.
---
--- ⚠ USE THIS, NOT queuedTop(), TO DECIDE WHETHER TO PIN. queuedTop only sees the QUEUE, and a card that
--- is on screen right now is not in the queue -- it is `showing`. A poller that pins whenever the queue
--- looks empty will therefore pin straight over a live banner, which re-queues that banner, which makes
--- the queue non-empty again, which makes the poller step aside, which plays the banner a second time...
--- Once a second, for as long as the event lasts. That is exactly what the objective bridge did to every
--- COIN RUSH and POWER SURGE announcement: the card slid in and out repeatedly instead of showing once
--- for its five seconds. Asking about the whole lane instead of half of it is the fix.
function NotifyCenter.laneTop(): number
	local top = NotifyCenter.queuedTop()
	if showing and showing.priority and showing.priority > top then
		top = showing.priority
	end
	return top
end

print("[NotifyCenter] ready \u{2014} HERO lane (shared banner spot, priority queue + pinned instructions) + SOCIAL lane (top-left)")

return NotifyCenter
