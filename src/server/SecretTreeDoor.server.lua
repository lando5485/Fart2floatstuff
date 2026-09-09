-- ============================================================================
-- SECRET TREE DOOR (easter egg) — a hidden, framed doorway carved into the existing "SecretTree", with a
-- LITTLE GUY (a tiny gnome/creature) living inside. Knock (E): the door creaks open, the little guy WALKS OUT
-- of the dark hollow, faces you, hands over a reward in his speech bubble, waves, and walks back in as the door
-- shuts. ONE-TIME per player (server-validated + DataStore-saved); after that he pops out with a flavour line and
-- gives nothing. Built from simple SmoothPlastic parts (no studs), in the existing easter-egg style.
-- ============================================================================

local Workspace        = game:GetService("Workspace")
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage    = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")

-- =========================== EASY-EDIT CONFIG ===============================
local CONFIG = {
	treeName     = "SecretTree",                  -- attach the door to this EXISTING tree in Workspace
	sideShift    = 0.0,                           -- shift the whole assembly along the trunk face to centre it (+= right)
	backShift    = 0.1,                           -- push the whole assembly into the trunk (+= backwards/recessed)
	-- COSMETIC SET DRESSING (mat + sign + mailbox + ambient life — all non-colliding, won't block the prompt/walk):
	signText       = "Gnome Home",
	butterflyCount = 3,                           -- little butterflies bobbing near the doorway (0 = none)
	pollenRate     = 5,                           -- drifting pollen motes per second (0 = off)
	gnomeScale   = 0.55,                          -- the little guy = a garden gnome shrunk to this scale (~55%)
	-- REWARD (easy to swap — see grantReward() to tie into another system instead of coins):
	rewardCoins  = 100,
	claimMode    = "once",                        -- "once" = one-time per player (saved) | "cooldown" = repeatable
	cooldownSecs = 24 * 3600,                     -- only used when claimMode == "cooldown" (once per day)
	-- LITTLE GUY — walk speed / timing (seconds) + his lines (all easy to edit):
	walkTime     = 1.4,                           -- time to walk out (and back)
	doorOpenWait = 0.55,                          -- after the door starts opening, before he steps out
	pauseTime    = 0.35,                          -- settle before handing over
	holdTime     = 1.6,                           -- how long he stays out after handing over
	hintHoldTime = 10,                            -- ...but 10s when he gives the buried-gnome hint instead
	giveLines    = { "Here, take this!", "A little gift for you!", "You found me! Here ya go!" },
	emptyLines   = { "Nothing today \xE2\x80\x94 come back later!", "All out for now... try again another day!" },
	-- ===== HE KNOWS ABOUT HIS BROTHER =====
	-- The buried gnome (CommunityGarden) is only visible while rain darkens the soil beds, which makes it
	-- unfindable by anyone who does not already know to look. This is the pointer -- and it comes from the
	-- one NPC who is himself a secret, so you only get the hint after solving a smaller puzzle.
	--
	-- DELIBERATELY NOT AN INSTRUCTION. It names the weather and the beds and stops there: no coordinates,
	-- no marker, no quest entry. It should send someone to the garden the next time it rains and leave the
	-- finding to them, because being told exactly where it is turns the secret into an errand.
	--
	-- SHORT. A speech bubble is a small white box read at a glance while a gnome is walking back into a
	-- tree -- anything past about seven words is a paragraph nobody finishes before it closes.
	hintLines    = {
		"Four in the garden. Only four.",
		"My brother stayed out in the rain.",
		"Dry earth hides a red hat.",
		"Check the beds when it storms.",
	},
	-- ===== BRINGING THE BROTHER HOME =====
	-- Dug up in the garden (CommunityGarden), carried across the island, and walked up to this door. There
	-- is no prompt for this and no quest step: you just arrive holding him and it happens. That is the
	-- point -- the only way to trigger it is to have worked out, unprompted, that the gnome you dug up and
	-- the gnome who told you about him are the same story.
	reunionDist    = 12,          -- how close you have to get, carrying him, for the door to notice
	reunionTokens  = 100,         -- four times the dig, and in the premium currency, not coins
	reunionTitle   = "Gnome Brothers",   -- REPLACES "Gnome Finder": the title itself proves you finished it
	-- THE KEY. Bring his brother home and the little gnome lets you INTO the tree: the door opens for
	-- you and you step through into his home -- a hollow room nobody else can reach. It is not a
	-- number and not a cosmetic; it is a place in the world that only exists for people who did this.
	-- Saved per player, so it survives leaving. (The door does NOT stay open -- it opens when a key
	-- holder asks and closes behind them; knocking works exactly as before for everyone.)
	homeDepth      = 350,         -- studs BELOW the door the room is built (out of sight of everything)
	homeLockedLine = "Locked. Brothers only.",   -- kept for reference; the menu replaced the locked door
	-- What he says when a KEY HOLDER asks him to come out for a chat. Warmer than the giveLines -- you
	-- are not a stranger knocking any more, you are the one who brought his brother home.
	visitLines     = {
		"Oh, it is you! Come in whenever.",
		"He is inside. He is always inside.",
		"Mind the roots. They move.",
		"We were just talking about you.",
		"Kettle is on. Sort of.",
	},
	reunionLines   = {
		"BROTHER!",
		"You found him. You actually found him.",
		"Stay, brother. Stay right here.",
		"And you... here. Come in whenever you like.",
	},
	-- prompt:
	promptText   = "Knock",
	promptDist   = 8,                             -- must be close (it's a secret)
	-- POLISH sounds (blank by default so nothing fails to load; drop in rbxassetid:// to enable):
	creakSoundId   = "",                          -- TODO: a soft creak on open
	ambientSoundId = "",                          -- TODO: a faint looping hum near the tree
}
-- ============================================================================

local SMOOTH = Enum.SurfaceType.Smooth
local SMOOTHPLASTIC = Enum.Material.SmoothPlastic
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part")
	p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
	p.Material = material or SMOOTHPLASTIC -- default SmoothPlastic -> no stud texture
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH -- all faces smooth -> no studs/dots
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end
local function pick(t) return t[math.random(1, #t)] end

-- ----- overhead bubble (same white rounded style the cow/farmer use) -----
local function makeBubble(adornee, heightY)
	local bb = Instance.new("BillboardGui")
	bb.Name = "DoorBubble"; bb.Adornee = adornee
	bb.Size = UDim2.fromOffset(230, 60); bb.StudsOffset = Vector3.new(0, heightY, 0)
	bb.AlwaysOnTop = true; bb.LightInfluence = 0; bb.MaxDistance = 26; bb.Enabled = false; bb.Parent = adornee
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1); frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BackgroundTransparency = 0.05; frame.BorderSizePixel = 0; frame.Parent = bb
	Instance.new("UICorner").Parent = frame
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(40, 40, 46); stroke.Thickness = 2; stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1; label.Size = UDim2.new(1, -16, 1, -10); label.Position = UDim2.fromOffset(8, 5)
	label.Font = Enum.Font.GothamBold; label.TextSize = 18; label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(34, 34, 40); label.Text = ""; label.Parent = frame
	return { gui = bb, label = label }
end
local function bubbleSay(bubble, msg, secs)
	if not (bubble and bubble.gui.Parent) then return end
	bubble.label.Text = msg; bubble.gui.Enabled = true
	task.delay(secs or 4, function() if bubble.gui.Parent then bubble.gui.Enabled = false end end)
end

-- =============================== DATASTORE CLAIM ============================
local CLAIM_STORE = DataStoreService:GetDataStore("SecretTreeDoor_v1")
local claimedAt, loaded = {}, {} -- [player] = unix time of last claim (0 = never)
local function loadClaim(p)
	local ok, v = pcall(function() return CLAIM_STORE:GetAsync(tostring(p.UserId)) end)
	claimedAt[p] = (ok and type(v) == "number") and v or 0
	loaded[p] = true
end
local function saveClaim(p) pcall(function() CLAIM_STORE:SetAsync(tostring(p.UserId), claimedAt[p] or 0) end) end
local function canClaim(p)
	if not loaded[p] then loadClaim(p) end
	local last = claimedAt[p] or 0
	if last == 0 then return true end
	if CONFIG.claimMode == "cooldown" then return (os.time() - last) >= CONFIG.cooldownSecs end
	return false -- "once" and already claimed
end
Players.PlayerAdded:Connect(function(p) task.spawn(loadClaim, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(loadClaim, p) end
Players.PlayerRemoving:Connect(function(p) claimedAt[p] = nil; loaded[p] = nil end)

-- ===== THE GNOME HOME KEY =====
-- Its own store, not a field on the claim: the claim is a timestamp with cooldown semantics and the key
-- is a permanent yes. Mirrored onto a player attribute so the client (and anything else) can read it.
local KEY_STORE = DataStoreService:GetDataStore("GnomeHomeKey_v1")
local hasKey = {}
-- ===== THE TESTING RESET APPLIES HERE TOO =====
-- This key has its own store, and for a long time that meant it sailed straight past PlayerStats'
-- DISABLE_SAVE_FOR_TESTING. A tester who had EVER carried the brother home (or typed /key once) then
-- joined every "brand-new" run already holding the key: the door menu opened on a fresh account with the
-- brother still buried, which is exactly the gate this file exists to enforce. Fresh means fresh.
-- One `task.wait()` first so PlayerStats' main chunk has published the flag before we read it -- both are
-- server Scripts and Roblox does not promise an order.
local function freshTesting()
	return _G.FRESH_PLAYER_TESTING == true
end
local function loadKey(p)
	task.wait()
	if freshTesting() then
		hasKey[p] = false
		pcall(function() p:SetAttribute("GnomeHomeKey", false) end)
		print(("[SecretDoor] %s starts WITHOUT the Gnome Home key (FRESH_PLAYER_TESTING) -- carry the brother home to earn it")
			:format(p.Name))
		return
	end
	local ok, v = pcall(function() return KEY_STORE:GetAsync(tostring(p.UserId)) end)
	hasKey[p] = (ok and v == true)
	if hasKey[p] then pcall(function() p:SetAttribute("GnomeHomeKey", true) end) end
end
local function giveKey(p)
	hasKey[p] = true
	pcall(function() p:SetAttribute("GnomeHomeKey", true) end)
	-- Not written while testing: a key granted in a throwaway run must not outlive it, or the next
	-- "fresh" join is back to the bug above.
	if freshTesting() then return end
	task.spawn(function() pcall(function() KEY_STORE:SetAsync(tostring(p.UserId), true) end) end)
end
-- Hands the key back. The store is the authority, so clearing it there is what actually undoes a key
-- somebody has already earned -- /key uses this to toggle.
local function takeKey(p)
	hasKey[p] = false
	pcall(function() p:SetAttribute("GnomeHomeKey", false) end)
	if freshTesting() then return end
	task.spawn(function() pcall(function() KEY_STORE:RemoveAsync(tostring(p.UserId)) end) end)
end
Players.PlayerAdded:Connect(function(p) task.spawn(loadKey, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(loadKey, p) end
Players.PlayerRemoving:Connect(function(p) hasKey[p] = nil end)

-- ===== ONE PROMPT, THEN A MENU =====
-- Two prompts on one door (E to knock, F to go in) is the same mistake the gnome had: Roblox shows one
-- of them and the other may as well not exist, and even when both render it is a guessing game. So a
-- key holder gets ONE prompt that opens a little panel and asks what they actually want -- bring him
-- out for a chat, or go inside. Client builds the panel, server decides everything that matters.
local GnomeHomeMenu = ReplicatedStorage:FindFirstChild("GnomeHomeMenu")
if not GnomeHomeMenu then
	GnomeHomeMenu = Instance.new("RemoteEvent")
	GnomeHomeMenu.Name = "GnomeHomeMenu"
	GnomeHomeMenu.Parent = ReplicatedStorage
end

-- TEST COMMAND /key -- hands the test accounts the Gnome Home key without the dig-carry-reunite chain,
-- so the room itself can be checked in seconds. Same allow-list as every other test command; anyone
-- else typing it gets nothing. REMOVE BEFORE LAUNCH.
task.spawn(function()
	local TCS = game:GetService("TextChatService")
	local ok, err = pcall(function()
		local c = Instance.new("TextChatCommand")
		c.Name = "TestGnomeKeyCommand"
		c.PrimaryAlias = "/key"
		c.Parent = TCS
		c.Triggered:Connect(function(source, text)
			local plr = source and Players:GetPlayerByUserId(source.UserId)
			if not plr then return end
			if type(_G.isAllowedTestUser) == "function" and not _G.isAllowedTestUser(plr) then return end
			-- TOGGLE, not a one-way grant. Testing the LOCK is as important as testing the room, and
			-- before this there was no way to put the key back once you had it -- the store said yes
			-- forever and every later run started past the gate.
			if hasKey[plr] then
				takeKey(plr)
				print(("[TEST] /key -- %s no longer holds the Gnome Home key (the door is locked again). REMOVE BEFORE LAUNCH.")
					:format(plr.Name))
			else
				giveKey(plr)
				print(("[TEST] /key -- %s now holds the Gnome Home key (press E at the tree door). REMOVE BEFORE LAUNCH.")
					:format(plr.Name))
			end
		end)
	end)
	if not ok then warn("[SecretDoor] /key command registration failed: " .. tostring(err)) end
end)

-- REWARD: easy to swap. Default = coins. To tie into another system, replace the body, e.g.:
--   if _G.grantGutSkin then _G.grantGutSkin(p, "Gold") end      -- a cosmetic skin / pet item / crate / etc.
local function grantReward(p)
	local ls = p:FindFirstChild("leaderstats")
	local coins = ls and ls:FindFirstChild("Coins")
	local tce   = ls and ls:FindFirstChild("TotalCoinsEarned")
	if coins then coins.Value = coins.Value + CONFIG.rewardCoins end
	if tce then tce.Value = tce.Value + CONFIG.rewardCoins end
end

-- ================= the EMBEDDED, FRAMED DOORWAY (carved-look) ==============
local function buildDoor(treeCF, trunkR, parent)
	local model = Instance.new("Model"); model.Name = "SecretDoor"; model.Parent = parent
	local function cx(x, y, z) return treeCF * CFrame.new(x, y, z) end
	local surf = trunkR -- the bark front is at local z = -surf

	-- (4) proportion to the trunk: small + never wider than the trunk, sits flat on the ground at the base.
	-- (trunkR is estimated from the bounding box, so keep the door modest so it stays "small + hidden".)
	local dW = math.clamp(trunkR * 1.0, 1.0, 1.5)
	local dH = math.clamp(trunkR * 1.8, 1.9, 2.5)
	local dT, fW, fT = 0.14, 0.16, 0.26
	local doorY = dH / 2 -- door bottom rests on the ground

	local DOOR  = Color3.fromRGB(82, 58, 38)  -- (5) the door
	local FRAME = Color3.fromRGB(45, 32, 22)  -- (3) frame: darker brown than the trunk
	local DARK  = Color3.fromRGB(14, 11, 9)   -- (2) dark hollow you see when it opens

	-- (2) dark backing right at the bark -> a dark opening shows when the door swings aside (never grass)
	newPart(model, "Backing", Enum.PartType.Block, Vector3.new(dW + 0.06, dH + 0.06, 0.12), DARK, cx(0, doorY, -(surf + 0.04)), SMOOTHPLASTIC)
	-- (3) simple wood FRAME (left / right / top), protrudes a touch so the door reads as recessed within it
	newPart(model, "FrameL", Enum.PartType.Block, Vector3.new(fW, dH + fW, fT), FRAME, cx(-(dW / 2 + fW / 2), doorY, -(surf + 0.12)), Enum.Material.SmoothPlastic)
	newPart(model, "FrameR", Enum.PartType.Block, Vector3.new(fW, dH + fW, fT), FRAME, cx( (dW / 2 + fW / 2), doorY, -(surf + 0.12)), Enum.Material.SmoothPlastic)
	newPart(model, "FrameT", Enum.PartType.Block, Vector3.new(dW + fW * 2, fW, fT), FRAME, cx(0, dH + fW / 2, -(surf + 0.12)), Enum.Material.SmoothPlastic)

	-- (1)(2) DOOR: SmoothPlastic, recessed within the frame (set back from the frame's front lip)
	local closedCF = cx(0, doorY, -(surf + 0.12))
	local door = newPart(model, "Door", Enum.PartType.Block, Vector3.new(dW, dH, dT), DOOR, closedCF, SMOOTHPLASTIC)
	door.CanQuery = true -- so the ProximityPrompt is interactable
	-- (5) brass/gold knob, SmoothPlastic
	newPart(model, "Knob", Enum.PartType.Ball, Vector3.new(0.16, 0.16, 0.16), Color3.fromRGB(214, 176, 92),
		closedCF * CFrame.new(dW * 0.33, 0, -(dT / 2 + 0.04)), SMOOTHPLASTIC)
	-- hinge on the LEFT edge -> swing open about it
	local hingeCF = closedCF * CFrame.new(-dW / 2, 0, 0)
	local openCF  = hingeCF * CFrame.Angles(0, math.rad(108), 0) * CFrame.new(dW / 2, 0, 0)

	-- faint glow inside + soft hum so observant players notice something's here
	local backing = model:FindFirstChild("Backing")
	local glow = Instance.new("PointLight"); glow.Color = Color3.fromRGB(255, 222, 150); glow.Brightness = 1.2; glow.Range = 7; glow.Parent = backing
	if CONFIG.ambientSoundId ~= "" then
		local s = Instance.new("Sound"); s.SoundId = CONFIG.ambientSoundId; s.Looped = true; s.Volume = 0.25
		s.RollOffMaxDistance = 28; s.RollOffMinDistance = 6; s.Parent = backing; pcall(function() s:Play() end)
	end

	return { model = model, door = door, closedCF = closedCF, openCF = openCF, surf = surf }
end

-- smooth matte, no studs/decals (used for the trunk + the cloned gnome)
local function cleanSmooth(part)
	part.Material = SMOOTHPLASTIC
	part.TopSurface = SMOOTH; part.BottomSurface = SMOOTH; part.LeftSurface = SMOOTH
	part.RightSurface = SMOOTH; part.FrontSurface = SMOOTH; part.BackSurface = SMOOTH
end

-- ===================== the LITTLE GUY = a shrunk GARDEN GNOME ==============
-- Clone the existing CommunityGarden gnome ("GardenGnome" clone, or the "Gnome" template), shrink it, and clean it
-- to the same smooth matte look (no studs/decals). Falls back to a tiny built gnome if the garden gnome isn't found.
local function buildGnome(parent)
	local src = Workspace:FindFirstChild("GardenGnome", true) or Workspace:FindFirstChild("Gnome", true)
		or ServerStorage:FindFirstChild("Gnome", true)
	local model
	if src and src:IsA("Model") then
		model = src:Clone()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
				cleanSmooth(d); if d:IsA("MeshPart") then d.TextureID = "" end
			elseif d:IsA("Decal") or d:IsA("Texture") then d:Destroy()           -- kill pasted-on stud/texture decals
			elseif d:IsA("Humanoid") or d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end -- static cosmetic only
		end
		pcall(function() model:ScaleTo(CONFIG.gnomeScale) end) -- shrink to a smaller version that fits the door
	else
		model = Instance.new("Model") -- fallback: a tiny smooth gnome so the feature still works
		local b = newPart(model, "Body", Enum.PartType.Ball, Vector3.new(0.8, 0.9, 0.8), Color3.fromRGB(86, 128, 70), CFrame.new()); b.Anchored = true; model.PrimaryPart = b
		newPart(model, "Head", Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(255, 214, 170), CFrame.new(0, 0.55, 0))
		newPart(model, "Hat",  Enum.PartType.Ball, Vector3.new(0.66, 0.5, 0.66), Color3.fromRGB(180, 62, 56), CFrame.new(0, 0.85, 0))
		newPart(model, "HatTip", Enum.PartType.Ball, Vector3.new(0.28, 0.36, 0.28), Color3.fromRGB(180, 62, 56), CFrame.new(0, 1.06, 0))
	end
	model.Name = "LittleGuy"; model.Parent = parent
	if not model.PrimaryPart then -- pick the highest part (~= the head) as the bubble anchor
		local top; for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") and (not top or d.Position.Y > top.Position.Y) then top = d end end
		model.PrimaryPart = top
	end
	-- snapshot each part's transparency so we can hide him in the hollow and restore him exactly
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then parts[#parts + 1] = { d, d.Transparency } end end
	return { model = model, parts = parts }
end
local function setGnomeVisible(g, v)
	for _, e in ipairs(g.parts) do e[1].Transparency = v and e[2] or 1 end
end

-- ===================== cosmetic SET DRESSING around the door ==============
-- Welcome mat + "Gnome Home" sign + tiny mailbox + gentle butterflies/pollen. All built off doorCF, on the
-- ground, non-colliding (newPart -> CanCollide false), so nothing blocks the prompt or the gnome's walk-out.
local function buildSetDressing(doorCF, surf, parent)
	local model = Instance.new("Model"); model.Name = "SecretDoorDressing"; model.Parent = parent
	local function at(x, h, z) return doorCF * CFrame.new(x, h, z) end
	local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- stands a Cylinder (length = X) up vertically
	local WOOD = Color3.fromRGB(96, 66, 42)

	-- WELCOME MAT: a thin flat oval (rounded), flush on the ground, centred in front of the door
	newPart(model, "WelcomeMat", Enum.PartType.Cylinder, Vector3.new(0.08, 1.4, 1.05), Color3.fromRGB(166, 126, 84), at(0, 0.04, -(surf + 1.15)) * FLAT)
	newPart(model, "MatTrim",    Enum.PartType.Cylinder, Vector3.new(0.085, 1.0, 0.72), Color3.fromRGB(122, 90, 58), at(0, 0.045, -(surf + 1.15)) * FLAT)

	-- "GNOME HOME" SIGN: small post + board to the LEFT, board facing the player's approach (-Z)
	local sx = -1.5
	newPart(model, "SignPost", Enum.PartType.Cylinder, Vector3.new(1.1, 0.12, 0.12), WOOD, at(sx, 0.55, -(surf + 0.8)) * FLAT)
	local board = newPart(model, "SignBoard", Enum.PartType.Block, Vector3.new(1.0, 0.44, 0.08), Color3.fromRGB(204, 170, 120), at(sx, 1.18, -(surf + 0.8)))
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.Parent = board
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne; lbl.TextScaled = true; lbl.Text = CONFIG.signText; lbl.TextColor3 = Color3.fromRGB(70, 46, 28)
	local ls = Instance.new("UIStroke"); ls.Color = Color3.fromRGB(235, 220, 190); ls.Thickness = 1; ls.Parent = lbl
	lbl.Parent = sg

	-- TINY MAILBOX: post + rounded box to the RIGHT, with a little red flag (purely cosmetic)
	local mx = 1.5
	newPart(model, "MailPost", Enum.PartType.Cylinder, Vector3.new(1.05, 0.12, 0.12), WOOD, at(mx, 0.52, -(surf + 0.7)) * FLAT)
	newPart(model, "MailBox",  Enum.PartType.Block, Vector3.new(0.5, 0.36, 0.64), Color3.fromRGB(70, 112, 170), at(mx, 1.12, -(surf + 0.7)))
	newPart(model, "MailLid",  Enum.PartType.Cylinder, Vector3.new(0.5, 0.46, 0.66), Color3.fromRGB(70, 112, 170), at(mx, 1.30, -(surf + 0.7))) -- rounded top (axis along X)
	newPart(model, "FlagPole", Enum.PartType.Block, Vector3.new(0.04, 0.32, 0.04), WOOD, at(mx + 0.27, 1.22, -(surf + 0.7)))
	newPart(model, "Flag",     Enum.PartType.Block, Vector3.new(0.04, 0.18, 0.2), Color3.fromRGB(200, 62, 55), at(mx + 0.27, 1.32, -(surf + 0.6)))

	-- POLLEN: a gentle drift of pale motes near the doorway (daytime, not glowy). Rate is easy to tune.
	if CONFIG.pollenRate > 0 then
		local anchor = newPart(model, "PollenAnchor", Enum.PartType.Block, Vector3.new(0.1, 0.1, 0.1), Color3.fromRGB(255, 255, 255), at(0, 1.1, -(surf + 0.7)))
		anchor.Transparency = 1
		local att = Instance.new("Attachment"); att.Parent = anchor
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(Color3.fromRGB(245, 238, 200)); pe.Transparency = NumberSequence.new(0.45)
		pe.Lifetime = NumberRange.new(3, 5); pe.Speed = NumberRange.new(0.3, 0.8); pe.Rate = CONFIG.pollenRate
		pe.SpreadAngle = Vector2.new(60, 60); pe.Size = NumberSequence.new(0.12); pe.LightEmission = 0
		pe.Acceleration = Vector3.new(0, 0.25, 0); pe.Rotation = NumberRange.new(0, 360); pe.RotSpeed = NumberRange.new(-30, 30)
		pe.EmissionDirection = Enum.NormalId.Top; pe.Parent = att
	end

	-- BUTTERFLIES: a few that gently bob + drift near the doorway. Count is easy to tune.
	local wingColors = { Color3.fromRGB(245, 225, 130), Color3.fromRGB(240, 180, 205), Color3.fromRGB(172, 202, 240), Color3.fromRGB(200, 235, 175) }
	local flock = {}
	for i = 1, math.max(0, CONFIG.butterflyCount) do
		local ang  = (i / math.max(1, CONFIG.butterflyCount)) * math.pi * 2
		local home = at(math.cos(ang) * 1.1, 1.35 + (i % 2) * 0.4, -(surf + 1.0 + math.sin(ang) * 0.5))
		local bm   = Instance.new("Model"); bm.Name = "Butterfly"; bm.Parent = model
		local col  = wingColors[((i - 1) % #wingColors) + 1]
		local body = newPart(bm, "BBody", Enum.PartType.Ball, Vector3.new(0.09, 0.2, 0.09), Color3.fromRGB(45, 38, 32), home); body.Anchored = true
		local function weld(p) p.Anchored = false; local w = Instance.new("WeldConstraint"); w.Part0 = body; w.Part1 = p; w.Parent = p end
		weld(newPart(bm, "WingL", Enum.PartType.Block, Vector3.new(0.03, 0.24, 0.32), col, home * CFrame.new(-0.15, 0, 0) * CFrame.Angles(0, 0, math.rad(22))))
		weld(newPart(bm, "WingR", Enum.PartType.Block, Vector3.new(0.03, 0.24, 0.32), col, home * CFrame.new( 0.15, 0, 0) * CFrame.Angles(0, 0, math.rad(-22))))
		flock[#flock + 1] = { part = body, home = home, phase = ang, speed = 1.4 + (i % 3) * 0.25 }
	end
	if #flock > 0 then
		local t = 0
		RunService.Heartbeat:Connect(function(dt)
			t = t + dt
			for _, b in ipairs(flock) do
				local bob = math.sin(t * b.speed + b.phase) * 0.32
				local dx  = math.cos(t * b.speed * 0.6 + b.phase) * 0.35
				local dz  = math.sin(t * b.speed * 0.5 + b.phase) * 0.35
				b.part.CFrame = b.home * CFrame.new(dx, bob, dz) * CFrame.Angles(0, math.sin(t * 0.6 + b.phase) * 0.8, 0)
			end
		end)
	end
end

-- =============================== WIRE IT UP ================================
task.spawn(function()
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end

	-- find the EXISTING tree named CONFIG.treeName (retry a bit in case it streams/loads in)
	local treeInst
	for _ = 1, 30 do treeInst = Workspace:FindFirstChild(CONFIG.treeName, true); if treeInst then break end; task.wait(1) end
	if not treeInst then
		warn(("[SecretDoor] '%s' not found in Workspace -> door NOT attached. Check the tree's name/location."):format(CONFIG.treeName))
		return
	end

	-- bottom-centre + size of the tree (Model -> bounding box; Part -> itself; container -> first part inside)
	local centerCF, size
	if treeInst:IsA("Model") then centerCF, size = treeInst:GetBoundingBox()
	elseif treeInst:IsA("BasePart") then centerCF, size = treeInst.CFrame, treeInst.Size
	else
		local part = treeInst:FindFirstChildWhichIsA("BasePart", true)
		if not part then warn(("[SecretDoor] '%s' has no parts -> door NOT attached."):format(CONFIG.treeName)); return end
		centerCF, size = part.CFrame, part.Size
	end
	local basePos = Vector3.new(centerCF.X, centerCF.Y - size.Y / 2, centerCF.Z)
	local trunkR  = math.clamp(math.min(size.X, size.Z) * 0.5, 0.8, 3)

	-- which side of the trunk faces the garden (so the door goes on that side)
	local garden = Workspace:FindFirstChild("CommunityGardenBuild", true) or Workspace:FindFirstChild("GardenHardscape", true)
	local facePos = basePos + Vector3.new(0, 0, -10)
	if garden and garden:IsA("Model") then facePos = garden:GetBoundingBox().Position
	elseif garden then local gp = garden:FindFirstChildWhichIsA("BasePart", true); if gp then facePos = gp.Position end end
	local gardenDir = Vector3.new(facePos.X - basePos.X, 0, facePos.Z - basePos.Z)
	gardenDir = (gardenDir.Magnitude > 0.1) and gardenDir.Unit or Vector3.new(0, 0, -1)

	-- (2) NO ANGLE: align the door to the TRUNK's own face. Snap to the tree's horizontal axis that points most
	-- toward the garden, then face the door straight along it -> upright (no tilt), flat + flush against that face.
	local treeCFrame = (treeInst:IsA("Model") and treeInst:GetPivot())
		or (treeInst:IsA("BasePart") and treeInst.CFrame) or CFrame.new(basePos)
	local axes = {}
	for _, v in ipairs({ treeCFrame.LookVector, -treeCFrame.LookVector, treeCFrame.RightVector, -treeCFrame.RightVector }) do
		local f = Vector3.new(v.X, 0, v.Z) -- flatten to horizontal so the door always stands straight up
		if f.Magnitude > 0.05 then axes[#axes + 1] = f.Unit end
	end
	if #axes == 0 then axes = { Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) } end
	local bestDir, bestDot = axes[1], -math.huge
	for _, a in ipairs(axes) do local d = a:Dot(gardenDir); if d > bestDot then bestDot, bestDir = d, a end end
	local treeCF = CFrame.lookAt(basePos, basePos + bestDir) -- upright; -Z (door front) flush to the chosen trunk face

	local parent = (treeInst:IsA("Model") and treeInst) or Workspace

	-- (3) clean the TRUNK: smooth all faces + SmoothPlastic so no studs show (mesh textures, if any, are kept)
	if treeInst:IsA("BasePart") then cleanSmooth(treeInst) end
	for _, d in ipairs(treeInst:GetDescendants()) do if d:IsA("BasePart") then cleanSmooth(d) end end

	-- (1) shift the whole door assembly along the trunk face so it centres better on the trunk
	local doorCF = treeCF * CFrame.new(CONFIG.sideShift, 0, CONFIG.backShift)
	local tree = buildDoor(doorCF, trunkR, parent)
	local surf = tree.surf

	-- cosmetic set dressing (mat + "Gnome Home" sign + mailbox + butterflies/pollen), aligned to the door
	pcall(buildSetDressing, doorCF, surf, parent)

	-- (2) the little guy = a shrunk garden gnome, hidden just inside the doorway, feet on the ground
	local gnome = buildGnome(parent)
	local R0 = gnome.model:GetPivot().Rotation -- the orientation that keeps the (cloned) gnome upright
	local homePos = (doorCF * CFrame.new(0, 0, -(surf + 0.1))).Position
	gnome.model:PivotTo(CFrame.new(homePos) * R0)
	local gcf, gsize = gnome.model:GetBoundingBox()
	gnome.model:PivotTo(gnome.model:GetPivot() + Vector3.new(0, basePos.Y - (gcf.Position.Y - gsize.Y / 2), 0)) -- feet on the door base
	local homePivot = gnome.model:GetPivot()
	setGnomeVisible(gnome, false) -- hidden in the dark hollow until knocked

	-- bubble above his head + a sparkle on him (PrimaryPart ≈ his head, picked in buildGnome)
	local head = gnome.model.PrimaryPart
	local bcf, bsize = gnome.model:GetBoundingBox()
	local bubble = makeBubble(head, (bcf.Position.Y + bsize.Y / 2 - head.Position.Y) + 0.6)
	local sAtt = Instance.new("Attachment"); sAtt.Position = Vector3.new(0, 0.2, 0); sAtt.Parent = head
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150))
	sparkle.Lifetime = NumberRange.new(0.6, 1.1); sparkle.Speed = NumberRange.new(1, 3); sparkle.Rate = 0
	sparkle.SpreadAngle = Vector2.new(50, 50); sparkle.Size = NumberSequence.new(0.5); sparkle.LightEmission = 0.6
	sparkle.Parent = sAtt

	-- door + gnome motion (the walk-out is purely VISUAL; the reward is granted server-side below)
	local function openDoor()
		TweenService:Create(tree.door, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = tree.openCF }):Play()
		if CONFIG.creakSoundId ~= "" then
			local s = Instance.new("Sound"); s.SoundId = CONFIG.creakSoundId; s.Volume = 0.5; s.Parent = tree.door
			pcall(function() s:Play() end); task.delay(3, function() s:Destroy() end)
		end
	end
	local function closeDoor()
		TweenService:Create(tree.door, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = tree.closedCF }):Play()
	end
	-- manual MODEL tween (TweenService can't tween a Model): lerp the pivot -> walks the whole anchored gnome.
	local function walkGnome(targetCF, dur)
		local startCF = gnome.model:GetPivot()
		local t0 = os.clock()
		while true do
			local a = math.clamp((os.clock() - t0) / dur, 0, 1)
			gnome.model:PivotTo(startCF:Lerp(targetCF, a * a * (3 - 2 * a))) -- smoothstep ease
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end
	end
	-- he stands just outside the door (keeping his upright orientation; translate-only avoids tilting the clone)
	local outFlat = (doorCF * CFrame.new(0, 0, -(surf + 1.9))).Position
	local gnomeOutPivot = CFrame.new(Vector3.new(outFlat.X, homePivot.Position.Y, outFlat.Z)) * R0
	local function waveGnome() -- a friendly little hop
		local base = gnome.model:GetPivot()
		walkGnome(base * CFrame.new(0, 0.3, 0), 0.18); walkGnome(base, 0.18)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = CONFIG.promptText; prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E; prompt.MaxActivationDistance = CONFIG.promptDist
	prompt.RequiresLineOfSight = false; prompt.HoldDuration = 0; prompt.Parent = tree.door

	local busy = false
	prompt.Triggered:Connect(function(player)
		-- KEY HOLDERS GET THE MENU INSTEAD. Everyone else knocks, exactly as before -- the menu is not a
		-- thing you can see until you have earned the way in, so it gives nothing away.
		if hasKey[player] then
			-- The ONLY place this panel is ever opened. Logged, because "why did the menu appear?" has
			-- exactly two answers -- /key, or you carried the brother home -- and the log should say so
			-- rather than leaving it to be guessed at.
			pcall(function() GnomeHomeMenu:FireClient(player, "open") end)
			print(("[SecretDoor] menu opened for %s (holds the Gnome Home key)"):format(player.Name))
			return
		end
		if busy then return end -- one interaction at a time (also prevents double-claim while he's out)
		busy = true
		local eligible = canClaim(player) -- SERVER decides up front whether this player gets a reward
		task.spawn(function()
			openDoor()
			task.wait(CONFIG.doorOpenWait)
			setGnomeVisible(gnome, true)             -- he appears in the now-open doorway
			walkGnome(gnomeOutPivot, CONFIG.walkTime); task.wait(CONFIG.pauseTime)
			-- HAND OVER (or empty). The reward grant + claim save happen HERE on the server.
			-- How long he lingers before walking back in. Normally the short hold; the buried-gnome hint
			-- below raises it, because that one has to be READ rather than just watched.
			local hold = CONFIG.holdTime
			if eligible then
				claimedAt[player] = os.time(); task.spawn(saveClaim, player)
				grantReward(player)
				sparkle:Emit(22)
				bubbleSay(bubble, pick(CONFIG.giveLines), 5)
				print(("[SecretDoor] %s received the reward from the little gnome"):format(player.Name))
			else
				-- NOTHING TO GIVE, SO HE TALKS INSTEAD. This is the better use of a wasted trip: a player who
				-- comes back on cooldown currently gets told off and nothing else, and that is the exact
				-- moment to spend a hint on them. Weighted so the refusal still reads first most of the time
				-- -- a hint every single visit stops being a secret and becomes signposting.
				if math.random() < 0.45 then
					-- HE STAYS OUT LONGER FOR THIS ONE. A hint is worth nothing if it is gone before you
					-- have read it, and the normal 1.6s hold is tuned for handing over an item -- you watch
					-- the gift, not the words. Ten seconds is long enough to read it, re-read it, and get a
					-- screenshot, which is how a hint like this actually travels between players.
					hold = CONFIG.hintHoldTime
					-- ALL FOUR LINES, IN ORDER, LIKE SLIDES -- not one picked at random. The list is written
					-- rough-to-specific (how many gnomes there are, then that one is missing, then what hides
					-- him, then where to look), so read as a sequence it actually explains something. Picked
					-- at random it was four disconnected mutterings and you needed four visits to get the one
					-- line that mattered.
					--
					-- ONE bubbleSay for the whole run, then the text is swapped underneath it. Calling
					-- bubbleSay per line would queue a hide for each: slide 1 s hide would fire partway
					-- through slide 2 and blank the bubble mid-sentence.
					bubbleSay(bubble, CONFIG.hintLines[1], hold)
					task.spawn(function()
						local per = hold / #CONFIG.hintLines
						for i = 2, #CONFIG.hintLines do
							task.wait(per)
							-- Only while the bubble is still the one we started: he may have been walked back
							-- in, or another player may have knocked and taken it over.
							if bubble.gui.Parent and bubble.gui.Enabled then
								bubble.label.Text = CONFIG.hintLines[i]
							end
						end
					end)
					print(("[SecretDoor] %s got the buried-gnome hint -- %d slides over %ds")
						:format(player.Name, #CONFIG.hintLines, hold))
				else
					bubbleSay(bubble, pick(CONFIG.emptyLines), 5) -- already claimed / on cooldown -> no grant
				end
			end
			task.wait(hold)
			waveGnome(); task.wait(0.3)
			walkGnome(homePivot, CONFIG.walkTime)
			setGnomeVisible(gnome, false)            -- back into the dark hollow
			closeDoor()
			busy = false
		end)
	end)

	-- ===== THE GNOME HOME =====
	-- The room behind the door. The trunk is a stud and a half across, so the room cannot literally be
	-- inside it -- it is built far BELOW the tree and you are moved there through a blackout, which is
	-- what every "bigger on the inside" door in a game does. Nobody can walk to it, fall to it or see it:
	-- the only way in is the door, and the door only opens for the key.
	--
	-- Persistent streaming, because the room sits hundreds of studs from any player until the moment one
	-- is teleported into it, and an unstreamed room is a fall through nothing.
	local homeCF = CFrame.new(doorCF.Position - Vector3.new(0, CONFIG.homeDepth, 0))
	local home = Instance.new("Model"); home.Name = "GnomeHome"; home.Parent = parent
	pcall(function() home.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
	local W, H, D = 18, 10.5, 18   -- 20% wider and taller again: snug, but not tight
	local BARK, WOOD, RED = Color3.fromRGB(86, 60, 40), Color3.fromRGB(150, 108, 66), Color3.fromRGB(168, 38, 32)
	local function solid(name, size, color, cf, mat)
		local part = newPart(home, name, Enum.PartType.Block, size, color, cf, mat)
		part.CanCollide = true; part.CanQuery = true; part.CastShadow = true
		return part
	end
	local function prop(name, size, color, cf, mat, shape)
		local part = newPart(home, name, shape or Enum.PartType.Block, size, color, cf, mat)
		part.CastShadow = true
		return part
	end
	local function at(x, y, z) return homeCF * CFrame.new(x, y - H / 2 + 0.5, z) end   -- y measured from the FLOOR

	-- The shell: you are inside a tree, so every wall is bark and the floor is planks laid over roots.
	solid("Floor",   Vector3.new(W, 1, D), WOOD, homeCF * CFrame.new(0, -H / 2, 0), Enum.Material.SmoothPlastic)
	solid("Ceiling", Vector3.new(W, 1, D), BARK, homeCF * CFrame.new(0,  H / 2, 0), Enum.Material.SmoothPlastic)
	solid("WallN", Vector3.new(W, H, 1), BARK, homeCF * CFrame.new(0, 0, -D / 2), Enum.Material.SmoothPlastic)
	solid("WallS", Vector3.new(W, H, 1), BARK, homeCF * CFrame.new(0, 0,  D / 2), Enum.Material.SmoothPlastic)
	solid("WallE", Vector3.new(1, H, D), BARK, homeCF * CFrame.new( W / 2, 0, 0), Enum.Material.SmoothPlastic)
	solid("WallW", Vector3.new(1, H, D), BARK, homeCF * CFrame.new(-W / 2, 0, 0), Enum.Material.SmoothPlastic)

	-- A rug, a round table with three stools (there are three of them now), a candle that is the room's
	-- light, a bed, a shelf of jars, a hearth, and a row of tiny hats on pegs -- one for every gnome in the
	-- family. It is a home, not a treasure room: the prize is being let in, not what is on the shelves.
	prop("Rug", Vector3.new(0.1, 7.2, 7.2), RED, at(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	prop("TableTop", Vector3.new(0.2, 3.1, 3.1), WOOD, at(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	prop("TableLeg", Vector3.new(0.4, 1.5, 0.4), WOOD, at(0, 0.8, 0), Enum.Material.SmoothPlastic)
	for i = 0, 2 do
		local a = math.rad(i * 120 + 30)
		local stool = prop("Stool", Vector3.new(0.15, 1.0, 1.0), WOOD, at(math.cos(a) * 2.3, 0.95, math.sin(a) * 2.3) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		stool.CanCollide = true
	end
	local candle = prop("Candle", Vector3.new(0.22, 0.6, 0.22), Color3.fromRGB(240, 232, 210), at(0, 2.0, 0))
	local flame = prop("Flame", Vector3.new(0.14, 0.22, 0.14), Color3.fromRGB(255, 200, 90), at(0, 2.4, 0), Enum.Material.Neon)
	local light = Instance.new("PointLight"); light.Color = Color3.fromRGB(255, 190, 120); light.Brightness = 1.8; light.Range = 26; light.Shadows = true; light.Parent = flame
	-- TWO beds against the north wall, one each. There are two of them living here now.
	for _, bx in ipairs({ -5.5, 5.5 }) do
		prop("BedBase", Vector3.new(4.4, 0.8, 2.6), WOOD, at(bx, 0.4, -7.4), Enum.Material.SmoothPlastic).CanCollide = true
		prop("Mattress", Vector3.new(4.2, 0.4, 2.4), Color3.fromRGB(226, 214, 186), at(bx, 1.0, -7.4), Enum.Material.SmoothPlastic)
		prop("Blanket", Vector3.new(2.6, 0.2, 2.4), Color3.fromRGB(52, 92, 148), at(bx + 0.8, 1.3, -7.4), Enum.Material.SmoothPlastic)
		prop("Pillow", Vector3.new(1.2, 0.35, 1.6), Color3.fromRGB(245, 240, 230), at(bx - 1.5, 1.35, -7.4), Enum.Material.SmoothPlastic)
	end
	-- Shelf of jars on the east wall.
	prop("Shelf", Vector3.new(0.4, 0.15, 7.2), WOOD, at(8.5, 3.3, 0), Enum.Material.SmoothPlastic)
	-- Five jars, evenly spaced. Nine crammed along the shelf just looked like stock.
	for i = -2, 2 do
		local jar = prop("Jar", Vector3.new(0.5, 0.8, 0.5), Color3.fromHSV((i + 2) / 5, 0.45, 0.85), at(8.5, 3.75, i * 1.35), Enum.Material.SmoothPlastic)
		jar.Transparency = 0.3
	end
	-- Hearth on the west wall: stone surround, a low fire, and a second warm light so the room is lit
	-- from two sides and nothing sits in a hard shadow.
	prop("HearthBack", Vector3.new(0.6, 3.5, 4.1), Color3.fromRGB(110, 104, 96), at(-8.6, 1.75, 3.6), Enum.Material.SmoothPlastic)
	prop("HearthFloor", Vector3.new(1.9, 0.2, 4.1), Color3.fromRGB(90, 84, 78), at(-8.2, 0.1, 3.6), Enum.Material.SmoothPlastic)
	local ember = prop("Ember", Vector3.new(0.8, 0.5, 1.8), Color3.fromRGB(255, 120, 40), at(-8.2, 0.4, 3.6), Enum.Material.Neon)
	local fire = Instance.new("Fire"); fire.Size = 3; fire.Heat = 4; fire.Parent = ember
	local glow = Instance.new("PointLight"); glow.Color = Color3.fromRGB(255, 140, 60); glow.Brightness = 1.4; glow.Range = 19; glow.Parent = ember
	-- Five little hats on pegs: four for the garden gnomes, one for the brother -- all home now.
	for i = 0, 4 do
		local hx = -2.4 + i * 1.2
		prop("Peg", Vector3.new(0.15, 0.15, 0.5), WOOD, at(hx, 5.4, -8.6), Enum.Material.SmoothPlastic)
		local hat = prop("HatOnPeg", Vector3.new(0.5, 0.8, 0.5), RED, at(hx, 5.05, -8.45))
		local cone = Instance.new("SpecialMesh"); cone.MeshType = Enum.MeshType.FileMesh; cone.MeshId = "rbxassetid://1033714"; cone.Scale = Vector3.new(0.5, 0.8, 0.5); cone.Parent = hat
	end
	-- A round window on the south wall with daylight behind it. There is no outside -- the glow is a neon
	-- disc -- but a windowless room underground reads as a cell, and this reads as a burrow.
	prop("WindowGlow", Vector3.new(0.2, 2.6, 2.6), Color3.fromRGB(200, 230, 255), at(4.8, 5.3, 8.55) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.Neon, Enum.PartType.Cylinder)
	prop("WindowFrame", Vector3.new(0.3, 3.1, 3.1), WOOD, at(4.8, 5.3, 8.5) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder).Transparency = 0.5
	-- The way out: the inside face of the front door, on the south wall.
	local innerDoor = prop("InnerDoor", Vector3.new(2.0, 3.4, 0.3), Color3.fromRGB(120, 78, 44), at(0, 1.7, 8.55), Enum.Material.SmoothPlastic)
	prop("InnerKnob", Vector3.new(0.2, 0.2, 0.2), Color3.fromRGB(200, 170, 60), at(0.6, 1.7, 8.45), Enum.Material.SmoothPlastic)

	-- ===== DRESSING: A TIDY HOLLOW TREE =====
	-- Six flat walls is a cellar, so a few things say "tree": fat roots in the corners (which hide the
	-- one thing that most says BOX -- a clean 90-degree inside corner), beams across the ceiling, a moss
	-- skirting where the floor meets the wall, and warm light from more than one place.
	--
	-- DELIBERATELY BARE. Earlier passes hung roots off the ceiling, splayed roots across the floor, grew
	-- glowing mushrooms up the walls, stacked a woodpile and hung a cuckoo clock -- and the room read as
	-- a junk drawer, where the things that matter (the beds, the hearth, the table you play at) had to
	-- compete for your eye with a dozen trinkets. All of that is gone. What is left is symmetrical, on a
	-- grid, and every single piece is structure, furniture, light, or the game. None of it collides
	-- (newPart props are non-colliding), so the floor is as clear to walk as an empty room.
	local DARK  = Color3.fromRGB(58, 40, 26)
	local MOSS  = Color3.fromRGB(96, 132, 58)
	local CYL   = Enum.PartType.Cylinder
	local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))   -- a Cylinder's axis is X; this stands it on end

	-- Corner roots: four fat trunks of root in the corners, taller than the room so they run floor to
	-- ceiling and hide the one thing that most says "box" -- a clean 90-degree inside corner.
	-- The two BACK corners only. Four ringed the room and closed it in; two frame the far wall, which is
	-- the one you are looking at when you walk in.
	for _, c in ipairs({ { -1, -1 }, { 1, -1 } }) do
		local cx, cz = c[1] * (W / 2 - 0.9), c[2] * (D / 2 - 0.9)
		prop("CornerRoot", Vector3.new(H + 0.5, 2.6, 2.6), DARK, at(cx, H / 2 - 0.25, cz) * UPRIGHT, Enum.Material.SmoothPlastic)
	end

	-- Ceiling beams: three across and a spine down the middle. A ceiling with beams is a room; a flat
	-- ceiling is a lid.
	for _, bz in ipairs({ -5.4, 5.4 }) do
		prop("Beam", Vector3.new(W - 1.2, 0.8, 0.8), DARK, at(0, H - 1.0, bz), Enum.Material.SmoothPlastic)
	end
	prop("Spine", Vector3.new(0.9, 0.9, D - 1.2), DARK, at(0, H - 1.0, 0), Enum.Material.SmoothPlastic)

	-- Skirting: a band of moss where floor meets wall, the way it grows in any damp hollow.
	prop("Moss", Vector3.new(W - 2, 0.35, 0.5), MOSS, at(0, 0.2, -D / 2 + 0.75), Enum.Material.SmoothPlastic)
	prop("Moss", Vector3.new(W - 2, 0.35, 0.5), MOSS, at(0, 0.2,  D / 2 - 0.75), Enum.Material.SmoothPlastic)
	prop("Moss", Vector3.new(0.5, 0.35, D - 2), MOSS, at(-W / 2 + 0.75, 0.2, 0), Enum.Material.SmoothPlastic)
	prop("Moss", Vector3.new(0.5, 0.35, D - 2), MOSS, at( W / 2 - 0.75, 0.2, 0), Enum.Material.SmoothPlastic)

	-- Hanging lanterns: three, on chains from the beams, so the light comes from above and from more
	-- than one place. With the candle and the hearth that is five warm sources and no dead corners.
	-- Two lanterns, diagonally opposite, rather than three in a scatter -- with the candle, the hearth
	-- and the window that is still four warm sources and no dead corner.
	for _, l in ipairs({ { -4.8, -3 }, { 4.8, 3 } }) do
		prop("Chain", Vector3.new(1.6, 0.08, 0.08), Color3.fromRGB(70, 66, 60), at(l[1], H - 1.4 - 0.8, l[2]) * UPRIGHT, Enum.Material.SmoothPlastic)
		prop("LanternCap", Vector3.new(0.9, 0.18, 0.9), Color3.fromRGB(70, 66, 60), at(l[1], H - 3.05, l[2]), Enum.Material.SmoothPlastic)
		local glass = prop("LanternGlass", Vector3.new(0.7, 0.9, 0.7), Color3.fromRGB(255, 214, 140), at(l[1], H - 3.6, l[2]), Enum.Material.Neon)
		prop("LanternBase", Vector3.new(0.8, 0.14, 0.8), Color3.fromRGB(70, 66, 60), at(l[1], H - 4.1, l[2]), Enum.Material.SmoothPlastic)
		local pl = Instance.new("PointLight"); pl.Color = Color3.fromRGB(255, 200, 130); pl.Brightness = 1.3; pl.Range = 19; pl.Shadows = true; pl.Parent = glass
	end

	-- A rug beside each bed. That is the last of the dressing: past this point everything in the room is
	-- either structure, furniture, light, or the game on the table.
	for _, bx in ipairs({ -5.5, 5.5 }) do
		prop("BedRug", Vector3.new(0.08, 2.2, 2.2), Color3.fromRGB(64, 110, 150), at(bx, 0.05, -5.8) * UPRIGHT, Enum.Material.SmoothPlastic, CYL)
	end

	-- ===== FIND THE ACORN =====
	-- Something to actually DO in here, and the smallest thing that works: three hats on the table, an
	-- acorn under one, they shuffle, you pick. Ten seconds a go, no instructions needed, and it is the
	-- one game a gnome would obviously own. It pays crate tokens on a cooldown, so it is a nice thing to
	-- come back to and not a token faucet -- the room is the reward, this is what you do while you are in it.
	local acornSlots = {}
	for i = 0, 2 do
		local a = math.rad(90 + i * 120)
		acornSlots[i + 1] = at(math.cos(a) * 1.0, 1.95, math.sin(a) * 1.0)
	end
	local acorn = prop("Acorn", Vector3.new(0.34, 0.42, 0.34), Color3.fromRGB(126, 88, 46), acornSlots[1], Enum.Material.SmoothPlastic)
	local acornCap = prop("AcornCap", Vector3.new(0.36, 0.16, 0.36), Color3.fromRGB(78, 54, 30),
		acornSlots[1] * CFrame.new(0, 0.24, 0), Enum.Material.SmoothPlastic)

	local hats, hatPrompts = {}, {}
	for i = 1, 3 do
		local hat = prop("GameHat", Vector3.new(0.95, 0.95, 0.95), RED, acornSlots[i])
		local cone = Instance.new("SpecialMesh")
		cone.MeshType = Enum.MeshType.FileMesh
		cone.MeshId = "rbxassetid://1033714"
		cone.Scale = Vector3.new(0.95, 0.95, 0.95)
		cone.Parent = hat
		hat.CanQuery = true                       -- it has a prompt on it, so it must be hittable
		hats[i] = { part = hat, slot = i }
		local pr = Instance.new("ProximityPrompt")
		pr.Name = "PickHat"
		pr.ActionText = "Pick"; pr.ObjectText = "Find the Acorn"
		pr.KeyboardKeyCode = Enum.KeyCode.E
		pr.MaxActivationDistance = 12; pr.RequiresLineOfSight = false; pr.HoldDuration = 0
		pr.Enabled = false
		pr.Parent = hat
		hatPrompts[i] = pr
	end

	local playPrompt = Instance.new("ProximityPrompt")
	playPrompt.Name = "PlayAcorn"
	playPrompt.ActionText = "Play"; playPrompt.ObjectText = "Find the Acorn"
	playPrompt.KeyboardKeyCode = Enum.KeyCode.E
	playPrompt.MaxActivationDistance = 12; playPrompt.RequiresLineOfSight = false; playPrompt.HoldDuration = 0
	playPrompt.Parent = acorn
	acorn.CanQuery = true

	-- One sign over the table so nobody has to guess what the hats are for.
	local signGui = Instance.new("BillboardGui")
	signGui.Name = "AcornSign"; signGui.Adornee = acorn
	signGui.Size = UDim2.fromOffset(230, 46); signGui.StudsOffset = Vector3.new(0, 2.6, 0)
	signGui.AlwaysOnTop = false; signGui.MaxDistance = 40; signGui.Parent = acorn
	local signLbl = Instance.new("TextLabel")
	signLbl.Size = UDim2.fromScale(1, 1); signLbl.BackgroundTransparency = 1
	signLbl.Font = Enum.Font.FredokaOne; signLbl.TextScaled = true
	signLbl.TextColor3 = Color3.fromRGB(255, 240, 210)
	signLbl.Text = "Find the Acorn"
	signLbl.Parent = signGui
	local signStroke = Instance.new("UIStroke")
	signStroke.Color = Color3.fromRGB(40, 26, 14); signStroke.Thickness = 2; signStroke.Parent = signLbl

	local ACORN_REWARD, ACORN_COOLDOWN = 10, 45
	local acornBusy, acornNext = false, {}
	local function placeHats()
		for _, h in ipairs(hats) do h.part.CFrame = acornSlots[h.slot] end
	end
	local function showAcorn(under)
		-- The acorn (and its cap) live at whichever slot the winning hat is standing on.
		local cf = acornSlots[hats[under].slot]
		acorn.CFrame = cf
		if acornCap then acornCap.CFrame = cf * CFrame.new(0, 0.24, 0) end
	end

	playPrompt.Triggered:Connect(function(player)
		if acornBusy then return end
		local now = os.clock()
		if (acornNext[player] or 0) > now then
			signLbl.Text = ("Back in %ds"):format(math.ceil(acornNext[player] - now))
			task.delay(2, function() if not acornBusy then signLbl.Text = "Find the Acorn" end end)
			return
		end
		acornBusy = true
		acornNext[player] = now + ACORN_COOLDOWN
		task.spawn(function()
			-- Lift the hats so you SEE which one it goes under -- a shuffle you did not watch start is
			-- just a one-in-three guess, and the whole game is the watching.
			signLbl.Text = "Watch..."
			local winner = math.random(1, 3)
			showAcorn(winner)
			for _, h in ipairs(hats) do h.part.CFrame = acornSlots[h.slot] * CFrame.new(0, 1.1, 0) end
			task.wait(1.1)
			placeHats()
			task.wait(0.45)
			signLbl.Text = "..."

			-- SHUFFLE: swap two hats at a time, sliding them round each other so the eye can follow.
			for _ = 1, 5 do
				local i = math.random(1, 3)
				local j = i % 3 + 1
				local fromI, fromJ = acornSlots[hats[i].slot], acornSlots[hats[j].slot]
				local t0 = os.clock()
				while os.clock() - t0 < 0.34 do
					local a = (os.clock() - t0) / 0.34
					local lift = math.sin(a * math.pi) * 0.35
					hats[i].part.CFrame = fromI:Lerp(fromJ, a) * CFrame.new(0, lift, 0)
					hats[j].part.CFrame = fromJ:Lerp(fromI, a) * CFrame.new(0, -lift * 0.4, 0)
					task.wait()
				end
				hats[i].slot, hats[j].slot = hats[j].slot, hats[i].slot
				placeHats()
			end

			signLbl.Text = "Which one?"
			for _, pr in ipairs(hatPrompts) do pr.Enabled = true end
			-- Whoever started the round is the one who gets to pick, and they have ten seconds.
			local picked, deadline = nil, os.clock() + 10
			local conns = {}
			for idx, pr in ipairs(hatPrompts) do
				conns[#conns + 1] = pr.Triggered:Connect(function(who)
					if who == player and not picked then picked = idx end
				end)
			end
			while not picked and os.clock() < deadline do task.wait(0.1) end
			for _, c in ipairs(conns) do c:Disconnect() end
			for _, pr in ipairs(hatPrompts) do pr.Enabled = false end

			-- Reveal: every hat lifts, so you see where it actually was either way.
			showAcorn(winner)
			for _, h in ipairs(hats) do h.part.CFrame = acornSlots[h.slot] * CFrame.new(0, 1.1, 0) end
			if picked == winner then
				signLbl.Text = ("+%d tickets!"):format(ACORN_REWARD)
				if type(_G.addSkinTokens) == "function" then
					pcall(_G.addSkinTokens, player, ACORN_REWARD, "found the acorn")
				end
				sparkle:Emit(18)
				print(("[SecretDoor] %s found the acorn -- %d tokens"):format(player.Name, ACORN_REWARD))
			elseif picked then
				signLbl.Text = "Not that one!"
			else
				signLbl.Text = "Too slow!"
			end
			task.wait(2.2)
			placeHats()
			signLbl.Text = "Find the Acorn"
			acornBusy = false
		end)
	end)
	Players.PlayerRemoving:Connect(function(pl) acornNext[pl] = nil end)

	local insideSpawn  = at(0, 3.2, 6.7) * CFrame.Angles(0, math.rad(180), 0)   -- just inside the door, facing the room
	local outsideSpawn = doorCF * CFrame.new(0, 3.2, -(surf + 3.5))              -- just outside the tree door

	-- A blackout built on the player's own PlayerGui from the server: the server can parent a ScreenGui
	-- there and it replicates, which saves a remote and a client script for a half-second fade. Stepping
	-- the transparency by hand rather than tweening, because a server-side tween on a replicated GUI
	-- property is itself just per-frame property writes with extra machinery.
	local function blackout(player, onBlack)
		local pg = player:FindFirstChild("PlayerGui")
		if not pg then if onBlack then onBlack() end return end
		local gui = Instance.new("ScreenGui"); gui.Name = "GnomeHomeFade"; gui.IgnoreGuiInset = true
		gui.DisplayOrder = 60; gui.ResetOnSpawn = false
		local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = 1; f.BorderSizePixel = 0; f.Parent = gui
		gui.Parent = pg
		local function to(target, secs)
			local t0, from = os.clock(), f.BackgroundTransparency
			while os.clock() - t0 < secs do
				f.BackgroundTransparency = from + (target - from) * ((os.clock() - t0) / secs)
				task.wait()
			end
			f.BackgroundTransparency = target
		end
		to(0, 0.35)
		if onBlack then onBlack() end
		task.wait(0.25)
		to(1, 0.5)
		gui:Destroy()
	end
	local function moveTo(player, cf)
		local char = player.Character
		if not char then return end
		-- Ask streaming for the destination first: a teleport into an unloaded area is a fall.
		pcall(function() player:RequestStreamAroundAsync(cf.Position, 2) end)
		char:PivotTo(cf)
	end

	-- WHAT THE MENU DOES. The client only ever sends a word; the server checks the key again on arrival,
	-- because a client that can ask for a teleport is a client that will eventually ask for a free one.
	GnomeHomeMenu.OnServerEvent:Connect(function(player, choice)
		if not hasKey[player] then return end            -- re-checked here, never trusted from the client
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then return end
		-- And they still have to be AT the door -- the menu is not a remote control for a door across
		-- the island.
		if (root.Position - doorCF.Position).Magnitude > CONFIG.promptDist + 6 then return end
		if busy then return end
		busy = true
		task.spawn(function()
			if choice == "inside" then
				openDoor()
				task.wait(0.45)
				blackout(player, function() moveTo(player, insideSpawn) end)
				closeDoor()
				busy = false
				print(("[SecretDoor] %s went inside the Gnome Home"):format(player.Name))
			else
				-- "talk": he comes out, says something, and goes back in. The same walk the knock uses,
				-- so a key holder has not lost the thing knocking used to do -- it just moved into a menu.
				openDoor()
				task.wait(CONFIG.doorOpenWait)
				setGnomeVisible(gnome, true)
				walkGnome(gnomeOutPivot, CONFIG.walkTime)
				task.wait(CONFIG.pauseTime)
				bubbleSay(bubble, pick(CONFIG.visitLines), 5)
				task.wait(CONFIG.holdTime + 1.4)
				waveGnome(); task.wait(0.3)
				walkGnome(homePivot, CONFIG.walkTime)
				setGnomeVisible(gnome, false)
				closeDoor()
				busy = false
				print(("[SecretDoor] %s asked the gnome to come out for a chat"):format(player.Name))
			end
		end)
	end)

	-- COMING OUT: the inner door. Does not touch `busy` or the outer door at all, so somebody leaving
	-- can never jam a knock that is playing outside.
	local leavePrompt = Instance.new("ProximityPrompt")
	leavePrompt.ActionText = "Leave"; leavePrompt.ObjectText = "Gnome Home"
	leavePrompt.KeyboardKeyCode = Enum.KeyCode.E; leavePrompt.MaxActivationDistance = 8
	leavePrompt.RequiresLineOfSight = false; leavePrompt.HoldDuration = 0; leavePrompt.Parent = innerDoor
	leavePrompt.Triggered:Connect(function(player)
		task.spawn(blackout, player, function() moveTo(player, outsideSpawn) end)
	end)
	print(("[SecretDoor] Gnome Home built %d studs below the door -- key holders press F at the door to go in")
		:format(CONFIG.homeDepth))

	-- ===== THE REUNION =====
	-- Watches for somebody walking up to the door while carrying the buried gnome. No prompt: a prompt
	-- would be a hint, and this is the payoff for a chain that was never signposted in the first place.
	-- Once only, for the whole server -- the brother is home, and he does not need bringing home twice.
	task.spawn(function()
		local done = false
		while not done do
			task.wait(0.5)
			local carrier = _G.gnomeCarrier
			if carrier and not busy and type(_G.gnomeReunite) == "function" then
				local char = carrier.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - doorCF.Position).Magnitude <= CONFIG.reunionDist then
					done = true
					busy = true   -- shared with the knock prompt, so the two can never play over each other
					openDoor()
					task.wait(CONFIG.doorOpenWait)
					setGnomeVisible(gnome, true)
					walkGnome(gnomeOutPivot, CONFIG.walkTime)
					task.wait(CONFIG.pauseTime)

					-- The brother is taken off the carrier and parked at the little gnome's shoulder, facing
					-- the same way. CommunityGarden owns his parts, so it does the placing.
					-- GROUND HEIGHT COMES FROM THE DOOR, not from the little gnome. His pivot is his
					-- mid-body on a 0.55-scaled rig, so measuring from it buries the brother to the waist.
					-- The door was built with its bottom resting on the ground, so doorCF IS floor level.
					local brotherCF = gnomeOutPivot * CFrame.new(1.6, 0, 0)
					local brotherPos = Vector3.new(brotherCF.Position.X, doorCF.Position.Y, brotherCF.Position.Z)
					pcall(_G.gnomeReunite, CFrame.new(brotherPos) * (brotherCF - brotherCF.Position))

					-- ===== THE PRIZES =====
					-- Deliberately NOT more coins. The dig already paid tokens; this pays four times that,
					-- plus a title that REPLACES the finder one (so the old title marks somebody who only
					-- did half), plus the KEY -- a place in the world only this chain opens. Three different
					-- kinds of reward, because the chain had three different kinds of step.
					if type(_G.addSkinTokens) == "function" then
						pcall(_G.addSkinTokens, carrier, CONFIG.reunionTokens, "brought the gnome home")
					end
					if _G.grantTitle then pcall(_G.grantTitle, carrier, CONFIG.reunionTitle) end
					giveKey(carrier)
					pcall(function() carrier:SetAttribute("GnomeBrothersReunited", true) end)

					sparkle:Emit(60)
					-- All four lines as slides, same trick the hint uses: one bubbleSay, text swapped under
					-- it, so a per-line hide can never blank the bubble mid-sentence.
					local hold = CONFIG.hintHoldTime
					bubbleSay(bubble, CONFIG.reunionLines[1], hold)
					task.spawn(function()
						local per = hold / #CONFIG.reunionLines
						for i = 2, #CONFIG.reunionLines do
							task.wait(per)
							if bubble.gui.Parent and bubble.gui.Enabled then
								bubble.label.Text = CONFIG.reunionLines[i]
							end
						end
					end)
					-- He hops around his brother the whole time rather than standing there talking.
					task.spawn(function()
						for _ = 1, 6 do waveGnome(); task.wait(0.5) end
					end)
					print(("[SecretDoor] %s brought the brother home -- %d tokens + '%s' + the KEY to the Gnome Home")
						:format(carrier.Name, CONFIG.reunionTokens, CONFIG.reunionTitle))

					task.wait(hold)
					waveGnome(); task.wait(0.3)
					walkGnome(homePivot, CONFIG.walkTime)
					setGnomeVisible(gnome, false)
					closeDoor()
					busy = false
					-- The BROTHER stays out. That is the permanent mark this chain leaves on the world:
					-- everyone else sees four gnomes in the garden and two at the tree, and one player knows
					-- why. He is never moved again -- gnomeReunite destroyed his carry prompt on the way in.
				end
			end
		end
	end)

	print("[SecretDoor] secret tree door + little gnome ready on '" .. CONFIG.treeName .. "' (knock to meet him).")
end)
