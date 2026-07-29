--======================================================================
-- DinoIslandArrow.client.luau   -- PUT THIS IN THE *DINO REALM* PLACE
-- (StarterPlayer > StarterPlayerScripts, as a LocalScript.)
--======================================================================
-- THE LITTLE ARROW THAT GUIDES YOU TO EACH ISLAND.
--
-- A big bold WHITE up-arrow with a thick black outline. It tracks the island you
-- are heading for: it rotates to point at it, and when the island is off-screen or
-- behind you it clamps to the edge of the screen and keeps pointing. A small name
-- label sits under it.
--
-- Copied from the main game's NEXT-ISLAND POINTER (WorldClient.client.lua) with the
-- projection + edge-clamp maths kept verbatim, so it looks and moves identically.
-- The only thing rewritten is HOW IT PICKS A TARGET, because the main game reads a
-- hardcoded island table and this has to work in a realm it knows nothing about.
--
-- ===== SETUP: PICK ONE (they are tried in this order) =====
--   1. TARGET_TAG   -- tag each island with the CollectionService tag "DinoIsland"
--                      (Studio: select the island model/part -> Tags -> add it).
--                      RECOMMENDED: no code edit, and it survives renames.
--   2. ISLANDS      -- fill in the explicit list below with {x,y,z,name} entries.
--                      Use this if your islands are at known fixed heights.
--   3. NAME_PREFIX  -- fallback: any top-level Workspace model whose name starts
--                      with "island" (matched loosely -- see norm()).
--
-- Nothing else needs changing. If none of the three finds anything, the arrow
-- simply stays hidden rather than pointing at the origin.
--======================================================================

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

--======================================================================
-- CONFIG
--======================================================================
local CONFIG = {
	-- ---- target sources (tried in order) ----
	TARGET_TAG   = "DinoIsland", -- 1. CollectionService tag on your island models/parts
	ISLANDS      = {             -- 2. explicit list; leave empty to skip
		-- { x = 0,   y = 150,  z = 0,  name = "Fossil Flats" },
		-- { x = 120, y = 790,  z = 60, name = "Raptor Ridge" },
	},
	NAME_PREFIX  = "island",     -- 3. fallback: top-level models whose name starts with this

	-- ---- behaviour ----
	CLIMBING     = true,  -- true: only ever point at islands ABOVE you (a climbing game --
	                      -- you never want to be sent back down to one you already cleared).
	                      -- false: point at the nearest island in any direction.
	HIDE_WITHIN  = 40,    -- hide once you are this close (studs) -- you can see it by now
	SHOW_NAME    = true,  -- show the island's name under the arrow
	NAME_GATE    = true,  -- only reveal the name once the player has REACHED that island
	                      -- (reads the "HighestIsland" attribute; see the note in nameFor).
	EDGE_MARGIN  = 60,    -- px in from the screen edge the clamped arrow stops at
	UPDATE_HZ    = 10,    -- refreshes per second (the main game uses 10)
	RESCAN       = 3,     -- seconds between full island searches (models are cached between)
}

--======================================================================
-- HUD -- identical build to the main game's pointer, do not restyle
--======================================================================
local function mkStroke(p, col, t)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = p; return s
end
local function mkLabel(p, props)
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1
	for k, v in pairs(props) do l[k] = v end
	l.Parent = p; return l
end
local function mkFrame(p, props)
	local f = Instance.new("Frame")
	for k, v in pairs(props) do f[k] = v end
	f.Parent = p; return f
end

local navSg = Instance.new("ScreenGui")
navSg.Name = "DinoNavGui"; navSg.ResetOnSpawn = false
-- IgnoreGuiInset is deliberately LEFT OFF (the main game leaves it default-false too).
-- Camera:WorldToScreenPoint returns coordinates that already EXCLUDE the topbar inset, so
-- it only lines up with an inset-respecting ScreenGui. Turning IgnoreGuiInset on shifts
-- the whole arrow ~36px off from where the island actually is.
navSg.Parent = player:WaitForChild("PlayerGui")

-- navFrame is just a transparent host that gets positioned; the arrow inside it rotates.
local navFrame = mkFrame(navSg, {
	Size = UDim2.new(0, 54, 0, 54), Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false,
})
local navArrow = mkLabel(navFrame, {
	Text = "\xe2\x86\x91", Font = Enum.Font.GothamBold, TextSize = 48,
	TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Center,
})
local navArrowStroke = mkStroke(navArrow, Color3.new(0, 0, 0), 5)
navArrowStroke.LineJoinMode = Enum.LineJoinMode.Round -- thick black outline

local navName = mkLabel(navSg, {
	Text = "", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Color3.new(1, 1, 1),
	Size = UDim2.new(0, 120, 0, 16), AnchorPoint = Vector2.new(0.5, 0),
	TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
})
mkStroke(navName, Color3.new(0, 0, 0), 1)

--======================================================================
-- TARGETS
--
-- Names in a real place carry stray spaces, underscores and casing ("Island_3_",
-- "island 3", "Island3"), so every name comparison goes through norm() first. Not
-- normalising is the exact class of mismatch that has silently broken guidance
-- scripts in this codebase before.
--======================================================================
local function norm(s)
	return (tostring(s):lower():gsub("[%s_%-]", ""))
end

local function pivotOf(inst)
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then
		local ok, cf = pcall(function() return inst:GetPivot() end)
		if ok and cf then return cf.Position end
	end
	return nil
end

-- Prefer an explicit IslandName attribute, else the instance name.
local function labelOf(inst)
	if not inst then return "" end
	local a = inst:GetAttribute("IslandName")
	if a then return tostring(a) end
	return inst.Name
end

-- Full island sweep -> { {pos = Vector3, name = string, num = number?}, ... }
-- Cached; re-run every CONFIG.RESCAN seconds because island models stream in late
-- and a single look at spawn time finds nothing on most of the map.
local cache, cacheAt = {}, -math.huge

local function scanIslands()
	local out = {}

	-- 1. tagged instances
	if CONFIG.TARGET_TAG and CONFIG.TARGET_TAG ~= "" then
		for _, inst in ipairs(CollectionService:GetTagged(CONFIG.TARGET_TAG)) do
			if inst:IsDescendantOf(Workspace) then
				local p = pivotOf(inst)
				if p then
					out[#out + 1] = {
						pos = p, name = labelOf(inst),
						num = tonumber(inst:GetAttribute("IslandNumber")) or tonumber(inst.Name:match("%d+")),
					}
				end
			end
		end
	end
	if #out > 0 then return out end

	-- 2. explicit config list
	for i, isl in ipairs(CONFIG.ISLANDS) do
		out[#out + 1] = {
			pos = Vector3.new(isl.x or 0, isl.y or 0, isl.z or 0),
			name = isl.name or ("Island " .. i),
			num = isl.num or i,
		}
	end
	if #out > 0 then return out end

	-- 3. top-level models named like islands
	local prefix = norm(CONFIG.NAME_PREFIX or "")
	if prefix ~= "" then
		for _, m in ipairs(Workspace:GetChildren()) do
			if m:IsA("Model") and norm(m.Name):sub(1, #prefix) == prefix then
				local p = pivotOf(m)
				if p then
					out[#out + 1] = { pos = p, name = labelOf(m), num = tonumber(m.Name:match("%d+")) }
				end
			end
		end
	end
	return out
end

local function islands(now)
	if now - cacheAt > CONFIG.RESCAN then
		cacheAt = now
		cache = scanIslands()
	end
	return cache
end

-- WHICH ISLAND ARE WE POINTING AT?
--
-- In a climbing realm the answer is always "the lowest one still above me" -- never
-- the nearest, because the nearest is usually the one under your feet, and never a
-- fixed next-index, because a player who skipped ahead would be sent backwards.
-- Height decides it, so this needs no progression data and cannot desync from it.
local function pickTarget(fromPos, now)
	local list = islands(now)
	local best, bestScore
	for _, isl in ipairs(list) do
		local above = isl.pos.Y - fromPos.Y
		local score
		if CONFIG.CLIMBING then
			-- only islands meaningfully above us; closest-above wins
			if above > CONFIG.HIDE_WITHIN then score = above end
		else
			score = (isl.pos - fromPos).Magnitude
		end
		if score and (not bestScore or score < bestScore) then best, bestScore = isl, score end
	end
	return best
end

-- NAME REVEAL: don't spoil an island the player has not been to yet. The main game
-- gates this on a server-set per-player "HighestIsland" attribute. If your realm does
-- not set that attribute, this returns the name straight away -- the gate simply does
-- nothing rather than hiding every label. Set NAME_GATE = false to always show names.
local function nameFor(isl)
	if not (CONFIG.SHOW_NAME and isl and isl.name ~= "") then return nil end
	if not CONFIG.NAME_GATE then return isl.name end
	local highest = player:GetAttribute("HighestIsland")
	if highest == nil then return isl.name end       -- realm doesn't track it -> no gate
	if isl.num and isl.num > highest then return nil end -- not been there yet: arrow only, no label
	return isl.name
end

--======================================================================
-- LOOP -- projection + edge-clamp + rotation, copied verbatim from the main game
--======================================================================
local acc = 0
RunService.RenderStepped:Connect(function(dt)
	acc = acc + dt
	if acc < (1 / CONFIG.UPDATE_HZ) then return end
	acc = 0

	pcall(function()
		local Camera = Workspace.CurrentCamera
		local char   = player.Character
		local hrp    = char and char:FindFirstChild("HumanoidRootPart")
		if not (Camera and hrp) then navFrame.Visible = false; navName.Visible = false; return end

		local isl = pickTarget(hrp.Position, os.clock())
		if not isl then navFrame.Visible = false; navName.Visible = false; return end

		local target3D = isl.pos
		if (target3D - hrp.Position).Magnitude <= CONFIG.HIDE_WITHIN then
			navFrame.Visible = false; navName.Visible = false; return
		end

		local vp = Camera.ViewportSize
		local cx, cy = vp.X / 2, vp.Y / 2
		local screenPos = Camera:WorldToScreenPoint(target3D)
		local dx, dy = screenPos.X - cx, screenPos.Y - cy
		local margin = CONFIG.EDGE_MARGIN
		local maxX, maxY = cx - margin, cy - margin
		local ex, ey

		if screenPos.Z > 0 and math.abs(dx) < maxX and math.abs(dy) < maxY then
			-- on screen and in front: sit right on the target
			ex, ey = screenPos.X, screenPos.Y
		else
			-- Behind the camera flips the projection, so mirror it before the edge maths --
			-- without this the arrow points the opposite way whenever you turn your back.
			if screenPos.Z < 0 then dx, dy = -dx, -dy end
			if math.abs(dx) * maxY >= math.abs(dy) * maxX then
				local sign = dx >= 0 and 1 or -1
				ex = cx + sign * maxX
				ey = cy + dy * (maxX / math.max(math.abs(dx), 0.001))
			else
				local sign = dy >= 0 and 1 or -1
				ey = cy + sign * maxY
				ex = cx + dx * (maxY / math.max(math.abs(dy), 0.001))
			end
		end

		navFrame.Position = UDim2.new(0, ex, 0, ey)
		navArrow.Rotation = math.deg(math.atan2(dy, dx)) + 90
		navFrame.Visible  = true

		local label = nameFor(isl)
		if label then
			navName.Position = UDim2.new(0, ex, 0, ey + 26)
			navName.Text     = label
			navName.Visible  = true
		else
			navName.Visible = false
		end
	end)
end)

-- If nothing is ever found, say so once rather than leaving a silently blank screen.
task.delay(8, function()
	if #cache == 0 then
		warn("[DinoArrow] no islands found -- tag them '" .. tostring(CONFIG.TARGET_TAG)
			.. "', or fill in CONFIG.ISLANDS, or name your island models '"
			.. tostring(CONFIG.NAME_PREFIX) .. "...'")
	end
end)

print("[DinoArrow] Dino Realm island pointer ready (tag your islands '" .. CONFIG.TARGET_TAG .. "').")
