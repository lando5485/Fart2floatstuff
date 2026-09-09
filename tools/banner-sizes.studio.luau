-- ============================================================================================
-- banner-sizes.studio.luau -- print the exact geometry of every top-centre banner
-- ============================================================================================
-- WHY: the Space Realm has the same banners at the wrong size. Porting needs the AUTHORED
-- numbers (Size/Position/AnchorPoint/corner) AND the UIScale the HUD multiplies them by, since
-- AbsoluteSize alone is meaningless on a different screen.
--
-- HOW TO RUN. This reads PlayerGui, so it MUST run on the CLIENT:
--   1. Press Play (F5).
--   2. In the Command Bar, set the context dropdown to  Client  (next to the input box).
--   3. Paste this whole file in and press Enter.
--   4. Land on an island / trigger a banner first if you want the live values of one that is
--      only built on demand -- anything not yet created prints as "(not built yet)".
-- ============================================================================================
local P = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local cam = workspace.CurrentCamera

-- Every ScreenGui that owns a top-centre banner, in stacking order (TopCenterStack's ORDER),
-- then the ones that live in the same column but are not part of that stack.
local NAMES = {
	"NotifyHero", "ServerEventGui", "EventBannerGui", "ArrivalGui", "AnnounceGui",
	"EventCountGui", "PetQuestUI", "HudNoticeGui",
}

-- The UIScale chain. CoreClient's applyScaling puts a UIScale on the HUD groups, so a 500px
-- banner is NOT 500px on a phone -- and that factor is the whole reason a straight copy of the
-- numbers looks wrong in another realm.
local function scaleOf(o)
	local s, n = 1, o
	while n and n ~= P do
		for _, c in ipairs(n:GetChildren()) do
			if c:IsA("UIScale") then s = s * c.Scale end
		end
		n = n.Parent
	end
	return s
end

local function udim2(u)
	return ("(%.2f, %d, %.2f, %d)"):format(u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset)
end

local function trim(o)
	local corner, stroke, pad = "-", "-", "-"
	for _, c in ipairs(o:GetChildren()) do
		if c:IsA("UICorner") then corner = ("%.0f"):format(c.CornerRadius.Offset) end
		if c:IsA("UIStroke") then stroke = ("%.1f"):format(c.Thickness) end
		if c:IsA("UIPadding") then pad = "yes" end
	end
	return corner, stroke, pad
end

print("=================== BANNER GEOMETRY ===================")
print(("viewport %d x %d   |   a banner's AbsoluteSize only means something next to this")
	:format(cam.ViewportSize.X, cam.ViewportSize.Y))
print("")

local found = 0
for _, name in ipairs(NAMES) do
	local sg = P:FindFirstChild(name)
	if not sg then
		print(("%-16s (not built yet -- trigger it and re-run)"):format(name))
	else
		print(("%-16s DisplayOrder=%d IgnoreGuiInset=%s Enabled=%s")
			:format(name, sg.DisplayOrder, tostring(sg.IgnoreGuiInset), tostring(sg.Enabled)))
		for _, f in ipairs(sg:GetDescendants()) do
			-- the banner itself: a direct child of the ScreenGui, or of the StackBox wrapper
			-- TopCenterStack parents it into. Anything narrower than 100px is a label, not a card.
			local host = f.Parent
			if f:IsA("GuiObject") and host and (host == sg or host.Name == "StackBox")
				and f.AbsoluteSize.X > 100 then
				local sc = scaleOf(f)
				local corner, stroke, pad = trim(f)
				found += 1
				print(("   %-12s authored=%s  anchor=(%.1f,%.1f)  pos=%s")
					:format(f.Name, udim2(f.Size), f.AnchorPoint.X, f.AnchorPoint.Y, udim2(f.Position)))
				print(("   %-12s ABSOLUTE=%.1f x %.1f at (%.0f, %.0f)   UIScale=%.3f   corner=%s stroke=%s pad=%s vis=%s")
					:format("", f.AbsoluteSize.X, f.AbsoluteSize.Y,
						f.AbsolutePosition.X, f.AbsolutePosition.Y, sc, corner, stroke, pad, tostring(f.Visible)))
			end
		end
	end
end

-- The numbers that are NOT on any instance -- they live as constants in the scripts, and they are
-- half of what makes the column line up.
local q = P:FindFirstChild("PetQuestUI")
local tracker = q and q:FindFirstChild("Tracker")
print("")
print("=================== THE PORTABLE SPEC ===================")
print("  one banner size, whole game : 500 x 65   (hero card, event banner, arrival, every pill)")
print("  corner radius               : 12 on NotifyCenter's hero, 16 on the pills/tracker")
print("  anchor / position           : AnchorPoint (0.5, 0), Position UDim2.new(0.5, 0, 0, laneY)")
print("  TopCenterStack TOP_MARGIN   : 8 px from the top of the screen to the first banner")
print("  TopCenterStack GAP          : 8 px between stacked banners")
print(("  quest lane Y (LaneY attr)   : %s   <- tuned on the mobile emulator, NOT 12")
	:format(tracker and tostring(tracker:GetAttribute("LaneY")) or "PetQuestUI not built"))
print("  stacking is done off AbsoluteSize, never the authored 500 -- that is what keeps it")
print("  correct once the UIScale above is applied. Copy the AUTHORED numbers + the scale rule,")
print("  never the ABSOLUTE ones: those are this screen only.")
print("=========================================================")
print(("%d banner frame(s) measured"):format(found))
