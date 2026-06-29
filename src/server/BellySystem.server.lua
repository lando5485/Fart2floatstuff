-- ============================================================================
-- GUT BELLY (server) — a SINGLE smooth belly bulge welded to each character's
-- torso that gets visibly bigger per gut tier. Made on the server so it
-- replicates to everyone. The charge "puff" is layered on locally by the owning
-- player's client (BellyPuff.client) on top of this tier base size.
--
-- Reads as a BELLY (not an egg): WIDE + FLAT (hugs the body), TALL (merges up into
-- the torso), with its BACK embedded into the torso so there's one continuous
-- bulge, only slightly protruding forward. Welded to the UpperTorso (R15) / Torso
-- (R6) and placed relative to that torso's size. SmoothPlastic, skin-tone tint.
-- ============================================================================

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local GutSkins = require(RS:WaitForChild("Shared"):WaitForChild("GutSkins")) -- cosmetic skin config (colour/material/effects only; never size)

-- GUT TIERS in RANK ORDER (smallest -> largest), matching PlayerStats.stomachTiers. The maxPower the belly
-- keys off MUST be ascending, and TIER_SCALE MUST be strictly increasing so each tier renders bigger than the
-- one below it. Iron (rank 6) is bigger than XL (rank 5).
--   rank  1      2       3        4       5      6       7
--   name  Tiny   Small   Medium   Large   XL     Iron    Infinite
local TIERS      = {100,  182,    520,     1075,   2146,  3218,   9999} -- maxPower per rank (ascending)
local TIER_NAMES = {"Tiny","Small","Medium","Large","XL",  "Iron", "Infinite"}
local TIER_SCALE = {1.00, 1.20,   1.40,    1.60,   1.80,  2.00,   2.20} -- size scale per rank (strictly increasing)

local function tierIndex(maxPower)
	-- highest rank whose maxPower threshold the gut has reached
	local idx = 1
	for i, mp in ipairs(TIERS) do if maxPower >= mp then idx = i end end
	return idx
end
local function tierScale(maxPower)
	return TIER_SCALE[tierIndex(maxPower)] -- explicit per-rank scale (XL=1.80 < Iron=2.00)
end

-- (3) SIZE/SHAPE: WIDER than it is DEEP (flat Z hugs the body), and TALL so the top merges into the torso.
local BASE       = Vector3.new(1.90, 1.50, 0.90) -- (X width) > (Z depth) -> hugs the body, not a sphere
local GROW       = Vector3.new(0.40, 0.85, 0.70) -- per-axis growth weights (width capped, height & depth grow)
local SHOULDER_W = 2.05                            -- hard cap on width
local function gutSize(scale)
	local g = scale - 1
	return Vector3.new(
		math.min(BASE.X * (1 + g * GROW.X), SHOULDER_W),
		BASE.Y * (1 + g * GROW.Y),
		BASE.Z * (1 + g * GROW.Z)
	)
end

-- (1/2/4) PLACEMENT relative to the torso + the gut's own depth:
--   * BACK embedded EMBED studs INTO the torso (one continuous belly, kills the double-circle seam),
--   * so it only protrudes slightly forward,
--   * centre RAISED so the top blends into the mid-torso.
local EMBED = 0.40
local TOP_TUCK = 0.30 -- (2) studs the TOP edge is pushed back INTO the torso to kill the seam
local function computeC0(torso, sz)
	local torsoFront = -torso.Size.Z * 0.5             -- the torso's front surface (-Z = forward)
	local centerZ = torsoFront + EMBED - sz.Z * 0.5    -- back sits EMBED studs inside the torso; grows forward as it gets bigger
	-- anchor the gut's TOP around the upper-mid torso so it blends in there, and let it grow DOWNWARD from that
	-- top (never pokes up into the neck): centre = topY - half the gut height.
	local topY = torso.Size.Y * 0.32
	local centerY = topY - sz.Y * 0.5
	-- (2)/(4) PITCH the gut back at the top: rotating about the centre by `pitch` pushes the TOP edge
	-- TOP_TUCK studs into the torso (+Z = back) so there's no hard seam, while the BOTTOM leans forward
	-- (-Z) for a heavier, sagging look. asin(TOP_TUCK / halfHeight) keeps the tuck constant across tiers.
	local pitch = math.asin(math.clamp(TOP_TUCK / (sz.Y * 0.5), -0.5, 0.5))
	return CFrame.new(0, centerY, centerZ) * CFrame.Angles(pitch, 0, 0) -- X = 0 -> centred left-to-right
end

local function tintOf(c, m)
	return Color3.new(math.clamp(c.R * m, 0, 1), math.clamp(c.G * m, 0, 1), math.clamp(c.B * m, 0, 1))
end
local function smoothAllFaces(p)
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.LeftSurface = Enum.SurfaceType.Smooth; p.RightSurface = Enum.SurfaceType.Smooth
	p.FrontSurface = Enum.SurfaceType.Smooth; p.BackSurface = Enum.SurfaceType.Smooth
end
local function torsoOf(char)
	return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("LowerTorso")
end

-- (1/3/4) DETAIL parts welded to the Gut ball (so they inherit its scale + tilt). They are re-sized/
-- re-positioned as fractions of the gut size every time the gut scales (tier change or charge puff), so
-- this MUST match the copy in BellyPuff.client.lua. Sizing only — colours are set in applyGutAppearance.
local function styleGut(gut, sz)
	-- (1/4) SAG: a slightly darker lobe sitting low so the underside reads heavier/rounder (not a symmetric egg).
	local sag = gut:FindFirstChild("Sag")
	if sag then
		sag.Size = Vector3.new(sz.X * 1.00, sz.Y * 0.64, sz.Z * 1.00)
		local w = sag:FindFirstChildWhichIsA("Weld"); if w then w.C0 = CFrame.new(0, -sz.Y * 0.27, -sz.Z * 0.03) end
	end
	-- (1) SHEEN: a subtly lighter highlight high on the front-centre so it looks round under lighting.
	local sheen = gut:FindFirstChild("Sheen")
	if sheen then
		sheen.Size = Vector3.new(sz.X * 0.55, sz.Y * 0.50, sz.Z * 0.94)
		local w = sheen:FindFirstChildWhichIsA("Weld"); if w then w.C0 = CFrame.new(0, sz.Y * 0.06, -sz.Z * 0.05) end
	end
	-- (3) NAVEL: a small dark disc flush with the front-centre surface -> reads as a belly button.
	local navel = gut:FindFirstChild("Navel")
	if navel then
		local d = sz.Z * 0.22
		navel.Size = Vector3.new(0.06, d, d) -- Cylinder: length along X (thin); rotated to face forward below
		local w = navel:FindFirstChildWhichIsA("Weld")
		if w then w.C0 = CFrame.new(0, -sz.Y * 0.05, -sz.Z * 0.5 + 0.03) * CFrame.Angles(0, math.rad(90), 0) end
	end
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

-- COLOUR: tint the gut ONE solid colour (no texture wrap — shirt images scramble on a sphere). Roblox can't
-- read a shirt image's colour at runtime, so:
--   * if the worn shirt's template id is listed in SHIRT_COLORS below, use that exact colour (a manual match),
--   * else use the avatar's torso/body colour (BodyColors.TorsoColor3 / UpperTorso.Color),
--   * and the skin tone when no shirt is worn.
-- To make a specific shirt match exactly, copy its template id from the print below into SHIRT_COLORS.
-- NOTE: Roblox does NOT allow reading another player's shirt colour at runtime — clothing assets are locked
-- ("not allowed to be forked"), so the gut can't auto-match a worn shirt for arbitrary players. The gut is
-- tinted the avatar's body/torso colour (works for everyone), with an optional manual per-shirt override.
local SHIRT_COLORS = {
	-- ["8928739964"] = Color3.fromRGB(120, 78, 45), -- manual: this shirt id -> this colour
}

-- (skin) ONE decal on the FRONT face only (pattern skins like Galaxy). No wrap -> never tiles/scrambles.
local function applyGutDecal(gut, skin)
	local existing = gut:FindFirstChild("GutSkinDecal")
	local tex = GutSkins.decalOf(skin)
	if not tex then if existing then existing:Destroy() end return end
	local d = existing or Instance.new("Decal")
	d.Name = "GutSkinDecal"; d.Face = Enum.NormalId.Front; d.Texture = tex; d.Parent = gut
end
-- (skin) optional glow (PointLight) + sparkle (Sparkles) effects
local function applyGutEffects(gut, skin)
	local light = gut:FindFirstChild("GutSkinLight")
	if skin and skin.glow then
		light = light or Instance.new("PointLight")
		light.Name = "GutSkinLight"; light.Color = skin.glow; light.Brightness = 2; light.Range = 11; light.Parent = gut
	elseif light then light:Destroy() end
	local sp = gut:FindFirstChild("GutSkinSparkle")
	if skin and skin.sparkle then
		sp = sp or Instance.new("Sparkles")
		sp.Name = "GutSkinSparkle"; sp.Parent = gut
	elseif sp then sp:Destroy() end
end

local function applyGutAppearance(folder)
	local torso = folder.Parent
	if not (torso and torso:IsA("BasePart")) then return end
	local gut = folder:FindFirstChild("Gut"); if not gut then return end
	-- clear stray shirt decals/textures but KEEP our own managed skin decal
	for _, c in ipairs(gut:GetChildren()) do if (c:IsA("Decal") or c:IsA("Texture")) and c.Name ~= "GutSkinDecal" then c:Destroy() end end

	local char = torso.Parent
	local plr = char and Players:GetPlayerFromCharacter(char)
	local shirt = char and char:FindFirstChildOfClass("Shirt")
	local id = shirt and shirt.ShirtTemplate and tostring(shirt.ShirtTemplate):match("%d+") or nil
	local bodyColors = char and char:FindFirstChildOfClass("BodyColors")
	local torsoCol = (bodyColors and bodyColors.TorsoColor3) or torso.Color
	if id and SHIRT_COLORS[id] then torsoCol = SHIRT_COLORS[id] end -- manual per-shirt override (Default skin only)

	-- EQUIPPED SKIN (cosmetic only). Default skin has no colour -> falls back to the avatar's skin/torso colour.
	local skinId = (plr and _G.playerEquippedGutSkin and _G.playerEquippedGutSkin[plr]) or "Default"
	local skin   = GutSkins.get(skinId) or GutSkins.get("Default")
	local base     = (skin and skin.color) or torsoCol
	local material = (skin and skin.material) or Enum.Material.SmoothPlastic

	-- paint EVERY gut part the same colour family + material (size is never touched here)
	gut.Color = base; gut.Material = material
	local function paint(name, mult)
		local p = gut:FindFirstChild(name); if p then p.Color = tintOf(base, mult); p.Material = material end
	end
	paint("Sag", 0.85)   -- underside ~15% darker
	paint("Sheen", 1.10) -- front highlight, a touch lighter
	paint("Navel", 0.55) -- belly button, clearly darker

	applyGutDecal(gut, skin)
	applyGutEffects(gut, skin)
end

-- exposed so GutSkinService can re-apply the equipped skin immediately after an equip (size unchanged)
_G.refreshGutSkin = function(player)
	local char = player and player.Character
	local torso = char and torsoOf(char)
	local folder = torso and torso:FindFirstChild("GutBelly")
	if folder then applyGutAppearance(folder) end
end

-- a detail bulge/disc welded to (and so moving + scaling with) the main Gut ball
local function buildDetail(gut, name, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Material = Enum.Material.SmoothPlastic
	p.Massless = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	smoothAllFaces(p)
	p.Size = Vector3.new(1, 1, 1)
	local w = Instance.new("Weld"); w.Name = "W"; w.Part0 = gut; w.Part1 = p; w.Parent = p
	p.Parent = gut
	return p
end

local function buildGut(torso)
	local folder = Instance.new("Model"); folder.Name = "GutBelly"
	local gut = Instance.new("Part")
	gut.Name = "Gut"
	gut.Shape = Enum.PartType.Ball              -- a real ball (always renders)
	gut.Material = Enum.Material.SmoothPlastic
	gut.Massless = true; gut.CanCollide = false; gut.CanQuery = false; gut.CanTouch = false; gut.CastShadow = false
	smoothAllFaces(gut)
	gut.Size = BASE
	gut.Parent = folder
	local w = Instance.new("Weld"); w.Name = "GutWeld"; w.Part0 = torso; w.Part1 = gut; w.C0 = computeC0(torso, BASE); w.Parent = gut
	-- (1/3/4) depth/shading + navel detail parts (sized by styleGut, coloured by applyGutAppearance)
	buildDetail(gut, "Sag", Enum.PartType.Ball)
	buildDetail(gut, "Sheen", Enum.PartType.Ball)
	buildDetail(gut, "Navel", Enum.PartType.Cylinder)
	styleGut(gut, BASE)
	folder.Parent = torso
	applyGutAppearance(folder) -- solid colour (shirt override / torso colour / skin tone)
	return folder
end

local function ensureGut(char)
	local torso = torsoOf(char); if not torso then return nil end
	return torso:FindFirstChild("GutBelly") or buildGut(torso)
end

local function sizeGut(char, maxPower)
	local folder = ensureGut(char); if not folder then return end
	applyGutAppearance(folder) -- refresh shirt/skin colour
	applyScale(folder, tierScale(maxPower))
end

local function currentMax(player)
	local ls = player:FindFirstChild("leaderstats")
	local sm = ls and ls:FindFirstChild("StomachMax")
	return (sm and sm.Value) or 100
end

local function hook(player)
	-- build + size the gut on spawn (it gets a base skin colour for now)
	local function onChar(char)
		task.wait(0.3) -- let the rig + torso load
		if char.Parent then sizeGut(char, currentMax(player)) end
	end
	-- (5) re-apply the COLOUR once the shirt + body colours are FULLY loaded (not on bare spawn)
	local function onAppearance(char)
		if not char.Parent then return end
		sizeGut(char, currentMax(player)) -- make sure the gut exists
		local torso = torsoOf(char); local f = torso and torso:FindFirstChild("GutBelly")
		if f then applyGutAppearance(f) end
	end
	if player.Character then task.spawn(onChar, player.Character) end
	player.CharacterAdded:Connect(onChar)
	player.CharacterAppearanceLoaded:Connect(onAppearance)
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats", 60)
		local sm = ls and ls:WaitForChild("StomachMax", 60)
		if sm then
			sm.Changed:Connect(function()
				if player.Character then sizeGut(player.Character, sm.Value) end
			end)
		end
	end)
end

for _, p in ipairs(Players:GetPlayers()) do hook(p) end
Players.PlayerAdded:Connect(hook)

-- VERIFY the tier progression goes smallest -> largest (scale strictly increases; Iron > XL).
print("[Belly] server gut system active. Tier size progression (rank: name maxPower scale -> size):")
for i = 1, #TIERS do
	local sz = gutSize(TIER_SCALE[i])
	print(string.format("  %d: %-9s maxPower=%-4d scale=%.2f -> size=(%.2f, %.2f, %.2f)",
		i, TIER_NAMES[i], TIERS[i], TIER_SCALE[i], sz.X, sz.Y, sz.Z))
	if i > 1 and TIER_SCALE[i] <= TIER_SCALE[i - 1] then
		warn(string.format("  [Belly] TIER ORDER ERROR: %s scale (%.2f) is not larger than %s (%.2f)!",
			TIER_NAMES[i], TIER_SCALE[i], TIER_NAMES[i - 1], TIER_SCALE[i - 1]))
	end
end
