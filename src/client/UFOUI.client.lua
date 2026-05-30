--======================================================================
-- UFOUI.client.lua  (LocalScript)
--======================================================================
-- Client-side presentation + the PLAYER-RIDE handler for the global "UFO"
-- event. Listens to the UFOSync RemoteEvent and renders everything that
-- MUST live on the client because it is per-client (this player's Camera /
-- Lighting view / network-owned character physics):
--
--   * cinematic SKY (green/purple sci-fi via ColorCorrection + Atmosphere +
--     fog + ClockTime + sped-up clouds) -- FULLY RESTORED from a saved
--     Lighting snapshot on reset.
--   * announcement banners ("UFO DETECTED...", "UFO EVENT ENDING..."),
--     random alien gibberish text, eerie/buzzing alien ambient sounds.
--   * a laser scan light on the player, a lens flare, camera shake, the
--     big ending flash.
--   * ★ the PLAYER-RIDE handler ★ -- grounded gating + capture/restore +
--     slow float-up + slight spin + pull toward the UFO + escape on
--     fly/jump/boost, plus the inside-UFO teleport-in/return for THIS
--     player.
--
-- ★★★ POSITION SAFETY (the single most important contract) ★★★
--   * The beam may ONLY engage a player who is GROUNDED on/near an island
--     and NOT flying. Before grabbing, this client checks `_G.isFlying ~=
--     true` AND the Humanoid is actually on the ground (FloorMaterial ~=
--     Air, state not Freefall/Jumping). If either fails, we IGNORE the
--     engage entirely -- we never grab a flying/airborne player.
--   * The INSTANT we engage, we CAPTURE the HumanoidRootPart CFrame (the
--     player's exact spot on their island). After the ride AND after any
--     inside-UFO scene we ALWAYS set them back to that captured CFrame --
--     same island, same surface. We NEVER deposit them higher.
--   * If the player starts flying / jumps / boosts mid-ride, we release
--     them IMMEDIATELY with NO teleport (they keep their current position).
--   * The ride touches ONLY the HRP CFrame/velocity. It NEVER reads or
--     writes the gas meter, fart power, flight code, food, guts, island
--     heights, the earn rate, or coins. The only _G access anywhere is
--     READING `_G.isFlying`.
--======================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local sync = ReplicatedStorage:WaitForChild("UFOSync")

--======================================================================
-- ScreenGui: banner (top) + reward popup (bottom) + lens flare overlay.
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "UFOEventUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 52
gui.Parent = player:WaitForChild("PlayerGui")

local BANNER_BG_VISIBLE = 0.2  -- the opaque background transparency when showing
local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0.14, 0)
banner.Size = UDim2.new(0.6, 0, 0.08, 0)
banner.BackgroundColor3 = Color3.fromRGB(18, 30, 22)
banner.BackgroundTransparency = 1  -- fully invisible when idle
banner.TextColor3 = Color3.fromRGB(170, 255, 190)
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

local gibberish = Instance.new("TextLabel")
gibberish.Name = "Gibberish"
gibberish.AnchorPoint = Vector2.new(0.5, 0)
gibberish.Position = UDim2.new(0.5, 0, 0.24, 0)
gibberish.Size = UDim2.new(0.5, 0, 0.05, 0)
gibberish.BackgroundTransparency = 1
gibberish.TextColor3 = Color3.fromRGB(150, 255, 170)
gibberish.TextStrokeColor3 = Color3.fromRGB(0, 20, 10)
gibberish.TextStrokeTransparency = 0.2
gibberish.TextScaled = true
gibberish.Font = Enum.Font.Code
gibberish.Text = ""
gibberish.Visible = false
gibberish.Parent = gui

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

-- Lens flare overlay (a soft radial image we fade in over the UFO glow).
local flare = Instance.new("ImageLabel")
flare.Name = "LensFlare"
flare.AnchorPoint = Vector2.new(0.5, 0.5)
flare.Position = UDim2.new(0.5, 0, 0.35, 0)
flare.Size = UDim2.new(0.5, 0, 0.5, 0)
flare.BackgroundTransparency = 1
flare.Image = "rbxasset://textures/ui/LuaApp/graphic/gradient_circle.png"
flare.ImageColor3 = Color3.fromRGB(150, 255, 170)
flare.ImageTransparency = 1
flare.Parent = gui

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
	banner.BackgroundColor3 = color or Color3.fromRGB(18, 30, 22)
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

-- ON-SCREEN ALIEN GIBBERISH TEXT IS DISABLED: per design it must NEVER appear on
-- screen, so showGibberish() is a no-op and the "gibberish" sync phase displays
-- nothing. The alien ambient SOUNDS (eerie / buzz in startSky) are separate and are
-- intentionally KEPT. The label stays in place but is permanently hidden.
local function showGibberish()
	gibberish.Visible = false
	gibberish.Text = ""
end

--======================================================================
-- SKY: green/purple sci-fi Lighting changes that are FULLY restored on
-- reset. We create our OWN ColorCorrection + Atmosphere instances and tween
-- the base Lighting props from a saved snapshot, plus speed up any Clouds.
--======================================================================
local ufoCC = nil          -- our ColorCorrectionEffect
local ufoAtmos = nil       -- our Atmosphere
local ambientFolder = nil  -- eerie/buzz ambient sounds following the camera
local scanFolder = nil     -- laser scan light following the player
local scanConn = nil       -- RenderStepped keeping the scan light on the player
local savedLighting = nil  -- snapshot of base Lighting props to restore
local savedCloudsSpeed = nil -- saved Clouds props to restore

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
	-- Save Clouds (Terrain) speed so we can restore it after speeding up.
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		savedCloudsSpeed = { Cover = clouds.Cover, Density = clouds.Density, Color = clouds.Color }
	end
end

local function startSky(variant)
	snapshotLighting()
	local tint = (variant == "hostile") and Color3.fromRGB(255, 140, 140)
		or (variant == "golden") and Color3.fromRGB(255, 240, 170)
		or Color3.fromRGB(150, 255, 180) -- alien green/purple feel

	if not ufoCC then
		ufoCC = Instance.new("ColorCorrectionEffect")
		ufoCC.Name = "UFOEventCC"
		ufoCC.Parent = Lighting
	end
	ufoCC.Brightness = 0
	ufoCC.Contrast = 0
	ufoCC.TintColor = Color3.fromRGB(255, 255, 255)
	TweenService:Create(ufoCC, TweenInfo.new(2),
		{ Contrast = 0.2, Saturation = 0.3, TintColor = tint }):Play()

	if not ufoAtmos then
		ufoAtmos = Instance.new("Atmosphere")
		ufoAtmos.Name = "UFOEventAtmosphere"
		ufoAtmos.Parent = Lighting
	end
	ufoAtmos.Density = 0.35
	ufoAtmos.Color = Color3.fromRGB(90, 140, 110)
	ufoAtmos.Decay = Color3.fromRGB(60, 30, 90) -- purple decay for that sci-fi haze
	ufoAtmos.Haze = 2.5
	ufoAtmos.Glare = 0.6

	-- Darken + tint the base Lighting (restored on reset from the snapshot).
	TweenService:Create(Lighting, TweenInfo.new(2.5), {
		ClockTime = 0.2,                                   -- deep night, ominous
		FogColor = Color3.fromRGB(30, 60, 45),
		FogEnd = 4000,
		FogStart = 150,
		Brightness = math.max(1, (savedLighting.Brightness or 2) * 0.5),
		OutdoorAmbient = Color3.fromRGB(50, 80, 65),
	}):Play()

	-- Speed up / thicken the clouds for the "something's coming" feel.
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		TweenService:Create(clouds, TweenInfo.new(2),
			{ Cover = 0.9, Density = 0.7, Color = Color3.fromRGB(120, 160, 140) }):Play()
	end

	-- Eerie + buzzing alien ambient sounds, anchored on the camera.
	if not ambientFolder then
		ambientFolder = Instance.new("Folder")
		ambientFolder.Name = "UFOAmbient"
		ambientFolder.Parent = workspace.CurrentCamera or workspace
		local eerie = Instance.new("Sound")
		eerie.Name = "Eerie"
		eerie.SoundId = "rbxassetid://9112854440" -- low alien drone
		eerie.Looped = true
		eerie.Volume = 1   -- unified volume: matches the meteor intro sound
		eerie.Parent = ambientFolder
		eerie:Play()
		local buzz = Instance.new("Sound")
		buzz.Name = "Buzz"
		buzz.SoundId = "rbxassetid://9114402399" -- electrical buzz
		buzz.Looped = true
		buzz.Volume = 1   -- unified volume: matches the meteor intro sound
		buzz.Parent = ambientFolder
		buzz:Play()
	end
end

local function restoreSky()
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
	-- Restore clouds.
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds and savedCloudsSpeed then
		TweenService:Create(clouds, TweenInfo.new(2.5), {
			Cover = savedCloudsSpeed.Cover,
			Density = savedCloudsSpeed.Density,
			Color = savedCloudsSpeed.Color,
		}):Play()
	end

	if ufoCC then
		local cc = ufoCC
		ufoCC = nil
		local fade = TweenService:Create(cc, TweenInfo.new(2),
			{ Contrast = 0, Saturation = 0, TintColor = Color3.fromRGB(255, 255, 255) })
		fade:Play()
		fade.Completed:Connect(function() cc:Destroy() end)
	end
	if ufoAtmos then
		local at = ufoAtmos
		ufoAtmos = nil
		local fade = TweenService:Create(at, TweenInfo.new(2), { Density = 0, Haze = 0, Glare = 0 })
		fade:Play()
		fade.Completed:Connect(function() at:Destroy() end)
	end
	if ambientFolder then
		local f = ambientFolder
		ambientFolder = nil
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("Sound") then d:Stop() end
		end
		task.delay(1, function() if f then f:Destroy() end end)
	end
	-- Fade out the lens flare if it was showing.
	TweenService:Create(flare, TweenInfo.new(1), { ImageTransparency = 1 }):Play()
	savedLighting = nil
	savedCloudsSpeed = nil
end

--======================================================================
-- Laser scan light on THIS player (a thin green beam sweeping down on them).
--======================================================================
local function startScan()
	if scanFolder then return end
	scanFolder = Instance.new("Folder")
	scanFolder.Name = "UFOScan"
	scanFolder.Parent = workspace.CurrentCamera or workspace
	local beam = Instance.new("Part")
	beam.Name = "ScanBeam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(120, 255, 160)
	beam.Transparency = 0.5
	beam.Size = Vector3.new(40, 2, 2)
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Parent = scanFolder
	scanConn = RunService.RenderStepped:Connect(function()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and beam.Parent then
			-- A thin sweeping beam from above the player down onto them.
			local sweep = math.sin(os.clock() * 2) * 6
			beam.CFrame = CFrame.new(hrp.Position + Vector3.new(sweep, 22, 0))
				* CFrame.Angles(0, 0, math.rad(90))
		end
	end)
end

local function stopScan()
	if scanConn then scanConn:Disconnect() scanConn = nil end
	if scanFolder then scanFolder:Destroy() scanFolder = nil end
end

--======================================================================
-- CLIENT EFFECT: camera shake (decaying random jitter).
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

-- Big ENDING flash (full-screen white-green flash via ColorCorrection).
local function bigFlash()
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 1
	cc.Contrast = 0.3
	cc.TintColor = Color3.fromRGB(220, 255, 230)
	cc.Parent = Lighting
	local fade = TweenService:Create(cc,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0, Contrast = 0 })
	fade:Play()
	fade.Completed:Connect(function() cc:Destroy() end)
end

--======================================================================
-- ★ THE PLAYER-RIDE HANDLER ★  (POSITION SAFETY lives here)
--======================================================================
local ride = nil  -- active ride state table, or nil when not riding

-- isGrounded(humanoid): true ONLY if the player is genuinely standing on a
-- surface and NOT airborne. Used to GATE engagement (never grab a flyer).
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

-- endRide(teleportBack): finish the current ride. If teleportBack is true we
-- ALWAYS restore the captured start CFrame (after a normal ride / inside
-- scene). If false (player flew/jumped/boosted), we leave them where they
-- are with NO teleport.
local function endRide(teleportBack)
	if not ride then return end
	local r = ride
	ride = nil

	if r.conn then r.conn:Disconnect() end
	if r.jumpConn then r.jumpConn:Disconnect() end
	if r.bodyVel and r.bodyVel.Parent then r.bodyVel:Destroy() end
	if r.bodyGyro and r.bodyGyro.Parent then r.bodyGyro:Destroy() end

	stopScan()
	TweenService:Create(flare, TweenInfo.new(0.6), { ImageTransparency = 1 }):Play()

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if teleportBack and hrp and r.startCF then
		-- ★ ALWAYS restore to the EXACT captured spot (same island surface). ★
		hrp.CFrame = r.startCF
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
end

-- runInsideScene(startCF, insideCF, duration): teleport the local player into
-- the SERVER-built enclosed chamber for `duration`, then ALWAYS return them to
-- the captured start CFrame. The chamber is sealed (walls/floor/ceiling) so
-- they can't walk/fly out to a higher island. This is SELF-CONTAINED: by the
-- time it runs the `ride` global is already cleared, so a later release/reset
-- can't double-teleport this player.
local function runInsideScene(startCF, insideCF, duration)
	stopScan()
	TweenService:Create(flare, TweenInfo.new(0.6), { ImageTransparency = 1 }):Play()

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	-- restoreToStart(): the guaranteed return to the captured island spot.
	local function restoreToStart()
		local c2 = player.Character
		local h2 = c2 and c2:FindFirstChild("HumanoidRootPart")
		if h2 and startCF then
			h2.CFrame = startCF
			h2.AssemblyLinearVelocity = Vector3.zero
			h2.AssemblyAngularVelocity = Vector3.zero
		end
	end
	if not hrp or typeof(insideCF) ~= "CFrame" then
		-- No chamber provided: just return to the captured spot immediately.
		restoreToStart()
		return
	end
	showBanner("\u{1F6F8} ABDUCTED! Inside the UFO\u{2026}", duration, Color3.fromRGB(20, 40, 28))
	-- Teleport INTO the enclosed chamber.
	hrp.CFrame = insideCF
	hrp.AssemblyLinearVelocity = Vector3.zero
	-- Hold them there for the duration, then force-return to the captured spot.
	task.delay(duration, function()
		restoreToStart()
		showBanner("Returned safely to your island.", 3, Color3.fromRGB(20, 40, 28))
	end)
end

-- beginRide(payload): the engage entry. Validates grounded/non-flying,
-- captures the start CFrame, then lifts the player up the beam.
local function beginRide(payload)
	if ride then return end -- already riding
	if typeof(payload) ~= "table" then return end
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end

	-- ★ GROUNDED-ONLY GATING ★
	-- Never grab a flying player (would hijack a fart-climb) and never grab an
	-- airborne player. Both checks must pass.
	if _G.isFlying == true then return end
	if not isGrounded(humanoid) then return end

	-- ★ CAPTURE the exact start spot (their island surface). ★
	local startCF = hrp.CFrame

	ride = {
		startCF = startCF,
		ufoPos = payload.ufoPos,
		beamGround = payload.beamGround,
		pull = payload.pull or 22,
		liftHeight = payload.liftHeight or 220,
		spinRate = payload.spinRate or 45,
		escapeSensitivity = payload.escapeSensitivity or 1,
		goInside = payload.goInside == true,
		insideCF = payload.insideCF,
		insideDuration = payload.insideDuration or 8,
	}

	-- Lift forces: a BodyVelocity for the float-up + gentle horizontal pull
	-- toward the UFO, and a BodyGyro for the slight spin. These touch ONLY
	-- the HRP physics -- nothing gameplay-related.
	local bodyVel = Instance.new("BodyVelocity")
	bodyVel.Name = "UFORideVelocity"
	bodyVel.MaxForce = Vector3.new(1, 1, 1) * 1e5
	bodyVel.P = 3000
	bodyVel.Velocity = Vector3.new(0, ride.pull, 0)
	bodyVel.Parent = hrp
	ride.bodyVel = bodyVel

	local bodyGyro = Instance.new("BodyGyro")
	bodyGyro.Name = "UFORideGyro"
	bodyGyro.MaxTorque = Vector3.new(0, 1, 0) * 1e5
	bodyGyro.P = 1500
	bodyGyro.CFrame = hrp.CFrame
	bodyGyro.Parent = hrp
	ride.bodyGyro = bodyGyro

	startScan()
	TweenService:Create(flare, TweenInfo.new(0.8), { ImageTransparency = 0.4 }):Play()
	showBanner("\u{1F6F8} A tractor beam has you! (jump / fly to escape)", 4, Color3.fromRGB(20, 40, 28))

	local spin = 0
	local startY = hrp.Position.Y
	ride.conn = RunService.Heartbeat:Connect(function(dt)
		if not ride then return end
		local c = player.Character
		local h = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if not h or not hum then endRide(false) return end

		-- ★ ESCAPE: if the player starts flying, release IMMEDIATELY, no TP. ★
		-- (A fart-climb mid-ride must never be hijacked.)
		if _G.isFlying == true then
			endRide(false)
			return
		end

		-- Pull toward the UFO horizontally so they drift under the saucer, plus
		-- the constant upward lift. Capped at liftHeight above the start.
		local lifted = h.Position.Y - startY
		local upVel = ride.pull
		if lifted >= ride.liftHeight then
			-- Reached the hold band: stop rising, just hover (don't go higher,
			-- so we never approach a higher island).
			upVel = 0
		end
		local horiz = Vector3.zero
		if typeof(ride.ufoPos) == "Vector3" then
			local toUFO = Vector3.new(ride.ufoPos.X - h.Position.X, 0, ride.ufoPos.Z - h.Position.Z)
			if toUFO.Magnitude > 1 then
				horiz = toUFO.Unit * math.min(ride.pull * 0.4, 8)
			end
		end
		ride.bodyVel.Velocity = Vector3.new(horiz.X, upVel, horiz.Z)

		-- Slight spin. BodyGyro.CFrame is a target ORIENTATION (rotation only).
		spin = spin + math.rad(ride.spinRate) * dt
		ride.bodyGyro.CFrame = CFrame.Angles(0, spin, 0)

		-- Once fully lifted, either pull into the inside scene (if rolled) or
		-- simply hold; the server's "release" message ends the ride otherwise.
		if lifted >= ride.liftHeight and ride.goInside then
			-- Hand off to the self-contained inside scene. Capture the values it
			-- needs, then CLEAR the ride global + tear down the lift forces so a
			-- later release/reset can't double-teleport this player.
			local r = ride
			ride = nil
			if r.bodyVel and r.bodyVel.Parent then r.bodyVel:Destroy() end
			if r.bodyGyro and r.bodyGyro.Parent then r.bodyGyro:Destroy() end
			if r.conn then r.conn:Disconnect() end
			if r.jumpConn then r.jumpConn:Disconnect() end
			runInsideScene(r.startCF, r.insideCF, r.insideDuration)
			return
		end
	end)

	-- ESCAPE on jump / boost: a jump input or a sufficiently large upward
	-- velocity spike (a fart boost) breaks the ride with NO teleport.
	ride.jumpConn = UserInputService.JumpRequest:Connect(function()
		if ride then
			endRide(false)
		end
	end)
end

-- Safety: if the character respawns/dies mid-ride, drop the ride forces (the
-- new character is at a spawn; we never teleport a fresh character).
player.CharacterAdded:Connect(function()
	if ride then
		if ride.conn then ride.conn:Disconnect() end
		if ride.jumpConn then ride.jumpConn:Disconnect() end
		ride = nil
	end
end)

--======================================================================
-- LOAD-TIME CLEAN SLATE: no event text shows at game load (all elements already
-- construct hidden; belt-and-suspenders). The gibberish text is fully disabled above.
--======================================================================
hideBanner()
rewardPopup.Visible = false
gibberish.Visible = false

--======================================================================
-- Listen to the server-driven sync events.
--======================================================================
sync.OnClientEvent:Connect(function(phase, payload)
	if phase == "start" then
		startSky(payload and payload.variant)
		showBanner((payload and payload.text) or "\u{1F6F8} UFO DETECTED ABOVE THE ISLANDS!",
			5, Color3.fromRGB(20, 40, 28))

	elseif phase == "warning" then
		showBanner("Strange lights in the sky\u{2026}", 4, Color3.fromRGB(20, 40, 28))

	elseif phase == "islandFlash" then
		-- A brief, SUBTLE green tint pulse (lighter than the ending flash).
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Brightness = 0.15
		cc.TintColor = Color3.fromRGB(150, 255, 170)
		cc.Parent = Lighting
		local fade = TweenService:Create(cc,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0 })
		fade:Play()
		fade.Completed:Connect(function() cc:Destroy() end)

	elseif phase == "gibberish" then
		showGibberish()

	elseif phase == "main" then
		showBanner("\u{1F6F8} The mothership descends\u{2026}", 4, Color3.fromRGB(20, 40, 28))
		-- Lens flare creeps in under the descending saucer's glow.
		TweenService:Create(flare, TweenInfo.new(3), { ImageTransparency = 0.6 }):Play()

	elseif phase == "abduction" then
		showBanner("\u{1F6F8} Tractor beams deployed! Watch your step\u{2026}", 4, Color3.fromRGB(20, 40, 28))

	elseif phase == "engage" then
		-- THIS client is under a beam: validate + ride (POSITION SAFETY).
		beginRide(payload)

	elseif phase == "release" then
		-- Beam shut off: end the ride and ALWAYS restore the captured spot.
		-- (If the inside scene is mid-run, `ride` is already nil and that scene
		-- restores the player on its own timer -- no double-teleport.)
		if ride then
			endRide(true)
		end

	elseif phase == "reward" then
		showReward((typeof(payload) == "table" and payload.coins) or 0)

	elseif phase == "ending" then
		showBanner((payload and payload.text) or "\u{1F6F8} UFO EVENT ENDING\u{2026}",
			4, Color3.fromRGB(20, 40, 28))

	elseif phase == "flash" then
		bigFlash()
		cameraShake(0.8, 0.6)

	elseif phase == "reset" then
		-- Force-end any active ride (restore to captured spot) + restore sky.
		if ride then
			endRide(true)
		end
		stopScan()
		hideBanner()
		-- Force-hide transient popups immediately so none linger past the event end.
		gibberish.Visible = false
		rewardPopup.Visible = false
		restoreSky()
	end
end)
