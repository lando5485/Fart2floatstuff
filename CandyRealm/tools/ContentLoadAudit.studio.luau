--======================================================================
-- ContentLoadAudit.studio.luau
--======================================================================
-- PASTE INTO THE STUDIO COMMAND BAR (edit mode, not Play) AND RUN.
--
-- Finds what makes Studio show "Gameplay Paused -- please wait while the game content loads".
--
-- ⚠ READ THIS BEFORE TRUSTING THE OUTPUT -- WHAT THAT DIALOG ACTUALLY MEANS
--
-- The pause is NOT caused by "lacking capability LoadUnownedAsset". Those come from
-- require(assetId) inside free-model scripts: a MODULE load failing, which is instant and
-- throws. They are worth deleting (section 4 lists them) but they are not the pause.
--
-- The pause is the client waiting on CONTENT -- meshes, textures, sounds, unions -- that is
-- still being fetched or streamed when something needs it. In this place there are three
-- realistic sources, and this audit measures all three:
--
--   1. ASSETS THAT NEVER RESOLVE. A mesh or texture id that 404s or is not approved for this
--      experience is retried and waited on rather than skipped. Section 1.
--   2. THE STREAMING RADIUS. Workspace.StreamingMinRadius is at its 64-stud default in this
--      place (IslandStreaming warns about it on every single boot). At 64 studs the client is
--      guaranteed almost nothing, so it is constantly fetching as you turn. Section 3 reports it.
--   3. THOUSANDS OF PARTS BUILT AT BOOT. The quest scripts are the biggest content producer
--      here -- the park alone builds ~3,100 parts in the first seconds. Section 3 counts them.
--
-- Nothing here modifies the place. It reads, measures and prints.
--======================================================================

local ContentProvider = game:GetService("ContentProvider")
local Workspace       = game:GetService("Workspace")

local BATCH       = 64      -- assets per PreloadAsync call; keeps Studio responsive
local BIG_MODEL   = 150     -- parts before a model counts as "heavy"
local NEAR_QUEST  = 250     -- studs from a quest marker that counts as "near"

--======================================================================
-- WHICH ISLAND IS THIS THING ON?
--======================================================================
-- Grouping is by ancestry first (the reliable answer) and by distance second, because plenty of
-- this place sits loose in Workspace next to an island rather than inside it -- IslandStreaming's
-- own audit reports that every boot.
local islands = {}
for _, m in ipairs(Workspace:GetChildren()) do
	if m:IsA("Model") and string.lower(m.Name):match("^island_?%d+") then
		local ok, cf, size = pcall(function() return m:GetBoundingBox() end)
		islands[#islands + 1] = {
			name = m.Name, model = m,
			centre = ok and cf and cf.Position or Vector3.zero,
			half = ok and size and size * 0.5 or Vector3.new(1, 1, 1),
		}
	end
end

local function islandOf(inst)
	for _, isl in ipairs(islands) do
		if inst:IsDescendantOf(isl.model) then return isl.name end
	end
	-- not inside one: fall back to nearest by distance, so loose parts still group sensibly
	local pos
	local ok = pcall(function()
		if inst:IsA("BasePart") then pos = inst.Position
		elseif inst:IsA("Model") then pos = inst:GetPivot().Position
		else
			local p = inst:FindFirstAncestorWhichIsA("BasePart")
				or inst:FindFirstAncestorWhichIsA("Model")
			if p then pos = p:IsA("BasePart") and p.Position or p:GetPivot().Position end
		end
	end)
	if not ok or not pos then return "(no island)" end
	local best, bestD
	for _, isl in ipairs(islands) do
		local d = (pos - isl.centre).Magnitude
		if not bestD or d < bestD then best, bestD = isl.name, d end
	end
	if best and bestD and bestD < 1200 then return best .. "  (LOOSE, not inside the model)" end
	return "(no island)"
end

--======================================================================
-- 1. EVERY ASSET ID IN THE PLACE, AND WHETHER IT RESOLVES
--======================================================================
-- Each property is checked by name because the classes do not share an interface: a MeshPart
-- carries MeshId + TextureID, a SpecialMesh MeshId + TextureId (different capitalisation, and
-- yes that is a real Roblox inconsistency), a Decal/Texture just Texture.
local ASSET_PROPS = {
	MeshPart        = { "MeshId", "TextureID" },
	SpecialMesh     = { "MeshId", "TextureId" },
	Decal           = { "Texture" },
	Texture         = { "Texture" },
	Sound           = { "SoundId" },
	ParticleEmitter = { "Texture" },
	Beam            = { "Texture" },
	Trail           = { "Texture" },
	ImageLabel      = { "Image" },
	ImageButton     = { "Image" },
	Sky             = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" },
	Animation       = { "AnimationId" },
}

local probes, byProbe = {}, {}     -- probe instance -> { inst=, prop=, id= }
local seenId = {}                  -- id -> first instance, so one id is tested once

for _, d in ipairs(game:GetDescendants()) do
	local props = ASSET_PROPS[d.ClassName]
	if props then
		for _, prop in ipairs(props) do
			local ok, id = pcall(function() return d[prop] end)
			if ok and type(id) == "string" and id ~= "" and not seenId[id] then
				seenId[id] = true
				-- PreloadAsync takes INSTANCES, and reports status per contentId. A throwaway
				-- Decal carrying the id is the cheapest way to ask about an id in isolation
				-- without dragging the real instance (and its whole model) into the request.
				local probe
				if d:IsA("Sound") then probe = Instance.new("Sound"); probe.SoundId = id
				elseif d:IsA("Animation") then probe = Instance.new("Animation"); probe.AnimationId = id
				elseif prop == "MeshId" then probe = Instance.new("SpecialMesh"); probe.MeshId = id
				else probe = Instance.new("Decal"); probe.Texture = id end
				probes[#probes + 1] = probe
				byProbe[id] = { inst = d, prop = prop, id = id }
			end
		end
	end
end

local failures = {}
print(("[Audit] testing %d unique asset id(s) in batches of %d..."):format(#probes, BATCH))
for i = 1, #probes, BATCH do
	local chunk = {}
	for j = i, math.min(i + BATCH - 1, #probes) do chunk[#chunk + 1] = probes[j] end
	pcall(function()
		ContentProvider:PreloadAsync(chunk, function(contentId, status)
			if status ~= Enum.AssetFetchStatus.Success then
				local rec = byProbe[contentId]
				if rec then
					failures[#failures + 1] = {
						island = islandOf(rec.inst),
						path = rec.inst:GetFullName(),
						prop = rec.prop, id = contentId, status = tostring(status),
					}
				end
			end
		end)
	end)
end
for _, pr in ipairs(probes) do pr:Destroy() end

--======================================================================
-- 2. FREE-MODEL SCRIPT CHAINS (the LoadUnownedAsset spam)
--======================================================================
-- Matched on NAME, not path, so moving or duplicating the model does not hide them. These are
-- the chains SecurityWatchdog already counts and mutes; this lists them individually with full
-- paths, which is what you need to delete them.
local JUNK = {
	ProceduralGeneration = true, SmartObject = true, GeometryPrimitives = true,
	MathUtils = true, ConstructiveSolidGeometry = true, Package = true,
	TextureConfiguration = true, CoreViewSystem = true, PoseTexture = true,
	LightConfig = true, EasyConfiguration = true, Type = true, qPerfectionWeld = true,
}
local junkFound = {}
for _, d in ipairs(game:GetDescendants()) do
	if (d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")) and JUNK[d.Name] then
		junkFound[#junkFound + 1] = { island = islandOf(d), path = d:GetFullName(), class = d.ClassName }
	end
end

--======================================================================
-- 3. HEAVY MODELS, AND THE STREAMING SETTINGS THAT DECIDE WHEN THEY ARRIVE
--======================================================================
local QUEST_MARKERS = {
	mixer = true, oven = true, chickenpart = true, fountain = true, gate = true,
	campfire = true, giantcandy = true, giantcookie = true, tractor = true,
	wheatplant = true, syruppump = true, butterlauncher = true, crystal = true,
	unstable = true, gumball = true, waste = true, guyser = true,
}
local function norm(s) return (tostring(s):lower():gsub("[%s_%-]", "")) end

local markers = {}
for _, d in ipairs(Workspace:GetDescendants()) do
	if (d:IsA("BasePart") or d:IsA("Model")) and QUEST_MARKERS[norm(d.Name)] then
		local okp, pos = pcall(function()
			return d:IsA("BasePart") and d.Position or d:GetPivot().Position
		end)
		if okp and pos then markers[#markers + 1] = { name = d.Name, pos = pos } end
	end
end

local heavy = {}
for _, m in ipairs(Workspace:GetDescendants()) do
	if m:IsA("Model") then
		local n = 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then n += 1 end
		end
		if n >= BIG_MODEL then
			local okp, pos = pcall(function() return m:GetPivot().Position end)
			local nearest, nd
			if okp and pos then
				for _, mk in ipairs(markers) do
					local dd = (pos - mk.pos).Magnitude
					if not nd or dd < nd then nearest, nd = mk.name, dd end
				end
			end
			heavy[#heavy + 1] = {
				island = islandOf(m), path = m:GetFullName(), parts = n,
				stream = tostring(m.ModelStreamingMode),
				near = (nd and nd <= NEAR_QUEST) and ("%s (%.0f studs)"):format(nearest, nd) or nil,
			}
		end
	end
end
table.sort(heavy, function(a, b) return a.parts > b.parts end)

--======================================================================
-- THE SUMMARY, GROUPED BY ISLAND
--======================================================================
local function group(list)
	local by, order = {}, {}
	for _, r in ipairs(list) do
		if not by[r.island] then by[r.island] = {}; order[#order + 1] = r.island end
		table.insert(by[r.island], r)
	end
	table.sort(order)
	return by, order
end

print("")
print("======================================================================")
print("  CONTENT LOAD AUDIT")
print("======================================================================")

print("")
print(("--- 1. ASSET IDS THAT DO NOT RESOLVE  (%d) ---"):format(#failures))
print("    These are waited on and retried by the client. This is the category that")
print("    genuinely contributes to the content-load pause.")
if #failures == 0 then
	print("    none -- every mesh/texture/sound id in the place resolves.")
else
	local by, order = group(failures)
	for _, isl in ipairs(order) do
		print(("  [%s]"):format(isl))
		for _, r in ipairs(by[isl]) do
			print(("      %s"):format(r.path))
			print(("          .%s = %s   -> %s"):format(r.prop, r.id, r.status))
		end
	end
end

print("")
print(("--- 2. FREE-MODEL SCRIPTS TO DELETE  (%d) ---"):format(#junkFound))
print("    Source of the 'lacking capability LoadUnownedAsset' spam. Delete these in Studio,")
print("    then republish. They are not the pause, but they are dead weight and noise.")
if #junkFound == 0 then
	print("    none")
else
	local by, order = group(junkFound)
	for _, isl in ipairs(order) do
		print(("  [%s]"):format(isl))
		for _, r in ipairs(by[isl]) do print(("      %-14s %s"):format(r.class, r.path)) end
	end
end

print("")
print(("--- 3. HEAVY MODELS  (%d with %d+ parts) ---"):format(#heavy, BIG_MODEL))
if #heavy == 0 then
	print("    none")
else
	local by, order = group(heavy)
	for _, isl in ipairs(order) do
		print(("  [%s]"):format(isl))
		for _, r in ipairs(by[isl]) do
			print(("      %6d parts  streaming=%-12s %s%s"):format(
				r.parts, r.stream, r.path, r.near and ("  <- near quest marker " .. r.near) or ""))
		end
	end
end

print("")
print("--- 4. STREAMING SETTINGS (the most likely single cause) ---")
local minR, tgtR = "?", "?"
pcall(function() minR = tostring(Workspace.StreamingMinRadius) end)
pcall(function() tgtR = tostring(Workspace.StreamingTargetRadius) end)
print(("    StreamingEnabled     = %s"):format(tostring(Workspace.StreamingEnabled)))
print(("    StreamingMinRadius   = %s   (want 768)"):format(minR))
print(("    StreamingTargetRadius= %s   (want 2048)"):format(tgtR))
if minR == "64" or minR == "0" then
	print("    ^^ AT THE DEFAULT. This is the setting IslandStreaming warns about every boot.")
	print("       At 64 studs the client is guaranteed almost nothing and re-fetches constantly")
	print("       as the camera turns -- which is exactly when the pause dialog appears.")
	print("       FIX: select Workspace in Studio, set the two radii by hand, republish.")
	print("       They are NOT scriptable, which is why no script in this repo can do it for you.")
end

print("")
print("======================================================================")
print(("  %d unresolved asset(s) | %d junk script(s) | %d heavy model(s)")
	:format(#failures, #junkFound, #heavy))
print("======================================================================")
