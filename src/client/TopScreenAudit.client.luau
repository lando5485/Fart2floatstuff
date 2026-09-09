--======================================================================
-- TopScreenAudit.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- "There are two white lines at the top of the screen and I don't know why."
--
-- This names them. It lists every GuiObject ACTUALLY VISIBLE in the top band of the screen -- rendering
-- something, not merely present -- with its full path, size, colour and owning ScreenGui, sorted
-- top-to-bottom then left-to-right so the list reads in the order your eye does. The white ones are marked.
--
-- ===== HOW TO RUN IT =====
--   * It prints ONCE on its own, ~8 seconds after you join (late enough that every HUD has drawn).
--   * Type  /topaudit  in chat any time to print it again -- useful when the thing only appears after you
--     open a menu, land on an island, or an event fires.
--   * Type  /topaudit 400  to widen the band if the culprit is lower down the screen.
--
-- Then copy the block out of the client log (F9 -> Client) and hand it over.
--
-- ===== WHY A TOOL AND NOT JUST READING THE SOURCE =====
-- Rojo only ADDS. A stale copy of a script baked into the place file runs ALONGSIDE the synced one, so what
-- is on your screen is not necessarily what is in the file -- and there are ~27 duplicated scripts in this
-- place. Anything drawn by a stale copy cannot be found by grepping src/ at all, only by looking at what is
-- actually rendering. That is exactly the class of bug the "black bar" turned out to be (a stale
-- SocialRewards copy showing an empty dark toast -- see BlackBarKiller.client.luau).
--
-- HUD_AllInOne.client.lua is the standing suspect here: it is NOT in default.project.json, so Rojo never
-- syncs it -- but if a copy is baked into the place it runs, and it rebuilds the ENTIRE right-hand stats
-- panel, complete with a 2px white UIStroke and a white divider at y=187. Two copies of that panel is two
-- of every white line in it. The DUPLICATE report at the bottom of the print is what confirms or clears it.
--
-- ===== IT NOW ALSO KILLS THE LINES =====
-- The audit half stays read-only. But the culprit could not be named from the source (it is not baked into
-- StarterGui either -- the place snapshot was scanned), so this file also carries an ENFORCER, on the exact
-- precedent of BlackBarKiller: define the shape that is ALWAYS a bug, and hide only that, forever.
--
-- Two shapes qualify, and only these two:
--   A. A NAKED WHITE LINE: wide (>= 60% of the screen), thin (<= 8px), white-ish, textless, pinned in the
--      top 80px, and NOT inside any visibly-filled panel. No legitimate HUD element has this shape -- every
--      real divider in the game lives inside a panel with a visible fill, which is the guard.
--   B. A HOLLOW STROKED BAND: a near-transparent frame, wide, 30-90px tall, top edge in the first 20px,
--      wearing a white-ish UIStroke -- the "two lines ~55px apart" signature, which is ONE frame's top and
--      bottom borders. Only the STROKE is disabled; the frame (a container, possibly with children) stays.
--   C. ANY LEGACY BORDER AT ALL. BorderSizePixel DEFAULTS TO 1 and draws whenever the fill is even
--      slightly visible -- and this codebase measurably never wants it: 292 assignments of
--      BorderSizePixel = 0 across src/client and not one assignment of anything else. So every non-zero
--      border in PlayerGui is an author's omission or a stale baked-in copy's, never a design, and it is
--      zeroed wherever it is found -- not just in the top band. This is the one shape source edits cannot
--      fully fix, because the stale duplicates redraw it from code that no longer exists in the repo.
--      NOTE the topbar arithmetic that makes this the prime suspect for THESE lines: a full-screen frame
--      in an inset ScreenGui starts right under the ~58px topbar, so its 1px top border lands at y=58 --
--      "just below the top bar" -- while one in an IgnoreGuiInset gui puts the same border at y=0.
--
-- Everything hidden is printed as  [TopAudit] KILLED <path>  -- so the fix also names the culprit, and the
-- proper deletion can follow. Passthrough containers (transparency >= 0.95) do not count as panels, so a
-- line floating in a full-screen transparent holder is still caught.
--======================================================================

local Players = game:GetService("Players")
local player  = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local DEFAULT_BAND = 200   -- how far down the screen counts as "the top"

-- ===== A UISTROKE IS NOT A GuiObject =====
-- THIS IS THE CASE THE FIRST VERSION OF THIS FILE COULD NOT SEE, AND IT IS THE LIKELY ANSWER.
--
-- Two thin white horizontal lines a fixed distance apart, one of them hard against the top edge, is the
-- signature of ONE frame with a white UIStroke: you are seeing its top and bottom borders, with the left
-- and right edges off-screen or lost against the HUD. It is one object, not two.
--
-- A stroke is a child object, not a GuiObject, so it never appeared in the listing at all -- and a frame
-- that is FULLY TRANSPARENT but carries a stroke fails the draws() test below, so such a frame would paint
-- two visible white lines and this tool would report nothing whatsoever. Hence strokeOf: a visible stroke
-- makes its object worth listing on its own, whatever the object's own fill is doing.
local function strokeOf(o)
	local st = o:FindFirstChildOfClass("UIStroke")
	if st and st.Thickness > 0 and st.Transparency < 0.95 then return st end
	return nil
end

-- Is this object drawing anything a player can actually see? A frame at full transparency with no image and
-- no text is present but invisible, and listing those would bury the handful of things really on screen.
local function draws(o)
	if strokeOf(o) then return true end   -- outlined but hollow still paints lines
	if o:IsA("Frame") or o:IsA("ScrollingFrame") then
		return o.BackgroundTransparency < 0.95
	elseif o:IsA("ImageLabel") or o:IsA("ImageButton") then
		return o.ImageTransparency < 0.95 or o.BackgroundTransparency < 0.95
	elseif o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
		return o.BackgroundTransparency < 0.95 or (o.TextTransparency < 0.95 and o.Text ~= "")
	elseif o:IsA("ViewportFrame") then
		return o.BackgroundTransparency < 0.95 or o.ImageTransparency < 0.95
	end
	return false
end

-- Visible means every ANCESTOR is visible too. A card inside a hidden panel is not on screen, however
-- visible its own flag says it is.
local function shown(o)
	local n = o
	while n and n ~= PlayerGui do
		if n:IsA("GuiObject") and not n.Visible then return false end
		if n:IsA("ScreenGui") and not n.Enabled then return false end
		n = n.Parent
	end
	return true
end

local function rgb(c)
	return string.format("%d,%d,%d",
		math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function whiteish(c) return (0.299 * c.R + 0.587 * c.G + 0.114 * c.B) > 0.8 end

local function path(o)
	local parts, n = {}, o
	while n and n ~= PlayerGui do
		table.insert(parts, 1, n.Name)
		n = n.Parent
	end
	return table.concat(parts, ".")
end

local function audit(band)
	band = tonumber(band) or DEFAULT_BAND
	local rows, seenGui = {}, {}

	for _, sg in ipairs(PlayerGui:GetChildren()) do
		if sg:IsA("ScreenGui") then
			seenGui[sg.Name] = (seenGui[sg.Name] or 0) + 1
			if sg.Enabled then
				for _, o in ipairs(sg:GetDescendants()) do
					if o:IsA("GuiObject") and o.AbsoluteSize.X > 0 and o.AbsoluteSize.Y > 0
						and o.AbsolutePosition.Y < band and draws(o) and shown(o)
					then
						-- A transparent frame around visible TEXT should report the TEXT's colour. Reporting
						-- the invisible background would make every white label read as a black one.
						local col = o.BackgroundColor3
						if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.BackgroundTransparency >= 0.95 then
							col = o.TextColor3
						end
						-- A thin bar is what "line" means, and it is the shape being hunted -- call it out.
						local thin = (o.AbsoluteSize.Y <= 6 and o.AbsoluteSize.X >= 40)
							or (o.AbsoluteSize.X <= 6 and o.AbsoluteSize.Y >= 40)

						-- An OUTLINED WIDE frame paints a line along its top edge AND another along its
						-- bottom -- which is what "two white lines" looks like from the outside. Flag it as
						-- loudly as a genuinely thin bar, and print BOTH edge positions so the pair in the
						-- screenshot can be matched against one row instead of hunted as two objects.
						local st = strokeOf(o)
						local outlined = st ~= nil and o.AbsoluteSize.X >= 200
						local note = ""
						if st then
							note = string.format("   stroke=%s t=%.1f  edgesY=%d/%d",
								rgb(st.Color), st.Thickness,
								math.floor(o.AbsolutePosition.Y),
								math.floor(o.AbsolutePosition.Y + o.AbsoluteSize.Y))
							if whiteish(st.Color) then note = note .. "  <<< WHITE OUTLINE" end
						end

						table.insert(rows, {
							y = o.AbsolutePosition.Y, x = o.AbsolutePosition.X,
							white = whiteish(col) or (st ~= nil and whiteish(st.Color)),
							thin = thin or outlined,
							line = string.format("%-5d %-5d %-5d x %-5d %-16s %-13s %-24s %s",
								math.floor(o.AbsolutePosition.X), math.floor(o.AbsolutePosition.Y),
								math.floor(o.AbsoluteSize.X), math.floor(o.AbsoluteSize.Y),
								rgb(col), o.ClassName, sg.Name, path(o)),
							txt = ((o:IsA("TextLabel") or o:IsA("TextButton")) and o.Text ~= "" and o.Text or nil),
							note = note,
						})
					end
				end
			end
		end
	end

	table.sort(rows, function(a, b)
		if a.y ~= b.y then return a.y < b.y end
		return a.x < b.x
	end)

	print("=====================================================================================================")
	print(string.format("[TopAudit] %d visible objects in the top %dpx", #rows, band))
	print("     X     Y     SIZE            COLOUR           CLASS         SCREENGUI                PATH")
	print("-----------------------------------------------------------------------------------------------------")
	for _, r in ipairs(rows) do
		-- LINE beats WHITE in the marker: a thin white bar is the thing being looked for, and it should be
		-- impossible to miss in a list that may run to fifty rows.
		local mark = r.thin and (r.white and "==> " or "--> ") or (r.white and " >  " or "    ")
		print(mark .. r.line
			.. (r.txt and ("   text=" .. string.format("%q", r.txt)) or "")
			.. r.note)
	end
	print("-----------------------------------------------------------------------------------------------------")
	print("==> thin-or-outlined AND white (this is almost certainly it)   --> thin/outlined    >  white")
	print("A row whose edgesY are roughly 0 and 55 IS the pair of lines -- one frame, two borders.")

	local dupes = {}
	for name, n in pairs(seenGui) do if n > 1 then table.insert(dupes, name .. " x" .. n) end end
	if #dupes > 0 then
		table.sort(dupes)
		print("")
		print("[TopAudit] DUPLICATE ScreenGuis -- near enough always a stale copy baked into the place file")
		print("           running alongside the Rojo-synced one. Delete the baked-in LocalScript in Studio:")
		for _, d in ipairs(dupes) do print("           " .. d) end
	else
		print("")
		print("[TopAudit] No duplicate ScreenGui names -- so whatever this is, it IS in the source.")
	end
	print("=====================================================================================================")
end

--======================================================================
-- THE ENFORCER
--======================================================================
local Workspace = game:GetService("Workspace")

-- "Inside a panel" = some ancestor GuiObject is taller than 100px AND visibly filled. A full-screen
-- TRANSPARENT container (a banner stack, an effects layer) is a passthrough, not a panel -- a bug line
-- parented into one is still naked.
local function insidePanel(o)
	local n = o.Parent
	while n and n ~= PlayerGui do
		if n:IsA("GuiObject") and n.AbsoluteSize.Y > 100 and n.BackgroundTransparency < 0.95 then
			return true
		end
		n = n.Parent
	end
	return false
end

local function viewport()
	local cam = Workspace.CurrentCamera
	local v = cam and cam.ViewportSize
	return (v and v.X or 1280), (v and v.Y or 720)
end

local killed = {}   -- path -> true, so the log reports each culprit once, not once per sweep
local function kill(o, what, detail)
	local pth = path(o)
	if not killed[pth] then
		killed[pth] = true
		print("[TopAudit] KILLED " .. what .. ": " .. pth .. "  (" .. detail .. ")")
	end
end

local function enforce()
	local vw, vh = viewport()
	for _, sg in ipairs(PlayerGui:GetChildren()) do
		-- ===== OPT-OUT: TopAuditKeep =====
		-- This enforcer hunts SHAPES, not owners: a thin white bar across the top of the screen is the bug
		-- it exists to kill, and it cannot tell one drawn on purpose from a legacy leftover. The climb race
		-- bar IS that shape by design -- a 3px white hairline spanning most of the width -- so it was being
		-- switched off a few seconds after every join ("KILLED white line: ClimbRaceBar.Line").
		--
		-- So a ScreenGui may opt out by setting the TopAuditKeep attribute on itself. Deliberately an
		-- attribute on the GUI rather than a name list in here: the owner declares it, in the file that
		-- builds it, and this file never needs to learn about a new one.
		if sg:IsA("ScreenGui") and sg.Enabled and not sg:GetAttribute("TopAuditKeep") then
			for _, o in ipairs(sg:GetDescendants()) do
				-- Shape C first, unconditionally: legacy borders die everywhere. Logged only when the
				-- border was actually SHOWING (fill not fully transparent), so the print names culprits
				-- rather than cataloguing every defaulted-but-invisible frame.
				if o:IsA("GuiObject") and o.BorderSizePixel ~= 0 then
					if o.Visible and o.BackgroundTransparency < 1 and shown(o) then
						kill(o, "legacy border", string.format("BorderSizePixel=%d y=%d %dx%d fillT=%.2f",
							o.BorderSizePixel, math.floor(o.AbsolutePosition.Y),
							math.floor(o.AbsoluteSize.X), math.floor(o.AbsoluteSize.Y),
							o.BackgroundTransparency))
					end
					o.BorderSizePixel = 0
				end
				if o:IsA("GuiObject") and o.Visible and shown(o) and o.AbsolutePosition.Y <= 80
					and o.AbsoluteSize.X >= vw * 0.6 and not insidePanel(o) then

					local hasText = (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox"))
						and o.Text ~= "" and o.TextTransparency < 0.95

					-- Shape A: the naked white line
					if o.AbsoluteSize.Y <= 8 and not hasText
						and o.BackgroundTransparency < 0.6 and whiteish(o.BackgroundColor3) then
						kill(o, "white line", string.format("y=%d %dx%d rgb=%s",
							math.floor(o.AbsolutePosition.Y), math.floor(o.AbsoluteSize.X),
							math.floor(o.AbsoluteSize.Y), rgb(o.BackgroundColor3)))
						o.Visible = false

					-- Shape B: the hollow stroked band -- disable the STROKE only, never the frame
					elseif o.AbsoluteSize.Y >= 30 and o.AbsoluteSize.Y <= 90
						and o.AbsolutePosition.Y <= 20 and o.BackgroundTransparency >= 0.7 then
						local st = strokeOf(o)
						if st and st.Enabled and whiteish(st.Color) then
							kill(o, "white outline", string.format("edgesY=%d/%d stroke=%s t=%.1f",
								math.floor(o.AbsolutePosition.Y),
								math.floor(o.AbsolutePosition.Y + o.AbsoluteSize.Y),
								rgb(st.Color), st.Thickness))
							st.Enabled = false
						end

					-- Shape D: a WHITE-STROKED HOLLOW SHEET -- an effect overlay (a fade, a flash, a storm
					-- dim) that something dressed as a menu card. This is what an early MenuSkin build did to
					-- every full-screen overlay: on a transparent sheet the 3px white rim is the only thing
					-- that draws, and its top edge is a hairline at y=0 (IgnoreGuiInset) or ~58 (inset).
					-- MenuSkin no longer adopts these; this branch keeps the shape dead whatever draws it.
					-- The UICorner goes too -- it arrived with the rim, and a sheet has no corners to round.
					elseif o.AbsoluteSize.Y >= vh * 0.4 and o.BackgroundTransparency >= 0.9 then
						local st = strokeOf(o)
						if st and st.Enabled and whiteish(st.Color) then
							kill(o, "stroked overlay sheet", string.format("%dx%d stroke=%s t=%.1f",
								math.floor(o.AbsoluteSize.X), math.floor(o.AbsoluteSize.Y),
								rgb(st.Color), st.Thickness))
							st.Enabled = false
							local c = o:FindFirstChildOfClass("UICorner")
							if c then c:Destroy() end
						end
					end
				end
			end
		end
	end
end

-- EVERY 2 SECONDS FOR THE FIRST MINUTE, then a slow patrol. The first cut of this swept at 3/6/10/20/40s
-- and the early passes hit nothing: the garden intro covers the screen and the HUD ScreenGuis are DISABLED
-- until it ends, so shown() correctly reported the bordered frames as not-visible -- and the first sweep
-- that could actually see them was the 20-SECOND one. A player is looking at the sky for all 20 of those
-- seconds. The 2s cadence lands the kill within a beat of the HUD revealing, whenever that turns out to be;
-- the walk is a few thousand nodes and costs nothing at this rate.
task.spawn(function()
	for _ = 1, 30 do
		task.wait(2)
		pcall(enforce)
	end
	while true do
		task.wait(30)
		pcall(enforce)
	end
end)

-- One automatic run, late enough that every HUD has built and any arrival banner has settled.
task.delay(8, function()
	local ok, err = pcall(audit, DEFAULT_BAND)
	if not ok then warn("[TopAudit] " .. tostring(err)) end
end)

-- /topaudit [band] -- re-run on demand, because some of these only appear after you open a menu or land.
player.Chatted:Connect(function(msg)
	local band = string.match(msg, "^/topaudit%s*(%d*)%s*$")
	if band == nil then return end
	pcall(enforce)  -- kill first, so the printed listing shows the AFTER state plus the KILLED lines above it
	local ok, err = pcall(audit, tonumber(band))
	if not ok then warn("[TopAudit] " .. tostring(err)) end
end)

print("[TopAudit] loaded -- auto-runs in 8s, or type /topaudit (optionally /topaudit 400) any time")
