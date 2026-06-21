--======================================================================
-- GardenerChat.client.lua  (LocalScript)  -- the Gardener NPC's PRESET-QUESTION dialogue menu (warm farm theme).
--======================================================================
-- Holding E on the Gardener (his "GardenerTalkPrompt") opens a parchment dialogue panel: a dark-wood header with a
-- sunflower + "Gardener" title + red X, a cream greeting box, and green icon "pill" question buttons. Tapping a
-- question asks the SERVER by key (GardenerChatFunction) and shows the gardener's answer; the list stays so you can
-- ask more, and "Bye!" closes it. The server owns the answers (so "How close are we?" reads live progress).
-- ONLY the look changed here -- questions, answers, and behaviour come from the server unchanged. Purely cosmetic.
--======================================================================

local Players                = game:GetService("Players")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ChatFn = ReplicatedStorage:WaitForChild("GardenerChatFunction", 60)
if not ChatFn then return end

-- ===== warm farm palette =====
local CREAM     = Color3.fromRGB(245, 238, 214) -- parchment body
local CREAM2    = Color3.fromRGB(252, 248, 232) -- lighter inset (greeting box)
local BORDER    = Color3.fromRGB(120, 78, 40)   -- thick warm border
local WOOD      = Color3.fromRGB(74, 48, 30)    -- dark wood header strip
local GOLD      = Color3.fromRGB(196, 160, 90)  -- gold/tan trim + chevron
local RED       = Color3.fromRGB(210, 60, 55)   -- close button
local BROWN     = Color3.fromRGB(60, 45, 30)    -- greeting text
local GREEN     = Color3.fromRGB(70, 110, 45)   -- question pill
local GREEN_HOV = Color3.fromRGB(55, 90, 35)    -- pill hover/press
local WHITE     = Color3.fromRGB(255, 255, 255)

-- small emoji icon per question key (built-in glyphs; falls back to a sprout)
local ICONS = {
	what   = "\xF0\x9F\x8C\xB1", -- sprout
	help   = "\xF0\x9F\x92\xA7", -- droplet (watering)
	close  = "\xF0\x9F\x91\xA5", -- people
	reward = "\xF0\x9F\x8E\x81", -- gift
	who    = "\xF0\x9F\x98\x84", -- smiley
	bye    = "\xF0\x9F\x91\x8B", -- wave
}

-- ===== build the dialogue UI (hidden until the prompt is triggered) =====
local gui = Instance.new("ScreenGui")
gui.Name = "GardenerChatGui"; gui.ResetOnSpawn = false; gui.DisplayOrder = 100 -- match the SHOP / Pet Hub / Seasonal Pets ScreenGui settings (DisplayOrder 100)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.Enabled = true; gui.Parent = playerGui -- no IgnoreGuiInset (same as the Shop) so the same Size/Position resolves to the same on-screen rect

local root = Instance.new("Frame")
-- EXACT same Size + Position + AnchorPoint as the SHOP panel: 700x520 logical, centered, nudged up 45px. applyScaling
-- (the shared scaling pass, called on open below) gives it the SAME UIScale as the Shop -> ~663x492 on screen.
root.Name = "Panel"; root.AnchorPoint = Vector2.new(0.5, 0.5); root.Position = UDim2.new(0.5, 0, 0.5, -45)
root.Size = UDim2.new(0, 700, 0, 520); root.BackgroundColor3 = CREAM; root.ClipsDescendants = true
root.Visible = false; root.Parent = gui
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 16)
local rootStroke = Instance.new("UIStroke", root); rootStroke.Thickness = 4; rootStroke.Color = BORDER

-- ----- dark-wood header bar (clipped to rounded top by the panel) -----
local header = Instance.new("Frame")
header.Name = "Header"; header.BackgroundColor3 = WOOD; header.BorderSizePixel = 0
header.Size = UDim2.new(1, 0, 0, 54); header.Position = UDim2.new(0, 0, 0, 0); header.Parent = root -- taller header to suit the bigger panel

local sun = Instance.new("TextLabel")
sun.Name = "Sun"; sun.BackgroundTransparency = 1; sun.Position = UDim2.new(0, 12, 0, 0); sun.Size = UDim2.new(0, 30, 1, 0)
sun.Font = Enum.Font.FredokaOne; sun.TextSize = 24; sun.Text = "\xF0\x9F\x8C\xBB"; sun.Parent = header

local titleLbl = Instance.new("TextLabel")
titleLbl.Name = "Title"; titleLbl.BackgroundTransparency = 1; titleLbl.Position = UDim2.new(0, 46, 0, 0)
titleLbl.Size = UDim2.new(1, -110, 1, 0); titleLbl.Font = Enum.Font.FredokaOne; titleLbl.TextSize = 24
titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.TextColor3 = WHITE; titleLbl.Text = "Gardener"; titleLbl.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"; closeBtn.AnchorPoint = Vector2.new(1, 0.5); closeBtn.Position = UDim2.new(1, -9, 0.5, 0)
closeBtn.Size = UDim2.new(0, 34, 0, 34); closeBtn.BackgroundColor3 = RED; closeBtn.AutoButtonColor = true
closeBtn.Font = Enum.Font.FredokaOne; closeBtn.TextSize = 22; closeBtn.Text = "X"; closeBtn.TextColor3 = WHITE; closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 9)

-- ----- greeting / current-answer box (inset cream + gold trim + leaf accent) -----
local replyBox = Instance.new("Frame")
replyBox.Name = "ReplyBox"; replyBox.BackgroundColor3 = CREAM2; replyBox.BorderSizePixel = 0
replyBox.Position = UDim2.new(0, 18, 0, 66); replyBox.Size = UDim2.new(1, -36, 0, 110); replyBox.Parent = root -- wider + taller greeting box to fill the bigger panel
Instance.new("UICorner", replyBox).CornerRadius = UDim.new(0, 12)
local replyStroke = Instance.new("UIStroke", replyBox); replyStroke.Thickness = 2; replyStroke.Color = GOLD

local leaf = Instance.new("TextLabel")
leaf.Name = "Leaf"; leaf.BackgroundTransparency = 1; leaf.Position = UDim2.new(0, 8, 0, 6); leaf.Size = UDim2.new(0, 22, 0, 22)
leaf.Font = Enum.Font.FredokaOne; leaf.TextSize = 18; leaf.Text = "\xF0\x9F\x8D\x83"; leaf.Parent = replyBox

local replyText = Instance.new("TextLabel")
replyText.Name = "Reply"; replyText.BackgroundTransparency = 1; replyText.Position = UDim2.new(0, 34, 0, 8)
replyText.Size = UDim2.new(1, -44, 1, -16); replyText.Font = Enum.Font.GothamBold; replyText.TextSize = 17
replyText.TextWrapped = true; replyText.TextColor3 = BROWN
replyText.TextXAlignment = Enum.TextXAlignment.Left; replyText.TextYAlignment = Enum.TextYAlignment.Top
replyText.Text = ""; replyText.Parent = replyBox

-- ----- scrolling list of green icon-pill question buttons -----
local list = Instance.new("ScrollingFrame")
list.Name = "Questions"; list.BackgroundTransparency = 1; list.BorderSizePixel = 0
list.Position = UDim2.new(0, 18, 0, 188); list.Size = UDim2.new(1, -36, 1, -206) -- fills the wider panel under the greeting box
list.ScrollBarThickness = 5; list.ScrollBarImageColor3 = BORDER
list.CanvasSize = UDim2.new(0, 0, 0, 0); list.AutomaticCanvasSize = Enum.AutomaticSize.Y; list.Parent = root
local listLayout = Instance.new("UIListLayout", list)
listLayout.Padding = UDim.new(0, 10); listLayout.SortOrder = Enum.SortOrder.LayoutOrder -- more space between the wider buttons
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local busy = false

local function closeChat()
	root.Visible = false
end

local function onPick(key)
	if busy then return end
	busy = true
	local ok, ans = pcall(function() return ChatFn:InvokeServer("ask", key) end)
	replyText.Text = (ok and type(ans) == "string" and ans) or "..."
	busy = false
	if key == "bye" then
		task.delay(1.4, closeChat) -- show the sign-off briefly, then close
	end
end

local function makeButton(q, order)
	local b = Instance.new("TextButton")
	b.Name = "Q_" .. tostring(q.key); b.LayoutOrder = order
	b.Size = UDim2.new(1, -16, 0, 56); b.BackgroundColor3 = GREEN; b.AutoButtonColor = false -- stretch to the wider panel, taller pill
	b.Text = ""; b.Parent = list
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 14)

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"; icon.BackgroundTransparency = 1; icon.Position = UDim2.new(0, 12, 0, 0); icon.Size = UDim2.new(0, 28, 1, 0)
	icon.Font = Enum.Font.FredokaOne; icon.TextSize = 20; icon.Text = ICONS[q.key] or "\xF0\x9F\x8C\xB1"; icon.Parent = b

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"; lbl.BackgroundTransparency = 1; lbl.Position = UDim2.new(0, 46, 0, 0); lbl.Size = UDim2.new(1, -76, 1, 0)
	lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 16; lbl.TextWrapped = true; lbl.TextColor3 = WHITE
	lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Text = q.label; lbl.Parent = b

	local chev = Instance.new("TextLabel")
	chev.Name = "Chevron"; chev.BackgroundTransparency = 1; chev.AnchorPoint = Vector2.new(1, 0.5)
	chev.Position = UDim2.new(1, -12, 0.5, 0); chev.Size = UDim2.new(0, 18, 1, 0)
	chev.Font = Enum.Font.FredokaOne; chev.TextSize = 22; chev.TextColor3 = GOLD; chev.Text = ">"; chev.Parent = b

	-- hover / press feedback
	b.MouseEnter:Connect(function() b.BackgroundColor3 = GREEN_HOV end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = GREEN end)
	b.MouseButton1Down:Connect(function() b.BackgroundColor3 = GREEN_HOV end)
	b.MouseButton1Up:Connect(function() b.BackgroundColor3 = GREEN end)
	b.MouseButton1Click:Connect(function() onPick(q.key) end)
	return b
end

local function buildButtons(questions)
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for i, q in ipairs(questions) do
		makeButton(q, i)
	end
end

local function openChat()
	local ok, data = pcall(function() return ChatFn:InvokeServer("menu") end)
	if not (ok and type(data) == "table" and type(data.questions) == "table") then return end
	replyText.Text = data.greeting or "Howdy!"
	buildButtons(data.questions)
	root.Visible = true
	if _G.applyHudScaling then _G.applyHudScaling() end -- same UIScale pass the Shop / Pet Hub / Seasonal Pets use -> identical on-screen size (~663x492)
	task.defer(function() print("[UIFix] Gardener AbsoluteSize=" .. tostring(root.AbsoluteSize) .. " AbsolutePosition=" .. tostring(root.AbsolutePosition)) end) -- confirm it matches the Shop
end

closeBtn.MouseButton1Click:Connect(closeChat)

-- open when the Gardener's hold-E prompt is triggered (by us)
ProximityPromptService.PromptTriggered:Connect(function(prompt, plr)
	if plr ~= player then return end
	if prompt.Name == "GardenerTalkPrompt" then openChat() end
end)

-- ===== HIDE THE BOTTOM HUD WHILE THE GARDENER CHAT IS OPEN (same logic the Shop / Pet Hub / Seasonal Pets use) =====
-- The gardener chat joins the shared main-menu group via _G.MainMenuManager: opening it hides the bottom HUD
-- (TAP TO FART! button + gas/fart meter + gut indicator, which all live in BottomStackGui) and closing it restores
-- them. Guarded factory in case this script loads first. (Chat behaviour/questions/answers are untouched.)
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible)
		local lp = game:GetService("Players").LocalPlayer
		local pgx = lp and lp:FindFirstChildOfClass("PlayerGui")
		local g = pgx and pgx:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h = mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name
		mgr.setHud(false)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
_G.MainMenuManager.register("Gardener", function() root.Visible = false end) -- another menu opening closes the chat
-- Drive the HUD hide/show off root.Visible so the HUD ALWAYS restores no matter HOW the chat closes (X button,
-- the "Bye!" sign-off, another menu opening, or the player walking away) -- it can never get left hidden.
root:GetPropertyChangedSignal("Visible"):Connect(function()
	if not _G.MainMenuManager then return end
	if root.Visible then _G.MainMenuManager.notifyOpened("Gardener") else _G.MainMenuManager.notifyClosed("Gardener") end
end)
-- WALK-AWAY safety: when the gardener's prompt hides (player left range), close the chat -> the line above then
-- restores the HUD. Without this, walking off mid-chat would leave the panel (and the hidden HUD) stuck.
ProximityPromptService.PromptHidden:Connect(function(prompt)
	if prompt.Name == "GardenerTalkPrompt" and root.Visible then closeChat() end
end)
