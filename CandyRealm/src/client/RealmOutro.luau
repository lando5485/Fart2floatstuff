--======================================================================
-- RealmOutro.luau  (ModuleScript, StarterPlayerScripts)  -- CandyRealm
--======================================================================
-- THE CROSSING CINEMATIC, PORTED FROM THE FOOD REALM'S PORTALS.
--
-- Walking into a portal on Bean Island plays a 4.2-second shot before the teleport: the world dims and
-- the doorway swells, the HUD peels off screen, an iris of portal-light opens from the centre and
-- swallows the frame, and it lands on a titled card in the destination realm's own colours. Coming the
-- other way -- back out of the Candy realm, through the wormhole's realm rows -- there was nothing at
-- all: a warp whoosh and an abrupt place swap.
--
-- ===== IT IS THE SAME SHOT, NOT A REBUILD =====
-- The body below is `playPortalOutro` lifted VERBATIM from
-- `Fart2floatstuff/src/client/RealmPortals.client.luau`. Two edits, both forced by the move:
--   * the HUD sweep no longer skips `msgGui` -- that is RealmPortals' own "you can't go there yet"
--     label, and it does not exist in this place.
--   * the two log prefixes say [RealmOutro] so a line in the output names the file that printed it.
-- Nothing about the timing, the beats, the easing or the layering has been touched. If the crossing
-- ever needs retuning, retune it THERE and re-port -- two copies that have drifted are worse than one
-- copy that is slightly wrong in both directions.
--
-- ===== THE LOOKS ARE MIRRORED =====
-- The Food realm ships looks for the three realms IT can reach (space / dino / candy). This place
-- reaches a different three (food / space / dino), so `space` and `dino` are its rows copied across
-- byte for byte -- the Space Realm should look identical whichever door you came through -- and `food`
-- is new, because no realm has ever needed a way to describe going BACK to the start.
--
-- ===== WHY A MODULE AND NOT A COPY IN THE WORMHOLE =====
-- WormholeClient is already the longest client file that is not a quest, and this is 390 lines of
-- cinematic that has nothing to do with listing islands. A module also means the day this realm grows
-- its own outbound portals, they call the same function rather than growing a second crossing that
-- looks almost but not quite the same.
--======================================================================

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local RunService    = game:GetService("RunService")
local Workspace     = game:GetService("Workspace")
local SoundService  = game:GetService("SoundService")
local Debris        = game:GetService("Debris")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RealmOutro = {}

--------------------------------------------------------------------------------
-- THE LOOKS -- one row per realm this place can travel to
--------------------------------------------------------------------------------
-- Every colour a crossing uses comes from here, which is what makes one shot read as three different
-- transitions. `space` and `dino` are RealmPortals' own rows, unchanged, so a player crossing Food ->
-- Space and Candy -> Space sees the same purple.
RealmOutro.LOOKS = {
	space = {
		emoji = "\xF0\x9F\x9A\x80", title = "SPACE REALM", name = "Space Realm",
		rune    = Color3.fromRGB(150, 120, 255),
		vortex  = Color3.fromRGB(120, 80, 235),
		lightA  = Color3.fromRGB(90, 150, 255),  -- blue...
		lightB  = Color3.fromRGB(185, 120, 255), -- ...and purple
		spark   = Color3.fromRGB(235, 228, 255),
		dim = 1,
	},
	dino = {
		emoji = "\xF0\x9F\xA6\x96", title = "DINO REALM", name = "Dino Realm",
		rune    = Color3.fromRGB(120, 235, 130),
		vortex  = Color3.fromRGB(70, 205, 100),
		lightA  = Color3.fromRGB(105, 235, 130), -- green energy
		lightB  = Color3.fromRGB(190, 245, 140),
		spark   = Color3.fromRGB(210, 255, 170),
		dim = 1,
	},
	-- NEW. The Food realm is where every player starts and the only realm nothing has ever had to
	-- describe travelling TO -- it is the place the other three are reached FROM. Built on its own
	-- islands rather than on a fourth invented palette: bean green against the warm gold of the
	-- wheat and butter islands, which is what the food tower actually looks like from the air.
	food = {
		emoji = "\xF0\x9F\xAB\x98", title = "FOOD REALM", name = "Food Realm",
		rune    = Color3.fromRGB(196, 245, 160),
		vortex  = Color3.fromRGB(120, 200, 90),
		lightA  = Color3.fromRGB(140, 215, 100), -- bean green...
		lightB  = Color3.fromRGB(250, 205, 110), -- ...and butter gold
		spark   = Color3.fromRGB(255, 244, 214),
		dim = 1,
	},
}

--------------------------------------------------------------------------------
-- THE ENTRY SOUND -- the same asset the portals fire on touch
--------------------------------------------------------------------------------
-- 2D (SoundService), because this is your own crossing rather than an event out in the world. One
-- Sound reused for every trip; the caller debounces, so this cannot machine-gun.
local ENTER_SOUND_ID = "rbxassetid://111559442515692"
local enterSound = Instance.new("Sound")
enterSound.Name = "RealmOutroEnter"
enterSound.SoundId = ENTER_SOUND_ID
enterSound.Volume = 0.8
enterSound.Parent = SoundService

-- SAY SO AT BOOT IF IT IS NOT AUTHORISED. This id belongs to the Food realm's place, and an asset is
-- only usable by the experience its creator uploaded it under -- this realm's log already carries
-- several "User is not authorized to access Asset" lines for exactly that reason. A silent crossing
-- is indistinguishable from a broken one, so the check runs once and names the id.
task.spawn(function()
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ enterSound }, function(_, status)
			if status == Enum.AssetFetchStatus.Success then
				print(("[RealmOutro] crossing sound %s loaded OK (%.2fs)"):format(ENTER_SOUND_ID, enterSound.TimeLength))
			else
				warn(("[RealmOutro] crossing sound %s FAILED to load (%s) -- the cinematic still plays, it is "
					.. "just silent. The id is the Food realm's; it has to be authorised for THIS experience too.")
					:format(ENTER_SOUND_ID, tostring(status)))
			end
		end)
	end)
end)

function RealmOutro.playSound()
	pcall(function() enterSound:Play() end)
end

--------------------------------------------------------------------------------
-- THE SHOT
--------------------------------------------------------------------------------
-- SHORTER THAN THE BLACK HOLE ON PURPOSE (4.2s vs 6.2s). The black hole is a one-time discovery and can
-- afford to be a set piece; a realm crossing is the everyday route and gets used over and over, so this
-- has to stay something you enjoy the fifth time.
local PORTAL_CINEMATIC_SECONDS = 4.2
-- FOUR beats, not three. The shot used to detonate on frame one -- you touched the vortex and the entire
-- interface was already flying off screen, which reads as a glitch before it reads as a transition. INTAKE
-- is the anticipation beat that fixes it: for half a second nothing leaves, the world just dims and the
-- portal light swells and the frame tightens, as though the doorway has noticed you. THEN the HUD goes.
-- Every good transition has a breath before the move; without one the move looks like a mistake.
local P_INTAKE, P_THRESHOLD, P_CROSS = 0.6, 1.0, 1.6

-- Set to the running shot's teardown while an outro is on screen, nil otherwise. It lets a failed
-- teleport cancel the cinematic immediately rather than waiting out the backstop timer.
local abortOutro = nil
local outroRunning = false

local function playPortalOutro(look)
	if outroRunning then return end
	outroRunning = true
	-- Proof the shot actually started, and which realm's look it got. If the travel sound plays and this
	-- line does NOT appear, the outro was never entered; if it appears and you still see no transition,
	-- the problem is inside the shot rather than in reaching it.
	print("[RealmOutro] OUTRO START -> " .. tostring(look and look.title or "?"))

	local cam = Workspace.CurrentCamera
	local origFov = cam and cam.FieldOfView or 70
	local heldCF = cam and cam.CFrame or CFrame.new()
	local restored, renderConn, guiAddedConn, blur, gui = false, nil, nil, nil, nil
	local hidden = {}
	local shakeMag = 0

	-- ONE teardown. The SUCCESS path never calls it -- we hold on black and the teleport is the cut. This
	-- exists for the failure paths and the backstop (Studio, where TeleportAsync does nothing at all).
	local function restore()
		if restored then return end
		restored = true
		if renderConn then renderConn:Disconnect() end
		if guiAddedConn then guiAddedConn:Disconnect() end
		pcall(function()
			local c = Workspace.CurrentCamera
			if c then
				c.CameraType = Enum.CameraType.Custom
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum then c.CameraSubject = hum end
				c.FieldOfView = origFov
			end
		end)
		if blur then pcall(function() blur:Destroy() end) end
		for sg, wasOn in pairs(hidden) do pcall(function() sg.Enabled = wasOn end) end
		pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
		if gui then pcall(function() gui:Destroy() end) end
		outroRunning = false
		abortOutro = nil
	end

	-- Published so the "error" reply from the server can end the shot the instant the teleport is known to
	-- have failed, instead of leaving the player staring at a card while a timer runs down.
	abortOutro = restore

	-- THE BACKSTOP -- 2.5s past the end of the shot, not 10.
	-- On a real crossing this never fires: the server teleports at 4.2s and the place swap takes the whole
	-- client with it. It only matters when the teleport DOESN'T happen -- in Studio, where TeleportAsync
	-- always fails, or on a live server that refuses. In that case the old +10 left you sitting on a black
	-- screen with no HUD for FOURTEEN SECONDS, which does not read as a cinematic, it reads as the HUD being
	-- broken. If we are still in this place 2.5s after the card has landed, the crossing did not happen and
	-- the interface should come back promptly.
	task.delay(PORTAL_CINEMATIC_SECONDS + 2.5, restore)

	-- Dying or respawning mid-shot also ends it. The HUD is hidden by .Enabled, which survives respawn, so
	-- without this a death during the crossing would strand the player with no interface at all.
	do
		local conn
		conn = player.CharacterAdded:Connect(function()
			if conn then conn:Disconnect() end
			restore()
		end)
		task.delay(PORTAL_CINEMATIC_SECONDS + 3, function() if conn then conn:Disconnect() end end)
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "RealmPortalOutro"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global; gui.DisplayOrder = 10000
	gui.Parent = playerGui

	local shell = Instance.new("Frame")
	shell.Size = UDim2.new(1, 0, 1, 0); shell.BackgroundTransparency = 1; shell.ZIndex = 2
	shell.Parent = gui

	-- ---- measure the HUD where it actually sits, then let it fall behind ----
	local ghosts = {}
	pcall(function()
		for _, sg in ipairs(playerGui:GetChildren()) do
			if sg:IsA("ScreenGui") and sg.Enabled and sg ~= gui then
				for _, obj in ipairs(sg:GetChildren()) do
					if #ghosts >= 24 then break end
					if obj:IsA("GuiObject") and obj.Visible and obj.AbsoluteSize.X > 24 and obj.AbsoluteSize.Y > 12 then
						local g = Instance.new("Frame")
						g.Position = UDim2.fromOffset(obj.AbsolutePosition.X, obj.AbsolutePosition.Y)
						g.Size = UDim2.fromOffset(obj.AbsoluteSize.X, obj.AbsoluteSize.Y)
						g.BackgroundColor3 = obj.BackgroundColor3
						-- Faint and edgeless -- see the same note in the black hole shot. An outlined, rounded
						-- rectangle sliding off screen is furniture being thrown; a feathered smear of the
						-- colour that used to be there is an interface being left behind.
						g.BackgroundTransparency = math.clamp(obj.BackgroundTransparency, 0.55, 0.82)
						g.BorderSizePixel = 0; g.ZIndex = 8; g.Parent = shell
						local gg = Instance.new("UIGradient")
						gg.Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1),
							NumberSequenceKeypoint.new(0.5, 0),
							NumberSequenceKeypoint.new(1, 1),
						})
						gg.Rotation = 90
						gg.Parent = g
						ghosts[#ghosts + 1] = g
					end
				end
			end
		end
	end)

	local function hideOne(child)
		if child == gui or not child:IsA("ScreenGui") then return end
		if hidden[child] == nil then hidden[child] = child.Enabled; child.Enabled = false end
	end
	for _, c in ipairs(playerGui:GetChildren()) do hideOne(c) end
	guiAddedConn = playerGui.ChildAdded:Connect(hideOne)
	pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)

	-- ---- the iris: portal light opening up to take the whole frame ----
	local iris = Instance.new("Frame")
	iris.AnchorPoint = Vector2.new(0.5, 0.5); iris.Position = UDim2.new(0.5, 0, 0.5, 0)
	iris.Size = UDim2.new(0, 0, 0, 0)
	iris.BackgroundColor3 = look.lightA
	iris.BackgroundTransparency = 0.15; iris.BorderSizePixel = 0; iris.ZIndex = 12; iris.Parent = shell
	Instance.new("UICorner", iris).CornerRadius = UDim.new(1, 0)
	-- NO RIM. A 10px bright ring around a growing circle is the single most "drawn shape" thing this file
	-- could put on screen. The iris now feathers out through its own gradient instead: solid colour in the
	-- middle, gone by the edge, so what expands is a wash of portal light with no boundary rather than a
	-- disc with an outline. The colour still runs lightB -> lightA across it, so it keeps the realm's look.
	local irisGrad = Instance.new("UIGradient")
	irisGrad.Color = ColorSequence.new(look.lightB or look.lightA, look.lightA)
	irisGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.28, 0.15),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.72, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	irisGrad.Rotation = 90; irisGrad.Parent = iris

	-- ---- streaks blowing PAST you (outward = you are moving forward through them) ----
	local function spawnPass()
		local s = Instance.new("Frame")
		local ang = math.rad(math.random(0, 359))
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Position = UDim2.new(0.5 + math.cos(ang) * 0.06, 0, 0.5 + math.sin(ang) * 0.06, 0)
		s.Size = UDim2.new(0, 3, 0, 18)
		s.BackgroundColor3 = (math.random() < 0.5) and (look.spark or Color3.new(1, 1, 1)) or look.lightB or look.lightA
		s.BackgroundTransparency = 0.3; s.BorderSizePixel = 0
		s.Rotation = math.deg(ang) + 90
		s.ZIndex = 10; s.Parent = shell
		-- fade to nothing at both ends: a streak of light, not a rounded pill flying past
		local sg = Instance.new("UIGradient")
		sg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		sg.Rotation = 90
		sg.Parent = s
		local dur = 0.3 + math.random() * 0.25
		pcall(function()
			TweenService:Create(s, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5 + math.cos(ang) * 1.2, 0, 0.5 + math.sin(ang) * 1.2, 0),
				Size = UDim2.new(0, 2, 0, 150 + math.random() * 90), -- stretches as it flies past
				BackgroundTransparency = 1,
			}):Play()
		end)
		game:GetService("Debris"):AddItem(s, dur + 0.1)
	end

	renderConn = RunService.RenderStepped:Connect(function()
		if restored then return end
		local c = Workspace.CurrentCamera
		if c then c.CameraType = Enum.CameraType.Scriptable; c.CFrame = heldCF end
		if shakeMag > 0 then
			shell.Position = UDim2.new(0, math.random(-8, 8) * shakeMag, 0, math.random(-8, 8) * shakeMag)
		else
			shell.Position = UDim2.new(0, 0, 0, 0)
		end
	end)

	blur = Instance.new("BlurEffect"); blur.Size = 0; blur.Parent = game:GetService("Lighting")

	local ok, err = pcall(function()
		-- ===== BEAT 0: INTAKE (0.6s) -- the doorway notices you =====
		-- Nothing leaves yet. The world dims a touch, the portal's light rises out of the middle of the
		-- screen, and the FOV pulls IN slightly -- a held breath before the step forward. The FOV tightening
		-- here is what makes the widening in the next beats land: without something to push against, a
		-- widening lens just looks like a lens.
		pcall(function()
			TweenService:Create(iris, TweenInfo.new(P_INTAKE, Enum.EasingStyle.Sine,
				Enum.EasingDirection.Out), { Size = UDim2.new(0, 90, 0, 90) }):Play()
			TweenService:Create(blur, TweenInfo.new(P_INTAKE), { Size = 4 }):Play()
		end)
		local t0 = os.clock()
		while not restored and (os.clock() - t0) < P_INTAKE do
			local a = (os.clock() - t0) / P_INTAKE
			if cam then cam.FieldOfView = origFov - a * 6 end -- the inhale
			task.wait()
		end
		if restored then return end

		-- ===== BEAT 1: THRESHOLD (1.0s) -- the interface falls behind =====
		for i, g in ipairs(ghosts) do
			task.delay((i - 1) * 0.03, function()
				pcall(function()
					-- each panel flies out through the nearest edge, away from centre
					local gx = g.AbsolutePosition.X + g.AbsoluteSize.X * 0.5
					local gy = g.AbsolutePosition.Y + g.AbsoluteSize.Y * 0.5
					local vx = (gx < shell.AbsoluteSize.X * 0.5) and -1 or 1
					local vy = (gy < shell.AbsoluteSize.Y * 0.5) and -1 or 1
					TweenService:Create(g, TweenInfo.new(0.7 + math.random() * 0.3,
						Enum.EasingStyle.Back, Enum.EasingDirection.In), {
						Position = UDim2.fromOffset(gx + vx * 900, gy + vy * 520),
						Rotation = vx * (18 + math.random(0, 26)),
						BackgroundTransparency = 1,
					}):Play()
				end)
			end)
			game:GetService("Debris"):AddItem(g, 2)
		end
		pcall(function()
			TweenService:Create(iris, TweenInfo.new(P_THRESHOLD, Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out), { Size = UDim2.new(0, 240, 0, 240) }):Play()
			TweenService:Create(blur, TweenInfo.new(P_THRESHOLD), { Size = 10 }):Play()
		end)
		t0 = os.clock()
		while not restored and (os.clock() - t0) < P_THRESHOLD do
			local a = (os.clock() - t0) / P_THRESHOLD
			shakeMag = a * 0.5
			-- picks up exactly where the inhale left off (-6) and swings through to +10, so the release out
			-- of the anticipation beat is one continuous move rather than a snap back to neutral first
			if cam then cam.FieldOfView = origFov - 6 + a * 16 end
			task.wait()
		end
		if restored then return end

		-- ===== BEAT 2: CROSS (1.6s) -- the doorway takes the screen =====
		pcall(function()
			TweenService:Create(iris, TweenInfo.new(P_CROSS * 0.8, Enum.EasingStyle.Quint,
				Enum.EasingDirection.In), { Size = UDim2.new(2.6, 0, 2.6, 0), BackgroundTransparency = 0 }):Play()
			TweenService:Create(blur, TweenInfo.new(P_CROSS), { Size = 22 }):Play()
		end)
		local passClock = 0
		t0 = os.clock()
		while not restored and (os.clock() - t0) < P_CROSS do
			local dt = task.wait()
			local a = (os.clock() - t0) / P_CROSS
			shakeMag = 0.5 + a * 0.7
			if cam then cam.FieldOfView = origFov + 10 + a * 16 end
			passClock += dt
			-- one at a time, half as often: two per 0.02s filled the screen with individually readable
			-- objects instead of a sense of speed
			if passClock > 0.04 then passClock = 0; spawnPass() end
		end
		if restored then return end

		-- ===== BEAT 3: CARD (1.0s) -- the destination, and hold =====
		-- This is the last thing the player sees before the place swaps, and it was the cheapest-looking
		-- moment in the whole shot: flat black with a word on it. Four changes, all of them light rather
		-- than shapes, so it stays in the same visual language as the rest:
		--
		--   GROUND  not pure black. A near-black tinted toward the realm's own colour, so the screen still
		--           belongs to where you are going instead of being an absence of picture.
		--   GLOW    a wide, fully feathered disc of realm light behind the text. It is what stops the card
		--           reading as a loading screen -- there is depth behind the words.
		--   SETTLE  the title arrives slightly oversized and eases down to true size as it fades up. A word
		--           that simply appears is a label; a word that settles was placed there.
		--   LINE    a thin horizontal light, feathered to nothing at both ends, that widens out from under
		--           the title. It gives the eye something completing rather than something waiting.
		shakeMag = 0
		--======================================================================
		-- FULL-BLEED. NO BAND, NO BARS, NO SEAM.
		--======================================================================
		-- This card used to be a black screen with a 420px-tall CAPSULE of realm light lying across the
		-- middle of it: `glow` was Size (1.4, 0, 0, 420) with UICorner(1,0) and its transparency tweened to
		-- 0, so what actually rendered was a solid coloured strip with a hard rounded edge, floating on
		-- plain black above and below. On a phone that strip was most of the screen; on an ultrawide it was
		-- a letterbox. Either way it read as a panel that had failed to load rather than as a shot.
		--
		-- The fix is two layers, BOTH edge-to-edge, and no shape anywhere:
		--   GROUND  the whole viewport, carrying a vertical realm gradient. Every pixel is coloured, so
		--           there is no "rest of the screen" left plain black to have an edge against.
		--   GLOW    also the whole viewport, feathered to FULLY transparent at the top and bottom edges. It
		--           still puts light behind the words -- that was the point of it -- but it now arrives at
		--           the screen edge already at zero, so there is nothing for a seam to form on.
		-- The ScreenGui is IgnoreGuiInset = true (above) and neither layer has a parent frame with an
		-- offset height, so this covers the true viewport on every aspect ratio.
		local black = Instance.new("Frame")
		black.Size = UDim2.fromScale(1, 1)
		black.Position = UDim2.fromScale(0, 0)
		black.AnchorPoint = Vector2.new(0, 0)
		-- 6% of the realm hue over black: enough to feel coloured, nowhere near enough to look lit
		black.BackgroundColor3 = look.lightA:Lerp(Color3.new(0, 0, 0), 0.94)
		black.BackgroundTransparency = 1; black.BorderSizePixel = 0; black.ZIndex = 25; black.Parent = gui
		do
			-- Top and bottom sit a touch darker than the middle, so the screen has a direction to it and the
			-- eye is walked to the title. It is a gradient across the WHOLE height -- not a shape with ends.
			local bg = Instance.new("UIGradient")
			local deep = look.lightA:Lerp(Color3.new(0, 0, 0), 0.975)
			local mid  = look.lightA:Lerp(Color3.new(0, 0, 0), 0.90)
			bg.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, deep),
				ColorSequenceKeypoint.new(0.5, mid),
				ColorSequenceKeypoint.new(1, deep),
			})
			bg.Rotation = 90
			bg.Parent = black
		end

		local glow = Instance.new("Frame")
		glow.AnchorPoint = Vector2.new(0, 0)
		glow.Position = UDim2.fromScale(0, 0)
		glow.Size = UDim2.fromScale(1, 1)
		glow.BackgroundColor3 = look.lightA
		glow.BackgroundTransparency = 1; glow.BorderSizePixel = 0; glow.ZIndex = 26; glow.Parent = gui
		-- NO UICorner here. The rounded corner is what turned this layer into a visible capsule with an
		-- outline; a full-screen layer that fades to nothing needs no shape at all.
		do
			local gg = Instance.new("UIGradient")
			-- Rotation 90 = top-to-bottom. Fully transparent at both screen edges, brightest across the
			-- middle where the title sits, and every step between is interpolated -- so the light falls off
			-- smoothly all the way to the edge instead of stopping at one.
			gg.Rotation = 90
			gg.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.28, 0.94),
				NumberSequenceKeypoint.new(0.5, 0.82),
				NumberSequenceKeypoint.new(0.72, 0.94),
				NumberSequenceKeypoint.new(1, 1),
			})
			gg.Parent = glow
		end

		local card = Instance.new("TextLabel")
		card.AnchorPoint = Vector2.new(0.5, 0.5); card.Position = UDim2.new(0.5, 0, 0.5, 0)
		card.Size = UDim2.new(1.02, 0, 0, 102) -- oversized; settles to 0.9/90 below
		card.BackgroundTransparency = 1
		card.Font = Enum.Font.FredokaOne; card.TextScaled = true
		card.TextColor3 = look.spark or Color3.new(1, 1, 1); card.TextTransparency = 1
		card.Text = look.title or "TRAVELLING"; card.ZIndex = 28; card.Parent = gui
		do local c = Instance.new("UITextSizeConstraint", card); c.MaxTextSize = 58 end
		local cardStroke = Instance.new("UIStroke", card)
		cardStroke.Color = look.lightA; cardStroke.Thickness = 3; cardStroke.Transparency = 1

		local sub = Instance.new("TextLabel")
		sub.AnchorPoint = Vector2.new(0.5, 0.5); sub.Position = UDim2.new(0.5, 0, 0.5, 62)
		sub.Size = UDim2.new(0.8, 0, 0, 30); sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamMedium; sub.TextScaled = true
		sub.TextColor3 = look.lightA; sub.TextTransparency = 1
		sub.Text = (look.emoji or "") .. "  entering the " .. (look.name or "realm")
		sub.ZIndex = 28; sub.Parent = gui
		do local c = Instance.new("UITextSizeConstraint", sub); c.MaxTextSize = 20 end

		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0.5); line.Position = UDim2.new(0.5, 0, 0.5, 38)
		line.Size = UDim2.new(0, 0, 0, 2)
		line.BackgroundColor3 = look.lightA
		line.BackgroundTransparency = 0.25; line.BorderSizePixel = 0; line.ZIndex = 28; line.Parent = gui
		do
			local lg = Instance.new("UIGradient")
			lg.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			lg.Parent = line
		end

		pcall(function()
			TweenService:Create(black, TweenInfo.new(0.4, Enum.EasingStyle.Quad,
				Enum.EasingDirection.In), { BackgroundTransparency = 0 }):Play()
		end)
		task.wait(0.4)
		pcall(function()
			TweenService:Create(glow, TweenInfo.new(0.6), { BackgroundTransparency = 0 }):Play()
			TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out), { TextTransparency = 0, Size = UDim2.new(0.9, 0, 0, 90) }):Play()
			TweenService:Create(cardStroke, TweenInfo.new(0.45), { Transparency = 0 }):Play()
			TweenService:Create(line, TweenInfo.new(0.55, Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out), { Size = UDim2.new(0.42, 0, 0, 2) }):Play()
		end)
		task.delay(0.2, function()
			pcall(function()
				TweenService:Create(sub, TweenInfo.new(0.4), { TextTransparency = 0.25 }):Play()
			end)
		end)
		-- HOLD. The teleport lands here.
	end)

	if not ok then
		warn("[RealmOutro] cinematic error: " .. tostring(err))
		restore()
	end
end

--------------------------------------------------------------------------------
-- THE PUBLIC FACE
--------------------------------------------------------------------------------
-- play(key) takes a realm KEY ("food" / "space" / "dino") rather than a look table, so a caller never
-- has to know what a look is. An unknown key is a no-op that says so instead of a nil-index error
-- three frames into a full-screen cinematic.
function RealmOutro.play(key)
	local look = RealmOutro.LOOKS[tostring(key)]
	if not look then
		warn(("[RealmOutro] no look for realm '%s' -- crossing plays no cinematic"):format(tostring(key)))
		return false
	end
	playPortalOutro(look)
	return true
end

-- HOW LONG THE SHOT RUNS. The caller needs this to know when the card has landed -- on a real crossing
-- the teleport happens under the card and the place swap takes the whole client with it.
RealmOutro.SECONDS = PORTAL_CINEMATIC_SECONDS

-- End the shot NOW. For the failure paths: a refused or failed teleport should hand the interface back
-- immediately rather than leaving the player on a card while the backstop timer runs down.
function RealmOutro.abort()
	if abortOutro then pcall(abortOutro) end
end

return RealmOutro
