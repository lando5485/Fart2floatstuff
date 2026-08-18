--======================================================================
-- CarryView.client.luau
--======================================================================
-- DRAWS WHAT OTHER PLAYERS ARE CARRYING, AND THE TRACTOR THEY ARE DRIVING.
--
-- The other half of CarrySync.server.lua -- read that file first, it explains why this exists.
-- Short version: quests are per-player LocalScripts, so the bale stack you are hauling lives on
-- your screen only. To everyone else you are holding nothing. This puts a copy in their hands.
--
-- ============================ HOW TO USE IT ============================
-- From ANY quest script, at any time:
--
--     _G.CarrySay("balestack")   -- I picked something up: show it to everyone
--     _G.CarrySay(nil)           -- I put it down / delivered it / got in a boat
--
-- That is the whole API. It is a _G function and not a module ON PURPOSE: the quest files that
-- need it are up against Luau's 200-local ceiling (BrokenTractorQuest sits at 198), and a
-- `local CarryProps = require(...)` costs a register that file does not have. Calling through
-- _G costs none. It is also safe to call before this script has loaded -- see the stub below.
--
-- Repeats are free: CarrySay drops a message identical to the last one, so calling it every
-- frame from a state refresh is fine and sends nothing.
--
-- ============================ WHAT IT DRAWS ============================
-- SIMPLIFIED props, not the real ones. The quest's own radiator is a detailed model built for
-- a prop you hold at arm's length; what other people need is a radiator-shaped thing they can
-- identify from across a field, that costs nothing to have five of on screen. These are a
-- handful of blocks and cylinders each, and that is the right amount of detail for the job.
--
-- Everything here is Anchored, CanCollide false and CanQuery false. A carried prop must never
-- push a player off a ledge, block a raycast a quest is using to find the ground, or catch a
-- ProximityPrompt. It is scenery that happens to follow somebody.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local player = Players.LocalPlayer

local EVENT_NAME = "CarryFxEvent"

-- Nobody needs to see what a kid two islands down is holding, and the islands here are stacked
-- in one tower so "far away" is mostly straight up. Beyond this the prop is destroyed and
-- rebuilt when they come back -- the KIND is remembered, so nothing is lost by culling.
local RENDER_RANGE = 340

-- ============================================================================
-- THE STUB -- so a quest can call _G.CarrySay before this file has run
-- ============================================================================
-- Client scripts start in no guaranteed order. A quest that picks something up in its first
-- second would hit a nil _G.CarrySay and throw. This queues the last thing said instead, and
-- the real implementation below replays it.
local pendingSay = nil
if not _G.CarrySay then
	_G.CarrySay = function(kind) pendingSay = kind end
end
-- nobody is carrying anything yet, and a caller that polls this every frame must get a number
-- rather than an error while this file is still loading
if not _G.CarryCount then
	_G.CarryCount = function() return 0 end
end

-- ============================================================================
-- BUILD HELPERS
-- ============================================================================
local function p(model, name, size, cf, color, shape, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material or Enum.Material.SmoothPlastic
	if shape then part.Shape = shape end
	part.Parent = model
	return part
end

-- ⚠ A Cylinder's length runs along its LOCAL X -- Size.X is how long the barrel is and Y/Z are
-- its diameter. Every wheel, pipe and plug below is built through this, so that the axle points
-- the way the name says it does instead of the disc lying flat like a dropped coin.
local function cylX(model, name, len, dia, cf, color, material)
	return p(model, name, Vector3.new(len, dia, dia), cf, color, Enum.PartType.Cylinder, material)
end

-- upright cylinder: same shape, turned so the length runs along Y
local function cylY(model, name, len, dia, cf, color, material)
	return cylX(model, name, len, dia, cf * CFrame.Angles(0, 0, math.rad(90)), color, material)
end

-- the island19 palette, matched to BrokenTractorQuest so a ghost tractor is recognisably THE
-- tractor and not some other green machine
local GREEN_T = Color3.fromRGB( 78, 142,  56)
local GREEN_D = Color3.fromRGB( 54, 102,  40)
local YELLOW  = Color3.fromRGB(246, 202,  62)
local WHEAT   = Color3.fromRGB(226, 186,  86)
local WHEAT_D = Color3.fromRGB(190, 148,  60)
local IRON    = Color3.fromRGB( 84,  80,  84)
local IRON_D  = Color3.fromRGB( 58,  55,  60)
local TYRE    = Color3.fromRGB( 38,  36,  38)
local COPPER  = Color3.fromRGB(196, 128,  62)
local PORC    = Color3.fromRGB(242, 236, 222)
local LEATHER = Color3.fromRGB( 60,  48,  40)

-- ============================================================================
-- THE PROPS
-- ============================================================================
local function buildBaleStack(m)
	-- four on the bottom, one on top: the shape a kid actually stacks, and narrow enough that
	-- it does not swallow the person carrying it when seen from the front
	local function bale(name, cf)
		p(m, name, Vector3.new(1.9, 1.35, 1.6), cf, WHEAT, nil, Enum.Material.Grass)
		p(m, name .. "Twine", Vector3.new(1.95, 0.16, 0.2), cf * CFrame.new(0, 0.2, -0.45), WHEAT_D)
		p(m, name .. "Twine2", Vector3.new(1.95, 0.16, 0.2), cf * CFrame.new(0, 0.2, 0.45), WHEAT_D)
	end
	bale("B1", CFrame.new(-0.98, 0, -0.85))
	bale("B2", CFrame.new( 0.98, 0, -0.85))
	bale("B3", CFrame.new(-0.98, 0,  0.85))
	bale("B4", CFrame.new( 0.98, 0,  0.85))
	bale("B5", CFrame.new(0, 1.36, 0) * CFrame.Angles(0, math.rad(12), 0))
end

local function buildWheel(m)
	cylX(m, "Tyre", 0.95, 3.3, CFrame.new(0, 0, 0), TYRE)
	cylX(m, "Hub",  1.05, 1.5, CFrame.new(0, 0, 0), YELLOW)
	-- three treads is enough to tell it is rolling stock and not a barrel
	for i = 0, 2 do
		local a = math.rad(i * 120)
		p(m, "Tread" .. i, Vector3.new(1.0, 0.3, 0.45),
			CFrame.Angles(a, 0, 0) * CFrame.new(0, 1.55, 0), IRON_D)
	end
end

local function buildPlug(m)
	-- stood upright, terminal at the top: white ceramic, hex nut, threaded body, copper tip
	cylY(m, "Ceramic", 1.5, 0.55, CFrame.new(0,  0.55, 0), PORC, Enum.Material.Marble)
	cylY(m, "Terminal", 0.4, 0.3, CFrame.new(0,  1.45, 0), IRON, Enum.Material.Metal)
	cylY(m, "Hex",     0.55, 0.78, CFrame.new(0, -0.35, 0), IRON, Enum.Material.Metal)
	cylY(m, "Thread",  0.8, 0.44, CFrame.new(0, -1.0, 0), IRON_D, Enum.Material.Metal)
	p(m, "Tip", Vector3.new(0.14, 0.42, 0.14), CFrame.new(0, -1.55, 0), COPPER, nil, Enum.Material.Metal)
end

local function buildPiston(m)
	cylY(m, "Crown", 1.3, 1.35, CFrame.new(0, 0.75, 0), IRON, Enum.Material.Metal)
	cylY(m, "Ring",  0.14, 1.42, CFrame.new(0, 0.55, 0), IRON_D, Enum.Material.Metal)
	cylY(m, "Ring2", 0.14, 1.42, CFrame.new(0, 0.25, 0), IRON_D, Enum.Material.Metal)
	p(m, "Rod",  Vector3.new(0.42, 1.7, 0.5), CFrame.new(0, -0.7, 0), IRON, nil, Enum.Material.Metal)
	cylX(m, "BigEnd", 0.65, 0.95, CFrame.new(0, -1.6, 0), IRON_D, Enum.Material.Metal)
end

local function buildRadiator(m)
	p(m, "Core", Vector3.new(2.4, 2.5, 0.45), CFrame.new(0, 0, 0), IRON_D, nil, Enum.Material.DiamondPlate)
	p(m, "TankTop", Vector3.new(2.6, 0.45, 0.7), CFrame.new(0, 1.45, 0), IRON, nil, Enum.Material.Metal)
	p(m, "TankBot", Vector3.new(2.6, 0.45, 0.7), CFrame.new(0, -1.45, 0), IRON, nil, Enum.Material.Metal)
	cylY(m, "Cap", 0.35, 0.6, CFrame.new(0.7, 1.75, 0), COPPER, Enum.Material.Metal)
	-- four fins, not forty: at carrying distance the eye reads "grille", not a fin count
	for i = -1, 2 do
		p(m, "Fin" .. i, Vector3.new(2.3, 0.12, 0.6), CFrame.new(0, i * 0.62 - 0.3, 0), IRON)
	end
end

local function buildSteer(m)
	-- a ring, approximated: ten short blocks around a circle. A torus is not worth a mesh here.
	local R = 1.15
	for i = 0, 9 do
		local a = math.rad(i * 36)
		p(m, "Rim" .. i, Vector3.new(0.34, 0.34, 0.78),
			CFrame.Angles(0, 0, a) * CFrame.new(0, R, 0) * CFrame.Angles(math.rad(90), 0, 0), LEATHER)
	end
	for i = 0, 2 do
		p(m, "Spoke" .. i, Vector3.new(0.24, R, 0.22),
			CFrame.Angles(0, 0, math.rad(i * 120)) * CFrame.new(0, R * 0.5, 0), IRON)
	end
	cylX(m, "Boss", 0.5, 0.62, CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0), IRON_D, Enum.Material.Metal)
	cylX(m, "Column", 1.5, 0.3, CFrame.new(0, 0, 0.9) * CFrame.Angles(0, math.rad(90), 0), IRON, Enum.Material.Metal)
end

-- ---- HAND TOOLS ----------------------------------------------------------
-- These hang off the RIGHT HAND, not the root, because that is where their owner's copy is: the
-- Smores axe and the tunnel pickaxe are both welded to the hand so the arm's swing animation
-- carries them. Animations replicate, so a viewer's copy swings with the chop for free.
local function buildAxe(m)
	p(m, "Shaft", Vector3.new(0.22, 3.0, 0.22), CFrame.new(0, 0, 0), Color3.fromRGB(146, 102, 58), nil, Enum.Material.Wood)
	p(m, "Head",  Vector3.new(0.32, 0.9, 1.1), CFrame.new(0, 1.35, 0.35), IRON, nil, Enum.Material.Metal)
	p(m, "Blade", Vector3.new(0.16, 0.95, 0.45), CFrame.new(0, 1.35, 0.95), Color3.fromRGB(196, 198, 204), nil, Enum.Material.Metal)
	p(m, "Butt",  Vector3.new(0.28, 0.22, 0.28), CFrame.new(0, -1.45, 0), IRON_D)
end

-- A HANDHELD ROCK DRILL -- what the tunnel miner actually carries now. Same hold angle as the
-- pickaxe it replaced, so the arm animation and the offset below are unchanged.
local function buildDrill(m)
	p(m, "Body",    Vector3.new(0.62, 1.15, 0.85), CFrame.new(0, 0.55, 0),    Color3.fromRGB(224, 168, 44), nil, Enum.Material.Metal)
	p(m, "Motor",   Vector3.new(0.5, 0.62, 0.5),   CFrame.new(0, 0.55, -0.6), Color3.fromRGB(56, 60, 68),   nil, Enum.Material.Metal)
	p(m, "Grip",    Vector3.new(0.3, 0.9, 0.3),    CFrame.new(0, -0.2, 0),    Color3.fromRGB(38, 38, 42),   nil, Enum.Material.SmoothPlastic)
	p(m, "Trigger", Vector3.new(0.16, 0.3, 0.22),  CFrame.new(0, 0.05, 0.28), Color3.fromRGB(28, 28, 32),   nil, Enum.Material.SmoothPlastic)
	p(m, "Chuck",   Vector3.new(0.34, 0.34, 0.34), CFrame.new(0, 1.25, 0),    Color3.fromRGB(150, 152, 158), nil, Enum.Material.Metal)
	p(m, "Bit",     Vector3.new(0.18, 1.5, 0.18),  CFrame.new(0, 2.0, 0),     Color3.fromRGB(196, 198, 204), nil, Enum.Material.Metal)
	p(m, "Tip",     Vector3.new(0.24, 0.28, 0.24), CFrame.new(0, 2.75, 0),    Color3.fromRGB(120, 122, 128), nil, Enum.Material.Metal)
end

local function buildPickaxe(m)
	p(m, "Shaft", Vector3.new(0.22, 3.0, 0.22), CFrame.new(0, 0, 0), Color3.fromRGB(146, 102, 58), nil, Enum.Material.Wood)
	p(m, "Head",  Vector3.new(0.3, 0.34, 2.4), CFrame.new(0, 1.4, 0), IRON, nil, Enum.Material.Metal)
	p(m, "TipA",  Vector3.new(0.22, 0.26, 0.5), CFrame.new(0, 1.35, 1.35), Color3.fromRGB(196, 198, 204), nil, Enum.Material.Metal)
	p(m, "TipB",  Vector3.new(0.22, 0.26, 0.5), CFrame.new(0, 1.35, -1.35), Color3.fromRGB(196, 198, 204), nil, Enum.Material.Metal)
end

local function buildDynamite(m)
	-- a crate of it, matching TunnelBlast's own buildDynamiteCrate closely enough that nobody
	-- can tell the difference from more than a couple of studs away
	p(m, "Crate", Vector3.new(2.2, 1.8, 2.2), CFrame.new(0, 0, 0), Color3.fromRGB(146, 102, 58), nil, Enum.Material.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do
		p(m, "Band" .. sx, Vector3.new(2.3, 0.26, 2.3), CFrame.new(0, sx * 0.6, 0), Color3.fromRGB(60, 48, 40))
	end
	for i = -1, 1 do
		cylY(m, "Stick" .. i, 1.5, 0.4, CFrame.new(i * 0.45, 1.0, 0), Color3.fromRGB(184, 54, 46))
	end
	cylY(m, "Fuse", 0.7, 0.12, CFrame.new(0.45, 1.9, 0), Color3.fromRGB(232, 220, 190))
end

-- THE GHOST TRACTOR. Cut down from the real one in BrokenTractorQuest (same offsets, same
-- palette, a third of the parts) so a driver going past is unmistakably on the farm tractor.
-- Its origin is the drive frame, which is why the seat lands at (0, 1.9, 1.4) -- see TRACTOR_OFF.
local function buildTractor(m)
	p(m, "Chassis", Vector3.new(4.6, 1.6, 9.5), CFrame.new(0, -0.6, 0), GREEN_D)
	p(m, "Bonnet",  Vector3.new(4.0, 2.6, 5.0), CFrame.new(0, 0.9, -2.4), GREEN_T)
	p(m, "Grille",  Vector3.new(3.4, 1.8, 0.4), CFrame.new(0, 0.9, -4.9), IRON, nil, Enum.Material.DiamondPlate)
	p(m, "Exhaust", Vector3.new(0.6, 3.4, 0.6), CFrame.new(-1.3, 3.0, -3.6), IRON_D, nil, Enum.Material.Metal)
	p(m, "Cab",     Vector3.new(4.2, 0.6, 3.4), CFrame.new(0, 1.6, 1.4), GREEN_D)
	p(m, "SeatBack", Vector3.new(2.4, 2.2, 0.5), CFrame.new(0, 2.6, 2.6), LEATHER)
	p(m, "SeatBase", Vector3.new(2.4, 0.6, 2.0), CFrame.new(0, 1.6, 1.6), LEATHER)
	for _, sx in ipairs({ -1, 1 }) do
		p(m, "Fender" .. sx, Vector3.new(0.4, 2.6, 4.4), CFrame.new(sx * 2.5, 0.9, 1.8), YELLOW)
	end
	-- big at the back, small at the front, sitting on a ground plane 3.2 below the drive frame
	local function wheel(name, x, z, r)
		cylX(m, name, 1.2, r * 2, CFrame.new(x, -3.2 + r, z), TYRE)
		cylX(m, name .. "Hub", 1.3, r * 0.9, CFrame.new(x, -3.2 + r, z), YELLOW)
	end
	wheel("RL", -2.3,  2.1, 1.7); wheel("RR",  2.3,  2.1, 1.7)
	wheel("FL", -2.0, -3.4, 1.1); wheel("FR",  2.0, -3.4, 1.1)
end

-- ============================================================================
-- THE REGISTRY -- ids here MUST match CarrySync's whitelist or nothing appears
-- ============================================================================
-- `off` is where the prop sits relative to the holder's HumanoidRootPart. The two carry offsets
-- are copied from BrokenTractorQuest exactly, so what your friends see in your hands is in the
-- same place as what you see in your own -- and both are IN FRONT (-Z), because a root part
-- looks down its negative Z and carrying a radiator behind your back tells nobody anything.
local KINDS = {
	balestack   = { off = CFrame.new(0, 1.5, -3.2) * CFrame.Angles(math.rad(7), 0, math.rad(2)), build = buildBaleStack },
	part_wheel  = { off = CFrame.new(0, 1.3, -1.9) * CFrame.Angles(math.rad(14), 0, math.rad(-8)), build = buildWheel },
	part_plug   = { off = CFrame.new(0, 1.3, -1.9) * CFrame.Angles(math.rad(14), 0, math.rad(-8)), build = buildPlug },
	part_piston = { off = CFrame.new(0, 1.3, -1.9) * CFrame.Angles(math.rad(14), 0, math.rad(-8)), build = buildPiston },
	part_rad    = { off = CFrame.new(0, 1.3, -1.9) * CFrame.Angles(math.rad(14), 0, math.rad(-8)), build = buildRadiator },
	part_steer  = { off = CFrame.new(0, 1.3, -1.9) * CFrame.Angles(math.rad(14), 0, math.rad(-8)), build = buildSteer },

	-- ⚠ NOT AN OFFSET YOU MAY TUNE BY EYE. BrokenTractorQuest seats the driver with
	--       seatedHrp.CFrame = driveFrame() * CFrame.new(0, 1.9, 1.4)
	-- so the tractor's origin is exactly that translation inverted. Change one and change both,
	-- or the driver will float above the seat on every screen except their own.
	tractor     = { off = CFrame.new(0, -1.9, -1.4), build = buildTractor },

	-- `limb` hangs the prop off a body part instead of the root, and the offsets match the hold
	-- angle each quest welds its own copy at. The arm animation does the rest.
	axe      = { limb = "RightHand", off = CFrame.new(0, -0.35, 0) * CFrame.Angles(math.rad(-110), 0, math.rad(-10)), build = buildAxe },
	pickaxe  = { limb = "RightHand", off = CFrame.new(0, -0.35, 0) * CFrame.Angles(math.rad(-110), 0, math.rad(-10)), build = buildPickaxe },
	drill    = { limb = "RightHand", off = CFrame.new(0, -0.35, 0) * CFrame.Angles(math.rad(-110), 0, math.rad(-10)), build = buildDrill },
	dynamite = { limb = "RightHand", off = CFrame.new(0, -2.4, -0.4), build = buildDynamite },
}

-- ============================================================================
-- THE VIEWER
-- ============================================================================
local ev = ReplicatedStorage:WaitForChild(EVENT_NAME, 30)
if not ev then
	warn("[CarryView] no " .. EVENT_NAME .. " -- CarrySync.server.lua is not running; "
		.. "carried props will stay invisible to other players")
	return
end

local folder = Instance.new("Folder")
folder.Name = "CarriedProps"
folder.Parent = Workspace

local shown = {}          -- [player] = { kind = string, model = Model? }  (model is nil while culled)

local function clearModel(rec)
	if rec.model then
		rec.model:Destroy()
		rec.model = nil
	end
end

local function setKind(plr, kind)
	local rec = shown[plr]
	if not kind then
		if rec then clearModel(rec); shown[plr] = nil end
		return
	end
	if not KINDS[kind] then return end
	if rec then
		if rec.kind == kind then return end
		clearModel(rec)
		rec.kind = kind
	else
		shown[plr] = { kind = kind, model = nil }
	end
end

ev.OnClientEvent:Connect(function(plr, kind)
	-- YOUR OWN MESSAGES COME BACK TO YOU and must be ignored here, not filtered on the server.
	-- The quest already built the real, detailed prop in your hands; drawing this simplified one
	-- as well would put two radiators in the same fist.
	if plr == player then return end
	setKind(plr, kind)
end)

Players.PlayerRemoving:Connect(function(plr)
	local rec = shown[plr]
	if rec then clearModel(rec); shown[plr] = nil end
end)

RunService.RenderStepped:Connect(function()
	local myChar = player.Character
	local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
	for plr, rec in pairs(shown) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		-- DEAD OR GONE MEANS EMPTY-HANDED. Without the health test a stack of bales hangs in the
		-- air over a ragdoll until that player picks something else up.
		local live = hrp and hum and hum.Health > 0
			and (not myHrp or (hrp.Position - myHrp.Position).Magnitude <= RENDER_RANGE)
		if live then
			local def = KINDS[rec.kind]
			if not rec.model and def then
				local m = Instance.new("Model")
				m.Name = "Carry_" .. plr.Name .. "_" .. rec.kind
				def.build(m)
				m.Parent = folder
				rec.model = m
			end
			if rec.model and def then
				-- WHERE IT HANGS. The root by default; a `limb` kind rides the hand instead, so
				-- it swings with the chop animation for free. R6 has no RightHand, so "Right Arm"
				-- is the fallback and the root is the last resort -- a tool in roughly the right
				-- place beats a tool that never appears at all.
				local anchorPart = hrp
				if def.limb then
					anchorPart = char:FindFirstChild(def.limb) or char:FindFirstChild("Right Arm") or hrp
				end
				rec.model:PivotTo(anchorPart.CFrame * def.off)
			end
		elseif rec.model then
			clearModel(rec)          -- keeps rec.kind, so it comes straight back when they do
		end
	end
end)

-- ============================================================================
-- THE SENDER
-- ============================================================================
local mySent = nil
_G.CarrySay = function(kind)
	if kind ~= nil and not KINDS[kind] then
		warn("[CarryView] unknown carry kind '" .. tostring(kind) .. "' -- add it to KINDS here "
			.. "AND to the whitelist in CarrySync.server.lua")
		return
	end
	if kind == mySent then return end     -- repeats are free, so quests may call this every frame
	mySent = kind
	ev:FireServer(kind)
end

-- HOW MANY *OTHER* PLAYERS ARE SHOWING THIS KIND RIGHT NOW.
-- `shown` never contains you -- your own messages are filtered on arrival -- so this answers
-- "is somebody ELSE doing that" without the caller having to know anything about the relay.
--
-- It exists for one-of-a-kind world objects. Island19's tractor is a real, hand-placed model
-- that every client sees parked in the field; when somebody drives, they drive THEIR copy, and
-- the parked one would otherwise sit there as a second tractor while a ghost one rolls past on
-- top of a kid. BrokenTractorQuest polls this and fades the parked one out while it is in use.
-- Any other shared prop with the same problem can do the same thing.
_G.CarryCount = function(kind)
	local n = 0
	for _, rec in pairs(shown) do
		if rec.kind == kind then n += 1 end
	end
	return n
end

-- DROPPING EVERYTHING ON DEATH is handled here rather than in each quest, because a quest that
-- errors halfway through dying would otherwise leave you holding a phantom bale stack forever.
player.CharacterAdded:Connect(function()
	mySent = nil
	ev:FireServer(nil)
end)

if pendingSay ~= nil then
	-- something was picked up before this script loaded; say it now
	local queued = pendingSay
	pendingSay = nil
	_G.CarrySay(queued)
end

print("[CarryView] ready -- other players' carried props and driven tractors are visible")
