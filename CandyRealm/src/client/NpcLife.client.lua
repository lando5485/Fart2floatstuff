--======================================================================
-- NpcLife.client.lua   (LocalScript, per-player)
--======================================================================
-- THE QUEST GIVERS STOP BEING STATUES.
--
-- Every island has a Candy Npc and every one of them stands perfectly still facing whichever
-- way it was dropped in Studio. A person who does not move is the most uncanny thing in a game
-- full of things that do -- the butterflies move, the smoke moves, the water moves, and the
-- one human on the island is furniture.
--
-- Three cues, in order of how much they buy you:
--
--   TURN    they face you when you come near. This is nearly all of it. Being LOOKED AT is
--           what makes something read as aware; the rest is decoration on top.
--   BREATHE a slow rise and fall on the spot. Enough that they are never perfectly static,
--           small enough that you would not catch it if you stared.
--   GREET   one bob when you first arrive, then not again until you have been away.
--   WAVE    the LEFT hand goes up while you are stood in front of them, and eases back down
--           when you leave. Paired with the turn it is what sells "they have noticed ME"
--           rather than "they are pointed at me": a head that follows you is a security
--           camera, a raised hand is a person. The maths lives in Shared.NpcWave so the
--           gardener (GardenerLife) waves at exactly the same angle and speed.
--
-- It drives the ROOT of each model, which is how you turn a rig whether it is anchored or not,
-- and it only ever touches yaw -- tipping a character to look at you is how you get a person
-- leaning over backwards when you stand on a rock above them.
--======================================================================

local Players    = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player     = Players.LocalPlayer

local NpcWave = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcWave"))

local NPC_HINT   = "npc"     -- any model whose name contains it, e.g. "Candy Npc"
local NOTICE     = 34        -- studs at which they turn toward you
local WAVE_AT    = 30        -- studs at which the left hand comes up (just inside NOTICE, so
                             -- they are already facing you before the arm moves -- an NPC that
                             -- waves at your back is waving at nobody)
local GREET_AT   = 16        -- studs at which they bob hello
local FORGET_AT  = 60        -- walk this far and they will greet you again next time
local RESCAN     = 4         -- seconds between sweeps for new NPCs

local function norm(s) return (tostring(s):lower():gsub("[%s_%-]", "")) end

local npcs, nextScan = {}, 0

local function rootOf(m)
	return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
		or m:FindFirstChild("Torso") or m:FindFirstChild("UpperTorso")
		or m:FindFirstChildWhichIsA("BasePart")
end

-- THE ONE NPC THAT IS NOT A RIG. The Baker is built out of welded blocks by
-- BakeryQuest_AllInOne, so he has no Humanoid and no shoulder joint to pose -- and a wave
-- that only works on Studio rigs would leave exactly one island with a statue on it.
--
-- His left arm is found by WHERE IT IS rather than by name, since the builder never named
-- the parts: in the model's own frame the NPC's left is -X, so anything far enough out to
-- that side and above the legs is arm. The cut-off is a fraction of the figure's own
-- half-width, not a stud count, so it holds whatever scale the block figure was built at
-- (0.55 keeps the arm and the hand, and drops the legs, eyes, buttons and hat, which all
-- sit nearer the centre line).
--
-- Returns the parts with their rest CFrames RELATIVE TO THE MODEL PIVOT, plus the shoulder
-- to swing them about (top of the highest arm part) -- both in that same local frame, so
-- the pose survives the model being pivoted around by the loop below.
local function blockArm(m, base)
	if m:FindFirstChildOfClass("Humanoid") then return nil end   -- rigs use their joints
	local inv = base:Inverse()
	local all, lowY, highY, wide = {}, math.huge, -math.huge, 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local rest = inv * d.CFrame
			all[#all + 1] = { part = d, rest = rest }
			lowY, highY = math.min(lowY, rest.Y), math.max(highY, rest.Y)
			wide = math.max(wide, math.abs(rest.X))
		end
	end
	if #all == 0 or highY <= lowY or wide <= 0 then return nil end

	local sideCut = -0.55 * wide
	local waist   = lowY + (highY - lowY) * 0.30
	local arm, sumX, sumZ, top = {}, 0, 0, -math.huge
	for _, e in ipairs(all) do
		if e.rest.X <= sideCut and e.rest.Y >= waist then
			arm[#arm + 1] = e
			sumX, sumZ = sumX + e.rest.X, sumZ + e.rest.Z
			top = math.max(top, e.rest.Y + e.part.Size.Y * 0.5)
		end
	end
	if #arm == 0 then return nil end
	return { parts = arm, pivot = Vector3.new(sumX / #arm, top, sumZ / #arm) }
end

local function adopt(m)
	if m:GetAttribute("NpcLife") then return end
	local root = rootOf(m)
	if not root then return end
	m:SetAttribute("NpcLife", true)

	-- ANCHOR IT FIRST. Every one of these is an unanchored Humanoid rig, and setting the CFrame
	-- of an unanchored root every frame is a fight you lose: the Humanoid and the physics solver
	-- both write to it after you do, so the pose is overwritten before it is ever drawn. That is
	-- why nothing moved. These are static quest givers -- they are never meant to walk anywhere
	-- -- so anchoring the root costs nothing and makes the pose stick.
	--
	-- It also means everyone gets the idle bounce. That was skipped on unanchored rigs precisely
	-- because nudging one up and down fights the same solver; with the root anchored there is
	-- nothing left to fight.
	--
	-- Client-side only: the server still owns an unanchored NPC, so nobody else sees a thing.
	if not root.Anchored then
		root.Anchored = true
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum then hum.AutoRotate = false end   -- or it turns itself back the moment we turn it
	end

	-- home is measured the same way it is applied: by the model pivot, since PivotTo moves the
	-- whole rig and a model's pivot is not its root part
	local anchored = true
	local base = m:GetPivot()
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, 1) end
	local home = CFrame.lookAt(base.Position, base.Position + flat.Unit)

	-- the waving arm: a rig's left shoulder joint if it has one, the block figure's left arm
	-- parts otherwise. Rigs stream their limbs in AFTER the model, so a nil joint here is
	-- retried by the loop rather than being taken as "this one cannot wave".
	local shoulder = NpcWave.leftShoulder(m)

	npcs[#npcs + 1] = {
		model = m, root = root, home = home,
		yaw = 0, greeted = false, bob = 0, jump = 0, nextJump = math.random() * 1.5,
		phase = math.random() * 6.28,
		anchored = anchored,
		arm = shoulder, armC0 = shoulder and shoulder.C0 or nil,
		-- measured against `base`, the pivot the parts are actually laid out around: PivotTo
		-- carries every part by cf * base^-1, so a rest offset taken from any other frame
		-- (`home` is yaw-flattened) would fly the arm off the shoulder on a tilted NPC
		block = (not shoulder) and blockArm(m, base) or nil,
		wave = 0, armRetry = 0,
	}
	print(("[NpcLife] adopted '%s'  root=%s  anchored=%s  arm=%s")
		:format(m:GetFullName(), root.Name, tostring(anchored),
			shoulder and "shoulder joint" or (npcs[#npcs].block and "block arm" or "none yet")))
end

local function sweep()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and string.find(norm(d.Name), NPC_HINT, 1, true) then
			adopt(d)
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt or 0.016, 0.05)
	local now = os.clock()
	if now >= nextScan then
		nextScan = now + RESCAN
		sweep()                       -- islands stream in, so keep looking rather than look once
	end

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	for i = #npcs, 1, -1 do
		local n = npcs[i]
		if not (n.model.Parent and n.root.Parent) then
			table.remove(npcs, i)
		else
			local here = n.anchored and n.home.Position or n.root.Position
			local d = (hrp.Position - here).Magnitude

			-- 1. TURN. Only if you are close enough to be worth noticing, and eased rather than
			-- snapped -- a head that whips round reads as a turret.
			local want = 0
			if d <= NOTICE then
				local to = hrp.Position - here
				local flat = Vector3.new(to.X, 0, to.Z)
				if flat.Magnitude > 0.5 then
					local target = CFrame.lookAt(here, here + flat.Unit)
					-- the yaw difference between home and facing you, as a signed angle
					local rel = n.home:ToObjectSpace(target)
					want = math.atan2(-rel.LookVector.X, -rel.LookVector.Z)
				end
			end
			n.yaw += (want - n.yaw) * math.min(1, dt * 6.5)

			-- 2. BREATHE. Everyone gets this now the roots are anchored -- a slow rise and fall
			-- so they are never perfectly still.
			local lift = 0
			if n.anchored then
				lift = math.sin(now * 1.7 + n.phase) * 0.11
			end

			-- 3. GREET. One bob, then never again until you have left and come back.
			if not n.greeted and d <= GREET_AT then
				n.greeted = true
				n.bob = 1
			elseif n.greeted and d > FORGET_AT then
				n.greeted = false
			end
			if n.bob > 0 then
				n.bob = math.max(0, n.bob - dt * 2.4)
				lift += math.sin((1 - n.bob) * math.pi) * 0.55
			end

			-- 4. MESSING ABOUT. With nobody watching they hop on the spot every few seconds.
			-- Somebody who is perfectly still the moment you look away is a mannequin that got
			-- switched on for you; someone doing their own thing until you arrive was always
			-- there. It only ever happens out of NOTICE range, so you never catch them at it --
			-- which is the point, you catch the tail end of it as you walk up.
			if d > NOTICE then
				n.nextJump -= dt
				if n.nextJump <= 0 and n.jump <= 0 then
					n.jump = 1
					n.nextJump = 0.7 + math.random() * 1.2
				end
			end
			if n.jump > 0 then
				n.jump = math.max(0, n.jump - dt * 2.2)
				-- a real hop: up fast, down faster, not a sine wobble
				local u = 1 - n.jump
				lift += math.sin(u * math.pi) ^ 0.7 * 1.5
			end

			local cf = n.home * CFrame.new(0, lift, 0) * CFrame.Angles(0, n.yaw, 0)
			if n.anchored then
				n.model:PivotTo(cf)
			else
				n.root.CFrame = cf          -- turning the root turns the whole rig with it
			end

			-- 5. WAVE. The left hand comes up while you are in front of them and eases back
			-- down when you go. AFTER the pivot, because posing block arms is done in the
			-- model's frame and PivotTo would otherwise put them straight back at rest.
			n.wave = NpcWave.ease(n.wave, (d <= WAVE_AT) and 1 or 0, dt)

			-- a rig whose limbs had not replicated when it was adopted gets another look --
			-- twice a second, and only while there is still no joint to pose
			if not n.arm and not n.block and now >= n.armRetry then
				n.armRetry = now + 0.5
				n.arm = NpcWave.leftShoulder(n.model)
				if n.arm then n.armC0 = n.arm.C0 end
			end

			local angle = NpcWave.angle(n.wave, now, n.phase)
			if n.arm then
				if n.arm.Parent then
					NpcWave.poseShoulder(n.arm, n.armC0, angle)
				else
					n.arm, n.armC0 = nil, nil   -- limb streamed out; look again next retry
				end
			elseif n.block and n.wave > 0.001 then
				-- swing the arm parts about the shoulder POINT, in the model's own frame, then
				-- carry them back out to where the model is standing this frame
				local swing = CFrame.new(n.block.pivot) * CFrame.Angles(0, 0, angle)
					* CFrame.new(-n.block.pivot)
				for _, e in ipairs(n.block.parts) do
					if e.part.Parent then e.part.CFrame = cf * swing * e.rest end
				end
			end
		end
	end
end)

-- /npc -- what it has found and what it thinks it is doing. A silent script that loaded fine
-- and moves nothing is impossible to diagnose from the outside.
local function npcDiag(msg)
	if tostring(msg or ""):lower():sub(1, 4) ~= "/npc" then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	print(("[NpcLife] ---- %d adopted ----"):format(#npcs))
	for _, n in ipairs(npcs) do
		local here = n.anchored and n.home.Position or n.root.Position
		print(("  %-42s root=%-18s anchored=%-5s dist=%s yaw=%.2f arm=%-9s wave=%.2f")
			:format(n.model:GetFullName(), n.root.Name, tostring(n.anchored),
				hrp and ("%d"):format((hrp.Position - here).Magnitude) or "?", n.yaw,
				n.arm and "shoulder" or (n.block and "block" or "none"), n.wave))
	end
	if #npcs == 0 then
		print("  none -- no Model with 'npc' in its name has streamed in yet")
	end
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then npcDiag(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(npcDiag) end)

print("[NpcLife] ready -- quest givers turn to face you, breathe, wave their left hand, and say hello once (/npc to check)")
