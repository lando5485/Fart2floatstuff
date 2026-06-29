-- ============================================================================
-- GUT SKIN CLIENT — UI + animation for cosmetic gut skins.
--   * Injects a "Skins" tab into the existing Stomach menu (StomachShopGui.Panel), switching between the
--     stomach TIERS view and a scrolling SKINS grid. (Bottom HUD already hides while that menu is open.)
--   * Equip requests go to the server (EquipGutSkin); the server validates ownership + saves + re-skins the gut.
--   * Animated skins (Rainbow) are tweened on THIS client for the local player's gut; stops when a
--     non-animated skin is equipped.
-- ============================================================================

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local RunService   = game:GetService("RunService")
local player       = Players.LocalPlayer
local playerGui    = player:WaitForChild("PlayerGui")
local GutSkins     = require(RS:WaitForChild("Shared"):WaitForChild("GutSkins"))

local EquipGutSkin   = RS:WaitForChild("EquipGutSkin", 60)
local GetGutSkins    = RS:WaitForChild("GetGutSkins", 60)
local GutSkinState   = RS:WaitForChild("GutSkinState", 60)
local GutSkinUnlocked= RS:WaitForChild("GutSkinUnlocked", 60)

local SKINTONE = Color3.fromRGB(255, 204, 153)
local localEquipped = "Default"
local localPlaytimeSec = 0 -- mirrors the server total; ticks up locally for live progress, re-synced on state events
local lastState = { owned = { Default = true }, equipped = "Default", playtimeSec = 0 }

-- ---- tiny UI helpers ----
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, o) end
local function stroke(o, c, t) new("UIStroke", { Color = c or Color3.new(1,1,1), Thickness = t or 2 }, o) end
local function swatchColor(skin) return (skin and skin.color) or SKINTONE end
-- the in-game STOMACH/GUT silhouette icon (same asset the HUD GutIcon / Stomach side button use).
-- Hardcoded (not via _G.GUT_IMAGE) so it can't resolve to anything else (e.g. an avatar/empty) at load time.
local GUT_ICON = "rbxassetid://108585083746103"
-- red -> orange -> yellow -> green -> blue -> purple (used for the Rainbow preview gradient + bg)
local RAINBOW_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.20, Color3.fromRGB(255, 150, 40)),
	ColorSequenceKeypoint.new(0.40, Color3.fromRGB(245, 235, 50)),
	ColorSequenceKeypoint.new(0.60, Color3.fromRGB(70, 220, 90)),
	ColorSequenceKeypoint.new(0.80, Color3.fromRGB(70, 150, 255)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(190, 80, 235)),
})
local function darken(c, amt) return c:Lerp(Color3.new(0, 0, 0), amt) end
-- the stomach-icon ImageColor3 tint for a skin (brighter for Lava so it reads as glowing neon)
local function previewTint(skin)
	if not skin.color then return SKINTONE end
	if skin.id == "Lava" then return Color3.fromRGB(255, 120, 45) end
	return skin.color
end

-- ============================ RAINBOW ANIMATION =============================
local function findGutFolder()
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("LowerTorso"))
	return torso and torso:FindFirstChild("GutBelly")
end
local hue = 0
RunService.Heartbeat:Connect(function(dt)
	local skin = GutSkins.get(localEquipped)
	if not (skin and skin.animated == "rainbow") then return end -- only while a rainbow-type skin is equipped
	hue = (hue + dt * 0.15) % 1
	local folder = findGutFolder(); if not folder then return end
	local g = folder:FindFirstChild("Gut"); if not g then return end
	g.Color = Color3.fromHSV(hue, 0.85, 1)
	local sag = g:FindFirstChild("Sag");   if sag   then sag.Color   = Color3.fromHSV(hue, 0.85, 0.85) end
	local sheen = g:FindFirstChild("Sheen"); if sheen then sheen.Color = Color3.fromHSV(hue, 0.70, 1.00) end
	local navel = g:FindFirstChild("Navel"); if navel then navel.Color = Color3.fromHSV(hue, 0.90, 0.55) end
end)

-- =============================== SKINS GRID UI =============================
local skinsScroll     -- the grid ScrollingFrame (built once injected into the panel)
local rebuildSkins    -- forward declaration (assigned below)
local lockedCards = {} -- { {fill=, label=, thresholdSec=}, ... } updated live while the menu is open
local rainbowGradients = {} -- UIGradients (rainbow card bg + stomach icon) animated each frame; reset on rebuild

-- flow the rainbow over every rainbow gradient (preview cards) by rotating them; drops destroyed ones
RunService.Heartbeat:Connect(function(dt)
	for i = #rainbowGradients, 1, -1 do
		local g = rainbowGradients[i]
		if g and g.Parent then g.Rotation = (g.Rotation + dt * 60) % 360 else table.remove(rainbowGradients, i) end
	end
end)

-- PREVIEW: a recoloured STOMACH icon over a skin-coloured background. Rainbow -> animated UIGradient (white icon).
-- If the stomach image ever fails to load, we swap to a tinted belly SHAPE so Roblox's grey image-failed
-- placeholder (the person/avatar silhouette) can NEVER show.
local ContentProvider = game:GetService("ContentProvider")
local function buildSkinPreview(card, skin, isOwned)
	local isRainbow = (skin.animated == "rainbow")
	local area = new("Frame", { Name = "Preview", BorderSizePixel = 0,
		BackgroundColor3 = isRainbow and Color3.fromRGB(40, 40, 55) or darken(swatchColor(skin), 0.18),
		Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(130, 56) }, card)
	corner(area, 8); stroke(area, Color3.fromRGB(0, 0, 0), 1)
	-- background fill: animated rainbow gradient, or a subtle vertical tint of the skin colour
	if isRainbow then
		rainbowGradients[#rainbowGradients + 1] = new("UIGradient", { Color = RAINBOW_SEQ, Rotation = 0 }, area)
	else
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(swatchColor(skin), darken(swatchColor(skin), 0.45)) }, area)
	end

	local tint = isRainbow and Color3.new(1, 1, 1) or previewTint(skin) -- white for rainbow so the gradient shows true
	-- the STOMACH silhouette icon, tinted to the skin
	local icon = new("ImageLabel", { Name = "GutIcon", Image = GUT_ICON, ImageColor3 = tint, ScaleType = Enum.ScaleType.Fit,
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.85, 0.85), ZIndex = 2 }, area)
	-- belly-shaped fallback (hidden unless the stomach image can't load)
	local fallback = new("Frame", { Name = "GutShape", BackgroundColor3 = tint, Visible = false, ZIndex = 2,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.82) }, area)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, fallback); stroke(fallback, Color3.fromRGB(0, 0, 0), 1)

	if isRainbow then
		rainbowGradients[#rainbowGradients + 1] = new("UIGradient", { Color = RAINBOW_SEQ, Rotation = 0 }, icon)      -- ON the stomach icon
		rainbowGradients[#rainbowGradients + 1] = new("UIGradient", { Color = RAINBOW_SEQ, Rotation = 0 }, fallback)  -- and the shape fallback
	elseif skin.id == "Lava" then
		stroke(icon, Color3.fromRGB(255, 180, 60), 2)     -- subtle neon glow ring on the stomach
		stroke(fallback, Color3.fromRGB(255, 180, 60), 2)
	elseif skin.id == "Galaxy" then -- overlay a few stars ON the stomach preview (no uploaded asset needed)
		for _, p in ipairs({ {0.22, 0.28}, {0.74, 0.32}, {0.58, 0.7}, {0.32, 0.74} }) do
			new("TextLabel", { Text = "\xE2\x9C\xA6", Font = Enum.Font.GothamBold, TextScaled = true, BackgroundTransparency = 1,
				TextColor3 = Color3.fromRGB(235, 225, 255), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(p[1], p[2]), Size = UDim2.fromOffset(11, 11), ZIndex = 3 }, area)
		end
	end
	if not isOwned then icon.ImageTransparency = 0.4; fallback.BackgroundTransparency = 0.35; area.BackgroundTransparency = 0.25 end -- greyed while locked

	-- swap to the belly shape if the stomach image asset doesn't load (e.g. it's a decal / not approved for this place)
	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync({ icon }) end)
		if icon.Parent and not icon.IsLoaded then icon.Visible = false; fallback.Visible = true end
	end)
end

local function equip(skinId)
	task.spawn(function()
		local ok, res = pcall(function() return EquipGutSkin:InvokeServer(skinId) end)
		if ok and type(res) == "table" and res.ok then
			localEquipped = res.equipped or skinId
			localPlaytimeSec = res.playtimeSec or localPlaytimeSec
			lastState = { owned = res.owned or lastState.owned, equipped = localEquipped, playtimeSec = localPlaytimeSec }
			if skinsScroll then rebuildSkins(lastState) end
		end
	end)
end

-- live-update each locked card's progress bar + "current / threshold" text from localPlaytimeSec
local function refreshLockedProgress()
	for _, lc in ipairs(lockedCards) do
		if lc.fill and lc.fill.Parent then
			local frac = math.clamp(localPlaytimeSec / math.max(1, lc.thresholdSec), 0, 1)
			lc.fill.Size = UDim2.new(frac, 0, 1, 0)
			lc.label.Text = GutSkins.formatMinutes(localPlaytimeSec / 60) .. " / " .. GutSkins.formatMinutes(lc.thresholdSec / 60)
		end
	end
end

function rebuildSkins(state)
	if not skinsScroll then return end
	lockedCards = {}
	rainbowGradients = {} -- old gradients live on destroyed cards; the animator drops them, but reset so we don't grow
	for _, c in ipairs(skinsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	local owned = (state and state.owned) or { Default = true }
	local equipped = (state and state.equipped) or "Default"
	for i, id in ipairs(GutSkins.Order) do
		local skin = GutSkins.get(id); if skin then
			local isOwned = (id == "Default") or owned[id] == true
			local isEquipped = (id == equipped)
			local rarityCol = GutSkins.RarityColor[skin.rarity] or Color3.fromRGB(190,190,200)

			-- card background reads as the skin's colour at a glance (darkened so text stays legible)
			local cardBg = (skin.animated == "rainbow") and Color3.fromRGB(34, 34, 48) or darken(swatchColor(skin), 0.55)
			local card = new("Frame", { LayoutOrder = i, BackgroundColor3 = cardBg, Size = UDim2.fromOffset(150, 150) }, skinsScroll)
			corner(card, 12); stroke(card, isEquipped and Color3.fromRGB(120, 255, 140) or (isOwned and Color3.fromRGB(255,255,255) or Color3.fromRGB(120,120,130)), isEquipped and 3 or 2)
			if skin.animated == "rainbow" then -- matching animated rainbow gradient behind the whole card
				rainbowGradients[#rainbowGradients + 1] = new("UIGradient", { Color = RAINBOW_SEQ, Rotation = 0, Transparency = NumberSequence.new(0.55) }, card)
			end

			-- preview: recoloured stomach icon over a skin-coloured background (rainbow = animated gradient)
			buildSkinPreview(card, skin, isOwned)

			-- name + rarity
			new("TextLabel", { Text = skin.displayName, Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = isOwned and Color3.new(1,1,1) or Color3.fromRGB(200,200,210), BackgroundTransparency = 1,
				Position = UDim2.fromOffset(8, 66), Size = UDim2.fromOffset(134, 20) }, card)
			new("TextLabel", { Text = skin.rarity, Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = rarityCol, BackgroundTransparency = 1,
				Position = UDim2.fromOffset(8, 86), Size = UDim2.fromOffset(134, 14) }, card)

			if isEquipped then
				local b = new("TextButton", { Text = "EQUIPPED", Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.new(1,1,1), AutoButtonColor = false,
					BackgroundColor3 = Color3.fromRGB(60, 170, 90), Position = UDim2.fromOffset(8, 110), Size = UDim2.fromOffset(134, 32), BorderSizePixel = 0 }, card)
				corner(b, 8); new("UITextSizeConstraint", { MaxTextSize = 16 }, b)
			elseif isOwned then
				local b = new("TextButton", { Text = "EQUIP", Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.new(1,1,1),
					BackgroundColor3 = Color3.fromRGB(40, 120, 220), Position = UDim2.fromOffset(8, 110), Size = UDim2.fromOffset(134, 32), BorderSizePixel = 0 }, card)
				corner(b, 8); new("UITextSizeConstraint", { MaxTextSize = 16 }, b)
				b.MouseButton1Click:Connect(function() equip(id) end)
			else
				-- LOCKED: "Unlocks at Xh Ym" + a live progress bar (current playtime / threshold)
				local thresholdSec = GutSkins.unlockMinutes(id) * 60
				new("TextLabel", { Text = "Unlocks at " .. GutSkins.formatMinutes(GutSkins.unlockMinutes(id)), Font = Enum.Font.GothamBold, TextScaled = true,
					TextColor3 = Color3.fromRGB(210,210,220), BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 104), Size = UDim2.fromOffset(134, 14) }, card)
				local barBg = new("Frame", { BackgroundColor3 = Color3.fromRGB(25, 35, 60), Position = UDim2.fromOffset(8, 122), Size = UDim2.fromOffset(134, 16), BorderSizePixel = 0 }, card)
				corner(barBg, 6)
				local fill = new("Frame", { BackgroundColor3 = rarityCol, Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, barBg)
				corner(fill, 6)
				local prog = new("TextLabel", { Text = "", Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = Color3.new(1,1,1), BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1), ZIndex = 3 }, barBg)
				new("UITextSizeConstraint", { MaxTextSize = 12 }, prog)
				lockedCards[#lockedCards + 1] = { fill = fill, label = prog, thresholdSec = thresholdSec }
			end
		end
	end
	refreshLockedProgress()
end

local function refreshFromServer()
	task.spawn(function()
		local ok, state = pcall(function() return GetGutSkins:InvokeServer() end)
		if ok and type(state) == "table" then
			lastState = state
			localEquipped = state.equipped or localEquipped
			if type(state.playtimeSec) == "number" then localPlaytimeSec = state.playtimeSec end
			rebuildSkins(state)
		end
	end)
end

GutSkinState.OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then return end
	lastState = state
	localEquipped = state.equipped or localEquipped
	if type(state.playtimeSec) == "number" then localPlaytimeSec = state.playtimeSec end -- re-sync the live timer
	if skinsScroll and skinsScroll.Visible then rebuildSkins(state) end
end)

-- PLAYTIME UNLOCK -> banner through the shared (no-overlap, event-gated) scheduler + refresh the grid
GutSkinUnlocked.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" or not info.id then return end
	if lastState.owned then lastState.owned[info.id] = true end
	if _G.enqueueReminderBanner then
		_G.enqueueReminderBanner("\xF0\x9F\x8E\x89 Unlocked the " .. (info.displayName or info.id) .. " gut skin!", "skinunlock_" .. info.id)
	end
	if skinsScroll and skinsScroll.Visible then rebuildSkins(lastState) end
end)

-- tick the local playtime mirror so locked progress bars move in real time while the menu is open
task.spawn(function()
	while true do
		task.wait(1)
		localPlaytimeSec = localPlaytimeSec + 1
		if skinsScroll and skinsScroll.Visible then refreshLockedProgress() end
	end
end)

-- =================== INJECT THE "SKINS" TAB INTO THE STOMACH MENU ===========
task.spawn(function()
	local gui = playerGui:WaitForChild("StomachShopGui", 120); if not gui then return end
	local panel = gui:WaitForChild("Panel", 30); if not panel then return end
	local tierList = panel:WaitForChild("TierList", 30)
	local currentLabel = panel:WaitForChild("CurrentLabel", 30)

	-- make room: drop the current-gut label + tier list down so a tab row fits above them
	currentLabel.Position = UDim2.fromOffset(10, 100)
	tierList.Position = UDim2.new(0, 10, 0, 143)
	tierList.Size = UDim2.new(1, -20, 1, -148)

	-- skins grid lives in the same rect as the tier list, hidden until the Skins tab is picked
	skinsScroll = new("ScrollingFrame", { Name = "SkinsList", Visible = false, BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(0, 10, 0, 143), Size = UDim2.new(1, -20, 1, -148),
		ScrollingEnabled = true, ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y,  -- same setup as PetInventory/Locker
		ScrollBarThickness = 6, ScrollBarImageColor3 = Color3.fromRGB(255, 215, 0), ClipsDescendants = true }, panel)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 150), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, skinsScroll)
	new("UIPadding", { PaddingTop = UDim.new(0,6), PaddingBottom = UDim.new(0,6) }, skinsScroll)

	-- two tabs at the top
	local function mkTab(text, x)
		local b = new("TextButton", { Text = text, Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.new(1,1,1),
			BackgroundColor3 = Color3.fromRGB(20, 90, 200), Position = UDim2.fromOffset(x, 62), Size = UDim2.fromOffset(150, 32), BorderSizePixel = 0 }, panel)
		corner(b, 8); stroke(b, Color3.fromRGB(255,255,255), 2)
		new("UITextSizeConstraint", { MaxTextSize = 18 }, b)
		return b
	end
	local tabStomachs = mkTab("STOMACHS", 10)
	local tabSkins    = mkTab("SKINS", 168)

	local function showTab(which)
		local skinsOn = (which == "skins")
		skinsScroll.Visible = skinsOn
		tierList.Visible = not skinsOn
		currentLabel.Visible = not skinsOn
		tabSkins.BackgroundColor3    = skinsOn and Color3.fromRGB(40, 140, 255) or Color3.fromRGB(18, 70, 150)
		tabStomachs.BackgroundColor3 = skinsOn and Color3.fromRGB(18, 70, 150) or Color3.fromRGB(40, 140, 255)
		if skinsOn then refreshFromServer() end -- pull the latest owned/equipped each time Skins opens
	end
	tabStomachs.MouseButton1Click:Connect(function() showTab("stomachs") end)
	tabSkins.MouseButton1Click:Connect(function() showTab("skins") end)
	-- whenever the Stomach menu re-opens, default back to the Stomachs (tiers) tab
	gui:GetPropertyChangedSignal("Enabled"):Connect(function() if gui.Enabled then showTab("stomachs") end end)
	showTab("stomachs")
end)

-- know the equipped skin early (so Rainbow animates even before the menu is opened)
refreshFromServer()

print("[GutSkinClient] ready (Skins tab in Stomach menu, equip + rainbow animation)")
