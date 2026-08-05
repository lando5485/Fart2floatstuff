--======================================================================
-- HELD QUEST ITEM SYNC  (LocalScript, per-player)
--======================================================================
-- TWO JOBS, AND THEY ARE OPPOSITES:
--   1. PUBLISH what THIS player is holding, so everyone else can draw it.
--   2. DRAW what every OTHER player is holding.
--
-- The holder never draws from this script -- PetFollow already builds the real, interactive rod on their own
-- hand, with the line and the bobber and the casting. This is the spectator copy: geometry only, no logic.
-- Two scripts drawing a rod on the same hand would z-fight and double the parts for the one person who
-- definitely does not need it.
--
-- ===== WHY THE COPY IS BUILT LOCALLY INSTEAD OF REPLICATED =====
-- See HeldItemSync.server.lua. Short version: the rod is re-CFramed every frame, so replicating it would push
-- a transform per player per frame across the wire for pure decoration. One replicated string per player, and
-- each client draws its own, costs nothing and looks identical.
--======================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("HeldItemEvent", 30)

local ATTR = "HeldQuestItem"

--======================================================================
-- 1. PUBLISH
--======================================================================
-- PetFollow calls this the moment the rod is grabbed and again when the leash drops it. Exposed through _G
-- because that is how every cross-script channel in this codebase works (_G.isFlying, _G.hudHold,
-- _G.guideTrailTo, _G.petQuestGate) -- and because PetFollow is at Luau's 200-local-register ceiling, so it
-- cannot afford to hold a reference to anything new at its top level.
local lastSent = nil
_G.setHeldQuestItem = function(itemId)
	if itemId == lastSent then return end -- the rod loop can call this repeatedly; only send on change
	lastSent = itemId
	if remote then remote:FireServer(itemId) end
end

--======================================================================
-- 2. DRAW EVERYONE ELSE'S
--======================================================================
-- Geometry deliberately matches PetFollow's startHeldRod(), including the hand offset and the forward+up
-- lean, so the rod a spectator sees sits exactly where the holder sees their own.
local BUILDERS = {}

BUILDERS.FishingRod = function()
	local rod = Instance.new("Model"); rod.Name = "RemoteHeldRod"
	local function rp(name, shape, size, color, mat)
		local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic; p.Anchored = true; p.CanCollide = false
		p.CanQuery = false; p.CastShadow = false; p.Parent = rod; return p
	end
	local shaft = rp("Shaft", Enum.PartType.Cylinder, Vector3.new(6, 0.16, 0.16), Color3.fromRGB(110, 70, 40), Enum.Material.Wood)
	local grip  = rp("Grip",  Enum.PartType.Cylinder, Vector3.new(1.1, 0.26, 0.26), Color3.fromRGB(35, 30, 28))
	local reel  = rp("Reel",  Enum.PartType.Cylinder, Vector3.new(0.3, 0.7, 0.7), Color3.fromRGB(40, 40, 46), Enum.Material.Metal)
	rod.Parent = Workspace
	-- returns the model plus the per-frame poser, so the update loop below stays item-agnostic
	return rod, function(cf)
		shaft.CFrame = cf
		grip.CFrame  = cf * CFrame.new(-2.6, 0, 0)
		reel.CFrame  = cf * CFrame.new(-2.0, -0.35, 0) * CFrame.Angles(0, 0, math.rad(90))
	end
end

local shown = {} -- [player] = {model = Model, pose = function, id = string}

local function clear(who)
	local rec = shown[who]
	if not rec then return end
	if rec.model then rec.model:Destroy() end
	shown[who] = nil
end

RunService.Heartbeat:Connect(function()
	for _, other in ipairs(Players:GetPlayers()) do
		-- never draw for ourselves: the holder has the real one, with the line and the bobber
		if other ~= player then
			local id  = other:GetAttribute(ATTR)
			local rec = shown[other]

			if not id or not BUILDERS[id] then
				if rec then clear(other) end
			else
				if rec and rec.id ~= id then clear(other); rec = nil end -- swapped to a different item
				local char = other.Character
				local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
				local hrp  = char and char:FindFirstChild("HumanoidRootPart")
				if not (hand and hrp) then
					-- character streamed out or is mid-respawn; drop the copy rather than leave it floating at
					-- the last known spot, which is what a stale Anchored part does
					if rec then clear(other) end
				else
					if not rec then
						local model, pose = BUILDERS[id]()
						rec = {model = model, pose = pose, id = id}
						shown[other] = rec
					end
					local look = hrp.CFrame.LookVector; look = Vector3.new(look.X, 0, look.Z)
					if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
					local rodDir = (look.Unit + Vector3.new(0, 0.62, 0)).Unit
					local center = hand.Position + look.Unit * 0.4 + rodDir * 3.0
					rec.pose(CFrame.lookAt(center, center + rodDir) * CFrame.Angles(0, math.rad(90), 0))
				end
			end
		end
	end
	-- players who left keep an entry until something notices, and an Anchored part with no owner never moves
	-- again -- a rod hanging in mid-air where someone disconnected.
	for who in pairs(shown) do
		if who.Parent == nil then clear(who) end
	end
end)

Players.PlayerRemoving:Connect(clear)

print("[HeldItem] client ready -- other players' quest props render on their hands (fishing rod)")
