-- ============================================================================
-- MEATBALL SHOOTER (easter egg) — a HIDDEN part named "Meatballshooter" on Pasta Peak. Every 4-7 minutes (random)
-- it fires a volley of meatballs that shoot UP and kind of OUT (a meatball fountain); they arc, land, and clean up.
-- The part is invisible + non-colliding in game. Type the chat command (default "meatballs") to fire a volley on
-- demand for testing (test users only). Fully cosmetic + server-side.
-- ============================================================================

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")
local Debris    = game:GetService("Debris")

-- =========================== EASY-EDIT CONFIG ===============================
local CONFIG = {
	shooterName  = "Meatballshooter",            -- the placed part to fire from
	minInterval  = 240,                          -- min seconds between auto-volleys (4 min)
	maxInterval  = 420,                          -- max seconds between auto-volleys (7 min)
	perVolley    = 6,                            -- meatballs per volley
	volleyStagger= 0.12,                         -- seconds between each meatball in a volley (rapid fire)
	meatballSize = 6.0,                          -- meatball diameter (studs) — BIG so it's easy to see
	upSpeed      = 80,                           -- launch speed UP (studs/s) — flies high so it's visible from afar
	outSpeed     = 32,                           -- random sideways "out" spread (studs/s)
	lifetime     = 10,                           -- how long meatballs last before cleanup (seconds)
	hitSoundId   = "",                           -- TODO optional: a "splat"/launch sound id (rbxassetid://...)
	chatCommand  = "meatballs",                  -- type this in chat to fire a test volley ("/meatballs" also works)
}
-- [TEST] only these players can fire it from chat (so it stays a hidden surprise for everyone else).
local TEST_USER_NAMES = { ["lando5485"] = true }
-- ============================================================================

local SMOOTH = Enum.SurfaceType.Smooth
local MEAT  = Color3.fromRGB(104, 58, 34)   -- browned meatball
local SAUCE = Color3.fromRGB(150, 40, 30)   -- marinara fleck
local function rnd(a, b) return a + math.random() * (b - a) end

local function fireOne(originPos)
	local r = CONFIG.meatballSize * rnd(0.85, 1.15)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball; ball.Size = Vector3.new(r, r, r)
	ball.Color = MEAT; ball.Material = Enum.Material.Cobblestone -- bumpy -> reads as a meatball
	ball.TopSurface = SMOOTH; ball.BottomSurface = SMOOTH
	ball.CanCollide = false; ball.CanQuery = false -- pass through the tree/canopy so it can't get blocked or stuck
	ball.CFrame = CFrame.new(originPos + Vector3.new(0, r + 4, 0)) -- spawn clear ABOVE the muzzle so it launches into open air
	-- a couple of sauce flecks welded on for flavour
	for _ = 1, 2 do
		local fleck = Instance.new("Part")
		fleck.Shape = Enum.PartType.Ball; fleck.Size = Vector3.new(r * 0.4, r * 0.4, r * 0.4)
		fleck.Color = SAUCE; fleck.Material = Enum.Material.SmoothPlastic; fleck.CanCollide = false; fleck.CanQuery = false; fleck.Massless = true
		fleck.CFrame = ball.CFrame * CFrame.new(rnd(-1, 1) * r * 0.4, rnd(-1, 1) * r * 0.4, rnd(-1, 1) * r * 0.4)
		local w = Instance.new("WeldConstraint"); w.Part0 = ball; w.Part1 = fleck; w.Parent = fleck
		fleck.Parent = ball
	end
	ball.Parent = Workspace
	-- UP + kind of OUT: mostly upward, with a random horizontal lean so the volley sprays out like a fountain
	local ang = rnd(0, math.pi * 2)
	local out = rnd(CONFIG.outSpeed * 0.4, CONFIG.outSpeed)
	ball.AssemblyLinearVelocity = Vector3.new(math.cos(ang) * out, CONFIG.upSpeed * rnd(0.9, 1.12), math.sin(ang) * out)
	ball.AssemblyAngularVelocity = Vector3.new(rnd(-12, 12), rnd(-12, 12), rnd(-12, 12))
	if CONFIG.hitSoundId ~= "" then
		local s = Instance.new("Sound"); s.SoundId = CONFIG.hitSoundId; s.Volume = 0.6; s.PlaybackSpeed = rnd(0.9, 1.2); s.Parent = ball
		pcall(function() s:Play() end)
	end
	Debris:AddItem(ball, CONFIG.lifetime)
end

local function findShooter()
	local want = string.lower(CONFIG.shooterName)
	local exact = Workspace:FindFirstChild(CONFIG.shooterName, true)
	if exact and exact:IsA("BasePart") then return exact end
	for _, d in ipairs(Workspace:GetDescendants()) do -- case-insensitive fallback
		if d:IsA("BasePart") and string.lower(d.Name) == want then return d end
	end
	return nil
end

-- We CAPTURE the launch position once and KEEP it. Something on Pasta Peak removes the part after spawn (the log
-- shows it found + hid, then later "not found"), so we can't depend on the live instance. A stored position fires
-- forever regardless. If the part is present we refresh from it (so moving it in Studio updates the spot) and hide it.
local muzzlePos
local function refreshMuzzle()
	local p = findShooter()
	if p then
		muzzlePos = p.Position
		if not p:GetAttribute("MBHidden") then
			p:SetAttribute("MBHidden", true)
			p.Transparency = 1; p.CanCollide = false; p.CastShadow = false -- hide it in-game
			print("[MeatballShooter] found + captured launch spot from '" .. p:GetFullName() .. "'")
		end
	end
	return muzzlePos ~= nil
end

local function fireVolley()
	if not refreshMuzzle() then
		warn("[MeatballShooter] '" .. CONFIG.shooterName .. "' was never found -- check the part's name/location.")
		return
	end
	for i = 1, CONFIG.perVolley do
		fireOne(muzzlePos)
		if i < CONFIG.perVolley then task.wait(CONFIG.volleyStagger) end
	end
	print("[MeatballShooter] fired a volley of " .. CONFIG.perVolley)
end

-- CHAT COMMAND (test users only): "meatballs" or "/meatballs" -> fire a volley now
local function onChat(player, msg)
	if not TEST_USER_NAMES[player.Name] then return end
	local cmd = string.lower(tostring(msg or "")):match("^%s*(.-)%s*$")
	if cmd == CONFIG.chatCommand or cmd == "/" .. CONFIG.chatCommand then
		task.spawn(fireVolley)
	end
end
Players.PlayerAdded:Connect(function(p) p.Chatted:Connect(function(m) onChat(p, m) end) end)
for _, p in ipairs(Players:GetPlayers()) do p.Chatted:Connect(function(m) onChat(p, m) end) end

task.spawn(function()
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end

	for _ = 1, 40 do if refreshMuzzle() then break end; task.wait(1) end -- capture the launch spot ONCE (kept forever)
	if muzzlePos then
		print("[MeatballShooter] ready (chat '" .. CONFIG.chatCommand .. "' to test; auto-fires every "
			.. CONFIG.minInterval .. "-" .. CONFIG.maxInterval .. "s).")
	else
		warn("[MeatballShooter] '" .. CONFIG.shooterName .. "' not found -- check the part's name/location.")
	end
	-- AUTO-FIRE forever from the captured spot
	while true do
		task.wait(rnd(CONFIG.minInterval, CONFIG.maxInterval))
		if muzzlePos then fireVolley() end
	end
end)
