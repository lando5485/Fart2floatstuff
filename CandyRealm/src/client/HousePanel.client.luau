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
--     Size = 700 x 260      Position = centred in the free band      AnchorPoint = (0.5, 0.5)
-- The WIDTH is the Pet Hub's. The HEIGHT is half of it (520 -> 260), because a task HUD is a few
-- rows you read and act on, not a browsable list -- see the PANEL_H note below for why.
-- The card is centred in the free band between the top and bottom HUD, so it never touches either.
--
-- ===== IT RESIZES YOUR PANEL TO 700x260 =====
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

-- ============================================================================
-- _G.housePanel IS PUBLISHED **BEFORE THE FIRST YIELD**, AS A QUEUE
-- ============================================================================
-- THIS IS A LOAD-ORDER FIX, AND IT IS THE REASON MOST TASK HUDs WERE NEVER ADOPTED.
--
-- Quest scripts adopt with `pcall(_G.housePanel, panel)`, and several of them do it at TOP LEVEL,
-- i.e. the moment the script runs. Every LocalScript in StarterPlayerScripts starts at roughly the
-- same time and runs until it yields -- and this file used to yield on WaitForChild("PlayerGui")
-- before it ever assigned _G.housePanel. So whether a quest got adopted came down to which script
-- happened to reach its adopt call first:
--
--     17:16:51.522  [Bakery]     loaded   <- adopts the recipe chooser at top level: _G.housePanel is NIL
--     17:16:51.525  [Tractor]    loaded   <- same
--     17:16:51.538  [Cleanup]    loaded   <- same
--     17:16:51.555  [HousePanel] ready    <- _G.housePanel finally exists
--     17:16:51.596  [Park]       loaded   <- adopts the console + wrench: WORKS
--
-- pcall SWALLOWS the "attempt to call a nil value", so those panels were silently never adopted --
-- no error, no warning, just a HUD sitting wherever its own author put it. The park's crank console
-- and wrench were the ones that looked right purely because that file loads 40ms later.
--
-- The stub below is assigned before ANY yield in this file, so it exists as early as this script can
-- make it exist. It banks whatever it is handed; the real adopt() drains the queue at the bottom.
local pendingAdoptions = {}
_G.housePanel = function(panel)
	pendingAdoptions[#pendingAdoptions + 1] = panel
	return panel
end

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== THE PET HUB'S CARD, COPIED EXACTLY =====
-- Size, position and anchor are the Pet Hub's, verbatim:
--     Size = 700 x 520      Position = (0.5, 0), (0.5, -45)      AnchorPoint = (0.5, 0.5)
-- and this file deliberately does NO layout maths of its own any more. It used to compute a
-- "free band" between the top and bottom HUD and centre the card in it, which was a second,
-- parallel way of placing a panel -- and it was measurably wrong: on a live 1848x1001 client the
-- card landed at y=266 when its own arithmetic said 324, with viewport, gui height and scale all
-- reading correct. Rather than keep chasing a 58px discrepancy in a bespoke layout, the card now
-- uses the one placement that is already proven on screen every day by the Shop, the Pet Hub,
-- MORE+, Daily Tasks, Season Pass, Rebirth and Gifting.
--
-- It also no longer opts out of ResponsiveUI, so small screens shrink a task HUD exactly the way
-- they shrink the menus. Same size, same spot, same scaling, one code path.
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
-- measured against one screen and it does not hold. At the 1280x720 design reference the old 520-tall
-- card centred at -45 spanned y 55..575 -- while the coin pill occupies 10..62 and the bottom meter
-- card 564..708. It overlapped BOTH, at the resolution everything else is authored for, and the
-- shorter the window the worse it got. (At 260 tall the card clears them comfortably, but the band
-- centring below is still what guarantees it on every other viewport.)
--
-- So the card is centred in the FREE BAND: the vertical space actually left between the top HUD
-- and the bottom HUD. If the band is shorter than the card, the whole shell scales down uniformly
-- until it fits -- the card stays 700x260 in its own coordinates, so every panel inside it is
-- unaffected and every HUD still gets the identical treatment. At half the height the band is now
-- taller than the card on almost every screen, so that shrink rarely has to fire at all.
--
-- Horizontally it stays screen-centred rather than centred between the left rail and the right
-- stats panel: those are not symmetrical (95 vs 230 wide), so centring between them would sit the
-- card visibly left of middle. It only has to FIT the width, not dodge it.
local TOP_RESERVE    = 84    -- coin pill: 52 tall at y10, + breathing room
local BOTTOM_RESERVE = 176   -- bottom meter card: 144 tall at bottom-12, + breathing room
local SIDE_MARGIN    = 24    -- never let the card touch the screen edge

-- The Pet Hub's spot. The -45 lifts the card off the bottom HUD; it is the same nudge every
-- main menu in this realm uses, which is the whole point of copying it rather than deriving one.
local function layoutShell(shell)
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position    = UDim2.new(0.5, 0, 0.5, -45)
	shell.Size        = UDim2.fromOffset(PANEL_W, PANEL_H)
end

local adopted = setmetatable({}, { __mode = "k" })   -- weak: a destroyed HUD must not be pinned here
local nextTag = 0

-- Above NotifyCenter's hero (95) and social (94) banner lanes, below the shop/menu layer (100).
local HUD_ORDER = 98

local function adopt(panel)
	if typeof(panel) ~= "Instance" or not panel:IsA("GuiObject") then return panel end
	if adopted[panel] then return panel end
	adopted[panel] = true

	-- An unparented panel is not a failure, it is a panel that has not been placed YET. This used to
	-- return silently WITH the panel already marked adopted, so it could never be picked up again --
	-- the same silent-drop as the nil _G.housePanel above. Retry when it lands in the tree instead.
	local parent = panel.Parent
	if not parent then
		adopted[panel] = nil
		local conn
		conn = panel:GetPropertyChangedSignal("Parent"):Connect(function()
			if panel.Parent then
				conn:Disconnect()
				adopt(panel)
			end
		end)
		return panel
	end

	-- ========================================================================
	-- THE HOST ScreenGui MUST IGNORE THE GUI INSET
	-- ========================================================================
	-- THIS IS WHY TWO HUDs WITH IDENTICAL Size AND Position LANDED IN DIFFERENT PLACES.
	--
	-- A ScreenGui with IgnoreGuiInset = false (the DEFAULT) has its whole coordinate space pushed
	-- down by Roblox's ~36px topbar. So UDim2.fromScale(0.5, 0.5) in an inset ScreenGui renders
	-- 36px LOWER on the real screen than the exact same UDim2 in a non-inset one -- and layoutShell
	-- below measures the FULL viewport, so an inset host silently lands the card 36px below where
	-- the maths put it.
	--
	-- The realm was split straight down the middle on this, and the split is invisible in the code
	-- because the flag is set on the ScreenGui, nowhere near the panel:
	--
	--     ParkWrench ("TIGHTEN THE COUPLING") ... IgnoreGuiInset = true    <- the one that looks right
	--     island13 irrigation console .......... inset  (36px low)
	--     island15 mixing bowl / oven .......... inset  (36px low)
	--     island19 tractor part repair ......... inset  (36px low)
	--     island5 delivery card ................ inset  (36px low)
	--     fishing panel ........................ inset  (36px low)
	--
	-- Holding Size/Position/AnchorPoint cannot fix this -- every one of those panels ALREADY had the
	-- right Position; they were being measured against a different origin. So the origin is
	-- normalised here instead: every host of an adopted task HUD ignores the inset, which makes the
	-- card's computed spot and its real spot the same thing on every island.
	--
	-- Safe for the ScreenGui's other children: what else lives in these is full-screen backdrops and
	-- dim films sized (1,0,1,0), which should cover the topbar strip anyway rather than stopping 36px
	-- short of it.
	do
		local hostGui = panel:FindFirstAncestorWhichIsA("ScreenGui")
		if hostGui and not hostGui.IgnoreGuiInset then
			hostGui.IgnoreGuiInset = true
			print(("[HousePanel] '%s' did not ignore the GUI inset -- its card was rendering ~36px "
				.. "below every other task HUD. Normalised."):format(hostGui.Name))
		end

		-- ====================================================================
		-- THE TASK HUD SITS ABOVE THE BANNERS. IT IS THE THING YOU ARE USING.
		-- ====================================================================
		-- Quest HUDs were authored at DisplayOrder 7..14; NotifyCenter's hero lane is 95 and its
		-- social lane 94. So EVERY banner in the realm -- island arrivals, purchases, event
		-- callouts, the mirrored objective line -- drew straight over the top of the card you
		-- were actually playing with, and the mini-game underneath simply vanished behind an
		-- announcement you did not ask for at that moment.
		--
		-- Fixed HERE rather than in the twelve quest files, for the same reason the inset is:
		-- this function already adopts every task HUD in the realm, so one rule covers the ones
		-- that exist and the ones nobody has written yet.
		--
		-- 98 is chosen, not arbitrary: ABOVE the hero/social banners (95/94), and still BELOW
		-- the shop and menu layer at 100 -- a menu you deliberately opened must cover a task
		-- card, while a banner that arrived on its own must not.
		if hostGui and hostGui.DisplayOrder < HUD_ORDER then
			local was = hostGui.DisplayOrder
			hostGui.DisplayOrder = HUD_ORDER
			print(("[HousePanel] '%s' DisplayOrder %d -> %d, so banners (95) can no longer "
				.. "cover the task HUD."):format(hostGui.Name, was, HUD_ORDER))
		end
	end

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

	-- NO NoResponsiveScale, and no UIScale of our own. ResponsiveUI is the single owner of fit for
	-- every menu in this realm; a task HUD is now just another one of its cards.
	layoutShell(shell)
	do
		local cam = Workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				layoutShell(shell)
			end)
		end
	end

	-- ===== RE-LAY-OUT AFTER ADOPTION. THE ONE-SHOT LAYOUT GOES STALE. =====
	-- layoutShell used to run exactly once here, then only again if ViewportSize CHANGED. That is fine
	-- for a HUD built at boot -- the viewport settles right after and the change handler corrects it --
	-- but it is wrong for a HUD built at RUNTIME, which most mini-games are: it captures whatever the
	-- viewport happens to be at the instant you tap the prop, and if nothing resizes afterwards there is
	-- no second chance. Measured on a 1848x1001 screen, island 1's chute rattle landed at y=266 when the
	-- band maths says 324 -- 58px high -- while boot-built cards sat correctly. Same code, same
	-- constants, different capture moment. That is the "these HUDs are in different places" bug.
	--
	-- So the layout is re-run on the next frame and again a beat later. Both are no-ops when the first
	-- pass was already right, and they cost nothing -- layoutShell is arithmetic on two numbers.
	task.defer(function()
		if shell.Parent then layoutShell(shell) end
	end)
	task.delay(0.2, function()
		if shell.Parent then layoutShell(shell) end
	end)

	-- ===== THE CARD IS THE PET HUB'S CARD, EXACTLY =====
	-- The panel is RESIZED to 700x260 and fills the shell. Not scaled-to-fit -- actually resized.
	--
	-- This reverses the original decision, and the reason is worth keeping. Scale-to-fit preserved
	-- each panel's aspect ratio, which meant a 560x158 minigame strip rendered as 700x197: the house
	-- POSITION, but not the house DIMENSIONS. Open the Shop and then a task HUD and they were still
	-- visibly two different cards -- which is the whole thing this file exists to stop. (Task HUDs now
	-- run at half the menus' height by design; they still share the width, the spot and the treatment.)
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

	local optedOut = panel:GetAttribute("NoHouseResize") == true
	if optedOut then
		-- opt-out: keep its own geometry, fit it inside the card like the original behaviour
		local w = math.max(1, panel.AbsoluteSize.X > 0 and panel.AbsoluteSize.X or panel.Size.X.Offset)
		local h = math.max(1, panel.AbsoluteSize.Y > 0 and panel.AbsoluteSize.Y or panel.Size.Y.Offset)
		us.Scale = math.min(PANEL_W / w, PANEL_H / h)
	else
		us.Scale = 1                                  -- 1:1, so nothing is resampled and text stays crisp
		panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	end

	-- ========================================================================
	-- THE HOUSE GEOMETRY IS ENFORCED, NOT JUST SET ONCE
	-- ========================================================================
	-- Setting Size/Position at adopt time is not enough, and island 13's wrench mini-game is the
	-- proof. It opened with:
	--
	--     MG.panel.Position = UDim2.new(0.5, -270, 0.82, 0)          -- then tweened to 0.74
	--
	-- Those numbers were measured against the SCREEN, back when the panel placed itself. After
	-- adoption the panel lives inside this shell, so the same UDim2 resolves INSIDE THE CARD:
	-- x = 0.5*700 - 270 = 80, y = 0.74*260 = 192. The card sat low and left in its own shell with
	-- half of it hanging outside -- while every other task HUD sat dead centre. One line, written
	-- once, in a file nobody would think to look in, and that HUD was in a different place from
	-- all the others for as long as it existed.
	--
	-- So the house geometry is now HELD. Anything that writes Size, Position or AnchorPoint after
	-- adoption is put straight back, and the first time it happens the offender is NAMED in a
	-- warning -- because the real fix is always at the call site, and this is how you find it.
	--
	-- WHAT TO DO IF YOU HIT THE WARNING: you almost certainly wanted an OPEN ANIMATION, not a move.
	-- Tween the panel's UIScale instead -- it is created above, housePanel never writes it again,
	-- and it gives the identical pop without touching the geometry the card owns. Both the island
	-- 13 wrench and the island 14 mill do exactly that now.
	--
	-- Position/AnchorPoint are held for EVERY panel. Size is held only for panels that did not opt
	-- out with NoHouseResize -- an opted-out panel owns its own size by definition.
	local HOUSE_POS    = UDim2.fromScale(0.5, 0.5)
	local HOUSE_ANCHOR = Vector2.new(0.5, 0.5)
	local HOUSE_SIZE   = UDim2.fromOffset(PANEL_W, PANEL_H)
	do
		local holding, warned = false, false
		local function announce(prop)
			if warned then return end
			warned = true
			warn(("[HousePanel] '%s' wrote %s AFTER adoption -- put back to the house card. Every task HUD "
				.. "has to be the same size in the same spot, so the card's geometry is held here. If you "
				.. "wanted an open animation, tween the panel's UIScale instead (see the note in "
				.. "HousePanel.client.luau).")
				:format(panel:GetFullName(), prop))
		end
		local function hold(prop, apply)
			panel:GetPropertyChangedSignal(prop):Connect(function()
				if holding then return end     -- our own write, not theirs
				holding = true
				apply()
				holding = false
				announce(prop)
			end)
		end
		-- A panel that deliberately ANIMATES its position -- island 11's drill shakes itself as it
		-- bites -- opts out with the HouseAnimatesPosition attribute. The contract for opting out is
		-- that the animation is centred on the house spot and RETURNS to it (the drill offsets from
		-- UDim2.fromScale(0.5, 0.5), which is the shell centre), so the resting geometry is still
		-- identical to every other card. AnchorPoint is held either way -- nothing needs to move it.
		if not panel:GetAttribute("HouseAnimatesPosition") then
			hold("Position", function() panel.Position = HOUSE_POS end)
		end
		hold("AnchorPoint", function() panel.AnchorPoint = HOUSE_ANCHOR end)
		if not optedOut then
			hold("Size",    function() panel.Size        = HOUSE_SIZE end)
		end
	end

	-- ---- the bottom HUD follows the panel's own visibility ----
	-- Watching rather than being told is the whole point: a quest that forgets to un-hide on one
	-- of its exit paths cannot strand the player with no buttons.
	-- ===== MEASURE WHAT ACTUALLY LANDS ON SCREEN =====
	-- Every "these HUDs are in different places" argument so far has been fought with SOURCE values --
	-- authored Size, authored Position, IgnoreGuiInset. Those are inputs. This prints the OUTPUT:
	-- the real pixel rect Roblox drew, read one frame after the card goes up so the layout has settled.
	--
	-- Open two task HUDs and compare the two lines. If the rects match, the cards ARE identical and
	-- whatever looks different is inside them (content that overflows or does not fill). If the rects
	-- differ, the numbers say exactly how far off and in which axis, which beats guessing.
	local RunService = game:GetService("RunService")
	local wasUp = false
	local function report()
		local sg = panel:FindFirstAncestorWhichIsA("ScreenGui")
		local cam = Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(0, 0)
		-- ⚠ EVERY NUMBER IS FLOORED. AbsolutePosition/AbsoluteSize are FLOATS and %d on a value with a
		-- fractional part throws "number has no integer representation" -- which would error inside the
		-- visibility handler and take the mini-game's HUD down with it. The earlier readings happened to
		-- land on whole pixels; the Pet Hub's -45 offset makes a half-pixel centre entirely possible.
		local function i(n) return math.floor((tonumber(n) or 0) + 0.5) end
		print(("[HousePanel:MEASURED] %-18s pos=(%d, %d)  size=(%d x %d)  inset=%s  "
			.. "viewport=%dx%d  guiH=%d")
			:format(sg and sg.Name or "?",
				i(panel.AbsolutePosition.X), i(panel.AbsolutePosition.Y),
				i(panel.AbsoluteSize.X), i(panel.AbsoluteSize.Y),
				(sg and tostring(sg.IgnoreGuiInset)) or "?",
				i(vp.X), i(vp.Y),
				i(sg and sg.AbsoluteSize.Y or -1)))
	end

	local function sync()
		local sg = panel:FindFirstAncestorWhichIsA("ScreenGui")
		local up = panel.Visible and shell.Visible and (not sg or sg.Enabled)
		hudHold(tag, up and true or nil)
		if up and not wasUp then
			wasUp = true
			-- the card may have been adopted minutes ago on a different window size
			layoutShell(shell)
			task.delay(0.1, function()
				if not panel.Parent then return end
				layoutShell(shell)
				report()
			end)
		elseif not up then
			wasUp = false
		end
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


-- The real adopt replaces the stub, then everything the stub banked before this script got here is
-- run through it. Panels adopted "too early" now land exactly where a late one does.
-- ============================================================================
-- ADOPTION BY ATTRIBUTE -- THE ONLY THING THAT SURVIVES LOAD ORDER
-- ============================================================================
-- The queueing stub at the top of this file only helps if THIS script's first line runs before the
-- quest's adopt call. LocalScript start order in StarterPlayerScripts is arbitrary, so that is a
-- coin flip, and it has been losing it:
--
--     18:01:19.499  [Park]       loaded   <- adopts the console + wrench at top level
--     18:01:19.574  [HousePanel] ready    <- 75ms too late; both adoptions went nowhere
--
-- An un-adopted panel keeps its own authored geometry instead of the house card's, which is why the
-- same HUD looked right on one run and shoved out of place on the next -- nothing about the panel
-- changed, only which script happened to start first.
--
-- The fix does not depend on timing at all. Every call site also stamps WantsHousePanel on the
-- frame; the attribute lives on the INSTANCE, so this script can find it whenever it gets going --
-- before, during or long after the quest built it. The sweep below catches everything already in
-- PlayerGui, and the DescendantAdded watcher catches every panel built later (most mini-game HUDs
-- are built the moment you interact with the prop, minutes into the session).
_G.housePanel = adopt

local WANT_ATTR = "WantsHousePanel"
local function adoptIfWanted(inst)
	if typeof(inst) == "Instance" and inst:IsA("GuiObject")
		and inst:GetAttribute(WANT_ATTR) and not adopted[inst] then
		pcall(adopt, inst)
	end
end
for _, d in ipairs(PlayerGui:GetDescendants()) do
	adoptIfWanted(d)
end
PlayerGui.DescendantAdded:Connect(function(d)
	-- deferred: a quest sets the attribute the line AFTER parenting the frame, so reading it in the
	-- same frame the child appears would miss it.
	task.defer(adoptIfWanted, d)
end)
if #pendingAdoptions > 0 then
	print(("[HousePanel] draining %d panel(s) that adopted before this script was ready "
		.. "(they would previously have been dropped silently -- see the load-order note at the top)")
		:format(#pendingAdoptions))
	for _, panel in ipairs(pendingAdoptions) do
		pcall(adopt, panel)
	end
end
pendingAdoptions = {}

print(("[HousePanel] ready -- _G.housePanel(frame) HOLDS a task HUD at the house %dx%d task card (half the"
	.. " menus' 520 height), centres it"
	.. " in the free band between the top and bottom HUD (reserving %d / %d px) and shrinks it uniformly if"
	.. " that band is shorter than the card. Size/Position/AnchorPoint are RE-ASSERTED if anything writes"
	.. " them after adoption, so every quest HUD is the same size in the same spot; the offender is named"
	.. " in a warning. It also hides the bottom buttons while the HUD is up."
	.. " _G.hudHold(tag,bool) is the same hold on its own.")
	:format(PANEL_W, PANEL_H, TOP_RESERVE, BOTTOM_RESERVE))
