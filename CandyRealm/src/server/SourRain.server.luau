--======================================================================
-- SourRain.server.luau  --  SOUR ACID RAIN: the realm-wide disaster
--======================================================================
-- Replaces the BIRD NUKE, which was a Food-realm leftover: its remote (BirdNukeEvent) was never
-- created by any Candy server script, so the 79 R$ product charged players for an event that
-- could not fire. This is what that product buys now.
--
-- WHAT IT IS. Green sour rain falls over the WHOLE TOWER -- all 14 islands at once, not one --
-- for 18 seconds. Anyone caught in the open melts: health drains steadily and kills in about six
-- seconds. Step under any roof, into a cave, inside the hay bale factory, and it stops at once.
-- The buyer is immune and watches it happen.
--
-- ===== WHY THE DAMAGE LIVES HERE AND NOT ON THE CLIENT =====
-- A LocalScript can only kill its own player, and only visually -- the server would put them
-- straight back. One player's client saying "everyone dies now" is also the first thing an
-- exploiter would send. So the server owns all of it: who is exposed, how fast they melt, and
-- when it stops. Clients are told only what to DRAW.
--
-- ===== THE ONE THING THAT MAKES OR BREAKS THE SHELTER TEST =====
-- (!) THE ROOF RAY IS DELIBERATELY SHORT. These islands are stacked in a tower, so a player on
-- island 3 has island 4 directly overhead -- a long "is anything above me?" ray marks all but the
-- top island as indoors, and the disaster does nothing to anybody. Thirty studs is longer than
-- any real roof is high and thousands of studs shorter than the gap between islands.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local PRODUCT_ID  = 3600303082    -- the old "Bird Nuke" dev product, 79 R$, now SOUR RAIN
local DURATION    = 18            -- seconds of rain
local DPS         = 17            -- health per second while exposed (~6s from full)
local SHELTER_UP  = 30            -- how far up we look for a roof. See the note above.
local TICK        = 0.25

local ev = ReplicatedStorage:FindFirstChild("SourRainEvent")
if not ev then
	ev = Instance.new("RemoteEvent")
	ev.Name = "SourRainEvent"
	ev.Parent = ReplicatedStorage
end

local active = false

-- everything a ray must ignore: every character (your own hat is not a roof) and anything a
-- quest has dropped on your back
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshFilter()
	local ex = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then ex[#ex + 1] = p.Character end
	end
	rayParams.FilterDescendantsInstances = ex
end

local function isSheltered(char)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return true end                     -- no body to melt
	local hit = Workspace:Raycast(hrp.Position + Vector3.new(0, 2, 0),
		Vector3.new(0, SHELTER_UP, 0), rayParams)
	return hit ~= nil
end

local function start(buyer)
	if active then
		-- a second purchase during a storm extends nothing and fires nothing: it would double the
		-- damage tick on everyone still outside, which is a way to buy a guaranteed server wipe
		if buyer then ev:FireClient(buyer, "already") end
		return false
	end
	active = true

	local buyerName = buyer and buyer.Name or "Someone"
	ev:FireAllClients("start", buyerName, DURATION)
	if buyer then ev:FireClient(buyer, "buyer") end
	print(("[SourRain] STARTED by %s -- %ds of rain over every island"):format(buyerName, DURATION))

	task.spawn(function()
		local sheltered = {}        -- [player] = last state we told them about
		local killed = 0
		local t0 = os.clock()
		while os.clock() - t0 < DURATION do
			refreshFilter()
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = plr.Character
				local hum = char and char:FindFirstChildWhichIsA("Humanoid")
				if hum and hum.Health > 0 then
					local safe = (plr == buyer) or isSheltered(char)
					if sheltered[plr] ~= safe then
						sheltered[plr] = safe
						ev:FireClient(plr, "shelter", safe)   -- told only when it CHANGES
					end
					if not safe then
						hum:TakeDamage(DPS * TICK)
						if hum.Health <= 0 then
							killed += 1
							print(("[SourRain] %s melted (caught in the open)"):format(plr.Name))
						end
					end
				end
			end
			task.wait(TICK)
		end

		active = false
		ev:FireAllClients("stop", killed)
		print(("[SourRain] over -- %d player(s) melted"):format(killed))
	end)
	return true
end

-- ===== THE PURCHASE =====
-- Receipts.server.luau owns the realm's single ProcessReceipt and calls every registered handler
-- until one claims the id. Returning false for anything else is what keeps the coin packs working.
_G.sourRainHandleReceipt = function(player, productId)
	if productId ~= PRODUCT_ID then return false end
	start(player)
	return true                    -- claimed: granted whether or not a storm was already running
end

-- ...and a plain call, so a future button, a badge or an admin panel can set it off without
-- pretending to be a receipt.
_G.startSourRain = start

-- ===== TESTING =====
-- 79 Robux is a steep way to check a screen effect. Any player may fire it from chat; if that is
-- not what you want live, delete this block -- the product path above does not depend on it.
Players.PlayerAdded:Connect(function(plr)
	plr.Chatted:Connect(function(msg)
		if string.lower(msg):sub(1, 9) == "/sourrain" then
			print(("[SourRain][TEST] fired from chat by %s"):format(plr.Name))
			start(plr)
		end
	end)
end)

print(("[SourRain] ready -- product %d is now SOUR ACID RAIN (%ds, %d dps outdoors, buyer immune)")
	:format(PRODUCT_ID, DURATION, DPS))
