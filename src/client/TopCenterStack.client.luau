-- ============================================================================================================
-- TOP-CENTRE STACK  (client)
--
-- FIVE different scripts each park a banner at the top-centre of the screen, and none of them know the others
-- exist. Every one is anchored (0.5, 0) and slides down to roughly the same Y:
--
--     NotifyHero        (NotifyCenter)   "BROCCOLI BLUFF!"      500 x 65
--     ServerEventGui    (CoreClient)     "SERVER EVENT!"        500 x 80
--     EventBannerGui    (EventClient)    the big event banner   500 x 65
--     ArrivalGui        (CoreClient)     "Welcome to ..."       500 x 65
--     AnnounceGui       (CoreClient)     announcements          500 x 65
--
-- So the moment two fire together -- which is exactly when they DO fire, because landing on a new island during a
-- server event is a completely normal thing to happen -- they land on top of each other and you read neither.
--
-- This stacks them instead: still top-centre, but each visible banner sits BELOW the visible ones above it, in a
-- fixed priority order. Nothing overlaps, and the stack compacts as banners come and go.
--
-- ===== HOW IT AVOIDS FIGHTING THEIR ANIMATIONS =====
-- Every one of those banners tweens its OWN Position to slide in from off-screen. If this script simply wrote
-- Position each frame, it would be in a tug-of-war with five tweens and the result would jitter.
--
-- So it never touches the banners. Each is REPARENTED into a full-screen transparent CONTAINER inside its own
-- ScreenGui, and the CONTAINER is what gets moved. The banner keeps sliding around inside its container exactly as
-- its author wrote it; the container just decides where "home" is. The slide-ins still work, untouched.
--
-- Stacking uses AbsoluteSize, not the authored 500x65, so it stays correct on phones -- where CoreClient's UIScale
-- shrinks every banner to ~60% and a hard-coded height would leave a large gap.
-- ============================================================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local TOP_MARGIN = 8   -- px from the top of the screen to the first banner
local GAP        = 8   -- px between stacked banners

-- Priority = stacking order, top to bottom. The most important thing in the game is landing on a new island, so
-- the hero lane owns the top slot and everything else gets pushed under it -- never the other way round.
local ORDER = {
	"NotifyHero",      -- island arrivals, milestones (NotifyCenter's hero lane)
	"ServerEventGui",  -- "SERVER EVENT!"
	"EventBannerGui",  -- the big event banner
	"ArrivalGui",      -- "Welcome to <island>"
	"AnnounceGui",     -- announcements / purchases
}

local tracked = {}  -- [guiName] = { frame = <the banner>, box = <its container> }

-- ===== WHY BANNERS WERE STILL LANDING ON TOP OF EACH OTHER =====
-- Two separate holes, both of which end with a banner drawn at its OWN absolute Y instead of in the stack --
-- which is exactly what "two banners on top of each other" looks like.
--
-- (1) TWO COPIES OF THIS SCRIPT. The boot log lists TopCenterStack among the duplicated LocalScripts (a stale
--     copy baked into the place file runs alongside the Rojo one), and it prints "ready" twice. Both copies
--     adopt, both build a StackBox, and the loser ends up driving an EMPTY box while the banner it thinks it
--     owns lives in the other copy's box. GEN below means the newest copy wins and the older one goes quiet
--     rather than fighting it -- the same retirement other duplicated scripts in this place do.
--
-- (2) REBUILT BANNERS. tracked[] held the FIRST frame it ever saw. When an owner rebuilds its banner --
--     NotifyCenter evicts stale banner guis at boot and re-creates its hero lane, ObjectiveHUD hands the lane
--     back and forth -- the new frame is parented straight to the ScreenGui, loose, positioned by its own
--     author at the top of the screen, while this script keeps carefully stacking the dead one. adopt() now
--     re-checks every pass and takes over whatever frame is currently loose.
--
-- Both fixes are about POSITION only: no banner is hidden, delayed or dropped, so nothing an owner script
-- queued ever goes unseen -- they just cannot occupy the same pixels any more.
local GEN = (_G.__topCenterStackGen or 0) + 1
_G.__topCenterStackGen = GEN
local function current() return _G.__topCenterStackGen == GEN end

-- Wrap a banner in a container we own. The container is full-screen and transparent, so the banner's own
-- (0.5, 0) anchor still centres it horizontally and its own slide tween still runs inside it.
local function adopt(guiName)
	if not current() then return end
	local sg = PlayerGui:FindFirstChild(guiName)
	if not (sg and sg:IsA("ScreenGui")) then return end

	-- A LOOSE Frame directly under the ScreenGui is by definition one this script is not positioning, so it
	-- is drawing itself wherever its author put it. That is true on the first pass (nothing adopted yet) and
	-- equally true later, when an owner script has rebuilt its banner -- so this check runs every pass, not
	-- just once, and re-adopting is how a rebuilt banner rejoins the stack instead of sitting over it.
	local frame
	for _, c in ipairs(sg:GetChildren()) do
		if c:IsA("Frame") and c.Name ~= "StackBox" then frame = c; break end
	end

	local t = tracked[guiName]
	if not frame then
		-- Nothing loose. If what we already hold is still in our box it is fine; if it is not, it was
		-- destroyed or moved and the lane should stop reserving height for it.
		if t and (t.frame.Parent ~= t.box or t.box.Parent == nil) then
			if t.box.Parent then t.box:Destroy() end
			tracked[guiName] = nil
		end
		return
	end
	if t then
		-- A newer banner has appeared while we hold an older one: hand the lane over and take the old box
		-- with it, so a dead frame can never keep pushing the stack down.
		if t.box.Parent then t.box:Destroy() end
		tracked[guiName] = nil
	end

	local box = Instance.new("Frame")
	box.Name = "StackBox"
	box.Size = UDim2.new(1, 0, 1, 0)   -- full-screen: CoreClient's applyScaling treats this as a cover and
	box.Position = UDim2.new(0, 0, 0, 0) -- recurses INTO it, so the banner still gets its UIScale exactly as before
	box.BackgroundTransparency = 1
	box.ZIndex = frame.ZIndex
	box.Parent = sg
	frame.Parent = box

	tracked[guiName] = { frame = frame, box = box }
	print("[TopCenterStack] adopted " .. guiName)
end

-- Banners are built by several scripts at different times, so keep looking rather than assuming they exist at boot.
-- Runs for the life of the session, not 20 seconds. Banners are rebuilt at any time (an event starting, a
-- quest handing the hero lane back), and a rebuild that happens at minute 5 needs re-adopting exactly as much
-- as one at boot -- the old 40-pass window is why late rebuilds ended up drawing themselves.
task.spawn(function()
	local n = 0
	while current() do
		for _, name in ipairs(ORDER) do adopt(name) end
		n = n + 1
		task.wait(n < 40 and 0.5 or 2)   -- eager while everything is still booting, then a quiet heartbeat
	end
end)
PlayerGui.ChildAdded:Connect(function(sg)
	task.defer(function()
		for _, name in ipairs(ORDER) do
			if sg.Name == name then adopt(name) end
		end
	end)
end)

RunService.Heartbeat:Connect(function()
	if not current() then return end   -- an older duplicate of this script: stay out of the newer one's way
	local y = TOP_MARGIN
	for _, name in ipairs(ORDER) do
		local t = tracked[name]
		if t and t.frame.Parent then
			if t.frame.Visible then
				-- Offset the CONTAINER by however much stack sits above it. The banner's own resting Y (its author's
				-- top margin) still applies inside the container, so this only ever ADDS clearance -- it can never
				-- pull a banner up into the one above it.
				t.box.Position = UDim2.new(0, 0, 0, y)
				local h = t.frame.AbsoluteSize.Y            -- LIVE height: already includes the phone UIScale
				if h > 1 then y = y + h + GAP end
			else
				t.box.Position = UDim2.new(0, 0, 0, 0)      -- hidden: park it, contributes nothing to the stack
			end
		end
	end
end)

print("[TopCenterStack] build 2 ACTIVE (gen " .. GEN .. ") -- re-adopts rebuilt banners, and only the "
	.. "newest copy of this script drives the stack")
print("[TopCenterStack] ready -- top-centre banners stack instead of overlapping ("
	.. #ORDER .. " lanes, priority: " .. table.concat(ORDER, " > ") .. ")")
