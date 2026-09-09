--[[
================================================================================================
FindMonolith.studio.luau -- COMMAND BAR SCRIPT (Studio only). Paste into the Studio command bar
with the Food Realm place open; it does not belong in the game and is never synced.
================================================================================================
WHY THIS EXISTS. The stone monolith is a STATIC INSTANCE baked into the place file, not something
any script builds -- no file under src/ creates a single MeshPart, so nothing in the repo can add
or remove it. And Rojo only ever ADDS: deleting the part from a source file is impossible because
there is no source file. It has to be deleted in Studio, and this finds it.

USAGE
  1. Paste the whole file into the command bar and press Enter. It PRINTS candidates, deletes
     nothing. Each line is a clickable full path.
  2. Read the list, decide which one is the monolith.
  3. Set DELETE_EXACT_PATH to that path (copy it verbatim from the printout) and run again.
     Only an EXACT full-path match is deleted, so a typo removes nothing rather than the wrong rock.
  4. An empty Model/Folder left behind by the delete is removed too, up the chain, as long as it
     is empty and is not one of the island roots.

WHAT COUNTS AS A CANDIDATE: a MeshPart/Part/Union taller than MIN_HEIGHT whose height is at least
SLENDER x its widest horizontal side. That is the shape of a standing stone and excludes floors,
walls and the wide island props. Widen MIN_HEIGHT/SLENDER if your part does not appear.
================================================================================================
]]

local MIN_HEIGHT = 10    -- studs: shorter than this is scenery, not a monolith
local SLENDER    = 1.6   -- height must be at least this many times the widest horizontal side
local DELETE_EXACT_PATH = ""  -- e.g. "Workspace.Island_1_BeanFarm.Model.Cube" -- EXACT GetFullName()

local Workspace = game:GetService("Workspace")

local found = {}
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("BasePart") then
		local s = d.Size
		local flat = math.max(s.X, s.Z)
		if s.Y >= MIN_HEIGHT and s.Y >= SLENDER * flat then
			found[#found + 1] = d
		end
	end
end

table.sort(found, function(a, b) return a.Size.Y > b.Size.Y end)

print(("[FindMonolith] %d tall/slender part(s) (height >= %d and >= %.1fx the widest side):")
	:format(#found, MIN_HEIGHT, SLENDER))
for _, d in ipairs(found) do
	local mesh = (d:IsA("MeshPart") and d.MeshId ~= "" and d.MeshId) or "(no mesh -- plain part)"
	local tex  = (d:IsA("MeshPart") and d.TextureID ~= "" and d.TextureID) or "-"
	print(("  %-12s size=(%.1f, %.1f, %.1f)  pos=(%.0f, %.0f, %.0f)  colour=%s  mesh=%s  tex=%s\n      %s")
		:format(d.ClassName, d.Size.X, d.Size.Y, d.Size.Z,
			d.Position.X, d.Position.Y, d.Position.Z,
			tostring(d.Color), mesh, tex, d:GetFullName()))
end

if DELETE_EXACT_PATH == "" then
	print("[FindMonolith] nothing deleted. Put one of the paths above in DELETE_EXACT_PATH and re-run.")
	return
end

-- DELETE. Exact full-path match only, and it reports what it did rather than failing silently.
local target
for _, d in ipairs(found) do
	if d:GetFullName() == DELETE_EXACT_PATH then target = d; break end
end
if not target then
	warn(("[FindMonolith] NOT DELETED -- no candidate has the path %q. Copy it verbatim from the list above.")
		:format(DELETE_EXACT_PATH))
	return
end

-- Walk UP first: the parents to consider clearing away have to be captured before the part is gone.
local chain = {}
local p = target.Parent
while p and p ~= Workspace do chain[#chain + 1] = p; p = p.Parent end

print(("[FindMonolith] deleting %s  size=(%.1f, %.1f, %.1f)  pos=(%.0f, %.0f, %.0f)")
	:format(target:GetFullName(), target.Size.X, target.Size.Y, target.Size.Z,
		target.Position.X, target.Position.Y, target.Position.Z))
target:Destroy()

-- Then sweep up any parent the delete just emptied. An island root is never removed even if empty:
-- PlayerStats positions those models by name at boot and would warn forever if one vanished.
for _, node in ipairs(chain) do
	if node.Name:lower():find("island") then break end
	if (node:IsA("Model") or node:IsA("Folder")) and #node:GetChildren() == 0 then
		print("[FindMonolith]   ...and its now-empty parent " .. node:GetFullName())
		node:Destroy()
	else
		break
	end
end
print("[FindMonolith] done. Save the place (Ctrl+S) to keep the deletion.")
