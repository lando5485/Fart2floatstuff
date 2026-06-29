--======================================================================
-- Eyes_AllInOne.client.lua  (LocalScript)
--======================================================================
-- EXACTLY how the game's pet eyes are MADE + how they BLINK, lifted VERBATIM:
--   * CONSTRUCTION  -- the standard eyes() helper from PetSystem.server.lua
--     (the SAME eyes on every pet): each eye is one big FLAT matte-black DISC
--     (a thin cylinder -> a disc facing +X, never a bulging sphere) whose back
--     embeds into the face and whose front sits just proud, plus a small flat
--     white sparkle disc on the upper-front.
--   * BLINK         -- the eye-squash from animatePet (PetFollow.client.lua):
--     parts named "Eye"/"Highlight" are flagged eye=true; every ~2-5s the eye
--     SQUASHES vertically (Size.Y -> ~15% then back) over 0.16s, then schedules
--     the next blink at a random 1.8-5.2s.
--
-- This demo builds a little head with the real eyes a few studs in front of you
-- and blinks them forever. Drop into StarterPlayer > StarterPlayerScripts.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- ============================================================================
-- PART HELPER (matte plastic, all faces Smooth -- like the game)
-- ============================================================================
local SMOOTH = Enum.SurfaceType.Smooth
local CYL, BAL = Enum.PartType.Cylinder, Enum.PartType.Ball
local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
	local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
	p.CFrame = cf
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
	p.Parent = model
	return p
end

-- ============================================================================
-- 1) HOW THE EYES ARE MADE  (VERBATIM from PetSystem.server.lua)
-- ============================================================================
-- Each eye is a big FLAT black disc (a thin cylinder -> flat, never a bulging
-- sphere) whose BACK embeds into the face surface and whose FRONT sits just
-- proud (no gap, no float), plus a small FLAT white sparkle disc on the
-- upper-front. A cylinder's circular faces point along its LOCAL X, so an
-- un-rotated thin cylinder IS a disc facing +X (the front). `fx` = eye CENTRE
-- (set per pet so the disc backs into THAT pet's face), `fy` height, `fz` lateral spread.
-- Named Eye/Highlight so the client blink squashes them together.
local EYE_DIA = 0.82  -- ONE standard eye size for the whole game (the armadillo's eye)
local function eyes(P, fx, fy, fz)
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = fz * sgn
		P("Eye", CYL, 0.22, EYE_DIA, EYE_DIA, Color3.fromRGB(16,16,20), fx, fy, zc)                        -- big flat matte-black disc (back embedded, front proud)
		P("Highlight", CYL, 0.12, EYE_DIA*0.34, EYE_DIA*0.34, Color3.fromRGB(255,255,255), fx + 0.16, fy + EYE_DIA*0.22, zc + EYE_DIA*0.16) -- flat white sparkle on the eye
	end
end

-- ============================================================================
-- 2) HOW THEY BLINK  (VERBATIM eye logic from animatePet, PetFollow.client.lua)
-- ============================================================================
-- The animator keeps a per-model A = { blink = <seconds until next blink> }. Each
-- frame it counts down; when it crosses 0 the eye SQUASHES for 0.16s (close then
-- open), then schedules the next blink 1.8 + rand*3.4 seconds out. Parts flagged
-- eye=true get their Size.Y multiplied by eyeY (1 = open, ~0.15 = shut).
local function stepBlink(A, dt)
	A.blink = A.blink - dt
	local eyeY = 1
	if A.blink <= 0 then
		local since = -A.blink
		if since < 0.16 then
			eyeY = 1 - 0.85 * (1 - math.abs((since / 0.16) * 2 - 1)) -- close then open (triangle over 0.16s)
		else
			A.blink = 1.8 + math.random() * 3.4 -- schedule the next blink (1.8 - 5.2s)
		end
	end
	-- apply: squash every eye part's vertical size; keep its base CFrame
	for _, e in ipairs(A.parts) do
		if e.eye then
			e.part.Size = Vector3.new(e.baseSize.X, e.baseSize.Y * eyeY, e.baseSize.Z)
			e.part.CFrame = A.rootCF * e.base -- hold its placement on the face
		end
	end
end

-- ============================================================================
-- DEMO: a small head wearing the real eyes, blinking in front of you.
-- ============================================================================
local model = Instance.new("Model"); model.Name = "EyesDemo"
-- a face to mount the eyes on (the eyes back INTO this surface, exactly like a pet head)
local head = mkPart(model, "Head", BAL, 3, 3, 3, Color3.fromRGB(139,195,74), 0,0,0)
model.PrimaryPart = head

-- build the eyes. P closure matches the server signature: P(name, shape, sx,sy,sz, color, x,y,z, rot)
-- and records each part so the blink can find the eyes (eye=true on Eye/Highlight, like registerClonedTemplate).
local A = { blink = 1.5, parts = {} }
local function P(name, shape, sx, sy, sz, color, x, y, z, rot)
	local p = mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
	local isEye = (name == "Eye" or name == "Highlight")
	A.parts[#A.parts+1] = { part = p, base = head.CFrame:ToObjectSpace(p.CFrame), baseSize = p.Size, eye = isEye }
	return p
end
-- fx 1.62 = sit on the +X face of a radius-1.5 head (back embeds ~0.11, front proud ~0.11); fy 0.5 up; fz 0.62 spread
eyes(P, 1.62, 0.5, 0.62)

model.Parent = Workspace

-- park it ~10 studs in front of the player, then blink forever
local function place()
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	local base = hrp and (hrp.CFrame * CFrame.new(0, 0, -10) * CFrame.Angles(0, math.rad(-90), 0)) or CFrame.new(0, 5, 0)
	model:PivotTo(base) -- +X (the eyes' front) turned to face the player
end
place()

RunService.RenderStepped:Connect(function(dt)
	if not model.Parent or not head.Parent then return end
	A.rootCF = head.CFrame
	stepBlink(A, dt)
end)

print("[Eyes] standard flat-disc eyes built + blinking in front of you")
