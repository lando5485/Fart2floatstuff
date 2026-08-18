--======================================================================
-- HousePanel.client.luau  (StarterPlayerScripts)  -- CandyRealm
--======================================================================
-- ONE SHAPE FOR EVERY TASK HUD, AND ONE PLACE THAT HIDES THE BOTTOM BUTTONS.
--
-- Every island grew its own station panel and every one is a different size in a different spot:
-- the oven is 560x290, the mixing bowl 560x420, the tractor repair 560x240, the mill minigame
-- 540x152, the delivery card 468x400, the fishing panel 300x360. Open two on one trip and they do
-- not even agree with each other, let alone with the Pet Hub, the Shop or the MORE+ menu -- which
-- are all the same 700x520 card in the same place.
--
-- ===== THE HOUSE PANEL =====
-- Copied off the Pet Hub, which is the reference every main menu already matches:
--     Size = 700 x 520      Position = (0.5, 0), (0.5, -45)      AnchorPoint = (0.5, 0.5)
-- The -45 is not decoration: it lifts the card off the bottom HUD so the two never touch.
--
-- ===== IT RESIZES YOUR PANEL TO 700x520 =====
-- Every adopted HUD is set to the house size outright, not scaled to fit inside it. Scale-to-fit
-- kept each panel's aspect ratio, so a 560x158 minigame strip came out 700x197 -- the house
-- position, but not the house dimensions, and still visibly a different card from the Shop.
--
-- These panels are built the way the Pet Hub is -- headers sized (1,0,0,H), content sized (1,-pad),
-- buttons ANCHORED to a corner -- so their children follow the new edges on their own. The close X
-- lands in the real corner instead of floating where the old corner was.
--
-- A panel that genuinely cannot take a resize opts out with the NoHouseResize attribute and gets
-- the old scale-to-fit treatment.
--
-- ===== IT ALSO OWNS THE BOTTOM HUD =====
-- Hiding the fart button / gas meter / rail while a HUD is up used to be a separate call the quest
-- had to remember at every show AND every hide -- and a missed hide leaves the buttons gone for
-- the rest of the session. Here it is automatic: the shell watches the panel's own Visible (and
-- its ScreenGui's Enabled) and holds the bottom HUD for exactly as long as the panel is on screen.
-- One call, both jobs, and nothing to forget.
--
-- Refcounted by tag, because two HUDs can legitimately overlap (an oven timer running while you
-- open the mixing bowl). The bottom HUD's real state is captured on the FIRST hold and restored
-- only when the LAST one lets go -- otherwise whichever closed first would hand the buttons back
-- underneath the other one.
--
--     _G.housePanel(panel)            -- adopt a task HUD: house size, house spot, auto hide/show
--     _G.hudHold("tag", true/false)   -- hold the bottom HUD directly, if you have no panel
--======================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- the Pet Hub's card, which the Shop and MORE+ already copy
local PANEL_W, PANEL_H = 700, 520
-- Only the value the shell is born with -- layoutShell() overwrites it on the same frame and on
-- every resize thereafter. Kept so a shell is never briefly at (0,0) before the first layout.
local PANEL_POS    = UDim2.new(0.5, 0, 0.5, -45)
local PANEL_ANCHOR = Vector2.new(0.5, 0.5)

-- ============================================================================
-- THE BOTTOM HUD HOLD  (promoted from BakeryQuest, which had the only working copy)
-- ============================================================================
local hudHold
do
	local NAMES = { "BottomStackGui", "GasMeterGui", "FartButtonGui", "StomachGui" }
	local held, prev = {}, nil
	function hudHold(tag, hidden)
		held[tag] = hidden or nil
		local any = next(held) ~= nil
		if any and not prev then
			prev = {}
			for _, n in ipairs(NAMES) do
				local sg = PlayerGui:FindFirstChild(n)
				if sg and sg:IsA("ScreenGui") then prev[n] = sg.Enabled; sg.Enabled = false end
			end
		elseif not any and prev then
			for n, was in pairs(prev) do
				local sg = PlayerGui:FindFirstChild(n)
				if sg and sg:IsA("ScreenGui") then sg.Enabled = was end
			end
			prev = nil
		end
	end
end
_G.hudHold = hudHold

-- ============================================================================
-- ADOPT A PANEL
-- ============================================================================

-- ============================================================================
-- WHERE THE CARD ACTUALLY GOES
-- ============================================================================
-- The house spot used to be a flat (0.5, 0), (0.5, -45): centred, lifted 45px. That -45 was
-- measured against one screen and it does not hold. At the 1280x720 design reference a 700x520
-- card centred at -45 spans y 55..575 -- while the coin pill occupies 10..62 and the bottom meter
-- card 564..708. It overlaps BOTH, at the resolution everything else is authored for, and the
-- shorter the window the worse it gets.
--
-- So the card is centred in the FREE BAND: the vertical space actually left between the top HUD
-- and the bottom HUD. If the band is shorter than the card, the whole shell scales down uniformly
-- until it fits -- the card stays 700x520 in its own coordinates, so every panel inside it is
-- unaffected and every HUD still gets the identical treatment.
--
-- Horizontally it stays screen-centred rather than centred between the left rail and the right
-- stats panel: those are not symmetrical (95 vs 230 wide), so centring between them would sit the
-- card visibly left of middle. It only has to FIT the width, not dodge it.
local TOP_RESERVE    = 84    -- coin pill: 52 tall at y10, + breathing room
local BOTTOM_RESERVE = 176   -- bottom meter card: 144 tall at bottom-12, + breathing room
local SIDE_MARGIN    = 24    -- never let the card touch the screen edge

local function layoutShell(shell, uiscale)
	local cam = Workspace.CurrentCamera
	local vp  = cam and cam.ViewportSize
	if not (vp and vp.X > 1 and vp.Y > 1) then return end   -- boot reports 1x1; a resize corrects it

	local bandTop    = TOP_RESERVE
	local bandBottom = vp.Y - BOTTOM_RESERVE
	local bandH      = math.max(120, bandBottom - bandTop)  -- floor: a tiny window still gets a card
	local availW     = math.max(200, vp.X - SIDE_MARGIN * 2)

	-- uniform, never grown past 1: a big monitor shows the authored card, small screens shrink it
	uiscale.Scale = math.min(1, availW / PANEL_W, bandH / PANEL_H)

	-- centre of the free band, as a fraction of the screen -- so it tracks a resize on its own
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position    = UDim2.fromScale(0.5, ((bandTop + bandBottom) * 0.5) / vp.Y)
end

local adopted = setmetatable({}, { __mode = "k" })   -- weak: a destroyed HUD must not be pinned here
local nextTag = 0

local function adopt(panel)
	if typeof(panel) ~= "Instance" or not panel:IsA("GuiObject") then return panel end
	if adopted[panel] then return panel end
	adopted[panel] = true

	local parent = panel.Parent
	if not parent then return panel end

	nextTag += 1
	local tag = "housePanel" .. nextTag

	-- the shell: house size, house spot. The panel moves inside it and keeps its own geometry.
	local shell = Instance.new("Frame")
	shell.Name = "HouseShell"
	shell.BackgroundTransparency = 1
	shell.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	shell.Position = PANEL_POS
	shell.AnchorPoint = PANEL_ANCHOR
	shell.ZIndex = panel.ZIndex
	shell.Visible = panel.Visible
	shell.Parent = parent

	-- ONE OWNER FOR THE FIT. ResponsiveUI puts its own shrink-to-fit UIScale on every ScreenGui's
	-- children, and the shell is one of those children -- two systems sizing the same card, with
	-- only one UIScale per instance actually read. layoutShell() below already measures the live
	-- viewport, so it opts out and owns the card outright.
	shell:SetAttribute("NoResponsiveScale", true)
	local shellScale = Instance.new("UIScale")
	shellScale.Parent = shell
	layoutShell(shell, shellScale)
	do
		local cam = Workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				layoutShell(shell, shellScale)
			end)
		end
	end

	-- ===== THE CARD IS THE PET HUB'S CARD, EXACTLY =====
	-- The panel is RESIZED to 700x520 and fills the shell. Not scaled-to-fit -- actually resized.
	--
	-- This reverses the original decision, and the reason is worth keeping. Scale-to-fit preserved
	-- each panel's aspect ratio, which meant a 560x158 minigame strip rendered as 700x197: the house
	-- POSITION, but not the house DIMENSIONS. Open the Shop (700x520) and then a task HUD and they
	-- were still visibly two different cards -- which is the whole thing this file exists to stop.
	--
	-- ===== WHY RESIZING IS SAFE HERE, WHEN THE HEADER USED TO SAY IT WAS NOT =====
	-- The old warning assumed children pinned in absolute pixels against the original width. In
	-- practice these panels are built the way the Pet Hub is: headers sized (1, 0, 0, H), content
	-- sized (1, -pad) / (1, -pad), and buttons ANCHORED to a corner -- (1,1) for a close X, (0.5,1)
	-- for a footer row. Every one of those is relative, so they follow the new edges by themselves,
	-- which is exactly what you want: the X ends up in the real corner instead of floating where the
	-- old corner used to be.
	--
	-- What a resize CAN move is a child positioned by fixed offset from the LEFT that was meant to
	-- read as right-aligned. That is a bug in the child either way -- it was already wrong on any
	-- other panel width -- and it shows up immediately rather than silently.
	--
	-- A panel that genuinely cannot take it can opt out: set the attribute NoHouseResize on it and
	-- it keeps its own size and gets the old scale-to-fit treatment instead.
	panel.Parent = shell
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)

	local us = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	us.Parent = panel

	if panel:GetAttribute("NoHouseResize") then
		-- opt-out: keep its own geometry, fit it inside the card like the original behaviour
		local w = math.max(1, panel.AbsoluteSize.X > 0 and panel.AbsoluteSize.X or panel.Size.X.Offset)
		local h = math.max(1, panel.AbsoluteSize.Y > 0 and panel.AbsoluteSize.Y or panel.Size.Y.Offset)
		us.Scale = math.min(PANEL_W / w, PANEL_H / h)
	else
		us.Scale = 1                                  -- 1:1, so nothing is resampled and text stays crisp
		panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	end

	-- ---- the bottom HUD follows the panel's own visibility ----
	-- Watching rather than being told is the whole point: a quest that forgets to un-hide on one
	-- of its exit paths cannot strand the player with no buttons.
	local function sync()
		local sg = panel:FindFirstAncestorWhichIsA("ScreenGui")
		local up = panel.Visible and shell.Visible and (not sg or sg.Enabled)
		hudHold(tag, up and true or nil)
	end
	panel:GetPropertyChangedSignal("Visible"):Connect(sync)
	shell:GetPropertyChangedSignal("Visible"):Connect(sync)
	do
		local sg = panel:FindFirstAncestorWhichIsA("ScreenGui")
		if sg then sg:GetPropertyChangedSignal("Enabled"):Connect(sync) end
	end
	-- a destroyed HUD must release the hold, or the buttons never come back
	panel.AncestryChanged:Connect(function(_, newParent)
		if not newParent then hudHold(tag, nil) end
	end)
	sync()

	return panel
end


_G.housePanel = adopt

print(("[HousePanel] ready -- _G.housePanel(frame) sets a task HUD to the Pet Hub's %dx%d card, centres it"
	.. " in the free band between the top and bottom HUD (reserving %d / %d px) and shrinks it uniformly if"
	.. " that band is shorter than the card. It also hides the bottom buttons while the HUD is up."
	.. " _G.hudHold(tag,bool) is the same hold on its own.")
	:format(PANEL_W, PANEL_H, TOP_RESERVE, BOTTOM_RESERVE))
