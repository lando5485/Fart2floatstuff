--======================================================================
-- MeteorUI.client.lua  (LocalScript)
--======================================================================
-- Client-side presentation for the global "MeteorStorm" event. Listens to
-- the MeteorSync RemoteEvent and renders everything that MUST live on the
-- client because it is per-client (this player's Camera / Lighting view /
-- owned-character physics) and cannot be a shared server part:
--
--   * announcement banners + warning sirens ("METEOR SHOWER INCOMING!",
--     "LEGENDARY METEOR DETECTED!", "Meteor Shower Ending...").
--   * cinematic SKY changes (dark red/orange via ColorCorrection +
--     Atmosphere + fog + ClockTime + drifting embers + distant streaks) --
--     all FULLY RESTORED on "reset".
--   * camera shake on impacts.
--   * APPLYING the server-decided KNOCKBACK to the LOCAL player's own
--     HumanoidRootPart.
--
-- WHY CLIENT-SIDE:
--   - Sky + camera shake live here because each player has their own Camera
--     and Lighting view; the server can't shake one player's camera or tint
--     one player's sky.
--   - Knockback is applied here because clients OWN their character physics
--     (network ownership). A server-set HRP velocity wouldn't stick
--     reliably, so the server decides WHO is hit + the vector, and this
--     client applies the impulse to its OWN HRP.
--
-- This script NEVER touches gameplay state: it only nudges the HRP's
-- velocity for knockback. It never reads or writes the gas meter, fart
-- power, flight, food, guts, height, the earn rate, or coins.
--======================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local sync = ReplicatedStorage:WaitForChild("MeteorSync")

--======================================================================
-- ScreenGui: banner (top) + small reward popup (bottom).
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "MeteorEventUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 51
gui.Parent = player:WaitForChild("PlayerGui")

local BANNER_BG_VISIBLE = 0.2  -- the opaque background transparency when showing
local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0.14, 0)
banner.Size = UDim2.new(0.6, 0, 0.08, 0)
banner.BackgroundColor3 = Color3.fromRGB(40, 12, 12)
banner.BackgroundTransparency = 1  -- fully invisible when idle
banner.TextColor3 = Color3.fromRGB(255, 220, 180)
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

local rewardPopup = Instance.new("TextLabel")
rewardPopup.Name = "RewardPopup"
rewardPopup.AnchorPoint = Vector2.new(0.5, 1)
rewardPopup.Position = UDim2.new(0.5, 0, 0.85, 0)
rewardPopup.Size = UDim2.new(0.25, 0, 0.06, 0)
rewardPopup.BackgroundTransparency = 1
rewardPopup.TextColor3 = Color3.fromRGB(255, 230, 120)
rewardPopup.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
rewardPopup.TextStrokeTransparency = 0.3
rewardPopup.TextScaled = true
rewardPopup.Font = Enum.Font.GothamBlack
rewardPopup.Text = ""
rewardPopup.Visible = false
rewardPopup.Parent = gui

local function hideBanner()
	banner.Visible = false
	banner.BackgroundTransparency = 1
	banner.Text = ""
	freeBannerSlot()
end

local function showBanner(text, duration, color)
	local slot = claimBannerSlot()
	banner.Position = UDim2.new(0.5, 0, bannerSlotY(slot), 0)
	banner.Text = text
	banner.BackgroundColor3 = color or Color3.fromRGB(40, 12, 12)
	banner.BackgroundTransparency = BANNER_BG_VISIBLE
	banner.Visible = true
	task.delay(duration or 4, function()
		if banner.Text == text then hideBanner() end
	end)
end

local function showReward(coins)
	rewardPopup.Text = "+" .. tostring(coins) .. " Coins!"
	rewardPopup.Visible = true
	task.delay(2.5, function()
		if rewardPopup.Text == "+" .. tostring(coins) .. " Coins!" then
			rewardPopup.Visible = false
		end
	end)
end

--======================================================================
-- SKY STORM: dark red/orange Lighting changes that are FULLY restored on
-- reset. We create our OWN ColorCorrection + Atmosphere instances and tween
-- the base Lighting props from saved originals, so nothing is left altered.
--======================================================================
local stormCC = nil        -- our ColorCorrectionEffect
local stormAtmos = nil     -- our Atmosphere
local emberFolder = nil    -- drifting ember parts (client-only, in Camera space)
local emberConn = nil      -- ember drift Heartbeat connection
local savedLighting = nil  -- snapshot of base Lighting props to restore

local function snapshotLighting()
	if savedLighting then return end -- already saved this storm
	savedLighting = {
		ClockTime = Lighting.ClockTime,
		FogColor = Lighting.FogColor,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		Brightness = Lighting.Brightness,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}
end

local function startSky()
	snapshotLighting()

	-- Tint the whole view dark red/orange via our OWN ColorCorrection.
	if not stormCC then
		stormCC = Instance.new("ColorCorrectionEffect")
		stormCC.Name = "MeteorStormCC"
		stormCC.Parent = Lighting
	end
	stormCC.Brightness = 0
	stormCC.Contrast = 0
	stormCC.TintColor = Color3.fromRGB(255, 255, 255)
	TweenService:Create(stormCC, TweenInfo.new(2),
		{ Contrast = 0.15, TintColor = Color3.fromRGB(255, 170, 130) }):Play()

	-- Heavy reddish atmosphere/haze via our OWN Atmosphere.
	if not stormAtmos then
		stormAtmos = Instance.new("Atmosphere")
		stormAtmos.Name = "MeteorStormAtmosphere"
		stormAtmos.Parent = Lighting
	end
	stormAtmos.Density = 0.3
	stormAtmos.Color = Color3.fromRGB(180, 90, 60)
	stormAtmos.Decay = Color3.fromRGB(120, 50, 30)
	stormAtmos.Haze = 2.5
	stormAtmos.Glare = 0.4

	-- Darken + redden the base Lighting (restored on reset from the snapshot).
	TweenService:Create(Lighting, TweenInfo.new(2.5), {
		ClockTime = 17.6,                              -- dusk-ish, ominous
		FogColor = Color3.fromRGB(120, 50, 35),
		FogEnd = 3500,
		FogStart = 200,
		Brightness = math.max(1, (savedLighting.Brightness or 2) * 0.6),
		OutdoorAmbient = Color3.fromRGB(90, 55, 50),
	}):Play()

	-- Drifting embers around the camera (client-only cosmetic particles).
	if not emberFolder then
		emberFolder = Instance.new("Folder")
		emberFolder.Name = "MeteorStormEmbers"
		emberFolder.Parent = workspace.CurrentCamera or workspace
		-- One anchor part following the camera, hosting a capped emitter.
		local anchor = Instance.new("Part")
		anchor.Name = "EmberAnchor"
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Parent = emberFolder
		local ember = Instance.new("ParticleEmitter")
		ember.Texture = "rbxasset://textures/particles/fire_main.dds"
		ember.Rate = 16                                 -- capped, cosmetic
		ember.Lifetime = NumberRange.new(2, 4)
		ember.Speed = NumberRange.new(2, 6)
		ember.SpreadAngle = Vector2.new(180, 180)
		ember.Size = NumberSequence.new(0.3)
		ember.Color = ColorSequence.new(Color3.fromRGB(255, 150, 60), Color3.fromRGB(180, 40, 0))
		ember.LightEmission = 1
		ember.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		ember.Acceleration = Vector3.new(0, -3, 0)
		ember.Parent = anchor
		-- Keep the ember anchor centered on the camera so embers fill the view.
		emberConn = RunService.RenderStepped:Connect(function()
			local cam = workspace.CurrentCamera
			if cam and anchor and anchor.Parent then
				anchor.CFrame = cam.CFrame * CFrame.new(0, 0, -30)
			end
		end)
	end
end

local function restoreSky()
	-- Tween base Lighting back to the saved originals, then drop our effects.
	if savedLighting then
		TweenService:Create(Lighting, TweenInfo.new(2.5), {
			ClockTime = savedLighting.ClockTime,
			FogColor = savedLighting.FogColor,
			FogEnd = savedLighting.FogEnd,
			FogStart = savedLighting.FogStart,
			Brightness = savedLighting.Brightness,
			OutdoorAmbient = savedLighting.OutdoorAmbient,
		}):Play()
	end

	if stormCC then
		local cc = stormCC
		stormCC = nil
		local fade = TweenService:Create(cc, TweenInfo.new(2),
			{ Contrast = 0, TintColor = Color3.fromRGB(255, 255, 255) })
		fade:Play()
		fade.Completed:Connect(function() cc:Destroy() end)
	end
	if stormAtmos then
		local at = stormAtmos
		stormAtmos = nil
		local fade = TweenService:Create(at, TweenInfo.new(2), { Density = 0, Haze = 0, Glare = 0 })
		fade:Play()
		fade.Completed:Connect(function() at:Destroy() end)
	end
	if emberConn then emberConn:Disconnect() emberConn = nil end
	if emberFolder then
		local f = emberFolder
		emberFolder = nil
		-- Stop emitting then destroy so in-flight embers fade out.
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("ParticleEmitter") then d.Enabled = false end
		end
		task.delay(4, function() if f then f:Destroy() end end)
	end
	-- Clear the snapshot so a future storm re-captures fresh originals.
	savedLighting = nil
end

--======================================================================
-- CLIENT EFFECT: camera shake (decaying random jitter). Falls off with
-- distance from the impact so far-away players aren't rattled hard.
--======================================================================
local function cameraShake(impactPos, intensity, seconds)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local scale = 1
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and typeof(impactPos) == "Vector3" then
		local dist = (hrp.Position - impactPos).Magnitude
		scale = math.clamp(1 - dist / 800, 0, 1) -- fades out past ~800 studs
	end
	if scale <= 0 then return end

	local amp = (intensity or 0.6) * scale
	local t0 = os.clock()
	local dur = seconds or 0.45
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - t0
		if elapsed >= dur then conn:Disconnect() return end
		local decay = 1 - (elapsed / dur)
		local jitter = CFrame.new(
			(math.random() - 0.5) * amp * decay,
			(math.random() - 0.5) * amp * decay,
			0)
		cam.CFrame = cam.CFrame * jitter
	end)
end

--======================================================================
-- CLIENT EFFECT: brief sky flash on a big/legendary impact.
--======================================================================
local function skyFlash(strong)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = strong and 0.9 or 0.5
	cc.Contrast = 0.2
	cc.TintColor = strong and Color3.fromRGB(255, 240, 180) or Color3.fromRGB(255, 200, 150)
	cc.Parent = Lighting
	local fade = TweenService:Create(cc,
		TweenInfo.new(strong and 1.0 or 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0, Contrast = 0 })
	fade:Play()
	fade.Completed:Connect(function() cc:Destroy() end)
end

--======================================================================
-- GAMEPLAY: apply the server-decided KNOCKBACK to the LOCAL player's HRP.
-- We ONLY set the HRP's assembly velocity (a pure physics nudge). We do
-- NOT touch gas / fart power / flight / coins / any gameplay variable.
--======================================================================
local function applyKnockback(payload)
	if typeof(payload) ~= "table" then return end
	local dir = payload.dir
	local force = payload.force
	if typeof(dir) ~= "Vector3" or typeof(force) ~= "number" then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	-- Add the impulse to the current velocity so it reads as a shove, blending
	-- with whatever the player was already doing (including flying upward).
	hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + (dir * force)
end

--======================================================================
-- LOAD-TIME CLEAN SLATE: no event text shows at game load (elements already
-- construct hidden; belt-and-suspenders, matching the blanket event-text rule).
--======================================================================
hideBanner()
rewardPopup.Visible = false

--======================================================================
-- Listen to the server-driven sync events.
--======================================================================
sync.OnClientEvent:Connect(function(phase, payload)
	if phase == "start" then
		startSky()
		showBanner(payload or "\u{2604} METEOR SHOWER INCOMING!", 5, Color3.fromRGB(60, 15, 15))

	elseif phase == "warning" then
		showBanner(payload or "Take cover! Meteors approaching...", 4, Color3.fromRGB(60, 30, 10))

	elseif phase == "distant" then
		-- A faint distant rumble shake during the warning phase.
		local cam = workspace.CurrentCamera
		cameraShake(cam and cam.CFrame.Position, (payload and payload.intensity) or 0.2, 0.3)

	elseif phase == "main" then
		showBanner(payload or "\u{2604} METEOR SHOWER!", 3, Color3.fromRGB(70, 15, 15))

	elseif phase == "legendaryIncoming" then
		showBanner(payload or "\u{1F31F} LEGENDARY METEOR DETECTED!", 5, Color3.fromRGB(70, 55, 0))

	elseif phase == "impact" then
		-- payload = { position, intensity, legendary }
		local pos = typeof(payload) == "table" and payload.position or nil
		local intensity = (typeof(payload) == "table" and payload.intensity) or 0.6
		local legendary = typeof(payload) == "table" and payload.legendary
		cameraShake(pos, intensity, legendary and 0.7 or 0.45)
		if legendary then skyFlash(true) end

	elseif phase == "knockback" then
		-- Server decided THIS client is near an impact: nudge our own HRP.
		applyKnockback(payload)

	elseif phase == "reward" then
		showReward((typeof(payload) == "table" and payload.coins) or 0)

	elseif phase == "legendaryClaimed" then
		local who = (typeof(payload) == "table" and payload.player) or "Someone"
		local amt = (typeof(payload) == "table" and payload.coins) or 0
		showBanner("\u{1F31F} " .. who .. " claimed the LEGENDARY meteor! +" .. amt,
			5, Color3.fromRGB(70, 55, 0))

	elseif phase == "ending" then
		showBanner(payload or "\u{2604} Meteor Shower Ending\u{2026}", 4, Color3.fromRGB(40, 20, 20))

	elseif phase == "reset" then
		-- Full restore of the sky/Lighting + cleanup of client cosmetics.
		hideBanner()
		rewardPopup.Visible = false  -- force-hide the transient reward popup so it can't linger past the event
		restoreSky()
	end
end)
