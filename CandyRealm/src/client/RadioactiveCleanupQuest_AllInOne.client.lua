--======================================================================
-- RadioactiveCleanupQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- "REACTOR CLEANUP" -- operate the BeanLiftCrane to clear radioactive cocoa
-- waste into the containment chamber before the reactor overloads.
--
-- WHAT THE WORLD PROVIDES (name these in Studio):
--   * BeanLiftCrane        -- the crane. ANY internal structure; this script reads
--                             its parts and works out which bits slew/hoist.
--   * ContainmentChamber   -- (you're adding this) where the waste gets dumped.
--                             Matched loosely: "Containment Chamber" works too.
--   * (optional) parts named  wastepile / cocoawaste  -- the piles to clear.
--                             If none exist, the script builds them around the crane.
--   * (optional) a "Candy Npc" near the crane -- gives the quest if present;
--                             otherwise an "OPERATE" prompt on the crane starts it.
--
-- HOW IT PLAYS:
--   Step onto the crane -> an industrial HUD console takes over. You SLEW the boom
--   left/right, HOIST the hook down onto a glowing pile, GRAB, hoist back up, slew
--   over the chamber, and RELEASE. The chamber fills, the warning lights walk from
--   red -> amber -> green, and the last load seals it with a CLUNK.
--
-- Everything is client-side and per-player, like the island's other quests.
--======================================================================

local Players            = game:GetService("Players")
local Workspace          = game:GetService("Workspace")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local Debris             = game:GetService("Debris")
local UserInputService   = game:GetService("UserInputService")
local SoundService       = game:GetService("SoundService")
local TextChatService    = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- SYNC CHECK: if you DON'T see this exact line in the Output when you play, Rojo is NOT syncing this
-- file into Studio (see the checklist) -- none of the recent crane/shovel fixes will be running.
print("[Cleanup] >>> VERSION redpanel-v4 loaded <<<")

-- ============================================================================
-- CONFIG
-- ============================================================================
local CRANE_NAME     = "beanliftcrane"       -- matched with norm() (spaces/underscores ignored)
local ENTER_NAME     = "entercrane"          -- the pad you stand on to take the controls
local VIEW_NAME      = "craneview"           -- a part whose CFrame IS the operator camera
local FINDINGS_NAME  = "findings"            -- block(s) that become the data terminal
-- Piles the crane physically can't reach are done by hand instead, with a shovel
-- this script BUILDS for you (nothing to place in Studio). The NPC hands it over once the
-- crane has cleared everything it can, so you only ever visit the crane once.
local SMOKE_BRICK_NAME  = "smokebrick"       -- extra chimneys: bricks that just belch smoke
local HAND_CARRY_HEIGHT = 3.4                -- how high the pile rides while you carry it
local HAND_DROP_RANGE   = 14                 -- how near the bin you must get to tip it in
local TERMINAL_YAW   = 90                    -- degrees CCW to spin each terminal on its block
local VIEW_YAW       = 270                   -- fallback facing, only used if there's no crate to aim at
local VIEW_RIDES_ARM = true                  -- true = the camera is bolted to the boom and swings with it
-- where the waste gets dumped. Exact (normalised) names, so "Nuclear Waste" counts but a
-- pile called "waste 3" doesn't get mistaken for the chamber.
local CHAMBER_NAMES  = { "nuclearwaste", "containmentchamber" }
local PILE_NAMES     = { "waste", "cocoawaste", "radioactivecocoa" }  -- "waste" also catches "WastePile"
local NPC_NAMES      = { "candynpc" }

local LOADS_REQUIRED = 4                     -- how many piles to clear (3-5 reads best)
local OPERATE_RANGE  = 18                    -- how close you must be to take the controls

local SLEW_SPEED     = 38                    -- degrees/sec the boom swings
local HOIST_SPEED    = 9                     -- studs/sec the hook drops
-- The whole machine rolls forwards/backwards on its rollers while you're at the controls,
-- so you can nudge it to reach the awkward piles. It's a LOAN, not a move: releasing the
-- controls rolls it straight back to where it started, so from outside it never shifted.
local DRIVE_SPEED    = 7                     -- studs/sec the machine rolls
local DRIVE_RANGE    = 16                    -- MAX studs it may travel from its parked spot
local MAX_DROP       = 42                    -- how far below its rest height the hook can go
local GRAB_RADIUS    = 16                    -- how near the crate must be to a pile to grab it
                                             -- (generous on purpose -- small kids play this)
local AUTO_SPEED     = 1.8                   -- multiplier on the assist's drive/slew/hoist speed

-- Audio: drop in your OWN asset ids. "" = silent, and nothing is ever created for an
-- empty id -- given how many ids in this place fail auth, silence is the safe default.
local SOUND_MOTOR    = ""        -- short whirr each time the crane starts moving
local SOUND_CLUNK    = ""        -- the containment lid slamming shut
local SOUND_SITE     = ""        -- LOOPING construction-site ambience from the crane
local SITE_VOLUME    = 0.35
local SITE_RANGE     = 140       -- studs you can hear the site from

-- industrial palette
local PANEL   = Color3.fromRGB(28, 30, 34)
local PANEL_2 = Color3.fromRGB(44, 47, 53)
local AMBER   = Color3.fromRGB(255, 176, 46)
local STEEL   = Color3.fromRGB(126, 134, 146)
local HAZARD  = Color3.fromRGB(232, 186, 34)
local RED_L   = Color3.fromRGB(226, 62, 58)
local AMBER_L = Color3.fromRGB(238, 176, 44)
local GREEN_L = Color3.fromRGB(86, 214, 116)
local WASTE   = Color3.fromRGB(150, 226, 74)   -- glowing radioactive cocoa

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s)
	return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", ""))
end

local function nameHas(name, needles)
	local n = norm(name)
	for _, want in ipairs(needles) do
		if string.find(n, want, 1, true) then return true end
	end
	return false
end

local function firstBasePart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function boundsOf(inst)
	if inst:IsA("Model") then return inst:GetBoundingBox() end
	return inst.CFrame, inst.Size
end

local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat
		local r = fn()
		if r then return r end
		task.wait(0.5)
	until os.clock() - t0 > (timeout or 45)
	return fn()
end

local function findByName(key)
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("BasePart")) and norm(d.Name) == key then return d end
	end
	return nil
end

-- first instance whose normalised name exactly matches any of `keys`
local function findByAnyName(keys)
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") or d:IsA("BasePart") then
			local n = norm(d.Name)
			for _, k in ipairs(keys) do if n == k then return d end end
		end
	end
	return nil
end
local function isChamberName(name)
	local n = norm(name)
	for _, k in ipairs(CHAMBER_NAMES) do if n == k then return true end end
	return false
end

local function mk(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function playSound(id, volume)
	if not id or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = id; s.Volume = volume or 0.6; s.Parent = SoundService
	s:Play(); Debris:AddItem(s, 5)
end

-- ============================================================================
-- STATE
-- ============================================================================
local readings      = {}    -- one per load dumped: { id, isotope, mass, dose, filed }
local findingsFiled = false -- true once every reading has been entered at the terminal
local crane, chamber, npcHead
local rig                  -- the classified crane (see buildRig)
local piles = {}           -- { model=, pos=, taken=bool }
local loadsDone   = 0
local questAccepted = false
local operating   = false  -- are we at the controls?
local carrying    = false  -- is there waste on the hook?
local carriedPile           -- the pile currently on the hook
local finished    = false
local startHazardCycle    -- defined near the bottom; the GO block calls it
local onExitBoard           -- set by wireOperatePrompt: starts the pad's re-board cooldown
local buildSegments         -- set by the HUD: rebuilds the containment bar when the pile count is known
local refreshBanner         -- defined in the OBJECTIVE BANNER section, used by the terminal above it
local solveFor              -- defined with the assist; spawnPiles uses it to test reachability
local registerLoad          -- defined with the crane; the hand-carry path uses it too
local handPickup            -- defined with the shovel; spawnPiles wires prompts to it
local unreachableLeft       -- \ both defined with the shovel, but the crane assist and
local craneWorkLeft         -- / the banner (defined earlier) both need to ask

local hasShovel   = false  -- has the player found the secret shovel?
local handPile     = nil    -- the pile currently being carried by hand
local shovelModel          -- the tool prop sitting next to the NPC
_G.cleanupQuestComplete = false

-- ============================================================================
-- CRANE RIG -- read BeanLiftCrane's parts and work out what moves
-- ============================================================================
-- BeanLiftCrane is a lattice tower with a boom on top: legs / cross-braces / ties /
-- brackets / ladder / platforms hold still, and the boom assembly swings on top of it.
--
-- SLEW = the boom and everything hanging off it (MainBoom, BoomSupportL/R, TipPulley,
--        TipAxle, BasePulley, BaseAxle, RopeTop, RopeDrop, CrateRope1-4, Crate*, HookBlock)
-- HOIST = the bits that ride DOWN with the hook (Crate*, HookBlock, CrateRope*)
-- static = everything else (Leg*, Cross*, *Tie*, Bracket*, Ladder*, Rung*, Rail*, Plat*, lamps)
--
-- NOTE "BasePulley"/"BaseAxle" contain "base" but are the boom's heel at the TOP of the
-- tower -- so slew words are tested FIRST, or they'd be mistaken for the crane's base.
local SLEW_WORDS  = { "boom", "rope", "crate", "hook", "pulley", "axle", "jib" }
local HOIST_WORDS = { "crate", "hook" }          -- + the drop rope, handled separately
local LEG_WORDS   = { "leg" }
local HEEL_WORDS  = { "basepulley", "baseaxle", "heel" }
local TIP_WORDS   = { "tippulley", "tipaxle" }
local DROPROPE    = { "ropedrop", "droprope" }

local function dumpCraneParts(parts)
	warn(("[Cleanup] BeanLiftCrane contains %d BasePart(s) -- listing them so the rig can be tuned:"):format(#parts))
	for _, p in ipairs(parts) do
		print(("    '%s'  %s  size=%.1f,%.1f,%.1f  offsetFromBase=%.1f,%.1f,%.1f"):format(
			p.Name, p.ClassName, p.Size.X, p.Size.Y, p.Size.Z,
			p.Position.X, p.Position.Y, p.Position.Z))
	end
end

local function buildRig(craneInst)
	local parts = {}
	if craneInst:IsA("BasePart") then parts[1] = craneInst
	else for _, d in ipairs(craneInst:GetDescendants()) do if d:IsA("BasePart") then parts[#parts + 1] = d end end end
	if #parts == 0 then return nil end

	local modelCF, modelSize = boundsOf(craneInst)
	local bottomY = modelCF.Position.Y - modelSize.Y * 0.5

	dumpCraneParts(parts)

	local r = {
		all = parts, base = {}, upper = {}, cable = nil, hook = nil,
		rest = {},                     -- [part] = its CFrame at rest
		slewCenter = nil, slewAngle = 0, drop = 0,
	}

	-- everything gets anchored so our CFrame animation is authoritative
	for _, p in ipairs(parts) do p.Anchored = true; r.rest[p] = p.CFrame end

	-- --- classify -----------------------------------------------------------
	r.hoists, r.dropRope, r.heel, r.tipPart = {}, nil, nil, nil
	local legs = {}
	for _, p in ipairs(parts) do
		if nameHas(p.Name, SLEW_WORDS) then
			r.upper[#r.upper + 1] = p
			if nameHas(p.Name, HOIST_WORDS) then r.hoists[#r.hoists + 1] = p end
			if nameHas(p.Name, DROPROPE) then r.dropRope = p end
			if nameHas(p.Name, HEEL_WORDS) and not r.heel then r.heel = p end
			if nameHas(p.Name, TIP_WORDS)  and not r.tipPart then r.tipPart = p end
			if nameHas(p.Name, { "hook" })  and not r.hook then r.hook = p end
		else
			r.base[#r.base + 1] = p
			if nameHas(p.Name, LEG_WORDS) then legs[#legs + 1] = p end
		end
	end

	-- nothing name-matched (a differently-built crane) -> fall back to geometry
	if #r.upper == 0 then
		local cutoff = bottomY + math.max(2, modelSize.Y * 0.55)
		r.base, r.upper = {}, {}
		for _, p in ipairs(parts) do
			if p.Position.Y <= cutoff then r.base[#r.base + 1] = p else r.upper[#r.upper + 1] = p end
		end
		if #r.upper == 0 then r.upper, r.base = parts, {} end
	end
	if r.dropRope then r.hoists[#r.hoists + 1] = r.dropRope end

	-- SLEW AXIS: the centre of the tower's legs (that's what the boom pivots on).
	-- Falls back to the static parts' footprint, then the model centre.
	local function centroidXZ(list)
		local sx, sz, n = 0, 0, 0
		for _, p in ipairs(list) do sx, sz, n = sx + p.Position.X, sz + p.Position.Z, n + 1 end
		if n == 0 then return nil end
		return Vector3.new(sx / n, bottomY, sz / n)
	end
	r.slewCenter = centroidXZ(legs) or centroidXZ(r.base)
		or Vector3.new(modelCF.Position.X, bottomY, modelCF.Position.Z)

	-- boom tip: the slewing part reaching furthest horizontally from the axis
	local tip, tipD
	for _, p in ipairs(r.upper) do
		local flat = (p.Position - r.slewCenter) * Vector3.new(1, 0, 1)
		local d = flat.Magnitude + math.max(p.Size.X, p.Size.Z) * 0.5
		if not tipD or d > tipD then tip, tipD = p, d end
	end
	r.boomTip = r.tipPart or tip
	r.reach   = tipD or 20

	-- the machine's "forward": the way the boom points at REST. The chassis never turns,
	-- so this stays fixed no matter how far you slew the boom round.
	do
		local ref = (r.boomTip and r.boomTip.Position) or (r.slewCenter + Vector3.new(0, 0, 1))
		local flat = (ref - r.slewCenter) * Vector3.new(1, 0, 1)
		r.boomDir = (flat.Magnitude > 0.5) and flat.Unit or Vector3.new(0, 0, 1)
	end
	r.drive = 0   -- studs rolled forward (-) back, cleared when you step off

	-- ---- EXHAUST STACK + SITE AMBIENCE -------------------------------------
	-- A working machine should look and sound like one. The stack is bolted by the
	-- winch heel and slews with the boom. `Smoke` is a built-in emitter with no
	-- texture asset behind it, so it can't fail to load like the sound ids do.
	do
		local heelPos = (r.heel and r.heel.Position)
			or Vector3.new(r.slewCenter.X, bottomY + modelSize.Y * 0.62, r.slewCenter.Z)

		local pipe = mk({ Name = "ExhaustStack", Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.6, 0.85, 0.85), Color = Color3.fromRGB(52, 48, 46),
			Material = Enum.Material.Metal })
		pipe.CFrame = CFrame.new(heelPos + Vector3.new(1.6, 1.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
		pipe.Parent = Workspace

		local cap = mk({ Name = "ExhaustCap", Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 1.15, 1.15), Color = Color3.fromRGB(84, 80, 78),
			Material = Enum.Material.Metal })
		cap.CFrame = pipe.CFrame * CFrame.new(1.35, 0, 0)
		cap.Parent = Workspace

		-- NB: Smoke always rises along WORLD +Y whatever way its part faces, and it has no
		-- Rate property -- Opacity maxes at 1 and RiseVelocity at 25. The only way to get a
		-- genuinely THICK column is to stack several emitters on the same part, so there
		-- are three here at slightly different sizes to break up the banding.
		local smokes = {}
		for i = 1, 3 do
			local sm = Instance.new("Smoke")
			sm.Name = "ExhaustSmoke" .. i
			sm.Color = Color3.fromRGB(74, 74, 80)
			sm.Opacity = 1                       -- max
			sm.RiseVelocity = 25                 -- max: straight up, fast
			sm.Size = 14 + i * 3                 -- 17 / 20 / 23 -- layered, not one flat sheet
			sm.Enabled = true
			sm.Parent = cap
			smokes[i] = sm
		end

		r.exhaust, r.exhaustCap, r.smokes = pipe, cap, smokes
		-- both pieces ride the boom
		r.upper[#r.upper + 1] = pipe; r.rest[pipe] = pipe.CFrame
		r.upper[#r.upper + 1] = cap;  r.rest[cap]  = cap.CFrame
		print(("[Cleanup] exhaust stack at %.0f,%.0f,%.0f (smoke on)"):format(cap.Position.X, cap.Position.Y, cap.Position.Z))

		-- looping site ambience, only built if you've supplied an id
		if SOUND_SITE ~= "" then
			local s = Instance.new("Sound")
			s.Name = "SiteAmbience"; s.SoundId = SOUND_SITE; s.Looped = true
			s.Volume = SITE_VOLUME; s.RollOffMaxDistance = SITE_RANGE; s.RollOffMinDistance = 12
			s.Parent = pipe
			s:Play()
			r.siteSound = s
		end
	end

	-- THE CRATE is the box that goes down and scoops the waste up, so grabbing is
	-- measured from IT, not from the hook block above it. Your build has FIVE parts all
	-- named "Crate" (the four walls + floor), so collect them and use their centre.
	r.crateParts = {}
	for _, p in ipairs(r.upper) do
		if nameHas(p.Name, { "crate" }) and not nameHas(p.Name, { "rope" }) then
			r.crateParts[#r.crateParts + 1] = p
			if nameHas(p.Name, { "cratebottom" }) then r.crate = p end
		end
	end
	r.crate = r.crate or r.crateParts[1] or r.hook
	-- the crate's resting centre AND the height of its underside -- the assist lowers by
	-- however much it takes to put that underside just above whatever it's reaching for,
	-- so the crate settles onto each pile instead of stopping short or sinking through.
	do
		local sx, sy, sz, n = 0, 0, 0, 0
		local lowest
		for _, p in ipairs(r.crateParts) do
			sx, sy, sz, n = sx + p.Position.X, sy + p.Position.Y, sz + p.Position.Z, n + 1
			local bottom = p.Position.Y - p.Size.Y * 0.5
			if not lowest or bottom < lowest then lowest = bottom end
		end
		r.crateRestPos = (n > 0) and Vector3.new(sx / n, sy / n, sz / n)
			or (r.hook and r.hook.Position) or r.slewCenter
		r.crateBottomRestY = lowest
			or (r.hook and (r.hook.Position.Y - r.hook.Size.Y * 0.5))
			or r.crateRestPos.Y
	end

	-- OPERATOR CAMERA: the part you named "crane view". Its CFrame *is* the shot.
	-- The camera is FIXED -- it does NOT swing with the boom. The arrow cluster drives
	-- the machine; the view stays exactly where you aimed it in Studio.
	local viewPart
	for _, p in ipairs(parts) do
		if norm(p.Name) == VIEW_NAME then viewPart = p; break end
	end
	viewPart = viewPart or findByName(VIEW_NAME)     -- also allow it to live outside the model
	if viewPart then
		viewPart.Transparency = 1; viewPart.CanCollide = false; viewPart.CanQuery = false
		viewPart.Anchored = true
		r.viewPart = viewPart
		-- only the POSITION of this part is used -- the aim comes from looking at the crate,
		-- so however it happens to be rotated in Studio doesn't matter.
		r.cabRest   = viewPart.CFrame
		r.rest[viewPart] = viewPart.CFrame
		r.viewFixed = not VIEW_RIDES_ARM

		for i = #r.base, 1, -1 do if r.base[i] == viewPart then table.remove(r.base, i) end end
		local inUp = false
		for _, u in ipairs(r.upper) do if u == viewPart then inUp = true; break end end
		if VIEW_RIDES_ARM then
			-- bolt it to the boom: the marker (and therefore the eye) swings with the arm
			if not inUp then r.upper[#r.upper + 1] = viewPart end
		else
			for i = #r.upper, 1, -1 do if r.upper[i] == viewPart then table.remove(r.upper, i) end end
		end

		print(("[Cleanup] operator camera '%s' -- %s, aimed at the crate"):format(
			viewPart.Name, VIEW_RIDES_ARM and "mounted on the boom (swings with it)" or "fixed"))
	else
		-- no marker placed: fall back to the boom heel looking down the boom
		local heelPos = r.heel and r.heel.Position
			or Vector3.new(r.slewCenter.X, bottomY + modelSize.Y * 0.62, r.slewCenter.Z)
		local aimAt = (r.boomTip and r.boomTip.Position) or (heelPos + Vector3.new(0, 0, 1))
		local flat = (aimAt - heelPos) * Vector3.new(1, 0, 1)
		local boomDir = (flat.Magnitude > 0.5) and flat.Unit or Vector3.new(0, 0, 1)
		local cabPos = heelPos + Vector3.new(0, 3.2, 0) - boomDir * 2.5
		r.cabRest = CFrame.lookAt(cabPos, cabPos + boomDir)
		r.boomDir = boomDir
		warn("[Cleanup] no 'crane view' part found -- using the boom heel as the camera")
	end

	-- --- no hook in the model? build one, hanging off the boom tip ----------
	if not r.hook then
		local tipCF, tipSize = (tip and tip.CFrame or modelCF), (tip and tip.Size or modelSize)
		local flat = ((tip and tip.Position or modelCF.Position) - r.slewCenter) * Vector3.new(1, 0, 1)
		local outward = (flat.Magnitude > 0.5) and flat.Unit or Vector3.new(0, 0, 1)
		local hangFrom = Vector3.new(0, tipCF.Position.Y - tipSize.Y * 0.5, 0)
			+ r.slewCenter * Vector3.new(1, 0, 1) + outward * (r.reach - 1.5)

		local holder = Instance.new("Model"); holder.Name = "BeanLiftRigging"; holder.Parent = Workspace

		local cable = mk({ Name = "Cable", Size = Vector3.new(0.22, 6, 0.22),
			Color = Color3.fromRGB(40, 42, 46), Material = Enum.Material.Metal })
		cable.CFrame = CFrame.new(hangFrom - Vector3.new(0, 3, 0))
		cable.Parent = holder

		local hook = mk({ Name = "Hook", Size = Vector3.new(1.6, 1.9, 1.6),
			Color = STEEL, Material = Enum.Material.Metal })
		hook.CFrame = CFrame.new(hangFrom - Vector3.new(0, 6.9, 0))
		hook.Parent = holder

		local jaw = mk({ Name = "HookJaw", Size = Vector3.new(2.3, 0.5, 2.3),
			Color = Color3.fromRGB(94, 100, 110), Material = Enum.Material.Metal })
		jaw.CFrame = hook.CFrame * CFrame.new(0, -1.1, 0)
		jaw.Parent = holder

		r.cable, r.hook, r.hookJaw, r.rigging = cable, hook, jaw, holder
		r.rest[cable], r.rest[hook], r.rest[jaw] = cable.CFrame, hook.CFrame, jaw.CFrame
		r.builtRigging = true
		print("[Cleanup] no hook/cable found in the crane -- built rigging off the boom tip")
	end

	-- the rigging slews with the boom
	local function inUpper(p) for _, u in ipairs(r.upper) do if u == p then return true end end return false end
	for _, p in ipairs({ r.cable, r.hook, r.hookJaw }) do
		if p and not inUpper(p) then r.upper[#r.upper + 1] = p end
	end

	r.cableRestSize = r.cable and r.cable.Size or Vector3.new(0.2, 6, 0.2)
	r.cableRestCF   = r.cable and r.cable.CFrame or CFrame.new()
	r.dropRopeSize  = r.dropRope and r.dropRope.Size or nil

	print(("[Cleanup] rig ready -- %d static, %d slewing, %d hoisting; reach %.1f; hook '%s'; heel '%s'"):format(
		#r.base, #r.upper, #(r.hoists or {}), r.reach,
		r.hook and r.hook.Name or "none", r.heel and r.heel.Name or "computed"))
	return r
end

-- Pay a rope out along whichever of its local axes is longest, keeping its TOP end
-- pinned. Works whatever way round the part was built (RopeDrop is long on X, not Y).
local function payOutRope(part, restSize, worldCF, extra)
	local s = restSize
	local axis, len
	if     s.X >= s.Y and s.X >= s.Z then axis, len = Vector3.new(1, 0, 0), s.X
	elseif s.Y >= s.X and s.Y >= s.Z then axis, len = Vector3.new(0, 1, 0), s.Y
	else                                  axis, len = Vector3.new(0, 0, 1), s.Z end

	local worldAxis = worldCF:VectorToWorldSpace(axis)
	local sign = (worldAxis.Y >= 0) and 1 or -1          -- which end of it points up
	local topPos = worldCF.Position + worldAxis * (len * 0.5 * sign)
	local newLen = len + extra
	part.Size = restSize + axis * extra
	part.CFrame = CFrame.fromMatrix(topPos - worldAxis * (newLen * 0.5 * sign),
		worldCF.XVector, worldCF.YVector, worldCF.ZVector)
end

local crateCenter   -- forward-declared: applyRig aims the camera with it, defined just below

-- Apply the current slew angle + hoist drop to every moving part.
local function applyRig()
	if not rig then return end
	local pivot = CFrame.new(rig.slewCenter) * CFrame.Angles(0, math.rad(rig.slewAngle), 0) * CFrame.new(-rig.slewCenter)

	local hoisting = {}
	for _, p in ipairs(rig.hoists or {}) do hoisting[p] = true end
	if rig.hook then hoisting[rig.hook] = true end
	if rig.hookJaw then hoisting[rig.hookJaw] = true end
	if rig.dropRope then hoisting[rig.dropRope] = false end   -- stretched, not moved

	-- ROLLERS: the whole machine shifts along its fixed forward axis. Every part gets this,
	-- tower included, so it reads as the crane rolling rather than the arm stretching.
	local driveVec = (rig.boomDir or Vector3.new(0, 0, 1)) * (rig.drive or 0)

	-- the static tower normally never moves -- it only does when you're rolling
	for _, p in ipairs(rig.base) do
		local rest = rig.rest[p]
		if rest and p.Parent then p.CFrame = rest + driveVec end
	end

	for _, p in ipairs(rig.upper) do
		local rest = rig.rest[p]
		if rest and p.Parent and p ~= rig.dropRope then
			local cf = pivot * rest
			if hoisting[p] then cf = cf - Vector3.new(0, rig.drop, 0) end
			p.CFrame = cf + driveVec
		end
	end

	-- the drop rope pays out from the tip pulley down to the hook
	if rig.dropRope and rig.dropRope.Parent then
		payOutRope(rig.dropRope, rig.rest[rig.dropRope] and rig.dropRopeSize or rig.dropRope.Size,
			(pivot * rig.rest[rig.dropRope]) + driveVec, rig.drop)
	end

	-- a hook/cable we built ourselves stretches the simple way (it's always +Y)
	if rig.builtRigging and rig.cable and rig.cable.Parent then
		local restCF, restSize = rig.rest[rig.cable], rig.cableRestSize
		local topY   = (pivot * restCF).Position.Y + restSize.Y * 0.5
		local newLen = restSize.Y + rig.drop
		local mid    = (pivot * restCF).Position
		rig.cable.Size   = Vector3.new(restSize.X, newLen, restSize.Z)
		rig.cable.CFrame = CFrame.new(Vector3.new(mid.X, topY - newLen * 0.5, mid.Z))
	end
	-- the load rides INSIDE the crate
	local carrier = rig.crate or rig.hook
	if carrying and carriedPile and carriedPile.model and carriedPile.model.Parent and carrier then
		carriedPile.model:PivotTo(carrier.CFrame * CFrame.new(0, 1.6, 0))
	end

	-- OPERATOR POV: the camera SITS at your "crane view" part and LOOKS AT THE CRATE.
	-- The eye never moves -- the arrows drive the machine, not the view -- but the aim
	-- follows the crate, so you're always watching the thing you're steering.
	if operating and rig.cabRest then
		local eyeCF = (rig.viewFixed and rig.cabRest or (pivot * rig.cabRest)) + driveVec
		local target = crateCenter()
		local viewCF
		if target then
			viewCF = CFrame.lookAt(eyeCF.Position, target)
		else
			viewCF = eyeCF * CFrame.Angles(0, math.rad(VIEW_YAW), 0)  -- nothing to watch: use the raw facing
		end

		local cam = Workspace.CurrentCamera
		if cam and cam.CameraType == Enum.CameraType.Scriptable then
			cam.CFrame = viewCF
		end
		-- NOTE: the character is deliberately NOT moved or anchored. Teleporting it into
		-- the crane put it inside the lattice, where it got shoved about / killed, and any
		-- respawn fired CharacterAdded -> setOperating(false) -- i.e. "it kicked me out".
		-- You stay stood safely on the pad; only the camera goes up the crane.
	end
end

-- middle of the crate box, averaged over its walls + floor
crateCenter = function()
	if not rig then return nil end
	local sx, sy, sz, n = 0, 0, 0, 0
	for _, p in ipairs(rig.crateParts or {}) do
		if p.Parent then sx, sy, sz, n = sx + p.Position.X, sy + p.Position.Y, sz + p.Position.Z, n + 1 end
	end
	if n > 0 then return Vector3.new(sx / n, sy / n, sz / n) end
	local c = rig.crate or rig.hook
	return (c and c.Parent) and c.Position or nil
end

-- where the pickup actually happens: the mouth of the crate (its underside)
local function hookPosition()
	if not rig then return Vector3.new() end
	local mid = crateCenter()
	if not mid then return Vector3.new() end
	local c = rig.crate or rig.hook
	local half = (c and c.Size.Y or 4) * 0.5
	return mid - Vector3.new(0, half, 0)
end

-- ============================================================================
-- SMOKE BRICKS -- any brick you named "smokebrick" becomes a chimney. Same
-- stacked-emitter trick as the crane's exhaust, since Smoke has no rate control.
-- The brick itself is left exactly as you built it (visible, solid) -- it's a
-- chimney, not a marker.
-- ============================================================================
local function wireSmokeBricks()
	local made = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and norm(d.Name) == SMOKE_BRICK_NAME then
			made += 1
			-- emit from the TOP of the brick rather than its centre, so tall chimneys
			-- don't look like they're leaking out of their own middle
			local mouth = mk({ Name = "SmokeMouth", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
			mouth.CFrame = CFrame.new(d.Position + Vector3.new(0, d.Size.Y * 0.5, 0))
			mouth.Parent = Workspace

			for i = 1, 3 do
				local sm = Instance.new("Smoke")
				sm.Name = "ChimneySmoke" .. i
				sm.Color = Color3.fromRGB(74, 74, 80)
				sm.Opacity = 1
				sm.RiseVelocity = 22
				sm.Size = 12 + i * 3      -- 15 / 18 / 21, layered like the crane stack
				sm.Enabled = true
				sm.Parent = mouth
			end
		end
	end
	if made > 0 then print(("[Cleanup] %d smoke brick(s) belching"):format(made))
	else warn("[Cleanup] no bricks named 'smokebrick' found") end
end

-- ============================================================================
-- WASTE PILES -- glowing radioactive cocoa
-- ============================================================================
local function makePile(pos, idx)
	local model = Instance.new("Model"); model.Name = "CocoaWaste"

	local heap = mk({ Name = "Heap", Size = Vector3.new(3.4, 1.8, 3.4),
		Color = Color3.fromRGB(74, 46, 30), Material = Enum.Material.Slate, CanQuery = true })
	heap.CFrame = CFrame.new(pos + Vector3.new(0, 0.9, 0))
	heap.Parent = model; model.PrimaryPart = heap

	for i = 1, 5 do   -- glowing lumps poking out of the heap
		local a = (i / 5) * math.pi * 2
		local lump = mk({ Name = "Lump", Shape = Enum.PartType.Ball, Size = Vector3.new(1.15, 1.15, 1.15),
			Color = WASTE, Material = Enum.Material.Neon, Transparency = 0.15 })
		lump.CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 1.1, 1.35 + (i % 3) * 0.3, math.sin(a) * 1.1))
		lump.Parent = model
	end

	local glow = Instance.new("PointLight")
	glow.Color = WASTE; glow.Brightness = 2.2; glow.Range = 14; glow.Parent = heap
	local spk = Instance.new("Sparkles"); spk.SparkleColor = WASTE; spk.Parent = heap

	local hl = Instance.new("Highlight")
	hl.FillColor = WASTE; hl.FillTransparency = 0.75
	hl.OutlineColor = WASTE; hl.OutlineTransparency = 0.1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = heap; hl.Parent = model

	model.Parent = Workspace

	-- slow ominous pulse
	task.spawn(function()
		local t = idx * 0.9
		while model.Parent do
			t += 0.05
			glow.Brightness = 1.8 + math.sin(t) * 0.9
			hl.FillTransparency = 0.72 + math.sin(t) * 0.12
			task.wait(0.05)
		end
	end)

	-- topY: the crown of the heap (heap is 1.8 tall centred at +0.9; the glowing lumps
	-- poke another ~0.9 above that). The assist lowers the crate onto exactly this.
	return { model = model, pos = pos, topY = pos.Y + 2.3, taken = false }
end

local function groundUnder(pos)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local filter = {}
	if player.Character then filter[#filter + 1] = player.Character end
	if crane then filter[#filter + 1] = crane end
	rp.FilterDescendantsInstances = filter
	local hit = Workspace:Raycast(pos + Vector3.new(0, 25, 0), Vector3.new(0, -120, 0), rp)
	return hit and hit.Position or pos
end

local function spawnPiles()
	-- prefer piles you placed in Studio
	local found = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		-- "Nuclear Waste" is the CHAMBER, not a pile -- and it contains the word "waste",
		-- so it (and anything inside it) has to be excluded explicitly.
		local isChamber = isChamberName(d.Name) or (chamber and d:IsDescendantOf(chamber))
		if not isChamber and (d:IsA("BasePart") or d:IsA("Model")) and nameHas(d.Name, PILE_NAMES) then
			local part = firstBasePart(d)
			if part then
				-- the marker is just an anchor: hide it, build the glowing heap on top
				for _, q in ipairs(d:IsA("Model") and d:GetDescendants() or { d }) do
					if q:IsA("BasePart") then q.Transparency = 1; q.CanCollide = false; q.CanQuery = false end
				end
				found[#found + 1] = part.Position
			end
		end
	end

	if #found == 0 and rig then
		-- none placed -> ring them around the crane, just inside its reach
		local r = math.max(10, rig.reach * 0.8)
		for i = 1, LOADS_REQUIRED do
			local a = (i / LOADS_REQUIRED) * math.pi * 2 + 0.4
			found[i] = groundUnder(rig.slewCenter + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
		end
		print(("[Cleanup] no parts named 'waste' found -- generated %d piles around the crane"):format(#found))
	else
		-- you placed them: the quest length becomes however many there are (capped, so a
		-- stray dozen markers doesn't turn this into a chore). The HUD bar rebuilds to match.
		local want = math.clamp(#found, 1, 8)
		if want ~= LOADS_REQUIRED then
			print(("[Cleanup] %d 'waste' part(s) placed -> containment now needs %d load(s)"):format(#found, want))
			LOADS_REQUIRED = want
			if buildSegments then buildSegments() end
		end
	end

	for i, pos in ipairs(found) do
		if i <= LOADS_REQUIRED then piles[#piles + 1] = makePile(pos, i) end
	end

	-- Work out which of these the crane can actually get to. Anything outside its swing
	-- (fixed crate radius, give or take DRIVE_RANGE of roll) has to be carried by hand.
	local reach, byHand = 0, 0
	for _, p in ipairs(piles) do
		local want = solveFor and solveFor(p.pos, p.topY, 1.2)
		p.reachable = (want ~= nil) and (want.miss <= GRAB_RADIUS)
		if p.reachable then reach += 1 else byHand += 1 end
		-- EVERY pile also gets a "Pick Up Waste" shovel prompt as a reliable fallback -- so a pile
		-- the crane can't actually grab (or that you'd rather do by hand) is never left stuck. The
		-- crane still grabs reachable ones normally; their prompts ride the hook + vanish on drop.
		local part = p.model and p.model.PrimaryPart
		if part then
			part.CanQuery = true
			local pr = Instance.new("ProximityPrompt")
			pr.ActionText = "Pick Up Waste"; pr.ObjectText = "Radioactive Cocoa"
			pr.HoldDuration = 0.4; pr.MaxActivationDistance = 12
			pr.RequiresLineOfSight = false; pr.Parent = part
			p.handPrompt = pr   -- kept so an interrupted carry can re-enable it (any-order safety)
			pr.Triggered:Connect(function()
				if p.taken then pr.Enabled = false; return end
				if not hasShovel then
					if _G.NotifyCenter then
						pcall(function() _G.NotifyCenter.push({
							text = "\xE2\x98\xA2 Too hot to touch -- find the secret shovel!", color = RED_L }) end)
					end
					return
				end
				if handPile then return end
				pr.Enabled = false
				handPickup(p)
			end)
		end
	end
	print(("[Cleanup] %d pile(s) in crane range, %d out of reach (all hand-diggable with the shovel)"):format(reach, byHand))
end

-- ============================================================================
-- CONTAINMENT CHAMBER -- fills up, warning lights walk red -> amber -> green
-- ============================================================================
local chamberFill, chamberLights, chamberLid = nil, {}, nil
local chamberTop, chamberBottom, chamberCF, chamberSize

local function buildChamberFX()
	if not chamber then return end
	chamberCF, chamberSize = boundsOf(chamber)
	chamberBottom = chamberCF.Position.Y - chamberSize.Y * 0.5
	chamberTop    = chamberCF.Position.Y + chamberSize.Y * 0.5

	-- the sludge that rises inside it
	chamberFill = mk({ Name = "WasteFill",
		Size = Vector3.new(chamberSize.X * 0.82, 0.2, chamberSize.Z * 0.82),
		Color = WASTE, Material = Enum.Material.Neon, Transparency = 0.25 })
	chamberFill.CFrame = CFrame.new(chamberCF.Position.X, chamberBottom + 0.2, chamberCF.Position.Z)
	chamberFill.Parent = Workspace

	-- three warning lamps up one side
	for i = 1, 3 do
		local lamp = mk({ Name = "WarnLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9),
			Color = RED_L, Material = Enum.Material.Neon })
		lamp.CFrame = CFrame.new(
			chamberCF.Position.X + chamberSize.X * 0.55,
			chamberBottom + chamberSize.Y * (0.25 * i + 0.15),
			chamberCF.Position.Z)
		lamp.Parent = Workspace
		local li = Instance.new("PointLight"); li.Color = RED_L; li.Brightness = 2; li.Range = 10; li.Parent = lamp
		chamberLights[i] = { part = lamp, light = li }
	end

	-- blink them while the reactor is unstable
	task.spawn(function()
		local t = 0
		while not finished do
			t += 0.1
			local on = (math.sin(t * 4) > 0)
			for _, l in ipairs(chamberLights) do
				l.light.Brightness = on and 2.6 or 0.7
			end
			task.wait(0.1)
		end
		for _, l in ipairs(chamberLights) do l.light.Brightness = 2.2 end
	end)
end

local function updateChamber()
	if not chamberFill then return end
	local frac = math.clamp(loadsDone / LOADS_REQUIRED, 0, 1)
	local h = math.max(0.2, chamberSize.Y * 0.9 * frac)
	TweenService:Create(chamberFill, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size   = Vector3.new(chamberSize.X * 0.82, h, chamberSize.Z * 0.82),
		CFrame = CFrame.new(chamberCF.Position.X, chamberBottom + h * 0.5, chamberCF.Position.Z),
	}):Play()

	-- lights walk red -> amber -> green as the load count climbs
	local stage = (frac >= 1 and 3) or (frac >= 0.5 and 2) or 1
	local col = (stage == 3 and GREEN_L) or (stage == 2 and AMBER_L) or RED_L
	for _, l in ipairs(chamberLights) do
		TweenService:Create(l.part, TweenInfo.new(0.4), { Color = col }):Play()
		l.light.Color = col
	end
end

local function sealChamber()
	if not chamber then return end
	-- a lid slams down over the top
	chamberLid = mk({ Name = "ChamberLid",
		Size = Vector3.new(chamberSize.X * 1.05, 0.8, chamberSize.Z * 1.05),
		Color = STEEL, Material = Enum.Material.DiamondPlate, CanCollide = true })
	chamberLid.CFrame = CFrame.new(chamberCF.Position.X, chamberTop + 14, chamberCF.Position.Z)
	chamberLid.Parent = Workspace

	local slam = TweenService:Create(chamberLid, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{ CFrame = CFrame.new(chamberCF.Position.X, chamberTop + 0.4, chamberCF.Position.Z) })
	slam.Completed:Connect(function()
		playSound(SOUND_CLUNK, 0.9)
		-- shock ring + a thump you can feel
		local ring = mk({ Name = "SealRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 4, 4),
			Color = GREEN_L, Material = Enum.Material.Neon, Transparency = 0.15 })
		ring.CFrame = CFrame.new(chamberCF.Position.X, chamberTop + 0.6, chamberCF.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = Workspace
		TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.7, 60, 60), Transparency = 1 }):Play()
		Debris:AddItem(ring, 1.1)

		local cam = Workspace.CurrentCamera
		if cam then
			task.spawn(function()
				local t0 = os.clock()
				while os.clock() - t0 < 0.45 do
					local left = 0.45 - (os.clock() - t0)
					local m = (left / 0.45) ^ 2 * 1.6
					cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
					RunService.RenderStepped:Wait()
				end
			end)
		end
	end)
	slam:Play()
end

-- ============================================================================
-- HUD -- the operator console
-- ============================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "CraneConsole"; gui.ResetOnSpawn = false; gui.DisplayOrder = 12
gui.IgnoreGuiInset = true; gui.Enabled = false; gui.Parent = PlayerGui

local console = Instance.new("Frame")
console.AnchorPoint = Vector2.new(0.5, 1)
console.Position = UDim2.new(0.5, 0, 1, -16)
console.Size = UDim2.new(0, 720, 0, 288)
console.BackgroundColor3 = PANEL
console.BorderSizePixel = 0
console.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = console
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(10, 11, 13); s.Thickness = 3; s.Parent = console
	-- brushed-metal falloff down the panel
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(46, 50, 57), Color3.fromRGB(24, 26, 30))
	g.Rotation = 90; g.Parent = console
end

-- ===== RED "the crane can't reach the rest" alert -- a full-screen red wash with the message +
-- a big EXIT button (named "RedExit"). Lives inside the console gui, so it only shows while you're
-- operating the crane. refreshHUD toggles its .Visible (found by name) and the EXIT button is wired
-- next to btnExit. Wrapped in do...end so none of this leaks a top-level local (Luau caps at 200). =====
do
	-- The stuck alert is its OWN ScreenGui with a high DisplayOrder, so it is GUARANTEED to render on
	-- top of the crane console (no ZIndex/parent ambiguity). refreshHUD + the assist toggle
	-- alertGui.Enabled; setOperating hides it on exit. Active frame = modal. All wrapped in do...end
	-- so nothing leaks a top-level local (Luau caps functions at 200 registers).
	local alertGui = Instance.new("ScreenGui")
	alertGui.Name = "CraneStuckGui"; alertGui.ResetOnSpawn = false; alertGui.IgnoreGuiInset = true
	alertGui.DisplayOrder = 60; alertGui.Enabled = false; alertGui.Parent = PlayerGui
	local redAlert = Instance.new("Frame")
	redAlert.Name = "CraneStuckAlert"; redAlert.Active = true
	redAlert.AnchorPoint = Vector2.new(0.5, 1); redAlert.Position = UDim2.new(0.5, 0, 1, -16); redAlert.Size = UDim2.new(0, 740, 0, 300)
	redAlert.BackgroundColor3 = Color3.fromRGB(150, 28, 22); redAlert.BackgroundTransparency = 0.02
	redAlert.BorderSizePixel = 0; redAlert.Parent = alertGui
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 14); rc.Parent = redAlert
	local rst = Instance.new("UIStroke"); rst.Color = Color3.fromRGB(255, 96, 74); rst.Thickness = 3; rst.Parent = redAlert
	local rg = Instance.new("UIGradient"); rg.Rotation = 90
	rg.Color = ColorSequence.new(Color3.fromRGB(176, 34, 26), Color3.fromRGB(120, 20, 16)); rg.Parent = redAlert
	local raMsg = Instance.new("TextLabel")
	raMsg.AnchorPoint = Vector2.new(0.5, 0); raMsg.Position = UDim2.new(0.5, 0, 0, 30); raMsg.Size = UDim2.new(1, -44, 0, 160)
	raMsg.BackgroundTransparency = 1; raMsg.Font = Enum.Font.GothamBlack; raMsg.TextScaled = true; raMsg.TextWrapped = true
	raMsg.Text = "\xE2\x9B\x8F THE CRANE CAN'T REACH THE REST!\n\nExit the machine and dig out the last piles with the Secret Shovel."
	raMsg.TextColor3 = Color3.fromRGB(255, 238, 230); raMsg.TextStrokeColor3 = Color3.new(0, 0, 0); raMsg.TextStrokeTransparency = 0
	raMsg.Parent = redAlert
	local sz1 = Instance.new("UITextSizeConstraint"); sz1.MaxTextSize = 30; sz1.Parent = raMsg
	local redExitBtn = Instance.new("TextButton")
	redExitBtn.Name = "RedExit"
	redExitBtn.AnchorPoint = Vector2.new(0.5, 1); redExitBtn.Position = UDim2.new(0.5, 0, 1, -28); redExitBtn.Size = UDim2.fromOffset(340, 60)
	redExitBtn.BackgroundColor3 = Color3.fromRGB(255, 236, 226); redExitBtn.AutoButtonColor = true
	redExitBtn.Font = Enum.Font.GothamBlack; redExitBtn.Text = "\xE2\x9C\x96 EXIT THE MACHINE"; redExitBtn.TextScaled = true
	redExitBtn.TextColor3 = Color3.fromRGB(150, 26, 22); redExitBtn.Parent = redAlert
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = redExitBtn
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(120, 20, 16); st.Thickness = 2; st.Parent = redExitBtn
	local sz2 = Instance.new("UITextSizeConstraint"); sz2.MaxTextSize = 24; sz2.Parent = redExitBtn
	task.spawn(function()
		local t = 0
		while true do
			t += 0.08
			if alertGui.Enabled then
				rst.Transparency = (math.sin(t * 4) * 0.5 + 0.5) * 0.55
				redExitBtn.Size = UDim2.fromOffset(340 + math.sin(t * 5) * 12, 60)
			end
			task.wait(0.08)
		end
	end)
end

-- ---- helpers ---------------------------------------------------------------
local function bevel(inst, radius, strokeCol)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, radius or 8); c.Parent = inst
	local s = Instance.new("UIStroke"); s.Color = strokeCol or Color3.fromRGB(12, 13, 15); s.Thickness = 2; s.Parent = inst
	return s
end
local function mkPanel(x, y, w, h, col)
	local f = Instance.new("Frame")
	f.Position = UDim2.new(0, x, 0, y); f.Size = UDim2.new(0, w, 0, h)
	f.BackgroundColor3 = col or Color3.fromRGB(18, 20, 23); f.BorderSizePixel = 0; f.Parent = console
	bevel(f, 8, Color3.fromRGB(8, 9, 11))
	return f
end
local function mkText(parent, txt, x, y, w, h, col, size, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1; l.Position = UDim2.new(0, x, 0, y); l.Size = UDim2.new(0, w, 0, h)
	l.Font = Enum.Font.RobotoMono; l.Text = txt; l.TextColor3 = col or STEEL; l.TextSize = size or 11
	l.TextXAlignment = align or Enum.TextXAlignment.Left; l.Parent = parent
	return l
end

-- ---- hazard-striped header -------------------------------------------------
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 28); header.BackgroundColor3 = HAZARD; header.BorderSizePixel = 0
header.Parent = console
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = header
	-- The sixteen diagonal hazard chevrons are gone. They were the loudest thing on a panel
	-- whose actual job is two buttons and one sentence, and stripes behind text are the first
	-- thing that makes a readout hard to read.
end
mkText(header, "BEANLIFT  //  REACTOR CLEANUP", 14, 0, 340, 28, Color3.fromRGB(28, 24, 8), 13).TextYAlignment = Enum.TextYAlignment.Center
local hdrRight = mkText(header, "SYS: NOMINAL", -170, 0, 156, 28, Color3.fromRGB(28, 24, 8), 11, Enum.TextXAlignment.Right)
hdrRight.Position = UDim2.new(1, -14, 0, 0); hdrRight.AnchorPoint = Vector2.new(1, 0)
hdrRight.TextYAlignment = Enum.TextYAlignment.Center
hdrRight.Visible = false                 -- "SYS: NOMINAL" never said anything you could act on

-- ---- BIG PLAIN-ENGLISH PROMPT + small telemetry ----------------------------
local hintBar = mkPanel(12, 38, 696, 40, Color3.fromRGB(16, 19, 22))
local hintLbl = mkText(hintBar, "", 12, 0, 672, 40, Color3.fromRGB(255, 226, 150), 17)
hintLbl.TextYAlignment = Enum.TextYAlignment.Center; hintLbl.TextWrapped = true

local depthTrack = Instance.new("Frame")
depthTrack.Position = UDim2.new(0, 12, 1, -7); depthTrack.Size = UDim2.new(0, 424, 0, 4)
depthTrack.BackgroundColor3 = Color3.fromRGB(10, 11, 13); depthTrack.BorderSizePixel = 0
depthTrack.Parent = hintBar
local depthFill = Instance.new("Frame")
depthFill.Size = UDim2.new(0, 0, 1, 0); depthFill.BackgroundColor3 = AMBER
depthFill.BorderSizePixel = 0; depthFill.Parent = depthTrack
depthTrack.Visible = false               -- the hook-depth bar goes with the depth readout

-- DEPTH AND SLEW READOUTS, HIDDEN. The crane drives itself; a boom angle in degrees is
-- telemetry for somebody flying it by hand, and nobody here is. They still update, so
-- turning either back on is one Visible.
local depthLbl = mkText(hintBar, "-00.0m", 452, 3, 110, 16, AMBER, 12)
local slewLbl  = mkText(hintBar, "000\xC2\xB0", 452, 21, 110, 16, AMBER, 12)
depthLbl.Visible = false
slewLbl.Visible  = false
local loadLbl  = mkText(hintBar, "EMPTY", 572, 0, 116, 40, STEEL, 12)
loadLbl.TextYAlignment = Enum.TextYAlignment.Center

-- No manual arm/roller buttons: the crane drives itself. Two buttons is the whole game.
-- (WASD / arrows / Q / E still work as a hidden manual override for anyone who wants it,
--  and using them cancels the assist -- but nothing on screen asks a kid to learn them.)

-- ---- containment + actions -------------------------------------------------
local contPanel = mkPanel(12, 202, 420, 34)
mkText(contPanel, "BIN", 10, 0, 40, 34, STEEL, 10).TextYAlignment = Enum.TextYAlignment.Center
local segFrames = {}
buildSegments = function()   -- rebuilt once the real number of waste piles is known
	for _, s in ipairs(segFrames) do s:Destroy() end
	segFrames = {}
	local n = math.max(1, LOADS_REQUIRED)
	local w = math.floor((300 - (n - 1) * 6) / n)
	for i = 1, n do
		local s = Instance.new("Frame")
		s.Position = UDim2.new(0, 52 + (i - 1) * (w + 6), 0, 7); s.Size = UDim2.new(0, w, 0, 20)
		s.BackgroundColor3 = Color3.fromRGB(46, 48, 54); s.BorderSizePixel = 0; s.Parent = contPanel
		bevel(s, 4, Color3.fromRGB(8, 9, 11))
		segFrames[i] = s
	end
end
buildSegments()

-- the three lamps, mirroring the chamber's
local lampRow = Instance.new("Frame")
lampRow.BackgroundTransparency = 1; lampRow.Position = UDim2.new(0, 364, 0, 6); lampRow.Size = UDim2.new(0, 84, 0, 22)
lampRow.Parent = contPanel
local hudLamps = {}
for i = 1, 3 do
	local l = Instance.new("Frame")
	l.Size = UDim2.new(0, 22, 0, 22); l.Position = UDim2.new(0, (i - 1) * 30, 0, 0)
	l.BackgroundColor3 = RED_L; l.BorderSizePixel = 0; l.Parent = lampRow
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = l
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(8, 9, 11); s.Thickness = 2; s.Parent = l
	hudLamps[i] = l
end
lampRow.Visible = false                  -- the three lamps only repeat the BIN bar beside them

local function mkButton(text, x, y, w, h, tint)
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(0, x, 0, y); b.Size = UDim2.new(0, w, 0, h)
	b.BackgroundColor3 = tint or PANEL_2; b.BorderSizePixel = 0; b.AutoButtonColor = false
	b.Font = Enum.Font.RobotoMono; b.Text = text; b.TextColor3 = Color3.fromRGB(238, 242, 247); b.TextScaled = true
	b.Parent = console
	bevel(b, 8, Color3.fromRGB(9, 10, 12))
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 16; sz.Parent = b
	return b
end

-- THE EASY BUTTON: one press drives the whole crane to whatever you need next.
-- A kid can finish the entire job with just this and GRAB.
-- THE WHOLE GAME: two big buttons. Press the blue one, then the green one. Repeat.
local btnAssist = mkButton("FIND WASTE", 12, 86, 344, 104, Color3.fromRGB(46, 84, 128))
btnAssist.TextSize = 30
local btnGrab   = mkButton("GRAB", 364, 86, 344, 104, Color3.fromRGB(52, 104, 60))
btnGrab.TextSize = 30

local btnExit = mkButton("LEAVE", 440, 202, 268, 34, Color3.fromRGB(84, 44, 46))
-- pulse the exit button red when the crane can't reach the last piles (attribute set in refreshHUD)
task.spawn(function()
	local t, base, hot = 0, Color3.fromRGB(84, 44, 46), Color3.fromRGB(226, 62, 58)
	while true do
		t += 0.08
		if btnExit:GetAttribute("pulse") then
			btnExit.BackgroundColor3 = base:Lerp(hot, math.sin(t * 5) * 0.5 + 0.5)
		else
			btnExit.BackgroundColor3 = base
		end
		task.wait(0.08)
	end
end)

-- ---- status strip ----------------------------------------------------------
local statusBar = mkPanel(12, 244, 480, 32, Color3.fromRGB(14, 16, 18))
local statusLbl = mkText(statusBar, "READY", 12, 0, 456, 32, AMBER, 13)
statusLbl.TextYAlignment = Enum.TextYAlignment.Center

-- ---- sample log: the analysis of the last load you tipped in ----------------
local sampleBar = mkPanel(500, 244, 208, 32, Color3.fromRGB(12, 18, 13))
local sampleLbl = mkText(sampleBar, "no samples yet", 10, 0, 190, 32, WASTE, 11)
sampleLbl.TextYAlignment = Enum.TextYAlignment.Center; sampleLbl.TextWrapped = true

-- manual override, keyboard only -- nothing on the HUD advertises it
local held = { left = false, right = false, down = false, up = false, dback = false, dfwd = false }

-- keyboard, for the "actually operating machinery" feel
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not operating then return end
	local k = input.KeyCode
	if     k == Enum.KeyCode.A or k == Enum.KeyCode.Left  then held.left  = true
	elseif k == Enum.KeyCode.D or k == Enum.KeyCode.Right then held.right = true
	elseif k == Enum.KeyCode.S or k == Enum.KeyCode.Down  then held.down  = true
	elseif k == Enum.KeyCode.W or k == Enum.KeyCode.Up    then held.up    = true
	elseif k == Enum.KeyCode.Q                            then held.dback = true
	elseif k == Enum.KeyCode.E                            then held.dfwd  = true
	end
end)
UserInputService.InputEnded:Connect(function(input)
	local k = input.KeyCode
	if     k == Enum.KeyCode.A or k == Enum.KeyCode.Left  then held.left  = false
	elseif k == Enum.KeyCode.D or k == Enum.KeyCode.Right then held.right = false
	elseif k == Enum.KeyCode.S or k == Enum.KeyCode.Down  then held.down  = false
	elseif k == Enum.KeyCode.W or k == Enum.KeyCode.Up    then held.up    = false
	elseif k == Enum.KeyCode.Q                            then held.dback = false
	elseif k == Enum.KeyCode.E                            then held.dfwd  = false
	end
end)

local statusText = ""
local function setStatus(t) statusText = t end

-- ============================================================================
-- SAMPLE READINGS -- every load you tip into the bin gets analysed. Irradiated
-- cocoa: the isotopes are chocolate, the hazard notes are deadpan lab-speak.
-- ============================================================================
local ISOTOPES = {
	"Cocoa-60", "Cacaosium-137", "Theobromine-90", "Chocotope-131",
	"Beanium-241", "Nougatium-235", "Fudgeon-99", "Praline-210",
}
local FINDINGS_NOTES = {
	"Still warm. Nobody knows why.",
	"Smells incredible. That is the problem.",
	"Glows in the dark; tastes of glowing.",
	"Half-life measured in snack breaks.",
	"Emits 4% more flavour than the legal limit.",
	"Technically a dessert. Legally a hazard.",
	"Cocoa content: 94%. Remainder: unclear.",
	"Melts at room temperature and through the floor.",
	"Sample bit the tongs.",
	"Do NOT add milk.",
}

local function makeReading(idx)
	local iso  = ISOTOPES[((idx - 1) % #ISOTOPES) + 1]
	local note = FINDINGS_NOTES[((idx * 3 - 1) % #FINDINGS_NOTES) + 1]
	return {
		id      = idx,
		isotope = iso,
		mass    = 2.4 + ((idx * 7) % 9) * 0.6,       -- kg, deterministic per sample
		dose    = 180 + ((idx * 137) % 700),          -- mSv
		note    = note,
		filed   = false,
	}
end

local function readingLine(r)
	return ("SAMPLE %02d  %s  %.1fkg  %d mSv"):format(r.id, r.isotope, r.mass, r.dose)
end

local function refreshHUD()
	local drop = rig and rig.drop or 0
	local frac = loadsDone / LOADS_REQUIRED
	local stage = (frac >= 1 and 3) or (frac >= 0.5 and 2) or 1
	local col   = (stage == 3 and GREEN_L) or (stage == 2 and AMBER_L) or RED_L

	-- gauges
	depthFill.Size = UDim2.new(math.clamp(drop / MAX_DROP, 0, 1), 0, 1, 0)
	depthLbl.Text  = ("-%04.1fm"):format(drop)
	slewLbl.Text   = ("%03d\xC2\xB0  R%+05.1f"):format(
		math.floor((rig and rig.slewAngle or 0) % 360), rig and rig.drive or 0)
	loadLbl.Text   = carrying and "HOLDING\nWASTE" or "CRATE\nEMPTY"
	loadLbl.TextColor3 = carrying and WASTE or STEEL

	-- the big plain-English prompt: always says what to do NEXT
	btnAssist.Text = carrying and "GO TO BIN" or "FIND WASTE"
	if finished then
		hintLbl.Text = "All done! Press LEAVE and go file your findings."
	elseif carrying then
		hintLbl.Text = "Nice! Press GO TO BIN, then press DROP."
	else
		hintLbl.Text = "Press FIND WASTE, then press GRAB."
	end

	-- crane can't reach the last piles -> tell them to EXIT and go find the shovel (pulses the button)
	-- crane out of reach but piles remain -> EXIT and finish by hand. Shown while operating, but NOT
	-- mid-carry (so the last crane drop isn't blocked by the modal red panel).
	local craneStuck = questAccepted and not finished and not carrying and craneWorkLeft and craneWorkLeft() == 0 and unreachableLeft and unreachableLeft() > 0
	if craneStuck then
		hintLbl.Text = hasShovel and "The crane can't reach the rest!\nEXIT and dig them out with the shovel."
			or "The crane can't reach the rest!\nEXIT and go find the Secret Shovel."
		btnExit.Text = "\xE2\x9B\x8F EXIT THE MACHINE"
		btnExit:SetAttribute("pulse", true)
	else
		if btnExit.Text ~= "LEAVE" then btnExit.Text = "LEAVE" end
		btnExit:SetAttribute("pulse", false)
	end
	local ag = PlayerGui:FindFirstChild("CraneStuckGui")   -- the full red panel over the console
	if ag then ag.Enabled = craneStuck and operating end

	-- containment segments fill left to right
	for i, s in ipairs(segFrames) do
		s.BackgroundColor3 = (i <= loadsDone) and col or Color3.fromRGB(46, 48, 54)
	end
	for i, l in ipairs(hudLamps) do
		l.BackgroundColor3 = (i <= stage) and col or Color3.fromRGB(60, 62, 68)
	end

	-- status strip: warnings (the "!!" ones) go red so a bad grab is obvious
	local warn = string.find(statusText, "!!", 1, true) ~= nil
	statusLbl.Text = (statusText ~= "" and statusText) or "READY"
	statusLbl.TextColor3 = warn and RED_L or AMBER
	statusBar.BackgroundColor3 = warn and Color3.fromRGB(44, 16, 18) or Color3.fromRGB(14, 16, 18)

	hdrRight.Text = finished and "SYS: CONTAINED" or (stage == 1 and "SYS: CRITICAL" or "SYS: UNSTABLE")

	-- latest analysis line
	local last = readings[#readings]
	if last then
		sampleLbl.Text = ("%s  --  %s"):format(readingLine(last), last.note)
	end

	btnGrab.Text = carrying and "DROP" or "GRAB"
	btnGrab.BackgroundColor3 = carrying and Color3.fromRGB(126, 78, 42) or Color3.fromRGB(52, 104, 60)
end

-- ============================================================================
-- OPERATING THE CRANE
-- ============================================================================
-- the crane only ever considers piles it can actually reach; the rest are hand jobs
local function nearestPile()
	local hp, best, bestD = hookPosition(), nil, nil
	for _, p in ipairs(piles) do
		if not p.taken and p.reachable ~= false then
			local d = (p.pos - hp).Magnitude
			if not bestD or d < bestD then best, bestD = p, d end
		end
	end
	return best, bestD
end

local function overChamber()
	if not chamber then return false end
	local hp = hookPosition()
	local flat = (hp - chamberCF.Position) * Vector3.new(1, 0, 1)
	return flat.Magnitude <= math.max(chamberSize.X, chamberSize.Z) * 0.75 + 3
end

-- One load is in the bin -- however it got there (crane or carried by hand). Analyses it,
-- updates the chamber, and closes the job out when the last one lands.
registerLoad = function()
	loadsDone += 1

	-- the bin analyses whatever was just tipped in; the full readout lands on the
	-- ANALYSIS strip, the status line just confirms the load
	readings[#readings + 1] = makeReading(loadsDone)

	updateChamber()
	refreshHUD()
	if loadsDone >= LOADS_REQUIRED then
		finished = true
		setStatus("<< CONTAINED -- FILE YOUR FINDINGS >>")
		refreshBanner()
		sealChamber()
		task.delay(1.2, function()
			if _G.NotifyCenter then
				pcall(function() _G.NotifyCenter.push({ text = "\xE2\x98\xA2 Reactor stabilised! Containment sealed.", color = GREEN_L }) end)
			end
		end)
		print("[Cleanup] complete -- containment sealed")
	else
		setStatus(("LOAD %d STOWED"):format(loadsDone))
	end
end

local function tryGrab()
	if carrying then
		-- DROP
		if overChamber() then
			-- into the chamber it goes
			local pile = carriedPile
			carrying, carriedPile = false, nil
			if pile and pile.model then
				local m = pile.model
				local drop = TweenService:Create(m.PrimaryPart, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = CFrame.new(chamberCF.Position.X, chamberBottom + 1, chamberCF.Position.Z) })
				drop.Completed:Connect(function()
					m:Destroy()
					registerLoad()
				end)
				drop:Play()
			end
		else
			setStatus("!! NOT OVER CHAMBER")
		end
		refreshHUD()
		return
	end

	-- GRAB
	local pile, d = nearestPile()
	if not pile then setStatus("NO WASTE REMAINING"); refreshHUD(); return end
	if d > GRAB_RADIUS then
		setStatus("!! HOOK NOT OVER WASTE")
		refreshHUD()
		return
	end
	pile.taken = true
	carrying, carriedPile = true, pile
	setStatus("LOAD SECURED")
	-- clamp shut
	if rig and rig.hookJaw then
		TweenService:Create(rig.hookJaw, TweenInfo.new(0.2), { Size = rig.hookJaw.Size * Vector3.new(0.8, 1, 0.8) }):Play()
	end
	applyRig()      -- snap the load under the hook right away, before anything else moves
	refreshHUD()
end

btnGrab.MouseButton1Click:Connect(tryGrab)

-- ============================================================================
-- THE ASSIST -- "FIND WASTE" / "GO TO BIN". Works out the slew, roll and hoist
-- needed to park the crate over a target and drives them there for you. Any
-- manual input cancels it, so it never fights the player.
-- ============================================================================
local autoTarget = nil     -- { pos = Vector3, mode = "pile" | "bin" }

local function flatDir(v) local f = v * Vector3.new(1, 0, 1); return (f.Magnitude > 0.01) and f.Unit or Vector3.new(0, 0, 1) end

-- How far round to swing so the crate lines up with `pos`, how far to roll, and how far
-- to lower so the crate's underside hovers `clearance` above `topY` -- the real height of
-- that particular pile or the bin's rim, not a fixed guess.
solveFor = function(pos, topY, clearance)
	if not (rig and rig.crateRestPos) then return nil end
	local c = rig.slewCenter
	local restDir = flatDir(rig.crateRestPos - c)
	local wantDir = flatDir(pos - c)
	-- signed angle about Y, in degrees, normalised to the shortest way round
	local a = math.deg(math.atan2(wantDir.X, wantDir.Z) - math.atan2(restDir.X, restDir.Z))
	while a > 180 do a -= 360 end
	while a < -180 do a += 360 end

	-- after slewing, where does the crate sit? roll the machine to close whatever gap is
	-- left. This is the forward/back axis, driven automatically and clamped to DRIVE_RANGE.
	local radius   = ((rig.crateRestPos - c) * Vector3.new(1, 0, 1)).Magnitude
	local landing  = c + wantDir * radius
	local residual = (pos - landing) * Vector3.new(1, 0, 1)
	local wantRoll = residual:Dot(rig.boomDir or Vector3.new(0, 0, 1))
	local roll     = math.clamp(wantRoll, -DRIVE_RANGE, DRIVE_RANGE)

	-- how close will we actually get once slew + roll are done?
	local finalPos = landing + (rig.boomDir or Vector3.new(0, 0, 1)) * roll
	local miss     = ((pos - finalPos) * Vector3.new(1, 0, 1)).Magnitude

	-- pay the rope out until the crate's UNDERSIDE sits just over the target's top face
	local aimTop = topY or pos.Y
	local dropWanted = math.clamp(rig.crateBottomRestY - (aimTop + (clearance or 1.5)), 0, MAX_DROP)
	return { slew = a, roll = roll, drop = dropWanted, miss = miss, clamped = math.abs(wantRoll) > DRIVE_RANGE }
end

local function startAssist()
	if not rig then return end
	if carrying then
		if not chamber then setStatus("!! NO BIN TO DROP INTO"); refreshHUD(); return end
		-- hold the crate clear above the bin's rim so it tips in rather than through it
		autoTarget = { pos = chamberCF.Position, topY = chamberTop, clearance = 4, mode = "bin" }
		setStatus("AUTO: HEADING TO THE BIN")
	else
		local pile = nearestPile()
		if not pile then
			-- crane's done everything in its reach. Anything left is a hand job.
			if unreachableLeft() > 0 then
				setStatus("!! CAN'T GRAB IT -- EXIT + USE THE SHOVEL")
				hintLbl.Text = "Oh no! The crane can't reach those last piles.\nEXIT and dig them out with the shovel!"
				local ag = PlayerGui:FindFirstChild("CraneStuckGui")   -- show the big red exit panel now
				if ag then ag.Enabled = true end
				print("[Cleanup] crane out of reach -- red EXIT panel shown")
				if _G.NotifyCenter then
					pcall(function() _G.NotifyCenter.push({
						text = "\xE2\x9B\x8F Can't grab it! Exit and use the shovel.", color = HAZARD }) end)
				end
			else
				setStatus("NO WASTE LEFT")
			end
			refreshHUD()
			return
		end
		autoTarget = { pos = pile.pos, topY = pile.topY, clearance = 1.2, mode = "pile" }
		setStatus("AUTO: HEADING TO THE WASTE")
	end
	refreshHUD()
end

btnAssist.MouseButton1Click:Connect(startAssist)

-- Taking the controls puts you IN the crane: you're lifted into the operator station,
-- anchored there, and the camera drops into a cab view down the boom. WASD then drives
-- the machine instead of your legs, and you swing round with it when you slew.
local engineWorking = false   -- true while the crane is being driven (smoke thickens)
local savedWalk, savedJump, returnCF
local function setOperating(on)
	operating = on
	gui.Enabled = on
	if not on then   -- leaving the crane -> always drop the red stuck panel
		local ag = PlayerGui:FindFirstChild("CraneStuckGui")
		if ag then ag.Enabled = false end
	end
	for k in pairs(held) do held[k] = false end

	local char = player.Character
	local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local cam  = Workspace.CurrentCamera

	if on then
		-- freeze you where you stand (so you can't wander off while looking through the
		-- crane) but DON'T move, anchor or platform-stand the character -- that's what was
		-- ejecting you.
		if hum then
			savedWalk, savedJump = hum.WalkSpeed, hum.JumpPower
			hum.WalkSpeed, hum.JumpPower = 0, 0
		end
		if hrp then returnCF = hrp.CFrame end
		if cam then cam.CameraType = Enum.CameraType.Scriptable end
		applyRig()                            -- points the camera at the crate
		setStatus("READY")
		refreshHUD()
	else
		-- roll the machine back to its parked spot: the drive is only ever a loan, so from
		-- outside the crane is exactly where it has always been.
		if rig and (rig.drive or 0) ~= 0 then
			rig.drive = 0
			applyRig()
		end
		if onExitBoard then onExitBoard() end   -- stop the pad boarding you straight back in
		if hum then
			hum.WalkSpeed = savedWalk or 16
			hum.JumpPower = savedJump or 50
		end
		if cam then
			cam.CameraType = Enum.CameraType.Custom
			if hum then cam.CameraSubject = hum end
		end
	end
end

btnExit.MouseButton1Click:Connect(function() setOperating(false) end)
do   -- the red-alert EXIT button (found by name so it costs no top-level local)
	local ag = PlayerGui:FindFirstChild("CraneStuckGui")
	local ra = ag and ag:FindFirstChild("CraneStuckAlert")
	local rb = ra and ra:FindFirstChild("RedExit")
	if rb then rb.MouseButton1Click:Connect(function() setOperating(false) end) end
end

-- dying at the controls shouldn't leave you frozen or stuck in the console
player.CharacterAdded:Connect(function()
	savedWalk, savedJump = nil, nil
	if operating then setOperating(false) end
end)

-- the motion loop: eased slew + hoist while a control is held
local motorPlaying = false
RunService.RenderStepped:Connect(function(dt)
	if not (operating and rig) then return end
	local moved = false

	if held.left  then rig.slewAngle -= SLEW_SPEED * dt; moved = true end
	if held.right then rig.slewAngle += SLEW_SPEED * dt; moved = true end
	if held.down  then rig.drop = math.min(MAX_DROP, rig.drop + HOIST_SPEED * dt); moved = true end
	if held.up    then rig.drop = math.max(0,        rig.drop - HOIST_SPEED * dt); moved = true end
	if held.dfwd  then rig.drive = math.min( DRIVE_RANGE, (rig.drive or 0) + DRIVE_SPEED * dt); moved = true end
	if held.dback then rig.drive = math.max(-DRIVE_RANGE, (rig.drive or 0) - DRIVE_SPEED * dt); moved = true end

	-- touching anything manually takes the assist off -- it must never fight the player
	if moved and autoTarget then autoTarget = nil; setStatus("MANUAL CONTROL") end

	-- ...otherwise the assist drives for you
	if autoTarget and not moved then
		local want = solveFor(autoTarget.pos, autoTarget.topY, autoTarget.clearance)
		if not want then
			autoTarget = nil
		else
			local function ease(cur, target, rate)
				local d = target - cur
				local step = rate * AUTO_SPEED * dt
				if math.abs(d) <= step then return target, true end
				return cur + (d > 0 and step or -step), false
			end

			-- A real crane works in three beats: LIFT clear, SWING over, then LOWER onto
			-- the target. Doing it in that order stops the crate (and its load) dragging
			-- through the ground or the piles on the way past.
			local phase = autoTarget.phase or "raise"
			local arrived = false

			if phase == "raise" then
				local up
				rig.drop, up = ease(rig.drop, 0, HOIST_SPEED)
				setStatus("AUTO: LIFTING CLEAR")
				if up then autoTarget.phase = "move" end

			elseif phase == "move" then
				local okS, okR
				rig.slewAngle, okS = ease(rig.slewAngle, want.slew, SLEW_SPEED)
				rig.drive,     okR = ease(rig.drive or 0, want.roll, DRIVE_SPEED)
				setStatus(autoTarget.mode == "bin" and "AUTO: SWINGING OVER THE BIN" or "AUTO: SWINGING OVER THE WASTE")
				if okS and okR then autoTarget.phase = "lower" end

			else -- lower onto it
				local okD
				rig.drop, okD = ease(rig.drop, want.drop, HOIST_SPEED)
				setStatus("AUTO: LOWERING")
				arrived = okD
			end

			applyRig()
			refreshHUD()

			if arrived then
				-- arrived: do the obvious thing
				local mode = autoTarget.mode
				autoTarget = nil
				if mode == "pile" then
					if not carrying then
						tryGrab()
						-- the rollers are capped, so a pile further out than the cane can
						-- reach leaves us short. Say so plainly instead of a cryptic miss.
						if not carrying then
							setStatus(want.clamped and "!! THAT PILE IS TOO FAR OUT" or "!! COULDN'T REACH IT")
						end
					end
				else
					if carrying then
						tryGrab()
						-- still holding it? then we never actually got over the bin
						if carrying then
							setStatus(want.clamped and "!! THE BIN IS TOO FAR OUT" or "!! COULDN'T LINE UP ON THE BIN")
						end
					end
				end
				refreshHUD()
			end
			return
		end
	end

	if moved then
		applyRig()
		if not motorPlaying then motorPlaying = true; playSound(SOUND_MOTOR, 0.35) end
		refreshHUD()
	else
		motorPlaying = false
	end

	engineWorking = moved or (autoTarget ~= nil)
end)
-- (there's deliberately no "walked too far away" auto-exit: you're anchored in the cab,
--  which sits ~26 studs above the slew axis, and that check was ejecting you instantly.)

-- ============================================================================
-- THE ENGINE -- the crane is ALWAYS running: it idles with a thin haze and a
-- ticking-over ambience whether or not anyone's at the controls, and works
-- harder while it's actually being driven. Runs in its own loop so it never
-- stops just because the operating loop returned early.
-- ============================================================================
RunService.RenderStepped:Connect(function(dt)
	if not (rig and rig.smokes) then return end
	if not operating then engineWorking = false end   -- nobody driving: back to idle

	-- idle is already a heavy column; working just pushes it higher and wider
	local k = math.min(1, dt * 3)
	for i, sm in ipairs(rig.smokes) do
		local baseSize    = 14 + i * 3
		local wantSize    = engineWorking and (baseSize + 8) or baseSize
		local wantRise    = engineWorking and 25 or 20
		local wantOpacity = 1
		sm.Opacity      = wantOpacity
		sm.RiseVelocity = sm.RiseVelocity + (wantRise - sm.RiseVelocity) * k
		sm.Size         = sm.Size         + (wantSize - sm.Size) * k
	end

	-- the ambience revs a little with it, and never stops
	if rig.siteSound then
		local wantVol = engineWorking and (SITE_VOLUME * 1.5) or SITE_VOLUME
		rig.siteSound.Volume = rig.siteSound.Volume + (wantVol - rig.siteSound.Volume) * k
		if not rig.siteSound.IsPlaying then rig.siteSound:Play() end
	end
end)

-- ============================================================================
-- THE FINDINGS TERMINAL -- built on the block(s) named "Findings". Once the bin
-- is full you walk over and type the samples up. Filing them all ends the job.
-- ============================================================================
local termGui = Instance.new("ScreenGui")
termGui.Name = "FindingsTerminal"; termGui.ResetOnSpawn = false; termGui.DisplayOrder = 14
termGui.IgnoreGuiInset = true; termGui.Enabled = false; termGui.Parent = PlayerGui

local termFrame = Instance.new("Frame")
termFrame.AnchorPoint = Vector2.new(0.5, 0.5); termFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
termFrame.Size = UDim2.new(0, 560, 0, 420); termFrame.BackgroundColor3 = Color3.fromRGB(10, 16, 12)
termFrame.BorderSizePixel = 0; termFrame.Parent = termGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = termFrame
	local s = Instance.new("UIStroke"); s.Color = WASTE; s.Thickness = 2; s.Transparency = 0.4; s.Parent = termFrame
end
do
	local hdr = Instance.new("Frame")
	hdr.Size = UDim2.new(1, 0, 0, 34); hdr.BackgroundColor3 = Color3.fromRGB(18, 34, 20); hdr.BorderSizePixel = 0
	hdr.Parent = termFrame
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = hdr
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1; t.Size = UDim2.new(1, -20, 1, 0); t.Position = UDim2.new(0, 14, 0, 0)
	t.Font = Enum.Font.RobotoMono; t.Text = "COCOA HAZARD LAB  //  FIELD DATA ENTRY"
	t.TextColor3 = WASTE; t.TextSize = 14; t.TextXAlignment = Enum.TextXAlignment.Left; t.Parent = hdr
end

local termList = Instance.new("ScrollingFrame")
termList.Position = UDim2.new(0, 12, 0, 44); termList.Size = UDim2.new(1, -24, 1, -100)
termList.BackgroundColor3 = Color3.fromRGB(8, 12, 9); termList.BorderSizePixel = 0
termList.ScrollBarThickness = 5; termList.CanvasSize = UDim2.new(0, 0, 0, 0); termList.Parent = termFrame
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = termList end

local termFoot = Instance.new("TextLabel")
termFoot.BackgroundTransparency = 1; termFoot.Position = UDim2.new(0, 14, 1, -52); termFoot.Size = UDim2.new(1, -180, 0, 22)
termFoot.Font = Enum.Font.RobotoMono; termFoot.Text = ""; termFoot.TextColor3 = STEEL; termFoot.TextSize = 12
termFoot.TextXAlignment = Enum.TextXAlignment.Left; termFoot.Parent = termFrame

local function mkTermButton(text, xFromRight, w, tint)
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, -xFromRight, 1, -14); b.Size = UDim2.new(0, w, 0, 30)
	b.BackgroundColor3 = tint; b.BorderSizePixel = 0; b.AutoButtonColor = false
	b.Font = Enum.Font.RobotoMono; b.Text = text; b.TextColor3 = Color3.fromRGB(240, 246, 240); b.TextSize = 13
	b.Parent = termFrame
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 7); c.Parent = b
	return b
end
local btnFileAll = mkTermButton("FILE ALL FINDINGS", 132, 180, Color3.fromRGB(38, 92, 46))
local btnTermX   = mkTermButton("CLOSE", 14, 108, Color3.fromRGB(60, 40, 42))

local screenLabels = {}   -- SurfaceGui text on each physical terminal, kept in sync
local refreshTerminal
local function fileReading(r)
	if r.filed then return end
	r.filed = true
	refreshTerminal()

	-- all done? that's the job finished
	local allFiled = #readings > 0
	for _, x in ipairs(readings) do if not x.filed then allFiled = false; break end end
	if allFiled and loadsDone >= LOADS_REQUIRED and not findingsFiled then
		findingsFiled = true
		_G.cleanupQuestComplete = true
		refreshBanner()
		if _G.NotifyCenter then
			pcall(function() _G.NotifyCenter.push({
				text = "\xE2\x98\xA2 Findings filed -- reactor cleanup complete!", color = GREEN_L }) end)
		end
		print("[Cleanup] findings filed -- quest complete")
	end
end

refreshTerminal = function()
	for _, ch in ipairs(termList:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end
	local y = 6
	for _, r in ipairs(readings) do
		local row = Instance.new("Frame")
		row.Position = UDim2.new(0, 6, 0, y); row.Size = UDim2.new(1, -12, 0, 46)
		row.BackgroundColor3 = r.filed and Color3.fromRGB(16, 30, 18) or Color3.fromRGB(16, 20, 17)
		row.BorderSizePixel = 0; row.Parent = termList
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = row

		local l1 = Instance.new("TextLabel")
		l1.BackgroundTransparency = 1; l1.Position = UDim2.new(0, 10, 0, 4); l1.Size = UDim2.new(1, -130, 0, 20)
		l1.Font = Enum.Font.RobotoMono; l1.Text = readingLine(r); l1.TextColor3 = WASTE; l1.TextSize = 13
		l1.TextXAlignment = Enum.TextXAlignment.Left; l1.Parent = row

		local l2 = Instance.new("TextLabel")
		l2.BackgroundTransparency = 1; l2.Position = UDim2.new(0, 10, 0, 24); l2.Size = UDim2.new(1, -130, 0, 18)
		l2.Font = Enum.Font.RobotoMono; l2.Text = r.note; l2.TextColor3 = STEEL; l2.TextSize = 11
		l2.TextXAlignment = Enum.TextXAlignment.Left; l2.Parent = row

		if r.filed then
			local ok = Instance.new("TextLabel")
			ok.BackgroundTransparency = 1; ok.AnchorPoint = Vector2.new(1, 0.5)
			ok.Position = UDim2.new(1, -10, 0.5, 0); ok.Size = UDim2.new(0, 100, 0, 24)
			ok.Font = Enum.Font.RobotoMono; ok.Text = "\xE2\x9C\x93 LOGGED"; ok.TextColor3 = GREEN_L; ok.TextSize = 13
			ok.Parent = row
		else
			local b = Instance.new("TextButton")
			b.AnchorPoint = Vector2.new(1, 0.5); b.Position = UDim2.new(1, -10, 0.5, 0); b.Size = UDim2.new(0, 100, 0, 26)
			b.BackgroundColor3 = Color3.fromRGB(38, 76, 44); b.BorderSizePixel = 0; b.AutoButtonColor = false
			b.Font = Enum.Font.RobotoMono; b.Text = "ENTER"; b.TextColor3 = Color3.fromRGB(238, 246, 238); b.TextSize = 13
			b.Parent = row
			local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = b
			b.MouseButton1Click:Connect(function() fileReading(r) end)
		end
		y += 52
	end
	termList.CanvasSize = UDim2.new(0, 0, 0, y + 6)

	local filed = 0
	for _, r in ipairs(readings) do if r.filed then filed += 1 end end
	if #readings == 0 then
		termFoot.Text = "NO SAMPLES ON FILE -- clear the waste with the crane first."
	elseif findingsFiled then
		termFoot.Text = "REPORT FILED. Reactor cleanup complete."
	else
		termFoot.Text = ("%d of %d findings entered."):format(filed, #readings)
	end
	btnFileAll.Visible = (#readings > 0) and (filed < #readings)

	-- mirror the state onto the physical terminal screens
	local screenTxt
	if #readings == 0 then
		screenTxt = "STATUS: AWAITING SAMPLES\n\nNo cocoa logged.\nClear the piles with\nthe BeanLift crane."
	elseif findingsFiled then
		screenTxt = ("STATUS: REPORT FILED\n\n%d samples logged.\nReactor stable.\nWell done, operator."):format(#readings)
	else
		screenTxt = ("STATUS: DATA PENDING\n\nSamples held: %d\nEntered: %d\n\n[E] to file findings"):format(#readings, filed)
	end
	for _, lbl in ipairs(screenLabels) do
		if lbl.Parent then lbl.Text = screenTxt end
	end
end

btnFileAll.MouseButton1Click:Connect(function()
	for _, r in ipairs(readings) do
		if not r.filed then fileReading(r) end
	end
end)
btnTermX.MouseButton1Click:Connect(function() termGui.Enabled = false end)

-- Build a real workstation on a "Findings" placement block: desk, legs, angled monitor
-- with a live green screen, keyboard, and blinking status lamps. The block itself is
-- only an anchor, so it's hidden.
local function buildTerminalAt(block)
	local part = firstBasePart(block)
	if not part then return false end

	-- the placement block is a marker only -- hide it (and anything inside it)
	for _, q in ipairs(block:IsA("Model") and block:GetDescendants() or { block }) do
		if q:IsA("BasePart") then
			q.Transparency = 1; q.CanCollide = false; q.CanQuery = false; q.Anchored = true
		end
	end

	local base   = part.CFrame                                  -- inherit however it was placed
	local topY   = part.Position.Y + part.Size.Y * 0.5
	-- keep the block's own yaw, then spin the whole workstation TERMINAL_YAW degrees
	-- counter-clockwise on top of it (+Y rotation = CCW seen from above)
	local origin = CFrame.new(Vector3.new(part.Position.X, topY, part.Position.Z))
		* (base - base.Position)
		* CFrame.Angles(0, math.rad(TERMINAL_YAW), 0)

	local model = Instance.new("Model"); model.Name = "FindingsTerminal"
	model:SetAttribute("QuestProp", true)   -- keeps Shop_AllInOne's stand scanner off it

	local DARK  = Color3.fromRGB(32, 36, 40)
	local TRIM  = Color3.fromRGB(58, 64, 70)

	local function piece(name, size, cf, colour, material, collide)
		local p = mk({ Name = name, Size = size, Color = colour or DARK,
			Material = material or Enum.Material.Metal, CanCollide = collide or false })
		p.CFrame = origin * cf
		p.Parent = model
		return p
	end

	-- desk + legs
	piece("Desk",  Vector3.new(5.0, 0.3, 2.4), CFrame.new(0, 2.55, 0), TRIM, Enum.Material.DiamondPlate, true)
	piece("LegL",  Vector3.new(0.3, 2.4, 0.3), CFrame.new(-2.1, 1.35, 0.9))
	piece("LegR",  Vector3.new(0.3, 2.4, 0.3), CFrame.new( 2.1, 1.35, 0.9))
	piece("LegBL", Vector3.new(0.3, 2.4, 0.3), CFrame.new(-2.1, 1.35, -0.9))
	piece("LegBR", Vector3.new(0.3, 2.4, 0.3), CFrame.new( 2.1, 1.35, -0.9))
	piece("Cable", Vector3.new(0.12, 1.9, 0.12), CFrame.new(1.7, 1.5, -0.7) * CFrame.Angles(0.2, 0, 0.1),
		Color3.fromRGB(18, 20, 22), Enum.Material.SmoothPlastic)

	-- monitor: bezel tilted back, with the screen face just in front of it
	local TILT = CFrame.Angles(math.rad(-12), 0, 0)
	-- NB: NOT called "Stand" -- Shop_AllInOne grabs any part whose name contains "stand"
	-- or "shop" and bolts a food-stand prompt onto it (Shop_AllInOne:990).
	piece("MonitorNeck", Vector3.new(0.9, 0.9, 0.5), CFrame.new(0, 3.05, -0.35))
	piece("Bezel",  Vector3.new(4.2, 2.8, 0.22), CFrame.new(0, 4.5, -0.45) * TILT, Color3.fromRGB(22, 25, 28))
	local screen = piece("Screen", Vector3.new(3.9, 2.5, 0.08), CFrame.new(0, 4.5, -0.32) * TILT,
		Color3.fromRGB(12, 26, 14), Enum.Material.Neon)

	-- keyboard + a couple of blinking lamps
	piece("Keyboard", Vector3.new(2.6, 0.12, 0.9), CFrame.new(0, 2.74, 0.55) * CFrame.Angles(math.rad(-6), 0, 0),
		Color3.fromRGB(26, 29, 32), Enum.Material.SmoothPlastic)
	local lampA = piece("LampA", Vector3.new(0.18, 0.18, 0.18), CFrame.new(-1.85, 2.78, 0.05), WASTE, Enum.Material.Neon)
	local lampB = piece("LampB", Vector3.new(0.18, 0.18, 0.18), CFrame.new(-1.55, 2.78, 0.05), AMBER, Enum.Material.Neon)

	local glow = Instance.new("PointLight")
	glow.Color = WASTE; glow.Brightness = 2; glow.Range = 14; glow.Parent = screen

	-- the live screen
	local sg = Instance.new("SurfaceGui")
	-- NormalId.Front is a part's -Z face. The monitor sits at z=-0.32 with the keyboard at
	-- z=+0.55, so the player reads it from the +Z side -- that's the BACK face. Using Front
	-- would have drawn the display inwards, into the bezel, invisible from where you stand.
	sg.Name = "ScreenGuiFace"; sg.Face = Enum.NormalId.Back; sg.CanvasSize = Vector2.new(390, 250)
	sg.LightInfluence = 0; sg.AlwaysOnTop = false; sg.Adornee = screen; sg.Parent = screen
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1); bg.BackgroundColor3 = Color3.fromRGB(8, 20, 10); bg.BorderSizePixel = 0
	bg.Parent = sg
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1; title.Position = UDim2.new(0, 12, 0, 10); title.Size = UDim2.new(1, -24, 0, 30)
	title.Font = Enum.Font.RobotoMono; title.Text = "COCOA HAZARD LAB"; title.TextColor3 = WASTE
	title.TextSize = 22; title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = bg
	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1; body.Position = UDim2.new(0, 12, 0, 48); body.Size = UDim2.new(1, -24, 1, -60)
	body.Font = Enum.Font.RobotoMono; body.Text = ""; body.TextColor3 = Color3.fromRGB(150, 210, 150)
	body.TextSize = 17; body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top; body.TextWrapped = true; body.Parent = bg
	screenLabels[#screenLabels + 1] = body

	model.Parent = Workspace

	-- lamps tick over so the thing looks powered
	task.spawn(function()
		local t = 0
		while model.Parent do
			t += 1
			lampA.Material = (t % 2 == 0) and Enum.Material.Neon or Enum.Material.SmoothPlastic
			lampB.Material = (t % 3 == 0) and Enum.Material.Neon or Enum.Material.SmoothPlastic
			task.wait(0.6)
		end
	end)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Enter findings"; prompt.ObjectText = "Data Terminal"
	prompt.HoldDuration = 0; prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false; prompt.Parent = screen
	screen.CanQuery = true
	prompt.Triggered:Connect(function()
		-- no job, no paperwork: send them to the NPC with arrows instead of opening
		-- an empty terminal they can't do anything with
		if not questAccepted then
			if _G.NotifyCenter then
				pcall(function() _G.NotifyCenter.push({
					text = "\xE2\x98\xA2 Talk to the Candy Npc first -- she hands out the job!", color = HAZARD }) end)
			end
			objLabel.Text = "\xE2\x98\xA2 You need the job first! Follow the arrows to the Candy Npc."
			task.delay(3, function() if not questAccepted then refreshBanner() end end)

			-- point the tutorial arrows at her until she's actually been spoken to
			if npcHead and npcHead.Parent then
				task.spawn(function()
					local t0 = os.clock()
					while not questAccepted and os.clock() - t0 < 30 and npcHead and npcHead.Parent do
						if _G.guideTrailTo then pcall(function() _G.guideTrailTo(npcHead.Position) end) end
						task.wait(2)
					end
					-- acceptQuest re-points the arrows at the crane, so only clear them
					-- if the player still hasn't taken the job
					if not questAccepted and _G.guideTrailClear then
						pcall(function() _G.guideTrailClear() end)
					end
				end)
			end
			return
		end

		if operating then setOperating(false) end   -- can't type while driving the crane
		refreshTerminal()
		termGui.Enabled = true
	end)
	return true
end

local function buildFindingsTerminals()
	local made = 0
	local blocks = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and norm(d.Name) == FINDINGS_NAME then
			blocks[#blocks + 1] = d
		end
	end
	for _, b in ipairs(blocks) do
		if buildTerminalAt(b) then made += 1 end
	end
	if made > 0 then print(("[Cleanup] %d findings terminal(s) built (placement blocks hidden)"):format(made))
	else warn("[Cleanup] no block named 'Findings' found -- nowhere to file the readings") end
end

-- ============================================================================
-- THE SECRET SHOVEL -- for the piles the crane physically can't get to. Built here (you
-- don't place anything), handed over by the NPC once the crane has done its share,
-- so a player never has to trek back to the crane a second time.
-- ============================================================================
unreachableLeft = function()
	local n = 0
	for _, p in ipairs(piles) do
		if not p.taken and p.reachable == false then n += 1 end
	end
	return n
end
craneWorkLeft = function()
	local n = 0
	for _, p in ipairs(piles) do
		if not p.taken and p.reachable ~= false then n += 1 end
	end
	return n
end

local function buildShovel(atPos, sourceModel)
	if shovelModel then return end

	local m, shaft
	local toolTemplate            -- a pristine clone the pickup converts into the held Tool

	if sourceModel then
		-- ===== preferred: use the "Shovel" Model the builder placed in Studio, in place =====
		m = sourceModel
		toolTemplate = sourceModel:Clone()        -- snapshot BEFORE we touch the original
		for _, q in ipairs(m:IsA("Model") and m:GetDescendants() or { m }) do
			if q:IsA("BasePart") then
				q.Anchored = true; q.CanCollide = false; q.CanQuery = false
				if q.Transparency >= 1 then q.Transparency = 0 end   -- un-hide (spot parts used to be hidden)
			end
		end
		shaft = (m:IsA("Model") and (m.PrimaryPart or firstBasePart(m))) or (m:IsA("BasePart") and m) or nil
		if m:IsA("Model") and not m.PrimaryPart and shaft then m.PrimaryPart = shaft end
		if shaft and atPos then
			-- plant the copy so the HANDLE sticks up out of the ground (blade half-buried) -- easy to
			-- spot, and it stays put on the baseplate template.
			local piv = m:GetPivot()
			m:PivotTo(CFrame.new(atPos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(12)) * (piv - piv.Position))
		end
		if not shaft then
			warn("[Cleanup] the 'Shovel' model has no parts -- building one from scratch instead")
			if toolTemplate then toolTemplate:Destroy(); toolTemplate = nil end
			sourceModel = nil
		end
	end

	if not sourceModel then
		-- ===== fallback: no model placed -> build a proper spade-shaped shovel =====
		atPos = atPos or (rig and groundUnder(rig.slewCenter - (rig.boomDir or Vector3.new(0, 0, 1)) * 26)) or Vector3.new(0, 0, 0)
		m = Instance.new("Model"); m.Name = "SecretShovel"
		m:SetAttribute("QuestProp", true)

		local WOOD   = Color3.fromRGB(150, 104, 58)
		local STEELC = Color3.fromRGB(204, 208, 216)
		local STEELD = Color3.fromRGB(150, 156, 166)
		local base = CFrame.new(atPos + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(16))
		local function bit(name, size, cf, colour, material)
			local p = mk({ Name = name, Size = size, Color = colour, Material = material or Enum.Material.Metal })
			p.CFrame = base * cf; p.Parent = m
			return p
		end
		-- wooden shaft + a D-shaped top handle (top bar carried on two short uprights)
		shaft = bit("Shaft", Vector3.new(0.3, 4.4, 0.3), CFrame.new(0, 0.2, 0), WOOD, Enum.Material.Wood)
		m.PrimaryPart = shaft
		bit("GripTop", Vector3.new(1.18, 0.3, 0.3),  CFrame.new(0, 2.65, 0),    WOOD, Enum.Material.Wood)
		bit("GripL",   Vector3.new(0.28, 0.8, 0.28), CFrame.new(-0.45, 2.25, 0), WOOD, Enum.Material.Wood)
		bit("GripR",   Vector3.new(0.28, 0.8, 0.28), CFrame.new( 0.45, 2.25, 0), WOOD, Enum.Material.Wood)
		-- steel ferrule + a foot-step across the blade shoulders
		bit("Ferrule", Vector3.new(0.44, 0.7, 0.44), CFrame.new(0, -2.05, 0), STEELD)
		bit("Step",    Vector3.new(1.7, 0.2, 0.36),  CFrame.new(0, -2.4, 0),  STEELD)
		-- a slightly dished spade blade (face + two angled side walls), tilted forward to scoop
		local bladeCF = CFrame.new(0, -3.25, 0.1) * CFrame.Angles(math.rad(-12), 0, 0)
		bit("Blade",      Vector3.new(1.75, 1.9, 0.12), bladeCF, STEELC)
		bit("BladeEdgeL", Vector3.new(0.14, 1.9, 0.42), bladeCF * CFrame.new(-0.8, 0, 0.16) * CFrame.Angles(0, math.rad(18), 0),  STEELC)
		bit("BladeEdgeR", Vector3.new(0.14, 1.9, 0.42), bladeCF * CFrame.new( 0.8, 0, 0.16) * CFrame.Angles(0, math.rad(-18), 0), STEELC)
		-- pointed spade tip (a rotated square: its lower corner is the point)
		bit("BladeTip",   Vector3.new(1.24, 1.24, 0.12), bladeCF * CFrame.new(0, -1.15, 0) * CFrame.Angles(0, 0, math.rad(45)), STEELC)
	end

	if not shaft then return end

	local hl = Instance.new("Highlight")
	hl.FillColor = HAZARD; hl.FillTransparency = 0.7
	hl.OutlineColor = HAZARD; hl.OutlineTransparency = 0.05
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = shaft; hl.Parent = m
	TweenService:Create(hl, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ FillTransparency = 0.95, OutlineTransparency = 0.6 }):Play()

	local bb = Instance.new("BillboardGui")
	bb.Adornee = shaft; bb.Size = UDim2.new(0, 190, 0, 44); bb.StudsOffset = Vector3.new(0, 3.6, 0)
	bb.AlwaysOnTop = true; bb.MaxDistance = 120; bb.Parent = shaft
	local bf = Instance.new("Frame"); bf.Size = UDim2.fromScale(1, 1); bf.BackgroundColor3 = PANEL
	bf.BackgroundTransparency = 0.1; bf.BorderSizePixel = 0; bf.Parent = bb
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = bf
	local bs = Instance.new("UIStroke"); bs.Color = HAZARD; bs.Thickness = 2; bs.Parent = bf
	local bt = Instance.new("TextLabel"); bt.BackgroundTransparency = 1; bt.Size = UDim2.fromScale(1, 1)
	bt.Font = Enum.Font.RobotoMono; bt.Text = "THE SECRET SHOVEL\nyou found it!"; bt.TextColor3 = HAZARD; bt.TextSize = 13
	bt.Parent = bf

	shaft.CanQuery = true
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take the shovel"; prompt.ObjectText = "Secret Shovel"
	prompt.HoldDuration = 0; prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false; prompt.Parent = shaft

	m.Parent = Workspace
	shovelModel = m

	-- a gentle sway (planted in the ground, not floating) to catch the eye until taken
	task.spawn(function()
		local t, home = 0, m:GetPivot()
		while m.Parent and not hasShovel do
			t += 0.05
			m:PivotTo(home * CFrame.Angles(0, 0, math.rad(math.sin(t) * 3)))
			task.wait(0.05)
		end
	end)

	-- Picking it up turns the prop into a REAL Tool -- welded from the placed "Shovel" model when
	-- there is one, else the code-built spade. It lands in the backpack, shows in the hotbar, and is
	-- held in the hands when equipped (auto-equipped so a kid doesn't have to find the hotbar).
	local function giveShovelTool()
		local backpack = player:FindFirstChildOfClass("Backpack")
		if not backpack then return end
		if backpack:FindFirstChild("Secret Shovel") then return end

		local tool = Instance.new("Tool")
		tool.Name = "Secret Shovel"
		tool.ToolTip = "For digging out cocoa the crane can't reach"
		tool.RequiresHandle = true
		tool.CanBeDropped = false

		-- the placed model's parts (if any) get welded into the Tool, longest part = Handle
		local srcParts = {}
		if toolTemplate then
			if toolTemplate:IsA("BasePart") then srcParts[1] = toolTemplate
			else for _, d in ipairs(toolTemplate:GetDescendants()) do if d:IsA("BasePart") then srcParts[#srcParts + 1] = d end end end
		end

		if #srcParts > 0 then
			local handle = srcParts[1]
			for _, p in ipairs(srcParts) do if p.Size.Magnitude > handle.Size.Magnitude then handle = p end end
			handle.Name = "Handle"
			for _, p in ipairs(srcParts) do
				p.Anchored = false; p.CanCollide = false; p.Massless = true
				if p.Transparency >= 1 then p.Transparency = 0 end
				if p ~= handle then
					local w = Instance.new("WeldConstraint"); w.Part0 = handle; w.Part1 = p; w.Parent = p
				end
				p.Parent = tool
			end
			if toolTemplate then toolTemplate:Destroy() end   -- discard the now-empty container
			tool.Grip = CFrame.new(0, -0.6, 0) * CFrame.Angles(math.rad(-65), math.rad(180), 0)   -- flipped 180, held at a natural angle
		else
			-- code-built spade handle (mirrors the from-scratch world prop)
			tool.Grip = CFrame.new(0, -0.6, 0) * CFrame.Angles(math.rad(-90), 0, 0)
			local handle = mk({ Name = "Handle", Size = Vector3.new(0.3, 4.4, 0.3),
				Color = Color3.fromRGB(150, 104, 58), Material = Enum.Material.Wood,
				Anchored = false, CanCollide = false })
			handle.Massless = true; handle.Parent = tool
			local function weldOn(name, size, offset, colour, material)
				local p = mk({ Name = name, Size = size, Color = colour, Material = material or Enum.Material.Metal,
					Anchored = false, CanCollide = false })
				p.Massless = true; p.CFrame = handle.CFrame * offset; p.Parent = tool
				local w = Instance.new("WeldConstraint"); w.Part0 = handle; w.Part1 = p; w.Parent = p
			end
			local STEELC = Color3.fromRGB(204, 208, 216)
			local STEELD = Color3.fromRGB(150, 156, 166)
			weldOn("GripTop",  Vector3.new(1.18, 0.3, 0.3),  CFrame.new(0, 2.45, 0),    Color3.fromRGB(150, 104, 58), Enum.Material.Wood)
			weldOn("Ferrule",  Vector3.new(0.44, 0.7, 0.44), CFrame.new(0, -2.05, 0), STEELD)
			weldOn("Blade",    Vector3.new(1.75, 1.9, 0.12), CFrame.new(0, -3.15, 0.1), STEELC)
			weldOn("BladeTip", Vector3.new(1.24, 1.24, 0.12), CFrame.new(0, -4.05, 0.1) * CFrame.Angles(0, 0, math.rad(45)), STEELC)
		end

		tool.Parent = backpack
		local hum = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
		if hum then pcall(function() hum:EquipTool(tool) end) end
	end

	prompt.Triggered:Connect(function()
		if hasShovel then return end
		hasShovel = true
		prompt.Enabled = false
		m:Destroy()                     -- the world prop is gone; it's yours now
		giveShovelTool()
		refreshBanner()
		if _G.NotifyCenter then
			pcall(function() _G.NotifyCenter.push({
				text = "\xE2\x9B\x8F The Secret Shovel is yours! Dig out the last piles.", color = HAZARD }) end)
		end
		print("[Cleanup] secret shovel taken -- Tool added to backpack")
	end)
end

-- carry a pile by hand, then walk it to the bin
handPickup = function(pile)
	if handPile or pile.taken or not hasShovel then return end
	pile.taken = true
	handPile = pile
	refreshBanner()
	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({ text = "\xE2\x98\xA2 You're carrying the waste -- go put it in the bin!", color = WASTE }) end)
	end
end

-- the carried pile follows you; walking near the bin tips it in
task.spawn(function()
	while true do
		RunService.RenderStepped:Wait()
		if handPile and (not handPile.model or not handPile.model.Parent) then
			-- the carried pile vanished before the bin -> free it up so the run never soft-locks
			handPile.taken = false
			if handPile.handPrompt then handPile.handPrompt.Enabled = true end
			handPile = nil
		end
		if handPile and handPile.model and handPile.model.Parent then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				handPile.model:PivotTo(hrp.CFrame * CFrame.new(0, HAND_CARRY_HEIGHT, -2.2))
				if chamber and chamberCF then
					local flat = (hrp.Position - chamberCF.Position) * Vector3.new(1, 0, 1)
					if flat.Magnitude <= math.max(chamberSize.X, chamberSize.Z) * 0.6 + HAND_DROP_RANGE then
						local m = handPile.model
						handPile = nil
						local tw = TweenService:Create(m.PrimaryPart, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
							{ CFrame = CFrame.new(chamberCF.Position.X, chamberBottom + 1, chamberCF.Position.Z) })
						tw.Completed:Connect(function() m:Destroy(); registerLoad(); refreshBanner() end)
						tw:Play()
					end
				end
			end
		end
	end
end)

-- ============================================================================
-- THE CANDY NPC -- island9's foreman. Same paged-bubble pattern as islands 1/3:
-- she hands out the job, tracks it, and signs it off. Disambiguated as the NPC
-- nearest the crane, so island1's/island3's Candy Npc is never grabbed.
-- ============================================================================
local NPC_MAX_DIST = 500

local function npcHeadOf(inst)
	if not inst then return nil end
	return (inst:IsA("Model") and (inst:FindFirstChild("Head") or inst.PrimaryPart or firstBasePart(inst)))
		or (inst:IsA("BasePart") and inst) or firstBasePart(inst)
end

local function findNPCNear(refPos)
	if not refPos then return nil end
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		local n = norm(d.Name)
		local match = false
		for _, want in ipairs(NPC_NAMES) do if n == want then match = true; break end end
		if match then
			local head = npcHeadOf(d)
			if head then
				local dist = (head.Position - refPos).Magnitude
				if dist <= NPC_MAX_DIST and (not bestD or dist < bestD) then best, bestD = head, dist end
			end
		end
	end
	return best
end

local function hideBubble(adornee)
	local prev = adornee and adornee:FindFirstChild("SpeechBubble")
	if prev then prev:Destroy() end
end

local function showBubble(adornee, text, persist, footer)
	hideBubble(adornee)
	local bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"; bb.Adornee = adornee; bb.Size = UDim2.new(0, 330, 0, 150)
	bb.StudsOffset = Vector3.new(0, 5.5, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local frame = Instance.new("Frame"); frame.Size = UDim2.fromScale(1, 1); frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.05; frame.BorderSizePixel = 0; frame.Parent = bb
	local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0, 14); cr.Parent = frame
	local st = Instance.new("UIStroke"); st.Color = HAZARD; st.Thickness = 2; st.Parent = frame
	local pd = Instance.new("UIPadding")
	pd.PaddingTop = UDim.new(0, 12); pd.PaddingBottom = UDim.new(0, 12)
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = frame
	local lbl = Instance.new("TextLabel")
	lbl.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.RobotoMono; lbl.Text = text
	lbl.TextColor3 = AMBER; lbl.TextScaled = true; lbl.TextWrapped = true; lbl.Parent = frame
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 18; sz.Parent = lbl
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1, 0.2); h.Position = UDim2.fromScale(0, 0.8)
		h.BackgroundTransparency = 1; h.Font = Enum.Font.RobotoMono; h.Text = footer
		h.TextColor3 = STEEL; h.TextScaled = true; h.Parent = frame
		local hs = Instance.new("UITextSizeConstraint"); hs.MaxTextSize = 13; hs.Parent = h
	end
	bb.Parent = adornee
	if not persist then
		task.delay(9, function() if bb and bb.Parent == adornee and bb.Name == "SpeechBubble" then bb:Destroy() end end)
	end
end

local function questPages()
	if findingsFiled then
		return {
			"Paperwork filed, reactor stable. You're a natural.",
			"Go on -- have a cocoa. The safe kind.",
		}
	end
	if finished then
		return {
			"Bin's sealed! Now the boring bit.",
			"Get those readings typed into the Findings terminal.",
		}
	end
	if hasShovel and unreachableLeft() > 0 then
		return {
			"Mind the tongs -- that stuff is still warm.",
			("%d pile(s) left to carry over by hand."):format(unreachableLeft()),
			"Pick one up, walk it to the bin, repeat.",
		}
	end
	if questAccepted and craneWorkLeft() == 0 and unreachableLeft() > 0 then
		return {
			"Oh no -- the crane can't reach those last ones!",
			"There's a SECRET SHOVEL hidden somewhere on this island.",
			"Go find it, dig them out, and walk them to the bin yourself.",
		}
	end
	if questAccepted then
		return {
			"Still glowing out there!",
			("Cleared: %d of %d loads."):format(loadsDone, LOADS_REQUIRED),
			"Board the crane, drop the grab, fill the bin.",
		}
	end
	return {
		"Don't come closer -- the cocoa's gone CRITICAL.",
		"A whole batch of beans went radioactive in the roaster.",
		"Get on the BeanLift crane and shift every pile into the waste bin.",
		"Then type the readings up at the Findings terminal. Go!",
	}
end

local function acceptQuest()
	if questAccepted then return end
	questAccepted = true
	refreshBanner()

	-- point the tutorial arrows at the crane, the same guide trail island1 uses to walk
	-- you to its NPC. Re-asserted on a loop because GardenGuideTrail can override it.
	task.spawn(function()
		local pad = findByName(ENTER_NAME)
		local target = (pad and firstBasePart(pad) and firstBasePart(pad).Position)
			or (rig and rig.slewCenter)
		if not target then return end
		while questAccepted and not operating and not finished do
			if _G.guideTrailTo then pcall(function() _G.guideTrailTo(target) end) end
			task.wait(2)
		end
		if _G.guideTrailClear then pcall(function() _G.guideTrailClear() end) end
	end)
end

local function wireNPC(head)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = "Candy Npc"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false; prompt.Parent = head

	local pages, index = nil, 0
	local watching = false
	local function closeDialogue() hideBubble(head); prompt.ActionText = "Talk"; index = 0; pages = nil end
	local function startWatcher()
		if watching then return end
		watching = true
		task.spawn(function()
			while index ~= 0 do
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if not hrp or (hrp.Position - head.Position).Magnitude > 12 then closeDialogue(); break end
				task.wait(0.25)
			end
			watching = false
		end)
	end

	prompt.Triggered:Connect(function()
		if index == 0 then pages = questPages() end
		index += 1
		if not pages or index > #pages then closeDialogue(); return end
		if index == 2 then acceptQuest() end     -- reading past page 1 = taking the job
		local last = index >= #pages
		local footer = last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages)
		showBubble(head, pages[index], true, footer)
		prompt.ActionText = last and "Close" or "Continue"
		startWatcher()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then closeDialogue() end end)
end

-- ============================================================================
-- OBJECTIVE BANNER
-- ============================================================================
local objGui = Instance.new("ScreenGui")
objGui.Name = "CleanupObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7; objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5, 0); objFrame.Position = UDim2.new(0.5, 0, 0, 12)
objFrame.Size = UDim2.new(0, 540, 0, 52); objFrame.BackgroundColor3 = PANEL; objFrame.Visible = false
objFrame.Parent = objGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = objFrame
	local s = Instance.new("UIStroke"); s.Color = HAZARD; s.Thickness = 3; s.Parent = objFrame
end
local objLabel = Instance.new("TextLabel")
objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1, 1); objLabel.Font = Enum.Font.RobotoMono
objLabel.TextColor3 = AMBER; objLabel.TextScaled = true; objLabel.Parent = objFrame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 19; sz.Parent = objLabel
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14); pad.Parent = objLabel
end

local function bannerText()
	if findingsFiled then return "\xE2\x98\xA2 Findings filed. Reactor cleanup complete." end
	if finished then return "\xE2\x98\xA2 Bin sealed -- now file your findings at the terminal!" end
	if not questAccepted then return "\xE2\x98\xA2 The reactor is unstable -- talk to the Candy Npc on Island 9!" end
	if handPile then return "\xE2\x98\xA2 You're carrying the waste -- put it in the bin!" end
	if hasShovel and unreachableLeft() > 0 then
		return ("\xE2\x98\xA2 Grab the last %d pile(s) by hand!  %d/%d loads"):format(unreachableLeft(), loadsDone, LOADS_REQUIRED)
	end
	if craneWorkLeft() == 0 and unreachableLeft() > 0 then
		return "\xE2\x9B\x8F The crane can't reach the rest -- go find the SECRET SHOVEL!"
	end
	return ("\xE2\x98\xA2 Clear the radioactive cocoa:  %d/%d loads"):format(loadsDone, LOADS_REQUIRED)
end
refreshBanner = function()
	objLabel.Text = bannerText()
	-- a pulsing RED "Find the Secret Shovel!" sign over the crane the moment it can't reach the rest
	-- (found/created by name so it costs no top-level local -- Luau caps functions at 200 registers)
	local show = questAccepted and not hasShovel and craneWorkLeft and craneWorkLeft() == 0 and unreachableLeft and unreachableLeft() > 0
	local anchor = (rig and (rig.boomTip or rig.heel)) or (crane and firstBasePart(crane))
	local existing = anchor and anchor:FindFirstChild("CraneShovelSign")
	if show and anchor and not existing then
		local bb = Instance.new("BillboardGui"); bb.Name = "CraneShovelSign"; bb.Adornee = anchor
		bb.Size = UDim2.fromOffset(300, 64); bb.StudsOffset = Vector3.new(0, 9, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 500; bb.Parent = anchor
		local tl = Instance.new("TextLabel"); tl.BackgroundTransparency = 1; tl.Size = UDim2.fromScale(1, 1)
		tl.Font = Enum.Font.GothamBlack; tl.Text = "\xE2\x9B\x8F Find the Secret Shovel!"; tl.TextColor3 = Color3.fromRGB(255, 58, 48)
		tl.TextStrokeColor3 = Color3.new(0, 0, 0); tl.TextStrokeTransparency = 0; tl.TextScaled = true; tl.Parent = bb
		task.spawn(function()
			local t = 0
			while bb.Parent do t += 0.08; tl.TextTransparency = 0.05 + (math.sin(t * 4) * 0.5 + 0.5) * 0.45; task.wait(0.08) end
		end)
	elseif (not show) and existing then
		existing:Destroy()
	end
end

-- Shop_AllInOne calls this when you touch the LOCKED island-9 stand -- same contract as
-- _G.candyQuestNudge (island 1) and _G.cookieQuestNudge (island 3).
_G.cleanupQuestNudge = function()
	local msg
	if finished then
		msg = "\xE2\x98\xA2 File your findings at the terminal to open the stand!"
	elseif questAccepted then
		msg = ("\xE2\x98\xA2 Clear the radioactive cocoa to open the stand!  %d/%d"):format(loadsDone, LOADS_REQUIRED)
	else
		msg = "\xE2\x98\xA2 Do the reactor cleanup for the Candy Npc to open this stand!"
	end
	objLabel.Text = msg
	objFrame.Visible = true
	task.delay(2.5, refreshBanner)
end

task.spawn(function()
	while true do
		local vis = false
		if rig and rig.slewCenter then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			vis = hrp ~= nil and (hrp.Position - rig.slewCenter).Magnitude <= 320
		end
		objFrame.Visible = vis and not operating
		task.wait(0.4)
	end
end)

-- ============================================================================
-- ENTRY POINT -- an OPERATE prompt on the crane
-- ============================================================================
local function wireOperatePrompt()
	-- prefer the pad you placed in Studio ("enter crane"); fall back to the crane itself
	local pad = findByName(ENTER_NAME)
	local anchor = firstBasePart(pad) or (rig and rig.base[1]) or (rig and rig.upper[1]) or firstBasePart(crane)
	if not anchor then return end
	anchor.CanQuery = true

	-- debounce: after RELEASE you're put back on the pad, and its Touched would
	-- otherwise board you again on the same frame -- you could never get off.
	local lastExit = 0
	local function board()
		if operating then return end
		if os.clock() - lastExit < 2 then return end
		-- the crane is locked until the Candy Npc gives you the job (same as the gumballs
		-- on island1 and the chocolate chunks on island3)
		if not questAccepted then
			objLabel.Text = "\xE2\x98\xA2 Talk to the Candy Npc before touching the crane!"
			task.delay(2.5, function() if not questAccepted then refreshBanner() end end)
			return
		end
		if findingsFiled then return end
		setOperating(true)
	end
	onExitBoard = function() lastExit = os.clock() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Board"; prompt.ObjectText = "BeanLift Crane"
	prompt.HoldDuration = 0; prompt.MaxActivationDistance = OPERATE_RANGE
	prompt.RequiresLineOfSight = false; prompt.Parent = anchor
	prompt.Triggered:Connect(board)

	if pad then
		-- stepping on the pad boards you too, and it glows so it reads as a way in
		anchor.Touched:Connect(function(hit)
			local char = player.Character
			if char and hit:IsDescendantOf(char) then board() end
		end)
		local hl = Instance.new("Highlight")
		hl.FillColor = HAZARD; hl.FillTransparency = 0.75
		hl.OutlineColor = HAZARD; hl.OutlineTransparency = 0.1
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee = anchor; hl.Parent = anchor
		TweenService:Create(hl, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ FillTransparency = 0.95, OutlineTransparency = 0.6 }):Play()
		print(("[Cleanup] boarding pad '%s' wired"):format(pad.Name))
	else
		print("[Cleanup] no 'enter crane' pad found -- Board prompt placed on the crane itself")
	end
end

-- ============================================================================
-- RADIOACTIVE HAZARD EVENT  -- an ambient cycle over the whole factory:
--   NORMAL -> RADIATION CLOUD (drifts across, slows you 35%) -> TOXIC SLUDGE
--   (leaks onto the floor in spots, slows you) -> NORMAL -> repeat.
-- Runs on its own whenever you're on island9, quest accepted or not. Never damages.
-- ============================================================================
local CLOUD_GAP_MIN, CLOUD_GAP_MAX = 25, 40   -- seconds of calm before a cloud
local CLOUD_TIME                   = 12        -- how long the cloud drifts
local CLOUD_SLOW                   = 0.65      -- speed multiplier inside the cloud (35% slower)
local CLOUD_RADIUS                 = 22
local SLUDGE_TIME                  = 18         -- how long the sludge stays after a cloud
local SLUDGE_SLOW                  = 0.62       -- speed in the sludge (~38% slower)
local SLUDGE_POOLS                 = 5          -- how many puddles leak out
local BASE_WALKSPEED               = 16

-- the toxic-sludge PART you placed marks where the thin hazard layer sits. Its footprint
-- is the spill area; we lay a glowing skin over it and (optionally) leak extra pools nearby.
local sludgePart

local hazardSlow = 1        -- current speed multiplier from all hazards combined
local function applySpeed()
	local hum = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	if not hum then return end
	-- never fight the crane (it zeroes WalkSpeed while you operate)
	if operating then return end
	hum.WalkSpeed = BASE_WALKSPEED * hazardSlow
end

-- keep re-asserting, since other systems (and respawns) reset WalkSpeed
task.spawn(function()
	while true do
		task.wait(0.3)
		if not operating then applySpeed() end
	end
end)

-- ---- the drifting radiation cloud ----------------------------------------
local function radiationCloud()
	if not rig then return end
	local centre = rig.slewCenter

	-- drift from one edge of the site to the other
	local a = os.time() % 360    -- deterministic-ish direction (no Math.random needed for spawn)
	local dir = Vector3.new(math.cos(a), 0, math.sin(a))
	local from = centre - dir * 55 + Vector3.new(0, 6, 0)
	local to   = centre + dir * 55 + Vector3.new(0, 6, 0)

	local cloud = mk({ Name = "RadiationCloud", Shape = Enum.PartType.Ball,
		Size = Vector3.new(CLOUD_RADIUS * 2, CLOUD_RADIUS * 1.4, CLOUD_RADIUS * 2),
		Color = WASTE, Material = Enum.Material.ForceField, Transparency = 0.4 })
	cloud.CFrame = CFrame.new(from)
	cloud.Parent = Workspace
	local glow = Instance.new("PointLight")
	glow.Color = WASTE; glow.Brightness = 3; glow.Range = CLOUD_RADIUS * 1.6; glow.Parent = cloud

	-- green motes churning inside it
	local att = Instance.new("Attachment"); att.Parent = cloud
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(WASTE); pe.Size = NumberSequence.new(2.5)
	pe.Transparency = NumberSequence.new(0.4); pe.Lifetime = NumberRange.new(1.5, 2.5)
	pe.Rate = 40; pe.Speed = NumberRange.new(2, 5); pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = att

	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({ text = "\xE2\x98\xA2 RADIATION CLOUD -- get clear!", color = WASTE }) end)
	end

	local t0 = os.clock()
	while os.clock() - t0 < CLOUD_TIME do
		local a2 = (os.clock() - t0) / CLOUD_TIME
		cloud.CFrame = CFrame.new(from:Lerp(to, a2))
		-- Geiger-style flicker
		glow.Brightness = 2.4 + math.sin(os.clock() * 12) * 0.8

		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local inCloud = hrp and (hrp.Position - cloud.Position).Magnitude <= CLOUD_RADIUS
		hazardSlow = inCloud and CLOUD_SLOW or 1
		applySpeed()
		task.wait(0.1)
	end

	hazardSlow = 1; applySpeed()
	TweenService:Create(cloud, TweenInfo.new(1.5), { Transparency = 1 }):Play()
	pe.Enabled = false
	Debris:AddItem(cloud, 1.8)
end

-- ---- the toxic sludge spill ----------------------------------------------
local function makeSludgePool(at, r)
	local pool = mk({ Name = "SludgePool", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, r * 2, r * 2), Color = WASTE, Material = Enum.Material.Neon,
		Transparency = 0.25 })
	pool.CFrame = CFrame.new(at + Vector3.new(0, 0.18, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pool.Parent = Workspace
	local li = Instance.new("PointLight"); li.Color = WASTE; li.Brightness = 1.6; li.Range = r + 6; li.Parent = pool
	-- bubbling
	local att = Instance.new("Attachment"); att.Position = Vector3.new(0, 0, 0); att.Parent = pool
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(WASTE); pe.Size = NumberSequence.new(0.8)
	pe.Transparency = NumberSequence.new(0.3); pe.Lifetime = NumberRange.new(0.8, 1.4)
	pe.Rate = 12; pe.Speed = NumberRange.new(1, 3); pe.Acceleration = Vector3.new(0, 4, 0)
	pe.Parent = att
	-- grow in
	local goal = pool.Size
	pool.Size = Vector3.new(0.35, 0.5, 0.5)
	TweenService:Create(pool, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = goal }):Play()
	return { part = pool, pos = at, r = r }
end

local function toxicSpill()
	if not rig then return end
	local centre = rig.slewCenter
	local pools = {}

	-- hiss from the pipes
	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({ text = "\xF0\x9F\xA7\xAA Pipes burst -- toxic sludge on the floor!", color = WASTE }) end)
	end

	-- (the 'toxic sludge' part is its OWN permanent layer -- the spill just adds extra
	--  temporary puddles around the site)
	for i = 1, SLUDGE_POOLS do
		local a = (i / SLUDGE_POOLS) * math.pi * 2 + (os.time() % 6)
		local dist = 14 + (i % 3) * 9
		local spot = groundUnder(centre + Vector3.new(math.cos(a) * dist, 0, math.sin(a) * dist))
		pools[#pools + 1] = makeSludgePool(spot, 5 + (i % 3))
	end

	local t0 = os.clock()
	while os.clock() - t0 < SLUDGE_TIME do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local inSludge = false
		if hrp then
			for _, p in ipairs(pools) do
				if p.part.Parent then
					local flat = (hrp.Position - p.pos) * Vector3.new(1, 0, 1)
					if flat.Magnitude <= p.r and math.abs(hrp.Position.Y - p.pos.Y) < 6 then
						inSludge = true; break
					end
				end
			end
		end
		hazardSlow = inSludge and SLUDGE_SLOW or 1
		applySpeed()
		task.wait(0.12)
	end

	hazardSlow = 1; applySpeed()
	-- drain back into the pipes
	for _, p in ipairs(pools) do
		if p.part.Parent then
			TweenService:Create(p.part, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = Vector3.new(0.35, 0.5, 0.5), Transparency = 1 }):Play()
			Debris:AddItem(p.part, 1.6)
		end
	end
end

-- is the player standing on the toxic-sludge part? tested in the part's OWN space, so
-- it matches the part's exact footprint and rotation whatever shape it is
local function onSludgePart()
	if not (sludgePart and sludgePart.Parent) then return false end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local local_ = sludgePart.CFrame:PointToObjectSpace(hrp.Position)
	local h = sludgePart.Size * 0.5
	return math.abs(local_.X) <= h.X and math.abs(local_.Z) <= h.Z and math.abs(local_.Y) <= h.Y + 4
end

startHazardCycle = function()
	sludgePart = findByName("toxicsludge")
	if sludgePart then
		-- the visible radiation layer IS a clone of the part -- exact size, shape and
		-- rotation, whether it's a block, cylinder or mesh. Only re-skinned green + thin.
		local wasArch = sludgePart.Archivable
		sludgePart.Archivable = true
		local skin = sludgePart:Clone()
		sludgePart.Archivable = wasArch
		for _, ch in ipairs(skin:GetDescendants()) do ch:Destroy() end   -- drop decals/welds/scripts
		skin.Name = "SludgeSkin"
		skin.Anchored = true; skin.CanCollide = false; skin.CanQuery = false; skin.CastShadow = false
		skin.Color = WASTE; skin.Material = Enum.Material.Neon; skin.Transparency = 0.3
		skin.Reflectance = 0
		pcall(function() if skin:IsA("MeshPart") then skin.TextureID = "" end end)
		-- match the part exactly, lifted a hair so it sits ON the surface (not z-fighting)
		skin.Size = sludgePart.Size + Vector3.new(0.05, 0.05, 0.05)
		skin.CFrame = sludgePart.CFrame
		skin.Parent = Workspace

		local li = Instance.new("PointLight")
		li.Color = WASTE; li.Brightness = 1.2
		li.Range = math.max(sludgePart.Size.X, sludgePart.Size.Z) + 8; li.Parent = skin

		-- the part is a PERMANENT slow zone -- stand on it and you're slowed, whatever
		-- else the hazard cycle is doing
		task.spawn(function()
			while true do
				task.wait(0.15)
				if not operating and onSludgePart() and hazardSlow == 1 then
					hazardSlow = SLUDGE_SLOW; applySpeed()
				elseif hazardSlow == SLUDGE_SLOW and not onSludgePart() then
					-- only lift the slow if the CLOUD/SPILL loop isn't also holding it
					hazardSlow = 1; applySpeed()
				end
			end
		end)

		print(("[Cleanup] toxic sludge layer skinned to '%s' (%s, %.0f x %.0f)"):format(
			sludgePart.Name, sludgePart.ClassName, sludgePart.Size.X, sludgePart.Size.Z))
	else
		warn("[Cleanup] no part named 'toxic sludge' found -- no permanent sludge layer")
	end

	local function onIsland9()
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		return hrp and rig and rig.slewCenter and (hrp.Position - rig.slewCenter).Magnitude <= 420
	end

	task.spawn(function()
		while true do
			task.wait(math.random(CLOUD_GAP_MIN, CLOUD_GAP_MAX))
			if onIsland9() and not finished then
				pcall(radiationCloud)
				task.wait(1.5)
				if onIsland9() then pcall(toxicSpill) end
			end
		end
	end)
	print("[Cleanup] radioactive hazard event armed (cloud -> sludge cycle)")
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	crane = pollFor(function() return findByName(CRANE_NAME) end, 60)
	if not crane then
		warn("[Cleanup] no 'BeanLiftCrane' found in Workspace -- quest inactive")
		return
	end
	-- streaming: the model replicates before its parts do
	pollFor(function() return firstBasePart(crane) end, 45)
	task.wait(1)

	rig = buildRig(crane)
	if not rig then warn("[Cleanup] BeanLiftCrane has no BaseParts -- cannot rig"); return end
	applyRig()

	chamber = pollFor(function() return findByAnyName(CHAMBER_NAMES) end, 20)
	if chamber then
		buildChamberFX()
		updateChamber()
		print(("[Cleanup] containment chamber '%s' wired"):format(chamber.Name))
	else
		warn("[Cleanup] no 'Nuclear Waste' / 'ContainmentChamber' found -- dropping will have nowhere to go")
	end

	-- island9's Candy Npc: the nearest one to the crane, so island1's/island3's is never taken
	npcHead = pollFor(function() return findNPCNear(rig.slewCenter) end, 30)
	if npcHead then
		wireNPC(npcHead)

		-- Arrive on island9 without the job and the arrows point you at her straight away
		-- -- no need to bump into a terminal or the crane first. Stops the moment you take
		-- the job (acceptQuest then re-points them at the crane).
		task.spawn(function()
			while not questAccepted and npcHead and npcHead.Parent do
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hrp and rig and rig.slewCenter
					and (hrp.Position - rig.slewCenter).Magnitude <= 420 then
					if _G.guideTrailTo then pcall(function() _G.guideTrailTo(npcHead.Position) end) end
				end
				task.wait(2)
			end
		end)
		-- The shovel comes from a MODEL named "Shovel" you keep on the baseplate. That original
		-- stays put as an invisible TEMPLATE -- the quest CLONES it and drops the copy where the
		-- player needs it (round the back of the crane), then welds that same copy into their hands
		-- as a Tool on pickup. With no such model, one is built from scratch instead.
		local shovelTemplate = findByName("shovel")
		local spotPos = rig and groundUnder(rig.slewCenter - (rig.boomDir or Vector3.new(0, 0, 1)) * 26) or nil
		if shovelTemplate then
			local copy = shovelTemplate:Clone()          -- clone BEFORE hiding, so the copy is visible
			copy.Parent = Workspace
			for _, q in ipairs(shovelTemplate:IsA("Model") and shovelTemplate:GetDescendants() or { shovelTemplate }) do
				if q:IsA("BasePart") then q.Transparency = 1; q.CanCollide = false; q.CanQuery = false end
			end
			buildShovel(spotPos, copy)
		else
			buildShovel(spotPos, nil)
		end
		print("[Cleanup] island9 Candy Npc wired")
	else
		-- no NPC in the world: don't lock the player out of their own crane
		warn("[Cleanup] no 'Candy Npc' found near the crane -- crane unlocked without her")
		questAccepted = true
	end

	spawnPiles()
	wireSmokeBricks()
	wireOperatePrompt()
	buildFindingsTerminals()
	startHazardCycle()
	refreshBanner()
	refreshHUD()

	print(("[Cleanup] ready -- crane rigged, %d pile(s), chamber %s, NPC %s"):format(
		#piles, chamber and "found" or "MISSING", npcHead and "wired" or "MISSING"))
end)

-- ============================================================================
-- /complete -- test command (only near this crane)
-- ============================================================================
local function onCommand(msg)
	if tostring(msg or ""):lower():sub(1, 9) ~= "/complete" then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (rig and rig.slewCenter and hrp) then return end
	if (hrp.Position - rig.slewCenter).Magnitude > 320 then return end
	questAccepted = true
	for _, p in ipairs(piles) do
		if not p.taken then p.taken = true; if p.model then p.model:Destroy() end end
	end
	loadsDone = LOADS_REQUIRED
	finished = true
	readings = {}
	for i = 1, LOADS_REQUIRED do readings[i] = makeReading(i) end  -- so the terminal has data to file
	updateChamber(); refreshBanner(); refreshHUD()
	sealChamber()
	print("[Cleanup][TEST] /complete -- containment sealed; file the findings at the terminal")
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
