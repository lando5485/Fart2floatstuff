--!nonstrict
-- ============================================================================================================
-- BLIMP RIDE (client) -- lets the donation blimp CARRY you while you stand on its deck.
-- ============================================================================================================
-- THE PROBLEM: the blimp is one anchored model driven by PivotTo every frame (BlimpService). An anchored part
-- moved by CFrame passes THROUGH the world -- it never pushes what is resting on it. So a solid blimp you can
-- stand on still slides out from under you the moment you stop walking, and you drop off the back.
--
-- SEATS solve the sitting case on their own: a Seat welds its rider into the anchored assembly, so the ride is
-- exact and needs no code. This file is the STANDING case -- walking around the deck while it flies.
--
-- WHY CLIENT-SIDE: your character is network-owned by YOUR client. If the server moved it every frame you'd
-- fight it and rubber-band. Moving it here, on the machine that owns it, is smooth and is what the physics
-- solver already expects.
--
-- HOW: each frame, take the blimp's movement since the last frame as a CFrame delta, and apply that delta to
-- the player's POSITION only -- never their rotation. Rotating the character with the ship would spin the
-- camera as it laps the island, which is nauseating and makes the deck impossible to walk on. Position-only
-- means the ship's orbit still carries you around the circle correctly, and you keep facing wherever you like.
-- ============================================================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local player = Players.LocalPlayer

-- The deck box, in the ROOF's own space: anywhere above the roof's top face, inside its footprint plus a
-- little margin, up to head height. Measured off the real part rather than hardcoded, because the whole ship
-- is scaled by BLIMP_SCALE after it's built -- hardcoded numbers would be wrong by that factor.
local SIDE_MARGIN = 2    -- studs of slack outside the roof footprint (you're carried right at the rail)
local DECK_HEIGHT = 9    -- studs above the deck that still counts as standing on it

task.spawn(function()
	local blimp, roof
	for _ = 1, 300 do -- the blimp is built ~10s in, after the islands settle; wait it out, don't give up early
		blimp = Workspace:FindFirstChild("DonationBlimp")
		roof  = blimp and blimp:FindFirstChild("GondolaRoof")
		if blimp and roof then break end
		task.wait(1)
	end
	if not (blimp and roof) then
		warn("[BlimpRide] no DonationBlimp/GondolaRoof found -- standing passengers will not be carried")
		return
	end

	local prev = blimp:GetPivot()
	local carrying = false
	print("[BlimpRide] ready -- stand on the blimp deck and it will carry you (sit in a seat for a locked ride)")

	RunService.Heartbeat:Connect(function()
		local now = blimp:GetPivot()
		local delta = now * prev:Inverse()
		prev = now

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (hrp and hum) then carrying = false; return end

		-- Seated riders are welded to the hull already -- moving them here would fight that weld.
		if hum.SeatPart and hum.SeatPart:IsDescendantOf(blimp) then carrying = false; return end

		local lp = roof.CFrame:PointToObjectSpace(hrp.Position)
		local onDeck = math.abs(lp.X) <= roof.Size.X * 0.5 + SIDE_MARGIN
			and math.abs(lp.Z) <= roof.Size.Z * 0.5 + SIDE_MARGIN
			and lp.Y > 0 and lp.Y < DECK_HEIGHT

		if onDeck then
			if not carrying then
				carrying = true
				print("[BlimpRide] aboard -- you're being carried by the blimp")
			end
			-- Position only. `delta * position` moves the point exactly the way the ship moved -- including
			-- the rotational part of its orbit, which is what keeps you over the same plank of deck as it
			-- turns -- while hrp.CFrame's own rotation is left completely alone.
			local moved = delta * hrp.Position
			hrp.CFrame = hrp.CFrame + (moved - hrp.Position)
		elseif carrying then
			carrying = false
			print("[BlimpRide] left the deck")
		end
	end)
end)
