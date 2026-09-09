-- ============================================================================================================
-- GNOME HOME MENU -- the panel a key holder gets at the secret tree door.
--
-- WHY IT EXISTS: the door used to carry TWO ProximityPrompts, E to knock and F to go inside. Roblox shows one
-- prompt per part at a time, so the second may as well not have existed. One prompt now opens this, and the
-- panel asks the question in words.
--
-- IT ONLY EVER APPEARS FOR A KEY HOLDER, AND ONLY WHEN THE SERVER SAYS SO. SecretTreeDoor checks its own
-- DataStore-backed key list, checks you are stood at the door, and only then fires us with "open". This script
-- never checks, never assumes, never opens itself. A button press sends back one word, and the server
-- re-checks the key AND the distance before acting on it.
--
-- ===== IT IS THE SAME OBJECT AS EVERY OTHER MENU =====
-- Copied from DailyTasks, which is itself copied from the Shop, so this is not a new look -- it is the house
-- look: 700x520, dark navy panel, UICorner 16, gold stroke, a 78px header with a GothamBlack 28 gold title,
-- a GothamMedium 14 subtitle, and the red FredokaOne "X" close button at 40x40. DisplayOrder 100 like the
-- Shop and Stomach menus, so it sits definitively above the HUD.
--
-- AND IT IS SIMPLE: a header, two rows, a footer. The previous version had hand-drawn gnome and door icons
-- built out of a dozen Frames each -- clever, and completely out of step with every other panel in the game,
-- which is plain rows of text on flat cards. Rows it is.
-- ============================================================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("GnomeHomeMenu", 30)
if not remote then
	warn("[GnomeHomeMenu] no GnomeHomeMenu remote -- SecretTreeDoor did not start. Panel disabled.")
	return
end

-- The DailyTasks palette, value for value.
local CARD    = Color3.fromRGB(32, 38, 58)
local GREEN   = Color3.fromRGB(110, 226, 140)
local GOLD    = Color3.fromRGB(255, 205, 70)
local GOLD_DK = Color3.fromRGB(196, 148, 34)
local TXT     = Color3.fromRGB(236, 240, 248)
local TXT_DIM = Color3.fromRGB(132, 143, 166)

local screen = Instance.new("ScreenGui")
screen.Name           = "GnomeHomeMenuGui"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true
screen.DisplayOrder   = 100
screen.Enabled        = false
screen.Parent         = player:WaitForChild("PlayerGui")

-- NO BACKDROP OF ITS OWN. Closing on an outside click is handled once, game-wide, by ClickOutside --
-- which insets its invisible catcher away from the live HUD, so pressing a HUD button presses the
-- button instead of slamming the panel shut. The full-screen 0.45-dim TextButton that used to sit
-- here did neither: it tinted the whole screen and swallowed every HUD press behind it.

local panel = Instance.new("Frame")
panel.AnchorPoint      = Vector2.new(0.5, 0.5)
panel.Position         = UDim2.fromScale(0.5, 0.5)
panel.Size             = UDim2.new(0, 700, 0, 520)   -- matches the Shop exactly
panel.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
panel.BorderSizePixel  = 0
panel.Parent           = screen
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
local pstroke = Instance.new("UIStroke", panel)
pstroke.Color = GOLD_DK; pstroke.Thickness = 3
local pgrad = Instance.new("UIGradient", panel)
pgrad.Rotation = 90
pgrad.Color    = ColorSequence.new(Color3.fromRGB(30, 36, 56), Color3.fromRGB(16, 19, 30))

-- ===== HEADER =====
local head = Instance.new("Frame")
head.Size             = UDim2.new(1, 0, 0, 78)
head.BackgroundColor3 = Color3.fromRGB(44, 52, 80)
head.BorderSizePixel  = 0
head.ZIndex           = 2
head.Parent           = panel
Instance.new("UICorner", head).CornerRadius = UDim.new(0, 16)
local hgrad = Instance.new("UIGradient", head)
hgrad.Rotation = 90
hgrad.Color    = ColorSequence.new(Color3.fromRGB(58, 48, 96), Color3.fromRGB(36, 54, 84))
-- squares off the header's bottom corners so it reads as a bar and not a floating pill
local hfill = Instance.new("Frame")
hfill.Size             = UDim2.new(1, 0, 0, 18)
hfill.Position         = UDim2.new(0, 0, 1, -18)
hfill.BackgroundColor3 = Color3.fromRGB(41, 51, 82)
hfill.BorderSizePixel  = 0
hfill.ZIndex           = 3
hfill.Parent           = head

local title = Instance.new("TextLabel")
title.Position               = UDim2.new(0, 24, 0, 12)
title.Size                   = UDim2.new(1, -110, 0, 32)
title.BackgroundTransparency = 1
title.Font                   = Enum.Font.GothamBlack
title.Text                   = "GNOME HOME"
title.TextColor3             = GOLD
title.TextSize               = 28
title.TextXAlignment         = Enum.TextXAlignment.Left
title.ZIndex                 = 4
title.Parent                 = head

local sub = Instance.new("TextLabel")
sub.Position               = UDim2.new(0, 24, 0, 44)
sub.Size                   = UDim2.new(1, -110, 0, 20)
sub.BackgroundTransparency = 1
sub.Font                   = Enum.Font.GothamMedium
sub.Text                   = "You hold the key to this door"
sub.TextColor3             = TXT_DIM
sub.TextSize               = 14
sub.TextXAlignment         = Enum.TextXAlignment.Left
sub.ZIndex                 = 4
sub.Parent                 = head

local close = Instance.new("TextButton")
close.AnchorPoint      = Vector2.new(1, 0.5)
close.Position         = UDim2.new(1, -18, 0.5, 0)
close.Size             = UDim2.fromOffset(40, 40)
close.BackgroundColor3 = Color3.fromRGB(212, 68, 84)
close.Font             = Enum.Font.FredokaOne
close.Text             = "X"
close.TextColor3       = Color3.new(1, 1, 1)
close.TextSize         = 22
close.ZIndex           = 5
close.Parent           = head
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)

-- ===== THE TWO CHOICES, AS ROWS =====
-- A row per choice: flat card, a coloured accent stripe down the left edge, GothamBold heading, GothamMedium
-- description, and a pill button on the right -- exactly the shape of a Daily Tasks row.
local function row(y, headline, body, btnText, accent)
	local card = Instance.new("Frame")
	card.Position         = UDim2.new(0, 24, 0, y)
	card.Size             = UDim2.new(1, -48, 0, 104)
	card.BackgroundColor3 = CARD
	card.BorderSizePixel  = 0
	card.Parent           = panel
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local stripe = Instance.new("Frame")
	stripe.Size             = UDim2.new(0, 6, 1, -24)
	stripe.Position         = UDim2.new(0, 14, 0, 12)
	stripe.BackgroundColor3 = accent
	stripe.BorderSizePixel  = 0
	stripe.Parent           = card
	Instance.new("UICorner", stripe).CornerRadius = UDim.new(0, 3)

	local h = Instance.new("TextLabel")
	h.Position               = UDim2.new(0, 36, 0, 20)
	h.Size                   = UDim2.new(1, -230, 0, 26)
	h.BackgroundTransparency = 1
	h.Font                   = Enum.Font.GothamBold
	h.Text                   = headline
	h.TextColor3             = TXT
	h.TextSize               = 20
	h.TextXAlignment         = Enum.TextXAlignment.Left
	h.Parent                 = card

	local d = Instance.new("TextLabel")
	d.Position               = UDim2.new(0, 36, 0, 48)
	d.Size                   = UDim2.new(1, -230, 0, 38)
	d.BackgroundTransparency = 1
	d.Font                   = Enum.Font.GothamMedium
	d.Text                   = body
	d.TextColor3             = TXT_DIM
	d.TextSize               = 14
	d.TextWrapped            = true
	d.TextXAlignment         = Enum.TextXAlignment.Left
	d.TextYAlignment         = Enum.TextYAlignment.Top
	d.Parent                 = card

	local btn = Instance.new("TextButton")
	btn.AnchorPoint      = Vector2.new(1, 0.5)
	btn.Position         = UDim2.new(1, -18, 0.5, 0)
	btn.Size             = UDim2.fromOffset(160, 46)
	btn.BackgroundColor3 = accent
	btn.Font             = Enum.Font.GothamBold
	btn.Text             = btnText
	btn.TextColor3       = Color3.fromRGB(18, 24, 34)
	btn.TextSize         = 16
	btn.AutoButtonColor  = true
	btn.BorderSizePixel  = 0
	btn.Parent           = card
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
	return btn
end

local talkBtn   = row(110, "Come outside",
	"He steps out of the tree for a chat, then heads back in.", "KNOCK", GREEN)
local insideBtn = row(232, "Go inside",
	"Step through the door into the hollow. Nobody else can.", "ENTER", GOLD)

-- ===== FOOTER =====
-- Says what is in there, so the panel is not just two buttons with no context.
local foot = Instance.new("TextLabel")
foot.Position               = UDim2.new(0, 24, 1, -78)
foot.Size                   = UDim2.new(1, -48, 0, 54)
foot.BackgroundColor3       = Color3.fromRGB(26, 31, 48)
foot.BorderSizePixel        = 0
foot.Font                   = Enum.Font.GothamMedium
foot.Text                   = "Both brothers live here now. There is a game on the table."
foot.TextColor3             = TXT_DIM
foot.TextSize               = 14
foot.Parent                 = panel
Instance.new("UICorner", foot).CornerRadius = UDim.new(0, 10)

-- ===== OPEN / CLOSE =====
local isOpen = false
local function hide()
	if not isOpen then return end
	isOpen = false
	screen.Enabled = false
end
local function show()
	isOpen = true
	screen.Enabled = true
	panel.Size = UDim2.new(0, 660, 0, 490)
	TweenService:Create(panel, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 700, 0, 520) }):Play()
end

close.Activated:Connect(hide)
talkBtn.Activated:Connect(function()
	hide()
	pcall(function() remote:FireServer("talk") end)
end)
insideBtn.Activated:Connect(function()
	hide()
	pcall(function() remote:FireServer("inside") end)
end)

-- The server only ever sends "open", and only to a player it has already confirmed holds the key and is
-- stood at the door. Nothing else in this script can open the panel.
remote.OnClientEvent:Connect(function(what)
	if what == "open" then show() end
end)

-- Walking away closes it: this is anchored to a door you are standing at.
task.spawn(function()
	while true do
		task.wait(0.5)
		if isOpen then
			local ch = player.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
			local tree = workspace:FindFirstChild("SecretTree", true)
			if not hrp then
				hide()
			elseif tree then
				local ok, pos = pcall(function()
					return (tree:IsA("Model") and tree:GetPivot().Position) or tree.Position
				end)
				if ok and pos and (hrp.Position - pos).Magnitude > 40 then hide() end
			end
		end
	end
end)

print("[GnomeHomeMenu] ready -- house-style 700x520 panel, hidden until the SERVER says open (key holders only)")
