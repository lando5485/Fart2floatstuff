-- ============================================================================
-- GUT BELLY PUFF (client) — layers a smooth "puff" on the LOCAL player's gut: it
-- INFLATES as the gas charge builds and quickly DEFLATES back to the gut-tier
-- base size as they fart it out. Same shape/scale/placement the server uses; the
-- puff is a temporary inflation on top.
-- ============================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local player     = Players.LocalPlayer

-- must match BellySystem.server -------------------------------------------------
-- ranks:           Tiny  Small Medium Large  XL    Iron  Infinite  (ascending; Iron > XL)
local TIERS      = {100,  182,  520,   1075,  2146, 3218, 9999}
local TIER_SCALE = {1.00, 1.20, 1.40,  1.60,  1.80, 2.00, 2.20}
local PUFF_MAX  = 0.30
local INFLATE_SPEED = 6
local DEFLATE_SPEED = 12
local BASE       = Vector3.new(1.90, 1.50, 0.90)
local GROW       = Vector3.new(0.40, 0.85, 0.70)
local SHOULDER_W = 2.05
local EMBED = 0.40
local TOP_TUCK = 0.30 -- must match BellySystem.server (top edge pushed into torso to hide the seam)
local function gutSize(scale)
	local g = scale - 1
	return Vector3.new(
		math.min(BASE.X * (1 + g * GROW.X), SHOULDER_W),
		BASE.Y * (1 + g * GROW.Y),
		BASE.Z * (1 + g * GROW.Z)
	)
end
local function computeC0(torso, sz)
	local torsoFront = -torso.Size.Z * 0.5
	local centerZ = torsoFront + EMBED - sz.Z * 0.5
	local topY = torso.Size.Y * 0.32
	local centerY = topY - sz.Y * 0.5
	local pitch = math.asin(math.clamp(TOP_TUCK / (sz.Y * 0.5), -0.5, 0.5)) -- tuck top in / lean bottom out
	return CFrame.new(0, centerY, centerZ) * CFrame.Angles(pitch, 0, 0)
end

-- detail sizing — MUST match styleGut in BellySystem.server (these parts are built server-side)
local function styleGut(gut, sz)
	local sag = gut:FindFirstChild("Sag")
	if sag then
		sag.Size = Vector3.new(sz.X * 1.00, sz.Y * 0.64, sz.Z * 1.00)
		local w = sag:FindFirstChildWhichIsA("Weld"); if w then w.C0 = CFrame.new(0, -sz.Y * 0.27, -sz.Z * 0.03) end
	end
	local sheen = gut:FindFirstChild("Sheen")
	if sheen then
		sheen.Size = Vector3.new(sz.X * 0.55, sz.Y * 0.50, sz.Z * 0.94)
		local w = sheen:FindFirstChildWhichIsA("Weld"); if w then w.C0 = CFrame.new(0, sz.Y * 0.06, -sz.Z * 0.05) end
	end
	local navel = gut:FindFirstChild("Navel")
	if navel then
		local d = sz.Z * 0.22
		navel.Size = Vector3.new(0.06, d, d)
		local w = navel:FindFirstChildWhichIsA("Weld")
		if w then w.C0 = CFrame.new(0, -sz.Y * 0.05, -sz.Z * 0.5 + 0.03) * CFrame.Angles(0, math.rad(90), 0) end
	end
end

local function tierIndex(maxPower)
	local idx = 1
	for i, mp in ipairs(TIERS) do if maxPower >= mp then idx = i end end
	return idx
end
local function tierScale(maxPower)
	return TIER_SCALE[tierIndex(maxPower)] -- explicit per-rank scale (XL=1.80 < Iron=2.00)
end

local function currentMax()
	local ls = player:FindFirstChild("leaderstats")
	local sm = ls and ls:FindFirstChild("StomachMax")
	return (sm and sm.Value) or 100
end
local function findGut()
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("LowerTorso"))
	return torso and torso:FindFirstChild("GutBelly")
end

local function applyScale(folder, scale)
	local torso = folder.Parent
	if not (torso and torso:IsA("BasePart")) then return end
	local sz = gutSize(scale)
	local gut = folder:FindFirstChild("Gut")
	if gut then
		gut.Size = sz
		local w = gut:FindFirstChildWhichIsA("Weld"); if w then w.C0 = computeC0(torso, sz) end
		styleGut(gut, sz)
	end
end

local curScale = tierScale(100)
RunService.Heartbeat:Connect(function(dt)
	local folder = findGut()
	if not folder then return end
	local fill = math.clamp(tonumber(_G.gasFill01) or 0, 0, 1) -- 0..1 gas charge (from CoreClient)
	local target = tierScale(currentMax()) * (1 + PUFF_MAX * fill) -- tier base + charge puff
	local speed = (target >= curScale) and INFLATE_SPEED or DEFLATE_SPEED
	curScale = curScale + (target - curScale) * math.clamp(dt * speed, 0, 1)
	applyScale(folder, curScale) -- local-only visual on top of the server's tier base
end)

print("[Belly] client puff active (inflates with gas charge, deflates on release)")
