--======================================================================
-- ColdIsland.client.lua   (LocalScript, per-player)
--======================================================================
-- IT IS COLD UP THERE, AND YOU SHOULD BE ABLE TO TELL.
--
-- Two effects, both only while you are stood on the snow island:
--   FLAKES   drifting across the screen, in three depths so they parallax
--   BREATH   a puff from your mouth every couple of seconds
--
-- The flakes are SCREEN-SPACE on purpose. World particles around the player look right in a
-- screenshot and wrong in motion -- they slide with the camera and read as dirt on the lens.
-- Flakes drawn on the screen and drifting on their own clock read as weather you are stood in.
--
-- The breath is the more important half. Snow tells you the PLACE is cold; breath tells you
-- YOU are cold, and that is the one that makes a player feel present in it.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local player     = Players.LocalPlayer
local PlayerGui  = player:WaitForChild("PlayerGui")

local COLD_ISLANDS = { island4 = true }   -- add more here as more of them get snow
local FLAKES       = 44
local BREATH_GAP   = 2.4                  -- seconds between puffs, roughly
local RESCAN       = 1.5

local function norm(s) return (tostring(s):lower():gsub("[%s_%-]", "")) end

-- ---- am I on a cold island? ------------------------------------------------
-- Bounding boxes, not pivots: an island model's pivot can sit anywhere, and judging by pivot
-- distance is how the NPC arrows ended up pointing at the wrong island entirely.
local boxes = {}
local function boxOf(m)
	local b = boxes[m]
	if b and b.h.X > 25 and b.h.Z > 25 then return b end
	local ok, cf, size = pcall(function() return m:GetBoundingBox() end)
	if not ok or not cf then return nil end
	b = { c = cf.Position, h = size * 0.5 }
	boxes[m] = b
	return b
end

local function onCold(pos)
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and COLD_ISLANDS[norm(m.Name)] then
			local b = boxOf(m)
			if b then
				local dx = math.abs(pos.X - b.c.X) - b.h.X
				local dz = math.abs(pos.Z - b.c.Z) - b.h.Z
				-- a little slack, so standing on the very edge still counts as being on it
				if dx < 30 and dz < 30 then return true end
			end
		end
	end
	return false
end

-- ---- the flakes ------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "ColdSnow"; gui.ResetOnSpawn = false; gui.DisplayOrder = 2
gui.IgnoreGuiInset = true; gui.Enabled = false; gui.Parent = PlayerGui

local flakes = {}
for i = 1, FLAKES do
	-- three depths. Near flakes are bigger, faster and brighter; far ones crawl. Without the
	-- split they all fall at one speed and it reads as a screen effect, not as depth.
	local depth = (i % 3) + 1
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	f.BackgroundTransparency = 0.75 - depth * 0.12
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(2 + depth, 2 + depth)
	f.ZIndex = depth
	f.Parent = gui
	Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
	flakes[i] = {
		f = f, depth = depth,
		x = math.random(), y = math.random(),
		fall = (0.05 + depth * 0.055) * (0.8 + math.random() * 0.5),
		sway = 0.02 + math.random() * 0.05,
		phase = math.random() * 6.28,
	}
end

-- ---- the breath ------------------------------------------------------------
local breathAtt, nextBreath = nil, 0
local function ensureBreath(head)
	if breathAtt and breathAtt.Parent == head then return breathAtt end
	if breathAtt then breathAtt:Destroy() end
	breathAtt = Instance.new("Attachment")
	breathAtt.Name = "ColdBreath"
	breathAtt.Position = Vector3.new(0, -0.15, -0.8)   -- at the mouth, pointing out
	breathAtt.Parent = head

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Puff"
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(226, 240, 255), Color3.fromRGB(255, 255, 255))
	pe.Lifetime = NumberRange.new(0.9, 1.5)
	pe.Rate = 0                                        -- emitted in puffs, never continuous
	pe.Speed = NumberRange.new(3, 5)
	pe.SpreadAngle = Vector2.new(14, 14)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.35, 1.1), NumberSequenceKeypoint.new(1, 2.0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.3, 0.72), NumberSequenceKeypoint.new(1, 1) })
	pe.Acceleration = Vector3.new(0, 2.2, 0)           -- it rises as it cools
	pe.LightEmission = 0.35
	pe.Parent = breathAtt
	return breathAtt
end

-- ---- drive it --------------------------------------------------------------
local cold, nextScan = false, 0

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt or 0.016, 0.05)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local head = char and char:FindFirstChild("Head")

	local now = os.clock()
	if now >= nextScan then
		nextScan = now + RESCAN
		local was = cold
		cold = (hrp ~= nil) and onCold(hrp.Position)
		if cold ~= was then
			gui.Enabled = cold
			print(("[Cold] %s the snow"):format(cold and "on" or "off"))
		end
	end
	if not cold then return end

	-- flakes drift down and sway; a flake off the bottom comes back in at the top with a new
	-- x, so the field never settles into a pattern you can see repeating
	for _, k in ipairs(flakes) do
		k.y += k.fall * dt
		if k.y > 1.05 then
			k.y = -0.05
			k.x = math.random()
		end
		local sx = k.x + math.sin(now * k.sway * 12 + k.phase) * 0.012 * k.depth
		k.f.Position = UDim2.fromScale(sx, k.y)
	end

	-- breath: only while you are actually breathing hard enough to see it, i.e. always here,
	-- but timed off a clock rather than every frame
	if head and now >= nextBreath then
		nextBreath = now + BREATH_GAP * (0.75 + math.random() * 0.5)
		local att = ensureBreath(head)
		local pe = att and att:FindFirstChild("Puff")
		if pe then pe:Emit(6 + math.random(4)) end
	end
end)

player.CharacterAdded:Connect(function() breathAtt = nil end)

print("[Cold] ready -- screen snow + visible breath while on the snow island")
