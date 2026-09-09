-- ============================================================================================================
-- COIN MAGNET (client) -- the Coin Magnet gamepass. Drags gas bubbles and coin rings toward you in flight.
-- ============================================================================================================
-- HOW IT WORKS, AND WHY IT TOUCHES NO COLLECTION CODE AT ALL.
--
-- CoreClient already collects a gas bubble within 20 studs and a ring within 16, every frame, whether you are
-- rising or falling (CoreClient ~3314 and ~3369). This script does not widen those radii and does not grant
-- anything -- it simply MOVES the pickup toward the player, and the existing loop then collects it on its own.
--
-- That is the whole design, and it buys three things:
--   * the reward, the respawn timer and the cap are all untouched, so the pass cannot change what a pickup is
--     worth -- only how easily you reach one
--   * it looks like a magnet, because the pickup visibly flies to you
--   * there is exactly ONE collection path in the game, so a magnet bug can never pay out twice
--
-- ---- THE TWO RANGES ARE VERY DIFFERENT ON PURPOSE ----------------------------------------------------------
-- A gas BUBBLE's GAS is bounded hard: 0.6% of the tank whatever your gut (the cap that keeps two bubbles
-- inside a wall crossing's 2% margin), on a 45s respawn. Pulling that from a long way off is free.
--
-- What is NOT bounded is COINS. Both pickups now pay a set amount priced off the player's island -- a coin
-- bubble is 15% of their current meal, a gas bubble half that -- and while flight HEIGHT coins are capped per
-- flight, pickup coins are not capped by anything. A long-range magnet would let a player hoover a whole
-- island's bubbles without flying at them. So the ring range stays short -- you still have to fly roughly at
-- them, the magnet just forgives your aim. (The streak multiplier this paragraph used to be about is gone;
-- the payout no longer compounds, which removes the worst version of that abuse.)
--
-- ⚠ Even at the short range this raises how fast a legitimate player fires CoinEvent. PlayerStats rate-limits
-- and budgets that per window (~PlayerStats 1447-1480); if magnet owners start seeing coin grants silently
-- dropped, that budget is what needs raising -- not this range.
-- ============================================================================================================

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local RS          = game:GetService("ReplicatedStorage")

local Gamepasses = require(RS:WaitForChild("Shared"):WaitForChild("Gamepasses"))

local player = Players.LocalPlayer

local BUBBLE_RANGE = Gamepasses.MAGNET_BUBBLE_RANGE
local RING_RANGE   = Gamepasses.MAGNET_RING_RANGE
local PULL_SPEED   = Gamepasses.MAGNET_PULL_SPEED

-- Parts we currently hold. Kept so a pickup that leaves range gets its drift handed BACK -- without this a
-- bubble the player flew away from would stay frozen mid-air forever, because the drift loop in WorldClient
-- skips any frame where Magnetized is set.
local held = {}

-- `part` may be nil (a pickup table entry can be missing its part), and `held[nil] = nil` is a hard error in
-- Lua -- "table index is nil" -- so the nil check has to come FIRST, not inside the body.
local function release(part)
	if not part then return end
	pcall(function() part:SetAttribute("Magnetized", nil) end)
	held[part] = nil
end

-- Pull one pickup toward `to`. Returns true if it is still in range and being held.
local function pull(part, to, range, dt)
	if not (part and part.Parent) then release(part); return false end

	local delta = to - part.Position
	local dist  = delta.Magnitude

	if dist > range then
		if held[part] then release(part) end -- flew out of range -> give it back to the drift
		return false
	end
	if dist < 0.5 then return true end -- effectively on top of the player; CoreClient's loop has it

	if not held[part] then
		part:SetAttribute("Magnetized", true) -- tell WorldClient's drift loop to stand down
		held[part] = true
	end

	-- Move at a fixed speed, never past the player. Deliberately NOT a lerp toward the player: a lerp is
	-- fastest when it is furthest away, which reads as the pickup being yanked, and it never quite arrives.
	local step = math.min(PULL_SPEED * dt, dist)
	pcall(function() part.CFrame = CFrame.new(part.Position + delta.Unit * step) end)
	return true
end

RunService.RenderStepped:Connect(function(dt)
	-- Not an owner -> this script costs one attribute read per frame and nothing else. The attribute is set by
	-- PlayerStats on join/purchase, so buying the pass starts the magnet mid-flight with no rejoin.
	if not Gamepasses.owns(player, "CoinMagnet") then
		if next(held) then for part in pairs(held) do release(part) end end -- pass lost/refunded: hand everything back
		return
	end

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		if next(held) then for part in pairs(held) do release(part) end end -- died mid-pull: never strand a pickup
		return
	end
	local to = hrp.Position

	-- GAS BUBBLES. _G.activeGasPockets is a flat array of Parts, owned by WorldClient/CoreClient; this only
	-- reads it and never removes from it -- CoreClient's collection loop is the only thing allowed to do that.
	local pockets = _G.activeGasPockets
	if type(pockets) == "table" then
		for i = 1, #pockets do
			pull(pockets[i], to, BUBBLE_RANGE, dt)
		end
	end

	-- RINGS. _G.activeRings holds entries, not parts -- the part is entry.part.
	local rings = _G.activeRings
	if type(rings) == "table" then
		for i = 1, #rings do
			local r = rings[i]
			if type(r) == "table" then pull(r.part, to, RING_RANGE, dt) end
		end
	end

	-- Sweep anything we hold that has since been collected or despawned. Cheap: `held` only ever contains the
	-- handful of pickups actually in range, not every pickup in the world.
	for part in pairs(held) do
		if not part.Parent then held[part] = nil end
	end
end)

print(("[CoinMagnet] ready -- bubbles %d studs, rings %d studs%s"):format(
	BUBBLE_RANGE, RING_RANGE,
	Gamepasses.isConfigured("CoinMagnet") and "" or " -- CoinMagnet id NOT SET, nobody can own it yet"))
