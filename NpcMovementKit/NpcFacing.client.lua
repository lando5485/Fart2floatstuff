--======================================================================
-- NpcFacing.client.lua  (LocalScript)  -- PORTABLE REALM KIT
--======================================================================
-- THE OTHER HALF OF NPC MOVEMENT: rigs that ALREADY animate.
--
-- NpcLife anchors a root and drives the whole pose. That is exactly wrong for an NPC the server
-- has given a looping idle Animation -- anchor + PivotTo every frame and you are writing the same
-- CFrame the Animator is writing, so the limbs judder or freeze outright.
--
-- This is the version for those. It touches ONE thing: yaw about the rig's fixed spot, on the
-- root only. The Animator keeps driving the limbs relative to that root, so the two never fight
-- and there is no jitter. He breathes and shifts because his idle anim says so; he turns to look
-- at you because this does.
--
-- Generalised from CandyRealm's GardenerLife, which did this for exactly one NPC (the Community
-- Garden gardener). Here it takes a LIST, so a realm with several animated NPCs needs one copy.
--
-- ===== PORTING TO ANOTHER REALM =====
-- Fill in TARGETS below: match by model name, by attribute, or both. Anything you list here
-- should ALSO carry the NoNpcLife attribute (or fall outside NpcLife's NPC_HINT) so the two
-- scripts never grab the same rig.
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ===== CONFIG =====
-- A rig qualifies if its name is in `names` OR it carries one of `attributes`.
local TARGETS = {
	names      = { Gardener = true },        -- e.g. { Gardener = true, Ranger = true }
	attributes = { "GardenerNPC" },          -- e.g. { "GardenerNPC", "AnimatedNPC" }
}

local FACE_RANGE = 42            -- studs: start tracking the player within this
local MAX_FACE   = math.rad(110) -- don't twist further than this off his resting facing
local EASE       = 4             -- higher = snappier turn

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function qualifies(model)
	if not model:IsA("Model") then return false end
	if TARGETS.names[model.Name] then return true end
	for _, attr in ipairs(TARGETS.attributes) do
		if model:GetAttribute(attr) then return true end
	end
	return false
end

local function bindNpc(model)
	local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not hrp then return end

	-- his fixed spot + resting orientation (captured once)
	local pivotPos = hrp.Position
	local restRot  = hrp.CFrame - pivotPos          -- rotation-only CFrame at the origin
	local restLook = flat(hrp.CFrame.LookVector)     -- the way he faces at rest
	if restLook.Magnitude < 1e-3 then restLook = Vector3.new(0, 0, 1) end
	restLook = restLook.Unit

	local yaw = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not hrp.Parent or not model.Parent then conn:Disconnect(); return end

		-- face the local player when near, otherwise ease back to the resting facing (yaw 0)
		local targetYaw = 0
		local char = player.Character
		local phrp = char and char:FindFirstChild("HumanoidRootPart")
		if phrp then
			local to = flat(phrp.Position - pivotPos)
			if to.Magnitude > 0.2 and to.Magnitude < FACE_RANGE then
				local d = to.Unit
				local ang = math.atan2(restLook.Z * d.X - restLook.X * d.Z,
				                       restLook.X * d.X + restLook.Z * d.Z)
				targetYaw = math.clamp(ang, -MAX_FACE, MAX_FACE)
			end
		end
		yaw = yaw + (targetYaw - yaw) * math.clamp(dt * EASE, 0, 1) -- frame-rate-independent ease

		-- rotate ONLY the (anchored) root about his fixed spot; the Animator keeps animating the
		-- limbs relative to it
		hrp.CFrame = CFrame.new(pivotPos) * CFrame.Angles(0, yaw, 0) * restRot
	end)
end

-- discover the rigs (and re-bind whenever one is rebuilt)
local bound = setmetatable({}, { __mode = "k" })
local function tryBind(model)
	if not qualifies(model) then return end
	if bound[model] then return end
	bound[model] = true
	task.spawn(function()
		for _ = 1, 100 do -- wait until the rig has replicated (root + Humanoid present)
			if (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
				and model:FindFirstChildOfClass("Humanoid") then break end
			task.wait(0.15)
		end
		if model.Parent then pcall(bindNpc, model) end
	end)
end

for _, d in ipairs(Workspace:GetDescendants()) do tryBind(d) end
Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then task.delay(0.5, function() tryBind(d) end) end
end)
-- safety re-scans during the initial load (props + rigs build a little after join)
task.spawn(function()
	for _ = 1, 30 do
		task.wait(1)
		for _, d in ipairs(Workspace:GetDescendants()) do tryBind(d) end
	end
end)

print("[NpcFacing] ready -- animated rigs turn to face you without fighting their idle anim")
