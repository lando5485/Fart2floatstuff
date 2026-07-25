-- ============================================================================================================
-- AMBIENT WILDLIFE  (client)
--
-- Butterflies and bees over the Community Garden, and birds circling Bean Farm. The garden is beautiful and
-- completely dead -- nothing in it moves except the gardener and his one songbird. A still scene reads as a
-- diorama; a scene with things drifting through it reads as a place.
--
-- ===== WHY CLIENT-SIDE =====
-- GardenBird runs on the server, which is right for it: it is ONE bird, it perches on a specific NPC, and every
-- player should see it in the same spot. This is the opposite case. Twenty small critters on the server would
-- replicate twenty CFrames per frame to every player, forever, and nobody would be able to tell whether your
-- butterfly and mine were in the same place -- because nobody is watching a butterfly that closely. So each client
-- grows its own. Zero replication, zero server cost.
--
-- Nothing here collides, is queryable, casts shadows, or can be touched. It is scenery that happens to move.
-- ============================================================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local BUTTERFLIES = 10
local BEES        = 7
local BIRDS       = 4

local GARDEN_R    = 42   -- studs: how far from the garden centre they wander
local FLY_LOW     = 3    -- height band above the garden floor they stay within
local FLY_HIGH    = 11
local BIRD_R      = 150  -- radius the birds circle the island at
local BIRD_H      = 60   -- how high above the island they circle
local DRAW_DIST   = 260  -- beyond this from the player, freeze everything. A butterfly you cannot see does not
                         -- need to be animated, and this is what keeps 21 critters free rather than merely cheap.

local player = Players.LocalPlayer
local rng = Random.new()

local folder = Instance.new("Folder")
folder.Name = "AmbientWildlife"
folder.Parent = Workspace

local function part(parent, name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A butterfly: two wings hinged either side of a body. The WINGS are what sell it -- a butterfly that glides with
-- fixed wings reads as a leaf, so the flap is the whole illusion and it has to be big and irregular.
local function buildButterfly(col1, col2)
	local m = Instance.new("Model"); m.Name = "Butterfly"; m.Parent = folder
	local body = part(m, "Body", Vector3.new(0.12, 0.12, 0.42), Color3.fromRGB(40, 32, 28))
	m.PrimaryPart = body
	local wingL = part(m, "WingL", Vector3.new(0.06, 0.5, 0.62), col1)
	local wingR = part(m, "WingR", Vector3.new(0.06, 0.5, 0.62), col2)
	wingL.Transparency = 0.1; wingR.Transparency = 0.1
	return { model = m, body = body, wingL = wingL, wingR = wingR }
end

local function buildBee()
	local m = Instance.new("Model"); m.Name = "Bee"; m.Parent = folder
	local body = part(m, "Body", Vector3.new(0.22, 0.22, 0.34), Color3.fromRGB(240, 200, 40))
	m.PrimaryPart = body
	part(m, "Stripe", Vector3.new(0.24, 0.24, 0.10), Color3.fromRGB(30, 26, 20)).CFrame = body.CFrame
	local wingL = part(m, "WingL", Vector3.new(0.03, 0.16, 0.30), Color3.fromRGB(230, 245, 255))
	local wingR = part(m, "WingR", Vector3.new(0.03, 0.16, 0.30), Color3.fromRGB(230, 245, 255))
	wingL.Transparency = 0.55; wingR.Transparency = 0.55
	return { model = m, body = body, wingL = wingL, wingR = wingR, stripe = m.Stripe }
end

local function buildBird()
	local m = Instance.new("Model"); m.Name = "SkyBird"; m.Parent = folder
	local body = part(m, "Body", Vector3.new(0.5, 0.4, 1.3), Color3.fromRGB(52, 48, 58))
	m.PrimaryPart = body
	local wingL = part(m, "WingL", Vector3.new(0.08, 0.18, 2.2), Color3.fromRGB(64, 60, 72))
	local wingR = part(m, "WingR", Vector3.new(0.08, 0.18, 2.2), Color3.fromRGB(64, 60, 72))
	return { model = m, body = body, wingL = wingL, wingR = wingR }
end

-- ===== FIND THE GARDEN + THE ISLAND (both build asynchronously, long after this script starts) =====
local gardenPos, islandPos
task.spawn(function()
	for _ = 1, 240 do
		if not gardenPos then
			local build = Workspace:FindFirstChild("CommunityGardenBuild", true)
			if build then
				local ok, cf = pcall(function() return build:GetPivot() end)
				if ok then gardenPos = cf.Position end
			end
		end
		if not islandPos then
			for _, m in ipairs(Workspace:GetChildren()) do
				if m:IsA("Model") and m.Name:match("^Island_1_") then
					local ok, cf = pcall(function() return m:GetPivot() end)
					if ok then islandPos = cf.Position end
					break
				end
			end
		end
		if gardenPos and islandPos then break end
		task.wait(0.5)
	end
	print(("[Wildlife] garden=%s island=%s"):format(tostring(gardenPos ~= nil), tostring(islandPos ~= nil)))
end)

-- ===== SPAWN =====
-- Each critter gets its OWN random speed, radius, height and phase. Give them shared values and they move as a
-- flock of clones, which is instantly readable as fake -- the irregularity IS the realism.
local WING_COLORS = {
	{ Color3.fromRGB(255, 170, 60),  Color3.fromRGB(255, 140, 40)  }, -- monarch
	{ Color3.fromRGB(120, 190, 255), Color3.fromRGB(90, 160, 240)  }, -- blue
	{ Color3.fromRGB(255, 245, 250), Color3.fromRGB(240, 225, 240) }, -- white
	{ Color3.fromRGB(255, 210, 90),  Color3.fromRGB(250, 180, 70)  }, -- yellow
}

local critters = {}
for i = 1, BUTTERFLIES do
	local c = WING_COLORS[((i - 1) % #WING_COLORS) + 1]
	local b = buildButterfly(c[1], c[2])
	b.kind    = "butterfly"
	b.radius  = rng:NextNumber(8, GARDEN_R)
	b.speed   = rng:NextNumber(0.16, 0.34)        -- lazy
	b.height  = rng:NextNumber(FLY_LOW, FLY_HIGH)
	b.bobAmp  = rng:NextNumber(0.8, 2.2)          -- butterflies do not fly straight; they bob a lot
	b.bobFreq = rng:NextNumber(1.4, 2.6)
	b.flap    = rng:NextNumber(7, 11)
	b.phase   = rng:NextNumber(0, math.pi * 2)
	critters[#critters + 1] = b
end
for _ = 1, BEES do
	local b = buildBee()
	b.kind    = "bee"
	b.radius  = rng:NextNumber(5, 22)             -- bees stay tighter to the flowers
	b.speed   = rng:NextNumber(0.5, 0.9)          -- and are much busier
	b.height  = rng:NextNumber(2, 6)
	b.bobAmp  = rng:NextNumber(0.3, 0.8)
	b.bobFreq = rng:NextNumber(3, 5)
	b.flap    = rng:NextNumber(28, 40)            -- a blur, as it should be
	b.phase   = rng:NextNumber(0, math.pi * 2)
	critters[#critters + 1] = b
end
for _ = 1, BIRDS do
	local b = buildBird()
	b.kind    = "bird"
	b.radius  = rng:NextNumber(BIRD_R * 0.6, BIRD_R)
	b.speed   = rng:NextNumber(0.10, 0.18)        -- slow, wide, unhurried circles
	b.height  = rng:NextNumber(BIRD_H * 0.7, BIRD_H * 1.4)
	b.bobAmp  = rng:NextNumber(1.5, 4)
	b.bobFreq = rng:NextNumber(0.3, 0.7)
	b.flap    = rng:NextNumber(2, 3.5)            -- birds glide; the flap is occasional, not constant
	b.phase   = rng:NextNumber(0, math.pi * 2)
	critters[#critters + 1] = b
end
print(("[Wildlife] %d butterflies, %d bees, %d birds"):format(BUTTERFLIES, BEES, BIRDS))

-- ===== FLY =====
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	local me = hrp and hrp.Position

	for _, c in ipairs(critters) do
		local centre = (c.kind == "bird") and islandPos or gardenPos
		if centre and c.model.Parent then
			-- CULL: freeze anything the player is nowhere near. This is what makes 21 animated critters free.
			if me and (centre - me).Magnitude > DRAW_DIST + c.radius then
				if c.body.Transparency < 1 then
					for _, p in ipairs(c.model:GetChildren()) do
						if p:IsA("BasePart") then p.Transparency = 1 end
					end
				end
			else
				if c.body.Transparency >= 1 then
					c.body.Transparency = 0
					c.wingL.Transparency = (c.kind == "bee") and 0.55 or ((c.kind == "butterfly") and 0.1 or 0)
					c.wingR.Transparency = c.wingL.Transparency
					if c.stripe then c.stripe.Transparency = 0 end
				end

				local a = t * c.speed + c.phase
				-- a wobbling circle, not a clean one -- a perfect orbit is the tell that something is on rails
				local r = c.radius * (1 + 0.18 * math.sin(a * 1.7 + c.phase))
				local pos = centre + Vector3.new(
					math.cos(a) * r,
					c.height + math.sin(t * c.bobFreq + c.phase) * c.bobAmp,
					math.sin(a) * r
				)

				-- face the way we are going (the tangent of the circle)
				local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
				local cf = CFrame.lookAt(pos, pos + tangent)
				c.body.CFrame = cf
				if c.stripe then c.stripe.CFrame = cf * CFrame.new(0, 0, 0.02) end

				-- WINGS. Butterflies and bees flap about the body's LONG axis (they beat up and down at the sides);
				-- the bird's wings sweep from a shoulder further out. Same maths, different hinge.
				local beat = math.sin(t * c.flap + c.phase)
				if c.kind == "bird" then
					local sweep = math.rad(38) * beat
					c.wingL.CFrame = cf * CFrame.new(-0.9, 0.1, 0) * CFrame.Angles(0, 0, sweep)
					c.wingR.CFrame = cf * CFrame.new(0.9, 0.1, 0) * CFrame.Angles(0, 0, -sweep)
				else
					local open = math.rad((c.kind == "bee") and 55 or 78) * (0.35 + 0.65 * ((beat + 1) / 2))
					c.wingL.CFrame = cf * CFrame.new(-0.06, 0.16, 0) * CFrame.Angles(0, 0, open)
					c.wingR.CFrame = cf * CFrame.new(0.06, 0.16, 0) * CFrame.Angles(0, 0, -open)
				end
			end
		end
	end
end)

print("[Wildlife] ready -- butterflies + bees over the garden, birds circling Bean Farm (client-side, no replication)")
