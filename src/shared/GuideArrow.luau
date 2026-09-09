--[[
	GuideArrow.luau  (ReplicatedStorage.GuideArrow)

	CLIENT-side shared "guide arrow" system, reused identically by Venus and Mercury.

	Shows ONE single, clear, directional arrow that floats at MID-BODY / chest height a
	few studs in front of the local player and points the way to a target NPC, updating
	its direction every frame as the player moves. It disappears (and logs) once the player
	reaches the target (within reachDistance) — i.e. when they arrive / turn in.

	Single-arrow invariant: there is exactly ONE arrow at any time across the whole game.
	`start()` always destroys any existing arrow first, so re-firing a completion event (or
	starting a different planet's arrow) can never stack a second arrow.

	All parts are client-created in a local Folder under Workspace (never replicated), so
	only this player sees the arrow and no server state is touched.

	Usage (from a client LocalScript):
		local GuideArrow = require(ReplicatedStorage.GuideArrow)
		GuideArrow.start({
			tag = "VenusGuideArrow", targetName = "VenusLabWorker", reachDistance = 8,
			getTarget = function() ... return a Model/BasePart or nil ... end,
		})
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer -- this module is required only on the client

local GuideArrow = {}

-- ===== TUNABLES =====
local ARROW_COLOR = Color3.fromRGB(80, 230, 200) -- teal-green (matches the lab/quest accent)
local FRONT_OFFSET = 6        -- studs in front of the player (toward the target) the arrow hovers
local REACH_DISTANCE_DEFAULT = 8 -- clear the arrow once the player is this close to the target
local BOB_AMP = 0.35          -- gentle vertical bob amplitude (studs)
local BOB_SPEED = 3           -- bob cycles/sec
local HEIGHT_BIAS = 0.5       -- nudge above HRP centre so it reads as chest/mid-body height

-- ===== SINGLE GLOBAL ARROW STATE (enforces "one arrow only") =====
local current = nil -- { model, conn, tag, targetName }

-- Resolve a world position for a target Instance (Model or BasePart).
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
local function buildArrowModel(colour)
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
		p.Color = colour or ARROW_COLOR
		p.Size = size
		p.CFrame = cframe
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	-- Invisible centre anchor (pivot).
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

-- Tear down the current arrow (if any) and log its removal.
local function destroyCurrent()
	local c = current
	if not c then return end
	current = nil
	if c.conn then c.conn:Disconnect() end
	if c.model then c.model:Destroy() end
	print(c.removeLog or ("[%s] arrow removed (reached %s / turned in)"):format(c.tag, c.targetName))
end

-- Public: stop/remove the current arrow (no-op if none).
-- Optional `handle` (the value returned by start): only stops if it's STILL the active arrow, so a
-- late stop() can't remove a different arrow that has since superseded it.
function GuideArrow.stop(handle)
	if handle and current ~= handle then
		return
	end
	destroyCurrent()
end

-- Public: start a single guide arrow toward a target. Destroys any existing arrow first.
-- opts = { tag, targetName, getTarget () -> Instance|nil, reachDistance?, activeLog?, removeLog?, color? }
-- color: this realm's guidance colour. The Food Realm passes its chevron green so the one arrow matches the
-- garden trail; omitted, it is the Space Realm's lab teal, so a straight copy of that file still looks right.
-- activeLog/removeLog: optional exact log strings to print on start/removal (default to the generic
-- "single mid-body arrow active …" / "arrow removed (reached …)" lines). reachDistance = 0 disables
-- proximity removal entirely (caller removes via GuideArrow.stop instead).
function GuideArrow.start(opts)
	assert(type(opts) == "table" and type(opts.getTarget) == "function", "GuideArrow.start: bad opts")
	-- Single-arrow guard: remove any existing arrow before creating a new one (prevents stacking
	-- if a completion event fires more than once, or another planet's arrow is still up).
	destroyCurrent()

	local reach = opts.reachDistance or REACH_DISTANCE_DEFAULT
	local model = buildArrowModel(opts.color)
	model.Parent = Workspace

	local handle = { model = model, tag = opts.tag, targetName = opts.targetName, removeLog = opts.removeLog }
	current = handle

	handle.conn = RunService.RenderStepped:Connect(function()
		if current ~= handle then return end -- superseded/stopped

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local tpos = targetPosition(opts.getTarget())
		if not hrp or not tpos then
			-- Player respawning, or target not streamed in yet: keep the arrow but wait.
			return
		end

		local from = hrp.Position
		local flat = Vector3.new(tpos.X - from.X, 0, tpos.Z - from.Z)
		local dist = flat.Magnitude

		-- Reached the target -> remove cleanly (and log).
		if dist <= reach then
			destroyCurrent()
			return
		end

		local dir = (dist > 1e-3) and flat.Unit or Vector3.new(0, 0, 1)
		-- Hover a few studs ahead, but never past the target.
		local front = math.clamp(FRONT_OFFSET, 2, math.max(2, dist - reach * 0.5))
		local bob = math.sin(os.clock() * BOB_SPEED) * BOB_AMP
		local pos = Vector3.new(
			from.X + dir.X * front,
			from.Y + HEIGHT_BIAS + bob, -- HRP centre is already mid-body; small bias to chest level
			from.Z + dir.Z * front
		)
		model:PivotTo(CFrame.lookAt(pos, pos + dir, Vector3.new(0, 1, 0))) -- -Z faces the target
	end)

	print(opts.activeLog or ("[%s] single mid-body arrow active → %s"):format(opts.tag, opts.targetName))
	return handle
end

return GuideArrow
