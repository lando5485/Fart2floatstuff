--======================================================================
-- NpcWave.luau  (ModuleScript -> ReplicatedStorage.Shared)  -- CandyRealm
--======================================================================
-- ONE LEFT-HANDED WAVE, shared by everything that animates an NPC, because there are
-- two scripts that pose NPCs (NpcLife for the island quest givers, GardenerLife for the
-- Community Garden gardener) and a wave that is written twice is a wave that drifts:
-- one arm ends up raised further, or swinging at a different speed, and the islands stop
-- looking like they belong to the same game.
--
-- IT POSES THE SHOULDER JOINT, NOT THE ARM PART. Every Studio-placed NPC here is a real
-- Humanoid rig, so the arm is driven by a Motor6D and writing the arm's CFrame directly
-- would be overwritten by the rig the same frame. The joint is posed through C0 (the
-- joint's REST offset) rather than Transform, because Transform is what an Animator
-- writes: an NPC with a looping idle keeps its idle, and the raised arm rides on top of
-- it instead of fighting it.
--
-- WHY THE ROTATION IS APPLIED IN TORSO SPACE. C0 lives in Part0's frame (the torso), but
-- it also carries the shoulder OFFSET, and the R6 and R15 rigs bake different yaws into
-- it (+/-90 degrees, mirrored per side). Multiplying a rotation onto the END of C0 would
-- therefore spin the arm about whichever axis that rig happened to bake in -- forward on
-- one rig, outward on the other. Rotating about the shoulder POINT instead
--       C0 = translate(shoulder) * R * rotationOf(C0)
-- puts R in the torso's own frame on every rig: +X is the NPC's right, +Y up, -Z forward.
-- The arm hangs at (0,-1,0) from the shoulder, so a rotation about the torso's +Z axis
-- lifts it sideways, and a NEGATIVE angle lifts the LEFT arm (a point below the pivot
-- swings toward -X, which is the NPC's left). Hence RAISE being negative -- flip its sign
-- and you have written a right-handed wave.
--======================================================================

local NpcWave = {}

-- -150 degrees puts the forearm up and out at about 30 degrees off vertical -- an open
-- "hello", not a salute (-180) and not a shrug (-90).
NpcWave.RAISE = math.rad(-150)

-- The wave itself: the arm rocks about RAISE rather than travelling anywhere. 17 degrees
-- at ~1.2 waves/second reads as friendly; much faster reads as frantic, much wider looks
-- like the NPC is signalling for help.
NpcWave.SWING       = math.rad(17)
NpcWave.SWING_SPEED = 7.5

-- How fast the wave fades in and out (per second, exponential ease). Snapping the arm to
-- fully raised the instant you cross the range is the single thing that makes an NPC read
-- as a trigger volume instead of a person.
NpcWave.EASE = 4.5

local function norm(s)
	return (tostring(s):lower():gsub("[%s_%-]", ""))
end

-- The LEFT shoulder Motor6D: R6 keeps it as "Left Shoulder" under the Torso, R15 as
-- "LeftShoulder" under the LeftUpperArm. The descendant sweep is the fallback for rigs
-- that were assembled by hand in Studio and do not have the standard part names.
function NpcWave.leftShoulder(model: Instance): Motor6D?
	local torso = model:FindFirstChild("Torso")
	if torso then
		local j = torso:FindFirstChild("Left Shoulder")
		if j and j:IsA("Motor6D") then return j end
	end
	local upper = model:FindFirstChild("LeftUpperArm")
	if upper then
		local j = upper:FindFirstChild("LeftShoulder")
		if j and j:IsA("Motor6D") then return j end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and norm(d.Name) == "leftshoulder" then return d end
	end
	return nil
end

-- Ease `amount` (0 = arm down, 1 = waving) toward `want` for a frame of `dt`. Written as
-- a helper so both callers fade at the same rate and neither has to remember the clamp.
function NpcWave.ease(amount: number, want: number, dt: number): number
	return amount + (want - amount) * math.clamp(dt * NpcWave.EASE, 0, 1)
end

-- The shoulder angle for a given wave amount. `phase` is a per-NPC offset so a row of
-- them does not wave in lockstep like a chorus line.
function NpcWave.angle(amount: number, clock: number, phase: number?): number
	local a = math.clamp(amount or 0, 0, 1)
	if a <= 0.001 then return 0 end
	return a * (NpcWave.RAISE + math.sin(clock * NpcWave.SWING_SPEED + (phase or 0)) * NpcWave.SWING)
end

-- Apply the angle to a shoulder joint. `baseC0` MUST be the joint's untouched C0, captured
-- once when the NPC was adopted -- read it live and every frame compounds on the last,
-- winding the arm round and round.
function NpcWave.poseShoulder(joint: Motor6D?, baseC0: CFrame?, angle: number)
	if not (joint and joint.Parent and baseC0) then return end
	if math.abs(angle) < 1e-4 then
		joint.C0 = baseC0
		return
	end
	local pivot = baseC0.Position
	joint.C0 = CFrame.new(pivot) * CFrame.Angles(0, 0, angle) * (baseC0 - pivot)
end

return NpcWave
