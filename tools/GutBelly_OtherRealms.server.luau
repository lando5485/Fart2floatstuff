--[[
============================================================================================================
 GUT BELLY -- PORTABLE COPY FOR THE OTHER REALMS  (Space / Dino / Candy)
============================================================================================================
 A drop-in copy of the stomach that sits on the player's body in the food realm: same shape, same placement
 on the torso, same growth as the player buys bigger guts. Put this in the other realm and the belly looks
 identical there.

 HOW TO INSTALL
   Paste this whole file into a new Script in ServerScriptService of the target place. Nothing else -- no
   modules, no RemoteEvents, no folders. It has no requires and no dependency on this realm's PlayerStats,
   GutSkins or anything else, so it cannot fail on a place that doesn't have them.

 DO NOT PUT IT IN THIS REALM.
   src/server/BellySystem.server.lua already does this job here. Two copies would weld two bellies to the
   same torso. It lives in tools/ precisely because tools/ is NOT in default.project.json, so Rojo will never
   sync it into the food realm.

 WHERE THE SIZE COMES FROM
   The belly picks its tier from the player's stomach max. It looks for that value in three places, in order,
   and uses the first one it finds -- so it works whether the target realm copies the food realm's leaderstats
   convention or does its own thing:

     1. player.leaderstats.StomachMax   (a NumberValue/IntValue -- the food realm's convention)
     2. player:GetAttribute("StomachMax")
     3. START_MAX below                 (fallback: Tiny)

   Whichever it finds, it WATCHES it, so the belly grows the moment the value changes -- no respawn needed.
   If the other realm has no notion of stomach size at all, leave it: every player just gets the Tiny belly.

 KEEPING IT IN SYNC
   This is a COPY, not a shared module -- the realms are separate places and cannot require across each other.
   If you retune the geometry in src/server/BellySystem.server.lua (BASE, GROW, SHOULDER_W, TIER_SCALE, EMBED,
   TOP_TUCK, or the styleGut fractions), paste the new numbers here too or the realms drift apart. Every
   duplicated block below is marked "-- [BellySystem]" so they are easy to find.

 WHAT IS DELIBERATELY LEFT OUT
   * GUT SKINS (Galaxy/rainbow/etc) -- a food-realm cosmetic, driven by that realm's GutSkinService. The belly
     here is always the avatar's own body colour, which is the Default skin's look.
   * THE CHARGE PUFF -- the belly inflating as you hold the fart button. That is BellyPuff.client, and it is
     driven by the flight system, which the other realms don't run.
   Both are additive: if you later port them, they layer on top of this without changing anything below.
============================================================================================================
]]

local Players = game:GetService("Players")

--==================== TUNABLES ====================
local START_MAX  = 100                             -- stomach max to assume when the realm has no value (= Tiny)
local SETTLE     = 0.3                             -- seconds to let the rig load before welding
local SKIN_FALLBACK = Color3.fromRGB(205, 148, 108) -- used only if the avatar exposes no body colour at all

-- Manual per-shirt colour overrides, same escape hatch the food realm has. Roblox will not let a script read
-- a worn shirt's colour at runtime (clothing assets can't be forked), so the belly is tinted the avatar's
-- BODY colour instead -- which is right for everyone. If one specific shirt needs an exact match, put its
-- template id here.
local SHIRT_COLORS = {
	-- ["8928739964"] = Color3.fromRGB(120, 78, 45),
}

--==================== [BellySystem] TIERS ====================
-- RANK ORDER, smallest -> largest. maxPower must be ASCENDING and TIER_SCALE STRICTLY INCREASING, so each
-- tier renders bigger than the one below it. Note Iron (2.00) is bigger than XL (1.80).
--   rank  1      2       3        4       5      6       7
--   name  Tiny   Small   Medium   Large   XL     Iron    Infinite
local TIERS      = { 100,  182,    520,     1075,   2146,  3218,   9999 }
local TIER_NAMES = { "Tiny","Small","Medium","Large","XL",  "Iron", "Infinite" }
local TIER_SCALE = { 1.00, 1.20,   1.40,    1.60,   1.80,  2.00,   2.20 }

local function tierIndex(maxPower)
	local idx = 1
	for i, mp in ipairs(TIERS) do if maxPower >= mp then idx = i end end
	return idx
end
local function tierScale(maxPower) return TIER_SCALE[tierIndex(maxPower)] end

--==================== [BellySystem] SIZE ====================
-- Reads as a BELLY, not an egg: WIDER than it is DEEP (flat Z hugs the body) and TALL, so the top merges up
-- into the torso. Width is hard-capped at the shoulders; height and depth carry the growth.
local BASE       = Vector3.new(1.90, 1.50, 0.90)
local GROW       = Vector3.new(0.40, 0.85, 0.70)
local SHOULDER_W = 2.05

local function gutSize(scale)
	local g = scale - 1
	return Vector3.new(
		math.min(BASE.X * (1 + g * GROW.X), SHOULDER_W),
		BASE.Y * (1 + g * GROW.Y),
		BASE.Z * (1 + g * GROW.Z)
	)
end

--==================== [BellySystem] PLACEMENT ON THE BODY ====================
-- THIS is what makes it sit the same way it does in the food realm:
--   * the BACK is embedded EMBED studs INTO the torso, so it reads as one continuous bulge instead of a ball
--     stuck on the front (that embed is what kills the double-circle seam),
--   * the TOP is anchored around the upper-mid torso and the belly grows DOWNWARD from there, so it never
--     pokes up into the neck as it gets bigger,
--   * the whole thing is PITCHED back at the top by TOP_TUCK studs, which also leans the bottom forward for a
--     heavier, sagging look. asin() keeps that tuck constant in studs at every tier.
local EMBED    = 0.40
local TOP_TUCK = 0.30

local function computeC0(torso, sz)
	local torsoFront = -torso.Size.Z * 0.5             -- -Z is forward
	local centerZ    = torsoFront + EMBED - sz.Z * 0.5
	local topY       = torso.Size.Y * 0.32
	local centerY    = topY - sz.Y * 0.5
	local pitch      = math.asin(math.clamp(TOP_TUCK / (sz.Y * 0.5), -0.5, 0.5))
	return CFrame.new(0, centerY, centerZ) * CFrame.Angles(pitch, 0, 0) -- X = 0 -> centred left-to-right
end

--==================== [BellySystem] DETAIL PROPORTIONS ====================
-- Sag / Sheen / Navel are re-sized as FRACTIONS of the gut every time it scales, so the look holds at every
-- tier instead of being authored once for one size.
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
		navel.Size = Vector3.new(0.06, d, d) -- Cylinder: length runs along X, so it is rotated to face forward
		local w = navel:FindFirstChildWhichIsA("Weld")
		if w then w.C0 = CFrame.new(0, -sz.Y * 0.05, -sz.Z * 0.5 + 0.03) * CFrame.Angles(0, math.rad(90), 0) end
	end
end

--==================== BUILD ====================
local function tintOf(c, m)
	return Color3.new(math.clamp(c.R * m, 0, 1), math.clamp(c.G * m, 0, 1), math.clamp(c.B * m, 0, 1))
end
local function smoothAllFaces(p)
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.LeftSurface = Enum.SurfaceType.Smooth; p.RightSurface = Enum.SurfaceType.Smooth
	p.FrontSurface = Enum.SurfaceType.Smooth; p.BackSurface = Enum.SurfaceType.Smooth
end
-- R15 first, then R6, then LowerTorso -- same order the food realm uses, so the belly lands on the same part
-- whichever rig the other realm spawns.
local function torsoOf(char)
	return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("LowerTorso")
end

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

-- Solid body colour, no texture wrap: a shirt image mapped onto a sphere scrambles, so the belly is tinted
-- ONE colour taken from the avatar's own body.
local function applyGutAppearance(folder)
	local torso = folder.Parent
	if not (torso and torso:IsA("BasePart")) then return end
	local gut = folder:FindFirstChild("Gut"); if not gut then return end
	for _, c in ipairs(gut:GetChildren()) do
		if c:IsA("Decal") or c:IsA("Texture") then c:Destroy() end -- strip anything a shirt tried to paint on
	end

	local char = torso.Parent
	local shirt = char and char:FindFirstChildOfClass("Shirt")
	local id = shirt and shirt.ShirtTemplate and tostring(shirt.ShirtTemplate):match("%d+") or nil
	local bodyColors = char and char:FindFirstChildOfClass("BodyColors")
	local base = (bodyColors and bodyColors.TorsoColor3) or torso.Color or SKIN_FALLBACK
	if id and SHIRT_COLORS[id] then base = SHIRT_COLORS[id] end

	gut.Color = base; gut.Material = Enum.Material.SmoothPlastic
	local function paint(name, mult)
		local p = gut:FindFirstChild(name)
		if p then p.Color = tintOf(base, mult); p.Material = Enum.Material.SmoothPlastic end
	end
	paint("Sag", 0.85)   -- underside ~15% darker
	paint("Sheen", 1.10) -- front highlight, a touch lighter
	paint("Navel", 0.55) -- belly button, clearly darker
end

local function buildGut(torso)
	local folder = Instance.new("Model"); folder.Name = "GutBelly"
	local gut = Instance.new("Part")
	gut.Name = "Gut"
	gut.Shape = Enum.PartType.Ball          -- a real ball: always renders, never needs a mesh to load
	gut.Material = Enum.Material.SmoothPlastic
	gut.Massless = true; gut.CanCollide = false; gut.CanQuery = false; gut.CanTouch = false; gut.CastShadow = false
	smoothAllFaces(gut)
	gut.Size = BASE
	gut.Parent = folder
	local w = Instance.new("Weld")
	w.Name = "GutWeld"; w.Part0 = torso; w.Part1 = gut; w.C0 = computeC0(torso, BASE); w.Parent = gut
	buildDetail(gut, "Sag",   Enum.PartType.Ball)
	buildDetail(gut, "Sheen", Enum.PartType.Ball)
	buildDetail(gut, "Navel", Enum.PartType.Cylinder)
	styleGut(gut, BASE)
	folder.Parent = torso
	applyGutAppearance(folder)
	return folder
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

local function ensureGut(char)
	local torso = torsoOf(char); if not torso then return nil end
	return torso:FindFirstChild("GutBelly") or buildGut(torso)
end

local function sizeGut(char, maxPower)
	local folder = ensureGut(char); if not folder then return end
	applyGutAppearance(folder)
	applyScale(folder, tierScale(maxPower))
end

--==================== STOMACH MAX: FIND IT, THEN WATCH IT ====================
-- Returns the current value, and (if it lives in something watchable) connects `onChange` so the belly can
-- grow the instant the player buys a bigger gut instead of waiting for a respawn.
local function bindMax(player, onChange)
	local ls = player:FindFirstChild("leaderstats")
	local sm = ls and ls:FindFirstChild("StomachMax")
	if sm and sm:IsA("ValueBase") then
		sm.Changed:Connect(function(v) onChange(tonumber(v) or START_MAX) end)
		return tonumber(sm.Value) or START_MAX
	end
	-- attribute form
	local a = player:GetAttribute("StomachMax")
	player:GetAttributeChangedSignal("StomachMax"):Connect(function()
		onChange(tonumber(player:GetAttribute("StomachMax")) or START_MAX)
	end)
	if tonumber(a) then return tonumber(a) end
	-- leaderstats may simply not exist yet on join -- wait briefly for it, then re-bind
	task.spawn(function()
		local waited = 0
		while waited < 15 and player.Parent do
			task.wait(0.5); waited += 0.5
			local ls2 = player:FindFirstChild("leaderstats")
			local sm2 = ls2 and ls2:FindFirstChild("StomachMax")
			if sm2 and sm2:IsA("ValueBase") then
				sm2.Changed:Connect(function(v) onChange(tonumber(v) or START_MAX) end)
				onChange(tonumber(sm2.Value) or START_MAX)
				return
			end
		end
	end)
	return START_MAX
end

local function hook(player)
	local current = START_MAX
	local function reapply(v)
		current = v or current
		local char = player.Character
		if char then pcall(sizeGut, char, current) end
	end
	current = bindMax(player, reapply)

	local function onChar(char)
		task.wait(SETTLE) -- let the rig + torso load before welding to it
		if char.Parent then pcall(sizeGut, char, current) end
		-- Re-apply once the body colours have finished loading. On a bare spawn BodyColors can arrive a beat
		-- after the torso, so the first paint would take the default grey and keep it.
		task.delay(1.5, function()
			local t = char.Parent and torsoOf(char)
			local f = t and t:FindFirstChild("GutBelly")
			if f then pcall(applyGutAppearance, f) end
		end)
	end
	if player.Character then task.spawn(onChar, player.Character) end
	player.CharacterAdded:Connect(onChar)
end

Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do hook(p) end

print("[Belly] portable gut belly active. Tier size progression (rank: name maxPower scale -> size):")
for i, s in ipairs(TIER_SCALE) do
	local sz = gutSize(s)
	print(("  %d: %-9s maxPower=%-5d scale=%.2f -> size=(%.2f, %.2f, %.2f)")
		:format(i, TIER_NAMES[i], TIERS[i], s, sz.X, sz.Y, sz.Z))
end
