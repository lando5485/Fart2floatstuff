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

-- THE "GardenToast" SCREENGUI IS GONE -- ported from realm 1, which deleted it for these reasons.
-- It was a 420x54 label at y 0.68 in its own ScreenGui, gated by an Enabled flag: a private message
-- box that had already caused one visible bug (it lingered over the bottom HUD as a dark band) and
-- had already been moved once to dodge the gas meter and MeteorUI's reward popup. Every message it
-- carried is a banner now, so there is no box to place, nothing to collide with, and no flag to stick.
--
-- Swept, because deleting the code that builds it does not delete one a stale baked-in copy already
-- built -- and this place has ~27 duplicated scripts.
task.spawn(function()
	local pg = player:WaitForChild("PlayerGui")
	for _ = 1, 5 do
		local old = pg:FindFirstChild("GardenToast")
		if old then
			old:Destroy()
			print("[Garden][client] removed a leftover GardenToast box -- garden replies are banners now")
		end
		task.wait(2)
	end
end)

-- These short REPLIES -- "come back tomorrow", "you can't water here" -- are the same class of message
-- as the wormhole's "land on an island first": a short answer to something the player just tried. They
-- belong in the hero lane with every other answer, same card, same place, same priority order.
--
-- `toast()` keeps its name and signature so every call site below is unchanged; only where the words
-- appear has moved. EVENT priority: a refusal must not shove an island landing off screen, and it
-- queues behind the watering directions rather than covering the instruction it is correcting.
-- NotifyCenter owns the hide, so the token guard and the Enabled flag are both gone.
local function toast(text, colour, seconds)
	local NC = _G.NotifyCenter
	if NC and NC.push then
		pcall(NC.push, {
			text     = text,
			color    = colour or Color3.fromRGB(46, 120, 60), -- the garden's green, not the generic banner green
			priority = (NC.PRIORITY and NC.PRIORITY.EVENT) or 80,
			duration = seconds or 3.5,
		})
		return
	end
	warn("[Garden][client] " .. text .. "  (NotifyCenter unavailable -- not shown on screen)")
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
	elseif payload.kind == "celebrate" then
		-- STAGE 2 harvest celebration: the same banner, in GOLD and held a little longer, because it is
		-- server-wide news rather than a reply to something you did.
		--
		-- This branch used to hand-drive the old toast label's colours and its Enabled flag, and it had
		-- already been bugged once by exactly that: it set only `Visible`, so unless a normal toast had
		-- fired moments earlier the whole celebration never appeared. Going through toast() means there
		-- is one code path, one hide, and no flag to get out of step.
		toast(payload.text or "\xF0\x9F\x8C\xBB The garden bloomed! Everyone gets 2x coins!",
			Color3.fromRGB(210, 160, 40), 5)
	end
end)

-- ask the server for our current cooldown so the prompt shows the right state on join
task.spawn(function() task.wait(1); pcall(function() GardenWaterEvent:FireServer("query") end) end)
