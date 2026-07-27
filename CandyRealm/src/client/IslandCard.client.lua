--======================================================================
-- IslandCard.client.lua   (LocalScript, per-player)
--======================================================================
-- LAND SOMEWHERE AND IT TELLS YOU WHERE YOU ARE.
--
--        COCONUT COVE
--        - ISLAND 5 -
--
-- Fourteen platforms with numbers become fourteen PLACES the moment they are named at you. It
-- is the cheapest thing on the whole polish list and the one players read as production value.
--
-- ONCE PER ISLAND PER SESSION. A card every time you set foot on Bean Farm is a notification;
-- a card the first time is an arrival. And it waits until you are actually DOWN -- announcing
-- an island while you are still falling past it is how you end up naming three on one flight.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player     = Players.LocalPlayer
local PlayerGui  = player:WaitForChild("PlayerGui")

-- The names come from the design doc, so the card agrees with everything else in the game.
local NAMES = {
	[1] = "BEAN FARM",        [2] = "BROCCOLI BLUFF",   [3] = "CABBAGE CLIFFS",
	[4] = "TURNIP TRANQUIL",  [5] = "COCONUT COVE",     [6] = "BREAD BOARD",
	[7] = "PASTA PEAK",       [8] = "POPCORN PINNACLE", [9] = "MILK MARSH",
	[10] = "BUTTER SWAMP",    [11] = "ICE CREAM ISLE",  [12] = "BURGER BLUFF",
	[13] = "BURRITO BARRENS", [14] = "PIZZA PALMS",
}

local SETTLE   = 0.7    -- seconds you must be on the ground before it will announce
local HOLD     = 2.6    -- how long the card stays up
local RESCAN   = 0.6

local function norm(s) return (tostring(s):lower():gsub("[%s_%-]", "")) end

-- ---- the card -------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "IslandCard"; gui.ResetOnSpawn = false; gui.DisplayOrder = 6
gui.IgnoreGuiInset = true; gui.Parent = PlayerGui

local holder = Instance.new("Frame")
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(0, 0.5)
holder.Position = UDim2.new(0.06, 0, 0.36, 0)
holder.Size = UDim2.new(0, 560, 0, 120)
holder.Parent = gui

-- A RULE, NOT A PANEL. A filled box over the view is a popup and reads as UI; a name with a
-- line under it reads as a title card. The difference is entirely in what you leave out.
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 0, 0, 0); title.Size = UDim2.new(1, 0, 0, 72)
title.Font = Enum.Font.FredokaOne; title.TextSize = 56
title.TextColor3 = Color3.fromRGB(255, 252, 245)
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextTransparency = 1
title.Text = ""
title.Parent = holder
local ts = Instance.new("UIStroke")
ts.Color = Color3.fromRGB(28, 22, 34); ts.Thickness = 3; ts.Transparency = 1
ts.Parent = title

local rule = Instance.new("Frame")
rule.BackgroundColor3 = Color3.fromRGB(255, 208, 92); rule.BorderSizePixel = 0
rule.Position = UDim2.new(0, 2, 0, 74); rule.Size = UDim2.new(0, 0, 0, 4)
rule.Parent = holder

local sub = Instance.new("TextLabel")
sub.BackgroundTransparency = 1
sub.Position = UDim2.new(0, 2, 0, 84); sub.Size = UDim2.new(1, 0, 0, 30)
sub.Font = Enum.Font.GothamBold; sub.TextSize = 20
sub.TextColor3 = Color3.fromRGB(255, 208, 92)
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.TextTransparency = 1
sub.Text = ""
sub.Parent = holder

local showing = 0
local function showCard(n)
	showing += 1
	local mine = showing
	title.Text = NAMES[n] or ("ISLAND " .. n)
	sub.Text   = ("- ISLAND %d -"):format(n)

	-- everything comes in from the left and slightly out of position, because a title that
	-- fades in on the spot reads as a label appearing, not as one arriving
	holder.Position = UDim2.new(0.04, 0, 0.36, 0)
	rule.Size = UDim2.new(0, 0, 0, 4)
	TweenService:Create(holder, TweenInfo.new(0.55, Enum.EasingStyle.Quint),
		{ Position = UDim2.new(0.06, 0, 0.36, 0) }):Play()
	TweenService:Create(title, TweenInfo.new(0.45), { TextTransparency = 0 }):Play()
	TweenService:Create(ts, TweenInfo.new(0.45), { Transparency = 0 }):Play()
	TweenService:Create(rule, TweenInfo.new(0.6, Enum.EasingStyle.Quint),
		{ Size = UDim2.new(0, 300, 0, 4) }):Play()
	task.delay(0.18, function()
		if mine ~= showing then return end
		TweenService:Create(sub, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	end)

	task.delay(HOLD, function()
		if mine ~= showing then return end
		TweenService:Create(title, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(ts, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		TweenService:Create(sub, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(rule, TweenInfo.new(0.5), { Size = UDim2.new(0, 0, 0, 4) }):Play()
	end)
end

-- ---- which island am I on? -------------------------------------------------
-- Bounding boxes, same as the NPC arrows. Pivot distance picks the wrong island entirely,
-- which is the bug that made those arrows point at island 14 while stood on island 8.
local boxes = {}
local function boxOf(m)
	local b = boxes[m]
	if b and b.h.X > 25 and b.h.Z > 25 then return b end
	local ok, cf, size = pcall(function() return m:GetBoundingBox() end)
	if not ok or not cf then return nil end
	b = { c = cf.Position, h = size * 0.5 }
	boxes[m] = b
	return b
end

local function islandUnder(pos)
	local best, bestScore, bestN
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") then
			local n = norm(m.Name):match("^island(%d+)$")
			if n then
				local b = boxOf(m)
				if b then
					local dx = math.max(0, math.abs(pos.X - b.c.X) - b.h.X)
					local dz = math.max(0, math.abs(pos.Z - b.c.Z) - b.h.Z)
					local score = math.sqrt(dx * dx + dz * dz) * 1000 + (b.h.X + b.h.Z)
					if not bestScore or score < bestScore then
						best, bestScore, bestN = m, score, tonumber(n)
					end
				end
			end
		end
	end
	-- only if you are genuinely over it, not merely nearest to it
	if best and bestScore and bestScore < 1000 then return bestN end
	return nil
end

local seen, current, grounded, nextScan = {}, nil, 0, 0

RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp then return end

	-- WAIT UNTIL YOU ARE DOWN. Mid-flight you cross several islands, and announcing each one as
	-- you pass over it turns the card into a ticker. Grounded, and still, and then it speaks.
	local still = (not _G.isFlying)
		and (hum == nil or hum.FloorMaterial ~= Enum.Material.Air)
		and hrp.AssemblyLinearVelocity.Magnitude < 26
	grounded = still and (grounded + dt) or 0

	local now = os.clock()
	if now < nextScan then return end
	nextScan = now + RESCAN

	local n = islandUnder(hrp.Position)
	if n ~= current then
		current = n
		return                       -- one scan of settling before it may announce
	end
	if n and grounded >= SETTLE and not seen[n] then
		seen[n] = true
		showCard(n)
		print(("[IslandCard] arrived on island %d -- %s"):format(n, NAMES[n] or "?"))
	end
end)

print("[IslandCard] ready -- names each island the first time you land on it")
