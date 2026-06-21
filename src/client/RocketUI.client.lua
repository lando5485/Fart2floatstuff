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
local BANNER_BASE_Y = 0.05   -- topmost banner Y (scale)
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
teleportBtn.AnchorPoint = Vector2.new(0.5, 0)
teleportBtn.Position = UDim2.new(0.5, 0, 0.20, 0)  -- horizontally centered, near top (below the banner)
teleportBtn.Size = UDim2.new(0, 210, 0, 50)
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

-- Show/hide helpers: toggle Visible AND the transparencies together so the
-- button is genuinely invisible when no rocket event is running.
local function showTeleportBtn()
	eventActive = true
	teleportBtn.BackgroundTransparency = 0
	teleportBtn.TextTransparency = 0
	tbStroke.Transparency = 0
	teleportBtn.Active = true        -- clickable ONLY now (event is running)
	teleportBtn.Selectable = true
	teleportBtn.Visible = true
	print("[RocketBtn] event active=true -> button visible=true")
end
local function hideTeleportBtn()
	eventActive = false
	teleportBtn.Visible = false
	teleportBtn.Active = false        -- non-interactive: cannot be clicked / cannot teleport when hidden
	teleportBtn.Selectable = false
	teleportBtn.BackgroundTransparency = 1
	teleportBtn.TextTransparency = 1
	tbStroke.Transparency = 1
	print("[RocketBtn] event active=false -> button visible=false")
end

--======================================================================
-- Helper: briefly show the banner then auto-hide.
--======================================================================
local function hideBanner()
	banner.Visible = false
	banner.BackgroundTransparency = 1
	banner.Text = ""
	freeBannerSlot()
end

local function showBanner(text, duration)
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
