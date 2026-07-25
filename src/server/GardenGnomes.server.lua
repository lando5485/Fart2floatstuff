-- ============================================================================================================
-- LIVING GARDEN GNOMES  (server)  --  ⚠ CURRENTLY SWITCHED OFF (see the ENABLE_ flags below)
--
-- The four garden gnomes are dead statues. This CAN make them one of the best jokes in the game -- but it is off
-- by default and they stand perfectly still, because gnomes that move are a strong flavour and not everyone wants
-- them. The machinery is here and dormant; flip a flag to wake it.
--
-- ===== THE IDEA (when enabled) =====
-- A gnome is SUPPOSED to be a statue. So the funny thing is not to animate them -- it is to have them move only
-- when nobody can see it happen. Three layers, in increasing order of "wait, did that just...":
--
--   1. BREATHE   -- a barely-there bob and sway. Always on. Sub-perceptual on purpose: you never consciously see
--                   it, you just stop reading them as furniture.
--
--   2. WATCH     -- when you get close, the gnome slowly turns to face you. Not a snap; a slow, patient rotation
--                   you catch out of the corner of your eye. If several players are near, it watches the closest.
--
--   3. CREEP     -- and here is the actual gag: when a player is nearby but NOBODY IS LOOKING AT HIM, he shuffles
--                   a few studs closer. Look back and he is standing somewhere he was not. He never, ever moves
--                   while you can see him -- that is the entire point, and it is why this cannot be done with a
--                   simple timer.
--
-- ===== HOW "NOBODY IS LOOKING" IS DECIDED =====
-- The server cannot read anyone's CAMERA. It can read their HumanoidRootPart's LookVector, which is where the
-- character is facing -- and in a third-person Roblox game the character faces roughly where the camera does. So:
-- take the unit vector from the gnome to the player, dot it with that player's LookVector, and if the result is
-- above LOOK_DOT for ANY nearby player, someone is looking in his direction and he freezes.
--
-- It is an approximation, and it errs the right way: a player looking slightly past him still counts as looking,
-- so the failure mode is "he is more shy than he needs to be", never "he moved while you were staring at him" --
-- which is the one failure that would ruin it.
--
-- Everything here is cosmetic. The gnomes are anchored and CFrame-driven; nothing is welded, nothing collides
-- differently, and no gnome can ever push a player.
-- ============================================================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- ============================================================================================================
-- ⚠ THE GNOMES ARE SWITCHED OFF. They stand perfectly still, exactly as they did before this script existed.
--
-- Three independent layers, each off. Turn on whichever you want and leave the rest false -- they do not depend on
-- each other, and CREEP is by far the most intrusive of the three, so it is worth trying the other two first:
--
--   ENABLE_BREATHE -- a sub-perceptual bob and sway. The mildest of the three: they still LOOK like statues, they
--                     just stop reading as furniture. If you want any of this, start here.
--   ENABLE_WATCH   -- they slowly turn to face you when you come close. Still rooted to the spot.
--   ENABLE_CREEP   -- they shuffle toward you when nobody is looking. This is the one that actually relocates them.
--
-- With all three false the loop never starts at all, so this costs nothing while it is off.
-- ============================================================================================================
local ENABLE_BREATHE = false
local ENABLE_WATCH   = false
local ENABLE_CREEP   = false

-- ===== TUNING =====
local NEAR_DIST   = 45      -- studs: a player must be at least this close for a gnome to do anything at all
local WATCH_DIST  = 26      -- studs: within this, he turns to face you
local TURN_SPEED  = 1.4     -- radians/sec he turns at -- slow enough to be unsettling, fast enough to notice

local BOB_AMP     = 0.06    -- studs. Tiny. If you can consciously SEE the bob, it is too big and he reads as a toy
local BOB_SPEED   = 1.1
local SWAY_DEG    = 1.2     -- degrees of lean

local LOOK_DOT    = 0.35    -- how directly a player must face him to count as "looking". Deliberately GENEROUS.
local CREEP_STEP  = 2.2     -- studs he shuffles per move
local CREEP_MIN   = 3.5     -- seconds between shuffles (at the earliest)
local CREEP_MAX   = 9.0
local CREEP_LIMIT = 14      -- studs he may wander from where he was planted, total. Without this he ends up in the
                            -- pond, or slowly migrates across the island over an hour-long server.
local STOP_DIST   = 6       -- he never creeps closer to you than this. A gnome in your face is not funny, it is a
                            -- collision bug.

local rng = Random.new()

local function findGnomes()
	local out = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == "GardenGnome" then out[#out + 1] = d end
	end
	return out
end

if not (ENABLE_BREATHE or ENABLE_WATCH or ENABLE_CREEP) then
	print("[Gnomes] disabled -- the gnomes stand still. Flip ENABLE_BREATHE / ENABLE_WATCH / ENABLE_CREEP to wake them.")
	return
end

task.spawn(function()
	-- the garden builds asynchronously, well after this script starts
	local gnomes = {}
	for _ = 1, 240 do
		gnomes = findGnomes()
		if #gnomes > 0 then break end
		task.wait(0.5)
	end
	if #gnomes == 0 then
		warn("[Gnomes] no GardenGnome models found -- gnomes stay statues")
		return
	end

	-- Capture each gnome's PLANTED pose. Every animation below is an offset from this, and CREEP_LIMIT is measured
	-- from it -- so no amount of drift, over any server lifetime, can take a gnome somewhere silly.
	local state = {}
	for i, g in ipairs(gnomes) do
		local ok, pivot = pcall(function() return g:GetPivot() end)
		if ok then
			state[i] = {
				model  = g,
				home   = pivot,       -- where he was planted (never changes)
				pos    = pivot.Position, -- where he has crept to
				yaw    = 0,           -- his current facing, as an offset from home's yaw
				phase  = rng:NextNumber(0, math.pi * 2), -- so the four never bob in lockstep. That would look mechanical.
				nextCreep = os.clock() + rng:NextNumber(CREEP_MIN, CREEP_MAX),
			}
		end
	end
	print(("[Gnomes] %d gnome(s) -- breathe=%s watch=%s creep=%s")
		:format(#state, tostring(ENABLE_BREATHE), tostring(ENABLE_WATCH), tostring(ENABLE_CREEP)))

	while true do
		RunService.Heartbeat:Wait()
		local now = os.clock()

		for _, s in ipairs(state) do
			if s.model.Parent then
				-- ---- who is near, and is anyone looking? ----
				local closest, closestDist = nil, math.huge
				local watched = false
				for _, p in ipairs(Players:GetPlayers()) do
					local ch = p.Character
					local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
					if hrp then
						local toGnome = s.pos - hrp.Position
						local dist = toGnome.Magnitude
						if dist <= NEAR_DIST then
							if dist < closestDist then closest, closestDist = hrp, dist end
							-- Is this player facing him? (their LookVector vs the direction to him)
							if dist > 0.1 then
								local dot = hrp.CFrame.LookVector:Dot(toGnome.Unit)
								if dot >= LOOK_DOT then watched = true end
							end
						end
					end
				end

				-- ---- 3. CREEP: only when someone is nearby AND nobody is looking ----
				if ENABLE_CREEP and closest and not watched and now >= s.nextCreep then
					s.nextCreep = now + rng:NextNumber(CREEP_MIN, CREEP_MAX)
					local toPlayer = closest.Position - s.pos
					local flat = Vector3.new(toPlayer.X, 0, toPlayer.Z)
					if flat.Magnitude > STOP_DIST then
						local step = flat.Unit * CREEP_STEP
						local want = s.pos + step
						-- stay on the leash: never more than CREEP_LIMIT from where he was planted
						if (want - s.home.Position).Magnitude <= CREEP_LIMIT then
							s.pos = want
						end
					end
				end

				-- ---- 2. WATCH: turn to face the nearest player ----
				local targetYaw = s.yaw
				if ENABLE_WATCH and closest and closestDist <= WATCH_DIST then
					local toPlayer = closest.Position - s.pos
					local flat = Vector3.new(toPlayer.X, 0, toPlayer.Z)
					if flat.Magnitude > 0.5 then
						-- the yaw that points him at the player, expressed as an offset from his planted facing
						local wantWorld = math.atan2(-flat.X, -flat.Z)
						local homeYaw = select(2, s.home:ToOrientation())
						targetYaw = wantWorld - homeYaw
					end
				end
				-- shortest way round, so he never spins the long way to look at you
				local d = (targetYaw - s.yaw + math.pi) % (math.pi * 2) - math.pi
				s.yaw = s.yaw + math.clamp(d, -TURN_SPEED / 60, TURN_SPEED / 60)

				-- ---- 1. BREATHE: always ----
				local bob, sway = 0, 0
				if ENABLE_BREATHE then
					local t = now * BOB_SPEED + s.phase
					bob  = math.sin(t) * BOB_AMP
					sway = math.rad(SWAY_DEG) * math.sin(t * 0.7)
				end

				-- Rebuild from HOME's rotation each frame (never from the last frame's CFrame) -- accumulating
				-- rotations frame-on-frame is how a gentle sway turns into a gnome lying on his back after an hour.
				local base = CFrame.new(s.pos.X, s.pos.Y + bob, s.pos.Z) * (s.home - s.home.Position)
				pcall(function()
					s.model:PivotTo(base * CFrame.Angles(0, s.yaw, 0) * CFrame.Angles(sway, 0, 0))
				end)
			end
		end
	end
end)
