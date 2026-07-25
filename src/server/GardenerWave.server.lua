-- ============================================================================================================
-- NPC WAVES  (server)   -- the Gardener AND the Farmer wave at you
--
-- Both wave with the LEFT arm, on the same rules: when you walk up to them, and when the intro's camera settles
-- on them. Written ONCE and driven from a list, not copy-pasted per NPC -- two hand-maintained copies of a wave
-- is exactly how you end up with one of them subtly out of sync six months later.
--
-- ===== WHY A MOTOR6D AND NOT AN ANIMATION =====
-- The obvious answer is "play Roblox's stock wave animation". It is the wrong one: every stock wave is RIGHT-handed,
-- and the Gardener's bird lands on his LEFT shoulder. Waving the other arm would look like a different character.
--
-- So the wave is driven straight from the LEFT SHOULDER Motor6D. A joint's final pose is
--     C0 * Transform * C1
-- and the idle ANIMATION only writes Transform. That means nudging C0 LAYERS the wave ON TOP of the idle rather
-- than replacing it -- they keep breathing and shifting their weight while they wave, instead of freezing into a
-- pose. Restoring the captured C0 afterwards puts the arm back exactly where it was.
--
-- ===== THE BIRD IS FINE =====
-- GardenBird perches using an offset from the Gardener's HumanoidRootPart -- NOT from his arm part. Rotating the
-- shoulder swings the forearm and hand through a big arc while the joint itself barely moves, so the bird sits
-- undisturbed on his shoulder while he waves underneath it. The two systems never touch the same instance.
--
-- Server-side on purpose: every player sees them wave, not just the one who triggered it.
-- ============================================================================================================

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Lets the CLIENT ask a specific NPC to wave. The garden intro needs this: during the cinematic the camera is on
-- the NPC but the player's character is still standing back at spawn, so the proximity check below can never fire
-- -- they would stand stone-still through the one scene that is entirely about them.
--
-- Safe to expose. The handler grants nothing, and the cooldown and "already waving" guards both still apply, so
-- the worst a spammed remote can do is ask a man to wave at a rate he was going to refuse anyway.
local waveRequest = ReplicatedStorage:FindFirstChild("GardenerWaveRequest")
if not waveRequest then
	waveRequest = Instance.new("RemoteEvent")
	waveRequest.Name = "GardenerWaveRequest"
	waveRequest.Parent = ReplicatedStorage
end

-- ===== TUNING =====
local NEAR_DIST   = 16     -- studs: how close you must get before they notice you
local COOLDOWN    = 8      -- seconds before the same NPC waves at the same person again (friendly, not manic)
local WAVE_SECS   = 2.2    -- how long one wave lasts
local LIFT_DEG    = 105    -- how far the arm comes up and out from the side
local SWING_DEG   = 22     -- how far the wave swings either side of that
local SWING_SPEED = 9      -- radians/sec of the swing -- roughly 3 waves in WAVE_SECS

-- If they wave INTO their own body instead of out to the side, flip this to 1. The sign of a shoulder rotation
-- depends on the rig, and R6 and R15 do not agree -- rather than guess, it is one number to flip.
local WAVE_SIGN   = -1

-- ===== WHO WAVES =====
-- Each finder returns the NPC's Model. The Gardener's lookup mirrors GardenBird's exactly, so the two can never
-- disagree about which model is "the Gardener".
local NPCS = {
	{
		key = "Gardener",
		find = function()
			local build = Workspace:FindFirstChild("CommunityGardenBuild", true)
			if build then
				local props = build:FindFirstChild("GardenProps")
				local g = props and props:FindFirstChild("Gardener")
				if g and g:IsA("Model") then return g end
				for _, d in ipairs(build:GetDescendants()) do
					if d:IsA("Model") and d:GetAttribute("GardenerNPC") then return d end
				end
			end
			local byName = Workspace:FindFirstChild("Gardener", true)
			if byName and byName:IsA("Model") then return byName end
			return nil
		end,
	},
	{
		key = "Farmer", -- the tutorial NPC by the bean/food stand on Bean Farm
		find = function()
			-- FarmerNPC.server.lua clones him into Workspace.TutorialNPCs and names him "FarmerNPC" -- the old
			-- lookup searched for "Farmer" and so never found him (that name matched something else, or nothing).
			local c = Workspace:FindFirstChild("TutorialNPCs")
			local f = c and c:FindFirstChild("FarmerNPC")
			if f and f:IsA("Model") then return f end
			f = Workspace:FindFirstChild("FarmerNPC", true) or Workspace:FindFirstChild("Farmer", true)
			if f and f:IsA("Model") and f.Name ~= "Farmer2" then return f end -- never the scarecrow
			return nil
		end,
	},
}

-- The LEFT shoulder joint. R15 and R6 name it and park it in completely different places, and the rig is chosen at
-- runtime, so both are handled rather than assumed.
local function findLeftShoulder(npc)
	local lua = npc:FindFirstChild("LeftUpperArm")            -- R15
	local m = lua and lua:FindFirstChild("LeftShoulder")
	if m and m:IsA("Motor6D") then return m, "R15" end
	local torso = npc:FindFirstChild("Torso")                 -- R6
	m = torso and torso:FindFirstChild("Left Shoulder")
	if m and m:IsA("Motor6D") then return m, "R6" end
	for _, d in ipairs(npc:GetDescendants()) do               -- last resort
		if d:IsA("Motor6D") and d.Name:lower():gsub("%s", "") == "leftshoulder" then return d, "?" end
	end
	return nil, nil
end

-- ===== ONE NPC'S WAVE =====
-- Each NPC gets its OWN state: its own motor, its own captured rest pose, its own "am I mid-wave" flag and its own
-- per-player cooldowns. Sharing any of those would make one NPC's wave cancel the other's.
local function runNPC(spec)
	local npc, hrp
	for _ = 1, 360 do -- the garden (and the NPCs in it) build asynchronously, long after this script starts
		npc = spec.find()
		hrp = npc and (npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart)
		if npc and hrp then break end
		task.wait(0.5)
	end
	if not (npc and hrp) then
		warn(("[Wave] %s not found -- he will not wave"):format(spec.key))
		return
	end

	local motor, rig = findLeftShoulder(npc)
	if not motor then
		warn(("[Wave] %s has no LEFT shoulder Motor6D -- cannot wave."
			.. " (Looked for R15 LeftUpperArm.LeftShoulder and R6 Torso['Left Shoulder'].)"):format(spec.key))
		return
	end

	-- Capture the REST pose ONCE. Every wave is an offset from this and every wave ends by restoring it, so the arm
	-- can never creep a little further out with each wave until he is stuck holding it up.
	local baseC0 = motor.C0
	print(("[Wave] %s ready -- %s rig, LEFT arm, within %d studs"):format(spec.key, rig, NEAR_DIST))

	local waving = false
	local lastWave = {} -- [player] = os.clock() of this NPC's last wave AT THEM

	local function wave()
		if waving then return end
		waving = true
		local t0 = os.clock()
		while os.clock() - t0 < WAVE_SECS do
			local t = os.clock() - t0
			-- ease the arm UP over the first 0.25s and back DOWN over the last 0.25s, so it does not snap
			local ease = math.clamp(t / 0.25, 0, 1) * math.clamp((WAVE_SECS - t) / 0.25, 0, 1)
			local lift  = math.rad(LIFT_DEG) * ease
			local swing = math.rad(SWING_DEG) * ease * math.sin(t * SWING_SPEED)
			motor.C0 = baseC0 * CFrame.Angles(0, 0, WAVE_SIGN * (lift + swing))
			RunService.Heartbeat:Wait()
		end
		motor.C0 = baseC0 -- back to rest, exactly
		waving = false
	end

	-- THE INTRO ASKS. Same cooldown and same "already waving" guard as walking up to him -- the remote is a
	-- different TRIGGER, not a different rule, so it cannot make him wave faster than a nearby player could.
	waveRequest.OnServerEvent:Connect(function(p, who)
		if who ~= spec.key then return end -- this request is for the other NPC
		if waving or not motor then return end
		local now = os.clock()
		if (now - (lastWave[p] or -math.huge)) < COOLDOWN then return end
		lastWave[p] = now
		print(("[Wave] %s waving for %s (intro)"):format(spec.key, p.Name))
		task.spawn(wave)
	end)

	-- PROXIMITY: someone walked up to him.
	while true do
		task.wait(0.25) -- proximity does not need checking every frame
		if not (npc.Parent and hrp.Parent) then
			-- a rebuild replaced him -- re-find rather than waving at a destroyed model forever
			npc = spec.find()
			hrp = npc and (npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart)
			if npc and hrp then
				motor = findLeftShoulder(npc)
				if motor then baseC0 = motor.C0 end
			end
			task.wait(1)
		elseif not waving and motor then
			local now = os.clock()
			for _, p in ipairs(Players:GetPlayers()) do
				local ch = p.Character
				local ph = ch and ch:FindFirstChild("HumanoidRootPart")
				if ph and (ph.Position - hrp.Position).Magnitude <= NEAR_DIST then
					if (now - (lastWave[p] or -math.huge)) >= COOLDOWN then
						lastWave[p] = now
						print(("[Wave] %s waving at %s"):format(spec.key, p.Name))
						task.spawn(wave)
						break -- one wave serves everyone standing there; he does not wave once per person
					end
				end
			end
		end
	end
end

for _, spec in ipairs(NPCS) do
	task.spawn(runNPC, spec)
end
