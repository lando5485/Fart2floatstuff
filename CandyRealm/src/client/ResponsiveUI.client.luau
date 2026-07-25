--[[
	ResponsiveUI.client.luau  (StarterPlayerScripts.ResponsiveUI)

	UNIVERSAL HUD SCALING — runs on EVERY device (desktop, laptop, tablet, phone).

	Adds ONE global UIScale to each HUD ScreenGui's children, sized from the live viewport against a
	design reference, so the authored layout fits every screen as a single unit (uniform scalar — squares
	stay square, circles stay circular, text scales with it). Nothing is repositioned or re-tuned per device.

	SHRINK-TO-FIT, NEVER GROW: the scale is clamped to a max of 1.0, so a normal/large desktop renders the HUD
	at its authored size (unchanged — desktop was always correct), and only SMALLER screens (small windows,
	split-screen, laptops, tablets, phones) scale DOWN to fit. This avoids ballooning the HUD on big monitors.

	  scale = clamp( min(viewport.X / REF_W, viewport.Y / REF_H), MIN_SCALE, 1.0 )

	REF = 1280×720: any screen at least this size stays at 1.0; smaller ones shrink proportionally. Recomputed
	on every viewport change (window resize, device rotation). Roblox's own control GUIs (touch joystick / jump)
	are never touched. Full-screen covers (shop dim backdrops) keep covering the screen — we recurse into them
	and scale the content inside instead. Opt out per element/ScreenGui with attribute NoResponsiveScale = true.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== TUNABLES =====
local REF_W, REF_H = 1280, 720   -- design reference; screens >= this render at 1.0 (authored), smaller shrink
local MIN_SCALE = 0.45           -- floor so the HUD never collapses to nothing on a tiny viewport
local MAX_SCALE = 1.0            -- never grow past authored size (desktop stays as-is; raise this to allow growth on 4K)
local FULLSCREEN_EPS = 0.95      -- Size.Scale >= this on BOTH axes => a full-screen cover (don't scale; recurse into it)

local SCALE_TAG = "ResponsiveScaleApplied" -- marks elements we've given a UIScale (idempotency guard)
local OPT_OUT = "NoResponsiveScale"        -- set true on any element/ScreenGui to skip it
local ROBLOX_GUIS = { TouchGui = true, ControlGui = true, RobloxGui = true } -- never touch Roblox's own control GUIs

-- ===== SCALE =====
local managed: { UIScale } = {} -- every UIScale we own, refreshed together on a viewport change

local function viewport(): Vector2
	local cam = Workspace.CurrentCamera
	return (cam and cam.ViewportSize) or Vector2.new(REF_W, REF_H)
end

local function currentScale(): number
	local vp = viewport()
	if vp.X <= 1 or vp.Y <= 1 then
		return MAX_SCALE -- viewport not valid yet (boot reports 1x1); a recompute corrects it once the camera settles
	end
	return math.clamp(math.min(vp.X / REF_W, vp.Y / REF_H), MIN_SCALE, MAX_SCALE)
end

local function isFullScreen(obj: Instance): boolean
	if not obj:IsA("GuiObject") then return false end
	local sz = obj.Size
	return sz.X.Scale >= FULLSCREEN_EPS and sz.Y.Scale >= FULLSCREEN_EPS
end

local function attachScale(obj: GuiObject, scale: number)
	if obj:GetAttribute(SCALE_TAG) or obj:GetAttribute(OPT_OUT) then return end
	if obj:FindFirstChildWhichIsA("UIScale") then return end -- respect a hand-authored UIScale (pop-in anims etc.)
	local us = Instance.new("UIScale")
	us.Scale = scale
	us.Parent = obj
	obj:SetAttribute(SCALE_TAG, true)
	table.insert(managed, us)
end

-- A non-full-screen element is scaled directly (its descendants follow via the UIScale). A full-screen cover keeps
-- covering the screen, so we recurse and scale the offset-sized content within (handles nested backdrops/panels).
local function applyResponsive(obj: Instance, scale: number)
	if not obj:IsA("GuiObject") or obj:GetAttribute(OPT_OUT) then return end
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
			us.Scale = s
		else
			table.remove(managed, i) -- prune UIScales whose element (e.g. a closed popup) was destroyed
		end
	end
end

-- ===== SCREENGUI DISCOVERY (current + future) =====
local processed = setmetatable({}, { __mode = "k" })

local function hookScreenGui(sg: Instance)
	if not sg:IsA("ScreenGui") or processed[sg] or sg:GetAttribute(OPT_OUT) then return end
	if ROBLOX_GUIS[sg.Name] then
		processed[sg] = true -- Roblox owns the movement joystick / jump button; leave them at default
		return
	end
	processed[sg] = true
	pcall(function() sg.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end) -- clear the notch/home-bar on phones; no-op on desktop
	for _, child in ipairs(sg:GetChildren()) do
		applyResponsive(child, currentScale())
	end
	-- Popups/banners add their root (often a full-screen backdrop) later; defer a step so the panel underneath exists.
	sg.ChildAdded:Connect(function(child)
		task.defer(function()
			applyResponsive(child, currentScale())
		end)
	end)
end

-- ===== VIEWPORT / RESIZE HOOKS =====
local lastW, lastH = -1, -1
local function recompute()
	refreshAll()
	local vp = viewport()
	local w, h = math.floor(vp.X), math.floor(vp.Y)
	if w ~= lastW or h ~= lastH then
		lastW, lastH = w, h
		print(("[ResponsiveUI] viewport=%dx%d → global HUD scale=%.3f"):format(w, h, currentScale()))
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

-- Connect BEFORE the initial sweep so a ScreenGui added mid-setup can't slip between the two.
PlayerGui.ChildAdded:Connect(function(sg)
	task.defer(function() hookScreenGui(sg) end)
end)
for _, sg in ipairs(PlayerGui:GetChildren()) do
	hookScreenGui(sg)
end

-- Settle passes: the camera reports 1x1 for a frame or two at boot, so re-apply once it's valid.
task.defer(refreshAll)
task.delay(0.3, recompute)
task.delay(1.0, recompute)

local touch = UserInputService.TouchEnabled
print(("[ResponsiveUI] universal scaling active on ALL devices (touch=%s) → shrink-to-fit, cap %.2f, ref %dx%d")
	:format(tostring(touch), MAX_SCALE, REF_W, REF_H))
