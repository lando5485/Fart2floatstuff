--======================================================================
-- TokenHud.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- THE CURRENCY CAPSULE -- tokens and coins as ONE premium component.
--
-- Tokens and coins used to be two unrelated boxes that happened to sit near each other:
-- CoreClient parked a gold coin pill at the right edge, this script glued a small blue
-- token chip beside it, and SettingsMenu parked the gear at a hand-tuned offset. Three
-- scripts, three guesses at the same corner.
--
-- The shape is now THREE NESTED CAPSULES, not one box with two rectangles cut out of it:
-- a dark-navy outer capsule, and floating inside it on a consistent inset, two fully
-- rounded pills -- navy tokens and gold coins. The frame showing through the gap between
-- them IS the divider, so it follows the same curve as everything else and there is no
-- square corner anywhere in the component.
--
-- The pills are MATCHED and SELF-SIZING. Each is only as wide as its own icon + digits +
-- "+" button, then both are squared off to the wider of the two, so there is never a slab
-- of dead orange after the coin count and the halves always look like a pair.
--
--     [ gear ] <-GAP-> (( ticket 1,234 )( $ 5,678 ))
--
-- NO DROP SHADOW BEHIND IT. Soft shadow frames stacked behind the capsule showed through
-- as a visible shaded slab on the bright HUD rather than reading as depth -- Roblox has no
-- real blur, so a "soft" shadow is just a bigger flat rectangle. All the depth here comes
-- from inside the component: gradients, inner shadows and rim highlights.
--
-- ===== WHY THE LAYOUT IS A UIListLayout AND NOTHING IS MEASURED =====
-- These HUD guis do NOT share a coordinate space. In one and the same frame CoinGui /
-- SettingsGui / RightPanelGui reported an 800x600 space while the shop, storm and banner
-- guis reported the real 2015x1042 viewport. Every earlier version of this file measured
-- pixels in one gui and wrote them into another, so the row computed correctly and landed
-- wrong -- and the diagnostics, which print early in a join before the viewport settles,
-- kept agreeing with the maths instead of the screen.
--
-- So no position is measured. The gear and the capsule are REPARENTED into one row frame
-- inside CoinGui and a UIListLayout does the spacing: one space, one scale, one owner. A
-- rival script writing Position on either is simply ignored -- children of a list layout
-- do not use their own Position at all.
--
-- The ORIGINAL coin pill is kept alive but hidden: CoreClient still owns the coin VALUE
-- (and its "+" buy button, which is adopted into the capsule so buying coins still works),
-- this file just owns how it looks. Reading the value instead of duplicating it means the
-- capsule can never disagree with CoreClient about how many coins you have.
--
-- TAP: the token pill opens the Skin Crates panel -- where tokens are spent.
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local player     = Players.LocalPlayer
local PlayerGui  = player:WaitForChild("PlayerGui")

--======================================================================
-- LOOK
--======================================================================
local CAP_W, CAP_H = 400, 60    -- the whole component
local PAD          = 6          -- inset between the outer frame and the inner pills
local INNER_GAP    = 6          -- gap between the two inner pills -- this is the divider
local GAP          = 8          -- breathing room between the gear and the capsule

local INNER_H = CAP_H - PAD * 2
local START_W = 120  -- each pill's width before fit() measures the real digits

local FRAME_TOP  = Color3.fromRGB( 46,  56,  96)  -- outer frame, lit upper edge
local FRAME_MID  = Color3.fromRGB( 28,  35,  68)
local FRAME_BOT  = Color3.fromRGB( 18,  23,  48)  -- outer frame, shaded underside
local FRAME_LINE = Color3.fromRGB( 14,  18,  38)  -- its thin containing outline
local NAVY_TOP   = Color3.fromRGB( 62, 116, 224)  -- token pill
local NAVY_MID   = Color3.fromRGB( 30,  72, 168)
local NAVY_BOT   = Color3.fromRGB( 17,  44, 116)
local NAVY_LINE  = Color3.fromRGB( 10,  26,  72)
local GOLD_TOP   = Color3.fromRGB(255, 226, 118)  -- coin pill: gold, through amber, to orange
local GOLD_MID   = Color3.fromRGB(255, 184,  46)
local GOLD_BOT   = Color3.fromRGB(233, 132,  16)
local GOLD_LINE  = Color3.fromRGB(150,  78,   6)

local function corner(inst, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = inst; return c
end
local function stroke(inst, col, t, trans)
	local s = Instance.new("UIStroke")
	s.Color = col; s.Thickness = t; s.Transparency = trans or 0
	s.LineJoinMode = Enum.LineJoinMode.Round; s.Parent = inst; return s
end
local function grad(inst, seq, rot)
	local g = Instance.new("UIGradient"); g.Color = seq; g.Rotation = rot or 90; g.Parent = inst; return g
end
local function three(a, b, c)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.55, b), ColorSequenceKeypoint.new(1, c),
	})
end

-- INNER SHADOW -- a soft dark ring hugging the inside of a pill's edge. This is what gives
-- a rounded panel the sense of sitting DOWN in its frame, and with no drop shadow behind
-- the component it is doing most of the work.
local function innerShadow(pill, radius, col, thickness, trans)
	local sh = Instance.new("Frame")
	sh.Name = "InnerShadow"
	sh.BackgroundTransparency = 1
	sh.Size = UDim2.new(1, 0, 1, 0)
	sh.ZIndex = pill.ZIndex + 1
	sh.Parent = pill
	corner(sh, radius)
	stroke(sh, col, thickness, trans)
	return sh
end

-- RIM HIGHLIGHT -- a short hairline of light along the top of a pill, fading out at both
-- ends. Gentle: it suggests one soft light source rather than a reflective strip.
local function rimLight(pill, widthFrac, trans)
	local r = Instance.new("Frame")
	r.Name = "RimLight"
	r.AnchorPoint = Vector2.new(0.5, 0)
	r.Position = UDim2.new(0.5, 0, 0, 3)
	r.Size = UDim2.new(widthFrac, 0, 0, 2)
	r.BackgroundColor3 = Color3.new(1, 1, 1)
	r.BackgroundTransparency = trans
	r.BorderSizePixel = 0
	r.ZIndex = pill.ZIndex + 3
	r.Parent = pill
	corner(r, 1)
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = r
	return r
end

-- CONTACT SHADOW -- the small soft pool an icon casts on the panel under it. Tiny, but it
-- is the difference between an icon sitting ON the surface and floating above it. This one
-- stays: it is INSIDE a pill, over a known colour, so it reads as shading, not as a slab.
local function contactShadow(parent, host, w, h)
	local sh = Instance.new("Frame")
	sh.Name = "ContactShadow"
	sh.AnchorPoint = Vector2.new(0.5, 0.5)
	sh.Position = UDim2.new(0, host.Position.X.Offset + host.Size.X.Offset / 2, 0.5, 7)
	sh.Size = UDim2.fromOffset(w, h)
	sh.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	sh.BackgroundTransparency = 0.72
	sh.BorderSizePixel = 0
	sh.ZIndex = host.ZIndex - 1
	sh.Parent = parent
	corner(sh, math.floor(h / 2))
	return sh
end

-- THE NUMBER -- white, thick clean outline, and a soft drop shadow behind it for
-- readability over both the navy and the gold. The label is AutomaticSize.X, so it is
-- exactly as wide as its digits. That is what lets the coin pill hug its own value instead
-- of reserving a fixed slot: the label drives the box, the box drives the pill's width, the
-- pill drives the capsule's. Nothing measures anything; Roblox propagates it.
--
-- The drop shadow is SCALE-sized inside the box rather than auto-sized, so it is excluded
-- from the box's content measurement -- otherwise the two labels would each try to define
-- the width and the box would fight itself.
local function autoNumber(parent, size, x)
	local box = Instance.new("Frame")
	box.Name = "ValueBox"
	box.BackgroundTransparency = 1
	box.AutomaticSize = Enum.AutomaticSize.X
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.Position = UDim2.new(0, x, 0.5, 0)
	box.Size = UDim2.fromOffset(0, 32)
	box.ZIndex = 8
	box.Parent = parent

	local shadow = Instance.new("TextLabel")
	shadow.Name = "ValueShadow"
	shadow.BackgroundTransparency = 1
	shadow.Position = UDim2.new(0, 0, 0, 2)
	shadow.Size = UDim2.new(1, 0, 1, 0)
	shadow.Font = Enum.Font.FredokaOne
	shadow.TextSize = size
	shadow.TextColor3 = Color3.new(0, 0, 0)
	shadow.TextTransparency = 0.62
	shadow.TextXAlignment = Enum.TextXAlignment.Left
	shadow.Text = "0"
	shadow.ZIndex = 8
	shadow.Parent = box

	local t = Instance.new("TextLabel")
	t.Name = "Value"
	t.BackgroundTransparency = 1
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.fromOffset(0, 32)
	t.Font = Enum.Font.FredokaOne
	t.TextSize = size
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = "0"
	t.ZIndex = 10
	t.Parent = box
	stroke(t, Color3.new(0, 0, 0), 3)

	t:GetPropertyChangedSignal("Text"):Connect(function() shadow.Text = t.Text end)
	return t
end

-- 1234567 -> "1,234,567". Big numbers are the point of a simulator HUD; an unbroken run of
-- digits is the one thing that makes them unreadable.
local function commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

--======================================================================
-- THE CAPSULE
--======================================================================
local tokenValue, coinValue, plusSlot   -- filled in by build(), read by the loop
local capRef, tokenPillRef, coinPillRef -- resized from the values, see fit() below

local PLUS_W  = 26   -- the little round "+" at the end of each pill
local TRAIL   = 12   -- air after the "+" before the pill's rounded cap
local TOKEN_X = 53   -- where each pill's number starts, measured from its own left edge
local COIN_X  = 66

-- A "+" BUTTON -- a bare white glyph on both pills, no chip behind it. A green circle read
-- as a third element competing with the icon and the number; the plus alone says the same
-- thing and lets each pill stay one clean shape. It keeps the numbers' dark outline so it
-- is just as legible on the gold as on the navy, and it is still a full-size hit target.
local function plusButton(parent, onClick)
	local b = Instance.new("TextButton")
	b.Name = "PlusBtn"
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -TRAIL, 0.5, 0)
	b.Size = UDim2.fromOffset(PLUS_W, PLUS_W)
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Font = Enum.Font.FredokaOne
	b.TextSize = 26
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = "+"
	b.ZIndex = 12
	b.Parent = parent
	local ts = Instance.new("UIStroke")  -- the same dark edge the numbers carry
	ts.Color = Color3.new(0, 0, 0); ts.Thickness = 2.5
	ts.LineJoinMode = Enum.LineJoinMode.Round
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; ts.Parent = b
	if onClick then
		b.MouseButton1Click:Connect(function()
			if _G.playUIClick then pcall(_G.playUIClick) end
			onClick()
		end)
	end
	return b
end

-- FIT -- both pills are sized from their own content, then squared off to the WIDER of the
-- two so the capsule stays symmetrical. TextBounds is the natural width of the digits and
-- is independent of the pill's own size, so there is no feedback loop between the two.
local function fit()
	if not (capRef and tokenPillRef and coinPillRef and tokenValue and coinValue) then return end
	local tw = TOKEN_X + tokenValue.TextBounds.X + 8 + PLUS_W + TRAIL
	local cw = COIN_X  + coinValue.TextBounds.X  + 8 + PLUS_W + TRAIL
	local w  = math.max(tw, cw, 120)
	if math.abs(tokenPillRef.Size.X.Offset - w) > 0.5 then
		tokenPillRef.Size = UDim2.fromOffset(w, INNER_H)
		coinPillRef.Size  = UDim2.fromOffset(w, INNER_H)
		capRef.Size       = UDim2.fromOffset(PAD * 2 + w * 2 + INNER_GAP, CAP_H)
	end
end

local function build(parent)
	-- ---- OUTER FRAME -----------------------------------------------------------------
	-- Dark navy rather than flat black, gradient-lit from above, with one thin containing
	-- outline. Nothing is drawn BEHIND it -- see the header note on drop shadows.
	local cap = Instance.new("Frame")
	cap.Name = "CurrencyCapsule"
	cap.Size = UDim2.fromOffset(CAP_W, CAP_H)
	cap.BackgroundColor3 = FRAME_BOT
	cap.BorderSizePixel = 0
	cap.ZIndex = 3
	cap.Parent = parent
	corner(cap, CAP_H / 2)
	grad(cap, three(FRAME_TOP, FRAME_MID, FRAME_BOT), 90)
	stroke(cap, FRAME_LINE, 2)

	-- the frame's own bevel: a light hairline along its top edge, nothing more
	rimLight(cap, 0.86, 0.70)

	-- ---- TOKEN PILL (left, 30%) ------------------------------------------------------
	-- A fully rounded capsule, inset by PAD on every side. A TextButton, because tapping
	-- it opens the crate panel -- the place tokens are spent.
	local tokenPill = Instance.new("TextButton")
	tokenPill.Name = "TokenPill"
	tokenPill.AnchorPoint = Vector2.new(0, 0.5)
	tokenPill.Position = UDim2.new(0, PAD, 0.5, 0)
	tokenPill.Size = UDim2.fromOffset(START_W, INNER_H)
	tokenPill.BackgroundColor3 = NAVY_BOT
	tokenPill.BorderSizePixel = 0
	tokenPill.AutoButtonColor = false
	tokenPill.Text = ""
	tokenPill.ZIndex = 5
	tokenPill.Parent = cap
	corner(tokenPill, INNER_H / 2)
	grad(tokenPill, three(NAVY_TOP, NAVY_MID, NAVY_BOT), 90)
	stroke(tokenPill, NAVY_LINE, 2)
	innerShadow(tokenPill, INNER_H / 2, Color3.fromRGB(6, 16, 48), 3, 0.55)
	rimLight(tokenPill, 0.62, 0.72)

	-- TICKET -- the emoji, larger, with a soft shadow under it. The hand-drawn ticket was
	-- crisper in theory and worse in practice; this one just reads better.
	local ticket = Instance.new("TextLabel")
	ticket.Name = "Ticket"
	ticket.BackgroundTransparency = 1
	ticket.AnchorPoint = Vector2.new(0, 0.5)
	ticket.Position = UDim2.new(0, 13, 0.5, 0)
	ticket.Size = UDim2.fromOffset(32, 32)
	ticket.Font = Enum.Font.FredokaOne
	ticket.TextSize = 28
	ticket.Text = "\xF0\x9F\x8E\x9F"
	ticket.ZIndex = 8
	ticket.Parent = tokenPill
	contactShadow(tokenPill, ticket, 26, 7)

	tokenValue = autoNumber(tokenPill, 26, TOKEN_X)

	-- BUY TOKENS -- the crate panel is where token packs live, so both the pill and its "+"
	-- lead there. Prefers a dedicated opener if one ever exists, rather than assuming.
	local function openTokenShop()
		local open = _G.openTokenShop or _G.toggleSkinCrates
		if type(open) == "function" then pcall(open) end
	end
	plusButton(tokenPill, openTokenShop)
	tokenPill.MouseButton1Click:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		openTokenShop()
	end)

	-- ---- COIN PILL (right, 70%) ------------------------------------------------------
	-- Its own rounded capsule, INNER_GAP away from the token pill. The dark frame showing
	-- through that gap is the divider -- so the divider is curved, like everything else.
	local coinPill = Instance.new("Frame")
	coinPill.Name = "CoinPill"
	coinPill.AnchorPoint = Vector2.new(1, 0.5)
	coinPill.Position = UDim2.new(1, -PAD, 0.5, 0)
	coinPill.Size = UDim2.fromOffset(START_W, INNER_H)
	coinPill.BackgroundColor3 = GOLD_BOT
	coinPill.BorderSizePixel = 0
	coinPill.ZIndex = 5
	coinPill.Parent = cap
	corner(coinPill, INNER_H / 2)
	grad(coinPill, three(GOLD_TOP, GOLD_MID, GOLD_BOT), 90)
	stroke(coinPill, GOLD_LINE, 2)
	innerShadow(coinPill, INNER_H / 2, Color3.fromRGB(140, 66, 4), 3, 0.6)
	rimLight(coinPill, 0.5, 0.74)

	-- COIN -- built in layers so it has real depth: a shaded thick edge, a lit face, a
	-- milled inner ring, an embossed $ (dark cut over a light lower lip), one small glint.
	local coin = Instance.new("Frame")
	coin.Name = "Coin"
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 14, 0.5, 0)
	coin.Size = UDim2.fromOffset(38, 38)
	coin.BackgroundColor3 = Color3.fromRGB(206, 126, 12)
	coin.BorderSizePixel = 0
	coin.ZIndex = 8
	coin.Parent = coinPill
	corner(coin, 19)
	stroke(coin, Color3.fromRGB(112, 62, 4), 2)
	contactShadow(coinPill, coin, 30, 8)

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.new(0.5, 0, 0.5, -1)
	face.Size = UDim2.fromOffset(32, 32)
	face.BackgroundColor3 = Color3.fromRGB(255, 206, 66)
	face.BorderSizePixel = 0
	face.ZIndex = 9
	face.Parent = coin
	corner(face, 16)
	grad(face, three(Color3.fromRGB(255, 243, 186), Color3.fromRGB(255, 202, 62),
		Color3.fromRGB(222, 142, 16)), 90)

	local ring = Instance.new("Frame")   -- milled inner ring
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.new(0.5, 0, 0.5, 0)
	ring.Size = UDim2.fromOffset(25, 25)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 10
	ring.Parent = face
	corner(ring, 13)
	stroke(ring, Color3.fromRGB(196, 120, 8), 1.5, 0.25)

	local lip = Instance.new("TextLabel")  -- lit lower lip of the embossed cut
	lip.Name = "DollarLip"
	lip.BackgroundTransparency = 1
	lip.Position = UDim2.new(0, 0, 0, 1)
	lip.Size = UDim2.new(1, 0, 1, 0)
	lip.Font = Enum.Font.FredokaOne
	lip.TextSize = 21
	lip.TextColor3 = Color3.fromRGB(255, 238, 170)
	lip.Text = "$"
	lip.ZIndex = 10
	lip.Parent = face

	local dollar = Instance.new("TextLabel")
	dollar.Name = "Dollar"
	dollar.BackgroundTransparency = 1
	dollar.Size = UDim2.new(1, 0, 1, 0)
	dollar.Font = Enum.Font.FredokaOne
	dollar.TextSize = 21
	dollar.TextColor3 = Color3.fromRGB(163, 92, 6)
	dollar.Text = "$"
	dollar.ZIndex = 11
	dollar.Parent = face

	local glint = Instance.new("Frame")  -- one small specular, upper left, at an angle
	glint.Name = "Glint"
	glint.AnchorPoint = Vector2.new(0.5, 0.5)
	glint.Position = UDim2.new(0.33, 0, 0.26, 0)
	glint.Size = UDim2.fromOffset(11, 6)
	glint.BackgroundColor3 = Color3.new(1, 1, 1)
	glint.BackgroundTransparency = 0.3
	glint.BorderSizePixel = 0
	glint.Rotation = -34
	glint.ZIndex = 12
	glint.Parent = face
	corner(glint, 3)

	coinValue = autoNumber(coinPill, 28, COIN_X)

	-- BUY COINS -- CoreClient's own "+" already knows how to open the coin shop, so it is
	-- adopted into this slot rather than reimplemented. The slot sits exactly where the
	-- token pill's "+" sits, and carries a matching green chip underneath in case the
	-- adopted button never arrives -- so the two pills always look like a matched pair.
	plusSlot = plusButton(coinPill, function()
		local open = _G.openCoinShop or _G.togglePremiumShop
		if type(open) == "function" then pcall(open) end
	end)
	plusSlot.Name = "PlusSlot"

	capRef, tokenPillRef, coinPillRef = cap, tokenPill, coinPill
	fit()
	return cap
end

--======================================================================
-- THE LAYOUT + VALUE PASS
--======================================================================
local warnedTwinGear = false           -- the duplicate-gear warning is worth saying once
local ZERO_ANCHOR    = Vector2.new(0, 0)

task.spawn(function()
	local capsule, nextCount = nil, 0
	while true do
		-- CoreClient owns the coin value and the coin gui; this file only re-dresses them.
		local coinFrame
		local cg = PlayerGui:FindFirstChild("CoinGui")
		if cg and cg:IsA("ScreenGui") then
			local f = cg:FindFirstChild("Frame")
			if f and f:IsA("GuiObject") then coinFrame = f end
		end

		if coinFrame then
			local row = cg:FindFirstChild("TopRightRow")
			if not row then
				-- Take the coin pill's own slot before it is hidden, so the capsule inherits the
				-- vertical position CoreClient authored for the coins.
				local cpos, canch = coinFrame.Position, coinFrame.AnchorPoint
				row = Instance.new("Frame")
				row.Name = "TopRightRow"
				row.BackgroundTransparency = 1
				row.AnchorPoint = Vector2.new(1, canch.Y)
				row.Position = UDim2.new(1, -10, cpos.Y.Scale, cpos.Y.Offset)
				row.Size = UDim2.fromOffset(0, 0)
				row.AutomaticSize = Enum.AutomaticSize.XY   -- exactly as wide as its contents
				row.ZIndex = 20
				row.Parent = cg
				local lay = Instance.new("UIListLayout")
				lay.FillDirection = Enum.FillDirection.Horizontal
				lay.HorizontalAlignment = Enum.HorizontalAlignment.Right
				lay.VerticalAlignment = Enum.VerticalAlignment.Center
				lay.SortOrder = Enum.SortOrder.LayoutOrder
				lay.Padding = UDim.new(0, GAP)
				lay.Parent = row
			end
			if not (capsule and capsule.Parent) then
				capsule = build(row)
				print("[TokenHud] currency capsule built -- two rounded pills nested in one navy "
					.. "capsule, no drop shadow (gear | capsule, laid out by UIListLayout)")
			end

			-- THE ORIGINAL PILL IS HIDDEN, NOT DESTROYED. CoreClient keeps updating its label
			-- (that is where the coin value comes from) and re-shows it whenever a menu closes,
			-- so this has to be re-asserted rather than done once.
			if coinFrame.Visible then coinFrame.Visible = false end

			-- ADOPT the "+" buy button out of the hidden pill so buying coins still works. It
			-- lands ON TOP of ours and covers it exactly, so the real handler gets the click
			-- and ours underneath is just the fallback if it never arrives.
			--
			-- CoreClient authored it as a green chip; that gets STRIPPED on the way in -- no
			-- fill, no outline, no gradient -- so the adopted button is the same bare white
			-- glyph as the token pill's. Two "+" buttons that look different would give away
			-- that they come from different scripts.
			if plusSlot and not plusSlot:FindFirstChildWhichIsA("TextButton") then
				for _, d in ipairs(coinFrame:GetDescendants()) do
					if d:IsA("TextButton") then
						d.AnchorPoint = ZERO_ANCHOR
						d.Position = UDim2.new()
						d.Size = UDim2.new(1, 0, 1, 0)
						d.ZIndex = 13
						d.BackgroundTransparency = 1
						d.AutoButtonColor = false
						d.Font = Enum.Font.FredokaOne
						d.TextSize = 26
						d.TextColor3 = Color3.new(1, 1, 1)
						for _, kid in ipairs(d:GetChildren()) do
							if kid:IsA("UIGradient") or kid:IsA("UICorner") then kid:Destroy() end
						end
						local ks = d:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
						ks.Color = Color3.new(0, 0, 0); ks.Thickness = 2.5
						ks.LineJoinMode = Enum.LineJoinMode.Round
						ks.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
						ks.Parent = d
						d.Parent = plusSlot
						break
					end
				end
			end

			-- VALUES. The coin number comes from leaderstats -- the same value CoreClient formats its own
			-- label from -- so the capsule and the label can never disagree about your balance.
			if os.clock() >= nextCount then
				nextCount = os.clock() + 0.25
				if tokenValue then
					tokenValue.Text = commas(tonumber(_G.crateTokenBalance) or 0)
				end
				if coinValue then
					local amt = coinFrame:FindFirstChild("Amount")
					-- READ THE NUMBER, DO NOT SCRAPE THE LABEL.
					--
					-- This used to take CoreClient's coin label and strip everything that was not a digit.
					-- That is exact below 1,000 and WRONG above it, because that label is ABBREVIATED:
					-- updateCoins() writes "1.2K" at a thousand and "3.4M" at a million, so stripping
					-- non-digits turned 1,200 coins into "12" and 3,400,000 into "34". The capsule was
					-- reporting a number the player had never had, and only ever past 999 -- which is
					-- exactly when the count starts mattering.
					--
					-- leaderstats.Coins is the value CoreClient itself formats FROM, so reading it directly
					-- is both correct at every magnitude and one step closer to the source. The label scrape
					-- survives only as a fallback for a realm that has no leaderstats entry.
					local ls = player:FindFirstChild("leaderstats")
					local cv = ls and ls:FindFirstChild("Coins")
					if cv and (cv:IsA("IntValue") or cv:IsA("NumberValue")) then
						coinValue.Text = commas(cv.Value)
					elseif amt and amt:IsA("TextLabel") then
						local digits = amt.Text:gsub("[^%d]", "")
						coinValue.Text = (#digits > 0) and commas(tonumber(digits)) or amt.Text
					end
				end
				fit()   -- both pills re-hug their digits, then square off to the wider one
			end

			-- THERE MAY BE TWO GEARS: SettingsMenu and HUD_AllInOne each build a ScreenGui named
			-- "SettingsGui", so FindFirstChild would return only one of them. Every copy is
			-- collected; the first is laid out, the rest are hidden as the duplicates they are.
			local gear, extras = nil, 0
			for _, sg in ipairs(PlayerGui:GetChildren()) do
				if sg:IsA("ScreenGui") and sg.Name == "SettingsGui" then
					local g = sg:FindFirstChild("SettingsGearBtn")
					if g and g:IsA("GuiObject") then
						if gear == nil then gear = g
						elseif g.Visible then g.Visible = false; extras = extras + 1 end
					end
				end
			end
			if gear == nil then gear = row:FindFirstChild("SettingsGearBtn") end
			if extras > 0 and not warnedTwinGear then
				warnedTwinGear = true
				warn("[TokenHud] hid " .. extras .. " DUPLICATE gear button(s) -- SettingsMenu and "
					.. "HUD_AllInOne both build a 'SettingsGui'. Delete one in Studio for good.")
			end

			-- ADOPT: move an element into the row once, then only keep its order. AnchorPoint is
			-- re-asserted EVERY frame, not just on the way in: a UIListLayout ignores a child's
			-- Position but NOT its AnchorPoint, and CoreClient re-stamps (1, 0) on menu close --
			-- which would slide the element a full width sideways inside the row.
			local function adopt(el, order)
				if not (el and el.Parent) then return end
				if el.Parent ~= row then
					el.Position = UDim2.new()
					el.Parent = row
				end
				if el.AnchorPoint ~= ZERO_ANCHOR then el.AnchorPoint = ZERO_ANCHOR end
				-- SCALED ONCE, NOT TWICE. The gear is born in SettingsGui, where the responsive pass gives
				-- it its OWN UIScale as a top-level child of that gui. Adopting it into this row does not
				-- remove that -- and the row is itself a top-level child of CoinGui, so it carries a second
				-- UIScale (the global scale x MOBILE_SHRINK.CoinGui = 0.78). The gear therefore rendered at
				-- scale^2 * 0.78: noticeably smaller than the pills it is supposed to match, and worse the
				-- smaller the device. The row's scale is the one that should win, so the element's own is
				-- neutralised -- re-asserted rather than destroyed, because the responsive sweep re-adds it.
				local us = el:FindFirstChildWhichIsA("UIScale")
				if us and us.Scale ~= 1 then us.Scale = 1 end
				el.LayoutOrder = order
			end
			adopt(gear, 1)      -- gear on the left
			adopt(capsule, 2)   -- the capsule on the right

			-- ===== THE ONLY MEASUREMENT LEFT: THE STATS PANEL'S RIGHT INSET, AS A FRACTION =====
			-- Read as a fraction of the PANEL gui's own width and re-applied as a fraction of OUR
			-- gui's width, so it is right whatever each gui's space happens to be -- which, per the
			-- header, is the whole problem. Falls back to the coin pill's authored 10px.
			local RIGHT_MARGIN = 10
			local ourW = cg.AbsoluteSize.X
			local rpg = PlayerGui:FindFirstChild("RightPanelGui")
			local rp = rpg and rpg:FindFirstChild("RightPanel")
			if rp and rp:IsA("GuiObject") and rp.Visible and ourW > 0 then
				local rpW = rpg.AbsoluteSize.X
				local right = rp.AbsolutePosition.X + rp.AbsoluteSize.X
				if rpW > 0 then
					local frac = (rpW - right) / rpW          -- 0 = flush to the edge
					local m = frac * ourW
					if m >= 0 and m < ourW * 0.5 then RIGHT_MARGIN = m end
				end
			end
			local pos = row.Position
			if pos.X.Scale ~= 1 or math.abs(pos.X.Offset + RIGHT_MARGIN) > 0.5 then
				row.Position = UDim2.new(1, -RIGHT_MARGIN, pos.Y.Scale, pos.Y.Offset)
			end
		end

		RunService.RenderStepped:Wait()
	end
end)

print("[TokenHud] ready -- one currency capsule [ticket | coins] beside the gear, "
	.. "right-aligned to the STATS panel (tap the token pill = Skin Crates)")
