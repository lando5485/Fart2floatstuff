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

-- Wrap a banner in a container we own. The container is full-screen and transparent, so the banner's own
-- (0.5, 0) anchor still centres it horizontally and its own slide tween still runs inside it.
local function adopt(guiName)
	if tracked[guiName] then return end
	local sg = PlayerGui:FindFirstChild(guiName)
	if not (sg and sg:IsA("ScreenGui")) then return end

	-- the banner is the ScreenGui's Frame child (skip anything we already made)
	local frame
	for _, c in ipairs(sg:GetChildren()) do
		if c:IsA("Frame") and c.Name ~= "StackBox" then frame = c; break end
	end
	if not frame then return end

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
task.spawn(function()
	for _ = 1, 40 do
		for _, name in ipairs(ORDER) do adopt(name) end
		task.wait(0.5)
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

print("[TopCenterStack] ready -- top-centre banners stack instead of overlapping ("
	.. #ORDER .. " lanes, priority: " .. table.concat(ORDER, " > ") .. ")")
