--[[
	PopupScale.luau  (ReplicatedStorage.PopupScale)

	Lets centered popup panels (Backpack store, Wormhole menu, Codes menu, Crate reveal) scale with the HUD on
	tablet / iPad using the EXACT SAME global scale every HUD element uses — no separate scale number.

	WHY THIS EXISTS: ResponsiveUI applies one global UIScale to each HUD element, but its generic pass SKIPS any
	element that already owns a UIScale (it won't stack a second one). These popups each keep their OWN UIScale for
	the open/pop animation, so ResponsiveUI never touches them and they stayed at authored size on big tablet
	screens. ResponsiveUI publishes its live computed+clamped scale onto the LocalPlayer as the attribute
	"ResponsiveScale" (refreshed on every viewport change). This helper reads that value so each popup can use it as
	the resting scale of its own animation UIScale.

	DESKTOP: ResponsiveUI returns early on desktop and NEVER sets the attribute → restScale() returns 1 → popups
	stay exactly as authored (desktop is unchanged). onChanged() likewise never fires on desktop.

	Client-only (uses Players.LocalPlayer).
]]

local Players = game:GetService("Players")

local PopupScale = {}

local SCALE_ATTR = "ResponsiveScale" -- set by ResponsiveUI on the LocalPlayer (phone/tablet branch only)

-- The current global HUD scale (same value/logic the HUD uses). 1 when not published (desktop / before the phone
-- branch's first publish) so the popup falls back to its authored size.
function PopupScale.restScale(): number
	local player = Players.LocalPlayer
	local s = player and player:GetAttribute(SCALE_ATTR)
	if type(s) == "number" and s > 0 then
		return s
	end
	return 1
end

-- Subscribe to global-scale changes (viewport resize / rotation on phone/tablet). Returns the connection so the
-- caller can disconnect (e.g. when a transient popup closes). On desktop the attribute never changes → never fires.
function PopupScale.onChanged(callback: () -> ()): RBXScriptConnection?
	local player = Players.LocalPlayer
	if not player then
		return nil
	end
	return player:GetAttributeChangedSignal(SCALE_ATTR):Connect(callback)
end

-- One-time confirmation (module runs once, on first require by any of the four popups).
print("[UIScale] popups now scale with HUD on tablet \u{2192} Backpack, Wormhole, Codes, Crate (reuse global scale).")

return PopupScale
