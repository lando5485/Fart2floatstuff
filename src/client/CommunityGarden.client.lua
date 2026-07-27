--======================================================================
-- CommunityGarden.client.lua  (LocalScript)  -- STAGE 1 community garden CLIENT side.
--======================================================================
-- Puts the "Water the Garden" ProximityPrompt on the WaterSpot, sends the player's WATER INTENT to the
-- server (the server owns + validates the progress and the per-player cooldown), shows the per-player
-- cooldown on the prompt ("Come back tomorrow!"), and plays the local watering SPLASH effect + sound when
-- the server broadcasts a water. Purely cosmetic -- it never touches flight/gameplay.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Debris            = game:GetService("Debris")
local SoundService      = game:GetService("SoundService")

local player = Players.LocalPlayer
local GardenWaterEvent = ReplicatedStorage:WaitForChild("GardenWaterEvent", 60)
if not GardenWaterEvent then return end

-- find the WaterSpot marker by name (inside Island_1_BeanFarm or anywhere in Workspace), after it exists
local function resolveWaterSpot()
	for _ = 1, 120 do
		local island
		for _, m in ipairs(Workspace:GetChildren()) do
			if m:IsA("Model") and string.find(m.Name, "Island_1_BeanFarm", 1, true) then island = m; break end
		end
		local p = (island and island:FindFirstChild("WaterSpot", true)) or Workspace:FindFirstChild("WaterSpot", true)
		if p and p:IsA("BasePart") then return p end
		task.wait(1)
	end
	return nil
end

-- small on-screen toast
-- HIDDEN by default: the ScreenGui starts Enabled=false so NOTHING shows until a real message fires (this was the
-- bug -- it was lingering visible over the bottom HUD as a dark band). Position restored to its normal 0.78 spot.
local toastGui = Instance.new("ScreenGui"); toastGui.Name = "GardenToast"; toastGui.ResetOnSpawn = false; toastGui.DisplayOrder = 40; toastGui.Enabled = false; toastGui.Parent = player:WaitForChild("PlayerGui")
-- y 0.68, not 0.78: at 0.78 (54px tall, centre-anchored) this occupied ~0.755..0.807, which sits ON the
-- bottom HUD (the gas meter / fart button stack starts at ~0.74) AND overlapped MeteorUI's reward popup
-- (~0.79..0.85). 0.68 keeps it clear of both.
local toastLbl = Instance.new("TextLabel"); toastLbl.AnchorPoint = Vector2.new(0.5,0.5); toastLbl.Position = UDim2.new(0.5,0,0.68,0); toastLbl.Size = UDim2.new(0,420,0,54)
toastLbl.BackgroundColor3 = Color3.fromRGB(28,52,28); toastLbl.BackgroundTransparency = 0.15; toastLbl.Font = Enum.Font.FredokaOne; toastLbl.TextSize = 22
toastLbl.TextColor3 = Color3.fromRGB(210,255,200); toastLbl.Text = ""; toastLbl.Visible = true; toastLbl.Parent = toastGui -- label always "visible"; the ScreenGui's Enabled gates whether it actually shows
Instance.new("UICorner", toastLbl).CornerRadius = UDim.new(0,12)
print("[TOASTFIX] GardenToast hidden by default; shows ~3.5s only on real messages")
local toastTok = 0 -- guards the auto-hide so a newer toast can't be hidden by an older timer
local function toast(text)
	toastLbl.Text = text
	toastGui.Enabled = true                                   -- show ONLY when a real message fires
	toastTok = toastTok + 1; local mine = toastTok
	task.delay(3.5, function() if toastTok == mine then toastGui.Enabled = false end end) -- auto-hide after ~3.5s
end

-- the watering splash: a quick burst of blue droplet sparkles over the field + a sound
local function playSplash(pos, soundId)
	local host = Instance.new("Part"); host.Anchored = true; host.CanCollide = false; host.CanQuery = false; host.Transparency = 1
	host.Size = Vector3.new(1,1,1); host.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)); host.Parent = Workspace
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(Color3.fromRGB(120,200,255), Color3.fromRGB(80,150,255))
	em.Lifetime = NumberRange.new(0.6, 1.1); em.Rate = 0; em.Speed = NumberRange.new(6, 14); em.SpreadAngle = Vector2.new(60, 60)
	em.Acceleration = Vector3.new(0, -40, 0); em.Size = NumberSequence.new(0.7); em.LightEmission = 0.6
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.1), NumberSequenceKeypoint.new(1,1) })
	em.Parent = host; em:Emit(60)
	if soundId and soundId ~= "" then
		local s = Instance.new("Sound"); s.SoundId = soundId; s.Volume = 0.6; s.Parent = host -- \xE2\x9A\xA0 REPLACE WITH WATERING SOUND (server-supplied placeholder)
		pcall(function() s:Play() end)
	end
	Debris:AddItem(host, 2)
end

-- ===== build the prompt + wire everything =====
local waterSpot = resolveWaterSpot()
if not waterSpot then warn("[Garden][client] WaterSpot not found -- no water prompt"); return end

local prompt = Instance.new("ProximityPrompt")
prompt.Name = "WaterGardenPrompt"
prompt.ActionText = "Water the Garden"
prompt.ObjectText = "Community Garden"
prompt.HoldDuration = 1.0
prompt.MaxActivationDistance = 12
prompt.RequiresLineOfSight = false
prompt.Parent = waterSpot

local cdToken = 0 -- cancels a stale re-enable timer when a newer cooldown state arrives
local function setReady()
	cdToken = cdToken + 1
	prompt.Enabled = true; prompt.ActionText = "Water the Garden"
end
local function setOnCooldown(secs)
	cdToken = cdToken + 1; local mine = cdToken
	prompt.Enabled = false; prompt.ActionText = "Come back tomorrow!"
	task.delay(secs, function() if cdToken == mine then setReady() end end) -- auto re-enable when the day passes
end

prompt.Triggered:Connect(function(plr)
	if plr == player then pcall(function() GardenWaterEvent:FireServer("water") end) end
end)

GardenWaterEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.kind == "splash" then
		pcall(playSplash, Vector3.new(payload.x or 0, payload.y or 0, payload.z or 0), payload.sound)
	elseif payload.kind == "cooldown" then
		if (payload.secs or 0) > 0 then setOnCooldown(payload.secs) else setReady() end
	elseif payload.kind == "denied" then
		toast("\xF0\x9F\x92\xA7 Come back tomorrow!")
		setOnCooldown(payload.secs or 0)
	elseif payload.kind == "toofar" then
		-- They swung the can somewhere that isn't the water spot. Say so plainly and immediately -- the arrows
		-- are already pointing at the right place, so the toast only has to name the mistake.
		toast("\xE2\x9D\x8C You can't water here! Follow the arrows to the water spot.")
	elseif payload.kind == "celebrate" then
		-- STAGE 2 harvest celebration: a bigger GOLD banner, shown a little longer than a normal toast
		-- toastGui.Enabled is what actually gates rendering (it defaults to FALSE and `toast()` is the
		-- only thing that ever set it true). This branch used to set only toastLbl.Visible, so unless a
		-- normal toast happened to have fired moments earlier, the server-wide harvest celebration
		-- NEVER APPEARED. Enable the ScreenGui, and take a token so the auto-hide can't be stolen.
		local txt = payload.text or "\xF0\x9F\x8C\xBB The garden bloomed! Everyone gets 2x coins!"
		toastLbl.BackgroundColor3 = Color3.fromRGB(210, 160, 40); toastLbl.TextColor3 = Color3.fromRGB(255, 250, 230)
		toastLbl.Text = txt; toastLbl.Visible = true
		toastGui.Enabled = true
		toastTok = toastTok + 1; local mine = toastTok
		task.delay(5, function()
			if toastTok ~= mine then return end -- a newer toast owns the label now
			toastGui.Enabled = false
			toastLbl.BackgroundColor3 = Color3.fromRGB(28, 52, 28); toastLbl.TextColor3 = Color3.fromRGB(210, 255, 200)
		end)
	end
end)

-- ask the server for our current cooldown so the prompt shows the right state on join
task.spawn(function() task.wait(1); pcall(function() GardenWaterEvent:FireServer("query") end) end)

--======================================================================
-- WATERING CAN GUIDANCE -- arrows to the water spot + a "what do I press?" banner.
--======================================================================
-- The can has no hotbar slot (CoreClient hides the Backpack CoreGui), it is auto-equipped, and Tool.Activated
-- is a plain tap -- so without this a player is handed an object with no stated purpose and no stated control.
-- Three things fix that, and all three are driven by ONE attribute the server already sets when it hands the
-- can over (CarryingWateringCan):
--   1. the existing green chevron trail is pointed at the WaterSpot (via _G.guideTrailTo -- we never build a
--      second trail; GardenGuideTrail owns the arrows and its override beats its own tutorial route),
--   2. a banner names the control: "TAP ANYWHERE to pour" once they're in range, "follow the arrows" before,
--   3. the Gardener says the same thing out loud when he hands it over (server side).
-- Everything here is display-only: the server still decides whether a swing actually waters anything.
local RunService = game:GetService("RunService")
local CARRY_ATTR = "CarryingWateringCan"
local POUR_RANGE = 26   -- a shade under the server's WATER_RANGE (28) so the banner never says "tap" a step
                        -- before a tap would actually be accepted

local hintGui = Instance.new("ScreenGui")
hintGui.Name = "WateringCanHint"; hintGui.ResetOnSpawn = false; hintGui.DisplayOrder = 45
hintGui.Enabled = false; hintGui.Parent = player:WaitForChild("PlayerGui")

-- y 0.60: above the garden toast (0.68) and well clear of the bottom HUD, so the hint, a toast and the meters
-- can all be on screen at once without stacking.
local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 0.5); hint.Position = UDim2.new(0.5, 0, 0.60, 0)
hint.Size = UDim2.new(0, 460, 0, 56)
hint.BackgroundColor3 = Color3.fromRGB(26, 79, 214)   -- the house blue, same as the crate/shop panels
hint.BackgroundTransparency = 0.08
hint.Font = Enum.Font.FredokaOne; hint.TextSize = 24; hint.TextColor3 = Color3.fromRGB(255, 255, 255)
hint.Text = ""; hint.Parent = hintGui
Instance.new("UICorner", hint).CornerRadius = UDim.new(0, 14)
do
	local s = Instance.new("UIStroke", hint); s.Color = Color3.fromRGB(255, 255, 255); s.Thickness = 3
	local ts = Instance.new("UIStroke", hint); ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ts.Color = Color3.fromRGB(14, 40, 110); ts.Thickness = 2
end

-- gentle breathing pulse so the banner reads as "act on me", not as static furniture
local hintScale = Instance.new("UIScale", hint)

local wasCarrying = false
RunService.Heartbeat:Connect(function()
	local carrying = player:GetAttribute(CARRY_ATTR) == true
	if not carrying then
		if wasCarrying then
			-- put everything away the moment the can is gone (used, dropped, died) -- guideTrailClear only
			-- drops OUR override, so the trail's own tutorial route is untouched.
			wasCarrying = false
			hintGui.Enabled = false
			if _G.guideTrailClear then _G.guideTrailClear() end
		end
		return
	end
	wasCarrying = true

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and waterSpot and waterSpot.Parent) then return end

	-- Point the shared trail at the spot. Called every frame on purpose: guideTrailTo is cheap and
	-- self-correcting, and it means the arrows follow the spot if the garden ever rebuilds it.
	if _G.guideTrailTo then _G.guideTrailTo(waterSpot.Position) end

	local dist = (hrp.Position - waterSpot.Position).Magnitude
	hintGui.Enabled = true
	if dist <= POUR_RANGE then
		hint.Text = "\xF0\x9F\x92\xA7  TAP ANYWHERE to pour the water!"
		hint.BackgroundColor3 = Color3.fromRGB(46, 150, 70)     -- green = you can do it right now
		hintScale.Scale = 1 + 0.03 * math.sin(os.clock() * 4)
	else
		hint.Text = "\xF0\x9F\x92\xA7  Follow the green arrows to the water spot"
		hint.BackgroundColor3 = Color3.fromRGB(26, 79, 214)
		hintScale.Scale = 1
	end
end)
