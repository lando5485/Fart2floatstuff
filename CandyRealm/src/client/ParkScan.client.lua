--======================================================================
-- ParkScan.client.lua  (LocalScript)  -- TEMPORARY. Delete once the Ancient Tree quest is wired up.
--======================================================================
-- Checks that the Ancient Tree quest's MARKER PARTS exist, and prints where/how big each one is.
-- Read only -- it never touches, moves or modifies anything.
--
-- HOW TO USE:
--   1. Ctrl+S in Studio so Rojo syncs this in, then Play.
--   2. Walk INTO the park (StreamingEnabled means far-away parts aren't loaded until you're near).
--   3. Read the checklist in Output. Anything MISSING still needs a part renamed.
--   4. Press  K  for a full dump of everything around you -- use that if a marker isn't being found,
--      or to show me what art is already standing in the park.
--   5. Paste the [ParkScan] block back to me.
--======================================================================

local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local RADIUS    = 220     -- studs around you that the K dump covers
local MAX_DEPTH = 3       -- how many levels of children to print per model
local MAX_KIDS  = 40      -- cap per level so a 500-leaf model doesn't flood Output

-- The markers the quest expects. `need` = the quest can't run without it.
local MARKERS = {
	{ key = "fountain",    need = true,  what = "fountain gets built here" },
	{ key = "garden1",     need = true,  what = "garden plot 1" },
	{ key = "garden2",     need = true,  what = "garden plot 2" },
	{ key = "garden3",     need = true,  what = "garden plot 3" },
	{ key = "ancienttree", need = true,  what = "the tree" },
	{ key = "gate",        need = true,  what = "THREE parts all named 'gate' -- one per garden" },
	{ key = "candynpc",    need = false, what = "quest giver; also matches 'Candy Npc'. Without it the valve opens immediately" },
}

local function norm(s)
	return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", ""))
end

local function pathOf(inst)
	local parts, cur = {}, inst
	while cur and cur ~= Workspace do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return "Workspace/" .. table.concat(parts, "/")
end

local function pivotOf(inst)
	local ok, cf = pcall(function()
		if inst:IsA("Model") then return inst:GetPivot() end
		return inst.CFrame
	end)
	if ok and cf then return cf.Position end
	return nil
end

local function sizeOf(inst)
	local ok, sz = pcall(function()
		if inst:IsA("Model") then local _, s = inst:GetBoundingBox(); return s end
		return inst.Size
	end)
	if ok and sz then return sz end
	return nil
end

local function fmtV3(v)
	if not v then return "?" end
	return ("%.0f, %.0f, %.0f"):format(v.X, v.Y, v.Z)
end

local function findByName(key)
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("BasePart")) and norm(d.Name) == key then return d end
	end
	return nil
end

-- how many instances share this name -- "gate" is deliberately used three times
local function countByName(key)
	local n = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("BasePart")) and norm(d.Name) == key then n += 1 end
	end
	return n
end

-- ============================================================================
-- THE CHECKLIST
-- ============================================================================
local function checklist()
	print("[ParkScan] ========================================================")
	print("[ParkScan] MARKER CHECKLIST")
	print("[ParkScan] ========================================================")
	local missingRequired = 0
	for _, m in ipairs(MARKERS) do
		local found = findByName(m.key)
		if found then
			local pos, sz = pivotOf(found), sizeOf(found)
			print(("[ParkScan]  OK       %-12s  %s  at(%s)  size(%s)  [%s]")
				:format(m.key, pathOf(found), fmtV3(pos), fmtV3(sz), found.ClassName))
			if found:IsA("BasePart") and not found.Anchored then
				print(("[ParkScan]           ^^ WARNING: '%s' is NOT anchored -- it will fall."):format(found.Name))
			end
			if m.key == "gate" then
				local n = countByName("gate")
				print(("[ParkScan]           ^^ %d part(s) named 'gate' found%s")
					:format(n, n == 3 and "" or "  <-- the quest expects exactly 3"))
			end
			if sz and sz.Magnitude < 0.1 then
				-- an empty Model: no parts inside, so no footprint to read. Fine as a position
				-- marker (the quest drops a ray to find the ground and uses its default width),
				-- but you can't size the plot by resizing it.
				print(("[ParkScan]           ^^ '%s' is an EMPTY MODEL -- position only, default size used."):format(found.Name))
			end
		elseif m.need then
			missingRequired = missingRequired + 1
			print(("[ParkScan]  MISSING  %-12s  <-- rename a part to this  (%s)"):format(m.key, m.what))
		else
			print(("[ParkScan]  --       %-12s  optional, not found  (%s)"):format(m.key, m.what))
		end
	end
	print("[ParkScan] --------------------------------------------------------")
	if missingRequired == 0 then
		print("[ParkScan] All required markers present. Ready to build the quest.")
	else
		print(("[ParkScan] %d required marker(s) still missing."):format(missingRequired))
		print("[ParkScan] (If you HAVE named them, they may just not have STREAMED IN yet -- empty")
		print("[ParkScan]  Models replicate at once, but a real Part only arrives when you're near it.")
		print("[ParkScan]  Fly to island 13; this re-checks itself automatically.)")
	end
	return missingRequired
end

-- ============================================================================
-- PRESS K -- everything near the player, whatever it's called
-- ============================================================================
local function dump(inst, depth, indent)
	local pos, sz = pivotOf(inst), sizeOf(inst)
	local partCount = 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then partCount = partCount + 1 end
	end

	local line = ("%s%s  [%s]"):format(indent, inst.Name, inst.ClassName)
	if inst:IsA("Model") then line = line .. ("  parts=%d"):format(partCount) end
	if pos then line = line .. ("  at(%s)"):format(fmtV3(pos)) end
	if sz  then line = line .. ("  size(%s)"):format(fmtV3(sz)) end
	print("[ParkScan] " .. line)

	if depth >= MAX_DEPTH then
		if #inst:GetChildren() > 0 then
			print(("[ParkScan] %s   ...(%d more children, not shown)"):format(indent, #inst:GetChildren()))
		end
		return
	end

	local shown = 0
	for _, child in ipairs(inst:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") or child:IsA("Folder") then
			shown = shown + 1
			if shown > MAX_KIDS then
				print(("[ParkScan] %s   ...(truncated at %d children)"):format(indent, MAX_KIDS))
				break
			end
			dump(child, depth + 1, indent .. "    ")
		end
	end
end

local function radiusDump()
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then print("[ParkScan] no character yet -- respawn and press K again."); return end
	local origin = hrp.Position

	print("[ParkScan] ========================================================")
	print(("[ParkScan] RADIUS DUMP -- everything within %d studs of (%s)"):format(RADIUS, fmtV3(origin)))
	print("[ParkScan] ========================================================")

	local near = {}
	for _, d in ipairs(Workspace:GetChildren()) do
		if d:IsA("Model") or d:IsA("BasePart") then
			if d ~= char and not Players:GetPlayerFromCharacter(d) then
				local p = pivotOf(d)
				if p and (p - origin).Magnitude <= RADIUS then
					table.insert(near, { inst = d, dist = (p - origin).Magnitude })
				end
			end
		end
	end
	table.sort(near, function(a, b) return a.dist < b.dist end)

	if #near == 0 then
		print("[ParkScan] nothing within range -- stand closer, or raise RADIUS at the top of this script.")
		return
	end
	for _, entry in ipairs(near) do
		print(("[ParkScan] --- %s  (%.0f studs away)"):format(pathOf(entry.inst), entry.dist))
		dump(entry.inst, 1, "    ")
	end
	print(("[ParkScan] radius dump done -- %d object(s)."):format(#near))
	print("[ParkScan] re-running the marker checklist now that you're standing in the park:")
	checklist()
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	task.wait(6)   -- let the world (and any streamed-in chunks) settle first
	print("[ParkScan] >>> ParkScan loaded. Walk into the park, then press K. <<<")
	local missing = checklist()
	-- Keep re-checking rather than judging the world on one early sweep: parts stream in as you
	-- approach island 13, so a marker reported MISSING at join can appear a minute later. Only
	-- reprints when the answer actually CHANGES, so it can't spam Output.
	local last = missing
	for _ = 1, 100 do
		if last == 0 then break end
		task.wait(3)
		local now = 0
		for _, m in ipairs(MARKERS) do
			if m.need and not findByName(m.key) then now += 1 end
		end
		if now ~= last then
			last = now
			print("[ParkScan] (marker set changed -- re-checking)")
			checklist()
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.K then radiusDump() end
end)
