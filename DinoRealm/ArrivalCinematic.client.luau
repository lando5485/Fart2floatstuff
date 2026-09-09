--======================================================================
-- ArrivalCinematic.client.luau  (LocalScript)   [RECEIVING PLACE — the DINO REALM]
--======================================================================
--[[
	The OTHER HALF of the seam. Put this in StarterPlayerScripts of the DINO REALM place.

	The Space Realm's rift cinematic ends on a dino-green title card and holds there while the teleport
	fires. This script opens the Dino Realm on that SAME card and wakes the player up out of it — so the
	place boundary is hidden inside the transition. Without this file the player gets: rift -> card ->
	*Roblox loading screen* -> hard cut to a jungle. With it, they get one continuous shot.

	THE SHOT (~10s, all of it on the client, nothing gated on the server):
	  0.0        THE HANDOFF  the exact card the rift left up — same green-black gradient ground, same
	                          "D I N O   R E A L M" kicker, rule and "65 MILLION YEARS AGO" headline, and
	                          the same embers still drifting up through it. Put up on the FIRST FRAME.
	  0.0-2.0    LISTEN       still on the card. Jungle ambience creeps in from silence: you hear where
	                          you are two full seconds before you see it.
	  2.0-4.6    SOMETHING    three FOOTSTEPS, each closer: a thud, the screen kicks, the ground flickers
	                          amber like a lamp being shaken and DUST JUMPS off the floor. On the third
	                          step it gets a BODY — a soft-edged shadow sweeps the whole screen, something
	                          enormous passing between you and the light — and then the ROAR, and the card
	                          flashes amber and goes dark.
	  4.6-8.6    EYES OPEN    THE BLINK. The reveal is not a crossfade: two eyelids open, snap shut, open
	                          wider, flutter, and finally stay open, each close spiking the blur — because
	                          the header of this beat has always claimed it is a person opening their eyes
	                          and a fade is not that. Underneath, the card and ground clear together, the
	                          CAMERA tilts up from the floor to the player's normal view with a TREMOR
	                          still in it (the thing that walked past is still walking), the FOV settles
	                          from 88 to 70, and a monospace lower-third TYPES the payoff of Neptune's
	                          quest: "ICE CORE SAMPLE 8  ·  DNA MATCH: THEROPODA". As it finishes, the
	                          roar ANSWERS from far off — pitched down and quiet, somewhere in the trees.
	  8.6-10.0   HANDBACK     lower-third fades, the camera settles at Roblox's own default framing so the
	                          hand back to Custom does not jump, HUD returns, the player can move.

	THE ONE RULE: put the cover up on the FIRST frame, before anything else. If the world renders even
	briefly before we cover it, the illusion is dead. So we check the teleport data SYNCHRONOUSLY at the
	top of the file and build the cover immediately — no WaitForChild, no yielding, first.

	WHY WE READ TELEPORT DATA ON THE CLIENT HERE:
	TeleportService:GetLocalPlayerTeleportData() is client-readable and therefore SPOOFABLE — which is
	completely fine, because everything in this file is COSMETIC. The worst an exploiter can do is give
	themselves a fade-in. Anything that MATTERS (pets, progress, spawn rights) is read server-side from
	player:GetJoinData() in ArrivalReceiver.server.luau, which cannot be faked. Never mix the two up.

	HOUSE RULES (same as the rift's client): one idempotent restore(), a hard master timeout, every exit
	path funnels through it, HUD hidden by toggling .Enabled and never destroyed, every asset touch pcall'd.
]]
--======================================================================
local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local TweenService    = game:GetService("TweenService")
local SoundService    = game:GetService("SoundService")
local StarterGui      = game:GetService("StarterGui")
local Lighting        = game:GetService("Lighting")
local RunService      = game:GetService("RunService")
local Debris          = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")
local Workspace       = game:GetService("Workspace")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ---- Did we arrive through the rift? (cosmetic only — see the header) ----
local data
pcall(function() data = TeleportService:GetLocalPlayerTeleportData() end)
if type(data) ~= "table" or data.arrivedViaRift ~= true then
	-- Joined the Dino Realm directly from the Roblox site (or the payload was lost). No transition to
	-- continue — just let them into the world normally. Do NOT black their screen out.
	print("[DinoArrival] direct join — no rift transition to continue")
	return
end

-- ===== SOUND IDS =====
-- All public-domain Creator Store audio, each confirmed AssetTypeId 3 + IsPublicDomain via the economy
-- API before being written here. Lists are tried IN ORDER by mkSound below.
local AMBIENCE_IDS = { "rbxassetid://9114892930" }                    -- "Jungle Birds Ambience 3" (36s, looped)
local ROAR_IDS     = { "rbxassetid://8413998658", "rbxassetid://105936998482350", "rbxassetid://150829983" } -- same chain as the rift
local FOOTSTEP_IDS = { "rbxassetid://9125404320", "rbxassetid://9125403433" } -- "Boom Impact Deep Distant Thumping Hit" (3s); pitched down per step below

-- ===== PALETTE — must match DinoRiftClient's card exactly, or the seam shows =====
local BONE        = Color3.fromRGB(255, 234, 196)
local AMBER       = Color3.fromRGB(255, 176, 64)
local DINO_ACCENT = Color3.fromRGB(105, 235, 130)

local MASTER_TIMEOUT = 25 -- hard backstop: never strand a player on a covered screen

-- Roblox has no letter-spacing, so a spaced-out title is typed. Same helper as the rift, same look.
local function spaced(s) return (s:gsub(".", "%0 "):gsub(" $", "")) end

-- ======================================================================
-- FIRST FRAME: cover everything, carrying the EXACT card the Space Realm left up.
-- ======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "DinoArrivalCinematic"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
gui.DisplayOrder = 10000
gui.Parent = PlayerGui

-- The ground: the rift's own full-bleed dino-green gradient, darker at the top and bottom edges than
-- through the middle. It used to be flat black here, which made a visible colour pop at the seam.
local ground = Instance.new("Frame")
ground.Size = UDim2.fromScale(1, 1)
ground.Position = UDim2.fromScale(0, 0)
ground.BackgroundColor3 = DINO_ACCENT:Lerp(Color3.new(0, 0, 0), 0.94)
ground.BackgroundTransparency = 0 -- OPAQUE from frame one — this is the handoff
ground.BorderSizePixel = 0
ground.ZIndex = 1
ground.Parent = gui
local groundGrad = Instance.new("UIGradient")
do
	local deep = DINO_ACCENT:Lerp(Color3.new(0, 0, 0), 0.975)
	local mid  = DINO_ACCENT:Lerp(Color3.new(0, 0, 0), 0.90)
	groundGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, deep),
		ColorSequenceKeypoint.new(0.5, mid),
		ColorSequenceKeypoint.new(1, deep),
	})
	groundGrad.Rotation = 90
	groundGrad.Parent = ground
end
-- An amber wash OVER the ground, normally invisible: the footsteps and the roar flicker it.
local wash = Instance.new("Frame")
wash.Size = UDim2.fromScale(1, 1)
wash.BackgroundColor3 = AMBER
wash.BackgroundTransparency = 1
wash.BorderSizePixel = 0
wash.ZIndex = 2
wash.Parent = gui

-- THE BODY BEHIND THE FOOTSTEPS. Three thuds and a card kick tell you something big is near; they never
-- show you any of it, so the beat is all sound and no subject. This is the subject: a soft-edged column of
-- shadow that sweeps the whole screen on the third step — something enormous passing between you and the
-- light. Gradient-edged rather than a hard bar, because a hard bar is a wipe and this has to read as a leg.
local shadow = Instance.new("Frame")
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.new(-0.5, 0, 0.5, 0)
shadow.Size = UDim2.new(0.7, 0, 1.5, 0)
shadow.Rotation = -7 -- off-vertical: a leg swings, it does not slide
shadow.BackgroundColor3 = Color3.new(0, 0, 0)
shadow.BackgroundTransparency = 1
shadow.BorderSizePixel = 0
shadow.ZIndex = 6
shadow.Parent = gui
do
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.12),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = shadow
end

-- The SAME three-part card, at the same sizes/fonts/offsets as the rift's Beat 5. To the player it
-- never went away — it persisted across a place boundary, which is exactly the feeling we want.
local kicker = Instance.new("TextLabel")
kicker.AnchorPoint = Vector2.new(0.5, 0.5)
kicker.Position = UDim2.new(0.5, 0, 0.5, -78)
kicker.Size = UDim2.new(0.8, 0, 0, 30)
kicker.BackgroundTransparency = 1
kicker.Font = Enum.Font.FredokaOne
kicker.TextScaled = true
kicker.TextColor3 = DINO_ACCENT
kicker.TextTransparency = 0.1
kicker.Text = spaced("DINO REALM")
kicker.ZIndex = 4
kicker.Parent = gui
do local c = Instance.new("UITextSizeConstraint", kicker); c.MaxTextSize = 26 end

local rule = Instance.new("Frame")
rule.AnchorPoint = Vector2.new(0.5, 0.5)
rule.Position = UDim2.new(0.5, 0, 0.5, -50)
rule.Size = UDim2.new(0, 300, 0, 2)
rule.BackgroundColor3 = DINO_ACCENT
rule.BackgroundTransparency = 0.35
rule.BorderSizePixel = 0
rule.ZIndex = 4
rule.Parent = gui

local card = Instance.new("TextLabel")
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.new(0.5, 0, 0.5, 16)
card.Size = UDim2.new(0.9, 0, 0, 90)
card.BackgroundTransparency = 1
card.Font = Enum.Font.FredokaOne
card.TextScaled = true
card.TextColor3 = BONE
card.TextTransparency = 0
card.Text = "65 MILLION YEARS AGO"
card.ZIndex = 4
card.Parent = gui
do local c = Instance.new("UITextSizeConstraint", card); c.MaxTextSize = 58 end

-- The lower-third that types the payoff during the reveal. Monospace, because it is a READOUT — the
-- scientist's instrument finishing the sentence it started on Neptune.
local readout = Instance.new("TextLabel")
readout.AnchorPoint = Vector2.new(0.5, 1)
readout.Position = UDim2.new(0.5, 0, 1, -64)
readout.Size = UDim2.new(0.9, 0, 0, 28)
readout.BackgroundTransparency = 1
readout.Font = Enum.Font.Code
readout.TextScaled = true
readout.TextColor3 = AMBER
readout.TextStrokeColor3 = Color3.fromRGB(20, 10, 0)
readout.TextStrokeTransparency = 0.3
readout.TextTransparency = 1
readout.Text = ""
readout.ZIndex = 5
readout.Parent = gui
do local c = Instance.new("UITextSizeConstraint", readout); c.MaxTextSize = 22 end

-- ===== EYELIDS =====
-- The reveal used to be a crossfade, which is a menu closing. These are the eyes. Two black bands, top and
-- bottom, that meet in the middle when shut and travel off-frame when open — soft-edged on their INNER lip
-- via a gradient, so the closed position reads as lashes rather than a letterbox. `lidA` is 0 = shut,
-- 1 = fully open, and the blink sequence in the reveal drives it.
local function mkLid(edge) -- edge: 0 = top, 1 = bottom
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, edge)
	f.Position = UDim2.new(0.5, 0, edge, 0)
	f.Size = UDim2.new(1.2, 0, 0.52, 0)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 1 -- invisible until the reveal takes them over
	f.BorderSizePixel = 0
	f.ZIndex = 8
	f.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = 90 -- runs top -> bottom of the band
	g.Transparency = (edge == 0)
		and NumberSequence.new({ -- top lid: solid, softening at its BOTTOM lip
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.82, 0),
			NumberSequenceKeypoint.new(1, 0.85),
		})
		or NumberSequence.new({   -- bottom lid: softening at its TOP lip
			NumberSequenceKeypoint.new(0, 0.85),
			NumberSequenceKeypoint.new(0.18, 0),
			NumberSequenceKeypoint.new(1, 0),
		})
	g.Parent = f
	return f
end
local lidTop, lidBot = mkLid(0), mkLid(1)
local lidA = 0 -- 0 = shut
local function applyLids()
	local h = 0.52 * (1 - lidA)
	lidTop.Size = UDim2.new(1.2, 0, h, 0)
	lidBot.Size = UDim2.new(1.2, 0, h, 0)
end
applyLids()

-- EMBERS, continuing. The rift's card had these drifting up through the seam; the first thing this
-- place does is keep them going, so the two PLACES share motion across the boundary.
local embersOn = true
-- One ember. Pulled out of the loop so a FOOTSTEP can throw a handful of them at once (see puff below) —
-- dust jumping off the floor on each thud, which is the cheapest way to make an off-screen animal weigh
-- something. `rush` shortens the climb so a kicked-up mote moves visibly faster than a drifting one.
local function spawnEmber(rush)
	if not gui.Parent then return end
	local sz = 2 + math.random() * 3
	local em = Instance.new("Frame")
	em.Name = "Ember"
	em.AnchorPoint = Vector2.new(0.5, 0.5)
	em.Position = UDim2.new(math.random(), 0, 1.05, 0)
	em.Size = UDim2.new(0, sz, 0, sz)
	em.BackgroundColor3 = (math.random() < 0.4) and DINO_ACCENT or AMBER
	em.BackgroundTransparency = 0.35
	em.BorderSizePixel = 0
	em.ZIndex = 3
	em.Parent = gui
	Instance.new("UICorner", em).CornerRadius = UDim.new(1, 0)
	local dur = rush and (1.1 + math.random() * 1.1) or (3 + math.random() * 3)
	pcall(function()
		TweenService:Create(em, TweenInfo.new(dur, Enum.EasingStyle.Linear), {
			Position = UDim2.new(em.Position.X.Scale + (math.random() - 0.5) * (rush and 0.24 or 0.1), 0, -0.1, 0),
			BackgroundTransparency = 1,
		}):Play()
	end)
	Debris:AddItem(em, dur + 0.2)
end
local function puff(n)
	for _ = 1, n do spawnEmber(true) end
end
task.spawn(function()
	while embersOn and gui.Parent do
		spawnEmber(false)
		task.wait(0.12)
	end
end)

-- Hide the HUD while we're covered (toggle .Enabled, never destroy — restored below).
local hidden = {}
local function hideOne(child)
	if child == gui or not child:IsA("ScreenGui") then return end
	if hidden[child] == nil then hidden[child] = child.Enabled; child.Enabled = false end
end
for _, c in ipairs(PlayerGui:GetChildren()) do hideOne(c) end
local guiAdded = PlayerGui.ChildAdded:Connect(hideOne)
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
pcall(function() StarterGui:SetCore("TopbarEnabled", false) end)

local blur = Instance.new("BlurEffect")
blur.Size = 28
blur.Parent = Lighting
local cc = Instance.new("ColorCorrectionEffect")
cc.Parent = Lighting

-- ===== SOUNDS: one persistent Sound per cue, verified, walking a list of ids =====
local function mkSound(ids, vol, looped, label)
	local s = Instance.new("Sound")
	s.SoundId = ids[1]; s.Volume = vol; s.Looped = looped; s.Parent = SoundService
	task.spawn(function() -- route through the SFX slider if this place has one
		local grp = SoundService:FindFirstChild("SFXGroup")
		if grp and grp:IsA("SoundGroup") then s.SoundGroup = grp end
	end)
	task.spawn(function()
		for _, id in ipairs(ids) do
			s.SoundId = id
			local ok = pcall(function() ContentProvider:PreloadAsync({ s }) end)
			if ok and s.TimeLength > 0 then return end
		end
		warn(("[DinoArrival] %s sound failed to load (%s) -- that cue is silent."):format(label, table.concat(ids, ", ")))
	end)
	return s
end
local ambience = mkSound(AMBIENCE_IDS, 0, true, "ambience")
local roar     = mkSound(ROAR_IDS, 1.0, false, "roar")
-- THE ANSWER. Its own Sound rather than a re-trigger of `roar`, because it is a different animal in a
-- different place: pitched down and quiet, played over the top of the reveal while `roar`'s own tail may
-- still be ringing. One instance could not be both, and re-triggering would cut the first one off.
local roarFar  = mkSound(ROAR_IDS, 0.34, false, "distant roar")
local footstep = mkSound(FOOTSTEP_IDS, 0.8, false, "footstep")

-- ===== CAMERA + THE PLAYER'S FEET =====
-- The player's own client anchors their HumanoidRootPart for the length of the shot: their screen is
-- covered, so a stumble now would be invisible to them and visible to everyone else. Network-owned
-- by this client, so it takes effect locally and is undone in restore().
local cam = Workspace.CurrentCamera
local origFov = cam and cam.FieldOfView or 70
local camDriven = false
local camCF = nil
local anchoredHRP = nil
-- THE TREMOR. The reveal used to be perfectly steady, which quietly undoes the beat before it: something
-- the size of a house just walked past and the world it left behind was rock solid. This is the same
-- continuous-noise shake the rift's shaft uses (three math.noise channels, NOT math.random per frame —
-- white noise at 60fps reads as buzzing static, noise reads as a rig being walked on), decayed to nothing
-- across the reveal so the picture is dead still by the time the player gets it back.
local tremor = 0
local tremorSeed = math.random() * 500
local renderConn = RunService.RenderStepped:Connect(function()
	if not camDriven or not camCF then return end
	local c = Workspace.CurrentCamera
	if not c then return end
	c.CameraType = Enum.CameraType.Scriptable
	if tremor > 0 then
		local t = os.clock() * 9
		c.CFrame = camCF * CFrame.Angles(
			math.noise(t, tremorSeed) * 0.030 * tremor,
			math.noise(t, tremorSeed + 31) * 0.030 * tremor,
			math.noise(t * 0.6, tremorSeed + 77) * 0.022 * tremor)
	else
		c.CFrame = camCF
	end
end)

local restored = false
local function restore()
	if restored then return end
	restored = true
	embersOn = false
	if guiAdded then guiAdded:Disconnect() end
	if renderConn then renderConn:Disconnect() end
	pcall(function()
		local c = Workspace.CurrentCamera
		if c then
			c.CameraType = Enum.CameraType.Custom
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then c.CameraSubject = hum end
			c.FieldOfView = origFov
		end
	end)
	if anchoredHRP then pcall(function() anchoredHRP.Anchored = false end) end
	pcall(function() blur:Destroy() end)
	pcall(function() cc:Destroy() end)
	pcall(function() roar:Stop(); roarFar:Stop(); footstep:Stop() end)
	-- The ambience is the one thing that OUTLIVES the shot: it keeps playing under normal play, because
	-- a jungle that goes silent the moment the cinematic ends would be its own kind of seam.
	for sg, was in pairs(hidden) do pcall(function() sg.Enabled = was end) end
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
	pcall(function() StarterGui:SetCore("TopbarEnabled", true) end)
	pcall(function() gui:Destroy() end)
end
task.delay(MASTER_TIMEOUT, restore) -- hard backstop

-- A footstep: thud, kick, amber flicker. Each one is bigger and lower than the last.
local function stomp(strength)
	pcall(function()
		footstep.PlaybackSpeed = 0.75 - strength * 0.2 -- lower = bigger animal
		footstep.Volume = 0.5 + strength * 0.5
		footstep.TimePosition = 0
		footstep:Play()
	end)
	pcall(function()
		wash.BackgroundTransparency = 1 - 0.18 * strength
		TweenService:Create(wash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		-- The card itself kicks: a few pixels down and back, harder each step.
		local dy = 6 + 10 * strength
		card.Position = UDim2.new(0.5, 0, 0.5, 16 + dy)
		kicker.Position = UDim2.new(0.5, 0, 0.5, -78 + dy * 0.6)
		TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0.5, 16) }):Play()
		TweenService:Create(kicker, TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0.5, -78) }):Play()
	end)
	-- Dust off the floor, more of it the closer the thing is. The card kick says the CAMERA was hit; the
	-- dust says the GROUND was.
	puff(math.floor(4 + strength * 12))
end

-- The third step's shadow crossing the screen. One pass, left to right, fading in as it enters and out as
-- it leaves, so nothing ever shows a hard edge arriving or a hard edge parking.
local function sweepShadow(secs)
	pcall(function()
		shadow.Position = UDim2.new(-0.5, 0, 0.5, 0)
		shadow.BackgroundTransparency = 0
		TweenService:Create(shadow, TweenInfo.new(secs, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Position = UDim2.new(1.5, 0, 0.5, 0),
		}):Play()
		-- The card dims under it: the shadow is between the player and whatever is lighting the title.
		TweenService:Create(card, TweenInfo.new(secs * 0.4), { TextTransparency = 0.55 }):Play()
		task.delay(secs * 0.5, function()
			pcall(function() TweenService:Create(card, TweenInfo.new(secs * 0.5), { TextTransparency = 0 }):Play() end)
		end)
		task.delay(secs, function() pcall(function() shadow.BackgroundTransparency = 1 end) end)
	end)
end

-- Drive the eyelids to `target` (0 shut, 1 open) over `secs`. A manual loop rather than a tween because
-- the lids are TWO frames driven off one number, and because every beat in this file has to be able to
-- bail the moment `restored` flips.
local function lidTo(target, secs, style, dir)
	local from = lidA
	local t0 = os.clock()
	while not restored and (os.clock() - t0) < secs do
		local a = (os.clock() - t0) / secs
		lidA = from + (target - from) * TweenService:GetValue(a, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
		applyLids()
		task.wait()
	end
	if restored then return end
	lidA = target
	applyLids()
end

-- Types `text` into the readout over `secs`, with a blinking block cursor.
local function typeOut(text, secs)
	local n = #text
	local t0 = os.clock()
	while not restored and (os.clock() - t0) < secs do
		local k = math.floor(n * ((os.clock() - t0) / secs))
		local cursor = (math.floor(os.clock() * 6) % 2 == 0) and "\u{2588}" or " "
		readout.Text = text:sub(1, k) .. cursor
		task.wait()
	end
	readout.Text = text
end

-- ======================================================================
-- THE WAKE-UP
-- ======================================================================
task.spawn(function()
	local ok, err = pcall(function()
		-- Let the world actually stream in before we reveal it. Revealing a half-loaded jungle is worse
		-- than holding the card a beat longer, so we wait on the character AND give streaming a moment.
		-- The LISTEN beat below is that streaming budget: two seconds of ambience on the card.
		local char = player.Character or player.CharacterAdded:Wait()
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if hrp then anchoredHRP = hrp; pcall(function() hrp.Anchored = true end) end
		pcall(function() player:RequestStreamAroundAsync(char:GetPivot().Position) end)

		-- ============ LISTEN (2.0s) — sound arrives before sight ============
		pcall(function() ambience:Play() end)
		pcall(function() TweenService:Create(ambience, TweenInfo.new(3.0, Enum.EasingStyle.Sine), { Volume = 0.55 }):Play() end)
		task.wait(2.0)
		if restored then return end

		-- ============ SOMETHING (2.7s) — three footsteps, a shadow crossing, then the roar ============
		stomp(0.35); task.wait(0.85)
		if restored then return end
		stomp(0.65); task.wait(0.75)
		if restored then return end
		-- THE THIRD STEP IS THE CLOSE ONE. It lands and the thing that made it crosses the screen: the
		-- sweep runs UNDER the wait, so the roar arrives while the shadow is still leaving frame rather
		-- than after it has tidily gone.
		stomp(1.0)
		sweepShadow(0.95)
		task.wait(0.72)
		if restored then return end

		-- THE ROAR. The whole card flashes amber and the ambience ducks under it — the birds stop.
		pcall(function()
			roar.TimePosition = 0
			roar:Play()
			TweenService:Create(ambience, TweenInfo.new(0.15), { Volume = 0.12 }):Play()
			wash.BackgroundTransparency = 0.25
			TweenService:Create(wash, TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
			card.TextColor3 = AMBER
			TweenService:Create(card, TweenInfo.new(0.9), { TextColor3 = BONE }):Play()
		end)
		-- A shake on the card, decaying, for the length of the roar's front.
		local t0 = os.clock()
		while not restored and (os.clock() - t0) < 0.4 do
			local m = 1 - (os.clock() - t0) / 0.4
			card.Position = UDim2.new(0.5, (math.random() - 0.5) * 22 * m, 0.5, 16 + (math.random() - 0.5) * 14 * m)
			task.wait()
		end
		card.Position = UDim2.new(0.5, 0, 0.5, 16)
		if restored then return end

		-- ============ EYES OPEN (4.2s) — the reveal ============
		-- Camera: from the ground at the player's feet, tilting UP to their normal view. We take the
		-- camera over only now, so that a direct-join or an early restore never sees a Scriptable camera.
		local head = char:FindFirstChild("Head")
		local eye = (head and head.Position or (hrp and hrp.Position or Vector3.new())) + Vector3.new(0, 0.5, 0)
		local fwd = hrp and hrp.CFrame.LookVector or Vector3.new(0, 0, -1)
		local fromCF = CFrame.lookAt(eye, eye + Vector3.new(0, -1, 0) + fwd * 0.15) -- looking at the floor
		-- WHERE WE HAND IT BACK MATTERS. The shot used to end 9 studs behind the player and 3.5 up, which
		-- is not where Roblox's Custom camera lives (its default zoom is 12.5), so the last thing the
		-- transition did was JUMP as control changed hands. Ending at the default framing means the switch
		-- to Custom is invisible — the player takes over the exact camera they were watching.
		local toCF = CFrame.lookAt(eye - fwd * 12.5 + Vector3.new(0, 3.2, 0), eye + fwd * 4)
		camCF = fromCF
		camDriven = true
		tremor = 1.0 -- the floor is still moving; decays to nothing across the reveal below
		if cam then cam.FieldOfView = 88 end

		pcall(function()
			TweenService:Create(kicker, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { TextTransparency = 1 }):Play()
			TweenService:Create(rule,   TweenInfo.new(0.8, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(card,   TweenInfo.new(1.0, Enum.EasingStyle.Quad), { TextTransparency = 1 }):Play()
		end)
		task.wait(0.6)
		if restored then return end
		embersOn = false
		pcall(function()
			TweenService:Create(ground, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(blur,   TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Size = 0 }):Play()
			TweenService:Create(ambience, TweenInfo.new(2.0), { Volume = 0.45 }):Play()
			TweenService:Create(readout, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
			-- The grade: arrive slightly amber and warm, and settle to neutral as the eyes adjust.
			cc.TintColor = Color3.fromRGB(255, 214, 170); cc.Saturation = -0.3; cc.Brightness = 0.12
			TweenService:Create(cc, TweenInfo.new(3.0, Enum.EasingStyle.Sine), { TintColor = Color3.new(1, 1, 1), Saturation = 0, Brightness = 0 }):Play()
		end)
		task.spawn(typeOut, "ICE CORE SAMPLE 8  \u{00B7}  DNA MATCH: THEROPODA", 2.2)

		-- THE LIDS CLOSE HERE, not when the camera was taken. At this instant the ground is still opaque
		-- and the lids are black, so shutting them is invisible — and everything that follows opens onto a
		-- picture that has already been revealed underneath. Closing them any earlier would black out the
		-- card while it is still fading, and the card and the ground are meant to clear together.
		lidA = 0; applyLids()
		lidTop.BackgroundTransparency = 0; lidBot.BackgroundTransparency = 0

		-- ===== THE BLINK =====
		-- Open, snap shut, open wider, flutter, stay open. Two things make it read as an eye rather than a
		-- shutter: the closes are much FASTER than the opens (a lid drops and is dragged back up), and each
		-- close spikes the blur, because a closing eye defocuses before it darkens. It runs in parallel
		-- with the camera move below — waking up is one motion, not a sequence of two.
		task.spawn(function()
			lidTo(0.38, 0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.wait(0.10)
			pcall(function() TweenService:Create(blur, TweenInfo.new(0.14), { Size = 20 }):Play() end)
			lidTo(0.04, 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			pcall(function() TweenService:Create(blur, TweenInfo.new(0.5), { Size = 6 }):Play() end)
			lidTo(0.78, 0.40, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			task.wait(0.16)
			pcall(function() TweenService:Create(blur, TweenInfo.new(0.10), { Size = 12 }):Play() end)
			lidTo(0.34, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			pcall(function() TweenService:Create(blur, TweenInfo.new(1.2, Enum.EasingStyle.Sine), { Size = 0 }):Play() end)
			lidTo(1.0, 0.80, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			lidTop.BackgroundTransparency = 1
			lidBot.BackgroundTransparency = 1
		end)

		-- THE ANSWER, from somewhere in the trees, as the readout lands. The first roar was the thing that
		-- walked past you; this one is the world telling you it was not the only one.
		task.delay(2.45, function()
			if restored then return end
			pcall(function() roarFar.PlaybackSpeed = 0.72; roarFar.TimePosition = 0; roarFar:Play() end)
			pcall(function()
				TweenService:Create(ambience, TweenInfo.new(0.4), { Volume = 0.2 }):Play()
				task.delay(1.6, function()
					pcall(function() TweenService:Create(ambience, TweenInfo.new(2.0), { Volume = 0.45 }):Play() end)
				end)
			end)
		end)

		t0 = os.clock()
		local T_OPEN = 3.6
		while not restored and (os.clock() - t0) < T_OPEN do
			local a = (os.clock() - t0) / T_OPEN
			local e = TweenService:GetValue(a, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			camCF = fromCF:Lerp(toCF, e)
			tremor = (1 - a) ^ 2.2 -- dies out under the move: still shaking at the start, dead by the end
			if cam then cam.FieldOfView = 88 - e * (88 - origFov) end
			task.wait()
		end
		if restored then return end
		tremor = 0

		-- ============ HANDBACK (1.4s) ============
		-- A held beat on the settled framing BEFORE the readout starts to go. The shot has been moving
		-- since the rift; letting it be still for a third of a second is what turns "the cinematic
		-- stopped" into "you are here now".
		camCF = toCF
		task.wait(0.35)
		pcall(function() TweenService:Create(readout, TweenInfo.new(0.6), { TextTransparency = 1 }):Play() end)
		task.wait(0.7)
		camDriven = false
	end)
	if not ok then warn("[DinoArrival] " .. tostring(err)) end
	restore()
end)

print("[DinoArrival] arrived through the rift — continuing the transition (card handoff, footsteps + dust, " ..
	"a shadow the size of a house crossing the screen, the roar, then a BLINK-open reveal with the floor still " ..
	"trembling and an answering roar in the trees). Ends on Roblox's default framing so the handback does not jump.")
