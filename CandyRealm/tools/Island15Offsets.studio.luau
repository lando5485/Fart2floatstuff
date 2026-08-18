--======================================================================
-- Island15Offsets.studio.luau  --  READ-ONLY DIAGNOSTIC (Command Bar)
--======================================================================
-- ANSWERS ONE QUESTION: are island15's props in different places in Play than
-- they are in Studio, or do they only LOOK different?
--
-- Everything is measured in the BASE SLAB's own object space ("chicken zone"),
-- never in world coordinates. That is the whole trick: the island sits at Y~209
-- in Studio and Y~59419 in Play, so world Y tells you nothing, but a prop's
-- offset from the slab is the same number in both -- IF the move was rigid.
--
-- HOW TO USE
--   1  Studio, EDIT MODE (not playing). View > Command Bar. Paste this. Copy the
--      output block into a text file.
--   2  Press Play. Fly to island15 (/island15). Paste this again. Copy that too.
--   3  Diff the two.
--        * Numbers identical  -> the props are exactly where Studio put them.
--          Nothing moved. What you are seeing is a rendering/streaming problem,
--          and the next thing to fix is Workspace.StreamingMinRadius /
--          StreamingTargetRadius (IslandStreaming warns about this every boot:
--          they are stuck at the 64-stud default and cannot be set by script).
--        * Numbers differ     -> a real move. The lines that changed name the
--          exact props and tell you by how much.
--
-- It writes nothing and moves nothing, so it is safe to run at any time, in
-- either mode, as often as you like.
--======================================================================

local ISLAND = "island15"

local isl
for _, m in ipairs(workspace:GetChildren()) do
	if m:IsA("Model") and string.lower(m.Name) == ISLAND then isl = m break end
end
if not isl then
	warn("[Offsets] no model named " .. ISLAND .. " in Workspace")
	return
end

-- The slab. PrimaryPart if IslandLayout has already set it (Play), otherwise
-- find it the same way IslandLayout does, so edit mode picks the same part.
local base = isl.PrimaryPart
if not base then
	local bestArea, bestNamed = -1, false
	for _, d in ipairs(isl:GetDescendants()) do
		if d:IsA("BasePart") then
			local area = d.Size.X * d.Size.Z
			local named = string.find(string.lower(d.Name):gsub("[%s_%-]", ""), "chickenzone", 1, true) ~= nil
			if (named and not bestNamed) or (named == bestNamed and area > bestArea) then
				base, bestArea, bestNamed = d, area, named
			end
		end
	end
end
if not base then warn("[Offsets] no BasePart under " .. ISLAND) return end

local baseCF  = base.CFrame
local baseTop = base.Size.Y * 0.5   -- slab top, in slab object space

print("=========================================================")
print(("[Offsets] %s  |  slab = '%s'  (%.1f x %.1f x %.1f)")
	:format(isl.Name, base.Name, base.Size.X, base.Size.Y, base.Size.Z))
print(("[Offsets] slab world pos = (%.1f, %.1f, %.1f)   <- expected to DIFFER between edit and play")
	:format(baseCF.Position.X, baseCF.Position.Y, baseCF.Position.Z))
print("[Offsets] everything below is relative to the slab -- these must MATCH")
print("---------------------------------------------------------")

local rows = {}
for _, child in ipairs(isl:GetChildren()) do
	local cf, size
	if child:IsA("BasePart") then
		cf, size = child.CFrame, child.Size
	elseif child:IsA("Model") then
		cf, size = child:GetBoundingBox()
	end
	if cf then
		local o = baseCF:PointToObjectSpace(cf.Position)
		rows[#rows + 1] = {
			name = child.Name,
			line = ("%-28s  aboveSlab=%+9.2f   x=%+9.2f  z=%+9.2f   size=%5.1f,%5.1f,%5.1f   %s")
				:format(child.Name, (o.Y - size.Y * 0.5) - baseTop, o.X, o.Z,
					size.X, size.Y, size.Z, child.ClassName),
		}
	end
end

-- Sorted so the two dumps line up for a plain text diff.
table.sort(rows, function(a, b) return a.name < b.name end)
for _, r in ipairs(rows) do print("  " .. r.line) end

print("---------------------------------------------------------")
print(("[Offsets] %d direct child object(s). 'aboveSlab' is the gap between the"):format(#rows))
print("[Offsets] object's BOTTOM and the slab's TOP: 0 = resting, + = floating.")
print("=========================================================")
