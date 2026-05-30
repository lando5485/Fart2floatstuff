--======================================================================
-- NPCMutationSystem.lua  (ModuleScript)
--======================================================================
-- Server-side NPC chaos for the global "MutationEvent". Mutates ambient
-- NPCs (the TutorialNPCs folder's humanoid models) for full comedic chaos:
-- grow huge / shrink tiny / run fast / bounce / glow green / scream, and a
-- rare "combine" where two NPCs temporarily merge into a giant mutant.
--
-- ★ HARD RULES ★
--   * CAPTURE + RESTORE: before changing ANY NPC value (scale, WalkSpeed,
--     part colors/materials, HipHeight, JumpPower) we SAVE the original, and
--     cleanup() restores every one. NO NPC is ever left mutated.
--   * CAPPED: at most CONFIG.MAX_MUTATED_NPCS NPCs mutated at once.
--   * VISUAL/MOVEMENT ONLY: we only tweak the NPC's own Humanoid + its parts.
--     We add NO collidable parts (glow is a PointLight + recolor, not a part).
--     We NEVER touch the player, the fart meter, power, flight, coins, food,
--     guts, island heights, or any other event.
--   * This module is server-authoritative; NPC changes replicate to clients.
--======================================================================

local NPCMutationSystem = {}

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Wired by init().
local CONFIG = nil
local Generator = nil

-- ★ EXCLUDED NPCs ★ -- the two bean-stand farmers placed by FarmerSpawner
-- (the tutorial "Farmer" and the decorative "Farmer2") must NEVER be mutated.
-- getNPCs() skips any model whose name is in this set, so the farmers can
-- never enter the `mutated` table via ANY path (mutateSome / combineTwo).
local EXCLUDED_NPC_NAMES = {
	["Farmer"] = true,
	["Farmer2"] = true,
}

-- State.
-- mutated[npcModel] = {
--   restoreAt   = os.clock() deadline to auto-revert this NPC,
--   originals   = { scale snapshot, walkSpeed, jumpPower, hipHeight, partLooks },
--   conns       = { connections to disconnect (bounce loop) },
--   extras      = { instances we added (PointLight, glow) to destroy },
--   id          = mutation id,
-- }
local mutated = {}
local mutatedCount = 0
local running = false
local tickConn = nil
-- baseline[model] = a full original snapshot of EVERY TutorialNPCs NPC (incl. the
-- farmers), taken at event start, used to RESTORE-ALL on event end so no NPC can be
-- left mutated even if something slipped through the per-mutation revert.
local baseline = {}

--------------------------------------------------------------------
-- init(config, generator): wire dependencies.
--------------------------------------------------------------------
function NPCMutationSystem.init(config, generator)
	CONFIG = config
	Generator = generator
end

--------------------------------------------------------------------
-- getNPCs(): READ-ONLY scan for ambient NPC models. We look in the known
-- TutorialNPCs folder (where FarmerNPC lives) for Models that have a
-- Humanoid + a HumanoidRootPart. We do NOT touch players. Returns a list.
--------------------------------------------------------------------
local function getNPCs()
	local list = {}
	local container = workspace:FindFirstChild("TutorialNPCs")
	if not container then return list end
	for _, m in ipairs(container:GetChildren()) do
		-- ★ Skip the bean-stand farmers entirely (never mutate them). ★
		if m:IsA("Model") and not EXCLUDED_NPC_NAMES[m.Name]
			and m:FindFirstChildOfClass("Humanoid") then
			local hrp = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
			if hrp then
				table.insert(list, m)
			end
		end
	end
	return list
end

--------------------------------------------------------------------
-- captureNPC(model): snapshot EVERYTHING we might change so we can restore it
-- exactly. Returns the originals table.
--------------------------------------------------------------------
local function captureNPC(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local originals = {
		walkSpeed = hum and hum.WalkSpeed,
		jumpPower = hum and hum.JumpPower,
		hipHeight = hum and hum.HipHeight,
		partLooks = {},                 -- [part] = { Color, Material, Transparency }
		bodyScales = {},                -- [scaleValue] = original Value (R15 humanoid scales)
	}
	-- Capture R15 body-scale NumberValues if present (BodyDepthScale etc.).
	if hum then
		for _, scaleName in ipairs({ "BodyDepthScale", "BodyHeightScale", "BodyWidthScale", "HeadScale" }) do
			local sv = hum:FindFirstChild(scaleName)
			if sv and sv:IsA("NumberValue") then
				originals.bodyScales[sv] = sv.Value
			end
		end
	end
	-- Capture every part's look so glow/recolor fully reverts.
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			originals.partLooks[part] = {
				Color = part.Color,
				Material = part.Material,
			}
		end
	end
	return originals
end

--------------------------------------------------------------------
-- restoreNPC(model): revert one mutated NPC fully + remove our extras +
-- disconnect its loops. Always safe.
--------------------------------------------------------------------
local function restoreNPC(model)
	local entry = mutated[model]
	if not entry then return end

	-- Disconnect any per-NPC loops (bounce).
	for _, conn in ipairs(entry.conns or {}) do
		if conn.Connected then conn:Disconnect() end
	end
	-- Destroy any added instances (glow lights, scream sounds).
	for _, inst in ipairs(entry.extras or {}) do
		if inst and inst.Parent then inst:Destroy() end
	end

	if model and model.Parent then
		local hum = model:FindFirstChildOfClass("Humanoid")
		local o = entry.originals or {}
		if hum then
			if o.walkSpeed ~= nil then hum.WalkSpeed = o.walkSpeed end
			if o.jumpPower ~= nil then hum.JumpPower = o.jumpPower end
			if o.hipHeight ~= nil then hum.HipHeight = o.hipHeight end
		end
		for sv, val in pairs(o.bodyScales or {}) do
			if sv and sv.Parent then sv.Value = val end
		end
		for part, look in pairs(o.partLooks or {}) do
			if part and part.Parent then
				part.Color = look.Color
				part.Material = look.Material
			end
		end
	end

	mutated[model] = nil
	mutatedCount = math.max(0, mutatedCount - 1)
end

--------------------------------------------------------------------
-- setScale(model, factor): scale an NPC by `factor`. Prefer R15 humanoid
-- body-scale NumberValues (clean + replicated); if absent, fall back to a
-- model:ScaleTo (Roblox built-in uniform scale). originals already captured.
--------------------------------------------------------------------
local function setScale(model, factor)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local applied = false
	if hum then
		for _, scaleName in ipairs({ "BodyDepthScale", "BodyHeightScale", "BodyWidthScale", "HeadScale" }) do
			local sv = hum:FindFirstChild(scaleName)
			if sv and sv:IsA("NumberValue") then
				sv.Value = sv.Value * factor
				applied = true
			end
		end
	end
	if not applied then
		-- Uniform model scale fallback (R6 / mesh rigs). ScaleTo scales about
		-- the pivot; we capture nothing extra because cleanup uses the inverse.
		pcall(function() model:ScaleTo(model:GetScale() * factor) end)
	end
end

--------------------------------------------------------------------
-- applyMutation(model, pick): apply one NPC mutation by id. CAPTURES first,
-- registers the entry, then applies. Returns true on success.
--------------------------------------------------------------------
local function applyMutation(model, pick)
	if not pick then return false end
	if mutated[model] then return false end              -- already mutated
	if mutatedCount >= CONFIG.MAX_MUTATED_NPCS then return false end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return false end

	local entry = {
		restoreAt = os.clock() + (pick.duration or 8),
		originals = captureNPC(model),
		conns = {},
		extras = {},
		id = pick.id,
	}
	mutated[model] = entry
	mutatedCount = mutatedCount + 1

	local id = pick.id
	if id == "grow" then
		setScale(model, CONFIG.NPC_GROW_FACTOR or 2)
	elseif id == "shrink" then
		setScale(model, CONFIG.NPC_SHRINK_FACTOR or 0.5)
	elseif id == "speed" then
		hum.WalkSpeed = (entry.originals.walkSpeed or 16) * (CONFIG.NPC_SPEED_FACTOR or 3)
	elseif id == "bounce" then
		-- Give the NPC a hop loop by nudging JumpPower + periodically jumping.
		hum.JumpPower = math.min((entry.originals.jumpPower or 50) * 1.4, CONFIG.NPC_BOUNCE_MAX_JUMP or 90)
		hum.UseJumpPower = true
		local nextHop = 0
		local conn = RunService.Heartbeat:Connect(function()
			if not model.Parent then return end
			if os.clock() >= nextHop then
				nextHop = os.clock() + 0.9
				pcall(function() hum.Jump = true end)
			end
		end)
		table.insert(entry.conns, conn)
	elseif id == "glow" then
		-- Recolor parts green + add a green PointLight on the root (no new part).
		for part in pairs(entry.originals.partLooks) do
			if part and part.Parent then
				part.Color = Color3.fromRGB(120, 255, 120)
				part.Material = Enum.Material.Neon
			end
		end
		local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		if hrp then
			local light = Instance.new("PointLight")
			light.Name = "MutationGlow"
			light.Color = Color3.fromRGB(120, 255, 120)
			light.Brightness = 3
			light.Range = 18
			light.Parent = hrp
			table.insert(entry.extras, light)
		end
	elseif id == "scream" then
		-- A short looping scream sound on the head (cosmetic). Auto-cleaned.
		local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
		if head then
			local s = Instance.new("Sound")
			s.Name = "MutationScream"
			s.SoundId = "rbxassetid://9112854440"
			s.Volume = 1   -- unified volume: matches the meteor intro sound
			s.Looped = true
			s.RollOffMaxDistance = 80
			s.Parent = head
			s:Play()
			table.insert(entry.extras, s)
		end
	end
	return true
end

--======================================================================
-- mutateSome(): pick a few not-yet-mutated NPCs and mutate them (up to the
-- cap). Called periodically by the manager during MAIN.
--======================================================================
function NPCMutationSystem.mutateSome()
	if not running then return end
	local npcs = getNPCs()
	-- Shuffle-ish: iterate from a random offset so it's not always the same NPCs.
	for _ = 1, #npcs do
		if mutatedCount >= CONFIG.MAX_MUTATED_NPCS then break end
		local model = npcs[math.random(1, #npcs)]
		if model and not mutated[model] then
			local pick = Generator and Generator.rollNPCMutation()
			applyMutation(model, pick)
		end
	end
end

--======================================================================
-- combineTwo(): rare chaos -> pick two free NPCs, grow one BIG (the "giant
-- mutant") and shrink/hide the other near it for a moment, both auto-revert.
-- Cheap; uses the same capture/restore path.
--======================================================================
function NPCMutationSystem.combineTwo()
	if not running then return end
	local free = {}
	for _, m in ipairs(getNPCs()) do
		if not mutated[m] then table.insert(free, m) end
	end
	if #free < 2 then return end
	if mutatedCount + 2 > CONFIG.MAX_MUTATED_NPCS then return end

	local a = table.remove(free, math.random(1, #free))
	local b = table.remove(free, math.random(1, #free))
	local dur = CONFIG.NPC_COMBINE_DURATION or 7

	applyMutation(a, { id = "grow", duration = dur })
	if mutated[a] then setScale(a, 1.6) end -- extra-giant on top of grow
	applyMutation(b, { id = "shrink", duration = dur })
	if mutated[b] then
		setScale(b, 0.6)
		-- Glow both for the mutant look.
		local hrp = a:FindFirstChild("HumanoidRootPart") or a.PrimaryPart
		if hrp then
			local light = Instance.new("PointLight")
			light.Name = "MutationGlow"
			light.Color = Color3.fromRGB(170, 90, 255)
			light.Brightness = 4; light.Range = 26
			light.Parent = hrp
			table.insert(mutated[a].extras, light)
		end
	end
end

--======================================================================
-- snapshotAll(): at event START, capture the ORIGINAL state of EVERY NPC in
-- TutorialNPCs (the farmers included). Restored verbatim on event end, so even
-- a slipped-through mutation can't leave any NPC altered. Captures: uniform
-- model scale (ScaleTo path), R15 body-scale values, Humanoid walk/jump/hip,
-- every part's Color/Material, and the primary part's CFrame (position).
--======================================================================
local function snapshotModel(model)
	local snap = { parts = {}, scaleVals = {} }
	local ok, s = pcall(function() return model:GetScale() end)
	snap.modelScale = ok and s or nil
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		snap.walkSpeed, snap.jumpPower, snap.hipHeight = hum.WalkSpeed, hum.JumpPower, hum.HipHeight
		for _, n in ipairs({ "BodyDepthScale", "BodyHeightScale", "BodyWidthScale", "HeadScale" }) do
			local sv = hum:FindFirstChild(n)
			if sv and sv:IsA("NumberValue") then snap.scaleVals[sv] = sv.Value end
		end
	end
	local prim = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if prim then snap.prim, snap.cframe = prim, prim.CFrame end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then snap.parts[p] = { Color = p.Color, Material = p.Material } end
	end
	return snap
end

function NPCMutationSystem.snapshotAll()
	baseline = {}
	local container = workspace:FindFirstChild("TutorialNPCs")
	if not container then return end
	for _, m in ipairs(container:GetChildren()) do
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
			baseline[m] = snapshotModel(m)
		end
	end
end

-- restoreFromBaseline(): force EVERY snapshotted NPC back to its original state +
-- strip any mutation extras we add (MutationGlow / MutationScream). Belt-and-
-- suspenders so NO NPC -- above all the bean-stand farmers -- stays mutated.
local function restoreFromBaseline()
	for model, snap in pairs(baseline) do
		if model and model.Parent then
			for _, d in ipairs(model:GetDescendants()) do
				if d.Name == "MutationGlow" or d.Name == "MutationScream" then pcall(function() d:Destroy() end) end
			end
			if snap.modelScale then pcall(function() model:ScaleTo(snap.modelScale) end) end
			for sv, v in pairs(snap.scaleVals) do if sv and sv.Parent then sv.Value = v end end
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum then
				if snap.walkSpeed then hum.WalkSpeed = snap.walkSpeed end
				if snap.jumpPower then hum.JumpPower = snap.jumpPower end
				if snap.hipHeight then hum.HipHeight = snap.hipHeight end
			end
			for p, look in pairs(snap.parts) do
				if p and p.Parent then p.Color = look.Color; p.Material = look.Material end
			end
			if snap.cframe and snap.prim and snap.prim.Parent then
				pcall(function() snap.prim.CFrame = snap.cframe end)
			end
		end
	end
	baseline = {}
end

--======================================================================
-- start(): begin the auto-revert tick (per-NPC durations expire) + flag the
-- system running so mutateSome()/combineTwo() actually do work.
--======================================================================
function NPCMutationSystem.start()
	if running then return end
	NPCMutationSystem.snapshotAll()   -- capture every NPC's original state for the end-of-event restore-ALL
	running = true
	tickConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		-- Auto-revert NPCs whose duration expired (collect first to avoid
		-- mutating the table while iterating).
		local expired = {}
		for model, entry in pairs(mutated) do
			if now >= entry.restoreAt then
				table.insert(expired, model)
			end
		end
		for _, model in ipairs(expired) do
			restoreNPC(model)
		end
	end)
end

--======================================================================
-- stop(): stop spawning new NPC mutations (the tick keeps reverting until
-- cleanup; we also stop scheduling here). Called when MAIN ends.
--======================================================================
function NPCMutationSystem.stop()
	running = false
end

--======================================================================
-- cleanup(): RESTORE EVERY mutated NPC + tear down the tick. After this, no
-- NPC is left mutated and nothing leaks.
--======================================================================
function NPCMutationSystem.cleanup()
	running = false
	if tickConn then tickConn:Disconnect() tickConn = nil end
	-- Restore every still-mutated NPC (per-mutation revert path).
	local models = {}
	for model in pairs(mutated) do table.insert(models, model) end
	for _, model in ipairs(models) do
		restoreNPC(model)
	end
	mutated = {}
	mutatedCount = 0
	-- SAFETY: force EVERY NPC (incl. the farmers) back to its captured original
	-- state, so nothing can be left mutated even if something slipped through.
	restoreFromBaseline()
end

return NPCMutationSystem
