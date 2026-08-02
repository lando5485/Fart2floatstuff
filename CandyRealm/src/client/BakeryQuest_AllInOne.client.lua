--======================================================================
-- BakeryQuest_AllInOne.client.lua  (LocalScript, per-player)
--======================================================================
-- "THE GREAT BAKE-OFF" -- ISLAND 15. Two recipes, one chicken, zero patience.
--
--   1  TALK     The Baker gives you the quest and shows two recipe cards:
--                 BROWNIE  -- 3 Cocoa, 2 Sugar, 1 Butter, 2 Eggs
--                 BROOKIE  -- 2 Cocoa, 2 Dough, 2 Sugar, 1 Butter, 2 Eggs
--   2  GATHER   Cocoa / Sugar / Butter / Dough are scattered around the island.
--               EGGS come from the CHICKEN: tap it, it squawks, hops, lays an
--               egg behind itself and scurries off. Tap it again for more.
--   3  MIX      Bring everything to the giant mixing bowl (built on your
--               "Mixer" part). The ingredients pour in one by one, then you
--               STIR -- press the prompt 8 times, the spoon sweeps, the batter
--               darkens -- and out comes a baking pan, carried in your hands.
--   4  BAKE     Walk the pan to EITHER oven (built on your two "Oven" parts).
--               The pan slides in, the door shuts -- and the OVEN HUD opens:
--               heat drains, the STOKE THE FIRE button throws it back, and the
--               bake fills fast only while the needle holds the orange sweet
--               zone. Glow and chimney smoke track the fire. DING! -- the door
--               opens and a finished tray slides onto the rack.
--   5  DELIVER  Carry the tray back to the Baker. Coins, fireworks, done.
--   *  BONUS    Talk to him again afterward and he offers the OTHER recipe
--               for a second, smaller reward. Both recipes get baked.
--
-- WHAT THE WORLD PROVIDES (names ignore case/spaces/underscores):
--   Mixer        x1   a plain block. The mixing station is BUILT on it.
--   Oven         x2   plain blocks. A brick oven is BUILT on each.
--   ChickenPart  x1   a plain block. The chicken spawns here and wanders
--                     around it. The block itself is hidden.
--   (optional) any model with "npc" in its name near the Mixer becomes the
--   quest giver; with none there, a Baker is BUILT beside the station.
--
-- Everything is client-side and per-player, like every other island quest.
-- STREAMING-SAFE: island 15 is far from spawn, so the marker parts trickle
-- in late -- the scanner below keeps looking and builds each station the
-- moment its marker appears. Positions are cached, so a marker streaming
-- back OUT afterwards breaks nothing.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local TextChatService   = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

print("[Bakery] >>> VERSION bakeoff-v1 loaded <<<")

-- ============================================================================
-- CONFIG
-- ============================================================================
local MIXER_NAME    = "mixer"        -- exact names after norm() -- see below
local OVEN_NAME     = "oven"
local CHICKEN_NAME  = "chickenpart"
local ZONE_NAME     = "chickenzone"  -- optional: an invisible pen. The chicken roams
                                     -- anywhere inside this part's footprint and
                                     -- never leaves it. No part -> old radius wander.
local ISLAND_PREFIX = "island15"     -- Baker parents under this model if it exists,
                                     -- so the NPC guide arrows can find him
local MARKER_RANGE  = 800            -- an Oven/ChickenPart must be this close to the
                                     -- Mixer to count as island 15's, so a same-named
                                     -- part on another island is never grabbed
local NPC_MAX_DIST  = 150            -- an existing *npc* model this close to the Mixer
                                     -- becomes the quest giver instead of the built Baker
local TALK_DIST     = 12
local BANNER_RANGE  = 420            -- objective banner shows only near the bakery

local MIXER_SCALE   = 5              -- the whole mixing station, grown in place around
                                     -- its base -- one dial each if the island outgrows them
local OVEN_SCALE    = 5              -- both brick ovens, same treatment
local STIRS_NEEDED  = 8              -- prompt presses to finish the batter
-- the oven HUD minigame: heat bleeds away, STOKE throws it back, and the bake
-- only fills fast while the needle sits in the orange sweet zone
local ZONE_LO, ZONE_HI = 42, 88      -- the sweet zone, on a 0..100 heat bar
local HEAT_DECAY    = 20             -- heat lost per second
local HEAT_STOKE    = 24             -- heat gained per STOKE press (~1 press/sec holds it)
local BAKE_FAST     = 8.5            -- %/sec in the zone  -> ~12s bake played well
local BAKE_SLOW     = 2.6            -- %/sec otherwise    -> a closed HUD still finishes
local EGG_COOLDOWN  = 2.5            -- seconds between chicken taps
local WANDER_R      = 45             -- studs the chicken strolls from its spawn block

local COIN_REWARD   = 2000           -- first bake
local BONUS_REWARD  = 1000           -- baking the second recipe afterward

-- the two recipes. `need` is ingredient -> count; eggs ONLY come from the chicken.
local RECIPES = {
	brownie = {
		title = "BROWNIE",
		need  = { cocoa = 3, sugar = 2, butter = 1, egg = 2 },
		batter = Color3.fromRGB(72, 44, 26),      -- what the bowl / pan fill looks like
		line   = "A classic! Dense, dark and fudgy.",
	},
	brookie = {
		title = "BROOKIE",
		need  = { cocoa = 2, dough = 2, sugar = 2, butter = 1, egg = 2 },
		batter = Color3.fromRGB(140, 100, 58),    -- half cookie dough, so lighter
		line   = "Half brownie, half cookie. ALL genius.",
	},
}

-- ingredient look-up: label + emoji for banners, and how the pickup prop is built
local ING = {
	cocoa  = { label = "Cocoa",  emoji = "\xF0\x9F\x8D\xAB" },
	sugar  = { label = "Sugar",  emoji = "\xF0\x9F\x8D\xAC" },
	butter = { label = "Butter", emoji = "\xF0\x9F\xA7\x88" },
	dough  = { label = "Dough",  emoji = "\xF0\x9F\x8D\xAA" },
	egg    = { label = "Eggs",   emoji = "\xF0\x9F\xA5\x9A" },
}
-- stable banner order (pairs() order isn't)
local ING_ORDER = { "cocoa", "dough", "sugar", "butter", "egg" }

local E_CHICK  = "\xF0\x9F\x90\x94"
local E_BOWL   = "\xF0\x9F\xA5\xA3"
local E_FIRE   = "\xF0\x9F\x94\xA5"
local E_BELL   = "\xF0\x9F\x94\x94"
local E_SPARK  = "\xE2\x9C\xA8"
local E_TIMER  = "\xE2\x8F\xB0"

-- warm bakery palette, one table (Luau register budget -- same trick as Smores)
local PAL = {
	CREAM   = Color3.fromRGB(255, 246, 232),
	CRUST   = Color3.fromRGB(196, 148, 92),
	CHOC    = Color3.fromRGB(92, 54, 28),
	CHOC_D  = Color3.fromRGB(58, 34, 18),
	CHOC_HI = Color3.fromRGB(140, 90, 52),
	DOUGHY  = Color3.fromRGB(226, 190, 132),
	BRICK   = Color3.fromRGB(158, 84, 62),
	BRICK_D = Color3.fromRGB(118, 60, 44),
	STONE   = Color3.fromRGB(150, 140, 130),
	IRON    = Color3.fromRGB(72, 70, 74),
	WOOD    = Color3.fromRGB(178, 126, 78),
	WOOD_D  = Color3.fromRGB(134, 92, 56),
	GLOW    = Color3.fromRGB(255, 148, 54),
	GLOW_H  = Color3.fromRGB(255, 224, 150),
	SUGAR   = Color3.fromRGB(252, 252, 255),
	BUTTER  = Color3.fromRGB(255, 214, 96),
	EGGSH   = Color3.fromRGB(250, 244, 228),
	FEATHER = Color3.fromRGB(248, 244, 236),
	FEATH_D = Color3.fromRGB(220, 212, 198),
	COMB    = Color3.fromRGB(226, 64, 58),
	BEAK    = Color3.fromRGB(255, 168, 54),
	PINK    = Color3.fromRGB(244, 156, 186),
	SKIN    = Color3.fromRGB(255, 204, 158),
	TEXTC   = Color3.fromRGB(74, 40, 22),
	HINTC   = Color3.fromRGB(158, 130, 108),
	PANEL   = Color3.fromRGB(255, 246, 236),
	SMOKE   = Color3.fromRGB(120, 112, 104),
}

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s) return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", "")) end

local function mk(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function tween(inst, t, goal, style, dir)
	local tw = TweenService:Create(inst,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play(); return tw
end

local function frameOf(inst)
	if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
	return inst:GetBoundingBox()
end

-- the BOTTOM face of a marker block, keeping its heading -- stations build up from
-- this. Building on the TOP surface floated everything a whole marker-height too
-- high; the marker's base is where it visibly sits, so that is the ground line.
local function baseFrameOf(part)
	local cf, sz = frameOf(part)
	return CFrame.new(Vector3.new(cf.Position.X, cf.Position.Y - sz.Y * 0.5, cf.Position.Z))
		* (cf - cf.Position)
end

local function hideMarker(src)
	local parts = src:IsA("BasePart") and { src } or src:GetDescendants()
	for _, p in ipairs(parts) do
		if p:IsA("BasePart") then
			p.Transparency = 1; p.CanCollide = false; p.CanQuery = false; p.Anchored = true
		end
	end
end

local function hrpOf()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- everything this quest builds lives in one folder, so the ground raycast can
-- ignore it all in one line (a chicken standing on its own egg counts as ground
-- otherwise, and it slowly climbs into the sky)
local bakeFolder = Instance.new("Folder")
bakeFolder.Name = "BakeryQuestLocal"; bakeFolder.Parent = Workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshRayFilter()
	local ex = { bakeFolder }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then table.insert(ex, pl.Character) end
	end
	rayParams.FilterDescendantsInstances = ex
end

local function groundAt(x, z, refY)
	refreshRayFilter()
	local hit = Workspace:Raycast(Vector3.new(x, refY + 60, z), Vector3.new(0, -220, 0), rayParams)
	return hit and hit.Position or nil
end

-- ============================================================================
-- STATE
-- ============================================================================
-- step: 0 talk  2 gather (incl. "bring it to the bowl")  3 mixing  4 carry pan
--       5 baking  6 carry tray  7 done
local step         = 0
local recipe       = nil        -- "brownie" | "brookie"
local have         = {}         -- ingredient -> count collected
local stirs        = 0
local bonusRound   = false      -- true while baking the second recipe
local bonusDone    = false
local mixerAt      = nil        -- cached CFrame of the mixing station (banner gate + scatter)
local bakerHead    = nil
local refreshBanner, flashBanner, showBubble, hideBubble, openChooser
local refreshPrompts            -- re-evaluates every station prompt after a state change

_G.bakeryQuestComplete = false
_G.bakeryQuestStep     = nil    -- small grey detail text for the Quest Journal

local function needOf() return recipe and RECIPES[recipe].need or nil end

local function allGathered()
	local need = needOf(); if not need then return false end
	for k, n in pairs(need) do if (have[k] or 0) < n then return false end end
	return true
end

local function stillNeeds(kind)
	local need = needOf(); if not need then return false end
	return (have[kind] or 0) < (need[kind] or 0)
end

-- ============================================================================
-- OBJECTIVE BANNER (top-center, proximity-gated to the bakery)
-- ============================================================================
local objGui = Instance.new("ScreenGui")
objGui.Name = "BakeryObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7
objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5, 0); objFrame.Position = UDim2.new(0.5, 0, 0, 12)
objFrame.Size = UDim2.new(0, 560, 0, 52); objFrame.BackgroundColor3 = PAL.PANEL
objFrame.Visible = false; objFrame.Parent = objGui
do
	Instance.new("UICorner", objFrame).CornerRadius = UDim.new(0, 16)
	local s = Instance.new("UIStroke"); s.Color = PAL.CRUST; s.Thickness = 3; s.Parent = objFrame
end
local objLabel = Instance.new("TextLabel")
objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1, 1)
objLabel.Font = Enum.Font.FredokaOne; objLabel.TextColor3 = PAL.TEXTC
objLabel.TextScaled = true; objLabel.Parent = objFrame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 21; sz.Parent = objLabel
	local pd = Instance.new("UIPadding")
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = objLabel
end

-- "🍫 2/3   🍬 1/2   🥚 0/2" -- the whole shopping list in one line
local function shoppingList()
	local need, bits = needOf(), {}
	if not need then return "" end
	for _, k in ipairs(ING_ORDER) do
		local n = need[k]
		if n then bits[#bits + 1] = ("%s %d/%d"):format(ING[k].emoji, math.min(have[k] or 0, n), n) end
	end
	return table.concat(bits, "   ")
end

local function baseObjectiveText()
	local R = recipe and RECIPES[recipe]
	if step >= 7 then
		return bonusDone and (E_SPARK .. " Both recipes baked. The Baker is thrilled!")
			or (E_SPARK .. " Bake-off complete! Ask the Baker about the OTHER recipe...")
	elseif step == 6 then
		return ("%s Carry the %s tray back to the Baker!"):format(E_SPARK, R.title)
	elseif step == 5 then
		return E_FIRE .. " Baking..."
	elseif step == 4 then
		return E_FIRE .. " Carry the pan to an OVEN!"
	elseif step == 3 then
		return ("%s STIR the bowl!  %d/%d"):format(E_BOWL, stirs, STIRS_NEEDED)
	elseif step == 2 then
		if allGathered() then return E_BOWL .. " All ingredients! Take them to the MIXING BOWL!" end
		return shoppingList() .. "   (" .. E_CHICK .. " tap the chicken for eggs!)"
	end
	return E_BOWL .. " Talk to the Baker to start the Bake-Off!"
end

local flashToken = 0
refreshBanner = function()
	objLabel.Text = baseObjectiveText()
	-- journal detail: a couple of words on where you are in the bake
	local d
	if step == 2 and recipe then
		local need, got, total = needOf(), 0, 0
		for k, n in pairs(need) do total += n; got += math.min(have[k] or 0, n) end
		d = ("gathering %d/%d"):format(got, total)
	elseif step == 3 then d = "mixing"
	elseif step == 4 then d = "to the oven!"
	elseif step == 5 then d = "baking"
	elseif step == 6 then d = "deliver it!"
	end
	_G.bakeryQuestStep = d
end
flashBanner = function(text, seconds)
	flashToken += 1; local tok = flashToken
	objLabel.Text = text
	task.delay(seconds or 2.5, function() if tok == flashToken then refreshBanner() end end)
end

task.spawn(function()
	while true do
		local hrp = hrpOf()
		objFrame.Visible = (mixerAt ~= nil and hrp ~= nil
			and (hrp.Position - mixerAt.Position).Magnitude <= BANNER_RANGE)
		task.wait(0.4)
	end
end)

-- ============================================================================
-- SPEECH BUBBLE (same paged look as the other island quests)
-- ============================================================================
hideBubble = function(adornee)
	local prev = adornee and adornee:FindFirstChild("SpeechBubble")
	if prev then prev:Destroy() end
end
showBubble = function(adornee, text, persist, footer)
	hideBubble(adornee)
	local bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"; bb.Adornee = adornee; bb.Size = UDim2.new(0, 320, 0, 150)
	bb.StudsOffset = Vector3.new(0, 5.5, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local frame = Instance.new("Frame"); frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = PAL.PANEL; frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0; frame.Parent = bb
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 18)
	local st = Instance.new("UIStroke"); st.Color = PAL.CRUST; st.Thickness = 2
	st.Transparency = 0.3; st.Parent = frame
	local pd = Instance.new("UIPadding")
	pd.PaddingTop = UDim.new(0, 12); pd.PaddingBottom = UDim.new(0, 12)
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = frame
	local lbl = Instance.new("TextLabel")
	lbl.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.FredokaOne; lbl.Text = text
	lbl.TextColor3 = PAL.TEXTC; lbl.TextScaled = true; lbl.TextWrapped = true; lbl.Parent = frame
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = lbl
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1, 0.2)
		h.Position = UDim2.fromScale(0, 0.8); h.BackgroundTransparency = 1
		h.Font = Enum.Font.FredokaOne; h.Text = footer; h.TextColor3 = PAL.HINTC
		h.TextScaled = true; h.Parent = frame
		local hs = Instance.new("UITextSizeConstraint"); hs.MaxTextSize = 14; hs.Parent = h
	end
	bb.Parent = adornee
	if not persist then
		task.delay(8, function()
			if bb and bb.Parent == adornee and bb.Name == "SpeechBubble" then bb:Destroy() end
		end)
	end
end

-- ============================================================================
-- RECIPE CHOOSER -- two big cards, pick one. X closes it (never the backdrop);
-- talking to the Baker again reopens it.
-- ============================================================================
local chGui = Instance.new("ScreenGui")
chGui.Name = "BakeryRecipeChooser"; chGui.ResetOnSpawn = false; chGui.DisplayOrder = 12
chGui.IgnoreGuiInset = true; chGui.Enabled = false; chGui.Parent = PlayerGui

local chShade = Instance.new("Frame")   -- a Frame, NOT a button: backdrop taps close NOTHING
chShade.Size = UDim2.fromScale(1, 1); chShade.BackgroundColor3 = Color3.new(0, 0, 0)
chShade.BackgroundTransparency = 0.5; chShade.ZIndex = 1
chShade.Active = true                   -- ...but they also don't reach the world behind it
chShade.Parent = chGui

local chPanel = Instance.new("Frame")
chPanel.AnchorPoint = Vector2.new(0.5, 0.5); chPanel.Position = UDim2.fromScale(0.5, 0.5)
chPanel.Size = UDim2.new(0, 640, 0, 400); chPanel.BackgroundColor3 = PAL.PANEL
chPanel.BorderSizePixel = 0; chPanel.ZIndex = 2; chPanel.Parent = chGui
Instance.new("UICorner", chPanel).CornerRadius = UDim.new(0, 18)
do local s = Instance.new("UIStroke"); s.Color = PAL.CRUST; s.Thickness = 3; s.Parent = chPanel end

local chHead = Instance.new("TextLabel")
chHead.BackgroundTransparency = 1; chHead.Position = UDim2.new(0, 24, 0, 14)
chHead.Size = UDim2.new(1, -110, 0, 40); chHead.Font = Enum.Font.FredokaOne
chHead.TextSize = 28; chHead.TextColor3 = PAL.TEXTC
chHead.TextXAlignment = Enum.TextXAlignment.Left; chHead.ZIndex = 3
chHead.Text = "Pick your bake!"; chHead.Parent = chPanel

local chClose = Instance.new("TextButton")
chClose.AnchorPoint = Vector2.new(1, 0); chClose.Position = UDim2.new(1, -16, 0, 16)
chClose.Size = UDim2.fromOffset(42, 42); chClose.BackgroundColor3 = PAL.CRUST
chClose.Text = "X"; chClose.Font = Enum.Font.FredokaOne; chClose.TextSize = 22
chClose.TextColor3 = Color3.new(1, 1, 1); chClose.BorderSizePixel = 0; chClose.ZIndex = 4
chClose.Parent = chPanel
Instance.new("UICorner", chClose).CornerRadius = UDim.new(0, 12)
chClose.MouseButton1Click:Connect(function() chGui.Enabled = false end)

local chosenCallback = nil     -- set by openChooser; the card buttons call it

local function recipeCard(key, x)
	local R = RECIPES[key]
	local card = Instance.new("Frame")
	card.Position = UDim2.new(0, x, 0, 68); card.Size = UDim2.new(0, 292, 0, 312)
	card.BackgroundColor3 = Color3.fromRGB(252, 238, 222); card.BorderSizePixel = 0
	card.ZIndex = 3; card.Parent = chPanel
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
	local st = Instance.new("UIStroke"); st.Color = R.batter; st.Thickness = 2.5; st.Parent = card

	local big = Instance.new("TextLabel")
	big.BackgroundTransparency = 1; big.Position = UDim2.new(0, 0, 0, 8)
	big.Size = UDim2.new(1, 0, 0, 64); big.Font = Enum.Font.FredokaOne; big.TextSize = 52
	big.Text = (key == "brownie") and ING.cocoa.emoji or (ING.dough.emoji .. ING.cocoa.emoji)
	big.ZIndex = 4; big.Parent = card

	local ttl = Instance.new("TextLabel")
	ttl.BackgroundTransparency = 1; ttl.Position = UDim2.new(0, 0, 0, 72)
	ttl.Size = UDim2.new(1, 0, 0, 34); ttl.Font = Enum.Font.FredokaOne; ttl.TextSize = 28
	ttl.TextColor3 = R.batter; ttl.Text = R.title; ttl.ZIndex = 4; ttl.Parent = card

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1; sub.Position = UDim2.new(0, 14, 0, 106)
	sub.Size = UDim2.new(1, -28, 0, 34); sub.Font = Enum.Font.GothamMedium; sub.TextSize = 13
	sub.TextColor3 = PAL.HINTC; sub.TextWrapped = true; sub.Text = R.line; sub.ZIndex = 4
	sub.Parent = card

	local list = Instance.new("TextLabel")
	list.BackgroundTransparency = 1; list.Position = UDim2.new(0, 14, 0, 144)
	list.Size = UDim2.new(1, -28, 0, 104); list.Font = Enum.Font.GothamBold; list.TextSize = 15
	list.TextColor3 = PAL.TEXTC; list.TextYAlignment = Enum.TextYAlignment.Top
	list.TextXAlignment = Enum.TextXAlignment.Left; list.ZIndex = 4
	local lines = {}
	for _, k in ipairs(ING_ORDER) do
		local n = R.need[k]
		if n then lines[#lines + 1] = ("%s  %d x %s"):format(ING[k].emoji, n, ING[k].label) end
	end
	list.Text = table.concat(lines, "\n"); list.Parent = card

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(0.5, 1); btn.Position = UDim2.new(0.5, 0, 1, -12)
	btn.Size = UDim2.new(1, -28, 0, 44); btn.BackgroundColor3 = R.batter
	btn.Font = Enum.Font.FredokaOne; btn.TextSize = 20; btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = "BAKE THIS!"; btn.BorderSizePixel = 0; btn.ZIndex = 4; btn.Parent = card
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
	btn.MouseButton1Click:Connect(function()
		if card.BackgroundTransparency > 0.3 then return end   -- greyed-out = locked
		if chosenCallback then chosenCallback(key) end
	end)
	return card
end
local cards = { brownie = recipeCard("brownie", 22), brookie = recipeCard("brookie", 326) }

-- lockTo: on the bonus round only the OTHER recipe is offered; its card stays
-- bright and the finished one fades out
openChooser = function(lockTo, onPick)
	for key, card in pairs(cards) do
		local locked = (lockTo ~= nil and key ~= lockTo)
		card.BackgroundTransparency = locked and 0.55 or 0
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("TextLabel") then d.TextTransparency = locked and 0.6 or 0 end
			if d:IsA("TextButton") then
				d.TextTransparency = locked and 0.6 or 0
				d.Text = locked and "ALREADY BAKED" or "BAKE THIS!"
			end
		end
	end
	chosenCallback = function(key)
		chGui.Enabled = false
		onPick(key)
	end
	chGui.Enabled = true
end

-- ============================================================================
-- FIREWORKS + WIN BANNER (the standard island celebration)
-- ============================================================================
local FW_COLORS = { Color3.fromRGB(255, 92, 138), Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(150, 235, 130), Color3.fromRGB(255, 205, 90), Color3.fromRGB(190, 130, 255) }

local function burst(atPos, color)
	for i = 1, 24 do
		local spark = mk({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5),
			Color = color, Material = Enum.Material.Neon })
		spark.CFrame = CFrame.new(atPos); spark.Parent = bakeFolder
		local dest = atPos + Vector3.new((i % 7) - 3, (i % 5), ((i * 3) % 7) - 3).Unit * 13
		tween(spark, 0.9, { CFrame = CFrame.new(dest), Transparency = 1,
			Size = Vector3.new(0.1, 0.1, 0.1) })
		Debris:AddItem(spark, 1)
	end
end

local function launchFireworks(fromPos)
	for i = 1, 3 do
		task.delay(i * 0.35, function()
			local rocket = mk({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6),
				Color = PAL.GLOW_H, Material = Enum.Material.Neon })
			local start = fromPos + Vector3.new((i - 2) * 6, 3, 0)
			local apex  = start + Vector3.new(0, 42 + i * 6, 0)
			rocket.CFrame = CFrame.new(start); rocket.Parent = bakeFolder
			local up = tween(rocket, 0.9, { CFrame = CFrame.new(apex) })
			up.Completed:Connect(function()
				burst(apex, FW_COLORS[((i - 1) % #FW_COLORS) + 1])
				rocket:Destroy()
			end)
		end)
	end
end

local function winBanner(text)
	local g = Instance.new("ScreenGui"); g.Name = "BakeryWin"; g.ResetOnSpawn = false
	g.DisplayOrder = 20; g.IgnoreGuiInset = true; g.Parent = PlayerGui
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, 0, 0.42, 0); f.Size = UDim2.new(0, 0, 0, 90)
	f.BackgroundColor3 = PAL.PANEL; f.Parent = g
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 18)
	local s = Instance.new("UIStroke"); s.Color = PAL.CRUST; s.Thickness = 4; s.Parent = f
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.FredokaOne; l.TextColor3 = PAL.TEXTC; l.TextScaled = true
	l.Text = text; l.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 24); pad.PaddingRight = UDim.new(0, 24); pad.Parent = l
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 32; sz.Parent = l
	tween(f, 0.5, { Size = UDim2.new(0, 640, 0, 90) }, Enum.EasingStyle.Back)
	task.delay(5, function()
		tween(f, 0.4, { BackgroundTransparency = 1 })
		tween(l, 0.4, { TextTransparency = 1 })
		task.delay(0.5, function() g:Destroy() end)
	end)
end

local function poofAt(pos, color)
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local s = mk({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4),
			Color = color or PAL.GLOW_H, Material = Enum.Material.Neon })
		s.CFrame = CFrame.new(pos); s.Parent = bakeFolder
		tween(s, 0.45, { CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 2.6, 1.4, math.sin(a) * 2.6)),
			Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05) })
		Debris:AddItem(s, 0.6)
	end
end

-- ============================================================================
-- CARRYING THINGS -- the pan and the tray are WELDED into the hands, not
-- anchored and re-positioned (an anchored prop fights the walk animation and
-- reads as floating -- same lesson as the Smores axe)
-- ============================================================================
local heldModel = nil      -- the pan/tray model currently welded on
local heldKind  = nil      -- "pan" | "tray", so a respawn can rebuild it

local function dropHeld()
	if heldModel then heldModel:Destroy(); heldModel = nil; heldKind = nil end
end

-- builds the prop AND welds it, held flat in front like a waiter's tray
local function giveHeld(kind)
	dropHeld()
	local char = player.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	if not hand then return end
	local R = RECIPES[recipe] or RECIPES.brownie

	local m = Instance.new("Model"); m.Name = "BakeryHeld"
	local function bit(props)
		props.Anchored = false; props.Massless = true; props.Parent = m
		return mk(props)
	end
	local root
	if kind == "pan" then
		root = bit({ Color = PAL.IRON, Size = Vector3.new(1.7, 0.3, 1.25), Material = Enum.Material.Metal })
		root.CFrame = CFrame.new()
		local fill = bit({ Color = R.batter, Size = Vector3.new(1.5, 0.18, 1.05) })
		fill.CFrame = CFrame.new(0, 0.14, 0)
		for _, sx in ipairs({ -1, 1 }) do
			local h = bit({ Color = PAL.IRON, Size = Vector3.new(0.3, 0.12, 0.5), Material = Enum.Material.Metal })
			h.CFrame = CFrame.new(sx * 0.98, 0.05, 0)
		end
	else -- tray of finished goods
		root = bit({ Color = PAL.BUTTER, Size = Vector3.new(1.9, 0.16, 1.35), Reflectance = 0.08 })
		root.CFrame = CFrame.new()
		for gx = -1, 1 do
			for gz = 0, 1 do
				-- brookie trays alternate brownie squares with cookie blobs
				local isCookie = (recipe == "brookie") and ((gx + gz) % 2 == 0)
				local sq = bit({
					Color = isCookie and PAL.DOUGHY or PAL.CHOC,
					Shape = isCookie and Enum.PartType.Ball or Enum.PartType.Block,
					Size = isCookie and Vector3.new(0.52, 0.34, 0.52) or Vector3.new(0.46, 0.3, 0.46),
				})
				sq.CFrame = CFrame.new(gx * 0.55, 0.22, (gz - 0.5) * 0.6)
			end
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local wc = Instance.new("WeldConstraint"); wc.Part0 = root; wc.Part1 = d; wc.Parent = root
		end
	end
	m.PrimaryPart = root
	m.Parent = char
	local w = Instance.new("Weld")
	w.Part0 = hand; w.Part1 = root
	w.C0 = CFrame.new(0, -0.35, -1.0) * CFrame.Angles(0, math.rad(90), 0)
	w.Parent = root
	heldModel, heldKind = m, kind
end

-- a respawn takes the weld (and the model) down with the old character, so the
-- STEP decides what belongs back in your hands, not what was held a second ago
player.CharacterAdded:Connect(function()
	heldModel = nil; heldKind = nil
	task.delay(1.6, function()
		if step == 4 then giveHeld("pan") elseif step == 6 then giveHeld("tray") end
	end)
end)

-- ============================================================================
-- INGREDIENT PICKUPS -- scattered around the mixing station, one prop per
-- item needed. Eggs are NOT scattered; the chicken is the only egg source.
-- ============================================================================
local scattered = {}    -- live pickup models, cleared between rounds

local function buildIngredientProp(kind, at)
	local m = Instance.new("Model"); m.Name = "BakeryPickup"
	local base = CFrame.new(at + Vector3.new(0, 1.1, 0))
	local main
	if kind == "cocoa" then
		main = mk({ Shape = Enum.PartType.Ball, Color = PAL.CHOC, Size = Vector3.new(1.8, 1.15, 1.15), CanQuery = true })
		main.CFrame = base; main.Parent = m
		local ridge = mk({ Shape = Enum.PartType.Ball, Color = PAL.CHOC_HI, Size = Vector3.new(1.4, 0.5, 0.9) })
		ridge.CFrame = base * CFrame.new(0, 0.35, 0); ridge.Parent = m
	elseif kind == "sugar" then
		main = mk({ Color = PAL.SUGAR, Size = Vector3.new(1.0, 1.0, 1.0), Reflectance = 0.12, CanQuery = true })
		main.CFrame = base; main.Parent = m
		local c2 = mk({ Color = PAL.SUGAR, Size = Vector3.new(0.8, 0.8, 0.8), Reflectance = 0.12 })
		c2.CFrame = base * CFrame.new(0.45, -0.15, 0.3) * CFrame.Angles(0, math.rad(25), 0); c2.Parent = m
		local c3 = mk({ Color = PAL.SUGAR, Size = Vector3.new(0.7, 0.7, 0.7), Reflectance = 0.12 })
		c3.CFrame = base * CFrame.new(-0.3, 0.75, -0.1) * CFrame.Angles(0, math.rad(40), 0); c3.Parent = m
	elseif kind == "butter" then
		main = mk({ Color = PAL.BUTTER, Size = Vector3.new(1.6, 0.8, 1.0), CanQuery = true })
		main.CFrame = base; main.Parent = m
		local pat = mk({ Color = Color3.fromRGB(255, 234, 150), Size = Vector3.new(0.9, 0.4, 0.7) })
		pat.CFrame = base * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, math.rad(15), 0); pat.Parent = m
	else -- dough
		main = mk({ Shape = Enum.PartType.Ball, Color = PAL.DOUGHY, Size = Vector3.new(1.5, 1.2, 1.5), CanQuery = true })
		main.CFrame = base; main.Parent = m
		for i = 1, 3 do
			local chip = mk({ Color = PAL.CHOC_D, Size = Vector3.new(0.28, 0.28, 0.28) })
			chip.CFrame = base * CFrame.new(math.cos(i * 2.1) * 0.5, 0.45, math.sin(i * 2.1) * 0.5)
			chip.Parent = m
		end
	end
	m.PrimaryPart = main

	local hl = Instance.new("Highlight"); hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(255, 210, 120); hl.OutlineTransparency = 0.2
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = m; hl.Parent = m
	local glow = Instance.new("PointLight"); glow.Color = PAL.GLOW_H
	glow.Brightness = 1.2; glow.Range = 7; glow.Parent = main
	m.Parent = bakeFolder
	return m, main
end

local function wirePickup(m, main, kind, idx)
	-- gentle bob + spin so it reads as a pickup from across the field. The loop
	-- stops the moment it's taken -- PivotTo would otherwise fight the collect
	-- tween and snap the parts back every frame.
	task.spawn(function()
		local b, t = m:GetPivot(), idx * 0.7
		while m.Parent and not m:GetAttribute("Taken") do
			t += 0.06
			m:PivotTo(b * CFrame.new(0, math.sin(t) * 0.3, 0) * CFrame.Angles(0, t * 0.5, 0))
			task.wait(0.03)
		end
	end)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take"; prompt.ObjectText = ING[kind].label
	prompt.HoldDuration = 0; prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false; prompt.Parent = main

	local taken = false
	prompt.Triggered:Connect(function()
		if taken then return end
		if step ~= 2 then return end
		if not stillNeeds(kind) then
			flashBanner(("%s You have enough %s already!"):format(ING[kind].emoji, ING[kind].label), 2)
			return
		end
		taken = true
		m:SetAttribute("Taken", true)
		have[kind] = (have[kind] or 0) + 1
		scattered[m] = nil
		poofAt(m:GetPivot().Position, PAL.GLOW_H)
		-- the prop arcs to you and shrinks away -- "picked up", not "vanished"
		local hrp = hrpOf()
		prompt:Destroy()
		if hrp then
			local goal = hrp.Position + Vector3.new(0, 1, 0)
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					tween(d, 0.35, { CFrame = CFrame.new(goal), Size = d.Size * 0.1, Transparency = 1 })
				end
			end
		end
		Debris:AddItem(m, 0.5)
		refreshBanner()
		if refreshPrompts then refreshPrompts() end
		if allGathered() then
			flashBanner(E_BOWL .. " That's everything! To the MIXING BOWL!", 3)
			if bakerHead then showBubble(bakerHead, "That's the lot! Get mixing!", false) end
		end
	end)
end

local function clearScattered()
	for m in pairs(scattered) do if m.Parent then m:Destroy() end end
	scattered = {}
end

-- one prop per item still needed, on a golden-angle spiral around the mixer --
-- deterministic (no random: this must land the same every respawn), spread out,
-- and snapped to the ground with a raycast so nothing floats or buries
local function scatterIngredients()
	clearScattered()
	if not (mixerAt and recipe) then return end
	local need, idx = needOf(), 0
	for _, kind in ipairs(ING_ORDER) do
		local n = (kind ~= "egg") and (need[kind] or 0) or 0
		for _ = 1, n do
			idx += 1
			local ang = idx * 2.39996              -- golden angle: never clumps, never lines up
			local rad = 28 + ((idx * 31) % 75)
			local x = mixerAt.Position.X + math.cos(ang) * rad
			local z = mixerAt.Position.Z + math.sin(ang) * rad
			local g = groundAt(x, z, mixerAt.Position.Y)
			-- a spot hanging off the island's edge raycasts to nothing (or to some
			-- island far below) -- pull those in close instead of losing the item
			if not g or math.abs(g.Y - mixerAt.Position.Y) > 60 then
				local rad2 = 12 + (idx * 7) % 14
				g = groundAt(mixerAt.Position.X + math.cos(ang) * rad2,
					mixerAt.Position.Z + math.sin(ang) * rad2, mixerAt.Position.Y)
					or (mixerAt.Position + Vector3.new(math.cos(ang) * rad2, 0, math.sin(ang) * rad2))
			end
			local m, main = buildIngredientProp(kind, g)
			wirePickup(m, main, kind, idx)
			scattered[m] = true
		end
	end
	print(("[Bakery] %d ingredient(s) scattered for the %s"):format(idx, recipe))
end

-- ============================================================================
-- THE CHICKEN -- built at "ChickenPart", wanders around it, and TAP = EGG
-- ============================================================================
local chicken, chickenOrigin
local chickenMode = "stroll"     -- stroll | pause | flee
local lastTap     = 0
local zoneCF, zoneHalf           -- the "chicken zone" pen, once it streams in
local zoneTopY                   -- the pen plate's TOP surface: the hidden marker is
                                 -- unraycastable, so this Y is the floor of record --
                                 -- chicken, nest and eggs all seat on it directly
local nestModel                  -- so the nest can be re-seated when the zone arrives

-- clamp a world position into the pen's footprint (a margin in from the walls,
-- in the ZONE's own object space, so a rotated pen still works)
local function clampToZone(pos)
	if not zoneCF then return pos end
	local o = zoneCF:PointToObjectSpace(pos)
	local hx = math.max(1, zoneHalf.X - 1.5)
	local hz = math.max(1, zoneHalf.Z - 1.5)
	local cx, cz = math.clamp(o.X, -hx, hx), math.clamp(o.Z, -hz, hz)
	if cx == o.X and cz == o.Z then return pos end
	return (zoneCF * CFrame.new(cx, o.Y, cz)).Position
end

-- a fresh stroll destination: anywhere in the pen when there is one, the old
-- home-radius ring otherwise. Clock-derived, no math.random (deterministic).
local function pickWanderTarget(now)
	if zoneCF then
		local hx = math.max(2, zoneHalf.X - 3)
		local hz = math.max(2, zoneHalf.Z - 3)
		local ox = ((now * 7.3) % (hx * 2)) - hx
		local oz = ((now * 11.1) % (hz * 2)) - hz
		return (zoneCF * CFrame.new(ox, 0, oz)).Position
	end
	local a = (now * 0.7) % (math.pi * 2)
	local r = 8 + (now * 13) % (WANDER_R - 8)
	return chickenOrigin + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- a feeler ray at chest height along the walk direction: solid things (the
-- ovens, the counter, island rocks) turn her around instead of being clipped
-- through. RespectCanCollide, so decor and pickups don't spook her.
local obsParams = RaycastParams.new()
obsParams.FilterType = Enum.RaycastFilterType.Exclude
obsParams.RespectCanCollide = true
local function obstacleAhead(from, dir)
	if dir.Magnitude < 0.01 then return false end
	local ex = { chicken }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then table.insert(ex, pl.Character) end
	end
	obsParams.FilterDescendantsInstances = ex
	return Workspace:Raycast(from + Vector3.new(0, 1.2, 0), dir.Unit * 2.4, obsParams) ~= nil
end

local function buildChicken(originPos)
	local m = Instance.new("Model"); m.Name = "BakeryChicken"
	local at = CFrame.new(originPos + Vector3.new(0, 1.05, 0))
	local function bit(props, cf)
		props.Parent = m
		local p = mk(props); p.CFrame = at * cf; return p
	end
	-- plump body, tiny head, big personality
	local body = bit({ Shape = Enum.PartType.Ball, Color = PAL.FEATHER,
		Size = Vector3.new(1.9, 1.7, 2.3), CanQuery = true }, CFrame.new())
	bit({ Shape = Enum.PartType.Ball, Color = PAL.FEATH_D, Size = Vector3.new(1.5, 1.1, 1.2) },
		CFrame.new(0, -0.15, 0.75))                                   -- tail puff
	local head = bit({ Shape = Enum.PartType.Ball, Color = PAL.FEATHER,
		Size = Vector3.new(0.95, 0.95, 0.95), CanQuery = true }, CFrame.new(0, 0.95, -1.0))
	bit({ Color = PAL.COMB, Size = Vector3.new(0.18, 0.5, 0.6) }, CFrame.new(0, 1.5, -1.0))
	bit({ Color = PAL.COMB, Size = Vector3.new(0.16, 0.35, 0.25) }, CFrame.new(0, 0.62, -1.35)) -- wattle
	bit({ Color = PAL.BEAK, Size = Vector3.new(0.3, 0.22, 0.5) }, CFrame.new(0, 0.95, -1.5))
	for _, sx in ipairs({ -1, 1 }) do
		bit({ Shape = Enum.PartType.Ball, Color = Color3.new(0, 0, 0),
			Size = Vector3.new(0.16, 0.16, 0.16) }, CFrame.new(sx * 0.28, 1.1, -1.32))
		bit({ Shape = Enum.PartType.Ball, Color = PAL.FEATH_D, Size = Vector3.new(0.5, 1.0, 1.4) },
			CFrame.new(sx * 0.85, 0.1, 0.1) * CFrame.Angles(0, 0, math.rad(sx * 14)))  -- wings
		bit({ Color = PAL.BEAK, Size = Vector3.new(0.14, 0.85, 0.14) }, CFrame.new(sx * 0.35, -1.05, 0))
		bit({ Color = PAL.BEAK, Size = Vector3.new(0.4, 0.1, 0.5) }, CFrame.new(sx * 0.35, -1.5, -0.1))
	end
	m.PrimaryPart = body
	m.WorldPivot = at
	m.Parent = bakeFolder

	-- her nest, planted at the spawn block: it explains where the eggs come from
	-- and gives the wandering somewhere to read as "home"
	local nest = Instance.new("Model"); nest.Name = "ChickenNest"; nest.Parent = bakeFolder
	nestModel = nest
	local ng = (zoneTopY and Vector3.new(originPos.X, zoneTopY, originPos.Z))
		or groundAt(originPos.X, originPos.Z, originPos.Y + 5) or originPos
	local ncf = CFrame.new(ng + Vector3.new(0, 0.3, 0))
	local pad = mk({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(214, 178, 110),
		Size = Vector3.new(0.6, 4.6, 4.6), Parent = nest })
	pad.CFrame = ncf * CFrame.Angles(0, 0, math.rad(90))
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local straw = mk({ Color = Color3.fromRGB(190, 152, 88),
			Size = Vector3.new(0.4, 0.5, 1.7), Parent = nest })
		straw.CFrame = ncf * CFrame.new(math.cos(a) * 2.0, 0.35, math.sin(a) * 2.0)
			* CFrame.Angles(0, -a, math.rad(14))
	end

	-- both input paths on the body AND head: prompt for controller/mobile
	-- radial, ClickDetector for a straight mouse tap
	for _, part in ipairs({ body, head }) do
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Tap"; prompt.ObjectText = "Chicken"; prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10; prompt.RequiresLineOfSight = false
		prompt.Parent = part
		prompt.Triggered:Connect(function() m:SetAttribute("Tapped", os.clock()) end)
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 24; click.Parent = part
		click.MouseClick:Connect(function(who)
			if who == player then m:SetAttribute("Tapped", os.clock()) end
		end)
	end
	return m
end

local function layEgg(fromCF)
	-- the egg pops out the BACK, arcs to the ground, and sits there with a prompt.
	-- With a pen plate, the egg seats ON the plate (clamped inside it) -- the
	-- hidden marker can't be raycast, so its stored top Y is the floor.
	local behind = fromCF * CFrame.new(0, 0.2, 2.0)
	local g
	if zoneCF and zoneTopY then
		local p = clampToZone(behind.Position)
		g = Vector3.new(p.X, zoneTopY, p.Z)
	else
		g = groundAt(behind.Position.X, behind.Position.Z, behind.Position.Y)
			or (behind.Position - Vector3.new(0, 1.5, 0))
	end
	local egg = mk({ Shape = Enum.PartType.Ball, Color = PAL.EGGSH,
		Size = Vector3.new(0.75, 0.95, 0.75), CanQuery = true })
	egg.CFrame = behind; egg.Parent = bakeFolder
	local glow = Instance.new("PointLight"); glow.Color = PAL.GLOW_H
	glow.Brightness = 1; glow.Range = 6; glow.Parent = egg
	tween(egg, 0.45, { CFrame = CFrame.new(g + Vector3.new(0, 0.5, 0)) }, Enum.EasingStyle.Bounce)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take"; prompt.ObjectText = "Egg"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false; prompt.Parent = egg
	local taken = false
	prompt.Triggered:Connect(function()
		if taken then return end
		if step == 2 and stillNeeds("egg") then
			taken = true
			have.egg = (have.egg or 0) + 1
			poofAt(egg.Position, PAL.GLOW_H)
			tween(egg, 0.3, { Size = egg.Size * 0.1, Transparency = 1 })
			Debris:AddItem(egg, 0.4)
			refreshBanner()
			if refreshPrompts then refreshPrompts() end
			if allGathered() then
				flashBanner(E_BOWL .. " That's everything! To the MIXING BOWL!", 3)
				if bakerHead then showBubble(bakerHead, "That's the lot! Get mixing!", false) end
			end
		else
			flashBanner(ING.egg.emoji .. " You don't need more eggs right now!", 2)
		end
	end)
	-- an unwanted egg tidies itself away
	task.delay(25, function() if egg.Parent and not taken then
		poofAt(egg.Position, PAL.EGGSH); egg:Destroy()
	end end)
end

-- one brain, driven by Heartbeat waits: stroll to a point near home, pause and
-- peck, repeat -- and on a tap, squawk + hop + egg + flee. All PivotTo on an
-- anchored model, so nothing here can be shoved off the island.
local function runChicken()
	task.spawn(function()
		local t, yaw = 0, 0
		local pos = chickenOrigin
		local target = pos
		local pauseUntil, fleeUntil = 0, 0
		local lastLay = 0
		while chicken and chicken.Parent do
			local dt = task.wait(0.05)
			t += dt
			local now = os.clock()

			-- a tap? (attribute set by prompt/click handlers on the parts)
			local tapped = chicken:GetAttribute("Tapped")
			if tapped and tapped > lastTap and now - lastLay >= EGG_COOLDOWN then
				lastTap = tapped; lastLay = now
				local cf = chicken:GetPivot()
				showBubble(chicken.PrimaryPart, "BAWK!!", false)
				poofAt(cf.Position + Vector3.new(0, 0.6, 0), PAL.FEATHER)   -- feathers fly
				-- hop first, THEN the egg -- the hop sells the effort
				task.spawn(function() task.wait(0.25); layEgg(chicken:GetPivot()) end)
				fleeUntil = now + 1.6
				-- flee AWAY from the player -- but never out of the pen
				local hrp = hrpOf()
				local away = hrp and (cf.Position - hrp.Position) * Vector3.new(1, 0, 1) or Vector3.new(1, 0, 0)
				away = away.Magnitude > 0.5 and away.Unit or Vector3.new(1, 0, 0)
				target = clampToZone(chickenOrigin
					+ ((cf.Position + away * 18) - chickenOrigin) * Vector3.new(1, 0, 1))
				chickenMode = "flee"
			end

			if chickenMode == "flee" and now >= fleeUntil then chickenMode = "stroll" end
			if chickenMode == "pause" and now >= pauseUntil then
				chickenMode = "stroll"
				target = pickWanderTarget(now)
			end

			local flat = (target - pos) * Vector3.new(1, 0, 1)
			local dist = flat.Magnitude
			if chickenMode ~= "pause" then
				if dist < 1.5 then
					chickenMode = "pause"
					pauseUntil = now + 1.2 + (now % 2)
				else
					local speed = (chickenMode == "flee") and 16 or 6
					local stepv = flat.Unit * math.min(dist, speed * dt)
					if obstacleAhead(pos, stepv) then
						-- something solid in the way: stop short and pick a new
						-- destination on the next tick rather than walking into it
						chickenMode = "pause"
						pauseUntil = now + 0.4
					else
						pos = clampToZone(pos + stepv)   -- the pen is a hard wall
						yaw = math.atan2(-stepv.X, -stepv.Z)
					end
				end
			end

			local y
			if zoneCF and zoneTopY then
				y = zoneTopY + 1.55            -- the pen plate IS the floor
			else
				local g = groundAt(pos.X, pos.Z, chickenOrigin.Y + 10)
				y = g and (g.Y + 1.55) or (chickenOrigin.Y + 1.55)
			end
			local wob = (chickenMode == "pause") and 0 or 1
			local hopY = 0
			if now - lastLay < 0.35 then hopY = math.sin((now - lastLay) / 0.35 * math.pi) * 1.6 end
			local peck = (chickenMode == "pause") and math.max(0, math.sin(t * 3)) * 18 or 0
			chicken:PivotTo(CFrame.new(pos.X, y + math.abs(math.sin(t * 9)) * 0.16 * wob + hopY, pos.Z)
				* CFrame.Angles(0, yaw, 0)
				* CFrame.Angles(math.rad(peck * 0.4), 0, math.sin(t * 9) * 0.06 * wob))
		end
	end)
end

-- ============================================================================
-- THE MIXING STATION -- built on your "Mixer" part
-- ============================================================================
local mixPrompt, batterDisc, spoonModel, spoonHome, bowlTopCF

local function buildMixer(part)
	local at = baseFrameOf(part)
	hideMarker(part)
	mixerAt = at
	-- a Model, not a Folder: the whole station is scaled up MIXER_SCALE at the end,
	-- and ScaleTo needs a Model with its pivot on the ground line to grow in place
	local f = Instance.new("Model"); f.Name = "MixingStation"; f.Parent = bakeFolder
	local function piece(props, where, parent)
		props.Parent = parent or f
		local p = mk(props); p.CFrame = where; return p
	end

	-- sturdy wooden counter for the bowl to sit on
	piece({ Color = PAL.WOOD, Size = Vector3.new(7.5, 0.7, 6.0), CanCollide = true, CastShadow = true },
		at * CFrame.new(0, 2.4, 0))
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(7.9, 0.25, 6.4) }, at * CFrame.new(0, 2.85, 0))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.7, 2.2, 0.7), CanCollide = true },
				at * CFrame.new(sx * 3.2, 1.1, sz * 2.4))
		end
	end

	-- THE BOWL: a fat cream cylinder with a rolled rim and a batter disc inside.
	-- The batter starts invisible and fades in as the ingredients go in.
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.CREAM, Size = Vector3.new(2.6, 5.2, 5.2),
		CastShadow = true }, at * CFrame.new(0, 4.3, 0) * CFrame.Angles(0, 0, math.rad(90)))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.PINK, Size = Vector3.new(0.5, 5.5, 5.5) },
		at * CFrame.new(0, 5.5, 0) * CFrame.Angles(0, 0, math.rad(90)))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.CHOC_D, Size = Vector3.new(0.2, 4.6, 4.6) },
		at * CFrame.new(0, 5.35, 0) * CFrame.Angles(0, 0, math.rad(90)))
	batterDisc = piece({ Shape = Enum.PartType.Cylinder, Color = PAL.CHOC,
		Size = Vector3.new(0.3, 4.4, 4.4), Transparency = 1 },
		at * CFrame.new(0, 5.42, 0) * CFrame.Angles(0, 0, math.rad(90)))
	bowlTopCF = at * CFrame.new(0, 6.4, 0)

	-- the wooden spoon, standing in the bowl; it sweeps a lap on every stir
	spoonModel = Instance.new("Model"); spoonModel.Name = "Spoon"; spoonModel.Parent = f
	spoonHome = at * CFrame.new(1.2, 6.6, 0) * CFrame.Angles(0, 0, math.rad(-16))
	local shaft = piece({ Color = PAL.WOOD, Size = Vector3.new(0.28, 3.4, 0.28) }, spoonHome, spoonModel)
	piece({ Shape = Enum.PartType.Ball, Color = PAL.WOOD_D, Size = Vector3.new(0.85, 1.1, 0.55) },
		spoonHome * CFrame.new(0, -1.85, 0), spoonModel)
	spoonModel.PrimaryPart = shaft
	spoonModel.WorldPivot = at * CFrame.new(0, 6.0, 0)      -- pivot at the bowl centre: PivotTo
	                                                        -- with a yaw = the spoon orbits

	-- set dressing: flour sack, sugar jar, a recipe card on a little stand
	piece({ Color = PAL.CREAM, Size = Vector3.new(1.6, 2.0, 1.4), CanCollide = true },
		at * CFrame.new(-2.6, 1.0, 2.9) * CFrame.Angles(0, math.rad(15), 0))
	piece({ Color = PAL.CRUST, Size = Vector3.new(1.7, 0.4, 1.5) },
		at * CFrame.new(-2.6, 2.0, 2.9) * CFrame.Angles(0, math.rad(15), math.rad(6)))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.SUGAR, Size = Vector3.new(1.1, 0.9, 0.9) },
		at * CFrame.new(2.8, 3.35, 2.2) * CFrame.Angles(0, 0, math.rad(90)))
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.15, 1.2, 1.6) },
		at * CFrame.new(3.3, 3.6, -1.8) * CFrame.Angles(0, math.rad(-25), math.rad(-12)))
	piece({ Color = PAL.CREAM, Size = Vector3.new(0.08, 1.0, 1.4) },
		at * CFrame.new(3.28, 3.62, -1.8) * CFrame.Angles(0, math.rad(-25), math.rad(-12)))

	-- pans and a rolling pin left out on the counter: a kitchen mid-shift, not a prop
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON, Size = Vector3.new(0.3, 1.7, 1.7) },
		at * CFrame.new(-2.5, 3.05, -1.9) * CFrame.Angles(0, 0, math.rad(90)))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON, Size = Vector3.new(0.3, 1.4, 1.4) },
		at * CFrame.new(-2.3, 3.4, -1.7) * CFrame.Angles(0, 0, math.rad(90)))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD, Size = Vector3.new(2.4, 0.42, 0.42) },
		at * CFrame.new(2.4, 3.1, -0.9) * CFrame.Angles(0, math.rad(20), 0))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_D, Size = Vector3.new(0.5, 0.3, 0.3) },
		at * CFrame.new(1.15, 3.1, -1.35) * CFrame.Angles(0, math.rad(20), 0))

	-- a hanging BAKERY sign over the walk-up side: at this scale the station is
	-- a landmark, so it should say what it is from across the island
	for _, sx in ipairs({ -1, 1 }) do
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.4, 6.2, 0.4), CanCollide = true },
			at * CFrame.new(sx * 2.6, 3.1, -3.6))
	end
	local board = piece({ Color = PAL.WOOD_D, Size = Vector3.new(6.4, 1.5, 0.3), CastShadow = true },
		at * CFrame.new(0, 5.6, -3.6))
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(640, 150); sg.Parent = board
	local signText = Instance.new("TextLabel")
	signText.BackgroundTransparency = 1; signText.Size = UDim2.fromScale(1, 1)
	signText.Font = Enum.Font.FredokaOne; signText.TextScaled = true
	signText.TextColor3 = PAL.CREAM; signText.Text = "THE BAKERY"; signText.Parent = sg

	-- THE PROMPT BOX LIVES OUTSIDE THE SCALED MODEL, at player height in front of
	-- the counter. Inside the model it grew with the station, which hoisted the
	-- floating [E] to the giant bowl's rim -- pretty, and unreachable. A roomy
	-- (not huge) box at the walk-up side keeps the prompt at eye level.
	local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(16, 10, 9),
		CFrame = at * CFrame.new(0, 5, -(3.0 * MIXER_SCALE + 3)), Parent = bakeFolder })
	mixPrompt = Instance.new("ProximityPrompt")
	mixPrompt.ActionText = "Mix"; mixPrompt.ObjectText = "Mixing Bowl"
	mixPrompt.HoldDuration = 0.3; mixPrompt.MaxActivationDistance = 18
	mixPrompt.RequiresLineOfSight = false; mixPrompt.Enabled = false; mixPrompt.Parent = hit

	-- GROW THE WHOLE STATION. Scaled about a pivot on the ground line, so the legs
	-- stay planted and everything above them gets bigger -- then every frame the
	-- animations rely on is recomputed at the same scale, or the blobs would pour
	-- into where the small bowl used to be.
	local S = MIXER_SCALE
	f.WorldPivot = at
	f:ScaleTo(S)
	-- NOT PASS-THROUGH-ABLE: every visible part goes solid, and queryable so the
	-- chicken's obstacle feeler can see the walls too. (The batter disc starts
	-- invisible, so it stays walk-through -- it lives inside the bowl anyway.)
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			d.CanCollide = true; d.CanQuery = true
		end
	end
	bowlTopCF  = at * CFrame.new(0, 6.4 * S, 0)
	spoonHome  = at * CFrame.new(1.2 * S, 6.6 * S, 0) * CFrame.Angles(0, 0, math.rad(-16))
	spoonModel.WorldPivot = at * CFrame.new(0, 6.0 * S, 0)
	print(("[Bakery] mixing station built on '%s' (x%.1f, seated on the marker's base)")
		:format(part:GetFullName(), S))
end

-- ingredients arc into the bowl one at a time, then the stirring begins
local function startMixing()
	step = 3; stirs = 0
	refreshBanner(); refreshPrompts()
	mixPrompt.Enabled = false
	local R = RECIPES[recipe]
	task.spawn(function()
		local need, i = needOf(), 0
		for _, kind in ipairs(ING_ORDER) do
			for _ = 1, (need[kind] or 0) do
				i += 1
				local n = i     -- captured per blob: `i` itself has hit its final value
				                -- long before the first task.delay callback ever runs
				task.delay(n * 0.28, function()
					-- a stand-in prop pops above the bowl and drops in with a puff,
					-- sized to the GROWN bowl or it reads as a crumb falling in
					local MS = math.max(1, MIXER_SCALE * 0.55)
					local start = bowlTopCF
						* CFrame.new(math.cos(n * 2.4) * 2.5 * MS, 4 * MS, math.sin(n * 2.4) * 2.5 * MS)
					local blob = mk({ Shape = Enum.PartType.Ball,
						Color = (kind == "egg" and PAL.EGGSH) or (kind == "sugar" and PAL.SUGAR)
							or (kind == "butter" and PAL.BUTTER) or (kind == "dough" and PAL.DOUGHY)
							or PAL.CHOC,
						Size = Vector3.new(0.9, 0.9, 0.9) * MS })
					blob.CFrame = start; blob.Parent = bakeFolder
					-- sink to just above the batter disc: the rim-to-batter gap grows
					-- with the station, so the drop depth has to as well
					local drop = tween(blob, 0.4,
						{ CFrame = bowlTopCF * CFrame.new(0, -0.95 * MIXER_SCALE, 0) },
						Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					drop.Completed:Connect(function()
						poofAt(bowlTopCF.Position, blob.Color)
						blob:Destroy()
						-- the batter creeps up as things go in
						batterDisc.Transparency = math.max(0, 1 - (n / 8) * 1.2)
					end)
				end)
			end
		end
		local total = 0
		for _, n in pairs(need) do total += n end
		task.delay(total * 0.28 + 0.7, function()
			batterDisc.Transparency = 0
			batterDisc.Color = R.batter:Lerp(Color3.new(1, 1, 1), 0.25)  -- pale until stirred
			mixPrompt.ActionText = "Stir!"; mixPrompt.HoldDuration = 0
			mixPrompt.Enabled = true
			flashBanner(E_BOWL .. " Now STIR!  Press the prompt again and again!", 3)
		end)
	end)
end

local function doStir()
	stirs += 1
	refreshBanner()
	local R = RECIPES[recipe]
	-- the spoon takes a lap round the bowl; the batter darkens toward done
	local from = (stirs - 1) / STIRS_NEEDED
	batterDisc.Color = R.batter:Lerp(Color3.new(1, 1, 1), 0.25 * (1 - stirs / STIRS_NEEDED))
	if spoonModel and spoonModel.Parent then
		task.spawn(function()
			for a = 1, 10 do
				spoonModel:PivotTo(spoonModel.WorldPivot
					* CFrame.Angles(0, math.rad((from * 360) + a * 36), 0)
					* spoonModel.WorldPivot:ToObjectSpace(spoonHome))
				task.wait(0.03)
			end
		end)
	end
	poofAt(bowlTopCF.Position + Vector3.new(math.cos(stirs * 2.2) * 1.6, -0.4, math.sin(stirs * 2.2) * 1.6)
		* math.max(1, MIXER_SCALE * 0.55), R.batter)
	mixPrompt.ActionText = ("Stir!  (%d/%d)"):format(stirs, STIRS_NEEDED)

	if stirs >= STIRS_NEEDED then
		mixPrompt.Enabled = false
		mixPrompt.ActionText = "Mix"
		flashBanner(E_SPARK .. " Perfect batter! Into the pan it goes...", 3)
		-- the batter drains into a pan that lands in your hands
		tween(batterDisc, 0.8, { Transparency = 1 })
		task.delay(0.8, function()
			step = 4
			giveHeld("pan")
			refreshBanner(); refreshPrompts()
			if bakerHead then showBubble(bakerHead, "Beautiful! Now bake it -- either oven!", false) end
		end)
	end
end

-- ============================================================================
-- THE OVEN HUD -- pops up when a pan goes in. One job, one button: heat bleeds
-- away on its own, STOKE throws it back up, and the bake bar only fills fast
-- while the needle holds the orange sweet zone. X closes it and the bake keeps
-- creeping along at the slow rate -- the oven's "Watch" prompt reopens it, so
-- a closed HUD can never strand a bake.
-- ============================================================================
local BH = { stokes = 0 }    -- widgets in one table (same register-budget trick as PAL)
do
	local g = Instance.new("ScreenGui")
	g.Name = "BakeryOvenHUD"; g.ResetOnSpawn = false; g.DisplayOrder = 12
	g.Enabled = false; g.Parent = PlayerGui
	BH.gui = g

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 1); panel.Position = UDim2.new(0.5, 0, 1, -30)
	panel.Size = UDim2.new(0, 560, 0, 290); panel.BackgroundColor3 = PAL.PANEL
	panel.BorderSizePixel = 0; panel.Parent = g
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	do local s = Instance.new("UIStroke"); s.Color = PAL.CRUST; s.Thickness = 3; s.Parent = panel end

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1; title.Position = UDim2.new(0, 20, 0, 12)
	title.Size = UDim2.new(1, -90, 0, 32); title.Font = Enum.Font.FredokaOne
	title.TextSize = 24; title.TextColor3 = PAL.TEXTC
	title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = panel
	BH.title = title

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0); close.Position = UDim2.new(1, -14, 0, 12)
	close.Size = UDim2.fromOffset(38, 38); close.BackgroundColor3 = PAL.CRUST
	close.Text = "X"; close.Font = Enum.Font.FredokaOne; close.TextSize = 20
	close.TextColor3 = Color3.new(1, 1, 1); close.BorderSizePixel = 0; close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 12)
	close.MouseButton1Click:Connect(function() g.Enabled = false end)

	-- the bake bar: how done it is
	local pLab = Instance.new("TextLabel")
	pLab.BackgroundTransparency = 1; pLab.Position = UDim2.new(0, 20, 0, 50)
	pLab.Size = UDim2.new(1, -40, 0, 18); pLab.Font = Enum.Font.GothamBold
	pLab.TextSize = 14; pLab.TextColor3 = PAL.HINTC
	pLab.TextXAlignment = Enum.TextXAlignment.Left; pLab.Text = "BAKED  0%"; pLab.Parent = panel
	BH.plabel = pLab
	local pTrack = Instance.new("Frame")
	pTrack.Position = UDim2.new(0, 20, 0, 72); pTrack.Size = UDim2.new(1, -40, 0, 24)
	pTrack.BackgroundColor3 = Color3.fromRGB(240, 224, 206); pTrack.BorderSizePixel = 0
	pTrack.Parent = panel
	Instance.new("UICorner", pTrack).CornerRadius = UDim.new(1, 0)
	local pFill = Instance.new("Frame")
	pFill.Size = UDim2.new(0, 0, 1, 0); pFill.BackgroundColor3 = PAL.CRUST
	pFill.BorderSizePixel = 0; pFill.Parent = pTrack
	Instance.new("UICorner", pFill).CornerRadius = UDim.new(1, 0)
	BH.fill = pFill

	-- the heat bar: a needle you keep inside the orange sweet-zone band
	local hLab = pLab:Clone()
	hLab.Position = UDim2.new(0, 20, 0, 106); hLab.Text = "OVEN HEAT"; hLab.Parent = panel
	local hTrack = Instance.new("Frame")
	hTrack.Position = UDim2.new(0, 20, 0, 128); hTrack.Size = UDim2.new(1, -40, 0, 30)
	hTrack.BackgroundColor3 = Color3.fromRGB(240, 224, 206); hTrack.BorderSizePixel = 0
	hTrack.Parent = panel
	Instance.new("UICorner", hTrack).CornerRadius = UDim.new(0, 8)
	local zone = Instance.new("Frame")
	zone.Position = UDim2.new(ZONE_LO / 100, 0, 0, 0)
	zone.Size = UDim2.new((ZONE_HI - ZONE_LO) / 100, 0, 1, 0)
	zone.BackgroundColor3 = PAL.GLOW; zone.BackgroundTransparency = 0.45
	zone.BorderSizePixel = 0; zone.Parent = hTrack
	Instance.new("UICorner", zone).CornerRadius = UDim.new(0, 8)
	local needle = Instance.new("Frame")
	needle.AnchorPoint = Vector2.new(0.5, 0.5); needle.Position = UDim2.new(0.65, 0, 0.5, 0)
	needle.Size = UDim2.new(0, 7, 1, 8); needle.BackgroundColor3 = PAL.TEXTC
	needle.BorderSizePixel = 0; needle.ZIndex = 2; needle.Parent = hTrack
	Instance.new("UICorner", needle).CornerRadius = UDim.new(1, 0)
	BH.needle = needle

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1; hint.Position = UDim2.new(0, 20, 0, 162)
	hint.Size = UDim2.new(1, -40, 0, 20); hint.Font = Enum.Font.GothamBold
	hint.TextSize = 15; hint.TextColor3 = PAL.HINTC; hint.Text = ""; hint.Parent = panel
	BH.hint = hint

	local stoke = Instance.new("TextButton")
	stoke.AnchorPoint = Vector2.new(0.5, 1); stoke.Position = UDim2.new(0.5, 0, 1, -16)
	stoke.Size = UDim2.new(0, 300, 0, 76); stoke.BackgroundColor3 = PAL.GLOW
	stoke.Font = Enum.Font.FredokaOne; stoke.TextSize = 26
	stoke.TextColor3 = Color3.new(1, 1, 1); stoke.BorderSizePixel = 0
	stoke.Text = E_FIRE .. " STOKE THE FIRE"; stoke.Parent = panel
	Instance.new("UICorner", stoke).CornerRadius = UDim.new(0, 16)
	-- Activated, not MouseButton1Click: it fires for touch and controller too
	stoke.Activated:Connect(function()
		BH.stokes += 1
		stoke.Size = UDim2.new(0, 288, 0, 70)   -- squash that pops back: the press reads
		tween(stoke, 0.18, { Size = UDim2.new(0, 300, 0, 76) }, Enum.EasingStyle.Back)
	end)
end

local function openBakeHUD(what)
	BH.stokes = 0
	BH.title.Text = ("Baking: %s"):format(what)
	BH.gui.Enabled = true
end
local function closeBakeHUD() BH.gui.Enabled = false end
local function updateBakeHUD(heat, progress, inZone)
	BH.needle.Position = UDim2.new(heat / 100, 0, 0.5, 0)
	BH.fill.Size = UDim2.new(progress / 100, 0, 1, 0)
	BH.plabel.Text = ("BAKED  %d%%"):format(progress)
	BH.hint.Text = inZone and (E_FIRE .. " Perfect heat -- hold it there!")
		or (heat < ZONE_LO and "Too cold! STOKE the fire!" or "Too hot! Let it settle a moment...")
	BH.hint.TextColor3 = inZone and Color3.fromRGB(72, 150, 60) or PAL.CRUST
end

-- ============================================================================
-- THE OVENS -- one built on each "Oven" part; either one bakes the pan
-- ============================================================================
local ovens = {}     -- [{ prompt=, mouthCF=, rackCF=, door=, doorCF=, glow=, smoke= }]
local bakingNow = false
local currentOven = nil   -- which oven holds the current bake (its prompt = "Watch")
local bakeIn         -- forward-declared: buildOven's prompt closure calls it, and
                     -- the function body is defined just below buildOven

local function buildOven(part)
	local at = baseFrameOf(part)
	hideMarker(part)
	-- a Model, not a Folder: the whole oven is grown OVEN_SCALE about its base
	local f = Instance.new("Model"); f.Name = "BrickOven"; f.Parent = bakeFolder
	local function piece(props, where)
		props.Parent = f
		local p = mk(props); p.CFrame = where; return p
	end

	-- stone slab, brick body, a black mouth with a glow inside, and a chimney.
	-- The mouth faces the marker's -Z, so aim the block's FRONT where players stand.
	piece({ Color = PAL.STONE, Size = Vector3.new(8.4, 1.0, 7.0), CanCollide = true, CastShadow = true },
		at * CFrame.new(0, 0.5, 0))
	piece({ Color = PAL.BRICK, Size = Vector3.new(7.0, 4.6, 5.6), CanCollide = true, CastShadow = true },
		at * CFrame.new(0, 3.3, 0.2))
	piece({ Color = PAL.BRICK_D, Size = Vector3.new(7.4, 0.6, 6.0) }, at * CFrame.new(0, 5.8, 0.2))
	-- dome: three shrinking slabs read as a curve without a single mesh
	piece({ Color = PAL.BRICK, Size = Vector3.new(6.0, 1.0, 4.8) }, at * CFrame.new(0, 6.5, 0.2))
	piece({ Color = PAL.BRICK_D, Size = Vector3.new(4.4, 0.9, 3.6) }, at * CFrame.new(0, 7.3, 0.2))
	piece({ Color = PAL.BRICK, Size = Vector3.new(2.8, 0.8, 2.4) }, at * CFrame.new(0, 8.0, 0.2))
	-- brick coursing: thin dark bands so the body reads as brick, not plastic
	for i = 1, 3 do
		piece({ Color = PAL.BRICK_D, Size = Vector3.new(7.05, 0.16, 5.65) },
			at * CFrame.new(0, 1.6 + i * 1.05, 0.2))
	end

	-- the mouth: a dark recess with a neon glow slab hidden inside
	piece({ Color = PAL.CHOC_D, Size = Vector3.new(3.4, 2.6, 0.4) }, at * CFrame.new(0, 2.7, -2.65))
	local glow = piece({ Color = PAL.GLOW, Material = Enum.Material.Neon, Transparency = 1,
		Size = Vector3.new(3.0, 2.2, 0.25) }, at * CFrame.new(0, 2.7, -2.55))
	local light = Instance.new("PointLight")
	light.Color = PAL.GLOW; light.Brightness = 0; light.Range = 14; light.Parent = glow
	-- ember sparks spitting from the mouth -- rate rides the bake's heat
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 120, 40))
	embers.Lifetime = NumberRange.new(0.5, 1.1); embers.Rate = 0
	embers.Speed = NumberRange.new(2, 5); embers.SpreadAngle = Vector2.new(25, 25)
	embers.Size = NumberSequence.new(0.3); embers.Acceleration = Vector3.new(0, 6, 0)
	embers.Parent = glow
	-- the door: an iron slab that slides up out of the way
	local doorCF = at * CFrame.new(0, 2.7, -2.9)
	local door = piece({ Color = PAL.IRON, Material = Enum.Material.Metal,
		Size = Vector3.new(3.5, 2.7, 0.3), CastShadow = true }, doorCF * CFrame.new(0, 3.1, 0))
	piece({ Color = PAL.STONE, Size = Vector3.new(4.6, 0.5, 1.6) }, at * CFrame.new(0, 1.2, -3.0)) -- hearth lip

	-- a bed of coals just inside the mouth: embers glowing even while it idles
	piece({ Color = Color3.fromRGB(46, 24, 16), Size = Vector3.new(2.8, 0.35, 1.6) },
		at * CFrame.new(0, 1.55, -2.2))
	for i = 1, 4 do
		piece({ Color = Color3.fromRGB(255, 96, 40), Material = Enum.Material.Neon,
			Size = Vector3.new(0.4, 0.22, 0.4) },
			at * CFrame.new(-0.9 + i * 0.45, 1.72, -2.15 + math.sin(i * 2.3) * 0.4))
	end
	-- arched bricks over the mouth so it reads as a proper hearth, not a slot
	for _, q in ipairs({ { -1.55, 4.15, 24 }, { -0.6, 4.45, 10 }, { 0.6, 4.45, -10 }, { 1.55, 4.15, -24 } }) do
		piece({ Color = PAL.BRICK_D, Size = Vector3.new(1.05, 0.6, 0.3) },
			at * CFrame.new(q[1], q[2], -2.5) * CFrame.Angles(0, 0, math.rad(q[3])))
	end
	-- split firewood stacked on the slab, waiting for the stoke
	for i = 1, 3 do
		piece({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_D, Size = Vector3.new(2.2, 0.7, 0.7) },
			at * CFrame.new(3.6, 1.35 + (i - 1) * 0.62, -0.6 + (i % 2) * 0.6)
				* CFrame.Angles(0, math.rad(90), 0))
	end

	-- chimney with a smoke emitter that only runs while baking
	piece({ Color = PAL.BRICK_D, Size = Vector3.new(1.5, 3.2, 1.5), CastShadow = true },
		at * CFrame.new(2.0, 9.2, 1.4))
	piece({ Color = PAL.STONE, Size = Vector3.new(1.9, 0.4, 1.9) }, at * CFrame.new(2.0, 10.9, 1.4))
	local smokeHost = piece({ Transparency = 1, Size = Vector3.new(1, 1, 1) },
		at * CFrame.new(2.0, 11.3, 1.4))
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(PAL.SMOKE)
	-- the chimney is NEVER cold: a lazy idle wisp all day, thickening with the
	-- fire while a bake is on (the bake loop drives Rate off the heat)
	smoke.Lifetime = NumberRange.new(1.4, 2.4); smoke.Rate = 3
	smoke.Speed = NumberRange.new(2.5, 4.5); smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.2) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1) })
	smoke.Acceleration = Vector3.new(0, 3, 0)
	smoke.Parent = smokeHost

	-- a side rack where the finished tray slides out
	local rackCF = at * CFrame.new(-3.2, 3.0, -1.6)
	piece({ Color = PAL.WOOD, Size = Vector3.new(2.6, 0.3, 2.0), CanCollide = true },
		rackCF * CFrame.new(0, -0.4, 0))
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.5, 2.6, 0.5), CanCollide = true },
		rackCF * CFrame.new(0, -1.8, 0))

	-- prompt box OUTSIDE the model (same reason as the mixer's): player height,
	-- in front of the mouth, roomy but not huge
	local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(16, 10, 10),
		CFrame = at * CFrame.new(0, 5, -3.3 * OVEN_SCALE), Parent = bakeFolder })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Bake"; prompt.ObjectText = "Brick Oven"; prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 18; prompt.RequiresLineOfSight = false
	prompt.Enabled = false; prompt.Parent = hit

	-- GROW THE WHOLE OVEN about its base, then recompute every frame the bake
	-- sequence steers by -- door, mouth, rack -- at the same scale. The smoke is
	-- rescaled by hand: ScaleTo grows parts, not particles, and a wisp sized for
	-- a garden oven vanishes against a chimney five times as tall.
	local S = OVEN_SCALE
	f.WorldPivot = at
	f:ScaleTo(S)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1 * S),
		NumberSequenceKeypoint.new(1, 3.0 * S) })
	smoke.Speed = NumberRange.new(2.5 * S * 0.6, 4.5 * S * 0.6)
	smoke.Acceleration = Vector3.new(0, 3 * S * 0.5, 0)
	embers.Size = NumberSequence.new(0.3 * S)
	embers.Speed = NumberRange.new(2 * S * 0.5, 5 * S * 0.5)
	light.Range = 14 * S
	-- NOT PASS-THROUGH-ABLE, same as the mixer. The glow slab starts invisible
	-- so it stays walk-through; the door goes solid, as a door should.
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			d.CanCollide = true; d.CanQuery = true
		end
	end

	local ovenDoorCF = at * CFrame.new(0, 2.7 * S, -2.9 * S)
	local oven = {
		prompt = prompt, glow = glow, light = light, smoke = smoke, embers = embers,
		door = door, doorCF = ovenDoorCF, doorUpCF = ovenDoorCF * CFrame.new(0, 3.1 * S, 0),
		mouthCF = at * CFrame.new(0, 2.4 * S, -2.4 * S),
		rackCF  = at * CFrame.new(-3.2 * S, 3.0 * S, -1.6 * S),
		-- where you STAND to take the tray: player height, beside the tall rack
		rackTakeCF = at * CFrame.new(-3.2 * S, 5, -1.6 * S - 5),
	}
	table.insert(ovens, oven)
	prompt.Triggered:Connect(function()
		if step == 4 and not bakingNow then bakeIn(oven)
		elseif step == 5 and oven == currentOven then BH.gui.Enabled = true end   -- "Watch"
	end)
	print(("[Bakery] oven %d built on '%s' (x%d, seated on the marker's base)")
		:format(#ovens, part:GetFullName(), S))
end

-- the bake itself: pan in, door down, glow up, smoke on, count down, DING
bakeIn = function(oven)
	bakingNow = true
	currentOven = oven
	step = 5
	refreshBanner(); refreshPrompts()
	local R = RECIPES[recipe]
	-- world props at the oven live at oven scale, or they vanish inside it
	local TS = math.max(1, OVEN_SCALE * 0.55)

	-- the pan leaves your hands, grows to oven size, and slides into the mouth
	local hrp = hrpOf()
	local pan = mk({ Color = PAL.IRON, Material = Enum.Material.Metal, Size = Vector3.new(1.7, 0.3, 1.25) })
	pan.CFrame = hrp and (hrp.CFrame * CFrame.new(0, 0, -2)) or oven.mouthCF * CFrame.new(0, 0, -4 * TS)
	pan.Parent = bakeFolder
	local fill = mk({ Color = R.batter, Size = Vector3.new(1.5, 0.18, 1.05) })
	fill.CFrame = pan.CFrame * CFrame.new(0, 0.16, 0); fill.Parent = bakeFolder
	dropHeld()
	tween(pan, 0.6, { CFrame = oven.mouthCF, Size = Vector3.new(1.7, 0.3, 1.25) * TS })
	tween(fill, 0.6, { CFrame = oven.mouthCF * CFrame.new(0, 0.16 * TS, 0),
		Size = Vector3.new(1.5, 0.18, 1.05) * TS })

	task.delay(0.7, function()
		-- door shuts, fire lights
		tween(oven.door, 0.4, { CFrame = oven.doorCF }, Enum.EasingStyle.Bounce)
		tween(oven.glow, 0.5, { Transparency = 0.3 })
		pan:Destroy(); fill:Destroy()

		-- THE BAKE IS PLAYED, NOT WAITED OUT. The oven HUD opens: heat bleeds
		-- away, STOKE puts it back, and progress runs fast only while the needle
		-- holds the sweet zone. Glow, light and chimney smoke all answer the heat,
		-- so the oven itself shows how the bake is going from across the island.
		openBakeHUD(R.title)
		task.spawn(function()
			local heat, progress, last = 65, 0, os.clock()
			while progress < 100 and step == 5 do
				task.wait(0.05)
				local now = os.clock()
				local dt = math.min(now - last, 0.25); last = now
				heat = math.clamp(heat + BH.stokes * HEAT_STOKE - HEAT_DECAY * dt, 0, 100)
				BH.stokes = 0
				local inZone = heat >= ZONE_LO and heat <= ZONE_HI
				progress = math.min(100, progress + dt * (inZone and BAKE_FAST or BAKE_SLOW))
				updateBakeHUD(heat, progress, inZone)
				oven.glow.Transparency = 0.65 - 0.55 * (heat / 100)
				oven.light.Brightness = 0.6 + 2.6 * (heat / 100)
				oven.smoke.Rate = 3 + math.floor(heat / 8)
				oven.embers.Rate = math.floor(heat / 12)
				objLabel.Text = ("%s Baking the %s...  %d%%"):format(E_FIRE, R.title, progress)
			end
			closeBakeHUD()
			if step ~= 5 then    -- /complete (or a reset) cut this bake short: stand down
				bakingNow = false; currentOven = nil
				oven.smoke.Rate = 3; oven.embers.Rate = 0
				tween(oven.glow, 0.5, { Transparency = 1 }); oven.light.Brightness = 0
				tween(oven.door, 0.5, { CFrame = oven.doorUpCF })
				return
			end
			-- DING! door up, fire down to an idle wisp, tray out onto the rack
			oven.smoke.Rate = 3; oven.embers.Rate = 0
			tween(oven.glow, 0.5, { Transparency = 1 })
			oven.light.Brightness = 0
			tween(oven.door, 0.5, { CFrame = oven.doorUpCF })
			flashBanner(E_BELL .. " DING! It's ready -- grab the tray!", 4)
			poofAt(oven.mouthCF.Position, PAL.GLOW_H)

			-- the finished tray slides from the mouth to the side rack, at oven scale
			local tray = Instance.new("Model"); tray.Name = "DoneTray"; tray.Parent = bakeFolder
			local base = mk({ Color = PAL.BUTTER, Size = Vector3.new(1.9, 0.16, 1.35) * TS,
				Reflectance = 0.08, CanQuery = true, Parent = tray })
			base.CFrame = oven.mouthCF
			for gx = -1, 1 do
				for gz = 0, 1 do
					local isCookie = (recipe == "brookie") and ((gx + gz) % 2 == 0)
					local sq = mk({
						Color = isCookie and PAL.DOUGHY or PAL.CHOC,
						Shape = isCookie and Enum.PartType.Ball or Enum.PartType.Block,
						Size = (isCookie and Vector3.new(0.52, 0.34, 0.52) or Vector3.new(0.46, 0.3, 0.46)) * TS,
						Parent = tray })
					sq.CFrame = base.CFrame * CFrame.new(gx * 0.55 * TS, 0.25 * TS, (gz - 0.5) * 0.6 * TS)
				end
			end
			tray.PrimaryPart = base
			-- steam wisps off the fresh bake
			local steam = Instance.new("ParticleEmitter")
			steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
			steam.Color = ColorSequence.new(Color3.new(1, 1, 1))
			steam.Lifetime = NumberRange.new(0.7, 1.2); steam.Rate = 4
			steam.Speed = NumberRange.new(1, 2); steam.Size = NumberSequence.new(0.5)
			steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6),
				NumberSequenceKeypoint.new(1, 1) })
			steam.Parent = base
			task.spawn(function()
				local from, to = oven.mouthCF, oven.rackCF
				for a = 0, 1, 0.06 do
					if not tray.Parent then return end
					tray:PivotTo(from:Lerp(to, a))
					task.wait(0.03)
				end
			end)

			-- the take prompt sits in a ground-level box by the rack, not on the
			-- tray itself -- the tray rides 15 studs up where no [E] can be reached
			local takeBox = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(12, 9, 10),
				CFrame = oven.rackTakeCF, Parent = bakeFolder })
			local tprompt = Instance.new("ProximityPrompt")
			tprompt.ActionText = "Take Tray"; tprompt.ObjectText = R.title
			tprompt.HoldDuration = 0; tprompt.MaxActivationDistance = 16
			tprompt.RequiresLineOfSight = false; tprompt.Parent = takeBox
			tprompt.Triggered:Connect(function()
				if step ~= 5 then return end
				step = 6
				bakingNow = false
				currentOven = nil
				tray:Destroy(); takeBox:Destroy()
				giveHeld("tray")
				refreshBanner(); refreshPrompts()
				if bakerHead then showBubble(bakerHead, "Ooooh, bring it here! Careful now!", false) end
			end)
		end)
	end)
end

-- ============================================================================
-- THE BAKER -- an existing *npc* model near the Mixer if you placed one,
-- otherwise a chef built beside the station
-- ============================================================================
local function findExistingNpc(nearPos)
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and string.find(norm(d.Name), "npc", 1, true)
			and not d:IsDescendantOf(bakeFolder) then
			local head = d:FindFirstChild("Head") or d.PrimaryPart
				or d:FindFirstChildWhichIsA("BasePart", true)
			if head then
				local dist = (head.Position - nearPos).Magnitude
				if dist <= NPC_MAX_DIST and (not bestD or dist < bestD) then best, bestD = head, dist end
			end
		end
	end
	return best
end

local function islandModel()
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.sub(norm(m.Name), 1, #ISLAND_PREFIX) == ISLAND_PREFIX then
			return m
		end
	end
	return nil
end

local function buildBaker(at)
	-- stands beside the mixing station, facing where players walk up. The station
	-- is MIXER_SCALE times wider than built, so stand clear of the grown counter.
	local spot = at * CFrame.new(4.2 * MIXER_SCALE + 3, 0, -1.5) * CFrame.Angles(0, math.rad(140), 0)
	local g = groundAt(spot.Position.X, spot.Position.Z, at.Position.Y)
	local base = CFrame.new(g and (g + Vector3.new(0, 0, 0)) or spot.Position) * (spot - spot.Position)

	local m = Instance.new("Model"); m.Name = "Baker Npc"   -- "npc" in the name: the island
	                                                        -- guide arrows will point at him
	local function bit(props, cf)
		props.Parent = m; props.CastShadow = true
		local p = mk(props); p.CFrame = base * cf; return p
	end
	for _, sx in ipairs({ -1, 1 }) do                        -- legs
		bit({ Color = PAL.CHOC_D, Size = Vector3.new(0.85, 1.9, 0.9) }, CFrame.new(sx * 0.5, 0.95, 0))
		bit({ Color = PAL.CHOC_D, Size = Vector3.new(0.9, 0.35, 1.3) }, CFrame.new(sx * 0.5, 0.18, -0.2))
	end
	bit({ Color = PAL.CREAM, Size = Vector3.new(2.2, 2.4, 1.4) }, CFrame.new(0, 3.1, 0))     -- jacket
	bit({ Color = PAL.PINK, Size = Vector3.new(1.7, 1.9, 0.2) }, CFrame.new(0, 2.8, -0.72))  -- apron
	bit({ Color = PAL.PINK, Size = Vector3.new(1.9, 0.35, 0.24) }, CFrame.new(0, 3.9, -0.7)) -- apron tie
	for i = 1, 3 do                                           -- jacket buttons
		bit({ Shape = Enum.PartType.Ball, Color = PAL.CHOC, Size = Vector3.new(0.18, 0.18, 0.18) },
			CFrame.new(0.55, 2.4 + i * 0.55, -0.72))
	end
	for _, sx in ipairs({ -1, 1 }) do                         -- arms: one on hip, one out
		bit({ Color = PAL.CREAM, Size = Vector3.new(0.7, 2.0, 0.7) },
			CFrame.new(sx * 1.45, 3.2, 0) * CFrame.Angles(0, 0, math.rad(sx * 14)))
		bit({ Shape = Enum.PartType.Ball, Color = PAL.SKIN, Size = Vector3.new(0.6, 0.6, 0.6) },
			CFrame.new(sx * 1.7, 2.15, 0))
	end
	local head = bit({ Color = PAL.SKIN, Size = Vector3.new(1.5, 1.4, 1.4), CanQuery = true },
		CFrame.new(0, 5.0, 0))
	head.Name = "Head"
	for _, sx in ipairs({ -1, 1 }) do
		bit({ Shape = Enum.PartType.Ball, Color = Color3.new(0, 0, 0), Size = Vector3.new(0.18, 0.22, 0.1) },
			CFrame.new(sx * 0.34, 5.15, -0.68))
	end
	bit({ Color = PAL.CHOC, Size = Vector3.new(0.9, 0.22, 0.3) }, CFrame.new(0, 4.7, -0.68))  -- mustache
	bit({ Shape = Enum.PartType.Ball, Color = PAL.SKIN, Size = Vector3.new(0.3, 0.25, 0.3) },
		CFrame.new(0, 4.95, -0.75))                                                            -- nose
	-- the chef hat: band + puffy top
	bit({ Shape = Enum.PartType.Cylinder, Color = PAL.CREAM, Size = Vector3.new(0.55, 1.5, 1.5) },
		CFrame.new(0, 5.85, 0) * CFrame.Angles(0, 0, math.rad(90)))
	bit({ Shape = Enum.PartType.Ball, Color = Color3.new(1, 1, 1), Size = Vector3.new(1.7, 1.2, 1.7) },
		CFrame.new(0, 6.5, 0))
	bit({ Shape = Enum.PartType.Ball, Color = Color3.new(1, 1, 1), Size = Vector3.new(0.9, 0.8, 0.9) },
		CFrame.new(0.5, 6.7, 0.3))
	m.PrimaryPart = head
	m.WorldPivot = base

	-- parent under the island model when there is one, so NpcGuideArrow's
	-- island-scoped scan can find him; Workspace otherwise
	m.Parent = islandModel() or bakeFolder

	-- a slow idle sway so he reads as alive, not a statue
	task.spawn(function()
		local t = 0
		while m.Parent do
			t += task.wait(0.06)
			m:PivotTo(base * CFrame.new(0, math.sin(t * 1.6) * 0.06, 0)
				* CFrame.Angles(0, math.sin(t * 0.8) * 0.04, 0))
		end
	end)
	print("[Bakery] no NPC nearby -- built the Baker beside the mixing station")
	return head
end

-- ============================================================================
-- DIALOGUE -- paged bubbles, same rhythm as every other island NPC
-- ============================================================================
local function questPages()
	if step >= 7 then
		if bonusDone then
			return { "Brownies AND Brookies. My hero!", "The bakery smells incredible. Thank you!" }
		end
		local other = (recipe == "brownie") and RECIPES.brookie or RECIPES.brownie
		return {
			"That was DELICIOUS. But you know what...",
			("I never got to taste the %s!"):format(other.title),
			("Bake me the %s too and there's %d more coins in it!"):format(other.title, BONUS_REWARD),
		}
	elseif step == 6 then
		return { "Is that it?! Hand it over, hand it over!" }
	elseif step == 5 then
		return { "Patience! Good baking takes time. Watch the oven!" }
	elseif step == 4 then
		return { "Don't just stand there holding batter -- OVEN. Either one!" }
	elseif step == 3 then
		return { "Stir stir stir! The bowl won't mix itself!" }
	elseif step == 2 then
		if allGathered() then return { "You've got everything! To the mixing bowl!" } end
		local pages = { "Still shopping? Here's what's left:", shoppingList() }
		if stillNeeds("egg") then
			pages[#pages + 1] = E_CHICK .. " Eggs? TAP my chicken. Gently! She'll lay one for you."
		end
		return pages
	end
	return {
		"Welcome to my bakery! Well... it WILL be a bakery.",
		"Two ovens, a giant bowl, my prize chicken -- and no baker's assistant!",
		"That's where YOU come in. Pick a recipe and we'll bake it together.",
		"Fetch the ingredients, mix them in my bowl, bake the pan golden...",
		("...and there's %d coins in it for you. Deal? Pick your bake!"):format(COIN_REWARD),
	}
end

local function completeBake()
	-- tray handed over: pay out, celebrate, and either open the bonus or wrap up
	dropHeld()
	local R = RECIPES[recipe]
	local reward = bonusRound and BONUS_REWARD or COIN_REWARD
	local ce = ReplicatedStorage:FindFirstChild("CoinEvent")
	if ce then pcall(function() ce:FireServer(reward) end) end
	if bonusRound then bonusDone = true end
	step = 7
	_G.bakeryQuestComplete = true
	_G.bakeryQuestStep = nil
	refreshBanner(); refreshPrompts()
	if bakerHead then
		launchFireworks(bakerHead.Position + Vector3.new(0, 4, 0))
		showBubble(bakerHead, "Mmmmf-- mm! Divine. DIVINE!", false)
	end
	winBanner(("%s You baked the %s!  +%d coins %s"):format(E_SPARK, R.title, reward, E_SPARK))
	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({
			text = ("%s %s baked! +%d coins"):format(E_SPARK, R.title, reward), color = PAL.CRUST }) end)
	end
	print(("[Bakery] %s delivered -- +%d coins%s"):format(R.title, reward,
		bonusRound and " (bonus round)" or ""))
end

local function startRound(key, isBonus)
	recipe = key
	bonusRound = isBonus or false
	have = {}
	stirs = 0
	step = 2
	scatterIngredients()
	refreshBanner(); refreshPrompts()
	flashBanner(("%s %s time! Find the ingredients -- and tap that chicken!")
		:format(RECIPES[key].title == "BROWNIE" and ING.cocoa.emoji or ING.dough.emoji, RECIPES[key].title), 3.5)
end

local function wireBaker(head)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = "The Baker"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = TALK_DIST; prompt.RequiresLineOfSight = false; prompt.Parent = head

	local pages, index = nil, 0
	local watching = false
	local function closeDialogue() hideBubble(head); prompt.ActionText = "Talk"; index = 0; pages = nil end
	local function startWatcher()
		if watching then return end
		watching = true
		task.spawn(function()
			while index ~= 0 do
				local hrp = hrpOf()
				if not hrp or (hrp.Position - head.Position).Magnitude > TALK_DIST then
					closeDialogue(); break
				end
				task.wait(0.25)
			end
			watching = false
		end)
	end

	prompt.Triggered:Connect(function()
		-- delivering beats talking: with the tray in hand, one press hands it over
		if step == 6 then completeBake(); closeDialogue(); return end

		if index == 0 then pages = questPages() end
		index += 1
		if not pages or index > #pages then
			closeDialogue()
			-- finishing the intro (or the bonus offer) opens the recipe cards
			if step == 0 then
				openChooser(nil, function(key) startRound(key, false) end)
			elseif step >= 7 and not bonusDone then
				local other = (recipe == "brownie") and "brookie" or "brownie"
				openChooser(other, function(key) startRound(key, true) end)
			end
			return
		end
		local last = index >= #pages
		local footer = last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages)
		showBubble(head, pages[index], true, footer)
		prompt.ActionText = last and "Close" or "Continue"
		startWatcher()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then closeDialogue() end end)
end

-- ============================================================================
-- PROMPT REFRESH -- one place that decides what is pressable right now
-- ============================================================================
refreshPrompts = function()
	if mixPrompt then
		if step == 2 and allGathered() then
			mixPrompt.ActionText = "Mix"; mixPrompt.HoldDuration = 0.3; mixPrompt.Enabled = true
		elseif step == 3 and stirs < STIRS_NEEDED then
			-- startMixing manages the stir prompt itself; leave it be
		else
			if step ~= 3 then mixPrompt.Enabled = false end
		end
	end
	for _, o in ipairs(ovens) do
		if step == 4 and not bakingNow then
			o.prompt.ActionText = "Bake"; o.prompt.Enabled = true
		elseif step == 5 and o == currentOven then
			o.prompt.ActionText = "Watch"; o.prompt.Enabled = true   -- reopens the HUD
		else
			o.prompt.Enabled = false
		end
	end
end

-- ============================================================================
-- GO -- the streaming-safe scanner. Island 15 is a long flight from spawn, so
-- its marker parts appear late (and only when the player is near). Scan every
-- few seconds; each station is built exactly once, the moment its marker shows.
-- ============================================================================
task.spawn(function()
	local builtMixer, builtChicken = false, false
	local builtOvens = {}     -- [instance] = true
	local mixerPos = nil

	while true do
		for _, d in ipairs(Workspace:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("Model")) and not d:IsDescendantOf(bakeFolder) then
				local key = norm(d.Name)
				if key == MIXER_NAME and not builtMixer then
					-- only latch once a real BasePart exists: a streamed-in Model can
					-- arrive EMPTY, with its parts following seconds later
					local part = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
					if part then
						builtMixer = true
						mixerPos = part.Position
						buildMixer(part)
						mixPrompt.Triggered:Connect(function()
							if step == 2 and allGathered() then startMixing()
							elseif step == 3 and stirs < STIRS_NEEDED then doStir() end
						end)
						-- the Baker: an existing NPC if one is close, else built
						task.spawn(function()
							task.wait(2)          -- give a Studio-placed NPC a beat to stream in
							bakerHead = findExistingNpc(mixerPos) or buildBaker(mixerAt)
							wireBaker(bakerHead)
							refreshBanner()
						end)
					end
				elseif key == OVEN_NAME and not builtOvens[d] and mixerPos then
					local part = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
					if part and (part.Position - mixerPos).Magnitude <= MARKER_RANGE then
						builtOvens[d] = true
						buildOven(part)
					end
				elseif key == CHICKEN_NAME and not builtChicken and mixerPos then
					local part = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
					if part and (part.Position - mixerPos).Magnitude <= MARKER_RANGE then
						builtChicken = true
						hideMarker(d)
						chickenOrigin = part.Position
						chicken = buildChicken(chickenOrigin)
						runChicken()
						print("[Bakery] chicken loose at '" .. part:GetFullName() .. "'")
					end
				elseif key == ZONE_NAME and not zoneCF and mixerPos then
					local part = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
					if part and (part.Position - mixerPos).Magnitude <= MARKER_RANGE then
						-- the pen: remember its frame AND its top surface -- once hidden
						-- the plate can't be raycast, so this Y becomes the floor of
						-- record for the chicken, her nest and every egg
						zoneCF, zoneHalf = part.CFrame, part.Size * 0.5
						zoneTopY = part.Position.Y + part.Size.Y * 0.5
						hideMarker(d)
						-- everything already built re-seats onto the plate: the chicken
						-- herself follows on her next tick, the nest is moved here
						if chickenOrigin then chickenOrigin = clampToZone(chickenOrigin) end
						if nestModel and nestModel.Parent then
							local p = clampToZone(nestModel:GetPivot().Position)
							nestModel:PivotTo(CFrame.new(p.X, zoneTopY + 0.3, p.Z))
						end
						print(("[Bakery] chicken zone: %s (%.0f x %.0f studs, floor Y=%.0f)")
							:format(part:GetFullName(), part.Size.X, part.Size.Z, zoneTopY))
					end
				end
			end
		end
		if builtMixer and builtChicken and #ovens >= 2 then break end
		task.wait(3)
	end
	print(("[Bakery] all stations up: mixer, %d oven(s), 1 chicken"):format(#ovens))
end)

refreshBanner()

-- ============================================================================
-- /start    -- jump straight to the recipe cards, no Baker chat needed
-- /complete -- instantly finishes the CURRENT bake
-- Both only fire standing at the bakery, so they can't trigger from elsewhere.
-- ============================================================================
local function onCommand(msg)
	local text = tostring(msg or ""):lower()
	if text:sub(1, 6) == "/start" then
		local hrp = hrpOf()
		if not (mixerAt and hrp) then return end
		if (hrp.Position - mixerAt.Position).Magnitude > BANNER_RANGE then return end
		if step == 0 then
			openChooser(nil, function(key) startRound(key, false) end)
		elseif step >= 7 and not bonusDone then
			local other = (recipe == "brownie") and "brookie" or "brownie"
			openChooser(other, function(key) startRound(key, true) end)
		else
			flashBanner(E_BOWL .. " The bake-off is already going -- check the banner!", 2.5)
		end
		print("[Bakery][TEST] /start -- recipe cards opened")
		return
	end
	if text:sub(1, 9) ~= "/complete" then return end
	local hrp = hrpOf()
	if not (mixerAt and hrp) then return end
	if (hrp.Position - mixerAt.Position).Magnitude > BANNER_RANGE then return end
	if step >= 7 and bonusDone then return end
	if not recipe then recipe = "brownie" end
	if step < 6 then step = 6; giveHeld("tray") end
	completeBake()
	print("[Bakery][TEST] /complete -- bake handed straight to the Baker")
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
