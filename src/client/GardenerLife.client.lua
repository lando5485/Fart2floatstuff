--======================================================================
-- GardenerLife.client.lua  (LocalScript)  -- makes the Community Garden Gardener turn toward YOU, locally.
--======================================================================
-- The Gardener is now a REAL R15 avatar (model named "Gardener", tagged GardenerNPC, with a Humanoid). The server
-- anchors only his HumanoidRootPart and plays a looping IDLE Animation (so his body has natural motion). This script
-- adds the only client-side touch: smoothly rotating him (yaw about his fixed spot) to FACE the local player when
-- they're nearby, easing back to his resting facing otherwise. It ONLY moves the root -- the idle animation drives the
-- limbs via the Animator -- so the two never fight, and there's no jitter. Cosmetic / local only; never touches gameplay.
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local player = Players.LocalPlayer

local FACE_RANGE = 42            -- studs: start tracking the player within this
local MAX_FACE   = math.rad(110) -- don't twist further than this off his resting facing

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function bindGardener(model)
	local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not hrp then return end

	-- his fixed spot + resting orientation (captured once)
	local pivotPos = hrp.Position
	local restRot  = hrp.CFrame - pivotPos            -- rotation-only CFrame at the origin (his rest facing)
	local restLook = flat(hrp.CFrame.LookVector)       -- the way he faces at rest (down-path)
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
				local ang = math.atan2(restLook.Z * d.X - restLook.X * d.Z, restLook.X * d.X + restLook.Z * d.Z)
				targetYaw = math.clamp(ang, -MAX_FACE, MAX_FACE)
			end
		end
		yaw = yaw + (targetYaw - yaw) * math.clamp(dt * 4, 0, 1) -- smooth, frame-rate-independent ease

		-- rotate ONLY the (anchored) root about his fixed spot; the Animator keeps animating the limbs relative to it
		hrp.CFrame = CFrame.new(pivotPos) * CFrame.Angles(0, yaw, 0) * restRot
	end)
end

-- discover the gardener (and re-bind whenever the garden rebuilds a fresh one)
local bound = setmetatable({}, { __mode = "k" })
local function tryBind(model)
	if not (model:IsA("Model") and model.Name == "Gardener" and model:GetAttribute("GardenerNPC")) then return end
	if bound[model] then return end
	bound[model] = true
	task.spawn(function()
		for _ = 1, 100 do -- wait until the rig has replicated (root + Humanoid present)
			if (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) and model:FindFirstChildOfClass("Humanoid") then break end
			task.wait(0.15)
		end
		if model.Parent then pcall(bindGardener, model) end
	end)
end

for _, d in ipairs(Workspace:GetDescendants()) do tryBind(d) end
Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") and d.Name == "Gardener" then task.delay(0.5, function() tryBind(d) end) end
end)
-- a few safety re-scans during the initial load (the garden + rig build a little after join)
task.spawn(function()
	for _ = 1, 30 do
		task.wait(1)
		for _, d in ipairs(Workspace:GetDescendants()) do tryBind(d) end
	end
end)
