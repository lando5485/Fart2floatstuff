--======================================================================
-- HALL OF FAME SCROLL   (LocalScript, per-player)
--======================================================================
-- SCROLL ARROWS ON THE HALL OF FAME BOARDS.
--
-- ===== WHY THIS EXISTS =====
-- Each board already IS a ScrollingFrame holding up to 100 rows behind a window that shows about nine, and
-- LeaderboardService sets SurfaceGui.Active so it accepts input. But a SurfaceGui out in the world only
-- scrolls if you press ON it and DRAG -- the mouse wheel does nothing there, because the wheel belongs to the
-- camera, not to a panel you happen to be looking at. So a board that was built to scroll reads, to everyone
-- standing in front of it, as a board that just stops at #9. This adds the one affordance that fixes that:
-- a visible pair of arrows you click, on a board that never advertised it could move.
--
-- ===== WHY THE BUTTONS ARE BUILT ON THE CLIENT =====
-- LeaderboardService builds the boards on the SERVER, and a server script can never hear a GUI button:
-- clicks on a world SurfaceGui are processed by the client that made them, and MouseButton1Click simply does
-- not fire server-side. Buttons added there would be decoration. Built here they are local to this player --
-- their scroll position is theirs alone, which is what you want anyway: two people reading the same sign
-- should be able to be on different pages of it.
--
-- ===== EVERYTHING IS RE-ENTRANT =====
-- The plaza is built at runtime and streams in and out as the player flies past, so boards arrive late and
-- can arrive twice. Each ScrollingFrame is tagged the moment it is fitted (a child named "ScrollArrows"), and
-- a board that already carries one is skipped -- so the DescendantAdded sweep can run as often as it likes
-- without stacking arrows on top of arrows.
--======================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local ARROW_W, ARROW_H = 44, 42
local STEP_FRACTION    = 0.8   -- one tap moves 80% of a window: overlapping by a row keeps your place

-- The board's own accent colour, so the arrows belong to the panel rather than sitting on it. The Rows frame
-- already carries it on its scrollbar, which is the one place it is readable from without asking the server.
local function accentOf(rows: ScrollingFrame): Color3
	return rows.ScrollBarImageColor3
end

local function makeArrow(rows: ScrollingFrame, holder: Frame, glyph: string, atTop: boolean, dir: number)
	local b = Instance.new("TextButton")
	b.Name                   = atTop and "Up" or "Down"
	b.AnchorPoint            = Vector2.new(1, atTop and 0 or 1)
	b.Position               = UDim2.new(1, -2, atTop and 0 or 1, 0)
	b.Size                   = UDim2.fromOffset(ARROW_W, ARROW_H)
	b.BackgroundColor3       = Color3.fromRGB(26, 32, 48)
	b.BackgroundTransparency = 0.15
	b.AutoButtonColor        = true
	b.BorderSizePixel        = 0
	b.Font                   = Enum.Font.GothamBlack
	b.Text                   = glyph
	b.TextSize               = 24
	b.TextColor3             = accentOf(rows)
	b.Parent                 = holder
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	local st = Instance.new("UIStroke")
	st.Color, st.Thickness, st.Transparency = accentOf(rows), 2, 0.25
	st.Parent = b

	-- One tap = one page. Clamped to the canvas, so the bottom arrow lands exactly on the last row rather
	-- than scrolling into empty space and leaving the player looking at nothing.
	local function page()
		local window = rows.AbsoluteWindowSize.Y
		local maxY   = math.max(0, rows.AbsoluteCanvasSize.Y - window)
		local y      = math.clamp(rows.CanvasPosition.Y + dir * window * STEP_FRACTION, 0, maxY)
		rows.CanvasPosition = Vector2.new(0, y)
		if _G.playUIClick then pcall(_G.playUIClick) end
	end
	b.Activated:Connect(page)
	return b
end

local function fit(rows: ScrollingFrame)
	if rows:FindFirstChild("ScrollArrows") then return end -- already fitted (streamed back in, or a re-sweep)

	-- The arrows ride in their own frame so they do NOT sit in the UIListLayout that stacks the rows -- a
	-- child of the list would be laid out as if it were a leaderboard entry, and would scroll away with them.
	local holder = Instance.new("Frame")
	holder.Name                   = "ScrollArrows"
	holder.Size                   = UDim2.new(1, 0, 1, 0)
	holder.BackgroundTransparency = 1
	holder.ZIndex                 = 20
	holder.Parent                 = rows

	local up   = makeArrow(rows, holder, "\xE2\x96\xB2", true, -1)
	local down = makeArrow(rows, holder, "\xE2\x96\xBC", false, 1)

	-- ===== KEEPING THE ARROWS STILL =====
	-- holder is a child of the ScrollingFrame, so it scrolls with the canvas. Rather than reparent it (the
	-- board's background frame is the server's, and dropping UI into it invites a fight with a future
	-- rebuild), the holder is simply moved by the same amount the canvas moved -- which pins it to the
	-- window. The arrows also fade out when there is nothing to scroll to, so a board with four names on it
	-- does not offer a control that cannot do anything.
	local function follow()
		holder.Position = UDim2.fromOffset(0, rows.CanvasPosition.Y)
		local maxY = math.max(0, rows.AbsoluteCanvasSize.Y - rows.AbsoluteWindowSize.Y)
		up.Visible   = maxY > 1
		down.Visible = maxY > 1
		up.TextTransparency   = (rows.CanvasPosition.Y <= 1) and 0.65 or 0
		down.TextTransparency = (rows.CanvasPosition.Y >= maxY - 1) and 0.65 or 0
	end
	rows:GetPropertyChangedSignal("CanvasPosition"):Connect(follow)
	rows:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(follow)
	rows:GetPropertyChangedSignal("CanvasSize"):Connect(follow)
	follow()
end

-- A board is: a Part named "Panel" -> SurfaceGui "Board" -> Frame -> ScrollingFrame "Rows", inside a Model
-- named Leaderboard_<key>. Matching on the ScrollingFrame's own name AND its Leaderboard ancestor keeps this
-- off every other ScrollingFrame in the game.
local function consider(inst: Instance)
	if not inst:IsA("ScrollingFrame") or inst.Name ~= "Rows" then return end
	local model = inst:FindFirstAncestorWhichIsA("Model")
	if not (model and model.Name:sub(1, 12) == "Leaderboard_") then return end
	fit(inst)
end

for _, d in ipairs(Workspace:GetDescendants()) do consider(d) end
Workspace.DescendantAdded:Connect(consider)

print("[HallOfFame] scroll arrows ready -- the boards page with a click as well as a drag (" ..
	player.Name .. ", client-side and local to this player)")
