--======================================================================
-- IslandTaskReward.client.lua  (LocalScript)  -- CandyRealm
--======================================================================
-- THE PAYOFF MOMENT. You finish an island quest and the game stops and makes a fuss: gold wash, a card that
-- punches in, the token number counting up from zero, confetti, and a stream of tokens that fly across the
-- screen and land in the token pill in the corner.
--
-- Fired by IslandTaskTokens.server, which decides the amount and the quest NAME -- this script never reads
-- either from a quest script, so the banner can only ever say what the server chose.
--
-- ===== WHY THE TOKENS FLY TO THE PILL =====
-- This is the whole trick, and it is worth doing properly. A number that simply appears is information. A
-- number you WATCH TRAVEL from the thing you earned it for to the place it lives is a reward -- it is why
-- every game that pays out currency animates it moving. It also teaches, without a word of tutorial, WHERE
-- the tokens went and therefore where to go to spend them. A seven-year-old who sees ten gold discs land in
-- the corner knows to tap the corner.
--
-- ===== NO EXTERNAL ASSETS =====
-- Everything here is Frames, UICorner and tweens. This place's own boot log shows several sound and image ids
-- failing with "Asset type does not match requested type" / "not approved for the requester", so anything
-- built on an asset id is a coin flip. The one sound used is the id CrateClient's diagnostic reports loading
-- successfully; if even that fails the pcall swallows it and the visual still plays.
--
-- ===== IT NEVER BLOCKS =====
-- No ModalEnabled, no input capture, no camera takeover. The player can keep walking and flying through the
-- whole thing. A celebration that takes the controls away from a kid mid-jump is a punishment.
--======================================================================

local Players      = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService  = game:GetService("SoundService")
local GuiService   = game:GetService("GuiService")
local Debris       = game:GetService("Debris")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Rojo adds, it never overwrites, so a stale baked-in copy would run alongside this one -- and two copies of
-- a reward moment means two overlapping cards and a doubled sound.
if _G.__IslandTaskRewardClient then
	warn("[IslandTask] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__IslandTaskRewardClient = true

--======================================================================
-- LOOK
--======================================================================
-- The house palette: bright blue/white/lime/gold. No dark panels -- this lands in front of a kid mid-game.
local GOLD      = Color3.fromRGB(255, 206, 92)
local GOLD_DEEP = Color3.fromRGB(226, 158, 30)
local BLUE      = Color3.fromRGB(30, 140, 255)
local BLUE_DEEP = Color3.fromRGB(18, 92, 190)
local CREAM     = Color3.fromRGB(255, 250, 236)
local LIME      = Color3.fromRGB(126, 224, 110)
local INK       = Color3.fromRGB(16, 44, 96)
-- Near-black navy for text sitting ON the gold banner. The regular INK is tuned for cream text on blue; on a
-- gold fill it is not dark enough to carry a heavy display face at a glance.
local TITLE_INK  = Color3.fromRGB(10, 26, 58)
local TITLE_EDGE = Color3.fromRGB(255, 236, 176)  -- pale gold outline: separates glyphs from the banner

local CONFETTI_COLOURS = { GOLD, LIME, CREAM, Color3.fromRGB(255, 132, 190), Color3.fromRGB(120, 200, 255) }

local HOLD      = 2.4    -- how long the card sits before it leaves
local FLY_COUNT = 10     -- tokens that make the trip to the pill
local CHIME_ID  = "rbxassetid://4612378364"

local function corner(g, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = g; return c end
local function stroke(g, col, th)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = g; return s
end
-- ===== ROBLOX HAS NO LETTER-SPACING =====
-- TextLabel exposes no tracking property, so it cannot be set to 0 or nudged positive. What actually reads
-- as "condensed" here is the OUTLINE: a 2.5px contextual stroke at TextSize 30 puts ~5px of outline between
-- one glyph and the next, and across a wide word like "TASK COMPLETE!" those outlines close the gaps until
-- the letters fuse into one block. Thinning the stroke is the real fix for the squeezed look.
--
-- `strokeCol` matters just as much: an outline the SAME dark as the fill only fattens each letter. A PALE
-- outline separates the glyph from what is behind it, which is what an outline is actually for.
local function label(parent, text, size, colour, font, strokeCol, strokeW)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = font or Enum.Font.FredokaOne
	t.TextSize = size
	t.TextColor3 = colour
	t.Text = text
	t.Parent = parent
	local st = Instance.new("UIStroke")
	st.Color = strokeCol or INK
	st.Thickness = strokeW or 2.5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Parent = t
	return t
end

-- SHRINK TO FIT, NEVER CLIP OR CROWD. TextScaled on its own lets a short string balloon to fill its box, so
-- it is always paired with a UITextSizeConstraint: `maxSize` becomes a CEILING rather than a fixed size, and
-- a long string steps DOWN until it fits instead of running into the edges.
local function fit(t, maxSize, minSize)
	t.TextScaled = true
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.MinTextSize = minSize or 12
	c.Parent = t
	return t
end

--======================================================================
-- WHERE THE TOKEN PILL IS
--======================================================================
-- Found by search, not a hard path -- the currency capsule has been rebuilt before. Returns a pixel point in
-- THIS gui's coordinate space, or nil if the pill is not on screen (in which case the tokens just fade out
-- mid-flight instead of flying somewhere wrong).
--
-- THE INSET IS THE FIDDLY BIT. AbsolutePosition is measured from below Roblox's topbar for a ScreenGui with
-- IgnoreGuiInset = false, and from the true screen corner for one with it true. This overlay sets it true so
-- the flash covers the whole screen, so a target living in a non-ignoring ScreenGui has to be shifted down by
-- the inset or the tokens land ~36px high.
local function tokenPillPoint()
	local cg = PlayerGui:FindFirstChild("CoinGui")
	if not cg then return nil end
	local pill
	for _, d in ipairs(cg:GetDescendants()) do
		if d:IsA("GuiObject") and d.Name == "TokenPill" then pill = d; break end
	end
	if not (pill and pill.AbsoluteSize.X > 1) then return nil end

	-- every ancestor visible, or it is on screen only in theory
	local node = pill
	while node and node ~= PlayerGui do
		if node:IsA("GuiObject") and not node.Visible then return nil end
		if node:IsA("ScreenGui") and not node.Enabled then return nil end
		node = node.Parent
	end

	local sg = pill:FindFirstAncestorWhichIsA("ScreenGui")
	local p = pill.AbsolutePosition + pill.AbsoluteSize / 2
	if sg and not sg.IgnoreGuiInset then p = p + GuiService:GetGuiInset() end
	return p
end

--======================================================================
-- THE MOMENT
--======================================================================
local playing = false

local function celebrate(questId, questName, tokens)
	if playing then return end   -- two islands cannot be cleared in the same frame, but a stray double-fire can
	playing = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "IslandTaskRewardGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 220          -- above the HUD; below nothing that matters
	gui.Parent = PlayerGui

	----------------------------------------------------------------
	-- 1. GOLD WASH
	----------------------------------------------------------------
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = GOLD
	flash.BackgroundTransparency = 0.45
	flash.BorderSizePixel = 0
	flash.ZIndex = 1
	flash.Parent = gui
	TweenService:Create(flash, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }):Play()

	----------------------------------------------------------------
	-- 2. THE CARD
	----------------------------------------------------------------
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.42)
	card.Size = UDim2.fromOffset(430, 228)
	card.BackgroundColor3 = BLUE
	card.BorderSizePixel = 0
	card.ZIndex = 4
	card.Parent = gui
	corner(card, 26); stroke(card, CREAM, 4)

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, BLUE),
		ColorSequenceKeypoint.new(1, BLUE_DEEP),
	})
	grad.Rotation = 90
	grad.Parent = card

	-- the whole card scales from one UIScale, so the punch-in is one tween instead of six
	local scale = Instance.new("UIScale"); scale.Scale = 0.2; scale.Parent = card

	local banner = Instance.new("Frame")
	banner.Size = UDim2.new(1, -28, 0, 52)
	banner.Position = UDim2.new(0.5, 0, 0, 16)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.BackgroundColor3 = GOLD
	banner.BorderSizePixel = 0
	banner.ZIndex = 5
	banner.Parent = card
	corner(banner, 16); stroke(banner, GOLD_DEEP, 3)

	-- Near-black navy on gold, with a PALE gold outline instead of another dark one. Dark text plus a dark
	-- outline of the same colour was what made this read as a yellow smear: the letters and their own
	-- outline were the same value, so the word thickened rather than sharpened.
	local title = label(banner, "TASK COMPLETE!", 30, TITLE_INK, nil, TITLE_EDGE, 1.2)
	-- Inset so the caps never touch the banner's rounded ends, then scaled to fit what is left.
	title.Size = UDim2.new(1, -28, 1, 0)
	title.Position = UDim2.new(0, 14, 0, 0)
	title.ZIndex = 6
	fit(title, 30, 16)

	local where = label(card, questName, 22, LIME)
	where.Size = UDim2.new(1, -28, 0, 28)
	where.Position = UDim2.new(0.5, 0, 0, 76)
	where.AnchorPoint = Vector2.new(0.5, 0)
	where.ZIndex = 5
	fit(where, 22, 11)

	-- the big number, counted up rather than printed
	local amount = label(card, "+0", 62, GOLD)
	amount.Size = UDim2.new(1, -28, 0, 74)
	amount.Position = UDim2.new(0.5, 0, 0, 108)
	amount.AnchorPoint = Vector2.new(0.5, 0)
	amount.ZIndex = 5
	fit(amount, 62, 24)
	-- 4px was the same crowding problem one size up; 2 keeps the digits distinct against the blue card.
	local amtStroke = amount:FindFirstChildOfClass("UIStroke"); if amtStroke then amtStroke.Thickness = 2 end

	local sub = label(card, "CRATE TOKENS", 20, CREAM)
	sub.Size = UDim2.new(1, -28, 0, 26)
	sub.Position = UDim2.new(0.5, 0, 0, 184)
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.ZIndex = 5
	fit(sub, 20, 11)

	-- The Food Realm's card had a fourth line here naming the pet that hatched. Candy quests do not grant a
	-- pet, so the line is gone and the card is 22px shorter rather than carrying an empty row.

	-- punch in: overshoot then settle. Back easing is what makes it feel like it LANDS.
	TweenService:Create(scale, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()

	----------------------------------------------------------------
	-- 3. CHIME
	----------------------------------------------------------------
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = CHIME_ID; s.Volume = 0.65; s.Parent = SoundService
		s:Play(); Debris:AddItem(s, 5)
	end)

	----------------------------------------------------------------
	-- 4. CONFETTI
	----------------------------------------------------------------
	task.delay(0.12, function()
		if not gui.Parent then return end
		for i = 1, 18 do
			local bit = Instance.new("Frame")
			bit.AnchorPoint = Vector2.new(0.5, 0.5)
			bit.Position = UDim2.fromScale(0.5, 0.42)
			bit.Size = UDim2.fromOffset(math.random(8, 15), math.random(8, 15))
			bit.BackgroundColor3 = CONFETTI_COLOURS[(i - 1) % #CONFETTI_COLOURS + 1]
			bit.BorderSizePixel = 0
			bit.Rotation = math.random(0, 360)
			bit.ZIndex = 3
			bit.Parent = gui
			corner(bit, 3)

			-- out and down: gravity is what stops it reading as a starburst sticker
			local ang  = math.rad(math.random(0, 360))
			local dist = math.random(160, 400)
			local dx   = math.cos(ang) * dist
			local dy   = math.sin(ang) * dist * 0.55 + math.random(180, 340)
			local t    = 0.9 + math.random() * 0.7
			TweenService:Create(bit, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5, dx, 0.42, dy),
				Rotation = bit.Rotation + math.random(-320, 320),
				BackgroundTransparency = 1,
			}):Play()
			Debris:AddItem(bit, t + 0.2)
		end
	end)

	----------------------------------------------------------------
	-- 5. COUNT THE NUMBER UP
	----------------------------------------------------------------
	task.spawn(function()
		local dur, t0 = 0.65, os.clock()
		while true do
			local k = (os.clock() - t0) / dur
			if k >= 1 or not amount.Parent then break end
			-- ease-out: fast at first, so it reads as "a lot" rather than as a slow tick
			amount.Text = "+" .. tostring(math.floor(tokens * (1 - (1 - k) ^ 3)))
			task.wait()
		end
		if amount.Parent then amount.Text = "+" .. tostring(tokens) end
	end)

	----------------------------------------------------------------
	-- 6. TOKENS FLY TO THE PILL
	----------------------------------------------------------------
	task.delay(0.85, function()
		if not gui.Parent then return end
		local target = tokenPillPoint()
		local cam = workspace.CurrentCamera
		local view = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local from = Vector2.new(view.X * 0.5, view.Y * 0.42)

		for i = 1, FLY_COUNT do
			task.delay((i - 1) * 0.055, function()
				if not gui.Parent then return end
				local disc = Instance.new("Frame")
				disc.AnchorPoint = Vector2.new(0.5, 0.5)
				disc.Position = UDim2.fromOffset(from.X, from.Y)
				disc.Size = UDim2.fromOffset(30, 30)
				disc.BackgroundColor3 = GOLD
				disc.BorderSizePixel = 0
				disc.ZIndex = 8
				disc.Parent = gui
				corner(disc, 15); stroke(disc, GOLD_DEEP, 3)

				if not target then
					-- no pill on screen: fade where it stands rather than fly somewhere meaningless
					TweenService:Create(disc, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
					Debris:AddItem(disc, 0.7)
					return
				end

				-- Two hops instead of one straight line. A token that arcs reads as thrown; a token that
				-- slides in a straight line reads as a UI element being repositioned.
				local midX = from.X + (target.X - from.X) * 0.45 + math.random(-70, 70)
				local midY = from.Y - math.random(60, 150)
				TweenService:Create(disc, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Position = UDim2.fromOffset(midX, midY) }):Play()
				task.delay(0.22, function()
					if not disc.Parent then return end
					local land = TweenService:Create(disc,
						TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(14, 14) })
					land:Play()
					land.Completed:Connect(function()
						if disc.Parent then
							TweenService:Create(disc, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
						end
					end)
				end)
				Debris:AddItem(disc, 1.2)
			end)
		end
	end)

	----------------------------------------------------------------
	-- 7. OUT
	----------------------------------------------------------------
	task.delay(HOLD, function()
		if not gui.Parent then return end
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Scale = 0.15 }):Play()
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(0.28), { TextTransparency = 1 }):Play()
				local st = d:FindFirstChildOfClass("UIStroke")
				if st then TweenService:Create(st, TweenInfo.new(0.28), { Transparency = 1 }):Play() end
			elseif d:IsA("Frame") then
				TweenService:Create(d, TweenInfo.new(0.28), { BackgroundTransparency = 1 }):Play()
			end
		end
		TweenService:Create(card, TweenInfo.new(0.28), { BackgroundTransparency = 1 }):Play()
		task.delay(0.45, function()
			if gui.Parent then gui:Destroy() end
			playing = false
		end)
	end)

	print(string.format("[IslandTask] reward moment played -- '%s' (%s), +%d tokens",
		tostring(questId), tostring(questName), tokens))
end

--======================================================================
-- LISTEN
--======================================================================
task.spawn(function()
	local ev = ReplicatedStorage:WaitForChild("IslandTaskRewardEvent", 60)
	if not ev then
		warn("[IslandTask] IslandTaskRewardEvent never arrived -- reward moment inactive")
		return
	end
	ev.OnClientEvent:Connect(function(questId, questName, tokens)
		tokens = tonumber(tokens) or 0
		if tokens <= 0 then return end
		-- Half a second of air. Every Candy quest ends with its OWN win banner and coin payout; landing this
		-- card on the same frame would step on both.
		task.delay(0.5, function()
			celebrate(tostring(questId or "?"), tostring(questName or "Island Quest"), tokens)
		end)
	end)
	print("[IslandTask] ready -- watching for island task rewards")
end)
