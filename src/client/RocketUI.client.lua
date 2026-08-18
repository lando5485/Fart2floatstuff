--======================================================================
-- RocketUI.client.lua  (LocalScript)
--======================================================================
-- Client-side presentation for the Rocket event. Listens to the
-- RocketEventSync RemoteEvent and renders:
--   * the global notification banner ("🚀 Rocket Construction Event Starting!")
--   * the big countdown text ("Launch in n…")
--   * the launch / end banner text
--
-- It also performs the CLIENT-ONLY presentation effects that cannot be
-- server parts because they are per-client camera/screen effects:
--   * camera shake near the launch site
--   * the brief sky flash on explosion
-- (These live on the client because each player has their own Camera and
--  Lighting view — the server can't shake one player's camera.)
--
-- This script never touches gameplay state (meter/flight/food/etc).
--======================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local sync = ReplicatedStorage:WaitForChild("RocketEventSync")
-- Server teleport to island 1's stand (same teleport the game uses elsewhere).
local GoToIsland1Event = ReplicatedStorage:WaitForChild("GoToIsland1Event")

--======================================================================
-- Build the ScreenGui (banner + countdown labels).
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "RocketEventUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

-- Notification banner (top of screen).
local BANNER_BG_VISIBLE = 0.25  -- the opaque background transparency when showing
local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0.05, 0)
banner.Size = UDim2.new(0.6, 0, 0.08, 0)
banner.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
banner.BackgroundTransparency = 1  -- fully invisible when idle
banner.TextColor3 = Color3.fromRGB(255, 240, 200)
banner.TextScaled = true
banner.Font = Enum.Font.GothamBold
banner.Text = ""
banner.ZIndex = 20
banner.Visible = false
banner.Parent = gui
local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 12)
bannerCorner.Parent = banner

-- Shared across all event banners (one per client) so concurrent announcements
-- stack vertically instead of covering each other.
_G.__eventBannerSlots = _G.__eventBannerSlots or {}
-- 0.17, NOT 0.05 -- see the identical note in MeteorUI (both share _G.__eventBannerSlots, so these two
-- constants MUST stay in step). At 0.05 this stack ran through the hero banner and the objective card.
local BANNER_BASE_Y = 0.17   -- topmost banner Y (scale) -- below the hero banner + objective card
local BANNER_SLOT_H = 0.10   -- vertical gap per slot (> banner height 0.08, no overlap)
local bannerSlot = nil       -- this banner's currently-claimed slot, or nil
local function claimBannerSlot()
	if bannerSlot then return bannerSlot end
	local slots = _G.__eventBannerSlots
	local i = 1
	while slots[i] do i = i + 1 end
	slots[i] = true
	bannerSlot = i
	return i
end
local function freeBannerSlot()
	if bannerSlot then _G.__eventBannerSlots[bannerSlot] = nil; bannerSlot = nil end
end
local function bannerSlotY(i) return BANNER_BASE_Y + (i - 1) * BANNER_SLOT_H end

-- Big countdown text (centre).
local countdown = Instance.new("TextLabel")
countdown.Name = "Countdown"
countdown.AnchorPoint = Vector2.new(0.5, 0.5)
countdown.Position = UDim2.new(0.5, 0, 0.35, 0)
countdown.Size = UDim2.new(0.4, 0, 0.2, 0)
countdown.BackgroundTransparency = 1
countdown.TextColor3 = Color3.fromRGB(255, 90, 60)
countdown.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
countdown.TextStrokeTransparency = 0.3
countdown.TextScaled = true
countdown.Font = Enum.Font.GothamBlack
countdown.Text = ""
countdown.Visible = false
countdown.Parent = gui

-- Countdown / LIFTOFF text control. A generation token guarantees a scheduled
-- auto-hide only ever clears the SAME message it was scheduled for (never a newer
-- one) AND that the LIFTOFF always disappears. hideCountdown() bumps the token, so
-- it instantly invalidates any pending auto-hide and leaves the label blank + hidden.
local countdownGen = 0
local function showCountdown(text)
	countdownGen = countdownGen + 1
	countdown.Text = text
	countdown.Visible = true
	return countdownGen
end
local function hideCountdown()
	countdownGen = countdownGen + 1   -- invalidate any pending auto-hide
	countdown.Visible = false
	countdown.Text = ""
end

--======================================================================
-- "Go to Island 1" teleport button. Visible ONLY while the rocket event is
-- active (shown on "start", hidden on "end"/cleanup). TOP-MIDDLE of the screen,
-- below the announcement banner, so it's clearly separated from the existing
-- "Return to Island 1" corner button and clears the bottom HUD (gas meter /
-- fart button) + coin pill. Clicking teleports the player to island 1's stand
-- (server-authoritative, same teleport the game already uses).
--======================================================================
local teleportBtn = Instance.new("TextButton")
teleportBtn.Name = "GoToIsland1Btn"
-- JUST ABOVE THE FART METER, bottom-centre. It lived in the top-right status column, which is where the
-- coin capsule, the gear and the stats panel all live -- on a scaled screen it overlapped them. The strip
-- directly above the bottom HUD stack is the one place nothing else claims, and this button is only ever
-- on screen during the rocket event, so borrowing that strip costs nothing the rest of the time.
-- Compact, and positioned for real against the stack's live top edge by placeTeleportBtn() below.
teleportBtn.AnchorPoint = Vector2.new(0.5, 1)
teleportBtn.Position = UDim2.new(0.5, 0, 1, -260)
teleportBtn.Size = UDim2.new(0, 190, 0, 44)
teleportBtn.BackgroundColor3 = Color3.fromRGB(55, 170, 90)
teleportBtn.AutoButtonColor = true
teleportBtn.Font = Enum.Font.GothamBold
teleportBtn.Text = "🚀 Go to Island 1"
teleportBtn.TextScaled = true
teleportBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
-- Fully invisible by default (Visible=false AND transparent), like the event
-- banners, so nothing shows at game load even if Visible is flipped elsewhere.
teleportBtn.Visible = false
teleportBtn.Active = false        -- NON-interactive until the rocket event starts (an invisible Active button still receives clicks -> this is the bug being fixed)
teleportBtn.Selectable = false    -- and not gamepad-selectable while hidden
teleportBtn.BackgroundTransparency = 1
teleportBtn.TextTransparency = 1
teleportBtn.ZIndex = 20
teleportBtn.Parent = gui
local tbCorner = Instance.new("UICorner")
tbCorner.CornerRadius = UDim.new(0, 12)
tbCorner.Parent = teleportBtn
local tbStroke = Instance.new("UIStroke")
tbStroke.Color = Color3.fromRGB(0, 90, 40)
tbStroke.Thickness = 3
tbStroke.Transparency = 1                          -- invisible until the event shows it
tbStroke.Parent = teleportBtn
local tbPad = Instance.new("UIPadding")
tbPad.PaddingTop = UDim.new(0, 8); tbPad.PaddingBottom = UDim.new(0, 8)
tbPad.PaddingLeft = UDim.new(0, 10); tbPad.PaddingRight = UDim.new(0, 10)
tbPad.Parent = teleportBtn

-- TRUE only while the rocket event is actively running. The click handler is guarded by it so the
-- button can NEVER teleport when the event isn't running -- even if it somehow ends up clickable.
local eventActive = false

teleportBtn.Activated:Connect(function()
	if not eventActive then return end   -- HARD GUARD: no rocket event -> no teleport (covers any invisible-but-clickable edge case)
	if _G.playUIClick then pcall(_G.playUIClick) end
	GoToIsland1Event:FireServer()   -- server teleports us to island 1's stand
end)

-- SIT IT ON THE BOTTOM STACK'S LIVE TOP EDGE. The stack (gut pill / gas meter / fart button) changes
-- height with device scale and with which of its rows are showing, so a fixed offset would gap on one
-- screen and overlap on another. CoreClient publishes the frame as _G.gui.bottomStack and both guis use
-- IgnoreGuiInset, so they share a coordinate space and AbsolutePosition can be used directly. Falls back
-- to a safe bottom-centre offset if the stack has not laid out yet.
local function placeTeleportBtn()
	local bs = _G.gui and _G.gui.bottomStack
	if bs and bs.AbsoluteSize.Y > 0 then
		teleportBtn.Position = UDim2.new(0.5, 0, 0, math.floor(bs.AbsolutePosition.Y) - 10)
	else
		teleportBtn.Position = UDim2.new(0.5, 0, 1, -260)
	end
end
do
	local bs = _G.gui and _G.gui.bottomStack
	if bs then -- follow the stack as it lays out / rescales, but only while the button is up
		bs:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			if teleportBtn.Visible then placeTeleportBtn() end
		end)
		bs:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if teleportBtn.Visible then placeTeleportBtn() end
		end)
	end
end

--======================================================================
-- ARE WE ALREADY THERE?
--======================================================================
-- A "Go to Island 1" button offered to somebody standing on Island 1 is a button that does nothing, and it
-- sits in the one strip of screen the bottom HUD does not already own -- so it is worth the check.
--
-- ===== WHY THIS IS NOT A leaderstats.Island TEST =====
-- That value is the HIGHEST island the player has unlocked, not where they are. A player who has reached
-- Pizza Palms and flown back down to the farm reads as Island 14 while standing on Island 1, which is
-- exactly backwards. Position is the only honest answer to "am I there".
--
-- ===== AND WHY IT CANNOT BE A HEIGHT TEST EITHER =====
-- The obvious cheap check is "Y below 500" -- Island 1 sits at Y=150 and Island 2 at Y=790, so height alone
-- separates them cleanly. It is also wrong, because the rocket's own capsule is parked at VOID_Y = 190,
-- squarely inside that band. A rider strapped into the couch would read as "on Island 1" and lose the
-- button for the whole ride. The capsule is thousands of studs out HORIZONTALLY (see RocketRideClient's
-- origin), so the horizontal test is the one that actually distinguishes them -- height is only the tiebreak
-- against the islands stacked directly overhead.
local ISLAND1_XZ = 400   -- generous: Island 1's furthest dressing sits ~150 studs out from its centre
local ISLAND1_Y  = 250   -- covers standing on the stand (Y~245) without reaching Island 2 (Y=790)

local function onIsland1()
	local ch  = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	-- _G.ISLAND_POS is CoreClient's table and may not exist yet on a very early frame; Island 1 is the
	-- world origin, so falling back to (0, 150, 0) costs nothing and keeps this working during boot.
	local p = (_G.ISLAND_POS and _G.ISLAND_POS[1]) or { x = 0, y = 150, z = 0 }
	local d = hrp.Position - Vector3.new(p.x, p.y, p.z)
	return (Vector3.new(d.X, 0, d.Z).Magnitude <= ISLAND1_XZ) and (math.abs(d.Y) <= ISLAND1_Y)
end

-- Show/hide helpers: toggle Visible AND the transparencies together so the
-- button is genuinely invisible when no rocket event is running.
--
-- SPLIT IN TWO ON PURPOSE. `eventActive` means "the rocket event is running" and is owned solely by the
-- server broadcasts -- the click handler's hard guard depends on that meaning, so the island-1 check must
-- never touch it. Whether the button is actually ON SCREEN is a separate question, re-answered continuously
-- by applyTeleportBtn() below, because a player walks on and off Island 1 all through the event.
local function applyTeleportBtn()
	local want = eventActive and not onIsland1()
	if teleportBtn.Visible == want then return end   -- idempotent: the poll below calls this constantly
	if want then
		teleportBtn.BackgroundTransparency = 0
		teleportBtn.TextTransparency = 0
		tbStroke.Transparency = 0
		teleportBtn.Active = true        -- clickable ONLY when it is genuinely on screen
		teleportBtn.Selectable = true
		placeTeleportBtn()               -- re-measure every time it appears (scale may have changed since load)
		teleportBtn.Visible = true
	else
		teleportBtn.Visible = false
		teleportBtn.Active = false        -- non-interactive: cannot be clicked / cannot teleport when hidden
		teleportBtn.Selectable = false
		teleportBtn.BackgroundTransparency = 1
		teleportBtn.TextTransparency = 1
		tbStroke.Transparency = 1
	end
	print(("[RocketBtn] event active=%s onIsland1=%s -> button visible=%s")
		:format(tostring(eventActive), tostring(onIsland1()), tostring(want)))
end

local function showTeleportBtn()
	eventActive = true
	applyTeleportBtn()
end
local function hideTeleportBtn()
	eventActive = false
	applyTeleportBtn()
end

-- The player crosses the boundary under their own power -- they fly off Island 1, or they take the teleport
-- and arrive. Neither fires an event we could listen to, so the state is re-derived on a slow poll. Gated on
-- eventActive so it costs nothing outside a rocket event, and applyTeleportBtn returns early when nothing
-- has changed, so the steady state is one distance check every half second.
task.spawn(function()
	while true do
		task.wait(0.5)
		if eventActive then applyTeleportBtn() end
	end
end)

--======================================================================
-- Helper: briefly show the banner then auto-hide.
--======================================================================
local function hideBanner()
	banner.Visible = false
	banner.BackgroundTransparency = 1
	banner.Text = ""
	freeBannerSlot()
end

-- ===== THE ROCKET SPEAKS THROUGH NOTIFYCENTER NOW =====
-- This banner was built before NotifyCenter existed and never moved over, so the biggest event in the game
-- was announcing itself in a completely different voice from everything else: its own ScreenGui, its own
-- font, its own dark box, parked at y=0.05 with its own private slot system -- and, because it is not one of
-- the five GUIs TopCenterStack manages, nothing stopping it drawing straight through an island banner or a
-- Shady Sal restock that happened to land at the same moment.
--
-- It now pushes to the HERO lane like every other announcement. That buys three things for free: the house
-- banner shape, the queue (so it takes turns instead of overlapping), and EVENT priority -- which is exactly
-- right for a rocket. It yields to "you just landed on a new island" (ISLAND, 100) and to a real Robux
-- purchase (90), and beats every reward nudge.
--
-- The old local banner is KEPT as a fallback rather than deleted, for the case NotifyCenter is missing or is
-- an older build without the API. A rocket launch nobody was told about is a worse outcome than a banner in
-- the wrong font, and this file already runs in three realms that may not all be on the same NotifyCenter.
local function showBanner(text, duration)
	local NC = _G.NotifyCenter
	if NC and NC.push then
		pcall(NC.push, {
			text     = text,
			color    = Color3.fromRGB(255, 150, 60),   -- rocket amber, distinct from Sal's and the island green
			priority = (NC.PRIORITY and NC.PRIORITY.EVENT) or 80,
			duration = duration or 4,
		})
		return
	end

	local slot = claimBannerSlot()
	banner.Position = UDim2.new(0.5, 0, bannerSlotY(slot), 0)
	banner.Text = text
	banner.BackgroundTransparency = BANNER_BG_VISIBLE
	banner.Visible = true
	task.delay(duration or 4, function()
		-- Only hide if the text hasn't been replaced since.
		if banner.Text == text then
			hideBanner()
		end
	end)
end

--======================================================================
-- CLIENT EFFECT: camera shake near the launch site.
-- We offset the Camera's CFrame with decaying random jitter. We only
-- shake meaningfully if the player is reasonably near the site so far-
-- away players aren't rattled for no reason.
--======================================================================
local function cameraShake(sitePos, intensity, seconds)
	local cam = workspace.CurrentCamera
	if not cam then return end

	-- Falloff by distance from the site (no shake if very far away).
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local scale = 1
	if hrp and typeof(sitePos) == "Vector3" then
		local dist = (hrp.Position - sitePos).Magnitude
		scale = math.clamp(1 - dist / 600, 0, 1) -- fades out past ~600 studs
	end
	if scale <= 0 then return end

	local amp = (intensity or 0.6) * scale
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - t0
		if elapsed >= (seconds or 0.4) then
			conn:Disconnect()
			return
		end
		local decay = 1 - (elapsed / (seconds or 0.4))
		local jitter = CFrame.new(
			(math.random() - 0.5) * amp * decay,
			(math.random() - 0.5) * amp * decay,
			0)
		cam.CFrame = cam.CFrame * jitter
	end)
end

--======================================================================
-- CLIENT EFFECT: brief sky flash on explosion (per-client Lighting).
--======================================================================
local function skyFlash()
	-- Use a ColorCorrection so we don't permanently alter base Lighting.
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0.6
	cc.Contrast = 0.2
	cc.TintColor = Color3.fromRGB(255, 230, 200)
	cc.Parent = Lighting

	local TweenService = game:GetService("TweenService")
	local fade = TweenService:Create(cc,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0, Contrast = 0 })
	fade:Play()
	fade.Completed:Connect(function()
		cc:Destroy()
	end)
end

--======================================================================
-- LOAD-TIME CLEAN SLATE: nothing event-driven should be visible at game load. All
-- elements already construct hidden; this is the belt-and-suspenders clear so no
-- LIFTOFF / countdown / banner / teleport button can persist from a prior state.
--======================================================================
hideBanner()
hideCountdown()
hideTeleportBtn()

--======================================================================
-- Listen to the server-driven sync events.
--======================================================================
sync.OnClientEvent:Connect(function(phase, payload)
	if phase == "start" then
		showBanner(payload or "🚀 The Big Rocket Construction Event Starting! Everyone go to Island 1!", 5)
		showTeleportBtn()   -- show the "Go to Island 1" button for the event

	elseif phase == "boarding" then
		-- THE HATCH IS OPEN. Nobody will look for a boarding prompt on a rocket that has never had one, so
		-- the event has to say out loud that this launch is rideable -- it is announced once, here, and the
		-- prompt itself is then the only other thing the player needs.
		showBanner("🚀 The hatch is OPEN! Hold E at the rocket's base to ride it!", 6)

	elseif phase == "countdown" then
		-- payload = the number n.
		showCountdown("Launch in " .. tostring(payload) .. "…")

	elseif phase == "shake" then
		-- payload = the site Vector3.
		cameraShake(payload, 0.6, 0.4)

	elseif phase == "launch" then
		-- LIFTOFF shows ONLY during the launch phase: shown here, auto-hidden after
		-- 2s, and force-cleared on "end". The token makes the hide robust — it fires
		-- for THIS LIFTOFF even if the text changed, and never hides a newer message.
		local g = showCountdown("🚀 LIFTOFF!")
		task.delay(2, function()
			if countdownGen == g then hideCountdown() end
		end)

	elseif phase == "flash" then
		skyFlash()
		-- A bigger shake for the explosion is harmless even if far (it falls off).
		cameraShake(workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position, 0.4, 0.5)

	elseif phase == "end" then
		hideCountdown()     -- launch/event over -> the LIFTOFF (and any countdown) disappears immediately
		hideTeleportBtn()   -- event over -> hide the teleport button
		showBanner(payload or "🚀 The rocket reached the stars!", 4)
	end
end)
