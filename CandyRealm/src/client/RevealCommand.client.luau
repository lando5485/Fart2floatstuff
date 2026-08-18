--======================================================================
-- RevealCommand.client.luau  (StarterPlayerScripts)  -- CandyRealm
--======================================================================
-- /reveal -- play the cinematic payoff shot for the island you are standing on.
--
-- ===== WHAT THIS IS FOR =====
-- CookieRepairQuest ends with a camera move: it pulls off the player, swings onto the giant cookie
-- and holds while the last chocolate chip lands. It works because the thing you just fixed is BIG,
-- STATIC, and OFF TO ONE SIDE -- from where you finish the quest you would never naturally be
-- looking at it. Almost every island in this realm has a moment with that same shape (the ancient
-- tree waking, the giant candy cracking open, the containment chamber going green) and none of
-- them show it to you.
--
-- That shot was written inside CookieRepairQuest as `cinematicFinish`, private to that file. This
-- is the same idea as ONE reusable move any island can call, plus a command to fire it by hand so
-- the framing can be tuned without finishing a quest ten times to see it.
--
--     /reveal              -- reveal this island's payoff object
--     /reveal <name>       -- reveal anything in Workspace by name, for aiming at something new
--     _G.playReveal(inst)  -- the same shot as a call, for a quest to fire on completion
--
-- ===== THE SHOT =====
-- Frame the subject, ORBIT slowly, hold, come back. The orbit is what makes it read as a camera
-- move rather than a screenshot -- and it is slow, because the point is to let the player look at
-- something, not to show off the move. Distance is derived from the subject's own bounding box, so
-- a 4-stud gumball machine and a 319-stud tree both fill roughly the same amount of screen without
-- a hand-tuned number per island.
--
-- ===== IT GIVES THE CAMERA BACK, ALWAYS =====
-- Every exit path restores CameraType. A cinematic that leaves the camera Scriptable is a soft-lock
-- with no message attached -- the player can move and cannot see, which reads as the game breaking.
-- So: the restore is in one place, it runs on death and on respawn as well as on finish, and the
-- loop bails the moment anything else takes the camera off us.
--======================================================================

local Players         = game:GetService("Players")
local Workspace       = game:GetService("Workspace")
local RunService      = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer

local function norm(s) return (tostring(s or ""):lower():gsub("[%s_%-]", "")) end

-- ============================================================================
-- WHICH ISLAND ARE YOU ON
-- ============================================================================
-- Lifted from DoneCommand deliberately, including the weighting: these islands sit above one
-- another and overlap in X/Z by design, so a horizontal footprint test picks the wrong one. Height
-- dominates. (See DoneCommand's note -- that bug once had guide arrows pointing 3,364 studs down.)
local boxes = {}
local function boxOf(m)
	local b = boxes[m]
	if b then return b end
	local ok, cf, size = pcall(function() return m:GetBoundingBox() end)
	if not ok or not cf or size.Magnitude < 1 then return nil end
	b = { c = cf.Position, h = size * 0.5 }
	boxes[m] = b
	return b
end

local function islandUnder(pos)
	local best, bestScore, bestNum
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") then
			local n = tonumber(string.match(norm(m.Name), "^island(%d+)$"))
			if n then
				local b = boxOf(m)
				if b then
					local dx = math.max(0, math.abs(pos.X - b.c.X) - b.h.X)
					local dz = math.max(0, math.abs(pos.Z - b.c.Z) - b.h.Z)
					local dy = math.max(0, math.abs(pos.Y - b.c.Y) - b.h.Y)
					local score = dy * 1e6 + math.sqrt(dx * dx + dz * dz) * 1000 + (b.h.X + b.h.Z)
					if not bestScore or score < bestScore then best, bestScore, bestNum = m, score, n end
				end
			end
		end
	end
	return best, bestNum
end

-- ============================================================================
-- ISLAND -> THE THING WORTH LOOKING AT
-- ============================================================================
-- Names are matched with norm(), so "Giant Cookie" / "giantcookie" / "Giant_Cookie" all hit. Each
-- island lists SEVERAL candidates in priority order: the world does not always contain the first
-- choice (island4 has no `bell` at the time of writing), and falling through to the next best thing
-- beats refusing to play.
--
-- Island numbers are the VERIFIED ones -- summit is island4 and crystal is island8, which is the
-- opposite of what IslandTaskWatcher's comments say. See DoneCommand's note on the same trap.
local TARGETS = {
	[1]  = { "gumballmachine", "candynpc" },
	[3]  = { "giantcookie", "cookiewitholespart" },   -- the one that already has its own cinematic
	[4]  = { "bell", "snow" },
	[5]  = { "guyser", "candynpc" },
	[8]  = { "crystal1", "crystal", "pickaxe" },
	[9]  = { "nuclearwaste", "beanliftcrane" },       -- the containment chamber sealing is the payoff
	-- ISLAND 11 IS THE MINE FRONT, HEAD-ON. The subject is what the blast BUILT -- the timber portal,
	-- the stone pillars and the hanging "THE MINE" sign -- not the painted X you set the charges on.
	-- MineShaft is created by openShaft() at the moment the wall bursts, so before the blast it does
	-- not exist and the list falls through to the blast zone, which is the right subject up to then.
	--
	-- Head-on because an entrance only reads from in front: orbit it and half the shot is hillside.
	[11] = { "mineshaft", "blastzone", "blast", "tnt", front = true },
	[13] = { "ancienttree", "fountain" },             -- the big one: 196 x 319 x 240 studs
	[14] = { "campfire", "mill" },
	[15] = { "oven", "mixer", "chickenzone" },
	-- ISLAND 16 IS THE GIANT CANDY CRACKING OPEN. There is no built entrance on this island to aim
	-- at instead: its only code-made text is the "PLACE HERE" charge tags, and those are 190x46
	-- billboards floating over socket pads -- a mine front is island11, not here.
	[16] = { "giantcandy" },
	[18] = { "syruppump", "butterlauncher", "candynpc" },
	[19] = { "tractor", "factory", "farmhouse" },
}

-- Search the island first and only then the wider Workspace: several of these names are not unique
-- across the realm ("campfire", "oven", "crystal"), and grabbing island 14's campfire while stood
-- on island 4 would fly the camera forty thousand studs.
local function findNamed(root, want)
	local w = norm(want)
	for _, d in ipairs(root:GetDescendants()) do
		if norm(d.Name) == w and (d:IsA("BasePart") or d:IsA("Model")) then
			local ok, _, size = pcall(function() return d:GetBoundingBox() end)
			if d:IsA("BasePart") or (ok and size and size.Magnitude > 0.5) then return d end
		end
	end
	return nil
end

local function targetFor(isle, num)
	local list = TARGETS[num]
	if not list then return nil end
	for _, want in ipairs(list) do
		local hit = isle and findNamed(isle, want)
		if hit then return hit, want, list end
	end
	for _, want in ipairs(list) do            -- island model may not contain it; widen the net
		local hit = findNamed(Workspace, want)
		if hit then return hit, want, list end
	end
	return nil
end

-- ============================================================================
-- THE SHOT
-- ============================================================================
local busy = false

local function subjectFrame(inst)
	if inst:IsA("BasePart") then return inst.Position, inst.Size end
	local ok, cf, size = pcall(function() return inst:GetBoundingBox() end)
	if ok and cf then return cf.Position, size end
	return inst:GetPivot().Position, Vector3.new(10, 10, 10)
end

-- Which way the subject FACES. A Part's own LookVector is the front of it, and for a sign or an
-- entrance mouth that is exactly the direction the player is meant to approach from. Falls back to
-- the model's pivot orientation, then to +Z, so this can never return a zero vector.
local function frontOf(inst)
	-- A RevealFacing attribute WINS, and it is the only reliable answer for anything built in code.
	-- Props assembled with CFrame.new(position) have identity rotation, so their LookVector is +Z no
	-- matter which way the thing they belong to actually points -- deriving a facing from them would
	-- frame whatever happens to be north of the subject. A builder that knows its own orientation
	-- says so; see openShaft() in TunnelBlastQuest.
	local n = inst
	while n and n ~= Workspace do
		local a = n:GetAttribute("RevealFacing")
		if typeof(a) == "Vector3" and a.Magnitude > 0.1 then return a.Unit end
		n = n.Parent
	end
	local part = inst:IsA("BasePart") and inst or (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true))
	local cf = part and part.CFrame or inst:GetPivot()
	local v = cf.LookVector
	if v.Magnitude < 0.1 then return Vector3.new(0, 0, 1) end
	return Vector3.new(v.X, 0, v.Z).Unit    -- flattened: an entrance is approached on the level
end

local function playReveal(inst, seconds, opts)
	if busy or not inst or not inst.Parent then return false end
	busy = true
	seconds = seconds or 4.5
	opts = opts or {}

	local cam = Workspace.CurrentCamera
	if not cam then busy = false; return false end
	local restoreType, restoreCF = cam.CameraType, cam.CFrame

	local centre, size = subjectFrame(inst)
	-- Distance from the subject's own size, so one rule frames a gumball machine and a 319-stud
	-- tree alike. The 1.5x is headroom: framing something to the exact edge of the screen reads as
	-- cramped, and these are all irregular shapes whose bounding box under-sells them.
	local reach = math.max(size.X, size.Y, size.Z)
	local dist  = math.clamp(reach * 1.5 + 14, 22, 420)
	local lift  = math.clamp(reach * 0.45, 6, 140)

	-- HEAD-ON: stand off the front face at roughly the height you would walk in at, and swing only
	-- a few degrees instead of a quarter turn. The low lift is the point -- looking DOWN at a
	-- doorway makes it read as a hole in the floor; looking level at it makes it read as a way in.
	local front, swing = nil, math.rad(28)
	if opts.front then
		front = frontOf(inst)
		lift  = math.clamp(size.Y * 0.35, 4, 24)
		dist  = math.clamp(math.max(size.X, size.Y) * 1.35 + 16, 20, 220)
		swing = math.rad(9)
	end

	-- Start behind the player's shoulder so the move reads as leaving THEM, not as a hard cut to
	-- somewhere else -- the cut is the thing that makes a reveal feel like a loading screen.
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local fromPos = hrp and (hrp.Position + Vector3.new(0, 6, 0)) or (centre + Vector3.new(dist, lift, dist))

	cam.CameraType = Enum.CameraType.Scriptable

	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		-- if anything else claims the camera mid-shot, let go rather than fight it every frame
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			conn:Disconnect(); busy = false
			return
		end
		local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
		-- ease in AND out: the orbit should drift to a stop on the subject, not stop dead
		local e = a < 0.5 and (2 * a * a) or (1 - (-2 * a + 2) ^ 2 / 2)
		local ang = swing * e                             -- a slow swing, not a full lap
		local orbit
		if front then
			-- rotate the FRONT direction by the swing, so the camera drifts across the face of the
			-- entrance while always looking at it from outside
			local dir = CFrame.Angles(0, ang - swing * 0.5, 0):VectorToWorldSpace(front)
			orbit = centre + dir * dist + Vector3.new(0, lift, 0)
		else
			orbit = centre + Vector3.new(math.cos(ang) * dist, lift, math.sin(ang) * dist)
		end
		-- the first fifth is the journey out from the player; the rest is the orbit itself
		local pos = (a < 0.2) and fromPos:Lerp(orbit, a / 0.2) or orbit
		cam.CFrame = CFrame.lookAt(pos, centre)
		if a >= 1 then
			conn:Disconnect()
			cam.CameraType = restoreType
			if restoreType ~= Enum.CameraType.Custom then cam.CFrame = restoreCF end
			busy = false
		end
	end)

	-- BELT AND BRACES. If the loop above is ever killed without reaching a == 1 (the character dies
	-- mid-shot, another script disconnects it, the place shuts a system down) this still hands the
	-- camera back. A stuck Scriptable camera is a soft-lock with no message attached.
	task.delay(seconds + 1.5, function()
		if conn.Connected then conn:Disconnect() end
		if cam.CameraType == Enum.CameraType.Scriptable then cam.CameraType = restoreType end
		busy = false
	end)
	return true
end

-- a quest that finishes can just call this
_G.playReveal = playReveal

-- ...or this, which is the one quests actually use: give it an island number and it resolves that
-- island's payoff object itself. One line per quest, no target knowledge duplicated into thirteen
-- files, and re-aiming an island later is a single edit to TARGETS above.
--
-- Deliberately silent when there is nothing to show. A quest completing is not the place to warn
-- about missing scenery -- /reveal is, and it does.
local function revealIsland(num, seconds)
	local isle
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and norm(m.Name) == ("island" .. tostring(num)) then isle = m; break end
	end
	local target, _, opts = targetFor(isle, num)
	if not target then return false end
	return playReveal(target, seconds, opts)
end
_G.revealIsland = revealIsland

-- ============================================================================
-- THE COMMAND
-- ============================================================================
local function runReveal(arg)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if arg and arg ~= "" then
		local hit = findNamed(Workspace, arg)
		if hit then
			print(("[Reveal] '%s' -> %s"):format(arg, hit:GetFullName()))
			playReveal(hit)
		else
			warn(("[Reveal] nothing in Workspace named '%s'"):format(arg))
		end
		return
	end

	local isle, num = islandUnder(hrp.Position)
	if not num then warn("[Reveal] not standing on a recognised island"); return end
	local target, matched, opts = targetFor(isle, num)
	if not target then
		warn(("[Reveal] island%d has no reveal target yet. Add one to TARGETS, or use /reveal <name>. "
			.. "(tried: %s)"):format(num, table.concat(TARGETS[num] or { "nothing listed" }, ", ")))
		return
	end
	print(("[Reveal] island%d -> '%s' (%s)%s"):format(num, matched, target:GetFullName(),
		(opts and opts.front) and "  [head-on]" or ""))
	playReveal(target, nil, opts)
end

local function onCommand(msg)
	local m = tostring(msg or ""):lower():gsub("^%s+", "")
	if m:sub(1, 7) ~= "/reveal" then return end
	runReveal((m:sub(8):gsub("^%s+", ""):gsub("%s+$", "")))
end

-- Both chat routes: TextChatService is the modern one, player.Chatted the legacy one. Every other
-- command in this realm (/done, /island<N>, /npc, /arrows) wires both, and so does this.
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)

print("[Reveal] ready -- /reveal plays this island's payoff shot, /reveal <name> aims at anything in "
	.. "Workspace, and _G.playReveal(inst) is the same shot for a quest to fire on completion.")
