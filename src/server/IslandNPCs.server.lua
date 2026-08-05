-- ============================================================================================
-- ISLAND QUEST NPCs (server)  --  one talking quest-giver per island, 1..14.
--
-- This is the Dino Realm's NPC speech + quest-accept system ported to the food realm, built to
-- NPC_SPEECH_AND_QUEST_ACCEPT.md. The whole thing in one line:
--
--     Talking to an NPC sets a player attribute on the server. Everything else gates on that.
--
--     player walks up -> ProximityPrompt "Talk" (8 studs)
--                            -> paged bubble (E advances)
--                            -> on PAGE 2: player:SetAttribute("Island<N>QuestAccepted", true)
--
-- No RemoteEvents in the accept path. The attribute is set on the SERVER, replicates to the
-- client for free, and survives respawns -- which is why a quest script needs zero knowledge of
-- the NPC and vice versa. Nothing here reads or writes flight, coins, food or island unlocks.
--
-- ===== TWO FOOD-REALM RULES THAT ARE NOT IN THE DINO DOC =====
--  1. NPCs are cloned into a Workspace FOLDER ("IslandNPCs"), NEVER inside an island model.
--     PlayerStats' stand-finder scans Workspace for models named "Island_<n>_..." and walks their
--     descendants; a rig parented into an island can break stand detection (this is exactly why
--     FarmerNPC.server.lua keeps its rig in ServerStorage and clones to "TutorialNPCs").
--  2. Placement waits for workspace:GetAttribute("StandsReady"). PlayerStats REPOSITIONS every
--     island at runtime (island 2 -> Y=790 etc). Place before that and every NPC lands at the
--     pre-move coordinates -- the same trap the pet markers hit.
-- ============================================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

-- ===== constants (NPC_SPEECH_AND_QUEST_ACCEPT.md 2c) =====
local SPEECH_LIFETIME         = 9   -- auto-hide for non-paged one-liners
-- Prompt range AND walk-away close range -- these MUST stay equal. If the prompt reaches further
-- than the conversation survives, there is a band where E opens a bubble that instantly closes.
local DIALOGUE_CLOSE_DISTANCE = 10
local STANDS_READY_TIMEOUT    = 90  -- seconds to wait for island positioning before placing anyway
local GROUND_SNAP_LIMIT       = 15  -- if a marker exists and the ray lands further than this off, the MARKER wins

-- ============================================================================================
-- 1) ADORNMENTS: name label + speech bubble  (doc 2a / 2b)
-- ============================================================================================

-- Floating name tag. MaxDistance 60 so you never read NPC names from other islands.
local function makeNameLabel(adornee, text)
	local old = adornee:FindFirstChild("NameLabel")
	if old then old:Destroy() end
	local bb = Instance.new("BillboardGui")
	bb.Name = "NameLabel"
	bb.Adornee = adornee
	bb.Size = UDim2.new(0, 200, 0, 44)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 60
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.Text = text
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextScaled = true
	lbl.Parent = bb
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(0, 0, 0); st.Thickness = 2; st.Transparency = 0.3; st.Parent = lbl
	bb.Parent = adornee
	return bb
end

local function setNameVisible(adornee, visible)
	local nl = adornee:FindFirstChild("NameLabel")
	if nl and nl:IsA("BillboardGui") then nl.Enabled = visible end
end

local function hideSpeech(adornee)
	local prev = adornee:FindFirstChild("SpeechBubble")
	if prev then prev:Destroy() end
	setNameVisible(adornee, true)
end

-- The bubble sits at +5.5 studs and is 150px tall, so its lower edge lands right on the name tag
-- at +3 -- the name is hidden for exactly as long as the NPC is talking, and restored the moment
-- the bubble goes.
local function showSpeech(adornee, text, persist, footer)
	hideSpeech(adornee)

	local bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"
	bb.Adornee = adornee
	bb.Size = UDim2.new(0, 320, 0, 150)
	bb.StudsOffset = Vector3.new(0, 5.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Parent = bb

	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 18); corner.Parent = frame
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(60,60,60); stroke.Thickness = 2; stroke.Transparency = 0.4; stroke.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0,12); pad.PaddingBottom = UDim.new(0,12)
	pad.PaddingLeft = UDim.new(0,14); pad.PaddingRight = UDim.new(0,14); pad.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = Color3.fromRGB(35, 35, 35)
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = frame
	local sizer = Instance.new("UITextSizeConstraint"); sizer.MaxTextSize = 22; sizer.Parent = label

	if footer then
		local hint = Instance.new("TextLabel")
		hint.Size = UDim2.fromScale(1, 0.2)
		hint.Position = UDim2.fromScale(0, 0.8)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.FredokaOne
		hint.Text = footer
		hint.TextColor3 = Color3.fromRGB(130, 130, 130)
		hint.TextScaled = true
		hint.Parent = frame
		local hsizer = Instance.new("UITextSizeConstraint"); hsizer.MaxTextSize = 14; hsizer.Parent = hint
	end

	bb.Parent = adornee
	setNameVisible(adornee, false) -- talking now: get the name out from under the bubble

	if not persist then
		task.delay(SPEECH_LIFETIME, function()
			-- guard so a NEWER bubble that replaced ours isn't destroyed
			if bb and bb.Parent == adornee and bb.Name == "SpeechBubble" then
				bb:Destroy()
				setNameVisible(adornee, true)
			end
		end)
	end
end

-- ============================================================================================
-- 2) PROMPT + the paging engine  (doc 3 / 4)
-- ============================================================================================

-- Prompts are CREATED if missing, never found-only: a rig placed in Studio without one would
-- silently never grant its quest, with nothing in the log to say why.
local function addPrompt(part, actionText, objectText)
	local prompt = part:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then prompt = Instance.new("ProximityPrompt") end
	prompt.ActionText = actionText              -- "Talk"
	prompt.ObjectText = objectText              -- "Quest"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = DIALOGUE_CLOSE_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

local function wireDialogue(prompt, adornee, getPages, onTalk)
	-- the prompt shows in exactly the range the conversation stays open, so there's no band where
	-- it opens then instantly closes
	prompt.MaxActivationDistance = DIALOGUE_CLOSE_DISTANCE

	local pages = nil
	local index = 0
	local watching = false

	local function closeDialogue()
		hideSpeech(adornee)
		prompt.ActionText = "Talk"
		index = 0
		pages = nil
	end

	local function playerInRange()
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			-- type-check: a recursive name match can hit a Pose called "HumanoidRootPart" with no .Position
			if hrp and hrp:IsA("BasePart")
				and (hrp.Position - adornee.Position).Magnitude <= DIALOGUE_CLOSE_DISTANCE then
				return true
			end
		end
		return false
	end

	-- while a conversation is open, close it the moment the player walks off
	local function startWatcher()
		if watching then return end
		watching = true
		task.spawn(function()
			while index ~= 0 do
				if not playerInRange() then closeDialogue(); break end
				task.wait(0.25)
			end
			watching = false
		end)
	end

	prompt.Triggered:Connect(function(player)
		if index == 0 then
			pages = getPages()  -- fetched FRESH on page 1 -> any live counters in the copy are current
		end
		index += 1
		if not pages or index > #pages then
			closeDialogue()
			return
		end
		-- ===== THE QUEST HANDOFF: page 2, so the player has to actually read a bit =====
		if index == 2 and onTalk and player then
			onTalk(player)
		end
		local last = index >= #pages
		local footer = last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages)
		showSpeech(adornee, pages[index], true, footer)
		prompt.ActionText = last and "Close" or "Continue"
		startWatcher()
	end)

	prompt.PromptHidden:Connect(function()
		if index ~= 0 then closeDialogue() end
	end)
end

-- ============================================================================================
-- 3) FINDING THINGS: the island, the marker, the ground
-- ============================================================================================

-- Islands are "Island_2_BrocolliBluff" (yes, the typo is in the place), so match a NORMALIZED
-- prefix with a digit guard -- otherwise "island1" also matches island 10..14.
local function normName(s) return (tostring(s):lower():gsub("[%s_%-%.]", "")) end
local function findIsland(n)
	local want = "island" .. n
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") then
			local nm = normName(m.Name)
			if nm:sub(1, #want) == want and not tonumber(nm:sub(#want + 1, #want + 1)) then return m end
		end
	end
	return nil
end

-- Marker search order (doc 5c), adapted. Returns the marker instance or nil.
--
-- "Quest" is the house convention for a hand-placed quest NPC: the SAME name on every quest island.
-- That only works because this search is ISLAND-SCOPED -- it is deliberately left out of the
-- Workspace-wide last resort below, or island 2's search would happily grab island 13's "Quest".
local function findMarker(island, n)
	local exact = { ("NPCSpot%d"):format(n), ("Island%dNPC"):format(n), ("NPC%d"):format(n) }
	-- 1. the quest NPC ON THAT ISLAND (recursive).
	--
	-- MATCH THE NAME NORMALISED, NEVER RAW. The models in this place are actually named "Quest " --
	-- with a TRAILING SPACE -- so FindFirstChild("Quest") missed every one of them, the island was
	-- treated as having no NPC, and a clone was built beside the real one. Studio names carry stray
	-- spaces, casing and underscores; compare through normName and none of that matters.
	if island then
		for _, d in ipairs(island:GetDescendants()) do
			if (d:IsA("Model") or d:IsA("BasePart")) and normName(d.Name) == "quest" then
				return d, "'Quest' on-island"
			end
		end
		for _, want in ipairs(exact) do
			local w = normName(want)
			for _, d in ipairs(island:GetDescendants()) do
				if (d:IsA("Model") or d:IsA("BasePart")) and normName(d.Name) == w then
					return d, "exact-on-island"
				end
			end
		end
		-- 2. anything on the island with "npc" in the name AND this island's number
		local loose
		for _, d in ipairs(island:GetDescendants()) do
			local nm = normName(d.Name)
			if nm:find("npc", 1, true) then
				if nm:find(tostring(n), 1, true) then return d, "npc+number-on-island" end
				loose = loose or d
			end
		end
		-- 3. any "npc" part on the island (warned: catches a stale number, e.g. a marker moved islands)
		if loose then return loose, "npc-on-island (NAME HAS NO/WRONG NUMBER)" end
	end
	-- 4. exact name anywhere in Workspace (last resort)
	for _, want in ipairs(exact) do
		local hit = Workspace:FindFirstChild(want, true)
		if hit then return hit, "exact-anywhere-in-Workspace" end
	end
	return nil, nil
end

local function markerPos(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then
		local ok, cf = pcall(function() return inst:GetPivot() end)
		if ok and cf then return cf.Position end
	end
	return nil
end

-- Ghost a marker so it never renders or blocks anything, but stays put for next time.
local function ghost(inst)
	if not inst then return end
	local function kill(p)
		if p:IsA("BasePart") then p.Transparency = 1; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false end
	end
	kill(inst)
	for _, d in ipairs(inst:GetDescendants()) do kill(d) end
end

-- Settle onto the ground. If a MARKER placed it and the ray lands more than GROUND_SNAP_LIMIT off,
-- the marker wins -- a non-queryable island mesh lets the ray punch clean through and would bury
-- the NPC hundreds of studs down.
local function groundY(pos, hadMarker, ignore)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore or {}
	local hit = Workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -260, 0), rp)
	if not hit then return pos.Y, "no ray hit (kept marker height)" end
	local y = hit.Position.Y
	if hadMarker and math.abs(y - pos.Y) > GROUND_SNAP_LIMIT then
		return pos.Y, ("ray landed %.0f studs off -> MARKER WINS"):format(y - pos.Y)
	end
	return y, "grounded"
end

-- ============================================================================================
-- 4) THE RIG: clone a template, or build a simple stand-in so the system works with nothing placed
-- ============================================================================================

local function findTemplate()
	for _, want in ipairs({ "IslandNPC", "NPCTemplate", "QuestNPC", "FarmerNPC", "Farmer" }) do
		local m = ServerStorage:FindFirstChild(want)
		if m and m:IsA("Model") and m:FindFirstChildWhichIsA("Humanoid") then return m, want end
	end
	for _, c in ipairs(ServerStorage:GetChildren()) do -- any rig at all
		if c:IsA("Model") and c:FindFirstChildWhichIsA("Humanoid") then return c, c.Name end
	end
	return nil, nil
end

-- Blocky stand-in: only used when ServerStorage has no rig, so a fresh place still gets working,
-- talkable NPCs instead of silence. Head is named "Head" so pickAdornee finds it.
local function buildStandIn(name, shirtColor)
	local m = Instance.new("Model"); m.Name = name
	local function part(pname, size, cf, col)
		local p = Instance.new("Part"); p.Name = pname; p.Size = size; p.CFrame = cf; p.Color = col
		p.Material = Enum.Material.SmoothPlastic; p.Anchored = true; p.CanCollide = false
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = m
		return p
	end
	local SKIN = Color3.fromRGB(240, 200, 160)
	local torso = part("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), shirtColor)
	m.PrimaryPart = torso
	part("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 4.7, 0), SKIN)
	part("LeftArm",  Vector3.new(0.6, 1.8, 0.6), CFrame.new(-1.3, 3, 0), SKIN)
	part("RightArm", Vector3.new(0.6, 1.8, 0.6), CFrame.new( 1.3, 3, 0), SKIN)
	part("LeftLeg",  Vector3.new(0.7, 2, 0.7), CFrame.new(-0.5, 1, 0), Color3.fromRGB(52, 70, 120))
	part("RightLeg", Vector3.new(0.7, 2, 0.7), CFrame.new( 0.5, 1, 0), Color3.fromRGB(52, 70, 120))
	for _, ex in ipairs({ -0.3, 0.3 }) do
		part("Eye", Vector3.new(0.18, 0.18, 0.1), CFrame.new(ex, 4.85, -0.62), Color3.fromRGB(20, 20, 20))
	end
	return m
end

-- Otherwise every clone is labelled "Dummy" with a health bar floating over the name tag.
local function clearAdornments(model)
	local hum = model:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum.DisplayName = ""
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayDistance = 0
		hum.NameDisplayDistance = 0
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "NameLabel" or d.Name == "SpeechBubble" or d:IsA("ProximityPrompt") then d:Destroy() end
	end
end

-- head part -> PrimaryPart -> biggest part by volume (doc 3)
local function pickAdornee(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower():find("head", 1, true) then return d end
	end
	if model.PrimaryPart then return model.PrimaryPart end
	local best, bestVol
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if not bestVol or v > bestVol then best, bestVol = d, v end
		end
	end
	return best
end

-- ============================================================================================
-- 5) PER-ISLAND DIALOGUE. Adding an island is ONE ROW -- the accept attribute is derived from the
-- number ("Island7QuestAccepted"), so there is no registry to keep in sync.
-- Page 2 is where the quest is granted, so put the ASK on page 2 wherever you can.
-- ============================================================================================
local ISLAND_NPCS = {
	{ island = 1,  name = "Bean Buddy Bill", title = "The Bean Farmer", pages = {
		"Welcome to Bean Farm! Everything starts here.",
		"Buy beans at the stand, then HOLD the fart button to fly.",
		"Higher you go, more coins you make. Off you go!",
	}},
	{ island = 2,  quest = true,  name = "Sprout",          title = "The Grower", pages = {
		"Broccoli Bluff! Careful where you step.",
		"Three broccoli are planted around here. Pull them all up for me.",
		"They're rooted deep -- hold on and ease off before the stalk slips!",
		"Bring me all three and a Broccoli Bunny will hatch for you.",
	}},
	{ island = 3,  name = "Cabbage Kate",    title = "The Picker", pages = {
		"Cabbage Cliffs -- windy up here, isn't it?",
		"Cabbage is heavier fuel than broccoli. Stock up and climb.",
		"If you're running out of gas mid-flight, buy a bigger gut first.",
	}},
	{ island = 4,  name = "Turnip Ted",      title = "The Root Keeper", pages = {
		"Turnip Tranquil. Quietest island on the stack.",
		"Turnips burn long and slow -- perfect for the next big climb.",
		"Don't skip the gut upgrades. Food's no good with nowhere to put it.",
	}},
	{ island = 5,  quest = true,  name = "Coco",            title = "The Beachcomber", pages = {
		"Coconut Cove! Mind the crabs.",
		"Seven coconuts are scattered about. Crack every one of them.",
		"Crack all seven and you've earned the Cave Key.",
		"The key opens the chest in the cave -- there's a Coconut Crab inside.",
	}},
	{ island = 6,  name = "Baker Bram",      title = "The Baker", pages = {
		"Bread Board! Smell that?",
		"Bread is the densest fuel yet. One loaf goes a long way.",
		"Keep climbing -- the good stuff is still above us.",
	}},
	{ island = 7,  name = "Nonna",           title = "The Cook", pages = {
		"Pasta Peak! Sit, eat, you're too skinny.",
		"Pasta will carry you higher than anything below us.",
		"And watch out for the meatball shooter. It has a mind of its own.",
	}},
	{ island = 8,  quest = true,  name = "Reel",            title = "The Projectionist", pages = {
		"Popcorn Pinnacle -- and my film is in pieces!",
		"Six film reels are scattered across the island. Find every one.",
		"Each is jammed tight -- work the pins loose to free it.",
		"Load them into the projector and see what the movie hatches...",
	}},
	{ island = 9,  name = "Milkman Moe",     title = "The Dairyman", pages = {
		"Milk Marsh. Watch your footing, it's soggy.",
		"Milk is proper rocket fuel. Fill up before you climb.",
		"If the milk cap blows, stand back and enjoy the show.",
	}},
	{ island = 10, quest = true,  name = "Butters",         title = "The Angler", pages = {
		"Butter Swamp! Best fishing on the whole stack.",
		"Grab a rod from the barrel and fish the butter lake.",
		"Hook something and it'll fight you -- keep the fish in the slider.",
		"Land the right catch and a Butter Duck is yours.",
	}},
	{ island = 11, name = "Scoop",           title = "The Scooper", pages = {
		"Ice Cream Isle! Careful, it's slippery.",
		"Ice cream is the coldest, strongest fuel down this far.",
		"Three islands to go. You're nearly at the top!",
	}},
	{ island = 12, name = "Patty",           title = "The Grillmaster", pages = {
		"Burger Bluff! Grill's always on.",
		"Burgers are heavy fuel -- you'll need the gut to match.",
		"And don't stand on the condiment geysers. Trust me.",
	}},
	{ island = 13, quest = true,  name = "Dusty",           title = "The Digger", pages = {
		"Burrito Barrens. Nothing out here but dirt and secrets.",
		"Grab a shovel from the barrel and dig the mounds along the trail.",
		"Most are junk. One of them isn't -- follow the tracks.",
		"Dig up the buried egg and a Burrito Armadillo comes home with you.",
	}},
	{ island = 14, name = "Pepper",          title = "The Pizzaiolo", pages = {
		"Pizza Palms -- the top of the world!",
		"Pizza is the strongest fuel there is. Nothing above us but sky.",
		"...well. Almost nothing. See that rift up there?",
		"Fly into it if you're brave. It goes somewhere else entirely.",
	}},
}

-- ============================================================================================
-- 6) BUILD + PLACE
-- ============================================================================================
local container = Workspace:FindFirstChild("IslandNPCs")
if not container then
	container = Instance.new("Folder"); container.Name = "IslandNPCs"; container.Parent = Workspace
end
container:ClearAllChildren() -- re-runs must not stack rigs

local SHIRT = { -- stand-in shirt colours, roughly themed per island
	Color3.fromRGB(196,150,90),  Color3.fromRGB(96,170,84),   Color3.fromRGB(120,190,120),
	Color3.fromRGB(190,150,200), Color3.fromRGB(140,100,60),  Color3.fromRGB(214,178,120),
	Color3.fromRGB(230,190,140), Color3.fromRGB(245,235,205), Color3.fromRGB(235,235,245),
	Color3.fromRGB(240,215,110), Color3.fromRGB(210,230,245), Color3.fromRGB(180,110,70),
	Color3.fromRGB(200,150,90),  Color3.fromRGB(220,90,70),
}

local function setupIslandNPC(spec, template)
	local n = spec.island
	local island = findIsland(n)
	if not island then
		warn(("[IslandNPC] island %d model NOT FOUND in Workspace -- skipping %s"):format(n, spec.name))
		return
	end

	-- WHERE. NO MARKER = NO NPC.
	--
	-- This used to fall back to the island's stand and build a stand-in there. That is what produced
	-- the "random copy" standing next to a hand-placed NPC whenever the name lookup missed, and it
	-- also dropped nameless NPCs on the nine islands that were never meant to have one. Building a
	-- character nobody asked for is always the wrong call: warn, and leave the island alone.
	local marker, how = findMarker(island, n)
	local pos = markerPos(marker)
	if not pos then
		warn(("[IslandNPC] island %d: no 'Quest' NPC found -- skipping %s. Place a model named 'Quest' on the island to give it one."):format(n, spec.name))
		return
	end
	local hadMarker = true
	if how and how:find("NAME HAS NO/WRONG NUMBER") then
		warn(("[IslandNPC] island %d marker '%s' has no/wrong island number in its name -- using it anyway"):format(n, marker.Name))
	end

	-- WHO. A MODEL we found IS the NPC -- we adopt it where it stands and never build a second one.
	--
	-- This used to require a Humanoid to count as a rig, and anything else was ghosted and had a
	-- clone dropped on top of it. That is what produced the duplicate standing next to the placed
	-- "Quest" NPC: a hand-built model with no Humanoid was treated as a marker, so the real NPC was
	-- turned invisible and a second, differently-named one (Sprout / Coco / Reel...) appeared beside
	-- it. A model is a model. Only a bare PART is a marker.
	local model, adopted = nil, false
	if marker and marker:IsA("Model") then
		model, adopted = marker, true
	else
		ghost(marker)
		model = template and template:Clone() or buildStandIn(spec.name, SHIRT[n] or Color3.fromRGB(120,160,220))
		model.Name = spec.name
	end
	clearAdornments(model)
	-- ANCHOR THE ROOT ONLY -- NEVER EVERY PART.
	--
	-- These are talkers, not walkers, so the root is pinned. But anchoring EVERY part is what stopped
	-- them waving: an anchored part ignores its Motor6D, so GardenerWave could rotate the shoulder all
	-- it liked and the arm never moved. Pin the root, leave the limbs jointed, and the rig is both
	-- immovable and still animatable.
	local pinned = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = (pinned == nil) or (d == pinned) end
	end
	local hum0 = model:FindFirstChildOfClass("Humanoid")
	if hum0 then hum0.AutoRotate = false end -- with a free rig the Humanoid would spin it back

	local finalPos, why
	if adopted then
		-- leave an adopted rig exactly where it was placed, and leave it parented where it is: moving
		-- it into the folder would change its pivot and undo whatever posing was done in Studio.
		finalPos, why = pos, "adopted in place (hand-placed rig)"
	else
		model.Parent = container -- NEVER inside the island model (see the header)
		-- settle onto the ground, then lift so the pivot's feet sit on the surface
		local gy; gy, why = groundY(pos, hadMarker, { model, container })
		local _, size = model:GetBoundingBox()
		finalPos = Vector3.new(pos.X, gy + size.Y * 0.5, pos.Z)
		model:PivotTo(CFrame.new(finalPos))
	end

	-- ADORN + WIRE
	local adornee = pickAdornee(model)
	if not adornee then
		warn(("[IslandNPC] %s has no BasePart to adorn -- destroying"):format(spec.name))
		model:Destroy(); return
	end
	-- The client movement kit (NpcLife) adopts on this attribute, and NpcGuideArrow points the
	-- chevron trail at it -- both by attribute rather than by name, so renaming an NPC in Studio
	-- can never quietly unhook it from either.
	model:SetAttribute("QuestNpc", true)
	-- The floating tag reads "Quest" on EVERY island, matching the prompt's ObjectText -- one
	-- consistent word for "this is the person with the quest". The per-island character name
	-- (Sprout, Coco, Dusty...) still drives the dialogue voice and the server logs.
	makeNameLabel(adornee, "Quest")

	-- THE PROMPT GOES ON THE HumanoidRootPart, not the head: it's the rig's true centre, so the
	-- 10-stud radius is measured from where the NPC actually stands rather than from a head that
	-- may be offset or missing entirely on a hand-built model.
	local promptHost = model:FindFirstChild("HumanoidRootPart")
	if not (promptHost and promptHost:IsA("BasePart")) then promptHost = adornee end
	local prompt = addPrompt(promptHost, "Talk", "Quest")

	-- THE ACCEPT ATTRIBUTE, derived from the island number -- no registry to keep in sync.
	local acceptAttr = ("Island%dQuestAccepted"):format(n)
	wireDialogue(prompt, adornee, function() return spec.pages end, function(plr)
		if plr:GetAttribute(acceptAttr) then return end
		plr:SetAttribute(acceptAttr, true)
		print(("[IslandNPC] %s talked to %s on island %d -> %s = true"):format(plr.Name, spec.name, n, acceptAttr))
	end)

	print(("[IslandNPC] island %d%s: %s (%s) at (%.0f, %.0f, %.0f) [%s; %s] -> %s")
		:format(n, spec.quest and " [QUEST ISLAND]" or "", spec.name, spec.title,
			finalPos.X, finalPos.Y, finalPos.Z, how or "?", why, acceptAttr))
end

task.spawn(function()
	-- CRITICAL: PlayerStats repositions every island at runtime. Placing before StandsReady puts
	-- every NPC at the pre-move coordinates (island 2 would land ~740 studs below its island).
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < STANDS_READY_TIMEOUT do
		task.wait(0.5); waited += 0.5
	end
	if Workspace:GetAttribute("StandsReady") then
		print(("[IslandNPC] StandsReady after %.1fs -- islands are positioned, placing NPCs"):format(waited))
	else
		warn("[IslandNPC] StandsReady never set -- placing anyway, positions may be pre-move")
	end

	-- SWEEP OUT OLD CLONES. An earlier build treated a Humanoid-less "Quest" model as a marker and
	-- spawned a second, differently-named NPC beside it. Those clones live on in a place that was
	-- saved while they existed, so remove any model bearing one of our spec names that ISN'T the
	-- island's actual "Quest" NPC. Scoped to the spec names so nothing else in Workspace is touched.
	local specName = {}
	for _, s in ipairs(ISLAND_NPCS) do specName[s.name] = true end
	local swept = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and specName[d.Name] and d.Name ~= "Quest" then
			d:Destroy(); swept += 1
		end
	end
	if swept > 0 then
		print(("[IslandNPC] swept %d leftover duplicate NPC clone(s) from a previous build"):format(swept))
	end

	local template, tname = findTemplate()
	if template then
		print(("[IslandNPC] using ServerStorage rig '%s' as the NPC template"):format(tname))
	else
		warn("[IslandNPC] no rig (a Model with a Humanoid) in ServerStorage -- building simple stand-in NPCs. "
			.. "Drop a character model into ServerStorage named 'IslandNPC' to use your own art.")
	end

	for _, spec in ipairs(ISLAND_NPCS) do
		local ok, err = pcall(setupIslandNPC, spec, template)
		if not ok then warn(("[IslandNPC] island %d (%s) FAILED: %s"):format(spec.island, spec.name, tostring(err))) end
	end
	print(("[IslandNPC] ready -- %d island NPCs; talking to one sets Island<N>QuestAccepted on the player"):format(#ISLAND_NPCS))
end)
