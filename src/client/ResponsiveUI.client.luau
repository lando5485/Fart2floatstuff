--[[
	ResponsiveUI.client.luau  (StarterPlayerScripts.ResponsiveUI)

	PHONE-ONLY responsive HUD layout. The PC/desktop/Studio layout is already correct and is left COMPLETELY
	UNTOUCHED: unless this script detects an ACTUAL phone, it does nothing at all — no UIScale, no inset changes —
	so Studio's default (non-emulated) preview and every desktop/laptop client render exactly as authored. Only a
	real phone (or the Studio device emulator set to a phone) gets the layout fitted to its screen.

	DETECTION — purely INPUT-CAPABILITY based (NOT pixel size). A handheld phone has touch and neither a mouse nor a
	physical keyboard:
	  PHONE   == TouchEnabled AND not KeyboardEnabled
	  DESKTOP == anything else (no touch — and a touchscreen laptop, which has a physical keyboard).
	  NOTE: we do NOT test MouseEnabled — real iPhones/iPads often report MouseEnabled=TRUE (Roblox exposes a
	  virtual mouse), so requiring "not MouseEnabled" wrongly sent actual phones to the DESKTOP branch (no scaling →
	  the oversize). MouseEnabled is still logged for diagnosis, just not part of the decision.
	We do NOT test viewport width: real high-res phones report large pixel viewports, so a width/size threshold
	wrongly routed them to the desktop branch (the bug this fixes). The Studio Device emulator for a phone reports
	touch-only (no mouse/keyboard), so it matches PHONE too — and so does an actual iPhone, regardless of its
	resolution. Desktop and Studio's non-emulated view keep mouse+keyboard, so they're never matched.

	PHONE LAYOUT — the SAME arrangement as desktop (left rail left, STATS right, coin pill + gear top-right, Daily
	Deals top-left, Planet pill + Race board top-centre, BUY FOOD FIRST! bottom-centre above the Astro Stomach bar),
	just made to fit every phone:
	  * A single GLOBAL UIScale (the SAME value on every managed HUD element) scales size + child Position offsets +
	    TextSize together about each element's OWN AnchorPoint. So every element keeps its corner/edge/centre anchor,
	    nothing distorts (uniform scalar — squares stay square, circles stay circular), and text scales to fit. The
	    scale is min(viewport.X/REF_W, viewport.Y/REF_H) against a phone REFERENCE resolution, clamped — so the EXACT
	    tuned phone layout is preserved and simply GROWS on bigger touch screens (tablet / iPad) and shrinks on
	    smaller ones, as ONE unit (no per-device re-tuning, no repositioning). See the TUNABLES block for the
	    reference + clamp. An iPad shows the identical phone layout, just larger and filling the screen.
	  * ScreenInsets = DeviceSafeInsets on each HUD ScreenGui keeps top elements clear of the notch / Dynamic Island
	    and bottom elements clear of the home-bar. Our bottom HUD is bottom-CENTRE, so it never reaches the
	    bottom-left joystick / bottom-right jump touch controls.

	Non-destructive: only ADDS UIScale instances and flips ScreenInsets on phones; never edits authored Size /
	Position / colour. Opt out per element/ScreenGui with attribute NoResponsiveScale = true.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== TUNABLES — GLOBAL UISCALE AUTO-SCALING =====
-- The whole HUD scales as ONE unit from a phone REFERENCE resolution, so the EXACT tuned phone layout (positions,
-- gaps, arrangement) is preserved and simply grows on bigger touch screens (tablet / iPad) and shrinks on smaller
-- ones — no per-device re-tuning, no element repositioning. The scale is the user-spec'd ratio:
--     ratio = clamp( min(viewport.X / REF_W, viewport.Y / REF_H), RATIO_MIN, deviceMax )   -- deviceMax is per-class
-- applied (clamped, directly — no compaction multiplier) as the single global UIScale to every managed HUD element.
--
-- REFERENCE: iPhone SE / 8 in LANDSCAPE (1334×750). This baseline iPhone is the design reference: its modest pixel
-- size means bigger devices (Plus/Pro iPhones, iPads) report a larger viewport and therefore scale UP from here,
-- while smaller screens scale DOWN — all keeping the identical layout. (Roblox reports phone viewports in PIXELS, so
-- the reference is in device pixels, not points.)
-- REF_H is the iPhone 16's LANDSCAPE short-axis as Roblox reports it (≈590 px); REF_W is set BELOW the iPhone's long
-- axis so phones bind on HEIGHT (ratio ≈ 1.0) while larger / taller screens (tablets, desktop) bind higher and scale
-- UP, smaller screens scale DOWN. The FINAL applied scale IS this computed ratio (clamped) — see below.
local REF_W, REF_H = 1100, 590
-- NO compaction multiplier. The previous DESIGN_SCALE = 0.6 (an old MAX_SCALE-0.6-era constant) was multiplying the
-- computed ratio DOWN to ~0.644 — that is REMOVED. The FINAL global UIScale = the COMPUTED ratio itself, clamped to
-- the clamp below, so UIDiag's "FINAL applied UIScale.Scale" equals the computedScale (e.g. 1.073) on a tablet.
-- Clamp the FINAL scale. The MAX is PER-DEVICE-CLASS so the PHONE can be capped lower (to clear the bottom-left
-- joystick + bottom-right jump) WITHOUT shrinking tablets: phone-class viewports cap at PHONE_MAX (~0.60), while
-- tablet / larger viewports keep their higher computed scale (cap at TABLET_MAX, effectively uncapped). Classified by
-- viewport SHORT-axis (min dimension) — the SAME >=800 ⇒ tablet split UIDiag uses for its branch label. MIN floors it.
local RATIO_MIN = 0.55
local PHONE_MAX = 0.60         -- phone-class cap → iPhone's ~0.666 clamps down to ~0.60, clearing the controls
local TABLET_MAX = 2.5         -- tablet / larger: keep the (higher) computed scale, NEVER capped down to the phone value
local TABLET_SHORT_AXIS = 800  -- viewport short-axis (min(X,Y)) >= this ⇒ tablet-class (so the tablet's 1.073 is kept)
local FULLSCREEN_EPS = 0.95               -- Size.Scale >= this on BOTH axes => a full-screen cover (don't scale; recurse)

local SCALE_TAG = "ResponsiveScaleApplied" -- marks elements we've given a UIScale (idempotency guard)
local OPT_OUT = "NoResponsiveScale"        -- set true on any element/ScreenGui to skip it
local EXTRA_SHRINK = "ResponsiveExtraShrink" -- per-element multiplier ON TOP of the scale (e.g. shrink the left rail extra)

-- ===== PHONE DETECTION (capability-based; NO pixel-size test) =====
-- A handheld phone has TOUCH and NO physical KEYBOARD. We intentionally do NOT require MouseEnabled==false: real
-- iPhones/iPads frequently report MouseEnabled=TRUE (Roblox exposes a virtual mouse), and the old "and not
-- MouseEnabled" therefore sent actual phones to the DESKTOP branch — so NONE of the phone scaling ran on the
-- device and it stayed oversized ("recent prompts changed nothing"). Touch + no-keyboard is the robust check;
-- desktop has no touch, a touchscreen laptop has a physical keyboard, so both correctly resolve to DESKTOP.
local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- ===== SCALE =====
-- Every UIScale we manage, so a viewport resize (rotation / window change) updates them all together.
local managed: { UIScale } = {}

-- The user-spec'd global ratio: min of the two axis ratios (fit the MORE constrained axis), clamped. Magnitude-only;
-- a consistent fraction of the screen vs the reference, so bigger viewports yield a bigger ratio (HUD grows).
-- PER-DEVICE-CLASS cap: phone-class viewports cap at PHONE_MAX (clears the controls); tablet / larger keep TABLET_MAX
-- (their higher computed scale), so a low phone cap never shrinks the tablet.
local function deviceMax(vp: Vector2): number
	return (math.min(vp.X, vp.Y) >= TABLET_SHORT_AXIS) and TABLET_MAX or PHONE_MAX
end

local function globalRatio(vp: Vector2): number
	return math.clamp(math.min(vp.X / REF_W, vp.Y / REF_H), RATIO_MIN, deviceMax(vp))
end

-- The single GLOBAL scale applied to every managed HUD element (so the whole HUD grows/shrinks as one unit). It IS
-- the computed viewport ratio, clamped — no compaction multiplier (DESIGN_SCALE was removed).
local function currentScale(): number
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(REF_W, REF_H)
	if vp.X <= 1 or vp.Y <= 1 then
		return PHONE_MAX -- viewport not valid yet (boot reports 1x1) → safe small default; a recompute fixes it
	end
	-- FINAL = the COMPUTED ratio, CLAMPED (per-device max), applied directly. No DESIGN_SCALE/0.6 compaction → UIDiag's
	-- "FINAL applied UIScale.Scale" equals the computedScale within [RATIO_MIN, deviceMax].
	return globalRatio(vp)
end

-- Full scale breakdown for tuning from the F9 console on any device: the RAW computed ratio, the clamp window, and
-- the FINAL applied UIScale (= the clamped ratio itself).
local function logScale()
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(REF_W, REF_H)
	local raw = (vp.X > 1 and vp.Y > 1) and math.min(vp.X / REF_W, vp.Y / REF_H) or 1.0
	local maxUsed = deviceMax(vp)
	local final = math.clamp(raw, RATIO_MIN, maxUsed)
	print(("[UIScale] calib → ref=%dx%d, viewport=%dx%d, computed=%.3f, clampMax=%.2f, final=%.3f"):format(
		REF_W, REF_H, math.floor(vp.X), math.floor(vp.Y), raw, maxUsed, final))
end

local function isFullScreen(obj: Instance): boolean
	if not obj:IsA("GuiObject") then
		return false
	end
	local sz = obj.Size
	return sz.X.Scale >= FULLSCREEN_EPS and sz.Y.Scale >= FULLSCREEN_EPS
end

local function attachScale(obj: GuiObject, scale: number)
	if obj:GetAttribute(SCALE_TAG) or obj:GetAttribute(OPT_OUT) then
		return
	end
	-- Respect a hand-authored UIScale (animation pop-ins etc.) — never stack a second one that would fight it.
	if obj:FindFirstChildWhichIsA("UIScale") then
		return
	end
	local us = Instance.new("UIScale")
	us.Scale = scale * (obj:GetAttribute(EXTRA_SHRINK) or 1)
	us.Parent = obj
	obj:SetAttribute(SCALE_TAG, true)
	table.insert(managed, us)
end

-- Apply responsive scaling to a subtree root. A non-full-screen element is scaled directly (and its descendants
-- come along via the UIScale). A full-screen cover keeps covering the screen, so we recurse into its children and
-- scale the meaningful offset-sized content within (handles arbitrarily nested backdrops/stages).
local function applyResponsive(obj: Instance, scale: number)
	if not obj:IsA("GuiObject") or obj:GetAttribute(OPT_OUT) then
		return
	end
	if isFullScreen(obj) then
		for _, child in ipairs(obj:GetChildren()) do
			applyResponsive(child, scale)
		end
	else
		attachScale(obj, scale)
	end
end

local function refreshAll()
	local s = currentScale()
	for i = #managed, 1, -1 do
		local us = managed[i]
		if us.Parent then
			us.Scale = s * (us.Parent:GetAttribute(EXTRA_SHRINK) or 1)
		else
			table.remove(managed, i) -- prune UIScales whose element (e.g. a closed popup) was destroyed
		end
	end
end

-- ===== SAFE AREA (phones only) =====
-- Map each HUD ScreenGui's coordinate space to the DEVICE SAFE AREA so edge elements clear the notch / Dynamic
-- Island (top) and the home-bar (bottom). pcall-guarded in case ScreenInsets is unavailable on an old client.
local function applySafeInsets(sg: ScreenGui)
	pcall(function()
		sg.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
end

-- ===== EXECUTION GATE =====
-- Decide PHONE vs DESKTOP purely from INPUT capabilities. On DESKTOP we touch NOTHING — the authored layout is
-- left exactly as-is.
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local touch = UserInputService.TouchEnabled
local mouse = UserInputService.MouseEnabled
local keyboard = UserInputService.KeyboardEnabled
local phone = isPhone()

local function viewport(): Vector2
	return (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(0, 0)
end

if not phone then
	local vp = viewport()
	print(("[UIScale] layout decision — branch=DESKTOP, TouchEnabled=%s, Mouse=%s, Keyboard=%s, viewport=%dx%d")
		:format(tostring(touch), tostring(mouse), tostring(keyboard), math.floor(vp.X), math.floor(vp.Y)))
	return -- DESKTOP / laptop / Studio non-emulated → leave the HUD layout exactly as authored
end

-- PHONE: do NOT size against ViewportSize until it is VALID. At boot the camera reports 1x1 (or 0x0) for a frame
-- or two; computing scale then makes every ratio ~0 → clamped to the MIN floor → the whole HUD collapses (the
-- too-small / cramped / overlapping-the-player bug). Yield until the viewport reads > 1x1, with a short timeout so
-- a stuck viewport can never hang the script — the ViewportSize listener below still corrects it afterwards.
local function viewportValid(): boolean
	local vp = viewport()
	return vp.X > 1 and vp.Y > 1
end
do
	local waited = 0
	while not viewportValid() and waited < 3 do
		waited += RunService.RenderStepped:Wait()
	end
end

local vpUsed = viewport()
print(("[UIScale] layout decision — branch=PHONE, TouchEnabled=%s, Mouse=%s, Keyboard=%s, viewport=%dx%d")
	:format(tostring(touch), tostring(mouse), tostring(keyboard), math.floor(vpUsed.X), math.floor(vpUsed.Y)))

-- Publish the reference + live global scale onto the player so UIDiag (and any tool) can read/log them; refreshed by
-- recompute() on every viewport / safe-area change.
local function publishScale()
	local vp = viewport()
	player:SetAttribute("ResponsiveRefW", REF_W)
	player:SetAttribute("ResponsiveRefH", REF_H)
	player:SetAttribute("ResponsiveScale", currentScale())
	player:SetAttribute("ResponsiveViewportW", math.floor(vp.X))
	player:SetAttribute("ResponsiveViewportH", math.floor(vp.Y))
	-- Diagnostic extras: ONLY set on the phone/scaling branch (publishScale never runs on DESKTOP), so their ABSENCE
	-- in UIDiag means the device fell to the desktop branch and the global UIScale was never computed/applied.
	player:SetAttribute("ResponsiveClampMin", RATIO_MIN)
	player:SetAttribute("ResponsiveClampMax", deviceMax(vp)) -- the PER-DEVICE cap actually applied (PHONE_MAX vs TABLET_MAX)
	player:SetAttribute("ResponsiveComputedRatio", (vp.X > 1 and vp.Y > 1) and math.min(vp.X / REF_W, vp.Y / REF_H) or 1.0)
	player:SetAttribute("ResponsiveBranchRan", true)
end
publishScale()
logScale()
print("[UIScale] scale recalibrated → iPhone restored to previous size, larger screens scale up.")
print("[UIScale] applied scale now uses computed value (FINAL = computedScale, clamped) — no fixed 0.644 override.")
print("[UIScale] phone scale capped lower (~0.60) to clear controls; tablet scale unchanged.")
print("[Mobile] Roblox movement joystick + jump button restored to default position (HUD no longer displacing them).")

-- ===== SCREENGUI DISCOVERY (current + future) — PHONE PATH =====
local processed = setmetatable({}, { __mode = "k" }) -- ScreenGuis already wired (weak so they're collectable)

-- Roblox-PROVIDED GUIs we must NEVER touch — above all the mobile movement controls (TouchGui → TouchControlFrame →
-- DynamicThumbstick + JumpButton). Roblox owns their position/size; if we add a UIScale or flip ScreenInsets on them,
-- the bottom-left joystick (and bottom-right jump) gets scaled / shoved out of place. Only the game's OWN HUD scales.
local ROBLOX_GUIS = { TouchGui = true, ControlGui = true, RobloxGui = true }

local function hookScreenGui(sg: Instance)
	if not sg:IsA("ScreenGui") or processed[sg] or sg:GetAttribute(OPT_OUT) then
		return
	end
	if ROBLOX_GUIS[sg.Name] then
		processed[sg] = true -- remember it, but do NOTHING to it: no UIScale, no ScreenInsets — Roblox keeps the controls at default
		print(("[Mobile] left Roblox control GUI '%s' untouched (movement joystick + jump stay at default position/size)"):format(sg.Name))
		return
	end
	processed[sg] = true

	applySafeInsets(sg)
	for _, child in ipairs(sg:GetChildren()) do
		applyResponsive(child, currentScale())
	end
	-- Popups/banners/reveals add their root (often a full-screen backdrop) later; defer one step so the panel it
	-- builds synchronously underneath exists before we scan it. attachScale is idempotent, so re-scans are safe.
	sg.ChildAdded:Connect(function(child)
		task.defer(function()
			applyResponsive(child, currentScale())
		end)
	end)
end

-- Re-run the sizing pass against the CURRENT (valid) viewport whenever it changes — emulator resize, device
-- rotation, or a real-device settle after boot — and log the new size so a real-phone recompute is diagnosable.
local resizeFartButton -- assigned by the tap-to-fart compact-resize handler (task.spawn near the end of this file)
local repositionDeals  -- assigned by the Daily-Deals-under-STATS handler (its Y depends on the STATS scaled height)
local repositionCoin   -- assigned by the coin-pill handler; docks the coin a couple px left of the settings gear
local clampSafeArea    -- assigned by the safe-area handler; pulls edge-anchored elements back inside the device safe area
local lastLoggedW, lastLoggedH = -1, -1
local function recompute()
	refreshAll()
	if resizeFartButton then
		resizeFartButton() -- keep the extra-compact TAP TO FART pill in sync with the new viewport too
	end
	if repositionDeals then
		repositionDeals() -- keep Daily Deals docked just under the (scaled) STATS panel
	end
	if repositionCoin then
		repositionCoin() -- keep the coin pill a couple px left of the (scaled) settings gear
	end
	if clampSafeArea then
		clampSafeArea() -- after a rotation / inset change, re-pull edge elements inside the (new) safe area
	end
	publishScale() -- refresh the published global scale (viewport / safe-area changed)
	local vp = viewport()
	local w, h = math.floor(vp.X), math.floor(vp.Y)
	if w ~= lastLoggedW or h ~= lastLoggedH then -- only log when the size actually changed (avoid spam)
		lastLoggedW, lastLoggedH = w, h
		logScale()
	end
end

local function hookCamera()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(recompute)
	end
end
hookCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	hookCamera()
	recompute()
end)
-- Safe-area / topbar inset changes (e.g. rotation, notch side switching) — guarded in case the property is
-- unavailable on an older client. ScreenInsets=DeviceSafeInsets re-insets automatically; this just re-syncs scale.
pcall(function()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(recompute)
end)

-- Connect BEFORE the initial sweep so a ScreenGui added mid-setup can't slip between the two.
PlayerGui.ChildAdded:Connect(function(sg)
	task.defer(function()
		hookScreenGui(sg)
	end)
end)
for _, sg in ipairs(PlayerGui:GetChildren()) do
	hookScreenGui(sg)
end

-- Belt-and-suspenders settle passes in case a ViewportSize change never fires after the wait.
task.defer(refreshAll)
task.delay(0.3, refreshAll)

-- ===== HIDE the Planet Race board on phones =====
-- The top-centre PLANET RACE leaderboard ("RaceBoard" ScreenGui) is hidden on phones; the transient banners
-- (server events / cosmic race / planet arrival) take its spot instead (see PhoneHUD + the banner scripts). A
-- guard re-disables it if anything flips it back on. Desktop never reaches here, so the board shows there as usual.
task.spawn(function()
	local rb = PlayerGui:FindFirstChild("RaceBoard") or PlayerGui:WaitForChild("RaceBoard", 20)
	if rb and rb:IsA("ScreenGui") then
		rb.Enabled = false
		rb:GetPropertyChangedSignal("Enabled"):Connect(function()
			if rb.Enabled then
				rb.Enabled = false
			end
		end)
		print("[UIScale] PHONE Planet Race board hidden")
	end
end)

-- ===== BOTTOM-CENTRE CLUSTER (phones): compact pill + clean glow + clear gap above the Astro Stomach bar =====
-- Two phone-only fixes handled together because they share the bottom-centre geometry:
--  (1) SPACING — the gas meter (Astro Stomach bar) is lifted a little off the bottom edge, and the TAP TO FART pill
--      is placed a clear GAP ABOVE the meter's (scaled) top. Repositioning only; no size changes.
--  (2) BORDER/GLOW — the pill keeps its OWN UIScale (fartScale, for the press pulse), so the generic pass skips the
--      pill and resizes it directly; its separate glow frame had been left at the generic scale, so it ballooned
--      into a blocky rectangle behind the small pill. We now scale + recentre that glow to the SAME factor as the
--      pill and make it a capsule, so it's a smooth rounded halo hugging the pill (like the stomach bar's border).
-- (FART_BUTTON_SHRINK removed — the pill now uses the SAME global scale as every other element, no extra shrink.)
local PHONE_METER_BOTTOM_GAP = 16 -- px between the gas meter's bottom and the (safe-area) screen bottom; lifts the WHOLE bottom cluster (pill + meter) UP a little (pill is derived off the meter top, so their gap is preserved)
local PILL_GAP_BASE = 10         -- TIGHT gap (× scale) between the pill's bottom and the gas meter's top

task.spawn(function()
	local function findGui(name)
		for _, d in ipairs(PlayerGui:GetDescendants()) do
			if d.Name == name and d:IsA("GuiObject") then
				return d
			end
		end
		return nil
	end

	-- Wait for the pill (FlightClient ScreenGui); the meter (SpaceRealmHUD) is normally up by then.
	local btn, waited = nil, 0
	while not btn and waited < 15 do
		btn = findGui("FartButton")
		if btn then break end
		waited += task.wait(0.2)
	end
	if not btn then
		warn("[UIScale] PHONE: FartButton not found within 15s — bottom-cluster fix skipped.")
		return
	end
	local glow = findGui("FartButtonGlow")
	local meter = findGui("GasMeter")
	local meterGlow = findGui("GasMeterGlow")

	-- Capture AUTHORED geometry ONCE so every recompute scales from the originals, never from an already-edited value.
	local baseW, baseH = btn.Size.X.Offset, btn.Size.Y.Offset
	local baseBtnY = btn.Position.Y.Offset
	local pads = {}
	for _, lbl in ipairs(btn:GetChildren()) do
		if lbl:IsA("GuiObject") then
			local pad = lbl:FindFirstChildOfClass("UIPadding")
			if pad then
				table.insert(pads, { pad = pad, t = pad.PaddingTop.Offset, b = pad.PaddingBottom.Offset, l = pad.PaddingLeft.Offset, r = pad.PaddingRight.Offset })
			end
		end
	end
	btn:SetAttribute(OPT_OUT, true) -- generic pass already skips it (fartScale); be explicit
	local fartScale = btn:FindFirstChildWhichIsA("UIScale") -- the pill's press-pulse UIScale; we now DRIVE it to the global scale (no direct sizing)

	local baseGlowW, baseGlowH, glowCorner
	if glow then
		-- PHONE: remove the oversized faint blue halo behind the pill ENTIRELY. The pill keeps its own border/glow.
		glow.Visible = false
		print("[HUD] PHONE removed faint blue halo behind tap-to-fart pill")
		glow = nil -- ignored everywhere below — apply() no longer sizes/repositions it
	end

	local baseMeterH = meter and meter.Size.Y.Offset or 64
	local baseMeterY = meter and meter.Position.Y.Offset or -20
	local baseMeterGlowY = meterGlow and meterGlow.Position.Y.Offset or -12

	local logged, lastCs = false, -1
	local function apply()
		local cs = currentScale()

		-- (1) drop the meter (+ its glow) DOWN so it sits only a couple px off the bottom edge.
		if meter then meter.Position = UDim2.new(0.5, 0, 1, -PHONE_METER_BOTTOM_GAP) end
		if meterGlow then meterGlow.Position = UDim2.new(0.5, 0, 1, -PHONE_METER_BOTTOM_GAP + (baseMeterGlowY - baseMeterY)) end

		-- meter TOP (px up from the bottom) = its bottom gap + its generic-scaled height.
		local meterBottomUp = meter and PHONE_METER_BOTTOM_GAP or (-baseBtnY)
		local meterTopUp = meterBottomUp + baseMeterH * cs

		-- pill: a clear GAP above the meter top. UNIFIED SCALE — the pill is no longer direct-sized / extra-shrunk; we
		-- drive its OWN fartScale UIScale to the SAME global scale as every other element (so UIDiag reads cs on it
		-- too). Size stays AUTHORED; the UIScale scales size + paddings + the TextScaled caption together about its
		-- bottom-centre anchor, so the placement (bottom at buttonBottomUp) is unchanged.
		local gap = math.floor(PILL_GAP_BASE * cs + 0.5)
		local buttonBottomUp = meter and (meterTopUp + gap) or (-baseBtnY)
		if fartScale then
			fartScale.Scale = cs
		end
		btn:SetAttribute("FartRestScale", cs) -- FlightClient's press pulse rests here (relative) so it won't snap back to 1.0
		btn.Position = UDim2.new(0.5, 0, 1, -math.floor(buttonBottomUp + 0.5))

		if cs ~= lastCs then
			lastCs = cs
			print(("[UIScale] PHONE tap-to-fart pill scaled to global scale → %.3f"):format(cs))
		end
		if not logged then
			logged = true
			print("[UIScale] PHONE bottom-center spacing fixed → pill/stomach gap added")
		end
	end

	resizeFartButton = apply -- recompute() re-runs this on every viewport / safe-area change
	apply()

	-- ===== Static (scale-independent) position tweaks — run ONCE (these are DELTAS, so must not re-run) =====
	-- Top-right cluster (STATS + coin + gear) hugs the right edge; Daily Deals drops below the Roblox topbar. Each
	-- shift also moves the element's addPanelDepth Glow/Shadow siblings so they stay aligned with their panel.
	if not findGui("StatsPanel") then task.wait(1) end -- ensure the HUD panels have finished building
	-- Right cluster sits a SMALL MARGIN INSIDE the safe-area right edge (the ScreenGui's ScreenInsets=DeviceSafeInsets
	-- already maps offset 0 to the safe edge, so a negative offset is inside it). NOT flush — a flush/past-edge value
	-- is what clipped STATS on iPhone. The runtime clampSafeArea() pass below guarantees this on any device/orientation.
	local RIGHT_SHIFT = 8         -- STATS/coin/gear: authored -16 → -8 → right edge ~8px inside the safe-area edge
	local TOP_RIGHT_DOWN = 0      -- vertical position stays at original (top) — only the horizontal shift remains
	local function shiftCluster(baseName, dx, dy)
		for _, n in ipairs({ baseName, baseName .. "Glow", baseName .. "Shadow" }) do
			local e = findGui(n)
			if e then
				e.Position = e.Position + UDim2.new(0, dx, 0, dy)
			end
		end
	end
	shiftCluster("StatsPanel", RIGHT_SHIFT, TOP_RIGHT_DOWN) -- Daily Deals follows: its X is derived from STATS below
	shiftCluster("CoinCounter", RIGHT_SHIFT, TOP_RIGHT_DOWN)
	shiftCluster("Settings", RIGHT_SHIFT, TOP_RIGHT_DOWN) -- the gear: keeps its alignment with the coin spacing intact
	print("[UIScale] PHONE positions tuned → bottom cluster up slightly, right cluster set inside safe-area edge")

	-- PHONE-CLASS ONLY (NOT tablet/iPad — short-axis < TABLET_SHORT_AXIS): two POSITION fixes the iPad doesn't need.
	-- No size/scale changes. One-time deltas (so a recompute can't double-apply them).
	local function isPhoneClass(): boolean
		local vp = viewport()
		return math.min(vp.X, vp.Y) < TABLET_SHORT_AXIS
	end
	if isPhoneClass() then
		-- (1) LEFT RAIL must clear the bottom-left movement joystick: raise the whole rail a little AND tighten the gap
		-- between its buttons so the bottom button (MORE) packs higher and leaves a gap above the joystick. Button
		-- SIZES are untouched (only the rail's Position and the UIListLayout Padding change).
		local RAIL_UP = 30      -- px the rail moves UP
		local RAIL_PADDING = 6  -- tighter inter-button gap (was 12)
		local sidebar = findGui("Sidebar")
		if sidebar then
			sidebar.Position = sidebar.Position - UDim2.fromOffset(0, RAIL_UP)
			local lst = sidebar:FindFirstChildWhichIsA("UIListLayout")
			if lst then
				lst.Padding = UDim.new(0, RAIL_PADDING)
			end
			print("[UIScale] PHONE left rail raised/tightened to clear movement joystick.")
		end

		-- (2) Move the right-side STATS panel UP (Daily Deals stacked under it follows via repositionDeals, which reads
		-- STATS's Position.Y below). ONLY STATS (not the coin pill / gear above it). 22px keeps a small gap below the
		-- coin/gear (their scaled bottom is ~y42 at the phone cap; STATS top moves 70 → 48).
		local STATS_UP = 22
		shiftCluster("StatsPanel", 0, -STATS_UP) -- carries StatsPanelGlow/Shadow too
		print("[UIScale] PHONE right-side STATS/Daily Deals moved up.")
	end

	-- UNIFIED SCALE: the left rail (Sidebar) and the right cluster (STATS / coin / gear / Daily Deals) NO LONGER get a
	-- per-element ResponsiveExtraShrink — every element now renders at the SAME single global scale (currentScale), so
	-- the HUD is uniform. (The ResponsiveExtraShrink mechanism stays in attachScale/refreshAll but is now unused → ×1.)
	print("[UIScale] all HUD elements unified to single global scale (no per-element overrides).")

	-- (2) Daily Deals: keep it docked UNDER STATS — right-aligned + WIDTH-MATCHED to
	-- the (now smaller) STATS panel. Its addPanelDepth glow/shadow were placed for the old top-left spot, so hide
	-- them. The dock Y is derived from STATS's LIVE rendered scale (its UIScale, which now includes the extra
	-- shrink), so recompute() re-runs applyDeals on every viewport change.
	local deals = findGui("DealsWeekPill")
	local statsForDeals = findGui("StatsPanel")
	for _, n in ipairs({ "DealsWeekPillGlow", "DealsWeekPillShadow" }) do
		local e = findGui(n)
		if e then
			e.Visible = false
		end
	end
	if deals and statsForDeals then
		-- deals gets the SAME base global scale as STATS (no extra shrink) → equal render scale → widths still match
		deals.AnchorPoint = Vector2.new(1, 0) -- top-right, matching STATS, so they share the right edge + width
		local baseDealsH = deals.Size.Y.Offset
		local DEALS_GAP = 3
		repositionDeals = function()
			local us = statsForDeals:FindFirstChildWhichIsA("UIScale")
			local ss = (us and us.Scale) or currentScale() -- STATS's live rendered scale (incl. the extra shrink)
			deals.Position = UDim2.new(1, statsForDeals.Position.X.Offset, 0,
				statsForDeals.Position.Y.Offset + math.floor(statsForDeals.Size.Y.Offset * ss + 0.5) + DEALS_GAP)
			deals.Size = UDim2.new(0, statsForDeals.Size.X.Offset, 0, baseDealsH) -- match STATS width, keep own height
		end
		print("[UIScale] PHONE Daily Deals moved under STATS + width matched")
	end

	-- COIN pill → docked a couple px LEFT of the settings gear (no touch/overlap). Computed from the gear's offset +
	-- its LIVE UIScale (so the gap stays a constant couple px at any scale); recompute() re-runs it on viewport change.
	-- It SETS the coin's right edge (anchor 1,0) and carries its Glow/Shadow siblings by the same delta.
	local coin = findGui("CoinCounter")
	local gear = findGui("Settings")
	local gearBaseW = (gear and gear.Size.X.Offset) or 44
	local COIN_GEAR_GAP = 3
	if coin and gear then
		repositionCoin = function()
			local us = gear:FindFirstChildWhichIsA("UIScale")
			local gearScale = (us and us.Scale) or currentScale()
			local gearLeftXo = gear.Position.X.Offset - math.floor(gearBaseW * gearScale + 0.5) -- gear's left edge offset
			local targetXo = gearLeftXo - COIN_GEAR_GAP -- coin's right edge sits a couple px left of the gear's left edge
			local delta = targetXo - coin.Position.X.Offset
			if delta ~= 0 then
				for _, n in ipairs({ "CoinCounter", "CoinCounterGlow", "CoinCounterShadow" }) do
					local e = findGui(n)
					if e then
						e.Position = e.Position + UDim2.fromOffset(delta, 0)
					end
				end
			end
		end
		print("[UIScale] PHONE coin pill moved right, couple-pixel gap from settings gear")
	end

	refreshAll() -- apply EVERY extra-shrink attribute (rail + STATS/coin/gear/deals) to their UIScales
	if repositionDeals then
		repositionDeals() -- now STATS's UIScale reflects the shrink → Daily Deals docks under the smaller panel
	end
	if repositionCoin then
		repositionCoin() -- dock the coin a couple px left of the gear (gear UIScale is now applied)
	end
	print("[UIScale] PHONE STATS/Daily Deals/gear/coin size increased a bit")

	-- ===== SAFE-AREA CLAMP (iPhone) — keep edge-anchored HUD elements fully ON-SCREEN inside the device safe area =====
	-- A full-bleed Frame inside a DeviceSafeInsets ScreenGui: its AbsolutePosition/Size ARE the device safe rect in
	-- screen pixels (notch / Dynamic Island / home indicator / rounded corners all excluded). CRITICAL: the probe must
	-- share the HUD's frame of reference. The HUD ScreenGuis use IgnoreGuiInset=true, so the probe does too — and we
	-- do NOT also subtract GuiService:GetGuiInset() here (that double-counted the topbar and pushed the top elements
	-- DOWN). GetGuiInset is only a fallback below. The clamp then leaves SAFE_MARGIN so nothing sits flush.
	local SAFE_MARGIN = 8
	local probeGui = Instance.new("ScreenGui")
	probeGui.Name = "SafeAreaProbe"
	probeGui.ResetOnSpawn = false
	probeGui.IgnoreGuiInset = true -- MATCH the HUD ScreenGuis (IgnoreGuiInset=true); a mismatch pushed top elements down
	probeGui.DisplayOrder = -1000
	probeGui:SetAttribute(OPT_OUT, true) -- never scaled/clamped itself
	pcall(function()
		probeGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	probeGui.Parent = PlayerGui
	local probe = Instance.new("Frame")
	probe.Name = "SafeRect"
	probe.BackgroundTransparency = 1
	probe.Size = UDim2.new(1, 0, 1, 0)
	probe.Position = UDim2.new(0, 0, 0, 0)
	probe.Parent = probeGui

	-- True on-screen safe rectangle in screen pixels → left, top, right, bottom. Taken straight from the PROBE (same
	-- IgnoreGuiInset=true + DeviceSafeInsets basis as the HUD), so the clamp never fights the HUD's own coordinate
	-- origin or shoves the top cluster down below the topbar.
	local function safeRect()
		local sp, ss = probe.AbsolutePosition, probe.AbsoluteSize
		if ss.X > 1 and ss.Y > 1 then
			return sp.X, sp.Y, sp.X + ss.X, sp.Y + ss.Y
		end
		-- Fallback only (ScreenInsets unavailable / probe not yet settled): viewport minus the Roblox topbar inset.
		local vp = viewport()
		local insetTL, insetBR = GuiService:GetGuiInset()
		return insetTL.X, insetTL.Y, vp.X - insetBR.X, vp.Y - insetBR.Y
	end

	-- How far `el` pokes past the safe rect (with margin); returns the inward correction in px (0 if already inside).
	local function safeDelta(el)
		local left, top, right, bottom = safeRect()
		if (right - left) <= 1 or (bottom - top) <= 1 then
			return 0, 0
		end
		local ep, es = el.AbsolutePosition, el.AbsoluteSize
		local dx, dy = 0, 0
		if ep.X < left + SAFE_MARGIN then
			dx = (left + SAFE_MARGIN) - ep.X
		elseif ep.X + es.X > right - SAFE_MARGIN then
			dx = (right - SAFE_MARGIN) - (ep.X + es.X)
		end
		if ep.Y < top + SAFE_MARGIN then
			dy = (top + SAFE_MARGIN) - ep.Y
		elseif ep.Y + es.Y > bottom - SAFE_MARGIN then
			dy = (bottom - SAFE_MARGIN) - (ep.Y + es.Y)
		end
		return math.floor(dx + 0.5), math.floor(dy + 0.5)
	end

	-- Move an element AND its addPanelDepth Glow/Shadow siblings by the same delta, so the depth stays aligned.
	local function nudgeWithDepth(baseName, dx, dy)
		for _, n in ipairs({ baseName, baseName .. "Glow", baseName .. "Shadow" }) do
			local e = findGui(n)
			if e then
				e.Position = e.Position + UDim2.fromOffset(dx, dy)
			end
		end
	end

	-- The edge-anchored, clip-prone elements. (Daily Deals and the coin pill aren't listed — they're re-derived from
	-- the clamped STATS / gear by repositionDeals / repositionCoin. The bottom cluster is centred + bottom-anchored
	-- within the safe-inset space, so it can't clip.)
	local CLAMP_TARGETS = { "StatsPanel", "Settings", "Sidebar" }
	local safeLogged = false
	clampSafeArea = function()
		task.spawn(function()
			RunService.RenderStepped:Wait() -- AbsolutePosition/Size only settle a frame AFTER a rescale/reposition
			for _, name in ipairs(CLAMP_TARGETS) do
				local el = findGui(name)
				if el then
					local dx, dy = safeDelta(el)
					if dx ~= 0 or dy ~= 0 then
						nudgeWithDepth(name, dx, dy)
					end
				end
			end
			if repositionDeals then
				repositionDeals() -- Daily Deals re-docks under STATS after STATS may have been clamped
			end
			if repositionCoin then
				repositionCoin() -- coin re-docks left of the gear after the gear may have been clamped
			end
			if not safeLogged then
				safeLogged = true
				print("[UIScale] PHONE safe-area insets applied → edge elements kept on-screen (iPhone).")
			end
		end)
	end
	clampSafeArea() -- initial pass once the layout above has been built + scaled
	print("[UIScale] PHONE STATS/Daily Deals/gear vertical position restored (back up)")
end)

print("[UIScale] PHONE branch — reference compact layout applied (scaled to fit + device safe-area insets).")
print("[UIScale] PHONE element sizes restored to compact reference + tap-to-fart shrunk")
