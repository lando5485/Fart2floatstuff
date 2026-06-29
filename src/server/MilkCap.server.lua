-- ============================================================================
-- MILK CAP (easter egg) — on Milk Marsh (island 9) there's a placed part named "MilkCap". Every 4-7 minutes
-- (random) the cap goes INVISIBLE and MILK GEYSERS out of that spot for a few seconds, then the cap reappears and
-- the spewing stops. No spinning / flying off — just the cap vanishing and a big flowy milk fountain. "/milkcap" tests it.
-- Cosmetic + server-side. The spew location is captured once so it works even if the cap gets moved.
-- ============================================================================

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")

-- =========================== EASY-EDIT CONFIG ===============================
local CONFIG = {
	capName      = "MilkCap",                    -- the placed cap part on Milk Marsh
	minInterval  = 240,                          -- min seconds between auto-events (4 min)
	maxInterval  = 420,                          -- max seconds between auto-events (7 min)
	spewDuration = 4.5,                          -- how long milk geysers for (seconds)
	flowRate     = 200,                          -- density of the thick milk column (particles/sec)
	frothRate    = 130,                          -- density of the finer spray on top
	chatCommand  = "milkcap",                    -- "/milkcap" (or "milkcap") to test
}
-- [TEST] only these players can fire it from chat (keeps it a hidden surprise for everyone else).
local TEST_USER_NAMES = { ["lando5485"] = true }
-- ============================================================================

local MILK  = Color3.fromRGB(255, 255, 252)
local function rnd(a, b) return a + math.random() * (b - a) end
local function seq(pts) local k = {} for _, p in ipairs(pts) do k[#k + 1] = NumberSequenceKeypoint.new(p[1], p[2]) end return NumberSequence.new(k) end

local function findCap()
	local want = string.lower(CONFIG.capName)
	local exact = Workspace:FindFirstChild(CONFIG.capName, true)
	if exact and exact:IsA("BasePart") then return exact end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and string.lower(d.Name) == want then return d end
	end
	return nil
end

local homeCF       -- captured carton-opening CFrame (kept forever, survives the cap being moved/destroyed)
local milkEmitters -- { {emitter, onRate}, ... }

local function setupSpew()
	local anchor = Instance.new("Part")
	anchor.Name = "MilkSpewAnchor"; anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false
	anchor.CastShadow = false; anchor.Transparency = 1; anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = homeCF; anchor.Parent = Workspace

	-- thick, slow, opaque MILK COLUMN — heavy gravity + drag so it pours/arcs like liquid (not raining balls)
	local flow = Instance.new("ParticleEmitter")
	flow.Texture = "rbxasset://textures/particles/smoke_main.dds"
	flow.Color = ColorSequence.new(MILK)
	flow.Transparency = seq({ {0, 0.05}, {0.55, 0.2}, {1, 1} })
	flow.Size = seq({ {0, 3.2}, {0.5, 5.5}, {1, 7.5} })   -- BIG
	flow.Lifetime = NumberRange.new(1.0, 1.9)
	flow.Speed = NumberRange.new(28, 44)
	flow.SpreadAngle = Vector2.new(13, 13)               -- focused column
	flow.Acceleration = Vector3.new(0, -65, 0)           -- gravity -> flows up then pours back down
	flow.Drag = 2.2                                       -- slows particles -> liquid, flowy feel
	flow.Rotation = NumberRange.new(0, 360); flow.RotSpeed = NumberRange.new(-45, 45)
	flow.LightEmission = 0.3; flow.EmissionDirection = Enum.NormalId.Top
	flow.Rate = 0; flow.Parent = anchor

	-- finer, faster FROTH/SPRAY layered on top for a wet milky look
	local froth = Instance.new("ParticleEmitter")
	froth.Texture = "rbxasset://textures/particles/smoke_main.dds"
	froth.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	froth.Transparency = seq({ {0, 0.25}, {1, 1} })
	froth.Size = seq({ {0, 1.4}, {1, 3.6} })
	froth.Lifetime = NumberRange.new(0.5, 1.1)
	froth.Speed = NumberRange.new(42, 64)
	froth.SpreadAngle = Vector2.new(28, 28)
	froth.Acceleration = Vector3.new(0, -52, 0)
	froth.Drag = 1; froth.LightEmission = 0.45; froth.EmissionDirection = Enum.NormalId.Top
	froth.Rate = 0; froth.Parent = anchor

	milkEmitters = { { flow, CONFIG.flowRate }, { froth, CONFIG.frothRate } }
end

local function setSpew(on)
	if not milkEmitters then return end
	for _, e in ipairs(milkEmitters) do e[1].Rate = on and e[2] or 0 end
end

local busy = false
local function doMilkCap()
	if busy then return end
	busy = true
	if not homeCF then busy = false; return end

	-- the cap goes INVISIBLE (no spin / no flying off) while the milk pours out
	local cap = findCap()
	local origT = cap and cap.Transparency or 0
	if cap then cap.Transparency = 1 end

	setSpew(true)                       -- milk fountain ON
	task.wait(CONFIG.spewDuration)
	setSpew(false)                      -- spewing stops (existing particles finish their lifetime -> natural tail-off)

	if cap and cap.Parent then cap.Transparency = origT end -- cap reappears
	busy = false
	print("[MilkCap] milk geyser done; cap visible again.")
end

-- CHAT COMMAND (test users only): "/milkcap" or "milkcap"
local function onChat(player, msg)
	if not TEST_USER_NAMES[player.Name] then return end
	local cmd = string.lower(tostring(msg or "")):match("^%s*(.-)%s*$")
	if cmd == CONFIG.chatCommand or cmd == "/" .. CONFIG.chatCommand then task.spawn(doMilkCap) end
end
Players.PlayerAdded:Connect(function(p) p.Chatted:Connect(function(m) onChat(p, m) end) end)
for _, p in ipairs(Players:GetPlayers()) do p.Chatted:Connect(function(m) onChat(p, m) end) end

task.spawn(function()
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end

	local cap
	for _ = 1, 40 do cap = findCap(); if cap then break end; task.wait(1) end
	if not cap then warn("[MilkCap] '" .. CONFIG.capName .. "' not found in Workspace -> disabled.") return end
	homeCF = cap.CFrame    -- capture the cap's home/opening CFrame ONCE (kept forever)
	cap.CastShadow = false -- turn off the cap part's shadow
	setupSpew()
	print("[MilkCap] ready at '" .. cap:GetFullName() .. "' (chat '/" .. CONFIG.chatCommand
		.. "' to test; auto every " .. CONFIG.minInterval .. "-" .. CONFIG.maxInterval .. "s).")

	while true do
		task.wait(rnd(CONFIG.minInterval, CONFIG.maxInterval))
		doMilkCap()
	end
end)
