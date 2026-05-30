--======================================================================
-- UFOAbduction.lua  (ModuleScript)
--======================================================================
-- The abduction logic for the global "UFO" event (SERVER-authoritative).
--
-- This module owns the NON-player abductees and the inside-UFO chamber:
--   * It scans a beam's ground column for nearby ABDUCTABLE objects (NPC
--     rigs, props, beans, signs, loose items), spawns lightweight stand-in
--     clones of them, and lifts the clones up the beam with a slight spin
--     plus a floating "screaming" label. Capped at CONFIG.MAX_ABDUCTEES.
--     (We lift CLONES, never the real gameplay objects, so the islands are
--     never permanently altered; the originals are briefly hidden and fully
--     restored on cleanup.)
--   * One NPC dramatically CLINGS to the ground (a comedic stretch) instead
--     of rising.
--   * It owns the ENCLOSED inside-UFO chamber Model (built once in the sky,
--     destroyed on reset). The PLAYER teleport into/out of that chamber is
--     done on the affected CLIENT (UFOUI) using a capture/restore CFrame --
--     this module only provides the chamber's spawn CFrame on request.
--   * The optional GOLDEN-UFO coin reward is awarded HERE (the only
--     leaderstat touch in the whole event), and is modest + zeroable.
--
-- SAFETY: server only moves CLONE props (never players, never the real
-- island objects). All lifted clones are tracked and returned/destroyed on
-- cleanup -- the islands look exactly as before. No gameplay state is read
-- or written other than the optional, modest, zeroable Coins reward.
--======================================================================

local UFOAbduction = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Wired by init().
local CONFIG = nil
local UFOSync = nil

-- State.
local abductFolder = nil    -- holds lifted clone props + screaming labels
local insideFolder = nil    -- holds the enclosed inside-UFO chamber
local insideChamberCF = nil -- spawn CFrame inside the chamber (for clients)
local lifted = {}           -- active abductees: { clone, originalHidden, conn }
local clingNPC = nil        -- the one dramatic ground-clinger { clone, conn }
local liftConn = nil        -- Heartbeat driving all clone lifts
local liftedCount = 0       -- how many clones are currently lifted (cap guard)

-- Funny "screaming" strings shown over abducted objects.
local SCREAMS = { "AAAAA!", "HELP!", "NOOO!", "MOOO!", "TAKE ME!", "WHY ME?!", "BEAM OFF!", "\u{1F628}" }

--------------------------------------------------------------------
-- init(config, syncEvent): wire shared dependencies.
--------------------------------------------------------------------
function UFOAbduction.init(config, syncEvent)
	CONFIG = config
	UFOSync = syncEvent
end

--------------------------------------------------------------------
-- ensureFolder(): fresh folder for lifted clone props.
--------------------------------------------------------------------
local function ensureFolder()
	if not abductFolder or not abductFolder.Parent then
		abductFolder = Instance.new("Folder")
		abductFolder.Name = "UFOEventAbductees"
		abductFolder.Parent = workspace
	end
	return abductFolder
end

--------------------------------------------------------------------
-- makeScreamLabel(adornee): a floating BillboardGui "scream" over an object.
--------------------------------------------------------------------
local function makeScreamLabel(adornee)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Scream"
	bb.Size = UDim2.new(0, 90, 0, 40)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = adornee
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lbl.TextStrokeTransparency = 0
	lbl.TextScaled = true
	lbl.Font = Enum.Font.LuckiestGuy
	lbl.Text = SCREAMS[math.random(1, #SCREAMS)]
	lbl.Parent = bb
	bb.Parent = adornee
	return bb
end

--------------------------------------------------------------------
-- candidateObjects(groundPos, radius): find abductable objects near a beam.
-- We look for small Models/Parts that are clearly props (NOT players, NOT
-- the island terrain, NOT our own event folders). Returns a list of parts
-- we will clone-and-lift. This is intentionally conservative.
--------------------------------------------------------------------
local function candidateObjects(groundPos, radius)
	local found = {}
	-- Iterate top-level workspace models near the beam's ground column (a
	-- brief, cheap scan; no Region3 voxel read needed).
	local skipFolders = {
		UFOEvent = true, UFOEventBeams = true, UFOEventAbductees = true,
		UFOEventInside = true, MeteorStormMeteors = true, MeteorStormImpacts = true,
		MeteorStormRewards = true, RocketEventEffects = true,
	}
	for _, inst in ipairs(workspace:GetChildren()) do
		-- Skip players, our folders, and the big island models themselves.
		if inst:IsA("Model") and not skipFolders[inst.Name]
			and not Players:GetPlayerFromCharacter(inst)
			and inst.Name:sub(1, 7) ~= "Island_" then
			local ok, cf, size = pcall(function() return inst:GetBoundingBox() end)
			if ok and cf and size then
				-- Only smallish props (skip huge structures), within radius.
				local maxDim = math.max(size.X, size.Y, size.Z)
				local horiz = Vector3.new(cf.Position.X - groundPos.X, 0, cf.Position.Z - groundPos.Z).Magnitude
				if maxDim <= 24 and horiz <= radius and math.abs(cf.Position.Y - groundPos.Y) <= 60 then
					table.insert(found, inst)
				end
			end
		end
	end
	return found
end

--------------------------------------------------------------------
-- buildFallbackProp(pos, variant): if no real props are nearby, spawn a fun
-- generic abductee (a cow / barrel / bean) so the beam always has something.
--------------------------------------------------------------------
local function buildFallbackProp(pos)
	local kinds = {
		{ name = "Cow",    color = Color3.fromRGB(235, 235, 235), size = Vector3.new(4, 3, 6) },
		{ name = "Barrel", color = Color3.fromRGB(120, 80, 40),  size = Vector3.new(3, 4, 3) },
		{ name = "Bean",   color = Color3.fromRGB(90, 200, 90),  size = Vector3.new(2, 3, 2) },
		{ name = "Sign",   color = Color3.fromRGB(160, 120, 70), size = Vector3.new(4, 4, 0.5) },
	}
	local k = kinds[math.random(1, #kinds)]
	local p = Instance.new("Part")
	p.Name = "Abductee_" .. k.name
	p.Material = Enum.Material.SmoothPlastic
	p.Color = k.color
	p.Size = k.size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CFrame = CFrame.new(pos + Vector3.new(0, k.size.Y / 2, 0))
	return p
end

--------------------------------------------------------------------
-- startLiftLoop(): one Heartbeat that drives every lifted clone upward with
-- a slight spin toward its hold point. Started lazily, stopped in cleanup.
--------------------------------------------------------------------
local function startLiftLoop()
	if liftConn then return end
	liftConn = RunService.Heartbeat:Connect(function(dt)
		for _, a in ipairs(lifted) do
			if a.clone and a.clone.Parent and a.holdY then
				local cf = a.clone:GetPivot()
				local pos = cf.Position
				-- Rise toward holdY, then bob gently at the top.
				local targetY = a.holdY
				local newY = pos.Y
				if pos.Y < targetY then
					newY = math.min(targetY, pos.Y + a.riseSpeed * dt)
				else
					newY = targetY + math.sin(os.clock() * 1.5 + a.phase) * 2
				end
				-- Slight spin as it rises.
				a.spin = (a.spin or 0) + math.rad(CONFIG.ABDUCTEE_SPIN_RATE) * dt
				a.clone:PivotTo(CFrame.new(a.baseX, newY, a.baseZ) * CFrame.Angles(0, a.spin, 0))
			end
		end
		-- The clinging NPC stretches comically toward the beam but stays anchored.
		if clingNPC and clingNPC.clone and clingNPC.clone.Parent then
			local t = os.clock()
			clingNPC.clone.CFrame = clingNPC.baseCF
				* CFrame.new(0, math.abs(math.sin(t * 4)) * 1.5, 0) -- bounces trying to hold on
		end
	end)
end

--======================================================================
-- scanBeam(groundPos, radius, ufoPos, variant): lift a couple of nearby
-- objects up THIS beam (server-moved clones). Respects MAX_ABDUCTEES.
--======================================================================
function UFOAbduction.scanBeam(groundPos, radius, ufoPos, variant)
	if liftedCount >= CONFIG.MAX_ABDUCTEES then return end
	local folder = ensureFolder()

	-- How high the clones rise: toward the UFO, capped to ABDUCT_LIFT_HEIGHT
	-- above the ground so they never reach a higher island.
	local holdY = groundPos.Y + CONFIG.ABDUCT_LIFT_HEIGHT
	if ufoPos then
		holdY = math.min(holdY, ufoPos.Y - CONFIG.UFO_DIAMETER * 0.15)
	end

	local candidates = candidateObjects(groundPos, radius)

	-- Lift up to a small number per beam, staying under the global cap.
	local perBeam = math.min(2, CONFIG.MAX_ABDUCTEES - liftedCount)
	for _ = 1, perBeam do
		local clone
		if #candidates > 0 then
			local idx = math.random(1, #candidates)
			local original = candidates[idx]
			table.remove(candidates, idx)
			-- Clone the real prop and HIDE the original briefly so the island
			-- visibly "loses" it. The original is restored on cleanup.
			local ok, c = pcall(function() return original:Clone() end)
			if ok and c then
				-- Anchor + decollide every part so the clone floats cleanly.
				for _, d in ipairs(c:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
					end
				end
				c.Parent = folder
				clone = c
				-- Hide the original (do NOT destroy -- restored on cleanup).
				original:SetAttribute("UFOHiddenOrig", true)
				for _, d in ipairs(original:GetDescendants()) do
					if d:IsA("BasePart") and not d:GetAttribute("UFOWasTransparent") then
						d:SetAttribute("UFOSavedTransparency", d.Transparency)
						d.Transparency = 1
					end
				end
				table.insert(lifted, { clone = clone, original = original })
			end
		end
		if not clone then
			-- No real prop available: spawn a fun fallback abductee.
			clone = buildFallbackProp(groundPos
				+ Vector3.new((math.random() - 0.5) * radius, 0, (math.random() - 0.5) * radius))
			clone.Parent = folder
			table.insert(lifted, { clone = clone })
		end

		-- Configure this clone's lift in the shared loop.
		local entry = lifted[#lifted]
		local startCF = clone:GetPivot()
		entry.baseX = startCF.Position.X
		entry.baseZ = startCF.Position.Z
		entry.holdY = holdY
		entry.phase = math.random() * 6
		entry.spin = 0
		entry.riseSpeed = CONFIG.ABDUCT_LIFT_HEIGHT / CONFIG.ABDUCTEE_LIFT_TIME

		-- Floating "screaming" label.
		local adornee = clone:IsA("Model") and (clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart"))
			or clone
		if adornee then makeScreamLabel(adornee) end

		liftedCount = liftedCount + 1
		if liftedCount >= CONFIG.MAX_ABDUCTEES then break end
	end

	-- Spawn the single dramatic ground-clinger once per event (a comedic prop
	-- that bounces trying to resist instead of rising).
	if not clingNPC then
		local p = buildFallbackProp(groundPos + Vector3.new(radius * 0.4, 0, 0))
		p.Name = "ClingingNPC"
		p.Color = Color3.fromRGB(255, 200, 120)
		p.Parent = folder
		makeScreamLabel(p)
		clingNPC = { clone = p, baseCF = p.CFrame }
	end

	startLiftLoop()
end

--======================================================================
-- getInsideChamberCF(): build the enclosed inside-UFO chamber (once) in the
-- sky and return a SPAWN CFrame inside it. The chamber has solid walls +
-- floor + ceiling so a player teleported in cannot walk/fly out to a higher
-- island; UFOUI handles the per-player teleport in/out + the forced return.
--======================================================================
function UFOAbduction.getInsideChamberCF()
	if insideChamberCF and insideFolder and insideFolder.Parent then
		return insideChamberCF
	end

	insideFolder = Instance.new("Folder")
	insideFolder.Name = "UFOEventInside"
	insideFolder.Parent = workspace

	-- Put the chamber FAR off to the side + very high, away from any island
	-- column, so even if something went wrong a player couldn't land on a
	-- real island from here. (They are force-returned by CFrame anyway.)
	local center = Vector3.new(20000, 20000, 20000)
	insideChamberCF = CFrame.new(center + Vector3.new(0, 3, 0))

	-- Build a sealed box: floor, ceiling, 4 walls. All anchored + collidable
	-- so the player is genuinely ENCLOSED (can't escape to a higher island).
	local roomSize = 60
	local wallT = 2
	local function box(name, size, cf, color, collide, neon)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Anchored = true
		p.CanCollide = collide
		p.Material = neon and Enum.Material.Neon or Enum.Material.Metal
		p.Color = color
		p.Parent = insideFolder
		return p
	end
	-- Floor + ceiling.
	box("Floor", Vector3.new(roomSize, wallT, roomSize),
		CFrame.new(center), Color3.fromRGB(40, 50, 60), true)
	box("Ceiling", Vector3.new(roomSize, wallT, roomSize),
		CFrame.new(center + Vector3.new(0, roomSize, 0)), Color3.fromRGB(30, 40, 50), true)
	-- 4 walls.
	local half = roomSize / 2
	box("WallN", Vector3.new(roomSize, roomSize, wallT),
		CFrame.new(center + Vector3.new(0, half, half)), Color3.fromRGB(35, 45, 55), true)
	box("WallS", Vector3.new(roomSize, roomSize, wallT),
		CFrame.new(center + Vector3.new(0, half, -half)), Color3.fromRGB(35, 45, 55), true)
	box("WallE", Vector3.new(wallT, roomSize, roomSize),
		CFrame.new(center + Vector3.new(half, half, 0)), Color3.fromRGB(35, 45, 55), true)
	box("WallW", Vector3.new(wallT, roomSize, roomSize),
		CFrame.new(center + Vector3.new(-half, half, 0)), Color3.fromRGB(35, 45, 55), true)

	-- Fun "experiment chamber" decor: a glowing central pod + green light.
	local pod = box("ExperimentPod", Vector3.new(6, 8, 6),
		CFrame.new(center + Vector3.new(0, 6, -15)), Color3.fromRGB(120, 255, 170), false, true)
	local podLight = Instance.new("PointLight")
	podLight.Color = Color3.fromRGB(120, 255, 170)
	podLight.Brightness = 4
	podLight.Range = 40
	podLight.Parent = pod

	return insideChamberCF
end

--======================================================================
-- awardGolden(player, amount): the ONLY leaderstat touch in the event.
-- Adds a flat, modest, zeroable coin bundle to the player's Coins (and
-- TotalCoinsEarned if present). Nothing else is touched.
--======================================================================
function UFOAbduction.awardGolden(player, amount)
	if not amount or amount <= 0 then return end
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	if coins then coins.Value = coins.Value + amount end
	local tce = ls:FindFirstChild("TotalCoinsEarned")
	if tce then tce.Value = tce.Value + amount end
	-- Client shows a small popup (presentation only).
	UFOSync:FireClient(player, "reward", { coins = amount })
end

--======================================================================
-- releaseAll(): return every lifted clone to its origin (restore originals),
-- and clear the clinger. Called at the end of ABDUCTION.
--======================================================================
function UFOAbduction.releaseAll()
	-- Restore each hidden original + drop the clones.
	for _, a in ipairs(lifted) do
		if a.clone and a.clone.Parent then
			a.clone:Destroy()
		end
		if a.original and a.original.Parent then
			a.original:SetAttribute("UFOHiddenOrig", nil)
			for _, d in ipairs(a.original:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("UFOSavedTransparency") ~= nil then
					d.Transparency = d:GetAttribute("UFOSavedTransparency")
					d:SetAttribute("UFOSavedTransparency", nil)
				end
			end
		end
	end
	lifted = {}
	liftedCount = 0
	if clingNPC and clingNPC.clone and clingNPC.clone.Parent then
		clingNPC.clone:Destroy()
	end
	clingNPC = nil
end

--======================================================================
-- cleanup(): full teardown -- return all abductees, destroy the inside
-- chamber + folders, disconnect the lift loop. No leaks.
--======================================================================
function UFOAbduction.cleanup()
	if liftConn then liftConn:Disconnect() liftConn = nil end
	UFOAbduction.releaseAll()
	if abductFolder and abductFolder.Parent then abductFolder:Destroy() end
	abductFolder = nil
	if insideFolder and insideFolder.Parent then insideFolder:Destroy() end
	insideFolder = nil
	insideChamberCF = nil
end

return UFOAbduction
