--======================================================================
-- ArrivalCinematic.client.luau  (StarterPlayerScripts)   [RECEIVING PLACE -- the CANDY REALM]
--======================================================================
--[[
	The far half of the seam, the near half being the portal cinematic in the Food Realm.

	The sending realm's portal ends on a FULL BLACK SCREEN and holds there while the teleport fires. This
	script opens the Candy Realm on that SAME black -- so the place boundary is hidden inside the
	transition. Without this file the player gets: portal -> black -> *Roblox loading screen* -> hard cut
	to a candy island. With it, they get one continuous shot.

	THE ONE RULE: put the black up on the FIRST frame, before anything else. If the world renders even
	briefly before we cover it, the illusion is dead. So we check the teleport data SYNCHRONOUSLY at the
	top of the file and build the cover immediately -- no WaitForChild, no yielding, first.

	WHY WE READ TELEPORT DATA ON THE CLIENT HERE:
	TeleportService:GetLocalPlayerTeleportData() is client-readable and therefore SPOOFABLE -- which is
	completely fine, because everything in this file is COSMETIC. The worst an exploiter can do is give
	themselves a fade-in. Anything that MATTERS (pets, coins, progress, entry rights) is read server-side
	from player:GetJoinData() in RealmServer.server.luau, which cannot be faked. Never mix the two up.
]]
--======================================================================
-- HOW THIS ENDS: WE HAND OFF TO THE TOWER INTRO.
--======================================================================
-- Intro.client.luau's descent cinematic is the opening of this realm, and a portal arrival gets it too.
-- But the two CANNOT run at the same time: both hide every ScreenGui, both seize the CoreGui, and both
-- anchor the HumanoidRootPart. So they run in sequence, and this script drives the join:
--
--   1. we hold the black and finish the card ("SOMEWHERE SWEETER" / "THE CANDY REALM")
--   2. we put the HUD's ScreenGuis back to their real Enabled states -- see restoreGuis() for why this
--      is not optional -- and fire IntroRequest
--   3. Intro.server fires IntroPlay; Intro.client takes the camera
--   4. the moment the descent is actually DRIVING the camera, we CUT the black away
--
-- We cut rather than fade, because the intro opens on a hard slam onto Bakery Summit, and a cut is
-- exactly what a slam wants. Black -> SLAM. That is the whole trick.
--
-- If no intro comes back (it failed, or the remote is missing), we fall through to our OWN reveal -- a
-- slow fade up out of the black. Nobody is ever stranded on black.
--======================================================================

local Players           = game:GetService("Players")
local TeleportService   = game:GetService("TeleportService")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local StarterGui        = game:GetService("StarterGui")
local Lighting          = game:GetService("Lighting")
local Debris            = game:GetService("Debris")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ---- Did we arrive through a portal? (cosmetic only -- see the header) ----
--
-- ANY teleport data means we came from inside the universe, which is the same test RealmServer's entry
-- guard uses and for the same reason: keying on one specific flag would break the day another realm
-- starts sending players here. A direct join from the Roblox site has no data and gets no black screen.
local data
pcall(function() data = TeleportService:GetLocalPlayerTeleportData() end)
if type(data) ~= "table" then
	-- Joined the Candy Realm directly (or the payload was lost). No transition to continue -- just let
	-- them into the world normally. Do NOT black their screen out.
	-- (Intro.client.luau still gives them the tower descent on its own timer, exactly as before.)
	print("[CandyArrival] direct join -- no portal transition to continue")
	return
end

--======================================================================
-- SOUND
--======================================================================
-- Each cue is a LIST so one dead asset can't silence it. The lead ids are ones already proven to load in
-- THIS place (EggSystem/PetFollow use both), rather than ids copied from another realm and hoped for.
-- 112825313814792 was here as a second entry and is REMOVED -- this place is not authorised to use it
-- ("User is not authorized to access Asset"), so it could never have played; it only added a console nag.
local CHIME_IDS = { "92880640988467" } -- pitched DOWN -- reads as a big, distant bell

-- ⚠ EMPTY ON PURPOSE, and the single best thing you could fix here. There is no working ambience asset
-- anywhere in this project -- Intro.client.luau's SFX.bed is empty for exactly the same reason. Paste a
-- soft music-box or wind-chime loop id in here and the arrival gains its strongest layer: sound arriving
-- before sight, so you HEAR where you are a full second before you SEE it.
local AMBIENCE_IDS = {}

local function playFirst(ids, vol, speed, looped)
	for _, id in ipairs(ids) do
		local ok, snd = pcall(function()
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. id
			s.Volume = vol
			s.PlaybackSpeed = speed or 1
			s.Looped = looped or false
			s.Parent = SoundService
			s:Play()
			return s
		end)
		if ok and snd then return snd end
	end
	return nil
end

local SUGAR = Color3.fromRGB(255, 236, 246)
local MINT  = Color3.fromRGB(150, 230, 210)

-- ======================================================================
-- FIRST FRAME: cover everything in black, carrying the card across the boundary.
-- ======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "CandyArrivalCinematic"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
gui.DisplayOrder = 10000
gui.Parent = PlayerGui

--======================================================================
-- FULL-BLEED GROUND -- and it MATCHES the outro it is catching
--======================================================================
-- This was flat pure black, edge to edge. That was right when the OUTRO on the other side of the teleport
-- was also flat black -- the point of this card is that it looks like the same frame surviving a place
-- boundary. The outro is now a realm-tinted vertical gradient filling the whole viewport (see
-- RealmPortals.client.luau), so pure black here would land as a colour pop on arrival: the exact seam this
-- pass exists to remove, just moved to the other end of the transition.
--
-- So it carries the same ground: the realm accent laid over black at the same three stops, vertical, whole
-- screen, no shape and no offset height anywhere. The ScreenGui above is IgnoreGuiInset = true and this
-- frame is parented straight to it, so it covers the true viewport on phone, desktop and ultrawide alike.
local CANDY_ACCENT = Color3.fromRGB(232, 104, 172) -- RealmPortals' Candy `lightA` -- keep the two in step

local black = Instance.new("Frame")
black.Size = UDim2.fromScale(1, 1)
black.Position = UDim2.fromScale(0, 0)
black.AnchorPoint = Vector2.new(0, 0)
black.BackgroundColor3 = CANDY_ACCENT:Lerp(Color3.new(0, 0, 0), 0.94)
black.BackgroundTransparency = 0 -- OPAQUE from frame one -- this is the handoff
black.BorderSizePixel = 0
black.ZIndex = 1
black.Parent = gui
do
	local bg = Instance.new("UIGradient")
	local deep = CANDY_ACCENT:Lerp(Color3.new(0, 0, 0), 0.975)
	local mid  = CANDY_ACCENT:Lerp(Color3.new(0, 0, 0), 0.90)
	bg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, deep),
		ColorSequenceKeypoint.new(0.5, mid),
		ColorSequenceKeypoint.new(1, deep),
	})
	bg.Rotation = 90 -- top to bottom, across the FULL height: a gradient, not a band with ends
	bg.Parent = black
end

-- The title card, still up. To the player it never went away -- it simply persisted across a place
-- boundary, which is exactly the feeling we want.
local card = Instance.new("TextLabel")
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.new(0.5, 0, 0.5, 0)
card.Size = UDim2.new(0.9, 0, 0, 90)
card.BackgroundTransparency = 1
card.Font = Enum.Font.FredokaOne
card.TextScaled = true
card.TextColor3 = SUGAR
card.TextTransparency = 0
card.Text = "SOMEWHERE SWEETER"
card.ZIndex = 2
card.Parent = gui
do local c = Instance.new("UITextSizeConstraint", card); c.MaxTextSize = 58 end

local sub = Instance.new("TextLabel")
sub.AnchorPoint = Vector2.new(0.5, 0)
sub.Position = UDim2.new(0.5, 0, 0.5, 56)
sub.Size = UDim2.new(0.8, 0, 0, 34)
sub.BackgroundTransparency = 1
sub.Font = Enum.Font.FredokaOne
sub.TextScaled = true
sub.TextColor3 = MINT
sub.TextTransparency = 1
sub.Text = "THE CANDY REALM"
sub.ZIndex = 2
sub.Parent = gui
do local c = Instance.new("UITextSizeConstraint", sub); c.MaxTextSize = 26 end

-- Hide the HUD while we're black (toggle .Enabled, never destroy -- put back by restoreGuis).
local hidden = {}
local guiAdded
local function hideOne(child)
	if child == gui or not child:IsA("ScreenGui") then return end
	if hidden[child] == nil then hidden[child] = child.Enabled; child.Enabled = false end
end
for _, c in ipairs(PlayerGui:GetChildren()) do hideOne(c) end
guiAdded = PlayerGui.ChildAdded:Connect(hideOne)
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
pcall(function() StarterGui:SetCore("TopbarEnabled", false) end)

local blur = Instance.new("BlurEffect")
blur.Size = 28
blur.Parent = Lighting

-- Put every ScreenGui back to the Enabled state it REALLY had, and stop hiding new ones.
--
-- This has to happen BEFORE Intro.client starts, and it is not optional. The intro hides the GUIs itself,
-- capturing each one's current Enabled into its own restore table -- so if it starts while ours are still
-- forced to false, it captures FALSE, and "restores" the player's HUD to hidden when the title card ends.
-- They'd come out of the cinematic with no HUD at all.
--
-- The ChildAdded hook has to go for the same reason: it would disable the intro's OWN cinema GUI (the
-- island chip, the altitude readout, the cut flash) the instant it was created.
--
-- Doing this under the black costs nothing visually -- our black is DisplayOrder 10000, so everything we
-- just re-enabled is still behind it.
local function restoreGuis()
	if guiAdded then guiAdded:Disconnect(); guiAdded = nil end
	for sg, was in pairs(hidden) do pcall(function() sg.Enabled = was end) end
	hidden = {}
end

local finished = false

-- Full teardown: we did the reveal ourselves, so we own putting everything back.
local function restore()
	if finished then return end
	finished = true
	restoreGuis()
	pcall(function() blur:Destroy() end)
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
	pcall(function() StarterGui:SetCore("TopbarEnabled", true) end)
	pcall(function() gui:Destroy() end)
end

-- Teardown when the INTRO is taking over instead. Deliberately does NOT touch the CoreGui: the intro has
-- already turned it off, and its own restore() turns it back on when the title card is done. Re-enabling
-- it here would pop the Roblox topbar up in the middle of the cinematic.
local function handOff()
	if finished then return end
	finished = true
	restoreGuis()
	pcall(function() blur:Destroy() end)
	pcall(function() gui:Destroy() end)
end

-- Hard backstop: never strand a player on a black screen. If the intro is running, it owns the screen and
-- its own restore() will clean up -- all we do is make sure our black is gone.
--
-- It has to sit BEYOND the worst-case handoff (~4s of card + up to 15s waiting for the intro to come back
-- + up to 15s waiting for its camera to move), or it would tear the black down while we were still
-- legitimately waiting for the intro.
task.delay(45, function()
	if _G.introPlaying then handOff() else restore() end
end)

--======================================================================
-- THE HANDOFF: ask for the tower intro, and wait until it's really running.
-- Returns true if the intro took over (so we must NOT do our own reveal).
--======================================================================
local function handOffToIntro(): boolean
	local req = ReplicatedStorage:FindFirstChild("IntroRequest")
	if not req then
		warn("[CandyArrival] no IntroRequest remote -> revealing the world myself")
		return false
	end

	restoreGuis() -- MUST be before the intro starts. See restoreGuis().
	pcall(function() req:FireServer() end)

	-- Wait for the intro to actually come back.
	--
	-- Be PATIENT here. We can easily beat the server to this point -- it's still waiting on our character
	-- to replicate, and on a live server that is not instant. Holding the black a few extra seconds costs
	-- nothing (the card is up; the player is looking at a title, not at a bug). Giving up too early is what
	-- actually hurts: we'd reveal the world, and then the intro would slam in on top of the player a
	-- moment later.
	local t0 = os.clock()
	while not _G.introPlaying and os.clock() - t0 < 15 do task.wait(0.1) end
	if not _G.introPlaying then
		print("[CandyArrival] no intro came back -> revealing the world myself")
		return false
	end

	-- Now HOLD THE BLACK until the descent is actually driving the camera.
	--
	-- _G.introPlaying alone is not enough to cut on. The intro sets it and then YIELDS -- it preloads its
	-- sounds and streams in Bakery Summit, which can take seconds. It also sets the camera to Scriptable
	-- BEFORE that yield, so even "the camera is Scriptable" would cut us to a frozen shot of the spawn
	-- point and hold it there.
	--
	-- So we wait for the camera to actually MOVE. That only happens once the first shot's frame loop is
	-- running, which is exactly the moment we want to cut on: the slam.
	local base = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame
	local t1 = os.clock()
	while os.clock() - t1 < 15 do
		local cam = Workspace.CurrentCamera
		if cam and base and cam.CameraType == Enum.CameraType.Scriptable
			and (cam.CFrame.Position - base.Position).Magnitude > 5 then
			break -- the descent has the camera. CUT.
		end
		RunService.RenderStepped:Wait()
	end
	return true
end

-- ======================================================================
-- THE ARRIVAL
-- ======================================================================
task.spawn(function()
	local ok, err = pcall(function()
		-- Let the world actually stream in before anything is revealed. We wait on the character AND give
		-- streaming a moment.
		local char = player.Character or player.CharacterAdded:Wait()
		char:WaitForChild("HumanoidRootPart", 10)
		pcall(function() player:RequestStreamAroundAsync(char:GetPivot().Position) end)
		task.wait(1.0) -- the card breathes here; this is also our streaming budget

		-- Ambience creeps IN while we're still black -- sound arrives before sight, which is what makes
		-- the reveal land. (Silent until you put an id in AMBIENCE_IDS. See the note up top.)
		local amb = playFirst(AMBIENCE_IDS, 0, 1, true)
		if amb then
			pcall(function() TweenService:Create(amb, TweenInfo.new(3.5), { Volume = 0.5 }):Play() end)
		else
			print("[CandyArrival] no ambience id configured (AMBIENCE_IDS is empty) -> revealing without it")
		end

		pcall(function() TweenService:Create(sub, TweenInfo.new(0.6), { TextTransparency = 0 }):Play() end)
		task.wait(1.4)

		-- A far-off chime, still on black. Something sweet out there knows you arrived.
		local c = playFirst(CHIME_IDS, 0.55, 0.6) -- pitched down = big, and far away
		if c then Debris:AddItem(c, 6) end
		task.wait(0.9)

		-- ---- Card out, and hand the black to the intro ----
		pcall(function()
			TweenService:Create(card, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { TextTransparency = 1 }):Play()
			TweenService:Create(sub,  TweenInfo.new(0.7, Enum.EasingStyle.Quad), { TextTransparency = 1 }):Play()
		end)
		task.wait(0.8)

		if handOffToIntro() then
			-- The descent has the camera and is mid-slam. Cut, don't fade.
			handOff()
			print("[CandyArrival] handed off to the tower intro")
			return
		end

		-- ---- No intro. Do the reveal ourselves: slow, like eyes opening. ----
		pcall(function()
			TweenService:Create(black, TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ BackgroundTransparency = 1 }):Play()
			TweenService:Create(blur, TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Size = 0 }):Play()
		end)
		task.wait(2.5)
		restore()
	end)
	if not ok then
		warn("[CandyArrival] " .. tostring(err))
		restore() -- an error must never leave them on a black screen
	end
end)

print("[CandyArrival] arrived through a portal -- continuing the transition")
print("[Transition] CandyArrivalCinematic UPDATED to the full-bleed ground: fromScale(1,1) at fromScale(0,0), " ..
	"IgnoreGuiInset=true, vertical candy-pink gradient across the whole viewport. No plain-black fill, no band, " ..
	"no seam against the RealmPortals outro it catches.")
