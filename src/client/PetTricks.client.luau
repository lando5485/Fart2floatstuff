-- ==============================================================================================================
-- PET TRICKS -- the button that makes a pet something you USE, not something that trails behind you.
--
-- One press, one big effect, then a cooldown. Which trick you get is decided entirely by the SERVER: it writes
-- the lead equipped pet's trick id to the `PetTrick` player attribute (see PetAbilityService), and this file
-- looks that string up in its own table. Nothing here decides what you own, and nothing here grants progression.
--
-- ===== WHY THE EFFECTS ARE PURELY LOCAL =====
-- Every trick below builds parts on the CLIENT and never asks the server for anything, with one exception
-- (Petal Burst's coin tip, which goes through CoinEvent and is bounded by that remote's existing validation and
-- 8,000 cap like every other pickup). That keeps tricks free: no replication cost, no remote to abuse, and a
-- trick can never leak progression because it has no route to.
--
-- ===== AND WHY NONE OF THEM TOUCHES FLIGHT =====
-- Same rule as PetAbilities: nothing here changes speed, climb, drain, coast or gas-bubble power. Rift MOVES
-- bubbles to you but does not change what one is worth; Belly Slide is ground movement only. The tower's gates
-- are asserted against ~1.9% of a climb and a trick must never eat into that.
-- ==============================================================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Debris            = game:GetService("Debris")

local player = Players.LocalPlayer
local COOLDOWN = 45

local CoinEvent = ReplicatedStorage:FindFirstChild("CoinEvent")

-- ===== SMALL BUILDERS =====
-- Every trick draws from these three, so the whole file has one visual language: unanchored-looking but
-- anchored parts, no collision, no query, always on a Debris timer so a trick can never leak geometry.
local function fxPart(size, color, cf, material, shape, transparency)
	local p = Instance.new("Part")
	p.Size = size; p.Color = color; p.CFrame = cf
	p.Material = material or Enum.Material.Neon
	p.Shape = shape or Enum.PartType.Block
	p.Transparency = transparency or 0
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false
	p.Parent = workspace
	return p
end

local function fade(part, secs, growTo)
	local goal = { Transparency = 1 }
	if growTo then goal.Size = growTo end
	TweenService:Create(part, TweenInfo.new(secs, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(part, secs + 0.2)
end

local function burst(parent, color, rate, life, speed)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.8
	e.Lifetime = NumberRange.new(life or 0.8)
	e.Speed = NumberRange.new(speed or 12)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	e.Parent = parent
	e:Emit(rate or 40)
	Debris:AddItem(e, (life or 0.8) + 0.5)
	return e
end

local function rootOf()
	local ch = player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function petRoot()
	local m = _G.petTrickModel
	if typeof(m) == "Instance" and m.Parent then
		local ok, cf = pcall(function() return m:GetPivot() end)
		if ok then return cf end
	end
	local r = rootOf()
	return r and (r.CFrame * CFrame.new(2.5, 0, 1.5)) or nil
end

-- ===== POSITION HISTORY (Bloom Trail needs where you have BEEN, not where you are) =====
local trail = {}
task.spawn(function()
	while true do
		task.wait(0.4)
		local r = rootOf()
		if r then
			table.insert(trail, r.Position)
			if #trail > 25 then table.remove(trail, 1) end   -- ~10 seconds of history
		end
	end
end)

-- ==============================================================================================================
-- THE TRICKS. Keyed by the id PetAbilities.DEFS publishes.
-- ==============================================================================================================
local TRICKS = {}

-- 7. PIZZA DRAGON -- FIRE BREATH
TRICKS.firebreath = {
	name = "Fire Breath",
	run = function()
		local pcf = petRoot(); local r = rootOf(); if not pcf or not r then return end
		local dir = r.CFrame.LookVector
		for i = 1, 14 do
			local t = i / 14
			local pos = pcf.Position + dir * (3 + t * 22) + Vector3.new(0, 1 - t * 1.5, 0)
			local flame = fxPart(Vector3.new(1, 1, 1) * (1.5 + t * 4),
				Color3.fromRGB(255, 200 - math.floor(t * 140), 60 - math.floor(t * 50)),
				CFrame.new(pos), Enum.Material.Neon, Enum.PartType.Ball, 0.25)
			task.delay(t * 0.25, function() fade(flame, 0.45, flame.Size * 1.6) end)
		end
		-- the scorch it leaves behind, on the ground under the cone
		local scorch = fxPart(Vector3.new(16, 0.15, 16), Color3.fromRGB(40, 28, 22),
			CFrame.new(r.Position + dir * 14 - Vector3.new(0, 2.6, 0)),
			Enum.Material.Slate, Enum.PartType.Cylinder, 0.2)
		scorch.CFrame = scorch.CFrame * CFrame.Angles(0, 0, math.rad(90))
		fade(scorch, 6)
		-- and the joke that sells it: every marshmallow on the island is done, instantly.
		if type(_G.campfireRoastAll) == "function" then pcall(_G.campfireRoastAll) end
	end,
}

-- 8. SUNFLOWER BEE -- BLOOM TRAIL
TRICKS.bloomtrail = {
	name = "Bloom Trail",
	run = function()
		if #trail == 0 then return end
		for i, pos in ipairs(trail) do
			task.delay(i * 0.05, function()
				local stem = fxPart(Vector3.new(0.3, 3, 0.3), Color3.fromRGB(96, 168, 60),
					CFrame.new(pos - Vector3.new(0, 1.5, 0)), Enum.Material.Grass)
				local head = fxPart(Vector3.new(2.2, 0.5, 2.2), Color3.fromRGB(250, 205, 60),
					CFrame.new(pos + Vector3.new(0, 1.4, 0)), Enum.Material.Neon, Enum.PartType.Cylinder, 0)
				head.CFrame = head.CFrame * CFrame.Angles(0, 0, math.rad(90))
				burst(head, Color3.fromRGB(255, 235, 140), 8, 1.2, 4)
				fade(stem, 7); fade(head, 7)
			end)
		end
	end,
}

-- 9. MAPLE FOX -- LEAF STORM
TRICKS.leafstorm = {
	name = "Leaf Storm",
	run = function()
		local r = rootOf(); if not r then return end
		for i = 1, 40 do
			local ang = (i / 40) * math.pi * 4
			local rad = 4 + (i / 40) * 9
			local leaf = fxPart(Vector3.new(0.9, 0.12, 1.3),
				(i % 3 == 0) and Color3.fromRGB(222, 120, 52) or Color3.fromRGB(190, 92, 40),
				CFrame.new(r.Position + Vector3.new(math.cos(ang) * rad, (i / 40) * 12 - 2, math.sin(ang) * rad))
					* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
				Enum.Material.SmoothPlastic)
			local spin = CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3)
			TweenService:Create(leaf, TweenInfo.new(1.6, Enum.EasingStyle.Quad), {
				CFrame = leaf.CFrame * CFrame.new(0, 8, 0) * spin, Transparency = 1,
			}):Play()
			Debris:AddItem(leaf, 1.9)
		end
		-- the blink: it vanishes in a puff and is suddenly at your shoulder
		local m = _G.petTrickModel
		if typeof(m) == "Instance" and m.Parent then
			local pcf = petRoot()
			if pcf then
				local puff = fxPart(Vector3.new(3, 3, 3), Color3.fromRGB(222, 120, 52), pcf,
					Enum.Material.Neon, Enum.PartType.Ball, 0.4)
				burst(puff, Color3.fromRGB(245, 180, 90), 30)
				fade(puff, 0.4, Vector3.new(7, 7, 7))
			end
			pcall(function() m:PivotTo(r.CFrame * CFrame.new(2, 1.6, 0.5)) end)
		end
	end,
}

-- 10. FROST PENGUIN -- BELLY SLIDE
TRICKS.bellyslide = {
	name = "Belly Slide",
	run = function()
		local r = rootOf(); if not r then return end
		local dir = r.CFrame.LookVector * Vector3.new(1, 0, 1)
		dir = (dir.Magnitude > 0) and dir.Unit or Vector3.new(0, 0, 1)
		local sheet = fxPart(Vector3.new(10, 0.4, 44), Color3.fromRGB(180, 225, 245),
			CFrame.lookAt(r.Position + dir * 20 - Vector3.new(0, 2.8, 0), r.Position + dir * 40 - Vector3.new(0, 2.8, 0)),
			Enum.Material.Ice, Enum.PartType.Block, 0.25)
		sheet.CanCollide = true                     -- you can genuinely stand and slide on it
		sheet.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.02, 0.5)  -- near-frictionless
		Debris:AddItem(sheet, 10)
		TweenService:Create(sheet, TweenInfo.new(9.4), { Transparency = 1 }):Play()
		for i = 1, 10 do
			local puff = fxPart(Vector3.new(2, 2, 2), Color3.fromRGB(235, 248, 255),
				CFrame.new(r.Position + dir * (i * 4) - Vector3.new(0, 2, 0)),
				Enum.Material.Neon, Enum.PartType.Ball, 0.5)
			task.delay(i * 0.06, function() fade(puff, 0.7, Vector3.new(5, 5, 5)) end)
		end
		-- the pet goes flat and rides it
		local m = _G.petTrickModel
		if typeof(m) == "Instance" and m.Parent then
			task.spawn(function()
				for i = 1, 30 do
					if not m.Parent then break end
					pcall(function() m:PivotTo(CFrame.new(r.Position + dir * (i * 1.3) - Vector3.new(0, 1.8, 0))
						* CFrame.Angles(math.rad(-70), 0, 0)) end)
					RunService.Heartbeat:Wait()
				end
			end)
		end
	end,
}

-- 11. BLOSSOM BUNNY -- PETAL BURST (the only trick other players can see the point of)
TRICKS.petalburst = {
	name = "Petal Burst",
	run = function()
		local r = rootOf(); if not r then return end
		local wave = fxPart(Vector3.new(4, 4, 4), Color3.fromRGB(245, 160, 195), CFrame.new(r.Position),
			Enum.Material.Neon, Enum.PartType.Ball, 0.4)
		fade(wave, 1.1, Vector3.new(70, 70, 70))
		burst(wave, Color3.fromRGB(252, 205, 215), 90, 1.6, 22)
		for i = 1, 30 do
			local ang = math.random() * math.pi * 2
			local rad = 5 + math.random() * 22
			local petal = fxPart(Vector3.new(0.7, 0.1, 1),
				Color3.fromRGB(240, 150, 180), CFrame.new(r.Position + Vector3.new(math.cos(ang) * rad, 6 + math.random() * 6, math.sin(ang) * rad)),
				Enum.Material.SmoothPlastic)
			TweenService:Create(petal, TweenInfo.new(2.4, Enum.EasingStyle.Linear), {
				CFrame = petal.CFrame * CFrame.new(0, -10, 0) * CFrame.Angles(2, 2, 0), Transparency = 1,
			}):Play()
			Debris:AddItem(petal, 2.6)
		end
		-- the tip. Priced off a GAS bubble (the smaller of the two pickups) so a trick can never out-earn
		-- actually flying, and routed through CoinEvent so it is validated and capped like everything else.
		if CoinEvent and _G.pickupCoins then
			local tip = math.floor(_G.pickupCoins("gas", r.Position.Y))
			if tip > 0 then pcall(function() CoinEvent:FireServer(tip) end) end
		end
	end,
}

-- 12. MOLTEN BEAN -- MELTDOWN
TRICKS.meltdown = {
	name = "Meltdown",
	run = function()
		local r = rootOf(); if not r then return end
		local core = fxPart(Vector3.new(5, 5, 5), Color3.fromRGB(255, 245, 220), CFrame.new(r.Position),
			Enum.Material.Neon, Enum.PartType.Ball, 0.15)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 140, 40); light.Brightness = 8; light.Range = 40; light.Parent = core
		TweenService:Create(core, TweenInfo.new(1.4), { Color = Color3.fromRGB(255, 90, 30), Size = Vector3.new(9, 9, 9) }):Play()
		TweenService:Create(light, TweenInfo.new(2.6), { Brightness = 0 }):Play()
		fade(core, 2.6)
		burst(core, Color3.fromRGB(255, 150, 40), 60, 1.4, 18)
		-- lava cracks spidering out, then cooling to obsidian
		for i = 1, 12 do
			local ang = (i / 12) * math.pi * 2
			local len = 8 + math.random() * 10
			local crack = fxPart(Vector3.new(0.8, 0.12, len), Color3.fromRGB(255, 110, 30),
				CFrame.new(r.Position + Vector3.new(math.cos(ang) * len / 2, -2.7, math.sin(ang) * len / 2))
					* CFrame.Angles(0, -ang, 0), Enum.Material.Neon)
			task.delay(1.6, function()
				if crack.Parent then
					TweenService:Create(crack, TweenInfo.new(2.2), { Color = Color3.fromRGB(28, 22, 26) }):Play()
				end
			end)
			fade(crack, 6)
		end
	end,
}

-- 13. VOID DRAGON -- RIFT
TRICKS.rift = {
	name = "Rift",
	run = function()
		local r = rootOf(); if not r then return end
		local portal = fxPart(Vector3.new(0.6, 12, 12), Color3.fromRGB(120, 60, 200),
			CFrame.new(r.Position + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Enum.Material.Neon, Enum.PartType.Cylinder, 0.1)
		burst(portal, Color3.fromRGB(180, 120, 255), 70, 1.5, 20)
		TweenService:Create(portal, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Size = Vector3.new(0.6, 26, 26) }):Play()
		fade(portal, 3.2)
		-- THE ACTUAL POWER: it drags every pickup in the gap to you. REACH ONLY -- a bubble pulled in is worth
		-- exactly what it was worth where it sat, and the gas ones still grant their normal (capped) power, so
		-- this cannot put a wall in range that was not already.
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 2.2 do
				local here = rootOf(); if not here then break end
				local target = here.Position + Vector3.new(0, 3, 0)
				for _, ring in ipairs(_G.activeRings or {}) do
					local prt = ring and ring.part
					if prt and prt.Parent and (prt.Position - target).Magnitude < 420 then
						prt.CFrame = prt.CFrame:Lerp(CFrame.new(target), 0.10)
					end
				end
				for _, pocket in ipairs(_G.activeGasPockets or {}) do
					if pocket and pocket.Parent and (pocket.Position - target).Magnitude < 420 then
						pocket.CFrame = pocket.CFrame:Lerp(CFrame.new(target), 0.10)
					end
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end,
}

-- 14. PRISM FOX -- REFRACT
TRICKS.refract = {
	name = "Refract",
	run = function()
		local r = rootOf(); if not r then return end
		local m = _G.petTrickModel
		-- afterimages of your whole collection, fanned out around you
		for i = 1, 7 do
			local hue = (i - 1) / 7
			local ang = (i / 7) * math.pi * 2
			local pos = r.Position + Vector3.new(math.cos(ang) * 7, 1.5, math.sin(ang) * 7)
			local ghost
			if typeof(m) == "Instance" and m.Parent then
				local ok, clone = pcall(function() return m:Clone() end)
				if ok and clone then
					for _, d in ipairs(clone:GetDescendants()) do
						if d:IsA("BasePart") then
							d.Transparency = 0.55; d.Color = Color3.fromHSV(hue, 0.85, 1)
							d.Material = Enum.Material.Neon; d.CanCollide = false; d.CanQuery = false
							d.Anchored = true; d.CastShadow = false
						end
					end
					clone.Parent = workspace
					pcall(function() clone:PivotTo(CFrame.new(pos)) end)
					Debris:AddItem(clone, 2.4)
					ghost = clone
				end
			end
			if not ghost then
				local orb = fxPart(Vector3.new(2.5, 2.5, 2.5), Color3.fromHSV(hue, 0.85, 1), CFrame.new(pos),
					Enum.Material.Neon, Enum.PartType.Ball, 0.35)
				fade(orb, 2.2, Vector3.new(5, 5, 5))
			end
		end
		-- and the rainbow thrown across the sky
		for i = 1, 7 do
			local beam = fxPart(Vector3.new(2.4, 260, 2.4), Color3.fromHSV((i - 1) / 7, 0.9, 1),
				CFrame.new(r.Position + Vector3.new((i - 4) * 3.2, 130, 0)) * CFrame.Angles(math.rad(12), 0, 0),
				Enum.Material.Neon, Enum.PartType.Block, 0.45)
			task.delay(i * 0.05, function() fade(beam, 2.0) end)
		end
	end,
}

-- ==============================================================================================================
-- SUNFLOWER BEE'S EXTRA COIN BUBBLES.
-- Not a trick -- a passive that has to build world objects, so it lives here rather than in the resolver.
-- COIN bubbles only. Gas bubbles stay at exactly two per gap: CLAUDE.md's own margin figures show the pair
-- already leaves only ~7-10 studs of slack on the Medium/Large/XL walls, and a third would clear a wall the gut
-- was never meant to clear. A coin bubble carries no power at all, so it is free to hand out.
-- ==============================================================================================================
local bonusRingsBuilt = 0
task.spawn(function()
	while true do
		task.wait(5)
		local want = math.floor(player:GetAttribute("PetAbil_bubbleExtra") or 0)
		if want > bonusRingsBuilt and _G.spawnRing and _G.ISLAND_POS and _G.RING_COLORS then
			local pos = _G.ISLAND_POS
			for extra = bonusRingsBuilt + 1, want do
				for i = 1, math.min(13, #pos - 1) do
					local a, b = pos[i], pos[i + 1]
					if a and b then
						-- Offset from the two stock rings both vertically (a different slice of the gap) and
						-- angularly, so a bonus bubble is a new place to go rather than a duplicate sitting
						-- on top of one you already sweep.
						local t   = (extra + 0.5) / 3.5
						local ang = (extra * 2.4) + i
						local rad = 95 + (extra % 2) * 40
						local p = Vector3.new(
							a.x + (b.x - a.x) * t + math.cos(ang) * rad,
							a.y + 120 + ((b.y - 200) - (a.y + 120)) * t,
							a.z + (b.z - a.z) * t + math.sin(ang) * rad)
						local dir = (Vector3.new(b.x, b.y, b.z) - Vector3.new(a.x, a.y, a.z))
						pcall(_G.spawnRing, p, _G.RING_COLORS[((i + extra) % 3) + 1], 900 + extra * 20 + i,
							dir.Magnitude > 0 and dir.Unit or Vector3.new(0, 1, 0))
					end
				end
			end
			bonusRingsBuilt = want
			print(("[PetTricks] Pollen Sweep: %d extra coin bubble(s) per gap now in the world"):format(want))
		end
	end
end)

-- ==============================================================================================================
-- THE BUTTON.
-- Right edge, below the STATS panel (which ends around y=527) and clear of the centred bottom stack and of
-- both mobile thumbsticks. It is its own ScreenGui with its own name so RailGuard -- which owns the 4-button
-- left rail and the MORE+ grid -- has no reason to touch it.
-- ==============================================================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "PetTrickGui"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.DisplayOrder = 6; gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local btn = Instance.new("TextButton")
btn.AnchorPoint      = Vector2.new(1, 0.5)
btn.Position         = UDim2.new(1, -24, 0.62, 0)
btn.Size             = UDim2.fromOffset(78, 78)
btn.BackgroundColor3 = Color3.fromRGB(140, 70, 210)
btn.Text             = ""
btn.AutoButtonColor  = true
btn.BorderSizePixel  = 0
btn.Parent           = gui
Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
local stroke = Instance.new("UIStroke", btn)
stroke.Color = Color3.fromRGB(255, 205, 70); stroke.Thickness = 3

local icon = Instance.new("TextLabel")
icon.Size = UDim2.fromScale(1, 0.62); icon.Position = UDim2.fromScale(0, 0.06)
icon.BackgroundTransparency = 1
icon.Font = Enum.Font.FredokaOne; icon.Text = "\xE2\x9C\xA6"
icon.TextColor3 = Color3.new(1, 1, 1); icon.TextSize = 34
icon.Parent = btn

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 0.34); label.Position = UDim2.fromScale(0, 0.62)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold; label.Text = "TRICK"
label.TextColor3 = Color3.fromRGB(255, 235, 190); label.TextSize = 12
label.Parent = btn

-- The cooldown reads as the button DRAINING, not as a number counting down: a wedge of dark sweeping over the
-- face is legible at a glance from across a phone screen, which a two-digit timer is not.
local cool = Instance.new("Frame")
cool.AnchorPoint = Vector2.new(0, 1)
cool.Position = UDim2.fromScale(0, 1); cool.Size = UDim2.fromScale(1, 0)
cool.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
cool.BackgroundTransparency = 0.45
cool.BorderSizePixel = 0
cool.ZIndex = 3
cool.Parent = btn
Instance.new("UICorner", cool).CornerRadius = UDim.new(1, 0)

local readyAt = 0

local function currentTrick()
	local id = player:GetAttribute("PetTrick")
	if type(id) ~= "string" or id == "" then return nil end
	return TRICKS[id], id
end

local function refreshButton()
	local trick = currentTrick()
	gui.Enabled = trick ~= nil
	if trick then label.Text = string.upper(trick.name) end
end

local function fire()
	local trick, id = currentTrick()
	if not trick then return end
	if os.clock() < readyAt then return end
	readyAt = os.clock() + COOLDOWN
	cool.Size = UDim2.fromScale(1, 1)
	TweenService:Create(cool, TweenInfo.new(COOLDOWN, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 0) }):Play()
	if _G.hapticPulse then pcall(_G.hapticPulse, "milestone") end
	local ok, err = pcall(trick.run)
	if not ok then warn(("[PetTricks] '%s' failed: %s"):format(tostring(id), tostring(err))) end
end

btn.Activated:Connect(fire)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.T then fire() end
end)

player:GetAttributeChangedSignal("PetTrick"):Connect(refreshButton)
task.defer(refreshButton)

print("[PetTricks] ready -- 8 pet tricks bound to the TRICK button (or T), " .. COOLDOWN .. "s cooldown")
