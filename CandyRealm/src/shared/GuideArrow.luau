--[[
	GuideArrow.luau  (ReplicatedStorage.Shared.GuideArrow)

	PORTED VERBATIM IN LOOK from the Space Realm (SpaceRealmStuff/src/shared/GuideArrow.luau),
	where it is the arrow Mercury and Venus both use. Same geometry, same teal neon, same
	mid-body hover, same single-arrow invariant. This realm asked for THAT arrow, so the
	tunables and the build function are left exactly as they are there rather than restyled.

	Shows ONE clear directional arrow floating at chest height a few studs in front of the
	player, pointing the way and re-aiming every frame. All parts are client-created under
	Workspace, so only this player sees it and no server state is touched.

	ONE ADDITION over the Space Realm copy: `getPosition`, returning a Vector3, alongside the
	original `getTarget`, which returns an Instance. CandyRealm's guide resolves its target to
	a world POSITION (the gardener, a food stand, a hatchable egg, an island NPC) and often has
	no Instance to hand at all -- so without this the module simply could not be driven here.

	Usage:
		local GuideArrow = require(ReplicatedStorage.Shared.GuideArrow)
		GuideArrow.start({ tag = "...", targetName = "...", getPosition = function() ... end })
		GuideArrow.stop(handle)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer -- client-only module

local GuideArrow = {}

-- ===== TUNABLES (the Space Realm's, except ARROW_COLOR -- see below) =====
-- HALF BRIGHTNESS. The Space Realm's teal is (80, 230, 200); these are those exact values
-- halved, so the hue is identical and only the luminance drops. On a Neon part the COLOUR IS
-- the brightness -- there is no separate intensity property to turn down -- so halving the
-- channels is literally how you halve a Neon part's output. It also still glows: Neon keeps
-- its bloom at any value, which a darker material would lose entirely.
local ARROW_COLOR = Color3.fromRGB(40, 115, 100) -- teal-green, 50% of the Space Realm value
local FRONT_OFFSET = 6        -- studs in front of the player the arrow hovers
local REACH_DISTANCE_DEFAULT = 8
local BOB_AMP = 0.35
local BOB_SPEED = 3
local HEIGHT_BIAS = 0.5

-- ===== SINGLE GLOBAL ARROW STATE (enforces "one arrow only") =====
local current = nil

local function targetPosition(inst)
	if not inst or not inst.Parent then return nil end
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then
		local pp = inst.PrimaryPart or inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChild("Head")
		if pp then return pp.Position end
		local ok, pivot = pcall(function() return inst:GetPivot() end)
		if ok then return pivot.Position end
	end
	return nil
end

-- Build the arrow Model (points along its own -Z). An invisible centre anchor is the
-- PrimaryPart so PivotTo() places the arrow's centre exactly where we want it.
local function buildArrowModel()
	local model = Instance.new("Model")
	model.Name = "GuideArrow"

	local function part(name, size, cframe)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.Neon
		p.Color = ARROW_COLOR
		p.Size = size
		p.CFrame = cframe
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	local anchor = part("Anchor", Vector3.new(0.1, 0.1, 0.1), CFrame.new(0, 0, 0))
	anchor.Transparency = 1

	-- Shaft along Z; the arrow points toward -Z.
	part("Shaft", Vector3.new(0.45, 0.45, 2.6), CFrame.new(0, 0, 0.7))

	-- Chevron head: two bars meeting at the tip (-Z), splayed back to form ">".
	local ARM_LEN = 1.7
	local function arm(sign)
		local rot = CFrame.Angles(0, math.rad(sign * 40), 0)
		local backDir = rot:VectorToWorldSpace(Vector3.new(0, 0, 1))
		local tip = Vector3.new(0, 0, -0.75)
		local center = tip + backDir * (ARM_LEN * 0.5)
		part("Head", Vector3.new(0.5, 0.5, ARM_LEN), CFrame.new(center) * rot)
	end
	arm(1)
	arm(-1)

	model.PrimaryPart = anchor
	return model
end

local function destroyCurrent()
	local c = current
	if not c then return end
	current = nil
	if c.conn then c.conn:Disconnect() end
	if c.model then c.model:Destroy() end
	if c.removeLog then print(c.removeLog) end
end

--[[ Stop the current arrow. Passing the handle returned by start() makes it a no-op if that
     arrow has already been superseded, so a late stop cannot remove someone else's arrow. ]]
function GuideArrow.stop(handle)
	if handle and current ~= handle then return end
	destroyCurrent()
end

--[[ Start a single guide arrow. Destroys any existing arrow first.
     opts = { tag, targetName, getTarget? () -> Instance, getPosition? () -> Vector3,
              reachDistance?, activeLog?, removeLog? }
     reachDistance = 0 disables proximity removal (the caller decides when arrival happens). ]]
function GuideArrow.start(opts)
	assert(type(opts) == "table" and (type(opts.getTarget) == "function"
		or type(opts.getPosition) == "function"), "GuideArrow.start: need getTarget or getPosition")
	destroyCurrent()

	local reach = opts.reachDistance or REACH_DISTANCE_DEFAULT
	local model = buildArrowModel()
	model.Parent = Workspace

	local handle = { model = model, tag = opts.tag, targetName = opts.targetName,
		removeLog = opts.removeLog }
	current = handle

	handle.conn = RunService.RenderStepped:Connect(function()
		if current ~= handle then return end

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local tpos = opts.getPosition and opts.getPosition() or targetPosition(opts.getTarget())
		if not hrp or not tpos then return end   -- respawning, or target not streamed in yet

		local from = hrp.Position
		local flat = Vector3.new(tpos.X - from.X, 0, tpos.Z - from.Z)
		local dist = flat.Magnitude

		if reach > 0 and dist <= reach then
			destroyCurrent()
			return
		end

		local dir = (dist > 1e-3) and flat.Unit or Vector3.new(0, 0, 1)
		local front = math.clamp(FRONT_OFFSET, 2, math.max(2, dist - reach * 0.5))
		local bob = math.sin(os.clock() * BOB_SPEED) * BOB_AMP
		local pos = Vector3.new(
			from.X + dir.X * front,
			from.Y + HEIGHT_BIAS + bob,
			from.Z + dir.Z * front
		)
		model:PivotTo(CFrame.lookAt(pos, pos + dir, Vector3.new(0, 1, 0)))
	end)

	if opts.activeLog then print(opts.activeLog) end
	return handle
end

return GuideArrow
