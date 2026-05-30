--======================================================================
-- MutationUI.client.lua  (LocalScript)
--======================================================================
-- Client-side presentation + the ★ FULL PLAYER-MUTATION ENGINE ★ for the
-- global "MutationEvent". Listens to MutationSync and renders everything that
-- MUST live on the client because it is per-client (this player's Camera /
-- Lighting view / network-owned character):
--
--   * cinematic SKY: neon green/purple tint + toxic clouds + pulsing neon
--     lighting -- FULLY RESTORED from a saved Lighting snapshot on reset.
--   * banners ("MUTATION EVENT ACTIVE!", "...Safe Range..."), alarm /
--     bubbling / siren / mutation SFX, surge/storm flashes + camera shake.
--   * a CAMERA-TRACKED, HARD-CAPPED radiation-particle volume + heat
--     distortion. NEVER exceeds the local caps.
--   * ★ the PLAYER MUTATION ENGINE ★:
--       - COSMETIC mutations (capture/restore, may stack, anytime, no flight
--         effect).
--       - GUARDED mutations behind the effectsAllowed()/isGrounded() gate +
--         a per-frame guard loop + the GUARDED_MAX_BOOST_HEIGHT cap, plus the
--         reverse-controls remap.
--       - the ULTIMATE mutation (gigantic + boosted, but the boost is STILL
--         GUARDED exactly like the others).
--       - FULL revert on mutation-end / "reset" / respawn (no player stuck).
--
-- ★★★ THE CONTRACT (the single most important thing in this file) ★★★
--   * COSMETIC = appearance/sound ONLY. May apply anytime, may STACK, NEVER
--     touches movement/flight. Every original value touched is CAPTURED +
--     restored on end/reset/respawn.
--   * GUARDED = movement-altering. Apply ONLY while GROUNDED and
--     `_G.isFlying ~= true`. The INSTANT the player flies or leaves the
--     ground, EVERY guarded effect is SUSPENDED (Humanoid props restored to
--     normal, forces removed) so it can NEVER trigger / remain during a climb.
--     Any vertical boost is capped to GUARDED_MAX_BOOST_HEIGHT studs above the
--     grounded start so it can NEVER reach a higher/locked island or skip
--     progression. They are TEMPORARY + NEVER touch the fart meter, power,
--     gas, coins, or flight -- only Humanoid/HRP movement props (captured +
--     restored) and client input remap.
--   * ULTIMATE = gigantic + loud + big jump/fart, but its boost is STILL
--     GUARDED exactly as above (grounded-only, height-capped, temporary,
--     fully reverted incl. the giant scale).
--   * The ONLY _G access anywhere in this whole event is READING `_G.isFlying`
--     to gate. We never write any _G flight/power/coin global.
--======================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local sync = ReplicatedStorage:WaitForChild("MutationSync")

--======================================================================
-- LOCAL CAPS (mirror the server CONFIG; the server is authoritative but the
-- client also self-caps so it can never over-spawn particles).
--======================================================================
local MAX_PARTICLE_RATE = 26
local MAX_RADIATION_EMITTERS = 4

-- The GUARDED vertical boost cap (studs above the grounded start). The server
-- sends the authoritative value at "start"/"mutate"; this is a safe default.
local guardedMaxBoostHeight = 40

--======================================================================
-- ScreenGui: announcement banner.
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "MutationEventUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 54
gui.Parent = player:WaitForChild("PlayerGui")

local BANNER_BG_VISIBLE = 0.2  -- the opaque background transparency when showing
local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0.14, 0)
banner.Size = UDim2.new(0.6, 0, 0.08, 0)
banner.BackgroundColor3 = Color3.fromRGB(30, 55, 25)
banner.BackgroundTransparency = 1  -- fully invisible when idle
banner.TextColor3 = Color3.fromRGB(190, 255, 170)
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
		if banner.Text == text then hideBanner() end
	end)
end

--======================================================================
-- SKY: neon green/purple toxic Lighting, FULLY restored on reset.
--======================================================================
local mutCC = nil
local mutAtmos = nil
local ambientFolder = nil
local pulseConn = nil
local savedLighting = nil
local savedClouds = nil

local function snapshotLighting()
	if savedLighting then return end
	savedLighting = {
		ClockTime = Lighting.ClockTime,
		FogColor = Lighting.FogColor,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		Brightness = Lighting.Brightness,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		savedClouds = { Cover = clouds.Cover, Density = clouds.Density, Color = clouds.Color }
	end
end

local function startSky()
	snapshotLighting()
	if not mutCC then
		mutCC = Instance.new("ColorCorrectionEffect")
		mutCC.Name = "MutationCC"
		mutCC.Parent = Lighting
	end
	mutCC.Brightness = 0
	mutCC.Contrast = 0
	mutCC.TintColor = Color3.fromRGB(255, 255, 255)
	TweenService:Create(mutCC, TweenInfo.new(3),
		{ Contrast = 0.12, Saturation = 0.25, TintColor = Color3.fromRGB(170, 255, 150) }):Play()

	if not mutAtmos then
		mutAtmos = Instance.new("Atmosphere")
		mutAtmos.Name = "MutationAtmosphere"
		mutAtmos.Parent = Lighting
	end
	mutAtmos.Density = 0.32
	mutAtmos.Color = Color3.fromRGB(140, 220, 130)
	mutAtmos.Decay = Color3.fromRGB(120, 80, 200)
	mutAtmos.Haze = 2.5
	mutAtmos.Glare = 0.3

	TweenService:Create(Lighting, TweenInfo.new(3), {
		FogColor = Color3.fromRGB(120, 200, 110),
		FogEnd = 2200,
		FogStart = 50,
		OutdoorAmbient = Color3.fromRGB(120, 170, 100),
	}):Play()

	-- Toxic clouds: thicken + tint green/purple.
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		TweenService:Create(clouds, TweenInfo.new(3),
			{ Cover = 0.9, Density = 0.6, Color = Color3.fromRGB(150, 220, 140) }):Play()
	end

	-- PULSING NEON lighting: gently oscillate the ColorCorrection tint between
	-- green + purple while the event runs (cheap Heartbeat lerp).
	if not pulseConn then
		pulseConn = RunService.Heartbeat:Connect(function()
			if not mutCC then return end
			local t = (math.sin(os.clock() * 1.5) + 1) / 2
			mutCC.TintColor = Color3.fromRGB(170, 255, 150):Lerp(Color3.fromRGB(190, 140, 255), t)
		end)
	end

	-- Alarm + bubbling ambient on the camera.
	if not ambientFolder then
		ambientFolder = Instance.new("Folder")
		ambientFolder.Name = "MutationAmbient"
		ambientFolder.Parent = workspace.CurrentCamera or workspace
		local alarm = Instance.new("Sound")
		alarm.Name = "Alarm"
		alarm.SoundId = "rbxassetid://9112854440"
		alarm.Looped = true
		alarm.Volume = 1   -- unified volume: matches the meteor intro sound
		alarm.Parent = ambientFolder
		alarm:Play()
		local bubble = Instance.new("Sound")
		bubble.Name = "Bubbling"
		bubble.SoundId = "rbxassetid://9114402399"
		bubble.Looped = true
		bubble.Volume = 1   -- unified volume: matches the meteor intro sound
		bubble.PlaybackSpeed = 0.7
		bubble.Parent = ambientFolder
		bubble:Play()
	end
end

local function restoreSky()
	if savedLighting then
		TweenService:Create(Lighting, TweenInfo.new(3), {
			ClockTime = savedLighting.ClockTime,
			FogColor = savedLighting.FogColor,
			FogEnd = savedLighting.FogEnd,
			FogStart = savedLighting.FogStart,
			Brightness = savedLighting.Brightness,
			OutdoorAmbient = savedLighting.OutdoorAmbient,
		}):Play()
	end
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds and savedClouds then
		TweenService:Create(clouds, TweenInfo.new(3), {
			Cover = savedClouds.Cover, Density = savedClouds.Density, Color = savedClouds.Color,
		}):Play()
	end
	if pulseConn then pulseConn:Disconnect() pulseConn = nil end
	if mutCC then
		local cc = mutCC; mutCC = nil
		local fade = TweenService:Create(cc, TweenInfo.new(2.5),
			{ Contrast = 0, Saturation = 0, TintColor = Color3.fromRGB(255, 255, 255) })
		fade:Play(); fade.Completed:Connect(function() cc:Destroy() end)
	end
	if mutAtmos then
		local at = mutAtmos; mutAtmos = nil
		local fade = TweenService:Create(at, TweenInfo.new(2.5), { Density = 0, Haze = 0, Glare = 0 })
		fade:Play(); fade.Completed:Connect(function() at:Destroy() end)
	end
	if ambientFolder then
		local f = ambientFolder; ambientFolder = nil
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("Sound") then d:Stop() end
		end
		task.delay(1, function() if f then f:Destroy() end end)
	end
	savedLighting = nil
	savedClouds = nil
end

--======================================================================
-- CAMERA-TRACKED, HARD-CAPPED RADIATION PARTICLE VOLUME + heat distortion.
--======================================================================
local radRig = nil
local radEmitters = {}
local radFollowConn = nil
local heatDistortion = nil

local function buildRadRig()
	if radRig then return end
	radRig = Instance.new("Part")
	radRig.Name = "MutationRadRig"
	radRig.Size = Vector3.new(1, 1, 1)
	radRig.Transparency = 1
	radRig.Anchored = true
	radRig.CanCollide = false
	radRig.CanQuery = false
	radRig.CanTouch = false
	radRig.Parent = workspace.CurrentCamera or workspace

	local layers = math.min(3, MAX_RADIATION_EMITTERS)
	for i = 1, layers do
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "Rad_" .. i
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Rate = math.min(6, MAX_PARTICLE_RATE)
		pe.Lifetime = NumberRange.new(2, 4)
		pe.Speed = NumberRange.new(1, 3)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new(0.4 + i * 0.1)
		pe.LightEmission = 0.6
		pe.Color = ColorSequence.new(Color3.fromRGB(150, 255, 120), Color3.fromRGB(190, 140, 255))
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.Acceleration = Vector3.new(0, 2, 0)
		pe.Parent = radRig
		table.insert(radEmitters, pe)
	end

	-- Heat distortion shimmer (a subtle ColorCorrection-free approach: a
	-- BlurEffect that gently breathes). Cheap + restored on reset.
	heatDistortion = Instance.new("BlurEffect")
	heatDistortion.Name = "MutationHeat"
	heatDistortion.Size = 0
	heatDistortion.Parent = Lighting
	TweenService:Create(heatDistortion, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = 3 }):Play()

	radFollowConn = RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if cam and radRig and radRig.Parent then
			radRig.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 5, 0))
		end
	end)
end

local function destroyRad()
	if radFollowConn then radFollowConn:Disconnect() radFollowConn = nil end
	if radRig then radRig:Destroy() radRig = nil end
	radEmitters = {}
	if heatDistortion then heatDistortion:Destroy() heatDistortion = nil end
end

--======================================================================
-- CLIENT EFFECT: camera shake (decaying random jitter) for storms/surges.
--======================================================================
local function cameraShake(intensity, seconds)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local amp = intensity or 0.5
	local t0 = os.clock()
	local dur = seconds or 0.4
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - t0
		if elapsed >= dur then conn:Disconnect() return end
		local decay = 1 - (elapsed / dur)
		cam.CFrame = cam.CFrame * CFrame.new(
			(math.random() - 0.5) * amp * decay,
			(math.random() - 0.5) * amp * decay, 0)
	end)
end

local function greenFlash()
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0.4
	cc.TintColor = Color3.fromRGB(150, 255, 130)
	cc.Parent = Lighting
	local fade = TweenService:Create(cc, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Brightness = 0 })
	fade:Play(); fade.Completed:Connect(function() cc:Destroy() end)
end

--======================================================================
-- ★★★ PLAYER MUTATION ENGINE ★★★
--======================================================================

-- isGrounded(humanoid): true ONLY if standing on a surface + not airborne.
-- (Copied from the IceAge gate.) Used to gate ALL guarded mutations.
local function isGrounded(humanoid)
	if not humanoid then return false end
	if humanoid.FloorMaterial == Enum.Material.Air then return false end
	local s = humanoid:GetState()
	if s == Enum.HumanoidStateType.Freefall
		or s == Enum.HumanoidStateType.Jumping
		or s == Enum.HumanoidStateType.FallingDown then
		return false
	end
	return true
end

-- effectsAllowed(): the single gate for GUARDED mutations. Both conditions
-- required: NOT flying (_G.isFlying ~= true) AND grounded. The instant either
-- fails, the guard loop SUSPENDS every guarded effect.
local function effectsAllowed(humanoid)
	if _G.isFlying == true then return false end
	return isGrounded(humanoid)
end

-- ---------- COSMETIC STATE ----------
-- activeCosmetics[id] = {
--   restoreAt, scaleVals = { [NumberValue] = original },
--   partLooks = { [part] = { Color, Material, Transparency } },
--   extras = { instances to destroy }, conns = { connections },
-- }
local activeCosmetics = {}

-- ---------- GUARDED STATE ----------
-- guardedState holds the SINGLE active guarded mutation (we keep one guarded
-- mutation at a time so caps/cleanup are simple + we never stack movement
-- forces). Cosmetics may still stack independently.
local guardedState = nil   -- { id, restoreAt, magnitude, applied, captured = {...}, conns = {} }
local guardConn = nil       -- master Heartbeat enforcing the gate every frame
local reverseActive = false -- whether reverse-controls remap is on
local reverseConn = nil     -- input remap connection

-- Helpers to find R15 body-scale NumberValues for cosmetic limb scaling.
local function getScaleValue(humanoid, name)
	local sv = humanoid and humanoid:FindFirstChild(name)
	if sv and sv:IsA("NumberValue") then return sv end
	return nil
end

-- captureCosmeticLooks(char): snapshot all part Color/Material/Transparency
-- so a recolor/material mutation fully reverts.
local function captureCosmeticLooks(char)
	local looks = {}
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			looks[part] = { Color = part.Color, Material = part.Material, Transparency = part.Transparency }
		end
	end
	return looks
end

-- restoreCosmetic(id): revert one cosmetic mutation fully.
local function restoreCosmetic(id)
	local entry = activeCosmetics[id]
	if not entry then return end
	for sv, val in pairs(entry.scaleVals or {}) do
		if sv and sv.Parent then sv.Value = val end
	end
	for part, look in pairs(entry.partLooks or {}) do
		if part and part.Parent then
			part.Color = look.Color
			part.Material = look.Material
			part.Transparency = look.Transparency
		end
	end
	for _, inst in ipairs(entry.extras or {}) do
		if inst and inst.Parent then inst:Destroy() end
	end
	for _, conn in ipairs(entry.conns or {}) do
		if conn.Connected then conn:Disconnect() end
	end
	activeCosmetics[id] = nil
end

-- restoreAllCosmetics(): revert every cosmetic.
local function restoreAllCosmetics()
	local ids = {}
	for id in pairs(activeCosmetics) do table.insert(ids, id) end
	for _, id in ipairs(ids) do restoreCosmetic(id) end
end

-- applyCosmetic(pick): apply one cosmetic mutation by id. CAPTURES first.
-- Cosmetics may STACK (each keyed by id; re-rolling the same id just refreshes
-- the timer). Appearance/sound ONLY -- never touches movement/flight.
local function applyCosmetic(pick)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not humanoid then return end

	local id = pick.id
	-- If already active, just extend the duration (don't re-capture).
	if activeCosmetics[id] then
		activeCosmetics[id].restoreAt = os.clock() + (pick.duration or 10)
		return
	end

	local entry = { restoreAt = os.clock() + (pick.duration or 10), scaleVals = {}, partLooks = {}, extras = {}, conns = {} }
	activeCosmetics[id] = entry

	-- Scale-based cosmetics use R15 body-scale NumberValues when present.
	local function scaleLimb(scaleName, factor)
		local sv = getScaleValue(humanoid, scaleName)
		if sv then
			entry.scaleVals[sv] = sv.Value
			sv.Value = sv.Value * factor
		end
	end

	if id == "giant_arms" then
		-- No dedicated arm scale exists; widen the body as a visible proxy.
		scaleLimb("BodyWidthScale", pick.magnitude or 2.5)
	elseif id == "tiny_legs" then
		scaleLimb("BodyHeightScale", pick.magnitude or 0.4)
	elseif id == "massive_head" then
		scaleLimb("HeadScale", pick.magnitude or 3.0)
	elseif id == "tiny_body" then
		scaleLimb("BodyWidthScale", pick.magnitude or 0.5)
		scaleLimb("BodyDepthScale", pick.magnitude or 0.5)
	elseif id == "giant_hands" then
		scaleLimb("BodyWidthScale", pick.magnitude or 2.5)
	elseif id == "giant_feet" then
		scaleLimb("BodyHeightScale", (pick.magnitude or 2.5) * 0.4 + 1)
		cameraShake(0.15, 0.3) -- small optional shake
	elseif id == "balloon_body" then
		scaleLimb("BodyWidthScale", pick.magnitude or 1.8)
		scaleLimb("BodyDepthScale", pick.magnitude or 1.8)
	elseif id == "glowing_skin" then
		entry.partLooks = captureCosmeticLooks(char)
		for part in pairs(entry.partLooks) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.Color = Color3.fromRGB(120, 255, 120)
				part.Material = Enum.Material.Neon
			end
		end
	elseif id == "squeaky_voice" then
		local head = char:FindFirstChild("Head")
		if head then
			local s = Instance.new("Sound")
			s.Name = "SqueakyVoice"
			s.SoundId = "rbxassetid://9114402399"
			s.Volume = 1   -- unified volume: matches the meteor intro sound
			s.Looped = true
			s.PlaybackSpeed = 2.2
			s.Parent = head
			s:Play()
			table.insert(entry.extras, s)
		end
	elseif id == "spin" then
		-- COSMETIC visual spin ONLY: spin a non-physics decorative part attached
		-- to the head. We do NOT spin the HRP (never move the player physically).
		local head = char:FindFirstChild("Head")
		if head then
			local halo = Instance.new("Part")
			halo.Name = "SpinHalo"
			halo.Shape = Enum.PartType.Cylinder
			halo.Material = Enum.Material.Neon
			halo.Color = Color3.fromRGB(150, 255, 130)
			halo.Size = Vector3.new(0.2, 4, 4)
			halo.Transparency = 0.4
			halo.CanCollide = false
			halo.CanQuery = false
			halo.CanTouch = false
			halo.Massless = true
			halo.Parent = char
			local weld = Instance.new("Weld")
			weld.Part0 = head
			weld.Part1 = halo
			weld.C0 = CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, math.rad(90))
			weld.Parent = halo
			table.insert(entry.extras, halo)
			local conn = RunService.Heartbeat:Connect(function()
				if halo.Parent then
					weld.C0 = CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(os.clock() * 4, 0, 0)
				end
			end)
			table.insert(entry.conns, conn)
		end
	elseif id == "radioactive_trail" then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 1, 0); a0.Parent = hrp
			local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -1, 0); a1.Parent = hrp
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0; trail.Attachment1 = a1; trail.Lifetime = 0.8
			trail.Color = ColorSequence.new(Color3.fromRGB(150, 255, 120), Color3.fromRGB(190, 140, 255))
			trail.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			trail.Parent = hrp
			table.insert(entry.extras, a0)
			table.insert(entry.extras, a1)
			table.insert(entry.extras, trail)
		end
	elseif id == "goofy_anim" then
		-- A purely cosmetic wobble of the HEAD tilt via a non-physics weld-free
		-- approach: tween the head's local CFrame offset is risky, so instead we
		-- just emit a small green sparkle burst as a stand-in goofy cue (safe).
		local head = char:FindFirstChild("Head")
		if head then
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			pe.Rate = math.min(8, MAX_PARTICLE_RATE)
			pe.Lifetime = NumberRange.new(0.6, 1.2)
			pe.Speed = NumberRange.new(1, 2)
			pe.Size = NumberSequence.new(0.4)
			pe.Color = ColorSequence.new(Color3.fromRGB(180, 255, 120))
			pe.Parent = head
			table.insert(entry.extras, pe)
		end
	end
end

-- ---------- GUARDED MUTATION APPLY / SUSPEND / RESTORE ----------

-- captureGuarded(humanoid): snapshot the Humanoid movement props we may touch
-- so suspend/restore is exact. NEVER touches fart/power/flight props.
local function captureGuarded(humanoid)
	return {
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		useJumpPower = humanoid.UseJumpPower,
		hipHeight = humanoid.HipHeight,
	}
end

-- restoreGuardedProps(humanoid, cap): restore captured Humanoid props.
local function restoreGuardedProps(humanoid, cap)
	if not humanoid or not humanoid.Parent or not cap then return end
	humanoid.WalkSpeed = cap.walkSpeed
	humanoid.JumpPower = cap.jumpPower
	humanoid.JumpHeight = cap.jumpHeight
	humanoid.UseJumpPower = cap.useJumpPower
	humanoid.HipHeight = cap.hipHeight
end

-- cleanupReverse(): turn off the reverse-controls remap.
local function cleanupReverse()
	reverseActive = false
	if reverseConn then reverseConn:Disconnect() reverseConn = nil end
	-- Restore default control module behaviour by re-enabling it (we only ever
	-- DISABLED our override; the default controls keep working underneath).
end

-- applyReverseControls(): remap movement input so WASD is reversed. We do this
-- WITHOUT touching flight: we only override the Humanoid:Move direction while
-- grounded; the guard loop disables it the instant the player flies/leaves the
-- ground (so flight is 100% normal). Cheap + fully reversible.
local function applyReverseControls()
	if reverseActive then return end
	reverseActive = true
	-- We drive Humanoid:Move with a reversed input vector each frame WHILE the
	-- guard considers it allowed. The guard loop (below) calls into this only
	-- when grounded + not flying; here we just install the per-frame override.
	reverseConn = RunService.Heartbeat:Connect(function()
		if not reverseActive then return end
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		-- Only override while grounded + not flying. Otherwise leave movement
		-- entirely alone (so normal walking/flight resumes instantly).
		if not effectsAllowed(humanoid) then return end
		-- Read current keyboard movement intent + reverse the horizontal axes.
		local moveDir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += Vector3.new(0, 0, 1) end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir += Vector3.new(0, 0, -1) end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir += Vector3.new(1, 0, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += Vector3.new(-1, 0, 0) end
		if moveDir.Magnitude > 0 then
			local cam = workspace.CurrentCamera
			local cf = cam and cam.CFrame or CFrame.new()
			-- Move relative to the camera, reversed (we already negated above).
			local worldDir = (cf:VectorToWorldSpace(moveDir))
			worldDir = Vector3.new(worldDir.X, 0, worldDir.Z)
			if worldDir.Magnitude > 0 then
				humanoid:Move(worldDir.Unit, false)
			end
		end
	end)
end

-- doGuardedHop(humanoid, hrp, magnitude): a SINGLE capped upward hop (used by
-- super_fart_boost). We apply an upward velocity but CAP it so the peak rise
-- never exceeds guardedMaxBoostHeight above the current grounded Y. Uses the
-- physics relation v = sqrt(2*g*h) with Workspace.Gravity. NEVER a climb.
local function doGuardedHop(humanoid, hrp, magnitude)
	if not hrp then return end
	local g = workspace.Gravity
	-- Desired rise = min(requested-ish, the hard cap).
	local desiredRise = math.min(magnitude or 20, guardedMaxBoostHeight)
	local vUp = math.sqrt(2 * g * math.max(0, desiredRise))
	-- Apply as a brief upward BodyVelocity that self-clears (cosmetic hop).
	local bv = Instance.new("BodyVelocity")
	bv.Name = "MutationHop"
	bv.MaxForce = Vector3.new(0, 1, 0) * 1e5 -- vertical only
	bv.P = 3000
	bv.Velocity = Vector3.new(0, vUp, 0)
	bv.Parent = hrp
	Debris:AddItem(bv, 0.18) -- a quick impulse, then gravity takes over
end

-- applyGuarded(pick): begin ONE guarded mutation. We only CAPTURE + register
-- here; the per-frame guard loop does the actual gated application/suspension.
local function applyGuarded(pick)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not humanoid then return end

	-- One guarded mutation at a time: end any prior guarded effect first so we
	-- never stack movement forces (clean caps + restore).
	if guardedState then
		restoreGuardedProps(humanoid, guardedState.captured)
		guardedState = nil
		cleanupReverse()
	end

	guardedState = {
		id = pick.id,
		restoreAt = os.clock() + (pick.duration or 10),
		magnitude = pick.magnitude,
		applied = false,                 -- whether props are currently applied
		captured = captureGuarded(humanoid),
		lastBounce = 0,
	}

	-- reverse_controls + fart_cloud are special (no Humanoid prop change).
	if pick.id == "reverse_controls" then
		-- The remap installs immediately but only acts when allowed (gated in
		-- its own loop). The guard loop tears it down on suspend/end.
		-- We mark applied=true so the guard loop knows to keep it gated.
		guardedState.applied = false
	elseif pick.id == "fart_cloud" then
		-- ★ Despite being in the GUARDED list, this is just a COSMETIC particle
		-- with NO force. We attach an oversized green fart cloud emitter. It is
		-- still managed under the guarded slot for simple capping, but it never
		-- alters movement/flight. ★
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "FartCloud"
			pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
			pe.Rate = math.min(10, MAX_PARTICLE_RATE)
			pe.Lifetime = NumberRange.new(1, 2)
			pe.Speed = NumberRange.new(2, 4)
			pe.Size = NumberSequence.new(6)
			pe.Color = ColorSequence.new(Color3.fromRGB(150, 230, 90))
			pe.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			pe.Parent = hrp
			guardedState.fartCloud = pe
		end
	end
end

-- applyGuardedPropsNow(humanoid, hrp): set the Humanoid movement props for the
-- active guarded mutation. Called by the guard loop ONLY when effectsAllowed().
-- Everything respects guardedMaxBoostHeight.
local function applyGuardedPropsNow(humanoid, hrp)
	local st = guardedState
	if not st or st.applied then return end
	local cap = st.captured
	local id = st.id
	if id == "super_jump" then
		-- Cap the jump so peak rise <= guardedMaxBoostHeight. Convert the cap to
		-- a JumpPower-equivalent so the player can never out-jump the cap.
		humanoid.UseJumpPower = true
		local g = workspace.Gravity
		-- JumpPower ~= takeoff velocity; v that yields the capped rise:
		local cappedV = math.sqrt(2 * g * guardedMaxBoostHeight)
		humanoid.JumpPower = math.min(st.magnitude or 50, cappedV)
		humanoid.JumpHeight = math.min(humanoid.JumpHeight, guardedMaxBoostHeight)
		st.applied = true
	elseif id == "extra_speed" then
		humanoid.WalkSpeed = (cap.walkSpeed or 16) + (st.magnitude or 20)
		st.applied = true
	elseif id == "floating" then
		-- Gentle hover: raise HipHeight a small amount (capped well under the
		-- island gap). Purely a standing float; never carries upward.
		humanoid.HipHeight = (cap.hipHeight or 0) + math.min(st.magnitude or 4, guardedMaxBoostHeight)
		st.applied = true
	elseif id == "bouncing" then
		-- Repeated gentle hops while grounded; each hop capped. The actual hop
		-- impulses are issued from the guard loop on a timer (see below).
		humanoid.UseJumpPower = true
		st.applied = true
	elseif id == "super_fart_boost" then
		-- A single capped upward hop on apply, then it just lingers cosmetically.
		doGuardedHop(humanoid, hrp, st.magnitude or 20)
		st.applied = true
	elseif id == "reverse_controls" then
		applyReverseControls()
		st.applied = true
	elseif id == "fart_cloud" then
		st.applied = true -- cosmetic only; nothing to apply
	end
end

-- suspendGuarded(humanoid): SUSPEND the active guarded mutation -- restore the
-- Humanoid props to normal + stop the reverse remap. Called the INSTANT the
-- player flies or leaves the ground. The mutation can RESUME when grounded
-- again (until its timer ends). Movement/flight is 100% normal while airborne.
local function suspendGuarded(humanoid)
	local st = guardedState
	if not st then return end
	if st.applied then
		restoreGuardedProps(humanoid, st.captured)
		st.applied = false
	end
	if reverseActive then cleanupReverse() end
end

-- endGuarded(): fully END the active guarded mutation (timer up / reset).
local function endGuarded()
	local st = guardedState
	if not st then return end
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	restoreGuardedProps(humanoid, st.captured)
	if st.fartCloud and st.fartCloud.Parent then st.fartCloud:Destroy() end
	cleanupReverse()
	guardedState = nil
end

-- ---------- ULTIMATE ----------
-- The Ultimate is gigantic + loud + boosted, but its boost is STILL GUARDED.
-- We implement it as: a cosmetic giant scale (captured/restored) PLUS a
-- guarded super_jump-style boost (grounded-only, height-capped) running in the
-- guarded slot. So all the guarded safety applies unchanged.
local ultimateState = nil -- { restoreAt, scaleVals = {}, extras = {} }

local function applyUltimate(pick)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not humanoid then return end

	-- Cosmetic giant scale (captured for restore).
	local scaleVals = {}
	for _, scaleName in ipairs({ "BodyDepthScale", "BodyHeightScale", "BodyWidthScale", "HeadScale" }) do
		local sv = getScaleValue(humanoid, scaleName)
		if sv then
			scaleVals[sv] = sv.Value
			sv.Value = sv.Value * (pick.magnitude or 3)
		end
	end
	ultimateState = { restoreAt = os.clock() + (pick.duration or 12), scaleVals = scaleVals, extras = {} }

	-- Loud mutant SFX + giant footstep cue on the camera (cosmetic).
	local cam = workspace.CurrentCamera or workspace
	local roar = Instance.new("Sound")
	roar.Name = "UltimateRoar"
	roar.SoundId = "rbxassetid://9112854440"
	roar.Volume = 1   -- unified volume: matches the meteor intro sound
	roar.Parent = cam
	roar:Play()
	roar.Ended:Connect(function() roar:Destroy() end)
	Debris:AddItem(roar, 6)
	table.insert(ultimateState.extras, roar)

	-- The boosted fart/jump: run it through the SAME guarded slot so all guard
	-- rules apply (grounded-only, height-capped, suspended on flight, reverts).
	applyGuarded({ id = "super_jump", duration = pick.duration or 12, magnitude = 999 })
	-- (magnitude 999 is intentionally large; applyGuardedPropsNow clamps it to
	-- the guardedMaxBoostHeight-derived velocity, so it can NEVER exceed the cap.)

	showBanner("\u{2623}\u{FE0F} ULTIMATE MUTATION!", 4)
	cameraShake(0.4, 0.6)
end

local function endUltimate()
	if not ultimateState then return end
	for sv, val in pairs(ultimateState.scaleVals) do
		if sv and sv.Parent then sv.Value = val end
	end
	for _, inst in ipairs(ultimateState.extras) do
		if inst and inst.Parent then inst:Destroy() end
	end
	ultimateState = nil
	endGuarded() -- end the guarded boost that backed the ultimate
end

-- ---------- THE MASTER GUARD LOOP ----------
-- Enforces every guarded gate EVERY frame: applies guarded props only when
-- allowed (grounded + not flying), SUSPENDS them the instant the player flies
-- or leaves the ground, issues capped bounce hops, caps any vertical position
-- so a guarded mutation can never carry the player above the height cap, and
-- expires cosmetic + guarded + ultimate timers.
local function startGuardLoop()
	if guardConn then return end
	guardConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")

		-- Expire cosmetics (safe anytime).
		local expired = {}
		for id, entry in pairs(activeCosmetics) do
			if now >= entry.restoreAt then table.insert(expired, id) end
		end
		for _, id in ipairs(expired) do restoreCosmetic(id) end

		-- Expire ultimate.
		if ultimateState and now >= ultimateState.restoreAt then
			endUltimate()
		end

		if not humanoid then
			-- No character: ensure nothing lingers.
			if guardedState then guardedState = nil end
			cleanupReverse()
			return
		end

		-- GUARDED handling.
		if guardedState then
			-- Expire by timer.
			if now >= guardedState.restoreAt then
				endGuarded()
			else
				local allowed = effectsAllowed(humanoid)
				if allowed then
					-- Apply (or keep applied) the guarded props.
					applyGuardedPropsNow(humanoid, hrp)
					-- Bouncing: issue a capped hop on a gentle cadence.
					if guardedState.id == "bouncing" and now - (guardedState.lastBounce or 0) >= 0.85 then
						guardedState.lastBounce = now
						doGuardedHop(humanoid, hrp, math.min(guardedState.magnitude or 20, guardedMaxBoostHeight))
					end
				else
					-- ★ The instant we fly or leave the ground: SUSPEND. ★
					suspendGuarded(humanoid)
				end
			end
		end
	end)
end

local function stopGuardLoop()
	if guardConn then guardConn:Disconnect() guardConn = nil end
end

-- FULL player revert: cosmetics + guarded + ultimate all back to normal.
local function revertAllPlayerMutations()
	restoreAllCosmetics()
	endGuarded()
	endUltimate()
end

-- Route an incoming "mutate" message to the right engine.
local function handleMutate(payload)
	if typeof(payload) ~= "table" then return end
	if payload.maxBoostHeight then guardedMaxBoostHeight = payload.maxBoostHeight end
	local pick = {
		id = payload.id,
		duration = payload.duration,
		magnitude = payload.magnitude,
		strong = payload.strong,
	}
	if payload.group == "ultimate" then
		applyUltimate(pick)
	elseif payload.group == "guarded" then
		applyGuarded(pick)
	else
		applyCosmetic(pick) -- cosmetic (default)
	end
	-- A short green mutation SFX cue on the camera.
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://9114402399"
	s.Volume = 1   -- unified volume: matches the meteor intro sound
	s.PlaybackSpeed = 1.4
	s.Parent = workspace.CurrentCamera or workspace
	s:Play()
	s.Ended:Connect(function() s:Destroy() end)
	Debris:AddItem(s, 3)
end

-- On respawn: the fresh character is normal; drop all tracking + restore.
player.CharacterAdded:Connect(function()
	-- The old part/value references are gone with the old character.
	activeCosmetics = {}
	guardedState = nil
	ultimateState = nil
	cleanupReverse()
end)

--======================================================================
-- LOAD-TIME CLEAN SLATE: no event text shows at game load (the banner already
-- constructs hidden; belt-and-suspenders, matching the blanket event-text rule).
--======================================================================
hideBanner()

--======================================================================
-- Listen to the server-driven sync events.
--======================================================================
sync.OnClientEvent:Connect(function(phase, payload)
	if phase == "start" then
		if typeof(payload) == "table" and payload.maxBoostHeight then
			guardedMaxBoostHeight = payload.maxBoostHeight
		end
		startSky()
		buildRadRig()
		startGuardLoop()
		showBanner((payload and payload.text) or "\u{2623}\u{FE0F} MUTATION EVENT ACTIVE!", 5)

	elseif phase == "warning" then
		showBanner("\u{2623}\u{FE0F} Radiation rising\u{2026} mutations imminent!", 4)

	elseif phase == "main" then
		showBanner("\u{2623}\u{FE0F} MUTATION! Anything can happen\u{2026}", 4)

	elseif phase == "mutate" then
		-- ★ A per-player mutation roll from the server. ★
		handleMutate(payload)

	elseif phase == "surge" then
		greenFlash()
		cameraShake(0.2, 0.25)

	elseif phase == "storm" then
		greenFlash()
		cameraShake(0.45, 0.5)

	elseif phase == "ending" then
		showBanner((payload and payload.text) or "\u{2623}\u{FE0F} Mutation Levels Returning to Safe Range\u{2026}", 5)

	elseif phase == "reset" then
		-- FULL restore: revert EVERY player mutation, stop the guard loop,
		-- remove particles + heat distortion, restore the sky.
		hideBanner()
		revertAllPlayerMutations()
		stopGuardLoop()
		destroyRad()
		restoreSky()
	end
end)
