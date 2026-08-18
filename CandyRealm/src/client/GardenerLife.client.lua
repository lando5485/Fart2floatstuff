--======================================================================
-- GardenerLife.client.lua  (LocalScript)  -- makes the Community Garden Gardener turn toward YOU, locally.
--======================================================================
-- The Gardener is now a REAL R15 avatar (model named "Gardener", tagged GardenerNPC, with a Humanoid). The server
-- anchors only his HumanoidRootPart and plays a looping IDLE Animation (so his body has natural motion). This script
-- adds the client-side touches: smoothly rotating him (yaw about his fixed spot) to FACE the local player when
-- they're nearby, easing back to his resting facing otherwise, and raising his LEFT hand in a wave while you are
-- stood with him -- the same wave the island quest givers do, from Shared.NpcWave, so the two never drift apart.
--
-- The yaw ONLY moves the root and the wave ONLY offsets the shoulder joint's C0, while the idle animation drives the
-- limbs through Transform. All three write different things, so nothing fights and there's no jitter. Cosmetic /
-- local only; never touches gameplay.
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local NpcWave = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcWave"))

local FACE_RANGE = 42            -- studs: start tracking the player within this
local WAVE_RANGE = 30            -- studs: the hand comes up inside this, so he is already facing you first
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

	-- his left shoulder joint + its untouched rest offset, captured once: reading C0 live would
	-- compound last frame's wave into this frame's and wind the arm round in circles
	local shoulder = NpcWave.leftShoulder(model)
	local shoulderC0 = shoulder and shoulder.C0 or nil
	local phase = math.random() * 6.28   -- so he is not in lockstep with the island NPCs

	local yaw, wave, armRetry = 0, 0, 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not hrp.Parent or not model.Parent then conn:Disconnect(); return end

		-- face the local player when near, otherwise ease back to the resting facing (yaw 0)
		local targetYaw, near = 0, false
		local char = player.Character
		local phrp = char and char:FindFirstChild("HumanoidRootPart")
		if phrp then
			local to = flat(phrp.Position - pivotPos)
			near = to.Magnitude < WAVE_RANGE
			if to.Magnitude > 0.2 and to.Magnitude < FACE_RANGE then
				local d = to.Unit
				local ang = math.atan2(restLook.Z * d.X - restLook.X * d.Z, restLook.X * d.X + restLook.Z * d.Z)
				targetYaw = math.clamp(ang, -MAX_FACE, MAX_FACE)
			end
		end
		yaw = yaw + (targetYaw - yaw) * math.clamp(dt * 4, 0, 1) -- smooth, frame-rate-independent ease

		-- rotate ONLY the (anchored) root about his fixed spot; the Animator keeps animating the limbs relative to it
		hrp.CFrame = CFrame.new(pivotPos) * CFrame.Angles(0, yaw, 0) * restRot

		-- wave the left hand while you are with him. The rig can replicate its arms after the
		-- model, so keep looking for the joint until one turns up.
		local now = os.clock()
		if not shoulder and now >= armRetry then
			armRetry = now + 0.5
			shoulder = NpcWave.leftShoulder(model)
			shoulderC0 = shoulder and shoulder.C0 or nil
		end
		wave = NpcWave.ease(wave, near and 1 or 0, dt)
		if shoulder then
			if shoulder.Parent then
				NpcWave.poseShoulder(shoulder, shoulderC0, NpcWave.angle(wave, now, phase))
			else
				shoulder, shoulderC0 = nil, nil
			end
		end
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
