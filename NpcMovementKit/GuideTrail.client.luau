--======================================================================
-- GuideTrail.client.luau   (StarterPlayerScripts)   -- PORTABLE REALM KIT
--======================================================================
-- A SLEEK CHEVRON TRAIL: a flat, striped "runway" of chevron arrows laid on the ground from the
-- player's feet to whatever anyone points it at.
--
-- This is the RENDERER ONLY. It has no opinion about where you should go -- other scripts write a
-- target into one of its two slots every frame, and it draws a line to whichever slot wins. Stop
-- writing and it puts itself away. That is the whole contract, and it is what makes it reusable:
-- a realm adds a new thing worth walking to by calling a function, not by editing this file.
--
--   _G.guideTrailTo(pos)   HIGH priority. A hatchable egg, a finished quest, anything urgent.
--   _G.guideTrailClear()   drop the high-priority target.
--   _G.guideTrailNpc(pos)  LOW priority. NpcGuideArrow writes the island quest giver here.
--
-- TWO SLOTS, NOT ONE, DELIBERATELY. With a single slot whichever script wrote most recently would
-- win, so the trail flickers between an egg and an NPC rather than choosing. An egg beats an NPC
-- every time, so it gets its own slot and the comparison is decided here, once.
--
-- ===== WHY IT NEVER DESTROYS ITSELF =====
-- The CandyRealm original was written for a one-shot tutorial and destroyed its pool at the end.
-- That is fatal for anything later in the game: by the time you reach island 8's egg the trail no
-- longer exists. It stays alive and idles hidden instead. Same reason flying only HIDES it --
-- ground chevrons are meaningless mid-air, but you want them back the moment you land.
--
-- ===== PORTING TO ANOTHER REALM =====
-- Nothing in here is realm-specific. Recolour BRIGHT/EDGE to taste and drop it in.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local player     = Players.LocalPlayer

-- ===== look / motion tuning =====
local BRIGHT     = Color3.fromRGB(90, 200, 110) -- friendly green
local EDGE       = Color3.fromRGB(40, 120, 60)  -- darker outline
local SPACING    = 6    -- studs between chevrons (minimum; long routes stretch this)
local MAX_ARROWS = 26   -- most chevrons drawn at once
local STOP_DIST  = 7    -- stop the trail this many studs short of the target ("arrived")
local RANGE_CAP  = 900  -- islands are big; this only stops cross-map pointing
local prefix     = "GuideTrail"

-- ============================================================================
-- CHEVRON BUILD -- flat striped runway of arrows
-- ============================================================================
local rayParams = RaycastParams.new(); rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function part(model, name, sx, sy, sz, color, refl, cf)
	local p = Instance.new("Part"); p.Name = name; p.Size = Vector3.new(sx, sy, sz); p.Color = color
	p.Material = Enum.Material.SmoothPlastic; p.Reflectance = refl or 0
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.LeftSurface = Enum.SurfaceType.Smooth; p.RightSurface = Enum.SurfaceType.Smooth
	p.FrontSurface = Enum.SurfaceType.Smooth; p.BackSurface = Enum.SurfaceType.Smooth
	p.CFrame = cf; p.Parent = model; return p
end
-- one chevron ">" pointing -Z (forward), lying flat (thin in Y): darker edge base + glossy bright top
local function buildChevron()
	local m = Instance.new("Model"); m.Name = prefix .. "Chevron"
	local root = part(m, "Root", 0.2, 0.2, 0.2, BRIGHT, 0, CFrame.new()); root.Transparency = 1; m.PrimaryPart = root
	local L, W, T, ANG = 2.6, 0.72, 0.22, math.rad(42)
	local front = CFrame.new(0, 0, -0.9) -- the chevron POINT
	part(m, "EdgeR", W + 0.20, T * 0.65, L + 0.20, EDGE, 0, front * CFrame.Angles(0,  ANG, 0) * CFrame.new(0, -0.03, L / 2))
	part(m, "EdgeL", W + 0.20, T * 0.65, L + 0.20, EDGE, 0, front * CFrame.Angles(0, -ANG, 0) * CFrame.new(0, -0.03, L / 2))
	part(m, "ArmR",  W, T, L, BRIGHT, 0.14,                front * CFrame.Angles(0,  ANG, 0) * CFrame.new(0,  0.04, L / 2))
	part(m, "ArmL",  W, T, L, BRIGHT, 0.14,                front * CFrame.Angles(0, -ANG, 0) * CFrame.new(0,  0.04, L / 2))
	m.Parent = Workspace
	return m
end
local pool = {}
local function getNode(i) if not pool[i] then pool[i] = buildChevron() end; return pool[i] end
local function setShown(nd, on)
	for _, p in ipairs(nd:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Root" then p.Transparency = on and 0 or 1 end
	end
end
local function hideFrom(n) for i = n, #pool do if pool[i] then setShown(pool[i], false) end end end

-- ============================================================================
-- THE TWO SLOTS
-- ============================================================================
local override  = nil    -- HIGH priority (eggs, urgent objectives)
local npcTarget = nil    -- LOW priority (the island quest giver you have not met)

_G.guideTrailTo    = function(pos) override  = (typeof(pos) == "Vector3") and pos or nil end
_G.guideTrailClear = function()    override  = nil end
_G.guideTrailNpc   = function(pos) npcTarget = (typeof(pos) == "Vector3") and pos or nil end

RunService.RenderStepped:Connect(function()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then hideFrom(1); return end

	-- Mid-flight there is no ground to lay chevrons on. HIDE, do not destroy.
	--
	-- BUT NOT ON THE FLAG ALONE. _G.isFlying belongs to the flight system and only has to be right
	-- for flight; if it lingers true after a landing or a teleport, this returns every frame and the
	-- trail is simply gone, with nothing anywhere saying why. So the flag hides the trail only when
	-- the player is ALSO off the ground.
	if _G.isFlying then
		local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -14, 0), rayParams)
		if not hit then hideFrom(1); return end
	end

	local tpos = override or npcTarget
	if not tpos then hideFrom(1); return end

	local d = tpos - hrp.Position
	local flat = Vector3.new(d.X, 0, d.Z)
	local dist = flat.Magnitude
	if dist <= STOP_DIST then hideFrom(1); return end
	if dist > RANGE_CAP then hideFrom(1); return end
	local dir = flat.Unit

	-- exclude the player + every chevron so the ground ray doesn't hit them
	local excl = { char }; for _, nd in ipairs(pool) do excl[#excl + 1] = nd end
	rayParams.FilterDescendantsInstances = excl

	-- SPREAD THEM OVER THE WHOLE ROUTE. At a fixed 6 studs apart, 26 chevrons cover 156 studs --
	-- across an island that is a stub of a trail pointing off into nothing, with no sense of how
	-- much further there is to go. Stretching the gap to fit means the line always runs from your
	-- feet to the target, and how far apart they sit tells you how far is left.
	local maxAlong = dist - STOP_DIST
	local step = math.max(SPACING, maxAlong / MAX_ARROWS)
	local placed = 0
	for i = 1, MAX_ARROWS do
		local along = i * step
		if along > maxAlong then break end
		placed += 1
		local px = hrp.Position.X + dir.X * along
		local pz = hrp.Position.Z + dir.Z * along
		local hit = Workspace:Raycast(Vector3.new(px, hrp.Position.Y + 14, pz), Vector3.new(0, -240, 0), rayParams)
		local gy = (hit and hit.Position.Y) or (hrp.Position.Y - 2.5)
		local nd = getNode(placed)
		-- FLAT on the ground (Y up), pointing toward the target (-Z = dir)
		local p0 = Vector3.new(px, gy + 0.12, pz)
		pcall(function() nd:PivotTo(CFrame.lookAt(p0, p0 + dir)) end)
		-- gentle pulse that FLOWS toward the target
		pcall(function() nd:ScaleTo(1 + 0.10 * math.sin(os.clock() * 5 - i * 0.8)) end)
		setShown(nd, true)
	end
	hideFrom(placed + 1)
end)

print("[GuideTrail] loaded -- _G.guideTrailTo(pos) high priority, _G.guideTrailNpc(pos) low")
