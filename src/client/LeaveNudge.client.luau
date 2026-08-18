--======================================================================
-- LeaveNudge.client.luau  (LocalScript)
--======================================================================
-- "Wait! A FREE crate is waiting for you." Shown the moment the player presses the Roblox button to leave.
-- Ported from the Space Realm.
--
-- ===== WHY THIS HOOK, AND NOT THE LEAVE DIALOG ITSELF =====
-- Roblox exposes no API to put custom text on its own "Are you sure you want to leave?" dialog -- neither
-- GuiService nor StarterGui:SetCore has a member for it. GuiService.MenuOpened, though, fires exactly when
-- the player presses that button, which is the supported moment to surface something of our own. Roblox
-- still owns the menu and its Leave / Resume buttons; this only adds a banner beside them.
--
-- The Roblox menu is CoreGui and draws ABOVE PlayerGui, so the banner cannot cover it -- which is why it is
-- also held on screen for a few seconds AFTER the menu closes. That is when it actually gets read: as the
-- player comes back and decides whether to stay.
--
-- ===== THE SERVER DECIDES, ALWAYS =====
-- Pressing leave asks the server; only an `ok` answer shows anything. On cooldown, or already holding a
-- claimable crate, the answer is no and the player sees NOTHING -- no banner, no sound -- and leaves
-- normally. Nagging someone with an offer that is not real is worse than not asking.
--
-- ===== ALL PLATFORMS, NOT JUST PHONES =====
-- Space gates this to phones. Here it runs everywhere: the Roblox button is the leave path on every
-- platform, the server enforces the 24h cooldown regardless of how many times the menu is opened, and a
-- desktop player pressing Esc to leave is exactly as worth keeping as a phone player tapping the button.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local ContentProvider   = game:GetService("ContentProvider")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

if _G.__LeaveNudgeClient then
	warn("[Retention] a SECOND leave nudge is running -- this one is bailing out.")
	return
end
_G.__LeaveNudgeClient = true

local MESSAGE = "Wait! A FREE crate is waiting for you \xE2\x80\x94 stay and grab it! \xF0\x9F\x8E\x81"

-- house palette
local BLUE   = Color3.fromRGB(30, 140, 255)
local BLUE_D = Color3.fromRGB(18, 92, 190)
local GOLD   = Color3.fromRGB(255, 206, 92)
local CREAM  = Color3.fromRGB(255, 250, 236)
local INK    = Color3.fromRGB(16, 44, 96)

local RequestStayReward = ReplicatedStorage:WaitForChild("RequestStayReward", 30)
if not RequestStayReward then
	warn("[Retention] RequestStayReward never arrived -- leave nudge inactive")
	return
end

--======================================================================
-- THE ALERT SOUND
--======================================================================
-- Its OWN SoundGroup, deliberately. SettingsClient routes groupless Sounds into the SFX group that the
-- in-game volume slider controls, and leaves foreign groups alone -- so putting this in its own group is what
-- keeps it audible for a player who has turned effects down. This is the one sound in the game that has to
-- land, because it fires at the exact moment they have stopped looking at the screen.
local LEAVE_SOUND_ID = "rbxassetid://109963399580326"
local loudGroup = SoundService:FindFirstChild("RetentionLoudGroup")
if not (loudGroup and loudGroup:IsA("SoundGroup")) then
	loudGroup = Instance.new("SoundGroup")
	loudGroup.Name = "RetentionLoudGroup"
	loudGroup.Volume = 1
	loudGroup.Parent = SoundService
end

local leaveSound = Instance.new("Sound")
leaveSound.Name = "LeaveAlert"
leaveSound.SoundId = LEAVE_SOUND_ID
leaveSound.Volume = 1.8
leaveSound.SoundGroup = loudGroup   -- set BEFORE parenting, so SettingsClient sees a foreign group and skips it
leaveSound.Parent = SoundService

-- Preloaded so the first play -- which is the only one that matters -- has no fetch delay.
task.spawn(function() pcall(function() ContentProvider:PreloadAsync({ leaveSound }) end) end)

--======================================================================
-- THE BANNER
--======================================================================
local function corner(g, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = g end
local function stroke(g, col, th)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = g
end

local gui = Instance.new("ScreenGui")
gui.Name = "LeaveNudgeGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 250          -- top of PlayerGui (still under the Roblox menu, which cannot be drawn over)
gui.Enabled = false
gui.Parent = PlayerGui

local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 24)
banner.Size = UDim2.new(0.92, 0, 0, 88)
banner.BackgroundColor3 = BLUE
banner.BorderSizePixel = 0
banner.Parent = gui
corner(banner, 16); stroke(banner, GOLD, 3)
do local sc = Instance.new("UISizeConstraint"); sc.MaxSize = Vector2.new(520, 96); sc.Parent = banner end
do
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(BLUE, BLUE_D)
	g.Rotation = 90
	g.Parent = banner
end

local gift = Instance.new("TextLabel")
gift.BackgroundTransparency = 1
gift.AnchorPoint = Vector2.new(0, 0.5)
gift.Position = UDim2.new(0, 14, 0.5, 0)
gift.Size = UDim2.fromOffset(56, 56)
gift.Font = Enum.Font.FredokaOne
gift.TextSize = 40
gift.Text = "\xF0\x9F\x8E\x81"
gift.Parent = banner

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.AnchorPoint = Vector2.new(0, 0.5)
label.Position = UDim2.new(0, 78, 0.5, 0)
label.Size = UDim2.new(1, -94, 1, -16)
label.Font = Enum.Font.FredokaOne
label.Text = MESSAGE
label.TextColor3 = CREAM
label.TextScaled = true
label.TextWrapped = true
label.Parent = banner
do
	-- TextScaled alone lets a short string balloon; the constraint makes 24 a CEILING so a long one steps
	-- down to fit instead of clipping.
	local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 24; c.MinTextSize = 12; c.Parent = label
	local s = Instance.new("UIStroke"); s.Color = INK; s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; s.Parent = label
end

local scale = Instance.new("UIScale"); scale.Scale = 1; scale.Parent = banner

--======================================================================
-- SHOW / HIDE
--======================================================================
-- hideToken invalidates any pending hide, so a second MenuOpened while the banner is already up cannot let an
-- older timer pull it off screen early.
local hideToken = 0

local function show()
	hideToken += 1
	gui.Enabled = true
	scale.Scale = 0.7
	pcall(function()
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
	end)
	pcall(function() leaveSound.TimePosition = 0; leaveSound:Play() end)
end

local function hideAfter(seconds)
	hideToken += 1
	local mine = hideToken
	task.delay(seconds, function()
		if mine == hideToken then gui.Enabled = false end
	end)
end

--======================================================================
-- THE LEAVE ATTEMPT
--======================================================================
local asking = false
GuiService.MenuOpened:Connect(function()
	if asking then return end   -- one question per menu open; the server would refuse anyway
	asking = true
	task.spawn(function()
		local ok, res = pcall(function() return RequestStayReward:InvokeServer() end)
		asking = false
		if ok and type(res) == "table" and res.ok then
			show()
		end
		-- Not eligible (cooldown, or their crate was already claimable): show nothing at all and let them go.
	end)
end)

-- Held past the close, not hidden on it: the Roblox menu covers this banner while it is open, so the seconds
-- AFTER they dismiss it are the only ones where the offer is actually readable.
GuiService.MenuClosed:Connect(function() hideAfter(5) end)

print("[Retention] leave nudge ready -- pressing the Roblox button offers a free daily crate "
	.. "(server-validated, 24h cooldown, all platforms)")
