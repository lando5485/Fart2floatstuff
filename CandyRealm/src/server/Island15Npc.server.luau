--======================================================================
-- Island15Npc.server.luau  (Server Script)  -- CandyRealm
--======================================================================
-- island15 (Bakery Summit) is the ONLY island with no Studio-placed
-- "Candy Npc" -- every boot BakeryQuest logs "no NPC nearby" and improvises
-- a client-side Baker instead. This builds the island's real NPC on the
-- server so every player sees the same one, and so the existing systems
-- pick it up with zero changes:
--
--   * NAMED "Candy Npc" -- the exact name every other island uses, so
--     NpcGuideArrow's island-scoped scan and NpcLife's adoption find it.
--   * ANCHORED HumanoidRootPart + Motor6D limbs -- the rig style NpcLife
--     reports as `root=HumanoidRootPart anchored=true arm=shoulder joint`:
--     the joints let it breathe/wave while the anchor pins it in place.
--   * PLACED NEAR THE MIXER MARKER when one exists -- BakeryQuest's
--     findExistingNpc() adopts any NPC close to the mixer, so this NPC
--     BECOMES the Baker and the client stops building its stand-in.
--   * PARENTED INTO island15 -- travels with the island's tower move and
--     inherits its Persistent streaming mode.
--
-- IDEMPOTENT: if island15 already holds a Humanoid model named "Candy Npc"
-- (placed later in Studio, or a baked copy of this script ran first),
-- nothing is built. Place a hand-made NPC in Studio any time and this
-- script steps aside for it.
--======================================================================

local Workspace = game:GetService("Workspace")

local NPC_NAME = "Candy Npc"

-- Bright kid-friendly house palette (see the UI memory: blue/white/lime/gold)
local SKIN   = Color3.fromRGB(255, 205, 148)
local SHIRT  = Color3.fromRGB( 66, 148, 255)   -- house blue
local APRON  = Color3.fromRGB(255, 255, 255)   -- baker white
local PANTS  = Color3.fromRGB(255, 196,  56)   -- gold
local HAT    = Color3.fromRGB(255, 255, 255)

-- Wait for the tower to be built so the NPC lands at the island's REAL
-- position, not its Studio one 59,000 studs below.
do
	local t0 = os.clock()
	while not _G.islandsPositioned and os.clock() - t0 < 20 do task.wait(0.25) end
end

local island = Workspace:FindFirstChild("island15")
if not island then warn("[I15Npc] no island15 in Workspace -- NPC not built") return end

-- Already has one? (Studio-placed, or a duplicate copy of this script won.)
for _, d in ipairs(island:GetChildren()) do
	if d:IsA("Model") and d.Name == NPC_NAME and d:FindFirstChildWhichIsA("Humanoid") then
		print("[I15Npc] island15 already has a '" .. NPC_NAME .. "' -- nothing to build")
		return
	end
end

-- The floor of record: the "chicken zone " slab. Named with a TRAILING SPACE in the
-- world, so it is matched the way BakeryQuest's norm() does it -- case, spaces,
-- underscores and hyphens all stripped -- rather than by a literal name compare.
local slab
for _, d in ipairs(island:GetDescendants()) do
	if d:IsA("BasePart") and d.Name:lower():gsub("[%s_%-]", "") == "chickenzone" then
		slab = d
		break
	end
end
if not slab then warn("[I15Npc] no 'chicken zone' slab on island15 -- NPC not built") return end
local floorY = slab.Position.Y + slab.Size.Y * 0.5

-- WHERE HE STANDS: exactly where BakeryQuest's own stand-in Baker would have.
-- That quest grows the mixing station to MIXER_SCALE (5) around the marker brick,
-- so the counter ends up ~37 studs wide -- anything placed a few studs off the
-- marker is standing INSIDE it. buildBaker()'s spot is the offset that is known
-- to clear the grown counter, in the marker's OWN frame so a rotated station
-- still puts him beside it and not through it. Copied deliberately: this NPC is
-- what findExistingNpc() adopts, so it has to be usable from the same place.
local MIXER_SCALE = 5                                        -- must match BakeryQuest
local BAKER_OFF   = CFrame.new(4.2 * MIXER_SCALE + 3, 0, -1.5)
local BAKER_YAW   = math.rad(140)                            -- faces where players walk up

local anchorCF
for _, d in ipairs(island:GetDescendants()) do
	if d.Name:lower():gsub("[%s_%-]", "") == "mixer" then
		local p = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
		if p then anchorCF = p.CFrame * BAKER_OFF * CFrame.Angles(0, BAKER_YAW, 0) break end
	end
end
-- no mixer brick: a spot in from the slab's centre, facing back across it
anchorCF = anchorCF or (CFrame.new(slab.Position + Vector3.new(24, 0, -18))
	* CFrame.Angles(0, math.rad(150), 0))

--======================================================================
-- BUILD -- classic blocky R6-style rig, joints driven, root anchored
--======================================================================
local npc = Instance.new("Model")
npc.Name = NPC_NAME

local function part(name, size, color, transparent)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.Color = color or SHIRT
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false; p.CanCollide = false
	if transparent then p.Transparency = 1 end
	p.Parent = npc
	return p
end

-- Root: the ONE anchored part; every limb hangs off it through Motor6Ds so
-- NpcLife's breathe/wave animation moves them while the rig stays pinned.
-- floorY + 3: an R6 rig's root sits legs (2) + half a torso (1) above the ground.
-- The heading is taken from the offset frame but FLATTENED: the marker brick is a
-- builder's block and may be tilted, and a baker leaning at 20 degrees reads as a
-- broken rig. Height comes from the slab, never from the marker.
local look = anchorCF.LookVector
local flat = Vector3.new(look.X, 0, look.Z)
if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
local standAt = Vector3.new(anchorCF.Position.X, floorY + 3, anchorCF.Position.Z)

local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), SHIRT, true)
root.Anchored = true
root.CFrame = CFrame.lookAt(standAt, standAt + flat.Unit)

local torso = part("Torso", Vector3.new(2, 2, 1), SHIRT)
local head  = part("Head",  Vector3.new(1.6, 1.2, 1.2), SKIN)
local lArm  = part("Left Arm",  Vector3.new(1, 2, 1), SKIN)
local rArm  = part("Right Arm", Vector3.new(1, 2, 1), SKIN)
local lLeg  = part("Left Leg",  Vector3.new(1, 2, 1), PANTS)
local rLeg  = part("Right Leg", Vector3.new(1, 2, 1), PANTS)

-- Baker dressing: white apron front + a puffy chef hat.
local apron = part("Apron", Vector3.new(1.7, 1.8, 0.2), APRON)
local hat   = part("ChefHat", Vector3.new(1.5, 0.9, 1.5), HAT)
hat.Shape = Enum.PartType.Cylinder

local face = Instance.new("Decal")
face.Name = "face"; face.Texture = "rbxasset://textures/face.png"; face.Parent = head

local function joint(name, p0, p1, c0, c1)
	local m = Instance.new("Motor6D")
	m.Name = name; m.Part0 = p0; m.Part1 = p1
	m.C0 = c0; m.C1 = c1 or CFrame.new()
	m.Parent = p0
	return m
end

joint("RootJoint",      root,  torso, CFrame.new(0, 0, 0))
joint("Neck",           torso, head,  CFrame.new(0, 1.6, 0))
joint("Left Shoulder",  torso, lArm,  CFrame.new(-1.5, 0.5, 0), CFrame.new(0, 0.5, 0))
joint("Right Shoulder", torso, rArm,  CFrame.new( 1.5, 0.5, 0), CFrame.new(0, 0.5, 0))
joint("Left Hip",       torso, lLeg,  CFrame.new(-0.5, -1, 0),  CFrame.new(0, 1, 0))
joint("Right Hip",      torso, rLeg,  CFrame.new( 0.5, -1, 0),  CFrame.new(0, 1, 0))
joint("ApronWeld",      torso, apron, CFrame.new(0, -0.1, -0.6))
joint("HatWeld",        head,  hat,   CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(90)))

-- The Humanoid is what NpcLife scans for; it is not a fighter. A finite MaxHealth
-- (not math.huge, which makes the health bar's own maths produce NaN) plus the bar
-- switched off means nothing about him can ever read as damaged.
local hum = Instance.new("Humanoid")
hum.DisplayName = "Baker"
hum.MaxHealth = 1e9; hum.Health = 1e9
hum.WalkSpeed = 0; hum.JumpPower = 0                 -- decorative: never moves on its own
hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
hum.Parent = npc

npc.PrimaryPart = root
npc.Parent = island

-- STREAMING: island15 is 59,000 studs up and the whole realm runs StreamingEnabled.
-- The island model is Persistent, but a model's streaming mode is its own property
-- rather than something inherited, and an NPC that streams out is a quest-giver that
-- vanishes mid-conversation. pcall'd because it is a newer property.
pcall(function() npc.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)

print(("[I15Npc] '%s' built on island15 at (%.0f, %.0f, %.0f) -- NpcLife/NpcGuide/BakeryQuest all find it by name")
	:format(NPC_NAME, root.Position.X, root.Position.Y, root.Position.Z))
