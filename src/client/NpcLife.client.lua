--======================================================================
-- NpcLife.client.lua   (LocalScript, per-player)   -- from NpcMovementKit
--======================================================================
-- THE QUEST GIVERS STOP BEING STATUES.
--
-- Every island has a quest NPC and every one of them stands perfectly still facing whichever way
-- it was dropped in Studio. A person who does not move is the most uncanny thing in a game full
-- of things that do -- the wildlife moves, the smoke moves, the blimp moves, and the one human
-- on the island is furniture.
--
-- Four cues, in order of how much they buy you:
--
--   TURN    they face you when you come near. This is nearly all of it. Being LOOKED AT is what
--           makes something read as aware; the rest is decoration on top.
--   BREATHE a slow rise and fall on the spot. Enough that they are never perfectly static, small
--           enough that you would not catch it if you stared.
--   GREET   one bob when you first arrive, then not again until you have been away. A wave every
--           time you walk past is a machine, not a person.
--   IDLE    with nobody near, they hop on the spot every few seconds. Somebody perfectly still
--           the moment you look away is a mannequin that got switched on for you.
--
-- It drives the ROOT of each model, which is how you turn a rig whether it is anchored or not,
-- and it only ever touches yaw -- tipping a character to look at you is how you get a person
-- leaning over backwards when you stand on a rock above them.
--
-- ===== ADOPTION IN THIS REALM =====
-- The kit adopts by name substring ("npc"). Our quest givers are all named "Quest" and are tagged
-- QuestNpc=true by IslandNPCs.server.lua when it wires them, so we adopt on EITHER: the attribute
-- (exact, survives any rename) or a name containing "quest"/"npc" (catches a rig placed in Studio
-- before the server has got to it). The Farmer and Gardener are deliberately NOT matched -- they
-- have their own wave/chat behaviour and two scripts driving one rig is judder.
--
-- DO NOT point this at rigs that play a looping idle Animation -- it anchors the root and fights
-- the Animator. Set the NoNpcLife attribute on those; NpcFacing.client.lua handles them instead.
--======================================================================

local Players         = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Workspace       = game:GetService("Workspace")
local RunService      = game:GetService("RunService")
local player          = Players.LocalPlayer

-- ===== CONFIG =====
local NPC_ATTR   = "QuestNpc"      -- set by IslandNPCs.server.lua on every wired quest giver
local NAME_HINTS = { "quest", "npc" } -- fallback: model name contains one of these (normalised)
local SKIP_TAG   = "NoNpcLife"     -- set this attribute on a model to exempt it (animated rigs)
local NOTICE     = 34              -- studs at which they turn toward you
local GREET_AT   = 16              -- studs at which they bob hello
local FORGET_AT  = 60              -- walk this far and they will greet you again next time
local RESCAN     = 4               -- seconds between sweeps for new NPCs (islands stream in)
local DEBUG_CMD  = "/npc"          -- chat command that prints what it has found

local function norm(s) return (tostring(s):lower():gsub("[%s_%-]", "")) end

local npcs, nextScan = {}, 0

local function rootOf(m)
	return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
		or m:FindFirstChild("Torso") or m:FindFirstChild("UpperTorso")
		or m:FindFirstChildWhichIsA("BasePart")
end

local function isQuestNpc(m)
	if m:GetAttribute(NPC_ATTR) then return true end
	local n = norm(m.Name)
	for _, hint in ipairs(NAME_HINTS) do
		if string.find(n, hint, 1, true) then return true end
	end
	return false
end

local function adopt(m)
	if m:GetAttribute("NpcLife") then return end
	if m:GetAttribute(SKIP_TAG) then return end
	local root = rootOf(m)
	if not root then return end
	m:SetAttribute("NpcLife", true)

	-- ANCHOR IT FIRST. Most of these are unanchored Humanoid rigs, and setting the CFrame of an
	-- unanchored root every frame is a fight you lose: the Humanoid and the physics solver both
	-- write to it after you do, so the pose is overwritten before it is ever drawn. That is why
	-- nothing moves without this. These are static quest givers -- never meant to walk anywhere --
	-- so anchoring the root costs nothing and makes the pose stick.
	--
	-- Client-side only: the server still owns an unanchored NPC, so nobody else sees a thing.
	if not root.Anchored then
		root.Anchored = true
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum then hum.AutoRotate = false end   -- or it turns itself back the moment we turn it
	end

	-- Home is measured on the ROOT, because the root is what we drive.
	--
	-- This used to measure the model PIVOT and apply with PivotTo. PivotTo writes the CFrame of EVERY
	-- part in the model, which meant that every single frame this script stamped the arms back to
	-- their rest pose -- silently erasing the wave GardenerWave was driving through the shoulder
	-- Motor6D. Moving the ROOT instead lets the joints carry the limbs, so a wave survives.
	local base = root.CFrame
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, 1) end
	local home = CFrame.lookAt(base.Position, base.Position + flat.Unit)

	npcs[#npcs + 1] = {
		model = m, root = root, home = home,
		yaw = 0, greeted = false, bob = 0, jump = 0, nextJump = math.random() * 1.5,
		phase = math.random() * 6.28,
		anchored = true,
	}
	print(("[NpcLife] adopted '%s'  root=%s"):format(m:GetFullName(), root.Name))
end

local function sweep()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and isQuestNpc(d) then adopt(d) end
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

			-- 2. BREATHE. A slow rise and fall so they are never perfectly still.
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

			-- 4. MESSING ABOUT. With nobody watching they hop on the spot every few seconds. It
			-- only ever happens out of NOTICE range, so you never catch them at it -- which is the
			-- point, you catch the tail end of it as you walk up.
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

			-- ALWAYS the root, never PivotTo: turning the root turns the whole rig with it through
			-- the joints, and leaves those joints free for anything else posing them (the wave).
			n.root.CFrame = n.home * CFrame.new(0, lift, 0) * CFrame.Angles(0, n.yaw, 0)
		end
	end
end)

-- /npc -- what it has found and what it thinks it is doing. A silent script that loaded fine and
-- moves nothing is impossible to diagnose from the outside.
local function npcDiag(msg)
	if tostring(msg or ""):lower():sub(1, #DEBUG_CMD) ~= DEBUG_CMD then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	print(("[NpcLife] ---- %d adopted ----"):format(#npcs))
	for _, n in ipairs(npcs) do
		local here = n.anchored and n.home.Position or n.root.Position
		print(("  %-42s root=%-18s dist=%s yaw=%.2f")
			:format(n.model:GetFullName(), n.root.Name,
				hrp and ("%d"):format((hrp.Position - here).Magnitude) or "?", n.yaw))
	end
	if #npcs == 0 then
		print(("  none -- nothing with the %s attribute or a matching name has streamed in yet"):format(NPC_ATTR))
	end
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then npcDiag(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(npcDiag) end)

print(("[NpcLife] ready -- quest givers turn, breathe, and say hello once (%s to check)"):format(DEBUG_CMD))
