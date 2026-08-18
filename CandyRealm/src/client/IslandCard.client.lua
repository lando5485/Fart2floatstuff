--======================================================================
-- IslandCard.client.lua   (LocalScript, per-player)  -- CandyRealm
--======================================================================
-- LAND SOMEWHERE AND IT WELCOMES YOU, exactly the way realm 1 does.
--
-- ===== WHAT CHANGED, AND WHY THE OLD CARD IS GONE =====
-- This file used to draw its own side title-card ("COCONUT COVE / - ISLAND 5 -", left edge of the
-- screen) -- a look this game shares with nothing, and worse, its name table was realm 1's: it said
-- "BEAN FARM" while you stood on Candy Cane Court, because the model numbers happen to line up.
--
-- Now it does what realm 1's showArrival does: push the arrival to NotifyCenter's HERO lane --
--
--       🏝️ You reached
--       Candy Cane Court!
--
-- -- on the island's own colour, at the top ISLAND priority (it PREEMPTS a reward nag or a purchase
-- toast rather than drawing under one), for 3.5s, with realm 1's landing chime. Same payload shape,
-- same priority, same duration, same sound id. The banner therefore also inherits every behaviour the
-- hero lane already has here: the TopCenterStack keeps it clear of other banners, and the quest objectives
-- no longer compete for the spot at all -- ObjectiveBannerBridge hides their eleven home-made banners for
-- good and re-pushes their text at PRIORITY.REWARD, which this ISLAND-priority card outranks outright.
--
-- Names come from IslandOrder (slot names), so the banner can never disagree with the wormhole, the HUD
-- or the shop about what an island is called.
--
-- ===== WHAT DID NOT CHANGE =====
-- The landing detector. Realm 1 fires from a server WelcomeEvent Candy doesn't have; this realm's
-- client-side detector was already right -- bounding-box island resolution (pivot distance picks the
-- wrong island; that bug shipped once in the NPC arrows), grounded + still + settled before speaking,
-- once per island per session.
--======================================================================

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local IslandOrder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IslandOrder"))

local SETTLE = 0.7    -- seconds you must be on the ground before it will announce
local RESCAN = 0.6

local function norm(s) return (tostring(s):lower():gsub("[%s_%-]", "")) end

-- Per-SLOT banner colours, climbing the tower the way realm 1's islandColors ladder climbs its own:
-- greens at the bottom, ambers in the middle, cool blues and pinks near the top, red-hot at the summit.
-- Indexed by CLIMB SLOT (not model number) so the progression follows the actual ascent.
local SLOT_COLORS = {
	Color3.fromRGB(100, 200, 100), Color3.fromRGB(100, 180, 100), Color3.fromRGB(150, 200, 80),
	Color3.fromRGB(180, 220, 80),  Color3.fromRGB(255, 180, 50),  Color3.fromRGB(220, 160, 80),
	Color3.fromRGB(200, 120, 60),  Color3.fromRGB(100, 180, 255), Color3.fromRGB(150, 200, 255),
	Color3.fromRGB(255, 150, 200), Color3.fromRGB(255, 80, 80),
}

-- Realm 1's landing chime.
--
-- ⚠ THE ID IS EMPTY ON PURPOSE. It was 117464325212045, copied over from realm 1 -- but that asset is not
-- shared with THIS experience, so every single island arrival threw:
--     "The experience doesn't have access permission to use asset id 117464325212045"
--     "Failed to load sound rbxassetid://117464325212045: User is not authorized to access Asset."
-- plus Studio's "Click to share access" nag. It never made a sound here; it only made noise in the log.
-- Asset ids do not travel between experiences just because the code does.
--
-- TO GIVE THE ARRIVAL ITS CHIME BACK: either share that asset with this experience on the Creator
-- Dashboard, or paste an id this place owns below. An empty id stays silent and creates no Sound at all.
local ISLAND_CHIME = ""

local function playIslandSound()
	if ISLAND_CHIME == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId = ISLAND_CHIME
	sound.Volume = 0.8
	sound.Parent = Workspace
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 4)
end

-- Realm 1's showArrival, fed by this realm's names and colours. NotifyCenter owns the pixels.
local function showArrival(islandNum)
	local NC = _G.NotifyCenter
	if not NC then return end
	local slot = IslandOrder.ISLAND_TO_SLOT[islandNum]
	local name = IslandOrder.NAME_BY_ISLAND[islandNum] or ("Island " .. islandNum)
	NC.push({
		top      = "\xF0\x9F\x8F\x9D\xEF\xB8\x8F You reached",
		text     = name .. "!",
		color    = (slot and SLOT_COLORS[slot]) or Color3.fromRGB(100, 200, 100),
		priority = NC.PRIORITY.ISLAND,
		duration = 3.5,
		sound    = playIslandSound,
	})
end

-- ---- which island am I on? -------------------------------------------------
-- Bounding boxes, same as the NPC arrows. Pivot distance picks the wrong island entirely,
-- which is the bug that made those arrows point at island 14 while stood on island 8.
local boxes = {}
local function boxOf(m)
	local b = boxes[m]
	if b and b.h.X > 25 and b.h.Z > 25 then return b end
	local ok, cf, size = pcall(function() return m:GetBoundingBox() end)
	if not ok or not cf then return nil end
	b = { c = cf.Position, h = size * 0.5 }
	boxes[m] = b
	return b
end

local function islandUnder(pos)
	local best, bestScore, bestN
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") then
			local n = norm(m.Name):match("^island(%d+)$")
			if n then
				local b = boxOf(m)
				if b then
					local dx = math.max(0, math.abs(pos.X - b.c.X) - b.h.X)
					local dz = math.max(0, math.abs(pos.Z - b.c.Z) - b.h.Z)
					local score = math.sqrt(dx * dx + dz * dz) * 1000 + (b.h.X + b.h.Z)
					if not bestScore or score < bestScore then
						best, bestScore, bestN = m, score, tonumber(n)
					end
				end
			end
		end
	end
	-- only if you are genuinely over it, not merely nearest to it
	if best and bestScore and bestScore < 1000 then return bestN end
	return nil
end

local seen, current, grounded, nextScan = {}, nil, 0, 0

RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp then return end

	-- WAIT UNTIL YOU ARE DOWN. Mid-flight you cross several islands, and announcing each one as
	-- you pass over it turns the banner into a ticker. Grounded, and still, and then it speaks.
	local still = (not _G.isFlying)
		and (hum == nil or hum.FloorMaterial ~= Enum.Material.Air)
		and hrp.AssemblyLinearVelocity.Magnitude < 26
	grounded = still and (grounded + dt) or 0

	local now = os.clock()
	if now < nextScan then return end
	nextScan = now + RESCAN

	local n = islandUnder(hrp.Position)
	if n ~= current then
		current = n
		return                       -- one scan of settling before it may announce
	end
	if n and grounded >= SETTLE and not seen[n] then
		seen[n] = true
		showArrival(n)
		print(("[IslandCard] arrived on island %d -- %s"):format(n, IslandOrder.NAME_BY_ISLAND[n] or "?"))
	end
end)

print("[IslandCard] ready -- realm 1's arrival banner (NotifyCenter hero lane), this realm's island names")
