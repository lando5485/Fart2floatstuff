--[[
================================================================================================
IslandAudit.studio.luau -- COMMAND BAR SCRIPT (Studio only). Paste the whole file into the Studio
command bar with the Food Realm place open. It PRINTS ONLY -- it never moves, renames or deletes
anything. It does not belong in the game and is never synced.
================================================================================================
WHY THIS EXISTS. "Island N is in the wrong place" is almost never a bad number in IslandOrder --
SLOT_POS is asserted by tools/ladder.py and PlayerStats prints the Y it used at every boot. It is
almost always one of four things in the PLACE, none of which any source file can see:

  1. DUPLICATE  -- two Models match "Island_N_". findIslandModel() takes the first top-level one,
                   moves THAT to SLOT_POS, and leaves the real island wherever it was authored.
                   This is the classic "the island didn't move" bug: you are looking at the copy
                   that nothing repositioned.
  2. GUTTED     -- the model the game found is an empty husk (its parts were dragged out, or the
                   real contents live in a different model). It gets moved to the right Y with
                   nothing inside it, so the island "is" at 1848 but there is nothing to stand on.
  3. NO Stand_N -- stand detection falls through Method 1 -> 2 -> 3 -> 3.5 and ends up on whatever
                   the largest flat part happens to be, INCLUDING props built at runtime (the AFK
                   farm's tank is a big flat slab and wins easily). You then land somewhere that
                   has nothing to do with the island's booth.
  4. OFF-CENTRE -- no island has a PrimaryPart, so PlayerStats positions every one of them with
                   MoveTo, which puts the BOUNDING-BOX CENTRE on SLOT_POS. Cliffs, a tall tower or
                   one stray far-away part drag that centre away from the walkable plateau, and the
                   landmass hangs off to one side of where the game thinks the island is.

WHEN TO RUN IT
  * While PLAYTESTING (F5), a few seconds after boot -- islands are positioned by then, so the
    printed centres are the live ones and the SLOT delta is meaningful. This is the useful mode.
  * In EDIT mode it still answers 1, 2 and 3 (contents are contents); ignore the SLOT delta there,
    because nothing has moved the islands yet.

READING THE OUTPUT. The per-island block is fine to skim -- go to the VERDICT list at the bottom
first. Anything printed there is a real difference from the other thirteen islands.
================================================================================================
]]

local Workspace = game:GetService("Workspace")

local NAMES = {
	"Island_1_BeanFarm","Island_2_BroccoliBluff","Island_3_CabbageCliffs",
	"Island_4_TurnipTranquil","Island_5_CoconutCove","Island_6_BreadBoard",
	"Island_7_PastaPeak","Island_8_PopcornPinnacle","Island_9_MilkMarsh",
	"Island_10_ButterSwamp","Island_11_IceCreamIsle","Island_12_BurgerBluff",
	"Island_13_BurritoBarrens","Island_14_PizzaPalms",
}
-- IslandOrder.SLOT_POS, copied. A command-bar chunk cannot require ReplicatedStorage.Shared in
-- edit mode, and this file must run in BOTH modes. If the ladder ever moves an island, update it.
local SLOT = {
	{0,150,0}, {120,780,60}, {-160,1848,100}, {180,3090,-120}, {-200,4395,160},
	{220,6187.5,-180}, {-240,8073,200}, {260,10555.5,-220}, {-280,13165.5,240},
	{300,16614,-260}, {-320,20239.5,280}, {340,25066.5,-300}, {-360,31266.5,320},
	{380,38162.7,-340},
}

-- Every Model anywhere in Workspace whose name contains "Island_<n>_". The plain-substring test is
-- the same one findIslandModel() uses, so "Island_1_" can never match "Island_10_" (the next char
-- there is a digit, not "_") and a trailing space or hidden character still matches.
local function matches(n)
	local key, out = "Island_" .. n .. "_", {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name:find(key, 1, true) then out[#out + 1] = d end
	end
	return out
end

-- findIslandModel()'s pick order, replicated exactly: exact top-level name -> top-level substring
-- -> nested anywhere. Whatever this returns is the model the GAME moved to SLOT_POS.
local function picked(n)
	local exact = Workspace:FindFirstChild(NAMES[n])
	if exact then return exact, "exact top-level name" end
	local key = "Island_" .. n .. "_"
	for _, c in ipairs(Workspace:GetChildren()) do
		if c:IsA("Model") and c.Name:find(key, 1, true) then return c, "top-level, name contains " .. key end
	end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name:find(key, 1, true) then return d, "NESTED under " .. tostring(d.Parent) end
	end
	return nil, "not found"
end

-- Counts + the largest flat BasePart, which is precisely what stand Method 3.5 would land on.
local function survey(model)
	local parts, models, standModel, bestPart, bestArea, unanchored = 0, 0, nil, nil, 0, 0
	local want = "Stand_" .. tostring(model:GetAttribute("__n") or "")
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts = parts + 1
			if not d.Anchored then unanchored = unanchored + 1 end
			local a = d.Size.X * d.Size.Z
			if a > bestArea then bestArea, bestPart = a, d end
		elseif d:IsA("Model") then
			models = models + 1
			if d.Name == want then standModel = d end
		end
	end
	return parts, models, standModel, bestPart, bestArea, unanchored
end

local function v3(v) return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z) end

-- STRAY PARTS -- the same test PlayerStats now uses. A part sitting more than OUTLIER_RADIUS from the
-- MEDIAN part of the island stretches the bounding box, and since MoveTo aims that box's CENTRE at
-- SLOT_POS, the island itself lands somewhere else. This is what put Cabbage Cliffs 1605 studs low.
-- The median is the point of it: it ignores a handful of outliers where a mean or a box cannot.
local OUTLIER_RADIUS = 1200
local function median(t) table.sort(t) return #t > 0 and t[(#t // 2) + 1] or 0 end
local function strayParts(model)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then parts[#parts + 1] = d end
	end
	if #parts == 0 then return {}, nil end
	local xs, ys, zs = {}, {}, {}
	for _, d in ipairs(parts) do xs[#xs+1] = d.Position.X; ys[#ys+1] = d.Position.Y; zs[#zs+1] = d.Position.Z end
	local med = Vector3.new(median(xs), median(ys), median(zs))
	local out = {}
	for _, d in ipairs(parts) do
		local dist = (d.Position - med).Magnitude
		if dist > OUTLIER_RADIUS then out[#out + 1] = { part = d, dist = dist } end
	end
	table.sort(out, function(a, b) return a.dist > b.dist end)
	return out, med
end

print("=================== ISLAND AUDIT ===================")
print(("mode: %s"):format(game:GetService("RunService"):IsRunning() and "PLAYTEST (positions are live)"
	or "EDIT (contents are real; ignore the SLOT delta -- nothing has moved yet)"))

local dupes, nostand, gutted, offcentre, missing, strayIslands, looseIslands = {}, {}, {}, {}, {}, {}, {}
local counts = {}

for n = 1, 14 do
	local all = matches(n)
	local model, how = picked(n)
	print(("\n-- ISLAND %d  %s"):format(n, NAMES[n]))
	print(("   models matching 'Island_%d_': %d"):format(n, #all))
	for _, m in ipairs(all) do
		print(("      %s%s"):format(m:GetFullName(), m == model and "   <-- THE GAME USES THIS ONE" or ""))
	end
	if #all > 1 then dupes[#dupes + 1] = n end
	if not model then
		print("   NOT FOUND -- nothing in Workspace matches. Restore it in Studio.")
		missing[#missing + 1] = n
	else
		model:SetAttribute("__n", n) -- survey() reads it to know which Stand_N to look for
		local parts, models, stand, best, area, unanchored = survey(model)
		model:SetAttribute("__n", nil)
		counts[n] = parts
		print(("   picked by: %s"):format(how))
		print(("   PrimaryPart: %s   (none => positioned with MoveTo, which centres the BOUNDING BOX on SLOT_POS)")
			:format(model.PrimaryPart and model.PrimaryPart.Name or "NONE"))
		print(("   contents: %d BasePart(s), %d Model(s)"):format(parts, models))
		-- UNANCHORED parts are how Cabbage Cliffs ended up "positioned at Y=1848" while physically lying
		-- on Bean Farm: MoveTo places the island, physics then drops every unanchored part. An island is
		-- static scenery -- everything in it should be anchored.
		if unanchored > 0 then
			print(("   *** %d UNANCHORED PART(S) -- the island FALLS after PlayerStats places it ***"):format(unanchored))
			looseIslands[#looseIslands + 1] = ("%d (%d unanchored of %d parts)"):format(n, unanchored, parts)
		else
			print("   anchoring: all parts anchored")
		end
		print(("   Stand_%d: %s"):format(n, stand and stand:GetFullName() or "*** MISSING -- stand falls through to Method 3.5 ***"))
		if not stand then nostand[#nostand + 1] = n end
		if best then
			print(("   largest flat part (what Method 3.5 would pick): '%s' area=%.0f at %s")
				:format(best.Name, area, v3(best.Position)))
		end
		local sp, med = strayParts(model)
		if med then
			if #sp == 0 then
				print(("   stray parts: none (all %d part(s) within %d studs of the island's median at %s)")
					:format(parts, OUTLIER_RADIUS, v3(med)))
			else
				print(("   *** %d STRAY PART(S) -- these stretch the bounding box and drag the island off SLOT_POS ***")
					:format(#sp))
				for i = 1, math.min(#sp, 10) do
					print(("      %s  at %s  (%d studs from the island)")
						:format(sp[i].part:GetFullName(), v3(sp[i].part.Position), sp[i].dist))
				end
				if #sp > 10 then print(("      ... and %d more"):format(#sp - 10)) end
				strayIslands[#strayIslands + 1] = ("%d (%d stray part(s), worst %d studs out)"):format(n, #sp, sp[1].dist)
			end
		end
		if parts > 0 then
			local cf, size = model:GetBoundingBox()
			local want = Vector3.new(SLOT[n][1], SLOT[n][2], SLOT[n][3])
			local d = cf.Position - want
			print(("   bbox centre %s  size %s"):format(v3(cf.Position), v3(size)))
			print(("   SLOT_POS    %s  ->  delta %s  (%.0f studs)"):format(v3(want), v3(d), d.Magnitude))
			if d.Magnitude > 50 then offcentre[#offcentre + 1] = ("%d (off by %.0f studs)"):format(n, d.Magnitude) end
			-- Is there anything solid directly under where the game thinks this island is?
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = {}
			local hit = Workspace:Raycast(want + Vector3.new(0, 60, 0), Vector3.new(0, -400, 0), rp)
			print(("   ground under SLOT_POS: %s"):format(hit
				and ("'" .. hit.Instance:GetFullName() .. "' at Y=" .. string.format("%.1f", hit.Position.Y))
				or "*** NOTHING within 400 studs below ***"))
		else
			print("   *** NO PARTS AT ALL -- this is an empty husk ***")
			gutted[#gutted + 1] = n
		end
	end
end

-- An island with a tiny fraction of the median part count has almost certainly been emptied out.
local sorted = {}
for _, c in pairs(counts) do sorted[#sorted + 1] = c end
table.sort(sorted)
local median = #sorted > 0 and sorted[math.ceil(#sorted / 2)] or 0
local thin = {}
for n, c in pairs(counts) do
	if median > 0 and c < median * 0.15 then thin[#thin + 1] = ("%d (%d parts vs median %d)"):format(n, c, median) end
end
table.sort(thin)

print("\n=================== VERDICT ===================")
local clean = true
local function report(list, headline, what)
	if #list == 0 then return end
	clean = false
	print(headline)
	for _, x in ipairs(list) do print("   * island " .. tostring(x)) end
	print("   " .. what)
end
report(missing,  "NOT IN WORKSPACE:", "restore the model, or fix its name to the entry in NAMES above.")
report(dupes,    "DUPLICATE MODELS -- the game may be moving the wrong copy:",
	"delete the copy that is NOT marked '<-- THE GAME USES THIS ONE', or, if the marked one is the empty\n   copy, delete THAT and rename the real island to the exact name so findIslandModel picks it up.")
report(gutted,   "EMPTY HUSK (no parts):", "the island's geometry was dragged out of the model. Put it back inside.")
report(thin,     "SUSPICIOUSLY FEW PARTS:", "compare against a healthy island; contents were probably moved out.")
report(nostand,  "NO Stand_N MODEL:",
	"add a Model named exactly 'Stand_N' at the booth, or the landing spot is whatever slab is biggest --\n   which after boot includes runtime props like the AFK farm's tank.")
report(looseIslands, "UNANCHORED PARTS -- the island falls out of the sky after placement:",
	"this is what dropped Cabbage Cliffs onto Bean Farm: MoveTo places the island, physics then drops it."
	.. " PlayerStats now anchors islands at boot as a safety net, but fix it at the source: select the"
	.. " island model in Studio, select all its parts (Ctrl+A inside it) and Anchor them, then save.")
report(strayIslands, "STRAY PARTS INSIDE THE ISLAND MODEL:",
	"this is the Cabbage Cliffs bug. PlayerStats now detects and corrects for these at boot (it warns with\n"
	.. "   ISLAND N: ... CORRECTED), but the real fix is here: in Studio, move or delete the parts listed\n"
	.. "   above so they are not descendants of the island model, and the bounding box matches it again.")
report(offcentre,"BOUNDING-BOX CENTRE IS NOT ON SLOT_POS:",
	"in a PLAYTEST this should be ~0. A big delta means something is moving/blocking it, or a stray far-away\n   part inside the model is dragging the bounding box (find it: it will be the odd one out in the list above).")
if clean then print("all 14 islands look consistent -- one model each, parts present, Stand_N present, centred on SLOT_POS.") end
print("===============================================")
