--[[
	DevAuraFX.client.luau  (StarterPlayerScripts.DevAuraFX)

	The MOVING half of the dev aura: two counter-rotating orbit rings of glowing orbs around any player
	tagged with the DevAura attribute. The static half (outline, ground halo, sparkles, trail, crown, light)
	is built server-side by DevArrival so it replicates once and is done.

	=== WHY THIS IS A CLIENT SCRIPT ===
	Orbiting needs a new CFrame every frame. On the server that is a property change per part, per frame,
	replicated to every client, forever -- 20 parts x 60fps x every player in the server, permanently, just
	for decoration. Here it is local: the server sends ONE attribute, and each machine draws the motion
	itself at whatever framerate it happens to be running.

	Everyone still sees the orbs on everyone else, because every client runs this for every tagged player.
	The parts are created locally, so they never replicate and never touch the network again.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ATTR = "DevAura"

local RING_ORBS = 10     -- orbs per ring
local RING_RADIUS = 4.2
local ORB_SIZE = 0.42
local SPIN_A = 1.5       -- radians/sec, ring A
local SPIN_B = -1.05     -- ring B counter-rotates, and slower, so the two never look locked together
local TILT_A = math.rad(18)
local TILT_B = math.rad(74)

local GOLD = Color3.fromRGB(255, 210, 74)
local LIME = Color3.fromRGB(126, 217, 87)
local CYAN = Color3.fromRGB(120, 220, 255)
local CYCLE = { GOLD, LIME, CYAN }

-- One container for every dev's orbs. Parented to Workspace (not the character) so a respawn cannot take
-- the parts with it mid-frame while the loop is reading them.
local root = Instance.new("Folder")
root.Name = "DevAuraFX_Local"
root.Parent = Workspace

local rigs = {} -- [player] = { orbs = {…}, folder = Folder }

local function makeOrb(colour, size)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(size, size, size)
	p.Color = colour
	p.Material = Enum.Material.Neon
	p.Anchored = true          -- driven by CFrame; unanchored would fall and fight the physics solver
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 0.1
	return p
end

local function buildRig(player)
	if rigs[player] then return rigs[player] end

	local folder = Instance.new("Folder")
	folder.Name = "Aura_" .. player.Name
	folder.Parent = root

	local orbs = {}
	for ring = 1, 2 do
		for i = 1, RING_ORBS do
			local t = (i - 1) / RING_ORBS
			-- Stagger the colours around each ring so it reads as a gradient in motion rather than a
			-- flat-coloured hoop.
			local orb = makeOrb(CYCLE[((i - 1) % #CYCLE) + 1], ring == 1 and ORB_SIZE or ORB_SIZE * 0.75)
			orb.Parent = folder
			orbs[#orbs + 1] = {
				part = orb,
				ring = ring,
				phase = t * math.pi * 2,
			}
		end
	end

	local rig = { folder = folder, orbs = orbs }
	rigs[player] = rig
	return rig
end

local function destroyRig(player)
	local rig = rigs[player]
	if not rig then return end
	rigs[player] = nil
	if rig.folder then rig.folder:Destroy() end
end

local function refresh(player)
	if player:GetAttribute(ATTR) then
		buildRig(player)
	else
		destroyRig(player)
	end
end

local function watch(player)
	refresh(player)
	player:GetAttributeChangedSignal(ATTR):Connect(function() refresh(player) end)
end

for _, p in ipairs(Players:GetPlayers()) do watch(p) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(destroyRig)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for player, rig in pairs(rigs) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			-- Dead or still streaming in: park the orbs out of sight rather than destroying the rig, so a
			-- respawn does not have to rebuild 20 parts.
			for _, o in ipairs(rig.orbs) do
				if o.part.Transparency < 1 then o.part.Transparency = 1 end
			end
		else
			local centre = hrp.Position + Vector3.new(0, 0.4, 0)
			for _, o in ipairs(rig.orbs) do
				local spin = (o.ring == 1) and SPIN_A or SPIN_B
				local tilt = (o.ring == 1) and TILT_A or TILT_B
				local a = o.phase + now * spin
				-- Circle in the ring's own plane, then tilt that plane about X so the two rings cross.
				local flat = Vector3.new(math.cos(a) * RING_RADIUS, 0, math.sin(a) * RING_RADIUS)
				local tilted = CFrame.Angles(tilt, 0, 0):VectorToWorldSpace(flat)
				o.part.CFrame = CFrame.new(centre + tilted)
				if o.part.Transparency ~= 0.1 then o.part.Transparency = 0.1 end
			end
		end
	end
end)

print("[DevAuraFX] ready -- orbit rings render locally for any player tagged " .. ATTR)
