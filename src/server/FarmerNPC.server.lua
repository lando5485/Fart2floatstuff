-- ===== FARMER TUTORIAL NPC (spawner) =====
-- Places a permanent tutorial-helper Farmer at island 1's bean stand, the SAFE way:
--   * The Farmer rig lives in ServerStorage (NOT Workspace), so the island stand-finder — which only
--     scans Workspace for MODELS named "Island_<n>_..." — can NEVER see it during setup.
--   * Waits for PlayerStats to finish stand setup (Workspace attribute "StandsReady") before doing
--     anything, then clones the Farmer into a dedicated Workspace Folder ("TutorialNPCs") — never
--     inside an island model — so it cannot break island detection.
-- PLACEMENT: hardcoded to the exact CFrame you picked in Studio (FARMER_CFRAME below). The whole rig
--   is pivoted there so his root sits at that spot, facing the recorded orientation.
-- The tutorial text is shown per-player by FarmerTutorial.client.lua (it listens for this prompt).
-- Touches NOTHING about flight, balance, islands, costs, food, earn rate, or test flags.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = workspace

-- Placement RELATIVE to island 1's REAL detected stand (published by PlayerStats as Stand1Pos/Stand1Face),
-- so he always stands on the island surface beside the bean stand, never on the baseplate.
local FARMER_FRONT_OFFSET  = 17  -- studs forward toward the path (11 base + 3 + 3 shifts)
local FARMER_SIDE_OFFSET   = 12  -- studs to the SIDE / right (6 base + 2 + 4 shifts)
local FARMER_YAW           = -47 -- degrees about Y — his facing (Studio orientation (0, -47, 0))
local PROMPT_DISTANCE      = 12  -- how close the player must be for the prompt to appear
local STANDS_READY_TIMEOUT = 30  -- seconds to wait for stand setup before giving up

-- BOTH farmers (Farmer + Farmer2) are shifted by this SAME world-space offset, so they keep their exact
-- arrangement relative to each other. It's applied to each farmer's target position BEFORE the ground
-- raycast, so they stay grounded and keep their facing/prompts. It REPLACES (does not stack on) any prior
-- offset — the position is always ORIGINAL + FARMER_NUDGE.
-- The previous move went the wrong way on screen (-X 4, -Z 2), so BOTH signs were FLIPPED: +X / +Z. The
-- horizontal is now bumped 8 -> 10 studs in that SAME +X direction; depth stays +Z 5.
-- ★ EASY TO ADJUST: if it still moves the wrong way on screen, just flip a sign here. ★
local FARMER_NUDGE = Vector3.new(10, 0, 5)  -- horizontal +X 10 studs, depth +Z 5 studs

task.spawn(function()
	-- 1) Locate the talking Farmer rig by EXACT name ("FarmerNPC"/"Farmer"), falling back to any Model with
	--    a Humanoid EXCEPT "Farmer2" (the scarecrow), so the two rigs can never be mixed up.
	local source = ServerStorage:FindFirstChild("FarmerNPC") or ServerStorage:FindFirstChild("Farmer")
	if not (source and source:FindFirstChildWhichIsA("Humanoid")) then
		source = nil
		for _, c in ipairs(ServerStorage:GetChildren()) do
			if c:IsA("Model") and c.Name ~= "Farmer2" and c:FindFirstChildWhichIsA("Humanoid") then source = c; break end
		end
	end
	if not source then
		warn("FARMER: no rig (a Model with a Humanoid) found in ServerStorage. Put your Farmer in "
			.. "ServerStorage (drag it there in Studio, then Ctrl+S). Skipping the tutorial NPC for now.")
		return
	end

	-- 2) Wait until stands are fully set up (AFTER island detection) so we can never interfere with it.
	local t = 0
	while not Workspace:GetAttribute("StandsReady") and t < STANDS_READY_TIMEOUT do
		task.wait(0.25); t += 0.25
	end
	if not Workspace:GetAttribute("StandsReady") then
		warn("FARMER: 'StandsReady' never set after " .. STANDS_READY_TIMEOUT .. "s; placing anyway.")
	end

	-- 3) Clone into a dedicated Workspace Folder — NEVER inside an island model.
	local container = Workspace:FindFirstChild("TutorialNPCs")
	if not container then
		container = Instance.new("Folder"); container.Name = "TutorialNPCs"; container.Parent = Workspace
	end
	local farmer = source:Clone()
	farmer.Name = "FarmerNPC"
	if not farmer.PrimaryPart then
		farmer.PrimaryPart = farmer:FindFirstChild("HumanoidRootPart") or farmer:FindFirstChildWhichIsA("BasePart")
	end
	farmer.Parent = container

	-- 4) PLACEMENT — (1) move forward toward the path, (2) snap feet to the real ground, (3) face (0,-47,0).
	local standPos = Workspace:GetAttribute("Stand1Pos") or Vector3.new(0, 242, 0)
	local face = Workspace:GetAttribute("Stand1Face") or Vector3.new(0, 0, 1)
	face = Vector3.new(face.X, 0, face.Z)
	if face.Magnitude < 0.05 then face = Vector3.new(0, 0, 1) end
	face = face.Unit
	local right = Vector3.new(face.Z, 0, -face.X)
	-- (1) forward toward the path + to the side, beside the stand. + the shared FARMER_NUDGE (left/back).
	local targetPos = standPos + face * FARMER_FRONT_OFFSET + right * FARMER_SIDE_OFFSET + FARMER_NUDGE
	-- (3) absolute facing: orientation (0, -47, 0) — yaw about Y only, kept upright so his face is visible.
	farmer:PivotTo(CFrame.new(targetPos) * CFrame.Angles(0, math.rad(FARMER_YAW), 0))

	-- (2) raycast straight DOWN to find the real island-1 surface, ignoring the Farmer himself.
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {farmer}
	rp.IgnoreWater = true
	local rayStart = Vector3.new(targetPos.X, standPos.Y + 50, targetPos.Z)
	local hit = Workspace:Raycast(rayStart, Vector3.new(0, -300, 0), rp)
	local groundY = hit and hit.Position.Y or standPos.Y
	if not hit then
		warn("FARMER: no ground detected under him; resting feet at the stand Y instead.")
	end

	-- snap his FEET (bottom of bounding box) exactly onto the detected ground (yaw doesn't change height).
	local bbCF, bbSize = farmer:GetBoundingBox()
	local lift = groundY - (bbCF.Position.Y - bbSize.Y / 2)
	farmer:PivotTo(farmer:GetPivot() + Vector3.new(0, lift, 0))

	local pivot = farmer:GetPivot()
	local footY = farmer:GetBoundingBox().Position.Y - bbSize.Y / 2
	local _, yawRad = pivot:ToOrientation()
	print(string.format("FARMER: placed — rootPos=%s, groundY=%.2f, feetY=%.2f, yaw=%.1f deg",
		tostring(pivot.Position), groundY, footY, math.deg(yawRad)))

	-- 5) Freeze him: anchor every part, no collision, no walking/falling/ragdoll.
	for _, d in ipairs(farmer:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	local hum = farmer:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
		hum.AutoRotate = false
		hum.BreakJointsOnDeath = false
		hum.DisplayName = "Farmer"
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end)
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false) end)
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
	end

	-- 6) "Press E to talk to Farmer" — only shows within PROMPT_DISTANCE.
	local promptParent = farmer:FindFirstChild("Head") or farmer.PrimaryPart
	if promptParent then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "FarmerTutorialPrompt"
		prompt.ActionText = "talk to Farmer"
		prompt.ObjectText = "Farmer"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = PROMPT_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Parent = promptParent
	end

	-- 6b) CONSTANT-SIZE overhead bubble (matches the cow's locked bubble): PIXEL OFFSET size only -> never shrinks
	-- when you walk away and never grows when you walk closer. Purely cosmetic -- the ProximityPrompt + tutorial
	-- dialog talk behavior is untouched.
	if promptParent then
		local bb = Instance.new("BillboardGui")
		bb.Name = "FarmerTalkBubble"; bb.Adornee = promptParent
		bb.Size = UDim2.fromOffset(230, 64)        -- PIXEL OFFSET units only (NO scale component) -> constant screen size at any distance
		bb.SizeOffset = Vector2.new(0, 0)
		bb.StudsOffset = Vector3.new(0, 2.6, 0)    -- local StudsOffset (NOT StudsOffsetWorldSpace) for the height above the head
		bb.LightInfluence = 0                      -- ignore world lighting -> constant look near/far
		bb.AlwaysOnTop = true; bb.MaxDistance = 20; bb.Parent = promptParent; print("[BUBBLE RANGE] farmer MaxDistance=20") -- only visible within 20 studs (Roblox auto-hides the BillboardGui beyond MaxDistance)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(230, 64); frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		frame.BackgroundTransparency = 0.05; frame.BorderSizePixel = 0; frame.Parent = bb
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = frame
		local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(40, 40, 46); stroke.Thickness = 2; stroke.Parent = frame
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1; label.Size = UDim2.fromOffset(214, 54); label.Position = UDim2.new(0, 8, 0, 5)
		label.Font = Enum.Font.GothamBold; label.TextScaled = false; label.TextSize = 18; label.AutomaticSize = Enum.AutomaticSize.None; label.TextColor3 = Color3.fromRGB(34, 34, 40)
		label.TextWrapped = true; label.Text = "\xC2\xA1Hola! Press E to talk"; label.Parent = frame
		print(string.format("[BUBBLE TEXT] farmer TextScaled=false->%s TextSize=%d sizeUsesScale=n", tostring(label.TextScaled), label.TextSize))
		print("[BUBBLE AUDIT] FarmerTalkBubble was=offset now=offset"); print(string.format("[BUBBLE DIAG] FarmerTalkBubble SizeOffset=%s StudsOffsetWorldSpace=%s hasUIScale=%s", tostring(bb.SizeOffset), tostring(bb.StudsOffsetWorldSpace), (bb:FindFirstChildWhichIsA("UIScale", true) or bb:FindFirstChildWhichIsA("UISizeConstraint", true)) and "y" or "n")); print("[BUBBLE SPEAK] farmer method=reuses spawn bubble (static text, never re-spoken)") -- bean-stand Farmer: ONE static BillboardGui
	end

	print("FARMER: tutorial NPC placed (anchored, in Workspace.TutorialNPCs, with talk prompt).")
end)

-- ===== FARMER2 (scarecrow) — PURE DECORATION: no ProximityPrompt, no talking. =====
-- Found by its EXACT name "Farmer2" so it's never confused with the talking "Farmer". Same safety as
-- Farmer: cloned from ServerStorage AFTER StandsReady into the TutorialNPCs folder (never an island),
-- anchored + frozen, scale preserved by Clone. Placed at island 1's REAL stand position with NO offset
-- and NO rotation (yet), feet snapped to the actual ground via a downward raycast.
task.spawn(function()
	-- Find ONLY the rig named exactly "Farmer2".
	local source = ServerStorage:FindFirstChild("Farmer2")
	if not (source and source:IsA("Model") and source:FindFirstChildWhichIsA("Humanoid")) then
		warn("FARMER2: no Model named exactly 'Farmer2' (with a Humanoid) found in ServerStorage. "
			.. "Put your scarecrow rig there named 'Farmer2', then Ctrl+S. Skipping.")
		return
	end

	-- Wait until stands are set up (same gate as Farmer) so we never interfere with island detection.
	local t = 0
	while not Workspace:GetAttribute("StandsReady") and t < STANDS_READY_TIMEOUT do
		task.wait(0.25); t += 0.25
	end

	-- Clone into the dedicated TutorialNPCs folder — NEVER inside an island model.
	local container = Workspace:FindFirstChild("TutorialNPCs")
	if not container then
		container = Instance.new("Folder"); container.Name = "TutorialNPCs"; container.Parent = Workspace
	end
	local farmer2 = source:Clone()
	farmer2.Name = "Farmer2"
	if not farmer2.PrimaryPart then
		farmer2.PrimaryPart = farmer2:FindFirstChild("HumanoidRootPart") or farmer2:FindFirstChildWhichIsA("BasePart")
	end
	farmer2.Parent = container

	-- PLACEMENT — at island 1's stand, pushed BACK 2 studs (away from the player), identity rotation.
	local FARMER2_BACK_OFFSET = 2  -- studs toward the back of the stand area (opposite the player approach)
	local standPos = Workspace:GetAttribute("Stand1Pos") or Vector3.new(3.95, 242.89, 115.87)
	local face = Workspace:GetAttribute("Stand1Face") or Vector3.new(0, 0, 1)
	face = Vector3.new(face.X, 0, face.Z)
	if face.Magnitude < 0.05 then face = Vector3.new(0, 0, 1) end
	face = face.Unit
	local right = Vector3.new(face.Z, 0, -face.X)
	local targetPos = standPos - face * FARMER2_BACK_OFFSET + face * 6 + right * 5 + FARMER_NUDGE  -- back 2, +6 forward, +5 right, + shared FARMER_NUDGE (left/back)
	farmer2:PivotTo(CFrame.new(targetPos))

	-- Find the island GROUND under him, ignoring Farmer2 AND the stand booth — so he lands on the ground,
	-- not on top of the stand. Cast down repeatedly, skipping any part that belongs to a "Stand" model.
	local function partIsStand(inst)
		local n = inst
		while n and n ~= Workspace do
			if string.find(n.Name, "Stand") then return true end
			n = n.Parent
		end
		return false
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {farmer2}
	rp.FilterDescendantsInstances = exclude
	rp.IgnoreWater = true
	local groundY = targetPos.Y
	local rayStart = Vector3.new(targetPos.X, targetPos.Y + 60, targetPos.Z)
	for _ = 1, 10 do
		local hit = Workspace:Raycast(rayStart, Vector3.new(0, -400, 0), rp)
		if not hit then
			warn("FARMER2: no ground detected; resting feet at the stand Y instead.")
			break
		elseif partIsStand(hit.Instance) then
			table.insert(exclude, hit.Instance)  -- it's the booth — skip it and keep looking downward
			rp.FilterDescendantsInstances = exclude
		else
			groundY = hit.Position.Y
			break
		end
	end

	-- Snap his FEET (bottom of bounding box) onto the detected ground.
	local bbCF, bbSize = farmer2:GetBoundingBox()
	local lift = groundY - (bbCF.Position.Y - bbSize.Y / 2)
	farmer2:PivotTo(farmer2:GetPivot() + Vector3.new(0, lift, 0))

	-- Freeze: anchor every part, no collision, no walking/falling/ragdoll. (Clone preserves his scale.)
	for _, d in ipairs(farmer2:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	local hum = farmer2:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
		hum.AutoRotate = false
		hum.BreakJointsOnDeath = false
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end)
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false) end)
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
	end
	-- NO ProximityPrompt, NO dialog — pure decoration.

	local pivot = farmer2:GetPivot()
	local footY = farmer2:GetBoundingBox().Position.Y - bbSize.Y / 2
	print(string.format("FARMER2: placed at stand — rootPos=%s, standPos=%s, groundY=%.2f, feetY=%.2f",
		tostring(pivot.Position), tostring(standPos), groundY, footY))
end)
